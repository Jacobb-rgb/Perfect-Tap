--[[
	Machine models (pure builders, used by the server and for build-mode ghosts).

	Style: the Kenney Factory Kit (docs/KENNEY_FACTORY_KIT.md, ART_DIRECTION
	section 9) rebuilt from parts in the forge palette: one matte forged-iron
	body colour (mid-tone, so shaded sides stay readable) with lighter tops
	and thick light frames around openings, sparse orange accents (base trims,
	feet, handles), matte copper pipes with octagonal flanges and two-kink
	bends (a pipe-wide ball joint in each kink), open hoppers on top as the
	intake (square on the Crusher, round on the Clay Furnace and Auto Cleaner,
	an octagonal connection pipe with a molten throat on the Blast Furnace),
	piston-round tanks (light band, octagonal cap), cogs, glass pipe sections
	with molten metal, and water that pours out of pipes (the client animates
	the stream between WaterOut and WaterIn, see MachineFxController). Flat
	details (hazard dashes, hatches, rivets) are painted with SurfaceGuis, so
	they cost no parts.

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
	DrumRib, BedRoller, Glow, Molten, StackRed/Amber/Green, WaterPool). Balls
	bigger than a bolt are only PipeJoint (in a bend's kink) and ArmJoint (the
	Auto Cleaner's elbows); Chute / ChuteLip are the only parts that reach out
	of the footprint (toward the Output).
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
	-- (mid-tone sides so shaded faces never go near-black at dusk)
	Housing = rgb(122, 128, 146),
	HousingTop = rgb(156, 162, 180),
	HousingLight = rgb(184, 188, 200),
	HousingDark = rgb(86, 90, 106),
	Recess = rgb(40, 40, 50),
	RecessLight = rgb(104, 108, 124), -- openings on the Cleaning Station (no black voids)
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
	Bristle = rgb(34, 92, 100), -- brush core (dark teal)
	BristleTip = rgb(58, 146, 150), -- brush rings
	Glass = rgb(176, 222, 240),
	Screen = rgb(30, 40, 48),
	-- the Iron Box: a gunmetal strongbox with bright steel straps (not the
	-- blue machine housing, so it never reads as a Crusher) and a lit screen
	Iron = rgb(96, 100, 106),
	IronTop = rgb(134, 138, 144),
	Steel = rgb(196, 200, 206),
	ScreenLit = rgb(16, 70, 64), -- dark teal glow, so the bright text reads
	ScreenText = rgb(196, 255, 236),
	Keep = rgb(70, 164, 92), -- the Iron Box's KEEP flap (green: into the pen)
	Gauge = rgb(220, 132, 40),
	Water = rgb(62, 152, 196),
	Red = rgb(235, 70, 60),
	Amber = rgb(255, 176, 40),
	Green = rgb(80, 210, 110),
	Smoke = rgb(150, 140, 135), -- chimney smoke: light warm grey
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
	Dim = 0.3, -- unlit lamps: colour lerped this far toward black (they keep their hue)
	Glow = 0.3, -- the lit (Neon) lamp too, so it glows in its colour instead of blooming white
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

-- Name plate: dark iron board, gold letters on its front (-Z) face, and on
-- its back too when it stands free (seen from both sides).
local function sign(parent: Instance, cf: CFrame, text: string, width: number, both: boolean?): Part
	local board = Geo.block(parent, cf, Vector3.new(width, 0.7, 0.15), C.HousingDark, nil, tiny())
	local faces: { Enum.NormalId } = { Enum.NormalId.Front }
	if both then
		table.insert(faces, Enum.NormalId.Back)
	end
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
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
	end
	return board
end

---------------------------------------------------------------- paint
-- Flat details painted on a face with a SurfaceGui (no parts): hazard
-- dashes, rivets, hatches. Conveyors stay at 6 parts this way.

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

-- `n` hazard dashes (orange / dark) as gradient keypoints.
local function hazardKeys(n: number): { ColorSequenceKeypoint }
	local keys = {}
	for s = 0, n - 1 do
		local color = if s % 2 == 0 then C.Hazard else C.HazardDark
		table.insert(keys, ColorSequenceKeypoint.new(if s == 0 then 0 else s / n + 0.002, color))
		table.insert(keys, ColorSequenceKeypoint.new((s + 1) / n, color))
	end
	return keys
end

-- A plain painted plate (x, y, w, h in face scale, 0..1 from the top left);
-- `round` paints a disc (a rivet head).
local function paintRect(gui: SurfaceGui, name: string, x: number, y: number, w: number, h: number, color: Color3, round: boolean?)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.Parent = gui
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
end

-- The back of a free-standing panel (tool board, screen): an inset iron
-- plate with a light brace across it and brass rivets in its corners.
local function panelBack(part: Part)
	local gui = surface(part, "BackFace", Enum.NormalId.Back, 60)
	paintRect(gui, "Inset", 0.1, 0.1, 0.8, 0.8, C.Housing)
	paintRect(gui, "Brace", 0.1, 0.46, 0.8, 0.08, C.HousingLight)
	for _, x in { 0.15, 0.85 } do
		for _, y in { 0.15, 0.85 } do
			paintRect(gui, "Rivet", x - 0.03, y - 0.03, 0.06, 0.06 * part.Size.X / part.Size.Y, C.Brass, true)
		end
	end
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

-- Frame whose local Z points straight down (an upright octagonal prism).
local UPRIGHT = CFrame.Angles(math.pi / 2, 0, 0)

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

local TAN8 = math.tan(math.pi / 8)

-- A bend piece reaches JOINT x its diameter past a kink hidden in a wall
-- (tan(22.5 deg) / 2: the outer edges just meet there).
local JOINT = TAN8 / 2

-- Cylinder from `a` to `b` (any direction). 1 part.
local function pipeBetween(m: Instance, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, props: Props?): Part
	return Geo.make(
		"Part",
		merge({
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new((b - a).Magnitude, d, d),
			Color = color,
			Material = material or SMOOTH,
		}, shine(color, props or prop())),
		m
	)
end

-- Block from `a` to `b` with a `w` x `h` cross-section (`a` -> `b` must not
-- be vertical). 1 part.
local function barBetween(m: Instance, a: Vector3, b: Vector3, w: number, h: number, color: Color3, props: Props?): Part
	return Geo.block(m, CFrame.lookAt((a + b) / 2, b), Vector3.new(w, h, (b - a).Magnitude), color, nil, props or tiny())
end

--[[
	Octagonal prism along `frame`'s local Z: four bars `across` long (the
	width across the flats) and as wide as an octagon side, crossed at 45
	degree steps - together exactly a regular octagon with flat top and
	sides. 4 parts.
]]
local function octagon(m: Instance, frame: CFrame, across: number, thick: number, color: Color3, props: Props)
	for k = 0, 3 do
		Geo.block(m, frame * CFrame.Angles(0, 0, k * math.pi / 4), Vector3.new(across, across * TAN8, thick), color, nil, props)
	end
end

--[[
	Kenney octagonal pipe flange: an octagon 1.4x the pipe diameter across,
	in the light frame colour. `bolts` (0 or 2) brass bolt heads sit on the
	face toward `facing` (+1 / -1 along the axis), in two opposite corners of
	the ring round the pipe. 4 parts + bolts.
]]
local function flange(m: Instance, center: Vector3, axis: Axis, d: number, bolts: number, facing: number?)
	local s = d * 1.4
	local t = math.clamp(d * 0.24, 0.16, 0.3)
	local frame = CFrame.new(center) * FACING[axis]
	octagon(m, frame, s, t, C.HousingLight, if d >= 0.9 then prop() else tiny())
	if bolts > 0 then
		local out = frame * CFrame.new(0, 0, (facing or 1) * (if axis == "Y" then -1 else 1) * t / 2)
		for _, turn in { 0.39, 0.39 + math.pi } do
			local spot = out * CFrame.new(math.cos(turn) * s * 0.455, math.sin(turn) * s * 0.455, 0)
			ball(m, spot.Position, math.max(0.16, d * 0.2), C.Brass)
		end
	end
end

--[[
	Pipe bend with two kinks (Kenney pipe-large-bend in low poly): a
	diagonal pipe piece between the ends of the two legs at p1 = corner +
	a * r and p2 = corner + b * r (`a`, `b` = unit directions from the
	corner to each leg; the legs end exactly there). A ball as wide as the
	pipe sits in each kink (PipeJoint): the cylinders meet it in great
	circles, so the kink is a smooth knuckle with no mitre gap. `joints` = 1
	when the second kink is inside a wall (the piece reaches into it
	instead). 3 parts (2 with joints = 1).
]]
local function bend(m: Instance, corner: Vector3, a: Vector3, b: Vector3, d: number, r: number, color: Color3, joints: number?): Part
	local p1, p2 = corner + a * r, corner + b * r
	ball(m, p1, d, color, prop({ Name = "PipeJoint" }))
	local tail = Vector3.zero
	if (joints or 2) >= 2 then
		ball(m, p2, d, color, prop({ Name = "PipeJoint" }))
	else
		tail = (p2 - p1).Unit * d * JOINT
	end
	return pipeBetween(m, p1, p2 + tail, d, color)
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
	thin light side lips (Chute, ChuteLip: the only parts that may reach out
	of the footprint, toward the Output). 3 parts.
]]
local function chute(m: Instance, top: Vector3, w: number, length: number, drop: number)
	local angle = math.atan2(drop, length)
	local run = math.sqrt(length * length + drop * drop)
	local cf = CFrame.new(top) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -0.06, -run / 2)
	Geo.block(m, cf, Vector3.new(w, 0.12, run), C.HousingDark, nil, solid({ Name = "Chute" }))
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(side * (w / 2 + 0.05), 0.1, 0),
			Vector3.new(0.1, 0.24, run),
			C.HousingLight,
			nil,
			tiny({ Name = "ChuteLip" })
		)
	end
