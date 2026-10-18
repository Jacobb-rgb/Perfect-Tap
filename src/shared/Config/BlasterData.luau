--[[
	Laser blasters (design v2, they replace pickaxes) and the rocks they break.

	- Hold the fire button: a beam hits the rock you aim at and takes
	  Damage HP per second. A rock needs the zone's MinBlaster level
	  (WorldLayout.Zones) before the beam does anything.
	- 10 levels; level 11 is shown as "Coming soon". New levels are forged in
	  the Foundry (step 3) from ingots + coins (Recipe). The blaster takes the
	  look of the ore it was forged from (data.BlasterOre, "" = the rusty
	  starter look) and a small damage bonus from that ore's rarity.
	- Rocks hold 1-3 ores (OreCountOdds). Their HP comes from the zone and
	  grows with the number and hardness of the ores inside (rockHealth).
]]

local OreData = require(script.Parent.OreData)

export type Recipe = {
	Ingots: number, -- ingots needed
	MinRarity: string, -- every ingot must be at least this rare
	Coins: number,
}

export type Blaster = {
	Level: number,
	Name: string,
	Damage: number, -- rock HP per second
	Range: number, -- studs from the character to the rock surface
	Recipe: Recipe?, -- nil for level 1 (everyone starts with it)
	ComingSoon: boolean?,
}

local BlasterData = {}

BlasterData.Levels = {
	{ Level = 1, Name = "Rusty Blaster", Damage = 5, Range = 22 },
	{ Level = 2, Name = "Scrap Blaster", Damage = 9, Range = 24, Recipe = { Ingots = 3, MinRarity = "Common", Coins = 330 } },
	{ Level = 3, Name = "Spark Blaster", Damage = 16, Range = 26, Recipe = { Ingots = 5, MinRarity = "Common", Coins = 12000 } },
	{ Level = 4, Name = "Ember Blaster", Damage = 29, Range = 28, Recipe = { Ingots = 6, MinRarity = "Uncommon", Coins = 380000 } },
	{ Level = 5, Name = "Forgefire Blaster", Damage = 52, Range = 30, Recipe = { Ingots = 8, MinRarity = "Uncommon", Coins = 1.5e6 } },
	{ Level = 6, Name = "Sunlance", Damage = 94, Range = 32, Recipe = { Ingots = 8, MinRarity = "Rare", Coins = 29e6 } },
	{ Level = 7, Name = "Stormlance", Damage = 170, Range = 34, Recipe = { Ingots = 10, MinRarity = "Rare", Coins = 51e6 } },
	{ Level = 8, Name = "Starlance", Damage = 305, Range = 36, Recipe = { Ingots = 10, MinRarity = "Epic", Coins = 1.2e9 } },
	{ Level = 9, Name = "Royal Sunlance", Damage = 550, Range = 38, Recipe = { Ingots = 12, MinRarity = "Epic", Coins = 2.1e9 } },
	{ Level = 10, Name = "Heartlance", Damage = 990, Range = 40, Recipe = { Ingots = 12, MinRarity = "Legendary", Coins = 35e9 } },
	{ Level = 11, Name = "???", Damage = 0, Range = 0, ComingSoon = true },
} :: { Blaster }

BlasterData.MaxLevel = 10

-- Extra damage from the rarity of the ore a blaster was forged from.
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
	it sells your NEXT blaster level for coins only (no ingots), in the look of
	that level's weapon case, and opens the case in the crate-opening
	cinematic. Levels go in order (no skipping). The Foundry stays the cheaper
	way (ingots + coins) and lets you pick the ore look.
]]
BlasterData.Vault = {
	PriceMultiplier = 4, -- x the level's Foundry coin price (Recipe.Coins)
	-- the ore look of each level's case (ores kept in the 36-ore roster too)
	Ores = { "", "Copper", "Cobalt", "Amethyst", "Gold", "Emberite", "Sapphire", "Obsidian", "RoyalAurum", "Heartstone" },
}

-- The coin price of a level's case in the Blaster Vault (nil for level 1 and unknown levels).
function BlasterData.vaultPrice(level: any): number?
	if type(level) ~= "number" or level ~= math.floor(level) then
		return nil
	end
	local blaster = BlasterData.ByLevel[level]
	if not blaster or not blaster.Recipe or blaster.ComingSoon then
		return nil
	end
	return blaster.Recipe.Coins * BlasterData.Vault.PriceMultiplier
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

-- Display name, e.g. "Gold Spark Blaster" (or "Rusty Blaster").
function BlasterData.displayName(level: any, oreId: string?): string
	local blaster = BlasterData.get(level)
	local ore = if oreId and oreId ~= "" then OreData.ById[oreId] else nil
	if ore and blaster.Level > 1 then
		return ore.Name .. " " .. blaster.Name
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
