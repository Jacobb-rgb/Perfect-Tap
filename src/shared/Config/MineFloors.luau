--[[
	The mine floors (owner, 2026-10-17): 5 floors now, more in updates. The
	deeper the floor, the harder its rocks and the better its ores.

	  1 Greystone Quarry    blaster 1+   walk        Common
	  2 Ember Caves         blaster 3+   walk        Uncommon
	  3 Deep Hollow         blaster 5+   walk        Rare (re-themed as a crystal lagoon)
	  4 Sunken Palace       blaster 7+   elevator    Epic
	  5 Heartstone Core     blaster 9+   elevator    Legendary / Mythic
	  6 ???                 blaster 11   "Coming soon"

	Every floor has 6 home ores. Rocks come in three kinds: Small (3 ores),
	Big (4 ores) and Crystal (3 ores rolled from the floor's better table,
	about 10 % of the rocks). A rock's HP is set so the weakest blaster allowed
	on the floor breaks it in `Seconds` (about 5 s, the owner's target).
	Special rocks (golden, geode, artifact) and the server-wide Giant Crystal
	are rare extras on every floor. The elevator is bought once with coins.

	Data only for now: WorldLayout.Zones still drive the live game until the
	floors are wired in (see docs/plans/MINE_FLOORS_PLAN.md).
]]

local BlasterData = require(script.Parent.BlasterData)

export type RockKind = "Small" | "Big" | "Crystal" | "Golden" | "Geode" | "Artifact" | "Giant"

export type Palette = {
	Mid: Color3, -- rock body
	Light: Color3, -- rock tops
	Dark: Color3, -- rock feet, cracks
	Crystal: Color3, -- the floor's main crystal color
	Crystal2: Color3, -- second crystal color
	Accent: Color3, -- lava, moss, gold trim, star glow (floor flavor)
	Ground: Color3, -- floor ground
}

export type Floor = {
	Index: number,
	Id: string,
	Name: string,
	ZoneId: string?, -- the WorldLayout zone this floor re-themes (floors 1-3)
	MinBlaster: number,
	ViaElevator: boolean, -- only reachable with the elevator
	Lighting: string, -- LightingConfig preset
	Ores: { [string]: number }, -- weights for Small and Big rocks
	CrystalOres: { [string]: number }, -- weights for Crystal rocks (better)
	Palette: Palette,
}

local MineFloors = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Ores per rock kind; Crystal rocks roll from CrystalOres.
MineFloors.OreCount = {
	Small = 3,
	Big = 4,
	Crystal = 3,
	Golden = 4,
	Geode = 3,
	Artifact = 3,
	Giant = 3, -- per player who helped
} :: { [RockKind]: number }

-- Seconds the floor's weakest allowed blaster (MinBlaster, rusty skin) needs per rock.
MineFloors.Seconds = {
	Small = 4,
	Big = 5,
	Crystal = 6,
	Golden = 6,
	Geode = 5,
	Artifact = 5,
	Giant = 240, -- one player alone; the whole server shares it
} :: { [RockKind]: number }

-- Chance of each kind when a rock spawns (the rest are Small).
MineFloors.SpawnChance = {
	Big = 0.3,
	Crystal = 0.1,
	Golden = 0.02,
	Geode = 0.015,
	Artifact = 0.01,
} :: { [string]: number }

MineFloors.GiantCrystal = {
	Interval = 600, -- seconds between Giant Crystals on a floor
	MinDamageShare = 0.02, -- a player must deal this share of its HP to get the reward
}

MineFloors.Elevator = {
	Price = 500000, -- coins, bought once (about when players reach floor 3)
}

MineFloors.ComingSoon = { Index = 6, MinBlaster = 11 }

MineFloors.List = {
	{
		Index = 1,
		Id = "Quarry",
		Name = "Greystone Quarry",
		ZoneId = "Quarry",
		MinBlaster = 1,
		ViaElevator = false,
		Lighting = "Quarry",
		Ores = { Coal = 30, Copper = 25, Tin = 18, Iron = 13, Quartz = 9, Silver = 5 },
		CrystalOres = { Iron = 20, Quartz = 30, Silver = 30, Amethyst = 14, Jade = 6 },
		Palette = {
			Mid = rgb(150, 128, 104),
			Light = rgb(190, 166, 134),
			Dark = rgb(108, 90, 76),
			Crystal = rgb(224, 122, 60),
			Crystal2 = rgb(244, 236, 236),
			Accent = rgb(255, 170, 90),
			Ground = rgb(196, 160, 116),
		},
	},
	{
		Index = 2,
		Id = "EmberCaves",
		Name = "Ember Caves",
		ZoneId = "EmberCaves",
		MinBlaster = 3,
		ViaElevator = false,
		Lighting = "EmberCaves",
		Ores = { Amethyst = 30, Jade = 25, Emberite = 18, Cobalt = 13, Gold = 9, Ruby = 5 },
		CrystalOres = { Cobalt = 20, Gold = 30, Ruby = 30, Azurium = 14, Sapphire = 6 },
		Palette = {
			Mid = rgb(124, 68, 54),
			Light = rgb(164, 96, 70),
			Dark = rgb(70, 38, 34),
			Crystal = rgb(255, 106, 36),
			Crystal2 = rgb(236, 44, 70),
			Accent = rgb(255, 120, 40),
			Ground = rgb(70, 40, 34),
		},
	},
	{
		Index = 3,
		Id = "DeepHollow",
		Name = "Deep Hollow",
		ZoneId = "DeepHollow",
		MinBlaster = 5,
		ViaElevator = false,
		Lighting = "Lagoon",
		Ores = { Azurium = 30, Sapphire = 25, Emerald = 18, Diamond = 13, Verdantine = 9, Obsidian = 5 },
		CrystalOres = { Diamond = 20, Verdantine = 30, Obsidian = 30, Stormcore = 14, Moonstone = 6 },
		Palette = {
			Mid = rgb(52, 86, 110),
			Light = rgb(82, 126, 152),
			Dark = rgb(30, 52, 72),
			Crystal = rgb(62, 200, 220),
			Crystal2 = rgb(200, 240, 255),
			Accent = rgb(80, 200, 140),
			Ground = rgb(38, 62, 80),
		},
	},
	{
		Index = 4,
		Id = "SunkenPalace",
		Name = "Sunken Palace",
		ZoneId = nil,
		MinBlaster = 7,
		ViaElevator = true,
		Lighting = "Palace",
		Ores = { Stormcore = 30, Moonstone = 25, Bloodstone = 18, Solarite = 13, Voidstone = 9, RoyalAurum = 5 },
		CrystalOres = { Solarite = 20, Voidstone = 30, RoyalAurum = 30, Magmacore = 14, Skyglass = 6 },
		Palette = {
			Mid = rgb(112, 98, 134),
			Light = rgb(152, 138, 174),
			Dark = rgb(70, 60, 90),
			Crystal = rgb(255, 196, 58),
			Crystal2 = rgb(190, 176, 255),
			Accent = rgb(232, 180, 60),
			Ground = rgb(88, 78, 110),
		},
	},
	{
		Index = 5,
		Id = "HeartstoneCore",
		Name = "Heartstone Core",
		ZoneId = nil,
		MinBlaster = 9,
		ViaElevator = true,
		Lighting = "Core",
		Ores = { Magmacore = 34, Skyglass = 28, Prismite = 18, Aetherium = 11, Starmetal = 6, Heartstone = 3 },
		CrystalOres = { Prismite = 30, Aetherium = 30, Starmetal = 25, Heartstone = 15 },
		Palette = {
			Mid = rgb(70, 58, 108),
			Light = rgb(106, 92, 152),
			Dark = rgb(38, 32, 64),
			Crystal = rgb(255, 56, 120),
			Crystal2 = rgb(130, 250, 220),
			Accent = rgb(255, 120, 200),
			Ground = rgb(34, 28, 56),
		},
	},
} :: { Floor }

MineFloors.ByIndex = {} :: { [number]: Floor }
MineFloors.ById = {} :: { [string]: Floor }
for _, floor in MineFloors.List do
	MineFloors.ByIndex[floor.Index] = floor
	MineFloors.ById[floor.Id] = floor
end

-- The floor for an index or id (floor 1 when unknown).
function MineFloors.get(key: number | string): Floor
	local floor = if type(key) == "number" then MineFloors.ByIndex[key] else MineFloors.ById[key]
	return floor or MineFloors.List[1]
end

-- HP of a rock of `kind` on a floor: the floor's weakest blaster needs Seconds[kind].
function MineFloors.rockHealth(key: number | string, kind: RockKind): number
	local floor = MineFloors.get(key)
	local seconds = MineFloors.Seconds[kind] or 4
	return math.max(1, math.floor(BlasterData.damage(floor.MinBlaster, "") * seconds + 0.5))
end

return MineFloors
