--[[
	Mine floor 5, STORMGLASS RIFT (blaster 8+, reached only by the elevator),
	between the Sunken Palace and the Heartstone Core (the balance study's
	3h-5h stretch, docs/plans/STORM_FLOOR_PLAN.md). MineFloors entry
	"StormglassRift", MineFloors.Placement[5] (0, -300, -800), WorldLayout zone
	and cave "StormglassRift", its Mine Lift TrainConfig "StormglassRift" at
	MineFloors.LiftSpots[5]. Contract: MineKit's header.

	A deep storm cavern of dark indigo stone where an ancient storm still
	rages: electric yellow-white stormglass crystals, silver-steel storm
	catcher machinery with copper coils (the Forgekeepers tapped the storm to
	run their forges), frozen lightning and frozen rain.

	Layout (local to `origin`, ground y = 0, +Z = front where players arrive):
	  z +42 .. +56  the landing: a steel deck (y 2.4) with the elevator (left),
	                the ore lift spot (right, LIFT_SPOT), the BLASTER LV 8+ gate
	                over the stairs, the floor sign, lamps and camp gear
	  z +12 .. +42  the front rock field, an avenue of tesla pylon pairs (neon
	                arcs between them) along the main path
	  z  +2 .. +12  THE RIFT: a glowing chasm across the cave (x -60..60) with a
	                jagged lip, lightning arcing between its walls, three silver
	                catwalk bridges (x 0, x -50, x 50) and a safety floor under
	                its lip (y -1.6) so nobody falls in
	  z  -9 .. -31  the pylon plaza (the GiantSpawn) under the STORM CROWN: a
	                ring of dark thundercloud puffs near the ceiling with glowing
	                undersides, frozen lightning bolts striking down onto the
	                plaza's four tesla pylons and into the rift, frozen rain, a
	                hanging cluster of storm crystals in the eye of the ring
	  z -41 .. -56  the storm catcher: a silver tesla tower with a copper coil
	                stack, a catwalk ring and a captured lightning heart, two
	                capacitor tanks and a gauge panel on the back wall
	  sides         jagged indigo rock walls with yellow lightning veins,
	                stormglass crystal clusters, small rain clouds
	26 rock spawns: 12 in the front field, 14 "deep" past the rift.

	Everything stays within local y -11.5 .. +50 (the walls' and the rift's
	foot, the roof's top). About 1900 parts in the game build (MineKit.PartBudget
	2500, the phase A target 2400), 11 PointLights (phones: the neon of the
	bolts, arcs, crystals, rain and lamps glows on its own), 3 emitters, 6 ambience
	spots. opts.Cutaway (preview pictures): no front wall and no ceiling over
	the front half (z > 0).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local MovementConfig = require(Shared:WaitForChild("Config"):WaitForChild("MovementConfig"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local MineKit = require(World:WaitForChild("Mine"):WaitForChild("MineKit"))

local Floor = {}

local ENTRY = MineFloors.get("StormglassRift")

Floor.Id = ENTRY.Id
Floor.Index = ENTRY.Index
Floor.Size = Vector3.new(136, 56, 120)
Floor.MinBlaster = ENTRY.MinBlaster

local rgb = Color3.fromRGB

-- The floor's MineFloors palette: dark indigo rock, electric yellow / yellow-white storm
-- crystals, copper coils (RockBuilder's "StormglassRift" look uses the same).
Floor.Palette = ENTRY.Palette

-- The train's Mine Lift on the landing (MineFloors.LiftSpots, TrainConfig.Lifts "StormglassRift");
-- its cable hangs from the crane beam at LIFT_SPOT.Y + 30 (WorldLayout.Caves.StormglassRift.Max.Y).
Floor.LiftSpot = MineFloors.LiftSpots[ENTRY.Index] or Vector3.new(28, 2.4, 47)

---------------------------------------------------------------- palette and part presets

local PAL = Floor.Palette
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local STONE = PAL.Mid
local STONE_LIGHT = PAL.Light
local STONE_DARK = PAL.Dark
local STORM = PAL.Crystal
local SPARK = PAL.Crystal2
local COPPER = PAL.Accent
local COPPER_DARK = rgb(168, 88, 46)
local GROUND = PAL.Ground
local PLATE = rgb(66, 74, 116)
local PLATE2 = rgb(76, 84, 128)
local PATH = rgb(108, 118, 166)
local PATH2 = rgb(96, 106, 154)
local WALL = rgb(44, 50, 84)
local CEILING = rgb(30, 34, 58)
local CAVE = { STONE, STONE_LIGHT, STONE_DARK }
local SILVER = rgb(198, 206, 226)
local STEEL = rgb(140, 150, 180)
local STEEL_DARK = rgb(62, 68, 100)
local HAZARD = rgb(255, 196, 52)
local CLOUD_DARK = rgb(70, 76, 120)
local CLOUD = rgb(94, 102, 150)
local CLOUD_LIGHT = rgb(132, 140, 188)
local CLOUD_GLOW = rgb(228, 168, 62)
local BOLT = rgb(255, 250, 222)
local BOLT_GLOW = rgb(255, 228, 110)
local ARC_BLUE = rgb(110, 172, 255)
local RIFT_CORE = rgb(200, 230, 255)
local RAIN = rgb(178, 204, 255)

local SOLID: Geo.PartProps = { CanTouch = false, CanQuery = true, CanCollide = true }
local BUMP: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = true }
local DECOR: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false }
local GLOW: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local HALO: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 0.8 }
local RAIN_P: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 0.45 }
local HIDDEN: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
-- the rift's safety floor: invisible, players stand on it, rays and the beam pass through
local NET: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = true, CastShadow = false, Transparency = 1 }

local UP = Vector3.new(0, 1, 0)
local VERTEX_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, math.pi / 4, 0)

---------------------------------------------------------------- layout

local IN_X = 64 -- inner face of the side walls
local IN_FRONT = 56 -- inner face of the front wall
local IN_BACK = -56 -- inner face of the back wall
local CEIL = 46 -- underside of the ceiling (its top at 50)
local BOTTOM = -11.5 -- the walls reach down to the rift's floor
local DECK_Y = 2.4 -- the landing deck's top
local DECK_Z = 42 -- the landing deck's front edge
local RIFT_Z0, RIFT_Z1 = 2, 12 -- the rift's back and front lip
local RIFT_X = 60 -- the rift runs x -60 .. 60 (rock caps to the walls)
local RIFT_FLOOR = -10 -- top of the rift's floor
local PLAZA = Vector2.new(0, -20) -- the pylon plaza and the GiantSpawn
local PLAZA_R = 11.5
local PLAZA_TOP = 0.7
local CROWN_Y = 33.5 -- bottom of the Storm Crown's puffs
local CROWN_R = 18
local CATCHER = Vector2.new(0, -49)
local BRIDGES = { { X = 0, W = 10 }, { X = -50, W = 7 }, { X = 50, W = 7 } }
local LIFT_SPOT = Floor.LiftSpot

-- rock spawns (x, z) on the ground: the front field, then the deep field past the rift
local SPAWNS = {
	{ -18, 24 },
	{ -34, 24 },
	{ -52, 26 },
	{ -18, 36 },
	{ -34, 36 },
	{ -52, 37 },
	{ 18, 24 },
	{ 34, 24 },
	{ 52, 26 },
	{ 18, 36 },
	{ 34, 36 },
	{ 52, 37 },
}
local DEEP_SPAWNS = {
	{ -22, -6 },
	{ -38, -10 },
	{ -56, -14 },
	{ -28, -27 },
	{ -46, -30 },
	{ -30, -45 },
	{ -50, -46 },
	{ 22, -6 },
	{ 38, -10 },
	{ 56, -14 },
	{ 28, -27 },
	{ 46, -30 },
	{ 30, -45 },
	{ 50, -46 },
}

-- every builder below works in floor-local space; O maps it to the world
local O = CFrame.identity

---------------------------------------------------------------- part helpers

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function blk(parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, props: Geo.PartProps?): Part
	return Geo.block(parent, O * cf, size, color, mat or SMOOTH, props or DECOR)
