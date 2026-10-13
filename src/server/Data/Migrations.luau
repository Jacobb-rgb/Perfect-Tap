--[[
	Migrations: brings a loaded save up to DataTemplate.Version and cleans
	up types. Runs on every load (DataService.migrate) and is idempotent:
	running it again changes nothing. Pure (no services), so the Lune tests
	run it.

	Version 2 (step d): PlacedMachines entries may carry In/Out queues.
	- MachineInventory: only string ids with whole counts 1..999 stay.
	  Unknown ids are kept (a newer server may know them).
	- PlacedMachines: junk entries are dropped. X/Z are floored and R
	  becomes 0-3. A known machine without usable X/Z goes back to the
	  inventory. In/Out items need a string K and O; well-formed items of an
	  unknown kind or ore move to Storage instead of being lost.
	- Storage: entries that aren't tables are dropped.
	Layout repair (off the plot, overlapping) is NOT done here:
	Placement.sanitize does it when the plot spawns, so the player gets a toast.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)

local Migrations = {}

Migrations.Latest = 2

export type Report = { Moved: number, Dropped: number }

local MAX_INVENTORY = 999

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
		if type(key) ~= "string" or whole == nil or whole ~= whole or whole < 1 or whole > MAX_INVENTORY then
			inventory[key] = nil
			report.Dropped += 1
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
			if MachineData.ById[entry.Id] then
				inventory[entry.Id] = math.min(MAX_INVENTORY, (inventory[entry.Id] or 0) + 1)
				report.Moved += 1
			else
				warn(`[Migrations] dropped unknown machine {entry.Id} without a position`)
				report.Dropped += 1
			end
		end
	end
	refill(placed, kept)

	local version = data.Version
	if type(version) ~= "number" or version ~= version or version < Migrations.Latest then
		data.Version = Migrations.Latest
	end
	return report
end

return Migrations
