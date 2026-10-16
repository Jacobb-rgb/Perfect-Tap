--[[
	SPIN & WIN: the free daily wheel of fortune, the big landmark left of
	the plaza (concept v2: docs/art/lobby_concept_v2.webp). A gunmetal
	platform with stairs and orange handrails, lantern pillars on the front
	daises, a thick dark mechanical ring frame (16 blocks, blue neon inner
	edge, orange light studs) on two legs and a base housing, the wheel
	inside it (10 glowing rainbow segments with item icons and a crown hub)
	that turns slowly on the client (sub-model "Wheel", tag Spin, Atomic,
	hub Y axis = axle), a pointer, the SPIN & WIN sign box over the ring
	with a gold crown on top, and the EmberChest (tag, the free daily
	reward) at the top of the stairs.

	Hierarchy: SpinWheel { frame parts, Wheel, EmberChest, sign }.
	Local frame: 18 wide, 26 tall, 10 deep, front = -Z (toward the plaza).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Wheel = {}

local C = Kit.C

local PLATFORM_TOP = 2.4
local PLATFORM_FRONT = -2.0
local AXLE_Y = 13.0
local RING_IN, RING_OUT = 7.0, 8.75 -- mechanical ring (inner radius, outer apothem)
local RING_Z, RING_D = 2.6, 2.0 -- ring center plane and depth (front face at 1.6)
local SEGMENT_R = 6.85
local FACE_Z = 1.95 -- front face of the colored segments
local SIGN_Y, SIGN_H = 21.3, 3.0

-- Rainbow segments, clockwise from the top (concept v2). Local saturated
-- neon tints: the Style.C crystal/leaf colors bloom to pastel on a big wheel.
local rgb = Color3.fromRGB
local SEGMENTS = {
	rgb(214, 26, 40), -- red
	rgb(240, 112, 12), -- orange
	rgb(236, 192, 12), -- yellow
	rgb(132, 210, 22), -- lime
	rgb(22, 176, 72), -- green
	rgb(12, 186, 200), -- teal
	rgb(30, 100, 240), -- blue
	rgb(92, 52, 232), -- indigo
	rgb(172, 40, 230), -- purple
	rgb(232, 40, 150), -- magenta
}

-- Item icon on each segment (daily rewards: coins, crates, rare ore, gems, golem capsules).
local ICONS = { "Coin", "Crate", "Gem", "Capsule", "Ore", "Coin", "Crate", "Gem", "Capsule", "Ore" }

-- A chunky item icon in the plane of `at` (front = LookVector, up = outward).
local function icon(m: Instance, at: CFrame, kind: string)
	if kind == "Coin" then
		Tech.faceDisc(m, at, 0.3, 1.8, C.Gold)
		Tech.faceDisc(m, at * CFrame.new(0, 0, -0.12), 0.12, 1.1, C.Brass)
	elseif kind == "Crate" then
		Kit.bit(m, at, Vector3.new(1.5, 1.5, 0.5), C.WoodLight)
		Kit.bit(m, at * CFrame.new(0, 0, -0.04), Vector3.new(1.6, 0.32, 0.5), C.WoodDark)
		Kit.bit(m, at * CFrame.new(0, 0, -0.04), Vector3.new(0.32, 1.6, 0.5), C.WoodDark)
	elseif kind == "Gem" then
		Kit.bit(m, at * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(1.3, 1.3, 0.3), C.FlowerWhite)
		Kit.glow(m, at * CFrame.new(0, 0, -0.12) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.75, 0.75, 0.12), C.CrystalCyan)
	elseif kind == "Capsule" then
		Kit.bit(m, at * CFrame.new(0, 0.42, 0), Vector3.new(1.2, 0.85, 0.4), C.FlowerWhite)
		Kit.bit(m, at * CFrame.new(0, -0.42, 0), Vector3.new(1.2, 0.85, 0.4), C.AwningRed)
		Kit.bit(m, at * CFrame.new(0, 0, -0.05), Vector3.new(1.3, 0.16, 0.4), Kit.Dark)
	else -- Ore: a stone block with a glowing vein
		Kit.bit(m, at, Vector3.new(1.5, 1.4, 0.5), C.StoneLight)
		Kit.glow(m, at * CFrame.new(0.2, 0.15, -0.2) * CFrame.Angles(0, 0, 0.5), Vector3.new(0.85, 0.32, 0.12), C.CrystalPurple)
	end
end

local function buildWheel(parent: Instance, center: CFrame)
	local m = Style.model("Wheel", parent)
	local function polar(r: number, a: number, z: number): Vector3
		return (center * CFrame.new(r * math.cos(a), r * math.sin(a), z)).Position
	end
	local normal = center.LookVector
	-- dark backing disc (fills the gaps behind the segments, hidden in the ring)
	Tech.faceDisc(m, center * CFrame.new(0, 0, 0.5), 0.3, 2 * RING_IN + 0.2, Tech.MetalDeep, nil, Style.tiny({ CastShadow = true }))
	-- 10 glowing segments, each two triangles (a 20-gon)
	local n = #SEGMENTS
	local step = 2 * math.pi / n
	local start = math.pi / 2 + step / 2 -- segment 1 centered at the top
	for i = 1, n do
		local a0 = start - (i - 1) * step
		local color = SEGMENTS[i]:Lerp(Kit.Dark, 0.22)
		for h = 0, 1 do
			local a = a0 - h * step / 2
			local b = a - step / 2
			Geo.triangle(m, polar(0, 0, 0), polar(SEGMENT_R, a, 0), polar(SEGMENT_R, b, 0), 0.4, color, Kit.NEON, normal, Style.tiny())
		end
		-- divider at the segment's leading edge
		local d = center * CFrame.Angles(0, 0, a0) * CFrame.new(1.2 + (SEGMENT_R - 1.2) / 2, 0, -0.1)
		Kit.bit(m, d, Vector3.new(SEGMENT_R - 1.2, 0.3, 0.16), C.FlowerWhite)
		-- item icon in the middle of the segment (upright as it passes the top)
		local mid = a0 - step / 2
		local iconAt = center * CFrame.Angles(0, 0, mid) * CFrame.new(4.55, 0, -0.35) * CFrame.Angles(0, 0, -math.pi / 2)
		icon(m, iconAt, ICONS[i])
	end
	-- gunmetal hub with a blue neon ring and a gold crown: its Y axis is the
	-- axle, so the client turns the wheel around it
	local hubCf = center * CFrame.new(0, 0, -0.35) * CFrame.Angles(math.pi / 2, 0, 0)
	local hub = Kit.block(m, hubCf, Vector3.new(2.8, 0.7, 2.8), Tech.Metal, nil, Style.tiny({ CastShadow = true }))
	hub.Name = "Hub"
	Kit.bit(m, hubCf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(2.8, 0.68, 2.8), Tech.MetalLight)
	Tech.faceDisc(m, center * CFrame.new(0, 0, -0.05), 0.12, 3.9, Tech.Neon, Kit.NEON)
	Tech.crown(m, center * CFrame.new(0, -0.65, -0.78), 1.7, Tech.GoldGlow, { Depth = 0.25, Neon = true })
	m.PrimaryPart = hub
	m:SetAttribute("SpinSpeed", 0.6)
	m:SetAttribute("BobHeight", 0)
	m:SetAttribute("BobSpeed", 0)
	Style.streaming(m, "Atomic")
	Kit.tag(m, "Spin")
end

-- The free daily reward chest (tag EmberChest, PrimaryPart "Chest").
local function emberChest(parent: Instance, base: CFrame)
	local m = Style.model("EmberChest", parent)
	local body = Style.block(m, base * CFrame.new(0, 1.3, 0), Vector3.new(4.6, 2.6, 3), Tech.Metal, nil, Style.solid())
	body.Name = "Chest"
	Style.block(m, base * CFrame.new(0, 3.05, 0), Vector3.new(4.8, 0.9, 3.2), Tech.MetalLight, nil, Style.solid())
	Kit.bit(m, base * CFrame.new(0, 3.6, 0), Vector3.new(4.4, 0.35, 2.6), Tech.MetalDark)
	for _, x in { -1.6, 1.6 } do
		Kit.bit(m, base * CFrame.new(x, 1.95, 0), Vector3.new(0.4, 3.5, 3.3), C.Gold)
	end
	Kit.bit(m, base * CFrame.new(0, 0.25, 0), Vector3.new(4.8, 0.3, 3.2), C.Gold)
	Tech.glow(m, base * CFrame.new(0, 2.6, -1.53), Vector3.new(4.4, 0.14, 0.08), C.Fire)
	local lock = Kit.glow(m, base * CFrame.new(0, 2.5, -1.6), Vector3.new(0.9, 1, 0.3), C.Ember)
	lock.Name = "Lock"
	Style.light(lock, C.Ember, 16, 1.6)
	Style.emitter(lock, "Embers", C.Fire, 3)
	m.PrimaryPart = body
	Kit.tag(m, "EmberChest")
end

function Wheel.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("SpinWheel")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- gunmetal platform with a light lip, a neon edge and orange light studs
	local platD = 5.0 - PLATFORM_FRONT
	Style.block(
		m,
		at(0, PLATFORM_TOP / 2, PLATFORM_FRONT + platD / 2),
		Vector3.new(18, PLATFORM_TOP, platD),
		Style.vary(Tech.MetalDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, PLATFORM_TOP - 0.1, PLATFORM_FRONT + 0.2), Vector3.new(18, 0.24, 0.5), Tech.MetalLight)
	Tech.glow(m, at(0, PLATFORM_TOP - 0.32, PLATFORM_FRONT - 0.06), Vector3.new(18, 0.14, 0.1), Tech.Neon)
	for _, side in { -1, 1 } do
		Tech.studs(m, cf, Vector3.new(side * 4.4, 1.75, PLATFORM_FRONT - 0.08), Vector3.new(side * 8.4, 1.75, PLATFORM_FRONT - 0.08), 4)
	end

	-- stairs with orange handrails up the middle (stairs + stairs-handrail)
	local run = (PLATFORM_FRONT + 5.0) / 4 -- 4 steps from the front edge (z = -5) to the platform
	Tech.stairs(m, at(0, 0, -5.0), 7.0, PLATFORM_TOP / 4, run, 4, { Rails = true })

	-- front daises with dark lantern pillars (glowing slots)
	for _, side in { -1, 1 } do
		Style.block(m, at(side * 6.3, 0.6, -3.5), Vector3.new(5.4, 1.2, 3.0), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
		Tech.glow(m, at(side * 6.3, 1.1, -5.02), Vector3.new(5.2, 0.12, 0.06), C.Fire)
		Tech.lanternPillar(m, at(side * 6.6, 1.2, -3.5), 5.2, 1.3)
	end

	-- the mechanical ring frame (static) with orange light studs
	local ringCf = at(0, AXLE_Y, RING_Z)
	Tech.ring(m, ringCf, RING_IN, RING_OUT, 16, { Depth = RING_D, Studs = C.Fire, AllStuds = true })
	-- outer bolts on the diagonals (gear-like knuckles)
	for k = 0, 3 do
		local a = math.pi / 4 + k * math.pi / 2
		local knuckle = ringCf * CFrame.Angles(0, 0, a) * CFrame.new(0, RING_OUT - 0.55, -RING_D / 2 - 0.3)
		Kit.bit(m, knuckle, Vector3.new(1.3, 0.7, 0.4), Tech.MetalLight)
		Tech.glow(m, knuckle * CFrame.new(0, 0, -0.22), Vector3.new(0.7, 0.24, 0.06), Tech.Neon)
	end

	-- two legs and a base housing carry the ring
	for _, side in { -1, 1 } do
		local leg = at(side * 7.6, PLATFORM_TOP, 3.2)
		Style.block(m, leg * CFrame.new(0, 3.4, 0), Vector3.new(1.6, 6.8, 2.4), Tech.Metal, nil, Style.solid())
		Kit.bit(m, leg * CFrame.new(0, 0.3, -0.05), Vector3.new(2.0, 0.6, 2.6), Tech.MetalDark)
		Kit.bit(m, leg * CFrame.new(0, 2.0, -1.24), Vector3.new(1.6, 0.8, 0.1), Tech.Band)
		Tech.glow(m, leg * CFrame.new(0, 4.4, -1.24), Vector3.new(0.3, 2.6, 0.08), Tech.Neon)
		-- back strut from the platform to the ring's back
		Tech.bar(
			m,
			at(side * 3.2, PLATFORM_TOP, 4.2).Position,
			at(side * 2.2, AXLE_Y - 3, RING_Z + 1.0).Position,
			0.9,
			0.9,
			Tech.MetalDark,
			nil,
			Style.tiny({ CastShadow = true })
		)
	end
	local housing = at(0, PLATFORM_TOP + 1.0, 2.8)
	Style.block(m, housing, Vector3.new(7.0, 2.0, 2.4), Tech.Metal, nil, Style.solid())
	Tech.glow(m, housing * CFrame.new(0, 0.9, -1.24), Vector3.new(7.0, 0.14, 0.08), Tech.Neon)
	for _, x in { -2.2, 0, 2.2 } do
		Tech.glow(m, housing * CFrame.new(x, -0.1, -1.23), Vector3.new(1.2, 0.3, 0.06), C.Fire)
	end

	-- the wheel
	buildWheel(m, at(0, AXLE_Y, FACE_Z))

	-- pointer at the top (does not turn), hanging under the sign
	local tipY = AXLE_Y + SEGMENT_R - 1.5
	local topY = SIGN_Y - SIGN_H / 2 - 0.5
	Kit.tri(m, at(0, tipY, 1.1).Position, at(-1.0, topY, 1.1).Position, at(1.0, topY, 1.1).Position, 0.45, C.Gold, cf.LookVector)
	Tech.line(m, at(0, 0, 1.1), 0, tipY - 0.15, -1.15, topY, 0.16, -0.26, Tech.Neon)
	Tech.line(m, at(0, 0, 1.1), 0, tipY - 0.15, 1.15, topY, 0.16, -0.26, Tech.Neon)

	-- the SPIN & WIN sign box over the ring with a gold crown on top
	Tech.sign(m, at(0, SIGN_Y, 0.6), "SPIN & WIN", 14.4, SIGN_H, { TextColor = C.FireCore, Light = 18 })
	-- the crown overlaps the casing's top margin, in front of it (concept v2)
	Tech.crown(m, at(0, SIGN_Y + SIGN_H / 2 + 0.3, 0.1), 3.5, Tech.GoldGlow, { Depth = 0.6, Neon = true })

	-- the EmberChest at the top of the stairs
	emberChest(m, at(0, PLATFORM_TOP, -0.4))
end

return Wheel
