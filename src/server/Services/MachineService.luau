--[[
	MachineService: machines placed on plots, each linked to its saved entry.

	- Saved in data.PlacedMachines as { Id, X, Z, R, In?, Out? } (min grid
	  cell, rotation 0-3, input queue, finished outputs). Every runtime
	  machine keeps m.Entry = that very table, so autosaves, leaving and
	  shutdowns save machine contents mid-job with no extra step.
	- New players get MachineData.StarterKit once. In Studio sessions whose
	  saves live in memory, GameConfig.StudioDevKit is added with it.
	- Machines spawn when the plot is assigned (hooked in start(), after
	  every behaviour registered in init()), and vanish when the player
	  leaves ('Unload' writes no data: the contents are already in the save).
	- place / move / pickup go through the shared Placement ledger, so the
	  server and the build-mode ghost always agree. Pickup drains the
	  machine's contents into Storage.
	- Behaviour per machine type is registered by other services with
	  MachineService.register(machineId, behaviour). Item hand-ins go through
	  canAccept -> insert (synchronous, so an item is never in two places).
	- A 10 Hz tick runs behaviour ticks and pushes finished items (Entry.Out)
	  out of the machine's front: straight into the machine standing there
	  when it takes them, otherwise as a loose item. Output pauses when the
	  front machine refuses or the owner has too many loose items.
	- The tick walks an ACTIVE list, never every placed machine: a machine
	  stays on it while it has finished items in Out or one of its tick
	  behaviours says it is busy (Behaviour.busy; a tick hook without busy
	  always ticks). Spawning, register, an item handed in, pushOut and move
	  wake a machine (MachineService.wake); MachineService.follow wakes a
	  follower (the Robot Arm) whenever its leader wakes. Belts, poles and
	  other machines without a tick hook or an intake never join it. A
	  machine leaves the list at the end of a visit that found nothing to do.
	- Status (why the output waits): a blocked reason shows at once; it
	  clears once nothing more waits, or when the NEXT item gets out too
	  (showBlocked / outputFlowed), so a machine that is blocked on every
	  other retry keeps its reason instead of flipping every second.
	- The loose-item cap check counts each owner's loose items once per tick
	  pass (plus what the pass spawned), not once per emit.
	- MachineAction remote: actions on your own machines (onAction).
	- emitSide: the same hand-over or loose pop toward a side output cell
	  (Splitter, Sorter: LogisticsService); the tick never uses it.
	- Levels (docs/plans/PLATFORMS_PLAN.md): an entry with L = 1 stands on
	  a platform's deck, MachineData.DeckHeight up (its model, attribute
	  GridL). The plot index is keyed by cell and level (atCell); deckAt
	  says which platform holds a cell's deck, atHeight finds the machine an
	  item at some height is on. Emits, side outputs and the Robot Arm's
	  neighbours look on the machine's own level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperConfig = require(Shared.Config.DropperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local Grid = require(Shared.Machines.Grid)
local Placement = require(Shared.Machines.Placement)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)

local MachineService = {}

export type Desc = MachineLogic.Desc
export type Reason = MachineLogic.Reason
export type Entry = Placement.Entry
export type Limits = Placement.Limits
-- how an item arrives: dropped/thrown into the hopper, fed by a belt,
-- loaded from your hands (Put In prompt), or handed over by another machine
export type Via = "Drop" | "Belt" | "Hand" | "Machine"
export type RemoveReason = "Unload" | "Pickup" | "Refresh" -- Refresh: the model is rebuilt (upgrade look), the data stays
export type EmitResult = "Handed" | "Spawned" | "Blocked"

export type PlacedMachine = {
	Model: Model,
	Id: string,
	Owner: Player,
	PlotId: number,
	X: number,
	Z: number,
	R: number,
	L: number, -- level: 0 = the ground, 1 = a platform's deck
	State: { [string]: any }, -- per-type runtime state (timers, sessions...)
	Entry: Entry, -- the saved table in data.PlacedMachines
	Info: MachineData.Machine,
	Removed: boolean, -- true once the model is gone (unloaded or packed up)
}

export type Behaviour = {
	spawned: ((PlacedMachine) -> ...any)?,
	removed: ((PlacedMachine, RemoveReason) -> ...any)?,
	moved: ((PlacedMachine) -> ...any)?,
	-- only machines with canAccept + insert take items
	canAccept: ((PlacedMachine, Desc, number, Via) -> (boolean, Reason?))?,
	insert: ((PlacedMachine, Desc, number, Via) -> ...any)?,
	tick: ((PlacedMachine, number) -> ...any)?,
	-- does the tick still have something to do (a queue, a running job, a
	-- timer)? false lets the machine leave the active list until something
	-- wakes it; without it a tick hook runs on every tick
	busy: ((PlacedMachine, number) -> boolean)?,
}

type PlotIndex = {
	Machines: { PlacedMachine }, -- in saved order
	-- Placement.key (cell and level) -> machine covering the cell; on the
	-- ground a belt under a platform wins over the platform's legs
	Cells: { [number]: PlacedMachine },
	Decks: { [number]: PlacedMachine }, -- Grid.key -> the platform whose deck covers it
}

local CELLS = GameConfig.PlotCells
-- the client HUD may still be starting when the plot spawns
local TOAST_DELAY = 3
local WARN_COOLDOWN = 10

local placed: { [Model]: PlacedMachine } = {}
local behaviours: { [string]: { Behaviour } } = {}
local plots: { [number]: PlotIndex } = {}
local layoutCallbacks: { (Player, number) -> ...any } = {}
local layoutPending: { [Player]: number } = {}
local actions: { [string]: (Player, PlacedMachine, any) -> ...any } = {}
local lastWarn: { [string]: number } = {}
local NO_HOOKS: { Behaviour } = table.freeze({})

