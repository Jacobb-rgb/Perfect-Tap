--[[
	Terra Forge machines, v2 look: style A "Soft" (owner 2026-10-17: "a cute
	and at the same time cool look like the new games", chosen from the
	styles in CuteMachines.luau). The Kenney Factory Kit pieces turned into
	chunky, rounded toy shapes:
	  - soft box bodies (every top and upright edge rounded, balls in the
	    corners) in cream, on slate pill-cornered plinths with glowing orange
	    strips, slate pill lids;
	  - arched glowing furnace doors (orange frame, dark ring, glow, hot core);
	  - fat chimneys with round caps and glowing rings; round bowl hoppers;
	  - capsule tanks with glowing portholes; slate pipes with orange sleeves,
	    glass sections with glowing water (a coil inside) or molten metal,
	    valves with orange wheels; round screens, stack lights, an orange
	    robot arm;
	  - belts: a black segmented belt between slate rails with round orange
	    tops and glowing strips, orange feet; optional end caps (a drum with
	    round orange plates, a control box with an arrow screen and an amber
	    beacon); slopes up (Belt Lift) and down (Slide).
	Flat details (hazard stripes, screen content, belt segments, bolts) are
	SurfaceGui frames, so they cost no parts.

	Upgrades change the look (owner): level 0 = plain; 1-2 small crystal
	clusters (level 2 also turns the orange glow to crystal colour); 3 bigger
	clusters, the slate frames and pipes turn crystal; 4 (max) = the whole
	machine is crystal with a hero crystal on top. Themes = crystal colours.

	Same contract as MachineBuilder (Base + attachments Intake (IntakeSize),
	Output, Prompt, Status, OrePoint/CamPoint, WaterOut/WaterIn; the named
	parts MachineFxController animates: Glow, Molten, Cog1/Cog2, Roller1/2
	(+Tooth), Drum/DrumRib, BedRoller, WaterPool, StackRed/Amber/Green, Vent,
	ChimneyTop) so it can replace it once the owner approves. Every part has
	the attribute Kit = its colour role (Body, Frame, Dark, Trim, Neon, Pipe,
	Glass, Water, Molten, Glow, Hot, Screen, ScreenGlow, Lamp, Rubber, Floor,
	Crystal); the crystal levels repaint by role.

	Local space: origin = footprint centre on the plot surface, front = -Z.
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Grid = require(script.Parent.Parent.Machines.Grid)

local KitMachines = {}

type Props = { [string]: any }
export type Theme = { Main: Color3, Deep: Color3, Pale: Color3 }
type Socket = { cf: CFrame, size: number, hero: boolean? }
type Ctx = { model: Model, base: BasePart, sockets: { Socket } }
type Paint = { x: number, y: number, w: number, h: number, color: Color3, round: boolean?, stripes: number? }

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local UP = Vector3.yAxis
local XA = Vector3.xAxis
local ZA = Vector3.zAxis
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local FLOOR = 0.3 -- top of the Base plate

KitMachines.MaxLevel = 4

KitMachines.Palette = {
	Body = rgb(232, 226, 214), -- cream bodies
	Frame = rgb(72, 84, 122), -- slate plinths, lids, rails, collars
	Pipe = rgb(88, 100, 138),
	Dark = rgb(36, 40, 60), -- recesses, mouths
	Trim = rgb(255, 146, 52), -- orange: door frames, sleeves, rims, feet, handles
	Neon = rgb(255, 150, 50), -- glowing strips
	Glass = rgb(206, 238, 252),
	Water = rgb(70, 196, 255), -- glowing water
	Molten = rgb(255, 124, 26),
	Glow = rgb(255, 132, 30), -- furnace fire
	Hot = rgb(255, 218, 110), -- hottest core of the fire
	Screen = rgb(24, 30, 48),
	ScreenGlow = rgb(90, 236, 200),
	Floor = rgb(60, 66, 92),
	Rubber = rgb(32, 34, 44),
	Red = rgb(235, 70, 60),
	Amber = rgb(255, 176, 40),
	Green = rgb(80, 210, 110),
	Bristle = rgb(40, 150, 160),
	Smoke = rgb(236, 236, 240),
	Bolt = rgb(196, 190, 178),
	Gold = rgb(255, 196, 60),
	Felt = rgb(255, 172, 204), -- the Polisher's pink felt
	Panel = rgb(44, 78, 160), -- solar cells
	Plasma = rgb(186, 110, 255), -- the Plasma Furnace's glow
	Cyan = rgb(70, 228, 255), -- end game glow (plasma, fusion)
	Brick = rgb(222, 126, 92), -- the Brick Furnace's terracotta dome
	Gem = rgb(90, 214, 255),
}
local P = KitMachines.Palette

KitMachines.Themes = {
	Aqua = { Main = rgb(90, 214, 255), Deep = rgb(36, 120, 226), Pale = rgb(204, 246, 255) },
	Amethyst = { Main = rgb(178, 122, 255), Deep = rgb(98, 52, 206), Pale = rgb(232, 212, 255) },
	Rose = { Main = rgb(255, 124, 198), Deep = rgb(212, 56, 140), Pale = rgb(255, 216, 238) },
} :: { [string]: Theme }
KitMachines.DefaultTheme = "Aqua"

local MATERIAL: { [string]: Enum.Material } = {
	Neon = NEON,
	Molten = NEON,
	Glow = NEON,
	Hot = NEON,
	ScreenGlow = NEON,
	Glass = GLASS,
	Water = NEON,
	Plasma = NEON,
	Cyan = NEON,
}
local TRANSPARENCY: { [string]: number } = { Glass = 0.6 }
local SHINE: { [string]: boolean } = { Body = true, Frame = true, Trim = true, Pipe = true, Gold = true, Brick = true, Panel = true }
local POOL_TRANSPARENCY = 0.2

local SOLID: Props = { CanTouch = false }
local PROP: Props = { CanTouch = false, CanQuery = false, CanCollide = false }
local TINY: Props = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }

---------------------------------------------------------------- parts

local function style(part: BasePart, role: string, flags: Props?, name: string?): BasePart
	part:SetAttribute("Kit", role)
	local color = (P :: any)[role]
	if color then
		part.Color = color
	end
	part.Material = MATERIAL[role] or SMOOTH
	part.Transparency = TRANSPARENCY[role] or 0
	if SHINE[role] then
		part.Reflectance = 0.04 -- a soft toy shine
	end
	for key, value in flags or SOLID do
		(part :: any)[key] = value
	end
	if name then
		part.Name = name
	end
	return part
end

local function block(m: Instance, cf: CFrame, size: Vector3, role: string, flags: Props?, name: string?): BasePart
	return style(Geo.make("Part", { CFrame = cf, Size = size }, m), role, flags, name)
end

local function wedge(m: Instance, cf: CFrame, size: Vector3, role: string, flags: Props?, name: string?): BasePart
	return style(Geo.make("WedgePart", { CFrame = cf, Size = size }, m), role, flags, name)
end

-- A frame at `pos` whose X axis points along `dir` (Roblox cylinders run along X).
local function along(pos: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) < 0.95 then UP else ZA
	local z = x:Cross(ref).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(pos, x, y, z)
end

-- Cylinder along `dir`; `d2` makes it an oval (d2 tall, d wide).
local function cyl(
	m: Instance,
	center: Vector3,
	dir: Vector3,
	length: number,
	d: number,
	role: string,
	flags: Props?,
	name: string?,
	d2: number?
): BasePart
	local part = Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = along(center, dir),
		Size = Vector3.new(length, d2 or d, d),
	}, m)
	return style(part, role, flags, name)
end

