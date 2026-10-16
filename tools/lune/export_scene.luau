--[[
	Builds a preview scene with the real game builders and writes it as JSON
	for tools/preview/render.mjs.

	  lune run tools/lune/export_scene.luau [scene]
	Scenes: world (default), style (the lobby Style kit gallery), lobby_blockout
	(world + a box per LobbyLayout set piece), gameplay, cleaning
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local sceneName = process.args[1] or "world"

local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")

local function presetToJson(preset)
	local out = {}
	for group, values in preset do
		out[group] = {}
		for key, value in values do
			if typeof(value) == "Color3" then
				out[group][key] = { value.R, value.G, value.B }
			else
				out[group][key] = value
			end
		end
	end
	return out
end

local function addNodes(parent)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Nodes"
	folder.Parent = parent
	for index, spawn in WorldBuilder.generateNodeSpawns() do
		local zone = WorldLayout.ZoneById[spawn.Zone]
		local rng = Rng.new(index * 97 + 5)
		local oreId = rng:weighted(zone.Ores)
		local node = OreNodeBuilder.build(oreId, roblox.CFrame.new(spawn.Position), index)
		node.Parent = folder
		-- show a mix of crack stages so the preview shows them
		if index % 5 == 1 then
			OreNodeBuilder.applyStage(node, 1, index)
		elseif index % 5 == 2 then
			OreNodeBuilder.applyStage(node, 1, index)
			OreNodeBuilder.applyStage(node, 2, index)
		end
	end
end

local uiExports: { [string]: { any } } = {}
local scene_extra: any = nil

if sceneName == "world" then
	WorldBuilder.build(workspace)
	addNodes(workspace)
elseif sceneName == "style" then
	-- the lobby style kit (src/server/World/Lobby/Style.luau), one of each helper
	require("./lib/style_gallery").build(Loader, workspace)
elseif sceneName == "lobby_blockout" then
	-- the world plus a translucent box for every lobby set piece (LobbyLayout)
	WorldBuilder.build(workspace)
	require("./lib/lobby_blockout").build(Loader, workspace)
elseif sceneName == "blasters" or sceneName == "blaster_fire" then
	-- laser blasters: the 10 levels in ore skins / a forgekeeper blasting a quarry rock
	require("./lib/blaster_gallery").build(Loader, workspace, sceneName)
elseif sceneName == "gameplay" then
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local Dummy = require("./lib/dummy")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local BlasterGallery = require("./lib/blaster_gallery")
	WorldBuilder.build(workspace)
	local props = roblox.Instance.new("Folder")
	props.Name = "Props"
	props.Parent = workspace

	-- 1) mining in the quarry: a cracked Silver node, chunks flying
	local nodePos = V3.new(-30, -12, -165)
	local node = OreNodeBuilder.build("Silver", CF.new(nodePos) * CF.Angles(0, 0.6, 0), 42)
	OreNodeBuilder.applyStage(node, 1, 42)
	node.Parent = props
	local root = CF.lookAt(nodePos + V3.new(4.2, 0, 4.2), nodePos)
	local hit = BlasterGallery.surface(node, root.Position, 0.5)
	local _, muzzle = BlasterGallery.forgekeeper(Loader, props, root, hit, 2, "Copper")
	BlasterGallery.beam(Loader, props, muzzle, hit, Loader.requirePath("ReplicatedStorage.Shared.Config.OreData").ById.Copper.Glow)
	local chunkSpots = {
		{ V3.new(-31, -6.5, -161), "Silver" },
		{ V3.new(-28.5, -5, -163.5), "Silver" },
		{ V3.new(-24, -11.2, -157), "Copper" },
		{ V3.new(-21, -11.2, -160), "Copper" },
		{ V3.new(-23, -11.2, -154), "Iron" },
	}
	for i, spot in chunkSpots do
		local item = ItemBuilder.build({ Kind = "Raw", OreId = spot[2] }, CF.new(spot[1]) * CF.Angles(i, i * 2, 0), i)
		item.Parent = props
	end
	-- a second forgekeeper carrying ore back to town
	local carrier = CF.lookAt(V3.new(-12, -12, -150), V3.new(0, -12, -130))
	Dummy.build(props, CF, carrier, "carry", { shirt = roblox.Color3.fromRGB(70, 120, 170), pants = roblox.Color3.fromRGB(50, 50, 60) })
	for i, oreId in { "Copper", "Iron", "Silver" } do
		local item = ItemBuilder.build({ Kind = "Raw", OreId = oreId }, carrier * Dummy.stackOffset(CF, i) * CF.new(0, 3, 0), i + 10)
		item.Parent = props
	end
	-- a few more nodes around
	local extra = { { V3.new(-44, -12, -150), "Copper" }, { V3.new(-15, -12, -185), "Gold" }, { V3.new(-48, -12, -180), "Iron" } }
	for i, e in extra do
		local n = OreNodeBuilder.build(e[2], CF.new(e[1]), i * 7)
		n.Parent = props
	end

	-- 2) item showcase on plot 1
	local plot = WorldLayout.Plots[5]
	local base = WorldLayout.plotCFrame(plot) * CF.new(0, 0.6, 0)
	local rows = {
		{ "Raw", nil, nil },
		{ "Clean", "Rough", nil },
		{ "Clean", "Flawless", nil },
		{ "Crushed", "Clean", nil },
		{ "Ingot", "Pristine", nil },
		{ "Gear", "Clean", "Dagger" },
		{ "Gear", "Clean", "Helm" },
	}
	local ores = { "Copper", "Silver", "Gold", "Azurium", "Stormcore", "Heartstone" }
	for r, row in rows do
		for c, oreId in ores do
			local cf = base * CF.new((c - 3.5) * 3.2, 0.4, (r - 4) * 3.2) * CF.Angles(0, 0.35, 0)
			local item = ItemBuilder.build({ Kind = row[1], OreId = oreId, Grade = row[2], Recipe = row[3] }, cf, r * 10 + c)
			item.Parent = props
		end
	end

	-- HUD as the player would see it while mining
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local refs = HudView.build()
	refs.Gui.Scale.Scale = 1.25
	refs.Coins.Text = "1,240"
	refs.Zone.Text = "Greystone Quarry"
	refs.Zone.TextTransparency = 0
	refs.CarryLabel.Text = "CARRYING 2/3"
	HudView.slot(refs.CarrySlots, Rarity.get("Uncommon").Color, 1)
	HudView.slot(refs.CarrySlots, Rarity.get("Common").Color, 2)
	HudView.slot(refs.CarrySlots, nil, 3)
	HudView.toast(refs.Toasts, "New ore discovered: Silver!", Rarity.get("Uncommon").Color)
	uiExports.hud_mining = UiExport.export({ refs.Gui })
