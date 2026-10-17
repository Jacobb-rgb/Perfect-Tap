--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) that reads as a tidy garden from the lobby hero camera (a mown
	lawn with a lighter stripe per other cell row and a paving band, all flat),
	framed with the yard by low brick walls after the Kenney Graveyard Kit:
	brick-wall (stone plinth, red brick band with staggered raised brick
	pairs, a rounded stone cap: a slab overhanging both faces under a
	bullnose cylinder), brick-wall-end pillars (a stone foot and a lantern
	tucked under a dark roof plate on the road entrance posts) and mitred
	45-degree back corners (brick-wall-curve-small). The name sign hangs on
	the left front wall, a banner pole stands at the back right corner, and
	behind the pad (plot-local +Z, the sea side) lies the yard from
	BaseLayout:
	  Walls            the pad's border and the long side walls: front walls
	                   with the road entrance between two lantern posts, the
	                   side walls from the road to the yard's back corners
	                   (pillars every ~12.5 studs on the left side only, see
	                   padWalls), the wall between pad and yard with the
	                   YardGate between two posts
	  Yard.Ground      lawn pad, gravel paths
	  Yard.Fence       the yard's cut back corners and the back walls up to
	                   the train stop opening
	  Yard.Pen         the Ore Pen: lower brick walls with a bullnose cap and
	                   a gate (the yard's side wall closes it on the outside, a
	                   dirt bank there rolls ore back in), an invisible
	                   `Intake` part (BaseLayout.Pen.Intake) with a `Prompt`
	                   attachment at Pen.PromptPoint, an "ORE PEN" sign
	  Yard.Podium1..4  showpiece pedestals (Space Station table-display-planet:
	                   a two-tier bevelled octagon with blue light slits, a
	                   hexagonal pipe-ring-colored column with an orange
	                   collar, a pale top plate edged by the amber neon `Rim`,
	                   a level cyan holo-ring around the floating ore and an
	                   invisible `Hover` box for the mouse); the `Top` part
	                   holds the `OrePoint` at BaseLayout.PodiumOreHeight and
	                   the `Prompt` attachment; slots 3 and 4 have a `Lock`
	                   model where the ore floats and a "100 R$" `PricePlate`
	                   (PodiumService hides them for players with the Podiums
	                   perk and lights the rim; the plate's neon frame lives in
	                   the lock)
	  Yard.Foundry     Factory Kit placeholder ("FOUNDRY - coming soon"):
	                   machine-fortified housing with a rib and copper eaves, a
	                   deep furnace portal (ember core, molten surround, grate),
	                   a hollow hopper-square, a chimney
	  Yard.TrainStop   platform with the TRAIN STOP sign on stone posts and a
	                   lantern post, and the `Track` placeholder (a short track
	                   piece with a `BufferStop`) that the railway step replaces
	Everything decorative stays outside the 48x48 build grid, so every cell
	is free for machines. Machines are added at runtime into the plot's
	"Machines" folder by MachineService. A plot with its yard is <= 300 parts
	(300, 13 of them in the Track placeholder) and one light (8 plots).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
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
local PLOT_LAWN = rgb(90, 156, 56)
local PLOT_LAWN_STRIPE = rgb(84, 148, 53) -- mower stripes (low contrast)
local HEDGE = rgb(54, 122, 48) -- the front hedge strip along the road
local MORTAR = rgb(86, 42, 36) -- darker mortar lines in the brick band
local POST_HEAD = rgb(255, 140, 48) -- the front lamp posts' neon heads (deep amber)
local PLOT_PAVING = rgb(196, 180, 152)
local PLOT_EDGE = rgb(156, 142, 128)
local GRAVEL = rgb(214, 192, 150)
local PEN_FLOOR = rgb(156, 124, 94)
local PEN_BANK = rgb(132, 102, 76) -- the dirt bank along the yard wall inside the pen
local RIM_GOLD = rgb(226, 116, 26) -- deep amber: no white bloom over the top plate
local RIM_LOCKED = rgb(96, 88, 104)
local ROBUX_GREEN = rgb(110, 255, 140)
-- Graveyard Kit brick walls in the warm concept palette: warm pale stone, red
-- brick light enough to stay red (not maroon) on the shaded side
local WALL_STONE = rgb(160, 150, 140) -- plinths, pillar shafts: warm grey stone (no cream posts)
local WALL_CAP = rgb(180, 170, 158) -- cap slabs, pillar caps and feet
-- (the renderer and Roblox both push a saturated red to orange in full sun and to
-- maroon in shade: a dusty brick red stays brick in both)
local BRICK = rgb(132, 64, 54) -- a muted deep brick red (Brick material), no salmon rails
local BRICK_RAISED = rgb(150, 78, 66) -- raised bricks: a close, lighter tone of the band
local PILLAR_CAP = rgb(112, 106, 100) -- (round 2) a darker stone cap on the posts
local LAMP_AMBER = rgb(220, 90, 20) -- lanterns on the posts (small and deep: no white bloom)
-- Factory / Space Station metals (docs/ART_DIRECTION.md section 9)
local HOUSING = rgb(66, 72, 92) -- the foundry's gunmetal housing (concept v2 dark metal)
local HOUSING_LIGHT = rgb(90, 98, 122)
local HOUSING_DARK = rgb(58, 60, 72)
local NAVY = rgb(27, 29, 41) -- the podium's octagon step (deep gunmetal)
local SHELL = rgb(44, 48, 64) -- gunmetal Space Station panels (podium base, foundry frame)
local PODIUM_TOP = rgb(70, 76, 98) -- the podium's top plate: a dark inset in the thin glowing rim (round 2)
local PODIUM_COLUMN = rgb(66, 72, 92)
local HOLO = rgb(40, 130, 255) -- the podium's holo-ring (the lobby's Tech blue: no debug-cyan outline)
local BASE_LIGHT = rgb(40, 140, 255) -- the podium base's corner lights
local LOCK_GOLD = rgb(255, 200, 40)
local LOCK_STEEL = rgb(230, 232, 240)
local LOCKED_RED = rgb(190, 16, 16) -- deep: a bright red neon tone-maps to salmon
local RAIL_STEEL = rgb(196, 200, 214)
local SLEEPER = rgb(196, 112, 62)
local FURNACE = rgb(196, 50, 12) -- the furnace mouth's surround: dark molten orange (C.Ember, the core, tone-maps to yellow)

