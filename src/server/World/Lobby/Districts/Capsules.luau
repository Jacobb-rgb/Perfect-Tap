--[[
	CAPSULES: the golem capsule stall left of the spawn, after concept v2
	(docs/art/lobby_concept_v2.webp). A dark gunmetal sci-fi module: a
	floor panel, two narrow shelving towers holding five rows of small
	opaque capsules (a saturated lower half, a light upper half, a small
	neon highlight) in dimly lit slots, thick blue neon edges, a beam
	across them carrying the big CAPSULES sign box, a dark back wall, and
	standing at the stall's front line the hero piece: a tall glass pill
	(a cylinder between two hemispheres, about 65% of the stall's height)
	in pale cyan-lilac glass round a glowing pink-to-cyan swirl (three
	twisted neon prisms, the brightest thing in the stall) with saturated
	gem chips floating in the glass and a small solid gold golem in front
	of the swirl, between dark metal end caps, on a pedestal with deep pink
	neon rings. Ore-tone golem figures with glowing crystal cores (original
	ore golems, Kenney Mini Characters proportions) on a stepped display
	and on the beam, the odds board on a stand inside the stall front, a
	capsule screen on the side that faces south.

	Lobby fix round 2: the hero capsule is one wide glass jar (no nested
	glass domes) filled by two stacked opaque neon cores, deep blue under
	violet, round a near-black golem silhouette with cyan eyes, under a dark
	metal cap with a blue neon ring. The board (part "OddsBoard") is titled
	RARITIES and lists the rarity names from Shared.Config.Rarity on one
	SurfaceGui (colour squares as row markers); there is no capsule odds
	table in Shared.Config yet, so it shows no percentages (paid random
	items: the real odds are added with the live table, docs/COMPLIANCE.md).
	Lobby fix round 3: the stall is 14 wide (it moved into the spawn view)
	and every x measure follows the footprint's width. The hero capsule is a
	rounded glass pod: one see-through glass shell (a body cylinder and two
	shrinking discs at each end, none overlapping) with two white highlight
	strips, round an opaque core of four stacked neon bands (deep blue,
	indigo, violet, magenta) with a bright cyan-white column, a gold golem
	with a glowing chest gem, five floating gem chips, bright cyan neon
	rings at both dark caps, on the ringed pedestal; well under the sign.
	The back wall carries a light panel and a neon strip; the small side
	blade sign is gone.

	Tag CapsuleStall on the Model, PrimaryPart = the pedestal base named
	"CapsuleMachine".
	Local frame: 14 wide (piece Size.X), 16 tall, 12 deep, front = -Z
	(toward the plaza and the spawn), +X = the viewer's left (south).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Rarity = require(Shared.Config.Rarity)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Capsules = {}

local C = Kit.C
local rgb = Color3.fromRGB

local FLOOR = 0.6
local TOWER_W = 2.4
local TOWER_Z0, TOWER_Z1 = -1.2, 2.4
local TOP = 10.4 -- tower and back wall top (the beam sits on it)
local EGG_Z = -2.9 -- the pod stands at the stall's front line, out of the module's recess
local EGG_R = 2.8 -- pod radius
-- (round 3: 3.5 -> 2.6 plus the rounded ends: the pod's cap stays 2 studs under the sign box)
local EGG_MID = 2.6
-- the rounded ends: shrinking glass discs { radius share, height } outward from the body
local EGG_ENDS = { { 0.84, 0.55 }, { 0.52, 0.42 } }
Capsules.PodClearance = 0.5 -- at least this much air between the pod's cap and the sign box
Capsules.SignY = TOP + 3.45 -- the CAPSULES sign box center
Capsules.SignH = 2.8
local POD_BOTTOM = FLOOR + 1.6
local END_H = EGG_ENDS[1][2] + EGG_ENDS[2][2]
local BODY_BOTTOM = POD_BOTTOM + END_H
local BODY_TOP = BODY_BOTTOM + EGG_MID + 2
Capsules.PodTop = BODY_TOP + END_H + 0.61 -- the top cap's ring

-- Saturated capsule colors (deep enough that none blooms to white).
local CAPSULE_COLORS = {
	C.AwningRed,
	rgb(240, 170, 20), -- yellow
	rgb(30, 100, 240), -- blue
	C.LeafGreen,
	rgb(140, 60, 240), -- purple
	C.LeafOrange,
	rgb(230, 60, 170), -- pink
	rgb(20, 160, 230), -- cyan
}

-- The hero pod (concept v2): light cyan glass round a blue-violet glow,
-- the brightest thing in the stall
local GLASS = rgb(190, 238, 255)
-- the core bands, bottom to top (round 3: a blend, no hard two-tone seam)
local CORE_BANDS = { rgb(12, 36, 200), rgb(44, 30, 210), rgb(84, 28, 214), rgb(132, 26, 196) }
local CORE_COLUMN = rgb(170, 240, 255) -- the bright cyan-white energy column
local CAP_RING = rgb(60, 230, 255) -- bright cyan neon rings at both caps
local PINK = Tech.Neon -- the pedestal's neon rings (round 2: blue, the stall's colour)
-- the golem inside the pod: a glowing gold figure (neon at mid value: it
-- reads in the stall's shade, no white bloom) with a cyan chest gem
local EGG_GOLEM = rgb(230, 150, 30)
local EGG_GOLEM_DARK = rgb(170, 96, 16)
local CHIP_COLORS = { rgb(60, 230, 255), rgb(255, 90, 200), rgb(255, 196, 64), rgb(150, 90, 255), rgb(90, 255, 170) }

-- Ore-tone golem figures with a small glowing crystal core (readable next
-- to the dark module, unlike dark stone golems)
local ORE_GOLEMS = {
	{ Body = C.Copper, Accent = C.LeafOrangeDark, Eyes = C.CrystalCyan, Gem = rgb(20, 160, 230) }, -- copper
	{ Body = C.StoneLight, Accent = C.Stone, Eyes = C.Fire, Gem = C.CrystalPurpleDeep }, -- stone grey
	{ Body = rgb(96, 150, 232), Accent = rgb(52, 92, 176), Eyes = C.FireCore, Gem = rgb(230, 60, 170) }, -- crystal
	{ Body = C.Gold, Accent = C.Brass, Eyes = C.Fire, Gem = rgb(230, 60, 170) }, -- gold
	{ Body = C.IronLight, Accent = C.Iron, Eyes = C.CrystalCyan, Gem = C.Molten }, -- iron
}

-- Rarity rows of the board: the names and colours of Shared.Config.Rarity
-- (there is no capsule odds table yet: no percentages are shown).

-- A small capsule: an opaque saturated lower half and a light upper half
-- (only the big pill is see-through: no sorting cost on phones) with a
-- small neon highlight on the front.
local function capsule(parent: Instance, center: Vector3, size: number, color: Color3, front: Vector3)
	Kit.ball(parent, center - Vector3.new(0, size * 0.2, 0), size, color)
	Kit.ball(parent, center + Vector3.new(0, size * 0.2, 0), size, color:Lerp(C.FlowerWhite, 0.6))
	Kit.glow(
		parent,
		CFrame.new(center + front * (size * 0.48) + Vector3.new(0, size * 0.18, 0)),
		Vector3.new(0.14, 0.14, 0.14),
		color:Lerp(C.FlowerWhite, 0.3)
	)
end

function Capsules.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("CapsuleStall")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- (round 3) every x measure follows the footprint's width
	local W = piece.Size.X - 0.4 -- floor, back wall and beam width
	local HALF = piece.Size.X / 2
	local TOWER_X = HALF - 1.4 -- shelving tower centers (narrow towers: the pod is the hero)

	-- floor panel with an orange front edge and blue side edges
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(W, FLOOR, 11.6), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.05, -0.4), Vector3.new(W - 6.6, 0.04, 9.4), Tech.MetalDeep)
	Tech.glow(m, at(0, FLOOR - 0.16, -5.84), Vector3.new(W - 0.4, 0.24, 0.12), Tech.Warm)
	-- a blue neon trim line along the floor's front lip (round 2)
	Tech.glow(m, at(0, FLOOR + 0.04, -5.62), Vector3.new(W - 0.6, 0.08, 0.3), Tech.Neon)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * (HALF - 0.16), FLOOR - 0.16, 0), Vector3.new(0.12, 0.24, 11.2), Tech.Neon)
	end

	-- dark gunmetal back wall with a dark recess panel (the pod is the light)
	Tech.wall(
		m,
		at(0, FLOOR, 4.9) * CFrame.Angles(0, math.pi, 0),
		W,
		TOP - FLOOR,
		1.0,
		{ Cap = false, BandY = 0.2, Color = Tech.MetalDark }
	)
	Kit.bit(m, at(0, FLOOR + 4.9, 4.36), Vector3.new(W - 6.2, 9.6, 0.1), Tech.MetalDeep)
	Tech.glow(m, at(0, FLOOR + 9.5, 4.28), Vector3.new(W - 6.6, 0.16, 0.08), Tech.Neon)
	-- (round 3) the back toward the pond and the town: a light steel panel
	-- and a blue neon strip, no blank dark slab
	Kit.bit(m, at(0, FLOOR + 5.6, 5.45), Vector3.new(W - 2.4, 5.2, 0.1), Tech.MetalLight)
	Tech.glow(m, at(0, FLOOR + 8.7, 5.52), Vector3.new(W - 2.4, 0.3, 0.08), Tech.Neon)

	-- two shelving towers with columns of glowing capsules
	local towerD = TOWER_Z1 - TOWER_Z0
	local towerZ = (TOWER_Z0 + TOWER_Z1) / 2
	local ci = 0
	for _, side in { -1, 1 } do
		local x = side * TOWER_X
		Style.block(
			m,
			at(x, (FLOOR + TOP) / 2, towerZ),
			Vector3.new(TOWER_W, TOP - FLOOR, towerD),
			Style.vary(Tech.MetalDark, rng, 0.03),
			nil,
			Style.solid()
		)
		local fz = TOWER_Z0
		-- a dim glowing backplate lights the capsule slots (lit cubbies, concept v2)
		Tech.glow(m, at(x, FLOOR + 5.2, fz - 0.04), Vector3.new(TOWER_W - 0.7, 9.2, 0.1), rgb(20, 30, 96))
		for _, ex in { -1, 1 } do
			Tech.glow(m, at(x + ex * (TOWER_W / 2 - 0.1), FLOOR + 4.9, fz - 0.1), Vector3.new(Tech.TUBE, 9.2, 0.16), Tech.Tube)
		end
		Kit.bit(m, at(x, FLOOR + 0.35, fz - 0.06), Vector3.new(TOWER_W, 0.4, 0.1), Tech.Band)
		Tech.glow(m, at(x, FLOOR + 0.08, fz - 0.07), Vector3.new(TOWER_W - 0.4, 0.1, 0.08), Tech.Warm)
		local out = (cf - cf.Position).LookVector
		for row = 0, 4 do
			local y = FLOOR + 1.55 + row * 1.68
			Kit.bit(m, at(x, y - 0.6, fz - 0.4), Vector3.new(TOWER_W - 0.5, 0.18, 0.8), Tech.MetalLight)
			for _, cx in { -0.42, 0.42 } do
				ci += 1
				capsule(m, pos(x + cx, y, fz - 0.45), 0.72, CAPSULE_COLORS[(ci - 1) % #CAPSULE_COLORS + 1], out)
			end
		end
	end

	-- the beam across the towers and the CAPSULES sign box on it
	Style.block(m, at(0, TOP + 0.8, towerZ), Vector3.new(W, 1.6, towerD), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, TOP + 0.2, TOWER_Z0 - 0.08), Vector3.new(W, Tech.TUBE, 0.16), Tech.Tube)
	-- a dark gunmetal band with a thin warm neon strip (no rust-brown band)
	Kit.bit(m, at(0, TOP + 0.95, TOWER_Z0 - 0.05), Vector3.new(W, 0.55, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, TOP + 0.95, TOWER_Z0 - 0.12), Vector3.new(W - 0.4, 0.14, 0.06), Tech.Warm)
	-- (the floodlight is a warm lens colour: no white light bar over the glass)
	-- (round 3: a deep electric blue frame with a bright core strip: a glowing tube)
	local signW = math.min(11.6, W - 2.0)
	Tech.sign(m, at(0, Capsules.SignY, -0.6), "CAPSULES", signW, Capsules.SignH, {
		Light = 14,
		LightColor = Tech.Lens,
		LightDist = 4.0,
		Back = true,
		Frame = C.GlowEdgeDeep,
		Core = C.GlowCore,
	})
	-- golem mascots on the beam ends
	Kit.golem(m, at(HALF - 1.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[4])
	Kit.golem(m, at(-(HALF - 1.0), TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[5])

	-- the ringed pedestal at the stall's front line: dark discs with blue
	-- neon rings (PrimaryPart)
	local base = Tech.disc(m, pos(0, FLOOR + 0.25, EGG_Z), 0.5, 2 * EGG_R + 0.4, Tech.MetalDark, nil, Style.solid())
	base.Name = "CapsuleMachine"
	Tech.disc(m, pos(0, FLOOR + 0.45, EGG_Z), 0.14, 2 * EGG_R + 0.6, PINK, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 0.75, EGG_Z), 0.5, 2 * EGG_R + 0.2, Tech.Metal, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 0.95, EGG_Z), 0.14, 2 * EGG_R + 0.4, PINK, Kit.NEON)
	-- the dark metal bottom cap the pod stands in, a bright cyan ring on it
	Tech.disc(m, pos(0, FLOOR + 1.3, EGG_Z), 0.6, 2 * EGG_R * EGG_ENDS[1][1] + 0.5, Tech.MetalDeep, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 1.62, EGG_Z), 0.1, 2 * EGG_R * EGG_ENDS[1][1] + 0.3, CAP_RING, Kit.NEON).Name = "CapRing"

	-- the rounded glass pod (round 3): ONE see-through shell built from a
	-- body cylinder and two shrinking discs at each end (no part overlaps
	-- another: one transparent layer, little overdraw on phones)
	local function glass(y: number, h: number, d: number): Part
		local part = Tech.disc(
			m,
			pos(0, y, EGG_Z),
			h,
			d,
			GLASS,
			Kit.GLASS,
			Style.decor({ Transparency = 0.45, Reflectance = 0.2, CastShadow = false })
		)
		part.Name = "CapsuleGlass"
		return part
	end
	local bodyBottom = BODY_BOTTOM
	local bodyTop = BODY_TOP
	local pill = glass((bodyBottom + bodyTop) / 2, bodyTop - bodyBottom, 2 * EGG_R)
	pill.Name = "CapsulePill"
	local yLo, yHi = bodyBottom, bodyTop
	for _, e in EGG_ENDS do
		glass(yLo - e[2] / 2, e[2], 2 * EGG_R * e[1])
		glass(yHi + e[2] / 2, e[2], 2 * EGG_R * e[1])
		yLo -= e[2]
		yHi += e[2]
	end
	local podTop = yHi
	-- two thin white highlight strips down the glass (front-left)
	for i, a in { -0.55, -0.32 } do
		local hx, hz = math.sin(a) * (EGG_R + 0.02), -math.cos(a) * (EGG_R + 0.02)
		Style.block(
			m,
			at(hx, (bodyBottom + bodyTop) / 2, EGG_Z + hz) * CFrame.Angles(0, -a, 0),
			Vector3.new(0.14, (bodyTop - bodyBottom) * (if i == 1 then 0.8 else 0.55), 0.06),
			C.FlowerWhite,
			nil,
			Style.tiny({ Transparency = 0.2 })
		).Name =
			"GlassHighlight"
	end
	-- the opaque glowing core: four stacked bands blending deep blue to
	-- magenta, a bright cyan-white column in front of them
	local coreZ = EGG_Z + 0.35
	local coreD = 2 * EGG_R - 1.3
	local bandH = (bodyTop - bodyBottom - 0.3) / #CORE_BANDS
	local coreMid: BasePart? = nil
	for i, color in CORE_BANDS do
		local y = bodyBottom + 0.15 + bandH * (i - 0.5)
		-- (each band tilted a little the other way: a swirl, not a paint can)
		local tilt = CFrame.Angles((i % 2 - 0.5) * 0.24, 0, ((i + 1) % 2 - 0.5) * 0.2)
		local band = Tech.disc(m, pos(0, y, coreZ), bandH, coreD - (i % 2) * 0.35, color, Kit.NEON, Style.tiny())
		local bandAt = band.CFrame.Position
		band.CFrame = CFrame.new(bandAt) * tilt * (band.CFrame - bandAt)
		if i == 3 then
			band.Name = "CapsuleCore"
			coreMid = band
		end
	end
	if coreMid then
		Style.light(coreMid, C.CrystalViolet, 18, 1.5)
		Style.emitter(coreMid, "Sparkle", C.CrystalCyan, 2)
	end
	Kit.glow(
		m,
		at(0, (bodyBottom + bodyTop) / 2, coreZ - coreD / 2 - 0.05),
		Vector3.new(0.45, bodyTop - bodyBottom - 0.6, 0.12),
		CORE_COLUMN
	).Name =
		"CoreColumn"
	-- the gold golem inside, in front of the core, a glowing chest gem
	local gz = EGG_Z - EGG_R + 0.7
	local gy = bodyBottom + 0.1
	local gs = 0.8
	for _, x in { -0.3, 0.3 } do
		Kit.glow(m, at(x * gs, gy + 0.4 * gs, gz), Vector3.new(0.5, 0.8, 0.45) * gs, EGG_GOLEM_DARK)
	end
	Kit.glow(m, at(0, gy + 1.35 * gs, gz), Vector3.new(1.3, 1.1, 0.5) * gs, EGG_GOLEM)
	for _, x in { -0.9, 0.9 } do
		Kit.glow(m, at(x * gs, gy + 1.35 * gs, gz), Vector3.new(0.42, 1.05, 0.42) * gs, EGG_GOLEM_DARK)
	end
	Kit.ball(m, pos(0, gy + 2.5 * gs, gz), 1.25 * gs, EGG_GOLEM, Kit.NEON)
	Kit.glow(m, at(0, gy + 1.4 * gs, gz - 0.27 * gs) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.42, 0.42, 0.08) * gs, C.CrystalCyan).Name =
		"GolemGem"
	for _, x in { -0.25, 0.25 } do
		Kit.bit(m, at(x * gs, gy + 2.55 * gs, gz - 0.6 * gs), Vector3.new(0.22, 0.18, 0.06) * gs, Kit.Dark)
	end
	-- floating gem chips in the glass's front half round the core (angle
	-- from local +X toward +Z, height share of the body)
	local chips = { { 200, 0.25 }, { 228, 0.7 }, { 312, 0.45 }, { 338, 0.15 }, { 262, 0.92 } }
	for i, color in CHIP_COLORS do
		local a = math.rad(chips[i][1])
		local r = EGG_R - 0.55
		local y = bodyBottom + 0.4 + (bodyTop - bodyBottom - 0.8) * chips[i][2]
		local chip = 0.5 + 0.05 * (i % 3)
		Kit.glow(
			m,
			at(math.cos(a) * r, y, EGG_Z + math.sin(a) * r) * CFrame.Angles(0.6, a, 0.785),
			Vector3.new(chip, chip, chip),
			color
		).Name =
			"GemChip"
	end
	-- the dark metal top cap with a bright cyan neon ring
	local capD = 2 * EGG_R * EGG_ENDS[#EGG_ENDS][1] + 0.6
	Tech.disc(m, pos(0, podTop + 0.25, EGG_Z), 0.5, capD, Tech.MetalDeep)
	Tech.disc(m, pos(0, podTop + 0.55, EGG_Z), 0.12, capD - 0.3, CAP_RING, Kit.NEON).Name = "CapRing"

	-- viewer's left (+X, south): stepped golem display in front of the tower
	-- (round 3: 1.3 studs per step, the golems no longer clip into each other)
	local gx = HALF - 1.3
	for k = 0, 2 do
		local h = 0.8 * (k + 1)
		local z = -5.15 + 1.3 * k
		Style.block(m, at(gx, FLOOR + h / 2, z), Vector3.new(2.2, h, 1.3), Style.vary(Tech.Metal, rng, 0.04), nil, Style.solid())
		Tech.glow(m, at(gx, FLOOR + h - 0.08, z - 0.67), Vector3.new(2.2, 0.12, 0.08), Tech.Neon)
		Kit.golem(m, at(gx, FLOOR + h, z), 0.7, ORE_GOLEMS[k + 1])
	end

	-- viewer's right (-X): the RARITIES board on a stand at the front edge,
	-- clear of the right tower's capsule column: one SurfaceGui lists the
	-- rarity names (white, unlit) with the colour squares as row markers
	local ox, oz = -(HALF - 1.3), -5.2
	Style.block(m, at(ox, FLOOR + 1.0, oz + 0.3), Vector3.new(0.5, 2.0, 0.5), Tech.MetalDark)
	Style.block(m, at(ox, FLOOR + 3.9, oz + 0.3), Vector3.new(2.3, 4.3, 0.5), Tech.MetalDark)
	local odds = Style.block(m, at(ox, FLOOR + 3.85, oz + 0.02), Vector3.new(1.9, 3.9, 0.1), Tech.Board, nil, Style.decor())
	odds.Name = "OddsBoard"
	odds.CastShadow = false
	Tech.outline(m, at(ox, FLOOR + 3.9, oz + 0.02), 1.08, 2.05, 0.3, 0.16, -0.06, Tech.Neon)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Rarities"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = odds
	local rows = #Rarity.List
	local function label(name: string, text: string, y: number, h: number, x: number, w: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(x, y)
		l.Size = UDim2.fromScale(w, h)
		l.Text = text
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeColor3 = Tech.Board
		l.TextStrokeTransparency = 0
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.FontFace = Font.fromEnum(Style.LabelFont)
		l.Parent = gui
	end
	label("Title", "RARITIES", 0.03, 0.12, 0.08, 0.84, Color3.new(1, 1, 1))
	local rowH = 0.8 / rows
	for i, info in Rarity.List do
		local y = 0.17 + (i - 1) * rowH
		local marker = Instance.new("Frame")
		marker.Name = "Marker" .. i
		marker.BorderSizePixel = 0
		marker.BackgroundColor3 = info.Color
		marker.Position = UDim2.fromScale(0.08, y + rowH * 0.22)
		marker.Size = UDim2.fromScale(0.13, rowH * 0.56)
		marker.Parent = gui
		label("Row" .. i, info.Name, y + rowH * 0.12, rowH * 0.76, 0.27, 0.68, Color3.new(1, 1, 1))
		-- (round 3) a small rarity-coloured chip beside each row, so the
		-- colours read from afar (and in the preview, which draws no frames)
		if i <= 6 then
			local boardH = 3.9
			local cy = FLOOR + 3.85 + boardH / 2 - (y + rowH * 0.5) * boardH
			Kit.glow(m, at(ox + 0.62, cy, oz - 0.05), Vector3.new(0.3, rowH * boardH * 0.55, 0.05), info.Color).Name = "RarityChip"
		end
	end

	-- the south side of the left tower: a screen with a capsule
	local sideAt = at(TOWER_X + TOWER_W / 2 + 0.06, FLOOR + 5.4, towerZ) * CFrame.Angles(0, -math.pi / 2, 0)
	Tech.screen(m, sideAt, 2.2, 3.0, C.GlowBoard, { Tabs = false })
	Kit.glow(m, sideAt * CFrame.new(0, 0.35, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(20, 150, 255))
	Kit.glow(m, sideAt * CFrame.new(0, -0.45, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(230, 60, 170))

	m.PrimaryPart = base
	Kit.tag(m, "CapsuleStall")
end

return Capsules
