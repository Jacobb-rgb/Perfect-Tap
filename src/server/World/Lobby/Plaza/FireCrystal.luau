--[[
	The plaza's centre piece (LOBBY_PLAN 6.3.2, restyled after concept v2):
	a low, wide, stepped mechanical ring, and inside it since 2026-10-25
	THE GOLDEN DRAGON holding the TERRA FORGE sign (Plaza/GoldenStatue,
	owner: "a big golden statue of this dragon holding the TERRA FORGE
	sign", in place of the fire crystal crown).

	The ring has two tiers (Kenney pipe-ring-colored, chunky): a wide low
	dark metal base tier (walk-through) with deep-blue neon segments along
	its rim; 12 armor segments on it - an angled armor plate leaning on the
	outer face, a long narrow orange glow slit under a light metal cap lip,
	a thin blue edge on the inner lip - clamped by 12 chamfered ribs (same
	height everywhere, four with small status lights). GoldenStatue builds
	the statue's pedestal inside it into the same model.

	Hook: the ring is the Model "FireCrystalRing" (RebirthService puts the
	Star Forge prompt on it, at the pedestal's front: LobbyLayout's
	FireCrystal.PromptSpot). The piece keeps its old id "FireCrystal".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)
local GoldenStatue = require(script.Parent.GoldenStatue)

local C = Style.C
local K = Common.Colors
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local FireCrystal = {}

-- the armor ring (segments 9.0 .. 11.4 from the center), on the base tier
FireCrystal.RingRadius = 10.2
FireCrystal.RingWidth = 2.4
FireCrystal.RingHeight = 1.2 -- the armor tier over the base tier (cap lip included)
FireCrystal.BaseRadius = 12.4 -- the wide low base tier
FireCrystal.BaseHeight = 0.4
FireCrystal.Segments = 12
local RING_R = FireCrystal.RingRadius
local RING_W = FireCrystal.RingWidth
local RING_H = FireCrystal.RingHeight
local SEGMENTS = FireCrystal.Segments
local BASE_R = FireCrystal.BaseRadius
local BASE_H = FireCrystal.BaseHeight
local CAP_H = 0.2
local RING_OUT = RING_R + RING_W / 2 -- outer face of the armor segments (11.4)
local RING_IN = RING_R - RING_W / 2 -- inner face (9.0)
-- colors: the dark machine metal of the plaza kit (the armor never reads
-- lighter than the slate floor), a mid bevel on the cap lips
local RING_METAL = K.Metal
local RING_BEVEL = K.MetalLight -- the cap lips (they catch the light, the segments read)
local RING_METAL_DARK = K.MetalDark

-- Status lights on every third rib (concept v2: blue, green, blue, amber).
local STATUS = { K.NeonBlueDeep, C.LeafGreenLight, K.NeonBlueDeep, K.SlotAmber }

--[[
	The armor tier: 12 segments on the base tier, each a light machine
	metal block with an angled armor plate leaning on its outer face, a
	long narrow orange glow slit right under the overhanging light metal
	cap lip, and a thin blue edge on the inner lip; between them chamfered
	ribs (a block and a sloped buttress, all the same height) clamp the
	segments, four with a small flush status light.
]]
local function armorRing(m: Model, center: Vector3, y0: number, rng: Rng.Rng)
	local step = 2 * math.pi / SEGMENTS
	local segLen = 2 * RING_R * math.tan(math.pi / SEGMENTS) -- meets the ribs at mid radius
	local yb = y0 + BASE_H -- top of the base tier
	local bodyH = RING_H - CAP_H
	local plateH, plateD = 0.62, 0.55
	for i = 0, SEGMENTS - 1 do
		local frame = CFrame.new(center) * CFrame.Angles(0, -(i + 0.5) * step, 0) * CFrame.new(RING_R, yb, 0)
		local seg = Style.block(
			m,
			frame * CFrame.new(0, bodyH / 2, 0),
			Vector3.new(RING_W, bodyH, segLen),
			Style.vary(RING_METAL, rng, 0.03),
			nil,
			Style.solid()
		)
		seg.Name = "RingSegment"
		-- the cap lip: light metal, overhanging outward (a bevel that catches the light)
		local cap = Style.block(
			m,
			frame * CFrame.new(0.1, bodyH + CAP_H / 2, 0),
			Vector3.new(RING_W + 0.45, CAP_H, segLen - 0.1),
			RING_BEVEL,
			nil,
			Style.tiny()
		)
		cap.Name = "RingCap"
		-- the angled armor plate leaning on the outer face (tall side at the face)
		Geo.wedge(
			m,
			frame * CFrame.new(RING_W / 2 + plateD / 2, plateH / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(segLen - 0.5, plateH, plateD),
			Style.vary(RING_METAL, rng, 0.03),
			SMOOTH,
			Style.tiny()
		).Name =
			"RingArmor"
		-- one long narrow horizontal glow slit under the lip
		local slit = Style.block(
			m,
			frame * CFrame.new(RING_W / 2 + 0.03, bodyH - 0.2, 0),
			Vector3.new(0.08, 0.22, segLen * 0.74),
			C.Ember,
			NEON,
			Style.tiny()
		)
		slit.Name = "RingSlot"
		-- thin blue edge along the inner lip (faces the crystal)
		local edge = Style.block(
			m,
			frame * CFrame.new(-RING_W / 2 - 0.08, bodyH + CAP_H - 0.06, 0),
			Vector3.new(0.12, 0.1, segLen - 0.3),
			K.NeonBlueDeep,
			NEON,
			Style.tiny()
		)
		edge.Name = "RingEdgeGlow"
		-- the clamp rib between this segment and the next: a block and a chamfered buttress
		local rib = CFrame.new(center) * CFrame.Angles(0, -(i + 1) * step, 0)
		-- (round 3: the ribs end flush with the cap lips: one even ring height)
		local ribH = RING_H
		local r0, r1 = RING_IN - 0.15, RING_OUT - 0.3
		Style.block(
			m,
			rib * CFrame.new((r0 + r1) / 2, yb + ribH / 2, 0),
			Vector3.new(r1 - r0, ribH, 0.9),
			Style.vary(RING_METAL_DARK, rng, 0.03),
			nil,
			Style.solid()
		).Name =
			"RingRib"
		local bw = 0.95
		Geo.wedge(
			m,
			rib * CFrame.new(r1 + bw / 2, yb + ribH / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(0.9, ribH, bw),
			Style.vary(RING_METAL_DARK, rng, 0.03),
			SMOOTH,
			Style.tiny()
		).Name =
			"RingRib"
		if i % 3 == 1 then
			local status = Style.block(
				m,
				rib * CFrame.new((r0 + r1) / 2, yb + ribH + 0.02, 0),
				Vector3.new(0.6, 0.06, 0.5),
				STATUS[(i - 1) // 3 + 1],
				NEON,
				Style.tiny()
			)
			status.Name = "StatusLight"
		end
	end
end

--[[
	The wide low base tier (walk-through, like the curb): a dark metal disc
	the armor ring stands on, with 12 deep-blue neon segments glowing along
	its rim between the ribs (concept v2's blue base lights).
]]
local function baseTier(m: Model, center: Vector3, y0: number)
	local lip = Geo.cylinder(
		m,
		center + Vector3.new(0, y0 + BASE_H / 2, 0),
		BASE_H,
		BASE_R * 2,
		RING_METAL_DARK,
		SMOOTH,
		Style.ghost({ CastShadow = false })
	)
	lip.Name = "RingLip"
	local step = 2 * math.pi / SEGMENTS
	-- (each strip lies on the rim, its outer face just proud of the disc's edge)
	local r = BASE_R - 0.2
	local len = 2 * r * math.sin(math.pi / SEGMENTS) * 0.62
	for i = 0, SEGMENTS - 1 do
		local frame = CFrame.new(center) * CFrame.Angles(0, -(i + 0.5) * step, 0) * CFrame.new(r, y0 + BASE_H - 0.06, 0)
		local glow = Style.block(m, frame, Vector3.new(0.5, 0.16, len), K.NeonBlueDeep, NEON, Style.tiny())
		glow.Name = "LipGlow"
	end
end

function FireCrystal.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("FireCrystal")
	local center = piece.Center
	local y0 = Common.TileTop
	local m = Style.model("FireCrystalRing", parent)
	baseTier(m, center, y0)
	armorRing(m, center, y0, rng)
	GoldenStatue.build(m, parent, center, y0 + BASE_H)
end

return FireCrystal
