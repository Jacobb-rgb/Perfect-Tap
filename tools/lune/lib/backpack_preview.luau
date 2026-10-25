--[[
	The backpack inventory window and the HUD's backpack button (owner
	2026-10-24: everything goes into the backpack; docs/plans/
	OWNER_PLAYTEST_1024.md "4 + 5") with nothing else on screen (scene
	"backpack_quick" for tools/lune/export_scene.luau: no world, fast UI
	iteration). Drawn with the game's own code (HudBubble, BackpackView,
	BackpackState) from a State snapshot. UI overlays (build/preview/<name>.json):
	  ui_backpack_pc      PC 1600 x 900: a mid-game Iron-Bound Pack, 62 / 100
	  ui_backpack_phone   667 x 375 pt phone (the compact layout)
	  ui_backpack_tv      1080p TV (compact, the gamepad hint)
	  ui_backpack_full    PC, a full Rookie Pack (5 / 5: FULL on the bar and the button)
	  ui_backpack_empty   PC, an empty backpack (the empty line)
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local roblox = require("@lune/roblox") :: any
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local BackpackView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BackpackView")
	local BackpackState = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.BackpackState")

	local function key(kind: string, ore: string, grade: string?): string
		return ItemData.storageKey({ K = kind, O = ore, G = grade })
	end
	-- a mid-game backpack: dirty ore, a dusty relic and cleaned ore of every kind of rarity
	local midGame = {
		Backpacks = {
			Equipped = "IronboundPack",
			Count = 62,
			Capacity = 100,
			Items = {
				[key("Raw", "Copper")] = 18,
				[key("Raw", "Gold")] = 9,
				[key("Raw", "Diamond")] = 3,
				[`Relic|{ArtifactConfig.List[1].Id}||`] = 1,
				[key("Clean", "Diamond", "Flawless")] = 1,
				[key("Clean", "Sunstone", "Pristine")] = 4,
				[key("Clean", "Silver", "Clean")] = 11,
				[key("Clean", "Copper", "Rough")] = 15,
			},
		},
	}
	local full = {
		Backpacks = {
			Equipped = "RookiePack",
			Count = 5,
			Capacity = 5,
			Items = { [key("Raw", "Copper")] = 3, [key("Clean", "Tin", "Clean")] = 2 },
		},
	}
	local empty = { Backpacks = { Equipped = "TrailPack", Count = 0, Capacity = 15, Items = {} } }

	-- `renderScale` px per design unit, `uiScale` the game's scale (0.62 phones), `screen` in pt
	local function shot(
		renderScale: number,
		uiScale: number,
		screen: Vector2,
		compact: boolean,
		state: any,
		hint: string,
		pad: boolean?
	): { any }
		local hud = HudBubble.buildGame(uiScale, screen.X)
		hud.Gui.Scale.Scale = renderScale
		hud.Coins.Text = Format.money(4.82e6)
		hud.Income.Text = Format.perSecond(1840)
		hud.Toasts:ClearAllChildren()
		local backpack = BackpackState.read(state)
		HudBubble.setBackpack(hud.Backpack, backpack.Count, backpack.Capacity)
		HudBubble.setBackpackKey(hud.Backpack, if pad then "RB" elseif compact then nil else "Q", nil)
		local view = BackpackView.build()
		view.Gui.Scale.Scale = renderScale
		BackpackView.layout(view, screen.X / uiScale, screen.Y / uiScale, compact)
		BackpackView.setBackpack(view, backpack)
		BackpackView.setHint(view, hint)
		view.Gui.Enabled = true
		return { hud.Gui, view.Gui }
	end

	local exports: { [string]: any } = {}
	local pc = roblox.Vector2.new(1600 / 1.25, (900 - 36) / 1.25)
	exports.ui_backpack_pc = UiExport.export(shot(1.25, 1.25, pc, false, midGame, "Q or Backspace: close"))
	exports.ui_backpack_full = UiExport.export(shot(1.25, 1.25, pc, false, full, "Q or Backspace: close"))
	exports.ui_backpack_empty = UiExport.export(shot(1.25, 1.25, pc, false, empty, "Q or Backspace: close"))
	exports.ui_backpack_phone =
		UiExport.export(shot(0.62 * 900 / 375, 0.62, roblox.Vector2.new(667, 375 - 58 * 375 / 900), true, midGame, "Tap X to close."))
	local tvScale = 1.25 * 900 / 1080
	exports.ui_backpack_tv =
		UiExport.export(shot(tvScale, 1.25, roblox.Vector2.new(1920 / 1.25, (1080 - 36) / 1.25), true, midGame, "B: close", true))
	return exports
end

return Preview
