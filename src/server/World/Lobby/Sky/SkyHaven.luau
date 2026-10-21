--[[
	SKY HAVEN (owner 2026-10-21): one bigger floating island you can climb to
	from the ground. A rock spire rises out of the sea off the south-east
	corner; stepping stones wind round it (a parkour climb, each stone a short
	jump higher than the last) up to the island. On the island: a village of
	cottages, trees, lanterns, a waterfall and, on a podium in the middle, the
	SKY EGG: a secret coin egg with three golems better than the Crystal
	capsule's but still below the Robux ones (the capsule and the golems are
	gameplay work for later; this builds the place).

	Walkable: the island's top, the stones, the podium's steps and the
	village paths collide; the rock underneath, leaves and glow don't.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Meadow = require(script.Parent.Parent.Flora.Meadow)

local C = Style.C
local NEON = Enum.Material.Neon

local SkyHaven = {}

SkyHaven.Center = Vector3.new(150, 72, 232) -- the island's ground point
SkyHaven.Size = Vector2.new(64, 52)
SkyHaven.Spire = Vector3.new(150, 0, 186) -- the rock spire in the sea
SkyHaven.SpireRadius = 9
SkyHaven.StepRadius = 16 -- the stones' path round the spire
SkyHaven.StepRise = 3.4 -- studs up per stone (a plain jump clears ~7)
SkyHaven.StepAngle = 0.5 -- radians between stones (~8 studs apart, gaps ~3)
SkyHaven.StepSize = 5
SkyHaven.Start = -math.pi / 2 -- the first stone faces the town (north, -Z)

local SKY_WHITE = Color3.fromRGB(240, 246, 255)
local SKY_BLUE = Color3.fromRGB(110, 190, 255)
local GOLD = Color3.fromRGB(255, 205, 70)

-- The stepping stones round the spire, from just above the sea to the island's edge.
local function parkour(m: Model, rng: Rng.Rng): { Vector3 }
	local stones: { Vector3 } = {}
	local spire = SkyHaven.Spire
	local topY = SkyHaven.Center.Y
	local count = math.ceil((topY - 2) / SkyHaven.StepRise)
	for i = 0, count - 1 do
		local a = SkyHaven.Start + i * SkyHaven.StepAngle
		local y = 2 + i * SkyHaven.StepRise
		local p = Vector3.new(spire.X + math.cos(a) * SkyHaven.StepRadius, y, spire.Z + math.sin(a) * SkyHaven.StepRadius)
		local s = SkyHaven.StepSize
		local stone = CFrame.new(p) * CFrame.Angles(0, -a, 0)
		Style.block(m, stone * CFrame.new(0, -0.6, 0), Vector3.new(s, 1.2, s), Style.vary(C.Stone, rng, 0.06), nil, Style.solid())
		Style.block(
			m,
			stone * CFrame.new(0, 0.05, 0),
			Vector3.new(s - 0.6, 0.12, s - 0.6),
			Style.vary(C.GrassLight, rng, 0.05),
			nil,
			Style.tiny()
		)
		Style.block(m, stone * CFrame.new(0, -1.6, 0), Vector3.new(s * 0.6, 1, s * 0.6), C.StoneDark, nil, Style.tiny())
		-- a glowing edge on the stone's outer side shows the way; a lantern every fifth stone
		Style.block(m, stone * CFrame.new(s / 2 - 0.1, -0.2, 0), Vector3.new(0.2, 0.25, s - 0.4), SKY_BLUE, NEON, Style.tiny())
		if i % 5 == 4 then
			Style.block(m, stone * CFrame.new(-s / 2 + 0.6, 1.2, 0), Vector3.new(0.35, 2.4, 0.35), C.WoodDark, nil, Style.tiny())
			Style.block(m, stone * CFrame.new(-s / 2 + 0.6, 2.7, 0), Vector3.new(0.75, 0.75, 0.75), C.LampAmber, NEON, Style.tiny())
		end
		table.insert(stones, p)
	end
	-- the spire: stacked rock drums narrowing to the top, crystals in its flanks
	local h = topY - 12
	local drums = 6
	for k = 0, drums - 1 do
		local t = k / drums
		local r = SkyHaven.SpireRadius * (1 - t * 0.45)
		local dh = h / drums
		local c = CFrame.new(spire.X, -6 + dh * (k + 0.5), spire.Z) * CFrame.Angles(0, k * 0.4, 0)
		Style.block(
			m,
			c,
			Vector3.new(r * 2, dh + 0.4, r * 2),
			Style.vary(if k % 2 == 0 then C.StoneDark else C.Stone, rng, 0.05),
			nil,
			Style.decor()
		)
		Style.block(
			m,
			c * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(r * 1.7, dh, r * 1.7),
			Style.vary(C.StoneDeep, rng, 0.05),
			nil,
			Style.tiny()
		)
		if k % 2 == 1 then
			Style.crystalCluster(m, c * CFrame.new(r * 0.8, -dh * 0.2, 0) * CFrame.Angles(0, 0, -0.9), 3.5, SKY_BLUE, rng, { Count = 2 })
		end
	end
	-- a plank bridge from the lobby's rim to the first stone
	local first = stones[1]
	local shore = Vector3.new(first.X, 0.6, 160)
	local dir = Vector3.new(0, 0, first.Z - shore.Z)
	local len = dir.Magnitude
	local mid = (shore + first) / 2
	Style.block(
		m,
		CFrame.lookAt(Vector3.new(mid.X, 1.1, mid.Z), Vector3.new(first.X, 1.1, first.Z)),
		Vector3.new(3.4, 0.4, len),
		C.Plank,
		nil,
		Style.solid()
	)
	for _, sx in { -1, 1 } do
		Style.block(m, CFrame.new(Vector3.new(mid.X + sx * 1.6, 1.8, mid.Z)), Vector3.new(0.25, 0.25, len), C.Wood, nil, Style.tiny())
	end
	-- the sign at the start
	Style.sign(m, CFrame.new(shore + Vector3.new(-3.5, 4.2, 0)) * CFrame.Angles(0, math.pi, 0), "SKY HAVEN", 7, 1.6, { Kind = "Wood" })
	return stones
end

-- A cottage: stone foot, timber walls, a gable roof, a lit window and a door facing `facing`.
local function cottage(m: Model, base: CFrame, rng: Rng.Rng, roof: Color3)
	local w, d, h = 9, 7, 5.5
	Style.block(m, base * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.8, 0.8, d + 0.8), C.StoneDark, nil, Style.solid())
	Style.block(m, base * CFrame.new(0, 0.8 + h / 2, 0), Vector3.new(w, h, d), Style.vary(C.Plank, rng, 0.05), nil, Style.solid())
	for _, sx in { -1, 1 } do
		Style.block(
			m,
			base * CFrame.new(sx * (w / 2 - 0.3), 0.8 + h / 2, -d / 2 - 0.05),
			Vector3.new(0.6, h, 0.3),
			C.WoodDark,
			nil,
			Style.tiny()
		)
	end
	Style.gableRoof(
		m,
		base * CFrame.new(0, 0.8 + h, 0),
		w + 1.6,
		d + 1.6,
		3.4,
		{ Color = roof, Dark = roof:Lerp(Color3.new(0, 0, 0), 0.3), Trim = C.WoodDark }
	)
	Style.block(m, base * CFrame.new(-1.8, 0.8 + 1.4, -d / 2 - 0.1), Vector3.new(1.6, 2.8, 0.2), C.WoodDark, nil, Style.tiny())
	Kit.window(m, base * CFrame.new(1.9, 0.8 + 3, -d / 2 - 0.2) * CFrame.Angles(0, math.pi, 0), 1.6, 1.3)
	Style.block(m, base * CFrame.new(w / 2 - 1.5, 0.8 + h + 3, 1.5), Vector3.new(1.1, 2.6, 1.1), C.StoneDark, nil, Style.tiny())
