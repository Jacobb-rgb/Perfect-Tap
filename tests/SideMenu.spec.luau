-- The side menu and its panels under Lune: SideMenuView's column layout
-- (mouse: below the coins, centred; touch: one MENU button that opens a
-- grid of up to four columns right under the coins, the thumbstick's
-- bottom-left corner free on phones and tablets; TVs: the title-safe
-- margin; 44 pt touch targets), its badges (added up on MENU), SOON chips
-- inside their buttons, hidden buttons and grid cells; the ORE CODEX
-- (entries from the save's Discovered record, NEW badges, the count, where
-- an ore is found, sell values, undiscovered ores keep their secrets, the
-- redraw fingerprint, the phone layout, CodexService's saved seen record,
-- one prompt on the terminal's cabinet); SETTINGS (SettingsConfig.sanitize
-- / steps / merge, SettingsService saving only sane records with
-- DataService.changed, SettingsView's slider math, texts, hidden rows and
-- touch sizes) and the shared MenuPanel frame (the teleport bar and coins
-- kept clear, the gamepad footer on compact layouts).
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local SettingsService = Loader.requirePath("ServerScriptService.Server.Services.SettingsService")
	local CodexService = Loader.requirePath("ServerScriptService.Server.Services.CodexService")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local CodexView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CodexView")
	local SettingsView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SettingsView")

	local PHONE = MenuPanel.PhoneScale
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	-- every target at least 44 pt at `scale`
	local function checkTouch(targets: { any }, scale: number, label: string)
		for _, target in targets do
			local size = target.Size
			T.truthy(size.X.Offset * scale >= MenuPanel.MinTouch - 0.5, `{label} {target.Name} wide enough ({size.X.Offset})`)
			T.truthy(size.Y.Offset * scale >= MenuPanel.MinTouch - 0.5, `{label} {target.Name} tall enough ({size.Y.Offset})`)
		end
	end

	---------------------------------------------------------------- side menu

	T.test("side menu: on a PC the column starts under the train and boost chips, inside the screen", function()
		local layout = SideMenuView.layout(1, 720 - 36)
		T.falsy(layout.Touch)
		T.eq(layout.Left, SideMenuView.Left)
		T.truthy(layout.Top >= SideMenuView.TopMin, "below the train chip and the boost chips")
		T.le(layout.Top + SideMenuView.Drop + layout.Size.Y, 720 - 36 - SideMenuView.BottomMargin)
		-- (eleven buttons since QUESTS: the dark fallback column may take a third column)
		T.truthy(layout.Columns >= 2 and layout.Columns <= 3, "a 720p window: two or three columns under the chips")
		-- a 1080p screen (HUD scale 1.25): one column
		local hd = SideMenuView.layout(1.25, (1080 - 36) / 1.25, { Count = 6 })
		T.eq(hd.Columns, 1)
		T.eq(hd.Rows, 6)
		-- a big screen centres it (nine buttons: a tall one)
		local tall = SideMenuView.layout(1, 1400)
		T.eq(tall.Columns, 1)
		T.near(tall.Top + tall.Size.Y / 2, 700, 1, "centred")
	end)

	-- The column's box on the screen (design units under the top bar), from
	-- the placed buttons.
	local function columnBox(refs: any): (number, number, number, number)
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		local origin = refs.Column.Position
		for _, target in SideMenuView.touchTargets(refs) do
			local x = origin.X.Offset + target.Position.X.Offset
			local y = origin.Y.Offset + target.Position.Y.Offset
			x0, y0 = math.min(x0, x), math.min(y0, y)
			x1, y1 = math.max(x1, x + target.Size.X.Offset), math.max(y1, y + target.Size.Y.Offset)
		end
		return x0, y0, x1, y1
	end

	-- { width, height, uiScale } in pt: phones in landscape under a 58 pt top
	-- bar (uiScale at the 0.62 floor) and tablets (HudController.uiScale)
	local TOUCH_SCREENS = {
		{ 568, 320, PHONE },
		{ 640, 360, PHONE },
		{ 667, 375, PHONE },
		{ 844, 390, PHONE },
		{ 932, 430, PHONE },
		{ 1024, 768, math.min(768 / 720, 1024 / 1100) },
		{ 1180, 820, math.min(820 / 720, 1180 / 1100) },
	}

	T.test("side menu: touch screens keep the thumbstick's bottom-left corner free", function()
		local refs = SideMenuView.build()
		-- the open grid (MENU + the buttons) is the biggest the menu gets
		SideMenuView.setExpanded(refs, true)
		for _, count in { 11, 10, 8 } do
			for i, id in refs.Order do
				-- 11: every button; 10: STORE hidden (step 8 isn't in the game: today's menu);
				-- 8: GOLEMS and ARTIFACTS hidden too (their packages not in the game)
				local hide = (count <= 10 and id == "Store") or (count <= 8 and (id == "Golems" or id == "Collection"))
				SideMenuView.setHidden(refs, id, hide)
				T.eq(refs.Buttons[id].Parent.Visible, not refs.Hidden[id], `{id} visibility ({i})`)
			end
			T.eq(#SideMenuView.shown(refs), count)
			for _, screen in TOUCH_SCREENS do
				local w, h, scale = screen[1], screen[2], screen[3]
				local label = `{w}x{h} pt, {count} buttons`
				-- every button at once (STORE too) on the smallest phone: ten buttons and MENU fit
				-- no grid at 44 pt there. STORE is hidden until step 8 (today's menu: nine), so
				-- that phone gets the nine; when STORE lands, it needs a decision (docs/QA_REPORTS.md)
				-- (QUESTS made it eleven: the dark fallback grid fits them all from 667 pt on;
				-- the shipping light UI puts QUESTS in its MORE flyout)
				if (count == 11 and w <= 640) or (count == 10 and w <= 568) then
					continue
				end
				local designW, designH = w / scale, (h - 58) / scale
				local layout = SideMenuView.layout(scale, designH, { Count = count, Touch = true, DesignWidth = designW })
				T.truthy(layout.Touch, label)
				T.truthy(layout.Toggle, label .. ": the MENU button")
				SideMenuView.apply(refs, layout)
				T.eq(#SideMenuView.touchTargets(refs), count + 1, label .. ": MENU and the buttons")
				checkTouch(SideMenuView.touchTargets(refs), scale, label)
				local x0, y0, x1, y1 = columnBox(refs)
				-- the thumb's resting corner: the left 40 % x the bottom 40 %
				local apart = x0 >= designW * 0.4 or y1 <= designH * 0.6
				T.truthy(apart, `{label}: the bottom-left 40 % x 40 % is free (bottom at {math.floor(y1 / designH * 100)} %)`)
				T.truthy(y0 >= SideMenuView.TopTight, `{label}: below the coins panel`)
				T.le(x1, designW - SideMenuView.RightReserve, `{label}: never the HUD's right-side menu`)
				if layout.Rows > 1 then
					T.lt(x1, designW * 0.45, `{label}: the rest of the width is the game's`)
				end
			end
		end
		-- MENU sits first in the train chip's row (the chip starts right of it on touch layouts)
		local phone = SideMenuView.layout(PHONE, (375 - 58) / PHONE, { Touch = true })
		local train = SideMenuView.trainRect(true)
		T.le(phone.Left + phone.Width, train.X - 8, "MENU left of the train chip")
		T.truthy(phone.Top + SideMenuView.Drop >= train.Y, "in the train chip's row")
		T.le(phone.Top + SideMenuView.Drop + phone.Height, train.Y + train.H)
		-- a small window (phone-sized buttons) uses the touch layout even without touch
		T.truthy(SideMenuView.layout(PHONE, (375 - 58) / PHONE).Touch)
	end)

	T.test("side menu: on touch screens one MENU button opens and shuts the grid", function()
		local refs = SideMenuView.build()
		-- five buttons: SHOP, CODEX, BOARDS, SETTINGS, STORE
		for _, id in { "Golems", "Collection", "Elevator", "Hoverboards", "Rebirth", "Quests" } do
			SideMenuView.setHidden(refs, id, true)
		end
		local designW, designH = 667 / PHONE, (375 - 58) / PHONE
		local layout = SideMenuView.layout(PHONE, designH, { Count = 5, Touch = true, DesignWidth = designW })
		SideMenuView.apply(refs, layout)
		-- shut: MENU alone, a small corner of the screen
		local targets = SideMenuView.touchTargets(refs)
		T.eq(#targets, 1)
		T.eq(targets[1], refs.Toggle.Parent)
		T.truthy(refs.Toggle.Parent.Visible)
		for _, id in refs.Order do
			T.falsy(refs.Buttons[id].Parent.Visible, id .. " hidden while shut")
		end
		checkTouch(targets, PHONE, "MENU")
		local _, _, x1, y1 = columnBox(refs)
		T.lt(x1, designW * 0.15, "MENU takes under 15 % of the width")
		T.le(y1, designH * 0.6)
		T.eq(refs.ToggleLabel.Text, "MENU")
		T.truthy(refs.ToggleBars.Visible)
		T.falsy(refs.ToggleX.Visible)
		-- the badges add up on MENU while it is shut
		SideMenuView.setBadge(refs, "Codex", 2)
		T.truthy(refs.ToggleBadge.Visible)
		T.eq(refs.ToggleBadge.Text, "2")
		SideMenuView.setBadge(refs, "Golems", 5) -- hidden: not counted
		T.eq(refs.ToggleBadge.Text, "2")
		-- open: MENU first, then the buttons; MENU reads CLOSE
		SideMenuView.setExpanded(refs, true)
		T.eq(#SideMenuView.touchTargets(refs), 6)
		T.eq(refs.ToggleLabel.Text, "CLOSE")
		T.truthy(refs.ToggleX.Visible)
		T.falsy(refs.ToggleBadge.Visible, "the buttons show their own badges")
		T.truthy(refs.Badges.Codex.Visible)
		T.eq(SideMenuView.cellOf(refs, refs.Toggle), 0)
		T.eq(SideMenuView.cellOf(refs, refs.Buttons.Shop), 1)
		T.eq(SideMenuView.cellOf(refs, refs.Buttons.Store.Parent), 5)
		T.eq(SideMenuView.cellOf(refs, refs.Buttons.Golems), nil, "a hidden button has no cell")
		T.eq(layout.Columns, 3, "MENU + 5 buttons: 3 x 2")
		-- shut again: the badge comes back on MENU
		SideMenuView.setExpanded(refs, false)
		T.truthy(refs.ToggleBadge.Visible)
		T.falsy(refs.Buttons.Shop.Parent.Visible)
		-- a mouse layout has no MENU button: every button shows, SHOP in the first cell
		SideMenuView.apply(refs, SideMenuView.layout(1, 684, { Count = 5 }))
		T.falsy(refs.Toggle.Parent.Visible)
		T.truthy(refs.Buttons.Shop.Parent.Visible)
		T.eq(SideMenuView.cellOf(refs, refs.Buttons.Shop), 0)
		T.eq(SideMenuView.cellOf(refs, refs.Toggle), nil)
		T.eq(#SideMenuView.touchTargets(refs), 5)
		-- the SOON chip sits inside its own button's top-right corner
		SideMenuView.setSoon(refs, "Store", true)
		local soon = refs.Soon.Store
		T.eq(soon.Parent, refs.Buttons.Store)
		T.truthy(soon.Visible)
		T.eq(soon.AnchorPoint.X, 1)
		T.eq(soon.Position.X.Scale, 1)
		T.le(soon.Position.X.Offset, 0, "inside the right edge")
		T.truthy(soon.Position.Y.Offset >= 0, "inside the top edge")
		T.le(soon.Size.X.Offset, SideMenuView.Normal.Width / 2, "a corner tag, not a bridge")
	end)

	-- Do two design-unit boxes overlap?
	local function overlaps(a: any, b: any): boolean
		return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
	end

	-- The side menu's shown targets as screen boxes (design units).
	local function targetRects(refs: any): { any }
		local list = {}
		local origin = refs.Column.Position
		for _, target in SideMenuView.touchTargets(refs) do
			table.insert(list, {
				Name = target.Name,
				X = origin.X.Offset + target.Position.X.Offset,
				Y = origin.Y.Offset + target.Position.Y.Offset,
				W = target.Size.X.Offset,
				H = target.Size.Y.Offset,
			})
		end
		return list
	end

	T.test("side menu: one owner for the left column (coins, train chip, boost chips, menu never overlap)", function()
		local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
		local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
		local coins = { X = 16, Y = 16, W = HudView.CoinsWidth, H = 74 }
		-- { label, width pt, height pt, uiScale, touch, top inset pt }
		local screens = {
			{ "PC 1600x900", 1600, 900, 1.25, false, 36 },
			{ "PC 1280x720", 1280, 720, 1, false, 36 },
			{ "phone 667x375", 667, 375, PHONE, true, 58 },
			{ "phone 568x320", 568, 320, PHONE, true, 58 },
		}
		for _, screen in screens do
			local label, w, h, scale, touch, inset = screen[1], screen[2], screen[3], screen[4], screen[5], screen[6]
			local designW, designH = w / scale, (h - inset) / scale
			-- the train chip where TrainController puts it (compact = touch here)
			local train = TrainView.build(touch)
			TrainView.layout(train, touch, designW, designH)
			local frame = train.ChipFrame
			local trainRect = { X = frame.Position.X.Offset, Y = frame.Position.Y.Offset, W = frame.Size.X.Offset, H = frame.Size.Y.Offset }
			local expected = SideMenuView.trainRect(touch)
			T.eq(trainRect.X, expected.X, label .. ": train chip x")
			T.eq(trainRect.W, expected.W, label .. ": train chip width")
			-- the boost chips' row under it (BoostController: chipsTop of the real frame), at its widest
			local chips =
				{ X = BoostView.ChipLeft, Y = BoostView.chipsTop(frame, touch), W = BoostView.chipsWidth(), H = BoostView.ChipHit }
			T.eq(chips.Y, SideMenuView.chipsRect(touch).Y, label .. ": chips where the side menu expects them")
			T.falsy(overlaps(trainRect, chips), label .. ": train chip and boost chips")
			T.falsy(overlaps(coins, trainRect), label .. ": coins and train chip")
			local refs = SideMenuView.build()
			SideMenuView.setHidden(refs, "Store", true)
			local count = #SideMenuView.shown(refs)
			local layout = SideMenuView.layout(scale, designH, { Count = count, Touch = touch, DesignWidth = designW })
			SideMenuView.apply(refs, layout)
			-- shut (touch: MENU alone; mouse: every button): nothing overlaps
			for _, rect in targetRects(refs) do
				T.falsy(overlaps(rect, trainRect), `{label}: {rect.Name} clear of the train chip`)
				T.falsy(overlaps(rect, chips), `{label}: {rect.Name} clear of the boost chips`)
				T.falsy(overlaps(rect, coins), `{label}: {rect.Name} clear of the coins`)
				T.le(rect.Y + rect.H, designH, `{label}: {rect.Name} on the screen`)
			end
			T.eq(refs.Gui.DisplayOrder, SideMenuView.Order)
			if touch then
				-- open: the grid takes the chips' place, so the chips it would cover hide
				-- (never a half-covered TRAIN chip with its SEND peeking out)
				SideMenuView.setExpanded(refs, true)
				local coversTrain, coversChips = false, false
				for _, rect in targetRects(refs) do
					coversTrain = coversTrain or overlaps(rect, trainRect)
					coversChips = coversChips or overlaps(rect, chips)
					T.falsy(overlaps(rect, coins), `{label}: open {rect.Name} clear of the coins`)
				end
				T.truthy(coversTrain, label .. ": the open grid opens in the train chip's row")
				T.falsy(TrainView.chipVisible(true, false, true), label .. ": the train chip hides under the open grid")
				T.truthy(not coversChips or not BoostView.chipsVisible(true, false, true), label .. ": the boost chips hide under it")
				T.truthy(refs.Gui.DisplayOrder > train.Chip.DisplayOrder, label .. ": the open grid above the HUD")
				SideMenuView.setExpanded(refs, false)
				T.eq(refs.Gui.DisplayOrder, SideMenuView.Order, label .. ": under the HUD again once shut")
				T.truthy(TrainView.chipVisible(true, false, false), label .. ": the train chip back once shut")
				T.truthy(BoostView.chipsVisible(true, false, false), label .. ": the boost chips back once shut")
			end
		end
	end)

	T.test("side menu: the open touch grid hides the TRAIN chip and the boost chips (MenuPanels.gridOpen)", function()
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		local seen: { boolean } = {}
		MenuPanels.onGridChanged(function(on: boolean)
			table.insert(seen, on)
		end)
		T.falsy(MenuPanels.gridOpen(), "shut at start")
		MenuPanels.setGridOpen(true)
		MenuPanels.setGridOpen(true) -- no change: no second call
		T.truthy(MenuPanels.gridOpen())
		MenuPanels.setGridOpen(false)
		T.falsy(MenuPanels.gridOpen())
		T.eq(#seen, 2)
		T.eq(seen[1], true)
		T.eq(seen[2], false)
		-- the controllers wire it (they need a LocalPlayer, so they are read as text)
		local fs = require("@lune/fs")
		local menu = fs.readFile("src/client/Controllers/SideMenuController.luau")
		T.truthy(menu:find("MenuPanels.setGridOpen(view.Expanded == true)", 1, true), "setExpanded tells MenuPanels")
		local train = fs.readFile("src/client/Controllers/TrainController.luau")
		T.truthy(train:find("TrainView.chipVisible(hudShown, panelOpen, MenuPanels.gridOpen())", 1, true), "the train chip reads it")
		T.truthy(train:find("MenuPanels.onGridChanged", 1, true), "and follows it")
		local boost = fs.readFile("src/client/Controllers/BoostController.luau")
		T.truthy(boost:find("BoostView.chipsVisible(hudShown(), panelOpen(), MenuPanels.gridOpen())", 1, true), "the boost chips read it")
		T.truthy(boost:find("MenuPanels.onGridChanged", 1, true), "and follow it")
	end)

	T.test("side menu: STORE stays hidden until its controller is in the game (no dead button)", function()
		-- (the controller needs a LocalPlayer, so its Actions table is read as text)
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/Controllers/SideMenuController.luau")
		local store = string.match(source, "\n\tStore = (%b{})")
		T.truthy(store, "the STORE action")
		T.truthy(string.find(store :: string, "Hide = true", 1, true), "STORE is hidden while StoreController is missing")
		for line in string.gmatch(source, "\n\t(%w+ = %b{})") do
			if string.find(line, "Soon = true", 1, true) then
				T.truthy(string.find(line, "Hide = true", 1, true), line .. ": no SOON-only dead button")
			end
		end
	end)

	T.test("side menu: ELEVATOR (a teleport, hidden without a stop) and HOVER (the hoverboards panel)", function()
		local byId: { [string]: any } = {}
		for _, entry in SideMenuView.Entries do
			byId[entry.Id] = entry
		end
		local elevator, hover = byId.Elevator, byId.Hoverboards
		T.truthy(elevator and hover, "both entries")
		T.truthy(elevator.Group == "Main" and elevator.Order == 3 and elevator.Label == "ELEVATOR", "ELEVATOR: Main 3")
		T.truthy(hover.Group == "More" and hover.Order == 6 and hover.Label == "HOVER", "HOVER: More 6 (BOARDS is the leaderboards)")
		T.eq(elevator.IconName, "Elevator")
		T.eq(hover.IconName, "Hoverboards")
		-- the controllers need a LocalPlayer, so their sources are read as text
		local fs = require("@lune/fs")
		local menu = fs.readFile("src/client/Controllers/SideMenuController.luau")
		for id, controller in { Elevator = "ElevatorController", Hoverboards = "HoverboardController" } do
			local action = string.match(menu, "\n\t" .. id .. " = (%b{})")
			T.truthy(action, id .. " action")
			T.truthy(string.find(action :: string, `Controller = "{controller}"`, 1, true), id .. " opens " .. controller)
			T.truthy(string.find(action :: string, "Hide = true", 1, true), id .. " hides while its controller is missing")
		end
		T.truthy(string.find(menu, "unavailable(controller)", 1, true), "updateSoon also hides an unavailable feature")
		T.truthy(string.find(menu, "function SideMenuController.refresh()", 1, true), "refresh for available() changes")
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		T.truthy(table.find(MenuPanels.Names, "ElevatorController"), "the floor picker is a panel (one at a time, build mode closes it)")
		T.truthy(table.find(MenuPanels.Names, "HoverboardController"), "the hoverboards panel too")
		local elevatorSource = fs.readFile("src/client/Controllers/ElevatorController.luau")
		for _, fn in { "open", "toggle", "isOpen", "close", "available", "openAt" } do
			T.truthy(string.find(elevatorSource, `function ElevatorController.{fn}(`, 1, true), "ElevatorController." .. fn)
		end
		T.truthy(string.find(elevatorSource, 'TeleportController.request("Elevator")', 1, true), "ELEVATOR teleports to the stop")
		T.truthy(string.find(elevatorSource, "SideMenuController.refresh", 1, true), "the stop's attribute refreshes the menu")
		T.truthy(string.find(elevatorSource, 'MenuPanels.closeOthers("ElevatorController")', 1, true), "the picker closes the other panels")
		T.falsy(string.find(elevatorSource, "DPadLeft", 1, true), "D-pad Left is the side menu's")
		local hoverSource = fs.readFile("src/client/Controllers/HoverboardController.luau")
		for _, fn in { "open", "toggle", "isOpen", "close" } do
			T.truthy(string.find(hoverSource, `function HoverboardController.{fn}(`, 1, true), "HoverboardController." .. fn)
		end
		T.truthy(string.find(hoverSource, 'MenuPanels.closeOthers("HoverboardController")', 1, true), "HOVER closes the other panels")
		-- one left column: nothing else builds a ScreenGui of the side menu's name
		local ElevatorView = fs.readFile("src/client/UI/ElevatorView.luau")
		T.falsy(string.find(ElevatorView, "TerraForgeSideMenu", 1, true), "no second left stack")
		T.falsy(string.find(fs.readFile("src/client/UI/HoverboardView.luau"), "sideButton", 1, true), "no own HOVER button")
		-- the RIDE key: free on a gamepad (the D-pad's four directions are taken)
		T.truthy(string.find(hoverSource, "GamepadKey = Enum.KeyCode.ButtonL2", 1, true), "RIDE on L2")
		local boost = fs.readFile("src/client/Controllers/BoostController.luau")
		T.falsy(string.find(boost, "ButtonL2", 1, true), "the boosts don't use L2")
	end)

	T.test("side menu: TVs read from the couch (labels and SOON chips at least 18 px)", function()
		local scale = 1.25
		local designW, designH = 1920 / scale, (1080 - 36) / scale
		local refs = SideMenuView.build()
		SideMenuView.apply(refs, SideMenuView.layout(scale, designH, { TenFoot = true, DesignWidth = designW }))
		for id, button in refs.Buttons do
			local text = button:FindFirstChild("Label") :: any
			T.truthy(text.TextSize * scale >= 18, `{id} label {text.TextSize * scale} px`)
			T.truthy(refs.Soon[id].TextSize * scale >= 18, `{id} SOON chip {refs.Soon[id].TextSize * scale} px`)
			T.le(refs.Soon[id].Size.X.Offset, (button.Parent :: any).Size.X.Offset * 0.6, id .. ": SOON still a corner tag")
		end
		-- a PC keeps the normal sizes
		SideMenuView.apply(refs, SideMenuView.layout(1, 684))
		T.eq((refs.Buttons.Shop:FindFirstChild("Label") :: any).TextSize, SideMenuView.LabelText)
		T.eq(refs.Soon.Shop.TextSize, SideMenuView.SoonText)
	end)

	T.test("side menu: TVs keep the title-safe margin", function()
		local scale = 1.25
		local designW, designH = 1920 / scale, (1080 - 36) / scale
		local layout = SideMenuView.layout(scale, designH, { TenFoot = true, DesignWidth = designW })
		T.truthy(layout.Left >= designW * SideMenuView.SafeShare, "5 % from the left edge")
		T.le(layout.Top + SideMenuView.Drop + layout.Size.Y, designH * (1 - SideMenuView.SafeShare) + 0.01)
		-- a PC keeps the normal margin
		T.eq(SideMenuView.layout(1, 684, { DesignWidth = 1280 }).Left, SideMenuView.Left)
	end)

	T.test("side menu: entries are data (Group, Order, IconName) shown by Group then Order", function()
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		local ids: { [string]: boolean } = {}
		local places: { [string]: boolean } = {}
		local mains: { string } = {}
		for _, entry in SideMenuView.Entries do
			T.falsy(ids[entry.Id], entry.Id .. " once")
			ids[entry.Id] = true
			T.truthy(entry.Group == "Main" or entry.Group == "More", entry.Id .. " group")
			T.truthy(type(entry.Order) == "number" and entry.Order == math.floor(entry.Order), entry.Id .. " order")
			local place = `{entry.Group}:{entry.Order}`
			T.falsy(places[place], place .. " is one entry's")
			places[place] = true
			T.truthy(HudBubble.EntryLooks[entry.IconName], entry.Id .. " has a light-HUD icon through HudBubble.EntryLooks")
			if entry.Group == "Main" then
				table.insert(mains, entry.Id)
			end
		end
		table.sort(mains)
		T.eq(table.concat(mains, ","), "Elevator,Golems,Shop", "GOLEMS, ELEVATOR and SHOP are the main tiles")
		local order = {}
		for _, entry in SideMenuView.sorted() do
			table.insert(order, entry.Id)
		end
		T.eq(table.concat(order, ","), "Golems,Elevator,Shop,Quests,Codex,Collection,Boards,Settings,Store,Hoverboards,Rebirth")
		local refs = SideMenuView.build()
		T.eq(table.concat(refs.Order, ","), table.concat(order, ","), "the buttons follow the sorted entries")
		T.eq(refs.Buttons.Golems:GetAttribute("MenuGroup"), "Main")
		T.eq(refs.Buttons.Codex:GetAttribute("MenuGroup"), "More")
		-- words only (no emoji icon): the name sits in the middle of the button
		T.falsy(refs.Buttons.Shop:FindFirstChild("Icon"), "no emoji icon")
		local label = refs.Buttons.Shop:FindFirstChild("Label") :: any
		T.eq(label.Text, "SHOP")
		T.truthy(label.AnchorPoint.X == 0.5 and label.AnchorPoint.Y == 0.5, "centred")
		T.truthy(label.Position.X.Scale == 0.5 and label.Position.Y.Scale == 0.5, "in the middle")
	end)

	T.test("side menu: the view places every button, badges, SOON chips and hidden buttons", function()
		local refs = SideMenuView.build()
		T.eq(#refs.Order, 11)
		for _, id in
			{ "Shop", "Golems", "Elevator", "Quests", "Codex", "Collection", "Boards", "Settings", "Store", "Hoverboards", "Rebirth" }
		do
			T.truthy(refs.Buttons[id], id)
		end
		-- under the HUD: its popups and toasts show on top
		T.lt(refs.Gui.DisplayOrder, HudView.build().Gui.DisplayOrder)
		local layout = SideMenuView.layout(PHONE, (375 - 58) / PHONE)
		refs.Expanded = true
		SideMenuView.apply(refs, layout)
		T.eq(#SideMenuView.touchTargets(refs), 12, "MENU and 11 buttons")
		checkTouch(SideMenuView.touchTargets(refs), PHONE, "menu")
		-- no two buttons overlap
		local boxes = {}
		for _, target in SideMenuView.touchTargets(refs) do
			table.insert(
				boxes,
				{ x = target.Position.X.Offset, y = target.Position.Y.Offset, w = target.Size.X.Offset, h = target.Size.Y.Offset }
			)
		end
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				local apart = a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
				T.truthy(apart, `buttons {i} and {j} apart`)
			end
		end
		-- the badge and the SOON chip
		SideMenuView.setSoon(refs, "Golems", true)
		T.truthy(refs.Soon.Golems.Visible)
		SideMenuView.setBadge(refs, "Codex", 3)
		T.truthy(refs.Badges.Codex.Visible)
		T.eq(refs.Badges.Codex.Text, "3")
		SideMenuView.setBadge(refs, "Codex", 12)
		T.eq(refs.Badges.Codex.Text, "9+")
		SideMenuView.setBadge(refs, "Codex", 0)
		T.falsy(refs.Badges.Codex.Visible)
		SideMenuView.setBadge(refs, "Golems", 1)
		T.falsy(refs.Soon.Golems.Visible, "a badge hides the SOON chip")
		SideMenuView.setBadge(refs, "Nope", 1) -- unknown ids are ignored
		-- a hidden button leaves no gap: the next one takes its place
		SideMenuView.apply(refs, SideMenuView.layout(1, 684))
		local codexCell = SideMenuView.cellOf(refs, refs.Buttons.Codex) :: number
		SideMenuView.setHidden(refs, "Golems", true)
		T.eq(SideMenuView.shown(refs)[1], "Elevator", "ELEVATOR moves into GOLEMS' cell")
		SideMenuView.apply(refs, SideMenuView.layout(1, 684, { Count = #SideMenuView.shown(refs) }))
		T.eq(SideMenuView.cellOf(refs, refs.Buttons.Codex), codexCell - 1, "CODEX moved up a cell")
		T.falsy(refs.Buttons.Golems.Parent.Visible)
		SideMenuView.setHidden(refs, "Golems", false)
		T.eq(#SideMenuView.shown(refs), 11)
		SideMenuView.setHidden(refs, "Nope", true) -- unknown ids are ignored
	end)

	---------------------------------------------------------------- codex

	T.test("codex: entries follow the save's Discovered record", function()
		local entries = CodexView.entries(
			{ Coal = true, Gold = true, Diamond = false, Bogus = true, [5] = true },
			{ Gold = true, Coal = false }
		)
		T.eq(#entries, #OreData.List)
		T.eq(#entries, 36, "the 36-ore roster")
		local found, total = CodexView.count(entries)
		T.eq(found, 2)
		T.eq(total, #OreData.List)
		T.eq(CodexView.countText(found, total), "2 / 36 FOUND")
		for i, entry in entries do
			T.eq(entry.Ore, OreData.List[i], "OreData order")
			if entry.Ore.Id == "Gold" then
				T.truthy(entry.Found and entry.New, "Gold: found and NEW")
			elseif entry.Ore.Id == "Coal" then
				T.truthy(entry.Found, "Coal found")
				T.falsy(entry.New, "Coal seen")
			else
				T.falsy(entry.Found, entry.Ore.Id)
				T.falsy(entry.New, entry.Ore.Id .. " not NEW")
			end
		end
		-- junk saves: nothing found
		for _, junk in { nil, 5, "x", { Coal = "yes" } } do
			local n = CodexView.count(CodexView.entries(junk))
			T.eq(n, 0)
		end
	end)

	T.test("codex: where an ore is found comes from the zones' rocks", function()
		local zoneNames = {}
		for _, zone in WorldLayout.Zones do
			zoneNames[zone.Name] = true
		end
		local coal = CodexView.zonesOf("Coal")
		T.truthy(#coal >= 1, "Coal is somewhere")
		for _, ore in OreData.List do
			for _, name in CodexView.zonesOf(ore.Id) do
				T.truthy(zoneNames[name], name .. " is a zone")
			end
			local text = CodexView.detailText({ Ore = ore, Found = true, New = false, Zones = CodexView.zonesOf(ore.Id) })
			T.truthy(#text.Where > #"Found in: ", ore.Id .. " says where")
			T.eq(text.Name, ore.Name)
			T.eq(text.Rarity, ore.Rarity)
			T.truthy(text.Income:find("/s", 1, true), "income per second")
			T.eq(text.Lore, ore.Lore)
		end
		T.eq(#CodexView.zonesOf("Bogus"), 0)
	end)

	T.test("codex: the blaster level agrees with where the ore is found", function()
		for _, ore in OreData.List do
			local open, any = math.huge, math.huge
			for _, zone in WorldLayout.Zones do
				local weight = zone.Ores[ore.Id]
				if type(weight) == "number" and weight > 0 then
					any = math.min(any, zone.MinBlaster)
					if not zone.VipOnly then
						open = math.min(open, zone.MinBlaster)
					end
				end
			end
			local expected = if open < math.huge then open elseif any < math.huge then any else ore.Tier
			T.eq(CodexView.levelOf(ore), expected, ore.Id .. ": the lowest gate of its zones")
			local text = CodexView.detailText({ Ore = ore, Found = true, New = false, Zones = CodexView.zonesOf(ore.Id) })
			T.eq(text.Tier, `Blaster level {expected}+`, ore.Id)
		end
		-- the 36-ore map: Bronze is the Quarry's (level 1), the Ember Caves hold Sapphire, Dragon Egg, Diamond (level 3)
		T.eq(CodexView.levelOf(OreData.ById.Bronze), 1, "Bronze")
		for _, id in { "Sapphire", "DragonEgg", "Diamond" } do
			T.eq(CodexView.levelOf(OreData.ById[id]), 3, id)
		end
		-- an ore no zone holds keeps its own Tier
		local loose = table.clone(OreData.ById.Coal)
		loose.Id = "NoZoneOre"
		loose.Tier = 7
		T.eq(CodexView.levelOf(loose), 7)
	end)

	T.test("codex: the redraw fingerprint changes only with what the cards show", function()
		local a = CodexView.fingerprint({ Coal = true, Gold = true }, {})
		T.eq(a, CodexView.fingerprint({ Gold = true, Coal = true, Diamond = false }, nil), "order and false entries don't matter")
		T.truthy(a ~= CodexView.fingerprint({ Coal = true, Gold = true, Tin = true }, {}), "a new ore")
		T.truthy(a ~= CodexView.fingerprint({ Coal = true, Gold = true }, { Gold = true }), "a NEW badge")
		T.eq(CodexView.fingerprint(nil, nil), CodexView.fingerprint("junk", {}))
		-- the zones per ore are worked out once
		T.truthy(rawequal(CodexView.zonesOf("Coal"), CodexView.zonesOf("Coal")))
	end)

	T.test("codex: the sell value says cleaned (Rough), Flawless and dirty", function()
		local ore = OreData.ById.Gold
		local text = CodexView.detailText({ Ore = ore, Found = true, New = false, Zones = {} })
		T.truthy(text.Value:find("Sells: " .. Format.money(ItemData.value("Clean", "Gold", "Rough")), 1, true), text.Value)
		T.truthy(text.Value:find("Flawless " .. Format.money(ItemData.value("Clean", "Gold", "Flawless")), 1, true), text.Value)
		T.truthy(text.Value:find("dirty " .. Format.money(ItemData.value("Raw", "Gold")), 1, true), text.Value)
		T.truthy(ItemData.value("Raw", "Gold") < ItemData.value("Clean", "Gold", "Rough"), "dirty is worth less")
	end)

	T.test("codex: the seen record is saved (NEW badges survive a rejoin)", function()
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local player: any = { UserId = 8, Name = "Seer" }
		local data = deepCopy(DataTemplate)
		local changed = 0
		patch(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		patch(DataService, "changed", function()
			changed += 1
		end)
		local ok, err = pcall(function()
			-- a new player: nothing seen, the record is ready
			T.eq(type(DataTemplate.OreCodex), "table")
			T.falsy(DataTemplate.OreCodex.Ready)
			local fresh = CodexService.prepare(data)
			T.truthy(fresh.Ready)
			T.eq(next(fresh.Seen), nil)
			-- discovered later, looked at: saved
			data.Discovered = { Coal = true, Gold = true }
			T.eq(CodexService.markSeen(player, { "Coal" }), 1)
			T.eq(changed, 1)
			T.truthy(data.OreCodex.Seen.Coal)
			T.eq(data.OreCodex.Seen.Gold, nil, "Gold still NEW")
			-- the next session keeps it (and Gold stays NEW)
			local again = CodexService.prepare(data)
			T.truthy(again.Seen.Coal)
			T.eq(again.Seen.Gold, nil)
			-- junk: undiscovered, unknown, not strings, too many, a metatable
			T.eq(CodexService.markSeen(player, { "Diamond", "Bogus", 5, "Coal" }), 0, "nothing new")
			T.eq(data.OreCodex.Seen.Diamond, nil)
			T.eq(CodexService.markSeen(player, "Gold"), 0)
			local many = {}
			for i = 1, CodexService.MaxIds + 1 do
				many[i] = "Gold"
			end
			T.eq(CodexService.markSeen(player, many), 0, "too many")
			T.eq(CodexService.markSeen(player, setmetatable({ "Gold" }, {})), 0)
			T.eq(changed, 1, "no change, no push")
			T.eq(CodexService.markSeen({ UserId = 9 }, { "Gold" }), 0, "not loaded")
			-- a save from before the record: what it found counts as seen, once
			local old = deepCopy(DataTemplate)
			old.OreCodex = nil
			old.Discovered = { Tin = true, Bogus = true }
			local record = CodexService.prepare(old)
			T.truthy(record.Seen.Tin)
			T.eq(record.Seen.Bogus, nil)
			T.truthy(old.OreCodex.Ready)
			old.Discovered.Iron = true
			T.eq(CodexService.prepare(old).Seen.Iron, nil, "a later discovery is NEW")
			-- a broken record is rebuilt
			data.OreCodex = "broken"
			T.eq(type(CodexService.prepare(data).Seen), "table")
		end)
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("codex: the prompt goes on the terminal's cabinet only", function()
		local Instance = (require("@lune/roblox") :: any).Instance
		local terminal = Instance.new("Model")
		local screen = Instance.new("Part")
		screen.Name = "Screen"
		screen.Parent = terminal
		-- streaming: the model came with a small part, not its cabinet yet
		T.eq(CodexView.promptPart(terminal), nil, "no fallback onto some small part")
		local cabinet = Instance.new("Part")
		cabinet.Name = "Cabinet"
		cabinet.Parent = terminal
		T.eq(CodexView.promptPart(terminal), cabinet, "the part named Cabinet")
		terminal.PrimaryPart = screen
		T.eq(CodexView.promptPart(terminal), screen, "the PrimaryPart first")
		T.eq(CodexView.promptPart(cabinet), cabinet, "a tagged part carries it itself")
		T.eq(CodexView.promptPart(Instance.new("Folder")), nil)
	end)

	T.test("codex: an undiscovered ore keeps its secrets", function()
		local ore = OreData.ById.Heartstone
		local text = CodexView.detailText({ Ore = ore, Found = false, New = false, Zones = CodexView.zonesOf(ore.Id) })
		T.eq(text.Name, CodexView.HiddenName)
		T.eq(text.Rarity, nil)
		T.eq(text.Lore, "")
		T.eq(text.Where, "")
		for _, field in { text.Income, text.Value, text.Tier } do
			T.falsy(field:find(ore.Name, 1, true), "no name")
		end
	end)

	T.test("codex: the view shows found cards, the count and the selected ore", function()
		local refs = CodexView.build(false)
		T.eq(#refs.CardList, #OreData.List)
		local entries = CodexView.entries({ Copper = true, Silver = true }, { Silver = true })
		CodexView.setEntries(refs, entries)
		T.eq(refs.Count.Text, `2 / {#OreData.List} FOUND`)
		T.near(refs.CountFill.Size.X.Scale, 2 / #OreData.List, 1e-6)
		T.eq(refs.Cards.Copper.Name.Text, "Copper")
		T.eq(refs.Cards.Coal.Name.Text, CodexView.HiddenName)
		T.truthy(refs.Cards.Coal.Mark.Visible, "a ? on the hidden gem")
		T.falsy(refs.Cards.Copper.Mark.Visible)
		T.eq(refs.Cards.Copper.Gem.BackgroundColor3, OreData.ById.Copper.Color)
		T.truthy(refs.Cards.Silver.New.Visible, "NEW badge")
		T.falsy(refs.Cards.Copper.New.Visible)
		local silver
		for _, entry in entries do
			if entry.Ore.Id == "Silver" then
				silver = entry
			end
		end
		CodexView.select(refs, silver)
		T.eq(refs.Selected, "Silver")
		T.eq(refs.DetailName.Text, "Silver")
		T.truthy(refs.DetailRarity.Visible)
		T.eq(refs.DetailRarity.Text, OreData.ById.Silver.Rarity, "Silver's rarity (Rare in the 36-ore roster)")
		CodexView.select(refs, entries[1])
		T.eq(refs.DetailName.Text, CodexView.HiddenName)
		T.falsy(refs.DetailRarity.Visible, "no rarity for a hidden ore")
	end)

	T.test("codex: the phone layout has 44 pt cards and fits the screen", function()
		local refs = CodexView.build(true)
		for _, phone in { { 667, 375 }, { 568, 320 }, { 844, 390 } } do
			local maxW, maxH = phone[1] / PHONE, (phone[2] - 58) / PHONE
			CodexView.layout(refs, true, maxW, maxH)
			local cell = refs.GridLayout.CellSize
			T.truthy(cell.X.Offset * PHONE >= MenuPanel.MinTouch - 0.5, "card wide enough")
			T.truthy(cell.Y.Offset * PHONE >= MenuPanel.MinTouch - 0.5, "card tall enough")
			local panel = refs.Frame.Panel
			T.le(panel.Size.X.Offset, maxW)
			T.le(panel.Position.Y.Offset + panel.Size.Y.Offset, maxH + 0.01)
			-- the grid shows at least 4 columns next to the detail pane
			local columns = math.floor((refs.Grid.Size.X.Offset + 8) / (cell.X.Offset + 8))
			T.truthy(columns >= 4, `{phone[1]}x{phone[2]}: {columns} columns`)
		end
		checkTouch({ MenuPanel.holderOf(refs.Frame.Close) }, PHONE, "codex close")
	end)

	---------------------------------------------------------------- settings

	T.test("settings: sanitize makes any record whole and sane", function()
		local d = SettingsConfig.Defaults
		for _, junk in { nil, 5, "x", {} } do
			local s = SettingsConfig.sanitize(junk)
			T.eq(s.Music, d.Music)
			T.eq(s.Sfx, d.Sfx)
			T.eq(s.Shake, d.Shake)
			T.eq(s.Rumble, d.Rumble)
		end
		local s = SettingsConfig.sanitize({ Music = 7, Sfx = -1, Shake = "no", Rumble = false, Evil = true })
		T.eq(s.Music, 1, "clamped")
		T.eq(s.Sfx, 0, "clamped")
		T.eq(s.Shake, d.Shake, "not a boolean: default")
		T.eq(s.Rumble, false)
		T.eq((s :: any).Evil, nil, "unknown keys dropped")
		T.eq(SettingsConfig.sanitize({ Music = 0 / 0 }).Music, d.Music, "NaN")
		T.eq(SettingsConfig.sanitize({ Music = math.huge }).Music, d.Music, "inf")
		T.eq(SettingsConfig.sanitize({ Music = 0.3333 }).Music, 0.33, "whole percent")
		local a = SettingsConfig.sanitize(nil)
		T.truthy(SettingsConfig.equal(a, SettingsConfig.sanitize(a)))
		T.falsy(rawequal(a, SettingsConfig.sanitize(a)), "a new table")
		-- the save template holds the defaults
		T.truthy(SettingsConfig.equal(SettingsConfig.sanitize(DataTemplate.Settings), DataTemplate.Settings))
	end)

	T.test("settings: a change made before the saved record arrived keeps the other saved keys", function()
		local saved = { Music = 0, Sfx = 0.3, Shake = false, Rumble = true }
		local merged = SettingsConfig.merge(saved, { Rumble = false })
		T.eq(merged.Music, 0, "the saved 0 % stays")
		T.eq(merged.Sfx, 0.3)
		T.eq(merged.Shake, false)
		T.eq(merged.Rumble, false, "the early change wins")
		T.eq(SettingsConfig.merge(saved, {}).Music, 0)
		local junk = SettingsConfig.merge("broken", { Sfx = 9, Evil = 1 })
		T.eq(junk.Sfx, 1, "clamped")
		T.eq(junk.Music, SettingsConfig.Defaults.Music)
		T.eq((junk :: any).Evil, nil)
	end)

	T.test("settings: - / + step on the 10% grid and stop at the ends", function()
		T.eq(SettingsConfig.stepVolume(0.6, 1), 0.7)
		T.eq(SettingsConfig.stepVolume(0.6, -1), 0.5)
		T.eq(SettingsConfig.stepVolume(0.55, 1), 0.7)
		T.eq(SettingsConfig.stepVolume(1, 1), 1)
		T.eq(SettingsConfig.stepVolume(0, -1), 0)
		T.eq(SettingsConfig.stepVolume(0.05, -1), 0)
		T.eq(SettingsConfig.percent(0.6), "60%")
		T.eq(SettingsConfig.percent(0.335), "34%")
		-- the slider maths
		T.eq(SettingsView.fraction(150, 100, 200), 0.25)
		T.eq(SettingsView.fraction(50, 100, 200), 0)
		T.eq(SettingsView.fraction(500, 100, 200), 1)
		T.eq(SettingsView.fraction(150, 100, 0), 0, "a zero-width bar")
		T.eq(SettingsView.fraction(0 / 0, 100, 200), 0)
	end)

	T.test("settings: the server keeps only sane records and pushes State", function()
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local player: any = { UserId = 5, Name = "Set" }
		local data = deepCopy(DataTemplate)
		local changed = 0
		patch(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		patch(DataService, "changed", function()
			changed += 1
		end)
		local ok, err = pcall(function()
			T.truthy(SettingsService.apply(player, { Music = 0.2, Sfx = 0.8, Shake = false, Rumble = true }))
			T.eq(changed, 1)
			T.eq(data.Settings.Music, 0.2)
			T.eq(data.Settings.Shake, false)
			T.falsy(SettingsService.apply(player, { Music = 0.2, Sfx = 0.8, Shake = false, Rumble = true }), "no change")
			T.eq(changed, 1)
			-- junk requests
			T.falsy(SettingsService.apply(player, "loud"))
			T.falsy(SettingsService.apply(player, nil))
			local big = {}
			for i = 1, 50 do
				big[i] = i
			end
			T.falsy(SettingsService.apply(player, big), "too many keys")
			T.falsy(SettingsService.apply(player, setmetatable({}, {})), "a metatable")
			T.eq(changed, 1)
			-- a request with junk values falls back to the defaults for those
			T.truthy(SettingsService.apply(player, { Music = 0 / 0, Sfx = 2, Shake = true, Rumble = "x" }))
			T.eq(data.Settings.Music, SettingsConfig.Defaults.Music)
			T.eq(data.Settings.Sfx, 1)
			T.eq(data.Settings.Rumble, SettingsConfig.Defaults.Rumble)
			-- not loaded: nothing
			T.falsy(SettingsService.apply({ UserId = 6 }, { Music = 0 }))
			-- a broken save is repaired on read
			data.Settings = "broken"
			local repaired = SettingsService.read(data)
			T.eq(type(data.Settings), "table")
			T.eq(repaired.Music, SettingsConfig.Defaults.Music)
			data.Settings = nil
			SettingsService.read(data)
			T.eq(data.Settings.Sfx, SettingsConfig.Defaults.Sfx)
		end)
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("settings: rows without a use hide and the panel closes up", function()
		local refs = SettingsView.build(false)
		SettingsView.layout(refs, false, 1280, 684)
		local full = refs.Frame.Panel.Size.Y.Offset
		T.eq(SettingsView.firstButton(refs), refs.Volumes.Sfx.Minus, "the gamepad starts on Sounds")
		T.truthy(SettingsView.setShown(refs, "Music", false))
		T.falsy(SettingsView.setShown(refs, "Music", false), "no change")
		T.truthy(SettingsView.setShown(refs, "Rumble", false))
		T.falsy(SettingsView.setShown(refs, "Nope", false))
		T.falsy(refs.Volumes.Music.Frame.Visible)
		T.falsy(refs.Toggles.Rumble.Frame.Visible)
		T.eq(#SettingsView.shown(refs), 2)
		SettingsView.layout(refs, false, 1280, 684)
		T.lt(refs.Frame.Panel.Size.Y.Offset, full, "shorter")
		for _, target in SettingsView.touchTargets(refs) do
			T.truthy(target ~= MenuPanel.holderOf(refs.Volumes.Music.Minus), "a hidden row isn't a target")
		end
		T.eq(#SettingsView.touchTargets(refs), 1 + 3 + 1, "close, Sounds (-, +, bar), Camera shake")
		T.eq(SettingsView.firstButton(refs), refs.Volumes.Sfx.Minus)
		-- Sounds hidden too (never in the game): the first row that shows
		SettingsView.setShown(refs, "Sfx", false)
		T.eq(SettingsView.firstButton(refs), refs.Toggles.Shake.Button)
		SettingsView.setShown(refs, "Sfx", true)
		SettingsView.setShown(refs, "Music", true)
		T.eq(#SettingsView.shown(refs), 3)
		-- the phone layout with two rows still fits and keeps 44 pt
		SettingsView.setShown(refs, "Music", false)
		SettingsView.layout(refs, true, 667 / PHONE, (375 - 58) / PHONE)
		checkTouch(SettingsView.touchTargets(refs), PHONE, "two rows")
	end)

	T.test("settings: the panel shows the values and its phone buttons are 44 pt", function()
		local refs = SettingsView.build(false)
		SettingsView.set(refs, SettingsConfig.sanitize({ Music = 0.25, Sfx = 0, Shake = false, Rumble = true }))
		T.eq(refs.Volumes.Music.Value.Text, "25%")
		T.eq(refs.Volumes.Music.Fill.Size.X.Scale, 0.25)
		T.eq(refs.Volumes.Sfx.Value.Text, "0%")
		T.eq(refs.Toggles.Shake.Button.Text, "OFF")
		T.eq(refs.Toggles.Rumble.Button.Text, "ON")
		for _, phone in { { 667, 375 }, { 568, 320 } } do
			local maxW, maxH = phone[1] / PHONE, (phone[2] - 58) / PHONE
			SettingsView.layout(refs, true, maxW, maxH)
			checkTouch(SettingsView.touchTargets(refs), PHONE, `{phone[1]}x{phone[2]}`)
			local panel = refs.Frame.Panel
			T.le(panel.Size.X.Offset, maxW)
			T.le(panel.Position.Y.Offset + panel.Size.Y.Offset, maxH + 0.01)
		end
	end)

	---------------------------------------------------------------- the frame

	T.test("menu panel: big screens keep the teleport bar and the coins clear, phones use the room", function()
		local frame = MenuPanel.build("Test", "TEST", "sub")
		-- a 1280 x 720 window at scale 1 (684 under the top bar)
		local body = MenuPanel.layout(frame, false, 900, 560, 1280, 684)
		T.eq(frame.Panel.Size.X.Offset, 900)
		T.truthy(frame.Panel.Position.Y.Offset >= MenuPanel.CoinsBottom, "below the coins")
		T.eq(body.X, 900 - MenuPanel.Pad * 2)
		T.truthy(frame.Subtitle.Visible)
		-- the teleport bar (top centre) never peeks out above a panel
		T.truthy(MenuPanel.TopBarBottom >= HudView.TopBarY + HudView.TopBarHeight, "under the bar")
		for _, size in { { 960, 640 }, { 600, 640 }, { 660, 442 } } do
			MenuPanel.layout(frame, false, size[1], size[2], 1280, 684)
			local top = frame.Panel.Position.Y.Offset
			local h = frame.Panel.Size.Y.Offset
			T.truthy(top >= MenuPanel.TopBarBottom, `{size[1]}x{size[2]}: under the teleport bar`)
			T.truthy(h >= size[2] * MenuPanel.BarShrink, "nearly whole")
			T.le(top + h, 684)
			-- the coins: below them or right of them
			local left = frame.Panel.Position.X.Offset
			T.truthy(top >= MenuPanel.CoinsBottom or left >= 16 + HudView.CoinsWidth, "clear of the coins")
		end
		-- too little room under the bar: the panel covers it from the top
		MenuPanel.layout(frame, false, 900, 640, 1280, 500)
		T.eq(frame.Panel.Position.Y.Offset, 4)
		T.eq(frame.Panel.Size.Y.Offset, 500 - 8)
		-- a phone: compact, no subtitle or footer, the X button 44 pt
		MenuPanel.layout(frame, true, 1200, 700, 667 / PHONE, (375 - 58) / PHONE)
		T.falsy(frame.Subtitle.Visible)
		T.falsy(frame.Hint.Visible)
		checkTouch({ MenuPanel.holderOf(frame.Close) }, PHONE, "close")
		T.le(frame.Panel.Size.X.Offset, 667 / PHONE)
		-- the gamepad footer
		MenuPanel.layout(frame, false, 900, 560, 1280, 684)
		MenuPanel.setHint(frame, "", { { Image = "rbxasset://b.png", Word = "close" } })
		T.truthy(frame.PadHint.Visible)
		T.falsy(frame.Hint.Visible)
		MenuPanel.setHint(frame, "Backspace: close", nil)
		T.falsy(frame.PadHint.Visible)
		T.truthy(frame.Hint.Visible)
		T.eq(#frame.PadHint:GetChildren(), 1, "only the list layout is left")
		-- compact layouts (TVs, phones with a gamepad) keep the gamepad footer and its room
		MenuPanel.setHint(frame, "", { { Image = "rbxasset://b.png", Word = "close" } })
		local withPad = MenuPanel.layout(frame, true, 1200, 700, 1536, 835)
		T.truthy(frame.PadHint.Visible, "glyph hints on a TV")
		T.falsy(frame.Hint.Visible)
		MenuPanel.setHint(frame, "Backspace: close", nil)
		local without = MenuPanel.layout(frame, true, 1200, 700, 1536, 835)
		T.falsy(frame.PadHint.Visible)
		T.falsy(frame.Hint.Visible, "no text footer when compact")
		T.eq(without.Y - withPad.Y, MenuPanel.PadFooter - MenuPanel.Metrics.Compact.Footer, "the footer's room")
		T.truthy(MenuPanel.compactFor(true, false, 1, 900), "touch")
		T.truthy(MenuPanel.compactFor(false, true, 1, 900), "TV")
		T.falsy(MenuPanel.compactFor(false, false, 1, 900), "PC")
	end)
end
