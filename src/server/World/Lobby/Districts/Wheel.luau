--[[
	SPIN & WIN: the free daily wheel of fortune, the big landmark left of
	the plaza (concept v2: docs/art/lobby_concept_v2.webp). A gunmetal
	platform with stairs and orange handrails, lantern pillars on the front
	daises, a thick dark mechanical ring frame (16 blocks, a thick blue neon
	inner edge, a blue neon outer rim, orange light studs) on two legs and a
	base housing, the wheel inside it (10 glowing rainbow segments with item
	icons and a crown hub) that turns slowly on the client (sub-model
	"Wheel", tag Spin, Atomic, hub Y axis = axle), a pointer, the SPIN & WIN
	sign box over the ring (orange words, a blue "&") with a gold crown on
	top, and the EmberChest (tag, the free daily reward) at the top of the
	stairs. The back is finished too: a cover plate with a neon rim, studs
	and the words behind the ring.

	The whole frame scales with the LobbyLayout footprint (S = 1 for the
	18 x 26 x 10 piece, ~1.4 for a 26 x 36 x 12 one); the EmberChest keeps
	its size.

	Hierarchy: SpinWheel { frame parts, Wheel, EmberChest, sign }.
	Local frame: front = -Z (toward the plaza).
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

-- The frame's proportions at S = 1 (the 18 x 26 x 10 footprint).
type Dims = {
	S: number,
	PlatformTop: number,
	PlatformFront: number,
	AxleY: number,
	RingIn: number,
	RingOut: number,
	RingZ: number,
	RingD: number,
	SegmentR: number,
	FaceZ: number,
	SignY: number,
	SignH: number,
}

local function dims(size: Vector3): Dims
	local s = math.clamp(math.min(size.X / 18, size.Y / 26), 1, 1.6)
	local hd = size.Z / 2
	local ringD = 2.0 * s
	local ringZ = hd - 2.4 * s
	return {
		S = s,
		PlatformTop = 2.4 * s,
		PlatformFront = -hd + 3.0 * s,
		AxleY = 13.0 * s,
		RingIn = 7.0 * s,
		RingOut = 8.75 * s,
		RingZ = ringZ,
		RingD = ringD,
		SegmentR = 6.85 * s,
		FaceZ = ringZ - 0.65 * s,
		SignY = 21.0 * s,
		SignH = 3.0 * s,
	}
end

-- A chunky item icon in the plane of `at` (front = LookVector, up = outward).
local function icon(m: Instance, at: CFrame, kind: string, s: number)
	if kind == "Coin" then
		Tech.faceDisc(m, at, 0.3 * s, 1.8 * s, C.Gold)
		Tech.faceDisc(m, at * CFrame.new(0, 0, -0.12 * s), 0.12 * s, 1.1 * s, C.Brass)
	elseif kind == "Crate" then
		Kit.bit(m, at, Vector3.new(1.5, 1.5, 0.5) * s, C.WoodLight)
		Kit.bit(m, at * CFrame.new(0, 0, -0.04 * s), Vector3.new(1.6, 0.32, 0.5) * s, C.WoodDark)
		Kit.bit(m, at * CFrame.new(0, 0, -0.04 * s), Vector3.new(0.32, 1.6, 0.5) * s, C.WoodDark)
	elseif kind == "Gem" then
		Kit.bit(m, at * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(1.3, 1.3, 0.3) * s, C.FlowerWhite)
		Kit.glow(m, at * CFrame.new(0, 0, -0.12 * s) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.75, 0.75, 0.12) * s, C.CrystalCyan)
	elseif kind == "Capsule" then
		Kit.bit(m, at * CFrame.new(0, 0.42 * s, 0), Vector3.new(1.2, 0.85, 0.4) * s, C.FlowerWhite)
		Kit.bit(m, at * CFrame.new(0, -0.42 * s, 0), Vector3.new(1.2, 0.85, 0.4) * s, C.AwningRed)
		Kit.bit(m, at * CFrame.new(0, 0, -0.05 * s), Vector3.new(1.3, 0.16, 0.4) * s, Kit.Dark)
	else -- Ore: a stone block with a glowing vein
		Kit.bit(m, at, Vector3.new(1.5, 1.4, 0.5) * s, C.StoneLight)
		Kit.glow(
			m,
			at * CFrame.new(0.2 * s, 0.15 * s, -0.2 * s) * CFrame.Angles(0, 0, 0.5),
			Vector3.new(0.85, 0.32, 0.12) * s,
			C.CrystalPurple
		)
	end
end

local function buildWheel(parent: Instance, center: CFrame, d: Dims)
	local s = d.S
	local m = Style.model("Wheel", parent)
	local function polar(r: number, a: number, z: number): Vector3
		return (center * CFrame.new(r * math.cos(a), r * math.sin(a), z)).Position
	end
	local normal = center.LookVector
	-- dark backing disc (fills the gaps behind the segments, hidden in the ring)
	Tech.faceDisc(
		m,
		center * CFrame.new(0, 0, 0.5 * s),
		0.3 * s,
		2 * d.RingIn + 0.2,
		Tech.MetalDeep,
		nil,
		Style.tiny({ CastShadow = true })
	)
	-- 10 glowing segments, each two triangles (a 20-gon)
	local n = #SEGMENTS
	local step = 2 * math.pi / n
	local start = math.pi / 2 + step / 2 -- segment 1 centered at the top
	local r = d.SegmentR
	for i = 1, n do
		local a0 = start - (i - 1) * step
		local color = SEGMENTS[i]:Lerp(Kit.Dark, 0.22)
		for h = 0, 1 do
			local a = a0 - h * step / 2
			local b = a - step / 2
			Geo.triangle(m, polar(0, 0, 0), polar(r, a, 0), polar(r, b, 0), 0.4 * s, color, Kit.NEON, normal, Style.tiny())
		end
		-- divider at the segment's leading edge
		local div = center * CFrame.Angles(0, 0, a0) * CFrame.new(1.2 * s + (r - 1.2 * s) / 2, 0, -0.1 * s)
		Kit.bit(m, div, Vector3.new(r - 1.2 * s, 0.3 * s, 0.16 * s), C.FlowerWhite)
		-- item icon in the middle of the segment (upright as it passes the top)
		local mid = a0 - step / 2
		local iconAt = center * CFrame.Angles(0, 0, mid) * CFrame.new(4.55 * s, 0, -0.35 * s) * CFrame.Angles(0, 0, -math.pi / 2)
		icon(m, iconAt, ICONS[i], s)
	end
	-- gunmetal hub with a blue neon ring and a thick gold crown: its Y axis
	-- is the axle, so the client turns the wheel around it
	local hubCf = center * CFrame.new(0, 0, -0.35 * s) * CFrame.Angles(math.pi / 2, 0, 0)
	local hub = Kit.block(m, hubCf, Vector3.new(2.8, 0.7, 2.8) * s, Tech.Metal, nil, Style.tiny({ CastShadow = true }))
	hub.Name = "Hub"
	Kit.bit(m, hubCf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(2.8, 0.68, 2.8) * s, Tech.MetalLight)
	Tech.faceDisc(m, center * CFrame.new(0, 0, -0.05 * s), 0.12 * s, 3.9 * s, Tech.Tube, Kit.NEON)
	Tech.crown(m, center * CFrame.new(0, -0.75 * s, -0.95 * s), 1.75 * s, Tech.GoldGlow, { Depth = 0.55 * s, Neon = true })
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
	Tech.glow(m, base * CFrame.new(0, 2.6, -1.55), Vector3.new(4.4, 0.22, 0.1), C.Fire)
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
	local d = dims(piece.Size)
	local s = d.S
	local hw, hd = piece.Size.X / 2, piece.Size.Z / 2
	local top, front = d.PlatformTop, d.PlatformFront

	-- gunmetal platform with a light lip, a thick neon edge and orange light studs
	local platD = hd - front
	Style.block(
		m,
		at(0, top / 2, front + platD / 2),
		Vector3.new(2 * hw, top, platD),
		Style.vary(Tech.MetalDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, top - 0.1, front + 0.2), Vector3.new(2 * hw, 0.24, 0.5), Tech.MetalLight)
	Tech.glow(m, at(0, top - 0.4, front - 0.1), Vector3.new(2 * hw, 0.3, 0.16), Tech.Tube)
	for _, side in { -1, 1 } do
		Tech.studs(
			m,
			cf,
			Vector3.new(side * 4.4 * s, top * 0.72, front - 0.08),
			Vector3.new(side * (hw - 0.6), top * 0.72, front - 0.08),
			4,
			0.4 * s
		)
	end

	-- stairs with orange handrails up the middle (stairs + stairs-handrail)
	local run = (front + hd) / 4 -- 4 steps from the front edge to the platform
	Tech.stairs(m, at(0, 0, -hd), 7.0 * s, top / 4, run, 4, { Rails = true })

	-- front daises with dark lantern pillars (glowing slots)
	local daisD = front + hd
	for _, side in { -1, 1 } do
		local dx = side * 6.3 * s
		Style.block(
			m,
			at(dx, 0.6 * s, -hd + daisD / 2),
			Vector3.new(5.4 * s, 1.2 * s, daisD),
			Style.vary(Tech.Metal, rng, 0.03),
			nil,
			Style.solid()
		)
		Tech.glow(m, at(dx, 1.1 * s, -hd - 0.04), Vector3.new(5.2 * s, 0.22, 0.1), C.Fire)
		Tech.lanternPillar(m, at(side * 6.6 * s, 1.2 * s, -hd + daisD / 2), 5.2 * s, 1.3 * s)
	end

	-- the mechanical ring frame (static) with orange light studs
	local ringCf = at(0, d.AxleY, d.RingZ)
	Tech.ring(m, ringCf, d.RingIn, d.RingOut, 16, { Depth = d.RingD, Studs = C.Fire, AllStuds = true, Tube = 0.42 * s })
	-- outer bolts on the diagonals (gear-like knuckles)
	for k = 0, 3 do
		local a = math.pi / 4 + k * math.pi / 2
		local knuckle = ringCf * CFrame.Angles(0, 0, a) * CFrame.new(0, d.RingOut - 0.55 * s, -d.RingD / 2 - 0.3 * s)
		Kit.bit(m, knuckle, Vector3.new(1.3, 0.7, 0.4) * s, Tech.MetalLight)
		Tech.glow(m, knuckle * CFrame.new(0, 0, -0.22 * s), Vector3.new(0.7 * s, 0.3 * s, 0.08), Tech.Tube)
	end
	-- the back: a blue neon rim disc just behind the ring (it shows as a thin
	-- glowing outer rim from the front too), a cover plate with orange studs
	-- and a hub cap
	local back = d.RingZ + d.RingD / 2
	Tech.faceDisc(m, at(0, d.AxleY, back + 0.06), 0.12, 2 * d.RingOut + 0.5 * s, Tech.Tube, Kit.NEON)
	Tech.faceDisc(m, at(0, d.AxleY, back + 0.2), 0.16, 2 * d.RingOut - 0.7 * s, Tech.MetalDark, nil, Style.tiny({ CastShadow = true }))
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local rr = d.RingIn + 0.5 * s
		Tech.glow(m, at(rr * math.cos(a), d.AxleY + rr * math.sin(a), back + 0.32), Vector3.new(0.6 * s, 0.6 * s, 0.1), Tech.Warm)
	end
	Tech.faceDisc(m, at(0, d.AxleY, back + 0.4), 0.3, 3.2 * s, Tech.MetalLight)
	-- the words on the back cover (seen from the sea side), in a light frame
	local backSign = at(0, d.AxleY + d.RingIn * 0.45, back + 0.36)
	Kit.bit(m, backSign, Vector3.new(9.6 * s, 2.6 * s, 0.12), Tech.MetalLight)
	Tech.label(m, backSign * CFrame.new(0, 0, 0.12) * CFrame.Angles(0, math.pi, 0), "SPIN & WIN", 9.0 * s, 2.0 * s, C.FireCore)

	-- two legs and a base housing carry the ring
	for _, side in { -1, 1 } do
		local leg = at(side * 7.6 * s, top, d.RingZ + 0.6 * s)
		Style.block(m, leg * CFrame.new(0, 3.4 * s, 0), Vector3.new(1.6, 6.8, 2.4) * s, Tech.Metal, nil, Style.solid())
		Kit.bit(m, leg * CFrame.new(0, 0.3 * s, -0.05), Vector3.new(2.0 * s, 0.6 * s, 2.6 * s), Tech.MetalDark)
		Kit.bit(m, leg * CFrame.new(0, 2.0 * s, -1.24 * s), Vector3.new(1.6 * s, 0.8 * s, 0.1), Tech.Band)
		Tech.glow(m, leg * CFrame.new(0, 4.4 * s, -1.26 * s), Vector3.new(0.36, 2.6 * s, 0.12), Tech.Tube)
		-- back strut from the platform to the ring's back
		Tech.bar(
			m,
			at(side * 3.2 * s, top, d.RingZ + 1.6 * s).Position,
			at(side * 2.2 * s, d.AxleY - 3 * s, d.RingZ + 0.4 * s).Position,
			0.9 * s,
			0.9 * s,
			Tech.MetalDark,
			nil,
			Style.tiny({ CastShadow = true })
		)
	end
	local housing = at(0, top + 1.0 * s, d.RingZ + 0.2 * s)
	Style.block(m, housing, Vector3.new(7.0, 2.0, 2.4) * s, Tech.Metal, nil, Style.solid())
	Tech.glow(m, housing * CFrame.new(0, 0.9 * s, -1.24 * s), Vector3.new(7.0 * s, 0.24, 0.1), Tech.Tube)
	for _, x in { -2.2, 0, 2.2 } do
		Tech.glow(m, housing * CFrame.new(x * s, -0.1 * s, -1.23 * s), Vector3.new(1.2 * s, 0.3 * s, 0.06), C.Fire)
	end

	-- the wheel
	buildWheel(m, at(0, d.AxleY, d.FaceZ), d)

	-- pointer at the top (does not turn), hanging under the sign
	local tipY = d.AxleY + d.SegmentR - 1.5 * s
	local topY = d.SignY - d.SignH / 2 - 0.5 * s
	local pz = d.FaceZ - 0.85 * s
	Kit.tri(m, at(0, tipY, pz).Position, at(-1.0 * s, topY, pz).Position, at(1.0 * s, topY, pz).Position, 0.45 * s, C.Gold, cf.LookVector)
	Tech.line(m, at(0, 0, pz), 0, tipY - 0.15, -1.15 * s, topY, 0.22, -0.26, Tech.Tube)
	Tech.line(m, at(0, 0, pz), 0, tipY - 0.15, 1.15 * s, topY, 0.22, -0.26, Tech.Tube)

	-- the SPIN & WIN sign box over the ring: orange words, a blue "&" between
	-- them (concept v2), a gold crown on top
	local sh = d.SignH
	Tech.sign(m, at(0, d.SignY, d.RingZ - 2.0 * s), "SPIN & WIN", 14.8 * s, sh, {
		TextColor = C.FireCore,
		Words = {
			{ Text = "SPIN", Width = 6.0 * s },
			{ Text = "&", Width = 2.2 * s, Color = C.GlowEdge },
			{ Text = "WIN", Width = 5.6 * s },
		},
		Light = 18,
	})
	-- the crown overlaps the casing's top margin, in front of it (concept v2)
	Tech.crown(m, at(0, d.SignY + sh / 2 + 0.3 * s, d.RingZ - 2.5 * s), 3.2 * s, Tech.GoldGlow, { Depth = 0.7 * s, Neon = true })

	-- the EmberChest at the top of the stairs
	emberChest(m, at(0, top, front + 1.6))
end

return Wheel