-- the foundry's front wall stands this far behind the front of its BaseLayout rect
local FOUNDRY_INSET = 3.5

PlotBuilder.RimGold = RIM_GOLD
PlotBuilder.RimLocked = RIM_LOCKED

-- Border walls (plot-local): the center line of the walls around the pad
-- (the pad's outer edge, |x| or |z|), pillars 0.1 further out so their caps
-- stay off the build grid, the half width of the road entrance, and the
-- back wall's line at the train stop.
PlotBuilder.WallLine = GameConfig.PlotCells * GameConfig.CellSize / 2 + 1
PlotBuilder.EntranceHalf = 10
PlotBuilder.BackWallZ = BaseLayout.Yard.Center.Z + BaseLayout.Yard.Size.Z / 2 - 0.4
local WALL_LINE = PlotBuilder.WallLine
local PILLAR_LINE = WALL_LINE + 0.1

-- part property sets
local SOLID = { CanTouch = false } -- players and items bump into it
local FENCE = { CanTouch = false, CanQuery = false }
local THIN = { CanTouch = false, CanQuery = false, CastShadow = false } -- collides, too thin for a shadow
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

-- An upright cylinder whose axis is the frame's up vector.
local function cylinder(
	parent: Instance,
	cf: CFrame,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Geo.PartProps
): Part
	local part = Geo.block(parent, cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(height, diameter, diameter), color, material, props)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- An upright regular prism with an even number of `sides` (flat-to-flat
-- `width`, a flat facing the frame's +-X) from sides/2 blocks turned in
-- equal steps (each covers two opposite flats).
local function prism(
	parent: Instance,
	cf: CFrame,
	sides: number,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	props: Geo.PartProps
): { Part }
	local parts = {}
	local n = sides // 2
	for i = 0, n - 1 do
		local strip = Geo.block(
			parent,
			cf * CFrame.Angles(0, i * math.pi / n, 0),
			Vector3.new(width, height, width * math.tan(math.pi / sides)),
			color,
			material,
			props
		)
		table.insert(parts, strip)
	end
	return parts
end

-- A board with text on a SurfaceGui facing the board's LookVector.
local function board(parent: Instance, cf: CFrame, size: Vector3, color: Color3, text: string, textColor: Color3): Part
	local part = Geo.block(parent, cf, size, color, nil, GHOST)
	part.Name = "Sign"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = gui
	return part
end

---------------------------------------------------------------- brick walls (Graveyard Kit)

--[[
	A low wall like Kenney's brick-wall: a pale stone plinth (about a quarter
	of the height), a red brick band (about half) and a rounded stone cap (a
	thin slab that overhangs both faces with a cylinder along its centre
	line, so its section reads as a bullnose; the lower pen walls have the
	bullnose alone), 4 parts per straight run (3 on the pen),
	plus raised bricks (one part pokes out of both faces): a staggered pair
	(lower and upper row, half a brick apart) or a single brick per bay.
	Pillars like brick-wall-end: a square stone shaft with a wider cap, 2
	parts (+1 for a stone foot, +2 for a lantern under a roof plate on the
	road entrance posts). A straight run goes on under the pillars that
	stand on it (their shafts are wider than the wall), so a long wall costs
	4 parts plus its pillars and bricks. Runs that meet without a pillar are
	mitred: every layer grows by its own half width * tan(turn / 2), so the
	outer faces of plinth, band, cap and bullnose meet exactly.
]]
type WallKit = {
	Plinth: number, -- plinth thickness
	Band: number, -- brick band thickness
	Bottom: number, -- plinth bottom (reaches the ground beside the raised pad)
	PlinthTop: number,
	BandTop: number,
	Cap: number, -- cap slab width (overhangs the band on both faces)
	CapH: number, -- cap slab height (0: no slab, the bullnose alone is the cap)
	Round: number, -- diameter of the bullnose cylinder on the cap
	RoundY: number, -- its axis above the band's top (the slab's centre when there is a slab)
	Pillar: number, -- pillar shaft width
	PillarTop: number,
	PillarCap: number, -- pillar cap width
	PillarCapH: number,
}

-- proportions of brick-wall: plinth ~1/4, brick band ~1/2, rounded cap ~1/4 of the height
local PLOT_WALL: WallKit = {
	Plinth = 1.3,
	Band = 1.0,
	Bottom = -0.4,
	PlinthTop = 0.6,
	BandTop = 1.95,
	Cap = 1.4,
	CapH = 0.3,
	Round = 1.0,
	RoundY = 0.15,
	Pillar = 1.6,
	PillarTop = 3.0,
	PillarCap = 2.05,
	PillarCapH = 0.45,
}

PlotBuilder.WallBand = PLOT_WALL.Band

local PEN_WALL: WallKit = {
	Plinth = 0.95,
	Band = 0.7,
	Bottom = -0.2,
	PlinthTop = 0.42,
	BandTop = 1.32,
	Cap = 1.0,
	CapH = 0,
	Round = 1.0,
	RoundY = 0.12,
	Pillar = 1.15,
	PillarTop = 2.1,
	PillarCap = 1.45,
	PillarCapH = 0.35,
}

