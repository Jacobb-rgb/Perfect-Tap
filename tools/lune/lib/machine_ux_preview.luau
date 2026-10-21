--[[
	Previews of the machine UX (owner playtest 2026-10-20,
	build/reviews/machine_ux_map.md) on plot 5 of the real world, a small
	mid-game base placed through the game's own rules (Placement.validate on
	Layout, in order). Scenes for tools/lune/export_scene.luau, shots in
	tools/preview/machine_ux_shots.json (the shots take this file's camera:
	useSceneCamera):

	  machine_ux_build  build mode placing a Brick Furnace (PlacementController's
	                    camera, grid, chute plates and labels, the green ghost,
	                    the amber output cell, the cable to the pole it would
	                    hang on, your other machines faded) and its UI:
	                      ui_mux_build_pc     PC 1600 x 900: the info card, the
	                                          tray with live machine pictures,
	                                          the keycap chips, "Powered"
	                      ui_mux_build_phone  an 844 x 390 pt phone (rendered at
	                                          2x): touch keys and buttons, the
	                                          phone sizes (BuildView.setCompact)
	  machine_ux_power  build mode placing a Power Pole: its reach (yellow) and
	                    link (blue) squares and the preview cable to the pole it
	                    would link; ui_mux_power_pc
	  machine_ux_yard   your base outside build mode, a player in it: the status
	                    signs (working / waiting / no power / blocked, with the
	                    FULL chip), the pole's info sign, a FULL pop over the
	                    Crusher's hopper, the stack lights, the power cables;
	                    ui_mux_yard_pc (the HUD with BUILD's "B" keycap and its
	                    badge)
	  machine_ux_close  the same from the right, close along the belt line: the
	                    stack lights face the camera (red on the blocked
	                    Crusher, green on the working Cleaning Plant);
	                    ui_mux_close_pc

	Everything on screen comes from the game's own code: BuildView,
	MachineInfo, GridOverlay plates and tags, MachineBillboard (statusOf,
	wants, update, lampOf / lightStack, buildPop, attachInfo), LightSkin.world
	(the light UI's world labels), HudBubble, TeleportView. The preview stands
	in for what three.js can't draw:
	  - BillboardGuis (signs, chute labels, the pop) are projected onto the
	    picture as a ScreenGui overlay for the scene's camera
	  - live ViewportFrames (tray cards, the info card) show the machine's
	    rendered picture: the same model (BuildView.picture) is written to
	    build/preview/icon_parts/machine_<Id>.json for render_icons.mjs
	  - the ghost's Highlight is a tint and your faded machines a wash (fade),
	    particles are left out (quiet), cable Beams are thin parts
	    (KitMachines.cable, like factory_preview)
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")
local Export = require("./export")
local UiExport = require("./uiexport")
local Gallery = require("./machines_gallery")
local Dummy = require("./dummy")

local Preview = {}

local V3, C3 = roblox.Vector3, roblox.Color3
local Instance = roblox.Instance
local UDim2, Vector2 = roblox.UDim2, roblox.Vector2

Preview.Plot = 5 -- an east plot: the sun lights its yard from the pad side

-- The base: { Id, X, Z, R } in placement order (cells: x 0 is the right of the
-- build camera's view, z 0 the road side, near the camera).
Preview.Layout = {
	{ "Conveyor", 3, 11, 0 }, -- on the PEN chute, running toward the road
	{ "Conveyor", 3, 10, 0 },
	{ "AutoCleaner", 2, 8, 0 },
	{ "Conveyor", 3, 7, 0 },
	{ "Conveyor", 3, 6, 0 },
	{ "Crusher", 2, 4, 0 },
	{ "Conveyor", 3, 3, 0 },
	{ "ClayFurnace", 2, 1, 0 },
	{ "CleaningStation", 5, 9, 0 },
	{ "PowerPole", 6, 7, 0 },
	{ "SolarPanel", 8, 8, 0 },
	{ "BlastFurnace", 9, 1, 0 }, -- out of the pole's reach: no power yet
}

-- What build mode holds (picture, x, z, r), per scene.
Preview.Ghosts = {
	build = { "BrickFurnace", 6, 4, 0 }, -- the pole at (6, 7) reaches it: "Powered"
	power = { "PowerPole", 8, 4, 0 }, -- links the pole at (6, 7), reaches the Blast Furnace
}

-- Machines waiting in the tray (MachineInventory), per scene.
Preview.Inventory = {
	build = { BrickFurnace = 1, Polisher = 1, Crusher = 1, Conveyor = 14, Splitter = 2, PowerPole = 2, SolarPanel = 1, SellBox = 1 },
	power = { Polisher = 1, Crusher = 1, Conveyor = 14, Splitter = 2, PowerPole = 2, SolarPanel = 1, SellBox = 1 },
}

-- Screens: size in points, the HUD's UIScale there (HudController.uiScale),
-- the pixel ratio of the render and Roblox's top bar inset in points.
Preview.Screens = {
	pc = { W = 1600, H = 900, Scale = 1.25, Ratio = 1, Inset = 58, Kind = "Mouse" },
	phone = { W = 844, H = 390, Scale = 0.62, Ratio = 2, Inset = 58, Kind = "Touch" },
}

-- PlacementController's camera (PITCH, FOV, the zoom range 40..80) and colours.
local PITCH = math.rad(55)
local FOV = 50
local OK_COLOR = C3.fromRGB(80, 220, 120)
local OUT_COLOR = C3.fromRGB(255, 160, 40)
local OTHERS_FADE = 0.4 -- LocalTransparencyModifier of your other machines while a ghost shows
local GHOST_TRANSPARENCY = 0.5
local GHOST_FILL = 0.3 -- the ghost Highlight's fill (FillTransparency 0.7)
local FLOOR = C3.fromRGB(64, 58, 92) -- the plot's metal floor (the faded machines' wash)
local CHUTE_LIFT = 0.05
local DECK_LIFT = 0.02 -- Deck.Lift
-- Ux (PlacementController's machine UX table)
local REACH_COLOR = C3.fromRGB(255, 214, 70)
local LINK_COLOR = C3.fromRGB(120, 200, 255)
local LINE_COLOR = C3.fromRGB(255, 240, 150)
local STRIP = 0.35
local INSET = 0.3
-- MachineFxController / PowerController
local POP_LIFT = 0.6
local INFO_RANGE = 26 -- PowerController: info signs on poles and generators this close

---------------------------------------------------------------- helpers

-- Screen pixel (x, y, depth) of a world point for a camera (three.js
-- perspective, vertical fov) on a W x H picture.
local function project(CF: any, cam: any, point: any, W: number, H: number): (number?, number?, number?)
	local cf = CF.lookAt(cam.position, cam.target)
	local rel = cf:PointToObjectSpace(point)
	if rel.Z > -0.5 then
		return nil, nil, nil
	end
	local t = math.tan(math.rad(cam.fov) / 2)
	local x = (rel.X / -rel.Z) / (t * W / H)
	local y = (rel.Y / -rel.Z) / t
	return (x + 1) / 2 * W, (1 - y) / 2 * H, -rel.Z
end

local function list(v: any): { number }
	return { math.floor(v.X * 100 + 0.5) / 100, math.floor(v.Y * 100 + 0.5) / 100, math.floor(v.Z * 100 + 0.5) / 100 }
end

-- The world position of an attachment (Lune has no WorldPosition).
local function attachmentAt(attachment: any): any
	return (attachment.Parent.CFrame * attachment.CFrame).Position
end

-- Where a BillboardGui hangs in the world (its Adornee or parent: a part or an attachment).
local function billboardAt(gui: any): any
	local at = gui.Adornee or gui.Parent
	local base = if at:IsA("Attachment") then attachmentAt(at) else at.CFrame.Position
	return base + gui.StudsOffset
end

--[[
	BillboardGuis as a ScreenGui overlay for camera `cam` on a W x H picture
	(pixels: billboards don't scale with the UI): each one's children move
	into a frame of its size at the projected point. A sign's SizeOffset
	(0, 0.5) puts its bottom edge on the point. Farther ones draw first.
]]
local function overlay(CF: any, cam: any, guis: { any }, W: number, H: number): any
	local screen = Instance.new("ScreenGui")
	screen.Name = "WorldLabels"
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = -1 -- under every ScreenGui, like world labels
	local placed = {}
	for _, gui in guis do
		local at = billboardAt(gui)
		local x, y, depth = project(CF, cam, at, W, H)
		local far = gui.MaxDistance > 0 and (at - cam.position).Magnitude > gui.MaxDistance
		if x and y and depth and gui.Enabled ~= false and not far then
			table.insert(placed, { Gui = gui, X = x, Y = y, Depth = depth })
		end
	end
	table.sort(placed, function(a, b)
		return a.Depth > b.Depth
	end)
	for rank, p in placed do
		local gui = p.Gui
		local holder = Instance.new("Frame")
		holder.Name = gui.Name .. rank
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5 + gui.SizeOffset.Y)
		holder.Position = UDim2.fromOffset(p.X, p.Y)
		holder.Size = gui.Size
		holder.ZIndex = rank
		holder.Parent = screen
		for _, child in gui:GetChildren() do
			child.Parent = holder
		end
	end
	return screen
end

--[[
	A model's parts in the faded look (LocalTransparencyModifier `amount`),
	drawn as a wash toward the floor `under` instead: three.js sorts
	see-through parts by group, so a see-through machine comes out as a
	grey cloud and a see-through ghost vanishes under its glowing plate.
]]
local function fade(model: any, amount: number, under: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.Color = d.Color:Lerp(under, amount * 0.8)
		end
	end
end

-- No particles: the renderer draws an emitter as a cloud whatever its rate (idle
-- machines barely smoke in the game; the ghost's emitters are off).
local function quiet(model: any)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
end

-- PlacementController.cameraGoal: the road-side view of the plot, `zoom` studs
-- out (40..80), panned to (panX, panZ) studs from its centre.
local function buildCamera(plotCF: any, panX: number, panZ: number, zoom: number): any
	local focus = plotCF:PointToWorldSpace(V3.new(panX, 0, panZ))
	local back = plotCF:VectorToWorldSpace(V3.new(0, math.sin(PITCH), -math.cos(PITCH)))
	return { position = focus + back * zoom, target = focus, fov = FOV }
end

---------------------------------------------------------------- the base

local function placeBase(Loader: any, workspace: any, plotCF: any, extra: { any }?): ({ any }, { any }, any)
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local root = Instance.new("Model")
	root.Name = "MachineUx"
	root.Parent = workspace
	-- paint the metal floor's tile seams (SurfaceGui) on every plot plate for the renderer
	for _, plate in workspace:GetDescendants() do
		if plate:IsA("BasePart") and plate.Name == "Plate" and plate:FindFirstChild("Tiles") then
			Gallery.paintGuis(Loader, workspace, plate.Parent)
		end
	end
	local rows = table.clone(Preview.Layout)
	for _, row in extra or {} do
		table.insert(rows, row)
	end
	local entries, models = {}, {}
	for _, row in rows do
		local id, x, z, r = row[1], row[2], row[3], row[4]
		local ok, why = Placement.validate(entries, id, x, z, r, nil, nil, 0)
		assert(ok, `{id} at {x},{z}: {why}`)
		table.insert(entries, { Id = id, X = x, Z = z, R = r })
		local model = MachineBuilder.build(id)
		model:PivotTo(plotCF * Grid.localCFrame(id, x, z, r))
		model.Parent = root
		Gallery.paintGuis(Loader, root, model)
		table.insert(models, model)
	end
	return entries, models, root
end

-- PowerController's cables (Beams in the game, parts here), from PowerLogic's networks.
local function cables(Loader: any, root: any, entries: { any }, models: { any }): any
	local PowerLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.PowerLogic")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local result = PowerLogic.compute(entries, {})
	local function insulator(pole: any, toward: any): any
		local base = pole.PrimaryPart
		local l = base.CFrame:PointToWorldSpace(base:FindFirstChild("CableL").CFrame.Position)
		local r = base.CFrame:PointToWorldSpace(base:FindFirstChild("CableR").CFrame.Position)
		return if (l - toward).Magnitude <= (r - toward).Magnitude then l else r
	end
	local function sag(a: any, b: any): number
		return math.clamp((a - b).Magnitude * 0.045, 0.25, 1.6)
	end
	for i, pole in result.Poles do
		local model = models[i]
		for _, j in pole.Links do
			if j > i then
				local a = insulator(model, models[j].PrimaryPart.CFrame.Position)
				local b = insulator(models[j], model.PrimaryPart.CFrame.Position)
				KitMachines.cable(root, a, b, sag(a, b))
			end
		end
		for _, j in pole.Feeds do
			local target = models[j].PrimaryPart
			local a = insulator(model, target.CFrame.Position)
			local status = target:FindFirstChild("Status")
			local top = if status then status.CFrame.Position.Y - 1.5 else 3
			local y = math.min(top, a.Y - 0.4 - target.CFrame.Position.Y)
			local b = target.CFrame:PointToWorldSpace(V3.new(0, y, 0))
			KitMachines.cable(root, a, b, sag(a, b))
		end
	end
	return result
end

--[[
	The replicated state of each machine in the yard (the attributes
	ProcessingService / PowerService / IntakeService set) and the sign
	numbers MachineFxController passes to MachineBillboard.update:
	progress, queue, queue max, finished items, the worked ore.
]]
Preview.States = {
	Crusher = { Attr = { Status = "OutputBlocked", Queue = 4 }, Progress = 1, Queue = 4, QueueMax = 4, Out = 1, Ore = "Gold" },
	AutoCleaner = { Attr = { Working = true, Queue = 2 }, Progress = 0.62, Queue = 2, QueueMax = 4, Out = 0 },
	BlastFurnace = { Attr = { PowerSpeed = 0.6, Powered = false }, Progress = 0, Queue = 0, QueueMax = 6, Out = 0 },
	ClayFurnace = { Attr = {}, Progress = 0, Queue = 0, QueueMax = 4, Out = 0 },
	BrickFurnace = {
		Attr = { Working = true, Queue = 1, PowerSpeed = 1, Powered = true },
		Progress = 0.3,
		Queue = 1,
		QueueMax = 4,
		Out = 0,
		Ore = "Copper",
	},
	SolarPanel = { Attr = { PowerOut = 15, Network = "1" } },
	PowerPole = { Attr = { PowerSupply = 15, PowerDemand = 10 } },
}

-- Sets each machine's state attributes and lights its stack light (MachineFxController.applySignal).
local function applyStates(Loader: any, models: { any })
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")
	for _, model in models do
		local id = model:GetAttribute("MachineId")
		local state = Preview.States[id]
		if state then
			for key, value in state.Attr do
				model:SetAttribute(key, value)
			end
		end
		local lamps = MachineBillboard.stackLamps(model)
		if lamps then
			MachineBillboard.lightStack(lamps, MachineBillboard.lampOf(model:GetAttributes(), MachineData.ById[id]))
		end
	end
end

---------------------------------------------------------------- machine pictures

-- The tray and info card pictures: the same model as the game's ViewportFrames.
local function writePictures(Loader: any, ids: { string })
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local root = Loader.root
	fs.writeDir(root .. "/build/preview/icon_parts")
	for _, id in ids do
		local model = BuildView.picture(id)
		fs.writeFile(root .. "/build/preview/icon_parts/machine_" .. id .. ".json", serde.encode("json", Export.collect(model)))
	end
end

-- Every live picture in a build UI shows its machine's rendered picture.
local function markPictures(refs: any)
	for id, card in refs.Cards do
		if card.Picture then
			card.Picture:SetAttribute("Icon", "machine_" .. id)
		end
	end
	local shown = refs.Info.Id
	if shown then
		refs.Info.View:SetAttribute("Icon", "machine_" .. shown)
	end
end

---------------------------------------------------------------- build mode

--[[
	The build-mode world: GridOverlay's lines, chute plates and labels, the
	ghost with its footprint and output plates, the power preview. Returns
	the power preview (MachineInfo.powerPreview) and the labels (BillboardGuis).
]]
local function buildWorld(Loader: any, root: any, plotCF: any, entries: { any }, models: { any }, ghostRow: { any }): (any, { any })
	local CF = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local MachineInfo = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineInfo")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local GridOverlay = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GridOverlay")
	local CELL = GameConfig.CellSize
	local CELLS = GameConfig.PlotCells
	local HALF = CELLS * CELL / 2

	local function cellsCFrame(x: number, z: number, w: number, d: number, level: number?): any
		return plotCF * CF.new(-HALF + (x + w / 2) * CELL, Grid.levelY(level), -HALF + (z + d / 2) * CELL)
	end

	-- the grid lines (GridOverlay.show: one line along X and one along Z per cell edge)
	local folder = GridOverlay.folder()
	local alongX, alongZ = 0, 0
	for _, line in folder:GetChildren() do
		if line.Name == "GridLine" then
			if line.Size.X > line.Size.Z then
				line.CFrame = plotCF * CF.new(0, 0.04, -HALF + alongX * CELL)
				alongX += 1
			else
				line.CFrame = plotCF * CF.new(-HALF + alongZ * CELL, 0.04, 0)
				alongZ += 1
			end
		end
	end
	-- the chutes (PlacementController.updateChutes)
	for _, name in BaseLayout.ChuteNames do
		local chute = BaseLayout.Chutes[name]
		local plateName = "Chute" .. name
		GridOverlay.plate(plateName, cellsCFrame(chute.X, chute.Z, 1, 1) * CF.new(0, CHUTE_LIFT, 0), CELL, CELL, chute.Color)
		GridOverlay.tag(plateName, chute.Label, chute.Color)
	end
	-- your other machines turn see-through while a ghost shows
	for _, model in models do
		fade(model, OTHERS_FADE, FLOOR)
		quiet(model)
	end
	-- the ghost (ghostFor + its Highlight), its footprint and output plates (updateVisuals)
	local id, x, z, r = ghostRow[1], ghostRow[2], ghostRow[3], ghostRow[4]
	local ok, why = Placement.validate(entries, id, x, z, r, nil, nil, 0)
	assert(ok, `ghost {id}: {why}`)
	local ghost = MachineBuilder.build(id)
	ghost.Name = "Ghost_" .. id
	ghost:PivotTo(plotCF * Grid.localCFrame(id, x, z, r))
	-- (solid here, tinted by the Highlight's fill: see fade)
	for _, d in ghost:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Color = d.Color:Lerp(OK_COLOR, GHOST_FILL + GHOST_TRANSPARENCY * 0.4)
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	ghost.Parent = folder
	local w, d = Grid.footprint(id, r)
	GridOverlay.plate("Footprint", cellsCFrame(x, z, w, d, 0), w * CELL, d * CELL, OK_COLOR)
	local ox, oz = Grid.outputCell(id, x, z, r)
	if ox and oz then
		GridOverlay.plate("Out", cellsCFrame(ox, oz, 1, 1, 0), CELL, CELL, OUT_COLOR)
	end

	-- the power preview (Ux.showPower / Ux.square / Ux.line)
	local machine = MachineData.ById[id]
	local preview = MachineInfo.powerPreview(entries, { Id = id, X = x, Z = z, R = r }, nil)
	local function square(prefix: string, x0: number, z0: number, x1: number, z1: number, color: any)
		local cw, cd = x1 - x0 + 1, z1 - z0 + 1
		local sw, sd = cw * CELL, cd * CELL
		local centre = cellsCFrame(x0, z0, cw, cd, 0) * CF.new(0, DECK_LIFT * 4, 0)
		local strip, half = STRIP + INSET, STRIP / 2
		GridOverlay.plate(prefix .. "N", centre * CF.new(0, 0, -sd / 2 + half), sw + INSET, strip, color)
		GridOverlay.plate(prefix .. "S", centre * CF.new(0, 0, sd / 2 - half), sw + INSET, strip, color)
		GridOverlay.plate(prefix .. "W", centre * CF.new(-sw / 2 + half, 0, 0), strip, sd + INSET, color)
		GridOverlay.plate(prefix .. "E", centre * CF.new(sw / 2 - half, 0, 0), strip, sd + INSET, color)
	end
	local function line(index: number, ax: number, az: number, bx: number, bz: number)
		local mx, mz, length, yaw = MachineInfo.segment(ax, az, bx, bz)
		local cf = plotCF * CF.new(-HALF + mx * CELL, Grid.levelY(0) + DECK_LIFT * 5, -HALF + mz * CELL) * CF.Angles(0, yaw, 0)
		GridOverlay.plate("PowerLine" .. index, cf, STRIP + INSET, length * CELL + INSET, LINE_COLOR)
	end
	local rules = MachineData.PowerRules
	if machine.IsPole then
		local rx0, rz0, rx1, rz1 = MachineInfo.area(x, z, rules.PoleReach, CELLS)
		square("PowerReach", rx0, rz0, rx1, rz1, REACH_COLOR)
		local lx0, lz0, lx1, lz1 = MachineInfo.area(x, z, rules.PoleLink, CELLS)
		square("PowerLink", lx0, lz0, lx1, lz1, LINK_COLOR)
		for i, pole in preview.Links do
			line(i, x + 0.5, z + 0.5, pole.X + 0.5, pole.Z + 0.5)
		end
	elseif preview.Pole then
		line(1, x + w / 2, z + d / 2, preview.Pole.X + 0.5, preview.Pole.Z + 0.5)
	end
	folder.Parent = root

	-- the labels: the chute tags in the light UI's world look (LightWorldController)
	local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
	local labels = {}
	for _, gui in folder:GetDescendants() do
		if gui:IsA("BillboardGui") then
			LightSkin.world(gui)
			table.insert(labels, gui)
		end
	end
	return preview, labels
end

--[[
	The HUD as build mode leaves it (PlacementController.hideHud: the carry
	panel, the side menu and the top bar hide) and the build UI, for a screen
	(Preview.Screens) placing `id`.
]]
local function buildUi(Loader: any, screen: any, id: string, inventory: { [string]: number }, entries: { any }, preview: any): { any }
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local MachineInfo = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineInfo")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local render = screen.Scale * screen.Ratio

	local hud = HudBubble.buildGame(screen.Scale, screen.W)
	hud.Gui.Scale.Scale = render
	hud.Coins.Text = Format.money(48250)
	hud.CarryPanel.Visible = false
	hud.Menu.Visible = false
	hud.TopBar.Visible = false

	local touch = screen.Kind == "Touch"
	local refs = BuildView.build()
	refs.Gui.Enabled = true
	refs.Gui.Scale.Scale = render
	-- PlacementController.refreshUI, then updateVisuals (Ux.showInfo, the reason line)
	BuildView.setInventory(refs, inventory, id, function() end, nil)
	local machines, conveyors = Placement.counts(entries)
	local limits = Placement.limits(2, false)
	BuildView.setCounts(refs, machines, limits.Machines, conveyors, limits.Conveyors)
	BuildView.setMode(refs, "Placing", touch, false)
	BuildView.setLayer(refs, false)
	local compact = touch or screen.Scale <= BuildView.CompactScale
	BuildView.setCompact(refs, compact, BuildView.infoRoom((screen.H - screen.Inset) / screen.Scale))
	BuildView.setKeys(refs, BuildView.keys(screen.Kind, "Placing", { Belt = false, Decks = false }), nil)
	BuildView.setInfo(refs, MachineInfo.describe(id), nil)
	if preview and preview.Text then
		BuildView.setReason(refs, preview.Text, if preview.Good then "Good" else "Warn")
	end
	markPictures(refs)
	return { hud.Gui, refs.Gui }
end

local function buildScene(Loader: any, workspace: any, which: string): (any, { [string]: any })
	local CF = Loader.CFrame
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[Preview.Plot])
	local extra = if which == "power" then { Preview.Ghosts.build } else nil
	local entries, models, root = placeBase(Loader, workspace, plotCF, extra)
	applyStates(Loader, models)
	cables(Loader, root, entries, models)
	local ghostRow = Preview.Ghosts[which]
	local preview, labels = buildWorld(Loader, root, plotCF, entries, models, ghostRow)
	local inventory = Preview.Inventory[which]
	local ids = { ghostRow[1] }
	for id in inventory do
		table.insert(ids, id)
	end
	writePictures(Loader, ids)

	-- the build camera, panned so the ghost clears the info card (the pole a little closer)
	local cam = if which == "power" then buildCamera(plotCF, 9, -1, 46) else buildCamera(plotCF, 3, -4, 60)
	UIConfig.LightUI = true
	local exports: { [string]: any } = {}
	local screens = if which == "power" then { "pc" } else { "pc", "phone" }
	for _, name in screens do
		local screen = Preview.Screens[name]
		local W, H = screen.W * screen.Ratio, screen.H * screen.Ratio
		-- the labels again for each screen (overlay takes their children)
		local copies = {}
		for _, gui in labels do
			local copy = gui:Clone()
			if gui.Adornee then
				copy.Adornee = gui.Adornee
			end
			copy.Parent = gui.Parent
			table.insert(copies, copy)
		end
		local guis = buildUi(Loader, screen, ghostRow[1], inventory, entries, preview)
		table.insert(guis, 1, overlay(CF, cam, copies, W, H))
		exports[`ui_mux_{which}_{name}`] = UiExport.export(guis)
	end
	for _, gui in labels do
		gui:Destroy()
	end
	UIConfig.LightUI = UIConfig.Default
	return { camera = list(cam.position), target = list(cam.target), fov = cam.fov }, exports
end

---------------------------------------------------------------- the yard

--[[
	Where you stand and the camera, per yard scene (Feet / Look: { x, z } in
	plot cells; Camera / Target: { x cells, studs up, z cells }): the overview
	from the road side (the sun behind it), and a close look from the right
	along the belt line, where the stack lights face the camera.
]]
Preview.Views = {
	yard = { Feet = { 5.4, 2.2 }, Look = { 4.6, 8 }, Camera = { 6.5, 30, -1 }, Target = { 6, 0, 5 }, Fov = 60 },
	close = { Feet = { 0.8, 6.6 }, Look = { 6, 6.6 }, Camera = { -2.5, 24, 6.5 }, Target = { 3, 3, 6.5 }, Fov = 40 },
}

local function yardScene(Loader: any, workspace: any, which: string): (any, { [string]: any })
	local view = Preview.Views[which]
	local CF = Loader.CFrame
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")
	local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local CELL = GameConfig.CellSize
	local HALF = GameConfig.PlotCells * CELL / 2
	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[Preview.Plot])
	local entries, models, root = placeBase(Loader, workspace, plotCF, { Preview.Ghosts.build })
	applyStates(Loader, models)
	cables(Loader, root, entries, models)
	for _, model in models do
		if model:GetAttribute("Working") ~= true then
			quiet(model) -- only working furnaces smoke and spark
		end
	end

	-- ore on the belts
	local items = {
		{ 3, 11, { Kind = "Raw", OreId = "Gold" }, 0.1 },
		{ 3, 10, { Kind = "Raw", OreId = "Copper" }, -0.2 },
		{ 3, 7, { Kind = "Clean", OreId = "Silver", Grade = "Clean" }, 0 },
		{ 3, 6, { Kind = "Clean", OreId = "Gold", Grade = "Clean" }, 0.2 },
		{ 3, 3, { Kind = "Crushed", OreId = "Gold", Grade = "Clean" }, 0 },
	}
	for i, it in items do
		local cf = plotCF * Grid.localCFrame("Conveyor", it[1], it[2], 0) * CF.new(0, 1.05, it[4] * CELL)
		ItemBuilder.build(it[3], cf * CF.Angles(0, 0.7 * i, 0), i).Parent = root
	end

	-- you, in your yard between the machines (the signs measure from here)
	local feet = plotCF:PointToWorldSpace(V3.new(-HALF + view.Feet[1] * CELL, 0.2, -HALF + view.Feet[2] * CELL))
	local look = plotCF:PointToWorldSpace(V3.new(-HALF + view.Look[1] * CELL, 0.2, -HALF + view.Look[2] * CELL))
	Dummy.build(root, CF, CF.lookAt(feet, V3.new(look.X, feet.Y, look.Z)), "idle", nil)

	-- the signs MachineFxController / PowerController would show
	local signs = {}
	for _, model in models do
		local id = model:GetAttribute("MachineId")
		local info = MachineData.ById[id]
		local attrs = model:GetAttributes()
		local state = Preview.States[id]
		local distance = (model:GetPivot().Position - feet).Magnitude
		local status = MachineBillboard.statusOf(attrs, info)
		if state and state.Progress and MachineBillboard.wants(attrs, status, distance) then
			local refs = MachineBillboard.attach(model)
			local ore = if state.Ore then OreData.ById[state.Ore] else nil
			MachineBillboard.update(refs, state.Progress, state.Queue, state.QueueMax, state.Out, status, if ore then ore.Color else nil)
			LightSkin.world(refs.Gui)
			table.insert(signs, refs.Gui)
		elseif info and (info.IsPole or (info.PowerOut or 0) > 0) and distance <= INFO_RANGE then
			local refs = MachineBillboard.attachInfo(model)
			LightSkin.world(refs.Gui)
			table.insert(signs, refs.Gui)
		end
		if id == "Crusher" then
			-- a dropped ore the full hopper refused: the FULL pop, part way up
			local anchor = Instance.new("Part")
			anchor.Name = "FullPop"
			anchor.Transparency = 1
			anchor.Anchored = true
			anchor.Size = V3.new(0.2, 0.2, 0.2)
			anchor.CFrame = CF.new(attachmentAt(model.PrimaryPart:FindFirstChild("Intake")))
			anchor.Parent = root
			local pop = MachineBillboard.buildPop(anchor)
			pop.Gui.Enabled = true
			pop.Gui.StudsOffset = V3.new(0, POP_LIFT + 1.2, 0)
			LightSkin.world(pop.Gui)
			table.insert(signs, pop.Gui)
		end
	end

	-- the camera: behind you, a little above
	local c, t = view.Camera, view.Target
	local camPos = plotCF:PointToWorldSpace(V3.new(-HALF + c[1] * CELL, c[2], -HALF + c[3] * CELL))
	local camTarget = plotCF:PointToWorldSpace(V3.new(-HALF + t[1] * CELL, t[2], -HALF + t[3] * CELL))
	local cam = { position = camPos, target = camTarget, fov = view.Fov }

	-- the HUD with BUILD: its keycap and the machines waiting to be placed
	UIConfig.LightUI = true
	local screen = Preview.Screens.pc
	local hud = HudBubble.buildGame(screen.Scale, screen.W)
	hud.Gui.Scale.Scale = screen.Scale
	local build = BuildView.menuButton(hud.Menu)
	BuildView.setMenuKey(build, "B", nil)
	BuildView.setMenuBadge(build, 2)
	local teleport = TeleportView.build(hud.TopBar, 1, screen.W)
	TeleportView.relayout(teleport, hud.TopBar, 1, screen.W)
	hud.Coins.Text = Format.money(48250)
	hud.CarryLabel.Text = "CARRYING 0/3"
	HudBubble.slot(hud.CarrySlots, nil, 1)
	HudBubble.slot(hud.CarrySlots, nil, 2)
	HudBubble.slot(hud.CarrySlots, nil, 3)
	UIConfig.LightUI = UIConfig.Default
	local exports = {
		[`ui_mux_{which}_pc`] = UiExport.export({ overlay(CF, cam, signs, screen.W, screen.H), hud.Gui }),
	}
	return { camera = list(cam.position), target = list(cam.target), fov = cam.fov }, exports
end

--[[
	Builds scene `which` ("build" | "power" | "yard" | "close") into workspace (the
	world is already there). Returns the camera for the scene file
	(useSceneCamera) and the UI overlays { name = guis }.
]]
function Preview.build(Loader: any, workspace: any, which: string): (any, { [string]: any })
	if Preview.Views[which] then
		return yardScene(Loader, workspace, which)
	end
	assert(Preview.Ghosts[which], "machine_ux scene: build, power, yard or close")
	return buildScene(Loader, workspace, which)
end

return Preview
