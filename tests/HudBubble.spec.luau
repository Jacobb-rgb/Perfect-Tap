-- HudBubble (the light "Bubble" HUD, pure builder) under Lune: every menu tile,
-- teleport tab and hotbar slot exists, uses an uploaded-icon name, and stays
-- >= 44 pt to tap on phones (uiScale 0.62).
return function(T, Loader)
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
	local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")

	T.test("HudBubble: tiles, tabs and slots exist with known icons and roles", function()
		for _, scale in { 1.25, 0.62 } do
			local refs = HudBubble.build(scale)
			T.truthy(refs.Gui:GetAttribute("TerraForge"), "UIScale applies")
			for _, entry in HudBubble.Menu do
				T.truthy(refs.Menu[entry.Id], "tile " .. entry.Id)
				T.truthy(IconAssets.has(entry.Icon), "icon listed " .. entry.Icon)
				T.truthy(BubbleTheme.Roles[entry.Role], "role " .. entry.Role)
			end
			for _, spot in HudBubble.Spots do
				T.truthy(refs.Tabs[spot.Id], "tab " .. spot.Id)
				T.truthy(IconAssets.has(spot.Icon), "icon listed " .. spot.Icon)
			end
			T.eq(#refs.Slots, HudBubble.layout(scale).Slots, "hotbar slots")
		end
	end)

	T.test("HudBubble: MORE flyout has a tile per entry and outlines MORE", function()
		for _, scale in { 1.25, 0.62 } do
			local refs = HudBubble.build(scale)
			local more = HudBubble.moreMenu(refs, scale)
			for _, entry in HudBubble.More do
				T.truthy(more.Tiles[entry.Id], "tile " .. entry.Id)
				T.truthy(IconAssets.has(entry.Icon), "icon listed " .. entry.Icon)
			end
			T.truthy(more.Close, "close")
			T.eq(refs.Menu.More:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Gold, "MORE outlined while open")
		end
	end)

	T.test("HudBubble: the menu math matches the grid", function()
		local layout = HudBubble.layout(1.25)
		local m = HudBubble.menuMetrics(layout)
		local first = HudBubble.tilePosition(layout, 1)
		local third = HudBubble.tilePosition(layout, 2 * layout.Columns + 1)
		T.eq(first.X.Offset, m.Origin.X.Offset, "first tile at the origin")
		T.eq(third.Y.Offset - first.Y.Offset, 2 * (m.CellHeight + m.RowGap), "row 3")
		-- (a 667-point touch phone: four a row in the round look, three in the others)
		local phone = HudBubble.layout(0.62, 667, true)
		local p5 = HudBubble.tilePosition(phone, phone.Columns + 1)
		local p1 = HudBubble.tilePosition(phone, 1)
		T.eq(p5.Y.Offset - p1.Y.Offset, HudBubble.menuMetrics(phone).CellHeight + HudBubble.menuMetrics(phone).RowGap, "row 2 on phones")
	end)

	T.test("HudBubble: phone layout keeps touch targets >= 44 pt", function()
		local layout = HudBubble.layout(0.62, 667, true) -- (a phone: a touch screen)
		T.truthy(layout.Compact, "compact on phones")
		T.truthy(layout.Tile * 0.62 >= 44, "menu tiles")
		T.truthy(layout.TabHeight * 0.62 >= 44, "teleport tabs")
		T.truthy(layout.Slot * 0.62 >= 44, "hotbar slots")
		T.falsy(HudBubble.layout(1.25).Compact, "full layout on PC")
	end)

	T.test("HudBubble: setSlot puts an icon in and outlines the held slot", function()
		local refs = HudBubble.build(1)
		HudBubble.setSlot(refs.Slots[1], "blaster", true)
		local face = refs.Slots[1]:FindFirstChild("Face")
		local icon = face:FindFirstChild("Icon")
		T.eq(icon:GetAttribute("Icon"), "blaster", "icon name")
		T.eq(face:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Gold, "held slot is gold")
		HudBubble.setSlot(refs.Slots[1], nil, false)
		T.falsy(face:FindFirstChild("Icon"), "cleared")
		T.eq(face:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Outline, "plain outline again")
	end)

	T.test("IconAssets: an icon without an upload gives an empty image", function()
		T.eq((IconAssets.find("coin")), "", "not uploaded yet")
		T.eq((IconAssets.find("nope")), "", "unknown icon")
		T.truthy((IconAssets.find("robux")):find("rbxasset://"), "Roblox's own Robux icon")
	end)

	T.test("IconAssets: sheets fit Roblox's 1024 px and every icon has one cell", function()
		local seen = {}
		for _, sheet in IconAssets.Sheets do
			T.truthy(#sheet.Icons <= IconAssets.Columns * IconAssets.Columns, sheet.Name .. " fits 6 x 6")
			for _, name in sheet.Icons do
				T.falsy(seen[name], "listed once: " .. name)
				seen[name] = true
			end
		end
		T.truthy(IconAssets.Columns * IconAssets.Cell <= 1024, "sheet size")
		local offset = IconAssets.cellOffset(7)
		T.eq(offset.X, IconAssets.Cell, "cell 7 = column 1")
		T.eq(offset.Y, IconAssets.Cell, "cell 7 = row 1")
	end)

	-- the owner's Studio photos (2026-11-07): the HUD was built on the camera's first tiny viewport,
	-- so a PC window kept the smallest phone's top row (Lobby / Base / Vault small, no Shop, no offers)
	T.test("HudBubble: the HUD waits for the real screen before it picks its layout", function()
		local roblox = require("@lune/roblox") :: any
		local Vector2 = roblox.Vector2
		local sizes = { Vector2.new(1, 1), Vector2.new(199, 900), Vector2.new(900, 199), Vector2.new(995, 485) }
		local reads, steps = 0, 0
		local ready, first, final = HudBubble.waitForScreen(5, function()
			reads = math.min(reads + 1, #sizes)
			return sizes[reads]
		end, function()
			steps += 1
		end)
		T.truthy(ready, "the real size came")
		T.eq(steps, 3, "too narrow and too low both wait")
		T.eq(first, sizes[1], "says what it saw first")
		T.eq(final, sizes[4], "and last")
		T.falsy(
			HudBubble.waitForScreen(0, function()
				return Vector2.new(1, 1)
			end, function() end),
			"never a real size: gives up, never hangs"
		)
		local noWait = 0
		T.truthy(
			HudBubble.waitForScreen(0, function()
				return Vector2.new(568, 320) -- (the smallest phone is a real screen)
			end, function()
				noWait += 1
			end),
			"a phone is real"
		)
		T.eq(noWait, 0, "no frame waited")
	end)

	T.test("HudBubble: HudController waits for the screen before it builds the HUD", function()
		-- (HudController reads Players.LocalPlayer when it loads: its source is checked, the very
		-- lines at init's own indent, so a comment or a dead branch doesn't count)
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/HudController.luau")
		local init = string.find(source, "function HudController.init()", 1, true)
		T.truthy(init, "init")
		local wait = string.find(source, "\n\tlocal ready, first, final = HudBubble.waitForScreen()", init, true)
		local build = string.find(source, "\n\trefs = HudView.build()", init, true)
		T.truthy(wait, "init waits for the screen")
		T.truthy(build, "init builds the HUD")
		T.truthy(wait < build, "first the wait, then the build")
	end)

	-- his window as it really is: 995 x 485 pt at scale 0.67 (his photos are 2 px a point), a mouse.
	-- Compact by its scale, but the big top row and the offers he picked on 2026-11-07 ("navrh tri").
	-- A touch phone of the same size keeps its short row and no offers.
	T.test("HudBubble: a mouse window like the owner's gets the big top row, its pictures and the offers", function()
		local roblox = require("@lune/roblox") :: any
		local Vector2 = roblox.Vector2
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
		local before, previewing = UIConfig.LightUI, IconAssets.Previewing
		UIConfig.LightUI = true
		IconAssets.Previewing = false -- (what the game shows, not a preview)
		local ok, err = pcall(function()
			local scale = HudBubble.scaleFor(Vector2.new(995, 485))
			T.truthy(scale < 0.75, "his window's scale is a phone's")
			local guiH = 485 - 58 -- (under Roblox's top bar)
			local width, height = 995 / scale, guiH / scale
			local window = HudBubble.buildGame(scale, 995, false, false, guiH)
			TeleportView.build(window.TopBar, scale, 995)
			local shop = window.TopBar:FindFirstChild("ShopPill") :: any
			T.truthy(shop, "the Shop leads the top row")
			T.eq(window.TopBar:GetAttribute("Narrow"), false, "not the phone's row")
			T.eq(shop.Size.X.Offset >= HudBubble.TabMin, true, "the big tabs")
			local icons = { ShopPill = "cart", Lobby = "lobby", Base = "base", Vault = "vault" }
			for name, icon in icons do
				local button = window.TopBar:FindFirstChild(name) :: any
				T.truthy(button, name)
				local mark = button:FindFirstChild("Icon", true) :: any
				T.truthy(mark, name .. "'s picture")
				T.truthy(mark.Visible, name .. "'s picture shows")
				T.eq(mark.Image, "rbxassetid://" .. tostring(IconAssets.TopRow.Id), name .. ": his image")
				T.eq(mark.ImageRectOffset.X, IconAssets.TopRow.Cells[icon] * IconAssets.Cell, name .. ": its own cell")
				T.eq(mark.ImageRectOffset.Y, 0, name .. ": one row")
				T.eq(mark.ImageRectSize.X, IconAssets.Cell, name .. ": a cell wide")
				T.eq(mark.ImageRectSize.Y, IconAssets.Cell, name .. ": a cell tall")
			end
			-- the offers fit his short window: under the top row, over the boost corner
			local offers = window.Gui:FindFirstChild("Offers") :: any
			T.truthy(offers, "the offers")
			local top = height / 2 - offers.Size.Y.Offset / 2
			local bottom = height / 2 + offers.Size.Y.Offset / 2
			T.truthy(top >= window.TopBar.Size.Y.Offset, "the offers start under the top row's height")
			local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
			local cornerTop = height - BoostView.CornerBottom - BoostView.cornerHeight()
			T.truthy(bottom <= cornerTop, "and end over the boost corner")
			T.truthy(width > 0, "a real width")
			window.Gui:Destroy()

			-- a touch phone of the same size: words only, a short row, no offers
			local phone = HudBubble.buildGame(scale, 995, true, false, guiH)
			TeleportView.build(phone.TopBar, scale, 995)
			T.eq(phone.TopBar:GetAttribute("Compact"), true, "the phone's row")
			T.falsy((phone.TopBar:FindFirstChild("Lobby") :: any):FindFirstChild("Icon", true), "words only")
			T.falsy(phone.Gui:FindFirstChild("Offers"), "no offers")
			phone.Gui:Destroy()

			-- what the first tiny viewport gave him on a mouse before the wait: a mouse never gets Narrow now
			local tiny = HudBubble.layout(HudBubble.scaleFor(Vector2.new(1, 1)), 1, false, false, guiH)
			T.falsy(tiny.Narrow, "a mouse window is never the smallest phone")
		end)
		UIConfig.LightUI, IconAssets.Previewing = before, previewing
		if not ok then
			error(err, 0)
		end
	end)

	-- the owner's one uploaded image for the top row (2026-11-07): one row of cells in the order of
	-- horni_lista.png; only those four icons, the left tiles wait for their own sheets
	T.test("HudBubble: the top row's own image holds only its four pictures", function()
		T.truthy(IconAssets.TopRow.Id > 0, "uploaded")
		for name, cell in { cart = 0, lobby = 1, base = 2, vault = 3 } do
			T.eq(IconAssets.TopRow.Cells[name], cell, name)
			T.truthy(IconAssets.topRowShows(name), name .. " shows")
		end
		T.falsy(IconAssets.topRowHas("wheel"), "only the four buttons")
	end)

	-- review 2026-11-07: in a small mouse window the lowest offer sat on the tutorial card's SKIP and
	-- took its click; there the offers stay away. Without their icon sheets they show live models.
	T.test("HudBubble: the offers show a picture and keep off the tutorial card's buttons", function()
		local roblox = require("@lune/roblox") :: any
		local Vector2 = roblox.Vector2
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")
		local before, previewing = UIConfig.LightUI, IconAssets.Previewing
		UIConfig.LightUI = true
		IconAssets.Previewing = false
		local ok, err = pcall(function()
			-- { width, height, the top bar's inset, should they show }
			local screens = {
				{ 995, 485, 58, true }, -- the owner's Studio window
				{ 1280, 720, 36, true },
				{ 1920, 1080, 58, true },
				{ 700, 400, 36, false },
				{ 682, 360, 36, false },
			}
			for _, size in screens do
				local scale = HudBubble.scaleFor(Vector2.new(size[1], size[2]))
				local gui = Vector2.new(size[1], size[2] - size[3])
				local at = `{size[1]} x {size[2]}`
				local refs = HudBubble.buildGame(scale, size[1], false, false, gui.Y)
				local offers = refs.Gui:FindFirstChild("Offers") :: any
				T.truthy(offers, "the offers at " .. at)
				local clear = TutorialView.clearOfOffers(offers, scale, gui, false)
				T.eq(clear, size[4], "shown or kept away at " .. at)
				for _, offer in HudBubble.Offers do
					local button = (offers:FindFirstChild(offer.Card) :: any):FindFirstChild("Offer") :: any
					local picture = button:FindFirstChild("Picture") :: any
					T.truthy(picture, offer.Card .. ": a picture at " .. at)
					T.truthy(#(picture:FindFirstChild("View") :: any):GetChildren() > 0, offer.Card .. ": a live model")
				end
				-- when they show, the lowest button really is above SKIP and GOT IT
				if clear then
					local h = gui.Y / scale
					local card = TutorialView.layout(scale, gui, false, false)
					local rowTop = card.Position.Y - TutorialView.Foot - card.RowHeight
					local lowest = h / 2 + offers.Size.Y.Offset / 2 - 24
					T.truthy(lowest <= rowTop, "above the card's buttons at " .. at)
				end
				refs.Gui:Destroy()
			end
		end)
		UIConfig.LightUI, IconAssets.Previewing = before, previewing
		if not ok then
			error(err, 0)
		end
	end)

	-- the owner's own pictures on the left (2026-11-07, hud_dlazdice.png): each listed tile shows its
	-- cell as the whole tile, the word drawn in it; "Shop" in the menu is the boosts, not his Shop picture
	T.test("HudBubble: the left tiles wear the owner's pictures, cell by cell", function()
		local roblox = require("@lune/roblox") :: any
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		local art = IconAssets.TileArt
		T.truthy(art.Id > 0, "uploaded")
		-- the order of the uploaded sheet, tools/preview/make_tile_sheet.py
		local order = { "shop", "build", "golems", "hoverboard", "index", "daily", "inventory", "rebirth", "more", "spin", "elevator" }
		for i, name in order do
			T.eq(art.Cells[name], i - 1, name .. "'s cell")
		end
		local expect = {
			Store = "shop",
			Build = "build",
			Golems = "golems",
			Ride = "hoverboard",
			Codex = "index",
			Quests = "daily",
			Backpack = "inventory",
			Rebirth = "rebirth",
			More = "more",
			Wheel = "spin",
			Elevator = "elevator",
		}
		for tile, name in expect do
			T.eq(IconAssets.tileArt(tile), name, tile)
		end
		T.falsy(IconAssets.tileArt("Shop") == "shop", "the boosts' tile is not his Shop picture")
		T.eq(IconAssets.tileArt("Shop"), "boosts", "it has its own")
		T.eq(IconAssets.tileArt("Settings"), "settings", "Settings")
		T.eq(IconAssets.tileArt("Trade"), "trade", "Trade")
		T.eq(IconAssets.tileArt("Gear"), nil, "no picture: keeps its face and word")
		-- the second image, in the order of hud_dlazdice_2.png
		local second = art.Second
		T.truthy(second.Id > 0, "the second image is uploaded")
		local order2 = {
			"boosts",
			"settings",
			"trade",
			"potion_lucky",
			"potion_coins",
			"potion_mining",
			"potion_speed",
			"potion_strength",
			"potion_mythic",
		}
		for i, name in order2 do
			T.eq(second.Cells[name], i - 1, name .. "'s cell")
		end
		local two = roblox.Instance.new("ImageLabel")
		IconAssets.applyTileArt(two, "trade")
		T.eq(two.Image, "rbxassetid://" .. tostring(second.Id), "Trade: the second image")
		T.eq(two.ImageRectOffset.X, 2 * art.Cell, "Trade: column 2")
		T.eq(two.ImageRectOffset.Y, 0, "Trade: row 0")
		IconAssets.applyTileArt(two, "potion_mythic")
		T.eq(two.ImageRectOffset.X, 2 * art.Cell, "Mythic: column 2")
		T.eq(two.ImageRectOffset.Y, 2 * art.Cell, "Mythic: row 2")

		local before, previewing = UIConfig.LightUI, IconAssets.Previewing
		UIConfig.LightUI = true
		IconAssets.Previewing = false -- (what the game shows)
		local ok, err = pcall(function()
			local holder = roblox.Instance.new("Frame")
			local spec = { Name = "Wheel", Label = "Spin", Icon = "wheel", Role = "Wheel", Size = 77 }
			local face = HudBubble.tile(holder, spec)
			T.eq(face:GetAttribute("TileArt"), "spin", "the Spin tile")
			T.eq(face.BackgroundTransparency, 1, "no dark face behind the picture")
			T.eq(face:GetAttribute("DarkTile"), nil, "not a dark tile")
			local icon = face:FindFirstChild("Icon") :: any
			T.eq(icon.Image, "rbxassetid://" .. tostring(art.Id), "his image")
			T.eq(icon.ImageRectOffset.X, 1 * art.Cell, "cell 9: column 1")
			T.eq(icon.ImageRectOffset.Y, 2 * art.Cell, "cell 9: row 2")
			T.eq(icon.ImageRectSize.X, art.Cell, "a cell wide")
			T.eq(icon.ImageRectSize.Y, art.Cell, "a cell tall")
			T.eq(icon.Size.X.Scale, 1, "the whole tile")
			T.eq(icon.Size.Y.Scale, 1, "the whole tile")
			local label = face:FindFirstChild("Label") :: any
			T.falsy(label.Visible, "the word is in the picture")
			local outline = face:FindFirstChildOfClass("UIStroke") :: any
			T.falsy(outline.Enabled, "no outline over the picture's own edge")
			local Bubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Bubble")
			Bubble.select(face, true)
			T.truthy(outline.Enabled, "selected: the outline")
			Bubble.select(face, false)
			T.falsy(outline.Enabled, "and away again")

			local plain = HudBubble.tile(holder, { Name = "Gear", Label = "Gear", Icon = "helmet", Role = "Gear", Size = 77 })
			T.eq(plain:GetAttribute("TileArt"), nil, "no picture for Gear")
			T.eq(plain:GetAttribute("DarkTile"), true, "its dark tile")
			T.truthy((plain:FindFirstChild("Label") :: any).Visible, "its word")

			-- the old pixel look keeps its own tiles
			PopTheme.setLook("Pixel")
			local pixel = HudBubble.tile(holder, spec)
			PopTheme.setLook("Round")
			T.eq(pixel:GetAttribute("TileArt"), nil, "the pixel look")
		end)
		UIConfig.LightUI, IconAssets.Previewing = before, previewing
		PopTheme.setLook("Round")
		if not ok then
			error(err, 0)
		end
	end)

	-- the hoverboard tile's picture says Hoverboard: while riding, Stop shows over the drawn word
	T.test("HudBubble: the Ride tile with the owner's picture says Stop while riding", function()
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local HoverboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HoverboardView")
		local before = UIConfig.LightUI
		UIConfig.LightUI = true
		local ok, err = pcall(function()
			local refs = HudBubble.buildGame(1, 1280, false, false, 684)
			local ride = HoverboardView.rideTile(refs.Menu) :: any
			T.truthy(ride, "the tile")
			T.eq(ride.Button:GetAttribute("TileArt"), "hoverboard", "his picture")
			T.falsy(ride.Label.Visible, "walking: only the picture")
			HoverboardView.setRiding(ride, true)
			T.truthy(ride.Label.Visible, "riding: the word shows")
			T.eq(ride.Label.Text, "Stop", "says Stop")
			HoverboardView.setRiding(ride, false)
			T.falsy(ride.Label.Visible, "back to the picture")
			refs.Gui:Destroy()
		end)
		UIConfig.LightUI = before
		if not ok then
			error(err, 0)
		end
	end)
end
