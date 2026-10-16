--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) that reads as a tidy garden from the lobby hero camera (a mown
	lawn with a lighter stripe per other cell row and a paving band, all flat),
	framed with the yard by low brick walls after the Kenney Graveyard Kit:
	brick-wall, brick-wall-end pillars, brick-wall-curve-small corners. A
	name sign at the front and a banner, and behind it (plot-local +Z, the sea
	side) the yard from BaseLayout:
	  Walls            the pad's border: front walls with the road entrance
	                   between two lamp posts, the side walls up to the yard,
	                   the wall between pad and yard with the YardGate opening
	  Yard.Ground      lawn pad, gravel paths
	  Yard.Fence       the yard's side walls, rounded back corners and the
	                   back walls up to the train stop
	  Yard.Pen         the Ore Pen: low brick walls with a gate, an invisible
	                   `Intake` part (BaseLayout.Pen.Intake) with a `Prompt`
	                   attachment at Pen.PromptPoint, an "ORE PEN" sign
	  Yard.Podium1..4  showpiece pedestals (Space Station table-display: an
	                   octagonal base with blue corner lights, metal bands, a
	                   glowing `Rim` ring under the top plate, a floating glass
	                   dome); the `Top` part holds the `OrePoint` at
	                   BaseLayout.PodiumOreHeight and the `Prompt` attachment;
	                   slots 3 and 4 have a `Lock` model in the dome and a
	                   "100 R$" `PricePlate` (PodiumService hides them for
	                   players with the Podiums perk)
	  Yard.Foundry     Factory Kit placeholder ("FOUNDRY - coming soon"):
	                   bevelled housing, hopper, chimney, glowing furnace mouth
	  Yard.TrainStop   platform with a short track piece and a buffer stop
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
local METAL = Enum.Material.Metal

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
local RIM_GOLD = rgb(255, 196, 72)
local RIM_LOCKED = rgb(96, 88, 104)
local ROBUX_GREEN = rgb(80, 200, 110)
-- Graveyard Kit brick walls: pale blue-grey stone and warm red brick
local WALL_STONE = rgb(174, 180, 198) -- plinths, pillar shafts
local WALL_CAP = rgb(212, 216, 228) -- rounded caps, pillar caps
local BRICK = rgb(198, 86, 74)
local BRICK_RAISED = rgb(222, 116, 100)
local LAMP_AMBER = rgb(255, 168, 64) -- gate post lamps (warmer than Lamp: no white bloom)
-- Factory / Space Station metals (docs/ART_DIRECTION.md section 9)
local HOUSING = rgb(92, 96, 112)
local HOUSING_LIGHT = rgb(138, 142, 160)
local HOUSING_DARK = rgb(58, 60, 72)
local SHELL = rgb(188, 194, 212) -- the podium column: pale Space Station panels
local GLASS = rgb(196, 234, 255)

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
PlotBuilder.CornerRadius = 3 -- the yard's rounded back corners (brick-wall-curve-small)
local CORNER_RADIUS = PlotBuilder.CornerRadius

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

---------------------------------------------------------------- brick walls (Graveyard Kit)

--[[
	A low wall like Kenney's brick-wall: a pale stone plinth, a red brick
	band with a few raised bricks and a rounded pale cap (a cylinder lying
	along the wall), 3 parts per segment. Pillars like brick-wall-end: a
	square stone shaft with a wider cap, 2 parts (+1 neon lamp on gate posts).
	Segments run from pillar center to pillar center; the shafts hide the ends.
]]
type WallKit = {
	Plinth: number, -- plinth thickness
	Band: number, -- brick band thickness
	Bottom: number, -- plinth bottom (reaches the ground beside the raised pad)
	PlinthTop: number,
	BandTop: number,
	Cap: number, -- cap cylinder diameter (a little wider than the band)
	CapDrop: number, -- the cap's axis sits this far below the band top
	Pillar: number, -- pillar shaft width
	PillarTop: number,
	PillarCap: number, -- pillar cap width
	PillarCapH: number,
}

