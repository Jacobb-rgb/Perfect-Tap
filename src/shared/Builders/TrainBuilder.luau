--[[
	Builds the per-player ore train (design v2, docs/plans/STEP2_PLAN.md) in the
	style of the Kenney Train Kit, rebuilt from Roblox parts (no meshes):

	  locomotive(color, trim?)  chunky steam locomotive after train-locomotive-a/b/c:
	                            grey smokebox with a big door, a raised hub and a lamp
	                            on top, chimney, steam dome, boiler with bands and
	                            handrails, cab with framed windows and a gabled roof,
	                            cow-catcher, red-spoked drive wheels with a rod from
	                            the steam cylinder, small front wheels, trim-colored
	                            buffers. <= 60 parts.
	  wagon(color, loads?)      ore wagon after train-carriage-dirt: a hollow tipping
	                            hopper, the sub-model "Hopper" (steel grey, the lower
	                            band in the body color), on two narrow bogie frames
	                            with outboard wheels, loaded with a mound of faceted
	                            ore rocks in the given colors; an open empty hopper
	                            when nil or {}. <= 20 parts.
	  track(length)             straight track after track-detailed: two chunky rails
	                            on wide sleepers (every ~6 studs), no ballast bed.
	                            3 + 1 per sleeper parts (budget 4 + 1 per sleeper).

	Contract (all three): a Model whose PrimaryPart "Root" (invisible) sits at the
	bottom center, front = -Z, +Y up. Trains stand on the rails when their Root is
	placed RailTop studs above a track's Root. Locomotive and wagon have the
	Attachments "CouplerFront" (on the part "BogieFront") and "CouplerBack" (on
	"BogieBack") at the buffer faces; the next vehicle's CouplerFront goes on the
	previous one's CouplerBack. Every part named "Wheel" is centered on its axle
	with its local X axis along the axle (spin: part.CFrame * CFrame.Angles(a, 0, 0))
	and carries the axle's rolling radius in the attribute "Radius". The locomotive
	has a "Smoke" Attachment at the chimney top (world up = +Y). The wagon's hopper
	tips about the Z axis through the Root attachment "TipPivot" (dumps to +X).
	Model attributes: "Kind" = Locomotive | Wagon | Track, "Length" = distance
	between the two couplers (locomotive and wagon).

	Everything is anchored, CanCollide/CanTouch/CanQuery off (the train is a client
	visual), CastShadow only on the big parts. Pure and deterministic: only
	Instance creation, so Lune tests and previews can build it. Faces that sit on
	top of each other step out by >= 0.06 stud (no z-fighting on phones).
]]

local TrainBuilder = {}

TrainBuilder.Gauge = 4.4 -- rail centers (the wheels sit on x = +-Gauge / 2)
TrainBuilder.RailTop = 1.1 -- rail top above a track's Root = wheel bottoms
TrainBuilder.SleeperSpacing = 6
TrainBuilder.CouplerHeight = 1.85
TrainBuilder.MaxLocomotiveParts = 60
TrainBuilder.MaxWagonParts = 20