end

-- The SKY EGG on its podium: a voxel egg (stacked layers, two squares each), cloud white with sky
-- blue and gold bands, glowing cracks, a halo ring and floating crystals.
local function eggPodium(m: Model, base: CFrame, rng: Rng.Rng)
	-- the podium: three stepped octagon-ish tiers and a neon ring
	for i, r in { 9, 7.2, 5.6 } do
		local y = (i - 0.5) * 1.1
		for _, turn in { 0, math.pi / 4 } do
			Style.block(
				m,
				base * CFrame.new(0, y, 0) * CFrame.Angles(0, turn, 0),
				Vector3.new(r * 2, 1.1, r * 2),
				Style.vary(if i == 3 then C.StoneLight else C.Stone, rng, 0.03),
				nil,
				Style.solid()
			)
		end
	end
	local top = base * CFrame.new(0, 3.3, 0)
	-- a thin glowing ring round the egg's plinth (four strips, not a glowing slab)
	for k = 0, 3 do
		Style.block(
			m,
			top * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0.08, 4.6),
			Vector3.new(9.4, 0.16, 0.3),
			SKY_BLUE,
			NEON,
			Style.tiny()
		)
	end
	-- the egg: profile radius by height (egg shape: wider low, narrower high)
	local H = 9
	local layers = 9
	for k = 0, layers - 1 do
		local t = (k + 0.5) / layers
		local r = 3.6 * math.sqrt(math.max(0, 1 - (2 * t - 1) ^ 2)) * (1.08 - 0.22 * t)
		local y = 0.2 + H * t
		local band = if k == 3 then GOLD elseif k == 5 then SKY_BLUE else SKY_WHITE
		for _, turn in { 0, math.pi / 4 } do
			Style.block(
				m,
				top * CFrame.new(0, y, 0) * CFrame.Angles(0, turn, 0),
				Vector3.new(r * 2, H / layers + 0.05, r * 2),
				band,
				nil,
				Style.decor()
			)
		end
	end
	-- glowing cracks and gold spots on the shell
	for i = 1, 6 do
		local a = i * math.pi / 3 + rng:range(-0.2, 0.2)
		local y = rng:range(2, 7)
		local t = y / H
		local r = 3.6 * math.sqrt(math.max(0, 1 - (2 * t - 1) ^ 2)) * (1.08 - 0.22 * t)
		Style.block(
			m,
			top * CFrame.new(math.cos(a) * (r + 0.05), y, math.sin(a) * (r + 0.05)) * CFrame.Angles(0, -a, rng:range(-0.7, 0.7)),
			Vector3.new(0.12, 1.4, 0.5),
			Color3.fromRGB(130, 240, 255),
			NEON,
			Style.tiny()
		)
	end
	-- the halo and floating crystals round it
	for k = 0, 11 do
		local a = k * math.pi / 6
		Style.block(
			m,
			top * CFrame.new(math.cos(a) * 6, 10.5, math.sin(a) * 6) * CFrame.Angles(0, -a, 0),
			Vector3.new(0.22, 0.22, 3.1),
			GOLD,
			NEON,
			Style.tiny()
		)
	end
	for k = 1, 4 do
		local a = k * math.pi / 2 + 0.4
		Style.crystal(
			m,
			top * CFrame.new(math.cos(a) * 7.5, rng:range(4, 7), math.sin(a) * 7.5) * CFrame.Angles(0.3, a, 0.2),
			2.6,
			0.9,
			SKY_BLUE
		)
	end
	-- the board in front
	Style.sign(m, base * CFrame.new(0, 1.4, -10.4) * CFrame.Angles(0, math.pi, 0), "SKY EGG", 6, 1.5, { Kind = "Wood" })
