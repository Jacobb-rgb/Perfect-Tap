--[[
	CAPSULES: the golem capsule stall left of the spawn, next to SPIN & WIN,
	after concept v2 (docs/art/lobby_concept_v2.webp). A sci-fi module: a
	gunmetal floor panel, two shelving towers holding columns of small
	glowing capsules behind blue neon edges, a beam across them carrying the
	big CAPSULES sign box, a back wall with a violet neon halo, and in the
	middle a giant glowing glass capsule (an egg-shaped pill with a violet
	core and a golem silhouette inside) on a pedestal of neon rings with a
	tilted orbit ring. Golem figures (original ore golems, Kenney Mini
	Characters proportions) on a stepped display and on the beam, the odds
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

local FLOOR = 0.6
local TOWER_X = 6.3 -- shelving tower centers
local TOWER_Z0, TOWER_Z1 = -1.2, 2.4
local TOP = 10.4 -- tower and back wall top (the beam sits on it)
local EGG_Z = 0.8
local EGG_R = 2.6

local CAPSULE_COLORS = {
	C.AwningRed,
	C.LeafYellow,
	C.CrystalBlue,
	C.LeafGreen,
	C.CrystalPurple,
	C.LeafOrange,
	C.CrystalPink,
	C.CrystalCyan,
}

-- Rarity rows of the odds board (colors only; numbers come from the live odds table).
local RARITIES = { C.StoneLight, C.LeafGreen, C.CrystalBlue, C.CrystalPurple, C.Gold, C.CrystalPink }

-- A small capsule: a glowing colored lower half and a pale glowing upper half.
local function capsule(parent: Instance, center: Vector3, size: number, color: Color3)
	Kit.ball(parent, center - Vector3.new(0, size * 0.2, 0), size, color:Lerp(Kit.Dark, 0.3), Kit.NEON)
	Kit.ball(parent, center + Vector3.new(0, size * 0.2, 0), size, color:Lerp(C.FlowerWhite, 0.3):Lerp(Kit.Dark, 0.35), Kit.NEON)
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
	Tech.glow(m, at(0, FLOOR - 0.15, -5.82), Vector3.new(15.2, 0.16, 0.1), Tech.Warm)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * 7.82, FLOOR - 0.15, 0), Vector3.new(0.1, 0.16, 11.2), Tech.Neon)
	end

	-- back wall with a violet neon halo behind the egg
	Tech.wall(m, at(0, FLOOR, 4.9) * CFrame.Angles(0, math.pi, 0), 15.6, TOP - FLOOR, 1.0, { Cap = false, BandY = 0.2 })
	Kit.bit(m, at(0, FLOOR + 4.9, 4.36), Vector3.new(9.4, 9.6, 0.1), Tech.MetalDeep)
	local haloY = FLOOR + 5.4
	for k = 0, 7 do
		local a = k * math.pi / 4
		local r = 3.7
		local seg = at(0, haloY, 4.28) * CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0)
		Tech.glow(m, seg, Vector3.new(2 * r * math.tan(math.pi / 8) + 0.2, 0.3, 0.1), C.CrystalViolet)
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
		Kit.bit(m, at(x, FLOOR + 4.9, fz - 0.04), Vector3.new(2.2, 8.4, 0.1), Tech.MetalDeep)
		for _, ex in { -1.3, 1.3 } do
			Tech.glow(m, at(x + ex, FLOOR + 4.9, fz - 0.07), Vector3.new(0.22, 9.2, 0.1), Tech.Neon)
		end
		Kit.bit(m, at(x, FLOOR + 0.5, fz - 0.06), Vector3.new(3.0, 0.5, 0.1), Tech.Band)
		Tech.glow(m, at(x, FLOOR + 0.12, fz - 0.07), Vector3.new(2.6, 0.12, 0.08), Tech.Warm)
		for row = 0, 3 do
			local y = FLOOR + 1.8 + row * 2.05
			Kit.bit(m, at(x, y - 0.66, fz - 0.4), Vector3.new(2.2, 0.18, 0.8), Tech.MetalLight)
			for _, cx in { -0.5, 0.5 } do
				ci += 1
				capsule(m, pos(x + cx, y, fz - 0.45), 0.82, CAPSULE_COLORS[(ci - 1) % #CAPSULE_COLORS + 1])
			end
		end
	end

	-- the beam across the towers and the CAPSULES sign box on it
	Style.block(m, at(0, TOP + 0.8, towerZ), Vector3.new(15.6, 1.6, towerD), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, TOP + 0.14, TOWER_Z0 - 0.05), Vector3.new(15.6, 0.16, 0.1), Tech.Neon)
	Kit.bit(m, at(0, TOP + 0.85, TOWER_Z0 - 0.05), Vector3.new(15.6, 0.55, 0.1), Tech.Band)
	Tech.sign(m, at(0, TOP + 3.45, -0.6), "CAPSULES", 11.6, 2.8, { Light = 14, LightColor = C.GlowText })
	-- golem mascots on the beam ends
	Kit.golem(m, at(7.0, TOP + 1.6, towerZ), 0.8, Kit.GolemLooks[2])
	Kit.golem(m, at(-7.0, TOP + 1.6, towerZ), 0.8, Kit.GolemLooks[4])

	-- the pedestal: three gunmetal discs with neon rings (PrimaryPart)
	local base = Tech.disc(m, pos(0, FLOOR + 0.3, EGG_Z), 0.6, 7.0, Tech.MetalDark, nil, Style.solid())
	base.Name = "CapsuleMachine"
	Tech.disc(m, pos(0, FLOOR + 0.55, EGG_Z), 0.12, 7.2, C.CrystalBlue, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 0.9, EGG_Z), 0.6, 5.8, Tech.Metal, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 1.15, EGG_Z), 0.12, 6.0, C.CrystalPurple, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 1.45, EGG_Z), 0.5, 4.6, Tech.MetalLight, nil, Style.solid())
	local eggBottom = FLOOR + 1.7

	-- the giant glass capsule: two half-spheres and a short cylinder (a pill),
	-- a violet glowing core behind a dark golem silhouette
	local lowY, highY = eggBottom + EGG_R, eggBottom + EGG_R + 1.8
	local glass = Style.decor({ Transparency = 0.5, CastShadow = false })
	local eggColor = Tech.Glass:Lerp(C.CrystalBlue, 0.35)
	Kit.ball(m, pos(0, lowY, EGG_Z), 2 * EGG_R, eggColor, Kit.GLASS, glass)
	Tech.disc(
		m,
		pos(0, (lowY + highY) / 2, EGG_Z),
		highY - lowY,
		2 * EGG_R,
		eggColor,
		Kit.GLASS,
		Style.decor({ Transparency = 0.5, CastShadow = false })
	)
	Kit.ball(m, pos(0, highY, EGG_Z), 2 * EGG_R, eggColor, Kit.GLASS, Style.decor({ Transparency = 0.5, CastShadow = false }))
	-- a soft blue aura fills the glass, the violet core glows behind the golem
	Kit.ball(m, pos(0, lowY + 0.1, EGG_Z), 2 * EGG_R - 0.5, C.CrystalBlue, Kit.NEON, Style.tiny({ Transparency = 0.72 }))
	Kit.ball(m, pos(0, highY - 0.1, EGG_Z), 2 * EGG_R - 0.5, C.CrystalBlue, Kit.NEON, Style.tiny({ Transparency = 0.72 }))
	local core = Kit.ball(m, pos(0, (lowY + highY) / 2 + 0.3, EGG_Z + 0.9), 3.4, C.CrystalViolet, Kit.NEON)
	core.Name = "CapsuleCore"
	Style.light(core, C.CrystalPurple, 18, 1.6)
	Style.emitter(core, "Sparkle", C.CrystalPink, 2)
	Kit.golem(m, at(0, eggBottom + 0.5, EGG_Z - 0.5), 1.35, {
		Body = Tech.MetalDeep,
		Accent = Tech.MetalDark,
		Eyes = C.CrystalCyan,
		Gem = C.CrystalPink,
	})
	Tech.disc(m, pos(0, highY + EGG_R - 0.1, EGG_Z), 0.3, 1.6, Tech.MetalLight)
	Kit.ball(m, pos(0, highY + EGG_R + 0.25, EGG_Z), 0.6, C.CrystalCyan, Kit.NEON)
	-- a tilted orbit ring of neon bars around the egg
	local orbit = at(0, (lowY + highY) / 2, EGG_Z) * CFrame.Angles(0.28, 0, 0.12)
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local r = 3.4
		local seg = orbit * CFrame.new(r * math.cos(a), 0, r * math.sin(a)) * CFrame.Angles(0, -a, 0)
		Tech.glow(m, seg, Vector3.new(0.14, 0.14, 2 * r * math.tan(math.pi / 8) + 0.1), C.CrystalCyan)
	end

	-- viewer's left (+X, south): stepped golem display in front of the tower
	for k = 0, 2 do
		local h = 0.8 * (k + 1)
		local z = -5.0 + 1.15 * k
		Style.block(m, at(TOWER_X, FLOOR + h / 2, z), Vector3.new(2.6, h, 1.15), Style.vary(Tech.Metal, rng, 0.04), nil, Style.solid())
		Tech.glow(m, at(TOWER_X, FLOOR + h - 0.08, z - 0.6), Vector3.new(2.6, 0.12, 0.08), Tech.Neon)
		Kit.golem(m, at(TOWER_X, FLOOR + h, z), 0.7, Kit.GolemLooks[3 + k + 1])
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
	Kit.glow(m, sideAt * CFrame.new(0, 0.35, -0.08), Vector3.new(1.2, 0.8, 0.06), C.FlowerWhite:Lerp(C.CrystalBlue, 0.2))
	Kit.glow(m, sideAt * CFrame.new(0, -0.45, -0.08), Vector3.new(1.2, 0.8, 0.06), C.CrystalPink)

	m.PrimaryPart = base
	Kit.tag(m, "CapsuleStall")
end

return Capsules
