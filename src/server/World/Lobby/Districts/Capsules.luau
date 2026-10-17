--[[
	CAPSULES: the golem capsule stall left of the spawn, next to SPIN & WIN,
	after concept v2 (docs/art/lobby_concept_v2.webp). A sci-fi module: a
	gunmetal floor panel, two shelving towers holding five rows of small
	capsules (saturated glowing lower halves, glass tops) in lit slots in
	front of a glowing backplate, thick blue neon edges, a beam across them
	carrying the big CAPSULES sign box, a back wall with a bright violet
	neon halo, and standing forward out of the recess the hero piece: a
	giant 8 stud tall glass capsule (a pill) around a vivid violet-to-blue
	glowing core, a big dark golem silhouette with two cyan eyes in front of
	the core, a thin deep blue band at the waist and a glowing cap, on a
	pedestal of deep neon rings with a thin tilted orbit ring. Ore-tone
	golem figures with glowing crystal cores (original ore golems, Kenney
	Mini Characters proportions) on a stepped display and on the beam, the odds
	board on a stand, a capsule screen on the side that faces south.

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
local TOWER_X = 6.3 -- shelving tower centers
local TOWER_Z0, TOWER_Z1 = -1.2, 2.4
local TOP = 10.4 -- tower and back wall top (the beam sits on it)
local EGG_Z = -0.5 -- the egg stands forward, out of the module's recess
local EGG_R = 2.3 -- egg radius; with the 3.4 tall middle the egg is 8 studs tall
local EGG_MID = 3.4

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

-- Deep neon tints of the hero capsule (vivid purple-blue, never pale)
local DEEP_BLUE = rgb(30, 90, 255)
local DEEP_VIOLET = rgb(120, 50, 255)
local CORE_TOP, CORE_BOTTOM = rgb(90, 30, 220), rgb(30, 70, 240)

-- Ore-tone golem figures with a small glowing crystal core (readable next
-- to the dark module, unlike dark stone golems)
local ORE_GOLEMS = {
	{ Body = C.Copper, Accent = C.LeafOrangeDark, Eyes = C.CrystalCyan, Gem = rgb(20, 160, 230) }, -- copper
	{ Body = C.StoneLight, Accent = C.Stone, Eyes = C.Fire, Gem = DEEP_VIOLET }, -- stone grey
	{ Body = rgb(96, 150, 232), Accent = rgb(52, 92, 176), Eyes = C.FireCore, Gem = rgb(230, 60, 170) }, -- crystal
	{ Body = C.Gold, Accent = C.Brass, Eyes = C.Fire, Gem = rgb(230, 60, 170) }, -- gold
	{ Body = C.IronLight, Accent = C.Iron, Eyes = C.CrystalCyan, Gem = C.Molten }, -- iron
}

-- Rarity rows of the odds board (colors only; numbers come from the live odds table).
local RARITIES = { C.StoneLight, C.LeafGreen, C.CrystalBlue, C.CrystalPurple, C.Gold, C.CrystalPink }

-- A small capsule: a saturated glowing lower half and a glass upper half.
local function capsule(parent: Instance, center: Vector3, size: number, color: Color3)
	Kit.ball(parent, center - Vector3.new(0, size * 0.2, 0), size, color, Kit.NEON)
	Kit.ball(
		parent,
		center + Vector3.new(0, size * 0.2, 0),
		size,
		color:Lerp(C.FlowerWhite, 0.55),
		Kit.GLASS,
		Style.tiny({ Transparency = 0.35 })
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

	-- back wall with a violet neon halo behind the egg
	Tech.wall(m, at(0, FLOOR, 4.9) * CFrame.Angles(0, math.pi, 0), 15.6, TOP - FLOOR, 1.0, { Cap = false, BandY = 0.2 })
	Kit.bit(m, at(0, FLOOR + 4.9, 4.36), Vector3.new(9.4, 9.6, 0.1), Tech.MetalDeep)
	local haloY = FLOOR + 5.9
	Tech.faceDisc(m, at(0, haloY, 4.3), 0.08, 7.2, rgb(58, 30, 150), Kit.NEON)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local r = 3.85
		local seg = at(0, haloY, 4.2) * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0)
		Tech.glow(m, seg, Vector3.new(2 * r * math.tan(math.pi / 8) + 0.25, 0.5, 0.12), C.CrystalViolet)
	end

	-- two shelving towers with columns of glowing capsules
	local towerD = TOWER_Z1 - TOWER_Z0
	local towerZ = (TOWER_Z0 + TOWER_Z1) / 2
	local ci = 0
	for _, side in { -1, 1 } do
		local x = side * TOWER_X
		Style.block(
			m,
			at(x, (FLOOR + TOP) / 2, towerZ),
			Vector3.new(3.0, TOP - FLOOR, towerD),
			Style.vary(Tech.Metal, rng, 0.03),
			nil,
			Style.solid()
		)
		local fz = TOWER_Z0
		-- a glowing backplate lights the capsule slots (lit cubbies, concept v2)
		Tech.glow(m, at(x, FLOOR + 5.2, fz - 0.04), Vector3.new(2.2, 9.2, 0.1), rgb(34, 46, 150))
		for _, ex in { -1.3, 1.3 } do
			Tech.glow(m, at(x + ex, FLOOR + 4.9, fz - 0.1), Vector3.new(Tech.TUBE, 9.2, 0.16), Tech.Tube)
		end
		Kit.bit(m, at(x, FLOOR + 0.35, fz - 0.06), Vector3.new(3.0, 0.4, 0.1), Tech.Band)
		Tech.glow(m, at(x, FLOOR + 0.08, fz - 0.07), Vector3.new(2.6, 0.1, 0.08), Tech.Warm)
		for row = 0, 4 do
			local y = FLOOR + 1.55 + row * 1.68
			Kit.bit(m, at(x, y - 0.66, fz - 0.4), Vector3.new(2.2, 0.18, 0.8), Tech.MetalLight)
			for _, cx in { -0.5, 0.5 } do
				ci += 1
				capsule(m, pos(x + cx, y, fz - 0.45), 0.82, CAPSULE_COLORS[(ci - 1) % #CAPSULE_COLORS + 1])
			end
		end
	end

	-- the beam across the towers and the CAPSULES sign box on it
	Style.block(m, at(0, TOP + 0.8, towerZ), Vector3.new(15.6, 1.6, towerD), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, TOP + 0.2, TOWER_Z0 - 0.08), Vector3.new(15.6, Tech.TUBE, 0.16), Tech.Tube)
	-- a dark gunmetal band with a thin warm neon strip (no rust-brown band)
	Kit.bit(m, at(0, TOP + 0.95, TOWER_Z0 - 0.05), Vector3.new(15.6, 0.55, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, TOP + 0.95, TOWER_Z0 - 0.12), Vector3.new(15.2, 0.14, 0.06), Tech.Warm)
	Tech.sign(m, at(0, TOP + 3.45, -0.6), "CAPSULES", 11.6, 2.8, { Light = 14, LightColor = C.GlowText, LightDist = 4.0, Back = true })
	-- golem mascots on the beam ends
	Kit.golem(m, at(7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[4])
	Kit.golem(m, at(-7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[5])

	-- the pedestal: three gunmetal discs with neon rings (PrimaryPart)
	local base = Tech.disc(m, pos(0, FLOOR + 0.25, EGG_Z), 0.5, 7.0, Tech.MetalDark, nil, Style.solid())
	base.Name = "CapsuleMachine"
	Tech.disc(m, pos(0, FLOOR + 0.45, EGG_Z), 0.14, 7.2, DEEP_BLUE, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 0.75, EGG_Z), 0.5, 5.8, Tech.Metal, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 0.95, EGG_Z), 0.14, 6.0, rgb(70, 50, 255), Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 1.2, EGG_Z), 0.4, 4.8, Tech.MetalLight, nil, Style.solid())
	local eggBottom = FLOOR + 1.4

	-- the giant glass capsule: a tall pill (two half-spheres and a cylinder)
	-- around a vivid violet-to-blue glowing core, a big dark golem
	-- silhouette (about 55% of the egg's height, two small cyan eyes) in
	-- front of the core, a thin deep blue band at the waist, a deep blue cap
	local lowY, highY = eggBottom + EGG_R, eggBottom + EGG_R + EGG_MID
	local midY = (lowY + highY) / 2
	local eggColor = rgb(150, 126, 255)
	local function glass(): { [string]: any }
		return Style.decor({ Transparency = 0.76, CastShadow = false })
	end
	Kit.ball(m, pos(0, lowY, EGG_Z), 2 * EGG_R, eggColor, Kit.GLASS, glass())
	Tech.disc(m, pos(0, midY, EGG_Z), EGG_MID, 2 * EGG_R, eggColor, Kit.GLASS, glass())
	Kit.ball(m, pos(0, highY, EGG_Z), 2 * EGG_R, eggColor, Kit.GLASS, glass())
	-- the core sits back in the egg so the silhouette stands in front of it
	local coreZ, coreD = EGG_Z + 0.65, 2 * EGG_R - 1.5
	local function core(): { [string]: any }
		return Style.tiny({ Transparency = 0.1 })
	end
	Kit.ball(m, pos(0, lowY + 0.1, coreZ), coreD, CORE_BOTTOM, Kit.NEON, core())
	local coreMid = Tech.disc(m, pos(0, midY, coreZ), EGG_MID, coreD, CORE_TOP:Lerp(CORE_BOTTOM, 0.5), Kit.NEON, core())
	coreMid.Name = "CapsuleCore"
	Kit.ball(m, pos(0, highY - 0.1, coreZ), coreD, CORE_TOP, Kit.NEON, core())
	Style.light(coreMid, C.CrystalPurple, 18, 1.8)
	Style.emitter(coreMid, "Sparkle", C.CrystalPink, 2)
	Kit.golem(m, at(0, eggBottom + 1.0, EGG_Z - 1.2), 1.6, {
		Body = rgb(20, 22, 52),
		Accent = rgb(12, 14, 36),
		Eyes = C.CrystalCyan,
		Depth = 0.35,
		TwinEyes = true,
	})
	Tech.disc(m, pos(0, midY + 0.1, EGG_Z), 0.22, 2 * EGG_R + 0.12, rgb(40, 60, 230), Kit.NEON)
	Tech.disc(m, pos(0, highY + EGG_R - 0.12, EGG_Z), 0.3, 1.7, Tech.MetalLight)
	Tech.disc(m, pos(0, highY + EGG_R + 0.12, EGG_Z), 0.2, 1.1, DEEP_BLUE, Kit.NEON)
	-- a tilted orbit ring of thin deep blue neon bars around the egg
	local orbit = at(0, midY - 0.4, EGG_Z) * CFrame.Angles(0.28, 0, 0.12)
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local r = 3.2
		local seg = orbit * CFrame.new(r * math.cos(a), 0, r * math.sin(a)) * CFrame.Angles(0, -a, 0)
		Tech.glow(m, seg, Vector3.new(0.1, 0.1, 2 * r * math.tan(math.pi / 8) + 0.06), DEEP_BLUE)
	end

	-- viewer's left (+X, south): stepped golem display in front of the tower
	for k = 0, 2 do
		local h = 0.8 * (k + 1)
		local z = -5.0 + 1.15 * k
		Style.block(m, at(TOWER_X, FLOOR + h / 2, z), Vector3.new(2.6, h, 1.15), Style.vary(Tech.Metal, rng, 0.04), nil, Style.solid())
		Tech.glow(m, at(TOWER_X, FLOOR + h - 0.08, z - 0.6), Vector3.new(2.6, 0.12, 0.08), Tech.Neon)
		Kit.golem(m, at(TOWER_X, FLOOR + h, z), 0.7, ORE_GOLEMS[k + 1])
	end

	-- viewer's right (-X): the odds board on a stand
	local ox, oz = -TOWER_X, -4.3
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
	local sideAt = at(TOWER_X + 1.65, FLOOR + 5.4, towerZ) * CFrame.Angles(0, -math.pi / 2, 0)
	Tech.screen(m, sideAt, 2.2, 3.0, C.GlowBoard)
	Kit.glow(m, sideAt * CFrame.new(0, 0.35, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(20, 150, 255))
	Kit.glow(m, sideAt * CFrame.new(0, -0.45, -0.08), Vector3.new(1.2, 0.8, 0.06), rgb(230, 60, 170))

	m.PrimaryPart = base
	Kit.tag(m, "CapsuleStall")
end

return Capsules