end

--[[
	Kenney hopper-square: a tapered neck (4 wedges), a light collar band and an
	open cup (4 walls) with a dark throat floor. `cf` = bottom centre of the
	taper. `color` / `collarColor` default to the machine housing and its
	light frame colour. Returns the height of the cup rim above `cf`. 10 parts.
]]
local function squareHopper(
	m: Instance,
	cf: CFrame,
	bottomW: number,
	topW: number,
	taperH: number,
	cupH: number,
	wall: number,
	color: Color3?,
	collarColor: Color3?
): number
	local body = color or C.Housing
	local run = (topW - bottomW) / 2
	for i = 0, 3 do
		local side = cf * CFrame.Angles(0, i * math.pi / 2, 0)
		-- upside-down wedge: flat face on top, slope down toward the middle
		Geo.wedge(
			m,
			side * CFrame.new(0, taperH / 2, -(bottomW / 2 + run / 2)) * CFrame.Angles(0, 0, math.pi),
			Vector3.new(topW, taperH, run),
			body,
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
		Geo.block(m, cf * CFrame.new(0, cupY + cupH / 2, side * (topW / 2 - wall / 2)), Vector3.new(topW, cupH, wall), body, nil, solid())
		Geo.block(
			m,
			cf * CFrame.new(side * (topW / 2 - wall / 2), cupY + cupH / 2, 0),
			Vector3.new(wall, cupH, topW - 2 * wall),
			body,
			nil,
			solid()
		)
	end
	Geo.block(m, cf * CFrame.new(0, cupY + 0.05, 0), Vector3.new(topW - 2 * wall, 0.1, topW - 2 * wall), C.Recess, nil, solid())
	return cupY + cupH
end

-- Open octagonal cup: 8 wall blocks whose outer corners meet, `across` the
-- flats, standing on `bottom`. 8 parts.
local function octCup(m: Instance, bottom: Vector3, across: number, wall: number, height: number, color: Color3)
	local apothem = across / 2
	local side = 2 * apothem * TAN8 + 0.02
	for i = 0, 7 do
		Geo.block(
			m,
			CFrame.new(bottom) * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, height / 2, -(apothem - wall / 2)),
			Vector3.new(side, height, wall),
			color,
			nil,
			solid()
		)
	end
end

--[[
	Kenney hopper-round: an open octagonal cup (8 wall blocks, the inner wall
	shows) with a dark floor sunk 0.6 below the rim, a light collar band round
	its foot, a funnel of `steps` (1 or 2) stepped rings and an optional neck.
	`bottom` = bottom centre, `d` = cup width across the flats. Returns the
	rim height. 10 parts + steps (+1 with a neck).
]]
local function roundHopper(m: Instance, bottom: Vector3, d: number, neck: number, steps: number?): number
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
	octCup(m, bottom + Vector3.new(0, y, 0), d, wall, cupH, C.Housing)
	-- light collar band round the foot of the cup
	local collarH = cupH * 0.42
	cyl(m, bottom + Vector3.new(0, y + collarH / 2, 0), "Y", collarH, d * 1.16, C.HousingLight, nil, solid())
	-- dark floor, reaching the inner corners
	local rim = y + cupH
	cyl(m, bottom + Vector3.new(0, rim - 0.6, 0), "Y", 0.1, (apothem - wall) * 2 * 1.08, C.Recess, nil, solid())
	return bottom.Y + rim
end

--[[
	Kenney piston-round as a fuel tank: a copper body on a narrower dark foot
	ring (the body bulges out over it), a light band just under the cap, a
	wide octagonal iron cap and a smaller dark disc on top of it (the
	chamfered top). `bottom` = bottom centre. Returns the top of the cap.
	8 parts.
]]
local function tank(m: Instance, bottom: Vector3, d: number, h: number, name: string?): number
	local foot, band, capH = 0.26, 0.18, 0.46
	local bodyTop = h - capH - band
	cyl(m, bottom + Vector3.new(0, foot / 2, 0), "Y", foot, d - 0.3, C.HousingDark, nil, prop())
	cyl(m, bottom + Vector3.new(0, (foot + bodyTop) / 2, 0), "Y", bodyTop - foot, d, C.Copper, nil, solid({ Name = name or "Tank" }))
	cyl(m, bottom + Vector3.new(0, bodyTop + band / 2, 0), "Y", band, d + 0.12, C.HousingLight, nil, prop())
	octagon(m, CFrame.new(bottom + Vector3.new(0, h - capH / 2, 0)) * UPRIGHT, d + 0.5, capH, C.Housing, solid())
	cyl(m, bottom + Vector3.new(0, h + 0.04, 0), "Y", 0.08, d - 0.1, C.HousingDark, nil, tiny())
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
	Kenney pipe-large-valve: a light bulge 1.7x the pipe between two thin iron
	collar rings, and a long orange T handle on top of the bulge, toward
	`dir`. 4 parts.
]]
local function valve(m: Instance, center: Vector3, axis: Axis, pipeD: number, dir: Vector3)
	local axisVector = if axis == "X" then Vector3.xAxis elseif axis == "Y" then Vector3.yAxis else Vector3.zAxis
	cyl(m, center, axis, 0.5, pipeD * 1.7, C.HousingLight, nil, prop())
	for _, s in { -1, 1 } do
		cyl(m, center + axisVector * s * 0.33, axis, 0.12, pipeD * 1.3, C.Housing, nil, tiny())
	end
	local out = dir.Unit
	local tip = center + out * (pipeD * 0.85 + 0.1)
	Geo.block(m, CFrame.lookAt(tip, tip + axisVector:Cross(out)), Vector3.new(0.24, 0.24, 1.15), C.Hazard, nil, tiny())
end

