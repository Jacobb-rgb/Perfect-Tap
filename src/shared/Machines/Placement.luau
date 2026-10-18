--[[
	Placement: pure placement rules, slot limits, the machine inventory
	ledger and the saved-layout cleaner. The build-mode ghost (client) and
	MachineService (server) use the same code, so they always agree.

	Entries are the saved tables in data.PlacedMachines: { Id, X, Z, R,
	In?, Out? }. In/Out are machine queues (see MachineLogic).

	Ledger rule: for every machine id, placed + MachineInventory stays the
	same across place, move and pickup. Nothing here yields, and a commit
	that fails changes nothing. The one exception is the inventory cap
	(MachineData.MaxInventory): a machine packed up past it is refunded at
	its Price instead (addInventory), so it is never lost.

	Chute cells (BaseLayout.Chutes, step 3) take belts only: any other
	machine whose footprint covers one is refused ("Chute") and moved off by
	sanitize like any other machine that doesn't fit (with the reason
	"Chute", so the player gets a chute toast).
]]

local BaseLayout = require(script.Parent.Parent.Config.BaseLayout)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local Grid = require(script.Parent.Grid)

local Placement = {}

export type Desc = ItemData.Desc
-- C: the machine's own setting (a whole number 1..9, e.g. a Sorter's threshold rarity)
export type Entry = { Id: string, X: number, Z: number, R: number, In: { Desc }?, Out: { Desc }?, C: number? }
export type Limits = { Machines: number, Conveyors: number }

-- Reason code -> text for the player (BuildResult.Reason is the code).
Placement.Reasons = {
	OutOfBounds = "Doesn't fit on your plot",
	Chute = "Only belts can go on a chute",
	Overlap = "Something is already there",
	NoMachineSlots = "All machine slots are used",
	NoConveyorSlots = "All belt slots are used",
	NoneOwned = "You don't have one to place",
	Busy = "Finish using it first",
	PenFull = "Make room in your Ore Pen for what's inside it first",
	TooFar = "Go to your forge to build",
	NoPlot = "You don't have a plot yet",
	NotYours = "That's not your machine",
	Invalid = "Something went wrong",
	UnknownMachine = "Can't place that",
	BadInput = "Can't place that",
} :: { [string]: string }

local CELLS = GameConfig.PlotCells

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v > -math.huge and v < math.huge
end

local function known(id: any): MachineData.Machine?
	if type(id) ~= "string" then
		return nil
	end
	return MachineData.ById[id]
end

-- Keys of every cell the footprint covers. Cells off the plot are left
-- out (their keys would clash with real cells).
function Placement.cells(id: string, x: number, z: number, r: number): { number }
	local w, d = Grid.footprint(id, r)
	local list = {}
	for cz = z, z + d - 1 do
		for cx = x, x + w - 1 do
			if cx >= 0 and cz >= 0 and cx < CELLS and cz < CELLS then
				table.insert(list, Grid.key(cx, cz))
			end
		end
	end
	return list
end

function Placement.inBounds(id: string, x: number, z: number, r: number): boolean
	local w, d = Grid.footprint(id, r)
	return x >= 0 and z >= 0 and x + w <= CELLS and z + d <= CELLS
end

-- Name of a chute cell (BaseLayout.Chutes) the footprint covers, or nil.
function Placement.chuteUnder(id: string, x: number, z: number, r: number): string?
	local w, d = Grid.footprint(id, r)
	for _, name in BaseLayout.ChuteNames do
		local cx, cz = BaseLayout.chuteCell(name)
		if cx >= x and cx < x + w and cz >= z and cz < z + d then
			return name
		end
	end
	return nil
end

-- May `id` stand at (x, z, r) as far as the chute cells go? (Belts may.)
function Placement.chuteAllows(id: string, x: number, z: number, r: number): boolean
	local info = known(id)
	return info ~= nil and (info.IsConveyor == true or Placement.chuteUnder(id, x, z, r) == nil)
end

-- Cell key -> entry covering it. Entries with an unknown Id are skipped;
-- `ignore` (a machine being moved) is left out. If saved entries overlap,
-- the earlier one keeps the cell.
function Placement.occupancy(entries: { Entry }, ignore: Entry?): { [number]: Entry }
	local map: { [number]: Entry } = {}
	for _, entry in entries do
		if entry ~= ignore and known(entry.Id) and isInt(entry.X) and isInt(entry.Z) and isInt(entry.R) then
			for _, k in Placement.cells(entry.Id, entry.X, entry.Z, entry.R) do
				if map[k] == nil then
					map[k] = entry
				end
			end
		end
	end
	return map
end

function Placement.limits(extraSlots: number, workshop: boolean): Limits
	return {
		Machines = MachineData.machineSlots(extraSlots, workshop),
		Conveyors = MachineData.conveyorSlots(workshop),
	}
