--[[
	The STAR FORGE window (rebirth B) over the lobby (scene "rebirth" for
	tools/lune/export_scene.luau: the world, shots in
	tools/preview/rebirth_shots.json). Drawn with the game's own code
	(RebirthView, HudView). UI overlays (build/preview/<name>.json):
	  ui_rebirth_pc            PC: blaster 8, ready (a rebirth pays its stars)
	  ui_rebirth_pc_locked     PC: blaster 4, not ready (the grey button)
	  ui_rebirth_pc_sure       PC: the first press: "SURE?"
	  ui_rebirth_shop_pc       PC: the STAR SHOP with 9 stars and some perks
	  ui_rebirth_phone         667 x 375 pt phone (compact: tabs in the header)
	  ui_rebirth_phone_small   568 x 320 pt phone
	  ui_rebirth_shop_phone    667 x 375 pt phone, the STAR SHOP
	  ui_rebirth_moment        the moment: "REBIRTH 2!", +6 Forge Stars, falling stars
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")
	local RebirthView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RebirthView")

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = MenuPanel.PhoneScale * 900 / 375
	local smallScale = MenuPanel.PhoneScale * 900 / 320
	local smallInset = math.floor(58 * 900 / 320)

	local function hud(uiScale: number, coins: number): any
		local refs = HudView.build()
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

	local function info(level: number, stars: number, perks: any, count: number): any
		return {
			Count = count,
			Stars = stars,
			Perks = perks,
			Level = level,
			Ready = level >= RebirthConfig.MinBlaster,
			StarsNow = RebirthConfig.starsFor(level),
		}
	end

	local function view(uiScale: number, compact: boolean, maxWidth: number, maxHeight: number, data: any, tab: string, hint: string): any
		local refs = RebirthView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		MenuPanel.setHint(refs.Frame, hint, nil)
		RebirthView.setTab(refs, tab)
		RebirthView.layout(refs, compact, maxWidth, maxHeight)
		RebirthView.setInfo(refs, data)
		return refs
	end

	local exports: { [string]: any } = {}
	local pcWidth, pcHeight = 1600 / scale, (900 - 36) / scale
	local pcHint = "Rebirth is optional: you choose when · Backspace: close"
	local perks = { GoldenTouch = 2 }

	exports.ui_rebirth_pc = UiExport.export({
		hud(scale, 1.4e9).Gui,
		view(scale, false, pcWidth, pcHeight, info(8, 3, perks, 1), "Rebirth", pcHint).Gui,
	})
	exports.ui_rebirth_pc_locked = UiExport.export({
		hud(scale, 2.1e6).Gui,
		view(scale, false, pcWidth, pcHeight, info(4, 0, {}, 0), "Rebirth", pcHint).Gui,
	})
	local sure = view(scale, false, pcWidth, pcHeight, info(8, 3, perks, 1), "Rebirth", pcHint)
	RebirthView.setConfirm(sure, true)
	exports.ui_rebirth_pc_sure = UiExport.export({ hud(scale, 1.4e9).Gui, sure.Gui })
	local shopPerks = { GoldenTouch = 4, HeadStart = 1, DeepPockets = 3, ExpressRails = 1 }
	exports.ui_rebirth_shop_pc = UiExport.export({
		hud(scale, 1.4e9).Gui,
		view(scale, false, pcWidth, pcHeight, info(8, 9, shopPerks, 3), "Shop", pcHint).Gui,
	})
	exports.ui_rebirth_phone = UiExport.export({
		hud(phoneScale, 1.4e9).Gui,
		view(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, info(8, 3, perks, 1), "Rebirth", "").Gui,
	})
	exports.ui_rebirth_phone_small = UiExport.export({
		hud(smallScale, 1.4e9).Gui,
		view(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, info(8, 3, perks, 1), "Rebirth", "").Gui,
	})
	exports.ui_rebirth_shop_phone = UiExport.export({
		hud(phoneScale, 1.4e9).Gui,
		view(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, info(8, 9, shopPerks, 3), "Shop", "").Gui,
	})
	local moment = RebirthView.buildMoment(2, RebirthConfig.starsFor(8), 11)
	moment.Flash.BackgroundTransparency = 0.82 -- the flash fading out
	exports.ui_rebirth_moment = UiExport.export({ hud(scale, 0).Gui, moment.Gui })
	return exports
end

return Preview
