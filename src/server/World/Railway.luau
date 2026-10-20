--[[
	The ore trains' railway (design v2, docs/plans/STEP2_PLAN.md), built into
	Workspace.Map.Railway from TrainConfig in the Kenney Train Kit / Factory
	Kit look (TrainBuilder's lavender rails on salmon sleepers, periwinkle
	steel with orange trim):

	  QuarryLine   the quarry track (TrainConfig.QuarryLine) on the quarry
	               floor, from the west to the east wall portal
	  MineStation  model tagged "TrainStation" at TrainConfig.Station: a
	               flagstone platform with a safety edge and an access ramp,
	               a red pitched canopy on periwinkle posts (open over the
	               hopper) with a rooftop "MINE STATION" sign, the big funnel
	               hopper (Kenney hopper-square: tub with a warm neon rim
	               strip, light band, funnel, throat, legs) over the invisible
	               `Intake` (tag "TrainHopper", HopperSize, its bottom at
	               Station.Hopper), a bucket elevator beside it on the track
	               side whose head feeds an angled loading chute (the spout
	               sits above the wagons at QuarryStop), a lever console at
	               the `PromptPoint` attachment, the `TrainPoint` attachment
	               at QuarryStop, neon lamps and one PointLight (the pendant
	               over the hopper), crates and a short straight siding off
	               the main line that ends in a buffer stop past the
	               platform's end
	  Portals      four tunnel portals with a dark mouth (black neon) in a
	               timber frame (lanterns on the posts, knee braces) under a
	               steel lintel with an orange plate and a signal lamp
	               (Railway.portalMouths: the mouth planes):
	               West/East where the quarry line meets the quarry walls, on
	               a light stone buttress (the mouth stands PortalInset in
	               front of the wall, so the wall's foot boulders stay behind
	               it), SouthWest/SouthEast at (+-166, 0, SouthPortalZ) facing
	               north in a rock hill (cheek rocks, a stone brow under a
	               grass crest with rock outcrops, three stone tiers stepping
	               down to the south, each under a grass slope with a stone
	               ledge between them, grass wing slopes beside the track)
	               that keeps between the town's rail strip (x 160) and the
	               island rim (x 171.7)
	  CoastWest    the coastal lines (TrainConfig.CoastWest/CoastEast) from the
	  CoastEast    south portal north to a buffer stop just past BufferZ,
	               behind every plot's yard train stop: both rails run past
	               each stop's platform (BaseLayout.TrainStop keeps 3 studs
	               from the centerline), the sleeper ends on the platform side
	               give way under it, so nothing cuts into a yard
	  MineLift_*   the Mine Lifts (TrainConfig.Lifts: "MineLift_" .. Id,
	               tagged "MineLift", attribute LiftId): a periwinkle headframe with orange
	               collars on a steel base, a low funnel hopper (rim LiftRim)
	               with a warm glowing floor over the invisible `Intake` (tag
	               "TrainHopper", attribute LiftId), the cage parked under the
	               crossbeams on a cable that runs up into the cave ceiling
	               with a lamp under it (the lift's one PointLight), a "LIFT"
	               sign (self-lit text) under a front header beam with a lamp
	               strip, a warning lamp and the `PromptPoint` attachment in
	               front

	The yards' `RailwayPlaceholder` track pieces (PlotBuilder) are removed:
	the through line replaces them (their buffer stops stood on the line).

	Track: straight runs of at most RunLength studs (two rail parts per run,
	split only where a platform would cover a rail) and a sleeper every ~6 studs
	(shortened where a platform or the station's elevator stands beside it); all
	track parts are anchored, non-colliding and cast no shadow (players walk
	over the line on the ground). Trains stand on the rails when their Root
	is TrainBuilder.RailTop above the line point. Nothing but the rails,
	sleepers and the portal mouths enters the trains' clearance (Clearance)
	between the portal mouths.

	Pure and deterministic (only Instance creation, a fixed-seed Rng for
	stone shades), so Lune tests, the bake and previews can build it.
	Streaming: the station, lifts and portals stream atomically; the portals
	keep a low-detail streaming mesh when far away.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local Rng = require(Shared.Util.Rng)
local BaseLayout = require(Shared.Config.BaseLayout)
local TrainConfig = require(Shared.Config.TrainConfig)
local WorldLayout = require(Shared.Config.WorldLayout)

local Railway = {}

Railway.MaxParts = 600 -- the whole railway (tests/Railway.spec.luau)
Railway.RunLength = 24 -- longest rail part
-- Quarry portals: the mouth stands this far in front of the line's end, and
-- the coastal buffer stops' face this far past theirs (shared with the
-- client, which hides and stops the trains there; see Railway.portalMouths).
Railway.PortalInset = TrainConfig.PortalInset
Railway.BufferGap = TrainConfig.BufferGap
-- The space the trains need around a line (TrainBuilder: steam cylinders
-- +-3.43, chimney top 9.31 above the line point); only rails, sleepers and
-- the portal mouths may enter it.
Railway.Clearance = { HalfWidth = 3.6, Bottom = 1.5, Top = 9.6 }
Railway.LiftRim = 3.2 -- the Mine Lifts' tub rim above the cave floor (the intake box reaches higher)
Railway.StationTag = "TrainStation"
Railway.HopperTag = "TrainHopper"
Railway.LiftTag = "MineLift"

export type Rect = { Min: Vector3, Max: Vector3 } -- world XZ (Y ignored)
type Props = { [string]: any }

local rgb = Color3.fromRGB
local TC = TrainBuilder.Colors

-- (the lobby's stone, grass, flagstone, roof and wood colours are copied
-- from Lobby/Style's palette, so the railway does not depend on the lobby)
local C = {
	Steel = rgb(122, 130, 184), -- the Factory Kit's periwinkle (as PlotBuilder's machine housings)
	SteelLight = rgb(160, 168, 212),
	SteelDark = rgb(58, 60, 72),
	Orange = TC.Corner, -- Kenney's orange collars and buffers
	Hazard = rgb(250, 206, 64), -- the safety edge of the yards' train stops
	Deck = rgb(178, 152, 126), -- flagstone
	DeckDark = rgb(146, 122, 102),
	Roof = rgb(198, 54, 42),
	RoofTrim = rgb(104, 30, 26),
	Stone = rgb(114, 122, 140),
	StoneLight = rgb(160, 167, 180),
	Grass = rgb(104, 178, 62),
	GrassDark = rgb(66, 138, 52),
	Interior = TC.Interior,
	Lamp = rgb(255, 184, 96),
	Mouth = rgb(6, 6, 9),
	Timber = rgb(138, 90, 54),
	TimberDark = rgb(88, 56, 36),
	Crate = rgb(232, 140, 90), -- Kenney box-large
	Tape = rgb(244, 200, 150),
	Board = rgb(58, 60, 72),
	Text = rgb(255, 210, 96),
	Screen = rgb(40, 150, 110), -- deep, so the neon stays a screen and not a lamp
	Glow = rgb(214, 110, 28), -- the lifts' hopper floor: a warm "drop it here" glow in the dark caves
	Lever = rgb(214, 56, 50),
}

local TRACK: Props = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local SOLID: Props = { CanTouch = false } -- players and items bump into it, casts a shadow
local SOLID_SMALL: Props = { CanTouch = false, CastShadow = false }
local BUMP: Props = { CanTouch = false, CanQuery = false } -- collides, ignored by queries
local BUMP_SMALL: Props = { CanTouch = false, CanQuery = false, CastShadow = false }
local DECOR: Props = { CanCollide = false, CanTouch = false, CanQuery = false }
local GHOST: Props = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }

local NEON = Enum.Material.Neon
local WOOD = Enum.Material.Wood
local ALONG_X = CFrame.new() -- Roblox cylinders run along X
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

---------------------------------------------------------------- helpers

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Props): Part
	local p = Geo.block(parent, cf, size, color, material, props)
	p.Name = name
	return p
