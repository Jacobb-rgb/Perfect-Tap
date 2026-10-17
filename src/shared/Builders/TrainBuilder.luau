--[[
	Builds the per-player ore train (design v2, docs/plans/STEP2_PLAN.md) in the
	style of the Kenney Train Kit, rebuilt from Roblox parts (no meshes):

	  locomotive(color, trim?)  chunky steam locomotive after train-locomotive-a/b/c:
	                            grey smokebox whose front is a big door (dark iron
	                            ring, light plate, raised hub) with a lamp on top,
	                            a sooty chimney stack in a lighter flared crown (its
	                            top reads as the opening), steam dome, boiler with
	                            bands, cab with a framed window and a dark entrance
	                            per side under an arched slate roof, Kenney's light
	                            running board, an iron cow-catcher tucked under a
	                            dark red buffer beam with orange corner discs, steam
	                            cylinders a shade darker than the body, red-spoked
	                            drive wheels joined by a level coupling rod plus a
	                            main rod from each cylinder, small front wheels.
	                            Trim = brass (red on a brass-like body such as
	                            amber). 60 parts (budget 60).
	  wagon(color, loads?)      ore wagon after train-carriage-dirt: two short
	                            bogies (dark side frames over the upper half of
	                            mid-steel wheels) under a steel chassis plate whose
	                            ends are the end beams; on it the tipping sub-model
	                            "Hopper": body-colored sloped flanks between two
	                            steel end walls (one clean block per end with a
	                            raised plate in the body color), a steel rim lip;
	                            loaded with a dome of chunky, mostly upright ore
	                            rocks (a two-block boulder in the middle, a chunk
	                            rolled toward each end) in the given colors on a
	                            dark rubble bed;
	                            an open empty hopper when nil or {}. 20 parts
	                            loaded, 17 empty (budget 20). The hoppers end 0.8
	                            before the couplers, so the cars of a consist stay
	                            apart.
	  track(length)             straight track after track-detailed: two chunky
	                            lavender rails (0.85 x 0.8) on deep salmon sleepers
	                            (every ~6 studs), no ballast bed. 3 + 1 per sleeper
	                            parts (budget 4 + 1 per sleeper).

	Contract (all three): a Model whose PrimaryPart "Root" (invisible) sits at the
	bottom center, front = -Z, +Y up. Trains stand on the rails when their Root is
	placed RailTop studs above a track's Root. Locomotive and wagon have the
	Attachments "CouplerFront" (on the part "BogieFront") and "CouplerBack" (on
	"BogieBack") at the buffer faces; the next vehicle's CouplerFront goes on the
	previous one's CouplerBack. Every part named "Wheel" is centered on its axle
	with its local X axis along the axle (spin: part.CFrame * CFrame.Angles(a, 0, 0))
	and carries the axle's rolling radius in the attribute "Radius". The locomotive
	has a "Smoke" Attachment at the chimney top (world up = +Y). The wagon's
	"Hopper" sub-model (PrimaryPart = a side "Rim") holds only the tipping body and
	its load: it tips about the Z axis through the Root attachment "TipPivot" (its
	outer bottom edge on the chassis, dumping to +X):
	  hopper:PivotTo(pivot * CFrame.Angles(0, 0, -angle) * pivot:Inverse() * hopper:GetPivot())
	while the bogies, wheels and the chassis stay in place.
	Model attributes: "Kind" = Locomotive | Wagon | Track, "Length" = distance
	between the two couplers (locomotive and wagon).

	Everything is anchored, CanCollide/CanTouch/CanQuery off (the train is a client
	visual), CastShadow only on the big parts. Pure and deterministic: only
	Instance creation, so Lune tests and previews can build it. Faces of different
	colors that sit on top of each other step out by >= 0.06 stud (no z-fighting
	on phones).
]]

local TrainBuilder = {}

TrainBuilder.Gauge = 4.4 -- rail centers (the wheels sit on x = +-Gauge / 2)
TrainBuilder.RailTop = 1.25 -- rail top above a track's Root = wheel bottoms
TrainBuilder.SleeperSpacing = 6
TrainBuilder.CouplerHeight = 1.85
TrainBuilder.MaxLocomotiveParts = 60
TrainBuilder.MaxWagonParts = 20