local function ball(m: Instance, center: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	local part = Geo.make("Part", { Shape = Enum.PartType.Ball, CFrame = CFrame.new(center), Size = Vector3.new(d, d, d) }, m)
	return style(part, role, flags or PROP, name)
end

local function rod(m: Instance, a: Vector3, b: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	return cyl(m, (a + b) / 2, b - a, (b - a).Magnitude, d, role, flags, name)
end

-- Painted details on one face (SurfaceGui frames, no parts). Scale coordinates, y down.
local function paint(part: BasePart, face: Enum.NormalId, items: { Paint }, name: string?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "Paint"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 140
	gui.Parent = part
	for _, it in items do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = it.color
		frame.Position = UDim2.fromScale(it.x, it.y)
		frame.Size = UDim2.fromScale(it.w, it.h)
		if it.round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
		end
		if it.stripes then
			-- hazard stripes: hard orange / dark steps
			local keys = {}
			local n = it.stripes
			for i = 0, n - 1 do
				local color = if i % 2 == 0 then P.Trim else P.Dark
				local t0, t1 = i / n, (i + 1) / n
				table.insert(keys, ColorSequenceKeypoint.new(t0, color))
				table.insert(keys, ColorSequenceKeypoint.new(math.max(t0, t1 - 0.001), color))
			end
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(keys)
			gradient.Parent = frame
			frame.BackgroundColor3 = WHITE
		end
		frame.Parent = gui
	end
	return gui
end

-- Two round rivets in the upper corners of a face.
local function rivets(part: BasePart, face: Enum.NormalId)
	paint(part, face, {
		{ x = 0.06, y = 0.1, w = 0.05, h = 0.08, color = P.Bolt, round = true },
		{ x = 0.89, y = 0.1, w = 0.05, h = 0.08, color = P.Bolt, round = true },
	})
end

local function attach(base: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = base
	return a
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function smoke(parent: Instance, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(P.Smoke)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 4.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(2.5, 4)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Rate = rate
	e.Parent = parent
end

local function embers(parent: Instance, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Embers"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Acceleration = Vector3.new(0, 3, 0)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 3
	e.Parent = parent
end

---------------------------------------------------------------- soft pieces

--[[
	Soft box standing on `bottom` (front = -Z): all four upright edges and all
	top edges rounded with radius `r`, balls in the top corners. Returns the
	main block (its +-X faces are flat). 15 parts.
]]
local function softBox(m: Instance, bottom: Vector3, w: number, h: number, d: number, r: number, role: string, name: string?): BasePart
	local lower = h - r
	local main = block(m, CFrame.new(bottom + Vector3.new(0, lower / 2, 0)), Vector3.new(w, lower, d - 2 * r), role, SOLID, name)
	local cross = block(m, CFrame.new(bottom + Vector3.new(0, lower / 2, 0)), Vector3.new(w - 2 * r, lower, d), role, SOLID)
	cross.Name = (name or role) .. "Front"
	block(m, CFrame.new(bottom + Vector3.new(0, h - r / 2, 0)), Vector3.new(w - 2 * r, r, d - 2 * r), role, SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = bottom + Vector3.new(sx * (w / 2 - r), 0, sz * (d / 2 - r))
			cyl(m, corner + Vector3.new(0, lower / 2, 0), UP, lower, 2 * r, role, SOLID)
			ball(m, corner + Vector3.new(0, lower, 0), 2 * r, role, SOLID)
		end
		cyl(m, bottom + Vector3.new(sx * (w / 2 - r), lower, 0), ZA, d - 2 * r, 2 * r, role, SOLID)
	end
	for _, sz in { -1, 1 } do
		cyl(m, bottom + Vector3.new(0, lower, sz * (d / 2 - r)), XA, w - 2 * r, 2 * r, role, SOLID)
	end
	return main
end

-- Slab with rounded upright corners standing on `bottom`. 6 parts.
local function pillSlab(
	m: Instance,
	bottom: Vector3,
	w: number,
	h: number,
	d: number,
	r: number,
	role: string,
	flags: Props?,
	name: string?
): BasePart
	local c = bottom + Vector3.new(0, h / 2, 0)
	local main = block(m, CFrame.new(c), Vector3.new(w, h, d - 2 * r), role, flags or SOLID, name)
	block(m, CFrame.new(c), Vector3.new(w - 2 * r, h, d), role, flags or SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(m, c + Vector3.new(sx * (w / 2 - r), 0, sz * (d / 2 - r)), UP, h, 2 * r, role, flags or SOLID)
		end
	end
	return main
end

-- Glowing strips on the four flat faces of a pill slab centred at `center`.
local function glowStrips(m: Instance, center: Vector3, w: number, d: number, r: number, thick: number, role: string?)
	local e = 0.06
	for _, s in { -1, 1 } do
		block(m, CFrame.new(center + Vector3.new(0, 0, s * (d / 2 + e / 2))), Vector3.new(w - 2 * r, thick, e), role or "Neon", TINY)
		block(m, CFrame.new(center + Vector3.new(s * (w / 2 + e / 2), 0, 0)), Vector3.new(e, thick, d - 2 * r), role or "Neon", TINY)
	end
end

-- Pill plinth with glowing strips; returns the height of its top.
local function plinth(m: Instance, bottom: Vector3, w: number, d: number, h: number, r: number): number
	pillSlab(m, bottom, w, h, d, r, "Frame")
	glowStrips(m, bottom + Vector3.new(0, h / 2, 0), w, d, r, 0.16)
	return bottom.Y + h
end

-- An arch (a block with a half circle on top) standing on `bottom`, `z` deep along Z. 2 parts.
local function arch(
	m: Instance,
	bottom: Vector3,
	w: number,
	straight: number,
	z: number,
	role: string,
	flags: Props?,
	name: string?
): BasePart
	local part = block(m, CFrame.new(bottom + Vector3.new(0, straight / 2, 0)), Vector3.new(w, straight, z), role, flags, name)
	cyl(m, bottom + Vector3.new(0, straight, 0), ZA, z, w, role, flags, name)
	return part
end

--[[
	Arched door on a front face at `z` (bottom centre `x`, `y0`): an orange
	frame, a dark ring, and inside either a fire (Glow with a hot core and a
	grate, a light, embers) or a dark opening. Returns the inside part.
]]
local function door(m: Instance, x: number, y0: number, z: number, w: number, straight: number, fill: string, name: string?): BasePart
	arch(m, Vector3.new(x, y0, z - 0.2), w + 0.7, straight, 0.4, "Trim", SOLID)
	arch(m, Vector3.new(x, y0, z - 0.42), w + 0.2, straight, 0.06, "Dark", TINY)
	local inside = arch(m, Vector3.new(x, y0, z - 0.46), w, straight, 0.06, fill, TINY, name)
	if fill == "Glow" then
		arch(m, Vector3.new(x, y0 + 0.25, z - 0.5), w * 0.55, straight * 0.7, 0.04, "Hot", TINY, "GlowCore")
		for i = -1, 1 do
			block(m, CFrame.new(x + i * w * 0.28, y0 + 0.3, z - 0.56), Vector3.new(0.2, 0.6, 0.1), "Dark", TINY)
		end
		block(m, CFrame.new(x, y0 + 0.55, z - 0.56), Vector3.new(w * 0.95, 0.14, 0.1), "Dark", TINY)
		light(inside, P.Glow, 8, 0.8)
		embers(inside, P.Glow)
	end
	return inside
end

type PipeOpts = { fluid: string?, a: boolean?, b: boolean?, name: string?, role: string? }

-- A pipe from `a` to `b` with orange sleeves at the ends; `fluid` = a glass pipe with glowing Water (+ coil) or Molten.
local function pipe(m: Instance, a: Vector3, b: Vector3, d: number, o: PipeOpts?)
	local opts: PipeOpts = o or {}
	local dir = (b - a).Unit
	local s = math.max(0.22, d * 0.36)
	if opts.fluid then
		rod(m, a, b, d * 1.02, "Glass", TINY, opts.name)
		rod(m, a + dir * s, b - dir * s, d * 0.5, opts.fluid, TINY, if opts.fluid == "Molten" then "Molten" else "Fluid")
		if opts.fluid == "Water" then
			local len = (b - a).Magnitude - 2 * s
			local turns = math.max(2, math.floor(len / 0.55))
			for i = 1, turns do
				local at = a + dir * (s + (i - 0.5) * len / turns)
				local ring = Geo.make("Part", {
					Shape = Enum.PartType.Cylinder,
					CFrame = along(at, dir) * CFrame.Angles(0, 0, math.rad(22)),
					Size = Vector3.new(0.08, d * 0.84, d * 0.84),
				}, m)
				style(ring, "Water", TINY, "Coil")
			end
		end
	else
		rod(m, a, b, d, opts.role or "Pipe", PROP, opts.name)
	end
	if opts.a ~= false then
		cyl(m, a + dir * (s / 2), dir, s, d * 1.3, "Trim", TINY)
	end
	if opts.b ~= false then
		cyl(m, b - dir * (s / 2), dir, s, d * 1.3, "Trim", TINY)
	end
end

--[[
	A smooth quarter bend of radius `r` from `p0` heading `da` to heading `db`
	(3 segments with ball joints). Returns the end point.
]]
local function bend(m: Instance, p0: Vector3, da: Vector3, db: Vector3, d: number, r: number, role: string?): Vector3
	local center = p0 + db * r
	local points = {}
	for i = 0, 3 do
		local th = i * math.pi / 6
		table.insert(points, center - db * (r * math.cos(th)) + da * (r * math.sin(th)))
	end
	for i = 1, 3 do
		rod(m, points[i], points[i + 1], d, role or "Pipe", PROP, "PipeBend")
	end
	for i = 2, 3 do
		ball(m, points[i], d, role or "Pipe", PROP, "PipeJoint")
	end
	return points[4]
end

-- A valve: a slate sleeve and an orange hand wheel toward `up`.
local function valve(m: Instance, center: Vector3, dir: Vector3, d: number, up: Vector3)
	cyl(m, center, dir, d * 0.9, d * 1.35, "Frame", PROP)
	local stemTop = center + up * (d * 0.68 + 0.32)
	rod(m, center + up * (d * 0.6), stemTop, d * 0.22, "Dark", TINY)
	cyl(m, stemTop, up, 0.18, d * 1.15, "Trim", TINY, "Wheel")
	ball(m, stemTop + up * 0.12, d * 0.36, "Frame", TINY)
end

--[[
	Fat chimney on `base` (bottom centre): a slate collar, a stout stack with
	an orange band, a round cap with a glowing ring and a dark mouth
	(ChimneyTop, smoke). Returns the mouth.
]]
local function chimney(m: Instance, base: Vector3, d: number, h: number, rate: number): BasePart
	local x, z = base.X, base.Z
	local y = base.Y
	cyl(m, Vector3.new(x, y + 0.25, z), UP, 0.5, d * 1.4, "Frame", SOLID)
	local stackH = h - 1.0
	cyl(m, Vector3.new(x, y + 0.5 + stackH / 2, z), UP, stackH, d, "Pipe", SOLID)
	for _, f in { 0.4 } do
		cyl(m, Vector3.new(x, y + 0.5 + stackH * f, z), UP, 0.3, d * 1.08, "Trim", TINY)
	end
	local capY = y + 0.5 + stackH
	cyl(m, Vector3.new(x, capY + 0.22, z), UP, 0.45, d * 1.37, "Frame", SOLID)
	cyl(m, Vector3.new(x, capY + 0.22, z), UP, 0.14, d * 1.42, "Neon", TINY)
	local mouth = cyl(m, Vector3.new(x, capY + 0.46, z), UP, 0.04, d * 0.86, "Dark", TINY, "ChimneyTop")
	smoke(mouth, rate)
	return mouth
end

-- Round bowl hopper on `bottom`: a slate neck, a cream bowl, an orange rim, the mouth (`inside`). Returns the rim height.
local function bowl(m: Instance, bottom: Vector3, d: number, neckH: number, inside: string?): number
	local x, z = bottom.X, bottom.Z
	local y = bottom.Y
	local neck = math.max(neckH, 0.5)
	cyl(m, Vector3.new(x, y + neck / 2, z), UP, neck, d * 0.56, "Frame", SOLID)
	y += neck
	local bowlH = d * 0.34
	cyl(m, Vector3.new(x, y + bowlH / 2, z), UP, bowlH, d, "Body", SOLID)
	cyl(m, Vector3.new(x, y + bowlH * 0.3, z), UP, 0.12, d * 1.04, "Neon", TINY)
	cyl(m, Vector3.new(x, y + bowlH + 0.05, z), UP, 0.26, d * 1.08, "Trim", SOLID)
	local rim = y + bowlH + 0.18
	cyl(m, Vector3.new(x, rim + 0.01, z), UP, 0.04, d * 0.8, inside or "Dark", TINY, if inside == "Molten" then "Molten" else nil)
	return rim
end

type TankOpts = { port: Vector3?, glow: string?, name: string? }

--[[
	Capsule tank on `bottom`: a slate foot, a round body with a domed top,
	orange bands, a round glowing porthole toward `port` (`glow` = Water /
	Neon / Molten). Returns the top of the dome.
]]
local function capsule(m: Instance, bottom: Vector3, d: number, h: number, o: TankOpts?): number
	local opts: TankOpts = o or {}
	cyl(m, bottom + Vector3.new(0, 0.15, 0), UP, 0.3, d + 0.2, "Frame", PROP)
	cyl(m, bottom + Vector3.new(0, 0.3 + h / 2, 0), UP, h, d, "Pipe", SOLID, opts.name or "Tank")
	ball(m, bottom + Vector3.new(0, 0.3 + h, 0), d, "Pipe", SOLID)
	cyl(m, bottom + Vector3.new(0, 0.3 + h * 0.18, 0), UP, 0.26, d + 0.08, "Trim", TINY)
	cyl(m, bottom + Vector3.new(0, 0.3 + h, 0), UP, 0.22, d + 0.06, "Trim", TINY)
	if opts.port then
		local dir = opts.port.Unit
		local at = bottom + Vector3.new(0, 0.3 + h * 0.55, 0) + dir * (d / 2)
		cyl(m, at, dir, 0.16, d * 0.56, "Frame", TINY)
		cyl(m, at + dir * 0.06, dir, 0.06, d * 0.4, opts.glow or "Neon", TINY, "TankGlow")
	end
	return bottom.Y + 0.3 + h + d / 2
end

-- A cog (8 teeth) in cream with an orange hub; every part takes `name`.
local function cog(m: Instance, center: Vector3, axis: Vector3, d: number, thick: number, name: string)
	local frame = along(center, axis)
	cyl(m, center, axis, thick, d * 0.8, "Body", PROP, name)
	for k = 0, 3 do
		block(m, frame * CFrame.Angles(k * math.pi / 4 + math.pi / 8, 0, 0), Vector3.new(thick, d, d * 0.17), "Body", TINY, name)
	end
	cyl(m, center, axis, thick + 0.1, d * 0.36, "Trim", TINY, name)
end

-- Stack light: round base, pole, red / amber / green lamps (green lit), round cap.
local function stackLight(m: Instance, bottom: Vector3, s: number)
	cyl(m, bottom + Vector3.new(0, 0.15 * s, 0), UP, 0.3 * s, 0.75 * s, "Frame", TINY)
	local poleTop = bottom.Y + 1.9 * s
	cyl(m, Vector3.new(bottom.X, (bottom.Y + poleTop) / 2, bottom.Z), UP, poleTop - bottom.Y, 0.22 * s, "Frame", PROP)
	local lamps: { { name: string, color: Color3 } } = {
		{ name = "StackGreen", color = P.Green },
		{ name = "StackAmber", color = P.Amber },
		{ name = "StackRed", color = P.Red },
	}
	for i, lamp in lamps do
		local part = cyl(m, Vector3.new(bottom.X, poleTop + (i - 0.5) * 0.34 * s, bottom.Z), UP, 0.3 * s, 0.5 * s, "Lamp", TINY, lamp.name)
		part.Color = lamp.color:Lerp(BLACK, 0.3)
		part.Material = if lamp.name == "StackGreen" then NEON else SMOOTH
	end
	ball(m, Vector3.new(bottom.X, poleTop + 1.05 * s, bottom.Z), 0.5 * s, "Frame", TINY)
end

--[[
	Screen panel on `cf` (bottom centre, screen toward -Z): a slate panel
	with round sides, the screen painted with a bright chart, a glowing bar.
]]
local function screenPanel(m: Instance, cf: CFrame, w: number, h: number, color: Color3?)
	block(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w - 0.4, h, 0.4), "Frame", PROP)
	for _, side in { -1, 1 } do
		cyl(m, (cf * CFrame.new(side * (w / 2 - 0.2), h / 2, 0)).Position, cf.UpVector, h, 0.4, "Frame", PROP)
	end
	local glow = color or P.ScreenGlow
	local screen = block(m, cf * CFrame.new(0, h * 0.56, -0.21), Vector3.new(w - 0.5, h * 0.56, 0.04), "Screen", TINY, "Screen")
	paint(screen, Enum.NormalId.Front, {
		{ x = 0.08, y = 0.14, w = 0.5, h = 0.08, color = glow, round = true },
		{ x = 0.08, y = 0.34, w = 0.32, h = 0.08, color = glow, round = true },
		{ x = 0.08, y = 0.6, w = 0.14, h = 0.26, color = glow },
		{ x = 0.28, y = 0.48, w = 0.14, h = 0.38, color = glow },
		{ x = 0.48, y = 0.68, w = 0.14, h = 0.18, color = glow },
		{ x = 0.7, y = 0.14, w = 0.2, h = 0.32, color = glow, round = true },
	})
	local bulb = block(m, cf * CFrame.new(0, h * 0.18, -0.21), Vector3.new(w * 0.45, 0.1, 0.04), "ScreenGlow", TINY, "LampBulb")
	bulb.Color = glow
end

-- Output chute from `a` to `b`: a dark slide with low orange lips.
local function chute(m: Instance, a: Vector3, b: Vector3, w: number)
	local cf = CFrame.lookAt((a + b) / 2, b)
	local len = (b - a).Magnitude
	block(m, cf, Vector3.new(w, 0.2, len), "Dark", PROP, "Chute")
	for _, side in { -1, 1 } do
		block(m, cf * CFrame.new(side * (w / 2 + 0.07), 0.08, 0), Vector3.new(0.14, 0.32, len), "Trim", TINY, "ChuteLip")
	end
end

-- Orange robot arm from `base` through `elbow` to `hand` (claw pointing down), round joints.
local function robotArm(m: Instance, base: Vector3, elbow: Vector3, hand: Vector3, s: number)
	cyl(m, base + Vector3.new(0, 0.2 * s, 0), UP, 0.4 * s, 1.25 * s, "Frame", SOLID)
	cyl(m, base + Vector3.new(0, 0.62 * s, 0), UP, 0.45 * s, 0.9 * s, "Trim", SOLID)
	local shoulder = base + Vector3.new(0, 1.0 * s, 0)
	ball(m, shoulder, 0.68 * s, "Frame", PROP)
	rod(m, shoulder, elbow, 0.46 * s, "Trim", PROP)
	ball(m, elbow, 0.6 * s, "Frame", PROP)
	rod(m, elbow, hand, 0.4 * s, "Trim", PROP)
	cyl(m, hand, UP, 0.32 * s, 0.56 * s, "Frame", TINY)
	for _, side in { -1, 1 } do
		block(m, CFrame.new(hand + Vector3.new(side * 0.17 * s, -0.36 * s, 0)), Vector3.new(0.1 * s, 0.42 * s, 0.26 * s), "Dark", TINY)
	end
end

---------------------------------------------------------------- crystals

local function shard(m: Instance, base: CFrame, height: number, width: number, color: Color3, glowTip: boolean, clear: boolean)
	local bodyH = height * 0.72
	local tipH = height - bodyH
	local lightC, darkC = color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.26)
	local material = if clear then GLASS else SMOOTH
	local transparency = if clear then 0.18 else 0
	local cf = base * CFrame.Angles(0, math.pi / 4, 0)
	local body = block(m, cf * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), "Crystal", TINY, "Crystal")
	body.Color, body.Material, body.Transparency = lightC, material, transparency
	if width >= 0.55 then
		local facet = block(
			m,
			base * CFrame.new(0, bodyH * 0.49, 0),
			Vector3.new(width * 0.84, bodyH * 0.98, width * 0.84),
			"Crystal",
			TINY,
			"CrystalFacet"
		)
		facet.Color, facet.Material, facet.Transparency = darkC, material, transparency * 0.5
	end
	local tipAt = cf * CFrame.new(0, bodyH + tipH / 2, 0)
	-- glowing tips stay close to the crystal colour (a white Neon blooms into a blob)
	local tipA = if glowTip then color:Lerp(WHITE, 0.12) else color:Lerp(WHITE, 0.5)
	local tipB = if glowTip then color:Lerp(BLACK, 0.1) else color:Lerp(WHITE, 0.25)
	local a = wedge(m, tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), "Crystal", TINY, "CrystalTip")
	local b = wedge(
		m,
		tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(width, tipH, width / 2),
		"Crystal",
		TINY,
		"CrystalTip"
	)
	for _, part in { a, b } do
		part.Material = if glowTip then NEON else SMOOTH
	end
	a.Color, b.Color = tipA, tipB
end

-- Leans a frame standing at `foot` outward toward yaw `a` by `amount` radians.
local function tilt(foot: CFrame, a: number, amount: number): CFrame
	return foot * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -amount) * CFrame.Angles(0, a, 0)
end

-- A cluster fanning out of `root` (up = outward): a tall crystal and `count - 1` leaning ones round it.
local function cluster(
	m: Instance,
	root: CFrame,
	count: number,
	height: number,
	theme: Theme,
	rng: Rng.Rng,
	glowTip: boolean,
	clear: boolean
)
	local colors = { theme.Main, theme.Main:Lerp(theme.Deep, 0.45), theme.Main:Lerp(theme.Pale, 0.35) }
	shard(m, root * CFrame.Angles(rng:range(-0.1, 0.1), 0, rng:range(-0.1, 0.1)), height, height * 0.27, colors[1], glowTip, clear)
	for i = 1, count - 1 do
		local a = (i / (count - 1)) * math.pi * 2 + rng:range(-0.4, 0.4)
		local amount = rng:range(0.35, 0.75)
		local h = height * rng:range(0.55, 0.85) * (1 - amount * 0.35)
		local foot = root * CFrame.new(math.cos(a) * height * 0.1, -height * 0.03, math.sin(a) * height * 0.1)
		shard(m, tilt(foot, a, amount), h, h * rng:range(0.24, 0.3), colors[i % #colors + 1], glowTip, clear)
	end
end

local function sparkle(part: BasePart, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.3, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 4
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = part
end

-- Crystal growth per level: sockets used, cluster height scale, shards per cluster.
local GROWTH = {
	{ sockets = 2, height = 1.5, count = 3 },
	{ sockets = 4, height = 1.9, count = 4 },
	{ sockets = 6, height = 2.3, count = 4 },
	{ sockets = 99, height = 2.6, count = 4 },
}

--[[
	Upgrade look: crystal clusters on the sockets (more and bigger per level),
	then the machine turns to crystal by colour role: level 2 the orange glow
	and trims, level 3 the slate frames and pipes, level 4 the cream body
	(opaque glossy crystal, glowing inside).
]]
local function crystalize(ctx: Ctx, level: number, theme: Theme)
	if level <= 0 then
		return
	end
	local growth = GROWTH[math.min(level, #GROWTH)]
	local rng = Rng.new(ctx.model.Name .. "/" .. level)
	local crystals = Instance.new("Model")
	crystals.Name = "Crystals"
	crystals.Parent = ctx.model
	local glowTip = level >= 4
	local clear = level >= 4
	local top: Socket? = nil
	for i, s in ctx.sockets do
		if s.hero then
			top = s
		elseif i <= growth.sockets then
			cluster(crystals, s.cf, growth.count, s.size * growth.height, theme, rng, glowTip, clear)
		end
	end
	if level >= 4 and top then
		cluster(crystals, top.cf, 5, top.size * 2.3, theme, rng, true, true)
	end
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Kit")
			if (role == "Neon" or role == "Plasma" or role == "Cyan") and level >= 2 then
				d.Color = theme.Main
			elseif role == "Trim" and level >= 2 then
				d.Color = if level >= 4 then theme.Deep else theme.Main
			-- crystal machine parts stay opaque and glossy: see-through parts would
			-- show the round corners inside them as balls (owner: no balls under crystals)
			elseif role == "Frame" and level >= 3 then
				d.Color = theme.Deep:Lerp(theme.Main, 0.25)
				d.Reflectance = 0.1
			elseif role == "Pipe" and level >= 3 then
				d.Color = theme.Main:Lerp(theme.Deep, 0.4)
				d.Reflectance = 0.1
			elseif (role == "Body" or role == "Brick" or role == "Gold" or role == "Felt" or role == "Accent") and level >= 4 then
				d.Color = theme.Main:Lerp(theme.Pale, 0.35)
				d.Reflectance = 0.1
			elseif role == "Dark" and level >= 4 then
				d.Color = theme.Deep:Lerp(theme.Main, 0.25)
				d.Material = NEON
			end
		end
	end
	if level >= 3 then
		light(ctx.base, theme.Main, if level >= 4 then 16 else 10, if level >= 4 then 1.4 else 0.8)
	end
	if level >= 4 then
		sparkle(ctx.base, theme.Pale)
	end
end

-- A crystal socket at `pos` growing along `up`.
local function socket(ctx: Ctx, pos: Vector3, up: Vector3, size: number, hero: boolean?)
	local u = up.Unit
	local ref = if math.abs(u.Y) < 0.95 then UP else ZA
	local x = ref:Cross(u).Unit
	local z = x:Cross(u)
	table.insert(ctx.sockets, { cf = CFrame.fromMatrix(pos, x, u, z), size = size, hero = hero })
end

-- Up and outward from the corner direction (dx, dz).
local function out(dx: number, dz: number, lean: number?): Vector3
	return Vector3.new(dx * (lean or 0.55), 1, dz * (lean or 0.55))
end

---------------------------------------------------------------- machines

-- Footprints (cells) of the roster machines that MachineData does not have yet (proposals).
KitMachines.Sizes = {
	IronBox = { 2, 2 },
	Sorter = { 1, 1 },
	Polisher = { 2, 2 },
	BrickFurnace = { 2, 2 },
	PlasmaFurnace = { 2, 2 },
	AlloyFurnace = { 3, 2 },
	CrystalExtractor = { 2, 2 },
	RestorationTable = { 2, 2 },
	SellBox = { 2, 2 },
	ExpressConveyor = { 1, 1 },
	Splitter = { 1, 1 },
	RobotArm = { 1, 1 },
	SolarPanel = { 2, 2 },
	WindTurbine = { 2, 2 },
	FusionReactor = { 3, 3 },
	PowerPole = { 1, 1 },
	BeltLift = { 1, 3 },
	Slide = { 1, 3 },
} :: { [string]: { number } }

-- Machines without a front output (they sell, route sideways, hand over or make power).
local NO_OUTPUT: { [string]: boolean } = {
	SellBox = true,
	Sorter = true,
	Splitter = true,
	RobotArm = true,
	SolarPanel = true,
	WindTurbine = true,
	FusionReactor = true,
	PowerPole = true,
	ExpressConveyor = true,
}

local function sizeOf(id: string): { number }
	local machine = MachineData.ById[id]
	if machine then
		return machine.Size
	end
	return KitMachines.Sizes[id] or { 2, 2 }
end

-- The output point (same rule as Grid.outputLocal for the machines MachineData does not have yet).
local function outputFor(id: string): Vector3?
	if MachineData.ById[id] then
		return Grid.outputLocal(id)
	end
	if NO_OUTPUT[id] then
		return nil
	end
	local size = sizeOf(id)
	local cell = GameConfig.CellSize
	local column = math.floor(size[1] / 2)
	return Vector3.new(-size[1] * cell / 2 + (column + 0.5) * cell, 1.8, -(size[2] * cell / 2) - 0.5)
end
KitMachines.outputFor = outputFor

local function newModel(id: string): Ctx
	local size = sizeOf(id)
	local w, d = size[1] * GameConfig.CellSize, size[2] * GameConfig.CellSize
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("MachineId", id)
	local base = block(model, CFrame.new(0, FLOOR / 2, 0), Vector3.new(w - 0.3, FLOOR, d - 0.3), "Floor", SOLID, "Base")
	paint(base, Enum.NormalId.Top, {
		{ x = 0, y = 0, w = 1, h = 0.04, color = P.Trim, stripes = 16 },
		{ x = 0, y = 0.96, w = 1, h = 0.04, color = P.Trim, stripes = 16 },
	})
	model.PrimaryPart = base :: any
	return { model = model, base = base, sockets = {} }
end

--[[
	Clay Furnace (2x2): a soft cream body on a glowing slate plinth, a slate
	pill lid, the arched glowing door, a fat chimney, a bowl hopper (the
	intake), a capsule tank with a glowing porthole whose pipe bends into the
	body, a chute from the door to the output, a screen on the right side.
]]
local function clayFurnace(): Ctx
	local ctx = newModel("ClayFurnace")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0.25, -0.1, 5.8, 4.4, 5.4, 1.0
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.7, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	local doorX = 0.75
	door(m, doorX, bodyY + 0.15, front, 2.2, 1.3, "Glow", "Glow")
	-- fat chimney at the back left, bowl hopper at the front right
	local cx, cz = hx - 1.25, hz + 1.1
	chimney(m, Vector3.new(cx, lidTop, cz), 1.5, 3.3, 2)
	local bx, bz = hx + 1.25, hz - 0.5
	local rim = bowl(m, Vector3.new(bx, lidTop, bz), 2.3, 0.5)
	-- capsule tank on the left with a glowing porthole; its pipe bends into the body
	local tx, tz = hx - w / 2 - 0.55, hz + 0.9
	local tankTop = capsule(m, Vector3.new(tx, FLOOR, tz), 1.5, 2.2, { port = -ZA })
	local pd, pr = 0.55, 0.5
	local p0 = Vector3.new(tx, tankTop - 0.1, tz)
	local p1 = p0 + UP * 0.4
	rod(m, p0, p1, pd, "Pipe", PROP)
	local p2 = bend(m, p1, UP, XA, pd, pr)
	pipe(m, p2, Vector3.new(hx - w / 2 + 0.3, p2.Y, tz), pd, { a = false })
	-- chute from the door to the shared output cell
	local outPos = Grid.outputLocal("ClayFurnace") :: Vector3
	chute(m, Vector3.new(doorX, bodyY + 0.45, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.3)
	screenPanel(m, CFrame.new(hx + w / 2 + 0.22, bodyY, hz + 1.2) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.6)

	socket(ctx, Vector3.new(hx - w / 2 + 0.7, top - 0.3, front + 0.7), out(-1, -1), 1.3)
	socket(ctx, Vector3.new(tx + 0.1, FLOOR, tz + 1.35), out(-0.6, 1, 0.7), 1.0)
	socket(ctx, Vector3.new(hx + w / 2 - 0.7, top - 0.3, hz + d / 2 - 0.7), out(1, 1), 1.2)
	socket(ctx, Vector3.new(-3.4, FLOOR, -3.3), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(3.4, FLOOR, 3.3), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(hx + w / 2 - 0.7, top - 0.3, front + 0.7), out(1, -1), 1.0)
	socket(ctx, Vector3.new(bx + 1.1, rim - 0.4, bz), out(1, 0, 0.9), 0.9)
	socket(ctx, Vector3.new(hx - w / 2 - 0.1, bodyY + 2.4, hz - 1.4), Vector3.new(-1, 0.6, 0), 0.9)
	socket(ctx, Vector3.new(cx, lidTop + 3.6, cz), UP, 1.0, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return ctx
end

--[[
	Crusher (2x2): a soft cream body on a glowing plinth under a big square
	hopper (cream funnel, slate rim with round corners and glowing strips,
	the two toothed rollers turning inside), an arched opening at the front
	with a chute to the output, cogs on the left side, a screen on the right,
	a stack light.
]]
local function crusher(): Ctx
	local ctx = newModel("Crusher")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0.2, 0.3, 5.6, 3.5, 5.0, 0.9
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.7, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	local top = bodyY + h
	local outPos = Grid.outputLocal("Crusher") :: Vector3
	local front = hz - d / 2
	local doorX = 1.1
	door(m, doorX, bodyY + 0.1, front, 1.3, 0.8, "Dark")
	chute(m, Vector3.new(doorX, bodyY + 0.45, front - 0.5), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.2)
	-- hopper: a slate tray with round corners sitting in the round top, glowing
	-- strips round it, a dark floor with the two toothed rollers on it
	local topW = 4.8
	local rimH = 1.3
	local rimY = top - 0.35
	pillSlab(m, Vector3.new(hx, rimY, hz), topW, rimH, topW, 0.6, "Frame")
	glowStrips(m, Vector3.new(hx, rimY + rimH * 0.62, hz), topW, topW, 0.6, 0.14)
	pillSlab(m, Vector3.new(hx, rimY + rimH, hz), topW - 0.7, 0.04, topW - 0.7, 0.35, "Dark", TINY)
	for i, zc in { -0.6, 0.6 } do
		local center = Vector3.new(hx, rimY + rimH + 0.3, hz + zc)
		cyl(m, center, XA, topW - 1.3, 0.85, "Frame", TINY, "Roller" .. i)
		for k = 0, 1 do
			block(
				m,
				along(center, XA) * CFrame.Angles(k * math.pi / 2 + i * 0.4, 0, 0),
				Vector3.new(topW - 1.5, 1.1, 0.22),
				"Trim",
				TINY,
				"Roller" .. i .. "Tooth"
			)
		end
	end
	local rimTop = rimY + rimH
	local sx = hx - w / 2 - 0.22
	cog(m, Vector3.new(sx, bodyY + 1.6, hz + 0.8), XA, 2.2, 0.36, "Cog1")
	cog(m, Vector3.new(sx - 0.02, bodyY + 2.35, hz - 0.95), XA, 1.5, 0.36, "Cog2")
	screenPanel(m, CFrame.new(hx + w / 2 + 0.22, bodyY, hz + 0.6) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.7, P.Water)
	stackLight(m, Vector3.new(-3.3, FLOOR, 3.3), 1.0)

	socket(ctx, Vector3.new(hx + w / 2 - 0.6, top - 0.3, front + 0.6), out(1, -1), 1.2)
	socket(ctx, Vector3.new(hx - w / 2 + 0.6, top - 0.3, hz + d / 2 - 0.6), out(-1, 1), 1.2)
	socket(ctx, Vector3.new(-3.4, FLOOR, -3.3), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(hx - topW / 2 + 0.2, rimTop, hz - topW / 2 + 0.2), out(-1, -1, 0.9), 0.9)
	socket(ctx, Vector3.new(3.4, FLOOR, 3.3), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(hx + topW / 2 - 0.2, rimTop, hz + topW / 2 - 0.2), out(1, 1, 0.9), 0.9)
	socket(ctx, Vector3.new(hx + w / 2 - 0.6, top - 0.3, hz + d / 2 - 0.6), out(1, 1), 1.0)
	socket(ctx, Vector3.new(hx - w / 2 - 0.1, bodyY + 2.8, hz - 2.0), Vector3.new(-1, 0.6, 0), 0.8)
	socket(ctx, Vector3.new(hx + topW / 2 - 0.2, rimTop, hz - topW / 2 + 0.2), out(1, -1, 0.5), 1.0, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return ctx
end

--[[
	Cleaning Plant / Auto Cleaner (2x2): a roller bed (slate body, cream rails
	with round orange tops and glowing strips, a glowing water tray) through a
	gantry of round cream pillars and a round slate beam holding the shower
	head; a brush drum in front of it; a capsule water tank with a glowing
	porthole and a glowing glass column feeds a pipe over the top (glass
	section with glowing water and a coil, a valve, down into the beam); a
	bowl hopper over the back of the bed; a stack light; a vent.
]]
local function autoCleaner(): Ctx
	local ctx = newModel("AutoCleaner")
	local m = ctx.model
	local outPos = Grid.outputLocal("AutoCleaner") :: Vector3
	local bx, bw = outPos.X - 0.1, 3.2
	local z0, z1 = -3.85, 3.7
	local len = z1 - z0
	local bz = (z0 + z1) / 2
	block(m, CFrame.new(bx, FLOOR + 0.5, bz), Vector3.new(bw - 0.4, 1.0, len), "Frame", SOLID, "Bed")
	for _, side in { -1, 1 } do
		local rx = bx + side * (bw / 2 - 0.22)
		local railPart = block(m, CFrame.new(rx, FLOOR + 0.75, bz), Vector3.new(0.44, 1.5, len), "Body", SOLID)
		paint(railPart, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, {
			{ x = 0, y = 0.8, w = 1, h = 0.2, color = P.Trim, stripes = 24 },
		})
		cyl(m, Vector3.new(rx, FLOOR + 1.5, bz), ZA, len, 0.44, "Trim", SOLID)
		block(m, CFrame.new(bx + side * (bw / 2 + 0.02), FLOOR + 1.0, bz), Vector3.new(0.05, 0.16, len - 0.8), "Neon", TINY)
	end
	local pool = block(m, CFrame.new(bx, FLOOR + 1.05, bz), Vector3.new(bw - 0.9, 0.1, len - 0.2), "Water", TINY, "WaterPool")
	pool.Material = SMOOTH
	pool.Transparency = POOL_TRANSPARENCY
	for i = 0, 5 do
		cyl(m, Vector3.new(bx, FLOOR + 1.35, z0 + 0.6 + i * (len - 1.2) / 5), XA, bw - 0.9, 0.66, "Body", SOLID, "BedRoller")
	end
	-- gantry: round cream pillars on orange feet, a round slate beam with ball ends
	local az = -0.4
	local legX = { bx - bw / 2 - 0.3, bx + bw / 2 - 0.1 }
	local beamY = FLOOR + 5.0
	for _, lx in legX do
		cyl(m, Vector3.new(lx, FLOOR + 0.25, az), UP, 0.5, 1.15, "Trim", SOLID)
		cyl(m, Vector3.new(lx, (FLOOR + beamY) / 2, az), UP, beamY - FLOOR, 0.85, "Body", SOLID)
		cyl(m, Vector3.new(lx, FLOOR + 2.6, az), UP, 0.16, 0.92, "Neon", TINY)
		ball(m, Vector3.new(lx, beamY, az), 1.1, "Frame", SOLID)
	end
	rod(m, Vector3.new(legX[1], beamY, az), Vector3.new(legX[2], beamY, az), 0.95, "Frame", SOLID, "Arch")
	block(m, CFrame.new(bx, beamY - 0.3, az - 0.46), Vector3.new(legX[2] - legX[1] - 1.2, 0.1, 0.05), "Neon", TINY)
	local headY = beamY - 0.65
	cyl(m, Vector3.new(bx, headY, az), XA, 1.5, 0.45, "Body", TINY, "ShowerHead")
	for i = -1, 1 do
		cyl(m, Vector3.new(bx + i * 0.45, headY - 0.25, az), UP, 0.1, 0.2, "Water", TINY)
	end
	local outlet = Vector3.new(bx, headY - 0.3, az)
	local landing = Vector3.new(bx, FLOOR + 1.9, az)
	local wo = attach(ctx.base, "WaterOut", ctx.base.CFrame:ToObjectSpace(CFrame.lookAt(outlet, outlet - UP)))
	wo.Axis = -UP
	wo:SetAttribute("Curve", 0.6)
	wo:SetAttribute("Spray", true)
	local wi = attach(ctx.base, "WaterIn", CFrame.new(ctx.base.CFrame:PointToObjectSpace(landing)))
	wi.Axis = -UP
	wi:SetAttribute("Curve", 0.3)
	-- brush drum on two arms in front of the gantry
	local drumZ = az - 1.35
	local drumY = FLOOR + 3.3 -- the brush rests on top of ore riding the bed
	for _, lx in legX do
		block(m, CFrame.new(lx, drumY + 0.25, (az + drumZ) / 2), Vector3.new(0.3, 0.3, az - drumZ), "Frame", PROP)
		ball(m, Vector3.new(lx, drumY + 0.25, drumZ), 0.45, "Frame", TINY)
	end
	local drumC = Vector3.new(bx, drumY, drumZ)
	local drum = cyl(m, drumC, XA, bw - 0.6, 0.85, "Body", PROP, "Drum")
	drum.Color = P.Bristle
	for _, dx in { -0.85, 0, 0.85 } do
		local rib = cyl(m, drumC + Vector3.new(dx, 0, 0), XA, 0.22, 1.08, "Body", TINY, "DrumRib")
		rib.Color = P.Bristle:Lerp(WHITE, 0.3)
	end
	cyl(m, drumC, XA, bw - 0.3, 0.32, "Trim", TINY)
	-- capsule water tank with the glowing glass column; the pipe over the top
	local tx, tz, td = -2.35, az, 2.1
	local tankTop = capsule(m, Vector3.new(tx, FLOOR, tz), td, 3.0, { port = -XA, glow = "Water", name = "WaterTank" })
	local colZ = tz - td / 2 - 0.5
	cyl(m, Vector3.new(tx, FLOOR + 0.35, colZ), UP, 0.7, 0.95, "Frame", SOLID)
	pipe(m, Vector3.new(tx, FLOOR + 0.7, colZ), Vector3.new(tx, FLOOR + 3.6, colZ), 0.6, { fluid = "Water" })
	cyl(m, Vector3.new(tx, FLOOR + 3.75, colZ), UP, 0.3, 0.85, "Frame", TINY)
	ball(m, Vector3.new(tx, FLOOR + 3.9, colZ), 0.6, "Frame", TINY)
	local pd, pr = 0.75, 0.6
	local runY = beamY + 1.3
	local p0 = Vector3.new(tx, runY - pr, tz)
	pipe(m, Vector3.new(tx, tankTop - 0.2, tz), p0, pd, { b = false })
	local p1 = bend(m, p0, UP, XA, pd, pr)
	local endX = bx - pr
	local glassFrom, glassTo = p1.X + 0.3, endX - 1.0
	pipe(m, p1, Vector3.new(glassFrom, runY, tz), pd, { a = false })
	pipe(m, Vector3.new(glassFrom, runY, tz), Vector3.new(glassTo, runY, tz), pd, { fluid = "Water" })
	pipe(m, Vector3.new(glassTo, runY, tz), Vector3.new(endX, runY, tz), pd, { b = false })
	valve(m, Vector3.new((glassTo + endX) / 2 + 0.05, runY, tz), XA, pd, -ZA)
	local p2 = bend(m, Vector3.new(endX, runY, tz), XA, -UP, pd, pr)
	pipe(m, p2, Vector3.new(bx, beamY + 0.4, tz), pd, { a = false })
	-- intake bowl over the back of the bed
	local rim = bowl(m, Vector3.new(bx, FLOOR + 1.9, 2.35), 2.5, 1.0)
	local vent = cyl(m, Vector3.new(-3.2, FLOOR + 0.6, 3.1), UP, 1.2, 0.7, "Pipe", PROP, "Vent")
	cyl(m, Vector3.new(-3.2, FLOOR + 1.05, 3.1), UP, 0.22, 0.9, "Trim", TINY)
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Smoke"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = 3
	steam.Parent = vent
	stackLight(m, Vector3.new(-3.3, FLOOR, -3.3), 0.95)

	socket(ctx, Vector3.new(tx - 0.3, FLOOR, tz + 1.55), out(-1, 1, 0.7), 1.1)
	socket(ctx, Vector3.new(legX[2] + 0.2, FLOOR + 0.5, az + 0.6), out(1, 0.6, 0.8), 1.0)
	socket(ctx, Vector3.new(-3.4, FLOOR, 3.3), out(-1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(bx + 1.1, rim - 0.4, 2.35 + 0.9), out(1, 1, 0.8), 0.9)
	socket(ctx, Vector3.new(legX[1] - 0.2, FLOOR, az + 0.9), out(-0.6, 1, 0.7), 0.8)
	socket(ctx, Vector3.new(3.5, FLOOR, -3.4), out(1, -1, 0.9), 0.9)
	socket(ctx, Vector3.new(bx + bw / 2, FLOOR + 1.6, 3.0), Vector3.new(1, 0.7, 0), 0.8)
	socket(ctx, Vector3.new(bx, beamY + 0.45, az + 0.25), out(0, 1, 0.3), 0.9, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return ctx
end

--[[
	Blast Furnace (3x3): a big soft cream body on a glowing plinth, a slate
	pill lid, a wide arched glowing door with a round badge (a glowing double
	mountain peak) above it, a molten bowl throat on the lid, a fat chimney,
	a pipe arching off the top into a glass drop of molten metal and a
	capsule tank, a molten pour channel to the output, a stack light, a screen.
]]
local function blastFurnace(): Ctx
	local ctx = newModel("BlastFurnace")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0.2, 8.4, 5.8, 7.6, 1.4
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.8, d + 0.8, 0.8, 1.0)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 2.6, 0.5, d - 2.6, 0.9, "Frame")
	local lidTop = top + 0.35
	local front = hz - d / 2
	door(m, 0, bodyY + 0.15, front, 3.2, 1.3, "Glow", "Glow")
	-- round badge with a glowing double peak
	local by = bodyY + 4.45
	cyl(m, Vector3.new(0, by, front - 0.1), ZA, 0.24, 1.7, "Frame", TINY)
	cyl(m, Vector3.new(0, by, front - 0.2), ZA, 0.06, 1.95, "Trim", TINY)
	for _, peak in { { -0.15, 0.36, 0.3 }, { 0.36, 0.24, 0.2 } } do
		local px, ph, pw = peak[1], peak[2], peak[3]
		for _, side in { -1, 1 } do
			local a = Vector3.new(px + side * pw * 1.6, by - ph * 0.9, front - 0.24)
			local b = Vector3.new(px, by + ph * 0.7, front - 0.24)
			local angle = math.atan2(b.Y - a.Y, b.X - a.X)
			block(m, CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, angle), Vector3.new((b - a).Magnitude + 0.1, 0.13, 0.05), "Neon", TINY)
		end
	end
	-- molten throat on the lid
	local rim = bowl(m, Vector3.new(1.6, lidTop, hz - 0.9), 2.9, 0.5, "Molten")
	-- (one light per machine on phones: the door's)
	-- the pipe arching off the top into the molten glass drop and the tank on the right
	local pd, pr = 0.95, 0.8
	local tx, tz = 5.05, 2.7
	local tankTop = capsule(m, Vector3.new(tx, FLOOR, tz), 1.5, 2.6, { port = -ZA, glow = "Molten", name = "MoltenTank" })
	local sx = tx - 2 * pr
	local up0, up1 = Vector3.new(sx, top - 0.5, tz), Vector3.new(sx, top + 0.9, tz)
	pipe(m, up0, up1, pd, { b = false })
	local over = bend(m, up1, UP, XA, pd, pr)
	local down0 = bend(m, over, XA, -UP, pd, pr)
	pipe(m, down0, Vector3.new(tx, tankTop - 0.3, tz), pd, { fluid = "Molten" })
	chimney(m, Vector3.new(-2.3, lidTop, hz + 1.5), 1.8, 5.0, 5)
	-- pour channel from the door to the output, molten metal in it
	local outPos = Grid.outputLocal("BlastFurnace") :: Vector3
	chute(m, Vector3.new(0, bodyY + 0.2, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.4, outPos.Z + 0.35), 1.6)
	local a, b = Vector3.new(0, bodyY + 0.33, front - 0.6), Vector3.new(outPos.X, outPos.Y - 0.27, outPos.Z + 0.6)
	block(m, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.7, 0.06, (b - a).Magnitude), "Molten", TINY, "Molten")
	stackLight(m, Vector3.new(-5.3, FLOOR, -5.1), 1.2)
	screenPanel(m, CFrame.new(-w / 2 - 0.25, bodyY, hz - 0.6) * CFrame.Angles(0, -math.pi / 2, 0), 2.0, 2.0)

	socket(ctx, Vector3.new(-w / 2 + 1.0, top - 0.45, front + 1.0), out(-1, -1), 1.6)
	socket(ctx, Vector3.new(tx + 0.1, FLOOR, tz + 1.3), out(1, 1, 0.7), 1.1)
	socket(ctx, Vector3.new(w / 2 - 1.0, top - 0.45, front + 1.0), out(1, -1), 1.5)
	socket(ctx, Vector3.new(-5.4, FLOOR, 5.3), out(-1, 1, 0.8), 1.4)
	socket(ctx, Vector3.new(5.4, FLOOR, -5.3), out(1, -1, 0.8), 1.3)
	socket(ctx, Vector3.new(-w / 2 + 1.0, top - 0.45, hz + d / 2 - 1.0), out(-1, 1), 1.3)
	socket(ctx, Vector3.new(-w / 2 - 0.1, bodyY + 3.4, hz + 2.6), Vector3.new(-1, 0.6, 0), 1.0)
	socket(ctx, Vector3.new(1.6 + 1.4, rim - 0.4, hz - 0.9), out(1, 0, 0.8), 1.0)
	socket(ctx, Vector3.new(1.6, rim + 0.05, hz - 0.9), UP, 1.3, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return ctx
end

--[[
	Cleaning Station (3x2): a soft cream workbench on a glowing plinth
	(painted drawers, an arched knee recess), a slate pill work top, the vise
	in the middle, a round tub of glowing blue water on the left fed by a
	slate pipe (glass section with a coil, valve, open end), an orange robot
	arm over the output tray, a round screen panel, a lever and a tool
	board. Same minigame points as MachineBuilder.
]]
local function cleaningStation(): Ctx
	local ctx = newModel("CleaningStation")
	local m = ctx.model
	local top = 3.4
	local benchZ = 0.4
	local front = benchZ - 2.3
	local bw, bd = 10, 4.6
	local bodyY = plinth(m, Vector3.new(0, FLOOR, benchZ), bw + 0.4, bd + 0.4, 0.55, 0.6)
	local body = softBox(m, Vector3.new(0, bodyY, benchZ), bw, top - bodyY, bd, 0.5, "Body", "Body")
	local _ = body
	local frontPart = m:FindFirstChild("BodyFront") :: BasePart?
	if frontPart then
		paint(frontPart, Enum.NormalId.Front, {
			{ x = 0.06, y = 0.18, w = 0.2, h = 0.66, color = P.Bolt },
			{ x = 0.066, y = 0.19, w = 0.188, h = 0.64, color = P.Body },
			{ x = 0.12, y = 0.3, w = 0.08, h = 0.08, color = P.Trim, round = true },
			{ x = 0.74, y = 0.18, w = 0.2, h = 0.66, color = P.Bolt },
			{ x = 0.746, y = 0.19, w = 0.188, h = 0.64, color = P.Body },
			{ x = 0.8, y = 0.3, w = 0.08, h = 0.08, color = P.Trim, round = true },
		})
	end
	-- arched knee recess with a glowing line over it
	arch(m, Vector3.new(0, bodyY, front - 0.02), 3.2, 0.8, 0.08, "Dark", TINY)
	block(m, CFrame.new(0, bodyY + 2.5, front - 0.05), Vector3.new(3.6, 0.1, 0.05), "Neon", TINY)
	-- work top: a slate pill slab
	local deck = top + 0.3
	pillSlab(m, Vector3.new(0, top - 0.05, benchZ + 0.1), bw + 0.6, 0.35, bd + 0.5, 0.5, "Frame", SOLID, "Bench")
	-- work slab + vise
	block(m, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), "Dark", SOLID, "WorkSlab")
	for _, side in { -1, 1 } do
		block(m, CFrame.new(side * 1.75, top + 0.95, 0.3), Vector3.new(0.5, 0.5, 2.2), "Body", SOLID, "Jaw")
		cyl(m, Vector3.new(side * 1.75, top + 1.2, 0.3), ZA, 2.2, 0.5, "Body", TINY)
	end
	cyl(m, Vector3.new(-1.75, top + 0.95, -0.98), ZA, 0.36, 0.5, "Frame", TINY)
	cyl(m, Vector3.new(-1.75, top + 0.95, -1.27), XA, 1.2, 0.18, "Trim", TINY)
	-- round tub with glowing water and a glowing rim
	local tx, tz = -4.15, -0.5
	local tubD = 2.4
	cyl(m, Vector3.new(tx, deck + 0.4, tz), UP, 0.8, tubD, "Body", SOLID, "Tub")
	local tubTop = deck + 0.96
	cyl(m, Vector3.new(tx, tubTop - 0.08, tz), UP, 0.3, tubD + 0.3, "Frame", SOLID)
	cyl(m, Vector3.new(tx, tubTop - 0.08, tz), UP, 0.1, tubD + 0.36, "Water", TINY)
	local poolTop = tubTop + 0.1
	local pool = cyl(m, Vector3.new(tx, poolTop - 0.06, tz), UP, 0.12, tubD - 0.2, "Water", TINY, "WaterPool")
	pool.Material = SMOOTH
	pool.Transparency = POOL_TRANSPARENCY
	-- the water pipe: riser out of the plot, glass section, bend over the tub, valve, open end
	local pd, px, pipeY, outX = 0.62, -5.62, 6.6, -4.35
	local pr = 0.55
	pipe(m, Vector3.new(px, FLOOR, tz), Vector3.new(px, pipeY - pr - 1.8, tz), pd)
	pipe(m, Vector3.new(px, pipeY - pr - 1.8, tz), Vector3.new(px, pipeY - pr, tz), pd, { fluid = "Water" })
	local p1 = bend(m, Vector3.new(px, pipeY - pr, tz), UP, XA, pd, pr)
	pipe(m, p1, Vector3.new(outX, pipeY, tz), pd, { a = false })
	valve(m, Vector3.new((p1.X + outX) / 2, pipeY, tz), XA, pd, -ZA)
	cyl(m, Vector3.new(outX + 0.02, pipeY, tz), XA, 0.04, pd * 0.7, "Dark", TINY)
	local outlet = Vector3.new(outX + 0.2, pipeY - 0.04, tz)
	local landing = Vector3.new(outX + 0.55, poolTop, tz)
	local wo = attach(ctx.base, "WaterOut", ctx.base.CFrame:ToObjectSpace(CFrame.lookAt(outlet, outlet + XA)))
	wo.Axis = XA
	wo:SetAttribute("Curve", 0.4)
	local wi = attach(ctx.base, "WaterIn", CFrame.new(ctx.base.CFrame:PointToObjectSpace(landing)))
	wi.Axis = -UP
	wi:SetAttribute("Curve", 0.6)
	-- tool board at the back: chisel, hammer, brush
	local boardZ = 2.85
	pillSlab(m, Vector3.new(-0.6, top + 0.3, boardZ), 3.6, 2.6, 0.3, 0.12, "Frame", SOLID)
	local toolZ = boardZ - 0.22
	block(m, CFrame.new(-1.9, top + 1.75, toolZ), Vector3.new(0.24, 1.6, 0.16), "Body", TINY)
	block(m, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), "Trim", TINY)
	block(m, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), "Body", TINY)
	block(m, CFrame.new(0.5, top + 1.75, toolZ), Vector3.new(0.7, 1.2, 0.3), "Trim", TINY)
	screenPanel(m, CFrame.new(2.2, deck, 2.8), 1.8, 2.2)
	-- lever
	local lx, lz = 4.7, 1.55
	cyl(m, Vector3.new(lx, deck + 0.12, lz), UP, 0.24, 1.0, "Frame", TINY)
	rod(m, Vector3.new(lx, deck + 0.2, lz), Vector3.new(lx, deck + 0.85, lz - 0.3), 0.14, "Dark", TINY)
	ball(m, Vector3.new(lx, deck + 0.9, lz - 0.32), 0.36, "Trim", TINY)
	-- output tray on the right, the robot arm over it
	block(m, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), "Dark", SOLID, "Tray")
	for _, side in { -1, 1 } do
		cyl(m, Vector3.new(3.6 + side * 1.22, top + 0.72, -0.4), ZA, 2.4, 0.3, "Body", SOLID)
	end
	cyl(m, Vector3.new(3.6, top + 0.72, -0.4 + 1.22), XA, 2.6, 0.3, "Body", SOLID)
	block(m, CFrame.new(3.6, top + 0.62, -0.4 - 1.25), Vector3.new(2.4, 0.06, 0.05), "Neon", TINY)
	robotArm(m, Vector3.new(4.55, deck, 2.6), Vector3.new(4.2, deck + 2.6, 1.6), Vector3.new(3.7, deck + 2.2, 0.2), 0.9)

	socket(ctx, Vector3.new(-5.0, deck, 2.2), out(-1, 1), 1.1)
	socket(ctx, Vector3.new(5.6, FLOOR, -1.6), out(1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(-5.6, FLOOR, -1.7), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(5.0, deck, 2.4), out(1, 1), 1.0)
	socket(ctx, Vector3.new(1.3, top + 2.9, boardZ), out(0.6, 1, 0.5), 0.8)
	socket(ctx, Vector3.new(-5.6, FLOOR, 3.5), out(-1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(5.6, FLOOR, 3.5), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(px, pipeY - pr - 1.8, tz - 0.5), Vector3.new(-0.5, 0.4, -1), 0.7)
	socket(ctx, Vector3.new(2.2, deck + 2.25, 2.9), UP, 0.8, true)

	local orePoint = CFrame.new(0, top + 1.95, 0.3)
	attach(ctx.base, "OrePoint", orePoint)
	attach(ctx.base, "CamPoint", CFrame.lookAt(Vector3.new(0, top + 5.4, -4.6), orePoint.Position + Vector3.new(0, 0.1, 0)))
	attach(ctx.base, "Output", CFrame.new(3.6, top + 1.4, -0.4))
	attach(ctx.base, "Prompt", CFrame.new(0, top + 0.6, -2.4))
	local intake = attach(ctx.base, "Intake", orePoint)
	intake:SetAttribute("IntakeSize", Vector3.new(3.4, 2.6, 3.4))
	return ctx
end

---------------------------------------------------------------- conveyors

local BELT_TOP = 0.8 -- the belt surface items ride on (same as MachineBuilder's belts)
local BELT_W = 3.0
local RAIL_X = 1.75

-- Black belt with painted segments (lines across) and optional orange markers.
local function beltPaint(belt: BasePart, length: number, markers: boolean)
	local items: { Paint } = {}
	local n = math.max(2, math.floor(length / 0.8 + 0.5))
	for i = 1, n - 1 do
		table.insert(items, { x = 0, y = i / n - 0.008, w = 1, h = 0.016, color = rgb(56, 60, 76) })
	end
	if markers then
		local count = math.max(1, math.floor(length / 2.4))
		for i = 0, count - 1 do
			table.insert(items, { x = 0.38, y = (i + 0.4) / count, w = 0.24, h = 0.7 / length, color = P.Trim, round = true })
		end
	end
	paint(belt, Enum.NormalId.Top, items, "BeltPaint")
end

--[[
	A slate rail (`cf` = its centre) with a round orange top, round rivets on
	the outer face and a glowing strip. Returns the rail block.
]]
local function rail(m: Instance, cf: CFrame, length: number, side: number, name: string?, flags: Props?): BasePart
	local part = block(m, cf, Vector3.new(0.5, 0.9, length), "Frame", flags or SOLID, name)
	cyl(m, (cf * CFrame.new(0, 0.45, 0)).Position, cf.LookVector, length, 0.5, "Trim", TINY, "RailCap")
	local dots: { Paint } = {}
	local n = math.max(1, math.floor(length / 2))
	for i = 0, n - 1 do
		table.insert(dots, { x = (i + 0.5) / n - 0.02, y = 0.12, w = 0.04, h = 0.14, color = P.Bolt, round = true })
	end
	paint(part, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, dots, "RailFace")
	block(m, cf * CFrame.new(side * 0.27, -0.05, 0), Vector3.new(0.05, 0.16, length * 0.62), "Neon", TINY, "RailGlow")
	return part
end

type CapOpts = { arrow: string?, beacon: boolean? }

--[[
	A belt end cap at `cf` (centre of the belt end on the belt surface; the
	belt lies toward -Z of `cf`, the cap sticks out toward +Z): a black drum
	with round orange side plates and hubs, and (with `arrow` = "right" /
	"up" / "down") a round-cornered control box beside it with an arrow
	screen and an amber beacon.
]]
local function beltCap(m: Instance, cf: CFrame, o: CapOpts?)
	local opts: CapOpts = o or {}
	local drumC = cf * CFrame.new(0, -0.38, 0.15)
	cyl(m, drumC.Position, cf.RightVector, BELT_W + 0.1, 0.86, "Rubber", PROP, "Drum")
	for _, side in { -1, 1 } do
		local at = (drumC * CFrame.new(side * RAIL_X, 0, 0)).Position
		cyl(m, at, cf.RightVector, 0.5, 1.25, "Trim", PROP)
		cyl(m, at + cf.RightVector * side * 0.27, cf.RightVector, 0.1, 0.55, "Frame", TINY)
		ball(m, at + cf.RightVector * side * 0.33, 0.3, "Trim", TINY)
	end
	if opts.arrow then
		local box = cf * CFrame.new(-(RAIL_X + 0.95), 0.2, 0.2)
		local bottom = (box * CFrame.new(0, -0.75, 0)).Position
		pillSlab(m, bottom, 1.2, 1.5, 1.1, 0.3, "Frame")
		cyl(m, bottom + Vector3.new(0, 0.1, 0), UP, 0.2, 1.3, "Trim", TINY)
		local screen = block(m, box * CFrame.new(0, 0.12, -0.57), Vector3.new(0.7, 0.75, 0.05), "Screen", TINY, "ArrowScreen")
		local color = if opts.arrow == "down" then P.Red else P.Green
		local items: { Paint }
		if opts.arrow == "right" then
			items = {
				{ x = 0.18, y = 0.44, w = 0.44, h = 0.12, color = color },
				{ x = 0.56, y = 0.28, w = 0.1, h = 0.44, color = color },
				{ x = 0.66, y = 0.38, w = 0.1, h = 0.24, color = color },
			}
		else
			local upArrow = opts.arrow == "up"
			items = {
				{ x = 0.44, y = 0.22, w = 0.12, h = 0.56, color = color },
				{ x = 0.28, y = if upArrow then 0.26 else 0.64, w = 0.44, h = 0.1, color = color },
				{ x = 0.38, y = if upArrow then 0.16 else 0.74, w = 0.24, h = 0.1, color = color },
			}
		end
		paint(screen, Enum.NormalId.Front, items)
		if opts.beacon ~= false then
			local bt = box * CFrame.new(0, 0.75, 0)
			cyl(m, (bt * CFrame.new(0, 0.1, 0)).Position, cf.UpVector, 0.2, 0.55, "Frame", TINY)
			local beacon = ball(m, (bt * CFrame.new(0, 0.36, 0)).Position, 0.5, "Lamp", TINY, "Beacon")
			beacon.Color = P.Amber
			beacon.Material = NEON
		end
	end
end

--[[
	1x1 conveyor (the parts the game uses: Base, Belt (tag ConveyorBelt),
	RailL, RailR, Arrow x2) in the soft style: black segmented belt, slate
	rails with round orange tops and glowing strips, orange feet.
	`caps` = { start = CapOpts?, finish = CapOpts? } adds end caps (back /
	front end of the cell).
]]
function KitMachines.conveyor(caps: { start: CapOpts?, finish: CapOpts? }?, express: boolean?): Model
	local model = Instance.new("Model")
	model.Name = if express then "ExpressConveyor" else "Conveyor"
	model:SetAttribute("MachineId", model.Name)
	local base = block(
		model,
		CFrame.new(0, 0.15, 0),
		Vector3.new(3.7, 0.3, 3.9),
		"Frame",
		{ CanTouch = false, CanCollide = false, CastShadow = false },
		"Base"
	)
	model.PrimaryPart = base :: any
	for _, side in { -1, 1 } do
		rail(
			model,
			CFrame.new(side * RAIL_X, 0.45, 0),
			4,
			side,
			if side < 0 then "RailL" else "RailR",
			{ CanTouch = false, CastShadow = false }
		)
		block(model, CFrame.new(side * RAIL_X, 0.1, 0), Vector3.new(0.7, 0.2, 1.0), "Trim", TINY, "Foot")
	end
	local belt = block(model, CFrame.new(0, BELT_TOP - 0.25, 0), Vector3.new(BELT_W, 0.5, 4), "Rubber", {
		CanTouch = true,
		CastShadow = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.2, 0, 100, 100),
	}, "Belt")
	belt:AddTag("ConveyorBelt")
	beltPaint(belt, 4, false)
	local w, h = 0.9, 0.6
	for _, side in { -1, 1 } do
		wedge(
			model,
			CFrame.new(side * w / 4, BELT_TOP + 0.02, 0) * CFrame.Angles(0, 0, -side * math.pi / 2),
			Vector3.new(0.04, w / 2, h),
			"Trim",
			TINY,
			"Arrow"
		)
	end
	if express then
		-- the Express Conveyor: cyan rail tops and glow, a second chevron (twice as fast)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "RailCap" then
				part.Color = P.Cyan:Lerp(BLACK, 0.15)
				part:SetAttribute("Kit", "Accent")
			elseif part:IsA("BasePart") and part.Name == "RailGlow" then
				style(part, "Cyan", TINY)
			end
		end
		for _, side in { -1, 1 } do
			wedge(
				model,
				CFrame.new(side * w / 4, BELT_TOP + 0.02, 1.0) * CFrame.Angles(0, 0, -side * math.pi / 2),
				Vector3.new(0.04, w / 2, h),
				"Cyan",
				TINY,
				"Arrow"
			)
			wedge(
				model,
				CFrame.new(side * w / 4, BELT_TOP + 0.02, -1.0) * CFrame.Angles(0, 0, -side * math.pi / 2),
				Vector3.new(0.04, w / 2, h),
				"Cyan",
				TINY,
				"Arrow"
			)
		end
	end
	if caps then
		if caps.start then
			beltCap(model, CFrame.new(0, BELT_TOP, 2), caps.start)
		end
		if caps.finish then
			beltCap(model, CFrame.new(0, BELT_TOP, -2) * CFrame.Angles(0, math.pi, 0), caps.finish)
		end
	end
	attach(base, "Prompt", CFrame.new(0, 1.5, 0))
	return model
end

--[[
	A belt slope `length` long rising `rise` (the Belt Lift carries items up,
	the Slide down; preview models, not in MachineData yet): a tilted
	segmented belt with round orange markers between tilted rails, round
	slate legs on orange feet with a cross brace under the high end, drums
	at both ends and the control box where items get on (green up arrow at
	the bottom of the lift, red down arrow at the top of the slide). Items
	travel toward -Z.
]]
function KitMachines.slope(up: boolean, length: number?, rise: number?): Model
	local L = length or 12
	local H = rise or 5
	local model = Instance.new("Model")
	model.Name = if up then "BeltLift" else "Slide"
	local base = block(model, CFrame.new(0, 0.05, 0), Vector3.new(0.1, 0.1, 0.1), "Frame", TINY, "Base")
	base.Transparency = 1
	model.PrimaryPart = base :: any
	local startZ, finishZ = L / 2 - 1, -L / 2 + 1
	local startY = if up then BELT_TOP else BELT_TOP + H
	local finishY = if up then BELT_TOP + H else BELT_TOP
	local a = Vector3.new(0, startY, startZ)
	local b = Vector3.new(0, finishY, finishZ)
	local len = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b)
	local belt = block(model, frame * CFrame.new(0, -0.25, 0), Vector3.new(BELT_W, 0.5, len), "Rubber", SOLID, "Belt")
	beltPaint(belt, len, true)
	for _, side in { -1, 1 } do
		rail(model, frame * CFrame.new(side * RAIL_X, -0.35, 0), len, side, nil, SOLID)
	end
	-- round legs on orange feet with a cross brace under the high end
	local highZ = if up then finishZ else startZ
	local highY = BELT_TOP + H
	local legZ = highZ + (if up then 1.0 else -1.0)
	local legTop = highY - 1.0
	for _, side in { -1, 1 } do
		cyl(model, Vector3.new(side * RAIL_X, (legTop + 0.4) / 2, legZ), UP, legTop - 0.4, 0.55, "Frame", SOLID)
		cyl(model, Vector3.new(side * RAIL_X, 0.25, legZ), UP, 0.5, 1.0, "Trim", SOLID)
		cyl(model, Vector3.new(side * RAIL_X, 0.25, legZ), UP, 0.12, 1.06, "Neon", TINY)
	end
	local yb = (legTop + 0.4) / 2
	local span = (legTop - 0.4) * 0.38
	for _, s in { -1, 1 } do
		rod(model, Vector3.new(-RAIL_X, yb - s * span, legZ + 0.3), Vector3.new(RAIL_X, yb + s * span, legZ + 0.3), 0.22, "Frame", PROP)
	end
	rod(model, Vector3.new(-RAIL_X - 0.2, legTop, legZ), Vector3.new(RAIL_X + 0.2, legTop, legZ), 0.5, "Frame", SOLID)
	-- drums at both ends, the control box where items get on
	beltCap(model, CFrame.new(a), { arrow = if up then "up" else "down" })
	beltCap(model, CFrame.new(b) * CFrame.Angles(0, math.pi, 0), nil)
	model:SetAttribute("MachineId", model.Name)
	attach(base, "Prompt", CFrame.new(0, 1.5, startZ))
	return model
end

---------------------------------------------------------------- the new machines (roster 2026-10-17)

-- Arched slot + chute from the front face to the machine's output.
local function outputChute(m: Instance, id: string, x: number, bodyY: number, front: number)
	local outPos = outputFor(id)
	if not outPos then
		return
	end
	door(m, x, bodyY + 0.1, front, 1.2, 0.5, "Dark")
	chute(m, Vector3.new(x, bodyY + 0.4, front - 0.5), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.1)
end

-- Item machine attachments: Output (when it has one), Prompt, a generous Intake box.
local function itemPoints(ctx: Ctx, id: string, intake: Vector3, intakeSize: Vector3)
	local outPos = outputFor(id)
	if outPos then
		attach(ctx.base, "Output", CFrame.new(outPos))
	end
	local size = sizeOf(id)
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -(size[2] * GameConfig.CellSize / 2) + 0.8))
	local a = attach(ctx.base, "Intake", CFrame.new(intake))
	a:SetAttribute("IntakeSize", intakeSize)
end

-- Sockets on the top corners of a soft box and on the floor corners of the footprint.
local function boxSockets(ctx: Ctx, hx: number, hz: number, w: number, d: number, top: number, size: number)
	local s = sizeOf(ctx.model.Name)
	local fw, fd = s[1] * GameConfig.CellSize / 2 - 0.45, s[2] * GameConfig.CellSize / 2 - 0.45
	socket(ctx, Vector3.new(hx - w / 2 + 0.7, top - 0.3, hz - d / 2 + 0.7), out(-1, -1), size * 1.2)
	socket(ctx, Vector3.new(hx + w / 2 - 0.7, top - 0.3, hz + d / 2 - 0.7), out(1, 1), size * 1.1)
	socket(ctx, Vector3.new(-fw, FLOOR, -fd), out(-1, -1, 0.8), size)
	socket(ctx, Vector3.new(fw, FLOOR, fd), out(1, 1, 0.8), size)
	socket(ctx, Vector3.new(hx + w / 2 - 0.7, top - 0.3, hz - d / 2 + 0.7), out(1, -1), size)
	socket(ctx, Vector3.new(-fw, FLOOR, fd), out(-1, 1, 0.8), size * 0.9)
	socket(ctx, Vector3.new(hx - w / 2 + 0.7, top - 0.3, hz + d / 2 - 0.7), out(-1, 1), size * 0.9)
	socket(ctx, Vector3.new(fw, FLOOR, -fd), out(1, -1, 0.8), size * 0.9)
end

-- A small glowing gem (diamond body, pointed top and bottom), `role` coloured, with a glowing core.
local function gem(m: Instance, center: Vector3, h: number, color: Color3)
	local w = h * 0.45
	local body = block(m, CFrame.new(center) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w, h * 0.4, w), "Gem", TINY, "Gem")
	body.Color = color
	for _, sy in { 1, -1 } do
		local tipH = h * 0.3
		local at = CFrame.new(center + Vector3.new(0, sy * (h * 0.2 + tipH / 2), 0)) * CFrame.Angles(0, math.pi / 4, 0)
		if sy < 0 then
			at = at * CFrame.Angles(math.pi, 0, 0)
		end
		local a = wedge(m, at * CFrame.new(0, 0, -w / 4), Vector3.new(w, tipH, w / 2), "Gem", TINY, "Gem")
		local b = wedge(m, at * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, tipH, w / 2), "Gem", TINY, "Gem")
		a.Color, b.Color = color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.1)
	end
	local core =
		block(m, CFrame.new(center) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.5, h * 0.42, w * 0.5), "Gem", TINY, "GemCore")
	core.Color = color:Lerp(WHITE, 0.4)
	core.Material = NEON
end

-- A star icon (two crossed squares) facing -Z at `center`.
local function star(m: Instance, center: Vector3, s: number, role: string)
	block(m, CFrame.new(center), Vector3.new(s, s, 0.06), role, TINY)
	block(m, CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s, s, 0.06), role, TINY)
end

-- A label on a flap's front face (SurfaceGui "FlapText", TextLabel "Text").
local function flapLabel(flap: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FlapText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.6
	gui.MaxDistance = 60
	gui.Parent = flap
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.86, 0.62)
	label.Position = UDim2.fromScale(0.07, 0.19)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = gui
end

--[[
	Iron Box (2x2): a sturdy soft box with a slate iron band and rivets; on
	the front a glass inspection bay (ShowPoint: the client stands a copy of
	the last sorted item there), a lit screen (Screen / ScreenGui with the
	Item and Counter labels), and two flaps hinged at their top edge (FlapKeep
	over a slide into a floor port to the Ore Pen, FlapSend over the chute to
	the output); a bowl intake on the lid. The client swings the flaps and
	fills the screen (MachineFxController, IronBoxService attributes).
]]
local function ironBox(): Ctx
	local ctx = newModel("IronBox")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0.15, 5.6, 3.6, 5.2, 0.9
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.6, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	rivets(body, Enum.NormalId.Right)
	local bandY = bodyY + 0.75
	block(m, CFrame.new(hx, bandY, hz + d / 2 + 0.05), Vector3.new(w - 2 * r, 0.55, 0.12), "Frame", TINY)
	for _, s in { -1, 1 } do
		block(m, CFrame.new(hx + s * (w / 2 + 0.05), bandY, hz), Vector3.new(0.12, 0.55, d - 2 * r), "Frame", TINY)
	end
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	-- glass inspection bay (front left): a slate frame standing out, dark inside, a warm lamp strip
	-- (high enough that its floor never hides the KEEP flap's label from in front)
	local wx, ww, wy0, wy1, dd, t = -0.95, 1.7, bodyY + 1.6, bodyY + 2.78, 0.8, 0.2
	local wh = wy1 - wy0
	local bayZ = front - dd / 2
	block(m, CFrame.new(wx, (wy0 + wy1) / 2, front - 0.03), Vector3.new(ww, wh, 0.06), "Dark", TINY, "BayBack")
	block(m, CFrame.new(wx, wy0 - t / 2, bayZ), Vector3.new(ww + 2 * t, t, dd), "Frame", SOLID, "BayFloor")
	block(m, CFrame.new(wx, wy1 + t / 2, bayZ), Vector3.new(ww + 2 * t, t, dd), "Frame", SOLID)
	for _, s in { -1, 1 } do
		block(m, CFrame.new(wx + s * (ww / 2 + t / 2), (wy0 + wy1) / 2, bayZ), Vector3.new(t, wh, dd), "Frame", SOLID)
	end
	block(m, CFrame.new(wx, wy1 - 0.05, front - dd * 0.4), Vector3.new(ww - 0.3, 0.06, 0.16), "Hot", TINY, "InspectLamp")
	block(m, CFrame.new(wx, (wy0 + wy1) / 2, front - dd + 0.03), Vector3.new(ww, wh, 0.05), "Glass", TINY, "BayGlass")
	attach(ctx.base, "ShowPoint", CFrame.new(wx, wy0 - FLOOR / 2, bayZ + 0.05))
	-- the lit screen (front right) in a round-sided slate frame
	local sx, sw, sy, sh = 1.05, 1.5, bodyY + 2.15, 0.95
	block(m, CFrame.new(sx, sy, front - 0.12), Vector3.new(sw + 0.1, sh + 0.3, 0.24), "Frame", TINY)
	for _, s in { -1, 1 } do
		cyl(m, Vector3.new(sx + s * (sw / 2 + 0.05), sy, front - 0.12), UP, sh + 0.3, 0.3, "Frame", TINY)
	end
	local screen = block(m, CFrame.new(sx, sy, front - 0.26), Vector3.new(sw, sh, 0.05), "ScreenGlow", TINY, "Screen")
	screen.Color = rgb(30, 70, 70)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Parent = screen
	type ScreenLine = { Name: string, Text: string, Y: number, H: number }
	local lines: { ScreenLine } = {
		{ Name = "Item", Text = "READY", Y = 0.1, H = 0.5 },
		{ Name = "Counter", Text = "KEPT 0 · SENT 0", Y = 0.62, H = 0.28 },
	}
	for _, spec in lines do
		local label = Instance.new("TextLabel")
		label.Name = spec.Name
		label.Text = spec.Text
		label.Position = UDim2.fromScale(0.06, spec.Y)
		label.Size = UDim2.fromScale(0.88, spec.H)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.TextColor3 = P.ScreenGlow
		label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
		label.Parent = gui
	end
	-- two flaps hinged at their top edge over dark openings: KEEP (to the pen) and SEND (to the output)
	local outPos = outputFor("IronBox") :: Vector3
	local flapY0, flapH, flapW = bodyY + 0.12, 0.8, 1.3
	local flapZ = front - 0.12
	local flaps: { { x: number, name: string, text: string, role: string, color: Color3 } } = {
		{ x = wx, name = "FlapKeep", text = "KEEP", role = "Lamp", color = rgb(255, 255, 255) },
		{ x = 1.2, name = "FlapSend", text = "SEND", role = "Trim", color = P.Dark },
	}
	for _, f in flaps do
		block(m, CFrame.new(f.x, flapY0 + flapH / 2, front - 0.03), Vector3.new(flapW + 0.1, flapH + 0.1, 0.08), "Dark", TINY)
		cyl(m, Vector3.new(f.x, flapY0 + flapH + 0.08, flapZ), XA, flapW + 0.2, 0.2, "Frame", TINY)
		local flap = block(m, CFrame.new(f.x, flapY0 + flapH / 2, flapZ), Vector3.new(flapW - 0.06, flapH, 0.1), f.role, TINY, f.name)
		if f.role == "Lamp" then
			flap.Color = rgb(70, 170, 110)
		end
		flapLabel(flap, f.text, f.color)
	end
	chute(m, Vector3.new(1.2, flapY0 + 0.05, front - 0.45), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.1)
	-- the keep slide down into a round port in front of the plinth
	local portZ = front - 0.95
	local slideTop, slideEnd = Vector3.new(wx, flapY0 + 0.02, front - 0.35), Vector3.new(wx, FLOOR + 0.12, portZ + 0.15)
	block(
		m,
		CFrame.lookAt((slideTop + slideEnd) / 2, slideEnd),
		Vector3.new(1.1, 0.12, (slideEnd - slideTop).Magnitude),
		"Dark",
		PROP,
		"KeepSlide"
	)
	cyl(m, Vector3.new(wx, FLOOR + 0.06, portZ), UP, 0.12, 1.15, "Trim", PROP, "PenPort")
	cyl(m, Vector3.new(wx, FLOOR + 0.13, portZ), UP, 0.04, 0.8, "Dark", TINY)
	local rim = bowl(m, Vector3.new(hx, lidTop, hz + 0.4), 2.4, 0.4)

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(hx, rim + 0.02, hz + 0.4 + 1.6), UP, 0.9, true)
	itemPoints(ctx, "IronBox", Vector3.new(0, 4.6, 0.4), Vector3.new(6, 6.6, 6))
	return ctx
end

--[[
	Sorter (1x1): a glowing pill base with a belt on it running through a
	cute rounded gate (cream posts, a round cream top with orange caps, a
	glowing scan bar under it and rarity lights on top), an orange flipper,
	exits to the left and right with glowing arrows.
]]
local function sorter(): Ctx
	local ctx = newModel("Sorter")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0), 3.7, 0.3, 3.7, 0.7, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.15, 0), 3.7, 3.7, 0.7, 0.1)
	local belt = block(m, CFrame.new(0, BELT_TOP - 0.12, 0), Vector3.new(BELT_W, 0.24, 3.6), "Rubber", SOLID, "Belt")
	beltPaint(belt, 3.6, false)
	local gz, gateY = 0.7, 3.0
	for _, side in { -1, 1 } do
		pillSlab(m, Vector3.new(side * 1.6, FLOOR, gz), 0.75, gateY - FLOOR, 1.1, 0.3, "Body")
		cyl(m, Vector3.new(side * 1.6, FLOOR + 0.3, gz), UP, 0.3, 1.2, "Trim", TINY)
		chute(m, Vector3.new(side * 1.3, BELT_TOP + 0.05, -1.0), Vector3.new(side * 2.5, BELT_TOP - 0.25, -1.0), 1.1)
		wedge(
			m,
			CFrame.new(side * 0.85, BELT_TOP + 0.02, -1.0) * CFrame.Angles(0, -side * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(0.04, 0.45, 0.5),
			"Neon",
			TINY,
			"Arrow"
		)
	end
	cyl(m, Vector3.new(0, gateY, gz), XA, 3.4, 1.15, "Body", SOLID, "Gate")
	for _, side in { -1, 1 } do
		cyl(m, Vector3.new(side * 1.75, gateY, gz), XA, 0.3, 1.25, "Trim", TINY)
	end
	block(m, CFrame.new(0, gateY - 0.62, gz), Vector3.new(2.6, 0.08, 0.3), "Plasma", TINY, "ScanBar")
	local rarity = { rgb(225, 225, 225), rgb(110, 220, 110), rgb(90, 160, 255), rgb(190, 110, 255), rgb(255, 196, 60) }
	for i, c in rarity do
		local dot = ball(m, Vector3.new(-1.0 + (i - 1) * 0.5, gateY + 0.6, gz), 0.3, "Lamp", TINY, "RarityLamp")
		dot.Color, dot.Material = c, NEON
	end
	cyl(m, Vector3.new(0, BELT_TOP + 0.3, -1.0), UP, 0.6, 0.45, "Frame", TINY)
	block(
		m,
		CFrame.new(0, BELT_TOP + 0.3, -1.0) * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(0, 0, -0.6),
		Vector3.new(0.22, 0.45, 1.2),
		"Trim",
		TINY,
		"Flipper"
	)

	for _, sx in { -1, 1 } do
		socket(ctx, Vector3.new(sx * 1.6, FLOOR + 0.3, 1.65), out(sx, 1, 0.7), 0.7)
	end
	socket(ctx, Vector3.new(0, gateY + 0.5, gz + 0.45), out(0, 1, 0.3), 0.7, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 1.5, 0))
	local a = attach(ctx.base, "Intake", CFrame.new(0, 1.2, 1.2))
	a:SetAttribute("IntakeSize", Vector3.new(3, 1.6, 1.4))
	return ctx
