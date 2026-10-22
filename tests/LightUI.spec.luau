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
		"Gui",
		"Coins",
		"CoinsPanel",
		"Income",
		"Floaters",
		"Zone",
		"Toasts",
		"CarryPanel",
		"CarrySlots",
		"CarryLabel",
		"ThrowBar",
		"ThrowFill",
		"Menu",
		"TopBar",
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

	-- (review #10) the Pop bar stays inside Roblox's free top-row span, or drops under the row
	T.test("LightUI: the top bar keeps clear of Roblox's top-row buttons", function()
		local HudBubble = ui("HudBubble")
		local V2 = Vector2.new
		-- unknown row: centred in the row
		local x, inRow = HudBubble.topBarX(nil, 0, 667, 416, 0.62)
		T.eq(x, 0)
		T.truthy(inRow)
		-- a phone whose left buttons reach 240 px: the bar moves right, inside the free span
		x, inRow = HudBubble.topBarX(V2(240, 620), 0, 667, 416, 0.62)
		T.truthy(inRow, "fits in the row")
		local left = 667 / 2 + x * 0.62 - 416 * 0.62 / 2
		local right = left + 416 * 0.62
		T.truthy(left >= 240 and right <= 620, `inside the free span ({left}..{right})`)
		-- no room in the row: under it
		x, inRow = HudBubble.topBarX(V2(300, 400), 0, 667, 416, 0.62)
		T.falsy(inRow, "drops under the row")
	end)

	-- (review #8) the gamepad glyph for the bar is a real size, left of the bar
	T.test("LightUI: the Pop bar's gamepad hint is visible size", function()
		local HudBubble = ui("HudBubble")
		local TeleportView = ui("TeleportView")
		withLight(function()
			local refs = HudBubble.buildGame(1.25)
			local bar = TeleportView.build(refs.TopBar, 1.25)
			T.truthy(bar.Hint.Size.X.Offset >= 34 and bar.Hint.Size.Y.Offset >= 34, "a real glyph size")
			T.eq(bar.Hint.Parent, refs.TopBar.Parent, "beside the bar, not squeezed into it")
			T.truthy(bar.Hint.Position.X.Offset < refs.TopBar.Position.X.Offset - refs.TopBar.Size.X.Offset / 2, "left of the bar")
		end)
	end)

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

	T.test("LightUI: teleport tabs and BUILD tile", function()
		withLight(function()
			for _, scale in { 1.25, 0.62 } do
				local refs = ui("HudBubble").buildGame(scale)
				local teleport = TeleportView.build(refs.TopBar, scale)
				for _, id in { "Base", "Lobby", "Vault" } do
					T.truthy(teleport.Buttons[id], "tab " .. id)
					T.eq(teleport.Buttons[id]:GetAttribute("Teleport"), id, "teleport id")
				end
				T.falsy(teleport.Buttons.Elevator, "the elevator's tile is the side menu's")
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
			-- platforms: the DECK / GROUND toggle
			BuildView.setMode(refs, "Selected", true, true)
			T.truthy((refs.Layer.Parent :: any).Visible, "DECK / GROUND shows with platforms")
			BuildView.setLayer(refs, true)
			T.eq((refs.Layer:FindFirstChild("Label") :: any).Text, "GROUND", "the layer on the light button")
			BuildView.setLayer(refs, false)
			T.eq((refs.Layer:FindFirstChild("Label") :: any).Text, "DECK", "and back")
			BuildView.setMode(refs, "Selected", true, false)
			T.falsy((refs.Layer.Parent :: any).Visible, "hidden without platforms")
		end)
	end)

	T.test("Pop: the Ore Pen wears the Pop look (switch on and off) and keeps its behaviour", function()
		local PenView = ui("PenView")
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		local entries = {
			{
				Key = "Clean|Silver|Clean|",
				Kind = "Clean",
				Name = "Clean Silver",
				Grade = "Clean",
				Count = 3,
				Income = 12,
				Value = 1,
				Color = Color3.new(0.7, 0.7, 0.8),
				Mystery = false,
			},
			{
				Key = "Dirty",
				Kind = "Raw",
				Name = "Dirty Ore",
				Count = 2,
				Income = 0,
				Value = 0,
				Color = Color3.new(0.5, 0.5, 0.5),
				Mystery = true,
				Keys = { ["Raw|Copper||"] = 2 },
			},
		}
		local function check(compact: boolean)
			local refs = PenView.build()
			PenView.setCompact(refs, compact)
			T.truthy(refs.Gui:GetAttribute("Pop"), "the Pop pen")
			T.falsy(refs.Gui:GetAttribute("LightSkin"), "never re-skinned")
			T.truthy(refs.Panel:FindFirstChild("Header") and refs.Panel:FindFirstChild("Body"), "the header band and the studded body")
			T.eq(refs.Panel.BackgroundColor3, PopTheme.Outline, "the black frame")
			local rows = PenView.setEntries(refs, entries, true)
			T.eq(#rows, 2, "a row per entry")
			local silver = refs.Rows["Clean|Silver|Clean|"]
			T.eq(silver.Name.TextColor3, PopTheme.Ink, "white item names")
			T.truthy(silver.Frame:FindFirstChild("Paint"), "a painted row")
			T.eq(silver.Icon:FindFirstChild("Picture"):GetAttribute("Icon"), "item_Clean_Silver", "the item's 3D picture")
			T.truthy(refs.Rows.Dirty.Mystery.Visible, "dirty ore: a question mark")
			T.eq(refs.Rows.Dirty.Icon:FindFirstChild("Picture"):GetAttribute("Icon"), "ore_raw", "never which ore")
			T.eq(silver.Income.TextColor3, PopTheme.Money, "income in money green")
			PenView.setHeader(refs, 3, 40)
			T.eq(refs.Header.TextColor3, PopTheme.Ink, "count in white")
			PenView.setSending(refs, nil, true, 0)
			T.near(refs.SendDirty.TextTransparency, 0.4, 1e-4, "no dirty ore: dimmed")
			PenView.setAutoSort(refs, true, false)
			T.eq(refs.AutoSort.Text, "AUTO-SORT OFF", "switch text")
			local take = refs.Rows["Clean|Silver|Clean|"].Take.Parent :: any
			T.truthy(not compact or take.Size.Y.Offset * 0.62 >= 44, "phone buttons >= 44 pt")
		end
		for _, compact in { false, true } do
			check(compact)
			withLight(function()
				check(compact)
			end)
		end
	end)

	T.test("LightSkin: old windows get the dark card look, text stays readable", function()
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
		T.eq(panel.BackgroundColor3, BubbleTheme.Panel, "dark slate panel")
		T.eq(panel:FindFirstChildOfClass("UIStroke").Color, BubbleTheme.Outline, "near-black outline")
		T.eq(body.TextColor3, BubbleTheme.Ink, "cream body text")
		T.truthy(body:FindFirstChildOfClass("UIStroke").Enabled, "with a dark edge, like the store cards")
		T.truthy(title:FindFirstChildOfClass("UIStroke").Enabled, "titles keep their edge")
		T.eq(button.BackgroundColor3, BubbleTheme.Roles.Go.Base, "the kit's green button")
		T.eq(button.TextColor3, BubbleTheme.Ink, "cream text on the button")
		T.eq(over.TextColor3, BubbleTheme.Ink, "cream text over the world")
		-- a controller setting the old colour again (Lune: refresh stands in for the signal)
		body.TextColor3 = Theme.Text
		LightSkin.refresh(gui)
		T.eq(body.TextColor3, BubbleTheme.Ink, "mapped again")
		LightSkin.refresh(gui)
		T.eq(panel.BackgroundColor3, BubbleTheme.Panel, "idempotent")
		-- a bright rarity colour keeps its hue, a shade darker; again: the same
		local rare = UIKit.label(panel, "Gold (Rare)", 18, { TextColor3 = Color3.fromRGB(255, 236, 120) })
		LightSkin.refresh(gui)
		local once = rare.TextColor3
		local h = once:ToHSV()
		T.truthy(math.abs(h - Color3.fromRGB(255, 236, 120):ToHSV()) < 0.01, "same hue")
		T.truthy(once ~= BubbleTheme.Ink, "not plain ink")
		LightSkin.refresh(gui)
		T.eq(rare.TextColor3, once, "idempotent")
		-- the STAR FORGE window's tabs
		local tab = UIKit.button(panel, "STAR SHOP", Color3.fromRGB(120, 108, 100), Color3.fromRGB(70, 62, 58))
		LightSkin.refresh(gui)
		T.eq(tab.BackgroundColor3, BubbleTheme.Roles.Settings.Base, "grey tab becomes the light grey role")
	end)

	T.test("Pop: the Sell, Tech Shop and Keep List windows wear the Pop look (switch on and off)", function()
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		local function builds(): { [string]: any }
			return {
				Sell = ui("SellView").build(false),
				TechShop = ui("TechShopView").build(false),
				IronBox = ui("IronBoxView").build(),
			}
		end
		local function check(label: string)
			for name, refs in builds() do
				T.truthy(refs.Gui:GetAttribute("Pop"), `{label}: Pop {name}`)
				T.falsy(refs.Gui:GetAttribute("LightSkin"), `{label}: {name} never re-skinned`)
				T.eq(refs.Panel.BackgroundColor3, PopTheme.Outline, `{label}: {name}'s black frame`)
				T.truthy(refs.Panel:FindFirstChild("Header") and refs.Panel:FindFirstChild("Body"), `{label}: {name}'s band and body`)
				T.eq(refs.Title.TextColor3, PopTheme.Ink, `{label}: {name}'s white title`)
				T.truthy(refs.Panel:FindFirstChild("TitleShadow"), `{label}: {name}'s title shadow`)
				local closeFace = refs.Close.Parent
				T.truthy(closeFace:FindFirstChild("Paint"), `{label}: {name}'s painted X`)
				T.eq(closeFace:FindFirstChild("Paint").Color.Keypoints[1].Value, PopTheme.Close.Top, `{label}: {name}'s red X`)
				T.eq(refs.Close.BackgroundTransparency, 1, `{label}: {name}'s X draws its word over the face`)
			end
		end
		check("switch off")
		withLight(function()
			check("switch on")
		end)
	end)

	T.test("LightUI: the older windows wear the light skin only with the switch on", function()
		local function builds(): { [string]: any }
			return {
				Forge = ui("FoundryView").buildForge(false).Gui, -- (the Foundry panel wears the Pop look)
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

	-- the train panel, the Foundry, the Blaster Vault and the Star Forge wear the Pop
	-- look (owner 2026-10-21): never the LightSkin recolouring; the same refs, every
	-- touch target still >= 44 pt on phones, the BUY states as before
	T.test("LightUI: the Pop windows (train, foundry, vault, star forge) keep their behaviour", function()
		local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
		local TrainView = ui("TrainView")
		local FoundryView = ui("FoundryView")
		local VaultView = ui("VaultView")
		local RebirthView = ui("RebirthView")
		local MenuPanel = ui("MenuPanel")
		local PHONE = 0.62
		-- a gui object's size in design units (scale sizes resolved against the parents)
		local function absolute(gui: any): (number, number)
			local size = gui.Size
			local w, h = size.X.Offset, size.Y.Offset
			if (size.X.Scale ~= 0 or size.Y.Scale ~= 0) and gui.Parent and gui.Parent:IsA("GuiObject") then
				local pw, ph = absolute(gui.Parent)
				w += pw * size.X.Scale
				h += ph * size.Y.Scale
			end
			return w, h
		end
		local function bigEnough(label: string, target: any)
			local w, h = absolute(target)
			T.le(44, w * PHONE, `{label} {target.Name} wide enough`)
			T.le(44, h * PHONE, `{label} {target.Name} tall enough`)
		end
		for name, gui in
			{
				Train = TrainView.build(false).Gui,
				Foundry = FoundryView.build().Gui,
				Vault = VaultView.build().Gui,
				Rebirth = RebirthView.build().Gui,
			}
		do
			T.falsy(gui:GetAttribute("PopSkin"), "switch off: today's " .. name)
		end
		withLight(function()
			-- the train panel (the HUD chip keeps the light skin)
			local train = TrainView.build(true)
			T.truthy(train.Gui:GetAttribute("PopSkin"), "Pop train panel")
			T.falsy(train.Gui:GetAttribute("LightSkin"), "no LightSkin on the train panel")
			T.falsy(train.Chip:GetAttribute("LightSkin"), "no LightSkin on the HUD chip")
			T.truthy(train.Chip:GetAttribute("PopSkin"), "the HUD chip in the pixel look")
			T.truthy(train.Card:FindFirstChild("Picture"), "the live locomotive")
			for _, screen in { { 667, 375 }, { 568, 320 } } do
				TrainView.layout(train, true, screen[1] / PHONE, (screen[2] - 58) / PHONE)
				for _, target in TrainView.touchTargets(train) do
					bigEnough(`train {screen[1]}x{screen[2]}`, target)
				end
			end
			local capacity = train.Rows.Capacity
			TrainView.setUpgrades(train, TrainView.read({ Cargo = 8, Capacity = 8, CapacityLevel = 1 }), 100)
			T.eq(capacity.Buy.BackgroundColor3, Theme.PanelLight, "can't afford: greyed (the state colour)")
			TrainView.setUpgrades(train, TrainView.read({ Cargo = 8, Capacity = 8, CapacityLevel = 1 }), 1e9)
			T.eq(capacity.Buy.Text, "BUY")
			local face = capacity.Buy:FindFirstChild("PopFace") :: any
			T.truthy(face and face.Visible, "the gold coin and the price on BUY")
			T.eq(face:FindFirstChild("Amount").Text, capacity.Price.Text, "the row's price")
			-- the controller's states: "BOUGHT!" (greyed) and "…" show as words
			capacity.Buy.Text = "BOUGHT!"
			TrainView.style(capacity.Buy, false, Theme.Good, Theme.GoodDark)
			T.eq(capacity.Buy.TextTransparency, 0, "BOUGHT! shows")
			T.falsy(face.Visible, "no price on BOUGHT!")
			T.eq(capacity.Buy.BackgroundColor3, Theme.PanelLight, "BOUGHT! is greyed")
			T.eq(train.Express.Buy.Text, "SOON", "Express is a placeholder")
			local robux = train.Express.Buy:FindFirstChild("PopFace") :: any
			T.truthy(robux and robux.Visible, "the green Robux button")
			T.eq(robux:FindFirstChild("Amount").Text, tostring(TrainView.ExpressPrice))

			-- the Foundry (the hammer moment keeps the light skin)
			local foundry = FoundryView.build()
			T.truthy(foundry.Gui:GetAttribute("PopSkin"), "Pop Foundry")
			T.falsy(foundry.Gui:GetAttribute("LightSkin"), "no LightSkin on the Foundry")
			FoundryView.setCompact(foundry, true)
			local state = { FoundryStock = { ["Ingot|Gold|Clean|"] = 2, ["Ingot|Coal||"] = 4 }, BlasterLevel = 3, Coins = 1e9 }
			FoundryView.setRows(foundry, FoundryView.oreRows(state.FoundryStock, 3), 6)
			FoundryView.setCard(foundry, FoundryView.status(state, nil), state)
			T.truthy(foundry.Rows.Gold.Frame:FindFirstChild("Picture"), "a live ingot per row")
			T.eq(foundry.Rows.Gold.Take.Text, "TAKE")
			T.eq(foundry.Rows.Coal.Take.Text, "TAKE ALL")
			local coalShade = foundry.Rows.Coal.Frame:FindFirstChild("Shade") :: any
			T.truthy(coalShade and coalShade.Visible, "a row the next level can't use is shaded")
			T.truthy(foundry.Card:FindFirstChild("Picture"), "the next blaster's picture")
			for _, button in { foundry.Close, foundry.Forge, foundry.Rows.Gold.Take, foundry.LookPrev } do
				bigEnough("foundry", button.Parent)
			end
			-- (the TAKE switch's faces fit the header band: their buttons reach past them)
			for _, button in { foundry.TakeOne, foundry.TakeEvery } do
				bigEnough("foundry switch", button)
			end

			-- the Blaster Vault
			local vault = VaultView.build()
			T.truthy(vault.Gui:GetAttribute("PopSkin"), "Pop vault")
			for _, screen in { { 667, 375 }, { 568, 320 } } do
				VaultView.layout(vault, true, screen[1] / PHONE, (screen[2] - 58) / PHONE)
				VaultView.setCards(vault, VaultView.cards(3, 1e9))
				for _, target in VaultView.touchTargets(vault) do
					bigEnough(`vault {screen[1]}x{screen[2]}`, target)
				end
			end
			local nextTile = VaultView.tileFor(vault, 4) :: any
			T.eq(nextTile.ButtonText.Text, "BUY")
			local coin = nextTile.Button:FindFirstChild("PopFace") :: any
			T.truthy(coin and coin.Visible, "the gold coin BUY with the price")
			T.truthy(nextTile.Ribbon.Visible, "the NEXT chip")
			local owned = VaultView.tileFor(vault, 2) :: any
			T.eq(owned.ButtonText.Text, "OWNED")
			T.truthy(owned.Check.Visible, "the owned tick")
			T.truthy((VaultView.tileFor(vault, 6) :: any).Dim.Visible, "a locked case is shaded")

			-- the Star Forge
			local rebirth = RebirthView.build()
			T.truthy(rebirth.Gui:GetAttribute("PopSkin"), "Pop Star Forge")
			T.falsy(rebirth.Gui:GetAttribute("LightSkin"), "no LightSkin on the Star Forge")
			RebirthView.layout(rebirth, true, 568 / PHONE, (320 - 58) / PHONE)
			for _, button in RebirthView.buttons(rebirth) do
				bigEnough("star forge", MenuPanel.holderOf(button))
			end
			bigEnough("star forge", MenuPanel.holderOf(rebirth.Frame.Close))
			-- the requirement line still fits over the (taller, glowing) REBIRTH!
			local TechShopView = ui("TechShopView")
			local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
			local ready = { Count = 1, Stars = 3, Perks = {}, Level = 8, Ready = true, StarsNow = RebirthConfig.starsFor(8) }
			for _, screen in { { false, 1280, 720 - 36 }, { true, 568 / PHONE, (320 - 58) / PHONE } } do
				RebirthView.layout(rebirth, screen[1], screen[2], screen[3])
				RebirthView.setInfo(rebirth, ready)
				local need = rebirth.Need
				T.truthy(
					TechShopView.fits(need.Text, need.Size.X.Offset, need.Size.Y.Offset, need.TextSize, true),
					"the requirement line fits"
				)
				T.truthy((rebirth.Pages.Rebirth:FindFirstChild("PopGlow") :: any).Visible, "REBIRTH! glows while ready")
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
			local teleport = TeleportView.build(refs.TopBar, 1.25)
			T.eq(teleport.Buttons.Base.NextSelectionRight, teleport.Buttons.Lobby, "BASE -> LOBBY")
			T.eq(teleport.Buttons.Vault.NextSelectionLeft, teleport.Buttons.Lobby, "VAULT -> LOBBY")
			local outline = HudBubble.selectionImage()
			T.truthy(outline:FindFirstChildOfClass("UIStroke"), "gold selection outline")
		end)
	end)

	-- (review #16) the Shop pill never sits under the TRAIN chip (its own gui, under the
	-- Roblox top bar, drawn over the HUD) nor on the menu tiles, on PC screens and phones
	T.test("LightUI: the Shop pill clear of the TRAIN chip and the menu", function()
		local HudBubble = ui("HudBubble")
		local TrainView = ui("TrainView")
		withLight(function()
			for _, screen in
				{
					{ 1280, 720, 58 },
					{ 1920, 1080, 58 },
					{ 1920, 1010, 58 },
					{ 1440, 900, 58 },
					{ 667, 375, 58 },
					{ 568, 320, 58 },
				}
			do
				local viewport = Vector2.new(screen[1], screen[2])
				local scale = HudBubble.scaleFor(viewport)
				local refs = HudBubble.buildGame(scale, screen[1]) -- (the screen width in points)
				local height = screen[2] / scale
				local pill = refs.Gui:FindFirstChild("ShopPill") :: any
				-- the HUD and the TRAIN gui share one frame (CoreUISafeInsets: under Roblox's top bar)
				height -= screen[3] / scale
				local compact = refs.Gui:FindFirstChild("Menu"):GetAttribute("Columns") == 3
				local chipTop = refs.Gui:GetAttribute("ChipTop")
				T.truthy(type(chipTop) == "number", "the HUD says where the TRAIN chip goes")
				local chipBottom = chipTop + TrainView.chipSize(compact).Y
				if compact then
					-- phones and tablets: the pill at the top-right, clear of the tabs and the chips' row
					local width = screen[1] / scale
					local pillLeft = width - 18 - pill.Size.X.Offset
					local barRight = width / 2 + refs.TopBar.Size.X.Offset / 2
					T.truthy(pillLeft > barRight, `pill right of the tabs at {screen[1]} x {screen[2]}`)
					local luck = refs.Gui:FindFirstChild("ServerLuck") :: any
					T.truthy(
						width - 18 - luck.Size.X.Offset > barRight,
						`the Server Luck line right of the tabs at {screen[1]} x {screen[2]}`
					)
					-- the pill rides on the chips' row: the chips stop short of it (the next test lays them out)
					T.eq(pill.Position.Y.Offset, chipTop, `pill on the chips' row at {screen[1]} x {screen[2]}`)
					T.eq(
						HudBubble.chipsRight(refs.Gui, width),
						pillLeft - HudBubble.ChipGap,
						`the chips' limit at {screen[1]} x {screen[2]}`
					)
					T.truthy(pill.Size.Y.Offset * scale >= 44, `the Shop pill >= 44 pt tall at {screen[1]} x {screen[2]}`)
				else
					T.eq(HudBubble.chipsRight(refs.Gui, screen[1] / scale), nil, `PC: no chips' limit at {screen[1]} x {screen[2]}`)
					local pillTop = height * pill.Position.Y.Scale + pill.Position.Y.Offset - pill.Size.Y.Offset
					T.truthy(pillTop > chipBottom, `pill under the TRAIN chip at {screen[1]} x {screen[2]}`)
				end
				-- the money (bottom-left) under the TRAIN chip
				local moneyTop = height + refs.CoinsPanel.Position.Y.Offset - refs.CoinsPanel.Size.Y.Offset
				T.truthy(moneyTop > chipBottom, `the money under the TRAIN chip at {screen[1]} x {screen[2]}`)
				local menu = refs.Menu
				local menuBottom = height * menu.Position.Y.Scale + menu.Position.Y.Offset + menu.Size.Y.Offset
				T.truthy(chipTop > menuBottom, `the TRAIN chip under the menu tiles at {screen[1]} x {screen[2]}`)
				-- the tiles (top-left) clear of the BASE / LOBBY / VAULT tabs (top centre)
				local menuRight = menu.Position.X.Offset + menu.Size.X.Offset
				local tabsLeft = (screen[1] / scale) / 2 - refs.TopBar.Size.X.Offset / 2
				T.truthy(menuRight < tabsLeft, `the tiles left of the tabs at {screen[1]} x {screen[2]}`)
			end
		end)
	end)

	-- (review: the wider pixel chips once covered the phone Shop pill; taps there opened Boosts)
	T.test("LightUI: the phone boost chips keep off the Shop pill, even with hour-long timers", function()
		local HudBubble = ui("HudBubble")
		local TrainView = ui("TrainView")
		local BoostView = ui("BoostView")
		local NOW = 1.7e9
		local function overlap(aPos: any, aSize: any, bPos: any, bSize: any): boolean
			return aPos.X < bPos.X + bSize.X and bPos.X < aPos.X + aSize.X and aPos.Y < bPos.Y + bSize.Y and bPos.Y < aPos.Y + aSize.Y
		end
		local beforeTop, beforeRight = TrainView.HudChipTop, BoostView.HudChipsRight
		local ok, err = pcall(withLight, function()
			for _, size in { { 568, 320 }, { 667, 375 }, { 736, 414 }, { 844, 390 } } do
				local screen = Vector2.new(size[1], size[2])
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, size[1])
				local width, height = size[1] / scale, size[2] / scale
				local pill = refs.Gui:FindFirstChild("ShopPill") :: any
				local pillSize = Vector2.new(pill.Size.X.Offset, pill.Size.Y.Offset)
				local pillPos = Vector2.new(
					width * pill.Position.X.Scale + pill.Position.X.Offset - pill.AnchorPoint.X * pillSize.X,
					pill.Position.Y.Offset - pill.AnchorPoint.Y * pillSize.Y
				)
				-- the TRAIN chip and the boost chips where TrainController / BoostController put them
				TrainView.HudChipTop = refs.Gui:GetAttribute("ChipTop")
				local train = TrainView.build(true)
				TrainView.layout(train, true, width, height)
				local chips = BoostView.buildChips()
				BoostView.placeChips(chips, BoostView.chipsTop(train.ChipFrame, true), BoostView.chipsLeft(train.ChipFrame))
				BoostView.HudChipsRight = HudBubble.chipsRight(refs.Gui, width)
				T.truthy(BoostView.HudChipsRight, `the chips get a limit at {size[1]} x {size[2]}`)
				local gap = (chips.Row:FindFirstChildOfClass("UIListLayout") :: any).Padding.Offset
				-- typical timers, the 2 h stack cap, a day of late Robux time
				for _, left in { { 222, 3900 }, { 7199, 7199 }, { 86399, 86399 } } do
					local state = { Boosts = { TripleLuckyUntil = NOW + left[1], HexaLuckyUntil = NOW + left[2] } }
					BoostView.setChips(chips, BoostView.chips(state, NOW), false)
					local fit = chips.Row:GetAttribute("Fit")
					local at = `{size[1]} x {size[2]}, {left[1]} s / {left[2]} s, fit {fit}`
					local x, y = chips.Row.Position.X.Offset, chips.Row.Position.Y.Offset
					for _, kindId in BoostView.Tabs do
						local button = chips.Chips[kindId]
						T.truthy(button.Visible, `{kindId} chip shows at {at}`)
						local s = Vector2.new(button.Size.X.Offset, button.Size.Y.Offset)
						T.falsy(overlap(Vector2.new(x, y), s, pillPos, pillSize), `{kindId} chip on the Shop pill at {at}`)
						T.truthy(s.X * scale >= 44 and s.Y * scale >= 44, `{kindId} chip >= 44 pt at {at}`)
						x += s.X + gap
					end
					T.truthy(BoostView.rowRight(chips) <= pillPos.X - HudBubble.ChipGap, `the row stops short of the pill at {at}`)
					if size[1] >= 667 and left[1] == 222 then
						T.eq(fit, "Tags", `room for the tags at {at}`)
					elseif size[1] == 568 then
						T.truthy(fit ~= "Tags", `the small phone drops the tags at {at}`)
					end
				end
				T.truthy(pillSize.Y * scale >= 44 and pillSize.X * scale >= 44, `the Shop pill >= 44 pt at {size[1]} x {size[2]}`)
			end
		end)
		TrainView.HudChipTop, BoostView.HudChipsRight = beforeTop, beforeRight
		if not ok then
			error(err, 0)
		end
	end)

	-- (review: every carry change once destroyed and rebuilt the whole hotbar)
	T.test("LightUI: the hotbar's slots are updated in place", function()
		local red, blue = Color3.fromRGB(255, 60, 60), Color3.fromRGB(60, 120, 255)
		local function count(root: any): number
			return #root:GetDescendants()
		end
		for _, light in { true, false } do
			local before = UIConfig.LightUI
			UIConfig.LightUI = light
			local ok, err = pcall(function()
				local refs = HudView.build() :: any
				local row = refs.CarrySlots
				local function lookA()
					HudView.carrySlot(row, 1, red, false, 0)
					HudView.carrySlot(row, 2, nil, true, 0)
					HudView.carrySlot(row, 3, nil, false, 7)
				end
				local function lookB()
					HudView.carrySlot(row, 1, nil, true, 0)
					HudView.carrySlot(row, 2, blue, false, 0)
					HudView.carrySlot(row, 3, nil, false, 120)
				end
				lookA()
				local first = row:FindFirstChild("Slot1")
				lookB()
				local warm = count(row)
				lookA()
				lookB()
				T.eq(count(row), warm, `no new instances once every look was shown (light {light})`)
				T.eq(row:FindFirstChild("Slot1"), first, `the same slot frame (light {light})`)
				T.truthy((row:FindFirstChild("Slot1"):FindFirstChild("Mystery", true) :: any).Visible, `dirty ore shows ? (light {light})`)
				T.eq((row:FindFirstChild("Slot3"):FindFirstChild("More", true) :: any).Text, "+120", `+N updated (light {light})`)
				if light then
					local slot1 = row:FindFirstChild("Slot1") :: any
					T.falsy(slot1:FindFirstChild("Ore", true).Visible, "the gem hides under the rock")
					local slot2 = row:FindFirstChild("Slot2") :: any
					T.truthy(slot2:FindFirstChild("Ore", true).Visible, "the gem shows")
					T.falsy(slot2:FindFirstChild("Mystery", true).Visible, "no ? on a clean ore")
					T.truthy(slot2:FindFirstChild("Glow", true).BackgroundColor3 == blue, "recoloured glow")
				else
					T.truthy((row:FindFirstChild("Slot2") :: any).BackgroundColor3 == blue, "recoloured square")
				end
				lookA()
				T.falsy((row:FindFirstChild("Slot3"):FindFirstChild("More", true) :: any).Visible == false, "+N back")
				HudView.carrySlot(row, 3, nil, false, 0)
				T.falsy((row:FindFirstChild("Slot3"):FindFirstChild("More", true) :: any).Visible, "+N hides on an empty well")
				HudView.trimSlots(row, 2)
				T.eq(row:FindFirstChild("Slot3"), nil, "a smaller backpack drops the extra slot")
				T.truthy(row:FindFirstChild("Slot2"), "and keeps the rest")
			end)
			UIConfig.LightUI = before
			if not ok then
				error(err, 0)
			end
		end
	end)

	-- (review: the phone pill once sat on the touch tutorial bubble and the FREE SPIN chip)
	T.test("LightUI: the phone Shop pill and Server Luck line clear of the tutorial bubble and FREE SPIN", function()
		local HudBubble = ui("HudBubble")
		local TutorialView = ui("TutorialView")
		local WheelView = ui("WheelView")
		local function overlap(aPos: any, aSize: any, bPos: any, bSize: any): boolean
			return aPos.X < bPos.X + bSize.X and bPos.X < aPos.X + aSize.X and aPos.Y < bPos.Y + bSize.Y and bPos.Y < aPos.Y + aSize.Y
		end
		withLight(function()
			for _, size in { { 568, 320 }, { 667, 375 }, { 736, 414 }, { 844, 390 } } do
				local screen = Vector2.new(size[1], size[2])
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, size[1])
				local width = size[1] / scale
				local function rect(gui: any): (any, any)
					local s = gui.Size
					local x = width * gui.Position.X.Scale + gui.Position.X.Offset - gui.AnchorPoint.X * s.X.Offset
					local y = gui.Position.Y.Offset - gui.AnchorPoint.Y * s.Y.Offset
					return Vector2.new(x, y), Vector2.new(s.X.Offset, s.Y.Offset)
				end
				local pillPos, pillSize = rect(refs.Gui:FindFirstChild("ShopPill"))
				local luckPos, luckSize = rect(refs.Gui:FindFirstChild("ServerLuck"))
				local bubble = TutorialView.layout(scale, screen, true)
				local bubblePos = Vector2.new(bubble.Position.X - bubble.AnchorPoint.X * bubble.Width, bubble.Position.Y)
				local bubbleSize = Vector2.new(bubble.Width, bubble.Height)
				local spinPos, spinSize = WheelView.chipRect(scale, screen)
				for name, r in { pill = { pillPos, pillSize }, luck = { luckPos, luckSize } } do
					T.falsy(overlap(r[1], r[2], bubblePos, bubbleSize), `{name} on the tutorial bubble at {size[1]} x {size[2]}`)
					T.falsy(overlap(r[1], r[2], spinPos, spinSize), `{name} on the FREE SPIN chip at {size[1]} x {size[2]}`)
				end
			end
		end)
	end)

	T.test("LightUI: on a small phone the Shop pill, the tabs, the money and the hotbar don't meet", function()
		local HudBubble = ui("HudBubble")
		withLight(function()
			for _, screen in { Vector2.new(667, 375), Vector2.new(568, 320), Vector2.new(932, 430) } do
				local scale = HudBubble.scaleFor(screen)
				local refs = HudBubble.buildGame(scale, screen.X)
				local width = screen.X / scale
				local barLeft = width / 2 - refs.TopBar.Size.X.Offset / 2
				local pill = refs.Gui:FindFirstChild("ShopPill") :: any
				T.truthy(pill, "the green Shop pill")
				local pillRight = pill.Position.X.Offset + pill.Size.X.Offset
				T.truthy(pillRight < barLeft, `the Shop pill clear of the tabs at {screen.X} x {screen.Y}`)
				-- the money sits bottom-left, the hotbar bottom-centre
				local moneyRight = refs.CoinsPanel.Position.X.Offset + refs.CoinsPanel.Size.X.Offset
				local hotbarLeft = width / 2 - refs.CarryPanel.Size.X.Offset / 2
				T.truthy(moneyRight < hotbarLeft, `the money clear of the hotbar at {screen.X} x {screen.Y}`)
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
		-- (the pill is off: UIConfig.CustomPrompts; the stock Roblox prompt ships)
		local prompt = LightPrompt.build("Open Shop", "Tobin's Ore Stall", "E")
		T.eq(prompt.Action.Text, "OPEN SHOP", "action in capitals")
		T.eq(prompt.Key.Text, "E", "key letter")
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

	T.test("LightUI: the stock Roblox prompt ships and the label skin leaves its UI alone", function()
		local fs = require("@lune/fs")
		local Players = Loader.game:GetService("Players")
		T.eq(UIConfig.CustomPrompts, false, "the stock Roblox prompt, not our pill (owner 2026-10-20)")
		-- a client module: it reads Players.LocalPlayer when it loads
		local hadLocal = rawget(Players, "LocalPlayer")
		rawset(Players, "LocalPlayer", { UserId = 1 })
		local loaded, LightWorldController =
			pcall(Loader.requirePath, "StarterPlayer.StarterPlayerScripts.Client.Controllers.LightWorldController")
		rawset(Players, "LocalPlayer", hadLocal)
		T.truthy(loaded, "LightWorldController loads: " .. tostring(LightWorldController))
		T.falsy(LightWorldController.Skip.Prompt, "no generic 'Prompt' in Skip (ProximityPrompts use that name too)")
		-- Roblox's core script: a ScreenGui "ProximityPrompts" in the PlayerGui with a
		-- BillboardGui "Prompt" per shown prompt (a Frame, the key text, the action and
		-- object texts) and a BillboardGui "Indicator". Its frame starts clear (it fades
		-- in to 0.2), so the label skin would give every text a navy UIStroke.
		local function stockShaped(name: string, parent: any): any
			local gui = Instance.new("BillboardGui")
			gui.Name = name
			local frame = Instance.new("Frame")
			frame.BackgroundTransparency = 1
			frame.Parent = gui
			for _, text in { "ButtonText", "ActionText", "ObjectText" } do
				local label = Instance.new("TextLabel")
				label.Name = text
				label.BackgroundTransparency = 1
				label.TextSize = 19
				label.Text = text
				label.Parent = frame
			end
			gui.Parent = parent
			return gui
		end
		local function strokes(gui: any): number
			local count = 0
			for _, d in gui:GetDescendants() do
				if d:IsA("UIStroke") then
					count += 1
				end
			end
			return count
		end
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local folder = Instance.new("ScreenGui")
		folder.Name = LightWorldController.StockPromptFolder
		folder.Parent = playerGui
		T.eq(folder.Name, "ProximityPrompts", "the core script's ScreenGui")
		for _, name in { "Prompt", "Indicator" } do
			local gui = stockShaped(name, folder)
			LightWorldController.skinLabel(gui)
			T.eq(strokes(gui), 0, name .. ": no navy edges on Roblox's own prompt")
			T.eq(gui:GetAttribute("LightSkin"), nil, name .. ": not skinned")
		end
		-- our own world labels still get the skin, even one named "Prompt"
		local hud = Instance.new("ScreenGui")
		hud.Name = "Hud"
		hud.Parent = playerGui
		for _, name in { "Prompt", "PodiumTag" } do
			local gui = stockShaped(name, hud)
			LightWorldController.skinLabel(gui)
			T.truthy(strokes(gui) > 0, name .. " outside ProximityPrompts gets the light skin")
		end
		-- the pill (and its Custom style) only behind the switch
		local source = fs.readFile("src/client/Controllers/LightWorldController.luau")
		T.truthy(string.find(source, "if UIConfig.CustomPrompts then\n\t\tstartPrompts()", 1, true), "startPrompts behind CustomPrompts")
		local _, calls = string.gsub(source, "startPrompts%(%)", "")
		T.eq(calls, 2, "startPrompts: defined once, called once (behind the switch)")
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

	-- the HUD chips (TRAIN, the boost timers, FREE SPIN) in the pixel reels' look
	-- (owner 2026-10-22): never LightSkin's recolouring, the same parts, SEND still greys
	T.test("LightUI: the TRAIN and boost chips wear the pixel look with the switch on", function()
		local TrainView = ui("TrainView")
		local BoostView = ui("BoostView")
		local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		T.falsy(TrainView.build(false).Chip:GetAttribute("PopSkin"), "switch off: today's train chip")
		T.falsy(BoostView.buildChips().Gui:GetAttribute("PopSkin"), "switch off: today's boost chips")
		withLight(function()
			for _, compact in { false, true } do
				local train = TrainView.build(compact)
				T.truthy(train.Chip:GetAttribute("PopSkin"), "the pixel train chip")
				T.falsy(train.Chip:GetAttribute("LightSkin"), "no LightSkin on the train chip")
				T.truthy(train.ChipFrame:FindFirstChild("Paint") and train.ChipFrame:FindFirstChild("Lattice"), "a painted face")
				T.truthy(train.ChipFrame:FindFirstChild("IconSquare"), "the locomotive in a painted square")
				local send = train.ChipSend.Parent :: any
				T.truthy(send:GetAttribute("Pop"), "SEND is a painted button")
				TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 0, Capacity = 8 }), 0, nil))
				T.eq(train.ChipSend.BackgroundColor3, Theme.PanelLight, "empty: SEND greyed (the state colour)")
				T.eq(send:FindFirstChild("Paint").Color.Keypoints[1].Value, PopTheme.Gray.Top, "a grey face")
				TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 8, Capacity = 8 }), 0, nil))
				T.eq(send:FindFirstChild("Paint").Color.Keypoints[1].Value, PopTheme.Paints.Green.Top, "full: a green face")
				T.eq(train.ChipFrame.Size.Y.Offset, BoostView.TrainChipHeight[if compact then "Compact" else "Normal"], "the chip's height")
			end
			local chips = BoostView.buildChips()
			T.truthy(chips.Gui:GetAttribute("PopSkin"), "the pixel boost chips")
			T.falsy(chips.Gui:GetAttribute("LightSkin"), "no LightSkin on the boost chips")
			for _, button in { chips.Chips.TripleLucky, chips.Chips.HexaLucky, chips.Launcher } do
				local pill = button:FindFirstChild("Pill") :: any
				T.truthy(pill:FindFirstChild("Paint") and pill:FindFirstChild("Lattice"), button.Name .. ": a painted face")
				T.truthy(pill:FindFirstChild("Dot"):FindFirstChild("Paint"), button.Name .. ": the picture's painted square")
				T.eq(pill:FindFirstChild("Text").FontFace.Family, PopTheme.Pixel.Family, button.Name .. ": pixel words")
				T.eq(button.Size.Y.Offset, BoostView.ChipHit, button.Name .. ": the touch area")
			end
		end)
	end)

	-- the windows rebuilt in the Pop kit (owner 2026-10-21: "every window new,
	-- modern, colourful, Roblox style") never wear the LightSkin recolouring
	T.test("LightUI: the Pop windows (codex, settings, hall of fame, book, journal) skip the light skin", function()
		local function builds(): { [string]: any }
			return {
				Codex = ui("CodexView").build(false).Gui,
				Settings = ui("SettingsView").build(false).Gui,
				Boards = ui("LeaderboardView").buildPanel(false).Gui,
				Collection = ui("CollectionView").build(false).Gui,
				Banner = ui("CollectionView").buildBanner(false).Gui,
				Reveal = ui("CollectionView").buildReveal(false).Gui,
				Story = ui("StoryView").build(false).Gui,
			}
		end
		local function check(label: string)
			for name, gui in builds() do
				T.falsy(gui:GetAttribute("LightSkin"), `{label}: no LightSkin on {name}`)
				T.truthy(gui:GetAttribute("PopSkin"), `{label}: the Pop {name}`)
				gui:Destroy()
			end
		end
		check("switch off")
		withLight(function()
			check("switch on")
		end)
		-- the shared frame: a window still built from the old kit inside keeps the skin
		withLight(function()
			local gui = ui("MenuPanel").build("Test", "TEST", "sub", nil).Gui
			T.truthy(gui:GetAttribute("LightSkin"))
			T.falsy(gui:GetAttribute("PopSkin"))
		end)
	end)

	-- the Spin & Win screen wears the Pop look (owner 2026-10-20): never the LightSkin
	-- recolouring, switch on or off (the chip neither)
	T.test("LightUI: the Spin & Win wheel and its chip keep the Pop look", function()
		local WheelView = ui("WheelView")
		local function check(label: string)
			for _, compact in { false, true } do
				local gui = WheelView.build(compact).Gui
				T.falsy(gui:GetAttribute("LightSkin"), `{label}: no LightSkin on the wheel`)
				T.truthy(gui:GetAttribute("PopSkin"), `{label}: the Pop wheel`)
				gui:Destroy()
			end
			local chip = WheelView.buildChip(1)
			T.falsy(chip.Gui:GetAttribute("LightSkin"), `{label}: no LightSkin on the chip`)
			chip.Gui:Destroy()
		end
		check("switch off")
		withLight(function()
			check("switch on")
		end)
	end)

	-- MY GOLEMS, GOLEM CAPSULES and the capsule opening wear the Pop look
	-- (owner 2026-10-21): never the LightSkin recolouring, switch on or off
	T.test("LightUI: the golem and capsule windows keep the Pop look", function()
		local function check(label: string)
			for _, compact in { false, true } do
				local guis = {
					Golem = ui("GolemView").build(compact).Gui,
					Capsule = ui("CapsuleView").build(compact).Gui,
					Opening = ui("CapsuleView").buildOpening(compact).Gui,
				}
				for name, gui in guis do
					T.falsy(gui:GetAttribute("LightSkin"), `{label}: no LightSkin on {name}`)
					T.truthy(gui:GetAttribute("PopSkin"), `{label}: the Pop {name}`)
					gui:Destroy()
				end
			end
		end
		check("switch off")
		withLight(function()
			check("switch on")
		end)
	end)

	-- the luck boosts, the Enchant shop and the Gear shop are rebuilt in the Pop
	-- look (owner 2026-10-21): never LightSkin, switch on or off
	T.test("LightUI: the boosts, Enchant and Gear windows keep the Pop look", function()
		local function check(label: string)
			for _, compact in { false, true } do
				local guis = {
					Boost = ui("BoostView").build(compact).Gui,
					Enchant = ui("EnchantView").build(compact).Gui,
					Gear = ui("GearShopView").build(compact).Gui,
				}
				for name, gui in guis do
					T.falsy(gui:GetAttribute("LightSkin"), `{label}: no LightSkin on {name}`)
					T.truthy(gui:GetAttribute("PopSkin"), `{label}: the Pop {name}`)
					local panel = gui:FindFirstChild("Panel") :: any
					T.truthy(panel:FindFirstChild("PopBand") and panel:FindFirstChild("PopBody"), `{label}: {name}'s band and body`)
					gui:Destroy()
				end
			end
		end
		check("switch off")
		withLight(function()
			check("switch on")
		end)
	end)

	T.test("LightUI: game HUD touch sizes on phones", function()
		local layout = ui("HudBubble").layout(ui("HudBubble").scaleFor(Vector2.new(844, 390)))
		T.truthy(layout.Compact, "a phone gets the compact layout")
		T.truthy(layout.Tile * 0.62 >= 44 and layout.Slot * 0.62 >= 44 and layout.TabHeight * 0.62 >= 44, ">= 44 pt")
	end)

	T.test("LightUI: no emoji stand-ins (owner: text only), one elevator tile", function()
		local Bubble = ui("Bubble")
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		local HudBubble = ui("HudBubble")
		local SideMenuView = ui("SideMenuView")
		local holder = Instance.new("Frame")
		T.eq(IconAssets.fallback, nil, "no emoji table")
		for _, name in { "backpack", "golem_PebbleGolem", "machine_Crusher", "artifact_CrownCoin", "lift" } do
			local icon = Bubble.icon(holder, name, 60)
			T.eq(#icon:GetChildren(), 0, "nothing stands in for " .. name)
			T.eq(icon.Image, "", "empty until uploaded: " .. name)
			T.falsy(IconAssets.shows(name), "not shown yet: " .. name)
		end
		local sheet = IconAssets.Sheets[1]
		local before = sheet.Id
		sheet.Id = 123
		local ok, err = pcall(function()
			T.truthy(IconAssets.shows("backpack"), "shown once uploaded")
		end)
		sheet.Id = before
		if not ok then
			error(err, 0)
		end

		withLight(function()
			local refs = HudBubble.buildGame(1.25)
			TeleportView.build(refs.TopBar, 1.25)
			for _, entry in SideMenuView.sorted() do
				local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
				if entry.Group == "Main" then
					HudBubble.claimTile(refs.Menu, entry.Id, spec)
				end
			end
			local count = 0
			for _, child in refs.Menu:GetChildren() do
				if child.Name == "Elevator" then
					count += 1
				end
			end
			T.eq(count, 1, "one ELEVATOR tile (the side menu's Elevator entry)")
			local label = refs.Menu.Elevator:FindFirstChild("Label", true)
			T.eq(label and label.Text, "ELEVATOR", "named like the side menu entry")
		end)
	end)
end
