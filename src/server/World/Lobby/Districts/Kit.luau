--[[
	Local helpers of the Districts package (stalls, NPCs, golem figures,
	signs with custom glow colors). Pure builders on top of the shared
	Lobby Style kit; everything here uses Style.C colors.

	Frames: every helper takes a "base" CFrame = bottom center, front =
	LookVector (local -Z), like the Style kit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)

local Kit = {}

type Opts = { [string]: any }

local C = Style.C
Kit.C = C

Kit.SMOOTH = Enum.Material.SmoothPlastic
Kit.NEON = Enum.Material.Neon
Kit.METAL = Enum.Material.Metal
Kit.GLASS = Enum.Material.Glass

-- Skin and dark details for NPCs (Style.C has no skin tone; Sand reads as one).
Kit.Skin = C.Sand
Kit.Dark = C.HazardDark

---------------------------------------------------------------- frames

-- A Districts piece and its frame (origin = bottom center, LookVector = Facing).
function Kit.piece(id: string): (LobbyLayout.Piece, CFrame)
	local piece = LobbyLayout.get(id)
	return piece, LobbyLayout.frame(piece)
end

function Kit.tag(instance: Instance, tag: string)
	instance:AddTag(tag)
end

---------------------------------------------------------------- blocks

function Kit.block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Style.block(parent, cf, size, color, material, props)
end

-- Tiny detail block (no collision, no shadow).
function Kit.bit(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return Style.block(parent, cf, size, color, material, Style.tiny())
end

-- Neon glow block (no collision, no shadow).
function Kit.glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Style.block(parent, cf, size, color, Kit.NEON, Style.tiny())
end

--[[
	A beam from world point `a` to world point `b` with a (width, depth)
	cross-section. `side` is a hint for the beam's local X axis (default:
	horizontal, perpendicular to the beam).
]]
function Kit.beam(parent: Instance, a: Vector3, b: Vector3, width: number, depth: number, color: Color3, props: Opts?, side: Vector3?): Part
	local delta = b - a
	local length = delta.Magnitude
	local look = delta / length
	local hint = side or Vector3.new(-look.Z, 0, look.X)
	if hint.Magnitude < 1e-3 then
		hint = Vector3.new(1, 0, 0)
	end
	local x = hint - look * hint:Dot(look)
	if x.Magnitude < 1e-3 then
		x = Vector3.new(0, 0, 1) - look * look.Z
	end
	x = x.Unit
	local z = -look
	local y = z:Cross(x)
	local cf = CFrame.fromMatrix((a + b) / 2, x, y, z)
	return Style.block(parent, cf, Vector3.new(width, depth, length), color, nil, props or Style.tiny())
end

-- Upright cylinder (round things only: barrels, discs, posts of round stalls).
function Kit.disc(
	parent: Instance,
	position: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	return Geo.cylinder(parent, position, height, diameter, color, material or Kit.SMOOTH, props or Style.decor())
end

-- Cylinder whose axis is the frame's Z axis (a disc facing the frame's front).
function Kit.faceDisc(
	parent: Instance,
	cf: CFrame,
	thickness: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	local p: Opts = props or Style.tiny()
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	p.Size = Vector3.new(thickness, diameter, diameter)
	p.Color = color
	p.Material = material or Kit.SMOOTH
	return Geo.make("Part", p, parent)
end

function Kit.ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Geo.ball(parent, position, diameter, color, material or Kit.SMOOTH, props or Style.tiny())
end

-- A filled triangle (two wedges); the face lies on a-b-c, `normal` = the visible side.
function Kit.tri(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	normal: Vector3,
	props: Opts?
): { WedgePart }
	return Geo.triangle(parent, a, b, c, thickness, color, Kit.SMOOTH, normal, props or Style.tiny({ CastShadow = true }))
end

-- Axis-aligned crate (no random yaw, so it stays inside tight footprints).
function Kit.crate(parent: Instance, base: CFrame, size: number, rng: Rng.Rng, color: Color3?): Model
	local m = Style.model("Crate", parent)
	local s = size
	Style.block(m, base * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Style.vary(color or C.WoodLight, rng, 0.05))
	Kit.bit(m, base * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.1, s * 0.2, s + 0.1), C.WoodDark)
	Kit.bit(m, base * CFrame.new(0, s / 2, 0), Vector3.new(s * 0.2, s + 0.1, s + 0.1), C.WoodDark)
	return m
end

---------------------------------------------------------------- signs

--[[
	Sign with a custom neon frame color (the Style kit's Glow signs are
	always blue): board, 4 neon frame bars and a SurfaceGui label.
	opts: Font, TextColor, Stroke (text outline color), DoubleSided, Depth.
]]
function Kit.neonSign(
	parent: Instance,
	cf: CFrame,
	text: string,
	width: number,
	height: number,
	board: Color3,
	frame: Color3,
	opts: Opts?
): Part
	local o: Opts = opts or {}
	local depth = o.Depth or 0.6
	local part = Style.block(parent, cf, Vector3.new(width, height, depth), board, nil, Style.decor())
	part.Name = "Sign"
	local t = math.clamp(math.min(width, height) * 0.09, 0.25, 0.6)
	local z = -depth / 2 - 0.05
	Kit.glow(parent, cf * CFrame.new(0, height / 2 - t / 2, z), Vector3.new(width + 0.2, t, 0.3), frame)
	Kit.glow(parent, cf * CFrame.new(0, -height / 2 + t / 2, z), Vector3.new(width + 0.2, t, 0.3), frame)
	Kit.glow(parent, cf * CFrame.new(-width / 2 + t / 2, 0, z), Vector3.new(t, height - 2 * t, 0.3), frame)
	Kit.glow(parent, cf * CFrame.new(width / 2 - t / 2, 0, z), Vector3.new(t, height - 2 * t, 0.3), frame)
	local faces = { Enum.NormalId.Front }
	if o.DoubleSided then
		table.insert(faces, Enum.NormalId.Back)
	end
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "FrontText" else "BackText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.86, 0.74)
		label.Position = UDim2.fromScale(0.07, 0.13)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = o.TextColor or C.GlowText
		label.TextStrokeColor3 = o.Stroke or frame
		label.TextStrokeTransparency = 0.4
		label.FontFace = Font.fromEnum(o.Font or Style.SignFont)
		label.Parent = gui
	end
	return part
end

--[[
	The concept's glowing blue shop sign: a Style Glow sign set into a
	chunky stone surround with two stone feet. `cf` = sign center.
]]
function Kit.glowSign(parent: Instance, cf: CFrame, text: string, width: number, height: number, rng: Rng.Rng, feet: boolean?): Part
	local board = Style.sign(parent, cf, text, width, height, { Kind = "Glow" })
	Style.block(parent, cf * CFrame.new(0, 0, 0.35), Vector3.new(width + 1.1, height + 1.1, 0.5), Style.vary(C.StoneDark, rng, 0.03))
	Kit.bit(parent, cf * CFrame.new(0, height / 2 + 0.75, 0.35), Vector3.new(width + 1.5, 0.4, 0.9), C.Stone)
	if feet ~= false then
		for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
			Style.block(parent, cf * CFrame.new(x, -height / 2 - 0.75, 0.35), Vector3.new(1.2, 1, 0.8), C.StoneDark)
		end
	end
	return board
end

---------------------------------------------------------------- people

local function nameTag(head: BasePart, text: string)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 40)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = C.LeafYellowLight
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Style.LabelFont)
	label.Parent = tag
	tag.Parent = head
