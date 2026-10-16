--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) that reads as a tidy garden from the lobby hero camera (a mown
	lawn with a lighter stripe per other cell row and a paving band, all flat),
	framed with the yard by low brick walls after the Kenney Graveyard Kit:
	brick-wall (stone plinth, red brick band with raised bricks, a stone cap
	slab that overhangs both faces) and brick-wall-end pillars with lanterns
	on the gate posts. A name sign at the front and a banner, and behind it
	(plot-local +Z, the sea side) the yard from BaseLayout:
	  Walls            the pad's border: front walls with the road entrance
	                   between two lantern posts, the side walls up to the
	                   yard, the wall between pad and yard with the YardGate
	  Yard.Ground      lawn pad, gravel paths
	  Yard.Fence       the yard's side walls, square corner pillars and the
	                   back walls up to the train stop
	  Yard.Pen         the Ore Pen: low brick walls with a gate (the yard's
	                   side wall closes it on the outside, a dirt bank there
	                   rolls ore back in), an invisible `Intake` part
	                   (BaseLayout.Pen.Intake) with a `Prompt` attachment at
	                   Pen.PromptPoint, an "ORE PEN" sign
	  Yard.Podium1..4  showpiece pedestals (Space Station table-display-planet:
	                   a wide bevelled octagon base with blue corner lights, a
	                   pale column with an orange band, an amber neon `Rim`
	                   under the light top plate, a tilted cyan holo-ring
	                   around the floating ore and an invisible `Hover` box
	                   for the mouse); the `Top` part holds the `OrePoint` at
	                   BaseLayout.PodiumOreHeight and the `Prompt` attachment;
	                   slots 3 and 4 have a `Lock` model where the ore floats
	                   and a "100 R$" `PricePlate` (PodiumService hides them
	                   for players with the Podiums perk)
	  Yard.Foundry     Factory Kit placeholder ("FOUNDRY - coming soon"):
	                   machine-fortified housing with a rib and copper eaves,
	                   hopper, chimney, an ember furnace mouth with a grate
	  Yard.TrainStop   platform with a short track piece, a buffer stop and an
	                   end block
Everything decorative stays outside the 48x48 build grid, so every cell
is free for machines. Machines are added at runtime into the plot's
"Machines" folder by MachineService. A plot with its yard is <= 300 parts
and one light (8 plots).
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

local LAWN = rgb(160, 202, 96)
-- the empty plot from above (lobby hero view): a mown lawn with subtle
-- lighter stripes on every other cell row, framed by a band of light paving
-- stones and a cobble edge
local PLOT_LAWN = rgb(112, 180, 66)
local PLOT_LAWN_STRIPE = rgb(128, 192, 76)
local PLOT_PAVING = rgb(196, 180, 152)
local PLOT_EDGE = rgb(156, 142, 128)
local GRAVEL = rgb(214, 192, 150)
local PEN_FLOOR = rgb(156, 124, 94)
local PEN_BANK = rgb(132, 102, 76) -- the dirt bank along the yard wall inside the pen
local RIM_GOLD = rgb(226, 116, 26) -- deep amber: no white bloom over the top plate
local RIM_LOCKED = rgb(96, 88, 104)
local ROBUX_GREEN = rgb(110, 255, 140)
-- Graveyard Kit brick walls in the warm concept palette: warm pale stone, muted red brick
local WALL_STONE = rgb(196, 188, 176) -- plinths, pillar shafts
local WALL_CAP = rgb(222, 214, 200) -- cap slabs, pillar caps
local BRICK = rgb(170, 82, 64)
local BRICK_RAISED = rgb(232, 136, 110)
local LAMP_AMBER = rgb(255, 140, 40) -- lanterns on the gate posts (small and deep: no white bloom)
-- Factory / Space Station metals (docs/ART_DIRECTION.md section 9)
local HOUSING = rgb(92, 96, 112)
local HOUSING_LIGHT = rgb(138, 142, 160)
local HOUSING_DARK = rgb(58, 60, 72)
local SHELL = rgb(188, 194, 212) -- pale Space Station panels (podium top, foundry frame)
local HOLO = rgb(60, 160, 255) -- the podium's holo-ring (deep enough not to bloom white)
local LOCK_GOLD = rgb(255, 210, 64)
local LOCK_STEEL = rgb(214, 218, 230)
local RAIL_STEEL = rgb(196, 200, 214)
local SLEEPER = rgb(196, 112, 62)
local FURNACE = rgb(240, 70, 18) -- the furnace mouth: deep molten orange (C.Ember tone-maps to yellow)

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

