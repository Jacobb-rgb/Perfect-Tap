--[[
	Builds the per-player ore train (design v2, docs/plans/STEP2_PLAN.md) in the
	style of the Kenney Train Kit, rebuilt from Roblox parts (no meshes):

	  locomotive(color, trim?)  chunky steam locomotive after train-locomotive-a/b/c:
	                            smokebox with a round door and a big lamp, chimney,
	                            steam dome, boiler with bands, cab with windows and
	                            a faceted roof, cow-catcher, red-spoked drive wheels
	                            with rods, small front wheels, buffers. <= 60 parts.
	  wagon(color, loads?)      ore wagon after train-carriage-dirt: a tipping hopper,
	                            the sub-model "Hopper", on two bogie frames, loaded
	                            with a heap of chunky ore lumps in the given colors;
	                            an empty hopper when nil or {}. <= 20 parts.
	  track(length)             straight track after track-detailed: two rails on wood
	                            sleepers (every ~6 studs) on a ballast bed. 4 + 1 per
	                            sleeper parts.

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
	Instance creation, so Lune tests and previews can build it.
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
	Smokebox = rgb(74, 78, 90), -- smokebox, chimney
	IronLight = rgb(112, 116, 130), -- smokebox door, chimney cap
	Steel = rgb(172, 178, 192), -- running board, tyres, rods, buffers, rails
	Roof = rgb(92, 96, 112),
	Soot = rgb(26, 26, 30),
	Red = rgb(200, 54, 46), -- wheel spokes, buffer beams (Kenney's red accent)
	Brass = rgb(226, 178, 78),
	Glass = rgb(150, 204, 238),
	Lamp = rgb(255, 210, 120),
	Interior = rgb(38, 38, 44),
	Sleeper = rgb(170, 108, 64),
	Ballast = rgb(94, 90, 88),
}

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
	the slope on top (roof, ore heap), false puts the flat face on top and the
	slope below (hopper flanks). side = 1 for +X, -1 for -X.
	size = (length, height, width).
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

-- Small axle: steel tyres + darker hub, one drum across both wheels (the frame hides the middle).
local function smallAxle(parent: Instance, z: number, diameter: number, halfSpan: number)
	local r = diameter / 2
	local pos = Vector3.new(0, r, z)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2, diameter, C.Steel), r)
	wheelPart(cyl(parent, "Wheel", pos, AXLE, halfSpan * 2 + 0.06, diameter * 0.6, C.Iron), r)
end

---------------------------------------------------------------- locomotive

