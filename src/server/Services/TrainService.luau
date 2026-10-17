--[[
	TrainService: every player's own ore train (design v2,
	docs/plans/STEP2_PLAN.md; all numbers in TrainConfig).

	Saved in data.Train (DataTemplate, cleaned by Migrations): CapacityLevel,
	SpeedLevel, Cargo (items waiting at the station), TripCargo (items on the
	train) and TripDepartAt / TripArriveAt (os.time(), 0 = no trip). An item
	is always in exactly one place: in the world (loose or carried), Cargo,
	TripCargo or the Ore Pen (data.Storage). Every move takes it from one
	place and puts it into the next without a yield in between.

	- Intake: every BasePart tagged "TrainHopper" under Workspace.Map.Railway
	  (the Mine Station hopper and the Mine Lifts, World/Railway builds them;
	  hooks added later are picked up too) is an IntakeService zone. A loose
	  item that lands in one goes into its OWNER's cargo (nobody can load
	  another player's train) while the cargo has room and the train is at
	  the station; otherwise it bounces back out toward the prompts with a
	  throttled toast. Each hook gets two prompts at its "PromptPoint"
	  attachment (tag "TrainPrompt", attribute Action = "Load" | "Send"):
	  "Load Train" (F / gamepad Y) loads what you carry while there is room,
	  "Send Train" (G / gamepad B).
	- Departure: as soon as the cargo is full, on TrainAction "Send" (from
	  anywhere: it is harmless) or AutoDepartSeconds after the last load.
	  Cargo moves to TripCargo, the trip times are saved and every client gets
	  "TrainTrip" { UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load }
	  (times in workspace:GetServerTimeNow() seconds) and animates the trip.
	- Arrival (a 1 s loop): TripCargo goes into the Ore Pen up to its capacity
	  (ItemService.penCapacity). Leftovers wait on the train and are tried
	  again every DeliveryRetry seconds (one "pen full" toast per trip). Once
	  empty: trip times cleared, Stats.TrainTrips + 1, Fx "TrainUnload"
	  (plotId, count) to everyone, and the empty train rolls back for
	  ReturnSeconds before it can load again.
	- Joining: a trip that arrived while you were away is delivered at once
	  (no animation); a running one is announced again, and the joining
	  player gets the list of everyone else's trips.
	- Upgrades: TrainAction "Upgrade" { Kind = "Capacity" | "Speed" } buys
	  the next level (TrainConfig.nextPrice, EconomyService.spend). The
	  Express perk (Perks "TrainExpress") adds cargo and speed.
	- StateService gets Train = { Cargo, Capacity, Moving, DepartAt?,
	  ArriveAt?, CapacityLevel, SpeedLevel, NextCapacityPrice?,
	  NextSpeedPrice?, Express, TripSeconds, AutoDepartIn?, ReturnAt? }
	  (DepartAt / ArriveAt / ReturnAt in server-time seconds).
	Studio: Players.<you>:SetAttribute("Perk_TrainExpress", true) tries Express.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local TrainConfig = require(Shared.Config.TrainConfig)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)
local IntakeService = require(script.Parent.IntakeService)
local EconomyService = require(script.Parent.EconomyService)

local TrainService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord

-- What clients get in "TrainTrip" (one per departure, a list on join).
export type Trip = {
	UserId: number,
	PlotId: number,
	DepartAt: number, -- server time
	ArriveAt: number, -- server time
	Count: number,
	Color: Color3, -- the plot banner
	Load: { Color3 }, -- ore colors for the wagon (dirty ore stays dirt colored)
}

type Train = {
	CapacityLevel: number,
	SpeedLevel: number,
	Cargo: { Desc },
	TripCargo: { Desc },
	TripDepartAt: number,
	TripArriveAt: number,
}

-- A station hopper or a lift: its intake box and where its prompts are.
type Hook = {
	Part: BasePart,
	Name: string, -- "Mine Station" | "Mine Lift"
	LiftId: string?,
	Point: Vector3, -- the prompt point (world)
	Out: Vector3, -- flat unit vector out of the hopper, toward the prompts
}