end

--[[
	Blocky townsperson (Kenney Mini Characters proportions: chunky head and
	body, short limbs). ~14-20 parts, decor only. opts:
	  Name (model name), Tag (name tag text, optional)
	  Shirt, Pants, Boots, Skin
	  Beard (Color3), Hair (Color3)
	  Helmet (Color3) + HelmetLamp (boolean): miner's hard hat with a head lamp
	  Overalls (Color3): bib + straps over the shirt (pants take the same color)
	  Apron (Color3), Goggles (Color3), Hat (Color3)
	  Robe (Color3): long robe instead of legs (mystics)
	  Wave (boolean): right arm raised
]]
function Kit.npc(parent: Instance, base: CFrame, opts: Opts): Model
	local m = Style.model(opts.Name or "Npc", parent)
	local skin = opts.Skin or Kit.Skin
	local shirt = opts.Shirt or C.AwningRed
	local pants = opts.Overalls or opts.Pants or C.WaterDeep
	local p = Style.decor({ CastShadow = true })
	if opts.Robe then
		Style.block(m, base * CFrame.new(0, 1.55, 0), Vector3.new(2.1, 3.1, 1.2), opts.Robe, nil, p)
		Kit.bit(m, base * CFrame.new(0, 0.2, 0), Vector3.new(2.3, 0.4, 1.4), opts.Robe:Lerp(Kit.Dark, 0.35))
	else
		for _, x in { -0.5, 0.5 } do
			Style.block(m, base * CFrame.new(x, 0.3, -0.12), Vector3.new(1, 0.6, 1.25), opts.Boots or C.WoodDark, nil, p)
			Style.block(m, base * CFrame.new(x, 1.3, 0), Vector3.new(0.9, 1.45, 0.9), pants, nil, p)
		end
	end
	local torso = Style.block(m, base * CFrame.new(0, 3.05, 0), Vector3.new(2, 2, 1.05), shirt, nil, p)
	torso.Name = "Torso"
	Kit.bit(m, base * CFrame.new(0, 2.2, 0), Vector3.new(2.06, 0.32, 1.1), opts.Belt or C.WoodDark)
	if opts.Overalls then
		Kit.bit(m, base * CFrame.new(0, 2.85, -0.53), Vector3.new(1.3, 1.3, 0.1), opts.Overalls)
		for _, x in { -0.62, 0.62 } do
			Kit.bit(m, base * CFrame.new(x, 3.65, -0.53), Vector3.new(0.3, 0.75, 0.1), opts.Overalls)
		end
		Kit.bit(m, base * CFrame.new(0, 2.95, -0.6), Vector3.new(0.5, 0.35, 0.06), C.Brass)
	end
	if opts.Apron then
		Kit.bit(m, base * CFrame.new(0, 2.45, -0.58), Vector3.new(1.6, 2.1, 0.1), opts.Apron)
	end
	-- arms and hands
	for _, x in { -1.48, 1.48 } do
		if opts.Wave and x < 0 then
			Style.block(m, base * CFrame.new(x, 4.3, 0), Vector3.new(0.85, 1.9, 0.85), shirt, nil, p)
			Kit.bit(m, base * CFrame.new(x, 5.5, 0), Vector3.new(0.75, 0.6, 0.75), skin)
		else
			Style.block(m, base * CFrame.new(x, 3.1, 0), Vector3.new(0.85, 1.9, 0.85), shirt, nil, p)
			Kit.bit(m, base * CFrame.new(x, 1.9, 0), Vector3.new(0.75, 0.6, 0.75), skin)
		end
	end
	local head = Style.block(m, base * CFrame.new(0, 4.8, 0), Vector3.new(1.45, 1.45, 1.45), skin, nil, p)
	head.Name = "Head"
	for _, x in { -0.32, 0.32 } do
		Kit.bit(m, base * CFrame.new(x, 4.95, -0.74), Vector3.new(0.2, 0.3, 0.05), Kit.Dark)
	end
	if opts.Beard then
		Kit.bit(m, base * CFrame.new(0, 4.32, -0.62), Vector3.new(1.5, 0.75, 0.4), opts.Beard)
		Kit.bit(m, base * CFrame.new(0, 4.62, -0.78), Vector3.new(0.95, 0.22, 0.15), opts.Beard)
	end
	if opts.Hair then
		Kit.bit(m, base * CFrame.new(0, 5.42, 0.1), Vector3.new(1.55, 0.36, 1.35), opts.Hair)
	end
	if opts.Goggles then
		Kit.bit(m, base * CFrame.new(0, 5.25, -0.7), Vector3.new(1.5, 0.3, 0.15), opts.Goggles)
		for _, x in { -0.34, 0.34 } do
			Kit.glow(m, base * CFrame.new(x, 5.25, -0.79), Vector3.new(0.4, 0.26, 0.06), C.CrystalCyan)
		end
	end
	if opts.Helmet then
		Style.block(m, base * CFrame.new(0, 5.75, 0), Vector3.new(1.6, 0.6, 1.6), opts.Helmet, nil, p)
		Kit.bit(m, base * CFrame.new(0, 5.5, -0.15), Vector3.new(1.85, 0.16, 1.95), opts.Helmet:Lerp(Kit.Dark, 0.2))
		if opts.HelmetLamp then
			Kit.bit(m, base * CFrame.new(0, 5.72, -0.85), Vector3.new(0.62, 0.55, 0.15), C.Iron)
			Kit.glow(m, base * CFrame.new(0, 5.72, -0.95), Vector3.new(0.42, 0.38, 0.08), C.Lamp)
		end
	elseif opts.Hat then
		Kit.bit(m, base * CFrame.new(0, 5.6, 0), Vector3.new(1.9, 0.22, 1.9), opts.Hat)
		Style.block(m, base * CFrame.new(0, 6.05, 0.05), Vector3.new(1.15, 0.8, 1.15), opts.Hat, nil, p)
		Kit.bit(m, base * CFrame.new(0.05, 6.65, 0.1), Vector3.new(0.6, 0.45, 0.6), opts.Hat)
	end
	m.PrimaryPart = torso
	if opts.Tag then
		nameTag(head, opts.Tag)
	end
	return m
