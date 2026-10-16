--[[
	Machine models (pure builders, used by the server and for build-mode ghosts).

	Style: the Kenney Factory Kit (docs/KENNEY_FACTORY_KIT.md, ART_DIRECTION
	section 9) rebuilt from parts in the forge palette: one soft blue-steel
	body colour with lighter tops and thick light frames around openings,
	sparse orange accents (base trims, feet, handles), dark red copper pipes
	with light flanges, open hoppers on top as the intake, squat piston tanks,
	cogs, glass pipe sections with molten metal, and water that pours out of
	pipes (the client animates the stream between WaterOut and WaterIn, see
	MachineFxController).

	Local space: origin = footprint center on the plot surface, front = -Z
	(LookVector). Every model has a PrimaryPart "Base" with Attachments:
	  Intake   center of the hopper's intake box (attribute IntakeSize: Vector3)
	  Output   where results are pushed out, at Grid.outputLocal (a cell
	           centre column, 0.5 studs in front of the footprint)
	  Prompt   where ProximityPrompts go
	  Status   above the model (machine billboards)
	  OrePoint / CamPoint   (Cleaning Station close-up; its Output is the tray)
	  AnvilPoint / CamPoint / IngotSlot1..4   (Anvil)
	  WaterOut / WaterIn   pipe outlet and where its water lands (Cleaning
	           Station, Auto Cleaner). Their Axis is the water's direction there,
	           attribute Curve = the Beam curve size; WaterOut.Spray = a shower.
	Conveyors are 6 parts: Base, Belt (tag ConveyorBelt), RailL, RailR, 2x Arrow;
	the rollers and hazard edges are painted on the belt, the axle caps on the
	rails (SurfaceGuis, no extra parts).
	Moving parts are named so the client can animate them (Roller1/2 + their
	Roller1Tooth/Roller2Tooth bars, the Crusher's side cogs Cog1/Cog2, Drum +
	DrumRib, BedRoller, Glow, Molten, StackRed/Amber/Green, WaterPool).
]]

local Geo = require(script.Parent.Geo)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Grid = require(script.Parent.Parent.Machines.Grid)

local MachineBuilder = {}

type Props = { [string]: any }
type Axis = "X" | "Y" | "Z"

local rgb = Color3.fromRGB
local C = {
	-- forged iron (ART_DIRECTION section 9): one soft body colour, lighter
	-- tops and frames so they catch the light, dark recesses for openings
	Housing = rgb(120, 128, 158),
	HousingTop = rgb(146, 154, 184),
	HousingLight = rgb(176, 182, 206),
	HousingDark = rgb(78, 80, 98),
	Recess = rgb(44, 44, 56),
	Floor = rgb(84, 88, 106),
	Copper = rgb(170, 88, 52),
	Brass = rgb(225, 185, 90),
	Hazard = rgb(255, 150, 36),
	HazardDark = rgb(40, 36, 40),
	Molten = rgb(255, 112, 26),
	Glow = rgb(255, 130, 40),
	Clay = rgb(150, 92, 76),
	ClayTop = rgb(168, 106, 90),
	ClayDark = rgb(100, 58, 46),
	Wood = rgb(150, 100, 58),
	WoodLight = rgb(196, 144, 92),
	WoodDark = rgb(100, 64, 38),
	Gold = rgb(255, 196, 72),
	Coin = rgb(228, 178, 62),
	Belt = rgb(40, 38, 44),
	Roller = rgb(118, 124, 146),
	Arrow = rgb(240, 160, 50),
	Cloth = rgb(240, 222, 190),
	Bristle = rgb(88, 62, 46),
	Glass = rgb(176, 222, 240),
	Screen = rgb(30, 40, 48),
	Gauge = rgb(220, 132, 40),
	Water = rgb(62, 152, 196),
	Red = rgb(235, 70, 60),
	Amber = rgb(255, 176, 40),
	Green = rgb(80, 210, 110),
}

-- Water look, shared by the client animation (MachineFxController) and the
-- preview gallery, so both draw the same stream.
MachineBuilder.Water = {
	Stream = rgb(150, 210, 240), -- the stream and the shower fan
	Deep = rgb(100, 174, 220), -- the stream's colour where it lands
	Core = rgb(196, 232, 250), -- faint highlight down the middle (stays see-through)
	Splash = rgb(222, 240, 252), -- droplets
	Pool = C.Water, -- basin water (part WaterPool)
	PoolTransparency = 0.22,
	Width = 0.42, -- stream width at the outlet...
	WidthEnd = 0.3, -- ...narrower where it lands (it speeds up while falling)
	SprayWidth = 0.7, -- shower fan: about the shower head at the top...
	SprayWidthEnd = 1.7, -- ...wide where it hits the ore
}

-- Warning-traffic stack light on the Auto Cleaner: only one lamp is lit (Neon),
-- the others are dimmed plastic. The built look lights `Lit`; the client
-- lights the lamp for the machine's state (MachineFxController).
MachineBuilder.Stack = {
	Lamps = { StackRed = C.Red, StackAmber = C.Amber, StackGreen = C.Green },
	Lit = "StackGreen",
	Dim = 0.5, -- unlit lamps: colour lerped this far toward black
}

-- The Crusher's side cogs: the small one (Cog2) turns this much faster than
-- the big one (Cog1) and the other way round.
local COG_BIG, COG_SMALL = 2.8, 1.9
MachineBuilder.CogRatio = COG_BIG / COG_SMALL

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass

local function merge(props: Props, extra: Props?): Props
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

-- Collides (main bodies, hopper walls, anything players or items bump into).
local function solid(extra: Props?): Props
	return merge({ CanTouch = false }, extra)
end

-- No collision, still casts a shadow (bigger trims and pipes).
local function prop(extra: Props?): Props
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false }, extra)
end

-- Small detail: no collision, no shadow.
local function tiny(extra: Props?): Props
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }, extra)
end

-- Copper and coins get a little shine (the rest stays matte plastic).
local function shine(color: Color3, props: Props): Props
	if props.Reflectance == nil and (color == C.Copper or color == C.Coin) then
		props.Reflectance = if color == C.Coin then 0.2 else 0.1
	end
	return props
end

local function attach(base: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = base
	return a
end

-- Output attachment at the shared grid position; returns it so lips and
-- chutes can line up with it.
local function output(base: BasePart, id: string): Vector3
	local position = Grid.outputLocal(id) :: Vector3
	attach(base, "Output", CFrame.new(position))
	return position
end

local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function emitter(parent: Instance, kind: string, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = kind
	if kind == "Smoke" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(3, 5)
		e.SpreadAngle = Vector2.new(10, 10)
		e.LightInfluence = 1
	else -- Embers
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.LightEmission = 1
		e.LightInfluence = 0
	end
	e.Rate = rate
	e.Parent = parent
	return e
end

local function newModel(id: string): (Model, Part)
	local machine = MachineData.ById[id]
	local w, d = machine.Size[1] * GameConfig.CellSize, machine.Size[2] * GameConfig.CellSize
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("MachineId", id)
	local base = Geo.block(model, CFrame.new(0, 0.15, 0), Vector3.new(w - 0.3, 0.3, d - 0.3), C.Floor, nil, solid({ Name = "Base" }))
	base.Name = "Base"
	model.PrimaryPart = base
	return model, base
end

-- Name plate: dark iron board, gold letters on its front (-Z) face.
local function sign(parent: Instance, cf: CFrame, text: string, width: number): Part
	local board = Geo.block(parent, cf, Vector3.new(width, 0.7, 0.15), C.HousingDark, nil, tiny())
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = C.Gold
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = gui
	return board
end

---------------------------------------------------------------- kit pieces

local AXIS: { [Axis]: CFrame } = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.pi / 2),
	Z = CFrame.Angles(0, math.pi / 2, 0),
}

