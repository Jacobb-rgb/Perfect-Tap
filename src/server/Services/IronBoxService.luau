--[[
	IronBoxService: the Iron Box (step 3, docs/plans/STEP3_PLAN.md) and the
	player's keep list.

	The box is a sorter on ProcessingService's timed jobs
	(ProcessingService.sorterBehaviour): items come in by its hopper, a belt
	on any side but the front, the Put In prompt or a machine in front of
	it (IntakeService / MachineService), wait their turn in its queue and
	take MachineData's sort Time (with Bellows and the box's Speed level).
	Then each item goes ONE way, decided when its job finishes:
	  - kept (MachineData.keeps with data.KeepMode / data.KeepList: only
	    clean ore is ever kept) -> into the Ore Pen (PenService.store), in
	    the same step that takes it out of the box, no yield in between;
	  - everything else (dirty ore still needs cleaning, crushed ore and
	    ingots always pass on), and kept ore while the pen is full (a
	    throttled hint says so) -> out of the box's front onto your belts,
	    like any machine output (MachineService sends Entry.Out).
	Model attributes for the client (MachineFxController draws the screen,
	the flaps and the item behind the window from them):
	  LastKind   "" | "Raw" | "Clean" | "Crushed" | "Ingot" (the last item sorted)
	  LastOre    its ore id ("" for dirty ore: the box can't see through dirt)
	  LastGrade  its grade id ("" for dirty ore or none)
	  LastRoute  "" | "Keep" | "Send"
	  Kept, Sent items sorted each way since the box appeared (not saved)

	Keep list: the "Keep List" prompt on your box (G / gamepad B) opens
	IronBoxView (OpenUI "IronBox" { Box = model }). IronBoxAction:
	  "SetMode"     { Mode }        data.KeepMode ("RarePlus" | "List" | "All")
	  "SetKeep"     { Ore, Keep }   one ore's choice on data.KeepList
	  "SetKeepMany" { Ores, Keep }  presets (up to #OreData.List ores)
	  "ClearList"   (no arg)        an empty list: every ore follows the Rare+ rule
	Ores must be known AND discovered (you can only choose ores you've seen
	clean). Choosing an ore while the mode isn't "List" first writes what the
	panel showed for every discovered ore into the list and switches to
	"List", so exactly the one tapped chip changes. Every change ->
	DataService.changed; the client redraws from the State snapshot
	(KeepMode, KeepList, Discovered).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)
local PenService = require(script.Parent.PenService)
local ProcessingService = require(script.Parent.ProcessingService)

local IronBoxService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineService.Desc

IronBoxService.MachineId = "IronBox"
IronBoxService.PromptName = "KeepListPrompt"
IronBoxService.PenFullText = "Your Ore Pen is full: the Iron Box sends the ore you keep out of its front."

local MAX_ORE_ID = 32
local DENY_COOLDOWN = 3

local lastDeny: { [Player]: number } = {}

---------------------------------------------------------------- keep settings

-- data.KeepList as a table (a broken value becomes an empty list).
local function keepListOf(data: { [string]: any }): { [string]: boolean }
	local list = data.KeepList
	if type(list) ~= "table" then
		list = {}
		data.KeepList = list
	end
	return list
end

local function isDiscovered(data: { [string]: any }, oreId: string): boolean
	local discovered = data.Discovered
	return type(discovered) == "table" and discovered[oreId] == true
end

-- A client's ore id that is known and that this player has discovered.
local function chosenOre(data: { [string]: any }, value: any): string?
	local oreId = Guard.string(value, MAX_ORE_ID)
	if oreId and OreData.ById[oreId] and isDiscovered(data, oreId) then
		return oreId
	end
	return nil
end

--[[
	Before a choice in a mode other than "List": the list becomes what the
	panel showed (keepsOre in the current mode) for every discovered ore,
	and the mode becomes "List". Undiscovered ores get no entry (they follow
	the Rare+ rule when they turn up).
]]
local function toListMode(data: { [string]: any })
	if data.KeepMode == "List" then
		keepListOf(data)
		return
	end
	local old = data.KeepList
	local list: { [string]: boolean } = {}
	for _, ore in OreData.List do
		if isDiscovered(data, ore.Id) then
			list[ore.Id] = MachineData.keepsOre(data.KeepMode, old, ore.Id)
		end
	end
	data.KeepList = list
	data.KeepMode = "List"
end

-- Applies one IronBoxAction to a save. Returns true when something changed.
function IronBoxService.apply(data: { [string]: any }, action: string, arg: any): boolean
	if action == "ClearList" then
		local list = data.KeepList
		if type(list) == "table" and next(list) == nil then
			return false
		end
		data.KeepList = {}
		return true
	end
	local payload = Guard.table(arg, 4)
	if not payload then
		return false
	end
	if action == "SetMode" then
		local mode = payload.Mode
		if not MachineData.isKeepMode(mode) or data.KeepMode == mode then
			return false
		end
		data.KeepMode = mode
		keepListOf(data)
		return true
	end
	local keep = Guard.boolean(payload.Keep)
	if keep == nil then
		return false
	end
	local ores: { string } = {}
	if action == "SetKeep" then
		local oreId = chosenOre(data, payload.Ore)
		if oreId then
			table.insert(ores, oreId)
		end
	elseif action == "SetKeepMany" then
		local list = Guard.table(payload.Ores, #OreData.List)
		if not list then
			return false
		end
		local seen: { [string]: boolean } = {}
		for _, value in list do
			local oreId = chosenOre(data, value)
			if oreId and not seen[oreId] then
				seen[oreId] = true
				table.insert(ores, oreId)
			end
		end
	else
		return false
	end
	if #ores == 0 then
		return false
	end
	local before = data.KeepMode
	toListMode(data)
	local list = keepListOf(data)
	local changed = before ~= data.KeepMode
	for _, oreId in ores do
		if list[oreId] ~= keep then
			list[oreId] = keep
			changed = true
		end
	end
	return changed
end

local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	local data = DataService.get(player)
	if not action or not data then
		return
	end
	if IronBoxService.apply(data, action, argArg) then
		DataService.changed(player)
	end
end

---------------------------------------------------------------- the box

-- Kept clean ore goes into the pen; false = it leaves the front.
local function take(machine: PlacedMachine, desc: Desc): boolean
	local player = machine.Owner
	local data = DataService.get(player)
	if not data or not MachineData.keeps(data.KeepMode, data.KeepList, desc) then
		return false
	end
	if PenService.hasRoom(player) then
		-- the last step: once stored, the item is in the pen
		return PenService.store(player, desc)
	end
	IntakeService.hint(player, "IronBox/PenFull", IronBoxService.PenFullText)
	return false
end

local function sorted(machine: PlacedMachine, desc: Desc, kept: boolean)
	local state = machine.State
	local dirty = desc.K == "Raw"
	if kept then
		state.Kept = (state.Kept or 0) + 1
	else
		state.Sent = (state.Sent or 0) + 1
	end
	MachineService.setAttrs(machine, {
		LastKind = desc.K,
		LastOre = if dirty then "" else desc.O,
		LastGrade = if dirty then "" else desc.G or "",
		LastRoute = if kept then "Keep" else "Send",
		Kept = state.Kept or 0,
		Sent = state.Sent or 0,
	})
end

local function deny(player: Player, text: string)
	local now = os.clock()
	if now - (lastDeny[player] or -math.huge) < DENY_COOLDOWN then
		return
	end
	lastDeny[player] = now
	Net.fire("Notify", player, { Text = text, Kind = "Deny" })
end

-- "Keep List": your own box opens the panel.
local function openList(player: Player, machine: PlacedMachine)
	if machine.Removed then
		return
	end
	if machine.Owner ~= player then
		deny(player, "That's not your Iron Box.")
		return
	end
	if DataService.get(player) then
		Net.fire("OpenUI", player, "IronBox", { Box = machine.Model })
	end
end

local function spawned(machine: PlacedMachine)
	machine.State.Kept = 0
	machine.State.Sent = 0
	MachineService.setAttrs(machine, {
		LastKind = "",
		LastOre = "",
		LastGrade = "",
		LastRoute = "",
		Kept = 0,
		Sent = 0,
	})
	local base = machine.Model.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = IronBoxService.PromptName
	prompt.ActionText = "Keep List"
	prompt.ObjectText = machine.Info.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 72)
	prompt.Parent = base:FindFirstChild("Prompt") or base
	prompt.Triggered:Connect(function(player: Player)
		openList(player, machine)
	end)
end

IronBoxService.sorter = {
	take = take,
	sorted = sorted,
	spawned = spawned,
} :: ProcessingService.Sorter

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/IronBox.spec.luau).
IronBoxService._test = {
	action = onAction,
	open = openList,
	reset = function()
		table.clear(lastDeny)
	end,
}

function IronBoxService.init()
	assert(MachineData.ById[IronBoxService.MachineId], "IronBox missing from MachineData")
	MachineService.register(IronBoxService.MachineId, ProcessingService.sorterBehaviour(IronBoxService.sorter))
	Net.on("IronBoxAction", onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastDeny[player] = nil
	end)
end

return IronBoxService
