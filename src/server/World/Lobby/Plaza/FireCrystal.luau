--[[
	The giant fire crystal in the middle of the plaza (LOBBY_PLAN 6.3.2,
	restyled after concept v2): a low, wide, stepped mechanical ring round a
	glowing molten bowl, and the towering amber crystal crown rising out of
	it.

	The ring has three tiers (Kenney pipe-ring-colored, chunky): a wide low
	dark metal base tier (walk-through) with deep-blue neon segments along
	its rim; 12 armor segments on it - an angled armor plate leaning on the
	outer face, a long narrow orange glow slit under a light metal cap lip,
	a thin blue edge on the inner lip - clamped by 12 chamfered ribs (same
	height everywhere, four with small status lights); and inside them the
	round molten bowl: a dark metal bowl wall, a deep-orange neon ring at
	its lip round a molten floor, and a dark inner pedestal with a glowing
	seam under the crystal.

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
local rgb = Color3.fromRGB

local FireCrystal = {}

FireCrystal.SpinSpeed = 0.25
FireCrystal.BobHeight = 0.25
FireCrystal.BobSpeed = 0.9

-- the armor ring (segments 9.0 .. 11.4 from the center), on the base tier
FireCrystal.RingRadius = 10.2
FireCrystal.RingWidth = 2.4
FireCrystal.RingHeight = 1.2 -- the armor tier over the base tier (cap lip included)
FireCrystal.BaseRadius = 12.4 -- the wide low base tier
FireCrystal.BaseHeight = 0.4
FireCrystal.CrystalHeight = 6.5 -- low: from the spawn (eye y >= 9) the forge's door and stairs show over it
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
-- the molten bowl inside the ring and the pedestal under the crystal
local BOWL_R = 8.6 -- the dark inner tier (its top is the bowl's rim)
local BOWL_TOP = 0.7 -- over the base tier
local GLOW_R = 5.5 -- the glowing ring at the bowl's lip
local POOL_R = 4.9 -- the molten floor inside it
local PEDESTAL_R = 2.5
local PEDESTAL_TOP = 1.5 -- over the base tier
local CRYSTAL_H = FireCrystal.CrystalHeight
local CRYSTAL_W = 3.6
-- colors: the dark machine metal of the plaza kit (the armor never reads
-- lighter than the slate floor), a mid bevel on the cap lips
local RING_METAL = K.Metal
local RING_BEVEL = K.MetalLight -- the cap lips (they catch the light, the segments read)
local RING_METAL_DARK = K.MetalDark
local HOT_IRON = rgb(128, 40, 22) -- the bowl's molten crust (dark red, lit by the crystal)
local CRYSTAL_GLOW = rgb(255, 120, 20) -- the inner glow (deep orange: no white-hot core)
local CRYSTAL_TIP = rgb(255, 150, 40)
-- turns a part's (1, 1, 1) corner straight up (a cube standing on a vertex)
local VERTEX_UP = CFrame.fromAxisAngle(Vector3.new(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))

--[[
	A leaning gem shard: a diamond-section body and a pointed tip (a cube
	standing on one corner, half sunk into the body), so the shard ends in
	a sharp point from every side instead of a box-cut ridge. 2 parts.
]]
local function shard(
	parent: Instance,
	base: CFrame,
	height: number,
	width: number,
	color: Color3,
	tip: Color3,
	material: Enum.Material,
	tipMaterial: Enum.Material?
): { BasePart }
	local a = width * 0.74
	local tipCenter = height - a * math.sqrt(3) / 2
	local bodyH = tipCenter + a * 0.12
	local body = Style.block(
		parent,
		base * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(0, bodyH / 2, 0),
		Vector3.new(width, bodyH, width),
		color,
		material,
		Style.tiny()
	)
	local point =
		Style.block(parent, base * CFrame.new(0, tipCenter, 0) * VERTEX_UP, Vector3.new(a, a, a), tip, tipMaterial or NEON, Style.tiny())
	return { body, point }
end

--[[
	The main crystal: a see-through amber shell with a pointed tip
	(Transparency 0.2, so its facets catch the sun and the lamps) round a
	slim deep-orange neon core, so the crystal reads as a sharp faceted gem
	that glows from within instead of a flat neon blob. Returns the core
	body (the spin pivot).
]]
local function mainCrystal(parent: Instance, base: CFrame): BasePart
	local shell = shard(parent, base, CRYSTAL_H, CRYSTAL_W, C.Fire, C.LeafOrange, SMOOTH, SMOOTH)
	for i, part in shell do
		part.Transparency = if i == 1 then 0.2 else 0.12
		part.Name = "CrystalShell"
	end
	local core = Style.crystal(parent, base * CFrame.new(0, 0.4, 0), CRYSTAL_H * 0.8, CRYSTAL_W * 0.44, CRYSTAL_GLOW, CRYSTAL_TIP)
	core[1].Name = "CrystalBody"
	return core[1]
end

--[[
	The crystal crown (concept v2): the tall main crystal and six side
	shards round it (about 2/3 of its height), big amber ones and smaller
	glowing ones alternating, leaning out 20-25 degrees, so the cluster is
	wide (about a third of the ring) and its points fan out like a crown.
]]
-- (shard heights scale with the main crystal: 9.2 tall in round 1)
local SIDE_SCALE = FireCrystal.CrystalHeight / 9.2
local SIDES = {
	{ A = 20, H = 6.0 * SIDE_SCALE, Lean = 0.42, Big = true },
	{ A = 80, H = 4.2 * SIDE_SCALE, Lean = 0.48, Big = false },
	{ A = 140, H = 5.5 * SIDE_SCALE, Lean = 0.46, Big = true },
	{ A = 200, H = 4.6 * SIDE_SCALE, Lean = 0.46, Big = false },
	{ A = 260, H = 5.8 * SIDE_SCALE, Lean = 0.42, Big = true },
	{ A = 320, H = 4.0 * SIDE_SCALE, Lean = 0.5, Big = false },
}
local function crystalCluster(parent: Instance, base: CFrame, rng: Rng.Rng): Model
	local m = Style.model("FireCrystal", parent)
	local body = mainCrystal(m, base)
	for i, s in SIDES do
		local a = math.rad(s.A + rng:range(-5, 5))
		local foot = base * CFrame.new(math.cos(a) * 1.9, 0.05, math.sin(a) * 1.9)
		local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -s.Lean) * CFrame.Angles(0, a, 0)
		if s.Big then
			-- shaded amber bodies (the facets read) with glowing points
			local parts = shard(m, foot * tilt, s.H, s.H * 0.3, if i % 4 == 1 then C.Fire else C.LeafOrange, CRYSTAL_TIP, SMOOTH)
			parts[1].Transparency = 0.05
		else
			shard(m, foot * tilt, s.H, s.H * 0.3, CRYSTAL_GLOW, CRYSTAL_TIP, NEON)
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
		local ribH = RING_H + 0.08
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

--[[
	The round molten bowl inside the ring (concept v2: the crystal rises
	from a glowing bowl): a dark metal inner tier with six blue and green
	glow bands, a deep-orange neon ring at the bowl's lip round a molten
	floor (lit by the crystal's light), and the dark pedestal with a
	glowing seam the crystal stands on, in a glowing molten heart. Round
	from every side (cylinders). 12 parts.
]]
local function moltenBowl(m: Model, center: Vector3, y0: number): number
	local yb = y0 + BASE_H
	local wall = Geo.cylinder(
		m,
		center + Vector3.new(0, yb + BOWL_TOP / 2, 0),
		BOWL_TOP,
		BOWL_R * 2,
		RING_METAL_DARK,
		SMOOTH,
		Style.solid({ CastShadow = false })
	)
	wall.Name = "BowlWall"
	local ring = Geo.cylinder(m, center + Vector3.new(0, yb + BOWL_TOP - 0.02, 0), 0.12, GLOW_R * 2, C.Ember, NEON, Style.tiny())
	ring.Name = "BowlGlow"
	-- blue and green glow bands on the inner tier (concept v2's coloured lights)
	for i = 0, 5 do
		local a = (i + 0.5) / 6 * 2 * math.pi
		local band = Style.block(
			m,
			CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(7.15, yb + BOWL_TOP + 0.01, 0),
			Vector3.new(0.45, 0.06, 3.6),
			if i % 2 == 0 then K.NeonBlueDeep else C.LeafGreenLight,
			NEON,
			Style.tiny()
		)
		band.Name = "InnerGlow"
	end
	local pool = Geo.cylinder(m, center + Vector3.new(0, yb + BOWL_TOP + 0.02, 0), 0.12, POOL_R * 2, C.Molten, SMOOTH, Style.tiny())
	pool.Name = "MoltenPool"
	pool.Color = HOT_IRON
	-- the white-hot heart round the pedestal (deep orange neon, not white)
	local core = Geo.cylinder(m, center + Vector3.new(0, yb + BOWL_TOP + 0.06, 0), 0.12, 3.3 * 2, C.Ember, NEON, Style.tiny())
	core.Name = "MoltenCore"
	Style.emitter(core, "Fire", C.Fire, 12)
	Style.emitter(core, "Embers", C.Fire, 6)
	local pedestalH = PEDESTAL_TOP - BOWL_TOP
	Geo.cylinder(
		m,
		center + Vector3.new(0, yb + BOWL_TOP + pedestalH / 2, 0),
		pedestalH,
		PEDESTAL_R * 2,
		Style.C.Iron,
		SMOOTH,
		Style.tiny()
	).Name =
		"Pedestal"
	local seamD = 2 * PEDESTAL_R + 0.24
	local seam = Geo.cylinder(m, center + Vector3.new(0, yb + BOWL_TOP + pedestalH * 0.45, 0), 0.14, seamD, C.Ember, NEON, Style.tiny())
	seam.Name = "PedestalSeam"
	return yb + PEDESTAL_TOP
end

function FireCrystal.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("FireCrystal")
	local center = piece.Center
	local y0 = Common.TileTop
	local m = Style.model("FireCrystalRing", parent)
	baseTier(m, center, y0)
	armorRing(m, center, y0, rng)
	local top = moltenBowl(m, center, y0)
	crystalCluster(parent, CFrame.new(center + Vector3.new(0, top, 0)), rng)
end

return FireCrystal
