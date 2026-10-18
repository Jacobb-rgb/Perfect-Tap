--[[
	PREVIEW ONLY: the plot pieces in the machines' style A "Soft", after
	src/shared/Builders/KitMachines.luau: cream bodies, slate frames and
	lids, orange trims and glowing orange strips, soft round shapes, signs in
	LuckiestGuy orange on slate. Nothing here is used by the game: the
	export mode `lune run tools/lune/export_scene.luau world yard_style_a`
	builds the yard preview and then swaps plot 5's pieces for these.

	Each builder keeps the footprint, position, names, attributes and
	attachments of the piece it replaces (so the services would keep
	working), and uses the same or fewer parts:
	  walls      PlotBuilder padWalls + fence: Plot_<id>.Walls and Yard.Fence:
	             a slate plinth with a glow strip, a cream body with a round
	             cream lid; cream round posts with slate caps, glowing orange
	             lamps on the road entrance and yard gate posts. The plot's
	             light hangs in the left entrance lamp. The name sign
	             PlotSign and the banner pole are only repainted.
	  pen        PlotBuilder pen: Yard.Pen with a slate tray floor, low soft
	             walls, round gate posts with glowing bands, the ORE PEN sign
	             on them, the dirt bank as a slate ramp, the same invisible
	             Intake with its Prompt attachment
	  podium     PlotBuilder podium: Yard.Podium1..4, a round slate base with
	             a glow ring, a cream drum with an orange band, the glowing
	             Rim under the slate Top, the holo-ring in a soft cyan,
	             Hover, Lock and PricePlate on the locked slots
	  foundry    World/FoundryBuilder building: Yard.Foundry with the same
	             layout and attachments: platform, back wall with the FOUNDRY
	             sign and WarnLight beacons, a round cream crucible furnace
	             with an arched glowing door, bowl hopper and fat chimney, the
	             glass pipe, casting channel and mould, the anvil, the rack;
	             FoundryBuilder.setRack still works on it. The FOUNDRY chute
	             receiver is only repainted.
	  trainStop  PlotBuilder trainStop: Yard.TrainStop, a metal platform with
	             a glow strip and a hazard edge, cream posts, the slate TRAIN
	             STOP sign, a slate lamp post with a glowing lamp
	  museum     a see-through block marked "MUSEUM (coming)" on
	             BaseLayout.Museum: the footprint steps 6-7 will use
]]

local roblox = require("@lune/roblox") :: any

local StyleA = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local UDim2 = roblox.UDim2
local UDim = roblox.UDim
local Font = roblox.Font

local rgb = C3.fromRGB
local CF: any = roblox.CFrame -- replaced by the Loader's CFrame (Lune's lookAt fix) in init
local Geo: any
local BaseLayout: any
local EconomyConfig: any
local WorldLayout: any
local PlotBuilder: any
local FoundryBuilder: any
local Palette: any
local P: any -- KitMachines.Palette

-- the plot floor's light metal (PlotBuilder PLOT_PLATE): the train stop's deck
local PLATE = rgb(150, 156, 174)
local TEXT = rgb(255, 170, 60) -- sign letters (orange, a little lighter than the strips)
local ROBUX_GREEN = rgb(110, 255, 140)
local LOCKED_RED = rgb(190, 16, 16)
local STEEL = rgb(200, 206, 220) -- the anvil's face and horn
local SILHOUETTE_BOARD = rgb(240, 234, 222)
local PEN_FLOOR = rgb(104, 112, 142) -- the pen's tray: a softer slate than the machines' Floor
local HOLO = rgb(90, 200, 255) -- the podiums' holo-ring (a soft cyan, like the Fusion Reactor's)
local LAMP = rgb(232, 102, 24) -- lamp balls: a deeper orange than the strips (no white / yellow bloom)

local SOLID = { CanTouch = false }
local FENCE = { CanTouch = false, CanQuery = false }
local PROP = { CanTouch = false, CanQuery = false, CanCollide = false }
local TINY = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }

local NEON_ROLES = { Neon = true, Glow = true, Hot = true, Molten = true, Cyan = true, Water = true }
local SHINE = { Body = true, Frame = true, Trim = true, Pipe = true }

function StyleA.init(Loader: any)
	CF = Loader.CFrame
	Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
	Palette = Loader.requirePath("ServerScriptService.Server.World.Palette")
	P = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines").Palette
end

---------------------------------------------------------------- parts

local function model(name: string, parent: any): any
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A part in a palette role (a KitMachines.Palette key) or a plain Color3.
local function part(parent: any, cf: any, size: any, role: any, flags: any, name: string?, shape: any?): any
	local isRole = type(role) == "string"
	local color = if isRole then P[role] else role
	local material = if isRole and NEON_ROLES[role] then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local p = Geo.block(parent, cf, size, color, material, flags)
	if isRole then
		p:SetAttribute("Kit", role)
		if SHINE[role] then
			p.Reflectance = 0.04
		end
		if role == "Glass" then
			p.Material = Enum.Material.Glass
			p.Transparency = 0.6
		end
	end
	if shape then
		p.Shape = shape
	end
	if name then
		p.Name = name
	end
	return p
end

local CYL = Enum.PartType.Cylinder

-- An upright cylinder centred at `cf`.
local function cylUp(parent: any, cf: any, height: number, d: number, role: any, flags: any, name: string?): any
	return part(parent, cf * CF.Angles(0, 0, math.pi / 2), V3.new(height, d, d), role, flags, name, CYL)
end

-- A cylinder along the frame's Z axis.
local function cylZ(parent: any, cf: any, length: number, d: number, role: any, flags: any, name: string?): any
	return part(parent, cf * CF.Angles(0, math.pi / 2, 0), V3.new(length, d, d), role, flags, name, CYL)
end

-- A cylinder along the frame's X axis.
local function cylX(parent: any, cf: any, length: number, d: number, role: any, flags: any, name: string?): any
	return part(parent, cf, V3.new(length, d, d), role, flags, name, CYL)
end

local function ball(parent: any, pos: any, d: number, role: any, flags: any, name: string?): any
	return part(parent, CF.new(pos), V3.new(d, d, d), role, flags, name, Enum.PartType.Ball)
end

-- A cylinder from world point a to b.
local function rod(parent: any, a: any, b: any, d: number, role: any, flags: any, name: string?): any
	local cf = CF.lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0)
	return part(parent, cf, V3.new((b - a).Magnitude, d, d), role, flags, name, CYL)
