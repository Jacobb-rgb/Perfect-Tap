--[[
	Ground, cliffs, sea, the quarry pit, enclosed caves, tunnels and the
	mountain range. Built from blocks only (no Terrain) for the low-poly look,
	and so the whole map can be generated outside Studio too.

	Lobby look (docs/ART_DIRECTION.md, LOBBY_PLAN 6.2): grass ground, a dark
	voxel stone rim around the island, axis-aligned stone mountain columns
	with grass or light stone caps. The ForgeMountain massif, the DEPTHS
	portal and the rest of the backdrop are built by Lobby/Backdrop; the
	mountain grid leaves the massif's box empty for it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Palette = require(script.Parent.Palette)
local PlotBuilder = require(script.Parent.PlotBuilder)
local Props = require(script.Parent.Props)
local Style = require(script.Parent.Lobby.Style)
local Spectrum = require(script.Parent.Lobby.Backdrop.Spectrum)

local C = Style.C

local Land = {}

-- Mountain columns under the Backdrop scaffold towers are cut to this height
-- (their grass cap sits on top), so the towers stand on a known shelf.
Land.ShelfHeight = 18
Land.ShelfPieces = { "ScaffoldWest", "ScaffoldWest2" }

-- Inner face of the east/west rim cliffs: the base yards end at |x| = 170.
local RIM_INNER_X = 172
-- Inner face of the south rim cliffs (the invisible wall is at z 152..154).
local RIM_INNER_Z = 153

type Box = { Min: Vector3, Max: Vector3 }

--[[
	Design v2 base yards: every plot grew a yard on its sea side (plot-local
	z 25..66, src/shared/Config/BaseLayout.luau) with the ore pen, podiums,
	foundry and the train stop of the coastal railway (world |x| ~166). The
	whole strip stays flat at y = 0: Land puts no decoration there (color
	patches excepted). True if a ground point (with `radius`) is on a base.
]]
local function onBaseYard(p: Vector3, radius: number): boolean
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, radius) then
			return true
		end
	end
	return false
end

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
local function boxPart(
	parent: Instance,
	min: Vector3,
	max: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): Part
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
		{
			box = { Min = Vector3.new(quarry.Min.X, quarry.Min.Y, quarry.Min.Z), Max = Vector3.new(quarry.Max.X, 200, quarry.Max.Z) },
			open = true,
		},
		{ box = { Min = caves.EmberCaves.Min, Max = caves.EmberCaves.Max }, roofTop = caves.EmberCaves.Max.Y + 4 },
		{ box = { Min = caves.DeepHollow.Min, Max = caves.DeepHollow.Max }, roofTop = caves.DeepHollow.Max.Y + 4 },
		{ box = { Min = caves.Grotto.Min, Max = caves.Grotto.Max }, roofTop = caves.Grotto.Max.Y + 3 },
		-- tunnels
		{ box = { Min = Vector3.new(-13, -12, -246), Max = Vector3.new(13, 8, -234) }, roofTop = 8 },
		{ box = { Min = Vector3.new(-13, -40, -382), Max = Vector3.new(13, 4, -350) }, roofTop = 4 },
		{ box = { Min = Vector3.new(70, -12, -192), Max = Vector3.new(90, 2, -172) }, roofTop = 2 },
	}
end

