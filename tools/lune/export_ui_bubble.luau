--[[
	Exports the light "Bubble" HUD (src/client/UI/HudBubble.luau) with sample
	numbers for preview renders: build/preview/ui_bubble_pc.json and
	ui_bubble_phone.json. Shots: tools/preview/ui_bubble_shots.json (the world
	scene + this overlay; icons from tools/preview/render_icons.mjs).

	  lune run tools/lune/export_ui_bubble.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
local Bubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Bubble")

-- uiScale = what HudController picks on that screen; pixels = render pixels per point
local function export(name: string, uiScale: number, pixels: number)
	local refs = HudBubble.build(uiScale)
	refs.Gui.Scale.Scale = uiScale * pixels
	refs.Coins.Text = "$1.25M"
	refs.Income.Text = "+$12.4K/s"
	HudBubble.setSlot(refs.Slots[1], "blaster", true)
	HudBubble.setSlot(refs.Slots[2], "ore_raw")
	HudBubble.setSlot(refs.Slots[3], "ingot_gold")
	refs.CarryLabel.Text = "CARRYING 2/3"
	HudBubble.toast(refs.Toasts, "New ore found: Copper!", "ore_raw", 1)
	local golems = refs.Menu.Golems
	if golems then
		Bubble.badge(golems, "!")
	end
	fs.writeDir(root .. "/build/preview")
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", UiExport.export({ refs.Gui })))
	print("Exported UI " .. name)
end

export("ui_bubble_pc", 1.25, 1)
export("ui_bubble_phone", 0.62, 2)
