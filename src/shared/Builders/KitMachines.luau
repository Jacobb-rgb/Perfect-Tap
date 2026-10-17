--[[
	Kenney Factory Kit machines (the v2 machine look, owner 2026-10-17:
	"make the machines with this kit, the pipes with water too, everything in
	the kit looks great"). Every machine is put together from part-built
	copies of the kit's pieces (docs/KENNEY_FACTORY_KIT.md):
	  housing   "machine": chunky body, chamfered top edges, a light arch
	            frame round the front opening, an orange base band, an
	            optional side window (machine-window) or wrap band
	            (machine-fortified)
	  pipes     pipe-large with octagonal flanges and bolts, pipe-large-bend
	            (a smooth quarter circle), pipe-large-valve (light sleeve,
	            orange hand wheel), pipe-glass-large (water or molten metal
	            inside), machine-connection-pipe (octagonal neck on a lid)
	  hoppers   hopper-round / hopper-square: the intake on top
	  tanks     piston-round
	  details   cog-a, warning-traffic, screen-panel-small, robot-arm-a,
	            scanner-high (the cleaner's arch), conveyor-bars-stripe-high
	Colours: the kit's shapes in iron (owner: "iron first"), the kit's orange.

	Upgrades change the look (owner): level 0 is plain iron; levels 1 and 2
	grow small crystal shards; level 3 turns the light frames, flanges and
	pipes into crystal with bigger clusters; level 4 (max) is a whole crystal
	machine with a hero crystal on top. Themes = the crystal colours.

	Same contract as MachineBuilder (Base + attachments Intake (IntakeSize),
	Output, Prompt, Status, OrePoint/CamPoint, WaterOut/WaterIn; the named
	moving parts MachineFxController animates: Glow, Molten, Cog1/Cog2,
	Roller1/2 (+Tooth), Drum/DrumRib, BedRoller, WaterPool, StackRed/Amber/
	Green, Vent, ChimneyTop) so it can replace it once the owner approves.
	Every part carries the attribute Kit = its colour role (Body, Light, Dark,
	Trim, Pipe, Glass, Water, Molten, Glow, Screen, ScreenGlow, Lamp, Floor,
	Crystal), which is how the crystal levels repaint a machine.

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

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local UP = Vector3.yAxis
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local TAN8 = math.tan(math.pi / 8)
local FLOOR = 0.3 -- top of the Base plate

KitMachines.MaxLevel = 4

-- The kit's shapes in iron: one mid body colour, light frames and flanges,
-- darker pipes and recesses, the kit's orange for base bands and handles.
KitMachines.Palette = {
	Body = rgb(122, 128, 146),
	Light = rgb(180, 186, 202),
	Dark = rgb(58, 62, 76),
	Pipe = rgb(96, 102, 120),
	Trim = rgb(255, 166, 58),
	Glass = rgb(200, 232, 246),
	Water = rgb(60, 170, 232),
	Molten = rgb(255, 120, 28),
	Glow = rgb(240, 100, 24),
	Screen = rgb(28, 36, 46),
	ScreenGlow = rgb(96, 232, 150),
	Floor = rgb(84, 88, 102),
	Red = rgb(235, 70, 60),
	Amber = rgb(255, 176, 40),
	Green = rgb(80, 210, 110),
	Rubber = rgb(42, 42, 50),
	Bristle = rgb(40, 110, 120),
	Smoke = rgb(150, 140, 135),
}
local P = KitMachines.Palette

-- Crystal colours for the upgrade levels.
KitMachines.Themes = {
	Aqua = { Main = rgb(90, 214, 255), Deep = rgb(36, 120, 226), Pale = rgb(204, 246, 255) },
	Amethyst = { Main = rgb(178, 122, 255), Deep = rgb(98, 52, 206), Pale = rgb(232, 212, 255) },
	Rose = { Main = rgb(255, 124, 198), Deep = rgb(212, 56, 140), Pale = rgb(255, 216, 238) },
} :: { [string]: Theme }
KitMachines.DefaultTheme = "Aqua"

-- Same water look as MachineBuilder.Water (the client animates the stream).
local WATER_POOL_TRANSPARENCY = 0.22

local MATERIAL: { [string]: Enum.Material } = {
	Molten = NEON,
	Glow = NEON,
	ScreenGlow = NEON,
	Glass = GLASS,
}
local TRANSPARENCY: { [string]: number } = { Glass = 0.55, Water = 0.2 }

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
	local ref = if math.abs(x.Y) < 0.95 then UP else Vector3.zAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(pos, x, y, z)
end

local function cyl(
	m: Instance,
	center: Vector3,
	dir: Vector3,
	length: number,
	d: number,
	role: string,
	flags: Props?,
	name: string?
): BasePart
	local part = Geo.make("Part", { Shape = Enum.PartType.Cylinder, CFrame = along(center, dir), Size = Vector3.new(length, d, d) }, m)
	return style(part, role, flags, name)
end

local function ball(m: Instance, center: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	local part = Geo.make("Part", { Shape = Enum.PartType.Ball, CFrame = CFrame.new(center), Size = Vector3.new(d, d, d) }, m)
	return style(part, role, flags or TINY, name)
end

-- Cylinder from `a` to `b`.
local function rod(m: Instance, a: Vector3, b: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	return cyl(m, (a + b) / 2, b - a, (b - a).Magnitude, d, role, flags, name)
end

--[[
	Octagonal prism along `frame`'s X axis, `across` the flats: four bars as
	wide as an octagon side crossed at 45 degree steps. 4 parts.
]]
local function octagon(m: Instance, frame: CFrame, across: number, thick: number, role: string, flags: Props?, name: string?)
	for k = 0, 3 do
		block(m, frame * CFrame.Angles(k * math.pi / 4, 0, 0), Vector3.new(thick, across, across * TAN8), role, flags, name)
	end
end

--[[
	Wedge whose slope faces `up` and `out` (perpendicular unit vectors): full
	height on the inner side, `length` along the edge, `rise` along `up`,
	`run` along `out`; `center` = centre of its bounding box. With up = -Y
	it is a funnel side.
]]
local function slope(
	m: Instance,
	center: Vector3,
	up: Vector3,
	out: Vector3,
	length: number,
	rise: number,
	run: number,
	role: string,
	flags: Props?,
	name: string?
): BasePart
	return wedge(m, CFrame.fromMatrix(center, out:Cross(up), up, -out), Vector3.new(length, rise, run), role, flags, name)
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
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(2, 3.5)
	e.Speed = NumberRange.new(3, 5)
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
	e.Rate = 2
	e.Parent = parent
end

---------------------------------------------------------------- kit pieces

--[[
	pipe-large flange: an octagon 1.45x the pipe across, light; an open end
	shows a dark hole. `center` = middle of the flange ring.
]]
local function flange(m: Instance, center: Vector3, dir: Vector3, d: number, open: boolean?)
	local t = math.max(0.16, d * 0.22)
	octagon(m, along(center, dir), d * 1.45, t, "Light", if d >= 0.9 then PROP else TINY)
	if open then
		cyl(m, center + dir.Unit * (t / 2 + 0.02), dir, 0.04, d * 0.78, "Dark", TINY)
	end
end

type PipeOpts = {
	role: string?, -- body role (default Pipe)
	fluid: string?, -- glass pipe with this inside (Water / Molten)
	a: boolean?, -- flange at a (default true)
	b: boolean?, -- flange at b (default true)
	openA: boolean?,
	openB: boolean?,
	bolts: boolean?, -- default true
	name: string?,
	flags: Props?,
}

--[[
	pipe-large (or pipe-glass-large with `fluid` inside) from `a` to `b`,
	octagonal flanges at the ends, two bolt heads on the body.
]]
local function pipe(m: Instance, a: Vector3, b: Vector3, d: number, o: PipeOpts?)
	local opts: PipeOpts = o or {}
	local dir = (b - a).Unit
	local t = math.max(0.16, d * 0.22)
	if opts.fluid then
		rod(m, a, b, d * 0.98, "Glass", TINY, opts.name)
		rod(m, a + dir * t, b - dir * t, d * 0.56, opts.fluid, TINY, if opts.fluid == "Molten" then "Molten" else "Fluid")
	else
		rod(m, a, b, d, opts.role or "Pipe", opts.flags or PROP, opts.name)
	end
	if opts.a ~= false then
		flange(m, a + dir * (t / 2), dir, d, opts.openA)
	end
	if opts.b ~= false then
		flange(m, b - dir * (t / 2), dir, d, opts.openB)
	end
	if opts.bolts ~= false and not opts.fluid and (b - a).Magnitude > d * 1.6 then
		local side = along(a, dir).YVector
		for _, f in { 0.0, 1.0 } do
			local p = a:Lerp(b, f) + dir * (if f == 0 then t + d * 0.32 else -(t + d * 0.32)) + side * (d / 2)
			ball(m, p, math.max(0.14, d * 0.2), "Light")
		end
	end
end

--[[
	pipe-large-bend: a quarter circle of radius `r` starting at `p0` heading
	`da`, ending heading `db` (3 segments, ball joints so it stays round).
	Returns the end point.
]]
local function bend(m: Instance, p0: Vector3, da: Vector3, db: Vector3, d: number, r: number, role: string?, flanges: boolean?): Vector3
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
	local p1 = points[4]
	if flanges then
		local t = math.max(0.16, d * 0.22)
		flange(m, p0 + da * (t / 2), da, d)
		flange(m, p1 - db * (t / 2), db, d)
	end
	return p1
end

-- pipe-large-valve: a light sleeve round the pipe and an orange hand wheel toward `up`.
local function valve(m: Instance, center: Vector3, dir: Vector3, d: number, up: Vector3)
	cyl(m, center, dir, d * 0.9, d * 1.3, "Light", PROP)
	local stemTop = center + up * (d * 0.65 + 0.35)
	rod(m, center + up * (d * 0.6), stemTop, d * 0.22, "Dark", TINY)
	cyl(m, stemTop, up, 0.14, d * 1.05, "Trim", TINY, "Wheel")
	cyl(m, stemTop + up * 0.08, up, 0.1, d * 0.32, "Light", TINY)
end

type HousingOpts = {
	bevel: number?,
	trim: number?,
	arch: { w: number, h: number, x: number?, bottom: number?, fill: string?, name: string? }?,
	window: { side: number, w: number, h: number, y: number, z: number? }?,
	band: { z: number, w: number }?, -- machine-fortified wrap band
	cap: boolean?,
	name: string?,
}

--[[
	Kenney "machine" housing at `cf` (bottom centre, front = -Z): orange base
	band, body, chamfered long top edges, a light arch frame round the front
	opening (`fill` = what shows inside: Dark, Glow...), an optional side
	window and wrap band. Returns the top height above `cf`.
]]
local function housing(m: Instance, cf: CFrame, w: number, h: number, d: number, o: HousingOpts?): number
	local opts: HousingOpts = o or {}
	local bevel = opts.bevel or math.min(w, d) * 0.13
	local trim = opts.trim or 0.5
	block(m, cf * CFrame.new(0, trim / 2, 0), Vector3.new(w + 0.14, trim, d + 0.14), "Trim", SOLID)
	local bodyH = h - trim - bevel
	block(m, cf * CFrame.new(0, trim + bodyH / 2, 0), Vector3.new(w, bodyH, d), "Body", SOLID, opts.name or "Body")
	block(m, cf * CFrame.new(0, h - bevel / 2, 0), Vector3.new(w - 2 * bevel, bevel, d), "Body", SOLID)
	for _, side in { -1, 1 } do
		local out = cf:VectorToWorldSpace(Vector3.new(side, 0, 0))
		slope(
			m,
			cf:PointToWorldSpace(Vector3.new(side * (w / 2 - bevel / 2), h - bevel / 2, 0)),
			cf.UpVector,
			out,
			d,
			bevel,
			bevel,
			"Body",
			SOLID
		)
	end
	if opts.arch then
		local a = opts.arch
		local ax = a.x or 0
		local bottom = a.bottom or trim
		local t = math.clamp(a.w * 0.18, 0.4, 0.75)
		local depth = 0.6
		local fz = -d / 2 - depth / 2 + 0.25
		local top = bottom + a.h + t
		for _, side in { -1, 1 } do
			block(m, cf * CFrame.new(ax + side * (a.w / 2 + t / 2), top / 2, fz), Vector3.new(t, top, depth), "Light", SOLID)
		end
		block(m, cf * CFrame.new(ax, top - t / 2, fz), Vector3.new(a.w + 2 * t, t, depth), "Light", SOLID)
		-- sill under the opening, then what shows inside it
		block(m, cf * CFrame.new(ax, bottom / 2, fz + 0.05), Vector3.new(a.w, bottom, depth - 0.1), "Light", SOLID)
		local inside =
			block(m, cf * CFrame.new(ax, bottom + a.h / 2, -d / 2 + 0.02), Vector3.new(a.w, a.h, 0.2), a.fill or "Dark", TINY, a.name)
		if a.fill == "Glow" then
			-- a darker throat round the glow so it reads as an opening
			block(m, cf * CFrame.new(ax, bottom + a.h - 0.15, -d / 2 - 0.06), Vector3.new(a.w, 0.3, 0.1), "Dark", TINY)
			light(inside, P.Glow, 9, 1.1)
			embers(inside, P.Glow)
		end
	end
	if opts.window then
		local win = opts.window
		local x = win.side * (w / 2 + 0.06)
		local z = win.z or 0
		local t = 0.32
		for _, s in { -1, 1 } do
			block(m, cf * CFrame.new(x, win.y + s * (win.h / 2 + t / 2), z), Vector3.new(0.3, t, win.w + 2 * t), "Light", TINY)
			block(m, cf * CFrame.new(x, win.y, z + s * (win.w / 2 + t / 2)), Vector3.new(0.3, win.h, t), "Light", TINY)
		end
		block(m, cf * CFrame.new(x - win.side * 0.02, win.y, z), Vector3.new(0.12, win.h, win.w), "Glass", TINY, "Window")
		block(m, cf * CFrame.new(win.side * (w / 2 - 0.9), win.y, z), Vector3.new(0.1, win.h, win.w), "Dark", TINY)
	end
	if opts.band then
		local b = opts.band
		local bw = w + 0.24
		for _, side in { -1, 1 } do
			block(
				m,
				cf * CFrame.new(side * (bw / 2 - 0.06), (h - bevel) / 2 + trim / 2, b.z),
				Vector3.new(0.12, h - bevel - trim, b.w),
				"Light",
				SOLID
			)
			local out = cf:VectorToWorldSpace(Vector3.new(side, 0, 0))
			slope(
				m,
				cf:PointToWorldSpace(Vector3.new(side * (bw / 2 - bevel / 2), h - bevel / 2 + 0.06, b.z)),
				cf.UpVector,
				out,
				b.w,
				bevel + 0.12,
				bevel + 0.06,
				"Light",
				TINY
			)
		end
		block(m, cf * CFrame.new(0, h - bevel / 2 + 0.06, b.z), Vector3.new(bw - 2 * bevel - 0.12, bevel + 0.12, b.w), "Light", SOLID)
	end
	if opts.cap ~= false then
		block(m, cf * CFrame.new(0, h + 0.1, d * 0.22), Vector3.new(w * 0.32, 0.2, d * 0.2), "Light", TINY)
	end
	return h
end

--[[
	hopper-round: an octagonal funnel from `neckD` up to an octagonal cup `d`
	across with a light band round its foot and a dark mouth; an optional
	neck below. `bottom` = where the neck (or funnel) starts. Returns the rim
	height (world Y).
]]
local function hopperRound(m: Instance, bottom: Vector3, d: number, neckD: number, neckH: number): number
	local x, z = bottom.X, bottom.Z
	local y = bottom.Y
	if neckH > 0 then
		cyl(m, Vector3.new(x, y + neckH / 2, z), UP, neckH, neckD, "Body", SOLID)
		cyl(m, Vector3.new(x, y + 0.15, z), UP, 0.3, neckD * 1.18, "Light", TINY)
		y += neckH
	end
	local funnelH = (d - neckD) * 0.42
	local topA, botA = d * 0.48, neckD * 0.5
	local sideW = (topA + botA) * TAN8 * 1.04
	for i = 0, 7 do
		local a = i * math.pi / 4
		local out = Vector3.new(math.sin(a), 0, -math.cos(a))
		slope(m, Vector3.new(x, y + funnelH / 2, z) + out * ((topA + botA) / 2), -UP, out, sideW, funnelH, topA - botA, "Body", SOLID)
	end
	cyl(m, Vector3.new(x, y + funnelH / 2, z), UP, funnelH, neckD, "Body", SOLID)
	y += funnelH
	local cupH = d * 0.34
	octagon(m, along(Vector3.new(x, y + cupH / 2, z), UP), d, cupH, "Body", SOLID)
	local bandH = cupH * 0.46
	octagon(m, along(Vector3.new(x, y + bandH / 2, z), UP), d * 1.1, bandH, "Light", SOLID)
	local rim = y + cupH
	octagon(m, along(Vector3.new(x, rim + 0.02, z), UP), d * 0.76, 0.06, "Dark", TINY)
	return rim
end

--[[
	hopper-square: a square funnel `bottomW` -> `topW` on `cf` (bottom
	centre), a light band, a square cup with a dark mouth. Returns the rim
	height above `cf`.
]]
local function hopperSquare(m: Instance, cf: CFrame, bottomW: number, topW: number, funnelH: number, cupH: number): number
	local run = (topW - bottomW) / 2
	local sideW = topW * 0.78 + bottomW * 0.22
	for i = 0, 3 do
		local out = cf:VectorToWorldSpace(Vector3.new(math.sin(i * math.pi / 2), 0, -math.cos(i * math.pi / 2)))
		local center = cf:PointToWorldSpace(Vector3.new(0, funnelH / 2, 0)) + out * (bottomW / 2 + run / 2)
		slope(m, center, -cf.UpVector, out, sideW, funnelH, run, "Body", SOLID)
	end
	block(m, cf * CFrame.new(0, funnelH / 2, 0), Vector3.new(bottomW, funnelH, bottomW), "Body", SOLID)
	local band = cupH * 0.45
	block(m, cf * CFrame.new(0, funnelH + band / 2, 0), Vector3.new(topW + 0.3, band, topW + 0.3), "Light", SOLID)
	block(m, cf * CFrame.new(0, funnelH + cupH / 2, 0), Vector3.new(topW, cupH, topW), "Body", SOLID)
	local rim = funnelH + cupH
	block(m, cf * CFrame.new(0, rim + 0.02, 0), Vector3.new(topW - 0.6, 0.06, topW - 0.6), "Dark", TINY)
	return rim
end

type TankOpts = { role: string?, window: Vector3?, name: string? }

--[[
	piston-round: a body on a narrower dark foot, a light band, a wide dark
	octagonal cap. `window` (a horizontal direction) adds a glass gauge strip
	with water behind it on that side. Returns the cap's top (world Y).
]]
local function tank(m: Instance, bottom: Vector3, d: number, h: number, o: TankOpts?): number
	local opts: TankOpts = o or {}
	local foot, band = 0.28, 0.24
	local capH = math.max(0.45, d * 0.2)
	local bodyTop = h - capH - band
	cyl(m, bottom + Vector3.new(0, foot / 2, 0), UP, foot, d * 0.86, "Dark", PROP)
	cyl(m, bottom + Vector3.new(0, (foot + bodyTop) / 2, 0), UP, bodyTop - foot, d, opts.role or "Body", SOLID, opts.name or "Tank")
	cyl(m, bottom + Vector3.new(0, bodyTop + band / 2, 0), UP, band, d * 0.9, "Light", PROP)
	octagon(m, along(bottom + Vector3.new(0, h - capH / 2, 0), UP), d * 1.08, capH, "Pipe", SOLID)
	cyl(m, bottom + Vector3.new(0, h + 0.03, 0), UP, 0.06, d * 0.62, "Light", TINY)
	if opts.window then
		local out = opts.window.Unit
		local gh = (bodyTop - foot) * 0.72
		local gy = foot + (bodyTop - foot) * 0.5
		local cf = CFrame.lookAt(bottom + Vector3.new(0, gy, 0) + out * (d / 2), bottom + Vector3.new(0, gy, 0) + out * (d / 2 + 1))
		block(m, cf * CFrame.new(0, 0, -0.02), Vector3.new(d * 0.3, gh, 0.22), "Light", TINY)
		block(m, cf * CFrame.new(0, -gh * 0.12, -0.16), Vector3.new(d * 0.18, gh * 0.72, 0.06), "Water", TINY, "TankWater")
		block(m, cf * CFrame.new(0, 0, -0.19), Vector3.new(d * 0.2, gh * 0.94, 0.04), "Glass", TINY)
	end
	return bottom.Y + h
end

-- cog-a: a light gear (8 teeth = 4 crossed bars) round a dark octagonal hole. All parts take `name`.
local function cog(m: Instance, center: Vector3, axis: Vector3, d: number, thick: number, name: string)
	local frame = along(center, axis)
	cyl(m, center, axis, thick, d * 0.8, "Light", PROP, name)
	for k = 0, 3 do
		block(m, frame * CFrame.Angles(k * math.pi / 4 + math.pi / 8, 0, 0), Vector3.new(thick, d, d * 0.17), "Light", TINY, name)
	end
	octagon(m, frame, d * 0.3, thick + 0.06, "Dark", TINY, name)
end

-- warning-traffic: foot, pole, red / amber / green lamps (green lit), cap. `s` = scale.
local function stackLight(m: Instance, bottom: Vector3, s: number)
	octagon(m, along(bottom + Vector3.new(0, 0.1 * s, 0), UP), 0.75 * s, 0.2 * s, "Light", TINY)
	local poleTop = bottom.Y + 2.0 * s
	cyl(m, Vector3.new(bottom.X, (bottom.Y + poleTop) / 2, bottom.Z), UP, poleTop - bottom.Y, 0.24 * s, "Pipe", PROP)
	cyl(m, Vector3.new(bottom.X, poleTop, bottom.Z), UP, 0.2 * s, 0.56 * s, "Light", TINY)
	local lamps: { { name: string, color: Color3 } } = {
		{ name = "StackGreen", color = P.Green },
		{ name = "StackAmber", color = P.Amber },
		{ name = "StackRed", color = P.Red },
	}
	for i, lamp in lamps do
		local part =
			cyl(m, Vector3.new(bottom.X, poleTop + (0.1 + (i - 0.5) * 0.34) * s, bottom.Z), UP, 0.32 * s, 0.5 * s, "Lamp", TINY, lamp.name)
		local lit = lamp.name == "StackGreen"
		part.Color = lamp.color:Lerp(BLACK, 0.3)
		part.Material = if lit then NEON else SMOOTH
	end
	cyl(m, Vector3.new(bottom.X, poleTop + 1.2 * s, bottom.Z), UP, 0.18 * s, 0.56 * s, "Light", TINY)
end

-- screen-panel-small standing on `cf` (bottom centre, screen toward -Z): light frame, dark screen, a green bar.
local function screenPanel(m: Instance, cf: CFrame, w: number, h: number)
	block(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, 0.4), "Light", PROP)
	block(m, cf * CFrame.new(0, h * 0.55, -0.21), Vector3.new(w - 0.36, h * 0.6, 0.05), "Screen", TINY, "Screen")
	block(m, cf * CFrame.new(-w * 0.12, h * 0.47, -0.245), Vector3.new((w - 0.36) * 0.55, 0.14, 0.03), "ScreenGlow", TINY, "LampBulb")
	block(m, cf * CFrame.new(w * 0.2, h * 0.68, -0.245), Vector3.new(0.18, 0.18, 0.03), "ScreenGlow", TINY)
end

-- Output chute: a dark slide with light lips from the housing face toward the Output.
local function chute(m: Instance, x: number, fromZ: number, toZ: number, fromY: number, toY: number, w: number)
	local a, b = Vector3.new(x, fromY, fromZ), Vector3.new(x, toY, toZ)
	local cf = CFrame.lookAt((a + b) / 2, b)
	local len = (b - a).Magnitude
	block(m, cf, Vector3.new(w, 0.2, len), "Dark", PROP, "Chute")
	for _, side in { -1, 1 } do
		block(m, cf * CFrame.new(side * (w / 2 + 0.06), 0.14, 0), Vector3.new(0.14, 0.42, len), "Light", TINY, "ChuteLip")
	end
end

---------------------------------------------------------------- crystals

--[[
	One crystal (like the mine's crystals): a diamond-section body, a darker
	facet block through it (alternating light and dark faces), a ridge tip.
	`base` = bottom centre, up = growth. 3-4 parts.
]]
local function shard(m: Instance, base: CFrame, height: number, width: number, color: Color3, glowTip: boolean, clear: boolean)
	local bodyH = height * 0.72
	local tipH = height - bodyH
	local light, dark = color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.26)
	local material = if clear then GLASS else SMOOTH
	local transparency = if clear then 0.18 else 0
	local cf = base * CFrame.Angles(0, math.pi / 4, 0)
	local body = block(m, cf * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), "Crystal", TINY, "Crystal")
	body.Color, body.Material, body.Transparency = light, material, transparency
	if width >= 0.55 then
		local facet = block(
			m,
			base * CFrame.new(0, bodyH * 0.49, 0),
			Vector3.new(width * 0.84, bodyH * 0.98, width * 0.84),
			"Crystal",
			TINY,
			"CrystalFacet"
		)
		facet.Color, facet.Material, facet.Transparency = dark, material, transparency * 0.5
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
	Upgrade look: crystal clusters on the machine's sockets (more and bigger
	per level), then the machine itself turns to crystal by colour role:
	level 2 the orange trims, level 3 the light frames, flanges and pipes,
	level 4 the body (see-through crystal with a glowing inside).
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
	-- repaint by role; frames stay opaque and lighter than the body so the
	-- shapes keep reading, only the inside (Dark) glows
	for _, d in ctx.model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Kit")
			if role == "Trim" and level >= 2 then
				d.Color = if level >= 4 then theme.Deep else theme.Main
			elseif role == "Light" and level >= 3 then
				d.Color = theme.Pale
				d.Material = GLASS
				d.Transparency = 0.04
			elseif role == "Pipe" and level >= 3 then
				d.Color = theme.Main:Lerp(theme.Deep, 0.4)
				d.Material = GLASS
				d.Transparency = 0.06
			elseif role == "Body" and level >= 4 then
				d.Color = theme.Main
				d.Material = GLASS
				d.Transparency = 0.1
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

-- A crystal socket at `pos` growing along `up` (tilted outward a bit).
local function socket(ctx: Ctx, pos: Vector3, up: Vector3, size: number, hero: boolean?)
	local u = up.Unit
	local ref = if math.abs(u.Y) < 0.95 then UP else Vector3.zAxis
	local x = ref:Cross(u).Unit
	local z = x:Cross(u)
	table.insert(ctx.sockets, { cf = CFrame.fromMatrix(pos, x, u, z), size = size, hero = hero })
end

-- Up and outward from the corner direction (dx, dz).
local function out(dx: number, dz: number, lean: number?): Vector3
	return Vector3.new(dx * (lean or 0.55), 1, dz * (lean or 0.55))
end

---------------------------------------------------------------- machines

local function newModel(id: string): Ctx
	local machine = MachineData.ById[id]
	local w, d = machine.Size[1] * GameConfig.CellSize, machine.Size[2] * GameConfig.CellSize
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("MachineId", id)
	local base = block(model, CFrame.new(0, FLOOR / 2, 0), Vector3.new(w - 0.3, FLOOR, d - 0.3), "Floor", SOLID, "Base")
	model.PrimaryPart = base :: any
	return { model = model, base = base, sockets = {} }
end

--[[
	Clay Furnace (2x2): a machine-connection-pipe housing with the glowing
	furnace mouth in its arch, a round hopper on the lid (the intake), a
	flanged chimney, a fuel tank whose pipe bends into the side, the output
	chute at the front right.
]]
local function clayFurnace(): Ctx
	local ctx = newModel("ClayFurnace")
	local m = ctx.model
	local hx, hz, w, h, d = -0.4, -0.2, 5.6, 4.6, 5.6
	housing(
		m,
		CFrame.new(hx, FLOOR, hz),
		w,
		h,
		d,
		{ arch = { w = 2.4, h = 2.0, x = -0.9, bottom = 0.8, fill = "Glow", name = "Glow" }, cap = false }
	)
	local top = FLOOR + h
	local rim = hopperRound(m, Vector3.new(-1.3, top, -0.9), 2.9, 1.3, 0.3)
	-- chimney: connection-pipe neck on the lid, a long flanged pipe, a dark mouth with smoke
	local cx, cz = 1.15, 1.25
	octagon(m, along(Vector3.new(cx, top + 0.3, cz), UP), 2.0, 0.6, "Light", SOLID)
	pipe(m, Vector3.new(cx, top + 0.6, cz), Vector3.new(cx, top + 2.4, cz), 1.15, { b = true })
	pipe(m, Vector3.new(cx, top + 2.4, cz), Vector3.new(cx, top + 4.2, cz), 1.15, { a = false, openB = true })
	local mouth = cyl(m, Vector3.new(cx, top + 4.25, cz), UP, 0.05, 0.85, "Dark", TINY, "ChimneyTop")
	smoke(mouth, 2)
	-- fuel tank on the right; its pipe climbs and bends into the housing side
	local tx, tz = 3.05, 1.6
	local tankTop = tank(m, Vector3.new(tx, FLOOR, tz), 1.5, 3.1)
	local p0 = Vector3.new(tx, tankTop + 0.35, tz)
	rod(m, Vector3.new(tx, tankTop, tz), p0, 0.6, "Pipe", PROP)
	local p1 = bend(m, p0, UP, -Vector3.xAxis, 0.6, 0.55)
	pipe(m, p1, Vector3.new(hx + w / 2 - 0.05, p1.Y, tz), 0.6, { a = false })
	-- output chute toward the shared output cell
	local outPos = Grid.outputLocal("ClayFurnace") :: Vector3
	chute(m, outPos.X, hz - d / 2 + 0.1, outPos.Z + 0.3, 2.0, outPos.Y - 0.25, 1.5)
	block(m, CFrame.new(outPos.X, 2.45, hz - d / 2 - 0.05), Vector3.new(1.6, 0.9, 0.2), "Dark", TINY)

	socket(ctx, Vector3.new(hx - w / 2 + 0.5, top, hz - d / 2 + 0.6), out(-1, -1), 1.3)
	socket(ctx, Vector3.new(tx, tankTop + 0.05, tz + 0.3), out(1, 0.4, 0.3), 1.0)
	socket(ctx, Vector3.new(hx - w / 2 + 0.5, top, hz + d / 2 - 0.5), out(-1, 1), 1.2)
	socket(ctx, Vector3.new(-3.4, FLOOR, -3.3), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(cx + 0.8, top, cz + 1.0), out(1, 1), 1.0)
	socket(ctx, Vector3.new(3.4, FLOOR, 3.3), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(-1.3 - 1.5, rim - 0.6, -0.9), out(-1, 0, 0.9), 0.9)
	socket(ctx, Vector3.new(hx + w / 2, FLOOR + 3.0, hz - 1.6), Vector3.new(1, 0.6, 0), 0.9)
	socket(ctx, Vector3.new(cx, top + 4.3, cz), UP, 1.0, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return ctx
end

--[[
	Crusher (2x2): a machine-window housing (the toothed rollers show
	through the side window), a square hopper on top (the intake), two cogs
	on the right side, the output coming out of the front arch, a stack light.
]]
local function crusher(): Ctx
	local ctx = newModel("Crusher")
	local m = ctx.model
	local hx, hz, w, h, d = -0.35, -0.1, 5.6, 4.1, 5.4
	local outPos = Grid.outputLocal("Crusher") :: Vector3
	housing(m, CFrame.new(hx, FLOOR, hz), w, h, d, {
		arch = { w = 1.9, h = 1.5, x = outPos.X - hx, bottom = 0.7, fill = "Dark" },
		window = { side = -1, w = 2.8, h = 1.9, y = 2.2, z = 0.2 },
		cap = false,
	})
	local top = FLOOR + h
	-- rollers behind the window: dark drums with brass-less light teeth, seen end-on
	for i, zc in { -0.5, 0.9 } do
		local c = Vector3.new(hx - w / 2 + 0.55, FLOOR + 2.2, hz + zc)
		cyl(m, c, Vector3.xAxis, 0.6, 1.15, "Dark", TINY, "Roller" .. i)
		for k = 0, 1 do
			block(
				m,
				along(c, Vector3.xAxis) * CFrame.Angles(k * math.pi / 2 + i * 0.4, 0, 0),
				Vector3.new(0.5, 1.45, 0.26),
				"Light",
				TINY,
				"Roller" .. i .. "Tooth"
			)
		end
	end
	local rim = top + hopperSquare(m, CFrame.new(hx, top, hz + 0.1), 2.4, 4.4, 1.2, 1.4)
	-- cogs on the right side
	local sx = hx + w / 2 + 0.24
	cog(m, Vector3.new(sx, FLOOR + 2.15, hz + 0.75), Vector3.xAxis, 2.7, 0.36, "Cog1")
	cog(m, Vector3.new(sx + 0.02, FLOOR + 3.05, hz - 1.1), Vector3.xAxis, 1.85, 0.36, "Cog2")
	stackLight(m, Vector3.new(-3.3, FLOOR, 3.25), 1.0)
	chute(m, outPos.X, hz - d / 2 + 0.2, outPos.Z + 0.3, 1.25, outPos.Y - 0.25, 1.4)

	socket(ctx, Vector3.new(hx + w / 2 - 0.5, top, hz - d / 2 + 0.5), out(1, -1), 1.2)
	socket(ctx, Vector3.new(hx - w / 2 + 0.5, top, hz + d / 2 - 0.5), out(-1, 1), 1.2)
	socket(ctx, Vector3.new(-3.4, FLOOR, -3.3), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(hx - 2.3, rim - 1.0, hz + 0.1 - 2.3), out(-1, -1, 0.9), 0.9)
	socket(ctx, Vector3.new(3.4, FLOOR, 3.2), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(hx + w / 2 - 0.5, top, hz + d / 2 - 0.5), out(1, 1), 1.0)
	socket(ctx, Vector3.new(hx + 2.3, rim - 1.0, hz + 0.1 + 2.3), out(1, 1, 0.9), 0.9)
	socket(ctx, Vector3.new(hx - w / 2, FLOOR + 3.5, hz - 1.8), Vector3.new(-1, 0.6, 0), 0.8)
	socket(ctx, Vector3.new(hx, rim + 0.05, hz + 0.1), UP, 1.0, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return ctx
end

--[[
	Cleaning Plant / Auto Cleaner (2x2): a conveyor-bars-stripe-high bed
	runs through a scanner-high arch; a water tank (glass gauge) feeds a
	pipe that climbs, runs through a glass section and a valve and bends
	down into the arch's shower head; a robot arm scrubs with a brush drum; a
	round hopper over the back of the bed is the intake; a stack light.
]]
local function autoCleaner(): Ctx
	local ctx = newModel("AutoCleaner")
	local m = ctx.model
	local outPos = Grid.outputLocal("AutoCleaner") :: Vector3
	local bx, bw = outPos.X - 0.1, 3.2
	local z0, z1 = -3.85, 3.7
	local len = z1 - z0
	local bz = (z0 + z1) / 2
	-- bed: body, light rails with an orange stripe, rollers over a shallow water tray
	block(m, CFrame.new(bx, FLOOR + 0.5, bz), Vector3.new(bw - 0.4, 1.0, len), "Body", SOLID, "Bed")
	for _, side in { -1, 1 } do
		block(m, CFrame.new(bx + side * (bw / 2 - 0.2), FLOOR + 0.85, bz), Vector3.new(0.4, 1.7, len), "Light", SOLID)
		block(m, CFrame.new(bx + side * (bw / 2 + 0.01), FLOOR + 1.2, bz), Vector3.new(0.04, 0.24, len), "Trim", TINY)
	end
	block(m, CFrame.new(bx, FLOOR + 1.05, bz), Vector3.new(bw - 0.8, 0.1, len - 0.2), "Water", TINY, "WaterPool").Transparency =
		WATER_POOL_TRANSPARENCY
	for i = 0, 5 do
		cyl(m, Vector3.new(bx, FLOOR + 1.35, z0 + 0.6 + i * (len - 1.2) / 5), Vector3.xAxis, bw - 0.8, 0.66, "Light", SOLID, "BedRoller")
	end
	-- scanner-high arch over the bed with the shower head
	local az = -0.5
	local legX = { bx - bw / 2 - 0.15, bx + bw / 2 + 0.05 }
	local archTop = FLOOR + 5.0
	for _, lx in legX do
		block(m, CFrame.new(lx, FLOOR + 0.3, az), Vector3.new(0.85, 0.6, 0.85), "Trim", SOLID)
		block(m, CFrame.new(lx, (FLOOR + 0.6 + archTop) / 2, az), Vector3.new(0.6, archTop - FLOOR - 0.6, 0.6), "Body", SOLID)
		block(m, CFrame.new(lx, archTop - 0.9, az), Vector3.new(0.72, 0.3, 0.72), "Light", TINY)
		ball(m, Vector3.new(lx, archTop, az), 0.85, "Body", PROP)
	end
	rod(m, Vector3.new(legX[1], archTop, az), Vector3.new(legX[2], archTop, az), 0.85, "Body", SOLID, "Arch")
	local head = block(m, CFrame.new(bx, archTop - 0.6, az), Vector3.new(1.5, 0.3, 0.6), "Light", TINY, "ShowerHead")
	for i = -1, 1 do
		block(m, head.CFrame * CFrame.new(i * 0.45, -0.18, 0), Vector3.new(0.18, 0.08, 0.3), "Dark", TINY)
	end
	local outlet = Vector3.new(bx, archTop - 0.8, az)
	local landing = Vector3.new(bx, FLOOR + 1.9, az)
	local wo = attach(ctx.base, "WaterOut", CFrame.lookAt(outlet, outlet - UP))
	wo.Axis = -UP
	wo:SetAttribute("Curve", 0.6)
	wo:SetAttribute("Spray", true)
	local wi = attach(ctx.base, "WaterIn", CFrame.new(landing))
	wi.Axis = -UP
	wi:SetAttribute("Curve", 0.3)
	-- water tank (glass gauge to the front) and its pipe: up, over, glass run, valve, down into the arch
	local tx, tz, td = -2.15, az, 2.6
	local tankTop = tank(m, Vector3.new(tx, FLOOR, tz), td, 4.0, { window = -Vector3.zAxis, name = "WaterTank" })
	local pd, r = 0.75, 0.6
	local runY = archTop + 1.35
	local p0 = Vector3.new(tx, runY - r, tz)
	pipe(m, Vector3.new(tx, tankTop, tz), p0, pd, { b = false, bolts = false })
	local p1 = bend(m, p0, UP, Vector3.xAxis, pd, r)
	local endX = bx - r
	local glassFrom, glassTo = p1.X + 0.35, endX - 1.1
	pipe(m, p1, Vector3.new(glassFrom, runY, tz), pd, { a = false, bolts = false })
	pipe(m, Vector3.new(glassFrom, runY, tz), Vector3.new(glassTo, runY, tz), pd, { fluid = "Water" })
	pipe(m, Vector3.new(glassTo, runY, tz), Vector3.new(endX, runY, tz), pd, { b = false, bolts = false })
	valve(m, Vector3.new((glassTo + endX) / 2 + 0.05, runY, tz), Vector3.xAxis, pd, -Vector3.zAxis)
	local p2 = bend(m, Vector3.new(endX, runY, tz), Vector3.xAxis, -UP, pd, r)
	pipe(m, p2, Vector3.new(bx, archTop + 0.3, tz), pd, { a = false, bolts = false })
	-- robot arm with the brush drum, front left
	local ax, azArm = -1.75, -2.55
	octagon(m, along(Vector3.new(ax, FLOOR + 0.18, azArm), UP), 1.5, 0.36, "Light", SOLID)
	cyl(m, Vector3.new(ax, FLOOR + 0.75, azArm), UP, 0.8, 1.0, "Body", SOLID)
	local shoulder = Vector3.new(ax, FLOOR + 1.45, azArm)
	cyl(m, shoulder, -Vector3.zAxis, 0.9, 0.75, "Trim", TINY, "ArmJoint")
	local elbow = Vector3.new(ax + 0.85, FLOOR + 3.45, azArm)
	local wrist = Vector3.new(bx - 0.95, FLOOR + 2.65, azArm)
	block(m, CFrame.lookAt((shoulder + elbow) / 2, elbow), Vector3.new(0.55, 0.55, (elbow - shoulder).Magnitude), "Body", PROP)
	cyl(m, elbow, -Vector3.zAxis, 0.8, 0.68, "Trim", TINY, "ArmJoint")
	block(m, CFrame.lookAt((elbow + wrist) / 2, wrist), Vector3.new(0.48, 0.48, (wrist - elbow).Magnitude), "Body", PROP)
	cyl(m, wrist, Vector3.xAxis, 0.5, 0.6, "Light", TINY)
	local drumC = Vector3.new(bx - 0.1, FLOOR + 2.35, azArm)
	cyl(m, drumC, Vector3.xAxis, 1.7, 0.8, "Body", PROP, "Drum").Color = P.Bristle
	for _, dx in { -0.55, 0, 0.55 } do
		cyl(m, drumC + Vector3.new(dx, 0, 0), Vector3.xAxis, 0.22, 1.05, "Body", TINY, "DrumRib").Color = P.Bristle:Lerp(WHITE, 0.25)
	end
	-- intake: round hopper on a neck over the back of the bed
	local rim = hopperRound(m, Vector3.new(bx, FLOOR + 1.9, 2.35), 2.7, 1.0, 1.1)
	local vent = cyl(m, Vector3.new(-3.2, FLOOR + 0.6, 3.1), UP, 1.2, 0.7, "Pipe", PROP, "Vent")
	cyl(m, Vector3.new(-3.2, FLOOR + 1.25, 3.1), UP, 0.12, 0.95, "Light", TINY)
	stackLight(m, Vector3.new(-3.3, FLOOR, -3.3), 0.95)
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Smoke"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = 3
	steam.Parent = vent

	socket(ctx, Vector3.new(tx - 0.8, tankTop + 0.05, tz + 0.7), out(-1, 1, 0.4), 1.1)
	socket(ctx, Vector3.new(legX[2] + 0.1, FLOOR + 0.6, az + 0.5), out(1, 0.6, 0.8), 1.0)
	socket(ctx, Vector3.new(-3.4, FLOOR, 3.3), out(-1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(bx + 1.2, rim - 0.5, 2.35 + 1.0), out(1, 1, 0.8), 0.9)
	socket(ctx, Vector3.new(legX[1] - 0.1, archTop, az), out(-1, 0, 0.6), 0.8)
	socket(ctx, Vector3.new(3.5, FLOOR, -3.4), out(1, -1, 0.9), 0.9)
	socket(ctx, Vector3.new(bx + bw / 2, FLOOR + 1.7, 3.0), Vector3.new(1, 0.7, 0), 0.8)
	socket(ctx, Vector3.new(bx, archTop + 0.4, az - 0.2), out(0, -1, 0.3), 0.9, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return ctx
end

--[[
	Blast Furnace (3x3): a big machine-fortified housing with a wide glowing
	mouth, an octagonal connection-pipe throat on the lid full of molten
	metal (the intake), a pipe arching from the lid over into a glass pipe of
	molten metal that drops into a tank on the right, a tall flanged chimney,
	a molten pour channel to the output, a stack light and a screen.
]]
local function blastFurnace(): Ctx
	local ctx = newModel("BlastFurnace")
	local m = ctx.model
	local hx, hz, w, h, d = 0, 0.2, 8.4, 6.4, 7.8
	housing(m, CFrame.new(hx, FLOOR, hz), w, h, d, {
		arch = { w = 3.4, h = 2.8, bottom = 0.8, fill = "Glow", name = "Glow" },
		band = { z = hz + 1.2, w = 1.1 },
		cap = false,
		bevel = 1.0,
	})
	local top = FLOOR + h
	-- throat: a light neck ring and an octagonal cup with molten metal
	octagon(m, along(Vector3.new(0, top + 0.35, hz - 0.6), UP), 4.2, 0.7, "Light", SOLID)
	octagon(m, along(Vector3.new(0, top + 1.25, hz - 0.6), UP), 3.6, 1.2, "Body", SOLID)
	local rim = top + 1.85
	octagon(m, along(Vector3.new(0, rim + 0.02, hz - 0.6), UP), 2.9, 0.06, "Dark", TINY)
	local molten = cyl(m, Vector3.new(0, rim + 0.06, hz - 0.6), UP, 0.06, 2.3, "Molten", TINY, "Molten")
	light(molten, P.Glow, 10, 0.8)
	-- the pipe arching off the lid into the glass drop and the tank on the right
	local pd, r = 1.0, 0.85
	local tx, tz = 5.0, 2.7
	local tankTop = tank(m, Vector3.new(tx, FLOOR, tz), 1.6, 4.2, { name = "MoltenTank" })
	local sx = tx - 2 * r
	local up0 = Vector3.new(sx, top, tz)
	local up1 = Vector3.new(sx, top + 1.2, tz)
	pipe(m, up0, up1, pd, { b = false })
	local over = bend(m, up1, UP, Vector3.xAxis, pd, r)
	local down0 = bend(m, over, Vector3.xAxis, -UP, pd, r)
	pipe(m, down0, Vector3.new(tx, tankTop + 0.1, tz), pd, { fluid = "Molten" })
	-- chimney at the back left
	local cx, cz = -2.6, hz + 2.4
	octagon(m, along(Vector3.new(cx, top + 0.3, cz), UP), 2.3, 0.6, "Light", SOLID)
	pipe(m, Vector3.new(cx, top + 0.6, cz), Vector3.new(cx, top + 3.4, cz), 1.35)
	pipe(m, Vector3.new(cx, top + 3.4, cz), Vector3.new(cx, top + 6.6, cz), 1.35, { a = false, openB = true })
	local mouth = cyl(m, Vector3.new(cx, top + 6.65, cz), UP, 0.05, 1.0, "Dark", TINY, "ChimneyTop")
	smoke(mouth, 5)
	-- pour channel from the mouth to the output, molten metal in it
	local outPos = Grid.outputLocal("BlastFurnace") :: Vector3
	local mouthZ = hz - d / 2
	chute(m, outPos.X, mouthZ - 0.2, outPos.Z + 0.35, FLOOR + 0.95, outPos.Y - 0.4, 1.6)
	local a, b = Vector3.new(outPos.X, FLOOR + 1.08, mouthZ - 0.25), Vector3.new(outPos.X, outPos.Y - 0.27, outPos.Z + 0.6)
	block(m, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.7, 0.06, (b - a).Magnitude), "Molten", TINY, "Molten")
	stackLight(m, Vector3.new(-5.2, FLOOR, -5.0), 1.2)
	screenPanel(m, CFrame.new(-5.15, FLOOR, -1.4) * CFrame.Angles(0, -math.pi / 2, 0), 1.9, 2.1)

	socket(ctx, Vector3.new(-w / 2 + 0.7, top, hz - d / 2 + 0.7), out(-1, -1), 1.6)
	socket(ctx, Vector3.new(tx, tankTop + 0.05, tz + 0.5), out(1, 1, 0.4), 1.1)
	socket(ctx, Vector3.new(w / 2 - 0.7, top, hz - d / 2 + 0.7), out(1, -1), 1.5)
	socket(ctx, Vector3.new(-5.4, FLOOR, 5.3), out(-1, 1, 0.8), 1.4)
	socket(ctx, Vector3.new(5.4, FLOOR, -5.3), out(1, -1, 0.8), 1.3)
	socket(ctx, Vector3.new(-w / 2 + 0.7, top, hz + d / 2 - 0.7), out(-1, 1), 1.3)
	socket(ctx, Vector3.new(cx, top + 3.4, cz - 0.9), Vector3.new(-0.4, 0.5, -1), 1.0)
	socket(ctx, Vector3.new(-w / 2, FLOOR + 4.2, hz + 2.6), Vector3.new(-1, 0.6, 0), 1.0)
	socket(ctx, Vector3.new(1.9, rim - 0.6, hz - 0.6 + 1.4), out(1, 1, 0.6), 1.0)
	socket(ctx, Vector3.new(0, rim + 0.1, hz - 0.6), UP, 1.4, true)

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return ctx
end

--[[
	Cleaning Station (3x2): a machine-bed workbench (orange base band, light
	knee arch, light work top) with the vise in the middle, the wash tub on
	the left fed by a kit pipe (riser, bend, glass section, valve, open
	flange pouring into the tub), a screen panel, a lever, a tool board and the
	output tray on the right. Same minigame points as MachineBuilder.
]]
local function cleaningStation(): Ctx
	local ctx = newModel("CleaningStation")
	local m = ctx.model
	local top = 3.4
	local benchZ = 0.4
	local front = benchZ - 2.3
	housing(m, CFrame.new(0, FLOOR, benchZ), 10, top - FLOOR, 4.6, {
		arch = { w = 3.6, h = 1.5, bottom = 0.55, fill = "Dark" },
		bevel = 0.25,
		cap = false,
	})
	local deck = top + 0.3
	block(m, CFrame.new(0, top + 0.08, benchZ), Vector3.new(10.5, 0.2, 5.4), "Light", SOLID)
	block(m, CFrame.new(0, deck - 0.1, benchZ + 0.15), Vector3.new(10.7, 0.22, 5.0), "Body", SOLID, "Bench")
	slope(m, Vector3.new(0, deck - 0.1, front - 0.25 + 0.15), UP, -Vector3.zAxis, 10.7, 0.22, 0.4, "Body", SOLID)
	-- drawers
	for _, side in { -1, 1 } do
		block(m, CFrame.new(side * 3.6, 1.9, front - 0.06), Vector3.new(2.2, 1.4, 0.12), "Light", TINY)
		block(m, CFrame.new(side * 3.6, 2.35, front - 0.16), Vector3.new(1.0, 0.18, 0.12), "Trim", TINY)
	end
	-- work slab + vise
	block(m, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), "Dark", SOLID, "WorkSlab")
	for _, side in { -1, 1 } do
		block(m, CFrame.new(side * 1.75, top + 0.95, 0.3), Vector3.new(0.5, 0.5, 2.2), "Light", SOLID, "Jaw")
	end
	block(m, CFrame.new(-1.75, top + 0.95, -0.98), Vector3.new(0.56, 0.44, 0.36), "Pipe", TINY)
	block(m, CFrame.new(-1.75, top + 0.95, -1.27), Vector3.new(1.2, 0.16, 0.16), "Trim", TINY)
	-- wash tub: a hopper-square-like basin with a light rim, filled almost to the lip
	local bx, bz, bw, bd = -4.15, -0.5, 2.3, 2.6
	local tubTop = deck + 0.96
	block(m, CFrame.new(bx, deck + 0.4, bz), Vector3.new(bw, 0.8, bd), "Body", SOLID, "Tub")
	block(m, CFrame.new(bx, tubTop - 0.08, bz), Vector3.new(bw + 0.2, 0.3, bd + 0.2), "Light", SOLID)
	local poolTop = tubTop + 0.1
	block(m, CFrame.new(bx, poolTop - 0.06, bz), Vector3.new(bw - 0.3, 0.12, bd - 0.3), "Water", TINY, "WaterPool").Transparency =
		WATER_POOL_TRANSPARENCY
	-- the kit water pipe: riser out of the plot, bend over the tub, glass run, valve, open flange
	local pd, px, pipeY, outX = 0.62, -5.75, 6.6, -4.35
	local r = 0.55
	pipe(m, Vector3.new(px, FLOOR, bz), Vector3.new(px, pipeY - r - 1.6, bz), pd)
	pipe(m, Vector3.new(px, pipeY - r - 1.6, bz), Vector3.new(px, pipeY - r, bz), pd, { fluid = "Water" })
	local p1 = bend(m, Vector3.new(px, pipeY - r, bz), UP, Vector3.xAxis, pd, r)
	pipe(m, p1, Vector3.new(outX, pipeY, bz), pd, { a = false, openB = true, bolts = false })
	valve(m, Vector3.new((p1.X + outX) / 2, pipeY, bz), Vector3.xAxis, pd, -Vector3.zAxis)
	local outlet = Vector3.new(outX + 0.2, pipeY - 0.04, bz)
	local landing = Vector3.new(outX + 0.55, poolTop, bz)
	local p1c, p2c = outlet + Vector3.xAxis * 0.4, landing + UP * 0.6
	local wo = attach(ctx.base, "WaterOut", CFrame.lookAt(outlet, outlet + Vector3.xAxis))
	wo.Axis = Vector3.xAxis
	wo:SetAttribute("Curve", (p1c - outlet).Magnitude)
	local wi = attach(ctx.base, "WaterIn", CFrame.new(landing))
	wi.Axis = -UP
	wi:SetAttribute("Curve", (landing - p2c).Magnitude)
	-- tool board at the back: chisel, hammer, brush
	local boardZ = 2.85
	block(m, CFrame.new(-0.6, top + 1.6, boardZ), Vector3.new(3.6, 2.6, 0.25), "Light", SOLID)
	local toolZ = boardZ - 0.2
	block(m, CFrame.new(-1.9, top + 1.75, toolZ), Vector3.new(0.24, 1.6, 0.16), "Body", TINY)
	block(m, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), "Trim", TINY)
	block(m, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), "Dark", TINY)
	block(m, CFrame.new(0.5, top + 1.75, toolZ), Vector3.new(0.7, 1.2, 0.3), "Light", TINY)
	screenPanel(m, CFrame.new(2.6, deck, 2.8), 1.8, 2.3)
	-- lever-double
	local lx, lz = 4.7, 1.55
	octagon(m, along(Vector3.new(lx, deck + 0.12, lz), UP), 1.0, 0.24, "Light", TINY)
	for _, side in { -1, 1 } do
		block(
			m,
			CFrame.new(lx + side * 0.24, deck + 0.5, lz) * CFrame.Angles(math.rad(-22), 0, 0),
			Vector3.new(0.12, 0.62, 0.16),
			"Dark",
			TINY
		)
	end
	cyl(m, Vector3.new(lx, deck + 0.8, lz - 0.12), Vector3.xAxis, 0.66, 0.26, "Trim", TINY)
	-- output tray on the right
	block(m, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), "Dark", SOLID, "Tray")
	block(m, CFrame.new(3.6, top + 0.76, -0.4 + 1.22), Vector3.new(2.6, 0.32, 0.16), "Light", SOLID)
	for _, side in { -1, 1 } do
		block(m, CFrame.new(3.6 + side * 1.22, top + 0.76, -0.4), Vector3.new(0.16, 0.32, 2.28), "Light", SOLID)
	end

	socket(ctx, Vector3.new(-5.0, deck, 2.2), out(-1, 1), 1.1)
	socket(ctx, Vector3.new(5.0, deck, 2.3), out(1, 1), 1.1)
	socket(ctx, Vector3.new(-5.6, FLOOR, -1.7), out(-1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(5.6, FLOOR, -1.6), out(1, -1, 0.8), 1.1)
	socket(ctx, Vector3.new(1.3, top + 2.9, boardZ), out(0.6, 1, 0.5), 0.8)
	socket(ctx, Vector3.new(-5.6, FLOOR, 3.5), out(-1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(5.6, FLOOR, 3.5), out(1, 1, 0.8), 1.0)
	socket(ctx, Vector3.new(px, pipeY - r - 1.6, bz - 0.5), Vector3.new(-0.5, 0.4, -1), 0.7)
	socket(ctx, Vector3.new(2.6, deck + 2.35, 2.9), UP, 0.8, true)

	local orePoint = CFrame.new(0, top + 1.95, 0.3)
	attach(ctx.base, "OrePoint", orePoint)
	attach(ctx.base, "CamPoint", CFrame.lookAt(Vector3.new(0, top + 5.4, -4.6), orePoint.Position + Vector3.new(0, 0.1, 0)))
	attach(ctx.base, "Output", CFrame.new(3.6, top + 1.4, -0.4))
	attach(ctx.base, "Prompt", CFrame.new(0, top + 0.6, -2.4))
	local intake = attach(ctx.base, "Intake", orePoint)
	intake:SetAttribute("IntakeSize", Vector3.new(3.4, 2.6, 3.4))
	return ctx
end

local BUILDERS: { [string]: () -> Ctx } = {
	ClayFurnace = clayFurnace,
	Crusher = crusher,
	AutoCleaner = autoCleaner,
	BlastFurnace = blastFurnace,
	CleaningStation = cleaningStation,
}

function KitMachines.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

--[[
	Builds machine `id` at the local origin with the upgrade look `level`
	(0 = iron ... MaxLevel = crystal) in crystal theme `themeName`.
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

return KitMachines