end

--[[
	Golem figure (original ore/metal golems in Kenney Mini Characters
	proportions: big head, short body, stubby limbs). scale 1 = ~2.6 studs.
	opts: Body, Accent, Eyes (neon), Gem (neon chest/head crystal),
	Helmet (Color3), Moss (boolean: grass cap). 9-12 parts.
]]
function Kit.golem(parent: Instance, base: CFrame, s: number, opts: Opts): Model
	local m = Style.model("Golem", parent)
	local body: Color3 = opts.Body or C.IronLight
	local accent: Color3 = opts.Accent or body:Lerp(Kit.Dark, 0.35)
	-- only big golems cast shadows (small details: no shadow)
	local p = Style.tiny({ CastShadow = s >= 1.2 })
	for _, x in { -0.32, 0.32 } do
		Style.block(m, base * CFrame.new(x * s, 0.3 * s, 0), Vector3.new(0.48, 0.6, 0.58) * s, accent, nil, p)
	end
	local torso = Style.block(m, base * CFrame.new(0, 0.98 * s, 0), Vector3.new(1.2, 0.8, 0.85) * s, body, nil, p)
	torso.Name = "Body"
	for _, x in { -0.8, 0.8 } do
		Style.block(m, base * CFrame.new(x * s, 0.9 * s, -0.05 * s), Vector3.new(0.4, 0.85, 0.5) * s, accent, nil, p)
	end
	Style.block(m, base * CFrame.new(0, 1.92 * s, 0), Vector3.new(1.4, 1.1, 1.2) * s, body, nil, p)
	-- face plate and glowing visor eyes
	Kit.bit(m, base * CFrame.new(0, 1.86 * s, -0.61 * s), Vector3.new(1.1, 0.62, 0.06) * s, accent)
	Kit.glow(m, base * CFrame.new(0, 1.92 * s, -0.66 * s), Vector3.new(0.86, 0.2, 0.06) * s, opts.Eyes or C.CrystalCyan)
	if opts.Gem then
		Kit.glow(m, base * CFrame.new(0, 1.0 * s, -0.45 * s) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.3, 0.3, 0.08) * s, opts.Gem)
		Kit.glow(
			m,
			base * CFrame.new(0.38 * s, 2.62 * s, 0.1 * s) * CFrame.Angles(0, math.pi / 4, 0.25),
			Vector3.new(0.28, 0.5, 0.28) * s,
			opts.Gem
		)
	end
	if opts.Helmet then
		Kit.bit(m, base * CFrame.new(0, 2.6 * s, 0), Vector3.new(1.5, 0.32, 1.3) * s, opts.Helmet)
		Kit.bit(m, base * CFrame.new(0, 2.5 * s, -0.6 * s), Vector3.new(1.5, 0.14, 0.3) * s, opts.Helmet:Lerp(Kit.Dark, 0.2))
	elseif opts.Moss then
		Kit.bit(m, base * CFrame.new(-0.1 * s, 2.55 * s, 0.05 * s), Vector3.new(1.2, 0.2, 1.0) * s, C.GrassLight)
	end
	m.PrimaryPart = torso
	return m