local rgb = Color3.fromRGB
local C = {
	Iron = rgb(52, 54, 64), -- frames, wheel centers
	Smokebox = rgb(100, 104, 118), -- smokebox, chimney (Kenney mid grey)
	Door = rgb(140, 144, 160), -- smokebox door
	IronLight = rgb(112, 116, 130), -- cow-catcher
	ChimneyTop = rgb(44, 45, 52), -- the sooty chimney crown (reads as the opening)
	Steel = rgb(172, 178, 192), -- tyres, rods
	Deck = rgb(140, 144, 160), -- running board
	Roof = rgb(128, 132, 150),
	Red = rgb(200, 54, 46), -- wheel spokes, buffer beams (Kenney's red accent)
	Brass = rgb(226, 178, 78),
	Glass = rgb(150, 204, 238),
	Lamp = rgb(255, 184, 96), -- warm, so the bloom stays a small dot
	Interior = rgb(62, 64, 74), -- the floor of an empty hopper
	Hopper = rgb(150, 156, 175), -- Kenney steel grey: hopper flanks and rim
	Frame = rgb(100, 104, 120), -- wagon bogie frames (between the hopper and the wheels)
	WagonWheel = rgb(58, 60, 70),
	Rubble = rgb(120, 112, 104), -- the bed under the ore rocks
	Sleeper = rgb(232, 140, 90), -- Kenney salmon wood
	Rail = rgb(190, 196, 225), -- Kenney lavender steel
}

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local AXLE = CFrame.new() -- along X (sideways): axles
-- a cube standing on a corner: the body diagonal points up, so its top shows three
-- rhombus facets around a peak (a faceted ore chunk)
local VERTEX_UP = CFrame.Angles(math.atan(1 / math.sqrt(2)), 0, math.pi / 4)

type Kind = "Block" | "Wedge" | "Cylinder" | "Ball"

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function part(
	parent: Instance,
	name: string,
	kind: Kind,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if kind == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif kind == "Ball" then
			block.Shape = Enum.PartType.Ball
		end
		p = block
	end
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Block between two corners (model space).
local function span(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?
): BasePart
	local lo = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local hi = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return part(parent, name, "Block", CFrame.new((lo + hi) / 2), hi - lo, color, material, shadow)
end

-- Bar of the given cross-section (width along X, height) from point a to point b.
local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, color: Color3): BasePart
	return part(parent, name, "Block", CFrame.lookAt((a + b) / 2, b), Vector3.new(width, height, (b - a).Magnitude), color)
end

-- Cylinder centered at `pos` whose axis is X rotated by `axis` (ALONG_Y / ALONG_Z / identity).
local function cyl(
	parent: Instance,
	name: string,
	pos: Vector3,
	axis: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?
): BasePart
	return part(parent, name, "Cylinder", CFrame.new(pos) * axis, Vector3.new(length, diameter, diameter), color, material, shadow)
end

--[[
	A wedge running along Z with a full vertical face toward the middle (x = 0)
	and a full horizontal face: `up` = true puts the flat face at the bottom and
	the slope on top (roof), false puts the flat face on top and the slope below
	(hopper flanks). side = 1 for +X, -1 for -X. size = (length, height, width).
]]
local function sideWedge(
	parent: Instance,
	name: string,
	center: Vector3,
	size: Vector3,
	side: number,
	up: boolean,
	color: Color3,
	shadow: boolean?
): BasePart
	local s = if up then 1 else -1
	local cf = CFrame.fromMatrix(center, Vector3.new(0, 0, s * side), Vector3.new(0, s, 0), Vector3.new(-side, 0, 0))
	return part(parent, name, "Wedge", cf, size, color, nil, shadow)
end

local function attach(p: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = p.CFrame:ToObjectSpace(cf)
	a.Parent = p
	return a
end

local function newModel(name: string, kind: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Kind", kind)
	local root = part(model, "Root", "Block", CFrame.new(), Vector3.new(1, 0.05, 1), C.Iron)
	root.Transparency = 1
	model.PrimaryPart = root
	return model, root
end

local function couplers(model: Model, front: BasePart, back: BasePart, frontZ: number, backZ: number)
	attach(front, "CouplerFront", CFrame.new(0, TrainBuilder.CouplerHeight, frontZ))
	attach(back, "CouplerBack", CFrame.new(0, TrainBuilder.CouplerHeight, backZ))
	model:SetAttribute("Length", backZ - frontZ)
end

local function wheelPart(p: BasePart, radius: number)
	p:SetAttribute("Radius", radius)
end

-- Small axle: steel tyres + a dark hub standing 0.12 proud, one drum across both
-- wheels (the frame hides the middle).
local function smallAxle(parent: Instance, z: number, diameter: number, halfSpan: number)
	local r = diameter / 2
	local pos = Vector3.new(0, r, z)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2, diameter, C.Steel), r)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2 + 0.24, diameter * 0.6, C.Iron), r)
end

---------------------------------------------------------------- locomotive

