--[[
	StorageService: the Storage Crate. All crates share ONE store,
	data.Storage, a list of item descriptors { K, O, G?, R? }.

	- Capacity: StorageCrateCapacity (60) per placed crate, at most
	  MaxStoredItems (300). Players can only fill it up to that; system
	  writes (leaving, the loose-item cap, packing a machine up) use
	  ItemService.storeDesc, which keeps the 300 cap and pays full value
	  beyond it. Packing a crate up never touches the store: the items wait
	  until a crate is placed again.
	- In: drop or throw items into the crate's hopper, run a belt into any
	  side, point a machine's front at it, or use "Store Items" (Put In).
	  Only your own items go in.
	- Out: "Open Crate" opens the crate panel on the owner's screen; its Take
	  buttons send MachineAction 'StorageTake' { Key, Count }. Taken items
	  appear at the crate's front and go straight into your hands while
	  they have room.
	- Every crate's sign shows the store's fill ('12/60'): green, amber from
	  80%, red when full.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local Theme = require(Shared.Config.UITheme)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)

local StorageService = {}

type Desc = ItemData.Desc
type PlacedMachine = MachineService.PlacedMachine

local CRATE = "StorageCrate"
-- "Your crates are full" toast at most this often (per player)
local FULL_TOAST_COOLDOWN = 5
-- taken items appear this much higher each, so they don't spawn inside each other
local TAKE_SPACING = 0.5
-- sign colours: under 80% green, then amber, red when full
local AMBER_FROM = 0.8
local HANDS_FULL = "Your hands are full and lots of items are lying around. Pick some up first!"

local lastFullToast: { [Player]: number } = {}
-- the sign text all of a player's crates show now (skips work on most data changes)
local shownSign: { [Player]: string } = {}

---------------------------------------------------------------- capacity

local function crateCount(data: { [string]: any }): number
	local count = 0
	for _, entry in data.PlacedMachines do
		if type(entry) == "table" and entry.Id == CRATE then
			count += 1
		end
	end
	return count
end

local function capacityOf(data: { [string]: any }): number
	return math.min(GameConfig.MaxStoredItems, GameConfig.StorageCrateCapacity * crateCount(data))
end

-- How many items the player's crates hold together (0 without crates).
function StorageService.capacity(player: Player): number
	local data = DataService.get(player)
	return if data then capacityOf(data) else 0
end

---------------------------------------------------------------- count sign

-- Sign text and colour for a store holding `count` of `capacity`.
function StorageService.signFor(count: number, capacity: number): (string, Color3)
	local text = `{count}/{capacity}`
	if capacity <= 0 or count >= capacity then
		return text, Theme.Bad
	elseif count >= capacity * AMBER_FROM then
		return text, Theme.Accent
	end
	return text, Theme.Good
end

local function signLabel(machine: PlacedMachine): TextLabel?
	local cached = machine.State.SignLabel :: TextLabel?
	if cached and cached.Parent then
		return cached
	end
	local board = machine.Model:FindFirstChild("CountSign")
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		machine.State.SignLabel = label
		return label
	end
	return nil
end

-- Writes the sign only when its text changes.
local function updateSign(machine: PlacedMachine, count: number, capacity: number)
	local text, color = StorageService.signFor(count, capacity)
	if machine.State.SignText == text then
		return
	end
	local label = signLabel(machine)
	if label then
		machine.State.SignText = text
		label.Text = text
		label.TextColor3 = color
	end
end

-- Refreshes every crate sign of a player (new crates set their own sign
-- when they spawn).
local function updateSigns(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local count, capacity = #data.Storage, capacityOf(data)
	local text = StorageService.signFor(count, capacity)
	if shownSign[player] == text then
		return
	end
	shownSign[player] = text
	for _, machine in MachineService.ofPlayer(player) do
		if machine.Id == CRATE and not machine.Removed then
			updateSign(machine, count, capacity)
		end
	end
end

---------------------------------------------------------------- crate behaviour

local function fullToast(player: Player, count: number, capacity: number, via: MachineService.Via)
	local now = os.clock()
	if now - (lastFullToast[player] or -math.huge) < FULL_TOAST_COOLDOWN then
		return
	end
	lastFullToast[player] = now
	Net.fire("Notify", player, {
		Text = `Your crates are full ({count}/{capacity}). Take items out or sell them.`,
		-- a quieter toast when belts or machines keep running into it
		Kind = if via == "Drop" then "Deny" else "Info",
	})
end

local function openCrate(player: Player, machine: PlacedMachine)
	if machine.Removed then
		return
	end
	if player ~= machine.Owner then
		Net.fire("Notify", player, { Text = "That's not your crate.", Kind = "Deny" })
		return
	end
	Net.fire("OpenUI", player, "Storage", { Machine = machine.Model })
end

-- "Open Crate": G / gamepad B, so it never shares a key with Store Items (F / Y).
local function addOpenPrompt(machine: PlacedMachine): ProximityPrompt
	local base = machine.Model.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open Crate"
	prompt.ObjectText = machine.Info.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 72)
	prompt.Parent = base:FindFirstChild("Prompt") or base
	prompt.Triggered:Connect(function(player)
		openCrate(player, machine)
	end)
	return prompt
end

local crateBehaviour: MachineService.Behaviour = {
	spawned = function(machine: PlacedMachine)
		machine.Model:SetAttribute("Cycles", 0)
		IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Store Items", 0)
		addOpenPrompt(machine)
		local data = DataService.get(machine.Owner)
		if data then
			updateSign(machine, #data.Storage, capacityOf(data))
		end
	end,
	-- the owner's items, while the shared store has room
	canAccept = function(machine: PlacedMachine, desc: Desc, ownerUserId: number, via: MachineService.Via): (boolean, MachineService.Reason?)
		local ok, reason = MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
		if not ok then
			return false, reason
		end
		local data = DataService.get(machine.Owner)
		if not data then
			return false, "Busy"
		end
		local count, capacity = #data.Storage, capacityOf(data)
		if count >= capacity then
			-- Put In already says why nothing went in
			if via ~= "Hand" then
				fullToast(machine.Owner, count, capacity, via)
			end
			return false, "Full"
		end
		return true, nil
	end,
	insert = function(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: MachineService.Via)
		local data = DataService.get(machine.Owner)
		if not data then
			-- MachineService puts the item back out instead of losing it
			error("the crate owner's data is not loaded")
		end
		table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		local cycles = machine.Model:GetAttribute("Cycles")
		machine.Model:SetAttribute("Cycles", (if type(cycles) == "number" then cycles else 0) + 1)
		DataService.changed(machine.Owner)
	end,
}

---------------------------------------------------------------- taking items out

-- Index of the last stored item with this storage key, if any.
local function lastMatching(storage: { Desc }, key: string): number?
	for i = #storage, 1, -1 do
		local entry = storage[i]
		if type(entry) == "table" and ItemData.storageKey(entry) == key then
			return i
		end
	end
	return nil
end

--[[
	MachineAction 'StorageTake' { Key = 'K|O|G|R', Count = 1..StorageTakeMax }.
	MachineService has already checked: the caller's own machine, within
	MachineUseRange. Takes at most what fits in free hands plus the room
	left under the loose-item cap (so taking never pushes other items into
	Storage). Each item spawns at the crate's front and goes into your hands
	while they have room.
]]
local function takeItems(player: Player, machine: PlacedMachine, arg: any)
	if machine.Id ~= CRATE or machine.Removed then
		return
	end
	local request = Guard.table(arg, 4)
	if not request then
		return
	end
	local keyText = Guard.string(request.Key, 80)
	local desc = if keyText then ItemData.parseKey(keyText) else nil
	local count = Guard.integer(request.Count, 1, GameConfig.StorageTakeMax)
	if not desc or not count then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local freeHands = math.max(0, CarryService.capacity(player) - #CarryService.list(player))
	local looseRoom = math.max(0, GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom - ItemService.looseCount(player.UserId))
	local allowed = math.min(count, freeHands + looseRoom)
	if allowed <= 0 then
		Net.fire("Notify", player, { Text = HANDS_FULL, Kind = "Deny" })
		return
	end
	local key = ItemData.storageKey(desc)
	local front = MachineService.point(machine, "Output") or machine.Model:GetPivot()
	local taken = 0
	for i = 1, allowed do
		local index = lastMatching(data.Storage, key)
		if not index then
			break
		end
		local entry = table.remove(data.Storage, index) :: Desc
		local record = ItemService.spawnDesc(entry, player.UserId, front + Vector3.new(0, TAKE_SPACING * (i - 1), 0))
		if not record then
			-- never lose it: back where it was
			table.insert(data.Storage, index, entry)
			warn(`[StorageService] could not take {key} out for {player.Name}`)
			break
		end
		taken += 1
		if freeHands > 0 and CarryService.pickup(player, record) then
			freeHands -= 1
		end
	end
	if taken > 0 then
		DataService.changed(player)
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/StorageService.spec.luau).
StorageService._test = {
	crate = crateBehaviour,
	take = takeItems,
	open = openCrate,
	updateSigns = updateSigns,
	reset = function()
		table.clear(lastFullToast)
		table.clear(shownSign)
	end,
}

function StorageService.init()
	MachineService.register(CRATE, crateBehaviour)
	MachineService.onAction("StorageTake", takeItems)
	MachineService.onLayoutChanged(function(player)
		updateSigns(player)
	end)
	DataService.onChanged(updateSigns)
	StateService.addProvider(function(_, data, snapshot)
		snapshot.StorageCapacity = capacityOf(data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastFullToast[player] = nil
		shownSign[player] = nil
	end)
end

return StorageService
