--[[
	Preview scenes of the rock labels and the rock breaking animation
	(tools/lune/lib/rock_fx_preview.luau). Writes the scenes, their UI overlays
	and the shots (cameras computed here, so the label projection and the
	render match) to build/preview/.

	  lune run tools/lune/export_rock_fx.luau
	  SHOTS_EXTRA=build/preview/rock_fx_shots.json node tools/preview/render.mjs rock_labels
	  SHOTS_EXTRA=build/preview/rock_fx_shots.json node tools/preview/render.mjs rock_labels_locked
	  SHOTS_EXTRA=build/preview/rock_fx_shots.json node tools/preview/render.mjs rock_shatter
	  python3 tools/preview/rock_fx_sheet.py     # the storyboard sheet -> build/preview/shots/rock_shatter_sheet.jpg

	Scenes: rock_labels (floor 1, blaster 2, HP labels), rock_labels_locked
	(floor 2 with a level 1 blaster: "Lv 3" labels and the "Needs Lv 3" note),
	rock_shatter (the breaking storyboard). Each label scene has a desktop and
	a phone-sized shot.
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
local Preview = require("./lib/rock_fx_preview")

local V3 = roblox.Vector3

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

fs.writeDir(root .. "/build/preview")
local allShots = {}

local function write(name: string, build: (workspace: any) -> (any, any))
	local game = roblox.Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local shots, uis = build(workspace)
	local scene = Export.collect(workspace)
	scene.presets = presets
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", scene))
	for uiName, guis in uis do
		fs.writeFile(root .. "/build/preview/" .. uiName .. ".json", serde.encode("json", guis))
	end
	for shotName, shot in shots do
		allShots[shotName] = shot
	end
	print(string.format("Exported %s: %d parts, %d lights, %d texts", name, #scene.parts, #scene.lights, #scene.texts))
end

write("rock_labels", function(workspace)
	return Preview.labels(Loader, workspace, {
		name = "rock_labels",
		floor = 1,
		level = 2,
		ore = "Copper",
		player = V3.new(-4, 0, 27),
		aimAt = V3.new(-14, 0.6, 18),
	})
end)

write("rock_labels_locked", function(workspace)
	return Preview.labels(Loader, workspace, {
		name = "rock_labels_locked",
		floor = 2,
		level = 1,
		ore = "Copper",
		player = V3.new(4, 0, 34),
		aimAt = V3.new(12, 1.7, 11),
	})
end)

write("rock_shatter", function(workspace)
	return Preview.shatter(Loader, workspace, "rock_shatter")
end)

fs.writeFile(root .. "/build/preview/rock_fx_shots.json", serde.encode("json", allShots, true))
print("Shots -> build/preview/rock_fx_shots.json")
