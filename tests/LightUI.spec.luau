-- The light UI switch (UIConfig.LightUI) under Lune: OFF by default and then
-- HudView builds today's HUD; ON, HudView forwards to the light HUD with the
-- same refs, TeleportView fills its top bar with bubble tabs + the LIFT tile
-- and BuildView claims the BUILD tile (no dead buttons).
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3
local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2
local Instance = roblox.Instance

return function(T, Loader)
	local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
	local function ui(name: string)
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local HudView = ui("HudView")
	local TeleportView = ui("TeleportView")
	local BuildView = ui("BuildView")

	local FIELDS = {
		"Gui", "Coins", "CoinsPanel", "Income", "Floaters", "Zone", "Toasts",
		"CarryPanel", "CarrySlots", "CarryLabel", "ThrowBar", "ThrowFill", "Menu", "TopBar",
	}

	-- runs fn with the flag on, always switching it back
	local function withLight(fn: () -> ())
		local before = UIConfig.LightUI
		UIConfig.LightUI = true
		local ok, err = pcall(fn)
		UIConfig.LightUI = before
		if not ok then
			error(err, 0)
		end
	end

	T.test("LightUI: switched off, today's HUD", function()
		T.eq(type(UIConfig.Default), "boolean", "the switch that ships")
		T.falsy(UIConfig.LightUI, "the runner tests the dark paths unless a spec switches it on")
		T.falsy(UIConfig.lightUI(), "no test attribute in Lune")
		local refs = HudView.build()
		T.falsy(refs.TopBar:GetAttribute("Bubble"), "old top bar")
		T.falsy(refs.Menu:GetAttribute("Bubble"), "old menu")
		T.falsy(refs.Gui:GetAttribute("Bubble"), "old HUD")
	end)

	T.test("LightUI: on, HudView forwards to the light HUD with every ref", function()
		withLight(function()
			local refs = HudView.build() :: any
			T.truthy(refs.Gui:GetAttribute("Bubble"), "light HUD")
			for _, field in FIELDS do
				T.truthy(refs[field], "ref " .. field)
			end
			for _, child in refs.Menu:GetChildren() do
				if child:IsA("Frame") then
					T.falsy(child.Visible, "tile hidden until claimed: " .. child.Name)
				end
			end
			-- carry slots, floaters, toasts, offline popup
			local slot = HudView.slot(refs.CarrySlots, Color3.new(1, 0, 0), 1, false)
			T.truthy(slot:FindFirstChild("Ore", true), "ore colour in the slot")
			local dirty = HudView.slot(refs.CarrySlots, nil, 2, true)
			T.truthy(dirty:FindFirstChild("Mystery", true), "dirty ore shows ?")
			local more = HudView.moreSlot(refs.CarrySlots, 7, 3)
			T.eq((more:FindFirstChild("More", true) :: any).Text, "+7", "+N on the last slot")
			T.truthy(HudView.floater(refs.Floaters, "+$5"):IsA("TextLabel"), "floater")
			T.truthy(HudView.toast(refs.Toasts, "Hi", Color3.new(0, 1, 0)):FindFirstChild("Dot", true), "toast")
			local offline = HudView.buildOffline()
			T.truthy(offline.Collect and offline.Amount and offline.Detail and offline.Panel, "offline popup")
			T.falsy(offline.Gui.Enabled, "offline starts hidden")
		end)
	end)

	T.test("LightUI: teleport tabs, LIFT tile and BUILD tile", function()
		withLight(function()
			for _, scale in { 1.25, 0.62 } do
				local refs = ui("HudBubble").buildGame(scale)
				local teleport = TeleportView.build(refs.TopBar, refs.Menu, scale)
				for _, id in { "Base", "Lobby", "Vault" } do
					T.truthy(teleport.Buttons[id], "tab " .. id)
					T.eq(teleport.Buttons[id]:GetAttribute("Teleport"), id, "teleport id")
				end
				T.truthy(teleport.Side, "LIFT tile")
				T.falsy((teleport.Side.Parent :: any).Visible, "LIFT hidden until an elevator exists")
				TeleportView.setSideVisible(teleport, true)
				T.truthy((teleport.Side.Parent :: any).Visible, "LIFT shows with an elevator")
				TeleportView.setCooldown(teleport, 3)
				T.truthy(teleport.Covers.Base.Visible, "cooldown cover")
				T.eq(teleport.Covers.Base.Text, "3", "seconds left")
				TeleportView.relayout(teleport, refs.TopBar, 1) -- a no-op for the light bar
				local build = BuildView.menuButton(refs.Menu)
				T.truthy(build:IsA("TextButton"), "BUILD button")
				T.truthy((build.Parent :: any).Visible, "BUILD tile shown")
				T.eq((build.Parent :: any).Name, "Build", "the BUILD tile")
			end
		end)
	end)

	T.test("LightUI: the Vault window gets the light header and its X stays on screen", function()
		local VaultView = ui("VaultView")
		withLight(function()
			for _, spec in { { false, 1280, 691 }, { true, 1000, 520 }, { true, 916, 480 } } do
				local compact, maxW, maxH = spec[1], spec[2], spec[3]
				local refs = VaultView.build()
				VaultView.layout(refs, compact, maxW, maxH)
				VaultView.setCards(refs, VaultView.cards(3, 125400))
				T.truthy(refs.Header:FindFirstChild("HeaderIcon", true), "3D vault icon")
				T.eq(refs.Header.Position.X.Offset, 0, "full-width band")
				local closeHolder = refs.Close.Parent :: any
				local closeW = closeHolder.Size.X.Offset
				local panelW = refs.Panel.Size.X.Offset
				-- the X's centre is 12 in from the panel's corner: it sticks out closeW/2 - 12
				T.truthy(panelW + 2 * (closeW / 2 - 12) <= maxW, "the X fits on screen")
				T.truthy(closeW * 0.62 >= 44 or not compact, "X >= 44 pt on phones")
			end
		end)
		local plain = VaultView.build()
		VaultView.layout(plain, false, 1280, 691)
		T.falsy(plain.Header:FindFirstChild("HeaderIcon", true), "switch off: today's header")
		T.eq(plain.Header.Position.X.Offset, 10, "switch off: today's layout")
	end)

	T.test("LightUI: build mode in the light look keeps BuildView's behaviour", function()
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		withLight(function()
			local refs = BuildView.build()
			T.truthy(refs.Gui:GetAttribute("Bubble"), "light build UI")
			BuildView.setInventory(refs, { ClayFurnace = 2, Crusher = 1, Conveyor = 0 }, "Crusher", function() end)
			T.truthy(refs.Cards.ClayFurnace.Button.Visible, "owned card shown")
			T.falsy(refs.Cards.Conveyor.Button.Visible, "zero count hidden (the whole card)")
			T.eq(refs.Cards.ClayFurnace.Count.Text, "x2", "count chip")
			T.eq(refs.Cards.Crusher.Stroke.Color, BubbleTheme.Gold, "selected card in gold")
			T.eq(refs.Cards.ClayFurnace.Stroke.Color, BubbleTheme.Outline, "others plain")
			BuildView.setCounts(refs, 10, 10, 0, 40)
			T.eq(refs.Chip.TextColor3, BubbleTheme.Bad, "full: red on the white pill")
			BuildView.setCounts(refs, 1, 10, 0, 40)
			T.eq(refs.Chip.TextColor3, BubbleTheme.Ink, "dark text on the white pill")
			BuildView.setMode(refs, "Placing", true)
			T.truthy((refs.Place.Parent :: any).Visible and (refs.Rotate.Parent :: any).Visible, "touch buttons for placing")
			T.falsy((refs.Move.Parent :: any).Visible, "MOVE hidden while placing")
			T.truthy((refs.Place.Parent :: any).Size.Y.Offset * 0.62 >= 44, "touch buttons >= 44 pt")
			BuildView.setMode(refs, "Placing", false)
			T.falsy(refs.Actions.Visible, "no touch buttons with a mouse")
		end)
	end)

	T.test("LightUI: the Ore Pen wears the light look and keeps its behaviour", function()
		local PenView = ui("PenView")
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		local entries = {
			{ Key = "a", Kind = "Clean", Name = "Clean Silver", Grade = "Clean", Count = 3, Income = 12, Value = 1, Color = Color3.new(0.7, 0.7, 0.8), Mystery = false },
			{ Key = "b", Kind = "Raw", Name = "Dirty Ore", Count = 2, Income = 0, Value = 0, Color = Color3.new(0.5, 0.5, 0.5), Mystery = true },
		}
		withLight(function()
			for _, compact in { false, true } do
				local refs = PenView.build()
				PenView.setCompact(refs, compact)
				T.truthy(refs.Gui:GetAttribute("Bubble"), "light pen")
				T.truthy(refs.Panel:FindFirstChild("HeaderIcon"), "3D backpack in the header")
				T.eq(refs.Panel.BackgroundColor3, BubbleTheme.Panel, "white panel")
				local rows = PenView.setEntries(refs, entries, true)
				T.eq(#rows, 2, "a row per entry")
				T.eq(refs.Rows.a.Name.TextColor3, BubbleTheme.Ink, "dark item names")
				T.truthy(refs.Rows.a.Income.TextColor3 ~= BubbleTheme.Panel, "income readable")
				PenView.setHeader(refs, 3, 40)
				T.eq(refs.Header.TextColor3, BubbleTheme.Ink, "count in dark text")
				PenView.setSending(refs, nil, true, 0)
				T.eq(refs.SendDirty.BackgroundColor3, BubbleTheme.Roles.Plain.Base, "no dirty ore: a plain button")
				PenView.setAutoSort(refs, true, false)
				T.eq(refs.AutoSort.Text, "AUTO-SORT OFF", "switch text")
				local take = refs.Rows.a.Take.Parent :: any
				T.truthy(not compact or take.Size.Y.Offset * 0.62 >= 44, "phone buttons >= 44 pt")
			end
		end)
		local plain = PenView.build()
		T.falsy(plain.Gui:GetAttribute("Bubble"), "switch off: today's pen")
		T.falsy(plain.Panel:FindFirstChild("HeaderIcon"), "switch off: no light header")
	end)

	T.test("LightSkin: old dark panels become light, text stays readable", function()
		local LightSkin = ui("LightSkin")
		local UIKit = ui("UIKit")
		local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		local gui = UIKit.screen("Old")
		local panel = UIKit.panel(gui, { Size = UDim2.fromOffset(400, 300) })
		local body = UIKit.label(panel, "Body text", 18)
		local title = UIKit.label(panel, "TITLE", 30, { FontFace = Theme.TitleFont, TextColor3 = Theme.Accent })
		local button = UIKit.button(panel, "BUY", Theme.Good, Theme.GoodDark)
		local over = UIKit.label(gui, "Over the world", 18)
		LightSkin.apply(gui)
		T.truthy(gui:GetAttribute("LightSkin"), "marked")
		T.eq(panel.BackgroundColor3, BubbleTheme.Panel, "white panel")
		T.eq(panel:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Outline, "navy outline")
		T.eq(body.TextColor3, BubbleTheme.Ink, "dark body text")
		T.falsy(body:FindFirstChildOfClass("UIStroke").Enabled, "no outline on body text")
		T.truthy(title:FindFirstChildOfClass("UIStroke").Enabled, "titles keep a thin edge")
		T.eq(button.BackgroundColor3, BubbleTheme.Roles.Go.Base, "light green button")
		T.eq(button.TextColor3, BubbleTheme.White, "white text on the button")
		T.eq(over.TextColor3, BubbleTheme.White, "white text over the world")
		-- a controller setting the old colour again (Lune: refresh stands in for the signal)
		body.TextColor3 = Theme.Text
		LightSkin.refresh(gui)
		T.eq(body.TextColor3, BubbleTheme.Ink, "mapped again")
		LightSkin.refresh(gui)
		T.eq(panel.BackgroundColor3, BubbleTheme.Panel, "idempotent")
	end)

	T.test("LightUI: the older windows wear the light skin only with the switch on", function()
		local function builds(): { [string]: any }
			return {
				Sell = ui("SellView").build(false).Gui,
				TechShop = ui("TechShopView").build(false).Gui,
				Train = ui("TrainView").build(false).Gui,
				IronBox = ui("IronBoxView").build().Gui,
				Foundry = ui("FoundryView").build().Gui,
				Forge = ui("FoundryView").buildForge(false).Gui,
				Cleaning = ui("CleaningView").build().Gui,
			}
		end
		for name, gui in builds() do
			T.falsy(gui:GetAttribute("LightSkin"), "switch off: today's " .. name)
		end
		withLight(function()
			for name, gui in builds() do
				T.truthy(gui:GetAttribute("LightSkin"), "switch on: light " .. name)
			end
		end)
	end)

	T.test("LightUI: gamepad order of the menu tiles and the teleport tabs", function()
		local HudBubble = ui("HudBubble")
		withLight(function()
			local refs = HudBubble.buildGame(1.25)
			local build = HudBubble.claimTile(refs.Menu, "Build")
			local shop = HudBubble.claimTile(refs.Menu, "Shop")
			local lift = HudBubble.claimTile(refs.Menu, "Elevator")
			local faces = HudBubble.linkMenu(refs.Menu)
			T.eq(#faces, 3, "only the claimed tiles")
			T.eq(faces[1], build, "grid order")
			T.eq(build.NextSelectionRight, shop, "right along the row")
			T.eq(shop.NextSelectionLeft, build, "left along the row")
			T.eq(build.NextSelectionDown, lift, "down the column")
			T.eq(lift.NextSelectionUp, build, "up the column")
			T.truthy(shop.NextSelectionRight ~= lift, "the row ends at SHOP")
			local teleport = TeleportView.build(refs.TopBar, refs.Menu, 1.25)
			T.eq(teleport.Buttons.Base.NextSelectionRight, teleport.Buttons.Lobby, "BASE -> LOBBY")
			T.eq(teleport.Buttons.Vault.NextSelectionLeft, teleport.Buttons.Lobby, "VAULT -> LOBBY")
			local outline = HudBubble.selectionImage()
			T.truthy(outline:FindFirstChildOfClass("UIStroke"), "gold selection outline")
		end)
	end)

	T.test("LightUI: on a small phone the coins and the teleport bar don't meet", function()
		local HudBubble = ui("HudBubble")
		withLight(function()
			for _, screen in { Vector2.new(667, 375), Vector2.new(568, 320), Vector2.new(932, 430) } do
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, screen.X)
				local width = screen.X / scale
				local barLeft = width / 2 - refs.TopBar.Size.X.Offset / 2
				local coinsRight = refs.CoinsPanel.Position.X.Offset + refs.CoinsPanel.Size.X.Offset
				T.truthy(coinsRight < barLeft, `coins clear of the tabs at {screen.X} x {screen.Y}`)
			end
		end)
	end)

	T.test("LightUI: the tutorial bubble keeps clear of the light tabs on touch screens", function()
		local TutorialView = ui("TutorialView")
		local HudBubble = ui("HudBubble")
		withLight(function()
			for _, screen in { Vector2.new(568, 320), Vector2.new(667, 375), Vector2.new(932, 430), Vector2.new(1024, 768) } do
				local scale = HudBubble.scaleFor(screen)
				local layout = TutorialView.layout(scale, screen, true, false, nil)
				local hud = HudBubble.buildGame(scale, screen.X)
				local w = screen.X / scale
				local tabsRight = w / 2 + hud.TopBar.Size.X.Offset / 2
				local bubbleLeft = layout.Position.X - layout.Width
				T.truthy(bubbleLeft >= tabsRight, `bubble right of the tabs at {screen.X} x {screen.Y}`)
				T.truthy(layout.RowHeight * scale >= 44, "SKIP >= 44 pt")
			end
			local refs = TutorialView.build()
			T.truthy(refs.Gui:GetAttribute("LightSkin"), "light bubble")
		end)
		T.falsy(TutorialView.build().Gui:GetAttribute("LightSkin"), "switch off: today's bubble")
	end)

	T.test("LightUI: prompt pills and world labels", function()
		local LightPrompt = ui("LightPrompt")
		local LightSkin = ui("LightSkin")
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		local prompt = LightPrompt.build("Open Shop", "Tobin's Ore Stall", "F")
		T.eq(prompt.Action.Text, "OPEN SHOP", "action in capitals")
		T.eq(prompt.Key.Text, "F", "key letter")
		T.truthy(prompt.Gui:FindFirstChild("Pill"), "the pill")
		T.truthy(LightPrompt.Height * 0.62 >= 38, "big enough to tap at the phone scale")
		LightPrompt.setKey(prompt, "TAP", nil)
		T.eq(prompt.Key.TextSize, 15, "TAP fits the circle")
		LightPrompt.setHold(prompt, 2)
		T.eq(prompt.Fill.Size.X.Scale, 1, "hold clamps to 1")
		local short = LightPrompt.width("Go", "")
		local long = LightPrompt.width("Take Ore Back To The Pen", "")
		T.truthy(long > short and short >= LightPrompt.MinWidth, "the pill grows with its text")
		-- a floating label gets the bold navy edge
		local tag = Instance.new("BillboardGui")
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.TextSize = 40
		label.Parent = tag
		LightSkin.world(tag)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		T.truthy(stroke and stroke.Color == BubbleTheme.Outline and stroke.Thickness >= 4, "bold navy edge")
		T.eq(label.TextStrokeTransparency, 1, "the thin built-in edge is off")
	end)

	T.test("LightUI: side menu entries become light tiles and a MORE flyout", function()
		local HudBubble = ui("HudBubble")
		local SideMenuView = ui("SideMenuView")
		withLight(function()
			local hud = HudBubble.buildGame(1.25)
			local faces = {}
			for _, entry in SideMenuView.sorted() do
				local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
				faces[entry.Id] = if entry.Group == "Main"
					then HudBubble.claimTile(hud.Menu, entry.Id, spec)
					else HudBubble.addMore(hud.Menu, entry.Id, spec)
			end
			local flyout = hud.Gui:FindFirstChild("MoreFlyout")
			T.truthy(flyout, "the MORE flyout")
			T.falsy(flyout.Visible, "starts shut")
			T.truthy((hud.Menu:FindFirstChild("More") :: any).Visible, "MORE tile shown once it has entries")
			for _, entry in SideMenuView.Entries do
				local face = faces[entry.Id]
				T.truthy(face, "tile for " .. entry.Id)
				local icon = face:FindFirstChild("Icon")
				T.truthy(icon and icon:GetAttribute("Icon") ~= "more", "a 3D icon for " .. entry.Id)
				if entry.Group == "More" then
					T.truthy(face:IsDescendantOf(flyout), entry.Id .. " behind MORE")
				else
					T.truthy(face:IsDescendantOf(hud.Menu), entry.Id .. " on the left")
				end
			end
			T.truthy(HudBubble.toggleMore(hud.Menu), "MORE opens")
			T.falsy(HudBubble.toggleMore(hud.Menu), "and shuts")
			HudBubble.setTileBadge(faces.Codex, 3)
			T.truthy(faces.Codex:FindFirstChild("Badge"), "badge")
			HudBubble.setTileBadge(faces.Codex, 0)
			T.falsy(faces.Codex:FindFirstChild("Badge"), "badge gone at 0")
			HudBubble.setTileVisible(hud.Menu, "Golems", false)
			T.falsy((hud.Menu:FindFirstChild("Golems") :: any).Visible, "hidden entry hides its tile")
		end)
	end)

	T.test("LightUI: the steps 6-7 windows wear the light skin only with the switch on", function()
		local function builds(): { [string]: any }
			return {
				Boost = ui("BoostView").build(false).Gui,
				BoostChips = ui("BoostView").buildChips().Gui,
				Capsule = ui("CapsuleView").build(false).Gui,
				Opening = ui("CapsuleView").buildOpening(false).Gui,
				Collection = ui("CollectionView").build(false).Gui,
				Banner = ui("CollectionView").buildBanner(false).Gui,
				Enchant = ui("EnchantView").build(false).Gui,
				Gear = ui("GearShopView").build(false).Gui,
				Golem = ui("GolemView").build(false).Gui,
				Story = ui("StoryView").build(false).Gui,
				Wheel = ui("WheelView").build(false).Gui,
				Panel = ui("MenuPanel").build("Test", "TEST", "sub", nil).Gui,
			}
		end
		for name, gui in builds() do
			T.falsy(gui:GetAttribute("LightSkin"), "switch off: today's " .. name)
		end
		withLight(function()
			for name, gui in builds() do
				T.truthy(gui:GetAttribute("LightSkin"), "switch on: light " .. name)
			end
		end)
	end)

	T.test("LightUI: game HUD touch sizes on phones", function()
		local layout = ui("HudBubble").layout(ui("HudBubble").scaleFor(Vector2.new(844, 390)))
		T.truthy(layout.Compact, "a phone gets the compact layout")
		T.truthy(layout.Tile * 0.62 >= 44 and layout.Slot * 0.62 >= 44 and layout.TabHeight * 0.62 >= 44, ">= 44 pt")
	end)

	T.test("LightUI: emoji stand-ins until the icon sheets are uploaded, one elevator tile", function()
		local Bubble = ui("Bubble")
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		local HudBubble = ui("HudBubble")
		local SideMenuView = ui("SideMenuView")
		local holder = Instance.new("Frame")
		for _, name in { "backpack", "golem_PebbleGolem", "machine_Crusher", "artifact_CrownCoin", "lift" } do
			local icon = Bubble.icon(holder, name, 60)
			local stand = icon:FindFirstChild("Fallback")
			T.truthy(stand and stand:GetAttribute("IconFallback"), "a stand-in for " .. name)
			T.eq(stand.Text, IconAssets.fallback(name), "its emoji")
		end
		local robux = Bubble.icon(holder, "robux", 60)
		T.falsy(robux:FindFirstChild("Fallback"), "Roblox's own robux picture needs none")
		local sheet = IconAssets.Sheets[1]
		local before = sheet.Id
		sheet.Id = 123
		local ok, err = pcall(function()
			T.falsy(Bubble.icon(holder, "backpack", 60):FindFirstChild("Fallback"), "none once uploaded")
		end)
		sheet.Id = before
		if not ok then
			error(err, 0)
		end

		withLight(function()
			local entries = SideMenuView.Entries
			local had = SideMenuView.hasEntry("Elevator")
			local added = false
			if not had then
				table.insert(entries, { Id = "Elevator", Label = "ELEVATOR", IconName = "lift", Group = "Main", Order = 50 })
				added = true
			end
			local done, problem = pcall(function()
				local refs = HudBubble.buildGame(1.25)
				local teleport = TeleportView.build(refs.TopBar, refs.Menu, 1.25)
				T.falsy(teleport.Side, "the LIFT teleport leaves the tile to the side menu's Elevator")
				local count = 0
				for _, child in refs.Menu:GetChildren() do
					if child.Name == "Elevator" then
						count += 1
					end
				end
				T.eq(count, 1, "one ELEVATOR tile")
			end)
			if added then
				table.remove(entries, #entries)
			end
			if not done then
				error(problem, 0)
			end
		end)
	end)
end
