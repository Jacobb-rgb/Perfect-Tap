--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) that reads as a tidy garden from the lobby hero camera (a mown
	lawn with a lighter stripe per other cell row and a paving band, all flat),
	framed with the yard by low brick walls after the Kenney Graveyard Kit:
	brick-wall (stone plinth, red brick band with raised bricks on every run,
	a stone cap slab that overhangs both faces), brick-wall-end pillars (a
	stone foot and a lantern under a roof plate on the road entrance posts,
	little lanterns on the corner and YardGate caps) and 45-degree back
	corners (brick-wall-curve-small). A name sign at the front and a banner,
	and behind it (plot-local +Z, the sea side) the yard from BaseLayout:
	  Walls            the pad's border and the long side walls: front walls
	                   with the road entrance between two lantern posts, the
	                   side walls from the road to the yard's back corners
	                   (pillars every ~12.5 studs on the left side only, so two
	                   neighbours never face each other with two pillared
	                   walls), the wall between pad and yard with the YardGate
	  Yard.Ground      lawn pad, gravel paths
	  Yard.Fence       the yard's cut back corners and the back walls up to
	                   the train stop opening
	  Yard.Pen         the Ore Pen: low brick walls with a gate (the yard's
	                   side wall closes it on the outside, a dirt bank there
	                   rolls ore back in), an invisible `Intake` part
	                   (BaseLayout.Pen.Intake) with a `Prompt` attachment at
	                   Pen.PromptPoint, an "ORE PEN" sign
	  Yard.Podium1..4  showpiece pedestals (Space Station table-display-planet,
	                   tapering upward: a pale octagon base with blue corner
	                   lights, a navy bevel step, a hexagonal pipe-ring column
	                   with an orange collar and two glowing slots, an amber
	                   neon `Rim` under the pale top plate with an amber inlay,
	                   a tilted cyan holo-ring around the floating ore and an
	                   invisible `Hover` box for the mouse); the `Top` part
	                   holds the `OrePoint` at BaseLayout.PodiumOreHeight and
	                   the `Prompt` attachment; slots 3 and 4 have a `Lock`
	                   model where the ore floats and a "100 R$" `PricePlate`
	                   (PodiumService hides them for players with the Podiums
	                   perk; the plate's neon frame lives in the lock)
	  Yard.Foundry     Factory Kit placeholder ("FOUNDRY - coming soon"):
	                   machine-fortified housing with a rib and copper eaves,
	                   hopper, chimney, an ember furnace mouth with a grate
	  Yard.TrainStop   platform with the TRAIN STOP sign and a lamp post, and
	                   the `Track` placeholder (a short track piece with a
	                   `BufferStop`) that the railway step replaces
Everything decorative stays outside the 48x48 build grid, so every cell
is free for machines. Machines are added at runtime into the plot's
"Machines" folder by MachineService. A plot with its yard is <= 300 parts
(about 293, 13 of them in the Track placeholder) and one light (8 plots).
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
-- Graveyard Kit brick walls in the warm concept palette: warm pale stone, red
-- brick light enough to stay red (not maroon) on the shaded side
local WALL_STONE = rgb(208, 200, 188) -- plinths, pillar shafts
local WALL_CAP = rgb(228, 221, 208) -- cap slabs, pillar caps and feet
local BRICK = rgb(200, 94, 72)
local BRICK_RAISED = rgb(250, 172, 140)
local LAMP_AMBER = rgb(255, 120, 30) -- lanterns on the posts (small and deep: no white bloom)
-- Factory / Space Station metals (docs/ART_DIRECTION.md section 9)
local HOUSING = rgb(122, 130, 184) -- the Factory Kit's periwinkle machine blue
local HOUSING_LIGHT = rgb(150, 158, 204)
local HOUSING_DARK = rgb(58, 60, 72)
local NAVY = rgb(62, 70, 112) -- the podium's bevel step
local SHELL = rgb(188, 194, 212) -- pale Space Station panels (podium base and top, foundry frame)
local HOLO = rgb(36, 140, 235) -- the podium's holo-ring (deep enough to stay cyan, not bloom white)
local BASE_LIGHT = rgb(40, 140, 255) -- the podium base's corner lights
local SLOT_ORANGE = rgb(255, 110, 24) -- glowing slots on the podium column
local LOCK_GOLD = rgb(255, 200, 40)
local LOCK_EDGE = rgb(255, 176, 30)
local LOCK_STEEL = rgb(230, 232, 240)
local LOCKED_RED = rgb(190, 16, 16) -- deep: a bright red neon tone-maps to salmon
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
	of the height), a red brick band (about half) and a chunky stone cap
	slab that overhangs both faces (about a quarter), 3 parts per straight
	run, plus raised bricks (one part pokes out of both faces), staggered
	over two rows. Pillars like brick-wall-end: a square stone shaft with a
	wider cap, 2 parts (+1 for a stone foot, +2 for a lantern under a roof
	plate on the gate posts, +1 for a little lantern on the corner caps).
	A straight run goes on under the pillars that stand on it (their shafts
	are wider than the wall), so a long wall costs 3 parts plus its pillars.
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