type WallOpts = {
	-- distances from `a` where pillars stand on the run: the bays between
	-- them (and the run's ends) get the raised bricks
	Stops: { number }?,
	-- raised bricks per bay, bay by bay from `a` (the last entry repeats):
	-- 2 = a staggered pair, 1 = one brick (rows alternate), 0 = none; nil: none
	Bricks: { number }?,
	-- the turn (radians) to the run that meets this one at `a` / `b` without a pillar
	TurnA: number?,
	TurnB: number?,
	-- (round 3) two darker mortar lines along the brick band (both faces)
	Mortar: boolean?,
}

-- One straight wall from a to b (plot-local, y ignored).
local function wall(parent: Instance, cf: CFrame, kit: WallKit, a: Vector3, b: Vector3, opts: WallOpts?)
	local o: WallOpts = opts or {}
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.05 then
		return
	end
	local frame = cf * CFrame.lookAt(flatA, flatB) -- `a` at the origin, the run along the frame's -Z
	local tanA, tanB = math.tan((o.TurnA or 0) / 2), math.tan((o.TurnB or 0) / 2)
	-- one layer of the run, mitred at both ends for its own half width
	local function layer(width: number, y: number, height: number, color: Color3, round: boolean?, material: Enum.Material?): Part
		local extA, extB = width / 2 * tanA, width / 2 * tanB
		local at = frame * CFrame.new(0, y, -(length + extB - extA) / 2)
		local full = length + extA + extB
		if round then
			-- a cylinder along the run (a Roblox cylinder's axis is its X)
			local part = Geo.block(parent, at * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(full, width, width), color, nil, FENCE)
			part.Shape = Enum.PartType.Cylinder
			return part
		end
		return Geo.block(parent, at, Vector3.new(width, height, full), color, material, FENCE)
	end
	local plinthH = kit.PlinthTop - kit.Bottom
	layer(kit.Plinth, kit.Bottom + plinthH / 2, plinthH, WALL_STONE)
	local bandH = kit.BandTop - kit.PlinthTop
	layer(kit.Band, kit.PlinthTop + bandH / 2, bandH, BRICK, false, Enum.Material.Brick)
	if kit.CapH > 0 then
		local cap = layer(kit.Cap, kit.BandTop + kit.CapH / 2, kit.CapH, WALL_CAP)
		cap.Name = "Cap"
	end
	-- (round 3) a square stone coping along the run's centre line (the round
	-- grey bullnose read as a plastic pipe)
	local copingH = kit.Round * 0.55
	local copingY = kit.BandTop + math.max(kit.CapH, 0) + copingH / 2 - 0.02
	local round = layer(kit.Round + 0.1, copingY, copingH, WALL_CAP)
	round.Name = "CapRound"
	if o.Mortar then
		for _, f in { 0.36, 0.68 } do
			local line = layer(kit.Band + 0.05, kit.PlinthTop + bandH * f, 0.09, MORTAR)
			line.Name = "Mortar"
			line.CanCollide = false
			line.CastShadow = false
		end
	end
	local perBay = o.Bricks
	if not perBay or #perBay == 0 then
		return
	end
	-- raised bricks, bay by bay
	local stops = { 0, length }
	local extra: { number } = o.Stops or {}
	for _, d in extra do
		table.insert(stops, d)
	end
	table.sort(stops)
	local brickH = math.min(0.42, bandH * 0.36)
	local brickL = math.min(1.3, kit.Band * 1.6)
	local size = Vector3.new(kit.Band + 0.24, brickH, brickL)
	local lowY, highY = kit.PlinthTop + bandH * 0.3, kit.PlinthTop + bandH * 0.7
	local function brick(d: number, y: number)
		local raised = Geo.block(parent, frame * CFrame.new(0, y, -d), size, BRICK_RAISED, Enum.Material.Brick, GHOST)
		raised.Name = "Brick"
	end
	local count = 0
	for i = 1, #stops - 1 do
		local d0, d1 = stops[i], stops[i + 1]
		local n = perBay[math.min(i, #perBay)]
		if d1 - d0 >= 3.5 and n > 0 then
			local mid = (d0 + d1) / 2
			count += 1
			if n >= 2 then
				-- a little running bond: lower and upper brick half a brick apart
				local flip = if count % 2 == 0 then 1 else -1
				brick(mid - flip * brickL / 2, lowY)
				brick(mid + flip * brickL / 2, highY)
			else
				brick(mid, if count % 2 == 0 then highY else lowY)
			end
		end
	end
end

type PillarOpts = { Width: number?, Cap: number?, Top: number?, Lamp: boolean?, Foot: boolean? }

-- A square stone pillar with a cap; returns the lantern's roof plate on top, if any
-- (it carries the light: from there it doesn't burn the pale cap white).
local function pillar(parent: Instance, cf: CFrame, kit: WallKit, at: Vector3, opts: PillarOpts?): Part?
	local o: PillarOpts = opts or {}
	local width = o.Width or kit.Pillar
	local capWidth = o.Cap or kit.PillarCap
	local top = o.Top or kit.PillarTop
	local height = top - kit.Bottom
	local shaft =
		Geo.block(parent, cf * CFrame.new(at.X, kit.Bottom + height / 2, at.Z), Vector3.new(width, height, width), WALL_STONE, nil, FENCE)
	shaft.Name = "Pillar"
	Geo.block(
		parent,
		cf * CFrame.new(at.X, top + kit.PillarCapH / 2, at.Z),
		Vector3.new(capWidth, kit.PillarCapH, capWidth),
		PILLAR_CAP,
		nil,
		if capWidth * capWidth * kit.PillarCapH < 1 then THIN else FENCE
	)
	if o.Foot then
		-- brick-wall-end's wider stone foot
		local footTop = kit.PlinthTop * 0.85
		Geo.block(
			parent,
			cf * CFrame.new(at.X, (kit.Bottom + footTop) / 2, at.Z),
			Vector3.new(width + 0.3, footTop - kit.Bottom, width + 0.3),
			WALL_CAP,
			nil,
			FENCE
		)
	end
	if o.Lamp then
		-- a little lantern (Graveyard lightpost): a small deep-amber glow tucked
		-- 0.15 under a dark roof plate, so it never blooms into a white blob
		local capTop = top + kit.PillarCapH
		local lamp = Geo.block(parent, cf * CFrame.new(at.X, capTop + 0.3, at.Z), Vector3.new(0.36, 0.6, 0.36), LAMP_AMBER, NEON, GHOST)
		lamp.Name = "Lamp"
		local roof = Geo.block(parent, cf * CFrame.new(at.X, capTop + 0.55, at.Z), Vector3.new(0.9, 0.2, 0.9), HOUSING_DARK, nil, GHOST)
		roof.Name = "LampRoof"
		return roof
	end
	return nil
end

-- The yard's back corners are cut at 45 degrees (brick-wall-curve-small),
-- this far along both walls; the long side walls end there.
PlotBuilder.YardChamfer = 2.5
local CHAMFER = PlotBuilder.YardChamfer
local TURN = math.pi / 4 -- the turn between a side or back wall and its cut corner

--[[
	The pad's border and the long side walls: front walls with the road
	entrance between two lantern posts, the side walls from the road corner
	to the yard's back corner, the wall between pad and yard with the
	YardGate. Returns the left entrance lantern's roof (it carries the
	plot's only light).
	Pillars stand every ~12.5 studs on the left side wall only (on purpose):
	neighbouring plots share a 5.8-stud alley, so every alley has one
	pillared wall (this plot's left side) facing a plain one (the
	neighbour's right side, with its corner pillars and brick pairs).
	Pillars on both walls would double the rhythm across the alley and cost
	8 more parts per plot, which the 300-part plot budget doesn't have.
]]
local function padWalls(plot: Model, cf: CFrame): Part?
	local m = model("Walls", plot)
	local k = PLOT_WALL
	local L, P = WALL_LINE, PILLAR_LINE
	local gate = BaseLayout.YardGate
	-- gate posts: their caps line up with the openings' edges
	local postWidth, postCap, postTop = 1.8, 2.1, 3.7
	local post: PillarOpts = { Width = postWidth, Cap = postCap, Top = postTop, Lamp = true, Foot = true }
	local sideEnd = PlotBuilder.BackWallZ - CHAMFER
	local leftLamp: Part? = nil
	for _, s in { -1, 1 } do
		-- corner pillars: the road corner and the pad/yard junction
		pillar(m, cf, k, Vector3.new(s * P, 0, -P))
		pillar(m, cf, k, Vector3.new(s * P, 0, P))
		-- the long side wall, road corner .. the yard's back corner
		local stops = { P + P }
		if s < 0 then
			for _, z in { -P / 2, 0, P / 2, (P + sideEnd) / 2 } do
				pillar(m, cf, k, Vector3.new(s * P, 0, z))
				table.insert(stops, z + P)
			end
		end
		wall(m, cf, k, Vector3.new(s * L, 0, -P), Vector3.new(s * L, 0, sideEnd), {
			Stops = stops,
			-- pairs on the pad's bays, single bricks beside the yard (none behind the foundry)
			Bricks = if s < 0 then { 2, 2, 2, 2, 1 } else { 2, 0 },
			TurnB = TURN,
		})
		-- front: corner .. the entrance post
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = pillar(m, cf, k, Vector3.new(s * ex, 0, -P), post)
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, Vector3.new(s * P, 0, -L), Vector3.new(s * ex, 0, -L), { Bricks = { 2 }, Mortar = true })
		-- back: the YardGate post, a pillar half way and the wall to the junction
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		pillar(m, cf, k, Vector3.new(gx, 0, P), { Width = postWidth, Cap = postCap, Top = postTop })
		local midX = (math.abs(gx) + P) / 2
		pillar(m, cf, k, Vector3.new(s * midX, 0, P))
		wall(m, cf, k, Vector3.new(gx, 0, L), Vector3.new(s * P, 0, L), { Stops = { midX - math.abs(gx) }, Bricks = { 1 } })
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
	-- gravel paths: along the front (pen gate .. podiums), the middle lane to
	-- the train stop, and the apron in front of the foundry
	local pen = BaseLayout.Pen.Area
	local penFront = pen.Center.Z - pen.Size.Z / 2
	local lastPodium = BaseLayout.Podiums[#BaseLayout.Podiums]
	local apronMinX = pen.Center.X - 3
	local apronMaxX = lastPodium.Center.X + lastPodium.Size.X / 2 + 0.5
	local apron = Geo.block(
		yard,
		cf * CFrame.new((apronMinX + apronMaxX) / 2, 0.03, (25 + penFront - 0.2) / 2),
		Vector3.new(apronMaxX - apronMinX, 0.06, penFront - 0.2 - 25),
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
	local foundry = BaseLayout.Foundry
	local slabFront = foundry.Center.Z - foundry.Size.Z / 2 + FOUNDRY_INSET - 1.5
	local foundryApron = Geo.block(
		yard,
		cf * CFrame.new((1.9 + foundry.Center.X + 2.5) / 2, 0.03, slabFront - 2.6),
		Vector3.new(foundry.Center.X + 2.5 - 1.9, 0.06, 5.2),
		GRAVEL,
		nil,
		GHOST
	)
	foundryApron.Name = "Path"
	-- (round 3) a gravel walk along the podium row to the foundry's apron
	local podiumBack = lastPodium.Center.Z + lastPodium.Size.Z / 2
	local walkZ0, walkZ1 = podiumBack + 0.2, slabFront - 5.2
	if walkZ1 - walkZ0 > 0.6 then
		local walk = Geo.block(
			yard,
			cf * CFrame.new((1.9 + apronMaxX) / 2, 0.03, (walkZ0 + walkZ1) / 2),
			Vector3.new(apronMaxX - 1.9, 0.06, walkZ1 - walkZ0),
			GRAVEL,
			nil,
			GHOST
		)
		walk.Name = "Path"
	end
end

-- The yard's back border (its long side walls belong to the pad's Walls):
-- a 45-degree corner run at each back corner (brick-wall-curve-small) and
-- the back walls up to a pillar at each side of the train stop opening.
local function fence(yard: Model, cf: CFrame)
	local f = model("Fence", yard)
	local k = PLOT_WALL
	local L = WALL_LINE
	local backZ = PlotBuilder.BackWallZ
	local gapX = BaseLayout.TrainStop.Size.X / 2 + 0.5 + k.Pillar / 2
	for _, s in { -1, 1 } do
		local turnA = Vector3.new(s * L, 0, backZ - CHAMFER)
		local turnB = Vector3.new(s * (L - CHAMFER), 0, backZ)
		wall(f, cf, k, turnA, turnB, { TurnA = TURN, TurnB = TURN })
		wall(f, cf, k, turnB, Vector3.new(s * gapX, 0, backZ), { TurnA = TURN, Bricks = { 1 } })
		pillar(f, cf, k, Vector3.new(s * gapX, 0, backZ))
	end
end

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
	local outerInside = yardSide + PLOT_WALL.Band / 2 -- inner face of the yard wall's brick band
	local inset = k.Plinth / 2
	local x0, x1 = cx - area.Size.X / 2 + inset, cx + area.Size.X / 2 - inset
	local z0, z1 = cz - area.Size.Z / 2 + inset, cz + area.Size.Z / 2 - inset
	local closedByYard = x0 - yardSide < 3
	local wallX0 = if closedByYard then yardSide else x0

	local floorX0 = if closedByYard then outerInside + 0.1 else x0 + 0.3
	local floorX1 = x1 - 0.3
	local floor = Geo.block(
		m,
		cf * CFrame.new((floorX0 + floorX1) / 2, 0.1, cz),
		Vector3.new(floorX1 - floorX0, 0.2, area.Size.Z - 1.4),
		PEN_FLOOR,
		nil,
		GHOST
	)
	floor.Name = "Floor"
	if closedByYard then
		-- a dirt bank against the yard wall: ore that lands beside the intake rolls back in
		local intakeMinX = info.Intake.Center.X - info.Intake.Size.X / 2
		local run = intakeMinX + 0.1 - outerInside
		local length = z1 - z0 - k.Plinth
		local bank = Geo.wedge(
			m,
			cf * CFrame.new(outerInside + run / 2, 0.65, cz) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(length, 1.3, run),
			PEN_BANK,
			nil,
			FENCE
		)
		bank.Name = "Bank"
	else
		pillar(m, cf, k, Vector3.new(x0, 0, z0))
		pillar(m, cf, k, Vector3.new(x0, 0, z1))
		wall(m, cf, k, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	end
	-- low brick walls on the pen's edge (inset half a wall), split by the gate
	wall(m, cf, k, Vector3.new(wallX0, 0, z1), Vector3.new(x1, 0, z1))
	-- the inner side wall reaches over both corners (square corners like stone-wall)
	wall(m, cf, k, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), { TurnA = math.pi / 2, TurnB = math.pi / 2 })
	-- the gate: two taller posts with the sign across them
	local postX = gateHalf + 0.8
	-- tall gate posts carry the board well above the pen's walls
	local gateTop = area.Size.Y + 2.4
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		pillar(m, cf, k, Vector3.new(px, 0, z0), { Width = 1.3, Cap = 1.65, Top = gateTop })
		local cornerX = if side < 0 then wallX0 else x1
		wall(m, cf, k, Vector3.new(cornerX, 0, z0), Vector3.new(px, 0, z0), { Bricks = { 1 } })
	end
	-- (round 2) the ORE PEN board stands upright on the two gate posts, high
	-- over the ores, facing the yard path
	board(
		m,
		cf * CFrame.new(gateX, gateTop + k.PillarCapH + 0.85, z0 - 0.1),
		Vector3.new(postX * 2 + 1.2, 1.5, 0.3),
		C.StoneDeep,
		"ORE PEN",
		Palette.Gold
	)

	-- what services use: the intake box and the prompt point
	local box = info.Intake
	local intake = Geo.block(
		m,
		cf * CFrame.new(box.Center.X, (box.Size.Y - 1) / 2, box.Center.Z),
		Vector3.new(box.Size.X, box.Size.Y + 1, box.Size.Z),
		Palette.Wood,
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

-- A padlock floating where the ore would be, facing the yard gate (-Z):
-- a bright gold body, a pale steel shackle, a dark keyhole slot and a red
-- "locked" light, its only glow (a neon top edge bloomed white from above).
-- Every part is opaque: PodiumService hides the lock by making its parts
-- transparent.
local function lock(parent: Instance, cf: CFrame): Model
	local m = model("Lock", parent)
	local body = Geo.block(m, cf, Vector3.new(1.5, 1.2, 0.62), LOCK_GOLD, nil, GHOST)
	body.Name = "Body"
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(side * 0.46, 0.88, 0), Vector3.new(0.32, 0.56, 0.32), LOCK_STEEL, nil, GHOST)
	end
	local bow = Geo.block(m, cf * CFrame.new(0, 1.16, 0), Vector3.new(1.24, 0.32, 0.32), LOCK_STEEL, nil, GHOST)
	bow.Shape = Enum.PartType.Cylinder
	Geo.block(m, cf * CFrame.new(0, 0.1, -0.32), Vector3.new(0.2, 0.46, 0.06), HOUSING_DARK, nil, GHOST)
	-- the red "locked" light along the bottom of the body
	local led = Geo.block(m, cf * CFrame.new(0, -0.4, -0.31), Vector3.new(1.1, 0.2, 0.06), LOCKED_RED, NEON, GHOST)
	led.Name = "LockedLight"
	return m
end

-- The podium's holo-ring (plot-local, around the ore): a level octagon of
-- thin cyan neon bars, the same on every slot and turned like the
-- pedestal's octagons (a flat faces the yard gate). Centre height, radius
-- of the bar centre lines and bar thickness: the inner edge clears the
-- widest ore at the ring's height (Prismite, 1.82 studs from the axis) and
-- the top stays below PodiumService's income tag.
-- (round 2: thinner, a little higher and tighter: it hugs the ore instead of
-- reading as a debug outline over the neighbours)
-- (round 3: thinner, tighter and see-through: the big hexagons read as
-- gizmos over the yard)
PlotBuilder.HoloRing = { Y = 5.2, Radius = 1.88, Bar = 0.09, Sides = 6, Transparency = 0.4 }

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
	Showpiece ore podium after Space Station table-display-planet: a
	two-tier bevelled octagon pedestal (a wide pale octagon with blue light
	slits on its diagonal faces under a narrower dark navy octagon step), a
	hexagonal column (pipe-ring-colored) with an orange collar, a
	pale top plate edged by the amber neon `Rim` (it reaches 0.2 past the
	plate, so the glowing ring is the top's edge; dull on locked slots),
	and the ore floating above it inside a level cyan holo-ring. An
	invisible `Hover` box around the ore catches the mouse for
	PodiumController (the ore itself is not queryable).
]]
local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local width = math.min(rect.Size.X, rect.Size.Z) - 0.1
	-- tier 1: the wide pale octagon (its top at 0.55) with blue light slits on its four diagonal faces
	local lowTop, lowH = 0.55, 0.7
	local strips = prism(m, base * CFrame.new(0, lowTop - lowH / 2, 0), 8, width, lowH, SHELL, nil, SOLID)
	local plinth = strips[1]
	plinth.Name = "Base"
	for i = 0, 1 do
		local bar = base * CFrame.Angles(0, math.pi / 4 + i * math.pi / 2, 0) * CFrame.new(0, 0.26, 0)
		Geo.block(m, bar, Vector3.new(0.7, 0.16, width + 0.08), BASE_LIGHT, NEON, GHOST)
	end
	-- tier 2: the narrower octagon step in the darker metal
	local stepH, stepW = 0.5, 3.3
	local bevelTop = lowTop + stepH
	prism(m, base * CFrame.new(0, lowTop + stepH / 2, 0), 8, stepW, stepH, NAVY, nil, SOLID)
	-- the pale top plate on the amber rim
	local topH, topW = 0.35, 3.5 -- (the holo-ring is about 1.2 x the top)
	local topY = 3.35 -- top plate centre
	local rimH = 0.24
	local rimTop = topY - topH / 2 + 0.02
	-- hexagonal column (a flat faces the yard gate) with the orange collar low on it
	local hex = base * CFrame.Angles(0, math.pi / 6, 0)
	local columnBottom, columnTop = bevelTop, rimTop - rimH
	local shaft =
		prism(m, hex * CFrame.new(0, (columnBottom + columnTop) / 2, 0), 6, 2.0, columnTop - columnBottom, PODIUM_COLUMN, nil, SOLID)
	shaft[1].Name = "Column"
	local collarBottom, collarH = columnBottom + 0.06, 0.42
	cylinder(m, base * CFrame.new(0, collarBottom + collarH / 2, 0), collarH, 2.5, C.Hazard, nil, FENCE)
	local rim = cylinder(
		m,
		base * CFrame.new(0, rimTop - rimH / 2, 0),
		rimH,
		topW + 0.4,
		if locked then RIM_LOCKED else RIM_GOLD,
		if locked then Enum.Material.SmoothPlastic else NEON,
		GHOST
	)
	rim.Name = "Rim"
	local top = cylinder(m, base * CFrame.new(0, topY, 0), topH, topW, PODIUM_TOP, nil, SOLID)
	top.Name = "Top"
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CFrame.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CFrame.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	-- the holo-ring around the floating ore
	local bars, barSize = PlotBuilder.holoRingBars(base)
	for _, barCF in bars do
		local bar = Geo.block(m, barCF, barSize, HOLO, NEON, GHOST)
		bar.Name = "HoloRing"
		bar.Transparency = PlotBuilder.HoloRing.Transparency
	end
	-- invisible hover box around the ore: the mouse over the ore finds the podium
	local hoverH = 3
	local hover =
		Geo.block(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + hoverH / 2, 0), Vector3.new(3.4, hoverH, 3.4), SHELL, nil, {
			CanTouch = false,
			CanCollide = false,
			CastShadow = false,
			Transparency = 1,
		})
	hover.Name = "Hover"
	if locked then
		local padlock = lock(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + 0.8, 0))
		-- the price label stands almost upright on the bevel step in front of the
		-- column (faces the yard gate); its green neon frame is part of the lock,
		-- so PodiumService hides it with the lock
		local plateCF = base * CFrame.new(0, bevelTop + 0.45, -1.42) * CFrame.Angles(0.12, 0, 0)
		local plate = board(m, plateCF, Vector3.new(2.2, 0.9, 0.1), rgb(22, 30, 26), "100 R$", ROBUX_GREEN)
		plate.Name = "PricePlate"
		local frame = Geo.block(padlock, plateCF * CFrame.new(0, 0, 0.06), Vector3.new(2.34, 1.04, 0.06), ROBUX_GREEN, NEON, GHOST)
		frame.Name = "PriceFrame"
		local gui = plate:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if gui and label then
			gui.LightInfluence = 0
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = rgb(10, 30, 16)
		end
	end
	m.PrimaryPart = plinth
end

--[[
	Foundry placeholder in the Factory Kit look (machine-fortified): an iron
	housing on a thick hazard-striped base, copper eaves and a pale rib that
	wraps over the roof and down both sides; a deep portal frame around the
	furnace mouth (a molten-orange surround set back 0.8 behind the frame
	front, a smaller bright ember inside it, two dark grate bars in front;
	ForgeGlow pulses on the client) with the COMING SOON plank hung across
	the lintel above it; a hopper-square on the roof (dark inset inside the
	copper rim, so its top reads hollow) and a round chimney with a copper
	flange and an ember glowing in its mouth.
]]
local function foundry(yard: Model, cf: CFrame)
	local rect = BaseLayout.Foundry
	local m = model("Foundry", yard)
	local c = rect.Center
	local front = c.Z - rect.Size.Z / 2 + FOUNDRY_INSET -- front wall face (a gravel apron lies before it)
	local depth = 9
	local width = 14
	local base = cf * CFrame.new(c.X, 0, front + depth / 2)
	Geo.block(m, base * CFrame.new(0, 0.2, -0.5), Vector3.new(width + 2, 0.8, depth + 2), C.StoneDark, nil, SOLID)
	Geo.block(m, base * CFrame.new(0, 0.95, 0), Vector3.new(width + 0.3, 0.7, depth + 0.3), C.Hazard, nil, FENCE)
	local bodyBottom, bodyTop = 1.3, 7.3
	local walls = Geo.block(
		m,
		base * CFrame.new(0, (bodyBottom + bodyTop) / 2, 0),
		Vector3.new(width, bodyTop - bodyBottom, depth),
		HOUSING,
		nil,
		SOLID
	)
	walls.Name = "Walls"
	-- copper eaves around the top of the walls (the warm accent from the hero camera)
	Geo.block(m, base * CFrame.new(0, bodyTop - 0.3, 0), Vector3.new(width + 0.4, 0.6, depth + 0.4), C.Copper, nil, FENCE)
	-- the pale roof slab, inset from the copper eaves
	local roofH = 0.9
	local roofTop = bodyTop + roofH
	Geo.block(m, base * CFrame.new(0, bodyTop + roofH / 2, 0), Vector3.new(width - 0.6, roofH, depth - 0.6), SHELL, nil, SOLID)
	-- machine-fortified rib: over the roof and down both sides, in the middle
	local ribTop = roofTop + 0.4
	Geo.block(
		m,
		base * CFrame.new(0, (bodyBottom + ribTop) / 2, 0.5),
		Vector3.new(width + 0.8, ribTop - bodyBottom, 1.4),
		HOUSING_LIGHT,
		nil,
		FENCE
	)
	-- the furnace mouth: a deep portal frame (1 stud proud of the wall), a dark
	-- recess, the molten surround and the ember inside it, a grate in front
	local face = base * CFrame.new(0, 0, -depth / 2)
	local mouthW, mouthTop, frameTop, frameD = 5.2, 4.9, 6.4, 1.0
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			face * CFrame.new(side * (mouthW / 2 + 0.45), (bodyBottom + frameTop) / 2, -frameD / 2),
			Vector3.new(0.9, frameTop - bodyBottom, frameD),
			SHELL,
			nil,
			FENCE
		)
	end
	Geo.block(
		m,
		face * CFrame.new(0, (mouthTop + frameTop) / 2, -frameD / 2),
		Vector3.new(mouthW + 1.8, frameTop - mouthTop, frameD),
		SHELL,
		nil,
		FENCE
	)
	Geo.block(
		m,
		face * CFrame.new(0, (bodyBottom + mouthTop) / 2, -0.05),
		Vector3.new(mouthW, mouthTop - bodyBottom, 0.1),
		HOUSING_DARK,
		nil,
		GHOST
	)
	local glowW, glowH = 3.8, 2.4
	local glowBottom = bodyBottom + 0.1
	local glow = Geo.block(m, face * CFrame.new(0, glowBottom + glowH / 2, -0.15), Vector3.new(glowW, glowH, 0.1), FURNACE, NEON, GHOST)
	glow.Name = "ForgeGlow"
	local ember = Geo.block(m, face * CFrame.new(0, glowBottom + 0.85, -0.25), Vector3.new(2.6, 1.4, 0.1), C.Ember, NEON, GHOST)
	ember.Name = "ForgeGlow"
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			face * CFrame.new(side * 0.7, glowBottom + glowH / 2, -0.45),
			Vector3.new(0.18, glowH + 0.2, 0.18),
			HOUSING_DARK,
			nil,
			THIN
		)
	end
	-- the sign over the frame, and the plank hung across the lintel above the mouth: not open yet
	board(m, face * CFrame.new(0, 7.25, -frameD - 0.15), Vector3.new(8.4, 1.6, 0.2), HOUSING_DARK, "FOUNDRY", C.Fire)
	local plank = board(
		m,
		face * CFrame.new(0, (mouthTop + frameTop) / 2, -frameD - 0.12) * CFrame.Angles(0, 0, 0.05),
		Vector3.new(6.2, 1.15, 0.2),
		C.StoneDeep,
		"COMING SOON",
		Palette.Gold
	)
	plank.Name = "ComingSoon"
	-- hopper-square on the roof (front left): a funnel standing on its tip, the
	-- copper rim around a dark inset (so the top reads hollow)
	local hopper = base * CFrame.new(-width / 2 + 3, roofTop, -2.1)
	for _, side in { -1, 1 } do
		-- upside-down wedges, their tall sides meeting in the middle
		Geo.wedge(
			m,
			hopper * CFrame.new(0, 0.7, side * 0.85) * CFrame.Angles(0, if side > 0 then math.pi else 0, math.pi),
			Vector3.new(3.2, 1.4, 1.7),
			HOUSING_LIGHT,
			nil,
			FENCE
		)
	end
	Geo.block(m, hopper * CFrame.new(0, 1.7, 0), Vector3.new(3.5, 0.6, 3.5), C.Copper, nil, FENCE)
	Geo.block(m, hopper * CFrame.new(0, 2.01, 0), Vector3.new(2.7, 0.04, 2.7), HOUSING_DARK, nil, GHOST)
	-- round chimney (back right) with a copper flange and an ember top
	local stack = base * CFrame.new(width / 2 - 2.6, 0, depth / 2 - 1.9)
	cylinder(m, stack * CFrame.new(0, 10.9, 0), 7.2, 2.4, HOUSING_LIGHT, nil, SOLID)
	cylinder(m, stack * CFrame.new(0, 9.4, 0), 0.5, 2.9, C.Copper, nil, FENCE)
	local top = cylinder(m, stack * CFrame.new(0, 14.52, 0), 0.06, 1.9, C.Ember, NEON, GHOST)
	top.Name = "ForgeGlow"
