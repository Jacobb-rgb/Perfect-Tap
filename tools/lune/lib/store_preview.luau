--[[
	The Robux STORE window (shop v3, owner 2026-11-11: the "WOW" concept)
	over the lobby (scene "store": the world, shots in
	tools/preview/store_shots.json) or an empty sky (scene "store_quick").
	Drawn with the game's own code (StoreView, HudBubble). UI overlays
	(build/preview/<name>.json), "today" = 2026-11-11 12:00 UTC (the
	Dragonforge edition ends Nov 30: 19d 11h left):
	  ui_store_pc            PC: FEATURED (the limited edition, the pass, the Starter Pack)
	  ui_store_pc_golems     PC: GOLEMS (the Royal Egg's golems and odds, x1 .. x10)
	  ui_store_pc_blasters   PC: BLASTERS (LV 4, three rebirths: two STAR blasters locked)
	  ui_store_pc_passes     PC: PASSES (Two More Podiums owned)
	  ui_store_pc_boosts     PC: BOOSTS (Server Luck, spins, luck, the Mythic enchants)
	  ui_store_pc_cash       PC: CASH (the coins at $1.84K/s)
	  ui_store_pc_odds       PC: the odds panel before a Royal Egg x5 buy
	  ui_store_pc_bare       PC: FEATURED as Studio shows it before the effects picture is
	                         uploaded (IconAssets.ShopFx: no rays, no studs, plain gradients)
	  ui_store_pc_bare_boosts / _bare_cash  BOOSTS / CASH before that upload
	  ui_store_phone         667 x 375 pt phone: FEATURED (44 pt buttons, the page scrolls)
	  ui_store_phone_golems  the phone: GOLEMS (and _blasters, _passes, _boosts; _cash scrolled down)
	  ui_store_phone_odds    the phone: the odds panel
	  ui_store_phone_small_limited  568 x 320 pt: FEATURED
	  ui_store_hud_pc / ui_store_hud_phone / ui_store_hud_phone_busy  the HUD without the window
	  ui_starter_popup_pc    the Starter Pack popup (first hour of play)
	The old names (ui_store_pc_more, _stars, _limited, _starter, _money) stay as
	aliases of the matching tabs.
]]

local process = require("@lune/process")
local UiExport = require("./uiexport")

local Preview = {}

Preview.Now = 1794398400 -- 2026-11-11 12:00 UTC
Preview.Income = 1840 -- the player's podium income ($1.84K/s, the concept's)

-- The game HUD as the controllers fill it (the left tiles claimed), for the shop renders.
function Preview.hud(Loader: any, uiScale: number): any
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local refs = HudBubble.buildGame(if uiScale > 1.4 then 0.62 else 1.25)
	-- the BASE / LOBBY / VAULT tabs (TeleportController fills the top bar in the game)
	TeleportView.build(refs.TopBar, if uiScale > 1.4 then 0.62 else 1.25, 1600 / uiScale)
	refs.Gui.Scale.Scale = uiScale
	refs.Coins.Text = Format.money(4.82e6)
	refs.Income.Text = Format.perSecond(Preview.Income)
	HudView.setBackpack(refs, 0, 5)
	refs.Toasts:ClearAllChildren()
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
	return refs
end

--[[
	An egg pack's pile is one 3D view of three eggs: the preview draws its
	parts (PreviewLive), not one egg's picture, and every Royal egg so for
	the same look. LIVE=1 draws every built 3D view so, with the game's
	viewport light (no special meshes). Again after a page is built later.
]]
function Preview.liveEggs(refs: any)
	local live = process.env.LIVE == "1"
	for _, d in refs.Gui:GetDescendants() do
		local egg = d:GetAttribute("Copies") == 3 or d:GetAttribute("Icon") == "capsule_Royal"
		if egg or (live and d:IsA("ImageLabel") and d:FindFirstChild("View")) then
			local view = d:FindFirstChild("View")
			if view and view:IsA("ViewportFrame") and #view:GetChildren() > 0 then
				d:SetAttribute("Icon", nil)
				view:SetAttribute("PreviewLive", true)
			end
		end
	end
end

