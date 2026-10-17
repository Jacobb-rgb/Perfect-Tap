--[[
	Blaster enchants (steps 6-7): perks bought at the Enchant shop (the rune
	table in town, hook EnchantCounter), owned forever and put into the
	blaster's enchant slots. Changing slots is free.

	- Slots: 1 at blaster level 1, 2 at level 4, 3 at level 7, 4 at level 10
	  (SlotLevels). Only enchants in an open slot work.
	- Every enchant has tiers (I, II, III; the two Mythics have one). "Buy"
	  buys the next tier; the Tier the client sends must be exactly current + 1
	  (quote, "Stale" otherwise), so a double tap never buys two tiers.
	- Prices grow with rarity (about x10-x20 per rarity) and x6 per tier.
	  Epic and Legendary enchants can also be paid with crystal shards
	  (data.Shards). The two Mythics ("Heartfire", "Starbreaker") cost an
	  enormous amount of coins OR 20 Robux (MonetizationConfig GAME PASSES
	  EnchantHeartfire / EnchantStarbreaker, one-time by design; "Coming soon"
	  while the id is 0; step 8 grants the enchant to pass owners on join and
	  after the purchase). The Robux option is hidden once the enchant is
	  owned (quote answers "Max").
	- Unknown enchant ids and tiers above today's count stay in the save (a
	  newer server may sell them, Migrations); every reader here ignores or
	  clamps them, and grant() never lowers a saved tier.

	Saved as data.Enchants = {
	  Owned = { [enchantId] = tier (whole 1..#tiers) },
	  Slots = { id | "", id | "", id | "", id | "" } (exactly MaxSlots strings,
	          "" = empty; an id sits in at most one slot and must be owned),
	}
	EnchantAction ("Buy", { Id, Currency = "Coins" | "Shards" | "Robux", Tier })
	              ("Slot", { Slot = 1..MaxSlots, Id = enchantId? (nil / "" = empty the slot) })
	The effects reach the game through src/server/Bonuses.luau (stats below).
]]

local MonetizationConfig = require(script.Parent.MonetizationConfig)
local Rarity = require(script.Parent.Rarity)
local StatConfig = require(script.Parent.StatConfig)

export type Enchant = {
	Id: string,
	Name: string,
	Rarity: string,
	Description: string,
	Effects: { [string]: { number } }, -- StatConfig id -> value per tier
	Coins: { number }, -- coin price per tier
	Shards: { number }?, -- shard price per tier (Epic and Legendary)
	Product: string?, -- MonetizationConfig key (the two Mythics: a 20 Robux game pass)
	Color: Color3, -- rune color on cards and the blaster
}

local EnchantConfig = {}

EnchantConfig.MaxSlots = 4
EnchantConfig.SlotLevels = { 1, 4, 7, 10 } -- blaster level that opens slot i
EnchantConfig.TierNames = { "I", "II", "III", "IV", "V" }
EnchantConfig.Currencies = { Coins = true, Shards = true, Robux = true } :: { [string]: boolean }
-- studs from an EnchantCounter's surface the server accepts a buy
EnchantConfig.Range = 30
EnchantConfig.Tag = "EnchantCounter"

-- EnchantAction / ActionResult reason codes -> text for the player
EnchantConfig.Reasons = {
	BadItem = "That isn't sold here",
	BadCurrency = "It can't be bought that way",
	Max = "Already at the top tier",
	Stale = "The card was out of date, try again",
	NoCoins = "Not enough coins",
	NoShards = "Not enough crystal shards",
	TooFar = "Go to the Enchant shop to buy",
	Robux = "Robux purchase", -- the server answers with PurchasePrompt instead
	BadSlot = "That slot doesn't exist",
	Locked = "Forge a stronger blaster to open this slot",
	NotOwned = "Buy this enchant first",
} :: { [string]: string }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

EnchantConfig.List = {
	---------------------------------------------------------------- Common
	{
		Id = "Power",
		Name = "Power",
		Rarity = "Common",
		Description = "Your beam hits harder.",
		Effects = { DamagePct = { 0.1, 0.2, 0.35 } },
		Coins = { 2000, 12000, 72000 },
		Color = rgb(255, 120, 60),
	},
	{
		Id = "Swift",
		Name = "Swift",
		Rarity = "Common",
		Description = "Light feet: you walk faster.",
		Effects = { WalkSpeed = { 1, 2, 3 } },
		Coins = { 1500, 9000, 54000 },
		Color = rgb(120, 230, 255),
	},
	---------------------------------------------------------------- Uncommon
	{
		Id = "Reach",
		Name = "Reach",
		Rarity = "Uncommon",
		Description = "Your beam reaches further.",
		Effects = { ReachStuds = { 2, 4, 6 } },
		Coins = { 20000, 120000, 720000 },
		Color = rgb(150, 200, 120),
	},
	{
		Id = "Magnetism",
		Name = "Magnetism",
		Rarity = "Uncommon",
		Description = "Your ore magnet pulls from further away.",
		Effects = { MagnetRadius = { 3, 6, 10 } },
		Coins = { 15000, 90000, 540000 },
		Color = rgb(200, 90, 255),
	},
	---------------------------------------------------------------- Rare
	{
		Id = "Lucky",
		Name = "Lucky",
		Rarity = "Rare",
		Description = "Rare and rarer ores show up more often in the rocks you break.",
		Effects = { OreLuckPct = { 0.15, 0.3, 0.5 } },
		Coins = { 250000, 1500000, 9000000 },
		Color = rgb(90, 220, 120),
	},
	{
		Id = "Midas",
		Name = "Midas",
		Rarity = "Rare",
		Description = "Tobin pays more for everything you sell.",
		Effects = { SellPct = { 0.1, 0.2, 0.35 } },
		Coins = { 200000, 1200000, 7200000 },
		Color = rgb(255, 205, 70),
	},
	---------------------------------------------------------------- Epic
	{
		Id = "TwinDrop",
		Name = "Twin Drop",
		Rarity = "Epic",
		Description = "Sometimes an ore drops twice.",
		Effects = { TwinDropChance = { 0.05, 0.1, 0.15 } },
		Coins = { 5000000, 30000000, 180000000 },
		Shards = { 40, 120, 360 },
		Color = rgb(120, 160, 255),
	},
	{
		Id = "Overcharge",
		Name = "Overcharge",
		Rarity = "Epic",
		Description = "Your beam surges when a rock is about to break.",
		Effects = { OverchargePct = { 0.25, 0.5, 0.8 } },
		Coins = { 4000000, 24000000, 144000000 },
		Shards = { 30, 90, 270 },
		Color = rgb(255, 90, 90),
	},
	---------------------------------------------------------------- Legendary
	{
		Id = "Prospector",
		Name = "Prospector",
		Rarity = "Legendary",
		Description = "Lost artifacts of Kaldrum turn up more often.",
		Effects = { ArtifactPct = { 0.25, 0.5, 1 } },
		Coins = { 100000000, 600000000, 3600000000 },
		Shards = { 150, 450, 1350 },
		Color = rgb(230, 170, 90),
	},
	{
		Id = "GolemBond",
		Name = "Golem Bond",
		Rarity = "Legendary",
		Description = "Your equipped golems give bigger bonuses.",
		Effects = { GolemBondPct = { 0.1, 0.25, 0.5 } },
		Coins = { 120000000, 720000000, 4300000000 },
		Shards = { 180, 540, 1600 },
		Color = rgb(170, 220, 230),
	},
	---------------------------------------------------------------- Mythic
	{
		Id = "Heartfire",
		Name = "Heartfire",
		Rarity = "Mythic",
		Description = "A spark of the Heartstone itself: a fierce beam that surges on cracked rock.",
		Effects = { DamagePct = { 0.75 }, OverchargePct = { 0.5 } },
		Coins = { 1e12 },
		Product = "EnchantHeartfire",
		Color = rgb(255, 80, 40),
	},
	{
		Id = "Starbreaker",
		Name = "Starbreaker",
		Rarity = "Mythic",
		Description = "Forged from a fallen star: rare ores and lost artifacts find you.",
		Effects = { OreLuckPct = { 0.75 }, ArtifactPct = { 0.5 } },
		Coins = { 1e12 },
		Product = "EnchantStarbreaker",
		Color = rgb(150, 120, 255),
	},
} :: { Enchant }

EnchantConfig.ById = {} :: { [string]: Enchant }
for _, enchant in EnchantConfig.List do
	EnchantConfig.ById[enchant.Id] = enchant
	local product = enchant.Product
	assert(product == nil or MonetizationConfig.Products[product], "EnchantConfig: unknown product " .. tostring(product))
end

-- Rarity order of an enchant (Common 1 .. Mythic 6), for sorting.
function EnchantConfig.order(id: string): number
	local enchant = EnchantConfig.ById[id]
	local info = if enchant then Rarity.ById[enchant.Rarity] else nil
	return if info then info.Order else 0
end

-- Number of tiers an enchant has.
function EnchantConfig.tiers(id: string): number
	local enchant = EnchantConfig.ById[id]
	return if enchant then #enchant.Coins else 0
end

-- Open slots for a blaster level (1..MaxSlots).
function EnchantConfig.unlockedSlots(blasterLevel: any): number
	local level = if type(blasterLevel) == "number" and blasterLevel == blasterLevel then blasterLevel else 1
	local count = 0
	for _, needed in EnchantConfig.SlotLevels do
		if level >= needed then
			count += 1
		end
	end
	return math.max(1, count)
end

-- The owned tier of an enchant in a data.Enchants record (0 = not owned).
function EnchantConfig.tierOf(enchants: any, id: string): number
	local owned = if type(enchants) == "table" then enchants.Owned else nil
	local tier = if type(owned) == "table" then owned[id] else nil
	if type(tier) ~= "number" or tier ~= tier then
		return 0
	end
	return math.clamp(math.floor(tier), 0, EnchantConfig.tiers(id))
end

-- The value of one stat of an enchant at a tier (0 below tier 1).
function EnchantConfig.value(id: string, stat: string, tier: number): number
	local enchant = EnchantConfig.ById[id]
	local values = if enchant then enchant.Effects[stat] else nil
	if not values or tier < 1 then
		return 0
	end
	return values[math.min(tier, #values)]
end

-- Card lines for an enchant at a tier: { "+10% blaster damage", ... }.
function EnchantConfig.describe(id: string, tier: number): { string }
	local enchant = EnchantConfig.ById[id]
	local lines = {}
	if enchant then
		local stats = {}
		for stat in enchant.Effects do
			table.insert(stats, stat)
		end
		table.sort(stats)
		for _, stat in stats do
			table.insert(lines, StatConfig.describe(stat, EnchantConfig.value(id, stat, tier)))
		end
	end
	return lines
end

-- Prices of the next tier: coins, shards (nil when not sold for shards) and the
-- Robux product key (nil when not sold for Robux). All nil at the top tier.
function EnchantConfig.nextPrice(id: string, currentTier: number): (number?, number?, string?)
	local enchant = EnchantConfig.ById[id]
	if not enchant or currentTier >= #enchant.Coins then
		return nil, nil, nil
	end
	local shards = enchant.Shards
	return enchant.Coins[currentTier + 1], if shards then shards[currentTier + 1] else nil, enchant.Product
end

-- The server's check of an EnchantAction "Buy" for this save: the price in
-- `currency` of the next tier when `tier` (from the client: the tier being
-- bought, as the card shows it) is exactly current + 1.
-- nil + "BadItem" | "BadCurrency" | "Max" | "Stale" | "Robux" (EnchantConfig.Reasons;
-- "Robux": a valid Robux buy, answered with PurchasePrompt, never granted here).
function EnchantConfig.quote(enchants: any, id: any, currency: any, tier: any): (number?, string?)
	if type(id) ~= "string" or not EnchantConfig.ById[id] then
		return nil, "BadItem"
	end
	if type(currency) ~= "string" or not EnchantConfig.Currencies[currency] then
		return nil, "BadCurrency"
	end
	local current = EnchantConfig.tierOf(enchants, id)
	local coins, shards, product = EnchantConfig.nextPrice(id, current)
	if coins == nil then
		return nil, "Max"
	end
	if tier ~= current + 1 then
		return nil, "Stale"
	end
	if currency == "Coins" then
		return coins, nil
	elseif currency == "Shards" then
		if shards == nil then
			return nil, "BadCurrency"
		end
		return shards, nil
	end
	if product == nil then
		return nil, "BadCurrency"
	end
	return nil, "Robux"
end

-- Gives the next tier of `id` (after a paid buy or a game pass). Returns
-- the new tier; at the top tier nothing is written (a higher tier saved by a
-- newer server is never lowered); 0 for an unknown id. Makes the record's
-- tables when they are missing.
function EnchantConfig.grant(enchants: { [string]: any }, id: string): number
	if not EnchantConfig.ById[id] then
		return 0
	end
	local current = EnchantConfig.tierOf(enchants, id)
	if current >= EnchantConfig.tiers(id) then
		return current
	end
	local owned = enchants.Owned
	if type(owned) ~= "table" then
		owned = {}
		enchants.Owned = owned
	end
	owned[id] = current + 1
	return current + 1
end

-- The first open, empty slot for this blaster level (nil when none).
function EnchantConfig.firstFreeSlot(enchants: any, blasterLevel: any): number?
	local slots = if type(enchants) == "table" then enchants.Slots else nil
	for i = 1, EnchantConfig.unlockedSlots(blasterLevel) do
		local id = if type(slots) == "table" then slots[i] else nil
		if type(id) ~= "string" or id == "" then
			return i
		end
	end
	return nil
end

-- EnchantAction "Slot": puts owned enchant `id` into `slot` (moving it out of
-- any other slot) or empties the slot when `id` is nil or "". Returns true,
-- or false + "BadSlot" | "Locked" | "NotOwned" | "BadItem".
function EnchantConfig.setSlot(enchants: { [string]: any }, blasterLevel: any, slot: any, id: any): (boolean, string?)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > EnchantConfig.MaxSlots then
		return false, "BadSlot"
	end
	if slot > EnchantConfig.unlockedSlots(blasterLevel) then
		return false, "Locked"
	end
	local empty = id == nil or id == ""
	if not empty then
		if type(id) ~= "string" or not EnchantConfig.ById[id] then
			return false, "BadItem"
		end
		if EnchantConfig.tierOf(enchants, id) < 1 then
			return false, "NotOwned"
		end
	end
	local slots = enchants.Slots
	if type(slots) ~= "table" then
		slots = {}
		enchants.Slots = slots
	end
	for i = 1, EnchantConfig.MaxSlots do
		if type(slots[i]) ~= "string" or (not empty and slots[i] == id) then
			slots[i] = ""
		end
	end
	slots[slot] = if empty then "" else id
	return true, nil
end

-- What the slotted enchants give (Bonuses stats): only open slots count.
function EnchantConfig.stats(enchants: any, blasterLevel: any): { [string]: number }
	local out: { [string]: number } = {}
	local slots = if type(enchants) == "table" then enchants.Slots else nil
	if type(slots) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for i = 1, EnchantConfig.unlockedSlots(blasterLevel) do
		local id = slots[i]
		local enchant = if type(id) == "string" then EnchantConfig.ById[id] else nil
		if enchant and not seen[id] then
			seen[id] = true
			local tier = EnchantConfig.tierOf(enchants, id)
			for stat in enchant.Effects do
				local value = EnchantConfig.value(id, stat, tier)
				out[stat] = (out[stat] or 0) + value
			end
		end
	end
	return out
end

return EnchantConfig
