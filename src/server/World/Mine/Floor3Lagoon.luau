--[[
	Floor 3, Deep Hollow: the Crystal Lagoon (blaster 5+, docs/plans/MINE_FLOORS_PLAN.md).

	A big blue cavern around an underground lagoon: glowing teal water over a
	neon bed, pale sand shores, two islands (Moss Isle with a mushroom grove,
	Crystal Isle in the deep part) and a crystal islet, reached by a plank
	boardwalk, an arched bridge and stepping stones. Two waterfalls pour from
	the back cliff into the lagoon; giant cyan and white crystals rise from the
	shores and out of the water and hang from the ceiling; glowing mushroom
	groves and moss in the corners; warm lanterns along the walkways.

	Layout (local studs; +Z = front where players arrive, -Z = back, "deep"):
	  entrance + blaster gate   x 0, z 49 (the Entrance marker at z 46)
	  elevator stop             front-left (-32, 42), facing the main road
	  Giant Crystal plaza       (0, 18): a round flagstone plaza, 14 studs clear
	  lagoon                    middle-back; the falls on the back cliff at x -4 / -15
	  ore lift                  east side (50, 2), a timber shaft frame up to its cable anchor
	  rock patches              front-left, front-right, west and east shores, the
	                            back corners (deep) and both islands
	Contract and budgets: MineKit's header.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local MineKit = require(World:WaitForChild("Mine"):WaitForChild("MineKit"))

local Floor = {}

Floor.Index = 3
Floor.Size = Vector3.new(136, 40, 116)

type BuildOpts = { Cutaway: boolean? }
type Ellipse = { x: number, z: number, rx: number, rz: number }
type Seg = { ax: number, az: number, bx: number, bz: number, w: number }

---------------------------------------------------------------- layout

local HX, HZ = 62, 52 -- wall lines (inner half extents)
local ROOF = 40 -- top of the ceiling slab: in the game the ground and mountains are above (world y 0)
local CEIL = ROOF - 3 -- ceiling underside
local WATER = -0.7 -- lagoon surface
local BED = -4 -- lagoon bed (the ground blocks run from here up to 0)
local DECK = 0.35 -- boardwalk top
local CELL = 2 -- ground grid
local GX, GZ = 68, 58 -- the ground runs on under the walls
local DEEP_Z = -18 -- spawns behind this line are "deep" (the back third)
local GIANT = Vector2.new(0, 18)
local ENTRANCE = Vector2.new(0, 46)
local ELEVATOR = Vector2.new(-32, 42)
-- the ramp from floor 2 (Land) comes in through the front wall: x -11..11, from about 5.6 up at
-- the front face (z 58) down to the floor at z 50; x -12..12, z 44..58 stays clear, the gate
-- stands at the ramp's foot
local OPEN_HALF = 12 -- half width of the opening in the front wall
local OPEN_TOP = 28 -- underside of the lintel (22+ over the ramp at the front face)
local GATE_Z = 49
local GATE_WIDTH = 22
-- the Mine Lift's spot (Railway builds the lift there from TrainConfig in the game)
local LIFT_SPOT = MineFloors.LiftSpots[3] or Vector3.new(50, 0, 2)
local LIFT = Vector2.new(LIFT_SPOT.X, LIFT_SPOT.Z)
local LIFT_ANCHOR = 30 -- the preview lift (Railway.buildLift outside a cave) hangs its cable from 30 up

local LAKE: { Ellipse } = {
	{ x = 0, z = -24, rx = 40, rz = 24 }, -- the main basin
	{ x = -6, z = -42, rx = 18, rz = 13 }, -- the falls pool, against the back cliff
	{ x = 16, z = -4, rx = 16, rz = 10 }, -- front-right bay
	{ x = -28, z = -8, rx = 12, rz = 9 }, -- west bay
}

local ISLANDS: { Ellipse } = {
	{ x = -18, z = -20, rx = 15, rz = 12 }, -- Moss Isle
	{ x = 18, z = -31, rx = 14, rz = 12 }, -- Crystal Isle (deep)
	{ x = -2, z = -41, rx = 4.5, rz = 4 }, -- the crystal islet before the falls
}

-- Rock spawn points (x, z) at ground height; ~9 studs apart in patches with open paths between.
local SPAWNS: { Vector2 } = {
	-- front-left
	Vector2.new(-52, 24),
	Vector2.new(-43, 27),
	Vector2.new(-34, 24),
	Vector2.new(-47, 16),
	Vector2.new(-38, 15),
	Vector2.new(-24, 21),
	-- front-right
	Vector2.new(52, 24),
	Vector2.new(43, 27),
	Vector2.new(34, 24),
	Vector2.new(47, 16),
	Vector2.new(38, 15),
	Vector2.new(24, 21),
	-- west shore
	Vector2.new(-55, 5),
	Vector2.new(-55, -4),
	Vector2.new(-55, -13),
	-- east shore
	Vector2.new(55, -12),
	Vector2.new(49, -19),
	-- back-left (deep)
	Vector2.new(-55, -26),
	Vector2.new(-48, -32),
	Vector2.new(-55, -38),
	Vector2.new(-46, -42),
	Vector2.new(-37, -44),
	-- back-right (deep)
	Vector2.new(55, -27),
	Vector2.new(55, -36),
	Vector2.new(46, -41),
	Vector2.new(37, -45),
	-- Moss Isle
	Vector2.new(-24, -15),
	Vector2.new(-25, -24),
	Vector2.new(-17, -26),
	-- Crystal Isle (deep)
	Vector2.new(12, -35),
	Vector2.new(21, -36),
}

-- Walkways kept clear of decoration (capsules: from, to, width).
local PATHS: { Seg } = {
	{ ax = 0, az = 58, bx = 0, bz = 20, w = 8 }, -- entrance to the plaza
	{ ax = 0, az = 40, bx = -27, bz = 41, w = 7 }, -- to the elevator
	{ ax = -6, az = 12, bx = -12, bz = -10, w = 7 }, -- plaza and the boardwalk to Moss Isle
	{ ax = -12, az = -10, bx = -5, bz = -22, w = 6 }, -- across Moss Isle
	{ ax = -5, az = -22, bx = 7, bz = -28, w = 6 }, -- the bridge to Crystal Isle
	{ ax = 7, az = -28, bx = 32, bz = -30, w = 6 }, -- across Crystal Isle
	{ ax = 32, az = -30, bx = 42, bz = -30, w = 5 }, -- the stepping stones
	{ ax = -8, az = 12, bx = -44, bz = 7, w = 8 }, -- plaza to the west shore
	{ ax = -44, az = 7, bx = -44, bz = -20, w = 8 }, -- west shore
	{ ax = -44, az = -20, bx = -40, bz = -30, w = 6 }, -- into the back-left corner
	{ ax = 8, az = 15, bx = 43, bz = 3, w = 8 }, -- plaza to the ore lift
	{ ax = 43, az = 3, bx = 42, bz = -30, w = 8 }, -- east shore
	{ ax = 42, az = -30, bx = 44, bz = -34, w = 6 }, -- into the back-right corner
}

local function inside(e: Ellipse, x: number, z: number, grow: number?): boolean
	local g = grow or 0
	local dx = (x - e.x) / (e.rx + g)
	local dz = (z - e.z) / (e.rz + g)
	return dx * dx + dz * dz <= 1
end

-- Is (x, z) (local studs) open lagoon water?
local function isWater(x: number, z: number): boolean
	local wet = false
	for _, e in LAKE do
		if inside(e, x, z) then
			wet = true
			break
		end
	end
	if not wet then
		return false
	end
	for _, e in ISLANDS do
		if inside(e, x, z) then
			return false
		end
	end
	return true
end

-- Is there water within `r` studs of (x, z)? (sampled on two rings)
local function waterNear(x: number, z: number, r: number): boolean
	if isWater(x, z) then
		return true
	end
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local c, s = math.cos(a), math.sin(a)
		if isWater(x + c * r, z + s * r) or isWater(x + c * r * 0.5, z + s * r * 0.5) then
			return true
		end
	end
	return false
end

-- Distance from (x, z) to the segment of a path.
local function segDistance(p: Seg, x: number, z: number): number
	local abx, abz = p.bx - p.ax, p.bz - p.az
	local len2 = abx * abx + abz * abz
	local t = if len2 > 0 then math.clamp(((x - p.ax) * abx + (z - p.az) * abz) / len2, 0, 1) else 0
	local dx, dz = x - (p.ax + abx * t), z - (p.az + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Is (x, z) clear of walkways, spawns and the plaza by `margin` studs?
local function clear(x: number, z: number, margin: number): boolean
	for _, p in PATHS do
		if segDistance(p, x, z) < p.w / 2 + margin then
			return false
		end
	end
	for _, s in SPAWNS do
		if (s - Vector2.new(x, z)).Magnitude < 3 + margin then
			return false
		end
	end
	return (GIANT - Vector2.new(x, z)).Magnitude >= 12 + margin
end

Floor.Layout = {
	Spawns = SPAWNS,
	Paths = PATHS,
	Lake = LAKE,
	Islands = ISLANDS,
	DeepZ = DEEP_Z,
	Giant = GIANT,
	Entrance = ENTRANCE,
	Elevator = ELEVATOR,
	Lift = LIFT,
	Walls = Vector2.new(HX, HZ),
	isWater = isWater,
}

---------------------------------------------------------------- look

local PAL = MineFloors.get(3).Palette
local rgb = Color3.fromRGB
local C = {
	-- walls: a deeper, greener blue than the rocks so the rocks stand out
	WallMid = rgb(76, 122, 140),
	WallLight = rgb(112, 160, 172),
	WallDark = rgb(46, 82, 102),
	Talus = rgb(134, 174, 180),
	-- ground: pale sand and stone, so the dark blue rocks pop
	Ground = rgb(200, 198, 180),
	Sand = rgb(238, 228, 192),
	StoneDark = rgb(132, 148, 156),
	Flag = rgb(204, 212, 212),
	FlagDark = rgb(172, 182, 188),
	FlagLight = rgb(230, 236, 232),
	Rim = rgb(156, 174, 180),
	Foot = rgb(196, 206, 206),
	Moss = rgb(92, 182, 110),
	MossLight = rgb(128, 204, 120),
	MossDark = rgb(56, 128, 92),
	-- the lagoon
	Bed = rgb(18, 54, 68),
	Glow = rgb(16, 104, 116),
	GlowMid = rgb(30, 160, 166),
	GlowHot = rgb(70, 214, 210),
	Water = rgb(64, 190, 204),
	WaterLight = rgb(160, 240, 246),
	Foam = rgb(236, 250, 255),
	-- mushrooms
	Stem = rgb(228, 236, 222),
	Gill = rgb(110, 232, 190),
	CapTeal = rgb(16, 122, 114),
	CapGreen = rgb(52, 140, 58),
	CapTop = rgb(120, 220, 190),
	-- crystals
	Crystal = PAL.Crystal,
	Crystal2 = PAL.Crystal2,
	-- wood and lamps
	Plank = Style.C.Plank,
	WoodDark = Style.C.WoodDark,
	WoodLight = Style.C.WoodLight,
	Lamp = Style.C.Lamp,
	PathGlow = rgb(120, 236, 255),
}

local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local BUMP = { CanTouch = false, CanQuery = false, CanCollide = true }
local DECOR = { CanTouch = false, CanQuery = false, CanCollide = false }
local TINY = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local NEON = Enum.Material.Neon
local CRYSTALS = { C.Crystal, C.Crystal2 }
local WALL_COLORS = { C.WallMid, C.WallLight, C.WallDark }

-- Ground kinds of the grid (0 = water).
local KIND_COLORS: { [number]: Color3 } = {
	[1] = C.Ground,
	[2] = C.Sand,
	[3] = C.Moss,
	[4] = C.StoneDark,
	[5] = C.Flag,
	[6] = C.FlagDark,
	[7] = C.FlagLight,
}

local function classify(x: number, z: number): number
	if isWater(x, z) then
		return 0
	end
	local plaza = (Vector2.new(x, z) - GIANT).Magnitude
	if plaza <= 5 then
		return 7
	elseif plaza <= 11 then
		return 5
	end
	if math.abs(x) <= 4 and z > GIANT.Y then
		return if math.floor(z / 4) % 2 == 0 then 5 else 6
	end
	-- sand: next to the water, or anywhere in a 4-stud block whose middle is within 5 of it
	-- (a coarser outer edge than per cell: fewer ground patches)
	if waterNear(x, z, 2) or waterNear(math.floor(x / 4) * 4 + 2, math.floor(z / 4) * 4 + 2, 5) then
		return 2
	end
	if math.abs(x) > HX - 6 or z < -HZ + 6 or z > HZ - 4 then
		return 4
	end
	if inside(ISLANDS[1], x, z) then
		return 3 -- Moss Isle
	end
	return 1
end

---------------------------------------------------------------- small builders

-- A frame at `cf.Position` whose UpVector is `dir` (crystal growth direction).
local function upFrame(position: Vector3, dir: Vector3): CFrame
	if math.abs(dir.Unit.Y) > 0.999 then
		return if dir.Y > 0 then CFrame.new(position) else CFrame.new(position) * CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.lookAt(position, position + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function lightAt(parent: Instance, cf: CFrame, color: Color3, range: number, brightness: number): Part
	local p = Geo.block(parent, cf, Vector3.new(0.4, 0.4, 0.4), color, nil, {
		Transparency = 1,
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	})
	p.Name = "LightAnchor"
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return p
end

-- A glowing mushroom: pale stem, neon gills, a faceted teal or green cap. `base` = ground point.
local function mushroom(parent: Instance, base: CFrame, h: number, cap: Color3, rng: Rng.Rng)
	local cf = base * CFrame.Angles(rng:range(-0.12, 0.12), rng:range(0, math.pi), rng:range(-0.12, 0.12))
	local sw = 0.16 * h + 0.3
	Geo.block(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(sw, h, sw), Geo.vary(C.Stem, rng, 0.04), nil, if h >= 3 then BUMP else TINY)
	local d = 0.62 * h + 1
	Geo.block(parent, cf * CFrame.new(0, h - 0.05, 0), Vector3.new(d * 0.8, 0.22, d * 0.8), C.Gill, NEON, TINY)
	Geo.block(
		parent,
		cf * CFrame.new(0, h + d * 0.12, 0),
		Vector3.new(d, d * 0.26, d),
		Geo.vary(cap, rng, 0.04),
		NEON,
		if h >= 3 then DECOR else TINY
	)
	Geo.block(
		parent,
		cf * CFrame.new(0, h + d * 0.3, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(d * 0.6, d * 0.2, d * 0.6),
		cap:Lerp(C.CapTop, 0.25),
		NEON,
		TINY
	)
end

-- A low moss carpet: a thin slab on the ground at `base`.
local function moss(parent: Instance, base: CFrame, size: number, rng: Rng.Rng)
	Geo.block(
		parent,
		base * CFrame.new(0, 0.11, 0) * CFrame.Angles(0, rng:range(0, math.pi), 0),
		Vector3.new(size, 0.12, size * rng:range(0.6, 0.9)),
		Geo.vary(C.Moss, rng, 0.04),
		nil,
		TINY
	)
end

-- A stalactite (wedge pair) with a glowing crystal tip, hanging from `top`.
local function crystalStalactite(parent: Instance, top: CFrame, h: number, w: number, rng: Rng.Rng)
	local cf = top * CFrame.Angles(math.pi, rng:range(0, math.pi), 0) * CFrame.new(0, h / 2, 0)
	Geo.wedge(parent, cf * CFrame.new(0, 0, -w / 4), Vector3.new(w, h, w / 2), Geo.vary(C.WallMid, rng, 0.05), nil, TINY)
	Geo.wedge(
		parent,
		cf * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(w, h, w / 2),
		Geo.vary(C.WallDark, rng, 0.05),
		nil,
		TINY
	)
	local color = if rng:chance(0.5) then C.Crystal else C.Crystal2
	Style.crystal(parent, top * CFrame.new(0, -h * 0.72, 0) * CFrame.Angles(math.pi, rng:range(0, 1.5), 0), h * 0.55, w * 0.42, color)
end

---------------------------------------------------------------- build

function Floor.build(parent: Instance, origin: CFrame, opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
	local cutaway = o.Cutaway == true
	local model = Instance.new("Model")
	model.Name = "MineFloor" .. Floor.Index
	model:SetAttribute("Floor", Floor.Index)

	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local function pt(x: number, y: number, z: number): Vector3
		return origin:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function dir(x: number, y: number, z: number): Vector3
		return origin:VectorToWorldSpace(Vector3.new(x, y, z))
	end
	-- a frame at local (x, y, z) facing local direction (fx, fz)
	local function facing(x: number, y: number, z: number, fx: number, fz: number): CFrame
		return origin * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + fx, y, z + fz))
	end
	local function folder(name: string): Model
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = model
		return m
	end

	---------------------------------------------------------------- ground
	local ground = folder("Ground")
	local groundRng = Rng.new(3101)
	local nx = math.floor(2 * GX / CELL)
	local nz = math.floor(2 * GZ / CELL)
	local grid: { { number } } = {}
	local used: { { boolean } } = {}
	for i = 1, nx do
		grid[i] = {}
		used[i] = {}
		local x = -GX + (i - 0.5) * CELL
		for j = 1, nz do
			grid[i][j] = classify(x, -GZ + (j - 0.5) * CELL)
			used[i][j] = false
		end
	end
	--[[
		The ground in layers (fewer parts than one block per patch of each kind):
		  the land: greedy rectangles over every dry cell, solid blocks from the bed up
		    to 0 in sand (the shores' color), the collision floor;
		  the other kinds: thin slabs just above it, no collision, one layer per entry
		    of OVERLAY. A slab of a lower layer may run on under the kinds of the layers
		    above it (they cover it), so it needs fewer, bigger rectangles.
	]]
	local OVERLAY: { { number } } = { { 1 }, { 4, 3 }, { 5 }, { 6, 7 } }
	local layerOf: { [number]: number } = {}
	for layer, kinds in OVERLAY do
		for _, k in kinds do
			layerOf[k] = layer
		end
	end
	-- greedy rectangles from each `need` cell: `need(i, j)` cells must be covered (each once),
	-- `may(i, j)` cells may be covered too
	local function rectangles(need: (number, number) -> boolean, may: (number, number) -> boolean, emit: (number, number, number, number) -> ())
		for i = 1, nx do
			for j = 1, nz do
				used[i][j] = false
			end
		end
		local function ok(ii: number, jj: number): boolean
			return (need(ii, jj) and not used[ii][jj]) or may(ii, jj)
		end
		for j = 1, nz do
			for i = 1, nx do
				if need(i, j) and not used[i][j] then
					local w = 1
					while i + w <= nx and ok(i + w, j) do
						w += 1
					end
					local h = 1
					local grow = true
					while grow and j + h <= nz do
						for ii = i, i + w - 1 do
							if not ok(ii, j + h) then
								grow = false
								break
							end
						end
						if grow then
							h += 1
						end
					end
					for ii = i, i + w - 1 do
						for jj = j, j + h - 1 do
							used[ii][jj] = true
						end
					end
					emit(i, j, w, h)
				end
			end
		end
	end
	local function never(_i: number, _j: number): boolean
		return false
	end
	rectangles(function(i: number, j: number): boolean
		return grid[i][j] ~= 0
	end, never, function(i: number, j: number, w: number, h: number)
		local sx, sz = w * CELL, h * CELL
		local x0, z0 = -GX + (i - 1) * CELL, -GZ + (j - 1) * CELL
		local tile = Geo.block(ground, at(x0 + sx / 2, BED / 2, z0 + sz / 2), Vector3.new(sx, -BED, sz), Geo.vary(C.Sand, groundRng, 0.025), nil, SOLID)
		tile.Name = "Ground"
	end)
	for layer, kinds in OVERLAY do
		local top = 0.02 * layer
		for _, k in kinds do
			rectangles(function(i: number, j: number): boolean
				return grid[i][j] == k
			end, function(i: number, j: number): boolean
				local above = layerOf[grid[i][j]]
				return above ~= nil and above > layer
			end, function(i: number, j: number, w: number, h: number)
				local sx, sz = w * CELL, h * CELL
				local x0, z0 = -GX + (i - 1) * CELL, -GZ + (j - 1) * CELL
				local slab = Geo.block(ground, at(x0 + sx / 2, top - 0.1, z0 + sz / 2), Vector3.new(sx, 0.2, sz), Geo.vary(KIND_COLORS[k], groundRng, 0.025), nil, TINY)
				slab.Name = "GroundPatch"
			end)
		end
	end
	Geo.block(ground, at(0, BED - 0.5, 0), Vector3.new(GX * 2, 1, GZ * 2), C.Bed, nil, SOLID).Name = "LagoonBed"

	-- shore stones along the waterline (not where the walkways land)
	local landings = {
		Vector2.new(-10, 0),
		Vector2.new(-12, -10),
		Vector2.new(-4, -22),
		Vector2.new(5, -28),
		Vector2.new(32, -30),
		Vector2.new(38.5, -30),
	}
	local rims = folder("ShoreStones")
	local rimRng = Rng.new(3102)
	for i = 2, nx - 1 do
		for j = 2, nz - 1 do
			if grid[i][j] ~= 0 then
				local toWater: Vector2? = nil
				if grid[i + 1][j] == 0 then
					toWater = Vector2.new(1, 0)
				elseif grid[i - 1][j] == 0 then
					toWater = Vector2.new(-1, 0)
				elseif grid[i][j + 1] == 0 then
					toWater = Vector2.new(0, 1)
				elseif grid[i][j - 1] == 0 then
					toWater = Vector2.new(0, -1)
				end
				if toWater and rimRng:chance(0.11) then
					local x = -GX + (i - 0.5) * CELL + toWater.X * 0.9
					local z = -GZ + (j - 0.5) * CELL + toWater.Y * 0.9
					local nearLanding = false
					for _, l in landings do
						if (l - Vector2.new(x, z)).Magnitude < 5.5 then
							nearLanding = true
							break
						end
					end
					if not nearLanding then
						local s = rimRng:range(1.5, 2.7)
						local hgt = rimRng:range(1.4, 2.2)
						local top = rimRng:range(0.05, 0.55)
						local cf = at(x, top - hgt / 2, z)
							* CFrame.Angles(rimRng:range(-0.1, 0.1), rimRng:range(0, math.pi), rimRng:range(-0.1, 0.1))
						Geo.block(rims, cf, Vector3.new(s, hgt, s * rimRng:range(0.7, 1)), Geo.vary(C.Rim, rimRng, 0.06), nil, BUMP)
						if rimRng:chance(0.3) then
							Geo.block(
								rims,
								cf * CFrame.new(0, hgt / 2 + 0.06, 0),
								Vector3.new(s * 0.8, 0.14, s * 0.7),
								Geo.vary(C.Moss, rimRng, 0.05),
								nil,
								TINY
							)
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- the lagoon
	local lagoon = folder("Lagoon")
	-- glow on the bed: a deep teal sheet, brighter cores in every basin
	Geo.block(lagoon, at(0, BED + 0.1, -24), Vector3.new(84, 0.2, 64), C.Glow, NEON, TINY).Name = "LagoonGlow"
	for _, e in LAKE do
		Geo.block(lagoon, at(e.x, BED + 0.25, e.z), Vector3.new(e.rx * 1.2, 0.2, e.rz * 1.2), C.GlowMid, NEON, TINY).Name = "LagoonGlow"
		Geo.block(lagoon, at(e.x, BED + 0.4, e.z), Vector3.new(e.rx * 0.55, 0.2, e.rz * 0.55), C.GlowHot, NEON, TINY).Name = "LagoonGlow"
	end
	local water = Geo.block(lagoon, at(0, WATER - 0.2, -24), Vector3.new(84, 0.4, 64), C.Water, nil, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
		Transparency = 0.38,
		Reflectance = 0.12,
	})
	water.Name = "Water"
	-- glints on the surface
	local glintRng = Rng.new(3103)
	local glints = 0
	for _ = 1, 80 do
		if glints >= 6 then
			break
		end
		local x, z = glintRng:range(-38, 38), glintRng:range(-50, 4)
		if isWater(x, z) and isWater(x + 3, z) and isWater(x - 3, z) and isWater(x, z + 2) and isWater(x, z - 2) then
			glints += 1
			Geo.block(
				lagoon,
				at(x, WATER + 0.03, z) * CFrame.Angles(0, glintRng:range(-0.3, 0.3), 0),
				Vector3.new(glintRng:range(1.5, 4), 0.06, 0.25),
				C.WaterLight,
				NEON,
				{
					CanTouch = false,
					CanQuery = false,
					CanCollide = false,
					CastShadow = false,
					Transparency = 0.35,
				}
			)
		end
	end
	-- glowing lily pads
	local padRng = Rng.new(3104)
	local pads = 0
	for _ = 1, 60 do
		if pads >= 5 then
			break
		end
		local x, z = padRng:range(-36, 36), padRng:range(-46, 4)
		if isWater(x, z) and isWater(x + 2.5, z + 2.5) and isWater(x - 2.5, z - 2.5) and clear(x, z, 0) then
			pads += 1
			local d = padRng:range(1.6, 2.6)
			local pad = Geo.cylinder(lagoon, pt(x, WATER + 0.08, z), 0.12, d, Geo.vary(C.MossLight, padRng, 0.05), nil, TINY)
			pad.Name = "LilyPad"
			if padRng:chance(0.6) then
				Geo.block(lagoon, at(x + d * 0.15, WATER + 0.35, z), Vector3.new(0.5, 0.45, 0.5), C.Gill, NEON, TINY)
			end
		end
	end
	-- light rising from the water onto the shores and islands
	for _, p in { Vector3.new(-4, 1.5, -30), Vector3.new(-30, 1.5, -32) } do
		lightAt(lagoon, at(p.X, p.Y, p.Z), rgb(100, 232, 226), 32, 1.5)
	end
	local sparkle = Geo.block(lagoon, at(0, 1.2, -14), Vector3.new(30, 0.4, 20), C.Water, nil, {
		Transparency = 1,
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	})
	sparkle.Name = "LagoonSparkle"
	Style.emitter(sparkle, "Sparkle", C.WaterLight, 6)

	---------------------------------------------------------------- walls
	local walls = folder("Walls")
	local wallRng = Rng.new(3105)
	local wallOpts = { Depth = 4, Step = 8 } -- (shards stay inside the floor's world box)
	local farWallOpts = { Depth = 4, Step = 9 } -- the back (behind the lagoon) and the front (behind the arrivals)
	local wallH = ROOF - 1 -- (tilted shard tops stay under the roof)
	MineKit.wall(walls, pt(-HX, 0, HZ), pt(-HX, 0, -HZ), wallH, dir(1, 0, 0), WALL_COLORS, wallRng, wallOpts)
	MineKit.wall(walls, pt(HX, 0, -HZ), pt(HX, 0, HZ), wallH, dir(-1, 0, 0), WALL_COLORS, wallRng, wallOpts)
	MineKit.wall(walls, pt(-HX, 0, -HZ), pt(-22, 0, -HZ), wallH, dir(0, 0, 1), WALL_COLORS, wallRng, farWallOpts)
	MineKit.wall(walls, pt(6, 0, -HZ), pt(HX, 0, -HZ), wallH, dir(0, 0, 1), WALL_COLORS, wallRng, farWallOpts)
	-- backing slabs fill every gap between the jagged shards and the ceiling
	Geo.block(walls, at(-HX - 4.5, ROOF / 2, 0), Vector3.new(3, ROOF, HZ * 2 + 12), C.WallDark, nil, SOLID)
	Geo.block(walls, at(HX + 4.5, ROOF / 2, 0), Vector3.new(3, ROOF, HZ * 2 + 12), C.WallDark, nil, SOLID)
	Geo.block(walls, at(0, ROOF / 2, -HZ - 4.5), Vector3.new(HX * 2 + 12, ROOF, 3), C.WallDark, nil, SOLID)
	if not cutaway then
		-- the front wall with the opening for the ramp from floor 2: jambs at x +-12, a lintel at OPEN_TOP
		local side = OPEN_HALF + 2.5
		MineKit.wall(walls, pt(HX, 0, HZ), pt(side, 0, HZ), wallH, dir(0, 0, -1), WALL_COLORS, wallRng, farWallOpts)
		MineKit.wall(walls, pt(-side, 0, HZ), pt(-HX, 0, HZ), wallH, dir(0, 0, -1), WALL_COLORS, wallRng, farWallOpts)
		local backW = HX + 6 - OPEN_HALF
		for _, sx in { -1, 1 } do
			Geo.block(walls, at(sx * (OPEN_HALF + backW / 2), ROOF / 2, HZ + 4.5), Vector3.new(backW, ROOF, 3), C.WallDark, nil, SOLID)
			Geo.block(walls, at(sx * (OPEN_HALF + 1.5), OPEN_TOP / 2, HZ + 3), Vector3.new(3, OPEN_TOP, 6), C.WallDark, nil, SOLID)
		end
		Geo.block(walls, at(0, (OPEN_TOP + ROOF) / 2, HZ + 3), Vector3.new(OPEN_HALF * 2 + 5, ROOF - OPEN_TOP, 6), C.WallMid, nil, SOLID)
		Geo.block(walls, at(0, OPEN_TOP + 0.5, HZ - 0.2), Vector3.new(OPEN_HALF * 2 + 3, 0.8, 0.8), C.WallLight, nil, TINY)
	end

	-- a band of lighter, mossy fallen stones at the foot of the walls (smaller next to spawns)
	local talus = folder("Talus")
	local talusRng = Rng.new(3113)
	local function talusRow(from: Vector2, to: Vector2, face: Vector2)
		local along = to - from
		local len = along.Magnitude
		local d = along.Unit
		local n = math.max(1, math.floor(len / 12))
		for k = 0, n - 1 do
			local p = from + d * ((k + talusRng:range(0.25, 0.75)) * len / n)
			local near = false
			for _, sp in SPAWNS do
				if (sp - p).Magnitude < 9 then
					near = true
					break
				end
			end
			local depth = if near then 1.8 else talusRng:range(2.6, 3.8)
			local h = talusRng:range(2.4, if near then 4 else 7.5)
			local w = talusRng:range(4.5, 7)
			local c = p + face * (depth / 2 + 0.2)
			local cf = facing(c.X, h / 2 - 0.3, c.Y, face.X, face.Y)
				* CFrame.Angles(talusRng:range(-0.08, 0.04), talusRng:range(-0.25, 0.25), talusRng:range(-0.06, 0.06))
			Geo.block(talus, cf, Vector3.new(w, h, depth), Geo.vary(C.Talus, talusRng, 0.07), nil, BUMP)
			if talusRng:chance(0.15) then
				Geo.block(
					talus,
					cf * CFrame.new(0, h / 2 + 0.07, 0),
					Vector3.new(w * 0.85, 0.14, depth * 0.8),
					Geo.vary(C.Moss, talusRng, 0.05),
					nil,
					TINY
				)
			end
		end
	end
	talusRow(Vector2.new(-HX, HZ - 2), Vector2.new(-HX, -HZ + 2), Vector2.new(1, 0))
	talusRow(Vector2.new(HX, -HZ + 2), Vector2.new(HX, HZ - 2), Vector2.new(-1, 0))
	talusRow(Vector2.new(-HX + 2, -HZ), Vector2.new(-23, -HZ), Vector2.new(0, 1))
	talusRow(Vector2.new(7, -HZ), Vector2.new(HX - 2, -HZ), Vector2.new(0, 1))
	if not cutaway then
		talusRow(Vector2.new(HX - 2, HZ), Vector2.new(OPEN_HALF + 4, HZ), Vector2.new(0, -1))
		talusRow(Vector2.new(-OPEN_HALF - 4, HZ), Vector2.new(-HX + 2, HZ), Vector2.new(0, -1))
	end

	-- moss drapes with glowing berries hanging down the wall faces
	local drapeRng = Rng.new(3114)
	local drapes = 0
	for _ = 1, 80 do
		if drapes >= 6 then
			break
		end
		local side = drapeRng:int(1, 3)
		local x, z, fx, fz
		if side == 1 then
			x, z, fx, fz = -HX + 0.35, drapeRng:range(-HZ + 4, HZ - 6), 1, 0
		elseif side == 2 then
			x, z, fx, fz = HX - 0.35, drapeRng:range(-HZ + 4, HZ - 6), -1, 0
		else
			x, z, fx, fz = drapeRng:range(-HX + 4, HX - 4), -HZ + 0.35, 0, 1
		end
		local inCliff = side == 3 and x > -26 and x < 10
		local atLift = side == 2 and math.abs(z - LIFT.Y) < 8
		if not inCliff and not atLift then
			drapes += 1
			local top = drapeRng:range(16, 32)
			local len = drapeRng:range(4, 11)
			local w = drapeRng:range(1.2, 2.6)
			local cf = facing(x, top - len / 2, z, fx, fz)
			Geo.block(
				walls,
				cf,
				Vector3.new(w, len, 0.3),
				Geo.vary(if drapes % 2 == 0 then C.MossDark else C.Moss, drapeRng, 0.05),
				nil,
				TINY
			)
			Geo.block(
				walls,
				cf * CFrame.new(drapeRng:range(-0.3, 0.3) * w, -len / 2 - 0.8, -0.05),
				Vector3.new(w * 0.5, 1.8, 0.25),
				Geo.vary(C.MossLight, drapeRng, 0.05),
				nil,
				TINY
			)
			if drapes % 2 == 1 then
				Geo.block(walls, cf * CFrame.new(0, -len / 2 - 1.9, -0.2), Vector3.new(0.45, 0.45, 0.45), C.Gill, NEON, TINY)
			end
		end
	end

	-- the back cliff the falls pour from
	local cliff = folder("FallsCliff")
	local cliffRng = Rng.new(3106)
	Geo.block(cliff, at(-8, (BED + ROOF) / 2, -55.5), Vector3.new(30, ROOF - BED, 5), C.WallMid, nil, SOLID)
	for _, s in { { -20.5, 30, 3.4 }, { -17, 16, 2.6 }, { 4.5, 34, 3.2 }, { 1.5, 12, 2.2 }, { -21, 38, 2 }, { 5, ROOF, 2 } } do
		local x, h, d = s[1], s[2], s[3]
		local cf = at(x, (h + BED) / 2, -53 + d / 2 - 0.4) * CFrame.Angles(0, cliffRng:range(-0.15, 0.15), cliffRng:range(-0.04, 0.04))
		Geo.block(
			cliff,
			cf,
			Vector3.new(cliffRng:range(3, 4.5), h - BED, d),
			Geo.vary(if h > 30 then C.WallDark else C.WallLight, cliffRng, 0.05),
			nil,
			SOLID
		)
	end
	-- lip ledges of the two falls, mossy on top, with crystals
	local lips = { { -4, 28, 16, 10 }, { -15, 20.5, 8, 5 } }
	for _, l in lips do
		local x, y, w = l[1], l[2], l[3]
		-- the shelf, a corbel wedge under it into the cliff and a crag stacked on top
		Geo.block(cliff, at(x, y + 1.5, -51.6), Vector3.new(w, 3, 3.6), Geo.vary(C.WallLight, cliffRng, 0.04), nil, SOLID)
		Geo.wedge(
			cliff,
			facing(x, y - 1.6, -51.6, 0, 1) * CFrame.Angles(0, 0, math.pi),
			Vector3.new(w * 0.86, 3.2, 3.2),
			Geo.vary(C.WallMid, cliffRng, 0.04),
			nil,
			SOLID
		)
		Geo.block(cliff, at(x + w * 0.08, y + 3.1, -51.8), Vector3.new(w * 0.9, 0.3, 3.2), Geo.vary(C.Moss, cliffRng, 0.04), nil, TINY)
		Geo.block(
			cliff,
			at(x - w * 0.12, y + 5.5, -52) * CFrame.Angles(0, 0, cliffRng:range(-0.06, 0.06)),
			Vector3.new(w * 0.72, 5, 2.4),
			Geo.vary(C.WallMid, cliffRng, 0.05),
			nil,
			SOLID
		)
		Geo.block(cliff, at(x + w * 0.3, y + 4.4, -51.4), Vector3.new(w * 0.3, 2.8, 1.6), Geo.vary(C.WallLight, cliffRng, 0.05), nil, TINY)
	end
	local falls = folder("Falls")
	local fallsRng = Rng.new(3107)
	for _, l in lips do
		local x, y, width = l[1], l[2], l[4]
		local top = facing(x, y, -49.7, 0, 1)
		Style.waterfall(falls, top, y - (WATER - 0.3), width, fallsRng, { Foam = true, Mist = false })
		local mist = Geo.block(falls, at(x, WATER + 1.4, -47.6), Vector3.new(width + 5, 2.6, 6), C.Foam, nil, {
			CanTouch = false,
			CanQuery = false,
			CanCollide = false,
			CastShadow = false,
			Transparency = 0.72,
		})
		mist.Name = "Mist"
		Style.emitter(mist, "Sparkle", C.WaterLight, 5)
	end
	lightAt(falls, at(-9, 4, -46), rgb(170, 240, 255), 30, 1.4)
	MineKit.crystals(cliff, upFrame(pt(3, 31.2, -51.4), dir(0.3, 1, 0.3)), 3, 3.6, "Shell", CRYSTALS, 31071)
	MineKit.crystals(cliff, upFrame(pt(-18.5, 23.6, -51), dir(-0.3, 1, 0.2)), 2, 3, "Shell", CRYSTALS, 31072)

	-- a timber shaft frame on top of the ore lift up to its cable anchor (LIFT_ANCHOR),
	-- braced back to the east wall
	local shaft = folder("LiftShaft")
	local shaftRng = Rng.new(3108)
	local half = 4.2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Geo.block(
				shaft,
				at(LIFT.X + sx * half, (15.2 + LIFT_ANCHOR + 1.2) / 2, LIFT.Y + sz * half),
				Vector3.new(0.8, LIFT_ANCHOR + 1.2 - 15.2, 0.8),
				Geo.vary(C.WoodDark, shaftRng, 0.04),
				nil,
				DECOR
			)
		end
	end
	for _, sz in { -1, 1 } do
		Geo.block(shaft, at(LIFT.X, LIFT_ANCHOR + 0.8, LIFT.Y + sz * half), Vector3.new(half * 2 + 1.2, 0.8, 0.9), C.WoodDark, nil, DECOR)
		Geo.block(shaft, at(LIFT.X, 22.5, LIFT.Y + sz * half), Vector3.new(half * 2 + 0.8, 0.6, 0.6), C.WoodLight, nil, TINY)
	end
	for _, sx in { -1, 1 } do
		Geo.block(shaft, at(LIFT.X + sx * half, LIFT_ANCHOR + 0.8, LIFT.Y), Vector3.new(0.9, 0.8, half * 2 + 1.2), C.WoodDark, nil, DECOR)
	end
	-- the head plate the cable anchor hangs from, a pulley and the beams into the wall
	Geo.block(shaft, at(LIFT.X, LIFT_ANCHOR + 0.5, LIFT.Y), Vector3.new(3.4, 1, 3.4), C.WoodDark, nil, DECOR)
	Geo.block(shaft, at(LIFT.X, LIFT_ANCHOR + 2.6, LIFT.Y), Vector3.new(0.6, 3.4, 3.4), Style.C.Hazard, Enum.Material.Metal, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	for _, sz in { -1, 1 } do
		local x0 = LIFT.X + half
		Geo.block(
			shaft,
			at((x0 + HX + 2) / 2, LIFT_ANCHOR + 0.8, LIFT.Y + sz * half),
			Vector3.new(HX + 2 - x0, 0.9, 0.9),
			C.WoodDark,
			nil,
			DECOR
		)
	end
	Geo.block(
		shaft,
		at(HX - 0.5, LIFT_ANCHOR + 0.8, LIFT.Y),
		Vector3.new(3, 3, half * 2 + 3),
		Geo.vary(C.WallDark, shaftRng, 0.04),
		nil,
		DECOR
	)

	---------------------------------------------------------------- ceiling
	local ceiling = folder("Ceiling")
	local ceilRng = Rng.new(3109)
	local front = if cutaway then 0 else GZ
	Geo.block(ceiling, at(0, CEIL + 1.5, (front - GZ) / 2), Vector3.new(GX * 2, 3, front + GZ), C.WallMid, nil, SOLID)
	-- rock lumps under the ceiling
	for _ = 1, if cutaway then 5 else 6 do
		local x, z = ceilRng:range(-54, 54), ceilRng:range(-48, front - 8)
		local s = ceilRng:range(8, 16)
		local h = ceilRng:range(2, 5)
		Geo.block(
			ceiling,
			at(x, CEIL - h / 2 + 0.5, z) * CFrame.Angles(0, ceilRng:range(0, math.pi), 0),
			Vector3.new(s, h, s * ceilRng:range(0.6, 1)),
			Geo.vary(C.WallLight, ceilRng, 0.05),
			nil,
			DECOR
		)
	end
	MineKit.stalactites(ceiling, pt(0, CEIL, -26), Vector2.new(116, 46), WALL_COLORS, ceilRng, 8)
	if not cutaway then
		MineKit.stalactites(ceiling, pt(0, CEIL, 26), Vector2.new(116, 46), WALL_COLORS, ceilRng, 4)
	end
	for _ = 1, 3 do
		local x, z = ceilRng:range(-50, 50), ceilRng:range(-48, if cutaway then -4 else 44)
		crystalStalactite(ceiling, at(x, CEIL, z), ceilRng:range(4, 8), ceilRng:range(1.4, 2.4), ceilRng)
	end
	-- giant crystals hanging over the lagoon
	local hanging = { { -12, -30, 9, 5 }, { 22, -16, 7, 4 }, { 36, -42, 7, 4 }, { -30, -12, 6, 4 } }
	for i, hc in hanging do
		local x, z, h, n = hc[1], hc[2], hc[3], hc[4]
		Geo.block(
			ceiling,
			at(x, CEIL - 1.2, z) * CFrame.Angles(0, i, 0),
			Vector3.new(h * 0.9, 3, h * 0.8),
			Geo.vary(C.WallLight, ceilRng, 0.05),
			nil,
			DECOR
		)
		Geo.block(
			ceiling,
			at(x, CEIL - 2.6, z) * CFrame.Angles(0, i + 0.8, 0),
			Vector3.new(h * 0.45, 1.4, h * 0.45),
			Geo.vary(C.WallMid, ceilRng, 0.05),
			nil,
			DECOR
		)
		MineKit.crystals(ceiling, upFrame(pt(x, CEIL - 3, z), dir(0, -1, 0)), n, h, "Shell", CRYSTALS, 31090 + i)
	end

	---------------------------------------------------------------- crystals
	local crystals = folder("Crystals")
	local crystalRng = Rng.new(3110)
	-- giants: x, z, foot height (BED = rising out of the lagoon), height, count, light (1/0), sparkle (1/0)
	local giants: { { number } } = {
		{ -27, -47, 0, 13, 4, 1, 1 },
		{ 13, -48, 0, 11, 3, 1, 1 },
		{ -2, -41, 0, 12, 4, 1, 1 },
		{ 32, -20, BED, 13, 3, 1, 0 },
		{ 24, 0, BED, 11, 3, 1, 0 },
		{ 10, -14, BED, 10, 3, 1, 0 },
		{ -20, -36, BED, 10, 3, 0, 0 },
	}
	for i, g in giants do
		local x, z, y0, h, n = g[1], g[2], g[3], g[4], g[5]
		local root = at(x, y0, z) * CFrame.Angles(0, i * 1.7, 0)
		if y0 >= 0 then
			-- a foot of pale stones the crystals grow out of
			for k = 1, 3 do
				local a = k / 3 * math.pi * 2 + i
				local s = h * crystalRng:range(0.13, 0.19)
				Geo.block(
					crystals,
					root
						* CFrame.new(math.cos(a) * h * 0.12, s * 0.2, math.sin(a) * h * 0.12)
						* CFrame.Angles(crystalRng:range(-0.2, 0.2), a, crystalRng:range(-0.2, 0.2)),
					Vector3.new(s, s * 0.6, s),
					Geo.vary(C.Foot, crystalRng, 0.05),
					nil,
					BUMP
				)
			end
		end
		MineKit.crystals(
			crystals,
			root * CFrame.new(0, 0.3, 0),
			n,
			h,
			"Shell",
			if i % 2 == 0 then { C.Crystal2, C.Crystal } else CRYSTALS,
			31100 + i
		)
		if g[6] == 1 then
			local anchor =
				lightAt(crystals, at(x, y0 + h * 0.55, z), C.Crystal:Lerp(Color3.new(1, 1, 1), 0.3), math.clamp(h * 2.6, 20, 32), 1.7)
			if g[7] == 1 then
				Style.emitter(anchor, "Sparkle", C.Crystal2, 4)
			end
		end
	end
	-- small clusters along the walls and shores
	local placed = 0
	for _ = 1, 120 do
		if placed >= 1 then
			break
		end
		local x, z = crystalRng:range(-HX + 4, HX - 4), crystalRng:range(-HZ + 4, HZ - 6)
		local nearWall = math.abs(x) > HX - 10 or z < -HZ + 10
		local nearWater = waterNear(x, z, 4) and not isWater(x, z)
		if
			nearWall
			and not nearWater
			and not isWater(x, z)
			and clear(x, z, 3)
			and (Vector2.new(x, z) - ELEVATOR).Magnitude > 9
			and (Vector2.new(x, z) - LIFT).Magnitude > 9
		then
			placed += 1
			local h = crystalRng:range(1.8, 3.6)
			MineKit.crystals(
				crystals,
				at(x, 0, z) * CFrame.Angles(0, crystalRng:range(0, math.pi * 2), 0),
				crystalRng:int(3, 4),
				h,
				"Shell",
				if placed % 2 == 0 then { C.Crystal2, C.Crystal } else CRYSTALS,
				31200 + placed
			)
		end
	end
	-- crystals growing out of the walls: x, y, z, out (x, z), light (1/0), crystals (1/0)
	-- (the lit spots glow over the rock patches next to them; two keep only their light)
	local wallSpots: { { number } } = {
		{ -HX + 0.6, 10, 22, 1, 0, 1, 1 },
		{ HX - 0.6, 11, 22, -1, 0, 1, 0 },
		{ -44, 12, -HZ + 0.6, 0, 1, 1, 1 },
		{ 46, 9, -HZ + 0.6, 0, 1, 1, 1 },
	}
	for i, w in wallSpots do
		local x, y, z, fx, fz = w[1], w[2], w[3], w[4], w[5]
		if w[7] == 1 then
			MineKit.crystals(crystals, upFrame(pt(x, y, z), dir(fx, 0.9, fz)), 3, 3.8, "Shell", CRYSTALS, 31300 + i)
		end
		if w[6] == 1 then
			lightAt(crystals, at(x + fx * 3, y + 2, z + fz * 3), rgb(196, 240, 255), 34, 1.8)
		end
	end

	---------------------------------------------------------------- walkways
	local walk = folder("Walkways")
	local walkRng = Rng.new(3111)
	-- the plank boardwalk from the front shore out to Moss Isle
	do
		local a, b = Vector3.new(-10, DECK, 2.5), Vector3.new(-12, DECK, -11.5)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = origin * CFrame.lookAt(mid, b)
		Style.planks(walk, cf, Vector3.new(7, 0.5, len), walkRng, { Color = C.Plank })
		local n = math.floor(len / 4)
		for k = 0, n do
			local t = -len / 2 + 1 + k * (len - 2) / n
			for _, sx in { -1, 1 } do
				local postH = DECK - BED + 1.4
				Geo.block(
					walk,
					cf * CFrame.new(sx * 3.2, -postH / 2 + 1.4, t),
					Vector3.new(0.6, postH, 0.6),
					Geo.vary(C.WoodDark, walkRng, 0.04),
					nil,
					BUMP
				)
			end
		end
		for _, sx in { -1, 1 } do
			Geo.block(walk, cf * CFrame.new(sx * 3.2, 1.25, 0), Vector3.new(0.35, 0.3, len - 1.5), C.WoodLight, nil, DECOR)
		end
		Style.lantern(walk, facing(-14.6, 0, 1.5, 1, 0), { Kind = "Post", Light = true, Color = C.Lamp, Range = 18, Brightness = 1.2 })
		Style.lantern(walk, facing(-16.5, 0, -12.5, 1, 0), { Kind = "Post", Light = true, Color = C.Lamp, Range = 18, Brightness = 1.2 })
	end
	-- the arched bridge from Moss Isle to Crystal Isle
	do
		local a, b = pt(-5, 0, -22), pt(7, 0, -28)
		Style.archBridge(walk, a, b, 6, 2.2, walkRng, {})
		Style.lantern(walk, facing(-7, 0, -18, 1, -0.5), { Kind = "Post", Light = true, Color = C.Lamp, Range = 18, Brightness = 1.2 })
		Style.lantern(walk, facing(9, 0, -32, -1, 0.5), { Kind = "Post", Light = true, Color = C.Lamp, Range = 18, Brightness = 1.2 })
	end
	-- stepping stones from Crystal Isle to the east shore
	local stones = { { 33.6, -30.2 }, { 36.9, -29.7 } }
	for i, s in stones do
		local x, z = s[1], s[2]
		local top = 0.15
		local cf = at(x, (top + BED) / 2, z) * CFrame.Angles(0, walkRng:range(0, math.pi), 0)
		Geo.block(walk, cf, Vector3.new(2.9, top - BED, 2.7), Geo.vary(C.Rim, walkRng, 0.05), nil, SOLID)
		if i % 2 == 1 then
			Geo.block(
				walk,
				cf * CFrame.new(0.2, (top - BED) / 2 + 0.06, 0.1),
				Vector3.new(2, 0.12, 1.8),
				Geo.vary(C.Moss, walkRng, 0.04),
				nil,
				TINY
			)
		end
	end
	-- glowing guide stones along the main road
	for _, z in { 36, 27 } do
		for _, sx in { -1, 1 } do
			Style.lantern(walk, at(sx * 5.4, 0, z), { Kind = "Ground", Color = C.PathGlow })
		end
	end
	-- warm lanterns (glow only, no light) where the side paths leave the plaza
	for _, l in { { -26, 13.5, 0, -1 }, { 26, 14.2, 0, -1 } } do
		Style.lantern(walk, facing(l[1], 0, l[2], l[3], l[4]), { Kind = "Post", Color = C.Lamp, Height = 6 })
	end
	-- warm pillar lanterns beside the gate (outside the ramp's clear box)
	for _, sx in { -1, 1 } do
		Style.lantern(
			walk,
			facing(sx * (OPEN_HALF + 4), 0, GATE_Z - 1.5, 0, 1),
			{ Kind = "Pillar", Light = true, Color = C.Lamp, Range = 20, Brightness = 1.3, Height = 4 }
		)
	end
	-- the Giant Crystal plaza: a ring of low crystal posts at its rim
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + math.pi / 8
		local x, z = GIANT.X + math.cos(a) * 15, GIANT.Y + math.sin(a) * 15
		local onPath = false
		for _, p in PATHS do
			if segDistance(p, x, z) < p.w / 2 + 1 then
				onPath = true
			end
		end
		if not onPath and not isWater(x, z) then
			Geo.block(
				walk,
				at(x, 0.4, z) * CFrame.Angles(0, a, 0),
				Vector3.new(1.8, 0.8, 1.8),
				Geo.vary(C.WallLight, walkRng, 0.04),
				nil,
				BUMP
			)
			Style.crystal(walk, at(x, 0.7, z) * CFrame.Angles(0, a, 0), 2.6, 0.8, if k % 2 == 0 then C.Crystal else C.Crystal2)
		end
	end

	---------------------------------------------------------------- mushrooms and moss
	local flora = folder("Flora")
	local floraRng = Rng.new(3112)
	-- groves: x, z, radius, big, small, light (1/0)
	local groves: { { number } } = {
		{ 53, 44, 6, 3, 2, 0 },
		{ -56, -48, 4, 2, 1, 1 },
		{ 56, -48, 4, 2, 1, 1 },
		{ -11, -27, 2.5, 1, 1, 0 },
		{ -56, 44, 4, 2, 1, 0 },
	}
	for gi, g in groves do
		local cx, cz, radius = g[1], g[2], g[3]
		local big, small = g[4], g[5]
		moss(flora, at(cx, 0, cz), radius * 2.2, floraRng)
		for k = 1, big do
			local a = k / big * math.pi * 2 + floraRng:range(-0.4, 0.4)
			local r = if k == 1 then 0 else floraRng:range(0.4, 1) * radius
			local mx, mz = cx + math.cos(a) * r, cz + math.sin(a) * r
			if not waterNear(mx, mz, 2) then
				mushroom(flora, at(mx, 0, mz), floraRng:range(3.2, 7), if k % 2 == 0 then C.CapGreen else C.CapTeal, floraRng)
			end
		end
		for _ = 1, small do
			local a = floraRng:range(0, math.pi * 2)
			local r = floraRng:range(0.6, 1.4) * radius
			local mx, mz = cx + math.cos(a) * r, cz + math.sin(a) * r
			if not waterNear(mx, mz, 1) then
				mushroom(flora, at(mx, 0, mz), floraRng:range(0.9, 2), if floraRng:chance(0.5) then C.CapGreen else C.CapTeal, floraRng)
			end
		end
		if g[6] == 1 then
			lightAt(flora, at(cx, 4, cz), rgb(110, 240, 170), 20, 1.2)
		end
		if gi == 1 then
			local spores = Geo.block(flora, at(cx, 3, cz), Vector3.new(6, 2, 6), C.Gill, nil, {
				Transparency = 1,
				CanTouch = false,
				CanQuery = false,
				CanCollide = false,
				CastShadow = false,
			})
			spores.Name = "Spores"
			Style.emitter(spores, "Sparkle", C.Gill, 4)
		end
	end
	-- single small mushrooms and moss carpets scattered along the walls and shores
	local scattered = 0
	for _ = 1, 160 do
		if scattered >= 2 then
			break
		end
		local x, z = floraRng:range(-HX + 4, HX - 4), floraRng:range(-HZ + 4, HZ - 4)
		if
			not waterNear(x, z, 1.5)
			and clear(x, z, 1.5)
			and (Vector2.new(x, z) - ELEVATOR).Magnitude > 8
			and (Vector2.new(x, z) - LIFT).Magnitude > 8
		then
			scattered += 1
			if scattered % 3 == 0 then
				moss(flora, at(x, 0, z), floraRng:range(2.5, 4.5), floraRng)
			else
				mushroom(flora, at(x, 0, z), floraRng:range(0.9, 2.2), if floraRng:chance(0.5) then C.CapGreen else C.CapTeal, floraRng)
			end
		end
	end

	---------------------------------------------------------------- gameplay pieces
	local spawns = MineKit.spawns(model)
	for _, s in SPAWNS do
		spawns.add(at(s.X, 0, s.Y), s.Y <= DEEP_Z)
	end
	MineKit.marker(model, "GiantSpawn", at(GIANT.X, 0, GIANT.Y))
	MineKit.marker(model, "Entrance", facing(ENTRANCE.X, 0, ENTRANCE.Y, 0, -1))
	MineKit.gate(model, facing(0, 0, GATE_Z, 0, 1), GATE_WIDTH, MineFloors.get(3).MinBlaster, { PAL.Mid, PAL.Light, PAL.Dark })
	MineKit.elevator(model, facing(ELEVATOR.X, 0, ELEVATOR.Y, 1, 0), Floor.Index)
	MineKit.oreLift(model, origin:PointToWorldSpace(LIFT_SPOT), "Floor3")

	---------------------------------------------------------------- ambience (Config/MineAmbience: tagged Attachments, no parts)
	-- water lapping at three stretches of the lagoon's shore (front, west bay, behind Crystal
	-- Isle), drips from the ceiling (a hanging crystal over the water, the front half: no
	-- ceiling there in the cutaway), the hum of the Giant Crystal's plaza and of the giant
	-- crystal on the islet before the falls
	for _, p in { Vector2.new(6, 2), Vector2.new(-36, -14), Vector2.new(10, -44) } do
		MineKit.ambience(water, "LagoonLap", pt(p.X, WATER + 0.6, p.Y))
	end
	MineKit.ambienceNear(ceiling, "MineDrip", pt(22, CEIL - 8, -16))
	if not cutaway then
		MineKit.ambienceNear(ceiling, "MineDrip", pt(-24, CEIL - 4, 26))
	end
	MineKit.ambienceNear(ground, "CrystalHum", pt(GIANT.X, 3, GIANT.Y))
	MineKit.ambienceNear(crystals, "CrystalHum", pt(-2, 4, -41))

	-- everything anchored (the helpers already are; this keeps it a rule)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	MineKit.dimLights(model, Floor.Index)
	model.Parent = parent
	return model
end

return Floor
