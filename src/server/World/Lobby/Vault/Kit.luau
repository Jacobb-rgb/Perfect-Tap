--[[
	Local helpers of the Vault package (the Blaster Vault shop, its giant
	statues and jungle trees): the vault palette, part makers with the lobby's
	collision presets, and the small set pieces it repeats (glass crystals,
	crests, banners, light blasters, cases).

	The look follows the owner-approved preview (tools/lune/lib/blaster_shop.luau,
	"Forge Vault") but is built for the game's budget: fewer, bigger stones,
	hand-built blasters and cases instead of the Kenney part rebuilds.

	Frames: "base" CFrames are bottom centers; a blaster's frame has its
	barrel along -Z and +Y up. Pure builders: Instance creation only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BlasterData = require(Shared.Config.BlasterData)
local CaseBuilder = require(Shared.Builders.CaseBuilder)
local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)

local Kit = {}

type Opts = { [string]: any }

local rgb = Color3.fromRGB

Kit.SMOOTH = Enum.Material.SmoothPlastic
Kit.SLATE = Enum.Material.Slate
Kit.MARBLE = Enum.Material.Marble
Kit.NEON = Enum.Material.Neon
Kit.METAL = Enum.Material.Metal
Kit.GLASS = Enum.Material.Glass
Kit.FABRIC = Enum.Material.Fabric
Kit.CONCRETE = Enum.Material.Concrete

Kit.C = {
	-- stone (darker than the preview: Roblox renders Slate much lighter)
	Core = rgb(40, 36, 48),
	Tiles = { rgb(94, 88, 106), rgb(82, 76, 94), rgb(104, 98, 116), rgb(74, 70, 86) },
	StoneLight = rgb(120, 114, 134),
	StoneDark = rgb(62, 58, 74),
	Moss = rgb(78, 108, 70),
	Slate = rgb(52, 48, 60),
	-- roof, wood, cloth, metal
	Roof = { rgb(84, 54, 50), rgb(96, 62, 56), rgb(72, 46, 44) },
	RoofEdge = rgb(46, 42, 56),
	Wood = rgb(108, 64, 42),
	WoodDark = rgb(70, 44, 30),
	Purple = rgb(88, 46, 132),
	PurpleDark = rgb(58, 30, 88),
	Red = rgb(128, 30, 40),
	Gold = rgb(222, 172, 72),
	Iron = rgb(40, 38, 44),
	Steel = rgb(70, 74, 90),
	SteelDark = rgb(48, 50, 60),
	Brass = rgb(196, 152, 66),
	Paper = rgb(226, 200, 146),
	Ink = rgb(96, 66, 42),
	InkRed = rgb(168, 44, 34),
	GlassTint = rgb(150, 205, 235),
	Candle = rgb(236, 224, 200),
	-- glows (Neon)
	Fire = rgb(255, 140, 50),
	FireCore = rgb(255, 200, 110),
	Lava = rgb(255, 96, 30),
	LavaCore = rgb(255, 200, 90),
	Flame = rgb(255, 176, 80),
	Holo = rgb(255, 120, 160),
	OrangeCrystal = rgb(240, 110, 50),
	OrangeCore = rgb(200, 70, 20),
	PinkCrystal = rgb(255, 50, 112),
	BlueCrystal = rgb(122, 104, 255),
	Gem = rgb(190, 90, 255),
	-- stone statues
	StatueStone = { rgb(112, 108, 116), rgb(98, 94, 102), rgb(126, 122, 130), rgb(86, 82, 92) },
	StatueDark = rgb(64, 60, 70),
	-- jungle trees
	Bark = rgb(104, 76, 50),
	BarkDark = rgb(74, 52, 36),
	Leaf = rgb(48, 124, 42),
	LeafLight = rgb(78, 158, 56),
	Vine = rgb(38, 102, 34),
	Fern = { rgb(56, 138, 50), rgb(70, 158, 58), rgb(46, 116, 42) },
	Cocoa = rgb(176, 104, 50),
}

local C = Kit.C

export type LevelLook = { Body: Color3, Glow: Color3, Magma: boolean }

--[[
	The looks of the ten blaster levels for the display cases and rims: the
	cases the shop sells (BlasterData.Vault.Ores in CaseBuilder's colours),
	so the cases behind the counter match the shop window and the opening.
]]
Kit.Levels = {} :: { LevelLook }
for level = 1, BlasterData.MaxLevel do
	local ore = BlasterData.vaultOre(level)
	local color = BlasterData.skin(ore)
	local _, _, glow, hot = CaseBuilder.look(ore)
	table.insert(Kit.Levels, { Body = color, Glow = glow, Magma = hot })
end

---------------------------------------------------------------- frames

-- The frame of a lobby piece (bottom center, LookVector = Facing), or `fallback` before the piece exists.
function Kit.frame(id: string, fallback: CFrame): CFrame
	local piece = LobbyLayout.ById[id]
	if piece then
		return LobbyLayout.frame(piece)
	end
	return fallback
end

-- A deterministic generator for one sub-part of the package.
function Kit.rng(name: string): Rng.Rng
	return Rng.new("Lobby/Vault/" .. name)
end

---------------------------------------------------------------- parts

Kit.solid = Style.solid
Kit.decor = Style.decor
Kit.ghost = Style.ghost
Kit.tiny = Style.tiny

-- A block (collides, not raycast unless `props` says so).
function Kit.block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Geo.block(parent, cf, size, color, material or Kit.SMOOTH, props or Style.decor())
end

-- A small detail block (no collision, no shadow).
function Kit.bit(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return Geo.block(parent, cf, size, color, material or Kit.SMOOTH, Style.tiny())
end

-- A neon glow block (no collision, no shadow).
function Kit.glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Geo.block(parent, cf, size, color, Kit.NEON, Style.tiny())
end

-- A cylinder whose axis is cf's local X.
function Kit.cyl(
	parent: Instance,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	local o = props or Style.tiny()
	o.Shape = Enum.PartType.Cylinder
	return Geo.block(parent, cf, Vector3.new(length, diameter, diameter), color, material or Kit.SMOOTH, o)
end

-- A cylinder standing upright (its axis along cf's local Y).
function Kit.drum(
	parent: Instance,
	cf: CFrame,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	return Kit.cyl(parent, cf * CFrame.Angles(0, 0, math.pi / 2), height, diameter, color, material, props)
end

function Kit.ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?, props: Opts?): Part
	local o = props or Style.tiny()
	o.Shape = Enum.PartType.Ball
	return Geo.block(parent, CFrame.new(position), Vector3.new(diameter, diameter, diameter), color, material or Kit.SMOOTH, o)
end

function Kit.wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): WedgePart
	return Geo.wedge(parent, cf, size, color, material or Kit.SMOOTH, props or Style.tiny())
end

-- A filled triangle (two wedges) `thickness` thick behind the face whose normal is `normal`.
function Kit.tri(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	normal: Vector3?,
	props: Opts?
): { WedgePart }
	return Geo.triangle(parent, a, b, c, thickness, color, material or Kit.SMOOTH, normal, props or Style.ghost())
end

-- A bar from world point a to world point b, w wide and d deep (its depth along `up`).
function Kit.beam(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	w: number,
	d: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?,
	up: Vector3?
): Part
	local cf = CFrame.lookAt((a + b) / 2, b, up or Vector3.new(0, 1, 0))
	return Geo.block(parent, cf, Vector3.new(w, d, (b - a).Magnitude), color, material or Kit.SMOOTH, props or Style.tiny())
end

-- An invisible part with a PointLight (count every light against the package budget).
function Kit.light(parent: Instance, position: Vector3, color: Color3, range: number, brightness: number): PointLight
	local holder = Geo.block(parent, CFrame.new(position), Vector3.new(0.2, 0.2, 0.2), color, Kit.SMOOTH, Style.tiny({ Transparency = 1 }))
	holder.Name = "LightHolder"
	return Style.light(holder, color, range, brightness)
end

--[[
	A text plate: a block with the text on its +Z face (SurfaceGui Back).
	font defaults to the lobby label font; the text has a dark stroke.
]]
function Kit.label(parent: Instance, cf: CFrame, size: Vector3, text: string, plate: Color3, ink: Color3, font: Enum.Font?): Part
	local p = Kit.bit(parent, cf, size, plate)
	p.Name = "Label"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(0.94, 0.86)
	t.Position = UDim2.fromScale(0.03, 0.07)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = ink
	t.TextStrokeColor3 = rgb(20, 8, 6)
	t.TextStrokeTransparency = 0.35
	t.FontFace = Font.fromEnum(font or Style.LabelFont)
	t.Parent = gui
	return p
end

---------------------------------------------------------------- crystals

--[[
	A glass crystal shard with a glowing core (a whole neon cluster blooms
	into a white blob in Roblox): a square column turned 45 degrees with a
	chisel tip. base = its foot, up = its direction. 4 parts.
]]
function Kit.glassShard(parent: Instance, base: Vector3, up: Vector3, s: number, length: number, color: Color3, core: Color3): { BasePart }
	local hint = if math.abs(up.X) > 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local right = (hint - up * hint:Dot(up)).Unit
	local cf = CFrame.fromMatrix(base, right, up) * CFrame.Angles(0, math.pi / 4, 0)
	local colL = length * 0.66
	local tipL = length - colL
	local glass = Style.tiny({ Transparency = 0.3, Reflectance = 0.15 })
	local parts: { BasePart } = {
		Geo.block(parent, cf * CFrame.new(0, colL / 2, 0), Vector3.new(s, colL, s), color, Kit.GLASS, glass),
		Geo.wedge(
			parent,
			cf * CFrame.new(0, colL + tipL / 2, -s / 4),
			Vector3.new(s, tipL, s / 2),
			color,
			Kit.GLASS,
			Style.tiny({ Transparency = 0.3 })
		),
		Geo.wedge(
			parent,
			cf * CFrame.new(0, colL + tipL / 2, s / 4) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(s, tipL, s / 2),
			color,
			Kit.GLASS,
			Style.tiny({ Transparency = 0.3 })
		),
		Kit.glow(parent, cf * CFrame.new(0, colL * 0.5, 0), Vector3.new(s * 0.42, colL * 0.82, s * 0.42), core),
	}
	return parts
end

-- A cluster of `count` (2-4) glass shards leaning out along `side`.
function Kit.gemCluster(
	parent: Instance,
	base: Vector3,
	up: Vector3,
	side: Vector3,
	size: number,
	color: Color3,
	core: Color3,
	count: number?
)
	local n = count or 3
	Kit.glassShard(parent, base - up * 0.04, up, size * 0.3, size, color, core)
	Kit.glassShard(parent, base + side * size * 0.2 - up * 0.04, (up + side * 0.75).Unit, size * 0.24, size * 0.66, color, core)
	if n >= 3 then
		Kit.glassShard(parent, base - side * size * 0.18 - up * 0.04, (up - side * 0.6).Unit, size * 0.2, size * 0.5, color, core)
	end
	if n >= 4 then
		local back = up:Cross(side).Unit
		Kit.glassShard(parent, base + back * size * 0.16, (up + back * 0.55).Unit, size * 0.18, size * 0.45, color, core)
	end
end

-- A small neon shard (a column with a pyramid-ish tip, 2 parts).
function Kit.shard(parent: Instance, base: Vector3, up: Vector3, s: number, length: number, color: Color3)
	local hint = if math.abs(up.X) > 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local right = (hint - up * hint:Dot(up)).Unit
	local cf = CFrame.fromMatrix(base, right, up) * CFrame.Angles(0, math.pi / 4, 0)
	Kit.glow(parent, cf * CFrame.new(0, length * 0.35, 0), Vector3.new(s, length * 0.7, s), color)
	Kit.glow(
		parent,
		cf * CFrame.new(0, length * 0.82, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
		Vector3.new(s * 0.7, s * 0.7, s * 0.7),
		color
	)
end

---------------------------------------------------------------- crest and banner

-- The vault's gold crest on a surface facing +Z (cf = its center, s = its size). `full`: 11 parts, else 5.
function Kit.crest(parent: Instance, cf: CFrame, s: number, full: boolean?)
	local function g(x: number, y: number, w: number, h: number, rot: number)
		Kit.bit(parent, cf * CFrame.new(x * s, y * s, 0.06) * CFrame.Angles(0, 0, rot), Vector3.new(w * s, h * s, 0.1), C.Gold, Kit.METAL)
	end
	g(0, 0, 0.36, 0.36, math.pi / 4)
	g(0, 0.62, 0.16, 0.5, 0)
	g(0, -0.6, 0.14, 0.4, 0)
	for _, sx in { -1, 1 } do
		g(sx * 0.62, 0.22, 0.6, 0.14, sx * 0.6)
	end
	if full then
		for i = 0, 3 do
			local a = math.pi / 4 + i * math.pi / 2
			g(math.cos(a + math.pi / 4) * 0.32, math.sin(a + math.pi / 4) * 0.32, 0.9, 0.14, a)
		end
		for _, sx in { -1, 1 } do
			g(sx * 0.92, 0.52, 0.34, 0.12, sx * 1.2)
		end
	end
end

--[[
	A hanging purple banner with a gold trim and the gold crest: an iron rod
	with gold finials, the cloth ending in a point. cf = the rod's center,
	facing +Z. About 14 parts.
]]
function Kit.banner(parent: Instance, cf: CFrame, w: number, h: number, cloth: Color3?)
	local color = cloth or C.Purple
	local pointH = w * 0.45
	local body = h - pointH
	Kit.cyl(parent, cf, w + 0.9, 0.35, C.Iron, Kit.METAL)
	for _, sx in { -1, 1 } do
		Kit.ball(parent, (cf * CFrame.new(sx * (w / 2 + 0.5), 0, 0)).Position, 0.55, C.Gold, Kit.METAL)
	end
	local clothPart = Kit.bit(parent, cf * CFrame.new(0, -body / 2 - 0.15, 0), Vector3.new(w, body, 0.14), color, Kit.FABRIC)
	clothPart.Name = "BannerCloth"
	Kit.tri(
		parent,
		(cf * CFrame.new(-w / 2, -body - 0.15, 0.07)).Position,
		(cf * CFrame.new(w / 2, -body - 0.15, 0.07)).Position,
		(cf * CFrame.new(0, -h - 0.15, 0.07)).Position,
		0.14,
		color,
		Kit.FABRIC,
		cf.LookVector * -1,
		Style.tiny()
	)
	for _, sx in { -1, 1 } do
		Kit.bit(parent, cf * CFrame.new(sx * (w / 2 - 0.12), -body / 2 - 0.15, 0.09), Vector3.new(0.16, body, 0.04), C.Gold, Kit.METAL)
	end
	Kit.bit(parent, cf * CFrame.new(0, -0.6, 0.09), Vector3.new(w, 0.16, 0.04), C.Gold, Kit.METAL)
	Kit.crest(parent, cf * CFrame.new(0, -body * 0.52, 0.07), w * 0.42, false)
end

---------------------------------------------------------------- blasters and cases

export type BlasterColors = { Body: Color3, Dark: Color3, Glow: Color3, Metal: Color3 }

-- A lava blaster (the Magmacore look) and a galaxy one (Heartstone), for decoration.
Kit.LavaBlaster = { Body = rgb(30, 26, 27), Dark = rgb(28, 29, 34), Glow = rgb(255, 150, 50), Metal = rgb(70, 74, 84) } :: BlasterColors
Kit.GalaxyBlaster = { Body = rgb(92, 14, 52), Dark = rgb(28, 29, 34), Glow = rgb(255, 120, 160), Metal = rgb(70, 74, 84) } :: BlasterColors
Kit.StoneBlaster =
	{ Body = rgb(104, 104, 110), Dark = rgb(80, 80, 86), Glow = rgb(104, 104, 110), Metal = rgb(92, 92, 98) } :: BlasterColors

--[[
	A light decorative blaster after the Kenney Blaster Kit's long rifle
	(blaster-e) in the Ore Glow style: a matte body with glowing seams, a
	scope with a glowing lens, a muzzle brake, a crystal on top. cf = its
	center (barrel along -Z, +Y up), length = its total length. ~22 parts.
	Returns the right hand's grip point (world).
]]
function Kit.blaster(parent: Instance, cf: CFrame, length: number, colors: BlasterColors, crystal: boolean?): Vector3
	local L = length
	local glowIsBody = colors.Glow == colors.Body
	local function b(x: number, y: number, z: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material?)
		return Kit.bit(parent, cf * CFrame.new(x * L, y * L, z * L), Vector3.new(sx * L, sy * L, sz * L), color, material)
	end
	local function glow(x: number, y: number, z: number, sx: number, sy: number, sz: number)
		if glowIsBody then
			return b(x, y, z, sx, sy, sz, colors.Dark)
		end
		return Kit.glow(parent, cf * CFrame.new(x * L, y * L, z * L), Vector3.new(sx * L, sy * L, sz * L), colors.Glow)
	end
	local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
	-- receiver, top shroud, handguard, lower
	b(0, 0, 0.02, 0.075, 0.11, 0.36, colors.Body)
	b(0, 0.068, -0.02, 0.064, 0.03, 0.3, colors.Dark)
	b(0, 0.005, -0.27, 0.068, 0.085, 0.2, colors.Body)
	b(0, -0.06, 0.04, 0.06, 0.03, 0.26, colors.Dark)
	glow(0, 0.02, 0.02, 0.078, 0.01, 0.34)
	glow(0, 0.005, -0.27, 0.071, 0.012, 0.16)
	-- barrel, muzzle brake with a glowing bore
	Kit.cyl(parent, cf * CFrame.new(0, 0.01 * L, -0.46 * L) * ALONG_Z, 0.18 * L, 0.03 * L, colors.Metal, Kit.METAL)
	b(0, 0.01, -0.575, 0.05, 0.06, 0.06, colors.Dark)
	glow(0, 0.01, -0.607, 0.024, 0.024, 0.01)
	-- scope on two mounts, a glowing lens
	Kit.cyl(parent, cf * CFrame.new(0, 0.12 * L, 0.0) * ALONG_Z, 0.22 * L, 0.045 * L, colors.Dark)
	glow(0, 0.12, -0.112, 0.034, 0.034, 0.008)
	for _, z in { -0.06, 0.07 } do
		b(0, 0.095, z, 0.025, 0.03, 0.025, colors.Dark)
	end
	-- grip (tilted back), magazine, trigger guard
	b(0, -0.11, 0.13, 0.05, 0.13, 0.055, colors.Dark)
	b(0, -0.12, -0.07, 0.045, 0.11, 0.06, colors.Body)
	b(0, -0.07, 0.06, 0.02, 0.012, 0.08, colors.Dark)
	-- stock and butt plate, a glowing core on the side
	b(0, -0.005, 0.32, 0.056, 0.085, 0.22, colors.Body)
	b(0, -0.01, 0.44, 0.06, 0.11, 0.03, colors.Dark)
	glow(0, 0.0, 0.3, 0.06, 0.012, 0.16)
	Kit.cyl(
		parent,
		cf * CFrame.new(0, 0.0, 0.1 * L),
		0.081 * L,
		0.04 * L,
		if glowIsBody then colors.Dark else colors.Glow,
		if glowIsBody then Kit.SMOOTH else Kit.NEON
	)
	if crystal and not glowIsBody then
		local top = (cf * CFrame.new(0, 0.09 * L, -0.15 * L)).Position
		Kit.shard(parent, top, cf.UpVector, 0.025 * L, 0.09 * L, colors.Glow)
		Kit.shard(parent, top + cf.LookVector * 0.03 * L, (cf.UpVector - cf.LookVector * 0.6).Unit, 0.02 * L, 0.06 * L, colors.Glow)
	end
	return (cf * CFrame.new(0, -0.1 * L, 0.13 * L)).Position
end

--[[
	A weapon case in a level's ore look (the Kenney crate silhouette): a dark
	body with an ore-colored band, a lid, a glowing seam and latches, a glowing
	diamond on the lid, ore crystals on top from level 4. cf = its bottom
	center, its length along local X. 12-17 parts.
]]
function Kit.case(parent: Instance, cf: CFrame, length: number, level: number)
	local look = Kit.Levels[math.clamp(level, 1, #Kit.Levels)]
	local L = length
	local w, hb, hl = L * 0.5, L * 0.19, L * 0.14
	local body = if look.Magma then rgb(34, 28, 30) else look.Body:Lerp(rgb(0, 0, 0), 0.62)
	local panel = if look.Magma then rgb(46, 40, 42) else look.Body:Lerp(rgb(0, 0, 0), 0.45)
	Kit.bit(parent, cf * CFrame.new(0, hb / 2, 0), Vector3.new(L, hb, w), body)
	Kit.bit(parent, cf * CFrame.new(0, hb * 0.45, 0), Vector3.new(L + 0.04, hb * 0.18, w + 0.04), look.Glow:Lerp(body, 0.35), Kit.NEON)
	Kit.bit(parent, cf * CFrame.new(0, hb + hl / 2, 0), Vector3.new(L - 0.1, hl, w - 0.1), panel)
	Kit.glow(parent, cf * CFrame.new(0, hb + 0.02, 0), Vector3.new(L + 0.06, 0.07, w + 0.06), look.Glow)
	for _, sx in { -1, 1 } do
		-- latches on the front, straps over the lid, dark end caps
		Kit.glow(parent, cf * CFrame.new(sx * L * 0.3, hb * 0.82, w / 2 + 0.03), Vector3.new(L * 0.12, hb * 0.3, 0.08), look.Glow)
		Kit.bit(parent, cf * CFrame.new(sx * L * 0.3, hb + hl / 2, 0), Vector3.new(L * 0.08, hl + 0.06, w + 0.02), C.SteelDark)
		Kit.bit(parent, cf * CFrame.new(sx * (L / 2 - 0.05), (hb + hl) / 2, 0), Vector3.new(0.14, hb + hl, w + 0.08), C.SteelDark)
	end
	Kit.glow(
		parent,
		cf * CFrame.new(0, hb + hl + 0.03, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(L * 0.13, 0.06, L * 0.13),
		look.Glow
	)
	if level >= 4 then
		local top = (cf * CFrame.new(0, hb + hl, 0)).Position
		Kit.shard(parent, top, cf.UpVector, L * 0.06, L * (0.14 + 0.02 * level), look.Glow)
		if level >= 7 then
			Kit.shard(parent, top + cf.RightVector * L * 0.08, (cf.UpVector + cf.RightVector * 0.6).Unit, L * 0.045, L * 0.12, look.Glow)
			Kit.shard(parent, top - cf.RightVector * L * 0.08, (cf.UpVector - cf.RightVector * 0.6).Unit, L * 0.045, L * 0.1, look.Glow)
		end
	end
end

---------------------------------------------------------------- finishing

-- Scales every part of `root` about `origin` (positions in origin's frame), light ranges too.
function Kit.scale(root: Instance, origin: CFrame, s: number)
	if s == 1 then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = origin:ToObjectSpace(d.CFrame)
			d.Size = d.Size * s
			d.CFrame = origin * CFrame.new(rel.Position * s) * rel.Rotation
		elseif d:IsA("PointLight") then
			d.Range = d.Range * s
		end
	end
end

-- Mobile finish: no shadows from neon or anything smaller than 4 studs; everything anchored.
function Kit.finish(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			local size = d.Size
			if d.Material == Kit.NEON or math.max(size.X, size.Y, size.Z) < 4 then
				d.CastShadow = false
			end
		end
	end
end

return Kit
