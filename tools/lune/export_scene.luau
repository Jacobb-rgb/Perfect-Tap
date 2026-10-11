--[[
	Builds a preview scene with the real game builders and writes it as JSON
	for tools/preview/render.mjs.

	  lune run tools/lune/export_scene.luau [scene]
	Scenes: world (default)
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

if sceneName == "world" then
	WorldBuilder.build(workspace)
	addNodes(workspace)
elseif sceneName == "gameplay" then
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local Dummy = require("./lib/dummy")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local PickaxeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.PickaxeBuilder")
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
	Dummy.build(props, CF, root, "swing", nil, PickaxeBuilder.build("CopperPick"))
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
else
	error("Unknown scene: " .. sceneName)
end

local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/" .. sceneName .. ".json", serde.encode("json", scene))
for name, guis in uiExports do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", guis))
	print("Exported UI " .. name)
end
print(string.format("Exported %s: %d parts, %d lights, %d emitters, %d texts", sceneName, #scene.parts, #scene.lights, #scene.emitters, #scene.texts))
