-- The side menu and its panels under Lune: SideMenuView's column layout
-- (below the coins, centred, two or three columns on phones, 44 pt touch
-- targets), its badges and SOON chips; the ORE CODEX (entries from the
-- save's Discovered record, NEW badges, the count, where an ore is found,
-- undiscovered ores keep their secrets, the phone layout); SETTINGS
-- (SettingsConfig.sanitize / steps, SettingsService saving only sane
-- records with DataService.changed, SettingsView's slider math, texts and
-- touch sizes) and the shared MenuPanel frame.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local SettingsService = Loader.requirePath("ServerScriptService.Server.Services.SettingsService")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local CodexView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CodexView")
	local SettingsView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SettingsView")

	local PHONE = MenuPanel.PhoneScale

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

	T.test("side menu: one column on a PC, under the coins, inside the screen", function()
		local layout = SideMenuView.layout(1, 720 - 36)
		T.eq(layout.Columns, 1)
		T.eq(layout.Rows, #SideMenuView.Entries)
		T.truthy(layout.Top >= SideMenuView.TopMin, "below the coins and their popups")
		T.le(layout.Top + layout.Size.Y, 720 - 36 - SideMenuView.BottomMargin)
		-- a big screen centres it
		local tall = SideMenuView.layout(1, 1200)
		T.eq(tall.Columns, 1)
		T.near(tall.Top + tall.Size.Y / 2, 600, 1, "centred")
	end)

	T.test("side menu: phones get 44 pt buttons in two (or three) columns that fit", function()
		-- pt sizes of common phones in landscape, under a 58 pt top bar
		for _, phone in { { 844, 390 }, { 667, 375 }, { 640, 360 }, { 568, 320 } } do
			local designH = (phone[2] - 58) / PHONE
			local layout = SideMenuView.layout(PHONE, designH)
			T.eq(layout.Columns, 2, `{phone[1]}x{phone[2]}: two columns`)
			T.truthy(layout.Width * PHONE >= SideMenuView.MinTouch - 0.5, "wide enough")
			T.truthy(layout.Height * PHONE >= SideMenuView.MinTouch - 0.5, "tall enough")
			T.truthy(layout.Top >= SideMenuView.TopTight, "below the coins panel")
			T.le(layout.Top + layout.Size.Y, designH - SideMenuView.BottomMargin + 0.01)
			-- it leaves most of the screen's width to the game (the thumbstick)
			T.lt(layout.Size.X * PHONE + SideMenuView.Left * PHONE, phone[1] * 0.3)
		end
		-- the common phones keep the "+$X" popups clear too
		T.truthy(SideMenuView.layout(PHONE, (375 - 58) / PHONE).Top >= SideMenuView.TopMin)
	end)

	T.test("side menu: the view places every button, badges and SOON chips", function()
		local refs = SideMenuView.build()
		T.eq(#refs.Order, 7)
		for _, id in { "Shop", "Golems", "Codex", "Collection", "Boards", "Settings", "Store" } do
			T.truthy(refs.Buttons[id], id)
		end
		local layout = SideMenuView.layout(PHONE, (375 - 58) / PHONE)
		SideMenuView.apply(refs, layout)
		checkTouch(SideMenuView.touchTargets(refs), PHONE, "menu")
		-- no two buttons overlap
		local boxes = {}
		for _, target in SideMenuView.touchTargets(refs) do
			table.insert(boxes, { x = target.Position.X.Offset, y = target.Position.Y.Offset, w = target.Size.X.Offset, h = target.Size.Y.Offset })
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
	end)

	---------------------------------------------------------------- codex

	T.test("codex: entries follow the save's Discovered record", function()
		local entries = CodexView.entries({ Coal = true, Gold = true, Diamond = false, Bogus = true, [5] = true }, { Gold = true, Coal = false })
		T.eq(#entries, #OreData.List)
		T.eq(#entries, 30)
		local found, total = CodexView.count(entries)
		T.eq(found, 2)
		T.eq(total, 30)
		T.eq(CodexView.countText(found, total), "2 / 30 FOUND")
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
		T.eq(#refs.CardList, 30)
		local entries = CodexView.entries({ Copper = true, Silver = true }, { Silver = true })
		CodexView.setEntries(refs, entries)
		T.eq(refs.Count.Text, "2 / 30 FOUND")
		T.near(refs.CountFill.Size.X.Scale, 2 / 30, 1e-6)
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
		T.eq(refs.DetailRarity.Text, "Uncommon")
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

	T.test("menu panel: big screens keep the HUD coins clear, phones use the room", function()
		local frame = MenuPanel.build("Test", "TEST", "sub")
		-- a 1280 x 720 window at scale 1 (684 under the top bar)
		local body = MenuPanel.layout(frame, false, 900, 560, 1280, 684)
		T.eq(frame.Panel.Size.X.Offset, 900)
		T.truthy(frame.Panel.Position.Y.Offset >= MenuPanel.CoinsBottom, "below the coins")
		T.eq(body.X, 900 - MenuPanel.Pad * 2)
		T.truthy(frame.Subtitle.Visible)
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
		T.truthy(MenuPanel.compactFor(true, false, 1, 900), "touch")
		T.truthy(MenuPanel.compactFor(false, true, 1, 900), "TV")
		T.falsy(MenuPanel.compactFor(false, false, 1, 900), "PC")
	end)
end
