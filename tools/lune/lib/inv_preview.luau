--[[
	The inventory windows alone over an empty sky (scene "inv_quick" for
	tools/lune/export_scene.luau: fast UI iteration, no WorldBuilder; shots
	in tools/preview/inv_shots.json). Drawn with the game's own code
	(GolemView, PenView, CollectionView). UI overlays:
	  ui_inv_golems         PC: MY GOLEMS, the first golem picked
	  ui_inv_golems_delete  PC: delete mode, three golems picked
	  ui_inv_golems_phone   667 x 375 pt phone at the 0.62 floor
	  ui_inv_pen            PC: the ORE PEN with its send toolbar
	  ui_inv_pen_phone      phone
	  ui_inv_book           PC: the artifact book
	  ui_inv_book_phone     phone
]]

local UiExport = require("./uiexport")
local CapsulePreview = require("./capsule_preview")
local BeltsPreview = require("./belts_preview")
local WheelPreview = require("./wheel_artifacts_preview")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local GolemView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemView")
	local PenView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.PenView")
	local CollectionView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CollectionView")
	local roblox = require("@lune/roblox") :: any

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phone = 0.62 * 900 / 375 -- a 667 x 375 pt phone at the 0.62 floor
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	local phW, phH = 1600 / phone, (900 - 58) / phone

	local function golems(uiScale: number, compact: boolean, w: number, h: number, deleting: boolean): any
		local state = CapsulePreview.state(false)
		-- the longest names too (two pixel lines on the cards and in the slot)
		state.Golems.Owned[3].Kind = "HeartstoneColossus"
		state.Golems.Owned[6].Kind = "CelestialSovereign"
		state.Golems.Owned[7].Kind = "ScaleKnight"
		local refs = GolemView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		GolemView.layout(refs, compact, w, h)
		local cards = GolemView.cards(state)
		local picked = if deleting then { [4] = true, [6] = true, [9] = true } else nil
		GolemView.setCards(refs, cards, if deleting then nil else cards[1].Id, picked)
		GolemView.setEquipped(refs, GolemView.equipped(state), GolemView.totals(state))
		GolemView.setCount(refs, GolemView.countText(state), false)
		GolemView.setDetail(refs, cards[1])
		GolemView.setDeleteMode(refs, deleting, if deleting then 3 else 0)
		GolemView.setHint(
			refs,
			if deleting
				then `Click the golems to delete{GolemView.Separator}Backspace: back`
				else `Click a golem to see it{GolemView.Separator}P / Backspace: close`
		)
		return refs
	end

	local function pen(compact: boolean, uiScale: number, inset: number): any
		local refs = PenView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		PenView.setCompact(refs, compact, roblox.Vector2.new(1600 / uiScale, (900 - inset) / uiScale))
		PenView.setMode(refs, "Pen", nil)
		PenView.setAutoSort(refs, true, true)
		local total = 0
		for _, n in BeltsPreview.Pen do
			total += n
		end
		PenView.setHeader(refs, total, 60)
		PenView.setEntries(refs, PenView.entries(BeltsPreview.Pen, "Pen"), true)
		PenView.setSending(refs, { Pen = 3 }, true, 10)
		PenView.setHint(
			refs,
			if compact
				then "TAKE: carry it  -  SEND: onto your belts (twice: all)  -  PODIUM: money every second"
				else "TAKE: to your hands  -  SEND: to your belts (twice: all)  -  PODIUM: money/s  -  Backspace: close",
			nil,
			nil
		)
		local row = refs.Rows["Clean|Amethyst|Pristine|"]
		if row then
			row.Send.Text = PenView.sendButtonText(BeltsPreview.Pen["Clean|Amethyst|Pristine|"])
		end
		return refs
	end

	local function book(uiScale: number, compact: boolean, w: number, h: number, collection: string, selected: string): any
		local refs = CollectionView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		refs.Collection = collection
		refs.Selected = selected
		CollectionView.layout(refs, w, h)
		CollectionView.fill(refs, { Found = WheelPreview.Found, Chapters = {} }, WheelPreview.Wallet)
		refs.Hint.Text = if compact
			then "Tap a collection, then an artifact"
			else "Click a collection, then an artifact  ·  Backspace: close"
		return refs
	end

	local exports: { [string]: any } = {}
	exports.ui_inv_golems = UiExport.export({ golems(scale, false, pcW, pcH, false).Gui })
	exports.ui_inv_golems_delete = UiExport.export({ golems(scale, false, pcW, pcH, true).Gui })
	exports.ui_inv_golems_phone = UiExport.export({ golems(phone, true, phW, phH, false).Gui })
	exports.ui_inv_pen = UiExport.export({ pen(false, scale, 0).Gui })
	exports.ui_inv_pen_phone = UiExport.export({ pen(true, phone, 58).Gui })
	exports.ui_inv_book = UiExport.export({ book(scale, false, pcW, pcH, "RoyalRailway", "RailLantern").Gui })
	exports.ui_inv_book_phone = UiExport.export({ book(phone, true, phW, phH, "HeartstoneLore", "HeartstoneFragment").Gui })
	return exports
end

return Preview