type WallOpts = {
	-- distances from `a` where pillars stand on the run: the bays between
	-- them (and the run's ends) get the raised bricks
	Stops: { number }?,
	Spacing: number?, -- about one raised brick per this many studs of a bay (nil: none)
	ExtendA: number?, -- grow the run past `a` / `b` (corner joints without a pillar)
	ExtendB: number?,
}

-- One straight wall from a to b (plot-local, y ignored).
local function wall(parent: Instance, cf: CFrame, kit: WallKit, a: Vector3, b: Vector3, opts: WallOpts?)
	local o: WallOpts = opts or {}
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.05 then
		return
	end
	local dir = (flatB - flatA) / length
	local extA, extB = o.ExtendA or 0, o.ExtendB or 0
	local runA, runB = flatA - dir * extA, flatB + dir * extB
	local frame = cf * CFrame.lookAt((runA + runB) / 2, runB) -- the wall runs along the frame's -Z
	local full = length + extA + extB
	local plinthH = kit.PlinthTop - kit.Bottom
	Geo.block(parent, frame * CFrame.new(0, kit.Bottom + plinthH / 2, 0), Vector3.new(kit.Plinth, plinthH, full), WALL_STONE, nil, FENCE)
	local bandH = kit.BandTop - kit.PlinthTop
	Geo.block(parent, frame * CFrame.new(0, kit.PlinthTop + bandH / 2, 0), Vector3.new(kit.Band, bandH, full), BRICK, nil, FENCE)
	local cap =
		Geo.block(parent, frame * CFrame.new(0, kit.BandTop + kit.CapH / 2, 0), Vector3.new(kit.Cap, kit.CapH, full), WALL_CAP, nil, FENCE)
	cap.Name = "Cap"
	local spacing = o.Spacing
	if not spacing then
		return
	end
	-- raised bricks, bay by bay, alternating between the lower and the upper row
	local stops = { 0, length }
	local extra: { number } = o.Stops or {}
	for _, d in extra do
		table.insert(stops, d)
	end
	table.sort(stops)
	local size = Vector3.new(kit.Band + 0.28, math.min(0.32, bandH * 0.24), math.min(1.6, kit.Band * 1.6))
	local count = 0
	for i = 1, #stops - 1 do
		local d0, d1 = stops[i], stops[i + 1]
		local bay = d1 - d0
		if bay >= 3.5 then
			local n = math.max(1, math.floor(bay / spacing + 0.5))
			for j = 1, n do
				count += 1
				local upper = count % 2 == 0
				local d = d0 + bay * (j - 0.5) / n
				local y = kit.PlinthTop + bandH * (if upper then 0.72 else 0.3)
				-- from the frame's centre (the run's middle) toward a (+Z)
				local z = (full / 2 - extA) - d
				local raised = Geo.block(parent, frame * CFrame.new(0, y, z), size, BRICK_RAISED, nil, GHOST)
				raised.Name = "Brick"
			end
		end
	end
end