end

--[[
	Polisher (2x2): a soft body with a turntable on top (slate, orange rim,
	pink felt), an arm from the back holding the spinning pink polishing
	wheel over it, sparkles, a star icon over the output slot, a side screen.
]]
local function polisher(): Ctx
	local ctx = newModel("Polisher")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0.1, 5.6, 3.0, 5.2, 0.9
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.6, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	local top = bodyY + h
	local front = hz - d / 2
	local tz = hz - 0.5
	cyl(m, Vector3.new(hx, top + 0.1, tz), UP, 0.5, 3.2, "Frame", SOLID, "Turntable")
	cyl(m, Vector3.new(hx, top + 0.3, tz), UP, 0.2, 3.4, "Trim", SOLID)
	cyl(m, Vector3.new(hx, top + 0.41, tz), UP, 0.04, 2.8, "Felt", TINY)
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "Sparkle"
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Rate = 5
	glint.Parent = m:FindFirstChild("Turntable") :: Instance
	-- the arm: a slate post at the back, a bend forward, the motor and the felt wheel
	local px, pz = hx, hz + d / 2 - 0.9
	local pd, pr = 0.7, 0.6
	local armY = top + 3.0
	pipe(m, Vector3.new(px, top - 0.2, pz), Vector3.new(px, armY - pr, pz), pd, { b = false })
	local p1 = bend(m, Vector3.new(px, armY - pr, pz), UP, -ZA, pd, pr)
	pipe(m, p1, Vector3.new(px, armY, tz + 0.2), pd, { a = false })
	cyl(m, Vector3.new(hx, armY - 0.2, tz), UP, 1.0, 1.1, "Body", PROP, "Motor")
	cyl(m, Vector3.new(hx, armY - 0.75, tz), UP, 0.14, 1.2, "Trim", TINY)
	cyl(m, Vector3.new(hx, armY - 1.0, tz), UP, 0.4, 2.3, "Felt", PROP, "Wheel")
	star(m, Vector3.new(1.4, bodyY + 1.95, front - 0.08), 0.55, "Gold")
	outputChute(m, "Polisher", 1.4, bodyY, front)
	screenPanel(m, CFrame.new(hx + w / 2 + 0.22, bodyY, hz + 0.6) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.5, P.Felt)

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(hx, armY + 0.35, pz - 0.4), out(0, -1, 0.3), 0.9, true)
	itemPoints(ctx, "Polisher", Vector3.new(0, 4.4, -0.4), Vector3.new(6, 6, 6))
	return ctx