-- proportions of brick-wall: plinth ~1/5, brick band ~1/2, rounded cap ~1/4 of the height
local PLOT_WALL: WallKit = {
	Plinth = 1.2,
	Band = 1.0,
	Bottom = -0.4,
	PlinthTop = 0.55,
	BandTop = 2.1,
	Cap = 1.14,
	CapDrop = 0.12,
	Pillar = 1.6,
	PillarTop = 3.0,
	PillarCap = 2.0,
	PillarCapH = 0.45,
}

local PEN_WALL: WallKit = {
	Plinth = 0.85,
	Band = 0.7,
	Bottom = -0.2,
	PlinthTop = 0.4,
	BandTop = 1.5,
	Cap = 0.82,
	CapDrop = 0.1,
	Pillar = 1.1,
	PillarTop = 2.2,
	PillarCap = 1.4,
	PillarCapH = 0.35,
}

-- Raised brick: { t = 0..1 along the wall, row = 1 lower / 2 upper, side = 1 toward `Inside` / -1 away }
type Brick = { number }
type WallOpts = { Inside: Vector3?, Bricks: { Brick }?, Extend: number? }

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
	local cap = Geo.block(
		parent,
		frame * CFrame.new(0, kit.BandTop - kit.CapDrop, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(full, kit.Cap, kit.Cap),
		WALL_CAP,
		nil,
		FENCE
	)
	cap.Shape = Enum.PartType.Cylinder
	cap.Name = "Cap"
	local bricks = o.Bricks
	if bricks then
		local dir = (flatB - flatA).Unit
		local right = dir:Cross(Vector3.new(0, 1, 0))
		local inside = o.Inside or Vector3.zero
		local toward = if (inside - mid):Dot(right) >= 0 then 1 else -1
		for _, brick in bricks do
			local x = toward * brick[3] * (kit.Band / 2 + 0.07)
			local y = kit.PlinthTop + bandH * (if brick[2] == 2 then 0.62 else 0.28)
			local z = (brick[1] - 0.5) * length
			Geo.block(parent, frame * CFrame.new(x, y, z), Vector3.new(0.16, bandH * 0.24, kit.Band * 1.3), BRICK_RAISED, nil, GHOST)
		end
	end
end

type PillarOpts = { Width: number?, Cap: number?, Top: number?, Lamp: boolean? }

-- A square stone pillar with a cap; returns the neon lamp on top, if any.
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
		local lamp =
			Geo.block(parent, cf * CFrame.new(at.X, top + kit.PillarCapH + 0.3, at.Z), Vector3.new(0.6, 0.5, 0.6), LAMP_AMBER, NEON, GHOST)
		lamp.Name = "Lamp"
		return lamp
	end
	return nil
end

-- A rounded corner (brick-wall-curve-small) as `steps` short walls on a
-- circle around `center` from angle `from` to `to` (radians, 0 = +X, pi/2 = +Z).
local function curve(parent: Instance, cf: CFrame, kit: WallKit, center: Vector3, radius: number, from: number, to: number, steps: number)
	local prev = center + Vector3.new(math.cos(from), 0, math.sin(from)) * radius
	for i = 1, steps do
		local angle = from + (to - from) * i / steps
		local point = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		wall(parent, cf, kit, prev, point, { Extend = 0.15 })
		prev = point
	end
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
	local postWidth, postCap, postTop = 1.8, 2.1, 3.9
	local zs = { -P, -P / 2, 0, P / 2, P }
	local leftLamp: Part? = nil
	for _, s in { -1, 1 } do
		-- side: corner pillar, three between (every ~12.5 studs), the yard junction
		for i, z in zs do
			pillar(m, cf, k, Vector3.new(s * P, 0, z))
			if i > 1 then
				local bricks = if i % 2 == 0 then { { if s > 0 then 0.32 else 0.66, i / 2, 1 } } else nil
				wall(m, cf, k, Vector3.new(s * L, 0, zs[i - 1]), Vector3.new(s * L, 0, z), { Bricks = bricks })
			end
		end
		-- front: corner .. the entrance post (raised bricks on both faces)
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = pillar(m, cf, k, Vector3.new(s * ex, 0, -P), { Width = postWidth, Cap = postCap, Top = postTop, Lamp = true })
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, Vector3.new(s * P, 0, -L), Vector3.new(s * ex, 0, -L), {
			Bricks = { { 0.3, 2, 1 }, { 0.7, 1, -1 } },
		})
		-- back: the YardGate posts and the wall to the junction
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		pillar(m, cf, k, Vector3.new(gx, 0, P), { Width = postWidth, Cap = postCap, Top = postTop, Lamp = true })
		wall(m, cf, k, Vector3.new(gx, 0, L), Vector3.new(s * P, 0, L), { Bricks = { { 0.62, 2, 1 } } })
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

