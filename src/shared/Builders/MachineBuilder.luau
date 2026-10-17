--[[
	Machine models (pure builders, used by the server and for build-mode ghosts).

	Style: the Kenney Factory Kit (docs/KENNEY_FACTORY_KIT.md, ART_DIRECTION
	section 9) rebuilt from parts in the forge palette: one matte forged-iron
	body colour with lighter tops and thick light frames around openings,
	sparse orange accents (base trims, feet, handles), matte copper pipes with
	octagonal bolted flanges and two-kink bends, open hoppers on top as the
	intake, squat piston tanks, cogs, glass pipe sections with molten metal,
	and water that pours out of pipes (the client animates the stream between
	WaterOut and WaterIn, see MachineFxController).

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
	rails (SurfaceGuis, no extra parts; the Auto Cleaner's bed rails too).
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
	-- forged iron (ART_DIRECTION section 9): one matte, slightly blue body
	-- colour, lighter tops and frames so they catch the light, dark recesses
	-- for openings
	Housing = rgb(108, 114, 132),
	HousingTop = rgb(140, 146, 164),
	HousingLight = rgb(172, 176, 190),
	HousingDark = rgb(72, 76, 90),
	Recess = rgb(40, 40, 50),
	RecessLight = rgb(70, 72, 88), -- openings on the Cleaning Station (no black voids)
	Floor = rgb(82, 86, 100),
	Copper = rgb(198, 112, 62),
	Brass = rgb(225, 185, 90),
	Hazard = rgb(255, 150, 36),
	HazardDark = rgb(40, 36, 40),
	Molten = rgb(236, 96, 22), -- molten metal (glass cores, trickle, mould): deep orange
	Glow = rgb(230, 90, 20), -- big furnace glows: deep orange, the client brightens it
	Ember = rgb(120, 52, 30), -- chimney mouths (dark, warm)
	Clay = rgb(150, 92, 76),
	ClayTop = rgb(168, 106, 90),
	ClayDark = rgb(100, 58, 46),
	Wood = rgb(150, 100, 58),
	WoodLight = rgb(196, 144, 92),
	WoodDark = rgb(100, 64, 38),
	Gold = rgb(255, 196, 72),
	Coin = rgb(228, 178, 62),
	Belt = rgb(40, 38, 44),
	Roller = rgb(120, 124, 136),
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
	Stream = rgb(168, 222, 246), -- the stream (light, fairly opaque)
	Deep = rgb(118, 190, 232), -- the stream's colour where it lands
	Core = rgb(240, 250, 255), -- white highlight strip down the middle
	Splash = rgb(236, 246, 255), -- droplets, spray streaks
	Foam = rgb(246, 251, 255), -- foam where the water lands
	Pool = C.Water, -- basin water (part WaterPool)
	PoolTransparency = 0.22,
	StreamTransparency = 0.3,
	Width = 0.45, -- stream width at the outlet...
	WidthEnd = 0.32, -- ...narrower where it lands (it speeds up while falling)
	CoreWidth = 0.3, -- core strip, part of the stream width
	SprayWidth = 1.1, -- shower: streaks leave the head this wide...
	SprayWidthEnd = 1.4, -- ...and are this far apart where they hit the ore
}

-- Warning-traffic stack light on the Auto Cleaner: only one lamp is lit (Neon),
-- the others are dimmed plastic. The built look lights `Lit`; the client
-- lights the lamp for the machine's state (MachineFxController).
MachineBuilder.Stack = {
	Lamps = { StackRed = C.Red, StackAmber = C.Amber, StackGreen = C.Green },
	Lit = "StackGreen",
	Dim = 0.5, -- unlit lamps: colour lerped this far toward black
}

-- Furnace glow: the built (idle) colour is C.Glow; while working the client
-- pulses it toward Hot (brightness animated, never a white blob).
MachineBuilder.Glow = { Idle = C.Glow, Hot = rgb(255, 150, 60) }

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

-- Coins get a little shine (everything else is matte and flat, like Kenney).
local function shine(color: Color3, props: Props): Props
	if props.Reflectance == nil and color == C.Coin then
		props.Reflectance = 0.2
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

--[[
	Particle emitters with built-in textures. Kinds: Smoke (chimneys), Steam
	(a short white plume that stays on its vent; named "Smoke" like the
	chimney ones so the client and tests find it the same way), Embers.
]]
local function emitter(parent: Instance, kind: string, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = if kind == "Steam" then "Smoke" else kind
	if kind == "Smoke" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(3, 5)
		e.SpreadAngle = Vector2.new(10, 10)
		e.LightInfluence = 1
	elseif kind == "Steam" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.8) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.6, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(1.5, 2.5)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Drag = 1
		e.LightInfluence = 0.6
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

--[[
	Kenney octagonal pipe flange: four flat bars, 1.4x the pipe diameter long
	and as wide as an octagon side, crossed at 45 degree steps about the pipe
	axis - together exactly a regular octagon (flat top and sides), in the
	light frame colour. `bolts` (0 or 2) brass bolt heads sit on the face
	toward `facing` (+1 / -1 along the axis), in two opposite corners of the
	ring round the pipe. 4 parts + bolts.
]]
local function flange(m: Instance, center: Vector3, axis: Axis, d: number, bolts: number, facing: number?)
	local s = d * 1.4
	local t = math.clamp(d * 0.24, 0.16, 0.3)
	local frame = CFrame.new(center) * FACING[axis]
	local props = if d >= 0.9 then prop() else tiny()
	for k = 0, 3 do
		Geo.block(m, frame * CFrame.Angles(0, 0, k * math.pi / 4), Vector3.new(s, s * math.tan(math.pi / 8), t), C.HousingLight, nil, props)
	end
	if bolts > 0 then
		local out = frame * CFrame.new(0, 0, (facing or 1) * (if axis == "Y" then -1 else 1) * t / 2)
		for _, turn in { 0.39, 0.39 + math.pi } do
			local spot = out * CFrame.new(math.cos(turn) * s * 0.455, math.sin(turn) * s * 0.455, 0)
			ball(m, spot.Position, math.max(0.16, d * 0.2), C.Brass)
		end
	end
end

--[[
	Pipe bend with two kinks (Kenney pipe-large-bend in low poly): a short
	diagonal pipe piece between the ends of the two legs, which stop `r`
	short of the corner (at corner + a * r and corner + b * r; `a`, `b` =
	unit directions from the corner to each leg). It reaches a little into
	both legs so the kinks stay closed. 1 part.
]]
local function bend(m: Instance, corner: Vector3, a: Vector3, b: Vector3, d: number, r: number, color: Color3): Part
	local p1, p2 = corner + a * r, corner + b * r
	return Geo.make(
		"Part",
		prop({
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.lookAt((p1 + p2) / 2, p2) * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new((p2 - p1).Magnitude + d * 0.42, d, d),
			Color = color,
			Material = SMOOTH,
		}),
		m
	)
end

-- Square plate where a pipe leaves a wall facing -Z (`at` on the wall). 1 part.
local function wallPlate(m: Instance, at: Vector3, d: number)
	Geo.block(m, CFrame.new(at + Vector3.new(0, 0, -0.1)), Vector3.new(d * 1.3, d * 1.3, 0.2), C.HousingLight, nil, prop())
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
	Thick light frame around an opening in a wall that faces -Z, standing
	`depth` out of the wall, with a recess plate filling the opening (dark by
	default). `cf` = bottom centre of the opening on the wall surface. `sill`
	closes the frame at the bottom (a window). 4 parts (+1 with a sill).
]]
local function portal(m: Instance, cf: CFrame, w: number, h: number, t: number, depth: number, sill: boolean?, fill: Color3?)
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
	Geo.block(m, cf * CFrame.new(0, h / 2, -0.04), Vector3.new(w, h, 0.1), fill or C.Recess, nil, tiny())
