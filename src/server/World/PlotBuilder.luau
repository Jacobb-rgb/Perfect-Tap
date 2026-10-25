--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) with a metal floor (owner 2026-10-17, like the machine pictures:
	a light metal plate with painted tile seams and a soft checker inside a
	slate band with glowing orange strips, all flat),
	framed with the yard by low soft walls in the machines' style A "Soft"
	(owner 2026-10-20, from the preview on art/plot-style-a; SoftKit with
	KitMachines' palette and roles): a slate plinth with a glowing orange
	strip through it, a cream body and a round cream lid, 4 parts per run;
	round cream posts with slate caps (a slate foot and a glowing orange
	lamp ball on the road entrance posts, a lamp ball on the yard gate
	posts) and mitred 45-degree back corners. The name sign (slate, orange
	letters) hangs on the left front wall, a slate banner pole stands at the
	back right corner, and behind the pad (plot-local +Z, the sea side) lies
	the yard from BaseLayout:
	  Walls            the pad's border and the long side walls: front walls
	                   with the road entrance between two lamp posts, the
	                   side walls from the road to the yard's back corners
	                   (posts every ~12.5 studs on the left side only, see
	                   padWalls), the wall between pad and yard with the
	                   YardGate between two posts
	  Yard.Ground      lawn pad, gravel paths
	  Yard.Fence       the yard's cut back corners and the back walls up to
	                   the train stop opening
	  Yard.Pen         the Ore Pen: a slate tray floor with painted tile seams,
	                   low soft walls (plinth, body, round lid) and a gate of
	                   two round posts with glowing bands carrying the ORE PEN
	                   sign (the yard's side wall closes it on the outside, a
	                   slate ramp there rolls ore back in), an invisible
	                   `Intake` part (BaseLayout.Pen.Intake) with a `Prompt`
	                   attachment at Pen.PromptPoint
	  Yard.Podium1..5  showpiece pedestals: a round slate `Base` (the
	                   PrimaryPart) with a glowing ring, a cream drum (`Column`)
	                   with an orange band, the glowing `Rim` under the slate
	                   `Top`, a level holo-ring of opaque soft cyan bars around
	                   the floating ore (the free slots only) and an invisible
	                   `Hover` box for the mouse; the `Top` part holds the
	                   `OrePoint` at BaseLayout.PodiumOreHeight and the `Prompt`
	                   attachment; slots 4 and 5 have a `Lock` model where the
	                   ore floats and a "100 R$" `PricePlate` (PodiumService
	                   hides them for players with the Podiums perk and lights
	                   the rim; the plate's neon frame lives in the lock)
	  Yard.TrainStop   a light metal platform with a glowing strip and a
	                   striped safety edge, the slate TRAIN STOP sign on two
	                   round cream posts, a slate lamp post with a glowing lamp,
	                   and the `Track` placeholder (a short track piece with a
	                   `BufferStop`) that the railway step replaces
	Everything decorative stays outside the build grid, so every cell
	is free for machines. Machines are added at runtime into the plot's
	"Machines" folder by MachineService. A plot with its yard is <= 300 parts
	(13 of them in the Track placeholder the railway replaces) and one light
	(8 plots): style A uses fewer parts than the brick walls did (see
	PlotBuilder.PieceParts).
	Perf pass 1 (phone audit fix 4): no see-through part (the holo-rings are
	opaque), no shadow from small trim (TRIM: post caps and feet, the podium
	bands, the chimney flange, the buffer stop struts: under a stud thick
	and at most 3 studs long, the rule tests/PlotService.spec.luau checks),
	none from the platform step either (STEP: 5 studs long, so outside that
	rule; it stays queryable like the platform it steps up to).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local SoftKit = require(Shared.Builders.SoftKit)
local Rng = require(Shared.Util.Rng)
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Style = require(script.Parent.Lobby.Style)

local PlotBuilder = {}

local BANNER_COLORS = {
	Color3.fromRGB(220, 70, 50),
	Color3.fromRGB(240, 170, 40),
	Color3.fromRGB(80, 180, 90),
	Color3.fromRGB(60, 140, 220),
	Color3.fromRGB(160, 90, 220),
	Color3.fromRGB(230, 110, 170),
	Color3.fromRGB(60, 190, 190),
	Color3.fromRGB(240, 230, 210),
}

local rgb = Color3.fromRGB
local C = Style.C
local NEON = Enum.Material.Neon

local LAWN = rgb(96, 150, 66) -- a deep warm lawn (no bright lime pitch in the hero view)
-- the empty plot from above (lobby hero view): a mown lawn with subtle
-- lighter stripes on every other cell row, framed by a band of light paving
-- stones and a cobble edge
-- (lobby fix round 3: the island's own grass, faint stripes: no lime pitch
-- with bold mower stripes in the hero view)
-- the metal plot floor (machine style "Soft": slate frame, light metal plate, orange glow)
local PLOT_PLATE = rgb(150, 156, 174)
local PLOT_PLATE_ALT = rgb(142, 148, 166) -- the soft checker on every other cell
local PLOT_SEAM = rgb(112, 118, 138) -- painted tile seams
local PLOT_FRAME = rgb(68, 76, 104) -- the slate band round the plate
local PLOT_GLOW = rgb(255, 150, 50) -- glowing strips on the band
local HEDGE = rgb(54, 122, 48) -- the front hedge strip along the road
local POST_HEAD = rgb(255, 140, 48) -- the front lamp posts' neon heads (deep amber)
local PLOT_EDGE = rgb(156, 142, 128)
local GRAVEL = rgb(214, 192, 150)
local RIM_GOLD = rgb(226, 116, 26) -- deep amber: no white bloom over the top plate
local RIM_LOCKED = rgb(96, 88, 104)
local ROBUX_GREEN = rgb(110, 255, 140)
-- style A "Soft" (SoftKit: KitMachines' palette and roles, see the header)
local P = SoftKit.Palette
local PEN_FLOOR = rgb(104, 112, 142) -- the pen's tray: a softer slate than the machines' Floor
local LOCKED_RED = rgb(190, 16, 16) -- deep: a bright red neon tone-maps to salmon
-- Factory / Space Station metal (docs/ART_DIRECTION.md section 9): the Track
-- placeholder's buffer stop (replaced at runtime)
local HOUSING = rgb(66, 72, 92) -- gunmetal (concept v2 dark metal)
-- the podium's holo-ring: style A's soft cyan (the Fusion Reactor's). Perf
-- pass 1: the bars are opaque, so holoTone mixes a glow color 0.4 of the way
-- to HOLO_BEHIND (the grey-blue the old 0.4 see-through bars let through over
-- the yard): a darker, less saturated cyan with the same soft look. A podium
-- skin's glow on the ring goes through it too (ArtifactService).
local HOLO_BEHIND = rgb(100, 115, 133)
local HOLO_SEE_THROUGH = 0.4
local function holoTone(glow: Color3): Color3
	return glow:Lerp(HOLO_BEHIND, HOLO_SEE_THROUGH)
end
local HOLO_GLOW = rgb(90, 200, 255)
local HOLO = holoTone(HOLO_GLOW) -- about rgb(94, 166, 206)
local RAIL_STEEL = rgb(196, 200, 214)
local SLEEPER = rgb(196, 112, 62)

PlotBuilder.RimGold = RIM_GOLD
PlotBuilder.RimLocked = RIM_LOCKED
PlotBuilder.HoloGlow = HOLO_GLOW -- the ring's glow before holoTone (style A's soft cyan)
PlotBuilder.HoloColor = HOLO
-- A glow color as an opaque holo-ring bar shows it (see HOLO).
PlotBuilder.holoTone = holoTone

--[[
	Part budgets per piece: the brick-wall look's counts before style A
	(2026-10-20, plot 1); style A must stay at or under them (tests/
	PlotService.spec.luau). Podium / PodiumLocked: a free / a locked slot;
	TrainStop with its 13-part Track placeholder.
]]
PlotBuilder.PieceParts = { Walls = 77, Fence = 22, Pen = 22, Podium = 23, PodiumLocked = 31, TrainStop = 23 }

-- Border walls (plot-local): the center line of the walls around the pad
-- (the pad's outer edge, |x| or |z|), pillars 0.1 further out so their caps
-- stay off the build grid, the half width of the road entrance, and the
-- back wall's line at the train stop.
PlotBuilder.WallLine = GameConfig.PlotCells * GameConfig.CellSize / 2 + 1
PlotBuilder.EntranceHalf = 10
PlotBuilder.BackWallZ = BaseLayout.Yard.Center.Z + BaseLayout.Yard.Size.Z / 2 - 0.4
local WALL_LINE = PlotBuilder.WallLine
local PILLAR_LINE = WALL_LINE + 0.1
local GATE_POST_CAP = 2.1 -- the entrance and gate posts' caps (their shafts are 1.8)

-- part property sets
local SOLID = SoftKit.SOLID -- players and items bump into it
local FENCE = SoftKit.FENCE
local THIN = SoftKit.TRIM -- collides, too thin for a shadow
-- (perf pass 1) small trim under a stud thick and at most 3 studs long:
-- post caps and feet, the podium band, the chimney flange, the buffer
-- stop struts: it still collides, but casts no shadow
local TRIM = THIN
local TINY = SoftKit.TINY
-- (perf pass 1) the train platform's step: no shadow (a 0.5-stud riser), but
-- solid and queryable like the platform (SOLID without the shadow)
local STEP = { CanTouch = false, CastShadow = false }
local GHOST = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function attachment(parent: BasePart, name: string, localCF: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = localCF
	a.Parent = parent
	return a
end

---------------------------------------------------------------- soft walls (style A)

--[[
	A soft wall run: a slate plinth (on the plot walls with a glowing orange
	strip through it, so it shows on both faces), a cream body and a round
	cream lid (a cylinder along the run, a little wider than the body): 4
	parts (3 on the pen), no raised bricks or mortar lines. A straight run
	goes on under the posts that stand on it (they are wider than the
	wall). Runs that meet without a post are mitred: every layer grows by
	its own half width * tan(turn / 2), so the outer faces meet exactly.
	Posts: a round cream shaft with a slate cap, 2 parts (+1 a slate foot,
	+1 a glowing orange lamp ball on the cap, +1 a glowing band).
]]
type WallKit = {
	Bottom: number, -- plinth bottom (reaches the ground beside the raised pad)
	PlinthTop: number,
	Plinth: number, -- plinth thickness
	Body: number, -- body thickness
	BodyTop: number, -- the lid's axis
	Lid: number, -- the round lid's diameter
	Glow: boolean, -- a glowing strip through the plinth
}

local PLOT_WALL: WallKit = { Bottom = -0.4, PlinthTop = 0.6, Plinth = 1.3, Body = 1.0, BodyTop = 1.95, Lid = 1.2, Glow = true }
local PEN_WALL: WallKit = { Bottom = -0.2, PlinthTop = 0.42, Plinth = 0.95, Body = 0.7, BodyTop = 1.32, Lid = 0.86, Glow = false }

-- the body is where the brick band was (ConveyorService and the tests measure the wall by it)
PlotBuilder.WallBand = PLOT_WALL.Body
PlotBuilder.WallLid = PLOT_WALL.Lid

-- One straight wall from a to b (plot-local, y ignored); `turnA` / `turnB`:
-- the turn (radians) to the run that meets this one there without a post.
local function wall(parent: Instance, cf: CFrame, kit: WallKit, a: Vector3, b: Vector3, turnA: number?, turnB: number?)
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.05 then
		return
	end
	local frame = cf * CFrame.lookAt(flatA, flatB) -- `a` at the origin, the run along the frame's -Z
	local tanA, tanB = math.tan((turnA or 0) / 2), math.tan((turnB or 0) / 2)
	-- one layer of the run, mitred at both ends for its own half width
	local function layer(width: number, y: number, height: number, role: string, flags: SoftKit.Props, name: string, round: boolean?): Part
		local extA, extB = width / 2 * tanA, width / 2 * tanB
		local at = frame * CFrame.new(0, y, -(length + extB - extA) / 2)
		local full = length + extA + extB
		if round then
			return SoftKit.cylZ(parent, at, full, width, role, flags, name)
		end
		return SoftKit.part(parent, at, Vector3.new(width, height, full), role, flags, name)
	end
	local plinthH = kit.PlinthTop - kit.Bottom
	layer(kit.Plinth, kit.Bottom + plinthH / 2, plinthH, "Frame", FENCE, "Plinth")
	if kit.Glow then
		layer(kit.Plinth + 0.06, kit.PlinthTop * 0.5, 0.12, "Neon", TINY, "WallGlow")
	end
	local bodyH = kit.BodyTop - kit.PlinthTop
	layer(kit.Body, kit.PlinthTop + bodyH / 2, bodyH, "Body", FENCE, "Body")
	layer(kit.Lid, kit.BodyTop, 0, "Body", FENCE, "Lid", true)
end

type PostOpts = { D: number?, Top: number?, Foot: boolean?, Lamp: boolean?, Band: number? }

-- A round post (see wall); returns its lamp ball, if any.
local function post(parent: Instance, cf: CFrame, kit: WallKit, at: Vector3, opts: PostOpts?): Part?
	local o: PostOpts = opts or {}
	local d = o.D or 1.7
	local top = o.Top or 3.0
	local height = top - kit.Bottom
	SoftKit.cylUp(parent, cf * CFrame.new(at.X, kit.Bottom + height / 2, at.Z), height, d, "Body", FENCE, "Pillar")
	local capH = 0.42
	-- cap and foot are 0.3 wider than the shaft: on the entrance and gate posts (d 1.8)
	-- their edges meet the openings' edges exactly
	SoftKit.cylUp(parent, cf * CFrame.new(at.X, top + capH / 2, at.Z), capH, d + 0.3, "Frame", TRIM, "PillarCap")
	if o.Foot then
		local footTop = kit.PlinthTop + 0.3
		SoftKit.cylUp(parent, cf * CFrame.new(at.X, (kit.Bottom + footTop) / 2, at.Z), footTop - kit.Bottom, d + 0.3, "Frame", TRIM, "Foot")
	end
	local band = o.Band
	if band then
		SoftKit.cylUp(parent, cf * CFrame.new(at.X, band, at.Z), 0.22, d + 0.06, "Neon", TINY, "PostGlow")
	end
	if o.Lamp then
		local lampD = 0.66
		local lampAt = cf * CFrame.new(at.X, top + capH + lampD / 2 - 0.08, at.Z)
		return SoftKit.glow(SoftKit.ball(parent, lampAt.Position, lampD, SoftKit.Lamp, TINY, "Lamp"))
	end
	return nil
end

-- The yard's back corners are cut at 45 degrees, this far along both walls;
-- the long side walls end there.
PlotBuilder.YardChamfer = 2.5
local CHAMFER = PlotBuilder.YardChamfer
local TURN = math.pi / 4 -- the turn between a side or back wall and its cut corner

--[[
	(bigger plots) Posts by length, so a bigger grid gets more of them in
	the same rhythm (at 12 cells: the left side wall 12.55 apart along the
	pad and 14 along the yard, one pillar half way on the pad/yard wall
	either side of the gate):
	  SidePostGap   the left side wall, at most this far apart
	  BackPostGap   the pad/yard wall beyond its first pillar
	  GatePillarGap the pad/yard wall's first pillar, this far out from the
	                YardGate post (it once left room for the FOUNDRY
	                receiver's hood; it stays put at any grid size)
]]
PlotBuilder.SidePostGap = 14.5
PlotBuilder.BackPostGap = 10
PlotBuilder.GatePillarGap = 9.025

-- The posts strictly between `a` and `b` (one coordinate along a wall), at
-- most `maxGap` apart, evenly spread.
local function postsBetween(a: number, b: number, maxGap: number): { number }
	local n = math.ceil((b - a) / maxGap)
	local list = {}
	for i = 1, n - 1 do
		table.insert(list, (a * (n - i) + b * i) / n)
	end
	return list
end

-- The pad/yard wall's pillars between the YardGate post and the corner post,
-- plot-local |x| (the same on both sides, nearest the gate first).
function PlotBuilder.backPillars(): { number }
	local gate = BaseLayout.YardGate
	local first = math.abs(gate.CenterX + gate.Width / 2 + GATE_POST_CAP / 2) + PlotBuilder.GatePillarGap
	local list = { first }
	for _, x in postsBetween(first, PILLAR_LINE, PlotBuilder.BackPostGap) do
		table.insert(list, x)
	end
	return list
end

--[[
	The pad's border and the long side walls: front walls with the road
	entrance between two lamp posts, the side walls from the road corner
	to the yard's back corner, the wall between pad and yard with the
	YardGate. Returns the left entrance post's lamp ball (it carries the
	plot's only light).
	Posts stand every ~12.5 studs (SidePostGap at most) on the left side
	wall only (on purpose): neighbouring plots share a 5.8-stud alley, so
	every alley has one posted wall (this plot's left side) facing a plain
	one (the neighbour's right side, with its corner posts).
]]
local function padWalls(plot: Model, cf: CFrame): Part?
	local m = model("Walls", plot)
	local k = PLOT_WALL
	local L, Pl = WALL_LINE, PILLAR_LINE
	local gate = BaseLayout.YardGate
	-- the entrance and gate posts' caps (2.1) line up with the openings' edges
	local postCap = GATE_POST_CAP
	local sideEnd = PlotBuilder.BackWallZ - CHAMFER
	local leftLamp: Part? = nil
	for _, s in { -1, 1 } do
		-- corner posts: the road corner and the pad/yard junction
		post(m, cf, k, Vector3.new(s * Pl, 0, -Pl))
		post(m, cf, k, Vector3.new(s * Pl, 0, Pl))
		if s < 0 then
			-- along the pad, then along the yard up to its cut corner
			local zs = postsBetween(-Pl, Pl, PlotBuilder.SidePostGap)
			for _, z in postsBetween(Pl, sideEnd, PlotBuilder.SidePostGap) do
				table.insert(zs, z)
			end
			for _, z in zs do
				post(m, cf, k, Vector3.new(s * Pl, 0, z))
			end
		end
		-- the long side wall, road corner .. the yard's back corner
		wall(m, cf, k, Vector3.new(s * L, 0, -Pl), Vector3.new(s * L, 0, sideEnd), nil, TURN)
		-- front: corner .. the entrance post (a slate foot and a lamp)
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = post(m, cf, k, Vector3.new(s * ex, 0, -Pl), { D = 1.8, Top = 3.7, Foot = true, Lamp = true })
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, Vector3.new(s * Pl, 0, -L), Vector3.new(s * ex, 0, -L))
		-- back: the YardGate post (a lamp), the pillars (backPillars) and the
		-- wall to the junction
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		post(m, cf, k, Vector3.new(gx, 0, Pl), { D = 1.8, Top = 3.7, Lamp = true })
		for _, x in PlotBuilder.backPillars() do
			post(m, cf, k, Vector3.new(s * x, 0, Pl))
		end
		wall(m, cf, k, Vector3.new(gx, 0, L), Vector3.new(s * Pl, 0, L))
	end
	return leftLamp
end

---------------------------------------------------------------- yard pieces

local function ground(yard: Model, cf: CFrame)
	local rect = BaseLayout.Yard
	local c = rect.Center
	local pad =
		Geo.block(yard, cf * CFrame.new(c.X, -0.6, c.Z), Vector3.new(rect.Size.X, 1.2, rect.Size.Z), LAWN, nil, { CanTouch = false })
	pad.Name = "Ground"
	-- gravel paths: along the front (pen gate .. podiums) and the middle lane
	-- to the train stop
	local pen = BaseLayout.Pen.Area
	local penFront = pen.Center.Z - pen.Size.Z / 2
	local lastPodium = BaseLayout.Podiums[#BaseLayout.Podiums]
	local apronMinX = pen.Center.X - 3
	local apronMaxX = lastPodium.Center.X + lastPodium.Size.X / 2 + 0.5
	local yardFront = BaseLayout.YardZ0
	local apron = Geo.block(
		yard,
		cf * CFrame.new((apronMinX + apronMaxX) / 2, 0.03, (yardFront + penFront - 0.2) / 2),
		Vector3.new(apronMaxX - apronMinX, 0.06, penFront - 0.2 - yardFront),
		GRAVEL,
		nil,
		GHOST
	)
	apron.Name = "Path"
	local laneMinZ = penFront - 0.2
	local laneMaxZ = BaseLayout.TrainStop.Center.Z - BaseLayout.TrainStop.Size.Z / 2 + 0.2
	local lane = Geo.block(
		yard,
		cf * CFrame.new(0.7, 0.03, (laneMinZ + laneMaxZ) / 2),
		Vector3.new(2.4, 0.06, laneMaxZ - laneMinZ),
		GRAVEL,
		nil,
		GHOST
	)
	lane.Name = "Path"
end

-- The yard's back border (its long side walls belong to the pad's Walls):
-- a 45-degree corner run at each back corner and the back walls up to a
-- post at each side of the train stop opening.
local function fence(yard: Model, cf: CFrame)
	local f = model("Fence", yard)
	local k = PLOT_WALL
	local L = WALL_LINE
	local backZ = PlotBuilder.BackWallZ
	local gapX = BaseLayout.TrainStop.Size.X / 2 + 0.5 + 1.6 / 2
	for _, s in { -1, 1 } do
		local turnA = Vector3.new(s * L, 0, backZ - CHAMFER)
		local turnB = Vector3.new(s * (L - CHAMFER), 0, backZ)
		wall(f, cf, k, turnA, turnB, TURN, TURN)
		wall(f, cf, k, turnB, Vector3.new(s * gapX, 0, backZ), TURN, nil)
		post(f, cf, k, Vector3.new(s * gapX, 0, backZ))
	end
end

--[[
	The Ore Pen: a slate tray floor with painted tile seams, low soft walls
	on its edge (inset half a wall), split by the gate: two round posts with
	glowing bands carry the ORE PEN sign. The yard's side wall closes it on
	the outside when the pen touches it (a slate ramp there rolls ore that
	lands beside the intake back in). What services use: the invisible
	`Intake` box and its `Prompt` attachment at Pen.PromptPoint.
]]
local function pen(yard: Model, cf: CFrame)
	local info = BaseLayout.Pen
	local area = info.Area
	local m = model("Pen", yard)
	local k = PEN_WALL
	local cx, cz = area.Center.X, area.Center.Z
	local gateX = info.PromptPoint.X
	local gateHalf = 2.5
	-- the outer side (x0) is the yard's side wall when the pen touches it
	local yardSide = -WALL_LINE
	local outerInside = yardSide + PLOT_WALL.Body / 2 -- inner face of the yard wall's body
	local inset = k.Plinth / 2
	local x0, x1 = cx - area.Size.X / 2 + inset, cx + area.Size.X / 2 - inset
	local z0, z1 = cz - area.Size.Z / 2 + inset, cz + area.Size.Z / 2 - inset
	local closedByYard = x0 - yardSide < 3
	local wallX0 = if closedByYard then yardSide else x0

	-- the floor: a slate tray with painted tile seams (no collision: the lawn is the ground)
	local floorX0 = if closedByYard then outerInside + 0.1 else x0 + 0.3
	local floorX1 = x1 - 0.3
	local floor = SoftKit.part(
		m,
		cf * CFrame.new((floorX0 + floorX1) / 2, 0.1, cz),
		Vector3.new(floorX1 - floorX0, 0.2, area.Size.Z - 1.4),
		PEN_FLOOR,
		TINY,
		"Floor"
	)
	local seams: { SoftKit.Paint } = {}
	local cols, rows = 8, 6
	for i = 1, cols - 1 do
		table.insert(seams, { x = i / cols - 0.002, y = 0, w = 0.004, h = 1, color = P.Frame })
	end
	for j = 1, rows - 1 do
		table.insert(seams, { x = 0, y = j / rows - 0.003, w = 1, h = 0.006, color = P.Frame })
	end
	SoftKit.paint(floor, Enum.NormalId.Top, seams)
	if closedByYard then
		-- the ramp against the yard wall: ore that lands beside the intake rolls back in
		local intakeMinX = info.Intake.Center.X - info.Intake.Size.X / 2
		local run = intakeMinX + 0.1 - outerInside
		local length = z1 - z0 - k.Plinth
		SoftKit.wedge(
			m,
			cf * CFrame.new(outerInside + run / 2, 0.65, cz) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(length, 1.3, run),
			"Frame",
			FENCE,
			"Bank"
		)
	else
		post(m, cf, k, Vector3.new(x0, 0, z0), { D = 1.2, Top = 2.1 })
		post(m, cf, k, Vector3.new(x0, 0, z1), { D = 1.2, Top = 2.1 })
		wall(m, cf, k, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	end
	wall(m, cf, k, Vector3.new(wallX0, 0, z1), Vector3.new(x1, 0, z1))
	-- the inner side wall reaches over both corners (square corners)
	wall(m, cf, k, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), math.pi / 2, math.pi / 2)
	-- the gate: two round posts with glowing bands carry the sign, high over the ores
	local postX = gateHalf + 0.8
	local gateTop = area.Size.Y + 2.4
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		post(m, cf, k, Vector3.new(px, 0, z0), { D = 1.3, Top = gateTop, Band = 2.55 })
		local cornerX = if side < 0 then wallX0 else x1
		wall(m, cf, k, Vector3.new(cornerX, 0, z0), Vector3.new(px, 0, z0))
	end
	-- the ORE PEN board stands upright on the two gate posts' caps, facing the yard path (both faces)
	SoftKit.sign(m, cf * CFrame.new(gateX, gateTop + 0.42 + 0.85, z0 - 0.1), Vector3.new(postX * 2 + 1.4, 1.5, 0.3), "ORE PEN", true)

	-- what services use: the intake box and the prompt point
	local box = info.Intake
	local intake = Geo.block(
		m,
		cf * CFrame.new(box.Center.X, (box.Size.Y - 1) / 2, box.Center.Z),
		Vector3.new(box.Size.X, box.Size.Y + 1, box.Size.Z),
		P.Floor,
		nil,
		{
			CanTouch = false,
			CanQuery = false,
			CanCollide = false,
			CastShadow = false,
			Transparency = 1,
		}
	)
	intake.Name = "Intake"
	local localPrompt = intake.CFrame:ToObjectSpace(cf * CFrame.new(info.PromptPoint))
	attachment(intake, "Prompt", localPrompt)
end

-- A padlock floating where the ore would be, facing the yard gate (-Z): an
-- orange body, a slate shackle, a dark keyhole slot and a red "locked"
-- light, its only glow. Every part is opaque: PodiumService hides the lock
-- by making its parts transparent.
local function lock(parent: Instance, cf: CFrame): Model
	local m = model("Lock", parent)
	SoftKit.part(m, cf, Vector3.new(1.5, 1.2, 0.62), "Trim", TINY, "Body")
	for _, side in { -1, 1 } do
		SoftKit.part(m, cf * CFrame.new(side * 0.46, 0.88, 0), Vector3.new(0.32, 0.56, 0.32), "Frame", TINY)
	end
	SoftKit.cylX(m, cf * CFrame.new(0, 1.16, 0), 1.24, 0.32, "Frame", TINY)
	SoftKit.part(m, cf * CFrame.new(0, 0.1, -0.32), Vector3.new(0.2, 0.46, 0.06), "Dark", TINY)
	-- the red "locked" light along the bottom of the body
	SoftKit.glow(SoftKit.part(m, cf * CFrame.new(0, -0.4, -0.31), Vector3.new(1.1, 0.2, 0.06), LOCKED_RED, TINY, "LockedLight"))
	return m
end

-- The podium's holo-ring (plot-local, around the ore): a level octagon of
-- thin cyan neon bars, the same on every slot and turned like the
-- pedestal's octagons (a flat faces the yard gate). Centre height, radius
-- of the bar centre lines and bar thickness: the inner edge clears the
-- widest ore at the ring's height (about 1.82 studs from the axis) and
-- the top stays below PodiumService's income tag.
-- (round 2: thinner, a little higher and tighter: it hugs the ore instead of
-- reading as a debug outline over the neighbours)
-- (round 3: thinner, tighter and see-through: the big hexagons read as
-- gizmos over the yard)
-- (perf pass 1: opaque, so the 192 bars of the 8 bases leave the
-- transparent pass; a darker, less saturated blue (holoTone) gives the
-- same soft glow the 0.4 see-through bars had, nobody looks through a
-- 0.09-stud bar)
PlotBuilder.HoloRing = { Y = 5.2, Radius = 1.88, Bar = 0.09, Sides = 6, Transparency = 0 }

-- The holo-ring as a closed polygon of bars (`Sides` bars, each tangent to
-- the circle at its middle): returns the bar CFrames and the bar size
-- (around the podium's `base` frame, on the ground at the podium's axis).
function PlotBuilder.holoRingBars(base: CFrame): ({ CFrame }, Vector3)
	local ring = PlotBuilder.HoloRing
	local center = base * CFrame.new(0, ring.Y, 0)
	local n = ring.Sides
	-- long enough for the outer corners to meet
	local length = 2 * (ring.Radius + ring.Bar / 2) * math.tan(math.pi / n)
	local list = {}
	for i = 0, n - 1 do
		table.insert(list, center * CFrame.Angles(0, i * 2 * math.pi / n, 0) * CFrame.new(0, 0, -ring.Radius))
	end
	return list, Vector3.new(length, ring.Bar, ring.Bar)
end

--[[
	Showpiece ore podium in style A: a round slate `Base` (the PrimaryPart)
	with a glowing ring, a cream drum (`Column`) with an orange band, the
	glowing `Rim` under the slate `Top` (it reaches 0.2 past the plate, so
	the glowing ring is the top's edge; dull on locked slots), and the ore
	floating above it inside a level holo-ring of opaque soft cyan bars. An
	invisible `Hover` box around the ore catches the mouse for
	PodiumController (the ore itself is not queryable). Locked slots: the
	`Lock` where the ore floats and the "100 R$" `PricePlate` on the base,
	and no holo-ring, not even once the Podiums perk opens them (the map's
	phone budget: the lit gold rim shows an open slot). 13 parts (15 on the
	paid slots). The Top is in the slightly lighter Pipe slate:
	ArtifactService tells the skin roles of Base, Column and Top apart by
	their own colours.
]]
local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local baseH = 0.6
	local plinth = SoftKit.cylUp(m, base * CFrame.new(0, baseH / 2, 0), baseH, 3.8, "Frame", SOLID, "Base")
	SoftKit.cylUp(m, base * CFrame.new(0, baseH * 0.5, 0), 0.09, 3.86, "Neon", TINY, "BaseGlow")
	local topH, topW = 0.35, 3.5 -- (the holo-ring is about 1.2 x the top)
	local topY = 3.35 -- top plate centre
	local rimH = 0.24
	local rimTop = topY - topH / 2 + 0.02
	local drumBottom, drumTop = baseH, rimTop - rimH
	SoftKit.cylUp(m, base * CFrame.new(0, (drumBottom + drumTop) / 2, 0), drumTop - drumBottom, 2.5, "Body", SOLID, "Column")
	SoftKit.cylUp(m, base * CFrame.new(0, drumBottom + 0.5, 0), 0.34, 2.62, "Trim", TRIM, "Band")
	-- the Rim keeps its colours: PodiumService repaints it (RimGold / RimLocked)
	local rim =
		SoftKit.cylUp(m, base * CFrame.new(0, rimTop - rimH / 2, 0), rimH, topW + 0.4, if locked then RIM_LOCKED else RIM_GOLD, TINY, "Rim")
	rim.Material = if locked then Enum.Material.SmoothPlastic else NEON
	local top = SoftKit.cylUp(m, base * CFrame.new(0, topY, 0), topH, topW, "Pipe", SOLID, "Top")
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CFrame.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CFrame.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	-- the holo-ring around the floating ore (a paid slot shows the padlock there, and its gold rim once open)
	if not locked then
		local bars, barSize = PlotBuilder.holoRingBars(base)
		for _, barCF in bars do
			local bar = SoftKit.glow(SoftKit.part(m, barCF, barSize, HOLO, TINY, "HoloRing"))
			bar.Transparency = PlotBuilder.HoloRing.Transparency
		end
	end
	-- invisible hover box around the ore: the mouse over the ore finds the podium
	local hoverH = 3
	local hover =
		Geo.block(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + hoverH / 2, 0), Vector3.new(3.4, hoverH, 3.4), P.Frame, nil, {
			CanTouch = false,
			CanCollide = false,
			CastShadow = false,
			Transparency = 1,
		})
	hover.Name = "Hover"
	if locked then
		local padlock = lock(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + 0.8, 0))
		-- the price label stands almost upright on the base in front of the drum
		-- (faces the yard gate); its green neon frame is part of the lock, so
		-- PodiumService hides it with the lock
		local plateCF = base * CFrame.new(0, baseH + 0.47, -1.45) * CFrame.Angles(0.12, 0, 0)
		local plate = SoftKit.part(m, plateCF, Vector3.new(2.2, 0.9, 0.1), "Screen", TINY, "PricePlate")
		local gui = SoftKit.label(plate, Enum.NormalId.Front, "100 R$", ROBUX_GREEN, 0)
		local label = gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = rgb(10, 30, 16)
		end
		SoftKit.glow(
			SoftKit.part(padlock, plateCF * CFrame.new(0, 0, 0.06), Vector3.new(2.34, 1.04, 0.06), ROBUX_GREEN, TINY, "PriceFrame")
		)
	end
	m.PrimaryPart = plinth
end

--[[
	The pad of the yard's own Cleaning Station (owner 2026-10-25: "the same ground as
	under the ores, not grass"): the Ore Pen's slate tray with its painted tile seams
	under the station's footprint (BaseLayout.CleaningStation, built there at runtime
	by CleaningService for the plot's owner), a stud round it and the spot in front
	where you stand to clean (the station's front faces -Z at R 0). One part, no
	collision (the lawn stays the ground).
]]
PlotBuilder.StationPad = { Margin = 1, Front = 4 }
local function stationPad(yard: Model, cf: CFrame)
	local area = BaseLayout.CleaningStation.Area
	local pad = PlotBuilder.StationPad
	local sizeX = area.Size.X + 2 * pad.Margin
	local sizeZ = area.Size.Z + 2 * pad.Margin + pad.Front
	local centerZ = area.Center.Z - pad.Front / 2
	local floor =
		SoftKit.part(yard, cf * CFrame.new(area.Center.X, 0.1, centerZ), Vector3.new(sizeX, 0.2, sizeZ), PEN_FLOOR, TINY, "StationFloor")
	local seams: { SoftKit.Paint } = {}
	local cols, rows = 4, 4
	for i = 1, cols - 1 do
		table.insert(seams, { x = i / cols - 0.003, y = 0, w = 0.006, h = 1, color = P.Frame })
	end
	for j = 1, rows - 1 do
		table.insert(seams, { x = 0, y = j / rows - 0.003, w = 1, h = 0.006, color = P.Frame })
	end
	SoftKit.paint(floor, Enum.NormalId.Top, seams)
end

--[[
	Train stop in style A: a light metal platform (the plot floor's plate)
	with a glowing strip along its yard face and a striped safety edge on
	the rail side, a slate step, the slate TRAIN STOP sign (both faces: the
	yard and the trains) on two round cream posts beside its ends, and a
	slate lamp post with a glowing lamp ball (neon only, lights are budgeted
	on mobile). And a short track piece on the rail line at the platform's
	far end (track-detailed: dense orange sleepers under pale steel rails)
	ending in an open buffer stop (two sloped struts, a red beam, two
	buffers down the rails): the `Track` model with the attribute
	`RailwayPlaceholder`, which the railway step replaces with the through
	line (its `BufferStop` would stand in the trains' way).
]]
local function trainStop(yard: Model, cf: CFrame)
	local rect = BaseLayout.TrainStop
	local m = model("TrainStop", yard)
	local c = rect.Center
	local platformH = 1
	local bottom = -0.4
	local platform = SoftKit.part(
		m,
		cf * CFrame.new(c.X, (bottom + platformH) / 2, c.Z),
		Vector3.new(rect.Size.X, platformH - bottom, rect.Size.Z),
		PLOT_PLATE,
		SOLID,
		"Platform"
	)
	platform.Reflectance = 0.04
	-- a glowing strip along the yard face, the striped safety edge on the rail side
	local frontZ = c.Z - rect.Size.Z / 2
	SoftKit.part(
		m,
		cf * CFrame.new(c.X, platformH * 0.5, frontZ - 0.03),
		Vector3.new(rect.Size.X - 1, 0.14, 0.06),
		"Neon",
		TINY,
		"PlatformGlow"
	)
	local railSide = c.Z + rect.Size.Z / 2
	local edge = SoftKit.part(
		m,
		cf * CFrame.new(c.X, platformH + 0.03, railSide - 0.35),
		Vector3.new(rect.Size.X, 0.06, 0.5),
		"Trim",
		TINY,
		"SafetyEdge"
	)
	SoftKit.paint(edge, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 68 } })
	SoftKit.part(m, cf * CFrame.new(0.7, 0.25, frontZ - 0.5), Vector3.new(5, 0.5, 1), "Frame", STEP, "Step")
	-- the sign on two round cream posts just beyond the board's ends
	local signZ = c.Z + 0.3
	local signW = 7.4
	for _, side in { -1, 1 } do
		local x = c.X + 5 + side * (signW / 2 + 0.45)
		SoftKit.cylUp(m, cf * CFrame.new(x, platformH + 2.65, signZ), 5.3, 0.8, "Body", FENCE, "SignPost")
	end
	SoftKit.sign(m, cf * CFrame.new(c.X + 5, platformH + 4.2, signZ), Vector3.new(signW + 0.2, 1.6, 0.26), "TRAIN STOP", true)
	-- the lamp post: a slate foot and pole, a glowing lamp ball on top
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ)
	local poleH = 5.4
	SoftKit.cylUp(m, lamp * CFrame.new(0, 0.3, 0), 0.6, 0.9, "Frame", THIN)
	SoftKit.cylUp(m, lamp * CFrame.new(0, poleH / 2, 0), poleH, 0.36, "Frame", THIN, "LampPost")
	SoftKit.glow(SoftKit.ball(m, (lamp * CFrame.new(0, poleH + 0.3, 0)).Position, 0.7, SoftKit.Lamp, TINY, "Lamp"))
	-- the track piece at the platform's +X end (track-detailed has no ballast): six sleepers, two rails
	local track = model("Track", m)
	track:SetAttribute("RailwayPlaceholder", true)
	local railZ = BaseLayout.RailZ
	local stopX = c.X + rect.Size.X / 2 + 2 -- the buffer stop, just past the platform's end
	local trackL = 14
	local trackX = stopX - trackL / 2
	local gauge = 2.5
	local sleepers = 6
	local pitch = 2.3
	for i = 0, sleepers - 1 do
		local x = stopX - 1.4 - i * pitch
		Geo.block(track, cf * CFrame.new(x, 0.12, railZ), Vector3.new(1.1, 0.24, 4.4), SLEEPER, nil, THIN)
	end
	for _, side in { -1, 1 } do
		Geo.block(track, cf * CFrame.new(trackX, 0.42, railZ + side * gauge / 2), Vector3.new(trackL, 0.36, 0.36), RAIL_STEEL, nil, THIN)
	end
	-- open buffer stop at the +X end: two sloped struts, a red beam facing the track,
	-- two buffers pointing down the rails
	local buffer = model("BufferStop", track)
	local stop = cf * CFrame.new(stopX, 0, railZ)
	local beamH, beamY = 0.8, 1.25
	for _, side in { -1, 1 } do
		-- wedge: tall side at the beam, sloping down away from the track
		Geo.wedge(
			buffer,
			stop * CFrame.new(1.3, 0.8, side * gauge / 2) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(0.45, 1.6, 1.8),
			HOUSING,
			nil,
			TRIM
		)
	end
	Geo.block(buffer, stop * CFrame.new(0.2, beamY, 0), Vector3.new(0.6, beamH, gauge + 1.6), C.AwningRed, nil, SOLID)
	for _, side in { -1, 1 } do
		local pad = Geo.block(buffer, stop * CFrame.new(-0.35, beamY, side * gauge / 2), Vector3.new(0.5, 0.8, 0.8), RAIL_STEEL, nil, THIN)
		pad.Shape = Enum.PartType.Cylinder
	end
end

-- The yard behind a plot (plot-local +Z side), from BaseLayout.
function PlotBuilder.buildYard(parent: Instance, cf: CFrame): Model
	local yard = model("Yard", parent)
	ground(yard, cf)
	fence(yard, cf)
	pen(yard, cf)
	for index, rect in BaseLayout.Podiums do
		podium(yard, cf, index, rect)
	end
	stationPad(yard, cf)
	trainStop(yard, cf)
	return yard
end

---------------------------------------------------------------- keep-out (decor, nodes)

-- Plot-local box of everything that belongs to a yard (the yard, the train
-- stop and the railway line just behind it).
local KEEP_MIN = Vector3.new(-BaseLayout.Yard.Size.X / 2, 0, BaseLayout.Yard.Center.Z - BaseLayout.Yard.Size.Z / 2 - 1)
local KEEP_MAX = Vector3.new(BaseLayout.Yard.Size.X / 2, 0, BaseLayout.RailZ + 3)

-- World-space bounds (flat, min/max X and Z) of one plot's yard area.
function PlotBuilder.yardBounds(plot: WorldLayout.Plot): (Vector3, Vector3)
	local cf = WorldLayout.plotCFrame(plot)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, x in { KEEP_MIN.X, KEEP_MAX.X } do
		for _, z in { KEEP_MIN.Z, KEEP_MAX.Z } do
			local p = cf:PointToWorldSpace(Vector3.new(x, 0, z))
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
	end
	return Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, maxZ)
end

local yardBoxes: { { Min: Vector3, Max: Vector3 } }? = nil

-- Is a world position (flat) inside any yard, grown by `margin` studs?
-- Trees, rocks, grass patches and ore node spawns use it to stay out.
function PlotBuilder.isInYard(position: Vector3, margin: number?): boolean
	local boxes = yardBoxes
	if not boxes then
		local list = {}
		for _, plot in WorldLayout.Plots do
			local min, max = PlotBuilder.yardBounds(plot)
			table.insert(list, { Min = min, Max = max })
		end
		boxes = list
		yardBoxes = list
	end
	local m = margin or 0
	for _, box in boxes :: { { Min: Vector3, Max: Vector3 } } do
		if position.X >= box.Min.X - m and position.X <= box.Max.X + m and position.Z >= box.Min.Z - m and position.Z <= box.Max.Z + m then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- plots

function PlotBuilder.buildPlot(parent: Instance, plot: WorldLayout.Plot, rng: Rng.Rng): Model
	local size = GameConfig.PlotCells * GameConfig.CellSize
	local half = size / 2
	local cf = WorldLayout.plotCFrame(plot)
	local m = Instance.new("Model")
	m.Name = "Plot_" .. plot.Id
	m:SetAttribute("PlotId", plot.Id)
	m:AddTag("Plot")

	-- the pad has a 1-stud cobble border around the grid for the walls
	local pad = Geo.block(m, cf * CFrame.new(0, -0.6, 0), Vector3.new(size + 2, 1.2, size + 2), PLOT_EDGE, nil, { CanTouch = false })
	pad.Name = "Pad"
	-- the build grid (owner 2026-10-17: a metal floor like the machine
	-- pictures): a dark gunmetal band exactly the grid's size shows round a
	-- light metal plate with painted tile seams and a soft checker, glowing
	-- orange strips lie on the band (all flat: tops at y <= 0.05, no
	-- collision, not raycast, so building and placement see the pad only)
	local flat = {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	}
	local band = 1.6
	local tile = Geo.block(m, cf * CFrame.new(0, -0.025, 0), Vector3.new(size, 0.07, size), PLOT_FRAME, nil, flat)
	tile.Name = "PlotTile"
	local inner = half - band
	local plate = Geo.block(m, cf * CFrame.new(0, 0.0, 0), Vector3.new(inner * 2, 0.06, inner * 2), PLOT_PLATE, nil, flat)
	plate.Name = "Plate"
	plate.Reflectance = 0.04
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Tiles"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 1
	gui.MaxDistance = 260
	gui.Parent = plate
	local cell = GameConfig.CellSize
	local n = GameConfig.PlotCells
	local function frame(x: number, y: number, w: number, h: number, color: Color3)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Parent = gui
	end
	-- cell edges in the plate's 0..1 space (the plate is the grid minus the band)
	local function at(k: number): number
		return math.clamp((-half + k * cell + inner) / (inner * 2), 0, 1)
	end
	for row = 0, n - 1 do
		for col = 0, n - 1 do
			if (row + col) % 2 == 0 then
				frame(at(col), at(row), at(col + 1) - at(col), at(row + 1) - at(row), PLOT_PLATE_ALT)
			end
		end
	end
	for k = 1, n - 1 do
		local u = at(k)
		frame(u - 0.0015, 0, 0.003, 1, PLOT_SEAM)
		frame(0, u - 0.0015, 1, 0.003, PLOT_SEAM)
	end
	-- glowing strips on the band, a little in from the walls
	local edge = half - band / 2
	for _, s in { -1, 1 } do
		local strip = Geo.block(m, cf * CFrame.new(0, 0.02, s * edge), Vector3.new(size - 6, 0.04, 0.22), PLOT_GLOW, NEON, flat)
		strip.Name = "FloorGlow"
		strip = Geo.block(m, cf * CFrame.new(s * edge, 0.02, 0), Vector3.new(0.22, 0.04, size - 6), PLOT_GLOW, NEON, flat)
		strip.Name = "FloorGlow"
	end

	-- soft walls on the border: the road entrance at the front (-Z local)
	-- between two lamp posts, the YardGate in the back wall; the plot's one light
	-- hangs in the left entrance post's lamp ball
	local entranceLamp = padWalls(m, cf)
	if entranceLamp then
		Props.pointLight(entranceLamp, Palette.LampGlow, 16, 0.8)
	end

	-- (round 3) the road-facing front: a hedge strip with flower tufts on
	-- both sides of the entrance and three lamp posts with neon heads (no
	-- lights), so the plots read as gardens of the town from the hero camera
	local frontZ = -WALL_LINE - PLOT_WALL.Plinth / 2 - 0.75
	local hedgeFrom = PlotBuilder.EntranceHalf + 2.6
	local flowers = { C.FlowerPink, C.FlowerYellow, C.FlowerWhite, C.FlowerPurple }
	for _, s in { -1, 1 } do
		local x0, x1 = hedgeFrom, half
		local hedge = Geo.block(
			m,
			cf * CFrame.new(s * (x0 + x1) / 2, 0.55, frontZ),
			Vector3.new(x1 - x0, 1.1, 1.1),
			HEDGE,
			nil,
			{ CanTouch = false, CanQuery = false, CastShadow = false }
		)
		hedge.Name = "Hedge"
		for i, f in { 0.55 } do
			local tuft = Geo.block(
				m,
				cf * CFrame.new(s * (x0 + (x1 - x0) * f), 1.25, frontZ - 0.1),
				Vector3.new(0.9, 0.35, 0.8),
				flowers[(plot.Id + i + (if s > 0 then 1 else 0)) % #flowers + 1],
				nil,
				GHOST
			)
			tuft.Name = "Flowers"
		end
	end
	for _, x in { -(half - 0.6), (hedgeFrom + half) / 2 - 3, half - 0.6 } do
		local post = Geo.block(m, cf * CFrame.new(x, 1.6, frontZ - 0.9), Vector3.new(0.4, 3.2, 0.4), Palette.WoodDark, nil, THIN)
		post.Name = "LampPost"
		local head = Geo.block(m, cf * CFrame.new(x, 3.45, frontZ - 0.9), Vector3.new(0.6, 0.5, 0.6), POST_HEAD, NEON, GHOST)
		head.Name = "LampHead"
	end

	-- name sign at the front, facing the road (slate, orange letters like the
	-- machine signs): mounted on the road face of the left front wall, its back
	-- on the round lid's front, standing up over the lid
	local railProps = { CanTouch = false, CanQuery = false }
	local signZ = -WALL_LINE - PLOT_WALL.Lid / 2 - 0.27
	local signBase = cf * CFrame.new(-(PlotBuilder.EntranceHalf + WALL_LINE) / 2, 0, signZ)
	local sign = Props.sign(m, signBase * CFrame.new(0, 3.45, 0), "Free Plot", 6.4, 2.2, P.Frame, SoftKit.Text)
	sign.Name = "PlotSign"

	-- slate banner pole rising out of the back right corner post (owner color);
	-- it reaches down past the pad so it never floats over lower ground
	local pole = cf * CFrame.new(half + 1.5, 0, half + 1.5)
	SoftKit.part(m, pole * CFrame.new(0, 5.4, 0), Vector3.new(0.5, 13.2, 0.5), "Frame", railProps)
	local banner =
		Geo.block(m, pole * CFrame.new(-1.8, 9.4, 0), Vector3.new(3.4, 4.4, 0.15), BANNER_COLORS[(plot.Id - 1) % #BANNER_COLORS + 1], nil, {
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		})
	banner.Name = "Banner"

	PlotBuilder.buildYard(m, cf)

	local machines = Instance.new("Folder")
	machines.Name = "Machines"
	machines.Parent = m

	m.PrimaryPart = pad
	m.Parent = parent
	local _ = rng
	return m
end

function PlotBuilder.build(map: Model, rng: Rng.Rng): Folder
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = map
	for _, plot in WorldLayout.Plots do
		PlotBuilder.buildPlot(plots, plot, rng)
	end
	return plots
end

return PlotBuilder
