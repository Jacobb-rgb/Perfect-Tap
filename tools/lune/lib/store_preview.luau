--[[
	The Robux STORE window (owner 2026-10-20, from his store photos) over the
	lobby (scene "store" for tools/lune/export_scene.luau: the world, shots in
	tools/preview/store_shots.json). Drawn with the game's own code
	(StoreView, HudBubble). UI overlays (build/preview/<name>.json):
	  ui_store_pc          PC: the first cards (the pass, coins, luck)
	  ui_store_pc_more     PC: scrolled on (capsules, the blaster, passes)
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

	local function hud(uiScale: number): any
		local refs = HudBubble.buildGame(if uiScale > 1.4 then 0.62 else 1.25)
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

	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	exports.ui_store_pc = UiExport.export({ hud(scale).Gui, store(scale, pcW, pcH).Gui })
	exports.ui_store_pc_more = UiExport.export({ hud(scale).Gui, store(scale, pcW, pcH, 1580).Gui })
	local odds = store(scale, pcW, pcH, 1580)
	local lines = { "Royal Capsule x5: 5 golems, each one of:" }
	for _, line in CapsuleConfig.odds("Royal", false) do
		local golem = GolemConfig.ById[line.Golem]
		table.insert(lines, string.format("   %s  %.2f%%", if golem then golem.Name else line.Golem, line.Chance * 100))
	end
	StoreView.showDetail(odds, { Title = "Royal Capsule x5", Lines = lines, Robux = 229, Glow = "Red" })
	exports.ui_store_pc_odds = UiExport.export({ hud(scale).Gui, odds.Gui })
	exports.ui_store_phone = UiExport.export({
		hud(phoneScale).Gui,
		store(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale).Gui,
	})
	return exports
end

return Preview
