--[[
	All ores in Terra Forge. Add a new ore by adding one entry to the list
	(and giving it a weight in WorldLayout.Zones so it spawns somewhere).
]]

export type Ore = {
	Id: string,
	Name: string,
	Rarity: string,
	Tier: number, -- minimum pickaxe tier needed to mine it
	Value: number, -- base sell value of 1 clean ore (Rough grade)
	Hardness: number, -- node HP (pickaxe damage per hit is subtracted)
	Color: Color3, -- main ore color (cleaned ore, ingots)
	Glow: Color3, -- neon/glow color (veins, crystals, light)
	Crust: Color3, -- rock crust color around the ore
	Lore: string,
}

local OreData = {}

OreData.List = {
	{
		Id = "Copper",
		Name = "Copper",
		Rarity = "Common",
		Tier = 1,
		Value = 6,
		Hardness = 6,
		Color = Color3.fromRGB(222, 120, 60),
		Glow = Color3.fromRGB(255, 150, 80),
		Crust = Color3.fromRGB(110, 86, 72),
		Lore = "Warm and soft. Every Forgekeeper's first ore.",
	},
	{
		Id = "Iron",
		Name = "Iron",
		Rarity = "Common",
		Tier = 1,
		Value = 9,
		Hardness = 8,
		Color = Color3.fromRGB(168, 174, 186),
		Glow = Color3.fromRGB(214, 120, 84),
		Crust = Color3.fromRGB(96, 84, 80),
		Lore = "The backbone of Emberfall. Rust-red veins run through grey stone.",
	},
	{
		Id = "Silver",
		Name = "Silver",
		Rarity = "Uncommon",
		Tier = 2,
		Value = 20,
		Hardness = 14,
		Color = Color3.fromRGB(222, 234, 246),
		Glow = Color3.fromRGB(190, 225, 255),
		Crust = Color3.fromRGB(104, 104, 116),
		Lore = "Cold and bright. It rings like a bell when the chisel hits.",
	},
	{
		Id = "Emberite",
		Name = "Emberite",
		Rarity = "Uncommon",
		Tier = 3,
		Value = 34,
		Hardness = 20,
		Color = Color3.fromRGB(255, 96, 36),
		Glow = Color3.fromRGB(255, 120, 30),
		Crust = Color3.fromRGB(70, 46, 40),
		Lore = "Still warm from the Heartstone's fire. Glows in the dark caves.",
	},
	{
		Id = "Gold",
		Name = "Gold",
		Rarity = "Rare",
		Tier = 3,
		Value = 60,
		Hardness = 26,
		Color = Color3.fromRGB(255, 200, 58),
		Glow = Color3.fromRGB(255, 214, 90),
		Crust = Color3.fromRGB(102, 82, 60),
		Lore = "Pell pays well for gold. Pell pays even better for flawless gold.",
	},
	{
		Id = "Azurium",
		Name = "Azurium",
		Rarity = "Rare",
		Tier = 4,
		Value = 100,
		Hardness = 36,
		Color = Color3.fromRGB(52, 128, 255),
		Glow = Color3.fromRGB(80, 160, 255),
		Crust = Color3.fromRGB(56, 60, 82),
		Lore = "Deep blue crystal metal. Said to hold the cold of the old sea.",
	},
	{
		Id = "Verdantine",
		Name = "Verdantine",
		Rarity = "Epic",
		Tier = 5,
		Value = 180,
		Hardness = 50,
		Color = Color3.fromRGB(56, 212, 130),
		Glow = Color3.fromRGB(90, 255, 160),
		Crust = Color3.fromRGB(52, 70, 58),
		Lore = "Living green ore. Moss grows wherever its dust settles.",
	},
	{
		Id = "Stormcore",
		Name = "Stormcore",
		Rarity = "Epic",
		Tier = 5,
		Value = 300,
		Hardness = 64,
		Color = Color3.fromRGB(122, 104, 255),
		Glow = Color3.fromRGB(110, 230, 255),
		Crust = Color3.fromRGB(50, 46, 72),
		Lore = "Crackles when you touch it. Forged blades hum like thunder.",
	},
	{
		Id = "Solarite",
		Name = "Solarite",
		Rarity = "Legendary",
		Tier = 6,
		Value = 600,
		Hardness = 90,
		Color = Color3.fromRGB(255, 232, 140),
		Glow = Color3.fromRGB(255, 244, 190),
		Crust = Color3.fromRGB(92, 70, 52),
		Lore = "A drop of captured sunlight, buried where the sun never reaches.",
	},
	{
		Id = "Heartstone",
		Name = "Heartstone Shard",
		Rarity = "Mythic",
		Tier = 7,
		Value = 1500,
		Hardness = 130,
		Color = Color3.fromRGB(255, 50, 112),
		Glow = Color3.fromRGB(255, 90, 140),
		Crust = Color3.fromRGB(64, 34, 44),
		Lore = "A piece of Terra's broken heart. It beats, very slowly.",
	},
} :: { Ore }

OreData.ById = {} :: { [string]: Ore }
for index, ore in OreData.List do
	local entry: any = ore
	entry.Index = index
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

return OreData
