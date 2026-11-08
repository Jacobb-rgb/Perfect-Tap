--[[
	Machine step 2 (owner 2026-11-07): steel + blue for the Solar Panel and the
	one belt only (his words: the other machines, fences, pen and podiums keep
	their colours), and the one belt's levels bought at a belt. Two rows of the
	game's own models on a plain floor: today in front, the new look behind
	(the Crusher and the Cleaning Plant between the belts keep their colours in
	both; an old Express belt keeps its cyan look), and the upgrade window at a
	belt. Built with the game's code (KitMachines, MachineBuilder,
	UI/MachineUpgradeView).

	  lune run tools/lune/export_steel_belt.luau
	  SHOTS_EXTRA=build/preview/steel_belt_shots.json node tools/preview/render.mjs steel_belt steel_rows steel_close steel_window
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

local CF = Loader.CFrame
local V3 = roblox.Vector3
local C3 = roblox.Color3
local Instance = roblox.Instance

local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineUpgradeView")

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local cell = GameConfig.CellSize
local face = CF.Angles(0, -math.pi / 2, 0) -- the machines' front (-Z) toward +X: the line runs along +X

local stage = Instance.new("Model")
stage.Name = "SteelBelt"
stage.Parent = workspace
Geo.block(stage, CF.new(30, -0.5, -10), V3.new(110, 1, 60), C3.fromRGB(188, 192, 204))
for i = -12, 14 do
	Geo.block(stage, CF.new(i * cell, 0.01, -10), V3.new(0.08, 0.02, 60), C3.fromRGB(150, 154, 170))
end

local function place(id: string, gx: number, gz: number, w: number)
	local model = MachineBuilder.build(id, nil, nil)
	model:PivotTo(CF.new((gx + w / 2) * cell, 0, (gz + w / 2) * cell) * face)
	model.Parent = stage
	return model
end

-- one row: a Solar Panel, belts through a Cleaning Plant and a Crusher, then an old Express belt
local function row(gz: number)
	place("SolarPanel", -3, gz - 1, 2)
	local x = 0
	for _ = 1, 3 do
		place("Conveyor", x, gz, 1)
		x += 1
	end
	place("AutoCleaner", x, gz - 1, 2)
	x += 2
	for _ = 1, 3 do
		place("Conveyor", x, gz, 1)
		x += 1
	end
	place("Crusher", x, gz - 1, 2)
	x += 2
	place("Conveyor", x, gz, 1)
	place("ExpressConveyor", x + 1, gz, 1)
	place("ExpressConveyor", x + 2, gz, 1)
end

-- today (front): the steel look off while it builds
local steel = KitMachines.SteelLook
KitMachines.SteelLook = {}
row(0)
KitMachines.SteelLook = steel
-- new (behind)
row(-6)

local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	local o = {}
	for group, values in preset do
		o[group] = {}
		for key, value in values do
			o[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
		end
	end
	presets[name] = o
end
scene.presets = presets
fs.writeFile(root .. "/build/preview/steel_belt.json", serde.encode("json", scene))

-- the window at a belt (belt level 0, coins for the first level)
local hud = HudView.build()
hud.Gui.Scale.Scale = 1.25
hud.Coins.Text = Format.money(180000)
hud.Income.Text = Format.perSecond(1840)
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()
HudView.placeBackpack(hud, 1.25)
HudView.setBackpack(hud, 0, 30)
local refs = View.build()
refs.Gui.Scale.Scale = 1.25
refs.Gui.Enabled = true
View.fill(refs, View.titleOf("Conveyor"), View.rows("Conveyor", { MachineUpgrades = {}, Upgrades = {} }, 180000), View.noteOf("Conveyor"))
for _, gui in { hud.Gui, refs.Gui } do
	for _, d in gui:GetDescendants() do
		if d:IsA("ViewportFrame") then
			d:SetAttribute("PreviewLive", true)
		end
		local icon = d:GetAttribute("Icon")
		if type(icon) == "string" and not fs.isFile(`{root}/build/preview/icons/{icon}.png`) then
			d:SetAttribute("Icon", nil)
		end
	end
end
fs.writeFile(root .. "/build/preview/ui_steel_window.json", serde.encode("json", UiExport.export({ hud.Gui, refs.Gui })))

local function shot(p: any, t: any, fov: number, ui: string?): any
	return {
		scene = "steel_belt",
		preset = "Surface",
		sunDir = { 0.55, 0.5, 0.65 },
		sunColor = { 1.0, 0.72, 0.55 },
		position = p,
		target = t,
		fov = fov,
		ui = ui,
	}
end
fs.writeFile(
	root .. "/build/preview/steel_belt_shots.json",
	serde.encode("json", {
		steel_rows = shot({ 18, 34, 34 }, { 18, 0, -10 }, 58),
		steel_close = shot({ 0, 13, -6 }, { 0, 2, -24 }, 62),
		steel_window = shot({ 18, 34, 34 }, { 18, 0, -10 }, 58, "ui_steel_window"),
	})
)
print(`steel belt: {#scene.parts} parts`)