type PillarOpts = { Width: number?, Cap: number?, Top: number?, Lamp: boolean?, Lantern: boolean?, Foot: boolean? }

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
	local capTop = top + kit.PillarCapH
	if o.Lamp then
		-- a little lantern (Graveyard lightpost): a small deep-amber glow under a dark roof plate
		local lamp = Geo.block(parent, cf * CFrame.new(at.X, capTop + 0.24, at.Z), Vector3.new(0.36, 0.48, 0.36), LAMP_AMBER, NEON, GHOST)
		lamp.Name = "Lamp"
		Geo.block(parent, cf * CFrame.new(at.X, capTop + 0.56, at.Z), Vector3.new(0.9, 0.16, 0.9), HOUSING_DARK, nil, GHOST)
		return lamp
	elseif o.Lantern then
		-- a warm glow point on a corner cap (no light object)
		local lantern =
			Geo.block(parent, cf * CFrame.new(at.X, capTop + 0.24, at.Z), Vector3.new(0.48, 0.48, 0.48), LAMP_AMBER, NEON, GHOST)
		lantern.Name = "Lamp"
		return lantern
	end
	return nil
end

-- The yard's back corners are cut at 45 degrees (brick-wall-curve-small),
-- this far along both walls; the long side walls end there.
PlotBuilder.YardChamfer = 2.5
local CHAMFER = PlotBuilder.YardChamfer
-- runs meeting at 135 degrees grow by half a cap times tan(22.5) to close the outer corner
local MITER = PLOT_WALL.Cap / 2 * math.tan(math.pi / 8)

-- The pad's border and the long side walls: front walls with the road
-- entrance between two lantern posts, the side walls from the road corner
-- to the yard's back corner (the left side with a pillar every ~12.5
-- studs; the right side only at the corners, so two neighbouring plots
-- don't put two pillared walls face to face across the alley), the wall
-- between pad and yard with the YardGate. Returns the left entrance lamp
-- (it carries the plot's only light).
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
		-- corner pillars with a lantern: the road corner and the pad/yard junction
		pillar(m, cf, k, Vector3.new(s * P, 0, -P), { Lantern = true })
		pillar(m, cf, k, Vector3.new(s * P, 0, P), { Lantern = true })
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
			Spacing = if s < 0 then 13 else 18,
			ExtendB = MITER,
		})
		-- front: corner .. the entrance post
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = pillar(m, cf, k, Vector3.new(s * ex, 0, -P), post)
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, Vector3.new(s * P, 0, -L), Vector3.new(s * ex, 0, -L), { Spacing = 6 })
		-- back: the YardGate post, a pillar half way and the wall to the junction
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		pillar(m, cf, k, Vector3.new(gx, 0, P), { Width = postWidth, Cap = postCap, Top = postTop, Lantern = true })
		local midX = (math.abs(gx) + P) / 2
		pillar(m, cf, k, Vector3.new(s * midX, 0, P))
		wall(m, cf, k, Vector3.new(gx, 0, L), Vector3.new(s * P, 0, L), { Stops = { midX - math.abs(gx) }, Spacing = 9.5 })
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
		wall(f, cf, k, turnA, turnB, { ExtendA = MITER, ExtendB = MITER })
		wall(f, cf, k, turnB, Vector3.new(s * gapX, 0, backZ), { ExtendA = MITER, Spacing = 4 })
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
	wall(m, cf, k, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), { ExtendA = k.Cap / 2, ExtendB = k.Cap / 2 })
	-- the gate: two taller posts with the sign across them
	local postX = gateHalf + 0.8
	local gateTop = area.Size.Y + 0.4
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		pillar(m, cf, k, Vector3.new(px, 0, z0), { Width = 1.3, Cap = 1.65, Top = gateTop })
		local cornerX = if side < 0 then wallX0 else x1
		wall(m, cf, k, Vector3.new(cornerX, 0, z0), Vector3.new(px, 0, z0), { Spacing = 4.5 })
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
-- a bright gold body with a gold neon edge along its top, a pale steel
-- shackle, a dark keyhole slot and a red "locked" light. Every part is
-- opaque: PodiumService hides the lock by making its parts transparent.
local function lock(parent: Instance, cf: CFrame): Model
	local m = model("Lock", parent)
	local body = Geo.block(m, cf, Vector3.new(1.5, 1.2, 0.62), LOCK_GOLD, nil, GHOST)
	body.Name = "Body"
	Geo.block(m, cf * CFrame.new(0, 0.6, 0), Vector3.new(1.56, 0.1, 0.68), LOCK_EDGE, NEON, GHOST)
	for _, side in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(side * 0.46, 0.92, 0), Vector3.new(0.32, 0.56, 0.32), LOCK_STEEL, nil, GHOST)
	end
	local bow = Geo.block(m, cf * CFrame.new(0, 1.2, 0), Vector3.new(1.24, 0.32, 0.32), LOCK_STEEL, nil, GHOST)
	bow.Shape = Enum.PartType.Cylinder
	Geo.block(m, cf * CFrame.new(0, 0.1, -0.32), Vector3.new(0.2, 0.46, 0.06), HOUSING_DARK, nil, GHOST)
	-- the red "locked" light along the bottom of the body
	local led = Geo.block(m, cf * CFrame.new(0, -0.4, -0.31), Vector3.new(1.1, 0.2, 0.06), LOCKED_RED, NEON, GHOST)
	led.Name = "LockedLight"
	return m