-- Frame whose local Z is the world axis `axis` (a disc's normal).
local FACING: { [Axis]: CFrame } = {
	X = CFrame.Angles(0, math.pi / 2, 0),
	Y = CFrame.Angles(math.pi / 2, 0, 0),
	Z = CFrame.new(),
}

-- Cylinder along a local axis (Roblox cylinders run along X).
local function cyl(
	m: Instance,
	center: Vector3,
	axis: Axis,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Props?
): Part
	return Geo.make(
		"Part",
		merge({
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(center) * AXIS[axis],
			Size = Vector3.new(length, diameter, diameter),
			Color = color,
			Material = material or SMOOTH,
		}, shine(color, props or solid())),
		m
	)
end

local function ball(m: Instance, center: Vector3, diameter: number, color: Color3, props: Props?, material: Enum.Material?): Part
	return Geo.ball(m, center, diameter, color, material, shine(color, props or tiny()))
end

type HousingOptions = {
	Name: string?,
	FrontBevel: boolean?, -- bevel the top front edge too
	Top: Color3?, -- top slab and bevels (default: a lighter body colour)
	Skirt: boolean?, -- dark iron skirt with the orange trim on it
}

--[[
	Kenney "machine" body standing on `cf` (bottom centre): body block, a
	lighter top slab, bevelled left/right top edges and an orange base band
	(or a dark iron skirt carrying a thinner orange trim). Returns the body.
]]
local function housing(m: Instance, cf: CFrame, size: Vector3, color: Color3, bevel: number, options: HousingOptions?): Part
	local o: HousingOptions = options or {}
	local w, h, d = size.X, size.Y, size.Z
	local top = o.Top or (if color == C.Housing then C.HousingTop else color)
	local body =
		Geo.block(m, cf * CFrame.new(0, (h - bevel) / 2, 0), Vector3.new(w, h - bevel, d), color, nil, solid({ Name = o.Name or "Body" }))
	local front = if o.FrontBevel then bevel else 0
	Geo.block(m, cf * CFrame.new(0, h - bevel / 2, front / 2), Vector3.new(w - 2 * bevel, bevel, d - front), top, nil, solid())
	if o.FrontBevel then
		Geo.wedge(m, cf * CFrame.new(0, h - bevel / 2, -d / 2 + bevel / 2), Vector3.new(w - 2 * bevel, bevel, bevel), top, nil, solid())
	end
	for _, side in { -1, 1 } do
		-- wedge: tall side inward, slope down to the outer edge
		Geo.wedge(
			m,
			cf * CFrame.new(side * (w / 2 - bevel / 2), h - bevel / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Vector3.new(d, bevel, bevel),
			top,
			nil,
			solid()
		)
	end
	if o.Skirt then
		Geo.block(m, cf * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.16, 0.8, d + 0.16), C.HousingDark, nil, prop())
		Geo.block(m, cf * CFrame.new(0, 0.42, 0), Vector3.new(w + 0.24, 0.3, d + 0.24), C.Hazard, nil, tiny())
	else
		Geo.block(m, cf * CFrame.new(0, 0.28, 0), Vector3.new(w + 0.12, 0.56, d + 0.12), C.Hazard, nil, prop())
	end
	return body
end

--[[
	Thick light frame around an opening in a wall that faces -Z, with a dark
	recess filling the opening. `cf` = bottom centre of the opening on the wall
	surface. `sill` closes the frame at the bottom (a window).
]]
local function portal(m: Instance, cf: CFrame, w: number, h: number, t: number, depth: number, sill: boolean?)
	local z = -depth / 2 + 0.05
	local low = if sill then -t else 0
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(side * (w / 2 + t / 2), (low + h + t) / 2, z),
			Vector3.new(t, h + t - low, depth),
			C.HousingLight,
			nil,
			prop()
		)
	end
	Geo.block(m, cf * CFrame.new(0, h + t / 2, z), Vector3.new(w, t, depth), C.HousingLight, nil, prop())
	if sill then
		Geo.block(m, cf * CFrame.new(0, -t / 2, z), Vector3.new(w, t, depth), C.HousingLight, nil, prop())
	end
	Geo.block(m, cf * CFrame.new(0, h / 2, -0.04), Vector3.new(w, h, 0.1), C.Recess, nil, tiny())
end

--[[
	Kenney hopper-square: a tapered neck (4 wedges), a light collar band and an
	open cup (4 walls) with a dark throat floor. `cf` = bottom centre of the
	taper. Returns the height of the cup rim above `cf`. 10 parts.
]]
local function squareHopper(m: Instance, cf: CFrame, bottomW: number, topW: number, taperH: number, cupH: number, wall: number): number
	local run = (topW - bottomW) / 2
	for i = 0, 3 do
		local side = cf * CFrame.Angles(0, i * math.pi / 2, 0)
		-- upside-down wedge: flat face on top, slope down toward the middle
		Geo.wedge(
			m,
			side * CFrame.new(0, taperH / 2, -(bottomW / 2 + run / 2)) * CFrame.Angles(0, 0, math.pi),
			Vector3.new(topW, taperH, run),
			C.Housing,
			nil,
			solid()
		)
	end
	local collar = 0.45
	Geo.block(m, cf * CFrame.new(0, taperH + collar / 2, 0), Vector3.new(topW + 0.3, collar, topW + 0.3), C.HousingLight, nil, solid())
	local cupY = taperH + collar
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(0, cupY + cupH / 2, side * (topW / 2 - wall / 2)),
			Vector3.new(topW, cupH, wall),
			C.Housing,
			nil,
			solid()
		)
		Geo.block(
			m,
			cf * CFrame.new(side * (topW / 2 - wall / 2), cupY + cupH / 2, 0),
			Vector3.new(wall, cupH, topW - 2 * wall),
			C.Housing,
			nil,
			solid()
		)
	end
	Geo.block(m, cf * CFrame.new(0, cupY + 0.05, 0), Vector3.new(topW - 2 * wall, 0.1, topW - 2 * wall), C.Recess, nil, solid())
	return cupY + cupH
end

--[[
	Kenney hopper-round: an open octagonal cup (8 wall blocks, the inner wall
	shows) with a dark floor sunk 0.6 below the rim, a light collar band round
	its foot, a funnel of two stepped rings and an optional neck.
	`bottom` = bottom centre, `d` = cup width across the flats. Returns the
	rim height. 12 parts (+1 with a neck).
]]
local function roundHopper(m: Instance, bottom: Vector3, d: number, neck: number): number
	local cf = CFrame.new(bottom)
	local y = 0
	if neck > 0 then
		cyl(m, bottom + Vector3.new(0, neck / 2, 0), "Y", neck, d * 0.42, C.Housing, nil, solid())
		y = neck
	end
	-- funnel: two stepped rings narrowing down to the neck (wedges would
	-- show fins at the corners of a round funnel)
	local stepH = d * 0.15
	cyl(m, bottom + Vector3.new(0, y + stepH / 2, 0), "Y", stepH, d * 0.56, C.Housing, nil, solid())
	y += stepH
	cyl(m, bottom + Vector3.new(0, y + stepH / 2, 0), "Y", stepH, d * 0.8, C.Housing, nil, solid())
	y += stepH
	-- octagonal cup: 8 walls whose outer corners meet
	local wall = 0.22
	local cupH = d * 0.42
	local apothem = d / 2
	local side = 2 * apothem * math.tan(math.pi / 8) + 0.02
	for i = 0, 7 do
		Geo.block(
			m,
			cf * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, y + cupH / 2, -(apothem - wall / 2)),
			Vector3.new(side, cupH, wall),
			C.Housing,
			nil,
			solid()
		)
	end
	-- light collar band round the foot of the cup
	local collarH = cupH * 0.42
	cyl(m, bottom + Vector3.new(0, y + collarH / 2, 0), "Y", collarH, d * 1.16, C.HousingLight, nil, solid())
	-- dark floor, reaching the inner corners
	local rim = y + cupH
	cyl(m, bottom + Vector3.new(0, rim - 0.6, 0), "Y", 0.1, (apothem - wall) * 2 * 1.08, C.Recess, nil, solid())
	return bottom.Y + rim
end