function TrainBuilder.locomotive(color: Color3, trim: Color3?): Model
	local trimColor = trim or C.Brass
	local model, root = newModel("Locomotive", "Locomotive")
	local metal = Enum.Material.Metal

	-- frames (between the wheels) and the running board
	local bogieFront = span(model, "BogieFront", Vector3.new(-1.6, 0.55, -6.1), Vector3.new(1.6, 2.4, -1.2), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-1.95, 0.8, -1.2), Vector3.new(1.95, 2.4, 6.4), C.Iron)
	span(model, "Deck", Vector3.new(-2.9, 2.4, -6.15), Vector3.new(2.9, 2.75, 6.35), C.Steel, nil, true)
	span(model, "Valance", Vector3.new(-2.96, 2.1, -6.2), Vector3.new(2.96, 2.42, -0.9), trimColor)

	-- small front wheels and the big red-spoked drive wheels
	smallAxle(model, -4.6, 1.8, 2.3)
	smallAxle(model, -2.4, 1.8, 2.3)
	for _, z in { 0.5, 3.55 } do
		local d, half = 2.7, 2.6
		local r = d / 2
		local pos = Vector3.new(0, r, z)
		wheelPart(cyl(model, "Wheel", pos, AXLE, half * 2, d, C.Steel), r)
		wheelPart(cyl(model, "Wheel", pos, AXLE, half * 2 + 0.06, d * 0.8, C.Iron), r)
		for k = 0, 2 do
			local spoke = part(
				model,
				"Wheel",
				"Block",
				CFrame.new(pos) * CFrame.Angles(k * math.pi / 3, 0, 0),
				Vector3.new(half * 2 + 0.1, 0.3, d * 0.78),
				C.Red
			)
			wheelPart(spoke, r)
		end
		wheelPart(cyl(model, "Wheel", pos, AXLE, half * 2 + 0.24, 0.8, C.Brass, metal), r)
	end
	-- steam cylinders and the coupling rods (crosshead to the back crank)
	for _, side in { -1, 1 } do
		cyl(model, "SteamCylinder", Vector3.new(side * 2.62, 1.45, -3.45), ALONG_Z, 2.4, 1.1, color)
		span(model, "Rod", Vector3.new(side * 2.86, 1.0, -2.3), Vector3.new(side * 3.06, 1.32, 3.75), C.Steel)
	end

	-- front: buffer beam, buffers and a V cow-catcher
	span(model, "BufferBeam", Vector3.new(-2.9, 1.3, -6.5), Vector3.new(2.9, 2.4, -6.1), C.Red)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 1.9, TrainBuilder.CouplerHeight, -6.75), ALONG_Z, 0.5, 0.8, C.Steel)
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
			C.Steel
		)
	end

	-- boiler: smokebox (round door, big lamp), barrel with bands, chimney, dome
	local boilerY = 4.45
	cyl(model, "Smokebox", Vector3.new(0, boilerY, -4.6), ALONG_Z, 2.7, 3.75, C.Smokebox, nil, true)
	cyl(model, "SmokeboxDoor", Vector3.new(0, boilerY - 0.1, -6.05), ALONG_Z, 0.4, 2.5, C.IronLight)
	cyl(model, "Lamp", Vector3.new(0, 6.85, -5.45), ALONG_Z, 1.0, 1.25, trimColor, metal)
	cyl(model, "LampGlass", Vector3.new(0, 6.85, -5.97), ALONG_Z, 0.1, 0.85, C.Lamp, Enum.Material.Neon)
	cyl(model, "Boiler", Vector3.new(0, boilerY, -1.85), ALONG_Z, 3.0, 3.5, color, nil, true)
	for _, z in { -2.95, -1.0 } do
		cyl(model, "Band", Vector3.new(0, boilerY, z), ALONG_Z, 0.28, 3.64, trimColor, metal)
	end
	cyl(model, "Chimney", Vector3.new(0, 6.6, -4.4), ALONG_Y, 1.5, 1.25, C.Smokebox, nil, true)
	local cap = cyl(model, "ChimneyCap", Vector3.new(0, 7.675, -4.4), ALONG_Y, 0.65, 1.85, C.IronLight)
	cyl(model, "ChimneySoot", Vector3.new(0, 8.0, -4.4), ALONG_Y, 0.04, 1.35, C.Soot)
	attach(cap, "Smoke", CFrame.new(0, 8.05, -4.4))
	cyl(model, "Dome", Vector3.new(0, 6.3, -1.85), ALONG_Y, 0.9, 1.35, color)
	part(model, "DomeCap", "Ball", CFrame.new(0, 6.75, -1.85), Vector3.new(1.35, 1.35, 1.35), trimColor, metal)
	for _, side in { -1, 1 } do
		span(model, "Handrail", Vector3.new(side * 1.84, 5.08, -5.6), Vector3.new(side * 2.0, 5.24, -0.6), trimColor, metal)
	end

	-- cab: body with a trim band, windows, faceted roof
	span(model, "Cab", Vector3.new(-2.6, 2.75, -0.6), Vector3.new(2.6, 6.6, 6.2), color, nil, true)
	span(model, "CabBand", Vector3.new(-2.72, 2.72, -0.72), Vector3.new(2.72, 3.55, 6.32), trimColor)
	for _, side in { -1, 1 } do
		span(model, "WindowFrame", Vector3.new(side * 2.55, 4.05, 0.1), Vector3.new(side * 2.64, 6.15, 4.85), darker(color, 0.4))
		span(model, "Window", Vector3.new(side * 2.56, 4.3, 0.35), Vector3.new(side * 2.68, 5.9, 2.65), C.Glass)
		span(model, "Window", Vector3.new(side * 2.56, 4.3, 2.9), Vector3.new(side * 2.68, 5.9, 4.6), C.Glass)
	end
	span(model, "Window", Vector3.new(-1.4, 4.3, 6.15), Vector3.new(1.4, 5.9, 6.27), C.Glass)
	local roofZ0, roofZ1 = -1.2, 6.8
	local roofLen = roofZ1 - roofZ0
	local roofMid = (roofZ0 + roofZ1) / 2
	span(model, "Roof", Vector3.new(-3.05, 6.6, roofZ0), Vector3.new(3.05, 6.95, roofZ1), C.Roof, nil, true)
	span(model, "Roof", Vector3.new(-1.55, 6.95, roofZ0), Vector3.new(1.55, 8.2, roofZ1), C.Roof, nil, true)
	for _, side in { -1, 1 } do
		sideWedge(model, "Roof", Vector3.new(side * 2.3, 7.575, roofMid), Vector3.new(roofLen, 1.25, 1.5), side, true, C.Roof, true)
	end

	-- back: buffer beam and buffers
	span(model, "BufferBeam", Vector3.new(-2.75, 1.3, 6.3), Vector3.new(2.75, 2.4, 6.65), C.Red)
	for _, side in { -1, 1 } do
		cyl(model, "Buffer", Vector3.new(side * 1.9, TrainBuilder.CouplerHeight, 6.9), ALONG_Z, 0.5, 0.8, C.Steel)
	end

	couplers(model, bogieFront, bogieBack, -7.0, 7.15)
	model.PrimaryPart = root
	return model