-- Per-player state that is not saved.
type Runtime = {
	LastLoad: number?, -- clock() of the last load (auto departure)
	DepartAt: number?, -- server time of the trip on the move (what clients got)
	ArriveAt: number?,
	ReturnUntil: number?, -- clock() when the empty train is back at the station
	ReturnAt: number?, -- the same in server time
	NextRetry: number?, -- clock() of the next unloading try (pen full)
	PenToast: boolean, -- "pen full" was said on this trip
	Delivered: number, -- items unloaded on this trip so far
	Prepared: boolean, -- the join checks (onLoaded) have run
	Announced: boolean, -- the trip from the last session was announced
	Toasts: { [string]: number }, -- clock() of the last throttled toast per kind
}

TrainService.HookTag = "TrainHopper"
TrainService.PromptTag = "TrainPrompt"
TrainService.LoadRange = 14 -- studs from a hook's prompt point for "Load Train"
TrainService.FullText = "Your train is full – press Send"
TrainService.AwayText = "Your train is on its way"
TrainService.PenFullText = "Your Ore Pen is full – make room"
TrainService.EmptyText = "Your train is empty. Throw ore into the Mine Station hopper first."

local RANGE_SLACK = 4 -- the server allows a little more (lag, walking while pressing)
local TOAST_COOLDOWN = 5
local MAX_LOAD = 64 -- more than any carry stack
local MAX_LOAD_COLORS = 6
local MAP_WAIT = 60
local BOUNCE_GAP = 1.5 -- studs outside the hopper box where refused items come out
local OUT_SPEED = 8
local OUT_UP = 12
local DEFAULT_COLOR = Color3.fromRGB(240, 230, 210)

local clock: () -> number = os.time
local serverNow: () -> number = function(): number
	return Workspace:GetServerTimeNow()
end

local runtimes: { [Player]: Runtime } = {}
local hooks: { Hook } = {} -- a list: a handful of hooks, compared by instance
local perkConnections: { [Player]: RBXScriptConnection } = {}

---------------------------------------------------------------- state

local function runtimeOf(player: Player): Runtime
	local r = runtimes[player]
	if not r then
		r = { PenToast = false, Delivered = 0, Prepared = false, Announced = false, Toasts = {} }
		runtimes[player] = r
	end
	return r
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function wholeLevel(v: any, list: { TrainConfig.Level }): number
	return if finite(v) then math.clamp(math.floor(v), 0, TrainConfig.maxLevel(list)) else 0
end

-- data.Train in the right shape (repaired in place; Migrations does the deep clean on load).
local function trainOf(data: { [string]: any }): Train
	local train = data.Train
	if type(train) ~= "table" then
		train = {}
		data.Train = train
	end
	if type(train.Cargo) ~= "table" then
		train.Cargo = {}
	end
	if type(train.TripCargo) ~= "table" then
		train.TripCargo = {}
	end
	train.CapacityLevel = wholeLevel(train.CapacityLevel, TrainConfig.Capacity)
	train.SpeedLevel = wholeLevel(train.SpeedLevel, TrainConfig.Speed)
	for _, field in { "TripDepartAt", "TripArriveAt" } do
		local v = train[field]
		if not finite(v) or v < 0 then
			train[field] = 0
		end
	end
	return train :: Train
end

local function hasExpress(player: Player): boolean
	return Perks.has(player, "TrainExpress")
end

local function capacityOf(player: Player, train: Train): number
	return TrainConfig.capacity(train.CapacityLevel, hasExpress(player))
end

local function tripSecondsOf(player: Player, train: Train): number
	return TrainConfig.tripSeconds(train.SpeedLevel, hasExpress(player))
end

-- The empty train is still rolling back after unloading.
local function isReturning(player: Player): boolean
	local r = runtimes[player]
	local returnUntil = r and r.ReturnUntil
	return returnUntil ~= nil and clock() < returnUntil
end

-- Not at the station: on the move, waiting at your stop (pen full) or rolling back.
local function isAway(player: Player, train: Train): boolean
	return #train.TripCargo > 0 or train.TripArriveAt > 0 or isReturning(player)
end

-- How many more items fit into the cargo (capacity and the save cap).
local function cargoRoom(player: Player, train: Train): number
	local byCapacity = capacityOf(player, train) - #train.Cargo
	local bySave = TrainConfig.MaxCargoSaved - #train.Cargo - #train.TripCargo
	return math.max(0, math.min(byCapacity, bySave))
end

