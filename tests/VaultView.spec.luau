--[[
	The Blaster Vault window (UI/VaultView) and the crate-opening overlay
	(UI/CrateOpeningView) under Lune: the cards follow the server's rules
	(VaultService.refusal), the layout fits PC, phones and TVs with nothing
	overlapping on a card, every button is at least 44 pt on phones, long
	names stay on two lines, and the overlay's timeline (fade, flash,
	reveal, AWESOME!, the skip hint).
]]
return function(T, Loader)
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local VaultService = Loader.requirePath("ServerScriptService.Server.Services.VaultService")
	local VaultView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.VaultView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
	local CrateOpeningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CrateOpeningView")
	local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")

	-- design-unit screens: { label, compact, width, height } (the screen / UI scale, the top bar left out)
	local SCREENS = {
		{ "PC 1280 x 720", false, 1280 / 1, (720 - 36) / 1 },
		{ "PC 1920 x 1080", false, 1920 / 1.25, (1080 - 36) / 1.25 },
		{ "phone 667 x 375", true, 667 / 0.62, (375 - 58) / 0.62 },
		{ "phone 568 x 320", true, 568 / 0.62, (320 - 58) / 0.62 },
		{ "tablet 1024 x 768", true, 1024 / 0.93, (768 - 36) / 0.93 },
		{ "TV 1920 x 1080", true, 1920 / 1.25, (1080 - 36) / 1.25 },
	}

	T.test("VaultView: the cards follow the server's rules", function()
		for current = 1, BlasterData.MaxLevel do
			for _, case in { { 0 }, { 1e5 }, { 1e15 }, { 1e15, 0 }, { 1e15, 9 } } do
				local coins, reached = case[1], case[2]
				local cards = VaultView.cards(current, coins, reached)
				T.eq(#cards, BlasterData.MaxLevel - VaultView.FirstLevel + 2, "levels 2..10 + coming soon")
				local nexts = 0
				for _, card in cards do
					if card.State == "Soon" then
						T.falsy(card.CanBuy, "coming soon can't be bought")
						continue
					end
					local expected = VaultService.refusal(card.Level, current, coins, reached)
					T.eq(card.CanBuy, expected == nil, string.format("LV %d at %d with %d", card.Level, current, coins))
					if expected and expected ~= "Max" then
						T.eq(card.Reason, expected, "same reason as the server")
					end
					T.eq(card.Price, BlasterData.vaultPrice(card.Level), "price")
					T.eq(card.Ore, BlasterData.vaultOre(card.Level), "case look")
					if card.State == "Next" then
						nexts += 1
						T.eq(card.Level, current + 1, "next is the level after yours")
					end
					T.eq(
						VaultView.buttonText(card),
						if card.State == "Owned"
							then "OWNED"
							elseif card.State == "Locked" then "LOCKED"
							elseif card.Reason == "ForgeFirst" then "FOUNDRY"
							else "BUY",
						"button text"
					)
				end
				T.eq(nexts, if current < BlasterData.MaxLevel then 1 else 0, "one NEXT card")
			end
		end
		-- the top level waits for the Foundry while a rebirth run has forged no rebirth level
		local top = VaultView.cards(BlasterData.MaxLevel - 1, 1e15, 0)
		T.eq(top[#top - 1].Reason, "ForgeFirst")
		T.eq(VaultView.buttonText(top[#top - 1]), "FOUNDRY")
		T.eq(top[#top].Reason, "StarForge", "the last card points to the Star Forge")
		T.eq(VaultView.buttonText(top[#top]), "REBIRTH")
		T.eq(VaultView.reasonText("NoCoins"), "Not enough coins", "reason text")
		T.truthy(#VaultView.reasonText("???") > 0, "unknown reasons still say something")
	end)

	local function inside(r: any, w: number, h: number): boolean
		return r.X >= 0 and r.Y >= 0 and r.X + r.W <= w and r.Y + r.H <= h
	end

	local function overlaps(a: any, b: any): boolean
		return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
	end

	T.test("VaultView: the layout fits every screen, nothing overlaps on a card", function()
		for _, screen in SCREENS do
			local label, compact, w, h = screen[1], screen[2], screen[3], screen[4]
			local g = VaultView.grid(BlasterData.MaxLevel - VaultView.FirstLevel + 2, compact, w, h)
			T.le(g.PanelW, w, label .. " panel width")
			T.le(g.PanelH + VaultView.Style.Lip, h, label .. " panel height")
			T.le(g.ViewW, g.PanelW, label .. " cards inside the panel")
			if not compact then
				T.eq(g.CanvasW, g.ViewW, label .. ": no scrolling on PC")
			end
			local slots = g.Slots
			local names = { "Pill", "Icon", "Name", "Damage", "Price", "Button" }
			for _, name in names do
				T.truthy(inside(slots[name], g.TileW, g.TileH), label .. " " .. name .. " inside the card")
			end
			for i, a in { "Name", "Damage", "Price", "Button" } do
				for j, b in { "Name", "Damage", "Price", "Button" } do
					if i < j then
						T.falsy(overlaps(slots[a], slots[b]), label .. " " .. a .. " / " .. b)
					end
				end
				T.falsy(overlaps(slots[a], slots.Icon), label .. " " .. a .. " / Icon")
			end
			if compact then
				T.truthy(slots.Button.H * VaultView.PhoneScale >= VaultView.MinTouch - 0.5, label .. " BUY tall enough")
				T.truthy(slots.Button.W * VaultView.PhoneScale >= VaultView.MinTouch, label .. " BUY wide enough")
			end
		end
	end)

	T.test("VaultView: builds, lays out and fills in on every screen", function()
		for _, screen in SCREENS do
			local label, compact, w, h = screen[1], screen[2], screen[3], screen[4]
			for _, level in { 1, 3, 9, 10 } do
				local refs = VaultView.build()
				VaultView.layout(refs, compact, w, h)
				VaultView.setCards(refs, VaultView.cards(level, 1e7))
				VaultView.setCoins(refs, 1e7)
				VaultView.setCurrent(refs, level, BlasterData.vaultOre(level))
				T.truthy(string.find(refs.Info.Text, "LV " .. level, 1, true), label .. " your level")
				local g = refs.Grid
				for _, tile in refs.Tiles do
					local card = tile.Card
					T.truthy(card, "every tile has a card")
					-- the name fits its two lines
					local box = g.Slots.Name
					T.truthy(
						TechShopView.fits(tile.Name.Text, box.W, box.H, tile.Name.TextSize, true),
						label .. " name fits: " .. tile.Name.Text
					)
					T.truthy(tile.Name.TextSize >= 11, "readable name")
					-- the price fits its row next to the coin (balance pass 1: up to $140B)
					if tile.PriceRow.Visible then
						local row = g.Slots.Price
						local width = row.W + tile.Price.Size.X.Offset
						T.truthy(
							TechShopView.fits(tile.Price.Text, width, row.H, tile.Price.TextSize, false),
							label .. " price fits: " .. tile.Price.Text
						)
					end
					T.eq(tile.Ribbon.Visible, card.State == "Next", "NEXT ribbon")
					T.eq(tile.Check.Visible, card.State == "Owned", "owned check")
					T.eq(tile.Icon ~= nil, card.State ~= "Soon", "case icon")
				end
				local first = VaultView.firstButton(refs)
				if level < BlasterData.MaxLevel then
					local tile = VaultView.tileFor(refs, level + 1)
					T.eq(first, tile and tile.Button, label .. " gamepads start on the next card")
				end
				if compact then
					for _, target in VaultView.touchTargets(refs) do
						T.truthy(
							target.Size.Y.Offset * VaultView.PhoneScale >= VaultView.MinTouch,
							label .. " " .. target.Name .. " tall enough"
						)
						T.truthy(
							target.Size.X.Offset * VaultView.PhoneScale >= VaultView.MinTouch,
							label .. " " .. target.Name .. " wide enough"
						)
					end
				end
				-- a message replaces the hint, then the hint comes back
				VaultView.setMessage(refs, "Not enough coins", VaultView.Style.Bad)
				T.truthy(refs.Message.Visible, "message shown")
				T.falsy(refs.Hint.Visible, "hint hidden")
				VaultView.setMessage(refs, nil, nil)
				T.falsy(refs.Message.Visible, "message gone")
				-- a relayout to the other mode redraws the icons at their new size
				VaultView.layout(refs, not compact, w, h)
				local icon = refs.Tiles[1].Icon
				T.truthy(icon and icon.Size.X.Offset == refs.Grid.Slots.Icon.W, label .. " icon redrawn")
			end
		end
	end)

	T.test("VaultView: every case icon draws", function()
		local refs = VaultView.build()
		for level = 1, BlasterData.MaxLevel do
			local icon = VaultView.caseIcon(refs.Root, level, BlasterData.vaultOre(level), 120)
			T.eq(icon.Size.X.Offset, 120, "icon width")
			T.truthy(#icon:GetChildren() > 10, "level " .. level .. " has detail")
		end
	end)

	T.test("CrateOpeningView: the overlay's timeline", function()
		local refs = CrateOpeningView.build()
		local burst, reveal = Stage.T_BURST, Stage.T_RISE_END + 0.25
		for level = 1, BlasterData.MaxLevel do
			CrateOpeningView.setBlaster(refs, level, BlasterData.vaultOre(level))
			T.truthy(#refs.Name.Text > 0, "name")
			T.truthy(string.find(refs.Stats.Text, "LV " .. level, 1, true), "level")
			T.truthy(#refs.RarityText.Text > 0, "rarity")
		end
		CrateOpeningView.update(refs, 0, burst, reveal)
		T.eq(refs.Fade.BackgroundTransparency, 0, "starts black")
		T.falsy(refs.Reveal.Visible, "no title yet")
		CrateOpeningView.update(refs, 1.2, burst, reveal)
		T.falsy(refs.Fade.Visible, "faded in")
		T.truthy(refs.Skip.Visible, "the skip hint while charging")
		CrateOpeningView.update(refs, burst + 0.05, burst, reveal)
		T.truthy(refs.Flash.Visible, "the flash at the burst")
		T.falsy(refs.Skip.Visible, "no skip hint after the burst")
		CrateOpeningView.update(refs, reveal + 0.1, burst, reveal)
		T.truthy(refs.Reveal.Visible, "NEW BLASTER!")
		T.falsy(refs.Flash.Visible, "the flash is gone")
		T.falsy(refs.ContinueHolder.Visible, "AWESOME! comes a moment later")
		CrateOpeningView.update(refs, reveal + CrateOpeningView.ButtonAfter + 0.1, burst, reveal)
		T.truthy(refs.ContinueHolder.Visible, "AWESOME!")
		T.near(refs.RevealScale.Scale, 1, 0.001, "popped in")
		CrateOpeningView.update(refs, 9, burst, reveal, 1)
		T.eq(refs.Fade.BackgroundTransparency, 0, "leaving fades to black")
		for _, target in CrateOpeningView.touchTargets(refs) do
			T.truthy(target.Size.Y.Offset * VaultView.PhoneScale >= VaultView.MinTouch, "AWESOME! tall enough")
		end
	end)
end