-- The podium's holo-ring (plot-local, around the ore): centre height,
-- radius of the bar centre lines, tilt (radians) and bar thickness.
PlotBuilder.HoloRing = { Y = 5.55, Radius = 2.2, Tilt = math.rad(14), Bar = 0.12, Sides = 6 }

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

-- An upright octagonal prism (flat-to-flat `width`) from four blocks turned
-- in 45-degree steps (each covers two opposite flats).
local TAN8 = math.tan(math.pi / 8)
local function octagon(
	parent: Instance,
	cf: CFrame,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	props: Geo.PartProps
): { Part }
	local parts = {}
	for i = 0, 3 do
		local strip =
			Geo.block(parent, cf * CFrame.Angles(0, i * math.pi / 4, 0), Vector3.new(width, height, width * TAN8), color, material, props)
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

-- A wedge whose right-angle corner sits at the top-left (side -1) or
-- top-right (side 1) corner of a `w` x `h` box facing the frame's -Z, the
-- slope running from that corner's lower end up to its inner end; `depth`
-- deep. `cf` is the box centre.
local function cornerFill(parent: Instance, cf: CFrame, side: number, w: number, h: number, depth: number, color: Color3): WedgePart
	return Geo.wedge(
		parent,
		cf * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(depth, h, w),
		color,
		nil,
		GHOST
	)
end

---------------------------------------------------------------- brick walls (Graveyard Kit)

--[[
	A low wall like Kenney's brick-wall: a pale stone plinth (about a quarter
	of the height), a red brick band (about half) and a chunky stone cap
	slab that overhangs both faces (about a quarter), 3 parts per segment,
	plus raised bricks (one part pokes out of both faces). Pillars like
	brick-wall-end: a square stone shaft with a wider cap, 2 parts (+2 for a
	lantern on gate posts). Segments run from pillar center to pillar
	center; the shafts hide the ends.
]]
type WallKit = {
	Plinth: number, -- plinth thickness
	Band: number, -- brick band thickness
	Bottom: number, -- plinth bottom (reaches the ground beside the raised pad)
	PlinthTop: number,
	BandTop: number,
	Cap: number, -- cap slab width (overhangs the band on both faces)
	CapH: number, -- cap slab height
	Pillar: number, -- pillar shaft width
	PillarTop: number,
	PillarCap: number, -- pillar cap width
	PillarCapH: number,
}

-- proportions of brick-wall: plinth ~1/4, brick band ~1/2, cap ~1/4 of the height
local PLOT_WALL: WallKit = {
	Plinth = 1.3,
	Band = 1.0,
	Bottom = -0.4,
	PlinthTop = 0.6,
	BandTop = 1.95,
	Cap = 1.4,
	CapH = 0.55,
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
	CapH = 0.4,
	Pillar = 1.15,
	PillarTop = 2.1,
	PillarCap = 1.45,
	PillarCapH = 0.35,
}

-- Raised brick: { t = 0..1 along the wall, row = 1 lower / 2 upper }; it
-- shows on both faces of the wall.
type Brick = { number }
type WallOpts = { Bricks: { Brick }?, Extend: number? }

