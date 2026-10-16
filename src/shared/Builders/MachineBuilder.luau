--[[
	Machine models (pure builders, used by the server and for build-mode ghosts).

	Style: the Kenney Factory Kit (docs/KENNEY_FACTORY_KIT.md, ART_DIRECTION
	section 9) rebuilt from parts in the forge palette: chunky bevelled iron
	housings with an orange base trim, thick light frames around openings,
	copper pipes with light flanges, hoppers on top as the intake, round
	piston tanks, cogs, and water that pours out of pipes (the client animates
	the stream between WaterOut and WaterIn, see MachineFxController).

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
	the rollers and hazard edges are painted on the belt (one SurfaceGui).
	Moving parts are named so the client can animate them (Roller1/2 + their
	Tooth parts and side cogs, Drum + DrumRib, BedRoller, Glow, Molten,
	StackRed/Amber/Green, WaterPool).
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
	-- forged iron (ART_DIRECTION section 9, machine palette)
	Housing = rgb(100, 108, 134),
	HousingLight = rgb(160, 166, 190),
	HousingDark = rgb(62, 64, 80),
	Floor = rgb(80, 84, 102),
	Copper = rgb(198, 112, 62),
	Brass = rgb(214, 170, 76),
	Hazard = rgb(255, 150, 36),
	HazardDark = rgb(40, 36, 40),
	Molten = rgb(255, 112, 26),
	Glow = rgb(255, 130, 40),
	Clay = rgb(196, 112, 70),
	ClayDark = rgb(150, 80, 50),
	Wood = rgb(150, 100, 58),
	WoodLight = rgb(196, 144, 92),
	WoodDark = rgb(100, 64, 38),
	Gold = rgb(255, 196, 72),
	Belt = rgb(46, 42, 44),
	Roller = rgb(124, 128, 144),
	Arrow = rgb(240, 164, 52),
	Cloth = rgb(240, 222, 190),
	Bristle = rgb(70, 160, 160),
	Glass = rgb(176, 222, 240),
	Screen = rgb(40, 150, 130),
	Water = rgb(62, 152, 196),
	Red = rgb(235, 70, 60),
	Amber = rgb(255, 176, 40),
	Green = rgb(80, 210, 110),
}

-- Water look, shared by the client animation (MachineFxController) and the
-- preview gallery, so both draw the same stream.
MachineBuilder.Water = {
	Stream = rgb(150, 214, 245), -- outer stream / spray fan
	Core = rgb(226, 246, 255), -- bright core of the stream
	Splash = rgb(236, 248, 255), -- droplets and mist
	Pool = C.Water, -- basin water (part WaterPool)
	PoolTransparency = 0.22,
	Width = 0.34, -- stream width at the outlet (studs)
	WidthEnd = 0.42,
	SprayWidth = 0.4, -- shower fan: narrow at the nozzle...
	SprayWidthEnd = 1.5, -- ...wide where it hits the ore
}

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
		}, props or solid()),
		m
	)
end

local function ball(m: Instance, center: Vector3, diameter: number, color: Color3, props: Props?, material: Enum.Material?): Part
	return Geo.ball(m, center, diameter, color, material, props or tiny())
end