function TrainBuilder.locomotive(color: Color3, trim: Color3?): Model
	local trimColor = trim or C.Brass
	local model, root = newModel("Locomotive", "Locomotive")
	local metal = Enum.Material.Metal

	-- frames (between the wheels), the running board and a trim valance along it
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.6, 0.55, -6.1), Vector3.new(1.6, 2.4, -1.2), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.95, 0.8, -1.2), Vector3.new(1.95, 2.4, 6.4), C.Iron)
	span(model, "Deck", Vector3.new(-2.9, 2.4, -6.15), Vector3.new(2.9, 2.75, 6.35), C.Deck, nil, true)
	span(model, "Valance", Vector3.new(-2.98, 2.15, -6.2), Vector3.new(2.98, 2.46, 6.3), trimColor)

	-- small front wheels and the big red-spoked drive wheels (tyre, iron, spokes
	-- and brass hub each step out by >= 0.07 per side)
	smallAxle(model, -4.6, 1.8, 2.3)
	smallAxle(model, -2.4, 1.8, 2.3)
	for _, z in { 0.5, 3.55 } do
		local d = 2.7
		local r = d / 2
		local pos = Vector3.new(0, r, z)
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.16, d, C.Steel), r)
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.3, d * 0.8, C.Iron), r)
		for k = 0, 2 do
			local spoke = part(
				model,
				"Wheel",
				"Block",
				CFrame.new(pos) * CFrame.Angles(k * math.pi / 3, 0, 0),
				Vector3.new(5.45, 0.3, d * 0.78),
				C.Red
			)
			wheelPart(spoke, r)
		end
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.6, 0.8, C.Brass, metal), r)
	end
	-- steam cylinders outboard between the front axles, rods from the cylinder end
	-- across both brass hubs
	for _, side in { -1, 1 } do
		cyl(model, "SteamCylinder", Vector3.new(side * 2.85, 1.95, -3.5), ALONG_Z, 1.9, 1.0, color)
		bar(model, "Rod", Vector3.new(side * 2.89, 1.7, -2.55), Vector3.new(side * 2.89, 1.3, 3.75), 0.18, 0.28, C.Steel)
	end

	-- front: buffer beam, trim-colored buffers and a V cow-catcher
	span(model, "BufferBeam", Vector3.new(-2.9, 1.3, -6.5), Vector3.new(2.9, 2.4, -6.1), C.Red)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 1.9, TrainBuilder.CouplerHeight, -6.75), ALONG_Z, 0.5, 0.8, trimColor, metal)
	end
	local theta, width, depth, tipZ = math.rad(18), 3.1, 1.2, -7.45
	for _, side in { -1, 1 } do
		local x = Vector3.new(math.cos(theta), 0, side * math.sin(theta))
		local zAxis = Vector3.new(-side * math.sin(theta), 0, math.cos(theta))
		local center = Vector3.new(
			side * (width / 2 * math.cos(theta) - depth / 2 * math.sin(theta)),
			0.8,
			tipZ + width / 2 * math.sin(theta) + depth / 2 * math.cos(theta)
		)
		part(
			model,
			"CowCatcher",
			"Wedge",
			CFrame.fromMatrix(center, x, Vector3.new(0, 1, 0), zAxis),
			Vector3.new(width, 1.2, depth),
			C.IronLight
		)
	end

	-- boiler: grey smokebox with a big door + raised hub and the lamp on top, the
	-- barrel with bands and handrails, chimney with a sooty crown, steam dome
	local boilerY = 4.45
	cyl(model, "Smokebox", Vector3.new(0, boilerY, -4.6), ALONG_Z, 2.7, 3.75, C.Smokebox, nil, true)
	cyl(model, "SmokeboxDoor", Vector3.new(0, boilerY, -6.05), ALONG_Z, 0.4, 3.1, C.Door)
	cyl(model, "DoorHub", Vector3.new(0, boilerY, -6.33), ALONG_Z, 0.36, 1.0, trimColor, metal)
	cyl(model, "Lamp", Vector3.new(0, 6.5, -5.7), ALONG_Z, 1.0, 0.95, trimColor, metal)
	cyl(model, "LampGlass", Vector3.new(0, 6.5, -6.24), ALONG_Z, 0.08, 0.5, C.Lamp, Enum.Material.Neon)
	cyl(model, "Boiler", Vector3.new(0, boilerY, -1.85), ALONG_Z, 3.0, 3.5, color, nil, true)
	for _, z in { -2.95, -1.0 } do
		cyl(model, "Band", Vector3.new(0, boilerY, z), ALONG_Z, 0.28, 3.64, trimColor, metal)
	end
	for _, side in { -1, 1 } do
		-- touches the barrel (r 1.75) and runs just outside the bands (r 1.82)
		span(model, "Handrail", Vector3.new(side * 1.64, 4.87, -3.25), Vector3.new(side * 1.8, 5.03, -0.6), trimColor, metal)
	end
	cyl(model, "Chimney", Vector3.new(0, 6.6, -4.4), ALONG_Y, 1.5, 1.25, C.Smokebox, nil, true)
	local cap = cyl(model, "ChimneyCap", Vector3.new(0, 7.675, -4.4), ALONG_Y, 0.65, 1.85, C.ChimneyTop)
	attach(cap, "Smoke", CFrame.new(0, 8.05, -4.4))
	cyl(model, "Dome", Vector3.new(0, 6.3, -2.0), ALONG_Y, 0.9, 1.35, color)
	part(model, "DomeCap", "Ball", CFrame.new(0, 6.75, -2.0), Vector3.new(1.35, 1.35, 1.35), trimColor, metal)

	-- cab: body with a trim band, framed windows, a light gabled roof with a thin
	-- eave that overhangs forward over the boiler
	span(model, "Cab", Vector3.new(-2.6, 2.75, -0.6), Vector3.new(2.6, 6.6, 6.2), color, nil, true)
	span(model, "CabBand", Vector3.new(-2.72, 2.72, -0.72), Vector3.new(2.72, 3.55, 6.32), trimColor)
	for _, side in { -1, 1 } do
		span(model, "WindowFrame", Vector3.new(side * 2.55, 4.05, 0.1), Vector3.new(side * 2.68, 6.15, 4.85), darker(color, 0.4))
		span(model, "Window", Vector3.new(side * 2.56, 4.3, 0.35), Vector3.new(side * 2.74, 5.9, 2.65), C.Glass)
		span(model, "Window", Vector3.new(side * 2.56, 4.3, 2.9), Vector3.new(side * 2.74, 5.9, 4.6), C.Glass)
	end
	span(model, "Window", Vector3.new(-1.4, 4.3, 6.1), Vector3.new(1.4, 5.9, 6.3), C.Glass)
	local roofZ0, roofZ1 = -1.25, 6.9 -- the front stops just behind the dome
	local roofLen = roofZ1 - roofZ0
	local roofMid = (roofZ0 + roofZ1) / 2
	span(model, "Roof", Vector3.new(-3.25, 6.6, roofZ0), Vector3.new(3.25, 6.95, roofZ1), C.Roof, nil, true)
	span(model, "Roof", Vector3.new(-1.55, 6.95, roofZ0), Vector3.new(1.55, 7.6, roofZ1), C.Roof, nil, true)
	for _, side in { -1, 1 } do
		sideWedge(model, "Roof", Vector3.new(side * 2.3, 7.275, roofMid), Vector3.new(roofLen, 0.65, 1.5), side, true, C.Roof, true)
	end

	-- back: buffer beam and buffers
	span(model, "BufferBeam", Vector3.new(-2.75, 1.3, 6.3), Vector3.new(2.75, 2.4, 6.65), C.Red)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 1.9, TrainBuilder.CouplerHeight, 6.9), ALONG_Z, 0.5, 0.8, trimColor, metal)
	end

	couplers(model, bogieFront, bogieBack, -7.0, 7.15)
	model.PrimaryPart = root
	return model
