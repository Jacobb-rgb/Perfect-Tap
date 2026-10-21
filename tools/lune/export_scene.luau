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
-- previews draw every icon (IconAssets.shows: the uploaded look)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local sceneName = process.args[1] or "world"

-- LIGHT_UI=1: every UI overlay with the light UI switched on (UIConfig.LightUI),
-- written as "<name>_light"; skinned old windows are re-skinned right before export.
local lightUI = process.env.LIGHT_UI == "1"
if lightUI then
	Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig").LightUI = true
	local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
	UiExport.before = function(gui)
		if gui:GetAttribute("LightSkin") then
			LightSkin.refresh(gui)
		end
		if gui:GetAttribute("HiddenByLight") then
			gui.Enabled = false -- (a preview that shows the old side menu column)
		end
	end
end

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
local scene_surface: any = nil -- a scene's own "Surface" preset (its sky and light), replacing LightingConfig's in its JSON

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
elseif sceneName == "hall" then -- the world + stand-in champions on the giant HALL OF FAME (tools/lune/lib/hall_preview.luau)
	local map = WorldBuilder.build(workspace)
	addMuseums(map)
	require("./lib/hall_preview").build(Loader, map)
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
elseif sceneName == "platforms_game" or sceneName == "platforms_build" then -- platforms in the game: lift, deck, slide (tools/lune/lib/platforms_scene.luau)
	require("./lib/platforms_scene").build(Loader, workspace, sceneName == "platforms_build")
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
elseif sceneName == "elevator_ui" then -- the elevator's floor list (7 cards) and the ride to floor 5 over the Stormglass Rift (tools/lune/lib/elevator_preview.luau)
	for name, guis in require("./lib/elevator_preview").build(Loader, workspace) do
		uiExports[name] = guis
	end
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
elseif sceneName == "rebirth" then -- the world + the STAR FORGE window overlays (tools/lune/lib/rebirth_preview.luau)
	WorldBuilder.build(workspace)
	require("./lib/rebirth_preview").buildWorld(Loader, workspace)
	for name, guis in require("./lib/rebirth_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "store" then -- the world + the Robux STORE window overlays (tools/lune/lib/store_preview.luau)
	WorldBuilder.build(workspace)
	for name, guis in require("./lib/store_preview").build(Loader) do
		uiExports[name] = guis
	end
elseif sceneName == "star_blasters" then -- the five STAR blasters on a starry stage (tools/lune/lib/star_blasters_preview.luau)
	require("./lib/star_blasters_preview").build(Loader, workspace)
elseif sceneName == "star_blasters_held" then -- LV 10 and the five STAR blasters in a dummy's hand (same file)
	require("./lib/star_blasters_preview").buildHeld(Loader, workspace)
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
elseif
	sceneName == "machine_ux_build"
	or sceneName == "machine_ux_power"
	or sceneName == "machine_ux_yard"
	or sceneName == "machine_ux_close"
then
	-- the machine UX: build mode's info card, tray, keys and power preview; the status signs (tools/lune/lib/machine_ux_preview.luau)
	WorldBuilder.build(workspace)
	local camera, guis = require("./lib/machine_ux_preview").build(Loader, workspace, string.sub(sceneName, 12))
	scene_extra = camera
	for name, g in guis do
		uiExports[name] = g
	end
elseif sceneName == "forge_bridge" then -- proposals: THE GREAT FORGE replaced by the bridge garden (tools/lune/lib/forge_bridge_preview.luau; arg 2 = A / B / C)
	require("./lib/forge_bridge_preview").build(Loader, workspace, process.args[2] or "A")
elseif sceneName == "nature_kit" then -- the Wilds pieces and secrets in rows (tools/lune/lib/nature_wilds_preview.luau)
	require("./lib/nature_wilds_preview").kit(Loader, workspace)
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
	local stage = process.args[3] or "spray"
	if stage ~= "spray" and stage ~= "reveal" then
		error("cleaning stage must be spray or reveal, got " .. stage)
	end
	local fx = roblox.Instance.new("Folder")
	fx.Parent = workspace
	local workLight = OreShellBuilder.workLight(workCf, fx)
	local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")
	local SprayParts = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.SprayParts")
	local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local ore = OreData.get(oreId)
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
	if stage == "spray" then
		-- a good player part of the way through (the same tracker the game uses)
		local Players = require("./lib/spray_players")(Loader)
		local _, full = Players.sweep(pattern, { Speed = 1.6 })
		local stopAt = full.firstT + (full.doneT - full.firstT) * 0.55
		local tracker = Scoring.SprayTracker.new(pattern, if phone then "Touch" else "Mouse")
		local sub = Players.sweep(pattern, { Speed = 1.6, Input = if phone then "Touch" else "Mouse" })
		local nozzle = nil
		for _, stroke in sub.Strokes do
			for i = 1, #stroke, 3 do
				if stroke[i + 2] <= stopAt then
					tracker:add(stroke[i], stroke[i + 1], stroke[i + 2])
					nozzle = roblox.Vector2.new(stroke[i], stroke[i + 1])
				end
			end
			tracker:lift()
		end
		for index, block in shell.Dirt do
			local left = tracker:left(index)
			if tracker.cleaned[index] then
				block:Destroy()
			elseif left < 1 then
				SprayParts.thin(block, left)
			end
		end
		-- the wand and its jet at the nozzle point
		local hit = workCf:PointToWorldSpace(
			roblox.Vector3.new(nozzle.X * OreShellBuilder.Scale, nozzle.Y * OreShellBuilder.Scale, OreShellBuilder.DirtFront)
		)
		local wand = SprayParts.wand(fx)
		local wandCf, tip = SprayParts.wandFrame(workCf, hit, true)
		SprayParts.placeWand(wand, wandCf)
		SprayParts.placeJet(SprayParts.jet(fx), tip, hit)
		-- a few droplets around the hit (the splash emitter, frozen)
		local rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng").new(5)
		for _ = 1, 9 do
			local offset = workCf:VectorToWorldSpace(roblox.Vector3.new(rng:range(-0.5, 0.5), rng:range(-0.4, 0.5), rng:range(0.1, 0.6)))
			Geo.ball(
				fx,
				hit + offset,
				rng:range(0.05, 0.1),
				SprayParts.JetColor,
				roblox.Enum.Material.Neon,
				{ CanCollide = false, Transparency = 0.3 }
			)
		end
		view.Instruction.Text = if #pattern.Crystals > 0
			then "Wash the dirt off. Don't blast the glowing crystals!"
			else "Wash all the dirt off the ore!"
		CleaningView.setClean(view, tracker:progress())
		CleaningView.setMeter(view, tracker:parts(stopAt).Score)
		-- the game's look (Cleaning/CardLook): the green bar and dirt chunks in flight
		local CardLook = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CardLook")
		CardLook.styleBar(view)
		do
			local seed = 7
			local function r(): number
				seed = (seed * 16807) % 2147483647
				return seed / 2147483647
			end
			local dirt = roblox.Color3.fromRGB(120, 86, 56)
			for c = 1, 7 do
				local from = hit + workCf:VectorToWorldSpace(roblox.Vector3.new((r() - 0.5) * 0.8, (r() - 0.5) * 0.8, 0.05))
				local velocity = CardLook.throw(workCf, r)
				for k = 1, 2 do
					local t = 0.05 + (c % 3) * 0.06 + k * 0.05
					local s = 0.12 + r() * 0.16
					Geo.block(
						fx,
						CF.new(CardLook.chunkAt(from, velocity, t)) * CF.Angles(r() * 3, r() * 3, r() * 3),
						roblox.Vector3.new(s, s * 0.8, s),
						dirt,
						nil,
						{ CanCollide = false }
					)
				end
			end
		end
		view.Hint.Text = if phone then "Hold your finger on the dirt and drag" else "Hold the left mouse button to spray"
	elseif stage == "reveal" then
		local lamp: any = workLight:FindFirstChildOfClass("PointLight")
		lamp.Brightness = 0.4
		for _, block in shell.Dirt do
			block:Destroy()
		end
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
		view.CardDetail.Text = "Time 9.4s  ·  Aim 97%"
		view.Card.Visible = true
		view.CleanBar.Visible = false -- like DefaultLook: the card sits where the bar was
		-- the game's look (Cleaning/CardLook): the card glows in the rarity colour, the NEW ORE banner
		local CardLook = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CardLook")
		CardLook.glowCard(view, rarity.Color)
		CardLook.banner(view, "NEW ORE DISCOVERED!", roblox.Color3.fromRGB(255, 196, 46))
		-- the ore lifted out and glowing, rays around it
		local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.RevealFx")
		local lift = workCf:VectorToWorldSpace(RevealFx.Rise)
		for _, part in shell.Core do
			part.CFrame = part.CFrame + lift
		end
		-- the crystals sparkled off with the dirt (DefaultLook.finished)
		for _, part in shell.Fragile do
			part:Destroy()
		end
		for _, d in shell.Model:GetChildren() do
			if d:IsA("BasePart") and d.Name == "CrystalBase" then
				d:Destroy()
			end
		end
		local center = shell.TreasurePivot.Position
		local rayCount = if rarity.Order >= 6 then 12 else 8
		for i = 1, rayCount do
			local a = i / rayCount * math.pi * 2 + 0.8
			local dir = workCf:VectorToWorldSpace(roblox.Vector3.new(math.cos(a), math.sin(a), RevealFx.RayTilt))
			Geo.block(
				fx,
				CF.lookAt(center + dir * 3.2, center + dir * 4),
				roblox.Vector3.new(0.12, 0.12, 6),
				rarity.Color,
				roblox.Enum.Material.Neon,
				{ CanCollide = false, Transparency = 0.75 }
			)
		end
		-- the glow light stays at the vise (behind the lifted ore), like the look's holder
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
		light.Brightness = 1.2
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
elseif string.match(sceneName, "^eggstall_") then -- the egg stall concepts (tools/lune/lib/egg_stall_preview.luau)
	local EggStall = require("./lib/egg_stall_preview")
	EggStall.build(Loader, workspace, string.sub(sceneName, #"eggstall_" + 1))
	for name, guis in EggStall.ui(Loader) do
		uiExports[name] = guis
	end
elseif string.match(sceneName, "^limitedbg_") then -- a limited edition's shop banner background (limited_golems_preview)
	local LimitedPreview = require("./lib/limited_golems_preview")
	scene_surface, scene_extra = LimitedPreview.build(Loader, workspace, string.sub(sceneName, #"limitedbg_" + 1), true)
elseif string.match(sceneName, "^limitedshard_") then -- a limited edition's SHARD showcase (limited_golems_preview)
	local LimitedPreview = require("./lib/limited_golems_preview")
	scene_surface, scene_extra = LimitedPreview.buildShard(Loader, workspace, string.sub(sceneName, #"limitedshard_" + 1))
elseif string.match(sceneName, "^limited_") then -- the LIMITED EDITION golem proposals (tools/lune/lib/limited_golems_preview.luau)
	local themeId = string.sub(sceneName, #"limited_" + 1)
	local LimitedPreview = require("./lib/limited_golems_preview")
	scene_surface, scene_extra = LimitedPreview.build(Loader, workspace, themeId)
	uiExports["ui_" .. sceneName] = LimitedPreview.ui(Loader, themeId)
	fs.writeDir(root .. "/build/preview")
	fs.writeFile(root .. "/build/preview/" .. sceneName .. "_info.json", serde.encode("json", LimitedPreview.info(Loader, themeId)))
else
	error("Unknown scene: " .. sceneName)
end

local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
if scene_surface then
	presets.Surface = presetToJson(scene_surface)
end
scene.presets = presets
if scene_extra then
	scene.camera = scene_extra
end

fs.writeDir(root .. "/build/preview")
local outName = if sceneName == "mine_floor"
	then "mine_floor_" .. (process.args[2] or "1")
	elseif sceneName == "cleaning" then "cleaning_" .. (process.args[3] or "spray") .. (if process.args[4] == "phone"
		then "_phone"
		else "")
	else sceneName
fs.writeFile(root .. "/build/preview/" .. outName .. ".json", serde.encode("json", scene))
for name, guis in uiExports do
	local out = if lightUI and not name:match("_light$") then name .. "_light" else name
	fs.writeFile(root .. "/build/preview/" .. out .. ".json", serde.encode("json", guis))
	print("Exported UI " .. out)
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
