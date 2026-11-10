--[[
	The Night Shift window (owner 2026-11-07, his picture
	obrazky/napady_obrazky_2026-10-30/05_nocni_smena.jpg, no golems) for the
	owner, rendered without Studio. tools/preview is a three.js approximation
	of Roblox: fonts and lighting are close, not exact. Built with the game's
	own code (UI/NightShiftView, UI/HudView) from made-up numbers. Icons that
	aren't uploaded yet stay away, as in the game (no IconAssets.Previewing).

	  lune run tools/lune/export_scene.luau world     (once: the town behind it)
	  lune run tools/lune/export_night_shift.luau
	  SHOTS_EXTRA=build/preview/night_shift_shots.json node tools/preview/render.mjs world night_full night_prize night_pass night_empty night_nofeeder night_phone night_small
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local NightShiftView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftView")

local function screen(payload: any, scale: number, prize: any?): any
	local hud = HudView.build()
	hud.Gui.Scale.Scale = scale
	hud.Coins.Text = Format.money(4820000)
	hud.Income.Text = Format.perSecond(1840)
	hud.Zone.Text = ""
	hud.Toasts:ClearAllChildren()
	HudView.placeBackpack(hud, scale)
	HudView.setBackpack(hud, 12, 30)
	local refs = NightShiftView.build()
	refs.Gui.Scale.Scale = scale
	refs.Gui.Enabled = true
	NightShiftView.fill(refs, payload)
	if prize then
		NightShiftView.setPrize(refs, prize)
	end
	-- the 3D pictures drawn live (the game's ViewportFrames); no stand-in icon for those or
	-- for a picture this preview has no rendered icon of
	for _, gui in { hud.Gui, refs.Gui } do
		for _, d in gui:GetDescendants() do
			if d:IsA("ViewportFrame") then
				d:SetAttribute("PreviewLive", true)
			end
			local icon = d:GetAttribute("Icon")
			if type(icon) == "string" and (gui == refs.Gui or not fs.isFile(`{root}/build/preview/icons/{icon}.png`)) then
				if d:FindFirstChildOfClass("ViewportFrame") or gui == hud.Gui then
					d:SetAttribute("Icon", nil)
				end
			end
		end
	end
	return UiExport.export({ hud.Gui, refs.Gui })
end

-- (machine step 4: what the machines made of the Ore Feeder's ore, or why nothing)
local MADE = {
	Fed = 412,
	Total = 824,
	Bars = 824,
	List = {
		{ K = "Ingot", O = "Iron", G = "Clean", N = 380 },
		{ K = "Ingot", O = "Copper", G = "Clean", N = 236 },
		{ K = "Ingot", O = "Cobalt", G = "Pristine", N = 128 },
		{ K = "Ingot", O = "Emberite", G = "Clean", N = 54 },
		{ K = "Ingot", O = "Amber", G = "Pristine", N = 26 },
	},
}
local MADE_PASS = {
	Fed = 1000,
	Total = 2000,
	Bars = 1640,
	List = {
		{ K = "Ingot", O = "Iron", G = "Clean", N = 900 },
		{ K = "Ingot", O = "Cobalt", G = "Pristine", N = 740 },
		{ K = "Crushed", O = "Frostbite", G = "Clean", N = 360 },
	},
}
local FULL = { Amount = 1240000, Seconds = 7 * 3600 + 42 * 60, Hours = 8, Rate = 0.25, Crate = true, Made = MADE }
local PASS = { Amount = 3970000, Seconds = 11 * 3600 + 5 * 60, Hours = 12, Rate = 0.5, Crate = true, Made = MADE_PASS }
local EMPTY = { Amount = 18400, Seconds = 3 * 3600 + 12 * 60, Hours = 8, Rate = 0.25, Crate = false, Why = "Empty" }
local NOFEEDER = { Amount = 640000, Seconds = 6 * 3600, Hours = 8, Rate = 0.25, Crate = true, Why = "NoFeeder" }

local files = {
	ui_night_full = screen(FULL, 1.25),
	ui_night_prize = screen(FULL, 1.25, { Ok = true, Prize = "Coins", Amount = 2190000 }),
	ui_night_pass = screen(PASS, 1.25, { Ok = true, Prize = "Ores", Ores = 3 }),
	ui_night_empty = screen(EMPTY, 1.25),
	ui_night_nofeeder = screen(NOFEEDER, 1.25),
	ui_night_phone = screen(FULL, 0.62),
	ui_night_small = screen(FULL, 0.62),
}
for name, json in files do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", json))
end

-- the town from the bridge at the spawn
local function shot(ui: string, width: number?, height: number?): any
	return {
		scene = "world",
		position = { 18, 14, 66 },
		target = { 0, 8, 0 },
		fov = 60,
		ui = ui,
		width = width,
		height = height,
		uiInset = if width then 36 else nil,
	}
end
fs.writeFile(
	root .. "/build/preview/night_shift_shots.json",
	serde.encode("json", {
		night_full = shot("ui_night_full"),
		night_prize = shot("ui_night_prize"),
		night_pass = shot("ui_night_pass"),
		night_empty = shot("ui_night_empty"),
		night_nofeeder = shot("ui_night_nofeeder"),
		night_phone = shot("ui_night_phone", 844, 390),
		night_small = shot("ui_night_small", 568, 320),
	})
)
print("night shift: 7 screens")
