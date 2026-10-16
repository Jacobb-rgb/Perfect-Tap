--[[
	Builds the per-player ore train (design v2, docs/plans/STEP2_PLAN.md) in the
	style of the Kenney Train Kit, rebuilt from Roblox parts (no meshes):

	  locomotive(color, trim?)  chunky steam locomotive after train-locomotive-a/b/c:
	                            grey smokebox whose front is a big door (dark iron
	                            ring, light plate, raised hub) with a lamp on top,
	                            chimney, steam dome, boiler with bands, cab with one
	                            framed window per side and an arched slate roof,
	                            cow-catcher, red buffer beam with Kenney's orange
	                            corner discs, big body-colored steam cylinders with
	                            a rod across the red-spoked drive wheels, small
	                            front wheels. Trim = brass (red on a brass-like body
	                            such as amber). 56 parts (budget 60).
	  wagon(color, loads?)      ore wagon after train-carriage-dirt: the tipping
	                            sub-model "Hopper" (body-colored sloped sides, thick
	                            steel rim and ends) on a steel chassis plate whose
	                            ends are the end beams, two short bogies with a gap
	                            under the middle, Kenney's end plates in the body
	                            color, loaded with a mound of four faceted ore rocks
	                            in the given colors; an open empty hopper when nil
	                            or {}. 20 parts loaded, 17 empty (budget 20). The
	                            hoppers end 0.8 before the couplers, so the cars of
	                            a consist stay apart.
	  track(length)             straight track after track-detailed: two chunky rails
	                            (0.85 x 0.8) on wide sleepers (every ~6 studs), no
	                            ballast bed. 3 + 1 per sleeper parts (budget 4 + 1
	                            per sleeper).

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
TrainBuilder.RailTop = 1.25 -- rail top above a track's Root = wheel bottoms
TrainBuilder.SleeperSpacing = 6
TrainBuilder.CouplerHeight = 1.85
TrainBuilder.MaxLocomotiveParts = 60
TrainBuilder.MaxWagonParts = 20

local rgb = Color3.fromRGB
local C = {
	Iron = rgb(52, 54, 64), -- frames, the smokebox door ring
	Smokebox = rgb(100, 104, 118), -- smokebox, chimney (Kenney mid grey)
	Door = rgb(150, 154, 170), -- the octagonal smokebox door
	IronLight = rgb(112, 116, 130), -- cow-catcher
	ChimneyTop = rgb(44, 45, 52), -- the sooty chimney crown (reads as the opening)
	Steel = rgb(172, 178, 192), -- tyres, rods, wagon wheels
	Deck = rgb(140, 144, 160), -- running board
	Roof = rgb(96, 100, 115), -- Kenney slate: darker than every body color's trim
	Red = rgb(200, 54, 46), -- wheel spokes, buffer beams (Kenney's red accent)
	Brass = rgb(226, 178, 78),
	Corner = rgb(250, 146, 40), -- Kenney's orange corner discs on the front beam
	Glass = rgb(150, 204, 238),
	Lamp = rgb(255, 184, 96), -- warm, so the bloom stays a small dot
	Interior = rgb(62, 64, 74), -- the floor of an empty hopper
	Hopper = rgb(150, 156, 175), -- Kenney steel grey: hopper flanks and rim
	Frame = rgb(118, 122, 138), -- wagon bogie side frames
	Rubble = rgb(96, 88, 82), -- the bed under the ore rocks (reads as the gaps)
	Sleeper = rgb(232, 140, 90), -- Kenney salmon wood
	Rail = rgb(190, 196, 225), -- Kenney lavender steel
}
TrainBuilder.Colors = C

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local AXLE = CFrame.new() -- along X (sideways): axles

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

-- Small axle: a steel tyre drum across both wheels (the frame hides the middle)
-- and a small brass hub (35 % of the wheel) standing 0.1 proud on each side, so
-- the wheel reads as a disc with a boss, not as a ring around a hole.
local function smallAxle(parent: Instance, z: number, diameter: number, halfSpan: number)
	local r = diameter / 2
	local pos = Vector3.new(0, r, z)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2, diameter, C.Steel), r)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2 + 0.2, diameter * 0.35, C.Brass, Enum.Material.Metal), r)
end

--[[
	The default trim is brass. A body color that is brass-like itself (the amber
	banner: same hue, value and saturation) would swallow the bands, valance and
	buffers, so it gets Kenney's red trim instead.
]]
function TrainBuilder.defaultTrim(color: Color3): Color3
	local h, s, v = color:ToHSV()
	local bh, bs, bv = C.Brass:ToHSV()
	local dh = math.abs(h - bh)
	dh = math.min(dh, 1 - dh) * 360
	if dh <= 30 and math.abs(v - bv) <= 0.15 and math.abs(s - bs) <= 0.35 then
		return C.Red
	end
	return C.Brass