--[[
	Kenney piston-round as a fuel/water tank: a squat copper body, a light
	band right under a wide, thick iron cap (about a quarter of the height).
	Returns the top of the cap. 3 parts.
]]
local function tank(m: Instance, bottom: Vector3, d: number, h: number, name: string?): number
	local capH = h * 0.27
	local bandH = 0.22
	local body = h - capH - bandH
	cyl(m, bottom + Vector3.new(0, body / 2, 0), "Y", body, d, C.Copper, nil, solid({ Name = name or "Tank" }))
	cyl(m, bottom + Vector3.new(0, body + bandH / 2, 0), "Y", bandH, d + 0.12, C.HousingLight, nil, prop())
	cyl(m, bottom + Vector3.new(0, body + bandH + capH / 2, 0), "Y", capH, d + 0.7, C.Housing, nil, solid())
	return bottom.Y + h
end

--[[
	Valve hand wheel facing along `axis`: an orange hexagon rim, two crossed
	spokes and a brass hub axle reaching back to the valve body at `bodyAt`
	(on the same axis line). 9 parts.
]]
local function wheel(m: Instance, center: Vector3, axis: Axis, d: number, bodyAt: Vector3)
	local frame = CFrame.new(center) * FACING[axis]
	local r = d / 2
	local bar = 0.13
	local apothem = r * math.cos(math.pi / 6)
	for k = 0, 5 do
		Geo.block(
			m,
			frame * CFrame.Angles(0, 0, k * math.pi / 3) * CFrame.new(apothem - bar / 2, 0, 0),
			Vector3.new(bar, r + 0.03, bar),
			C.Hazard,
			nil,
			tiny()
		)
	end
	-- spokes: one across the flats, one corner to corner
	Geo.block(m, frame, Vector3.new(2 * apothem - bar, 0.09, 0.09), C.Hazard, nil, tiny())
	Geo.block(m, frame, Vector3.new(0.09, 2 * r - 2 * bar, 0.09), C.Hazard, nil, tiny())
	cyl(m, (center + bodyAt) / 2, axis, (center - bodyAt).Magnitude + 0.14, 0.24, C.Brass, nil, tiny())
end

--[[
	Kenney pipe-large-valve: a light bulge round the pipe and a small orange
	T-handle sticking out of it toward `dir`. 3 parts.
]]
local function valve(m: Instance, center: Vector3, axis: Axis, pipeD: number, dir: Vector3)
	cyl(m, center, axis, 0.45, pipeD * 1.45, C.HousingLight, nil, prop())
	local axisVector = if axis == "X" then Vector3.xAxis elseif axis == "Y" then Vector3.yAxis else Vector3.zAxis
	local out = dir.Unit
	local stemFrom = center + out * (pipeD * 0.66)
	Geo.block(m, CFrame.lookAt(stemFrom + out * 0.18, stemFrom + out), Vector3.new(0.16, 0.16, 0.36), C.HousingDark, nil, tiny())
	local tip = stemFrom + out * 0.4
	Geo.block(m, CFrame.lookAt(tip, tip + axisVector:Cross(out)), Vector3.new(0.18, 0.18, 0.75), C.Hazard, nil, tiny())
end

--[[
	Kenney cog: disc, `bars` tooth bars (2 teeth each) and a hub axle that
	reaches `axle` studs back into the housing (toward -side on X). Turns
	around X; every part carries `name` so the client spins them together.
]]
local function cog(m: Instance, center: Vector3, d: number, thick: number, bars: number, side: number, axle: number, name: string)
	cyl(m, center, "X", thick, d * 0.8, C.Brass, nil, tiny({ Name = name }))
	for k = 0, bars - 1 do
		Geo.block(
			m,
			CFrame.new(center) * CFrame.Angles(k * math.pi / bars, 0, 0),
			Vector3.new(thick, d * 0.17, d),
			C.Brass,
			nil,
			tiny({ Name = name })
		)
	end
	local inner = center.X - side * (thick / 2 + axle)
	local outer = center.X + side * (thick / 2 + 0.08)
	cyl(m, Vector3.new((inner + outer) / 2, center.Y, center.Z), "X", math.abs(outer - inner), d * 0.3, C.Housing, nil, tiny({ Name = name }))
end