end

function SkyHaven.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("SkyHaven", parent)
	local center = SkyHaven.Center
	local frame = CFrame.lookAt(center, Vector3.new(center.X, center.Y, 0)) -- front (-Z local) toward the town
	local w, d = SkyHaven.Size.X, SkyHaven.Size.Y
	local rock = Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 52, Tiers = 6 })
	for _, p in rock:GetChildren() do
		if p:IsA("BasePart") and p.CFrame.Position.Y > center.Y - 2.6 then
			p.CanCollide = true
			p.CanQuery = true
		end
	end
	parkour(m, rng)
	-- a path from the parkour's arrival (front edge) to the podium, then on to the village
	local path = Style.model("Paths", m)
	Style.block(path, frame * CFrame.new(0, 0.12, -d / 2 + 8), Vector3.new(4, 0.24, 16), C.Cobble, nil, Style.solid())
	Style.block(path, frame * CFrame.new(0, 0.12, 11), Vector3.new(30, 0.24, 4), C.Cobble, nil, Style.solid())
	eggPodium(m, frame * CFrame.new(0, 0, -2), rng)
	-- the village: three cottages at the back, doors toward the egg
	for i, spot in
		{
			{ X = -20, Z = 16, Roof = C.RoofTerracotta },
			{ X = 0, Z = 19, Roof = Color3.fromRGB(80, 130, 200) },
			{ X = 20, Z = 16, Roof = C.RoofTerracotta },
		}
	do
		local base = frame * CFrame.new(spot.X, 0, spot.Z) * CFrame.Angles(0, if i == 1 then -0.35 elseif i == 3 then 0.35 else 0, 0)
		cottage(m, base, rng, spot.Roof)
	end
	-- trees: jungle giants at the corners, blossom and green trees between
	for _, t in { { X = -26, Z = 4 }, { X = 26, Z = 5 } } do
		Meadow.jungleTree(m, (frame * CFrame.new(t.X, 0, t.Z)).Position, 15, 5.5, rng, nil)
	end
	Style.tree(m, frame * CFrame.new(-14, 0, -12), "Pink", rng, 1.15)
	Style.tree(m, frame * CFrame.new(16, 0, -14), "Pink", rng, 1.05)
	Style.tree(m, frame * CFrame.new(-28, 0, 20), "Green", rng, 1)
	-- lanterns along the front path
	for _, z in { -20, -13 } do
		for _, sx in { -1, 1 } do
			local at = frame * CFrame.new(sx * 3.4, 0, z)
			Style.block(m, at * CFrame.new(0, 1.4, 0), Vector3.new(0.4, 2.8, 0.4), C.WoodDark, nil, Style.tiny())
			Style.block(m, at * CFrame.new(0, 3.1, 0), Vector3.new(0.8, 0.9, 0.8), C.LampAmber, NEON, Style.tiny())
		end
	end
	-- a waterfall off the east edge
	Kit.box(m, frame, Vector3.new(w / 2 - 8, 0.15, 0), Vector3.new(14, 0.3, 3), C.Water, nil, Kit.far({ Transparency = 0.15 }))
	Kit.skyFall(m, frame * CFrame.new(w / 2 + 0.5, -0.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), 48, 5, rng)
	return m
end

return SkyHaven
