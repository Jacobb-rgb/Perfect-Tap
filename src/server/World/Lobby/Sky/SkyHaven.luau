--[[
	SKY HAVEN (owner 2026-10-21): one bigger floating island you can climb to
	from the ground. A rock spire rises out of the sea off the south-east
	corner; stepping stones wind round it (a parkour climb, each stone a short
	jump higher than the last) up to the island. (Owner 2026-10-22: "make the
	steps more massive, little levitating islands, and improve the mountain,
	add moss": every stone is a little floating islet, the spire has moss on
	its ledges, vines, mossy outcrops, bushes and a crystal crown; and vines
	with glowing buds hang from under the island.) On the island: a village of
	cottages, trees, a waterfall and, on a podium in the middle, the SKY EGG:
	a secret coin egg with three golems better than the Crystal capsule's but
	still below the Robux ones (the capsule and the golems are gameplay work
	for later; this builds the place). The egg (owner 2026-10-22: "cooler
	still than the eggs below") is the town's premium egg recipe in its own
	Sky theme (CapsuleEggs.Themes.Sky: pearl over sky blue, gold claw, wings,
	a halo) at more than twice the stall eggs' size, turning slowly, two
	glowing orbit rings with riding crystals round it, a beam of light into
	the sky, four pearl columns with floating crystals and clouds round the
	podium. A lit path (owner: "a cool lit path to the egg") runs from the
	last stone to the podium: a dark walkway with neon edges and pearl tiles
	under three pearl-and-gold sky gates with hanging lanterns (the first one
	carries the SKY EGG board) and floating lights bobbing beside it.

	Walkable: the island's top, the stones, the podium's steps and the
	village paths collide; the rock underneath, leaves and glow don't.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Meadow = require(script.Parent.Parent.Flora.Meadow)
local Tech = require(script.Parent.Parent.Districts.Tech)

local C = Style.C
local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil
local PI = math.pi

local SkyHaven = {}

-- the south coast (WorldLayout.Island follows the plot size): the spire stands in the sea
-- 36 studs out from it, the island floats beyond the spire
SkyHaven.CoastZ = WorldLayout.Island.Max.Z
SkyHaven.Spire = Vector3.new(WorldLayout.SouthGate.X, 0, SkyHaven.CoastZ + 36) -- the rock spire in the sea, out from the wall's gate
SkyHaven.Center = SkyHaven.Spire + Vector3.new(0, 72, 50) -- the island's ground point
SkyHaven.Size = Vector2.new(64, 60)
SkyHaven.SpireRadius = 9
SkyHaven.StepRadius = 16 -- the stones' path round the spire
SkyHaven.StepRise = 3.4 -- studs up per stone (a plain jump clears ~7)
SkyHaven.StepFrom = 2 -- the first stone's top, by the bridge
SkyHaven.StepCount = math.ceil((SkyHaven.Center.Y - SkyHaven.StepFrom) / SkyHaven.StepRise)
-- one and a half turns round the spire (~7.5 studs apart, gaps ~2.5): the last stone lands
-- in front of the island's front edge, where the lit path starts
SkyHaven.StepAngle = 3 * math.pi / (SkyHaven.StepCount - 1)
SkyHaven.StepSize = 5.5 -- the islets' grass tops
SkyHaven.Start = -math.pi / 2 -- the first stone faces the town (north, -Z)
SkyHaven.Podium = 0 -- the egg podium's local z on the island (front = -Z)
SkyHaven.PodiumReach = 9 * math.sqrt(2) -- the podium's star points (two turned squares)
SkyHaven.EggScale = 3.2 -- the SKY EGG against the opening's egg (the town's stall eggs are 1.45)
SkyHaven.EggSpin = 0.35 -- radians per second (client, DecorController)
SkyHaven.BeamTop = 64 -- the light beam's top over the podium
SkyHaven.SpireBase = -24 -- the spire's foot under the sea (its top surface at -21, Sea)
SkyHaven.PathLift = 0.15 -- the paths' extra height over the island's top (its light-grass cap tops at +0.35)

local PEARL = Color3.fromRGB(244, 248, 255)
local SKY_STONE = Color3.fromRGB(196, 210, 236)
local SKY_BLUE = Color3.fromRGB(110, 190, 255)
local SKY_GLOW = Color3.fromRGB(90, 200, 255)
local SKY_DEEP = Color3.fromRGB(50, 150, 255) -- neon sky blue that stays blue under bloom
local GOLD = Color3.fromRGB(255, 205, 70)
local GOLD_GLOW = Color3.fromRGB(240, 160, 20) -- neon gold that stays gold under bloom
local GOLD_TEXT = Color3.fromRGB(255, 184, 24)
local NAVY = Color3.fromRGB(24, 32, 74)
local NAVY_DARK = Color3.fromRGB(14, 18, 46)
local WALK = Color3.fromRGB(40, 48, 82) -- the lit path's dark walkway (like the lobby's neon walkways)
local MOSS = Color3.fromRGB(78, 140, 58) -- moss on the spire's ledges and under the islets
local FLOWERS = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 214, 90), Color3.fromRGB(150, 200, 255) }

