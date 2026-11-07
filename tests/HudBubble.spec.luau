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
		local sizes = { Vector2.new(1, 1), Vector2.new(1, 1), Vector2.new(2000, 970) }
		local reads, steps = 0, 0
		local ready = HudBubble.waitForScreen(5, function()
			reads = math.min(reads + 1, #sizes)
			return sizes[reads]
		end, function()
			steps += 1
		end)
		T.truthy(ready, "the real size came")
		T.eq(steps, 2, "two frames waited")
		T.falsy(
			HudBubble.waitForScreen(0, function()
				return Vector2.new(1, 1)
			end, function() end),
			"never a real size: gives up, never hangs"
		)
		T.truthy(
			HudBubble.waitForScreen(0, function()
				return Vector2.new(568, 320) -- (the smallest phone is a real screen)
			end),
			"a phone needs no wait"
		)

		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local before = UIConfig.LightUI
		UIConfig.LightUI = true
		local ok, err = pcall(function()
			-- the owner's window: the four big tabs with the Shop first, and the offers
			local window = HudBubble.buildGame(1.25, 2000, false, false, 912)
			T.truthy(window.TopBar:FindFirstChild("ShopPill"), "the Shop leads the top row")
			T.eq(window.TopBar:GetAttribute("Narrow"), false, "not the phone's row")
			T.eq((window.TopBar:GetAttribute("Button") :: any).X, HudBubble.TabMax, "the big tabs")
			T.truthy(window.Gui:FindFirstChild("Offers"), "the offers")
			window.Gui:Destroy()
			-- what the 1 x 1 viewport gave him (why the wait matters)
			local tiny = HudBubble.buildGame(HudBubble.scaleFor(Vector2.new(1, 1)), 1, false, false, 912)
			T.falsy(tiny.TopBar:FindFirstChild("ShopPill"), "the tiny viewport: no Shop")
			T.falsy(tiny.Gui:FindFirstChild("Offers"), "the tiny viewport: no offers")
			tiny.Gui:Destroy()
		end)
		UIConfig.LightUI = before
		if not ok then
			error(err, 0)
		end
	end)
end