end

-- Slots in use. Every machine without SlotFree takes a machine slot
-- (the Cleaning Station too); belts take belt slots. Unknown ids are skipped.
function Placement.counts(entries: { Entry }): (number, number)
	local machines, conveyors = 0, 0
	for _, entry in entries do
		local info = known(entry.Id)
		if info then
			if info.IsConveyor or info.IsPole then
				conveyors += 1 -- power poles use belt slots
			elseif not info.SlotFree then
				machines += 1
			end
		end
	end
	return machines, conveyors
end

-- Can `id` go at (x, z, r)? Checks, in order: UnknownMachine, BadInput,
-- OutOfBounds, Chute (only belts on chute cells), Overlap, then slots.
-- Slots are skipped when `limits` is nil or when moving (`ignore` set), so
-- a move never fails on slots.
function Placement.validate(
	entries: { Entry },
	id: string,
	x: number,
	z: number,
	r: number,
	limits: Limits?,
	ignore: Entry?
): (boolean, string?)
	local info = known(id)
	if not info then
		return false, "UnknownMachine"
	end
	if not isInt(x) or not isInt(z) or not isInt(r) or r < 0 or r > 3 then
		return false, "BadInput"
	end
	if not Placement.inBounds(id, x, z, r) then
		return false, "OutOfBounds"
	end
	if not Placement.chuteAllows(id, x, z, r) then
		return false, "Chute"
	end
	local occupied = Placement.occupancy(entries, ignore)
	for _, k in Placement.cells(id, x, z, r) do
		if occupied[k] then
			return false, "Overlap"
		end
	end
	if limits and not ignore then
		local machines, conveyors = Placement.counts(entries)
		if info.IsConveyor or info.IsPole then
			if conveyors >= limits.Conveyors then
				return false, "NoConveyorSlots"
			end
		elseif not info.SlotFree and machines >= limits.Machines then
			return false, "NoMachineSlots"
		end
	end
	return true, nil
end

-- Origin cell for a footprint around a cursor cell: the cursor lands on the
-- middle cell (the lower one for even sizes), then the footprint is pushed
-- back onto the plot.
function Placement.clampOrigin(id: string, cellX: number, cellZ: number, r: number): (number, number)
	local w, d = Grid.footprint(id, r)
	local cx = if cellX == cellX then math.floor(cellX) else 0
	local cz = if cellZ == cellZ then math.floor(cellZ) else 0
	local x = math.clamp(cx - math.floor((w - 1) / 2), 0, math.max(0, CELLS - w))
	local z = math.clamp(cz - math.floor((d - 1) / 2), 0, math.max(0, CELLS - d))
	return x, z
end

local function inventoryOf(data: { [string]: any }): { [string]: number }
	local inventory = data.MachineInventory
	if type(inventory) ~= "table" then
		inventory = {}
		data.MachineInventory = inventory
	end
	return inventory
end

