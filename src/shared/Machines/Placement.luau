--[[
	Placement: pure placement rules, slot limits, the machine inventory
	ledger and the saved-layout cleaner. The build-mode ghost (client) and
	MachineService (server) use the same code, so they always agree.

	Entries are the saved tables in data.PlacedMachines: { Id, X, Z, R,
	In?, Out?, C?, L? }. In/Out are machine queues (see MachineLogic).

	Ledger rule: for every machine id, placed + MachineInventory stays the
	same across place, move and pickup. Nothing here yields, and a commit
	that fails changes nothing. The one exception is the inventory cap
	(MachineData.MaxInventory): a machine packed up past it is refunded at
	its Price instead (addInventory), so it is never lost.

	Chute cells (BaseLayout.Chutes, step 3) take belts only: any other
	machine whose footprint covers one is refused ("Chute") and moved off by
	sanitize like any other machine that doesn't fit (with the reason
	"Chute", so the player gets a chute toast).

	Levels (docs/plans/PLATFORMS_PLAN.md): Entry.L is nil (or 0) on the
	ground, 1 on a deck (MachineData.DeckHeight up). Occupancy is keyed by
	cell and level (Placement.key).
	  Platform   (Behaviour "Platform", 2x2) stands on the ground. Its cells
	             are its legs on the ground: flat belts (Conveyor, Express
	             Conveyor) may run there, no other ground machine may
	             ("UnderDeck"). The same cells are deck cells one level up.
	  level 1    every footprint cell must be a deck cell (one platform or
	             several side by side, "NoDeck") and free on the deck.
	             Platforms and slopes never go on a deck ("BadInput").
	  Belt Lift  (Slope "Up", 1x3, ground): stands outside every deck (its
	             cells are ground cells like any machine's); the cell in front
	             of its high end (its front) must be a deck cell ("DeckEdge").
	  Slide      (Slope "Down", 1x3, ground): the same, with the cell behind
	             its high end (its back).
	  A platform with anything on its deck (or a Lift / Slide reaching it)
	  can't be packed up or moved off its cells ("DeckInUse"; turning it in
	  place is fine): nothing on it moves with it, nothing is left floating.
	sanitize drops junk levels (the entry stands on the ground) and sends a
	deck entry whose platform is gone (or a Lift / Slide that lost its deck)
	back to the inventory ("NoDeck" / "DeckEdge").
]]

local BaseLayout = require(script.Parent.Parent.Config.BaseLayout)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local DropperConfig = require(script.Parent.Parent.Config.DropperConfig)
local Grid = require(script.Parent.Grid)

local Placement = {}