end

---------------------------------------------------------------- wagon

--[[
	The ore load, a mound like the Kenney dirt load: a rubble bed just under the
	rim, three big rounded rocks along the middle (balls sunk into the bed, so only
	a low dome shows) and two smaller faceted chunks (cubes standing on a corner)
	in the gaps between them. Rise = how far each rock's top stands above the bed.
	All stay inside the hopper opening (the chunks only dip into the rim).
]]
type Lump = { Pos: Vector3, Size: number, Rise: number, Yaw: number, Round: boolean }
local LUMPS: { Lump } = {
	{ Pos = Vector3.new(0.08, 0, -3.45), Size = 4.2, Rise = 1.3, Yaw = 0, Round = true },
	{ Pos = Vector3.new(-0.05, 0, 0), Size = 4.3, Rise = 1.45, Yaw = 0, Round = true },
	{ Pos = Vector3.new(0.06, 0, 3.45), Size = 4.1, Rise = 1.25, Yaw = 0, Round = true },
	{ Pos = Vector3.new(1.05, 0, -1.75), Size = 1.9, Rise = 1.55, Yaw = 0.5, Round = false },
	{ Pos = Vector3.new(-1.0, 0, 1.75), Size = 1.85, Rise = 1.5, Yaw = 1.4, Round = false },
}

-- hopper cross-section (model space)
local INNER = 2.05 -- inner half width: the flanks' vertical inner faces
local FLANK_TOP = 2.65 -- outer edge of the flanks at the rim
local RIM = 2.85 -- outer half width of the rim (~85 % of the locomotive)
local FLOOR, BRIM, TOP = 3.6, 6.0, 6.6 -- hopper floor, flank tops, rim top
local INNER_Z, END_Z = 5.3, 5.9 -- inner end walls, outer ends of the rim

