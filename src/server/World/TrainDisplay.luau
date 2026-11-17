--[[
	TrainDisplay: the ore train as a still decoration (owner 2026-11-17: "The
	train should basically become just a static decorative object sitting on a
	platform. It should have no functionality at all."). The railway, its
	tunnels, the Mine Station, the yards' train stops and every train system
	are gone. On the quarry floor east of the ramp's foot, where the train used
	to wait at the Mine Station, one plain flagstone platform carries the red
	locomotive and two loaded ore wagons (TrainBuilder), coupled, standing
	still, facing the ramp the players come down. Beside it the Mine Station's
	shelter stands again as it was (owner 2026-11-17 after his test: "the
	shelter that was there by the train, put it back, only it must do
	nothing"): its platform with the access ramp and the safety edge, the
	canopy (posts, collars, beams, the red pitched roof, now closed: no
	hopper under it), the MINE STATION sign on the roof, the lamps under
	the eaves with one pendant light, and the crates; without the hopper,
	the bucket elevator, the chute, the lever console and the prompts.

	No rails, no prompts, no scripts, no sounds: it is a prop. The platforms
	collide like the floor; the train's own parts are TrainBuilder's (no
	collisions), so one invisible box per vehicle keeps players out of it.
	Everything is anchored. Pure and deterministic (Instance creation only),
	so Lune tests, the bake and previews build it; the world keeps rocks and
	big decorations off it (WorldLayout.KeepOut).

	  TrainDisplay.build(map)  builds Map.TrainDisplay (replacing an old one)
	  TrainDisplay.Platform    the train's { Center (its ground middle), Size }
	  TrainDisplay.Shelter     the shelter's platform { Center, Size } (the old station's)
	  TrainDisplay.MaxParts    the whole display's budget (tests/TrainDisplay.spec.luau)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared.Builders.Geo)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local WorldLayout = require(Shared.Config.WorldLayout)

local TrainDisplay = {}

local rgb = Color3.fromRGB

-- On the quarry floor where the train waited at the Mine Station (its line at z -156): a little
-- longer than the train (the locomotive and two wagons: 38 studs coupler to coupler), which stands
-- in its middle; the shelter's platform beside it, where the station's was (a 2-stud gap between).
TrainDisplay.Platform = {
	Center = Vector3.new(26, WorldLayout.Quarry.Min.Y, -156),
	Size = Vector3.new(44, 0.8, 8),
}
TrainDisplay.Shelter = {
	Center = Vector3.new(26, WorldLayout.Quarry.Min.Y, -147),
	Size = Vector3.new(28, 1.2, 6),
}
-- the locomotive's colour (the shop's old Express Train picture) and the wagons' loads
TrainDisplay.Color = rgb(226, 72, 60)
TrainDisplay.Loads = {
	{ rgb(250, 196, 60), rgb(255, 222, 120), rgb(220, 150, 40) }, -- gold
	{ rgb(150, 110, 230), rgb(196, 160, 255), rgb(120, 200, 230) }, -- amethyst and quartz
}
TrainDisplay.MaxParts = 200

local DECK = rgb(178, 152, 126) -- flagstone (the old Mine Station's)
local DECK_DARK = rgb(146, 122, 102)
-- the old station's colours (Railway's palette)
local C = {
	Steel = rgb(122, 130, 184), -- the Factory Kit's periwinkle
	SteelDark = rgb(58, 60, 72),
	Orange = TrainBuilder.Colors.Corner, -- Kenney's orange collars
	Hazard = rgb(250, 206, 64),
	Roof = rgb(198, 54, 42),
	RoofTrim = rgb(104, 30, 26),
	Lamp = rgb(255, 184, 96),
	Crate = rgb(232, 140, 90),
	Tape = rgb(244, 200, 150),
	Board = rgb(58, 60, 72),
	Text = rgb(255, 210, 96),
}
local SOLID = { CanTouch = false } -- players bump into it, casts a shadow
local SOLID_SMALL = { CanTouch = false, CastShadow = false }
local BUMP = { CanTouch = false, CanQuery = false } -- collides, ignored by queries
local BUMP_SMALL = { CanTouch = false, CanQuery = false, CastShadow = false }
local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false }
local GHOST = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local BLOCKER = { CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }
local NEON = Enum.Material.Neon

-- A named block between two corners of a frame (local coordinates).
local function box(
	parent: Instance,
	name: string,
	frame: CFrame,
	a: Vector3,
	b: Vector3,
	color: Color3,
	material: Enum.Material?,
	props: any
): Part
	local lo = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local hi = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	local p = Geo.block(parent, frame * CFrame.new((lo + hi) / 2), hi - lo, color, material, props)
	p.Name = name
	return p
end

-- A right-angle wedge: the right-angle edge runs through `corner` (frame space) with its two legs
-- along `up` and `back` (perpendicular, their lengths the legs); `thickness` is the width across.
local function triangle(
	parent: Instance,
	name: string,
	frame: CFrame,
	corner: Vector3,
	up: Vector3,
	back: Vector3,
	thickness: number,
	color: Color3,
	props: any
): WedgePart
	local y = frame:VectorToWorldSpace(up.Unit)
	local z = frame:VectorToWorldSpace(-back.Unit)
	local x = y:Cross(z)
	local center = frame:PointToWorldSpace(corner + up / 2 + back / 2)
	local w = Geo.wedge(parent, CFrame.fromMatrix(center, x, y, z), Vector3.new(thickness, up.Magnitude, back.Magnitude), color, nil, props)
	w.Name = name
	return w
end

-- A sign board, the words on both faces (self-lit a little: LightInfluence 0.3).
local function sign(parent: Instance, cf: CFrame, size: Vector3, text: string): Part
	local p = Geo.block(parent, cf, size, C.Board, nil, GHOST)
	p.Name = "Sign"
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, 0.1)
		label.Size = UDim2.fromScale(0.92, 0.8)
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = C.Text
		label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
		label.Parent = gui
	end
	return p
