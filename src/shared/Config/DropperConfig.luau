--[[
	Droppers (owner 2026-10-21; first called "hoppers"): the most expensive
	things in Terra Forge. A dropper stands on your plot and drops ores of
	ONE price range (only Epic ores, only Legendary ores, ...) from its arm.
	Bought at the DROPPERS shop for `Price`, sold back for `Resale`. The looks
	follow the owner's picture docs/art/droppers_concept.webp (DropperBuilder).

	Real ore on the belts (owner 2026-10-24: "the ore rides through the laser,
	its price goes up, then into the Sell"): every DropEvery seconds a dropper
	pushes one DROP out of its front onto the belt there (DropperService). A
	Drop is an item of its own kind (ItemData kind "Drop", O = the dropper's
	id): it looks like one of the dropper's ores, rides belts, Splitters and
	Money Lasers, and only a Sell Box sells it, for dropValue: the dropper's
	`Income` x DropEvery (so a dropper whose every Drop sells earns `Income`
	coins per second), times Laser.Mult once it passed a Money Laser
	(R = LaserMark). It is never carried, stored, saved or put anywhere else.
	`Ores` / `Grade` are only its looks.
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

-- At most this many droppers stand on one plot (owner 2026-10-23: "max 5"), and as
-- many Money Lasers (a laser doubles one dropper: more lasers than droppers do nothing).
DropperConfig.MaxPlaced = 5
DropperConfig.MaxLasers = 5

-- (owner 2026-10-24: themed names, "like a Heaven Dropper"; the Ids stay: saves keep them)
local LIST: { any } = {
	{
		Id = "BasicDropper",
		Name = "Toxic Dropper",
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
		Name = "Frost Dropper",
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
		Name = "Lava Dropper",
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
		Name = "Crystal Dropper",
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
		Name = "Heaven Dropper",
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

-- The MONEY LASER (owner 2026-10-21; 2026-10-24: "tiny, smaller than the
-- machines and the Sell Box, it sits between the belts and the ore just rides
-- through it"): a 1 x 1 gate on the belt line; every Drop that passes it is
-- worth Mult times as much (once: a second laser lets it pass as it is).
export type Laser = { Id: string, Name: string, Price: number, Resale: number, Mult: number, Tagline: string }
DropperConfig.Laser = {
	Id = "MoneyLaser2X",
	Name = "2X Money Laser",
	Price = 10e9,
	Resale = 7e9,
	Mult = 2,
	Tagline = "Ores that pass it are worth double",
} :: Laser

-- The most coins per second the droppers in a list of placed machines
-- (data.PlacedMachines: { Id = machineId, ... }) can earn: every Drop sold,
-- and with any Money Laser on the plot every dropper doubled (their belts
-- can merge before one laser; more lasers add nothing then). For the shop's
-- numbers and tools/lune/balance_sim: the coins come from the sales.
function DropperConfig.placedIncome(placed: { any }?): number
	if type(placed) ~= "table" then
		return 0
	end
	local total = 0
	local laser = false
	for _, entry in placed do
		local id = if type(entry) == "table" then entry.Id else nil
		local dropper = if type(id) == "string" then DropperConfig.ById[id] else nil
		if dropper then
			total += dropper.Income
		elseif id == DropperConfig.Laser.Id then
			laser = true
		end
	end
	return if laser then total * DropperConfig.Laser.Mult else total
end

-- One Drop: an item a dropper pushes onto the belt (see the header).
DropperConfig.DropKind = "Drop" -- ItemData kind
DropperConfig.LaserMark = "X2" -- a Drop's R once a Money Laser doubled it
DropperConfig.DropEvery = 3 -- seconds between two Drops of one dropper
-- Live Drops (server perf, docs/SERVER_PERF_AUDIT.md): a dropper waits while
-- its owner has MaxLiveDrops of them in the world (loose or waiting in a
-- laser / splitter queue), or the server MaxLiveDropsServer; a LOOSE Drop
-- older than DropLife disappears (it fell off the belt, its belt ends
-- nowhere, or its ride is longer than DropLife: about 79 cells of plain belt;
-- a laser hands it on as a new item, which starts its own DropLife).
DropperConfig.MaxLiveDrops = 15 -- (half of GameConfig.MaxLooseItemsPerPlayer: the ore factory keeps its room)
DropperConfig.MaxLiveDropsServer = 120
DropperConfig.DropLife = 45
-- Studs over the plot floor where a dropper's Drop appears: right under its
-- nozzle, which hangs over the middle of the cell in front of it (the belt
-- there: DropperBuilder's onBelt arm, Grid.outputLocal); it falls onto the belt.
DropperConfig.SpoutHeight = 6.4

-- Is `desc` (an item Desc: K, O, G, R) a Drop?
function DropperConfig.isDrop(desc: any): boolean
	return type(desc) == "table" and desc.K == DropperConfig.DropKind
end

-- A well-formed Drop: a known dropper, no grade, no mark or the laser's mark.
function DropperConfig.validDrop(desc: any): boolean
	return DropperConfig.isDrop(desc)
		and type(desc.O) == "string"
		and DropperConfig.ById[desc.O] ~= nil
		and desc.G == nil
		and (desc.R == nil or desc.R == DropperConfig.LaserMark)
end

-- Coins one Drop of dropper `id` sells for (0 for an unknown dropper);
-- `lasered`: it passed a Money Laser.
function DropperConfig.dropValue(id: string, lasered: boolean?): number
	local dropper = DropperConfig.ById[id]
	if not dropper then
		return 0
	end
	local value = dropper.Income * DropperConfig.DropEvery
	return if lasered then value * DropperConfig.Laser.Mult else value
end

-- Removes every Drop from a list of item Descs in place (a save never keeps
-- one: machine queues, the pen); returns how many went.
function DropperConfig.stripDrops(list: any): number
	if type(list) ~= "table" then
		return 0
	end
	local removed = 0
	for i = #list, 1, -1 do
		if DropperConfig.isDrop(list[i]) then
			table.remove(list, i)
			removed += 1
		end
	end
	return removed
end

-- Seconds the dropper needs to earn back its price.
function DropperConfig.payback(dropper: Dropper): number
	return dropper.Price / dropper.Income
end

return DropperConfig