function TrainBuilder.wagon(color: Color3, loadColors: { Color3 }?): Model
	local model, root = newModel("OreWagon", "Wagon")

	-- running gear: two narrow, deep bogie frames hide the middle of each axle
	-- drum, so only its ends show, as separate wheels outboard of the frame
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.7, 0.3, -6.0), Vector3.new(1.7, 2.45, 0), C.Frame)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.7, 0.3, 0), Vector3.new(1.7, 2.45, 6.0), C.Frame)
	for _, z in { -4.3, -2.15, 2.15, 4.3 } do
		wheelPart(cyl(model, "Wheel", Vector3.new(0, 0.85, z), AXLE, 4.6, 1.7, C.WagonWheel), 0.85)
	end

	-- the hollow tipping hopper: a lower band in the body color (it is the floor),
	-- sloped steel flanks whose inner faces are the side walls, a thick rim whose
	-- end pieces reach down to the floor and close the ends (with the flanks they
	-- make the Kenney trapezoid end), overhanging the band for a flare
	local hopper = Instance.new("Model")
	hopper.Name = "Hopper"
	hopper.Parent = model
	local band = INNER + 0.1 -- a lip shows outside the flanks' bottom edge
	local body = span(hopper, "Body", Vector3.new(-band, 2.4, -INNER_Z), Vector3.new(band, FLOOR, INNER_Z), color, nil, true)
	hopper.PrimaryPart = body
	local flankWidth = FLANK_TOP - INNER
	for _, side in { -1, 1 } do
		sideWedge(
			hopper,
			"Flank",
			Vector3.new(side * (INNER + flankWidth / 2), (FLOOR + BRIM) / 2, 0),
			Vector3.new((END_Z - 0.06) * 2, BRIM - FLOOR, flankWidth),
			side,
			false,
			C.Hopper,
			true
		)
		span(hopper, "Rim", Vector3.new(side * INNER, BRIM, -END_Z), Vector3.new(side * RIM, TOP, END_Z), C.Hopper, nil, true)
		span(hopper, "Rim", Vector3.new(-INNER, FLOOR, side * INNER_Z), Vector3.new(INNER, TOP, side * END_Z), C.Hopper, nil, true)
	end
	attach(root, "TipPivot", CFrame.new(band, 2.4, 0))

	if loadColors and #loadColors > 0 then
		-- a neutral rubble bed keeps every ore color readable
		local bedTop = TOP - 0.15
		local bed = loadColors[1]:Lerp(C.Rubble, 0.6)
		span(hopper, "OreBed", Vector3.new(-INNER, BRIM, -INNER_Z), Vector3.new(INNER, bedTop, INNER_Z), bed)
		for i, lump in LUMPS do
			local s = lump.Size
			local oreColor = loadColors[(i - 1) % #loadColors + 1]
			if lump.Round then
				local at = CFrame.new(lump.Pos.X, bedTop + lump.Rise - s / 2, lump.Pos.Z)
				part(hopper, "Ore", "Ball", at, Vector3.new(s, s, s), oreColor)
			else
				local at = CFrame.new(lump.Pos.X, bedTop + lump.Rise - s * math.sqrt(3) / 2, lump.Pos.Z)
				part(hopper, "Ore", "Block", at * CFrame.Angles(0, lump.Yaw, 0) * VERTEX_UP, Vector3.new(s, s, s), oreColor)
			end
		end
	else
		-- empty: a dark floor plate deep down between the walls
		span(hopper, "Inside", Vector3.new(-INNER, FLOOR, -INNER_Z), Vector3.new(INNER, FLOOR + 0.1, INNER_Z), C.Interior)
	end

	couplers(model, bogieFront, bogieBack, -6.0, 6.0)
	return model
end

---------------------------------------------------------------- track

function TrainBuilder.track(length: number): Model
	local len = math.max(length, 1)
	local model = newModel("Track", "Track")
	local half = len / 2
	local rail = TrainBuilder.Gauge / 2
	-- no ballast bed: like track-detailed, the wide sleepers sit on the ground and
	-- stick out past the rails (the ladder look)
	for _, side in { -1, 1 } do
		span(
			model,
			"Rail",
			Vector3.new(side * rail - 0.3, 0.45, -half),
			Vector3.new(side * rail + 0.3, TrainBuilder.RailTop, half),
			C.Rail,
			nil,
			true
		)
	end
	local count = math.max(1, math.floor(len / TrainBuilder.SleeperSpacing + 0.5))
	local step = len / count
	for i = 1, count do
		local z = -half + (i - 0.5) * step
		local depth = math.min(0.9, step / 2 - 0.05)
		span(model, "Sleeper", Vector3.new(-4.2, 0, z - depth), Vector3.new(4.2, 0.45, z + depth), C.Sleeper, Enum.Material.Wood, true)
	end
	return model
end

return TrainBuilder
