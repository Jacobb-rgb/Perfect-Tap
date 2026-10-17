--[[
	Horizon isles: a ring of far islands on the sea around the whole map, so
	no side of the town looks out on empty water (owner 2026-10-17). Shapes
	after the Kenney Pirate Kit: sand islands with palms and orange rock
	stacks, grey rock islands with a lighthouse, a fortress with a round
	blue-roofed tower, a wreck on a sand bar; plus Candy pillar sea stacks in
	the Spectrum colours of the mountains.

	Every isle sits 400+ studs out (past every Sky piece and the sun path),
	is unreachable decoration (Kit.far: no collision, no raycasts, no
	shadows) and carries no lights; each lighthouse beam turns (tag Spin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Spectrum = require(script.Parent.Parent.Spectrum)
local Place = require(script.Parent.Place)

local C = Style.C
local K = Place.K
local SEA = Place.Sea
local NEON = Enum.Material.Neon

local Isles = {}

type Spot = { Az: number, Dist: number, Kind: string, Size: number }

--[[
	The ring (bearing, studs from the plaza, kind, size). Keep-outs: the sun
	path and its glitter (bearings 250-285 out to ~900), CastleIsland
	(bearing ~311, 573), NextIsland (~114, 280), the ships (Pirates.Spots).
]]
Isles.Spots = {
	-- south: the side that looked out on empty sea
	{ Az = 150, Dist = 620, Kind = "Stack", Size = 70 },
	{ Az = 172, Dist = 760, Kind = "Lighthouse", Size = 1.2 },
	{ Az = 192, Dist = 600, Kind = "Sand", Size = 1.1 },
	{ Az = 212, Dist = 720, Kind = "Stack", Size = 92 },
	{ Az = 232, Dist = 560, Kind = "Wreck", Size = 1 },
	-- east
	{ Az = 58, Dist = 640, Kind = "Stack", Size = 82 },
	{ Az = 80, Dist = 740, Kind = "Fort", Size = 1.1 },
	{ Az = 100, Dist = 560, Kind = "Sand", Size = 0.9 },
	{ Az = 118, Dist = 820, Kind = "Stack", Size = 104 },
	{ Az = 136, Dist = 660, Kind = "Sand", Size = 0.8 },
	-- north, behind the massif (seen from the heights)
	{ Az = 10, Dist = 1000, Kind = "Stack", Size = 112 },
	{ Az = 340, Dist = 1040, Kind = "Lighthouse", Size = 1.3 },
	{ Az = 24, Dist = 900, Kind = "Stack", Size = 72 },
	-- west, beside the sunset
	{ Az = 245, Dist = 760, Kind = "Sand", Size = 1.2 },
	{ Az = 300, Dist = 880, Kind = "Stack", Size = 88 },
} :: { Spot }

---------------------------------------------------------------- pieces

-- White surf around an isle: one translucent slab just over the sea.
local function surf(m: Model, center: Vector3, w: number, d: number)
	Style.block(
		m,
		CFrame.new(center.X, SEA + 0.12, center.Z),
		Vector3.new(w + 7, 0.25, d + 7),
		C.Foam,
		nil,
		Kit.far({ Transparency = 0.45 })
	)
end

-- A leaning palm: three trunk beams and five drooping leaves. ~9 parts.
local function palm(m: Model, base: Vector3, h: number, rng: Rng.Rng)
	local yaw = rng:range(0, math.pi * 2)
	local lean = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * h * rng:range(0.18, 0.3)
	local pts = {
		base,
		base + lean * 0.25 + Vector3.new(0, h * 0.36, 0),
		base + lean * 0.62 + Vector3.new(0, h * 0.7, 0),
		base + lean + Vector3.new(0, h, 0),
	}
	local t = math.max(1, h * 0.09)
	for i = 1, 3 do
		Kit.beam(m, pts[i], pts[i + 1], t * (1.15 - i * 0.1), Style.vary(K.Palm, rng, 0.04))
	end
	local top = pts[4]
	local leaf = h * 0.42
	for k = 1, 5 do
		local a = k * (math.pi * 2 / 5) + rng:range(-0.25, 0.25)
		local cf = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(-rng:range(0.25, 0.45), 0, 0) * CFrame.new(0, 0, -leaf / 2)
		Style.block(m, cf, Vector3.new(t * 2.3, t * 0.45, leaf), if k % 2 == 0 then K.LeafLight else K.Leaf, nil, Kit.far())
	end
	Style.block(m, CFrame.new(top - Vector3.new(0, t * 0.5, 0)), Vector3.new(t * 1.6, t * 1.1, t * 1.6), K.HullDark, nil, Kit.far())
end

-- A Kenney rock stack: 2-3 chunky blocks narrowing upward.
local function rocks(m: Model, base: Vector3, h: number, w: number, light: Color3, dark: Color3, rng: Rng.Rng)
	local y = base.Y
	local n = if h > w * 1.2 then 3 else 2
	local cx, cz = base.X, base.Z
	for i = 1, n do
		local seg = h / n * rng:range(0.9, 1.1)
		local k = 1 - (i - 1) * 0.22
		Style.block(
			m,
			CFrame.new(cx, y + seg / 2, cz) * CFrame.Angles(0, rng:range(-0.3, 0.3), 0),
			Vector3.new(w * k, seg, w * k * rng:range(0.8, 1)),
			Style.vary(if i == 1 then dark else light, rng, 0.05),
			nil,
			Kit.far()
		)
		y += seg
		cx += rng:range(-w * 0.12, w * 0.12)
		cz += rng:range(-w * 0.12, w * 0.12)
	end
end

-- A small hut with a gable roof and a lit window, facing `face` (+Z local).
local function hut(m: Model, base: CFrame, w: number, d: number, h: number)
	Style.block(m, base * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), K.Tower, nil, Kit.far())
	local roofH = d * 0.5
	local half = (d + 1.2) / 2
	Geo.wedge(m, base * CFrame.new(0, h + roofH / 2, -half / 2), Vector3.new(w + 1.2, roofH, half), K.RoofBlueDark, nil, Kit.far())
	Geo.wedge(
		m,
		base * CFrame.new(0, h + roofH / 2, half / 2) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(w + 1.2, roofH, half),
		K.RoofBlue,
		nil,
		Kit.far()
	)
	Kit.glow(m, base * CFrame.new(w * 0.2, h * 0.55, d / 2 + 0.06), Vector3.new(w * 0.22, h * 0.3, 0.2), C.Lamp)
end

-- A turning lighthouse beam: two long faint shafts around an invisible hub
-- (the pivot), tag Spin.
local function beam(m: Model, at: Vector3, length: number, rng: Rng.Rng)
	local b = Style.model("LightBeam", m)
	local hub = Style.block(b, CFrame.new(at), Vector3.new(1, 1, 1), C.Lamp, nil, Kit.far({ Transparency = 1 }))
	hub.Name = "Hub"
	for _, side in { -1, 1 } do
		Kit.glow(b, CFrame.new(at) * CFrame.new(0, 0, side * (length / 2 + 2)), Vector3.new(2.6, 2.6, length), C.Lamp, 0.8)
	end
	b.PrimaryPart = hub
	b:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:range(0, math.pi), 0))
	b:AddTag("Spin")
	b:SetAttribute("SpinSpeed", 0.6)
	b:SetAttribute("BobHeight", 0)
