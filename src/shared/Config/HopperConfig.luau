--[[
	Hoppers (owner 2026-10-20): the most expensive things in Terra Forge. A
	hopper stands in your base and pours a stream of ores into its chest; the
	stream earns `Income` coins per second. Bought at the HOPPER WORKS shop for
	`Price`, sold back for `Resale` (less than the price).

	Concept stage: the numbers are the proposal the owner accepted in chat
	(payback about 1 to 5 hours of the hopper running); the ores in the stream
	are only its look (`Ores`, `Grade`).
]]

export type Hopper = {
	Id: string,
	Name: string,
	Order: number,
	Price: number,
	Resale: number,
	Income: number, -- coins per second
	Ores: { string }, -- OreData ids poured by the hopper (its look)
	Grade: string, -- ItemData grade of the poured ores
	Glow: string, -- CardTheme glow name of its shop card
	Tagline: string,
}

local HopperConfig = {}

local LIST: { any } = {
	{
		Id = "EpicHopper",
		Name = "Epic Hopper",
		Price = 5e9,
		Resale = 3e9,
		Income = 1.5e6,
		Ores = { "Diamond", "Amethyst", "Obsidian", "CrystalRose", "StormPearl", "GalaxyStone" },
		Grade = "Clean",
		Glow = "Purple",
		Tagline = "Pours Epic ores",
	},
	{
		Id = "LegendaryHopper",
		Name = "Legendary Hopper",
		Price = 35e9,
		Resale = 28e9,
		Income = 8e6,
		Ores = { "RoyalAurum", "Sunstone", "Moonstone", "StormGem", "LeafGem", "VolcanicCore" },
		Grade = "Clean",
		Glow = "Orange",
		Tagline = "Pours Legendary ores",
	},
	{
		Id = "MythicHopper",
		Name = "Mythic Hopper",
		Price = 100e9,
		Resale = 75e9,
		Income = 20e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale" },
		Grade = "Clean",
		Glow = "Red",
		Tagline = "Pours Mythic ores",
	},
	{
		Id = "HeartHopper",
		Name = "Heart Hopper",
		Price = 250e9,
		Resale = 190e9,
		Income = 40e6,
		Ores = { "CelestialCore", "Heartstone" },
		Grade = "Clean",
		Glow = "Pink",
		Tagline = "Pours Celestial Cores + Heartstones",
	},
	{
		Id = "StarHopper",
		Name = "Star Hopper",
		Price = 1e12,
		Resale = 750e9,
		Income = 120e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale", "CelestialCore", "Heartstone" },
		Grade = "Pristine",
		Glow = "Gold",
		Tagline = "Pours Pristine Mythic ores",
	},
	{
		Id = "RiftHopper",
		Name = "Rift Hopper",
		Price = 5e12,
		Resale = 3.8e12,
		Income = 400e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale", "CelestialCore", "Heartstone" },
		Grade = "Flawless",
		Glow = "Rainbow",
		Tagline = "Pours Flawless Mythic ores",
	},
	{
		Id = "TerraCoreHopper",
		Name = "Terra Core Hopper",
		Price = 25e12,
		Resale = 19e12,
		Income = 1.5e9,
		Ores = { "Heartstone" },
		Grade = "Flawless",
		Glow = "Rainbow",
		Tagline = "A river of Flawless Heartstones",
	},
}

for index, entry in LIST do
	entry.Order = index
end
HopperConfig.List = LIST :: { Hopper }

HopperConfig.ById = {} :: { [string]: Hopper }
for _, hopper in HopperConfig.List do
	HopperConfig.ById[hopper.Id] = hopper
end

-- Seconds the hopper needs to earn back its price.
function HopperConfig.payback(hopper: Hopper): number
	return hopper.Price / hopper.Income
end

return HopperConfig
