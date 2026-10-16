--[[
	Builds physical items (ore chunks, ingots, gear) and still display copies.

	Physical items: a Model whose PrimaryPart "Body" is the only colliding
	part; decoration parts are welded, massless and non-colliding, so one
	item = one cheap physics body. Attributes are set by ItemService.

	Ore looks (design v2):
	- Raw = "Dirty Ore": the same dull crust chunk for every ore (same size,
	  shape and part count); only a tiny glint shows the ore's Glow color.
	  Rarity stays hidden until the ore is cleaned.
	- Clean: every ore has its own silhouette from OreData.Shape (a recipe in
	  SHAPES below, built in "unit" space: bottom center at the origin, about
	  2 studs big). Clean items use CleanScale; Body is an invisible box
	  around the shape, so the look never changes the physics.
	- display(): the same recipe with extra details (DisplayScale), anchored,
	  for podiums and the Ore Pen pile.
	Rarity readability (ore-design skill): Common no glow, Uncommon faint
	veins, Rare glowing veins/tips, Epic + sparkles, Legendary + light,
	Mythic + pulse and orbiting motes. Neon only on veins and tips.
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local ItemBuilder = {}

export type ItemInfo = {
	Kind: string, -- Raw | Clean | Crushed | Ingot | Gear
	OreId: string,
	Grade: string?,
	Recipe: string?,
}

ItemBuilder.CleanScale = 0.85 -- unit recipe -> physical clean ore
ItemBuilder.DisplayScale = 1.15 -- unit recipe -> podium / pen display
ItemBuilder.Budget = { Raw = 6, Clean = 8, Ingot = 4, Display = 14 }

-- Dirty Ore crust (the same for every ore: it must not hint at the rarity).
ItemBuilder.DirtyCrust = Color3.fromRGB(122, 106, 92)
ItemBuilder.DirtyCrustLight = Color3.fromRGB(146, 128, 108)
ItemBuilder.DirtyCrustDark = Color3.fromRGB(92, 78, 66)
ItemBuilder.DirtyMud = Color3.fromRGB(96, 74, 54)

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local BLACK = Color3.new(0, 0, 0)

-- A cube turned so one corner points straight up: a 3-sided point at both ends.
local VERTEX_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, math.pi / 4, 0)
-- Roblox cylinders run along X; this turns X to Y.
local UP_CYL = CFrame.Angles(0, 0, math.pi / 2)

local function P(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(x, y, z)
end

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

--[[
	Neon color that keeps its hue under bloom: never near-white (white Neon
	blooms into a blob), never fully bright.
]]
function ItemBuilder.glowColor(color: Color3): Color3
	local h, s, v = color:ToHSV()
	-- strong saturation keeps the hue in the bloom's core (pale glows turn into white blobs)
	local safe = Color3.fromHSV(h, math.max(s, 0.62), math.min(v, 0.84))
	-- bright hues (cyan, yellow) bloom first: cap the luminance a little
	local luminance = 0.2126 * safe.R + 0.7152 * safe.G + 0.0722 * safe.B
	if luminance > 0.7 then
		safe = safe:Lerp(BLACK, 1 - 0.7 / luminance)
	end
	return safe
end

---------------------------------------------------------------- specs

type Spec = {
	Shape: string, -- Block | Wedge | Ball | Cyl
	CF: CFrame, -- unit space, relative to the bottom center
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	Neon: boolean,
}

type Pal = {
	Main: Color3,
	Light: Color3,
	Dark: Color3,
	Base: Color3,
	Glow: Color3,
	GlowDark: Color3,
	Dull: Color3,
	Material: Enum.Material,
	Reflectance: number,
}

type Ctx = {
	Specs: { Spec },
	Pal: Pal,
	Rng: Rng.Rng,
	Order: number,
	Full: boolean,
}

local function palette(ore: OreData.Ore): Pal
	local h, s, v = ore.Color:ToHSV()
	local material = ore.Material
	local reflectance = 0
	if material == GLASS then
		-- Glass at Transparency 0 renders opaque in Roblox; a glossy plastic reads the same
		-- in game and in the preview. Real glass is only used for see-through shells.
		-- Common and Uncommon gems stay matte (no sun glare): shine comes with rarity.
		material = SMOOTH
		reflectance = if Rarity.get(ore.Rarity).Order <= 2 then 0.04 else 0.2
	elseif material == Enum.Material.SmoothPlastic then
		reflectance = 0.08
	end
	local glow = ItemBuilder.glowColor(ore.Glow)
	-- near-white surfaces glare into a bloom blob in sunlight: keep them a touch below white
	local cap = if s < 0.15 then 0.88 else 1
	v = math.min(v, cap)
	local main = Color3.fromHSV(h, s, v)
	return {
		Main = main,
		Light = Color3.fromHSV(h, s * 0.78, math.min(cap, v + 0.2 + (1 - v) * 0.12)),
		Dark = Color3.fromHSV(h, math.min(1, s * 1.05), v * 0.66),
		Base = ore.Crust:Lerp(Color3.fromHSV(h, s * 0.5, v * 0.5), 0.3),
		Glow = glow,
		GlowDark = glow:Lerp(BLACK, 0.28),
		Dull = main:Lerp(ore.Glow, 0.55):Lerp(BLACK, 0.18),
		Material = material,
		Reflectance = reflectance,
	}
end

--[[
	Tones: "Main" | "Light" | "Dark" (ore surface), "Base" (matrix stone),
	"Vein" (rarity glow: dull / faint Neon / Neon), "Tip" (Neon from Rare up,
	else the light shade), "Neon" / "NeonDark" (always glowing, Epic+ shapes),
	"Glass" (see-through shell), or a Color3 (plain plastic).
]]
type Tone = string | Color3

local function resolve(c: Ctx, tone: Tone): (Color3, Enum.Material, number, number, boolean)
	local p = c.Pal
	if typeof(tone) == "Color3" then
		return tone, SMOOTH, 0, 0, false
	end
	if tone == "Main" then
		return p.Main, p.Material, p.Reflectance, 0, false
	elseif tone == "Light" then
		return p.Light, p.Material, p.Reflectance, 0, false
	elseif tone == "Dark" then
		return p.Dark, p.Material, p.Reflectance, 0, false
	elseif tone == "Base" then
		return p.Base, SMOOTH, 0, 0, false
	elseif tone == "Vein" then
		if c.Order <= 1 then
			return p.Dull, SMOOTH, 0, 0, false
		elseif c.Order == 2 then
			return p.GlowDark, NEON, 0, 0.3, true
		end
		return p.Glow, NEON, 0, 0, true
	elseif tone == "Tip" then
		if c.Order >= 3 then
			return p.Glow, NEON, 0, 0, true
		end
		return p.Light, p.Material, p.Reflectance, 0, false
	elseif tone == "Neon" then
		return p.Glow, NEON, 0, 0, true
	elseif tone == "NeonDark" then
		return p.GlowDark, NEON, 0, 0, true
	elseif tone == "Glass" then
		return p.Main:Lerp(p.Light, 0.4), GLASS, 0.1, 0.32, false
	end
	error("unknown tone " .. tostring(tone))
end

local function put(c: Ctx, shape: string, cf: CFrame, size: Vector3, tone: Tone): Spec
	local color, material, reflectance, transparency, neon = resolve(c, tone)
	local spec: Spec = {
		Shape = shape,
		CF = cf,
		Size = size,
		Color = color,
		Material = material,
		Transparency = transparency,
		Reflectance = reflectance,
		Neon = neon,
	}
	table.insert(c.Specs, spec)
	return spec
end

local function block(c: Ctx, cf: CFrame, size: Vector3, tone: Tone): Spec
	return put(c, "Block", cf, size, tone)
end

local function wedge(c: Ctx, cf: CFrame, size: Vector3, tone: Tone): Spec
	return put(c, "Wedge", cf, size, tone)
end

local function ball(c: Ctx, position: Vector3, diameter: number, tone: Tone): Spec
	return put(c, "Ball", CFrame.new(position), Vector3.new(diameter, diameter, diameter), tone)
end

-- Cylinder whose axis is cf's UpVector.
local function cyl(c: Ctx, cf: CFrame, height: number, diameter: number, tone: Tone): Spec
	return put(c, "Cyl", cf * UP_CYL, Vector3.new(height, diameter, diameter), tone)
end

-- Crystal point: a cube standing on a corner (cf = its center).
local function point(c: Ctx, cf: CFrame, size: number, tone: Tone): Spec
	return put(c, "Block", cf * VERTEX_UP, Vector3.new(size, size, size), tone)
end

-- Square bar from a to b.
local function beam(c: Ctx, a: Vector3, b: Vector3, width: number, tone: Tone): Spec
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return put(c, "Block", CFrame.lookAt((a + b) / 2, b, up), Vector3.new(width, width, dir.Magnitude), tone)
end

-- Hexagonal prism (axis = cf.UpVector) from three crossed blocks.
local function hexPrism(c: Ctx, cf: CFrame, radius: number, height: number, tones: { Tone })
	for i = 0, 2 do
		block(c, cf * A(0, i * math.pi / 3, 0), Vector3.new(radius, height, radius * math.sqrt(3)), tones[i + 1])
	end
end

-- Point on a ball's surface (for glints and speckles).
local function onBall(center: Vector3, diameter: number, dir: Vector3, inset: number?): Vector3
	return center + dir.Unit * (diameter / 2 - (inset or 0))
end

---------------------------------------------------------------- the 30 shapes

local SHAPES: { [string]: (Ctx) -> () } = {}

-- typed rows for the recipe tables below
type Piece = { cf: CFrame, size: Vector3, tone: string }
type Stick = { cf: CFrame, w: number, len: number, tone: string }
type Blob = { pos: Vector3, d: number, tone: string }

local function piece(cf: CFrame, size: Vector3, tone: string): Piece
	return { cf = cf, size = size, tone = tone }
end

local function stick(cf: CFrame, w: number, len: number, tone: string): Stick
	return { cf = cf, w = w, len = len, tone = tone }
end

local function blob(pos: Vector3, d: number, tone: string): Blob
	return { pos = pos, d = d, tone = tone }
end

-- Coal: black lumps that remember fire.
SHAPES.Lump = function(c)
	-- a heap of glossy black chunks, each turned its own way
	local chunks = {
		piece(P(0.05, 0.48, 0.05) * A(0.55, 0.4, 0.35), V(1.0, 0.85, 0.92), "Main"),
		piece(P(-0.52, 0.38, 0.22) * A(-0.4, 1.3, 0.6), V(0.82, 0.7, 0.78), "Light"),
		piece(P(0.5, 0.36, -0.28) * A(0.3, 2.2, -0.5), V(0.78, 0.66, 0.74), "Main"),
		piece(P(-0.08, 0.95, -0.18) * A(0.7, 0.9, -0.4), V(0.6, 0.52, 0.58), "Light"),
	}
	if c.Full then
		table.insert(chunks, piece(P(0.62, 0.24, 0.5) * A(0.5, 0.4, 0.6), V(0.44, 0.4, 0.42), "Main"))
		table.insert(chunks, piece(P(-0.7, 0.2, -0.48) * A(-0.3, 1.1, 0.5), V(0.4, 0.36, 0.4), "Light"))
	end
	for _, ch in chunks do
		local spec = block(c, ch.cf, ch.size, ch.tone)
		spec.Reflectance = 0.16
	end
	-- dull embers: Common ores do not glow
	block(c, chunks[1].cf * P(0.1, 0.43, 0.05), V(0.34, 0.06, 0.28), "Vein")
	block(c, chunks[2].cf * P(-0.05, 0.36, 0.1), V(0.3, 0.06, 0.22), "Vein")
	if c.Full then
		block(c, chunks[3].cf * P(0.05, 0.34, 0), V(0.26, 0.06, 0.24), "Vein")
	end
end

-- Copper: a little copper tree.
SHAPES.Branch = function(c)
	block(c, P(0, 0.22, 0) * A(0, 0.4, 0.05), V(0.95, 0.44, 0.82), "Dark")
	local trunk = P(0, 0.95, 0) * A(0.05, 0.4, -0.06)
	block(c, trunk, V(0.34, 1.2, 0.34), "Main")
	local left = P(-0.3, 1.02, 0.05) * A(0.1, 0.4, 0.8)
	block(c, left, V(0.27, 0.8, 0.27), "Main")
	local right = P(0.3, 1.15, -0.05) * A(-0.1, 0.4, -0.75)
	block(c, right, V(0.26, 0.72, 0.26), "Main")
	ball(c, (trunk * P(0, 0.62, 0)).Position, 0.46, "Light")
	ball(c, (left * P(0, 0.42, 0)).Position, 0.38, "Light")
	ball(c, (right * P(0, 0.38, 0)).Position, 0.36, "Light")
	if c.Full then
		local back = P(0.05, 0.88, -0.28) * A(-0.75, 0.2, 0.1)
		block(c, back, V(0.24, 0.7, 0.24), "Main")
		ball(c, (back * P(0, 0.37, 0)).Position, 0.34, "Light")
		local patina = Color3.fromRGB(86, 170, 140)
		block(c, P(0.3, 0.44, 0.22) * A(0, 0.4, 0), V(0.34, 0.06, 0.26), patina)
		block(c, P(-0.34, 0.3, -0.36) * A(0, 0.4, 0.4), V(0.3, 0.22, 0.06), patina)
	end
end

-- Tin: pale plates standing like old books.
SHAPES.Slab = function(c)
	block(c, P(0, 0.08, 0), V(1.6, 0.16, 1.2), "Dark")
	local heights = { 1.42, 1.18, 1.62, 1.06 }
	local leans = { 0.05, -0.03, 0.02, -0.2 }
	for i, h in heights do
		local lean = leans[i]
		local x = -0.52 + (i - 1) * 0.35 - math.sin(lean) * h / 2
		local cf = P(x, 0.16 + h / 2 * math.cos(lean), 0) * A(0, 0, lean)
		block(c, cf, V(0.28, h, 1.1), if i % 2 == 0 then "Light" else "Main")
		if i == 1 or i == 3 then
			block(c, cf * P(0, h / 2, 0), V(0.3, 0.06, 1.12), "Light")
		end
	end
	if c.Full then
		block(c, P(0.05, 0.25, 0.45), V(1.5, 0.18, 0.4), "Main")
		block(c, P(0.86, 0.3, 0) * A(0, 0, -0.4), V(0.12, 0.5, 0.9), "Vein")
	end
end

-- Iron: intergrown metal cubes with rust bands.
SHAPES.Block = function(c)
	local main = P(0, 0.53, 0) * A(0, 0.3, 0)
	block(c, main, V(1.06, 1.06, 1.06), "Main")
	block(c, P(0.56, 0.36, 0.38) * A(0, 0.95, 0), V(0.72, 0.72, 0.72), "Light")
	block(c, P(-0.34, 1.12, -0.18) * A(0.3, 0.6, 0.35), V(0.56, 0.56, 0.56), "Dark")
	block(c, main * P(0, 0.53, 0), V(0.9, 0.05, 0.9), "Light")
	block(c, main * P(0, -0.14, 0), V(1.1, 0.12, 1.1), "Vein")
	block(c, main * P(0, 0.2, 0), V(1.1, 0.06, 1.1), "Vein")
	if c.Full then
		block(c, P(-0.55, 0.22, 0.55) * A(0.2, 0.3, 0.1), V(0.44, 0.44, 0.44), "Main")
		block(c, P(0.56, 0.36, 0.38) * A(0, 0.95, 0), V(0.75, 0.08, 0.75), "Vein")
	end
end

-- Quartz: clear spikes on a small matrix stone.
SHAPES.Spike = function(c)
	block(c, P(0, 0.17, 0) * A(0, 0.5, 0), V(1.0, 0.34, 0.86), "Base")
	local spikes = {
		stick(P(0.04, 0.24, 0) * A(0.06, 0.2, -0.08), 0.42, 1.75, "Light"),
		stick(P(-0.26, 0.24, 0.12) * A(0.25, 0.9, 0.5), 0.34, 1.25, "Main"),
		stick(P(0.3, 0.24, -0.12) * A(-0.3, -0.6, -0.48), 0.32, 1.05, "Main"),
	}
	if c.Full then
		table.insert(spikes, stick(P(0.1, 0.22, 0.28) * A(0.55, 0.3, -0.1), 0.26, 0.7, "Main"))
		table.insert(spikes, stick(P(-0.12, 0.22, -0.3) * A(-0.5, 0.1, 0.15), 0.24, 0.62, "Light"))
	end
	for i, s in spikes do
		local cf = s.cf * P(0, s.len / 2, 0) * A(0, math.pi / 4, 0)
		-- clear crystal bodies (see-through glass), solid frosted tips
		block(c, cf, V(s.w, s.len, s.w), if i == 1 then "Glass" else s.tone)
		point(c, s.cf * P(0, s.len, 0), s.w * 0.9, "Tip")
	end
end

-- Silver: a bright drop.
SHAPES.Drop = function(c)
	-- a round belly and a stepped cone that ends in a point
	ball(c, V(0, 0.6, 0), 1.2, "Main")
	cyl(c, P(0, 1.12, 0), 0.24, 0.98, "Main")
	cyl(c, P(0, 1.34, 0), 0.22, 0.7, "Light")
	cyl(c, P(0, 1.53, 0), 0.18, 0.42, "Light")
	point(c, P(0, 1.66, 0) * A(0, 0.4, 0), 0.24, "Light")
	cyl(c, P(0, 0.64, 0), 0.06, 1.22, "Vein")
	if c.Full then
		cyl(c, P(0, 0.03, 0), 0.06, 1.7, "Light")
		ball(c, V(0.82, 0.13, 0.48), 0.26, "Main")
		ball(c, V(-0.74, 0.1, -0.56), 0.2, "Main")
		cyl(c, P(0, 1.0, 0), 0.05, 1.02, "Vein")
		ball(c, onBall(V(0, 0.6, 0), 1.2, V(-0.45, 0.55, 0.7), 0.1), 0.24, "Light")
	end
end

-- Amethyst: a crown of violet points in a dark geode bed.
SHAPES.Cluster = function(c)
	block(c, P(0, 0.24, 0) * A(0, 0.3, 0), V(1.5, 0.48, 1.3), "Base")
	block(c, P(0, 0.48, 0) * A(0, 1.1, 0), V(1.12, 0.1, 0.98), "Vein")
	local points = {
		stick(P(0, 0.66, 0), 0.74, 0, "Light"),
		stick(P(-0.42, 0.54, 0.2) * A(0.2, 0, 0.35), 0.58, 0, "Main"),
		stick(P(0.42, 0.52, -0.12) * A(-0.15, 0, -0.38), 0.56, 0, "Main"),
		stick(P(0.12, 0.5, 0.44) * A(0.42, 0, -0.1), 0.48, 0, "Light"),
		stick(P(-0.16, 0.5, -0.44) * A(-0.4, 0, 0.12), 0.46, 0, "Dark"),
	}
	if c.Full then
		table.insert(points, stick(P(0.5, 0.42, 0.36) * A(0.4, 0, -0.45), 0.36, 0, "Main"))
		table.insert(points, stick(P(-0.52, 0.42, -0.3) * A(-0.3, 0, 0.5), 0.34, 0, "Light"))
		table.insert(points, stick(P(0.38, 0.44, -0.5) * A(-0.5, 0, -0.2), 0.32, 0, "Main"))
	end
	for i, p in points do
		point(c, p.cf * A(0, i * 0.7, 0), p.w, p.tone)
	end
end

-- Jade: a little cairn of smooth river pebbles.
SHAPES.Pebble = function(c)
	local stack = {
		stick(P(0, 0.21, 0), 1.55, 0.42, "Dark"),
		stick(P(0.06, 0.6, -0.04) * A(0.06, 0.4, -0.06), 1.12, 0.36, "Main"),
		stick(P(-0.02, 0.94, 0.02) * A(-0.06, 1.0, 0.08), 0.74, 0.3, "Main"),
	}
	for _, s in stack do
		cyl(c, s.cf, s.len, s.w, s.tone)
		cyl(c, s.cf * P(0, s.len / 2, 0), 0.08, s.w * 0.84, "Light")
	end
	cyl(c, P(0.06, 0.6, -0.04) * A(0.06, 0.4, -0.06), 0.05, 1.15, "Vein")
	if c.Full then
		cyl(c, P(0.86, 0.13, 0.42) * A(0.1, 0, 0.12), 0.26, 0.62, "Main")
		cyl(c, P(0.87, 0.27, 0.42) * A(0.1, 0, 0.12), 0.06, 0.5, "Light")
		ball(c, V(-0.02, 1.12, 0.02), 0.3, "Light")
	end
end

-- Emberite: flame-shaped shards on a scorched stone.
SHAPES.Shard = function(c)
	block(c, P(0, 0.2, 0) * A(0, 0.3, 0), V(1.05, 0.4, 0.86), "Base")
	local shards = {
		piece(P(0.02, 1.0, 0.05) * A(0.08, 0.25, 0.04), V(0.32, 1.75, 0.82), "Main"),
		piece(P(-0.36, 0.78, 0.12) * A(0, 2.5, 0.22), V(0.3, 1.3, 0.7), "Light"),
		piece(P(0.36, 0.7, -0.14) * A(0.05, -1.4, -0.24), V(0.28, 1.1, 0.62), "Main"),
	}
	if c.Full then
		table.insert(shards, piece(P(-0.1, 0.55, -0.32) * A(-0.3, 3.6, 0.1), V(0.24, 0.8, 0.5), "Light"))
		table.insert(shards, piece(P(0.32, 0.5, 0.3) * A(0.35, 0.9, -0.3), V(0.22, 0.7, 0.45), "Main"))
	end
	for i, s in shards do
		local cf, size = s.cf, s.size
		wedge(c, cf, size, s.tone)
		if i <= 2 or (c.Full and i == 4) then
			-- the glowing top of the flame: a smaller copy of the wedge's tip
			local t = size.Y * 0.3
			local depth = size.Z * t / size.Y
			wedge(c, cf * P(0, size.Y / 2 - t / 2, size.Z / 2 - depth / 2), V(size.X + 0.03, t, depth + 0.01), "Vein")
		end
	end
end

-- Cobalt: deep blue stripes, layer on layer.
SHAPES.Banded = function(c)
	local layers = {
		piece(CFrame.new(), V(1.42, 0.36, 1.26), "Dark"),
		piece(CFrame.new(), V(1.34, 0.3, 1.2), "Light"),
		piece(CFrame.new(), V(1.38, 0.34, 1.22), "Main"),
		piece(CFrame.new(), V(1.24, 0.26, 1.1), "Light"),
		piece(CFrame.new(), V(1.1, 0.3, 0.98), "Main"),
	}
	local y = 0
	local bands: { number } = {}
	for i, layer in layers do
		local h = layer.size.Y
		local yaw = 0.35 + (if i % 2 == 0 then 0.05 else -0.04)
		block(c, P(0, y + h / 2, 0) * A(0, yaw, 0), layer.size, layer.tone)
		y += h
		table.insert(bands, y)
	end
	block(c, P(0, y + 0.06, 0) * A(0, 0.35, 0), V(0.84, 0.12, 0.74), "Light")
	block(c, P(0, bands[2], 0) * A(0, 0.35, 0), V(1.42, 0.07, 1.26), "Vein")
	if c.Full then
		block(c, P(0, bands[4], 0) * A(0, 0.35, 0), V(1.28, 0.06, 1.14), "Vein")
		block(c, P(0.72, 0.16, 0.5) * A(0, 0.9, 0.2), V(0.4, 0.3, 0.36), "Dark")
	end
end

-- Gold: a bumpy nugget with glowing glints.
SHAPES.Nugget = function(c)
	local blobs = {
		blob(V(0, 0.52, 0), 1.04, "Main"),
		blob(V(0.46, 0.42, 0.2), 0.82, "Main"),
		blob(V(-0.44, 0.4, -0.14), 0.78, "Dark"),
		blob(V(0.08, 0.95, -0.12), 0.66, "Light"),
		blob(V(-0.3, 0.82, 0.32), 0.48, "Light"),
	}
	if c.Full then
		table.insert(blobs, blob(V(0.62, 0.22, -0.42), 0.42, "Main"))
		table.insert(blobs, blob(V(-0.66, 0.18, 0.46), 0.34, "Light"))
	end
	for _, b in blobs do
		ball(c, b.pos, b.d, b.tone)
	end
	ball(c, onBall(V(0.46, 0.42, 0.2), 0.82, V(0.6, 0.6, 0.25), 0.06), 0.2, "Vein")
	ball(c, onBall(V(0, 0.52, 0), 1.04, V(-0.3, 0.1, 0.95), 0.06), 0.18, "Vein")
	if c.Full then
		ball(c, onBall(V(0.08, 0.95, -0.12), 0.66, V(-0.2, 0.8, -0.5), 0.05), 0.16, "Vein")
	end
end

-- Ruby: a cut gem (round crown, pointed pavilion).
SHAPES.Gem = function(c)
	-- a faceted six-sided gem, tipped a little so the pointed pavilion shows
	local g = P(0, 0.9, 0) * A(-0.18, 0, 0.14) -- girdle center
	point(c, g * P(0, -0.13, 0) * A(0, 0.25, 0), 0.78, "Main")
	hexPrism(c, g * P(0, 0.15, 0), 0.72, 0.3, { "Main", "Dark", "Main" })
	cyl(c, g * P(0, 0.4, 0), 0.22, 1.12, "Light")
	cyl(c, g * P(0, 0.53, 0), 0.06, 0.7, "Tip")
	if c.Full then
		cyl(c, g * P(0, 0.02, 0), 0.06, 1.5, "Vein")
		point(c, P(0.9, 0.2, -0.35) * A(0.3, 0.5, 0.2), 0.3, "Main")
		point(c, P(-0.85, 0.16, -0.45) * A(-0.2, 1.2, 0.3), 0.24, "Light")
	end
end

-- Azurium: two crystals that always grow crossed.
SHAPES.Twin = function(c)
	local center = V(0, 1.0, 0)
	for i, rot in { A(0.05, 0, 0.55), A(-0.12, 0.35, -0.55) } do
		local cf = CFrame.new(center) * rot
		block(c, cf * A(0, math.pi / 4, 0), V(0.46, 1.7, 0.46), if i == 1 then "Main" else "Light")
		point(c, cf * P(0, 0.85, 0), 0.42, "Tip")
		point(c, cf * P(0, -0.85, 0), 0.42, "Light")
	end
	ball(c, center, 0.42, "Vein")
	if c.Full then
		local small = P(0.55, 0.0, 0.45) * A(0.35, 0.8, -0.25)
		block(c, small * P(0, 0.35, 0) * A(0, math.pi / 4, 0), V(0.26, 0.7, 0.26), "Main")
		point(c, small * P(0, 0.72, 0), 0.24, "Tip")
		block(c, P(0, 0.08, 0) * A(0, 0.5, 0), V(0.9, 0.16, 0.7), "Base")
	end
end

-- Sapphire: a six-sided barrel with glowing hoops.
SHAPES.Barrel = function(c)
	local r, h = 0.62, 1.2
	hexPrism(c, P(0, 0.26 + h / 2, 0), r, h, { "Main", "Dark", "Main" })
	cyl(c, P(0, 0.13, 0), 0.26, 0.92, "Dark")
	cyl(c, P(0, 0.26 + h + 0.12, 0), 0.24, 0.92, "Light")
	cyl(c, P(0, 0.26 + h + 0.27, 0), 0.07, 0.52, "Tip")
	cyl(c, P(0, 0.26 + h * 0.5, 0), 0.09, 1.3, "Vein")
	if c.Full then
		cyl(c, P(0, 0.26 + h * 0.18, 0), 0.07, 1.3, "Vein")
		cyl(c, P(0, 0.26 + h * 0.82, 0), 0.07, 1.3, "Vein")
		point(c, P(0.78, 0.18, 0.4) * A(0.3, 0.2, -0.3), 0.3, "Light")
	end
end

-- Emerald: a long hexagonal prism with stepped ends.
SHAPES.Prism = function(c)
	-- a long six-sided crystal leaning out of a stone, its flat top stepped
	block(c, P(0, 0.2, 0) * A(0, 0.4, 0), V(1.1, 0.4, 0.95), "Base")
	local r, length = 0.38, 1.7
	local axis = P(-0.12, 0.22, 0) * A(0.12, 0.3, -0.36) * P(0, length / 2, 0)
	hexPrism(c, axis, r, length, { "Main", "Light", "Dark" })
	cyl(c, axis * P(0, length / 2 + 0.06, 0), 0.14, 0.52, "Light")
	cyl(c, axis * P(0, length / 2 + 0.15, 0), 0.06, 0.3, "Tip")
	block(c, axis * P(r * 0.96, 0, 0) * A(0, math.pi / 4, 0), V(0.08, length * 0.8, 0.08), "Vein")
	if c.Full then
		local small = P(0.42, 0.25, 0.18) * A(-0.25, 0.9, 0.5) * P(0, 0.4, 0)
		block(c, small * A(0, math.pi / 4, 0), V(0.26, 0.8, 0.26), "Main")
		cyl(c, small * P(0, 0.42, 0), 0.06, 0.22, "Tip")
	end
end

-- Diamond: two pyramids back to back, a bright core inside.
SHAPES.Octa = function(c)
	-- a stepped bipyramid: slabs grow to a glowing girdle, then shrink to a point
	local turn = A(0, math.pi / 4 + 0.2, 0)
	local steps = {
		piece(P(0, 0.62, 0), V(0.8, 0.3, 0.8), "Dark"),
		piece(P(0, 0.9, 0), V(1.2, 0.26, 1.2), "Light"),
		piece(P(0, 1.16, 0), V(0.86, 0.26, 0.86), "Main"),
		piece(P(0, 1.4, 0), V(0.5, 0.24, 0.5), "Light"),
	}
	for _, st in steps do
		block(c, st.cf * turn, st.size, st.tone)
	end
	block(c, P(0, 0.9, 0) * turn, V(1.25, 0.07, 1.25), "Neon")
	point(c, P(0, 1.58, 0) * turn, 0.32, "Neon")
	point(c, P(0, 0.34, 0) * turn, 0.44, "Dark")
	if c.Full then
		point(c, P(0.72, 0.2, 0.3) * A(0.2, 1, 0.3), 0.3, "Light")
		point(c, P(-0.66, 0.18, -0.36) * A(-0.3, 0.4, 0.2), 0.26, "Main")
		point(c, P(0.1, 0.16, -0.75) * A(0.4, 2, -0.2), 0.22, "Light")
	end
end

-- Verdantine: living moss on a stone, glowing sprouts.
SHAPES.Moss = function(c)
	block(c, P(0, 0.28, 0) * A(0, 0.3, 0.04), V(1.45, 0.56, 1.25), "Base")
	ball(c, V(-0.3, 0.72, 0.12), 0.8, "Main")
	ball(c, V(0.36, 0.68, -0.12), 0.72, "Light")
	ball(c, V(0.08, 0.98, -0.28), 0.6, "Main")
	ball(c, V(-0.05, 0.9, 0.42), 0.52, "Light")
	beam(c, V(0.25, 0.9, 0.22), V(0.4, 1.45, 0.32), 0.07, "Neon")
	ball(c, V(0.41, 1.48, 0.33), 0.17, "Neon")
	if c.Full then
		ball(c, V(0.58, 0.5, 0.42), 0.46, "Main")
		ball(c, V(-0.62, 0.5, -0.4), 0.44, "Light")
		beam(c, V(-0.35, 1.0, -0.1), V(-0.55, 1.42, -0.18), 0.06, "Neon")
		ball(c, V(-0.56, 1.44, -0.18), 0.15, "NeonDark")
	end
end

-- Obsidian: black glass blades with purple edges.
SHAPES.Blade = function(c)
	block(c, P(0, 0.18, 0) * A(0, 0.25, 0), V(0.95, 0.36, 0.75), "Dark")
	local blades = {
		piece(P(0, 1.05, 0) * A(0, 0.15, 0), V(0.12, 1.75, 0.95), "Main"),
		piece(P(-0.32, 0.86, 0.05) * A(0, 0.7, 0.32), V(0.12, 1.35, 0.8), "Light"),
		piece(P(0.32, 0.82, -0.04) * A(0, -0.4, -0.34), V(0.12, 1.25, 0.75), "Main"),
	}
	if c.Full then
		table.insert(blades, piece(P(0.05, 0.62, 0.3) * A(0.3, 1.9, 0.1), V(0.1, 0.9, 0.6), "Light"))
	end
	for _, b in blades do
		local cf, size = b.cf, b.size
		wedge(c, cf, size, b.tone)
		-- the cutting edge glows along the slope
		local a = (cf * P(0, -size.Y / 2 + 0.08, -size.Z / 2 + 0.05)).Position
		local tip = (cf * P(0, size.Y / 2 - 0.02, size.Z / 2 - 0.01)).Position
		beam(c, a, tip, 0.14, "Neon")
	end
	if c.Full then
		block(c, P(0.6, 0.12, 0.4) * A(0.4, 0.3, 0.6), V(0.3, 0.06, 0.3), "Light")
		block(c, P(-0.6, 0.1, -0.35) * A(-0.3, 1.3, 0.5), V(0.26, 0.06, 0.24), "Main")
	end
end

-- Stormcore: an orb wrapped in lightning rings.
SHAPES.Orb = function(c)
	local center = V(0, 0.66, 0)
	ball(c, center, 1.2, "Main")
	ball(c, onBall(center, 1.2, V(-0.5, 0.6, 0.6), 0.2), 0.42, "Light")
	cyl(c, CFrame.new(center) * A(0.45, 0, 0.35), 0.07, 1.27, "Neon")
	cyl(c, CFrame.new(center) * A(-0.55, 0.4, -0.7), 0.07, 1.27, "NeonDark")
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3 + 0.3
		local dir = V(math.cos(a), 0.35 * (if i == 2 then -1 else 1), math.sin(a))
		point(c, CFrame.new(onBall(center, 1.2, dir, 0.02)) * A(0.3 * i, a, 0.5), 0.2, "Neon")
	end
	if c.Full then
		cyl(c, CFrame.new(center) * A(0.25, 0, -0.2), 0.03, 1.9, "NeonDark").Transparency = 0.55
		ball(c, center + V(0.95, 0.15, 0.15), 0.16, "Neon")
		ball(c, center + V(-0.85, -0.1, -0.45), 0.14, "Neon")
		block(c, P(0, 0.05, 0) * A(0, 0.4, 0), V(0.62, 0.1, 0.62), "Base")
	end
end

-- Moonstone: a round moon standing on a stone, a glowing crescent on both faces.
SHAPES.Disc = function(c)
	block(c, P(0, 0.14, 0), V(0.9, 0.28, 0.56), "Base")
	local face = P(0, 0.96, 0) * A(math.pi / 2, 0, 0) -- cylinder axis along Z
	cyl(c, face, 0.36, 1.6, "Main")
	cyl(c, face, 0.4, 1.44, "Neon")
	local cover = face * P(0.17, 0, -0.1)
	cyl(c, cover, 0.44, 1.32, "Light")
	cyl(c, cover * P(0.28, 0, 0.12), 0.46, 0.3, "Main")
	cyl(c, cover * P(-0.2, 0, -0.26), 0.46, 0.2, "Main")
	if c.Full then
		point(c, P(0.52, 0.32, 0.28) * A(0.3, 0.4, -0.3), 0.26, "Light")
		point(c, P(-0.5, 0.3, -0.26) * A(-0.2, 1.1, 0.4), 0.22, "Main")
		cyl(c, cover * P(0.0, 0, 0.36), 0.46, 0.16, "Main")
	end
end

-- Bloodstone: a dark green polished stone, sprinkled with red.
SHAPES.Speckled = function(c)
	block(c, P(0, 0.24, 0) * A(0, 0.3, 0), V(1.32, 0.48, 1.12), "Dark")
	local center = V(0, 0.7, 0)
	ball(c, center, 1.3, "Main")
	local dots = {
		blob(V(0.5, 0.6, 0.6), 0.2, "Vein"),
		blob(V(-0.7, 0.35, 0.45), 0.17, "Vein"),
		blob(V(0.1, 0.95, -0.2), 0.18, "Vein"),
		blob(V(-0.3, 0.4, -0.8), 0.16, "Vein"),
		blob(V(0.85, 0.2, -0.35), 0.15, "Vein"),
	}
	if c.Full then
		table.insert(dots, blob(V(-0.2, 0.75, 0.6), 0.14, "Vein"))
		table.insert(dots, blob(V(0.4, 0.5, -0.75), 0.13, "Vein"))
		table.insert(dots, blob(V(-0.75, 0.6, -0.1), 0.15, "Vein"))
		table.insert(dots, blob(V(0.15, 0.25, 0.95), 0.12, "Vein"))
	end
	for _, d in dots do
		ball(c, onBall(center, 1.3, d.pos, 0.04), d.d, d.tone)
	end
	if c.Full then
		cyl(c, P(0, 0.44, 0), 0.08, 1.33, "Light")
	end
end

-- Solarite: a twelve-pointed sun with a glowing heart.
SHAPES.Star = function(c)
	local a = 1.3
	local center = P(0, a / math.sqrt(2), 0)
	local tones = { "Main", "Light", "Main" }
	for i, angle in { 45, 15, 75 } do
		block(c, center * A(0, 0, math.rad(angle)), V(a, a, 0.3 + i * 0.02), tones[i])
	end
	block(c, center * A(0, 0, math.rad(0)), V(0.62, 0.62, 0.44), "NeonDark")
	block(c, center * A(0, 0, math.rad(45)), V(0.62, 0.62, 0.46), "Vein")
	cyl(c, center * A(math.pi / 2, 0, 0), 0.5, 0.42, "Light")
	if c.Full then
		block(c, center, V(2.2, 0.06, 0.08), "NeonDark")
		block(c, center, V(0.06, 2.2, 0.08), "NeonDark")
	end
end

-- Voidstone: a black stone cracked open, a violet night sky inside.
SHAPES.Geode = function(c)
	-- split in two: one half lies cut face up, the other stands behind it, both faces glowing
	local star = Color3.fromRGB(255, 236, 170)
	local lying = P(0, 0.25, 0.3)
	block(c, lying, V(1.15, 0.5, 1.0), "Main")
	block(c, lying * P(0, 0.26, 0), V(0.95, 0.04, 0.8), "NeonDark")
	local standing = P(0, 0.62, -0.42) * A(1.2, 0, 0)
	block(c, standing, V(1.1, 0.48, 0.95), "Light")
	block(c, standing * P(0, 0.25, 0), V(0.9, 0.04, 0.76), "NeonDark")
	point(c, lying * P(0.22, 0.32, 0.1) * A(0, 0.5, 0), 0.34, "Tip")
	block(c, standing * P(-0.24, 0.27, 0.15) * A(0, 0.7, 0), V(0.09, 0.03, 0.09), star)
	block(c, lying * P(-0.3, 0.28, -0.12) * A(0, 0.4, 0), V(0.08, 0.03, 0.08), star)
	if c.Full then
		block(c, standing * P(0.26, 0.27, -0.2) * A(0, 0.2, 0), V(0.07, 0.03, 0.07), star)
		block(c, standing * P(0.05, 0.27, 0.3) * A(0, 1.1, 0), V(0.06, 0.03, 0.06), star)
		point(c, lying * P(-0.12, 0.3, 0.22) * A(0, 1.1, 0), 0.24, "Light")
		block(c, lying * P(0, -0.02, 0) * A(0, math.pi / 4, 0), V(1.0, 0.44, 1.0), "Dark")
		block(c, standing * P(0, -0.02, 0) * A(0, math.pi / 4, 0), V(0.95, 0.42, 0.95), "Main")
	end
end

-- Magmacore: a molten ball held in an iron cradle.
SHAPES.Blob = function(c)
	local iron = Color3.fromRGB(64, 64, 72)
	local ironLight = Color3.fromRGB(116, 118, 128)
	block(c, P(0, 0.12, 0) * A(0, 0.3, 0), V(1.15, 0.24, 1.15), iron)
	local center = V(0, 0.8, 0)
	ball(c, center, 1.2, "Main")
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3 + 0.3
		local foot = V(math.cos(a) * 0.48, 0.2, math.sin(a) * 0.48)
		local top = V(math.cos(a) * 0.62, 1.0, math.sin(a) * 0.62)
		beam(c, foot, top, 0.16, ironLight)
	end
	cyl(c, CFrame.new(center) * A(0.25, 0, 0.15), 0.08, 1.24, "Vein")
	block(c, CFrame.new(center + V(0.08, 0.55, -0.05)) * A(0.3, 0.5, 0.2), V(0.5, 0.12, 0.42), "Dark")
	if c.Full then
		for i = 0, 2 do
			local a = i * math.pi * 2 / 3 + 0.3
			ball(c, V(math.cos(a) * 0.63, 1.04, math.sin(a) * 0.63), 0.22, ironLight)
		end
		ball(c, V(0.35, 0.26, 0.38), 0.18, "NeonDark")
		block(c, CFrame.new(center + V(-0.42, 0.3, 0.25)) * A(-0.4, 1.2, 0.5), V(0.36, 0.1, 0.3), "Dark")
	end
end

-- Skyglass: a crystal floating inside its own ring of light.
SHAPES.Halo = function(c)
	local r = 0.86
	local cy = r * math.sqrt(3) / 2 + 0.05
	local ring = P(0, cy, 0)
	for k = 0, 5 do
		local a0, a1 = k * math.pi / 3, (k + 1) * math.pi / 3
		local p0 = (ring * P(math.cos(a0) * r, math.sin(a0) * r, 0)).Position
		local p1 = (ring * P(math.cos(a1) * r, math.sin(a1) * r, 0)).Position
		beam(c, p0, p1, 0.11, if k % 2 == 0 then "Neon" else "NeonDark")
	end
	point(c, ring * A(0, 0.6, 0), 0.62, "Main")
	if c.Full then
		point(c, ring * A(0, 0.6, 0), 0.7, "Glass")
		point(c, ring * P(0.55, 0.55, 0.3) * A(0.4, 0, 0.5), 0.16, "Light")
		point(c, ring * P(-0.5, -0.5, -0.3) * A(-0.3, 0, 0.2), 0.14, "Light")
		cyl(c, P(0, 0.02, 0), 0.04, 0.9, "NeonDark")
	end
end

-- Royal Aurum: still shaped like the Kaldrum crown, a red stone in front.
SHAPES.Crown = function(c)
	local velvet = Color3.fromRGB(150, 30, 46)
	cyl(c, P(0, 0.36, 0), 0.72, 1.36, "Main")
	ball(c, V(0, 0.5, 0), 0.96, velvet)
	local count = if c.Full then 8 else 4
	for k = 0, count - 1 do
		local a = k * math.pi * 2 / count + math.pi / 4
		local big = k % 2 == 0 or not c.Full
		point(c, P(math.cos(a) * 0.44, if big then 0.88 else 0.8, math.sin(a) * 0.44) * A(0, -a, 0), if big then 0.5 else 0.38, "Light")
	end
	ball(c, V(0, 0.4, 0.68), 0.32, "Vein")
	if c.Full then
		cyl(c, P(0, 0.05, 0), 0.1, 1.44, "Dark")
		ball(c, V(0.62, 0.3, -0.33), 0.18, "NeonDark")
		ball(c, V(-0.62, 0.3, -0.33), 0.18, "NeonDark")
	end
end

-- Prismite: every color at once, in neat bands.
SHAPES.Rainbow = function(c)
	local base = Color3.fromRGB(255, 196, 228)
	block(c, P(0, 0.43, 0), V(1.95, 0.86, 0.62), base)
	local face = P(0, 0.86, 0) * A(math.pi / 2, 0, 0)
	local bands = {
		Color3.fromRGB(236, 64, 84),
		Color3.fromRGB(255, 150, 56),
		Color3.fromRGB(255, 222, 80),
		Color3.fromRGB(92, 212, 112),
		Color3.fromRGB(76, 150, 255),
	}
	for i, color in bands do
		cyl(c, face, 0.3 + (i - 1) * 0.04, 1.7 - (i - 1) * 0.28, color)
	end
	cyl(c, face, 0.52, 0.3, "Neon")
	if c.Full then
		ball(c, V(-0.98, 0.9, 0), 0.62, base)
		ball(c, V(0.98, 0.86, 0.02), 0.56, base)
		point(c, P(0.55, 0.92, 0.2), 0.18, "Neon")
	end
end

-- Aetherium: shards circling a bright core above a faint glow.
SHAPES.Wisp = function(c)
	cyl(c, P(0, 0.02, 0), 0.04, 0.95, "NeonDark").Transparency = 0.7
	local core = V(0, 1.15, 0)
	point(c, CFrame.new(core) * A(0, 0.3, 0), 0.95, "Glass")
	ball(c, core, 0.36, "NeonDark")
	local count = if c.Full then 7 else 4
	for k = 1, count do
		local a = k * math.pi * 2 / count + 0.3
		local radius = if k > 4 then 0.78 else 1.05
		local y = 1.15 + math.sin(a * 2 + 0.5) * 0.4
		local pos = V(math.cos(a) * radius, y, math.sin(a) * radius)
		local tangent = V(-math.sin(a), 0.35, math.cos(a))
		local tone = if k % 2 == 0 then "Neon" else "Main"
		block(c, CFrame.lookAt(pos, pos + tangent) * A(0, 0, math.pi / 4), V(0.22, 0.22, if k > 4 then 0.42 else 0.7), tone)
	end
end

-- Starmetal: a dark blue lump from a fallen star, its tail still glowing.
SHAPES.Meteor = function(c)
	local center = V(0.08, 0.6, 0.08)
	block(c, P(0.08, 0.6, 0.08) * A(0.4, 0.7, 0.3), V(0.86, 0.8, 0.86), "Light")
	ball(c, center, 1.16, "Main")
	local tail = V(-0.62, 0.55, -0.58).Unit
	local t1 = center + tail * 0.75
	wedge(c, CFrame.lookAt(t1, t1 + tail), V(0.6, 0.5, 1.2), "NeonDark")
	local t2 = center + tail * 1.25
	wedge(c, CFrame.lookAt(t2, t2 + tail) * P(0, 0.06, 0), V(0.3, 0.26, 0.9), "Neon")
	for _, dir in { V(0.6, 0.4, 0.7), V(-0.2, 0.9, 0.4), V(0.9, -0.1, -0.3) } do
		ball(c, onBall(center, 1.16, dir, 0.02), 0.14, "Neon")
	end
	if c.Full then
		cyl(c, P(0.08, 0.04, 0.08), 0.08, 1.75, "Dark")
		ball(c, onBall(center, 1.16, V(-0.5, 0.3, 0.8), 0.02), 0.12, "Neon")
		block(c, P(0.85, 0.12, 0.45) * A(0.3, 0.5, 0.4), V(0.3, 0.24, 0.28), "Main")
	end
end

-- Heartstone Shard: a heart with a beating core, two broken shards beside it.
SHAPES.Heart = function(c)
	block(c, P(0, 0.78, 0) * A(0, 0, math.pi / 4), V(0.9, 0.9, 0.62), "Main")
	ball(c, V(-0.33, 1.2, 0), 0.92, "Main")
	ball(c, V(0.33, 1.2, 0), 0.92, "Main")
	block(c, P(0, 0.95, 0) * A(0, 0, math.pi / 4), V(0.34, 0.34, 0.7), "Neon")
	ball(c, V(-0.42, 1.38, 0.3), 0.24, "Light")
	point(c, P(0.78, 0.28, 0.2) * A(0.4, 0.3, -0.5), 0.26, "Light")
	point(c, P(-0.72, 0.22, -0.18) * A(-0.3, 1.2, 0.3), 0.2, "Main")
	if c.Full then
		block(c, P(0, 0.95, 0) * A(0, 0, math.pi / 4), V(0.22, 0.22, 0.95), "NeonDark")
		point(c, P(0.6, 0.12, -0.45) * A(0.2, 0.6, 0.2), 0.16, "Light")
	end
end

ItemBuilder.Shapes = SHAPES

---------------------------------------------------------------- building

local function makeCtx(ore: OreData.Ore, seed: number | string, full: boolean): Ctx
	return {
		Specs = {},
		Pal = palette(ore),
		Rng = Rng.new(seed),
		Order = Rarity.get(ore.Rarity).Order,
		Full = full,
	}
end

local function recipe(ore: OreData.Ore, seed: number | string, full: boolean): Ctx
	local c = makeCtx(ore, seed, full)
	local shape = SHAPES[ore.Shape] or SHAPES.Lump
	shape(c)
	return c
end

-- Axis-aligned bounds of the specs in unit space.
local function bounds(specs: { Spec }): (Vector3, Vector3)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, s in specs do
		local p = s.CF.Position
		local half: Vector3
		if s.Shape == "Ball" then
			half = s.Size / 2
		else
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = s.CF:GetComponents()
			local h = s.Size / 2
			half = Vector3.new(
				math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
				math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
				math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
			)
		end
		local lo, hi = p - half, p + half
		mn = Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z))
		mx = Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z))
	end
	return mn, mx
