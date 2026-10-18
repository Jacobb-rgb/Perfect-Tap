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

	T.test("LightUI: game HUD touch sizes on phones", function()
		local layout = ui("HudBubble").layout(ui("HudBubble").scaleFor(Vector2.new(844, 390)))
		T.truthy(layout.Compact, "a phone gets the compact layout")
		T.truthy(layout.Tile * 0.62 >= 44 and layout.Slot * 0.62 >= 44 and layout.TabHeight * 0.62 >= 44, ">= 44 pt")
	end)
end