elseif sceneName == "cleaning" then
	local CF = Loader.CFrame
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
	WorldBuilder.build(workspace)
	-- plot 1 with the starter kit, like a new player
	local plot = WorldLayout.Plots[1]
	local plotCf = WorldLayout.plotCFrame(plot)
	local stationCf
	for _, entry in MachineData.StarterKit do
		local machine = MachineData.ById[entry.Id]
		local w, d = MachineData.footprint(machine, entry.R)
		local half = GameConfig.PlotCells * GameConfig.CellSize / 2
		local cf = plotCf * CF.new(-half + (entry.X + w / 2) * GameConfig.CellSize, 0, -half + (entry.Z + d / 2) * GameConfig.CellSize) * CF.Angles(0, -entry.R * math.pi / 2, 0)
		local model = MachineBuilder.build(entry.Id)
		model:PivotTo(cf)
		model.Parent = workspace
		if entry.Id == "CleaningStation" then
			stationCf = cf
		end
	end
	local base = stationCf
	local orePoint = base * CF.new(0, 3.4 + 1.95, 0.3)
	local camPos = (base * CF.new(0, 3.4 + 5.4, -4.6)).Position
	local oreId = process.args[2] or "Gold"
	local pattern = Patterns.generate(oreId, 4242)
	local workCf = CF.lookAt(orePoint.Position, orePoint.Position - (camPos - orePoint.Position).Unit)
	local shell = OreShellBuilder.build(pattern, workCf, workspace)
	local stage = process.args[3] or "chisel"
	local fx = roblox.Instance.new("Folder")
	fx.Parent = workspace
	local scrapedCount = 0
	local workLight = OreShellBuilder.workLight(workCf, fx)
	if stage == "reveal" then
		local lamp: any = workLight:FindFirstChildOfClass("PointLight")
		lamp.Brightness = 0.4
	end
	if stage == "chisel" then
		local cut = pattern.Cuts[1]
		OreShellBuilder.guideDots(shell, cut, roblox.Color3.fromRGB(255, 230, 140), fx)
		OreShellBuilder.updateGroove(shell, cut, 0.45, 1, {}, fx, roblox.Color3.fromRGB(255, 160, 60))
		-- like ChiselStep once a cut started: the start end is dark and the far end stays as
		-- the goal ("phone" shows the finger lifted: no tool, a white ball at the groove tip)
		local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
		local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
		local function marker(p, size, color)
			local world = workCf:PointToWorldSpace(roblox.Vector3.new(p.X * OreShellBuilder.Scale, p.Y * OreShellBuilder.Scale, OreShellBuilder.DotZ + 0.03))
			Geo.ball(fx, world, size, color, roblox.Enum.Material.Neon, { CanCollide = false, CastShadow = false })
		end
		marker(cut.Line[#cut.Line], 0.2, roblox.Color3.fromRGB(255, 232, 150))
		if process.args[4] == "phone" then
			marker(Geometry2D.pointAt(cut.Line, cut.Length * 0.45), 0.2, roblox.Color3.fromRGB(255, 255, 255))
		end
	elseif stage == "scrape" or stage == "polish" or stage == "reveal" then
		for _, caps in shell.Caps do
			for _, cap in caps do
				cap:Destroy()
			end
		end
		for _, part in shell.CoreRim do
			part.Transparency = 0
		end
		if stage == "scrape" then
			local i = 0
			for _, patch in shell.Dirt do
				i += 1
				if i % 3 ~= 0 then
					patch:Destroy()
					scrapedCount += 1
				end
			end
		else
			for _, patch in shell.Dirt do
				patch:Destroy()
			end
			local ore = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData").get(oreId)
			for _, part in shell.Core do
				part.Color = ore.Color
				part.Reflectance = 0.25
			end
		end
	end
	-- tool in hand + UI overlay, as the real controller would show it
	local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local ore = OreData.get(oreId)
	local function toolAt(u, v, kind)
		local tip = workCf:PointToWorldSpace(roblox.Vector3.new(u * OreShellBuilder.Scale, v * OreShellBuilder.Scale, OreShellBuilder.DotZ + 0.05))
		local axis = workCf:VectorToWorldSpace(roblox.Vector3.new(0.35, 0.5, 0.8)).Unit
		local right = axis:Cross(workCf.LookVector * -1).Unit
		local back = right:Cross(axis).Unit
		local cf = CF.fromMatrix(tip, right, axis, back)
		-- a working (pressed) chisel is see-through, like CleaningController.updateTool
		local props = { CanCollide = false, Transparency = if kind == "Chisel" then 0.55 else 0 }
		if kind == "Chisel" then
			Geo.wedge(fx, cf * CF.new(0, 0.12, 0) * CF.Angles(math.pi, 0, 0), roblox.Vector3.new(0.16, 0.24, 0.12), roblox.Color3.fromRGB(200, 205, 215), roblox.Enum.Material.Metal, props)
			Geo.block(fx, cf * CF.new(0, 0.5, 0), roblox.Vector3.new(0.16, 0.55, 0.12), roblox.Color3.fromRGB(170, 176, 188), roblox.Enum.Material.Metal, props)
			Geo.block(fx, cf * CF.new(0, 1.1, 0), roblox.Vector3.new(0.24, 0.7, 0.24), roblox.Color3.fromRGB(150, 98, 56), nil, props)
		elseif kind == "Brush" then
			for x = -1, 1 do
				Geo.block(fx, cf * CF.new(x * 0.11, 0.1, 0), roblox.Vector3.new(0.08, 0.22, 0.32), roblox.Color3.fromRGB(230, 205, 140), nil, props)
			end
			Geo.block(fx, cf * CF.new(0, 0.3, 0), roblox.Vector3.new(0.42, 0.18, 0.4), roblox.Color3.fromRGB(150, 98, 56), nil, props)
			Geo.block(fx, cf * CF.new(0, 0.75, 0.05), roblox.Vector3.new(0.16, 0.8, 0.16), roblox.Color3.fromRGB(120, 80, 48), nil, props)
		else
			Geo.block(fx, cf * CF.new(0, 0.1, 0), roblox.Vector3.new(0.6, 0.18, 0.5), roblox.Color3.fromRGB(240, 222, 190), nil, props)
		end
	end
	-- "phone": an iPhone SE-sized screen (375 pt tall) scaled up to the 900 px render
	local phone = process.args[4] == "phone"
	local pxPerPoint = 900 / 375
	local uiScale = if phone then 0.62 * pxPerPoint else 1.25
	local insetTop = if phone then 58 * pxPerPoint else 36
	local view = CleaningView.build({ Touch = phone })
	view.Gui.Scale.Scale = uiScale
	CleaningView.setCompact(view, phone, if phone then 70 else 48)
	local CameraFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CameraFit")
	local camPoint = CF.lookAt(camPos, orePoint.Position + roblox.Vector3.new(0, 0.1, 0))
	local camCf, camFov = CameraFit.compute({
		ViewportHeight = 900,
		InsetTop = insetTop,
		FreeTop = if phone then 16 else CleaningView.BannerBottom,
		FreeBottom = CleaningView.BottomReserved,
		UiScale = uiScale,
		Outline = pattern.Outline,
		FaceScale = OreShellBuilder.Scale,
		CamPoint = camPoint,
		OrePoint = orePoint.Position,
	})
	if stage == "chisel" then
		local p = Geometry2D.pointAt(pattern.Cuts[1].Line, pattern.Cuts[1].Length * 0.45)
		if not phone then
			toolAt(p.X, p.Y, "Chisel")
		end
		CleaningView.setStep(view, 1, "CHISEL", "Cut 1 of " .. #pattern.Cuts .. ": trace the glowing line.")
		CleaningView.setMeter(view, 0.94)
		view.Progress.Text = "Cut 1 / " .. #pattern.Cuts
		view.Feedback.TextTransparency = 0
		if phone then
			-- the long hint at the size CleaningController.feedback gives it
			view.Feedback.Text = "Continue from the glowing tip!"
			view.Feedback.TextSize = 28
			view.Feedback.TextColor3 = roblox.Color3.fromRGB(255, 200, 90)
		else
			view.Feedback.Text = "Great cut!"
			view.Feedback.TextColor3 = roblox.Color3.fromRGB(160, 255, 170)
		end
		view.Hint.Text = if phone then "Drag with your finger" else "Hold the left mouse button and drag"
	elseif stage == "scrape" then
		toolAt(-0.15, 0.1, "Brush")
		CleaningView.setStep(view, 2, "SCRAPE", "Brush away the dirt. Careful: don't scrape the glowing crystals!")
		CleaningView.setMeter(view, 0.9)
		view.Chips.Text = "Chips: 1"
		view.Progress.Text = "Dirt: " .. scrapedCount .. " / " .. pattern.DirtCount
		view.Hint.Text = "Drag with your finger"
	elseif stage == "polish" then
		toolAt(0.35, -0.3, "Cloth")
		CleaningView.setStep(view, 3, "POLISH", "Rub in circles around the ore. Keep the SPEED needle in the green!")
		CleaningView.setMeter(view, 0.88)
		view.Chips.Text = "Chips: 1"
		view.Progress.Text = "Shine: 72%"
		view.Gauge.Visible = true
		local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningScoring")
		view.GaugeNeedle.Position = roblox.UDim2.fromScale(Scoring.needleFor(Scoring.PolishBand.Demo), 0.5)
		view.RubToggle.Text = "Easy polish (R): OFF"
		view.Shine.Visible = true
		view.ShineFill.Size = roblox.UDim2.fromScale(0.72, 1)
		view.RubToggle.Parent.Visible = true
		view.Feedback.Text = "Shiny!"
		view.Feedback.TextTransparency = 0
		view.Feedback.TextColor3 = roblox.Color3.fromRGB(255, 240, 170)
	elseif stage == "reveal" then
		CleaningView.setReveal(view, "Let's see what you uncovered...")
		-- Leave is hidden during the reveal (only Collect works)
		view.Leave.Parent.Visible = false
		CleaningView.setMeter(view, 0.95)
		local grade = ItemData.GradeById.Flawless
		local rarity = Rarity.get(ore.Rarity)
		view.CardGrade.Text = "FLAWLESS"
		view.CardGrade.TextColor3 = grade.Color
		view.CardStars.Text = "★★★★"
		view.CardOre.Text = ore.Name .. "  (" .. rarity.Name .. ")"
		view.CardOre.TextColor3 = rarity.Color
		view.CardValue.Text = "Worth " .. ItemData.value("Clean", oreId, "Flawless") .. " coins"
		view.CardDetail.Text = "Chisel 96%  ·  Scrape 100%  ·  Polish 91%  ·  Chips 0"
		view.Card.Visible = true
		-- core lifted out and glowing, rays around it
		local lift = workCf:VectorToWorldSpace(roblox.Vector3.new(0, 0.2, 0.9))
		for _, part in shell.Core do
			part.CFrame = part.CFrame + lift
		end
		for _, part in shell.CoreRim do
			part.CFrame = part.CFrame + lift
			part.Transparency = 0.6
		end
		local center = orePoint.Position + (camPos - orePoint.Position).Unit * 0.6
		local rayCount = if rarity.Order >= 6 then 12 else 8
		for i = 1, rayCount do
			local a = i / rayCount * math.pi * 2 + 0.8
			local dir = workCf:VectorToWorldSpace(roblox.Vector3.new(math.cos(a), math.sin(a), 0.15))
			Geo.block(fx, CF.lookAt(center + dir * 3.2, center + dir * 4), roblox.Vector3.new(0.12, 0.12, 6), rarity.Color, roblox.Enum.Material.Neon, { CanCollide = false, Transparency = 0.7 })
		end
		-- the glow light stays at the vise (behind the lifted core), like the controller's holder
		local holder = Geo.ball(fx, workCf:PointToWorldSpace(roblox.Vector3.new(0, 0, OreShellBuilder.CoreFront - 0.4)), 0.1, ore.Glow, nil, { CanCollide = false, Transparency = 1 })
		local light = roblox.Instance.new("PointLight")
		light.Color = ore.Glow
		light.Range = 18
		light.Brightness = 2
		light.Parent = holder
	end
	local suffix = if phone then "_phone" else ""
	uiExports["ui_clean_" .. stage .. suffix] = UiExport.export({ view.Gui })
	local look = camCf.Position + camCf.LookVector * 10
	scene_extra = {
		camera = { camCf.Position.X, camCf.Position.Y, camCf.Position.Z },
		target = { look.X, look.Y, look.Z },
		fov = camFov,
		uiInset = insetTop,
	}
else
	error("Unknown scene: " .. sceneName)
end

local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets
if scene_extra then
	scene.camera = scene_extra
end

fs.writeDir(root .. "/build/preview")
local outName = if sceneName == "cleaning" then "cleaning_" .. (process.args[3] or "chisel") .. (if process.args[4] == "phone" then "_phone" else "") else sceneName
fs.writeFile(root .. "/build/preview/" .. outName .. ".json", serde.encode("json", scene))
for name, guis in uiExports do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", guis))
	print("Exported UI " .. name)
end
print(string.format("Exported %s: %d parts, %d lights, %d emitters, %d texts", sceneName, #scene.parts, #scene.lights, #scene.emitters, #scene.texts))
