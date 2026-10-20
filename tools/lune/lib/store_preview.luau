--[[
	The Robux STORE window (owner 2026-10-20, from his store photos) over the
	lobby (scene "store" for tools/lune/export_scene.luau: the world, shots in
	tools/preview/store_shots.json). Drawn with the game's own code
	(StoreView, HudBubble). UI overlays (build/preview/<name>.json):
	  ui_store_pc          PC: the first cards (the pass, coins, luck)
	  ui_store_pc_more     PC: scrolled on (capsules, the blaster, passes)
	  ui_store_pc_stars    PC: the end of the row, the five STAR blasters (3 rebirths)
	  ui_store_pc_odds     PC: the odds panel before a Royal Capsule x5 buy
	  ui_store_phone       667 x 375 pt phone
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375

	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local function hud(uiScale: number): any
		local refs = HudBubble.buildGame(if uiScale > 1.4 then 0.62 else 1.25)
		-- the BASE / LOBBY / VAULT tabs (TeleportController fills the top bar in the game)
		TeleportView.build(refs.TopBar, if uiScale > 1.4 then 0.62 else 1.25, 1600 / uiScale)
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(4.82e6)
		refs.Income.Text = Format.perSecond(1840)
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		return refs
	end

	local function store(uiScale: number, w: number, h: number, scroll: number?): any
		local refs = StoreView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		StoreView.layout(refs, w, h)
		StoreView.setCoins(refs, 1840)
		local blaster = StoreConfig.ById.Blaster
		StoreView.setCard(refs, "Blaster", StoreConfig.blasterKey(blaster, 4) or blaster.Keys[1], "Buy")
		StoreView.setBig(refs, "Blaster", "LV 5")
		StoreView.setCard(refs, "Podiums", "Podiums", "Owned")
		if scroll then
			refs.Scroller.CanvasPosition = (require("@lune/roblox") :: any).Vector2.new(scroll, 0)
		end
		return refs
	end

	-- the TRAIN and boost chips over the HUD (TrainController / BoostController place them)
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local NOW = 1.7e9
	local function chips(renderScale: number, compact: boolean, designW: number, designH: number, hudGui: any): { any }
		-- the light HUD puts the chip under its tiles (HudController does this in the game)
		TrainView.HudChipTop = hudGui:GetAttribute("ChipTop")
		local train = TrainView.build(compact)
		train.Chip.Scale.Scale = renderScale
		train.Gui.Scale.Scale = renderScale
		TrainView.layout(train, compact, designW, designH)
		train.ChipKey.Visible = not compact
		TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 5, Capacity = 8, Moving = 0 }), NOW, nil))
		train.Gui.Enabled = false
		train.Chip.Enabled = true
		local boost = BoostView.buildChips()
		boost.Gui.Scale.Scale = renderScale
		BoostView.placeChips(boost, BoostView.chipsTop(train.ChipFrame, compact), BoostView.chipsLeft(train.ChipFrame))
		local state = { Boosts = { TripleLuckyUntil = NOW + 222, HexaLuckyUntil = NOW + 3900 } }
		BoostView.setChips(boost, BoostView.chips(state, NOW), false)
		boost.Gui.Enabled = true
		return { train.Chip, boost.Gui }
	end

	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	exports.ui_store_pc = UiExport.export({ hud(scale).Gui, store(scale, pcW, pcH).Gui })
	exports.ui_store_pc_more = UiExport.export({ hud(scale).Gui, store(scale, pcW, pcH, 1580).Gui })
	-- the end of the row: the STAR blasters for a player with 3 rebirths
	local stars = store(scale, pcW, pcH, 3560)
	StoreView.setCard(stars, "StarComet", "StarComet", "Owned")
	StoreView.setNote(stars, "StarComet", "In your hands")
	StoreView.setCard(stars, "StarNebula", "StarNebula", "Owned")
	StoreView.setNote(stars, "StarNebula", "Equip it in the STAR FORGE")
	StoreView.setCard(stars, "StarPulsar", "StarPulsar", "Buy")
	StoreView.setNote(stars, "StarPulsar", "Kept forever, every rebirth")
	StoreView.setCard(stars, "StarSupernova", "StarSupernova", "Locked")
	StoreView.setCard(stars, "StarSingularity", "StarSingularity", "Locked")
	exports.ui_store_pc_stars = UiExport.export({ hud(scale).Gui, stars.Gui })
	local odds = store(scale, pcW, pcH, 1580)
	local lines = { "Royal Capsule x5: 5 golems, each one of:" }
	for _, line in CapsuleConfig.odds("Royal", false) do
		local golem = GolemConfig.ById[line.Golem]
		table.insert(lines, string.format("   %s  %.2f%%", if golem then golem.Name else line.Golem, line.Chance * 100))
	end
	StoreView.showDetail(odds, { Title = "Royal Capsule x5", Lines = lines, Robux = 229, Glow = "Red" })
	exports.ui_store_pc_odds = UiExport.export({ hud(scale).Gui, odds.Gui })
	-- the HUD with a train (review #16: the Shop pill clear of the TRAIN chip) and Server Luck on
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local function hudWithChips(uiScale: number, compact: boolean, w: number, h: number): { any }
		local refs = hud(uiScale)
		-- the left tiles as the controllers claim them in the game (SideMenuController, BuildView)
		HudBubble.claimTile(refs.Menu, "Build")
		for _, entry in SideMenuView.sorted() do
			local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
			if entry.Group == "Main" then
				HudBubble.claimTile(refs.Menu, entry.Id, spec)
			else
				HudBubble.addMore(refs.Menu, entry.Id, spec)
			end
		end
		local luck = refs.Gui:FindFirstChild("ServerLuck")
		if luck then
			luck.Text = "🍀 Server Luck x2 · 14:32 · thanks Kuba"
			luck.Visible = true
		end
		local list = { refs.Gui }
		for _, gui in chips(uiScale, compact, w, h, refs.Gui) do
			table.insert(list, gui)
		end
		return list
	end
	exports.ui_store_hud_pc = UiExport.export(hudWithChips(scale, false, pcW, pcH))
	exports.ui_store_hud_phone = UiExport.export(hudWithChips(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale))
	-- the odds panel on a phone (compact sizes)
	local phoneOdds = store(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale, 1580)
	StoreView.layout(phoneOdds, 1600 / phoneScale, (900 - 58) / phoneScale, true)
	StoreView.showDetail(phoneOdds, { Title = "Royal Capsule x5", Lines = lines, Robux = 229, Glow = "Red" })
	exports.ui_store_phone_odds = UiExport.export({ hud(phoneScale).Gui, phoneOdds.Gui })
	exports.ui_store_phone = UiExport.export({
		hud(phoneScale).Gui,
		store(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale).Gui,
	})
	return exports
end

return Preview