-- the tick's active list (see the header): an array the tick walks, and a set
local active: { PlacedMachine } = {}
local activeSet: { [PlacedMachine]: boolean } = {}
-- leader -> the machines that wake whenever it wakes (MachineService.follow)
local followers: { [PlacedMachine]: { [PlacedMachine]: boolean } } = {}
-- behaviours with a tick hook per machine type (rebuilt after register)
local tickCache: { [string]: { Behaviour } } = {}
-- layout version per plot: goes up on every change of which machine covers
-- which cell (and on register), so neighbour caches know when to look again
local versions: { [number]: number } = {}
-- loose items per owner during one tick pass (looseNow)
local passLoose: { [number]: number } = {}
local inPass = false
-- counters for the tests and the benchmark
local stats = { Visits = 0, Hooks = 0 }

-- Tick errors would repeat 10 times a second; warn about each one now and then.
local function warnThrottled(key: string, message: string)
	local now = os.clock()
	if now - (lastWarn[key] or -math.huge) >= WARN_COOLDOWN then
		lastWarn[key] = now
		warn(message)
	end
end

local function hooksOf(machineId: string): { Behaviour }
	return behaviours[machineId] or NO_HOOKS
end

-- The behaviours of a machine type that have a tick hook.
local function tickHooksOf(machineId: string): { Behaviour }
	local cached = tickCache[machineId]
	if cached then
		return cached
	end
	local list: { Behaviour } = {}
	for _, behaviour in hooksOf(machineId) do
		if behaviour.tick then
			table.insert(list, behaviour)
		end
	end
	tickCache[machineId] = list
	return list
end

local function bumpVersion(plotId: number)
	versions[plotId] = (versions[plotId] or 0) + 1
end

local function hasOut(entry: Entry): boolean
	local out = entry.Out
	return out ~= nil and #out > 0
end

local function addActive(machine: PlacedMachine)
	if not activeSet[machine] then
		activeSet[machine] = true
		table.insert(active, machine)
	end
end

--[[
	Puts a machine on the tick's active list (no-op when it is on it or
	gone), and its followers with it. Safe during a tick pass: the pass
	visits machines added meanwhile too.
]]
function MachineService.wake(machine: PlacedMachine)
	if machine.Removed then
		return
	end
	addActive(machine)
	local list = followers[machine]
	if list then
		for follower in list do
			if follower.Removed then
				list[follower] = nil
			else
				addActive(follower)
			end
		end
	end
end

-- `follower` wakes whenever `leader` wakes (until unfollow or either goes).
function MachineService.follow(follower: PlacedMachine, leader: PlacedMachine)
	local list = followers[leader]
	if not list then
		list = {}
		followers[leader] = list
	end
	list[follower] = true
end

function MachineService.unfollow(follower: PlacedMachine, leader: PlacedMachine)
	local list = followers[leader]
	if list then
		list[follower] = nil
		if next(list) == nil then
			followers[leader] = nil
		end
	end
end

-- Is the machine on the tick's active list (it has work, or just woke)?
function MachineService.isActive(machine: PlacedMachine): boolean
	return activeSet[machine] == true
end

-- Goes up whenever which machine covers which cell of the plot changes
-- (place, move, pickup, spawn, unload) or a behaviour is registered.
function MachineService.layoutVersion(plotId: number): number
	return versions[plotId] or 0
end

-- The behaviour that takes items for this machine type (first one with
-- both canAccept and insert), if any.
local function intakeOf(machineId: string): Behaviour?
	for _, behaviour in hooksOf(machineId) do
		if behaviour.canAccept and behaviour.insert then
			return behaviour
		end
	end
	return nil
end

local function callSpawned(machine: PlacedMachine, behaviour: Behaviour)
	local hook = behaviour.spawned
	if hook then
		local ok, err = pcall(hook, machine)
		if not ok then
			warn(`[MachineService] {machine.Id} spawned hook failed: {err}`)
		end
	end
end

local function callRemoved(machine: PlacedMachine, reason: RemoveReason)
	for _, behaviour in hooksOf(machine.Id) do
		local hook = behaviour.removed
		if hook then
			local ok, err = pcall(hook, machine, reason)
			if not ok then
				warn(`[MachineService] {machine.Id} removed hook failed: {err}`)
			end
		end
	end
end

local function callMoved(machine: PlacedMachine)
	for _, behaviour in hooksOf(machine.Id) do
		local hook = behaviour.moved
		if hook then
			local ok, err = pcall(hook, machine)
			if not ok then
				warn(`[MachineService] {machine.Id} moved hook failed: {err}`)
			end
		end
	end
end

---------------------------------------------------------------- plot index

local function onPlot(gx: number, gz: number): boolean
	return gx >= 0 and gz >= 0 and gx < CELLS and gz < CELLS
end

local function isPlatform(machine: PlacedMachine): boolean
	return machine.Info.Behaviour == "Platform"
end

local function indexCells(index: PlotIndex, machine: PlacedMachine)
	local platform = isPlatform(machine)
	-- deck keys come after the ground keys (Placement.key)
	local offset = if machine.L == 1 then CELLS * CELLS else 0
	for _, k in Placement.cells(machine.Id, machine.X, machine.Z, machine.R) do
		local had = index.Cells[k + offset]
		if had == nil or (not platform and offset == 0 and isPlatform(had)) then
			index.Cells[k + offset] = machine
		end
		if platform and index.Decks[k] == nil then
			index.Decks[k] = machine
		end
	end
end

local function indexOf(plotId: number): PlotIndex
	local index = plots[plotId]
	if not index then
		index = { Machines = {}, Cells = {}, Decks = {} }
		plots[plotId] = index
	end
	return index
end

-- Rebuilds a plot's machine list (saved order) and cell map.
local function rebuildPlot(plotId: number)
	local list: { PlacedMachine } = {}
	for _, machine in placed do
		if machine.PlotId == plotId and not machine.Removed then
			table.insert(list, machine)
		end
	end
	local owner = PlotService.ownerOf(plotId)
	local data = owner and DataService.get(owner)
	if data then
		local order: { [any]: number } = {}
		for i, entry in data.PlacedMachines do
			order[entry] = i
		end
		table.sort(list, function(a, b)
			return (order[a.Entry] or math.huge) < (order[b.Entry] or math.huge)
		end)
	end
	local index: PlotIndex = { Machines = list, Cells = {}, Decks = {} }
	for _, machine in list do
		indexCells(index, machine)
	end
	plots[plotId] = index
	bumpVersion(plotId)