end

--[[
	The Mine Station's shelter (the old Railway.buildStation without anything
	that worked): the platform with its safety edge on the train's side and an
	access ramp on the players' side, six steel posts with orange collars (the
	middle two on the train's side only), the beams, a closed red pitched roof
	on its eave plates, the MINE STATION sign on two posts on the ridge, a lamp
	under the eave at each corner post, one pendant lamp in the middle (the
	display's one PointLight) and four crates at its east end.
]]
local function shelter(m: Model)
	local cfg = TrainDisplay.Shelter
	local S = CFrame.new(cfg.Center)
	local half = cfg.Size / 2
	local deck = cfg.Size.Y
	local base = box(m, "ShelterPlatform", S, Vector3.new(-half.X, 0, -half.Z), Vector3.new(half.X, deck, half.Z), DECK, nil, SOLID)
	box(m, "Edge", S, Vector3.new(-half.X, deck, -half.Z + 0.05), Vector3.new(half.X, deck + 0.06, -half.Z + 0.55), C.Hazard, nil, GHOST)
	triangle(m, "Ramp", S, Vector3.new(0, 0, half.Z), Vector3.new(0, deck, 0), Vector3.new(0, 0, 2.6), half.X * 2, DECK_DARK, SOLID)
	-- the canopy
	local postX, postZ = half.X - 0.4, half.Z - 0.4
	local eave = deck + 6.9
	local posts = {
		Vector3.new(-postX, 0, -postZ),
		Vector3.new(postX, 0, -postZ),
		Vector3.new(-postX, 0, postZ),
		Vector3.new(postX, 0, postZ),
		Vector3.new(-6.8, 0, -postZ),
		Vector3.new(6.8, 0, -postZ),
	}
	for i, p in posts do
		box(
			m,
			"Post",
			S,
			Vector3.new(p.X - 0.35, deck, p.Z - 0.35),
			Vector3.new(p.X + 0.35, eave, p.Z + 0.35),
			C.Steel,
			nil,
			if i <= 4 then BUMP else BUMP_SMALL
		)
		box(
			m,
			"Collar",
			S,
			Vector3.new(p.X - 0.5, eave - 1.2, p.Z - 0.5),
			Vector3.new(p.X + 0.5, eave - 0.7, p.Z + 0.5),
			C.Orange,
			nil,
			GHOST
		)
	end
	for _, z in { -postZ, postZ } do
		box(m, "Beam", S, Vector3.new(-half.X, eave, z - 0.35), Vector3.new(half.X, eave + 0.6, z + 0.35), C.Steel, nil, DECOR)
	end
	box(m, "CrossBeam", S, Vector3.new(-0.25, eave + 0.1, -postZ + 0.35), Vector3.new(0.25, eave + 0.5, postZ - 0.35), C.Steel, nil, GHOST)
	-- the roof: its train side ends over the platform's edge, the players' side overhangs the ramp
	local roofL = half.X + 0.7
	local roofZ0, roofZ1 = -half.Z, half.Z + 0.7
	local ridgeZ = (roofZ0 + roofZ1) / 2
	local plate = eave + 0.6
	box(m, "Eave", S, Vector3.new(-roofL, plate, roofZ0), Vector3.new(roofL, plate + 0.35, roofZ1), C.RoofTrim, nil, DECOR)
	for _, edge in { roofZ0 + 0.1, roofZ1 - 0.1 } do
		triangle(
			m,
			"Roof",
			S,
			Vector3.new(0, plate + 0.35, ridgeZ),
			Vector3.new(0, 1.4, 0),
			Vector3.new(0, 0, edge - ridgeZ),
			roofL * 2 - 0.2,
			C.Roof,
			DECOR
		)
	end
	-- the rooftop sign on two posts (both faces: the ramp and the train's side)
	local ridge = plate + 0.35 + 1.4
	for _, side in { -1, 1 } do
		box(
			m,
			"SignPost",
			S,
			Vector3.new(side * 5.8 - 0.2, ridge - 0.6, ridgeZ - 0.2),
			Vector3.new(side * 5.8 + 0.2, ridge + 0.5, ridgeZ + 0.2),
			C.SteelDark,
			nil,
			GHOST
		)
	end
	local board = sign(m, S * CFrame.new(0, ridge + 1.6, ridgeZ) * CFrame.Angles(0, math.pi, 0), Vector3.new(12, 2.4, 0.35), "MINE STATION")
	board.CastShadow = true
	-- lamps under the eave at the corner posts, and the pendant in the middle under the cross beam
	for i = 1, 4 do
		local p = posts[i]
		local inward = -math.sign(p.Z)
		box(
			m,
			"Lamp",
			S,
			Vector3.new(p.X - 0.3, eave - 0.6, p.Z + inward * 0.35),
			Vector3.new(p.X + 0.3, eave - 0.05, p.Z + inward * 0.95),
			C.Lamp,
			NEON,
			GHOST
		)
	end
	local pendant = S * CFrame.new(0, eave - 0.15, 0)
	local shade = Geo.block(m, pendant * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.5, 1.4, 1.4), C.SteelDark, nil, GHOST)
	shade.Shape = Enum.PartType.Cylinder
	shade.Name = "Shade"
	local bulb = Geo.block(m, pendant * CFrame.new(0, -0.45, 0), Vector3.new(0.7, 0.7, 0.7), C.Lamp, NEON, GHOST)
	bulb.Shape = Enum.PartType.Ball
	bulb.Name = "Bulb"
	local light = Instance.new("PointLight")
	light.Color = C.Lamp
	light.Range = 16
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = bulb
	-- crates at the east end
	for _, c in { { 9.6, 0, -1.1, 0.12 }, { 12.1, 0, -0.8, -0.1 }, { 10.9, 1.2, -0.95, 0.35 }, { 11.4, 0, 1.3, 0.5 } } do
		local cf = S * CFrame.new(c[1], deck + c[2], c[3]) * CFrame.Angles(0, c[4], 0)
		local size = Vector3.new(2.4, 1.2, 2.2)
		Geo.block(m, cf * CFrame.new(0, size.Y / 2, 0), size, C.Crate, nil, SOLID_SMALL).Name = "Crate"
		Geo.block(m, cf * CFrame.new(0, size.Y / 2 + 0.03, 0), Vector3.new(0.7, size.Y, size.Z + 0.06), C.Tape, nil, GHOST).Name = "Tape"
	end
	return base