-- One straight wall from a to b (plot-local, y ignored).
local function wall(parent: Instance, cf: CFrame, kit: WallKit, a: Vector3, b: Vector3, opts: WallOpts?)
	local o: WallOpts = opts or {}
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.05 then
		return
	end
	local extend = o.Extend or 0
	local mid = (flatA + flatB) / 2
	local frame = cf * CFrame.lookAt(mid, flatB) -- the wall runs along the frame's -Z
	local full = length + 2 * extend
	local plinthH = kit.PlinthTop - kit.Bottom
	Geo.block(parent, frame * CFrame.new(0, kit.Bottom + plinthH / 2, 0), Vector3.new(kit.Plinth, plinthH, full), WALL_STONE, nil, FENCE)
	local bandH = kit.BandTop - kit.PlinthTop
	Geo.block(parent, frame * CFrame.new(0, kit.PlinthTop + bandH / 2, 0), Vector3.new(kit.Band, bandH, full), BRICK, nil, FENCE)
	local cap =
		Geo.block(parent, frame * CFrame.new(0, kit.BandTop + kit.CapH / 2, 0), Vector3.new(kit.Cap, kit.CapH, full), WALL_CAP, nil, FENCE)
	cap.Name = "Cap"
	local bricks: { Brick } = o.Bricks or {}
	for _, brick in bricks do
		local y = kit.PlinthTop + bandH * (if brick[2] == 2 then 0.7 else 0.3)
		local z = (brick[1] - 0.5) * length
		local size = Vector3.new(kit.Band + 0.28, math.min(0.32, bandH * 0.24), math.min(1.6, kit.Band * 1.6))
		local raised = Geo.block(parent, frame * CFrame.new(0, y, z), size, BRICK_RAISED, nil, GHOST)
		raised.Name = "Brick"
	end
end

type PillarOpts = { Width: number?, Cap: number?, Top: number?, Lamp: boolean? }

-- A square stone pillar with a cap; returns the lantern's glow on top, if any.
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
		WALL_CAP,
		nil,
		if capWidth * capWidth * kit.PillarCapH < 1 then THIN else FENCE
	)
	if o.Lamp then
		-- a little lantern (Graveyard lightpost): a small amber glow under a dark roof plate
		local lampY = top + kit.PillarCapH
		local lamp = Geo.block(parent, cf * CFrame.new(at.X, lampY + 0.26, at.Z), Vector3.new(0.42, 0.52, 0.42), LAMP_AMBER, NEON, GHOST)
		lamp.Name = "Lamp"
		Geo.block(parent, cf * CFrame.new(at.X, lampY + 0.6, at.Z), Vector3.new(0.8, 0.16, 0.8), HOUSING_DARK, nil, GHOST)
		return lamp
	end
	return nil
end

-- The pad's border: front walls with the road entrance, the sides up to the
-- yard, the wall between pad and yard with the YardGate. Returns the left
-- entrance lamp (it carries the plot's only light).
local function padWalls(plot: Model, cf: CFrame): Part?
	local m = model("Walls", plot)
	local k = PLOT_WALL
	local L, P = WALL_LINE, PILLAR_LINE
	local gate = BaseLayout.YardGate
	-- gate posts: their caps line up with the openings' edges
	local postWidth, postCap, postTop = 1.8, 2.1, 3.7
	local zs = { -P, -P / 2, 0, P / 2, P }
	local leftLamp: Part? = nil
	for _, s in { -1, 1 } do
		-- side: corner pillar, three between (every ~12.5 studs), the yard junction;
		-- raised bricks on the segment nearest the road
		for i, z in zs do
			pillar(m, cf, k, Vector3.new(s * P, 0, z))
			if i > 1 then
				local bricks = if i == 2 then { { 0.4, 2 } } else nil
				wall(m, cf, k, Vector3.new(s * L, 0, zs[i - 1]), Vector3.new(s * L, 0, z), { Bricks = bricks })
			end
		end
		-- front: corner .. the entrance post
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = pillar(m, cf, k, Vector3.new(s * ex, 0, -P), { Width = postWidth, Cap = postCap, Top = postTop, Lamp = true })
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, Vector3.new(s * P, 0, -L), Vector3.new(s * ex, 0, -L), {
			Bricks = { { 0.3, 2 }, { 0.7, 1 } },
		})
		-- back: the YardGate posts and the wall to the junction
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		pillar(m, cf, k, Vector3.new(gx, 0, P), { Width = postWidth, Cap = postCap, Top = postTop, Lamp = true })
		wall(m, cf, k, Vector3.new(gx, 0, L), Vector3.new(s * P, 0, L))
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
end

