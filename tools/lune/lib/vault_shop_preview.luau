--[[
	The Blaster Vault shop window over the vault interior (scene "vault_shop"
	for tools/lune/export_scene.luau: the world, shots in
	tools/preview/vault_shop_shots.json at the vault counter). Drawn with the
	game's own code (VaultView.build / layout / cards, HudView).
	UI overlays (build/preview/<name>.json):
	  ui_vault_pc           PC: a level 3 player who can buy level 4
	  ui_vault_pc_poor      PC: level 6 next, not enough coins (red price, the message)
	  ui_vault_phone        667 x 375 pt phone (compact: one row that scrolls)
	  ui_vault_phone_small  568 x 320 pt phone
	  ui_vault_tv           1080p TV (console, HUD scale 1.25): the compact layout
	With LIGHT_UI=1 in the environment the same overlays use the light UI
	(UIConfig.LightUI on) and their names end in "_light".
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local VaultView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.VaultView")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")

	local process = require("@lune/process")
	local light = process.env.LIGHT_UI == "1"
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	UIConfig.LightUI = light

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = VaultView.PhoneScale * 900 / 375
	local smallScale = VaultView.PhoneScale * 900 / 320
	local smallInset = math.floor(58 * 900 / 320)

	local function hud(uiScale: number, coins: number): any
		-- the light HUD picks its phone layout from the screen (no camera in Lune)
		local refs = if light then HudBubble.buildGame(if uiScale > 1.4 then 0.62 else 1.25) else HudView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(coins)
		refs.Income.Text = Format.perSecond(2400)
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		return refs
	end

	local function view(
		uiScale: number,
		compact: boolean,
		maxWidth: number,
		maxHeight: number,
		level: number,
		coins: number,
		hint: string
	): any
		local refs = VaultView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		VaultView.layout(refs, compact, maxWidth, maxHeight)
		VaultView.setCards(refs, VaultView.cards(level, coins))
		VaultView.setCoins(refs, coins)
		VaultView.setCurrent(refs, level, BlasterData.vaultOre(level))
		VaultView.setHint(refs, hint)
		return refs
	end

	local exports: { [string]: any } = {}
	local pcWidth, pcHeight = 1600 / scale, (900 - 36) / scale
	local pcHint = `Click BUY on the next case{VaultView.Separator}Backspace: close`

	-- level 3 with 125K: level 4 (60K) can be bought
	exports.ui_vault_pc = UiExport.export({ hud(scale, 125400).Gui, view(scale, false, pcWidth, pcHeight, 3, 125400, pcHint).Gui })

	-- level 5 with 1.9M: level 6 costs 2.8M (red), BUY tells why
	local poor = view(scale, false, pcWidth, pcHeight, 5, 1.9e6, pcHint)
	VaultView.setMessage(poor, VaultView.reasonText("NoCoins"), VaultView.Style.Bad)
	exports.ui_vault_pc_poor = UiExport.export({ hud(scale, 1.9e6).Gui, poor.Gui })

	-- phones: the compact layout
	exports.ui_vault_phone = UiExport.export({
		hud(phoneScale, 125400).Gui,
		view(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, 3, 125400, "Tap BUY").Gui,
	})
	exports.ui_vault_phone_small = UiExport.export({
		hud(smallScale, 4.2e9).Gui,
		view(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, 7, 4.2e9, "Tap BUY").Gui,
	})

	-- a console on a 1080p TV
	local tvScale = 1.25 * 900 / 1080
	exports.ui_vault_tv = UiExport.export({
		hud(tvScale, 9e9).Gui,
		view(tvScale, true, 1600 / tvScale, (900 - 36 * 900 / 1080) / tvScale, 9, 9e9, "A: buy   B: close").Gui,
	})
	UIConfig.LightUI = false
	if light then
		local renamed = {}
		for name, guis in exports do
			renamed[name .. "_light"] = guis
		end
		return renamed
	end
	return exports
end

return Preview