end

-- Layout listeners run once per player per frame, after the change is done.
local function fireLayout(player: Player, plotId: number)
	local wasPending = layoutPending[player] ~= nil
	layoutPending[player] = plotId
	if wasPending then
		return
	end
	task.defer(function()
		local id = layoutPending[player]
		layoutPending[player] = nil
		if id == nil then
			return
		end
		for _, callback in layoutCallbacks do
			local ok, err = pcall(callback, player, id)
			if not ok then
				warn("[MachineService] layout listener failed: " .. tostring(err))
			end
		end
	end)
end

local function layoutChanged(player: Player, plotId: number)
	rebuildPlot(plotId)
	DataService.changed(player)
	fireLayout(player, plotId)
end

---------------------------------------------------------------- registry and lookups

-- Adds behaviour for a machine type. Machines already placed get its
-- spawned hook right away.
function MachineService.register(machineId: string, behaviour: Behaviour)
	local list = behaviours[machineId]
	if not list then
		list = {}
		behaviours[machineId] = list
	end
	table.insert(list, behaviour)
	tickCache[machineId] = nil
	local wakes = behaviour.tick ~= nil or (behaviour.canAccept ~= nil and behaviour.insert ~= nil)
	local touched: { [number]: Player } = {}
	for _, machine in placed do
		if machine.Id == machineId and not machine.Removed then
			callSpawned(machine, behaviour)
			touched[machine.PlotId] = machine.Owner
			if wakes then
				MachineService.wake(machine)
			end
		end
	end
	-- the intake index depends on which machines take items
	for plotId, owner in touched do
		bumpVersion(plotId)
		fireLayout(owner, plotId)
	end
end

-- Does this machine take items (a behaviour with canAccept and insert)?
function MachineService.hasIntake(machine: PlacedMachine): boolean
	return intakeOf(machine.Id) ~= nil
end

function MachineService.get(model: Instance?): PlacedMachine?
	local node = model
	while node do
		if node:IsA("Model") and placed[node :: Model] then
			return placed[node :: Model]
		end
		node = node.Parent
	end
	return nil
end

function MachineService.ofPlayer(player: Player): { PlacedMachine }
	local list = {}
	for _, machine in placed do
		if machine.Owner == player then
			table.insert(list, machine)
		end
	end
	return list
end

function MachineService.all(): { [Model]: PlacedMachine }
	return placed
end

-- Machines on a plot, in saved order (a copy).
function MachineService.ofPlot(plotId: number): { PlacedMachine }
	local index = plots[plotId]
	return if index then table.clone(index.Machines) else {}
end

-- The machine covering a grid cell of a plot on `level` (nil / 0 = the
-- ground, 1 = a deck), if any. On the ground a belt under a platform
-- comes before the platform's legs.
function MachineService.atCell(plotId: number, gx: number, gz: number, level: number?): PlacedMachine?
	local index = plots[plotId]
	if not index or not onPlot(gx, gz) then
		return nil
	end
	return index.Cells[Placement.key(gx, gz, level)]
end

-- The platform whose deck covers a grid cell of a plot, if any.
function MachineService.deckAt(plotId: number, gx: number, gz: number): PlacedMachine?
	local index = plots[plotId]
	if not index or not onPlot(gx, gz) then
		return nil
	end
	return index.Decks[Grid.key(gx, gz)]
end

-- Items at least this high over the pad (plot-local Y) are up at deck level.
MachineService.DeckItemY = MachineData.DeckHeight - 1

--[[
	The machine an item at plot-local height `localY` over cell (gx, gz) is
	on: up at deck level the one on the deck (nil over a bare deck: the item
	lies on it, not on the belt under it), else the ground one (an item high
	up a Belt Lift is still on the lift: no deck covers its cells).
]]
function MachineService.atHeight(plotId: number, gx: number, gz: number, localY: number): PlacedMachine?
	if localY >= MachineService.DeckItemY then
		local up = MachineService.atCell(plotId, gx, gz, 1)
		if up or MachineService.deckAt(plotId, gx, gz) then
			return up
		end
	end
	return MachineService.atCell(plotId, gx, gz, 0)
end

-- World CFrame of a named attachment on the machine's Base
-- (= its WorldCFrame, worked out from the Base so Lune tests can run it).
function MachineService.point(machine: PlacedMachine, name: string): CFrame?
	local base = machine.Model.PrimaryPart
	local attachment = base and base:FindFirstChild(name)
	if base and attachment and attachment:IsA("Attachment") then
		return base.CFrame * attachment.CFrame
	end
	return nil
end

-- Sets model attributes, writing only the ones that changed.
function MachineService.setAttrs(machine: PlacedMachine, attrs: { [string]: any })
	local model = machine.Model
	for name, value in attrs do
		if model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
	end
end

-- One attribute, written only when it changed (no table: for hot paths).
function MachineService.setAttr(machine: PlacedMachine, name: string, value: any)
	local model = machine.Model
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Shows why the machine's output waits ("OutputBlocked", "TooManyItems"),
-- at once; a clear still pending (outputFlowed) is called off.
function MachineService.showBlocked(machine: PlacedMachine, reason: string)
	machine.State.StatusClear = nil
	if not machine.Removed then
		MachineService.setAttr(machine, "Status", reason)
	end
end

--[[
	An item got out of the machine. With `drained` (nothing more waits to
	leave) the status clears now; otherwise it clears when the next item
	gets out too, and a block before that keeps it shown (showBlocked), so
	a front that takes every other item doesn't flip the status every retry.
]]
function MachineService.outputFlowed(machine: PlacedMachine, drained: boolean)
	if machine.Removed then
		return
	end
	local state = machine.State
	if drained or state.StatusClear then
		state.StatusClear = nil
		MachineService.setAttr(machine, "Status", "")
		return
	end
	local status = machine.Model:GetAttribute("Status")
	if type(status) == "string" and status ~= "" then
		state.StatusClear = true
	end
