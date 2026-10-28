-- HoverboardView (pure UI builder) under Lune: what each card offers (BUY / locked BUY /
-- EQUIP / EQUIPPED / Robux / COMING SOON), prices, speeds, the owned list from a State
-- snapshot, five cards in a row on a PC and phones with 72-unit buttons (3 + 2 when narrow),
-- every card inside the panel, the opening poses and RIDE / STOP.
return function(T, Loader)
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HoverboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HoverboardView")
	local roblox = require("@lune/roblox") :: any

	local B = HoverboardData.ById

	T.test("HoverboardView: card states from the save, coins and game pass ids", function()
		local none = {}
		local p1 = B.TimberDrifter.Price :: number
		T.eq(HoverboardView.cardState(B.TimberDrifter, none, "", p1 - 1), "BuyLocked", "not enough coins")
		T.eq(HoverboardView.cardState(B.TimberDrifter, none, "", p1), "Buy", "exactly enough")
		T.eq(HoverboardView.cardState(B.TimberDrifter, none, "", 0 / 0), "BuyLocked", "NaN coins")
		T.eq(HoverboardView.cardState(B.TimberDrifter, none, "", nil), "BuyLocked", "no coins")
		local owned = { TimberDrifter = true }
		T.eq(HoverboardView.cardState(B.TimberDrifter, owned, "", 0), "Equip", "owned")
		T.eq(HoverboardView.cardState(B.TimberDrifter, owned, "TimberDrifter", 0), "Equipped", "equipped")
		-- Robux boards: COMING SOON until the owner writes the game pass id
		local pass = MonetizationConfig.Entries.HoverboardCustom
		local old = pass.Id
		pass.Id = 0
		T.eq(HoverboardView.cardState(B.TerraForgeCustom, none, "", 1e12), "Soon", "no pass id")
		pass.Id = 777
		local realReady = HoverboardView.receiptsReady
		rawset(HoverboardView, "receiptsReady", function()
			return false
		end)
		T.eq(HoverboardView.cardState(B.TerraForgeCustom, none, "", 0), "Soon", "a real pass id, but the receipts gate is closed")
		rawset(HoverboardView, "receiptsReady", function()
			return true
		end)
		T.eq(HoverboardView.cardState(B.TerraForgeCustom, none, "", 0), "Robux", "a real pass id, receipts open")
		T.eq(HoverboardView.cardState(B.TerraForgeCustom, { TerraForgeCustom = true }, "", 0), "Equip", "owned Robux board")
		rawset(HoverboardView, "receiptsReady", realReady)
		pass.Id = old
	end)

	T.test("HoverboardView: texts", function()
		T.eq(HoverboardView.priceText(B.TimberDrifter), Format.money(B.TimberDrifter.Price :: number), "coin price")
		T.eq(HoverboardView.priceText(B.TerraForgeCustom), "49 R$", "Robux price")
		T.eq(HoverboardView.priceText(B.RoyalPhoenix), Format.money(B.RoyalPhoenix.Price :: number), "the Royal Phoenix costs coins now")
		T.eq(HoverboardView.speedText(B.CartCruiser), "SPEED 33", "speed")
		T.eq(HoverboardView.bonusText(B.TimberDrifter), `+{HoverboardData.speedBonus(B.TimberDrifter)}%`, "bonus")
		T.eq(HoverboardView.buttonText("Buy", B.TimberDrifter), "BUY")
		T.eq(HoverboardView.buttonText("BuyLocked", B.TimberDrifter), "BUY")
		T.eq(HoverboardView.buttonText("Equip", B.TimberDrifter), "EQUIP")
		T.eq(HoverboardView.buttonText("Equipped", B.TimberDrifter), "EQUIPPED")
		T.eq(HoverboardView.buttonText("Robux", B.TerraForgeCustom), "49")
		T.eq(HoverboardView.buttonText("Soon", B.TerraForgeCustom), "COMING SOON")
		local set = HoverboardView.ownedSet({ "TimberDrifter", "Nope", 5, "TerraForgeCustom" })
		T.truthy(set.TimberDrifter and set.TerraForgeCustom, "known ids")
		T.eq(set.Nope, nil, "unknown ids dropped")
		T.eq(next(HoverboardView.ownedSet("junk")), nil, "junk = nothing")
	end)

	local function panelSize(refs: any): (number, number)
		return refs.Root.Size.X.Offset, refs.Root.Size.Y.Offset
	end

	local function insidePanel(refs: any, label: string)
		local w, h = panelSize(refs)
		local page = refs.CardPage.Position
		for _, card in refs.Cards do
			local p, s = card.Frame.Position, card.Frame.Size
			local left = page.X.Offset + p.X.Offset - s.X.Offset / 2
			local top = page.Y.Offset + card.Frame:GetAttribute("BaseY") - s.Y.Offset / 2
			T.truthy(left >= 0 and left + s.X.Offset <= w + 0.5, `{label}: {card.Board.Id} inside the panel horizontally`)
			T.truthy(top >= 0 and top + s.Y.Offset <= h + 0.5, `{label}: {card.Board.Id} inside the panel vertically`)
			T.truthy(card.Look.Holder.Size.Y.Offset >= (if refs.Compact then 72 else 50), `{label}: {card.Board.Id} button height`)
			-- the words and the picture stay above the button
			local buttonTop = s.Y.Offset - 10 - card.Look.Holder.Size.Y.Offset
			for _, part in { card.PriceRow, card.SpeedChip, card.BonusChip, card.Name, card.ArtBack } do
				T.le(part.Position.Y.Offset + part.Size.Y.Offset, buttonTop + 0.5, `{label}: {card.Board.Id} {part.Name} above the button`)
				T.truthy(
					part.Position.X.Offset >= 0 and part.Position.X.Offset + part.Size.X.Offset <= s.X.Offset + 0.5,
					`{label}: {card.Board.Id} {part.Name} inside the card`
				)
			end
		end
	end

	T.test("HoverboardView: builds closed with a card per board, five in a row on a PC", function()
		local refs = HoverboardView.build()
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.eq(refs.Title.Text, "HOVERBOARDS", "title")
		T.eq(#refs.Cards, #HoverboardData.List, "a card per board")
		T.truthy(refs.Root.SelectionGroup, "gamepad stays inside")
		T.eq(refs.CloseLook.Style, "Close", "red X")
		for i, card in refs.Cards do
			T.eq(card.Board, HoverboardData.List[i], "card order = board order")
			T.eq(card.Ribbon ~= nil, card.Board.Kind == "Robux", card.Board.Id .. " ROBUX ribbon only on Robux boards")
			-- the live 3D board (PictureModels "board_<Id>": HoverboardBuilder in a ViewportFrame)
			local picture = card.Picture
			T.truthy(picture ~= nil, card.Board.Id .. " has its live 3D board")
			T.eq(picture:GetAttribute("Icon"), "board_" .. card.Board.Id, card.Board.Id .. " picture name")
			T.truthy(picture:FindFirstChild("View"):FindFirstChildOfClass("Model") ~= nil, card.Board.Id .. " model in the view")
			T.eq(#card.Canvas:GetChildren(), 1, card.Board.Id .. " no drawn stand-in (only its UIScale)")
			T.falsy(card.Face.Selectable, card.Board.Id .. " the card itself is not a gamepad stop")
		end
		-- without a model the board is drawn from Frames
		local canvas = roblox.Instance.new("Frame")
		HoverboardView.drawBoard(canvas, HoverboardData.List[1])
		T.truthy(#canvas:GetChildren() > 3, "the drawn stand-in")
		HoverboardView.layout(refs, false, 1600, 900)
		T.eq(refs.Columns, 5, "five in a row")
		insidePanel(refs, "PC")
		HoverboardView.layout(refs, false, 900, 700)
		T.eq(refs.Columns, 3, "narrow screens: 3 + 2")
		insidePanel(refs, "narrow")
	end)

	T.test("HoverboardView: phones get the compact layout with 72-unit buttons", function()
		local refs = HoverboardView.build(true)
		-- an iPhone 14 in landscape (844 x 390 pt) at the 0.62 phone scale
		HoverboardView.layout(refs, true, 844 / 0.62, (390 - 36) / 0.62)
		T.truthy(refs.Compact, "compact")
		local w, h = panelSize(refs)
		T.truthy(w <= 844 / 0.62 - 24 + 0.5 and h <= (390 - 36) / 0.62 - 16 + 0.5, "fits the phone screen")
		T.falsy(refs.Footer.Visible, "no footer on phones")
		T.falsy(refs.Scrolls, "everything shows")
		insidePanel(refs, "phone")
		-- a 667 x 375 pt phone: still no scrolling
		HoverboardView.layout(refs, true, 667 / 0.62, (375 - 36) / 0.62)
		T.falsy(refs.Scrolls, "667 x 375: everything shows")
		insidePanel(refs, "667 x 375")
		-- a small 568 x 320 pt phone: the cards keep their height and the page scrolls (the second row peeks in)
		local smallW, smallH = 568 / 0.62, (320 - 36) / 0.62
		HoverboardView.layout(refs, true, smallW, smallH)
		w, h = panelSize(refs)
		T.truthy(w <= smallW - 24 + 0.5 and h <= math.max(380, smallH - 16) + 0.5, "fits the small phone")
		T.truthy(refs.Scrolls and refs.CardPage.ScrollingEnabled, "568 x 320: the cards scroll")
		T.eq(refs.CardPage.ScrollingDirection, roblox.Enum.ScrollingDirection.Y, "up and down only")
		T.falsy(refs.CardPage.Selectable, "the gamepad selects the buttons, not the scroll")
		local page = refs.CardPage
		local pageW = w + page.Size.X.Offset
		for _, card in refs.Cards do
			local p, s = card.Frame.Position, card.Frame.Size
			T.truthy(
				p.X.Offset - s.X.Offset / 2 >= 0 and p.X.Offset + s.X.Offset / 2 <= pageW + 0.5,
				`{card.Board.Id} inside the page width`
			)
			T.le(
				card.Frame:GetAttribute("BaseY") + s.Y.Offset / 2,
				page.CanvasSize.Y.Offset + 0.5,
				`{card.Board.Id} inside the scroll canvas`
			)
			T.truthy(card.Look.Holder.Size.Y.Offset >= 72, `{card.Board.Id} button is a thumb target`)
			local buttonTop = s.Y.Offset - 10 - card.Look.Holder.Size.Y.Offset
			T.le(card.PriceRow.Position.Y.Offset + card.PriceRow.Size.Y.Offset, buttonTop + 0.5, `{card.Board.Id} price above the button`)
		end
	end)

	T.test("HoverboardView: setCards paints every card", function()
		local refs = HoverboardView.build()
		HoverboardView.setCards(refs, { TimberDrifter = true, CartCruiser = true }, "CartCruiser", 100)
		local byId = {}
		for _, card in refs.Cards do
			byId[card.Board.Id] = card
		end
		T.eq(byId.TimberDrifter.State, "Equip", "owned")
		T.eq(byId.CartCruiser.State, "Equipped", "equipped")
		T.truthy(byId.CartCruiser.Glow.Visible, "equipped glow")
		T.eq(byId.CartCruiser.Stroke.Color, roblox.Color3.fromRGB(255, 204, 64), "equipped: a gold outline")
		T.falsy(byId.TimberDrifter.Glow.Visible, "no glow on the others")
		T.falsy(byId.CartCruiser.Button.Selectable, "nothing to do on EQUIPPED")
		T.falsy(byId.TimberDrifter.PriceRow.Visible, "no price on owned boards")
		T.truthy(byId.TimberDrifter.Owned.Visible and byId.CartCruiser.Owned.Visible, "OWNED chips")
		T.falsy(byId.EmberglassGlider.Owned.Visible, "not owned: no chip")
		T.eq(byId.TimberDrifter.Look.Style, "Equip", "EQUIP")
		T.truthy(byId.CartCruiser.Look.Icons.Check.Visible, "EQUIPPED has a check")
		local mark = byId.TerraForgeCustom.Look.Row:FindFirstChild("Mark")
		T.eq(mark.Visible, byId.TerraForgeCustom.State == "Robux", "the robux mark only on the Robux price (Pop.price)")
		-- a Robux board's price is only on its green button: its price line shows one more perk
		for _, id in { "TerraForgeCustom" } do
			T.falsy(byId[id].PriceRow.Visible, id .. ": no second price")
			T.truthy(byId[id].Extra.Visible, id .. ": its perk instead")
			T.truthy(byId[id].Extra.Text ~= "" and not string.find(byId[id].Extra.Text, "R$", 1, true), id .. ": a perk, not a price")
		end
		T.falsy(byId.EmberglassGlider.Extra.Visible, "coin boards keep their price line")
		T.eq(byId.EmberglassGlider.State, "BuyLocked", "too expensive")
		T.truthy(byId.EmberglassGlider.Look.Icons.Lock.Visible, "lock icon")
		T.truthy(byId.EmberglassGlider.PriceRow.Visible, "price shown")
		T.eq(byId.EmberglassGlider.Price.Text, Format.money(B.EmberglassGlider.Price :: number), "price text")
		T.eq(
			byId.TerraForgeCustom.Look.Label.Text,
			if HoverboardData.canPrompt(B.TerraForgeCustom) then "49" else "COMING SOON",
			"Robux card"
		)
		T.eq(HoverboardView.firstButton(refs), byId.TimberDrifter.Button, "a gamepad lands on the first useful card")
	end)

	T.test("HoverboardView: the opening animation pops the panel and drops the cards in", function()
		local refs = HoverboardView.build()
		HoverboardView.pose(refs, 0)
		T.truthy(refs.Pop.Scale < 1, "starts small")
		for _, card in refs.Cards do
			T.falsy(card.Frame.Visible, "cards hidden at the start")
		end
		HoverboardView.pose(refs, HoverboardView.OpenTime)
		T.near(refs.Pop.Scale, 1, 1e-6, "full size")
		for _, card in refs.Cards do
			T.truthy(card.Frame.Visible, "cards shown")
			T.near(card.Scale.Scale, 1, 1e-6, "full card size")
		end
	end)

	T.test("HoverboardView: RIDE / STOP (the panel opens from the side menu's HOVER)", function()
		local parent = roblox.Instance.new("Frame")
		local ride = HoverboardView.rideButton(parent)
		T.eq(ride.Label.Text, "RIDE", "walking")
		T.truthy(ride.Key.Visible, "the H chip on a keyboard")
		T.eq(ride.Key.Text, "H", "H")
		HoverboardView.setRiding(ride, true, "", "rbxasset://glyph")
		T.eq(ride.Label.Text, "STOP", "riding")
		T.truthy(ride.Glyph.Visible, "gamepad glyph")
		T.falsy(ride.Key.Visible, "no key chip with a glyph")
		HoverboardView.setRiding(ride, false, "", "")
		T.falsy(ride.Key.Visible, "touch: no chip")
		T.falsy(ride.Glyph.Visible, "touch: no glyph")
		T.truthy(ride.Button.Size.X.Offset >= 72, "a big touch target")
	end)
end