end

--[[
	Short output chute out of a wall facing -Z: a dark iron plate sloping down
	and away from `top` (the plate's top edge centre, on the wall) with two
	thin light side lips. 3 parts.
]]
local function chute(m: Instance, top: Vector3, w: number, length: number, drop: number)
	local angle = math.atan2(drop, length)
	local run = math.sqrt(length * length + drop * drop)
	local cf = CFrame.new(top) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -0.06, -run / 2)
	Geo.block(m, cf, Vector3.new(w, 0.12, run), C.HousingDark, nil, solid())
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(side * (w / 2 + 0.05), 0.1, 0), Vector3.new(0.1, 0.24, run), C.HousingLight, nil, tiny())
	end
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
	its foot, a funnel of `steps` (1 or 2) stepped rings and an optional neck.
	`bottom` = bottom centre, `d` = cup width across the flats. Returns the
	rim height. 10 parts + steps (+1 with a neck).
]]
local function roundHopper(m: Instance, bottom: Vector3, d: number, neck: number, steps: number?): number
	local cf = CFrame.new(bottom)
	local y = 0
	if neck > 0 then
		cyl(m, bottom + Vector3.new(0, neck / 2, 0), "Y", neck, d * 0.42, C.Housing, nil, solid())
		y = neck
	end
	-- funnel: stepped rings narrowing down to the neck (wedges would show
	-- fins at the corners of a round funnel)
	local stepH = d * 0.15
	local count = steps or 2
	for i = 1, count do
		local width = if count == 1 then 0.7 elseif i == 1 then 0.56 else 0.8
		cyl(m, bottom + Vector3.new(0, y + stepH / 2, 0), "Y", stepH, d * width, C.Housing, nil, solid())
		y += stepH
	end
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
	Kenney piston-round as a fuel/water tank: a squat copper body under a
	wide, thick iron cap (about 30% of the height). Returns the top of the
	cap. 2 parts.
]]
local function tank(m: Instance, bottom: Vector3, d: number, h: number, name: string?): number
	local capH = h * 0.3
	local body = h - capH
	cyl(m, bottom + Vector3.new(0, body / 2, 0), "Y", body, d, C.Copper, nil, solid({ Name = name or "Tank" }))
	cyl(m, bottom + Vector3.new(0, body + capH / 2, 0), "Y", capH, d + 0.5, C.Housing, nil, solid())
	return bottom.Y + h
end

