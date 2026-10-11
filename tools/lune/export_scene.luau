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

if sceneName == "world" then
	WorldBuilder.build(workspace)
	addNodes(workspace)
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
print(string.format("Exported %s: %d parts, %d lights, %d emitters, %d texts", sceneName, #scene.parts, #scene.lights, #scene.emitters, #scene.texts))
