--[[
	Ground, cliffs, sea, the quarry pit, enclosed caves, tunnels and the
	mountain range. Built from blocks only (no Terrain) for the low-poly look,
	and so the whole map can be generated outside Studio too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local Land = {}

type Box = { Min: Vector3, Max: Vector3 }

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function solid(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

-- Axis-aligned box part from min/max corners.
local function boxPart(parent: Instance, min: Vector3, max: Vector3, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
	return Geo.block(parent, CFrame.new((min + max) / 2), max - min, color, material, solid(extra))
end

local function boxesOverlap2D(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3): boolean
	return aMin.X < bMax.X and aMax.X > bMin.X and aMin.Z < bMax.Z and aMax.Z > bMin.Z
end

-- Rooms that must stay hollow. Ceiling = Max.Y of the room's roof.
local function protectedSpaces(): { { box: Box, roofTop: number?, open: boolean? } }
	local caves = WorldLayout.Caves
	local quarry = WorldLayout.Quarry
	return {
		{ box = { Min = Vector3.new(quarry.Min.X, quarry.Min.Y, quarry.Min.Z), Max = Vector3.new(quarry.Max.X, 200, quarry.Max.Z) }, open = true },
		{ box = { Min = caves.EmberCaves.Min, Max = caves.EmberCaves.Max }, roofTop = caves.EmberCaves.Max.Y + 4 },
		{ box = { Min = caves.DeepHollow.Min, Max = caves.DeepHollow.Max }, roofTop = caves.DeepHollow.Max.Y + 4 },
		{ box = { Min = caves.Grotto.Min, Max = caves.Grotto.Max }, roofTop = caves.Grotto.Max.Y + 3 },
		-- tunnels
		{ box = { Min = Vector3.new(-13, -12, -246), Max = Vector3.new(13, 8, -234) }, roofTop = 8 },
		{ box = { Min = Vector3.new(-13, -40, -382), Max = Vector3.new(13, 4, -350) }, roofTop = 4 },
		{ box = { Min = Vector3.new(70, -12, -192), Max = Vector3.new(90, 2, -172) }, roofTop = 2 },
	}
end

-- Builds a wall of chunky rocks along a line, skipping gaps.
local function rockWall(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	inward: Vector3,
	bottom: number,
	top: number,
	color: Color3,
	rng: Rng.Rng,
	gaps: { { number } }?
)
	local delta = to - from
	local length = delta.Magnitude
	local dir = delta.Unit
	local step = 9
	local count = math.ceil(length / step)
	for i = 0, count do
		local t = math.min(i * step, length)
		local p = from + dir * t
		local skip = false
		if gaps then
			for _, gap in gaps do
				-- gap = {centerAlongLine, halfWidth}
				if math.abs(t - gap[1]) < gap[2] + 6.5 then
					skip = true
				end
			end
		end
		if not skip then
			local height = top - bottom + rng:range(0, 6)
			local width = rng:range(9, 13)
			local depth = rng:range(7, 10)
			local center = Vector3.new(p.X, bottom + height / 2 - 1, p.Z) - inward * (depth / 2 - rng:range(0.5, 2))
			local cf = CFrame.lookAt(center, center + inward) * CFrame.Angles(rng:range(-0.05, 0.05), rng:range(-0.18, 0.18), rng:range(-0.05, 0.05))
			Geo.block(parent, cf, Vector3.new(width, height, depth), Geo.vary(color, rng, 0.06), nil, solid())
			-- a smaller boulder at the foot of the wall for a natural edge
			if rng:chance(0.45) then
				local s = Vector3.new(rng:range(3, 6), rng:range(2.5, 5), rng:range(3, 5))
				local foot = Vector3.new(p.X, bottom, p.Z) + inward * rng:range(1, 3) + dir * rng:range(-3, 3)
				Geo.rock(parent, CFrame.new(foot), s, color, rng, nil, solid())
			end
		end
	end
end

-- Hanging rocks under a cave ceiling.
local function stalactites(parent: Instance, min: Vector3, max: Vector3, ceilingY: number, count: number, color: Color3, rng: Rng.Rng)
	for _ = 1, count do
		local x = rng:range(min.X + 6, max.X - 6)
		local z = rng:range(min.Z + 6, max.Z - 6)
		local h = rng:range(4, 9)
		local w = rng:range(2, 4.5)
		local cf = CFrame.new(x, ceilingY - h / 2, z) * CFrame.Angles(math.pi, rng:range(0, 6.28), 0)
		Geo.wedge(parent, cf, Vector3.new(w, h, w), Geo.vary(color, rng, 0.06), nil, decor({ CastShadow = false }))
	end
end

local function caveRoom(
	parent: Instance,
	name: string,
	min: Vector3,
	max: Vector3,
	color: Color3,
	darkColor: Color3,
	rng: Rng.Rng,
	gaps: { south: { { number } }?, north: { { number } }?, west: { { number } }?, east: { { number } }? }
): Model
	local room = Instance.new("Model")
	room.Name = name
	room.Parent = parent
	local floorY = min.Y
	local ceilY = max.Y
	-- floor
	boxPart(room, Vector3.new(min.X - 8, floorY - 6, min.Z - 8), Vector3.new(max.X + 8, floorY, max.Z + 8), darkColor)
	-- ceiling (4 studs thick)
	boxPart(room, Vector3.new(min.X - 10, ceilY, min.Z - 10), Vector3.new(max.X + 10, ceilY + 4, max.Z + 10), darkColor, nil, { CastShadow = true })
	-- walls (inward normals)
	local width = max.X - min.X
	local depth = max.Z - min.Z
	rockWall(room, Vector3.new(min.X, 0, max.Z), Vector3.new(max.X, 0, max.Z), Vector3.new(0, 0, -1), floorY, ceilY, color, rng, gaps.south)
	rockWall(room, Vector3.new(min.X, 0, min.Z), Vector3.new(max.X, 0, min.Z), Vector3.new(0, 0, 1), floorY, ceilY, color, rng, gaps.north)
	rockWall(room, Vector3.new(min.X, 0, min.Z), Vector3.new(min.X, 0, max.Z), Vector3.new(1, 0, 0), floorY, ceilY, color, rng, gaps.west)
	rockWall(room, Vector3.new(max.X, 0, min.Z), Vector3.new(max.X, 0, max.Z), Vector3.new(-1, 0, 0), floorY, ceilY, color, rng, gaps.east)
	stalactites(room, min, max, ceilY, math.floor(width * depth / 500), color, rng)
	-- uneven floor slabs for a rocky feel
	for _ = 1, math.floor(width * depth / 300) do
		local x = rng:range(min.X + 4, max.X - 4)
		local z = rng:range(min.Z + 4, max.Z - 4)
		if not WorldLayout.isKeepOut(Vector3.new(x, floorY, z), 4) then
			local s = Vector3.new(rng:range(5, 12), rng:range(0.3, 0.8), rng:range(5, 12))
			Geo.block(room, CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:range(0, 6.28), 0), s, Geo.vary(darkColor, rng, 0.05), nil, solid({ CastShadow = false }))
		end
	end
	return room
end

local function tunnel(parent: Instance, min: Vector3, max: Vector3, alongZ: boolean, color: Color3)
	local t = Instance.new("Model")
	t.Name = "Tunnel"
	t.Parent = parent
	if alongZ then
		boxPart(t, Vector3.new(min.X - 4, min.Y, min.Z), Vector3.new(min.X, max.Y, max.Z), color)
		boxPart(t, Vector3.new(max.X, min.Y, min.Z), Vector3.new(max.X + 4, max.Y, max.Z), color)
	else
		boxPart(t, Vector3.new(min.X, min.Y, min.Z - 4), Vector3.new(max.X, max.Y, min.Z), color)
		boxPart(t, Vector3.new(min.X, min.Y, max.Z), Vector3.new(max.X, max.Y, max.Z + 4), color)
	end
	boxPart(t, Vector3.new(min.X - 4, max.Y, min.Z - 4), Vector3.new(max.X + 4, max.Y + 4, max.Z + 4), color)
	return t
end

-- A ramp wedge going from `high` (top end) down to `low` (bottom end), along Z.
local function ramp(parent: Instance, high: Vector3, low: Vector3, width: number, color: Color3): WedgePart
	local height = high.Y - low.Y
	local length = math.abs(high.Z - low.Z)
	local center = Vector3.new(high.X, (high.Y + low.Y) / 2, (high.Z + low.Z) / 2)
	-- WedgePart: high side at +Z. If the ramp descends toward -Z this is the default.
	local cf = if low.Z < high.Z then CFrame.new(center) else CFrame.new(center) * CFrame.Angles(0, math.pi, 0)
	local w = Geo.wedge(parent, cf, Vector3.new(width, height, length), color, nil, solid())
	w.Name = "Ramp"
	return w
end

-- `avoid` = node spawn positions; lava pools and crystals keep clear of them.
function Land.build(map: Model, rng: Rng.Rng, avoid: { Vector3 })
	local land = folder("Land", map)
	local function clearOfNodes(p: Vector3, radius: number): boolean
		for _, a in avoid do
			if (Vector3.new(a.X, p.Y, a.Z) - p).Magnitude < radius then
				return false
			end
		end
		return true
	end
	local island = WorldLayout.Island

	---------------------------------------------------------------- ground
	local townMin = Vector3.new(island.Min.X - 6, -6, -122)
	local townMax = Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6)
	local ground = boxPart(land, townMin, townMax, Palette.Grass, nil, { Name = "Ground" })
	ground.Name = "Ground"
	-- strips of ground beside the quarry up to the mountains
	boxPart(land, Vector3.new(townMin.X, -6, -240), Vector3.new(-72, 0, -122), Palette.GrassDark).Name = "Ground"
	boxPart(land, Vector3.new(72, -6, -150), Vector3.new(townMax.X, 0, -122), Palette.GrassDark).Name = "Ground"

	-- soft color patches so the grass is not one flat color
	for _ = 1, 140 do
		local x = rng:range(island.Min.X, island.Max.X)
		local z = rng:range(-118, island.Max.Z)
		local s = Vector3.new(rng:range(8, 22), 0.2, rng:range(8, 22))
		local color = if rng:chance(0.5) then Palette.GrassLight else Palette.GrassDark
		Geo.block(land, CFrame.new(x, 0.02, z) * CFrame.Angles(0, rng:range(0, 6.28), 0), s, Geo.vary(color, rng, 0.03), nil, decor({ CastShadow = false, CanCollide = false }))
	end

	---------------------------------------------------------------- sea + cliffs
	-- The sea is four strips AROUND the island: one big plane would cut
	-- through the Deep Hollow, which lies below sea level.
	local seaFolder = folder("Sea", land)
	local seaY = -22
	local far = 1000
	local iMin = Vector3.new(island.Min.X - 6, 0, island.Min.Z - 30)
	local iMax = Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6)
	local seaStrips = {
		{ Vector3.new(iMin.X - far, seaY - 1, iMax.Z), Vector3.new(iMax.X + far, seaY + 1, iMax.Z + far) }, -- south
		{ Vector3.new(iMin.X - far, seaY - 1, iMin.Z - far), Vector3.new(iMax.X + far, seaY + 1, iMin.Z) }, -- north
		{ Vector3.new(iMin.X - far, seaY - 1, iMin.Z), Vector3.new(iMin.X, seaY + 1, iMax.Z) }, -- west
		{ Vector3.new(iMax.X, seaY - 1, iMin.Z), Vector3.new(iMax.X + far, seaY + 1, iMax.Z) }, -- east
	}
	for _, strip in seaStrips do
		local sea = boxPart(seaFolder, strip[1], strip[2], Palette.Sea, Enum.Material.SmoothPlastic, decor({ Reflectance = 0.12, CanCollide = false, CastShadow = false }))
		sea.Name = "Sea"
	end
	local cliffs = folder("Cliffs", land)
	local edges = {
		{ Vector3.new(island.Min.X - 6, 0, island.Max.Z + 6), Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6), Vector3.new(0, 0, -1) },
		{ Vector3.new(island.Min.X - 6, 0, -240), Vector3.new(island.Min.X - 6, 0, island.Max.Z + 6), Vector3.new(1, 0, 0) },
		{ Vector3.new(island.Max.X + 6, 0, -240), Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6), Vector3.new(-1, 0, 0) },
	}
	for _, edge in edges do
		local from, to, inward = edge[1], edge[2], edge[3]
		local dir = (to - from).Unit
		local length = (to - from).Magnitude
		local t = 0
		while t < length do
			local p = from + dir * t
			local s = Vector3.new(rng:range(12, 18), rng:range(22, 28), rng:range(10, 16))
			local center = Vector3.new(p.X, -24 + s.Y / 2 + rng:range(-1, 1.5), p.Z) - inward * (s.Z * 0.3)
			local cf = CFrame.lookAt(center, center + inward) * CFrame.Angles(rng:range(-0.08, 0.08), rng:range(-0.25, 0.25), rng:range(-0.08, 0.08))
			Geo.block(cliffs, cf, s, Geo.vary(Palette.Cliff, rng, 0.07), nil, solid())
			-- grassy cap on some cliff blocks
			if rng:chance(0.5) then
				Geo.block(cliffs, cf * CFrame.new(0, s.Y / 2, 0), Vector3.new(s.X * 0.9, 0.8, s.Z * 0.9), Geo.vary(Palette.Grass, rng, 0.04), nil, decor({ CastShadow = false }))
			end
			t += rng:range(9, 13)
		end
	end
	-- invisible walls around the island
	local bounds = folder("Bounds", land)
	local wallProps = decor({ Transparency = 1, CanCollide = true, CastShadow = false })
	boxPart(bounds, Vector3.new(island.Min.X - 10, -60, island.Max.Z + 2), Vector3.new(island.Max.X + 10, 200, island.Max.Z + 4), Palette.Cliff, nil, wallProps)
	boxPart(bounds, Vector3.new(island.Min.X - 4, -60, island.Min.Z - 20), Vector3.new(island.Min.X - 2, 200, island.Max.Z + 4), Palette.Cliff, nil, wallProps)
	boxPart(bounds, Vector3.new(island.Max.X + 2, -60, island.Min.Z - 20), Vector3.new(island.Max.X + 4, 200, island.Max.Z + 4), Palette.Cliff, nil, wallProps)
	boxPart(bounds, Vector3.new(island.Min.X - 10, -60, island.Min.Z - 22), Vector3.new(island.Max.X + 10, 200, island.Min.Z - 20), Palette.Cliff, nil, wallProps)
	for _, child in bounds:GetChildren() do
		child.Name = "Boundary"
	end

	---------------------------------------------------------------- quarry
	local quarry = WorldLayout.Quarry
	local q = Instance.new("Model")
	q.Name = "Quarry"
	q.Parent = land
	boxPart(q, Vector3.new(quarry.Min.X - 4, quarry.Min.Y - 6, quarry.Min.Z - 2), Vector3.new(quarry.Max.X + 4, quarry.Min.Y, quarry.Max.Z), Palette.QuarryFloor).Name = "Floor"
	-- dusty floor patches
	for _ = 1, 40 do
		local x = rng:range(quarry.Min.X + 4, quarry.Max.X - 4)
		local z = rng:range(quarry.Min.Z + 4, quarry.Max.Z - 4)
		local s = Vector3.new(rng:range(6, 16), 0.25, rng:range(6, 16))
		Geo.block(q, CFrame.new(x, quarry.Min.Y + 0.05, z) * CFrame.Angles(0, rng:range(0, 6.28), 0), s, Geo.vary(Palette.StoneWarm, rng, 0.05), nil, decor({ CastShadow = false, CanCollide = false }))
	end
	-- walls: south cliff (ground edge), west, east (grotto gap), north (cave gap)
	local qBottom, qTop = quarry.Min.Y - 2, 4
	rockWall(q, Vector3.new(quarry.Min.X, 0, quarry.Max.Z), Vector3.new(quarry.Max.X, 0, quarry.Max.Z), Vector3.new(0, 0, -1), qBottom, 1, Palette.Cliff, rng, { { -quarry.Min.X, 10 } })
	rockWall(q, Vector3.new(quarry.Min.X, 0, quarry.Min.Z), Vector3.new(quarry.Min.X, 0, quarry.Max.Z), Vector3.new(1, 0, 0), qBottom, qTop + 8, Palette.Cliff, rng)
	rockWall(q, Vector3.new(quarry.Max.X, 0, quarry.Min.Z), Vector3.new(quarry.Max.X, 0, quarry.Max.Z), Vector3.new(-1, 0, 0), qBottom, qTop + 8, Palette.Cliff, rng, { { -182 - quarry.Min.Z, 7 } })
	rockWall(q, Vector3.new(quarry.Min.X, 0, quarry.Min.Z), Vector3.new(quarry.Max.X, 0, quarry.Min.Z), Vector3.new(0, 0, 1), qBottom, qTop + 14, Palette.Cliff, rng, { { -quarry.Min.X, 10 } })
	ramp(q, Vector3.new(0, 0, quarry.Max.Z), Vector3.new(0, quarry.Min.Y, quarry.Max.Z - 26), quarry.RampWidth, Palette.Dirt)
	-- wooden scaffolding + mine cart rails for flavor
	for i = 0, 3 do
		local x = -50 + i * 32
		Props.crate(q, CFrame.new(x + rng:range(-3, 3), quarry.Min.Y, quarry.Max.Z - 10), rng)
	end
	Props.lantern(q, CFrame.new(-11, quarry.Min.Y, -150) * CFrame.Angles(0, math.pi / 2, 0), true)
	Props.lantern(q, CFrame.new(11, quarry.Min.Y, -150) * CFrame.Angles(0, -math.pi / 2, 0), true)
	Props.lantern(q, CFrame.new(-12, quarry.Min.Y, -228) * CFrame.Angles(0, math.pi / 2, 0), true)
	Props.lantern(q, CFrame.new(12, quarry.Min.Y, -228) * CFrame.Angles(0, -math.pi / 2, 0), true)
	Props.sign(q, CFrame.new(0, quarry.Min.Y + 14, -235) * CFrame.Angles(0, 0, 0), "EMBER CAVES", 16, 3.2, Palette.WoodDark, Palette.ForgeGlow)

	---------------------------------------------------------------- caves
	local caves = WorldLayout.Caves
	local ember = caves.EmberCaves
	local emberRoom = caveRoom(land, "EmberCaves", ember.Min, ember.Max, Palette.CaveRock, Palette.CaveRockDark, rng, {
		south = { { -ember.Min.X, 9 } },
		north = { { -ember.Min.X, 9 } },
	})
	tunnel(land, Vector3.new(-11, ember.Min.Y, ember.Max.Z), Vector3.new(11, 6, quarry.Min.Z), true, Palette.CaveRock)
	boxPart(land, Vector3.new(-12, ember.Min.Y - 6, ember.Max.Z - 1), Vector3.new(12, ember.Min.Y, quarry.Min.Z + 1), Palette.CaveRockDark)

	-- lava pools (positions saved as attributes so nodes avoid them)
	local pools = folder("LavaPools", emberRoom)
	local placed: { Vector3 } = {}
	local tries = 0
	while #placed < ember.LavaPools and tries < 200 do
		tries += 1
		local x = rng:range(ember.Min.X + 14, ember.Max.X - 14)
		local z = rng:range(ember.Min.Z + 14, ember.Max.Z - 14)
		local p = Vector3.new(x, ember.Min.Y, z)
		local ok = not WorldLayout.isKeepOut(p, 10) and clearOfNodes(p, 14)
		for _, other in placed do
			if (other - p).Magnitude < 26 then
				ok = false
			end
		end
		if ok then
			table.insert(placed, p)
			local d = rng:range(10, 15)
			Geo.cylinder(pools, p + Vector3.new(0, 0.25, 0), 0.5, d + 2.5, Palette.LavaCrust, nil, solid({ CastShadow = false }))
			local lava = Geo.cylinder(pools, p + Vector3.new(0, 0.32, 0), 0.5, d, Palette.Lava, Enum.Material.Neon, decor({ CastShadow = false, CanCollide = false }))
			lava.Name = "Lava"
			Props.pointLight(lava, Palette.ForgeGlow, 28, 2.2)
			Props.emitter(lava, "Embers", Palette.Ember, 5)
			for _ = 1, 3 do
				local a = rng:range(0, 6.28)
				Geo.rock(pools, CFrame.new(p + Vector3.new(math.cos(a), 0, math.sin(a)) * (d / 2 + 1.5)), Vector3.new(2.5, 2, 2.5), Palette.LavaCrust, rng, nil, solid())
			end
		end
	end
	emberRoom:SetAttribute("PoolCount", #placed)
	-- braziers along the walls so the cave stays readable on small screens
	for i = 1, 6 do
		local side = if i % 2 == 0 then 1 else -1
		local z = ember.Max.Z - 14 - (i - 1) * ((ember.Max.Z - ember.Min.Z - 28) / 5)
		local p = Vector3.new(side * (ember.Max.X - 7), ember.Min.Y, z)
		if clearOfNodes(p, 6) then
			Props.brazier(emberRoom, CFrame.new(p), true)
		end
	end

	local hollow = caves.DeepHollow
	local hollowRoom = caveRoom(land, "DeepHollow", hollow.Min, hollow.Max, Palette.HollowRock, Palette.HollowRockDark, rng, {
		south = { { -hollow.Min.X, 9 } },
	})
	tunnel(land, Vector3.new(-11, hollow.Min.Y, hollow.Max.Z), Vector3.new(11, 4, ember.Min.Z), true, Palette.HollowRock)
	ramp(land, Vector3.new(0, ember.Min.Y, ember.Min.Z), Vector3.new(0, hollow.Min.Y, hollow.Max.Z - 12), 16, Palette.HollowRockDark)

	-- glowing crystal clusters
	local crystalColors = {
		Color3.fromRGB(90, 255, 160),
		Color3.fromRGB(110, 230, 255),
		Color3.fromRGB(150, 120, 255),
		Color3.fromRGB(255, 244, 190),
		Color3.fromRGB(255, 90, 140),
	}
	local function crystalCluster(parent: Instance, p: Vector3, color: Color3, size: number)
		local cluster = Instance.new("Model")
		cluster.Name = "CrystalCluster"
		cluster.Parent = parent
		local biggest: BasePart? = nil
		for i = 1, rng:int(3, 5) do
			local h = size * rng:range(0.5, 1)
			local w = h * rng:range(0.22, 0.3)
			local a = rng:range(0, 6.28)
			local base = p + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:range(0, size * 0.3)
			local cf = CFrame.new(base) * CFrame.Angles(rng:range(-0.45, 0.45), rng:range(0, 6.28), rng:range(-0.45, 0.45)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.pi / 4, 0)
			local body = Geo.block(cluster, cf, Vector3.new(w, h, w), Geo.vary(color, rng, 0.04), Enum.Material.Neon, decor({ CastShadow = false }))
			Geo.wedge(cluster, cf * CFrame.new(0, h / 2 + w * 0.55, 0), Vector3.new(w, w * 1.1, w), color, Enum.Material.Neon, decor({ CastShadow = false }))
			if i == 1 then
				biggest = body
			end
		end
		if biggest then
			Props.pointLight(biggest, color, 30, 1.6)
		end
	end
	for i = 1, hollow.CrystalClusters do
		local side = rng:int(1, 4)
		local p: Vector3
		if side == 1 then
			p = Vector3.new(rng:range(hollow.Min.X + 6, hollow.Max.X - 6), hollow.Min.Y, hollow.Min.Z + 8)
		elseif side == 2 then
			p = Vector3.new(hollow.Min.X + 8, hollow.Min.Y, rng:range(hollow.Min.Z + 6, hollow.Max.Z - 6))
		elseif side == 3 then
			p = Vector3.new(hollow.Max.X - 8, hollow.Min.Y, rng:range(hollow.Min.Z + 6, hollow.Max.Z - 6))
		else
			p = Vector3.new(rng:range(hollow.Min.X + 30, hollow.Max.X - 30), hollow.Min.Y, rng:range(hollow.Min.Z + 20, hollow.Max.Z - 40))
		end
		if clearOfNodes(p, 10) then
			crystalCluster(hollowRoom, p, crystalColors[(i - 1) % #crystalColors + 1], rng:range(9, 16))
		end
	end

	local grotto = caves.Grotto
	local grottoRoom = caveRoom(land, "Grotto", grotto.Min, grotto.Max, Palette.GrottoRock, Palette.HollowRockDark, rng, {
		west = { { -182 - grotto.Min.Z, 6 } },
	})
	tunnel(land, Vector3.new(quarry.Max.X, grotto.Min.Y, -188), Vector3.new(grotto.Min.X, -1, -176), false, Palette.GrottoRock)
	boxPart(land, Vector3.new(quarry.Max.X - 2, grotto.Min.Y - 6, -190), Vector3.new(grotto.Min.X + 2, grotto.Min.Y, -174), Palette.HollowRockDark)
	for _ = 1, grotto.CrystalClusters do
		local p = Vector3.new(rng:range(grotto.Min.X + 8, grotto.Max.X - 8), grotto.Min.Y, rng:range(grotto.Min.Z + 8, grotto.Max.Z - 8))
		if math.abs(p.Z + 182) > 10 and clearOfNodes(p, 9) then
			crystalCluster(grottoRoom, p, Palette.Vip, rng:range(6, 10))
		end
	end
	local door = Geo.block(land, CFrame.new(80, grotto.Min.Y + 5.5, -182), Vector3.new(1, 11, 12), Palette.Vip, Enum.Material.Neon, { Transparency = 0.55, CanTouch = true, CanQuery = false, CastShadow = false })
	door.Name = "VipDoor"
	door:AddTag("VipDoor")
	Props.sign(land, CFrame.new(73, grotto.Min.Y + 11, -182) * CFrame.Angles(0, -math.pi / 2, 0), "GLIMMER GROTTO - VIP", 12, 2.4, Palette.HollowRockDark, Palette.Vip)

	---------------------------------------------------------------- mountains
	-- Columns on a 40-stud grid. Cells touching a cave or tunnel are split into
	-- smaller cells, so rock sits on the cave roof only where the cave is and
	-- reaches the ground everywhere else (no floating overhangs).
	local mountains = folder("Mountains", land)
	local spaces = protectedSpaces()
	local function heightAt(x: number, z: number): number
		local northness = math.clamp((-z - 128) / 360, 0, 1)
		local ridge = math.sin(x * 0.031 + 1.3) * math.cos(z * 0.022 + 0.4) * 12 + math.sin(x * 0.011 - z * 0.017) * 8
		return 20 + northness * 48 + ridge
	end
	local function placeColumn(x: number, z: number, half: number, depth: number)
		local reach = half * 1.15
		local cMin = Vector3.new(x - reach, 0, z - reach)
		local cMax = Vector3.new(x + reach, 0, z + reach)
		local bottom = -20
		for _, space in spaces do
			local margin = if space.open then 3 else 1
			local sMin = space.box.Min - Vector3.new(margin, 0, margin)
			local sMax = space.box.Max + Vector3.new(margin, 0, margin)
			if boxesOverlap2D(cMin, cMax, sMin, sMax) then
				local inside = cMin.X >= sMin.X and cMax.X <= sMax.X and cMin.Z >= sMin.Z and cMax.Z <= sMax.Z
				if (space.open or not inside) and depth < 2 then
					local q = half / 2
					placeColumn(x - q, z - q, q, depth + 1)
					placeColumn(x + q, z - q, q, depth + 1)
					placeColumn(x - q, z + q, q, depth + 1)
					placeColumn(x + q, z + q, q, depth + 1)
					return
				elseif space.open then
					return
				end
				bottom = math.max(bottom, space.roofTop :: number)
			end
		end
		local top = math.max(heightAt(x, z) + rng:range(-4, 4), bottom + 10)
		local size = Vector3.new(half * 2 * rng:range(0.95, 1.08), top - bottom, half * 2 * rng:range(0.95, 1.08))
		local center = Vector3.new(x, bottom + size.Y / 2, z)
		local band = math.clamp((top - 20) / 60, 0, 1)
		local colorBase = Palette.Cliff:Lerp(Palette.CliffDark, band)
		Geo.block(mountains, CFrame.new(center) * CFrame.Angles(0, rng:range(-0.12, 0.12), 0), size, Geo.vary(colorBase, rng, 0.05), nil, solid())
		if depth <= 1 then
			-- a tilted cap block gives a jagged low-poly silhouette
			local peak = Vector3.new(size.X * rng:range(0.5, 0.75), rng:range(6, 14), size.Z * rng:range(0.5, 0.75))
			local capColor = if top < 34 then Palette.GrassDark else Palette.StoneWarm:Lerp(Palette.CliffDark, band)
			Geo.block(
				mountains,
				CFrame.new(center + Vector3.new(rng:range(-4, 4), size.Y / 2 + peak.Y * 0.25, rng:range(-4, 4))) * Geo.randomTilt(rng, 0.22),
				peak,
				Geo.vary(capColor, rng, 0.05),
				nil,
				solid()
			)
			if top < 34 and rng:chance(0.5) then
				Props.pine(mountains, CFrame.new(center + Vector3.new(rng:range(-half * 0.6, half * 0.6), size.Y / 2, rng:range(-half * 0.6, half * 0.6))), rng)
			end
		end
	end
	local cell = 40
	local gx = island.Min.X - 8
	while gx <= island.Max.X + 8 do
		local gz = -142
		while gz >= island.Min.Z - 8 do
			placeColumn(gx, gz, cell / 2, 0)
			gz -= cell
		end
		gx += cell
	end

	return land
end

return Land
