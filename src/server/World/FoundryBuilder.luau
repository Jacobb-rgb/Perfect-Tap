--[[
	The Foundry on every base yard (step 3), in the Kenney Factory Kit look
	of the restyled machines (MachineBuilder: forged-iron bodies with lighter
	tops and frames, sparse orange trims, copper pipes, glass pipes with
	molten metal, warning lights). Pure builder: only Instance creation, so
	the Lune tests and the preview tools build it too.

	FoundryService builds it at server start and puts it in place of the
	PlotBuilder placeholder (Plot_<id>.Yard.Foundry); PlotBuilder itself is
	not changed. It stands in BaseLayout.Foundry (plot-local x 5..21,
	z 41..52, at most 16 studs high so the trains' ore arcs clear it), on a
	concrete platform whose front meets the gravel apron PlotBuilder lays:

	  back wall        iron panels with the FOUNDRY sign on top, a warning
	                   beacon at each end (WarnLight: the client blinks them
	                   while the owner forges, attribute Forging)
	  crucible furnace an octagonal furnace (back left as you look at it) with
	                   a glowing mouth, a hopper on top (the Intake box takes
	                   thrown ingots) and a chimney; the copper pipe beside it
	                   rises out of the floor: the ingots from the FOUNDRY
	                   chute arrive through it
	  glass pipe       molten metal runs from the furnace through a glass pipe
	                   into a sloped casting channel
	  blaster mould    the channel pours into a blaster-shaped mould on a table
	  anvil            front right: AnvilPoint (top centre), CamPoint (the
	                   hammer close-up camera, looking at the anvil) and the
	                   Prompt attachment ("Open Foundry", "Put In")
	  blaster rack     a light shadow board on the back wall behind the anvil:
	                   the black Silhouette of the owner's next blaster level
	                   (setRack) and the RackSign plate ("NEXT: LV 3")
	Molten / Glow parts are Neon (the client pulses them). The PrimaryPart
	"Base" (the platform) holds the attachments: AnvilPoint, CamPoint,
	Prompt, HopperIn (where a thrown ingot disappears), HopperOut (where a
	refused one pops out), RackMount.

	receiver(): the FOUNDRY chute's receiver at BaseLayout.FoundryIntake: a
	hood over the end of the sink belt, leaning on the plot's back wall, with
	a glowing throat and a pipe that goes down into the ground. Mouth =
	where a taken item flies in; the PenFull billboard says "Ore Pen full"
	while an item has to wait. Nothing in it collides or blocks raycasts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local BaseLayout = require(Shared.Config.BaseLayout)
local BlasterData = require(Shared.Config.BlasterData)

local FoundryBuilder = {}

type Props = { [string]: any }

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local TAN8 = math.tan(math.pi / 8)

-- the restyled machines' palette (MachineBuilder), plus the platform and the board
local C = {
	Housing = rgb(122, 128, 146),
	HousingTop = rgb(156, 162, 180),
	HousingLight = rgb(184, 188, 200),
	HousingDark = rgb(86, 90, 106),
	Recess = rgb(40, 40, 50),
	Copper = rgb(198, 112, 62),
	Hazard = rgb(255, 150, 36),
	HazardDark = rgb(40, 36, 40),
	Molten = rgb(236, 96, 22),
	Glow = rgb(230, 90, 20),
	Ember = rgb(120, 52, 30),
	Glass = rgb(176, 222, 240),
	Iron = rgb(70, 72, 82),
	Steel = rgb(104, 108, 122),
	AnvilSteel = rgb(178, 184, 198), -- the anvil's face and horn (light, so it reads from the yard at dusk)
	Concrete = rgb(166, 158, 148),
	ConcreteDark = rgb(132, 124, 116),
	Board = rgb(236, 220, 190), -- the shadow board behind the silhouette
	Silhouette = rgb(30, 26, 32),
	Sign = rgb(255, 150, 50),
	Beacon = rgb(255, 150, 20),
	Alert = rgb(255, 92, 70),
}

FoundryBuilder.Colors = C
FoundryBuilder.MaxParts = 110 -- the building with the silhouette (a mobile budget)
FoundryBuilder.ReceiverMaxParts = 10

-- Plot-local frame of the building: the platform's front edge centre.
-- x grows toward the plot's right wall, z toward the sea (as BaseLayout).
local ORIGIN = Vector3.new(BaseLayout.Foundry.Center.X, 0, 41)
local FLOOR = 0.3 -- platform top
local WIDTH, DEPTH = 16, 11

-- Building-frame positions (also used by FoundryService and the tests).
local ANVIL = Vector3.new(-3.8, 0, 3.0)
local ANVIL_TOP = 2.6
local FURNACE = Vector3.new(4.6, 0, 6.6)
local FURNACE_ACROSS = 4.6
local FURNACE_TOP = 5.1
local HOPPER_Y = FURNACE_TOP + 0.8 -- bottom of the hopper (on the lid)
local MOULD = Vector3.new(0.4, 0, 3.0)
local RACK = Vector3.new(-4.4, 4.45, 10.3)
local CAMERA = Vector3.new(-2.1, 6.2, -2.9)

-- Plot-local points FoundryService needs without the model (range checks).
FoundryBuilder.AnvilLocal = ORIGIN + ANVIL + Vector3.new(0, ANVIL_TOP, 0)
FoundryBuilder.PromptLocal = ORIGIN + ANVIL + Vector3.new(0, 3.1, -0.8)
FoundryBuilder.Height = 14.2 -- the chimney's top (the trains' ore arcs need <= BaseLayout.Foundry.Size.Y)

---------------------------------------------------------------- kit

local function merge(props: Props, extra: Props?): Props
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function solid(extra: Props?): Props
	return merge({ CanTouch = false }, extra)
end

local function prop(extra: Props?): Props
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false }, extra)
end