end

-- Makes a part glow (a Color3 part in Neon).
local function glow(p: any): any
	p.Material = Enum.Material.Neon
	return p
end

local function wedge(parent: any, cf: any, size: any, role: any, flags: any, name: string?): any
	local p = Geo.wedge(parent, cf, size, if type(role) == "string" then P[role] else role, nil, flags)
	if type(role) == "string" then
		p:SetAttribute("Kit", role)
	end
	if name then
		p.Name = name
	end
	return p
end

local function attachment(parent: any, name: string, localCF: any): any
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = localCF
	a.Parent = parent
	return a
end

-- Text on one face of a part (LuckiestGuy, like the machine signs).
local function label(board: any, face: any, text: string, color: any, light: number?): any
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = light or 0.3
	gui.Parent = board
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.04, 0.1)
	l.Size = UDim2.fromScale(0.92, 0.8)
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	l.Parent = gui
	return gui
end

-- A slate sign board with orange letters (both faces when `back`).
local function sign(parent: any, cf: any, size: any, text: string, back: boolean?, role: any?): any
	local board = part(parent, cf, size, role or "Frame", PROP, "Sign")
	label(board, Enum.NormalId.Front, text, TEXT)
	if back then
		label(board, Enum.NormalId.Back, text, TEXT)
	end
	return board
end

type Paint = { x: number, y: number, w: number, h: number, color: any, round: boolean?, stripes: number? }

-- Painted details (SurfaceGui frames: no parts in game; the preview paints them).
local function paint(target: any, face: any, items: { Paint }): any
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Paint"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 140
	gui.Parent = target
	for _, it in items do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = it.color
		frame.Position = UDim2.fromScale(it.x, it.y)
		frame.Size = UDim2.fromScale(it.w, it.h)
		if it.round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
		end
		if it.stripes then
			local keys = {}
			local n = it.stripes
			for i = 0, n - 1 do
				local color = if i % 2 == 0 then P.Trim else P.Dark
				local t0, t1 = i / n, (i + 1) / n
				table.insert(keys, roblox.ColorSequenceKeypoint.new(t0, color))
				table.insert(keys, roblox.ColorSequenceKeypoint.new(math.max(t0, t1 - 0.001), color))
			end
			local gradient = Instance.new("UIGradient")
			gradient.Color = roblox.ColorSequence.new(keys)
			gradient.Parent = frame
			frame.BackgroundColor3 = C3.new(1, 1, 1)
		end
		frame.Parent = gui
	end
	return gui
end

---------------------------------------------------------------- soft walls

--[[
	A soft wall run: a slate plinth (on the plot walls with a glowing orange
	strip through it, so it shows on both faces), a cream body and a round
	slate lid (a cylinder along the run, a little wider than the body): 4
	parts (3 on the pen), no raised bricks or mortar lines. Runs that meet
	without a post are mitred like PlotBuilder's.
]]
type Kit = {
	Bottom: number,
	PlinthTop: number,
	Plinth: number,
	Body: number,
	BodyTop: number,
	Lid: number, -- the round lid's diameter
	Glow: boolean,
}

local PLOT_WALL: Kit = { Bottom = -0.4, PlinthTop = 0.6, Plinth = 1.3, Body = 1.0, BodyTop = 1.95, Lid = 1.2, Glow = true }
local PEN_WALL: Kit = { Bottom = -0.2, PlinthTop = 0.42, Plinth = 0.95, Body = 0.7, BodyTop = 1.32, Lid = 0.86, Glow = false }

local function wall(parent: any, cf: any, kit: Kit, a: any, b: any, turnA: number?, turnB: number?)
	local flatA, flatB = V3.new(a.X, 0, a.Z), V3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.05 then
		return
	end
	local frame = cf * CF.lookAt(flatA, flatB) -- `a` at the origin, the run along the frame's -Z
	local tanA, tanB = math.tan((turnA or 0) / 2), math.tan((turnB or 0) / 2)
	local function layer(width: number, y: number, height: number, role: string, flags: any, name: string, round: boolean?): any
		local extA, extB = width / 2 * tanA, width / 2 * tanB
		local at = frame * CF.new(0, y, -(length + extB - extA) / 2)
		local full = length + extA + extB
		if round then
			return cylZ(parent, at, full, width, role, flags, name)
		end
		return part(parent, at, V3.new(width, height, full), role, flags, name)
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

--[[
	A round post: a cream shaft and a slate cap (2 parts); +1 a slate foot,
	+1 a glowing orange lamp ball on the cap, +1 a glowing band at height
	`Band`. Returns the lamp.
]]
local function post(parent: any, cf: any, kit: Kit, at: any, opts: PostOpts?): any?
	local o: PostOpts = opts or {}
	local d = o.D or 1.7
	local top = o.Top or 3.0
	local height = top - kit.Bottom
	cylUp(parent, cf * CF.new(at.X, kit.Bottom + height / 2, at.Z), height, d, "Body", FENCE, "Pillar")
	local capH = 0.42
	cylUp(parent, cf * CF.new(at.X, top + capH / 2, at.Z), capH, d + 0.34, "Frame", FENCE, "PillarCap")
	if o.Foot then
		local footTop = kit.PlinthTop + 0.3
		cylUp(parent, cf * CF.new(at.X, (kit.Bottom + footTop) / 2, at.Z), footTop - kit.Bottom, d + 0.5, "Frame", FENCE, "Foot")
	end
	if o.Band then
		cylUp(parent, cf * CF.new(at.X, o.Band, at.Z), 0.22, d + 0.06, "Neon", TINY, "PostGlow")
	end
	if o.Lamp then
		local lampD = 0.66
		return glow(ball(parent, (cf * CF.new(at.X, top + capH + lampD / 2 - 0.08, at.Z)).Position, lampD, LAMP, TINY, "Lamp"))
	end
	return nil
end