end

-- Where an attachment is in the world (Lune does not keep WorldPosition up to date).
local function attachmentAt(model: Model, name: string): Vector3?
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			local part = d.Parent :: BasePart
			return (part.CFrame * d.CFrame).Position
		end
	end
	return nil
end

-- An invisible box round a vehicle (its parts don't collide): players walk round the train.
-- (its own box in the vehicle's frame, from every part's corners)
local function blocker(parent: Instance, vehicle: Model)
	local pivot = vehicle:GetPivot()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in vehicle:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = pivot:PointToObjectSpace((d.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
		end
	end
	if lo.X > hi.X then
		return
	end
	local part = Geo.block(parent, pivot * CFrame.new((lo + hi) / 2), hi - lo, DECK, nil, BLOCKER)
	part.Name = "Blocker"
end

function TrainDisplay.build(map: Instance): Model
	local old = map:FindFirstChild("TrainDisplay")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "TrainDisplay"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- the train's platform: a flagstone deck with a darker skirt (no lines on the deck: two would read
	-- as rails), the shelter beside it
	local cfg = TrainDisplay.Platform
	local top = cfg.Center.Y + cfg.Size.Y
	local deck = Geo.block(m, CFrame.new(cfg.Center + Vector3.new(0, cfg.Size.Y / 2, 0)), cfg.Size, DECK, nil, SOLID)
	deck.Name = "Platform"
	m.PrimaryPart = deck
	local skirt = Geo.block(
		m,
		CFrame.new(cfg.Center + Vector3.new(0, cfg.Size.Y / 2 - 0.1, 0)),
		cfg.Size + Vector3.new(0.6, -0.2, 0.6),
		DECK_DARK,
		nil,
		SOLID
	)
	skirt.Name = "Skirt"
	shelter(m)
	-- the train: the locomotive in front (facing -X, the ramp's side), its wagons coupled behind,
	-- the whole train in the platform's middle
	local loco = TrainBuilder.locomotive(TrainDisplay.Color)
	loco.Name = "Locomotive"
	-- (the train stays smooth as it always was, the platform gets the map's studs: StudStyleConfig.SkipTag)
	loco:SetAttribute("NoStuds", true)
	loco.Parent = m
	local wagons: { Model } = {}
	local total = (loco:GetAttribute("Length") :: number?) or 10
	for i, loads in TrainDisplay.Loads do
		local wagon = TrainBuilder.wagon(TrainDisplay.Color, loads)
		wagon.Name = "Wagon" .. i
		wagon:SetAttribute("NoStuds", true)
		wagon.Parent = m
		total += (wagon:GetAttribute("Length") :: number?) or 10
		table.insert(wagons, wagon)
	end
	local front = Vector3.new(cfg.Center.X - total / 2, top, cfg.Center.Z)
	local facing = CFrame.lookAt(front, front + Vector3.new(-1, 0, 0))
	-- (the Root is the bottom middle: the wheels on the deck)
	local length = (loco:GetAttribute("Length") :: number?) or 10
	loco:PivotTo(facing * CFrame.new(0, 0, length / 2))
	blocker(m, loco)
	local previous: Model = loco
	for _, wagon in wagons do
		-- turned like the locomotive, then moved so its front coupler meets the back one before it
		wagon:PivotTo(facing.Rotation + wagon:GetPivot().Position)
		local back = attachmentAt(previous, "CouplerBack")
		local coupler = attachmentAt(wagon, "CouplerFront")
		if back and coupler then
			wagon:PivotTo(wagon:GetPivot() + (back - coupler))
		end
		blocker(m, wagon)
		previous = wagon
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = map
	return m
end

return TrainDisplay