-- CFrame at `position` whose Axis (local X) points along `axis`.
local function axisFrame(position: Vector3, axis: Vector3): CFrame
	local x = axis.Unit
	local ref = if math.abs(x.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(position, x, y, z)
end

--[[
	WaterOut / WaterIn for a pipe whose outlet at `outlet` points along `dir`
	and whose water lands at `landing`. The Beam curve imitates a falling jet:
	the two control points sit on the tangents of a parabola (start tangent
	= `dir`), so Beam (P1 = out + out.Axis * Curve, P2 = in - in.Axis * Curve)
	draws the arc.
]]
local function water(base: BasePart, outlet: Vector3, dir: Vector3, landing: Vector3, spray: boolean?)
	local flat = Vector3.new(landing.X - outlet.X, 0, landing.Z - outlet.Z)
	local q = if flat.Magnitude < 0.05 or math.abs(dir.Unit.Y) > 0.9
		then (outlet + landing) / 2
		else outlet + dir.Unit * (flat.Magnitude / 2)
	local p1 = outlet + (q - outlet) * (2 / 3)
	local p2 = landing + (q - landing) * (2 / 3)
	-- attachments live in the Base's space (its centre is 0.15 above the pad)
	local out = attach(base, "WaterOut", axisFrame(base.CFrame:PointToObjectSpace(outlet), p1 - outlet))
	out:SetAttribute("Curve", (p1 - outlet).Magnitude)
	if spray then
		out:SetAttribute("Spray", true)
	end
	local into = attach(base, "WaterIn", axisFrame(base.CFrame:PointToObjectSpace(landing), landing - p2))
	into:SetAttribute("Curve", (landing - p2).Magnitude)
end

---------------------------------------------------------------- machines

--[[
	Cleaning Station (3x2): Kenney machine-bed workbench (iron cabinet with a
	framed knee opening and drawers, dark wooden top, vent grille at the back),
	vise at OrePoint, a copper water pipe with a valve wheel pouring into a
	copper wash tub left of the vise (WaterOut -> WaterIn), tool board,
	screen-panel-small, lever-double, lamp, output tray. 70 parts.
]]
local function cleaningStation(): Model
	local model, base = newModel("CleaningStation")
	local top = 3.4 -- bench reference height (the plank top is top + 0.3)
	local benchZ = 0.4
	-- bench cabinet (y 0.3..3.3, z -1.9..2.7) and its framed knee opening
	Geo.block(model, CFrame.new(0, 1.8, benchZ), Vector3.new(10, 3, 4.6), C.Housing, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 0.58, benchZ), Vector3.new(10.12, 0.56, 4.72), C.Hazard, nil, prop())
	portal(model, CFrame.new(0, 0.85, benchZ - 2.3), 3.8, 1.95, 0.5, 0.5)
	-- drawers on both side panels
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 3.65, 1.85, benchZ - 2.34), Vector3.new(2.2, 1.5, 0.08), C.HousingDark, nil, tiny())
		Geo.block(model, CFrame.new(side * 3.65, 2.3, benchZ - 2.42), Vector3.new(1.0, 0.18, 0.16), C.HousingLight, nil, tiny())
	end
	sign(model, CFrame.new(0, 3.05, benchZ - 2.84), "CLEANING STATION", 4.6)
	-- vent grille on the back panel
	Geo.block(model, CFrame.new(2.6, 1.9, benchZ + 2.33), Vector3.new(2.8, 1.3, 0.08), C.Recess, nil, tiny())
	Geo.block(model, CFrame.new(2.6, 1.9, benchZ + 2.4), Vector3.new(2.9, 0.22, 0.14), C.HousingLight, nil, tiny())
	-- dark wooden work top
	Geo.block(model, CFrame.new(0, top + 0.1, benchZ), Vector3.new(10.8, 0.4, 5.4), C.WoodDark, nil, solid({ Name = "Bench" }))
	-- work slab + vise (screw and T handle out to the front)
	Geo.block(model, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), C.HousingDark, nil, solid({ Name = "WorkSlab" }))
	for _, x in { -1.75, 1.75 } do
		Geo.block(model, CFrame.new(x, top + 0.95, 0.3), Vector3.new(0.5, 0.5, 2.2), C.HousingLight, nil, solid({ Name = "Jaw" }))
	end
	cyl(model, Vector3.new(-1.75, top + 0.95, -1.2), "Z", 0.8, 0.22, C.Brass, nil, tiny())
	Geo.block(model, CFrame.new(-1.75, top + 0.95, -1.62), Vector3.new(1.2, 0.14, 0.14), C.Brass, nil, tiny())

	-- copper wash tub left of the vise (rim 3.7..4.8, water top 4.62) with a
	-- light band (one block hidden in the tub floor, only its lip shows)
	local bx, bz, bw, bd, bh, t = -4.15, -0.5, 2.3, 2.6, 1.1, 0.22
	local by = top + 0.3
	for _, side in { -1, 1 } do
		Geo.block(
			model,
			CFrame.new(bx, by + bh / 2, bz + side * (bd / 2 - t / 2)),
			Vector3.new(bw, bh, t),
			C.Copper,
			nil,
			solid({ Reflectance = 0.1 })
		)
		Geo.block(
			model,
			CFrame.new(bx + side * (bw / 2 - t / 2), by + bh / 2, bz),
			Vector3.new(t, bh, bd - 2 * t),
			C.Copper,
			nil,
			solid({ Reflectance = 0.1 })
		)
	end
	Geo.block(model, CFrame.new(bx, by + 0.3, bz), Vector3.new(bw - 2 * t, 0.6, bd - 2 * t), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(bx, by + 0.36, bz), Vector3.new(bw + 0.08, 0.2, bd + 0.08), C.HousingLight, nil, tiny())
	local poolTop = by + 0.92
	Geo.block(
		model,
		CFrame.new(bx, poolTop - 0.06, bz),
		Vector3.new(bw - 2 * t, 0.12, bd - 2 * t),
		MachineBuilder.Water.Pool,
		nil,
		tiny({ Name = "WaterPool", Transparency = MachineBuilder.Water.PoolTransparency, Reflectance = 0.1 })
	)

	-- copper water pipe: floor flange, riser with a valve (hand wheel facing
	-- the station's left side), elbow, run over the tub to a flanged outlet
	local pz, pipeY, outZ, valveY = 2.7, 7.3, 0.05, 5.5
	cyl(model, Vector3.new(bx, by + 0.14, pz), "Y", 0.28, 1.0, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(bx, (by + pipeY) / 2, pz), "Y", pipeY - by, 0.6, C.Copper, nil, solid())
	cyl(model, Vector3.new(bx, valveY, pz), "Y", 0.7, 0.95, C.HousingLight, nil, prop())
	wheel(model, Vector3.new(bx - 0.78, valveY, pz), "X", 1.1, Vector3.new(bx - 0.44, valveY, pz))
	ball(model, Vector3.new(bx, pipeY, pz), 0.7, C.Copper, prop())
	cyl(model, Vector3.new(bx, pipeY, (pz + outZ) / 2 + 0.07), "Z", pz - outZ - 0.14, 0.6, C.Copper, nil, prop())
	cyl(model, Vector3.new(bx, pipeY, outZ + 0.12), "Z", 0.28, 0.95, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(bx, pipeY, outZ - 0.03), "Z", 0.04, 0.46, C.Recess, nil, tiny())
	water(base, Vector3.new(bx, pipeY - 0.06, outZ - 0.05), Vector3.new(0, 0, -1), Vector3.new(bx, poolTop, bz - 0.2))

	-- tool board at the back: chisel, hammer, brush
	local boardZ = 2.85
	Geo.block(model, CFrame.new(-0.6, top + 1.6, boardZ), Vector3.new(3.6, 2.6, 0.25), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(-0.6, top + 2.98, boardZ), Vector3.new(3.7, 0.24, 0.34), C.HousingLight, nil, tiny())
	local toolZ = boardZ - 0.22
	Geo.block(model, CFrame.new(-1.9, top + 1.4, toolZ), Vector3.new(0.2, 1.1, 0.14), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(-1.9, top + 2.25, toolZ), Vector3.new(0.3, 0.7, 0.24), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), C.HousingDark, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 2.05, toolZ), Vector3.new(0.24, 1.0, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 1.3, toolZ), Vector3.new(0.7, 0.55, 0.3), C.Cloth, nil, tiny())

	-- screen-panel-small: two legs in front of a panel, dark glass screen
	-- with an amber gauge bar
	for _, x in { 2.05, 3.15 } do
		Geo.block(model, CFrame.new(x, top + 1.1, 2.55), Vector3.new(0.28, 1.6, 0.28), C.HousingLight, nil, prop())
	end
	Geo.block(model, CFrame.new(2.6, top + 1.95, 2.8), Vector3.new(1.8, 1.3, 0.3), C.Housing, nil, prop())
	Geo.block(model, CFrame.new(2.6, top + 2.05, 2.63), Vector3.new(1.4, 0.85, 0.06), C.Screen, nil, tiny({ Name = "Screen", Reflectance = 0.25 }))
	Geo.block(model, CFrame.new(2.45, top + 1.92, 2.59), Vector3.new(0.85, 0.12, 0.03), C.Gauge, NEON, tiny({ Name = "Gauge" }))

	-- lever-double on the top, right behind the tray: two uprights holding an
	-- orange grip
	local lx, lz = 4.7, 1.55
	Geo.block(model, CFrame.new(lx, top + 0.42, lz), Vector3.new(1.0, 0.24, 1.0), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(lx, top + 0.64, lz), Vector3.new(0.7, 0.22, 0.7), C.Housing, nil, tiny())
	for _, side in { -1, 1 } do
		Geo.block(
			model,
			CFrame.new(lx + side * 0.24, top + 0.92, lz) * CFrame.Angles(math.rad(-22), 0, 0),
			Vector3.new(0.12, 0.62, 0.16),
			C.HousingLight,
			nil,
			tiny()
		)
	end
	cyl(model, Vector3.new(lx, top + 1.22, lz - 0.12), "X", 0.66, 0.24, C.Hazard, nil, tiny())

	-- lamp (upper right, out of the close-up camera's view)
	Geo.block(model, CFrame.new(5.1, top + 2.6, 2.8), Vector3.new(0.35, 4.6, 0.35), C.HousingDark, nil, solid())
	local armFrom, armTo = Vector3.new(5.1, top + 4.75, 2.8), Vector3.new(3.4, top + 4.75, 1.6)
	Geo.block(
		model,
		CFrame.lookAt((armFrom + armTo) / 2, armTo),
		Vector3.new(0.24, 0.24, (armTo - armFrom).Magnitude),
		C.HousingDark,
		nil,
		tiny()
	)
	Geo.block(model, CFrame.new(3.3, top + 4.55, 1.5), Vector3.new(1.3, 0.55, 1.3), C.HousingLight, nil, tiny({ Name = "LampShade" }))
	local bulb = ball(model, Vector3.new(3.3, top + 4.18, 1.5), 0.5, rgb(255, 214, 150), tiny({ Name = "LampBulb" }), NEON)
	light(bulb, rgb(255, 214, 160), 14, 1.6)

	-- output tray on the right
	Geo.block(model, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), C.HousingDark, nil, solid({ Name = "Tray" }))
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(3.6, top + 0.8, -0.4 + side * 1.25), Vector3.new(2.6, 0.5, 0.15), C.HousingLight, nil, solid())
		Geo.block(model, CFrame.new(3.6 + side * 1.25, top + 0.8, -0.4), Vector3.new(0.15, 0.5, 2.6), C.HousingLight, nil, solid())
	end

	local orePoint = CFrame.new(0, top + 1.95, 0.3)
	attach(base, "OrePoint", orePoint)
	-- close-up camera: in front and above, looking down at about 35 degrees
	attach(base, "CamPoint", CFrame.lookAt(Vector3.new(0, top + 5.4, -4.6), orePoint.Position + Vector3.new(0, 0.1, 0)))
	attach(base, "Output", CFrame.new(3.6, top + 1.4, -0.4))
	attach(base, "Prompt", CFrame.new(0, top + 0.6, -2.4))
	local intake = attach(base, "Intake", orePoint)
	intake:SetAttribute("IntakeSize", Vector3.new(3.4, 2.6, 3.4))
	return model
end