-- PlotBuilder padWalls in style A; returns the left entrance lamp (the plot's light).
function StyleA.padWalls(plot: any, cf: any): any?
	local m = model("Walls", plot)
	local k = PLOT_WALL
	local L = PlotBuilder.WallLine
	local Pl = L + 0.1
	local gate = BaseLayout.YardGate
	local chamfer = PlotBuilder.YardChamfer
	local turn = math.pi / 4
	local postCap = 2.1
	local sideEnd = PlotBuilder.BackWallZ - chamfer
	local leftLamp: any? = nil
	for _, s in { -1, 1 } do
		post(m, cf, k, V3.new(s * Pl, 0, -Pl))
		post(m, cf, k, V3.new(s * Pl, 0, Pl))
		if s < 0 then
			for _, z in { -Pl / 2, 0, Pl / 2, (Pl + sideEnd) / 2 } do
				post(m, cf, k, V3.new(s * Pl, 0, z))
			end
		end
		wall(m, cf, k, V3.new(s * L, 0, -Pl), V3.new(s * L, 0, sideEnd), nil, turn)
		local ex = PlotBuilder.EntranceHalf + postCap / 2
		local lamp = post(m, cf, k, V3.new(s * ex, 0, -Pl), { D = 1.8, Top = 3.7, Foot = true, Lamp = true })
		if s < 0 then
			leftLamp = lamp
		end
		wall(m, cf, k, V3.new(s * Pl, 0, -L), V3.new(s * ex, 0, -L))
		local gx = gate.CenterX + s * (gate.Width / 2 + postCap / 2)
		post(m, cf, k, V3.new(gx, 0, Pl), { D = 1.8, Top = 3.7, Lamp = true })
		local midX = (math.abs(gx) + Pl) / 2
		post(m, cf, k, V3.new(s * midX, 0, Pl))
		wall(m, cf, k, V3.new(gx, 0, L), V3.new(s * Pl, 0, L))
	end
	return leftLamp
end

-- PlotBuilder fence (the yard's cut back corners and back walls) in style A.
function StyleA.fence(yard: any, cf: any)
	local f = model("Fence", yard)
	local k = PLOT_WALL
	local L = PlotBuilder.WallLine
	local backZ = PlotBuilder.BackWallZ
	local chamfer = PlotBuilder.YardChamfer
	local turn = math.pi / 4
	local gapX = BaseLayout.TrainStop.Size.X / 2 + 0.5 + 1.6 / 2
	for _, s in { -1, 1 } do
		local turnA = V3.new(s * L, 0, backZ - chamfer)
		local turnB = V3.new(s * (L - chamfer), 0, backZ)
		wall(f, cf, k, turnA, turnB, turn, turn)
		wall(f, cf, k, turnB, V3.new(s * gapX, 0, backZ), turn, nil)
		post(f, cf, k, V3.new(s * gapX, 0, backZ))
	end
end

---------------------------------------------------------------- ore pen

function StyleA.pen(yard: any, cf: any)
	local info = BaseLayout.Pen
	local area = info.Area
	local m = model("Pen", yard)
	local k = PEN_WALL
	local cx, cz = area.Center.X, area.Center.Z
	local gateX = info.PromptPoint.X
	local gateHalf = 2.5
	local yardSide = -PlotBuilder.WallLine
	local outerInside = yardSide + PLOT_WALL.Body / 2
	local inset = k.Plinth / 2
	local x0, x1 = cx - area.Size.X / 2 + inset, cx + area.Size.X / 2 - inset
	local z0, z1 = cz - area.Size.Z / 2 + inset, cz + area.Size.Z / 2 - inset
	local closedByYard = x0 - yardSide < 3
	local wallX0 = if closedByYard then yardSide else x0

	-- the floor: a slate tray with painted tile seams
	local floorX0 = if closedByYard then outerInside + 0.1 else x0 + 0.3
	local floorX1 = x1 - 0.3
	local floorW, floorD = floorX1 - floorX0, area.Size.Z - 1.4
	local floor = part(m, cf * CF.new((floorX0 + floorX1) / 2, 0.1, cz), V3.new(floorW, 0.2, floorD), PEN_FLOOR, PROP, "Floor")
	local seams: { Paint } = {}
	local cols, rows = 8, 6
	for i = 1, cols - 1 do
		table.insert(seams, { x = i / cols - 0.002, y = 0, w = 0.004, h = 1, color = P.Frame })
	end
	for j = 1, rows - 1 do
		table.insert(seams, { x = 0, y = j / rows - 0.003, w = 1, h = 0.006, color = P.Frame })
	end
	paint(floor, Enum.NormalId.Top, seams)
	if closedByYard then
		-- the ramp against the yard wall (PlotBuilder's dirt bank): ore that lands beside the intake rolls back in
		local intakeMinX = info.Intake.Center.X - info.Intake.Size.X / 2
		local run = intakeMinX + 0.1 - outerInside
		local length = z1 - z0 - k.Plinth
		wedge(
			m,
			cf * CF.new(outerInside + run / 2, 0.65, cz) * CF.Angles(0, -math.pi / 2, 0),
			V3.new(length, 1.3, run),
			"Frame",
			FENCE,
			"Bank"
		)
	else
		post(m, cf, k, V3.new(x0, 0, z0), { D = 1.2, Top = 2.1 })
		post(m, cf, k, V3.new(x0, 0, z1), { D = 1.2, Top = 2.1 })
		wall(m, cf, k, V3.new(x0, 0, z0), V3.new(x0, 0, z1))
	end
	wall(m, cf, k, V3.new(wallX0, 0, z1), V3.new(x1, 0, z1))
	wall(m, cf, k, V3.new(x1, 0, z0), V3.new(x1, 0, z1), math.pi / 2, math.pi / 2)
	-- the gate: two round posts with glowing bands carry the sign
	local postX = gateHalf + 0.8
	local gateTop = area.Size.Y + 2.4
	for _, side in { -1, 1 } do
		local px = gateX + side * postX
		post(m, cf, k, V3.new(px, 0, z0), { D = 1.3, Top = gateTop, Band = 2.55 })
		local cornerX = if side < 0 then wallX0 else x1
		wall(m, cf, k, V3.new(cornerX, 0, z0), V3.new(px, 0, z0))
	end
	sign(m, cf * CF.new(gateX, gateTop + 0.42 + 0.85, z0 - 0.1), V3.new(postX * 2 + 1.4, 1.5, 0.3), "ORE PEN", true)

	-- what services use: the intake box and the prompt point (as PlotBuilder)
	local box = info.Intake
	local intake = Geo.block(
		m,
		cf * CF.new(box.Center.X, (box.Size.Y - 1) / 2, box.Center.Z),
		V3.new(box.Size.X, box.Size.Y + 1, box.Size.Z),
		P.Floor,
		nil,
		{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
	)
	intake.Name = "Intake"
	attachment(intake, "Prompt", intake.CFrame:ToObjectSpace(cf * CF.new(info.PromptPoint)))
end

---------------------------------------------------------------- podiums

-- The padlock over a locked slot: an orange body, a slate shackle, the keyhole, the red light.
local function lock(parent: any, cf: any): any
	local m = model("Lock", parent)
	part(m, cf, V3.new(1.5, 1.2, 0.62), "Trim", TINY, "Body")
	for _, side in { -1, 1 } do
		part(m, cf * CF.new(side * 0.46, 0.88, 0), V3.new(0.32, 0.56, 0.32), "Frame", TINY)
	end
	cylX(m, cf * CF.new(0, 1.16, 0), 1.24, 0.32, "Frame", TINY)
	part(m, cf * CF.new(0, 0.1, -0.32), V3.new(0.2, 0.46, 0.06), "Dark", TINY)
	local led = part(m, cf * CF.new(0, -0.4, -0.31), V3.new(1.1, 0.2, 0.06), LOCKED_RED, TINY, "LockedLight")
	led.Material = Enum.Material.Neon
	return m
end

--[[
	A soft round pedestal: a slate base with a glowing ring (Base, the
	PrimaryPart), a cream drum with an orange band, the glowing Rim under the
	slate Top (OrePoint, Prompt), the holo-ring, Hover; Lock and PricePlate on
	the locked slots. 13 parts (21 locked).
]]
function StyleA.podium(yard: any, cf: any, index: number, rect: any): any
	local m = model("Podium" .. index, yard)
	m:SetAttribute("Slot", index)
	local locked = index > EconomyConfig.Podiums.Free
	local base = cf * CF.new(rect.Center.X, 0, rect.Center.Z)
	local baseH = 0.6
	local plinth = cylUp(m, base * CF.new(0, baseH / 2, 0), baseH, 3.8, "Frame", SOLID, "Base")
	cylUp(m, base * CF.new(0, baseH * 0.5, 0), 0.09, 3.86, "Neon", TINY, "BaseGlow")
	local topH, topW = 0.35, 3.5
	local topY = 3.35
	local rimH = 0.24
	local rimTop = topY - topH / 2 + 0.02
	local drumBottom, drumTop = baseH, rimTop - rimH
	cylUp(m, base * CF.new(0, (drumBottom + drumTop) / 2, 0), drumTop - drumBottom, 2.5, "Body", SOLID, "Column")
	cylUp(m, base * CF.new(0, drumBottom + 0.5, 0), 0.34, 2.62, "Trim", FENCE, "Band")
	-- the Rim keeps PlotBuilder's colours: PodiumService repaints it (RimGold / RimLocked)
	local rim = cylUp(
		m,
		base * CF.new(0, rimTop - rimH / 2, 0),
		rimH,
		topW + 0.4,
		if locked then PlotBuilder.RimLocked else PlotBuilder.RimGold,
		TINY,
		"Rim"
	)
	rim.Material = if locked then Enum.Material.SmoothPlastic else Enum.Material.Neon
	local top = cylUp(m, base * CF.new(0, topY, 0), topH, topW, "Frame", SOLID, "Top")
	attachment(top, "OrePoint", top.CFrame:ToObjectSpace(base * CF.new(0, BaseLayout.PodiumOreHeight, 0)))
	attachment(top, "Prompt", top.CFrame:ToObjectSpace(base * CF.new(0, 2.6, -rect.Size.Z / 2 - 0.3)))
	local bars, barSize = PlotBuilder.holoRingBars(base)
	for _, barCF in bars do
		local bar = glow(part(m, barCF, barSize, HOLO, TINY, "HoloRing"))
		bar.Transparency = PlotBuilder.HoloRing.Transparency
	end
	local hoverH = 3
	local hover = Geo.block(m, base * CF.new(0, BaseLayout.PodiumOreHeight + hoverH / 2, 0), V3.new(3.4, hoverH, 3.4), P.Frame, nil, {
		CanTouch = false,
		CanCollide = false,
		CastShadow = false,
		Transparency = 1,
	})
	hover.Name = "Hover"
	if locked then
		local padlock = lock(m, base * CF.new(0, BaseLayout.PodiumOreHeight + 0.8, 0))
		local plateCF = base * CF.new(0, baseH + 0.47, -1.45) * CF.Angles(0.12, 0, 0)
		local plate = part(m, plateCF, V3.new(2.2, 0.9, 0.1), "Screen", PROP, "PricePlate")
		local gui = label(plate, Enum.NormalId.Front, "100 R$", ROBUX_GREEN, 0)
		local _ = gui
		local frame = part(padlock, plateCF * CF.new(0, 0, 0.06), V3.new(2.34, 1.04, 0.06), ROBUX_GREEN, TINY, "PriceFrame")
		frame.Material = Enum.Material.Neon
	end
	m.PrimaryPart = plinth
	return m
end

---------------------------------------------------------------- foundry

-- FoundryBuilder's frame and positions (plot-local origin = the platform's front edge centre).
local FLOOR = 0.3
local WIDTH, DEPTH = 16, 11
local ANVIL = V3.new(-3.8, 0, 3.0)
local ANVIL_TOP = 2.6
local FURNACE = V3.new(4.6, 0, 6.6)
local FURNACE_D = 4.6
local FURNACE_TOP = 5.1
local HOPPER_Y = FURNACE_TOP + 0.8
local MOULD = V3.new(0.4, 0, 3.0)
local RACK = V3.new(-4.4, 4.45, 10.3)
local CAMERA = V3.new(-2.1, 6.2, -2.9)
local HEIGHT = 14.2

local function foundryPlatform(m: any, F: any): any
	local base = part(m, F * CF.new(0, FLOOR - 0.25, DEPTH / 2), V3.new(WIDTH, 0.5, DEPTH), "Floor", SOLID, "Base")
	local seams: { Paint } = {}
	for i = 1, 3 do
		table.insert(seams, { x = i / 4 - 0.002, y = 0, w = 0.004, h = 1, color = P.Frame })
	end
	table.insert(seams, { x = 0, y = 0.5, w = 1, h = 0.006, color = P.Frame })
	paint(base, Enum.NormalId.Top, seams)
	-- the glowing strip along the front face and the hazard edge on top
	part(m, F * CF.new(0, FLOOR - 0.25, -0.03), V3.new(WIDTH - 0.8, 0.12, 0.06), "Neon", TINY, "FrontGlow")
	local edge = part(m, F * CF.new(0, FLOOR + 0.01, 0.3), V3.new(WIDTH, 0.04, 0.6), "Trim", TINY, "HazardEdge")
	paint(edge, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 24 } })
	return base
end

local function foundryWall(m: any, F: any)
	local z = DEPTH - 0.3
	local wallH = 6.8
	local w = part(m, F * CF.new(0, FLOOR + wallH / 2, z), V3.new(WIDTH, wallH, 0.6), "Body", SOLID, "Wall")
	-- painted panels: a slate skirting, soft insets with bolts, the slate frame behind the rack
	local items: { Paint } = { { x = 0, y = 0.9, w = 1, h = 0.1, color = P.Frame } }
	for i = 0, 3 do
		local x = 0.025 + i * 0.245
		table.insert(items, { x = x, y = 0.08, w = 0.22, h = 0.74, color = rgb(222, 214, 200) })
		table.insert(items, { x = x + 0.012, y = 0.11, w = 0.014, h = 0.03, color = P.Bolt, round = true })
		table.insert(items, { x = x + 0.194, y = 0.11, w = 0.014, h = 0.03, color = P.Bolt, round = true })
	end
	-- the rack's frame (the wall's front face runs from +X at x = 0 to -X at x = 1)
	local rackU = 0.5 - RACK.X / WIDTH
	table.insert(items, { x = rackU - 0.215, y = 1 - (RACK.Y - FLOOR + 2.0) / wallH, w = 0.43, h = 4.1 / wallH, color = P.Frame })
	paint(w, Enum.NormalId.Front, items)
	-- the train side: the same soft insets (no rack frame)
	local back: { Paint } = { { x = 0, y = 0.9, w = 1, h = 0.1, color = P.Frame } }
	for i = 0, 3 do
		table.insert(back, { x = 0.025 + i * 0.245, y = 0.08, w = 0.22, h = 0.74, color = rgb(222, 214, 200) })
	end
	paint(w, Enum.NormalId.Back, back)
	-- a slate lid with a glowing strip, the FOUNDRY sign standing on it
	part(m, F * CF.new(0, FLOOR + wallH + 0.15, z), V3.new(WIDTH + 0.4, 0.4, 1.0), "Frame", SOLID)
	part(m, F * CF.new(0, FLOOR + wallH + 0.15, z - 0.53), V3.new(WIDTH - 0.2, 0.12, 0.06), "Neon", TINY, "WallGlow")
	sign(m, F * CF.new(0, FLOOR + 7.95, z), V3.new(7.6, 1.6, 0.3), "FOUNDRY", true)
	-- warning beacons: glowing balls on slate cups (the client blinks WarnLight)
	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.6)
		cylUp(m, F * CF.new(x, FLOOR + 7.35, z), 0.4, 0.8, "Frame", TINY)
		ball(m, (F * CF.new(x, FLOOR + 7.8, z)).Position, 0.75, "Neon", TINY, "WarnLight")
	end