end

--[[
	Brick Furnace (2x2, the normal furnace between the Clay and the Blast
	Furnace): a soft body under a big terracotta dome with an orange band, a
	little fat chimney on the dome, the arched glowing door, a bowl intake on
	the side shelf, a chute to the output.
]]
local function brickFurnace(): Ctx
	local ctx = newModel("BrickFurnace")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, -0.1, 5.8, 3.3, 5.4, 0.9
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.6, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	local top = bodyY + h
	local domeD = 5.0
	local domeC = Vector3.new(hx, top - 0.8, hz + 0.1)
	ball(m, domeC, domeD, "Brick", SOLID, "Dome")
	cyl(m, Vector3.new(hx, top + 0.05, hz + 0.1), UP, 0.35, domeD + 0.1, "Trim", SOLID)
	local domeTop = domeC.Y + domeD / 2
	chimney(m, Vector3.new(hx + 0.6, domeTop - 0.5, hz + 0.6), 1.1, 2.3, 2)
	local front = hz - d / 2
	local doorX = 0.3
	door(m, doorX, bodyY + 0.15, front, 2.1, 0.9, "Glow", "Glow")
	local outPos = outputFor("BrickFurnace") :: Vector3
	chute(m, Vector3.new(doorX, bodyY + 0.45, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.3)
	-- side shelf with the bowl intake on the left
	pillSlab(m, Vector3.new(hx - w / 2 - 0.2, bodyY + 1.6, hz + 0.6), 1.4, 0.3, 2.4, 0.4, "Frame")
	local rim = bowl(m, Vector3.new(hx - w / 2 - 0.2, bodyY + 1.9, hz + 0.6), 1.6, 0.3)
	screenPanel(m, CFrame.new(hx + w / 2 + 0.22, bodyY, hz + 0.8) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.5)

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(hx - w / 2 - 0.2, rim + 0.02, hz + 0.6 + 0.9), out(-1, 0.5, 0.6), 0.8)
	socket(ctx, Vector3.new(hx + 0.6, domeTop + 2.0, hz + 0.6), UP, 1.0, true)
	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return ctx