-- The yard's border: the side walls from the pad junction to the back, a
-- square brick-wall-end pillar on each back corner and the back walls up to
-- the train stop opening.
local function fence(yard: Model, cf: CFrame)
	local f = model("Fence", yard)
	local k = PLOT_WALL
	local L, P = WALL_LINE, PILLAR_LINE
	local backZ = PlotBuilder.BackWallZ
	local gapX = BaseLayout.TrainStop.Size.X / 2 + 0.5 + k.Pillar / 2
	for _, s in { -1, 1 } do
		local midZ = (P + backZ) / 2
		pillar(f, cf, k, Vector3.new(s * P, 0, midZ))
		wall(f, cf, k, Vector3.new(s * L, 0, P), Vector3.new(s * L, 0, midZ))
		wall(f, cf, k, Vector3.new(s * L, 0, midZ), Vector3.new(s * L, 0, backZ))
		pillar(f, cf, k, Vector3.new(s * L, 0, backZ))
		wall(f, cf, k, Vector3.new(s * L, 0, backZ), Vector3.new(s * gapX, 0, backZ))
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
	wall(m, cf, k, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), { Extend = k.Cap / 2 })
	-- the gate: two taller posts with the sign across them
	local postX = gateHalf + 0.8
	local gateTop = area.Size.Y + 0.4
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		pillar(m, cf, k, Vector3.new(px, 0, z0), { Width = 1.3, Cap = 1.65, Top = gateTop })
		local cornerX = if side < 0 then wallX0 else x1
		wall(m, cf, k, Vector3.new(cornerX, 0, z0), Vector3.new(px, 0, z0))
	end
	board(
		m,
		cf * CFrame.new(gateX, gateTop + k.PillarCapH + 0.55, z0 - 0.1),
		Vector3.new(postX * 2 + 1.6, 1.1, 0.3),
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
-- a bright gold body, a pale steel shackle, a dark round keyhole and a red
-- "locked" light. Every
-- part is opaque: PodiumService hides the lock by making its parts
-- transparent.
local function lock(parent: Instance, cf: CFrame)
	local m = model("Lock", parent)
	local body = Geo.block(m, cf, Vector3.new(1.5, 1.2, 0.62), LOCK_GOLD, nil, GHOST)
	body.Name = "Body"
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(side * 0.46, 0.86, 0), Vector3.new(0.34, 0.6, 0.34), LOCK_STEEL, nil, GHOST)
	end
	local bow = Geo.block(m, cf * CFrame.new(0, 1.16, 0), Vector3.new(1.26, 0.34, 0.34), LOCK_STEEL, nil, GHOST)
	bow.Shape = Enum.PartType.Cylinder
	local keyhole = Geo.block(
		m,
		cf * CFrame.new(0, 0.12, -0.32) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(0.06, 0.36, 0.36),
		HOUSING_DARK,
		nil,
		GHOST
	)
	keyhole.Shape = Enum.PartType.Cylinder
	Geo.block(m, cf * CFrame.new(0, -0.14, -0.32), Vector3.new(0.14, 0.36, 0.06), HOUSING_DARK, nil, GHOST)
	-- a red "locked" light along the bottom of the body
	local led = Geo.block(m, cf * CFrame.new(0, -0.44, -0.31), Vector3.new(1.1, 0.14, 0.04), C.AwningRed, NEON, GHOST)
	led.Name = "LockedLight"
end