--[[
	Kenney cog: disc, `bars` tooth bars (2 teeth each) and, when `axle` > 0, a
	hub axle that reaches `axle` studs back into the housing (toward -side on
	X). Turns around X; every part carries `name` so the client spins them
	together.
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
	if axle > 0 then
		local inner = center.X - side * (thick / 2 + axle)
		local outer = center.X + side * (thick / 2 + 0.08)
		cyl(
			m,
			Vector3.new((inner + outer) / 2, center.Y, center.Z),
			"X",
			math.abs(outer - inner),
			d * 0.3,
			C.Housing,
			nil,
			tiny({ Name = name })
		)
	end
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
	Cleaning Station (3x2): Kenney machine-bed workbench: an iron cabinet
	with a chunky light U frame round a shallow, light knee opening (a shelf
	with a box-long inside, the name plate on the frame), light drawer fronts
	with brass handles, a back panel with a light band and vent slats; the
	work top in the light top colour with a chamfered front edge over a light
	edge band. Vise at OrePoint (dark jaw faces, brass screw block), a copper
	water pipe rising beside the wash tub (a two-kink bend with ball joints,
	valve wheel, a bolted octagonal outlet flange) that pours into the tub
	(WaterOut -> WaterIn), a light tool board, screen-panel-small (LampShade,
	gauge LampBulb), lever-double, output tray open to the front. 70 parts.
]]
local function cleaningStation(): Model
	local model, base = newModel("CleaningStation")
	local top = 3.4 -- bench reference height (the work top's surface is top + 0.3)
	local benchZ = 0.4
	local front, back = benchZ - 2.3, benchZ + 2.3 -- cabinet faces (z -1.9 / 2.7)
	-- bench cabinet (y 0.3..3.3) with a shallow knee opening in a chunky U
	-- frame, the name plate on its top bar, a shelf with a box inside
	Geo.block(model, CFrame.new(0, 1.8, benchZ), Vector3.new(10, 3, 4.6), C.Housing, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 0.58, benchZ), Vector3.new(10.12, 0.56, 4.72), C.Hazard, nil, prop())
	local kneeH, kneeT, kneeDepth = 1.55, 0.5, 0.4
	portal(model, CFrame.new(0, 0.86, front), 3.6, kneeH, kneeT, kneeDepth, false, C.RecessLight)
	sign(model, CFrame.new(0, 0.86 + kneeH + kneeT / 2, front - kneeDepth + 0.05 - 0.085), "CLEANING STATION", 4.6)
	Geo.block(model, CFrame.new(0, 1.55, front - 0.16), Vector3.new(3.6, 0.14, 0.32), C.HousingLight, nil, tiny())
	Geo.block(model, CFrame.new(-0.85, 1.845, front - 0.17), Vector3.new(1.1, 0.45, 0.3), C.Copper, nil, tiny())
	-- drawer fronts on both side panels: light plates, brass handles
	for _, side in { -1, 1 } do
		Geo.block(model, CFrame.new(side * 3.65, 1.95, front - 0.06), Vector3.new(2.2, 1.5, 0.12), C.HousingLight, nil, tiny())
		Geo.block(model, CFrame.new(side * 3.65, 2.4, front - 0.17), Vector3.new(1.0, 0.2, 0.14), C.Brass, nil, tiny())
	end
	-- back panel: a light band, a vent of two light slats
	Geo.block(model, CFrame.new(0, 2.85, back + 0.05), Vector3.new(10.04, 0.34, 0.12), C.HousingLight, nil, tiny())
	for i = 0, 1 do
		Geo.block(model, CFrame.new(2.6, 1.35 + i * 0.5, back + 0.07), Vector3.new(2.6, 0.24, 0.14), C.HousingLight, nil, tiny())
	end
	-- work top: a light edge band standing out all round, the top in the
	-- light top colour, its front edge chamfered (a wedge) like the bevels
	-- of the Kenney housings
	Geo.block(model, CFrame.new(0, top - 0.01, benchZ), Vector3.new(10.5, 0.18, 5.6), C.HousingLight, nil, prop())
	local deck = top + 0.3
	Geo.block(model, CFrame.new(0, deck - 0.12, benchZ + 0.2), Vector3.new(10.8, 0.24, 5.0), C.HousingTop, nil, solid({ Name = "Bench" }))
	Geo.wedge(model, CFrame.new(0, deck - 0.12, front - 0.225), Vector3.new(10.8, 0.24, 0.45), C.HousingTop, nil, solid())
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
	Geo.block(model, CFrame.new(bx, deck + 0.08, bz), Vector3.new(bw - 0.5, 0.16, bd - 0.5), C.HousingDark, nil, tiny())
	local bodyTop = deck + 0.96
	Geo.block(model, CFrame.new(bx, bodyTop - 0.4, bz), Vector3.new(bw, 0.8, bd), C.Copper, nil, solid({ Name = "Tub" }))
	for _, side in { -1, 1 } do
		Geo.block(
			model,
			CFrame.new(bx, bodyTop + 0.05, bz + side * (bd / 2 + 0.04 - lip / 2)),
			Vector3.new(bw + 0.08, 0.3, lip),
			C.HousingLight,
			nil,
			solid()
		)
		Geo.block(
			model,
			CFrame.new(bx + side * (bw / 2 + 0.04 - lip / 2), bodyTop + 0.05, bz),
			Vector3.new(lip, 0.3, bd + 0.08 - 2 * lip),
			C.HousingLight,
			nil,
			solid()
		)
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
	local riserTop = pipeY - r
	cyl(model, Vector3.new(px, (0.3 + riserTop) / 2, bz), "Y", riserTop - 0.3, pd, C.Copper, nil, solid())
	bend(model, Vector3.new(px, pipeY, bz), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), pd, r, C.Copper)
	local runFrom = px + r
	cyl(model, Vector3.new((runFrom + outX) / 2, pipeY, bz), "X", outX - runFrom, pd, C.Copper, nil, prop())
	local valveX = (runFrom + outX) / 2 - 0.05
	cyl(model, Vector3.new(valveX, pipeY, bz), "X", 0.42, pd * 1.5, C.HousingLight, nil, prop())
	wheel(model, Vector3.new(valveX, pipeY, bz - 0.72), "Z", 1.0, Vector3.new(valveX, pipeY, bz - 0.45))
	flange(model, Vector3.new(outX + 0.07, pipeY, bz), "X", pd, 2, 1)
	water(base, Vector3.new(outX + 0.2, pipeY - 0.04, bz), Vector3.new(1, 0, 0), Vector3.new(outX + 0.55, poolTop, bz))

	-- tool board at the back (light on both sides): chisel, hammer, brush
	local boardZ = 2.85
	panelBack(Geo.block(model, CFrame.new(-0.6, top + 1.6, boardZ), Vector3.new(3.6, 2.6, 0.25), C.HousingLight, nil, solid()))
	local toolZ = boardZ - 0.2
	Geo.block(model, CFrame.new(-1.9, top + 1.75, toolZ), Vector3.new(0.24, 1.6, 0.16), C.Housing, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 1.6, toolZ), Vector3.new(0.22, 1.6, 0.2), C.Wood, nil, tiny())
	Geo.block(model, CFrame.new(-0.7, top + 2.45, toolZ), Vector3.new(0.95, 0.42, 0.42), C.HousingDark, nil, tiny())
	Geo.block(model, CFrame.new(0.5, top + 1.75, toolZ), Vector3.new(0.7, 1.2, 0.3), C.Cloth, nil, tiny())

	-- screen-panel-small: a chunky light panel standing on the top (light
	-- on the back too), dark glass screen with an amber gauge bar (the old
	-- lamp's names, so old lookups still find them)
	panelBack(
		Geo.block(model, CFrame.new(2.6, top + 1.45, 2.8), Vector3.new(1.8, 2.3, 0.3), C.HousingLight, nil, prop({ Name = "LampShade" }))
	)
	Geo.block(
		model,
		CFrame.new(2.6, top + 2.05, 2.63),
		Vector3.new(1.4, 0.85, 0.06),
		C.Screen,
		nil,
		tiny({ Name = "Screen", Reflectance = 0.25 })
	)
	Geo.block(model, CFrame.new(2.45, top + 1.92, 2.59), Vector3.new(0.85, 0.12, 0.03), C.Gauge, NEON, tiny({ Name = "LampBulb" }))

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

	-- output tray on the right: dark floor, iron rims (open to the front)
	Geo.block(model, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), C.HousingDark, nil, solid({ Name = "Tray" }))
	Geo.block(model, CFrame.new(3.6, top + 0.76, -0.4 + 1.22), Vector3.new(2.6, 0.32, 0.16), C.Housing, nil, solid())
	for _, side in { -1, 1 } do
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
	output, an open round hopper on top (intake) with a hatch plate beside
	it, and a large copper chimney in two sections between bolted octagonal
	flanges. 64 parts.
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
		Geo.block(
			model,
			CFrame.new(mouthX, mouthY + i * mouthH / 4, wallZ - 0.32),
			Vector3.new(mouthW + 0.1, 0.2, 0.18),
			C.HousingDark,
			nil,
			tiny()
		)
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
	emitter(chimneyTop, "Smoke", C.Smoke, 2)
	-- open round hopper on top (the intake), a Kenney hatch plate beside it
	roundHopper(model, Vector3.new(0.9, 5.3, 0.45), 2.8, 0.3)
	Geo.block(model, CFrame.new(1.45, 5.375, 2.85), Vector3.new(1.2, 0.15, 0.9), C.HousingLight, nil, tiny())

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	return model
end

