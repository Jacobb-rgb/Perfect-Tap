--[[
	The HUD in the pixel reels' look (owner 2026-10-22) with nothing else on
	screen (scene "hud_quick" for tools/lune/export_scene.luau: no world, fast
	UI iteration). Drawn with the game's own code (HudBubble, TeleportView,
	TrainView, BoostView, WheelView). UI overlays (build/preview/<name>.json):
	  ui_hud_pixel_pc       PC: the top bar, the left tiles with the TRAIN and
	                        boost chips, the FREE SPIN chip, a full hotbar
	  ui_hud_pixel_phone    667 x 375 pt phone (uiScale 0.62)
	  ui_hud_pixel_narrow   568 x 320 pt phone (the narrow top bar)
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local roblox = require("@lune/roblox") :: any
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
	local NOW = 1.7e9

	-- `renderScale` px per design unit, `uiScale` the game's scale (0.62 phones), `screen` in pt
	local function hud(renderScale: number, uiScale: number, screen: Vector2): { any }
		local compact = uiScale <= 0.75
		local refs = HudBubble.buildGame(uiScale, screen.X)
		-- (as HudController does: on phones the boost chips stop before the Shop pill)
		BoostView.HudChipsRight = HudBubble.chipsRight(refs.Gui, screen.X / uiScale)
		TeleportView.build(refs.TopBar, uiScale, screen.X)
		refs.Gui.Scale.Scale = renderScale
		refs.Coins.Text = Format.money(4.82e6)
		refs.Income.Text = Format.perSecond(1840)
		refs.Toasts:ClearAllChildren()
		HudBubble.claimTile(refs.Menu, "Build")
		for _, entry in SideMenuView.sorted() do
			local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
			if entry.Group == "Main" then
				HudBubble.claimTile(refs.Menu, entry.Id, spec)
			else
				HudBubble.addMore(refs.Menu, entry.Id, spec)
			end
		end
		-- the backpack button as HudController fills it (12 of 30) with the PC key hint
		HudView.setBackpack(refs, 12, 30)
		HudView.setBackpackKey(refs, if compact then nil else "Q", nil)
		local list = { refs.Gui }
		-- the TRAIN chip and the boost chips (TrainController / BoostController place them)
		TrainView.HudChipTop = refs.Gui:GetAttribute("ChipTop")
		local train = TrainView.build(compact)
		train.Chip.Scale.Scale = renderScale
		train.Gui.Scale.Scale = renderScale
		TrainView.layout(train, compact, screen.X / uiScale, screen.Y / uiScale)
		train.ChipKey.Visible = not compact
		TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 5, Capacity = 8, Moving = 0 }), NOW, nil))
		train.Gui.Enabled = false
		train.Chip.Enabled = true
		table.insert(list, train.Chip)
		local boost = BoostView.buildChips()
		boost.Gui.Scale.Scale = renderScale
		BoostView.placeChips(boost, BoostView.chipsTop(train.ChipFrame, compact), BoostView.chipsLeft(train.ChipFrame))
		local state = { Boosts = { TripleLuckyUntil = NOW + 222, HexaLuckyUntil = NOW + 3900 } }
		BoostView.setChips(boost, BoostView.chips(state, NOW), false)
		boost.Gui.Enabled = true
		table.insert(list, boost.Gui)
		-- the FREE SPIN chip right of the top bar
		local spin = WheelView.buildChip(uiScale, screen.X)
		spin.Gui.Scale.Scale = renderScale
		spin.Gui.Enabled = true
		table.insert(list, spin.Gui)
		return list
	end

	local exports: { [string]: any } = {}
	exports.ui_hud_pixel_pc = UiExport.export(hud(1.25, 1.25, roblox.Vector2.new(1600, 864)))
	exports.ui_hud_pixel_phone = UiExport.export(hud(0.62 * 900 / 375, 0.62, roblox.Vector2.new(667, 375 - 58 * 375 / 900)))
	exports.ui_hud_pixel_narrow = UiExport.export(hud(0.62 * 900 / 320, 0.62, roblox.Vector2.new(568, 320 - 58 * 320 / 900)))
	return exports
end

return Preview
