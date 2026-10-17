-- ElevatorView (pure UI builder) under Lune: the Buy page (price, BUY greyed
-- out when you can't afford it, the note), the floor cards (states, texts,
-- which buttons a gamepad can select), both layouts fitting a PC screen and
-- phones with 72-unit buttons, and the ride fade.
return function(T, Loader)
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ElevatorView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorView")

	local PRICE = MineFloors.Elevator.Price

	local function holder(button: any): any
		return button.Parent
	end

	-- the panel's size in design units
	local function panelSize(refs: any): (number, number)
		local size = refs.Panel.Size
		return size.X.Offset, size.Y.Offset
	end

	T.test("ElevatorView: builds closed on the Buy page", function()
		local refs = ElevatorView.build()
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.eq(refs.Mode, "Buy")
		T.truthy(refs.BuyPage.Visible, "Buy page")
		T.falsy(refs.FloorPage.Visible, "no floor cards")
		T.eq(refs.Title.Text, "ELEVATOR", "title")
		T.eq(refs.Pitch.Text, "Ride to every floor you have unlocked. Buy once, keep forever.", "pitch")
		T.eq(refs.Price.Text, Format.money(PRICE), "price")
		T.eq(#refs.Tiles, #MineFloors.List + 1, "a tile per floor + coming soon")
		T.eq(#refs.Cards, #MineFloors.List + 1, "a card per floor + coming soon")
		T.truthy(refs.Panel.SelectionGroup, "gamepad stays inside")
	end)

	T.test("ElevatorView: BUY is greyed out until you can afford it", function()
		local refs = ElevatorView.build()
		ElevatorView.setPurchase(refs, PRICE - 1, PRICE)
		T.falsy(refs.CanAfford, "can't afford")
		T.falsy(refs.BuyButton.Selectable, "not selectable")
		T.eq(refs.BuyButton.BackgroundColor3, ElevatorView.LockedColor, "grey")
		T.eq(refs.BuyButton.TextColor3, Theme.TextDim, "dim text")
		T.eq(refs.Note.Text, `You have {Format.money(PRICE - 1)}. You need {Format.money(1)} more.`, "note")
		ElevatorView.setPurchase(refs, PRICE, PRICE)
		T.truthy(refs.CanAfford, "exactly enough")
		T.truthy(refs.BuyButton.Selectable, "selectable")
		T.eq(refs.BuyButton.BackgroundColor3, Theme.Good, "green")
		T.eq(refs.Note.Text, `You have {Format.money(PRICE)}.`, "note")
		ElevatorView.setPurchase(refs, 0 / 0, PRICE)
		T.falsy(refs.CanAfford, "NaN coins")
		ElevatorView.setPurchase(refs, nil, PRICE)
		T.falsy(refs.CanAfford, "no coins yet")
	end)

	T.test("ElevatorView: floor entries follow the blaster level and the stop", function()
		local list = ElevatorView.entries(5, 2)
		T.eq(#list, 6, "five floors and coming soon")
		local states = {}
		for i, entry in list do
			states[i] = entry.State
		end
		T.eq(table.concat(states, ","), "Open,Here,Open,Locked,Locked,Soon", "states")
		T.eq(list[4].Requirement, "Blaster 7+", "requirement text")
		T.eq(list[4].Name, MineFloors.get(4).Name, "name")
		T.truthy(list[4].ElevatorOnly and list[5].ElevatorOnly, "4 and 5 by elevator only")
		T.falsy(list[1].ElevatorOnly or list[2].ElevatorOnly or list[3].ElevatorOnly, "1-3 walkable")
		T.eq(list[6].Name, "Coming soon")
		T.eq(list[6].Index, MineFloors.ComingSoon.Index)
		T.eq(list[6].Requirement, "Blaster " .. MineFloors.ComingSoon.MinBlaster .. "+")
		T.truthy(list[3].Met, "level 5 meets floor 3")
		T.falsy(list[4].Met, "level 5 doesn't meet floor 4")
		-- junk level reads as 1; no stop = nothing is "here"
		local fresh = ElevatorView.entries(0 / 0, nil)
		T.eq(fresh[1].State, "Open", "floor 1 always open")
		T.eq(fresh[2].State, "Locked", "floor 2 locked at 1")
		local maxed = ElevatorView.entries(10, nil)
		for i = 1, 5 do
			T.eq(maxed[i].State, "Open", "all open at 10: " .. i)
		end
		T.eq(maxed[6].State, "Soon", "coming soon stays locked")
	end)

	T.test("ElevatorView: the Floors page shows cards with GO only where you can ride", function()
		local refs = ElevatorView.build()
		ElevatorView.setMode(refs, "Floors")
		T.falsy(refs.BuyPage.Visible, "Buy page hidden")
		T.truthy(refs.FloorPage.Visible, "cards shown")
		ElevatorView.setFloors(refs, ElevatorView.entries(5, 2), 5)
		local texts = {}
		for i, card in refs.Cards do
			texts[i] = card.Button.Text
		end
		T.eq(table.concat(texts, ","), "GO,YOU ARE HERE,GO,LOCKED,LOCKED,COMING SOON", "button texts")
		for _, card in refs.Cards do
			T.eq(card.Button.Selectable, card.Entry.State == "Open", "selectable only when open: " .. card.Index)
		end
		T.eq(refs.Cards[1].Button.BackgroundColor3, Theme.Good, "GO is green")
		T.eq(refs.Cards[2].Stroke.Color, Theme.Accent, "the current floor stands out")
		T.eq(refs.Cards[4].Chip.Text, "Blaster 7+", "chip")
		T.eq(refs.Cards[4].Chip.BackgroundColor3, Theme.BadDark, "unmet chip is red")
		T.eq(refs.Cards[1].Chip.BackgroundColor3, Theme.GoodDark, "met chip is green")
		T.eq(refs.Cards[4].Tag.Text, "Elevator only", "tag")
		T.eq(refs.Cards[6].Number.Text, "?", "coming soon badge")
		T.eq(refs.Cards[4].Name.Text, MineFloors.get(4).Name, "floor name")
		T.eq(ElevatorView.firstGo(refs), refs.Cards[1].Button, "first GO for the gamepad")
		T.truthy(refs.Subtitle.Text:find("Lv 5", 1, true), "blaster level in the header")
		-- nothing to ride to
		ElevatorView.setFloors(refs, ElevatorView.entries(1, 1), 1)
		T.eq(ElevatorView.firstGo(refs), nil, "no GO")
	end)

	T.test("ElevatorView: messages replace the subtitle for a while", function()
		local refs = ElevatorView.build()
		ElevatorView.showMessage(refs, "You need $1 more.", Theme.Bad)
		T.truthy(refs.Message.Visible, "shown")
		T.falsy(refs.Subtitle.Visible, "subtitle hidden")
		T.eq(refs.Message.TextColor3, Theme.Bad)
		ElevatorView.hideMessage(refs)
		T.falsy(refs.Message.Visible, "hidden")
		T.truthy(refs.Subtitle.Visible, "subtitle back")
	end)

	-- every card button sits inside its card, cards inside the page
	local function checkCards(refs: any, label: string)
		local page = refs.FloorPage
		for _, card in refs.Cards do
			local f = card.Frame
			local x, y = f.Position.X.Offset, f.Position.Y.Offset
			local w, h = f.Size.X.Offset, f.Size.Y.Offset
			local pw, _ = panelSize(refs)
			T.le(x + w, pw - 32 + 0.5, label .. ": card inside the page width " .. card.Index)
			T.truthy(y >= 0, label .. ": card top " .. card.Index)
			local hold = holder(card.Button)
			local bh = hold.Size.Y.Offset
			T.le(10 + card.Badge.Size.Y.Offset + bh + 10, h, label .. ": badge + button fit card " .. card.Index)
		end
		T.truthy(page.Visible, label .. ": page shown")
	end

	T.test("ElevatorView: the PC layout fits 1280 x 690 design units", function()
		local refs = ElevatorView.build()
		ElevatorView.layout(refs, false, 1280, 690)
		local w, h = panelSize(refs)
		T.le(w, 1280 - 24, "Buy width")
		T.le(h, 690 - 16, "Buy height")
		ElevatorView.setMode(refs, "Floors")
		w, h = panelSize(refs)
		T.le(w, 1280 - 24, "Floors width")
		T.le(h, 690 - 16, "Floors height")
		checkCards(refs, "PC")
		T.truthy(refs.Hint.Visible, "hint on PC")
	end)

	T.test("ElevatorView: phones get the compact layout with 72-unit buttons", function()
		-- a 667 x 375 pt phone at uiScale 0.62, 36 pt top inset
		local maxW, maxH = 667 / 0.62, (375 - 36) / 0.62
		local refs = ElevatorView.build()
		ElevatorView.layout(refs, true, maxW, maxH)
		local w, h = panelSize(refs)
		T.le(w, maxW - 24, "Buy width")
		T.le(h, maxH - 16, "Buy height")
		T.truthy(holder(refs.BuyButton).Size.Y.Offset >= 72, "BUY is a thumb target")
		T.truthy(holder(refs.Close).Size.Y.Offset >= 64, "close is a thumb target")
		ElevatorView.setMode(refs, "Floors")
		w, h = panelSize(refs)
		T.le(w, maxW - 24, "Floors width")
		T.le(h, maxH - 16, "Floors height")
		for _, card in refs.Cards do
			T.truthy(holder(card.Button).Size.Y.Offset >= 72, "card button is a thumb target " .. card.Index)
		end
		checkCards(refs, "phone")
		T.falsy(refs.Hint.Visible, "no key hint on phones")
		-- a small 568 x 320 pt phone still fits (smaller cards, no tag line)
		local smallW, smallH = 568 / 0.62, (320 - 36) / 0.62
		ElevatorView.layout(refs, true, smallW, smallH)
		w, h = panelSize(refs)
		T.le(w, smallW - 24 + 0.5, "small width")
		T.le(h, math.max(380, smallH - 16) + 0.5, "small height")
		checkCards(refs, "small phone")
		for _, card in refs.Cards do
			T.truthy(holder(card.Button).Size.Y.Offset >= 60, "small phone button " .. card.Index)
		end
	end)

	T.test("ElevatorView: the ride fade covers the screen and names the floor", function()
		local fade = ElevatorView.buildFade()
		T.falsy(fade.Gui.Enabled, "off until a ride")
		T.truthy(fade.Gui.IgnoreGuiInset, "covers the top bar too")
		T.eq(fade.Black.Size.X.Scale, 1, "full width")
		T.eq(fade.Black.Size.Y.Scale, 1, "full height")
		T.eq(fade.Black.BackgroundTransparency, 1, "clear at first")
		T.eq(fade.Gui:FindFirstChildOfClass("UIScale"), nil, "no UIScale (would shrink the black layer)")
		ElevatorView.setFadeText(fade, 4, MineFloors.get(4).Name)
		T.eq(fade.Title.Text, "FLOOR 4")
		T.eq(fade.Name.Text, MineFloors.get(4).Name)
	end)
end
