--[[
	Laser blasters (design v2, they replace pickaxes) and the rocks they break.

	- Hold the fire button: a beam hits the rock you aim at and takes
	  Damage HP per second. A rock needs the zone's MinBlaster level
	  (WorldLayout.Zones) before the beam does anything.
	- 10 levels; level 11 is shown as "Coming soon". New levels are bought in
	  the Blaster Vault for coins (owner 2026-10-24: no Foundry any more; the
	  enchants in the shop make a blaster better). The blaster takes the look
	  of its case's ore (data.BlasterOre, "" = the rusty starter look) and a
	  small damage bonus from that ore's rarity.
	- Rocks hold 1-3 ores (OreCountOdds). Their HP comes from the zone and
	  grows with the number and hardness of the ores inside (rockHealth).
]]

local OreData = require(script.Parent.OreData)

export type Blaster = {
	Level: number,
	Name: string,
	Damage: number, -- rock HP per second
	Range: number, -- studs from the character to the rock surface
	-- the level's coin scale (nil for level 1, everyone starts with it): the Vault price is
	-- Coins x Vault.PriceMultiplier, and the prices that follow the blaster (hoverboards, the
	-- lift, coin boosts, quest floors, the rebirth stars) scale with it (the Foundry's old prices)
	Coins: number?,
	ComingSoon: boolean?,
}

local BlasterData = {}

BlasterData.Levels = {
	{ Level = 1, Name = "Rusty Blaster", Damage = 5, Range = 22 },
	{ Level = 2, Name = "Scrap Blaster", Damage = 9, Range = 24, Coins = 350 },
	{ Level = 3, Name = "Spark Blaster", Damage = 16, Range = 26, Coins = 17000 },
	{ Level = 4, Name = "Ember Blaster", Damage = 29, Range = 28, Coins = 710000 },
	{ Level = 5, Name = "Forgefire Blaster", Damage = 52, Range = 30, Coins = 2.1e6 },
	{ Level = 6, Name = "Sunlance", Damage = 94, Range = 32, Coins = 73e6 },
	{ Level = 7, Name = "Stormlance", Damage = 170, Range = 34, Coins = 130e6 },
	{ Level = 8, Name = "Starlance", Damage = 305, Range = 36, Coins = 2.2e9 },
	{ Level = 9, Name = "Royal Sunlance", Damage = 550, Range = 38, Coins = 31e9 },
	{ Level = 10, Name = "Heartlance", Damage = 990, Range = 40, Coins = 290e9 },
	{ Level = 11, Name = "???", Damage = 0, Range = 0, ComingSoon = true },
} :: { Blaster }

BlasterData.MaxLevel = 10

-- Extra damage from the rarity of the blaster's ore (its case's, BlasterData.vaultOre).
BlasterData.RarityBonus = {
	Common = 0,
	Uncommon = 0.05,
	Rare = 0.1,
	Epic = 0.15,
	Legendary = 0.2,
	Mythic = 0.3,
} :: { [string]: number }

-- The starter blaster's look (used when data.BlasterOre is "").
BlasterData.RustySkin = {
	Color = Color3.fromRGB(150, 96, 64),
	Glow = Color3.fromRGB(255, 150, 70),
}

BlasterData.Beam = {
	ServerTick = 0.1, -- seconds between damage ticks on the server
	MaxTickGap = 0.35, -- a longer gap (lag) counts as this much, so lag never gives burst damage
	ClientRetarget = 0.15, -- the client tells the server about a new target at most this often
	RangeSlack = 4, -- extra studs the server allows (latency, rock radius estimate)
}

BlasterData.Rocks = {
	OreCountOdds = { 0.55, 0.32, 0.13 }, -- chance of 1, 2 or 3 ores in a rock
	ArtifactChance = 0.01, -- per rock (artifacts arrive in step 7)
}

--[[
	The Blaster Vault (the blaster shop at the end of the lobby's south road):
	the only way to a better blaster (owner 2026-10-24). It sells your NEXT
	blaster level for coins, in the look of that level's weapon case, and
	opens the case in the crate-opening cinematic. Levels go in order (no
	skipping).
]]
BlasterData.Vault = {
	-- x the level's Coins: `lune run tools/lune/balance_sim.luau calibrate-vault` puts a typical
	-- player at LV 10 at ~8 h with it (2026-10-24, no Foundry; 4 while the Foundry was the cheap way)
	PriceMultiplier = 1.15,
	-- A rebirth keeps the factory and its income (droppers, Money Lasers, the podiums with
	-- Podium Keeper), so in a rebirth run the low levels would cost seconds and the stars
	-- would farm. There a level costs at least RunShare x RunSeconds[level] seconds of the
	-- income kept at the rebirth (Stats.RunIncome, RebirthService): RunSeconds are the gaps
	-- of a first run (balance_sim's targets), so an idle run takes at least RunShare of one.
	RunShare = 0.5,
	RunSeconds = { [2] = 180, [3] = 540, [4] = 780, [5] = 1200, [6] = 2100, [7] = 2400, [8] = 4500, [9] = 6300, [10] = 10800 },
	-- the ore look of each level's case (ores kept in the 36-ore roster too); the
	-- ores' rarity never falls as the level rises (owner 2026-10-20: LV 4 Emberite,
	-- LV 6 Sapphire, LV 7 Amethyst, so the case colours follow the rarity)
	Ores = { "", "Copper", "Cobalt", "Emberite", "Gold", "Sapphire", "Amethyst", "Obsidian", "RoyalAurum", "Heartstone" },
}

--[[
	The coin price of a level's case in the Blaster Vault (nil for level 1 and
	unknown levels): Coins x PriceMultiplier rounded to 2 significant digits,
	and in a rebirth run at least `runIncome` (Stats.RunIncome, coins / s) x
	RunShare x RunSeconds[level], rounded up to 2 significant digits.
]]
function BlasterData.vaultPrice(level: any, runIncome: number?): number?
	if type(level) ~= "number" or level ~= math.floor(level) then
		return nil
	end
	local blaster = BlasterData.ByLevel[level]
	if not blaster or not blaster.Coins or blaster.ComingSoon then
		return nil
	end
	local raw = blaster.Coins * BlasterData.Vault.PriceMultiplier
	local digits = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	local price = math.floor(raw / digits + 0.5) * digits
	local seconds = BlasterData.Vault.RunSeconds[level]
	if seconds and type(runIncome) == "number" and runIncome == runIncome and runIncome > 0 then
		local floor = math.min(runIncome, 1e27) * seconds * BlasterData.Vault.RunShare
		if floor > price then
			local step = 10 ^ math.max(0, math.floor(math.log10(floor)) - 1)
			price = math.ceil(floor / step) * step
		end
	end
	return price
