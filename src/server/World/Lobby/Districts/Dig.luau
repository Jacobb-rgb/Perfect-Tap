--[[
	FOSSIL DIG: the artifacts and Kingdom of Kaldrum story corner east of
	the plaza. A dig site inside a metal barrier fence (light posts with
	neon caps, orange round handrails) with dark lantern pillars, a
	sunken-looking pit (stone rim, a dirt terrace, a tan inner step and a
	light sand bed with darker dug patches, flush with the ground, no hole),
	a half-buried dinosaur
	skeleton (a long skull with a jaw, eye sockets and teeth), a small find,
	tools, a sieve, a wheelbarrow, a City Kit parasol over the finds, a
	bone-scanning terminal and two glowing FOSSIL DIG sign boxes with a bone
	icon: at the entrance (which faces the plaza and the ToFossil path) and
	over the south fence (its back, seen from the plaza, repeats the words).

	Tag FossilDig on the model, PrimaryPart = the bed.
	Local frame: 18 wide (+X = north), 8 tall, 24 deep, front = -Z (west).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Dig = {}

local C = Kit.C

local BED_X, BED_Z = 6.6, 8.6 -- half sizes of the sand bed
-- light tan sand (concept v1) with darker dug patches, a tan inner step;
-- bones in a light bone white so they keep their contrast on the sand
local SAND = Color3.fromRGB(196, 160, 110)
local DUG = Color3.fromRGB(150, 112, 72)
local STEP = Color3.fromRGB(162, 124, 82)
local BONE = Color3.fromRGB(240, 230, 204)
local FENCE_X, FENCE_Z = 8.3, 11.3
local GATE_FROM, GATE_TO = 1.4, FENCE_X -- entrance gap on the front fence (local x)

function Dig.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("FossilDig")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end

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
	-- front rim with the entrance gap (x 2.4 .. 6.8)
	Style.block(m, at((-rx + 2.4) / 2, 0.38, -rz), Vector3.new(2.4 + rx, 0.75, 0.8), rimColor, nil, Style.solid())
	Style.block(m, at((6.8 + rx) / 2, 0.38, -rz), Vector3.new(rx - 6.8, 0.75, 0.8), rimColor, nil, Style.solid())

	-- the dinosaur: skull at the front, spine in a gentle S, ribs, legs, tapering tail
	local function spineX(z: number): number
		return 1.0 * math.sin(z / 3.2)
	end
	for i = 0, 9 do
		local z = -5.6 + i * 0.9
		local s = 1.15 - i * 0.02
		Kit.bit(
			m,
			at(spineX(z), 0.85, z) * CFrame.Angles(0, 0.2 * math.cos(z), 0),
			Vector3.new(s, s, 0.72),
			if i % 2 == 0 then C.FlowerWhite else BONE
		)
	end
	for i = 1, 5 do
		local z = 2.5 + i * 0.95
		local s = 0.75 - i * 0.09
		Kit.bit(m, at(spineX(z), 0.62 - i * 0.05, z), Vector3.new(s, s, 0.8), C.FlowerWhite)
	end
	-- the skull (pointing at the entrance): a cranium with a brow ridge and
	-- dark eye sockets, a long snout sloping down to the nose, a lower jaw
	-- hanging slightly open and a row of teeth
	local sx = spineX(-7.2)
	local shadow = Style.tiny({ CastShadow = true })
	Kit.block(m, at(sx, 1.2, -6.9), Vector3.new(2.2, 1.6, 2.2), C.FlowerWhite, nil, shadow)
	Kit.bit(m, at(sx, 2.08, -7.55), Vector3.new(2.4, 0.4, 0.7), C.Sand)
	for _, x in { -0.8, 0.8 } do
		Kit.bit(m, at(sx + x, 1.62, -7.88), Vector3.new(0.6, 0.55, 0.5), C.StoneDeep)
	end
	Kit.block(m, at(sx, 0.95, -9.15), Vector3.new(1.1, 0.7, 2.3), C.FlowerWhite, nil, shadow)
	Tech.bevel(m, at(sx, 1.6, -9.0), Vector3.new(1.1, 0.6, 2.0), C.FlowerWhite)
	Kit.block(m, at(sx, 0.32, -9.0) * CFrame.Angles(-0.1, 0, 0), Vector3.new(1.0, 0.32, 2.8), C.Sand, nil, shadow)
	for _, q in { { -0.42, -8.5 }, { 0.42, -8.5 }, { -0.42, -9.6 }, { 0.42, -9.6 } } do
		Kit.bit(m, at(sx + q[1], 0.5, q[2]), Vector3.new(0.2, 0.36, 0.2), C.FlowerWhite)
	end
	for i = 0, 5 do
		local z = -4.6 + i * 1.0
		local h = 3.0 - i * 0.2
		local x0 = spineX(z)
		local top = pos(x0, h, z)
		for _, side in { -1, 1 } do
			Kit.beam(m, top, pos(x0 + side * (2.2 - i * 0.1), 0.25, z + 0.35), 0.4, 0.4, BONE, Style.tiny({ CastShadow = true }))
		end
	end
	for _, leg in { { -3.6, -1, 3.2 }, { 2.0, 1, 3.6 } } do
		local z, dz, reach = leg[1], leg[2], leg[3]
		for _, side in { -1, 1 } do
			Kit.beam(m, pos(spineX(z) + side * 0.6, 0.65, z), pos(spineX(z) + side * reach, 0.28, z + dz * 1.4), 0.42, 0.42, C.FlowerWhite)
		end
	end
	Kit.bit(m, at(spineX(2.2), 0.7, 2.2), Vector3.new(1.8, 0.7, 1.3), C.Sand)

	-- a small second find (a little lizard skeleton) and survey stakes
	local lx, lz = -4.2, 4.4
	Kit.bit(m, at(lx, 0.4, lz - 1.4), Vector3.new(0.8, 0.6, 1.0), C.FlowerWhite)
	for i = 0, 3 do
		Kit.bit(m, at(lx + 0.25 * i, 0.32, lz - 0.6 + i * 0.6), Vector3.new(0.45, 0.4, 0.45), C.Sand)
	end
	for _, s in { { 3.4, -6.2 }, { -3.4, -6.2 }, { 3.6, 3.8 } } do
		Kit.bit(m, at(s[1], 0.85, s[2]), Vector3.new(0.18, 1.3, 0.18), C.WoodLight)
		Kit.bit(m, at(s[1] + 0.25, 1.35, s[2]), Vector3.new(0.4, 0.3, 0.06), C.AwningRed)
	end

	-- tools: a shovel stuck in the terrace and a brush by the skull
	local shovel = at(5.8, 0.4, 7.6) * CFrame.Angles(0.15, 0.4, 0.25)
	Kit.bit(m, shovel * CFrame.new(0, 1.6, 0), Vector3.new(0.25, 2.6, 0.25), C.WoodLight)
	Kit.bit(m, shovel * CFrame.new(0, 2.95, 0), Vector3.new(0.7, 0.2, 0.25), C.WoodDark)
	Kit.bit(m, shovel * CFrame.new(0, 0.1, 0), Vector3.new(0.9, 1.0, 0.15), C.IronLight)
	local brush = at(2.0, 0.3, -7.6) * CFrame.Angles(0, 0.7, 0)
	Kit.bit(m, brush, Vector3.new(1.1, 0.18, 0.2), C.WoodLight)
	Kit.bit(m, brush * CFrame.new(0.65, 0, 0), Vector3.new(0.35, 0.3, 0.35), C.LeafYellow)

	-- a sieve on legs and a wheelbarrow of dirt
	local sieve = at(4.4, 0.2, -3.8)
	for _, side in { -1, 1 } do
		Kit.bit(m, sieve * CFrame.new(side * 1.2, 1.5, 0), Vector3.new(0.25, 0.25, 2.6), C.WoodLight)
		Kit.bit(m, sieve * CFrame.new(0, 1.5, side * 1.2), Vector3.new(2.6, 0.25, 0.25), C.WoodLight)
		local legTop = sieve * Vector3.new(side * 1.1, 1.4, 0)
		local legFoot = sieve * Vector3.new(side * 1.5, 0, 0.3)
		Kit.beam(m, legTop, legFoot, 0.2, 0.2, C.WoodDark)
	end
	Kit.block(m, sieve * CFrame.new(0, 1.5, 0), Vector3.new(2.3, 0.06, 2.3), C.StoneLight, nil, Style.tiny({ Transparency = 0.3 }))
	local barrow = at(-4.6, 0.2, -5.4) * CFrame.Angles(0, -0.5, 0)
	Kit.block(m, barrow * CFrame.new(0, 1.0, 0), Vector3.new(1.8, 0.8, 2.4), C.Iron, nil, Style.decor())
	Kit.bit(m, barrow * CFrame.new(0, 1.5, 0), Vector3.new(1.6, 0.35, 2.1), C.Dirt)
	Kit.faceDisc(m, barrow * CFrame.new(0, 0.55, -1.5) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 1.1, C.StoneDeep)
	for _, x in { -0.7, 0.7 } do
		Kit.bit(m, barrow * CFrame.new(x, 1.0, 1.8), Vector3.new(0.2, 0.2, 1.6), C.WoodDark)
		Kit.bit(m, barrow * CFrame.new(x, 0.4, 0.8), Vector3.new(0.2, 0.8, 0.2), C.WoodDark)
	end

	-- a City Kit parasol over the crew's table, a crate of finds with a lamp
	-- and a computer-screen terminal that scans the bones
	Tech.parasol(m, at(-4.4, 0.2, 6.6), 4.6, 4.4, Tech.Band)
	Kit.crate(m, at(-1.8, 0.2, 7.4), 1.6, rng)
	Kit.glow(m, at(-1.8, 2.1, 7.4), Vector3.new(0.55, 0.6, 0.55), C.Lamp)
	Tech.computer(m, at(-5.6, 0.2, 0.6), 2.2, Tech.Screen, { Bars = C.FlowerWhite })

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
	for _, x in { -2.9, 2.9 } do
		post(x, FENCE_Z)
	end
	for _, z in { -5.8, 0, 5.8 } do
		post(FENCE_X, z)
		post(-FENCE_X, z)
	end
	post(-3.6, -FENCE_Z)
	post(-FENCE_X, -FENCE_Z)
	post(FENCE_X, FENCE_Z)
	for _, c in { { GATE_FROM, -FENCE_Z }, { GATE_TO, -FENCE_Z }, { -FENCE_X, FENCE_Z } } do
		Tech.lanternPillar(m, at(c[1], 0, c[2]), 4.4, 1.0)
	end

	-- FOSSIL DIG sign box with a bone icon, on two posts behind the front fence
	local signZ = -11.0
	for _, x in { -7.6, -0.2 } do
		Style.block(m, at(x, 2.1, signZ + 0.6), Vector3.new(0.6, 4.2, 0.6), Tech.MetalLight)
		Tech.disc(m, at(x, 0.5, signZ + 0.6).Position, 1.0, 0.9, Tech.Band)
	end
	local _, frontIcon = Tech.sign(m, at(-3.9, 5.7, signZ), "FOSSIL DIG", 8.4, 2.0, { Icon = 2.4, IconLeft = true, Back = true })
	if frontIcon then
		Style.icon(m, frontIcon * CFrame.new(0, 0, -0.12), "Bone", 1.9, Tech.GoldGlow, Kit.NEON)
	end

	-- a second, bigger FOSSIL DIG sign box over the south fence, facing the
	-- south road and the hero camera (the concept shows the dig's board from
	-- the south); its frame turns local -Z (west) to local -X (south)
	local south = at(-8.5, 0, 5.6) * CFrame.Angles(0, math.pi / 2, 0)
	for _, dx in { -4.0, 4.0 } do
		Style.block(m, south * CFrame.new(dx, 2.15, 0.45), Vector3.new(0.6, 4.3, 0.6), Tech.MetalLight)
	end
	local _, southIcon = Tech.sign(m, south * CFrame.new(0, 5.9, 0), "FOSSIL DIG", 8.4, 2.2, {
		Icon = 2.6,
		IconLeft = true,
		Back = "FOSSIL DIG",
		BackFrame = true,
	})
	if southIcon then
		Style.icon(m, southIcon * CFrame.new(0, 0, -0.12), "Bone", 2.1, Tech.GoldGlow, Kit.NEON)
	end

	m.PrimaryPart = bed
	Kit.tag(m, "FossilDig")
end

return Dig
