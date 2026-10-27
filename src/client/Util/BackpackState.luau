--[[
	BackpackState: the backpack as this client sees it (owner 2026-10-24:
	everything you pick up goes into the backpack, nothing is carried in the
	hands; docs/plans/OWNER_PLAYTEST_1024.md "4 + 5"). Every prompt rule,
	the HUD's backpack button and the inventory window read it here instead
	of scanning item models.

	Sources: State.Backpacks (StateService: { Equipped, Owned, Count,
	Capacity, Items = { [ItemData.storageKey] = count } }) and the player
	attributes CarryCount / CarryCapacity (CarryService sets them the moment
	the backpack changes, so they lead the State push: a CarryCount of 0
	means empty even while an older snapshot still lists items).

	  read(state, count?, capacity?)  pure: the Backpack of a snapshot (the
	                                  attribute values win when given)
	  get()                           read() of the latest State + the attributes
	  parse(items)                    pure: the Stacks of State.Backpacks.Items
	                                  (ItemData.parseStoredKey: dusty relics too;
	                                  keys this build can't read are skipped),
	                                  sorted: dirty ore, relics, cleaned ore
	                                  (rarest, best grade first), the rest
	  has(predicate, backpack?)       any stack matching (predicate: Desc -> boolean)
	  count() / capacity() / isFull()
	  onChanged(callback)             callback() on every State push and every
	                                  CarryCount / CarryCapacity change
	Predicates for the prompt rules: anything, notRelic (the train, the
	pen), podiumOre (EconomyConfig.Podiums.Kinds), cleanable (Raw or Relic).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BackpackData = require(Shared.Config.BackpackData)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local StateController = require(script.Parent.Parent.Controllers.StateController)

local BackpackState = {}

export type Desc = ItemData.Desc
export type Stack = { Key: string, Desc: Desc, Count: number }
export type Backpack = {
	Equipped: string, -- the worn pack's id (BackpackData; a newer build's id is kept)
	Name: string, -- the worn pack's name ("Backpack" for an id this build doesn't know)
	Count: number, -- items inside
	Capacity: number,
	Full: boolean,
	Stacks: { Stack },
}

BackpackState.CountAttribute = "CarryCount"
BackpackState.CapacityAttribute = "CarryCapacity"

-- A whole count >= 0 (anything broken = 0).
local function whole(v: any): number
	return if type(v) == "number" and v == v and v > 0 and v < math.huge then math.floor(v) else 0
end

-- Sort groups: dirty ore first (the usual load), dusty relics, cleaned ore, everything else.
local GROUP = { Raw = 1, Relic = 2, Clean = 3 } :: { [string]: number }

local function rarityOrder(oreId: string): number
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	return if info then info.Order else 0
end

-- The stacks of a State.Backpacks.Items table, sorted (see the header). Pure.
function BackpackState.parse(items: any): { Stack }
	local list: { Stack } = {}
	if type(items) ~= "table" then
		return list
	end
	for key, n in items do
		local count = whole(n)
		local desc = if type(key) == "string" and count > 0 then ItemData.parseStoredKey(key) else nil
		if desc then
			table.insert(list, { Key = key, Desc = desc, Count = count })
		end
	end
	table.sort(list, function(a: Stack, b: Stack): boolean
		local ga, gb = GROUP[a.Desc.K] or 4, GROUP[b.Desc.K] or 4
		if ga ~= gb then
			return ga < gb
		end
		-- (dirty ore and relics never sort by what they hide: by key only)
		if ga >= 3 then
			local ra, rb = rarityOrder(a.Desc.O), rarityOrder(b.Desc.O)
			if ra ~= rb then
				return ra > rb
			end
			local la, lb = ItemData.gradeLevel(a.Desc.G), ItemData.gradeLevel(b.Desc.G)
			if la ~= lb then
				return la > lb
			end
		end
		return a.Key < b.Key
	end)
	return list
end

-- A snapshot's State.Backpacks (an empty table when missing).
local function sectionOf(state: any): { [string]: any }
	return if type(state) == "table" and type(state.Backpacks) == "table" then state.Backpacks else {}
end

-- The item count: the CarryCount attribute when given, else the snapshot's (else its stacks' sum).
local function countOf(section: { [string]: any }, count: any?, stacks: { Stack }?): number
	if type(count) == "number" then
		return whole(count)
	elseif type(section.Count) == "number" then
		return whole(section.Count)
	end
	local n = 0
	for _, stack in stacks or BackpackState.parse(section.Items) do
		n += stack.Count
	end
	return n