end

--[[
	Train stop: a paved platform with a yellow safety edge, the TRAIN STOP
	sign between two square stone posts beside its ends and a
	lantern post (Graveyard lightpost-single: a stone foot, a post, an arm
	and a lantern under a cap), and a short track piece on the rail line at
	the platform's far end (track-detailed: dense orange sleepers under
	pale steel rails) ending in an open buffer stop (two sloped struts, a
	red beam, two buffers down the rails).
	The track piece is the `Track` model with the attribute
	`RailwayPlaceholder`: the railway step replaces it with the through line
	(its `BufferStop` would stand in the trains' way).
]]
local function trainStop(yard: Model, cf: CFrame)
	local rect = BaseLayout.TrainStop
	local m = model("TrainStop", yard)
	local c = rect.Center
	local platformH = 1
	local bottom = -0.4
	local platform = Geo.block(
		m,
		cf * CFrame.new(c.X, (bottom + platformH) / 2, c.Z),
		Vector3.new(rect.Size.X, platformH - bottom, rect.Size.Z),
		C.Flag,
		nil,
		SOLID
	)
	platform.Name = "Platform"
	-- yellow safety edge on the rail side, a step up from the yard
	local railSide = c.Z + rect.Size.Z / 2
	Geo.block(
		m,
		cf * CFrame.new(c.X, platformH + 0.03, railSide - 0.35),
		Vector3.new(rect.Size.X, 0.06, 0.5),
		rgb(250, 206, 64),
		nil,
		GHOST
	)
	Geo.block(m, cf * CFrame.new(0.7, 0.25, c.Z - rect.Size.Z / 2 - 0.5), Vector3.new(5, 0.5, 1), WALL_STONE, nil, SOLID)
	-- sign on two square stone posts (the walls' stone) just beyond the board's
	-- ends (they never cut into its faces), a little taller than the board
	local signZ = c.Z + 0.3
	local signW = 7.4
	for _, side in { -1, 1 } do
		local x = c.X + 5 + side * (signW / 2 + 0.4)
		Geo.block(m, cf * CFrame.new(x, platformH + 2.65, signZ), Vector3.new(0.75, 5.3, 0.75), WALL_STONE, nil, FENCE)
	end
	local stopSign =
		board(m, cf * CFrame.new(c.X + 5, platformH + 4.2, signZ), Vector3.new(signW, 1.6, 0.22), HOUSING_DARK, "TRAIN STOP", Palette.Gold)
	-- the same words on the back, for the trains (and the view from the sea)
	local front = stopSign:FindFirstChildOfClass("SurfaceGui")
	if front then
		local back = front:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = stopSign
	end
	-- lantern post (Graveyard lightpost-single; neon only, lights are budgeted on mobile):
	-- a stone foot, a dark post and its arm toward the rails, which widens into the
	-- cap of the lantern hanging under it
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ)
	local postH = 5.6
	Geo.block(m, lamp * CFrame.new(0, 0.3, 0), Vector3.new(0.9, 0.6, 0.9), WALL_CAP, nil, THIN)
	Geo.block(m, lamp * CFrame.new(0, postH / 2, 0), Vector3.new(0.36, postH, 0.36), HOUSING_DARK, nil, THIN)
	Geo.block(m, lamp * CFrame.new(0, postH - 0.1, 0.55), Vector3.new(0.66, 0.18, 1.5), HOUSING_DARK, nil, GHOST)
	Geo.block(m, lamp * CFrame.new(0, postH - 0.52, 0.9), Vector3.new(0.44, 0.66, 0.44), LAMP_AMBER, NEON, GHOST)
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
			FENCE
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
	foundry(yard, cf)
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
	-- the build grid: a mown lawn exactly the size of the grid, with a lighter
	-- stripe on every other row of cells (flat: tops at y <= 0.048, no
	-- collision, not raycast, so building and placement see the pad only)
	local flat = {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	}
	-- the tile (paving stones, exactly the grid) shows as a band just inside the
	-- walls around the lawn and its stripes, which lie on top of it
	local band = 1.6
	local tile = Geo.block(m, cf * CFrame.new(0, -0.025, 0), Vector3.new(size, 0.07, size), PLOT_PAVING, nil, flat)
	tile.Name = "PlotTile"
	local inner = half - band
	local lawn = Geo.block(m, cf * CFrame.new(0, 0.0, 0), Vector3.new(inner * 2, 0.06, inner * 2), PLOT_LAWN, nil, flat)
	lawn.Name = "Lawn"
	local cell = GameConfig.CellSize
	for row = 0, GameConfig.PlotCells - 1, 2 do
		local z0 = math.max(-half + row * cell, -inner)
		local z1 = math.min(-half + (row + 1) * cell, inner)
		local stripe =
			Geo.block(m, cf * CFrame.new(0, 0.024, (z0 + z1) / 2), Vector3.new(inner * 2, 0.04, z1 - z0), PLOT_LAWN_STRIPE, nil, flat)
		stripe.Name = "LawnStripe"
	end

	-- brick walls on the border: the road entrance at the front (-Z local)
	-- between two lamp posts, the YardGate in the back wall; the plot's one light
	-- hangs in the left entrance lantern's roof plate
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

	-- name sign at the front, facing the road: mounted on the road face of the
	-- left front wall, standing up over its rounded cap
	local railProps = { CanTouch = false, CanQuery = false }
	local signZ = -WALL_LINE - PLOT_WALL.Cap / 2 - 0.27
	local signBase = cf * CFrame.new(-(PlotBuilder.EntranceHalf + WALL_LINE) / 2, 0, signZ)
	local sign = Props.sign(m, signBase * CFrame.new(0, 3.45, 0), "Free Plot", 6.4, 2.2, Palette.WoodLight, Palette.WoodDark)
	sign.Name = "PlotSign"

	-- banner pole rising out of the back right wall pillar (owner color); it
	-- reaches down past the pad so it never floats over lower ground
	local pole = cf * CFrame.new(half + 1.5, 0, half + 1.5)
	Geo.block(m, pole * CFrame.new(0, 5.4, 0), Vector3.new(0.5, 13.2, 0.5), Palette.WoodDark, nil, railProps)
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