end

-- Runs after every layout change on a plot (place, move, pickup, spawn,
-- unload), at most once per player per frame.
function MachineService.onLayoutChanged(callback: (Player, number) -> ...any)
	table.insert(layoutCallbacks, callback)
end

-- Handler for MachineAction(model, action, arg). The dispatcher has already
-- checked that the model is one of the caller's machines and that they are
-- within MachineUseRange; `arg` is raw client data.
function MachineService.onAction(action: string, handler: (Player, PlacedMachine, any) -> ...any)
	if actions[action] then
		warn("[MachineService] action registered twice: " .. action)
	end
	actions[action] = handler
end

function MachineService.limits(player: Player): Limits
	local data = DataService.get(player)
	local upgrades = data and data.Upgrades
	local extra = if type(upgrades) == "table" then tonumber(upgrades.ExtraSlots) or 0 else 0
	return Placement.limits(extra, Perks.has(player, "Workshop"))
end

-- Slots in use: (machines, conveyors).
function MachineService.usage(player: Player): (number, number)
	local data = DataService.get(player)
	if not data then
		return 0, 0
	end
	return Placement.counts(data.PlacedMachines)
end

---------------------------------------------------------------- spawning

local function spawnMachine(player: Player, plotId: number, entry: Entry): PlacedMachine?
	local info = MachineData.ById[entry.Id]
	if not info then
		return nil
	end
	local plotModel = PlotService.model(plotId)
	local folder = plotModel and plotModel:FindFirstChild("Machines")
	if not folder then
		warn(`[MachineService] plot {plotId} has no Machines folder`)
		return nil
	end
	-- the upgrade look follows the machine type's Speed level (KitMachines crystals); a
	-- machine with tiers (the Furnace) works and looks like the player's tier of it
	local data = DataService.get(player)
	local upgrades = data and data.MachineUpgrades
	local own = if type(upgrades) == "table" then upgrades[entry.Id] else nil
	local level = MachineData.lookLevel(if type(own) == "table" then own.Speed else 0)
	local tier = MachineData.tierOf(upgrades, entry.Id)
	info = MachineData.info(entry.Id, tier)
	local model = MachineBuilder.build(entry.Id, level, tier)
	local deck = Placement.levelOf(entry)
	model:PivotTo(PlotService.footprintCFrame(plotId, entry.Id, entry.X, entry.Z, entry.R, deck))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("GridX", entry.X)
	model:SetAttribute("GridZ", entry.Z)
	model:SetAttribute("Rotation", entry.R)
	model:SetAttribute("GridL", deck)
	-- a machine with tiers (the Furnace): the tier it works at (clients: MachineData.info)
	model:SetAttribute("Tier", if tier > 0 then tier else nil)
	model:SetAttribute("OutCount", if entry.Out then #entry.Out else 0)
	model:SetAttribute("Status", "")
	model:AddTag("Machine")
	model.Parent = folder
	local machine: PlacedMachine = {
		Model = model,
		Id = entry.Id,
		Owner = player,
		PlotId = plotId,
		X = entry.X,
		Z = entry.Z,
		R = entry.R,
		L = deck,
		State = {},
		Entry = entry,
		Info = info,
		Removed = false,
	}
	placed[model] = machine
	local index = indexOf(plotId)
	table.insert(index.Machines, machine)
	indexCells(index, machine)
	bumpVersion(plotId)
	for _, behaviour in hooksOf(entry.Id) do
		callSpawned(machine, behaviour)
	end
	-- belts, poles and the like (no tick hook, no intake) never tick
	if #tickHooksOf(entry.Id) > 0 or intakeOf(entry.Id) ~= nil or hasOut(entry) then
		MachineService.wake(machine)
	end
	return machine
end

-- Takes the model out of the world (hooks first). Touches no data.
local function detach(machine: PlacedMachine, reason: RemoveReason)
	if machine.Removed then
		return
	end
	callRemoved(machine, reason)
	machine.Removed = true
	placed[machine.Model] = nil
	-- the tick drops it from the active array on its next visit
	activeSet[machine] = nil
	followers[machine] = nil
	bumpVersion(machine.PlotId)
	machine.Model:Destroy()
end

--[[
	Rebuilds the models of every placed machine of type `machineId` the
	player owns (after a Tech shop upgrade: the upgrade look). Hooks see a
	"Refresh" removal and a fresh spawn; queues and settings stay in the
	save (a job in progress starts over).
]]
function MachineService.refreshType(player: Player, machineId: string)
	local plotId = PlotService.plotOf(player)
	if not plotId then
		return
	end
	for _, machine in MachineService.ofPlayer(player) do
		if machine.Id == machineId then
			detach(machine, "Refresh")
			spawnMachine(player, plotId, machine.Entry)
		end
	end
	rebuildPlot(plotId)
	-- hoppers, belt feeds and cables point at the new models
	fireLayout(player, plotId)
end

-- Speed modifiers (PowerService): each returns a multiplier for a machine (1 = normal).
local speedModifiers: { (PlacedMachine) -> number } = {}

function MachineService.addSpeedModifier(modifier: (PlacedMachine) -> number)
	table.insert(speedModifiers, modifier)
end

-- How fast this machine works right now (1 = normal, below 1 = slower).
-- Job times are divided by it.
function MachineService.speedFactor(machine: PlacedMachine): number
	local factor = 1
	for _, modifier in speedModifiers do
		local ok, value = pcall(modifier, machine)
		if ok and type(value) == "number" and value == value and value > 0 then
			factor *= value
		end
	end
	return factor
end

local function devKit(): GameConfig.DevKit?
	local kit = GameConfig.StudioDevKit
	if kit == false or not RunService:IsStudio() or not DataService.isInMemory() then
		return nil
	end
	return kit :: GameConfig.DevKit
end

local function notifyLater(player: Player, text: string)
	task.delay(TOAST_DELAY, function()
		if player.Parent then
			Net.fire("Notify", player, { Text = text, Kind = "Info" })
		end
	end)
end

local function spawnAll(player: Player, plotId: number)
	local data = DataService.get(player)
	if not data or not player.Parent or PlotService.plotOf(player) ~= plotId then
		return
	end
	-- entries that already have a machine (spawnAll ran before) are skipped
	local spawned: { [any]: boolean } = {}
	for _, machine in MachineService.ofPlayer(player) do
		spawned[machine.Entry] = true
	end
	if type(data.MachineInventory) ~= "table" then
		data.MachineInventory = {}
	end
	if not data.StarterKitGiven then
		data.StarterKitGiven = true
		for _, entry in MachineData.StarterKit do
			table.insert(data.PlacedMachines, { Id = entry.Id, X = entry.X, Z = entry.Z, R = entry.R })
		end
		-- Studio test layout: only for in-memory saves, never on live servers
		local kit = devKit()
		if kit then
			for _, entry in kit.Layout do
				table.insert(data.PlacedMachines, { Id = entry.Id, X = entry.X, Z = entry.Z, R = entry.R })
			end
			for id, count in kit.Inventory do
				data.MachineInventory[id] = math.max(tonumber(data.MachineInventory[id]) or 0, count)
			end
			print(`[MachineService] Studio dev kit added for {player.Name}`)
		end
	end
	-- repair the saved layout (off the plot, on a chute, overlapping); never enforces slot limits
	local displaced, reasons = Placement.sanitize(data)
	if next(spawned) then
		-- a machine whose entry was just sent back to the inventory goes too
		local kept: { [any]: boolean } = {}
		for _, entry in data.PlacedMachines do
			kept[entry] = true
		end
		for _, machine in MachineService.ofPlayer(player) do
			if not kept[machine.Entry] then
				detach(machine, "Pickup")
			end
		end
	end
	for _, entry in data.PlacedMachines do
		if spawned[entry] then
			continue
		elseif type(entry) == "table" and MachineData.ById[entry.Id] then
			spawnMachine(player, plotId, entry)
		else
			local id = if type(entry) == "table" then tostring(entry.Id) else typeof(entry)
			warn(`[MachineService] {player.Name} has an unknown machine {id} (kept in the save)`)
		end
	end
	layoutChanged(player, plotId)
	-- machines that stood where a chute now is (step 3) get their own toast
	local offChute, didntFit = {}, {}
	for i, id in displaced do
		table.insert(if reasons[i] == "Chute" then offChute else didntFit, id)
	end
	local function nameOf(id: string): string
		local info = MachineData.ById[id]
		return if info then info.Name else id
	end
	if #didntFit == 1 then
		notifyLater(player, `{nameOf(didntFit[1])} didn't fit and is waiting in your Build menu.`)
	elseif #didntFit > 1 then
		notifyLater(player, `{#didntFit} machines didn't fit and are waiting in your Build menu.`)
	end
	if #offChute == 1 then
		notifyLater(
			player,
			`A chute now sits where your {nameOf(offChute[1])} stood (only belts can go on it). It is waiting in your Build menu.`
		)
	elseif #offChute > 1 then
		notifyLater(
			player,
			`{#offChute} machines stood where the new chutes are (only belts can go on them). They are waiting in your Build menu.`
		)
	end
end

local function unload(player: Player, plotId: number)
	for _, machine in MachineService.ofPlayer(player) do
		detach(machine, "Unload")
	end
	rebuildPlot(plotId)
	fireLayout(player, plotId)
end

---------------------------------------------------------------- place / move / pickup

-- Places a machine from the player's inventory on `level` (nil / 0 = the
-- ground, 1 = a deck). Returns the machine or a Placement.Reasons code.
function MachineService.place(player: Player, machineId: string, x: number, z: number, r: number, level: number?): (PlacedMachine?, string?)
	local plotId = PlotService.plotOf(player)
	local data = DataService.get(player)
	if not plotId or not data then
		return nil, "NoPlot"
	end
	local entry, code = Placement.commitPlace(data, machineId, x, z, r, MachineService.limits(player), level)
	if not entry then
		return nil, code
	end
	local machine = spawnMachine(player, plotId, entry)
	if not machine then
		-- roll the ledger back: the machine goes back into the inventory
		Placement.commitPickup(data, entry)
		return nil, "Invalid"
	end
	layoutChanged(player, plotId)
	return machine, nil
