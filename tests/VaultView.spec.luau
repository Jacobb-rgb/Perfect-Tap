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
			for _, case in { { 0 }, { 1e5 }, { 1e15 }, { 1e15, 0 }, { 1e15, 1e9 }, { 1e8, 1e6 } } do
				local coins, runIncome = case[1], case[2]
				local cards = VaultView.cards(current, coins, runIncome)
				T.eq(#cards, BlasterData.MaxLevel - VaultView.FirstLevel + 2, "levels 2..10 + coming soon")
				local nexts = 0
				for _, card in cards do
					if card.State == "Soon" then
						T.falsy(card.CanBuy, "coming soon can't be bought")
						continue
					end
					local expected = VaultService.refusal(card.Level, current, coins, runIncome)
					T.eq(card.CanBuy, expected == nil, string.format("LV %d at %d with %d", card.Level, current, coins))
					if expected and expected ~= "Max" then
						T.eq(card.Reason, expected, "same reason as the server")
					end
					T.eq(card.Price, BlasterData.vaultPrice(card.Level, runIncome), "price (with the rebirth run's floor)")
					T.eq(card.Ore, BlasterData.vaultOre(card.Level), "case look")
					if card.State == "Next" then
						nexts += 1
						T.eq(card.Level, current + 1, "next is the level after yours")
					end
					T.eq(
						VaultView.buttonText(card),
						if card.State == "Owned" then "OWNED" elseif card.State == "Locked" then "LOCKED" else "BUY",
						"button text"
					)
				end
				T.eq(nexts, if current < BlasterData.MaxLevel then 1 else 0, "one NEXT card")
			end
		end
		-- the coin Vault sells the top level (owner 2026-10-24: no Foundry)
		local top = VaultView.cards(BlasterData.MaxLevel - 1, 1e15, 0)
		T.truthy(top[#top - 1].CanBuy, "LV 10 for coins")
		T.eq(VaultView.buttonText(top[#top - 1]), "BUY")
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
			T.truthy(icon:FindFirstChild("Emblem"), "level " .. level .. " has its core")
			local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
			local color = BlasterBuilder.colors(level, BlasterData.vaultOre(level)).Color
			T.eq((icon:FindFirstChild("Band") :: any).BackgroundColor3, color, "level " .. level .. ": its blaster's colour")
		end
	end)

	T.test("CrateOpeningView: the overlay's timeline", function()
		local refs = CrateOpeningView.build()
		local burst, reveal = Stage.T_BURST, Stage.T_RISE_END
		for level = 1, BlasterData.MaxLevel do
			CrateOpeningView.setBlaster(refs, level, BlasterData.vaultOre(level))
			T.truthy(#refs.Name.Text > 0, "name")
			T.truthy(string.find(refs.Stats.Text, "LV " .. level, 1, true), "level")
			T.truthy(#refs.RarityText.Text > 0, "rarity")
			local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
			T.eq(refs.Line.BackgroundColor3, BlasterBuilder.colors(level, BlasterData.vaultOre(level)).Color, "the words in its colour")
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
		T.truthy(refs.Title.Visible, "NEW BLASTER!")
		T.falsy(refs.Reveal.Visible, "the rarity comes after it")
		T.falsy(refs.Flash.Visible, "the flash is gone")
		T.falsy(refs.ContinueHolder.Visible, "AWESOME! comes a moment later")
		T.truthy(refs.Title.Position.Y.Scale > 0.6, "under the blaster, not over it")
		CrateOpeningView.update(refs, reveal + CrateOpeningView.RarityAt + 0.05, burst, reveal)
		T.truthy(refs.Reveal.Visible, "the words")
		T.truthy(refs.Ribbon.Visible and refs.RarityText.Visible, "the ribbon and the rarity")
		T.falsy(refs.Name.Visible, "one after the other")
		T.truthy(refs.Reveal.Position.X.Scale > 0.6, "on the right of the screen")
		T.eq(CrateOpeningView.CollectAt, Stage.T_HOLD - reveal, "its Hold is the stage's")
		CrateOpeningView.update(refs, reveal + CrateOpeningView.ValueAt + 0.1, burst, reveal)
		local counting = refs.Damage.Text
		CrateOpeningView.update(refs, Stage.T_HOLD, burst, reveal)
		T.truthy(counting ~= refs.Damage.Text, "the damage counts up")
		T.falsy(refs.Title.Visible, "NEW BLASTER! has flown on")
		T.truthy(refs.ContinueHolder.Visible, "AWESOME! at the hold")
		T.truthy(refs.Name.Visible and refs.Row.Visible and refs.Value.Visible, "every word shows")
		T.falsy(refs.Collected.Visible, "not collected yet")
		CrateOpeningView.update(refs, Stage.T_HOLD + 0.3, burst, reveal)
		T.truthy(refs.Collected.Visible, "COLLECTED!")
		T.falsy(refs.Reveal.Visible, "the words are gone")
		-- the words fit beside the blaster on every screen
		CrateOpeningView.fit(refs, 680, 390)
		T.truthy(refs.RevealScale.Scale * 660 <= 340 + 1e-6, "a phone: half the screen")
		CrateOpeningView.fit(refs, 1920, 1080)
		T.le(refs.RevealScale.Scale, 1.15, "a big screen: not huge")
		CrateOpeningView.update(refs, 9, burst, reveal, 1)
		T.eq(refs.Fade.BackgroundTransparency, 0, "leaving fades to black")
		for _, target in CrateOpeningView.touchTargets(refs) do
			T.truthy(target.Size.Y.Offset * VaultView.PhoneScale >= VaultView.MinTouch, "AWESOME! tall enough")
		end
	end)

	T.test("CrateOpeningView: the words name exactly the blaster you got", function()
		local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
		local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
		local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
		local refs = CrateOpeningView.build()
		local burst, reveal = Stage.T_BURST, Stage.T_RISE_END
		local function check(level: number, oreId: string)
			local label = string.format("level %d in %q: ", level, oreId)
			local rarity = if oreId ~= "" then Rarity.ById[OreData.ById[oreId].Rarity] else Rarity.ById.Common
			local damage = BlasterData.damage(level, oreId)
			CrateOpeningView.setBlaster(refs, level, oreId)
			T.eq(refs.Name.Text, string.upper(BlasterData.displayName(level, oreId)), label .. "name")
			T.eq(refs.RarityText.Text, string.upper(rarity.Name), label .. "rarity")
			T.eq(refs.Stats.Text, "LV " .. level, label .. "level")
			T.eq(refs.DamageValue, damage, label .. "damage")
			local stars = 0
			for _, st in refs.Stars do
				stars += if st.Visible then 1 else 0
			end
			T.eq(stars, math.min(rarity.Order, #refs.Stars), label .. "stars")
			-- the damage counted all the way up
			CrateOpeningView.update(refs, Stage.T_HOLD, burst, reveal)
			T.eq(refs.Damage.Text, Format.big(damage), label .. "damage shown")
		end
		for level = 1, BlasterData.MaxLevel do
			check(level, BlasterData.vaultOre(level))
		end
		check(5, "Sapphire") -- (an older save's blaster)
		check(3, "")
	end)

	T.test("CrateOpeningView: every colour on the screen is the blaster's", function()
		local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
		local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault.Kit")
		local function hueGap(a: number, b: number): number
			local gap = math.abs(a - b)
			return math.min(gap, 1 - gap)
		end
		local outlineHue, outlineSat = VaultView.Style.Outline:ToHSV()
		local function gradientColors(g: any): { any }
			local out = {}
			for _, k in g.Color.Keypoints do
				table.insert(out, k.Value)
			end
			return out
		end
		for level = 1, BlasterData.MaxLevel do
			local ore = BlasterData.vaultOre(level)
			local glow = BlasterBuilder.colors(level, ore).Color
			T.eq(Kit.Levels[level].Glow, glow, "level " .. level .. ": the crate in the Vault")
			local hue, sat = glow:ToHSV()
			local refs = CrateOpeningView.build()
			CrateOpeningView.setBlaster(refs, level, ore)
			local function inHue(color: any, what: string)
				local h, s = color:ToHSV()
				if s > 0.04 then
					local isOutline = math.abs(h - outlineHue) < 1e-3 and math.abs(s - outlineSat) < 1e-3
					T.truthy(
						isOutline or hueGap(h, hue) <= 0.015,
						string.format("level %d %s: hue %.3f, its blaster %.3f", level, what, h, hue)
					)
				end
			end
			-- the whole screen: nothing in another colour is left
			for _, d in refs.Gui:GetDescendants() do
				if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
					inHue(d.BackgroundColor3, d.Name)
				end
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
					inHue(d.TextColor3, d.Name .. " text")
				end
				if d:IsA("UIStroke") then
					inHue(d.Color, (d.Parent :: any).Name .. " edge")
				end
				if d:IsA("UIGradient") and d.Name == "Colour" then
					for _, c in gradientColors(d) do
						inHue(c, (d.Parent :: any).Name .. " gradient")
					end
				end
			end
			-- and each of these really took it (a blaster with a colour at all)
			if sat > 0.2 then
				local function coloured(color: any, what: string)
					local h, s = color:ToHSV()
					T.truthy(s > 0.05 and hueGap(h, hue) <= 0.015, string.format("level %d %s: %.3f sat %.2f", level, what, h, s))
				end
				local holder = refs.ContinueHolder
				local face = refs.Continue
				local badge = refs.Collected:FindFirstChild("Badge") :: any
				coloured(refs.Line.BackgroundColor3, "the line")
				coloured(refs.Row.BackgroundColor3, "the level's chip")
				coloured(refs.Value.BackgroundColor3, "the damage's chip")
				coloured((refs.Row:FindFirstChild("Edge") :: any).Color, "its edge")
				coloured((refs.Value:FindFirstChild("Edge") :: any).Color, "its edge")
				coloured(refs.NewTag.BackgroundColor3, "NEW!")
				coloured(refs.NewTag:FindFirstChildOfClass("UIStroke").Color, "NEW!'s edge")
				coloured(refs.Damage.TextColor3, "the damage")
				coloured(refs.Stars[1].BackgroundColor3, "the stars")
				coloured((holder:FindFirstChild("Lip") :: any).BackgroundColor3, "AWESOME!'s lip")
				coloured((face:FindFirstChild("Edge") :: any).Color, "AWESOME!'s edge")
				coloured(gradientColors(face:FindFirstChild("Colour"))[1], "AWESOME!")
				coloured(gradientColors(refs.Ribbon:FindFirstChild("Colour"))[2], "the ribbon")
				coloured(gradientColors(refs.RarityText:FindFirstChild("Colour"))[2], "the rarity")
				coloured(gradientColors(refs.TitleBlaster:FindFirstChild("Colour"))[2], "BLASTER!")
				coloured(badge.BackgroundColor3, "COLLECTED!'s badge")
				coloured((badge:FindFirstChild("Edge") :: any).Color, "its edge")
				for _, label in { refs.TitleBlaster, refs.TitleNew, refs.Name, refs.RarityText } do
					coloured(label:FindFirstChildOfClass("UIStroke").Color, label.Name .. "'s edge")
				end
				coloured((refs.Collected:FindFirstChild("Text") :: any):FindFirstChildOfClass("UIStroke").Color, "COLLECTED!'s edge")
			end
		end
	end)

	T.test("CrateOpeningView: Reduce motion: no flash at all; otherwise one, through the game's flash gap", function()
		local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
		local burst, reveal = Stage.T_BURST, Stage.T_RISE_END
		local function strongest(refs: any): number
			local most = 0
			for frame = math.floor(burst * 60) - 2, math.ceil(reveal * 60) do
				CrateOpeningView.update(refs, frame / 60, burst, reveal)
				if refs.Flash.Visible then
					most = math.max(most, 1 - refs.Flash.BackgroundTransparency)
				end
			end
			return most
		end
		RevealKit.resetFlash()
		local calm = CrateOpeningView.build()
		calm.Calm = true
		CrateOpeningView.claimFlash(calm, 100)
		T.falsy(calm.FlashOk, "no slot asked for")
		T.eq(strongest(calm), 0, "calm: never visible")
		calm.FlashOk = true -- (whatever the slot said)
		T.eq(strongest(calm), 0, "calm: never visible, whatever the slot said")
		local first = CrateOpeningView.build()
		CrateOpeningView.claimFlash(first, 100)
		T.truthy(first.FlashOk, "calm took no slot: the next opening's flash may go")
		T.lt(0.9, strongest(first), "the normal flash")
		local soon = CrateOpeningView.build()
		CrateOpeningView.claimFlash(soon, 100 + RevealKit.FlashGap / 2)
		T.falsy(soon.FlashOk, "too soon after another reveal's flash")
		T.eq(strongest(soon), 0, "so none")
		local later = CrateOpeningView.build()
		CrateOpeningView.claimFlash(later, 100 + RevealKit.FlashGap + 0.01)
		T.truthy(later.FlashOk, "a moment later it may")
		RevealKit.resetFlash()
	end)
end
