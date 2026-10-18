--[[
	Preview frames of the IN-GAME crate opening (Builders/CrateOpeningStage,
	the code VaultController plays): the stage posed at chosen times, each as
	its own scene, with the cinematic's own camera.

	  lune run tools/lune/export_crate_opening.luau [level] [t1,t2,...]   (default: 10, a set of key moments)
	-> build/preview/crate_open_<level>_<i>.json + build/preview/crate_open_shots.json
	  SHOTS_EXTRA=build/preview/crate_open_shots.json node tools/preview/render.mjs crate_open_10_1 crate_open_10_1
	(tools/preview/render_crate_opening.sh renders them all)
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

local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")
local CrateOpeningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CrateOpeningView")
local CF = Loader.CFrame

local level = tonumber(process.args[1]) or 10
local times = {}
for t in string.gmatch(process.args[2] or "0.25,1.9,2.75,3.0,3.5,6.5", "[^,]+") do
	table.insert(times, tonumber(t))
end

local function presetsJson()
	local out = {}
	for name, preset in LightingConfig.Presets do
		local p = {}
		for group, values in preset do
			p[group] = {}
			for key, value in values do
				p[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		out[name] = p
	end
	return out
end

local ORIGIN = CF.new(0, 3000, 0)
local ore = BlasterData.vaultOre(level)
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local stage = Stage.build(workspace, ORIGIN, level, ore, Stage.blasterModel(level, ore))
-- the overlay ("NEW BLASTER!", the flash, AWESOME!) at the render's 1.25 UI scale
local view = CrateOpeningView.build()
view.Gui.Scale.Scale = 1.25
CrateOpeningView.setBlaster(view, level, ore)

fs.writeDir(root .. "/build/preview")
local shotsPath = root .. "/build/preview/crate_open_shots.json"
local shots = if fs.isFile(shotsPath) then serde.decode("json", fs.readFile(shotsPath)) else {}
local presets = presetsJson()
for i, t in times do
	stage.update(t)
	local cam, fov = stage.camera(t)
	local scene = Export.collect(workspace)
	scene.presets = presets
	local name = string.format("crate_open_%d_%d", level, i)
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", scene))
	CrateOpeningView.update(view, t, stage.Burst, stage.Reveal)
	fs.writeFile(root .. "/build/preview/ui_" .. name .. ".json", serde.encode("json", UiExport.export({ view.Gui })))
	local p, look = cam.Position, cam.Position + cam.LookVector * 20
	shots[name] = {
		scene = name,
		position = { p.X, p.Y, p.Z },
		target = { look.X, look.Y, look.Z },
		fov = fov,
		preset = "CrateOpening",
		maxLights = 4,
		ui = "ui_" .. name,
	}
	print(string.format("Exported %s (t = %.2f): %d parts, %d lights", name, t, #scene.parts, #scene.lights))
end
fs.writeFile(shotsPath, serde.encode("json", shots, true))
