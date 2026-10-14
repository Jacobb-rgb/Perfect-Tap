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
	- MachineAction remote: actions on your own machines (onAction).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local Grid = require(Shared.Machines.Grid)
local Placement = require(Shared.Machines.Placement)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Net = require(Shared.Net)
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
export type RemoveReason = "Unload" | "Pickup"
export type EmitResult = "Handed" | "Spawned" | "Blocked"

export type PlacedMachine = {
	Model: Model,
	Id: string,
	Owner: Player,
	PlotId: number,
	X: number,
	Z: number,
	R: number,
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
}

type PlotIndex = {
	Machines: { PlacedMachine }, -- in saved order
	Cells: { [number]: PlacedMachine }, -- Grid.key -> machine covering the cell
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

-- Tick errors would repeat 10 times a second; warn about each one now and then.
local function warnThrottled(key: string, message: string)
	local now = os.clock()
	if now - (lastWarn[key] or -math.huge) >= WARN_COOLDOWN then
		lastWarn[key] = now
		warn(message)
	end
end

local function hooksOf(machineId: string): { Behaviour }
	return behaviours[machineId] or {}
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

local function indexCells(index: PlotIndex, machine: PlacedMachine)
	for _, k in Placement.cells(machine.Id, machine.X, machine.Z, machine.R) do
		if index.Cells[k] == nil then
			index.Cells[k] = machine
		end
	end
end

local function indexOf(plotId: number): PlotIndex
	local index = plots[plotId]
	if not index then
		index = { Machines = {}, Cells = {} }
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
	local index: PlotIndex = { Machines = list, Cells = {} }
	for _, machine in list do
		indexCells(index, machine)
	end
	plots[plotId] = index
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
	local touched: { [number]: Player } = {}
	for _, machine in placed do
		if machine.Id == machineId and not machine.Removed then
			callSpawned(machine, behaviour)
			touched[machine.PlotId] = machine.Owner
		end
	end
	-- the intake index depends on which machines take items
	for plotId, owner in touched do
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

-- The machine covering a grid cell of a plot, if any.
function MachineService.atCell(plotId: number, gx: number, gz: number): PlacedMachine?
	local index = plots[plotId]
	if not index or not onPlot(gx, gz) then
		return nil
	end
	return index.Cells[Grid.key(gx, gz)]
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
	local model = MachineBuilder.build(entry.Id)
	model:PivotTo(PlotService.footprintCFrame(plotId, entry.Id, entry.X, entry.Z, entry.R))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("GridX", entry.X)
	model:SetAttribute("GridZ", entry.Z)
	model:SetAttribute("Rotation", entry.R)
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
		State = {},
		Entry = entry,
		Info = info,
		Removed = false,
	}
	placed[model] = machine
	local index = indexOf(plotId)
	table.insert(index.Machines, machine)
	indexCells(index, machine)
	for _, behaviour in hooksOf(entry.Id) do
		callSpawned(machine, behaviour)
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
	machine.Model:Destroy()
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
	-- repair the saved layout (off the plot, overlapping); never enforces slot limits
	local displaced = Placement.sanitize(data)
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
	if #displaced == 1 then
		local info = MachineData.ById[displaced[1]]
		notifyLater(player, `{if info then info.Name else displaced[1]} didn't fit and is waiting in your Build menu.`)
	elseif #displaced > 1 then
		notifyLater(player, `{#displaced} machines didn't fit and are waiting in your Build menu.`)
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

-- Places a machine from the player's inventory. Returns the machine or a
-- Placement.Reasons code.
function MachineService.place(player: Player, machineId: string, x: number, z: number, r: number): (PlacedMachine?, string?)
	local plotId = PlotService.plotOf(player)
	local data = DataService.get(player)
	if not plotId or not data then
		return nil, "NoPlot"
	end
	local entry, code = Placement.commitPlace(data, machineId, x, z, r, MachineService.limits(player))
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

