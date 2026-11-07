--[[
	The Night Shift window (owner 2026-11-07, his picture
	obrazky/napady_obrazky_2026-10-30/05_nocni_smena.jpg, no golems) for the
	owner, rendered without Studio. tools/preview is a three.js approximation
	of Roblox: fonts and lighting are close, not exact. Built with the game's
	own code (UI/NightShiftView, UI/HudView) from made-up numbers.

	  lune run tools/lune/export_scene.luau world     (once: the town behind it)
	  lune run tools/lune/export_night_shift.luau
	  SHOTS_EXTRA=build/preview/night_shift_shots.json node tools/preview/render.mjs world night_full night_prize night_pass night_empty night_phone night_small
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local NightShiftView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftView")

local function row(kind: string, ore: string, grade: string?, count: number): any
	return { K = kind, O = ore, G = grade, N = count }
end

local MADE = {
	Total = 46,
	Bars = 46,
	List = {
		row("Ingot", "Sapphire", "Pristine", 4),
		row("Ingot", "Gold", "Clean", 9),
		row("Ingot", "Silver", "Clean", 12),
		row("Ingot", "Bronze", "Rough", 18),
		row("Ingot", "Cobalt", "Rough", 3),
	},
}

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

local FULL = { Amount = 1240000, Seconds = 7 * 3600 + 42 * 60, Hours = 8, Rate = 0.25, Made = MADE, Crate = true }
local PASS = { Amount = 3970000, Seconds = 11 * 3600 + 5 * 60, Hours = 12, Rate = 0.5, Made = MADE, Crate = true }
local EMPTY = { Amount = 18400, Seconds = 3 * 3600 + 12 * 60, Hours = 8, Rate = 0.25, Crate = false }

local files = {
	ui_night_full = screen(FULL, 1.25),
	ui_night_prize = screen(FULL, 1.25, { Ok = true, Prize = "Coins", Amount = 2190000 }),
	ui_night_pass = screen(PASS, 1.25, { Ok = true, Prize = "Ores", Ores = 3 }),
	ui_night_empty = screen(EMPTY, 1.25),
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
		night_phone = shot("ui_night_phone", 844, 390),
		night_small = shot("ui_night_small", 568, 320),
	})
)
print("night shift: 6 screens")
