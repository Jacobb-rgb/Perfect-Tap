--[[
	Droppers (owner 2026-10-21; first called "hoppers"): the most expensive
	things in Terra Forge. A dropper stands on your plot and drops ores of
	ONE price range (only Epic ores, only Legendary ores, ...) from its arm;
	the ores earn `Income` coins per second. Bought at the DROPPER WORKS shop
	for `Price`, sold back for `Resale`. The looks follow the owner's picture
	docs/art/droppers_concept.webp (DropperBuilder).

	Concept stage: the numbers are the proposal the owner accepted in chat
	(payback about 1 to 5 hours of the dropper running); `Ores` / `Grade` are
	what it drops.
]]

export type Dropper = {
	Id: string,
	Name: string,
	Order: number,
	Price: number,
	Resale: number,
	Income: number, -- coins per second
	Ores: { string }, -- OreData ids it drops (one price range)
	Grade: string, -- ItemData grade of the dropped ores
	Glow: string, -- shop card glow
	Tagline: string,
}

local DropperConfig = {}

local LIST: { any } = {
	{
		Id = "BasicDropper",
		Name = "Basic Dropper",
		Price = 5e9,
		Resale = 3e9,
		Income = 1.5e6,
		Ores = { "Diamond", "Amethyst", "Obsidian", "CrystalRose", "StormPearl", "GalaxyStone" },
		Grade = "Clean",
		Glow = "Green",
		Tagline = "Drops only Epic ores",
	},
	{
		Id = "BlueDropper",
		Name = "Blue Dropper",
		Price = 35e9,
		Resale = 28e9,
		Income = 8e6,
		Ores = { "RoyalAurum", "Sunstone", "Moonstone", "StormGem", "LeafGem", "VolcanicCore" },
		Grade = "Clean",
		Glow = "Blue",
		Tagline = "Drops only Legendary ores",
	},
	{
		Id = "RedDropper",
		Name = "Red Dropper",
		Price = 100e9,
		Resale = 75e9,
		Income = 20e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale" },
		Grade = "Clean",
		Glow = "Red",
		Tagline = "Drops only Mythic ores",
	},
	{
		Id = "PurpleDropper",
		Name = "Purple Dropper",
		Price = 250e9,
		Resale = 190e9,
		Income = 40e6,
		Ores = { "CelestialCore", "Heartstone" },
		Grade = "Clean",
		Glow = "Purple",
		Tagline = "Drops Celestial Cores + Heartstones",
	},
	{
		Id = "GoldDropper",
		Name = "Gold Dropper",
		Price = 1e12,
		Resale = 750e9,
		Income = 120e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale", "CelestialCore", "Heartstone" },
		Grade = "Pristine",
		Glow = "Gold",
		Tagline = "Drops only Pristine Mythic ores",
	},
	{
		Id = "RainbowDropper",
		Name = "Rainbow Dropper",
		Price = 5e12,
		Resale = 3.8e12,
		Income = 400e6,
		Ores = { "Aetherium", "PhoenixFeather", "DragonScale", "CelestialCore", "Heartstone" },
		Grade = "Flawless",
		Glow = "Rainbow",
		Tagline = "Drops only Flawless Mythic ores",
	},
	{
		Id = "DarkMatterDropper",
		Name = "Dark Matter Dropper",
		Price = 25e12,
		Resale = 19e12,
		Income = 1.5e9,
		Ores = { "Heartstone" },
		Grade = "Flawless",
		Glow = "Purple",
		Tagline = "A river of Flawless Heartstones",
	},
}

for index, entry in LIST do
	entry.Order = index
end
DropperConfig.List = LIST :: { Dropper }

DropperConfig.ById = {} :: { [string]: Dropper }
for _, dropper in DropperConfig.List do
	DropperConfig.ById[dropper.Id] = dropper
end

-- The MONEY LASER (owner 2026-10-21): the dropper's ores that pass it are
-- worth double: every laser on the plot doubles one dropper (the best first).
export type Laser = { Id: string, Name: string, Price: number, Resale: number, Mult: number, Tagline: string }
DropperConfig.Laser = {
	Id = "MoneyLaser2X",
	Name = "2X Money Laser",
	Price = 10e9,
	Resale = 7e9,
	Mult = 2,
	Tagline = "Ores that pass it are worth double",
} :: Laser

-- Coins per second from the droppers in a list of placed machines
-- (data.PlacedMachines: { Id = machineId, ... }). Every Money Laser doubles
-- one dropper, the best ones first.
function DropperConfig.placedIncome(placed: { any }?): number
	if type(placed) ~= "table" then
		return 0
	end
	local incomes: { number } = {}
	local lasers = 0
	for _, entry in placed do
		local id = if type(entry) == "table" then entry.Id else nil
		local dropper = if type(id) == "string" then DropperConfig.ById[id] else nil
		if dropper then
			table.insert(incomes, dropper.Income)
		elseif id == DropperConfig.Laser.Id then
			lasers += 1
		end
	end
	table.sort(incomes, function(a, b)
		return a > b
	end)
	local total = 0
	for i, income in incomes do
		total += if i <= lasers then income * DropperConfig.Laser.Mult else income
	end
	return total
end

-- Seconds the dropper needs to earn back its price.
function DropperConfig.payback(dropper: Dropper): number
	return dropper.Price / dropper.Income
end

return DropperConfig