export type Desc = ItemData.Desc
-- C: the machine's own setting (a whole number 1..9, e.g. a Sorter's threshold rarity)
-- L: the level (nil / 0 = the ground, 1 = a platform's deck)
export type Entry = { Id: string, X: number, Z: number, R: number, In: { Desc }?, Out: { Desc }?, C: number?, L: number? }
export type Limits = { Machines: number, Conveyors: number }

-- Reason code -> text for the player (BuildResult.Reason is the code).
Placement.Reasons = {
	OutOfBounds = "Doesn't fit on your plot",
	Chute = "Only belts can go on a chute",
	Overlap = "Something is already there",
	NoMachineSlots = "All machine slots are used",
	NoConveyorSlots = "All belt slots are used",
	DropperLimit = `Your plot holds {DropperConfig.MaxPlaced} droppers at most`,
	LaserLimit = `Your plot holds {DropperConfig.MaxLasers} Money Lasers at most`,
	NoneOwned = "You don't have one to place",
	Busy = "Finish using it first",
	PenFull = "Make room in your Ore Pen for what's inside it first",
	TooFar = "Go to your forge to build",
	NoPlot = "You don't have a plot yet",
	NotYours = "That's not your machine",
	Invalid = "Something went wrong",
	UnknownMachine = "Can't place that",
	BadInput = "Can't place that",
	NoDeck = "That needs a platform under it",
	UnderDeck = "Only belts fit under a platform",
	DeckEdge = "Its top end must reach a platform's edge",
	DeckInUse = "Clear the platform first",
} :: { [string]: string }

local CELLS = GameConfig.PlotCells
-- the deck level's keys come after every ground key (Placement.key)
local LEVEL_STRIDE = CELLS * CELLS

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v > -math.huge and v < math.huge
end

local function known(id: any): MachineData.Machine?
	if type(id) ~= "string" then
		return nil
	end
	return MachineData.ById[id]
end

local function onPlot(x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < CELLS and z < CELLS
end

-- An entry's level: 1 on a deck, 0 for anything else (nil, 0, junk).
function Placement.levelOf(entry: Entry): number
	return if entry.L == 1 then 1 else 0
end

-- The key of cell (x, z) on `level` (ground keys are Grid.key).
function Placement.key(x: number, z: number, level: number?): number
	return Grid.key(x, z) + (if level == 1 then LEVEL_STRIDE else 0)
end

-- Is `id` a platform (a deck on legs)?
function Placement.isPlatform(id: string): boolean
	local info = known(id)
	return info ~= nil and info.Behaviour == "Platform"
end

-- "Up" (Belt Lift), "Down" (Slide) or nil for anything that isn't a slope.
function Placement.slopeOf(id: string): ("Up" | "Down")?
	local info = known(id)
	return if info then info.Slope else nil
end

-- May `id` share a ground cell with a platform's legs? (Flat belts only.)
function Placement.fitsUnderDeck(id: string): boolean
	local info = known(id)
	return info ~= nil and info.IsConveyor == true and info.Slope == nil
end

-- May `id` stand on a deck? (Anything but platforms and slopes.)
function Placement.fitsOnDeck(id: string): boolean
	local info = known(id)
	return info ~= nil and info.Behaviour ~= "Platform" and info.Slope == nil
end

-- The deck cell a Belt Lift's front / a Slide's back must be (raw numbers,
-- maybe off the plot), or nil for anything that isn't a slope.
function Placement.deckEdgeCell(id: string, x: number, z: number, r: number): (number?, number?)
	local slope = Placement.slopeOf(id)
	if not slope then
		return nil, nil
	end
	return Grid.endCell(id, x, z, r, if slope == "Up" then 1 else -1)
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

-- May `id` stand at (x, z, r) as far as the chute cells go? (Flat belts
-- may; a Lift / Slide is no chute belt: a Source spawns onto a flat one.)
function Placement.chuteAllows(id: string, x: number, z: number, r: number): boolean
	local info = known(id)
	return info ~= nil and (Placement.fitsUnderDeck(id) or Placement.chuteUnder(id, x, z, r) == nil)
end

local function usable(entry: Entry, ignore: Entry?): boolean
	return entry ~= ignore and known(entry.Id) ~= nil and isInt(entry.X) and isInt(entry.Z) and isInt(entry.R)
end

--[[
	Cell key (Placement.key: cell and level) -> the entry covering it.
	Entries with an unknown Id are skipped; `ignore` (a machine being moved)
	is left out. If saved entries overlap, the earlier one keeps the cell,
	except that a belt under a platform keeps its ground cell from the
	platform's legs (decks() has the platforms).
]]
function Placement.occupancy(entries: { Entry }, ignore: Entry?): { [number]: Entry }
	local map: { [number]: Entry } = {}
	for _, entry in entries do
		if usable(entry, ignore) then
			local level = Placement.levelOf(entry)
			local offset = if level == 1 then LEVEL_STRIDE else 0
			local over = level == 0 and not Placement.isPlatform(entry.Id)
			for _, k in Placement.cells(entry.Id, entry.X, entry.Z, entry.R) do
				local had = map[k + offset]
				if had == nil or (over and Placement.isPlatform(had.Id)) then
					map[k + offset] = entry
				end
			end
		end
	end
	return map
end

-- Grid.key -> the platform whose deck covers the cell (platforms on the
-- ground; `ignore` left out; the earlier one wins in a damaged save).
function Placement.decks(entries: { Entry }, ignore: Entry?): { [number]: Entry }
	local map: { [number]: Entry } = {}
	for _, entry in entries do
		if usable(entry, ignore) and Placement.levelOf(entry) == 0 and Placement.isPlatform(entry.Id) then
			for _, k in Placement.cells(entry.Id, entry.X, entry.Z, entry.R) do
				if map[k] == nil then
					map[k] = entry
				end
			end
		end
	end
	return map
end

-- Ground cells: the platforms' legs and everything else (Grid.key -> entry).
local function groundOf(entries: { Entry }, ignore: Entry?): ({ [number]: Entry }, { [number]: Entry })
	local platforms: { [number]: Entry } = {}
	local others: { [number]: Entry } = {}
	for _, entry in entries do
		if usable(entry, ignore) and Placement.levelOf(entry) == 0 then
			local map = if Placement.isPlatform(entry.Id) then platforms else others
			for _, k in Placement.cells(entry.Id, entry.X, entry.Z, entry.R) do
				if map[k] == nil then
					map[k] = entry
				end
			end
		end
	end
	return platforms, others
end

--[[
	The ground rules for `id` on `cells` (Grid keys): nothing else on a
	cell, except a flat belt and a platform's legs sharing one. `platforms`
	/ `others` are the ground maps (groundOf). nil when it fits, else the
	Reasons code ("Overlap" | "UnderDeck").
]]
local function groundConflict(id: string, cells: { number }, platforms: { [number]: Entry }, others: { [number]: Entry }): string?
	local platform = Placement.isPlatform(id)
	local under = Placement.fitsUnderDeck(id)
	for _, k in cells do
		local other = others[k]
		if other and not (platform and Placement.fitsUnderDeck(other.Id)) then
			return "Overlap"
		end
		if platforms[k] then
			if platform then
				return "Overlap"
			elseif not under then
				return "UnderDeck"
			end
		end
	end
	return nil
end

-- A Lift / Slide's high end must touch a deck cell (decks: Grid.key -> platform).
local function edgeOk(id: string, x: number, z: number, r: number, decks: { [number]: Entry }): boolean
	local ex, ez = Placement.deckEdgeCell(id, x, z, r)
	if not ex or not ez then
		return true
	end
	return onPlot(ex, ez) and decks[Grid.key(ex, ez)] ~= nil
end

--[[
	Is anything using this platform's deck: an entry on it (level 1 on one
	of its cells) or a Belt Lift / Slide whose high end reaches it? Then it
	can't be packed up or moved away (DeckInUse). false for anything that
	isn't a platform.
]]
function Placement.deckInUse(entries: { Entry }, platform: Entry): boolean
	if not usable(platform, nil) or not Placement.isPlatform(platform.Id) or Placement.levelOf(platform) ~= 0 then
		return false
	end
	local mine: { [number]: boolean } = {}
	for _, k in Placement.cells(platform.Id, platform.X, platform.Z, platform.R) do
		mine[k] = true
	end
	for _, entry in entries do
		if entry ~= platform and usable(entry, nil) then
			if Placement.levelOf(entry) == 1 then
				for _, k in Placement.cells(entry.Id, entry.X, entry.Z, entry.R) do
					if mine[k] then
						return true
					end
				end
			else
				local ex, ez = Placement.deckEdgeCell(entry.Id, entry.X, entry.Z, entry.R)
				if ex and ez and onPlot(ex, ez) and mine[Grid.key(ex, ez)] then
					return true
				end
			end
		end
	end
	return false
end

-- May this placed entry be packed up? (false, "DeckInUse") for a platform in use.
function Placement.canPickup(entries: { Entry }, entry: Entry): (boolean, string?)
	if Placement.deckInUse(entries, entry) then
		return false, "DeckInUse"
	end
	return true, nil
end

function Placement.limits(extraSlots: number, workshop: boolean): Limits
	return {
		Machines = MachineData.machineSlots(extraSlots, workshop),
		Conveyors = MachineData.conveyorSlots(workshop),
	}
end

-- Slots in use. Every machine without SlotFree takes a machine slot
-- (the Cleaning Station and platforms too); belts (Belt Lifts and Slides
-- too) take belt slots. Unknown ids are skipped.
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

--[[
	Can `id` go at (x, z, r) on `level` (nil / 0 = the ground, 1 = a deck)?
	Checks, in order: UnknownMachine, BadInput (also a level other than 0 /
	1, a platform or slope on a deck), OutOfBounds, Chute (ground: only flat
	belts on chute cells), DeckInUse (moving a used platform off its
	cells), then the cells: on the ground Overlap / UnderDeck and the Lift /
	Slide's DeckEdge, on a deck NoDeck / Overlap; then slots. Slots are
	skipped when `limits` is nil or when moving (`ignore` set), so a move
	never fails on slots.
]]
function Placement.validate(
	entries: { Entry },
	id: string,
	x: number,
	z: number,
	r: number,
	limits: Limits?,
	ignore: Entry?,
	level: number?
): (boolean, string?)
	local info = known(id)
	if not info then
		return false, "UnknownMachine"
	end
	if not isInt(x) or not isInt(z) or not isInt(r) or r < 0 or r > 3 then
		return false, "BadInput"
	end
	local lvl = if level == nil then 0 else level
	if lvl ~= 0 and lvl ~= 1 then
		return false, "BadInput"
	end
	if lvl == 1 and not Placement.fitsOnDeck(id) then
		return false, "BadInput"
	end
	if not Placement.inBounds(id, x, z, r) then
		return false, "OutOfBounds"
	end
	if lvl == 0 and not Placement.chuteAllows(id, x, z, r) then
		return false, "Chute"
	end
	if
		ignore
		and info.Behaviour == "Platform"
		and (x ~= ignore.X or z ~= ignore.Z or lvl ~= Placement.levelOf(ignore))
		and Placement.deckInUse(entries, ignore)
	then
		return false, "DeckInUse"
	end
	local cells = Placement.cells(id, x, z, r)
	if lvl == 1 then
		local decks = Placement.decks(entries, ignore)
		for _, k in cells do
			if not decks[k] then
				return false, "NoDeck"
			end
		end
		local occupied = Placement.occupancy(entries, ignore)
		for _, k in cells do
			if occupied[k + LEVEL_STRIDE] then
				return false, "Overlap"
			end
		end
	else
		local platforms, others = groundOf(entries, ignore)
		local conflict = groundConflict(id, cells, platforms, others)
		if conflict then
			return false, conflict
		end
		if not edgeOk(id, x, z, r, platforms) then
			return false, "DeckEdge"
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
	-- the droppers and Money Lasers have their own cap per plot (DropperConfig)
	if not ignore and (info.Behaviour == "Dropper" or info.Behaviour == "Laser") then
		local same = 0
		for _, entry in entries do
			local other = if type(entry) == "table" then MachineData.ById[entry.Id] else nil
			if other and other.Behaviour == info.Behaviour then
				same += 1
			end
		end
		if info.Behaviour == "Dropper" and same >= DropperConfig.MaxPlaced then
			return false, "DropperLimit"
		elseif info.Behaviour == "Laser" and same >= DropperConfig.MaxLasers then
			return false, "LaserLimit"
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

-- Place one machine from the inventory on `level` (nil / 0 = the ground,
-- 1 = a deck). Returns the new saved entry (it carries L only on a deck).
function Placement.commitPlace(
	data: { [string]: any },
	id: string,
	x: number,
	z: number,
	r: number,
	limits: Limits,
	level: number?
): (Entry?, string?)
	local inventory = data.MachineInventory
	local owned = if type(inventory) == "table" and type(id) == "string" then inventory[id] else nil
	if type(owned) ~= "number" or owned < 1 then
		return nil, "NoneOwned"
	end
	local ok, code = Placement.validate(data.PlacedMachines, id, x, z, r, limits, nil, level)
	if not ok then
		return nil, code
	end
	inventory[id] = if owned - 1 >= 1 then owned - 1 else nil
	local entry: Entry = { Id = id, X = x, Z = z, R = r }
	if level == 1 then
		entry.L = 1
	end
	table.insert(data.PlacedMachines, entry)
	return entry, nil
end

-- Move or turn a placed machine in place, onto `level` (nil / 0 = the
-- ground, 1 = a deck). Its In/Out stay with it.
function Placement.commitMove(data: { [string]: any }, entry: Entry, x: number, z: number, r: number, level: number?): (boolean, string?)
	if not table.find(data.PlacedMachines, entry) then
		return false, "Invalid"
	end
	local ok, code = Placement.validate(data.PlacedMachines, entry.Id, x, z, r, nil, entry, level)
	if not ok then
		return false, code
	end
	entry.X, entry.Z, entry.R = x, z, r
	entry.L = if level == 1 then 1 else nil
	return true, nil
end

-- Pack a placed machine back into the inventory. Drain its In/Out first
-- (MachineLogic.drain); this only moves the machine itself. The second
-- result is 1 when the inventory already held MachineData.MaxInventory of
-- that type and the machine was refunded at its Price instead (addInventory).
-- A platform whose deck is in use stays (false; canPickup says why).
function Placement.commitPickup(data: { [string]: any }, entry: Entry): (boolean, number)
	local index = table.find(data.PlacedMachines, entry)
	if not index or Placement.deckInUse(data.PlacedMachines, entry) then
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

--[[
	Repairs a loaded layout (MachineService runs it before spawning). In
	saved order: an unknown Id is kept and skipped. A junk level (not a
	whole number >= 0) is dropped: the entry stands on the ground. A machine
	that is off the plot, stands on a chute cell (anything but a flat belt),
	overlaps an earlier one (on its level, with validate's ground rules), is
	on a level this server doesn't know, stands on a deck no platform holds
	up any more, or is a Lift / Slide whose high end lost its deck goes back
	to the inventory (addInventory: refunded past the cap) and its In/Out
	spill into Storage. Queues longer than allowed are trimmed the same
	way. Slot limits are never enforced here. The ground comes first, so
	every deck is known before a deck entry is looked at.
	Returns the displaced ids and, at the same index, why each one moved:
	"BadInput" | "OutOfBounds" | "Chute" | "Overlap" | "UnderDeck" |
	"NoDeck" | "DeckEdge" (Reasons codes).
]]
function Placement.sanitize(data: { [string]: any }): ({ string }, { string })
	local displaced: { string } = {}
	local reasons: { string } = {}
	local list = data.PlacedMachines
	if type(list) ~= "table" then
		data.PlacedMachines = {}
		return displaced, reasons
	end
	-- entry -> the reason it moves off (kept entries have none)
	local verdict: { [any]: string } = {}
	local deckEntries: { Entry } = {}
	local slopes: { Entry } = {}
	local platforms: { [number]: Entry } = {}
	local others: { [number]: Entry } = {}
	-- 1. the ground (and the basic checks of every entry)
	for _, entry in list do
		local info = type(entry) == "table" and known(entry.Id)
		if not info then
			continue
		end
		local reason: string? = nil
		if not (isInt(entry.X) and isInt(entry.Z) and isInt(entry.R) and entry.R >= 0 and entry.R <= 3) then
			reason = "BadInput"
		else
			local l = entry.L
			if l ~= nil and not (isInt(l) and l >= 0) then
				entry.L = nil -- junk: on the ground
			elseif l == 0 then
				entry.L = nil
			elseif l ~= nil and l > MachineData.MaxLevel then
				reason = "BadInput" -- a level this server doesn't know
			end
		end
		if reason == nil and not Placement.inBounds(entry.Id, entry.X, entry.Z, entry.R) then
			reason = "OutOfBounds"
		end
		if reason == nil and Placement.levelOf(entry) == 1 then
			if Placement.fitsOnDeck(entry.Id) then
				table.insert(deckEntries, entry)
			else
				reason = "BadInput"
			end
		elseif reason == nil then
			if not Placement.chuteAllows(entry.Id, entry.X, entry.Z, entry.R) then
				reason = "Chute"
			else
				local cells = Placement.cells(entry.Id, entry.X, entry.Z, entry.R)
				reason = groundConflict(entry.Id, cells, platforms, others)
				if reason == nil then
					local map = if Placement.isPlatform(entry.Id) then platforms else others
					for _, k in cells do
						if map[k] == nil then
							map[k] = entry
						end
					end
					if Placement.slopeOf(entry.Id) then
						table.insert(slopes, entry)
					end
				end
			end
		end
		if reason then
			verdict[entry] = reason
		end
	end
	-- 2. what the decks hold up: Lift / Slide ends, then the deck entries
	for _, entry in slopes do
		if not edgeOk(entry.Id, entry.X, entry.Z, entry.R, platforms) then
			verdict[entry] = "DeckEdge"
		end
	end
	local upper: { [number]: boolean } = {}
	for _, entry in deckEntries do
		local cells = Placement.cells(entry.Id, entry.X, entry.Z, entry.R)
		local reason: string? = nil
		for _, k in cells do
			if not platforms[k] then
				reason = "NoDeck"
				break
			elseif upper[k] then
				reason = "Overlap"
				break
			end
		end
		if reason then
			verdict[entry] = reason
		else
			for _, k in cells do
				upper[k] = true
			end
		end
	end
	-- 3. in saved order: keep it (trimming its queues) or send it back
	local kept: { Entry } = {}
	for _, entry in list do
		local reason = if type(entry) == "table" then verdict[entry] else nil
		if reason == nil then
			if type(entry) == "table" and known(entry.Id) then
				entry.In = trim(data, entry.In, GameConfig.MachineIntakeQueue)
				entry.Out = trim(data, entry.Out, MachineData.MaxOutBuffer)
			end
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
