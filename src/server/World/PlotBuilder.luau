--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border) that reads as a tidy garden from the lobby hero camera (a mown
	lawn with a lighter stripe per other cell row and a paving band, all flat),
	low blue-grey stone curbs with lamp caps on the corner posts, a name sign
	at the front and a banner, and
	behind it (plot-local +Z, the sea side) the yard from BaseLayout:
	  Yard.Ground      lawn pad, gravel paths, a low fence, the YardGate
	                   opening in the plot's back rail
	  Yard.Pen         the Ore Pen: fence with a gate, an invisible `Intake`
	                   part (BaseLayout.Pen.Intake) with a `Prompt`
	                   attachment at Pen.PromptPoint, an "ORE PEN" sign
	  Yard.Podium1..4  pedestals with a glowing rim; the `Top` part holds the
	                   `OrePoint` (BaseLayout.PodiumOreHeight) and `Prompt`
	                   attachments; slots 3 and 4 have a `Lock` model and a
	                   "100 R$" `PricePlate` (PodiumService hides them for
	                   players with the Podiums perk)
	  Yard.Foundry     placeholder building ("FOUNDRY - coming soon")
	  Yard.TrainStop   placeholder platform with a "TRAIN STOP" sign
	Everything decorative stays outside the 48x48 build grid, so every cell
	is free for machines. Machines are added at runtime into the plot's
	"Machines" folder by MachineService. A yard is ~125 parts (8 plots).
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
local LAWN = rgb(160, 202, 96)
-- the empty plot from above (lobby hero view): a mown lawn with subtle
-- lighter stripes on every other cell row, framed by a band of light paving
-- stones, a cobble edge, low blue-grey stone curbs (the lobby's Style stone)
-- and lamp caps on the corner posts
local PLOT_LAWN = rgb(112, 180, 66)
local PLOT_LAWN_STRIPE = rgb(128, 192, 76)
local PLOT_PAVING = rgb(196, 180, 152)
local PLOT_EDGE = rgb(156, 142, 128)
local CURB = rgb(114, 122, 140)
local CURB_CAP = rgb(160, 167, 180)
local GRAVEL = rgb(214, 192, 150)
local PEN_FLOOR = rgb(156, 124, 94)
local RIM_GOLD = rgb(255, 196, 72)
local RIM_LOCKED = rgb(96, 88, 104)
local ROBUX_GREEN = rgb(80, 200, 110)

-- the foundry's front wall stands this far behind the front of its BaseLayout rect
local FOUNDRY_INSET = 3.5

PlotBuilder.RimGold = RIM_GOLD
PlotBuilder.RimLocked = RIM_LOCKED

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

-- Low wooden fence between two plot-local points (posts at both ends).
local function lowFence(parent: Instance, cf: CFrame, from: Vector3, to: Vector3, posts: boolean?)
	local delta = to - from
	local length = delta.Magnitude
	local segments = math.max(1, math.floor(length / 6 + 0.5))
	local line = cf * CFrame.lookAt(from, to)
	if posts ~= false then
		for i = 0, segments do
			Geo.block(parent, line * CFrame.new(0, 1.1, -length * i / segments), Vector3.new(0.5, 2.2, 0.5), Palette.WoodDark, nil, THIN)
		end
	end
	Geo.block(parent, line * CFrame.new(0, 1.9, -length / 2), Vector3.new(0.3, 0.35, length), Palette.Wood, nil, THIN)
	Geo.block(parent, line * CFrame.new(0, 1.0, -length / 2), Vector3.new(0.25, 0.3, length), Palette.Wood, nil, GHOST)
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

local function fence(yard: Model, cf: CFrame)
	local f = model("Fence", yard)
	local rect = BaseLayout.Yard
	local x = rect.Size.X / 2 - 0.4
	local z0 = rect.Center.Z - rect.Size.Z / 2 + 0.2
	local z1 = rect.Center.Z + rect.Size.Z / 2 - 0.2
	lowFence(f, cf, Vector3.new(-x, 0, z0), Vector3.new(-x, 0, z1))
	-- the right side starts a little later: the banner pole stands at that corner
	lowFence(f, cf, Vector3.new(x, 0, z0 + 1.2), Vector3.new(x, 0, z1))
	-- the back, open where the train stop platform is
	local stop = BaseLayout.TrainStop
	local gap = stop.Size.X / 2 + 0.4
	lowFence(f, cf, Vector3.new(-x, 0, z1), Vector3.new(-gap, 0, z1), false)
	lowFence(f, cf, Vector3.new(gap, 0, z1), Vector3.new(x, 0, z1), false)
	Geo.block(f, cf * CFrame.new(-gap, 1.1, z1), Vector3.new(0.5, 2.2, 0.5), Palette.WoodDark, nil, THIN)
	Geo.block(f, cf * CFrame.new(gap, 1.1, z1), Vector3.new(0.5, 2.2, 0.5), Palette.WoodDark, nil, THIN)
	-- gate posts where the yard meets the plot's back rail
	local gate = BaseLayout.YardGate
	local edge = GameConfig.PlotCells * GameConfig.CellSize / 2 + 0.5
	for _, side in { -1, 1 } do
		local px = gate.CenterX + side * (gate.Width / 2 + 0.45)
		Geo.block(f, cf * CFrame.new(px, 1.3, edge), Vector3.new(0.9, 2.6, 0.9), Palette.WoodDark, nil, FENCE)
		Geo.block(f, cf * CFrame.new(px, 2.75, edge), Vector3.new(1, 0.3, 1), Palette.Gold, nil, GHOST)
	end
end

local function pen(yard: Model, cf: CFrame)
	local info = BaseLayout.Pen
	local area = info.Area
	local m = model("Pen", yard)
	local cx, cz = area.Center.X, area.Center.Z
	local hx, hz = area.Size.X / 2, area.Size.Z / 2
	local x0, x1, z0, z1 = cx - hx, cx + hx, cz - hz, cz + hz
	local height = area.Size.Y
	local gateX = info.PromptPoint.X
	local gateHalf = 2.5

	local floor = Geo.block(m, cf * CFrame.new(cx, 0.1, cz), Vector3.new(area.Size.X - 1.4, 0.2, area.Size.Z - 1.4), PEN_FLOOR, nil, GHOST)
	floor.Name = "Floor"
	-- stone curb (split by the gate)
	local curb = Palette.StoneDark
	local t = 0.8
	Geo.block(m, cf * CFrame.new(cx, t / 2, z1 - t / 2), Vector3.new(area.Size.X, t, t), curb, nil, SOLID)
	Geo.block(m, cf * CFrame.new(x0 + t / 2, t / 2, cz), Vector3.new(t, t, area.Size.Z - 2 * t), curb, nil, SOLID)
	Geo.block(m, cf * CFrame.new(x1 - t / 2, t / 2, cz), Vector3.new(t, t, area.Size.Z - 2 * t), curb, nil, SOLID)
	local leftLen = gateX - gateHalf - x0
	local rightLen = x1 - (gateX + gateHalf)
	Geo.block(m, cf * CFrame.new(x0 + leftLen / 2, t / 2, z0 + t / 2), Vector3.new(leftLen, t, t), curb, nil, SOLID)
	Geo.block(m, cf * CFrame.new(x1 - rightLen / 2, t / 2, z0 + t / 2), Vector3.new(rightLen, t, t), curb, nil, SOLID)
	-- posts (corners, side middles, gate) and one thick top rail per side
	local postH = height + 0.2
	local px0, px1, pz0, pz1 = x0 + 0.4, x1 - 0.4, z0 + 0.4, z1 - 0.4
	local posts = {
		Vector3.new(px0, 0, pz0),
		Vector3.new(px1, 0, pz0),
		Vector3.new(px0, 0, pz1),
		Vector3.new(px1, 0, pz1),
		Vector3.new(cx, 0, pz1),
		Vector3.new(px0, 0, cz),
		Vector3.new(px1, 0, cz),
	}
	for _, p in posts do
		Geo.block(m, cf * CFrame.new(p.X, postH / 2, p.Z), Vector3.new(0.8, postH, 0.8), Palette.WoodDark, nil, FENCE)
	end
	local railY = height - 0.35
	Geo.block(m, cf * CFrame.new(cx, railY, z1 - 0.4), Vector3.new(area.Size.X, 0.45, 0.4), Palette.Wood, nil, FENCE)
	Geo.block(m, cf * CFrame.new(x0 + 0.4, railY, cz), Vector3.new(0.4, 0.45, area.Size.Z), Palette.Wood, nil, FENCE)
	Geo.block(m, cf * CFrame.new(x1 - 0.4, railY, cz), Vector3.new(0.4, 0.45, area.Size.Z), Palette.Wood, nil, FENCE)
	Geo.block(m, cf * CFrame.new(x0 + leftLen / 2, railY, z0 + 0.4), Vector3.new(leftLen, 0.45, 0.4), Palette.Wood, nil, FENCE)
	Geo.block(m, cf * CFrame.new(x1 - rightLen / 2, railY, z0 + 0.4), Vector3.new(rightLen, 0.45, 0.4), Palette.Wood, nil, FENCE)
	-- gate: two tall posts with the sign on top, the gate swung open into the pen
	local gateTop = height + 1.9
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(gateX + side * (gateHalf + 0.45), gateTop / 2, z0 + 0.4),
			Vector3.new(0.9, gateTop, 0.9),
			Palette.WoodDark,
			nil,
			FENCE
		)
	end
	local hinge = cf * CFrame.new(gateX - gateHalf, 0, z0 + 0.4) * CFrame.Angles(0, -1.3, 0)
	Geo.block(m, hinge * CFrame.new(gateHalf - 0.2, 1.2, 0), Vector3.new(gateHalf * 2 - 0.6, 0.45, 0.25), Palette.WoodLight, nil, THIN)
	Geo.block(m, hinge * CFrame.new(gateHalf - 0.2, 2.3, 0), Vector3.new(gateHalf * 2 - 0.6, 0.45, 0.25), Palette.WoodLight, nil, GHOST)
	board(
		m,
		cf * CFrame.new(gateX, gateTop - 0.25, z0 + 0.1),
		Vector3.new(gateHalf * 2 + 1.8, 1.3, 0.3),
		Palette.WoodDark,
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

local function lock(parent: Instance, cf: CFrame)
	local m = model("Lock", parent)
	local gold = Palette.Gold
	Geo.block(m, cf * CFrame.new(0, 0, 0), Vector3.new(1.3, 1.1, 0.45), gold, Enum.Material.Metal, GHOST)
	Geo.block(m, cf * CFrame.new(0, 0.05, -0.24), Vector3.new(0.22, 0.42, 0.05), Palette.WoodDark, nil, GHOST)
	Geo.block(m, cf * CFrame.new(-0.42, 0.8, 0), Vector3.new(0.22, 0.6, 0.22), Palette.MetalLight, Enum.Material.Metal, GHOST)
	Geo.block(m, cf * CFrame.new(0.42, 0.8, 0), Vector3.new(0.22, 0.6, 0.22), Palette.MetalLight, Enum.Material.Metal, GHOST)
	Geo.block(m, cf * CFrame.new(0, 1.05, 0), Vector3.new(1.06, 0.22, 0.22), Palette.MetalLight, Enum.Material.Metal, GHOST)
end

local function podium(yard: Model, cf: CFrame, index: number, rect: BaseLayout.Rect)
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)
	local plinth = Geo.block(m, base * CFrame.new(0, 0.4, 0), Vector3.new(rect.Size.X, 0.8, rect.Size.Z), Palette.StoneDark, nil, SOLID)
	plinth.Name = "Base"
	Geo.block(
		m,
		base * CFrame.new(0, 0.92, 0),
		Vector3.new(rect.Size.X - 1, 0.25, rect.Size.Z - 1),
		Palette.Gold,
		Enum.Material.Metal,
		GHOST
	)
	local column = Geo.block(m, base * CFrame.new(0, 2.05, 0), Vector3.new(2.5, 2.5, 2.5), Palette.Stone, nil, SOLID)
	column.Name = "Column"
	local rim = Geo.block(
		m,
		base * CFrame.new(0, 3.38, 0),
		Vector3.new(3.5, 0.2, 3.5),
		if locked then RIM_LOCKED else RIM_GOLD,
		if locked then Enum.Material.SmoothPlastic else Enum.Material.Neon,
		GHOST
	)
	rim.Name = "Rim"
	local topY = 3.7
	local top = Geo.block(m, base * CFrame.new(0, topY, 0), Vector3.new(3.2, 0.45, 3.2), Palette.MetalLight, Enum.Material.Metal, SOLID)
	top.Name = "Top"
	local cushion =
		Geo.block(m, base * CFrame.new(0, topY + 0.32, 0), Vector3.new(1.7, 0.2, 1.7), Palette.Cloth, Enum.Material.Fabric, GHOST)
	cushion.Name = "Cushion"
	attachment(top, "OrePoint", CFrame.new(0, BaseLayout.PodiumOreHeight - topY, 0))
	attachment(top, "Prompt", CFrame.new(0, 2.6 - topY, -rect.Size.Z / 2 - 0.3))
	if locked then
		lock(m, base * CFrame.new(0, 2.1, -1.5))
		local plate = board(
			m,
			base * CFrame.new(0, 0.42, -rect.Size.Z / 2 - 0.08),
			Vector3.new(2.6, 0.7, 0.12),
			rgb(36, 26, 22),
			"100 R$",
			ROBUX_GREEN
		)
		plate.Name = "PricePlate"
	end
	m.PrimaryPart = plinth