end

-- A cylinder whose axis is the UpVector of `cf` (Roblox cylinders run along X).
local function cyl(parent: Instance, cf: CFrame, height: number, diameter: number, color: Color3, mat: Enum.Material?, props: Geo.PartProps?): Part
	local p = Geo.block(parent, O * cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(height, diameter, diameter), color, mat or SMOOTH, props or DECOR)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A bar from p to q (thick x thick cross-section).
local function bar(parent: Instance, p: Vector3, q: Vector3, thick: number, color: Color3, mat: Enum.Material, props: Geo.PartProps): Part?
	local d = q - p
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (p + q) / 2
	return blk(parent, CFrame.lookAt(mid, q), Vector3.new(thick, thick, len + thick * 0.5), color, mat, props)
end

-- A flat glowing strip from p to q lying on a surface whose normal is `up`.
local function strip(parent: Instance, p: Vector3, q: Vector3, up: Vector3, width: number, color: Color3)
	local d = q - p
	if d.Magnitude < 0.05 then
		return
	end
	local mid = (p + q) / 2
	blk(parent, CFrame.lookAt(mid, q, up), Vector3.new(width, 0.12, d.Magnitude + width * 0.5), color, NEON, GLOW)
end

local function pointLight(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

-- An invisible holder part with a PointLight (light where no glowing part is).
local function lightAt(parent: Instance, pos: Vector3, color: Color3, range: number, brightness: number): Part
	local holder = blk(parent, CFrame.new(pos), Vector3.new(0.2, 0.2, 0.2), color, SMOOTH, HIDDEN)
	holder.Name = "LightHolder"
	pointLight(holder, color, range, brightness)
	return holder
end

local function crystal(parent: Instance, base: CFrame, height: number, width: number, color: Color3)
	Style.crystal(parent, O * base, height, width, color)
end

-- A neon diamond (a cube standing on a vertex).
local function diamond(parent: Instance, pos: Vector3, size: number, color: Color3, spin: number): Part
	return blk(parent, CFrame.new(pos) * CFrame.Angles(0, spin, 0) * VERTEX_UP, Vector3.new(size, size, size), color, NEON, GLOW)
end

local function v3(p: Vector2, y: number): Vector3
	return Vector3.new(p.X, y, p.Y)
end

local function spawnPoints(): { Vector2 }
	local list = {}
	for _, s in SPAWNS do
		table.insert(list, Vector2.new(s[1], s[2]))
	end
	for _, s in DEEP_SPAWNS do
		table.insert(list, Vector2.new(s[1], s[2]))
	end
	return list
end

local function nearSpawn(points: { Vector2 }, p: Vector2, distance: number): boolean
	for _, s in points do
		if (s - p).Magnitude < distance then
			return true
		end
	end
	return false
end

-- A glowing zig-zag crack on the floor from (x, z), heading `angle`.
local function crack(parent: Instance, rng: Rng.Rng, x: number, z: number, angle: number, segs: number, len: number, color: Color3)
	local p = Vector3.new(x, 0.06, z)
	local a = angle
	for k = 1, segs do
		local l = len * rng:range(0.65, 1.1)
		local q = p + Vector3.new(math.cos(a), 0, math.sin(a)) * l
		strip(parent, p, q, UP, if k == 1 then 0.3 else 0.22, color)
		p = q
		a += (if k % 2 == 0 then 1 else -1) * rng:range(0.5, 0.9)
	end
end

---------------------------------------------------------------- signs

-- A sign board with a neon frame and big glowing letters (both faces); cf = board center.
local function glowSign(parent: Instance, cf: CFrame, text: string, width: number, height: number, frame: Color3, textColor: Color3): Part
	local board = blk(parent, cf, Vector3.new(width, height, 0.5), STEEL_DARK, SMOOTH, DECOR)
	board.Name = "Sign"
	blk(parent, cf * CFrame.new(0, height / 2 - 0.15, 0), Vector3.new(width + 0.3, 0.3, 0.8), frame, NEON, GLOW)
	blk(parent, cf * CFrame.new(0, -height / 2 + 0.15, 0), Vector3.new(width + 0.3, 0.3, 0.8), frame, NEON, GLOW)
	blk(parent, cf * CFrame.new(-width / 2 + 0.15, 0, 0), Vector3.new(0.3, height, 0.8), frame, NEON, GLOW)
	blk(parent, cf * CFrame.new(width / 2 - 0.15, 0, 0), Vector3.new(0.3, height, 0.8), frame, NEON, GLOW)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "FrontText" else "BackText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.9, 0.72)
		label.Position = UDim2.fromScale(0.05, 0.14)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = textColor
		label.TextStrokeColor3 = frame
		label.TextStrokeTransparency = 0.3
		label.FontFace = Font.fromEnum(Style.SignFont)
		label.Parent = gui
	end
	return board
end

---------------------------------------------------------------- lightning

--[[
	A frozen lightning bolt from `from` to `to`: a zig-zag of tapering neon
	segments (every other one in a soft see-through glow sleeve), `branches`
	short forked zig-zags off its middle, and a spark star where it strikes.
]]
local function bolt(parent: Instance, from: Vector3, to: Vector3, width: number, branches: number, rng: Rng.Rng): Model
	local m = model("FrozenBolt", parent)
	local d = to - from
	local side = d:Cross(UP)
	if side.Magnitude < 0.01 then
		side = Vector3.new(1, 0, 0)
	end
	side = side.Unit
	local side2 = d:Cross(side).Unit
	local n = math.clamp(math.floor(d.Magnitude / 5), 4, 8)
	local pts: { Vector3 } = { from }
	for k = 1, n - 1 do
		local t = k / n
		local swing = (if k % 2 == 0 then 1 else -1) * rng:range(1.1, 2.1) * math.min(1, d.Magnitude / 22)
		table.insert(pts, from + d * t + side * swing + side2 * rng:range(-0.8, 0.8))
	end
	table.insert(pts, to)
	for k = 1, #pts - 1 do
		local w = width * (1 - 0.4 * (k - 1) / n)
		bar(m, pts[k], pts[k + 1], w, BOLT, NEON, GLOW)
		if k % 2 == 1 then
			bar(m, pts[k], pts[k + 1], w * 2.1, BOLT_GLOW, NEON, HALO)
		end
	end
	for b = 1, branches do
		local k = math.clamp(2 + (b - 1) * 2, 2, #pts - 2)
		local p = pts[k]
		local out = (d.Unit + side * (if b % 2 == 0 then 1.1 else -1.1)).Unit
		local q1 = p + out * rng:range(2.6, 3.8)
		local q2 = q1 + (d.Unit * 0.8 - side * (if b % 2 == 0 then 0.5 else -0.5)).Unit * rng:range(1.8, 2.8)
		bar(m, p, q1, width * 0.5, BOLT, NEON, GLOW)
		bar(m, q1, q2, width * 0.36, BOLT, NEON, GLOW)
	end
	-- the spark where it strikes
	local star = CFrame.new(to) * CFrame.Angles(0, rng:range(0, math.pi), 0)
	blk(m, star, Vector3.new(2.2, 0.22, 0.22), SPARK, NEON, GLOW)
	blk(m, star * CFrame.Angles(0, math.pi / 2, math.pi / 2), Vector3.new(1.8, 0.22, 0.22), SPARK, NEON, GLOW)
	return m
end

-- A neon arc between two pylon tips: a zig-zag bowing up a little, and a fainter blue strand.
local function arc(parent: Instance, a: Vector3, b: Vector3, rng: Rng.Rng): Vector3
	local m = model("Arc", parent)
	local d = b - a
	local side = d:Cross(UP).Unit
	local n = 5
	for strand = 1, 2 do
		local prev = a
		for k = 1, n do
			local t = k / n
			local q = if k == n
				then b
				else a + d * t + UP * (math.sin(math.pi * t) * 1.4 + (if (k + strand) % 2 == 0 then 0.7 else -0.7)) + side * rng:range(-0.5, 0.5)
			bar(m, prev, q, if strand == 1 then 0.24 else 0.13, if strand == 1 then BOLT else ARC_BLUE, NEON, GLOW)
			prev = q
		end
	end
	return a + d * 0.5 + UP * 1.4
end

---------------------------------------------------------------- tesla pylons

--[[
	A tesla pylon: a steel plinth with a copper trim, a silver column wound
	with a copper coil, a steel cap and a storm crystal on top. Returns the
	crystal's tip and the coil's top ring (an ambience host).
]]
local function pylon(parent: Instance, base: Vector3, height: number, rings: number): (Vector3, BasePart)
	local m = model("TeslaPylon", parent)
	m:AddTag(MovementConfig.BeamIgnoreTag) -- never blocks the mining beam
	blk(m, CFrame.new(base + Vector3.new(0, 0.5, 0)), Vector3.new(2.8, 1, 2.8), STEEL_DARK, METAL, BUMP)
	blk(m, CFrame.new(base + Vector3.new(0, 1.04, 0)), Vector3.new(2.3, 0.14, 2.3), COPPER, METAL, GLOW)
	cyl(m, CFrame.new(base + Vector3.new(0, 1 + height / 2, 0)), height, 1.1, SILVER, METAL, BUMP)
	local ring: BasePart = nil :: any
	for k = 1, rings do
		ring = cyl(m, CFrame.new(base + Vector3.new(0, 1 + height * 0.3 + (k - 1) * 0.62, 0)), 0.5, 2.1, if k % 2 == 0 then COPPER_DARK else COPPER, METAL, DECOR)
	end
	cyl(m, CFrame.new(base + Vector3.new(0, 1 + height + 0.2, 0)), 0.4, 2.3, STEEL, METAL, DECOR)
	local h = 3.2
	crystal(m, CFrame.new(base + Vector3.new(0, 1 + height + 0.35, 0)), h, 1.1, STORM)
	return base + Vector3.new(0, 1 + height + 0.35 + h * 0.86, 0), ring
end

---------------------------------------------------------------- thunderclouds

--[[
	A voxel thundercloud puff with its bottom at `bottom` (Clouds.luau's
	stepped cumulus, storm-dark): a glowing underside slab, a wide dark base,
	a lower lump with its own glow, two mid domes, a light top dome and a
	shoulder cube. `yaw` turns it (its X axis along the Storm Crown's ring).
	Returns the underside's middle.
]]
local function puff(parent: Instance, bottom: Vector3, scale: number, yaw: number, rng: Rng.Rng): Vector3
	local m = model("ThunderPuff", parent)
	local s = scale
	local f = CFrame.new(bottom) * CFrame.Angles(0, yaw, 0)
	blk(m, f * CFrame.new(0, 0.3, 0), Vector3.new(6.6 * s, 0.6, 4.4 * s), CLOUD_GLOW, NEON, GLOW)
	blk(m, f * CFrame.new(0, 0.55 + 1.3 * s, 0), Vector3.new(9 * s, 2.6 * s, 6.6 * s), Geo.vary(CLOUD_DARK, rng, 0.03), SMOOTH, DECOR)
	local lx = rng:range(-2.4, 2.4) * s
	blk(m, f * CFrame.new(lx, -0.45, 0.4 * s), Vector3.new(2.8 * s, 0.5, 2.4 * s), CLOUD_GLOW, NEON, GLOW)
	blk(m, f * CFrame.new(lx, 0.2 + 0.5 * s, 0.4 * s), Vector3.new(4.4 * s, 1.0 * s + 0.4, 4 * s), Geo.vary(CLOUD_DARK, rng, 0.03), SMOOTH, DECOR)
	for _, sx in { -1, 1 } do
		blk(m, f * CFrame.new(sx * 2.1 * s, 0.55 + 2.6 * s + 1.1 * s, sx * 0.5 * s), Vector3.new(5.4 * s, 2.4 * s, 4.8 * s), Geo.vary(CLOUD, rng, 0.03), SMOOTH, DECOR)
	end
	blk(m, f * CFrame.new(0.6 * s, 0.55 + 5 * s + 0.9 * s, -0.2 * s), Vector3.new(4.2 * s, 1.9 * s, 3.4 * s), Geo.vary(CLOUD_LIGHT, rng, 0.03), SMOOTH, DECOR)
	blk(m, f * CFrame.new(-3.9 * s, 0.55 + 2.4 * s, -1.4 * s) * CFrame.Angles(0, 0.5, 0), Vector3.new(2.6 * s, 2.6 * s, 2.6 * s), Geo.vary(CLOUD, rng, 0.03), SMOOTH, DECOR)
	return bottom
end

-- Frozen rain under a cloud: thin see-through streaks slanting a little with the wind.
local function rain(parent: Instance, top: Vector3, spread: Vector2, count: number, minLen: number, maxLen: number, rng: Rng.Rng)
	local m = model("FrozenRain", parent)
	local wind = Vector3.new(0.12, -1, 0.05).Unit
	for _ = 1, count do
		local p = top + Vector3.new(rng:range(-0.5, 0.5) * spread.X, -rng:range(0.2, 2.5), rng:range(-0.5, 0.5) * spread.Y)
		local len = rng:range(minLen, maxLen)
		bar(m, p, p + wind * len, 0.13, RAIN, NEON, RAIN_P)
	end
end

---------------------------------------------------------------- ground, paths, cracks

local function buildGround(parent: Instance, rng: Rng.Rng)
	local m = model("Ground", parent)
	local front = blk(m, CFrame.new(0, -1, (RIFT_Z1 + IN_FRONT) / 2), Vector3.new(IN_X * 2, 2, IN_FRONT - RIFT_Z1), GROUND, SMOOTH, SOLID)
	front.Name = "Ground"
	local back = blk(m, CFrame.new(0, -1, (IN_BACK + RIFT_Z0) / 2), Vector3.new(IN_X * 2, 2, RIFT_Z0 - IN_BACK), GROUND, SMOOTH, SOLID)
	back.Name = "Ground"
	-- slate plates scattered over the fields (not under the rocks, paths, plaza or landing)
	local points = spawnPoints()
	local placed = 0
	for _ = 1, 400 do
		if placed >= 46 then
			break
		end
		local p = Vector2.new(rng:range(-60, 60), rng:range(-53, 40))
		local onPath = math.abs(p.X) < 6.5
		local inRift = p.Y > RIFT_Z0 - 3 and p.Y < RIFT_Z1 + 3
		local onPlaza = (p - PLAZA).Magnitude < PLAZA_R + 4
		local atCatcher = math.abs(p.X - CATCHER.X) < 22 and p.Y < -40
		if not onPath and not inRift and not onPlaza and not atCatcher and not nearSpawn(points, p, 6.2) then
			placed += 1
			local s = rng:range(3.4, 6.2)
			local cf = CFrame.new(p.X, 0.03 + (placed % 3) * 0.01, p.Y) * CFrame.Angles(0, rng:range(0, math.pi), 0)
			blk(m, cf, Vector3.new(s, 0.08, s * rng:range(0.7, 1.0)), if placed % 2 == 0 then PLATE else PLATE2, SMOOTH, DECOR)
		end
	end
	-- the main path: flagstones from the stairs to the rift, the rift to the plaza, the plaza to the catcher
	local runs = { { 36.4, RIFT_Z1 + 2 }, { RIFT_Z0 - 2, PLAZA.Y + PLAZA_R + 0.5 }, { PLAZA.Y - PLAZA_R - 0.5, CATCHER.Y + 5 } }
	local k = 0
	for _, run in runs do
		local z0, z1 = run[1], run[2]
		local count = math.max(1, math.floor((z0 - z1) / 3.6 + 0.5))
		local step = (z0 - z1) / count
		for i = 0, count - 1 do
			k += 1
			local z = z0 - step * (i + 0.5)
			local cf = CFrame.new(0, 0.07, z) * CFrame.Angles(0, rng:range(-0.04, 0.04), 0)
			blk(m, cf, Vector3.new(7.2, 0.18, step - 0.35), if k % 2 == 0 then PATH else PATH2, SMOOTH, SOLID)
		end
	end
	-- crackling cracks: around the plaza, in the deep field, a few in front
	local cracks = {
		{ -14, -6, 2.6 },
		{ 14, -7, 0.4 },
		{ -16, -34, -2.2 },
		{ 15, -33, -0.6 },
		{ -40, -20, 1.0 },
		{ 40, -21, 2.2 },
		{ -20, -50, 0.2 },
		{ 20, -51, 2.9 },
		{ -10, 30, 2.8 },
		{ 10, 18, 0.3 },
		{ -44, 31, -0.4 },
		{ 44, 31, 3.4 },
	}
	for _, c in cracks do
		crack(m, rng, c[1], c[2], c[3], rng:int(3, 4), 2.6, STORM)
	end
end

---------------------------------------------------------------- the rift

local function catwalk(parent: Instance, x: number, width: number)
	local m = model("Catwalk", parent)
	local z0, z1 = RIFT_Z0 - 2.2, RIFT_Z1 + 2.2
	local len = z1 - z0
	local mid = (z0 + z1) / 2
	local deck = blk(m, CFrame.new(x, 0.18, mid), Vector3.new(width, 0.36, len), SILVER, METAL, SOLID)
	deck.Name = "CatwalkDeck"
	for _, z in { RIFT_Z0 + 1.6, mid, RIFT_Z1 - 1.6 } do
		blk(m, CFrame.new(x, 0.38, z), Vector3.new(width - 0.6, 0.06, 0.16), STEEL_DARK, METAL, GLOW)
	end
	for _, side in { -1, 1 } do
		local ex = x + side * (width / 2 - 0.25)
		blk(m, CFrame.new(ex, 0.5, mid), Vector3.new(0.5, 0.4, len), STEEL_DARK, METAL, BUMP)
		blk(m, CFrame.new(ex, 0.72, mid), Vector3.new(0.52, 0.06, len), HAZARD, SMOOTH, GLOW)
		for _, z in { z0 + 0.6, mid, z1 - 0.6 } do
			blk(m, CFrame.new(ex, 1.9, z), Vector3.new(0.34, 2.4, 0.34), STEEL, METAL, BUMP)
		end
		blk(m, CFrame.new(ex, 3.15, mid), Vector3.new(0.3, 0.3, len - 0.6), SILVER, METAL, BUMP)
		blk(m, CFrame.new(ex, 2.0, mid), Vector3.new(0.16, 0.16, len - 0.6), STEEL, METAL, DECOR)
		-- the truss under the deck
		blk(m, CFrame.new(x + side * (width / 2 - 1.2), -0.55, mid), Vector3.new(0.5, 1.1, len - 0.4), STEEL_DARK, METAL, DECOR)
	end
	bar(m, Vector3.new(x - width / 2 + 1.2, -1.0, RIFT_Z0 + 0.4), Vector3.new(x + width / 2 - 1.2, -1.0, RIFT_Z1 - 0.4), 0.3, STEEL, METAL, DECOR)
end

local function buildRift(parent: Instance, rng: Rng.Rng): { BasePart }
	local m = model("Rift", parent)
	local width = RIFT_Z1 - RIFT_Z0
	local mid = (RIFT_Z0 + RIFT_Z1) / 2
	local depth = -BOTTOM
	-- the walls (their faces 0.05 in front of the ground slabs' ends), the floor and its glow
	blk(m, CFrame.new(0, BOTTOM / 2 - 0.02, RIFT_Z1 + 0.7), Vector3.new(RIFT_X * 2, depth - 0.04, 1.5), STONE_DARK, SMOOTH, SOLID)
	blk(m, CFrame.new(0, BOTTOM / 2 - 0.02, RIFT_Z0 - 0.7), Vector3.new(RIFT_X * 2, depth - 0.04, 1.5), STONE_DARK, SMOOTH, SOLID)
	blk(m, CFrame.new(0, (BOTTOM + RIFT_FLOOR) / 2, mid), Vector3.new(RIFT_X * 2, RIFT_FLOOR - BOTTOM, width), WALL, SMOOTH, SOLID)
	blk(m, CFrame.new(0, RIFT_FLOOR + 0.1, mid), Vector3.new(RIFT_X * 2, 0.2, width - 3.2), ARC_BLUE, NEON, GLOW)
	blk(m, CFrame.new(0, RIFT_FLOOR + 0.22, mid), Vector3.new(RIFT_X * 2, 0.16, 1.6), RIFT_CORE, NEON, GLOW)
	-- glowing seams along both lips, just under the edge
	for _, z in { RIFT_Z1 - 0.06, RIFT_Z0 + 0.06 } do
		blk(m, CFrame.new(0, -0.9, z), Vector3.new(RIFT_X * 2, 0.26, 0.1), ARC_BLUE, NEON, GLOW)
	end
	-- rock caps close the rift's ends up to the walls
	for _, sx in { -1, 1 } do
		blk(m, CFrame.new(sx * (RIFT_X + IN_X) / 2, BOTTOM / 2, mid), Vector3.new(IN_X - RIFT_X, depth, width), GROUND, SMOOTH, SOLID)
	end
	-- the safety floor under the lip: who steps in lands 1.6 under the edge and jumps out
	local net = blk(m, CFrame.new(0, -1.8, mid), Vector3.new(RIFT_X * 2, 0.4, width), STONE_DARK, SMOOTH, NET)
	net.Name = "RiftNet"
	-- the jagged lip: rock teeth over the edge (not where the catwalks cross)
	local function onBridge(x: number): boolean
		for _, b in BRIDGES do
			if math.abs(x - b.X) < b.W / 2 + 1.6 then
				return true
			end
		end
		return false
	end
	for _, lip in { RIFT_Z1, RIFT_Z0 } do
		local x = -RIFT_X + 2
		while x < RIFT_X - 1.5 do
			local s = rng:range(2.0, 3.2)
			if not onBridge(x) then
				local cf = CFrame.new(x, -0.2, lip + (if lip == RIFT_Z1 then -0.15 else 0.15)) * CFrame.Angles(0, math.pi / 4 + rng:range(-0.25, 0.25), 0)
				blk(m, cf, Vector3.new(s, 0.5, s), Geo.vary(if rng:chance(0.5) then STONE_DARK else STONE, rng, 0.04), SMOOTH, DECOR)
			end
			x += s * 1.25 + rng:range(0, 1.2)
		end
	end
	-- a glowing haze rising out of the rift (seen from any angle) and blue veins down its walls
	local haze = blk(m, CFrame.new(0, -5, mid), Vector3.new(RIFT_X * 2, 7, 0.3), ARC_BLUE, NEON, GLOW)
	haze.Name = "RiftHaze"
	haze.Transparency = 0.7
	Style.emitter(haze, "Sparkle", RIFT_CORE, 8)
	local veinX = -RIFT_X + 4
	while veinX < RIFT_X - 3 do
		for _, z in { RIFT_Z1 - 0.05, RIFT_Z0 + 0.05 } do
			local x = veinX + rng:range(-1.5, 1.5)
			local top = Vector3.new(x, -1.4, z)
			local midP = Vector3.new(x + rng:range(-1.2, 1.2), -4.6, z)
			local low = Vector3.new(x + rng:range(-1.2, 1.2), -8.5, z)
			strip(m, top, midP, Vector3.new(0, 0, if z > mid then -1 else 1), 0.3, ARC_BLUE)
			strip(m, midP, low, Vector3.new(0, 0, if z > mid then -1 else 1), 0.24, ARC_BLUE)
		end
		veinX += rng:range(9, 13)
	end
	-- lightning arcing between the walls
	local arcs = { -46, -26, -10, 12, 30, 44 }
	for i, x0 in arcs do
		local prev = Vector3.new(x0, rng:range(-6, -3.5), RIFT_Z0 + 0.4)
		for k = 1, 5 do
			local q = Vector3.new(prev.X + rng:range(1.8, 3.0), math.clamp(prev.Y + rng:range(-1.4, 1.6), -8, -1.8), if k % 2 == 1 then RIFT_Z1 - 0.4 - rng:range(0, 1.5) else RIFT_Z0 + 0.4 + rng:range(0, 1.5))
			bar(m, prev, q, if k == 1 then 0.22 else 0.17, if i % 2 == 0 then BOLT else RIFT_CORE, NEON, GLOW)
			prev = q
		end
	end
	-- the catwalks
	for _, b in BRIDGES do
		catwalk(m, b.X, b.W)
	end
	-- its glow lights the walls and the catwalks from below (two lights for the whole rift)
	local lights: { BasePart } = {}
	for _, x in { -30, 30 } do
		table.insert(lights, lightAt(m, Vector3.new(x, -3, mid), ARC_BLUE, 34, 1.9))
	end
	return lights
end

---------------------------------------------------------------- walls and ceiling

local function buildWalls(parent: Instance, rng: Rng.Rng, cutaway: boolean)
	local m = model("Walls", parent)
	local height = 50 - BOTTOM
	local midY = (50 + BOTTOM) / 2
	for _, sx in { -1, 1 } do
		blk(m, CFrame.new(sx * (IN_X + 2), midY, 0), Vector3.new(4, height, IN_FRONT * 2 + 8), WALL, SMOOTH, SOLID)
		-- jagged rock with lightning veins low, sparser broken rock up to the ceiling
		MineKit.wall(m, O * Vector3.new(sx * (IN_X - 4), 0, IN_FRONT), O * Vector3.new(sx * (IN_X - 4), 0, IN_BACK), 30, Vector3.new(-sx, 0, 0), CAVE, rng, { Depth = 6, Glow = STORM })
		MineKit.wall(m, O * Vector3.new(sx * (IN_X - 2.5), 26, IN_FRONT), O * Vector3.new(sx * (IN_X - 2.5), 26, IN_BACK), 20, Vector3.new(-sx, 0, 0), CAVE, rng, { Depth = 5, Step = 9 })
	end
	blk(m, CFrame.new(0, midY, IN_BACK - 2), Vector3.new(IN_X * 2, height, 4), WALL, SMOOTH, SOLID)
	-- the back wall: rock on both sides of the storm catcher's gauge panel
	for _, sx in { -1, 1 } do
		MineKit.wall(m, O * Vector3.new(sx * (IN_X - 2), 0, IN_BACK + 4), O * Vector3.new(sx * 16, 0, IN_BACK + 4), 30, Vector3.new(0, 0, 1), CAVE, rng, { Depth = 6, Glow = STORM })
	end
	MineKit.wall(m, O * Vector3.new(-IN_X + 2, 26, IN_BACK + 2.5), O * Vector3.new(IN_X - 2, 26, IN_BACK + 2.5), 20, Vector3.new(0, 0, 1), CAVE, rng, { Depth = 5, Step = 9 })
	if not cutaway then
		blk(m, CFrame.new(0, midY, IN_FRONT + 2), Vector3.new(IN_X * 2, height, 4), WALL, SMOOTH, SOLID)
		MineKit.wall(m, O * Vector3.new(-IN_X + 2, DECK_Y, IN_FRONT - 1.5), O * Vector3.new(IN_X - 2, DECK_Y, IN_FRONT - 1.5), 28, Vector3.new(0, 0, -1), CAVE, rng, { Depth = 4, Step = 7 })
		MineKit.wall(m, O * Vector3.new(-IN_X + 2, 28, IN_FRONT - 2), O * Vector3.new(IN_X - 2, 28, IN_FRONT - 2), 18, Vector3.new(0, 0, -1), CAVE, rng, { Depth = 4, Step = 10 })
	end
	-- boulders at the foot of the side walls
	for _, b in { { -59, 19 }, { 59, 31 }, { -59, -22 }, { 59, -38 }, { -58.5, 46 } } do
		Geo.rock(m, O * CFrame.new(b[1], if b[2] > DECK_Z then DECK_Y else 0, b[2]), Vector3.new(4.4, 3.6, 4.4), Geo.vary(STONE, rng, 0.05), rng, nil, BUMP)
	end
end

local function buildCeiling(parent: Instance, rng: Rng.Rng, cutaway: boolean)
	local m = model("Ceiling", parent)
	local z0 = IN_BACK - 4
	local z1 = if cutaway then 0 else IN_FRONT + 4
	local mid = (z0 + z1) / 2
	blk(m, CFrame.new(0, CEIL + 2, mid), Vector3.new(IN_X * 2 + 8, 4, z1 - z0), CEILING, SMOOTH, SOLID)
	for _ = 1, if cutaway then 4 else 7 do
		local x = rng:range(-54, 54)
		local z = rng:range(z0 + 10, z1 - 6)
		if (Vector2.new(x, z) - PLAZA).Magnitude > CROWN_R + 6 then
			local size = Vector3.new(rng:range(7, 13), rng:range(2, 4), rng:range(6, 11))
			blk(m, CFrame.new(x, CEIL - size.Y * 0.3, z) * CFrame.Angles(rng:range(-0.12, 0.12), rng:range(0, math.pi), rng:range(-0.12, 0.12)), size, Geo.vary(rng:pick(CAVE), rng, 0.05), SMOOTH, DECOR)
		end
	end
	MineKit.stalactites(m, O * Vector3.new(0, CEIL, mid), Vector2.new(112, z1 - z0 - 14), CAVE, rng, if cutaway then 5 else 8)
	-- the eye of the storm: a glowing swirl on the ceiling over the plaza
	local eye = v3(PLAZA, CEIL - 0.08)
	for arm = 0, 2 do
		local a0 = arm * math.pi * 2 / 3
		local prev = eye + Vector3.new(math.cos(a0), 0, math.sin(a0)) * 2.2
		for k = 1, 3 do
			local a = a0 + k * 0.55
			local q = eye + Vector3.new(math.cos(a), 0, math.sin(a)) * (2.2 + k * 2.4)
			strip(m, prev, q, -UP, 0.5 - k * 0.08, CLOUD_GLOW)
			prev = q
		end
	end
end

---------------------------------------------------------------- the landing

local function buildLanding(parent: Instance, rng: Rng.Rng)
	local m = model("Landing", parent)
	local depth = IN_FRONT - DECK_Z
	local mid = (IN_FRONT + DECK_Z) / 2
	local deck = blk(m, CFrame.new(0, DECK_Y / 2 - 0.05, mid), Vector3.new(IN_X * 2, DECK_Y - 0.1, depth), STEEL_DARK, METAL, SOLID)
	deck.Name = "LandingDeck"
	-- steel floor plates with dark seams between them
	for i = 0, 7 do
		local x = -IN_X + 8 + i * 16
		blk(m, CFrame.new(x, DECK_Y - 0.05, mid), Vector3.new(15.7, 0.1, depth - 0.3), if i % 2 == 0 then STEEL else rgb(128, 138, 170), METAL, SOLID)
	end
	-- the front edge: hazard trim over a dark base band
	blk(m, CFrame.new(0, DECK_Y - 0.25, DECK_Z - 0.1), Vector3.new(IN_X * 2, 0.4, 0.3), HAZARD, SMOOTH, GLOW)
	blk(m, CFrame.new(0, 0.7, DECK_Z - 0.08), Vector3.new(IN_X * 2, 1.2, 0.2), rgb(40, 44, 70), SMOOTH, GLOW)
	-- stairs down to the main path
	for k = 1, 3 do
		local top = DECK_Y - 0.6 * k
		local z = DECK_Z - 0.9 - 1.8 * (k - 1)
		blk(m, CFrame.new(0, top / 2, z), Vector3.new(14, top, 1.8), STEEL_DARK, METAL, SOLID)
		blk(m, CFrame.new(0, top - 0.05, z - 0.75), Vector3.new(14, 0.1, 0.3), HAZARD, SMOOTH, GLOW)
	end
	-- railings along the edge (open over the stairs)
	for _, sx in { -1, 1 } do
		local x0, x1 = sx * 8, sx * (IN_X - 2)
		local n = 7
		for i = 0, n do
			local x = x0 + (x1 - x0) * i / n
			blk(m, CFrame.new(x, DECK_Y + 1.3, DECK_Z + 0.35), Vector3.new(0.4, 2.6, 0.4), STEEL, METAL, BUMP)
		end
		blk(m, CFrame.new((x0 + x1) / 2, DECK_Y + 2.65, DECK_Z + 0.35), Vector3.new(math.abs(x1 - x0) + 0.4, 0.3, 0.32), SILVER, METAL, BUMP)
		blk(m, CFrame.new((x0 + x1) / 2, DECK_Y + 1.4, DECK_Z + 0.35), Vector3.new(math.abs(x1 - x0), 0.16, 0.16), STEEL, METAL, DECOR)
	end
	-- lamps by the gate
	for _, sx in { -1, 1 } do
		local base = Vector3.new(sx * 12, DECK_Y, 45)
		blk(m, CFrame.new(base + Vector3.new(0, 2.6, 0)), Vector3.new(0.5, 5.2, 0.5), STEEL_DARK, METAL, BUMP)
		blk(m, CFrame.new(base + Vector3.new(0, 5.4, 0)), Vector3.new(1.2, 0.4, 1.2), STEEL, METAL, DECOR)
		local lamp = diamond(m, base + Vector3.new(0, 6.2, 0), 1.0, SPARK, 0.4)
		lamp.Name = "Lamp"
	end
	-- one light over the arrival ring for both lamps (their neon glows on its own)
	lightAt(m, Vector3.new(0, DECK_Y + 7, 46), rgb(255, 240, 200), 26, 1.4)
	-- the arrival ring where players step out
	local center = Vector3.new(0, DECK_Y + 0.02, 48.5)
	for k = 0, 7 do
		local a0, a1 = k / 8 * math.pi * 2, (k + 1) / 8 * math.pi * 2
		strip(m, center + Vector3.new(math.cos(a0), 0, math.sin(a0)) * 3.6, center + Vector3.new(math.cos(a1), 0, math.sin(a1)) * 3.6, UP, 0.34, if k % 2 == 0 then STORM else ARC_BLUE)
	end
	-- the floor sign between the gate and the ore lift
	local signAt = CFrame.new(16, DECK_Y, 52)
	for _, sx in { -5.6, 5.6 } do
		blk(m, signAt * CFrame.new(sx, 2.8, 0), Vector3.new(0.7, 5.6, 0.7), STEEL_DARK, METAL, BUMP)
		blk(m, signAt * CFrame.new(sx, 5.75, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.6, 0.3, 0.6), STORM, NEON, GLOW)
	end
	glowSign(m, signAt * CFrame.new(0, 4.4, 0), "STORMGLASS RIFT", 11.5, 2.4, STORM, rgb(255, 250, 230))
	-- the Forgekeepers' camp gear by the elevator, a cart by the lift
	Style.crate(m, O * CFrame.new(-40, DECK_Y, 50.5), rng, 2.4)
	Style.crate(m, O * CFrame.new(-42.8, DECK_Y, 51), rng, 2.2)
	Style.crate(m, O * CFrame.new(-41.2, DECK_Y + 2.3, 50.8), rng, 1.8)
	Style.barrel(m, O * Vector3.new(-39.4, DECK_Y, 46.6), rng)
	Style.mineCart(m, O * CFrame.new(40, DECK_Y, 47.5), rng, { Load = "Gold" })
	-- the crane beam from the right wall that holds the ore lift's cable
	local beamY = LIFT_SPOT.Y + 30.45
	local x0, x1 = LIFT_SPOT.X - 2.6, IN_X - 0.2
	blk(m, CFrame.new((x0 + x1) / 2, beamY, LIFT_SPOT.Z), Vector3.new(x1 - x0, 0.9, 0.9), STEEL_DARK, METAL, DECOR)
	blk(m, CFrame.new((x0 + x1) / 2, beamY - 0.5, LIFT_SPOT.Z), Vector3.new(x1 - x0, 0.2, 1.3), STEEL, METAL, GLOW)
	blk(m, CFrame.new(x0 + 0.4, beamY, LIFT_SPOT.Z), Vector3.new(0.8, 2.2, 2.2), STEEL_DARK, METAL, GLOW)
	blk(m, CFrame.new(IN_X - 0.6, beamY - 2.5, LIFT_SPOT.Z), Vector3.new(1.0, 6, 2.6), STEEL_DARK, METAL, DECOR)
	bar(m, Vector3.new(IN_X - 1, beamY - 6.5, LIFT_SPOT.Z), Vector3.new(IN_X - 9, beamY - 0.6, LIFT_SPOT.Z), 0.8, STEEL, METAL, DECOR)
end

---------------------------------------------------------------- the plaza and the Storm Crown

type Plaza = { Top: BasePart, Tips: { Vector3 }, Rings: { BasePart } }

local function buildPlaza(parent: Instance): Plaza
	local m = model("Plaza", parent)
	local c = v3(PLAZA, 0)
	cyl(m, CFrame.new(c + Vector3.new(0, 0.3, 0)), 0.6, PLAZA_R * 2 + 1.2, STEEL_DARK, METAL, SOLID)
	cyl(m, CFrame.new(c + Vector3.new(0, 0.32, 0)), 0.64, PLAZA_R * 2, STORM, NEON, GLOW)
	local top = cyl(m, CFrame.new(c + Vector3.new(0, PLAZA_TOP / 2, 0)), PLAZA_TOP, PLAZA_R * 2 - 1.4, STONE, SMOOTH, SOLID)
	top.Name = "PlazaTop"
	-- lightning spokes between the pylons and an inner ring of copper studs
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + math.pi / 8
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		strip(m, c + dir * 6.6 + UP * (PLAZA_TOP + 0.02), c + dir * 9.6 + UP * (PLAZA_TOP + 0.02), UP, 0.36, STORM)
		blk(m, CFrame.new(c + dir * 5.2 + UP * PLAZA_TOP) * CFrame.Angles(0, a, 0), Vector3.new(0.9, 0.2, 0.9), COPPER, METAL, GLOW)
	end
	pointLight(top, STORM, 26, 1.1)
	Style.emitter(top, "Sparkle", STORM, 4)
	-- the four tall pylons the Storm Crown strikes
	local tips: { Vector3 } = {}
	local rings: { BasePart } = {}
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		local tip, ring = pylon(m, c + Vector3.new(math.cos(a), 0, math.sin(a)) * (PLAZA_R + 1.6), 9.5, 5)
		table.insert(tips, tip)
		table.insert(rings, ring)
	end
	return { Top = top, Tips = tips, Rings = rings }
end

local function buildCrown(parent: Instance, plaza: Plaza, rng: Rng.Rng): Model
	local m = model("StormCrown", parent)
	local center = v3(PLAZA, CROWN_Y)
	local bottoms: { Vector3 } = {}
	local count = 9
	for k = 0, count - 1 do
		local a = k / count * math.pi * 2 + 0.2 + rng:range(-0.08, 0.08)
		local r = CROWN_R + rng:range(-1.2, 1.4)
		local bottom = center + Vector3.new(math.cos(a) * r, rng:range(-1.0, 1.2), math.sin(a) * r)
		puff(m, bottom, rng:range(0.95, 1.15), -a + math.pi / 2, rng)
		table.insert(bottoms, bottom)
	end
	-- frozen bolts: from the nearest puff onto each pylon, one deep into the rift
	local bolts = model("Bolts", m)
	for i, tip in plaza.Tips do
		local best, bestD = bottoms[1], math.huge
		for _, b in bottoms do
			local d = (Vector2.new(b.X, b.Z) - Vector2.new(tip.X, tip.Z)).Magnitude
			if d < bestD then
				best, bestD = b, d
			end
		end
		bolt(bolts, best + Vector3.new(0, 0.1, 0), tip, 0.62, if i % 2 == 0 then 2 else 1, rng)
	end
	local front = bottoms[1]
	for _, b in bottoms do
		if b.Z > front.Z and b.X < 0 then
			front = b
		end
	end
	bolt(bolts, front + Vector3.new(0, 0.1, 0), Vector3.new(-16, RIFT_FLOOR + 1.5, (RIFT_Z0 + RIFT_Z1) / 2), 0.7, 2, rng)
	-- frozen rain from the puffs between the bolts
	for i, b in bottoms do
		if i % 2 == 0 then
			rain(m, b, Vector2.new(6, 4), 4, 5, 9, rng)
		end
	end
	-- the eye: a cluster of storm crystals hanging from the ceiling in the ring's middle
	MineKit.crystals(m, O * CFrame.new(v3(PLAZA, CEIL - 0.2)) * CFrame.Angles(math.pi, 0, 0), 7, 7, "Glow", { STORM, SPARK }, "StormEye")
	-- the underside glow lights the plaza, the crown's bolts and the field around it
	for k = 0, 1 do
		local a = k * math.pi + 0.6
		lightAt(m, center + Vector3.new(math.cos(a) * 11, -3, math.sin(a) * 11), rgb(255, 236, 170), 50, 1.45)
	end
	return m
end

---------------------------------------------------------------- tesla pylon pairs

local function buildPylonPairs(parent: Instance, rng: Rng.Rng): { Vector3 }
	local m = model("PylonPairs", parent)
	-- { left base, right base }: the main path at the stairs and at the rift, the side catwalks
	local pairs: { { Vector3 } } = {
		{ Vector3.new(-7, 0, 33.5), Vector3.new(7, 0, 33.5) },
		{ Vector3.new(-7.5, 0, 15.6), Vector3.new(7.5, 0, 15.6) },
		{ Vector3.new(-55, 0, 15.6), Vector3.new(-45, 0, 15.6) },
		{ Vector3.new(45, 0, 15.6), Vector3.new(55, 0, 15.6) },
	}
	local mids: { Vector3 } = {}
	for _, p in pairs do
		local a = pylon(m, p[1], 6.5, 4)
		local b = pylon(m, p[2], 6.5, 4)
		-- (no light: the arc's neon glows on its own)
		table.insert(mids, arc(m, a, b, rng))
	end
	return mids
end

---------------------------------------------------------------- the storm catcher

local function buildCatcher(parent: Instance, rng: Rng.Rng): BasePart
	local m = model("StormCatcher", parent)
	m:AddTag(MovementConfig.BeamIgnoreTag) -- never blocks the mining beam
	local c = v3(CATCHER, 0)
	blk(m, CFrame.new(c + Vector3.new(0, 0.8, 0)), Vector3.new(14, 1.6, 10), STEEL_DARK, METAL, SOLID)
	blk(m, CFrame.new(c + Vector3.new(0, 1.45, 5.05)), Vector3.new(14, 0.3, 0.2), HAZARD, SMOOTH, GLOW)
	-- the tower, its copper coil stack and the collar
	cyl(m, CFrame.new(c + Vector3.new(0, 1.6 + 10, 0)), 20, 3.6, SILVER, METAL, BUMP)
	for k = 0, 6 do
		cyl(m, CFrame.new(c + Vector3.new(0, 4.6 + k * 1.25, 0)), 0.85, 5.6 - k * 0.12, if k % 2 == 0 then COPPER else COPPER_DARK, METAL, DECOR)
	end
	cyl(m, CFrame.new(c + Vector3.new(0, 14.4, 0)), 1, 6.2, STEEL, METAL, DECOR)
	-- the toroid ring at the top, lightning rods and the captured lightning heart
	local topY = 21.8
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		blk(m, CFrame.new(c + Vector3.new(math.cos(a) * 4.1, topY, math.sin(a) * 4.1)) * CFrame.Angles(0, -a + math.pi / 2, 0), Vector3.new(3.6, 1.3, 1.3), SILVER, METAL, DECOR)
	end
	cyl(m, CFrame.new(c + Vector3.new(0, topY, 0)), 0.6, 6.4, STEEL_DARK, METAL, DECOR)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		local from = c + Vector3.new(math.cos(a) * 3.6, topY + 0.4, math.sin(a) * 3.6)
		local to = c + Vector3.new(math.cos(a) * 5.4, topY + 5.2, math.sin(a) * 5.4)
		bar(m, from, to, 0.3, STEEL, METAL, DECOR)
		blk(m, CFrame.new(to) * VERTEX_UP, Vector3.new(0.6, 0.6, 0.6), COPPER, METAL, GLOW)
	end
	local heart = diamond(m, c + Vector3.new(0, topY + 3.1, 0), 3.2, STORM, 0.3)
	heart.Name = "StormHeart"
	diamond(m, c + Vector3.new(0, topY + 3.1, 0), 2.3, SPARK, 1.1)
	pointLight(heart, STORM, 36, 1.7)
	Style.emitter(heart, "Sparkle", SPARK, 6)
	-- the catwalk ring round the tower
	local walkY = 9.4
	blk(m, CFrame.new(c + Vector3.new(0, walkY, 0)), Vector3.new(10, 0.4, 8), SILVER, METAL, DECOR)
	blk(m, CFrame.new(c + Vector3.new(0, walkY - 0.3, 4.05)), Vector3.new(10, 0.2, 0.12), HAZARD, SMOOTH, GLOW)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(m, CFrame.new(c + Vector3.new(sx * 4.6, (1.6 + walkY) / 2, sz * 3.6)), Vector3.new(0.4, walkY - 1.6, 0.4), STEEL_DARK, METAL, DECOR)
			blk(m, CFrame.new(c + Vector3.new(sx * 4.8, walkY + 1.2, sz * 3.8)), Vector3.new(0.3, 2.4, 0.3), STEEL, METAL, DECOR)
		end
		blk(m, CFrame.new(c + Vector3.new(sx * 4.8, walkY + 2.4, 0)), Vector3.new(0.26, 0.26, 7.6), SILVER, METAL, DECOR)
	end
	blk(m, CFrame.new(c + Vector3.new(0, walkY + 2.4, 3.8)), Vector3.new(9.6, 0.26, 0.26), SILVER, METAL, DECOR)
	-- a ladder up the front
	for k = 1, 5 do
		blk(m, CFrame.new(c + Vector3.new(3.2, 1.6 + k * 1.3, 4.15)), Vector3.new(1.4, 0.16, 0.16), STEEL, METAL, DECOR)
	end
	for _, lx in { 2.5, 3.9 } do
		blk(m, CFrame.new(c + Vector3.new(lx, (1.6 + walkY) / 2, 4.15)), Vector3.new(0.18, walkY - 1.6, 0.18), STEEL_DARK, METAL, DECOR)
	end
	-- capacitor tanks on both sides with glowing windows, cables to the tower
	for _, sx in { -1, 1 } do
		local t = c + Vector3.new(sx * 12, 0, -1)
		cyl(m, CFrame.new(t + Vector3.new(0, 0.3, 0)), 0.6, 5.8, STEEL_DARK, METAL, BUMP)
		cyl(m, CFrame.new(t + Vector3.new(0, 4.6, 0)), 8, 5, STEEL, METAL, BUMP)
		for _, y in { 2.2, 7.6 } do
			cyl(m, CFrame.new(t + Vector3.new(0, y, 0)), 0.5, 5.3, COPPER, METAL, DECOR)
		end
		cyl(m, CFrame.new(t + Vector3.new(0, 9.0, 0)), 0.8, 3.8, SILVER, METAL, DECOR)
		blk(m, CFrame.new(t + Vector3.new(0, 4.9, 2.45)), Vector3.new(0.7, 3.8, 0.2), STORM, NEON, GLOW)
		bar(m, t + Vector3.new(-sx * 1.6, 8.8, 0), c + Vector3.new(sx * 1.9, 14.2, 0), 0.5, rgb(30, 32, 48), SMOOTH, DECOR)
	end
	-- copper pipes along the path to the plaza
	for _, sx in { -1, 1 } do
		local z0, z1 = CATCHER.Y + 5, PLAZA.Y - PLAZA_R - 0.4
		cyl(m, CFrame.new(sx * 4.8, 0.45, (z0 + z1) / 2) * CFrame.Angles(math.pi / 2, 0, 0), z1 - z0, 0.8, COPPER, METAL, DECOR)
		for _, z in { z0 + 1.5, z1 - 1.5 } do
			cyl(m, CFrame.new(sx * 4.8, 0.45, z) * CFrame.Angles(math.pi / 2, 0, 0), 0.4, 1.15, COPPER_DARK, METAL, DECOR)
		end
	end
	-- the gauge panel on the back wall
	local panel = CFrame.new(CATCHER.X, 10, IN_BACK + 0.4)
	blk(m, panel, Vector3.new(24, 13, 0.8), STEEL_DARK, METAL, DECOR)
	blk(m, panel * CFrame.new(0, 6.6, 0.2), Vector3.new(24.6, 0.6, 1.2), STEEL, METAL, DECOR)
	for k = -1, 1 do
		local g = panel * CFrame.new(k * 7.5, 2.2, 0.45)
		cyl(m, g * CFrame.Angles(math.pi / 2, 0, 0), 0.2, 3.2, SILVER, METAL, DECOR)
		blk(m, g * CFrame.new(0.4, 0.4, 0.12) * CFrame.Angles(0, 0, -0.8 + k * 0.5), Vector3.new(0.16, 1.3, 0.06), rgb(220, 60, 50), SMOOTH, GLOW)
		blk(m, panel * CFrame.new(k * 7.5, -2.6, 0.42), Vector3.new(2.2, 0.5, 0.1), if k == 0 then STORM else ARC_BLUE, NEON, GLOW)
	end
	return heart
end

---------------------------------------------------------------- side rain clouds and crystals

local function buildRainClouds(parent: Instance, rng: Rng.Rng)
	local m = model("RainClouds", parent)
	-- (no lights: the rain's neon and the clouds' glowing bellies carry them)
	for _, p in { Vector3.new(-42, 35, 28), Vector3.new(44, 36, -34), Vector3.new(-46, 37, -36) } do
		puff(m, p, 0.72, rng:range(0, math.pi), rng)
		rain(m, p, Vector2.new(7, 5), 9, 7, 16, rng)
	end
end

local function buildCrystals(parent: Instance): { BasePart }
	local m = model("Crystals", parent)
	local A = CFrame.Angles
	-- { x, y, z, tilt, count, height, look, light? }
	local list: { { any } } = {
		-- the deep back corners: big stormglass clusters
		{ -57.5, 0, -50, A(0.3, 0, -0.3), 7, 8.5, "Storm", true },
		{ 57.5, 0, -50, A(0.35, 0, 0.3), 7, 9, "Storm", false },
		{ -22, 0, -53, A(0.2, 0, 0.2), 5, 5.5, "Storm", false },
		{ 23, 0, -53, A(0.2, 0, -0.2), 5, 5, "Storm", false },
		-- out of the side walls
		{ -60, 3, -24, A(0, 0, -0.6), 5, 6, "Storm", false },
		{ 60, 3, 8, A(0, 0, 0.6), 5, 6, "Storm", false },
		{ -60, 2, 20, A(0, 0, -0.5), 4, 4.5, "Storm", false },
		{ 60, 2, -40, A(0, 0, 0.5), 4, 5, "Storm", false },
		-- by the rift's ends and near the landing
		{ -58, 0, 15, A(0.2, 0, -0.25), 4, 4, "Storm", false },
		{ 58, 0, -1, A(-0.2, 0, 0.25), 4, 4.2, "Storm", false },
		{ -56, DECK_Y, 54, A(-0.2, 0, -0.2), 4, 4.5, "Storm", false },
		{ 57, DECK_Y, 54, A(-0.2, 0, 0.2), 4, 4.5, "Storm", false },
	}
	local hosts: { BasePart } = {}
	for i, k in list do
		local root = CFrame.new(k[1] :: number, k[2] :: number, k[3] :: number) * (k[4] :: CFrame)
		local cluster = MineKit.crystals(m, O * root, k[5] :: number, k[6] :: number, k[7] :: string, { STORM, SPARK }, "storm-" .. i)
		if k[8] then
			table.insert(hosts, lightAt(cluster, (root * CFrame.new(0, (k[6] :: number) * 0.5, 0)).Position, STORM, 22, 1.2))
		end
	end
	-- clusters hanging from the ceiling in the back half
	for i, p in { { -34, -30 }, { 34, -12 }, { -12, -44 }, { 26, -46 } } do
		MineKit.crystals(m, O * CFrame.new(p[1], CEIL - 0.4, p[2]) * A(math.pi + 0.12 * i, 0, 0.1), 4, 4.5, "Storm", { STORM, SPARK }, "storm-ceiling-" .. i)
	end
	return hosts
end

---------------------------------------------------------------- build

function Floor.build(parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	O = origin
	local cutaway = opts ~= nil and opts.Cutaway == true
	local rng = Rng.new("StormglassRift")
	local m = Instance.new("Model")
	m.Name = "MineFloor" .. Floor.Index
	m:SetAttribute("Floor", Floor.Index)
	m:SetAttribute("FloorId", Floor.Id)

	buildGround(m, rng)
	buildRift(m, rng)
	buildWalls(m, rng, cutaway)
	buildCeiling(m, rng, cutaway)
	buildLanding(m, rng)
	local plaza = buildPlaza(m)
	buildCrown(m, plaza, rng)
	local arcs = buildPylonPairs(m, rng)
	local heart = buildCatcher(m, rng)
	buildRainClouds(m, rng)
	local litClusters = buildCrystals(m)
	-- a soft cool wash over each field
	local wash = model("Wash", m)
	lightAt(wash, Vector3.new(0, 26, 28), rgb(190, 200, 255), 60, 1.5)
	lightAt(wash, Vector3.new(0, 24, -38), rgb(190, 200, 255), 60, 1.4)

	-- gameplay pieces: the elevator (the only way in), the gate, the ore lift
	MineKit.elevator(m, O * CFrame.new(-28, DECK_Y, 48.5) * CFrame.Angles(0, -math.pi / 2, 0), Floor.Index)
	MineKit.gate(m, O * CFrame.new(0, DECK_Y, DECK_Z + 0.9) * CFrame.Angles(0, math.pi, 0), 14, Floor.MinBlaster, { STEEL, COPPER, STEEL_DARK })
	-- in the game only its spot (Railway builds the lift from TrainConfig), the preview shows it
	MineKit.oreLift(m, O * LIFT_SPOT, Floor.Id)

	-- markers and rock spawns
	local entrance = MineKit.marker(m, "Entrance", O * CFrame.new(0, DECK_Y, 48.5))
	entrance:SetAttribute("Floor", Floor.Index)
	MineKit.marker(m, "GiantSpawn", O * CFrame.new(PLAZA.X, PLAZA_TOP, PLAZA.Y))
	local spawns = MineKit.spawns(m)
	for _, s in SPAWNS do
		spawns.add(O * CFrame.new(s[1], 0, s[2]), false)
	end
	for _, s in DEEP_SPAWNS do
		spawns.add(O * CFrame.new(s[1], 0, s[2]), true)
	end

	-- ambience (Config/MineAmbience: tagged Attachments, no parts): the hum of the Giant
	-- Crystal's plaza and of the big stormglass cluster in the back left corner, sparks
	-- crackling on a plaza pylon, at the rift's tesla pair and at the storm catcher's heart,
	-- thunder rolling under the Storm Crown
	MineKit.ambience(plaza.Top, "CrystalHum", O * Vector3.new(PLAZA.X, 3, PLAZA.Y))
	if litClusters[1] then
		MineKit.ambience(litClusters[1], "CrystalHum", litClusters[1].CFrame.Position)
	end
	MineKit.ambience(plaza.Rings[2], "StormCrackle", plaza.Rings[2].CFrame.Position)
	MineKit.ambienceNear(m, "StormCrackle", O * arcs[2])
	MineKit.ambience(heart, "StormCrackle", heart.CFrame.Position)
	MineKit.ambienceNear(m, "MineRumble", O * v3(PLAZA, CEIL - 4))

	m.Parent = parent
	return m
end

return Floor
