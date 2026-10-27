--[[
	The EMOTES menu over the HUD, for the preview pictures (UI overlays only;
	the world comes from the "store" scene: lune run tools/lune/export_scene.luau store).
	Drawn with the game's own code (EmoteView, HudBubble: the EMOTES tile in the left menu).

	  lune run tools/lune/export_emote_menu.luau
	-> build/preview/ui_emotes_pc.json, ui_emotes_hud_pc, ui_emotes_phone, ui_emotes_hud_phone
	   (shots: tools/preview/emote_menu_shots.json; the HUD's icons: node tools/preview/render_icons.mjs)
	  SHOTS_EXTRA=tools/preview/emote_menu_shots.json node tools/preview/render.mjs store emotes_pc emotes_hud_pc emotes_phone emotes_hud_phone
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
local EmoteRules = Loader.requirePath("ReplicatedStorage.Shared.Moves.EmoteRules")
local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
local EmoteView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EmoteView")

local scale = 1.25 -- a 900 px tall render / 720 design height
local phoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone at HudController's 0.62

local function hud(uiScale: number): any
	local phone = uiScale > 1.4
	local refs = HudBubble.buildGame(if phone then 0.62 else 1.25)
	TeleportView.build(refs.TopBar, if phone then 0.62 else 1.25, 1600 / uiScale)
	refs.Gui.Scale.Scale = uiScale
	refs.Coins.Text = Format.money(4.82e6)
	refs.Income.Text = Format.perSecond(1840)
	HudView.setBackpack(refs, 0, 5)
	refs.Toasts:ClearAllChildren()
	-- the left tiles as the controllers claim them in the game, the EMOTES tile last
	HudBubble.claimTile(refs.Menu, "Build")
	for _, entry in SideMenuView.sorted() do
		local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
		if entry.Group == "Main" then
			HudBubble.claimTile(refs.Menu, entry.Id, spec)
		else
			HudBubble.addMore(refs.Menu, entry.Id, spec)
		end
	end
	HudBubble.claimTile(refs.Menu, "Emotes", { Label = "EMOTES", IconName = "Emotes", Order = 40 })
	return refs
end

local function menu(uiScale: number, w: number, h: number, compact: boolean, hint: string): any
	local refs = EmoteView.build()
	refs.Gui.Scale.Scale = uiScale
	refs.Gui.Enabled = true
	EmoteView.layout(refs, w, h, compact)
	-- as EmoteController shows it: one emote playing, the Blaster Spin without the blaster
	EmoteView.setCard(refs, "Breakdance", "Playing", "pick again to stop")
	EmoteView.setCard(refs, "BlasterSpin", "Locked", EmoteRules.NeedsBlaster)
	EmoteView.setHint(refs, hint)
	return refs
end

local exports: { [string]: any } = {}
local pcW, pcH = 1600 / scale, (900 - 36) / scale
exports.ui_emotes_pc = UiExport.export({ hud(scale).Gui, menu(scale, pcW, pcH, false, "Pick a move. Walk to stop it.   N: this menu").Gui })
exports.ui_emotes_hud_pc = UiExport.export({ hud(scale).Gui })
local phW, phH = 1600 / phoneScale, (900 - 58) / phoneScale
exports.ui_emotes_phone = UiExport.export({ hud(phoneScale).Gui, menu(phoneScale, phW, phH, true, "Tap a move. Walk to stop it.").Gui })
exports.ui_emotes_hud_phone = UiExport.export({ hud(phoneScale).Gui })

fs.writeDir(root .. "/build/preview")
for name, guis in exports do
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", guis))
	print("Exported UI " .. name)
end
