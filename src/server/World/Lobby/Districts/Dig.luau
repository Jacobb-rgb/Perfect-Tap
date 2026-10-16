--[[
	FOSSIL DIG: the artifacts and Kingdom of Kaldrum story corner east of
	the plaza. A fenced dig site with lantern posts, a sunken-looking pit
	(stone rim, dirt terrace, dark bed flush with the ground, no hole), a
	half-buried dinosaur skeleton, a small second find, tools, a sieve, a
	wheelbarrow, a canvas tent and the FOSSIL DIG sign with a bone icon at
	the entrance (which faces the plaza and the ToFossil path).

	Tag FossilDig on the model, PrimaryPart = the bed.
	Local frame: 18 wide (+X = north), 8 tall, 24 deep, front = -Z (west).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Dig = {}

local C = Kit.C

local BED_X, BED_Z = 6.6, 8.6 -- half sizes of the dark bed
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

	-- the pit: dark bed, dirt terrace, stone rim (gap at the entrance)
	local bed = Style.block(m, at(0, 0.1, 0), Vector3.new(2 * BED_X, 0.2, 2 * BED_Z), C.Dirt, nil, Style.solid())
	bed.Name = "Bed"
	for _ = 1, 5 do
		local x, z = rng:range(-BED_X + 2, BED_X - 2), rng:range(-BED_Z + 2, BED_Z - 2)
		Kit.bit(m, at(x, 0.22, z), Vector3.new(rng:range(1.6, 3), 0.06, rng:range(1.6, 3)), Style.vary(C.DirtLight, rng, 0.05))
	end
	local tx, tz = BED_X + 0.5, BED_Z + 0.5
	for _, side in { -1, 1 } do
		Style.block(m, at(side * tx, 0.2, 0), Vector3.new(1, 0.4, 2 * tz + 1), Style.vary(C.DirtDark, rng, 0.04), nil, Style.solid())
		Style.block(m, at(0, 0.2, side * tz), Vector3.new(2 * BED_X, 0.4, 1), Style.vary(C.DirtDark, rng, 0.04), nil, Style.solid())
		Kit.bit(m, at(side * tx, 0.42, side * 3), Vector3.new(0.8, 0.06, 4), C.Dirt)
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
			if i % 2 == 0 then C.FlowerWhite else C.Sand
		)
	end
	for i = 1, 5 do
		local z = 2.5 + i * 0.95
		local s = 0.75 - i * 0.09
		Kit.bit(m, at(spineX(z), 0.62 - i * 0.05, z), Vector3.new(s, s, 0.8), C.FlowerWhite)
	end
	local sx = spineX(-7.2)
	Kit.block(m, at(sx, 1.15, -7.2), Vector3.new(2.4, 1.8, 2.6), C.FlowerWhite, nil, Style.tiny({ CastShadow = true }))
	Kit.block(m, at(sx, 0.9, -9.1), Vector3.new(1.7, 1.2, 1.9), C.FlowerWhite, nil, Style.tiny({ CastShadow = true }))
	Kit.bit(m, at(sx, 0.35, -8.7), Vector3.new(1.6, 0.4, 2.8), C.Sand)
	for _, x in { -0.6, 0.6 } do
		Kit.bit(m, at(sx + x, 2.06, -7.0), Vector3.new(0.55, 0.06, 0.6), C.StoneDeep)
	end
	for i = 0, 5 do
		local z = -4.6 + i * 1.0
		local h = 3.0 - i * 0.2
		local x0 = spineX(z)
		local top = pos(x0, h, z)
		for _, side in { -1, 1 } do
			Kit.beam(m, top, pos(x0 + side * (2.2 - i * 0.1), 0.25, z + 0.35), 0.4, 0.4, C.Sand, Style.tiny({ CastShadow = true }))
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

	-- the dig crew's canvas tent and a crate of finds with a lamp
	local tent = at(-4.4, 0.2, 6.6)
	for _, side in { -1, 1 } do
		Kit.block(
			m,
			tent * CFrame.new(side * 0.85, 1.05, 0) * CFrame.Angles(0, 0, side * 0.9),
			Vector3.new(2.6, 0.15, 3.4),
			C.AwningWhite,
			nil,
			Style.ghost()
		)
		Kit.bit(m, tent * CFrame.new(0, 1.0, side * 1.6), Vector3.new(0.2, 2.0, 0.2), C.WoodDark)
	end
	Kit.bit(m, tent * CFrame.new(0, 2.05, 0), Vector3.new(0.25, 0.25, 3.7), C.WoodDark)
	Kit.crate(m, at(-1.8, 0.2, 7.4), 1.6, rng)
	Kit.glow(m, at(-1.8, 2.1, 7.4), Vector3.new(0.55, 0.6, 0.55), C.Lamp)

	-- fence (posts and two long rails per side) with lantern posts at the corners and the gate
	local postH = 3
	local function post(x: number, z: number)
		Style.block(m, at(x, postH / 2, z), Vector3.new(0.8, postH, 0.8), C.WoodDark)
	end
	local function rails(x1: number, z1: number, x2: number, z2: number)
		for _, y in { 1.05, 2.4 } do
			Kit.beam(m, pos(x1, y, z1), pos(x2, y, z2), 0.35, 0.45, C.Wood, Style.decor({ CastShadow = false }))
		end
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
	for i, c in { { -FENCE_X, -FENCE_Z }, { GATE_FROM, -FENCE_Z }, { GATE_TO, -FENCE_Z }, { FENCE_X, FENCE_Z }, { -FENCE_X, FENCE_Z } } do
		local glow = Kit.lampPost(m, at(c[1], 0, c[2]), 4.2)
		if i == 1 then
			Style.light(glow, C.Lamp, 18, 1.4)
		end
	end

	-- FOSSIL DIG sign with a bone icon, on two posts behind the front fence
	local signZ = -10.8
	for _, x in { -8.1, 0.9 } do
		Style.block(m, at(x, 3.7, signZ), Vector3.new(0.7, 7.4, 0.7), C.WoodDark)
	end
	Kit.bit(m, at(-3.6, 7.1, signZ), Vector3.new(9.6, 0.5, 0.45), C.WoodDark)
	Style.sign(m, at(-4.9, 5.7, signZ - 0.55), "FOSSIL DIG", 6.0, 2.4, { Depth = 0.4 })
	local iconBoard = at(-0.4, 5.7, signZ - 0.55)
	Style.block(m, iconBoard, Vector3.new(2.4, 2.4, 0.4), C.SignBoard)
	Style.icon(m, iconBoard * CFrame.new(0, 0, -0.4), "Bone", 2.0, C.SignText)

	m.PrimaryPart = bed
	Kit.tag(m, "FossilDig")
end

return Dig