end

-- Golem looks used on the capsule stall shelves (original ore golems).
Kit.GolemLooks = {
	{ Body = C.IronLight, Accent = C.Iron, Eyes = C.CrystalCyan, Helmet = C.LeafYellow }, -- silver miner golem
	{ Body = C.Gold, Accent = C.Brass, Eyes = C.Fire, Gem = C.CrystalPink }, -- gold golem
	{ Body = C.Copper, Accent = C.LeafOrangeDark, Eyes = C.CrystalCyan }, -- copper golem
	{ Body = C.StoneDark, Accent = C.StoneDeep, Eyes = C.CrystalPurple, Gem = C.CrystalPurple }, -- amethyst golem
	{ Body = C.StoneDeep, Accent = C.Iron, Eyes = C.Ember, Gem = C.Ember }, -- ember golem
	{ Body = C.Stone, Accent = C.StoneDark, Eyes = C.Lamp, Moss = true }, -- mossy stone golem
	{ Body = C.LeafGreenDark, Accent = C.StoneDark, Eyes = C.FireCore, Gem = C.CrystalCyan }, -- jade golem
} :: { Opts }

---------------------------------------------------------------- lamps

-- Small hanging lamp (glow only unless `range` is given). `top` = hook point.
function Kit.hangingLamp(parent: Instance, top: CFrame, color: Color3?, range: number?): Part
	local m = Style.lantern(parent, top, { Kind = "Hanging", Color = color, Light = range ~= nil, Range = range or 16 })
	return m.PrimaryPart :: Part
end

-- Wooden lantern post with a lamp box on top (3 parts). Returns the glow.
function Kit.lampPost(parent: Instance, base: CFrame, height: number, color: Color3?): Part
	Style.block(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(0.9, height, 0.9), C.WoodDark)
	local glow = Kit.glow(parent, base * CFrame.new(0, height + 0.45, 0), Vector3.new(0.9, 0.9, 0.9), color or C.Lamp)
	glow.Name = "LanternGlow"
	Kit.bit(parent, base * CFrame.new(0, height + 1.05, 0), Vector3.new(1.3, 0.3, 1.3), C.Iron)
	return glow
end

return Kit