--[[
	Kenney "machine" body standing on `cf` (bottom centre): body block, a top
	slab, bevelled left/right top edges and an orange base band. Returns the
	body block.
]]
local function housing(m: Instance, cf: CFrame, size: Vector3, color: Color3, bevel: number, name: string?, frontBevel: boolean?): Part
	local w, h, d = size.X, size.Y, size.Z
	local body =
		Geo.block(m, cf * CFrame.new(0, (h - bevel) / 2, 0), Vector3.new(w, h - bevel, d), color, nil, solid({ Name = name or "Body" }))
	local front = if frontBevel then bevel else 0
	Geo.block(m, cf * CFrame.new(0, h - bevel / 2, front / 2), Vector3.new(w - 2 * bevel, bevel, d - front), color, nil, solid())
	if frontBevel then
		Geo.wedge(m, cf * CFrame.new(0, h - bevel / 2, -d / 2 + bevel / 2), Vector3.new(w - 2 * bevel, bevel, bevel), color, nil, solid())
	end
	for _, side in { -1, 1 } do
		-- wedge: tall side inward, slope down to the outer edge
		Geo.wedge(
			m,
			cf * CFrame.new(side * (w / 2 - bevel / 2), h - bevel / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Vector3.new(d, bevel, bevel),
			color,
			nil,
			solid()
		)
	end
	Geo.block(m, cf * CFrame.new(0, 0.28, 0), Vector3.new(w + 0.12, 0.56, d + 0.12), C.Hazard, nil, prop())
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
	Geo.block(m, cf * CFrame.new(0, h / 2, -0.04), Vector3.new(w, h, 0.1), C.HousingDark, nil, tiny())
end

--[[
	Kenney hopper-square: a tapered neck (4 wedges), a light collar band and an
	open cup (4 walls) with a dark throat floor. `cf` = bottom centre of the
	taper. Returns the height of the cup rim above `cf`.
]]
local function squareHopper(
	m: Instance,
	cf: CFrame,
	bottomW: number,
	topW: number,
	taperH: number,
	cupH: number,
	wall: number,
	collarColor: Color3?
): number
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
	Geo.block(
		m,
		cf * CFrame.new(0, taperH + collar / 2, 0),
		Vector3.new(topW + 0.3, collar, topW + 0.3),
		collarColor or C.HousingLight,
		nil,
		solid()
	)
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
	Geo.block(m, cf * CFrame.new(0, cupY + 0.05, 0), Vector3.new(topW - 2 * wall, 0.1, topW - 2 * wall), C.HousingDark, nil, solid())
	return cupY + cupH
end

--[[
	Kenney hopper-round: neck, taper, light collar, cup and a dark mouth.
	`bottom` = bottom centre, `d` = cup diameter. Returns the top height.
]]
local function roundHopper(m: Instance, bottom: Vector3, d: number, neck: number): number
	local y = bottom.Y
	cyl(m, Vector3.new(bottom.X, y + neck / 2, bottom.Z), "Y", neck, d * 0.5, C.Housing, nil, solid())
	y += neck
	cyl(m, Vector3.new(bottom.X, y + 0.25, bottom.Z), "Y", 0.5, d * 0.76, C.Housing, nil, solid())
	y += 0.5
	cyl(m, Vector3.new(bottom.X, y + 0.175, bottom.Z), "Y", 0.35, d * 1.12, C.HousingLight, nil, solid())
	y += 0.35
	cyl(m, Vector3.new(bottom.X, y + 0.475, bottom.Z), "Y", 0.95, d, C.Housing, nil, solid())
	y += 0.95
	cyl(m, Vector3.new(bottom.X, y - 0.09, bottom.Z), "Y", 0.18, d + 0.08, C.HousingLight, nil, tiny())
	cyl(m, Vector3.new(bottom.X, y + 0.03, bottom.Z), "Y", 0.06, d - 0.55, C.HousingDark, nil, tiny())
	return y + 0.06
end

-- Kenney piston-round as a fuel/water tank: copper body, light band, wide dark cap.
local function tank(m: Instance, bottom: Vector3, d: number, h: number, name: string?): number
	local body = h - 0.8
	cyl(m, bottom + Vector3.new(0, body / 2, 0), "Y", body, d, C.Copper, nil, solid({ Name = name or "Tank" }))
	cyl(m, bottom + Vector3.new(0, body + 0.13, 0), "Y", 0.26, d + 0.16, C.HousingLight, nil, prop())
	cyl(m, bottom + Vector3.new(0, body + 0.26 + 0.27, 0), "Y", 0.54, d + 0.4, C.HousingDark, nil, solid())
	return bottom.Y + h
end

-- Hand wheel of a valve, facing along `axis`: orange rim, dark inside, hub.
local function wheel(m: Instance, center: Vector3, axis: Axis, d: number)
	cyl(m, center, axis, 0.14, d, C.Hazard, nil, tiny())
	cyl(m, center, axis, 0.16, d * 0.62, C.HazardDark, nil, tiny())
	cyl(m, center, axis, 0.3, d * 0.28, C.Hazard, nil, tiny())
end

-- Kenney cog-a: disc, 8 teeth, dark hub; turns around X (named for spinning).
local function cog(m: Instance, center: Vector3, d: number, thick: number, color: Color3, name: string)
	cyl(m, center, "X", thick, d * 0.8, color, nil, tiny({ Name = name }))
	for k = 0, 3 do
		Geo.block(
			m,
			CFrame.new(center) * CFrame.Angles(k * math.pi / 4, 0, 0),
			Vector3.new(thick, d * 0.17, d),
			color,
			nil,
			tiny({ Name = name })
		)
	end
	cyl(m, center, "X", thick + 0.14, d * 0.3, C.HousingDark, nil, tiny({ Name = name }))
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
	framed knee opening, wooden top), vise at OrePoint, a copper water pipe
	with a valve wheel pouring into a wash basin left of the vise (WaterOut ->
	WaterIn), tool board, screen-panel-small, lever-double, lamp, output tray.
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
	-- wooden work top
	Geo.block(model, CFrame.new(0, top + 0.1, benchZ), Vector3.new(10.8, 0.4, 5.4), C.WoodLight, nil, solid({ Name = "Bench" }))
	-- work slab + vise (screw and T handle out to the front)
	Geo.block(model, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), C.HousingDark, nil, solid({ Name = "WorkSlab" }))
	for _, x in { -1.75, 1.75 } do
		Geo.block(model, CFrame.new(x, top + 0.95, 0.3), Vector3.new(0.5, 0.5, 2.2), C.HousingLight, nil, solid({ Name = "Jaw" }))
	end
	cyl(model, Vector3.new(-1.75, top + 0.95, -1.2), "Z", 0.8, 0.22, C.Brass, nil, tiny())
	Geo.block(model, CFrame.new(-1.75, top + 0.95, -1.62), Vector3.new(1.2, 0.14, 0.14), C.Brass, nil, tiny())

	-- wash basin left of the vise (rim 3.7..4.8, water top 4.62)
	local bx, bz, bw, bd, bh, t = -4.15, -0.5, 2.3, 2.6, 1.1, 0.22
	local by = top + 0.3
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(bx, by + bh / 2, bz + side * (bd / 2 - t / 2)), Vector3.new(bw, bh, t), C.HousingLight, nil, solid())
		Geo.block(
			model,
			CFrame.new(bx + side * (bw / 2 - t / 2), by + bh / 2, bz),
			Vector3.new(t, bh, bd - 2 * t),
			C.HousingLight,
			nil,
			solid()
		)
	end
	Geo.block(model, CFrame.new(bx, by + 0.3, bz), Vector3.new(bw - 2 * t, 0.6, bd - 2 * t), C.HousingDark, nil, solid())
	local poolTop = by + 0.92
	Geo.block(
		model,
		CFrame.new(bx, poolTop - 0.06, bz),
		Vector3.new(bw - 2 * t, 0.12, bd - 2 * t),
		MachineBuilder.Water.Pool,
		nil,
		tiny({ Name = "WaterPool", Transparency = MachineBuilder.Water.PoolTransparency, Reflectance = 0.1 })
	)

	-- copper water pipe: floor flange, riser with a valve wheel, elbow, run to the outlet
	local pz, pipeY, outZ = 2.35, 7.3, 0.05
	cyl(model, Vector3.new(bx, by + 0.14, pz), "Y", 0.28, 1.0, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(bx, (by + pipeY) / 2, pz), "Y", pipeY - by, 0.6, C.Copper, nil, solid())
	cyl(model, Vector3.new(bx, 5.4, pz), "Y", 0.7, 0.92, C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(bx, 5.4, pz - 0.58), Vector3.new(0.18, 0.18, 0.32), C.HousingDark, nil, tiny())
	wheel(model, Vector3.new(bx, 5.4, pz - 0.76), "Z", 1.15)
	ball(model, Vector3.new(bx, pipeY, pz), 0.68, C.Copper, prop())
	cyl(model, Vector3.new(bx, pipeY, (pz + outZ) / 2 + 0.07), "Z", pz - outZ - 0.14, 0.6, C.Copper, nil, prop())
	cyl(model, Vector3.new(bx, pipeY, outZ + 0.12), "Z", 0.28, 0.95, C.HousingLight, nil, prop())
	water(base, Vector3.new(bx, pipeY - 0.06, outZ - 0.04), Vector3.new(0, 0, -1), Vector3.new(bx, poolTop, bz - 0.2))

	-- tool board at the back: chisel, hammer, brush
	local boardZ = 2.85
	Geo.block(model, CFrame.new(-0.6, top + 1.6, boardZ), Vector3.new(3.6, 2.6, 0.25), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(-0.6, top + 2.98, boardZ), Vector3.new(3.7, 0.24, 0.34), C.Hazard, nil, tiny())
	local toolZ = boardZ - 0.22
	Geo.block(model, CFrame.new(-1.9, top + 1.4, toolZ), Vector3.new(0.2, 1.1, 0.14), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(-1.9, top + 2.25, toolZ), Vector3.new(0.3, 0.7, 0.24), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), C.HousingDark, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 2.05, toolZ), Vector3.new(0.24, 1.0, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 1.3, toolZ), Vector3.new(0.7, 0.55, 0.3), C.Cloth, nil, tiny())

	-- screen-panel-small: two legs in front of a panel with a teal screen
	for _, x in { 2.05, 3.15 } do
		Geo.block(model, CFrame.new(x, top + 1.1, 2.55), Vector3.new(0.28, 1.6, 0.28), C.HousingLight, nil, prop())
	end
	Geo.block(model, CFrame.new(2.6, top + 1.95, 2.8), Vector3.new(1.8, 1.3, 0.3), C.Housing, nil, prop())
	Geo.block(model, CFrame.new(2.6, top + 2.05, 2.63), Vector3.new(1.4, 0.85, 0.06), C.Screen, NEON, tiny({ Name = "Screen" }))

	-- lever-double on the top, right behind the tray
	local lx, lz = 4.7, 1.55
	Geo.block(model, CFrame.new(lx, top + 0.42, lz), Vector3.new(1.0, 0.24, 1.0), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(lx, top + 0.64, lz), Vector3.new(0.6, 0.22, 0.6), C.Housing, nil, tiny())
	Geo.block(
		model,
		CFrame.new(lx, top + 1.0, lz - 0.12) * CFrame.Angles(math.rad(-22), 0, 0),
		Vector3.new(0.14, 0.75, 0.14),
		C.HousingDark,
		nil,
		tiny()
	)
	cyl(model, Vector3.new(lx, top + 1.36, lz - 0.27), "X", 0.6, 0.28, C.Hazard, nil, tiny())

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
	Geo.block(model, CFrame.new(3.3, top + 4.55, 1.5), Vector3.new(1.3, 0.55, 1.3), C.Hazard, nil, tiny({ Name = "LampShade" }))
	local bulb = ball(model, Vector3.new(3.3, top + 4.15, 1.5), 0.55, rgb(255, 222, 150), tiny({ Name = "LampBulb" }), NEON)
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