end

local function scaled(cf: CFrame, k: number): CFrame
	return CFrame.new(cf.Position * k) * cf.Rotation
end

local function makePart(spec: Spec, root: CFrame, k: number, props: { [string]: any }): BasePart
	local part = Geo.make(if spec.Shape == "Wedge" then "WedgePart" else "Part", props)
	if spec.Shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif spec.Shape == "Cyl" then
		part.Shape = Enum.PartType.Cylinder
	end
	local size = spec.Size * k
	part.Size = size
	part.CFrame = root * scaled(spec.CF, k)
	part.Color = spec.Color
	part.Material = spec.Material
	part.Transparency = spec.Transparency
	part.Reflectance = spec.Reflectance
	part.CastShadow = not spec.Neon and spec.Transparency < 0.2 and math.max(size.X, size.Y, size.Z) >= 0.9
	return part
end

local function sparkle(parent: BasePart, name: string, color: Color3, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = rate
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = parent
end

---------------------------------------------------------------- physical items

local DECOR: { [string]: any } = {
	CanCollide = false,
	CanTouch = false,
	CanQuery = true, -- so clicking any part of the item targets it
	Massless = true,
	Anchored = false,
	CastShadow = false,
}

local function decorProps(extra: { [string]: any }?): { [string]: any }
	local props = table.clone(DECOR)
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function weld(body: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = part
	w.Parent = body
end

local function addDecor(model: Model, body: BasePart, part: BasePart)
	part.Parent = model
	weld(body, part)
end

local function body(model: Model, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Geo.make("Part", {
		Name = "Body",
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		CastShadow = true,
	})
	if shape then
		part.Shape = shape
		part.Size = size
	end
	-- light, slightly bouncy so throwing feels good
	part.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.5, 0.25, 1, 1)
	part.Parent = model
	model.PrimaryPart = part
	return part
end

--[[
	Dirty Ore: one crust chunk for every ore. Sizes are constants and the
	random details only depend on the seed, so two chunks with the same seed
	look the same whatever is inside; the glint color is the only hint.
]]
local function rawChunk(model: Model, cf: CFrame, info: ItemInfo, rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local glint = ItemBuilder.glowColor(ore.Glow)
	local b = body(model, cf, Vector3.new(1.5, 1.15, 1.3), Geo.vary(ItemBuilder.DirtyCrust, rng, 0.04))
	-- the same block turned 45 degrees adds facets: it reads as a stone, not a box
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, -0.04, 0) * CFrame.Angles(rng:range(-0.12, 0.12), math.pi / 4, rng:range(-0.12, 0.12)),
		Size = Vector3.new(1.3, 1.02, 1.2),
		Color = Geo.vary(ItemBuilder.DirtyCrust:Lerp(ItemBuilder.DirtyCrustDark, 0.35), rng, 0.03),
		Material = SMOOTH,
	})))
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(rng:range(-0.25, 0.05), 0.42, rng:range(-0.1, 0.2)) * CFrame.Angles(rng:range(0.3, 0.55), rng:range(0, math.pi * 2), rng:range(-0.55, -0.3)),
		Size = Vector3.new(0.9, 0.7, 0.8),
		Color = Geo.vary(ItemBuilder.DirtyCrustLight, rng, 0.04),
		Material = SMOOTH,
	})))
	-- a smear of mud
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(-0.25, -0.08, -0.66) * CFrame.Angles(0, 0, rng:range(-0.4, 0.4)),
		Size = Vector3.new(0.72, 0.5, 0.08),
		Color = ItemBuilder.DirtyMud,
		Material = SMOOTH,
	})))
	-- the tiny glint: the only thing that differs between ores
	local glintSpots = { CFrame.new(0.42, 0.42, -0.62), CFrame.new(-0.5, 0.5, 0.52) }
	local glintSizes = { 0.26, 0.18 }
	for i, spot in glintSpots do
		local glintPart = Geo.make("Part", decorProps({
			Name = "Glint",
			CFrame = cf * spot * CFrame.Angles(0, i * 0.8, 0) * VERTEX_UP,
			Size = Vector3.one * glintSizes[i],
			Color = glint,
			Material = NEON,
		}))
		addDecor(model, b, glintPart)
	end
