--[[
	SPIN & WIN: the free daily wheel of fortune, the colorful landmark left
	of the SHOP. A stone platform, a tall timber frame, the wheel (8 colored
	segments, gold rim with bulbs, gold star hub) that turns slowly on the
	client (sub-model "Wheel", tag Spin, Atomic, hub Y axis = axle), a gold
	pointer at the top, the SPIN & WIN sign and the EmberChest (tag, the
	free daily reward) on the platform.

	Hierarchy: SpinWheel { frame parts, Wheel, EmberChest, sign }.
	Local frame: 18 wide, 26 tall, 10 deep, front = -Z (toward the plaza).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Wheel = {}

local C = Kit.C

local AXLE_Y = 15.4
local SEGMENT_R = 7.2 -- colored segments end under the rim
local RIM_R = 7.6 -- rim block centers
local FACE_Z = -0.6 -- front face of the segments

-- Segment colors, clockwise from the top (LOBBY_PLAN 6.4).
local SEGMENTS = {
	C.AwningRed,
	C.LeafOrange,
	C.LeafYellow,
	C.LeafGreen,
	C.CrystalCyan,
	C.CrystalBlue,
	C.CrystalPurple,
	C.AwningPink,
}

-- Icon on each segment: Coin, Gem, Capsule (daily rewards: coins, rare ore, golem capsules).
local ICONS = { "Coin", "Gem", "Capsule", "Coin", "Gem", "Coin", "Capsule", "Gem" }

local function buildWheel(parent: Instance, center: CFrame)
	local m = Style.model("Wheel", parent)
	local function polar(r: number, a: number, z: number): Vector3
		return (center * CFrame.new(r * math.cos(a), r * math.sin(a), z)).Position
	end
	local normal = center.LookVector
	-- dark backing disc (fills the gaps between the segments)
	Kit.faceDisc(m, center * CFrame.new(0, 0, 0.05), 0.5, 2 * RIM_R + 0.4, C.WoodDark, nil, Style.tiny({ CastShadow = true }))
	-- 8 segments, each two triangles (a 16-gon)
	local step = 2 * math.pi / 8
	local start = math.pi / 2 - step / 2 -- segment 1 centered at the top
	for i = 1, 8 do
		local a0 = start - (i - 1) * step
		for h = 0, 1 do
			local a = a0 - h * step / 2
			local b = a - step / 2
			local color = SEGMENTS[i]:Lerp(Kit.Dark, 0.5)
			Geo.triangle(
				m,
				polar(0, 0, FACE_Z),
				polar(SEGMENT_R, a, FACE_Z),
				polar(SEGMENT_R, b, FACE_Z),
				0.4,
				color,
				Kit.NEON,
				normal,
				Style.tiny()
			)
		end
		-- divider at the segment's leading edge
		local d = center * CFrame.Angles(0, 0, a0) * CFrame.new(SEGMENT_R / 2 + 0.5, 0, FACE_Z - 0.1)
		Kit.bit(m, d, Vector3.new(SEGMENT_R - 1, 0.32, 0.2), C.WoodDark)
		-- icon in the middle of the segment (upright as it passes the top)
		local mid = a0 - step / 2
		local iconAt = center * CFrame.Angles(0, 0, mid) * CFrame.new(4.7, 0, FACE_Z - 0.15) * CFrame.Angles(0, 0, -math.pi / 2)
		local kind = ICONS[i]
		if kind == "Coin" then
			Kit.faceDisc(m, iconAt, 0.2, 1.9, C.Gold)
			Kit.faceDisc(m, iconAt * CFrame.new(0, 0, -0.08), 0.12, 1.2, C.Brass)
		elseif kind == "Gem" then
			Kit.bit(m, iconAt * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(1.3, 1.3, 0.2), C.FlowerWhite)
			Kit.bit(m, iconAt * CFrame.new(0, 0, -0.08) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.7, 0.7, 0.12), C.CrystalCyan)
		else
			Kit.bit(m, iconAt * CFrame.new(0, 0.45, 0), Vector3.new(1.2, 0.9, 0.2), C.FlowerWhite)
			Kit.bit(m, iconAt * CFrame.new(0, -0.45, 0), Vector3.new(1.2, 0.9, 0.2), C.AwningRed)
		end
	end
	-- gold rim with 16 bulbs
	for k = 0, 15 do
		local a = k * 2 * math.pi / 16
		local rf = center * CFrame.Angles(0, 0, a) * CFrame.new(RIM_R, 0, -0.35)
		Kit.block(m, rf, Vector3.new(0.9, 3.05, 0.95), C.Gold, nil, Style.tiny({ CastShadow = true }))
		local bulb = center * CFrame.Angles(0, 0, a + math.pi / 16) * CFrame.new(RIM_R, 0, -0.9)
		Kit.glow(m, bulb, Vector3.new(0.55, 0.55, 0.3), C.Lamp)
	end
	-- gold star hub: its Y axis is the axle, so the client turns the wheel around it
	local hubCf = center * CFrame.new(0, 0, FACE_Z - 0.35) * CFrame.Angles(math.pi / 2, 0, 0)
	local hub = Kit.block(m, hubCf, Vector3.new(2.6, 0.8, 2.6), C.Gold, nil, Style.tiny({ CastShadow = true }))
	hub.Name = "Hub"
	Kit.bit(m, hubCf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(2.6, 0.78, 2.6), C.Gold)
	Kit.bit(m, hubCf * CFrame.new(0, -0.3, 0), Vector3.new(1.2, 0.5, 1.2), C.Iron)
	Kit.glow(m, hubCf * CFrame.new(0, -0.55, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.6, 0.12, 0.6), C.Fire)
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
	local body = Style.block(m, base * CFrame.new(0, 1.3, 0), Vector3.new(4.6, 2.6, 3), C.Wood, nil, Style.solid())
	body.Name = "Chest"
	Style.block(m, base * CFrame.new(0, 3.05, 0), Vector3.new(4.8, 0.9, 3.2), C.WoodDark, nil, Style.solid())
	Kit.bit(m, base * CFrame.new(0, 3.6, 0), Vector3.new(4.4, 0.35, 2.6), C.WoodDark)
	for _, x in { -1.6, 1.6 } do
		Kit.bit(m, base * CFrame.new(x, 1.95, 0), Vector3.new(0.4, 3.5, 3.3), C.Gold)
	end
	Kit.bit(m, base * CFrame.new(0, 0.25, 0), Vector3.new(4.8, 0.3, 3.2), C.Gold)
	local lock = Kit.glow(m, base * CFrame.new(0, 2.5, -1.6), Vector3.new(0.9, 1, 0.3), C.Ember)
	lock.Name = "Lock"
	Style.light(lock, C.Ember, 14, 1.5)
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

	-- stone platform with a step
	Style.block(m, at(0, 0.3, 0), Vector3.new(18, 0.6, 10), Style.vary(C.StoneDark, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, 0.9, 0.4), Vector3.new(16.4, 0.6, 8.6), Style.vary(C.Stone, rng, 0.03), nil, Style.solid())
	local floor = 1.2

	-- timber frame: two tall posts, top beam, axle beam, knee braces, back strut
	local postZ = 2.4
	for _, side in { -1, 1 } do
		Style.block(m, at(side * 8.2, floor + 11.2, postZ), Vector3.new(1.2, 22.4, 1.2), Style.vary(C.WoodDark, rng, 0.03))
		Kit.beam(m, at(side * 8.2, 19.2, postZ).Position, at(side * 4.4, 23.0, postZ).Position, 0.8, 0.8, C.Wood)
		Kit.beam(m, at(side * 8.2, 4.6, postZ).Position, at(side * 3.4, floor, postZ + 1.6).Position, 0.8, 0.8, C.Wood)
		-- lantern caps on the posts
		Kit.glow(m, at(side * 8.2, 24.45, postZ), Vector3.new(1.0, 0.9, 1.0), C.Lamp)
		Kit.bit(m, at(side * 8.2, 25.05, postZ), Vector3.new(1.5, 0.3, 1.5), C.Iron)
	end
	Style.block(m, at(0, 23.6, postZ), Vector3.new(17.6, 1.2, 1.4), C.WoodDark)
	Style.block(m, at(0, AXLE_Y, postZ - 1.0), Vector3.new(15.2, 1.0, 1.0), C.Wood)
	Kit.bit(m, at(0, AXLE_Y, 0.85), Vector3.new(1.2, 1.2, 1.9), C.Iron)
	Kit.beam(m, at(0, AXLE_Y - 0.5, postZ - 0.6).Position, at(0, floor, 4.1).Position, 1.0, 1.0, C.WoodDark, Style.decor())

	-- the wheel
	buildWheel(m, at(0, AXLE_Y, 0))

	-- gold pointer at the top (does not turn), hung from a bracket above the rim
	Style.block(m, at(0, 24.6, 0.1), Vector3.new(1.0, 0.8, 3.2), C.WoodDark)
	local tip = AXLE_Y + RIM_R - 0.6
	local top = 24.2
	Kit.tri(m, at(0, tip, -1.25).Position, at(-1.0, top, -1.25).Position, at(1.0, top, -1.25).Position, 0.5, C.Gold, cf.LookVector)
	Kit.glow(m, at(0, top - 0.55, -1.55), Vector3.new(0.45, 0.45, 0.2), C.AwningRed)

	-- SPIN & WIN sign under the wheel, on a deep crossbar between the posts
	Style.block(m, at(0, 5.6, 1.0), Vector3.new(15.2, 0.8, 2.6), C.Wood)
	Style.sign(m, at(0, 5.6, -0.6), "SPIN & WIN", 12, 3, { Kind = "Wood", TextColor = C.FireCore })
	-- glowing bulbs along the sign's top edge (concept: lit marquee)
	for k = -2, 2 do
		Kit.glow(m, at(k * 2.6, 7.28, -1.0), Vector3.new(0.45, 0.45, 0.3), C.Lamp)
	end

	-- the EmberChest on the platform in front of the sign
	emberChest(m, at(0, floor, -2.7))

	-- pillar lanterns at the platform's front corners (glow only)
	for _, side in { -1, 1 } do
		Style.lantern(m, at(side * 7.4, floor, -3.6), { Kind = "Pillar", Height = 3 })
	end
end

return Wheel