end

-- An arched door on the frame `face` (bottom centre at y0, facing -Z): orange frame, glow, hot core, a grate bar.
local function door(m: any, face: any, y0: number, w: number, straight: number)
	local function arch(width: number, z: number, depth: number, role: string, flags: any, name: string?): any
		local p = part(m, face * CF.new(0, y0 + straight / 2, z), V3.new(width, straight, depth), role, flags, name)
		cylZ(m, face * CF.new(0, y0 + straight, z), depth, width, role, flags, name)
		return p
	end
	-- the frame stands 0.35 proud of the face (it sinks into a round body at its sides)
	arch(w + 0.7, 0.1, 0.9, "Trim", SOLID)
	arch(w, -0.38, 0.06, "Glow", TINY, "Glow")
	part(m, face * CF.new(0, y0 + 0.75, -0.42), V3.new(w * 0.5, 1.3, 0.04), "Hot", TINY, "GlowCore")
	part(m, face * CF.new(0, y0 + 0.5, -0.46), V3.new(w * 0.95, 0.16, 0.1), "Dark", TINY)
end

local function foundryFurnace(m: any, F: any)
	local at = F * CF.new(FURNACE.X, 0, FURNACE.Z)
	-- slate plinth with a glow ring, the cream crucible, a slate lid
	local plinthH = 0.6
	cylUp(m, at * CF.new(0, FLOOR + plinthH / 2, 0), plinthH, FURNACE_D + 0.6, "Frame", SOLID)
	cylUp(m, at * CF.new(0, FLOOR + plinthH / 2, 0), 0.14, FURNACE_D + 0.66, "Neon", TINY)
	local bodyBottom = FLOOR + plinthH
	cylUp(m, at * CF.new(0, (bodyBottom + FURNACE_TOP) / 2, 0), FURNACE_TOP - bodyBottom, FURNACE_D, "Body", SOLID, "Crucible")
	cylUp(m, at * CF.new(0, FURNACE_TOP + 0.2, 0), 0.45, FURNACE_D + 0.3, "Frame", SOLID, "Lid")
	-- the arched door on the front
	door(m, at * CF.new(0, 0, -FURNACE_D / 2), bodyBottom + 0.05, 2.0, 1.5)
	-- the bowl hopper on the lid (KitMachines bowl): slate neck, cream bowl, glow ring, orange rim, dark mouth
	local hd = 3.4
	local y = FURNACE_TOP + 0.42
	local neck = 0.5
	cylUp(m, at * CF.new(0, y + neck / 2, 0), neck, hd * 0.56, "Frame", SOLID)
	y += neck
	local bowlH = hd * 0.34
	cylUp(m, at * CF.new(0, y + bowlH / 2, 0), bowlH, hd, "Body", SOLID, "Hopper")
	cylUp(m, at * CF.new(0, y + bowlH * 0.3, 0), 0.12, hd + 0.14, "Neon", TINY)
	cylUp(m, at * CF.new(0, y + bowlH + 0.05, 0), 0.26, hd + 0.28, "Trim", SOLID)
	cylUp(m, at * CF.new(0, y + bowlH + 0.19, 0), 0.04, hd * 0.8, "Dark", TINY, "HopperFloor")
	-- the fat chimney behind it (KitMachines chimney): slate stack, orange band, slate cap with a glow ring, smoke
	local stack = F * CF.new(FURNACE.X + 1.8, 0, FURNACE.Z + 2.4)
	local stackBottom, capY = FURNACE_TOP - 0.4, HEIGHT - 0.55
	cylUp(m, stack * CF.new(0, (stackBottom + capY) / 2, 0), capY - stackBottom, 1.5, "Pipe", SOLID)
	cylUp(m, stack * CF.new(0, stackBottom + (capY - stackBottom) * 0.55, 0), 0.32, 1.62, "Trim", TINY)
	cylUp(m, stack * CF.new(0, capY + 0.22, 0), 0.45, 2.05, "Frame", SOLID)
	cylUp(m, stack * CF.new(0, capY + 0.22, 0), 0.14, 2.12, "Neon", TINY)
	local mouth = cylUp(m, stack * CF.new(0, capY + 0.46, 0), 0.04, 1.3, "Dark", TINY, "ChimneyTop")
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = roblox.ColorSequence.new(P.Smoke)
	smoke.Rate = 2
	smoke.Parent = mouth
	-- the feed pipe from the FOUNDRY chute: an orange sleeve, a slate pipe up, an orange joint, into the side
	local px, pz = FURNACE.X + FURNACE_D / 2 + 0.75, FURNACE.Z - 0.9
	local bendY = FURNACE_TOP - 0.9
	cylUp(m, F * CF.new(px, FLOOR + 0.15, pz), 0.3, 1.0, "Trim", TINY)
	cylUp(m, F * CF.new(px, (FLOOR + bendY) / 2, pz), bendY - FLOOR, 0.7, "Pipe", PROP, "FeedPipe")
	local bend = (F * CF.new(px, bendY, pz)).Position
	local inlet = (F * CF.new(FURNACE.X + FURNACE_D / 2 - 0.4, bendY, pz)).Position
	ball(m, bend, 0.86, "Trim", PROP, "PipeJoint")
	rod(m, bend, inlet, 0.7, "Pipe", PROP)
