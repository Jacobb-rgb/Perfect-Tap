--[[
	The side menu, the ORE CODEX, SETTINGS and the leaderboards over the game
	(scene "menus" for tools/lune/export_scene.luau: the world; shots in
	tools/preview/menus_shots.json). Everything is drawn with the game's own
	builders (SideMenuView, CodexView, SettingsView, LeaderboardView,
	HudView, TeleportView, BuildView) from sample data.
	UI overlays (build/preview/<name>.json); the side menu as it ships now
	(all 7 buttons since the golem and artifact packages are in, sorted by
	Group then Order: GOLEMS, SHOP | CODEX, ARTIFACTS, BOARDS, SETTINGS, STORE):
	  ui_menu_hud        PC: the HUD with the side menu (CODEX badge, STORE's
	                     SOON chip)
	  ui_menu_hud_full   PC: the same with the ARTIFACTS badge (a chapter to read)
	  ui_menu_phone      667 x 375 pt phone: the MENU button alone (its badge
	                     adds up the CODEX count), the screen the game's
	  ui_menu_phone_open 667 x 375 pt phone: MENU tapped, the grid open (the
	                     thumbstick's corner free)
	  ui_menu_phone_small 568 x 320 pt phone, the grid open
	  ui_menu_column_pc / _phone / _phone_open / _small / _small_open
	                     the whole left column as it ships: coins, the TRAIN
	                     chip, two running boost chips and the side menu (PC:
	                     the column under the chips; phones: MENU first in the
	                     train chip's row; open: the grid over the chips)
	  ui_codex           PC: the codex, 14 of 30 found, Ruby selected (NEW)
	  ui_codex_hidden    PC: an undiscovered ore selected
	  ui_codex_phone     667 x 375 pt phone (compact)
	  ui_settings        PC with a gamepad connected: SETTINGS (Sounds,
	                     Camera shake, Gamepad rumble; Music shows once a
	                     soundtrack plays)
	  ui_settings_phone  667 x 375 pt phone (no gamepad: Sounds, Camera shake)
	  ui_boards          PC: HALL OF FAME panel, TOTAL EARNED tab
	  ui_boards_phone    667 x 375 pt phone, MONEY/S tab
	  ui_board_closeup   the four lobby boards as the SurfaceGuis draw them
	                     (navy board, the hall's title strip, 5 rows, YOUR line;
	                     ARTIFACTS: "~#6", your live value already ranks there)
	  ui_board_studio    one board in Studio without DataStores
	(the 3D renderer draws one text per SurfaceGui, so the lobby boards are
	shown as a close-up overlay)
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

Preview.Discovered = {
	"Coal",
	"Copper",
	"Tin",
	"Iron",
	"Quartz",
	"Silver",
	"Amethyst",
	"Jade",
	"Emberite",
	"Cobalt",
	"Gold",
	"Ruby",
	"Azurium",
	"Sapphire",
}
Preview.Fresh = { Ruby = true, Sapphire = true }
Preview.Me = 9001

local NAMES = {
	"EmberQueen",
	"RockyMiner77",
	"Forgekeeper_Ola",
	"CrystalKid",
	"DeepHollowDan",
	"Pickaxe_Pat",
	"You_TerraFan",
	"GolemWhisperer",
	"SparkyStone",
	"QuarryQuinn",
}

-- A sample Leaderboards payload: 10 rows per board, you at rank 7 on TOTAL EARNED,
-- "~#6" on ARTIFACTS (your live value passed #6 there), "#11+" on the other two.
function Preview.payload(): any
	local boards = {}
	local bases = { MoneyPerSec = 4.2e9, TotalEarned = 8.2e15, Artifacts = 412, HoursPlayed = 380 * 3600 }
	for id, base in bases do
		local rows = {}
		for i, name in NAMES do
			local value = if id == "Artifacts" or id == "HoursPlayed" then math.floor(base / (1 + (i - 1) * 0.35)) else base / 3.1 ^ (i - 1)
			-- you are #7 on TOTAL EARNED (the rank the server sends); elsewhere you aren't in the rows
			local mine = i == 7 and id == "TotalEarned"
			table.insert(rows, { Rank = i, UserId = if mine then Preview.Me else 1000 + i, Name = name, Value = value })
		end
		boards[id] = { Rows = rows, Ready = true }
	end
	return {
		Live = true,
		Boards = boards,
		Own = {
			MoneyPerSec = { Value = 1840 },
			TotalEarned = { Value = boards.TotalEarned.Rows[7].Value, Rank = 7 },
			-- not in the rows read yet, but worth more than #6 there: "~#6"
			Artifacts = { Value = 150 },
			HoursPlayed = { Value = 12.5 * 3600 },
		},
	}
end

function Preview.build(Loader: any): { [string]: any }
	local C3 = roblox.Color3
	local UDim2 = roblox.UDim2
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
	local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local UIKit = Loader.requirePath(UI .. "UIKit")
	local HudView = Loader.requirePath(UI .. "HudView")
	local TeleportView = Loader.requirePath(UI .. "TeleportView")
	local BuildView = Loader.requirePath(UI .. "BuildView")
	local MenuPanel = Loader.requirePath(UI .. "MenuPanel")
	local SideMenuView = Loader.requirePath(UI .. "SideMenuView")
	local CodexView = Loader.requirePath(UI .. "CodexView")
	local SettingsView = Loader.requirePath(UI .. "SettingsView")
	local LeaderboardView = Loader.requirePath(UI .. "LeaderboardView")

	local PC = 1.25 -- 900 px tall render / 720 design height
	local PHONE = MenuPanel.PhoneScale
	-- a 667 x 375 pt phone scaled up to the 1600 x 900 render; its 58 pt top bar
	local phoneScale = PHONE * 900 / 375
	local phoneInset = 58 * 900 / 375
	local smallScale = PHONE * 900 / 320
	local smallInset = 58 * 900 / 320
	local pcW, pcH = 1600 / PC, (900 - 36) / PC

	local discovered = {}
	for _, id in Preview.Discovered do
		discovered[id] = true
	end

	local function hud(renderScale: number, uiScale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = renderScale
		BuildView.menuButton(refs.Menu)
		local teleport = TeleportView.build(refs.TopBar, refs.Menu, uiScale)
		TeleportView.relayout(teleport, refs.TopBar, uiScale)
		refs.Coins.Text = Format.money(4.82e6)
		refs.Income.Text = Format.perSecond(1840)
		refs.Income.TextColor3 = Theme.Good
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		return refs
	end

	-- the side menu (all 7 buttons); `full` = the ARTIFACTS badge too,
	-- `open` = the touch layout's grid opened with MENU
	local function menu(renderScale: number, uiScale: number, designH: number, full: boolean?, open: boolean?): any
		local refs = SideMenuView.build()
		refs.Gui.Scale.Scale = renderScale
		if full then
			SideMenuView.setBadge(refs, "Collection", 1) -- a completed chapter waits unread
		end
		local touch = uiScale <= SideMenuView.CompactScale
		refs.Expanded = open == true
		local count = #SideMenuView.shown(refs)
		SideMenuView.apply(refs, SideMenuView.layout(uiScale, designH, { Count = count, Touch = touch, DesignWidth = 1600 / renderScale }))
		SideMenuView.setBadge(refs, "Codex", 2)
		SideMenuView.setSoon(refs, "Store", true)
		return refs
	end

	-- the train chip and two running boost chips under it, placed like
	-- TrainController and BoostController place them
	local BoostView = Loader.requirePath(UI .. "BoostView")
	local TrainView = Loader.requirePath(UI .. "TrainView")
	local NOW = 1.7e9
	local function chips(renderScale: number, compact: boolean, designW: number, designH: number): { any }
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
		BoostView.placeChips(boost, BoostView.chipsTop(train.ChipFrame, compact))
		local state = { Boosts = { TripleLuckyUntil = NOW + 222, HexaLuckyUntil = NOW + 3900 } }
		BoostView.setChips(boost, BoostView.chips(state, NOW), false)
		return { train.Chip, boost.Gui }
	end

	-- the side menu as it ships (STORE hidden until step 8's store) over the whole left column
	local function column(renderScale: number, uiScale: number, designH: number, open: boolean?): { any }
		local touch = uiScale <= SideMenuView.CompactScale
		local designW = 1600 / renderScale
		local refs = SideMenuView.build()
		refs.Gui.Scale.Scale = renderScale
		SideMenuView.setHidden(refs, "Store", true)
		refs.Expanded = open == true
		SideMenuView.apply(refs, SideMenuView.layout(uiScale, designH, { Count = #SideMenuView.shown(refs), Touch = touch, DesignWidth = designW }))
		SideMenuView.setBadge(refs, "Codex", 2)
		local list = { hud(renderScale, uiScale).Gui }
		for _, gui in chips(renderScale, touch, designW, designH) do
			table.insert(list, gui)
		end
		table.insert(list, refs.Gui)
		return list
	end

	local exports: { [string]: any } = {}

	-- the HUD with the side menu
	exports.ui_menu_hud = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH).Gui })
	exports.ui_menu_hud_full = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH, true).Gui })
	local phoneDesignH = (900 - phoneInset) / phoneScale
	exports.ui_menu_phone = UiExport.export({ hud(phoneScale, PHONE).Gui, menu(phoneScale, PHONE, phoneDesignH).Gui })
	exports.ui_menu_phone_open = UiExport.export({ hud(phoneScale, PHONE).Gui, menu(phoneScale, PHONE, phoneDesignH, false, true).Gui })
	local smallDesignH = (900 - smallInset) / smallScale
	exports.ui_menu_phone_small = UiExport.export({ hud(smallScale, PHONE).Gui, menu(smallScale, PHONE, smallDesignH, false, true).Gui })
	exports.ui_menu_column_pc = UiExport.export(column(PC, 1, pcH))
	exports.ui_menu_column_phone = UiExport.export(column(phoneScale, PHONE, phoneDesignH))
	exports.ui_menu_column_phone_open = UiExport.export(column(phoneScale, PHONE, phoneDesignH, true))
	exports.ui_menu_column_small = UiExport.export(column(smallScale, PHONE, smallDesignH))
	exports.ui_menu_column_small_open = UiExport.export(column(smallScale, PHONE, smallDesignH, true))

	-- the codex
	local function codex(renderScale: number, compact: boolean, maxW: number, maxH: number, select: string): any
		local refs = CodexView.build(compact)
		refs.Gui.Scale.Scale = renderScale
		refs.Gui.Enabled = true
		CodexView.layout(refs, compact, maxW, maxH)
		local entries = CodexView.entries(discovered, Preview.Fresh)
		CodexView.setEntries(refs, entries)
		for _, entry in entries do
			if entry.Ore.Id == select then
				CodexView.select(refs, entry)
			end
		end
		MenuPanel.setHint(refs.Frame, "Click an ore to read about it · Backspace: close", nil)
		return refs
	end
	exports.ui_codex = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH).Gui, codex(PC, false, pcW, pcH, "Ruby").Gui })
	exports.ui_codex_hidden = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH).Gui, codex(PC, false, pcW, pcH, "Heartstone").Gui })
	exports.ui_codex_phone = UiExport.export({
		hud(phoneScale, PHONE).Gui,
		menu(phoneScale, PHONE, phoneDesignH).Gui,
		codex(phoneScale, true, 1600 / phoneScale, phoneDesignH, "Sapphire").Gui,
	})

	-- settings
	-- (no soundtrack yet: the Music row is hidden; Gamepad rumble shows with a gamepad)
	local function settings(renderScale: number, compact: boolean, maxW: number, maxH: number, gamepad: boolean): any
		local refs = SettingsView.build(compact)
		refs.Gui.Scale.Scale = renderScale
		refs.Gui.Enabled = true
		SettingsView.setShown(refs, "Music", false)
		SettingsView.setShown(refs, "Rumble", gamepad)
		SettingsView.layout(refs, compact, maxW, maxH)
		SettingsView.set(refs, SettingsConfig.sanitize({ Music = 0.6, Sfx = 0.8, Shake = true, Rumble = false }))
		MenuPanel.setHint(refs.Frame, "Drag a bar or use - and + · Backspace: close", nil)
		return refs
	end
	exports.ui_settings = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH).Gui, settings(PC, false, pcW, pcH, true).Gui })
	exports.ui_settings_phone = UiExport.export({
		hud(phoneScale, PHONE).Gui,
		menu(phoneScale, PHONE, phoneDesignH).Gui,
		settings(phoneScale, true, 1600 / phoneScale, phoneDesignH, false).Gui,
	})

	-- the HALL OF FAME panel
	local payload = LeaderboardView.sanitize(Preview.payload())
	local function boards(renderScale: number, compact: boolean, maxW: number, maxH: number, tab: string): any
		local panel = LeaderboardView.buildPanel(compact)
		panel.Gui.Scale.Scale = renderScale
		panel.Gui.Enabled = true
		LeaderboardView.layoutPanel(panel, compact, maxW, maxH)
		LeaderboardView.setTab(panel, tab)
		for id, canvas in panel.Canvases do
			local lines =
				LeaderboardView.lines(id, payload.Boards[id], payload.Own[id], Preview.Me, LeaderboardConfig.TopCount, payload.Live)
			LeaderboardView.fill(canvas, lines)
		end
		MenuPanel.setHint(panel.Frame, "Click a tab to see a board · Backspace: close", nil)
		return panel
	end
	exports.ui_boards = UiExport.export({ hud(PC, 1).Gui, menu(PC, 1, pcH).Gui, boards(PC, false, pcW, pcH, "TotalEarned").Gui })
	exports.ui_boards_phone = UiExport.export({
		hud(phoneScale, PHONE).Gui,
		menu(phoneScale, PHONE, phoneDesignH).Gui,
		boards(phoneScale, true, 1600 / phoneScale, phoneDesignH, "MoneyPerSec").Gui,
	})

	-- the lobby boards as their SurfaceGuis draw them (270 x 250 px each at 50 px / stud)
	local function closeup(live: boolean, only: number?): any
		local gui = UIKit.screen("BoardCloseup", 1)
		gui.Scale.Scale = 1
		local dim = UIKit.new("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C3.fromRGB(12, 10, 16),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, gui)
		local k = 1.45 -- close-up zoom
		local w, h = 270 * k, 250 * k
		for _, board in LeaderboardConfig.Boards do
			if only == nil or only == board.Index then
				local col = (board.Index - 1) % 2
				local row = (board.Index - 1) // 2
				local x = if only then 800 - w / 2 else 800 + (if col == 0 then -w - 24 else 24)
				local y = if only then 450 - h / 2 else 60 + row * (h + 36)
				-- the light bezel and the navy board
				local bezel = UIKit.new("Frame", {
					Name = "Bezel" .. board.Index,
					Position = UDim2.fromOffset(x - 12, y - 12),
					Size = UDim2.fromOffset(w + 24, h + 24),
					BackgroundColor3 = C3.fromRGB(196, 202, 214),
					BorderSizePixel = 0,
				}, dim)
				UIKit.corner(bezel, 6)
				local face = UIKit.new("Frame", {
					Name = "Board" .. board.Index,
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.fromOffset(w, h),
					BackgroundColor3 = LeaderboardView.Board,
					BorderSizePixel = 0,
				}, bezel)
				local canvas = LeaderboardView.canvas(face, board, LeaderboardConfig.BoardRows, true, math.floor(20 * k), w)
				local data = if live
					then payload.Boards[board.Id]
					else { Rows = { { Rank = 1, UserId = -1, Name = "Player1", Value = payload.Own[board.Id].Value } }, Ready = true }
				local own = if live then payload.Own[board.Id] else { Value = payload.Own[board.Id].Value, Rank = 1 }
				LeaderboardView.fill(
					canvas,
					LeaderboardView.lines(board.Id, data, own, if live then Preview.Me else -1, LeaderboardConfig.BoardRows, live)
				)
				-- the hall's own title strip in front of the board's top
				local strip = UIKit.new("Frame", {
					Name = "TitleStrip",
					Position = UDim2.new(0, 4, 0, 0),
					Size = UDim2.new(1, -8, 0.19, 0),
					BackgroundColor3 = C3.fromRGB(22, 28, 52),
					BorderSizePixel = 0,
					ZIndex = 5,
				}, face)
				UIKit.label(strip, board.Title, math.floor(26 * k), {
					Name = "Title",
					Size = UDim2.fromScale(1, 1),
					FontFace = Theme.TitleFont,
					TextColor3 = C3.new(1, 1, 1),
					TextWrapped = false,
					ZIndex = 6,
				})
			end
		end
		return gui
	end
	exports.ui_board_closeup = UiExport.export({ closeup(true, nil) })
	exports.ui_board_studio = UiExport.export({ closeup(false, 2) })
	return exports
end

return Preview
