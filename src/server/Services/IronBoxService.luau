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
	    ingots always pass on), and kept ore while the pen is full -> out of
	    the box's front onto your belts, like any machine output
	    (MachineService sends Entry.Out). A full pen sets the box's PenFull
	    attribute (its billboard says "Ore Pen full") until kept ore fits
	    again, the pen has room again, the keep list changes, or the box
	    has only passed on ore it doesn't keep for PEN_FULL_HOLD seconds
	    (nothing waits on the pen any more); the toast comes once when the
	    pen turns full for the box, at most every PEN_FULL_COOLDOWN seconds.
	Model attributes for the client (MachineFxController draws the screen,
	the flaps and the item behind the window from them):
	  LastKind   "" | "Raw" | "Clean" | "Crushed" | "Ingot" (the last item sorted)
	  LastOre    its ore id ("" for dirty ore: the box can't see through dirt)
	  LastGrade  its grade id ("" for dirty ore or none)
	  LastRoute  "" | "Keep" | "Send"
	  Kept, Sent items sorted each way since the box appeared (not saved)
	  PenFull    true while kept ore can't go into the full pen

	Keep list: the "Keep List" prompt on your box (G / gamepad B) opens
	IronBoxView (OpenUI "IronBox" { Box = model, Position = its pivot, the
	client's range check while the model hasn't streamed in }). IronBoxAction:
	  "SetMode"     { Mode }        data.KeepMode ("RarePlus" | "List" | "All")
	  "SetKeep"     { Ore, Keep }   one ore's choice on data.KeepList
	  "SetKeepMany" { Ores, Keep }  presets (up to #OreData.List ores)
	  "ClearList"   (no arg)        an empty list: every ore follows the Rare+ rule
	Ores must be known AND discovered (you can only choose ores you've seen
	clean). Choosing an ore while the mode isn't "List" first writes what the
	panel showed for every discovered ore into the list and switches to
	"List", so exactly the one tapped chip changes; this REPLACES an older
	custom list (switching modes alone keeps it, so MY LIST brings it back,
	and the panel's mode line warns before a tap replaces it). Every change
	-> DataService.changed; the client redraws from the State snapshot
	(KeepMode, KeepList, Discovered).

	Sorting board (Pen Automation, EconomyConfig.PenAutomation.Billboard):
	while the owner's Upgrades.PenAutomation is at least that level, their
	plot has a board at the Ore Pen gate (MachineBuilder.sortingBoard, at
	boardPoint, in the yard) showing what the keep list keeps (the mode and
	the kept ores' colours). Its "Keep List" prompt (F / gamepad Y: its
	only prompt, while G / B is the gate's "Open Pen" a few steps away, so
	both show at the gate; tagged like the pen's prompts, so only the owner
	sees it) opens the same IronBoxView (OpenUI "IronBox" { Box = board,
	Position }) after the owner and level checks, so the list can be set
	without an Iron Box (for the pen's "Send unkept"). The board comes with
	the upgrade (a cheap check on every DataService.changed) and goes with
	the plot; it is repainted only when what it shows can change (an
	IronBoxAction, a new discovery), not on every save change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Discovery = require(script.Parent.Parent.Discovery)
local DataService = require(script.Parent.DataService)
local MachineService = require(script.Parent.MachineService)
local PenService = require(script.Parent.PenService)
local PlotService = require(script.Parent.PlotService)
local ProcessingService = require(script.Parent.ProcessingService)

local IronBoxService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineService.Desc

IronBoxService.MachineId = "IronBox"
IronBoxService.PromptName = "KeepListPrompt"
IronBoxService.PenFullText = "Your Ore Pen is full: the Iron Box sends the ore you keep out of its front."
IronBoxService.PenOverText =
	"Your Ore Pen is over its limit: the Iron Box sends the ore you keep out of its front until you take or sell some."
IronBoxService.BoardName = "SortingBoard"
IronBoxService.BoardPromptName = "SortingBoardPrompt"
IronBoxService.BoardModeText = {
	RarePlus = "KEEPS RARE+",
	List = "KEEPS MY LIST",
	All = "KEEPS EVERYTHING",
} :: { [string]: string }

local MAX_ORE_ID = 32
local DENY_COOLDOWN = 3
local PEN_FULL_COOLDOWN = 120 -- seconds between two "pen full" toasts
-- seconds after the last kept item the full pen refused before ore the box
-- doesn't keep clears its "pen full" sign (no flicker in a mixed stream)
local PEN_FULL_HOLD = 15

local clock = os.clock -- the tests swap it
local lastDeny: { [Player]: number } = {}
-- "pen full" toasts: when the last one came, and whether the pen is still
-- full since then (no new toast until kept ore fits into the pen again)
local penFullAt: { [Player]: number } = {}
local penFullShown: { [Player]: boolean } = {}
-- boxes showing "pen full" (cleared when their owner's pen has room again)
local fullBoxes: { [PlacedMachine]: boolean } = {}
-- sorting boards by plot id, and what each one shows
local boards: { [number]: Model } = {}
local boardShows: { [number]: string } = {}

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

---------------------------------------------------------------- the box

-- The "pen full" toast: once when the pen turns full, then not again for
-- PEN_FULL_COOLDOWN seconds (a running factory with a full pen stays quiet;
-- the box's billboard keeps saying it).
local function penFullHint(player: Player)
	if penFullShown[player] then
		return
	end
	local now = clock()
	if now - (penFullAt[player] or -math.huge) < PEN_FULL_COOLDOWN then
		return
	end
	penFullShown[player] = true
	penFullAt[player] = now
	local data = DataService.get(player)
	local over = data ~= nil and PenService.isOver(data)
	Net.fire("Notify", player, { Text = if over then IronBoxService.PenOverText else IronBoxService.PenFullText, Kind = "Info" })
end

-- The box's PenFull attribute (its billboard says "Ore Pen full").
local function setPenFull(machine: PlacedMachine, on: boolean)
	if on and not machine.Removed then
		fullBoxes[machine] = true
	else
		fullBoxes[machine] = nil
	end
	if (machine.State.PenFull == true) ~= on then
		machine.State.PenFull = on
		if not machine.Removed then
			MachineService.setAttrs(machine, { PenFull = on })
		end
	end
end

-- Does the owner's keep list keep this item (clean ore only)?
local function wanted(machine: PlacedMachine, desc: Desc): boolean
	local data = DataService.get(machine.Owner)
	return data ~= nil and MachineData.keeps(data.KeepMode, data.KeepList, desc)
end

--[[
	Kept clean ore goes into the pen; false = it leaves the front. The store
	is the very last step (ProcessingService's Sorter contract: an error
	after it would leave the item in the pen AND in the box); the PenFull
	bookkeeping for a stored item happens in sorted(), after complete().
]]
local function take(machine: PlacedMachine, desc: Desc): boolean
	local player = machine.Owner
	if not wanted(machine, desc) then
		return false
	end
	if not PenService.hasRoom(player) then
		machine.State.PenRefusedAt = clock()
		setPenFull(machine, true)
		penFullHint(player)
		return false
	end
	return PenService.store(player, desc)
end

-- The player's pen has room again: their boxes stop saying "pen full", and
-- the next time it turns full may toast again (on every save change: cheap,
-- only boxes that show it are looked at).
local function penRoomCheck(player: Player)
	if not penFullShown[player] and next(fullBoxes) == nil then
		return
	end
	if not PenService.hasRoom(player) then
		return
	end
	penFullShown[player] = nil
	for machine in fullBoxes do
		if machine.Removed then
			fullBoxes[machine] = nil
		elseif machine.Owner == player then
			setPenFull(machine, false)
		end
	end
end

local function sorted(machine: PlacedMachine, desc: Desc, kept: boolean)
	local state = machine.State
	local dirty = desc.K == "Raw"
	if kept then
		state.Kept = (state.Kept or 0) + 1
		setPenFull(machine, false)
	else
		state.Sent = (state.Sent or 0) + 1
		-- ore the list doesn't keep went on (not the full pen's fault): once
		-- the pen hasn't refused anything for a while, nothing waits on it
		local refused = state.PenRefusedAt
		local since = clock() - (if type(refused) == "number" then refused else -math.huge)
		if state.PenFull == true and since >= PEN_FULL_HOLD and not wanted(machine, desc) then
			setPenFull(machine, false)
		end
	end
	penRoomCheck(machine.Owner)
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
		Net.fire("OpenUI", player, "IronBox", { Box = machine.Model, Position = machine.Model:GetPivot().Position })
	end
end

local function spawned(machine: PlacedMachine)
	machine.State.Kept = 0
	machine.State.Sent = 0
	machine.State.PenFull = false
	MachineService.setAttrs(machine, {
		LastKind = "",
		LastOre = "",
		LastGrade = "",
		LastRoute = "",
		Kept = 0,
		Sent = 0,
		PenFull = false,
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

---------------------------------------------------------------- the sorting board

local PEN_AUTOMATION = EconomyConfig.techItem("PenAutomation")

-- Does this save have the sorting board (Pen Automation level)?
function IronBoxService.hasBoard(data: { [string]: any }): boolean
	if not PEN_AUTOMATION then
		return false
	end
	local level = EconomyConfig.techLevel(PEN_AUTOMATION, data)
	return level >= EconomyConfig.PenAutomation.Billboard
end

-- Where the board stands, plot space: in front of the pen's front wall,
-- between the gate's right post and the pen's corner, facing the grid (-Z).
function IronBoxService.boardPoint(): CFrame
	local area = BaseLayout.Pen.Area
	local x = area.Center.X + area.Size.X / 2 - 3.6
	local z = area.Center.Z - area.Size.Z / 2 - 0.75
	return CFrame.new(x, 0, z)
end

-- What a board shows for a save: the mode line, the kept discovered ores'
-- colours (best income first) and the text when nothing is kept.
function IronBoxService.boardInfo(data: { [string]: any }): MachineBuilder.BoardInfo
	local mode = if MachineData.isKeepMode(data.KeepMode) then data.KeepMode else MachineData.Keep.Default
	local discovered = if type(data.Discovered) == "table" then data.Discovered else {}
	local kept: { OreData.Ore } = {}
	local any = false
	for _, ore in OreData.List do
		if discovered[ore.Id] == true then
			any = true
			if MachineData.keepsOre(mode, data.KeepList, ore.Id) then
				table.insert(kept, ore)
			end
		end
	end
	table.sort(kept, function(a, b)
		if a.Income ~= b.Income then
			return a.Income > b.Income
		end
		return a.Name < b.Name
	end)
	local colors: { Color3 } = {}
	for _, ore in kept do
		table.insert(colors, ore.Color)
	end
	return {
		Mode = IronBoxService.BoardModeText[mode] or IronBoxService.BoardModeText.RarePlus,
		Colors = colors,
		Empty = if any then "SENDS EVERYTHING ON" else "NO ORE FOUND YET",
	}
end

local function boardKey(info: MachineBuilder.BoardInfo): string
	local parts = { info.Mode, info.Empty }
	for _, color in info.Colors do
		table.insert(parts, `{math.floor(color.R * 255 + 0.5)},{math.floor(color.G * 255 + 0.5)},{math.floor(color.B * 255 + 0.5)}`)
	end
	return table.concat(parts, "|")
end

-- "Keep List" at the board: the owner with the upgrade opens the panel.
local function openBoard(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		deny(player, "That's not your sorting board.")
		return
	end
	local data = DataService.get(player)
	local board = boards[plotId]
	if not data or not board or not board.Parent then
		return
	end
	if not IronBoxService.hasBoard(data) then
		deny(player, "The sorting board comes with Pen Automation in the Tech shop.")
		return
	end
	Net.fire("OpenUI", player, "IronBox", { Box = board, Position = board:GetPivot().Position })
end

local function removeBoard(plotId: number)
	local board = boards[plotId]
	boards[plotId] = nil
	boardShows[plotId] = nil
	if board then
		board:Destroy()
	end
end

local function buildBoard(plotId: number): Model?
	local plot = PlotService.model(plotId)
	if not plot then
		return nil
	end
	local board = MachineBuilder.sortingBoard()
	board.Name = IronBoxService.BoardName
	-- streams in whole, like machines (the client's panel needs the model)
	board.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	board:SetAttribute("PlotId", plotId)
	board:PivotTo(PlotService.plotCFrame(plotId) * IronBoxService.boardPoint())
	local base = board.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = IronBoxService.BoardPromptName
	prompt.ActionText = "Keep List"
	prompt.ObjectText = "Sorting Board"
	-- its only prompt: F / Y, so it never hides behind the gate's "Open Pen"
	-- (G / B, a few steps away; one prompt per key shows). "Put In" (F / Y)
	-- at the gate only shows while you carry ore, and then the nearer wins.
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	-- like the pen's own prompts: PenController shows it on your plot only
	prompt:SetAttribute("PlotId", plotId)
	prompt:AddTag(PenService.PromptTag)
	prompt.Parent = base:FindFirstChild("Prompt") or base
	prompt.Triggered:Connect(function(player: Player)
		openBoard(player, plotId)
	end)
	board.Parent = PenService.yard(plotId) or plot
	boards[plotId] = board
	return board
end

--[[
	The player's board as their save says: built when they have the upgrade
	(and a plot), removed when not, repainted only when what it shows
	changed. Called when the plot is assigned, after an IronBoxAction, on a
	new discovery and when boardPresence sees the upgrade come or go.
]]
function IronBoxService.refreshBoard(player: Player)
	local plotId = PlotService.plotOf(player)
	if not plotId then
		return
	end
	local data = DataService.get(player)
	if not data or not IronBoxService.hasBoard(data) then
		if boards[plotId] then
			removeBoard(plotId)
		end
		return
	end
	local board: Model? = boards[plotId]
	if not board or not board.Parent then
		-- (a board something else took out of the world is replaced)
		removeBoard(plotId)
		board = buildBoard(plotId)
	end
	if not board then
		return
	end
	local info = IronBoxService.boardInfo(data)
	local key = boardKey(info)
	if boardShows[plotId] ~= key then
		boardShows[plotId] = key
		MachineBuilder.paintSortingBoard(board, info)
	end
end

-- The plot's sorting board (nil without one).
function IronBoxService.boardOf(plotId: number): Model?
	return boards[plotId]
end

-- On every save change: only whether the board should stand (O(1), no
-- ore loop); what it shows changes through refreshBoard's other callers.
local function boardPresence(player: Player)
	local plotId = PlotService.plotOf(player)
	if not plotId then
		return
	end
	local data = DataService.get(player)
	local want = data ~= nil and IronBoxService.hasBoard(data)
	local board: Model? = boards[plotId]
	local has = if board then board.Parent ~= nil else false
	if want ~= has then
		IronBoxService.refreshBoard(player)
	end
end

---------------------------------------------------------------- IronBoxAction

-- The keep settings changed: the player's boxes stop saying "pen full" (the
-- next kept item that can't fit says it again) and the board repaints.
local function keepChanged(player: Player)
	for machine in fullBoxes do
		if machine.Removed then
			fullBoxes[machine] = nil
		elseif machine.Owner == player then
			setPenFull(machine, false)
		end
	end
	IronBoxService.refreshBoard(player)
end

local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	local data = DataService.get(player)
	if not action or not data then
		return
	end
	if IronBoxService.apply(data, action, argArg) then
		DataService.changed(player)
		keepChanged(player)
	end
end

-- Every DataService.changed (many a second in a running factory): cheap.
local function onSaveChanged(player: Player)
	penRoomCheck(player)
	boardPresence(player)
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/IronBox.spec.luau).
IronBoxService._test = {
	action = onAction,
	open = openList,
	openBoard = openBoard,
	removeBoard = removeBoard,
	penRoomCheck = penRoomCheck,
	saveChanged = onSaveChanged,
	discovered = function(player: Player)
		IronBoxService.refreshBoard(player)
	end,
	setClock = function(fn: (() -> number)?)
		clock = fn or os.clock
	end,
	reset = function()
		clock = os.clock
		table.clear(lastDeny)
		table.clear(penFullAt)
		table.clear(penFullShown)
		table.clear(fullBoxes)
		for plotId in boards do
			removeBoard(plotId)
		end
	end,
}

function IronBoxService.init()
	assert(MachineData.ById[IronBoxService.MachineId], "IronBox missing from MachineData")
	MachineService.register(IronBoxService.MachineId, ProcessingService.sorterBehaviour(IronBoxService.sorter))
	Net.on("IronBoxAction", onAction)
	PlotService.onAssigned(function(player: Player)
		IronBoxService.refreshBoard(player)
	end)
	PlotService.onReleased(function(_, plotId: number)
		removeBoard(plotId)
	end)
	DataService.onChanged(onSaveChanged)
	-- a new ore can join the board's colours (only discovered ores show)
	Discovery.onDiscovered(function(player: Player)
		IronBoxService.refreshBoard(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDeny[player] = nil
		penFullAt[player] = nil
		penFullShown[player] = nil
		for machine in fullBoxes do
			if machine.Owner == player or machine.Removed then
				fullBoxes[machine] = nil
			end
		end
	end)
end

return IronBoxService