end

---------------------------------------------------------------- isles

-- Candy sea stack: Spectrum pillars rising out of the surf, the tallest in
-- the middle, a pale lit top on each (grass and a tree on the tall ones).
-- ~14-22 parts.
local function stack(m: Model, c: Vector3, height: number, rng: Rng.Rng)
	local lane = rng:range(-170, 170)
	local w = math.floor(height * rng:range(0.16, 0.2))
	local function pillar(x: number, z: number, size: number, top: number, grass: boolean?)
		local shade = 14 + (top - SEA) / height * 150
		local color = Spectrum.color(lane + rng:range(-20, 20), shade, rng)
		Style.block(m, CFrame.new(x, (SEA - 2 + top) / 2, z), Vector3.new(size, top - SEA + 2, size), color, nil, Kit.far())
		local cap = if grass then C.Grass else Spectrum.tint(color)
		Style.block(m, CFrame.new(x, top + 0.45, z), Vector3.new(size + 0.4, 0.9, size + 0.4), cap, nil, Kit.far())
	end
	-- the tall stacks wear a grassy top with a big tree
	local crowned = height >= 80
	pillar(c.X, c.Z, w, SEA + height, crowned)
	if crowned then
		local kinds = { "Pink", "Green", "Orange", "Yellow" }
		Style.tree(m, CFrame.new(c.X, SEA + height + 0.9, c.Z), kinds[rng:int(1, #kinds)], rng, w / 7)
	end
	local step = w / 2
	for _ = 1, math.floor(rng:range(4, 6.99)) do
		local dx = math.floor(rng:range(-3.99, 4)) * step
		local dz = math.floor(rng:range(-3.99, 4)) * step
		if math.abs(dx) < step and math.abs(dz) < step then
			dx = step * 2
		end
		pillar(c.X + dx, c.Z + dz, w * rng:range(0.6, 1), SEA + height * rng:range(0.35, 0.8))
	end
	surf(m, c, w * 4, w * 4)
end

-- Kenney sand island: stepped sand, a grass patch, palms, orange rock
-- stacks and a little dock. ~45 parts at size 1.
local function sand(m: Model, c: Vector3, s: number, rng: Rng.Rng)
	local w, d = 70 * s, 52 * s
	surf(m, c, w, d)
	Style.block(m, CFrame.new(c.X, SEA + 0.5, c.Z), Vector3.new(w + 2, 1.4, d + 2), K.SandDark, nil, Kit.far())
	Style.block(m, CFrame.new(c.X, SEA + 2, c.Z), Vector3.new(w, 3, d), K.Sand, nil, Kit.far())
	-- a raised dune in the middle (turned twin: a rounder outline) and lumps
	local dune = CFrame.new(c.X, SEA + 4, c.Z)
	Style.block(m, dune, Vector3.new(w * 0.7, 4, d * 0.7), Style.vary(K.Sand, rng, 0.03), nil, Kit.far())
	Style.block(m, dune * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(d * 0.62, 3.8, d * 0.62), Style.vary(K.Sand, rng, 0.03), nil, Kit.far())
	for _ = 1, 3 do
		local lw, ld = w * rng:range(0.25, 0.4), d * rng:range(0.25, 0.4)
		local at = Vector3.new(c.X + rng:range(-w * 0.38, w * 0.38), SEA + 2.6, c.Z + rng:range(-d * 0.38, d * 0.38))
		Style.block(m, CFrame.new(at), Vector3.new(lw, 3.6, ld), Style.vary(K.SandDark:Lerp(K.Sand, 0.6), rng, 0.03), nil, Kit.far())
	end
	local top = SEA + 6
	local gx, gz = c.X + rng:range(-w * 0.1, w * 0.1), c.Z + rng:range(-d * 0.1, d * 0.1)
	Style.block(m, CFrame.new(gx, top + 0.1, gz), Vector3.new(w * 0.52, 0.8, d * 0.46), C.Grass, nil, Kit.far())
	Style.block(m, CFrame.new(gx + w * 0.08, top + 0.6, gz - d * 0.05), Vector3.new(w * 0.26, 0.8, d * 0.22), C.GrassLight, nil, Kit.far())
	for _ = 1, math.max(2, math.floor(3 * s + 0.5)) do
		local p = Vector3.new(gx + rng:range(-w * 0.22, w * 0.22), top + 0.5, gz + rng:range(-d * 0.2, d * 0.2))
		palm(m, p, 22 * s * rng:range(0.85, 1.15), rng)
	end
	for _ = 1, 2 do
		local edge = if rng:chance(0.5) then 1 else -1
		local p = Vector3.new(c.X + edge * w * rng:range(0.3, 0.42), SEA + 1, c.Z + rng:range(-d * 0.3, d * 0.3))
		rocks(m, p, 14 * s * rng:range(0.8, 1.3), 10 * s, K.RockOrange, K.RockOrangeDark, rng)
	end
	-- dock toward the town (the plaza side)
	local toTown = Vector3.new(-c.X, 0, -c.Z).Unit
	local start = Vector3.new(c.X, top - 0.3, c.Z) + toTown * d * 0.45
	local dockEnd = start + toTown * 18 * s
	local cf = CFrame.lookAt((start + dockEnd) / 2, dockEnd)
	Style.block(m, cf, Vector3.new(5 * s, 0.6, (dockEnd - start).Magnitude), C.Plank, nil, Kit.far())
	for _, f in { 0.45, 1 } do
		local p = start:Lerp(dockEnd, f)
		for _, side in { -1, 1 } do
			local post = cf.RightVector * side * 2.3 * s
			Style.block(m, CFrame.new(p + post - Vector3.new(0, 2, 0)), Vector3.new(0.9, 5.6, 0.9), C.WoodDark, nil, Kit.far())
		end
	end
	hut(m, CFrame.lookAt(Vector3.new(gx - w * 0.16, top + 0.5, gz), Vector3.new(gx - w * 0.16, top + 0.5, gz) + toTown), 8 * s, 7 * s, 6 * s)
end

-- Grey rock island with a red/white lighthouse, a keeper's hut and a
-- turning beam. ~28 parts at size 1.
local function lighthouse(m: Model, c: Vector3, s: number, rng: Rng.Rng)
	local w = 44 * s
	surf(m, c, w, w * 0.8)
	Style.block(m, CFrame.new(c.X, SEA + 3, c.Z), Vector3.new(w, 8, w * 0.8), K.RockGreyDark, nil, Kit.far())
	Style.block(m, CFrame.new(c.X - w * 0.06, SEA + 9, c.Z + w * 0.04), Vector3.new(w * 0.66, 6, w * 0.56), K.RockGrey, nil, Kit.far())
	for _ = 1, 3 do
		local edge = if rng:chance(0.5) then 1 else -1
		local p = Vector3.new(c.X + edge * w * rng:range(0.3, 0.45), SEA, c.Z + rng:range(-w * 0.35, w * 0.35))
		rocks(m, p, 12 * s * rng:range(0.9, 1.4), 9 * s, K.RockGrey, K.RockGreyDark, rng)
	end
	Style.block(m, CFrame.new(c.X - w * 0.06, SEA + 12.4, c.Z + w * 0.04), Vector3.new(w * 0.5, 0.8, w * 0.42), C.GrassDark, nil, Kit.far())
	-- tower: four tapering bands, red and white
	local x, z = c.X + w * 0.08, c.Z
	local y = SEA + 12
	local seg = 7 * s
	for i = 1, 4 do
		local dia = (11 - i * 0.8) * s
		Geo.cylinder(m, Vector3.new(x, y + seg / 2, z), seg, dia, if i % 2 == 1 then C.AwningWhite else C.AwningRed, nil, Kit.far())
		y += seg
	end
	-- gallery, lamp room, stepped blue cone roof with a tip
	Geo.cylinder(m, Vector3.new(x, y + 0.5 * s, z), 1 * s, 10.5 * s, C.Iron, nil, Kit.far())
	y += 1 * s
	Geo.cylinder(m, Vector3.new(x, y + 2.2 * s, z), 4.4 * s, 6 * s, C.Lamp, NEON, Kit.far())
	local lamp = Vector3.new(x, y + 2.2 * s, z)
	y += 4.4 * s
	for i, dia in { 7.4, 5.2, 3 } do
		local h = (1.6 - i * 0.2) * s
		Geo.cylinder(m, Vector3.new(x, y + h / 2, z), h, dia * s, if i == 2 then K.RoofBlueDark else K.RoofBlue, nil, Kit.far())
		y += h
	end
	Geo.ball(m, Vector3.new(x, y + 0.6 * s, z), 1.4 * s, C.Gold, nil, Kit.far())
	beam(m, lamp, 90 * s, rng)
	local toTown = Vector3.new(-c.X, 0, -c.Z).Unit
	local hp = Vector3.new(c.X - w * 0.2, SEA + 12.8, c.Z + w * 0.08)
	hut(m, CFrame.lookAt(hp, hp + toTown), 9 * s, 7 * s, 6 * s)
end

-- Kenney fortress: rock island, crenellated walls with a gate, a round tower
-- with a blue cone roof and a black flag. ~34 parts at size 1.
local function fort(m: Model, c: Vector3, s: number, rng: Rng.Rng)
	local w, d = 64 * s, 50 * s
	surf(m, c, w, d)
	Style.block(m, CFrame.new(c.X, SEA + 3.5, c.Z), Vector3.new(w, 9, d), K.RockGreyDark, nil, Kit.far())
	Style.block(m, CFrame.new(c.X, SEA + 8.4, c.Z), Vector3.new(w * 0.86, 1, d * 0.84), K.RockGrey, nil, Kit.far())
	for _ = 1, 3 do
		local edge = if rng:chance(0.5) then 1 else -1
		local p = Vector3.new(c.X + rng:range(-w * 0.4, w * 0.4), SEA, c.Z + edge * d * rng:range(0.36, 0.48))
		rocks(m, p, 10 * s * rng:range(0.9, 1.3), 9 * s, K.RockGrey, K.RockGreyDark, rng)
	end
	local toTown = Vector3.new(-c.X, 0, -c.Z).Unit
	local frame = CFrame.lookAt(Vector3.new(c.X, SEA + 8.9, c.Z), Vector3.new(c.X, SEA + 8.9, c.Z) + toTown)
	local wallH, wallT = 9 * s, 3 * s
	local hw, hd = w * 0.36, d * 0.34
	-- front (town side, -Z in the frame), left and right walls
	local walls: { { Center: Vector3, Size: Vector3, AlongX: boolean } } = {
		{ Center = Vector3.new(0, wallH / 2, -hd), Size = Vector3.new(hw * 2, wallH, wallT), AlongX = true },
		{ Center = Vector3.new(-hw, wallH / 2, 0), Size = Vector3.new(wallT, wallH, hd * 2), AlongX = false },
		{ Center = Vector3.new(hw, wallH / 2, 0), Size = Vector3.new(wallT, wallH, hd * 2), AlongX = false },
	}
	for i, wall in walls do
		local center, size, alongX = wall.Center, wall.Size, wall.AlongX
		Style.block(m, frame * CFrame.new(center), size, if i == 1 then K.Tower else K.TowerDark, nil, Kit.far())
		local len = if alongX then size.X else size.Z
		for j = 1, 4 do
			local t = (j - 0.5) / 4 - 0.5
			local off = if alongX then Vector3.new(t * len, 0, 0) else Vector3.new(0, 0, t * len)
			Style.block(
				m,
				frame * CFrame.new(center + off + Vector3.new(0, wallH / 2 + 1 * s, 0)),
				Vector3.new(2.6 * s, 2 * s, 2.6 * s),
				K.Tower,
				nil,
				Kit.far()
			)
		end
	end
	-- gate in the front wall
	Style.block(m, frame * CFrame.new(0, wallH * 0.32, -hd - wallT * 0.4), Vector3.new(7 * s, wallH * 0.64, 0.6), C.WoodDark, nil, Kit.far())
	Style.block(m, frame * CFrame.new(0, wallH * 0.7, -hd - wallT * 0.45), Vector3.new(9 * s, 1.2 * s, 0.8), K.TowerDark, nil, Kit.far())
	-- the round tower at the back corner, blue cone roof, flag
	local tp = (frame * CFrame.new(hw * 0.55, 0, hd * 0.4)).Position
	local th = 26 * s
	Geo.cylinder(m, tp + Vector3.new(0, th / 2, 0), th, 15 * s, K.Tower, nil, Kit.far())
	Geo.cylinder(m, tp + Vector3.new(0, th + 1.2 * s, 0), 2.4 * s, 17 * s, K.TowerDark, nil, Kit.far())
	local y = tp.Y + th + 2.4 * s
	for i, dia in { 15, 10.4, 5.8 } do
		local h = (4.6 - i * 0.6) * s
		Geo.cylinder(m, Vector3.new(tp.X, y + h / 2, tp.Z), h, dia * s, if i == 2 then K.RoofBlueDark else K.RoofBlue, nil, Kit.far())
		y += h
	end
	Style.block(m, CFrame.new(tp.X, y + 4 * s, tp.Z), Vector3.new(0.6, 8 * s, 0.6), C.WoodDark, nil, Kit.far())
	local flag = CFrame.lookAt(Vector3.new(tp.X, y + 6.4 * s, tp.Z), Vector3.new(tp.X, y + 6.4 * s, tp.Z) + toTown:Cross(Vector3.yAxis))
	Style.block(m, flag * CFrame.new(0, 0, -3 * s), Vector3.new(0.3, 3.6 * s, 6 * s), K.SailBlack, nil, Kit.far())
	Style.block(m, flag * CFrame.new(-0.2, 0.2 * s, -3 * s), Vector3.new(0.3, 1.6 * s, 1.6 * s), K.Skull, nil, Kit.far())
	-- a smaller open turret at the other corner, lit windows in the keep
	local sp = (frame * CFrame.new(-hw * 0.6, 0, hd * 0.3)).Position
	Geo.cylinder(m, sp + Vector3.new(0, 8 * s, 0), 16 * s, 10 * s, K.TowerDark, nil, Kit.far())
	Geo.cylinder(m, sp + Vector3.new(0, 16.8 * s, 0), 1.6 * s, 11.4 * s, K.Tower, nil, Kit.far())
	for _, h in { 0.45, 0.7 } do
		Kit.glow(m, CFrame.lookAt(tp + Vector3.new(0, th * h, 0), tp + Vector3.new(0, th * h, 0) + toTown) * CFrame.new(0, 0, -7.6 * s), Vector3.new(1.8 * s, 2.4 * s, 0.3), C.Lamp)
	end
end

-- A wreck on a sand bar: a tilted broken hull, a snapped mast with a torn
-- black sail, grey rocks. ~16 parts.
local function wreck(m: Model, c: Vector3, s: number, rng: Rng.Rng)
	local w, d = 46 * s, 30 * s
	surf(m, c, w, d)
	Style.block(m, CFrame.new(c.X, SEA + 0.8, c.Z), Vector3.new(w, 2.4, d), K.Sand, nil, Kit.far())
	Style.block(m, CFrame.new(c.X + w * 0.15, SEA + 2.2, c.Z - d * 0.1), Vector3.new(w * 0.5, 1.6, d * 0.5), K.SandDark, nil, Kit.far())
	for _ = 1, 3 do
		local p = Vector3.new(c.X + rng:range(-w * 0.42, w * 0.42), SEA, c.Z + rng:range(-d * 0.4, d * 0.4))
		rocks(m, p, 9 * s * rng:range(0.8, 1.4), 8 * s, K.RockGrey, K.RockGreyDark, rng)
	end
	local yaw = rng:range(0, math.pi * 2)
	local hull = CFrame.new(c.X - w * 0.05, SEA + 4.2, c.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(22))
	Style.block(m, hull, Vector3.new(11 * s, 6 * s, 30 * s), K.Wreck, nil, Kit.far())
	Style.block(m, hull * CFrame.new(0, -3.4 * s, 0), Vector3.new(6 * s, 1.6 * s, 26 * s), K.HullTrim, nil, Kit.far())
	Style.block(m, hull * CFrame.new(0, 3.4 * s, 9 * s), Vector3.new(10 * s, 3 * s, 8 * s), K.Wreck:Lerp(K.HullTrim, 0.3), nil, Kit.far())
	-- broken ribs where the bow broke off
	for i = 1, 3 do
		local rib = hull * CFrame.new((i - 2) * 3.4 * s, 4 * s, -13 * s) * CFrame.Angles(math.rad(rng:range(-12, 12)), 0, 0)
		Style.block(m, rib, Vector3.new(0.9 * s, 7 * s, 0.9 * s), K.HullTrim, nil, Kit.far())
	end
	local mast = hull * CFrame.new(0, 3 * s, 1 * s) * CFrame.Angles(math.rad(30), 0, math.rad(-10))
	Style.block(m, mast * CFrame.new(0, 9 * s, 0), Vector3.new(1.2 * s, 18 * s, 1.2 * s), K.HullTrim, nil, Kit.far())
	Style.block(m, mast * CFrame.new(0, 13 * s, -0.8 * s), Vector3.new(9 * s, 6 * s, 0.3), K.SailBlack, nil, Kit.far())
	Style.block(m, mast * CFrame.new(1.5 * s, 9.5 * s, -0.8 * s), Vector3.new(5 * s, 2 * s, 0.3), K.SailBlack, nil, Kit.far())
end

function Isles.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Isles", parent)
	for i, spot in Isles.Spots do
		local im = Style.model(`{spot.Kind}{i}`, m)
		local r = Rng.new(`Horizon/Isles/{i}/{rng:nextU32()}`)
		local c = Place.at(spot.Az, spot.Dist, SEA)
		if spot.Kind == "Stack" then
			stack(im, c, spot.Size, r)
		elseif spot.Kind == "Sand" then
			sand(im, c, spot.Size, r)
		elseif spot.Kind == "Lighthouse" then
			lighthouse(im, c, spot.Size, r)
		elseif spot.Kind == "Fort" then
			fort(im, c, spot.Size, r)
		elseif spot.Kind == "Wreck" then
			wreck(im, c, spot.Size, r)
		end
	end
	return m
end

return Isles