end

-- Moves or turns a placed machine, onto `level` (nil / 0 = the ground,
-- 1 = a deck). Its contents and running job stay.
function MachineService.move(machine: PlacedMachine, x: number, z: number, r: number, level: number?): (boolean, string?)
	if machine.Removed then
		return false, "Invalid"
	end
	if machine.Model:GetAttribute("Busy") == true then
		return false, "Busy"
	end
	local data = DataService.get(machine.Owner)
	if not data then
		return false, "Invalid"
	end
	local ok, code = Placement.commitMove(data, machine.Entry, x, z, r, level)
	if not ok then
		return false, code
	end
	machine.X, machine.Z, machine.R = machine.Entry.X, machine.Entry.Z, machine.Entry.R
	machine.L = Placement.levelOf(machine.Entry)
	machine.Model:PivotTo(PlotService.footprintCFrame(machine.PlotId, machine.Id, machine.X, machine.Z, machine.R, machine.L))
	MachineService.setAttrs(machine, { GridX = machine.X, GridZ = machine.Z, Rotation = machine.R, GridL = machine.L })
	layoutChanged(machine.Owner, machine.PlotId)
	callMoved(machine)
	-- a new front cell: a blocked output may get out now
	if #tickHooksOf(machine.Id) > 0 or hasOut(machine.Entry) then
		MachineService.wake(machine)
	end
	return true, nil
end