end

local function cleanOre(model: Model, cf: CFrame, info: ItemInfo, rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local c = recipe(ore, rng:nextU32(), false)
	local k = ItemBuilder.CleanScale
	local mn, mx = bounds(c.Specs)
	local center = (mn + mx) / 2
	local extent = (mx - mn) * k
	-- invisible box around the shape: stable physics whatever the silhouette
	local boxSize = Vector3.new(math.max(extent.X - 0.08, 0.5), math.max(extent.Y - 0.08, 0.5), math.max(extent.Z - 0.08, 0.5))
	local b = body(model, cf, boxSize, ore.Color)
	b.Transparency = 1
	b.CastShadow = false
	local volume = boxSize.X * boxSize.Y * boxSize.Z
	b.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(2.2 / volume, 0.3, 1.5), 0.5, 0.25, 1, 1)
	local root = cf * CFrame.new(-center * k)
	for _, spec in c.Specs do
		local part = makePart(spec, root, k, decorProps())
		addDecor(model, b, part)
	end
	-- one sparkle emitter at most: grade (Pristine/Flawless) and rarity (Epic+) share it
	local rate = 0
	local color = c.Pal.Glow
	if info.Grade == "Flawless" then
		rate += 3
		color = Color3.fromRGB(255, 236, 140)
	elseif info.Grade == "Pristine" then
		rate += 1.2
		color = Color3.fromRGB(200, 255, 210)
	end
	if c.Order >= 4 then
		rate += 0.6 + (c.Order - 4) * 0.6
	end
	if rate > 0 then
		sparkle(b, "GradeSparkle", color, rate, 0.35)
	end