end

local function foundryCasting(m: any, F: any)
	local pipeY = FLOOR + 3.3
	local fromX = FURNACE.X - FURNACE_D / 2 + 0.2
	local turnX = MOULD.X + 0.2
	local z = FURNACE.Z
	local a = (F * CF.new(fromX, pipeY, z)).Position
	local b = (F * CF.new(turnX, pipeY, z)).Position
	rod(m, a, b, 0.9, "Glass", PROP, "GlassPipe")
	rod(m, a, b, 0.42, "Molten", TINY, "Molten")
	cylX(m, F * CF.new(fromX - 0.2, pipeY, z), 0.3, 1.2, "Trim", TINY)
	ball(m, b, 0.98, "Frame", PROP, "PipeJoint")
	local spoutY = FLOOR + 2.25
	local c = (F * CF.new(turnX, spoutY, z)).Position
	rod(m, b, c, 0.8, "Glass", PROP, "GlassPipe")
	rod(m, b, c, 0.36, "Molten", TINY, "Molten")
	-- the sloped casting channel (KitMachines chute: a dark slide with orange lips) with molten metal
	local mouldTop = FLOOR + 1.45
	local from = (F * CF.new(turnX, spoutY - 0.25, z + 0.2)).Position
	local to = (F * CF.new(MOULD.X + 0.2, mouldTop + 0.18, MOULD.Z + 0.9)).Position
	local frame = CF.lookAt((from + to) / 2, to)
	local length = (to - from).Magnitude
	part(m, frame * CF.new(0, -0.12, 0), V3.new(0.9, 0.12, length), "Dark", PROP, "Channel")
	for _, side in { -1, 1 } do
		part(m, frame * CF.new(side * 0.42, 0.04, 0), V3.new(0.14, 0.32, length), "Trim", TINY)
	end
	part(m, frame * CF.new(0, -0.04, 0), V3.new(0.6, 0.05, length), "Molten", TINY, "Molten")
	cylUp(m, F * CF.new(turnX, (FLOOR + spoutY - 0.4) / 2, z + 0.2), spoutY - 0.4 - FLOOR, 0.36, "Frame", TINY)
	-- the mould table: a cream body, a glowing strip, the slate mould with the blaster cavity
	local tableCF = F * CF.new(MOULD.X, 0, MOULD.Z)
	local tableTop = mouldTop - 0.2
	part(m, tableCF * CF.new(0, (FLOOR + tableTop) / 2, 0), V3.new(3.6, tableTop - FLOOR, 2.4), "Body", SOLID, "MouldTable")
	part(m, tableCF * CF.new(0, FLOOR + 0.35, -1.23), V3.new(3.2, 0.12, 0.06), "Neon", TINY)
	part(m, tableCF * CF.new(0, mouldTop - 0.1, 0), V3.new(3.4, 0.2, 2.2), "Frame", SOLID, "Mould")
	local y = mouldTop + 0.005
	local cavity = {
		{ -1.36, 0.26, 0.24, 0.5, 0 },
		{ -0.85, 0.26, 0.85, 0.28, 0 },
		{ 0.3, 0.2, 1.5, 0.62, 0 },
		{ 0.15, 0.58, 0.5, 0.16, 0 },
		{ 1.2, 0.2, 0.32, 0.46, 0 },
		{ 0.6, -0.5, 0.42, 0.82, -0.3 },
		{ 0.1, -0.26, 0.12, 0.26, 0.3 },
	}
	for _, piece in cavity do
		part(
			m,
			tableCF * CF.new(piece[1], y, piece[2]) * CF.Angles(0, piece[5], 0),
			V3.new(piece[3], 0.03, piece[4]),
			"Molten",
			TINY,
			"Molten"
		)
	end