-- The shop window as StoreController fills it for a player at LV 4 with three rebirths, tab `tab` open.
function Preview.store(Loader: any, uiScale: number, w: number, h: number, tab: string?, compact: boolean?): any
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")
	local _, fit = StoreView.windowSize(w, h)
	local refs = StoreView.build(StoreView.metricsFor(compact, fit))
	refs.Gui.Scale.Scale = uiScale
	refs.Gui.Enabled = true
	StoreView.layout(refs, w, h, compact)
	local blaster = StoreConfig.ById.Blaster
	StoreView.setCard(refs, "Blaster", StoreConfig.blasterKey(blaster, 4) or blaster.Keys[1], "Buy")
	StoreView.setBig(refs, "Blaster", "LV 4 > LV 5")
	StoreView.setCard(refs, "Podiums", "Podiums", "Owned")
	for id, note in
		{
			StarComet = "Kept forever, every rebirth",
			StarNebula = "Kept forever, every rebirth",
			StarPulsar = "Kept forever, every rebirth",
		}
	do
		StoreView.setCard(refs, id, id, "Buy")
		StoreView.setNote(refs, id, note)
	end
	StoreView.setCard(refs, "StarSupernova", "StarSupernova", "Locked")
	StoreView.setCard(refs, "StarSingularity", "StarSingularity", "Locked")
	StoreView.setCoins(refs, Preview.Income)
	local current = LimitedGolems.current(Preview.Now)
	if current then
		StoreView.setEdition(refs, current)
		StoreView.setTimer(refs, current.EndsAt - Preview.Now)
		local odds = {}
		for _, line in CapsuleConfig.odds(current.CapsuleId, false) do
			odds[line.Golem] = line.Chance
		end
		StoreView.setBannerOdds(refs, odds, false)
	end
	local royal = {}
	for _, line in CapsuleConfig.odds("Royal", false) do
		royal[line.Golem] = line.Chance
	end
	StoreView.setRoyalOdds(refs, royal, false)
	StoreView.selectTab(refs, tab or "Featured")
	Preview.liveEggs(refs)
	return refs
end