end

local function crushed(model: Model, cf: CFrame, info: ItemInfo, rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local c = makeCtx(ore, 1, false)
	local pal = c.Pal
	-- a low heap: a wide base, the same base turned 45 degrees, chunks on top
	local grit = Color3.fromRGB(90, 80, 74)
	local b = body(model, cf, Vector3.new(1.5, 0.45, 1.5), pal.Dark:Lerp(grit, 0.35))
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Size = Vector3.new(1.25, 0.5, 1.25),
		Color = pal.Main:Lerp(grit, 0.25),
		Material = SMOOTH,
	})))
	for i, tone in { "Main", "Light", "Dark" } do
		local color, material, reflectance = resolve(c, tone)
		local a = i * 2.1 + rng:range(-0.3, 0.3)
		addDecor(model, b, Geo.make("Part", decorProps({
			CFrame = cf * CFrame.new(math.cos(a) * 0.3, rng:range(0.36, 0.44), math.sin(a) * 0.3) * Geo.randomTilt(rng, 0.7),
			Size = Vector3.new(0.46, 0.36, 0.42),
			Color = color,
			Material = material,
			Reflectance = reflectance,
		})))
	end
	local veinColor, veinMaterial, _, veinT = resolve(c, "Vein")
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(rng:range(-0.15, 0.15), 0.52, rng:range(-0.15, 0.15)) * VERTEX_UP,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Color = veinColor,
		Material = veinMaterial,
		Transparency = veinT,
	})))