end

-- A level's coin scale (0 for level 1 and unknown levels): what the prices that follow
-- the blaster scale with.
function BlasterData.coins(level: any): number
	local blaster = if type(level) == "number" then BlasterData.ByLevel[level] else nil
	return if blaster and blaster.Coins then blaster.Coins else 0
end

-- The ore look of a level's case ("" = the rusty starter look).
function BlasterData.vaultOre(level: any): string
	local n = if type(level) == "number" and level == level then math.floor(level) else 1
	return BlasterData.Vault.Ores[math.clamp(n, 1, #BlasterData.Vault.Ores)] or ""
end

BlasterData.ByLevel = {} :: { [number]: Blaster }
for _, blaster in BlasterData.Levels do
	BlasterData.ByLevel[blaster.Level] = blaster
end

-- The level coin prices that grow with the blaster follow (capsules, coin
-- boosts, the wheel's capsule fallback): the highest level the save ever
-- had (Stats.BestBlaster, written by a rebirth) or the level now, so a
-- rebirth never makes them cheaper (rebirth B keeps the income).
function BlasterData.priceLevel(data: any): number
	local level = BlasterData.get(if type(data) == "table" then data.BlasterLevel else nil).Level
	local stats = if type(data) == "table" then data.Stats else nil
	local best = if type(stats) == "table" then stats.BestBlaster else nil
	if type(best) == "number" and best == best and best > level then
		level = math.min(math.floor(best), BlasterData.MaxLevel)
	end
	return level
end

-- The blaster for a saved level (clamped to 1..MaxLevel).
function BlasterData.get(level: any): Blaster
	local n = if type(level) == "number" and level == level then math.floor(level) else 1
	return BlasterData.ByLevel[math.clamp(n, 1, BlasterData.MaxLevel)]
end

-- Damage per second of a blaster level forged from `oreId` ("" = rusty).
function BlasterData.damage(level: any, oreId: string?): number
	local blaster = BlasterData.get(level)
	local ore = if oreId and oreId ~= "" then OreData.ById[oreId] else nil
	local bonus = if ore then BlasterData.RarityBonus[ore.Rarity] or 0 else 0
	return blaster.Damage * (1 + bonus)
end

-- Display name, e.g. "Gold Spark Blaster" (or "Rusty Blaster"). A word the ore's
-- name already has is said once: Royal Aurum + Royal Sunlance = "Royal Aurum Sunlance".
function BlasterData.displayName(level: any, oreId: string?): string
	local blaster = BlasterData.get(level)
	local ore = if oreId and oreId ~= "" then OreData.ById[oreId] else nil
	if ore and blaster.Level > 1 then
		local said = {}
		for word in string.gmatch(ore.Name, "%S+") do
			said[string.lower(word)] = true
		end
		local words = { ore.Name }
		for word in string.gmatch(blaster.Name, "%S+") do
			if not said[string.lower(word)] then
				table.insert(words, word)
			end
		end
		return table.concat(words, " ")
	end
	return blaster.Name
end

-- Colors of a blaster forged from `oreId` (the rusty look for "" or unknown ores).
function BlasterData.skin(oreId: string?): (Color3, Color3)
	local ore = if oreId and oreId ~= "" then OreData.ById[oreId] else nil
	if ore then
		return ore.Color, ore.Glow
	end
	return BlasterData.RustySkin.Color, BlasterData.RustySkin.Glow
end

-- HP of a rock with base health `zoneHealth` holding these ores.
function BlasterData.rockHealth(zoneHealth: number, oreIds: { string }): number
	local count = math.max(1, #oreIds)
	local hardest = 1
	for _, oreId in oreIds do
		local ore = OreData.ById[oreId]
		if ore and ore.Hardness > hardest then
			hardest = ore.Hardness
		end
	end
	return math.max(1, math.floor(zoneHealth * (0.7 + 0.3 * count) * (1 + 0.04 * (hardest - 1)) + 0.5))
end

-- How many ores a rock gets for a roll in [0, 1).
function BlasterData.oreCount(roll: number): number
	local acc = 0
	for count, chance in BlasterData.Rocks.OreCountOdds do
		acc += chance
		if roll < acc then
			return count
		end
	end
	return #BlasterData.Rocks.OreCountOdds
end

return BlasterData