-- The stepping stones' top centers, first (just above the sea, at the bridge) to last (at the
-- island's front edge); each stone is StepSize square, turned to face the spire.
function SkyHaven.stonePositions(): { Vector3 }
	local out: { Vector3 } = {}
	local spire = SkyHaven.Spire
	for i = 0, SkyHaven.StepCount - 1 do
		local a = SkyHaven.Start + i * SkyHaven.StepAngle
		local y = SkyHaven.StepFrom + i * SkyHaven.StepRise
		table.insert(out, Vector3.new(spire.X + math.cos(a) * SkyHaven.StepRadius, y, spire.Z + math.sin(a) * SkyHaven.StepRadius))
	end
	return out
end

-- A stepping stone as a little floating islet (owner 2026-10-22: "make the steps more massive:
-- little levitating islands"). `stone` = the top's center, turned to face the spire. The grass
-- top is the only solid part (in `m`); under it (in `decor`, never in the way of a jump): a dirt
-- band turned 45 degrees, two stone tiers narrowing to a hanging tip and a moss drip. On top: a
-- lighter grass cap, a glowing edge on the outer side (the way up) and one small touch by turns
-- (a tuft, flowers, a crystal, a mossy rock); a lantern every fifth islet.
local function islet(m: Model, decor: Model, stone: CFrame, i: number, rng: Rng.Rng)
	local s = SkyHaven.StepSize
	Style.block(m, stone * CFrame.new(0, -0.45, 0), Vector3.new(s, 0.9, s), Style.vary(C.Grass, rng, 0.05), nil, Style.solid())
	Style.block(
		m,
		stone * CFrame.new(0, 0.05, 0),
		Vector3.new(s - 0.6, 0.12, s - 0.6),
		Style.vary(C.GrassLight, rng, 0.05),
		nil,
		Style.tiny()
	)
	local under = Style.tiny()
	Style.block(
		decor,
		stone * CFrame.new(0, -1.35, 0) * CFrame.Angles(0, PI / 4, 0),
		Vector3.new(s * 0.92, 1.0, s * 0.92),
		Style.vary(C.Dirt, rng, 0.06),
		nil,
		under
	)
	Style.block(
		decor,
		stone * CFrame.new(0, -2.65, 0) * CFrame.Angles(0, 0.35, 0),
		Vector3.new(s * 0.74, 1.7, s * 0.74),
		Style.vary(C.StoneDark, rng, 0.05),
		nil,
		under
	)
	Style.block(
		decor,
		stone * CFrame.new(0.2, -4.2, 0) * CFrame.Angles(0, 0.9, 0),
		Vector3.new(s * 0.46, 1.6, s * 0.46),
		Style.vary(C.StoneDeep, rng, 0.05),
		nil,
		under
	)
	Style.block(decor, stone * CFrame.new(0.3, -5.45, 0), Vector3.new(s * 0.2, 1.1, s * 0.2), C.StoneDeep, nil, under)
	-- moss dripping off the dirt band on the outer side
	Style.block(decor, stone * CFrame.new(s * 0.36, -1.9, s * 0.1), Vector3.new(0.3, 1.4, s * 0.4), Style.vary(MOSS, rng, 0.06), nil, under)
	-- a glowing edge on the outer side shows the way
	Style.block(m, stone * CFrame.new(s / 2 - 0.1, -0.2, 0), Vector3.new(0.2, 0.25, s - 0.4), SKY_BLUE, NEON, Style.tiny())
	-- one small touch on top, toward the back corner (never on the landing spot's middle)
	local spot = stone * CFrame.new(-s * 0.3, 0.1, s * 0.3)
	local touch = i % 4
	if i % 5 == 0 then
		Style.block(m, stone * CFrame.new(-s / 2 + 0.6, 1.2, 0), Vector3.new(0.35, 2.4, 0.35), C.WoodDark, nil, Style.tiny())
		Style.block(m, stone * CFrame.new(-s / 2 + 0.6, 2.7, 0), Vector3.new(0.75, 0.75, 0.75), C.LampAmber, NEON, Style.tiny())
	elseif touch == 0 then
		for _, lean in { -0.35, 0.3 } do
			local bh = rng:range(1.1, 1.7)
			Style.block(
				decor,
				spot * CFrame.Angles(0, 0, lean) * CFrame.new(0, bh / 2, 0),
				Vector3.new(0.28, bh, 0.5),
				Style.vary(C.LeafGreenLight, rng, 0.06),
				nil,
				Style.tiny()
			)
		end
	elseif touch == 1 then
		for f, dx in { -0.4, 0.45 } do
			local fh = rng:range(0.7, 1.0)
			local at = spot * CFrame.new(dx, 0, f * 0.3)
			Style.block(decor, at * CFrame.new(0, fh / 2, 0), Vector3.new(0.14, fh, 0.14), C.LeafGreen, nil, Style.tiny())
			Style.block(decor, at * CFrame.new(0, fh, 0), Vector3.new(0.45, 0.3, 0.45), FLOWERS[(i + f) % #FLOWERS + 1], nil, Style.tiny())
		end
	elseif touch == 2 then
		Style.crystal(decor, spot * CFrame.Angles(0.2, 0.5, -0.15), 1.5, 0.55, SKY_DEEP, nil, 0.12)
	else
		local rs = rng:range(0.9, 1.2)
		local rock = spot * CFrame.new(0, rs * 0.3, 0) * CFrame.Angles(0, rng:range(0, 1.5), 0)
		Style.block(decor, rock, Vector3.new(rs * 1.2, rs * 0.7, rs), Style.vary(C.Stone, rng, 0.06), nil, Style.tiny())
		Style.block(
			decor,
			rock * CFrame.new(0, rs * 0.38, 0),
			Vector3.new(rs * 1.1, 0.16, rs * 0.9),
			Style.vary(MOSS, rng, 0.06),
			nil,
			Style.tiny()
		)
	end
end

-- The stepping stones round the spire, from just above the sea to the island's edge (the
-- spire itself goes into `decor`, the Lod part).
local function parkour(m: Model, decor: Model, rng: Rng.Rng): { Vector3 }
	local stones = SkyHaven.stonePositions()
	local spire = SkyHaven.Spire
	local topY = SkyHaven.Center.Y
	for i, p in stones do
		local a = SkyHaven.Start + (i - 1) * SkyHaven.StepAngle
		islet(m, decor, CFrame.new(p) * CFrame.Angles(0, -a, 0), i, rng)
	end
	-- the spire: stacked rock drums narrowing to the top, rising out of the sea, crystals in its
	-- flanks; moss on every ledge and down the sides in vines, mossy rock outcrops, a crystal crown
	local base = SkyHaven.SpireBase
	local h = topY - 18 - base
	local drums = 6
	for k = 0, drums - 1 do
		local t = k / drums
		local r = SkyHaven.SpireRadius * (1 - t * 0.45)
		local dh = h / drums
		local c = CFrame.new(spire.X, base + dh * (k + 0.5), spire.Z) * CFrame.Angles(0, k * 0.4, 0)
		Style.block(
			decor,
			c,
			Vector3.new(r * 2, dh + 0.4, r * 2),
			Style.vary(if k % 2 == 0 then C.StoneDark else C.Stone, rng, 0.05),
			nil,
			Style.decor()
		)
		Style.block(
			decor,
			c * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(r * 1.7, dh, r * 1.7),
			Style.vary(C.StoneDeep, rng, 0.05),
			nil,
			Style.tiny()
		)
		-- (the sea hides the lowest drum's top: no moss down there)
		if k > 0 then
			-- a moss carpet on the drum's top ledge, its rim over the edge
			Style.block(
				decor,
				c * CFrame.new(0, dh / 2 + 0.05, 0),
				Vector3.new(r * 2 + 0.3, 0.5, r * 2 + 0.3),
				Style.vary(MOSS, rng, 0.06),
				nil,
				Style.tiny()
			)
			-- vines hanging from it down the four faces
			for v = 0, 2 do
				local face = (v + k) % 4
				local along = rng:range(-r * 0.7, r * 0.7)
				local long = dh * rng:range(0.35, 0.7)
				local onFace = c * CFrame.Angles(0, face * math.pi / 2, 0) * CFrame.new(along, dh / 2 - long / 2, -r - 0.12)
				Style.block(
					decor,
					onFace,
					Vector3.new(rng:range(0.5, 0.9), long, 0.25),
					Style.vary(C.LeafGreen, rng, 0.08),
					nil,
					Style.tiny()
				)
			end
		end
		-- two mossy rock outcrops sticking out of the flanks
		for o = 1, 2 do
			local around = k * 1.3 + o * math.pi + rng:range(-0.4, 0.4)
			local size = r * rng:range(0.45, 0.6)
			local out = c
				* CFrame.Angles(0, around, 0)
				* CFrame.new(0, rng:range(-dh * 0.25, dh * 0.2), -r - size * 0.15)
				* CFrame.Angles(rng:range(-0.25, 0.25), rng:range(0, 1.5), 0)
			Style.block(decor, out, Vector3.new(size, size * 0.7, size), Style.vary(C.Stone, rng, 0.06), nil, Style.tiny())
			Style.block(
				decor,
				out * CFrame.new(0, size * 0.35 + 0.1, 0),
				Vector3.new(size * 1.05, 0.3, size * 1.05),
				Style.vary(MOSS, rng, 0.06),
				nil,
				Style.tiny()
			)
		end
		if k % 2 == 1 then
			Style.crystalCluster(
				decor,
				c * CFrame.new(r * 0.8, -dh * 0.2, 0) * CFrame.Angles(0, 0, -0.9),
				3.5,
				SKY_DEEP,
				rng,
				{ Count = 2, TipLerp = 0.12 }
			)
		end
	end
	-- the crown: a crystal cluster in the moss on the spire's top
	local crown = CFrame.new(spire.X, base + h + 0.2, spire.Z) * CFrame.Angles(0, 0.7, 0)
	Style.crystalCluster(decor, crown, 4.2, SKY_DEEP, rng, { Count = 4, TipLerp = 0.12 })
	-- little bushes growing on the ledges
	for b, k in { 1, 3, 4 } do
		local r = SkyHaven.SpireRadius * (1 - k / drums * 0.45)
		local around = b * 2.1 + 0.6
		local at = CFrame.new(spire.X, base + h / drums * (k + 1) + 0.3, spire.Z) * CFrame.Angles(0, around, 0) * CFrame.new(0, 0, -r + 0.6)
		local size = rng:range(1.6, 2.2)
		Style.block(
			decor,
			at * CFrame.new(0, size * 0.4, 0),
			Vector3.new(size, size * 0.8, size),
			Style.vary(C.LeafGreen, rng, 0.06),
			nil,
			Style.tiny()
		)
		Style.block(
			decor,
			at * CFrame.new(size * 0.25, size * 0.75, -0.2) * CFrame.Angles(0, 0.6, 0),
			Vector3.new(size * 0.6, size * 0.5, size * 0.6),
			Style.vary(C.LeafGreenLight, rng, 0.06),
			nil,
			Style.tiny()
		)
	end
	-- a plank bridge from the gate in the island's south wall (WorldLayout.SouthGate) over the
	-- rim (its grass top ~1.8) to the first stone, and a ramp plank up to it from the lawn (y 0)
	local first = stones[1]
	local shore = Vector3.new(first.X, 0, SkyHaven.CoastZ + 3.5)
	local len = first.Z - shore.Z
	local foot = Vector3.new(first.X, -0.15, SkyHaven.CoastZ + 0.3)
	local head = Vector3.new(first.X, 1.7, shore.Z + 0.2)
	local ramp =
		Style.block(m, CFrame.lookAt((foot + head) / 2, head), Vector3.new(3.4, 0.4, (head - foot).Magnitude), C.Plank, nil, Style.solid())
	ramp.Name = "Ramp"
	local mid = (shore + first) / 2
	Style.block(
		m,
		CFrame.lookAt(Vector3.new(mid.X, 1.7, mid.Z), Vector3.new(first.X, 1.7, first.Z)),
		Vector3.new(3.4, 0.4, len),
		C.Plank,
		nil,
		Style.solid()
	)
	for _, sx in { -1, 1 } do
		Style.block(m, CFrame.new(Vector3.new(mid.X + sx * 1.6, 2.4, mid.Z)), Vector3.new(0.25, 0.25, len), C.Wood, nil, Style.tiny())
	end
	-- the sign on the rim just out past the wall, beside the gate (out of the lobby area), facing
	-- the town (a board's front is its LookVector)
	local signAt = Vector3.new(first.X - 6.6, 0, SkyHaven.CoastZ + 5)
	Style.sign(m, CFrame.new(signAt + Vector3.new(0, 4.4, 0)), "SKY HAVEN", 6, 1.5, { Kind = "Wood" })
	for _, sx in { -1, 1 } do
		Style.block(m, CFrame.new(signAt + Vector3.new(sx * 2.6, 1.3, 0.45)), Vector3.new(0.4, 4.6, 0.4), C.WoodDark, nil, Style.tiny())
	end
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

-- A ring of neon segments (`n` beams, `width` thick) in the XZ plane of `frame`.
local function ring(parent: Instance, frame: CFrame, radius: number, n: number, width: number, color: Color3)
	for i = 1, n do
		local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
		local p0 = (frame * CFrame.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)).Position
		local p1 = (frame * CFrame.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)).Position
		local dir = (p1 - p0).Unit
		Kit.beam(parent, p0 - dir * width / 2, p1 + dir * width / 2, width, color).Material = NEON
	end
end

-- A ball (a round cloud puff, a floating light).
local function ball(parent: Instance, position: Vector3, size: number, color: Color3, material: Enum.Material?): Part
	local p = Style.block(parent, CFrame.new(position), Vector3.new(size, size, size), color, material, Style.tiny())
	p.Shape = Enum.PartType.Ball
	return p
end

-- A model the client turns about its pivot (DecorController: the "Spin" tag).
local function spinner(m: Model, pivot: Part, spin: number, bob: number?)
	m.PrimaryPart = pivot
	m:SetAttribute("SpinSpeed", spin)
	m:SetAttribute("BobHeight", bob or 0)
	Style.streaming(m, "Atomic")
	m:AddTag("Spin")
end

-- The SKY EGG on its podium (see the header). `base` = the podium's bottom center, front = -Z;
-- the columns, the clouds and the beam go into `decor` (the Lod part).
local function eggPodium(m: Model, decor: Model, base: CFrame, rng: Rng.Rng)
	-- the podium: three stepped tiers (two turned squares each), pearl over sky stone, a gold lip under every step
	for i, r in { 9, 7.2, 5.6 } do
		local y = (i - 0.5) * 1.1
		for _, turn in { 0, PI / 4 } do
			local at = base * CFrame.new(0, y, 0) * CFrame.Angles(0, turn, 0)
			Style.block(
				m,
				at,
				Vector3.new(r * 2, 1.1, r * 2),
				Style.vary(if i == 3 then PEARL else SKY_STONE, rng, 0.03),
				nil,
				Style.solid()
			)
			Style.block(m, at * CFrame.new(0, 0.4, 0), Vector3.new(r * 2 + 0.3, 0.2, r * 2 + 0.3), GOLD, FOIL, Style.tiny())
		end
	end
	local top = base * CFrame.new(0, 3.3, 0)
	-- the egg's stall hook for the capsule side (CapsuleConfig "Sky": prompt, odds board)
	local hook = Style.block(m, top * CFrame.new(0, 0.5, 0), Vector3.new(7, 1, 7), C.StoneLight, nil, Style.tiny({ Transparency = 1 }))
	hook.Name = "SkyEggPodium"
	hook:SetAttribute("Capsule", "Sky")
	-- a thin glowing ring round the egg's plinth (four strips, not a glowing slab)
	for k = 0, 3 do
		Style.block(
			m,
			top * CFrame.Angles(0, k * PI / 2, 0) * CFrame.new(0, 0.08, 4.6),
			Vector3.new(9.4, 0.16, 0.3),
			SKY_BLUE,
			NEON,
			Style.tiny()
		)
	end

	-- the egg: the town's premium egg in the Sky theme, scaled about its center, turning slowly
	local k = SkyHaven.EggScale
	local center = top * CFrame.new(0, (1.25 + 0.15) * k, 0)
	local egg = GolemBuilder.themedEgg("Sky", center, { Calm = true })
	for _, d in egg:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = center:ToObjectSpace(d.CFrame)
			d.CFrame = center * CFrame.new(rel.Position * k) * rel.Rotation
			d.Size *= k
		end
	end
	egg.Name = "SkyEgg"
	egg.Parent = m
	spinner(egg, egg.PrimaryPart :: Part, SkyHaven.EggSpin)
	local glow = Style.block(m, center, Vector3.new(0.4, 0.4, 0.4), SKY_GLOW, nil, Style.tiny({ Transparency = 1 }))
	glow.Name = "SkyEggLight"
	Style.light(glow, SKY_GLOW, 18, 0.9)
	-- sparkles drifting off the shell
	local sparkles = Style.block(m, center, Vector3.new(8, 10, 8), SKY_GLOW, nil, Style.tiny({ Transparency = 1 }))
	sparkles.Name = "SkyEggSparkles"
	Style.emitter(sparkles, "Sparkle", Color3.fromRGB(200, 240, 255), 8)

	-- two tilted orbit rings round the egg (gold and sky blue), three crystals riding the gold one
	local orbit = Style.model("SkyOrbit", m)
	local hub = Style.block(orbit, center, Vector3.new(0.2, 0.2, 0.2), GOLD, nil, Style.tiny({ Transparency = 1 }))
	hub.Name = "OrbitHub"
	for r, o in { { 10.2, 0.3, 0 }, { 9.2, -0.36, 1.1 } } do
		local frame = center * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, o[3], 0) * CFrame.Angles(o[2], 0, 0)
		ring(orbit, frame, o[1], 14, 0.2, if r == 1 then GOLD_GLOW else SKY_DEEP)
		if r == 1 then
			for c = 0, 2 do
				local a = c * 2 * PI / 3 + 0.5
				Style.crystal(orbit, frame * CFrame.new(math.cos(a) * o[1], -0.9, math.sin(a) * o[1]), 1.8, 0.7, SKY_DEEP, nil, 0.12)
			end
		end
	end
	spinner(orbit, hub, -0.45)

	-- a beam of light from the crown into the sky (seen from the town: something is up there)
	local beamY0 = (1.25 + 0.15) * k + 2.4 * k
	local beam = Style.block(
		decor,
		top * CFrame.new(0, (beamY0 + SkyHaven.BeamTop) / 2, 0) * CFrame.Angles(0, 0, PI / 2),
		Vector3.new(SkyHaven.BeamTop - beamY0, 1.1, 1.1),
		Color3.fromRGB(150, 215, 255),
		NEON,
		Style.tiny({ Transparency = 0.65 })
	)
	beam.Shape = Enum.PartType.Cylinder
	beam.Name = "SkyBeam"

	-- four pearl columns on the diagonals: a gold foot and capital, a glowing stripe toward the egg,
	-- a crystal floating over each
	for c = 0, 3 do
		local a = (c + 0.5) * PI / 2
		local p = (base * CFrame.new(math.sin(a) * 14.6, 0, -math.cos(a) * 14.6)).Position
		local at = CFrame.lookAt(p, Vector3.new(base.Position.X, p.Y, base.Position.Z))
		Style.block(decor, at * CFrame.new(0, 0.5, 0), Vector3.new(2.3, 1, 2.3), GOLD, FOIL, Style.decor())
		local shaft = Style.block(
			decor,
			at * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, PI / 2),
			Vector3.new(7.2, 1.5, 1.5),
			PEARL,
			nil,
			Style.decor()
		)
		shaft.Shape = Enum.PartType.Cylinder
		Kit.glow(decor, at * CFrame.new(0, 4.6, -0.74), Vector3.new(0.24, 5.6, 0.08), SKY_GLOW)
		Style.block(decor, at * CFrame.new(0, 8.5, 0), Vector3.new(2.3, 0.6, 2.3), GOLD, FOIL, Style.tiny())
		Style.crystal(decor, at * CFrame.new(0, 9.7, 0) * CFrame.Angles(0, c * 0.4, 0), 2.0, 0.8, SKY_DEEP, nil, 0.12)
	end

	-- clouds round the podium's sides and back (the front stays open for the path)
	for c = 1, 8 do
		local a = PI * (0.38 + 1.24 * (c - 1) / 7)
		local r = 12.4 + rng:range(-0.6, 0.6)
		local p = (base * CFrame.new(math.sin(a) * r, 0.5, -math.cos(a) * r)).Position
		local size = rng:range(2.8, 3.8)
		ball(decor, p, size, Color3.new(1, 1, 1))
		ball(decor, p + Vector3.new(rng:range(-1.4, 1.4), 0.7, rng:range(-1.4, 1.4)), size * 0.7, PEARL)
	end
end

-- The lit path (see the header) from local z `from` (the island's front edge) to `to` (the podium).
local function litPath(m: Model, frame: CFrame, from: number, to: number, rng: Rng.Rng)
	local path = Style.model("SkyPath", m)
	local len = to - from
	local mid = (from + to) / 2
	local lift = SkyHaven.PathLift
	Style.block(path, frame * CFrame.new(0, 0.12 + lift, mid), Vector3.new(6, 0.24, len), WALK, nil, Style.solid())
	for _, sx in { -1, 1 } do
		Style.block(path, frame * CFrame.new(sx * 2.85, 0.28 + lift, mid), Vector3.new(0.3, 0.08, len), SKY_GLOW, NEON, Style.tiny())
	end
	local tiles = math.floor(len / 2.6)
	for i = 0, tiles - 1 do
		local z = from + (i + 0.5) * len / tiles
		Style.block(path, frame * CFrame.new(0, 0.27 + lift, z), Vector3.new(4.2, 0.06, 1.7), PEARL, nil, Style.tiny())
	end
	-- crystals at the landing
	for _, sx in { -1, 1 } do
		Style.crystalCluster(path, frame * CFrame.new(sx * 4.9, 0, from + 1.6), 2.2, SKY_BLUE, rng, { Count = 3 })
	end
	-- three sky gates
	local gates = { from + 3.4, mid, to - 2.4 }
	for g, z in gates do
		local at = frame * CFrame.new(0, 0, z)
		local h = 5.5 + 2 * g -- rising toward the egg: the egg stays framed in them from the landing
		for _, sx in { -1, 1 } do
			Style.block(path, at * CFrame.new(sx * 3.8, 0.4, 0), Vector3.new(1.5, 0.8, 1.5), GOLD, FOIL, Style.decor())
			Style.block(path, at * CFrame.new(sx * 3.8, h / 2, 0), Vector3.new(0.9, h, 0.9), PEARL, nil, Style.decor())
			Kit.glow(path, at * CFrame.new(sx * 3.8, h * 0.52, -0.47), Vector3.new(0.22, h * 0.6, 0.06), SKY_GLOW)
		end
		Style.block(path, at * CFrame.new(0, h + 0.3, 0), Vector3.new(8.9, 0.6, 0.9), GOLD, FOIL, Style.tiny())
		Kit.glow(path, at * CFrame.new(0, h - 0.04, 0), Vector3.new(6.9, 0.12, 0.3), SKY_GLOW)
		-- the top beam with its ends swept up
		Style.block(path, at * CFrame.new(0, h + 0.9, 0), Vector3.new(9.4, 0.55, 1.2), PEARL, nil, Style.tiny())
		for _, sx in { -1, 1 } do
			Style.block(
				path,
				at * CFrame.new(sx * 5.1, h + 1.15, 0) * CFrame.Angles(0, 0, sx * 0.32),
				Vector3.new(1.6, 0.5, 1.2),
				PEARL,
				nil,
				Style.tiny()
			)
		end
		-- two lanterns hanging from the beam's ends outside the posts (the opening stays clear)
		for j, sx in { -1, 1 } do
			Style.block(path, at * CFrame.new(sx * 4.95, h + 0.2, 0), Vector3.new(0.1, 0.9, 0.1), GOLD, FOIL, Style.tiny())
			local lamp = Kit.glow(path, at * CFrame.new(sx * 4.95, h - 0.65, 0), Vector3.new(0.65, 0.85, 0.65), C.LampAmber)
			if g == 2 and j == 1 then
				Style.light(lamp, C.LampAmber, 18, 1.2)
			end
		end
		if g == 1 then
			-- the SKY EGG board on the first gate, over the landing: gold letters on navy, gold lips, a cyan frame
			local signAt = at * CFrame.new(0, h + 2.6, 0)
			Style.block(path, signAt * CFrame.new(0, 0, 0.45), Vector3.new(7.6, 2.3, 0.8), NAVY_DARK, nil, Style.tiny())
			for _, sy in { -1, 1 } do
				Style.block(path, signAt * CFrame.new(0, sy * 1.2, 0.45), Vector3.new(7.8, 0.16, 0.9), GOLD, FOIL, Style.tiny())
			end
			Tech.sign(path, signAt, "SKY EGG", 6.4, 1.9, {
				Casing = false,
				Board = NAVY,
				TextColor = GOLD_TEXT,
				Frame = SKY_GLOW,
				Studs = false,
			})
		end
	end
	-- floating lights bobbing beside the path, gold and sky blue
	local lights = Style.model("FloatingLights", path)
	local pivot =
		Style.block(lights, frame * CFrame.new(0, 3.4, mid), Vector3.new(0.2, 0.2, 0.2), GOLD, nil, Style.tiny({ Transparency = 1 }))
	pivot.Name = "LightsPivot"
	for i = 1, #gates - 1 do
		local z = (gates[i] + gates[i + 1]) / 2
		for j, sx in { -1, 1 } do
			ball(
				lights,
				(frame * CFrame.new(sx * 4.6, 3.2 + 0.5 * j, z)).Position,
				0.75,
				if (i + j) % 2 == 0 then GOLD_GLOW else SKY_GLOW,
				NEON
			)
		end
	end
	spinner(lights, pivot, 0, 0.45)
end

-- Vines hanging from under the island (owner 2026-10-23: "a few vines hanging down from under
-- the big island, so it looks mega cool"): from the dirt band's rim and the first two stone
-- tiers' ledges (Kit.floatingIsland: the band ~0.97 of the island, the tiers ~0.85 and ~0.70),
-- each a zigzag of three strands with two leaves and a glowing bud at its tip. 6 parts each.
SkyHaven.Vines = 18
local BUDS = { Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 205, 70) }
local function hangingVines(decor: Model, frame: CFrame, rng: Rng.Rng)
	local w, d = SkyHaven.Size.X, SkyHaven.Size.Y
	-- { the ledge's height, its half-size share of the island, how many vines, their length }
	local ledges = { { -4.6, 0.455, 8, 18 }, { -11.4, 0.4, 6, 24 }, { -18.2, 0.33, 4, 28 } }
	local n = 0
	for l, ledge in ledges do
		local y, share, count, long = ledge[1], ledge[2], ledge[3], ledge[4]
		for v = 1, count do
			n += 1
			if n > SkyHaven.Vines then
				return
			end
			-- round the ledge's rim, spread evenly with a little jitter
			local a = (v - 1 + rng:range(-0.25, 0.25)) / count * 2 * PI + l * 0.6
			local dx, dz = math.sin(a), -math.cos(a)
			local scale = 1 / math.max(math.abs(dx), math.abs(dz))
			local at = Vector3.new(dx * scale * w * share, y, dz * scale * d * share)
			local length = long * rng:range(0.75, 1.25)
			local points = { at }
			for j = 1, 3 do
				local side = if j % 2 == 0 then 1 else -1
				table.insert(points, at + Vector3.new(side * rng:range(0.5, 1.3), -length * j / 3, side * rng:range(-0.9, 0.9)))
			end
			for j = 1, 3 do
				local a0 = (frame * CFrame.new(points[j])).Position
				local a1 = (frame * CFrame.new(points[j + 1])).Position
				local dir = (a1 - a0).Unit
				Kit.beam(
					decor,
					a0 - dir * 0.2,
					a1 + dir * 0.2,
					1.05 - j * 0.15,
					Style.vary(if j == 2 then C.LeafGreen else C.LeafGreenDark, rng, 0.06)
				)
			end
			for leaf = 1, 2 do
				local q = (frame * CFrame.new(points[leaf + 1] + Vector3.new(0, length * 0.12, 0))).Position
				Style.block(
					decor,
					CFrame.new(q) * CFrame.Angles(0, rng:range(0, PI), 0.5) * CFrame.new(0.8, 0, 0),
					Vector3.new(1.6, 0.14, 0.95),
					Style.vary(C.LeafGreenLight, rng, 0.06),
					nil,
					Style.tiny()
				)
			end
			ball(decor, (frame * CFrame.new(points[4] - Vector3.new(0, 0.4, 0))).Position, 1.0, BUDS[n % #BUDS + 1], NEON)
		end
	end
end

function SkyHaven.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("SkyHaven", parent)
	-- what you can't walk on (the rock underside, the spire, cottages, trees, columns, clouds, the
	-- waterfall): a Lod sub-model, so phones farther than the streaming radius get a proxy of it
	local decor = Style.model("SkyHavenDecor", m)
	Style.streaming(decor, "Lod")
	local center = SkyHaven.Center
	local frame = CFrame.lookAt(center, Vector3.new(center.X, center.Y, 0)) -- front (-Z local) toward the town
	local w, d = SkyHaven.Size.X, SkyHaven.Size.Y
	local rock = Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 52, Tiers = 6 })
	local under: { Instance } = {}
	for _, child in rock:GetChildren() do
		if child:IsA("BasePart") and child.CFrame.Position.Y > center.Y - 2.6 then
			child.CanCollide = true
			child.CanQuery = true
		else
			table.insert(under, child)
		end
	end
	for _, child in under do
		child.Parent = decor
	end
	parkour(m, decor, rng)
	hangingVines(decor, frame, rng)
	-- the lit path from the parkour's landing (the front edge) to the podium, a plain path past it to the village
	litPath(m, frame, -d / 2, SkyHaven.Podium - SkyHaven.PodiumReach + 0.4, rng)
	local path = Style.model("Paths", m)
	Style.block(path, frame * CFrame.new(0, 0.12 + SkyHaven.PathLift, 15.5), Vector3.new(34, 0.24, 4), C.Cobble, nil, Style.solid())
	eggPodium(m, decor, frame * CFrame.new(0, 0, SkyHaven.Podium), rng)
	-- the village: three cottages at the back, doors toward the egg
	for i, spot in
		{
			{ X = -21, Z = 21, Roof = C.RoofTerracotta },
			{ X = 0, Z = 23.5, Roof = Color3.fromRGB(80, 130, 200) },
			{ X = 21, Z = 21, Roof = C.RoofTerracotta },
		}
	do
		local base = frame * CFrame.new(spot.X, 0, spot.Z) * CFrame.Angles(0, if i == 1 then -0.35 elseif i == 3 then 0.35 else 0, 0)
		cottage(decor, base, rng, spot.Roof)
	end
	-- trees: jungle giants at the corners, blossom and green trees between
	for _, t in { { X = -26, Z = 4 }, { X = 26, Z = 5 } } do
		Meadow.jungleTree(decor, (frame * CFrame.new(t.X, 0, t.Z)).Position, 15, 5.5, rng, nil)
	end
	Style.tree(decor, frame * CFrame.new(-19, 0, -17), "Pink", rng, 1.15)
	Style.tree(decor, frame * CFrame.new(20, 0, -19), "Pink", rng, 1.05)
	Style.tree(decor, frame * CFrame.new(-28, 0, 24), "Green", rng, 1)
	-- a waterfall off the east edge, its pool over the grass cap
	Kit.box(decor, frame, Vector3.new(w / 2 - 8, 0.3, 0), Vector3.new(14, 0.3, 3), C.Water, nil, Kit.far({ Transparency = 0.15 }))
	Kit.skyFall(decor, frame * CFrame.new(w / 2 + 0.5, -0.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), 48, 5, rng)
	return m
end

return SkyHaven