end

-- Ingot: three stepped metal layers and a stamp in the ore's glow (4 parts).
local function ingot(model: Model, cf: CFrame, info: ItemInfo, _rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local c = makeCtx(ore, 1, false)
	local pal = c.Pal
	local b = body(model, cf, Vector3.new(1.9, 0.5, 0.92), pal.Main, Enum.Material.Metal)
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, -0.21, 0),
		Size = Vector3.new(1.96, 0.1, 0.98),
		Color = pal.Dark,
		Material = Enum.Material.Metal,
	})))
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Size = Vector3.new(1.6, 0.12, 0.66),
		Color = pal.Light,
		Material = Enum.Material.Metal,
	})))
	local stampColor, stampMaterial, _, stampT = resolve(c, "Vein")
	addDecor(model, b, Geo.make("Part", decorProps({
		Name = "Stamp",
		CFrame = cf * CFrame.new(0, 0.37, 0),
		Size = Vector3.new(0.52, 0.04, 0.26),
		Color = if c.Order <= 1 then pal.Dark else stampColor,
		Material = stampMaterial,
		Transparency = stampT,
	})))
	if info.Grade == "Flawless" then
		sparkle(b, "GradeSparkle", Color3.fromRGB(255, 236, 140), 2, 0.3)
	end
end

