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
	A second, double-sided CAPSULES sign on a post at the front-left corner
	faces south (the hero camera).

	Tag CapsuleStall on the Model, PrimaryPart = the pedestal base named
	"CapsuleMachine".
	Local frame: 16 wide, 16 tall, 12 deep, front = -Z (toward the spawn),
	+X = the viewer's left (south).
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
local TOWER_X = 6.5 -- shelving tower centers (narrow towers: the pill is the hero)
local TOWER_W = 2.4
local TOWER_Z0, TOWER_Z1 = -1.2, 2.4
local TOP = 10.4 -- tower and back wall top (the beam sits on it)
local EGG_Z = -2.9 -- the jar stands at the stall's front line, out of the module's recess
local EGG_R = 3.0 -- jar radius (round 2: a wide egg-like jar, concept v2)
local EGG_MID = 3.5 -- with the two cap allowances the jar is 2 * EGG_R + EGG_MID = 9.5 studs tall

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

-- The hero jar (concept v2): pale glass round a violet-to-blue glow, the
-- brightest thing in the stall
local GLASS = rgb(206, 226, 255)
local CORE_LOW, CORE_HIGH = rgb(20, 60, 255), rgb(130, 60, 255) -- deep blue under violet
local PINK = Tech.Neon -- the pedestal's neon rings (round 2: blue, the stall's colour)
-- the golem inside the jar: a near-black silhouette (its cyan eyes glow)
local EGG_GOLEM = rgb(22, 22, 30)

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

	-- floor panel with an orange front edge and blue side edges
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(15.6, FLOOR, 11.6), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.05, -0.4), Vector3.new(9.0, 0.04, 9.4), Tech.MetalDeep)
	Tech.glow(m, at(0, FLOOR - 0.16, -5.84), Vector3.new(15.2, 0.24, 0.12), Tech.Warm)
	-- a blue neon trim line along the floor's front lip (round 2)
	Tech.glow(m, at(0, FLOOR + 0.04, -5.62), Vector3.new(15.0, 0.08, 0.3), Tech.Neon)
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
	-- (the floodlight is a warm lens colour: no white light bar over the glass)
	Tech.sign(m, at(0, TOP + 3.45, -0.6), "CAPSULES", 11.6, 2.8, { Light = 14, LightColor = Tech.Lens, LightDist = 4.0, Back = true })
	-- golem mascots on the beam ends
	Kit.golem(m, at(7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[4])
	Kit.golem(m, at(-7.0, TOP + 1.6, towerZ), 0.8, ORE_GOLEMS[5])

	-- the pink pedestal at the stall's front line: dark discs with deep pink
	-- neon rings (PrimaryPart)
	local base = Tech.disc(m, pos(0, FLOOR + 0.25, EGG_Z), 0.5, 6.4, Tech.MetalDark, nil, Style.solid())
	base.Name = "CapsuleMachine"
	Tech.disc(m, pos(0, FLOOR + 0.45, EGG_Z), 0.14, 6.6, PINK, Kit.NEON)
	Tech.disc(m, pos(0, FLOOR + 0.75, EGG_Z), 0.5, 6.2, Tech.Metal, nil, Style.solid())
	Tech.disc(m, pos(0, FLOOR + 0.95, EGG_Z), 0.14, 6.4, PINK, Kit.NEON)
	-- the dark metal bottom end cap the pill stands in
	Tech.disc(m, pos(0, FLOOR + 1.3, EGG_Z), 0.6, 2 * EGG_R + 0.5, Tech.MetalDeep, nil, Style.solid())
	local eggBottom = FLOOR + 1.6

	-- the giant glass jar: ONE wide glass shell (no nested domes: no
	-- clipping, little transparent overdraw on phones) filled by two stacked
	-- opaque neon cores (deep blue under violet), a near-black golem
	-- silhouette with cyan eyes in front of them, a dark metal top cap with a
	-- blue neon ring
	local jarH = 2 * EGG_R + EGG_MID
	local midY = eggBottom + jarH / 2
	local pill = Tech.disc(
		m,
		pos(0, midY, EGG_Z),
		jarH,
		2 * EGG_R,
		GLASS,
		Kit.GLASS,
		Style.decor({ Transparency = 0.62, CastShadow = false })
	)
	pill.Name = "CapsulePill"
	local coreZ = EGG_Z + 0.4
	local coreH = (jarH - 0.6) / 2
	local coreMid: BasePart? = nil
	for i, color in { CORE_LOW, CORE_HIGH } do
		local y = eggBottom + 0.3 + coreH * (i - 0.5)
		local core = Tech.disc(m, pos(0, y, coreZ), coreH - 0.04, 2 * EGG_R - 1.0, color, Kit.NEON, Style.tiny())
		if i == 2 then
			core.Name = "CapsuleCore"
			coreMid = core
		end
	end
	if coreMid then
		Style.light(coreMid, C.CrystalViolet, 18, 1.5)
		Style.emitter(coreMid, "Sparkle", C.CrystalViolet, 2)
	end
	-- the golem inside, in front of the cores: a near-black silhouette, cyan eyes
	local gz = EGG_Z - EGG_R + 0.75
	local gy = eggBottom + 1.2
	for _, x in { -0.35, 0.35 } do
		Kit.bit(m, at(x, gy + 0.45, gz), Vector3.new(0.55, 0.9, 0.5), EGG_GOLEM)
	end
	Kit.bit(m, at(0, gy + 1.5, gz), Vector3.new(1.4, 1.2, 0.55), EGG_GOLEM)
	for _, x in { -0.95, 0.95 } do
		Kit.bit(m, at(x, gy + 1.55, gz), Vector3.new(0.45, 1.15, 0.45), EGG_GOLEM)
	end
	Kit.ball(m, pos(0, gy + 2.85, gz), 1.4, EGG_GOLEM)
	for _, x in { -0.28, 0.28 } do
		Kit.glow(m, at(x, gy + 2.9, gz - 0.66), Vector3.new(0.24, 0.2, 0.08), C.CrystalCyan)
	end
	-- the dark metal top cap with a blue neon ring
	local capY = eggBottom + jarH
	Tech.disc(m, pos(0, capY + 0.3, EGG_Z), 0.6, 2 * EGG_R + 0.3, Tech.MetalDeep)
	Tech.disc(m, pos(0, capY + 0.7, EGG_Z), 0.2, 2 * EGG_R - 0.6, Tech.Neon, Kit.NEON)

	-- viewer's left (+X, south): stepped golem display in front of the tower
	local gx = TOWER_X + 0.6
	for k = 0, 2 do
		local h = 0.8 * (k + 1)
		local z = -5.0 + 1.0 * k
		Style.block(m, at(gx, FLOOR + h / 2, z), Vector3.new(2.2, h, 1.0), Style.vary(Tech.Metal, rng, 0.04), nil, Style.solid())
		Tech.glow(m, at(gx, FLOOR + h - 0.08, z - 0.52), Vector3.new(2.2, 0.12, 0.08), Tech.Neon)
		Kit.golem(m, at(gx, FLOOR + h, z), 0.7, ORE_GOLEMS[k + 1])
	end
	-- the second, double-sided CAPSULES sign on a post at the front-left
	-- corner, turned to face south (the hero camera sees it past the jar)
	local corner = at(5.7, 0, -3.9) * CFrame.Angles(0, math.rad(-45), 0)
	Style.block(m, corner * CFrame.new(0, 3.6, 0.7), Vector3.new(0.5, 7.2, 0.5), Tech.MetalDark, nil, Style.decor())
	Tech.sign(m, corner * CFrame.new(0, 8.4, 0), "CAPSULES", 4.0, 1.3, { DoubleSided = true, Margin = 0.3, Studs = false })

	-- viewer's right (-X): the RARITIES board on a stand at the front edge,
	-- clear of the right tower's capsule column: one SurfaceGui lists the
	-- rarity names (white, unlit) with the colour squares as row markers
	local ox, oz = -7.0, -5.2
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