end

--[[
	Plasma Furnace (2x2, end game): a soft body with a purple glowing arched
	door, a glass sphere on the lid with a glowing plasma ball and two orbit
	rings, two tesla coils with cyan glowing tops, purple glowing strips.
]]
local function plasmaFurnace(): Ctx
	local ctx = newModel("PlasmaFurnace")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, -0.1, 5.8, 3.6, 5.4, 1.0
	pillSlab(m, Vector3.new(hx, FLOOR, hz), w + 0.6, 0.6, d + 0.6, 0.7, "Frame")
	glowStrips(m, Vector3.new(hx, FLOOR + 0.3, hz), w + 0.6, d + 0.6, 0.7, 0.16, "Plasma")
	local bodyY = FLOOR + 0.6
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	-- purple door
	local doorX = 0.3
	arch(m, Vector3.new(doorX, bodyY + 0.15, front - 0.2), 2.8, 1.1, 0.4, "Trim", SOLID)
	arch(m, Vector3.new(doorX, bodyY + 0.15, front - 0.42), 2.3, 1.1, 0.06, "Dark", TINY)
	local glow = arch(m, Vector3.new(doorX, bodyY + 0.15, front - 0.46), 2.1, 1.1, 0.06, "Plasma", TINY, "Glow")
	local core = arch(m, Vector3.new(doorX, bodyY + 0.4, front - 0.5), 1.15, 0.8, 0.04, "Plasma", TINY, "GlowCore")
	core.Color = P.Plasma:Lerp(WHITE, 0.45)
	light(glow, P.Plasma, 8, 0.8)
	local outPos = outputFor("PlasmaFurnace") :: Vector3
	chute(m, Vector3.new(doorX, bodyY + 0.45, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.3)
	-- glass sphere with the plasma ball
	local sx, sz = hx - 0.6, hz + 0.2
	cyl(m, Vector3.new(sx, lidTop + 0.25, sz), UP, 0.5, 2.6, "Frame", SOLID)
	cyl(m, Vector3.new(sx, lidTop + 0.45, sz), UP, 0.14, 2.7, "Plasma", TINY)
	local sc = Vector3.new(sx, lidTop + 0.5 + 1.25, sz)
	ball(m, sc, 2.5, "Glass", TINY, "Chamber")
	local plasma = ball(m, sc, 1.3, "Plasma", TINY, "PlasmaBall")
	light(plasma, P.Plasma, 10, 1.0)
	for _, a in { 0.45, -0.45 } do
		local ring = Geo.make("Part", {
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(sc) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(a, 0, 0),
			Size = Vector3.new(0.08, 2.0, 2.0),
		}, m)
		style(ring, "Cyan", TINY, "Orbit")
	end
	-- tesla coils at the back corners of the lid
	for _, cx in { hx + 1.7, hx - 2.2 } do
		local cz = hz + 1.6
		cyl(m, Vector3.new(cx, lidTop + 0.2, cz), UP, 0.4, 0.9, "Frame", SOLID)
		cyl(m, Vector3.new(cx, lidTop + 1.2, cz), UP, 1.8, 0.35, "Pipe", PROP)
		for i = 1, 3 do
			cyl(m, Vector3.new(cx, lidTop + 0.5 + i * 0.45, cz), UP, 0.12, 0.7 - i * 0.08, "Trim", TINY)
		end
		ball(m, Vector3.new(cx, lidTop + 2.25, cz), 0.55, "Cyan", TINY, "CoilTop")
	end

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(sx + 1.0, lidTop + 0.5, sz - 1.0), out(1, -1, 0.6), 0.9, true)
	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return ctx
