-- UI/Motion (the tween kit) and UIMotionController (the watcher) under Lune:
-- the easing curves match TweenService's, the count-up steps and the shine's
-- offset, press targets, Reduce motion jumping to the end without a single
-- tween, the watcher's window / dim finders and button kinds, attaching the
-- press feel twice adding one UIScale, the shop's breathe / shine marks, and
-- the Reduce motion setting.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local UDim2 = roblox.UDim2
	local Color3 = roblox.Color3

	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
	local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")
	local SettingsView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SettingsView")
	local Watcher = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.UIMotionController")

	local SCREEN = Vector2.new(1280, 720)
	local STYLES = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Bounce", "Elastic" }

	---------------------------------------------------------------- pure

	T.test("UIMotion: easing curves start at 0, end at 1 and match TweenService's shapes", function()
		for _, style in STYLES do
			for _, dir in { "In", "Out", "InOut" } do
				T.near(Motion.ease(style, dir, 0), 0, 1e-3, `{style} {dir} at 0`)
				T.near(Motion.ease(style, dir, 1), 1, 1e-3, `{style} {dir} at 1`)
			end
		end
		T.near(Motion.ease("Quad", "Out", 0.5), 0.75, 1e-9)
		T.near(Motion.ease("Quad", "In", 0.5), 0.25, 1e-9)
		T.near(Motion.ease("Sine", "InOut", 0.5), 0.5, 1e-9)
		T.near(Motion.ease("Linear", "Out", 0.3), 0.3, 1e-9)
		T.eq(Motion.ease("Quad", "Out", -1), 0, "clamped below")
		T.eq(Motion.ease("Quad", "Out", 2), 1, "clamped above")
		-- Back out overshoots (about 10 %) before it settles: the pop's bounce
		local peak = 0
		for i = 0, 100 do
			peak = math.max(peak, Motion.ease("Back", "Out", i / 100))
		end
		T.truthy(peak > 1.08 and peak < 1.12, `Back out peak {peak}`)
		-- every Out curve rises (Elastic and Bounce wobble, the rest never go back)
		for _, style in { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular" } do
			local last = -1
			for i = 0, 20 do
				local v = Motion.ease(style, "Out", i / 20)
				T.truthy(v >= last - 1e-9, `{style} rises`)
				last = v
			end
		end
	end)

	T.test("UIMotion: a window pops 0.85 -> 1 with a bounce over 1", function()
		T.near(Motion.popScale(0), Motion.Pop.From, 1e-9)
		T.near(Motion.popScale(Motion.Pop.Time), 1, 1e-9)
		T.truthy(Motion.popScale(Motion.Pop.Time * 0.6) > 1, "overshoots")
		T.near(Motion.popScale(0, 0.95), 0.95, 1e-9, "a window that isn't centred starts closer")
		T.eq(Motion.Pop.From, 0.85)
		T.truthy(Motion.Pop.Time >= 0.18 and Motion.Pop.Time <= 0.26, "about 0.22 s")
	end)

	T.test("UIMotion: the money count-up rolls up through formatted steps", function()
		local steps = Motion.countSteps(0, 1234567, Format.money, 10)
		T.eq(#steps, 11)
		T.eq(steps[1], Format.money(0))
		T.eq(steps[#steps], Format.money(1234567))
		local last = -1
		for i = 0, 10 do
			local v = Motion.countValue(0, 1234567, i / 10)
			T.truthy(v >= last, "never counts down")
			last = v
		end
		-- Quad out: most of the roll happens early
		T.truthy(Motion.countValue(0, 100, 0.5) >= 70, "fast first")
		-- a count from a balance (not zero)
		local from = Motion.countSteps(4.82e6, 4.95e6, Format.money, 4)
		T.eq(from[1], Format.money(4.82e6))
		T.eq(from[5], Format.money(4.95e6))
		-- bigger jumps roll a little longer, always 0.45 .. 0.9 s
		local small = Motion.countTime(100, 150)
		local big = Motion.countTime(0, 5e9)
		T.truthy(small >= Motion.Count.Min and big <= Motion.Count.Max)
		T.truthy(big >= small, "bigger takes longer")
		T.eq(Motion.countTime(5, 5), Motion.Count.Min)
		T.eq(Motion.countTime(0, 1e30), Motion.Count.Max)
	end)

	T.test("UIMotion: the shine crosses the button once a period, off it the rest", function()
		local s = Motion.Shine
		T.near(Motion.shineOffset(0), s.From, 1e-9)
		T.near(Motion.shineOffset(s.Sweep), s.To, 1e-6, "across after Sweep seconds")
		T.near(Motion.shineOffset(s.Period), s.From, 1e-6, "the loop starts again")
		T.near(Motion.shineOffset(s.Period - 1e-6), Motion.shineEnd(), 1e-3, "the loop's end")
		T.truthy(Motion.shineEnd() > 1.5, "most of the loop is off the button")
		T.near(Motion.shineOffset(0, s.Sweep), s.To, 1e-6, "a phase shifts it")
		local keys = Motion.shineKeys()
		T.eq(keys[1][1], 0)
		T.eq(keys[#keys][1], 1)
		for i = 2, #keys do
			T.truthy(keys[i][1] > keys[i - 1][1], "keypoint times rise")
		end
		T.eq(keys[1][2], 1, "clear at the edges")
		T.eq(keys[#keys][2], 1)
		T.truthy(keys[3][2] < 1, "a light band in the middle")
	end)

	T.test("UIMotion: breathing, press targets, centres and slides", function()
		local b = Motion.Breathe
		T.near(Motion.breatheScale(0), 1, 1e-9)
		T.near(Motion.breatheScale(b.Time), b.Peak, 1e-9)
		T.near(Motion.breatheScale(b.Time * 2), 1, 1e-9)
		T.eq(b.Peak, 1.03)
		local n = Motion.Profiles.Normal
		T.eq(Motion.pressTarget(1, true, false, n), 0.92)
		T.eq(Motion.pressTarget(1, false, true, n), 1.04)
		T.eq(Motion.pressTarget(1, true, true, n), 0.92, "pressed wins over hover")
		T.eq(Motion.pressTarget(1, false, false, n), 1)
		T.near(Motion.pressTarget(1.25, true, false, n), 1.15, 1e-9, "an existing UIScale's value is the base")
		T.truthy(Motion.Profiles.Big.Down > n.Down and Motion.Profiles.Big.Hover < n.Hover, "big cards move less")
		T.truthy(Motion.centred(Vector2.new(0.5, 0.5)))
		T.falsy(Motion.centred(Vector2.new(0, 0)))
		local base = Vector2.new(0, 0)
		local size = Vector2.new(84, 400)
		local right = Motion.slideAnchor(base, "Right", 42, size)
		T.near(right.X, -0.5, 1e-6, "from the right: the anchor moves left (the thing right)")
		T.near(Motion.slideAnchor(base, "Left", 42, size).X, 0.5, 1e-6)
		T.near(Motion.slideAnchor(base, "Up", 40, size).Y, 0.1, 1e-6)
		T.near(Motion.slideAnchor(base, "Down", 40, size).Y, -0.1, 1e-6)
	end)

	---------------------------------------------------------------- reduce motion

	-- a ScreenGui in a PlayerGui (Motion.shown: what Roblox draws)
	local function screen(): (any, any, any)
		local playerGui = Instance.new("PlayerGui")
		local gui = UIKit.screen("TerraForgeTest", 1)
		gui.Parent = playerGui
		local window = UIKit.new("Frame", {
			Name = "Panel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(600, 400),
		}, gui)
		return playerGui, gui, window
	end

	T.test("UIMotion: Reduce motion jumps every animation to its end (no tween at all)", function()
		-- (TweenService isn't there in Lune: a tween would fail this test)
		Motion.setReduced(true)
		local ok, err = pcall(function()
			T.truthy(Motion.reduced())
			local _, gui, window = screen()
			T.truthy(Motion.shown(window), "it shows")
			local dim = UIKit.new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.5 }, gui)
			Motion.pop(window, dim)
			T.eq((Motion.scaleOf(window) :: any).Scale, 1, "popped: already whole")
			T.eq(dim.BackgroundTransparency, 0.5, "the dim as it is")
			local closed = false
			Motion.close(window, function()
				closed = true
			end)
			T.truthy(closed, "closed at once")
			local label = UIKit.new("TextLabel", { Name = "Amount", Text = "$0" }, gui)
			Motion.countUp(label, 0, 5000, Format.money)
			T.eq(label.Text, Format.money(5000), "the new amount at once")
			T.falsy(Motion.isCounting(label))
			T.falsy(Motion.flyTo(nil, window, "cash"), "no cash flies")
			local card = UIKit.new("Frame", { Name = "Card", Size = UDim2.fromOffset(200, 200) }, gui)
			local scale = Motion.popIn(card)
			T.eq(scale.Scale, 1, "a reward card just shows")
			local ribbon = UIKit.new("Frame", { Name = "Ribbon", Size = UDim2.fromOffset(136, 30) }, gui)
			Motion.breathe(ribbon)
			local kind, running = Motion.loopOf(ribbon)
			T.eq(kind, "Breathe")
			T.falsy(running, "no loop runs")
			local price = Pop.price(gui, 99, Vector2.new(220, 56))
			Motion.shine(price)
			local _, shining = Motion.loopOf(price)
			T.falsy(shining)
			T.truthy(price:FindFirstChild("MotionShine"), "the streak is there (still)")
			local tabs = UIKit.new("Frame", { Name = "Tabs", Size = UDim2.fromOffset(84, 400) }, gui)
			Motion.slide(tabs, "Right")
			T.eq(tabs.AnchorPoint, Vector2.new(0, 0), "no slide")
			local button = Pop.button(gui, "OK", "Green", Vector2.new(160, 56))
			Motion.press(button)
			Motion.pressDown(button, nil)
			T.eq((Motion.scaleOf(button) :: any).Scale, 1, "no squash")
			Motion.pressUp(button)
			-- (out of the PlayerGui: nothing shows, so turning motion back on starts nothing)
			gui.Parent = nil
			T.falsy(Motion.shown(window))
		end)
		Motion.setReduced(false)
		Motion.refreshLoops()
		if not ok then
			error(err, 0)
		end
		T.falsy(Motion.reduced())
		Motion.setSystemReduced(true)
		T.truthy(Motion.reduced(), "Roblox's own setting counts too")
		Motion.setSystemReduced(false)
	end)

	T.test("UIMotion: a hidden gui gets no animation, only its end", function()
		local _, gui, window = screen()
		gui.Enabled = false
		T.falsy(Motion.shown(window))
		local label = UIKit.new("TextLabel", { Name = "Amount", Text = "$0" }, gui)
		Motion.countUp(label, 0, 250, Format.money)
		T.eq(label.Text, Format.money(250))
		T.falsy(Motion.flyTo(nil, window))
		T.eq(Motion.popIn(window).Scale, 1)
		gui.Enabled = true
		window.Visible = false
		T.falsy(Motion.shown(window), "a hidden frame")
	end)

	---------------------------------------------------------------- press attach

	T.test("UIMotion: attaching the press feel twice adds one UIScale", function()
		local holder = Instance.new("Frame")
		local button = Pop.button(holder, "BUY", "Green", Vector2.new(180, 60))
		Motion.press(button)
		Motion.press(button)
		Motion.hover(button)
		Watcher.attach(button)
		local count = 0
		for _, child in button:GetChildren() do
			if child:IsA("UIScale") then
				count += 1
				T.eq(child.Name, "MotionScale")
			end
		end
		T.eq(count, 1, "one UIScale")
		T.eq((Motion.stateOf(button) :: any).Profile, Motion.Profiles.Normal)
		-- a button with its own UIScale: that one is used, none is added
		local own = Pop.button(holder, "GO", "Green", Vector2.new(180, 60))
		local existing = Instance.new("UIScale")
		existing.Name = "Bounce"
		existing.Scale = 1.1
		existing.Parent = own
		Watcher.attach(own)
		Watcher.attach(own)
		T.eq(Motion.scaleOf(own), existing, "the existing UIScale")
		T.falsy(own:FindFirstChild("MotionScale"), "nothing stacked")
		-- a big card: the gentle profile
		local card = Pop.card(holder, "Green", { Size = UDim2.fromOffset(300, 400) })
		Watcher.attach(card)
		T.eq((Motion.stateOf(card) :: any).Profile, Motion.Profiles.Big)
	end)

	T.test("UIMotion: the watcher knows the Pop buttons and the old kit's chunky buttons", function()
		local holder = Instance.new("Frame")
		T.eq(Watcher.pressKind(Pop.button(holder, "OK", "Green", Vector2.new(160, 56))), "Pop", "Pop.button")
		T.eq(Watcher.pressKind(Pop.price(holder, 99, Vector2.new(200, 56))), "Pop", "Pop.price")
		T.eq(Watcher.pressKind(Pop.close(holder, 50)), "Pop", "Pop.close")
		T.eq(Watcher.pressKind(Pop.pill(holder, "Shop", "cart", "Green", Vector2.new(176, 56))), "Pop", "Pop.pill")
		local face = Pop.tile(holder, { Name = "Tab", Label = "MONEY", Icon = "coins", Paint = "Green", Size = 84 })
		T.eq(Watcher.pressKind(face), "Pop", "Pop.tile")
		local kit = UIKit.button(holder, "SELL", Color3.new(0, 1, 0), Color3.new(0, 0.5, 0))
		T.eq(Watcher.pressKind(kit), "Kit", "UIKit.button")
		T.eq(Watcher.pressKind(UIKit.new("TextButton", { Name = "Track" }, holder)), nil, "a plain button")
		T.eq(Watcher.pressKind(UIKit.new("Frame", { Name = "Button" }, holder)), nil, "not a button")
		local out = Pop.button(holder, "NO", "Gray", Vector2.new(160, 56))
		out:SetAttribute("Motion", "None")
		T.eq(Watcher.pressKind(out), nil, "opted out")
	end)

	T.test("UIMotion: a holder-filling button is held by its middle in the same place", function()
		local holder = Instance.new("Frame")
		local kit = UIKit.button(holder, "SELL", Color3.new(0, 1, 0), Color3.new(0, 0.5, 0))
		local w, h = 160, 52
		local function rect(b: any): (number, number)
			local x = b.Position.X.Scale * w + b.Position.X.Offset - b.AnchorPoint.X * (b.Size.X.Scale * w + b.Size.X.Offset)
			local y = b.Position.Y.Scale * h + b.Position.Y.Offset - b.AnchorPoint.Y * (b.Size.Y.Scale * h + b.Size.Y.Offset)
			return x, y
		end
		local x0, y0 = rect(kit)
		T.truthy(Watcher.centre(kit))
		T.eq(kit.AnchorPoint, Vector2.new(0.5, 0.5))
		local x1, y1 = rect(kit)
		T.near(x1, x0, 1e-9, "same left")
		T.near(y1, y0, 1e-9, "same top (the lip still shows)")
		T.falsy(Watcher.centre(kit), "once")
		-- a button a layout places itself (a price on a card) stays as it is
		local price = Pop.price(holder, 99, Vector2.new(200, 56), { AnchorPoint = Vector2.new(0.5, 1) })
		T.falsy(Watcher.centre(price))
		T.eq(price.AnchorPoint, Vector2.new(0.5, 1))
	end)

	---------------------------------------------------------------- window finder

	T.test("UIMotion: the watcher finds the main window and the dim backdrop", function()
		-- the store: a dim, a full-screen Fit holder, the Group inside it
		local store = StoreView.build()
		local window = Watcher.findWindow(store.Gui, SCREEN)
		T.eq(window, store.Group, "the store's Group (window and tabs)")
		T.eq(Watcher.findDim(store.Gui, SCREEN), store.Gui:FindFirstChild("Dim"))
		T.falsy(Watcher.selfAnimated(store.Gui, store.Group))
		-- a menu panel
		local settings = SettingsView.build(false)
		T.eq(Watcher.findWindow(settings.Gui, SCREEN), settings.Frame.Panel, "the panel")
		T.eq(Watcher.findDim(settings.Gui, SCREEN), nil, "no dim")
		-- named first, then the biggest; small frames are no window
		local gui = UIKit.screen("TerraForgeTest", 1)
		UIKit.new("Frame", { Name = "Big", Size = UDim2.fromOffset(900, 600) }, gui)
		local panel = UIKit.new("Frame", { Name = "Panel", Size = UDim2.fromOffset(500, 400) }, gui)
		T.eq(Watcher.findWindow(gui, SCREEN), panel, "the named one")
		panel.Visible = false
		T.eq((Watcher.findWindow(gui, SCREEN) :: any).Name, "Big", "a hidden frame isn't it")
		local chips = UIKit.screen("TerraForgeChips", 1)
		UIKit.new("Frame", { Name = "Chip", Size = UDim2.fromOffset(160, 40) }, chips)
		UIKit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, chips)
		T.eq(Watcher.findWindow(chips, SCREEN), nil, "chips and an empty full-screen frame: no window")
		-- a window that animates itself is left alone
		local pop = Instance.new("UIScale")
		pop.Name = "OpenPop"
		pop.Parent = settings.Frame.Panel
		T.truthy(Watcher.selfAnimated(settings.Gui, settings.Frame.Panel))
		local ours = Instance.new("UIScale")
		ours.Name = "MotionPop"
		ours.Parent = panel
		T.falsy(Watcher.selfAnimated(gui, panel), "its own MotionPop doesn't count")
		T.truthy(Watcher.Skip.TerraForgeHud, "the HUD never pops")
	end)

	---------------------------------------------------------------- the shop's marks

	T.test("UIMotion: the shop's prices shine, BEST VALUE and the x50 breathe from their middle", function()
		local refs = StoreView.build()
		local ribbons = 0
		for _, card in refs.Cards do
			T.eq(card.Price:GetAttribute("Motion"), "Shine", card.Spec.Id .. " price shines")
			local ribbon = card.Button:FindFirstChild("Ribbon")
			if ribbon then
				ribbons += 1
				T.eq(ribbon:GetAttribute("Motion"), "Breathe")
				T.eq(ribbon.AnchorPoint, Vector2.new(0.5, 0.5))
				-- the same corner as Pop.ribbon puts it: right edge 8 in, top 12 down
				T.near(ribbon.Position.X.Offset + ribbon.Size.X.Offset / 2, -8, 1e-9)
				T.near(ribbon.Position.Y.Offset - ribbon.Size.Y.Offset / 2, 12, 1e-9)
			end
		end
		T.truthy(ribbons >= 1, "a BEST VALUE ribbon")
		T.eq(refs.DetailBuy:GetAttribute("Motion"), "Shine")
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		if edition then
			local banner = StoreView.setEdition(refs, edition) :: any
			local first = StoreView.BannerCounts[1]
			for count, button in banner.Buys do
				T.eq(button:GetAttribute("Motion"), if count == first then "Breathe" else "Shine", `x{count}`)
				T.eq(button.AnchorPoint, Vector2.new(0.5, 0.5))
				-- its bottom edge stays 30 over the banner's bottom
				T.near(button.Position.Y.Offset + button.Size.Y.Offset / 2, StoreView.BannerHeight - 30, 1e-9)
			end
		end
	end)

	---------------------------------------------------------------- the setting

	T.test("UIMotion: Reduce motion is a saved setting, off by default, with a row", function()
		T.eq(SettingsConfig.Defaults.ReduceMotion, false)
		T.eq(DataTemplate.Settings.ReduceMotion, false)
		T.eq(SettingsConfig.sanitize(nil).ReduceMotion, false)
		T.eq(SettingsConfig.sanitize({ ReduceMotion = true }).ReduceMotion, true)
		T.eq(SettingsConfig.sanitize({ ReduceMotion = "yes" }).ReduceMotion, false, "junk: the default")
		T.falsy(SettingsConfig.equal(SettingsConfig.sanitize({ ReduceMotion = true }), SettingsConfig.sanitize(nil)), "a change is sent")
		T.eq(SettingsConfig.merge({ Music = 0.2 }, { ReduceMotion = true }).Music, 0.2, "the other settings stay")
		T.truthy(table.find(SettingsConfig.Toggles, "ReduceMotion"))
		local refs = SettingsView.build(false)
		T.truthy(refs.Toggles.ReduceMotion, "the SETTINGS panel row")
		SettingsView.set(refs, SettingsConfig.sanitize(nil))
		T.eq(refs.Toggles.ReduceMotion.Button.Text, "OFF")
	end)
end