-- Optional look of a rock wall: axis-aligned voxel blocks in random shades
-- and grass caps (the quarry walls; cave walls keep the jagged look).
type WallLook = { aligned: boolean?, colors: { Color3 }?, grass: boolean? }

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
	gaps: { { number } }?,
	look: WallLook?
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
			local jitter = CFrame.Angles(rng:range(-0.05, 0.05), rng:range(-0.18, 0.18), rng:range(-0.05, 0.05))
			local aligned = look ~= nil and look.aligned == true
			local cf = CFrame.lookAt(center, center + inward) * (if aligned then CFrame.new() else jitter)
			local blockColor = if look and look.colors then rng:pick(look.colors) else color
			Geo.block(parent, cf, Vector3.new(width, height, depth), Geo.vary(blockColor, rng, 0.06), nil, solid())
			if look and look.grass then
				-- dirt band and grass cap on top (the wall reads as a voxel cliff)
				Geo.block(
					parent,
					cf * CFrame.new(0, height / 2 - 0.6, 0),
					Vector3.new(width + 0.3, 1.2, depth + 0.3),
					Geo.vary(C.DirtDark, rng, 0.04),
					nil,
					decor({ CastShadow = false })
				)
				Geo.block(
					parent,
					cf * CFrame.new(0, height / 2 + 0.35, 0),
					Vector3.new(width + 0.5, 0.9, depth + 0.5),
					Geo.vary(C.Grass, rng, 0.05),
					nil,
					solid()
				)
			end
			-- a smaller boulder at the foot of the wall for a natural edge
			if rng:chance(0.45) then
				local s = Vector3.new(rng:range(3, 6), rng:range(2.5, 5), rng:range(3, 5))
				local foot = Vector3.new(p.X, bottom, p.Z) + inward * rng:range(1, 3) + dir * rng:range(-3, 3)
				if aligned then
					Geo.block(parent, CFrame.new(foot + Vector3.new(0, s.Y / 2 - 0.3, 0)), s, Geo.vary(blockColor, rng, 0.06), nil, solid())
				else
					Geo.rock(parent, CFrame.new(foot), s, color, rng, nil, solid())
				end
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
	boxPart(
		room,
		Vector3.new(min.X - 10, ceilY, min.Z - 10),
		Vector3.new(max.X + 10, ceilY + 4, max.Z + 10),
		darkColor,
		nil,
		{ CastShadow = true }
	)
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
			Geo.block(
				room,
				CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:range(0, 6.28), 0),
				s,
				Geo.vary(darkColor, rng, 0.05),
				nil,
				solid({ CastShadow = false })
			)
		end
	end
	return room
end

local function tunnel(parent: Instance, min: Vector3, max: Vector3, alongZ: boolean, color: Color3)
	local t = Instance.new("Model")
	t.Name = "Tunnel"
	t.Parent = parent
	-- thick side walls so the gaps in the rock walls next to the mouth are closed
	local wall = 8
	if alongZ then
		boxPart(t, Vector3.new(min.X - wall, min.Y, min.Z), Vector3.new(min.X, max.Y, max.Z), color)
		boxPart(t, Vector3.new(max.X, min.Y, min.Z), Vector3.new(max.X + wall, max.Y, max.Z), color)
	else
		boxPart(t, Vector3.new(min.X, min.Y, min.Z - wall), Vector3.new(max.X, max.Y, min.Z), color)
		boxPart(t, Vector3.new(min.X, min.Y, max.Z), Vector3.new(max.X, max.Y, max.Z + wall), color)
	end
	boxPart(t, Vector3.new(min.X - wall, max.Y, min.Z - wall), Vector3.new(max.X + wall, max.Y + 4, max.Z + wall), color)
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

--[[
	Island rim: axis-aligned dark voxel stone columns along the south, west
	and east coasts, from below the sea up to about ground level (grass cap,
	a dirt band on the sea side), with lower stepping blocks toward the
	water. Inner faces stay at |x| >= RIM_INNER_X (the base yards end at
	|x| = 170) and tops stay below y 2.5 (the NEXT AREA boardwalk crosses the
	east rim at deck height ~5).
]]
type RimEdge = { along: string, inner: number, out: number, from: number, to: number }

-- The south rim stays low over this x range: the stream's waterfall
-- (Lobby/Flora/Stream, Stream.Notch) pours over it into the sea.
Land.RimNotch = { X0 = 96, X1 = 106 }