end

local function foundryAnvil(m: any, F: any)
	local at = F * CF.new(ANVIL.X, 0, ANVIL.Z)
	local face, faceH = V3.new(2.6, 0.6, 1.2), 0.6
	part(m, at * CF.new(0, FLOOR + 0.45, 0), V3.new(1.9, 0.9, 1.5), "Frame", SOLID, "AnvilBase")
	part(m, at * CF.new(0, FLOOR + 0.2, 0), V3.new(2.0, 0.24, 1.6), "Trim", PROP)
	local waistBottom, waistTop = FLOOR + 0.9, ANVIL_TOP - faceH
	part(m, at * CF.new(0, (waistBottom + waistTop) / 2, 0), V3.new(0.95, waistTop - waistBottom, 0.85), "Dark", SOLID)
	part(m, at * CF.new(0, ANVIL_TOP - faceH / 2, 0), face, STEEL, SOLID, "Anvil")
	wedge(
		m,
		at * CF.new(-face.X / 2 - 0.55, ANVIL_TOP - faceH / 2, 0) * CF.Angles(0, math.pi / 2, 0) * CF.Angles(0, 0, math.pi),
		V3.new(face.Z, faceH, 1.1),
		STEEL,
		SOLID
	)
end

local function foundryRack(m: any, F: any)
	local board = part(m, F * CF.new(RACK.X, RACK.Y, RACK.Z), V3.new(6.2, 3.4, 0.2), SILHOUETTE_BOARD, PROP, "RackBoard")
	local gui = label(board, Enum.NormalId.Front, "?", rgb(30, 26, 32), 0.4)
	gui.Name = "Mystery"
	gui.Enabled = false
	local mark = gui:FindFirstChild("Text")
	mark.Name = "Mark"
	mark.Position = UDim2.fromScale(0.3, 0.05)
	mark.Size = UDim2.fromScale(0.4, 0.9)
	cylX(m, F * CF.new(RACK.X, RACK.Y + 1.85, RACK.Z - 0.05), 6.6, 0.36, "Trim", TINY)
	local plate = part(m, F * CF.new(RACK.X, RACK.Y - 1.95, RACK.Z - 0.08), V3.new(6.6, 0.6, 0.4), "Frame", TINY, "RackSign")
	label(plate, Enum.NormalId.Front, "NEXT: LV 2", TEXT)
