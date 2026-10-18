-- The light UI switch (UIConfig.LightUI) under Lune: OFF by default and then
-- HudView builds today's HUD; ON, HudView forwards to the light HUD with the
-- same refs, TeleportView fills its top bar with bubble tabs + the LIFT tile
-- and BuildView claims the BUILD tile (no dead buttons).
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3
local Vector2 = roblox.Vector2

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
		UIConfig.LightUI = true
		local ok, err = pcall(fn)
		UIConfig.LightUI = false
		if not ok then
			error(err, 0)
		end
	end

	T.test("LightUI: off by default, today's HUD", function()
		T.falsy(UIConfig.LightUI, "the flag ships OFF")
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

	T.test("LightUI: game HUD touch sizes on phones", function()
		local layout = ui("HudBubble").layout(ui("HudBubble").scaleFor(Vector2.new(844, 390)))
		T.truthy(layout.Compact, "a phone gets the compact layout")
		T.truthy(layout.Tile * 0.62 >= 44 and layout.Slot * 0.62 >= 44 and layout.TabHeight * 0.62 >= 44, ">= 44 pt")
	end)
end
