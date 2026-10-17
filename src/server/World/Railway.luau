--[[
	The ore trains' railway (design v2, docs/plans/STEP2_PLAN.md), built into
	Workspace.Map.Railway from TrainConfig in the Kenney Train Kit / Factory
	Kit look (TrainBuilder's lavender rails on salmon sleepers, periwinkle
	steel with orange trim):

	  QuarryLine   the quarry track (TrainConfig.QuarryLine) on the quarry
	               floor, from the west to the east wall portal
	  MineStation  model tagged "TrainStation" at TrainConfig.Station: a
	               flagstone platform with a safety edge and an access ramp,
	               a red pitched canopy on periwinkle posts with a rooftop
	               "MINE STATION" sign, the big funnel hopper (Kenney
	               hopper-square: tub, light band, funnel, throat, legs) over
	               the invisible `Intake` (tag "TrainHopper", HopperSize, its
	               bottom at Station.Hopper), a bucket elevator beside it whose
	               head feeds a loading chute over the track (the spout sits
	               above the wagons at QuarryStop), a lever console at the
	               `PromptPoint` attachment, the `TrainPoint` attachment at
	               QuarryStop, neon lamps and one PointLight (the pendant over
	               the hopper), crates and a short siding off the main line
	               that ends in a buffer stop
	  Portals      four tunnel portals with a dark mouth (black neon) in a
	               timber frame (lanterns on the posts, knee braces) under a
	               steel lintel with an orange plate and a signal lamp:
	               West/East where the quarry line meets the quarry walls, on
	               a light stone buttress (the mouth stands PortalInset in
	               front of the wall, so the wall's foot boulders stay behind
	               it), SouthWest/SouthEast at (+-166, 0, SouthPortalZ) facing
	               north in a narrow rock hill (a grass slope over the lintel,
	               a crest, two lower steps with bushes) that keeps between the
	               town's rail strip (x 160) and the island rim (x 171.7)
	  CoastWest    the coastal lines (TrainConfig.CoastWest/CoastEast) from the
	  CoastEast    south portal north to a buffer stop just past BufferZ,
	               behind every plot's yard train stop: the near rail and the
	               sleeper ends give way under each stop's platform
	               (BaseLayout.TrainStop), so nothing cuts into a yard
	  EmberCaves   the Mine Lifts (TrainConfig.Lifts, named by their LiftId,
	  DeepHollow   tagged "MineLift"): a periwinkle headframe with orange
	               collars on a steel base, a funnel hopper with a warm glowing
	               floor over the invisible `Intake` (tag "TrainHopper",
	               attribute LiftId), a cage hanging above it on a cable that
	               runs up into the cave ceiling with a lamp under it (the
	               lift's one PointLight), a "LIFT" sign, a warning lamp and
	               the `PromptPoint` attachment in front

	The yards' `RailwayPlaceholder` track pieces (PlotBuilder) are removed:
	the through line replaces them (their buffer stops stood on the line).

	Track: straight runs of at most RunLength studs (two rail parts per run,
	split where a platform covers a rail) and a sleeper every ~6 studs; all
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
local Style = require(script.Parent.Lobby.Style)

local Railway = {}

Railway.MaxParts = 600 -- the whole railway (tests/Railway.spec.luau)
Railway.RunLength = 24 -- longest rail part
Railway.PortalInset = 6 -- quarry portals: the mouth stands this far in front of the line's end
Railway.BufferGap = 1.7 -- the coastal buffer stops' face, past the line's end (clear of the last platform)
-- The space the trains need around a line (TrainBuilder: steam cylinders
-- +-3.43, chimney top 9.31 above the line point); only rails, sleepers and
-- the portal mouths may enter it.
Railway.Clearance = { HalfWidth = 3.6, Bottom = 1.5, Top = 9.6 }
Railway.StationTag = "TrainStation"
Railway.HopperTag = "TrainHopper"
Railway.LiftTag = "MineLift"

export type Rect = { Min: Vector3, Max: Vector3 } -- world XZ (Y ignored)
type Props = { [string]: any }

local rgb = Color3.fromRGB
local SC = Style.C
local TC = TrainBuilder.Colors

local C = {
	Steel = rgb(122, 130, 184), -- the Factory Kit's periwinkle (as PlotBuilder's machine housings)
	SteelLight = rgb(160, 168, 212),
	SteelDark = rgb(58, 60, 72),
	Orange = TC.Corner, -- Kenney's orange collars and buffers
	Hazard = rgb(250, 206, 64), -- the safety edge of the yards' train stops
	Deck = SC.Flag,
	DeckDark = SC.FlagDark,
	Roof = SC.Roof,
	RoofTrim = SC.RoofTrim,
	Interior = TC.Interior,
	Lamp = rgb(255, 184, 96),
	Mouth = rgb(6, 6, 9),
	Timber = SC.Wood,
	TimberDark = SC.WoodDark,
	Crate = rgb(232, 140, 90), -- Kenney box-large
	Tape = rgb(244, 200, 150),
	Board = rgb(58, 60, 72),
	Text = SC.SignText,
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
-- on the back too when `twoSided`.
local function sign(parent: Instance, name: string, cf: CFrame, size: Vector3, text: string, twoSided: boolean): Part
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

-- Streams in as one piece; `lod` keeps a low-detail mesh in view when far away.
-- (pcall'd like Style.streaming: a runtime rebuild may not write these.)
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
local function bufferStop(parent: Instance, cf: CFrame): Model
	local m = model("BufferStop", parent)
	local y = RAIL_TOP + TrainBuilder.CouplerHeight
	box(m, "Beam", cf, Vector3.new(-2.9, y - 0.6, 0), Vector3.new(2.9, y + 0.6, 0.8), TC.Beam, nil, BUMP)
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
	`half` = the frame's outer half width. Returns the lintel's top height.
]]
local MOUTH_W, MOUTH_H, MOUTH_D = 8.6, 11.4, 1.2
local LINTEL = 1.5
local function portalFrame(m: Model, cf: CFrame, half: number): number
	local mouth =
		box(m, "Mouth", cf, Vector3.new(-MOUTH_W / 2, 0, 0), Vector3.new(MOUTH_W / 2, MOUTH_H, MOUTH_D), C.Mouth, NEON, SOLID_SMALL)
	m.PrimaryPart = mouth
	local postW = half - MOUTH_W / 2
	local postX = MOUTH_W / 2 + postW / 2
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
			Vector3.new(side * MOUTH_W / 2, top, -0.3),
			Vector3.new(0, -1.7, 0),
			Vector3.new(-side * 1.7, 0, 0),
			0.7,
			C.TimberDark,
			WOOD,
			GHOST
		)
	end
	-- steel lintel with an orange plate and a signal lamp on its front edge
	-- (the rock above the lintel starts behind the lamp)
	local lintelTop = top + LINTEL
	box(m, "Lintel", cf, Vector3.new(-half - 0.2, top, -1.1), Vector3.new(half + 0.2, lintelTop, 0.5), C.Steel, nil, BUMP)
	box(m, "Plate", cf, Vector3.new(-half + 1.6, top + 0.35, -1.22), Vector3.new(half - 1.6, top + 1.15, -1.1), C.Orange, nil, GHOST)
	box(m, "Lamp", cf, Vector3.new(-0.4, lintelTop, -1.0), Vector3.new(0.4, lintelTop + 0.6, -0.4), C.Lamp, NEON, GHOST)
	return lintelTop
end

-- Quarry wall portal: the frame on a stone buttress against the wall.
local function quarryPortal(parent: Instance, name: string, cf: CFrame, rng: Rng.Rng)
	local m = portalModel(parent, name)
	local half = 5.55
	local top = portalFrame(m, cf, half)
	-- (a lighter stone than the wall's, so the portal stands out of its shadow)
	local function stone(): Color3
		return Geo.vary(rng:pick({ SC.Stone, SC.Stone, SC.StoneLight }), rng, 0.05)
	end
	box(m, "Rock", cf, Vector3.new(-8, 0, MOUTH_D), Vector3.new(8, top + 3.2, 7.5), stone(), nil, SOLID)
	for _, side in { -1, 1 } do
		box(m, "Rock", cf, Vector3.new(side * (half - 0.1), 0, -1.4), Vector3.new(side * 9.2, 8.6, 3), stone(), nil, SOLID)
		box(m, "Rock", cf, Vector3.new(side * (half + 0.6), 8.6, -0.4), Vector3.new(side * 8.4, top - 0.6, 2.6), stone(), nil, SOLID)
	end
	box(m, "Rock", cf, Vector3.new(-7.4, top, -0.3), Vector3.new(7.4, top + 3.2, 3), stone(), nil, SOLID)
end

--[[
	South portal: the frame in a narrow stepped rock hill with grass caps
	(it must keep between the town's rail strip and the island rim).
]]
local function southPortal(parent: Instance, name: string, cf: CFrame, rng: Rng.Rng)
	local m = portalModel(parent, name)
	local half = 5.6
	local top = portalFrame(m, cf, half - 0.2)
	-- light stone (its north face is in the evening shadow) under grass caps
	local function stone(): Color3
		return Geo.vary(rng:pick({ SC.Stone, SC.StoneLight, SC.Stone }), rng, 0.05)
	end
	local function grass(x: number, z0: number, z1: number, y: number)
		box(m, "Grass", cf, Vector3.new(-x, y, z0), Vector3.new(x, y + 0.8, z1), Geo.vary(SC.Grass, rng, 0.04), nil, SOLID_SMALL)
	end
	-- the hill: a grass slope rising from the lintel to a mound with a
	-- narrower crest (the slope faces the sky, so it stays bright while the
	-- north face is in the evening shadow), then two lower steps down to the
	-- south coast
	local h1, crest, h2, h3 = top + 2.4, top + 5, 9.5, 4.5
	local slopeZ = 3.4
	box(m, "Rock", cf, Vector3.new(-half, 0, MOUTH_D), Vector3.new(half, top, slopeZ), stone(), nil, SOLID)
	triangle(
		m,
		"Slope",
		cf,
		Vector3.new(0, top, slopeZ),
		Vector3.new(0, h1 + 0.8 - top, 0),
		Vector3.new(0, 0, -slopeZ - 0.3),
		half * 2,
		Geo.vary(SC.Grass, rng, 0.04),
		nil,
		SOLID
	)
	box(m, "Rock", cf, Vector3.new(-half, 0, slopeZ), Vector3.new(half, h1, 9), stone(), nil, SOLID)
	grass(half, slopeZ, 9.2, h1)
	box(m, "Rock", cf, Vector3.new(-4, h1 + 0.8, slopeZ), Vector3.new(4, crest, 8.4), stone(), nil, SOLID)
	grass(4.2, slopeZ - 0.2, 8.6, crest)
	box(m, "Rock", cf, Vector3.new(-half, 0, 9), Vector3.new(half, h2, 16), stone(), nil, SOLID)
	grass(half, 9, 16.2, h2)
	box(m, "Rock", cf, Vector3.new(-half, 0, 16), Vector3.new(half, h3, 23.4), stone(), nil, SOLID)
	grass(half, 16, 23.4, h3)
	-- bushes on the steps and a boulder on the crest for a rougher silhouette
	local bushes = { { -3, h2 + 0.8, 12.6, 2.6 }, { 2.6, h2 + 0.8, 14.4, 2.0 }, { 2.4, h3 + 0.8, 20, 2.2 } }
	for i, b in bushes do
		local s = Vector3.new(b[4], b[4] * 0.75, b[4] * 0.9)
		local at = cf * CFrame.new(b[1], b[2] + s.Y / 2 - 0.1, b[3]) * CFrame.Angles(0, 0.4 * i, 0)
		block(m, "Bush", at, s, Geo.vary(SC.GrassDark, rng, 0.05), nil, GHOST)
	end
	local s = Vector3.new(2.8, 2.0, 2.4)
	block(m, "Boulder", cf * CFrame.new(-1.6, crest + 0.8 + s.Y / 2 - 0.3, 5.6) * CFrame.Angles(0, 0.5, 0.1), s, stone(), nil, SOLID_SMALL)
end

---------------------------------------------------------------- Mine Station

--[[
	Kenney hopper-square on short legs: tub walls, a lighter band, a dark
	floor and dark liners inside the tub (a neon `glow` floor in the caves), a
	four-sided funnel and a throat. `cf` = the ground under the hopper (the
	deck top), openX/openZ = the tub's inner half size (the intake box's), `rim`
	= the rim height above `cf`. The tub collides (items fall into it).
]]
local function hopper(m: Model, cf: CFrame, openX: number, openZ: number, rim: number, throat: number, glow: Color3?)
	local wall = 0.4
	local tubH, bandH, funnelH = 1.4, 0.6, 1.4
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
		Vector3.new(ox - wall / 2, tub0 + 0.05, oz - wall / 2),
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
	-- stays open), beams, eave plate and a red pitched roof
	local postX, postZ = half.X - 0.4, half.Z - 0.4
	local eave = deck + 6.9
	local posts = {
		Vector3.new(-postX, 0, -postZ),
		Vector3.new(postX, 0, -postZ),
		Vector3.new(-postX, 0, postZ),
		Vector3.new(postX, 0, postZ),
		Vector3.new(-5.4, 0, -postZ),
		Vector3.new(5.4, 0, -postZ),
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
	local roofL = half.X + 0.7
	local roofZ = half.Z + 0.7
	local plate = eave + 0.6
	box(m, "Eave", S, Vector3.new(-roofL, plate, -roofZ), Vector3.new(roofL, plate + 0.35, roofZ), C.RoofTrim, nil, DECOR)
	for _, side in { -1, 1 } do
		triangle(
			m,
			"Roof",
			S,
			Vector3.new(0, plate + 0.35, 0),
			Vector3.new(0, 1.4, 0),
			Vector3.new(0, 0, side * (roofZ - 0.1)),
			roofL * 2 - 0.2,
			C.Roof,
			nil,
			DECOR
		)
	end
	-- rooftop sign on two posts (both faces: the ramp and the track side)
	local ridge = plate + 0.35 + 1.4
	for _, side in { -1, 1 } do
		box(
			m,
			"SignPost",
			S,
			Vector3.new(side * 5 - 0.2, ridge - 0.6, -0.2),
			Vector3.new(side * 5 + 0.2, ridge + 0.5, 0.2),
			C.SteelDark,
			nil,
			GHOST
		)
	end
	local stationSign =
		sign(m, "Sign", S * CFrame.new(0, ridge + 1.6, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 2.4, 0.35), "MINE STATION", true)
	stationSign.CastShadow = true

	-- the hopper over the intake (its rim = the top of the intake box)
	local intakeSize = cfg.HopperSize
	local hopperAt = cfg.Hopper - center
	hopper(m, S * CFrame.new(hopperAt.X, deck, hopperAt.Z), intakeSize.X / 2, intakeSize.Z / 2, intakeSize.Y - deck, 1.3)
	local intake = block(m, "Intake", CFrame.new(cfg.Hopper + Vector3.new(0, intakeSize.Y / 2, 0)), intakeSize, C.Steel, nil, GHOST)
	intake.Transparency = 1
	intake:AddTag(Railway.HopperTag)

	-- bucket elevator between the platform and the track: the casing (its
	-- track-side face just outside the trains' clearance), a duct from the
	-- hopper's throat, the head with a round hood, and the loading chute
	-- from the head down to a spout over the wagons at QuarryStop
	local towerX = hopperAt.X
	local casingZ0, casingZ1 = -half.Z - 2.3, -half.Z - 0.1
	local headY = 12.6
	box(m, "Elevator", S, Vector3.new(towerX - 1.2, 0, casingZ0), Vector3.new(towerX + 1.2, headY, casingZ1), C.Steel, nil, SOLID)
	box(
		m,
		"ElevatorBand",
		S,
		Vector3.new(towerX - 1.35, 0, casingZ0 - 0.15),
		Vector3.new(towerX + 1.35, 0.9, casingZ1 + 0.15),
		C.Orange,
		nil,
		BUMP_SMALL
	)
	box(
		m,
		"Duct",
		S,
		Vector3.new(towerX - 0.8, deck, casingZ1 - 0.1),
		Vector3.new(towerX + 0.8, deck + 0.9, hopperAt.Z - 1.2),
		C.SteelDark,
		nil,
		BUMP_SMALL
	)
	local headZ0 = casingZ0 - 1.3
	box(m, "Head", S, Vector3.new(towerX - 1.6, headY, headZ0), Vector3.new(towerX + 1.6, headY + 1.6, casingZ1 + 0.3), C.Steel, nil, SOLID)
	cyl(m, "Hood", S * CFrame.new(towerX, headY + 1.6, (headZ0 + casingZ1 + 0.3) / 2), ALONG_X, 3.2, 3.4, C.SteelLight, nil, DECOR)
	local spoutBottom = 9.8 -- above every train (chimney top 9.31)
	local chuteFrom = Vector3.new(towerX, headY + 0.6, headZ0 + 0.3)
	local chuteTo = Vector3.new(towerX, spoutBottom + 1.1, trackZ)
	local chuteLen = (chuteTo - chuteFrom).Magnitude
	local chute = S * CFrame.lookAt((chuteFrom + chuteTo) / 2, chuteTo)
	block(m, "Chute", chute, Vector3.new(1.6, 0.25, chuteLen), C.SteelDark, nil, DECOR)
	for _, side in { -1, 1 } do
		block(m, "ChuteSide", chute * CFrame.new(side * 0.9, 0.35, 0), Vector3.new(0.2, 0.95, chuteLen), C.Steel, nil, GHOST)
	end
	box(
		m,
		"Spout",
		S,
		Vector3.new(towerX - 0.75, spoutBottom, trackZ - 0.75),
		Vector3.new(towerX + 0.75, spoutBottom + 1.1, trackZ + 0.75),
		C.Orange,
		nil,
		GHOST
	)
	box(
		m,
		"Strut",
		S,
		Vector3.new(towerX - 0.2, spoutBottom, casingZ0),
		Vector3.new(towerX + 0.2, spoutBottom + 0.4, trackZ + 0.75),
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
	-- (the station's one PointLight)
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
	local pendant = S * CFrame.new(hopperAt.X, eave - 0.35, hopperAt.Z)
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

	-- a short siding that leaves the main line at a shallow angle east of the
	-- platform and ends in a buffer stop (2 hundredths under the main line, so
	-- crossing faces never fight; its first timbers lie under the main line's)
	local fork = TrainConfig.QuarryStop + Vector3.new(half.X - 4, 0, 0)
	local bend = fork + Vector3.new(19, 0, 8.6)
	local stub = bend + Vector3.new(3.5, 0, 0)
	track(m, "Siding", { fork, bend, stub }, 0, -(0.3 + BUFFER_DEPTH), { Drop = 0.02, SleepersFrom = 4 })
	bufferStop(m, CFrame.lookAt(stub + Vector3.new(0.3, 0, 0), stub - Vector3.new(1, 0, 0)))

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
	local m = model(info.Id, parent)
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

	-- the hopper over the intake (rim = the top of the intake box)
	hopper(m, F * CFrame.new(0, 0.4, 0), size.X / 2, size.Z / 2, size.Y - 0.4, 1.2, C.Glow)
	local intake = block(m, "Intake", CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)), size, C.Steel, nil, GHOST)
	intake.Transparency = 1
	intake:AddTag(Railway.HopperTag)
	intake:SetAttribute("LiftId", info.Id)

	-- the cage hanging above the hopper, its cable up into the ceiling
	local cage0, cage1 = 6.4, 10.2
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

	-- the LIFT sign on the front crossbeam, a warning lamp on its end
	sign(m, "Sign", F * CFrame.new(0, postTop + 1.6, -frameHalf), Vector3.new(4.6, 1.6, 0.3), "LIFT", false)
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

-- Where the visible part of each line ends: the portal mouths (and the buffer).
function Railway.visibleLines(): { [string]: { Vector3 } }
	local q = TrainConfig.QuarryLine
	local inset = (q[2] - q[1]).Unit * Railway.PortalInset
	return {
		QuarryLine = { q[1] + inset, q[#q] - inset },
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

	-- the quarry line, its wall portals and the Mine Station
	local quarry = TrainConfig.QuarryLine
	local trim = Railway.PortalInset - MOUTH_D / 2
	track(root, "QuarryLine", quarry, trim, trim, {})
	local portals = Instance.new("Folder")
	portals.Name = "Portals"
	portals.Parent = root
	for i, name in { "West", "East" } do
		local endPoint = if i == 1 then quarry[1] else quarry[#quarry]
		local inward = if i == 1 then (quarry[2] - quarry[1]).Unit else (quarry[#quarry - 1] - quarry[#quarry]).Unit
		local mouth = endPoint + inward * Railway.PortalInset
		quarryPortal(portals, name, CFrame.lookAt(mouth, mouth + inward), rng)
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
		local out = (line[2] - line[1]).Unit
		southPortal(portals, coast.Portal, CFrame.lookAt(line[1], line[1] + out), rng)
	end

	-- the Mine Lifts down in the caves
	for _, info in TrainConfig.Lifts do
		buildLift(root, info)
	end

	root.Parent = map
	return root
end

return Railway
