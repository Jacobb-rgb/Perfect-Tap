--[[
	The giant fire crystal in the middle of the plaza (LOBBY_PLAN 6.3.2,
	restyled after concept v2): a chunky two-tier mechanical ring - 16 dark
	metal housing segments with dark cap plates, big orange glowing slots on
	their outer faces, a thin blue neon outer top edge and orange glows
	facing the crystal, clamped by taller dark ribs with small blue / green /
	amber status lights, and round it a low stepped outer lip with a blue
	neon line at its foot - around a glowing ember bed, a stepped octagonal
	metal base with a blue neon rim and a glowing fire bed, an octagonal
	pedestal with an Ember seam, and the crystal cluster on top. The cluster
	is kept short (tip under y 11 with the bob), so from the spawn the
	Great Forge's raised, glowing doorway shows beside and above it.

	Hook: the crystal cluster is the Model "FireCrystal", tagged Spin
	(SpinSpeed 0.25, BobHeight 0.5, BobSpeed 0.9), streamed Atomic, its
	PrimaryPart the main crystal body (Y axis = the spin axis). The one
	PointLight sits on the main body.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local K = Common.Colors
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local FireCrystal = {}

FireCrystal.SpinSpeed = 0.25
FireCrystal.BobHeight = 0.5
FireCrystal.BobSpeed = 0.9

-- the mechanical housing ring (segments 8.8 .. 11.6 from the center)
FireCrystal.RingRadius = 10.2
FireCrystal.RingWidth = 2.8
FireCrystal.RingHeight = 2.0
FireCrystal.LipRadius = 12.1 -- the low outer step (r 11.6 .. 12.6)
FireCrystal.CrystalHeight = 7.5
FireCrystal.Segments = 16
local RING_R = FireCrystal.RingRadius
local RING_W = FireCrystal.RingWidth
local RING_H = FireCrystal.RingHeight
local SEGMENTS = FireCrystal.Segments
local MOAT_R = 8.9 -- the glowing ember bed inside the housing
local INNER = 10.4 -- side of the star base blocks (points reach r 7.35)
-- low base and a short cluster: the crystal tip stays under y 11 (with the
-- bob), so from the spawn the forge's raised doorway, its banners and THE
-- GREAT FORGE board all read above and beside it
local INNER_H = 0.8
local PEDESTAL = 6.6
local PEDESTAL_H = 1.0
local CRYSTAL_H = FireCrystal.CrystalHeight
local CRYSTAL_W = 3.0
local SIDE_SCALE = 0.75 -- the leaning side crystals

-- Two square slabs turned 45 degrees to each other (an 8-point star).
local function star(
	parent: Instance,
	cf: CFrame,
	side: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }?
): { Part }
	local p = props or Style.solid()
	return {
		Style.block(parent, cf, Vector3.new(side, height, side), color, material or SMOOTH, p),
		Style.block(parent, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(side, height, side), color, material or SMOOTH, p),
	}
end

--[[
	The main crystal: a see-through orange shell (Transparency 0.3, so its
	facets catch the sun and the lamps) around a slim neon core, so the
	crystal reads as a faceted gem that glows from within instead of a flat
	neon blob. Returns the core body (the spin pivot).
]]
local function mainCrystal(parent: Instance, base: CFrame): BasePart
	local shell = Style.crystal(parent, base, CRYSTAL_H, CRYSTAL_W, C.Fire, C.LeafOrange)
	for i, part in shell do
		part.Material = SMOOTH
		part.Transparency = if i == 1 then 0.3 else 0.22
		part.Name = "CrystalShell"
	end
	local core = Style.crystal(parent, base * CFrame.new(0, 0.4, 0), CRYSTAL_H * 0.86, CRYSTAL_W * 0.46, C.Fire, C.FireCore)
	core[1].Name = "CrystalBody"
	return core[1]
end

local function crystalCluster(parent: Instance, base: CFrame, rng: Rng.Rng): Model
	local m = Style.model("FireCrystal", parent)
	local body = mainCrystal(m, base)
	-- leaning side crystals (deep Ember glow, Fire tips) and small shards
	local sides = {
		{ A = 25, H = 7.2, Lean = 0.38, Color = C.Ember },
		{ A = 115, H = 5.6, Lean = 0.46, Color = C.Ember },
		{ A = 205, H = 6.6, Lean = 0.4, Color = C.Ember },
		{ A = 295, H = 5.2, Lean = 0.5, Color = C.Ember },
		{ A = 70, H = 3.4, Lean = 0.7, Color = C.Fire },
		{ A = 160, H = 3.0, Lean = 0.75, Color = C.Ember },
		{ A = 250, H = 3.6, Lean = 0.65, Color = C.Fire },
	}
	for i, s in sides do
		local a = math.rad(s.A + rng:range(-6, 6))
		local foot = base * CFrame.new(math.cos(a) * 1.4, 0.1, math.sin(a) * 1.4)
		local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -s.Lean) * CFrame.Angles(0, a, 0)
		local h = s.H * SIDE_SCALE
		local parts = Style.crystal(m, foot * tilt, h, h * 0.3, s.Color, C.Fire)
		if i <= 4 then
			-- the big side crystals: shaded amber bodies (facets read), glowing tips
			parts[1].Material = SMOOTH
			parts[1].Color = if i % 2 == 0 then C.LeafOrange else C.Fire
			parts[1].Transparency = 0.12
		end
	end
	m.PrimaryPart = body
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", FireCrystal.SpinSpeed)
	m:SetAttribute("BobHeight", FireCrystal.BobHeight)
	m:SetAttribute("BobSpeed", FireCrystal.BobSpeed)
	Style.streaming(m, "Atomic")
	Style.light(body, C.Fire, 40, 2.2)
	Style.emitter(body, "Sparkle", C.FireCore, 3)
	return m
