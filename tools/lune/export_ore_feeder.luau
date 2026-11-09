--[[
	Machine step 3a, the Ore Feeder (owner 2026-11-07): the game's own models on a
	plain floor, a feeder at the head of a line (feeder -> belts -> Cleaning Plant
	-> belts -> Crusher -> belts -> Furnace), its counter showing what it holds,
	and the upgrade window at the feeder (its Capacity row). Built with the game's
	code (MachineBuilder, KitMachines, UI/MachineUpgradeView, FeederController's
	text); the counter's text is drawn on its screen part as the client does.

	  lune run tools/lune/export_ore_feeder.luau
	  SHOTS_EXTRA=build/preview/ore_feeder_shots.json node tools/preview/render.mjs ore_feeder feeder_line feeder_close feeder_window
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
local Enum = roblox.Enum

local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineUpgradeView")
local FeederController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.FeederController")

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local cell = GameConfig.CellSize
local face = CF.Angles(0, -math.pi / 2, 0) -- the machines' front (-Z) toward +X: the line runs along +X

local stage = Instance.new("Model")
stage.Name = "OreFeederLine"
stage.Parent = workspace
Geo.block(stage, CF.new(36, -0.5, 0), V3.new(130, 1, 50), C3.fromRGB(188, 192, 204))
for i = -6, 24 do
	Geo.block(stage, CF.new(i * cell, 0.01, 0), V3.new(0.08, 0.02, 50), C3.fromRGB(150, 154, 170))
end

local function place(id: string, gx: number, gz: number, w: number, tier: number?): any
	local model = MachineBuilder.build(id, nil, tier)
	model:PivotTo(CF.new((gx + w / 2) * cell, 0, (gz + w / 2) * cell) * face)
	model.Parent = stage
	return model
end

-- the feeder (its outlet over the cell in front: gz 0), then the line
local feeder = place("OreFeeder", -2, -1, 2)
for _, d in feeder:GetDescendants() do
	if d:IsA("BasePart") and d:HasTag("FeederScreen") then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Text = FeederController.text(142, 200)
		label.TextColor3 = C3.fromRGB(70, 220, 255)
		label.FontFace = Theme.TitleFont
		label.Parent = gui
		gui.Parent = d
	end
end
local x = 0
local function belts(n: number)
	for _ = 1, n do
		place("Conveyor", x, 0, 1)
		x += 1
	end
end
belts(3)
place("AutoCleaner", x, -1, 2)
x += 2
belts(2)
place("Crusher", x, -1, 2)
x += 2
belts(2)
place("ClayFurnace", x, -1, 2, 1)
x += 2
belts(2)
-- a few ores riding the first belts
local ores = { "Gold", "Sapphire", "Silver" }
for k, ore in ores do
	local item = ItemBuilder.build({ Kind = "Raw", OreId = ore }, CF.new((k - 0.5) * cell * 0.9, 1.4, 0.5 * cell) * CF.Angles(0, k, 0), k)
	item.Parent = stage
end

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
fs.writeFile(root .. "/build/preview/ore_feeder.json", serde.encode("json", scene))

-- the window at the feeder (Capacity 0, coins for the first level)
local hud = HudView.build()
hud.Gui.Scale.Scale = 1.25
hud.Coins.Text = Format.money(640000000)
hud.Income.Text = Format.perSecond(184000)
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()
HudView.placeBackpack(hud, 1.25)
HudView.setBackpack(hud, 0, 30)
local refs = View.build()
refs.Gui.Scale.Scale = 1.25
refs.Gui.Enabled = true
View.fill(refs, View.titleOf("OreFeeder"), View.rows("OreFeeder", { MachineUpgrades = {}, Upgrades = {} }, 640000000), View.noteOf("OreFeeder"))
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
fs.writeFile(root .. "/build/preview/ui_feeder_window.json", serde.encode("json", UiExport.export({ hud.Gui, refs.Gui })))

local function shot(p: any, t: any, fov: number, ui: string?): any
	return {
		scene = "ore_feeder",
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
	root .. "/build/preview/ore_feeder_shots.json",
	serde.encode("json", {
		feeder_line = shot({ 24, 30, 40 }, { 24, 2, 0 }, 58),
		feeder_close = shot({ 4, 14, 18 }, { -4, 4, 0 }, 55),
		feeder_window = shot({ 24, 30, 40 }, { 24, 2, 0 }, 58, "ui_feeder_window"),
	})
)
print(`ore feeder: {#scene.parts} parts`)
