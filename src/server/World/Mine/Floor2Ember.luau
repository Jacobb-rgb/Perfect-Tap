--[[
	Floor 2: EMBER CAVES (blaster 3+), docs/plans/MINE_FLOORS_PLAN.md.

	A big dark basalt cave: walls of hexagonal basalt columns in front of a jagged
	rock wall, glowing orange and gold veins running up the columns, a lava river
	crossing from side to side in a sunken channel with a crusty rim (it comes out
	of a tunnel in the left wall and runs into one in the right wall), a stone arch
	bridge over it on the main path and a slab bridge on the right, lava pools with
	crusty rims and hot cores, a lava fall pouring out of a crack in the back wall,
	a few ember emitters, orange and ruby crystal clusters (bigger in the back),
	stalactites, and old mining props near the entrance (cart on rails, lanterns,
	crates, timber supports). The back third ("deep") is hotter: the lava fall,
	a second pool, more veins and the big crystals.

	Layout (local to `origin`, +Z = front where players arrive, x = 0 main path):
	  z +58 .. +38  entrance plaza: gate, elevator (left), ore lift (right), props
	  z +34 ..  +6  front rock field on both sides of the hex-tiled path
	  z  -2 .. -19  the lava river (arch bridge at x = 0, slab bridge at x = 44)
	  z -22 .. -48  deep rock field around the Giant Crystal spot (0, -33)
	About 2400 parts (2150 cutaway), 21 PointLights, 6 ParticleEmitters.
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

Floor.Index = 2
Floor.Size = Vector3.new(136, 46, 120)

type Opts = { Cutaway: boolean? }
type Pool = { C: Vector2, R: number }
type Zone = { C: Vector2, R: number }

local PAL = MineFloors.get(2).Palette
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SQRT3 = math.sqrt(3)

local SOLID: Geo.PartProps = { CanTouch = false, CanQuery = true, CanCollide = true }
local BUMP: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = true }
local DECOR: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false }
local GLOW: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local HIDDEN: Geo.PartProps = {
	Transparency = 1,
	CanTouch = false,
	CanQuery = false,
	CanCollide = false,
	CastShadow = false,
}

---------------------------------------------------------------- palette

-- basalt walls: the rocks' dark red-brown pushed darker and cooler, so the rocks pop
local BASALT = rgb(116, 106, 128)
local BASALT_DARK = rgb(78, 70, 92)
local BASALT_LIGHT = rgb(156, 144, 166)
local GROUND = rgb(146, 134, 146) -- light ash: the rocks stand out dark on it
local TILE = rgb(82, 72, 96) -- dark basalt causeway tiles
local CRUST = rgb(40, 26, 26)
local CRUST_LIGHT = rgb(70, 44, 40)
local STONE = rgb(178, 150, 134) -- the bridges' cut stone
local STONE_DARK = rgb(134, 110, 102)
local LAVA = PAL.Accent
local LAVA_HOT = rgb(255, 204, 92)
local LAVA_DEEP = rgb(228, 64, 24)
local VEIN = rgb(255, 92, 24)
local GOLD = rgb(255, 172, 48)
local WALL_COLORS = { BASALT, BASALT_LIGHT, BASALT_DARK }

---------------------------------------------------------------- layout

local HALF_X, HALF_Z = 66, 58 -- ground extents
local WALL_X, WALL_BACK, WALL_FRONT = 62, -54, 56 -- jagged rock wall lines
local COL_X, COL_BACK, COL_FRONT = 59.5, -51.5, 53.5 -- basalt column rows
local CEIL = 38 -- ceiling underside
local LAVA_Y = -1.6 -- river surface
local RIVER_HW = 6.5 -- river half width
-- river centerline (x, z), from under the left wall to under the right wall
local RIVER: { Vector2 } = {
	Vector2.new(-74, -4),
	Vector2.new(-48, -10),
	Vector2.new(-26, -6),
	Vector2.new(-8, -9),
	Vector2.new(8, -9),
	Vector2.new(26, -12),
	Vector2.new(48, -7),
	Vector2.new(74, -9),
}
local BRIDGE_FRONT, BRIDGE_BACK, BRIDGE_W, BRIDGE_RISE = 8, -24, 10, 3
local BRIDGE2_X, BRIDGE2_W = 44, 9.6
local GATE_Z, ENTRANCE_Z, OPENING = 54, 48, 11
local GIANT = Vector2.new(0, -33)
local ELEVATOR = Vector2.new(-26, 43)
local LIFT = Vector2.new(46, 40)
local FALL_X, FALL_TOP = 34, 24
local POOLS: { Pool } = {
	{ C = Vector2.new(FALL_X, -46), R = 7 }, -- under the lava fall
	{ C = Vector2.new(-42, -40), R = 6 },
	{ C = Vector2.new(-44, 20), R = 5 },
}

-- rock spawns: about 10 studs apart, 5+ from walls and lava, clear of the path
local FRONT_SPAWNS: { Vector2 } = {
	Vector2.new(-13, 30),
	Vector2.new(-23, 31),
	Vector2.new(-46, 33),
	Vector2.new(-18, 21),
	Vector2.new(-28, 22),
	Vector2.new(-12, 11),
	Vector2.new(-22, 10),
	Vector2.new(-32, 10),
	Vector2.new(-47, 6),
	Vector2.new(13, 30),
	Vector2.new(23, 31),
	Vector2.new(35, 30),
	Vector2.new(47, 26),
	Vector2.new(18, 21),
	Vector2.new(28, 21),
	Vector2.new(40, 21),
	Vector2.new(12, 11),
	Vector2.new(22, 10),
	Vector2.new(32, 9),
}
local DEEP_SPAWNS: { Vector2 } = {
	Vector2.new(-17, -25),
	Vector2.new(-27, -33),
	Vector2.new(-37, -25),
	Vector2.new(-47, -28),
	Vector2.new(-18, -42),
	Vector2.new(17, -25),
	Vector2.new(27, -33),
	Vector2.new(36, -26),
	Vector2.new(47, -33),
	Vector2.new(18, -42),
}

-- River centerline z at x (piecewise linear).
local function riverZ(x: number): number
	for i = 1, #RIVER - 1 do
		local a, b = RIVER[i], RIVER[i + 1]
		if x <= b.X or i == #RIVER - 1 then
			local t = math.clamp((x - a.X) / (b.X - a.X), 0, 1)
			return a.Y + (b.Y - a.Y) * t
		end
	end
	return RIVER[1].Y
end

---------------------------------------------------------------- build