local function gear(model: Model, cf: CFrame, info: ItemInfo, _rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local metal = ore.Color
	local grip = Color3.fromRGB(96, 60, 36)
	local recipeId = info.Recipe or "Dagger"
	if recipeId == "Dagger" or recipeId == "Greatsword" then
		local long = recipeId == "Greatsword"
		local bladeLength = if long then 3.4 else 1.6
		local b = body(model, cf, Vector3.new(bladeLength + 1, 0.35, 0.6), metal, Enum.Material.Metal)
		b.Transparency = 1 -- the collider is invisible; visible parts are decor
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4, 0, 0), Size = Vector3.new(bladeLength, 0.14, if long then 0.55 else 0.42), Color = metal, Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("WedgePart", decorProps({ CFrame = cf * CFrame.new(0.4 + bladeLength / 2 + 0.25, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), Size = Vector3.new(if long then 0.55 else 0.42, 0.14, 0.5), Color = metal, Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4 - bladeLength / 2 - 0.1, 0, 0), Size = Vector3.new(0.2, 0.24, if long then 1.4 else 1), Color = Color3.fromRGB(220, 180, 80), Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4 - bladeLength / 2 - 0.55, 0, 0), Size = Vector3.new(0.7, 0.22, 0.22), Color = grip, Material = Enum.Material.SmoothPlastic })))
	elseif recipeId == "ToolHead" then
		local b = body(model, cf, Vector3.new(2.4, 0.5, 0.5), metal, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			addDecor(model, b, Geo.make("WedgePart", decorProps({
				CFrame = cf * CFrame.new(side * 1.45, 0, 0) * CFrame.Angles(0, side * math.pi / 2, 0),
				Size = Vector3.new(0.5, 0.5, 0.6),
				Color = metal,
				Material = Enum.Material.Metal,
			})))
		end
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0, 0), Size = Vector3.new(0.6, 0.62, 0.62), Color = metal:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Metal })))
	else -- Helm
		local b = body(model, cf, Vector3.new(1.6, 1.3, 1.6), metal, Enum.Material.Metal, Enum.PartType.Ball)
		b.Size = Vector3.new(1.6, 1.6, 1.6)
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, -0.45, 0), Size = Vector3.new(1.8, 0.25, 1.8), Color = metal:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0.85, 0), Size = Vector3.new(0.25, 0.45, 1.2), Color = Color3.fromRGB(200, 60, 50), Material = Enum.Material.SmoothPlastic })))
	end
	-- every gear piece gets a small glowing ore inlay
	local primary = model.PrimaryPart :: BasePart
	addDecor(model, primary, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0.2, 0), Size = Vector3.new(0.2, 0.2, 0.2), Color = ItemBuilder.glowColor(ore.Glow), Material = Enum.Material.Neon })))
