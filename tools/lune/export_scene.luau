--[[
	Builds a preview scene with the real game builders and writes it as JSON
	for tools/preview/render.mjs.

	  lune run tools/lune/export_scene.luau [scene]
	Scenes: world (default), style (the lobby Style kit gallery), lobby_blockout
	(world + a box per LobbyLayout set piece), gameplay, cleaning, ores (the ore
	gallery: clean, display, ingots, dirty ore, rocks per zone)
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

local function addNodes(parent, map)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Nodes"
	folder.Parent = parent
	-- the mine floors' rocks (RockBuilder) on their NodeSpawn markers
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local markers = map and map:FindFirstChild("NodeSpawns")
	if markers then
		for _, marker in markers:GetChildren() do
			local floorIndex = marker:GetAttribute("Floor")
			if type(floorIndex) == "number" then
				local index = marker:GetAttribute("SpawnIndex") or 0
				local rng = Rng.new(index * 131 + 7)
				local floor = MineFloors.get(floorIndex)
				local kind = marker:GetAttribute("Kind")
				if kind ~= "Giant" then
					local roll = rng:next()
					local deep = marker:GetAttribute("Deep") == true
					kind = if roll < (if deep then 0.25 else 0.1) then "Crystal" elseif roll < 0.42 then "Big" else "Small"
				end
				local weights = if kind == "Crystal" then floor.CrystalOres else floor.Ores
				local ores = {}
				for _ = 1, MineFloors.OreCount[kind] or 3 do
					table.insert(ores, rng:weighted(weights))
				end
				local ground = marker.CFrame.Position - roblox.Vector3.new(0, marker.Size.Y / 2, 0)
				RockBuilder.build(floorIndex, kind, ores, roblox.CFrame.new(ground), index).Parent = folder
			end
		end
	end
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

-- The artifact museum ArtifactService builds into every plot's yard at
-- server start (MuseumBuilder), empty (the relics show near the camera for
-- each owner's finds; yard_preview fills its plot's).
local function addMuseums(map: any)
	local MuseumBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MuseumBuilder")
	local plots = map and map:FindFirstChild("Plots")
	for _, plot in WorldLayout.Plots do
		local model = plots and plots:FindFirstChild("Plot_" .. plot.Id)
		local yard = model and model:FindFirstChild("Yard")
		if yard then
			local museum = MuseumBuilder.build(WorldLayout.plotCFrame(plot))
			museum:SetAttribute("PlotId", plot.Id)
			museum.Parent = yard
		end
	end
end

if sceneName == "world" or string.match(sceneName, "^world_") then
	-- "world_<name>": the same world into build/preview/world_<name>.json (parallel workers)
	local map = WorldBuilder.build(workspace)
	addMuseums(map)
	addNodes(workspace, map)
elseif sceneName == "style" then
	-- the lobby style kit (src/server/World/Lobby/Style.luau), one of each helper
	require("./lib/style_gallery").build(Loader, workspace)
elseif sceneName == "lobby_blockout" then
	-- the world plus a translucent box for every lobby set piece (LobbyLayout)
	WorldBuilder.build(workspace)
	require("./lib/lobby_blockout").build(Loader, workspace)
elseif sceneName == "machines" then
	require("./lib/machines_gallery").build(Loader, workspace) -- every machine on a plot pad (Kenney Factory Kit style)
elseif sceneName == "kit_showroom" then -- every roster machine in rows (tools/lune/lib/kit_showroom.luau)
	require("./lib/kit_showroom").build(Loader, workspace)
elseif sceneName == "kit_showroom_max" then -- the same at the max upgrade level (crystal)
	require("./lib/kit_showroom").build(Loader, workspace, 4)
elseif sceneName == "factory" then -- a working roster factory with power cables (tools/lune/lib/factory_preview.luau)
	require("./lib/factory_preview").build(Loader, workspace)
elseif sceneName == "factory_max" then -- the same at the max upgrade level (crystal)
	require("./lib/factory_preview").build(Loader, workspace, 4)
elseif sceneName == "ore_stages_1" or sceneName == "ore_stages_2" or sceneName == "ore_stages_3" then
	-- every ore through the loop's stages, one sheet per two rarities (tools/lune/lib/ore_stages.luau)
	require("./lib/ore_stages").build(Loader, workspace, tonumber(string.sub(sceneName, -1)) :: number)
elseif sceneName == "cleaning_reveal_strip" then -- the cleaning reveal, Common vs Mythic, 4 moments (tools/lune/lib/reveal_strip.luau)
	require("./lib/reveal_strip").build(Loader, workspace)
elseif sceneName == "ore_showcase" then -- every ore in one picture on a tiered shelf (tools/lune/lib/ore_showcase.luau)
	require("./lib/ore_showcase").build(Loader, workspace)
elseif sceneName == "cute_styles" then -- the machine style exploration A / B / C (tools/lune/lib/cute_styles_gallery.luau)
	require("./lib/cute_styles_gallery").build(Loader, workspace)
elseif sceneName == "kit_machines" then -- the Factory Kit machines + upgrade crystal levels (tools/lune/lib/kit_machines_gallery.luau)
	require("./lib/kit_machines_gallery").build(Loader, workspace)
elseif sceneName == "blasters" or sceneName == "blaster_fire" then
	-- laser blasters: the 10 levels in ore skins / a forgekeeper blasting a quarry rock
	require("./lib/blaster_gallery").build(Loader, workspace, sceneName)
elseif sceneName == "blaster_concepts" then -- blaster style proposals (tools/lune/lib/blaster_concepts.luau)
	require("./lib/blaster_concepts").build(Loader, workspace)
elseif sceneName == "kenney_check" then -- the Kenney Blaster Kit shapes rebuilt from parts (tools/lune/lib/blaster_kenney.luau)
	require("./lib/blaster_kenney").buildCheck(Loader, workspace)
elseif sceneName == "blaster_kenney" then -- the ten levels: Kenney shapes with the Ore Glow skins
	require("./lib/blaster_kenney").build(Loader, workspace)
elseif sceneName == "horizon_kenney" then -- Kenney kit models rebuilt from boxes for the horizon (tools/lune/lib/horizon_gallery.luau)
	require("./lib/horizon_gallery").build(Loader, workspace)
elseif sceneName == "kit_check" then -- Space Station / Mini Dungeon / City pieces rebuilt from parts (tools/lune/lib/kenney_kit.luau)
	require("./lib/kenney_kit").buildCheck(Loader, workspace)
elseif sceneName == "vault_game" then -- the in-game Vault lobby package at its place (tools/lune/lib/vault_game.luau)
	require("./lib/vault_game").build(Loader, workspace)
elseif sceneName == "blaster_shop_lobby" then -- TEST: the Forge Vault placed in the lobby (preview only)
	require("./lib/blaster_shop").buildLobby(Loader, workspace)
elseif sceneName == "blaster_shop" then -- the blaster shop proposals (tools/lune/lib/blaster_shop.luau)
	require("./lib/blaster_shop").build(Loader, workspace)
elseif sceneName == "crate_gallery" then -- the weapon cases in the ore skins (tools/lune/lib/blaster_kenney.luau)
	require("./lib/blaster_kenney").buildCrates(Loader, workspace)
elseif sceneName == "blaster_glow" then -- proposal D "Ore Glow" floating in the sky (tools/lune/lib/blaster_glow.luau)
	require("./lib/blaster_glow").build(Loader, workspace)
elseif sceneName == "blaster_glow_hold" then -- proposal D held on the plaza
	require("./lib/blaster_glow").buildHold(Loader, workspace)
elseif sceneName == "blaster_hold_tool" or sceneName == "blaster_hold_aim" then -- avatars holding the blaster proposals
	require("./lib/blaster_concepts").buildHold(Loader, workspace, if sceneName == "blaster_hold_aim" then "aim" else "tool")
elseif sceneName == "trains" then -- the ore train gallery (tools/lune/lib/train_gallery.luau)
	require("./lib/train_gallery").build(Loader, workspace)
elseif sceneName == "mine_rocks" then -- mine floor rocks, giant crystals, breaking storyboard (tools/lune/lib/mine_concepts.luau)
	require("./lib/mine_concepts").buildRocks(Loader, workspace)
elseif sceneName == "mine_showcase" then -- the ore-shelf showcase of the mine floor rocks
	require("./lib/mine_concepts").buildShowcase(Loader, workspace)
elseif sceneName == "mine_floor" then -- one mine floor area with rocks (tools/lune/lib/mine_floor_scene.luau)
	require("./lib/mine_floor_scene").build(Loader, workspace, tonumber(process.args[2]) or 1)
elseif sceneName == "hoverboards" then -- the hoverboard showroom, Robux close-ups, lineup (tools/lune/lib/hoverboard_preview.luau)
	require("./lib/hoverboard_preview").build(Loader, workspace)
elseif sceneName == "hoverboard_ride" or sceneName == "hoverboard_hero" then -- riders on hoverboards in the Greystone Quarry floor (+ the hoverboards UI)
	local HoverboardPreview = require("./lib/hoverboard_preview")
	HoverboardPreview.buildRide(Loader, workspace, sceneName == "hoverboard_hero")
	if sceneName == "hoverboard_ride" then
		for name, guis in HoverboardPreview.buildUi(Loader) do
			uiExports[name] = guis
		end
	end
elseif sceneName == "railway" then -- the world with parked preview trains on the railway (tools/lune/lib/railway_gallery.luau)
	require("./lib/railway_gallery").build(Loader, workspace)
	addNodes(workspace)
elseif sceneName == "train_trip" then -- trains on their trips + the train HUD and panel (tools/lune/lib/train_trip_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/train_trip_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
elseif sceneName == "belts" then -- step 3 belts, chutes, sorting board, pen send toolbar (tools/lune/lib/belts_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/belts_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
elseif sceneName == "ironbox" then -- the Iron Box sorting line + keep list overlays (tools/lune/lib/ironbox_preview.luau)
	for name, guis in require("./lib/ironbox_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
elseif sceneName == "foundry" or sceneName == "foundry_moment" then -- the Foundry buildings and the chute line (+ the hammer moment and the reveal) and their UI (tools/lune/lib/foundry_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/foundry_preview").build(Loader, workspace, sceneName == "foundry_moment") do
		uiExports[name] = guis
	end
elseif sceneName == "relic_flow" then -- dusty relic -> hand / Restoration Table cleaning -> museum (tools/lune/lib/relic_flow_preview.luau)
	require("./lib/relic_flow_preview").build(Loader, workspace)
elseif sceneName == "wheel_artifacts" then -- the museum, the relic gallery and the wheel / book / journal overlays (tools/lune/lib/wheel_artifacts_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/wheel_artifacts_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
elseif sceneName == "menus" then -- the world + the side menu, codex, settings and leaderboard overlays (tools/lune/lib/menus_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/menus_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "tech_shop" then -- the world + the Tech shop panel overlays (tools/lune/lib/tech_shop_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/tech_shop_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "vault_shop" then -- the world + the Blaster Vault shop window overlays (tools/lune/lib/vault_shop_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/vault_shop_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "gear_shop" then -- the world + miners with head lamps + the Gear shop panel overlays (tools/lune/lib/gear_shop_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/gear_shop_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
elseif sceneName == "enchants" then -- the world + the Enchant shop / luck boosts overlays (tools/lune/lib/enchant_boost_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/enchant_boost_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "golems" or sceneName == "capsules" or sceneName == "capsule_reveal" or sceneName == "capsule_crack" then
	-- step 7: golem pets, capsules and their UI (tools/lune/lib/capsule_preview.luau)
	for name, guis in require("./lib/capsule_preview").build(Loader, workspace, sceneName) do
		uiExports[name] = guis
	end
elseif sceneName == "tutorial" or sceneName == "tutorial_hopper" or sceneName == "tutorial_golems" then -- the tutorial's bubble + guide in the quarry (tools/lune/lib/tutorial_preview.luau)
	WorldBuilder.build(workspace)
	addNodes(workspace)
	local TutorialPreview = require("./lib/tutorial_preview")
	local variant = if sceneName == "tutorial_hopper" then "hopper" elseif sceneName == "tutorial_golems" then "golems" else "station"
	TutorialPreview.scene(Loader, workspace, variant)
	for name, guis in TutorialPreview.build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "loading" then -- the loading screen (tools/lune/lib/loading_preview.luau); the screen is opaque, no world
	for name, guis in require("./lib/loading_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "blaster_gallery" then -- the world + the blaster gallery in THE GREAT FORGE (tools/lune/lib/gallery_preview.luau)
	require("./lib/gallery_preview").build(Loader, workspace)
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
	local ores = { "Copper", "Silver", "Gold", "DragonEgg", "StormPearl", "Heartstone" }
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
		local cf = plotCf
			* CF.new(-half + (entry.X + w / 2) * GameConfig.CellSize, 0, -half + (entry.Z + d / 2) * GameConfig.CellSize)
			* CF.Angles(0, -entry.R * math.pi / 2, 0)
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
			local world = workCf:PointToWorldSpace(
				roblox.Vector3.new(p.X * OreShellBuilder.Scale, p.Y * OreShellBuilder.Scale, OreShellBuilder.DotZ + 0.03)
			)
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
		local tip =
			workCf:PointToWorldSpace(roblox.Vector3.new(u * OreShellBuilder.Scale, v * OreShellBuilder.Scale, OreShellBuilder.DotZ + 0.05))
		local axis = workCf:VectorToWorldSpace(roblox.Vector3.new(0.35, 0.5, 0.8)).Unit
		local right = axis:Cross(workCf.LookVector * -1).Unit
		local back = right:Cross(axis).Unit
		local cf = CF.fromMatrix(tip, right, axis, back)
		-- a working (pressed) chisel is see-through, like CleaningController.updateTool
		local props = { CanCollide = false, Transparency = if kind == "Chisel" then 0.55 else 0 }
		if kind == "Chisel" then
			Geo.wedge(
				fx,
				cf * CF.new(0, 0.12, 0) * CF.Angles(math.pi, 0, 0),
				roblox.Vector3.new(0.16, 0.24, 0.12),
				roblox.Color3.fromRGB(200, 205, 215),
				roblox.Enum.Material.Metal,
				props
			)
			Geo.block(
				fx,
				cf * CF.new(0, 0.5, 0),
				roblox.Vector3.new(0.16, 0.55, 0.12),
				roblox.Color3.fromRGB(170, 176, 188),
				roblox.Enum.Material.Metal,
				props
			)
			Geo.block(fx, cf * CF.new(0, 1.1, 0), roblox.Vector3.new(0.24, 0.7, 0.24), roblox.Color3.fromRGB(150, 98, 56), nil, props)
		elseif kind == "Brush" then
			for x = -1, 1 do
				Geo.block(
					fx,
					cf * CF.new(x * 0.11, 0.1, 0),
					roblox.Vector3.new(0.08, 0.22, 0.32),
					roblox.Color3.fromRGB(230, 205, 140),
					nil,
					props
				)
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
			Geo.block(
				fx,
				CF.lookAt(center + dir * 3.2, center + dir * 4),
				roblox.Vector3.new(0.12, 0.12, 6),
				rarity.Color,
				roblox.Enum.Material.Neon,
				{ CanCollide = false, Transparency = 0.7 }
			)
		end
		-- the glow light stays at the vise (behind the lifted core), like the controller's holder
		local holder = Geo.ball(
			fx,
			workCf:PointToWorldSpace(roblox.Vector3.new(0, 0, OreShellBuilder.CoreFront - 0.4)),
			0.1,
			ore.Glow,
			nil,
			{ CanCollide = false, Transparency = 1 }
		)
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
elseif sceneName == "ores" then
	-- Ore gallery (shots in tools/preview/ore_shots.json): every ore clean, on display and as an
	-- ingot, dirty ore chunks, and rocks with 1-3 ores in every zone.
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local gallery = roblox.Instance.new("Model")
	gallery.Name = "OreGallery"
	gallery.Parent = workspace
	Geo.block(gallery, CF.new(60, -0.5, 0), V3.new(420, 1, 260), C3.fromRGB(70, 74, 88))

	local function label(cf, width, height, text, color)
		local board = Geo.block(gallery, cf, V3.new(width, height, 0.08), C3.fromRGB(44, 36, 46))
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = color
		textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		textLabel.Parent = gui
		return board
	end
	-- lays a built model on top of a surface at height `top`
	local function settle(model, top)
		local lowest = math.huge
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
				local h = d.Size / 2
				lowest = math.min(lowest, d.CFrame.Position.Y - (math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z))
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + V3.new(0, top - lowest, 0)
			end
		end
	end

	local byRarity = {}
	for _, ore in OreData.List do
		local order = Rarity.get(ore.Rarity).Order
		byRarity[order] = byRarity[order] or {}
		table.insert(byRarity[order], ore)
	end
	local COL, YAW = 3.8, 0.45
	-- a 3-row grid of rarities (first..first+2) centered at x; cell(ore, x, top, z) builds one cell.
	-- Low plinths get a tilted name plate in front, tall pedestals a plaque on their front face.
	local function grid(x0, z0, first, plinthHeight, cell)
		local row = if plinthHeight > 0.5 then 6.4 else 4.6
		for r = first, first + 2 do
			local ores = byRarity[r]
			local rarity = Rarity.get(ores[1].Rarity)
			local z = z0 - (r - first) * row
			for i, ore in ores do
				local x = x0 + (i - (#ores + 1) / 2) * COL
				local shade = if (i + r) % 2 == 0 then C3.fromRGB(150, 146, 152) else C3.fromRGB(136, 132, 140)
				Geo.block(gallery, CF.new(x, plinthHeight / 2, z), V3.new(2.9, plinthHeight, 2.9), shade)
				cell(ore, x, plinthHeight, z)
				if plinthHeight > 0.5 then
					label(CF.new(x, plinthHeight * 0.5, z + 1.5), 2.7, 0.55, ore.Name, rarity.Color)
				else
					label(CF.new(x, 0.3, z + 1.62) * CF.Angles(-1.05, 0, 0), 2.9, 0.5, ore.Name, rarity.Color)
				end
			end
			label(CF.new(x0 - 3 * COL - 1.6, 0.3, z + 0.6) * CF.Angles(-1.05, 0, 0), 3.0, 0.62, string.upper(rarity.Name), rarity.Color)
		end
	end
	-- the preview draws every particle emitter as a fixed cloud: keep those on the display grid only
	local function noEmitters(model)
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
	end
	local function cleanCell(ore, x, top, z)
		local item = ItemBuilder.build({ Kind = "Clean", OreId = ore.Id }, CF.new(x, 0, z) * CF.Angles(0, YAW, 0), ore.Id)
		settle(item, top)
		noEmitters(item)
		item.Parent = gallery
	end
	local function displayCell(ore, x, top, z)
		local item = ItemBuilder.display({ K = "Clean", O = ore.Id }, CF.new(x, top, z) * CF.Angles(0, YAW, 0), ore.Id)
		item.Parent = gallery
	end
	local function ingotCell(ore, x, top, z)
		local ingot = ItemBuilder.build({ Kind = "Ingot", OreId = ore.Id }, CF.new(x - 0.2, 0, z + 0.5) * CF.Angles(0, 0.25, 0), 1)
		settle(ingot, top)
		ingot.Parent = gallery
		local pile = ItemBuilder.build({ Kind = "Crushed", OreId = ore.Id }, CF.new(x + 0.45, 0, z - 0.65), 2)
		settle(pile, top)
		pile.Parent = gallery
	end
	grid(0, 0, 1, 0.4, cleanCell) -- Clean: Common, Uncommon, Rare in front,
	grid(0, -14, 4, 0.4, cleanCell) -- Epic, Legendary, Mythic behind them
	grid(70, 0, 1, 1.1, displayCell) -- podium look
	grid(100, 0, 4, 1.1, displayCell)
	grid(-40, 0, 1, 0.4, ingotCell) -- ingots + crushed
	grid(-70, 0, 4, 0.4, ingotCell)

	-- dirty ore: the same chunk for every ore (same seed), only the glint differs
	for i, oreId in { "Coal", "Copper", "Silver", "Gold", "Bronze", "Diamond", "Sunstone", "Heartstone" } do
		local x = -125 + (i - 4.5) * 3.2
		Geo.block(gallery, CF.new(x, 0.2, 0), V3.new(2.6, 0.4, 2.6), C3.fromRGB(134, 128, 132))
		local chunk = ItemBuilder.build({ Kind = "Raw", OreId = oreId }, CF.new(x, 0, 0) * CF.Angles(0, YAW, 0), 7)
		settle(chunk, 0.4)
		chunk.Parent = gallery
		label(CF.new(x, 0.3, 1.45) * CF.Angles(-1.05, 0, 0), 2.6, 0.45, "(" .. OreData.get(oreId).Name .. ")", C3.fromRGB(200, 190, 180))
		local shown = ItemBuilder.display({ K = "Raw", O = oreId }, CF.new(x, 0.4, -4) * CF.Angles(0, YAW, 0), 7)
		Geo.block(gallery, CF.new(x, 0.2, -4), V3.new(2.6, 0.4, 2.6), C3.fromRGB(122, 116, 120))
		shown.Parent = gallery
	end

	-- rocks: a row per zone with 1, 2 and 3 ores, then stage 1 and stage 2
	local zones = { "Outcrops", "Quarry", "EmberCaves", "DeepHollow", "Grotto" }
	for row, zoneId in zones do
		local zone = WorldLayout.ZoneById[zoneId]
		local ids = {}
		for oreId in zone.Ores do
			table.insert(ids, oreId)
		end
		table.sort(ids, function(a, b)
			return OreData.get(a).Income < OreData.get(b).Income
		end)
		local low, mid, high = ids[1], ids[math.ceil(#ids / 2)], ids[#ids]
		local sets = { { mid }, { low, high }, { low, mid, high }, { low, high }, { low, mid, high } }
		local z = -(row - 1) * 11
		for col, set in sets do
			local x = 200 + (col - 3) * 10
			local rock = OreNodeBuilder.buildRock(zoneId, set, CF.new(x, 0, z), row * 10 + col)
			rock.Parent = gallery
			if col >= 4 then
				OreNodeBuilder.applyStage(rock, 1, col)
			end
			if col == 5 then
				for _, piece in OreNodeBuilder.applyStage(rock, 2, col) do
					piece:Destroy()
				end
			end
			local text = if col <= 3
				then zoneId .. " · " .. #set .. (if #set == 1 then " ore" else " ores")
				else zoneId .. " · stage " .. (col - 3)
			label(CF.new(x, 0.4, z + 4.4) * CF.Angles(-1.05, 0, 0), 6.5, 0.8, text, C3.fromRGB(240, 226, 200))
		end
	end
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
local outName = if sceneName == "mine_floor"
	then "mine_floor_" .. (process.args[2] or "1")
	elseif sceneName == "cleaning"
	then "cleaning_" .. (process.args[3] or "chisel") .. (if process.args[4] == "phone" then "_phone" else "")
	else sceneName
fs.writeFile(root .. "/build/preview/" .. outName .. ".json", serde.encode("json", scene))
for name, guis in uiExports do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", guis))
	print("Exported UI " .. name)
end
print(
	string.format(
		"Exported %s: %d parts, %d lights, %d emitters, %d texts",
		sceneName,
		#scene.parts,
		#scene.lights,
		#scene.emitters,
		#scene.texts
	)
)

---------------------------------------------------------------- scene "yard" (WP-Base)
-- `lune run tools/lune/export_scene.luau world yard`: the world above plus ores on
-- plot 1's podiums and in its Ore Pen -> build/preview/yard.json, and the HUD /
-- Ore Pen / offline popup overlays (tools/lune/lib/yard_preview.luau,
-- shots in tools/preview/yard_shots.json).
if sceneName == "world" and process.args[2] == "yard" then
	local yardUi = require("./lib/yard_preview").build(Loader, workspace)
	local yardScene = Export.collect(workspace)
	yardScene.presets = scene.presets
	fs.writeFile(root .. "/build/preview/yard.json", serde.encode("json", yardScene))
	for name, guis in yardUi do
		fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", guis))
		print("Exported UI " .. name)
	end
	print(string.format("Exported yard: %d parts, %d lights", #yardScene.parts, #yardScene.lights))
end

---------------------------------------------------------------- scene "yard_ingame" (plot style A)
-- `lune run tools/lune/export_scene.luau world yard_ingame`: the yard scene above
-- with every plot's Foundry building and FOUNDRY chute receiver as FoundryService
-- builds them at server start (their SurfaceGui frames painted for the renderer,
-- plot 5's chimney smoking) -> build/preview/yard_ingame.json. Shots:
-- tools/preview/plot_style_a_shots.json (the in-game pictures of the plot pieces
-- in the machines' style A, docs/screenshots/plot_style_a/ingame_*.jpg).
if sceneName == "world" and process.args[2] == "yard_ingame" then
	local YardPreview = require("./lib/yard_preview")
	YardPreview.build(Loader, workspace)
	local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
	local Gallery = require("./lib/machines_gallery")
	local plots = workspace:FindFirstChild("Map"):FindFirstChild("Plots")
	for _, plot in WorldLayout.Plots do
		local model = plots:FindFirstChild("Plot_" .. plot.Id)
		local yard = model and model:FindFirstChild("Yard")
		local old = yard and yard:FindFirstChild("Foundry")
		if old then
			local plotCF = WorldLayout.plotCFrame(plot)
			old:Destroy()
			local building = FoundryBuilder.build(plotCF, 3)
			building.Parent = yard
			local receiver = FoundryBuilder.receiver(plotCF)
			receiver.Parent = model
			Gallery.paintGuis(Loader, workspace, building)
			Gallery.paintGuis(Loader, workspace, receiver)
			if plot.Id == YardPreview.Plot then
				local top = building:FindFirstChild("ChimneyTop", true)
				if top then
					Gallery.smoke(Loader, workspace, top, 0.8)
				end
			end
		end
	end
	local ingameScene = Export.collect(workspace)
	ingameScene.presets = scene.presets
	fs.writeFile(root .. "/build/preview/yard_ingame.json", serde.encode("json", ingameScene))
	print(string.format("Exported yard_ingame: %d parts, %d lights", #ingameScene.parts, #ingameScene.lights))
end

---------------------------------------------------------------- scene "penboard" (WP-CleanerBox)
-- `lune run tools/lune/export_scene.luau world penboard`: the world above plus the
-- Pen Automation sorting board at plot 5's Ore Pen gate -> build/preview/penboard.json
-- (tools/lune/lib/ironbox_preview.luau buildBoard, shots in tools/preview/ironbox_shots.json).
if sceneName == "world" and process.args[2] == "penboard" then
	require("./lib/ironbox_preview").buildBoard(Loader, workspace)
	local boardScene = Export.collect(workspace)
	boardScene.presets = scene.presets
	fs.writeFile(root .. "/build/preview/penboard.json", serde.encode("json", boardScene))
	print(string.format("Exported penboard: %d parts, %d lights", #boardScene.parts, #boardScene.lights))
end