-- The holo-ring as a closed polygon of thin bars on a tilted circle
-- (`Sides` bars, each tangent to the circle at its middle): returns the bar
-- CFrames and the bar size (around the podium's `base` frame).
function PlotBuilder.holoRingBars(base: CFrame): ({ CFrame }, Vector3)
	local ring = PlotBuilder.HoloRing
	local center = base * CFrame.new(0, ring.Y, 0) * CFrame.Angles(ring.Tilt, 0, 0)
	local n = ring.Sides
	local length = 2 * ring.Radius * math.tan(math.pi / n) + ring.Bar * math.tan(math.pi / n)
	local list = {}
	for i = 0, n - 1 do
		local angle = (i + 0.5) * 2 * math.pi / n
		table.insert(list, center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -ring.Radius))
	end
	return list, Vector3.new(length, ring.Bar, ring.Bar)
end

--[[
	Showpiece ore podium after Space Station table-display-planet: a wide
	low octagon with a narrower octagon on top (the bevel) and blue corner
	lights, a pale column with an orange band (pipe-ring-colored), a light
	top plate over an amber neon `Rim`, and the ore floating above it inside
	a tilted cyan holo-ring. An invisible `Hover` box around the ore catches
	the mouse for PodiumController (the ore itself is not queryable).
]]
local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local width = math.min(rect.Size.X, rect.Size.Z) - 0.1
	-- the wide base (its top at 0.6) and the bevel step on it
	local lowTop, lowH = 0.6, 0.7
	local strips = octagon(m, base * CFrame.new(0, lowTop - lowH / 2, 0), width, lowH, HOUSING, nil, SOLID)
	local plinth = strips[1]
	plinth.Name = "Base"
	-- corner lights: two neon bars through the base, their ends glow on the four diagonal faces
	for i = 0, 1 do
		local bar = base * CFrame.Angles(0, math.pi / 4 + i * math.pi / 2, 0) * CFrame.new(0, 0.3, 0)
		Geo.block(m, bar, Vector3.new(0.85, 0.2, width + 0.08), C.GlowEdge, NEON, GHOST)
	end
	local bevelTop = lowTop + 0.45
	octagon(m, base * CFrame.new(0, lowTop + 0.45 / 2, 0), width - 0.75, 0.45, HOUSING, nil, SOLID)
	-- squat pale column with the orange band, the amber rim tucked under the light top plate
	local topH = 0.4
	local topY = 3.3 -- top plate centre
	local columnTop = topY - topH / 2
	local column = cylinder(m, base * CFrame.new(0, (bevelTop + columnTop) / 2, 0), columnTop - bevelTop, 2.4, HOUSING_LIGHT, nil, SOLID)
	column.Name = "Column"
	cylinder(m, base * CFrame.new(0, bevelTop + 1.05, 0), 0.42, 2.7, C.Hazard, nil, FENCE)
	local rim = cylinder(
		m,
		base * CFrame.new(0, columnTop - 0.03, 0),
		0.14,
		3.5,
		if locked then RIM_LOCKED else RIM_GOLD,
		if locked then Enum.Material.SmoothPlastic else NEON,
		GHOST
	)
	rim.Name = "Rim"
	local top = cylinder(m, base * CFrame.new(0, topY, 0), topH, 3.3, SHELL, nil, SOLID)
	top.Name = "Top"
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CFrame.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CFrame.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	-- the holo-ring around the floating ore (wide enough for every ore, below the income tag)
	local bars, barSize = PlotBuilder.holoRingBars(base)
	for _, barCF in bars do
		local bar = Geo.block(m, barCF, barSize, HOLO, NEON, GHOST)
		bar.Name = "HoloRing"
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
		lock(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + 0.8, 0))
		-- a label leaning on the column, standing on the bevel step (faces the yard gate)
		local stepFront = (width - 0.75) / 2
		local plate = board(
			m,
			base * CFrame.new(0, bevelTop + 0.36, -(stepFront + 1.2) / 2 - 0.02) * CFrame.Angles(0.32, 0, 0),
			Vector3.new(1.5, 0.72, 0.1),
			rgb(30, 26, 30),
			"100 R$",
			ROBUX_GREEN
		)
		plate.Name = "PricePlate"
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
	wraps over the roof and down both sides, a thick frame around the ember
	furnace mouth (an arched top, a grate; ForgeGlow pulses on the client),
	a square hopper on the roof, a round chimney with a copper flange and an
	ember top, and a copper pipe up the back wall.
]]
local function foundry(yard: Model, cf: CFrame, rng: Rng.Rng)
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
	-- bevelled roof: a slab with sloped front and back edges
	local roofH = 0.9
	local roofTop = bodyTop + roofH
	Geo.block(m, base * CFrame.new(0, bodyTop + roofH / 2, 0), Vector3.new(width, roofH, depth - 2), SHELL, nil, SOLID)
	Geo.wedge(m, base * CFrame.new(0, bodyTop + roofH / 2, -depth / 2 + 0.5), Vector3.new(width, roofH, 1), SHELL, nil, FENCE)
	Geo.wedge(
		m,
		base * CFrame.new(0, bodyTop + roofH / 2, depth / 2 - 0.5) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(width, roofH, 1),
		SHELL,
		nil,
		FENCE
	)
	-- machine-fortified rib: over the roof and down both sides, in the middle
	local ribTop = roofTop + 0.4
	Geo.block(
		m,
		base * CFrame.new(0, (bodyBottom + ribTop) / 2, 0.5),
		Vector3.new(width + 0.8, ribTop - bodyBottom, 1.4),
		SHELL,
		nil,
		FENCE
	)
	-- the furnace mouth: a thick frame, a dark recess, the ember glow with an arched top and a grate
	local face = base * CFrame.new(0, 0, -depth / 2)
	local mouthW, mouthTop = 5.2, 5.5
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			face * CFrame.new(side * (mouthW / 2 + 0.45), (bodyBottom + 6.4) / 2, -0.2),
			Vector3.new(0.9, 6.4 - bodyBottom, 0.8),
			SHELL,
			nil,
			FENCE
		)
	end
	Geo.block(m, face * CFrame.new(0, (mouthTop + 6.4) / 2, -0.2), Vector3.new(mouthW + 1.8, 6.4 - mouthTop, 0.8), SHELL, nil, FENCE)
	Geo.block(
		m,
		face * CFrame.new(0, (bodyBottom + mouthTop) / 2, -0.06),
		Vector3.new(mouthW, mouthTop - bodyBottom, 0.2),
		HOUSING_DARK,
		nil,
		GHOST
	)
	local glowW, glowH = 3.6, 2.3
	local glowBottom = bodyBottom + 0.15
	local glowMid = glowBottom + glowH / 2
	local glow = Geo.block(m, face * CFrame.new(0, glowMid, -0.2), Vector3.new(glowW, glowH, 0.2), FURNACE, NEON, GHOST)
	glow.Name = "ForgeGlow"
	local archW, archH = 0.65, 0.55
	for _, side in { -1, 1 } do
		cornerFill(
			m,
			face * CFrame.new(side * (glowW / 2 - archW / 2), glowBottom + glowH - archH / 2, -0.36),
			side,
			archW,
			archH,
			0.16,
			HOUSING_DARK
		)
	end
	for _, y in { glowBottom + 0.35, glowBottom + 0.8 } do
		Geo.block(m, face * CFrame.new(0, y, -0.38), Vector3.new(glowW + 0.2, 0.2, 0.16), HOUSING_DARK, nil, GHOST)
	end
	-- sign over the frame, and a plank across the mouth: not open yet
	board(m, face * CFrame.new(0, 7.25, -0.95), Vector3.new(8.4, 1.6, 0.2), HOUSING_DARK, "FOUNDRY", C.Fire)
	local plank = board(
		m,
		face * CFrame.new(0, 4.65, -0.75) * CFrame.Angles(0, 0, 0.08),
		Vector3.new(6.4, 1.1, 0.2),
		Palette.WoodLight,
		"COMING SOON",
		Palette.WoodDark
	)
	plank.Name = "ComingSoon"
	-- square hopper on the roof (front left): neck, funnel, copper rim
	local hopper = base * CFrame.new(-width / 2 + 3, roofTop, -2.1)
	Geo.block(m, hopper * CFrame.new(0, 0.4, 0), Vector3.new(1.4, 0.8, 1.4), HOUSING_DARK, nil, FENCE)
	for _, side in { -1, 1 } do
		-- upside-down wedges, their tall sides meeting in the middle
		Geo.wedge(
			m,
			hopper * CFrame.new(0, 1.4, side * 0.85) * CFrame.Angles(0, if side > 0 then math.pi else 0, math.pi),
			Vector3.new(3.2, 1.2, 1.7),
			HOUSING_LIGHT,
			nil,
			FENCE
		)
	end
	Geo.block(m, hopper * CFrame.new(0, 2.35, 0), Vector3.new(3.5, 0.7, 3.5), C.Copper, nil, FENCE)
	-- round chimney (back right) with a copper flange and an ember top
	local stack = base * CFrame.new(width / 2 - 2.6, 0, depth / 2 - 1.9)
	cylinder(m, stack * CFrame.new(0, 10.9, 0), 7.2, 2.4, HOUSING_LIGHT, nil, SOLID)
	cylinder(m, stack * CFrame.new(0, 9.4, 0), 0.5, 2.9, C.Copper, nil, FENCE)
	cylinder(m, stack * CFrame.new(0, 14.3, 0), 0.5, 2.9, SHELL, nil, FENCE)
	local ember = cylinder(m, stack * CFrame.new(0, 14.6, 0), 0.2, 1.9, C.Ember, NEON, GHOST)
	ember.Name = "ForgeGlow"
	-- a copper pipe up the back wall into the eaves
	cylinder(
		m,
		base * CFrame.new(-width / 2 + 2.6, (bodyBottom + bodyTop) / 2, depth / 2 + 0.55),
		bodyTop - bodyBottom,
		1.1,
		C.Copper,
		nil,
		FENCE
	)
	local _ = rng