-- Storage Crate (retired): a closed Kenney box-large with a tape band and a
-- dark slot in the top (the intake), inside a structure-yellow-high frame.
local function storageCrate(): Model
	local model, base = newModel("StorageCrate")
	Geo.block(model, CFrame.new(0, 2.1, 0.2), Vector3.new(5.6, 3.6, 5.6), C.WoodLight, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 2.1, 0.2), Vector3.new(1.4, 3.64, 5.66), C.Cloth, nil, prop())
	Geo.block(model, CFrame.new(0, 3.92, -0.6), Vector3.new(3.6, 0.06, 0.8), C.Recess, nil, tiny())
	for _, x in { -3.1, 3.1 } do
		for _, z in { -2.85, 3.25 } do
			cyl(model, Vector3.new(x, 2.55, z), "Y", 4.5, 0.5, C.HousingLight, nil, prop())
			cyl(model, Vector3.new(x, 3.4, z), "Y", 0.5, 0.78, C.Hazard, nil, tiny())
		end
	end
	for _, z in { -2.85, 3.25 } do
		Geo.block(model, CFrame.new(0, 3.4, z), Vector3.new(6.2, 0.3, 0.3), C.Hazard, nil, tiny())
	end
	local label = sign(model, CFrame.new(0, 2.4, -2.68), "0/60", 2.4)
	label.Name = "CountSign"
	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	output(base, "StorageCrate")
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.2))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 2.4, 6))
	return model
end

