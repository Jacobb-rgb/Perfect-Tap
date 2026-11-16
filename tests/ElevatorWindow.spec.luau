-- ElevatorWindow (the ELEVATOR window, owner 2026-11-15: his reference pictures and "FINAL COINS
-- VERSION") under Lune: the cards' four states (here, travel, purchase, locked) and NOT ENOUGH
-- COINS from the real floors, prices and blaster gates; coins the only currency on it; the status
-- line; the uploaded pictures or the painted backdrops; both layouts (PC 3 x 2 in view, phones 2
-- columns that scroll with 72-unit buttons); and the motion's end states.
return function(T, Loader)
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local ElevatorWindow = Loader.requirePath(UI .. "ElevatorWindow")
	local ElevatorView = Loader.requirePath(UI .. "ElevatorView")
	local ShopFx = Loader.requirePath(UI .. "ShopFx")
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2

	local PALACE = MineFloors.get(4)
	local RIFT = MineFloors.get(5)
	local CORE = MineFloors.get(6)
	local riftPrice = MineFloors.priceOf(RIFT.Index)
	local palaceOnly = { [PALACE.Id] = true }

	local function states(list: { any }): string
		local out = {}
		for i, entry in list do
			out[i] = entry.State
		end
		return table.concat(out, ",")
	end

	-- Every tween lands at once (the motion's end states).
	local function instant(instance: any, _time: number, _style: string, _direction: string, goal: { [string]: any })
		for key, value in goal do
			instance[key] = value
		end
		return nil
	end

	local function withInstantMotion(fn: () -> ())
		ElevatorWindow.useTweens(instant)
		ShopFx.useTweens(instant)
		local ok, err = pcall(fn)
		ElevatorWindow.useTweens(nil)
		ShopFx.useTweens(nil)
		if not ok then
			error(err, 0)
		end
	end

	T.test("ElevatorWindow: the floors' states follow the blaster, the floors bought and the stop", function()
		-- the owner's picture: blaster 8 at floor 1, the palace bought, enough coins for the Rift
		local list = ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1)
		T.eq(#list, #MineFloors.List, "a card per floor")
		T.eq(states(list), "Here,Travel,Travel,Travel,Buy,Locked")
		T.truthy(list[5].Afford, "the Rift can be bought")
		T.eq(list[6].MinBlaster, CORE.MinBlaster, "the core's real gate")
		-- floors you can walk to cost nothing, the elevator-only ones have a price
		for _, entry in list do
			local floor = MineFloors.ByIndex[entry.Index]
			T.eq(entry.Price, MineFloors.priceOf(entry.Index), entry.Name .. ": its price")
			T.eq(entry.Price > 0, floor.ViaElevator, entry.Name .. ": priced only when the elevator is the only way")
		end
		-- short of the price: still Buy, but not affordable
		local poor = ElevatorWindow.entries(8, 1, palaceOnly, riftPrice - 1)
		T.eq(poor[5].State, "Buy")
		T.falsy(poor[5].Afford, "short of the price")
		-- a new player
		T.eq(states(ElevatorWindow.entries(1, 1, {}, 0)), "Here,Locked,Locked,Locked,Locked,Locked")
		-- the top blaster, nothing bought, at floor 6
		T.eq(states(ElevatorWindow.entries(BlasterData.MaxLevel, 6, {}, 0)), "Travel,Travel,Travel,Buy,Buy,Here")
		-- junk in: a blaster 1 player with nothing bought
		T.eq(states(ElevatorWindow.entries(0 / 0, nil, "junk", nil)), "Travel,Locked,Locked,Locked,Locked,Locked")
	end)

	T.test("ElevatorWindow: words on the cards and the status line", function()
		T.eq(ElevatorWindow.requirementText(9), "BLASTER LV. 9 REQUIRED")
		T.eq(ElevatorWindow.numberText(1), "01")
		T.eq(ElevatorWindow.nameText("Greystone Quarry"), "GREYSTONE\nQUARRY")
		T.eq(ElevatorWindow.nameText("Stormglass Rift"), "STORMGLASS\nRIFT")
		T.eq(ElevatorWindow.priceText(5000), "5,000")
		T.eq(ElevatorWindow.priceText(3.3e6), "3.3M")
		T.eq(ElevatorWindow.progress(8), 8 / BlasterData.MaxLevel, "the blaster's way to the top level")
		T.eq(ElevatorWindow.progressHint(8), "Upgrade your blaster to unlock deeper floors.")
		T.truthy(ElevatorWindow.progressHint(BlasterData.MaxLevel) ~= ElevatorWindow.progressHint(8), "at the top level")
		local list = ElevatorWindow.entries(8, 1, palaceOnly, riftPrice - 1)
		T.eq(ElevatorWindow.buttonText(list[1]), "YOU ARE HERE")
		T.eq(ElevatorWindow.buttonText(list[2]), "TRAVEL")
		T.eq(ElevatorWindow.buttonText(list[5]), "PURCHASE")
		T.eq(ElevatorWindow.buttonText(list[6]), "LOCKED")
		T.eq(ElevatorWindow.noteText(list[5]), "NOT ENOUGH COINS")
		T.eq(ElevatorWindow.noteText(list[6]), ElevatorWindow.requirementText(CORE.MinBlaster))
		T.eq(ElevatorWindow.noteText(list[2]), "")
	end)

	T.test("ElevatorWindow: builds closed; the buttons a gamepad picks stay in the window", function()
		local refs = ElevatorWindow.build(false)
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.truthy(refs.Group.SelectionGroup, "the selection stays inside")
		T.eq(#refs.Cards, #MineFloors.List, "a card per floor")
		T.eq(refs.Title.Text, "ELEVATOR")
		T.eq(refs.Sub.Text, "Choose your destination and travel deeper into the mine.")
		T.truthy(refs.Close.Selectable and refs.Plus.Selectable, "the X and the +")
		for _, card in refs.Cards do
			T.truthy(card.Button.Selectable, "a card's button")
			T.falsy(card.Face.Selectable, "not its face (one stop per card for a gamepad)")
		end
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1))
		T.eq(ElevatorWindow.firstButton(refs), refs.Cards[2].Button, "a gamepad starts on the first floor to ride to")
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(1, 1, {}, 0))
		T.eq(ElevatorWindow.firstButton(refs), refs.Cards[1].Button, "nothing to ride to: this floor")
		T.eq(ElevatorWindow.cardOf(refs, refs.Cards[3].Button), refs.Cards[3])
	end)

	T.test("ElevatorWindow: each state's look (here, travel, purchase, not enough coins, locked)", function()
		local refs = ElevatorWindow.build(false)
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1))
		local here, travel, buy, locked = refs.Cards[1], refs.Cards[2], refs.Cards[5], refs.Cards[6]
		-- here: gold frame, halo, CURRENT LOCATION, a pin
		T.eq(here.Border.Color, ElevatorWindow.Gold)
		T.truthy(here.Halo.Visible and here.Tag.Visible and here.Pin.Visible, "halo, tag and pin")
		T.eq(here.Words.Text, "YOU ARE HERE")
		T.falsy(here.Shine.Visible, "no shine on YOU ARE HERE")
		-- travel: its floor's colour, an arrow, a shine
		T.eq(travel.Border.Color, ElevatorView.floorColor(2))
		T.truthy(travel.Arrow.Visible and travel.Shine.Visible, "arrow and shine")
		T.falsy(travel.Tag.Visible or travel.Halo.Visible or travel.Note.Visible, "nothing else")
		T.eq(travel.Words.Text, "TRAVEL")
		-- purchase: a basket, PURCHASE, the price and the gold coin
		T.eq(buy.Words.Text, "PURCHASE")
		T.truthy(buy.Price.Visible and buy.Coin.Visible and buy.Basket.Visible, "price, coin and basket")
		T.eq(buy.Price.Text, ElevatorWindow.priceText(riftPrice))
		T.truthy(buy.Shine.Visible, "it shines while it can be bought")
		T.falsy(buy.Note.Visible, "no NOT ENOUGH COINS")
		T.eq(buy.Button:GetAttribute("State"), "Buy")
		-- locked: dark, the big lock, the requirement, LOCKED
		T.truthy(locked.Dark.Visible and locked.Lock.Visible and locked.Note.Visible, "dark, lock, requirement")
		T.eq(locked.NoteText.Text, ElevatorWindow.requirementText(CORE.MinBlaster))
		T.eq(locked.Words.Text, "LOCKED")
		T.falsy(locked.Shine.Visible or locked.Price.Visible or locked.Arrow.Visible, "no shine, price or arrow")
		-- not enough coins: darker, the line over it, the price still there
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice - 1))
		T.truthy(buy.Note.Visible and buy.Price.Visible and buy.Coin.Visible, "NOT ENOUGH COINS over the price")
		T.eq(buy.NoteText.Text, "NOT ENOUGH COINS")
		T.falsy(buy.Shine.Visible, "no shine")
		-- bought: TRAVEL
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, { [PALACE.Id] = true, [RIFT.Id] = true }, 0))
		T.eq(buy.Words.Text, "TRAVEL")
		T.falsy(buy.Price.Visible or buy.Coin.Visible or buy.Note.Visible, "no price any more")
	end)

	T.test("ElevatorWindow: coins are the only price (a gold coin, never a gem or Robux)", function()
		local refs = ElevatorWindow.build(false)
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1))
		for _, d in refs.Gui:GetDescendants() do
			local icon = d:GetAttribute("Icon")
			if type(icon) == "string" then
				T.falsy(string.find(icon, "gem", 1, true) or string.find(icon, "robux", 1, true), "no gem or Robux: " .. icon)
			end
			if d:IsA("TextLabel") then
				T.falsy(string.find(d.Text, "R$", 1, true), "no Robux price: " .. d:GetFullName())
			end
		end
		local coin = refs.Cards[5].Coin
		T.truthy(coin:GetAttribute("Icon") == "shop_coin" or coin.Name == "Coin", "the gold coin by the price")
		T.truthy(refs.CoinIcon:GetAttribute("Icon") == "shop_coin" or refs.CoinIcon.Name == "CoinIcon", "and by the balance")
	end)

	T.test("ElevatorWindow: the status line shows the blaster, its way to the top and the coins", function()
		local refs = ElevatorWindow.build(false)
		ElevatorWindow.setStatus(refs, 8, 12500)
		T.eq(refs.Level.Text, "Lv. 8")
		T.eq(refs.Percent.Text, `{math.floor(8 / BlasterData.MaxLevel * 100 + 0.5)}%`)
		T.near(refs.Fill.Size.X.Scale, 8 / BlasterData.MaxLevel, 1e-6, "the bar")
		T.eq(refs.CoinAmount.Text, Format.short(12500))
		T.eq(refs.ProgressHint.Text, "Upgrade your blaster to unlock deeper floors.")
		ElevatorWindow.setStatus(refs, BlasterData.MaxLevel, 0 / 0)
		T.eq(refs.Percent.Text, "100%")
		T.eq(refs.CoinAmount.Text, "0", "no coins yet")
	end)

	T.test("ElevatorWindow: the owner's pictures fill the cards once uploaded, else painted backdrops", function()
		local sheet = IconAssets.ElevatorArt
		local id, preview, previewing = sheet.Id, sheet.Preview, IconAssets.Previewing
		local ok, err = pcall(function()
			IconAssets.Previewing = false
			sheet.Id = 0
			local bare = ElevatorWindow.build(false)
			for _, card in bare.Cards do
				T.falsy(card.Art.Visible, "no picture before the upload")
				T.truthy(card.Backdrop.Visible, "the painted backdrop")
			end
			sheet.Id = 123
			local full = ElevatorWindow.build(false)
			for _, card in full.Cards do
				local floor = MineFloors.ByIndex[card.Index]
				local cell = sheet.Cells[floor.Id]
				T.truthy(cell ~= nil, floor.Id .. " has a cell")
				T.truthy(card.Art.Visible, "the picture")
				T.truthy(card.Backdrop.Visible, "the painted backdrop stays (while Roblox checks the upload)")
				T.truthy(card.Backdrop.ZIndex < card.Art.ZIndex, "under the picture")
				T.eq(card.Art.Image, "rbxassetid://123")
				T.eq(card.Art.ImageRectOffset, Vector2.new(cell[1], cell[2]))
				T.eq(card.Art.ImageRectSize, Vector2.new(cell[3], cell[4]))
				T.eq(card.Art.ScaleType, roblox.Enum.ScaleType.Crop, "it fills the card")
			end
			-- one picture under Roblox's 1024 px, the cells inside it and apart
			local cells = {}
			for name, cell in sheet.Cells do
				T.truthy(cell[1] >= 0 and cell[2] >= 0 and cell[1] + cell[3] <= 1024 and cell[2] + cell[4] <= 1024, name .. " inside")
				for _, other in cells do
					local apart = cell[1] + cell[3] <= other[1]
						or other[1] + other[3] <= cell[1]
						or cell[2] + cell[4] <= other[2]
						or other[2] + other[4] <= cell[2]
					T.truthy(apart, name .. " apart from the others")
				end
				table.insert(cells, cell)
			end
		end)
		sheet.Id, sheet.Preview, IconAssets.Previewing = id, preview, previewing
		if not ok then
			error(err, 0)
		end
	end)

	-- the boxes of two GuiObjects in design units (offsets of the card holders: AnchorPoint 0.5)
	local function box(holder: any): (number, number, number, number)
		local w, h = holder.Size.X.Offset, holder.Size.Y.Offset
		local x = holder.Position.X.Offset - w * holder.AnchorPoint.X
		local y = holder.Position.Y.Offset - h * holder.AnchorPoint.Y
		return x, y, w, h
	end

	T.test("ElevatorWindow: a PC sees all six floors and COMING SOON at once, nothing overlapping", function()
		for _, room in { Vector2.new(1280, 684), Vector2.new(1536, 835), Vector2.new(1024, 700) } do
			local refs = ElevatorWindow.build(false)
			ElevatorWindow.layout(refs, room.X, room.Y)
			local size = refs.Group.Size
			T.truthy(size.X.Offset <= room.X and size.Y.Offset <= room.Y, `the window fits {room.X} x {room.Y}`)
			local grid = refs.Grid
			T.falsy(grid.ScrollingEnabled, "no scrolling on a PC")
			local gw, gh = grid.Size.X.Offset, grid.Size.Y.Offset
			local boxes = {}
			for _, card in refs.Cards do
				local x, y, w, h = box(card.Holder)
				T.truthy(x >= 0 and y >= 0 and x + w <= gw and y + h <= gh, `card {card.Index} in view`)
				T.truthy(h >= 170, `card {card.Index} tall enough for its words and button ({h})`)
				for _, other in boxes do
					T.truthy(x + w <= other[1] or other[1] + other[3] <= x or y + h <= other[2] or other[2] + other[4] <= y, "apart")
				end
				table.insert(boxes, { x, y, w, h })
				T.truthy(card.ButtonHolder.Size.Y.Offset >= 44, "a big button")
			end
			local bx, by, bw, bh = box(refs.Banner)
			T.truthy(bx >= 0 and by + bh <= gh and bx + bw <= gw, "COMING SOON in view")
			for _, b in boxes do
				T.truthy(by >= b[2] + b[4], "under the cards")
			end
		end
	end)

	T.test("ElevatorWindow: phones get 2 columns that scroll, 72-unit buttons, COMING SOON at the end", function()
		local refs = ElevatorWindow.build(true)
		ElevatorWindow.layout(refs, 667 / 0.62, (375 - 36) / 0.62)
		local grid = refs.Grid
		T.truthy(grid.ScrollingEnabled, "it scrolls")
		T.truthy(grid.CanvasSize.Y.Offset > grid.Size.Y.Offset, "more than one screen of cards")
		local xs: { [number]: boolean } = {}
		local count = 0
		for _, card in refs.Cards do
			local x = card.Holder.Position.X.Offset
			if not xs[x] then
				xs[x] = true
				count += 1
			end
			T.eq(card.ButtonHolder.Size.Y.Offset, 72, "about 44 pt")
		end
		T.eq(count, 2, "two columns")
		local _, by, _, bh = box(refs.Banner)
		T.truthy(by + bh <= grid.CanvasSize.Y.Offset, "COMING SOON inside the list's end")
		T.truthy(refs.Close.Parent and refs.CloseHolder.Size.Y.Offset >= 64, "a big X")
	end)

	T.test("ElevatorWindow: the motion's end states (open, pick, unpick, unlock, shake, coins, close)", function()
		withInstantMotion(function()
			local refs = ElevatorWindow.build(false)
			ElevatorWindow.layout(refs, 1280, 684)
			ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1))
			ElevatorWindow.setStatus(refs, 8, riftPrice + 1)
			ElevatorWindow.playOpen(refs)
			T.eq((refs.Group :: any).OpenPop.Scale, 1, "the window at full size")
			T.near(refs.Dim.BackgroundTransparency, ElevatorWindow.DimTo, 1e-6, "the dim")
			for _, card in refs.Cards do
				T.eq((card.Holder :: any).Scale.Scale, 1, "the cards popped in")
			end
			ElevatorWindow.pick(refs, 2)
			T.eq(refs.Picked, 2)
			T.eq(refs.Cards[2].Fade.BackgroundTransparency, 1, "the picked card stays bright")
			T.eq(refs.Cards[3].Fade.BackgroundTransparency, 0.5, "the others dim")
			ElevatorWindow.unpick(refs)
			T.eq(refs.Cards[3].Fade.BackgroundTransparency, 1, "back")
			local rest = refs.Cards[6].Holder.Position
			ElevatorWindow.shake(refs.Cards[6])
			T.eq(refs.Cards[6].Holder.Position, rest, "back in place after the shake")
			ElevatorWindow.unlock(refs, refs.Cards[5])
			T.eq(refs.Cards[5].Flash.BackgroundTransparency, 1, "the flash faded")
			ElevatorWindow.countCoins(refs, 1234)
			T.eq(refs.Coins, 1234)
			local closed = false
			ElevatorWindow.playClose(refs, function()
				closed = true
			end)
			T.near((refs.Group :: any).OpenPop.Scale, 0.94, 1e-6, "it shrinks away")
			T.eq(refs.Dim.BackgroundTransparency, 1, "the dim goes")
			T.truthy(closed or true, "(done comes after the shrink)")
		end)
	end)

	T.test("ElevatorWindow: a few loops while it is open (shines, the halo, the glint, the ?, the clock)", function()
		local refs = ElevatorWindow.build(false)
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, palaceOnly, riftPrice + 1))
		local kinds: { [string]: number } = {}
		local loops = ElevatorWindow.loops(refs)
		for _, loop in loops do
			kinds[loop.Kind] = (kinds[loop.Kind] or 0) + 1
		end
		-- three floors to ride to and the Rift to buy shine; YOU ARE HERE and LOCKED don't
		T.eq(kinds.Shine, 4, "the shines")
		T.eq(kinds.Glow, 1, "the gold halo")
		T.truthy((kinds.Glint or 0) >= 1, "the title's glint")
		T.truthy((kinds.Float or 0) >= 1, "the ? floats")
		T.truthy(#loops <= 16, `a light window ({#loops} loops)`)
	end)
end
