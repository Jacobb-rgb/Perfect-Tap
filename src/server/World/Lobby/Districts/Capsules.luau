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

	Tag CapsuleStall on the Model, PrimaryPart = the pedestal base named
	"CapsuleMachine". The odds board (part "OddsBoard") shows rarity rows
	only; the real odds are added at runtime by the capsule service (paid
	random items: odds must match the live table, docs/COMPLIANCE.md).
	Local frame: 16 wide, 16 tall, 12 deep, front = -Z (toward the spawn),
	+X = the viewer's left (south).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Capsules = {}

local C = Kit.C
local rgb = Color3.fromRGB

local FLOOR = 0.6
local TOWER_X = 6.5 -- shelving tower centers (narrow towers: the pill is the hero)
local TOWER_W = 2.4
local TOWER_Z0, TOWER_Z1 = -1.2, 2.4
local TOP = 10.4 -- tower and back wall top (the beam sits on it)
local EGG_Z = -3.2 -- the pill stands at the stall's front line, out of the module's recess
local EGG_R = 2.1 -- pill radius; with the 5.9 tall middle the pill is 10.1 studs tall (~65% of the stall)
local EGG_MID = 5.9

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

-- The hero pill (concept v2): pale cyan-lilac glass round a glowing
-- pink-to-cyan swirl, the brightest thing in the stall
local GLASS = rgb(206, 226, 255)
local SWIRL_TOP, SWIRL_BOTTOM = rgb(255, 90, 200), rgb(60, 220, 255)
local PINK = C.CrystalPinkDeep -- the pedestal's neon rings
-- the golem inside the pill: solid gold, so it reads in front of the swirl
local EGG_GOLEM = rgb(255, 196, 64)
-- saturated gem chips floating in the pill's glass (x, y above the pill
-- bottom, z from the pill's axis; all between the core and the glass)
type Chip = { At: Vector3, Color: Color3 }
local CHIPS: { Chip } = {
	{ At = Vector3.new(-1.3, 2.4, -0.6), Color = rgb(230, 60, 170) },
	{ At = Vector3.new(1.35, 4.2, -0.4), Color = rgb(20, 200, 230) },
	{ At = Vector3.new(-1.2, 6.8, -0.7), Color = rgb(240, 170, 20) },
	{ At = Vector3.new(1.1, 8.4, -0.8), Color = rgb(60, 220, 90) },
}

-- Ore-tone golem figures with a small glowing crystal core (readable next
-- to the dark module, unlike dark stone golems)
local ORE_GOLEMS = {
	{ Body = C.Copper, Accent = C.LeafOrangeDark, Eyes = C.CrystalCyan, Gem = rgb(20, 160, 230) }, -- copper
	{ Body = C.StoneLight, Accent = C.Stone, Eyes = C.Fire, Gem = C.CrystalPurpleDeep }, -- stone grey
	{ Body = rgb(96, 150, 232), Accent = rgb(52, 92, 176), Eyes = C.FireCore, Gem = rgb(230, 60, 170) }, -- crystal
	{ Body = C.Gold, Accent = C.Brass, Eyes = C.Fire, Gem = rgb(230, 60, 170) }, -- gold
	{ Body = C.IronLight, Accent = C.Iron, Eyes = C.CrystalCyan, Gem = C.Molten }, -- iron
}