function Floor.build(parent: Instance, origin: CFrame, opts: Opts?): Model
	local o: Opts = opts or {}
	local cutaway = o.Cutaway == true
	local rng = Rng.new(2002)
	local model = Instance.new("Model")
	model.Name = "MineFloor2"
	model:SetAttribute("Floor", 2)

	-- every helper below takes LOCAL frames (relative to origin)
	local function block(p: Instance, frame: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Geo.PartProps): Part
		return Geo.block(p, origin * frame, size, color, material, props)
	end
	local function wedge(p: Instance, frame: CFrame, size: Vector3, color: Color3, props: Geo.PartProps): WedgePart
		return Geo.wedge(p, origin * frame, size, color, nil, props)
	end
	local function cylinder(p: Instance, pos: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, props: Geo.PartProps): Part
		local part = Geo.cylinder(p, pos, height, diameter, color, material, props)
		part.CFrame = origin * part.CFrame
		return part
	end
	local function pt(x: number, y: number, z: number): Vector3
		return origin:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function dir(x: number, y: number, z: number): Vector3
		return origin:VectorToWorldSpace(Vector3.new(x, y, z))
	end
	local function flat(p: Vector2, y: number): Vector3
		return Vector3.new(p.X, y, p.Y)
	end
	local function facing(p: Vector3, toward: Vector3): CFrame
		return CFrame.lookAt(p, p + toward)
	end
	-- an invisible anchor with a PointLight (counts against the 24-light budget)
	local function lamp(p: Instance, pos: Vector3, color: Color3, range: number, brightness: number): BasePart
		local anchor = block(p, CFrame.new(pos), Vector3.new(0.2, 0.2, 0.2), color, nil, HIDDEN)
		anchor.Name = "LightAnchor"
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = anchor
		return anchor
	end
	local function group(name: string): Model
		return Style.model(name, model)
	end

	-- A hexagonal basalt column: three boxes turned 60 degrees apart (their union is
	-- an exact hexagonal prism). `frame` = bottom center, LookVector = the way one
	-- flat face points; width = across the flats.
	local function hexColumn(p: Instance, frame: CFrame, width: number, height: number, color: Color3, props: Geo.PartProps)
		local side = width / SQRT3
		for k = 0, 2 do
			block(p, frame * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, height / 2, 0), Vector3.new(side, height, width), color, nil, props)
		end
	end

	-- A zig-zag glowing vein up the front flat face of a hex column (half sunk in it).
	local function columnVein(p: Instance, frame: CFrame, width: number, height: number, color: Color3, r: Rng.Rng)
		local half = width / SQRT3 / 2 - 0.3
		local u = r:range(0.2, 0.6) * half * (if r:chance(0.5) then 1 else -1)
		local v = r:range(0.8, math.max(1, height * 0.3))
		local sign = if u > 0 then 1 else -1
		for _ = 1, r:int(2, 4) do
			local len = r:range(2.4, 4.2)
			local theta = sign * r:range(0.22, 0.42)
			local du, dv = -math.sin(theta) * len, math.cos(theta) * len
			if v + dv > height - 0.5 then
				break
			end
			if math.abs(u + du) > half then
				theta, du = -theta, -du
			end
			block(p, frame * CFrame.new(u + du / 2, v + dv / 2, -width / 2) * CFrame.Angles(0, 0, theta), Vector3.new(0.26, len + 0.26, 0.4), color, NEON, GLOW)
			u += du
			v += dv
			sign = -sign
		end
	end

	-- keep-out circles for decoration (rocks, giant, paths, machines, props)
	local zones: { Zone } = {}
	local function keep(c: Vector2, r: number)
		table.insert(zones, { C = c, R = r })
	end
	local function free(c: Vector2, r: number): boolean
		for _, z in zones do
			if (z.C - c).Magnitude < z.R + r then
				return false
			end
		end
		return true
	end
	for _, s in FRONT_SPAWNS do
		keep(s, 5.5)
	end
	for _, s in DEEP_SPAWNS do
		keep(s, 5.5)
	end
	keep(GIANT, 13)
	keep(ELEVATOR, 8)
	keep(LIFT, 8)
	for z = ENTRANCE_Z, BRIDGE_FRONT, -4 do
		keep(Vector2.new(0, z), 5)
	end
	keep(Vector2.new(BRIDGE2_X, 6), 5)
	keep(Vector2.new(BRIDGE2_X, -21), 5)

	------------------------------------------------------------ ground

	local ground = group("Ground")
	-- the bed under everything (the river channel's bottom)
	block(ground, CFrame.new(0, -6, 0), Vector3.new(HALF_X * 2 + 4, 4, HALF_Z * 2 + 4), CRUST, nil, SOLID)
	-- strips across the river: each covers the bank up to the river edge
	local stripW = 6
	for x0 = -HALF_X, HALF_X - stripW, stripW do
		local x1 = x0 + stripW
		local zf, zb = math.huge, -math.huge
		for _, x in { x0, (x0 + x1) / 2, x1 } do
			local zc = riverZ(x)
			zf = math.min(zf, zc + RIVER_HW)
			zb = math.max(zb, zc - RIVER_HW)
		end
		local cx = (x0 + x1) / 2
		block(ground, CFrame.new(cx, -2, (zf + HALF_Z) / 2), Vector3.new(stripW, 4, HALF_Z - zf), GROUND, nil, SOLID).Name = "Floor"
		block(ground, CFrame.new(cx, -2, (zb - HALF_Z) / 2), Vector3.new(stripW, 4, zb + HALF_Z), GROUND, nil, SOLID).Name = "Floor"
	end

	-- hex-tiled path (basalt causeway) from the gate to the bridge
	local tiles = group("Path")
	local function tile(x: number, z: number, width: number)
		local shade = Geo.vary(TILE, rng, 0.05)
		hexColumn(tiles, CFrame.new(x, -0.1, z) * CFrame.Angles(0, rng:range(-0.05, 0.05), 0), width, 0.32, shade, DECOR)
	end
	for ix = -1, 1 do
		local x = ix * 2.6
		local z = ENTRANCE_Z + 2 - (ix % 2) * 1.5
		while z > BRIDGE_FRONT + 1 do
			tile(x, z, 2.7)
			z -= 3
		end
	end
	-- the Giant Crystal's round causeway plaza behind the bridge
	for ix = -3, 3 do
		local x = GIANT.X + ix * 3.46
		for iz = -3, 3 do
			local z = GIANT.Y + iz * 4 + (ix % 2) * 2
			if (Vector2.new(x, z) - GIANT).Magnitude <= 9.6 then
				tile(x, z, 3.6)
			end
		end
	end

	-- ash patches on a jittered grid (never overlapping), loose pebbles, and glowing
	-- cracks in the hot back half
	local function nearLava(p: Vector2, margin: number): boolean
		if math.abs(p.Y - riverZ(p.X)) < RIVER_HW + margin then
			return true
		end
		for _, pool in POOLS do
			if (pool.C - p).Magnitude < pool.R + margin then
				return true
			end
		end
		return false
	end
	for gx = -56, 40, 16 do
		for gz = -50, 38, 16 do
			local c = Vector2.new(gx + 8 + rng:range(-2, 2), gz + 8 + rng:range(-2, 2))
			if rng:chance(0.6) and not nearLava(c, 6) and math.abs(c.X) > 7 then
				local shade = if c.Y < -20 then GROUND:Lerp(CRUST_LIGHT, 0.35) else GROUND:Lerp(BASALT_DARK, 0.3)
				block(ground, CFrame.new(c.X, 0.02, c.Y) * CFrame.Angles(0, rng:range(0, math.pi), 0), Vector3.new(rng:range(5, 9), 0.08, rng:range(4, 7)), Geo.vary(shade, rng, 0.04), nil, DECOR)
			end
		end
	end
	for _ = 1, 44 do
		local p = Vector2.new(rng:range(-54, 54), rng:range(-46, 48))
		if not nearLava(p, 2.5) and math.abs(p.X) > 5 and free(p, 0.6) then
			local sz = rng:range(0.5, 1.3)
			block(ground, CFrame.new(p.X, sz * 0.25, p.Y) * Geo.randomTilt(rng, 0.4), Vector3.new(sz, sz * 0.7, sz * 0.9), Geo.vary(if rng:chance(0.5) then BASALT else BASALT_DARK, rng, 0.05), nil, DECOR)
		end
	end
	for _ = 1, 9 do
		local p = Vector2.new(rng:range(-50, 50), rng:range(-46, -22))
		if not nearLava(p, 1.5) then
			local yaw = rng:range(0, math.pi)
			for k = 0, 1 do
				local len = rng:range(2, 4)
				local a = yaw + (if k == 0 then 0.5 else -0.5)
				local off = Vector2.new(math.cos(yaw), math.sin(yaw)) * (k - 0.5) * 3
				block(ground, CFrame.new(p.X + off.X, 0.03, p.Y + off.Y) * CFrame.Angles(0, -a, 0), Vector3.new(len, 0.1, 0.22), LAVA, NEON, GLOW)
			end
		end
	end

	------------------------------------------------------------ lava river

	local lava = group("Lava")
	local riverParts: { Part } = {}
	for i = 1, #RIVER - 1 do
		local a, b = RIVER[i], RIVER[i + 1]
		local along = b - a
		local len = along.Magnitude
		local d2 = along.Unit
		local mid = (a + b) / 2
		local frame = facing(flat(mid, 0), Vector3.new(d2.X, 0, d2.Y))
		local w = RIVER_HW * 2
		local base = block(lava, frame * CFrame.new(0, LAVA_Y - 0.3, 0), Vector3.new(w + 2.4, 0.6, len + 3), LAVA, NEON, GLOW)
		base.Name = "LavaRiver"
		table.insert(riverParts, base)
		-- deeper red near the banks, a hot yellow core down the middle
		for _, s in { -1, 1 } do
			block(lava, frame * CFrame.new(s * (RIVER_HW - 0.9), LAVA_Y + 0.02, 0), Vector3.new(2, 0.1, len + 3), LAVA_DEEP, NEON, GLOW)
		end
		local wob = rng:range(-1, 1)
		block(lava, frame * CFrame.new(wob, LAVA_Y + 0.06, -len * 0.25), Vector3.new(2.4, 0.1, len * 0.5 + 1.5), LAVA_HOT, NEON, GLOW)
		block(lava, frame * CFrame.new(-wob * 0.8, LAVA_Y + 0.06, len * 0.25), Vector3.new(2.2, 0.1, len * 0.5 + 1.5), LAVA_HOT, NEON, GLOW)
		-- crust rafts drifting on it
		for _ = 1, 3 do
			local s = rng:range(1.2, 2.6)
			block(
				lava,
				frame * CFrame.new(rng:range(-RIVER_HW + 1.6, RIVER_HW - 1.6), LAVA_Y + 0.12, rng:range(-len / 2, len / 2)) * CFrame.Angles(0, rng:range(0, math.pi), 0),
				Vector3.new(s, 0.22, s * rng:range(0.5, 0.9)),
				Geo.vary(CRUST_LIGHT, rng, 0.05),
				nil,
				DECOR
			)
		end
		-- crusty rim along both banks (low: keeps players and rocks off the lava)
		local nrm = Vector2.new(-d2.Y, d2.X)
		for _, s in { -1, 1 } do
			local t = rng:range(0, 1.2)
			while t < len do
				local step = rng:range(2.6, 3.6)
				local p = a + d2 * t + nrm * s * (RIVER_HW + 0.2)
				local onBridge = math.abs(p.X) < 7 or math.abs(p.X - BRIDGE2_X) < BRIDGE2_W / 2 + 1.2
				if math.abs(p.X) < WALL_X - 1 and not onBridge then
					local top = rng:range(0.35, 1.3)
					local bottom = LAVA_Y - 0.8
					local depth = rng:range(2, 2.8)
					local rimFrame = facing(flat(p, 0), Vector3.new(d2.X, 0, d2.Y)) * CFrame.Angles(rng:range(-0.06, 0.06), rng:range(-0.2, 0.2), 0)
					block(lava, rimFrame * CFrame.new(0, (top + bottom) / 2, 0), Vector3.new(depth, top - bottom, step * rng:range(1.05, 1.3)), Geo.vary(if rng:chance(0.6) then CRUST else CRUST_LIGHT, rng, 0.05), nil, BUMP)
					if rng:chance(0.35) then
						-- a glowing crack low on the lava side
						block(lava, rimFrame * CFrame.new(-s * depth / 2, rng:range(LAVA_Y + 0.4, 0), 0) * CFrame.Angles(rng:range(-0.4, 0.4), 0, 0), Vector3.new(0.3, 0.24, step * 0.7), LAVA, NEON, GLOW)
					end
				end
				t += step
			end
		end
	end
	-- glow over the river (one light per stretch) and embers rising off it
	for _, x in { -50, -25, 25, 50 } do
		lamp(lava, Vector3.new(x, 3, riverZ(x)), rgb(255, 128, 48), 30, 1.6)
	end
	lamp(lava, Vector3.new(0, 0.2, riverZ(0)), rgb(255, 128, 48), 26, 1.6)
	for _, i in { 2, 4, 6 } do
		Style.emitter(riverParts[i], "Embers", LAVA_HOT, 5)
	end

	------------------------------------------------------------ bridges

	-- the main stone arch bridge over the river on the path
	local bridge = group("Bridge")
	do
		local n = 12
		local length = BRIDGE_FRONT - BRIDGE_BACK
		local zc = riverZ(0)
		local open0 = (BRIDGE_FRONT - (zc + RIVER_HW)) / length
		local open1 = (BRIDGE_FRONT - (zc - RIVER_HW)) / length
		local function point(t: number): Vector3
			return Vector3.new(0, BRIDGE_RISE * (1 - (2 * t - 1) ^ 2), BRIDGE_FRONT - length * t)
		end
		local function intrados(t: number): number
			if t <= open0 or t >= open1 then
				return LAVA_Y - 1
			end
			local u = (t - (open0 + open1) / 2) / ((open1 - open0) / 2)
			return LAVA_Y + 3 * (1 - u * u)
		end
		local thick = 1.1
		local right = Vector3.new(1, 0, 0)
		for i = 0, n - 1 do
			local t0, t1 = i / n, (i + 1) / n
			local a, b = point(t0), point(t1)
			local seg = b - a
			local segDir = seg.Unit
			local up = right:Cross(segDir)
			if up.Y < 0 then
				up = -up
			end
			local deck = CFrame.fromMatrix((a + b) / 2 - up * (thick / 2), right, up, -segDir)
			local shade = if i % 2 == 0 then STONE else STONE:Lerp(STONE_DARK, 0.4)
			block(bridge, deck, Vector3.new(BRIDGE_W, thick, seg.Magnitude + 0.2), Geo.vary(shade, rng, 0.03), nil, SOLID).Name = "Deck"
			-- parapets (keep players on the deck: walkway 8.2 wide)
			for _, s in { -1, 1 } do
				block(bridge, deck * CFrame.new(s * (BRIDGE_W / 2 - 0.45), thick / 2 + 0.65, 0), Vector3.new(0.9, 1.3, seg.Magnitude + 0.25), Geo.vary(STONE, rng, 0.03), nil, BUMP)
			end
			-- spandrel wall down to the arch (over the lava) or into the bank
			local tm = (t0 + t1) / 2
			local deckBottom = math.min(a.Y, b.Y) - thick + 0.05
			local bottom = intrados(tm)
			if deckBottom - bottom > 0.2 then
				local zMid = (a.Z + b.Z) / 2
				block(bridge, CFrame.new(0, (deckBottom + bottom) / 2, zMid), Vector3.new(BRIDGE_W - 0.6, deckBottom - bottom, math.abs(seg.Z) + 0.05), Geo.vary(STONE_DARK, rng, 0.03), nil, BUMP)
				if bottom > LAVA_Y then
					-- the arch ring: lighter voussoirs on both faces, lava glow under them
					for _, s in { -1, 1 } do
						block(bridge, CFrame.new(s * (BRIDGE_W / 2 - 0.2), bottom + 0.35, zMid), Vector3.new(0.5, 0.8, math.abs(seg.Z) - 0.12), STONE, nil, DECOR)
						block(bridge, CFrame.new(s * (BRIDGE_W / 2 - 0.3), bottom - 0.1, zMid), Vector3.new(0.4, 0.14, math.abs(seg.Z)), LAVA, NEON, GLOW)
					end
				end
			end
		end
		-- end posts: short basalt columns with lava braziers
		for _, t in { 0, 1 } do
			local p = point(t)
			for _, s in { -1, 1 } do
				local base = CFrame.new(s * (BRIDGE_W / 2 + 0.6), p.Y - 0.2, p.Z)
				hexColumn(bridge, base, 1.9, 3.4, BASALT_DARK, BUMP)
				block(bridge, base * CFrame.new(0, 3.6, 0), Vector3.new(1.6, 0.4, 1.6), Style.C.Iron, METAL, DECOR)
				block(bridge, base * CFrame.new(0, 4.1, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.9, 0.7, 0.9), LAVA_HOT, NEON, GLOW)
			end
		end
	end

	-- the slab bridge on the right: a basalt slab on two hex piers, ramps at both ends
	do
		local zc = riverZ(BRIDGE2_X)
		local z0, z1 = zc + RIVER_HW + 3.5, zc - RIVER_HW - 3.5
		local top = 0.9
		local len = z0 - z1
		block(bridge, CFrame.new(BRIDGE2_X, top - 0.5, (z0 + z1) / 2), Vector3.new(BRIDGE2_W, 1, len), Geo.vary(STONE, rng, 0.03), nil, SOLID).Name = "Deck"
		for _, s in { -1, 1 } do
			block(bridge, CFrame.new(BRIDGE2_X + s * (BRIDGE2_W / 2 - 0.35), top + 0.3, (z0 + z1) / 2), Vector3.new(0.7, 0.6, len - 1), STONE_DARK, nil, BUMP)
			-- ramps (wedge slope faces outward along the bridge)
			local zEnd = if s > 0 then z0 + 1.5 else z1 - 1.5
			wedge(bridge, CFrame.new(BRIDGE2_X, top / 2, zEnd) * CFrame.Angles(0, if s > 0 then math.pi else 0, 0), Vector3.new(BRIDGE2_W, top, 3), STONE_DARK, SOLID)
		end
		for _, dz in { -3, 3 } do
			hexColumn(bridge, CFrame.new(BRIDGE2_X, LAVA_Y - 2, zc + dz), 3.2, top - 1 - (LAVA_Y - 2), BASALT_DARK, BUMP)
		end
	end

	------------------------------------------------------------ lava pools and the lava fall

	local function lavaPool(pool: Pool, index: number): Part
		local c, r = pool.C, pool.R
		local m = group("LavaPool")
		local disc = cylinder(m, Vector3.new(c.X, 0.25, c.Y), 0.4, r * 2 + 1, LAVA, NEON, GLOW)
		disc.Name = "Lava"
		cylinder(m, Vector3.new(c.X + rng:range(-0.6, 0.6), 0.36, c.Y + rng:range(-0.6, 0.6)), 0.3, r * 0.95, LAVA_HOT, NEON, GLOW)
		for _ = 1, 3 do
			local a = rng:range(0, math.pi * 2)
			local d = rng:range(r * 0.45, r * 0.8)
			local s = rng:range(0.9, 1.8)
			block(m, CFrame.new(c.X + math.cos(a) * d, 0.5, c.Y + math.sin(a) * d) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(s, 0.2, s * 0.7), CRUST_LIGHT, nil, DECOR)
		end
		-- the crusty rim
		local count = math.max(10, math.floor(math.pi * 2 * r / 2.4))
		for k = 1, count do
			local a = (k / count) * math.pi * 2 + rng:range(-0.08, 0.08)
			local p = Vector3.new(c.X + math.cos(a) * (r + 0.7), 0, c.Y + math.sin(a) * (r + 0.7))
			local h = rng:range(0.8, 1.7)
			local arc = math.pi * 2 * (r + 0.7) / count
			local rimFrame = facing(p, Vector3.new(-math.sin(a), 0, math.cos(a))) * CFrame.Angles(0, rng:range(-0.15, 0.15), rng:range(-0.08, 0.08))
			block(m, rimFrame * CFrame.new(0, h / 2 - 0.2, 0), Vector3.new(rng:range(1.8, 2.6), h, arc * rng:range(1.15, 1.4)), Geo.vary(if k % 3 == 0 then CRUST_LIGHT else CRUST, rng, 0.05), nil, BUMP)
		end
		-- glowing cracks running out over the ground
		for _ = 1, 3 do
			local a = rng:range(0, math.pi * 2)
			local len = rng:range(3, 6)
			local d = r + 0.5 + len / 2
			block(m, CFrame.new(c.X + math.cos(a) * d, 0.02, c.Y + math.sin(a) * d) * CFrame.Angles(0, -a + rng:range(-0.25, 0.25), 0), Vector3.new(len, 0.1, 0.24), LAVA, NEON, GLOW)
		end
		lamp(m, Vector3.new(c.X, 3.5, c.Y), rgb(255, 132, 50), r * 3.6 + 6, if index == 1 then 2 else 1.6)
		return disc
	end
	local poolDiscs: { Part } = {}
	for i, pool in POOLS do
		table.insert(poolDiscs, lavaPool(pool, i))
	end
	Style.emitter(poolDiscs[2], "Embers", LAVA_HOT, 4)
	Style.emitter(poolDiscs[3], "Embers", LAVA_HOT, 4)

	-- the lava fall: a crack in the back wall, a sheet onto a rock ledge, a wider
	-- sheet from the ledge into the pool, a splash
	local fall = group("LavaFall")
	do
		local wallZ = COL_BACK + 1 -- front face of the rock behind the fall
		-- the cracked rock face behind the fall
		block(fall, CFrame.new(FALL_X, 17, wallZ - 1.5), Vector3.new(13, 34, 3), BASALT_DARK, nil, BUMP)
		for k, seg in { { -1.2, 27.5, 0.5 }, { 0.8, 31.5, -0.6 }, { -0.4, 35, 0.4 }, { 3, 28, 0.9 }, { -3.4, 29, -0.9 } } do
			local len = if k <= 3 then 4.4 else 3.6
			block(fall, CFrame.new(FALL_X + seg[1], seg[2], wallZ) * CFrame.Angles(0, 0, seg[3]), Vector3.new(0.5, len, 0.5), if k % 2 == 0 then GOLD else LAVA, NEON, GLOW)
		end
		-- the spout lip and the ledge halfway down
		local ledgeY = 13
		block(fall, CFrame.new(FALL_X, FALL_TOP + 0.6, wallZ + 1.2), Vector3.new(8.4, 1.6, 3), CRUST, nil, DECOR)
		block(fall, CFrame.new(FALL_X, FALL_TOP - 0.1, wallZ + 2.5), Vector3.new(6.2, 0.4, 0.5), LAVA_HOT, NEON, GLOW)
		block(fall, CFrame.new(FALL_X, ledgeY - 0.7, wallZ + 2), Vector3.new(10, 1.4, 5), CRUST, nil, DECOR)
		block(fall, CFrame.new(FALL_X - 0.6, ledgeY - 2.2, wallZ + 1.2) * CFrame.Angles(math.rad(30), 0, 0), Vector3.new(7, 2.6, 3.2), CRUST_LIGHT, nil, DECOR)
		block(fall, CFrame.new(FALL_X, ledgeY + 0.04, wallZ + 2.2), Vector3.new(7, 0.1, 3.8), LAVA, NEON, GLOW)
		local function sheet(y0: number, y1: number, z: number, w: number, streaks: number): Part
			local h = y0 - y1
			local cy = (y0 + y1) / 2
			local main = block(fall, CFrame.new(FALL_X, cy, z), Vector3.new(w, h, 1), LAVA, NEON, GLOW)
			main.Name = "LavaFall"
			block(fall, CFrame.new(FALL_X + rng:range(-0.4, 0.4), cy, z + 0.55), Vector3.new(w * 0.3, h, 0.12), LAVA_HOT, NEON, GLOW)
			for _, sd in { -1, 1 } do
				block(fall, CFrame.new(FALL_X + sd * (w / 2 - 0.3), cy, z + 0.5), Vector3.new(0.6, h, 0.12), LAVA_DEEP, NEON, GLOW)
			end
			for _ = 1, streaks do
				-- cooling crust streaks running down
				local sh = rng:range(1.5, 3.5)
				block(fall, CFrame.new(FALL_X + rng:range(-w * 0.35, w * 0.35), rng:range(y1 + sh / 2, y0 - sh / 2), z + 0.56), Vector3.new(0.35, sh, 0.1), CRUST_LIGHT, nil, GLOW)
			end
			return main
		end
		sheet(FALL_TOP, ledgeY, wallZ + 2.2, 5.4, 2)
		sheet(ledgeY - 0.4, 5, wallZ + 4.2, 6.6, 2)
		sheet(5.4, 0.3, wallZ + 4.5, 8.2, 1)
		-- splash at the foot
		local splash = block(fall, CFrame.new(FALL_X, 0.55, wallZ + 5.6), Vector3.new(7, 0.5, 3), LAVA_HOT, NEON, GLOW)
		splash.Name = "Splash"
		for k = 1, 5 do
			local sz = rng:range(0.9, 1.6)
			block(fall, CFrame.new(FALL_X + (k - 3) * 1.6, 0.7 + sz * 0.3, wallZ + 5.6 + rng:range(-1, 1)) * Geo.randomTilt(rng, 0.6), Vector3.new(sz, sz * 0.7, sz), if k % 2 == 0 then LAVA_HOT else LAVA, NEON, GLOW)
		end
		Style.emitter(splash, "Fire", LAVA, 14)
		lamp(fall, Vector3.new(FALL_X, 19, wallZ + 6), rgb(255, 150, 60), 26, 1.5)
	end

	------------------------------------------------------------ walls

	local walls = group("Walls")
	local veinRng = Rng.new(2203)
	local function wallRun(from: Vector3, to: Vector3, face: Vector3, height: number)
		MineKit.wall(walls, pt(from.X, 0, from.Z), pt(to.X, 0, to.Z), height, dir(face.X, 0, face.Z), WALL_COLORS, rng, { Depth = 5, Glow = VEIN })
	end
	-- side walls: split where the river runs into its tunnels
	for _, s in { -1, 1 } do
		local x = s * WALL_X
		local zc = riverZ(x)
		local gap0, gap1 = zc + RIVER_HW + 1.5, zc - RIVER_HW - 1.5
		local face = Vector3.new(-s, 0, 0)
		wallRun(Vector3.new(x, 0, HALF_Z), Vector3.new(x, 0, gap0), face, 46)
		wallRun(Vector3.new(x, 0, gap1), Vector3.new(x, 0, -HALF_Z), face, 46)
		-- the tunnel mouth: a crusty lintel beam (columns stand on it), rock behind, glowing underside
		block(walls, CFrame.new(x + s * 3.5, 27, zc), Vector3.new(4, 38, gap0 - gap1 + 2), BASALT_DARK, nil, BUMP)
		block(walls, CFrame.new(COL_X * s, 6.8, zc), Vector3.new(7, 1.4, gap0 - gap1 + 3), CRUST, nil, BUMP)
		block(walls, CFrame.new(COL_X * s - s * 3.4, 6, zc), Vector3.new(0.4, 0.3, gap0 - gap1 - 1), LAVA, NEON, GLOW)
		lamp(walls, Vector3.new(x - s * 4, 4, zc), rgb(255, 128, 48), 30, 1.6)
	end
	wallRun(Vector3.new(-HALF_X, 0, WALL_BACK), Vector3.new(HALF_X, 0, WALL_BACK), Vector3.new(0, 0, 1), 46)
	if not cutaway then
		wallRun(Vector3.new(HALF_X, 0, WALL_FRONT), Vector3.new(OPENING, 0, WALL_FRONT), Vector3.new(0, 0, -1), 46)
		wallRun(Vector3.new(-OPENING, 0, WALL_FRONT), Vector3.new(-HALF_X, 0, WALL_FRONT), Vector3.new(0, 0, -1), 46)
		-- rock over the way in
		block(walls, CFrame.new(0, 30, WALL_FRONT + 2), Vector3.new(OPENING * 2 + 2, 32, 4), BASALT_DARK, nil, BUMP)
	end
	-- the outer shell (closes every gap between the jagged wall tops and the ceiling)
	for _, s in { -1, 1 } do
		block(walls, CFrame.new(s * (HALF_X + 1), 19, 0), Vector3.new(2, 54, HALF_Z * 2 + 4), BASALT_DARK, nil, BUMP)
	end
	block(walls, CFrame.new(0, 19, -HALF_Z - 1), Vector3.new(HALF_X * 2 + 4, 54, 2), BASALT_DARK, nil, BUMP)
	if not cutaway then
		for _, s in { -1, 1 } do
			local w = HALF_X - OPENING
			block(walls, CFrame.new(s * (OPENING + w / 2), 19, HALF_Z + 1), Vector3.new(w + 2, 54, 2), BASALT_DARK, nil, BUMP)
		end
		block(walls, CFrame.new(0, 30, HALF_Z + 1), Vector3.new(OPENING * 2, 32, 2), BASALT_DARK, nil, BUMP)
	end

	-- basalt column rows in front of the rock walls: a tall back row, a stepped
	-- front row and a few knee-high stools, glowing zig-zag veins on the columns
	local columns = group("BasaltColumns")
	local function columnRow(a: Vector2, b: Vector2, inward: Vector2, skip: (p: Vector2) -> boolean, frontRow: (p: Vector2) -> boolean, deepBonus: boolean, raise: ((p: Vector2) -> number)?)
		local along = b - a
		local len = along.Magnitude
		local d2 = along.Unit
		local t = 0
		while t < len do
			local width = rng:range(4.2, 6)
			local p = a + d2 * t + inward * rng:range(-0.4, 0.4)
			t += width * 0.88
			if not skip(p) then
				local deep = deepBonus and p.Y < -18
				local h = rng:range(13, 27) + (if deep then 4 else 0)
				local baseY = if raise then raise(p) else 0
				local frame = facing(flat(p, baseY), Vector3.new(inward.X, 0, inward.Y)) * CFrame.Angles(0, rng:range(-0.12, 0.12), 0)
				local shade = Geo.vary(if rng:chance(0.3) then BASALT_LIGHT:Lerp(BASALT, 0.5) else BASALT, rng, 0.06)
				hexColumn(columns, frame, width, h, shade, BUMP)
				if veinRng:chance(if deep or p.Y < -30 then 0.55 else 0.28) then
					columnVein(columns, frame, width, h, if veinRng:chance(0.2) then GOLD else VEIN, veinRng)
				end
				if veinRng:chance(0.15) then
					-- a gold nugget sitting in the face
					local s = veinRng:range(0.6, 1)
					block(columns, frame * CFrame.new(veinRng:range(-0.6, 0.6), veinRng:range(2, h * 0.6), -width / 2) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s, s, s), GOLD, NEON, GLOW)
				end
				if veinRng:chance(0.25) then
					-- glow in the seam to the next column
					block(columns, CFrame.new(flat(p + d2 * width * 0.47 - inward * 0.9, baseY + h * 0.4)), Vector3.new(0.35, h * veinRng:range(0.45, 0.75), 0.35), VEIN, NEON, GLOW)
				end
				-- stepped front row
				local p2 = p + inward * width * 0.82 + d2 * rng:range(-1, 1)
				local w2 = width * rng:range(0.72, 0.95)
				if frontRow(p2) and rng:chance(0.6) and free(p2, w2 / SQRT3) then
					local h2 = rng:range(3, 11)
					local f2 = facing(flat(p2, 0), Vector3.new(inward.X, 0, inward.Y)) * CFrame.Angles(0, rng:range(-0.15, 0.15), 0)
					hexColumn(columns, f2, w2, h2, Geo.vary(BASALT_LIGHT:Lerp(BASALT, 0.35), rng, 0.06), BUMP)
					if veinRng:chance(0.2) then
						columnVein(columns, f2, w2, h2, VEIN, veinRng)
					end
					local p3 = p2 + inward * w2 * 0.78 + d2 * rng:range(-0.8, 0.8)
					local w3 = w2 * rng:range(0.7, 0.9)
					if rng:chance(0.35) and free(p3, w3 / SQRT3) then
						hexColumn(columns, facing(flat(p3, 0), Vector3.new(inward.X, 0, inward.Y)), w3, rng:range(0.8, 2.6), Geo.vary(BASALT_LIGHT, rng, 0.05), BUMP)
					end
				end
			end
		end
	end
	for _, s in { -1, 1 } do
		local x = s * COL_X
		columnRow(Vector2.new(x, HALF_Z - 2), Vector2.new(x, -HALF_Z + 2), Vector2.new(-s, 0), function(_p: Vector2): boolean
			return false
		end, function(p: Vector2): boolean
			return math.abs(p.Y - riverZ(p.X)) > RIVER_HW + 4 and not (p.Y > 36 and s > 0)
		end, true, function(p: Vector2): number
			-- columns over the river tunnel stand on its lintel beam
			return if math.abs(p.Y - riverZ(p.X)) < RIVER_HW + 2.5 then 7.4 else 0
		end)
	end
	columnRow(Vector2.new(-HALF_X + 4, COL_BACK), Vector2.new(HALF_X - 4, COL_BACK), Vector2.new(0, 1), function(p: Vector2): boolean
		return math.abs(p.X - FALL_X) < 6
	end, function(p: Vector2): boolean
		return math.abs(p.X) > 40 and math.abs(p.X - FALL_X) > 10
	end, true)
	if not cutaway then
		columnRow(Vector2.new(HALF_X - 4, COL_FRONT), Vector2.new(-HALF_X + 4, COL_FRONT), Vector2.new(0, -1), function(p: Vector2): boolean
			return math.abs(p.X) < OPENING + 2
		end, function(_p: Vector2): boolean
			return false
		end, false)
	end
	-- frame the lava fall with two tall columns
	for _, s in { -1, 1 } do
		hexColumn(columns, facing(Vector3.new(FALL_X + s * 7.5, 0, COL_BACK + 0.5), Vector3.new(0, 0, 1)), 5, 34, BASALT_DARK, BUMP)
	end
	-- and the river tunnels
	for _, s in { -1, 1 } do
		local x = s * (COL_X + 1)
		local zc = riverZ(x)
		for _, side in { -1, 1 } do
			hexColumn(columns, facing(Vector3.new(x, 0, zc + side * (RIVER_HW + 3)), Vector3.new(-s, 0, 0)), 4.6, rng:range(20, 26), BASALT_DARK, BUMP)
		end
	end

	------------------------------------------------------------ ceiling

	local ceiling = group("Ceiling")
	local zMin = -HALF_Z - 2
	local zMax = if cutaway then 0 else HALF_Z + 2
	block(ceiling, CFrame.new(0, CEIL + 3, (zMin + zMax) / 2), Vector3.new(HALF_X * 2 + 4, 6, zMax - zMin), BASALT_DARK, nil, BUMP)
	local chunks = if cutaway then 12 else 18
	for k = 1, chunks do
		local x = rng:range(-54, 54)
		local edge = k <= 6 and cutaway
		local z = if edge then rng:range(-4, 0) else rng:range(zMin + 8, zMax - 6)
		local h = if edge then rng:range(4, 8) else rng:range(2, 5.5)
		block(ceiling, CFrame.new(x, CEIL - h / 2 + 0.4, z) * CFrame.Angles(0, rng:range(0, math.pi), 0), Vector3.new(rng:range(8, 15), h, rng:range(7, 12)), Geo.vary(BASALT, rng, 0.05), nil, DECOR)
	end
	local zSpan = zMax - zMin - 10
	MineKit.stalactites(ceiling, pt(0, CEIL + 0.3, (zMin + zMax) / 2), Vector2.new(HALF_X * 2 - 16, zSpan), WALL_COLORS, rng, if cutaway then 34 else 60)
	-- glowing cracks across the ceiling (the deep half is hotter)
	for _ = 1, 5 do
		local x = rng:range(-48, 48)
		local z = rng:range(-48, -6)
		local yaw = rng:range(0, math.pi)
		local base = CFrame.new(x, CEIL - 0.1, z) * CFrame.Angles(0, yaw, 0)
		local px, pz = 0, 0
		for j = 1, 3 do
			local len = rng:range(3, 5)
			local a = (if j % 2 == 0 then 1 else -1) * rng:range(0.3, 0.6)
			local dx, dz = math.sin(a) * len, -math.cos(a) * len
			block(ceiling, base * CFrame.new(px + dx / 2, 0, pz + dz / 2) * CFrame.Angles(0, -a, 0), Vector3.new(0.3, 0.35, len + 0.3), VEIN, NEON, GLOW)
			px += dx
			pz += dz
		end
	end

	------------------------------------------------------------ crystals

	local crystals = group("Crystals")
	local orange = { PAL.Crystal, PAL.Crystal2 }
	local ruby = { PAL.Crystal2, PAL.Crystal }
	local function cluster(pos: Vector3, up: Vector3, count: number, height: number, colors: { Color3 }, seed: number)
		local u = up.Unit
		local right = u:Cross(Vector3.new(0, 0, 1))
		if right.Magnitude < 0.1 then
			right = u:Cross(Vector3.new(1, 0, 0))
		end
		right = right.Unit
		local root = origin * CFrame.fromMatrix(pos, right, u)
		MineKit.crystals(crystals, root, count, height, "Tipped", colors, seed)
	end
	-- front corners and side walls (small)
	cluster(Vector3.new(-55, 0, 48), Vector3.new(0.35, 1, -0.3), 6, 4.5, orange, 21)
	cluster(Vector3.new(56, 0, 51), Vector3.new(-0.35, 1, -0.3), 6, 4.5, ruby, 22)
	cluster(Vector3.new(-53.5, 0, 15), Vector3.new(0.5, 1, 0), 5, 4, orange, 23)
	cluster(Vector3.new(54, 0, 12), Vector3.new(-0.5, 1, 0), 5, 4.5, ruby, 24)
	-- deep: big corner clusters, the back wall, side walls, out of the wall, from the ceiling
	cluster(Vector3.new(-53, 0, -47), Vector3.new(0.4, 1, 0.4), 9, 9, ruby, 25)
	cluster(Vector3.new(54, 0, -47), Vector3.new(-0.4, 1, 0.4), 9, 8.5, orange, 26)
	cluster(Vector3.new(-8, 0, -48.5), Vector3.new(0, 1, 0.45), 7, 6.5, ruby, 27)
	cluster(Vector3.new(9, 0, -48.5), Vector3.new(0.1, 1, 0.45), 7, 5.5, orange, 28)
	cluster(Vector3.new(-54, 0, -35), Vector3.new(0.5, 1, 0), 7, 6, orange, 29)
	cluster(Vector3.new(55, 0, -23), Vector3.new(-0.5, 1, 0), 7, 6, ruby, 30)
	for k, ledge in { Vector3.new(-30, 12, -48.6), Vector3.new(21, 15, -48.6) } do
		-- a rock ledge sticking out of the back wall with crystals on it
		block(crystals, CFrame.new(ledge.X, ledge.Y - 0.6, ledge.Z - 1.2), Vector3.new(5.5, 1.4, 5), BASALT_DARK, nil, DECOR)
		block(crystals, CFrame.new(ledge.X, ledge.Y - 2, ledge.Z - 2.2) * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(4, 2.4, 3), BASALT, nil, DECOR)
		cluster(ledge + Vector3.new(0, -0.1, 0.2), Vector3.new(0, 1, 0.35), 6, 4, if k == 1 then orange else ruby, 30 + k)
	end
	cluster(Vector3.new(-24, CEIL + 0.4, -28), Vector3.new(0.1, -1, 0), 6, 4, orange, 33)
	cluster(Vector3.new(20, CEIL + 0.4, -38), Vector3.new(-0.1, -1, 0.1), 6, 3.5, ruby, 34)
	lamp(crystals, Vector3.new(-50, 5, -44), rgb(255, 70, 90), 26, 1.5)
	lamp(crystals, Vector3.new(51, 5, -44), rgb(255, 120, 50), 26, 1.5)

	------------------------------------------------------------ machines and props

	local props = group("Props")
	-- the blaster gate in the way in, facing the arriving players
	MineKit.gate(model, origin * facing(Vector3.new(0, 0, GATE_Z), Vector3.new(0, 0, 1)), 14, MineFloors.get(2).MinBlaster, { BASALT, BASALT_LIGHT, BASALT_DARK })
	-- the elevator stop on the left, turned toward the way in
	MineKit.elevator(model, origin * facing(flat(ELEVATOR, 0), Vector3.new(1, 0, 1).Unit), 2)
	-- the train's ore lift on the right, hung from a timber beam out of the wall
	MineKit.oreLift(model, pt(LIFT.X, 0, LIFT.Y), "MineFloor2")
	block(props, CFrame.new((LIFT.X - 3 + WALL_X + 2) / 2, 30.6, LIFT.Y), Vector3.new(WALL_X + 2 - LIFT.X + 3, 1.2, 1.4), Style.C.WoodDark, nil, DECOR)
	block(props, CFrame.new(LIFT.X + 10.5, 26.6, LIFT.Y) * CFrame.Angles(0, 0, math.rad(-45)), Vector3.new(9, 0.9, 1), Style.C.Wood, nil, DECOR)

	-- lantern posts at the way in, timber supports with hanging lanterns over the path
	for _, s in { -1, 1 } do
		Style.lantern(props, origin * facing(Vector3.new(s * 7.5, 0, 45), Vector3.new(-s, 0, 0)), { Kind = "Post", Light = true, Range = 22, Brightness = 1.4 })
	end
	-- stone lanterns lighting the side walls of the front field
	for _, spot in { Vector2.new(-52, 26), Vector2.new(53, 18) } do
		Style.lantern(props, origin * CFrame.new(spot.X, 0, spot.Y), { Kind = "Pillar", Light = true, Range = 28, Brightness = 1.5 })
		keep(spot, 2)
	end
	for k, z in { 35, 20 } do
		local frame = CFrame.new(0, 0, z)
		for _, s in { -1, 1 } do
			block(props, frame * CFrame.new(s * 6.5, 5.5, 0), Vector3.new(1, 11, 1), Style.C.WoodDark, nil, BUMP)
			block(props, frame * CFrame.new(s * 5.4, 9.9, 0) * CFrame.Angles(0, 0, s * math.rad(45)), Vector3.new(0.5, 2.6, 0.5), Style.C.Wood, nil, DECOR)
		end
		block(props, frame * CFrame.new(0, 11.4, 0), Vector3.new(15, 1, 1.2), Style.C.Wood, nil, DECOR)
		Style.lantern(props, origin * frame * CFrame.new(if k == 1 then -4.2 else 4.2, 10.9, 0), { Kind = "Hanging", Light = true, Range = 26, Brightness = 1.5 })
	end

	-- rails with a loaded cart running toward the lift
	local railsFrom, railsTo = Vector3.new(19, 0, 47.5), Vector3.new(40, 0, 47.5)
	Style.rails(props, pt(railsFrom.X, 0, railsFrom.Z), pt(railsTo.X, 0, railsTo.Z))
	Style.mineCart(props, origin * facing(Vector3.new(31, 0, 47.5), Vector3.new(1, 0, 0)), rng, { Load = "Gold" })
	block(props, CFrame.new(18.4, 0.8, 47.5), Vector3.new(1.2, 1.6, 4.4), Style.C.WoodDark, nil, BUMP)
	-- crates and barrels by the elevator, a few by the lift
	Style.crate(props, origin * CFrame.new(-40, 0, 48), rng, 2.6)
	Style.crate(props, origin * CFrame.new(-40, 2.6, 48), rng, 2)
	Style.crate(props, origin * CFrame.new(-43, 0, 47), rng, 2.2)
	Style.barrel(props, pt(-36.5, 0, 49.5), rng)
	Style.barrel(props, pt(-46, 0, 49), rng)
	Style.crate(props, origin * CFrame.new(53, 0, 33), rng, 2.4)
	Style.barrel(props, pt(54, 0, 29.5), rng)
	-- the cave's name board facing the arrivals
	do
		local boardAt = CFrame.new(15.5, 3.6, 44)
		for _, s in { -1, 1 } do
			block(props, CFrame.new(15.5 + s * 3.2, 2.2, 44), Vector3.new(0.6, 4.4, 0.6), Style.C.WoodDark, nil, BUMP)
		end
		Style.sign(props, origin * boardAt * CFrame.Angles(0, math.pi, 0), "EMBER CAVES", 7, 1.8, { Kind = "Wood", DoubleSided = true })
	end
	-- loose basalt boulders in the open corners
	for _ = 1, 10 do
		local p = Vector2.new(rng:range(-52, 52), rng:range(-46, 46))
		if math.abs(p.Y - riverZ(p.X)) > RIVER_HW + 4 and free(p, 3.2) and math.abs(p.X) > 8 then
			local inPool = false
			for _, pool in POOLS do
				if (pool.C - p).Magnitude < pool.R + 4 then
					inPool = true
				end
			end
			if not inPool then
				hexColumn(props, facing(flat(p, 0), Vector3.new(rng:range(-1, 1), 0, 1)), rng:range(1.8, 2.8), rng:range(0.8, 2.2), Geo.vary(BASALT_LIGHT, rng, 0.05), BUMP)
				keep(p, 2)
			end
		end
	end

	------------------------------------------------------------ spawns and markers

	local spawns = MineKit.spawns(model)
	for _, s in FRONT_SPAWNS do
		spawns.add(origin * CFrame.new(s.X, 0, s.Y), false)
	end
	for _, s in DEEP_SPAWNS do
		spawns.add(origin * CFrame.new(s.X, 0, s.Y), true)
	end
	MineKit.marker(model, "GiantSpawn", origin * CFrame.new(GIANT.X, 0, GIANT.Y))
	MineKit.marker(model, "Entrance", origin * facing(Vector3.new(0, 0, ENTRANCE_Z), Vector3.new(0, 0, -1)))

	model.Parent = parent
	return model
end

return Floor