end

local function foundry(yard: Model, cf: CFrame, rng: Rng.Rng)
	local rect = BaseLayout.Foundry
	local m = model("Foundry", yard)
	local c = rect.Center
	local front = c.Z - rect.Size.Z / 2 + FOUNDRY_INSET -- front wall face (a gravel apron lies before it)
	local depth = 9
	local width = 14
	local wallH = 7
	local base = cf * CFrame.new(c.X, 0, front + depth / 2)
	Geo.block(m, base * CFrame.new(0, 0.3, -0.5), Vector3.new(width + 2, 0.6, depth + 2), Palette.StoneDark, nil, SOLID)
	local walls = Geo.block(m, base * CFrame.new(0, 0.6 + wallH / 2, 0), Vector3.new(width, wallH, depth), Palette.StoneWarm, nil, SOLID)
	walls.Name = "Walls"
	-- gable roof (ridge along X)
	local roofY = 0.6 + wallH
	local roofH = 3.2
	local half = (depth + 1.2) / 2
	Geo.wedge(m, base * CFrame.new(0, roofY + roofH / 2, -half / 2), Vector3.new(width + 1.2, roofH, half), Palette.RoofRed, nil, SOLID)
	Geo.wedge(
		m,
		base * CFrame.new(0, roofY + roofH / 2, half / 2) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(width + 1.2, roofH, half),
		Palette.RoofRedDark,
		nil,
		SOLID
	)
	-- chimney with an ember glow
	local chimney = base * CFrame.new(width / 2 - 2.6, 0, depth / 2 - 2.4)
	Geo.block(m, chimney * CFrame.new(0, 7.6, 0), Vector3.new(2.4, 10.4, 2.4), Palette.CliffDark, nil, SOLID)
	Geo.block(m, chimney * CFrame.new(0, 12.95, 0), Vector3.new(3, 0.5, 3), Palette.Metal, nil, GHOST)
	local glow = Geo.block(m, chimney * CFrame.new(0, 13.25, 0), Vector3.new(1.8, 0.2, 1.8), Palette.ForgeGlow, Enum.Material.Neon, GHOST)
	glow.Name = "ForgeGlow"
	-- furnace mouth in the front wall
	local face = base * CFrame.new(0, 0, -depth / 2)
	Geo.block(m, face * CFrame.new(0, 2.7, -0.15), Vector3.new(5, 4.2, 0.4), rgb(40, 28, 26), nil, GHOST)
	local embers = Geo.block(m, face * CFrame.new(0, 1.25, -0.3), Vector3.new(4.2, 0.9, 0.3), Palette.Ember, Enum.Material.Neon, GHOST)
	embers.Name = "ForgeGlow"
	Geo.block(m, face * CFrame.new(0, 5.05, -0.35), Vector3.new(6.2, 0.7, 0.8), Palette.Metal, Enum.Material.Metal, GHOST)
	-- sign over the door, and a plank across it: not open yet
	board(m, face * CFrame.new(0, 6.55, -0.32), Vector3.new(8.4, 1.6, 0.2), Palette.WoodDark, "FOUNDRY", Palette.ForgeGlow)
	local plank = board(
		m,
		face * CFrame.new(0, 2.9, -0.55) * CFrame.Angles(0, 0, 0.1),
		Vector3.new(6.4, 1.1, 0.2),
		Palette.WoodLight,
		"COMING SOON",
		Palette.WoodDark
	)
	plank.Name = "ComingSoon"
	-- a barrel and crates by the door
	Props.barrel(m, face * CFrame.new(-width / 2 + 1.4, 0.6, -1.4), rng)
	Props.crate(m, face * CFrame.new(width / 2 - 1.5, 0.6, -1.5), rng, 2.4)
	Props.crate(m, face * CFrame.new(width / 2 - 1.5, 3, -1.5), rng, 1.8)
