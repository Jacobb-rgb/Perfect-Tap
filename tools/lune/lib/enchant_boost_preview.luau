--[[
	The Enchant shop and the luck boosts over the game (scene "enchants" for
	tools/lune/export_scene.luau: the world; shots in
	tools/preview/enchant_boost_shots.json at the rune table and in Deep
	Hollow). Everything is drawn with the game's own code (EnchantView,
	BoostView, HudView, TrainView's chip) from a mid-game State snapshot:
	blaster level 5, Power II and Lucky I in the two open slots, Twin Drop
	I owned, Triple Lucky running. Every HUD shows the train chip and a
	"+$X" popup under the coins, with the boost chips under the train chip.
	UI overlays (build/preview/<name>.json):
	  ui_enchant_lucky     PC: Lucky picked, its new odds in Deep Hollow
	  ui_enchant_star      PC: Starbreaker (1T coins or "20 R$ • SOON" until
	                       step 8's receipts gate), its ore luck and artifact
	                       rows, both slots full: AFTER with it in place of
	                       Power, the server's "bought" receipt
	  ui_enchant_pick      PC: Twin Drop owned, EQUIP with both slots full:
	                       the slots light up, "Pick a slot"
	  ui_enchant_phone     667 x 375 pt phone (compact), Lucky
	  ui_enchant_small     568 x 320 pt phone, Prospector (artifact odds per
	                       zone)
	  ui_enchant_tv        1080p TV (console), Overcharge (coins or shards),
	                       the gamepad row
	  ui_boost_hexa        PC: Hexa Lucky, every Deep Hollow ore without / with
	  ui_boost_triple      PC: Triple Lucky (running), Crystal capsule golems
	  ui_boost_phone       phone: Hexa Lucky
	  ui_boost_small       small phone: Triple Lucky (the short card)
	  ui_boost_tv          1080p TV: Hexa Lucky, the gamepad row
	  ui_hud_chips         PC HUD: the two running boosts under the train chip
	                       ([clover] TRIPLE 3:42, [gem] HEXA 1h 05m)
	  ui_hud_launcher      phone HUD: the BOOSTS launcher (no boost running; only in a game without the side menu)
	Every view gets what this build says is coming soon (Preview.soon: the
	same set the controllers build from BoostService's attribute and the
	receipts gate), so nothing that is live shows COMING SOON.
	(the renderer has no scrolling: lists show their first rows; it draws
	no images, so the gamepad glyphs get a lettered stand-in)
]]

local UiExport = require("./uiexport")

local Preview = {}

Preview.Now = 1_800_000_000
Preview.Coins = 4_820_000
-- What this build says is coming soon, computed as the game does: the
-- BoostService.Consumers ids whose service isn't in the game
-- (BoostService.soonIds, the TerraForgeComingSoon attribute) plus
-- BoostView.RobuxSoon while step 8's receipts gate is shut (Receipts.ready).
function Preview.soon(Loader: any): { [string]: boolean }
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local Receipts = Loader.requirePath("ServerScriptService.Server.Receipts")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	return BoostView.soonNow(table.concat(BoostService.soonIds(), ","), Receipts.ready())
end

Preview.State = {
	Coins = Preview.Coins,
	BlasterLevel = 5,
	Shards = 135,
	Enchants = { Owned = { Power = 2, Lucky = 1, TwinDrop = 1 }, Slots = { "Power", "Lucky", "", "" } },
	Boosts = { TripleLuckyUntil = Preview.Now + 222, HexaLuckyUntil = 0 },
	Bonuses = { OreLuckPct = 0.15, OreLuckMult = 1, ArtifactPct = 0 },
	Perks = { ForgeVip = false },
}

function Preview.build(Loader: any): { [string]: any }
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local EnchantView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EnchantView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
	local UDim2 = Loader.roblox.UDim2

	local NOW = Preview.Now
	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = TechShopView.PhoneScale * 900 / 375 -- a 667 x 375 pt phone scaled up to the render
	local smallScale = TechShopView.PhoneScale * 900 / 320 -- a 568 x 320 pt phone
	local smallInset = math.floor(58 * 900 / 320)
	local tvScale = 1.25 * 900 / 1080

	-- a screen: its HUD scale, layout and the design room it gives
	type Screen = { Scale: number, Compact: boolean, Width: number, Height: number }
	local PC: Screen = { Scale = scale, Compact = false, Width = 1600 / scale, Height = (900 - 36) / scale }
	local PHONE: Screen = { Scale = phoneScale, Compact = true, Width = 1600 / phoneScale, Height = (900 - 58) / phoneScale }
	local SMALL: Screen = { Scale = smallScale, Compact = true, Width = 1600 / smallScale, Height = (900 - smallInset) / smallScale }
	local TV: Screen = { Scale = tvScale, Compact = true, Width = 1600 / tvScale, Height = (900 - 36 * 900 / 1080) / tvScale }

	-- the HUD with a "+$X" popup under the coins, the train chip (as
	-- TrainController shows it) and the boost chips under it (as
	-- BoostController places them)
	local function hud(screen: Screen, state: any, launcher: boolean): { any }
		local refs = HudView.build()
		refs.Gui.Scale.Scale = screen.Scale
		refs.Coins.Text = Format.money(Preview.Coins)
		refs.Income.Text = Format.perSecond(1840)
		refs.Income.TextColor3 = Theme.Good
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		HudView.floater(refs.Floaters, "+" .. Format.money(18400))
		local train = TrainView.build(screen.Compact)
		train.Chip.Scale.Scale = screen.Scale
		train.Gui.Scale.Scale = screen.Scale
		TrainView.layout(train, screen.Compact, screen.Width, screen.Height)
		train.ChipKey.Visible = not screen.Compact
		local snapshot = TrainView.read({ Cargo = 5, Capacity = 8, Moving = 0 })
		TrainView.setStatus(train, TrainView.status(snapshot, NOW, nil))
		train.Gui.Enabled = false
		train.Chip.Enabled = TrainView.chipVisible(true, false)
		local chips = BoostView.buildChips()
		chips.Gui.Scale.Scale = screen.Scale
		BoostView.placeChips(chips, BoostView.chipsTop(train.ChipFrame, screen.Compact))
		BoostView.setChips(chips, BoostView.chips(state, NOW), launcher)
		return { refs.Gui, train.Chip, chips.Gui }
	end

	-- the renderer draws no images: a lettered stand-in for each gamepad glyph
	local function fakeGlyphs(glyphs: { any }, names: { string })
		for i, image in glyphs do
			image.BackgroundTransparency = 0
			image.BackgroundColor3 = Theme.PanelLight
			UIKit.corner(image, 12)
			UIKit.label(image, names[i] or "?", 14, {
				Name = "Letter",
				Size = UDim2.fromScale(1, 1),
				FontFace = Theme.TitleFont,
				TextScaled = true,
				TextWrapped = false,
			})
		end
	end

	local soon = Preview.soon(Loader)
	local function enchants(screen: Screen, id: string, zone: string?, picking: string?): any
		local s = Preview.State
		local refs = EnchantView.build(screen.Compact)
		refs.Gui.Scale.Scale = screen.Scale
		refs.Gui.Enabled = true
		EnchantView.layout(refs, screen.Compact, screen.Width, screen.Height)
		local cards = EnchantView.cards(s, Preview.Coins, false, soon)
		local card = nil
		for _, c in cards do
			if c.Id == id then
				card = c
			end
		end
		EnchantView.setBalances(refs, Preview.Coins, s.Shards)
		EnchantView.setSlots(refs, EnchantView.slotCards(s), s.BlasterLevel, picking)
		EnchantView.setRows(refs, cards, id)
		local odds, canSwitch = EnchantView.odds(s, id, zone, NOW, soon)
		EnchantView.setDetail(refs, card, odds, canSwitch)
		if screen == TV then
			EnchantView.setHint(refs, "", { "", "", "" })
			fakeGlyphs(refs.PadGlyphs, { "A", "B", "RS" })
			EnchantView.setDetail(refs, card, odds, canSwitch)
		else
			EnchantView.setHint(refs, `Click an enchant, then BUY or EQUIP{EnchantView.Separator}Backspace: close`, nil)
		end
		if picking then
			EnchantView.setStatus(refs, EnchantView.StatusText.PickSlot, Theme.Accent)
		end
		return refs
	end

	local function boosts(screen: Screen, kind: string, zoneOrCapsule: string): any
		local refs = BoostView.build(screen.Compact)
		refs.Gui.Scale.Scale = screen.Scale
		refs.Gui.Enabled = true
		BoostView.layout(refs, screen.Compact, screen.Width, screen.Height)
		BoostView.setTab(refs, kind)
		BoostView.setCoins(refs, Preview.Coins)
		local cards = BoostView.cards(Preview.State, Preview.Coins, NOW, false, soon)
		BoostView.setCard(refs, if kind == "TripleLucky" then cards[1] else cards[2])
		if kind == "HexaLucky" then
			BoostView.setTable(refs.Odds, BoostView.hexaOdds(Preview.State, zoneOrCapsule), true)
		else
			BoostView.setTable(refs.Odds, BoostView.tripleOdds(zoneOrCapsule), true)
		end
		if screen == TV then
			BoostView.setHint(refs, "", { "", "", "", "", "" })
			fakeGlyphs(refs.PadGlyphs, { "LB", "RB", "A", "B", "RS" })
			BoostView.setCard(refs, if kind == "TripleLucky" then cards[1] else cards[2])
		else
			BoostView.setHint(refs, `Click an offer to buy{BoostView.Separator}L or Backspace: close`, nil)
		end
		return refs
	end

	-- a panel over the HUD and the train chip (the boost chips hide while a
	-- panel is open, as BoostController does)
	local function with(guis: { any }, extra: any): { any }
		local list = { guis[1], guis[2], extra.Gui }
		return UiExport.export(list)
	end

	local exports: { [string]: any } = {}
	exports.ui_enchant_lucky = with(hud(PC, Preview.State, true), enchants(PC, "Lucky", "DeepHollow", nil))
	local star = enchants(PC, "Starbreaker", "DeepHollow", nil)
	local EnchantService = Loader.requirePath("ServerScriptService.Server.Services.EnchantService")
	EnchantView.showReceipt(star, EnchantService.boughtText("Starbreaker", 1, nil), Theme.Good)
	exports.ui_enchant_star = with(hud(PC, Preview.State, true), star)
	exports.ui_enchant_pick = with(hud(PC, Preview.State, true), enchants(PC, "TwinDrop", "DeepHollow", "TwinDrop"))
	exports.ui_enchant_phone = with(hud(PHONE, Preview.State, true), enchants(PHONE, "Lucky", "EmberCaves", nil))
	exports.ui_enchant_small = with(hud(SMALL, Preview.State, true), enchants(SMALL, "Prospector", nil, nil))
	exports.ui_enchant_tv = with(hud(TV, Preview.State, true), enchants(TV, "Overcharge", nil, nil))

	exports.ui_boost_hexa = with(hud(PC, Preview.State, true), boosts(PC, "HexaLucky", "DeepHollow"))
	exports.ui_boost_triple = with(hud(PC, Preview.State, true), boosts(PC, "TripleLucky", "Crystal"))
	exports.ui_boost_phone = with(hud(PHONE, Preview.State, true), boosts(PHONE, "HexaLucky", "EmberCaves"))
	exports.ui_boost_small = with(hud(SMALL, Preview.State, true), boosts(SMALL, "TripleLucky", "Stone"))
	exports.ui_boost_tv = with(hud(TV, Preview.State, true), boosts(TV, "HexaLucky", "DeepHollow"))

	local both = table.clone(Preview.State)
	both.Boosts = { TripleLuckyUntil = NOW + 222, HexaLuckyUntil = NOW + 3900 }
	exports.ui_hud_chips = UiExport.export(hud(PC, both, true))
	local none = table.clone(Preview.State)
	none.Boosts = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 }
	exports.ui_hud_launcher = UiExport.export(hud(PHONE, none, true))
	return exports
end

return Preview