local rgb = Color3.fromRGB
-- The greys lean blue: the golden-hour Surface light (warm sun, pink outdoor
-- ambient) turns a neutral grey mauve; these render as Kenney's cool lavender
-- steel and slate.
local C = {
	Iron = rgb(52, 54, 64), -- frames, the smokebox door ring, the cow-catcher
	Smokebox = rgb(96, 104, 132), -- smokebox, the chimney crown (Kenney mid grey)
	Door = rgb(146, 154, 186), -- the smokebox door plate
	Soot = rgb(44, 45, 52), -- the chimney stack (its top is the opening)
	Steel = rgb(166, 176, 206), -- tyres, rods
	WheelSteel = rgb(126, 138, 178), -- wagon wheels: mid steel under the dark side frames
	Deck = rgb(190, 200, 238), -- Kenney's off-white running board
	Roof = rgb(104, 114, 150), -- Kenney slate
	Red = rgb(200, 54, 46), -- Kenney's red accent (the trim of brass-like bodies)
	Spoke = rgb(228, 64, 52), -- drive wheel spokes, bright so they read half covered
	WheelRed = rgb(132, 34, 32), -- the drive wheel disc behind the spokes
	Beam = rgb(150, 36, 32), -- buffer beams: darker than any red body
	Brass = rgb(226, 178, 78),
	Corner = rgb(250, 146, 40), -- Kenney's orange corner discs on the front beam
	Glass = rgb(150, 204, 238),
	Lamp = rgb(255, 184, 96), -- warm, so the bloom stays a small dot
	Interior = rgb(62, 64, 74), -- the floor of an empty hopper
	Hopper = rgb(132, 148, 200), -- Kenney steel: hopper rim, end walls, chassis
	Rubble = rgb(74, 66, 62), -- the bed under the ore rocks: shadowed rock in every load
	Sleeper = rgb(232, 140, 90), -- Kenney salmon wood
	Rail = rgb(152, 172, 248), -- Kenney lavender steel
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

	-- frames (between the wheels), Kenney's light running board and a thin trim
	-- valance along it (kept high and close, so the drive wheels show)
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.6, 0.55, -6.1), Vector3.new(1.6, 2.4, -1.2), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.95, 0.8, -1.2), Vector3.new(1.95, 2.4, 6.4), C.Iron)
	span(model, "Deck", Vector3.new(-2.82, 2.4, -6.15), Vector3.new(2.82, 2.75, 6.35), C.Deck, nil, true)
	span(model, "Valance", Vector3.new(-2.9, 2.3, -6.2), Vector3.new(2.9, 2.46, 6.3), trimColor)

	-- small front wheels (narrow, so the big steam cylinders fit outboard of them)
	-- and the big drive wheels: steel tyre, dark red disc, bright red spokes and a
	-- brass hub (each steps out by >= 0.07 per side)
	smallAxle(model, -4.6, 1.8, 1.9)
	smallAxle(model, -2.4, 1.8, 1.9)
	for _, z in { 0.5, 3.55 } do
		local d = 2.7
		local r = d / 2
		local pos = Vector3.new(0, r, z)
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.16, d, C.Steel), r)
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.3, d * 0.8, C.WheelRed), r)
		for k = 0, 2 do
			local spoke = part(
				model,
				"Wheel",
				"Block",
				CFrame.new(pos) * CFrame.Angles(k * math.pi / 3, 0, 0),
				Vector3.new(5.45, 0.3, d * 0.78),
				C.Spoke
			)
			wheelPart(spoke, r)
		end
		wheelPart(cyl(model, "Wheel", pos, AXLE, 5.6, 0.8, C.Brass, metal), r)
	end
	-- Kenney's big steam cylinders: about a small wheel high, hung under the
	-- running board over the front wheels, a shade darker than the body (so they
	-- part from the cab and the beam on a red train); a level coupling rod at
	-- crank-pin height joins the drive wheels, and a main rod runs from each
	-- piston down to the front crank, outboard of it
	local crankY = 1.05
	for _, side in { -1, 1 } do
		cyl(model, "SteamCylinder", Vector3.new(side * 2.7, 1.85, -3.5), ALONG_Z, 2.2, 1.46, darker(color, 0.15), nil, true)
		bar(model, "Rod", Vector3.new(side * 2.95, crankY, 0.1), Vector3.new(side * 2.95, crankY, 3.95), 0.18, 0.3, C.Steel)
		bar(model, "Rod", Vector3.new(side * 3.12, 1.85, -2.5), Vector3.new(side * 3.12, crankY, 0.6), 0.16, 0.26, C.Steel)
	end

	-- front: dark red buffer beam with Kenney's orange corner discs (the buffers)
	-- and an iron V cow-catcher tucked under it (its back edge stays under the
	-- beam, inside the buffers)
	span(model, "BufferBeam", Vector3.new(-2.86, 1.3, -6.5), Vector3.new(2.86, 2.4, -6.1), C.Beam)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 2.2, TrainBuilder.CouplerHeight, -6.75), ALONG_Z, 0.5, 0.95, C.Corner)
	end
	local theta, width, depth, tipZ = math.rad(15), 2.68, 0.78, -7.55
	for _, side in { -1, 1 } do
		local x = Vector3.new(math.cos(theta), 0, side * math.sin(theta))
		local zAxis = Vector3.new(-side * math.sin(theta), 0, math.cos(theta))
		local center = Vector3.new(
			side * (width / 2 * math.cos(theta) - depth / 2 * math.sin(theta)),
			0.85,
			tipZ + width / 2 * math.sin(theta) + depth / 2 * math.cos(theta)
		)
		part(
			model,
			"CowCatcher",
			"Wedge",
			CFrame.fromMatrix(center, x, Vector3.new(0, 1, 0), zAxis),
			Vector3.new(width, 1.0, depth),
			C.Iron
		)
	end

	-- boiler: grey smokebox whose front is Kenney's big door (a dark iron ring, a
	-- light plate and a raised hub), the lamp on top, the barrel with bands, a
	-- sooty chimney stack standing 0.06 out of a lighter flared crown (its top is
	-- the dark opening), steam dome
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
	local stackTop = 8.06
	local stack = cyl(model, "Chimney", Vector3.new(0, (5.85 + stackTop) / 2, -4.4), ALONG_Y, stackTop - 5.85, 1.15, C.Soot, nil, true)
	cyl(model, "ChimneyCap", Vector3.new(0, 7.675, -4.4), ALONG_Y, 0.65, 1.85, C.Smokebox)
	attach(stack, "Smoke", CFrame.new(0, stackTop + 0.04, -4.4))
	cyl(model, "Dome", Vector3.new(0, 6.3, -2.0), ALONG_Y, 0.9, 1.35, color)
	-- matte and a shade darker, so it never catches a highlight like a second lamp
	part(model, "DomeCap", "Ball", CFrame.new(0, 6.75, -2.0), Vector3.new(1.35, 1.35, 1.35), darker(trimColor, 0.12))

	-- cab: body with a trim band; per side a compact window in a thick dark frame
	-- near the front and a tall dark entrance at the back (Kenney's second
	-- opening); Kenney's arched slate roof: an eave plate that overhangs front and
	-- back, a narrow flat top and two tall sloped sides
	span(model, "Cab", Vector3.new(-2.6, 2.75, -0.6), Vector3.new(2.6, 6.6, 6.2), color, nil, true)
	span(model, "CabBand", Vector3.new(-2.72, 2.72, -0.72), Vector3.new(2.72, 3.55, 6.32), trimColor)
	for _, side in { -1, 1 } do
		span(model, "WindowFrame", Vector3.new(side * 2.55, 3.9, -0.05), Vector3.new(side * 2.7, 6.1, 2.55), darker(color, 0.45))
		span(model, "Window", Vector3.new(side * 2.56, 4.25, 0.3), Vector3.new(side * 2.76, 5.8, 2.2), C.Glass)
		span(model, "CabDoor", Vector3.new(side * 2.55, 3.55, 4.15), Vector3.new(side * 2.7, 6.1, 5.45), darker(color, 0.45))
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
	span(model, "BufferBeam", Vector3.new(-2.75, 1.3, 6.3), Vector3.new(2.75, 2.4, 6.65), C.Beam)
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
	the rim (it reads as the shadowed gaps between the rocks) and chunky rocks
	made of blocks that stay mostly upright (a yaw of their own and a tilt of at
	most ~0.2 rad, so each shows a broad, slightly tipped top facet and its side
	facets): in the middle the big boulder that peaks the mound, two blocks of
	one color turned 45 degrees apart (Kenney's octagonal boulder outline), and at
	each end a lower chunk turned ~45 degrees (a vertical edge toward the end)
	and rolled outward, so the heap slopes down to the ends like a dome. Show =
	the share of a rock's height that stands above the bed (the rest sits in the
	bed); Tone = which load color it takes. Every corner stays inside the hopper
	walls (no rock pokes through a flank or an end).
]]
type Lump = { Pos: Vector3, Size: Vector3, Show: number, Yaw: number, Tilt: Vector3, Tone: number }
local LUMPS: { Lump } = {
	{
		Pos = Vector3.new(0.05, 0, 0),
		Size = Vector3.new(2.9, 2.5, 2.9),
		Show = 0.62,
		Yaw = 0.2,
		Tilt = Vector3.new(0.1, 0, 0.14),
		Tone = 1,
	},
	{
		Pos = Vector3.new(0.05, 0, 0),
		Size = Vector3.new(2.9, 2.5, 2.9),
		Show = 0.62,
		Yaw = 0.2 + math.pi / 4,
		Tilt = Vector3.new(-0.14, 0, 0.06),
		Tone = 1,
	},
	{
		Pos = Vector3.new(-0.15, 0, -2.9),
		Size = Vector3.new(2.4, 2.1, 2.4),
		Show = 0.56,
		Yaw = math.pi / 4 + 0.1,
		Tilt = Vector3.new(-0.2, 0, -0.2),
		Tone = 2,
	},
	{
		Pos = Vector3.new(0.15, 0, 2.9),
		Size = Vector3.new(2.4, 2.1, 2.4),
		Show = 0.55,
		Yaw = math.pi / 4 - 0.15,
		Tilt = Vector3.new(0.2, 0, 0.2),
		Tone = 3,
	},
}