end

---------------------------------------------------------------- locomotive

function TrainBuilder.locomotive(color: Color3, trim: Color3?): Model
	local trimColor = trim or TrainBuilder.defaultTrim(color)
	local model, root = newModel("Locomotive", "Locomotive")
	local metal = Enum.Material.Metal

	-- frames (between the wheels), the running board and a trim valance along it
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.6, 0.55, -6.1), Vector3.new(1.6, 2.4, -1.2), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.95, 0.8, -1.2), Vector3.new(1.95, 2.4, 6.4), C.Iron)
	span(model, "Deck", Vector3.new(-2.9, 2.4, -6.15), Vector3.new(2.9, 2.75, 6.35), C.Deck, nil, true)
	span(model, "Valance", Vector3.new(-2.98, 2.15, -6.2), Vector3.new(2.98, 2.46, 6.3), trimColor)

	-- small front wheels (narrow, so the big steam cylinders fit outboard of them)
	-- and the big red-spoked drive wheels (tyre, iron, spokes and brass hub each
	-- step out by >= 0.07 per side)
	smallAxle(model, -4.6, 1.8, 1.9)
	smallAxle(model, -2.4, 1.8, 1.9)
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
	-- Kenney's big steam cylinders: about a small wheel high, hung under the
	-- running board over the front wheels in the body color; the piston rod comes
	-- out of the rear face and runs across both brass hubs
	for _, side in { -1, 1 } do
		cyl(model, "SteamCylinder", Vector3.new(side * 2.7, 1.85, -3.5), ALONG_Z, 2.2, 1.46, color, nil, true)
		bar(model, "Rod", Vector3.new(side * 2.95, 1.85, -2.55), Vector3.new(side * 2.95, 1.3, 3.75), 0.18, 0.28, C.Steel)
	end

	-- front: red buffer beam with Kenney's orange corner discs (the buffers) and a
	-- V cow-catcher
	span(model, "BufferBeam", Vector3.new(-2.9, 1.3, -6.5), Vector3.new(2.9, 2.4, -6.1), C.Red)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 2.2, TrainBuilder.CouplerHeight, -6.75), ALONG_Z, 0.5, 0.95, C.Corner)
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

	-- boiler: grey smokebox whose front is Kenney's big door (a dark iron ring, an
	-- octagonal plate from two squares 45 degrees apart and a raised hub), the lamp
	-- on top, the barrel with bands, chimney with a sooty crown, steam dome
	local boilerY = 4.45
	cyl(model, "Smokebox", Vector3.new(0, boilerY, -4.6), ALONG_Z, 2.7, 3.75, C.Smokebox, nil, true)
	cyl(model, "SmokeboxDoor", Vector3.new(0, boilerY, -6.05), ALONG_Z, 0.4, 3.3, C.Iron)
	cyl(model, "DoorPlate", Vector3.new(0, boilerY, -6.33), ALONG_Z, 0.16, 2.6, C.Door)
	cyl(model, "DoorHub", Vector3.new(0, boilerY, -6.55), ALONG_Z, 0.36, 1.3, C.Smokebox)
	cyl(model, "Lamp", Vector3.new(0, 6.5, -5.7), ALONG_Z, 1.0, 0.95, trimColor, metal)
	cyl(model, "LampGlass", Vector3.new(0, 6.5, -6.24), ALONG_Z, 0.08, 0.5, C.Lamp, Enum.Material.Neon)
	cyl(model, "Boiler", Vector3.new(0, boilerY, -1.85), ALONG_Z, 3.0, 3.5, color, nil, true)
	for _, z in { -2.95, -1.0 } do
		cyl(model, "Band", Vector3.new(0, boilerY, z), ALONG_Z, 0.28, 3.64, trimColor, metal)
	end
	cyl(model, "Chimney", Vector3.new(0, 6.6, -4.4), ALONG_Y, 1.5, 1.25, C.Smokebox, nil, true)
	local cap = cyl(model, "ChimneyCap", Vector3.new(0, 7.675, -4.4), ALONG_Y, 0.65, 1.85, C.ChimneyTop)
	attach(cap, "Smoke", CFrame.new(0, 8.05, -4.4))
	cyl(model, "Dome", Vector3.new(0, 6.3, -2.0), ALONG_Y, 0.9, 1.35, color)
	-- matte and a shade darker, so it never catches a highlight like a second lamp
	part(model, "DomeCap", "Ball", CFrame.new(0, 6.75, -2.0), Vector3.new(1.35, 1.35, 1.35), darker(trimColor, 0.12))

	-- cab: body with a trim band, one compact window per side near the front in a
	-- thick dark frame (the rear of the side stays plain), and Kenney's arched
	-- slate roof: an eave plate that overhangs front and back, a narrow flat top
	-- and two tall sloped sides
	span(model, "Cab", Vector3.new(-2.6, 2.75, -0.6), Vector3.new(2.6, 6.6, 6.2), color, nil, true)
	span(model, "CabBand", Vector3.new(-2.72, 2.72, -0.72), Vector3.new(2.72, 3.55, 6.32), trimColor)
	for _, side in { -1, 1 } do
		span(model, "WindowFrame", Vector3.new(side * 2.55, 3.9, -0.05), Vector3.new(side * 2.7, 6.1, 2.55), darker(color, 0.45))
		span(model, "Window", Vector3.new(side * 2.56, 4.25, 0.3), Vector3.new(side * 2.76, 5.8, 2.2), C.Glass)
	end
	local roofZ0, roofZ1 = -1.25, 7.1 -- the front stops just behind the dome, the back overhangs 0.9
	local roofLen = roofZ1 - roofZ0
	local roofMid = (roofZ0 + roofZ1) / 2
	local ridge, slope, roofH = 1.1, 2.15, 0.9
	span(model, "Roof", Vector3.new(-3.25, 6.6, roofZ0), Vector3.new(3.25, 6.95, roofZ1), C.Roof, nil, true)
	span(model, "Roof", Vector3.new(-ridge, 6.95, roofZ0), Vector3.new(ridge, 6.95 + roofH, roofZ1), C.Roof, nil, true)
	for _, side in { -1, 1 } do
		sideWedge(
			model,
			"Roof",
			Vector3.new(side * (ridge + slope / 2), 6.95 + roofH / 2, roofMid),
			Vector3.new(roofLen, roofH, slope),
			side,
			true,
			C.Roof,
			true
		)
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
	The ore load, a heap like the Kenney dirt load: a dark rubble bed just under
	the rim (it reads as the gaps between the rocks) and four chunky faceted
	rocks (blocks, each turned its own way like ItemBuilder's ore chunks, so every
	one shows three flat facets in different shades): three big ones along the
	middle that overlap into one mound peaking in the middle and a smaller one in
	a saddle. Rise = how far a rock's highest corner stands above the bed. Every
	corner stays inside the hopper walls (no rock pokes through a flank).
]]
type Lump = { Pos: Vector3, Size: Vector3, Rise: number, Turn: Vector3 }
local LUMPS: { Lump } = {
	{ Pos = Vector3.new(-0.15, 0, -3.1), Size = Vector3.new(2.9, 2.3, 2.7), Rise = 1.7, Turn = Vector3.new(0.5, 0.4, 0.6) },
	{ Pos = Vector3.new(0.05, 0, 0.05), Size = Vector3.new(2.9, 2.5, 2.7), Rise = 2.1, Turn = Vector3.new(0.35, -0.6, -0.45) },
	{ Pos = Vector3.new(0.25, 0, 2.95), Size = Vector3.new(2.6, 2.4, 2.9), Rise = 1.6, Turn = Vector3.new(-0.3, 1.1, 0.5) },
	{ Pos = Vector3.new(-1.0, 0, -1.45), Size = Vector3.new(1.9, 1.7, 1.9), Rise = 1.2, Turn = Vector3.new(-0.6, 0.3, -0.4) },
}

