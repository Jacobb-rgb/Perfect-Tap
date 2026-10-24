--[[
	Lobby layout: where every set piece of the town lobby goes (see
	docs/plans/LOBBY_PLAN.md and docs/ART_DIRECTION.md).

	The lobby is built by six parallel packages (src/server/World/Lobby/*).
	Each set piece here belongs to exactly one package. A piece is an
	oriented box on the ground:
	  Center  bottom center (ground point, Y = base height)
	  Size    local X = width, Y = height budget, Z = depth
	  Facing  the piece's front (LookVector), horizontal
	  Radius  optional: the footprint is a circle instead of a box
	  Walkable  flat walk-over decor (paths, rails, bridges): may sit on roads
	  Reserve   a reservation only (the Vault's jungle trees): nothing is built
	            from it, it keeps the scatter and the town buildings away
	            (isFree) and may overlap its own package's pieces
	  DesignCenter/DesignFacing  the frame the piece's builder was written
	            for (fixed world coordinates); Town.luau moves the built
	            model from there to Center/Facing
	Build inside your footprint. tests/Lobby.spec.luau checks that the solid
	lobby footprints stay off roads, plots, ore outcrops, the spawn and each
	other, so packages can work in parallel without colliding.

	Only the art director edits this file. If a piece must move, ask; inside
	your own footprint you are free.
]]

local BaseLayout = require(script.Parent.BaseLayout)
local WorldLayout = require(script.Parent.WorldLayout)

export type Piece = {
	Id: string,
	Package: string,
	Center: Vector3,
	Size: Vector3,
	Facing: Vector3,
	Radius: number?,
	Walkable: boolean?,
	Reserve: boolean?,
	DesignCenter: Vector3?,
	DesignFacing: Vector3?,
	Note: string,
}

export type Path = {
	Id: string,
	From: Vector3,
	To: Vector3,
	Width: number,
	Kind: string, -- "Cobble" | "Dirt" | "Plank"
}

local LobbyLayout = {}

LobbyLayout.Packages = { "Sky", "Backdrop", "Plaza", "Districts", "Flora", "Vault" }

-- The lobby budget area (same box as the Emberfall zone, any height): the
-- island from the quarry rim road's north edge to the south coast.
LobbyLayout.Area = {
	Min = Vector3.new(WorldLayout.Island.Min.X, -60, -122),
	Max = Vector3.new(WorldLayout.Island.Max.X, 400, WorldLayout.Island.Max.Z),
}

-- Mobile budgets. Map = every BasePart in Workspace.Map; Lobby = parts and
-- PointLights/SpotLights whose part is inside LobbyLayout.Area.
LobbyLayout.Budget = {
	-- visual upgrade (concept v2): richer stalls, brick plot walls, town
	-- buildings; + the owner-approved Blaster Vault package (~2970 parts);
	-- + the owner-approved Candy mountains (~570 parts: Spectrum strata on
	-- the massif and the Land range, the spire skyline); + the owner-approved
	-- Horizon (~2,450 parts far out at sea and in the sky, Persistent: the
	-- outer sea, Kenney kit isles and ships, planets, constellations); + the
	-- owner-approved meadow and road look (~1,330 parts: grass tufts, grass
	-- patches and flower beds on the free lawns, fences along the roads, the
	-- main roads paved with kerbs and glowing studs).
	-- (the blaster gallery in THE GREAT FORGE's hall went with the hall, 2026-10-20: the open
	-- passage and the bridge garden took its place)
	-- + the artifact museums (steps 6-7: ArtifactService builds one into
	-- every plot's yard at server start, MuseumBuilder, ~44 structure parts
	-- each = ~350; the relics the owners found are NOT on the server: the
	-- clients build them only for museums near the camera, at most
	-- ArtifactConfig.MaxParts each, so a full collection never touches
	-- this budget).
	-- + the concept fixes (~350: plaza miners, lanterns, stall props, the
	-- stream with its bridge and waterfall) and the meadow ponds.
	-- tests/LobbyBudget.spec.luau: the built map (perf pass 1 cut ~110 parts)
	-- + one ore node on every node spawn (~1,320) + the 8 empty museums (~350)
	-- must stay 200 under it (the podium and pen ores).
	-- + the six mine floor areas (integrator 2026-10-18: ≤ 2,500 parts each,
	-- MineKit.PartBudget; ~8,160 in all after the trims, + ~1,900 for the
	-- Stormglass Rift; floors 4-6 sit far north and deep and never stream in
	-- near the town).
	-- (bigger plots 2026-10-21, 16x16 grid: the map 31,773 + nodes 294 + museums 352 = 32,419 measured,
	-- + 200 for the podium and pen ores, + ~250 headroom; 32,200 at 12 cells)
	-- (2026-10-22, map v48: the sea bay behind the Vault filled with island (owner), its lawn
	-- planted: the map 31,895 + nodes 294 + museums 352 = 32,541 measured, ~110 headroom)
	-- (2026-10-22, map v49: + the six more floating islands and SKY HAVEN with its SKY EGG and
	-- lit path, ~1,050 outside the lobby area: ~33,590 measured)
	-- (2026-10-23, map v52 on main v51 (33,688 measured): SKY HAVEN's stones as little islets, its spire
	-- mossy, 12 vines under the island, trimmed to +136: 33,824 measured)
	-- (owner 2026-10-24, "quality over the limits": the town's lawn back to its full density, the
	-- lawn behind the Vault's pieces on top of it, Meadow.Max: +231 parts; the map 33,450 + nodes 294
	-- + museums 352 = 34,096 measured, + 200 for the podium and pen ores = 34,296, + ~30: 34,100 -> 34,330)
	MapParts = 34330, -- (+50 owner 2026-10-23: the DROPPERS shop's boulders, round roof, crystal logo, vines and trees; 33,873 + 200 measured; asked via the integrator)  23,000 (integrator plan 2026-10-18, docs/QA_NIGHT_2026-10-18.md section 7, + the yard museums) + the mine floors + the bigger plots + the more floating islands and SKY HAVEN
	-- 5000 for the lobby art + about 1200 for the 8 player bases with their
	-- yards (design v2) + room for the coastal railway (step 2) + the Blaster
	-- Vault. Plots stream in and out with StreamingEnabled like everything else.
	-- The 8 yard museums (steps 6-7) are inside the area and counted too. The
	-- headroom is a deliberate buffer, so a small merge from a parallel
	-- package session (Backdrop, Districts, Plaza, Flora) does not break this
	-- budget; spend it on purpose, not by accident.
	-- (bigger plots 2026-10-21: 14,226 measured with the museums, + ~250 headroom; 13,700 at 12 cells. The
	-- bigger lobby area now counts the Vault's south trees (~110), + the street lamps along the longer
	-- plot roads (~110), + the meadow on the new south lawns (~300); 2026-10-22: the sea bay behind
	-- the Vault is island again, its cliffs gone, its lawn planted: 14,301 measured with the museums)
	-- (owner 2026-10-24, "quality over the limits": the town's lawn back to its full density, Meadow.Max,
	-- +217 in the lobby area: 14,347 + museums 352 = 14,699 measured, + ~30: 14,500 -> 14,730)
	LobbyParts = 14730, -- integrator plan 2026-10-18: + the blaster gallery (Kenney-shape guns: +174), + the plaza life, + the yard museums
	LobbyLights = 62, -- (2026-10-20: + ~20 street lamp lights, every other lamp along the roads; shadows off)
	-- phones (integrator 2026-10-18): what streams in around a player in the lobby, i.e. the
	-- lobby area plus every Persistent model's parts anywhere, plus the 8 yard museums
	-- (steps 6-7): ~15,510 parts (tests/PhoneBudget.spec.luau, map v26)
	PhoneParts = 18000,
	-- phones (integrator 2026-10-22, the SKY HAVEN review): everything within Workspace.
	-- StreamingTargetRadius (384) of the spawn or the plaza, Lod models included, + the Persistent
	-- models beyond it + the 8 yard museums (tests/PhoneBudget.spec.luau): map v49 with the sky
	-- islands and SKY HAVEN measures ~24,550 at the plaza (21,421 + 2,785 + 352), ~24,300 at the spawn
	-- (owner 2026-10-24: "limit je jedno, hlavni je aby vse bylo nejlepsi", phones and PC alike: the
	-- town's lawn back to its full density, Meadow.Max, ~+230 near each spot; map v57 measures 24,811 at
	-- the spawn (21,680 + 2,779 + 352), 25,063 at the plaza (21,926 + 2,785 + 352) and 25,206 at the
	-- DROPPERS shop's door (21,578 + 2,750 + 352 + the 526-part showroom, tests/DropperShop.spec.luau),
	-- + ~30: 25,000 -> 25,240)
	StreamParts = 25240,
	-- per package: Parts = all parts in Map.Emberfall.Lobby.<Package>,
	-- LobbyParts = those of them inside LobbyLayout.Area,
	-- Lights = all PointLights/SpotLights of that package,
	-- LobbyLights = those of them inside LobbyLayout.Area.
	-- Everything else inside the lobby area today (ground, plots, ore
	-- outcrops, the quarry rim) is ~360 parts and 8 lights; the rest is spare.
	Packages = {
		Sky = { Parts = 2100, LobbyParts = 200, Lights = 6, LobbyLights = 2 }, -- (2026-10-22: SKY HAVEN's premium SKY EGG with its orbit rings, columns and clouds, and the lit path with three sky gates, ~190, outside the lobby area; then its parkour stones as little islets, the mossy spire and the vines under the island, +136: 2,041)
		Backdrop = { Parts = 4800, LobbyParts = 500, Lights = 10, LobbyLights = 3 }, -- + Spectrum strata and spires (Candy mountains), + Horizon (~2,450)
		Plaza = { Parts = 3300, LobbyParts = 3300, Lights = 30, LobbyLights = 30 }, -- (2026-10-20, owner: the street lamps along every road, ~35 lamps of 12-14 parts, every other one lit, in place of the 9 road lanterns, and every road a neon walkway without kerbs and studs) (2026-10-20: the blaster gallery, ~500 parts, went with THE GREAT FORGE's hall; the open passage's stone pillars and the bridge garden under and behind the roof came, ~700, and the two stone kings at its steps, ~390, no lights) + facade aprons, planters, ore carts, + Plaza/Life (~220: miners, hanging lanterns, stall-front props)
		Districts = { Parts = 2500, LobbyParts = 2500, Lights = 11, LobbyLights = 11 }, -- (2026-10-23: + the DROPPERS shop's grounds and round roof, 2,469 measured) + v2 stalls, concept v2 look (~2,080 parts after perf pass 1) + the walk-in DROPPERS shop (owner 2026-10-23, ~2,425; the map total stays inside MapParts / LobbyParts)
		Flora = { Parts = 4150, LobbyParts = 3205, Lights = 8, LobbyLights = 8 }, -- the town-edge tree belts, the scatter, the Meadow (~1,770: lawns, fences, ponds, jungle trees on the lawns and the mountains; the town houses went 2026-10-18) + the Wilds (owner 2026-10-21, ~790: pebble, grass, flower, bush and stump groups on the lawns and the near mountains' green tops, five secrets; ~410 of them in the lobby area, a few of the Meadow lawn's tufts make way) + the bigger plots (2026-10-21, 16x16 grid: the meadow, ponds and wilds on the new south lawns, the town belt's road-side row on along the longer plot roads; 3,880 measured, 3,004 of them in the lobby area) + the lawn behind the Vault where the sea bay was (owner 2026-10-22: a koi pond, 8 voxel trees, a butterfly and its share of the meadow's capped lawn pieces: the town's lawn ~26% thinner, tufts 100 -> 58, flower beds 47 -> 34, Meadow.Max; 3,956 measured, 3,047 of them in the lobby area) (owner 2026-10-24, "quality over the limits": the town's lawn back to its full density, tufts 58 -> 100, flower beds 34 -> 48, patches 52 -> 60, bushes 30 -> 36, rocks 20 -> 24, the lawn behind the Vault keeping its own share on top, Meadow.Max / Meadow.SouthLawnMax: 4,046 measured, 3,173 of them in the lobby area, + ~30: LobbyParts 3,100 -> 3,205; Parts unchanged)
		Vault = { Parts = 3500, LobbyParts = 3500, Lights = 6, LobbyLights = 6 }, -- the Blaster Vault, its statues and jungle trees (~2970 parts, 5 lights)
	} :: { [string]: { Parts: number, LobbyParts: number, Lights: number, LobbyLights: number } },
	-- Land.luau (the Backdrop package restyles it) had 1775 parts before the
	-- lobby pass and may grow by at most LandExtraParts.
	LandBaselineParts = 1775,
	LandExtraParts = 450, -- + Spectrum strata on the mountain columns
}

-- Where the low evening sun should sit (unit vector toward the sun):
-- azimuth ~262 deg (just south of west, over the west sea), ~13 deg high.
-- Preview shots use it as "sunDir"; the Sky package tunes ClockTime and
-- GeographicLatitude so Lighting:GetSunDirection() matches it in Studio.
LobbyLayout.SunDirection = Vector3.new(-0.965, 0.225, 0.136).Unit

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function toward(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return d.Unit
end

-- Bigger plots (WorldLayout.PlotGrid): pieces in the south band (past the
-- plot roads' south end) move south with the plot columns, pieces on the
-- outer coast move out with it. Both shifts are 0 at 12 cells.
local GRID = WorldLayout.PlotGrid

-- The DROPPERS house (owner 2026-10-23) and the half-round walkway apron in
-- front of its porch (owner: "a half circle in front of it"; later "turn the
-- shop so its entrance faces the crystal in the middle, and make it wider"):
-- the house stands north-east of the plaza between the plaza rim, the east
-- spur, the east plot road and the ore outcrops at (56, 46) and (50, 58),
-- its front to the plaza's fire crystal; the apron's straight edge runs
-- along the porch front and its round edge reaches the plaza rim.
local DROPPERS_DIR = Vector3.new(math.cos(math.rad(34)), 0, math.sin(math.rad(34)))
local DROPPERS_CENTER = DROPPERS_DIR * 53.5
local DROPPERS_FACING = -DROPPERS_DIR
LobbyLayout.DroppersFront = 4.5 -- the front wall's local z (DropperShopBuilder.Room.Front)
local DROPPERS_APRON = DROPPERS_CENTER + DROPPERS_FACING * (LobbyLayout.DroppersFront + 4.7)
LobbyLayout.DroppersApron = {
	Center = DROPPERS_APRON, -- the middle of the straight edge
	Radius = DROPPERS_APRON.Magnitude - 36.1, -- (to the plaza rim)
	Back = 4.2, -- from the straight edge back to the house wall (the apron is a U)
	PorchHalf = 5.4, -- half the porch's width (no panels under its planks)
}
local function south(p: Vector3): Vector3
	return p + Vector3.new(0, 0, GRID.SouthShift)
end
local function coast(x: number): number
	return x + math.sign(x) * GRID.CoastShift
end

-- (bigger plots: the sea bay that was left behind the Blaster Vault is island
-- again, owner 2026-10-22: "fill the gap"; the south coast runs straight
-- at every grid size, Land, and the lawn behind the Vault is decorated like
-- the lawns either side, Flora)

local PLAZA = v(0, 0, 0)
local SHOP = v(-46, 0, -22)
local UPGRADES = v(46, 0, -22)
local SHOP_FACING = toward(SHOP, PLAZA)
local UPGRADES_FACING = toward(UPGRADES, PLAZA)
-- the SHOP's local +X (its south end, toward the spawn)
local SHOP_RIGHT = Vector3.new(-SHOP_FACING.Z, 0, SHOP_FACING.X)
-- (lobby fix round 3: the giant wheel stands free north of the SHOP, square
-- to the plaza, so its disc clears the SHOP's roof from the spawn; the
-- forge west path and the west plot road leave 34 studs between them, the
-- NW pool and the outcrop at (-52, -52) bound it north and south)
local WHEEL = v(-47.5, 0, -72.5)
-- (round 3: CAPSULES moved south-east into the spawn view, between the west
-- spur and the lily pond, turned half to the plaza, half to the spawn)
-- (owner 2026-10-22: the egg temple, wider and bigger: 25 x 18, its back
-- toward the west plot road, its front to the plaza; between the west spur
-- and the lily pond)
local CAPSULES = v(-44.5, 0, 20.3)
-- the Blaster Vault closes the south road (its steps at z ~79.6)
local VAULT = v(0, 0, 112.4)
-- the MINE (Backdrop: hill + yard): designed at MINE_DESIGN facing east,
-- built in the south-west corner (see the MineEntrance piece)
local MINE_DESIGN = v(-46, 0, 88)
local MINE = south(v(-100, 0, 134))
local MINE_FACING = v(1, 0, 0)
local function mineMoved(p: Vector3): Vector3
	local from = CFrame.lookAt(MINE_DESIGN, MINE_DESIGN + v(1, 0, 0))
	local to = CFrame.lookAt(MINE, MINE + MINE_FACING)
	return (to * from:Inverse()) * p
end

LobbyLayout.Pieces = {
	------------------------------------------------------------ Plaza package
	{
		Id = "Plaza",
		Package = "Plaza",
		Center = PLAZA,
		Size = v(72, 1, 72),
		Radius = 36,
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Round flagstone plaza in concentric rings, radiating seams, low edge curb with gaps for every road.",
	},
	{
		Id = "FireCrystal",
		Package = "Plaza",
		Center = PLAZA,
		Size = v(22, 24, 22),
		Radius = 11,
		Facing = v(0, 0, 1),
		Note = "Stepped stone ring (glowing orange insets) around a pedestal with the giant orange fire crystal (tag Spin, slow).",
	},
	{
		Id = "SpawnPad",
		Package = "Plaza",
		Center = WorldLayout.SpawnPoint,
		Size = v(18, 1, 18),
		Radius = 9,
		Facing = v(0, 0, -1),
		Walkable = true,
		Note = "Keep clear: only flat paving. Town.luau builds the TownSpawn SpawnLocation here.",
	},
	{
		Id = "GreatForge",
		Package = "Plaza",
		-- front at z -38; 42 wide (the forge paths at x +-26 are 9 wide: x +-21.5),
		-- grown upward and deeper instead of wider
		Center = v(0, 0, -62),
		Size = v(42, 54, 48),
		Facing = v(0, 0, 1),
		Note = "Stone hall on a raised plinth with a long stair, dark slate gable roof with shingle courses and a red ridge trim (ridge <= 38 so the DEPTHS sign still shows above it from the hero camera), short chimneys, crossed-hammers gable emblem, banners hung from gold rods, THE GREAT FORGE board, open glowing interior.",
	},
	------------------------------------------------------------ Districts package
	{
		Id = "Shop",
		Package = "Districts",
		Center = SHOP,
		Size = v(28, 20, 14),
		Facing = SHOP_FACING,
		Note = "SHOP = the Gear shop (boots, helmet lamp, backpack, gloves, magnet): pink/white striped awning, glowing blue SHOP sign, gear on racks. Hook ShopCounter.",
	},
	{
		Id = "ShopFront",
		Package = "Districts",
		-- south of the SHOP's door lane, out at the plaza rim (the 6.6 wide door
		-- lane stays open; the west spur road leaves no room beside the SHOP's
		-- south end): a narrow stall reaching from the SHOP's porch to the rim
		Center = SHOP + SHOP_FACING * 12.5 + SHOP_RIGHT * 6.6,
		Size = v(6.6, 10.6, 8), -- (round 3: the SELL box rides higher, over Tobin's head)
		Facing = SHOP_FACING,
		Note = "Tobin's Sell stall south of the SHOP's door lane: an ore cart with a counter and a scale (tag SellCounter), the SellBin (tag SellBin, child part Intake), Tobin the Miner (NPC) facing the lane, a SELL sign.",
	},
	{
		Id = "Upgrades",
		Package = "Districts",
		Center = UPGRADES,
		Size = v(28, 20, 14),
		Facing = UPGRADES_FACING,
		Note = "UPGRADES stall = the Tech shop (automation machines, machine upgrades): purple/white striped awning, glowing blue UPGRADES sign, blue neon trims. Hook UpgradeCounter.",
	},
	{
		Id = "UpgradesFront",
		Package = "Districts",
		Center = UPGRADES + UPGRADES_FACING * 11.5,
		Size = v(14, 7, 8),
		Facing = UPGRADES_FACING,
		Note = "Display props in front of UPGRADES: a glowing laser blaster on a pedestal, small machine models, gear crates.",
	},
	{
		Id = "SpinWheel",
		Package = "Districts",
		Center = WHEEL,
		-- (round 3: 33 wide (the roads either side allow no more), 58 tall:
		-- the frame at scale 2 on a platform 4 studs higher, the disc clears
		-- the SHOP from the spawn; 22 deep for a longer stair run)
		Size = v(33, 58, 22),
		Facing = v(0, 0, 1),
		Note = "SPIN & WIN = the free daily wheel of fortune, the giant free-standing landmark behind and left of the SHOP (nothing hides its disc and stairs from the spawn), square to the plaza. EmberChest (tag) on the side of its top landing.",
	},
	{
		Id = "GuildBoard",
		Package = "Districts",
		Center = v(-15, 0, -30),
		Size = v(9, 11, 3),
		-- (round 3: turned 20 degrees to the plaza: it no longer stacks on the wheel)
		Facing = v(math.sin(math.rad(20)), 0, math.cos(math.rad(20))),
		Note = "Forgekeepers' notice board beside the forge porch (tag GuildBoard on the model).",
	},
	{
		Id = "FossilDig",
		Package = "Districts",
		-- turned toward the hero camera and the spawn (its gate faces south-west)
		-- (round 3: a big open dig pulled toward the plaza, between the plaza
		-- rim and the outcrops at (56, 46) and (50, 58))
		-- (owner 2026-10-23: moved by the Tech shop, north-east of the plaza, turned to it;
		-- the DROPPERS house took its old place)
		Center = v(49, 0, -60),
		Size = v(26, 14, 30),
		Facing = v(-1, 0, 0),
		Note = "Fenced sunken-look dirt pit with a dinosaur skeleton, tools, FOSSIL DIG sign: the artifacts + Kingdom of Kaldrum story corner. Tag FossilDig on the model.",
	},
	{
		Id = "DroppersHouse",
		Package = "Districts",
		-- the DROPPERS shop (owner 2026-10-23) where the FOSSIL DIG stood, its front to the crystal
		Center = DROPPERS_CENTER,
		-- (the walk-in shop 30 wide and 15 deep + the porch)
		Size = v(32, 27, 23),
		Facing = DROPPERS_FACING,
		Note = "Town-style house (stone ground floor, timber upper floor, terracotta roof, DROPPERS sign); its porch counter carries the DropperCounter tag (ShopService: opens the Tech shop).",
	},
	{
		Id = "DroppersApron",
		Package = "Plaza",
		Center = LobbyLayout.DroppersApron.Center + DROPPERS_FACING * (LobbyLayout.DroppersApron.Radius / 2),
		Size = v(LobbyLayout.DroppersApron.Radius * 2 + 1, 1, LobbyLayout.DroppersApron.Radius),
		Facing = DROPPERS_FACING,
		Walkable = true,
		Note = "Half-round neon walkway apron in front of the DROPPERS porch (Plaza/Roads), street lamps at its two ends.",
	},
	{
		Id = "CapsuleStall",
		Package = "Districts",
		-- front-left anchor (concept v2): its front reads from the spawn camera
		-- and from the hero camera (round 3: wholly inside the spawn view, its
		-- front corners outside the plaza curb, r 36)
		Center = CAPSULES,
		Size = v(25, 26, 18), -- (the giant egg's light beam on the roof reaches 26; 25 wide: the eggs ~7.6 studs apart, owner 2026-10-22; the west spur's lamps keep their spots)
		-- (28 wide: square to the lawn between the west spur and the lily pond,
		-- facing east, between the plaza and the spawn)
		Facing = v(1, 0, 0),
		Note = "The EGGS temple left of the spawn (owner 2026-10-21/22): an open gold rotunda with the three eggs on podiums, a curved navy back wall, crystal shards, a giant crowned egg on the roof, EGGS sign, odds board. Tag CapsuleStall (Model with PrimaryPart CapsuleMachine).",
	},
	{
		Id = "BackpackStall",
		Package = "Districts",
		-- (owner 2026-10-24: a new BACKPACKS stall; then "in place of the ROCK SCANNER, in
		-- front of the Vault", bigger like a shop: the ROCK SCANNER went (the Ore Codex
		-- opens from the side menu), the shop stands at the end of the ToScanner path,
		-- its gateway to the path, between the DROPPERS house, the vault's east statue,
		-- the red trees and the outcrop at (50, 58))
		Center = v(46, 0, 74),
		Size = v(16, 16, 12),
		Facing = v(-1, 0, 0),
		Note = "BACKPACKS: a small walk-in shop (porch with two plinths, gold-framed gateway, BACKPACKS board, corner pillars with lantern cubes, a roof podium for the giant turning Starforge pack, side racks, the counter and the shopkeeper's step). Tag BackpackCounter (BasePart: the counter top, Attachments BackpackPromptPoint and KeeperFeet); the plates carry the attribute BackpackId (no tag): the clients build the ten display packs and the small decor (Builders/BackpackShopDecor), they are not map parts.",
	},
	{
		Id = "EnchantShop",
		Package = "Districts",
		Center = v(50, 0, -84),
		Size = v(16, 16, 12),
		Facing = toward(v(50, 0, -84), v(0, 0, -20)),
		Note = "Design v2: Enchant shop behind UPGRADES, past the pink trees: a small mystic workshop with a glowing purple rune table, floating crystals, ENCHANT sign. Tag EnchantCounter (BasePart: the table top).",
	},
	{
		Id = "HallOfFame",
		Package = "Districts",
		-- (round 3: off the south-east rim, where it hid the FOSSIL DIG and the
		-- ROCK SCANNER; the outcrops leave no room by the east plot road, so a
		-- compact board stands beside the forge porch opposite the guild board)
		Center = v(14, 0, -25),
		-- (owner 2026-10-20: the giant hall: four tall boards side by side, the
		-- champions' avatars hopping on pedestals over the HALL OF FAME sign)
		Size = v(22, 21, 4),
		Facing = v(-math.sin(math.rad(28)), 0, math.cos(math.rad(28))), -- (2026-10-20: 5 studs forward, turned 13 deg more to the plaza: the giant hall clears the forge east path)
		Note = "Design v2: four leaderboards (Money per second, Total earned, Artifacts found, Hours played) side by side in a giant hall wall beside the forge porch (owner 2026-10-20: massive, the best player's avatar hops on top). Each board is a BasePart named Board1..Board4 with tag Leaderboard and attribute Board = 1..4; a HALL OF FAME sign; over it pedestals Champion1..Champion4 (tag LeaderChampion, attribute Board) for the #1 players' avatars.",
	},
	------------------------------------------------------------ Flora package
	{
		Id = "LilyPond",
		Package = "Flora",
		Center = v(-37, 0, 41.5),
		Size = v(24, 2, 16),
		Facing = v(0, 0, 1),
		Note = "Big blocky stone-rimmed pond left of the plaza, south of CAPSULES (concept v1: the hero sees it past the stall) with lily pads, pink flowers, a few purple crystals on the bank.",
	},
	{
		Id = "KoiPond",
		Package = "Flora",
		Center = v(0, 0, 50),
		Size = v(44, 2, 18),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "The big front koi pond under the arched bridge (concept v1): orange/white koi, lily pads, stepping stones, lanterns. Walkable: the bridge carries the south road over it (water is non-collide over solid ground).",
	},
	{
		Id = "CreekBridge",
		Package = "Flora",
		Center = v(0, 0, 50),
		Size = v(12, 8, 23),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Humped wooden bridge carrying the south road over the koi pond, stepped arched railings, a lantern post at each end.",
	},
	{
		Id = "Signpost",
		Package = "Flora",
		-- on the koi pond's south-west bank, west of the bridge's south end and
		-- out of the plaza-to-vault view (it hid the west statue's pedestal),
		-- facing the hero camera
		Center = v(-20, 0, 62),
		Size = v(14, 17, 4),
		Facing = v(0.16, 0, 0.99).Unit,
		Note = "Big double-sided signpost: MINE / UPGRADE / EXPLORE / BUILD with part-built icons.",
	},
	{
		Id = "NextArea",
		Package = "Flora",
		Center = v(150, 0, -120),
		Size = v(22, 16, 4),
		Facing = v(0, 0, 1),
		Note = "NEXT AREA -> sign (arrow points east along the boardwalk), lantern posts, a closed rope gate.",
	},
	{
		Id = "NextAreaBoardwalk",
		Package = "Flora",
		-- (from the coast to the landing at x 240, which stays put)
		Center = v(205 + GRID.CoastShift / 2, 0, -112),
		Size = v(8, 3, 70 - GRID.CoastShift),
		Facing = v(1, 0, 0),
		Walkable = true,
		Note = "Plank boardwalk on posts from the east coast out over the sea toward the Sky package's NextIsland.",
	},
	{
		Id = "PinkGrove",
		Package = "Flora",
		-- (owner 2026-10-23: the FOSSIL DIG took its place behind UPGRADES; the grove moved
		-- to the south-west park by the ponds)
		Center = v(-54, 0, 74),
		Size = v(22, 30, 22),
		Radius = 10,
		Facing = v(0, 0, 1),
		Note = "Two big pink voxel cherry trees in the south-west park (hero trees).",
	},
	{
		Id = "RedTree",
		Package = "Flora",
		Center = v(59, 0, 80),
		Size = v(12, 18, 12),
		Radius = 6,
		Facing = v(0, 0, 1),
		Note = "One big red voxel tree at the east town edge (it joins the east tree belt, off the camera-to-dig line).",
	},
	{
		Id = "AutumnCorner",
		Package = "Flora",
		-- (behind the MINE hill in the south-west corner: the Vault's jungle
		-- trees took its old spot)
		Center = south(v(-139, 0, 130)),
		Size = v(24, 18, 24),
		Radius = 12,
		Facing = v(0, 0, 1),
		Note = "Cluster of yellow and orange voxel trees and bushes in the south-west corner, behind the MINE hill.",
	},
	------------------------------------------------------------ Backdrop package
	-- (the Blaster Vault took the MINE's old spot west of the south road: the
	-- hill and its yard moved to the south-west corner past the west plot
	-- road's end, the front-left of the hero view; Lowlands.luau still builds
	-- them at their design spot and Town.relocate moves them here)
	{
		Id = "MineEntrance",
		Package = "Backdrop",
		Center = MINE,
		Size = v(26, 20, 20),
		Facing = MINE_FACING,
		DesignCenter = MINE_DESIGN,
		DesignFacing = v(1, 0, 0),
		Note = "Voxel rock hill with a timber mine portal (MINE sign, crossed pickaxes), dark tunnel mouth, lanterns.",
	},
	{
		Id = "MineYard",
		Package = "Backdrop",
		Center = mineMoved(v(-20, 0, 88)),
		Size = v(12, 4, 30),
		Facing = MINE_FACING,
		DesignCenter = v(-20, 0, 88),
		DesignFacing = v(1, 0, 0),
		Walkable = true,
		Note = "Rails from the portal toward the west plot road's end, buffer stop, two carts heaped with glowing gold.",
	},
	{
		Id = "NWCliff",
		Package = "Backdrop",
		Center = v(-48, 0, -98),
		Size = v(32, 22, 10),
		Facing = v(0, 0, 1),
		Note = "Dark voxel stone cliff with grass ledges, a waterfall, purple crystals (left of the forge in the hero view).",
	},
	{
		Id = "NWPool",
		Package = "Backdrop",
		Center = v(-48, 0, -88),
		Size = v(18, 2, 8),
		Facing = v(0, 0, 1),
		Note = "Splash pool at the foot of the NW cliff waterfall.",
	},
	{
		Id = "ForgeMountain",
		Package = "Backdrop",
		Center = v(40, 22, -290),
		Size = v(240, 100, 100),
		Facing = v(0, 0, 1),
		Note = "Stepped dark-stone massif north of the quarry (rests on the Ember Caves roof, y >= 22): ledges, trees, crystals, waterfalls.",
	},
	{
		Id = "DepthsPortal",
		Package = "Backdrop",
		Center = v(0, -12, -236),
		Size = v(44, 40, 8),
		Facing = v(0, 0, 1),
		Note = "Stone-and-iron tunnel portal framing the Ember Caves entrance (keep the 18x16 opening and the tunnel walkable), receding glowing arch rings inside, DEPTHS sign with a down arrow over the arch, lanterns. Replaces Land's EMBER CAVES sign.",
	},
	{
		Id = "ForgeWorks",
		Package = "Backdrop",
		Center = v(34, 26, -250),
		Size = v(34, 34, 18),
		Facing = v(0, 0, 1),
		Note = "Industrial works on the cave roof right of the portal (seen right of the Great Forge in the hero shot): THE FORGE sign with crossed hammers, stone-and-iron block house with lit windows and a PWR gauge board, ore chute with a conveyor down to the quarry, derrick.",
	},
	{
		Id = "DepthsRails",
		Package = "Backdrop",
		Center = v(0, -12, -218),
		Size = v(8, 3, 34),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Rails out of the DEPTHS portal across the quarry floor, one ore cart.",
	},
	{
		Id = "QuarryFallsWest",
		Package = "Backdrop",
		Center = v(-44, -12, -232),
		Size = v(12, 46, 6),
		Facing = v(0, 0, 1),
		Note = "Waterfall down the massif face into a pool hugging the quarry's north wall (pool within 5 studs of the wall).",
	},
	{
		Id = "QuarryFallsEast",
		Package = "Backdrop",
		Center = v(44, -12, -232),
		Size = v(12, 46, 6),
		Facing = v(0, 0, 1),
		Note = "Second waterfall, east of the portal.",
	},
	{
		Id = "ScaffoldWest",
		Package = "Backdrop",
		Center = v(-96, 0, -170),
		Size = v(10, 60, 10),
		Facing = v(0, 0, 1),
		Note = "Timber scaffold tower with a derrick top and a lantern, rising out of the west mountains.",
	},
	{
		Id = "ScaffoldWest2",
		Package = "Backdrop",
		Center = v(-124, 0, -206),
		Size = v(10, 56, 10),
		Facing = v(0, 0, 1),
		Note = "Second scaffold tower.",
	},
	{
		Id = "Crane",
		Package = "Backdrop",
		Center = v(104, 64, -268),
		Size = v(40, 40, 12),
		Facing = v(-0.6, 0, 0.8).Unit,
		Note = "Lattice crane on a massif ledge, jib reaching south-west, hanging crate.",
	},
	{
		Id = "Beacon",
		Package = "Backdrop",
		Center = v(60, 104, -300),
		Size = v(10, 30, 10),
		Facing = v(0, 0, 1),
		Note = "Derrick/radio tower on the peak with a red neon beacon.",
	},
	------------------------------------------------------------ Vault package
	-- (owner-approved spot: the Blaster Vault closes the south road, facing
	-- the plaza; Vault.luau places its jungle trees relative to the vault)
	{
		Id = "BlasterVault",
		Package = "Vault",
		Center = VAULT,
		-- podium 1.3, eaves ~20, ridge ~34, fire towers ~31, the hologram
		-- blaster ~55, the searchlight beams ~76
		Size = v(67.2, 76, 65.6),
		Facing = v(0, 0, -1),
		Note = "BLASTER VAULT = the blaster shop at the end of the south road: stone hall on a podium, glass front, lava-lit gables, fire towers, a spinning hologram blaster, searchlights, the cases and the counter inside (tag VaultCounter), a LightingZone over the inside.",
	},
	{
		Id = "VaultStatueWest",
		Package = "Vault",
		Center = v(-43, 0, 92),
		Size = v(15.4, 45, 13.4), -- the pedestal (the statue's arms reach ~2 studs past it up high)
		Facing = v(0.296, 0, -0.955).Unit,
		Note = "Giant stone king statue with glowing lava cracks on a pedestal, turned to the plaza, the blaster arm on the outer side.",
	},
	{
		Id = "VaultStatueEast",
		Package = "Vault",
		Center = v(43, 0, 92),
		Size = v(15.4, 45, 13.4),
		Facing = v(-0.296, 0, -0.955).Unit,
		Note = "The second giant statue, mirrored.",
	},
	-- the six jungle trees around the vault (reservations: the Vault package
	-- builds them as offsets from the vault, so they move with it); Radius =
	-- the canopy, Size.Y = the top
	{
		Id = "VaultTree1",
		Package = "Vault",
		Center = v(-29, 0, 153),
		Size = v(30, 57, 30),
		Radius = 15,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree behind the vault (west).",
	},
	{
		Id = "VaultTree2",
		Package = "Vault",
		Center = v(29, 0, 155),
		Size = v(32, 61, 32),
		Radius = 16,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree behind the vault (east).",
	},
	{
		Id = "VaultTree3",
		Package = "Vault",
		Center = v(-45, 0, 120),
		Size = v(26, 49, 26),
		Radius = 13,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree west of the vault.",
	},
	{
		Id = "VaultTree4",
		Package = "Vault",
		Center = v(-47, 0, 140),
		Size = v(28, 53, 28),
		Radius = 14,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree west of the vault, further back.",
	},
	{
		Id = "VaultTree5",
		Package = "Vault",
		Center = v(45, 0, 108),
		Size = v(26, 49, 26),
		Radius = 13,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree east of the vault, behind the east statue.",
	},
	{
		Id = "VaultTree6",
		Package = "Vault",
		Center = v(46, 0, 136),
		Size = v(28, 53, 28),
		Radius = 14,
		Reserve = true,
		Facing = v(0, 0, 1),
		Note = "Jungle tree east of the vault, further back.",
	},
	------------------------------------------------------------ Sky package
	{
		Id = "WestPier",
		Package = "Sky",
		Center = v(coast(-196), -22, -36),
		Size = v(10, 26, 44),
		Facing = v(-1, 0, 0),
		Walkable = true,
		Note = "Decor only (beyond the island's invisible wall): timber stairs down the west cliff to a plank dock 2.5 above the sea, posts in the water, lantern posts, a moored rowboat and a small sailboat.",
	},
	{
		Id = "SunGlitter",
		Package = "Sky",
		Center = v(-520, -21.8, 73),
		Size = v(36, 0.2, 660),
		Facing = v(-0.99, 0, 0.14).Unit,
		Walkable = true,
		Note = "Broken neon gold strips on the sea toward the low sun.",
	},
	{
		Id = "ShipA",
		Package = "Sky",
		Center = v(-240, -22, -90),
		Size = v(14, 26, 34),
		Facing = v(0, 0, 1),
		Note = "Sailing ship with orange-lit sails.",
	},
	{
		Id = "ShipB",
		Package = "Sky",
		Center = v(-330, -22, 10),
		Size = v(10, 20, 24),
		Facing = v(0.3, 0, -1).Unit,
		Note = "Smaller sailing ship.",
	},
	{
		Id = "CastleIsland",
		Package = "Sky",
		Center = v(-430, -22, -380),
		Size = v(110, 80, 70),
		Facing = v(1, 0, 0.3).Unit,
		Note = "Distant rocky islet with a castle/lighthouse silhouette (low detail, hazed by Atmosphere).",
	},
	{
		Id = "FloatingIslandWest",
		Package = "Sky",
		Center = v(-150, 77, -232),
		Size = v(40, 50, 34),
		Facing = v(0.5, 0, 0.87).Unit,
		Note = "Floating voxel island: grass top, hanging stone underside, cottage, tree, small waterfall.",
	},
	{
		Id = "FloatingIslandEast",
		Package = "Sky",
		Center = v(150, 105, -220),
		Size = v(44, 50, 36),
		Facing = v(-0.5, 0, 0.87).Unit,
		Note = "Bigger floating island with trees and a long waterfall falling into the mountains below.",
	},
	{
		Id = "NextIsland",
		Package = "Sky",
		Center = v(255, 16, -112),
		Size = v(46, 46, 40),
		Facing = v(-1, 0, 0),
		Note = "Floating island the NEXT AREA boardwalk points at: tower house with lit windows.",
	},
	{
		Id = "Balloon",
		Package = "Sky",
		Center = v(-60, 70, -120),
		Size = v(16, 26, 16),
		Facing = v(0.5, 0, 0.87).Unit,
		Note = "Hot air balloon (red/yellow stripes) with a little airship gondola; tag Spin with SpinSpeed 0.05, BobHeight 2.",
	},
	{
		Id = "CloudBanks",
		Package = "Sky",
		-- (reaches the south horizon too: one distant bank for lobby_south)
		Center = v(-250, 160, -300),
		Size = v(1500, 300, 1800), -- (round 3: the high banks moved up)
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Opaque two-tone voxel cloud clusters near the horizon (W/NW/N/NE, one far south bank): warm sunset undersides, light pink tops.",
	},
	-- (last: its random stream never reshuffles the other Sky pieces)
	{
		Id = "NearSea",
		Package = "Sky",
		Center = v(coast(-250), -21, -20),
		Size = v(160, 12, 560), -- (12 tall: a small far sail on its south end)
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Decor only: a small far sail on the south horizon (the deep-water bands were removed: they read as a dark rectangle next to the horizon sea).",
	},
} :: { Piece }

-- Extra walkable paths (the Plaza package renders them together with
-- WorldLayout.Roads). From/To are ground points; Width in studs.
LobbyLayout.Paths = {
	{ Id = "ToShop", From = v(-28, 0, -13), To = v(-40, 0, -19), Width = 12, Kind = "Cobble" },
	{ Id = "ToUpgrades", From = v(28, 0, -13), To = v(40, 0, -19), Width = 12, Kind = "Cobble" },
	-- from the forge west path to the wheel's stair foot: a 6-stud clear corridor
	{ Id = "ToWheel", From = v(-30.9, 0, -59.6), To = v(-44.5, 0, -58.5), Width = 6, Kind = "Cobble" },
	-- (the Blaster Vault's podium starts at z 79.6: the scanner path leaves the
	-- south road north of the vault's steps; since 2026-10-24 it leads to the
	-- BACKPACKS shop's gateway, the ROCK SCANNER went)
	{ Id = "ToScanner", From = v(5, 0, 71), To = v(37, 0, 74), Width = 6, Kind = "Cobble" },
	-- the MINE in the south-west corner: a dirt lane from the west plot road's
	-- end to the yard, a dirt track under the rails to the portal
	{ Id = "MineLane", From = south(v(-70, 0, 118)), To = south(v(-70, 0, 125)), Width = 9, Kind = "Dirt" },
	{ Id = "ToMine", From = mineMoved(v(-13, 0, 88)), To = mineMoved(v(-34, 0, 88)), Width = 9, Kind = "Dirt" },
	-- the south-east hamlet: a dirt lane from the east plot road's end to the
	-- MAP door, round the south of the ore outcrop at (82, 118); it stops
	-- 2 studs short of the MAP facade (the town site stays free ground)
	{ Id = "HamletLane", From = south(v(70, 0, 119)), To = south(v(80, 0, 127.5)), Width = 5, Kind = "Dirt" },
	{ Id = "ToMap", From = south(v(80, 0, 127.5)), To = south(v(88, 0, 125)), Width = 5, Kind = "Dirt" },
	{ Id = "ToNextArea", From = v(75, 0, -115), To = v(coast(160), 0, -115), Width = 6, Kind = "Dirt" },
} :: { Path }

LobbyLayout.ById = {} :: { [string]: Piece }
for _, piece in LobbyLayout.Pieces do
	assert(LobbyLayout.ById[piece.Id] == nil, "duplicate lobby piece " .. piece.Id)
	LobbyLayout.ById[piece.Id] = piece
end

function LobbyLayout.get(id: string): Piece
	local piece = LobbyLayout.ById[id]
	assert(piece, "unknown lobby piece " .. id)
	return piece
end

-- Frame of a piece: origin at Center, LookVector = Facing, Y up.
function LobbyLayout.frame(piece: Piece): CFrame
	local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	return CFrame.fromMatrix(piece.Center, right, Vector3.new(0, 1, 0), -look)
end

-- Pieces of one package, in file order.
function LobbyLayout.ofPackage(package: string): { Piece }
	local out = {}
	for _, piece in LobbyLayout.Pieces do
		if piece.Package == package then
			table.insert(out, piece)
		end
	end
	return out
end

function LobbyLayout.inArea(position: Vector3): boolean
	return WorldLayout.isInBox(position, LobbyLayout.Area.Min, LobbyLayout.Area.Max)
end

-- A piece standing on the lobby ground (not in the sky, not outside the island).
function LobbyLayout.isGroundPiece(piece: Piece): boolean
	return piece.Center.Y < 10 and piece.Center.Y > -5 and LobbyLayout.inArea(piece.Center)
end

-- Distance from a ground point to a piece's footprint (0 inside; Y ignored).
function LobbyLayout.distanceTo(piece: Piece, p: Vector3): number
	local flat = Vector3.new(p.X, 0, p.Z)
	local c = Vector3.new(piece.Center.X, 0, piece.Center.Z)
	if piece.Radius then
		return math.max(0, (flat - c).Magnitude - piece.Radius)
	end
	local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local d = flat - c
	local lx = math.max(0, math.abs(d:Dot(right)) - piece.Size.X / 2)
	local lz = math.max(0, math.abs(d:Dot(look)) - piece.Size.Z / 2)
	return math.sqrt(lx * lx + lz * lz)
end

-- Distance from a ground point to a road/path strip (0 on it). Strips are
-- the segment widened by Width/2 and extended by Width/2 at both ends, like
-- the rendered road blocks.
function LobbyLayout.distanceToStrip(from: Vector3, to: Vector3, width: number, p: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	local q = Vector3.new(p.X, 0, p.Z)
	local ab = b - a
	local length = ab.Magnitude
	local dir = if length > 1e-6 then ab / length else Vector3.new(1, 0, 0)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local d = q - (a + b) / 2
	local lx = math.max(0, math.abs(d:Dot(side)) - width / 2)
	local lz = math.max(0, math.abs(d:Dot(dir)) - (length + width) / 2)
	return math.sqrt(lx * lx + lz * lz)
end

-- Is a ground point on a player base: the plot pad (+-BASE_HALF: +-28 at
-- 12 cells) or its yard and train stop on the sea side (plot-local z up to
-- BASE_BACK, 4 past the rail: 66 at 12 cells, docs BaseLayout)?
local BASE_HALF = GRID.Half + 4
local BASE_BACK = BaseLayout.RailZ + 4
function LobbyLayout.onBase(plot: WorldLayout.Plot, p: Vector3, radius: number): boolean
	local localPos = WorldLayout.plotCFrame(plot):PointToObjectSpace(Vector3.new(p.X, plot.Center.Y, p.Z))
	return math.abs(localPos.X) < BASE_HALF + radius and localPos.Z > -BASE_HALF - radius and localPos.Z < BASE_BACK + radius
end

--[[
	Is a ground point free for scattered decoration (trees, rocks, flowers)?
	`radius` = the decoration's own radius. Keeps off roads, lobby paths,
	plots, the plaza, ore outcrops, keep-out boxes and every lobby piece.
	Flora (and the legacy scatter) use it.
]]
function LobbyLayout.isFree(p: Vector3, radius: number): boolean
	if not LobbyLayout.inArea(p) then
		return false
	end
	local island = WorldLayout.Island
	if p.X < island.Min.X + radius or p.X > island.Max.X - radius or p.Z > island.Max.Z - radius then
		return false
	end
	if p.Z < -122 + radius then
		return false
	end
	for _, road in WorldLayout.Roads do
		if LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p) < radius + 1.5 then
			return false
		end
	end
	for _, path in LobbyLayout.Paths do
		if LobbyLayout.distanceToStrip(path.From, path.To, path.Width, p) < radius + 1 then
			return false
		end
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, radius) then
			return false
		end
	end
	for _, spot in WorldLayout.OutcropSpots do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < radius + 7 then
			return false
		end
	end
	if WorldLayout.isKeepOut(p, radius) then
		return false
	end
	for _, piece in LobbyLayout.Pieces do
		-- (reservations count even when their center lies past the area's edge:
		-- the jungle trees behind the vault stand on the south cliff top)
		local ground = LobbyLayout.isGroundPiece(piece) or piece.Reserve == true
		if ground and LobbyLayout.distanceTo(piece, p) < radius + 1 then
			return false
		end
	end
	return true
end

return LobbyLayout
