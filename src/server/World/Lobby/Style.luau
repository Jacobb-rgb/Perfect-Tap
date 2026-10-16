--[[
	Lobby style kit: the shared palette and building blocks of the town
	lobby, so all five lobby packages share one look (docs/ART_DIRECTION.md).

	Pure builders: only Instance creation (no services, no events), so the
	Lune tools can bake and preview them. Every helper takes a parent and a
	frame; "base" frames are the bottom center with LookVector = front.

	Look rules in short:
	- chunky voxel-ish blocks, axis-aligned to the piece's frame (quarter
	  turns only); rocks, crystals and loot are the only tilted things
	- flat SmoothPlastic colors with small shade variation (Style.vary),
	  Neon for every glow, Metal only for forge iron
	- small details: no collision, no shadow (Style.tiny)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Props = require(script.Parent.Parent.Props)

local Style = {}

type Opts = { [string]: any }

local rgb = Color3.fromRGB
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

---------------------------------------------------------------- palette

Style.C = {
	-- ground
	Grass = rgb(104, 178, 62),
	GrassLight = rgb(142, 204, 78),
	GrassDark = rgb(66, 138, 52),
	Dirt = rgb(138, 98, 62),
	DirtDark = rgb(102, 72, 48),
	DirtLight = rgb(176, 132, 86),
	Sand = rgb(222, 196, 146),
	-- stone (cool blue-grey voxel stone like the concept's cliffs and walls,
	-- warm flagstones for paving)
	Stone = rgb(114, 122, 140),
	StoneDark = rgb(80, 87, 106),
	StoneDeep = rgb(56, 61, 80),
	StoneLight = rgb(160, 167, 180),
	Flag = rgb(178, 152, 126),
	FlagDark = rgb(146, 122, 102),
	FlagLight = rgb(204, 180, 146),
	Cobble = rgb(156, 142, 128),
	CobbleDark = rgb(122, 110, 102),
	-- wood
	WoodDark = rgb(88, 56, 36),
	Wood = rgb(138, 90, 54),
	WoodLight = rgb(186, 130, 78),
	Plank = rgb(164, 110, 64),
	-- roofs
	Roof = rgb(198, 54, 42),
	RoofDark = rgb(150, 38, 32),
	RoofTrim = rgb(104, 30, 26),
	-- metals
	Iron = rgb(64, 64, 72),
	IronLight = rgb(116, 118, 128),
	Copper = rgb(198, 112, 62),
	Brass = rgb(214, 170, 76),
	Gold = rgb(255, 196, 64),
	-- glows (Neon)
	Fire = rgb(255, 140, 32),
	FireCore = rgb(255, 200, 96),
	Ember = rgb(255, 92, 24),
	Molten = rgb(255, 112, 26),
	Lamp = rgb(255, 200, 120),
	CrystalPurple = rgb(180, 96, 255),
	CrystalViolet = rgb(124, 84, 255),
	CrystalBlue = rgb(84, 168, 255),
	CrystalCyan = rgb(96, 232, 255),
	CrystalPink = rgb(255, 110, 200),
	-- signs
	SignBoard = rgb(70, 44, 30),
	SignFrame = rgb(158, 106, 60),
	SignText = rgb(255, 210, 96),
	GlowBoard = rgb(26, 50, 120),
	GlowEdge = rgb(70, 176, 255),
	GlowText = rgb(232, 246, 255),
	TextShadow = rgb(40, 22, 14),
	-- cloth
	AwningPink = rgb(236, 82, 150),
	AwningPurple = rgb(150, 82, 214),
	AwningRed = rgb(214, 56, 50),
	AwningWhite = rgb(250, 242, 236),
	-- water
	Water = rgb(62, 152, 196),
	WaterDeep = rgb(34, 92, 140),
	Falls = rgb(132, 204, 248),
	FallsLight = rgb(200, 236, 255),
	FallsGlint = rgb(150, 226, 255),
	Foam = rgb(242, 250, 255),
	Sea = rgb(44, 112, 156),
	-- foliage
	LeafGreen = rgb(92, 176, 62),
	LeafGreenDark = rgb(54, 130, 52),
	LeafGreenLight = rgb(146, 206, 80),
	LeafPink = rgb(246, 142, 194),
	LeafPinkLight = rgb(255, 188, 222),
	LeafPinkDark = rgb(214, 100, 160),
	LeafRed = rgb(214, 52, 50),
	LeafRedDark = rgb(160, 32, 40),
	LeafRedLight = rgb(240, 98, 80),
	LeafYellow = rgb(248, 204, 62),
	LeafYellowLight = rgb(255, 232, 122),
	LeafOrange = rgb(242, 138, 40),
	LeafOrangeDark = rgb(204, 92, 30),
	Trunk = rgb(110, 72, 44),
	TrunkDark = rgb(80, 52, 34),
	FlowerYellow = rgb(255, 222, 80),
	FlowerWhite = rgb(250, 250, 244),
	FlowerPurple = rgb(182, 112, 255),
	FlowerPink = rgb(255, 124, 176),
	FlowerRed = rgb(240, 70, 60),
	FlowerBlue = rgb(100, 160, 255),
	-- sunset sky (clouds, sun glitter; the Sky package)
	SkyTop = rgb(50, 52, 138),
	SkyPurple = rgb(156, 114, 198),
	SkyHorizon = rgb(255, 162, 86),
	Sun = rgb(255, 222, 150),
	CloudPink = rgb(246, 156, 178),
	CloudPurple = rgb(132, 104, 184),
	CloudOrange = rgb(255, 176, 112),
	CloudLight = rgb(255, 216, 200),
	-- factory accents (Kenney-style machines, see ART_DIRECTION "Machines")
	Hazard = rgb(255, 150, 36),
	HazardDark = rgb(40, 36, 40),
}

local C = Style.C

-- Leaf shades per tree kind: { light, mid, dark }.
Style.TreeKinds = {
	Green = { C.LeafGreenLight, C.LeafGreen, C.LeafGreenDark },
	Pink = { C.LeafPinkLight, C.LeafPink, C.LeafPinkDark },
	Red = { C.LeafRedLight, C.LeafRed, C.LeafRedDark },
	Yellow = { C.LeafYellowLight, C.LeafYellow, C.LeafOrange },
	Orange = { C.LeafYellow, C.LeafOrange, C.LeafOrangeDark },
} :: { [string]: { Color3 } }

Style.SignFont = Enum.Font.LuckiestGuy
Style.LabelFont = Enum.Font.FredokaOne

---------------------------------------------------------------- part presets

local function merge(base: Opts, extra: Opts?): Opts
	if extra then
		for k, v in extra do
			base[k] = v
		end
	end
	return base
end

-- Collides and can be raycast (floors, walls, counters, anything walked on).
function Style.solid(extra: Opts?): Opts
	return merge({ CanTouch = false }, extra)
end

-- Big decoration players bump into (collides, not raycast).
function Style.decor(extra: Opts?): Opts
	return merge({ CanTouch = false, CanQuery = false }, extra)
end

-- Overhead decoration that casts a shadow but never blocks (canopies, awnings).
function Style.ghost(extra: Opts?): Opts
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false }, extra)
end

-- Small detail: no collision, no shadow.
function Style.tiny(extra: Opts?): Opts
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }, extra)
end

function Style.model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Shade variation that keeps the hue (value +-amount, saturation +-amount/2).
function Style.vary(color: Color3, rng: Rng.Rng, amount: number?): Color3
	return Geo.vary(color, rng, amount or 0.05)
end

function Style.block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Geo.block(parent, cf, size, color, material or SMOOTH, props or Style.decor())
end

-- PointLight, shadows off. Count every light against your package budget.
function Style.light(part: BasePart, color: Color3?, range: number?, brightness: number?): PointLight
	return Props.pointLight(part, color or C.Lamp, range or 16, brightness or 1.3, false)
end

-- Particles from built-in textures: "Smoke", "Embers", "Fire", "Sparkle", "Mist".
function Style.emitter(part: BasePart, kind: string, color: Color3?, rate: number?): ParticleEmitter
	if kind == "Mist" then
		local e = Props.emitter(part, "Smoke", color or C.Foam, rate or 4)
		e.Name = "MistParticles"
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, 1, 0)
		return e
	end
	return Props.emitter(part, kind, color, rate)
end