end

local function foundryMount(base: any, F: any)
	local function at(name: string, world: any)
		attachment(base, name, base.CFrame:ToObjectSpace(world))
	end
	at("AnvilPoint", F * CF.new(ANVIL.X, ANVIL_TOP, ANVIL.Z))
	local camPos = (F * CF.new(CAMERA)).Position
	local look = (F * CF.new(ANVIL.X, ANVIL_TOP + 0.35, ANVIL.Z + 0.6)).Position
	at("CamPoint", CF.lookAt(camPos, look))
	at("Prompt", F * CF.new(ANVIL.X, 3.1, ANVIL.Z - 0.8))
	at("HopperIn", F * CF.new(FURNACE.X, HOPPER_Y + 1.7, FURNACE.Z))
	at("HopperOut", F * CF.new(FURNACE.X, HOPPER_Y + 2.6, FURNACE.Z - 2.6))
	at("RackMount", F * CF.new(RACK.X, RACK.Y + 0.1, RACK.Z - 0.12))
end

-- FoundryBuilder.build in style A (same contract: Base + attachments, Intake, RackBoard / RackSign, WarnLight, Glow / Molten).
function StyleA.foundry(plotCF: any, nextLevel: number?): any
	local m = Instance.new("Model")
	m.Name = "Foundry"
	local F = plotCF * CF.new(BaseLayout.Foundry.Center.X, 0, 41)
	local base = foundryPlatform(m, F)
	m.PrimaryPart = base
	foundryWall(m, F)
	foundryFurnace(m, F)
	foundryCasting(m, F)
	foundryAnvil(m, F)
	foundryRack(m, F)
	foundryMount(base, F)
	local intake = Geo.block(
		m,
		F * CF.new(FURNACE.X, HOPPER_Y + 2.25, FURNACE.Z),
		V3.new(3.8, 2.9, 3.8),
		P.Dark,
		nil,
		{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
	)
	intake.Name = "Intake"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	FoundryBuilder.setRack(m, nextLevel or 2)
	return m
end

-- The FOUNDRY chute receiver, repainted in style A (same parts as FoundryBuilder.receiver).
function StyleA.repaintReceiver(receiver: any)
	local C = FoundryBuilder.Colors
	for _, d in receiver:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Hood" then
				d.Color = P.Frame
			elseif d.Name == "Roof" then
				d.Color = P.Trim
			elseif d.Name == "Pipe" then
				d.Color = P.Pipe
			elseif d.Name == "Glow" then
				d.Color = P.Glow
			elseif d.Color == C.HousingLight then
				d.Color = if d.Shape == CYL then P.Trim else P.Body
			end
		end
	end
end

---------------------------------------------------------------- train stop

function StyleA.trainStop(yard: any, cf: any): any
	local rect = BaseLayout.TrainStop
	local m = model("TrainStop", yard)
	local c = rect.Center
	local platformH, bottom = 1, -0.4
	local platform = part(
		m,
		cf * CF.new(c.X, (bottom + platformH) / 2, c.Z),
		V3.new(rect.Size.X, platformH - bottom, rect.Size.Z),
		PLATE,
		SOLID,
		"Platform"
	)
	platform.Reflectance = 0.04
	local front = c.Z - rect.Size.Z / 2
	part(m, cf * CF.new(c.X, platformH * 0.5, front - 0.03), V3.new(rect.Size.X - 1, 0.14, 0.06), "Neon", TINY, "PlatformGlow")
	local railSide = c.Z + rect.Size.Z / 2
	local edge = part(m, cf * CF.new(c.X, platformH + 0.03, railSide - 0.35), V3.new(rect.Size.X, 0.06, 0.5), "Trim", TINY, "SafetyEdge")
	paint(edge, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 68 } })
	part(m, cf * CF.new(0.7, 0.25, front - 0.5), V3.new(5, 0.5, 1), "Frame", SOLID, "Step")
	-- the sign on two cream posts (both faces: the yard and the trains)
	local signZ = c.Z + 0.3
	local signW = 7.4
	for _, side in { -1, 1 } do
		local x = c.X + 5 + side * (signW / 2 + 0.45)
		cylUp(m, cf * CF.new(x, platformH + 2.65, signZ), 5.3, 0.8, "Body", FENCE, "SignPost")
	end
	sign(m, cf * CF.new(c.X + 5, platformH + 4.2, signZ), V3.new(signW + 0.2, 1.6, 0.26), "TRAIN STOP", true)
	-- lamp post: a slate foot and pole, a glowing lamp on top (neon only, lights are budgeted)
	local lamp = cf * CF.new(c.X - rect.Size.X / 2 + 1.2, platformH, signZ)
	local poleH = 5.4
	cylUp(m, lamp * CF.new(0, 0.3, 0), 0.6, 0.9, "Frame", TINY)
	cylUp(m, lamp * CF.new(0, poleH / 2, 0), poleH, 0.36, "Frame", TINY, "LampPost")
	glow(ball(m, (lamp * CF.new(0, poleH + 0.3, 0)).Position, 0.7, LAMP, TINY, "Lamp"))
	return m
