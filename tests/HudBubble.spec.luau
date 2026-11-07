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
		local fifth = HudBubble.tilePosition(layout, 5)
		T.eq(first.X.Offset, m.Origin.X.Offset, "first tile at the origin")
		T.eq(fifth.Y.Offset - first.Y.Offset, 2 * (m.CellHeight + m.RowGap), "row 3 on PC (2 columns)")
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
		-- (the controller needs a real client: its source says what init does, in which order)
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/HudController.luau")
		local init = string.find(source, "function HudController.init()", 1, true)
		T.truthy(init, "init")
		local wait = string.find(source, "HudBubble.waitForScreen()", init, true)
		local build = string.find(source, "HudView.build()", init, true)
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
end