--[[
	Blast Furnace (3x3): Kenney machine-connection-pipe on a plinth with
	hazard dashes painted round its edge. A tall iron body with a barred
	molten window (Glow set back in a deep frame with a dark border), a hatch
	and rivet bands painted on its back. On the roof the connection pipe - a
	light octagonal collar, a pipe neck and a wide open octagonal cup (the
	intake) with molten metal glowing in its throat - and the dominant
	vertical, a big copper chimney in two sections split by an octagonal
	flange, under a light cap. A tap: a glass section showing the molten
	metal, an octagonal flange, molten metal pouring from it into an ingot
	mould at the output. Piston-round fuel tanks: the front right one feeds
	the body through a riser with a valve and a two-kink bend, a spare one
	stands at the back left; an orange box-long fills the front left
	corner. 70 parts.
]]
local function blastFurnace(): Model
	local model, base = newModel("BlastFurnace")
	local plinth = Geo.block(model, CFrame.new(0, 0.6, 0.15), Vector3.new(11.6, 0.6, 10.9), C.Housing, nil, solid({ Name = "Plinth" }))
	-- hazard dashes round the plinth's top edge (painted, no parts)
	local pad = surface(plinth, "PlinthFace", Enum.NormalId.Top, 90)
	local edgeX, edgeZ = 0.4 / plinth.Size.X, 0.4 / plinth.Size.Z
	gradientStrip(pad, "HazardL", 0, edgeX, hazardKeys(12))
	gradientStrip(pad, "HazardR", 1 - edgeX, edgeX, hazardKeys(12))
	for _, y in { 0, 1 - edgeZ } do
		local strip = Instance.new("Frame")
		strip.Name = "HazardEnd"
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = Color3.new(1, 1, 1)
		strip.Position = UDim2.fromScale(edgeX, y)
		strip.Size = UDim2.fromScale(1 - 2 * edgeX, edgeZ)
		strip.Parent = pad
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 0
		gradient.Color = ColorSequence.new(hazardKeys(11))
		gradient.Parent = strip
	end

	local bz = 0.8
	local floor = 0.9 -- plinth top
	local bodyH = 7.0
	local body = housing(model, CFrame.new(0, floor, bz), Vector3.new(6.8, bodyH, 6.4), C.Housing, 0.9)
	local front = bz - 3.2
	local roof = floor + bodyH
	-- the back: a painted hatch (light frame, dark panel, rivets, handle)
	-- and two rivet bands
	local back = surface(body, "BackFace", Enum.NormalId.Back, 70)
	paintRect(back, "HatchFrame", 0.31, 0.34, 0.38, 0.46, C.HousingLight)
	paintRect(back, "Hatch", 0.35, 0.38, 0.3, 0.38, C.HousingDark)
	paintRect(back, "HatchHandle", 0.56, 0.55, 0.06, 0.05, C.Hazard)
	for _, x in { 0.33, 0.67 } do
		for _, y in { 0.36, 0.78 } do
			paintRect(back, "Rivet", x - 0.012, y - 0.014, 0.024, 0.028, C.Brass, true)
		end
	end
	for _, y in { 0.14, 0.86 } do
		for i = 0, 8 do
			paintRect(back, "Rivet", 0.07 + i * 0.107, y, 0.024, 0.028, C.Brass, true)
		end
	end

	-- molten window: deep light frame, dark recess, a smaller glow set back
	-- inside a dark border, two thick grate bars
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
	sign(model, CFrame.new(0, 6.75, front - 0.08), "BLAST FURNACE", 3.9)

	-- the connection pipe on the roof (the intake): a light octagonal
	-- collar, a pipe neck, a wide open octagonal cup with molten metal
	-- glowing in its throat
	local stack = Vector3.new(0.3, roof, 0.2)
	local collarH, neckH, cupH, cupW = 0.5, 0.9, 1.6, 3.8
	octagon(model, CFrame.new(stack + Vector3.new(0, collarH / 2, 0)) * UPRIGHT, 4.2, collarH, C.HousingLight, solid())
	cyl(model, stack + Vector3.new(0, collarH + neckH / 2, 0), "Y", neckH, 2.9, C.Housing, nil, solid())
	local cupY = collarH + neckH
	octCup(model, stack + Vector3.new(0, cupY, 0), cupW, 0.42, cupH, C.Housing)
	cyl(model, stack + Vector3.new(0, cupY + 0.7, 0), "Y", 0.12, (cupW - 0.84) * 1.08, C.Molten, NEON, tiny({ Name = "Molten" }))

	-- the chimney: a big copper pipe out of the roof behind the cup, split
	-- by an octagonal flange, a light cap, a dark mouth
	local cx, cz, cd, chimneyTo = -1.75, 3.15, 1.5, 14.0
	cyl(model, Vector3.new(cx, (roof + chimneyTo) / 2, cz), "Y", chimneyTo - roof, cd, C.Copper, nil, solid())
	flange(model, Vector3.new(cx, 11.4, cz), "Y", cd, 0)
	cyl(model, Vector3.new(cx, chimneyTo, cz), "Y", 0.4, cd + 0.45, C.HousingLight, nil, prop())
	local chimneyTop = cyl(model, Vector3.new(cx, chimneyTo + 0.23, cz), "Y", 0.06, cd - 0.2, C.Ember, nil, tiny({ Name = "ChimneyTop" }))
	emitter(chimneyTop, "Smoke", C.Smoke, 5)

	-- tap: a big glass section with molten metal out of the wall, an
	-- octagonal flange, the metal pouring from its mouth into an ingot mould
	-- at the output
	local out = output(base, "BlastFurnace")
	local tapY, glassD = 2.55, 1.1
	local glassFrom, glassTo = front + 0.05, front - 1.25
	cyl(
		model,
		Vector3.new(out.X, tapY, (glassFrom + glassTo) / 2),
		"Z",
		glassFrom - glassTo,
		glassD,
		C.Glass,
		GLASS,
		tiny({ Transparency = 0.5 })
	)
	cyl(
		model,
		Vector3.new(out.X, tapY, (glassFrom + glassTo) / 2),
		"Z",
		glassFrom - glassTo + 0.02,
		0.5,
		C.Molten,
		NEON,
		tiny({ Name = "Molten" })
	)
	local lipZ = glassTo - 0.26
	flange(model, Vector3.new(out.X, tapY, glassTo - 0.13), "Z", glassD, 0)
	local mouldZ, mouldTop = lipZ - 0.55, floor + 0.17
	pipeBetween(
		model,
		Vector3.new(out.X, tapY - 0.12, lipZ + 0.05),
		Vector3.new(out.X, mouldTop, mouldZ),
		0.3,
		C.Molten,
		NEON,
		tiny({ Name = "Molten" })
	)
	Geo.block(model, CFrame.new(out.X, floor + 0.08, mouldZ), Vector3.new(1.6, 0.16, 1.1), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(out.X, mouldTop, mouldZ), Vector3.new(1.2, 0.04, 0.7), C.Glow, NEON, tiny({ Name = "Molten" }))

	-- fuel tanks: the front right one feeds the body through a riser with a
	-- valve and a two-kink bend into its side, a spare one stands at the
	-- back left; an orange box-long in the front left corner
	local side, tx, feedD, entry = 3.4, 4.65, 0.8, 6.0
	local feedR = tx - side
	local capTop = tank(model, Vector3.new(tx, floor, -1.2), 1.9, 2.7)
	tank(model, Vector3.new(-tx, floor, 2.4), 1.9, 2.7)
	local riserTop = entry - feedR
	cyl(model, Vector3.new(tx, (capTop + riserTop) / 2, -1.2), "Y", riserTop - capTop, feedD, C.Copper, nil, prop())
	valve(model, Vector3.new(tx, capTop + 0.55, -1.2), "Y", feedD, Vector3.new(0, 0, -1))
	bend(model, Vector3.new(tx, entry, -1.2), Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0), feedD, feedR, C.Copper, 1)
	Geo.block(model, CFrame.new(-4.45, floor + 0.45, -3.85), Vector3.new(1.9, 0.9, 1.0), C.Copper, nil, solid({ Name = "Box" }))

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6 * 1.45))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5 * 1.45, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * 1.45, 9 * 1.45, 6 * 1.45))
	return model