end

---------------------------------------------------------------- museum (reserved)

-- The museum's footprint (BaseLayout.Museum, steps 6-7): a see-through block with its name.
function StyleA.museum(yard: any, cf: any): any
	local r = BaseLayout.Museum
	local m = model("MuseumReserved", yard)
	local h = 2.4
	local block = part(m, cf * CF.new(r.Center.X, h / 2, r.Center.Z), V3.new(r.Size.X, h, r.Size.Z), P.Glass, TINY, "Footprint")
	block.Transparency = 0.55
	label(block, Enum.NormalId.Front, "MUSEUM (coming)", P.Frame, 0.2)
	label(block, Enum.NormalId.Back, "MUSEUM (coming)", P.Frame, 0.2)
	return m
end

---------------------------------------------------------------- apply to a plot

local function countParts(root: any): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local inSilhouette = false
			local parent = d.Parent
			while parent and parent ~= root do
				if parent.Name == "Silhouette" then
					inSilhouette = true
					break
				end
				parent = parent.Parent
			end
			if not inSilhouette then
				n += 1
			end
		end
	end
	return n
end
StyleA.countParts = countParts

-- What FoundryService does at server start: every plot's placeholder becomes
-- the FoundryBuilder building, and the FOUNDRY chute gets its receiver.
function StyleA.setupFoundries(workspace: any, nextLevel: number)
	local plots = workspace:FindFirstChild("Map"):FindFirstChild("Plots")
	for _, plot in WorldLayout.Plots do
		local model_ = plots:FindFirstChild("Plot_" .. plot.Id)
		local yard = model_ and model_:FindFirstChild("Yard")
		local old = yard and yard:FindFirstChild("Foundry")
		if old then
			local plotCF = WorldLayout.plotCFrame(plot)
			old:Destroy()
			FoundryBuilder.build(plotCF, nextLevel).Parent = yard
			FoundryBuilder.receiver(plotCF).Parent = model_
		end
	end
end

export type Count = { Piece: string, Today: number, StyleA: number }

--[[
	Swaps one plot's pieces for the style A builders. Today's pieces are found
	by name in the plot model (PlotBuilder / FoundryService names):
	  Plot_<id>.Walls, Yard.Fence    the walls and posts (+ PlotSign and the
	                                 banner pole, repainted in place: the pole
	                                 is the plot's 0.5 x 13.2 x 0.5 part)
	  Yard.Pen                       the Ore Pen
	  Yard.Podium1..4                the podiums
	  Yard.Foundry                   the FoundryBuilder building (after setupFoundries)
	  Plot_<id>.FoundryReceiver      repainted in place
	  Yard.TrainStop                 the train stop (its Track placeholder is
	                                 already gone: the railway replaces it)
	Returns the part counts, today vs style A, per piece.
]]
function StyleA.apply(workspace: any, plotId: number, nextLevel: number): { Count }
	local plots = workspace:FindFirstChild("Map"):FindFirstChild("Plots")
	local plot = plots:FindFirstChild("Plot_" .. plotId)
	local yard = plot:FindFirstChild("Yard")
	local cf = WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
	local counts: { Count } = {}
	local function record(piece: string, today: number, styleA: number)
		table.insert(counts, { Piece = piece, Today = today, StyleA = styleA })
	end

	-- walls and posts
	local today = countParts(plot:FindFirstChild("Walls")) + countParts(yard:FindFirstChild("Fence"))
	plot:FindFirstChild("Walls"):Destroy()
	yard:FindFirstChild("Fence"):Destroy()
	local lamp = StyleA.padWalls(plot, cf)
	if lamp then
		local light = Instance.new("PointLight")
		light.Color = Palette.LampGlow
		light.Range = 16
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = lamp
	end
	StyleA.fence(yard, cf)
	record("Walls + posts (pad and yard)", today, countParts(plot:FindFirstChild("Walls")) + countParts(yard:FindFirstChild("Fence")))
	local plotSign = plot:FindFirstChild("PlotSign")
	if plotSign then
		plotSign.Color = P.Frame
		local text = plotSign:FindFirstChild("Text", true)
		if text then
			text.TextColor3 = TEXT
		end
	end
	for _, d in plot:GetChildren() do
		if d:IsA("BasePart") and math.abs(d.Size.Y - 13.2) < 0.01 and math.abs(d.Size.X - 0.5) < 0.01 then
			d.Color = P.Frame -- the banner pole
		end
	end

	-- the Ore Pen
	today = countParts(yard:FindFirstChild("Pen"))
	yard:FindFirstChild("Pen"):Destroy()
	StyleA.pen(yard, cf)
	record("Ore Pen", today, countParts(yard:FindFirstChild("Pen")))

	-- podiums
	for index, rect in BaseLayout.Podiums do
		local old = yard:FindFirstChild("Podium" .. index)
		today = countParts(old)
		old:Destroy()
		local new = StyleA.podium(yard, cf, index, rect)
		record("Podium" .. index .. (if index > EconomyConfig.Podiums.Free then " (locked)" else ""), today, countParts(new))
	end

	-- the Foundry building (+ its chute receiver, repainted)
	local oldFoundry = yard:FindFirstChild("Foundry")
	today = countParts(oldFoundry)
	oldFoundry:Destroy()
	local foundry = StyleA.foundry(cf, nextLevel)
	foundry.Parent = yard
	record("Foundry building (without the rack silhouette)", today, countParts(foundry))
	local receiver = plot:FindFirstChild("FoundryReceiver")
	if receiver then
		StyleA.repaintReceiver(receiver)
		record("Foundry chute receiver (repainted)", countParts(receiver), countParts(receiver))
	end

	-- the train stop
	local oldStop = yard:FindFirstChild("TrainStop")
	today = countParts(oldStop)
	oldStop:Destroy()
	local stop = StyleA.trainStop(yard, cf)
	record("Train stop", today, countParts(stop))

	-- the museum's reserved footprint (not counted: steps 6-7 build the museum)
	StyleA.museum(yard, cf)
	return counts
end

return StyleA