-- The yard's border: the side walls from the pad junction to the back, the
-- rounded back corners and the back walls up to the train stop opening.
local function fence(yard: Model, cf: CFrame)
	local f = model("Fence", yard)
	local k = PLOT_WALL
	local L, P = WALL_LINE, PILLAR_LINE
	local backZ = PlotBuilder.BackWallZ
	local curveZ = backZ - CORNER_RADIUS
	local gapX = BaseLayout.TrainStop.Size.X / 2 + 0.5 + k.Pillar / 2
	for _, s in { -1, 1 } do
		local midZ = (P + curveZ) / 2
		pillar(f, cf, k, Vector3.new(s * P, 0, midZ))
		wall(f, cf, k, Vector3.new(s * L, 0, P), Vector3.new(s * L, 0, midZ), {
			Inside = BaseLayout.Yard.Center,
			Bricks = { { 0.4, 2, 1 } },
		})
		wall(f, cf, k, Vector3.new(s * L, 0, midZ), Vector3.new(s * L, 0, curveZ), { Extend = 0.15 })
		local center = Vector3.new(s * (L - CORNER_RADIUS), 0, curveZ)
		curve(f, cf, k, center, CORNER_RADIUS, if s > 0 then 0 else math.pi, math.pi / 2, 2)
		wall(f, cf, k, Vector3.new(s * (L - CORNER_RADIUS), 0, backZ), Vector3.new(s * gapX, 0, backZ), { Extend = 0.15 })
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

	local floor = Geo.block(m, cf * CFrame.new(cx, 0.1, cz), Vector3.new(area.Size.X - 1.4, 0.2, area.Size.Z - 1.4), PEN_FLOOR, nil, GHOST)
	floor.Name = "Floor"
	-- low brick walls on the pen's edge (inset half a wall), split by the gate
	local inset = k.Plinth / 2
	local x0, x1 = cx - area.Size.X / 2 + inset, cx + area.Size.X / 2 - inset
	local z0, z1 = cz - area.Size.Z / 2 + inset, cz + area.Size.Z / 2 - inset
	local center = Vector3.new(cx, 0, cz)
	for _, corner in { Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1) } do
		pillar(m, cf, k, corner)
	end
	wall(m, cf, k, Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1), { Inside = center, Bricks = { { 0.3, 2, 1 } } })
	wall(m, cf, k, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	wall(m, cf, k, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), { Inside = center, Bricks = { { 0.6, 1, 1 } } })
	-- the gate: two taller posts with the sign across them
	local postX = gateHalf + 0.8
	local gateTop = area.Size.Y + 0.6
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		pillar(m, cf, k, Vector3.new(px, 0, z0), { Width = 1.3, Cap = 1.6, Top = gateTop })
		local cornerX = if side < 0 then x0 else x1
		wall(m, cf, k, Vector3.new(cornerX, 0, z0), Vector3.new(px, 0, z0), {
			Inside = center,
			Bricks = if side < 0 then { { 0.5, 2, -1 } } else nil,
		})
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

