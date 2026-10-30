--[[
	Preview scene of the Dragon King's royal cape (Builders/RoyalCape) on
	stand-in R6 / R15 players (tools/lune/lib/cape_preview.luau).

	  lune run tools/lune/export_cape.luau
	  SHOTS_EXTRA=tools/preview/cape_shots.json node tools/preview/render.mjs cape
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local Preview = require("./lib/cape_preview")

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

local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
Preview.build(Loader, workspace)
local scene = Export.collect(workspace)
scene.presets = presets
fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/cape.json", serde.encode("json", scene))
print(string.format("Exported cape: %d parts, %d lights, %d emitters", #scene.parts, #scene.lights, #scene.emitters))