end

--[[
	Alloy Furnace (3x2): a wide soft body with two bowl hoppers on the lid
	(an orange and a cyan rim, two different ingots) feeding a glass mixing
	column with molten metal and a cyan coil, a wide arched glowing door, a
	fat chimney, screens on both sides.
]]
local function alloyFurnace(): Ctx
	local ctx = newModel("AlloyFurnace")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0, 10.0, 4.0, 5.8, 1.0
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.8, d + 0.8, 0.6, 0.8)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.8, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	door(m, 0, bodyY + 0.15, front, 2.8, 1.0, "Glow", "Glow")
	local outPos = outputFor("AlloyFurnace") :: Vector3
	chute(m, Vector3.new(0, bodyY + 0.45, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.45), 1.4)
	-- two hoppers, the mixing column between them
	local rims = {}
	for i, bx in { -3.0, 3.0 } do
		rims[i] = bowl(m, Vector3.new(bx, lidTop, hz - 0.4), 2.4, 0.5)
	end
	local colY0, colY1 = lidTop + 0.3, lidTop + 2.6
	cyl(m, Vector3.new(0, lidTop + 0.15, hz - 0.4), UP, 0.3, 1.6, "Frame", SOLID)
	pipe(m, Vector3.new(0, colY0, hz - 0.4), Vector3.new(0, colY1, hz - 0.4), 1.1, { fluid = "Molten" })
	for i = 1, 4 do
		local ring = Geo.make("Part", {
			Shape = Enum.PartType.Cylinder,
			CFrame = along(Vector3.new(0, colY0 + 0.3 + i * 0.4, hz - 0.4), UP) * CFrame.Angles(0, 0, math.rad(22)),
			Size = Vector3.new(0.08, 0.95, 0.95),
		}, m)
		style(ring, "Cyan", TINY, "Coil")
	end
	cyl(m, Vector3.new(0, colY1 + 0.2, hz - 0.4), UP, 0.4, 1.5, "Frame", SOLID)
	for _, side in { -1, 1 } do
		local from = Vector3.new(side * 1.85, rims[1] - 0.45, hz - 0.4)
		pipe(m, from, Vector3.new(side * 0.55, colY1 - 0.4, hz - 0.4), 0.45, { a = false })
	end
	-- the right hopper's rim in cyan: the second metal
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Kit") == "Trim" then
			local flat = Vector3.new(part.CFrame.Position.X - 3.0, 0, part.CFrame.Position.Z - (hz - 0.4))
			if flat.Magnitude < 1.6 and part.CFrame.Position.Y > lidTop + 0.3 then
				part.Color = P.Cyan:Lerp(BLACK, 0.1)
				part:SetAttribute("Kit", "Accent")
			end
		end
	end
	chimney(m, Vector3.new(3.3, lidTop, hz + 1.7), 1.5, 3.4, 3)
	screenPanel(m, CFrame.new(hx - w / 2 - 0.25, bodyY, hz) * CFrame.Angles(0, -math.pi / 2, 0), 1.6, 1.6)
	screenPanel(m, CFrame.new(hx + w / 2 + 0.25, bodyY, hz) * CFrame.Angles(0, math.pi / 2, 0), 1.6, 1.6, P.Cyan)

	boxSockets(ctx, hx, hz, w, d, top, 1.2)
	socket(ctx, Vector3.new(0, colY1 + 0.42, hz - 0.4), UP, 1.0, true)
	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 5, 0))
	intake:SetAttribute("IntakeSize", Vector3.new(10, 9, 6))
	return ctx
