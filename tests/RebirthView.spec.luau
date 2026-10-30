--[[
	The STAR FORGE window (UI/RebirthView) under Lune: the three columns
	list exactly what RebirthConfig.reset does (Head Start's level, Podium
	Keeper), the REBIRTH! button's states, the Star Shop cards' texts, and
	the layout fits PC, phones and TVs: every row and card text fits its
	box, nothing leaves the panel, every button is at least 44 pt on phones.
]]
return function(T, Loader)
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local RebirthView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.RebirthView")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")

	-- design-unit screens: { label, compact, width, height } (the screen / UI scale, the top bar left out)
	local SCREENS = {
		{ "PC 1280 x 720", false, 1280 / 1, (720 - 36) / 1 },
		{ "PC 1920 x 1080", false, 1920 / 1.25, (1080 - 36) / 1.25 },
		{ "phone 667 x 375", true, 667 / 0.62, (375 - 58) / 0.62 },
		{ "phone 568 x 320", true, 568 / 0.62, (320 - 58) / 0.62 },
		{ "tablet 1024 x 768", true, 1024 / 0.93, (768 - 36) / 0.93 },
		{ "TV 1920 x 1080", true, 1920 / 1.25, (1080 - 36) / 1.25 },
	}

	local function info(level: number, perks: any, stars: number): any
		return {
			Count = 2,
			Stars = stars,
			Perks = perks,
			Level = level,
			Ready = level >= RebirthConfig.MinBlaster,
			StarsNow = RebirthConfig.starsFor(level),
		}
	end

	T.test("RebirthView: the columns follow the reset, the button and the cards their state", function()
		local plain = RebirthView.lists({})
		T.truthy(string.find(plain.Lose[2], "LV 1", 1, true), "back to LV 1")
		T.truthy(string.find(plain.Lose[7], "Your ore (not secret ores)", 1, true), "ore goes, the secret ores stay")
		T.truthy(table.find(plain.Keep, "Artifacts, codex, secret ores"), "the secret ores stay (owner 2026-10-29)")
		local perks = { HeadStart = 2, PodiumKeeper = 1 }
		local kept = RebirthView.lists(perks)
		T.truthy(string.find(kept.Lose[2], "LV " .. RebirthConfig.HeadStartLevels[2], 1, true), "Head Start's level")
		T.truthy(string.find(kept.Lose[7], "podiums stay", 1, true), "Podium Keeper")
		T.truthy(string.find(plain.Keep[1], "factory", 1, true), "the factory stays")
		T.truthy(string.find(plain.Lose[1], "Earned coins", 1, true), "earned coins go")
		T.truthy(table.find(plain.Keep, "Coins bought with Robux"), "bought coins stay")
		-- the bottom line
		T.truthy(string.find(RebirthView.needText(info(3, {}, 0)), "Reach blaster LV " .. RebirthConfig.MinBlaster, 1, true))
		T.truthy(string.find(RebirthView.needText(info(8, {}, 0)), `pays {RebirthConfig.starsFor(8)} stars`, 1, true))
		-- cards
		local level, buy, can = RebirthView.cardText({ GoldenTouch = 2 }, 5, "GoldenTouch")
		T.eq(level, "2/10")
		T.eq(buy, `BUY {RebirthConfig.nextCost({ GoldenTouch = 2 }, "GoldenTouch")} STARS`)
		T.eq(select(2, RebirthView.cardText({}, 5, "GoldenTouch")), "BUY 1 STAR", "one star: STAR")
		T.truthy(can)
		local _, top, buyable = RebirthView.cardText({ PodiumKeeper = 1 }, 99, "PodiumKeeper")
		T.eq(top, "MAX")
		T.falsy(buyable)
		T.falsy(select(3, RebirthView.cardText({}, 0, "HeadStart")), "no stars: can't buy")
		T.eq(select(2, RebirthView.cardText({}, 99, "HeadStart", 9)), "MAX", "Robux levels already start at LV 9")
		-- a lifted / paid run past MinBlaster: buy the next level with coins (never "LV 6" at LV 9)
		local lifted = info(9, {}, 0)
		lifted.Ready = false
		T.truthy(string.find(RebirthView.needText(lifted), "Buy blaster LV 10", 1, true))
		local stuck = info(10, {}, 0)
		stuck.StarsNow = 0
		T.truthy(string.find(RebirthView.needText(stuck), "no stars", 1, true), "the top with no coin level")
		-- the REBIRTH! button
		local refs = RebirthView.build()
		RebirthView.setInfo(refs, info(3, {}, 0))
		RebirthView.setConfirm(refs, true)
		T.eq(refs.Rebirth.Text, RebirthView.rebirthWords(false), "not ready: never SURE?")
		T.falsy(refs.Confirm)
		RebirthView.setInfo(refs, info(8, {}, 4))
		RebirthView.setConfirm(refs, true)
		T.eq(refs.Rebirth.Text, RebirthView.rebirthWords(true))
		RebirthView.setConfirm(refs, false)
		T.eq(refs.Rebirth.Text, RebirthView.rebirthWords(false))
		T.eq(refs.Stars.Text, "4 STARS")
		T.eq(refs.Columns.Get.Rows[2].Text, "Rebirth #3")
		RebirthView.setTab(refs, "Shop")
		T.truthy(refs.Pages.Shop.Visible)
		T.falsy(refs.Pages.Rebirth.Visible)
		RebirthView.setTab(refs, "junk")
		T.eq(refs.Tab, "Rebirth")
	end)

	local function box(object: any): (number, number, number, number)
		return object.Position.X.Offset, object.Position.Y.Offset, object.Size.X.Offset, object.Size.Y.Offset
	end

	T.test("RebirthView: the layout fits PC, phones and TVs", function()
		for _, screen in SCREENS do
			local label, compact, w, h = screen[1], screen[2], screen[3], screen[4]
			local refs = RebirthView.build()
			RebirthView.setInfo(refs, info(8, { HeadStart = 3, PodiumKeeper = 1, GoldenTouch = 9 }, 123))
			RebirthView.layout(refs, compact, w, h)
			local panel = refs.Frame.Panel
			local px, py, pw, ph = box(panel)
			T.truthy(px >= 0 and py >= 0 and px + pw <= w + 1e-6 and py + ph <= h + 1e-6, label .. ": the panel is on screen")
			-- every column row fits its column and its text fits the row (the round look's reel
			-- page hides the columns)
			for id, column in refs.Columns do
				if not column.Frame.Visible then
					continue
				end
				local _, _, cw, chh = box(column.Frame)
				for _, row in column.Rows do
					local x, y, rw, rh = box(row)
					T.truthy(y + rh <= chh + 1e-6, `{label}: {id} row inside its column`)
					T.truthy(x + rw <= cw + 1e-6, `{label}: {id} row inside its column's width`)
					T.truthy(
						TechShopView.fits(row.Text, rw, rh, row.TextSize, false),
						`{label}: "{row.Text}" fits ({rw} wide at {row.TextSize})`
					)
				end
				T.truthy(
					TechShopView.fits(column.Chip.Text, column.Chip.Size.X.Offset, column.Chip.Size.Y.Offset, column.Chip.TextSize, false)
				)
			end
			-- the bottom line and the button
			local _, _, nw, nh = box(refs.Need)
			T.truthy(TechShopView.fits(refs.Need.Text, nw, nh, refs.Need.TextSize, true), label .. ": the requirement line fits")
			-- the star count by the tabs ("123 STARS": words, no emoji) fits its room
			local _, _, sw, sh = box(refs.Stars)
			T.truthy(TechShopView.fits(refs.Stars.Text, sw, sh, refs.Stars.TextSize, false), `{label}: "{refs.Stars.Text}" fits`)
			T.truthy(refs.Stars.TextSize >= RebirthView.metrics(compact).Text, label .. ": the star count stays big")
			-- the rows' bullet dots sit in the column, left of the text
			for id, column in refs.Columns do
				for _, row in if column.Frame.Visible then column.Rows else {} do
					local dot = row:FindFirstChild("Dot") :: any
					T.truthy(dot, `{label}: {id} row has its dot`)
					local x = row.Position.X.Offset + dot.Position.X.Offset - dot.Size.X.Offset / 2
					T.truthy(x >= 8 and x + dot.Size.X.Offset <= row.Position.X.Offset, `{label}: {id} dot left of the text`)
				end
			end
			-- the cards' texts (no icon: the name starts at the card's padding)
			for _, card in refs.Cards do
				T.falsy(card.Frame:FindFirstChild("Icon"), `{card.Id}: no emoji icon`)
				local _, _, tw, th = box(card.Text)
				T.truthy(TechShopView.fits(card.Text.Text, tw, th, card.Text.TextSize, true), `{label}: {card.Id} text fits`)
				local nx, _, namew, nameh = box(card.Name)
				T.truthy(nx <= 12, `{label}: {card.Id} name without a gap`)
				T.truthy(TechShopView.fits(card.Name.Text, namew, nameh, card.Name.TextSize, false), `{label}: {card.Id} name fits`)
				local holder = MenuPanel.holderOf(card.Buy)
				T.truthy(
					TechShopView.fits(card.Buy.Text, holder.Size.X.Offset - 12, holder.Size.Y.Offset - 6, card.Buy.TextSize, false),
					`{label}: "{card.Buy.Text}" fits its button`
				)
			end
			-- touch sizes on phones
			if compact then
				for _, button in RebirthView.buttons(refs) do
					local holder = MenuPanel.holderOf(button)
					T.truthy(holder.Size.Y.Offset * MenuPanel.PhoneScale >= MenuPanel.MinTouch, `{label}: {holder.Name} tall enough`)
					T.truthy(holder.Size.X.Offset * MenuPanel.PhoneScale >= MenuPanel.MinTouch, `{label}: {holder.Name} wide enough`)
				end
			end
		end
	end)

	T.test("RebirthView: the round look's page is the reel's Rebirth with real numbers", function()
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		-- the numbers: the stars now and after this rebirth, the blaster level now and after
		local ready = info(8, { HeadStart = 1 }, 4)
		ready.Reached = 8
		local v = RebirthView.reelValues(ready)
		T.eq(v.From, "Rebirth 2")
		T.eq(v.To, "Rebirth 3")
		T.eq(v.Rows[1][1], "4")
		T.eq(v.Rows[1][2], tostring(4 + RebirthConfig.starsFor(8)), "what this rebirth pays")
		T.eq(v.Rows[2][1], "LV 8")
		T.eq(v.Rows[2][2], `LV {RebirthConfig.HeadStartLevels[1]}`, "Head Start's level")
		T.eq(v.Bar, 1)
		local early = info(3, {}, 0)
		local e = RebirthView.reelValues(early)
		T.near(e.Bar, 3 / RebirthConfig.MinBlaster, 1e-9, "toward the requirement")
		T.eq(e.BarText, `Blaster LV 3/{RebirthConfig.MinBlaster}`)
		T.eq(e.Rows[1][2], tostring(RebirthConfig.starsFor(RebirthConfig.MinBlaster)), "a rebirth at the requirement")
		T.eq(e.Rows[2][2], "LV 1")
		T.eq(e.Lead, RebirthView.LeadText)
		-- right after a rebirth the snapshot's Reached is 0 (no level bought with coins yet): the bar
		-- reads the blaster's level, like the row above it (review 2026-10-28 #16)
		local fresh = info(1, {}, 5)
		fresh.Reached = 0
		T.eq(RebirthView.reelValues(fresh).BarText, `Blaster LV 1/{RebirthConfig.MinBlaster}`)
		-- past MinBlaster with no coin level this run (NotForged): the box says what the server wants
		local lifted = info(RebirthConfig.MinBlaster + 1, {}, 0)
		lifted.Ready = false
		lifted.Reached = 0
		local l = RebirthView.reelValues(lifted)
		T.eq(l.Lead, RebirthView.forgeText(RebirthConfig.MinBlaster + 1), "the reason in the box")
		T.eq(l.BarText, `Buy LV {RebirthConfig.MinBlaster + 2} with coins`)
		T.eq(l.Rows[1][2], tostring(RebirthConfig.starsFor(RebirthConfig.MinBlaster + 2)), "what that rebirth would pay")
		if not (PopTheme.round() and UIConfig.lightUI()) then
			return
		end
		-- the page: no columns, the two rows, the box, Rebirth / OR / Not now; the tabs stay
		local refs = RebirthView.build()
		RebirthView.setInfo(refs, ready)
		RebirthView.layout(refs, false, 1280, 684)
		local reel = refs.Reel :: any
		T.truthy(reel, "the reel page")
		for _, column in refs.Columns do
			T.falsy(column.Frame.Visible, "no YOU LOSE / KEEP / GET")
		end
		T.eq(reel.Rows[1].BeforeText.Text, "4")
		T.eq(reel.Rows[2].AfterText.Text, "LV 2")
		T.eq(reel.Lead.Text, RebirthView.LeadText)
		T.truthy(refs.NotNow and refs.NotNow.Text == RebirthView.NotNowText, "Not now")
		T.truthy(table.find(RebirthView.buttons(refs), refs.NotNow), "a button like the others")
		T.eq(refs.Frame.Panel.Size.X.Offset, RebirthView.ReelSize.Normal.X, "the reel's small window")
		for _, id in RebirthView.TabIds do
			T.truthy(MenuPanel.holderOf(refs.Tabs[id]).Visible, id .. " tab stays")
		end
		-- the same SURE? second press
		RebirthView.setConfirm(refs, true)
		T.eq(refs.Rebirth.Text, "Sure?")
		-- a refusal replaces the box's line
		RebirthView.setMessage(refs, "Not yet")
		T.truthy(refs.Message.Visible and not reel.Lead.Visible)
		RebirthView.setMessage(refs, nil)
		T.truthy(reel.Lead.Visible)
		-- the shop pages get their room back, the Rebirth tab the small window
		RebirthView.setTab(refs, "Shop")
		T.eq(refs.Frame.Panel.Size.X.Offset, RebirthView.Metrics.Normal.Width)
		RebirthView.setTab(refs, "Rebirth")
		T.eq(refs.Frame.Panel.Size.X.Offset, RebirthView.ReelSize.Normal.X)
		-- the pieces stay inside the page
		local page = refs.Pages.Rebirth
		for _, piece in { reel.Box, MenuPanel.holderOf(refs.Rebirth), MenuPanel.holderOf(refs.NotNow :: any) } do
			local x, y, w, h = box(piece)
			T.truthy(
				x >= 0 and y >= 0 and x + w <= page.Size.X.Offset + 1e-6 and y + h <= page.Size.Y.Offset + 1e-6,
				piece.Name .. " inside"
			)
		end
	end)
end
