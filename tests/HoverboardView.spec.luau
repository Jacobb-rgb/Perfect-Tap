-- HoverboardView (pure UI builder) under Lune: what each board offers (BUY / locked BUY /
-- EQUIP / EQUIPPED / Robux / COMING SOON), prices, speeds, the owned list from a State
-- snapshot, the golem inventory's layout (a grid of reel cards, 3 + 2, and the picked
-- board's detail card with its one action button) on a PC and on phones (72-unit
-- buttons, 568 x 320 pt fits), the tags, the picked card, the gamepad's start and links,
-- the detail's 3D board, the opening poses and RIDE / STOP.
return function(T, Loader)
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HoverboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HoverboardView")
	local GolemView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemView")
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
		T.eq(HoverboardView.speedText(B.CartCruiser), "SPEED 27", "speed")
		T.eq(HoverboardView.bonusText(B.TimberDrifter), `+{HoverboardData.speedBonus(B.TimberDrifter)}%`, "bonus")
		T.eq(HoverboardView.buttonText("Buy", B.TimberDrifter), "BUY")
		T.eq(HoverboardView.buttonText("BuyLocked", B.TimberDrifter), "BUY")
		T.eq(HoverboardView.buttonText("Equip", B.TimberDrifter), "EQUIP")
		T.eq(HoverboardView.buttonText("Equipped", B.TimberDrifter), "EQUIPPED")
		T.eq(HoverboardView.buttonText("Robux", B.TerraForgeCustom), "49")
		T.eq(HoverboardView.buttonText("Soon", B.TerraForgeCustom), "COMING SOON")
		T.eq(HoverboardView.amountText("Buy", B.CartCruiser), Format.money(B.CartCruiser.Price :: number), "BUY shows the price")
		T.eq(HoverboardView.amountText("BuyLocked", B.CartCruiser), Format.money(B.CartCruiser.Price :: number), "also greyed")
		T.eq(HoverboardView.amountText("Equip", B.CartCruiser), "", "no price once owned")
		T.eq(HoverboardView.kindText(B.CartCruiser), "COIN BOARD")
		T.eq(HoverboardView.kindText(B.TerraForgeCustom), "ROBUX BOARD")
		T.eq(HoverboardView.tagText(B.CartCruiser, true), "OWNED")
		T.eq(HoverboardView.tagText(B.CartCruiser, false), Format.money(B.CartCruiser.Price :: number), "the price tag")
		T.eq(HoverboardView.tagText(B.TerraForgeCustom, false), "ROBUX")
		local set = HoverboardView.ownedSet({ "TimberDrifter", "Nope", 5, "TerraForgeCustom" })
		T.truthy(set.TimberDrifter and set.TerraForgeCustom, "known ids")
		T.eq(set.Nope, nil, "unknown ids dropped")
		T.eq(next(HoverboardView.ownedSet("junk")), nil, "junk = nothing")
		T.eq(HoverboardView.countText(set), `2 / {#HoverboardData.List}`, "the count chip")
		T.eq(HoverboardView.defaultBoard("CartCruiser"), "CartCruiser", "the equipped board first")
		T.eq(HoverboardView.defaultBoard(""), HoverboardData.List[1].Id, "else the first board")
		T.eq(HoverboardView.defaultBoard("Gone"), HoverboardData.List[1].Id, "an unknown id: the first board")
	end)

	T.test("HoverboardView: the grid's cells are 3 + 2 and fill the well", function()
		local cells = HoverboardView.cells(600, 450, 5)
		T.eq(#cells, 5, "a cell per board")
		for i = 1, 3 do
			T.eq(cells[i][2], cells[1][2], "three on top")
		end
		T.eq(cells[4][2], cells[5][2], "two under them")
		T.truthy(cells[4][2] > cells[1][2] + cells[1][4], "the second row is below the first")
		T.truthy(cells[4][3] > cells[1][3], "the bottom cards are wider")
		for i, c in cells do
			T.truthy(c[1] >= 0 and c[1] + c[3] <= 600 and c[2] >= 0 and c[2] + c[4] <= 450, `cell {i} inside the well`)
			for j, d in cells do
				if j > i then
					local apart = c[1] + c[3] <= d[1] or d[1] + d[3] <= c[1] or c[2] + c[4] <= d[2] or d[2] + d[4] <= c[2]
					T.truthy(apart, `cells {i} and {j} don't overlap`)
				end
			end
		end
		-- the row fills the well (only the rounding is left over)
		local last = cells[3]
		T.truthy(600 - (last[1] + last[3]) <= 6 + 2, "the top row reaches the right edge")
	end)

	local function bounds(object: any): (number, number, number, number)
		return object.Position.X.Offset, object.Position.Y.Offset, object.Size.X.Offset, object.Size.Y.Offset
	end

	-- Everything in its place for a layout: the well and the detail inside the window, every card
	-- inside the well, its picture and words inside the card, the action button inside the detail.
	local function checkLayout(refs: any, label: string, buttonMin: number)
		local w, h = refs.Root.Size.X.Offset, refs.Root.Size.Y.Offset
		local wx, wy, ww, wh = bounds(refs.GridWell)
		T.truthy(wx >= 0 and wy >= 0 and wx + ww <= w and wy + wh <= h, `{label}: the grid's well inside the window`)
		local dx, dy, dw, dh = bounds(refs.Detail)
		T.truthy(dx >= wx + ww and dx + dw <= w and dy >= 0 and dy + dh <= h, `{label}: the detail right of the grid, inside the window`)
		for _, card in refs.Cards do
			local s = card.Frame.Size
			local x = card.Frame.Position.X.Offset - s.X.Offset / 2
			local y = card.Frame:GetAttribute("BaseY") - s.Y.Offset / 2
			T.truthy(
				x >= 0 and y >= 0 and x + s.X.Offset <= ww + 0.5 and y + s.Y.Offset <= wh + 0.5,
				`{label}: {card.Board.Id} inside the well`
			)
			T.truthy(s.X.Offset >= buttonMin and s.Y.Offset >= buttonMin, `{label}: {card.Board.Id} is a big enough target`)
			-- the name above the picture's middle, the bottom line under it
			local cy = card.ArtBack.Position.Y.Offset
			T.le(card.Name.Position.Y.Offset + card.Name.Size.Y.Offset, cy, `{label}: {card.Board.Id} name above the picture`)
			T.truthy(card.Name.Size.Y.Offset >= 12, `{label}: {card.Board.Id} name box`)
		end
		local holder = refs.Action.Parent
		local ax, ay, aw, ah = bounds(holder)
		T.truthy(ax >= 0 and ay >= 0 and ax + aw <= dw and ay + ah <= dh, `{label}: the action button inside the detail`)
		T.truthy(ah >= buttonMin, `{label}: the action button height`)
		local cx, cyy, cw, ch = bounds(refs.Close.Parent)
		T.truthy(ch >= buttonMin and cw >= buttonMin, `{label}: the X is a big enough target`)
		T.truthy(cyy >= 0 and cx <= 0, `{label}: the X sits in the band (right anchored)`)
		-- the detail's texts stay above its button
		for _, part in { refs.DetailName, refs.DetailKind, refs.DetailSpeed, refs.DetailBonus } do
			T.le(part.Position.Y.Offset + part.Size.Y.Offset, ay + 0.5, `{label}: {part.Name} above the button`)
		end
		if refs.DetailText.Visible then
			T.le(refs.DetailText.Position.Y.Offset + refs.DetailText.Size.Y.Offset, ay + 0.5, `{label}: the description above the button`)
		end
		for _, perk in refs.DetailPerks do
			if perk.Visible then
				T.le(perk.Position.Y.Offset + perk.Size.Y.Offset, ay + 0.5, `{label}: {perk.Name} above the button`)
			end
		end
	end

	T.test("HoverboardView: builds closed like the golem inventory, a reel card per board", function()
		local refs = HoverboardView.build()
		T.eq(refs.Gui.Name, "TerraForgeHoverboards", "the ScreenGui's name")
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.truthy(refs.Gui:GetAttribute("PopSkin"), "never the LightSkin")
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.eq(refs.Title.Text, "HOVERBOARDS", "title")
		T.truthy(refs.Root:FindFirstChild("TitleShadow") ~= nil, "the title's 3D shadow")
		T.truthy(refs.Root:FindFirstChild("Band") ~= nil, "the header band")
		T.eq(#refs.Cards, #HoverboardData.List, "a card per board")
		T.truthy(refs.Root.SelectionGroup, "gamepad stays inside")
		T.eq(refs.Close.Text, "X", "red X")
		for i, card in refs.Cards do
			T.eq(card.Board, HoverboardData.List[i], "card order = board order")
			T.truthy(card.Button.Selectable, card.Board.Id .. " the card is a gamepad stop (it picks the board)")
			T.truthy(card.Button:FindFirstChild("Lattice") ~= nil, card.Board.Id .. " the reels' lattice")
			-- the live 3D board (PictureModels "board_<Id>": HoverboardBuilder in a ViewportFrame)
			local picture = card.Picture
			T.truthy(picture ~= nil, card.Board.Id .. " has its live 3D board")
			T.eq(picture:GetAttribute("Icon"), "board_" .. card.Board.Id, card.Board.Id .. " picture name")
			T.truthy(picture:FindFirstChild("View"):FindFirstChildOfClass("Model") ~= nil, card.Board.Id .. " model in the view")
			T.eq(#card.Canvas:GetChildren(), 1, card.Board.Id .. " no drawn stand-in (only its UIScale)")
		end
		-- without a model the board is drawn from Frames
		local canvas = roblox.Instance.new("Frame")
		HoverboardView.drawBoard(canvas, HoverboardData.List[1])
		T.truthy(#canvas:GetChildren() > 3, "the drawn stand-in")
		HoverboardView.layout(refs, false, 1600 / 1.25, 900 / 1.25)
		checkLayout(refs, "PC", 50)
		HoverboardView.layout(refs, false, 1024, 600)
		checkLayout(refs, "small PC", 50)
	end)

	T.test("HoverboardView: phones get the compact layout (72-unit buttons, 568 x 320 fits)", function()
		local refs = HoverboardView.build(true)
		HoverboardView.setHint(refs, "Touch", "Tap a board to see it")
		for _, size in { { 844, 390 }, { 667, 375 }, { 568, 320 } } do
			local label = `{size[1]} x {size[2]}`
			local maxW, maxH = size[1] / 0.62, (size[2] - 36) / 0.62
			HoverboardView.layout(refs, true, maxW, maxH)
			T.truthy(refs.Compact, "compact")
			local w, h = refs.Root.Size.X.Offset, refs.Root.Size.Y.Offset
			T.truthy(w <= maxW + 0.5 and h <= maxH + 0.5, `{label}: fits the phone screen`)
			checkLayout(refs, label, 72)
			for _, target in HoverboardView.touchTargets(refs) do
				T.truthy(target.Size.Y.Offset >= 72 or target.Size.Y.Scale >= 1, `{label}: {target.Name} is a thumb target`)
			end
			T.eq(refs.Hint.Text, HoverboardView.Pitch, `{label}: no control hint on phones, the pitch`)
		end
		-- the gamepad's words stay on a TV / a phone with a pad
		HoverboardView.setHint(refs, "Gamepad", "Choose a board · B: close")
		T.eq(refs.Hint.Text, "Choose a board · B: close", "a gamepad gets its hint")
	end)

	T.test("HoverboardView: setCards tags every card and the detail shows the picked board", function()
		local refs = HoverboardView.build()
		HoverboardView.layout(refs, false, 1280, 720)
		local realReady = HoverboardView.receiptsReady
		rawset(HoverboardView, "receiptsReady", function()
			return true
		end)
		local pass = MonetizationConfig.Entries.HoverboardCustom
		local oldId = pass.Id
		pass.Id = 777
		local coins = (B.EmberglassGlider.Price :: number) + 1
		HoverboardView.setCards(refs, { TimberDrifter = true, CartCruiser = true }, "CartCruiser", coins)
		local byId = {}
		for _, card in refs.Cards do
			byId[card.Board.Id] = card
		end
		T.eq(refs.Count.Text, `2 / {#HoverboardData.List}`, "the count chip")
		T.eq(byId.TimberDrifter.State, "Equip", "owned")
		T.eq(byId.CartCruiser.State, "Equipped", "equipped")
		T.eq(byId.EmberglassGlider.State, "Buy", "affordable")
		T.eq(byId.RoyalPhoenix.State, "BuyLocked", "too expensive")
		T.eq(byId.TerraForgeCustom.State, "Robux", "the Robux board")
		-- the tags
		T.truthy(byId.CartCruiser.Equipped.Visible, "E on the equipped board")
		T.falsy(byId.TimberDrifter.Equipped.Visible, "no E on the others")
		T.eq(byId.TimberDrifter.Tag.Text, "OWNED", "OWNED")
		T.eq(byId.CartCruiser.Tag.Text, "OWNED", "the equipped board is owned too")
		T.eq(byId.EmberglassGlider.Tag.Text, Format.money(B.EmberglassGlider.Price :: number), "the price")
		T.truthy(byId.EmberglassGlider.TagCoin.Visible and not byId.EmberglassGlider.TagLock.Visible, "a coin before it")
		T.truthy(byId.RoyalPhoenix.TagLock.Visible and not byId.RoyalPhoenix.TagCoin.Visible, "a lock: too expensive")
		T.eq(byId.TerraForgeCustom.Tag.Text, "ROBUX", "the ROBUX tag")
		T.falsy(byId.TimberDrifter.TagCoin.Visible or byId.TimberDrifter.TagLock.Visible, "no icon on OWNED")
		T.eq(byId.CartCruiser.Line.Text, "SPEED 27", "the bottom line")
		-- the detail: the equipped board first, picked with the gold outline and the white ring
		T.eq(refs.Selected, "", "nothing clicked yet")
		T.eq(refs.Shown, "CartCruiser", "the equipped board is shown first")
		T.truthy(byId.CartCruiser.Pick.Visible, "the white ring")
		T.eq(byId.CartCruiser.Stroke.Color, GolemView.SelectColor, "the gold outline")
		T.falsy(byId.TimberDrifter.Pick.Visible, "only the picked card")
		T.eq(refs.DetailName.Text, "CART CRUISER", "the detail's name")
		T.eq(refs.DetailKind.Text, "COIN BOARD", "the pill")
		T.eq(refs.DetailSpeed.Text, "SPEED 27", "the speed chip")
		T.eq(refs.DetailBonus.Text, HoverboardView.bonusText(B.CartCruiser), "the bonus chip")
		T.eq(refs.DetailText.Text, B.CartCruiser.Description, "the description")
		T.eq(refs.DetailPicture:GetAttribute("Icon"), "board_CartCruiser", "its 3D board")
		T.truthy(refs.DetailView:FindFirstChildOfClass("Model") ~= nil, "the model in the view")
		T.eq(refs.ActionWord.Text, "EQUIPPED", "EQUIPPED")
		T.truthy(refs.ActionIcons.Check.Visible, "a check")
		T.falsy(refs.Action.Selectable, "EQUIPPED is no gamepad stop")
		T.eq(HoverboardView.firstButton(refs), byId.CartCruiser.Button, "a gamepad starts on the equipped card")
		T.eq(byId.EmberglassGlider.Button.NextSelectionRight, refs.Close, "nothing to press: right goes to the X")
		-- each state's button
		HoverboardView.select(refs, "TimberDrifter")
		T.eq(refs.ActionWord.Text, "EQUIP", "EQUIP")
		T.truthy(refs.Action.Selectable, "a stop again")
		T.eq(refs.Action.NextSelectionLeft, byId.TimberDrifter.Button, "left goes back to the picked card")
		T.eq(byId.EmberglassGlider.Button.NextSelectionRight, refs.Action, "the right column goes to the button")
		T.falsy(byId.CartCruiser.Pick.Visible, "the old pick is gone")
		HoverboardView.select(refs, "EmberglassGlider")
		T.eq(refs.ActionStyle, "Buy", "BUY")
		T.eq(refs.ActionWord.Text, "BUY", "BUY")
		T.eq(refs.ActionAmount.Text, Format.money(B.EmberglassGlider.Price :: number), "with the price")
		T.truthy(refs.ActionIcons.Coin.Visible and not refs.ActionIcons.Lock.Visible, "and a coin")
		HoverboardView.select(refs, "RoyalPhoenix")
		T.eq(refs.ActionStyle, "BuyLocked", "greyed BUY")
		T.truthy(refs.ActionIcons.Lock.Visible and refs.ActionIcons.Coin.Visible, "a lock and the coin")
		T.eq(refs.DetailPerks[1].Text, "+ " .. string.upper(B.RoyalPhoenix.Perks[1]), "the perks")
		HoverboardView.select(refs, "TerraForgeCustom")
		T.eq(refs.ActionStyle, "Robux", "the Robux price")
		T.eq(refs.ActionWord.Text, "49", "49")
		T.truthy(refs.ActionIcons.Mark.Visible, "the robux mark")
		T.eq(refs.DetailKind.Text, "ROBUX BOARD", "the Robux pill")
		T.eq(refs.DetailPicture:GetAttribute("Icon"), "board_TerraForgeCustom", "the detail's board follows")
		pass.Id = 0
		HoverboardView.setCards(refs, {}, "", 0)
		T.eq(refs.Shown, "TerraForgeCustom", "a refresh keeps the picked board")
		T.eq(refs.ActionStyle, "Soon", "COMING SOON without a pass id")
		T.eq(refs.ActionWord.Text, "COMING SOON")
		T.truthy(refs.ActionIcons.Clock.Visible, "a clock")
		HoverboardView.select(refs, "Nope")
		T.eq(refs.Selected, "", "an unknown id: no pick")
		T.eq(HoverboardView.selectedCard(refs).Board.Id, HoverboardData.List[1].Id, "the default")
		pass.Id = oldId
		rawset(HoverboardView, "receiptsReady", realReady)
	end)

	T.test("HoverboardView: the detail's board swings, the camera keeps its distance", function()
		local refs = HoverboardView.build()
		HoverboardView.setCards(refs, {}, "", 0)
		local camera = refs.DetailCamera
		local at0 = camera.CFrame.Position
		local d0 = (at0 - refs.DetailCenter).Magnitude
		HoverboardView.turnDetail(refs, 2)
		local at1 = camera.CFrame.Position
		T.truthy((at1 - at0).Magnitude > 0.01, "it turned")
		T.near((at1 - refs.DetailCenter).Magnitude, d0, 1e-3, "same distance")
		T.near(camera.CFrame.LookVector:Dot((refs.DetailCenter - at1).Unit), 1, 1e-4, "still looking at the board")
	end)

	T.test("HoverboardView: the opening animation pops the window and drops the cards in", function()
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
			T.eq(card.Frame.Position.Y.Offset, card.Frame:GetAttribute("BaseY"), "in place")
		end
	end)

	T.test("HoverboardView: messages take the footer's place", function()
		local refs = HoverboardView.build()
		HoverboardView.showMessage(refs, "Not enough coins", roblox.Color3.new(1, 0, 0))
		T.truthy(refs.Message.Visible, "the message")
		T.falsy(refs.Footer.Visible, "instead of the hint")
		HoverboardView.hideMessage(refs)
		T.falsy(refs.Message.Visible, "gone")
		T.truthy(refs.Footer.Visible, "the hint is back")
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