local function tiny(extra: Props?): Props
	return merge({ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }, extra)
end

local function glow(extra: Props?): Props
	return tiny(extra)
end

-- Cylinder along the frame's local axis ("X", "Y" or "Z").
local AXIS = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.pi / 2),
	Z = CFrame.Angles(0, math.pi / 2, 0),
}
local function cyl(
	parent: Instance,
	cf: CFrame,
	axis: "X" | "Y" | "Z",
	length: number,
	d: number,
	color: Color3,
	material: Enum.Material?,
	props: Props?
): Part
	local part = Geo.block(parent, cf * AXIS[axis], Vector3.new(length, d, d), color, material, props or prop())
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Cylinder from a to b (any direction).
local function pipeBetween(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	d: number,
	color: Color3,
	material: Enum.Material?,
	props: Props?
): Part
	local part = Geo.block(
		parent,
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new((b - a).Magnitude, d, d),
		color,
		material,
		props or prop()
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Block from a to b with a w x h cross-section (a -> b must not be vertical).
local function barBetween(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	material: Enum.Material?,
	props: Props?
): Part
	return Geo.block(parent, CFrame.lookAt((a + b) / 2, b), Vector3.new(w, h, (b - a).Magnitude), color, material, props or prop())
end

-- Upright octagonal prism (4 crossed bars), `cf` = its centre.
local function octPrism(parent: Instance, cf: CFrame, across: number, height: number, color: Color3, props: Props?)
	for k = 0, 3 do
		Geo.block(
			parent,
			cf * CFrame.Angles(0, k * math.pi / 4, 0),
			Vector3.new(across, height, across * TAN8 + 0.02),
			color,
			nil,
			props or solid()
		)
	end
end

local function attach(base: BasePart, name: string, world: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = base.CFrame:ToObjectSpace(world)
	a.Parent = base
	return a
end

local function surface(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number, light: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = light
	gui.MaxDistance = 140
	gui.Parent = part
	return gui
end

-- A painted rectangle (x, y, w, h in face scale from the top left).
local function paint(gui: SurfaceGui, name: string, x: number, y: number, w: number, h: number, color: Color3, round: boolean?)
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

-- Hazard dashes across a face (a horizontal gradient, no extra parts).
local function hazard(gui: SurfaceGui, dashes: number)
	local frame = Instance.new("Frame")
	frame.Name = "Hazard"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local keys = {}
	for s = 0, dashes - 1 do
		local color = if s % 2 == 0 then C.Hazard else C.HazardDark
		table.insert(keys, ColorSequenceKeypoint.new(if s == 0 then 0 else s / dashes + 0.002, color))
		table.insert(keys, ColorSequenceKeypoint.new((s + 1) / dashes, color))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keys)
	gradient.Rotation = 0
	gradient.Parent = frame
end

local function text(gui: SurfaceGui, name: string, value: string, color: Color3, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Text = value
	label.TextScaled = true
	label.TextColor3 = color
	label.FontFace = Font.fromEnum(font or Enum.Font.LuckiestGuy)
	label.Parent = gui
	return label
end

---------------------------------------------------------------- the building

local function platform(m: Model, F: CFrame): Part
	local base =
		Geo.block(m, F * CFrame.new(0, FLOOR - 0.25, DEPTH / 2), Vector3.new(WIDTH, 0.5, DEPTH), C.Concrete, nil, solid({ Name = "Base" }))
	base.Name = "Base"
	-- a darker plinth course under it (the yard ground slopes a little)
	Geo.block(m, F * CFrame.new(0, -0.15, DEPTH / 2), Vector3.new(WIDTH + 0.3, 0.3, DEPTH + 0.3), C.ConcreteDark, nil, prop())
	-- hazard dashes along the front edge and painted floor tiles (no parts)
	local top = surface(base, "Floor", Enum.NormalId.Top, 8, 1)
	for i = 1, 3 do
		paint(top, "Seam", i / 4 - 0.002, 0, 0.004, 1, C.ConcreteDark)
	end
	paint(top, "SeamZ", 0, 0.5, 1, 0.006, C.ConcreteDark)
	local edge =
		Geo.block(m, F * CFrame.new(0, FLOOR + 0.01, 0.3), Vector3.new(WIDTH, 0.04, 0.6), C.Hazard, nil, tiny({ Name = "HazardEdge" }))
	hazard(surface(edge, "Dashes", Enum.NormalId.Top, 8, 1), 16)
	return base
end

local function backWall(m: Model, F: CFrame)
	local z = DEPTH - 0.3
	local wall = Geo.block(m, F * CFrame.new(0, FLOOR + 3.4, z), Vector3.new(WIDTH, 6.8, 0.6), C.Housing, nil, solid({ Name = "Wall" }))
	-- Kenney panel insets with brass rivets, painted (no parts)
	local face = surface(wall, "Panels", Enum.NormalId.Front, 10, 1)
	for i = 0, 3 do
		local x = 0.02 + i * 0.245
		paint(face, "Inset", x, 0.08, 0.225, 0.72, C.HousingDark)
		paint(face, "Brace", x, 0.42, 0.225, 0.04, C.HousingTop)
		for _, cx in { x + 0.012, x + 0.2 } do
			paint(face, "Rivet", cx, 0.11, 0.012, 0.03, C.HousingLight, true)
		end
	end
	paint(face, "Trim", 0, 0.88, 1, 0.12, C.Hazard)
	-- a light cap with an orange trim under it
	Geo.block(m, F * CFrame.new(0, FLOOR + 6.95, z), Vector3.new(WIDTH + 0.4, 0.4, 1.0), C.HousingLight, nil, solid())
	-- the FOUNDRY sign standing on the cap (both faces: the yard and the train side)
	local sign = Geo.block(m, F * CFrame.new(0, FLOOR + 7.95, z), Vector3.new(7.6, 1.6, 0.3), C.HousingDark, nil, prop({ Name = "Sign" }))
	for _, normal in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surface(sign, "Gui", normal, 40, 0.2)
		text(gui, "Text", "FOUNDRY", C.Sign)
	end
	-- warning beacons on both ends of the cap (the client blinks WarnLight)
	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.6)
		Geo.block(m, F * CFrame.new(x, FLOOR + 7.35, z), Vector3.new(0.7, 0.4, 0.7), C.HazardDark, nil, tiny())
		local lamp = Geo.ball(m, (F * CFrame.new(x, FLOOR + 7.8, z)).Position, 0.75, C.Beacon, NEON, glow({ Name = "WarnLight" }))
		lamp.Name = "WarnLight"
	end
end

local function furnace(m: Model, F: CFrame)
	local at = F * CFrame.new(FURNACE.X, 0, FURNACE.Z)
	local height = FURNACE_TOP - FLOOR
	octPrism(m, at * CFrame.new(0, FLOOR + height / 2, 0), FURNACE_ACROSS, height, C.Housing)
	-- orange base band, light collar, the lid
	cyl(m, at * CFrame.new(0, FLOOR + 0.3, 0), "Y", 0.6, FURNACE_ACROSS * 1.07, C.Hazard, nil, prop())
	cyl(m, at * CFrame.new(0, FURNACE_TOP + 0.2, 0), "Y", 0.4, FURNACE_ACROSS * 1.08, C.HousingLight, nil, solid())
	cyl(m, at * CFrame.new(0, FURNACE_TOP + 0.55, 0), "Y", 0.3, FURNACE_ACROSS * 0.8, C.HousingTop, nil, solid())
	-- the furnace mouth on the front flat: a light frame, the molten glow, a grate
	local front = at * CFrame.new(0, 0, -FURNACE_ACROSS / 2)
	local w, bottom, top = 2.0, FLOOR + 0.7, FLOOR + 2.7
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			front * CFrame.new(side * (w / 2 + 0.22), (bottom + top + 0.4) / 2, -0.15),
			Vector3.new(0.44, top - bottom + 0.4, 0.5),
			C.HousingLight,
			nil,
			prop()
		)
	end
	Geo.block(m, front * CFrame.new(0, top + 0.2, -0.15), Vector3.new(w + 0.88, 0.4, 0.5), C.HousingLight, nil, prop())
	local mouth = Geo.block(
		m,
		front * CFrame.new(0, (bottom + top) / 2, 0.02),
		Vector3.new(w, top - bottom, 0.1),
		C.Glow,
		NEON,
		glow({ Name = "Glow" })
	)
	mouth.Name = "Glow"
	Geo.block(m, front * CFrame.new(0, (bottom + top) / 2, -0.12), Vector3.new(0.16, top - bottom, 0.14), C.Iron, nil, tiny())
	-- the hopper on the lid (Kenney hopper-square): a tapered neck of four
	-- upside-down wedges, a light collar, an open copper cup with a dark floor
	local hopper = at * CFrame.new(0, HOPPER_Y, 0)
	local bottomW, topW, taperH = 1.5, 3.2, 1.0
	local run = (topW - bottomW) / 2
	for i = 0, 3 do
		Geo.wedge(
			m,
			hopper
				* CFrame.Angles(0, i * math.pi / 2, 0)
				* CFrame.new(0, taperH / 2, -(bottomW / 2 + run / 2))
				* CFrame.Angles(0, 0, math.pi),
			Vector3.new(topW, taperH, run),
			C.HousingTop,
			nil,
			solid()
		)
	end
	Geo.block(m, hopper * CFrame.new(0, taperH + 0.2, 0), Vector3.new(topW + 0.3, 0.4, topW + 0.3), C.HousingLight, nil, solid())
	local cupY, cupH, wall = taperH + 0.4, 0.75, 0.28
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			hopper * CFrame.new(0, cupY + cupH / 2, side * (topW / 2 - wall / 2)),
			Vector3.new(topW, cupH, wall),
			C.Copper,
			nil,
			solid()
		)
		Geo.block(
			m,
			hopper * CFrame.new(side * (topW / 2 - wall / 2), cupY + cupH / 2, 0),
			Vector3.new(wall, cupH, topW - 2 * wall),
			C.Copper,
			nil,
			solid()
		)
	end
	Geo.block(
		m,
		hopper * CFrame.new(0, cupY + 0.05, 0),
		Vector3.new(topW - 2 * wall, 0.1, topW - 2 * wall),
		C.Recess,
		nil,
		solid({ Name = "HopperFloor" })
	)
	-- the chimney behind it: a copper flange and an ember mouth (a little smoke)
	local stack = F * CFrame.new(FURNACE.X + 1.8, 0, FURNACE.Z + 2.4)
	local stackBottom, stackTop = FURNACE_TOP - 0.4, FoundryBuilder.Height - 0.06
	cyl(m, stack * CFrame.new(0, (stackBottom + stackTop) / 2, 0), "Y", stackTop - stackBottom, 1.5, C.Housing, nil, solid())
	cyl(m, stack * CFrame.new(0, stackTop - 2.2, 0), "Y", 0.4, 1.95, C.Copper, nil, prop())
	local ember = cyl(m, stack * CFrame.new(0, stackTop + 0.03, 0), "Y", 0.06, 1.1, C.Ember, NEON, glow({ Name = "Glow" }))
	ember.Name = "Glow"
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(150, 140, 135))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Speed = NumberRange.new(2.5, 4)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Rate = 2
	smoke.LightInfluence = 1
	smoke.Parent = ember
	-- the copper feed pipe from the FOUNDRY chute: up out of the floor, into the furnace's side
	local px, pz = FURNACE.X + FURNACE_ACROSS / 2 + 0.75, FURNACE.Z - 0.9
	local bendY = FURNACE_TOP - 0.9
	cyl(m, F * CFrame.new(px, FLOOR + 0.12, pz), "Y", 0.24, 1.05, C.HousingLight, nil, tiny())
	cyl(m, F * CFrame.new(px, (FLOOR + bendY) / 2, pz), "Y", bendY - FLOOR, 0.7, C.Copper, nil, prop({ Name = "FeedPipe" }))
	local bend = (F * CFrame.new(px, bendY, pz)).Position
	local inlet = (F * CFrame.new(FURNACE.X + FURNACE_ACROSS / 2 - 0.4, bendY, pz)).Position
	Geo.ball(m, bend, 0.7, C.Copper, nil, prop({ Name = "PipeJoint" }))
	pipeBetween(m, bend, inlet, 0.7, C.Copper)
