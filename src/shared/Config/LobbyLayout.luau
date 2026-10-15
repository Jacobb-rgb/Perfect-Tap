--[[
	Lobby layout: where every set piece of the town lobby goes (see
	docs/plans/LOBBY_PLAN.md and docs/ART_DIRECTION.md).

	The lobby is built by five parallel packages (src/server/World/Lobby/*).
	Each set piece here belongs to exactly one package. A piece is an
	oriented box on the ground:
	  Center  bottom center (ground point, Y = base height)
	  Size    local X = width, Y = height budget, Z = depth
	  Facing  the piece's front (LookVector), horizontal
	  Radius  optional: the footprint is a circle instead of a box
	  Walkable  flat walk-over decor (paths, rails, bridges): may sit on roads
	Build inside your footprint. tests/Lobby.spec.luau checks that the solid
	lobby footprints stay off roads, plots, ore outcrops, the spawn and each
	other, so packages can work in parallel without colliding.

	Only the art director edits this file. If a piece must move, ask; inside
	your own footprint you are free.
]]

local WorldLayout = require(script.Parent.WorldLayout)

export type Piece = {
	Id: string,
	Package: string,
	Center: Vector3,
	Size: Vector3,
	Facing: Vector3,
	Radius: number?,
	Walkable: boolean?,
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

LobbyLayout.Packages = { "Sky", "Backdrop", "Plaza", "Districts", "Flora" }

-- The lobby budget area (same box as the Emberfall zone, any height).
LobbyLayout.Area = {
	Min = Vector3.new(-170, -60, -122),
	Max = Vector3.new(170, 400, 150),
}

-- Mobile budgets. Map = every BasePart in Workspace.Map; Lobby = parts and
-- PointLights/SpotLights whose part is inside LobbyLayout.Area.
LobbyLayout.Budget = {
	MapParts = 11000,
	LobbyParts = 5000,
	LobbyLights = 45,
	-- per package: Parts = all parts in Map.Emberfall.Lobby.<Package>,
	-- LobbyLights = lights of that package inside the lobby area,
	-- Lights = all lights of that package
	Packages = {
		Sky = { Parts = 1400, LobbyLights = 2, Lights = 6 },
		Backdrop = { Parts = 1800, LobbyLights = 3, Lights = 11 },
		Plaza = { Parts = 1100, LobbyLights = 11, Lights = 11 },
		Districts = { Parts = 1000, LobbyLights = 9, Lights = 9 },
		Flora = { Parts = 1500, LobbyLights = 9, Lights = 10 },
	} :: { [string]: { Parts: number, LobbyLights: number, Lights: number } },
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

local PLAZA = v(0, 0, 0)
local SHOP = v(-46, 0, -22)
local UPGRADES = v(46, 0, -22)
local SHOP_FACING = toward(SHOP, PLAZA)
local UPGRADES_FACING = toward(UPGRADES, PLAZA)

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
		Center = v(0, 0, -58),
		Size = v(42, 50, 40),
		Facing = v(0, 0, 1),
		Note = "Stone hall, red stepped gable roofs, crossed-hammers gable sign, THE GREAT FORGE board, open glowing interior.",
	},
	------------------------------------------------------------ Districts package
	{
		Id = "Shop",
		Package = "Districts",
		Center = SHOP,
		Size = v(20, 20, 14),
		Facing = SHOP_FACING,
		Note = "SHOP = Pell's Trading Post: pink/white striped awning, glowing blue SHOP sign. Hooks ShopCounter + SellCounter.",
	},
	{
		Id = "ShopFront",
		Package = "Districts",
		Center = SHOP + SHOP_FACING * 11.5,
		Size = v(14, 7, 8),
		Facing = SHOP_FACING,
		Note = "In front of the SHOP counter: the SellBin (tag SellBin, child part Intake) and a few crates.",
	},
	{
		Id = "Upgrades",
		Package = "Districts",
		Center = UPGRADES,
		Size = v(20, 20, 14),
		Facing = UPGRADES_FACING,
		Note = "UPGRADES stall: purple/white striped awning, glowing blue UPGRADES sign, blue neon trims. Hook UpgradeCounter.",
	},
	{
		Id = "UpgradesFront",
		Package = "Districts",
		Center = UPGRADES + UPGRADES_FACING * 11.5,
		Size = v(14, 7, 8),
		Facing = UPGRADES_FACING,
		Note = "Display props in front of UPGRADES: pickaxe on a glowing pedestal, gear crates.",
	},
	{
		Id = "SpinWheel",
		Package = "Districts",
		Center = v(-48, 0, 18),
		Size = v(18, 26, 10),
		Facing = v(0.85, 0, 0.53).Unit,
		Note = "SPIN & WIN prize wheel on a timber A-frame, 8 colored segments, gold pointer, bulbs. EmberChest on its platform.",
	},
	{
		Id = "GuildBoard",
		Package = "Districts",
		Center = v(-15, 0, -30),
		Size = v(9, 10, 3),
		Facing = v(0, 0, 1),
		Note = "Forgekeepers' notice board beside the forge porch (tag GuildBoard on the model).",
	},
	{
		Id = "FossilDig",
		Package = "Districts",
		Center = v(50, 0, 24),
		Size = v(18, 8, 24),
		Facing = v(-1, 0, 0),
		Note = "Fenced sunken-look dirt pit with a dinosaur skeleton, tools, FOSSIL DIG sign. Tag FossilDig on the model.",
	},
	{
		Id = "RockScanner",
		Package = "Districts",
		Center = v(56, 0, 80),
		Size = v(12, 10, 10),
		Facing = v(-0.71, 0, 0.71).Unit,
		Note = "Stone platform, terminal with a glowing blue screen ring, sample rocks, ROCK SCANNER sign. Tag OreCodex on the terminal.",
	},
	------------------------------------------------------------ Flora package
	{
		Id = "LilyPond",
		Package = "Flora",
		Center = v(-26, 0, 62),
		Size = v(24, 2, 14),
		Facing = v(0, 0, 1),
		Note = "Blocky stone-rimmed pond with lily pads, pink flowers, a few purple crystals on the bank.",
	},
	{
		Id = "KoiPond",
		Package = "Flora",
		Center = v(26, 0, 62),
		Size = v(24, 2, 14),
		Facing = v(0, 0, 1),
		Note = "Koi pond: orange/white koi under the surface, lily pads, stepping stones, lanterns.",
	},
	{
		Id = "Creek",
		Package = "Flora",
		Center = v(0, 0, 62),
		Size = v(28, 1, 6),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Shallow creek joining the two ponds, flowing under the bridge (water is non-collide over solid ground).",
	},
	{
		Id = "CreekBridge",
		Package = "Flora",
		Center = v(0, 0, 62),
		Size = v(12, 5, 16),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Arched wooden bridge carrying the south road over the creek, railings, two lanterns.",
	},
	{
		Id = "Signpost",
		Package = "Flora",
		Center = v(-14, 0, 46),
		Size = v(7, 10, 3),
		Facing = v(0.52, 0, 0.86).Unit,
		Note = "Big double-sided signpost: MINE / UPGRADE / EXPLORE / BUILD with part-built icons.",
	},
	{
		Id = "NextArea",
		Package = "Flora",
		Center = v(150, 0, -120),
		Size = v(14, 12, 4),
		Facing = v(0, 0, 1),
		Note = "NEXT AREA -> sign (arrow points east along the boardwalk), lantern posts, a closed rope gate.",
	},
	{
		Id = "NextAreaBoardwalk",
		Package = "Flora",
		Center = v(205, 0, -112),
		Size = v(8, 3, 70),
		Facing = v(1, 0, 0),
		Walkable = true,
		Note = "Plank boardwalk on posts from the east coast out over the sea toward the Sky package's NextIsland.",
	},
	{
		Id = "PinkGrove",
		Package = "Flora",
		Center = v(41, 0, -66),
		Size = v(18, 22, 18),
		Radius = 9,
		Facing = v(0, 0, 1),
		Note = "Two big pink voxel cherry trees behind UPGRADES (hero trees).",
	},
	{
		Id = "RedTree",
		Package = "Flora",
		Center = v(28, 0, 40),
		Size = v(12, 18, 12),
		Radius = 6,
		Facing = v(0, 0, 1),
		Note = "One big red voxel tree in the south-east foreground (hero tree).",
	},
	{
		Id = "AutumnCorner",
		Package = "Flora",
		Center = v(-50, 0, 118),
		Size = v(24, 18, 24),
		Radius = 12,
		Facing = v(0, 0, 1),
		Note = "Cluster of yellow and orange voxel trees and bushes in the south-west foreground.",
	},
	------------------------------------------------------------ Backdrop package
	{
		Id = "MineEntrance",
		Package = "Backdrop",
		Center = v(-46, 0, 88),
		Size = v(26, 20, 20),
		Facing = v(1, 0, 0),
		Note = "Voxel rock hill with a timber mine portal (MINE sign, crossed pickaxes), dark tunnel mouth, lanterns.",
	},
	{
		Id = "MineYard",
		Package = "Backdrop",
		Center = v(-20, 0, 88),
		Size = v(12, 4, 30),
		Facing = v(1, 0, 0),
		Walkable = true,
		Note = "Rails from the portal toward the south road, buffer stop, two carts heaped with glowing gold.",
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
		Note = "Stone tunnel portal around the Ember Caves entrance (keep the 18x16 opening and the KeepOut box clear), DEPTHS sign with down arrow, THE FORGE sign above.",
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
	------------------------------------------------------------ Sky package
	{
		Id = "WestPier",
		Package = "Sky",
		Center = v(-192, 0, -36),
		Size = v(8, 6, 44),
		Facing = v(-1, 0, 0),
		Walkable = true,
		Note = "Wooden pier on posts from the west cliff out over the sea, lanterns, a moored rowboat.",
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
		Center = v(-150, 95, -250),
		Size = v(40, 50, 34),
		Facing = v(0.5, 0, 0.87).Unit,
		Note = "Floating voxel island: grass top, hanging stone underside, cottage, tree, small waterfall.",
	},
	{
		Id = "FloatingIslandEast",
		Package = "Sky",
		Center = v(150, 92, -185),
		Size = v(44, 50, 36),
		Facing = v(-0.5, 0, 0.87).Unit,
		Note = "Bigger floating island with trees and a long waterfall falling into the mountains below.",
	},
	{
		Id = "NextIsland",
		Package = "Sky",
		Center = v(255, 40, -112),
		Size = v(46, 46, 40),
		Facing = v(-1, 0, 0),
		Note = "Floating island the NEXT AREA boardwalk points at: tower house with lit windows.",
	},
	{
		Id = "Balloon",
		Package = "Sky",
		Center = v(-72, 74, -84),
		Size = v(16, 26, 16),
		Facing = v(0.5, 0, 0.87).Unit,
		Note = "Hot air balloon (red/yellow stripes) with a little airship gondola; tag Spin with SpinSpeed 0.05, BobHeight 2.",
	},
	{
		Id = "CloudBanks",
		Package = "Sky",
		Center = v(-300, 160, -500),
		Size = v(1400, 160, 1400),
		Facing = v(0, 0, 1),
		Walkable = true,
		Note = "Voxel cloud clusters near the horizon (W/NW/N), pink-orange lit undersides, purple tops.",
	},
} :: { Piece }

-- Extra walkable paths (the Plaza package renders them together with
-- WorldLayout.Roads). From/To are ground points; Width in studs.
LobbyLayout.Paths = {
	{ Id = "ToShop", From = v(-28, 0, -13), To = v(-40, 0, -19), Width = 12, Kind = "Cobble" },
	{ Id = "ToUpgrades", From = v(28, 0, -13), To = v(40, 0, -19), Width = 12, Kind = "Cobble" },
	{ Id = "ToWheel", From = v(-31, 0, 17), To = v(-41, 0, 22), Width = 7, Kind = "Cobble" },
	{ Id = "ToFossil", From = v(33, 0, 14), To = v(40, 0, 20), Width = 7, Kind = "Cobble" },
	{ Id = "ToScanner", From = v(5, 0, 80), To = v(49, 0, 80), Width = 6, Kind = "Cobble" },
	{ Id = "ToMine", From = v(-5, 0, 88), To = v(-34, 0, 88), Width = 10, Kind = "Dirt" },
	{ Id = "ToNextArea", From = v(75, 0, -115), To = v(160, 0, -115), Width = 6, Kind = "Cobble" },
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
		local d = p - plot.Center
		if math.abs(d.X) < 28 + radius and math.abs(d.Z) < 28 + radius then
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
		if LobbyLayout.isGroundPiece(piece) and LobbyLayout.distanceTo(piece, p) < radius + 1 then
			return false
		end
	end
	return true
end

return LobbyLayout