function Preview.build(Loader: any): { [string]: any }
	local roblox = require("@lune/roblox") :: any
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375

	local function hud(uiScale: number): any
		return Preview.hud(Loader, uiScale)
	end
	local function store(uiScale: number, w: number, h: number, tab: string?, compact: boolean?): any
		return Preview.store(Loader, uiScale, w, h, tab, compact)
	end

	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	local function pc(tab: string?): any
		return UiExport.export({ hud(scale).Gui, store(scale, pcW, pcH, tab).Gui })
	end
	exports.ui_store_pc = pc("Featured")
	exports.ui_store_pc_golems = pc("Golems")
	exports.ui_store_pc_blasters = pc("Blasters")
	exports.ui_store_pc_passes = pc("Passes")
	exports.ui_store_pc_boosts = pc("Boosts")
	exports.ui_store_pc_cash = pc("Cash")
	-- (the old names: the tabs that hold what they showed)
	exports.ui_store_pc_limited = exports.ui_store_pc
	exports.ui_store_pc_starter = exports.ui_store_pc
	exports.ui_store_pc_more = exports.ui_store_pc_golems
	exports.ui_store_pc_stars = exports.ui_store_pc_blasters
	exports.ui_store_pc_money = exports.ui_store_pc_cash

	-- the odds panel before a Royal Egg x5 buy (StoreController's lines)
	local lines = { "Royal Egg x5: each golem is one of (odds):" }
	for _, line in CapsuleConfig.odds("Royal", false) do
		local golem = GolemConfig.ById[line.Golem]
		table.insert(lines, `   {if golem then golem.Name else line.Golem}:  {StoreView.percent(line.Chance)}`)
	end
	local odds = store(scale, pcW, pcH, "Golems")
	StoreView.showDetail(odds, { Title = "Royal Egg x5", Lines = lines, Robux = 229, Paint = "Pink" })
	exports.ui_store_pc_odds = UiExport.export({ hud(scale).Gui, odds.Gui })

	-- before the effects picture is uploaded (what Studio shows now): plain gradients, the icon
	-- sheet's bolt and sparkle (the icon sheet itself is uploaded)
	local before, beforeId = IconAssets.ShopFx.Preview, IconAssets.ShopFx.Id
	IconAssets.ShopFx.Preview = false
	IconAssets.ShopFx.Id = 0
	exports.ui_store_pc_bare = pc("Featured")
	exports.ui_store_pc_bare_boosts = pc("Boosts")
	exports.ui_store_pc_bare_cash = pc("Cash")
	IconAssets.ShopFx.Preview = before
	IconAssets.ShopFx.Id = beforeId

	-- phones: the 44 pt sizes, the page scrolls
	local phoneW, phoneH = 1600 / phoneScale, (900 - 58) / phoneScale
	exports.ui_store_phone = UiExport.export({ hud(phoneScale).Gui, store(phoneScale, phoneW, phoneH, "Featured", true).Gui })
	exports.ui_store_phone_golems = UiExport.export({ hud(phoneScale).Gui, store(phoneScale, phoneW, phoneH, "Golems", true).Gui })
	for _, tab in { "Blasters", "Passes", "Boosts" } do
		exports["ui_store_phone_" .. string.lower(tab)] =
			UiExport.export({ hud(phoneScale).Gui, store(phoneScale, phoneW, phoneH, tab, true).Gui })
	end
	do
		local scrolled = store(phoneScale, phoneW, phoneH, "Cash", true)
		scrolled.Scroller.CanvasPosition = roblox.Vector2.new(0, 160)
		exports.ui_store_phone_cash = UiExport.export({ hud(phoneScale).Gui, scrolled.Gui })
	end
	local phoneOdds = store(phoneScale, phoneW, phoneH, "Golems", true)
	StoreView.showDetail(phoneOdds, { Title = "Royal Egg x5", Lines = lines, Robux = 229, Paint = "Pink" })
	exports.ui_store_phone_odds = UiExport.export({ hud(phoneScale).Gui, phoneOdds.Gui })
	do
		local small = 0.62 * 900 / 320
		local w, h = 1600 / small, (900 - 163) / small
		exports.ui_store_phone_small_limited = UiExport.export({ hud(small).Gui, store(small, w, h, "Featured", true).Gui })
	end

	-- the HUD alone (the Shop button and the offers it opens the window from)
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local function chips(renderScale: number, compact: boolean, designW: number, designH: number, hudGui: any): { any }
		-- the light HUD puts the chip under its tiles (HudController does this in the game)
		TrainView.HudChipTop = hudGui:GetAttribute("ChipTop")
		local train = TrainView.build(compact)
		train.Chip.Scale.Scale = renderScale
		train.Gui.Scale.Scale = renderScale
		TrainView.layout(train, compact, designW, designH)
		train.ChipKey.Visible = not compact
		TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 5, Capacity = 8, Moving = 0 }), 1.7e9, nil))
		train.Gui.Enabled = false
		train.Chip.Enabled = true
		local boost = BoostView.buildChips()
		boost.Gui.Scale.Scale = renderScale
		BoostView.placeChips(boost, BoostView.chipsTop(train.ChipFrame, compact), BoostView.chipsLeft(train.ChipFrame))
		local state = { Boosts = { TripleLuckyUntil = 1.7e9 + 222, HexaLuckyUntil = 1.7e9 + 3900 } }
		BoostView.setChips(boost, BoostView.chips(state, 1.7e9), false)
		boost.Gui.Enabled = true
		return { train.Chip, boost.Gui }
	end
	local function hudWithChips(uiScale: number, compact: boolean, w: number, h: number): { any }
		local refs = hud(uiScale)
		local luck = refs.Gui:FindFirstChild("ServerLuck")
		if luck then
			-- (as StoreController writes it: phones drop "thanks name")
			luck.Text = if refs.Gui:GetAttribute("ShortLuck") then "Server Luck x2 · 14:32" else "Server Luck x2 · 14:32 · thanks Kuba"
			luck.Visible = true
		end
		local list = { refs.Gui }
		for _, gui in chips(uiScale, compact, w, h, refs.Gui) do
			table.insert(list, gui)
		end
		return list
	end
	exports.ui_store_hud_pc = UiExport.export(hudWithChips(scale, false, pcW, pcH))
	exports.ui_store_hud_phone = UiExport.export(hudWithChips(phoneScale, true, phoneW, phoneH))
	do
		local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")
		local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
		local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
		local list = hudWithChips(phoneScale, true, phoneW, phoneH)
		local tutorial = TutorialView.build()
		tutorial.Gui.Scale.Scale = phoneScale
		TutorialView.apply(tutorial, TutorialView.layout(0.62, roblox.Vector2.new(667, 375), true, false, nil))
		local step = TutorialConfig.get(2)
		TutorialView.setStep(tutorial, 2, step, if step.Hint then step.Hint.Touch else nil)
		tutorial.Bubble.Visible = true
		table.insert(list, tutorial.Gui)
		local spin = WheelView.buildChip(0.62, 667)
		spin.Gui.Scale.Scale = phoneScale
		spin.Gui.Enabled = true
		table.insert(list, spin.Gui)
		exports.ui_store_hud_phone_busy = UiExport.export(list)
	end
	local StarterPackView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StarterPackView")
	local popup = StarterPackView.build()
	popup.Gui.Scale.Scale = scale
	popup.Gui.Enabled = true
	exports.ui_starter_popup_pc = UiExport.export({ hud(scale).Gui, popup.Gui })
	return exports
end

return Preview