-- Moves or turns a placed machine. Its contents and running job stay.
function MachineService.move(machine: PlacedMachine, x: number, z: number, r: number): (boolean, string?)
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
	local ok, code = Placement.commitMove(data, machine.Entry, x, z, r)
	if not ok then
		return false, code
	end
	machine.X, machine.Z, machine.R = machine.Entry.X, machine.Entry.Z, machine.Entry.R
	machine.Model:PivotTo(PlotService.footprintCFrame(machine.PlotId, machine.Id, machine.X, machine.Z, machine.R))
	MachineService.setAttrs(machine, { GridX = machine.X, GridZ = machine.Z, Rotation = machine.R })
	layoutChanged(machine.Owner, machine.PlotId)
	callMoved(machine)
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
	Placement.commitPickup(data, machine.Entry)
	layoutChanged(player, machine.PlotId)
	local total = stored + sold
	if total > 0 then
		local items = if total == 1 then "1 item" else `{total} items`
		local text = if sold == 0
			then `{items} from your {machine.Info.Name} went to Storage.`
			else `{items} from your {machine.Info.Name}: {stored} went to Storage, {sold} sold (storage full).`
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
		MachineService.setAttrs(machine, { OutCount = #out })
	end
	DataService.changed(player)
end

--[[
	Sends one finished item out of the machine's front:
	- 'Handed': the machine in the output cell took it (its face must take
	  items from that side).
	- 'Spawned': it popped out as a loose item (returned as the 2nd value).
	- 'Blocked': the front machine refused it ('OutputBlocked'), or the owner
	  has too many loose items ('TooManyItems'). The caller keeps the item.
]]
function MachineService.emit(machine: PlacedMachine, desc: Desc): (EmitResult, ItemService.ItemRecord?)
	if machine.Removed then
		return "Blocked", nil
	end
	local owner = machine.Owner.UserId
	local ox, oz = Grid.outputCell(machine.Id, machine.X, machine.Z, machine.R)
	if ox and oz then
		local target = MachineService.atCell(machine.PlotId, ox, oz)
		if target and target ~= machine and not target.Info.IsConveyor then
			-- the item comes from the source's own front cell
			local dx, dz = Grid.dir(machine.R)
			if ConveyorLogic.faceAllowed(target.Entry, ox - dx, oz - dz) then
				if MachineService.insertDesc(target, desc, owner, "Machine") then
					return "Handed", nil
				end
				MachineService.setAttrs(machine, { Status = "OutputBlocked" })
				return "Blocked", nil
			end
		end
	end
	if ItemService.looseCount(owner) >= GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom then
		MachineService.setAttrs(machine, { Status = "TooManyItems" })
		return "Blocked", nil
	end
	local pivot = machine.Model:GetPivot()
	local cf = MachineService.point(machine, "Output") or pivot
	local velocity = pivot.LookVector * GameConfig.OutputPop.Forward + Vector3.new(0, GameConfig.OutputPop.Up, 0)
	-- the server keeps output physics, so belts and hoppers never wait on a client
	local record = ItemService.spawnDesc(desc, owner, cf, velocity, true)
	if not record then
		return "Blocked", nil
	end
	return "Spawned", record
end

---------------------------------------------------------------- tick

local function tickAll()
	local now = os.clock()
	local dirty: { [Player]: boolean } = {}
	for _, machine in placed do
		if machine.Removed then
			continue
		end
		for _, behaviour in hooksOf(machine.Id) do
			local hook = behaviour.tick
			if hook then
				local ok, err = pcall(hook, machine, now)
				if not ok then
					warnThrottled(machine.Id .. ".tick", `[MachineService] {machine.Id} tick failed: {err}`)
				end
			end
		end
		local out = machine.Entry.Out
		if machine.Removed or not out or #out == 0 or now < (machine.State.NextEmit or 0) then
			continue
		end
		local desc = out[1]
		if not MachineLogic.isValidDesc(desc) then
			-- junk from a damaged save: drop it so the machine doesn't jam
			MachineLogic.popOut(machine.Entry)
			warn(`[MachineService] dropped a bad item from {machine.Owner.Name}'s {machine.Id}`)
			dirty[machine.Owner] = true
			continue
		end
		local result = MachineService.emit(machine, desc)
		if result == "Blocked" then
			machine.State.NextEmit = now + GameConfig.OutputRetry
		else
			MachineLogic.popOut(machine.Entry)
			machine.State.NextEmit = now
			local left = machine.Entry.Out
			MachineService.setAttrs(machine, { OutCount = if left then #left else 0, Status = "" })
			dirty[machine.Owner] = true
		end
	end
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