end

--[[
	Crusher (2x2): Kenney machine-window housing (a window with a cog behind
	the glass and a glint on it) with a high square hopper, the intake,
	holding two dark rollers with light steel teeth standing proud, low in
	its dark throat; a big cog-a and a smaller cog-c meshing on each side of
	the housing (Cog1 / Cog2, they turn with the rollers), an output slot
	with a short chute above the base trim, hazard chevrons, and a
	piston-square drive mounted on the back (its rod showing, the cap
	reaching into the housing). 69 parts.
]]
local function crusher(): Model
	local model, base = newModel("Crusher")
	local bz = 0.35
	local body = housing(model, CFrame.new(0, 0.3, bz), Vector3.new(6.2, 4.0, 5.0), C.Housing, 0.6)
	-- the back: a painted service hatch beside the piston and a rivet band
	local back = surface(body, "BackFace", Enum.NormalId.Back, 60)
	paintRect(back, "HatchFrame", 0.56, 0.3, 0.32, 0.46, C.HousingLight)
	paintRect(back, "Hatch", 0.59, 0.34, 0.26, 0.38, C.HousingDark)
	paintRect(back, "HatchHandle", 0.61, 0.5, 0.05, 0.06, C.Hazard)
	for i = 0, 7 do
		paintRect(back, "Rivet", 0.06 + i * 0.125, 0.12, 0.03, 0.044, C.Brass, true)
	end
	local front = bz - 2.5
	-- window (front left): a dark recess with a brass cog inside, the glass
	-- out at the frame's face with one diagonal glint
	portal(model, CFrame.new(-1.4, 1.5, front), 1.8, 1.4, 0.35, 0.4, true)
	cyl(model, Vector3.new(-1.75, 2.05, front - 0.13), "Z", 0.08, 1.2, C.Brass, nil, tiny())
	Geo.block(model, CFrame.new(-1.4, 2.2, front - 0.28), Vector3.new(1.8, 1.4, 0.04), C.Glass, GLASS, tiny({ Transparency = 0.6 }))
	Geo.block(
		model,
		CFrame.new(-1.05, 2.35, front - 0.31) * CFrame.Angles(0, 0, math.rad(-40)),
		Vector3.new(0.13, 1.1, 0.02),
		rgb(236, 248, 255),
		nil,
		tiny({ Transparency = 0.25 })
	)
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
	-- dark drums with four light steel teeth each (two bars) standing well
	-- proud, and brass cog discs on their ends
	squareHopper(model, CFrame.new(0, 4.3, bz), 3.6, 5.8, 1.1, 1.25, 0.4)
	local rollerY, rollerD = 5.8, 1.5
	for i, dz in { -0.95, 0.95 } do
		local c = Vector3.new(0, rollerY, bz + dz)
		cyl(model, c, "X", 4.9, rollerD, C.HousingDark, nil, solid({ Name = "Roller" .. i }))
		for k = 0, 1 do
			Geo.block(
				model,
				CFrame.new(c) * CFrame.Angles(k * math.pi / 2 + i * math.pi / 4, 0, 0),
				Vector3.new(4.3, rollerD + 0.7, 0.2),
				C.HousingLight,
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
		cog(model, Vector3.new(s * cogX, smallY, smallZ), COG_SMALL, 0.36, 3, s, 0, "Cog2")
	end
	sign(model, CFrame.new(0, 6.42, bz - 2.98), "CRUSHER", 3.4)
	-- piston-square drive mounted on the back wall (inside the footprint):
	-- body, light band, the piston rod showing (extended), and the wide cap
	-- whose back reaches into the housing
	local px, pz = -1.4, 3.15
	Geo.block(model, CFrame.new(px, 0.875, pz), Vector3.new(2.0, 1.15, 1.4), C.Housing, nil, solid())
	Geo.block(model, CFrame.new(px, 1.56, pz), Vector3.new(2.12, 0.22, 1.52), C.HousingLight, nil, prop())
	cyl(model, Vector3.new(px, 1.86, pz), "Y", 0.4, 0.62, C.Brass, nil, prop())
	Geo.block(model, CFrame.new(px, 2.3, pz - 0.1), Vector3.new(2.6, 0.5, 1.8), C.HousingLight, nil, prop())

	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return model
end

-- Anvil (retired): chunky anvil on a machine-bed style pedestal - a foot, a
-- waist flaring up into the face (two wedges), the face with a pointed horn
-- at one end and a lower heel step with a dark hardy hole at the other -
-- quench bucket, hammer. AnvilPoint / IngotSlots unchanged. 20 parts.
local function anvil(): Model
	local model, base = newModel("Anvil")
	housing(model, CFrame.new(0, 0.3, 0.3), Vector3.new(3.0, 2.2, 2.6), C.Housing, 0.4, { Name = "Stump" })
	Geo.block(model, CFrame.new(0, 2.75, 0.3), Vector3.new(2.6, 0.5, 2.0), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(0, 3.48, 0.3), Vector3.new(1.4, 0.95, 1.3), C.HousingDark, nil, solid())
	Geo.block(model, CFrame.new(0, 4.35, 0.3), Vector3.new(3.6, 0.8, 1.8), C.HousingLight, nil, solid({ Name = "AnvilFace" }))
	-- the waist flares up into the face: an upside-down wedge on each side
	for _, side in { -1, 1 } do
		Geo.wedge(
			model,
			CFrame.new(side * 1.05, 3.525, 0.3) * CFrame.Angles(0, -side * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
			Vector3.new(1.3, 0.85, 0.7),
			C.HousingDark,
			nil,
			solid()
		)
	end
	-- heel step at the back end, a dark hardy hole in it
	Geo.block(model, CFrame.new(2.15, 4.2, 0.3), Vector3.new(0.7, 0.5, 1.5), C.HousingLight, nil, solid())
	Geo.block(model, CFrame.new(2.15, 4.46, 0.3), Vector3.new(0.34, 0.03, 0.34), C.Recess, nil, tiny())
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
	Cleaning Plant (AutoCleaner, 2x2): a Kenney scanner-high arch (name plate on top, gold
	letters on both faces) over a short striped roller conveyor
	(conveyor-bars-stripe-high: grey rollers named BedRoller between low
	light rails with painted brass axle caps) with a shallow WaterPool tray
	under the rollers at the shower. Two robot-arm-b arms (chunky segments,
	an orange ball joint at the elbow) slant forward out of the arch and hold
	a teal brush (Drum, bristle rings DrumRib) that rests on the ore's top
	just behind the shower. A copper water riser comes up out of the plot
	(floor plate, a valve), bends (ball joints) into a spray bar with an
	octagonal end flange and a shower head with a dark nozzle face that sprays onto the ore
	(WaterOut -> WaterIn). An open round hopper at the back, a steam Vent, a
	warning-traffic stack light and a short output chute. 69 parts.
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
	-- the shower's catch tray: water under the rollers (they dip into it)
	local tx, tz = -2.75, -1.85
	Geo.block(
		model,
		CFrame.new(cx, 1.56, tz),
		Vector3.new(2.98, 0.1, 2.5),
		MachineBuilder.Water.Pool,
		nil,
		tiny({ Name = "WaterPool", Transparency = MachineBuilder.Water.PoolTransparency, Reflectance = 0.1 })
	)
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
	sign(model, CFrame.new(cx, 6.16, az), "CLEANING PLANT", 3.9, true)
	-- the brush: a dark teal core with three bristle rings, resting on the
	-- ore just behind the shower
	local drumC = Vector3.new(cx, 3.8, -1.0)
	cyl(model, drumC, "X", 2.4, 0.8, C.Bristle, nil, prop({ Name = "Drum" }))
	for _, dx in { -0.78, 0, 0.78 } do
		cyl(model, drumC + Vector3.new(dx, 0, 0), "X", 0.4, 1.15, C.BristleTip, nil, tiny({ Name = "DrumRib" }))
	end
	-- robot-arm-b arms out of the arch beam, slanting forward: a chunky
	-- upper segment, an orange ball joint at the elbow, a lighter lower
	-- segment down to the brush axle
	for _, s in { -1, 1 } do
		local ax = cx + s * 1.36
		local shoulder = Vector3.new(ax, 5.05, az + 0.05)
		local elbow = Vector3.new(ax, 4.45, -0.35)
		local wrist = Vector3.new(ax, drumC.Y, drumC.Z)
		barBetween(model, shoulder, elbow, 0.5, 0.5, C.Housing, prop())
		ball(model, elbow, 0.64, C.Hazard, tiny({ Name = "ArmJoint" }))
		barBetween(model, elbow, wrist + (wrist - elbow).Unit * 0.2, 0.44, 0.44, C.HousingLight)
	end
	-- water: a copper riser out of the plot (floor plate, valve), a two-kink
	-- bend into the spray bar (octagonal end flange), a shower head with a
	-- dark nozzle face over the bed
	local barY, barD = 4.7, 0.6
	local barR = barD * 0.85
	Geo.block(model, CFrame.new(tx, 0.38, tz), Vector3.new(1.0, 0.16, 1.0), C.HousingLight, nil, prop())
	local riserTop = barY - barR
	cyl(model, Vector3.new(tx, (0.3 + riserTop) / 2, tz), "Y", riserTop - 0.3, barD, C.Copper, nil, prop())
	valve(model, Vector3.new(tx, 2.4, tz), "Y", barD, Vector3.new(0, 0, -1))
	bend(model, Vector3.new(tx, barY, tz), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), barD, barR, C.Copper)
	local barFrom, barEnd = tx + barR, cx + 1.0
	cyl(model, Vector3.new((barFrom + barEnd) / 2, barY, tz), "X", barEnd - barFrom, barD, C.Copper, nil, prop())
	flange(model, Vector3.new(barEnd + 0.06, barY, tz), "X", barD, 0)
	Geo.block(model, CFrame.new(cx, barY - 0.36, tz), Vector3.new(1.3, 0.2, 0.5), C.HousingLight, nil, tiny({ Name = "ShowerHead" }))
	Geo.block(model, CFrame.new(cx, barY - 0.48, tz), Vector3.new(1.1, 0.04, 0.36), C.Recess, nil, tiny())
	water(base, Vector3.new(cx, barY - 0.5, tz), Vector3.new(0, -1, 0), Vector3.new(cx, 2.3, tz), true)
	-- open round hopper at the back on a bridge over the rails
	Geo.block(model, CFrame.new(cx, 2.6, 2.45), Vector3.new(3.7, 0.35, 1.15), C.HousingLight, nil, solid())
	roundHopper(model, Vector3.new(cx, 2.775, 2.45), 2.6, 0, 1)
	-- exhaust vent: a short white steam plume (more while working)
	cyl(model, Vector3.new(3.2, 2.25, 3.1), "Y", 3.9, 0.7, C.Housing, nil, prop())
	local vent = cyl(model, Vector3.new(3.2, 4.37, 3.1), "Y", 0.35, 0.95, C.HousingLight, nil, tiny({ Name = "Vent" }))
	emitter(vent, "Steam", rgb(236, 238, 240), 3)
	-- warning-traffic light: green / amber / red on a post under a cap; one
	-- lamp is lit (the client picks it by state), the others keep their hue
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
			color:Lerp(Color3.new(0, 0, 0), if lit then MachineBuilder.Stack.Glow else MachineBuilder.Stack.Dim),
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

--[[
	Iron Box (2x2, step 3): a sturdy gunmetal sorting box (Iron palette, not
	the blue machine housing, so it never reads as a Crusher) on a dark iron
	skirt, with bright steel corner guards and a riveted back. Kenney Factory
	Kit pieces, rebuilt in parts:
	  - an iron hopper-square on the roof (the intake, IRON BOX plate on its
	    front wall);
	  - a glass inspection bay on the front left (steel frame, dark inside,
	    a warm lamp strip InspectLamp under its roof): the client shows the
	    last sorted item standing on its floor (attachment ShowPoint);
	  - a little lit screen on the front right (Screen, Neon; SurfaceGui
	    ScreenGui with Item = the last item, Counter = kept / sent) that the
	    client fills in from the box's attributes;
	  - two output flaps under them, hinged at their top edge: FlapKeep
	    (green, KEEP) over a short slide into a copper-rimmed floor port
	    (PenPort: kept ore goes down to the Ore Pen) and FlapSend (orange,
	    SEND) over the output chute at the output column (everything else
	    rolls out onto your belts). The client swings the flap of each item's
	    way open;
	  - framed belt slots on the left, right and back (belts feed every side
	    but the front).
	The screen, the flaps and the shown item are drawn by MachineFxController
	from the attributes IronBoxService sets (LastKind / LastOre / LastGrade /
	LastRoute / Kept / Sent). 64 parts.
]]

-- The Iron Box's flaps, screen and window, shared with the client animation.
MachineBuilder.IronBox = {
	FlapOpen = math.rad(62), -- how far a flap swings out (about its top edge)
	ScreenIdle = "READY",
	ScreenText = C.ScreenText, -- the screen's text colour...
	RarityTint = 0.3, -- ...tinted this much toward a cleaned ore's rarity colour
	Window = 1.3, -- the shown item is scaled to fit a cube this big
}

local function flapLabel(flap: Part, text: string, color: Color3)
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

local function ironBox(): Model
	local model, base = newModel("IronBox")
	local bz, w, h, d = 0.5, 6.4, 3.9, 5.4
	local body = housing(model, CFrame.new(0, 0.3, bz), Vector3.new(w, h, d), C.Iron, 0.5, { Skirt = true, Top = C.IronTop })
	local back = surface(body, "BackFace", Enum.NormalId.Back, 60)
	for row, y in { 0.14, 0.86 } do
		for i = 0, 7 do
			paintRect(back, "Rivet" .. row, 0.06 + i * 0.125, y, 0.03, 0.044, C.Brass, true)
		end
	end
	local front, rear, side = bz - d / 2, bz + d / 2, w / 2
	local top = 0.3 + h
	local skirtTop = 1.1
	-- steel corner guards from the skirt up to the bevels
	local guardH = top - 0.5 - skirtTop
	for _, x in { -side, side } do
		for _, z in { front, rear } do
			Geo.block(
				model,
				CFrame.new(x, skirtTop + guardH / 2, z),
				Vector3.new(0.42, guardH, 0.42),
				C.Steel,
				nil,
				prop({ Name = "Guard" })
			)
		end
	end
	-- belt slots just over the skirt: left, right, back (portals face -Z, so turn them)
	local slotY = skirtTop + 0.05
	portal(model, CFrame.new(-side, slotY, bz) * CFrame.Angles(0, math.pi / 2, 0), 2.0, 0.9, 0.22, 0.3)
	portal(model, CFrame.new(side, slotY, bz) * CFrame.Angles(0, -math.pi / 2, 0), 2.0, 0.9, 0.22, 0.3)
	portal(model, CFrame.new(0, slotY, rear) * CFrame.Angles(0, math.pi, 0), 2.0, 0.9, 0.22, 0.3)

	-- glass inspection bay (front left): a steel frame standing out of the
	-- wall, dark inside, a warm lamp strip, glass with one glint
	local wx, ww, wy0, wy1, dd, t = -1.45, 2.5, 2.45, 3.95, 1.0, 0.2
	local wh = wy1 - wy0
	local bayZ = front - dd / 2
	Geo.block(model, CFrame.new(wx, (wy0 + wy1) / 2, front - 0.03), Vector3.new(ww, wh, 0.06), C.Recess, nil, tiny({ Name = "BayBack" }))
	Geo.block(model, CFrame.new(wx, wy0 - t / 2, bayZ), Vector3.new(ww + 2 * t, t, dd), C.Steel, nil, solid({ Name = "BayFloor" }))
	Geo.block(model, CFrame.new(wx, wy1 + t / 2, bayZ), Vector3.new(ww + 2 * t, t, dd), C.Steel, nil, solid())
	for _, s in { -1, 1 } do
		Geo.block(model, CFrame.new(wx + s * (ww / 2 + t / 2), (wy0 + wy1) / 2, bayZ), Vector3.new(t, wh, dd), C.Steel, nil, solid())
	end
	Geo.block(
		model,
		CFrame.new(wx, wy1 - 0.05, front - dd * 0.4),
		Vector3.new(ww - 0.4, 0.06, 0.16),
		rgb(255, 232, 196),
		NEON,
		tiny({ Name = "InspectLamp" })
	)
	local glassZ = front - dd + 0.03
	Geo.block(
		model,
		CFrame.new(wx, (wy0 + wy1) / 2, glassZ),
		Vector3.new(ww, wh, 0.05),
		C.Glass,
		GLASS,
		tiny({ Name = "BayGlass", Transparency = 0.6 })
	)
	Geo.block(
		model,
		CFrame.new(wx + 0.55, (wy0 + wy1) / 2 + 0.2, glassZ - 0.03) * CFrame.Angles(0, 0, math.rad(-40)),
		Vector3.new(0.13, 1.2, 0.02),
		rgb(236, 248, 255),
		nil,
		tiny({ Transparency = 0.3 })
	)
	-- where the client stands the last sorted item: on the bay floor
	attach(base, "ShowPoint", CFrame.new(wx, wy0 - 0.15, bayZ + 0.05))

	-- the little lit screen (front right) in a dark frame
	local sx, sw, sy, sh = 1.8, 2.0, 2.5, 1.25
	portal(model, CFrame.new(sx, sy, front), sw, sh, 0.22, 0.3, true, C.HousingDark)
	local screen =
		Geo.block(model, CFrame.new(sx, sy + sh / 2, front - 0.2), Vector3.new(sw, sh, 0.06), C.ScreenLit, NEON, tiny({ Name = "Screen" }))
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
		{ Name = "Item", Text = MachineBuilder.IronBox.ScreenIdle, Y = 0.1, H = 0.5 },
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
		label.TextColor3 = C.ScreenText
		label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
		label.Parent = gui
	end

	-- two output flaps hinged at their top edge: KEEP over a slide into the
	-- floor port (to the Ore Pen), SEND over the chute at the output column
	local out = output(base, "IronBox")
	local flapY0, flapH, flapW = skirtTop + 0.05, 0.8, 1.4
	local flapZ = front - 0.22
	portal(model, CFrame.new(out.X, flapY0, front), flapW, flapH, 0.2, 0.35)
	local send = Geo.block(
		model,
		CFrame.new(out.X, flapY0 + flapH / 2, flapZ),
		Vector3.new(flapW - 0.06, flapH, 0.1),
		C.Hazard,
		nil,
		tiny({ Name = "FlapSend" })
	)
	flapLabel(send, "SEND", C.HazardDark)
	chute(model, Vector3.new(out.X, flapY0 + 0.02, front - 0.35), 1.3, 1.0, 0.15)
	portal(model, CFrame.new(wx, flapY0, front), flapW, flapH, 0.2, 0.35)
	local keep = Geo.block(
		model,
		CFrame.new(wx, flapY0 + flapH / 2, flapZ),
		Vector3.new(flapW - 0.06, flapH, 0.1),
		C.Keep,
		nil,
		tiny({ Name = "FlapKeep" })
	)
	flapLabel(keep, "KEEP", C.ScreenText)
	-- the slide down into a copper-rimmed port in the floor
	local portZ, portD = front - 1.1, 1.4
	local slideTop = Vector3.new(wx, flapY0 + 0.02, front - 0.35)
	local slideEnd = Vector3.new(wx, 0.46, portZ + 0.1)
	barBetween(model, slideTop, slideEnd, 1.2, 0.12, C.HousingDark, prop({ Name = "KeepSlide" }))
	cyl(model, Vector3.new(wx, 0.36, portZ), "Y", 0.12, portD, C.Copper, nil, prop({ Name = "PenPort" }))
	cyl(model, Vector3.new(wx, 0.43, portZ), "Y", 0.04, portD - 0.36, C.Recess, nil, tiny())

	-- iron hopper on the roof with the name plate on its front wall
	local hopperW = 4.6
	local rim = squareHopper(model, CFrame.new(0, top, bz), 3.0, hopperW, 0.9, 0.8, 0.28, C.Iron, C.Steel)
	sign(model, CFrame.new(0, top + rim - 0.4, bz - hopperW / 2 - 0.08), "IRON BOX", 3.4)

	attach(base, "Prompt", CFrame.new(0, 2.6, -3.3))
	local intake = attach(base, "Intake", CFrame.new(0, top + 1.4, bz))
	intake:SetAttribute("IntakeSize", Vector3.new(5.4, 3.2, 5.4))
	return model
end

--[[
	Sorting board (Pen Automation level 1, IronBoxService builds one at the
	pen gate): the Iron Box's keep list shown at your Ore Pen. Two gunmetal
	posts on dark footings with brass caps, a riveted iron frame holding a
	lit teal display (Display, Neon; SurfaceGui BoardGui: Mode line,
	Swatches = the kept ores in their colours, Empty text), a warm lamp
	strip over it, steel rails top and bottom (a hazard band on the lower
	one) and a gold KEEP LIST plate on top. Not a machine (no MachineId);
	Base is an invisible anchor on the ground, Prompt where its "Keep List"
	prompt goes. paintSortingBoard fills the display in. 13 parts.
]]
MachineBuilder.SortingBoard = {
	MaxSwatches = 12, -- 2 rows of 6; more kept ores show "+N" on the last one
	Columns = 6,
}

function MachineBuilder.sortingBoard(): Model
	local model = Instance.new("Model")
	model.Name = "SortingBoard"
	-- the pivot: centred on the ground line, so PivotTo puts the posts on the ground
	local base = Geo.block(model, CFrame.new(), Vector3.new(4.2, 0.2, 0.7), C.Floor, nil, tiny({ Name = "Base", Transparency = 1 }))
	base.Name = "Base"
	model.PrimaryPart = base
	local postX, postTop = 1.85, 4.75
	for _, s in { -1, 1 } do
		Geo.block(model, CFrame.new(s * postX, 0.15, 0), Vector3.new(0.7, 0.3, 0.7), C.HousingDark, nil, prop({ Name = "Footing" }))
		Geo.block(model, CFrame.new(s * postX, postTop / 2, 0), Vector3.new(0.34, postTop, 0.34), C.Iron, nil, solid({ Name = "Post" }))
		ball(model, Vector3.new(s * postX, postTop + 0.12, 0), 0.5, C.Brass)
	end
	-- the iron frame between the posts, the display set into its front
	local y0, y1 = 1.6, 4.35
	local frame = Geo.block(
		model,
		CFrame.new(0, (y0 + y1) / 2, 0.02),
		Vector3.new(postX * 2 - 0.1, y1 - y0, 0.22),
		C.Iron,
		nil,
		solid({ Name = "Frame" })
	)
	local back = surface(frame, "BackFace", Enum.NormalId.Back, 60)
	for row, y in { 0.1, 0.9 } do
		for i = 0, 5 do
			paintRect(back, "Rivet" .. row, 0.08 + i * 0.165, y - 0.03, 0.025, 0.06, C.Brass, true)
		end
	end
	local display = Geo.block(
		model,
		CFrame.new(0, (y0 + y1) / 2 - 0.05, -0.12),
		Vector3.new(postX * 2 - 0.5, y1 - y0 - 0.5, 0.06),
		C.ScreenLit,
		NEON,
		tiny({ Name = "Display" })
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Parent = display
	local mode = Instance.new("TextLabel")
	mode.Name = "Mode"
	mode.Text = "KEEPS RARE+"
	mode.Position = UDim2.fromScale(0.05, 0.05)
	mode.Size = UDim2.fromScale(0.9, 0.26)
	mode.BackgroundTransparency = 1
	mode.TextScaled = true
	mode.TextColor3 = C.ScreenText
	mode.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	mode.Parent = gui
	local swatches = Instance.new("Frame")
	swatches.Name = "Swatches"
	swatches.BackgroundTransparency = 1
	swatches.Position = UDim2.fromScale(0.06, 0.38)
	swatches.Size = UDim2.fromScale(0.88, 0.56)
	swatches.Parent = gui
	local grid = Instance.new("UIGridLayout")
	local columns = MachineBuilder.SortingBoard.Columns
	grid.CellSize = UDim2.new(1 / columns, -6, 0.5, -6)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirectionMaxCells = columns
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = swatches
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.Text = ""
	empty.Position = UDim2.fromScale(0.06, 0.45)
	empty.Size = UDim2.fromScale(0.88, 0.3)
	empty.BackgroundTransparency = 1
	empty.TextScaled = true
	empty.TextColor3 = C.ScreenText
	empty.TextTransparency = 0.25
	empty.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	empty.Visible = false
	empty.Parent = gui
	-- a warm lamp over the display, steel rails top and bottom
	Geo.block(model, CFrame.new(0, y1 - 0.08, -0.19), Vector3.new(postX * 2 - 0.7, 0.06, 0.1), rgb(255, 232, 196), NEON, tiny({ Name = "Lamp" }))
	Geo.block(model, CFrame.new(0, y1 + 0.09, -0.02), Vector3.new(postX * 2 + 0.2, 0.18, 0.36), C.Steel, nil, prop({ Name = "Rail" }))
	local low = Geo.block(model, CFrame.new(0, y0 - 0.09, -0.02), Vector3.new(postX * 2 + 0.2, 0.18, 0.36), C.Steel, nil, prop({ Name = "Rail" }))
	local band = surface(low, "Hazard", Enum.NormalId.Front, 60)
	gradientStrip(band, "Dashes", 0.06, 0.88, hazardKeys(11))
	-- the name plate on top, between the brass caps
	sign(model, CFrame.new(0, y1 + 0.55, -0.02), "KEEP LIST", 2.7, true)
	attach(base, "Prompt", CFrame.new(0, 2.5, -1.0))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return model
end

export type BoardInfo = {
	Mode: string, -- the line on top ("KEEPS RARE+")
	Colors: { Color3 }, -- kept ores' colours, best first
	Empty: string, -- shown when Colors is empty
}

--[[
	Fills a sorting board's display in: the Mode line, one swatch per kept
	ore (at most MaxSwatches; the last one says "+N" when there are more),
	or the Empty text. Reuses its swatches. Pure (only Instances).
]]
function MachineBuilder.paintSortingBoard(model: Model, info: BoardInfo)
	local display = model:FindFirstChild("Display")
	local gui = display and display:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	local mode = gui:FindFirstChild("Mode")
	local swatches = gui:FindFirstChild("Swatches")
	local empty = gui:FindFirstChild("Empty")
	if mode and mode:IsA("TextLabel") then
		mode.Text = info.Mode
	end
	local max = MachineBuilder.SortingBoard.MaxSwatches
	local shown = math.min(#info.Colors, max)
	if swatches then
		for i = 1, max do
			local swatch = swatches:FindFirstChild("Swatch" .. i)
			if i > shown then
				if swatch then
					swatch:Destroy()
				end
				continue
			end
			local frame: Frame
			if swatch and swatch:IsA("Frame") then
				frame = swatch
			else
				frame = Instance.new("Frame")
				frame.Name = "Swatch" .. i
				frame.LayoutOrder = i
				frame.BorderSizePixel = 0
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.3, 0)
				corner.Parent = frame
				local stroke = Instance.new("UIStroke")
				stroke.Color = C.ScreenText
				stroke.Thickness = 2
				stroke.Transparency = 0.4
				stroke.Parent = frame
				frame.Parent = swatches
			end
			frame.BackgroundColor3 = info.Colors[i]
			-- the last swatch stands for itself and every ore after it
			local more = #info.Colors - max + 1
			local existing = frame:FindFirstChild("More")
			if i == max and more > 1 then
				local text: TextLabel
				if existing and existing:IsA("TextLabel") then
					text = existing
				else
					text = Instance.new("TextLabel")
					text.Name = "More"
					text.Size = UDim2.fromScale(1, 1)
					text.BackgroundTransparency = 1
					text.TextScaled = true
					text.TextColor3 = C.ScreenText
					text.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
					text.Parent = frame
				end
				text.Text = `+{more}`
				frame.BackgroundColor3 = C.HousingDark
			elseif existing then
				existing:Destroy()
			end
		end
	end
	if empty and empty:IsA("TextLabel") then
		empty.Text = info.Empty
		empty.Visible = shown == 0
	end
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
	sign(model, CFrame.new(0, 1.75, -1.6), "SELL", 1.3, true)
	attach(base, "Prompt", CFrame.new(0, 2, -1.2))
	local intake = attach(base, "Intake", CFrame.new(0, 3.8, 0))
	intake:SetAttribute("IntakeSize", Vector3.new(3.6, 2.4, 3.6))
	return model
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
	local dashes = hazardKeys(6)
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
	IronBox = ironBox,
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
