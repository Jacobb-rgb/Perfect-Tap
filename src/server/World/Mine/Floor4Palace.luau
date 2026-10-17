--[[
	Mine floor 4: THE SUNKEN PALACE OF KALDRUM (blaster 7+, reached only by the
	elevator). docs/plans/MINE_FLOORS_PLAN.md, story in docs/DESIGN_V2_NOTES.md.

	The ruined throne hall of the Ember Kings, sunk deep into the rock by the
	Shattering. Players step out of the elevator onto an arrival terrace at the
	front (+Z), pass the blaster gate and walk down the stairs into the hall:

	  - a checkered violet/cream tile floor with cracks, heaved tiles, a raised
	    kerb along the walls and shallow puddles of glowing water
	  - two rows of tall marble columns with gold bases and capitals and broken
	    arches between them; one column fell across the left front corner, one
	    snapped and lies in pieces at its foot
	  - carved violet walls (dado, pilasters, cornice, blind niches, red and
	    gold royal banners) with cave rock pushing in through two bays and
	    growing over every cornice, a rough rock ceiling with stalactites
	  - at the back a stepped dais under a grand arch with the Ember King: the
	    vault's giant stone king statue (Lobby/Vault/Statue, smaller) on its pedestal
	    (owner, 2026-10-17), replacing the earlier broken golden throne
	    and a huge cracked statue of an Ember King (crowned, a Heartstone on his
	    chest, the scepter in one hand, the other arm broken off) in front of a
	    golden halo, braziers with warm fire on both sides
	  - gold and lavender crystals (MineKit.crystals "Shell") growing through
	    the floor and walls, richest in the deep back corners
	  - a gold rune circle in the middle of the hall (the Giant Crystal's spot)
	    and a lavender one on the terrace where players arrive

	Layout (local to `origin`, ground y = 0): footprint 132 x 112, walls 4
	thick (inner faces x = +-62, z = -52 back, z = +52 front), ceiling at 40.
	Terrace z 38..52 at y 2.4 (elevator left, ore lift right, gate + stairs in
	the middle). 24 rock spawns in the side aisles (x +-34 / +-49) and the nave,
	9 of them deep (z < -18). About 2300 parts, 18 PointLights, 6 emitters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local MineKit = require(World:WaitForChild("Mine"):WaitForChild("MineKit"))
local VaultStatue = require(World:WaitForChild("Lobby"):WaitForChild("Vault"):WaitForChild("Statue"))

local Floor = {}

Floor.Index = 4
Floor.Size = Vector3.new(132, 44, 112)

---------------------------------------------------------------- palette

local rgb = Color3.fromRGB
local PAL = MineFloors.get(4).Palette

local STONE = PAL.Mid
local STONE_LIGHT = PAL.Light
local STONE_DARK = PAL.Dark
local GOLD = PAL.Accent
local GOLD_DARK = rgb(184, 128, 40)
local GOLD_GLOW = rgb(255, 204, 90)
local CRYSTALS = { PAL.Crystal, PAL.Crystal2 }
local CRYSTALS_LAVENDER = { PAL.Crystal2, PAL.Crystal }

local TILE_CREAM = rgb(222, 204, 192)
local TILE_VIOLET = rgb(92, 72, 134)
local GROUT = rgb(52, 40, 76)
local WALL = rgb(88, 72, 124)
local WALL_DARK = rgb(60, 46, 88)
local WALL_DEEP = rgb(32, 24, 52)
local MARBLE = rgb(216, 204, 230)
local MARBLE_DARK = rgb(166, 150, 192)
local RED = rgb(182, 34, 56)
local RED_DARK = rgb(120, 22, 40)
local FIRE = rgb(255, 140, 40)
local FIRE_CORE = rgb(255, 216, 128)
local EMBER = rgb(255, 104, 40)
local WATER = rgb(118, 96, 236)
local WET = rgb(46, 36, 78)
local RUNE_GOLD = rgb(255, 202, 84)
local RUNE_LAVENDER = rgb(196, 172, 255)
local CAVE = { rgb(94, 80, 128), rgb(128, 114, 162), rgb(62, 52, 90) }
local CEILING = rgb(52, 44, 76)
local LIFT_STEEL = rgb(118, 130, 186)
local LIFT_STEEL_DARK = rgb(62, 68, 102)

local NEON = Enum.Material.Neon

-- walkable / solid, bump-into decoration, overhead decoration, tiny glow bits
local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local BUMP = { CanTouch = false, CanQuery = false, CanCollide = true }
local DECOR = { CanTouch = false, CanQuery = false, CanCollide = false }
local TINY = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local WATER_PROPS = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 0.4 }

---------------------------------------------------------------- layout

local IN_X = 62 -- inner face of the side walls
local IN_BACK = -52 -- inner face of the back wall
local IN_FRONT = 52 -- inner face of the front wall
local HEIGHT = 44
local CEIL = 40 -- underside of the ceiling
local TERRACE_Z = 38 -- front edge of the arrival terrace
local TERRACE_Y = 2.4
local COL_X = 22
local COL_Z = { 26, 10, -6, -22, -38 }
local COL_H = 30 -- top of a full column's capital
local GIANT = Vector2.new(0, 4)

-- rock spawns (x, z) at ground height: front half, then the deep back third
local SPAWNS = {
	{ 49, 30 },
	{ 34, 22 },
	{ 49, 14 },
	{ 34, 6 },
	{ 49, -2 },
	{ 34, -10 },
	{ -34, 20 },
	{ -49, 14 },
	{ -34, 4 },
	{ -49, -2 },
	{ -34, -12 },
	{ 11, 24 },
	{ -11, 20 },
	{ 11, -10 },
}
local DEEP_SPAWNS = {
	{ 34, -24 },
	{ 49, -28 },
	{ 36, -40 },
	{ 49, -42 },
	{ -42, -20 },
	{ -49, -28 },
	{ -34, -30 },
	{ -48, -40 },
	{ -36, -41 },
	{ -11, -20 },
}

---------------------------------------------------------------- helpers

type Ctx = {
	origin: CFrame,
	rng: Rng.Rng,
	cutaway: boolean,
}

local function at(c: Ctx, x: number, y: number, z: number): CFrame
	return c.origin * CFrame.new(x, y, z)
end

local function pt(c: Ctx, x: number, y: number, z: number): Vector3
	return c.origin:PointToWorldSpace(Vector3.new(x, y, z))
end

local function dir(c: Ctx, x: number, y: number, z: number): Vector3
	return c.origin:VectorToWorldSpace(Vector3.new(x, y, z))
end

local function group(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function pointLight(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
	return l
end

-- An invisible holder part with a PointLight (light where no glowing part is).
local function lightAt(parent: Instance, cf: CFrame, color: Color3, range: number, brightness: number): PointLight
	local holder = Geo.block(parent, cf, Vector3.new(0.2, 0.2, 0.2), color, nil, {
		Transparency = 1,
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	})
	holder.Name = "LightHolder"
	return pointLight(holder, color, range, brightness)
end

local function sparkle(part: BasePart, color: Color3, rate: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Speed = NumberRange.new(0.6, 1.6)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = Vector3.new(0, 1.2, 0)
	e.Rate = rate
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = part
	return e
end

--[[
	A ring of blocks along a circular arc in the local XY plane of `center`
	spanning local X with depth along local Z, from angle a0 to a1 (radians,
	0 = local +X, pi/2 = up). The middle segment of an odd count is the
	keystone in `keyColor`. `skip` leaves segments out (broken arches).
]]
local function arc(
	parent: Instance,
	center: CFrame,
	radius: number,
	a0: number,
	a1: number,
	segments: number,
	thick: number,
	depth: number,
	color: Color3,
	keyColor: Color3?,
	skip: { [number]: boolean }?
)
	local step = (a1 - a0) / segments
	local chord = 2 * radius * math.sin(step / 2) + 0.14
	local key = if segments % 2 == 1 and keyColor ~= nil then (segments + 1) / 2 else -1
	local kc: Color3 = keyColor or color
	for k = 1, segments do
		if not (skip and skip[k]) then
			local a = a0 + step * (k - 0.5)
			local cf = center * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
			if k == key then
				Geo.block(parent, cf, Vector3.new(chord * 0.9, thick + 0.4, depth + 0.3), kc, nil, DECOR)
			else
				Geo.block(parent, cf, Vector3.new(chord, thick, depth), color, nil, DECOR)
			end
		end
	end
end

-- A thin zig-zag crack on the floor from (x, z); glowing cracks are neon.
local function crack(parent: Instance, c: Ctx, x: number, z: number, angle: number, segs: number, len: number, color: Color3, glow: boolean)
	local px, pz, a = x, z, angle
	local width = if glow then 0.22 else 0.18
	for _ = 1, segs do
		local l = len * c.rng:range(0.6, 1.1)
		local nx, nz = px + math.cos(a) * l, pz + math.sin(a) * l
		local cf = at(c, (px + nx) / 2, 0.115, (pz + nz) / 2) * CFrame.Angles(0, -a, 0)
		Geo.block(parent, cf, Vector3.new(l + 0.12, 0.05, width), color, if glow then NEON else nil, TINY)
		px, pz = nx, nz
		a += c.rng:range(-0.75, 0.75)
	end
end

-- A small pile of stone chips around (x, y, z).
local function rubble(parent: Instance, c: Ctx, x: number, y: number, z: number, count: number, colors: { Color3 }, scale: number)
	for i = 1, count do
		local s = scale * c.rng:range(0.5, 1.1)
		local px = x + c.rng:range(-1.6, 1.6) * scale
		local pz = z + c.rng:range(-1.6, 1.6) * scale
		local cf = at(c, px, y + s * 0.3, pz) * Geo.randomTilt(c.rng, 0.5)
		Geo.block(parent, cf, Vector3.new(s, s * 0.7, s * 0.9), Geo.vary(colors[(i - 1) % #colors + 1], c.rng, 0.05), nil, DECOR)
	end
end

-- Spawn positions as Vector2s, so decorations can keep away from the rocks.
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

local function nearSpawn(points: { Vector2 }, x: number, z: number, distance: number): boolean
	local p = Vector2.new(x, z)
	for _, s in points do
		if (s - p).Magnitude < distance then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- floor

local function buildFloor(parent: Instance, c: Ctx)
	local m = group("TileFloor", parent)
	local points = spawnPoints()
	local hallDepth = TERRACE_Z - IN_BACK
	local hallMid = (TERRACE_Z + IN_BACK) / 2
	-- the cream tiles are the floor slab itself; violet tiles lie on it in a checker
	local slab = Geo.block(m, at(c, 0, -1, hallMid), Vector3.new(IN_X * 2, 2, hallDepth), TILE_CREAM, nil, SOLID)
	slab.Name = "Ground"
	local tile = 6
	for i = 0, 19 do
		for j = 0, 14 do
			local x = -60 + tile * i + tile / 2
			local z = IN_BACK + tile * j + tile / 2
			local underDais = math.abs(x) < 18 and z < -30
			local free = not nearSpawn(points, x, z, 5.5) and not underDais
			local roll = c.rng:next()
			if (i + j) % 2 == 0 and not underDais then
				local color = Geo.vary(TILE_VIOLET, c.rng, 0.035)
				if free and roll < 0.07 then
					-- a broken tile: two halves, one sunk and tilted
					local alongX = c.rng:chance(0.5)
					for _, side in { -1, 1 } do
						local off = if alongX then Vector3.new(side * 1.5, 0, 0) else Vector3.new(0, 0, side * 1.5)
						local size = if alongX then Vector3.new(2.9, 0.12, 5.9) else Vector3.new(5.9, 0.12, 2.9)
						local tilt = if side < 0 then CFrame.Angles(c.rng:range(-0.04, 0.04), 0, c.rng:range(-0.05, 0.05)) else CFrame.new()
						Geo.block(m, at(c, x + off.X, 0.03, z + off.Z) * tilt, size, color, nil, TINY)
					end
				elseif free and roll < 0.1 then
					-- a missing tile: a dark hole with a chip in it
					Geo.block(m, at(c, x, 0.02, z), Vector3.new(5.9, 0.06, 5.9), WALL_DEEP, nil, TINY)
					Geo.block(
						m,
						at(c, x + c.rng:range(-1.5, 1.5), 0.1, z + c.rng:range(-1.5, 1.5)) * Geo.randomTilt(c.rng, 0.2),
						Vector3.new(1.6, 0.4, 1.2),
						color,
						nil,
						TINY
					)
				else
					Geo.block(m, at(c, x, 0.03, z), Vector3.new(5.9, 0.06, 5.9), color, nil, TINY)
				end
			elseif (i + j) % 2 == 1 and free and roll < 0.05 then
				-- a heaved cream tile: one edge pushed up by the sinking
				local tilt = CFrame.Angles(c.rng:range(0.05, 0.09) * (if c.rng:chance(0.5) then 1 else -1), 0, c.rng:range(-0.06, 0.06))
				Geo.block(m, at(c, x, 0.12, z) * tilt, Vector3.new(5.8, 0.4, 5.8), Geo.vary(TILE_CREAM, c.rng, 0.04), nil, SOLID)
			end
		end
	end
	-- grout lines
	for i = 0, 20 do
		Geo.block(m, at(c, -60 + tile * i, 0.05, hallMid), Vector3.new(0.22, 0.1, hallDepth), GROUT, nil, TINY)
	end
	for j = 0, 15 do
		Geo.block(m, at(c, 0, 0.05, IN_BACK + tile * j), Vector3.new(120, 0.1, 0.22), GROUT, nil, TINY)
	end
	-- the raised kerb along the walls with a gold edge
	for _, sx in { -1, 1 } do
		Geo.block(m, at(c, sx * 60.5, 0.3, hallMid), Vector3.new(3, 0.6, hallDepth), STONE, nil, SOLID)
		Geo.block(m, at(c, sx * 59.2, 0.62, hallMid), Vector3.new(0.4, 0.1, hallDepth), GOLD, nil, TINY)
		Geo.block(m, at(c, sx * 38.5, 0.3, IN_BACK + 1.5), Vector3.new(41, 0.6, 3), STONE, nil, SOLID)
		Geo.block(m, at(c, sx * 38.6, 0.62, IN_BACK + 2.8), Vector3.new(40.8, 0.1, 0.4), GOLD, nil, TINY)
	end
	-- cracks: dark ones across the hall, glowing gold ones near the crystals
	local cracks = {
		{ -26, 14, 0.6 },
		{ 26, -2, 2.6 },
		{ -20, -30, -0.4 },
		{ 18, 30, 3.6 },
		{ -42, -12, 1.2 },
		{ 42, 4, -1.8 },
		{ -6, -24, 0.2 },
		{ 30, -32, 2.2 },
		{ -54, 24, -0.9 },
		{ 54, -14, 2.9 },
		{ -14, 32, -1.3 },
		{ 16, -16, 1.5 },
	}
	for _, k in cracks do
		crack(m, c, k[1], k[2], k[3], c.rng:int(3, 5), 2.6, GROUT, false)
	end
	local glowCracks = {
		{ -54, -44, 0.5 },
		{ 54, -44, 2.6 },
		{ -20, -44, 1.9 },
		{ 20, -44, 1.2 },
		{ 54, 18, 3.3 },
		{ -54, -14, -0.2 },
		{ -9, 10, 2.2 },
		{ 9, -2, -0.9 },
	}
	for _, k in glowCracks do
		crack(m, c, k[1], k[2], k[3], c.rng:int(3, 4), 2.4, PAL.Crystal, true)
	end
end

-- A flat disc lying on the floor (a cylinder with a vertical axis).
local function disc(
	parent: Instance,
	c: Ctx,
	x: number,
	y: number,
	z: number,
	diameter: number,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }
): Part
	local p =
		Geo.block(parent, at(c, x, y, z) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(thick, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A shallow round puddle of glowing water on a dark wet stain, with a smaller pool beside it.
local function puddle(parent: Instance, c: Ctx, x: number, z: number, size: number, withLight: boolean)
	local a = c.rng:range(0, math.pi * 2)
	local ox, oz = math.cos(a) * size * 0.55, math.sin(a) * size * 0.55
	disc(parent, c, x, 0.09, z, size * 1.25, 0.06, WET, nil, TINY)
	disc(parent, c, x + ox, 0.095, z + oz, size * 0.8, 0.06, WET, nil, TINY)
	local w = disc(parent, c, x, 0.13, z, size, 0.05, WATER, NEON, WATER_PROPS)
	w.Name = "Water"
	disc(parent, c, x + ox, 0.14, z + oz, size * 0.6, 0.05, WATER, NEON, WATER_PROPS)
	if withLight then
		pointLight(w, WATER, 14, 1.1)
	end
end

-- A glowing rune circle on the floor: two rings, rune marks and a star.
local function runeCircle(parent: Instance, c: Ctx, x: number, y: number, z: number, radius: number, color: Color3): BasePart
	local m = group("RuneCircle", parent)
	local center = at(c, x, y + 0.14, z)
	local function ring(r: number, n: number, width: number)
		local chord = 2 * r * math.sin(math.pi / n) + 0.1
		for k = 1, n do
			local a = (k - 0.5) / n * math.pi * 2
			Geo.block(
				m,
				center * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0),
				Vector3.new(chord, 0.06, width),
				color,
				NEON,
				TINY
			)
		end
	end
	local outer = math.clamp(math.floor(radius * 1.8), 10, 18)
	ring(radius, outer, 0.4)
	ring(radius * 0.74, math.max(8, math.floor(outer * 0.75)), 0.25)
	local marks = math.floor(outer / 2)
	for k = 1, marks do
		local a = k / marks * math.pi * 2
		local r = radius * 0.87
		Geo.block(
			m,
			center * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 4, 0),
			Vector3.new(radius * 0.09, 0.06, radius * 0.09),
			color,
			NEON,
			TINY
		)
	end
	-- a four-point star inside
	for _, a in { 0, math.pi / 2 } do
		Geo.block(m, center * CFrame.Angles(0, a, 0), Vector3.new(radius * 1.4, 0.05, 0.22), color, NEON, TINY)
	end
	local core = Geo.block(
		m,
		center * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(radius * 0.26, 0.07, radius * 0.26),
		color:Lerp(Color3.new(1, 1, 1), 0.3),
		NEON,
		TINY
	)
	core.Name = "RuneCore"
	return core
end

---------------------------------------------------------------- walls

-- A royal banner: gold rod, red cloth with a swallowtail, gold borders, a
-- Heartstone emblem under a crown. `top` = rod center, LookVector = out of the wall.
local function banner(parent: Instance, top: CFrame, width: number, length: number, torn: boolean)
	local m = group("Banner", parent)
	local tail = width * 0.45
	local body = if torn then length * 0.78 else length - tail
	Geo.block(m, top, Vector3.new(width + 1.4, 0.45, 0.45), GOLD, nil, TINY)
	for _, sx in { -1, 1 } do
		Geo.block(m, top * CFrame.new(sx * (width / 2 + 0.85), 0, 0), Vector3.new(0.7, 0.7, 0.7), GOLD_DARK, nil, TINY)
	end
	local cloth = top * CFrame.new(0, -0.25, 0)
	Geo.block(m, cloth * CFrame.new(0, -body / 2, 0), Vector3.new(width, body, 0.25), RED, nil, DECOR)
	if torn then
		-- a ragged end: two uneven shreds
		Geo.block(
			m,
			cloth * CFrame.new(-width * 0.22, -body - 0.9, 0) * CFrame.Angles(0, 0, 0.12),
			Vector3.new(width * 0.4, 2, 0.25),
			RED,
			nil,
			DECOR
		)
		Geo.block(
			m,
			cloth * CFrame.new(width * 0.27, -body - 0.5, 0) * CFrame.Angles(0, 0, -0.2),
			Vector3.new(width * 0.3, 1.2, 0.25),
			RED_DARK,
			nil,
			DECOR
		)
	else
		local yb = -body
		Geo.wedge(
			m,
			cloth * CFrame.new(-width / 4, yb - tail / 2, 0) * CFrame.Angles(0, 0, math.pi) * CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new(0.25, tail, width / 2),
			RED,
			nil,
			DECOR
		)
		Geo.wedge(
			m,
			cloth * CFrame.new(width / 4, yb - tail / 2, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new(0.25, tail, width / 2),
			RED,
			nil,
			DECOR
		)
	end
	-- gold borders and the top band
	for _, sx in { -1, 1 } do
		Geo.block(m, cloth * CFrame.new(sx * (width / 2 - 0.2), -body / 2, -0.1), Vector3.new(0.4, body, 0.2), GOLD, nil, TINY)
	end
	Geo.block(m, cloth * CFrame.new(0, -0.9, -0.1), Vector3.new(width, 0.5, 0.2), GOLD, nil, TINY)
	-- the emblem: a Heartstone in a gold diamond under a crown
	local e = cloth * CFrame.new(0, -body * 0.45, -0.14)
	local s = width * 0.36
	Geo.block(m, e * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s, s, 0.2), GOLD, nil, TINY)
	Geo.block(m, e * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s * 0.55, s * 0.55, 0.2), EMBER, NEON, TINY)
	Geo.block(m, e * CFrame.new(0, s * 0.95, 0), Vector3.new(s * 1.1, s * 0.25, 0.2), GOLD, nil, TINY)
	for _, sx in { -1, 0, 1 } do
		Geo.block(
			m,
			e * CFrame.new(sx * s * 0.42, s * 1.22, 0),
			Vector3.new(s * 0.2, s * (if sx == 0 then 0.42 else 0.32), 0.2),
			GOLD,
			nil,
			TINY
		)
	end
end

-- A blind niche: dark recess, stone jambs and sill, an arched top with a gold
-- keystone. `cf` = bottom center on the wall face, LookVector = out of the wall.
local function niche(parent: Instance, cf: CFrame, w: number, h: number)
	local m = group("Niche", parent)
	Geo.block(m, cf * CFrame.new(0, h / 2, -0.12), Vector3.new(w, h, 0.24), WALL_DEEP, nil, TINY)
	Geo.block(m, cf * CFrame.new(0, h + w * 0.13, -0.12), Vector3.new(w * 0.9, w * 0.26, 0.24), WALL_DEEP, nil, TINY)
	Geo.block(m, cf * CFrame.new(0, h + w * 0.34, -0.12), Vector3.new(w * 0.55, w * 0.18, 0.24), WALL_DEEP, nil, TINY)
	for _, sx in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(sx * (w / 2 + 0.35), h / 2, -0.35), Vector3.new(0.7, h, 0.7), STONE_LIGHT, nil, DECOR)
	end
	Geo.block(m, cf * CFrame.new(0, -0.25, -0.5), Vector3.new(w + 1.6, 0.5, 1), STONE_LIGHT, nil, DECOR)
	arc(m, cf * CFrame.new(0, h, -0.35), w / 2 + 0.35, 0, math.pi, 5, 0.7, 0.7, STONE_LIGHT, GOLD)
end

-- A wall torch: gold plate and arm with a neon flame in a cup.
-- `cf` = mount point on the wall (or pilaster) face, LookVector = out of the wall.
local function sconce(parent: Instance, cf: CFrame, withLight: boolean)
	local m = group("Sconce", parent)
	Geo.block(m, cf * CFrame.new(0, 0, -0.15), Vector3.new(0.9, 1.8, 0.3), GOLD_DARK, nil, TINY)
	Geo.block(m, cf * CFrame.new(0, -0.3, -0.75), Vector3.new(0.35, 0.35, 1.2), GOLD, nil, TINY)
	Geo.block(m, cf * CFrame.new(0, 0, -1.4), Vector3.new(1.0, 0.5, 1.0), GOLD, nil, TINY)
	local flame =
		Geo.block(m, cf * CFrame.new(0, 0.75, -1.4) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.65, 1.1, 0.65), FIRE, NEON, TINY)
	flame.Name = "Flame"
	Geo.block(m, cf * CFrame.new(0.05, 0.95, -1.4), Vector3.new(0.32, 0.7, 0.32), FIRE_CORE, NEON, TINY)
	if withLight then
		pointLight(flame, FIRE, 26, 1.3)
	end
end

-- The carved face of a wall: dado, gold trims, pilasters and the cornice.
-- `face` = wall face frame at ground level (LookVector out of the wall, local X along it),
-- `pilasters` = local X positions, `segments` = { {x0, x1} } spans of dado/cornice.
local function wallFace(parent: Instance, face: CFrame, pilasters: { number }, segments: { { number } })
	for _, s in segments do
		local mid = (s[1] + s[2]) / 2
		local len = s[2] - s[1]
		Geo.block(parent, face * CFrame.new(mid, 2.2, -0.3), Vector3.new(len, 4.4, 0.6), WALL_DARK, nil, BUMP)
		Geo.block(parent, face * CFrame.new(mid, 4.55, -0.45), Vector3.new(len, 0.35, 0.9), GOLD, nil, TINY)
		Geo.block(parent, face * CFrame.new(mid, 26.6, -0.9), Vector3.new(len, 1.2, 1.8), STONE_LIGHT, nil, DECOR)
		Geo.block(parent, face * CFrame.new(mid, 25.85, -1.0), Vector3.new(len, 0.3, 2.0), GOLD, nil, TINY)
	end
	for _, x in pilasters do
		Geo.block(parent, face * CFrame.new(x, 13, -0.8), Vector3.new(3.2, 26, 1.6), STONE, nil, BUMP)
		Geo.block(parent, face * CFrame.new(x, 4.9, -1.0), Vector3.new(3.6, 0.6, 2.0), GOLD, nil, TINY)
		Geo.block(parent, face * CFrame.new(x, 24.9, -1.05), Vector3.new(4.0, 0.4, 2.1), GOLD, nil, TINY)
	end
end

local function buildWalls(parent: Instance, c: Ctx)
	local m = group("Walls", parent)
	local rng = c.rng
	-- side walls
	for _, sx in { -1, 1 } do
		Geo.block(m, at(c, sx * (IN_X + 2), HEIGHT / 2, 0), Vector3.new(4, HEIGHT, IN_FRONT * 2 + 8), WALL, nil, SOLID)
		local face = at(c, sx * IN_X, 0, 0) * CFrame.Angles(0, sx * math.pi / 2, 0)
		-- in this frame local X runs along -Z on the right wall and +Z on the left wall
		local function lx(z: number): number
			return if sx > 0 then -z else z
		end
		local pil = {}
		for _, z in { 44, 26, 10, -6, -22, -38 } do
			table.insert(pil, lx(z))
		end
		wallFace(m, face, pil, { { -IN_FRONT, IN_FRONT } })
		-- cave rock grows over the cornice
		MineKit.wall(
			m,
			pt(c, sx * (IN_X - 1.6), 27.2, IN_FRONT),
			pt(c, sx * (IN_X - 1.6), 27.2, IN_BACK),
			14,
			dir(c, -sx, 0, 0),
			CAVE,
			rng,
			{ Depth = 5 }
		)
	end
	-- side wall bays: banners, niches, rock pushing in
	local function sideFrame(sx: number, z: number, y: number): CFrame
		return at(c, sx * IN_X, y, z) * CFrame.Angles(0, sx * math.pi / 2, 0)
	end
	banner(m, sideFrame(-1, 18, 24) * CFrame.new(0, 0, -0.5), 5.5, 16, true)
	banner(m, sideFrame(-1, -30, 24) * CFrame.new(0, 0, -0.5), 5.5, 17, false)
	banner(m, sideFrame(1, 32, 24) * CFrame.new(0, 0, -0.5), 5.5, 17, false)
	banner(m, sideFrame(1, 2, 24) * CFrame.new(0, 0, -0.5), 5.5, 17, false)
	banner(m, sideFrame(1, -30, 24) * CFrame.new(0, 0, -0.5), 5.5, 15, true)
	niche(m, sideFrame(-1, 32, 6.5) * CFrame.new(0, 0, -0.6), 6, 11)
	niche(m, sideFrame(-1, 2, 6.5) * CFrame.new(0, 0, -0.6), 6, 11)
	niche(m, sideFrame(-1, -45, 6.5) * CFrame.new(0, 0, -0.6), 6, 11)
	niche(m, sideFrame(1, -14, 6.5) * CFrame.new(0, 0, -0.6), 6, 11)
	niche(m, sideFrame(1, -45, 6.5) * CFrame.new(0, 0, -0.6), 6, 11)
	-- torches on the pilasters (not where the rock burst through)
	local torches = {
		{ sx = -1, z = 26, lit = false },
		{ sx = -1, z = 10, lit = true },
		{ sx = -1, z = -38, lit = true },
		{ sx = 1, z = -6, lit = true },
		{ sx = 1, z = -22, lit = true },
		{ sx = 1, z = -38, lit = false },
	}
	for _, t in torches do
		sconce(m, sideFrame(t.sx, t.z, 15) * CFrame.new(0, 0, -1.6), t.lit)
	end
	-- cave rock bursting through two bays (crystals grow out of it), boulders at its foot
	MineKit.wall(m, pt(c, 58.5, 0, 25), pt(c, 58.5, 0, 11), 29, dir(c, -1, 0, 0), CAVE, rng, { Depth = 6 })
	MineKit.wall(m, pt(c, -58.5, 0, -7), pt(c, -58.5, 0, -21), 29, dir(c, 1, 0, 0), CAVE, rng, { Depth = 6 })
	for _, b in { { 56.5, 22.5 }, { 57, 12.5 }, { -56.5, -9 }, { -57, -19.5 } } do
		Geo.rock(m, at(c, b[1], 0, b[2]), Vector3.new(4, 3.4, 4), Geo.vary(CAVE[1], rng, 0.05), rng, nil, BUMP)
	end

	-- back wall: carved face, the apse arch behind the statue, corner rock
	Geo.block(m, at(c, 0, HEIGHT / 2, IN_BACK - 2), Vector3.new(IN_X * 2, HEIGHT, 4), WALL, nil, SOLID)
	local back = at(c, 0, 0, IN_BACK) * CFrame.Angles(0, math.pi, 0)
	-- in this frame local X runs along world -X
	wallFace(m, back, { 26, 40, 54, -26, -40, -54 }, { { -IN_X, -14.6 }, { 14.6, IN_X } })
	for _, sx in { -1, 1 } do
		MineKit.wall(
			m,
			pt(c, sx * IN_X, 27.2, IN_BACK + 1.6),
			pt(c, sx * 15, 27.2, IN_BACK + 1.6),
			14,
			dir(c, 0, 0, 1),
			CAVE,
			rng,
			{ Depth = 5 }
		)
		banner(m, at(c, sx * 19.5, 25, IN_BACK + 0.5) * CFrame.Angles(0, math.pi, 0), 6.5, 19, false)
		niche(m, at(c, sx * 33, 6.5, IN_BACK + 0.6) * CFrame.Angles(0, math.pi, 0), 6.5, 11)
		sconce(m, at(c, sx * 26, 15, IN_BACK + 1.6) * CFrame.Angles(0, math.pi, 0), false)
		-- the back corners: rock pushing in behind the big crystals
		local x0, x1 = sx * 44, sx * 61
		MineKit.wall(m, pt(c, x0, 0.6, IN_BACK + 1.6), pt(c, x1, 0.6, IN_BACK + 1.6), 26, dir(c, 0, 0, 1), CAVE, rng, { Depth = 5 })
	end
	-- the apse: big pilasters, a dark recess, the great arch with a gold inner ring
	local apse = group("Apse", m)
	for _, sx in { -1, 1 } do
		Geo.block(apse, at(c, sx * 13, 13, IN_BACK + 1), Vector3.new(3.2, 26, 2), STONE_LIGHT, nil, BUMP)
		Geo.block(apse, at(c, sx * 13, 25.6, IN_BACK + 1.1), Vector3.new(3.8, 0.8, 2.4), GOLD, nil, DECOR)
		Geo.block(apse, at(c, sx * 13, 0.6, IN_BACK + 1.1), Vector3.new(3.8, 1.2, 2.4), STONE_DARK, nil, BUMP)
	end
	Geo.block(apse, at(c, 0, 13, IN_BACK + 0.15), Vector3.new(22.8, 26, 0.3), WALL_DEEP, nil, TINY)
	-- the recess under the arch, stepped to follow its curve (corners hide behind the ring)
	for k, hw in { 12.3, 11.5, 9.7, 6.0 } do
		Geo.block(apse, at(c, 0, 26 + 3.1 * (k - 0.5), IN_BACK + 0.15), Vector3.new(hw * 2, 3.1, 0.3), WALL_DEEP, nil, TINY)
	end
	arc(apse, at(c, 0, 26, IN_BACK + 1), 13, 0, math.pi, 9, 1.8, 2, STONE_LIGHT, GOLD)
	arc(apse, at(c, 0, 26, IN_BACK + 1.05), 12, 0, math.pi, 9, 0.35, 2.05, GOLD)
	-- the golden halo behind the statue's head
	local halo = at(c, 0, 27.5, IN_BACK + 0.35)
	for k = 0, 10 do
		local a = math.rad(-22 + k * 22.4)
		Geo.block(
			apse,
			halo * CFrame.new(math.cos(a) * 7.2, math.sin(a) * 7.2, 0) * CFrame.Angles(0, 0, a),
			Vector3.new(6, 0.5, 0.12),
			GOLD_GLOW,
			NEON,
			TINY
		)
	end
	arc(apse, halo, 4.2, math.rad(-30), math.rad(210), 10, 0.35, 0.14, GOLD_GLOW)
	lightAt(apse, at(c, 0, 26, IN_BACK + 13), GOLD_GLOW, 32, 1.5)

	-- front wall (left out for the cutaway pictures): a grand door choked with rubble
	if not c.cutaway then
		for _, sx in { -1, 1 } do
			Geo.block(m, at(c, sx * 34.5, HEIGHT / 2, IN_FRONT + 2), Vector3.new(55, HEIGHT, 4), WALL, nil, SOLID)
		end
		Geo.block(m, at(c, 0, 29, IN_FRONT + 2), Vector3.new(14, 30, 4), WALL, nil, SOLID)
		local front = at(c, 0, 0, IN_FRONT)
		wallFace(m, front, { -12, 12, -30, 30, -48, 48 }, { { -IN_X, -9.4 }, { 9.4, IN_X } })
		for _, sx in { -1, 1 } do
			Geo.block(m, front * CFrame.new(sx * 8.2, 8, -0.6), Vector3.new(2.4, 16, 1.2), STONE_LIGHT, nil, BUMP)
			banner(m, front * CFrame.new(sx * 20, 24, -0.5), 5.5, 15, false)
		end
		Geo.block(m, front * CFrame.new(0, 16.6, -0.6), Vector3.new(18.8, 1.6, 1.2), STONE_LIGHT, nil, DECOR)
		Geo.block(m, front * CFrame.new(0, 15.7, -1.25), Vector3.new(18.8, 0.3, 0.2), GOLD, nil, TINY)
		MineKit.wall(
			m,
			pt(c, -7, TERRACE_Y, IN_FRONT + 0.4),
			pt(c, 7, TERRACE_Y, IN_FRONT + 0.4),
			15,
			dir(c, 0, 0, -1),
			CAVE,
			rng,
			{ Depth = 3 }
		)
		MineKit.wall(
			m,
			pt(c, -IN_X, 27.2, IN_FRONT - 1.6),
			pt(c, IN_X, 27.2, IN_FRONT - 1.6),
			14,
			dir(c, 0, 0, -1),
			CAVE,
			rng,
			{ Depth = 5 }
		)
	end
end

---------------------------------------------------------------- ceiling

local function buildCeiling(parent: Instance, c: Ctx)
	local m = group("Ceiling", parent)
	local rng = c.rng
	local spans: { { number } } = { { IN_BACK - 4, 0 } }
	if not c.cutaway then
		table.insert(spans, { 0, IN_FRONT + 4 })
	end
	for _, s in spans do
		local mid = (s[1] + s[2]) / 2
		local len = s[2] - s[1]
		Geo.block(m, at(c, 0, CEIL + 2, mid), Vector3.new(IN_X * 2 + 8, 4, len), CEILING, nil, SOLID)
		-- rough rock hanging under it
		for _ = 1, 9 do
			local x = rng:range(-54, 54)
			local z = rng:range(s[1] + 8, s[2] - 6)
			local size = Vector3.new(rng:range(7, 14), rng:range(2, 4), rng:range(6, 12))
			Geo.block(
				m,
				at(c, x, CEIL - size.Y * 0.3, z) * CFrame.Angles(rng:range(-0.12, 0.12), rng:range(0, math.pi), rng:range(-0.12, 0.12)),
				size,
				Geo.vary(rng:pick(CAVE), rng, 0.05),
				nil,
				DECOR
			)
		end
		MineKit.stalactites(m, pt(c, 0, CEIL, mid), Vector2.new(116, len - 10), CAVE, rng, 22)
	end
end

---------------------------------------------------------------- columns and arches

local function column(parent: Instance, c: Ctx, x: number, z: number, brokenAt: number?)
	local m = group("Column", parent)
	local base = at(c, x, 0, z)
	Geo.block(m, base * CFrame.new(0, 0.6, 0), Vector3.new(6.4, 1.2, 6.4), Geo.vary(STONE_DARK, c.rng, 0.03), nil, BUMP)
	Geo.block(m, base * CFrame.new(0, 1.45, 0), Vector3.new(5.8, 0.5, 5.8), GOLD, nil, DECOR)
	Geo.block(m, base * CFrame.new(0, 2.1, 0), Vector3.new(5.0, 0.8, 5.0), MARBLE_DARK, nil, BUMP)
	local bottom = 2.5
	local top = brokenAt or (COL_H - 3.4)
	local len = top - bottom
	local drums = math.max(1, math.floor(len / 6 + 0.5))
	local dh = len / drums
	-- a darker core shows in the joints between the drums
	Geo.block(m, base * CFrame.new(0, bottom + len / 2, 0), Vector3.new(3.8, len, 3.8), MARBLE_DARK, nil, TINY)
	for i = 0, drums - 1 do
		local shade = if i % 2 == 0 then MARBLE else MARBLE:Lerp(MARBLE_DARK, 0.22)
		Geo.block(
			m,
			base * CFrame.new(0, bottom + dh * (i + 0.5), 0),
			Vector3.new(4.2, dh - 0.12, 4.2),
			Geo.vary(shade, c.rng, 0.025),
			nil,
			BUMP
		)
	end
	-- flutes: two grooves on each face
	for _, f in { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) } do
		for _, o in { -0.95, 0.95 } do
			local fx = f.X * 2.12 + (if f.X == 0 then o else 0)
			local fz = f.Y * 2.12 + (if f.Y == 0 then o else 0)
			local size = if f.X ~= 0 then Vector3.new(0.1, len - 0.6, 0.5) else Vector3.new(0.5, len - 0.6, 0.1)
			Geo.block(m, base * CFrame.new(fx, bottom + len / 2, fz), size, MARBLE_DARK, nil, TINY)
		end
	end
	if brokenAt then
		-- a jagged broken top
		Geo.block(m, base * CFrame.new(0, top + 0.02, 0), Vector3.new(3.9, 0.2, 3.9), MARBLE_DARK, nil, DECOR)
		Geo.wedge(m, base * CFrame.new(-0.7, top + 0.9, 0.4) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.6, 1.8, 2.4), MARBLE, nil, DECOR)
		Geo.block(
			m,
			base * CFrame.new(1.0, top + 0.4, -0.8) * CFrame.Angles(0.3, 0.6, 0.25),
			Vector3.new(1.8, 1.0, 1.6),
			MARBLE_DARK,
			nil,
			DECOR
		)
	else
		Geo.block(m, base * CFrame.new(0, COL_H - 3.15, 0), Vector3.new(4.6, 0.5, 4.6), GOLD, nil, DECOR)
		Geo.block(m, base * CFrame.new(0, COL_H - 2.3, 0), Vector3.new(5.3, 1.2, 5.3), MARBLE, nil, DECOR)
		Geo.block(m, base * CFrame.new(0, COL_H - 1.5, 0), Vector3.new(5.9, 0.4, 5.9), GOLD, nil, DECOR)
		Geo.block(m, base * CFrame.new(0, COL_H - 0.65, 0), Vector3.new(6.6, 1.3, 6.6), STONE_LIGHT, nil, DECOR)
	end
end

-- A column drum lying on the floor from a to b (x, z), rolled a little.
local function fallenDrum(parent: Instance, c: Ctx, a: Vector2, b: Vector2, color: Color3)
	local d = b - a
	local mid = (a + b) / 2
	local yaw = math.atan2(d.X, d.Y)
	local roll = c.rng:range(-0.18, 0.18)
	local cf = at(c, mid.X, 2.1 * (math.cos(roll) + math.abs(math.sin(roll))) - 0.05, mid.Y)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(0, 0, roll)
	Geo.block(parent, cf, Vector3.new(4.2, 4.2, d.Magnitude - 0.3), color, nil, BUMP)
	Geo.block(parent, cf * CFrame.new(0, 0, d.Magnitude / 2 - 0.2), Vector3.new(3.8, 3.8, 0.2), MARBLE_DARK, nil, DECOR)
end

local function buildColumns(parent: Instance, c: Ctx)
	local m = group("Columns", parent)
	for _, sx in { -1, 1 } do
		for _, z in COL_Z do
			local broken: number? = nil
			if z == 26 then
				broken = if sx < 0 then 11 else 17
			end
			column(m, c, sx * COL_X, z, broken)
		end
	end
	-- arches along each row (local +X of the arc frame = world -Z, so k = 1 starts at the back column)
	local function rowArch(sx: number, zFront: number, zBack: number, skip: { [number]: boolean }?)
		local center = at(c, sx * COL_X, COL_H, (zFront + zBack) / 2) * CFrame.Angles(0, math.pi / 2, 0)
		arc(m, center, 5.6, 0, math.pi, 7, 1.8, 3.2, STONE_LIGHT, GOLD, skip)
	end
	rowArch(-1, 10, -6)
	rowArch(-1, -6, -22, { [4] = true, [5] = true })
	rowArch(-1, -22, -38)
	rowArch(1, 26, 10, { [4] = true, [5] = true, [6] = true, [7] = true })
	rowArch(1, 10, -6)
	rowArch(1, -6, -22)
	rowArch(1, -22, -38, { [3] = true, [4] = true })
	rowArch(-1, 26, 10, { [3] = true, [4] = true, [5] = true, [6] = true, [7] = true })
	-- the grand arch over the dais (segmental, between the two back columns)
	local span, rise = 18.7, 6.5
	local r = (span * span + rise * rise) / (2 * rise)
	local half = math.asin(span / r)
	arc(m, at(c, 0, COL_H + rise - r, -38), r, math.pi / 2 - half, math.pi / 2 + half, 11, 2.2, 3.4, STONE_LIGHT, GOLD)
	arc(m, at(c, 0, COL_H + rise - r, -38), r - 1.25, math.pi / 2 - half + 0.02, math.pi / 2 + half - 0.02, 11, 0.3, 3.5, GOLD)

	-- the left front column fell toward the terrace and broke into drums
	local fall = group("FallenColumn", m)
	local start = Vector2.new(-24.6, 27.4)
	local d = Vector2.new(-22, 10).Unit
	local drumColors = { MARBLE, MARBLE:Lerp(MARBLE_DARK, 0.22), MARBLE }
	local s = 0
	for i, l in { 5.6, 5.8, 5.4 } do
		fallenDrum(fall, c, start + d * s, start + d * (s + l), drumColors[i])
		s += l + 0.5
	end
	local capPos = start + d * (s + 2.4)
	local capCf = at(c, capPos.X, 3.1, capPos.Y) * CFrame.Angles(0, math.atan2(d.X, d.Y), 0) * CFrame.Angles(1.25, 0, 0.15)
	Geo.block(fall, capCf, Vector3.new(6.6, 1.3, 6.6), STONE_LIGHT, nil, BUMP)
	Geo.block(fall, capCf * CFrame.new(0, -1.2, 0), Vector3.new(5.3, 1.2, 5.3), MARBLE, nil, DECOR)
	Geo.block(fall, capCf * CFrame.new(0, -0.6, 0), Vector3.new(5.9, 0.4, 5.9), GOLD, nil, DECOR)
	rubble(fall, c, -27, 0, 23.5, 4, { MARBLE, MARBLE_DARK }, 1.1)
	rubble(fall, c, -45, 0, 33, 4, { MARBLE, STONE_LIGHT }, 1.0)

	-- the right front column snapped: pieces lie at its foot
	local snap = group("SnappedColumn", m)
	fallenDrum(snap, c, Vector2.new(25.5, 28.2), Vector2.new(30.5, 31.4), MARBLE)
	local cap = at(c, 29.5, 1.6, 35.2) * CFrame.Angles(0.35, 0.5, 0.12)
	Geo.block(snap, cap, Vector3.new(6.6, 1.3, 6.6), STONE_LIGHT, nil, BUMP)
	Geo.block(snap, cap * CFrame.new(0, 1.2, 0), Vector3.new(5.3, 1.2, 5.3), MARBLE, nil, DECOR)
	Geo.block(snap, cap * CFrame.new(0, 0.6, 0), Vector3.new(5.9, 0.4, 5.9), GOLD, nil, DECOR)
	Geo.block(snap, at(c, 25.4, 1.4, 22.6) * CFrame.Angles(0.2, 0.9, 1.1), Vector3.new(4.0, 2.4, 3.6), MARBLE, nil, BUMP)
	rubble(snap, c, 24.5, 0, 31.5, 5, { MARBLE, MARBLE_DARK }, 1.0)
end

---------------------------------------------------------------- the dais, throne and statue

local function brazier(parent: Instance, c: Ctx, x: number, y: number, z: number, tall: boolean)
	local m = group("Brazier", parent)
	local base = at(c, x, y, z)
	local stem = if tall then 4.6 else 2.4
	Geo.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(2.6, 0.6, 2.6), STONE_DARK, nil, BUMP)
	Geo.block(m, base * CFrame.new(0, 0.6 + stem / 2, 0), Vector3.new(1.0, stem, 1.0), GOLD_DARK, nil, BUMP)
	local b = 0.6 + stem
	Geo.block(m, base * CFrame.new(0, b + 0.25, 0), Vector3.new(1.9, 0.5, 1.9), GOLD_DARK, nil, DECOR)
	Geo.block(m, base * CFrame.new(0, b + 0.9, 0), Vector3.new(3.0, 0.9, 3.0), GOLD, nil, DECOR)
	Geo.block(m, base * CFrame.new(0, b + 1.45, 0), Vector3.new(3.4, 0.3, 3.4), GOLD_DARK, nil, DECOR)
	Geo.block(m, base * CFrame.new(0, b + 1.5, 0), Vector3.new(2.6, 0.3, 2.6), EMBER, NEON, TINY)
	local flame =
		Geo.block(m, base * CFrame.new(0, b + 2.4, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(1.4, 1.9, 1.4), FIRE, NEON, TINY)
	flame.Name = "Flame"
	Geo.block(m, base * CFrame.new(0.2, b + 2.9, -0.1) * CFrame.Angles(0, 0.3, 0), Vector3.new(0.8, 1.6, 0.8), FIRE_CORE, NEON, TINY)
	pointLight(flame, FIRE, 26, 1.7)
	Style.emitter(flame, "Fire", FIRE, 16)
end

-- The Ember King: the same giant stone king statue as at the Blaster Vault in the lobby
-- (owner, 2026-10-17: "make the king like the statues at the vault"), smaller to fit under
-- the apse arch: stone blocks veined with glowing cracks, crown, purple tabard, raised
-- blaster, on its own pedestal at the back of the top tier, facing the hall (+Z).
local KING_SCALE = 1.35 -- studs per body unit (the vault's statues use 1.85)
local KING_PEDESTAL = 5.5

local function buildStatue(parent: Instance, c: Ctx)
	-- the vault builder reads its size from these module fields: set them for this call only
	local oldK, oldPedestal = VaultStatue.K, VaultStatue.PedestalHeight
	VaultStatue.K, VaultStatue.PedestalHeight = KING_SCALE, KING_PEDESTAL
	local ok, result = pcall(VaultStatue.build, parent, at(c, 0, 3.2, IN_BACK + 6.9), 1, "EmberKingStatue")
	VaultStatue.K, VaultStatue.PedestalHeight = oldK, oldPedestal
	if not ok then
		error(result)
	end
end

local function buildDais(parent: Instance, c: Ctx)
	local m = group("Dais", parent)
	-- three tiers with gold edges
	local tiers = {
		{ hw = 18, zf = -30, y = 0, h = 1, color = STONE },
		{ hw = 14, zf = -34, y = 1, h = 1, color = STONE_LIGHT },
		{ hw = 10, zf = -38, y = 2, h = 1.2, color = STONE },
	}
	for _, t in tiers do
		local hw, zf, y, h, color = t.hw, t.zf, t.y, t.h, t.color
		local depth = zf - IN_BACK
		Geo.block(m, at(c, 0, y + h / 2, (zf + IN_BACK) / 2), Vector3.new(hw * 2, h, depth), color, nil, SOLID)
		Geo.block(m, at(c, 0, y + h - 0.1, zf + 0.12), Vector3.new(hw * 2 + 0.2, 0.25, 0.3), GOLD, nil, TINY)
		for _, sx in { -1, 1 } do
			Geo.block(m, at(c, sx * (hw + 0.12), y + h - 0.1, (zf + IN_BACK) / 2), Vector3.new(0.3, 0.25, depth), GOLD, nil, TINY)
		end
	end
	-- violet inlay and a gold ring on the top tier around the throne
	Geo.block(m, at(c, 0, 3.22, -45), Vector3.new(17, 0.06, 12), TILE_VIOLET, nil, TINY)
	-- the carpet climbs the steps to the throne
	local carpet = {
		{ 1.0, -32, 4 },
		{ 2.0, -36, 4 },
		{ 3.2, -39.2, 2.4 },
	}
	for _, k in carpet do
		Geo.block(m, at(c, 0, k[1] + 0.06, k[2]), Vector3.new(8, 0.14, k[3]), RED, nil, TINY)
	end
	for _, r in { { -30, 0, 1 }, { -34, 1, 1 }, { -38, 2, 1.2 } } do
		Geo.block(m, at(c, 0, r[2] + r[3] / 2, r[1] + 0.07), Vector3.new(8, r[3], 0.14), RED, nil, TINY)
	end
	brazier(m, c, -21, 0, -30, false)
	brazier(m, c, 21, 0, -30, false)
	brazier(m, c, -12, 2, -46, true)
	brazier(m, c, 12, 2, -46, true)
	buildStatue(m, c)
end

---------------------------------------------------------------- the carpet, terrace and entrance

local function carpetRun(parent: Instance, c: Ctx, y: number, z0: number, z1: number)
	local mid, len = (z0 + z1) / 2, math.abs(z1 - z0)
	Geo.block(parent, at(c, 0, y + 0.08, mid), Vector3.new(8, 0.16, len), RED, nil, TINY)
	for _, sx in { -1, 1 } do
		Geo.block(parent, at(c, sx * 3.75, y + 0.1, mid), Vector3.new(0.5, 0.2, len), GOLD, nil, TINY)
	end
end

local function balustrade(parent: Instance, c: Ctx, x0: number, x1: number)
	local z = TERRACE_Z + 0.6
	local y = TERRACE_Y
	local len = x1 - x0
	local mid = (x0 + x1) / 2
	Geo.block(parent, at(c, mid, y + 0.25, z), Vector3.new(len, 0.5, 1.1), STONE, nil, BUMP)
	Geo.block(parent, at(c, mid, y + 3.0, z), Vector3.new(len, 0.5, 1.3), MARBLE, nil, BUMP)
	Geo.block(parent, at(c, mid, y + 3.28, z), Vector3.new(len, 0.1, 0.5), GOLD, nil, TINY)
	local n = math.floor((len - 2) / 2)
	for i = 1, n do
		local x = x0 + 1 + (len - 2) * (i - 0.5) / n
		Geo.block(parent, at(c, x, y + 1.62, z) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.6, 2.25, 0.6), MARBLE_DARK, nil, DECOR)
	end
	for _, x in { x0 + 0.7, x1 - 0.7 } do
		Geo.block(parent, at(c, x, y + 1.8, z), Vector3.new(1.4, 3.6, 1.4), STONE_LIGHT, nil, BUMP)
		Geo.block(parent, at(c, x, y + 3.75, z), Vector3.new(1.7, 0.4, 1.7), GOLD, nil, TINY)
	end
end

local function stairs(parent: Instance, c: Ctx, x: number, width: number)
	for i = 0, 2 do
		local top = 0.6 * (i + 1)
		local z0 = TERRACE_Z - 4 + i
		Geo.block(parent, at(c, x, top / 2, (z0 + TERRACE_Z) / 2), Vector3.new(width, top, TERRACE_Z - z0), STONE_LIGHT, nil, SOLID)
		Geo.block(parent, at(c, x, top + 0.02, z0 + 0.14), Vector3.new(width, 0.1, 0.28), GOLD, nil, TINY)
	end
end

local function lampPost(parent: Instance, c: Ctx, x: number, z: number)
	local m = group("LampPost", parent)
	local base = at(c, x, TERRACE_Y, z)
	Geo.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(1.8, 0.6, 1.8), STONE_DARK, nil, BUMP)
	Geo.block(m, base * CFrame.new(0, 3.6, 0), Vector3.new(0.7, 6, 0.7), STONE, nil, BUMP)
	Geo.block(m, base * CFrame.new(0, 6.7, 0), Vector3.new(1.5, 0.25, 1.5), GOLD, nil, TINY)
	local lamp = Geo.block(m, base * CFrame.new(0, 7.45, 0), Vector3.new(1.1, 1.3, 1.1), FIRE_CORE, NEON, TINY)
	lamp.Name = "LampGlow"
	Geo.block(m, base * CFrame.new(0, 8.2, 0), Vector3.new(1.6, 0.3, 1.6), GOLD, nil, TINY)
	Geo.block(m, base * CFrame.new(0, 8.55, 0), Vector3.new(0.7, 0.4, 0.7), GOLD_DARK, nil, TINY)
	pointLight(lamp, FIRE_CORE, 22, 1.2)
end

local function buildTerrace(parent: Instance, c: Ctx)
	local m = group("Terrace", parent)
	local rng = c.rng
	local depth = IN_FRONT - TERRACE_Z
	local mid = (IN_FRONT + TERRACE_Z) / 2
	local top = Geo.block(m, at(c, 0, TERRACE_Y / 2, mid), Vector3.new(IN_X * 2, TERRACE_Y, depth), TILE_CREAM, nil, SOLID)
	top.Name = "TerraceFloor"
	-- checker tiles and grout matching the hall
	for i = 0, 19 do
		for j = 0, 1 do
			if (i + j) % 2 == 0 then
				Geo.block(
					m,
					at(c, -60 + 6 * i + 3, TERRACE_Y + 0.03, TERRACE_Z + 1 + 6 * j + 3),
					Vector3.new(5.9, 0.06, 5.9),
					Geo.vary(TILE_VIOLET, rng, 0.035),
					nil,
					TINY
				)
			end
		end
	end
	for i = 0, 20 do
		Geo.block(m, at(c, -60 + 6 * i, TERRACE_Y + 0.05, mid), Vector3.new(0.22, 0.1, depth), GROUT, nil, TINY)
	end
	for _, z in { TERRACE_Z + 1, TERRACE_Z + 7, TERRACE_Z + 13 } do
		Geo.block(m, at(c, 0, TERRACE_Y + 0.05, z), Vector3.new(120, 0.1, 0.22), GROUT, nil, TINY)
	end
	-- the front edge: dark base, gold lip
	Geo.block(m, at(c, 0, 0.3, TERRACE_Z - 0.15), Vector3.new(IN_X * 2, 0.6, 0.3), WALL_DARK, nil, TINY)
	Geo.block(m, at(c, 0, TERRACE_Y - 0.15, TERRACE_Z - 0.15), Vector3.new(IN_X * 2, 0.3, 0.3), GOLD, nil, TINY)
	-- stairs down into the hall (center, and one by the ore lift)
	stairs(m, c, 0, 16)
	stairs(m, c, 40, 6)
	-- the balustrade, broken where the column hit it and at one more spot
	balustrade(m, c, -61, -46.5)
	balustrade(m, c, -39.5, -9)
	balustrade(m, c, 9, 16)
	balustrade(m, c, 21.5, 37)
	balustrade(m, c, 43, 61)
	for i = 1, 3 do
		Geo.block(
			m,
			at(c, 17 + i * 1.1, 0.32, 35.4 - i * 0.6) * CFrame.Angles(0, rng:range(-0.8, 0.8), math.pi / 2),
			Vector3.new(0.6, 2.25, 0.6),
			MARBLE_DARK,
			nil,
			DECOR
		)
	end
	Geo.block(m, at(c, 19, 0.5, 33.2) * CFrame.Angles(0.1, 0.35, 0.08), Vector3.new(4.5, 0.5, 1.3), MARBLE, nil, DECOR)
	-- the royal carpet from the arrival circle down the stairs
	carpetRun(m, c, TERRACE_Y, TERRACE_Z - 1, 42.2)
	for i = 0, 1 do
		Geo.block(m, at(c, 0, 0.6 * (i + 1) + 0.07, TERRACE_Z - 4 + i + 0.5), Vector3.new(8, 0.14, 1), RED, nil, TINY)
	end
	-- lamps and the Forgekeepers' camp gear by the elevator and the ore lift
	lampPost(m, c, -14, 49.5)
	lampPost(m, c, 14, 49.5)
	Style.crate(m, at(c, -33, TERRACE_Y, 49.4), rng, 2.4)
	Style.crate(m, at(c, -35.8, TERRACE_Y, 49.8), rng, 2.2)
	Style.crate(m, at(c, -34.2, TERRACE_Y + 2.3, 49.6), rng, 1.8)
	Style.barrel(m, pt(c, -33.2, TERRACE_Y, 45.6), rng)
	Style.mineCart(m, at(c, 35, TERRACE_Y, 46.6), rng, { Load = "Gold" })
	Style.crate(m, at(c, 35, TERRACE_Y, 50.4), rng, 2.2)
	-- a steel crane beam from the right wall holds the ore lift's cable
	local beamY = TERRACE_Y + 30.7
	local beamX0, beamX1 = 23.4, IN_X - 0.2
	Geo.block(m, at(c, (beamX0 + beamX1) / 2, beamY, 45), Vector3.new(beamX1 - beamX0, 0.9, 0.9), LIFT_STEEL_DARK, nil, DECOR)
	Geo.block(m, at(c, (beamX0 + beamX1) / 2, beamY - 0.5, 45), Vector3.new(beamX1 - beamX0, 0.2, 1.3), LIFT_STEEL, nil, TINY)
	Geo.block(m, at(c, beamX0 + 0.4, beamY, 45), Vector3.new(0.8, 2.2, 2.2), LIFT_STEEL_DARK, nil, TINY)
	Geo.block(m, at(c, IN_X - 0.6, beamY - 2.5, 45), Vector3.new(1.0, 6, 2.6), LIFT_STEEL_DARK, nil, DECOR)
	local braceFrom, braceTo = Vector3.new(IN_X - 1, beamY - 6.5, 45), Vector3.new(IN_X - 9, beamY - 0.6, 45)
	Geo.block(
		m,
		CFrame.lookAt(pt(c, (braceFrom.X + braceTo.X) / 2, (braceFrom.Y + braceTo.Y) / 2, 45), pt(c, braceTo.X, braceTo.Y, 45)),
		Vector3.new(0.8, 0.8, (braceTo - braceFrom).Magnitude),
		LIFT_STEEL,
		nil,
		DECOR
	)
end

local function buildHallCarpet(parent: Instance, c: Ctx)
	local m = group("Carpet", parent)
	carpetRun(m, c, 0, TERRACE_Z - 4, GIANT.Y + 10.5)
	carpetRun(m, c, 0, GIANT.Y - 10.5, -30)
	-- torn ends around the rune circle
	Geo.block(m, at(c, -1.6, 0.09, GIANT.Y + 9.7) * CFrame.Angles(0, 0.3, 0), Vector3.new(3.4, 0.14, 1.8), RED, nil, TINY)
	Geo.block(m, at(c, 2.4, 0.09, GIANT.Y + 10) * CFrame.Angles(0, -0.4, 0), Vector3.new(2.4, 0.14, 1.2), RED_DARK, nil, TINY)
	Geo.block(m, at(c, 1.2, 0.09, GIANT.Y - 9.8) * CFrame.Angles(0, 0.25, 0), Vector3.new(3.6, 0.14, 1.6), RED, nil, TINY)
end

---------------------------------------------------------------- crystals and debris

local function buildCrystals(parent: Instance, c: Ctx)
	local m = group("Crystals", parent)
	local A = CFrame.Angles
	-- { x, y, z, tilt, count, height, lavender?, light? }
	local list: { { any } } = {
		-- the deep back: big clusters in the corners and beside the dais
		{ -56.5, 0.6, -48.4, A(0.3, 0, -0.3), 9, 8, false, true },
		{ 57, 0.6, -49, A(0.35, 0, 0.15), 9, 9, false, true },
		{ -21.4, 0, -47.6, A(0.15, 0, 0.25), 7, 6, true, false },
		{ 21.4, 0, -47.6, A(0.15, 0, -0.25), 7, 6.5, false, false },
		{ -33, 0.6, -50.2, A(0.25, 0, 0), 6, 5, false, false },
		{ 33, 0.6, -50.2, A(0.25, 0, 0), 6, 5, true, false },
		{ -16.4, 1, -44.6, A(0.1, 0, 0.2), 5, 3.4, false, false },
		{ 16.4, 1, -44.6, A(0.1, 0, -0.2), 5, 3.4, true, false },
		-- out of the rock that burst through the walls
		{ 56.6, 3, 19.5, A(0.15, 0, 0.6), 7, 6, true, true },
		{ -56.6, 3, -13.5, A(-0.15, 0, -0.6), 7, 6, false, true },
		-- small ones through cracks near the entrance and the columns
		{ -25.8, 0, -10, A(0.1, 0, 0.2), 4, 3, true, false },
		{ 25.8, 0, 6.2, A(-0.1, 0, -0.2), 4, 2.8, false, false },
		{ 14.5, 0, 36.2, A(-0.2, 0, -0.15), 4, 3, false, false },
		{ -14.5, 0, 36.2, A(-0.2, 0, 0.15), 4, 3.2, true, false },
	}
	for i, k in list do
		local root = at(c, k[1] :: number, k[2] :: number, k[3] :: number) * (k[4] :: CFrame)
		local colors = if k[7] then CRYSTALS_LAVENDER else CRYSTALS
		local cluster = MineKit.crystals(m, root, k[5] :: number, k[6] :: number, "Shell", colors, "palace-" .. i)
		if k[8] then
			lightAt(cluster, root * CFrame.new(0, (k[6] :: number) * 0.5, 0), colors[1], 20, 1.2)
		end
	end
	-- small clusters on the cornices, leaning out of the rock above them
	for i, p in { { -1, 2 }, { -1, -32 }, { 1, -4 }, { 1, 36 } } do
		local sx = p[1]
		MineKit.crystals(
			m,
			at(c, sx * (IN_X - 1.4), 27.2, p[2]) * A(0, 0, sx * 0.55),
			5,
			3.4,
			"Shell",
			if i % 2 == 0 then CRYSTALS else CRYSTALS_LAVENDER,
			"palace-cornice-" .. i
		)
	end
	-- clusters hanging from the ceiling in the back half
	for i, p in { { -30, -28 }, { 30, -40 }, { 9, -22 }, { -12, -46 } } do
		MineKit.crystals(
			m,
			at(c, p[1], CEIL - 0.5, p[2]) * A(math.pi + 0.1 * i, 0, 0.1),
			6,
			5,
			"Shell",
			if i % 2 == 0 then CRYSTALS_LAVENDER else CRYSTALS,
			"palace-ceiling-" .. i
		)
	end
end

local function buildDebris(parent: Instance, c: Ctx)
	local m = group("Debris", parent)
	rubble(m, c, -56, 0.6, 6, 4, { STONE, STONE_LIGHT }, 1.0)
	rubble(m, c, 56, 0.6, -6, 4, { STONE, STONE_LIGHT }, 1.0)
	rubble(m, c, 56, 0, 27.5, 4, CAVE, 1.0)
	rubble(m, c, -55.5, 0, -22.5, 5, CAVE, 1.2)
	rubble(m, c, -26, 0, -26, 3, { MARBLE, MARBLE_DARK }, 0.8)
	rubble(m, c, 26, 0, -14, 3, { MARBLE, MARBLE_DARK }, 0.8)
	rubble(m, c, 42, 0, -48.5, 4, CAVE, 1.1)
	rubble(m, c, -42, 0, -48.5, 4, CAVE, 1.1)
	-- a fallen chandelier ring in the right aisle path
	local ring = at(c, 42, 0.25, -14.5) * CFrame.Angles(0.06, 0.4, 0.04)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		Geo.block(
			m,
			ring * CFrame.new(math.cos(a) * 2.4, 0, math.sin(a) * 2.4) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Vector3.new(2.0, 0.35, 0.35),
			GOLD,
			nil,
			DECOR
		)
		if k % 2 == 0 then
			Geo.block(m, ring * CFrame.new(math.cos(a) * 2.4, 0.5, math.sin(a) * 2.4), Vector3.new(0.35, 0.7, 0.35), MARBLE, nil, TINY)
		end
	end
	Geo.block(m, ring * CFrame.new(0, 0.1, 0), Vector3.new(0.6, 0.6, 0.6), GOLD_DARK, nil, DECOR)
end

---------------------------------------------------------------- build

function Floor.build(parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	local cutaway = if opts then opts.Cutaway == true else false
	local model = Instance.new("Model")
	model.Name = "MineFloor" .. Floor.Index
	model:SetAttribute("Floor", Floor.Index)
	model:SetAttribute("FloorId", "SunkenPalace")
	local c: Ctx = {
		origin = origin,
		rng = Rng.new("SunkenPalace"),
		cutaway = cutaway,
	}

	buildFloor(model, c)
	buildWalls(model, c)
	buildCeiling(model, c)
	buildColumns(model, c)
	buildDais(model, c)
	buildTerrace(model, c)
	buildHallCarpet(model, c)
	buildCrystals(model, c)
	buildDebris(model, c)

	-- glowing water and rune circles
	local glow = group("Glow", model)
	puddle(glow, c, 42, 18, 4.2, true)
	puddle(glow, c, -42, 8, 3.6, false)
	puddle(glow, c, -42, -34, 4.0, true)
	puddle(glow, c, 43, -24, 3.2, false)
	local giantCore = runeCircle(glow, c, GIANT.X, 0, GIANT.Y, 9, RUNE_GOLD)
	pointLight(giantCore, RUNE_GOLD, 22, 1.2)
	sparkle(giantCore, GOLD_GLOW, 6, 0.8)
	local arrivalCore = runeCircle(glow, c, 0, TERRACE_Y, 46.4, 4, RUNE_LAVENDER)
	pointLight(arrivalCore, RUNE_LAVENDER, 16, 1.0)

	-- gameplay pieces: elevator (the only way in), the gate, the ore lift
	MineKit.elevator(model, at(c, -24, TERRACE_Y, 45) * CFrame.Angles(0, -math.pi / 2, 0), Floor.Index)
	MineKit.gate(
		model,
		at(c, 0, TERRACE_Y, TERRACE_Z + 0.9) * CFrame.Angles(0, math.pi, 0),
		14,
		MineFloors.get(4).MinBlaster,
		{ MARBLE, GOLD, WALL_DARK }
	)
	MineKit.oreLift(model, pt(c, 26, TERRACE_Y, 45), "SunkenPalace")

	-- markers and rock spawns
	MineKit.marker(model, "Entrance", at(c, 0, TERRACE_Y, 46))
	MineKit.marker(model, "GiantSpawn", at(c, GIANT.X, 0, GIANT.Y))
	local spawns = MineKit.spawns(model)
	for _, s in SPAWNS do
		spawns.add(at(c, s[1], 0, s[2]), false)
	end
	for _, s in DEEP_SPAWNS do
		spawns.add(at(c, s[1], 0, s[2]), true)
	end

	model.Parent = parent
	return model
end

return Floor