end

---------------------------------------------------------------- wagon

-- The ore load: a gable-shaped heap with three big faceted lumps along its
-- ridge (tilted cubes sunk into the heap, so their tops read as low-poly rock
-- domes like the Kenney dirt load) and a smaller chunk. All stay inside the hopper.
type Lump = { Pos: Vector3, Size: Vector3, Rot: Vector3 }
local LUMPS: { Lump } = {
	{ Pos = Vector3.new(0.25, 6.05, -3.55), Size = Vector3.new(2.6, 2.6, 2.6), Rot = Vector3.new(0.65, 0.5, 0.4) },
	{ Pos = Vector3.new(-0.3, 6.5, 0), Size = Vector3.new(2.8, 2.8, 2.8), Rot = Vector3.new(0.6, 1.1, -0.45) },
	{ Pos = Vector3.new(0.25, 6.1, 3.55), Size = Vector3.new(2.6, 2.6, 2.6), Rot = Vector3.new(-0.65, 0.8, -0.45) },
	{ Pos = Vector3.new(1.35, 6.4, -1.75), Size = Vector3.new(1.9, 1.6, 1.9), Rot = Vector3.new(0.5, 0.4, 0.35) },
}

function TrainBuilder.wagon(color: Color3, loadColors: { Color3 }?): Model
	local model, root = newModel("OreWagon", "Wagon")

	-- two bogie frames (one long underframe) with two axles each
	local bogieFront = span(model, "BogieFront", Vector3.new(-2.4, 1.5, -6.0), Vector3.new(2.4, 2.45, 0), C.Iron)
	local bogieBack = span(model, "BogieBack", Vector3.new(-2.4, 1.5, 0), Vector3.new(2.4, 2.45, 6.0), C.Iron)
	for _, z in { -4.3, -2.15, 2.15, 4.3 } do
		wheelPart(cyl(model, "Wheel", Vector3.new(0, 0.9, z), AXLE, 4.6, 1.8, C.IronLight), 0.9)
	end

	-- the tipping hopper: narrow body, sloped flanks, a thick rim
	local hopper = Instance.new("Model")
	hopper.Name = "Hopper"
	hopper.Parent = model
	local body = span(hopper, "Body", Vector3.new(-1.9, 2.4, -5.3), Vector3.new(1.9, 6.0, 5.3), color, nil, true)
	hopper.PrimaryPart = body
	for _, side in { -1, 1 } do
		sideWedge(hopper, "Flank", Vector3.new(side * 2.45, 4.7, 0), Vector3.new(10.6, 2.6, 1.1), side, false, color, true)
		span(hopper, "Rim", Vector3.new(side * 2.72, 6.0, -5.75), Vector3.new(side * 3.22, 6.6, 5.75), darker(color, 0.35), nil, true)
		span(hopper, "Rim", Vector3.new(-3.22, 6.0, side * 5.25), Vector3.new(3.22, 6.6, side * 5.75), darker(color, 0.35))
	end
	attach(root, "TipPivot", CFrame.new(1.9, 2.4, 0))

	if loadColors and #loadColors > 0 then
		local heap = darker(loadColors[1], 0.35)
		for _, side in { -1, 1 } do
			sideWedge(hopper, "OreHeap", Vector3.new(side * 1.375, 6.7, 0), Vector3.new(10.4, 1.4, 2.75), side, true, heap)
		end
		for i, lump in LUMPS do
			local cf = CFrame.new(lump.Pos) * CFrame.Angles(lump.Rot.X, lump.Rot.Y, lump.Rot.Z)
			part(hopper, "Ore", "Block", cf, lump.Size, loadColors[(i - 1) % #loadColors + 1])
		end
	else
		span(hopper, "Inside", Vector3.new(-2.74, 5.95, -5.27), Vector3.new(2.74, 6.05, 5.27), C.Interior)
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
	span(model, "Ballast", Vector3.new(-3.8, 0, -half), Vector3.new(3.8, 0.3, half), C.Ballast, Enum.Material.Pebble)
	for _, side in { -1, 1 } do
		span(
			model,
			"Rail",
			Vector3.new(side * rail - 0.25, 0.6, -half),
			Vector3.new(side * rail + 0.25, TrainBuilder.RailTop, half),
			C.Steel,
			nil,
			true
		)
	end
	local count = math.max(1, math.floor(len / TrainBuilder.SleeperSpacing + 0.5))
	local step = len / count
	for i = 1, count do
		local z = -half + (i - 0.5) * step
		span(model, "Sleeper", Vector3.new(-3.3, 0.2, z - 0.65), Vector3.new(3.3, 0.6, z + 0.65), C.Sleeper, Enum.Material.Wood, true)
	end
	return model
end

return TrainBuilder