end

-- The podium's holo-ring (plot-local, around the ore): centre height,
-- radius of the bar centre lines, tilt (radians: the gate side dips toward
-- the player's camera, so the ring shows as an open ellipse), bar
-- thickness, and per podium a turn of the tilt toward the yard gate (Yaw,
-- per slot) and of the polygon in its plane (Spin), so neighbouring rings
-- never line up into one line.
PlotBuilder.HoloRing = { Y = 5.2, Radius = 2.3, Tilt = math.rad(21), Bar = 0.18, Sides = 6, Yaw = 0.16, Spin = 0.45 }

-- The holo-ring of podium `index` as a closed polygon of thin bars on a
-- tilted circle (`Sides` bars, each tangent to the circle at its middle):
-- returns the bar CFrames and the bar size (around the podium's `base` frame).
function PlotBuilder.holoRingBars(base: CFrame, index: number): ({ CFrame }, Vector3)
	local ring = PlotBuilder.HoloRing
	local center = base
		* CFrame.new(0, ring.Y, 0)
		* CFrame.Angles(0, (index - 1) * ring.Yaw, 0)
		* CFrame.Angles(-ring.Tilt, 0, 0)
		* CFrame.Angles(0, index * ring.Spin, 0)
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
	Showpiece ore podium after Space Station table-display-planet, tapering
	upward: a wide pale octagon base with blue corner lights, a navy bevel
	step, a hexagonal column (pipe-ring-colored) with an orange ring and two
	orange neon slots, an amber neon `Rim` under the pale top plate with an
	amber neon inlay, and the ore floating above it inside a tilted cyan
	holo-ring. An invisible `Hover` box around the ore catches the mouse for
	PodiumController (the ore itself is not queryable).
]]
local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local width = math.min(rect.Size.X, rect.Size.Z) - 0.1
	-- the wide pale base (its top at 0.6) with blue lights on its four diagonal faces
	local lowTop, lowH = 0.6, 0.75
	local strips = prism(m, base * CFrame.new(0, lowTop - lowH / 2, 0), 8, width, lowH, SHELL, nil, SOLID)
	local plinth = strips[1]
	plinth.Name = "Base"
	for i = 0, 1 do
		local bar = base * CFrame.Angles(0, math.pi / 4 + i * math.pi / 2, 0) * CFrame.new(0, 0.28, 0)
		Geo.block(m, bar, Vector3.new(0.8, 0.18, width + 0.08), BASE_LIGHT, NEON, GHOST)
	end
	-- the navy bevel step
	local stepH, stepW = 0.45, 3.3
	local bevelTop = lowTop + stepH
	cylinder(m, base * CFrame.new(0, lowTop + stepH / 2, 0), stepH, stepW, NAVY, nil, SOLID)
	-- pale top plate over the amber rim, an amber inlay under the ore
	local topH, topW = 0.35, 2.9
	local topY = 3.35 -- top plate centre
	local rimH = 0.22
	local rimTop = topY - topH / 2
	-- hexagonal column (a flat faces the yard gate) with the orange ring low on it
	local hex = base * CFrame.Angles(0, math.pi / 6, 0)
	local columnBottom, columnTop = bevelTop, rimTop - rimH
	local shaft =
		prism(m, hex * CFrame.new(0, (columnBottom + columnTop) / 2, 0), 6, 2.0, columnTop - columnBottom, HOUSING_LIGHT, nil, SOLID)
	shaft[1].Name = "Column"
	local ringBottom, ringH = columnBottom + 0.06, 0.42
	cylinder(m, base * CFrame.new(0, ringBottom + ringH / 2, 0), ringH, 2.5, C.Hazard, nil, FENCE)
	-- two glowing slots on the column's front flat, above the orange ring
	local slotBottom = ringBottom + ringH + 0.14
	local slotTop = columnTop - 0.14
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			base * CFrame.new(side * 0.34, (slotBottom + slotTop) / 2, -1.0 - 0.02),
			Vector3.new(0.12, slotTop - slotBottom, 0.06),
			SLOT_ORANGE,
			NEON,
			GHOST
		)
	end
	local rim = cylinder(
		m,
		base * CFrame.new(0, rimTop - rimH / 2, 0),
		rimH,
		3.1,
		if locked then RIM_LOCKED else RIM_GOLD,
		if locked then Enum.Material.SmoothPlastic else NEON,
		GHOST
	)
	rim.Name = "Rim"
	local top = cylinder(m, base * CFrame.new(0, topY, 0), topH, topW, SHELL, nil, SOLID)
	top.Name = "Top"
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CFrame.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CFrame.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	local inlay = cylinder(m, base * CFrame.new(0, topY + topH / 2 + 0.005, 0), 0.05, 2.2, RIM_GOLD, NEON, GHOST)
	inlay.Name = "Inlay"
	-- the holo-ring around the floating ore (wide enough for every ore, below the income tag)
	local bars, barSize = PlotBuilder.holoRingBars(base, index)
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
		HOUSING_LIGHT,
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
	Geo.block(m, face * CFrame.new(0, glowBottom + 0.55, -0.38), Vector3.new(glowW + 0.2, 0.24, 0.16), HOUSING_DARK, nil, GHOST)
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
	Train stop: a paved platform with a yellow safety edge, the TRAIN STOP
	sign on two posts beside its ends and a lamp post, and a short track
	piece on the rail line (track-detailed: ballast, orange sleepers, pale
	steel rails) ending in an open buffer stop (two sloped struts, a red
	beam, two buffers down the rails, a red lamp) with an end block at the
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
	-- sign on two posts just beyond the board's ends (they never cut into its faces)
	local signZ = c.Z + 0.3
	local signW = 7.4
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(c.X + 5 + side * (signW / 2 + 0.25), platformH + 2.5, signZ),
			Vector3.new(0.45, 5, 0.45),
			HOUSING_DARK,
			nil,
			THIN
		)
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
	-- lamp post with a lantern (no light: neon only, lights are budgeted on mobile)
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ) * CFrame.Angles(0, math.pi / 2, 0)
	Geo.block(m, lamp * CFrame.new(0, 3.5, 0), Vector3.new(0.5, 7, 0.5), HOUSING_DARK, nil, FENCE)
	Geo.block(m, lamp * CFrame.new(0, 7.3, 0), Vector3.new(0.6, 0.6, 0.6), LAMP_AMBER, NEON, GHOST)
	-- the track piece on the rail line: ballast, four sleepers, two rails
	local track = model("Track", m)
	track:SetAttribute("RailwayPlaceholder", true)
	local railZ = BaseLayout.RailZ
	local half = rect.Size.X / 2 + 2
	local gauge = 2.5
	Geo.block(track, cf * CFrame.new(c.X, -0.2, railZ), Vector3.new(half * 2, 0.4, 5.2), C.CobbleDark, nil, SOLID)
	local sleepers = 4
	for i = 0, sleepers - 1 do
		local x = -half + (i + 0.5) * (half * 2 / sleepers)
		Geo.block(track, cf * CFrame.new(c.X + x, 0.12, railZ), Vector3.new(1.6, 0.24, 4.4), SLEEPER, nil, THIN)
	end
	for _, side in { -1, 1 } do
		Geo.block(track, cf * CFrame.new(c.X, 0.42, railZ + side * gauge / 2), Vector3.new(half * 2, 0.36, 0.36), RAIL_STEEL, nil, THIN)
	end
	-- open buffer stop at the +X end: two sloped struts, a red beam facing the track,
	-- two buffers pointing down the rails and a red lamp on top
	local buffer = model("BufferStop", track)
	local stop = cf * CFrame.new(c.X + half, 0, railZ)
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
	Geo.block(buffer, stop * CFrame.new(0.2, beamY + beamH / 2 + 0.22, 0), Vector3.new(0.45, 0.44, 0.45), C.AwningRed, NEON, GHOST)
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
