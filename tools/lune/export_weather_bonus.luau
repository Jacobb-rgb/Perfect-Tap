--[[
	What a weather's bonus looks like on the player's screen (owner 2026-11-07)
	for the owner, rendered without Studio: the running chip and the toast from
	the game's own code (UI/BoostView, UI/HudView, Weather/WeatherBonus), over the
	town. Icons not uploaded yet stay away, as in the game.

	  lune run tools/lune/export_scene.luau world     (once)
	  lune run tools/lune/export_weather_bonus.luau
	  SHOTS_EXTRA=build/preview/weather_bonus_shots.json node tools/preview/render.mjs world bonus_storm bonus_rain bonus_snow bonus_rainbow bonus_phone
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local WeatherBonus = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherBonus")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")

local function screen(kind: string, scale: number): any
	local entry = WeatherBonus.List[kind]
	local hud = HudView.build()
	hud.Gui.Scale.Scale = scale
	hud.Coins.Text = Format.money(4820000)
	hud.Income.Text = Format.perSecond(1840)
	hud.Zone.Text = ""
	hud.Toasts:ClearAllChildren()
	HudView.placeBackpack(hud, scale)
	HudView.setBackpack(hud, 12, 30)
	HudView.toast(hud.Toasts, entry.Text, entry.Color)
	BoostView.weather = function()
		return entry
	end
	BoostView.weatherLeft = function()
		return 151
	end
	local chips = BoostView.buildChips()
	chips.Gui.Scale.Scale = scale
	chips.Gui.Enabled = true
	BoostView.placeCorner(chips, 16, 16, false)
	BoostView.setChips(chips, BoostView.chips({ Boosts = {} }, 1000), false)
	return UiExport.export({ hud.Gui, chips.Gui })
end

local files = {
	ui_bonus_storm = screen("Storm", 1.25),
	ui_bonus_rain = screen("Rain", 1.25),
	ui_bonus_snow = screen("Snow", 1.25),
	ui_bonus_rainbow = screen("Rainbow", 1.25),
	ui_bonus_phone = screen("Storm", 0.62),
}
for name, json in files do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", json))
end

local function shot(ui: string, width: number?, height: number?): any
	return {
		scene = "world",
		position = { 2, 10, 66 },
		target = { 8, 10, 8 },
		fov = 70,
		ui = ui,
		width = width,
		height = height,
		uiInset = if width then 36 else nil,
	}
end
fs.writeFile(
	root .. "/build/preview/weather_bonus_shots.json",
	serde.encode("json", {
		bonus_storm = shot("ui_bonus_storm"),
		bonus_rain = shot("ui_bonus_rain"),
		bonus_snow = shot("ui_bonus_snow"),
		bonus_rainbow = shot("ui_bonus_rainbow"),
		bonus_phone = shot("ui_bonus_phone", 844, 390),
	})
)
print("weather bonus: 5 screens")