end

-- Glass pipe from the furnace, the casting channel and the blaster mould.
local function casting(m: Model, F: CFrame)
	local pipeY = FLOOR + 3.3
	local fromX = FURNACE.X - FURNACE_ACROSS / 2 + 0.2
	local turnX = MOULD.X + 0.2
	local z = FURNACE.Z
	local a = (F * CFrame.new(fromX, pipeY, z)).Position
	local b = (F * CFrame.new(turnX, pipeY, z)).Position
	local outer = pipeBetween(m, a, b, 0.9, C.Glass, GLASS, prop({ Transparency = 0.45, Name = "GlassPipe" }))
	outer.Name = "GlassPipe"
	local core = pipeBetween(m, a, b, 0.42, C.Molten, NEON, glow({ Name = "Molten" }))
	core.Name = "Molten"
	cyl(m, F * CFrame.new(fromX - 0.15, pipeY, z), "X", 0.25, 1.25, C.HousingLight, nil, tiny())
	Geo.ball(m, b, 0.95, C.HousingLight, nil, prop({ Name = "PipeJoint" }))
	-- down into the channel
	local spoutY = FLOOR + 2.25
	local c = (F * CFrame.new(turnX, spoutY, z)).Position
	local down = pipeBetween(m, b, c, 0.8, C.Glass, GLASS, prop({ Transparency = 0.45 }))
	down.Name = "GlassPipe"
	local downCore = pipeBetween(m, b, c, 0.36, C.Molten, NEON, glow())
	downCore.Name = "Molten"
	-- the sloped casting channel: an open trough with molten metal in it, on a leg
	local mouldTop = FLOOR + 1.45
	local from = (F * CFrame.new(turnX, spoutY - 0.25, z + 0.2)).Position
	local to = (F * CFrame.new(MOULD.X + 0.2, mouldTop + 0.18, MOULD.Z + 0.9)).Position
	local frame = CFrame.lookAt((from + to) / 2, to)
	local length = (to - from).Magnitude
	Geo.block(m, frame * CFrame.new(0, -0.12, 0), Vector3.new(0.9, 0.12, length), C.HousingDark, nil, prop({ Name = "Channel" }))
	for _, side in { -1, 1 } do
		Geo.block(m, frame * CFrame.new(side * 0.4, 0.06, 0), Vector3.new(0.12, 0.34, length), C.HousingLight, nil, tiny())
	end
	local stream = Geo.block(m, frame * CFrame.new(0, -0.04, 0), Vector3.new(0.6, 0.05, length), C.Molten, NEON, glow())
	stream.Name = "Molten"
	cyl(m, F * CFrame.new(turnX, (FLOOR + spoutY - 0.4) / 2, z + 0.2), "Y", spoutY - 0.4 - FLOOR, 0.36, C.Iron, nil, tiny())
	-- the mould table with a blaster-shaped cavity of molten metal
	local table_ = F * CFrame.new(MOULD.X, 0, MOULD.Z)
	Geo.block(
		m,
		table_ * CFrame.new(0, (FLOOR + mouldTop - 0.2) / 2, 0),
		Vector3.new(3.6, mouldTop - 0.2 - FLOOR, 2.4),
		C.Housing,
		nil,
		solid({ Name = "MouldTable" })
	)
	Geo.block(m, table_ * CFrame.new(0, FLOOR + 0.25, 0), Vector3.new(3.7, 0.3, 2.5), C.Hazard, nil, prop())
	Geo.block(m, table_ * CFrame.new(0, mouldTop - 0.1, 0), Vector3.new(3.3, 0.2, 2.1), C.Iron, METAL, solid({ Name = "Mould" }))
	-- the cavity: a blaster lying on its side, seen from above (muzzle block,
	-- barrel, body with a sight, rear block, the grip slanting toward the yard)
	local y = mouldTop + 0.005
	local cavity = {
		{ -1.36, 0.26, 0.24, 0.5, 0 }, -- muzzle
		{ -0.85, 0.26, 0.85, 0.28, 0 }, -- barrel
		{ 0.3, 0.2, 1.5, 0.62, 0 }, -- body
		{ 0.15, 0.58, 0.5, 0.16, 0 }, -- sight
		{ 1.2, 0.2, 0.32, 0.46, 0 }, -- rear block
		{ 0.6, -0.5, 0.42, 0.82, -0.3 }, -- grip
		{ 0.1, -0.26, 0.12, 0.26, 0.3 }, -- trigger
	}
	for _, piece in cavity do
		local part = Geo.block(
			m,
			table_ * CFrame.new(piece[1], y, piece[2]) * CFrame.Angles(0, piece[5], 0),
			Vector3.new(piece[3], 0.03, piece[4]),
			C.Molten,
			NEON,
			glow()
		)
		part.Name = "Molten"
	end