-- Server times of the trip on the move (worked out from the save once per session).
local function tripTimes(train: Train, r: Runtime): (number, number)
	local departAt, arriveAt = r.DepartAt, r.ArriveAt
	if departAt and arriveAt then
		return departAt, arriveAt
	end
	local now = clock()
	local server = serverNow()
	local depart = server - (now - train.TripDepartAt)
	local arrive = server + (train.TripArriveAt - now)
	r.DepartAt = depart
	r.ArriveAt = arrive
	return depart, arrive
end

---------------------------------------------------------------- toasts and looks

local function toast(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

-- At most one toast of this kind per TOAST_COOLDOWN seconds.
local function throttledToast(player: Player, key: string, text: string, kind: string?)
	local r = runtimeOf(player)
	local now = clock()
	local last = r.Toasts[key]
	if last and now >= last and now - last < TOAST_COOLDOWN then
		return
	end
	r.Toasts[key] = now
	toast(player, text, kind)
end

-- The plot's banner color (the train is painted in it).
function TrainService.bannerColor(plotId: number): Color3
	local model = PlotService.model(plotId)
	local banner = model and model:FindFirstChild("Banner")
	if banner and banner:IsA("BasePart") then
		return banner.Color
	end
	return DEFAULT_COLOR
end

-- What the wagon shows: the cargo's ore colors, most common first. Dirty ore
-- keeps its secret (one dirt color for every ore).
function TrainService.loadColors(items: { Desc }): { Color3 }
	local counts: { [string]: number } = {}
	local colors: { [string]: Color3 } = {}
	for _, item in items do
		local ore = if item.K ~= "Raw" then OreData.ById[item.O] else nil
		local key = if ore then item.O else "~Dirt"
		counts[key] = (counts[key] or 0) + 1
		colors[key] = if ore then ore.Color else ItemBuilder.DirtyCrust
	end
	local keys = {}
	for key in counts do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: string, b: string): boolean
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local list = {}
	for i = 1, math.min(#keys, MAX_LOAD_COLORS) do
		table.insert(list, colors[keys[i]])
	end
	return list
end

-- The "TrainTrip" payload of a player's trip (nil when nothing is on the move).
local function tripOf(player: Player, train: Train): Trip?
	local plotId = PlotService.plotOf(player)
	if not plotId or #train.TripCargo == 0 then
		return nil
	end
	local departAt, arriveAt = tripTimes(train, runtimeOf(player))
	return {
		UserId = player.UserId,
		PlotId = plotId,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		Count = #train.TripCargo,
		Color = TrainService.bannerColor(plotId),
		Load = TrainService.loadColors(train.TripCargo),
	}
end

---------------------------------------------------------------- departure and arrival

-- Sends the train off with everything in its cargo. Returns true when it left.
function TrainService.depart(player: Player): boolean
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId then
		return false
	end
	local train = trainOf(data)
	if #train.Cargo == 0 or isAway(player, train) then
		return false
	end
	-- no yield from here until the trip is saved
	for _, item in train.Cargo do
		table.insert(train.TripCargo, item)
	end
	train.Cargo = {}
	local seconds = tripSecondsOf(player, train)
	local now = clock()
	train.TripDepartAt = now
	train.TripArriveAt = now + seconds
	local r = runtimeOf(player)
	local server = serverNow()
	r.LastLoad = nil
	r.DepartAt = server
	r.ArriveAt = server + seconds
	r.ReturnUntil = nil
	r.ReturnAt = nil
	r.NextRetry = nil
	r.PenToast = false
	r.Delivered = 0
	r.Announced = true
	DataService.changed(player)
	local trip = tripOf(player, train)
	if trip then
		Net.fireAll("TrainTrip", trip)
	end
	return true
end

--[[
	Unloads an arrived train into the Ore Pen, up to the pen's capacity.
	What doesn't fit stays on the train and is tried again later. `animated`
	is false for trips that arrived while the player was away (no unload
	effect, no return trip).
]]
local function deliver(player: Player, data: { [string]: any }, animated: boolean)
	local train = trainOf(data)
	local storage = data.Storage
	if type(storage) ~= "table" then
		return
	end
	local r = runtimeOf(player)
	local capacity = ItemService.penCapacity(data)
	local moved = 0
	-- no yield between taking an item off the train and putting it into the pen
	while #train.TripCargo > 0 and #storage < capacity do
		local item = table.remove(train.TripCargo, 1) :: Desc
		table.insert(storage, { K = item.K, O = item.O, G = item.G, R = item.R })
		moved += 1
	end
	r.Delivered += moved
	local now = clock()
	if #train.TripCargo > 0 then
		r.NextRetry = now + TrainConfig.DeliveryRetry
		if not r.PenToast then
			r.PenToast = true
			toast(player, TrainService.PenFullText)
		end
		if moved > 0 then
			DataService.changed(player)
		end
		return
	end
	local count = r.Delivered
	train.TripDepartAt = 0
	train.TripArriveAt = 0
	local stats = data.Stats
	if type(stats) == "table" then
		stats.TrainTrips = (tonumber(stats.TrainTrips) or 0) + 1
	end
	r.DepartAt = nil
	r.ArriveAt = nil
	r.NextRetry = nil
	r.PenToast = false
	r.Delivered = 0
	if animated then
		r.ReturnUntil = now + TrainConfig.ReturnSeconds
		r.ReturnAt = serverNow() + TrainConfig.ReturnSeconds
		local plotId = PlotService.plotOf(player)
		if plotId and count > 0 then
			Net.fireAll("Fx", "TrainUnload", plotId, count)
		end
	elseif count > 0 then
		toast(player, `Your train brought {count} ore to your Ore Pen while you were away.`, "Info")
	end
	DataService.changed(player)
end

-- "Send": the train leaves now with what it has (TrainAction or the prompt).
function TrainService.send(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local train = trainOf(data)
	if isAway(player, train) then
		toast(player, TrainService.AwayText, "Info")
		return false
	end
	if #train.Cargo == 0 then
		toast(player, TrainService.EmptyText, "Info")
		return false
	end
	return TrainService.depart(player)
end

-- After items went into the cargo: remember the time, tell the HUD, leave when full.
local function afterLoad(player: Player, train: Train, position: Vector3)
	runtimeOf(player).LastLoad = clock()
	DataService.changed(player)
	Net.fire("Fx", player, "TrainLoad", position)
	if cargoRoom(player, train) <= 0 then
		TrainService.depart(player)
	end
end

---------------------------------------------------------------- intake and prompts

-- Pops a refused item out of a hopper, toward its prompts (out of the box).
local function bounceOut(hook: Hook, record: ItemRecord)
	local part = hook.Part
	local half = part.Size / 2
	local reach = math.sqrt(half.X * half.X + half.Z * half.Z) + BOUNCE_GAP
	local side = Vector3.new(-hook.Out.Z, 0, hook.Out.X) * ((math.random() - 0.5) * 2)
	local position = part.CFrame.Position + hook.Out * reach + side
	ItemService.release(record, CFrame.new(position), hook.Out * OUT_SPEED + Vector3.new(0, OUT_UP, 0))
end

--[[
	An item came to rest in (or flew into) a hopper. It goes into its owner's
	cargo while there is room and the train is at the station; everything
	else bounces back out.
]]
local function onIntake(hook: Hook, record: ItemRecord)
	if record.State ~= "Loose" then
		return
	end
	local owner = Players:GetPlayerByUserId(record.Owner)
	local data = if owner then DataService.get(owner) else nil
	if not owner or not data or not PlotService.plotOf(owner) then
		bounceOut(hook, record)
		return
	end
	local train = trainOf(data)
	local position = record.Body.CFrame.Position
	if isAway(owner, train) then
		bounceOut(hook, record)
		throttledToast(owner, "Away", TrainService.AwayText)
		Net.fire("Fx", owner, "Reject", position)
		return
	end
	if cargoRoom(owner, train) <= 0 then
		bounceOut(hook, record)
		throttledToast(owner, "Full", TrainService.FullText)
		Net.fire("Fx", owner, "Reject", position)
		return
	end
	-- no yield between taking it out of the world and loading it
	table.insert(train.Cargo, ItemService.absorb(record))
	afterLoad(owner, train, position)
end

local function isNear(player: Player, position: Vector3, range: number): boolean
	local root = Guard.rootPart(player)
	return root ~= nil and (root.Position - position).Magnitude <= range + RANGE_SLACK
end

-- "Load Train": everything you carry goes into your cargo while there is room.
local function loadFromHands(player: Player, hook: Hook)
	local data = DataService.get(player)
	if not data or not PlotService.plotOf(player) then
		return
	end
	if not isNear(player, hook.Point, TrainService.LoadRange) then
		return
	end
	local train = trainOf(data)
	if #CarryService.list(player) == 0 then
		toast(player, "Carry ore here to load your train.", "Info")
		return
	end
	if isAway(player, train) then
		toast(player, TrainService.AwayText)
		return
	end
	local loaded = 0
	for _ = 1, MAX_LOAD do
		if cargoRoom(player, train) <= 0 then
			break
		end
		local record = CarryService.takeTop(player, function(r: ItemRecord): boolean
			return r.Owner == player.UserId and r.State == "Carried"
		end)
		if not record then
			break
		end
		-- no yield between taking it off the stack and loading it
		table.insert(train.Cargo, ItemService.absorb(record))
		loaded += 1
	end
	if loaded > 0 then
		afterLoad(player, train, hook.Part.CFrame.Position)
	end
	if #CarryService.list(player) > 0 then
		toast(player, if isAway(player, train) then TrainService.AwayText else TrainService.FullText)
	end
end

local function makePrompt(
	parent: Instance,
	name: string,
	action: string,
	text: string,
	objectText: string,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	order: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = text
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt:SetAttribute("Action", action)
	prompt:AddTag(TrainService.PromptTag)
	prompt.Parent = parent
	return prompt
end

-- World position of an attachment (WorldPosition without needing the engine).
local function worldPoint(attachment: Attachment): Vector3
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return (parent.CFrame * attachment.CFrame).Position
	end
	return attachment.CFrame.Position
end

-- Intake zone and prompts for one hopper (once per part).
local function setupHook(part: BasePart): Hook
	for _, existing in hooks do
		if existing.Part == part then
			return existing
		end
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	local found = if model then model:FindFirstChild("PromptPoint", true) else nil
	local point = if found and found:IsA("Attachment") then found else nil
	local liftAttribute = part:GetAttribute("LiftId")
	local liftId = if type(liftAttribute) == "string" then liftAttribute else nil
	local name = if liftId then "Mine Lift" else "Mine Station"
	local center = part.CFrame.Position
	local position = if point then worldPoint(point) else center
	local offset = position - center
	local out = Vector3.new(offset.X, 0, offset.Z)
	if out.Magnitude < 0.5 then
		local look = part.CFrame.LookVector
		out = Vector3.new(look.X, 0, look.Z)
		if out.Magnitude < 0.5 then
			out = Vector3.new(0, 0, 1)
		end
	end
	local hook: Hook = { Part = part, Name = name, LiftId = liftId, Point = position, Out = out.Unit }
	table.insert(hooks, hook)
	IntakeService.addZone("Train" .. (liftId or "Station"), part, function(record: ItemRecord)
		onIntake(hook, record)
	end)
	local anchor: Instance = point or part
	local load = makePrompt(anchor, "TrainLoadPrompt", "Load", "Load Train", name, Enum.KeyCode.F, Enum.KeyCode.ButtonY, 0)
	load.Triggered:Connect(function(player: Player)
		loadFromHands(player, hook)
	end)
	local send = makePrompt(anchor, "TrainSendPrompt", "Send", "Send Train", name, Enum.KeyCode.G, Enum.KeyCode.ButtonB, 1)
	send.Triggered:Connect(function(player: Player)
		TrainService.send(player)
	end)
	return hook
end

local function tryHook(instance: Instance)
	if instance:IsA("BasePart") and instance:HasTag(TrainService.HookTag) and instance.Parent then
		setupHook(instance)
	end
end

-- Every hook under the railway, now and later (deferred: a model being
-- built gets its attachments before the hook is set up).
local function watchRailway(railway: Instance)
	for _, d in railway:GetDescendants() do
		tryHook(d)
	end
	railway.DescendantAdded:Connect(function(d: Instance)
		task.defer(tryHook, d)
	end)
end

---------------------------------------------------------------- TrainAction

function TrainService.upgrade(player: Player, kind: string): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	if kind ~= "Capacity" and kind ~= "Speed" then
		return false, "BadKind"
	end
	local train = trainOf(data)
	local isCapacity = kind == "Capacity"
	local list = if isCapacity then TrainConfig.Capacity else TrainConfig.Speed
	local level = if isCapacity then train.CapacityLevel else train.SpeedLevel
	local price = TrainConfig.nextPrice(list, level)
	if not price then
		toast(player, "Your train is already at the top level.", "Info")
		return false, "Max"
	end
	if not EconomyService.spend(player, price, "Train" .. kind) then
		toast(player, `You need {Format.money(price)} for this train upgrade.`)
		return false, "Coins"
	end
	-- no yield between paying and the new level
	if isCapacity then
		train.CapacityLevel = level + 1
	else
		train.SpeedLevel = level + 1
	end
	DataService.changed(player)
	local express = hasExpress(player)
	local text = if isCapacity
		then `Train upgraded: {TrainConfig.capacity(level + 1, express)} cargo slots!`
		else `Train upgraded: {string.format("%g", TrainConfig.tripSeconds(level + 1, express))} s trips!`
	toast(player, text, "Reward")
	return true, nil
end

-- TrainAction ("Send") or ("Upgrade", { Kind = "Capacity" | "Speed" })
local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	if not action or not DataService.get(player) then
		return
	end
	if action == "Send" then
		TrainService.send(player)
	elseif action == "Upgrade" then
		local arg = Guard.table(argArg, 4)
		local kind = if arg then Guard.string(arg.Kind, 16) else nil
		if kind == "Capacity" or kind == "Speed" then
			TrainService.upgrade(player, kind)
		end
	end
end

---------------------------------------------------------------- the 1 s loop

local function tickOne(player: Player, now: number)
	if not player.Parent then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local train = trainOf(data)
	local r = runtimes[player]
	-- on the move or waiting at the stop: unload when it has arrived
	if #train.TripCargo > 0 or train.TripArriveAt > 0 then
		local retry = r and r.NextRetry
		if now >= train.TripArriveAt and (not retry or now >= retry) then
			deliver(player, data, true)
		end
		return
	end
	-- back at the station after unloading
	if r and r.ReturnUntil and now >= r.ReturnUntil then
		r.ReturnUntil = nil
		r.ReturnAt = nil
		DataService.changed(player)
	end
	if #train.Cargo == 0 or isReturning(player) then
		return
	end
	-- leave when full, or AutoDepartSeconds after the last load
	local rt = runtimeOf(player)
	local lastLoad = rt.LastLoad
	if cargoRoom(player, train) <= 0 then
		TrainService.depart(player)
	elseif not lastLoad or now < lastLoad then
		rt.LastLoad = now
		DataService.changed(player)
	elseif now - lastLoad >= TrainConfig.AutoDepartSeconds then
		TrainService.depart(player)
	end
end

-- Arrivals, pen-full retries, returns and auto departures for every player.
-- One player's error never stops the others' trains.
function TrainService.tick()
	local now = clock()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(tickOne :: any, player, now)
		if not ok then
			warn(`[TrainService] train of {player.Name} failed: {err}`)
		end
	end
end

---------------------------------------------------------------- joining

-- A player's running trip to every client (once per session, when both the
-- save and the plot are ready).
local function announce(player: Player)
	local r = runtimes[player]
	local data = DataService.get(player)
	if not r or not r.Prepared or r.Announced or not data then
		return
	end
	local trip = tripOf(player, trainOf(data))
	if not trip or trip.ArriveAt <= serverNow() then
		return
	end
	r.Announced = true
	Net.fireAll("TrainTrip", trip)
end

-- Everyone else's trips for a joining player (a list, maybe empty).
local function sendTripsTo(player: Player)
	local list: { Trip } = {}
	for other in runtimes do
		local data = if other ~= player then DataService.get(other) else nil
		if data then
			local trip = tripOf(other, trainOf(data))
			if trip then
				table.insert(list, trip)
			end
		end
	end
	Net.fire("TrainTrip", player, list)
end

local function onLoaded(player: Player, data: { [string]: any })
	local train = trainOf(data)
	local r = runtimeOf(player)
	local now = clock()
	if #train.TripCargo > 0 then
		-- a save from a server with a skewed clock: never more than a full trip away
		local longest = TrainConfig.tripSeconds(0, false)
		if train.TripArriveAt > now + longest then
			train.TripArriveAt = now + tripSecondsOf(player, train)
		end
		if train.TripDepartAt <= 0 or train.TripDepartAt > train.TripArriveAt then
			train.TripDepartAt = train.TripArriveAt - tripSecondsOf(player, train)
		end
		tripTimes(train, r)
		if now >= train.TripArriveAt then
			deliver(player, data, false)
		end
	else
		train.TripDepartAt = 0
		train.TripArriveAt = 0
	end
	if #train.Cargo > 0 then
		r.LastLoad = now
	end
	r.Prepared = true
	sendTripsTo(player)
	announce(player)
	DataService.changed(player)
end

---------------------------------------------------------------- state snapshot

local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	local train = trainOf(data)
	local r = runtimes[player]
	local express = hasExpress(player)
	local away = isAway(player, train)
	local departAt: number?, arriveAt: number? = nil, nil
	if #train.TripCargo > 0 and r then
		departAt, arriveAt = tripTimes(train, r)
	end
	local lastLoad = r and r.LastLoad
	local autoIn: number? = nil
	if not away and #train.Cargo > 0 and lastLoad then
		autoIn = math.max(0, lastLoad + TrainConfig.AutoDepartSeconds - clock())
	end
	snapshot.Train = {
		Cargo = #train.Cargo,
		Capacity = TrainConfig.capacity(train.CapacityLevel, express),
		Moving = #train.TripCargo,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		CapacityLevel = train.CapacityLevel,
		SpeedLevel = train.SpeedLevel,
		NextCapacityPrice = TrainConfig.nextPrice(TrainConfig.Capacity, train.CapacityLevel),
		NextSpeedPrice = TrainConfig.nextPrice(TrainConfig.Speed, train.SpeedLevel),
		Express = express,
		TripSeconds = TrainConfig.tripSeconds(train.SpeedLevel, express),
		AutoDepartIn = autoIn,
		ReturnAt = if r and isReturning(player) then r.ReturnAt else nil,
	}
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/TrainService.spec.luau).
TrainService._test = {
	action = onAction,
	intake = onIntake,
	load = loadFromHands,
	setupHook = setupHook,
	watch = watchRailway,
	loaded = onLoaded,
	announce = announce,
	provide = provide,
	tickOne = tickOne,
	runtime = function(player: Player): Runtime?
		return runtimes[player]
	end,
	-- what leaving does to the unsaved state (a rejoin starts from the save)
	forget = function(player: Player)
		runtimes[player] = nil
	end,
	setClock = function(fn: (() -> number)?, server: (() -> number)?)
		clock = fn or os.time
		serverNow = server or function(): number
			return Workspace:GetServerTimeNow()
		end
	end,
	reset = function()
		table.clear(runtimes)
		table.clear(hooks)
		clock = os.time
		serverNow = function(): number
			return Workspace:GetServerTimeNow()
		end
	end,
}

local function watchPerk(player: Player)
	if perkConnections[player] then
		return
	end
	perkConnections[player] = player:GetAttributeChangedSignal("Perk_TrainExpress"):Connect(function()
		DataService.changed(player)
	end)
end

function TrainService.init()
	Net.on("TrainAction", onAction)
	StateService.addProvider(provide)
	DataService.onLoaded(onLoaded)
	PlotService.onAssigned(function(player: Player)
		announce(player)
	end)
	Players.PlayerAdded:Connect(watchPerk)
	for _, player in Players:GetPlayers() do
		watchPerk(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtimes[player] = nil
		-- the 1 s loop may touch a leaving player once more before the save is released
		task.delay(5, function()
			runtimes[player] = nil
		end)
		local connection = perkConnections[player]
		if connection then
			connection:Disconnect()
			perkConnections[player] = nil
		end
	end)
end

function TrainService.start()
	-- a hook tagged after it was built (or rebuilt) under the railway
	CollectionService:GetInstanceAddedSignal(TrainService.HookTag):Connect(function(instance: Instance)
		local map = Workspace:FindFirstChild("Map")
		local railway = map and map:FindFirstChild("Railway")
		if railway and instance:IsDescendantOf(railway) then
			task.defer(tryHook, instance)
		end
	end)
	task.spawn(function()
		local map = Workspace:WaitForChild("Map", MAP_WAIT)
		if not map then
			warn("[TrainService] no Workspace.Map: the train hoppers are missing")
			return
		end
		local railway = map:WaitForChild("Railway", 10)
		if railway then
			watchRailway(railway)
			return
		end
		warn("[TrainService] Workspace.Map has no Railway yet (old map?): waiting for it")
		map.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Railway" then
				watchRailway(child)
			end
		end)
	end)
	while true do
		task.wait(1)
		TrainService.tick()
	end
end

return TrainService