-- hopper cross-section (model space)
local INNER = 2.05 -- inner half width: the flanks' vertical inner faces
local FLANK_TOP = 2.65 -- outer edge of the flanks at the rim
local RIM = 2.85 -- outer half width of the rim (~85 % of the locomotive)
local CHASSIS_X, CHASSIS_Y, CHASSIS_Z = 2.35, 1.9, 5.9 -- the end-beam chassis plate
local FLOOR, BRIM, TOP = 2.8, 5.8, 6.4 -- hopper floor, flank tops, rim top
-- inner end walls and the outer ends of the rim: the rims end 0.8 before the
-- couplers, so a consist shows a clear gap between the hoppers
local INNER_Z, END_Z = 4.6, 5.2
local PLATE = 0.2 -- how far the end plates stand out of the end walls
TrainBuilder.HopperEndZ = END_Z

-- Half extents of a rotated box along the model axes.
local function extents(cf: CFrame, size: Vector3): Vector3
	local h = size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
end

function TrainBuilder.wagon(color: Color3, loadColors: { Color3 }?): Model
	local model, root = newModel("OreWagon", "Wagon")

	-- running gear: two short bogies with a gap between them (the ground shows
	-- under the middle of the hopper); each narrow side frame hides the middle of
	-- its two axle drums, so only the steel wheel ends show outboard of it
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.7, 0.55, -5.4), Vector3.new(1.7, CHASSIS_Y, -1.6), C.Frame)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.7, 0.55, 1.6), Vector3.new(1.7, CHASSIS_Y, 5.4), C.Frame)
	for _, z in { -4.45, -2.55, 2.55, 4.45 } do
		wheelPart(cyl(model, "Wheel", Vector3.new(0, 0.85, z), AXLE, 4.6, 1.7, C.Steel), 0.85)
	end

	-- the hollow tipping hopper on its chassis plate: the plate ("Body", body
	-- color) is wider and longer than the hopper, so its ends are the end beams
	-- between the cars; sloped flanks whose inner faces are the side walls; a thick
	-- steel rim whose end pieces reach down to the floor and close the ends (with
	-- the flanks they make the Kenney trapezoid end)
	local hopper = Instance.new("Model")
	hopper.Name = "Hopper"
	hopper.Parent = model
	local body =
		span(hopper, "Body", Vector3.new(-CHASSIS_X, CHASSIS_Y, -CHASSIS_Z), Vector3.new(CHASSIS_X, FLOOR, CHASSIS_Z), C.Hopper, nil, true)
	hopper.PrimaryPart = body
	local flankWidth = FLANK_TOP - INNER
	for _, side in { -1, 1 } do
		sideWedge(
			hopper,
			"Flank",
			Vector3.new(side * (INNER + flankWidth / 2), (FLOOR + BRIM) / 2, 0),
			Vector3.new(END_Z * 2, BRIM - FLOOR, flankWidth),
			side,
			false,
			color,
			true
		)
		span(hopper, "Rim", Vector3.new(side * INNER, BRIM, -END_Z), Vector3.new(side * RIM, TOP, END_Z), C.Hopper, nil, true)
		span(hopper, "Rim", Vector3.new(-INNER, FLOOR, side * INNER_Z), Vector3.new(INNER, TOP, side * END_Z), C.Hopper, nil, true)
	end
	attach(root, "TipPivot", CFrame.new(CHASSIS_X, CHASSIS_Y, 0))
	local function endPlate(z0: number, z1: number)
		span(hopper, "EndPlate", Vector3.new(-0.85, FLOOR + 0.35, z0), Vector3.new(0.85, FLOOR + 1.75, z1), color)
	end

	if loadColors and #loadColors > 0 then
		local bedTop = TOP - 0.15
		local bed = darker(loadColors[1]:Lerp(C.Rubble, 0.55), 0.25)
		span(hopper, "OreBed", Vector3.new(-INNER, BRIM, -INNER_Z), Vector3.new(INNER, bedTop, INNER_Z), bed)
		-- Kenney's end plates in the body color: one block through the hollow under
		-- the bed shows on both ends (one part instead of two)
		endPlate(-END_Z - PLATE, END_Z + PLATE)
		local n = #loadColors
		for i, lump in LUMPS do
			-- the colors cycle; a repeat is 12 % darker, so neighbours of one color
			-- still show their facets in flat light (the first round stays exact)
			local oreColor = loadColors[(i - 1) % n + 1]
			if ((i - 1) // n) % 2 == 1 then
				oreColor = darker(oreColor, 0.12)
			end
			local turn = CFrame.Angles(lump.Turn.X, lump.Turn.Y, lump.Turn.Z)
			local rise = extents(turn, lump.Size).Y
			local at = CFrame.new(lump.Pos.X, bedTop + lump.Rise - rise, lump.Pos.Z) * turn
			part(hopper, "Ore", "Block", at, lump.Size, oreColor)
		end
	else
		-- empty: a dark floor plate deep down between the walls, and an end plate
		-- on each end (the open hopper would show a through-block)
		span(hopper, "Inside", Vector3.new(-INNER, FLOOR, -INNER_Z), Vector3.new(INNER, FLOOR + 0.1, INNER_Z), C.Interior)
		for _, side in { -1, 1 } do
			endPlate(side * (END_Z - 0.1), side * (END_Z + PLATE))
		end
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
	-- stick out past the rails (the ladder look); the rails are chunky bars (0.85
	-- wide, 0.8 tall) so they hold their own under the chunky locomotive
	for _, side in { -1, 1 } do
		span(
			model,
			"Rail",
			Vector3.new(side * rail - 0.425, 0.45, -half),
			Vector3.new(side * rail + 0.425, TrainBuilder.RailTop, half),
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