--[[
	Clay Furnace (2x2): Kenney machine-fortified in terracotta brick (dark
	mortar courses, a dark iron skirt carrying the orange trim, a bolted iron
	strap over the top), a framed glowing mouth with a latch near the output,
	an open round hopper on top (intake) and a large flanged copper chimney.
]]
local function clayFurnace(): Model
	local model, base = newModel("ClayFurnace")
	local z0 = 0.6
	housing(model, CFrame.new(0, 0.3, z0), Vector3.new(6.6, 5.0, 6.0), C.Clay, 0.8, { FrontBevel = true, Top = C.ClayTop, Skirt = true })
	for _, y in { 1.9, 3.05, 4.2 } do
		Geo.block(model, CFrame.new(0, y, z0), Vector3.new(6.66, 0.2, 6.06), C.ClayDark, nil, tiny())
	end
	-- fortified iron strap over the top, bolted at the front and the back
	-- (front plate, a wedge over the rounded front edge, top plate, back plate)
	local strapX = -1.9
	Geo.block(model, CFrame.new(strapX, 2.53, z0 - 3.1), Vector3.new(1.2, 3.94, 0.2), C.HousingLight, nil, prop())
	Geo.wedge(model, CFrame.new(strapX, 4.93, z0 - 2.63), Vector3.new(1.2, 0.86, 0.86), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(strapX, 5.38, z0 + 0.5), Vector3.new(1.2, 0.16, 5.4), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(strapX, 2.95, z0 + 3.1), Vector3.new(1.2, 4.9, 0.2), C.HousingLight, nil, prop())
	for _, y in { 1.5, 3.7 } do
		ball(model, Vector3.new(strapX, y, z0 - 3.22), 0.32, C.Brass)
		ball(model, Vector3.new(strapX, y, z0 + 3.22), 0.32, C.Brass)
	end
	-- glowing mouth in a thick frame with a latch, toward the output column
	local out = output(base, "ClayFurnace")
	local mouthX = 1.45
	portal(model, CFrame.new(mouthX, 0.85, z0 - 3.0), 2.3, 2.25, 0.45, 0.5)
	local glow = Geo.block(model, CFrame.new(mouthX, 1.6, z0 - 3.07), Vector3.new(2.1, 1.4, 0.12), C.Glow, NEON, tiny({ Name = "Glow" }))
	light(glow, C.Glow, 12, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	Geo.block(model, CFrame.new(mouthX + 1.38, 1.95, z0 - 3.5), Vector3.new(0.22, 0.5, 0.14), C.Brass, nil, tiny())
	Geo.wedge(model, CFrame.new(out.X - 0.1, 0.65, z0 - 3.85), Vector3.new(1.6, 0.7, 1.5), C.HousingLight, nil, solid())
	sign(model, CFrame.new(mouthX, 3.4, z0 - 3.55), "CLAY FURNACE", 3.2)
	-- large pipe chimney at the back left, bolted flanges
	local cx, cz = -1.9, 2.15
	cyl(model, Vector3.new(cx, 5.5, cz), "Y", 0.4, 1.9, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 7.0, cz), "Y", 3.4, 1.3, C.Copper, nil, solid())
	cyl(model, Vector3.new(cx, 8.55, cz), "Y", 0.4, 1.9, C.HousingLight, nil, prop())
	for _, y in { 5.72, 8.77 } do
		for _, a in { -2.2, -0.94 } do
			ball(model, Vector3.new(cx + math.cos(a) * 0.72, y, cz + math.sin(a) * 0.72), 0.2, C.Brass)
		end
	end
	local chimneyTop = cyl(model, Vector3.new(cx, 8.8, cz), "Y", 0.1, 1.2, C.Glow, NEON, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", rgb(110, 100, 96), 2)
	-- open round hopper on top (the intake)
	roundHopper(model, Vector3.new(0.9, 5.3, 0.45), 2.8, 0.3)

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return model
end

--[[
	Blast Furnace (3x3): Kenney machine-connection-pipe on a plinth: a tall
	iron body with straps (front and back), a barred molten window (Glow), a
	high square hopper (intake), a tap whose big glass pipe section shows the
	molten metal running into an ingot mould at the output, two squat
	piston-round fuel tanks piped in with large flanged copper pipes (the
	front one through a glass riser of glowing fuel, the back one through a
	valve), a tall flanged chimney and a warning-orange beacon.
]]
local function blastFurnace(): Model
	local model, base = newModel("BlastFurnace")
	-- plinth with an orange edge band on its sides (below its top face)
	Geo.block(model, CFrame.new(0, 0.6, 0.15), Vector3.new(11.6, 0.6, 10.9), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(0, 0.7, 0.15), Vector3.new(11.72, 0.16, 11.02), C.Hazard, nil, tiny())
	local bz = 0.8
	housing(model, CFrame.new(0, 0.9, bz), Vector3.new(6.8, 7.0, 6.4), C.Housing, 0.9)
	local front = bz - 3.2
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 2.55, 4.2, front - 0.1), Vector3.new(0.9, 5.5, 0.2), C.HousingLight, nil, prop())
	end
	-- bolted strap across the back
	Geo.block(model, CFrame.new(0, 4.6, bz + 3.3), Vector3.new(5.4, 0.9, 0.2), C.HousingLight, nil, prop())
	for _, x in { -2.2, 2.2 } do
		ball(model, Vector3.new(x, 4.6, bz + 3.42), 0.34, C.Brass)
	end
	-- molten window behind a grate
	portal(model, CFrame.new(0, 3.2, front), 3.0, 2.4, 0.4, 0.5, true)
	local glow = Geo.block(model, CFrame.new(0, 4.4, front - 0.07), Vector3.new(3.0, 2.4, 0.12), C.Glow, NEON, tiny({ Name = "Glow" }))
	light(glow, C.Glow, 17, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	for _, x in { -0.5, 0.5 } do
		Geo.block(model, CFrame.new(x, 4.4, front - 0.17), Vector3.new(0.16, 2.4, 0.1), C.HousingDark, nil, tiny())
	end
	sign(model, CFrame.new(0, 6.75, front - 0.08), "BLAST FURNACE", 3.9)
	-- tap: body flange, a big glass section with molten metal, flange, elbow
	-- down into an ingot mould at the output
	local out = output(base, "BlastFurnace")
	local tapY = 2.0
	cyl(model, Vector3.new(out.X, tapY, front - 0.15), "Z", 0.3, 1.5, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(out.X, tapY, front - 1.05), "Z", 1.5, 1.3, C.Glass, GLASS, tiny({ Transparency = 0.5 }))
	cyl(model, Vector3.new(out.X, tapY, front - 1.05), "Z", 1.52, 0.62, C.Molten, NEON, tiny({ Name = "Molten" }))
	cyl(model, Vector3.new(out.X, tapY, front - 1.92), "Z", 0.25, 1.5, C.HousingLight, nil, prop())
	ball(model, Vector3.new(out.X, tapY, front - 2.3), 1.0, C.Housing, prop())
	Geo.block(model, CFrame.new(out.X, 1.42, front - 2.3), Vector3.new(0.2, 0.26, 0.2), C.Molten, NEON, tiny({ Name = "Molten" }))
	Geo.block(model, CFrame.new(out.X, 1.1, front - 2.3), Vector3.new(1.5, 0.4, 1.1), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(out.X, 1.32, front - 2.3), Vector3.new(1.2, 0.06, 0.8), C.Molten, NEON, tiny({ Name = "Molten" }))
	-- high square hopper on top (the intake)
	squareHopper(model, CFrame.new(0, 7.9, 0.6), 3.2, 5.0, 1.3, 1.5, 0.4)
	-- warning-orange beacon at the front left corner of the plinth: base nut,
	-- light post, collar, orange dome
	local wx, wz = -4.7, -4.3
	cyl(model, Vector3.new(wx, 1.0, wz), "Y", 0.22, 0.95, C.HousingLight, nil, tiny())
	cyl(model, Vector3.new(wx, 2.0, wz), "Y", 1.9, 0.42, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(wx, 3.02, wz), "Y", 0.26, 0.72, C.Housing, nil, tiny())
	ball(model, Vector3.new(wx, 3.18, wz), 0.62, C.Hazard, tiny({ Name = "Beacon" }))
	-- tall flanged chimney at the back left, standing on the plinth
	local cx, cz = -4.6, 3.4
	cyl(model, Vector3.new(cx, 1.1, cz), "Y", 0.4, 2.2, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 6.85, cz), "Y", 11.1, 1.5, C.Copper, nil, solid())
	cyl(model, Vector3.new(cx, 7.2, cz), "Y", 0.4, 2.0, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 12.4, cz), "Y", 0.45, 2.2, C.HousingLight, nil, prop())
	local chimneyTop = cyl(model, Vector3.new(cx, 12.66, cz), "Y", 0.1, 1.3, C.Glow, NEON, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", rgb(110, 100, 96), 5)
	-- fuel tanks on the right, piped into the body with large copper pipes
	local tx, pipeY, entry = 4.72, 5.65, 3.4
	for i, tz in { -1.0, 2.6 } do
		local capTop = tank(model, Vector3.new(tx, 0.9, tz), 2.0, 2.5)
		if i == 1 then
			-- glass riser: flange, glass with glowing fuel, flange
			cyl(model, Vector3.new(tx, capTop + 0.1, tz), "Y", 0.2, 1.45, C.HousingLight, nil, prop())
			cyl(model, Vector3.new(tx, capTop + 0.9, tz), "Y", 1.4, 1.3, C.Glass, GLASS, tiny({ Transparency = 0.5 }))
			cyl(model, Vector3.new(tx, capTop + 0.9, tz), "Y", 1.42, 0.62, C.Molten, NEON, tiny({ Name = "Molten" }))
			cyl(model, Vector3.new(tx, capTop + 1.7, tz), "Y", 0.2, 1.45, C.HousingLight, nil, prop())
		else
			cyl(model, Vector3.new(tx, (capTop + pipeY) / 2, tz), "Y", pipeY - capTop, 1.0, C.Copper, nil, prop())
			valve(model, Vector3.new(tx, capTop + 0.75, tz), "Y", 1.0, Vector3.new(1, 0, 0))
		end
		ball(model, Vector3.new(tx, pipeY, tz), 1.15, C.Copper, prop())
		cyl(model, Vector3.new((tx + entry) / 2, pipeY, tz), "X", tx - entry, 1.0, C.Copper, nil, prop())
		cyl(model, Vector3.new(entry + 0.15, pipeY, tz), "X", 0.3, 1.45, C.HousingLight, nil, prop())
	end

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return model
end

--[[
	Crusher (2x2): Kenney machine-window housing with a high square hopper,
	the intake, holding two dark rollers with steel tooth ridges low in
	its dark throat, a big cog-a and a smaller cog-c meshing on each side of
	the housing (Cog1 / Cog2, they turn with the rollers), an output slot with
	a chute, hazard chevrons and a piston-square drive at the back.
]]
local function crusher(): Model
	local model, base = newModel("Crusher")
	local bz = 0.35
	housing(model, CFrame.new(0, 0.3, bz), Vector3.new(6.2, 4.0, 5.0), C.Housing, 0.6)
	local front = bz - 2.5
	-- window (front left)
	portal(model, CFrame.new(-1.4, 1.5, front), 1.8, 1.4, 0.35, 0.4, true)
	Geo.block(model, CFrame.new(-1.4, 2.2, front - 0.1), Vector3.new(1.8, 1.4, 0.06), C.Glass, GLASS, tiny({ Transparency = 0.35 }))
	-- output slot and chute (front right, at the output column)
	local out = output(base, "Crusher")
	portal(model, CFrame.new(out.X, 0.75, front), 1.6, 1.05, 0.3, 0.4)
	Geo.wedge(model, CFrame.new(out.X, 0.55, front - 0.75), Vector3.new(1.5, 0.5, 1.3), C.HousingLight, nil, solid())
	-- hazard chevrons on the base band
	for _, x in { -2.5, -1.9, -1.3, -0.7 } do
		Geo.block(
			model,
			CFrame.new(x, 0.58, front - 0.09) * CFrame.Angles(0, 0, math.rad(40)),
			Vector3.new(0.22, 0.62, 0.04),
			C.HazardDark,
			nil,
			tiny()
		)
	end
	-- high square hopper (cup 5.85..7.1) with the rollers low in its throat
	squareHopper(model, CFrame.new(0, 4.3, bz), 3.6, 5.8, 1.1, 1.25, 0.4)
	local rollerY = 5.8
	for i, dz in { -0.95, 0.95 } do
		local c = Vector3.new(0, rollerY, bz + dz)
		cyl(model, c, "X", 4.9, 1.5, C.HousingDark, nil, solid({ Name = "Roller" .. i }))
		for k = 0, 2 do
			Geo.block(
				model,
				CFrame.new(c) * CFrame.Angles(k * math.pi / 3, 0, 0),
				Vector3.new(4.8, 2.1, 0.2),
				C.HousingLight,
				nil,
				tiny({ Name = "Roller" .. i .. "Tooth" })
			)
		end
	end
	-- a big and a small cog meshing on both sides of the housing, on axle
	-- stubs (both sides share the axis lines, so each pair turns as one)
	local cogX = 3.1 + 0.22
	local bigY, bigZ = 2.75, bz - 0.85
	local reach = (COG_BIG + COG_SMALL) * 0.45
	local smallY, smallZ = bigY + reach * math.sin(0.26), bigZ + reach * math.cos(0.26)
	for _, side in { 1, -1 } do
		cog(model, Vector3.new(side * cogX, bigY, bigZ), COG_BIG, 0.36, 4, side, 0.25, "Cog1")
		cog(model, Vector3.new(side * cogX, smallY, smallZ), COG_SMALL, 0.36, 3, side, 0.25, "Cog2")
	end
	sign(model, CFrame.new(0, 6.42, bz - 2.98), "CRUSHER", 3.4)
	-- piston-square drive at the back: body, light band, wide cap
	Geo.block(model, CFrame.new(-1.5, 0.95, 3.5), Vector3.new(2.0, 1.3, 1.3), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(-1.5, 1.71, 3.5), Vector3.new(2.08, 0.22, 1.38), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(-1.5, 2.07, 3.45), Vector3.new(2.5, 0.5, 1.8), C.HousingTop, nil, prop())

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return model
end

-- Anvil (retired): chunky anvil with a pointed horn on a machine-bed style
-- pedestal, quench bucket, hammer. AnvilPoint / IngotSlots unchanged.
local function anvil(): Model
	local model, base = newModel("Anvil")
	housing(model, CFrame.new(0, 0.3, 0.3), Vector3.new(3.0, 2.2, 2.6), C.Housing, 0.4, { Name = "Stump" })
	Geo.block(model, CFrame.new(0, 2.75, 0.3), Vector3.new(2.6, 0.5, 2.0), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(0, 3.48, 0.3), Vector3.new(1.4, 0.95, 1.3), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(0, 4.35, 0.3), Vector3.new(3.6, 0.8, 1.8), C.HousingLight, nil, solid({ Name = "AnvilFace" }))
	-- horn: a sloping top wedge over an inverted wedge, meeting in a point
	local horn = CFrame.new(-2.4, 4.35, 0.3) * CFrame.Angles(0, math.pi / 2, 0)
	Geo.wedge(model, horn * CFrame.new(0, 0.2, 0), Vector3.new(1.1, 0.4, 1.2), C.HousingLight, nil, tiny())
	Geo.wedge(model, horn * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.pi), Vector3.new(1.1, 0.4, 1.2), C.HousingLight, nil, tiny())
	-- hammer leaning on the pedestal, its head on the handle tip
	local handle = CFrame.new(1.9, 2.0, -1.3) * CFrame.Angles(0, 0, math.rad(20))
	Geo.block(model, handle, Vector3.new(0.25, 2.6, 0.25), C.Wood, nil, tiny())
	Geo.block(model, handle * CFrame.new(0, 1.3, 0), Vector3.new(1.1, 0.5, 0.5), C.HousingDark, nil, tiny())
	-- quench bucket (copper, water)
	cyl(model, Vector3.new(-2.4, 1.05, 2.1), "Y", 1.5, 1.6, C.Copper, nil, solid())
	cyl(model, Vector3.new(-2.4, 1.72, 2.1), "Y", 0.08, 1.35, C.Water, nil, tiny())
	sign(model, CFrame.new(0, 1.5, -1.15), "ANVIL", 1.8)
	local anvilPoint = Vector3.new(0, 4.95, 0.3)
	attach(base, "AnvilPoint", CFrame.new(anvilPoint))
	-- forging close-up: in front and above, looking down at the face
	attach(base, "CamPoint", CFrame.lookAt(Vector3.new(0, 8.5, -5.5), anvilPoint + Vector3.new(0, 0.2, 0)))
	-- where the client shows waiting ingots: side by side across the face,
	-- turned so their long side runs front to back
	for i = 1, 4 do
		attach(base, "IngotSlot" .. i, CFrame.new((i - 2.5) * 0.9, 5.05, 0.3) * CFrame.Angles(0, math.pi / 2, 0))
	end
	attach(base, "Prompt", CFrame.new(0, 3.5, -1.8))
	output(base, "Anvil")
	local intake = attach(base, "Intake", CFrame.new(0, 5, 0.3))
	intake:SetAttribute("IntakeSize", Vector3.new(4.4, 2.6, 3.4))
	return model
