--[[
	FOSSIL DIG: the artifacts and Kingdom of Kaldrum story corner east of
	the plaza. A dig site inside a metal barrier fence (light posts with
	neon caps, orange round handrails) with dark lantern pillars, a
	sunken-looking pit (stone rim, a dirt terrace, a tan inner step and a
	light sand bed with darker dug patches, flush with the ground, no hole),
	a half-buried dinosaur
	skeleton (a long skull with a jaw, eye sockets and teeth), a small find,
	tools, a sieve, a wheelbarrow, a City Kit parasol over the finds, a
	bone-scanning terminal, the glowing FOSSIL DIG sign box with a bone
	icon at the entrance (which faces west, to the road) and
	the tall FOSSIL DIG back board (round 2): a wide wooden board on two
	timber posts over the back fence, 11 studs tall, facing the front (the
	hero camera and the spawn see it over the pit), with the Kingdom of
	Kaldrum story screen hung under it on the same posts.

	Lobby fix round 3: a big open dig (the piece grew to 26 x 30 and moved
	toward the plaza; every measure follows the footprint): dark soil in
	the pit, the skeleton 1.5 times as big and bone white on a low dirt
	mound, and one FOSSIL DIG header (the tall back board facing the hero
	and the plaza); the small entrance sign box is gone.

	Tag FossilDig on the model, PrimaryPart = the bed.
	Local frame: Size.X wide, 14 tall, Size.Z deep, front = -Z (turned
	south-west toward the hero camera and the spawn).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Dig = {}

local C = Kit.C

-- (round 3) dark soil with lighter dug patches and a tan inner step; the
-- bones bone white, they read on the dark soil from the hero camera
local SAND = C.DirtDark
local DUG = Color3.fromRGB(140, 100, 66)
local STEP = Color3.fromRGB(150, 112, 74)
local BONE = Color3.fromRGB(240, 232, 210)
local BONE_SHADE = Color3.fromRGB(214, 204, 178) -- every other vertebra, the jaw
Dig.SkeletonScale = 1.4

function Dig.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("FossilDig")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	local FENCE_X, FENCE_Z = piece.Size.X / 2 - 0.7, piece.Size.Z / 2 - 0.75
	local BED_X, BED_Z = FENCE_X - 1.7, FENCE_Z - 2.35 -- half sizes of the bed
	local GATE_FROM, GATE_TO = 1.4, 7.2 -- entrance gap on the front fence (local x)

	-- the pit, stepping down toward the middle so it reads as sunken: stone
	-- rim (gap at the entrance), a dirt terrace, a darker inner step and the
	-- darkest bed
	local bed = Style.block(m, at(0, 0.1, 0), Vector3.new(2 * BED_X, 0.2, 2 * BED_Z), SAND, nil, Style.solid())
	bed.Name = "Bed"
	for _ = 1, 4 do
		local x, z = rng:range(-BED_X + 2, BED_X - 2), rng:range(-BED_Z + 2, BED_Z - 2)
		Kit.bit(m, at(x, 0.22, z), Vector3.new(rng:range(1.6, 3), 0.06, rng:range(1.6, 3)), Style.vary(DUG, rng, 0.04))
	end
	local ix, iz = BED_X - 0.3, BED_Z - 0.3
	for _, side in { -1, 1 } do
		Style.block(m, at(side * ix, 0.16, 0), Vector3.new(0.6, 0.32, 2 * iz + 0.6), Style.vary(STEP, rng, 0.03), nil, Style.solid())
		Style.block(m, at(0, 0.16, side * iz), Vector3.new(2 * ix - 0.6, 0.32, 0.6), Style.vary(STEP, rng, 0.03), nil, Style.solid())
	end
	local tx, tz = BED_X + 0.5, BED_Z + 0.5
	for _, side in { -1, 1 } do
		Style.block(m, at(side * tx, 0.25, 0), Vector3.new(1, 0.5, 2 * tz + 1), Style.vary(C.Dirt, rng, 0.04), nil, Style.solid())
		Style.block(m, at(0, 0.25, side * tz), Vector3.new(2 * BED_X, 0.5, 1), Style.vary(C.Dirt, rng, 0.04), nil, Style.solid())
		Kit.bit(m, at(side * tx, 0.52, side * 3), Vector3.new(0.8, 0.06, 4), C.DirtLight)
	end
	local rx, rz = tx + 0.9, tz + 0.9
	local rimColor = Style.vary(C.StoneDark, rng, 0.03)
	for _, side in { -1, 1 } do
		Style.block(m, at(side * rx, 0.38, 0), Vector3.new(0.8, 0.75, 2 * rz + 0.8), rimColor, nil, Style.solid())
		Kit.bit(m, at(side * rx, 0.8, side * 4), Vector3.new(0.9, 0.12, 3), C.Stone)
	end
	Style.block(m, at(0, 0.38, rz), Vector3.new(2 * rx, 0.75, 0.8), rimColor, nil, Style.solid())
	-- front rim with the entrance gap (x 2.4 .. 6.2)
	Style.block(m, at((-rx + 2.4) / 2, 0.38, -rz), Vector3.new(2.4 + rx, 0.75, 0.8), rimColor, nil, Style.solid())
	Style.block(m, at((6.2 + rx) / 2, 0.38, -rz), Vector3.new(rx - 6.2, 0.75, 0.8), rimColor, nil, Style.solid())

	-- the dinosaur (round 3: 1.5 times as big, bone white, on a low dirt
	-- mound): skull at the front, spine in a gentle S, ribs, legs, tapering tail
	local k = Dig.SkeletonScale
	local y0 = 0.45 -- the mound's top
	local dz = 1.6 -- (the skull stays on the front terrace)
	Style.block(m, at(0, 0.32, dz - 0.5), Vector3.new(6.4 * k, 0.24, 15 * k), Style.vary(C.Dirt, rng, 0.04), nil, Style.solid()).Name =
		"Mound"
	local function bone(x: number, y: number, z: number): CFrame
		return at(x * k, y0 + y * k, z * k + dz)
	end
	local function bpos(x: number, y: number, z: number): Vector3
		return bone(x, y, z).Position
	end
	local function spineX(z: number): number
		return 1.0 * math.sin(z / 3.2)
	end
	for i = 0, 9 do
		local z = -5.6 + i * 0.9
		local sz = (1.15 - i * 0.02) * k
		Kit.bit(
			m,
			bone(spineX(z), 0.45, z) * CFrame.Angles(0, 0.2 * math.cos(z), 0),
			Vector3.new(sz, sz, 0.72 * k),
			if i % 2 == 0 then BONE else BONE_SHADE
		)
	end
	for i = 1, 5 do
		local z = 2.5 + i * 0.95
		local sz = (0.75 - i * 0.09) * k
		Kit.bit(m, bone(spineX(z), 0.22 - i * 0.05, z), Vector3.new(sz, sz, 0.8 * k), BONE)
	end
	-- the skull (pointing at the entrance): a cranium with a brow ridge and
	-- dark eye sockets, a long snout sloping down to the nose, a lower jaw
	-- hanging slightly open and a row of teeth
	local sx = spineX(-7.2)
	local shadow = Style.tiny({ CastShadow = true })
	Kit.block(m, bone(sx, 0.8, -6.9), Vector3.new(2.2, 1.6, 2.2) * k, BONE, nil, shadow)
	Kit.bit(m, bone(sx, 1.68, -7.55), Vector3.new(2.4, 0.4, 0.7) * k, BONE_SHADE)
	for _, x in { -0.8, 0.8 } do
		Kit.bit(m, bone(sx + x, 1.22, -7.88), Vector3.new(0.6, 0.55, 0.5) * k, C.StoneDeep)
	end
	Kit.block(m, bone(sx, 0.55, -9.15), Vector3.new(1.1, 0.7, 2.3) * k, BONE, nil, shadow)
	Tech.bevel(m, bone(sx, 1.2, -9.0), Vector3.new(1.1, 0.6, 2.0) * k, BONE)
	Kit.block(m, bone(sx, -0.08, -9.0) * CFrame.Angles(-0.1, 0, 0), Vector3.new(1.0, 0.32, 2.8) * k, BONE_SHADE, nil, shadow)
	for _, q in { { -0.42, -8.5 }, { 0.42, -8.5 }, { -0.42, -9.6 }, { 0.42, -9.6 } } do
		Kit.bit(m, bone(sx + q[1], 0.1, q[2]), Vector3.new(0.2, 0.36, 0.2) * k, BONE)
	end
	for i = 0, 5 do
		local z = -4.6 + i * 1.0
		local h = 2.6 - i * 0.2
		local x0 = spineX(z)
		local top = bpos(x0, h, z)
		for _, side in { -1, 1 } do
			Kit.beam(m, top, bpos(x0 + side * (2.2 - i * 0.1), -0.15, z + 0.35), 0.4 * k, 0.4 * k, BONE, Style.tiny({ CastShadow = true }))
		end
	end
	for _, leg in { { -3.6, -1, 3.2 }, { 2.0, 1, 3.6 } } do
		local z, dir, reach = leg[1], leg[2], leg[3]
		for _, side in { -1, 1 } do
			Kit.beam(
				m,
				bpos(spineX(z) + side * 0.6, 0.25, z),
				bpos(spineX(z) + side * reach, -0.12, z + dir * 1.4),
				0.42 * k,
				0.42 * k,
				BONE
			)
		end
	end

	-- a small second find (a little lizard skeleton) and survey stakes
	local lx, lz = -BED_X + 2.4, BED_Z - 2.2
	Kit.bit(m, at(lx, 0.4, lz - 1.4), Vector3.new(0.8, 0.6, 1.0), C.FlowerWhite)
	for i = 0, 3 do
		Kit.bit(m, at(lx + 0.25 * i, 0.32, lz - 0.6 + i * 0.6), Vector3.new(0.45, 0.4, 0.45), C.Sand)
	end
	for _, s in { { BED_X - 2.2, -BED_Z + 1.2 }, { -BED_X + 2.2, -BED_Z + 1.2 }, { BED_X - 1.8, BED_Z - 3.6 } } do
		Kit.bit(m, at(s[1], 0.85, s[2]), Vector3.new(0.18, 1.3, 0.18), C.WoodLight)
		Kit.bit(m, at(s[1] + 0.25, 1.35, s[2]), Vector3.new(0.4, 0.3, 0.06), C.AwningRed)
	end

	-- tools: a shovel stuck in the terrace and a brush by the skull
	local shovel = at(BED_X - 0.8, 0.4, BED_Z - 0.3) * CFrame.Angles(0.15, 0.4, 0.25)
	Kit.bit(m, shovel * CFrame.new(0, 1.6, 0), Vector3.new(0.25, 2.6, 0.25), C.WoodLight)
	Kit.bit(m, shovel * CFrame.new(0, 2.95, 0), Vector3.new(0.7, 0.2, 0.25), C.WoodDark)
	Kit.bit(m, shovel * CFrame.new(0, 0.1, 0), Vector3.new(0.9, 1.0, 0.15), C.IronLight)
	local brush = at(2.6, 0.3, -BED_Z + 0.6) * CFrame.Angles(0, 0.7, 0)
	Kit.bit(m, brush, Vector3.new(1.1, 0.18, 0.2), C.WoodLight)
	Kit.bit(m, brush * CFrame.new(0.65, 0, 0), Vector3.new(0.35, 0.3, 0.35), C.LeafYellow)

	-- a sieve on legs and a wheelbarrow of dirt
	local sieve = at(BED_X - 2.4, 0.2, -4.6)
	for _, side in { -1, 1 } do
		Kit.bit(m, sieve * CFrame.new(side * 1.2, 1.5, 0), Vector3.new(0.25, 0.25, 2.6), C.WoodLight)
		Kit.bit(m, sieve * CFrame.new(0, 1.5, side * 1.2), Vector3.new(2.6, 0.25, 0.25), C.WoodLight)
		local legTop = sieve * Vector3.new(side * 1.1, 1.4, 0)
		local legFoot = sieve * Vector3.new(side * 1.5, 0, 0.3)
		Kit.beam(m, legTop, legFoot, 0.2, 0.2, C.WoodDark)
	end
	Kit.block(m, sieve * CFrame.new(0, 1.5, 0), Vector3.new(2.3, 0.06, 2.3), C.StoneLight, nil, Style.tiny({ Transparency = 0.3 }))
	local barrow = at(-BED_X + 2.0, 0.2, -BED_Z + 3.0) * CFrame.Angles(0, -0.5, 0)
	Kit.block(m, barrow * CFrame.new(0, 1.0, 0), Vector3.new(1.8, 0.8, 2.4), C.Iron, nil, Style.decor())
	Kit.bit(m, barrow * CFrame.new(0, 1.5, 0), Vector3.new(1.6, 0.35, 2.1), C.Dirt)
	Kit.faceDisc(m, barrow * CFrame.new(0, 0.55, -1.5) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 1.1, C.StoneDeep)
	for _, x in { -0.7, 0.7 } do
		Kit.bit(m, barrow * CFrame.new(x, 1.0, 1.8), Vector3.new(0.2, 0.2, 1.6), C.WoodDark)
		Kit.bit(m, barrow * CFrame.new(x, 0.4, 0.8), Vector3.new(0.2, 0.8, 0.2), C.WoodDark)
	end

	-- a City Kit parasol over the crew's table, a crate of finds with a lamp
	-- and a computer-screen terminal that scans the bones
	Tech.parasol(m, at(-BED_X + 2.4, 0.2, BED_Z - 1.3), 4.6, 4.4, Tech.Band)
	Kit.crate(m, at(-BED_X + 5.0, 0.2, BED_Z - 0.5), 1.6, rng)
	Kit.glow(m, at(-BED_X + 5.0, 2.1, BED_Z - 0.5), Vector3.new(0.55, 0.6, 0.55), C.LampAmber)
	Tech.computer(m, at(-BED_X + 1.2, 0.2, 0.6), 2.2, Tech.Screen, { Bars = C.FlowerWhite })

	-- metal barrier fence: light posts with neon caps, a lower rail and an
	-- orange round handrail, dark lantern pillars at the corners and the gate
	local postH = 3
	local function post(x: number, z: number)
		Style.block(m, at(x, postH / 2, z), Vector3.new(0.6, postH, 0.6), Tech.MetalLight)
		Tech.glow(m, at(x, postH + 0.05, z), Vector3.new(0.66, 0.12, 0.66), Tech.Neon)
	end
	local function rails(x1: number, z1: number, x2: number, z2: number)
		Kit.beam(m, pos(x1, 1.05, z1), pos(x2, 1.05, z2), 0.3, 0.35, Tech.Metal, Style.decor({ CastShadow = false }))
		Tech.rod(m, pos(x1, 2.5, z1), pos(x2, 2.5, z2), 0.42, Tech.Band, nil, Style.decor({ CastShadow = false }))
	end
	rails(-FENCE_X, FENCE_Z, FENCE_X, FENCE_Z)
	rails(FENCE_X, FENCE_Z, FENCE_X, -FENCE_Z)
	rails(-FENCE_X, -FENCE_Z, -FENCE_X, FENCE_Z)
	rails(-FENCE_X, -FENCE_Z, GATE_FROM, -FENCE_Z)
	for _, x in { -FENCE_X / 3, FENCE_X / 3 } do
		post(x, FENCE_Z)
	end
	for _, z in { -FENCE_Z / 2, 0, FENCE_Z / 2 } do
		post(FENCE_X, z)
		post(-FENCE_X, z)
	end
	post(-FENCE_X / 2, -FENCE_Z)
	post(-FENCE_X, -FENCE_Z)
	post(FENCE_X, FENCE_Z)
	for _, c in { { GATE_FROM, -FENCE_Z }, { GATE_TO, -FENCE_Z }, { -FENCE_X, FENCE_Z } } do
		Tech.lanternPillar(m, at(c[1], 0, c[2]), 4.4, 1.0)
	end

	-- the tall FOSSIL DIG back board over the back fence, facing the front
	-- (the hero camera and the spawn read it over the pit): gold letters on
	-- dark wood with a dark outline on two timber posts, a bone over it, and
	-- the Kingdom of Kaldrum story screen hung under it on the same posts
	local back = at(0, 0, FENCE_Z - 0.6)
	-- (round 3: the one FOSSIL DIG header, bigger: 15 x 3.6)
	for _, dx in { -7.6, 7.6 } do
		Style.block(m, back * CFrame.new(dx, 5.6, 0.25), Vector3.new(0.9, 11.2, 0.9), C.WoodDark)
		Kit.bit(m, back * CFrame.new(dx, 11.35, 0.25), Vector3.new(1.2, 0.3, 1.2), C.Wood)
	end
	Style.sign(m, back * CFrame.new(0, 9.0, -0.25), "FOSSIL DIG", 15, 3.6, {
		Kind = "Wood",
		Depth = 0.5,
		StrokeColor = C.TextShadow,
		StrokeTransparency = 0,
	})
	Style.icon(m, back * CFrame.new(0, 11.6, -0.3), "Bone", 2.2, C.SignText)
	local story = back * CFrame.new(0, 5.2, -0.2)
	Tech.screen(m, story, 6.4, 2.4, Tech.Screen)
	-- the kingdom's name on two lines, filling most of the screen's height
	Tech.label(m, story * CFrame.new(-0.75, 0, -0.08), "KINGDOM OF\nKALDRUM", 4.4, 2.0, C.GlowText)
	Style.icon(m, story * CFrame.new(2.3, 0, -0.12), "Bone", 1.5, Tech.GoldGlow, Kit.NEON)

	m.PrimaryPart = bed
	Kit.tag(m, "FossilDig")
end

return Dig