end

--[[
	Train stop: a paved platform with a yellow safety edge,
	a short track piece on the rail line (track-detailed: ballast, orange
	sleepers, pale steel rails) ending in an open buffer stop (two sloped
	struts, a red beam, two buffers down the rails, a red lamp) and an end
	block at the other end, the TRAIN STOP sign and a lamp post.
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
	-- sign on two posts
	local signZ = c.Z + 0.6
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(c.X + 5 + side * 3.3, platformH + 2.4, signZ), Vector3.new(0.45, 4.8, 0.45), HOUSING_DARK, nil, THIN)
	end
	local stopSign = board(
		m,
		cf * CFrame.new(c.X + 5, platformH + 4.2, signZ - 0.3),
		Vector3.new(7.4, 1.6, 0.25),
		HOUSING_DARK,
		"TRAIN STOP",
		Palette.Gold
	)
	-- the same words on the back, for the trains (and the view from the sea)
	local front = stopSign:FindFirstChildOfClass("SurfaceGui")
	if front then
		local back = front:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = stopSign
	end
	-- lamp post with a lantern (no light: neon only, lights are budgeted on mobile)
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ) * CFrame.Angles(0, math.pi / 2, 0)
	Geo.block(m, lamp * CFrame.new(0, 3.5, 0), Vector3.new(0.5, 7, 0.5), HOUSING_DARK, nil, FENCE)
	Geo.block(m, lamp * CFrame.new(0, 6.45, 0.75), Vector3.new(0.55, 0.7, 0.55), LAMP_AMBER, NEON, GHOST)
	Geo.block(m, lamp * CFrame.new(0, 6.95, 0.55), Vector3.new(1.1, 0.3, 1.6), HOUSING_DARK, nil, GHOST)
	-- the track piece on the rail line: ballast, five sleepers, two rails
	local railZ = BaseLayout.RailZ
	local half = rect.Size.X / 2 + 2
	local gauge = 2.5
	Geo.block(m, cf * CFrame.new(c.X, -0.2, railZ), Vector3.new(half * 2, 0.4, 5.2), C.CobbleDark, nil, SOLID)
	local sleepers = 5
	for i = 0, sleepers - 1 do
		local x = -half + (i + 0.5) * (half * 2 / sleepers)
		Geo.block(m, cf * CFrame.new(c.X + x, 0.12, railZ), Vector3.new(1.4, 0.24, 4.4), SLEEPER, nil, THIN)
	end
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(c.X, 0.42, railZ + side * gauge / 2), Vector3.new(half * 2, 0.36, 0.36), RAIL_STEEL, nil, THIN)
	end
	-- open buffer stop at the +X end: two sloped struts, a red beam facing the track,
	-- two buffers pointing down the rails and a red lamp on top
	local stop = cf * CFrame.new(c.X + half, 0, railZ)
	local beamH, beamY = 0.8, 1.25
	for _, side in { -1, 1 } do
		-- wedge: tall side at the beam, sloping down away from the track
		Geo.wedge(
			m,
			stop * CFrame.new(1.3, 0.8, side * gauge / 2) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(0.45, 1.6, 1.8),
			HOUSING,
			nil,
			FENCE
		)
	end
	Geo.block(m, stop * CFrame.new(0.2, beamY, 0), Vector3.new(0.6, beamH, gauge + 1.6), C.AwningRed, nil, SOLID)
	for _, side in { -1, 1 } do
		local buffer = Geo.block(m, stop * CFrame.new(-0.35, beamY, side * gauge / 2), Vector3.new(0.5, 0.8, 0.8), RAIL_STEEL, nil, THIN)
		buffer.Shape = Enum.PartType.Cylinder
	end
	Geo.block(m, stop * CFrame.new(0.2, beamY + beamH / 2 + 0.22, 0), Vector3.new(0.45, 0.44, 0.45), C.AwningRed, NEON, GHOST)
	-- end block at the -X end
	Geo.block(m, cf * CFrame.new(c.X - half - 0.4, 0.45, railZ), Vector3.new(0.8, 0.9, gauge + 1.4), C.WoodDark, nil, SOLID)