-- Packs a machine back into the inventory. Its queued and finished items
-- go to Storage (paid out at full value when Storage is full).
function MachineService.pickup(machine: PlacedMachine): (boolean, string?)
	if machine.Removed then
		return false, "Invalid"
	end
	if machine.Model:GetAttribute("Busy") == true then
		return false, "Busy"
	end
	local player = machine.Owner
	local data = DataService.get(player)
	if not data or not table.find(data.PlacedMachines, machine.Entry) then
		return false, "Invalid"
	end
	-- a platform with things on its deck stays (nothing is left floating)
	local free, why = Placement.canPickup(data.PlacedMachines, machine.Entry)
	if not free then
		return false, why
	end
	-- the contents must fit the Ore Pen (packing a machine up is no way past
	-- the pen's paid capacity; nothing is lost: the player makes room first)
	-- (a dropper's Drop never goes to the pen: DropperConfig, storeDesc "Lost")
	local contents = 0
	for _, queue in { machine.Entry.In, machine.Entry.Out } do
		if queue then
			for _, desc in queue do
				if not DropperConfig.isDrop(desc) then
					contents += 1
				end
			end
		end
	end
	if contents > 0 and #data.Storage + contents > ItemService.penCapacity(data) then
		return false, "PenFull"
	end
	-- hooks first (sessions end, the vise item is stashed), then the contents
	detach(machine, "Pickup")
	local stored, sold = 0, 0
	for _, desc in MachineLogic.drain(machine.Entry) do
		local result = ItemService.storeDesc(player, desc)
		if result == "Stored" then
			stored += 1
		elseif result == "Sold" then
			sold += 1
		end
	end
	local _, refunded = Placement.commitPickup(data, machine.Entry)
	layoutChanged(player, machine.PlotId)
	if refunded > 0 then
		-- the Build menu already held MachineData.MaxInventory of these
		Net.fire("Notify", player, {
			Text = `Your Build menu is full of {machine.Info.Name}s: this one was refunded ({Format.money(machine.Info.Price)}).`,
			Kind = "Info",
		})
	end
	local total = stored + sold
	if total > 0 then
		local items = if total == 1 then "1 item" else `{total} items`
		local text = if sold == 0
			then `{items} from your {machine.Info.Name} went to your Ore Pen.`
			else `{items} from your {machine.Info.Name}: {stored} went to your Ore Pen, {sold} sold (pen full).`
		Net.fire("Notify", player, { Text = text, Kind = "Info" })
	end
	return true, nil
end

-- Takes a machine out of the world without touching its save (used when
-- the plot is released). Use pickup() to pack a machine up.
function MachineService.remove(machine: PlacedMachine, reason: RemoveReason)
	if machine.Removed then
		return
	end
	detach(machine, reason)
	rebuildPlot(machine.PlotId)
	fireLayout(machine.Owner, machine.PlotId)
end

---------------------------------------------------------------- items in and out

-- Would the machine take this item right now? 'Full' and 'Busy' mean wait;
-- 'Wrong', 'Foreign' and 'Mixed' mean push it back out. For 'Belt' and
-- 'Machine' the caller has already checked ConveyorLogic.faceAllowed.
function MachineService.canAccept(machine: PlacedMachine, desc: Desc, ownerUserId: number, via: Via): (boolean, Reason?)
	if machine.Removed then
		return false, "Busy"
	end
	if not MachineLogic.isValidDesc(desc) then
		return false, "Wrong"
	end
	local behaviour = intakeOf(machine.Id)
	local check = behaviour and behaviour.canAccept
	if not check then
		return false, "Wrong"
	end
	local ok, accepted, reason = pcall(check, machine, desc, ownerUserId, via)
	if not ok then
		warnThrottled(machine.Id .. ".canAccept", `[MachineService] {machine.Id} canAccept failed: {accepted}`)
		return false, "Busy"
	end
	if accepted then
		return true, nil
	end
	return false, (reason :: Reason?) or "Wrong"
end

-- Hands an accepted item to the machine's behaviour. If that fails, the
-- item comes back out next to the machine instead of vanishing.
local function deliver(machine: PlacedMachine, desc: Desc, ownerUserId: number, via: Via)
	local behaviour = intakeOf(machine.Id)
	local insert = behaviour and behaviour.insert
	local ok, err: any = false, "no insert hook"
	if insert then
		ok, err = pcall(insert, machine, desc, ownerUserId, via)
	end
	-- new work: the tick looks at it again
	MachineService.wake(machine)
	if not ok then
		warn(`[MachineService] {machine.Id} insert failed: {err}`)
		local cf = MachineService.point(machine, "Output") or (machine.Model:GetPivot() + Vector3.new(0, 4, 0))
		ItemService.spawnDesc(desc, ownerUserId, cf, nil, true)
	end
end

-- Puts a physical item into a machine: check, absorb, insert, with no
-- yield in between. Returns (false, reason) when the machine refuses.
function MachineService.insertRecord(machine: PlacedMachine, record: ItemService.ItemRecord, via: Via): (boolean, Reason?)
	if record.State == "Consumed" then
		return false, "Busy"
	end
	local desc = ItemService.descOf(record)
	local ok, reason = MachineService.canAccept(machine, desc, record.Owner, via)
	if not ok then
		return false, reason :: Reason?
	end
	ItemService.absorb(record)
	deliver(machine, desc, record.Owner, via)
	return true, nil
end

-- Puts an item descriptor into a machine (machine-to-machine handoff).
-- true means the caller no longer holds the item.
function MachineService.insertDesc(machine: PlacedMachine, desc: Desc, ownerUserId: number, via: Via): (boolean, Reason?)
	local ok, reason = MachineService.canAccept(machine, desc, ownerUserId, via)
	if not ok then
		return false, reason :: Reason?
	end
	deliver(machine, desc, ownerUserId, via)
	return true, nil
end

-- Queues a finished item to leave the machine's front (the tick sends it).
function MachineService.pushOut(machine: PlacedMachine, desc: Desc)
	local player = machine.Owner
	local data = DataService.get(player)
	if machine.Removed and not (data and table.find(data.PlacedMachines, machine.Entry)) then
		-- packed up meanwhile: the item goes to Storage instead
		ItemService.storeDesc(player, desc)
		return
	end
	local out = machine.Entry.Out or {}
	machine.Entry.Out = out
	table.insert(out, desc)
	if not machine.Removed then
		MachineService.setAttr(machine, "OutCount", #out)
		MachineService.wake(machine)
	end
	DataService.changed(player)
end

-- Loose items the owner has on / around bases now (ore lying in the mine
-- doesn't stall the factory). During a tick pass each owner is counted
-- once (ItemService.looseCount walks their items) plus what the pass spawned:
-- nothing else takes loose items away or adds them while the pass runs.
local function looseNow(owner: number): number
	if not inPass then
		return ItemService.looseCount(owner, "Base")
	end
	local n = passLoose[owner]
	if n == nil then
		n = ItemService.looseCount(owner, "Base")
		passLoose[owner] = n
	end
	return n :: number
end

local function blockedBy(machine: PlacedMachine, reason: string, quiet: boolean?): (EmitResult, ItemService.ItemRecord?, string?)
	if not quiet then
		MachineService.showBlocked(machine, reason)
	end
	return "Blocked", nil, reason
end

-- The loose pop shared by emit and emitSide (server physics from the start,
-- so belts and hoppers never wait on a client).
local function popLoose(desc: Desc, owner: number, cf: CFrame, velocity: Vector3): (EmitResult, ItemService.ItemRecord?, string?)
	local record = ItemService.spawnDesc(desc, owner, cf, velocity, true)
	if not record then
		return "Blocked", nil, nil
	end
	local n = if inPass then passLoose[owner] else nil
	if n then
		passLoose[owner] = n + 1
	end
	return "Spawned", record, nil
end

--[[
	Sends one finished item out of the machine's front:
	- 'Handed': the machine in the output cell took it (its face must take
	  items from that side).
	- 'Spawned': it popped out as a loose item (returned as the 2nd value).
	- 'Blocked': the front machine refused it ('OutputBlocked'), or the owner
	  has too many loose items ('TooManyItems'). The caller keeps the item.
	  The reason comes back as the 3rd value and shows as the Status at once,
	  unless `quiet` (the caller decides what to show).
]]
function MachineService.emit(machine: PlacedMachine, desc: Desc, quiet: boolean?): (EmitResult, ItemService.ItemRecord?, string?)
	if machine.Removed then
		return "Blocked", nil, nil
	end
	local owner = machine.Owner.UserId
	local ox, oz = Grid.outputCell(machine.Id, machine.X, machine.Z, machine.R)
	if ox and oz then
		local target = MachineService.atCell(machine.PlotId, ox, oz, machine.L)
		if target and target ~= machine and not target.Info.IsConveyor then
			-- the item comes from the source's own front cell
			local dx, dz = Grid.dir(machine.R)
			if ConveyorLogic.faceAllowed(target.Entry, ox - dx, oz - dz) then
				if MachineService.insertDesc(target, desc, owner, "Machine") then
					return "Handed", nil, nil
				end
				return blockedBy(machine, "OutputBlocked", quiet)
			end
		end
	end
	if looseNow(owner) >= GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom then
		return blockedBy(machine, "TooManyItems", quiet)
	end
	local pivot = machine.Model:GetPivot()
	local cf = MachineService.point(machine, "Output") or pivot
	-- (a dropper's Drop falls straight down from its nozzle onto the belt under it)
	local velocity = if machine.Info.Behaviour == "Dropper"
		then Vector3.new(0, -2, 0)
		else pivot.LookVector * GameConfig.OutputPop.Forward + Vector3.new(0, GameConfig.OutputPop.Up, 0)
	return popLoose(desc, owner, cf, velocity)
end

-- How an item leaves a side output when nothing takes it: sideways onto the
-- belt in the side cell (studs per second out of the side, and up).
MachineService.SidePop = { Out = 3, Up = 1.5 }

--[[
	Sends one item out of a side output (MachineData SideOutputs: Splitter,
	Sorter), like emit() but toward Grid.sideOutputCell: `side` -1 = the
	machine's left (OutputL), 1 = its right (OutputR, Grid.right).
	- 'Handed': the non-belt machine in the side cell took it (its face must
	  take items from the side the item comes from: the source's own cell
	  on that side of its front row).
	- 'Spawned': it popped out as a loose item at the OutputL / OutputR
	  attachment, moving sideways onto the belt there (SidePop).
	- 'Blocked': the machine in the side cell refused it ('OutputBlocked'),
	  or the owner has too many loose items ('TooManyItems'). The caller
	  keeps the item. Reason and `quiet` as in emit().
]]
function MachineService.emitSide(
	machine: PlacedMachine,
	desc: Desc,
	side: number,
	quiet: boolean?
): (EmitResult, ItemService.ItemRecord?, string?)
	if machine.Removed then
		return "Blocked", nil, nil
	end
	local s = if side < 0 then -1 else 1
	local owner = machine.Owner.UserId
	local sx, sz = Grid.sideOutputCell(machine.Id, machine.X, machine.Z, machine.R, s)
	local target = MachineService.atCell(machine.PlotId, sx, sz, machine.L)
	if target and target ~= machine and not target.Info.IsConveyor then
		-- the item comes from the source's own cell beside the side cell
		local rx, rz = Grid.right(machine.R)
		if ConveyorLogic.faceAllowed(target.Entry, sx - s * rx, sz - s * rz) then
			if MachineService.insertDesc(target, desc, owner, "Machine") then
				return "Handed", nil, nil
			end
			return blockedBy(machine, "OutputBlocked", quiet)
		end
	end
	if looseNow(owner) >= GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom then
		return blockedBy(machine, "TooManyItems", quiet)
	end
	local pivot = machine.Model:GetPivot()
	local cf = MachineService.point(machine, if s < 0 then "OutputL" else "OutputR")
		or pivot * CFrame.new(Grid.sideOutputLocal(machine.Id, s))
	local pop = MachineService.SidePop
	local velocity = pivot.RightVector * (s * pop.Out) + Vector3.new(0, pop.Up, 0)
	return popLoose(desc, owner, cf, velocity)
end

---------------------------------------------------------------- tick

-- Does a machine still need the tick after a visit? Finished items to send,
-- or a tick behaviour that says it's busy (one without `busy` always is).
local function stillBusy(machine: PlacedMachine, hooks: { Behaviour }, now: number): boolean
	if machine.Removed then
		return false
	end
	if hasOut(machine.Entry) then
		return true
	end
	local busy = false
	for _, behaviour in hooks do
		local check = behaviour.busy
		if not check then
			busy = true
			break
		end
		local ok, result = pcall(check, machine, now)
		if not ok then
			warnThrottled(machine.Id .. ".busy", `[MachineService] {machine.Id} busy check failed: {result}`)
		end
		if not ok or result then
			busy = true
			break
		end
	end
	if not busy and machine.State.StatusClear then
		-- nothing waits to leave any more (the Robot Arm took it, junk dropped)
		MachineService.outputFlowed(machine, true)
	end
	return busy
end

-- One machine's turn: its tick hooks, then one finished item out of its front.
local function visit(machine: PlacedMachine, now: number, dirty: { [Player]: boolean }): boolean
	if machine.Removed then
		return false
	end
	stats.Visits += 1
	local hooks = tickHooksOf(machine.Id)
	for _, behaviour in hooks do
		local hook = behaviour.tick
		if hook then
			stats.Hooks += 1
			local ok, err = pcall(hook, machine, now)
			if not ok then
				warnThrottled(machine.Id .. ".tick", `[MachineService] {machine.Id} tick failed: {err}`)
			end
		end
	end
	local state = machine.State
	local out = machine.Entry.Out
	if not machine.Removed and out and #out > 0 and now >= (state.NextEmit or 0) then
		local desc = out[1]
		if not MachineLogic.isValidDesc(desc) then
			-- junk from a damaged save: drop it so the machine doesn't jam
			MachineLogic.popOut(machine.Entry)
			warn(`[MachineService] dropped a bad item from {machine.Owner.Name}'s {machine.Id}`)
			dirty[machine.Owner] = true
		elseif MachineService.emit(machine, desc) == "Blocked" then
			state.NextEmit = now + GameConfig.OutputRetry
		else
			MachineLogic.popOut(machine.Entry)
			state.NextEmit = now
			local left = machine.Entry.Out
			MachineService.setAttr(machine, "OutCount", if left then #left else 0)
			MachineService.outputFlowed(machine, left == nil)
			dirty[machine.Owner] = true
		end
	end
	return stillBusy(machine, hooks, now)
end

-- One pass over the active list. Machines woken during the pass are visited
-- in it too; a machine with nothing to do leaves the list (swap-remove).
local function tickAll()
	local now = os.clock()
	local dirty: { [Player]: boolean } = {}
	table.clear(passLoose)
	inPass = true
	local i = 1
	while i <= #active do
		local machine = active[i]
		if visit(machine, now, dirty) then
			i += 1
		else
			activeSet[machine] = nil
			local last = #active
			active[i] = active[last]
			active[last] = nil
		end
	end
	inPass = false
	for player in dirty do
		DataService.changed(player)
	end
end

---------------------------------------------------------------- MachineAction remote

local function onMachineAction(player: Player, target: any, action: any, arg: any)
	local plotId = PlotService.plotOf(player)
	local plotModel = plotId and PlotService.model(plotId)
	local folder = plotModel and plotModel:FindFirstChild("Machines")
	if not folder then
		return
	end
	local model = Guard.instance(target, "Model", folder)
	local machine = model and MachineService.get(model)
	if not machine or machine.Removed or machine.Owner ~= player then
		return
	end
	local root = Guard.rootPart(player)
	if not root or (root.Position - machine.Model:GetPivot().Position).Magnitude > GameConfig.MachineUseRange then
		return
	end
	local name = Guard.string(action, 24)
	local handler = name and actions[name]
	if not handler then
		return
	end
	local ok, err = pcall(handler, player, machine, arg)
	if not ok then
		warn(`[MachineService] action {name} from {player.Name} failed: {err}`)
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/MachineService.spec.luau).
MachineService._test = {
	spawnAll = spawnAll,
	tick = tickAll,
	action = onMachineAction,
	-- forget every machine, behaviour and listener (no hooks run)
	reset = function()
		table.clear(placed)
		table.clear(behaviours)
		table.clear(plots)
		table.clear(layoutCallbacks)
		table.clear(layoutPending)
		table.clear(actions)
		table.clear(speedModifiers)
		table.clear(active)
		table.clear(activeSet)
		table.clear(followers)
		table.clear(tickCache)
		table.clear(versions)
		table.clear(passLoose)
		inPass = false
		stats.Visits = 0
		stats.Hooks = 0
	end,
	-- tick counters since the last reset: machine visits and tick hook calls
	stats = function(): { Visits: number, Hooks: number }
		return { Visits = stats.Visits, Hooks = stats.Hooks }
	end,
	activeCount = function(): number
		local n = 0
		for machine in activeSet do
			if not machine.Removed then
				n += 1
			end
		end
		return n
	end,
}

function MachineService.init()
	Net.on("MachineAction", onMachineAction)
	PlotService.onReleased(unload)
end

function MachineService.start()
	-- Spawning waits until every service has run init(), so all behaviours
	-- (and their prompts) are registered before the first machine appears.
	PlotService.onAssigned(spawnAll)
	while true do
		task.wait(GameConfig.MachineTick)
		local ok, err = pcall(function()
			tickAll()
		end)
		if not ok then
			warnThrottled("tickAll", "[MachineService] tick failed: " .. tostring(err))
		end
	end
end

return MachineService