end

--[[
	Crystal Extractor (2x2): a soft body with a glass chamber on the lid in
	which a glowing gem floats between two laser emitters, a small bowl
	intake at the back, a shard tray and chute at the front, a side screen.
]]
local function crystalExtractor(): Ctx
	local ctx = newModel("CrystalExtractor")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0.1, 5.6, 3.2, 5.2, 0.9
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.6, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	local cx, cz = hx - 0.3, hz - 0.3
	cyl(m, Vector3.new(cx, lidTop + 0.25, cz), UP, 0.5, 3.0, "Frame", SOLID)
	cyl(m, Vector3.new(cx, lidTop + 0.45, cz), UP, 0.14, 3.1, "Neon", TINY)
	local chamberH = 2.6
	cyl(m, Vector3.new(cx, lidTop + 0.5 + chamberH / 2, cz), UP, chamberH, 2.5, "Glass", TINY, "Chamber")
	cyl(m, Vector3.new(cx, lidTop + 0.5 + chamberH + 0.2, cz), UP, 0.4, 2.9, "Frame", SOLID)
	cyl(m, Vector3.new(cx, lidTop + 0.5 + chamberH + 0.42, cz), UP, 0.06, 1.2, "Trim", TINY)
	local gc = Vector3.new(cx, lidTop + 0.5 + chamberH / 2, cz)
	gem(m, gc, 1.5, rgb(90, 214, 255))
	local gemLight = m:FindFirstChild("GemCore")
	if gemLight then
		light(gemLight, rgb(90, 214, 255), 8, 0.8)
	end
	for _, side in { -1, 1 } do
		local e = gc + Vector3.new(side * 1.05, -0.7, 0)
		cyl(m, e, UP, 0.3, 0.35, "Frame", TINY)
		rod(m, e + Vector3.new(0, 0.15, 0), gc + Vector3.new(side * 0.25, -0.15, 0), 0.06, "Cyan", TINY, "Laser")
	end
	local rim = bowl(m, Vector3.new(hx + 1.7, lidTop, hz + 1.4), 1.6, 0.3)
	-- shard tray at the front: a slate tray with a few small shards
	outputChute(m, "CrystalExtractor", 1.4, bodyY, front)
	pillSlab(m, Vector3.new(-1.3, bodyY + 0.6, front - 0.55), 1.8, 0.3, 1.0, 0.3, "Frame")
	for i, x in { -1.8, -1.3, -0.85 } do
		local sh = block(
			m,
			CFrame.new(x, bodyY + 1.05, front - 0.55) * CFrame.Angles(0, 0.6 * i, 0.3 - 0.25 * i),
			Vector3.new(0.22, 0.5, 0.22),
			"Gem",
			TINY,
			"Shard"
		)
		sh.Color = rgb(90, 214, 255):Lerp(WHITE, 0.2)
	end
	screenPanel(m, CFrame.new(hx + w / 2 + 0.22, bodyY, hz - 0.6) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.5, P.Water)

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(hx + 1.7, rim + 0.02, hz + 1.4 + 0.6), out(0.6, 1, 0.5), 0.7)
	socket(ctx, Vector3.new(cx, lidTop + 0.5 + chamberH + 0.48, cz), UP, 1.0, true)
	itemPoints(ctx, "CrystalExtractor", Vector3.new(0, 4.6, 0.6), Vector3.new(6, 6.6, 6))
	return ctx
end

--[[
	Restoration Table (2x2): a soft cream table with a slate top, a glass bell
	jar on a turntable with a golden artifact inside, a magnifier lamp arm with
	a glowing bulb, brushes, a screen, a small output tray.
]]
local function restorationTable(): Ctx
	local ctx = newModel("RestorationTable")
	local m = ctx.model
	local hx, hz, w, h, d = 0, 0.2, 6.2, 2.6, 5.0
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.5, d + 0.5, 0.5, 0.6)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, 0.6, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.05, hz), w + 0.5, 0.35, d + 0.4, 0.5, "Frame", SOLID, "Bench")
	local deck = top + 0.3
	local front = hz - d / 2
	-- turntable, artifact, bell jar
	local jx, jz = hx - 0.6, hz - 0.2
	cyl(m, Vector3.new(jx, deck + 0.2, jz), UP, 0.4, 2.2, "Frame", SOLID, "Turntable")
	cyl(m, Vector3.new(jx, deck + 0.42, jz), UP, 0.06, 2.3, "Trim", TINY)
	local vy = deck + 0.45
	for _, seg in { { 0.35, 0.55 }, { 0.6, 0.9 }, { 0.3, 0.5 }, { 0.15, 0.65 } } do
		local hgt, dia = seg[1], seg[2]
		cyl(m, Vector3.new(jx, vy + hgt / 2, jz), UP, hgt, dia, "Gold", TINY, "Artifact")
		vy += hgt
	end
	cyl(m, Vector3.new(jx, deck + 0.45 + 0.9, jz), UP, 1.8, 1.9, "Glass", TINY, "BellJar")
	ball(m, Vector3.new(jx, deck + 0.45 + 1.8, jz), 1.9, "Glass", TINY, "BellJar")
	ball(m, Vector3.new(jx, deck + 0.45 + 2.82, jz), 0.36, "Trim", TINY)
	-- magnifier lamp arm
	local ax, az = hx + 2.2, hz + 1.6
	cyl(m, Vector3.new(ax, deck + 0.15, az), UP, 0.3, 0.9, "Frame", TINY)
	local j1 = Vector3.new(ax, deck + 2.3, az)
	rod(m, Vector3.new(ax, deck + 0.3, az), j1, 0.2, "Trim", TINY)
	ball(m, j1, 0.34, "Frame", TINY)
	local head = Vector3.new(ax - 1.2, deck + 2.0, az - 1.3)
	rod(m, j1, head, 0.18, "Trim", TINY)
	local lensFrame = CFrame.new(head) * CFrame.Angles(math.rad(-50), 0, 0)
	local ringPart = Geo.make(
		"Part",
		{ Shape = Enum.PartType.Cylinder, CFrame = lensFrame * CFrame.Angles(0, 0, math.pi / 2), Size = Vector3.new(0.2, 1.3, 1.3) },
		m
	)
	style(ringPart, "Trim", TINY, "Magnifier")
	local lens = Geo.make(
		"Part",
		{ Shape = Enum.PartType.Cylinder, CFrame = lensFrame * CFrame.Angles(0, 0, math.pi / 2), Size = Vector3.new(0.24, 1.05, 1.05) },
		m
	)
	style(lens, "Glass", TINY, "Lens")
	local bulb = ball(m, head + Vector3.new(0.5, 0.45, 0.2), 0.3, "Hot", TINY, "LampBulb")
	light(bulb, P.Hot, 6, 0.6)
	-- brushes and a little hammer on the left
	block(m, CFrame.new(hx - 2.4, deck + 0.12, hz + 0.6), Vector3.new(0.9, 0.24, 0.3), "Trim", TINY)
	block(m, CFrame.new(hx - 2.4, deck + 0.3, hz + 0.6), Vector3.new(0.7, 0.18, 0.24), "Body", TINY)
	block(m, CFrame.new(hx - 2.3, deck + 0.1, hz - 0.5) * CFrame.Angles(0, 0.4, 0), Vector3.new(0.18, 0.18, 1.0), "Trim", TINY)
	block(m, CFrame.new(hx - 2.12, deck + 0.18, hz - 0.95) * CFrame.Angles(0, 0.4, 0), Vector3.new(0.6, 0.32, 0.32), "Frame", TINY)
	screenPanel(m, CFrame.new(hx + 0.4, deck, hz + 2.0), 1.6, 1.6, P.Gold)
	local outPos = outputFor("RestorationTable") :: Vector3
	outputChute(m, "RestorationTable", 1.5, bodyY, front)

	boxSockets(ctx, hx, hz, w, d, top + 0.3, 0.9)
	socket(ctx, Vector3.new(hx + 0.4, deck + 1.65, hz + 2.05), UP, 0.8, true)
	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, deck + 0.6, front - 0.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(jx, deck + 1, jz))
	intake:SetAttribute("IntakeSize", Vector3.new(4, 3, 4))
	return ctx
end

--[[
	Sell Box (2x2): a soft box with a big gold coin and a glowing star on the
	front, a gold-rimmed bowl intake, a coin sign on a post, a little stack
	of coins. No output: what goes in is sold to Tobin.
]]
local function sellBox(): Ctx
	local ctx = newModel("SellBox")
	local m = ctx.model
	local hx, hz, w, h, d, r = 0, 0.2, 5.4, 3.6, 5.0, 1.0
	local bodyY = plinth(m, Vector3.new(hx, FLOOR, hz), w + 0.6, d + 0.6, 0.6, 0.7)
	local body = softBox(m, Vector3.new(hx, bodyY, hz), w, h, d, r, "Body", "Body")
	rivets(body, Enum.NormalId.Left)
	rivets(body, Enum.NormalId.Right)
	local top = bodyY + h
	pillSlab(m, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	local front = hz - d / 2
	local cc = Vector3.new(hx, bodyY + 1.45, front - 0.05)
	cyl(m, cc + Vector3.new(0, 0, 0.02), ZA, 0.3, 2.5, "Gold", TINY, "Coin")
	cyl(m, cc + Vector3.new(0, 0, -0.14), ZA, 0.06, 2.0, "Trim", TINY)
	star(m, cc + Vector3.new(0, 0, -0.2), 0.8, "Hot")
	local rim = bowl(m, Vector3.new(hx, lidTop, hz + 0.2), 2.4, 0.4)
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Kit") == "Trim" and part.CFrame.Position.Y > lidTop + 0.4 then
			part.Color = P.Gold
			part:SetAttribute("Kit", "Gold")
		end
	end
	-- coin sign on a post at the back right
	local px, pz = hx + w / 2 - 0.4, hz + d / 2 - 0.2
	cyl(m, Vector3.new(px, lidTop + 1.0, pz), UP, 2.6, 0.3, "Frame", PROP)
	local sign = Vector3.new(px, lidTop + 2.6, pz)
	cyl(m, sign, ZA, 0.3, 1.5, "Gold", PROP, "SignCoin")
	cyl(m, sign + Vector3.new(0, 0, -0.17), ZA, 0.05, 1.1, "Trim", TINY)
	-- a little coin stack by the front
	for i = 0, 2 do
		cyl(m, Vector3.new(-1.9 + i * 0.12, bodyY + 0.1 + i * 0.16, front - 0.7), UP, 0.14, 0.75, "Gold", TINY)
	end

	boxSockets(ctx, hx, hz, w, d, top, 1.0)
	socket(ctx, Vector3.new(hx, rim + 0.02, hz + 0.2 - 1.6), out(0, -1, 0.3), 0.9, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.6, 0.2))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return ctx
end

--[[
	Splitter (1x1): a round slate platform (belt-dark top) on a glowing pill
	base, an orange flipper on a pivot that sends items left and right
	(glowing arrows), exits on both sides.
]]
local function splitter(): Ctx
	local ctx = newModel("Splitter")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0), 3.7, 0.3, 3.7, 0.7, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.15, 0), 3.7, 3.7, 0.7, 0.1)
	cyl(m, Vector3.new(0, 0.6, 0), UP, 0.4, 3.4, "Frame", SOLID, "Platform")
	cyl(m, Vector3.new(0, 0.82, 0), UP, 0.04, 3.0, "Rubber", TINY, "Belt")
	cyl(m, Vector3.new(0, 0.78, 0), UP, 0.1, 3.5, "Trim", TINY)
	cyl(m, Vector3.new(0, 1.1, 0), UP, 0.6, 0.55, "Frame", TINY, "Pivot")
	ball(m, Vector3.new(0, 1.45, 0), 0.5, "Trim", TINY)
	block(
		m,
		CFrame.new(0, 1.05, 0) * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, -0.8),
		Vector3.new(0.24, 0.45, 1.6),
		"Trim",
		TINY,
		"Flipper"
	)
	for _, side in { -1, 1 } do
		chute(m, Vector3.new(side * 1.4, BELT_TOP + 0.02, 0), Vector3.new(side * 2.5, BELT_TOP - 0.25, 0), 1.2)
		for k = -1, 1, 2 do
			wedge(
				m,
				CFrame.new(side * 0.95, 0.86, k * 0.18) * CFrame.Angles(0, -side * math.pi / 2, 0) * CFrame.Angles(0, 0, -k * math.pi / 2),
				Vector3.new(0.04, 0.36, 0.5),
				"Neon",
				TINY,
				"Arrow"
			)
		end
	end
	for _, sz in { -1, 1 } do
		socket(ctx, Vector3.new(1.7, FLOOR, sz * 1.7), out(1, sz, 0.8), 0.7)
	end
	attach(ctx.base, "Prompt", CFrame.new(0, 1.5, 0))
	local a = attach(ctx.base, "Intake", CFrame.new(0, 1.2, 1.4))
	a:SetAttribute("IntakeSize", Vector3.new(3, 1.6, 1.2))
	return ctx
end

--[[
	Robot Arm (1x1): a glowing pill base, a cream pedestal, the orange arm
	with slate ball joints and a claw, a little screen.
]]
local function robotArmMachine(): Ctx
	local ctx = newModel("RobotArm")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0.2), 3.6, 0.35, 3.2, 0.8, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.18, 0.2), 3.6, 3.2, 0.8, 0.1)
	cyl(m, Vector3.new(0, FLOOR + 0.75, 0.4), UP, 0.8, 1.8, "Body", SOLID, "Pedestal")
	robotArm(m, Vector3.new(0, FLOOR + 1.15, 0.4), Vector3.new(0.5, FLOOR + 4.4, 0.1), Vector3.new(0.1, FLOOR + 3.4, -1.4), 1.3)
	screenPanel(m, CFrame.new(1.3, FLOOR + 0.35, 1.45), 0.9, 1.0)
	for _, sx in { -1, 1 } do
		socket(ctx, Vector3.new(sx * 1.55, FLOOR, -1.6), out(sx, -1, 0.8), 0.7)
	end
	socket(ctx, Vector3.new(-1.4, FLOOR + 0.35, 1.5), out(-1, 1, 0.6), 0.6, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 1.5, -1.2))
	return ctx
end