-- Puts `n` machines of `id` into the inventory, at most MachineData.MaxInventory
-- of one type. Any above the cap are refunded at their Price into Coins (not
-- TotalEarned: it isn't income), so a machine is never lost. Returns how many
-- were refunded.
function Placement.addInventory(data: { [string]: any }, id: string, n: number): number
	if not (isInt(n) and n > 0) then
		return 0
	end
	local inventory = inventoryOf(data)
	local have = inventory[id]
	local current = if type(have) == "number" and have == have and have > 0 then math.floor(have) else 0
	local room = math.max(0, MachineData.MaxInventory - current)
	local added = math.min(n, room)
	local refunded = n - added
	if added > 0 then
		inventory[id] = current + added
	end
	if refunded > 0 then
		local info = known(id)
		local coins = tonumber(data.Coins) or 0
		data.Coins = (if coins == coins then coins else 0) + (if info then info.Price else 0) * refunded
	end
	return refunded
end

-- Place one machine from the inventory. Returns the new saved entry.
function Placement.commitPlace(data: { [string]: any }, id: string, x: number, z: number, r: number, limits: Limits): (Entry?, string?)
	local inventory = data.MachineInventory
	local owned = if type(inventory) == "table" and type(id) == "string" then inventory[id] else nil
	if type(owned) ~= "number" or owned < 1 then
		return nil, "NoneOwned"
	end
	local ok, code = Placement.validate(data.PlacedMachines, id, x, z, r, limits, nil)
	if not ok then
		return nil, code
	end
	inventory[id] = if owned - 1 >= 1 then owned - 1 else nil
	local entry: Entry = { Id = id, X = x, Z = z, R = r }
	table.insert(data.PlacedMachines, entry)
	return entry, nil
end

-- Move or turn a placed machine in place (its In/Out stay with it).
function Placement.commitMove(data: { [string]: any }, entry: Entry, x: number, z: number, r: number): (boolean, string?)
	if not table.find(data.PlacedMachines, entry) then
		return false, "Invalid"
	end
	local ok, code = Placement.validate(data.PlacedMachines, entry.Id, x, z, r, nil, entry)
	if not ok then
		return false, code
	end
	entry.X, entry.Z, entry.R = x, z, r
	return true, nil
end

-- Pack a placed machine back into the inventory. Drain its In/Out first
-- (MachineLogic.drain); this only moves the machine itself. The second
-- result is 1 when the inventory already held MachineData.MaxInventory of
-- that type and the machine was refunded at its Price instead (addInventory).
function Placement.commitPickup(data: { [string]: any }, entry: Entry): (boolean, number)
	local index = table.find(data.PlacedMachines, entry)
	if not index then
		return false, 0
	end
	table.remove(data.PlacedMachines, index)
	return true, Placement.addInventory(data, entry.Id, 1)
end

-- An item that has to leave a machine during layout repair goes to Storage,
-- or is paid out at full value when Storage is full (like ItemService.stash).
local function spill(data: { [string]: any }, desc: any)
	if type(desc) ~= "table" then
		return
	end
	local storage = data.Storage
	if type(storage) ~= "table" then
		storage = {}
		data.Storage = storage
	end
	if #storage < GameConfig.MaxStoredItems then
		table.insert(storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
	else
		local value = 0
		if type(desc.K) == "string" and type(desc.O) == "string" then
			value = ItemData.value(desc.K, desc.O, desc.G, desc.R)
		end
		data.Coins = (tonumber(data.Coins) or 0) + value
		data.TotalEarned = (tonumber(data.TotalEarned) or 0) + value
	end
end

-- Keeps the first `max` items of a queue and spills the rest. Empty -> nil.
local function trim(data: { [string]: any }, list: any, max: number): { Desc }?
	if type(list) ~= "table" then
		return nil
	end
	for i = #list, max + 1, -1 do
		spill(data, table.remove(list, i))
	end
	if #list == 0 then
		return nil
	end
	return list
end

-- Repairs a loaded layout (MachineService runs it before spawning).
-- In saved order: an unknown Id is kept and skipped. A machine that is off
-- the plot, stands on a chute cell (anything but a belt) or overlaps an
-- earlier one goes back to the inventory (addInventory: refunded past the
-- cap) and its In/Out spill into Storage. Queues longer than allowed are
-- trimmed the same way. Slot limits are never enforced here.
-- Returns the displaced ids and, at the same index, why each one moved:
-- "BadInput" | "OutOfBounds" | "Chute" | "Overlap" (Reasons codes).
function Placement.sanitize(data: { [string]: any }): ({ string }, { string })
	local displaced: { string } = {}
	local reasons: { string } = {}
	local list = data.PlacedMachines
	if type(list) ~= "table" then
		data.PlacedMachines = {}
		return displaced, reasons
	end
	local kept: { Entry } = {}
	local occupied: { [number]: boolean } = {}
	for _, entry in list do
		local info = type(entry) == "table" and known(entry.Id)
		if not info then
			table.insert(kept, entry)
			continue
		end
		local reason: string? = nil
		if not (isInt(entry.X) and isInt(entry.Z) and isInt(entry.R) and entry.R >= 0 and entry.R <= 3) then
			reason = "BadInput"
		elseif not Placement.inBounds(entry.Id, entry.X, entry.Z, entry.R) then
			reason = "OutOfBounds"
		elseif not Placement.chuteAllows(entry.Id, entry.X, entry.Z, entry.R) then
			reason = "Chute"
		end
		local cells: { number } = if reason == nil then Placement.cells(entry.Id, entry.X, entry.Z, entry.R) else {}
		for _, k in cells do
			if occupied[k] then
				reason = "Overlap"
				break
			end
		end
		if reason == nil then
			for _, k in cells do
				occupied[k] = true
			end
			entry.In = trim(data, entry.In, GameConfig.MachineIntakeQueue)
			entry.Out = trim(data, entry.Out, MachineData.MaxOutBuffer)
			table.insert(kept, entry)
		else
			for _, queue in { entry.In, entry.Out } do
				if type(queue) == "table" then
					for _, desc in queue do
						spill(data, desc)
					end
				end
			end
			entry.In, entry.Out = nil, nil
			Placement.addInventory(data, entry.Id, 1)
			table.insert(displaced, entry.Id)
			table.insert(reasons, reason)
		end
	end
	-- rewrite the list in place so references to kept entries stay valid
	table.clear(list)
	for i, entry in kept do
		list[i] = entry
	end
	return displaced, reasons
end

return Placement