end

-- Block between two corners of a frame (local coordinates).
local function box(
	parent: Instance,
	name: string,
	frame: CFrame,
	a: Vector3,
	b: Vector3,
	color: Color3,
	material: Enum.Material?,
	props: Props
): Part
	local lo = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local hi = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return block(parent, name, frame * CFrame.new((lo + hi) / 2), hi - lo, color, material, props)
end

-- Cylinder whose axis is the X axis of `cf` turned by `axis` (ALONG_X/Y/Z).
local function cyl(
	parent: Instance,
	name: string,
	cf: CFrame,
	axis: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Props
): Part
	local p = block(parent, name, cf * axis, Vector3.new(length, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(
	parent: Instance,
	name: string,
	cf: CFrame,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Props
): Part
	local p = block(parent, name, cf, Vector3.new(diameter, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Ball
	return p
end

--[[
	A right-angle wedge: the right-angle edge runs through `corner` (frame
	space) with its two legs along `up` and `back` (perpendicular vectors whose
	lengths are the legs); `thickness` is the width across both.
]]
local function triangle(
	parent: Instance,
	name: string,
	frame: CFrame,
	corner: Vector3,
	up: Vector3,
	back: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	props: Props
): WedgePart
	local y = frame:VectorToWorldSpace(up.Unit)
	local z = frame:VectorToWorldSpace(-back.Unit)
	local x = y:Cross(z)
	local center = frame:PointToWorldSpace(corner + up / 2 + back / 2)
	local w =
		Geo.wedge(parent, CFrame.fromMatrix(center, x, y, z), Vector3.new(thickness, up.Magnitude, back.Magnitude), color, material, props)
	w.Name = name
	return w
end

local function attach(part: BasePart, name: string, world: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = part.CFrame:ToObjectSpace(CFrame.new(world))
	a.Parent = part
	return a
end

-- A sign board: the text on its front face (the frame's look direction), and
-- on the back too when `twoSided`. `lightInfluence` (default 0.3): 0 keeps
-- the text its own colour under a cave's tinted ambient.
local function sign(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	text: string,
	twoSided: boolean,
	lightInfluence: number?
): Part
	local p = block(parent, name, cf, size, C.Board, nil, GHOST)
	local faces: { Enum.NormalId } = { Enum.NormalId.Front }
	if twoSided then
		table.insert(faces, Enum.NormalId.Back)
	end
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = lightInfluence or 0.3
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

-- Streams in as one piece; `lod` keeps a low-detail mesh in view when far away.
-- (pcall'd: a runtime rebuild may not write these.)
local function streaming(m: Model, lod: boolean)
	local target: any = m
	pcall(function()
		target.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	if lod then
		pcall(function()
			target.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
		end)
	end
end

local function light(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
	return l
end

---------------------------------------------------------------- track

local GAUGE = TrainBuilder.Gauge
local RAIL_TOP = TrainBuilder.RailTop
local RAIL_W = 0.85
local RAIL_BOTTOM = 0.45
local SLEEPER_HALF = 4.2
local SLEEPER_TOP = 0.45
local SLEEPER_DEPTH = 2.4
local GAP = 0.05 -- clearance to a platform the track gives way to
local MIN_RAIL = 0.5
local MIN_SLEEPER = 3

-- A rect's extent in a segment frame: across (X) and along the line (s = -Z).
local function extentIn(frame: CFrame, rect: Rect): (number, number, number, number)
	local x0, x1, s0, s1 = math.huge, -math.huge, math.huge, -math.huge
	for _, x in { rect.Min.X, rect.Max.X } do
		for _, z in { rect.Min.Z, rect.Max.Z } do
			local p = frame:PointToObjectSpace(Vector3.new(x, frame.Position.Y, z))
			x0, x1 = math.min(x0, p.X), math.max(x1, p.X)
			s0, s1 = math.min(s0, -p.Z), math.max(s1, -p.Z)
		end
	end
	return x0, x1, s0, s1
end

-- [a, b] minus the blocked intervals.
local function subtract(a: number, b: number, blocked: { { number } }): { { number } }
	local pieces = { { a, b } }
	for _, cut in blocked do
		local kept = {}
		for _, piece in pieces do
			if cut[2] <= piece[1] or cut[1] >= piece[2] then
				table.insert(kept, piece)
			else
				if cut[1] > piece[1] then
					table.insert(kept, { piece[1], cut[1] })
				end
				if cut[2] < piece[2] then
					table.insert(kept, { cut[2], piece[2] })
				end
			end
		end
		pieces = kept
	end
	return pieces
end

type TrackOpts = {
	Clips: { Rect }?, -- platforms the track gives way to
	Drop: number?, -- lower the whole track (a siding under its main line)
	SleepersFrom: number?, -- no sleepers in the first studs (where a siding leaves the main line)
}

-- One straight segment of track from a to b (ground points).
local function segment(parent: Instance, a: Vector3, b: Vector3, opts: TrackOpts, sleeperStart: number)
	local length = (b - a).Magnitude
	if length < MIN_RAIL then
		return
	end
	local frame = CFrame.lookAt(a, b)
	local drop = opts.Drop or 0
	local extents: { { number } } = {}
	local clips: { Rect } = opts.Clips or {}
	for _, rect in clips do
		local x0, x1, s0, s1 = extentIn(frame, rect)
		if s1 > 0 and s0 < length then
			table.insert(extents, { x0, x1, s0, s1 })
		end
	end

	-- rails: runs of at most RunLength, cut where a platform covers them
	local runs = math.max(1, math.ceil(length / Railway.RunLength - 1e-6))
	local railY = (RAIL_BOTTOM + RAIL_TOP) / 2 - drop
	for _, side in { -1, 1 } do
		local x = side * GAUGE / 2
		local blocked: { { number } } = {}
		for _, e in extents do
			if e[1] < x + RAIL_W / 2 + GAP and e[2] > x - RAIL_W / 2 - GAP then
				table.insert(blocked, { e[3] - GAP, e[4] + GAP })
			end
		end
		for i = 1, runs do
			for _, piece in subtract((i - 1) * length / runs, i * length / runs, blocked) do
				local l = piece[2] - piece[1]
				if l >= MIN_RAIL then
					block(
						parent,
						"Rail",
						frame * CFrame.new(x, railY, -(piece[1] + piece[2]) / 2),
						Vector3.new(RAIL_W, RAIL_TOP - RAIL_BOTTOM, l),
						TC.Rail,
						nil,
						TRACK
					)
				end
			end
		end
	end

	-- sleepers every ~SleeperSpacing; a platform shortens them from its side
	local count = math.max(1, math.floor(length / TrainBuilder.SleeperSpacing + 0.5))
	local step = length / count
	local depth = math.min(SLEEPER_DEPTH, step - 0.2)
	for i = 1, count do
		local s = (i - 0.5) * step
		if sleeperStart + s >= (opts.SleepersFrom or 0) then
			local x0, x1 = -SLEEPER_HALF, SLEEPER_HALF
			local keep = true
			for _, e in extents do
				if e[3] < s + depth / 2 + GAP and e[4] > s - depth / 2 - GAP and e[1] < x1 + GAP and e[2] > x0 - GAP then
					if e[1] <= x0 then
						x0 = e[2] + GAP
					elseif e[2] >= x1 then
						x1 = e[1] - GAP
					else
						keep = false
					end
				end
			end
			if keep and x1 - x0 >= MIN_SLEEPER then
				block(
					parent,
					"Sleeper",
					frame * CFrame.new((x0 + x1) / 2, SLEEPER_TOP / 2 - drop, -s),
					Vector3.new(x1 - x0, SLEEPER_TOP, depth),
					TC.Sleeper,
					WOOD,
					TRACK
				)
			end
		end
	end
end

--[[
	Track along a polyline; the first and last points move along their
	segment by `startTrim` / `endTrim` studs (negative = longer).
]]
local function track(parent: Instance, name: string, points: { Vector3 }, startTrim: number, endTrim: number, opts: TrackOpts): Model
	local m = model(name, parent)
	local pts = table.clone(points)
	local n = #pts
	pts[1] = pts[1] + (pts[2] - pts[1]).Unit * startTrim
	pts[n] = pts[n] - (pts[n] - pts[n - 1]).Unit * endTrim
	local travelled = 0
	for i = 1, n - 1 do
		segment(m, pts[i], pts[i + 1], opts, travelled)
		travelled += (pts[i + 1] - pts[i]).Magnitude
	end
	return m
end

--[[
	Buffer stop at the end of a track: `cf` = the ground point under the
	beam's face, looking at the incoming trains. A dark red beam at coupler
	height on two sloped steel struts along the rails, two orange buffers.
]]
local BUFFER_DEPTH = 3.4 -- from the beam's face to the struts' feet (the track runs on under them)
local BUFFER_HALF = 2.9 -- the beam's half length across the track
local SIDING_DROP = 0.06 -- a siding's track under its main line's where they cross
local function bufferStop(parent: Instance, cf: CFrame): Model
	local m = model("BufferStop", parent)
	local y = RAIL_TOP + TrainBuilder.CouplerHeight
	box(m, "Beam", cf, Vector3.new(-BUFFER_HALF, y - 0.6, 0), Vector3.new(BUFFER_HALF, y + 0.6, 0.8), TC.Beam, nil, BUMP)
	for _, side in { -1, 1 } do
		cyl(m, "Buffer", cf * CFrame.new(side * 2, y, -0.3), ALONG_Z, 0.6, 0.95, C.Orange, nil, GHOST)
		triangle(
			m,
			"Strut",
			cf,
			Vector3.new(side * GAUGE / 2, 0, 0.8),
			Vector3.new(0, y + 0.6, 0),
			Vector3.new(0, 0, BUFFER_DEPTH - 0.8),
			0.6,
			C.SteelDark,
			nil,
			BUMP_SMALL
		)
	end
	return m
end

---------------------------------------------------------------- portals

local function portalModel(parent: Instance, name: string): Model
	local m = model(name, parent)
	streaming(m, true)
	return m
end

--[[
	Timber portal frame with a black mouth. `cf` = the mouth face's ground
	center, looking out of the tunnel (local +Z runs into the hill).
	`half` = the frame's outer half width, `mouthW` = the mouth's width.
	Returns the lintel's top height.
]]
local MOUTH_W, MOUTH_H, MOUTH_D = 8.6, 11.4, 1.2
local LINTEL = 1.5
local function portalFrame(m: Model, cf: CFrame, half: number, mouthW: number): number
	local mouth = box(m, "Mouth", cf, Vector3.new(-mouthW / 2, 0, 0), Vector3.new(mouthW / 2, MOUTH_H, MOUTH_D), C.Mouth, NEON, SOLID_SMALL)
	m.PrimaryPart = mouth
	local postW = half - mouthW / 2
	local postX = mouthW / 2 + postW / 2
	local top = MOUTH_H
	for _, side in { -1, 1 } do
		box(
			m,
			"Post",
			cf,
			Vector3.new(side * (postX - postW / 2), 0, -0.9),
			Vector3.new(side * (postX + postW / 2), top, 0.3),
			C.Timber,
			WOOD,
			BUMP
		)
		box(
			m,
			"Foot",
			cf,
			Vector3.new(side * (postX - postW / 2 - 0.2), 0, -1.1),
			Vector3.new(side * (postX + postW / 2 + 0.2), 0.8, 0.5),
			C.SteelDark,
			nil,
			BUMP_SMALL
		)
		-- a lantern on the post's face
		box(m, "Lantern", cf, Vector3.new(side * postX - 0.3, 6.6, -1.4), Vector3.new(side * postX + 0.3, 7.4, -0.9), C.Lamp, NEON, GHOST)
		-- knee brace in the upper inner corner
		triangle(
			m,
			"Brace",
			cf,
			Vector3.new(side * mouthW / 2, top, -0.3),
			Vector3.new(0, -1.7, 0),
			Vector3.new(-side * 1.7, 0, 0),
			0.7,
			C.TimberDark,
			WOOD,
			GHOST
		)
	end
	-- steel lintel (a little wider than the frame, so no rock face lines up
	-- with its ends) with an orange plate and a signal lamp on its front edge;
	-- the rock above it starts behind it (local z >= 0.55)
	local lintelTop = top + LINTEL
	box(m, "Lintel", cf, Vector3.new(-half - 0.25, top, -1.1), Vector3.new(half + 0.25, lintelTop, 0.5), C.Steel, nil, BUMP)
	box(m, "Plate", cf, Vector3.new(-half + 1.6, top + 0.35, -1.22), Vector3.new(half - 1.6, top + 1.15, -1.1), C.Orange, nil, GHOST)
	box(m, "Lamp", cf, Vector3.new(-0.4, lintelTop, -1.0), Vector3.new(0.4, lintelTop + 0.6, -0.4), C.Lamp, NEON, GHOST)
	return lintelTop
end

-- Quarry wall portal: the frame on a stone buttress against the wall.
local function quarryPortal(parent: Instance, name: string, cf: CFrame, rng: Rng.Rng)
	local m = portalModel(parent, name)
	local half = 5.55
	local top = portalFrame(m, cf, half, MOUTH_W)
	-- (a lighter stone than the wall's, so the portal stands out of its shadow)
	local function stone(): Color3
		return Geo.vary(rng:pick({ C.Stone, C.Stone, C.StoneLight }), rng, 0.05)
	end
	box(m, "Rock", cf, Vector3.new(-8, 0, MOUTH_D), Vector3.new(8, top + 3.2, 7.5), stone(), nil, SOLID)
	for _, side in { -1, 1 } do
		box(m, "Rock", cf, Vector3.new(side * (half - 0.1), 0, -1.4), Vector3.new(side * 9.2, 8.6, 3), stone(), nil, SOLID)
		box(m, "Rock", cf, Vector3.new(side * (half + 0.6), 8.6, -0.4), Vector3.new(side * 8.4, top - 0.6, 2.6), stone(), nil, SOLID)
	end
	-- the rock over the lintel: behind it, a step under the buttress top
	box(m, "Rock", cf, Vector3.new(-7.4, top + 0.06, 0.55), Vector3.new(7.4, top + 2.8, 3), stone(), nil, SOLID)
end

--[[
	South portal: the frame set into a rock hill that keeps between the town's
	rail strip (|x| 160) and the island rim (|x| 171.7), so it gains its mass
	in height: cheek rocks either side of the frame, a stone brow over the
	lintel under a grass crest with rock outcrops, then three stone tiers
	stepping down to the south coast, each under a grass slope, with a stone
	ledge (a lip a little proud of the tier) where one tier steps down to the
	next, a rough rock block on each flank and grass wing slopes beside the
	track in front (low enough to leave the post lanterns in view).
]]
Railway.SouthHill = { HalfWidth = 5.65, Depth = 23.4 } -- local x / z extent of the hill behind the mouth
local function southPortal(parent: Instance, name: string, cf: CFrame, rng: Rng.Rng)
	local m = portalModel(parent, name)
	local half = 4.95
	local top = portalFrame(m, cf, half, 8.2)
	local W = Railway.SouthHill.HalfWidth
	-- light stone (the north face is in the evening shadow), one grass shade
	local function stone(): Color3
		return Geo.vary(rng:pick({ C.StoneLight, C.StoneLight, C.Stone:Lerp(C.StoneLight, 0.6) }), rng, 0.04)
	end
	local grass = Geo.vary(C.Grass, rng, 0.03)
	local crest = top + 1.5
	local slopeZ = 3.2 -- the tiers start here (local z)
	local depth = Railway.SouthHill.Depth -- where the last slope meets the ground
	-- core behind the mouth and the brow over the lintel, under a grass crest
	box(m, "Rock", cf, Vector3.new(-5.45, 0, MOUTH_D), Vector3.new(5.45, top + 0.06, slopeZ), stone(), nil, SOLID)
	box(m, "Brow", cf, Vector3.new(-W, top + 0.06, 0.55), Vector3.new(W, crest, slopeZ), stone(), nil, SOLID)
	box(m, "Crest", cf, Vector3.new(-5.3, crest, 0.7), Vector3.new(5.3, crest + 0.6, slopeZ), grass, nil, SOLID_SMALL)
	local high = crest + 0.6
	-- three tiers: a stone body (its top = the ledge it steps down to) under a
	-- grass slope from `y0` at its front down to `y1`, which leaves the
	-- ledge's flat stone strip (`ledge` deep) before the next tier's slope
	-- starts below it; each tier a little narrower than the one in front
	type Tier = { z0: number, z1: number, y0: number, y1: number, ledge: number, w: number }
	local tiers: { Tier } = {
		{ z0 = slopeZ, z1 = 10, y0 = high, y1 = 10, ledge = 1.8, w = 5.45 },
		{ z0 = 10, z1 = 16.6, y0 = 8.4, y1 = 5.6, ledge = 2, w = 5.15 },
		{ z0 = 16.6, z1 = depth, y0 = 4.2, y1 = 0, ledge = 0, w = 4.85 },
	}
	for i, t in tiers do
		local slopeEnd = t.z1 - t.ledge
		if t.y1 > 0 then
			box(m, "Tier", cf, Vector3.new(-t.w, 0, t.z0), Vector3.new(t.w, t.y1, t.z1), stone(), nil, SOLID)
			-- the ledge's lip, proud of the tier at its sides and back
			box(
				m,
				"Ledge",
				cf,
				Vector3.new(-t.w - 0.15, t.y1 - 0.4, slopeEnd - 0.2),
				Vector3.new(t.w + 0.15, t.y1 + 0.15, t.z1 + 0.25),
				Geo.vary(C.StoneLight, rng, 0.03),
				nil,
				SOLID
			)
		end
		triangle(
			m,
			"Slope",
			cf,
			Vector3.new(0, t.y1, t.z0),
			Vector3.new(0, t.y0 - t.y1, 0),
			Vector3.new(0, 0, slopeEnd - t.z0),
			(t.w - 0.15) * 2,
			if i == 2 then Geo.vary(C.Grass:Lerp(C.GrassDark, 0.35), rng, 0.03) else grass,
			nil,
			SOLID
		)
	end
	local function groundAt(z: number): number
		for _, t in tiers do
			local slopeEnd = t.z1 - t.ledge
			if z <= slopeEnd then
				return t.y1 + (t.y0 - t.y1) * math.clamp((slopeEnd - z) / (slopeEnd - t.z0), 0, 1)
			elseif z <= t.z1 then
				return t.y1
			end
		end
		return 0
	end
	-- rock outcrops on the crest, the first ledge and the lowest slope
	local outcrops = {
		{ x = -2.2, z = 2.4, size = Vector3.new(3.8, 1.7, 2.6) },
		{ x = 2.2, z = 9.1, size = Vector3.new(2.8, 2.3, 2.2) },
		{ x = -1.6, z = 18.8, size = Vector3.new(2.6, 2, 2.4) },
	}
	for _, o in outcrops do
		Geo.rock(m, cf * CFrame.new(o.x, groundAt(o.z) - 0.4, o.z), o.size, stone(), rng, nil, SOLID_SMALL)
	end
	for _, side in { -1, 1 } do
		-- cheek rocks either side of the frame, set a little forward
		local cheekTop = if side > 0 then 10.4 else 9.6
		box(m, "Cheek", cf, Vector3.new(side * 4.85, 0, -1.6), Vector3.new(side * W, cheekTop, slopeZ), stone(), nil, SOLID)
		-- a grass wing slope beside the track, down from the cheek to the
		-- ground (under the post lanterns, y 6.6)
		triangle(
			m,
			"Wing",
			cf,
			Vector3.new(side * 5.075, 0, -1.6),
			Vector3.new(0, 6.2, 0),
			Vector3.new(0, 0, -6),
			1.15,
			grass,
			nil,
			SOLID_SMALL
		)
		-- a rough rock block on the flank of the second tier
		local size = Vector3.new(1.6, 6.6 + side * 0.4, 4.4)
		local at = cf * CFrame.new(side * 4.45, size.Y / 2 - 0.1, 12.4 + side * 0.6) * CFrame.Angles(0, 0.06 * side, -0.04 * side)
		block(m, "Rock", at, size, stone(), nil, SOLID)
	end
	-- bushes on the slopes
	local bushes = { { 2.6, 5.4, 1.9 }, { -2.2, 12.2, 2.2 }, { 2.0, 20.4, 1.8 } }
	for i, b in bushes do
		local s = Vector3.new(b[3], b[3] * 0.7, b[3] * 0.85)
		block(
			m,
			"Bush",
			cf * CFrame.new(b[1], groundAt(b[2]) + s.Y / 2 - 0.35, b[2]) * CFrame.Angles(0, 0.5 * i, 0),
			s,
			Geo.vary(C.GrassDark, rng, 0.05),
			nil,
			GHOST
		)
	end
end

-- The four tunnel mouths: the mouth face's ground center, looking out of the
-- tunnel (the client hides a car once it passes this plane going in).
function Railway.portalMouths(): { [string]: CFrame }
	local q = TrainConfig.QuarryLine
	local inwardWest = (q[2] - q[1]).Unit
	local inwardEast = (q[#q - 1] - q[#q]).Unit
	local west = q[1] + inwardWest * Railway.PortalInset
	local east = q[#q] + inwardEast * Railway.PortalInset
	local mouths: { [string]: CFrame } = {
		West = CFrame.lookAt(west, west + inwardWest),
		East = CFrame.lookAt(east, east + inwardEast),
	}
	local coasts: { [string]: { Vector3 } } = { SouthWest = TrainConfig.CoastWest, SouthEast = TrainConfig.CoastEast }
	for name, line in coasts do
		local out = (line[2] - line[1]).Unit
		mouths[name] = CFrame.lookAt(line[1], line[1] + out)
	end
	return mouths
end

---------------------------------------------------------------- Mine Station

--[[
	Kenney hopper-square on short legs: tub walls, a lighter band, a dark
	floor and dark liners inside the tub (a neon `glow` floor in the caves), a
	four-sided funnel and a throat. `cf` = the ground under the hopper (the
	deck top), openX/openZ = the tub's inner half size (the intake box's), `rim`
	= the rim height above `cf`. The tub collides (items fall into it).
	opts: Throat (half size), Tub/Band/Funnel heights (a low hopper squats),
	Glow (a neon floor), RimGlow (a thin neon strip along the rim, so the
	opening reads from afar).
]]
type HopperOpts = { Throat: number, Tub: number?, Band: number?, Funnel: number?, Glow: Color3?, RimGlow: Color3? }
local function hopper(m: Model, cf: CFrame, openX: number, openZ: number, rim: number, opts: HopperOpts)
	local wall = 0.4
	local tubH, bandH, funnelH = opts.Tub or 1.4, opts.Band or 0.6, opts.Funnel or 1.4
	local throat, glow = opts.Throat, opts.Glow
	local tub0 = rim - tubH
	local band0 = tub0 - bandH
	local funnel0 = band0 - funnelH
	local ox, oz = openX + wall / 2, openZ + wall / 2 -- wall centers: the inner faces stand on the box edges
	for _, side in { -1, 1 } do
		box(
			m,
			"Tub",
			cf,
			Vector3.new(-ox - wall / 2, tub0, side * oz - wall / 2),
			Vector3.new(ox + wall / 2, rim, side * oz + wall / 2),
			C.Steel,
			nil,
			BUMP
		)
		box(
			m,
			"Tub",
			cf,
			Vector3.new(side * ox - wall / 2, tub0, -oz + wall / 2),
			Vector3.new(side * ox + wall / 2, rim, oz - wall / 2),
			C.Steel,
			nil,
			BUMP_SMALL
		)
	end
	local bx, bz = ox + wall / 2 + 0.2, oz + wall / 2 + 0.2
	box(m, "Band", cf, Vector3.new(-bx, band0, -bz), Vector3.new(bx, tub0, bz), C.SteelLight, nil, BUMP)
	box(
		m,
		"Inside",
		cf,
		Vector3.new(-ox + wall / 2, tub0, -oz + wall / 2),
		Vector3.new(ox - wall / 2, tub0 + 0.08, oz - wall / 2),
		glow or C.Interior,
		if glow then NEON else nil,
		GHOST
	)
	-- dark liners on the tub's inner faces (below a periwinkle lip), so the
	-- opening reads as a deep funnel and not a shallow tray
	local ix, iz, lip = ox - wall / 2, oz - wall / 2, rim - 0.25
	for _, side in { -1, 1 } do
		box(m, "Liner", cf, Vector3.new(-ix, tub0, side * (iz - 0.06)), Vector3.new(ix, lip, side * iz), C.Interior, nil, GHOST)
		box(
			m,
			"Liner",
			cf,
			Vector3.new(side * (ix - 0.06), tub0, -iz + 0.06),
			Vector3.new(side * ix, lip, iz - 0.06),
			C.Interior,
			nil,
			GHOST
		)
	end
	if opts.RimGlow then
		-- a thin neon strip along the middle of each tub wall's top
		local w = 0.16
		for _, side in { -1, 1 } do
			box(
				m,
				"RimGlow",
				cf,
				Vector3.new(-ox - w / 2, rim, side * oz - w / 2),
				Vector3.new(ox + w / 2, rim + 0.08, side * oz + w / 2),
				opts.RimGlow,
				NEON,
				GHOST
			)
			box(
				m,
				"RimGlow",
				cf,
				Vector3.new(side * ox - w / 2, rim, -oz + w / 2),
				Vector3.new(side * ox + w / 2, rim + 0.08, oz - w / 2),
				opts.RimGlow,
				NEON,
				GHOST
			)
		end
	end
	-- funnel: one wedge per side, flat on top, its slope running in to the throat
	local fx, fz = bx - 0.2, bz - 0.2
	for _, side in { -1, 1 } do
		triangle(
			m,
			"Funnel",
			cf,
			Vector3.new(0, band0, side * throat),
			Vector3.new(0, -funnelH, 0),
			Vector3.new(0, 0, side * (fz - throat)),
			fx * 2,
			C.Steel,
			nil,
			BUMP_SMALL
		)
		triangle(
			m,
			"Funnel",
			cf,
			Vector3.new(side * throat, band0, 0),
			Vector3.new(0, -funnelH, 0),
			Vector3.new(side * (fx - throat), 0, 0),
			fz * 2,
			C.Steel,
			nil,
			BUMP_SMALL
		)
	end
	box(m, "Throat", cf, Vector3.new(-throat, 0, -throat), Vector3.new(throat, funnel0, throat), C.SteelDark, nil, BUMP_SMALL)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (fx - 0.25), sz * (fz - 0.25)
			box(m, "Leg", cf, Vector3.new(x - 0.25, 0, z - 0.25), Vector3.new(x + 0.25, band0, z + 0.25), C.SteelDark, nil, BUMP_SMALL)
		end
	end
end

-- Kenney box-large: an orange box with a light tape band over the top.
local function crate(m: Model, cf: CFrame)
	local size = Vector3.new(2.4, 1.2, 2.2)
	block(m, "Crate", cf * CFrame.new(0, size.Y / 2, 0), size, C.Crate, nil, SOLID_SMALL)
	block(m, "Tape", cf * CFrame.new(0, size.Y / 2 + 0.03, 0), Vector3.new(0.7, size.Y, size.Z + 0.06), C.Tape, nil, GHOST)
end

--[[
	The bucket elevator beside the hopper (station frame: its x, and the
	casing's z from the track side to the platform), and its world footprint
	with the orange foot band, which the quarry line's sleepers give way to.
]]
local ELEVATOR_HALF, ELEVATOR_BAND = 1.2, 0.15
local function elevatorAt(): (number, number, number)
	local cfg = TrainConfig.Station
	local halfZ = cfg.Platform.Size.Z / 2
	return cfg.Hopper.X - cfg.Platform.Center.X + 7.4, -halfZ - 2.3, -halfZ - 0.1
end

local function elevatorRect(): Rect
	local x, z0, z1 = elevatorAt()
	local c = TrainConfig.Station.Platform.Center
	local h = ELEVATOR_HALF + ELEVATOR_BAND
	return {
		Min = Vector3.new(c.X + x - h, 0, c.Z + z0 - ELEVATOR_BAND),
		Max = Vector3.new(c.X + x + h, 0, c.Z + z1 + ELEVATOR_BAND),
	}
end

local function buildStation(parent: Instance, rng: Rng.Rng): Model
	local cfg = TrainConfig.Station
	local m = model("MineStation", parent)
	m:AddTag(Railway.StationTag)
	streaming(m, false)
	-- station frame: the platform's ground center, axes = world axes (the track
	-- lies at -Z, the ramp and the players' side at +Z)
	local center = cfg.Platform.Center
	local S = CFrame.new(center)
	local half = cfg.Platform.Size / 2
	local deck = cfg.Platform.Size.Y
	local trackZ = TrainConfig.QuarryStop.Z - center.Z

	-- platform, safety edge on the track side, access ramp on the players' side
	local platform = box(m, "Platform", S, Vector3.new(-half.X, 0, -half.Z), Vector3.new(half.X, deck, half.Z), C.Deck, nil, SOLID)
	m.PrimaryPart = platform
	box(m, "Edge", S, Vector3.new(-half.X, deck, -half.Z + 0.05), Vector3.new(half.X, deck + 0.06, -half.Z + 0.55), C.Hazard, nil, GHOST)
	triangle(m, "Ramp", S, Vector3.new(0, 0, half.Z), Vector3.new(0, deck, 0), Vector3.new(0, 0, 2.6), half.X * 2, C.DeckDark, nil, SOLID)

	-- canopy: posts (the middle ones on the track side only, the players' side
	-- stays open), beams, eave plates and a red pitched roof with an opening
	-- over the hopper (so the hopper reads from the ramp and from high
	-- cameras; a cross beam over the opening carries the pendant lamp)
	local hopperAt = cfg.Hopper - center
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
	box(
		m,
		"CrossBeam",
		S,
		Vector3.new(hopperAt.X - 0.25, eave + 0.1, -postZ + 0.35),
		Vector3.new(hopperAt.X + 0.25, eave + 0.5, postZ - 0.35),
		C.Steel,
		nil,
		GHOST
	)
	-- the roof: its track side ends over the platform edge (the elevator stands
	-- just beyond it), the players' side overhangs the ramp
	local roofL = half.X + 0.7
	local roofZ0, roofZ1 = -half.Z, half.Z + 0.7
	local ridgeZ = (roofZ0 + roofZ1) / 2
	local plate = eave + 0.6
	local gap = 4.3 -- the opening's half width (the hopper's band is 4.1)
	for _, span in { { -roofL, hopperAt.X - gap }, { hopperAt.X + gap, roofL } } do
		local x0, x1 = span[1], span[2]
		box(m, "Eave", S, Vector3.new(x0, plate, roofZ0), Vector3.new(x1, plate + 0.35, roofZ1), C.RoofTrim, nil, DECOR)
		for _, edge in { roofZ0 + 0.1, roofZ1 - 0.1 } do
			triangle(
				m,
				"Roof",
				S,
				Vector3.new((x0 + x1) / 2, plate + 0.35, ridgeZ),
				Vector3.new(0, 1.4, 0),
				Vector3.new(0, 0, edge - ridgeZ),
				x1 - x0 - 0.2,
				C.Roof,
				nil,
				DECOR
			)
		end
	end
	-- rooftop sign on two posts (both faces: the ramp and the track side)
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
	local stationSign = sign(
		m,
		"Sign",
		S * CFrame.new(0, ridge + 1.6, ridgeZ) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(12, 2.4, 0.35),
		"MINE STATION",
		true
	)
	stationSign.CastShadow = true

	-- the hopper over the intake (its rim = the top of the intake box), a
	-- warm neon strip along its rim
	local intakeSize = cfg.HopperSize
	hopper(
		m,
		S * CFrame.new(hopperAt.X, deck, hopperAt.Z),
		intakeSize.X / 2,
		intakeSize.Z / 2,
		intakeSize.Y - deck,
		{ Throat = 1.3, RimGlow = C.Lamp }
	)
	local intake = block(m, "Intake", CFrame.new(cfg.Hopper + Vector3.new(0, intakeSize.Y / 2, 0)), intakeSize, C.Steel, nil, GHOST)
	intake.Transparency = 1
	intake:AddTag(Railway.HopperTag)

	-- bucket elevator on the track side east of the hopper (its track-side
	-- face just outside the trains' clearance, its head beside the sign's end
	-- so the sign reads from both sides, under no roof), fed by a duct from
	-- the hopper's band, the head with a round hood, and the loading chute
	-- angled from the head down to a spout over the wagons at QuarryStop
	local towerX, casingZ0, casingZ1 = elevatorAt()
	local headY = 12.6
	box(
		m,
		"Elevator",
		S,
		Vector3.new(towerX - ELEVATOR_HALF, 0, casingZ0),
		Vector3.new(towerX + ELEVATOR_HALF, headY, casingZ1),
		C.Steel,
		nil,
		SOLID
	)
	local bandY = deck + intakeSize.Y - deck - 1.4 -- the hopper band's top (the tub floor)
	box(
		m,
		"Duct",
		S,
		Vector3.new(hopperAt.X + intakeSize.X / 2 + 0.6, bandY - 1.0, -half.Z - 0.7),
		Vector3.new(towerX - 1.2, bandY - 0.2, -half.Z + 0.2),
		C.SteelDark,
		nil,
		GHOST
	)
	box(
		m,
		"ElevatorBand",
		S,
		Vector3.new(towerX - ELEVATOR_HALF - ELEVATOR_BAND, 0, casingZ0 - ELEVATOR_BAND),
		Vector3.new(towerX + ELEVATOR_HALF + ELEVATOR_BAND, 0.9, casingZ1 + ELEVATOR_BAND),
		C.Orange,
		nil,
		BUMP_SMALL
	)
	local headZ0 = casingZ0 - 1.3
	box(m, "Head", S, Vector3.new(towerX - 1.6, headY, headZ0), Vector3.new(towerX + 1.6, headY + 1.6, casingZ1 + 0.3), C.Steel, nil, SOLID)
	cyl(m, "Hood", S * CFrame.new(towerX, headY + 1.6, (headZ0 + casingZ1 + 0.3) / 2), ALONG_X, 3.2, 3.4, C.SteelLight, nil, DECOR)
	local spoutBottom = 9.8 -- above every train (chimney top 9.31)
	local spout = Vector3.new(hopperAt.X, spoutBottom, trackZ)
	local chuteFrom = Vector3.new(towerX - 1.1, headY + 0.5, headZ0 + 0.5)
	local chuteTo = spout + Vector3.new(0, 1.1, 0)
	local chuteLen = (chuteTo - chuteFrom).Magnitude
	local chute = S * CFrame.lookAt((chuteFrom + chuteTo) / 2, chuteTo)
	block(m, "Chute", chute, Vector3.new(1.6, 0.25, chuteLen), C.SteelDark, nil, DECOR)
	for _, side in { -1, 1 } do
		block(m, "ChuteSide", chute * CFrame.new(side * 0.9, 0.35, 0), Vector3.new(0.2, 0.95, chuteLen), C.Steel, nil, GHOST)
	end
	box(m, "Spout", S, spout - Vector3.new(0.75, 0, 0.75), spout + Vector3.new(0.75, 1.1, 0.75), C.Orange, nil, GHOST)
	-- a strut from the casing's face to the spout
	local strutFrom = Vector3.new(towerX - 0.6, spoutBottom + 0.2, casingZ0)
	local strutTo = spout + Vector3.new(0.75, 0.2, 0)
	block(
		m,
		"Strut",
		S * CFrame.lookAt((strutFrom + strutTo) / 2, strutTo),
		Vector3.new(0.4, 0.4, (strutTo - strutFrom).Magnitude),
		C.SteelDark,
		nil,
		GHOST
	)

	-- lever console (Kenney lever-double) just behind the prompt point
	local prompt = cfg.PromptPoint - center
	local console = S * CFrame.new(prompt.X, deck, half.Z - 1.1)
	box(m, "Console", console, Vector3.new(-1.1, 0, -0.6), Vector3.new(1.1, 1.4, 0.6), C.Steel, nil, BUMP_SMALL)
	triangle(
		m,
		"ConsoleTop",
		console,
		Vector3.new(0, 1.4, -0.6),
		Vector3.new(0, 0.6, 0),
		Vector3.new(0, 0, 1.2),
		2.2,
		C.SteelLight,
		nil,
		GHOST
	)
	block(
		m,
		"Screen",
		console * CFrame.new(-0.35, 1.72, 0.02) * CFrame.Angles(math.atan2(0.6, 1.2), 0, 0),
		Vector3.new(0.9, 0.05, 0.7),
		C.Screen,
		NEON,
		GHOST
	)
	cyl(m, "Lever", console * CFrame.new(0.6, 1.95, -0.1) * CFrame.Angles(0.3, 0, 0), ALONG_Y, 1.1, 0.18, C.SteelDark, nil, GHOST)
	ball(m, "Knob", console * CFrame.new(0.6, 2.5, 0.07), 0.42, C.Lever, nil, GHOST)

	-- lamps under the eave at the corner posts, and the pendant over the hopper
	-- (the station's one PointLight) under the cross beam
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
	local pendant = S * CFrame.new(hopperAt.X, eave - 0.15, hopperAt.Z)
	cyl(m, "Shade", pendant, ALONG_Y, 0.5, 1.4, C.SteelDark, nil, GHOST)
	local bulb = ball(m, "Bulb", pendant * CFrame.new(0, -0.45, 0), 0.7, C.Lamp, NEON, GHOST)
	light(bulb, C.Lamp, 16, 1.3)

	-- crates at the east end of the platform
	local crates = {
		{ 9.6, 0, -1.1, 0.12 },
		{ 12.1, 0, -0.8, -0.1 },
		{ 10.9, 1.2, -0.95, 0.35 },
		{ 11.4, 0, 1.3, 0.5 },
	}
	for _, c in crates do
		crate(m, S * CFrame.new(c[1], deck + c[2], c[3]) * CFrame.Angles(0, c[4], 0))
	end

	-- a short straight siding that leaves the main line at a shallow angle
	-- east of the platform and ends in a buffer stop past the platform's end,
	-- well short of the east portal: the buffer's face just far enough out
	-- that its beam keeps out of the main line's clearance, the track running
	-- on under the buffer's struts (SidingDrop under the main line, so the
	-- crossing rails' and timbers' top faces never fight; its first timbers
	-- lie under the main line's)
	local fork = TrainConfig.QuarryStop + Vector3.new(half.X - 4, 0, 0)
	local angle = math.rad(26)
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) -- toward the platform side
	local reach = (Railway.Clearance.HalfWidth + 0.15 + BUFFER_HALF * math.cos(angle)) / math.sin(angle)
	local face = fork + out * reach
	track(m, "Siding", { fork, face + out * BUFFER_DEPTH }, 0, 0, { Drop = SIDING_DROP, SleepersFrom = 4 })
	bufferStop(m, CFrame.lookAt(face, face - out))

	-- attachments for the prompts and the waiting train
	attach(platform, "PromptPoint", cfg.PromptPoint)
	attach(platform, "TrainPoint", TrainConfig.QuarryStop)
	return m
end

---------------------------------------------------------------- Mine Lifts

--[[
	One Mine Lift: frame `F` on the floor at the lift's position looking at
	its front (toward the cave's middle). The Intake's box is the lift's Size,
	its bottom on the floor.
]]
local function buildLift(parent: Instance, info: { Id: string, Position: Vector3, Size: Vector3 }): Model
	-- (find lifts by the MineLift tag and LiftId; tests/World.spec.luau lets a
	-- lift stand in its own cave's walkable space by the same tag)
	local m = model("MineLift_" .. info.Id, parent)
	m:AddTag(Railway.LiftTag)
	m:SetAttribute("LiftId", info.Id)
	streaming(m, false)
	local pos = info.Position
	local size = info.Size
	local front = if pos.X > 0 then Vector3.new(-1, 0, 0) else Vector3.new(1, 0, 0)
	local F = CFrame.lookAt(pos, pos + front)
	local cave = (WorldLayout.Caves :: any)[info.Id]
	local ceiling = (if cave then cave.Max.Y else pos.Y + 30) - pos.Y

	local frameHalf = math.max(size.X, size.Z) / 2 + 1.2
	local base = box(
		m,
		"Base",
		F,
		Vector3.new(-frameHalf - 0.4, 0, -frameHalf - 0.4),
		Vector3.new(frameHalf + 0.4, 0.4, frameHalf + 0.4),
		C.SteelDark,
		nil,
		SOLID
	)
	m.PrimaryPart = base
	-- headframe: four posts with orange collars, two crossbeams, a spine
	local postTop = 14.4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * frameHalf, sz * frameHalf
			box(m, "Post", F, Vector3.new(x - 0.4, 0.4, z - 0.4), Vector3.new(x + 0.4, postTop, z + 0.4), C.Steel, nil, BUMP)
			box(
				m,
				"Collar",
				F,
				Vector3.new(x - 0.55, postTop - 2.2, z - 0.55),
				Vector3.new(x + 0.55, postTop - 1.6, z + 0.55),
				C.Orange,
				nil,
				GHOST
			)
		end
	end
	for _, sz in { -1, 1 } do
		box(
			m,
			"Crossbeam",
			F,
			Vector3.new(-frameHalf - 0.6, postTop, sz * frameHalf - 0.4),
			Vector3.new(frameHalf + 0.6, postTop + 0.8, sz * frameHalf + 0.4),
			C.Steel,
			nil,
			DECOR
		)
	end
	box(
		m,
		"Spine",
		F,
		Vector3.new(-0.4, postTop + 0.8, -frameHalf + 0.6),
		Vector3.new(0.4, postTop + 1.6, frameHalf - 0.6),
		C.SteelDark,
		nil,
		DECOR
	)

	-- the hopper: a low tub (its rim LiftRim above the floor, so a soft throw
	-- from the floor clears it) inside the taller intake box
	hopper(
		m,
		F * CFrame.new(0, 0.4, 0),
		size.X / 2,
		size.Z / 2,
		Railway.LiftRim - 0.4,
		{ Throat = 0.9, Tub = 1.2, Band = 0.4, Funnel = 0.8, Glow = C.Glow }
	)
	local intake = block(m, "Intake", CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)), size, C.Steel, nil, GHOST)
	intake.Transparency = 1
	intake:AddTag(Railway.HopperTag)
	intake:SetAttribute("LiftId", info.Id)

	-- the cage parked up under the crossbeams (high above the throws into
	-- the hopper), its cable up into the ceiling
	local cage0, cage1 = 10.5, 14
	local ch = 2.8
	box(m, "CageFloor", F, Vector3.new(-ch, cage0, -ch), Vector3.new(ch, cage0 + 0.3, ch), C.Steel, nil, DECOR)
	box(m, "CageRoof", F, Vector3.new(-ch - 0.2, cage1 - 0.4, -ch - 0.2), Vector3.new(ch + 0.2, cage1, ch + 0.2), C.Orange, nil, DECOR)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				m,
				"CageBar",
				F,
				Vector3.new(sx * ch - 0.18, cage0 + 0.3, sz * ch - 0.18),
				Vector3.new(sx * ch + 0.18, cage1 - 0.4, sz * ch + 0.18),
				C.SteelLight,
				nil,
				GHOST
			)
		end
	end
	for _, y in { cage0 + 1.3, cage0 + 2.5 } do
		box(m, "Gate", F, Vector3.new(-ch, y - 0.12, -ch - 0.12), Vector3.new(ch, y + 0.12, -ch + 0.12), C.Orange, nil, GHOST)
	end
	cyl(m, "Cable", F * CFrame.new(0, (cage1 + ceiling + 0.5) / 2, 0), ALONG_Y, ceiling + 0.5 - cage1, 0.45, C.SteelLight, nil, GHOST)
	-- a lamp under the cage lights the hopper (the lift's one PointLight)
	local cageLamp = box(m, "CageLamp", F, Vector3.new(-0.5, cage0 - 0.35, -0.5), Vector3.new(0.5, cage0, 0.5), C.Lamp, NEON, GHOST)
	light(cageLamp, C.Lamp, 16, 1.4)
	box(m, "Anchor", F, Vector3.new(-1.1, ceiling - 0.8, -1.1), Vector3.new(1.1, ceiling, 1.1), C.SteelDark, nil, GHOST)

	-- a header beam across the front posts with the LIFT sign hanging under it
	-- in view of a player at the hopper (both faces), a warning lamp on the
	-- front crossbeam's end
	local headerY = 11.6
	box(
		m,
		"Header",
		F,
		Vector3.new(-frameHalf, headerY, -frameHalf - 0.3),
		Vector3.new(frameHalf, headerY + 0.5, -frameHalf + 0.3),
		C.Steel,
		nil,
		DECOR
	)
	-- (self-lit text: the caves' tinted ambient would turn it red or olive; a
	-- warm lamp strip along the header's front edge over it)
	sign(m, "Sign", F * CFrame.new(0, headerY - 0.85, -frameHalf - 0.05), Vector3.new(4.6, 1.6, 0.3), "LIFT", true, 0)
	box(
		m,
		"SignLamp",
		F,
		Vector3.new(-1.9, headerY - 0.02, -frameHalf - 0.48),
		Vector3.new(1.9, headerY + 0.16, -frameHalf - 0.3),
		C.Lamp,
		NEON,
		GHOST
	)
	box(
		m,
		"LampBase",
		F,
		Vector3.new(frameHalf - 0.25, postTop + 0.8, -frameHalf - 0.25),
		Vector3.new(frameHalf + 0.25, postTop + 1.6, -frameHalf + 0.25),
		C.SteelDark,
		nil,
		GHOST
	)
	ball(m, "Lamp", F * CFrame.new(frameHalf, postTop + 2.0, -frameHalf), 0.9, C.Orange, NEON, GHOST)

	attach(base, "PromptPoint", F:PointToWorldSpace(Vector3.new(0, 3, -frameHalf - 1.8)))
	return m
end

---------------------------------------------------------------- build

-- World XZ rect of every plot's train stop platform (the coastal track gives way to it).
function Railway.platformRects(): { Rect }
	local rects: { Rect } = {}
	local stop = BaseLayout.TrainStop
	for _, plot in WorldLayout.Plots do
		local cf = WorldLayout.plotCFrame(plot)
		local lo = Vector3.new(math.huge, 0, math.huge)
		local hi = Vector3.new(-math.huge, 0, -math.huge)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cf:PointToWorldSpace(stop.Center + Vector3.new(sx * stop.Size.X / 2, 0, sz * stop.Size.Z / 2))
				lo = Vector3.new(math.min(lo.X, p.X), 0, math.min(lo.Z, p.Z))
				hi = Vector3.new(math.max(hi.X, p.X), 0, math.max(hi.Z, p.Z))
			end
		end
		table.insert(rects, { Min = lo, Max = hi })
	end
	return rects
end

-- Where the visible part of each line ends: the portal mouths (and the
-- buffer); each quarry end moves in along its own end segment (as
-- portalMouths), the interior points stay.
function Railway.visibleLines(): { [string]: { Vector3 } }
	local q = table.clone(TrainConfig.QuarryLine)
	local n = #q
	q[1] = q[1] + (q[2] - q[1]).Unit * Railway.PortalInset
	q[n] = q[n] + (q[n - 1] - q[n]).Unit * Railway.PortalInset
	return {
		QuarryLine = q,
		CoastWest = table.clone(TrainConfig.CoastWest),
		CoastEast = table.clone(TrainConfig.CoastEast),
	}
end

-- The yards' short placeholder tracks (PlotBuilder) give way to the through line.
local function removePlaceholders(map: Instance)
	local plots = map:FindFirstChild("Plots")
	if not plots then
		return
	end
	local doomed = {}
	for _, d in plots:GetDescendants() do
		if d:GetAttribute("RailwayPlaceholder") == true then
			table.insert(doomed, d)
		end
	end
	for _, d in doomed do
		d:Destroy()
	end
end

function Railway.build(map: Instance): Folder
	removePlaceholders(map)
	local old = map:FindFirstChild("Railway")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Railway"
	local rng = Rng.new(WorldLayout.Seed * 13 + 7)

	-- the quarry line (its sleepers give way to the station's elevator), its
	-- wall portals and the Mine Station
	local quarry = TrainConfig.QuarryLine
	local trim = Railway.PortalInset - MOUTH_D / 2
	track(root, "QuarryLine", quarry, trim, trim, { Clips = { elevatorRect() } })
	local portals = Instance.new("Folder")
	portals.Name = "Portals"
	portals.Parent = root
	local mouths = Railway.portalMouths()
	for _, name in { "West", "East" } do
		quarryPortal(portals, name, mouths[name], rng)
	end
	buildStation(root, rng)

	-- the coastal lines from the south portals to their buffer stops
	local clips = Railway.platformRects()
	local coasts = {
		{ Name = "CoastWest", Line = TrainConfig.CoastWest, Portal = "SouthWest" },
		{ Name = "CoastEast", Line = TrainConfig.CoastEast, Portal = "SouthEast" },
	}
	for _, coast in coasts do
		local line = coast.Line
		local n = #line
		local dir = (line[n] - line[n - 1]).Unit
		local m = track(root, coast.Name, line, -MOUTH_D / 2, -(Railway.BufferGap + BUFFER_DEPTH), { Clips = clips })
		local face = line[n] + dir * Railway.BufferGap
		bufferStop(m, CFrame.lookAt(face, face - dir))
		southPortal(portals, coast.Portal, mouths[coast.Portal], rng)
	end

	-- the Mine Lifts down in the caves
	for _, info in TrainConfig.Lifts do
		buildLift(root, info)
	end

	root.Parent = map
	return root
end

-- The Mine Lift builder, also used by the mine floor areas (src/server/World/Mine).
Railway.buildLift = buildLift

return Railway
