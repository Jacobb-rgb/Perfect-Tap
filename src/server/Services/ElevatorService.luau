--[[
	ElevatorService: the mine elevator (docs/plans/MINE_STEP_PLAN.md, WP Elevator).

	Owner's rules: the elevator is bought ONCE with coins
	(MineFloors.Elevator.Price, saved as data.Upgrades.Elevator) and then rides
	to any unlocked floor. Floors 1-3 can also be walked; floors 4-5 are
	reachable only by elevator. A floor is unlocked when the player's blaster
	level (data.BlasterLevel) is at least its MinBlaster.

	- Stops: every Model tagged "MineElevator" (MineKit.elevator: attribute
	  Floor, a "Base" plate whose front is -Z, a "CallPanel" part with an
	  Attachment "PromptPoint"), also the ones added later. Each gets one
	  ProximityPrompt "ElevatorPrompt" (Object "Elevator", Action "Use"; the
	  client turns the action into "Buy $500K" while the player doesn't own it).
	  F / gamepad Y / tap. Triggering it opens the client's view:
	  OpenUI "Elevator" { Stop, Floor, Owned }. This prompt is the only way in
	  (owner 2026-10-18): the HUD's elevator button teleports you to a stop
	  first (TeleportService "Elevator").
	- ElevatorAction (Net, rate limited), only within Range studs of a stop:
	    { Action = "Buy" }           spends the price (EconomyService), sets
	                                 Upgrades.Elevator, saves, Notify
	    { Action = "Go", Floor = n } owned, whole n in 1..#MineFloors.List,
	                                 unlocked, a living character, not in a
	                                 running cleaning session, at a stop but not
	                                 that stop's own floor, not within Cooldown
	                                 of the last ride. Then the ride:
	                                 ElevatorRide "Depart" { Floor, From, Name,
	                                 Duration, DoorsClose } starts the client's
	                                 full-screen ride (doors slam shut, floor
	                                 counter, ding, doors open); DoorsClose
	                                 seconds later (the doors are shut by then)
	                                 the area round the target is streamed in
	                                 (StreamTimeout), the character moves to the
	                                 target stop (on its plate in front of the
	                                 cage, facing out) and ElevatorRide "Arrive"
	                                 lets the client open the doors (after at
	                                 least Duration seconds of ride).
	  Refusals answer with a "Deny" Notify (bad input is ignored silently).
	  Buying never yields between the coin check and the flag, so a double tap
	  buys once.
	- Target of a floor: its elevator stop, else the "Entrance" marker part of
	  the floor model "MineFloor<N>" under Workspace.Map.
	- Void catcher: parts tagged "VoidCatcher" (attribute Floor) under floor
	  5's floating islands. A character's HumanoidRootPart touching one (or
	  found inside / below it by a 0.5 s check over the players, in case a
	  fast fall skips the touch) goes back to that floor's target, at most once
	  per CatchDebounce seconds.
	- State: snapshot.ElevatorOwned.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local MineFloors = require(Shared.Config.MineFloors)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EconomyService = require(script.Parent.EconomyService)

local ElevatorService = {}

export type Reason =
	"Ok"
	| "NoData"
	| "BadAction"
	| "BadFloor"
	| "Owned"
	| "NoCoins"
	| "NotOwned"
	| "Locked"
	| "NoCharacter"
	| "Cleaning"
	| "TooFar"
	| "Here"
	| "Cooldown"
	| "NoStop"

ElevatorService.Tag = "MineElevator"
ElevatorService.CatcherTag = "VoidCatcher"
ElevatorService.PromptName = "ElevatorPrompt"
-- studs from a stop's Base plate: its prompt opens the view within this, and a
-- rider standing this close can't pick the stop's own floor (the prompt reaches less)
ElevatorService.Range = 16
ElevatorService.PromptDistance = 10
-- seconds between two rides of one player
ElevatorService.Cooldown = 3
-- seconds from "Depart" until the character moves: the client's doors are shut by then
-- (ElevatorRideView closes them in DoorsClose - 0.05 at most)
ElevatorService.DoorsClose = 0.5
-- the client's ride lasts at least RideTime + RidePerFloor per floor travelled (at most RideMax)
-- before the doors open again; about 2.5-3 s with the doors
ElevatorService.RideTime = 1.9
ElevatorService.RidePerFloor = 0.15
ElevatorService.RideMax = 2.5
-- seconds the server waits at most for the target area to stream in
ElevatorService.StreamTimeout = 3
-- seconds between two void rescues of one player
ElevatorService.CatchDebounce = 2
-- the arrival point from a stop's floor center (MineKit.elevator: the cage spans
-- z -2.8..3.2 and the plate reaches z -4.8): on the plate in front of the cage, at
-- HumanoidRootPart height
ElevatorService.ArrivalOffset = CFrame.new(0, 3.6, -3.9)
-- root height above an Entrance marker (a 1-stud part on the ground)
ElevatorService.EntranceLift = 3
-- a VoidCatcher also catches roots this far below its bottom (inside its X/Z box)
ElevatorService.CatchDepth = 200

local CATCH_CHECK = 0.5

local stops: { Model } = {}
local catchers: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastRide: { [Player]: number } = {}
local riding: { [Player]: boolean } = {}
local lastCatch: { [Player]: number } = {}
local clock: () -> number = os.clock
local mapOverride: Instance? = nil

---------------------------------------------------------------- rules

-- True when the save says the player owns the elevator.
function ElevatorService.owns(data: { [string]: any }): boolean
	local upgrades = data.Upgrades
	return type(upgrades) == "table" and upgrades.Elevator == true
end

-- The player's blaster level as the game reads it (1..BlasterData.MaxLevel).
function ElevatorService.blasterLevel(data: { [string]: any }): number
	return BlasterData.get(data.BlasterLevel).Level
end

-- True when a blaster of `level` may ride to floor `floorIndex` (an index of MineFloors.List).
function ElevatorService.isUnlocked(level: number, floorIndex: number): boolean
	local floor = MineFloors.ByIndex[floorIndex]
	return floor ~= nil and level >= floor.MinBlaster
end

---------------------------------------------------------------- stops

local function stopBase(model: Model): BasePart?
	local base = model:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base
	end
	return model.PrimaryPart
end

-- The floor a stop serves (its Floor attribute), nil when missing or junk.
function ElevatorService.floorOf(model: Model): number?
	return Guard.integer(model:GetAttribute("Floor"), 1, 999)
end

-- The stop's floor center: the bottom of its Base plate (front = LookVector).
function ElevatorService.stopCFrame(model: Model): CFrame?
	local base = stopBase(model)
	if not base then
		return nil
	end
	return base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
end

-- A turn about Y only, looking along `look` (flattened); -Z when `look` is vertical.
local function facing(position: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- Where a rider arrives at a stop: on its plate in front of the cage, facing out.
function ElevatorService.arrivalCFrame(model: Model): CFrame?
	local cf = ElevatorService.stopCFrame(model)
	if not cf then
		return nil
	end
	return facing((cf * ElevatorService.ArrivalOffset).Position, cf.LookVector)
end

-- Distance from a point to the surface of a part's box (0 inside).
local function distanceToPart(part: BasePart, position: Vector3): number
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceToStop(model: Model, position: Vector3): number
	local base = stopBase(model)
	return if base then distanceToPart(base, position) else math.huge
end

-- The stop the player stands at (the nearest within `range`), or nil.
function ElevatorService.stopNear(player: Player, range: number): Model?
	local root = Guard.rootPart(player)
	if not root then
		return nil
	end
	local best: Model? = nil
	local bestDistance = math.huge
	for _, model in stops do
		if model.Parent then
			local distance = distanceToStop(model, root.Position)
			if distance <= range and distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- The elevator stop of a floor, or nil.
function ElevatorService.stopFor(floorIndex: number): Model?
	for _, model in stops do
		if model.Parent and ElevatorService.floorOf(model) == floorIndex then
			return model
		end
	end
	return nil
end

local function mapRoot(): Instance?
	return mapOverride or Workspace:FindFirstChild("Map")
end

-- The "Entrance" marker of the floor model MineFloor<N> under Workspace.Map, or nil.
function ElevatorService.entranceFor(floorIndex: number): BasePart?
	local map = mapRoot()
	local floorModel = map and map:FindFirstChild("MineFloor" .. floorIndex, true)
	if not floorModel then
		return nil
	end
	local entrance = floorModel:FindFirstChild("Entrance") or floorModel:FindFirstChild("Entrance", true)
	if entrance and entrance:IsA("BasePart") then
		return entrance
	end
	return nil
end

-- Where a ride to (or a rescue on) a floor puts the character: the floor's stop,
-- else its Entrance marker; nil when the floor has neither.
function ElevatorService.targetFor(floorIndex: number): CFrame?
	local stop = ElevatorService.stopFor(floorIndex)
	local arrival = stop and ElevatorService.arrivalCFrame(stop)
	if arrival then
		return arrival
	end
	local entrance = ElevatorService.entranceFor(floorIndex)
	if entrance then
		local cf = entrance.CFrame
		return facing(cf.Position + Vector3.new(0, ElevatorService.EntranceLift, 0), cf.LookVector)
	end
	return nil
end

---------------------------------------------------------------- moving characters

-- Moves the player's (living) character so its root stands at `target`.
local function teleport(player: Player, target: CFrame): boolean
	local root = Guard.rootPart(player)
	local character = player.Character
	if not root or not character then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(target)
	return true
end

-- Is the player in the middle of the cleaning minigame? (CleaningService is loaded
-- on first use, like TeleportService does: it needs the whole game around it)
function ElevatorService.isCleaning(player: Player): boolean
	local CleaningService = require(script.Parent.CleaningService) :: any
	return CleaningService.inSession(player) == true
end

local function deny(player: Player, text: string)
	Net.fire("Notify", player, { Text = text, Kind = "Deny" })
	-- the view may be out of date: send a fresh snapshot
	StateService.push(player)
end

-- Seconds of ride (doors shut) the client shows from one floor to another.
function ElevatorService.rideTime(from: number?, to: number): number
	local floors = if from then math.abs(to - from) else 1
	return math.min(ElevatorService.RideMax, ElevatorService.RideTime + ElevatorService.RidePerFloor * floors)
end

local function ride(player: Player, from: number?, floorIndex: number, target: CFrame)
	local floor = MineFloors.ByIndex[floorIndex]
	riding[player] = true
	Net.fire("ElevatorRide", player, {
		Phase = "Depart",
		Floor = floorIndex,
		From = from,
		Name = floor.Name,
		Duration = ElevatorService.rideTime(from, floorIndex),
		DoorsClose = ElevatorService.DoorsClose,
	})
	task.spawn(function()
		-- only behind closed doors
		if ElevatorService.DoorsClose > 0 then
			task.wait(ElevatorService.DoorsClose)
		end
		-- StreamingEnabled: load the target area first so the rider never falls through it
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, ElevatorService.StreamTimeout)
		end)
		local ok, arrived = false, false
		if player.Parent then
			ok, arrived = pcall(teleport, player, target)
		end
		-- always free the rider, even when the move failed
		riding[player] = nil
		if player.Parent then
			Net.fire("ElevatorRide", player, { Phase = "Arrive", Floor = floorIndex, Name = floor.Name, Ok = ok and arrived == true })
		end
	end)
end

---------------------------------------------------------------- requests

local function buy(player: Player, data: { [string]: any }): (boolean, Reason)
	if ElevatorService.owns(data) then
		deny(player, "You already own the Elevator.")
		return false, "Owned"
	end
	if not ElevatorService.stopNear(player, ElevatorService.Range) then
		deny(player, "Walk up to an elevator to buy it.")
		return false, "TooFar"
	end
	local price = MineFloors.Elevator.Price
	local upgrades = data.Upgrades
	if type(upgrades) ~= "table" then
		upgrades = {}
		data.Upgrades = upgrades
	end
	-- no yield from the coin check to the flag: a double tap buys once
	if not EconomyService.spend(player, price, "Elevator") then
		local missing = price - EconomyService.balance(player)
		deny(player, `The Elevator costs {Format.money(price)}. You need {Format.money(math.max(missing, 1))} more.`)
		return false, "NoCoins"
	end
	upgrades.Elevator = true
	DataService.changed(player)
	Net.fire("Notify", player, { Text = "Elevator bought! Ride to every floor you have unlocked.", Kind = "Reward" })
	return true, "Ok"
end

local function go(player: Player, data: { [string]: any }, args: { [any]: any }): (boolean, Reason)
	local floorIndex = Guard.integer(args.Floor, 1, #MineFloors.List)
	if not floorIndex then
		return false, "BadFloor"
	end
	if not ElevatorService.owns(data) then
		deny(player, `Buy the Elevator first ({Format.money(MineFloors.Elevator.Price)}).`)
		return false, "NotOwned"
	end
	local floor = MineFloors.ByIndex[floorIndex]
	if not ElevatorService.isUnlocked(ElevatorService.blasterLevel(data), floorIndex) then
		deny(player, `{floor.Name} needs Blaster {floor.MinBlaster}+.`)
		return false, "Locked"
	end
	if not Guard.rootPart(player) then
		return false, "NoCharacter"
	end
	if ElevatorService.isCleaning(player) then
		deny(player, "Finish cleaning first.")
		return false, "Cleaning"
	end
	local here = ElevatorService.stopNear(player, ElevatorService.Range)
	if not here then
		deny(player, "Walk up to an elevator to ride it.")
		return false, "TooFar"
	end
	if ElevatorService.floorOf(here) == floorIndex then
		deny(player, `You're already on Floor {floorIndex}.`)
		return false, "Here"
	end
	local now = clock()
	local last = lastRide[player]
	if riding[player] or (last and now - last < ElevatorService.Cooldown) then
		return false, "Cooldown"
	end
	local target = ElevatorService.targetFor(floorIndex)
	if not target then
		deny(player, `{floor.Name} isn't open yet.`)
		return false, "NoStop"
	end
	lastRide[player] = now
	ride(player, ElevatorService.floorOf(here), floorIndex, target)
	return true, "Ok"
end

local function onAction(player: Player, arg: any): (boolean, Reason)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	local args = Guard.table(arg, 4)
	if not args then
		return false, "BadAction"
	end
	if args.Action == "Buy" then
		return buy(player, data)
	elseif args.Action == "Go" then
		return go(player, data, args)
	end
	return false, "BadAction"
end

---------------------------------------------------------------- void catcher

-- The floor a catcher rescues to: its Floor attribute, else the floor of the nearest stop.
local function catcherFloor(part: BasePart): number?
	local floorIndex = Guard.integer(part:GetAttribute("Floor"), 1, #MineFloors.List)
	if floorIndex then
		return floorIndex
	end
	local best: number? = nil
	local bestDistance = math.huge
	for _, model in stops do
		local base = model.Parent and stopBase(model)
		if base then
			local distance = (base.CFrame.Position - part.CFrame.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = ElevatorService.floorOf(model), distance
			end
		end
	end
	return best
end

-- True when `position` is inside a catcher's box or below it (within CatchDepth).
function ElevatorService.isCaught(part: BasePart, position: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y <= half.Y and p.Y >= -half.Y - ElevatorService.CatchDepth
end

-- Puts a fallen player back on the catcher's floor (debounced). True when moved.
function ElevatorService.rescue(player: Player, part: BasePart): boolean
	local now = clock()
	local last = lastCatch[player]
	if last and now - last < ElevatorService.CatchDebounce then
		return false
	end
	local floorIndex = catcherFloor(part)
	local target = floorIndex and ElevatorService.targetFor(floorIndex)
	if not floorIndex or not target then
		return false
	end
	lastCatch[player] = now
	if not teleport(player, target) then
		return false
	end
	local floor = MineFloors.ByIndex[floorIndex]
	Net.fire("ElevatorRide", player, { Phase = "Arrive", Floor = floorIndex, Name = floor.Name, Rescue = true })
	return true
end

local function checkCatchers()
	if #catchers == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = Guard.rootPart(player)
		if root then
			for _, part in catchers do
				if part.Parent and ElevatorService.isCaught(part, root.Position) then
					ElevatorService.rescue(player, part)
					break
				end
			end
		end
	end
end

---------------------------------------------------------------- hooks

local function openView(player: Player, model: Model)
	local data = DataService.get(player)
	local root = Guard.rootPart(player)
	if not data or not root or distanceToStop(model, root.Position) > ElevatorService.Range then
		return
	end
	Net.fire("OpenUI", player, "Elevator", {
		Stop = model,
		Floor = ElevatorService.floorOf(model),
		Owned = ElevatorService.owns(data),
	})
end

local function hookStop(instance: Instance)
	if hooked[instance] or not instance:IsA("Model") then
		return
	end
	local model = instance :: Model
	local panel = model:FindFirstChild("CallPanel")
	local point = panel and panel:FindFirstChild("PromptPoint")
	local parent: Instance? = if point and point:IsA("Attachment")
		then point
		elseif panel and panel:IsA("BasePart") then panel
		else stopBase(model)
	if not parent then
		warn("[ElevatorService] an elevator stop has no CallPanel or Base: " .. model:GetFullName())
		return
	end
	hooked[instance] = true
	table.insert(stops, model)
	-- a stop streamed or rebuilt in comes back with one prompt, never two
	local old = parent:FindFirstChild(ElevatorService.PromptName)
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = ElevatorService.PromptName
	prompt.ObjectText = "Elevator"
	prompt.ActionText = "Use"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ElevatorService.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	prompt.Triggered:Connect(function(player: Player)
		openView(player, model)
	end)
end

local function unhookStop(instance: Instance)
	local index = table.find(stops, instance :: any)
	if index then
		table.remove(stops, index)
	end
	hooked[instance] = nil
end

local function onCatcherTouched(part: BasePart, hit: BasePart)
	if hit.Name ~= "HumanoidRootPart" then
		return
	end
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		ElevatorService.rescue(player, part)
	end
end

local function hookCatcher(instance: Instance)
	if hooked[instance] or not instance:IsA("BasePart") then
		return
	end
	hooked[instance] = true
	local part = instance :: BasePart
	table.insert(catchers, part)
	part.CanTouch = true
	part.Touched:Connect(function(hit: BasePart)
		onCatcherTouched(part, hit)
	end)
end

local function unhookCatcher(instance: Instance)
	local index = table.find(catchers, instance :: any)
	if index then
		table.remove(catchers, index)
	end
	hooked[instance] = nil
end

local function hookTagged(tag: string, hook: (Instance) -> (), unhook: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unhook)
	for _, instance in CollectionService:GetTagged(tag) do
		hook(instance)
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/ElevatorService.spec.luau).
ElevatorService._test = {
	action = onAction,
	hookStop = hookStop,
	hookCatcher = hookCatcher,
	touched = onCatcherTouched,
	open = openView,
	checkCatchers = checkCatchers,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setMap = function(map: Instance?)
		mapOverride = map
	end,
	reset = function()
		table.clear(stops)
		table.clear(catchers)
		table.clear(lastRide)
		table.clear(riding)
		table.clear(lastCatch)
		for instance in hooked do
			hooked[instance] = nil
		end
		clock = os.clock
		mapOverride = nil
	end,
}

function ElevatorService.init()
	Net.on("ElevatorAction", onAction)
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		snapshot.ElevatorOwned = ElevatorService.owns(data)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRide[player] = nil
		riding[player] = nil
		lastCatch[player] = nil
	end)
end

function ElevatorService.start()
	-- the map is built in WorldService.init, so the stops exist by now
	hookTagged(ElevatorService.Tag, hookStop, unhookStop)
	hookTagged(ElevatorService.CatcherTag, hookCatcher, unhookCatcher)
	while true do
		task.wait(CATCH_CHECK)
		checkCatchers()
	end
end

return ElevatorService
