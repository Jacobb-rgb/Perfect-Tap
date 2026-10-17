--[[
	All 36 ores in Terra Forge (the owner's ore picture, 2026-10-18). Add a new ore by adding one entry
	to the list and giving it a weight in WorldLayout.Zones so rocks in that
	zone can contain it.

	Money: an ore earns `Income` coins per second while it sits on a podium
	(Rough grade; cleaning grades multiply it, see ItemData.income). Selling it
	at the Sell stall pays `Value` = Income * SellSeconds (ItemData.value).
	Every ore has its own Shape: a unique silhouette built by ItemBuilder.
	Rocks hide their ores: a raw chunk is "Dirty Ore" until it is cleaned.
]]

export type Ore = {
	Id: string,
	Name: string,
	Rarity: string,
	Tier: number, -- blaster level the ore usually needs (its home zone's MinBlaster)
	Income: number, -- coins per second on a podium (Rough grade)
	Value: number, -- sell value of 1 clean Rough ore (Income * SellSeconds)
	Hardness: number, -- how much tougher it makes the rock it sits in
	Color: Color3, -- main ore color (cleaned ore, ingots, blaster skin)
	Glow: Color3, -- neon/glow color (veins, tips, laser)
	Crust: Color3, -- rock crust color around the ore
	Shape: string, -- unique silhouette family (ItemBuilder)
	Material: Enum.Material, -- surface of the cleaned ore
	Lore: string,
}

local OreData = {}

-- Selling an ore pays this many seconds of its podium income.
OreData.SellSeconds = 30

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

-- Value is filled in below (Income * SellSeconds). The roster, names, rarities and looks follow the
-- owner's ore picture (docs/art/ores_reference.webp, 2026-10-18): Shape = the ore's own look in
-- ItemBuilder (OreShapesLow / OreShapesHigh).
local LIST: { any } = {
	---------------------------------------------------------------- Common
	{
		Id = "Coal",
		Name = "Coal",
		Rarity = "Common",
		Tier = 1,
		Income = 1,
		Hardness = 1,
		Color = rgb(44, 42, 50),
		Glow = rgb(255, 122, 58),
		Crust = rgb(96, 88, 82),
		Shape = "Coal",
		Material = M.Slate,
		Lore = "A heap of black chunks that still remember fire. Every forge in Emberfall starts with coal.",
	},
	{
		Id = "Copper",
		Name = "Copper",
		Rarity = "Common",
		Tier = 1,
		Income = 2,
		Hardness = 1,
		Color = rgb(190, 98, 54),
		Glow = rgb(255, 150, 90),
		Crust = rgb(110, 86, 72),
		Shape = "Copper",
		Material = M.Metal,
		Lore = "Warm brown nuggets, faceted like little gems. Every Forgekeeper's first ore.",
	},
	{
		Id = "Tin",
		Name = "Tin",
		Rarity = "Common",
		Tier = 1,
		Income = 3,
		Hardness = 1.2,
		Color = rgb(176, 184, 196),
		Glow = rgb(226, 236, 248),
		Crust = rgb(100, 102, 98),
		Shape = "Tin",
		Material = M.Metal,
		Lore = "Pale cubes that grow stacked on each other. Kaldrum's smiths mixed it into bronze bells.",
	},
	{
		Id = "Iron",
		Name = "Iron",
		Rarity = "Common",
		Tier = 1,
		Income = 4,
		Hardness = 1.4,
		Color = rgb(128, 134, 146),
		Glow = rgb(214, 226, 240),
		Crust = rgb(96, 84, 80),
		Shape = "Iron",
		Material = M.Metal,
		Lore = "Heavy grey blocks, the backbone of Emberfall.",
	},
	{
		Id = "Quartz",
		Name = "Quartz",
		Rarity = "Common",
		Tier = 1,
		Income = 5,
		Hardness = 1.6,
		Color = rgb(238, 238, 246),
		Glow = rgb(255, 255, 255),
		Crust = rgb(122, 112, 110),
		Shape = "Quartz",
		Material = M.Glass,
		Lore = "A crown of clear six-sided spikes. Hold one to the sun and it throws tiny rainbows.",
	},
	{
		Id = "Oakwood",
		Name = "Oakwood",
		Rarity = "Common",
		Tier = 1,
		Income = 6,
		Hardness = 1.8,
		Color = rgb(132, 88, 52),
		Glow = rgb(120, 206, 84),
		Crust = rgb(84, 70, 56),
		Shape = "Oakwood",
		Material = M.Wood,
		Lore = "A stone-hard oak log with fresh leaves. The old forest sank into the rock and kept growing.",
	},
	{
		Id = "Honeycomb",
		Name = "Honeycomb",
		Rarity = "Common",
		Tier = 1,
		Income = 8,
		Hardness = 2,
		Color = rgb(255, 186, 40),
		Glow = rgb(255, 216, 96),
		Crust = rgb(110, 86, 52),
		Shape = "Honeycomb",
		Material = M.Glass,
		Lore = "Golden honey turned to crystal. A cave bee still guards every piece.",
	},
	---------------------------------------------------------------- Uncommon
	{
		Id = "LeafOre",
		Name = "Leaf Ore",
		Rarity = "Uncommon",
		Tier = 1,
		Income = 13,
		Hardness = 2.2,
		Color = rgb(64, 196, 72),
		Glow = rgb(130, 255, 120),
		Crust = rgb(64, 84, 58),
		Shape = "LeafOre",
		Material = M.Glass,
		Lore = "Green crystal points shaped like new leaves. They lean toward the light.",
	},
	{
		Id = "Frostbite",
		Name = "Frostbite",
		Rarity = "Uncommon",
		Tier = 1,
		Income = 20,
		Hardness = 2.5,
		Color = rgb(122, 204, 255),
		Glow = rgb(200, 240, 255),
		Crust = rgb(70, 86, 104),
		Shape = "Frostbite",
		Material = M.Glass,
		Lore = "Ice-blue crystals, cold enough to grow snowflakes around them.",
	},
	{
		Id = "Emberite",
		Name = "Emberite",
		Rarity = "Uncommon",
		Tier = 3,
		Income = 28,
		Hardness = 2.8,
		Color = rgb(222, 48, 40),
		Glow = rgb(255, 110, 60),
		Crust = rgb(70, 46, 40),
		Shape = "Emberite",
		Material = M.Glass,
		Lore = "Red crystals still warm from the Heartstone's fire. They glow in the dark caves.",
	},
	{
		Id = "Cobalt",
		Name = "Cobalt",
		Rarity = "Uncommon",
		Tier = 3,
		Income = 40,
		Hardness = 3.1,
		Color = rgb(76, 52, 206),
		Glow = rgb(140, 112, 255),
		Crust = rgb(60, 62, 84),
		Shape = "Cobalt",
		Material = M.Glass,
		Lore = "Deep blue-violet crystals with black roots. The old railway painted its lamps with it.",
	},
	{
		Id = "Bogwood",
		Name = "Bogwood",
		Rarity = "Uncommon",
		Tier = 3,
		Income = 55,
		Hardness = 3.4,
		Color = rgb(92, 66, 42),
		Glow = rgb(96, 176, 70),
		Crust = rgb(64, 58, 46),
		Shape = "Bogwood",
		Material = M.Wood,
		Lore = "A dark, mossy swamp log as hard as iron. It smells of rain.",
	},
	{
		Id = "Amber",
		Name = "Amber",
		Rarity = "Uncommon",
		Tier = 3,
		Income = 80,
		Hardness = 3.7,
		Color = rgb(255, 168, 28),
		Glow = rgb(255, 204, 80),
		Crust = rgb(104, 80, 50),
		Shape = "Amber",
		Material = M.Glass,
		Lore = "A drop of old sunlight with a sleeping bee inside it.",
	},
	---------------------------------------------------------------- Rare
	{
		Id = "Bronze",
		Name = "Bronze",
		Rarity = "Rare",
		Tier = 3,
		Income = 130,
		Hardness = 4,
		Color = rgb(160, 94, 52),
		Glow = rgb(236, 156, 96),
		Crust = rgb(98, 78, 62),
		Shape = "Bronze",
		Material = M.Metal,
		Lore = "Big brown faceted lumps. Tin and copper that met deep in the rock.",
	},
	{
		Id = "Silver",
		Name = "Silver",
		Rarity = "Rare",
		Tier = 3,
		Income = 190,
		Hardness = 4.6,
		Color = rgb(206, 212, 226),
		Glow = rgb(236, 246, 255),
		Crust = rgb(104, 104, 116),
		Shape = "Silver",
		Material = M.Glass,
		Lore = "Cold, bright spikes. They ring like a bell when the chisel hits.",
	},
	{
		Id = "Gold",
		Name = "Gold",
		Rarity = "Rare",
		Tier = 3,
		Income = 270,
		Hardness = 5.2,
		Color = rgb(255, 196, 40),
		Glow = rgb(255, 226, 110),
		Crust = rgb(102, 82, 60),
		Shape = "Gold",
		Material = M.Glass,
		Lore = "Golden crystal points. Tobin pays well for gold, and better for flawless gold.",
	},
	{
		Id = "Jade",
		Name = "Jade",
		Rarity = "Rare",
		Tier = 3,
		Income = 380,
		Hardness = 6,
		Color = rgb(46, 170, 82),
		Glow = rgb(124, 240, 150),
		Crust = rgb(62, 88, 70),
		Shape = "Jade",
		Material = M.SmoothPlastic,
		Lore = "A smooth green stone with a carved swirl. It never gets warm.",
	},
	{
		Id = "Sapphire",
		Name = "Sapphire",
		Rarity = "Rare",
		Tier = 5,
		Income = 550,
		Hardness = 6.5,
		Color = rgb(40, 92, 232),
		Glow = rgb(96, 152, 255),
		Crust = rgb(50, 54, 82),
		Shape = "Sapphire",
		Material = M.Glass,
		Lore = "Midnight-blue crystal points. The royal astronomers ground them into lenses.",
	},
	{
		Id = "DragonEgg",
		Name = "Dragon Egg",
		Rarity = "Rare",
		Tier = 5,
		Income = 800,
		Hardness = 7,
		Color = rgb(164, 212, 240),
		Glow = rgb(206, 240, 255),
		Crust = rgb(70, 86, 100),
		Shape = "DragonEgg",
		Material = M.SmoothPlastic,
		Lore = "A pale blue egg with stone scales. Nobody knows if it will ever hatch.",
	},
	---------------------------------------------------------------- Epic
	{
		Id = "Diamond",
		Name = "Diamond",
		Rarity = "Epic",
		Tier = 5,
		Income = 1300,
		Hardness = 8,
		Color = rgb(226, 236, 252),
		Glow = rgb(206, 232, 255),
		Crust = rgb(84, 90, 100),
		Shape = "Diamond",
		Material = M.Glass,
		Lore = "A cut gem in a nest of clear crystals. Nothing in Terra is harder.",
	},
	{
		Id = "Amethyst",
		Name = "Amethyst",
		Rarity = "Epic",
		Tier = 5,
		Income = 2000,
		Hardness = 9,
		Color = rgb(152, 72, 232),
		Glow = rgb(204, 134, 255),
		Crust = rgb(86, 74, 96),
		Shape = "Amethyst",
		Material = M.Glass,
		Lore = "Tall violet points. Kaldrum's queens wore them on their way to the throne.",
	},
	{
		Id = "Obsidian",
		Name = "Obsidian",
		Rarity = "Epic",
		Tier = 5,
		Income = 3200,
		Hardness = 10,
		Color = rgb(42, 30, 62),
		Glow = rgb(146, 82, 226),
		Crust = rgb(60, 50, 66),
		Shape = "Obsidian",
		Material = M.Glass,
		Lore = "Black volcano glass that breaks into blades. A purple light lives under the black.",
	},
	{
		Id = "CrystalRose",
		Name = "Crystal Rose",
		Rarity = "Epic",
		Tier = 5,
		Income = 5000,
		Hardness = 11.5,
		Color = rgb(255, 80, 150),
		Glow = rgb(255, 140, 200),
		Crust = rgb(86, 60, 74),
		Shape = "CrystalRose",
		Material = M.Glass,
		Lore = "A rose made of pink crystal. It blooms once in a hundred years.",
	},
	{
		Id = "StormPearl",
		Name = "Storm Pearl",
		Rarity = "Epic",
		Tier = 5,
		Income = 8000,
		Hardness = 13,
		Color = rgb(206, 214, 255),
		Glow = rgb(150, 182, 255),
		Crust = rgb(70, 74, 100),
		Shape = "StormPearl",
		Material = M.Glass,
		Lore = "A glowing pearl wrapped in its own little storm.",
	},
	{
		Id = "GalaxyStone",
		Name = "Galaxy Stone",
		Rarity = "Epic",
		Tier = 5,
		Income = 13000,
		Hardness = 14.5,
		Color = rgb(92, 52, 204),
		Glow = rgb(184, 124, 255),
		Crust = rgb(50, 44, 72),
		Shape = "GalaxyStone",
		Material = M.Glass,
		Lore = "A tiny planet with a ring, full of stars.",
	},
	---------------------------------------------------------------- Legendary
	{
		Id = "RoyalAurum",
		Name = "Royal Aurum",
		Rarity = "Legendary",
		Tier = 5,
		Income = 20000,
		Hardness = 16,
		Color = rgb(40, 36, 46),
		Glow = rgb(255, 196, 60),
		Crust = rgb(64, 56, 48),
		Shape = "RoyalAurum",
		Material = M.Glass,
		Lore = "A black royal gem edged with gold. It was set in the Kaldrum crown.",
	},
	{
		Id = "Sunstone",
		Name = "Sunstone",
		Rarity = "Legendary",
		Tier = 5,
		Income = 28000,
		Hardness = 18,
		Color = rgb(255, 182, 32),
		Glow = rgb(255, 222, 96),
		Crust = rgb(96, 74, 52),
		Shape = "Sunstone",
		Material = M.Glass,
		Lore = "A spiky golden star. A piece of captured sun, buried where the sun never reaches.",
	},
	{
		Id = "Moonstone",
		Name = "Moonstone",
		Rarity = "Legendary",
		Tier = 5,
		Income = 40000,
		Hardness = 20,
		Color = rgb(192, 206, 242),
		Glow = rgb(172, 202, 255),
		Crust = rgb(88, 88, 110),
		Shape = "Moonstone",
		Material = M.Glass,
		Lore = "A crescent moon of pale crystal. It shimmers when you don't look at it.",
	},
	{
		Id = "StormGem",
		Name = "Storm Gem",
		Rarity = "Legendary",
		Tier = 5,
		Income = 55000,
		Hardness = 22,
		Color = rgb(42, 112, 255),
		Glow = rgb(112, 192, 255),
		Crust = rgb(50, 58, 90),
		Shape = "StormGem",
		Material = M.Glass,
		Lore = "Blue crystal spikes that crackle with lightning.",
	},
	{
		Id = "LeafGem",
		Name = "Leaf Gem",
		Rarity = "Legendary",
		Tier = 5,
		Income = 80000,
		Hardness = 23,
		Color = rgb(72, 212, 62),
		Glow = rgb(152, 255, 112),
		Crust = rgb(56, 80, 50),
		Shape = "LeafGem",
		Material = M.Glass,
		Lore = "Green crystal leaves from the first tree of Terra.",
	},
	{
		Id = "VolcanicCore",
		Name = "Volcanic Core",
		Rarity = "Legendary",
		Tier = 5,
		Income = 130000,
		Hardness = 24,
		Color = rgb(70, 42, 38),
		Glow = rgb(255, 92, 30),
		Crust = rgb(44, 30, 30),
		Shape = "VolcanicCore",
		Material = M.Basalt,
		Lore = "Black lava rock with fire running through its cracks. It never cools.",
	},
	---------------------------------------------------------------- Mythic
	{
		Id = "Aetherium",
		Name = "Aetherium",
		Rarity = "Mythic",
		Tier = 5,
		Income = 200000,
		Hardness = 27,
		Color = rgb(152, 62, 242),
		Glow = rgb(212, 142, 255),
		Crust = rgb(74, 58, 96),
		Shape = "Aetherium",
		Material = M.Glass,
		Lore = "Violet crystals inside a swirl of light that refuses to touch the ground.",
	},
	{
		Id = "PhoenixFeather",
		Name = "Phoenix Feather",
		Rarity = "Mythic",
		Tier = 5,
		Income = 280000,
		Hardness = 30,
		Color = rgb(255, 122, 30),
		Glow = rgb(255, 192, 60),
		Crust = rgb(90, 52, 40),
		Shape = "PhoenixFeather",
		Material = M.SmoothPlastic,
		Lore = "A feather that burns forever and never turns to ash.",
	},
	{
		Id = "DragonScale",
		Name = "Dragon Scale",
		Rarity = "Mythic",
		Tier = 5,
		Income = 400000,
		Hardness = 34,
		Color = rgb(42, 34, 38),
		Glow = rgb(255, 72, 30),
		Crust = rgb(52, 36, 36),
		Shape = "DragonScale",
		Material = M.Basalt,
		Lore = "Black dragon scales with lava glowing between them.",
	},
	{
		Id = "CelestialCore",
		Name = "Celestial Core",
		Rarity = "Mythic",
		Tier = 5,
		Income = 550000,
		Hardness = 37,
		Color = rgb(62, 72, 232),
		Glow = rgb(142, 162, 255),
		Crust = rgb(50, 50, 80),
		Shape = "CelestialCore",
		Material = M.Glass,
		Lore = "A blue star-gem held by golden rings that never stop turning.",
	},
	{
		Id = "Heartstone",
		Name = "Heartstone Shard",
		Rarity = "Mythic",
		Tier = 5,
		Income = 800000,
		Hardness = 40,
		Color = rgb(255, 80, 140),
		Glow = rgb(255, 142, 192),
		Crust = rgb(64, 34, 44),
		Shape = "Heartstone",
		Material = M.Glass,
		Lore = "A piece of Terra's broken heart. Little hearts float around it.",
	},
}

for index, entry in LIST do
	entry.Index = index
	entry.Value = entry.Income * OreData.SellSeconds
end
OreData.List = LIST :: { Ore }

OreData.ById = {} :: { [string]: Ore }
for _, ore in OreData.List do
	OreData.ById[ore.Id] = ore
end

function OreData.get(id: string): Ore
	local ore = OreData.ById[id]
	assert(ore, "Unknown ore: " .. tostring(id))
	return ore
end

function OreData.exists(id: any): boolean
	return type(id) == "string" and OreData.ById[id] ~= nil
end

-- Ores of the old roster (design v2, 30 ores) that the owner's picture
-- replaced -> the new ore of the same rarity that takes their place in old
-- saves (Data/Migrations). Ores that stayed keep their Id (some changed rarity).
OreData.Renamed = {
	Ruby = "Bronze",
	Azurium = "DragonEgg",
	Emerald = "Jade",
	Verdantine = "CrystalRose",
	Stormcore = "StormPearl",
	Bloodstone = "GalaxyStone",
	Solarite = "Sunstone",
	Voidstone = "RoyalAurum",
	Magmacore = "VolcanicCore",
	Skyglass = "StormGem",
	Prismite = "PhoenixFeather",
	Starmetal = "CelestialCore",
} :: { [string]: string }

-- An ore id from a save: itself when it exists, its replacement when it was renamed, else nil.
function OreData.current(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	if OreData.ById[id] then
		return id
	end
	local new = OreData.Renamed[id]
	return if new and OreData.ById[new] then new else nil
end

return OreData
