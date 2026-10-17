--[[
	Migrations: brings a loaded save up to DataTemplate.Version and cleans
	up types. Runs on every load (DataService.migrate) and is idempotent:
	running it again changes nothing. Pure (no services), so the Lune tests
	run it.

	Version 2 (step d): PlacedMachines entries may carry In/Out queues.
	- MachineInventory: only string ids with whole counts >= 1 stay; a count
	  above MachineData.MaxInventory (999) is capped to it, never dropped.
	  Unknown ids are kept (a newer server may know them).
	- PlacedMachines: junk entries are dropped. X/Z are floored and R
	  becomes 0-3. A known machine without usable X/Z goes back to the
	  inventory (refunded at its Price when that type is at the cap).
	  In/Out items need a string K and O; well-formed items of an unknown
	  kind or ore move to Storage instead of being lost.
	- Storage: entries that aren't tables are dropped.
	Layout repair (off the plot, overlapping) is NOT done here:
	Placement.sanitize does it when the plot spawns, so the player gets a toast.

	Version 3 (design v2):
	- Pickaxes are gone: Pickaxe/OwnedPickaxes are removed, BlasterLevel is a
	  whole number 1..BlasterData.MaxLevel and BlasterOre a known ore id or "".
	- Retired machines (MachineData.Retired: Storage Crate, Sell Chute, Anvil)
	  leave the plot and the inventory; their queued items go to the pen
	  (data.Storage) and each machine is refunded at its price.
	- Podiums is a list of exactly 4 strings: a storage key of a cleaned
	  ore, or "". Anything else on a podium moves to the pen.
	- Coins, TotalEarned and LastSeen are finite numbers >= 0.

	Trains (step 2, same Version 3; DataTemplate fills the record in):
	- Train levels are whole numbers in range; Cargo and TripCargo keep
	  well-formed items of known kinds/ores (unknown ones go to the pen),
	  together at most TrainConfig.MaxCargoSaved (the rest goes to the pen);
	  trip times are finite and >= 0, and 0 when nothing is on the move.

	Machines + automation (step 3, same Version 3; DataTemplate fills the
	records in):
	- MachineUpgrades: { [string machine id] = { [string kind] = level } }
	  with whole levels 0..MAX_LEVEL_KEPT. Unknown machines, upgrade kinds
	  and levels above what this server sells are kept (a newer server may
	  sell them, as with MachineInventory); readers clamp to what is sold
	  (EconomyConfig.upgradeLevel, MachineData.speedMult / gradeOdds).
	  Retired machines, non-string keys and non-number levels are dropped,
	  empty records removed.
	- KeepMode is one of MachineData.Keep.Modes (else the default);
	  KeepList keeps only known ore ids mapped to a boolean (true keep,
	  false send on; MachineData.keepsOre).
	- Foundry.Stock: well-formed ingots (kind Ingot, known ore and grade, no
	  recipe), at most GameConfig.MaxFoundryStock; other well-formed items
	  and the overflow go to the pen, junk is dropped.
	- Upgrades is a record and Upgrades.PenAutomation a whole number
	  0..MAX_LEVEL_KEPT (readers clamp to EconomyConfig.PenAutomation; a newer
	  server may sell more levels).

	Steps 6-7 (same Version 3; DataTemplate fills the records in; `now` =
	os.time() unless the caller passes one, for the time caps). As with
	MachineInventory and MachineUpgrades, well-formed entries this server
	doesn't know are KEPT (Roblox keeps old servers running after an update:
	a player who joins one must not lose the golems, enchants, artifacts or
	gear levels a newer server gave them, paid ones included). Only junk
	types are dropped; the config readers clamp or ignore what they don't
	know (GearConfig.level, EnchantConfig.tierOf, GolemConfig.stats/equip,
	ArtifactConfig.countOf).
	- Gear: string keys with whole levels 0..MAX_LEVEL_KEPT (the five lines
	  this server sells always exist, broken = 0; other junk keys dropped).
	  The old CarryLevel N (1..5) folds into Backpack level N - 1 (same
	  capacity; the higher of the two wins) and CarryLevel is removed.
	- Enchants.Owned: string ids -> whole tiers 1..MAX_LEVEL_KEPT.
	  Enchants.Slots: exactly EnchantConfig.MaxSlots strings; a slot keeps an
	  owned id only once, and only when the blaster level has opened it.
	- Boosts: finite whole os.time() seconds >= 0, at most now +
	  BoostConfig.MaxSavedSeconds.
	- Golems.Owned: entries { Id, Kind, ... } with a whole unique Id
	  1..MAX_GOLEM_ID and a string Kind (unknown kinds too), at most
	  GolemConfig.MaxSaved. Paid and Locked must be booleans (else dropped).
	  Other fields a newer server adds (trading flags, sources) are KEPT when
	  they are well-formed scalars: a string key of at most
	  MAX_FIELD_KEY_LENGTH characters with a boolean, finite number or string
	  of at most MAX_FIELD_TEXT_LENGTH characters; at most MAX_GOLEM_FIELDS of
	  them per entry (the first by name); anything else is dropped. Equipped:
	  at most GolemConfig.EquipSlots unique owned ids of known kinds. NextId
	  is a whole number above every owned Id.
	- Daily (the retired 7-day Ember Chest streak, replaced by the daily
	  wheel: docs/plans/V2_PLAN.md) is removed.
	- Wheel.NextSpinAt: finite whole >= 0, at most now + WheelConfig.CooldownSeconds.
	- Artifacts.Found: string ids -> whole counts 1..ArtifactConfig.MaxCount;
	  Chapters: string ids -> true.
	- Stats is a record; Stats.ArtifactsFound / CapsulesOpened / WheelSpins are
	  whole numbers >= 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GearConfig = require(Shared.Config.GearConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local WheelConfig = require(Shared.Config.WheelConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local TrainConfig = require(Shared.Config.TrainConfig)
local OreData = require(Shared.Config.OreData)
local DataTemplate = require(script.Parent.DataTemplate)

local Migrations = {}

Migrations.Latest = 3

export type Report = { Moved: number, Dropped: number }

local MAX_INVENTORY = MachineData.MaxInventory
-- Highest saved level of a step 3 upgrade (readers clamp to what is sold).
local MAX_LEVEL_KEPT = 99
local PODIUM_SLOTS = 4
local MAX_GOLEM_ID = 2 ^ 31 - 1
-- extra golem entry fields a newer server may add (see the header)
local MAX_GOLEM_FIELDS = 8
local MAX_FIELD_KEY_LENGTH = 32
local MAX_FIELD_TEXT_LENGTH = 64
local GOLEM_FLAGS = { Paid = true, Locked = true } -- booleans or nothing
local OLD_CARRY_LEVELS = 5 -- the retired ToolData carry levels 1..5

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Values of a table in a fixed order: number keys ascending, then the rest
-- by name. Saves are plain arrays, but a damaged one might not be.
local function values(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a: any, b: any): boolean
		local an, bn = type(a) == "number", type(b) == "number"
		if an ~= bn then
			return an
		end
		if an then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	local list = {}
	for _, k in keys do
		table.insert(list, t[k])
	end
	return list
end

-- Replaces the contents of `t` with `list` (keeps the table itself).
local function refill(t: { [any]: any }, list: { any })
	table.clear(t)
	for i, v in list do
		t[i] = v
	end
end

local function wellFormed(item: any): boolean
	return type(item) == "table"
		and type(item.K) == "string"
		and type(item.O) == "string"
		and (item.G == nil or type(item.G) == "string")
		and (item.R == nil or type(item.R) == "string")
end

-- A well-formed ingot the Foundry can hold: known ore and grade, no recipe.
local function foundryIngot(item: any): boolean
	return wellFormed(item)
		and item.K == "Ingot"
		and OreData.ById[item.O] ~= nil
		and (item.G == nil or ItemData.GradeById[item.G] ~= nil)
		and item.R == nil
end

-- The keys of a table (so entries can be removed while walking them).
local function keysOf(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	return keys
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- data[field] as a table: anything else is replaced by a copy of the
-- template's record (counted as dropped when it wasn't nil).
local function record(data: { [string]: any }, field: string, report: Report): { [any]: any }
	local t = data[field]
	if type(t) ~= "table" then
		if t ~= nil then
			report.Dropped += 1
		end
		t = deepCopy((DataTemplate :: any)[field])
		data[field] = t
	end
	return t
end

-- t[field] as a table (a fresh empty one when missing or junk).
local function subTable(t: { [any]: any }, field: string, report: Report): { [any]: any }
	local sub = t[field]
	if type(sub) ~= "table" then
		if sub ~= nil then
			report.Dropped += 1
		end
		sub = {}
		t[field] = sub
	end
	return sub
end

-- A whole number in lo..hi from a finite number (floored, clamped); nil for junk.
local function wholeIn(v: any, lo: number, hi: number): number?
	if not isFinite(v) then
		return nil
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- One well-formed golem entry: Id and Kind, Paid / Locked when they are
-- booleans, and the extra scalar fields a newer server added (header).
local function cleanGolem(entry: { [any]: any }, id: number, kind: string, report: Report): { [string]: any }
	local clean: { [string]: any } = { Id = id, Kind = kind }
	local extras = {}
	for key, value in entry do
		if key == "Id" or key == "Kind" then
			continue
		end
		if GOLEM_FLAGS[key] then
			if type(value) == "boolean" then
				clean[key] = value
			else
				report.Dropped += 1
			end
		elseif
			type(key) == "string"
			and #key <= MAX_FIELD_KEY_LENGTH
			and (type(value) == "boolean" or isFinite(value) or (type(value) == "string" and #value <= MAX_FIELD_TEXT_LENGTH))
		then
			table.insert(extras, key)
		else
			report.Dropped += 1
		end
	end
	table.sort(extras)
	for i, key in extras do
		if i > MAX_GOLEM_FIELDS then
			report.Dropped += 1
		else
			clean[key] = entry[key]
		end
	end
	return clean
end

-- Steps 6-7: gear, enchants, boosts, golems, wheel, artifacts, new stats.
local function migrateSteps67(data: { [string]: any }, now: number, report: Report)
	-- the retired 7-day Ember Chest streak (the daily wheel replaced it)
	if data.Daily ~= nil then
		data.Daily = nil
	end

	-- gear levels (unknown lines and levels kept); the old CarryLevel N becomes Backpack level N - 1
	local gear = record(data, "Gear", report)
	for _, key in keysOf(gear) do
		local v = gear[key]
		local level = if type(key) == "string" then wholeIn(v, 0, MAX_LEVEL_KEPT) else nil
		if level == nil then
			-- junk (a known line comes back as 0 below)
			report.Dropped += 1
			gear[key] = nil
		elseif level ~= v then
			gear[key] = level
		end
	end
	for _, lineId in GearConfig.LineIds do
		if gear[lineId] == nil then
			gear[lineId] = 0
		end
	end
	local carry = data.CarryLevel
	if carry ~= nil then
		if isFinite(carry) then
			-- the old levels were 1..OLD_CARRY_LEVELS: higher junk never gives more
			local backpack = math.clamp(math.floor(carry) - 1, 0, OLD_CARRY_LEVELS - 1)
			gear.Backpack = math.max(gear.Backpack, backpack)
		end
		data.CarryLevel = nil
	end

	-- enchants: owned tiers (unknown ids and tiers kept), then slots (owned, unique, opened by the blaster level)
	local enchants = record(data, "Enchants", report)
	local owned = subTable(enchants, "Owned", report)
	for _, id in keysOf(owned) do
		local tier = owned[id]
		local whole = if type(id) == "string" and isFinite(tier) and tier >= 1 then wholeIn(tier, 1, MAX_LEVEL_KEPT) else nil
		if whole == nil then
			owned[id] = nil
			report.Dropped += 1
		elseif whole ~= tier then
			owned[id] = whole
		end
	end
	local slots = enchants.Slots
	if slots ~= nil and type(slots) ~= "table" then
		report.Dropped += 1
	end
	local open = EnchantConfig.unlockedSlots(data.BlasterLevel)
	local cleanSlots = {}
	local slotted: { [string]: boolean } = {}
	for i = 1, EnchantConfig.MaxSlots do
		local id = if type(slots) == "table" then slots[i] else nil
		if type(id) == "string" and id ~= "" and i <= open and owned[id] ~= nil and not slotted[id] then
			slotted[id] = true
			cleanSlots[i] = id
		else
			if id ~= nil and id ~= "" then
				report.Dropped += 1
			end
			cleanSlots[i] = ""
		end
	end
	enchants.Slots = cleanSlots

	-- boosts: whole os.time() seconds, never absurdly far ahead
	local boosts = record(data, "Boosts", report)
	for _, kindId in BoostConfig.KindIds do
		local field = BoostConfig.Kinds[kindId].Field
		local v = boosts[field]
		if not isFinite(v) or v < 0 then
			if v ~= nil then
				report.Dropped += 1
			end
			boosts[field] = 0
		else
			boosts[field] = math.min(math.floor(v), now + BoostConfig.MaxSavedSeconds)
		end
	end

	-- golems: well-formed unique entries (unknown kinds kept), equipped ids of
	-- known kinds that exist, NextId above them all
	local golems = record(data, "Golems", report)
	local ownedGolems = {}
	local kinds: { [number]: string } = {}
	local maxId = 0
	local list = golems.Owned
	if type(list) == "table" then
		for _, entry in values(list) do
			local id = if type(entry) == "table" then entry.Id else nil
			local kind = if type(entry) == "table" then entry.Kind else nil
			if
				isFinite(id)
				and id >= 1
				and id <= MAX_GOLEM_ID
				and id == math.floor(id)
				and not kinds[id]
				and type(kind) == "string"
				and kind ~= ""
				and #ownedGolems < GolemConfig.MaxSaved
			then
				kinds[id] = kind
				maxId = math.max(maxId, id)
				table.insert(ownedGolems, cleanGolem(entry, id, kind, report))
			else
				report.Dropped += 1
			end
		end
	elseif list ~= nil then
		report.Dropped += 1
	end
	golems.Owned = ownedGolems
	local equipped = {}
	local wearing = golems.Equipped
	if type(wearing) == "table" then
		for _, id in values(wearing) do
			local kind = if type(id) == "number" then kinds[id] else nil
			if kind and GolemConfig.ById[kind] and not table.find(equipped, id) and #equipped < GolemConfig.EquipSlots then
				table.insert(equipped, id)
			else
				report.Dropped += 1
			end
		end
	elseif wearing ~= nil then
		report.Dropped += 1
	end
	golems.Equipped = equipped
	local nextId = golems.NextId
	local wholeNext = if isFinite(nextId) then math.floor(nextId) else 1
	golems.NextId = math.clamp(math.max(wholeNext, maxId + 1), 1, MAX_GOLEM_ID + 1)

	-- the daily wheel: a whole time, at most one cooldown ahead
	local wheel = record(data, "Wheel", report)
	local spinAt = wheel.NextSpinAt
	if not isFinite(spinAt) or spinAt < 0 then
		if spinAt ~= nil then
			report.Dropped += 1
		end
		wheel.NextSpinAt = 0
	else
		wheel.NextSpinAt = math.min(math.floor(spinAt), now + WheelConfig.CooldownSeconds)
	end

	-- artifacts: string ids with whole counts, chapters read (unknown ids kept)
	local artifacts = record(data, "Artifacts", report)
	local found = subTable(artifacts, "Found", report)
	for _, id in keysOf(found) do
		local n = found[id]
		local whole = if type(id) == "string" and isFinite(n) and n >= 1 then wholeIn(n, 1, ArtifactConfig.MaxCount) else nil
		if whole == nil then
			found[id] = nil
			report.Dropped += 1
		elseif whole ~= n then
			found[id] = whole
		end
	end
	local chapters = subTable(artifacts, "Chapters", report)
	for _, id in keysOf(chapters) do
		if type(id) ~= "string" or chapters[id] ~= true then
			chapters[id] = nil
			report.Dropped += 1
		end
	end

	-- the new stats
	local stats = record(data, "Stats", report)
	for _, field in { "ArtifactsFound", "CapsulesOpened", "WheelSpins" } do
		local v = stats[field]
		stats[field] = if isFinite(v) and v > 0 then math.floor(math.min(v, 1e15)) else 0
	end
end

-- Cleans one machine queue. Returns the kept items, or nil when none are left.
local function cleanQueue(queue: any, storage: { any }, report: Report): { any }?
	if queue == nil then
		return nil
	end
	if type(queue) ~= "table" then
		report.Dropped += 1
		return nil
	end
	local kept = {}
	for _, item in values(queue) do
		if not wellFormed(item) then
			report.Dropped += 1
		elseif ItemData.Kinds[item.K] and OreData.ById[item.O] then
			table.insert(kept, item)
		else
			table.insert(storage, item)
			report.Moved += 1
		end
	end
	return if #kept > 0 then kept else nil
end

function Migrations.run(data: { [string]: any }, now: number?): Report
	local report: Report = { Moved = 0, Dropped = 0 }
	local clock = math.floor(if isFinite(now) then now :: number else os.time())

	-- MachineInventory first, so machines sent back below add to clean counts
	local inventory = data.MachineInventory
	if type(inventory) ~= "table" then
		if inventory ~= nil then
			report.Dropped += 1
		end
		inventory = {}
		data.MachineInventory = inventory
	end
	local keys = {}
	for key in inventory do
		table.insert(keys, key)
	end
	for _, key in keys do
		local count = inventory[key]
		local whole = if type(count) == "number" then math.floor(count) else nil
		if type(key) ~= "string" or whole == nil or whole ~= whole or whole < 1 then
			inventory[key] = nil
			report.Dropped += 1
		elseif whole > MAX_INVENTORY then
			-- capped, never dropped: the cap is a DataStore guard, not a penalty
			inventory[key] = MAX_INVENTORY
		elseif whole ~= count then
			inventory[key] = whole
		end
	end

	-- Storage: drop anything that isn't an item table
	local storage = data.Storage
	if type(storage) ~= "table" then
		if storage ~= nil then
			report.Dropped += 1
		end
		storage = {}
		data.Storage = storage
	else
		local kept = {}
		for _, item in values(storage) do
			if type(item) == "table" then
				table.insert(kept, item)
			else
				report.Dropped += 1
			end
		end
		refill(storage, kept)
	end

	-- PlacedMachines
	local placed = data.PlacedMachines
	if type(placed) ~= "table" then
		if placed ~= nil then
			report.Dropped += 1
		end
		placed = {}
		data.PlacedMachines = placed
	end
	local kept = {}
	for _, entry in values(placed) do
		if type(entry) ~= "table" or type(entry.Id) ~= "string" then
			report.Dropped += 1
			continue
		end
		entry.In = cleanQueue(entry.In, storage, report)
		entry.Out = cleanQueue(entry.Out, storage, report)
		if isFinite(entry.X) and isFinite(entry.Z) then
			entry.X = math.floor(entry.X)
			entry.Z = math.floor(entry.Z)
			entry.R = if isFinite(entry.R) then math.floor(entry.R) % 4 else 0
			table.insert(kept, entry)
		else
			-- nowhere to put it: its contents go to Storage, the machine to the inventory
			for _, queue in { entry.In, entry.Out } do
				if queue then
					for _, item in queue do
						table.insert(storage, item)
						report.Moved += 1
					end
				end
			end
			local info = MachineData.ById[entry.Id]
			if info then
				local have = inventory[entry.Id] or 0
				if have < MAX_INVENTORY then
					inventory[entry.Id] = have + 1
				else
					-- that type is at the cap: refunded, never lost
					data.Coins = (if isFinite(data.Coins) then data.Coins else 0) + info.Price
				end
				report.Moved += 1
			else
				warn(`[Migrations] dropped unknown machine {entry.Id} without a position`)
				report.Dropped += 1
			end
		end
	end
	refill(placed, kept)

	-- v3: retired machines leave (items to the pen, coins back)
	local retired = MachineData.Retired
	local stillPlaced = {}
	for _, entry in placed do
		if retired[entry.Id] then
			for _, queue in { entry.In, entry.Out } do
				if queue then
					for _, item in queue do
						table.insert(storage, item)
						report.Moved += 1
					end
				end
			end
			data.Coins = (if isFinite(data.Coins) then data.Coins else 0) + MachineData.ById[entry.Id].Price
			report.Moved += 1
		else
			table.insert(stillPlaced, entry)
		end
	end
	refill(placed, stillPlaced)
	for id in retired do
		local count = inventory[id]
		if count then
			data.Coins = (if isFinite(data.Coins) then data.Coins else 0) + MachineData.ById[id].Price * count
			inventory[id] = nil
			report.Moved += 1
		end
	end

	-- v3: blasters instead of pickaxes
	data.Pickaxe = nil
	data.OwnedPickaxes = nil
	local level = data.BlasterLevel
	data.BlasterLevel = if isFinite(level) then math.clamp(math.floor(level), 1, BlasterData.MaxLevel) else 1
	if type(data.BlasterOre) ~= "string" or (data.BlasterOre ~= "" and not OreData.ById[data.BlasterOre]) then
		data.BlasterOre = ""
	end

	-- v3: exactly 4 podium strings, each a cleaned ore or ""
	local podiums = data.Podiums
	local slots = {}
	for i = 1, PODIUM_SLOTS do
		local key = if type(podiums) == "table" then podiums[i] else nil
		local desc = if type(key) == "string" and key ~= "" then ItemData.parseKey(key) else nil
		if desc and desc.K == "Clean" then
			slots[i] = ItemData.storageKey(desc)
		else
			if desc then
				table.insert(storage, desc)
				report.Moved += 1
			elseif key ~= nil and key ~= "" then
				report.Dropped += 1
			end
			slots[i] = ""
		end
	end
	data.Podiums = slots

	-- v3: money and time are finite and not negative
	for _, field in { "Coins", "TotalEarned", "LastSeen" } do
		local v = data[field]
		if not isFinite(v) or v < 0 then
			data[field] = 0
		end
	end

	-- trains: levels in range, clean cargo lists, sane trip times
	local train = data.Train
	if type(train) ~= "table" then
		if train ~= nil then
			report.Dropped += 1
		end
		train = {}
		data.Train = train
	end
	for _, field in { "CapacityLevel", "SpeedLevel" } do
		local list = if field == "CapacityLevel" then TrainConfig.Capacity else TrainConfig.Speed
		local v = train[field]
		train[field] = if isFinite(v) then math.clamp(math.floor(v), 0, TrainConfig.maxLevel(list)) else 0
	end
	local cargoKept = 0
	for _, field in { "Cargo", "TripCargo" } do
		local list = train[field]
		local clean = {}
		if type(list) == "table" then
			for _, item in values(list) do
				if not wellFormed(item) then
					report.Dropped += 1
				elseif not (ItemData.Kinds[item.K] and OreData.ById[item.O]) or cargoKept >= TrainConfig.MaxCargoSaved then
					table.insert(storage, item)
					report.Moved += 1
				else
					table.insert(clean, item)
					cargoKept += 1
				end
			end
		elseif list ~= nil then
			report.Dropped += 1
		end
		train[field] = clean
	end
	for _, field in { "TripDepartAt", "TripArriveAt" } do
		local v = train[field]
		if not isFinite(v) or v < 0 then
			train[field] = 0
		end
	end
	if #train.TripCargo == 0 then
		train.TripDepartAt = 0
		train.TripArriveAt = 0
	end

	-- step 3: machine upgrades, whole levels in range (unknown ones kept for newer servers)
	local machineUpgrades = data.MachineUpgrades
	if type(machineUpgrades) ~= "table" then
		if machineUpgrades ~= nil then
			report.Dropped += 1
		end
		machineUpgrades = {}
		data.MachineUpgrades = machineUpgrades
	end
	local upgradeIds = {}
	for id in machineUpgrades do
		table.insert(upgradeIds, id)
	end
	for _, id in upgradeIds do
		local record = machineUpgrades[id]
		if type(id) ~= "string" or MachineData.Retired[id] or type(record) ~= "table" then
			machineUpgrades[id] = nil
			report.Dropped += 1
			continue
		end
		local kinds = {}
		for kind in record do
			table.insert(kinds, kind)
		end
		for _, kind in kinds do
			local upgradeLevel = record[kind]
			if type(kind) ~= "string" or not isFinite(upgradeLevel) then
				record[kind] = nil
				report.Dropped += 1
				continue
			end
			local whole = math.clamp(math.floor(upgradeLevel), 0, MAX_LEVEL_KEPT)
			if whole ~= upgradeLevel then
				record[kind] = whole
			end
		end
		if next(record) == nil then
			machineUpgrades[id] = nil
		end
	end

	-- step 3: the keep mode is a known mode, the keep list maps known ore ids to booleans
	if not MachineData.isKeepMode(data.KeepMode) then
		if data.KeepMode ~= nil then
			report.Dropped += 1
		end
		data.KeepMode = MachineData.Keep.Default
	end
	local keepList = data.KeepList
	if type(keepList) ~= "table" then
		if keepList ~= nil then
			report.Dropped += 1
		end
		keepList = {}
		data.KeepList = keepList
	end
	local keepKeys = {}
	for oreId in keepList do
		table.insert(keepKeys, oreId)
	end
	for _, oreId in keepKeys do
		if type(oreId) ~= "string" or not OreData.ById[oreId] or type(keepList[oreId]) ~= "boolean" then
			keepList[oreId] = nil
			report.Dropped += 1
		end
	end

	-- step 3: the Foundry's ingot stock (other items and the overflow go to the pen)
	local foundry = data.Foundry
	if type(foundry) ~= "table" then
		if foundry ~= nil then
			report.Dropped += 1
		end
		foundry = {}
		data.Foundry = foundry
	end
	local stock = foundry.Stock
	local stockKept = {}
	if type(stock) == "table" then
		for _, item in values(stock) do
			if not wellFormed(item) then
				report.Dropped += 1
			elseif foundryIngot(item) and #stockKept < GameConfig.MaxFoundryStock then
				table.insert(stockKept, item)
			else
				table.insert(storage, item)
				report.Moved += 1
			end
		end
		refill(stock, stockKept)
	else
		if stock ~= nil then
			report.Dropped += 1
		end
		foundry.Stock = stockKept
	end

	-- step 3: pen automation level (sorting billboard, Direct Unload)
	local bought = data.Upgrades
	if type(bought) ~= "table" then
		if bought ~= nil then
			report.Dropped += 1
		end
		bought = table.clone(DataTemplate.Upgrades)
		data.Upgrades = bought
	end
	local automation = bought.PenAutomation
	bought.PenAutomation = if isFinite(automation) then math.clamp(math.floor(automation), 0, MAX_LEVEL_KEPT) else 0

	-- steps 6-7 (after the blaster level is clean: it opens the enchant slots)
	migrateSteps67(data, clock, report)

	local version = data.Version
	if type(version) ~= "number" or version ~= version or version < Migrations.Latest then
		data.Version = Migrations.Latest
	end
	return report
end

return Migrations