--[[
	Streaming for far-away backdrop models (StreamingEnabled is on):
	  "Lod"        LevelOfDetail = StreamingMesh: a low-res proxy is drawn when
	               the model is not streamed in (mountains, floating islands, ships)
	  "Persistent" always streamed (small sky props: balloon, clouds)
	  "Atomic"     streams in as one piece (animated models)
]]
function Style.streaming(m: Model, mode: string)
	local target: any = m
	if mode == "Persistent" then
		pcall(function()
			target.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
	elseif mode == "Atomic" then
		pcall(function()
			target.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end)
	elseif mode == "Lod" then
		pcall(function()
			target.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
		end)
	end
end

---------------------------------------------------------------- foliage

--[[
	Voxel canopy: a core cube, a lighter cap and 4-6 lumps poking out of its
	sides, in the three shades of `shades` ({light, mid, dark}). `cf` is the
	canopy center; lumps stay axis-aligned to it.
]]
function Style.canopy(parent: Instance, cf: CFrame, size: number, shades: { Color3 }, rng: Rng.Rng, props: Opts?): { Part }
	local light, mid, dark = shades[1], shades[2], shades[3]
	local p = props or Style.ghost()
	local parts = {}
	table.insert(parts, Style.block(parent, cf, Vector3.new(size, size * 0.78, size), Style.vary(mid, rng, 0.03), nil, p))
	local capOffset = Vector3.new(rng:range(-0.12, 0.12) * size, size * 0.42, rng:range(-0.12, 0.12) * size)
	table.insert(
		parts,
		Style.block(
			parent,
			cf * CFrame.new(capOffset),
			Vector3.new(size * 0.66, size * 0.34, size * 0.66),
			Style.vary(light, rng, 0.03),
			nil,
			p
		)
	)
	local sides = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local start = rng:int(0, 3)
	for i = 1, rng:int(4, 6) do
		local s = sides[(start + i) % 4 + 1]
		local k = size * rng:range(0.42, 0.58)
		local out = size * 0.5
		local y = rng:range(-0.24, 0.22) * size
		local lateral = rng:range(-0.26, 0.26) * size
		local offset = Vector3.new(s[1] * out + s[2] * lateral, y, s[2] * out + s[1] * lateral)
		local color = if y < -0.06 * size then dark elseif rng:chance(0.45) then light else mid
		table.insert(parts, Style.block(parent, cf * CFrame.new(offset), Vector3.new(k, k * 0.9, k), Style.vary(color, rng, 0.04), nil, p))
	end
	-- two top shoulders round off the silhouette
	for _, corner in { { 1, 1 }, { -1, -1 } } do
		local k = size * rng:range(0.36, 0.46)
		local offset = Vector3.new(corner[1] * size * 0.28, size * 0.3, corner[2] * size * rng:range(0.1, 0.3))
		table.insert(
			parts,
			Style.block(
				parent,
				cf * CFrame.new(offset),
				Vector3.new(k, k * 0.8, k),
				Style.vary(if rng:chance(0.6) then light else mid, rng, 0.04),
				nil,
				p
			)
		)
	end
	-- darker underside so the canopy reads as a volume from below
	table.insert(
		parts,
		Style.block(parent, cf * CFrame.new(0, -size * 0.37, 0), Vector3.new(size * 0.84, size * 0.1, size * 0.84), dark, nil, Style.tiny())
	)
	return parts
end

--[[
	Voxel tree. kind = "Green" | "Pink" | "Red" | "Yellow" | "Orange".
	scale 1 = ~13 studs tall. Quarter-turn yaw only, so trees share the
	world's voxel grid. About 9-14 parts.
]]
function Style.tree(parent: Instance, base: CFrame, kind: string, rng: Rng.Rng, scale: number?): Model
	local s = scale or 1
	local m = Style.model("Tree", parent)
	local shades = Style.TreeKinds[kind] or Style.TreeKinds.Green
	local frame = base * CFrame.Angles(0, rng:int(0, 3) * math.pi / 2, 0)
	local h = rng:range(6, 7.5) * s
	local tw = 1.7 * s
	Style.block(m, frame * CFrame.new(0, h / 2, 0), Vector3.new(tw, h, tw), Style.vary(C.Trunk, rng, 0.04))
	-- roots and a stub branch
	Style.block(m, frame * CFrame.new(tw * 0.55, 0.4 * s, 0), Vector3.new(tw * 0.6, 0.8 * s, tw * 0.6), C.TrunkDark, nil, Style.tiny())
	Style.block(m, frame * CFrame.new(0, 0.3 * s, -tw * 0.55), Vector3.new(tw * 0.5, 0.6 * s, tw * 0.5), C.TrunkDark, nil, Style.tiny())
	Style.block(m, frame * CFrame.new(-tw * 0.7, h * 0.62, 0), Vector3.new(tw * 0.8, tw * 0.5, tw * 0.5), C.Trunk, nil, Style.tiny())
	local size = rng:range(7.5, 9) * s
	Style.canopy(m, frame * CFrame.new(0, h + size * 0.22, 0), size, shades, rng)
	if s >= 1.15 then
		-- big trees get a second, smaller canopy lump
		local side = if rng:chance(0.5) then 1 else -1
		Style.canopy(m, frame * CFrame.new(side * size * 0.55, h + size * 0.02, size * 0.2), size * 0.55, shades, rng)
	end
	return m
end

-- A low voxel bush: 2-3 cubes (walk-through).
function Style.bush(parent: Instance, position: Vector3, color: Color3, rng: Rng.Rng, size: number?): Model
	local m = Style.model("Bush", parent)
	local s = size or rng:range(2, 3.2)
	local base = CFrame.new(position) * CFrame.Angles(0, rng:int(0, 3) * math.pi / 2, 0)
	Style.block(m, base * CFrame.new(0, s * 0.4, 0), Vector3.new(s * 1.3, s * 0.8, s), Style.vary(color, rng, 0.05), nil, Style.ghost())
	Style.block(
		m,
		base * CFrame.new(s * 0.35, s * 0.75, rng:range(-0.2, 0.2) * s),
		Vector3.new(s * 0.6, s * 0.5, s * 0.6),
		Style.vary(color, rng, 0.08),
		nil,
		Style.tiny()
	)
	if rng:chance(0.5) then
		Style.block(
			m,
			base * CFrame.new(-s * 0.55, s * 0.3, s * 0.2),
			Vector3.new(s * 0.6, s * 0.6, s * 0.6),
			Style.vary(color, rng, 0.08),
			nil,
			Style.tiny()
		)
	end
	return m
end

-- A patch of tiny voxel flowers (one cube each, no collision).
function Style.flowers(parent: Instance, center: Vector3, color: Color3, rng: Rng.Rng, count: number?, spread: number?): { Part }
	local parts = {}
	local r = spread or 1.8
	for _ = 1, count or 5 do
		local q = center + Vector3.new(rng:range(-r, r), rng:range(0.3, 0.55), rng:range(-r, r))
		local s = rng:range(0.45, 0.65)
		table.insert(parts, Style.block(parent, CFrame.new(q), Vector3.new(s, s, s), Style.vary(color, rng, 0.05), nil, Style.tiny()))
	end
	if rng:chance(0.6) then
		local q = center + Vector3.new(rng:range(-r, r) * 0.6, 0.2, rng:range(-r, r) * 0.6)
		table.insert(parts, Style.block(parent, CFrame.new(q), Vector3.new(0.9, 0.4, 0.9), C.LeafGreenDark, nil, Style.tiny()))
	end
	return parts
end

---------------------------------------------------------------- lights

--[[
	Lantern. opts.Kind:
	  "Post"    (default) wooden post with an arm and a hanging lamp
	  "Pillar"  stone column with a lamp box on top
	  "Hanging" just the lamp; base = the hook point (hangs below it)
	  "Ground"  knee-high stone path light
	opts.Light = true adds a PointLight (most lanterns are glow-only).
	opts.Height overrides the post/pillar height. The glowing part is
	named "LanternGlow".
]]
function Style.lantern(parent: Instance, base: CFrame, opts: Opts?): Model
	local o: Opts = opts or {}
	local kind = o.Kind or "Post"
	local glowColor = o.Color or C.Lamp
	local m = Style.model("Lantern", parent)
	local glow: Part
	local function lamp(at: CFrame, s: number): Part
		Style.block(m, at * CFrame.new(0, s * 0.62, 0), Vector3.new(s * 1.3, s * 0.28, s * 1.3), C.Iron, nil, Style.tiny())
		Style.block(m, at * CFrame.new(0, s * 0.8, 0), Vector3.new(s * 0.7, s * 0.2, s * 0.7), C.Iron, nil, Style.tiny())
		local g = Style.block(m, at, Vector3.new(s, s, s), glowColor, NEON, Style.tiny())
		Style.block(m, at * CFrame.new(0, -s * 0.58, 0), Vector3.new(s * 1.15, s * 0.18, s * 1.15), C.Iron, nil, Style.tiny())
		g.Name = "LanternGlow"
		return g
	end
	if kind == "Pillar" then
		local h = o.Height or 4.5
		Style.block(m, base * CFrame.new(0, 0.35, 0), Vector3.new(2.2, 0.7, 2.2), C.StoneDark)
		Style.block(m, base * CFrame.new(0, h / 2, 0), Vector3.new(1.5, h, 1.5), C.Stone)
		Style.block(m, base * CFrame.new(0, h + 0.15, 0), Vector3.new(2, 0.3, 2), C.StoneDark, nil, Style.tiny())
		glow = lamp(base * CFrame.new(0, h + 0.95, 0), 1.2)
	elseif kind == "Hanging" then
		Style.block(m, base * CFrame.new(0, -0.5, 0), Vector3.new(0.15, 1, 0.15), C.Iron, nil, Style.tiny())
		glow = lamp(base * CFrame.new(0, -1.6, 0), 1)
	elseif kind == "Ground" then
		Style.block(m, base * CFrame.new(0, 0.5, 0), Vector3.new(1.3, 1, 1.3), C.StoneDark, nil, Style.tiny())
		glow = Style.block(m, base * CFrame.new(0, 1.2, 0), Vector3.new(0.9, 0.5, 0.9), glowColor, NEON, Style.tiny())
		glow.Name = "LanternGlow"
	else
		local h = o.Height or 7
		Style.block(m, base * CFrame.new(0, h / 2, 0), Vector3.new(0.7, h, 0.7), C.WoodDark)
		Style.block(m, base * CFrame.new(0, h + 0.15, 0), Vector3.new(1, 0.3, 1), C.Wood, nil, Style.tiny())
		Style.block(m, base * CFrame.new(0, h - 0.4, -0.9), Vector3.new(0.35, 0.35, 2.2), C.WoodDark, nil, Style.tiny())
		glow = lamp(base * CFrame.new(0, h - 1.8, -1.7), 1.05)
	end
	if o.Light then
		Style.light(glow, glowColor, o.Range or 16, o.Brightness or 1.3)
	end
	m.PrimaryPart = glow
	return m
end

---------------------------------------------------------------- signs and icons

--[[
	Sign board with big readable letters. `cf` = board center, front = LookVector.
	opts.Kind: "Wood" (default: dark board, light frame, gold letters),
	           "Glow" (deep blue board, neon blue frame, white letters, unlit),
	           "Stone" (dark stone, light stone frame, gold letters)
	opts.DoubleSided, opts.TextColor, opts.Font, opts.Frame (default true),
	opts.Depth (board thickness, default 0.6). Returns the board ("Sign").
]]
function Style.sign(parent: Instance, cf: CFrame, text: string, width: number, height: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local kind = o.Kind or "Wood"
	local depth = o.Depth or 0.6
	local boardColor, frameColor, textColor, frameMaterial = C.SignBoard, C.SignFrame, C.SignText, SMOOTH
	local lightInfluence = 0.2
	if kind == "Glow" then
		boardColor, frameColor, textColor, frameMaterial = C.GlowBoard, C.GlowEdge, C.GlowText, NEON
		lightInfluence = 0
	elseif kind == "Stone" then
		boardColor, frameColor = C.StoneDeep, C.StoneLight
	end
	textColor = o.TextColor or textColor
	local board = Style.block(parent, cf, Vector3.new(width, height, depth), o.BoardColor or boardColor, nil, Style.decor())
	board.Name = "Sign"
	if o.Frame ~= false then
		local t = math.clamp(math.min(width, height) * 0.09, 0.25, 0.7)
		local z = -depth / 2 - 0.05
		local fp = Style.tiny()
		Style.block(parent, cf * CFrame.new(0, height / 2 - t / 2, z), Vector3.new(width + 0.2, t, 0.3), frameColor, frameMaterial, fp)
		Style.block(parent, cf * CFrame.new(0, -height / 2 + t / 2, z), Vector3.new(width + 0.2, t, 0.3), frameColor, frameMaterial, fp)
		Style.block(parent, cf * CFrame.new(-width / 2 + t / 2, 0, z), Vector3.new(t, height - 2 * t, 0.3), frameColor, frameMaterial, fp)
		Style.block(parent, cf * CFrame.new(width / 2 - t / 2, 0, z), Vector3.new(t, height - 2 * t, 0.3), frameColor, frameMaterial, fp)
	end
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
		gui.LightInfluence = lightInfluence
		gui.MaxDistance = o.MaxDistance or 250
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.86, 0.74)
		label.Position = UDim2.fromScale(0.07, 0.13)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = textColor
		label.TextStrokeColor3 = if kind == "Glow" then C.GlowEdge else C.TextShadow
		label.TextStrokeTransparency = 0.4
		label.FontFace = Font.fromEnum(o.Font or Style.SignFont)
		label.Parent = gui
	end
	return board
end

local function bar(parent: Instance, cf: CFrame, w: number, h: number, d: number, color: Color3, material: Enum.Material): Part
	return Style.block(parent, cf, Vector3.new(w, h, d), color, material, Style.tiny())
end

--[[
	Part-built icon for signs (no decals). `cf` = icon center, front = LookVector;
	place it just in front of a board (board.CFrame * CFrame.new(0, 0, -depth/2 - 0.2)).
	kind: "Hammer", "CrossedHammers", "Pickaxe", "CrossedPickaxes", "Gear",
	"House", "Compass", "Arrow" (points to the VIEWER's right when seen from
	the front), "ArrowLeft", "ArrowDown", "Coin", "Bone", "Target".
	Note: seen from the front, a frame's local +X is on the viewer's LEFT, so
	"viewer's right" = local -X.
]]
function Style.icon(parent: Instance, cf: CFrame, kind: string, size: number, color: Color3, material: Enum.Material?): { BasePart }
	local s = size
	local mat = material or SMOOTH
	local d = 0.3
	local parts: { BasePart } = {}
	local function add(p: BasePart)
		table.insert(parts, p)
	end
	local function hammer(at: CFrame)
		add(bar(parent, at * CFrame.new(0, -s * 0.08, 0), s * 0.14, s * 0.8, d, color, mat))
		add(bar(parent, at * CFrame.new(0, s * 0.36, 0), s * 0.5, s * 0.22, d * 1.2, color, mat))
	end
	local function pickaxe(at: CFrame)
		add(bar(parent, at * CFrame.new(0, -s * 0.06, 0), s * 0.12, s * 0.84, d, color, mat))
		add(bar(parent, at * CFrame.new(-s * 0.17, s * 0.34, 0) * CFrame.Angles(0, 0, -0.38), s * 0.4, s * 0.12, d * 1.2, color, mat))
		add(bar(parent, at * CFrame.new(s * 0.17, s * 0.34, 0) * CFrame.Angles(0, 0, 0.38), s * 0.4, s * 0.12, d * 1.2, color, mat))
	end
	if kind == "Hammer" then
		hammer(cf)
	elseif kind == "CrossedHammers" then
		hammer(cf * CFrame.Angles(0, 0, 0.7))
		hammer(cf * CFrame.Angles(0, 0, -0.7))
	elseif kind == "Pickaxe" then
		pickaxe(cf * CFrame.Angles(0, 0, -0.5))
	elseif kind == "CrossedPickaxes" then
		pickaxe(cf * CFrame.Angles(0, 0, 0.7))
		pickaxe(cf * CFrame.Angles(0, 0, -0.7))
	elseif kind == "Gear" then
		add(bar(parent, cf, s * 0.62, s * 0.62, d, color, mat))
		add(bar(parent, cf * CFrame.Angles(0, 0, math.pi / 4), s * 0.62, s * 0.62, d, color, mat))
		for i = 0, 3 do
			add(bar(parent, cf * CFrame.Angles(0, 0, i * math.pi / 4), s * 0.16, s * 0.92, d, color, mat))
		end
		add(bar(parent, cf * CFrame.new(0, 0, -d * 0.6), s * 0.22, s * 0.22, d * 0.3, C.SignBoard, SMOOTH))
	elseif kind == "House" then
		add(bar(parent, cf * CFrame.new(0, -s * 0.18, 0), s * 0.6, s * 0.5, d, color, mat))
		-- roof: two wedges, tall sides meeting in the middle (a wedge's tall side is +Z;
		-- a quarter turn of +pi/2 turns +Z to +X)
		add(
			Geo.wedge(
				parent,
				cf * CFrame.new(-s * 0.2, s * 0.25, 0) * CFrame.Angles(0, math.pi / 2, 0),
				Vector3.new(d, s * 0.36, s * 0.4),
				color,
				mat,
				Style.tiny()
			)
		)
		add(
			Geo.wedge(
				parent,
				cf * CFrame.new(s * 0.2, s * 0.25, 0) * CFrame.Angles(0, -math.pi / 2, 0),
				Vector3.new(d, s * 0.36, s * 0.4),
				color,
				mat,
				Style.tiny()
			)
		)
		add(bar(parent, cf * CFrame.new(0, -s * 0.28, -d * 0.6), s * 0.16, s * 0.3, d * 0.3, C.SignBoard, SMOOTH))
	elseif kind == "Compass" then
		add(bar(parent, cf * CFrame.Angles(0, 0, math.pi / 4), s * 0.6, s * 0.6, d, color, mat))
		add(
			bar(
				parent,
				cf * CFrame.new(0, 0, -d * 0.6) * CFrame.Angles(0, 0, math.pi / 4),
				s * 0.36,
				s * 0.36,
				d * 0.3,
				C.SignBoard,
				SMOOTH
			)
		)
		add(bar(parent, cf * CFrame.new(0, 0, -d) * CFrame.Angles(0, 0, 0.5), s * 0.1, s * 0.7, d * 0.3, color, mat))
	elseif kind == "Arrow" or kind == "ArrowLeft" then
		-- k = -1: the head is at local -X, i.e. on the viewer's right
		local k = if kind == "Arrow" then -1 else 1
		add(bar(parent, cf * CFrame.new(-k * s * 0.1, 0, 0), s * 0.7, s * 0.16, d, color, mat))
		add(
			bar(
				parent,
				cf * CFrame.new(k * s * 0.2, s * 0.13, 0) * CFrame.Angles(0, 0, -k * math.pi / 4),
				s * 0.42,
				s * 0.16,
				d,
				color,
				mat
			)
		)
		add(
			bar(
				parent,
				cf * CFrame.new(k * s * 0.2, -s * 0.13, 0) * CFrame.Angles(0, 0, k * math.pi / 4),
				s * 0.42,
				s * 0.16,
				d,
				color,
				mat
			)
		)
	elseif kind == "ArrowDown" then
		add(bar(parent, cf * CFrame.new(0, s * 0.1, 0), s * 0.16, s * 0.7, d, color, mat))
		add(bar(parent, cf * CFrame.new(-s * 0.13, -s * 0.2, 0) * CFrame.Angles(0, 0, -math.pi / 4), s * 0.16, s * 0.42, d, color, mat))
		add(bar(parent, cf * CFrame.new(s * 0.13, -s * 0.2, 0) * CFrame.Angles(0, 0, math.pi / 4), s * 0.16, s * 0.42, d, color, mat))
	elseif kind == "Coin" then
		local coin = Geo.make(
			"Part",
			Style.tiny({
				Shape = Enum.PartType.Cylinder,
				CFrame = cf * CFrame.Angles(0, math.pi / 2, 0),
				Size = Vector3.new(d, s * 0.7, s * 0.7),
				Color = color,
				Material = mat,
			}),
			parent
		)
		add(coin)
	elseif kind == "Bone" then
		add(bar(parent, cf, s * 0.7, s * 0.16, d, color, mat))
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				add(bar(parent, cf * CFrame.new(x * s * 0.36, y * s * 0.1, 0), s * 0.2, s * 0.2, d, color, mat))
			end
		end
	elseif kind == "Target" then
		add(bar(parent, cf, s * 0.8, s * 0.8, d, color, mat))
		add(bar(parent, cf * CFrame.Angles(0, 0, math.pi / 4), s * 0.8, s * 0.8, d, color, mat))
		add(bar(parent, cf * CFrame.new(0, 0, -d * 0.55), s * 0.56, s * 0.56, d * 0.2, C.SignBoard, SMOOTH))
		add(
			bar(
				parent,
				cf * CFrame.new(0, 0, -d * 0.55) * CFrame.Angles(0, 0, math.pi / 4),
				s * 0.56,
				s * 0.56,
				d * 0.2,
				C.SignBoard,
				SMOOTH
			)
		)
		add(bar(parent, cf * CFrame.new(0, 0, -d * 0.7), s * 0.2, s * 0.2, d * 0.3, color, mat))
	end
	return parts
end

---------------------------------------------------------------- stone and wood

--[[
	Ring of stone blocks around `center` (ground point). opts: Height (1.4),
	Width (2.2), Segments, Color, Glow (Color3: neon insets on every other
	block's outer face), Gaps ({ {fromAngle, toAngle} } in radians, measured
	from +X toward +Z), Y (base height).
]]
function Style.stoneRing(parent: Instance, center: Vector3, radius: number, rng: Rng.Rng, opts: Opts?): { Part }
	local o: Opts = opts or {}
	local h = o.Height or 1.4
	local w = o.Width or 2.2
	local color = o.Color or C.Stone
	local segments = o.Segments or math.max(8, math.floor(2 * math.pi * radius / 3.2 + 0.5))
	local segLen = 2 * math.pi * radius / segments * 1.04
	local y = o.Y or 0
	local parts = {}
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * 2 * math.pi
		local skip = false
		if o.Gaps then
			for _, gap in o.Gaps do
				local lo, hi = gap[1], gap[2]
				local aa = a
				while aa < lo do
					aa += 2 * math.pi
				end
				if aa <= hi then
					skip = true
				end
			end
		end
		if not skip then
			local bump = if i % 3 == 0 then 0.3 else 0
			local frame = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(radius, y + (h + bump) / 2, 0)
			table.insert(
				parts,
				Style.block(parent, frame, Vector3.new(w, h + bump, segLen), Style.vary(color, rng, 0.06), nil, Style.solid())
			)
			if o.Glow and i % 2 == 0 then
				Style.block(
					parent,
					frame * CFrame.new(w / 2 + 0.06, -h * 0.05, 0),
					Vector3.new(0.2, h * 0.36, segLen * 0.55),
					o.Glow,
					NEON,
					Style.tiny()
				)
			end
		end
	end
	return parts
end

--[[
	Stone/brick wall slab with a voxel brick texture: dark mortar courses
	every ~2 studs, a few protruding bricks in lighter/darker shades and a
	cap row. `base` = bottom center, front = LookVector, size = (width,
	height, thickness). opts: Color, Accent (brick shade), Density (0..1,
	default 0.45), Courses (default true; stud spacing via CourseEvery = 2),
	Cap (default true), TwoSided. About 6 + 0.5 * area/9 * Density parts per side.
]]
function Style.stoneWall(parent: Instance, base: CFrame, size: Vector3, rng: Rng.Rng, opts: Opts?): { Part }
	local o: Opts = opts or {}
	local color = o.Color or C.Stone
	local parts = {}
	table.insert(parts, Style.block(parent, base * CFrame.new(0, size.Y / 2, 0), size, Style.vary(color, rng, 0.03), nil, Style.solid()))
	local density = o.Density or 0.45
	local count = math.floor(size.X * size.Y / 9 * density)
	local sidesList: { number } = if o.TwoSided then { -1, 1 } else { -1 }
	local mortar = (o.Color or C.Stone):Lerp(C.StoneDeep, 0.55)
	for _, side in sidesList do
		if o.Courses ~= false then
			local every = o.CourseEvery or 2
			local y = every
			while y < size.Y - 0.5 do
				table.insert(
					parts,
					Style.block(
						parent,
						base * CFrame.new(0, y, side * (size.Z / 2 + 0.04)),
						Vector3.new(size.X - 0.1, 0.18, 0.12),
						mortar,
						nil,
						Style.tiny()
					)
				)
				y += every
			end
		end
		for _ = 1, count do
			local bw = rng:pick({ 1.6, 2, 2.4 })
			local bh = rng:pick({ 0.8, 1, 1.2 })
			local x = math.floor(rng:range(-size.X / 2 + bw / 2, size.X / 2 - bw / 2) + 0.5)
			local yy = math.floor(rng:range(bh, size.Y - bh) + 0.5)
			local shade = o.Accent or (if rng:chance(0.5) then C.StoneLight else C.StoneDark)
			table.insert(
				parts,
				Style.block(
					parent,
					base * CFrame.new(x, yy, side * (size.Z / 2 + 0.1)),
					Vector3.new(bw, bh, 0.3),
					Style.vary(shade, rng, 0.05),
					nil,
					Style.tiny()
				)
			)
		end
	end
	if o.Cap ~= false then
		table.insert(
			parts,
			Style.block(
				parent,
				base * CFrame.new(0, size.Y + 0.3, 0),
				Vector3.new(size.X + 0.4, 0.6, size.Z + 0.4),
				Style.vary(C.StoneDark, rng, 0.03),
				nil,
				Style.solid()
			)
		)
	end
	return parts
end

--[[
	Gable roof: ridge along local X. `cf` = center at eave height. opts:
	Color, Dark (tile-row lines), Trim (eaves and gable edges), Rows (tile
	lines per slope, default 2), Ridge (default true). About 13-17 parts.
]]
function Style.gableRoof(parent: Instance, cf: CFrame, width: number, depth: number, height: number, opts: Opts?): { BasePart }
	local o: Opts = opts or {}
	local color = o.Color or C.Roof
	local dark = o.Dark or C.RoofDark
	local trim = o.Trim or C.RoofTrim
	local half = depth / 2
	local parts: { BasePart } = {}
	local p = Style.solid()
	-- WedgePart's tall side is at +Z: the front half needs no turn, the back half turns around
	table.insert(parts, Geo.wedge(parent, cf * CFrame.new(0, height / 2, -half / 2), Vector3.new(width, height, half), color, SMOOTH, p))
	table.insert(
		parts,
		Geo.wedge(
			parent,
			cf * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(width, height, half),
			color,
			SMOOTH,
			p
		)
	)
	parts[1].Name = "Roof"
	parts[2].Name = "Roof"
	local slope = math.atan2(height, half)
	local slopeLen = math.sqrt(height * height + half * half)
	for _, side in { -1, 1 } do
		-- tile lines across each slope
		for r = 1, o.Rows or 2 do
			local t = r / ((o.Rows or 2) + 1)
			local pos = Vector3.new(0, height * (1 - t) + 0.12, side * half * t)
			local rot = CFrame.Angles(side * slope, 0, 0)
			table.insert(
				parts,
				Style.block(parent, cf * CFrame.new(pos) * rot, Vector3.new(width + 0.1, 0.3, 0.7), dark, nil, Style.tiny())
			)
		end
		-- eave board
		table.insert(
			parts,
			Style.block(parent, cf * CFrame.new(0, -0.2, side * (half + 0.15)), Vector3.new(width + 0.4, 0.7, 0.5), trim, nil, Style.tiny())
		)
		-- gable edge boards (both ends of this slope)
		for _, x in { -1, 1 } do
			local mid = Vector3.new(x * (width / 2 + 0.15), height / 2 + 0.1, side * half / 2)
			table.insert(
				parts,
				Style.block(
					parent,
					cf * CFrame.new(mid) * CFrame.Angles(side * slope, 0, 0),
					Vector3.new(0.5, 0.6, slopeLen + 0.4),
					trim,
					nil,
					Style.tiny()
				)
			)
		end
	end
	if o.Ridge ~= false then
		table.insert(
			parts,
			Style.block(
				parent,
				cf * CFrame.new(0, height + 0.2, 0),
				Vector3.new(width + 0.6, 0.8, 1.2),
				trim,
				nil,
				Style.tiny({ CastShadow = true })
			)
		)
	end
	return parts
end

--[[
	Striped market awning. `cf` = top back edge center (on the wall),
	LookVector = outward. It slopes `drop` studs down over `depth` studs and
	ends in a scalloped valance. opts: Stripes (count), Scallops (default true).
]]
function Style.awning(
	parent: Instance,
	cf: CFrame,
	width: number,
	depth: number,
	drop: number,
	colorA: Color3,
	colorB: Color3,
	opts: Opts?
): { Part }
	local o: Opts = opts or {}
	local stripes = o.Stripes or math.max(2, math.floor(width / 2.4 + 0.5))
	local stripeW = width / stripes
	local angle = math.atan2(drop, depth)
	local len = math.sqrt(depth * depth + drop * drop)
	local parts = {}
	for i = 0, stripes - 1 do
		local x = -width / 2 + stripeW * (i + 0.5)
		local color = if i % 2 == 0 then colorA else colorB
		local mid = cf * CFrame.new(x, -drop / 2, -depth / 2) * CFrame.Angles(-angle, 0, 0)
		table.insert(parts, Style.block(parent, mid, Vector3.new(stripeW + 0.02, 0.3, len), color, nil, Style.ghost()))
		if o.Scallops ~= false then
			local edge = cf * CFrame.new(x, -drop - 0.45, -depth + 0.05)
			table.insert(parts, Style.block(parent, edge, Vector3.new(stripeW * 0.72, 0.9, 0.25), color, nil, Style.tiny()))
		end
	end
	return parts
end

--[[
	One crystal: a diamond-section prism with a ridge tip. `base` = bottom
	center, up = growth direction. Neon; the tip is a lighter tint so the
	facets still read under bloom (pass `tip` to override). 3 parts.
]]
function Style.crystal(parent: Instance, base: CFrame, height: number, width: number, color: Color3, tip: Color3?): { BasePart }
	local body = base * CFrame.Angles(0, math.pi / 4, 0)
	local bodyH = height * 0.78
	local tipH = height - bodyH
	local p = Style.tiny()
	local parts: { BasePart } = {}
	table.insert(parts, Style.block(parent, body * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), color, NEON, p))
	local tipAt = body * CFrame.new(0, bodyH + tipH / 2, 0)
	local tipColor = tip or color:Lerp(Color3.new(1, 1, 1), 0.35)
	table.insert(parts, Geo.wedge(parent, tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tipColor, NEON, p))
	table.insert(
		parts,
		Geo.wedge(
			parent,
			tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(width, tipH, width / 2),
			color,
			NEON,
			p
		)
	)
	return parts