end

-- Status light colors on every fourth rib (concept v2: blue, green, orange).
local STATUS = { K.NeonBlue, C.LeafGreenLight, K.NeonBlue, C.FireCore }

--[[
	The chunky mechanical housing (concept v2, Kenney pipe-ring-colored):
	16 dark metal segments, each with an inset dark cap plate, a thin blue
	neon strip on the outer top edge, a big orange glowing slot on the outer
	face and (every other one) an orange glow facing the crystal; between
	them taller dark clamp ribs with dark bolt caps or small status lights.
	Dark metal and orange dominate; blue is only a thin accent line.
]]
local function housing(m: Model, center: Vector3, y0: number, rng: Rng.Rng)
	local step = 2 * math.pi / SEGMENTS
	local segLen = 2 * math.pi * RING_R / SEGMENTS * 0.8
	for i = 0, SEGMENTS - 1 do
		local frame = CFrame.new(center) * CFrame.Angles(0, -(i + 0.5) * step, 0) * CFrame.new(RING_R, y0, 0)
		local seg = Style.block(
			m,
			frame * CFrame.new(0, RING_H / 2, 0),
			Vector3.new(RING_W, RING_H, segLen),
			Style.vary(K.Metal, rng, 0.04),
			nil,
			Style.solid()
		)
		seg.Name = "RingSegment"
		Style.block(
			m,
			frame * CFrame.new(-0.15, RING_H + 0.08, 0),
			Vector3.new(RING_W - 0.8, 0.16, segLen - 0.5),
			Style.vary(K.MetalDark, rng, 0.04),
			nil,
			Style.tiny()
		)
		local edge = Style.block(
			m,
			frame * CFrame.new(RING_W / 2 - 0.07, RING_H - 0.03, 0),
			Vector3.new(0.14, 0.12, segLen + 0.02),
			K.NeonBlue,
			NEON,
			Style.tiny()
		)
		edge.Name = "RingEdgeGlow"
		local slot = Style.block(
			m,
			frame * CFrame.new(RING_W / 2 + 0.02, RING_H * 0.45, 0),
			Vector3.new(0.12, 0.8, segLen * 0.75),
			K.NeonOrange,
			NEON,
			Style.tiny()
		)
		slot.Name = "RingSlot"
		if i % 2 == 0 then
			Style.block(
				m,
				frame * CFrame.new(-RING_W / 2 - 0.02, RING_H * 0.55, 0),
				Vector3.new(0.12, 0.6, segLen * 0.5),
				C.Fire,
				NEON,
				Style.tiny()
			)
		end
		-- clamp rib between this segment and the next
		local rib = CFrame.new(center) * CFrame.Angles(0, -(i + 1) * step, 0) * CFrame.new(RING_R + 0.1, y0, 0)
		local ribH = RING_H + 0.5
		Style.block(
			m,
			rib * CFrame.new(0, ribH / 2, 0),
			Vector3.new(RING_W + 0.5, ribH, 0.95),
			Style.vary(K.MetalDark, rng, 0.04),
			nil,
			Style.solid()
		)
		if i % 4 == 1 then
			local status = Style.block(
				m,
				rib * CFrame.new(0.9, ribH + 0.1, 0),
				Vector3.new(0.4, 0.2, 0.4),
				STATUS[(i - 1) // 4 + 1],
				NEON,
				Style.tiny()
			)
			status.Name = "StatusLight"
		else
			Style.block(m, rib * CFrame.new(0, ribH + 0.08, 0), Vector3.new(RING_W - 0.2, 0.16, 0.7), K.Metal, nil, Style.tiny())
		end
	end
end

--[[
	The low stepped outer lip of the two-tier ring (concept v2): a dark
	metal disc step (r 12.6, 0.4 high, walk-through like the curb) right
	round the housing, with a blue neon line glowing at its foot (the rim
	of a slightly larger neon disc under it). 2 parts.
]]
local function outerLip(m: Model, center: Vector3, y0: number)
	local r = FireCrystal.LipRadius + 0.5
	local glow = Geo.cylinder(m, center + Vector3.new(0, y0 + 0.06, 0), 0.12, (r + 0.28) * 2, K.NeonBlue, NEON, Style.tiny())
	glow.Name = "LipGlow"
	local lip = Geo.cylinder(m, center + Vector3.new(0, y0 + 0.3, 0), 0.4, r * 2, K.MetalDark, SMOOTH, Style.ghost({ CastShadow = false }))
	lip.Name = "RingLip"
end

function FireCrystal.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("FireCrystal")
	local center = piece.Center
	local y0 = Common.TileTop
	local m = Style.model("FireCrystalRing", parent)

	-- glowing ember bed inside the housing
	local moat = Geo.cylinder(m, center + Vector3.new(0, y0 - 0.01, 0), 0.1, MOAT_R * 2, C.Ember, NEON, Style.tiny())
	moat.Name = "EmberMoat"

	housing(m, center, y0, rng)
	outerLip(m, center, y0)

	-- stepped octagonal metal base with a blue neon rim under its cap, and the glowing fire bed
	local yInner = y0 + INNER_H
	star(m, CFrame.new(center + Vector3.new(0, y0 + INNER_H / 2, 0)), INNER, INNER_H, Style.vary(K.Metal, rng, 0.03))
	local rim = star(m, CFrame.new(center + Vector3.new(0, yInner - 0.08, 0)), INNER + 0.2, 0.16, K.NeonBlue, NEON, Style.tiny())
	rim[1].Name = "BaseGlow"
	rim[2].Name = "BaseGlow"
	star(m, CFrame.new(center + Vector3.new(0, yInner + 0.2, 0)), INNER + 0.5, 0.4, Style.vary(K.MetalDark, rng, 0.03))
	local bed = star(m, CFrame.new(center + Vector3.new(0, yInner + 0.4, 0)), INNER - 3.4, 0.2, C.Ember, NEON, Style.tiny())
	bed[1].Name = "FireBed"
	bed[2].Name = "FireBed"
	Style.emitter(bed[1], "Fire", C.Fire, 12)
	Style.emitter(bed[1], "Embers", C.Fire, 6)

	-- octagonal pedestal with an Ember seam
	local yPed = yInner + 0.4
	star(
		m,
		CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H / 2, 0)) * CFrame.Angles(0, math.pi / 8, 0),
		PEDESTAL,
		PEDESTAL_H,
		Style.vary(K.MetalDark, rng, 0.03)
	)
	star(
		m,
		CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H * 0.45, 0)) * CFrame.Angles(0, math.pi / 8, 0),
		PEDESTAL + 0.25,
		0.25,
		C.Ember,
		NEON,
		Style.tiny()
	)

	crystalCluster(parent, CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H, 0)), rng)
end

return FireCrystal
