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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local GameConfig = require(Shared.Config.GameConfig)
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

function Migrations.run(data: { [string]: any }): Report
	local report: Report = { Moved = 0, Dropped = 0 }

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
		-- the machine's own setting (Sorter threshold): a whole number 1..9 or nothing
		if entry.C ~= nil then
			entry.C = if isFinite(entry.C) then math.clamp(math.floor(entry.C), 1, 9) else nil
		end
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

	-- crystal shards: a whole number >= 0
	data.Shards = if isFinite(data.Shards) and data.Shards > 0 then math.floor(data.Shards) else 0

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

	local version = data.Version
	if type(version) ~= "number" or version ~= version or version < Migrations.Latest then
		data.Version = Migrations.Latest
	end
	return report
end

return Migrations
