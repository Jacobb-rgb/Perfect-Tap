--[[
	The mine floors (owner, 2026-10-17; the Stormglass Rift added 2026-10-20,
	docs/plans/STORM_FLOOR_PLAN.md): 6 floors now, more in updates. The deeper
	the floor, the harder its rocks and the better its ores.

	  1 Greystone Quarry    blaster 1+   walk        Common
	  2 Ember Caves         blaster 3+   walk        Uncommon
	  3 Deep Hollow         blaster 5+   walk        Rare (re-themed as a crystal lagoon)
	  4 Sunken Palace       blaster 7+   elevator    Epic
	  5 Stormglass Rift     blaster 8+   elevator    Epic / Legendary
	  6 Heartstone Core     blaster 9+   elevator    Legendary / Mythic
	  7 ???                 blaster 11   "Coming soon"

	Floor logic keys on a floor's Id (RockBuilder looks, MineAmbience kinds,
	the floor layouts), never on its Index: a floor can go in between.

	Every floor has 5-8 home ores (variant A2 of the balance sim; all 36 ores, OreData.Tier = the floor's MinBlaster). Rocks come in three kinds: Small (3 ores),
	Big (4 ores) and Crystal (3 ores rolled from the floor's better table,
	about 10 % of the rocks). A rock's HP is set so the weakest blaster allowed
	on the floor breaks it in `Seconds` (about 5 s, the owner's target).
	Special rocks (golden, geode, artifact) and the server-wide Giant Crystal
	are rare extras on every floor. Floors 1-3 are free (walk there, or ride
	the elevator); each elevator-only floor's ticket is bought once with coins
	in the elevator (owner 2026-11-15: priceOf, ElevatorService).

	Data only for now: WorldLayout.Zones still drive the live game until the
	floors are wired in (see docs/plans/MINE_FLOORS_PLAN.md).
]]

local BlasterData = require(script.Parent.BlasterData)
local MeshCatalog = require(script.Parent.MeshCatalog)
local MeshKit = require(script.Parent.Parent.Builders.MeshKit)

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
	ZoneId: string, -- the WorldLayout zone of the floor's area (lighting, rocks)
	MinBlaster: number,
	ViaElevator: boolean, -- only reachable with the elevator (its ticket costs priceOf coins)
	Lighting: string, -- LightingConfig preset
	Ores: { [string]: number }, -- weights for Small and Big rocks
	CrystalOres: { [string]: number }, -- weights for Crystal rocks (better)
	Palette: Palette,
	RockName: string, -- the name over Small rocks ("Greystone 20 HP")
	CrystalName: string, -- the name over Crystal rocks
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

MineFloors.ComingSoon = { Index = 7, MinBlaster = 11 }

MineFloors.List = {
	{
		Index = 1,
		Id = "Quarry",
		RockName = "Greystone",
		CrystalName = "Quartz Shard",
		Name = "Greystone Quarry",
		ZoneId = "Quarry",
		MinBlaster = 1,
		ViaElevator = false,
		Lighting = "Quarry",
		Ores = { Coal = 26, Copper = 21, Tin = 16, Iron = 12, Quartz = 9, Oakwood = 7, Honeycomb = 5, LeafOre = 4 },
		CrystalOres = { Quartz = 15, Oakwood = 20, Honeycomb = 25, LeafOre = 25, Frostbite = 10, Emberite = 5 },
		Palette = {
			Mid = rgb(118, 124, 142),
			Light = rgb(168, 176, 194),
			Dark = rgb(74, 78, 96),
			Crystal = rgb(255, 146, 60),
			Crystal2 = rgb(252, 246, 240),
			Accent = rgb(255, 170, 90),
			Ground = rgb(196, 160, 116),
		},
	},
	{
		Index = 2,
		Id = "EmberCaves",
		RockName = "Basalt",
		CrystalName = "Ember Shard",
		Name = "Ember Caves",
		ZoneId = "EmberCaves",
		MinBlaster = 3,
		ViaElevator = false,
		Lighting = "EmberCaves",
		Ores = { Frostbite = 28, Emberite = 22, Cobalt = 39, Bronze = 7, Silver = 4 }, -- (Bogwood 13 + Amber 9 -> Cobalt, removed 2026-11-13)
		CrystalOres = { Cobalt = 20, Bronze = 30, Silver = 30, Gold = 15, Jade = 5 }, -- (Amber's place)
		Palette = {
			Mid = rgb(86, 58, 54),
			Light = rgb(124, 88, 76),
			Dark = rgb(52, 34, 34),
			Crystal = rgb(255, 106, 36),
			Crystal2 = rgb(236, 44, 70),
			Accent = rgb(255, 120, 40),
			Ground = rgb(70, 40, 34),
		},
	},
	{
		Index = 3,
		Id = "DeepHollow",
		RockName = "Hollow Stone",
		CrystalName = "Azure Shard",
		Name = "Deep Hollow",
		ZoneId = "DeepHollow",
		MinBlaster = 5,
		ViaElevator = false,
		Lighting = "Lagoon",
		Ores = { Gold = 22, Jade = 20, Sapphire = 18, DragonEgg = 16, Diamond = 13 }, -- (Amethyst moved home to the Sunken Palace 2026-11-13)
		CrystalOres = { Diamond = 20, Amethyst = 30, CrystalRose = 50 }, -- (Obsidian 30 -> Crystal Rose, removed 2026-11-13)
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
		RockName = "Palace Stone",
		CrystalName = "Royal Shard",
		Name = "Sunken Palace",
		ZoneId = "SunkenPalace",
		MinBlaster = 7,
		ViaElevator = true,
		Lighting = "Palace",
		Ores = { Amethyst = 12, CrystalRose = 18, StormPearl = 22, GalaxyStone = 24, RoyalAurum = 24 }, -- (Amethyst in Obsidian's place, 2026-11-13)
		CrystalOres = { RoyalAurum = 30, Sunstone = 35, Moonstone = 35 },
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
		Id = "StormglassRift",
		RockName = "Stormrock",
		CrystalName = "Thunder Shard",
		Name = "Stormglass Rift",
		ZoneId = "StormglassRift",
		MinBlaster = 8,
		ViaElevator = true,
		Lighting = "Storm",
		Ores = { Sunstone = 16, Moonstone = 22, StormGem = 26, LeafGem = 22, VolcanicCore = 14 },
		CrystalOres = { VolcanicCore = 30, Aetherium = 40, PhoenixFeather = 30 },
		-- dark indigo stone, electric yellow-white storm crystals, copper coils (World/Mine/Floor5Storm.luau)
		Palette = {
			Mid = rgb(58, 66, 104),
			Light = rgb(92, 102, 150),
			Dark = rgb(36, 40, 70),
			Crystal = rgb(255, 236, 120),
			Crystal2 = rgb(255, 250, 215),
			Accent = rgb(226, 132, 72),
			Ground = rgb(54, 62, 100),
		},
	},
	{
		Index = 6,
		Id = "HeartstoneCore",
		RockName = "Void Rock",
		CrystalName = "Heart Shard",
		Name = "Heartstone Core",
		ZoneId = "HeartstoneCore",
		MinBlaster = 9,
		ViaElevator = true,
		Lighting = "Core",
		Ores = { Aetherium = 30, PhoenixFeather = 25, DragonScale = 20, CelestialCore = 15, Heartstone = 10 },
		CrystalOres = { DragonScale = 30, CelestialCore = 35, Heartstone = 35 },
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

-- Where each floor area stands in the world (ground center; +Z = front/entrance), see
-- docs/plans/MINE_STEP_PLAN.md: floors 1-3 replace the old quarry and caves; 4-6 lie deep below
-- and far north (beyond the streaming radius of the town, above Workspace.FallenPartsDestroyHeight
-- -700 in default.project.json: tests/FallHeights.spec.luau keeps every floor well above it).
-- The Rift (local y -11.5 .. +50) sits between the palace (its ground at -222) and the core's
-- void enclosure (its top at -316).
MineFloors.Placement = {
	CFrame.new(0, -12, -180),
	CFrame.new(0, -12, -300),
	CFrame.new(0, -40, -444),
	CFrame.new(0, -220, -800),
	CFrame.new(0, -300, -800),
	CFrame.new(0, -400, -800),
} :: { CFrame }

-- Where each part-built floor's Mine Lift stood (floor-local, on the ground). The owner took the
-- lifts out of every floor 2026-11-14 ("it really bothers me there"); the part-built floors (no
-- upload) keep the spot clear and their lift's beams as decoration.
MineFloors.LiftSpots = {
	[2] = Vector3.new(46, 0, 40),
	[3] = Vector3.new(50, 0, 2),
	[4] = Vector3.new(26, 2.4, 45),
	[5] = Vector3.new(28, 2.4, 47), -- on the Rift's landing deck, under its crane beam
	[6] = Vector3.new(12, 0, 25),
} :: { [number]: Vector3 }

-- The floors built from the owner's dioramas (World/Mine/Diorama, DioramaData) when every tile is
-- uploaded (MeshKit). (An entry per floor: a floor without one is never its diorama.)
MineFloors.Dioramas = {
	[1] = {},
	[2] = {},
	[3] = {},
	[4] = {},
	[5] = {},
	[6] = {},
} :: { [number]: {} }

-- The underside of every diorama cave floor's ceiling, studs above its ground (owner 2026-11-14:
-- "all ceilings the same, really important"): one closed room per cave floor (Mine/Diorama) up to
-- it, the elevator tower reaches it. Under the ForgeMountain massif that
-- rests on the Ember Caves' roof (world y 22 = local 34) and over the tallest diorama (the Rift's
-- 32.7); the Heartstone Core keeps its void.
MineFloors.CeilingHeight = 33.5
MineFloors.CeilingFloors = { [2] = true, [3] = true, [4] = true, [5] = true } :: { [number]: boolean }

-- The tiles floor `index`'s diorama is built from: the sharper set (MeshCatalog.FloorsHD) once
-- every one of its tiles is uploaded, else the first set once all of those are; nil without a
-- diorama or before the upload.
function MineFloors.floorTiles(index: number): { string }?
	local floor = MineFloors.ByIndex[index]
	if not floor or not MineFloors.Dioramas[index] then
		return nil
	end
	local function uploaded(tiles: { string }?): boolean
		if not tiles or #tiles == 0 then
			return false
		end
		for _, name in tiles do
			if not MeshKit.has(name) then
				return false
			end
		end
		return true
	end
	local hd = MeshCatalog.FloorsHD[floor.Id]
	if uploaded(hd) then
		return hd
	end
	local tiles = MeshCatalog.Floors[floor.Id]
	return if uploaded(tiles) then tiles else nil
end

-- Whether floor `index` is built from its diorama (its layout exists and its tiles are uploaded).
function MineFloors.usesDiorama(index: number): boolean
	return MineFloors.floorTiles(index) ~= nil
end

MineFloors.ByIndex = {} :: { [number]: Floor }
MineFloors.ById = {} :: { [string]: Floor }
for _, floor in MineFloors.List do
	MineFloors.ByIndex[floor.Index] = floor
	MineFloors.ById[floor.Id] = floor
end

--[[
	Coins for a floor's elevator ticket (owner 2026-11-15: every floor is bought
	one by one in the elevator, coins only, never gems or Robux; ElevatorService
	sells it, saved in data.Upgrades.Floors). 0 for a floor you can walk to
	(ViaElevator false: floors 1-3) and for an unknown index. An elevator-only
	floor costs half of "2/3 of the price of the blaster that opens it"
	(BlasterData.coins(MinBlaster), rounded to 2 significant digits, then
	halved: the owner 2026-11-16 "zlevnil bych to vše tak o polovinu"), so
	about 1/3 of that blaster: today 43,500,000 (floor 4, blaster 7, half the
	old one-time elevator), 750,000,000 (floor 5) and 10,500,000,000 (floor 6).
]]
function MineFloors.priceOf(index: number): number
	local floor = MineFloors.ByIndex[index]
	if not floor or not floor.ViaElevator then
		return 0
	end
	local scale = BlasterData.coins(floor.MinBlaster)
	local raw = (if scale > 0 then scale else 3e6) * 2 / 3
	local step = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	return math.floor(raw / step + 0.5) * step / 2
end

MineFloors.ByZone = {} :: { [string]: Floor }
for _, floor in MineFloors.List do
	MineFloors.ByZone[floor.ZoneId] = floor
end

-- The floor whose area is the WorldLayout zone `zoneId` (the town's starter outcrops count as floor 1).
function MineFloors.floorForZone(zoneId: string): Floor?
	if zoneId == "Outcrops" then
		return MineFloors.List[1]
	end
	return MineFloors.ByZone[zoneId]
end

-- The floor for an index or id (floor 1 when unknown).
function MineFloors.get(key: number | string): Floor
	local floor = if type(key) == "number" then MineFloors.ByIndex[key] else MineFloors.ById[key]
	return floor or MineFloors.List[1]
end

-- The name shown over a rock (English UI), e.g. "Greystone", "Basalt Boulder", "Ember Shard".
function MineFloors.rockName(key: number | string, kind: RockKind): string
	local floor = MineFloors.get(key)
	if kind == "Big" then
		return floor.RockName .. " Boulder"
	elseif kind == "Crystal" then
		return floor.CrystalName
	elseif kind == "Golden" then
		return "Golden Rock"
	elseif kind == "Geode" then
		return "Geode"
	elseif kind == "Artifact" then
		return "Ancient Rock"
	elseif kind == "Giant" then
		return "Giant " .. floor.CrystalName
	end
	return floor.RockName
end

-- Name color over a rock: plain rocks warm white, crystals in the floor's crystal color,
-- special rocks in their own colors (the same on every floor).
MineFloors.LabelColors = {
	Rock = rgb(255, 240, 220),
	Golden = rgb(255, 206, 72),
	Geode = rgb(196, 140, 255),
	Artifact = rgb(110, 255, 220),
}

function MineFloors.labelColor(key: number | string, kind: RockKind): Color3
	local floor = MineFloors.get(key)
	if kind == "Crystal" or kind == "Giant" then
		return floor.Palette.Crystal:Lerp(Color3.new(1, 1, 1), 0.35)
	elseif kind == "Golden" or kind == "Geode" or kind == "Artifact" then
		return MineFloors.LabelColors[kind]
	end
	return MineFloors.LabelColors.Rock
end

-- HP of a rock of `kind` on a floor: the floor's weakest blaster needs Seconds[kind].
function MineFloors.rockHealth(key: number | string, kind: RockKind): number
	local floor = MineFloors.get(key)
	local seconds = MineFloors.Seconds[kind] or 4
	return math.max(1, math.floor(BlasterData.damage(floor.MinBlaster, "") * seconds + 0.5))
end

return MineFloors
