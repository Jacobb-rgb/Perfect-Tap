-- ElevatorView (pure UI builder) under Lune: the Buy page (price, BUY greyed
-- out with a lock when you can't afford it, the note), the floor cards
-- (states, texts, colours, mode lines, which buttons a gamepad can select),
-- the header's coloured subtitle, the footer hint, both layouts fitting a PC
-- screen and phones with 72-unit buttons, the opening animation's poses and
-- the ride fade. (The side menu's ELEVATOR button is main's: tests/SideMenu.spec.)
return function(T, Loader)
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ElevatorView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorView")
	local roblox = require("@lune/roblox") :: any

	local PRICE = MineFloors.Elevator.Price

	-- the panel's size in design units
	local function panelSize(refs: any): (number, number)
		local size = refs.Root.Size
		return size.X.Offset, size.Y.Offset
	end

	local function midColor(gradient: any): any
		return gradient.Color.Keypoints[2].Value
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
		T.eq(#refs.Tiles, #MineFloors.List + 1, "a chip per floor + coming soon")
		T.eq(#refs.Cards, #MineFloors.List + 1, "a card per floor + coming soon")
		T.truthy(refs.Root.SelectionGroup, "gamepad stays inside")
		T.truthy(refs.Panel.ClipsDescendants, "the doors stay inside the frame")
		T.eq(refs.Close.Parent, refs.CloseLook.Holder, "X on its lip")
		T.eq(refs.CloseLook.Style, "Close", "red X")
		T.eq(refs.Caption.Text, "Floors 4, 5 and 6 can only be reached by elevator.", "caption")
	end)

	T.test("ElevatorView: BUY is greyed out with a lock until you can afford it", function()
		local refs = ElevatorView.build()
		ElevatorView.setPurchase(refs, PRICE - 1, PRICE)
		T.falsy(refs.CanAfford, "can't afford")
		T.falsy(refs.BuyButton.Selectable, "not selectable")
		T.eq(refs.BuyLook.Style, "BuyLocked", "slate")
		T.truthy(refs.BuyLook.Icons.Lock.Visible, "lock icon")
		T.eq(refs.BuyLook.Label.Text, "BUY")
		T.eq(refs.Note.Text, `You have {Format.money(PRICE - 1)}. You need {Format.money(1)} more.`, "note")
		ElevatorView.setPurchase(refs, PRICE, PRICE)
		T.truthy(refs.CanAfford, "exactly enough")
		T.truthy(refs.BuyButton.Selectable, "selectable")
		T.eq(refs.BuyLook.Style, "Buy", "green")
		T.falsy(refs.BuyLook.Icons.Lock.Visible, "no lock")
		T.eq(midColor(refs.BuyLook.Gradient), ElevatorView.ButtonStyles.Buy.Mid, "green face")
		T.eq(refs.Note.Text, `You have {Format.money(PRICE)}.`, "note")
		ElevatorView.setPurchase(refs, 0 / 0, PRICE)
		T.falsy(refs.CanAfford, "NaN coins")
		ElevatorView.setPurchase(refs, nil, PRICE)
		T.falsy(refs.CanAfford, "no coins yet")
	end)

	T.test("ElevatorView: floor entries follow the blaster level and the floor you are on", function()
		local list = ElevatorView.entries(5, 2)
		T.eq(#list, 7, "six floors and coming soon")
		local states = {}
		for i, entry in list do
			states[i] = entry.State
		end
		T.eq(table.concat(states, ","), "Open,Here,Open,Locked,Locked,Locked,Soon", "states")
		T.eq(list[4].Requirement, "Blaster 7+", "requirement text")
		T.eq(list[4].Name, MineFloors.get(4).Name, "name")
		T.eq(list[5].Name, "Stormglass Rift", "the Rift is floor 5")
		T.eq(list[5].Requirement, "Blaster 8+", "the Rift's gate")
		T.eq(list[6].Name, "Heartstone Core", "the core is floor 6")
		T.truthy(list[4].ElevatorOnly and list[5].ElevatorOnly and list[6].ElevatorOnly, "4-6 by elevator only")
		T.falsy(list[1].ElevatorOnly or list[2].ElevatorOnly or list[3].ElevatorOnly, "1-3 walkable")
		T.eq(list[7].Name, "Coming soon")
		T.eq(list[7].Index, MineFloors.ComingSoon.Index)
		T.eq(list[7].Requirement, "Blaster " .. MineFloors.ComingSoon.MinBlaster .. "+")
		for i = 1, 6 do
			T.eq(list[i].Color, ElevatorView.FloorColors[i], "floor colour " .. i)
		end
		T.eq(list[7].Color, ElevatorView.SoonColor, "grey coming soon")
		T.truthy(list[3].Met, "level 5 meets floor 3")
		T.falsy(list[4].Met, "level 5 doesn't meet floor 4")
		-- junk level reads as 1; no floor = nothing is "here"
		local fresh = ElevatorView.entries(0 / 0, nil)
		T.eq(fresh[1].State, "Open", "floor 1 always open")
		T.eq(fresh[2].State, "Locked", "floor 2 locked at 1")
		local maxed = ElevatorView.entries(10, nil)
		for i = 1, 6 do
			T.eq(maxed[i].State, "Open", "all open at 10: " .. i)
		end
		T.eq(maxed[7].State, "Soon", "coming soon stays locked")
		T.eq(ElevatorView.entries(8, nil)[5].State, "Open", "blaster 8 opens the Rift")
		T.eq(ElevatorView.entries(8, nil)[6].State, "Locked", "but not the core")
	end)

	T.test("ElevatorView: the cards look like the mock", function()
		local refs = ElevatorView.build()
		ElevatorView.setMode(refs, "Floors")
		T.falsy(refs.BuyPage.Visible, "Buy page hidden")
		T.truthy(refs.FloorPage.Visible, "cards shown")
		ElevatorView.setFloors(refs, ElevatorView.entries(7, 3), 7)
		local texts, styles = {}, {}
		for i, card in refs.Cards do
			texts[i] = card.Look.Label.Text
			styles[i] = card.Look.Style
		end
		T.eq(table.concat(texts, ","), "GO,GO,YOU ARE HERE,GO,LOCKED,LOCKED,COMING SOON", "button texts")
		T.eq(table.concat(styles, ","), "Go,Go,Here,Go,Locked,Locked,Soon", "button styles")
		local icons = { "Arrow", "Arrow", "Pin", "Arrow", "Lock", "Lock", "Clock" }
		local gold = roblox.Color3.fromRGB(255, 204, 64)
		for i, card in refs.Cards do
			T.eq(card.Button.Selectable, card.Entry.State == "Open", "selectable only when open: " .. card.Index)
			T.truthy(card.Look.Icons[icons[i]].Visible, "button icon " .. icons[i])
			local here = card.Entry.State == "Here"
			T.eq(card.Stroke.Color, if here then gold else roblox.Color3.fromRGB(14, 14, 18), "Pop black edge, gold on the current floor")
			-- painted in the floor's colour (Pop.card: its light top is the colour lifted toward white)
			local top = card.Face:FindFirstChild("Paint").Color.Keypoints[1].Value
			local want = ElevatorView.paintFrom(card.Entry.Color).Top
			T.near(top.R + top.G + top.B, want.R + want.G + want.B, 1e-3, "card in the floor's colour " .. i)
			T.falsy(card.Face.Selectable, "the card itself is not a gamepad stop " .. i)
			local closed = card.Entry.State == "Locked" or card.Entry.State == "Soon"
			T.eq(card.Shade.Visible, closed, "the LOCKED shade " .. i)
			T.eq(card.Pill.Visible, closed, "the requirement shows on a locked card " .. i)
		end
		T.truthy(refs.Cards[3].Glow.Visible, "the current floor glows")
		T.falsy(refs.Cards[1].Glow.Visible, "the others don't")
		T.eq(refs.Cards[3].Stroke.Thickness, 4, "brighter, thicker frame")
		T.eq(refs.Cards[5].Chip.Text, "Blaster 8+", "pill")
		T.eq(refs.Cards[6].Chip.Text, "Blaster 9+", "pill")
		T.truthy(midColor(refs.Cards[5].ChipGradient).R > 0.8, "unmet pill is red")
		T.truthy(midColor(refs.Cards[1].ChipGradient).G > 0.6, "met pill is green")
		T.eq(midColor(refs.Cards[7].ChipGradient), ElevatorView.SoonColor, "coming soon pill is grey")
		-- the ore rarity chips: a chip per rarity on the floor, in the rarity's colour
		T.eq(table.concat(ElevatorView.floorRarities(1), ","), "Common,Uncommon", "floor 1's rarities")
		T.eq(#ElevatorView.floorRarities(99), 0, "no such floor: no chips")
		for i, card in refs.Cards do
			local shown = {}
			for _, chip in card.RarityChips do
				if chip.Visible then
					table.insert(shown, (chip:FindFirstChild("Label") :: any).Text)
				end
			end
			T.eq(table.concat(shown, ","), table.concat(card.Entry.Rarities, ","), "rarity chips " .. i)
		end
		T.eq(#refs.Cards[7].Entry.Rarities, 0, "coming soon: no ores yet")
		T.eq(refs.Cards[6].Entry.Rarities[#refs.Cards[6].Entry.Rarities], "Mythic", "the core has Mythic ores")
		T.eq(refs.Cards[1].ModeText.Text, "Walk or ride")
		T.truthy(refs.Cards[1].ModeIcons.Walk.Visible, "walker")
		T.eq(refs.Cards[4].ModeText.Text, "Elevator only")
		T.truthy(refs.Cards[4].ModeIcons.Crown.Visible, "crown")
		T.eq(refs.Cards[7].ModeText.Text, "Next update")
		T.truthy(refs.Cards[7].ModeIcons.Clock.Visible, "clock")
		T.eq(refs.Cards[7].Number.Text, "?", "coming soon badge")
		T.eq(refs.Cards[5].Name.Text, "Stormglass Rift", "the Rift's card")
		T.truthy(
			refs.Cards[5].Canvas:FindFirstChild("Bolt") and refs.Cards[5].Canvas:FindFirstChild("Belly"),
			"the Rift's art: a storm cloud and a bolt"
		)
		T.eq(refs.Cards[4].Name.Text, MineFloors.get(4).Name, "floor name")
		T.eq(ElevatorView.firstGo(refs), refs.Cards[1].Button, "first GO for the gamepad")
		for _, card in refs.Cards do
			T.truthy(#card.Canvas:GetChildren() > 2, "themed art on card " .. card.Index)
		end
		-- nothing to ride to
		ElevatorView.setFloors(refs, ElevatorView.entries(1, 1), 1)
		T.eq(ElevatorView.firstGo(refs), nil, "no GO")
	end)

	T.test("ElevatorView: the subtitle shows the blaster level in yellow", function()
		local refs = ElevatorView.build()
		ElevatorView.setMode(refs, "Floors")
		ElevatorView.setFloors(refs, ElevatorView.entries(7, nil), 7)
		local parts = refs.SubtitleParts
		T.eq(parts[1].Text, "Your blaster: ")
		T.eq(parts[2].Text, "Lv 7.")
		T.eq(parts[3].Text, " Forge better blasters to unlock deeper floors.")
		T.truthy(parts[2].TextColor3.R > 0.9 and parts[2].TextColor3.B < 0.4, "yellow level")
		for _, part in parts do
			T.truthy(part.Size.X.Offset >= ElevatorView.measure(part.Text, part.TextSize), "each part fits its text")
		end
		ElevatorView.setMode(refs, "Buy")
		T.truthy(parts[1].Visible and not parts[2].Visible and not parts[3].Visible, "one part on the Buy page")
		ElevatorView.showMessage(refs, "You need $1 more.", roblox.Color3.new(1, 0, 0))
		T.truthy(refs.Message.Visible, "message shown")
		T.falsy(refs.Subtitle.Visible, "subtitle hidden")
		ElevatorView.hideMessage(refs)
		T.falsy(refs.Message.Visible, "hidden")
		T.truthy(refs.Subtitle.Visible, "subtitle back")
	end)

	T.test("ElevatorView: text widths and the footer hint", function()
		T.truthy(ElevatorView.measure("GO", 24) > 20, "measures")
		T.near(ElevatorView.measure("ab", 100), ElevatorView.measure("a", 100) + ElevatorView.measure("b", 100), 1e-6, "adds up")
		T.truthy(ElevatorView.measure("ELEVATOR", 50, true) > 0, "title font")
		local saved = ElevatorView.Measure
		ElevatorView.Measure = function(text: string, size: number)
			return #text * size
		end
		T.eq(ElevatorView.measure("abc", 10), 30, "the game's measure wins")
		ElevatorView.Measure = function()
			error("no TextService")
		end
		T.truthy(ElevatorView.measure("abc", 10) > 0, "a failing measure falls back")
		ElevatorView.Measure = saved
		local refs = ElevatorView.build()
		ElevatorView.setHint(refs, "Mouse", "Click GO to ride · Backspace: close")
		T.truthy(refs.HintIcons.Mouse.Visible and not refs.HintIcons.Touch.Visible and not refs.HintGlyph.Visible, "mouse icon")
		T.truthy(refs.Footer.Size.X.Offset > ElevatorView.measure(refs.Hint.Text, refs.Hint.TextSize), "pill fits the text")
		ElevatorView.setHint(refs, "Gamepad", "Choose a floor · B: close")
		T.truthy(refs.HintGlyph.Visible and not refs.HintIcons.Mouse.Visible, "gamepad glyph")
		ElevatorView.setHint(refs, "Touch", "Tap GO to ride")
		T.truthy(refs.HintIcons.Touch.Visible, "tap icon")
	end)

	-- every card's badge, name and button fit inside the card; the cards fit the page's width
	-- (no sideways scroll), the first two rows show without scrolling, the rest is in the
	-- scroll's canvas; the page sits inside the panel
	local function checkCards(refs: any, label: string)
		local pw, ph = panelSize(refs)
		local page = refs.FloorPage
		local pageW = pw + page.Size.X.Offset
		local pageH = ph + page.Size.Y.Offset
		T.truthy(page.Position.X.Offset >= 0 and page.Position.X.Offset + pageW <= pw + 0.5, label .. ": page inside the panel width")
		T.truthy(page.Position.Y.Offset >= 0 and page.Position.Y.Offset + pageH <= ph + 0.5, label .. ": page inside the panel height")
		local canvasH = math.max(refs.FloorScroll.CanvasSize.Y.Offset, pageH)
		for i, card in refs.Cards do
			local f = card.Frame
			local w, h = f.Size.X.Offset, f.Size.Y.Offset
			local x = f.Position.X.Offset - w / 2
			local y = f.Position.Y.Offset - h / 2
			T.truthy(x >= 0 and x + w <= pageW + 0.5, label .. ": card inside the page width " .. card.Index)
			T.truthy(y >= 0 and y + h <= canvasH + 0.5, label .. ": card inside the scroll canvas " .. card.Index)
			if math.floor((i - 1) / refs.Columns) < 2 then
				T.truthy(y + h <= pageH + 0.5, label .. ": card shows without scrolling " .. card.Index)
			end
			local bh = card.Look.Holder.Size.Y.Offset
			T.le(12 + card.Badge.Size.Y.Offset + bh + 12, h, label .. ": badge + button fit card " .. card.Index)
			local room = w - (12 + card.Badge.Size.Y.Offset + 12) - 10
			T.le(ElevatorView.measure(card.Name.Text, card.Name.TextSize), room + 0.5, label .. ": the name fits card " .. card.Index)
			T.truthy(card.Name.TextSize >= ElevatorView.MinNameSize, label .. ": the name stays readable " .. card.Index)
		end
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
		T.eq(refs.Columns, 4, "PC: four cards a row (4 + 3)")
		T.falsy(refs.FloorScroll.ScrollingEnabled, "PC: every card shows, nothing scrolls")
		local first, last = refs.Cards[5].Frame.Position.X.Offset, refs.Cards[7].Frame.Position.X.Offset
		T.truthy(
			first > refs.Cards[1].Frame.Position.X.Offset and last < refs.Cards[4].Frame.Position.X.Offset,
			"PC: the short last row sits in the middle"
		)
		T.truthy(refs.Footer.Visible, "footer pill on PC")
	end)

	T.test("ElevatorView: phones get the compact layout with 72-unit buttons", function()
		-- a 667 x 375 pt phone at uiScale 0.62, 36 pt top inset
		local maxW, maxH = 667 / 0.62, (375 - 36) / 0.62
		local refs = ElevatorView.build()
		ElevatorView.layout(refs, true, maxW, maxH)
		local w, h = panelSize(refs)
		T.le(w, maxW - 24, "Buy width")
		T.le(h, maxH - 16, "Buy height")
		T.truthy(refs.BuyLook.Holder.Size.Y.Offset >= 72, "BUY is a thumb target")
		T.truthy(refs.CloseLook.Holder.Size.Y.Offset >= 64, "close is a thumb target")
		ElevatorView.setMode(refs, "Floors")
		w, h = panelSize(refs)
		T.le(w, maxW - 24, "Floors width")
		T.le(h, maxH - 16, "Floors height")
		for _, card in refs.Cards do
			T.truthy(card.Look.Holder.Size.Y.Offset >= 72, "card button is a thumb target " .. card.Index)
		end
		checkCards(refs, "phone")
		T.eq(refs.Columns, 3, "phone: three cards a row")
		T.truthy(refs.FloorScroll.ScrollingEnabled, "phone: the last row scrolls into view")
		T.eq(refs.FloorScroll.ScrollingDirection, roblox.Enum.ScrollingDirection.Y, "up and down only")
		T.falsy(refs.FloorScroll.Selectable, "the gamepad selects the buttons, not the scroll")
		T.falsy(refs.Footer.Visible, "no key hint on phones")
		-- a small 568 x 320 pt phone still fits (smaller cards, no mode line)
		local smallW, smallH = 568 / 0.62, (320 - 36) / 0.62
		ElevatorView.layout(refs, true, smallW, smallH)
		w, h = panelSize(refs)
		T.le(w, smallW - 24 + 0.5, "small width")
		T.le(h, math.max(380, smallH - 16) + 0.5, "small height")
		checkCards(refs, "small phone")
		for _, card in refs.Cards do
			T.truthy(card.Look.Holder.Size.Y.Offset >= 60, "small phone button " .. card.Index)
		end
	end)

	T.test("ElevatorView: the opening animation parts the doors, pops the panel and drops the cards", function()
		local refs = ElevatorView.build()
		ElevatorView.setMode(refs, "Floors")
		T.truthy(ElevatorView.OpenTime >= 0.4 and ElevatorView.OpenTime <= 0.6, "about half a second")
		ElevatorView.pose(refs, 0)
		T.truthy(refs.Doors.Visible, "doors shut")
		T.eq(refs.DoorLeft.Position.X.Scale, 0, "left door closed")
		T.eq(refs.DoorRight.Position.X.Scale, 1, "right door closed")
		T.truthy(refs.Pop.Scale < 0.95, "panel small")
		for _, card in refs.Cards do
			T.falsy(card.Frame.Visible, "cards not in yet")
		end
		ElevatorView.pose(refs, 0.22)
		T.truthy(refs.DoorLeft.Position.X.Scale < 0 and refs.DoorLeft.Position.X.Scale > -0.56, "doors parting")
		T.truthy(refs.Pop.Scale > 1, "overshoot")
		T.truthy(refs.Cards[1].Frame.Visible, "first card dropping")
		T.falsy(refs.Cards[#refs.Cards].Frame.Visible, "last card waits")
		local dropping = refs.Cards[1].Frame.Position.Y.Offset < refs.DropIns.Floors[1].Base.Y.Offset
		T.truthy(dropping, "the first card comes from above")
		ElevatorView.pose(refs, ElevatorView.OpenTime)
		T.falsy(refs.Doors.Visible, "doors gone")
		T.near(refs.Pop.Scale, 1, 1e-6, "panel at rest")
		for i, card in refs.Cards do
			T.truthy(card.Frame.Visible, "card in " .. i)
			T.eq(card.Frame.Position, refs.DropIns.Floors[i].Base, "card at rest " .. i)
			T.near(card.Scale.Scale, 1, 1e-6, "card full size " .. i)
		end
		-- the Buy page drops its chips, price and BUY
		ElevatorView.setMode(refs, "Buy")
		ElevatorView.pose(refs, 0)
		T.falsy(refs.PriceBox.Visible, "price not in yet")
		ElevatorView.pose(refs, ElevatorView.OpenTime)
		T.truthy(refs.PriceBox.Visible and refs.BuyLook.Holder.Visible, "price and BUY in")
		-- a layout keeps the pose
		ElevatorView.pose(refs, 0.1)
		ElevatorView.layout(refs, false, 1280, 690)
		T.near(refs.PoseTime, 0.1, 1e-6, "pose kept")
		T.truthy(refs.Doors.Visible, "doors still shown")
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