--[[
	Solar Panel (2x2): a tilted glossy blue panel (painted cells) with a round
	cream frame on a slate post and an orange bracket, a battery box with a
	glowing charge bar.
]]
local function solarPanel(): Ctx
	local ctx = newModel("SolarPanel")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0), 6.4, 0.4, 6.4, 1.0, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.2, 0), 6.4, 6.4, 1.0, 0.12)
	local postTop = FLOOR + 3.0
	cyl(m, Vector3.new(0, FLOOR + 0.3, 0.4), UP, 0.3, 1.4, "Trim", SOLID)
	cyl(m, Vector3.new(0, (FLOOR + postTop) / 2, 0.4), UP, postTop - FLOOR, 0.7, "Frame", SOLID)
	cyl(m, Vector3.new(0, postTop, 0.4), XA, 2.4, 0.55, "Trim", PROP)
	local tiltCf = CFrame.new(0, postTop + 0.35, 0.4) * CFrame.Angles(math.rad(-28), 0, 0)
	local pw, pd = 6.6, 4.6
	local panel = block(m, tiltCf, Vector3.new(pw, 0.22, pd), "Panel", SOLID, "Panel")
	local cells: { Paint } = {}
	for i = 1, 5 do
		table.insert(cells, { x = i / 6 - 0.004, y = 0, w = 0.008, h = 1, color = rgb(120, 170, 240) })
	end
	for i = 1, 3 do
		table.insert(cells, { x = 0, y = i / 4 - 0.006, w = 1, h = 0.012, color = rgb(120, 170, 240) })
	end
	paint(panel, Enum.NormalId.Top, cells, "Cells")
	for _, sz in { -1, 1 } do
		cyl(m, (tiltCf * CFrame.new(0, 0, sz * pd / 2)).Position, tiltCf.RightVector, pw, 0.32, "Body", TINY)
	end
	for _, sx in { -1, 1 } do
		cyl(m, (tiltCf * CFrame.new(sx * pw / 2, 0, 0)).Position, tiltCf.LookVector, pd, 0.32, "Body", TINY)
	end
	pillSlab(m, Vector3.new(-2.1, FLOOR + 0.4, 2.0), 1.6, 1.2, 1.1, 0.3, "Body")
	local bar = block(m, CFrame.new(-2.1, FLOOR + 1.0, 2.0 - 0.58), Vector3.new(1.0, 0.22, 0.05), "ScreenGlow", TINY, "Charge")
	bar.Color = P.Green
	for _, sx in { -1, 1 } do
		socket(ctx, Vector3.new(sx * 2.9, FLOOR + 0.4, -2.9), out(sx, -1, 0.7), 0.9)
	end
	socket(ctx, Vector3.new(2.9, FLOOR + 0.4, 2.9), out(1, 1, 0.7), 0.9)
	socket(ctx, Vector3.new(-2.9, FLOOR + 0.4, 2.9), out(-1, 1, 0.7), 0.8)
	socket(ctx, Vector3.new(-2.1, FLOOR + 1.62, 2.2), UP, 0.7, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 2.0, -3.4))
	return ctx
end

--[[
	Wind Turbine (2x2): a glowing pill base, a two-step cream tower with an
	orange band, a nacelle with an orange hub (Rotor) and three cream blades
	with orange tips (Blade, the client can spin them), a battery box.
]]
local function windTurbine(): Ctx
	local ctx = newModel("WindTurbine")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0), 6.0, 0.5, 6.0, 1.2, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.25, 0), 6.0, 6.0, 1.2, 0.12)
	local y0 = FLOOR + 0.5
	cyl(m, Vector3.new(0, y0 + 0.3, 0.6), UP, 0.6, 2.4, "Trim", SOLID)
	cyl(m, Vector3.new(0, y0 + 3.0, 0.6), UP, 5.2, 1.6, "Body", SOLID, "Tower")
	cyl(m, Vector3.new(0, y0 + 5.7, 0.6), UP, 0.35, 1.8, "Trim", TINY)
	cyl(m, Vector3.new(0, y0 + 8.2, 0.6), UP, 4.8, 1.15, "Body", SOLID)
	cyl(m, Vector3.new(0, y0 + 1.2, 0.6), UP, 0.14, 1.7, "Neon", TINY)
	local hubY = y0 + 11.0
	cyl(m, Vector3.new(0, hubY, 0.8), ZA, 2.6, 1.4, "Body", SOLID, "Nacelle")
	ball(m, Vector3.new(0, hubY, 2.1), 1.4, "Body", SOLID)
	cyl(m, Vector3.new(0, hubY, -0.55), ZA, 0.3, 1.2, "Frame", TINY)
	local hub = Vector3.new(0, hubY, -0.85)
	ball(m, hub, 1.0, "Trim", PROP, "Rotor")
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + 0.3
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local cf = CFrame.fromMatrix(hub + dir * 2.3, dir:Cross(ZA), dir, ZA) * CFrame.Angles(0, math.rad(12), 0)
		block(m, cf, Vector3.new(0.7, 3.8, 0.16), "Body", PROP, "Blade")
		block(m, cf * CFrame.new(0, 1.65, 0), Vector3.new(0.72, 0.5, 0.18), "Trim", TINY, "Blade")
	end
	pillSlab(m, Vector3.new(-1.9, y0, -1.9), 1.5, 1.1, 1.1, 0.3, "Body")
	local bar = block(m, CFrame.new(-1.9, y0 + 0.6, -1.9 - 0.58), Vector3.new(0.9, 0.2, 0.05), "ScreenGlow", TINY, "Charge")
	bar.Color = P.Green
	for _, c in { { -2.6, -2.6 }, { 2.6, -2.6 }, { 2.6, 2.6 }, { -2.6, 2.6 } } do
		socket(ctx, Vector3.new(c[1], y0, c[2]), out(if c[1] > 0 then 1 else -1, if c[2] > 0 then 1 else -1, 0.7), 0.9)
	end
	socket(ctx, Vector3.new(0, y0 + 5.9, 0.6 - 0.8), Vector3.new(0, 0.4, -1), 0.8, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 2.0, -3.4))
	return ctx
end

--[[
	Fusion Reactor (3x3, the strongest power): a round cream pedestal on a
	glowing pill base, a glass sphere with a glowing cyan core, a slate ring
	with orange joints round it, two tilted orbit rings, four pylons with
	glowing tips beaming energy into the core, a screen and a stack light.
]]
local function fusionReactor(): Ctx
	local ctx = newModel("FusionReactor")
	local m = ctx.model
	pillSlab(m, Vector3.new(0, FLOOR, 0), 11.2, 0.7, 11.2, 2.2, "Frame")
	glowStrips(m, Vector3.new(0, FLOOR + 0.35, 0), 11.2, 11.2, 2.2, 0.16, "Cyan")
	local y0 = FLOOR + 0.7
	cyl(m, Vector3.new(0, y0 + 0.6, 0), UP, 1.2, 7.0, "Body", SOLID, "Body")
	cyl(m, Vector3.new(0, y0 + 1.25, 0), UP, 0.3, 7.3, "Frame", SOLID)
	cyl(m, Vector3.new(0, y0 + 1.25, 0), UP, 0.1, 7.42, "Cyan", TINY)
	cyl(m, Vector3.new(0, y0 + 1.6, 0), UP, 0.5, 3.4, "Frame", SOLID)
	local core = Vector3.new(0, y0 + 3.9, 0)
	ball(m, core, 3.6, "Glass", TINY, "Chamber")
	local plasma = ball(m, core, 2.0, "Cyan", TINY, "Core")
	light(plasma, P.Cyan, 16, 1.2)
	local ringR = 2.7
	local pts = {}
	for i = 0, 7 do
		local a = i * math.pi / 4
		table.insert(pts, core + Vector3.new(math.cos(a) * ringR, 0, math.sin(a) * ringR))
	end
	for i = 1, 8 do
		rod(m, pts[i], pts[i % 8 + 1], 0.7, "Frame", PROP, "Ring")
		ball(m, pts[i], 0.85, "Trim", PROP)
	end
	for _, a in { 0.5, -0.5 } do
		local ring = Geo.make("Part", {
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(core) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(a, a * 0.6, 0),
			Size = Vector3.new(0.1, 4.6, 4.6),
		}, m)
		style(ring, "Cyan", TINY, "Orbit")
	end
	for _, c in { { -4.0, -4.0 }, { 4.0, -4.0 }, { 4.0, 4.0 }, { -4.0, 4.0 } } do
		local p = Vector3.new(c[1], y0, c[2])
		cyl(m, p + Vector3.new(0, 0.25, 0), UP, 0.5, 1.5, "Trim", SOLID)
		cyl(m, p + Vector3.new(0, 2.4, 0), UP, 4.0, 0.9, "Body", SOLID, "Pylon")
		cyl(m, p + Vector3.new(0, 3.6, 0), UP, 0.2, 1.0, "Trim", TINY)
		local tipP = p + Vector3.new(0, 4.75, 0)
		cyl(m, tipP - Vector3.new(0, 0.3, 0), UP, 0.3, 1.1, "Frame", TINY)
		ball(m, tipP, 0.7, "Cyan", TINY, "PylonTip")
		rod(m, tipP, core + (tipP - core).Unit * 1.9, 0.08, "Cyan", TINY, "Beam")
	end
	screenPanel(m, CFrame.new(0, y0, -4.9), 2.0, 1.6, P.Cyan)
	stackLight(m, Vector3.new(5.0, y0, -1.6), 1.0)
	for _, c in { { -2.4, -4.6 }, { 4.6, 2.4 }, { -4.6, 2.4 }, { 2.4, -4.6 }, { 0, 4.8 }, { 4.8, -0.6 } } do
		socket(ctx, Vector3.new(c[1], y0, c[2]), Vector3.new(c[1] * 0.12, 1, c[2] * 0.12), 1.2)
	end
	socket(ctx, Vector3.new(0, y0 + 1.86, -1.6), out(0, -1, 0.3), 1.2, true)
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -5.2))
	return ctx
end

--[[
	Power Pole (1x1): a slate pole on a round base with an orange band, a
	cross arm with orange insulators (attachments CableL / CableR for the
	cables) and a glowing green status ball on a cream cap.
]]
local function powerPole(): Ctx
	local ctx = newModel("PowerPole")
	local m = ctx.model
	cyl(m, Vector3.new(0, FLOOR + 0.2, 0), UP, 0.4, 1.5, "Frame", SOLID)
	cyl(m, Vector3.new(0, FLOOR + 0.45, 0), UP, 0.2, 1.2, "Trim", TINY)
	local poleTop = FLOOR + 6.4
	cyl(m, Vector3.new(0, (FLOOR + poleTop) / 2, 0), UP, poleTop - FLOOR, 0.45, "Frame", SOLID, "Pole")
	local armY = poleTop - 0.6
	rod(m, Vector3.new(-1.1, armY, 0), Vector3.new(1.1, armY, 0), 0.3, "Frame", PROP)
	for _, side in { -1, 1 } do
		cyl(m, Vector3.new(side * 0.95, armY + 0.3, 0), UP, 0.45, 0.3, "Trim", TINY)
		ball(m, Vector3.new(side * 0.95, armY + 0.58, 0), 0.32, "Trim", TINY)
		attach(ctx.base, if side < 0 then "CableL" else "CableR", CFrame.new(side * 0.95, armY + 0.58 - FLOOR / 2, 0))
	end
	cyl(m, Vector3.new(0, poleTop + 0.1, 0), UP, 0.25, 0.8, "Body", TINY)
	local status = ball(m, Vector3.new(0, poleTop + 0.45, 0), 0.5, "Lamp", TINY, "PowerLamp")
	status.Color, status.Material = P.Green, NEON
	attach(ctx.base, "Prompt", CFrame.new(0, 1.5, 0))
	return ctx
end

--[[
	A power cable from `a` to `b` sagging by `sag` in the middle: dark
	segments along a parabola. Preview helper for the poles.
]]
function KitMachines.cable(parent: Instance, a: Vector3, b: Vector3, sag: number?)
	local n = 6
	local s = sag or 0.8
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, s * 4 * t * (1 - t), 0)
		rod(parent, prev, p, 0.1, "Rubber", TINY, "Cable")
		prev = p
	end
end

local BUILDERS: { [string]: () -> Ctx } = {
	ClayFurnace = clayFurnace,
	Crusher = crusher,
	AutoCleaner = autoCleaner,
	BlastFurnace = blastFurnace,
	CleaningStation = cleaningStation,
	IronBox = ironBox,
	Sorter = sorter,
	Polisher = polisher,
	BrickFurnace = brickFurnace,
	PlasmaFurnace = plasmaFurnace,
	AlloyFurnace = alloyFurnace,
	CrystalExtractor = crystalExtractor,
	RestorationTable = restorationTable,
	SellBox = sellBox,
	Splitter = splitter,
	RobotArm = robotArmMachine,
	SolarPanel = solarPanel,
	WindTurbine = windTurbine,
	FusionReactor = fusionReactor,
	PowerPole = powerPole,
}

export type CatalogEntry = { Id: string, Name: string, Group: string, Upgrades: boolean }

-- The whole machine roster (docs/plans/MACHINES_PLAN.md) in showroom order.
KitMachines.Catalog = {
	{ Id = "CleaningStation", Name = "Cleaning Station", Group = "Cleaning", Upgrades = true },
	{ Id = "AutoCleaner", Name = "Cleaning Plant", Group = "Cleaning", Upgrades = true },
	{ Id = "IronBox", Name = "Iron Box", Group = "Cleaning", Upgrades = true },
	{ Id = "Sorter", Name = "Sorter", Group = "Cleaning", Upgrades = true },
	{ Id = "Polisher", Name = "Polisher", Group = "Cleaning", Upgrades = true },
	{ Id = "ClayFurnace", Name = "Clay Furnace", Group = "Furnaces", Upgrades = true },
	{ Id = "BrickFurnace", Name = "Brick Furnace", Group = "Furnaces", Upgrades = true },
	{ Id = "BlastFurnace", Name = "Blast Furnace", Group = "Furnaces", Upgrades = true },
	{ Id = "PlasmaFurnace", Name = "Plasma Furnace", Group = "Furnaces", Upgrades = true },
	{ Id = "AlloyFurnace", Name = "Alloy Furnace", Group = "Furnaces", Upgrades = true },
	{ Id = "Crusher", Name = "Crusher", Group = "Special", Upgrades = true },
	{ Id = "CrystalExtractor", Name = "Crystal Extractor", Group = "Special", Upgrades = true },
	{ Id = "RestorationTable", Name = "Restoration Table", Group = "Special", Upgrades = true },
	{ Id = "SellBox", Name = "Sell Box", Group = "Special", Upgrades = true },
	{ Id = "Conveyor", Name = "Conveyor", Group = "Transport", Upgrades = false },
	{ Id = "ExpressConveyor", Name = "Express Conveyor", Group = "Transport", Upgrades = false },
	{ Id = "Splitter", Name = "Splitter", Group = "Transport", Upgrades = true },
	{ Id = "BeltLift", Name = "Belt Lift", Group = "Transport", Upgrades = false },
	{ Id = "Slide", Name = "Slide", Group = "Transport", Upgrades = false },
	{ Id = "RobotArm", Name = "Robot Arm", Group = "Transport", Upgrades = true },
	{ Id = "SolarPanel", Name = "Solar Panel", Group = "Power", Upgrades = true },
	{ Id = "WindTurbine", Name = "Wind Turbine", Group = "Power", Upgrades = true },
	{ Id = "FusionReactor", Name = "Fusion Reactor", Group = "Power", Upgrades = true },
	{ Id = "PowerPole", Name = "Power Pole", Group = "Power", Upgrades = false },
} :: { CatalogEntry }

function KitMachines.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

--[[
	Builds machine `id` at the local origin with the upgrade look `level`
	(0 = plain ... MaxLevel = crystal) in crystal theme `themeName`.
]]
function KitMachines.build(id: string, level: number?, themeName: string?): Model
	local builder = BUILDERS[id]
	assert(builder, "No kit model for machine " .. tostring(id))
	local ctx = builder()
	local lvl = math.clamp(math.floor(level or 0), 0, KitMachines.MaxLevel)
	local theme = KitMachines.Themes[themeName or KitMachines.DefaultTheme] or KitMachines.Themes[KitMachines.DefaultTheme]
	crystalize(ctx, lvl, theme)
	ctx.model:SetAttribute("Level", lvl)
	local base = ctx.base
	local topY = 0
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			local cf, size = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local halfHeight = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
			topY = math.max(topY, cf.Position.Y + halfHeight)
		end
	end
	attach(base, "Status", CFrame.new(0, topY - base.CFrame.Position.Y + 1.5, 0))
	return ctx.model
end

-- Any roster entry: the machines through build(), the belts and slopes through their own builders.
function KitMachines.buildAny(id: string, level: number?, themeName: string?): Model
	if id == "Conveyor" then
		return KitMachines.conveyor()
	elseif id == "ExpressConveyor" then
		return KitMachines.conveyor(nil, true)
	elseif id == "BeltLift" then
		return KitMachines.slope(true)
	elseif id == "Slide" then
		return KitMachines.slope(false)
	end
	return KitMachines.build(id, level, themeName)
end

return KitMachines