end

local BUILDERS = {
	Raw = rawChunk,
	Clean = cleanOre,
	Crushed = crushed,
	Ingot = ingot,
	Gear = gear,
}

-- Returns a Model (not parented). `seed` only changes the random details.
function ItemBuilder.build(info: ItemInfo, cf: CFrame, seed: number | string): Model
	local model = Instance.new("Model")
	model.Name = info.Kind .. "_" .. info.OreId
	local builder = BUILDERS[info.Kind]
	assert(builder, "Unknown item kind " .. tostring(info.Kind))
	builder(model, cf, info, Rng.new(seed))
	return model
end

---------------------------------------------------------------- display copies

local DISPLAY: { [string]: any } = {
	Anchored = true,
	CanCollide = false,
	CanTouch = false,
	CanQuery = false,
	CastShadow = false,
}

local function displayOre(model: Model, cf: CFrame, ore: OreData.Ore, grade: string?, seed: number | string)
	local c = recipe(ore, seed, true)
	local k = ItemBuilder.DisplayScale
	local mn, mx = bounds(c.Specs)
	local root = cf * CFrame.new(-(mn.X + mx.X) / 2 * k, -mn.Y * k, -(mn.Z + mx.Z) / 2 * k)
	local parts: { BasePart } = {}
	for _, spec in c.Specs do
		local part = makePart(spec, root, k, table.clone(DISPLAY))
		part.Parent = model
		table.insert(parts, part)
	end
	local main = parts[1]
	model.PrimaryPart = main
	local glow = c.Pal.Glow
	local center = cf.Position + cf.UpVector * ((mx.Y - mn.Y) / 2 * k)
	-- Mythic: motes on a tilted orbit (a client may spin parts named "Mote" around Center)
	if c.Order >= 6 then
		local radius = math.max(mx.X - mn.X, mx.Z - mn.Z) / 2 * k + 0.35
		local orbit = CFrame.new(center) * cf.Rotation * CFrame.Angles(0.35, 0, 0.2)
		for i = 1, 3 do
			local a = i * math.pi * 2 / 3 + 0.5
			local mote = Geo.make("Part", table.clone(DISPLAY))
			mote.Name = "Mote"
			mote.Shape = Enum.PartType.Ball
			mote.Size = Vector3.one * (0.18 + (i % 2) * 0.05)
			mote.CFrame = orbit * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			mote.Color = glow
			mote.Material = NEON
			mote.Parent = model
		end
		-- a soft glow that swells and fades: the "pulse"
		local pulse = Instance.new("ParticleEmitter")
		pulse.Name = "Pulse"
		pulse.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pulse.Color = ColorSequence.new(glow)
		pulse.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.2) })
		pulse.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		pulse.Lifetime = NumberRange.new(1.4)
		pulse.Speed = NumberRange.new(0)
		pulse.Rate = 0.8
		pulse.LockedToPart = true
		pulse.LightEmission = 1
		pulse.LightInfluence = 0
		pulse.Parent = main
		model:SetAttribute("Pulse", true)
	end
	-- Epic and up sparkle; a grade sparkle joins the same emitter
	local rate = 0
	local color = glow
	if c.Order >= 4 then
		rate = 1.5 + (c.Order - 4) * 1
	end
	if grade == "Flawless" then
		rate += 2
		color = Color3.fromRGB(255, 236, 140)
	elseif grade == "Pristine" then
		rate += 1
	end
	if rate > 0 then
		sparkle(main, "Sparkle", color, rate, 0.4)
	end
	-- one light, Legendary and Mythic only
	if c.Order >= 5 then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 6 + (c.Order - 5)
		light.Brightness = 0.8 + (c.Order - 5) * 0.2
		light.Shadows = false
		light.Parent = main
	end
	model:SetAttribute("Center", center)