end

local function anvil(m: Model, F: CFrame)
	local at = F * CFrame.new(ANVIL.X, 0, ANVIL.Z)
	-- a stout iron stand with an orange band, the waist, the big light steel
	-- face and horn (they read from the yard next to the mould table)
	local face, faceH = Vector3.new(2.6, 0.6, 1.2), 0.6
	Geo.block(m, at * CFrame.new(0, FLOOR + 0.45, 0), Vector3.new(1.9, 0.9, 1.5), C.HousingDark, nil, solid({ Name = "AnvilBase" }))
	Geo.block(m, at * CFrame.new(0, FLOOR + 0.25, 0), Vector3.new(1.98, 0.3, 1.58), C.Hazard, nil, prop())
	local waistBottom = FLOOR + 0.9
	local waistTop = ANVIL_TOP - faceH
	Geo.block(m, at * CFrame.new(0, (waistBottom + waistTop) / 2, 0), Vector3.new(0.95, waistTop - waistBottom, 0.85), C.Iron, nil, solid())
	local top = Geo.block(m, at * CFrame.new(0, ANVIL_TOP - faceH / 2, 0), face, C.AnvilSteel, nil, solid({ Name = "Anvil" }))
	top.Name = "Anvil"
	-- the horn: a wedge with its flat side on top, tapering to the left (-X)
	Geo.wedge(
		m,
		at * CFrame.new(-face.X / 2 - 0.55, ANVIL_TOP - faceH / 2, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(face.Z, faceH, 1.1),
		C.AnvilSteel,
		nil,
		solid()
	)
end

local function rack(m: Model, F: CFrame)
	local board =
		Geo.block(m, F * CFrame.new(RACK.X, RACK.Y, RACK.Z), Vector3.new(6.2, 3.4, 0.2), C.Board, nil, prop({ Name = "RackBoard" }))
	board.Name = "RackBoard"
	-- a big "?" for the level after the top one (shown by setRack)
	local gui = surface(board, "Mystery", Enum.NormalId.Front, 30, 0.4)
	gui.Enabled = false
	local mark = text(gui, "Mark", "?", C.Silhouette)
	mark.Position = UDim2.fromScale(0.3, 0.05)
	mark.Size = UDim2.fromScale(0.4, 0.9)
	Geo.block(m, F * CFrame.new(RACK.X, RACK.Y + 1.85, RACK.Z - 0.05), Vector3.new(6.6, 0.3, 0.35), C.HousingLight, nil, tiny())
	local plate = Geo.block(
		m,
		F * CFrame.new(RACK.X, RACK.Y - 1.95, RACK.Z - 0.08),
		Vector3.new(6.6, 0.6, 0.4),
		C.HousingDark,
		nil,
		tiny({ Name = "RackSign" })
	)
	plate.Name = "RackSign"
	text(surface(plate, "Gui", Enum.NormalId.Front, 40, 0.3), "Text", "NEXT: LV 2", C.Sign)
end

local function mount(base: BasePart, F: CFrame)
	attach(base, "AnvilPoint", F * CFrame.new(ANVIL.X, ANVIL_TOP, ANVIL.Z))
	local camPos = (F * CFrame.new(CAMERA)).Position
	local look = (F * CFrame.new(ANVIL.X, ANVIL_TOP + 0.35, ANVIL.Z + 0.6)).Position
	attach(base, "CamPoint", CFrame.lookAt(camPos, look))
	attach(base, "Prompt", F * CFrame.new(ANVIL.X, 3.1, ANVIL.Z - 0.8))
	attach(base, "HopperIn", F * CFrame.new(FURNACE.X, HOPPER_Y + 1.7, FURNACE.Z))
	attach(base, "HopperOut", F * CFrame.new(FURNACE.X, HOPPER_Y + 2.6, FURNACE.Z - 2.6))
	attach(base, "RackMount", F * CFrame.new(RACK.X, RACK.Y + 0.1, RACK.Z - 0.12)) -- the board's front face
end

-- The Foundry building of a plot (plotCF = WorldLayout.plotCFrame). Its
-- silhouette shows `nextLevel` (default 2).
function FoundryBuilder.build(plotCF: CFrame, nextLevel: number?): Model
	local m = Instance.new("Model")
	m.Name = "Foundry"
	local F = plotCF * CFrame.new(ORIGIN)
	local base = platform(m, F)
	m.PrimaryPart = base
	backWall(m, F)
	furnace(m, F)
	casting(m, F)
	anvil(m, F)
	rack(m, F)
	mount(base, F)
	-- the hopper's intake box (an invisible IntakeService zone part)
	local intake = Geo.block(
		m,
		F * CFrame.new(FURNACE.X, HOPPER_Y + 2.25, FURNACE.Z),
		Vector3.new(3.8, 2.9, 3.8),
		C.Recess,
		nil,
		tiny({ Name = "Intake", Transparency = 1 })
	)
	intake.Name = "Intake"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	FoundryBuilder.setRack(m, nextLevel or 2)
	return m
end

--[[
	Shows blaster level `level` as a black silhouette on the shadow board (a
	level past BlasterData.MaxLevel: the "?" and COMING SOON). Rebuilds only
	the "Silhouette" model; the parts keep their BlasterBuilder shapes,
	scaled to fit the board.
]]
function FoundryBuilder.setRack(building: Model, level: number)
	local old = building:FindFirstChild("Silhouette")
	if old then
		old:Destroy()
	end
	local base = building.PrimaryPart
	local mountPoint = base and base:FindFirstChild("RackMount")
	local board = building:FindFirstChild("RackBoard")
	local plate = building:FindFirstChild("RackSign")
	local label = plate and plate:FindFirstChild("Text", true)
	local mystery = board and board:FindFirstChild("Mystery")
	local comingSoon = level > BlasterData.MaxLevel
	if label and label:IsA("TextLabel") then
		label.Text = if comingSoon then "COMING SOON" else `NEXT: LV {level}`
	end
	if mystery and mystery:IsA("SurfaceGui") then
		mystery.Enabled = comingSoon
	end
	building:SetAttribute("RackLevel", level)
	if comingSoon or not base or not mountPoint or not mountPoint:IsA("Attachment") then
		return
	end
	local tool = BlasterBuilder.build(math.max(2, level), "")
	local parts: { BasePart } = {}
	local minP = Vector3.new(math.huge, math.huge, math.huge)
	local maxP = -minP
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local half = d.Size / 2
			local cf = d.CFrame
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			local ext = Vector3.new(
				math.abs(r00) * half.X + math.abs(r01) * half.Y + math.abs(r02) * half.Z,
				math.abs(r10) * half.X + math.abs(r11) * half.Y + math.abs(r12) * half.Z,
				math.abs(r20) * half.X + math.abs(r21) * half.Y + math.abs(r22) * half.Z
			)
			local lo, hi = cf.Position - ext, cf.Position + ext
			minP = Vector3.new(math.min(minP.X, lo.X), math.min(minP.Y, lo.Y), math.min(minP.Z, lo.Z))
			maxP = Vector3.new(math.max(maxP.X, hi.X), math.max(maxP.Y, hi.Y), math.max(maxP.Z, hi.Z))
		end
	end
	local extent = maxP - minP
	local scale = math.min(1.5, 4.8 / math.max(extent.Z, 0.1), 2.5 / math.max(extent.Y, 0.1))
	local center = (minP + maxP) / 2
	-- barrel (-Z in the design frame) toward -X, the gun's side toward the yard
	-- (its side rests against the board: the gun's width is the depth here)
	local frame = base.CFrame * mountPoint.CFrame * CFrame.new(0, 0, -extent.X * scale / 2 - 0.02) * CFrame.Angles(0, math.pi / 2, 0)
	local silhouette = Instance.new("Model")
	silhouette.Name = "Silhouette"
	for _, part in parts do
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		local rel = part.CFrame
		part.Size *= scale
		part.CFrame = frame * CFrame.new((rel.Position - center) * scale) * rel.Rotation
		part.Anchored = true
		part.Massless = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Color = C.Silhouette
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0
		part.Parent = silhouette
	end
	tool:Destroy()
	silhouette.Parent = building
end

---------------------------------------------------------------- the chute receiver

-- The FOUNDRY chute's receiver (plot-local BaseLayout.FoundryIntake).
function FoundryBuilder.receiver(plotCF: CFrame): Model
	local zone = BaseLayout.FoundryIntake.Zone
	local m = Instance.new("Model")
	m.Name = "FoundryReceiver"
	local cx = zone.Center.X
	local front = zone.Center.Z - zone.Size.Z / 2 + 0.08
	local wall = zone.Center.Z + 0.4 -- the hood's back plate leans on the plot wall
	local w = zone.Size.X - 0.1
	local hood = Geo.block(m, plotCF * CFrame.new(cx, 1.55, wall - 0.15), Vector3.new(w, 3.1, 0.3), C.Housing, nil, tiny({ Name = "Hood" }))
	hood.Name = "Hood"
	m.PrimaryPart = hood
	local throat =
		Geo.block(m, plotCF * CFrame.new(cx, 1.5, wall - 0.32), Vector3.new(w - 1.1, 1.2, 0.05), C.Glow, NEON, glow({ Name = "Glow" }))
	throat.Name = "Glow"
	-- the roof leans from the wall down over the belt's end
	local roofBack = plotCF * CFrame.new(cx, 3.22, wall)
	local roofFront = plotCF * CFrame.new(cx, 2.5, front)
	barBetween(m, roofFront.Position, roofBack.Position, zone.Size.X, 0.18, C.Copper, nil, tiny({ Name = "Roof" }))
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			plotCF * CFrame.new(cx + side * (zone.Size.X / 2 - 0.13), 1.85, (front + wall - 0.3) / 2),
			Vector3.new(0.25, 1.5, wall - 0.3 - front),
			C.HousingLight,
			nil,
			tiny()
		)
	end
	local lintel = Geo.block(m, plotCF * CFrame.new(cx, 2.25, front + 0.09), Vector3.new(zone.Size.X, 0.3, 0.18), C.Hazard, nil, tiny())
	hazard(surface(lintel, "Dashes", Enum.NormalId.Front, 16, 1), 8)
	-- the pipe the belt's end drops into, going down into the ground
	local pipe = plotCF * CFrame.new(cx, 0, wall - 0.3)
	cyl(m, pipe * CFrame.new(0, 0.1, 0), "Y", 1.4, 1.35, C.Copper, nil, tiny({ Name = "Pipe" }))
	cyl(m, pipe * CFrame.new(0, 0.12, 0), "Y", 0.22, 1.58, C.HousingLight, nil, tiny())
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.CFrame = hood.CFrame:ToObjectSpace(plotCF * CFrame.new(BaseLayout.FoundryIntake.Mouth))
	mouth.Parent = hood
	-- "Ore Pen full" over the hood while an item has to wait (FoundryService)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PenFull"
	billboard.Size = UDim2.fromScale(6, 1.3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, -0.6)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = hood
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundColor3 = rgb(40, 20, 18)
	label.BackgroundTransparency = 0.15
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "Ore Pen full"
	label.TextScaled = true
	label.TextColor3 = C.Alert
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = label
	return m
end

return FoundryBuilder
