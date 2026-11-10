--[[
	A machine's upgrade window (owner 2026-11-07: press E at the machine, its
	upgrades with short stats; never in a shop any more), rendered without
	Studio. tools/preview is a three.js approximation of Roblox: fonts and
	lighting are close, not exact. Built with the game's own code
	(UI/MachineUpgradeView, UI/HudView) from made-up saves.

	  lune run tools/lune/export_scene.luau world     (once: the town behind it)
	  lune run tools/lune/export_machine_upgrades.luau
	  SHOTS_EXTRA=build/preview/machine_upgrade_shots.json node tools/preview/render.mjs world upgrade_furnace upgrade_plant upgrade_solar upgrade_phone
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Color3 = (require("@lune/roblox") :: any).Color3

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineUpgradeView")

type Say = { Row: number, Text: string, Good: boolean }

local function screen(machineId: string, save: any, coins: number, scale: number, say: Say?): any
	local hud = HudView.build()
	hud.Gui.Scale.Scale = scale
	hud.Coins.Text = Format.money(coins)
	hud.Income.Text = Format.perSecond(1840)
	hud.Zone.Text = ""
	hud.Toasts:ClearAllChildren()
	HudView.placeBackpack(hud, scale)
	HudView.setBackpack(hud, 0, 30)
	local refs = View.build()
	refs.Gui.Scale.Scale = scale
	refs.Gui.Enabled = true
	local tier = MachineData.tierOf(save.MachineUpgrades, machineId)
	View.fill(refs, `{MachineData.info(machineId, tier).Name} Upgrades`, View.rows(machineId, save, coins))
	if say then
		local r = refs.Rows[say.Row]
		View.say(r, say.Text)
		r.Why.TextColor3 = if say.Good then Color3.fromRGB(130, 240, 120) else Color3.fromRGB(255, 120, 110)
	end
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
	return UiExport.export({ hud.Gui, refs.Gui })
end

local FURNACE = { MachineUpgrades = { ClayFurnace = { Speed = 1, Tier = 1 } }, Upgrades = { Bellows = 1 } }
local PLANT = { MachineUpgrades = { AutoCleaner = { Speed = 2, Quality = 5 } }, Upgrades = { Bellows = 2 } }
local SOLAR = { MachineUpgrades = { SolarPanel = { Speed = 1 } }, Upgrades = { Bellows = 0 } }

local files = {
	ui_upgrade_furnace = screen("ClayFurnace", FURNACE, 480000, 1.25),
	ui_upgrade_plant = screen("AutoCleaner", PLANT, 2400000, 1.25, { Row = 1, Text = View.Reasons.Bought, Good = true }),
	ui_upgrade_solar = screen("SolarPanel", SOLAR, 2400000, 1.25),
	ui_upgrade_phone = screen("ClayFurnace", FURNACE, 30000, 0.62, { Row = 2, Text = View.reasonText("NoCoins"), Good = false }),
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
	root .. "/build/preview/machine_upgrade_shots.json",
	serde.encode("json", {
		upgrade_furnace = shot("ui_upgrade_furnace"),
		upgrade_plant = shot("ui_upgrade_plant"),
		upgrade_solar = shot("ui_upgrade_solar"),
		upgrade_phone = shot("ui_upgrade_phone", 844, 390),
	})
)
print("machine upgrades: 4 screens")