end

--[[
	Contract (design v2): a still, anchored display copy of an item for
	podiums and the Ore Pen pile. No collisions, no welds, no physics.
	`cf` is the bottom center of where it should stand. Budget: <= 14 parts
	and at most 1 light (Legendary and Mythic only). Clean ores get their
	rich display look; other kinds are the physical item, anchored.
	Attribute Center = the middle of the ore (for spinning/bobbing on the client).
]]
function ItemBuilder.display(desc: { K: string, O: string, G: string?, R: string? }, cf: CFrame, seed: number | string?): Model
	local model = Instance.new("Model")
	model.Name = "Display_" .. desc.K .. "_" .. desc.O
	if desc.K == "Clean" then
		displayOre(model, cf, OreData.get(desc.O), desc.G, seed or 1)
		return model
	end
	local built = ItemBuilder.build({ Kind = desc.K, OreId = desc.O, Grade = desc.G, Recipe = desc.R }, CFrame.new(), seed or 1)
	local primary = built.PrimaryPart
	local lowest = math.huge
	local parts: { BasePart } = {}
	for _, d in built:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Transparency < 1 then
				local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
				local h = d.Size / 2
				lowest = math.min(lowest, d.CFrame.Position.Y - (math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z))
			end
		end
	end
	local lift = CFrame.new(0, if lowest < math.huge then -lowest else 0, 0)
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = false
		part.CFrame = cf * lift * part.CFrame
		part.Parent = model
	end
	model.PrimaryPart = primary
	for _, d in built:GetChildren() do
		d.Parent = model
	end
	built:Destroy()
	model:SetAttribute("Center", (cf * lift).Position)
	return model
end

return ItemBuilder