-- A padlock floating where the ore would be (every part opaque: PodiumService
-- hides the lock by making its parts transparent).
local function lock(parent: Instance, cf: CFrame)
	local m = model("Lock", parent)
	Geo.block(m, cf, Vector3.new(1.4, 1.15, 0.5), Palette.Gold, nil, GHOST)
	Geo.block(m, cf * CFrame.new(0, 0.02, -0.26), Vector3.new(0.24, 0.46, 0.05), HOUSING_DARK, nil, GHOST)
	Geo.block(m, cf * CFrame.new(-0.44, 0.84, 0), Vector3.new(0.24, 0.6, 0.24), C.StoneLight, nil, GHOST)
	Geo.block(m, cf * CFrame.new(0.44, 0.84, 0), Vector3.new(0.24, 0.6, 0.24), C.StoneLight, nil, GHOST)
	Geo.block(m, cf * CFrame.new(0, 1.1, 0), Vector3.new(1.12, 0.24, 0.24), C.StoneLight, nil, GHOST)
end

--[[
	Showpiece ore podium after Space Station table-display-planet (a
	bevelled octagonal base), pipe-ring-colored (an orange band on a pale
	column) and the concept v2 neon: blue corner lights on the base, a gold
	neon `Rim` ring around the top plate, a cyan holo pad, and a floating
	glass dome where the ore hovers.
]]
local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local width = math.min(rect.Size.X, rect.Size.Z) - 0.1
	-- octagonal pedestal with a light on every diagonal face
	local strips = octagon(m, base * CFrame.new(0, 0.3, 0), width, 0.8, HOUSING, nil, SOLID)
	local plinth = strips[1]
	plinth.Name = "Base"
	for i = 0, 3 do
		local face = base * CFrame.Angles(0, math.pi / 4 + i * math.pi / 2, 0) * CFrame.new(0, 0.34, -width / 2 - 0.04)
		Geo.block(m, face, Vector3.new(0.9, 0.24, 0.1), C.GlowEdge, NEON, GHOST)
	end
	-- bevel step, pale column with an orange band, the glowing rim and the top plate
	cylinder(m, base * CFrame.new(0, 0.85, 0), 0.3, 3.3, HOUSING_LIGHT, METAL, FENCE)
	local column = cylinder(m, base * CFrame.new(0, 2.25, 0), 2.5, 2.0, SHELL, nil, SOLID)
	column.Name = "Column"
	cylinder(m, base * CFrame.new(0, 2.05, 0), 0.55, 2.35, C.Hazard, nil, FENCE)
	local rim = cylinder(
		m,
		base * CFrame.new(0, 3.62, 0),
		0.22,
		3.75,
		if locked then RIM_LOCKED else RIM_GOLD,
		if locked then Enum.Material.SmoothPlastic else NEON,
		GHOST
	)
	rim.Name = "Rim"
	local topY = 3.92
	local top = cylinder(m, base * CFrame.new(0, topY, 0), 0.42, 3.3, Palette.MetalLight, METAL, SOLID)
	top.Name = "Top"
	local holo = cylinder(m, base * CFrame.new(0, topY + 0.24, 0), 0.06, 1.0, C.CrystalBlue, NEON, GHOST)
	holo.Name = "HoloPad"
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CFrame.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CFrame.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	-- the floating glass dome (queryable: the mouse hover over the ore finds the podium)
	local domeSize = 3.4
	local dome = Geo.ball(m, (base * CFrame.new(0, topY + 0.21 + 0.18 + domeSize / 2, 0)).Position, domeSize, GLASS, Enum.Material.Glass, {
		CanTouch = false,
		CanCollide = false,
		CastShadow = false,
		Transparency = 0.7,
	})
	dome.Name = "Dome"
	if locked then
		lock(m, base * CFrame.new(0, BaseLayout.PodiumOreHeight + 0.75, 0))
		local plate = board(
			m,
			base * CFrame.new(0, 0.42, -width / 2 - 0.12) * CFrame.Angles(0.3, 0, 0),
			Vector3.new(2.3, 0.7, 0.12),
			rgb(36, 26, 22),
			"100 R$",
			ROBUX_GREEN
		)
		plate.Name = "PricePlate"
	end
	m.PrimaryPart = plinth
end