local function buildRim(parent: Instance, rng: Rng.Rng)
	local island = WorldLayout.Island
	local shades = { C.StoneDark, C.StoneDark, C.Stone, C.StoneDeep }
	local edges: { RimEdge } = {
		{ along = "x", inner = RIM_INNER_Z, out = 1, from = island.Min.X - 14, to = island.Max.X + 14 }, -- south
		{ along = "z", inner = -RIM_INNER_X, out = -1, from = -240, to = RIM_INNER_Z }, -- west
		{ along = "z", inner = RIM_INNER_X, out = 1, from = -240, to = RIM_INNER_Z }, -- east
	}
	local tiny = { CanCollide = false, CanQuery = false, CastShadow = false }
	-- s = along the edge, c = across (outward from the inner face), y = height
	local function block(
		edge: RimEdge,
		s0: number,
		s1: number,
		c0: number,
		c1: number,
		y0: number,
		y1: number,
		color: Color3,
		extra: { [string]: any }?
	): Part?
		local lo, hi = math.min(c0, c1), math.max(c0, c1)
		local min = if edge.along == "x" then Vector3.new(s0, y0, lo) else Vector3.new(lo, y0, s0)
		local max = if edge.along == "x" then Vector3.new(s1, y1, hi) else Vector3.new(hi, y1, s1)
		local center = (min + max) / 2
		if onBaseYard(Vector3.new(center.X, 0, center.Z), 0) and y1 > 0.3 then
			return nil -- never above the ground on a base yard
		end
		return boxPart(parent, min, max, color, nil, extra)
	end
	for _, edge in edges do
		local t = edge.from
		while t < edge.to - 1 do
			local w = math.min(math.floor(rng:range(10, 16)), edge.to - t)
			local depth = math.floor(rng:range(8, 13))
			local top = math.floor(rng:range(-0.8, 1.6) * 2) / 2
			if edge.along == "x" and t < Land.RimNotch.X1 and t + w > Land.RimNotch.X0 then
				-- low under the stream's mouth (Lobby/Flora/Stream pours over it)
				top = math.min(top, -1)
			end
			local i0 = edge.inner
			local function across(d: number): number
				return i0 + edge.out * d
			end
			block(edge, t, t + w, across(0), across(depth), -26, top, Geo.vary(rng:pick(shades), rng, 0.06))
			block(edge, t - 0.15, t + w + 0.15, across(-0.3), across(depth + 0.3), top - 0.1, top + 0.8, Geo.vary(C.Grass, rng, 0.05))
			if rng:chance(0.6) then
				-- dirt band under the grass on the sea side
				block(
					edge,
					t - 0.1,
					t + w + 0.1,
					across(0.6),
					across(depth + 0.15),
					top - 1.7,
					top - 0.1,
					Geo.vary(C.DirtDark, rng, 0.04),
					tiny
				)
			end
			if rng:chance(0.45) then
				-- a lower step toward the sea
				local s0 = t + w * rng:range(0.05, 0.25)
				local s1 = t + w * rng:range(0.75, 0.95)
				local stepTop = math.floor(rng:range(-14, -6))
				block(
					edge,
					s0,
					s1,
					across(depth - 2),
					across(depth + math.floor(rng:range(3, 7))),
					-26,
					stepTop,
					Geo.vary(if rng:chance(0.5) then C.StoneDeep else C.StoneDark, rng, 0.06)
				)
			end
			t += w
		end
	end
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
	local townMin = Vector3.new(island.Min.X - 6, -18, -122)
	local townMax = Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6)
	local ground = boxPart(land, townMin, townMax, C.Grass, nil, { Name = "Ground" })
	ground.Name = "Ground"
	-- strips of ground beside the quarry up to the mountains
	boxPart(land, Vector3.new(townMin.X, -18, -240), Vector3.new(-72, 0, -122), C.Grass).Name = "Ground"
	boxPart(land, Vector3.new(72, -18, -150), Vector3.new(townMax.X, 0, -122), C.Grass).Name = "Ground"

	-- soft color patches so the grass is not one flat color (axis-aligned:
	-- they share the voxel grid; none in the base yards, whose pads have
	-- their own look; every random value is still drawn so the rest stays put)
	for _ = 1, 140 do
		local x = rng:range(island.Min.X, island.Max.X)
		local z = rng:range(-118, island.Max.Z)
		local s = Vector3.new(math.floor(rng:range(8, 22)), 0.2, math.floor(rng:range(8, 22)))
		local color = if rng:chance(0.5) then C.GrassLight else C.GrassDark
		local tint = Geo.vary(color, rng, 0.03)
		if not PlotBuilder.isInYard(Vector3.new(x, 0, z), math.max(s.X, s.Z) * 0.7) then
			Geo.block(land, CFrame.new(math.floor(x), 0.02, math.floor(z)), s, tint, nil, decor({ CastShadow = false, CanCollide = false }))
		end
	end

	---------------------------------------------------------------- sea + cliffs
	-- The sea is four strips AROUND the island: one big plane would cut
	-- through the Deep Hollow, which lies below sea level.
	local seaFolder = folder("Sea", land)
	local seaY = -22
	local far = 850 -- keeps every sea strip under Roblox's 2048-stud part size limit
	local iMin = Vector3.new(island.Min.X - 6, 0, island.Min.Z - 30)
	local iMax = Vector3.new(island.Max.X + 6, 0, island.Max.Z + 6)
	local seaStrips = {
		{ Vector3.new(iMin.X - far, seaY - 1, iMax.Z), Vector3.new(iMax.X + far, seaY + 1, iMax.Z + far) }, -- south
		{ Vector3.new(iMin.X - far, seaY - 1, iMin.Z - far), Vector3.new(iMax.X + far, seaY + 1, iMin.Z) }, -- north
		{ Vector3.new(iMin.X - far, seaY - 1, iMin.Z), Vector3.new(iMin.X, seaY + 1, iMax.Z) }, -- west
		{ Vector3.new(iMax.X, seaY - 1, iMin.Z), Vector3.new(iMax.X + far, seaY + 1, iMax.Z) }, -- east
	}
	for _, strip in seaStrips do
		local sea = boxPart(
			seaFolder,
			strip[1],
			strip[2],
			C.Sea,
			Enum.Material.SmoothPlastic,
			decor({ Reflectance = 0.2, CanCollide = false, CastShadow = false })
		)
		sea.Name = "Sea"
	end
	buildRim(folder("Cliffs", land), Rng.new(WorldLayout.Seed * 5 + 3))
	-- invisible walls around the island
	local bounds = folder("Bounds", land)
	local wallProps = decor({ Transparency = 1, CanCollide = true, CastShadow = false })
	boxPart(
		bounds,
		Vector3.new(island.Min.X - 10, -60, island.Max.Z + 2),
		Vector3.new(island.Max.X + 10, 200, island.Max.Z + 4),
		Palette.Cliff,
		nil,
		wallProps
	)
	boxPart(
		bounds,
		Vector3.new(island.Min.X - 4, -60, island.Min.Z - 20),
		Vector3.new(island.Min.X - 2, 200, island.Max.Z + 4),
		Palette.Cliff,
		nil,
		wallProps
	)
	boxPart(
		bounds,
		Vector3.new(island.Max.X + 2, -60, island.Min.Z - 20),
		Vector3.new(island.Max.X + 4, 200, island.Max.Z + 4),
		Palette.Cliff,
		nil,
		wallProps
	)
	boxPart(
		bounds,
		Vector3.new(island.Min.X - 10, -60, island.Min.Z - 22),
		Vector3.new(island.Max.X + 10, 200, island.Min.Z - 20),
		Palette.Cliff,
		nil,
		wallProps
	)
	for _, child in bounds:GetChildren() do
		child.Name = "Boundary"
	end

	---------------------------------------------------------------- quarry
	local quarry = WorldLayout.Quarry
	local q = Instance.new("Model")
	q.Name = "Quarry"
	q.Parent = land
	boxPart(
		q,
		Vector3.new(quarry.Min.X - 4, quarry.Min.Y - 6, quarry.Min.Z - 2),
		Vector3.new(quarry.Max.X + 4, quarry.Min.Y, quarry.Max.Z),
		Palette.QuarryFloor
	).Name =
		"Floor"
	-- dusty floor patches
	for _ = 1, 40 do
		local x = rng:range(quarry.Min.X + 4, quarry.Max.X - 4)
		local z = rng:range(quarry.Min.Z + 4, quarry.Max.Z - 4)
		local s = Vector3.new(rng:range(6, 16), 0.25, rng:range(6, 16))
		Geo.block(
			q,
			CFrame.new(x, quarry.Min.Y + 0.05, z) * CFrame.Angles(0, rng:range(0, 6.28), 0),
			s,
			Geo.vary(Palette.StoneWarm, rng, 0.05),
			nil,
			decor({ CastShadow = false, CanCollide = false })
		)
	end
	-- walls: south cliff (ground edge), west, east (grotto gap), north (cave gap);
	-- axis-aligned voxel stone, grass on the walls players see from the town
	local qBottom, qTop = quarry.Min.Y - 2, 4
	local wallShades = { C.Stone, C.StoneDark, C.StoneDark }
	local grassy: WallLook = { aligned = true, colors = wallShades, grass = true }
	rockWall(
		q,
		Vector3.new(quarry.Min.X, 0, quarry.Max.Z),
		Vector3.new(quarry.Max.X, 0, quarry.Max.Z),
		Vector3.new(0, 0, -1),
		qBottom,
		1,
		C.StoneDark,
		rng,
		{ { -quarry.Min.X, 10 } },
		grassy
	)
	rockWall(
		q,
		Vector3.new(quarry.Min.X, 0, quarry.Min.Z),
		Vector3.new(quarry.Min.X, 0, quarry.Max.Z),
		Vector3.new(1, 0, 0),
		qBottom,
		qTop + 8,
		C.StoneDark,
		rng,
		nil,
		grassy
	)
	rockWall(
		q,
		Vector3.new(quarry.Max.X, 0, quarry.Min.Z),
		Vector3.new(quarry.Max.X, 0, quarry.Max.Z),
		Vector3.new(-1, 0, 0),
		qBottom,
		qTop + 8,
		C.StoneDark,
		rng,
		{ { -182 - quarry.Min.Z, 7 } },
		grassy
	)
	-- the north wall stands under the ForgeMountain massif (no grass)
	rockWall(
		q,
		Vector3.new(quarry.Min.X, 0, quarry.Min.Z),
		Vector3.new(quarry.Max.X, 0, quarry.Min.Z),
		Vector3.new(0, 0, 1),
		qBottom,
		qTop + 14,
		C.StoneDark,
		rng,
		{ { -quarry.Min.X, 10 } },
		{ aligned = true, colors = { C.StoneDark, C.StoneDeep } }
	)
	ramp(q, Vector3.new(0, 0, quarry.Max.Z), Vector3.new(0, quarry.Min.Y, quarry.Max.Z - 26), quarry.RampWidth, Palette.Dirt)
	-- wooden scaffolding + mine cart rails for flavor
	for i = 0, 3 do
		local x = -50 + i * 32
		Props.crate(q, CFrame.new(x + rng:range(-3, 3), quarry.Min.Y, quarry.Max.Z - 10), rng)
	end
	Props.lantern(q, CFrame.new(-11, quarry.Min.Y, -150) * CFrame.Angles(0, math.pi / 2, 0), true)
	Props.lantern(q, CFrame.new(11, quarry.Min.Y, -150) * CFrame.Angles(0, -math.pi / 2, 0), true)
	-- (the DEPTHS portal of Lobby/Backdrop frames the cave entrance: no sign or lanterns here)

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
			local lava = Geo.cylinder(
				pools,
				p + Vector3.new(0, 0.32, 0),
				0.5,
				d,
				Palette.Lava,
				Enum.Material.Neon,
				decor({ CastShadow = false, CanCollide = false })
			)
			lava.Name = "Lava"
			Props.pointLight(lava, Palette.ForgeGlow, 28, 2.2)
			Props.emitter(lava, "Embers", Palette.Ember, 5)
			for _ = 1, 3 do
				local a = rng:range(0, 6.28)
				Geo.rock(
					pools,
					CFrame.new(p + Vector3.new(math.cos(a), 0, math.sin(a)) * (d / 2 + 1.5)),
					Vector3.new(2.5, 2, 2.5),
					Palette.LavaCrust,
					rng,
					nil,
					solid()
				)
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
	-- starts where the Ember Caves floor slab ends (it overhangs the room by 8) and fills the tunnel
	ramp(land, Vector3.new(0, ember.Min.Y, ember.Min.Z - 8), Vector3.new(0, hollow.Min.Y, hollow.Max.Z - 14), 22, Palette.HollowRockDark)

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
			local cf = CFrame.new(base)
				* CFrame.Angles(rng:range(-0.45, 0.45), rng:range(0, 6.28), rng:range(-0.45, 0.45))
				* CFrame.new(0, h / 2, 0)
				* CFrame.Angles(0, math.pi / 4, 0)
			local body =
				Geo.block(cluster, cf, Vector3.new(w, h, w), Geo.vary(color, rng, 0.04), Enum.Material.Neon, decor({ CastShadow = false }))
			Geo.wedge(
				cluster,
				cf * CFrame.new(0, h / 2 + w * 0.55, 0),
				Vector3.new(w, w * 1.1, w),
				color,
				Enum.Material.Neon,
				decor({ CastShadow = false })
			)
			if i == 1 then
				biggest = body
			end
		end
		if biggest then
			Props.pointLight(biggest, color, 30, 1.6)
		end
	end
	for i = 1, hollow.CrystalClusters do
		for _ = 1, 25 do
			local side = rng:int(1, 4)
			local p: Vector3
			if side == 1 then
				p = Vector3.new(rng:range(hollow.Min.X + 6, hollow.Max.X - 6), hollow.Min.Y, hollow.Min.Z + 8)
			elseif side == 2 then
				p = Vector3.new(hollow.Min.X + 8, hollow.Min.Y, rng:range(hollow.Min.Z + 6, hollow.Max.Z - 6))
			elseif side == 3 then
				p = Vector3.new(hollow.Max.X - 8, hollow.Min.Y, rng:range(hollow.Min.Z + 6, hollow.Max.Z - 6))
			else
				p = Vector3.new(
					rng:range(hollow.Min.X + 30, hollow.Max.X - 30),
					hollow.Min.Y,
					rng:range(hollow.Min.Z + 20, hollow.Max.Z - 40)
				)
			end
			if clearOfNodes(p, 9) and not WorldLayout.isKeepOut(p, 6) then
				crystalCluster(hollowRoom, p, crystalColors[(i - 1) % #crystalColors + 1], rng:range(9, 16))
				break
			end
		end
	end

	local grotto = caves.Grotto
	local grottoRoom = caveRoom(land, "Grotto", grotto.Min, grotto.Max, Palette.GrottoRock, Palette.HollowRockDark, rng, {
		west = { { -182 - grotto.Min.Z, 6 } },
	})
	tunnel(land, Vector3.new(quarry.Max.X, grotto.Min.Y, -188), Vector3.new(grotto.Min.X, -1, -176), false, Palette.GrottoRock)
	boxPart(
		land,
		Vector3.new(quarry.Max.X - 2, grotto.Min.Y - 6, -200),
		Vector3.new(grotto.Min.X + 2, grotto.Min.Y, -164),
		Palette.HollowRockDark
	)
	-- solid rock above the tunnel up to the grotto ceiling (nothing to sneak through)
	boxPart(land, Vector3.new(quarry.Max.X - 2, 3, -200), Vector3.new(grotto.Min.X + 2, grotto.Max.Y + 3, -164), Palette.GrottoRock)
	for _ = 1, grotto.CrystalClusters do
		for _ = 1, 25 do
			-- along the walls, where no ore grows
			local alongX = rng:chance(0.5)
			local p = if alongX
				then Vector3.new(
					rng:range(grotto.Min.X + 6, grotto.Max.X - 6),
					grotto.Min.Y,
					if rng:chance(0.5) then grotto.Min.Z + 5 else grotto.Max.Z - 5
				)
				else Vector3.new(grotto.Max.X - 5, grotto.Min.Y, rng:range(grotto.Min.Z + 6, grotto.Max.Z - 6))
			if math.abs(p.Z + 182) > 10 and clearOfNodes(p, 7) then
				crystalCluster(grottoRoom, p, Palette.Vip, rng:range(6, 9))
				break
			end
		end
	end
	local door = Geo.block(
		land,
		CFrame.new(80, grotto.Min.Y + 5.5, -182),
		Vector3.new(1, 11, 12),
		Palette.Vip,
		Enum.Material.Neon,
		{ Transparency = 0.55, CanTouch = true, CanQuery = false, CastShadow = false }
	)
	door.Name = "VipDoor"
	door:AddTag("VipDoor")
	Props.sign(
		land,
		CFrame.new(73, grotto.Min.Y + 9, -182) * CFrame.Angles(0, math.pi / 2, 0),
		"GLIMMER GROTTO - VIP",
		12,
		2.4,
		Palette.HollowRockDark,
		Palette.Vip
	)

	---------------------------------------------------------------- mountains
	-- Columns on a 40-stud grid. Cells touching a cave or tunnel are split into
	-- smaller cells, so rock sits on the cave roof only where the cave is and
	-- reaches the ground everywhere else (no floating overhangs).
	-- Lobby look: axis-aligned voxel stone (Stone low, StoneDark / StoneDeep
	-- high), grass caps under 40 studs (sparse green voxel trees), stepped
	-- light stone caps above. The ForgeMountain box is left to Lobby/Backdrop.
	local mountains = folder("Mountains", land)
	local mrng = Rng.new(WorldLayout.Seed * 7 + 5)
	-- trees get their own stream and a cap, so column tweaks never reshuffle them
	local trng = Rng.new(WorldLayout.Seed * 7 + 6)
	local treesLeft = 14
	local spaces = protectedSpaces()
	local massif = LobbyLayout.get("ForgeMountain")
	local massifMin = massif.Center - massif.Size / 2
	local massifMax = massif.Center + massif.Size / 2
	local shelves: { Box } = {}
	for _, id in Land.ShelfPieces do
		local piece = LobbyLayout.get(id)
		local half = Vector3.new(piece.Size.X / 2 + 2, 0, piece.Size.Z / 2 + 2)
		table.insert(shelves, { Min = piece.Center - half, Max = piece.Center + half })
	end
	-- lower than the old range so the ForgeMountain massif towers over it
	local function heightAt(x: number, z: number): number
		local northness = math.clamp((-z - 128) / 360, 0, 1)
		local ridge = math.sin(x * 0.031 + 1.3) * math.cos(z * 0.022 + 0.4) * 12 + math.sin(x * 0.011 - z * 0.017) * 8
		return 20 + northness * 22 + ridge * 0.8
	end
	-- the flanks right beside the massif rise as dark cliffs that step down
	-- toward the coasts, so the backdrop reads as one mountain range
	local function flankAt(x: number, z: number): number?
		if z > massifMax.Z or z < massifMin.Z - 6 then
			return nil
		end
		local dx = if x < massifMin.X then massifMin.X - x elseif x > massifMax.X then x - massifMax.X else 0
		if dx <= 0 then
			return nil
		end
		return 62 - dx * 0.36
	end
	-- mid blue-grey low, darker high (never the deepest shade: the concept's
	-- mountains read light against the evening sky)
	-- (Spectrum themes colour the range by height on their own stream, so the
	-- column shapes never change with the theme)
	local crng = Rng.new(WorldLayout.Seed * 7 + 7)
	local function stoneShade(x: number, top: number): Color3
		if Spectrum.colored() then
			return Spectrum.color(x, top, crng)
		end
		local band = math.clamp((top - 8) / 44, 0, 1)
		return C.Stone:Lerp(C.StoneDark, band * 0.85)
	end
	-- the stepped cap on high columns: light stone, or a pale tint of the theme
	local function capShade(x: number, top: number, mix: number): Color3
		if Spectrum.colored() then
			return Spectrum.tint(Spectrum.color(x, top, crng))
		end
		return C.StoneLight:Lerp(C.StoneDark, mix)
	end
	-- the concept's slopes mix green with yellow, orange, pink and red crowns
	local treeKinds = { "Green", "Yellow", "Green", "Orange", "Pink", "Green", "Red" }
	local function placeColumn(x: number, z: number, half: number, depth: number)
		if x >= massifMin.X and x <= massifMax.X and z >= massifMin.Z and z <= massifMax.Z then
			return -- the Backdrop massif stands here
		end
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
		-- cells under a scaffold are split once; the parts under it become the shelf
		local shelf = false
		for _, s in shelves do
			if boxesOverlap2D(cMin, cMax, s.Min, s.Max) then
				if depth == 0 then
					local q = half / 2
					placeColumn(x - q, z - q, q, depth + 1)
					placeColumn(x + q, z - q, q, depth + 1)
					placeColumn(x - q, z + q, q, depth + 1)
					placeColumn(x + q, z + q, q, depth + 1)
					return
				end
				shelf = true
			end
		end
		local function nearShelf(p: Vector3, r: number): boolean
			for _, s in shelves do
				if p.X > s.Min.X - r and p.X < s.Max.X + r and p.Z > s.Min.Z - r and p.Z < s.Max.Z + r then
					return true
				end
			end
			return false
		end
		local top = if shelf
			then Land.ShelfHeight
			else math.floor(math.max((flankAt(x, z) or heightAt(x, z)) + mrng:range(-4, 4), bottom + 10))
		local size = Vector3.new(half * 2 * mrng:range(0.97, 1.06), top - bottom, half * 2 * mrng:range(0.97, 1.06))
		local center = Vector3.new(x, bottom + size.Y / 2, z)
		local shade = Geo.vary(stoneShade(x, top), mrng, 0.05)
		if Spectrum.colored() then
			Spectrum.stack(mountains, center - size / 2, center + size / 2, crng, solid())
		else
			Geo.block(mountains, CFrame.new(center), size, shade, nil, solid())
		end
		if depth == 0 and ((flankAt(x, z) and z > massifMax.Z - 40) or z > -165) then
			-- protruding stones on the town-facing walls of the flanks
			for _ = 1, 2 do
				local s = math.floor(mrng:range(3, 6))
				local stone = center
					+ Vector3.new(mrng:range(-half * 0.6, half * 0.6), mrng:range(-size.Y * 0.2, size.Y * 0.35), size.Z / 2 + 0.4)
				local accent = if Spectrum.colored() then stoneShade(x, top):Lerp(Color3.new(1, 1, 1), 0.2) else C.Stone
				Geo.block(
					mountains,
					CFrame.new(stone),
					Vector3.new(s * 1.4, s, 1.2),
					Geo.vary(accent, mrng, 0.06),
					nil,
					decor({ CastShadow = false })
				)
			end
		end
		if top < 40 then
			-- dirt band (big columns only) and grass cap (the shelves keep exactly ShelfHeight + 0.8)
			if depth <= 1 then
				Geo.block(
					mountains,
					CFrame.new(center + Vector3.new(0, size.Y / 2 - 0.7, 0)),
					Vector3.new(size.X + 0.4, 1.4, size.Z + 0.4),
					Geo.vary(C.DirtDark, mrng, 0.04),
					nil,
					decor({ CastShadow = false })
				)
			end
			Geo.block(
				mountains,
				CFrame.new(center + Vector3.new(0, size.Y / 2 + 0.3, 0)),
				Vector3.new(size.X + 0.6, 1, size.Z + 0.6),
				Geo.vary(if mrng:chance(0.3) then C.GrassDark else C.Grass, mrng, 0.05),
				nil,
				solid()
			)
			if depth <= 1 and treesLeft > 0 and trng:chance(if shelf then 0.4 else 0.12) then
				local p = center + Vector3.new(trng:range(-half * 0.5, half * 0.5), size.Y / 2 + 0.8, trng:range(-half * 0.5, half * 0.5))
				if not onBaseYard(p, 6) and not nearShelf(p, 6) then
					Style.tree(mountains, CFrame.new(p), treeKinds[treesLeft % #treeKinds + 1], trng, trng:range(0.9, 1.25))
					treesLeft -= 1
				end
			end
		elseif depth <= 1 then
			-- a stepped light stone cap gives a voxel silhouette
			local cap = Vector3.new(
				math.floor(size.X * mrng:range(0.5, 0.72)),
				math.floor(mrng:range(4, 9)),
				math.floor(size.Z * mrng:range(0.5, 0.72))
			)
			local offset = Vector3.new(math.floor(mrng:range(-4, 4)), size.Y / 2 + cap.Y / 2, math.floor(mrng:range(-4, 4)))
			Geo.block(
				mountains,
				CFrame.new(center + offset),
				cap,
				Geo.vary(capShade(x, top + cap.Y, mrng:range(0.4, 0.7)), mrng, 0.04),
				nil,
				solid()
			)
		end
	end
	local cell = 40
	local gx = island.Min.X - 8
	while gx - cell / 2 <= island.Max.X + 8 do
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