end

--[[
	Glowing crystal cluster: one tall crystal and 3-5 smaller ones leaning
	outward, on a dark rock. opts: Count, Light (adds one PointLight).
]]
function Style.crystalCluster(parent: Instance, base: CFrame, size: number, color: Color3, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("CrystalCluster", parent)
	Style.block(
		m,
		base * CFrame.new(0, size * 0.08, 0) * CFrame.Angles(0, rng:range(0, 1.5), 0),
		Vector3.new(size * 0.5, size * 0.2, size * 0.45),
		C.StoneDeep,
		nil,
		Style.decor()
	)
	local tint = color:Lerp(Color3.new(1, 1, 1), 0.3)
	local main = Style.crystal(
		m,
		base * CFrame.new(0, size * 0.1, 0) * CFrame.Angles(rng:range(-0.12, 0.12), 0, rng:range(-0.12, 0.12)),
		size,
		size * 0.24,
		color
	)
	local count = o.Count or rng:int(3, 5)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:range(-0.3, 0.3)
		local lean = rng:range(0.3, 0.6)
		local h = size * rng:range(0.35, 0.7)
		local foot = base * CFrame.new(math.cos(a) * size * 0.16, size * 0.06, math.sin(a) * size * 0.16)
		local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -lean) * CFrame.Angles(0, a, 0)
		Style.crystal(m, foot * tilt, h, h * 0.26, if i % 2 == 0 then tint else color)
	end
	if o.Light then
		Style.light(main[1], color, o.Range or math.clamp(size * 2.4, 12, 26), o.Brightness or 1.4)
	end
	return m
