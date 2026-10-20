--[[
	Migrations: brings a loaded save up to DataTemplate.Version and cleans
	up types. Runs on every load (DataService.migrate) and is idempotent:
	running it again changes nothing. Pure (no services), so the Lune tests
	run it.

	Newer saves (docs/SAVE_AUDIT.md #1(b)): anything a newer build may have
	written that this server doesn't know is KEPT, never "repaired" away:
	ore ids, grades, recipes, item kinds, keep modes, golem kinds, enchant /
	gear / boost / artifact ids, and levels above what this server sells
	(clamped only to MAX_LEVEL_KEPT, a junk guard). Unknown items in machine
	queues and on the train move to the pen (the runtime drops queue items
	it can't read), where they wait. The readers clamp or ignore what they
	don't know (BlasterData.get / skin, TrainConfig levels,
	MachineData.keepsOre, PodiumService.podiumDesc, ...). Only junk types
	are dropped. tests/Migration.spec.luau runs a "future" save through and
	requires it unchanged. (DataService refuses saves with a higher Version
	outright; this is the second line for content added without a bump.)

	Version 2 (step d): PlacedMachines entries may carry In/Out queues.
	- MachineInventory: only string ids with whole counts >= 1 stay; a count
	  above MachineData.MaxInventory (999) is capped to it, never dropped.
	  Unknown ids are kept (a newer server may know them).
	- PlacedMachines: junk entries are dropped. X/Z are floored and R
	  becomes 0-3. A known machine without usable X/Z goes back to the
	  inventory (refunded at its Price when that type is at the cap).
	  In/Out items need a string K and O; well-formed items of a kind or
	  ore this server doesn't know move to Storage (kept: the machines would
	  drop queue items they can't read).
	- Storage: entries that aren't tables are dropped.
	Layout repair (off the plot, overlapping) is NOT done here:
	Placement.sanitize does it when the plot spawns, so the player gets a toast.
	Platforms (same Version 3): an entry's level L is a whole number >= 1 or
	nil (the ground); 0 and junk become nil. Saves without L are unchanged.

	Version 3 (design v2):
	- Pickaxes are gone: Pickaxe/OwnedPickaxes are removed, BlasterLevel is a
	  whole number 1..MAX_LEVEL_KEPT and BlasterOre a short id string or "".
	- Retired machines (MachineData.Retired: Storage Crate, Sell Chute, Anvil)
	  leave the plot and the inventory; their queued items go to the pen
	  (data.Storage) and each machine is refunded at its price.
	- Podiums is a list of at least 4 strings: a storage key of a cleaned
	  ore, or "". A readable non-clean item on a podium moves to the pen; a
	  four-part key this server can't read stays. Slots past the 4th (a
	  newer build's, up to MAX_PODIUM_SLOTS_KEPT) stay when "" or four-part.
	- Coins, TotalEarned and LastSeen are finite numbers >= 0.

	Trains (step 2, same Version 3; DataTemplate fills the record in):
	- Train levels are whole numbers 0..MAX_LEVEL_KEPT; Cargo and TripCargo
	  keep well-formed items of known kinds/ores (unknown ones wait in the
	  pen), together at most TrainConfig.MaxCargoSaved (the rest goes to
	  the pen);
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
	- KeepMode is a short mode name (else the default; an unknown one reads
	  as the default); KeepList keeps short ore ids mapped to a boolean (true
	  keep, false send on; MachineData.keepsOre).
	- Foundry.Stock: well-formed ingots (kind Ingot, no recipe, any ore and
	  grade), at most GameConfig.MaxFoundryStock; other well-formed items
	  and the overflow go to the pen, junk is dropped.
	- Upgrades is a record and Upgrades.PenAutomation a whole number
	  0..MAX_LEVEL_KEPT (readers clamp to EconomyConfig.PenAutomation; a newer
	  server may sell more levels).

	The owner's ore picture (2026-10-18, same Version 3): ores of the old
	roster that were replaced become their OreData.Renamed ore (same rarity)
	before anything else runs, wherever the save names an ore: item O fields
	(pen, machine queues, train, Foundry), storage keys ("Clean|Ruby|..." on
	podiums and in any other string), BlasterOre, the keys of Discovered,
	KeepList and OreCodex.Seen (steps 6-7; an existing entry of the new ore
	wins). This is the first step of run(): everything below (the steps 6-7
	records included) already sees the new ids. Golem kinds named after
	replaced ores are renamed by migrateSteps67 (GolemConfig.Renamed).

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
	  capacity; the higher of the two wins) and CarryLevel is removed. A
	  save that still has CarryLevel is from before the Gear shop, when
	  everyone walked at 18: it gets Boots level 1 (18, GearConfig) at
	  least, so nobody walks slower after the update.
	- Enchants.Owned: string ids -> whole tiers 1..MAX_LEVEL_KEPT.
	  Enchants.Slots: at least EnchantConfig.MaxSlots strings; a slot keeps an
	  owned id only once, and only when the blaster level has opened it.
	  Slots past MaxSlots (a newer build's, up to MAX_ENCHANT_SLOTS_KEPT)
	  stay when "" or an owned id not slotted before (readers skip them).
	- Boosts: finite whole os.time() seconds >= 0, at most now +
	  BoostConfig.MaxSavedSeconds (a year: a junk guard only; paid boost
	  time beyond MaxStackSeconds is kept, it is never lost).
	- Golems.Owned: entries { Id, Kind, ... } with a whole unique Id
	  1..MAX_GOLEM_ID and a string Kind (unknown kinds too), at most
	  GolemConfig.MaxSaved. Paid and Locked must be booleans (else dropped).
	  Other fields a newer server adds (trading flags, sources) are KEPT when
	  they are well-formed scalars: a string key of at most
	  MAX_FIELD_KEY_LENGTH characters with a boolean, finite number or string
	  of at most MAX_FIELD_TEXT_LENGTH characters; at most MAX_GOLEM_FIELDS of
	  them per entry (the first by name); anything else is dropped. A Kind
	  in GolemConfig.Renamed (RubyKnight, StormcoreTitan, StarmetalSovereign:
	  the 36-ore roster's names) becomes its new id. Equipped:
	  at most GolemConfig.EquipSlots unique owned ids (unknown kinds too:
	  GolemConfig.stats / equippedKinds skip them). NextId
	  is a whole number above every owned Id.
	- Daily (the retired 7-day Ember Chest streak, replaced by the daily
	  wheel: docs/plans/V2_PLAN.md) is removed.
	- Wheel.NextSpinAt: finite whole >= 0, at most now + WheelConfig.CooldownSeconds.
	- Artifacts.Found: string ids -> whole counts 1..ArtifactConfig.MaxCount;
	  Chapters: string ids -> true; Equipped: a string of at most
	  MAX_EQUIPPED_LENGTH characters (unknown ids kept: ArtifactConfig.
	  equipped ignores them), anything else nil.
	- Stats is a record; Stats.ArtifactsFound / CapsulesOpened / WheelSpins /
	  WheelOres are whole numbers >= 0.
	- Not here: Settings (SettingsService.read) and OreCodex
	  (CodexService.prepare) are repaired by their services once per load
	  (DataService.onLoaded, after this chain), next to the code that owns
	  their rules.
	Every step above runs once per load, in this order, inside run(); the
	Version stays 3 (all of it is additive and idempotent).

	Step 8 (Robux receipts, same Version 3):
	- PurchaseLog: [purchaseId] = { Product = a short string, At = finite
	  >= 0 } (other fields kept); entries whose id left Purchases (trimmed
	  together) and junk are dropped.
	- Golems.Pending (when present): { Kind = a short string, Paid =
	  boolean? } entries, renamed kinds renamed, at most
	  GolemConfig.MaxPending; junk dropped.
	- Enchants.Passes (when present): owned enchant ids -> true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
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
-- Highest saved level of any upgrade line (readers clamp to what is sold;
-- TrainService uses the same GameConfig number).
local MAX_LEVEL_KEPT = GameConfig.MaxLevelKept
local PODIUM_SLOTS = 4
-- a newer build may sell more podiums: its slots past PODIUM_SLOTS are kept up to here
local MAX_PODIUM_SLOTS_KEPT = 16
-- and more enchant slots: kept past EnchantConfig.MaxSlots up to here
local MAX_ENCHANT_SLOTS_KEPT = 16
local MAX_GOLEM_ID = 2 ^ 31 - 1
-- extra golem entry fields a newer server may add (see the header)
local MAX_GOLEM_FIELDS = 8
local MAX_FIELD_KEY_LENGTH = 32
local MAX_FIELD_TEXT_LENGTH = 64
-- data.Artifacts.Equipped: a collection id (or "" = none) is never longer
local MAX_EQUIPPED_LENGTH = 64
local GOLEM_FLAGS = { Paid = true, Locked = true } -- booleans or nothing
local OLD_CARRY_LEVELS = 5 -- the retired ToolData carry levels 1..5
-- ids this server doesn't know (a newer build's ores, grades, kinds, modes)
-- are kept when they are short strings (docs/SAVE_AUDIT.md #1(b))
local MAX_ID_LENGTH = 64
local MAX_KEY_LENGTH = 160 -- a storage key "Kind|Ore|Grade|Recipe"

-- A short string id (known to this server or not).
local function idLike(v: any): boolean
	return type(v) == "string" and v ~= "" and #v <= MAX_ID_LENGTH
end

-- A storage key of four parts with a kind and an ore (known to this server or not).
local function keyLike(v: any): boolean
	if type(v) ~= "string" or #v > MAX_KEY_LENGTH then
		return false
	end
	local parts = string.split(v, "|")
	return #parts == 4 and parts[1] ~= "" and parts[2] ~= ""
end

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

-- Ores of the old roster -> their replacements (OreData.Renamed), everywhere a save names an ore.
local function renameOres(data: { [string]: any })
	local renamed = OreData.Renamed
	local function storageKey(text: string): string
		local kind, ore, rest = string.match(text, "^([^|]*)|([^|]*)(.*)$")
		if kind and ore and rest and ItemData.Kinds[kind] and renamed[ore] then
			return kind .. "|" .. renamed[ore] .. rest
		end
		return text
	end
	local seen: { [any]: boolean } = {}
	local function walk(t: { [any]: any }, depth: number)
		if depth > 8 or seen[t] then
			return
		end
		seen[t] = true
		if type(t.O) == "string" and renamed[t.O] then
			t.O = renamed[t.O]
		end
		for k, v in t do
			if type(v) == "table" then
				walk(v, depth + 1)
			elseif type(v) == "string" and string.find(v, "|", 1, true) then
				t[k] = storageKey(v)
			end
		end
	end
	walk(data, 0)
	if type(data.BlasterOre) == "string" and renamed[data.BlasterOre] then
		data.BlasterOre = renamed[data.BlasterOre]
	end
	-- ore-keyed maps: Discovered, KeepList and the ORE CODEX's seen ores (steps 6-7,
	-- so a renamed ore the player had looked at gets no NEW badge again)
	local codex = data.OreCodex
	local maps = { data.Discovered, data.KeepList, if type(codex) == "table" then codex.Seen else nil }
	for i = 1, 3 do
		local map = maps[i]
		if type(map) == "table" then
			local moves = {}
			for old, new in renamed do
				if map[old] ~= nil then
					table.insert(moves, { old, new })
				end
			end
			for _, move in moves do
				if map[move[2]] == nil then
					map[move[2]] = map[move[1]]
				end
				map[move[1]] = nil
			end
		end
	end
end

-- A well-formed ingot the Foundry can hold: an ingot without a recipe (an ore
-- or grade this server doesn't know too: a newer build's ingots stay).
local function foundryIngot(item: any): boolean
	return wellFormed(item) and item.K == "Ingot" and item.R == nil
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
		-- from before the Gear shop: the old walk speed (18) is Boots I now
		gear.Boots = math.max(gear.Boots, 1)
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
	-- slots a newer build added stay ("" or an owned id once; the readers only look at 1..MaxSlots)
	local function extraSlot(id: any): boolean
		return id == "" or (type(id) == "string" and owned[id] ~= nil and not slotted[id])
	end
	local lastExtra = EnchantConfig.MaxSlots
	if type(slots) == "table" then
		for i = EnchantConfig.MaxSlots + 1, MAX_ENCHANT_SLOTS_KEPT do
			if extraSlot(slots[i]) then
				lastExtra = i
			end
		end
	end
	for i = EnchantConfig.MaxSlots + 1, MAX_ENCHANT_SLOTS_KEPT do
		local id = if type(slots) == "table" then slots[i] else nil
		if i <= lastExtra and extraSlot(id) then
			if id ~= "" then
				slotted[id] = true
			end
			cleanSlots[i] = id
		else
			if id ~= nil and id ~= "" then
				report.Dropped += 1
			end
			if i <= lastExtra then
				cleanSlots[i] = ""
			end
		end
	end
	enchants.Slots = cleanSlots
	-- step 8: the Mythic enchants a game pass gave (string ids -> true; a refund takes back
	-- only these); a mark for an enchant that isn't owned is dropped
	local passes = enchants.Passes
	if passes ~= nil then
		if type(passes) ~= "table" then
			enchants.Passes = {}
			report.Dropped += 1
		else
			for _, id in keysOf(passes) do
				if type(id) ~= "string" or passes[id] ~= true or owned[id] == nil then
					passes[id] = nil
					report.Dropped += 1
				end
			end
		end
	end

	-- boosts: whole os.time() seconds, never absurdly far ahead (MaxSavedSeconds
	-- is a junk guard: paid time stacked past MaxStackSeconds is kept)
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
			-- a renamed kind (GolemConfig.Renamed) takes its new id
			local renamed = if type(kind) == "string" then GolemConfig.Renamed[kind] else nil
			if renamed then
				kind = renamed
			end
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
			-- (a newer build's kinds stay equipped: GolemConfig.stats / equippedKinds skip them)
			local kind = if type(id) == "number" then kinds[id] else nil
			if kind and not table.find(equipped, id) and #equipped < GolemConfig.EquipSlots then
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
	-- step 8: paid golems waiting past MaxSaved (a Royal capsule receipt's credit):
	-- { Kind, Paid? } entries (unknown kinds kept, renamed ones renamed), at most MaxPending
	local pending = golems.Pending
	if pending ~= nil then
		local waiting = {}
		if type(pending) == "table" then
			for _, entry in values(pending) do
				local kind = if type(entry) == "table" then entry.Kind else nil
				local paid = if type(entry) == "table" then entry.Paid else nil
				if type(kind) == "string" and GolemConfig.Renamed[kind] then
					kind = GolemConfig.Renamed[kind]
				end
				if idLike(kind) and (paid == nil or type(paid) == "boolean") and #waiting < GolemConfig.MaxPending then
					entry.Kind = kind -- (the entry itself: fields a newer build adds stay)
					table.insert(waiting, entry)
				else
					report.Dropped += 1
				end
			end
			refill(pending, waiting)
		else
			golems.Pending = waiting
			report.Dropped += 1
		end
	end

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
	-- whose title + podium skin show: a short string ("" = none), else nil (the last completed)
	local pick = artifacts.Equipped
	if pick ~= nil and (type(pick) ~= "string" or #pick > MAX_EQUIPPED_LENGTH) then
		artifacts.Equipped = nil
		report.Dropped += 1
	end

	-- the new stats
	local stats = record(data, "Stats", report)
	for _, field in { "ArtifactsFound", "CapsulesOpened", "WheelSpins", "WheelOres" } do
		local v = stats[field]
		stats[field] = if isFinite(v) and v > 0 then math.floor(math.min(v, 1e15)) else 0
	end
end

-- Step 8: data.PurchaseLog[purchaseId] = { Product, At } for the granted
-- receipts (MonetizationService). Entries need a short string Product and a
-- finite At >= 0 (other fields a newer build adds stay); an entry whose id
-- isn't in Purchases any more (trimmed with it, DataService.trimPurchases)
-- or that is junk is dropped.
local function migrateStep8(data: { [string]: any }, report: Report)
	local log = record(data, "PurchaseLog", report)
	local purchases = if type(data.Purchases) == "table" then data.Purchases else {}
	for _, id in keysOf(log) do
		local entry = log[id]
		local ok = (type(id) == "string" or type(id) == "number")
			and purchases[id] ~= nil
			and type(entry) == "table"
			and idLike(entry.Product)
			and isFinite(entry.At)
			and entry.At >= 0
		if not ok then
			log[id] = nil
			report.Dropped += 1
		end
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
		elseif ItemData.Kinds[item.K] and (OreData.ById[item.O] or (item.K == "Relic" and ArtifactConfig.ById[item.O])) then
			-- (a dusty relic in a Restoration Table or Cleaning Station queue stays there)
			table.insert(kept, item)
		else
			-- a newer build's kind or ore: into the pen, where it waits safely
			-- (MachineService / ProcessingService drop queue items they can't read)
			table.insert(storage, item)
			report.Moved += 1
		end
	end
	return if #kept > 0 then kept else nil
end

function Migrations.run(data: { [string]: any }, now: number?): Report
	local report: Report = { Moved = 0, Dropped = 0 }
	local clock = math.floor(if isFinite(now) then now :: number else os.time())

	-- replaced ores take their new ids first, so nothing below drops them
	renameOres(data)

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
		-- the machine's own setting (Sorter threshold): a whole number or nothing
		-- (readers clamp to the rarities they know; a newer build may have more)
		if entry.C ~= nil then
			entry.C = if isFinite(entry.C) then math.clamp(math.floor(entry.C), 1, MAX_LEVEL_KEPT) else nil
		end
		-- the level (platforms): a whole number >= 1 or nothing (the ground);
		-- 0 and junk become nothing, a newer build's higher level is kept
		-- (Placement.sanitize sends an entry on a level this server doesn't
		-- know back to the inventory when the plot spawns)
		if entry.L ~= nil then
			local level = entry.L
			entry.L = if isFinite(level) and level == math.floor(level) and level >= 1 then math.min(level, MAX_LEVEL_KEPT) else nil
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
	-- shard rolls of crushed piles (ProcessingService): a whole number >= 0
	local rolls = data.ShardRolls
	data.ShardRolls = if isFinite(rolls) and rolls > 0 then math.floor(math.min(rolls, 100000)) else 0

	-- v3: blasters instead of pickaxes
	data.Pickaxe = nil
	data.OwnedPickaxes = nil
	-- a level above this server's top and an ore it doesn't know stay (a newer
	-- build's; BlasterData.get and BlasterData.skin clamp / fall back for the readers)
	local level = data.BlasterLevel
	data.BlasterLevel = if isFinite(level) then math.clamp(math.floor(level), 1, MAX_LEVEL_KEPT) else 1
	if data.BlasterOre ~= "" and not idLike(data.BlasterOre) then
		data.BlasterOre = ""
	end

	-- v3: at least 4 podium strings, each a cleaned ore or "". A key this server
	-- can't read (a newer build's ore or grade) stays as it is: PodiumService
	-- shows that slot empty, and the newer server reads it again. Slots past
	-- the 4th (a newer build's) stay as they are when "" or key-shaped.
	local podiums = data.Podiums
	local slots = {}
	local lastPodium = PODIUM_SLOTS
	if type(podiums) == "table" then
		for i = PODIUM_SLOTS + 1, MAX_PODIUM_SLOTS_KEPT do
			if podiums[i] == "" or keyLike(podiums[i]) then
				lastPodium = i
			end
		end
	end
	for i = 1, PODIUM_SLOTS do
		local key = if type(podiums) == "table" then podiums[i] else nil
		local desc = if type(key) == "string" and key ~= "" then ItemData.parseKey(key) else nil
		if desc and desc.K == "Clean" then
			slots[i] = ItemData.storageKey(desc)
		elseif desc then
			table.insert(storage, desc)
			report.Moved += 1
			slots[i] = ""
		elseif keyLike(key) then
			slots[i] = key
		else
			if key ~= nil and key ~= "" then
				report.Dropped += 1
			end
			slots[i] = ""
		end
	end
	for i = PODIUM_SLOTS + 1, MAX_PODIUM_SLOTS_KEPT do
		local key = if type(podiums) == "table" then podiums[i] else nil
		if i <= lastPodium and (key == "" or keyLike(key)) then
			slots[i] = key
		else
			if key ~= nil and key ~= "" then
				report.Dropped += 1
			end
			if i <= lastPodium then
				slots[i] = ""
			end
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
	-- levels above what this server sells stay (TrainConfig clamps for the readers)
	for _, field in { "CapacityLevel", "SpeedLevel" } do
		local v = train[field]
		train[field] = if isFinite(v) then math.clamp(math.floor(v), 0, MAX_LEVEL_KEPT) else 0
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
					-- a newer build's item waits in the pen (the unload can't store what it can't read), so does the overflow
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

	-- step 3: the keep mode is a mode name (a newer build's too: MachineData
	-- treats an unknown one as Keep.Default), the keep list maps ore ids to booleans
	if not MachineData.isKeepMode(data.KeepMode) and not idLike(data.KeepMode) then
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
		if not idLike(oreId) or type(keepList[oreId]) ~= "boolean" then
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
	migrateStep8(data, report)

	local version = data.Version
	if type(version) ~= "number" or version ~= version or version < Migrations.Latest then
		data.Version = Migrations.Latest
	end
	return report
end

return Migrations