-- Storage Crate (retired): Kenney box-large with a tape band, inside a
-- structure-yellow-high frame.
local function storageCrate(): Model
	local model, base = newModel("StorageCrate")
	Geo.block(model, CFrame.new(0, 2.1, 0.2), Vector3.new(5.6, 3.6, 5.6), C.WoodLight, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 2.1, 0.2), Vector3.new(1.4, 3.64, 5.66), C.Cloth, nil, prop())
	Geo.block(model, CFrame.new(0, 3.93, 0.2), Vector3.new(5.0, 0.06, 5.0), rgb(50, 34, 24), nil, tiny())
	-- open lid leaning back
	Geo.block(model, CFrame.new(0, 4.9, 3.25) * CFrame.Angles(math.rad(-65), 0, 0), Vector3.new(5.6, 0.35, 2.6), C.WoodLight, nil, prop())
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
	Clay Furnace (2x2): Kenney machine-fortified in clay brick (mortar courses,
	an iron strap over the top), a framed glowing mouth near the output, a
	round hopper on top (intake) and a large copper pipe chimney.
]]
local function clayFurnace(): Model
	local model, base = newModel("ClayFurnace")
	local z0 = 0.6
	housing(model, CFrame.new(0, 0.3, z0), Vector3.new(6.6, 5.0, 6.0), C.Clay, 0.8, nil, true)
	for _, y in { 1.95, 3.45 } do
		Geo.block(model, CFrame.new(0, y, z0), Vector3.new(6.66, 0.14, 6.06), C.ClayDark, nil, tiny())
	end
	-- fortified iron strap over the top, bolted at the front
	-- (front plate, a wedge over the rounded front edge, top plate, back plate)
	local strapX = -1.9
	Geo.block(model, CFrame.new(strapX, 2.53, z0 - 3.1), Vector3.new(1.2, 3.94, 0.2), C.HousingLight, nil, prop())
	Geo.wedge(model, CFrame.new(strapX, 4.93, z0 - 2.63), Vector3.new(1.2, 0.86, 0.86), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(strapX, 5.38, z0 + 0.5), Vector3.new(1.2, 0.16, 5.4), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(strapX, 2.95, z0 + 3.1), Vector3.new(1.2, 4.9, 0.2), C.HousingLight, nil, prop())
	for _, y in { 1.4, 3.9 } do
		ball(model, Vector3.new(strapX, y, z0 - 3.22), 0.3, C.Brass)
	end
	-- glowing mouth in a thick frame, toward the output column
	local out = output(base, "ClayFurnace")
	local mouthX = 1.45
	portal(model, CFrame.new(mouthX, 0.85, z0 - 3.0), 2.3, 2.25, 0.45, 0.5)
	local glow = Geo.block(model, CFrame.new(mouthX, 1.6, z0 - 3.07), Vector3.new(2.1, 1.4, 0.12), C.Glow, NEON, tiny({ Name = "Glow" }))
	light(glow, C.Glow, 12, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	Geo.wedge(model, CFrame.new(out.X - 0.1, 0.65, z0 - 3.85), Vector3.new(1.6, 0.7, 1.5), C.HousingLight, nil, solid())
	sign(model, CFrame.new(mouthX, 3.4, z0 - 3.55), "CLAY FURNACE", 3.2)
	-- large pipe chimney at the back left
	local cx, cz = -1.9, 2.15
	cyl(model, Vector3.new(cx, 5.5, cz), "Y", 0.4, 1.9, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 7.0, cz), "Y", 3.4, 1.3, C.Copper, nil, solid())
	cyl(model, Vector3.new(cx, 8.55, cz), "Y", 0.4, 1.9, C.HousingLight, nil, prop())
	local chimneyTop = cyl(model, Vector3.new(cx, 8.8, cz), "Y", 0.1, 1.2, C.Glow, NEON, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", rgb(110, 100, 96), 2)
	-- round hopper on top (the intake)
	roundHopper(model, Vector3.new(0.9, 5.3, 0.45), 2.8, 0.35)

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return model
end

--[[
	Blast Furnace (3x3): Kenney machine-connection-pipe on a plinth: a tall
	iron body with straps, a barred molten window (Glow), a high square
	hopper (intake), a tap of flanged pipe with a glass section showing molten
	metal into an ingot mould at the output, two piston-round fuel tanks piped
	in through elbows (one with a valve wheel), a tall flanged chimney.
]]
local function blastFurnace(): Model
	local model, base = newModel("BlastFurnace")
	-- plinth with an orange edge strip
	Geo.block(model, CFrame.new(0, 0.6, 0.3), Vector3.new(11.0, 0.6, 10.6), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(0, 0.82, 0.3), Vector3.new(11.12, 0.16, 10.72), C.Hazard, nil, tiny())
	local bz = 0.8
	housing(model, CFrame.new(0, 0.9, bz), Vector3.new(6.8, 7.0, 6.4), C.Housing, 0.9)
	local front = bz - 3.2
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 2.55, 4.2, front - 0.1), Vector3.new(0.9, 5.5, 0.2), C.HousingLight, nil, prop())
	end
	-- molten window behind a grate
	portal(model, CFrame.new(0, 3.2, front), 3.0, 2.4, 0.4, 0.5, true)
	local glow = Geo.block(model, CFrame.new(0, 4.4, front - 0.07), Vector3.new(3.0, 2.4, 0.12), C.Glow, NEON, tiny({ Name = "Glow" }))
	light(glow, C.Glow, 17, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	for _, x in { -0.75, 0, 0.75 } do
		Geo.block(model, CFrame.new(x, 4.4, front - 0.17), Vector3.new(0.16, 2.4, 0.1), C.HousingDark, nil, tiny())
	end
	sign(model, CFrame.new(0, 6.75, front - 0.08), "BLAST FURNACE", 3.9)
	-- tap: flanged pipe, glass section with molten metal, elbow down into a mould
	local out = output(base, "BlastFurnace")
	local tapY = 2.4
	cyl(model, Vector3.new(out.X, tapY, front - 0.22), "Z", 0.45, 0.75, C.Housing, nil, prop())
	cyl(model, Vector3.new(out.X, tapY, front - 0.5), "Z", 0.2, 1.15, C.HousingLight, nil, tiny())
	cyl(model, Vector3.new(out.X, tapY, front - 1.05), "Z", 0.9, 0.85, C.Glass, GLASS, tiny({ Transparency = 0.45 }))
	cyl(model, Vector3.new(out.X, tapY, front - 1.05), "Z", 0.92, 0.4, C.Molten, NEON, tiny({ Name = "Molten" }))
	cyl(model, Vector3.new(out.X, tapY, front - 1.6), "Z", 0.2, 1.15, C.HousingLight, nil, tiny())
	ball(model, Vector3.new(out.X, tapY, front - 1.95), 0.82, C.Housing, prop())
	cyl(model, Vector3.new(out.X, tapY - 0.3, front - 1.95), "Y", 0.6, 0.6, C.Housing, nil, tiny())
	Geo.block(model, CFrame.new(out.X, 1.6, front - 1.95), Vector3.new(0.2, 0.55, 0.2), C.Molten, NEON, tiny({ Name = "Molten" }))
	Geo.block(model, CFrame.new(out.X, 1.1, front - 1.95), Vector3.new(1.4, 0.4, 1.1), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(out.X, 1.32, front - 1.95), Vector3.new(1.1, 0.06, 0.8), C.Molten, NEON, tiny({ Name = "Molten" }))
	-- high square hopper on top (the intake)
	squareHopper(model, CFrame.new(0, 7.9, 0.6), 3.2, 5.0, 1.3, 1.5, 0.4, C.Hazard)
	-- warning-orange beacon at the front left corner of the plinth
	cyl(model, Vector3.new(-4.5, 2.2, -3.9), "Y", 2.6, 0.3, C.HousingDark, nil, prop())
	cyl(model, Vector3.new(-4.5, 3.55, -3.9), "Y", 0.22, 0.62, C.HousingLight, nil, tiny())
	ball(model, Vector3.new(-4.5, 3.75, -3.9), 0.6, C.Hazard, tiny({ Name = "Beacon" }), NEON)
	-- tall flanged chimney at the back left, standing on the plinth
	local cx, cz = -4.6, 3.4
	cyl(model, Vector3.new(cx, 1.1, cz), "Y", 0.4, 2.2, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 6.85, cz), "Y", 11.1, 1.5, C.Copper, nil, solid())
	cyl(model, Vector3.new(cx, 7.2, cz), "Y", 0.4, 2.0, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(cx, 12.4, cz), "Y", 0.45, 2.2, C.HousingLight, nil, prop())
	local chimneyTop = cyl(model, Vector3.new(cx, 12.66, cz), "Y", 0.1, 1.3, C.Glow, NEON, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", rgb(110, 100, 96), 5)
	-- fuel tanks on the right, piped into the body through elbows
	for i, tz in { -1.0, 2.6 } do
		local tx = 4.6
		local capTop = tank(model, Vector3.new(tx, 0.9, tz), 1.9, 3.4)
		cyl(model, Vector3.new(tx, (capTop + 5.6) / 2, tz), "Y", 5.6 - capTop, 0.5, C.Housing, nil, prop())
		ball(model, Vector3.new(tx, 5.6, tz), 0.58, C.Housing)
		cyl(model, Vector3.new((tx + 3.4) / 2, 5.6, tz), "X", tx - 3.4, 0.5, C.Housing, nil, prop())
		cyl(model, Vector3.new(3.48, 5.6, tz), "X", 0.2, 0.85, C.HousingLight, nil, tiny())
		if i == 1 then
			cyl(model, Vector3.new(tx, 4.9, tz), "Y", 0.45, 0.75, C.HousingLight, nil, tiny())
			wheel(model, Vector3.new(tx, 4.9, tz - 0.5), "Z", 0.9)
		else
			cyl(model, Vector3.new(tx + 0.96, 2.4, tz), "X", 0.1, 0.75, C.Brass, nil, tiny())
			Geo.block(
				model,
				CFrame.new(tx + 1.02, 2.47, tz - 0.06) * CFrame.Angles(0.7, 0, 0),
				Vector3.new(0.04, 0.3, 0.06),
				C.HazardDark,
				nil,
				tiny()
			)
		end
	end

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return model
end

--[[
	Crusher (2x2): Kenney machine-window housing with a high square hopper,
	the intake, holding the two toothed rollers, big cogs on the sides that turn
	with them (named Roller1Tooth/Roller2Tooth), an output slot with a chute,
	hazard chevrons and a piston-square drive at the back.
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
	-- high square hopper with the rollers inside
	squareHopper(model, CFrame.new(0, 4.3, bz), 3.6, 5.8, 1.1, 1.25, 0.4)
	local rollerY = 6.55
	for i, dz in { -0.75, 0.75 } do
		local c = Vector3.new(0, rollerY, bz + dz)
		cyl(model, c, "X", 4.9, 1.5, C.HousingLight, nil, solid({ Name = "Roller" .. i }))
		for k = 0, 1 do
			Geo.block(
				model,
				CFrame.new(c) * CFrame.Angles(k * math.pi / 2, 0, 0),
				Vector3.new(4.8, 1.75, 0.28),
				C.Housing,
				nil,
				tiny({ Name = "Roller" .. i .. "Tooth" })
			)
		end
	end
	-- big cogs on the sides, on the roller axles
	cog(model, Vector3.new(3.3, rollerY, bz - 0.75), 3.0, 0.4, C.Brass, "Roller1Tooth")
	cog(model, Vector3.new(-3.3, rollerY, bz + 0.75), 3.0, 0.4, C.Brass, "Roller2Tooth")
	sign(model, CFrame.new(0, 6.42, bz - 2.98), "CRUSHER", 3.4)
	-- piston-square drive at the back
	Geo.block(model, CFrame.new(-1.6, 1.1, 3.45), Vector3.new(2.0, 1.6, 1.1), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(-1.6, 2.02, 3.45), Vector3.new(2.1, 0.25, 1.2), C.HousingLight, nil, prop())
	Geo.block(model, CFrame.new(-1.6, 2.37, 3.45), Vector3.new(2.4, 0.45, 1.4), C.HousingDark, nil, prop())

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return model
end

-- Anvil (retired): chunky anvil on a machine-bed style pedestal, quench
-- bucket, hammer. AnvilPoint / IngotSlots unchanged.
local function anvil(): Model
	local model, base = newModel("Anvil")
	housing(model, CFrame.new(0, 0.3, 0.3), Vector3.new(3.0, 2.2, 2.6), C.Housing, 0.4, "Stump")
	Geo.block(model, CFrame.new(0, 2.75, 0.3), Vector3.new(2.6, 0.5, 2.0), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(0, 3.48, 0.3), Vector3.new(1.4, 0.95, 1.3), C.HousingDark, nil, solid())
	local face = Geo.block(model, CFrame.new(0, 4.35, 0.3), Vector3.new(3.6, 0.8, 1.8), C.HousingLight, nil, solid({ Name = "AnvilFace" }))
	local _ = face
	Geo.wedge(
		model,
		CFrame.new(-2.3, 4.35, 0.3) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0),
		Vector3.new(1.4, 0.8, 1.2),
		C.HousingLight,
		nil,
		tiny()
	)
	-- hammer leaning on the pedestal
	Geo.block(model, CFrame.new(1.9, 2.0, -1.3) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.25, 2.6, 0.25), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(2.3, 3.2, -1.3) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(1.1, 0.5, 0.5), C.HousingDark, nil, tiny())
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
	Auto Cleaner (2x2): a Kenney scanner-high arch over a short striped roller
	conveyor (conveyor-bars-stripe-high, rollers named BedRoller), a brush Drum
	hanging from two arms (robot-arm style), a copper water tank whose pipe
	runs to a shower head that sprays onto the ore (WaterOut -> WaterIn), a
	round hopper at the back, an exhaust Vent and a warning-traffic light.
]]
local function autoCleaner(): Model
	local model, base = newModel("AutoCleaner")
	local cx, z0, z1 = 0.9, -3.5, 3.3
	local len, zc = z1 - z0, (z0 + z1) / 2
	-- roller conveyor bed
	Geo.block(model, CFrame.new(cx, 0.9, zc), Vector3.new(3.0, 1.2, len), C.Housing, nil, solid({ Name = "Bed" }))
	Geo.block(model, CFrame.new(cx, 0.58, zc), Vector3.new(3.12, 0.56, len + 0.12), C.Hazard, nil, prop())
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(cx + side * 1.65, 1.95, zc), Vector3.new(0.32, 0.9, len), C.HousingLight, nil, solid())
		Geo.block(model, CFrame.new(cx + side * 1.65, 2.44, zc), Vector3.new(0.34, 0.1, len + 0.02), C.Hazard, nil, tiny())
	end
	for i = 0, 4 do
		cyl(model, Vector3.new(cx, 1.85, z0 + 0.7 + i * 1.35), "X", 3.0, 0.62, C.Roller, nil, solid({ Name = "BedRoller" }))
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
	-- brush drum on two arms
	local drumC = Vector3.new(cx, 3.2, az)
	cyl(model, drumC, "X", 2.9, 1.0, C.Brass, nil, solid({ Name = "Drum" }))
	for k = 0, 2 do
		Geo.block(
			model,
			CFrame.new(drumC) * CFrame.Angles(k * math.pi / 3, 0, 0),
			Vector3.new(2.7, 1.75, 0.3),
			C.Bristle,
			nil,
			tiny({ Name = "DrumRib" })
		)
	end
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(cx + side * 1.6, 4.05, az), Vector3.new(0.3, 1.7, 0.34), C.HousingLight, nil, tiny())
		ball(model, Vector3.new(cx + side * 1.6, 3.2, az), 0.5, C.HousingDark)
	end
	-- water: copper tank (front left), riser with a valve wheel, spray bar to a shower head
	local tx, tz = -2.75, -1.2
	local capTop = tank(model, Vector3.new(tx, 0.3, tz), 1.7, 3.26)
	cyl(model, Vector3.new(tx, 1.9, tz - 0.88), "Z", 0.1, 0.62, C.Brass, nil, tiny())
	Geo.block(
		model,
		CFrame.new(tx + 0.07, 1.97, tz - 0.94) * CFrame.Angles(0, 0, -0.6),
		Vector3.new(0.06, 0.26, 0.04),
		C.HazardDark,
		nil,
		tiny()
	)
	local barY = 5.3
	cyl(model, Vector3.new(tx, (capTop + barY) / 2, tz), "Y", barY - capTop, 0.45, C.Copper, nil, prop())
	cyl(model, Vector3.new(tx, 4.4, tz), "Y", 0.42, 0.72, C.HousingLight, nil, tiny())
	wheel(model, Vector3.new(tx, 4.4, tz - 0.48), "Z", 0.85)
	ball(model, Vector3.new(tx, barY, tz), 0.52, C.Copper)
	local barEnd = cx + 0.95
	cyl(model, Vector3.new((tx + barEnd) / 2, barY, tz), "X", barEnd - tx, 0.45, C.Copper, nil, prop())
	cyl(model, Vector3.new(barEnd + 0.08, barY, tz), "X", 0.2, 0.7, C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(cx, barY - 0.32, tz), Vector3.new(1.6, 0.2, 0.42), C.HousingLight, nil, tiny({ Name = "ShowerHead" }))
	water(base, Vector3.new(cx, barY - 0.44, tz), Vector3.new(0, -1, 0), Vector3.new(cx, 2.3, tz), true)
	-- round hopper at the back on a bridge over the rails
	Geo.block(model, CFrame.new(cx, 2.6, 2.6), Vector3.new(3.7, 0.35, 1.4), C.HousingLight, nil, solid())
	roundHopper(model, Vector3.new(cx, 2.775, 2.6), 2.6, 0.5)
	-- exhaust vent (smokes more while working)
	cyl(model, Vector3.new(3.2, 2.25, 3.1), "Y", 3.9, 0.7, C.Housing, nil, prop())
	local vent = cyl(model, Vector3.new(3.2, 4.37, 3.1), "Y", 0.35, 0.95, C.HousingLight, nil, tiny({ Name = "Vent" }))
	emitter(vent, "Smoke", rgb(190, 170, 150), 1)
	-- warning-traffic light: red / amber / green (the client lights one by state)
	local sx, sz = -3.25, -3.2
	cyl(model, Vector3.new(sx, 0.43, sz), "Y", 0.25, 0.7, C.HousingLight, nil, tiny())
	cyl(model, Vector3.new(sx, 1.6, sz), "Y", 2.6, 0.3, C.HousingDark, nil, prop())
	local stack =
		{ { Name = "StackGreen", Color = C.Green }, { Name = "StackAmber", Color = C.Amber }, { Name = "StackRed", Color = C.Red } }
	for i, lamp in stack do
		cyl(model, Vector3.new(sx, 2.74 + i * 0.32, sz), "Y", 0.3, 0.55, lamp.Color, NEON, tiny({ Name = lamp.Name }))
	end
	cyl(model, Vector3.new(sx, 4.15, sz), "Y", 0.18, 0.62, C.HousingLight, nil, tiny())
	-- output lip and name plate
	local out = output(base, "AutoCleaner")
	Geo.wedge(model, CFrame.new(out.X - 0.6, 1.8, z0 - 0.5), Vector3.new(2.2, 0.6, 1.0), C.HousingLight, nil, solid())
	sign(model, CFrame.new(cx, 0.95, z0 - 0.14), "AUTO CLEANER", 2.8)

	attach(base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return model
end

-- Sell Chute (retired): hopper-high-round on a copper pipe that goes into the
-- ground through a flange, a glowing coin pile (Coins) and a SELL plate.
local function sellChute(): Model
	local model, base = newModel("SellChute")
	cyl(model, Vector3.new(0, 0.45, 0), "Y", 0.3, 1.7, C.HousingLight, nil, prop())
	cyl(model, Vector3.new(0, 1.4, 0), "Y", 2.2, 1.1, C.Copper, nil, solid())
	cyl(model, Vector3.new(0, 2.8, 0), "Y", 0.6, 2.2, C.Housing, nil, solid())
	cyl(model, Vector3.new(0, 3.28, 0), "Y", 0.35, 3.3, C.HousingLight, nil, solid())
	cyl(model, Vector3.new(0, 3.9, 0), "Y", 0.9, 3.0, C.Housing, nil, solid())
	local coins = cyl(model, Vector3.new(0, 4.38, 0), "Y", 0.1, 2.4, C.Gold, NEON, tiny({ Name = "Coins" }))
	light(coins, C.Gold, 8, 0.8)
	Geo.block(model, CFrame.new(0, 1.0, -1.45), Vector3.new(0.22, 1.4, 0.22), C.HousingDark, nil, tiny())
	sign(model, CFrame.new(0, 1.75, -1.6), "SELL", 1.3)
	attach(base, "Prompt", CFrame.new(0, 2, -1.2))
	local intake = attach(base, "Intake", CFrame.new(0, 3.8, 0))
	intake:SetAttribute("IntakeSize", Vector3.new(3.6, 2.4, 3.6))
	return model
end

-- Rollers and hazard edges painted on the belt's top face (one SurfaceGui,
-- no parts: a conveyor stays at 6 parts). Gradients run along the belt.
local function beltFace(belt: Part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BeltFace"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 1
	gui.MaxDistance = 90
	gui.Parent = belt
	local function strip(name: string, x: number, width: number, keys: { ColorSequenceKeypoint })
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
	-- 5 rollers: dark gaps, light crowns
	local rollers = {}
	for i = 0, 10 do
		table.insert(rollers, ColorSequenceKeypoint.new(i / 10, if i % 2 == 0 then C.Belt else C.Roller))
	end
	-- 6 hazard dashes along each edge
	local dashes = {}
	local n = 6
	for s = 0, n - 1 do
		local color = if s % 2 == 0 then C.Hazard else C.HazardDark
		table.insert(dashes, ColorSequenceKeypoint.new(if s == 0 then 0 else s / n + 0.002, color))
		table.insert(dashes, ColorSequenceKeypoint.new((s + 1) / n, color))
	end
	strip("Rollers", 0.08, 0.84, rollers)
	strip("HazardL", 0, 0.08, dashes)
	strip("HazardR", 0.92, 0.08, dashes)
end

local function conveyor(): Model
	local model, base = newModel("Conveyor")
	base.CanCollide = false
	base.CanQuery = true
	base.CastShadow = false
	Geo.block(
		model,
		CFrame.new(-1.85, 0.55, 0),
		Vector3.new(0.3, 1.1, 4),
		C.HousingLight,
		nil,
		solid({ Name = "RailL", CastShadow = false })
	)
	Geo.block(
		model,
		CFrame.new(1.85, 0.55, 0),
		Vector3.new(0.3, 1.1, 4),
		C.HousingLight,
		nil,
		solid({ Name = "RailR", CastShadow = false })
	)
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
	-- one flat chevron pointing to the front (-Z), the direction items move:
	-- two wedges lying flat, mirrored around x = 0
	local w, h = 1.8, 1.2
	for _, side in { -1, 1 } do
		Geo.wedge(
			model,
			CFrame.new(side * w / 4, 0.82, 0) * CFrame.Angles(0, 0, -side * math.pi / 2),
			Vector3.new(0.04, w / 2, h),
			C.Arrow,
			NEON,
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