end

-- The yard behind a plot (plot-local +Z side), from BaseLayout.
function PlotBuilder.buildYard(parent: Instance, cf: CFrame, rng: Rng.Rng): Model
	local yard = model("Yard", parent)
	ground(yard, cf)
	fence(yard, cf)
	pen(yard, cf)
	for index, rect in BaseLayout.Podiums do
		podium(yard, cf, index, rect)
	end
	foundry(yard, cf, rng)
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
	-- between two lamp posts, the YardGate in the back wall
	local entranceLamp = padWalls(m, cf)
	if entranceLamp then
		Props.pointLight(entranceLamp, Palette.LampGlow, 16, 1.2)
	end

	-- name sign at the front, facing the road, before the left front wall (posts behind the board)
	local railProps = { CanTouch = false, CanQuery = false }
	local signBase = cf * CFrame.new(-(PlotBuilder.EntranceHalf + WALL_LINE) / 2, 0, -half - 2.6)
	Geo.block(m, signBase * CFrame.new(-2.6, 2.6, 0.45), Vector3.new(0.5, 5.2, 0.5), Palette.WoodDark, nil, railProps)
	Geo.block(m, signBase * CFrame.new(2.6, 2.6, 0.45), Vector3.new(0.5, 5.2, 0.5), Palette.WoodDark, nil, railProps)
	local sign = Props.sign(m, signBase * CFrame.new(0, 4, 0), "Free Plot", 6.4, 2.2, Palette.WoodLight, Palette.WoodDark)
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
	Geo.wedge(
		m,
		pole * CFrame.new(-1.8, 6.4, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(0.15, 1.6, 3.4),
		banner.Color,
		nil,
		{
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		}
	)

	PlotBuilder.buildYard(m, cf, Rng.new(`Yard/{plot.Id}`))

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