end

---------------------------------------------------------------- water

-- Water surface (non-collide, slightly see-through), named "Water".
function Style.water(parent: Instance, cf: CFrame, size: Vector3, color: Color3?): Part
	local w = Style.block(parent, cf, size, color or C.Water, SMOOTH, Style.tiny({ Transparency = 0.18, Reflectance = 0.15 }))
	w.Name = "Water"
	return w
end

--[[
	Waterfall like the concept's: a light sky-blue sheet with a paler middle
	band (two tones), two cyan glints, the lip on top and white foam at the
	foot (a churned slab and a few cubes, mist on the slab). `top` = center
	of the lip, LookVector = toward the viewer (the side the water faces).
	opts: Foam (default true), Mist (default true). About 8-11 parts.
]]
function Style.waterfall(parent: Instance, top: CFrame, height: number, width: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Waterfall", parent)
	local sheet = Style.block(
		m,
		top * CFrame.new(0, -height / 2, 0),
		Vector3.new(width, height, 0.6),
		C.Falls,
		SMOOTH,
		Style.tiny({ Transparency = 0.1, Reflectance = 0.1 })
	)
	sheet.Name = "Water"
	Style.block(
		m,
		top * CFrame.new(rng:range(-0.08, 0.08) * width, -height / 2, -0.36),
		Vector3.new(width * 0.42, height, 0.12),
		C.FallsLight,
		SMOOTH,
		Style.tiny({ Transparency = 0.15 })
	)
	Style.block(m, top * CFrame.new(0, 0.2, 0.2), Vector3.new(width + 0.6, 0.9, 1.4), C.Water, SMOOTH, Style.tiny())
	for _, side in { -1, 1 } do
		local x = side * width * rng:range(0.22, 0.36)
		local h = height * rng:range(0.6, 0.95)
		Style.block(
			m,
			top * CFrame.new(x, -h / 2 - 0.4, -0.5),
			Vector3.new(math.max(0.3, width * 0.07), h, 0.12),
			C.FallsGlint,
			NEON,
			Style.tiny({ Transparency = 0.45 })
		)
	end
	if o.Foam ~= false then
		local foot = top * CFrame.new(0, -height, -1)
		local slab = Style.block(m, foot * CFrame.new(0, 0.5, 0), Vector3.new(width + 1.6, 1, 2.6), C.Foam, SMOOTH, Style.tiny())
		slab.Name = "Foam"
		local n = math.max(2, math.floor(width / 2.4))
		for i = 1, n do
			local s = rng:range(1.4, 2.6)
			local x = -width / 2 + (i - 0.5) * (width / n) + rng:range(-0.4, 0.4)
			Style.block(
				m,
				foot * CFrame.new(x, 0.9 + s * 0.25, rng:range(-0.6, 0.6)),
				Vector3.new(s, s * 0.75, s),
				C.Foam,
				SMOOTH,
				Style.tiny()
			)
		end
		if o.Mist ~= false then
			Style.emitter(slab, "Mist", C.Foam, 4)
		end
	end
	return m
end

--[[
	Blocky pond on flat ground: dark bottom, water surface 0.65 above the
	ground, a rim of stone cubes around a rounded rectangle, lily pads and
	koi. opts: LilyPads (count), Koi (count), Rim (default true), RimColor.
	The water is non-collide over solid ground (wading, never a hole).
]]
function Style.pond(parent: Instance, center: Vector3, sizeX: number, sizeZ: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Pond", parent)
	local inX, inZ = sizeX - 2, sizeZ - 2
	Style.block(m, CFrame.new(center + Vector3.new(0, 0.08, 0)), Vector3.new(inX, 0.16, inZ * 0.7), C.WaterDeep, nil, Style.tiny())
	Style.block(m, CFrame.new(center + Vector3.new(0, 0.08, 0)), Vector3.new(inX * 0.78, 0.16, inZ), C.WaterDeep, nil, Style.tiny())
	Style.water(m, CFrame.new(center + Vector3.new(0, 0.4, 0)), Vector3.new(inX, 0.5, inZ * 0.7))
	Style.water(m, CFrame.new(center + Vector3.new(0, 0.39, 0)), Vector3.new(inX * 0.78, 0.5, inZ))
	if o.Rim ~= false then
		-- walk around a rounded rectangle (superellipse) placing rim cubes
		local rimColor = o.RimColor or C.Stone
		local steps = math.floor((sizeX + sizeZ) * 2 / 2.6)
		for i = 0, steps - 1 do
			local a = i / steps * 2 * math.pi
			local cx, sz = math.cos(a), math.sin(a)
			local k = 4
			local rx = math.sign(cx) * math.abs(cx) ^ (2 / k)
			local rz = math.sign(sz) * math.abs(sz) ^ (2 / k)
			local p = center + Vector3.new(rx * sizeX / 2, 0, rz * sizeZ / 2)
			local s = rng:range(1.8, 2.6)
			local h = rng:range(0.8, 1.4)
			Style.block(
				m,
				CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, -a, 0),
				Vector3.new(s, h, s * 1.1),
				Style.vary(rimColor, rng, 0.07),
				nil,
				Style.solid()
			)
		end
	end
	for _ = 1, o.LilyPads or 0 do
		local q = center + Vector3.new(rng:range(-inX * 0.38, inX * 0.38), 0.68, rng:range(-inZ * 0.3, inZ * 0.3))
		local d = rng:range(1.6, 2.6)
		Geo.cylinder(m, q, 0.12, d, Style.vary(C.LeafGreen, rng, 0.06), SMOOTH, Style.tiny())
		if rng:chance(0.5) then
			Style.block(m, CFrame.new(q + Vector3.new(d * 0.15, 0.3, 0)), Vector3.new(0.55, 0.45, 0.55), C.FlowerPink, nil, Style.tiny())
		end
	end
	for i = 1, o.Koi or 0 do
		local q = center + Vector3.new(rng:range(-inX * 0.35, inX * 0.35), 0.5, rng:range(-inZ * 0.28, inZ * 0.28))
		local yaw = rng:range(0, math.pi * 2)
		local color = if i % 3 == 0 then C.FlowerWhite elseif i % 3 == 1 then C.LeafOrange else C.FlowerRed
		local fish = CFrame.new(q) * CFrame.Angles(0, yaw, 0)
		Style.block(m, fish, Vector3.new(0.55, 0.3, 1.4), color, nil, Style.tiny())
		Style.block(m, fish * CFrame.new(0, 0, 0.85), Vector3.new(0.7, 0.12, 0.45), C.FlowerWhite, nil, Style.tiny())
	end
	return m
end

---------------------------------------------------------------- wood, rails, paths

--[[
	Wooden fence from `from` to `to` (ground points): posts every
	opts.PostEvery (5) studs and opts.Rails (2) rails. Collides.
]]
function Style.fence(parent: Instance, from: Vector3, to: Vector3, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Fence", parent)
	local h = o.Height or 3
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local frame = CFrame.fromMatrix(from, right, Vector3.new(0, 1, 0), -dir)
	local posts = math.max(1, math.ceil(length / (o.PostEvery or 5)))
	for i = 0, posts do
		Style.block(m, frame * CFrame.new(0, h / 2, -length * i / posts), Vector3.new(0.8, h, 0.8), o.PostColor or C.WoodDark)
		if o.Caps then
			Style.block(m, frame * CFrame.new(0, h + 0.15, -length * i / posts), Vector3.new(1.1, 0.3, 1.1), C.Wood, nil, Style.tiny())
		end
	end
	local rails = o.Rails or 2
	for r = 1, rails do
		local y = h * (0.35 + 0.5 * (r - 1) / math.max(1, rails - 1))
		Style.block(
			m,
			frame * CFrame.new(0, y, -length / 2),
			Vector3.new(0.35, 0.45, length),
			o.RailColor or C.Wood,
			nil,
			Style.decor({ CastShadow = false })
		)
	end
	return m
end

--[[
	Mine rails from `from` to `to` (ground points): two iron rails on
	sleepers. Flat walk-over decor. opts: Gauge (3), SleeperEvery (2.2).
]]
function Style.rails(parent: Instance, from: Vector3, to: Vector3, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Rails", parent)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local right = if flat.Magnitude > 1e-3 then Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) else Vector3.new(1, 0, 0)
	local up = right:Cross(dir)
	if up.Y < 0 then
		up = -up
	end
	local frame = CFrame.fromMatrix((from + to) / 2, right, up, -dir)
	local gauge = o.Gauge or 3
	for _, x in { -gauge / 2, gauge / 2 } do
		Style.block(m, frame * CFrame.new(x, 0.42, 0), Vector3.new(0.3, 0.3, length), C.IronLight, METAL, Style.tiny())
	end
	local every = o.SleeperEvery or 2.2
	local count = math.max(1, math.floor(length / every))
	for i = 0, count do
		local z = -length / 2 + (i + 0.5) * (length / (count + 1))
		Style.block(m, frame * CFrame.new(0, 0.14, z), Vector3.new(gauge + 1.4, 0.28, 0.7), C.WoodDark, nil, Style.tiny())
	end
	return m
end

--[[
	Mine cart on rails. `base` = bottom center on the rails, LookVector =
	travel direction. opts.Load = "Gold" (default) | "Ore" | "Empty".
	About 12-16 parts.
]]
function Style.mineCart(parent: Instance, base: CFrame, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("MineCart", parent)
	local body = Style.block(m, base * CFrame.new(0, 1.7, 0), Vector3.new(3, 1.8, 4.2), C.Iron, nil, Style.decor())
	body.Name = "Body"
	Style.block(m, base * CFrame.new(0, 2.65, 0), Vector3.new(3.3, 0.3, 4.5), C.IronLight, METAL, Style.tiny())
	for _, z in { -1.2, 1.2 } do
		Style.block(m, base * CFrame.new(0, 1.7, z), Vector3.new(3.1, 1.9, 0.3), C.Copper, nil, Style.tiny())
	end
	for _, x in { -1.45, 1.45 } do
		for _, z in { -1.3, 1.3 } do
			Geo.make(
				"Part",
				Style.tiny({
					Shape = Enum.PartType.Cylinder,
					CFrame = base * CFrame.new(x, 0.65, z),
					Size = Vector3.new(0.45, 1.2, 1.2),
					Color = C.StoneDeep,
					Material = SMOOTH,
				}),
				m
			)
		end
	end
	local load = o.Load or "Gold"
	if load ~= "Empty" then
		local color = if load == "Gold" then C.Gold else C.StoneLight
		for i = 1, 6 do
			local s = rng:range(0.8, 1.4)
			local q = Vector3.new(rng:range(-0.9, 0.9), 2.6 + rng:range(0, 0.5), rng:range(-1.4, 1.4))
			local glowing = load == "Gold" and i <= 2
			Style.block(
				m,
				base * CFrame.new(q) * Geo.randomTilt(rng, 0.5),
				Vector3.new(s, s * 0.8, s),
				Style.vary(color, rng, 0.06),
				if glowing then NEON else SMOOTH,
				Style.tiny()
			)
		end
	end
	m.PrimaryPart = body
	return m
end

--[[
	Plank deck. `cf` = center of the deck's top surface, planks run across
	local X, the deck runs along local Z. One solid walkable base plus
	alternating lighter plank strips (no collision).
]]
function Style.planks(parent: Instance, cf: CFrame, size: Vector3, rng: Rng.Rng, opts: Opts?): { Part }
	local o: Opts = opts or {}
	local color = o.Color or C.Plank
	local parts = {}
	table.insert(parts, Style.block(parent, cf * CFrame.new(0, -size.Y / 2, 0), size, color, nil, Style.solid()))
	local pw = o.PlankWidth or 1.2
	local n = math.floor(size.Z / pw)
	for i = 0, n - 1, 2 do
		local z = -size.Z / 2 + (i + 0.5) * pw
		table.insert(
			parts,
			Style.block(
				parent,
				cf * CFrame.new(0, 0.03, z),
				Vector3.new(size.X - 0.1, 0.06, pw - 0.15),
				Style.vary(C.WoodLight, rng, 0.05),
				nil,
				Style.tiny()
			)
		)
	end
	return parts
end

--[[
	Arched wooden bridge from `from` to `to` (ground points), `width` wide,
	rising `rise` studs in the middle. The deck is walkable (6 segments),
	with posts and handrails on both sides. About 30-36 parts.
]]
function Style.archBridge(parent: Instance, from: Vector3, to: Vector3, width: number, rise: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Bridge", parent)
	local n = o.Segments or 6
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local function point(t: number): Vector3
		local y = rise * (1 - (2 * t - 1) ^ 2)
		return from + dir * (length * t) + Vector3.new(0, y, 0)
	end
	local thickness = 0.7
	for i = 0, n - 1 do
		local a, b = point(i / n), point((i + 1) / n)
		local seg = b - a
		local segDir = seg.Unit
		local up = right:Cross(segDir)
		if up.Y < 0 then
			up = -up
		end
		local mid = (a + b) / 2 - up * (thickness / 2)
		local frame = CFrame.fromMatrix(mid, right, up, -segDir)
		local color = if i % 2 == 0 then C.Plank else C.WoodLight
		Style.block(m, frame, Vector3.new(width, thickness, seg.Magnitude + 0.35), Style.vary(color, rng, 0.03), nil, Style.solid())
		-- side beams under the deck edge
		for _, side in { -1, 1 } do
			Style.block(
				m,
				frame * CFrame.new(side * (width / 2 + 0.2), -0.25, 0),
				Vector3.new(0.5, 0.9, seg.Magnitude + 0.3),
				C.WoodDark,
				nil,
				Style.tiny()
			)
		end
	end
	if o.Rails ~= false then
		for i = 0, n do
			local p = point(i / n)
			for _, side in { -1, 1 } do
				local tall = (i == 0 or i == n)
				local h = if tall then 3.4 else 2.6
				Style.block(
					m,
					CFrame.new(p + right * side * (width / 2 + 0.3) + Vector3.new(0, h / 2, 0)),
					Vector3.new(0.7, h, 0.7),
					C.WoodDark
				)
			end
		end
		for i = 0, n - 1 do
			local a, b = point(i / n), point((i + 1) / n)
			for _, side in { -1, 1 } do
				local pa = a + right * side * (width / 2 + 0.3) + Vector3.new(0, 2.4, 0)
				local pb = b + right * side * (width / 2 + 0.3) + Vector3.new(0, 2.4, 0)
				local seg = pb - pa
				local frame = CFrame.fromMatrix((pa + pb) / 2, right, right:Cross(seg.Unit), -seg.Unit)
				Style.block(m, frame, Vector3.new(0.4, 0.4, seg.Magnitude + 0.5), C.Wood, nil, Style.decor({ CastShadow = false }))
			end
		end
	end
	return m
end

--[[
	Walkable ground path strip from `from` to `to` (flat, non-collide over
	the solid ground, like the roads). opts.Kind = "Cobble" (default) |
	"Dirt" | "Plank"; TileEvery (studs between tile rows, default 3.2;
	0 = none); CurbEvery (studs between curb stones, default 0 = none).
]]
function Style.path(parent: Instance, from: Vector3, to: Vector3, width: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Path", parent)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local frame = CFrame.fromMatrix((from + to) / 2, right, Vector3.new(0, 1, 0), -dir)
	local kind = o.Kind or "Cobble"
	local baseColor = if kind == "Dirt" then C.DirtLight elseif kind == "Plank" then C.Plank else C.Cobble
	local full = length + width
	Style.block(m, frame * CFrame.new(0, 0.08, 0), Vector3.new(width, 0.3, full), baseColor, nil, Style.tiny({ CanQuery = true }))
	local every = o.TileEvery or 3.2
	if every > 0 then
		local rows = math.floor(full / every)
		for i = 0, rows - 1 do
			local z = -full / 2 + (i + 0.5) * every
			local tw = rng:range(1.6, 2.6)
			local x = rng:range(-width / 2 + tw / 2 + 0.3, width / 2 - tw / 2 - 0.3)
			local shade = if kind == "Dirt"
				then C.Dirt
				elseif kind == "Plank" then C.WoodLight
				elseif rng:chance(0.5) then C.FlagLight
				else C.CobbleDark
			local size = if kind == "Plank" then Vector3.new(width - 0.2, 0.08, every * 0.45) else Vector3.new(tw, 0.08, rng:range(1.3, 2))
			if kind == "Plank" then
				x = 0
			end
			Style.block(m, frame * CFrame.new(x, 0.26, z), size, Style.vary(shade, rng, 0.05), nil, Style.tiny())
		end
	end
	local curb = o.CurbEvery or 0
	if curb > 0 then
		local count = math.floor(full / curb)
		for i = 0, count - 1 do
			local side = if i % 2 == 0 then -1 else 1
			local z = -full / 2 + (i + 0.5) * curb
			Style.block(
				m,
				frame * CFrame.new(side * (width / 2 + 0.3), 0.25, z),
				Vector3.new(1.1, 0.5, rng:range(1.6, 2.4)),
				Style.vary(C.StoneDark, rng, 0.06),
				nil,
				Style.tiny()
			)
		end
	end
	return m
end

--[[
	Voxel cliff chunk: stepped stone columns with a grass cap and a dirt
	band, plus protruding accent stones on the front. `base` = bottom
	center, front = LookVector, size = (width, height, depth). opts: Color,
	Grass (default true), Columns.
]]
function Style.voxelCliff(parent: Instance, base: CFrame, size: Vector3, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Cliff", parent)
	local color = o.Color or C.StoneDark
	local n = o.Columns or math.max(2, math.floor(size.X / 6 + 0.5))
	local colW = size.X / n
	for i = 0, n - 1 do
		local x = -size.X / 2 + colW * (i + 0.5)
		local h = size.Y * rng:range(0.62, 1)
		local d = size.Z * rng:range(0.8, 1)
		local z = rng:range(-0.12, 0.12) * size.Z
		local col = base * CFrame.new(x, 0, z)
		Style.block(m, col * CFrame.new(0, h / 2, 0), Vector3.new(colW * 1.04, h, d), Style.vary(color, rng, 0.05), nil, Style.solid())
		if o.Grass ~= false then
			Style.block(
				m,
				col * CFrame.new(0, h - 0.6, 0),
				Vector3.new(colW * 1.04 + 0.4, 1.2, d + 0.4),
				Style.vary(C.DirtDark, rng, 0.04),
				nil,
				Style.tiny()
			)
			Style.block(
				m,
				col * CFrame.new(0, h + 0.4, 0),
				Vector3.new(colW * 1.04 + 0.6, 1, d + 0.6),
				Style.vary(C.Grass, rng, 0.05),
				nil,
				Style.solid()
			)
		end
		-- accent stones on the face
		for _ = 1, 2 do
			local s = rng:range(1.4, 2.6)
			local yy = rng:range(s, math.max(s + 0.1, h - 2))
			Style.block(
				m,
				col * CFrame.new(rng:range(-colW * 0.35, colW * 0.35), yy, -d / 2 - 0.15),
				Vector3.new(s * 1.2, s, 0.6),
				Style.vary(if rng:chance(0.5) then C.Stone else C.StoneDeep, rng, 0.05),
				nil,
				Style.tiny()
			)
		end
	end
	return m
end

---------------------------------------------------------------- small props

--[[
	Voxel boulder: 2-3 stacked, slightly offset cubes (one may tilt a
	little). `position` = ground point, size = rough width. opts: Color
	(default Stone), Solid (default true: players bump into it).
]]
function Style.boulder(parent: Instance, position: Vector3, size: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Boulder", parent)
	local color = o.Color or C.Stone
	local props = if o.Solid == false then Style.ghost() else Style.decor()
	local yaw = CFrame.Angles(0, rng:int(0, 3) * math.pi / 2 + rng:range(-0.2, 0.2), 0)
	local base = CFrame.new(position) * yaw
	local h = size * rng:range(0.55, 0.75)
	Style.block(
		m,
		base * CFrame.new(0, h / 2, 0),
		Vector3.new(size, h, size * rng:range(0.75, 0.95)),
		Style.vary(color, rng, 0.05),
		nil,
		props
	)
	local top = size * rng:range(0.5, 0.65)
	Style.block(
		m,
		base * CFrame.new(rng:range(-0.15, 0.15) * size, h + top * 0.32, rng:range(-0.12, 0.12) * size) * Geo.randomTilt(rng, 0.12),
		Vector3.new(top, top * 0.7, top),
		Style.vary(color:Lerp(C.StoneLight, 0.3), rng, 0.05),
		nil,
		Style.tiny({ CastShadow = true })
	)
	if rng:chance(0.5) then
		local s = size * 0.4
		Style.block(
			m,
			base * CFrame.new(size * 0.55, s * 0.35, size * 0.2),
			Vector3.new(s, s * 0.7, s),
			Style.vary(color:Lerp(C.StoneDeep, 0.3), rng, 0.05),
			nil,
			Style.tiny()
		)
	end
	return m
end

--[[
	Voxel stone pillar: a plinth, a shaft of stacked blocks with alternating
	small offsets and a capital. `base` = bottom center. opts: Color, Width
	(default 2.4), Cap (default true), Glow (Color3: a neon band near the top).
]]
function Style.pillar(parent: Instance, base: CFrame, height: number, rng: Rng.Rng, opts: Opts?): Model
	local o: Opts = opts or {}
	local m = Style.model("Pillar", parent)
	local color = o.Color or C.Stone
	local w = o.Width or 2.4
	Style.block(m, base * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.8, 0.8, w + 0.8), Style.vary(C.StoneDark, rng, 0.04), nil, Style.solid())
	local blocks = math.max(2, math.floor((height - 1.6) / 2.2 + 0.5))
	local bh = (height - 1.6) / blocks
	for i = 0, blocks - 1 do
		local jitter = if i % 2 == 0 then 0.12 else -0.12
		local shade = if i % 2 == 0 then color else color:Lerp(C.StoneLight, 0.18)
		Style.block(
			m,
			base * CFrame.new(jitter, 0.8 + bh * (i + 0.5), -jitter),
			Vector3.new(w, bh - 0.08, w),
			Style.vary(shade, rng, 0.04),
			nil,
			Style.solid()
		)
	end
	if o.Cap ~= false then
		Style.block(
			m,
			base * CFrame.new(0, height - 0.4, 0),
			Vector3.new(w + 0.7, 0.8, w + 0.7),
			Style.vary(C.StoneDark, rng, 0.04),
			nil,
			Style.solid()
		)
	end
	if o.Glow then
		Style.block(m, base * CFrame.new(0, height - 1.3, 0), Vector3.new(w + 0.12, 0.3, w + 0.12), o.Glow, NEON, Style.tiny())
	end
	return m
end

--[[
	Lit window: dark frame, warm neon pane, wooden cross bars and a sill.
	`cf` = pane center, front = LookVector (outward). opts: Color (pane,
	default Lamp), Frame (default WoodDark), Bars (default true). 4-7 parts.
]]
function Style.window(parent: Instance, cf: CFrame, width: number, height: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local frameColor = o.Frame or C.WoodDark
	Style.block(parent, cf * CFrame.new(0, 0, 0.1), Vector3.new(width + 0.5, height + 0.5, 0.3), frameColor, nil, Style.tiny())
	local pane = Style.block(parent, cf * CFrame.new(0, 0, -0.08), Vector3.new(width, height, 0.2), o.Color or C.Lamp, NEON, Style.tiny())
	pane.Name = "WindowGlow"
	if o.Bars ~= false then
		Style.block(parent, cf * CFrame.new(0, 0, -0.22), Vector3.new(0.22, height, 0.12), frameColor, nil, Style.tiny())
		Style.block(parent, cf * CFrame.new(0, 0, -0.22), Vector3.new(width, 0.22, 0.12), frameColor, nil, Style.tiny())
	end
	Style.block(parent, cf * CFrame.new(0, -height / 2 - 0.3, -0.2), Vector3.new(width + 0.9, 0.3, 0.6), frameColor, nil, Style.tiny())
	return pane
end

function Style.crate(parent: Instance, base: CFrame, rng: Rng.Rng, size: number?): Model
	local m = Style.model("Crate", parent)
	local s = size or rng:range(2, 2.8)
	local cf = base * CFrame.Angles(0, rng:int(0, 3) * math.pi / 2 + rng:range(-0.15, 0.15), 0)
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Style.vary(C.WoodLight, rng, 0.05))
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.1, s * 0.2, s + 0.1), C.WoodDark, nil, Style.tiny())
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s * 0.2, s + 0.1, s + 0.1), C.WoodDark, nil, Style.tiny())
	return m
end

function Style.barrel(parent: Instance, position: Vector3, rng: Rng.Rng, color: Color3?): Model
	local m = Style.model("Barrel", parent)
	local h = 2.8
	Geo.cylinder(m, position + Vector3.new(0, h / 2, 0), h, 2.2, Style.vary(color or C.Wood, rng, 0.05), SMOOTH, Style.decor())
	for _, f in { 0.22, 0.78 } do
		Geo.cylinder(m, position + Vector3.new(0, h * f, 0), 0.25, 2.32, C.Iron, SMOOTH, Style.tiny())
	end
	Geo.cylinder(m, position + Vector3.new(0, h + 0.05, 0), 0.1, 1.8, C.WoodDark, SMOOTH, Style.tiny())
	return m
end

return Style