--[[
	Foundry placeholder in the Factory Kit look (machine-fortified): a
	bevelled iron housing on a hazard-striped base, a thick frame around the
	glowing furnace mouth (ForgeGlow pulses on the client), a square hopper
	on the roof, a round chimney with a copper flange and an ember top.
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
	Geo.block(m, base * CFrame.new(0, 0.85, 0), Vector3.new(width + 0.3, 0.5, depth + 0.3), C.Hazard, nil, FENCE)
	local bodyTop = 7.3
	local walls =
		Geo.block(m, base * CFrame.new(0, (1.1 + bodyTop) / 2, 0), Vector3.new(width, bodyTop - 1.1, depth), HOUSING_LIGHT, nil, SOLID)
	walls.Name = "Walls"
	-- bevelled roof: a slab with sloped front and back edges
	local roofH = 0.9
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
	-- the furnace mouth: a thick frame, a dark recess, the glow behind two bars
	local face = base * CFrame.new(0, 0, -depth / 2)
	local mouthW, mouthTop = 5.2, 5.5
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			face * CFrame.new(side * (mouthW / 2 + 0.45), (1.1 + 6.4) / 2, -0.2),
			Vector3.new(0.9, 6.4 - 1.1, 0.8),
			SHELL,
			nil,
			FENCE
		)
	end
	Geo.block(m, face * CFrame.new(0, (mouthTop + 6.4) / 2, -0.2), Vector3.new(mouthW + 1.8, 6.4 - mouthTop, 0.8), SHELL, nil, FENCE)
	Geo.block(m, face * CFrame.new(0, (1.1 + mouthTop) / 2, -0.06), Vector3.new(mouthW, mouthTop - 1.1, 0.2), HOUSING_DARK, nil, GHOST)
	local glow = Geo.block(m, face * CFrame.new(0, 2.6, -0.2), Vector3.new(mouthW - 0.8, 2.4, 0.2), C.Molten, NEON, GHOST)
	glow.Name = "ForgeGlow"
	for _, side in { -1, 1 } do
		Geo.block(m, face * CFrame.new(side * 1.1, 2.6, -0.36), Vector3.new(0.32, 2.6, 0.16), HOUSING_DARK, nil, GHOST)
	end
	-- sign over the frame, and a plank across the mouth: not open yet
	board(m, face * CFrame.new(0, 7.25, -0.95), Vector3.new(8.4, 1.6, 0.2), HOUSING_DARK, "FOUNDRY", C.Fire)
	local plank = board(
		m,
		face * CFrame.new(0, 4.6, -0.75) * CFrame.Angles(0, 0, 0.08),
		Vector3.new(6.4, 1.1, 0.2),
		Palette.WoodLight,
		"COMING SOON",
		Palette.WoodDark
	)
	plank.Name = "ComingSoon"
	-- square hopper on the roof (front left): neck, funnel, copper rim, dark mouth
	local roofTop = bodyTop + roofH
	local hopper = base * CFrame.new(-width / 2 + 3, roofTop, -0.6)
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
	Geo.block(m, hopper * CFrame.new(0, 2.71, 0), Vector3.new(2.7, 0.04, 2.7), HOUSING_DARK, nil, GHOST)
	-- round chimney (back right) with a copper flange and an ember top
	local stack = base * CFrame.new(width / 2 - 2.6, 0, depth / 2 - 2.6)
	cylinder(m, stack * CFrame.new(0, 10.9, 0), 7.2, 2.4, HOUSING_LIGHT, nil, SOLID)
	cylinder(m, stack * CFrame.new(0, 9.4, 0), 0.5, 2.9, C.Copper, nil, FENCE)
	cylinder(m, stack * CFrame.new(0, 14.3, 0), 0.5, 2.9, SHELL, nil, FENCE)
	local ember = cylinder(m, stack * CFrame.new(0, 14.6, 0), 0.2, 1.9, C.Ember, NEON, GHOST)
	ember.Name = "ForgeGlow"
	-- a barrel by the door
	Props.barrel(m, face * CFrame.new(-width / 2 + 1.4, 0.6, -1.4), rng)
end

--[[
	Train stop: a paved platform with a brick face and a yellow safety edge,
	a short track piece on the rail line (track-detailed: ballast, sleepers,
	two rails) ending in a buffer stop, the TRAIN STOP sign and a lamp.
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
	-- brick face on the rail side, yellow safety edge on top, a step up from the yard
	local railSide = c.Z + rect.Size.Z / 2
	Geo.block(m, cf * CFrame.new(c.X, 0.4, railSide + 0.06), Vector3.new(rect.Size.X, 1, 0.14), BRICK, nil, GHOST)
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
	board(m, cf * CFrame.new(c.X + 5, platformH + 4.2, signZ - 0.3), Vector3.new(7.4, 1.6, 0.25), HOUSING_DARK, "TRAIN STOP", Palette.Gold)
	-- lamp post (no light: neon only, lights are budgeted on mobile)
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ) * CFrame.Angles(0, math.pi / 2, 0)
	Geo.block(m, lamp * CFrame.new(0, 3.5, 0), Vector3.new(0.5, 7, 0.5), HOUSING_DARK, nil, FENCE)
	Geo.block(m, lamp * CFrame.new(0, 6.5, 0.8), Vector3.new(0.9, 1, 0.9), C.Lamp, NEON, GHOST)
	Geo.block(m, lamp * CFrame.new(0, 7.15, 0.55), Vector3.new(1.2, 0.3, 1.7), HOUSING, nil, GHOST)
	-- the track piece on the rail line, sleepers every 5 studs
	local railZ = BaseLayout.RailZ
	local half = rect.Size.X / 2 + 2
	local gauge = 2.5
	Geo.block(m, cf * CFrame.new(c.X, -0.2, railZ), Vector3.new(half * 2, 0.4, 5.2), C.CobbleDark, nil, SOLID)
	for x = -half + 1.5, half - 1, 5 do
		Geo.block(m, cf * CFrame.new(c.X + x, 0.12, railZ), Vector3.new(1, 0.24, 4.4), C.Wood, nil, THIN)
	end
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(c.X, 0.42, railZ + side * gauge / 2), Vector3.new(half * 2, 0.36, 0.36), C.IronLight, METAL, THIN)
	end
	-- buffer stop at the +X end: a block with a red beam, two buffers and a red lamp
	local stop = cf * CFrame.new(c.X + half + 0.2, 0, railZ)
	Geo.block(m, stop * CFrame.new(0.3, 0.9, 0), Vector3.new(1.2, 1.8, 3.8), HOUSING, nil, SOLID)
	Geo.block(m, stop * CFrame.new(-0.45, 1.25, 0), Vector3.new(0.5, 0.8, 4.4), C.AwningRed, nil, FENCE)
	for _, side in { -1, 1 } do
		local buffer =
			Geo.block(m, stop * CFrame.new(-0.95, 1.25, side * gauge / 2), Vector3.new(0.6, 0.62, 0.62), Palette.MetalLight, METAL, THIN)
		buffer.Shape = Enum.PartType.Cylinder
	end
	Geo.block(m, stop * CFrame.new(0.3, 2.05, 0), Vector3.new(0.6, 0.5, 0.6), C.AwningRed, NEON, GHOST)
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
	local tile = Geo.block(m, cf * CFrame.new(0, -0.02, 0), Vector3.new(size, 0.06, size), PLOT_LAWN, nil, flat)
	tile.Name = "PlotTile"
	local cell = GameConfig.CellSize
	for row = 0, GameConfig.PlotCells - 1, 2 do
		local stripe =
			Geo.block(m, cf * CFrame.new(0, 0.015, -half + (row + 0.5) * cell), Vector3.new(size, 0.03, cell), PLOT_LAWN_STRIPE, nil, flat)
		stripe.Name = "LawnStripe"
	end
	-- a band of paving stones just inside the walls (flat, like the stripes)
	local band = 1.6
	for _, side in { -1, 1 } do
		local alongX =
			Geo.block(m, cf * CFrame.new(0, 0.028, side * (half - band / 2)), Vector3.new(size, 0.04, band), PLOT_PAVING, nil, flat)
		alongX.Name = "Paving"
		local alongZ = Geo.block(
			m,
			cf * CFrame.new(side * (half - band / 2), 0.028, 0),
			Vector3.new(band, 0.04, size - 2 * band),
			PLOT_PAVING,
			nil,
			flat
		)
		alongZ.Name = "Paving"
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