end

local function trainStop(yard: Model, cf: CFrame)
	local rect = BaseLayout.TrainStop
	local m = model("TrainStop", yard)
	local c = rect.Center
	local platformH = 1
	local platform =
		Geo.block(m, cf * CFrame.new(c.X, platformH / 2, c.Z), Vector3.new(rect.Size.X, platformH, rect.Size.Z), Palette.Plaza, nil, SOLID)
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
	Geo.block(m, cf * CFrame.new(0.7, 0.25, c.Z - rect.Size.Z / 2 - 0.5), Vector3.new(5, 0.5, 1), Palette.PlazaDark, nil, SOLID)
	-- sign on two posts
	local signZ = c.Z + 0.6
	for _, side in { -1, 1 } do
		Geo.block(
			m,
			cf * CFrame.new(c.X + 5 + side * 3.3, platformH + 2.4, signZ),
			Vector3.new(0.45, 4.8, 0.45),
			Palette.WoodDark,
			nil,
			THIN
		)
	end
	board(
		m,
		cf * CFrame.new(c.X + 5, platformH + 4.2, signZ - 0.3),
		Vector3.new(7.4, 1.6, 0.25),
		Palette.WoodDark,
		"TRAIN STOP",
		Palette.Gold
	)
	-- bench and a lamp post
	local bench = cf * CFrame.new(c.X - 9, platformH, signZ)
	Geo.block(m, bench * CFrame.new(0, 0.9, 0), Vector3.new(4, 0.35, 1.2), Palette.WoodLight, nil, GHOST)
	Geo.block(m, bench * CFrame.new(-1.6, 0.4, 0), Vector3.new(0.35, 0.8, 1), Palette.Metal, nil, GHOST)
	Geo.block(m, bench * CFrame.new(1.6, 0.4, 0), Vector3.new(0.35, 0.8, 1), Palette.Metal, nil, GHOST)
	-- lamp post (no light: neon only, lights are budgeted on mobile)
	local lamp = cf * CFrame.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ) * CFrame.Angles(0, math.pi / 2, 0)
	Geo.block(m, lamp * CFrame.new(0, 3.5, 0), Vector3.new(0.6, 7, 0.6), Palette.WoodDark, nil, FENCE)
	Geo.block(m, lamp * CFrame.new(0, 7.1, 0.8), Vector3.new(0.4, 0.4, 2), Palette.WoodDark, nil, GHOST)
	Geo.block(m, lamp * CFrame.new(0, 6.4, 1.6), Vector3.new(1, 1.2, 1), Palette.LampGlow, Enum.Material.Neon, GHOST)
	Geo.block(m, lamp * CFrame.new(0, 7.1, 1.6), Vector3.new(1.3, 0.3, 1.3), Palette.Metal, nil, GHOST)
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

	-- the pad has a 1-stud cobble border around the grid for the rails and posts
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
	-- a band of paving stones just inside the curbs (flat, like the stripes)
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

	-- low stone curbs on the back and sides, on the border; the front (road
	-- side, -Z local) stays open and the back curb has the YardGate opening
	local edge = half + 0.5
	local railColor = CURB
	local railProps = { CanTouch = false, CanQuery = false }
	local gate = BaseLayout.YardGate
	local gateMin, gateMax = gate.CenterX - gate.Width / 2, gate.CenterX + gate.Width / 2
	local leftLen, rightLen = gateMin + edge + 0.5, edge + 0.5 - gateMax
	Geo.block(m, cf * CFrame.new(-edge - 0.5 + leftLen / 2, 0.35, edge), Vector3.new(leftLen, 0.7, 1), railColor, nil, railProps)
	Geo.block(m, cf * CFrame.new(edge + 0.5 - rightLen / 2, 0.35, edge), Vector3.new(rightLen, 0.7, 1), railColor, nil, railProps)
	Geo.block(m, cf * CFrame.new(-edge, 0.35, 0), Vector3.new(1, 0.7, size + 2), railColor, nil, railProps)
	Geo.block(m, cf * CFrame.new(edge, 0.35, 0), Vector3.new(1, 0.7, size + 2), railColor, nil, railProps)
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		Geo.block(m, cf * CFrame.new(corner.X * edge, 1, corner.Z * edge), Vector3.new(1, 2, 1), CURB_CAP, nil, railProps)
		Geo.block(
			m,
			cf * CFrame.new(corner.X * edge, 2.3, corner.Z * edge),
			Vector3.new(0.7, 0.6, 0.7),
			Palette.LampGlow,
			Enum.Material.Neon,
			flat
		)
	end

	-- front lanterns
	Props.lantern(m, cf * CFrame.new(-half + 1, 0, -half - 1.5) * CFrame.Angles(0, -math.pi / 2, 0), true)
	Props.lantern(m, cf * CFrame.new(half - 1, 0, -half - 1.5) * CFrame.Angles(0, math.pi / 2, 0), false)

	-- name sign at the front, facing the road
	local signBase = cf * CFrame.new(-half + 8, 0, -half - 2)
	Geo.block(m, signBase * CFrame.new(-2.6, 2.4, 0), Vector3.new(0.5, 4.8, 0.5), Palette.WoodDark, nil, railProps)
	Geo.block(m, signBase * CFrame.new(2.6, 2.4, 0), Vector3.new(0.5, 4.8, 0.5), Palette.WoodDark, nil, railProps)
	local sign = Props.sign(m, signBase * CFrame.new(0, 3.6, 0), "Free Plot", 6.4, 2.2, Palette.WoodLight, Palette.WoodDark)
	sign.Name = "PlotSign"

	-- banner pole just outside the back corner (owner color); it reaches
	-- down past the pad so it never floats over lower ground
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