end

--[[
	Auto Cleaner (2x2): a Kenney scanner-high arch (name plate on top) over a
	short striped roller conveyor (conveyor-bars-stripe-high, rollers named
	BedRoller), a brush Drum hanging from two robot-arm style arms, a squat
	copper water tank whose pipe (with a valve) runs to a shower head that
	sprays onto the ore (WaterOut -> WaterIn), an open round hopper at the
	back, an exhaust Vent and a warning-traffic stack light. 68 parts.
]]
local function autoCleaner(): Model
	local model, base = newModel("AutoCleaner")
	local cx, z0, z1 = 0.9, -3.5, 3.3
	local len, zc = z1 - z0, (z0 + z1) / 2
	-- roller conveyor bed
	Geo.block(model, CFrame.new(cx, 0.9, zc), Vector3.new(3.0, 1.2, len), C.Housing, nil, solid({ Name = "Bed" }))
	Geo.block(model, CFrame.new(cx, 0.58, zc), Vector3.new(3.12, 0.56, len + 0.12), C.Hazard, nil, prop())
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(cx + side * 1.65, 1.95, zc), Vector3.new(0.32, 0.9, len), C.Housing, nil, solid())
		Geo.block(model, CFrame.new(cx + side * 1.65, 2.44, zc), Vector3.new(0.38, 0.1, len + 0.04), C.HousingLight, nil, tiny())
	end
	for i = 0, 4 do
		cyl(model, Vector3.new(cx, 1.85, z0 + 0.7 + i * 1.35), "X", 3.0, 0.62, C.HousingLight, nil, solid({ Name = "BedRoller" }))
	end
	-- scanner arch: orange feet, legs, light collars, rounded top corners
	local az = 0.3
	for _, side in { -1, 1 } do
		local lx = cx + side * 2.35
		Geo.block(model, CFrame.new(lx, 0.65, az), Vector3.new(1.1, 0.7, 1.15), C.Hazard, nil, solid())
		Geo.block(model, CFrame.new(lx, 3.175, az), Vector3.new(0.9, 4.35, 0.9), C.Housing, nil, solid())
		Geo.block(model, CFrame.new(lx, 4.25, az), Vector3.new(1.04, 0.3, 1.04), C.HousingLight, nil, tiny())
		cyl(model, Vector3.new(lx, 5.35, az), "Z", 0.9, 0.9, C.Housing, nil, solid())
	end
	Geo.block(model, CFrame.new(cx, 5.35, az), Vector3.new(4.7, 0.9, 0.9), C.Housing, nil, solid({ Name = "Arch" }))
	sign(model, CFrame.new(cx, 6.16, az), "AUTO CLEANER", 2.9)
	-- brush drum (dark bristles) on two chunky arms with light joints
	local drumC = Vector3.new(cx, 3.2, az)
	cyl(model, drumC, "X", 2.9, 1.0, C.Brass, nil, solid({ Name = "Drum" }))
	for k = 0, 2 do
		Geo.block(
			model,
			CFrame.new(drumC) * CFrame.Angles(k * math.pi / 3, 0, 0),
			Vector3.new(2.7, 1.4, 0.3),
			C.Bristle,
			nil,
			tiny({ Name = "DrumRib" })
		)
	end
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(cx + side * 1.62, 4.05, az), Vector3.new(0.4, 1.7, 0.44), C.Housing, nil, tiny())
		ball(model, Vector3.new(cx + side * 1.62, 3.2, az), 0.62, C.HousingLight)
	end
	-- water: squat copper tank (front left), riser with a valve, a spray bar
	-- (below the name plate's sight line) to a shower head over the bed
	local tx, tz = -2.75, -1.5
	local capTop = tank(model, Vector3.new(tx, 0.3, tz), 2.0, 2.4)
	local barY = 4.7
	cyl(model, Vector3.new(tx, (capTop + barY) / 2, tz), "Y", barY - capTop, 0.5, C.Copper, nil, prop())
	valve(model, Vector3.new(tx, capTop + 0.75, tz), "Y", 0.5, Vector3.new(0, 0, -1))
	ball(model, Vector3.new(tx, barY, tz), 0.6, C.Copper)
	local barEnd = cx + 0.95
	cyl(model, Vector3.new((tx + barEnd) / 2, barY, tz), "X", barEnd - tx, 0.5, C.Copper, nil, prop())
	cyl(model, Vector3.new(barEnd + 0.08, barY, tz), "X", 0.2, 0.75, C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(cx, barY - 0.32, tz), Vector3.new(1.6, 0.2, 0.46), C.HousingLight, nil, tiny({ Name = "ShowerHead" }))
	water(base, Vector3.new(cx, barY - 0.44, tz), Vector3.new(0, -1, 0), Vector3.new(cx, 2.3, tz), true)
	-- open round hopper at the back on a bridge over the rails
	Geo.block(model, CFrame.new(cx, 2.6, 2.6), Vector3.new(3.7, 0.35, 1.4), C.HousingLight, nil, solid())
	roundHopper(model, Vector3.new(cx, 2.775, 2.6), 2.6, 0.5)
	-- exhaust vent (smokes more while working)
	cyl(model, Vector3.new(3.2, 2.25, 3.1), "Y", 3.9, 0.7, C.Housing, nil, prop())
	local vent = cyl(model, Vector3.new(3.2, 4.37, 3.1), "Y", 0.35, 0.95, C.HousingLight, nil, tiny({ Name = "Vent" }))
	emitter(vent, "Smoke", rgb(190, 170, 150), 1)
	-- warning-traffic light: green / amber / red between light collars; one
	-- lamp is lit (the client picks it by state)
	local sx, sz = -3.25, -3.6
	cyl(model, Vector3.new(sx, 0.43, sz), "Y", 0.25, 0.7, C.HousingLight, nil, tiny())
	cyl(model, Vector3.new(sx, 1.72, sz), "Y", 2.35, 0.3, C.HousingDark, nil, prop())
	local lampY = 2.9
	for i, name in { "StackGreen", "StackAmber", "StackRed" } do
		local lit = name == MachineBuilder.Stack.Lit
		local color = MachineBuilder.Stack.Lamps[name]
		cyl(
			model,
			Vector3.new(sx, lampY + 0.15, sz),
			"Y",
			0.3,
			0.55,
			if lit then color else color:Lerp(Color3.new(0, 0, 0), MachineBuilder.Stack.Dim),
			if lit then NEON else SMOOTH,
			tiny({ Name = name })
		)
		lampY += 0.3
		if i < 3 then
			cyl(model, Vector3.new(sx, lampY + 0.04, sz), "Y", 0.08, 0.62, C.HousingLight, nil, tiny())
			lampY += 0.08
		end
	end
	cyl(model, Vector3.new(sx, lampY + 0.09, sz), "Y", 0.18, 0.62, C.HousingLight, nil, tiny())
	-- output lip
	local out = output(base, "AutoCleaner")
	Geo.wedge(model, CFrame.new(out.X - 0.6, 1.8, z0 - 0.5), Vector3.new(2.2, 0.6, 1.0), C.HousingLight, nil, solid())

	attach(base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return model
end

-- Sell Chute (retired): an open round hopper on a copper pipe that goes into
-- the ground through a flange, a pile of gold coins (Coins, a small glowing
-- centre) in its cup and a SELL plate.
local function sellChute(): Model
	local model, base = newModel("SellChute")
	cyl(model, Vector3.new(0, 0.45, 0), "Y", 0.3, 1.7, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(0, 1.4, 0), "Y", 2.2, 1.1, C.Copper, nil, solid())
	local rim = roundHopper(model, Vector3.new(0, 2.5, 0), 2.6, 0)
	local coins = cyl(model, Vector3.new(0, rim - 0.48, 0), "Y", 0.14, 1.9, C.Coin, nil, tiny({ Name = "Coins" }))
	light(coins, C.Gold, 8, 0.8)
	cyl(model, Vector3.new(0, rim - 0.4, 0), "Y", 0.04, 0.45, rgb(220, 130, 40), NEON, tiny({ Name = "CoinsGlow" }))
	Geo.block(model, CFrame.new(0, 1.0, -1.45), Vector3.new(0.22, 1.4, 0.22), C.HousingDark, nil, tiny())
	sign(model, CFrame.new(0, 1.75, -1.6), "SELL", 1.3)
	attach(base, "Prompt", CFrame.new(0, 2, -1.2))
	local intake = attach(base, "Intake", CFrame.new(0, 3.8, 0))
	intake:SetAttribute("IntakeSize", Vector3.new(3.6, 2.4, 3.6))
	return model
end

local function gradientStrip(gui: SurfaceGui, name: string, x: number, width: number, keys: { ColorSequenceKeypoint })
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Position = UDim2.fromScale(x, 0)
	frame.Size = UDim2.fromScale(width, 1)
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = frame
end

local function surface(part: Part, name: string, face: Enum.NormalId, maxDistance: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 1
	gui.MaxDistance = maxDistance
	gui.Parent = part
	return gui
end

-- Rollers and hazard edges painted on the belt's top face (one SurfaceGui,
-- no parts: a conveyor stays at 6 parts). Gradients run along the belt:
-- 4 rollers, each dark crease -> mid -> light crown -> mid.
local function beltFace(belt: Part)
	local gui = surface(belt, "BeltFace", Enum.NormalId.Top, 90)
	local rollers = {}
	for i = 0, 3 do
		local t0 = i / 4
		table.insert(rollers, ColorSequenceKeypoint.new(t0, C.Belt))
		table.insert(rollers, ColorSequenceKeypoint.new(t0 + 0.045, C.Roller))
		table.insert(rollers, ColorSequenceKeypoint.new(t0 + 0.125, C.HousingLight))
		table.insert(rollers, ColorSequenceKeypoint.new(t0 + 0.205, C.Roller))
	end
	table.insert(rollers, ColorSequenceKeypoint.new(1, C.Belt))
	-- 6 hazard dashes along each edge
	local dashes = {}
	local n = 6
	for s = 0, n - 1 do
		local color = if s % 2 == 0 then C.Hazard else C.HazardDark
		table.insert(dashes, ColorSequenceKeypoint.new(if s == 0 then 0 else s / n + 0.002, color))
		table.insert(dashes, ColorSequenceKeypoint.new((s + 1) / n, color))
	end
	gradientStrip(gui, "Rollers", 0.08, 0.84, rollers)
	gradientStrip(gui, "HazardL", 0, 0.08, dashes)
	gradientStrip(gui, "HazardR", 0.92, 0.08, dashes)
end

-- A rail's outer side: a darker top strip and the 4 rollers' axle caps.
local function railFace(rail: Part, face: Enum.NormalId)
	local gui = surface(rail, "RailFace", face, 60)
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.BorderSizePixel = 0
	cap.BackgroundColor3 = C.Housing
	cap.Size = UDim2.fromScale(1, 0.24)
	cap.Parent = gui
	for i = 0, 3 do
		local dot = Instance.new("Frame")
		dot.Name = "Axle"
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = C.HousingDark
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale((i + 0.5) / 4, 0.55)
		dot.Size = UDim2.fromScale(0.075, 0.27)
		dot.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
	end
end

local function conveyor(): Model
	local model, base = newModel("Conveyor")
	base.CanCollide = false
	base.CanQuery = true
	base.CastShadow = false
	local railL = Geo.block(
		model,
		CFrame.new(-1.85, 0.55, 0),
		Vector3.new(0.3, 1.1, 4),
		C.HousingLight,
		nil,
		solid({ Name = "RailL", CastShadow = false })
	)
	local railR = Geo.block(
		model,
		CFrame.new(1.85, 0.55, 0),
		Vector3.new(0.3, 1.1, 4),
		C.HousingLight,
		nil,
		solid({ Name = "RailR", CastShadow = false })
	)
	railFace(railL, Enum.NormalId.Left)
	railFace(railR, Enum.NormalId.Right)
	-- zero bounce and high friction so items ride the belt instead of hopping
	local belt = Geo.block(
		model,
		CFrame.new(0, 0.55, 0),
		Vector3.new(3.4, 0.5, 4),
		C.Belt,
		nil,
		solid({
			Name = "Belt",
			CanTouch = true,
			CastShadow = false,
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.2, 0, 100, 100),
		})
	)
	belt:AddTag("ConveyorBelt")
	beltFace(belt)
	-- one flat painted chevron pointing to the front (-Z), the direction items
	-- move: two wedges lying flat, mirrored around x = 0
	local w, h = 1.2, 0.8
	for _, side in { -1, 1 } do
		Geo.wedge(
			model,
			CFrame.new(side * w / 4, 0.82, 0) * CFrame.Angles(0, 0, -side * math.pi / 2),
			Vector3.new(0.04, w / 2, h),
			C.Arrow,
			nil,
			tiny({ Name = "Arrow" })
		)
	end
	attach(base, "Prompt", CFrame.new(0, 1.5, 0))
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	CleaningStation = cleaningStation,
	StorageCrate = storageCrate,
	ClayFurnace = clayFurnace,
	BlastFurnace = blastFurnace,
	Crusher = crusher,
	Anvil = anvil,
	AutoCleaner = autoCleaner,
	SellChute = sellChute,
	Conveyor = conveyor,
}

-- Builds a machine model at the local origin (place it with :PivotTo()).
function MachineBuilder.build(id: string): Model
	local builder = BUILDERS[id]
	assert(builder, "No model for machine " .. tostring(id))
	local model = builder()
	local base = model.PrimaryPart :: BasePart
	local top = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- highest point of the (possibly rotated) part
			local cf, size = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local halfHeight = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
			top = math.max(top, cf.Position.Y + halfHeight)
		end
	end
	attach(base, "Status", CFrame.new(0, top - base.CFrame.Position.Y + 1.5, 0))
	return model
end

return MachineBuilder
