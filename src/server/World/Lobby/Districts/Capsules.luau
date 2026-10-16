--[[
	CAPSULES: the golem capsule stall left of the spawn, next to SPIN & WIN
	(design v2). A round carousel stall: a red/white striped cone canopy on
	four posts, a big glass capsule machine (gumball shape, capsules in
	many colors) in the middle, little golem figures (original ore golems,
	Kenney Mini Characters proportions) on a stepped display and on the
	canopy top, a glowing CAPSULES sign and an odds board.

	Tag CapsuleStall on the Model, PrimaryPart = the machine body. The odds
	board (part "OddsBoard") shows rarity rows only; the real odds are
	added at runtime by the capsule service (paid random items: odds must
	match the live table, docs/COMPLIANCE.md).
	Local frame: 16 wide, 16 tall, 12 deep, front = -Z (toward the spawn).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Capsules = {}

local C = Kit.C

local FLOOR = 0.75
local CANOPY_Y = 9.2 -- canopy rim height
local CANOPY_R = 5.9 -- canopy rim radius
local APEX_Y = 12.4

local CAPSULE_COLORS = {
	C.AwningRed,
	C.LeafYellow,
	C.CrystalBlue,
	C.LeafGreen,
	C.AwningPurple,
	C.LeafOrange,
	C.FlowerPink,
	C.CrystalCyan,
	C.FlowerWhite,
}

-- Rarity rows of the odds board (colors only; numbers come from the live odds table).
local RARITIES = { C.StoneLight, C.LeafGreen, C.CrystalBlue, C.CrystalPurple, C.Gold, C.CrystalPink }

function Capsules.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("CapsuleStall")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end

	-- round platform (two discs) with a ring of little lamps
	Kit.disc(m, pos(0, 0.2, 0), 0.4, 11.8, C.FlagDark, nil, Style.solid())
	Kit.disc(m, pos(0, 0.575, 0), 0.35, 10.8, C.Flag, nil, Style.solid())
	for k = 0, 9 do
		local a = (k + 0.5) * 2 * math.pi / 10
		Kit.glow(m, at(5.62 * math.cos(a), 0.5, 5.62 * math.sin(a)), Vector3.new(0.36, 0.3, 0.36), C.Lamp)
	end

	-- the capsule machine: red base, gold bands, coin slot, crank, chute, glass globe
	local mz = 0.8
	local body = Style.block(m, at(0, FLOOR + 1.7, mz), Vector3.new(3.6, 3.4, 3.6), C.AwningRed, nil, Style.solid())
	body.Name = "CapsuleMachine"
	Kit.bit(m, at(0, FLOOR + 0.15, mz), Vector3.new(3.8, 0.3, 3.8), C.Gold)
	Kit.bit(m, at(0, FLOOR + 3.6, mz), Vector3.new(3.9, 0.4, 3.9), C.Gold)
	local front = mz - 1.8
	Kit.bit(m, at(0.8, FLOOR + 2.6, front - 0.06), Vector3.new(1.1, 0.8, 0.12), C.Iron)
	Kit.bit(m, at(0.8, FLOOR + 2.6, front - 0.13), Vector3.new(0.6, 0.12, 0.05), Kit.Dark)
	Kit.faceDisc(m, at(-0.7, FLOOR + 2.4, front - 0.12), 0.25, 1.3, C.Gold)
	Kit.bit(m, at(-0.25, FLOOR + 2.75, front - 0.35), Vector3.new(0.3, 0.3, 0.5), C.Gold)
	Kit.bit(m, at(0, FLOOR + 0.9, front - 0.3), Vector3.new(1.5, 1.0, 0.6), C.Iron)
	Kit.bit(m, at(0, FLOOR + 0.85, front - 0.62), Vector3.new(1.0, 0.55, 0.05), Kit.Dark)
	Kit.ball(m, pos(0.3, FLOOR + 0.8, front - 0.7), 0.7, C.FlowerPink)
	local globeY = FLOOR + 3.8 + 3.1
	local globe = Kit.ball(m, pos(0, globeY, mz), 6.2, C.Foam, Kit.GLASS, Style.tiny({ Transparency = 0.5, Reflectance = 0.1 }))
	globe.Name = "Globe"
	Style.light(globe, C.CloudLight, 14, 1.3)
	-- capsules heaped in the lower part of the globe
	for i = 1, 22 do
		local q: Vector3
		repeat
			q = Vector3.new(rng:range(-2.2, 2.2), rng:range(-2.3, 0.6), rng:range(-2.2, 2.2))
		until q.Magnitude < 2.3
		-- every third capsule glows a little (a golem core inside), the rest are plain
		local color = CAPSULE_COLORS[(i - 1) % #CAPSULE_COLORS + 1]
		local glowing = i % 3 == 0
		Kit.ball(
			m,
			pos(q.X, globeY + q.Y, mz + q.Z),
			rng:range(1.0, 1.25),
			if glowing then color:Lerp(Kit.Dark, 0.35) else color,
			if glowing then Kit.NEON else Kit.SMOOTH
		)
	end
	Kit.disc(m, pos(0, globeY + 3.25, mz), 0.7, 2.4, C.Gold, nil, Style.tiny())
	Kit.ball(m, pos(0, globeY + 3.8, mz), 0.9, C.Gold)

	-- two little golems guarding the machine on its gold band
	Kit.golem(m, at(1.55, FLOOR + 3.8, mz - 1.4), 0.55, Kit.GolemLooks[1])
	Kit.golem(m, at(-1.55, FLOOR + 3.8, mz - 1.4), 0.55, Kit.GolemLooks[3])

	-- four candy-striped posts (front opening between the front two)
	for _, deg in { 0, 180, 225, 315 } do
		local a = math.rad(deg)
		local x, z = 4.95 * math.cos(a), 4.95 * math.sin(a)
		Style.block(m, at(x, (FLOOR + CANOPY_Y) / 2, z), Vector3.new(0.5, CANOPY_Y - FLOOR, 0.5), C.AwningWhite)
		for _, y in { 3.0, 6.2 } do
			Kit.bit(m, at(x, y, z), Vector3.new(0.58, 0.7, 0.58), C.AwningRed)
		end
	end

	-- striped cone canopy (8 panels) with a scalloped valance
	local apex = pos(0, APEX_Y, 0)
	local step = 2 * math.pi / 8
	for k = 0, 7 do
		local a = math.pi / 8 + k * step
		local b = a + step
		local pa = pos(CANOPY_R * math.cos(a), CANOPY_Y, CANOPY_R * math.sin(a))
		local pb = pos(CANOPY_R * math.cos(b), CANOPY_Y, CANOPY_R * math.sin(b))
		local normal = (pa - apex):Cross(pb - apex)
		if normal.Y < 0 then
			normal = -normal
		end
		local color = if k % 2 == 0 then C.AwningRed else C.AwningWhite
		Kit.tri(m, apex, pa, pb, 0.35, color, normal)
		local mid = (a + b) / 2
		local r = CANOPY_R * math.cos(step / 2) - 0.1
		local valance = at(r * math.cos(mid), CANOPY_Y - 0.5, r * math.sin(mid)) * CFrame.Angles(0, math.pi / 2 - mid, 0)
		Kit.bit(m, valance, Vector3.new(3.6, 1.0, 0.25), color)
	end
	Kit.disc(m, pos(0, APEX_Y - 0.05, 0), 0.4, 1.8, C.Gold, nil, Style.tiny())
	-- the golem mascot on the top
	Kit.golem(m, at(0, APEX_Y + 0.15, 0), 1.15, Kit.GolemLooks[2])

	-- CAPSULES sign on the canopy front
	Style.sign(m, at(0, CANOPY_Y + 1.15, -5.25), "CAPSULES", 8, 2.3, { Kind = "Glow" })

	-- viewer's left (+X): stepped golem display with three golems
	for k = 0, 2 do
		local h = 1.1 * (k + 1)
		local z = -1.3 + 1.3 * k
		Style.block(m, at(6.6, h / 2, z), Vector3.new(2.4, h, 1.3), Style.vary(C.WoodLight, rng, 0.04))
		Kit.bit(m, at(6.6, h - 0.1, z - 0.62), Vector3.new(2.45, 0.22, 0.1), C.AwningRed)
		Kit.golem(m, at(6.6, h, z), 0.8, Kit.GolemLooks[3 + k + 1])
	end

	-- viewer's right (-X): the odds board on two posts
	for _, x in { -5.4, -7.7 } do
		Style.block(m, at(x, 3.2, 0), Vector3.new(0.45, 6.4, 0.45), C.WoodDark)
	end
	local odds = Style.block(m, at(-6.55, 3.75, -0.3), Vector3.new(2.6, 3.8, 0.3), C.SignBoard)
	odds.Name = "OddsBoard"
	Style.sign(m, at(-6.55, 6.15, -0.4), "ODDS", 2.9, 0.9, { Kind = "Wood", Depth = 0.3 })
	for i, color in RARITIES do
		local y = 5.25 - (i - 1) * 0.6
		Kit.bit(m, at(-5.65, y, -0.48), Vector3.new(0.4, 0.4, 0.06), color)
		Kit.bit(m, at(-6.75, y, -0.47), Vector3.new(1.6, 0.18, 0.05), C.SignText)
	end

	m.PrimaryPart = body
	Kit.tag(m, "CapsuleStall")
end

return Capsules
