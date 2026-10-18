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
		local phone = HudBubble.layout(0.62)
		local p5 = HudBubble.tilePosition(phone, 5)
		local p1 = HudBubble.tilePosition(phone, 1)
		T.eq(p5.Y.Offset - p1.Y.Offset, HudBubble.menuMetrics(phone).CellHeight + HudBubble.menuMetrics(phone).RowGap, "row 2 on phones (3 columns)")
	end)

	T.test("HudBubble: phone layout keeps touch targets >= 44 pt", function()
		local layout = HudBubble.layout(0.62)
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
end