-- hopper cross-section (model space)
local INNER = 2.05 -- inner half width: the flanks' vertical inner faces
local FLANK_TOP = 2.65 -- outer edge of the flanks at the rim = the end walls' half width
local RIM = 2.85 -- outer half width of the rim lip (~85 % of the locomotive)
local CHASSIS_X, CHASSIS_Y, CHASSIS_Z = 2.55, 1.9, 5.9 -- the end-beam chassis plate
local FLOOR, BRIM, TOP = 2.8, 5.8, 6.4 -- hopper floor, flank tops, rim top
-- inner end walls and the outer ends of the rim: the rims end 0.8 before the
-- couplers, so a consist shows a clear gap between the hoppers
local INNER_Z, END_Z = 4.6, 5.2
local PLATE = 0.2 -- how far the end plates stand out of the end walls
local WHEEL_R = 0.85 -- wagon wheel radius = axle height = the side frames' bottom
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
	-- under the middle of the hopper). Each bogie is Kenney's dark side frame:
	-- outboard of its two mid-steel wheel drums, its bottom at axle height, so it
	-- covers the upper half of the wheels and their lower halves show under it.
	local bogieFront = span(model, "BogieFront", Vector3.new(-2.45, WHEEL_R, -5.4), Vector3.new(2.45, CHASSIS_Y, -1.6), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-2.45, WHEEL_R, 1.6), Vector3.new(2.45, CHASSIS_Y, 5.4), C.Iron)
	for _, z in { -4.45, -2.55, 2.55, 4.45 } do
		wheelPart(cyl(model, "Wheel", Vector3.new(0, WHEEL_R, z), AXLE, 4.6, WHEEL_R * 2, C.WheelSteel), WHEEL_R)
	end
	-- the steel chassis plate, wider and longer than the hopper: its ends are the
	-- end beams between the cars. It stays on the bogies when the hopper tips.
	span(model, "Chassis", Vector3.new(-CHASSIS_X, CHASSIS_Y, -CHASSIS_Z), Vector3.new(CHASSIS_X, FLOOR, CHASSIS_Z), C.Hopper, nil, true)

	-- the hollow tipping hopper on the chassis: sloped flanks in the body color
	-- (their inner faces are the side walls) between two steel end walls (one
	-- clean block per end, as wide as the flanks' top), a steel rim lip along the
	-- sides that overhangs the ends, and Kenney's raised end plates in the body
	-- color
	local hopper = Instance.new("Model")
	hopper.Name = "Hopper"
	hopper.Parent = model
	local flankWidth = FLANK_TOP - INNER
	for _, side in { -1, 1 } do
		sideWedge(
			hopper,
			"Flank",
			Vector3.new(side * (INNER + flankWidth / 2), (FLOOR + BRIM) / 2, 0),
			Vector3.new(INNER_Z * 2, BRIM - FLOOR, flankWidth),
			side,
			false,
			color,
			true
		)
		local rim = span(hopper, "Rim", Vector3.new(side * INNER, BRIM, -END_Z), Vector3.new(side * RIM, TOP, END_Z), C.Hopper, nil, true)
		if side == 1 then
			hopper.PrimaryPart = rim
		end
		span(
			hopper,
			"EndWall",
			Vector3.new(-FLANK_TOP, FLOOR, side * INNER_Z),
			Vector3.new(FLANK_TOP, TOP, side * END_Z),
			C.Hopper,
			nil,
			true
		)
	end
	-- the hinge: the hopper's outer bottom edge on the chassis
	attach(root, "TipPivot", CFrame.new(FLANK_TOP, FLOOR, 0))
	local function endPlate(z0: number, z1: number)
		span(hopper, "EndPlate", Vector3.new(-1.1, FLOOR + 0.3, z0), Vector3.new(1.1, FLOOR + 2.1, z1), color)
	end

	if loadColors and #loadColors > 0 then
		local bedTop = TOP - 0.15
		span(hopper, "OreBed", Vector3.new(-INNER, BRIM, -INNER_Z), Vector3.new(INNER, bedTop, INNER_Z), C.Rubble)
		-- Kenney's end plates: one block through the hollow under the bed shows on
		-- both ends (one part instead of two)
		endPlate(-END_Z - PLATE, END_Z + PLATE)
		local n = #loadColors
		for _, lump in LUMPS do
			-- the colors cycle; a repeat is 12 % darker, so neighbours of one color
			-- still show their facets in flat light (the first round stays exact)
			local t = lump.Tone
			local oreColor = loadColors[(t - 1) % n + 1]
			if ((t - 1) // n) % 2 == 1 then
				oreColor = darker(oreColor, 0.12)
			end
			local turn = CFrame.Angles(0, lump.Yaw, 0) * CFrame.Angles(lump.Tilt.X, 0, lump.Tilt.Z)
			local half = extents(turn, lump.Size).Y
			local at = CFrame.new(lump.Pos.X, bedTop + half * (2 * lump.Show - 1), lump.Pos.Z) * turn
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
	-- stick out past the rails (the ladder look); the rails are chunky lavender
	-- bars (0.85 wide, 0.8 tall) so they hold their own under the chunky
	-- locomotive. (track-detailed's tie plates would need a pair of parts per
	-- rail or per sleeper; the budget of 4 + 1 per sleeper leaves one spare.)
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
		-- deep sleepers (2.4 studs at the 6-stud spacing): Kenney's tight tie rhythm
		local depth = math.min(1.2, step / 2 - 0.05)
		span(model, "Sleeper", Vector3.new(-4.2, 0, z - depth), Vector3.new(4.2, 0.45, z + depth), C.Sleeper, Enum.Material.Wood, true)
	end
	return model
end

return TrainBuilder