--[[
	Valve hand wheel facing along `axis`: an orange hexagon rim, one spoke
	and a brass hub axle reaching back to the valve body at `bodyAt` (on the
	same axis line). 8 parts.
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
	-- spoke corner to corner
	Geo.block(m, frame, Vector3.new(0.1, 2 * r - 2 * bar, 0.1), C.Hazard, nil, tiny())
	cyl(m, (center + bodyAt) / 2, axis, (center - bodyAt).Magnitude + 0.14, 0.24, C.Brass, nil, tiny())
end

--[[
	Kenney pipe-large-valve: a light bulge round the pipe and an orange
	T-handle sticking out of it toward `dir`. 2 parts.
]]
local function valve(m: Instance, center: Vector3, axis: Axis, pipeD: number, dir: Vector3)
	cyl(m, center, axis, 0.45, pipeD * 1.45, C.HousingLight, nil, prop())
	local axisVector = if axis == "X" then Vector3.xAxis elseif axis == "Y" then Vector3.yAxis else Vector3.zAxis
	local out = dir.Unit
	local tip = center + out * (pipeD * 0.725 + 0.08)
	Geo.block(m, CFrame.lookAt(tip, tip + axisVector:Cross(out)), Vector3.new(0.2, 0.2, 0.8), C.Hazard, nil, tiny())
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

-- Round brass axle caps painted on a rail's side (a SurfaceGui, no parts),
-- at `spots` (0..1 along the face) and `height` (0..1 from the top).
local function axleCaps(rail: Part, face: Enum.NormalId, spots: { number }, height: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RailFace"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 1
	gui.MaxDistance = 60
	gui.Parent = rail
	for _, x in spots do
		local dot = Instance.new("Frame")
		dot.Name = "Axle"
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = C.Brass
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(x, height)
		dot.Size = UDim2.fromScale(0.3 / rail.Size.Z, 0.3 / rail.Size.Y)
		dot.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
	end
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
	chunky light U frame round the knee opening, light drawer fronts with
	brass handles, a back panel with a bolted band and a slatted vent, dark
	wooden top with the name plate on its edge), vise at OrePoint (dark jaw
	faces, brass screw block), a copper water pipe rising beside the wash tub
	(mounting plate, a two-kink bend, valve wheel, a bolted octagonal outlet
	flange) that pours into the tub (WaterOut -> WaterIn), tool board,
	screen-panel-small, lever-double, output tray. 69 parts.
]]
local function cleaningStation(): Model
	local model, base = newModel("CleaningStation")
	local top = 3.4 -- bench reference height (the plank top is top + 0.3)
	local benchZ = 0.4
	local front, back = benchZ - 2.3, benchZ + 2.3 -- cabinet faces (z -1.9 / 2.7)
	-- bench cabinet (y 0.3..3.3) with the knee opening in a chunky U frame
	Geo.block(model, CFrame.new(0, 1.8, benchZ), Vector3.new(10, 3, 4.6), C.Housing, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 0.58, benchZ), Vector3.new(10.12, 0.56, 4.72), C.Hazard, nil, prop())
	portal(model, CFrame.new(0, 0.86, front), 3.6, 1.75, 0.5, 0.65, false, C.RecessLight)
	-- drawer fronts on both side panels: light plates, brass handles
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 3.65, 1.95, front - 0.06), Vector3.new(2.2, 1.5, 0.12), C.HousingLight, nil, tiny())
		Geo.block(model, CFrame.new(side * 3.65, 2.4, front - 0.17), Vector3.new(1.0, 0.2, 0.14), C.Brass, nil, tiny())
	end
	-- back panel: a light band with two brass bolts, a vent of three light slats
	Geo.block(model, CFrame.new(0, 2.85, back + 0.05), Vector3.new(10.04, 0.34, 0.12), C.HousingLight, nil, tiny())
	for _, x in { -4.5, 4.5 } do
		ball(model, Vector3.new(x, 2.85, back + 0.13), 0.26, C.Brass)
	end
	for i = 0, 2 do
		Geo.block(model, CFrame.new(2.6, 1.25 + i * 0.45, back + 0.07), Vector3.new(2.6, 0.22, 0.14), C.HousingLight, nil, tiny())
	end
	-- dark wooden work top, the name plate on its front edge
	Geo.block(model, CFrame.new(0, top + 0.1, benchZ), Vector3.new(10.8, 0.4, 5.4), C.WoodDark, nil, solid({ Name = "Bench" }))
	sign(model, CFrame.new(0, top + 0.1, benchZ - 2.775), "CLEANING STATION", 4.6)
	-- work slab + vise: jaws with dark faces, a brass screw block and an
	-- orange T handle out to the front
	Geo.block(model, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), C.HousingDark, nil, solid({ Name = "WorkSlab" }))
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 1.75, top + 0.95, 0.3), Vector3.new(0.5, 0.5, 2.2), C.HousingTop, nil, solid({ Name = "Jaw" }))
		Geo.block(model, CFrame.new(side * 1.46, top + 0.97, 0.3), Vector3.new(0.1, 0.44, 1.9), C.Recess, nil, tiny())
	end
	Geo.block(model, CFrame.new(-1.75, top + 0.95, -0.98), Vector3.new(0.56, 0.44, 0.36), C.Brass, nil, tiny())
	Geo.block(model, CFrame.new(-1.75, top + 0.95, -1.27), Vector3.new(1.2, 0.16, 0.16), C.Hazard, nil, tiny())

	-- copper wash tub left of the vise on a dark foot plinth, a light lip
	-- round its top, filled almost to the lip
	local bx, bz, bw, bd, lip = -4.15, -0.5, 2.3, 2.6, 0.2
	local deck = top + 0.3
	Geo.block(model, CFrame.new(bx, deck + 0.08, bz), Vector3.new(bw - 0.5, 0.16, bd - 0.5), C.HousingDark, nil, tiny())
	local bodyTop = deck + 0.96
	Geo.block(model, CFrame.new(bx, bodyTop - 0.4, bz), Vector3.new(bw, 0.8, bd), C.Copper, nil, solid({ Name = "Tub" }))
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(bx, bodyTop + 0.05, bz + side * (bd / 2 + 0.04 - lip / 2)), Vector3.new(bw + 0.08, 0.3, lip), C.HousingLight, nil, solid())
		Geo.block(model, CFrame.new(bx + side * (bw / 2 + 0.04 - lip / 2), bodyTop + 0.05, bz), Vector3.new(lip, 0.3, bd + 0.08 - 2 * lip), C.HousingLight, nil, solid())
	end
	local poolTop = bodyTop + 0.1
	Geo.block(
		model,
		CFrame.new(bx, poolTop - 0.06, bz),
		Vector3.new(bw + 0.06 - 2 * lip, 0.12, bd + 0.06 - 2 * lip),
		MachineBuilder.Water.Pool,
		nil,
		tiny({ Name = "WaterPool", Transparency = MachineBuilder.Water.PoolTransparency, Reflectance = 0.1 })
	)

	-- copper water pipe, all of it outside the close-up camera's view: it
	-- comes up out of the plot beside the station's left end, bends over the
	-- tub with two kinks, a valve (hand wheel facing the front) on the short
	-- run, and pours out of a bolted octagonal flange
	local pd, px, pipeY, outX = 0.6, -5.7, 6.6, -4.4
	local r = pd * 0.8
	cyl(model, Vector3.new(px, (0.3 + pipeY - r) / 2, bz), "Y", pipeY - r - 0.3, pd, C.Copper, nil, solid())
	bend(model, Vector3.new(px, pipeY, bz), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), pd, r, C.Copper)
	local runFrom = px + r
	cyl(model, Vector3.new((runFrom + outX) / 2, pipeY, bz), "X", outX - runFrom, pd, C.Copper, nil, prop())
	local valveX = (runFrom + outX) / 2 - 0.05
	cyl(model, Vector3.new(valveX, pipeY, bz), "X", 0.42, pd * 1.5, C.HousingLight, nil, prop())
	wheel(model, Vector3.new(valveX, pipeY, bz - 0.72), "Z", 1.0, Vector3.new(valveX, pipeY, bz - 0.45))
	flange(model, Vector3.new(outX + 0.07, pipeY, bz), "X", pd, 2, 1)
	water(base, Vector3.new(outX + 0.2, pipeY - 0.04, bz), Vector3.new(1, 0, 0), Vector3.new(outX + 0.55, poolTop, bz))

	-- tool board at the back: chisel, hammer, brush
	local boardZ = 2.85
	Geo.block(model, CFrame.new(-0.6, top + 1.6, boardZ), Vector3.new(3.6, 2.6, 0.25), C.HousingTop, nil, solid())
	Geo.block(model, CFrame.new(-0.6, top + 2.98, boardZ), Vector3.new(3.75, 0.24, 0.36), C.HousingLight, nil, tiny())
	local toolZ = boardZ - 0.2
	Geo.block(model, CFrame.new(-1.9, top + 1.75, toolZ), Vector3.new(0.24, 1.6, 0.16), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), C.HousingDark, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 1.75, toolZ), Vector3.new(0.7, 1.2, 0.3), C.Cloth, nil, tiny())

	-- screen-panel-small: a chunky panel standing on the top, dark glass
	-- screen with an amber gauge bar
	Geo.block(model, CFrame.new(2.6, top + 1.45, 2.8), Vector3.new(1.8, 2.3, 0.3), C.HousingTop, nil, prop())
	Geo.block(model, CFrame.new(2.6, top + 2.05, 2.63), Vector3.new(1.4, 0.85, 0.06), C.Screen, nil, tiny({ Name = "Screen", Reflectance = 0.25 }))
	Geo.block(model, CFrame.new(2.45, top + 1.92, 2.59), Vector3.new(0.85, 0.12, 0.03), C.Gauge, NEON, tiny({ Name = "Gauge" }))

	-- lever-double on the top, right behind the tray: a light base, two
	-- slanted uprights holding an orange grip
	local lx, lz = 4.7, 1.55
	Geo.block(model, CFrame.new(lx, top + 0.45, lz), Vector3.new(1.0, 0.3, 1.0), C.HousingLight, nil, tiny())
	for _, side in { -1, 1 } do
		Geo.block(
			model,
			CFrame.new(lx + side * 0.24, top + 0.85, lz) * CFrame.Angles(math.rad(-22), 0, 0),
			Vector3.new(0.12, 0.62, 0.16),
			C.HousingDark,
			nil,
			tiny()
		)
	end
	cyl(model, Vector3.new(lx, top + 1.15, lz - 0.12), "X", 0.66, 0.24, C.Hazard, nil, tiny())

	-- output tray on the right: dark floor, iron rims
	Geo.block(model, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), C.HousingDark, nil, solid({ Name = "Tray" }))
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(3.6, top + 0.76, -0.4 + side * 1.22), Vector3.new(2.6, 0.32, 0.16), C.Housing, nil, solid())
		Geo.block(model, CFrame.new(3.6 + side * 1.22, top + 0.76, -0.4), Vector3.new(0.16, 0.32, 2.28), C.Housing, nil, solid())
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
	strap over the top), a mouth in a deep light frame with a dark border, a
	set-back glow behind three grate bars and a latch, a short chute at the
	output, an open round hopper on top (intake) and a large copper chimney
	in two sections between bolted octagonal flanges. 63 parts.
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
	-- the mouth: a deep light frame, a dark recess, a smaller glow set back
	-- inside a dark border, three grate bars in front, a latch
	local out = output(base, "ClayFurnace")
	local mouthX, mouthY, mouthW, mouthH = 1.45, 1.15, 2.2, 2.0
	local wallZ = z0 - 3.0
	portal(model, CFrame.new(mouthX, mouthY, wallZ), mouthW, mouthH, 0.45, 0.7)
	local glow = Geo.block(
		model,
		CFrame.new(mouthX, mouthY + mouthH / 2 - 0.05, wallZ - 0.13),
		Vector3.new(mouthW - 0.3, mouthH - 0.4, 0.08),
		C.Glow,
		NEON,
		tiny({ Name = "Glow" })
	)
	light(glow, C.Glow, 12, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	for i = 1, 3 do
		Geo.block(model, CFrame.new(mouthX, mouthY + i * mouthH / 4, wallZ - 0.32), Vector3.new(mouthW + 0.1, 0.2, 0.18), C.HousingDark, nil, tiny())
	end
	Geo.block(model, CFrame.new(mouthX + mouthW / 2 + 0.23, mouthY + 1.1, wallZ - 0.76), Vector3.new(0.22, 0.5, 0.14), C.Brass, nil, tiny())
	-- short chute below the mouth, above the orange trim
	chute(model, Vector3.new(out.X - 0.55, mouthY + 0.06, wallZ - 0.1), 1.6, 1.55, 0.32)
	sign(model, CFrame.new(mouthX, 3.98, wallZ - 0.08), "CLAY FURNACE", 3.2)
	-- large pipe chimney at the back left: bolted octagonal foot flange, two
	-- copper sections split by a flange, a bolted top flange, a dark mouth
	-- with a thin copper rim
	local cx, cz, cd = -1.9, 2.15, 1.3
	flange(model, Vector3.new(cx, 5.45, cz), "Y", cd, 2, 1)
	cyl(model, Vector3.new(cx, 7.1, cz), "Y", 3.6, cd, C.Copper, nil, solid())
	flange(model, Vector3.new(cx, 7.0, cz), "Y", cd, 0)
	flange(model, Vector3.new(cx, 8.75, cz), "Y", cd, 2, 1)
	local chimneyTop = cyl(model, Vector3.new(cx, 8.93, cz), "Y", 0.06, cd - 0.26, C.Ember, nil, tiny({ Name = "ChimneyTop" }))
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
	iron body, a barred molten window (Glow set back in a deep frame with a
	dark border), a bolted strap across the back, a high square hopper
	(intake) with a flanged copper connection-pipe chimney on the roof behind
	it, a tap whose glass section (between a wall plate and a bolted
	octagonal flange) shows the molten metal running through a two-kink bend
	and a spout stub into an ingot mould at the output (a glowing trickle),
	and two squat piston-round fuel tanks: the front one feeds the body
	through a tall glass riser with glowing fuel, a two-kink bend and an
	octagonal entry flange, the back one is linked to it by a low pipe with a
	valve. 69 parts.
]]
local function blastFurnace(): Model
	local model, base = newModel("BlastFurnace")
	Geo.block(model, CFrame.new(0, 0.6, 0.15), Vector3.new(11.6, 0.6, 10.9), C.Housing, nil, solid())
	local bz = 0.8
	local floor = 0.9 -- plinth top
	housing(model, CFrame.new(0, floor, bz), Vector3.new(6.8, 7.0, 6.4), C.Housing, 0.9)
	local front = bz - 3.2
	local roof = floor + 7.0
	-- molten window: deep light frame, dark recess, a smaller glow set back
	-- inside a dark border, thick grate bars (two uprights, one cross bar)
	local winY, winW, winH = 3.8, 2.8, 2.0
	portal(model, CFrame.new(0, winY, front), winW, winH, 0.45, 0.7, true)
	local glow = Geo.block(
		model,
		CFrame.new(0, winY + winH / 2, front - 0.13),
		Vector3.new(winW - 0.3, winH - 0.3, 0.08),
		C.Glow,
		NEON,
		tiny({ Name = "Glow" })
	)
	light(glow, C.Glow, 17, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	for _, x in { -0.47, 0.47 } do
		Geo.block(model, CFrame.new(x, winY + winH / 2, front - 0.3), Vector3.new(0.3, winH, 0.2), C.HousingDark, nil, tiny())
	end
	Geo.block(model, CFrame.new(0, winY + winH / 2, front - 0.33), Vector3.new(winW, 0.3, 0.2), C.HousingDark, nil, tiny())
	sign(model, CFrame.new(0, 6.75, front - 0.08), "BLAST FURNACE", 3.9)
	-- bolted strap across the back
	Geo.block(model, CFrame.new(0, 4.6, bz + 3.3), Vector3.new(5.4, 0.9, 0.2), C.HousingLight, nil, prop())
	ball(model, Vector3.new(-2.2, 4.6, bz + 3.44), 0.34, C.Brass)
	ball(model, Vector3.new(2.2, 4.6, bz + 3.44), 0.34, C.Brass)

	-- tap: a plate on the body, a big glass section with molten metal, a
	-- bolted octagonal flange, a two-kink bend down into a short spout stub,
	-- a glowing trickle into an ingot mould at the output
	local out = output(base, "BlastFurnace")
	local tapY, glassD, pipeD = 2.55, 1.1, 0.8
	wallPlate(model, Vector3.new(out.X, tapY, front), glassD)
	local glassFrom, glassTo = front - 0.2, front - 1.5
	cyl(model, Vector3.new(out.X, tapY, (glassFrom + glassTo) / 2), "Z", glassFrom - glassTo, glassD, C.Glass, GLASS, tiny({ Transparency = 0.5 }))
	cyl(model, Vector3.new(out.X, tapY, (glassFrom + glassTo) / 2), "Z", glassFrom - glassTo + 0.02, 0.5, C.Molten, NEON, tiny({ Name = "Molten" }))
	flange(model, Vector3.new(out.X, tapY, glassTo - 0.13), "Z", glassD, 2, -1)
	local tapR = 0.5
	local cornerZ = glassTo - 0.26 - tapR
	bend(model, Vector3.new(out.X, tapY, cornerZ), Vector3.new(0, 0, 1), Vector3.new(0, -1, 0), pipeD, tapR, C.Copper)
	local spoutTop, spoutBottom = tapY - tapR, tapY - tapR - 0.32
	cyl(model, Vector3.new(out.X, (spoutTop + spoutBottom) / 2, cornerZ), "Y", spoutTop - spoutBottom, pipeD, C.Copper, nil, prop())
	local mouldTop = floor + 0.16
	cyl(model, Vector3.new(out.X, (spoutBottom + mouldTop) / 2, cornerZ), "Y", spoutBottom - mouldTop + 0.04, 0.3, C.Molten, NEON, tiny({ Name = "Molten" }))
	Geo.block(model, CFrame.new(out.X, floor + 0.08, cornerZ), Vector3.new(1.6, 0.16, 1.0), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(out.X, mouldTop + 0.01, cornerZ), Vector3.new(1.2, 0.04, 0.62), C.Glow, NEON, tiny({ Name = "Molten" }))

	-- high square hopper on top (the intake)
	squareHopper(model, CFrame.new(0, roof, 0.1), 3.2, 5.0, 1.3, 1.5, 0.4)
	-- connection-pipe chimney out of the roof behind the hopper: a copper
	-- pipe split by an octagonal flange above the hopper, a top flange and a
	-- dark mouth with a thin copper rim
	local cx, cz, cd, chimneyTo = -1.5, 3.25, 1.0, 12.7
	cyl(model, Vector3.new(cx, (roof + chimneyTo) / 2, cz), "Y", chimneyTo - roof, cd, C.Copper, nil, solid())
	flange(model, Vector3.new(cx, 11.6, cz), "Y", cd, 0)
	flange(model, Vector3.new(cx, chimneyTo - 0.15, cz), "Y", cd, 0)
	local chimneyTop = cyl(model, Vector3.new(cx, chimneyTo + 0.03, cz), "Y", 0.06, cd - 0.24, C.Ember, nil, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", rgb(110, 100, 96), 5)

	-- fuel tanks on the right: the front one feeds the body through a tall
	-- glass riser of glowing fuel, a two-kink bend and an octagonal entry flange;
	-- a low pipe with a valve links the back tank to it
	local tx, frontZ, backZ = 4.75, -1.2, 2.6
	local side = 3.4 -- body right face
	local capTop = tank(model, Vector3.new(tx, floor, frontZ), 2.0, 2.5)
	tank(model, Vector3.new(tx, floor, backZ), 2.0, 2.5)
	local entryY = 6.05
	local feedD, feedR = 0.9, 0.62
	local glassTop = entryY - feedR
	cyl(model, Vector3.new(tx, (capTop + glassTop) / 2, frontZ), "Y", glassTop - capTop, 1.0, C.Glass, GLASS, tiny({ Transparency = 0.5 }))
	cyl(model, Vector3.new(tx, (capTop + glassTop) / 2, frontZ), "Y", glassTop - capTop + 0.02, 0.46, C.Molten, NEON, tiny({ Name = "Molten" }))
	bend(model, Vector3.new(tx, entryY, frontZ), Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0), feedD, feedR, C.Copper)
	local runTo = side + 0.22
	cyl(model, Vector3.new((tx - feedR + runTo) / 2, entryY, frontZ), "X", tx - feedR - runTo, feedD, C.Copper, nil, prop())
	flange(model, Vector3.new(side + 0.11, entryY, frontZ), "X", feedD, 0)
	-- the low link between the two tanks, its valve handle up
	local linkY = floor + 1.0
	cyl(model, Vector3.new(tx, linkY, (frontZ + backZ) / 2), "Z", backZ - frontZ - 1.8, 0.7, C.Copper, nil, prop())
	valve(model, Vector3.new(tx, linkY, (frontZ + backZ) / 2), "Z", 0.7, Vector3.new(0, 1, 0))

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return model
end

--[[
	Crusher (2x2): Kenney machine-window housing with a high square hopper,
	the intake, holding two dark rollers with narrow steel teeth low in its
	dark throat, a big cog-a and a smaller cog-c meshing on each side of the
	housing (Cog1 / Cog2, they turn with the rollers), an output slot with a
	short chute above the base trim, hazard chevrons and a piston-square
	drive at the back. 68 parts.
]]
local function crusher(): Model
	local model, base = newModel("Crusher")
	local bz = 0.35
	housing(model, CFrame.new(0, 0.3, bz), Vector3.new(6.2, 4.0, 5.0), C.Housing, 0.6)
	local front = bz - 2.5
	-- window (front left)
	portal(model, CFrame.new(-1.4, 1.5, front), 1.8, 1.4, 0.35, 0.4, true)
	Geo.block(model, CFrame.new(-1.4, 2.2, front - 0.1), Vector3.new(1.8, 1.4, 0.06), C.Glass, GLASS, tiny({ Transparency = 0.35 }))
	-- output slot (front right, at the output column) and a short chute
	local out = output(base, "Crusher")
	portal(model, CFrame.new(out.X, 1.0, front), 1.5, 1.0, 0.3, 0.4)
	chute(model, Vector3.new(out.X, 1.12, front - 0.35), 1.4, 0.9, 0.1)
	-- hazard chevrons on the base band
	for _, x in { -2.4, -1.6, -0.8 } do
		Geo.block(
			model,
			CFrame.new(x, 0.58, front - 0.09) * CFrame.Angles(0, 0, math.rad(40)),
			Vector3.new(0.24, 0.62, 0.04),
			C.HazardDark,
			nil,
			tiny()
		)
	end
	-- high square hopper (cup 5.85..7.1) with the rollers low in its throat:
	-- dark drums with four narrow steel teeth each (two bars) standing a
	-- little proud, and brass cog discs on their ends
	squareHopper(model, CFrame.new(0, 4.3, bz), 3.6, 5.8, 1.1, 1.25, 0.4)
	local rollerY, rollerD = 5.8, 1.5
	for i, dz in { -0.95, 0.95 } do
		local c = Vector3.new(0, rollerY, bz + dz)
		cyl(model, c, "X", 4.9, rollerD, C.HousingDark, nil, solid({ Name = "Roller" .. i }))
		for k = 0, 1 do
			Geo.block(
				model,
				CFrame.new(c) * CFrame.Angles(k * math.pi / 2 + i * math.pi / 4, 0, 0),
				Vector3.new(4.3, rollerD + 0.4, 0.15),
				rgb(104, 108, 122),
				nil,
				tiny({ Name = "Roller" .. i .. "Tooth" })
			)
		end
		for _, x in { -2.3, 2.3 } do
			cyl(model, c + Vector3.new(x, 0, 0), "X", 0.14, rollerD + 0.36, C.Brass, nil, tiny({ Name = "Roller" .. i .. "Tooth" }))
		end
	end
	-- a big and a small cog meshing on both sides of the housing, on axle
	-- stubs (both sides share the axis lines, so each pair turns as one)
	local cogX = 3.1 + 0.22
	local bigY, bigZ = 2.75, bz - 0.85
	local reach = (COG_BIG + COG_SMALL) * 0.45
	local smallY, smallZ = bigY + reach * math.sin(0.26), bigZ + reach * math.cos(0.26)
	for _, s in { 1, -1 } do
		cog(model, Vector3.new(s * cogX, bigY, bigZ), COG_BIG, 0.36, 4, s, 0.25, "Cog1")
		cog(model, Vector3.new(s * cogX, smallY, smallZ), COG_SMALL, 0.36, 3, s, 0.25, "Cog2")
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
	short striped roller conveyor (conveyor-bars-stripe-high: grey rollers
	named BedRoller between low light rails with painted brass axle caps,
	chevrons on the bed's front), a brush Drum hanging in front of the arch
	from two robot-arm-b style arms (two segments, an orange collar), a squat
	copper water tank whose riser (with a valve) bends into a spray bar with
	a bolted end flange and a shower head that sprays onto the ore (WaterOut
	-> WaterIn), an open round hopper at the back, a steam Vent, a warning-
	traffic stack light and a short output chute. 68 parts.
]]
local function autoCleaner(): Model
	local model, base = newModel("AutoCleaner")
	local cx, z0, z1 = 0.9, -3.5, 3.3
	local len, zc = z1 - z0, (z0 + z1) / 2
	-- roller conveyor bed: low light rails just above the rollers
	Geo.block(model, CFrame.new(cx, 0.9, zc), Vector3.new(3.0, 1.2, len), C.Housing, nil, solid({ Name = "Bed" }))
	Geo.block(model, CFrame.new(cx, 0.58, zc), Vector3.new(3.12, 0.56, len + 0.12), C.Hazard, nil, prop())
	local rollerY, rollers = 1.85, {}
	for i = 0, 4 do
		local z = z0 + 0.7 + i * 1.35
		table.insert(rollers, (z - z0) / len)
		cyl(model, Vector3.new(cx, rollerY, z), "X", 3.0, 0.62, C.Roller, nil, solid({ Name = "BedRoller" }))
	end
	for _, s in { -1, 1 } do
		local rail = Geo.block(model, CFrame.new(cx + s * 1.65, 1.875, zc), Vector3.new(0.3, 0.75, len), C.HousingLight, nil, solid())
		axleCaps(rail, if s < 0 then Enum.NormalId.Left else Enum.NormalId.Right, rollers, (2.25 - rollerY) / 0.75)
	end
	-- chevrons on the orange band of the bed's front
	for _, dx in { -0.55, 0.55 } do
		Geo.block(
			model,
			CFrame.new(cx + dx, 0.58, z0 - 0.09) * CFrame.Angles(0, 0, math.rad(40)),
			Vector3.new(0.26, 0.62, 0.04),
			C.HazardDark,
			nil,
			tiny()
		)
	end
	-- scanner arch: orange feet, legs, light collars, rounded top corners
	local az = 0.3
	for _, s in { -1, 1 } do
		local lx = cx + s * 2.35
		Geo.block(model, CFrame.new(lx, 0.65, az), Vector3.new(1.1, 0.7, 1.15), C.Hazard, nil, solid())
		Geo.block(model, CFrame.new(lx, 3.175, az), Vector3.new(0.9, 4.35, 0.9), C.Housing, nil, solid())
		Geo.block(model, CFrame.new(lx, 4.25, az), Vector3.new(1.04, 0.3, 1.04), C.HousingLight, nil, tiny())
		cyl(model, Vector3.new(lx, 5.35, az), "Z", 0.9, 0.9, C.Housing, nil, solid())
	end
	Geo.block(model, CFrame.new(cx, 5.35, az), Vector3.new(4.7, 0.9, 0.9), C.Housing, nil, solid({ Name = "Arch" }))
	sign(model, CFrame.new(cx, 6.16, az), "AUTO CLEANER", 2.9)
	-- brush drum (dark bristles) in front of the arch, on two robot-arm-b
	-- arms: an upper segment, an orange collar, a lower segment slanting
	-- forward to the drum's axle
	local drumC = Vector3.new(cx, 3.3, -0.25)
	cyl(model, drumC, "X", 2.9, 1.0, C.Brass, nil, solid({ Name = "Drum" }))
	for k = 0, 1 do
		Geo.block(
			model,
			CFrame.new(drumC) * CFrame.Angles(k * math.pi / 2, 0, 0),
			Vector3.new(2.7, 1.4, 0.34),
			C.Bristle,
			nil,
			tiny({ Name = "DrumRib" })
		)
	end
	for _, s in { -1, 1 } do
		local ax = cx + s * 1.62
		Geo.block(model, CFrame.new(ax, 4.55, az), Vector3.new(0.38, 0.7, 0.42), C.Housing, nil, tiny())
		Geo.block(model, CFrame.new(ax, 4.15, az), Vector3.new(0.48, 0.2, 0.52), C.Hazard, nil, tiny())
		local from, to = Vector3.new(ax, 4.05, az), Vector3.new(ax, drumC.Y, drumC.Z)
		Geo.block(model, CFrame.lookAt((from + to) / 2, to), Vector3.new(0.32, 0.34, (to - from).Magnitude + 0.2), C.HousingLight, nil, tiny())
	end
	-- water: squat copper tank (front left), riser with a valve, a two-kink
	-- bend into the spray bar (bolted end flange) with a shower head over
	-- the bed
	local tx, tz = -2.75, -1.85
	local capTop = tank(model, Vector3.new(tx, 0.3, tz), 2.0, 2.4)
	local barY, barD = 4.7, 0.55
	local barR = barD * 0.85
	cyl(model, Vector3.new(tx, (capTop + barY - barR) / 2, tz), "Y", barY - barR - capTop, barD, C.Copper, nil, prop())
	valve(model, Vector3.new(tx, capTop + 0.75, tz), "Y", barD, Vector3.new(0, 0, -1))
	bend(model, Vector3.new(tx, barY, tz), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), barD, barR, C.Copper)
	local barEnd = cx + 1.0
	cyl(model, Vector3.new((tx + barR + barEnd) / 2, barY, tz), "X", barEnd - tx - barR, barD, C.Copper, nil, prop())
	flange(model, Vector3.new(barEnd + 0.06, barY, tz), "X", barD, 2, 1)
	Geo.block(model, CFrame.new(cx, barY - 0.36, tz), Vector3.new(1.3, 0.2, 0.5), C.HousingLight, nil, tiny({ Name = "ShowerHead" }))
	water(base, Vector3.new(cx, barY - 0.48, tz), Vector3.new(0, -1, 0), Vector3.new(cx, 2.3, tz), true)
	-- open round hopper at the back on a bridge over the rails
	Geo.block(model, CFrame.new(cx, 2.6, 2.6), Vector3.new(3.7, 0.35, 1.4), C.HousingLight, nil, solid())
	roundHopper(model, Vector3.new(cx, 2.775, 2.6), 2.6, 0, 2)
	-- exhaust vent: a short white steam plume (more while working)
	cyl(model, Vector3.new(3.2, 2.25, 3.1), "Y", 3.9, 0.7, C.Housing, nil, prop())
	local vent = cyl(model, Vector3.new(3.2, 4.37, 3.1), "Y", 0.35, 0.95, C.HousingLight, nil, tiny({ Name = "Vent" }))
	emitter(vent, "Steam", rgb(236, 238, 240), 3)
	-- warning-traffic light: green / amber / red on a post under a cap; one
	-- lamp is lit (the client picks it by state)
	local sx, sz = -3.25, -3.6
	cyl(model, Vector3.new(sx, 1.6, sz), "Y", 2.6, 0.3, C.HousingDark, nil, prop())
	local lampY = 2.9
	for _, name in { "StackGreen", "StackAmber", "StackRed" } do
		local lit = name == MachineBuilder.Stack.Lit
		local color = MachineBuilder.Stack.Lamps[name]
		cyl(
			model,
			Vector3.new(sx, lampY + 0.16, sz),
			"Y",
			0.3,
			0.55,
			if lit then color else color:Lerp(Color3.new(0, 0, 0), MachineBuilder.Stack.Dim),
			if lit then NEON else SMOOTH,
			tiny({ Name = name })
		)
		lampY += 0.32
	end
	cyl(model, Vector3.new(sx, lampY + 0.1, sz), "Y", 0.2, 0.64, C.HousingLight, nil, tiny())
	-- short output chute off the front of the bed
	output(base, "AutoCleaner")
	chute(model, Vector3.new(cx, 2.0, z0 - 0.02), 2.7, 1.0, 0.35)

	attach(base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return model
end

-- Sell Chute (retired): an open round hopper on a copper pipe that goes into
-- the ground through an octagonal flange, a pile of gold coins (Coins, a
-- small glowing centre) in its cup and a SELL plate.
local function sellChute(): Model
	local model, base = newModel("SellChute")
	flange(model, Vector3.new(0, 0.42, 0), "Y", 1.1, 2, 1)
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