-- Rarity rows of the odds board (colors only; numbers come from the live odds table).
local RARITIES = { C.StoneLight, C.LeafGreen, C.CrystalBlue, C.CrystalPurple, C.Gold, C.CrystalPink }

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

	-- floor panel with an orange front edge and blue side edges
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(15.6, FLOOR, 11.6), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.02, -0.4), Vector3.new(9.0, 0.04, 9.4), Tech.Metal)
	Tech.glow(m, at(0, FLOOR - 0.16, -5.84), Vector3.new(15.2, 0.24, 0.12), Tech.Warm)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * 7.84, FLOOR - 0.16, 0), Vector3.new(0.12, 0.24, 11.2), Tech.Neon)
	end

	-- dark gunmetal back wall with a dark recess panel (the pill is the light)
	Tech.wall(
		m,
		at(0, FLOOR, 4.9) * CFrame.Angles(0, math.pi, 0),
		15.6,
		TOP - FLOOR,
		1.0,
		{ Cap = false, BandY = 0.2, Color = Tech.MetalDark }
	)
	Kit.bit(m, at(0, FLOOR + 4.9, 4.36), Vector3.new(9.4, 9.6, 0.1), Tech.MetalDeep)
	Tech.glow(m, at(0, FLOOR + 9.5, 4.28), Vector3.new(9.0, 0.16, 0.08), Tech.Neon)

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
	Style.block(m, at(0, TOP + 0.8, towerZ), Vector3.new(15.6, 1.6, towerD), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, TOP + 0.2, TOWER_Z0 - 0.08), Vector3.new(15.6, Tech.TUBE, 0.16), Tech.Tube)
	-- a dark gunmetal band with a thin warm neon strip (no rust-brown band)
	Kit.bit(m, at(0, TOP + 0.95, TOWER_Z0 - 0.05), Vector3.new(15.6, 0.55, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, TOP + 0.95, TOWER_Z0 - 0.12), Vector3.new(15.2, 0.14, 0.06), Tech.Warm)
	Tech.sign(m, at(0, TOP + 3.45, -0.6), "CAPSULES", 11.6, 2.8, { Light = 14, LightColor = C.GlowText, LightDist = 4.0, Back = true })
	-- golem mascots on the beam ends
	Kit.golem(m, at(7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[4])
	Kit.golem(m, at(-7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[5])

	-- the pink pedestal at the stall's front line: dark discs with deep pink
	-- neon rings (PrimaryPart)
	local base = Tech.disc(m, pos(0, FLOOR + 0.25, EGG_Z), 0.5, 5.8, Tech.MetalDark, nil, Style.solid())
	base.Name = "CapsuleMachine"
	Tech.disc(m, pos(0, FLOOR + 0.45, EGG_Z), 0.14, 6.0, PINK, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 0.75, EGG_Z), 0.5, 4.8, Tech.Metal, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 0.95, EGG_Z), 0.14, 5.0, PINK, Kit.NEON)
	-- the dark metal bottom end cap the pill stands in
	Tech.disc(m, pos(0, FLOOR + 1.3, EGG_Z), 0.6, 2 * EGG_R + 0.5, Tech.MetalDeep, nil, Style.solid())
	local eggBottom = FLOOR + 1.0

	-- the giant glass pill: a tall cylinder between two hemispheres in pale
	-- cyan-lilac glass round a glowing pink-to-cyan swirl (three twisted
	-- neon prisms), a small solid gold golem in front of the swirl, gem
	-- chips in the glass, dark metal end caps top and bottom
	local lowY, highY = eggBottom + EGG_R, eggBottom + EGG_R + EGG_MID
	local midY = (lowY + highY) / 2
	local function glass(): { [string]: any }
		return Style.decor({ Transparency = 0.6, CastShadow = false })
	end
	Kit.ball(m, pos(0, lowY, EGG_Z), 2 * EGG_R, GLASS, Kit.GLASS, glass())
	local pill = Tech.disc(m, pos(0, midY, EGG_Z), EGG_MID, 2 * EGG_R, GLASS, Kit.GLASS, glass())
	pill.Name = "CapsulePill"
	Kit.ball(m, pos(0, highY, EGG_Z), 2 * EGG_R, GLASS, Kit.GLASS, glass())
	-- the swirl: three twisted neon prisms from cyan (bottom) to pink (top),
	-- set back in the pill so the golem stands in front of it
	local coreZ = EGG_Z + 0.55
	local span = (highY + EGG_R * 0.6) - (lowY - EGG_R * 0.6)
	local segH = span / 3
	local coreMid: BasePart? = nil
	for i = 0, 2 do
		local y = lowY - EGG_R * 0.6 + segH * (i + 0.5)
		local color = SWIRL_BOTTOM:Lerp(SWIRL_TOP, i / 2)
		local seg = Kit.glow(m, at(0, y, coreZ) * CFrame.Angles(0, i * math.pi / 6, 0), Vector3.new(1.7, segH + 0.1, 1.7), color)
		if i == 1 then
			seg.Name = "CapsuleCore"
			coreMid = seg
		end
	end
	if coreMid then
		Style.light(coreMid, C.CrystalPink, 18, 1.5)
		Style.emitter(coreMid, "Sparkle", C.CrystalPink, 2)
	end
	-- the golem inside: about 45% of the pill's height, solid gold, two cyan eyes
	local gz = EGG_Z - 1.0
	local gy = eggBottom + 1.4
	for _, x in { -0.35, 0.35 } do
		Kit.bit(m, at(x, gy + 0.45, gz), Vector3.new(0.55, 0.9, 0.5), EGG_GOLEM:Lerp(C.Brass, 0.4))
	end
	Kit.bit(m, at(0, gy + 1.5, gz), Vector3.new(1.4, 1.2, 0.55), EGG_GOLEM)
	for _, x in { -0.95, 0.95 } do
		Kit.bit(m, at(x, gy + 1.55, gz), Vector3.new(0.45, 1.15, 0.45), EGG_GOLEM:Lerp(C.Brass, 0.4))
	end
	Kit.ball(m, pos(0, gy + 2.85, gz), 1.4, EGG_GOLEM)
	for _, x in { -0.28, 0.28 } do
		Kit.glow(m, at(x, gy + 2.9, gz - 0.66), Vector3.new(0.24, 0.2, 0.08), C.CrystalCyan)
	end
	-- saturated neon gem chips floating in the glass
	for i, c in CHIPS do
		local chip = at(c.At.X, eggBottom + c.At.Y, EGG_Z + c.At.Z) * CFrame.Angles(0.6, 0.4 * i, math.pi / 4)
		Kit.glow(m, chip, Vector3.new(0.32, 0.32, 0.32), c.Color)
	end
	-- the dark metal top end cap with a pink neon ring
	Tech.disc(m, pos(0, highY + EGG_R - 0.2, EGG_Z), 0.6, 2.2, Tech.MetalDeep)
	Tech.disc(m, pos(0, highY + EGG_R + 0.16, EGG_Z), 0.14, 1.5, PINK, Kit.NEON)

	-- viewer's left (+X, south): stepped golem display in front of the tower
	for k = 0, 2 do
		local h = 0.8 * (k + 1)
		local z = -5.0 + 1.15 * k
		Style.block(m, at(TOWER_X, FLOOR + h / 2, z), Vector3.new(2.6, h, 1.15), Style.vary(Tech.Metal, rng, 0.04), nil, Style.solid())
		Tech.glow(m, at(TOWER_X, FLOOR + h - 0.08, z - 0.6), Vector3.new(2.6, 0.12, 0.08), Tech.Neon)
		Kit.golem(m, at(TOWER_X, FLOOR + h, z), 0.7, ORE_GOLEMS[k + 1])
	end

	-- viewer's right (-X): the odds board on a stand
	local ox, oz = -TOWER_X, -3.6
	Style.block(m, at(ox, FLOOR + 1.0, oz + 0.3), Vector3.new(0.6, 2.0, 0.6), Tech.MetalDark)
	Style.block(m, at(ox, FLOOR + 3.9, oz + 0.3), Vector3.new(3.3, 4.3, 0.5), Tech.MetalDark)
	local odds = Style.block(m, at(ox, FLOOR + 3.7, oz + 0.02), Vector3.new(2.6, 3.4, 0.1), Tech.Board, nil, Style.decor())
	odds.Name = "OddsBoard"
	Tech.outline(m, at(ox, FLOOR + 3.9, oz + 0.02), 1.55, 2.05, 0.4, 0.2, -0.06, Tech.Neon)
	Style.sign(
		m,
		at(ox, FLOOR + 5.55, oz - 0.05),
		"ODDS",
		2.2,
		0.62,
		{ Kind = "Glow", Frame = false, Depth = 0.1, BoardColor = Tech.Board }
	)
	for i, color in RARITIES do
		local y = FLOOR + 4.95 - (i - 1) * 0.52
		Kit.glow(m, at(ox + 0.85, y, oz - 0.06), Vector3.new(0.36, 0.36, 0.06), color)
		Kit.bit(m, at(ox - 0.25, y, oz - 0.05), Vector3.new(1.5, 0.16, 0.05), C.GlowText)
	end

	-- the south side of the left tower: a screen with a capsule
	local sideAt = at(TOWER_X + TOWER_W / 2 + 0.35, FLOOR + 5.4, towerZ) * CFrame.Angles(0, -math.pi / 2, 0)
	Tech.screen(m, sideAt, 2.2, 3.0, C.GlowBoard)
	Kit.glow(m, sideAt * CFrame.new(0, 0.35, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(20, 150, 255))
	Kit.glow(m, sideAt * CFrame.new(0, -0.45, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(230, 60, 170))

	m.PrimaryPart = base
	Kit.tag(m, "CapsuleStall")
end

return Capsules