end

-- The capacity: the CarryCapacity attribute when given, else the snapshot's, else the worn pack's.
local function capacityOf(section: { [string]: any }, capacity: any?): number
	local cap = whole(capacity)
	if cap <= 0 then
		cap = whole(section.Capacity)
	end
	if cap <= 0 then
		cap = BackpackData.capacity(section.Equipped)
	end
	return cap
end

--[[
	The Backpack a State snapshot describes. `count` / `capacity` (the
	CarryCount / CarryCapacity attributes) win over the snapshot's when
	given: a count of 0 empties the stacks (the attribute is newer). Pure.
]]
function BackpackState.read(state: any, count: any?, capacity: any?): Backpack
	local section = sectionOf(state)
	local equipped = if type(section.Equipped) == "string" then section.Equipped else BackpackData.StarterId
	local pack = BackpackData.ById[equipped]
	local stacks = BackpackState.parse(section.Items)
	local n = countOf(section, count, stacks)
	if n == 0 then
		stacks = {}
	end
	local cap = capacityOf(section, capacity)
	return {
		Equipped = equipped,
		Name = if pack then pack.Name else "Backpack",
		Count = n,
		Capacity = cap,
		Full = n >= cap,
		Stacks = stacks,
	}
end

local function attribute(name: string): any
	local player = Players.LocalPlayer
	return if player then player:GetAttribute(name) else nil
end

-- The backpack now: the latest State snapshot and the CarryCount / CarryCapacity attributes.
function BackpackState.get(): Backpack
	return BackpackState.read(StateController.get(), attribute(BackpackState.CountAttribute), attribute(BackpackState.CapacityAttribute))
end

-- (count / capacity / isFull read no stacks: cheap enough for a loop)
function BackpackState.count(): number
	return countOf(sectionOf(StateController.get()), attribute(BackpackState.CountAttribute))
end

function BackpackState.capacity(): number
	return capacityOf(sectionOf(StateController.get()), attribute(BackpackState.CapacityAttribute))
end

function BackpackState.isFull(): boolean
	return BackpackState.count() >= BackpackState.capacity()
end

-- Does the backpack (default: get()) hold an item matching `predicate` (nil = anything)?
function BackpackState.has(predicate: ((Desc) -> boolean)?, backpack: Backpack?): boolean
	local b = backpack or BackpackState.get()
	if b.Count <= 0 then
		return false
	end
	for _, stack in b.Stacks do
		if not predicate or predicate(stack.Desc) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- the prompt rules' predicates

function BackpackState.anything(_desc: Desc): boolean
	return true
end

-- The train's "Load Train" and the pen's "Put In": everything but dusty relics (cleaned, never shipped or stored).
function BackpackState.notRelic(desc: Desc): boolean
	return desc.K ~= "Relic"
end

-- "Put On Podium": a cleaned ore (EconomyConfig.Podiums.Kinds).
function BackpackState.podiumOre(desc: Desc): boolean
	return EconomyConfig.Podiums.Kinds[desc.K] == true
end

-- The Cleaning Station's vise: dirty ore or a dusty relic.
function BackpackState.cleanable(desc: Desc): boolean
	return desc.K == "Raw" or desc.K == "Relic"
end

---------------------------------------------------------------- changes

--[[
	callback() whenever the backpack may have changed: every State push and
	every CarryCount / CarryCapacity change (the attribute comes first, the
	snapshot with the items a moment later: both refresh).
]]
function BackpackState.onChanged(callback: () -> ())
	StateController.onChanged(function()
		callback()
	end)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal(BackpackState.CountAttribute):Connect(callback)
		player:GetAttributeChangedSignal(BackpackState.CapacityAttribute):Connect(callback)
	end
end

return BackpackState
