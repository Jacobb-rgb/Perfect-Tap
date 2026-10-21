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
		T.truthy(string.find(plain.Lose[7], "All your ore", 1, true))
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
		-- a lifted / paid run past MinBlaster: forge the next level (never "LV 6" at LV 9)
		local lifted = info(9, {}, 0)
		lifted.Ready = false
		T.truthy(string.find(RebirthView.needText(lifted), "Forge blaster LV 10", 1, true))
		local stuck = info(10, {}, 0)
		stuck.StarsNow = 0
		T.truthy(string.find(RebirthView.needText(stuck), "no stars", 1, true), "the top with nothing forged")
		-- the REBIRTH! button
		local refs = RebirthView.build()
		RebirthView.setInfo(refs, info(3, {}, 0))
		RebirthView.setConfirm(refs, true)
		T.eq(refs.Rebirth.Text, "REBIRTH!", "not ready: never SURE?")
		T.falsy(refs.Confirm)
		RebirthView.setInfo(refs, info(8, {}, 4))
		RebirthView.setConfirm(refs, true)
		T.eq(refs.Rebirth.Text, "SURE?")
		RebirthView.setConfirm(refs, false)
		T.eq(refs.Rebirth.Text, "REBIRTH!")
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
			-- every column row fits its column and its text fits the row
			for id, column in refs.Columns do
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
				for _, row in column.Rows do
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
end
