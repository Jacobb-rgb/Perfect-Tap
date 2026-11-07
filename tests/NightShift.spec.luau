--[[
	Night Shift (owner 2026-11-07): the offline rates, the crate's rules and
	chances, the service, the window, the controller.
]]

return function(T, Loader)
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local NightShiftConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.NightShiftConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
	local NightShiftService = Loader.requirePath("ServerScriptService.Server.Services.NightShiftService")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local NightShiftView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftView")

	T.test("night shift: the pass says what it does, in the game's own numbers", function()
		local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
		local o = EconomyConfig.Offline
		local entry: any = nil
		for _, e in MonetizationConfig.List do
			if e.Key == "OfflineExtension" then
				entry = e
			end
		end
		T.truthy(entry, "the Night Shift pass")
		local text =
			`Your podiums keep earning at {math.floor(o.PassRate * 100)}% for up to {o.ExtendedHours} hours while you are away, instead of {math.floor(
				o.Rate * 100
			)}% for {o.BaseHours}.`
		T.eq(entry.Description, text)
	end)

	T.test("night shift: free 25 % for 8 h, the pass 50 % for 12 h", function()
		local o = EconomyConfig.Offline
		T.eq(o.Rate, 0.25)
		T.eq(o.BaseHours, 8)
		T.eq(o.PassRate, 0.5)
		T.eq(o.ExtendedHours, 12)
		T.eq(EconomyConfig.offlineEarnings(100, 3600, false), 100 * 0.25 * 3600, "an hour, free")
		T.eq(EconomyConfig.offlineEarnings(100, 3600, true), 100 * 0.5 * 3600, "an hour, the pass")
		T.eq(EconomyConfig.offlineEarnings(100, 20 * 3600, false), 100 * 0.25 * 8 * 3600, "capped at 8 h")
		T.eq(EconomyConfig.offlineEarnings(100, 20 * 3600, true), 100 * 0.5 * 12 * 3600, "capped at 12 h")
		T.eq(EconomyConfig.offlineEarnings(100, 59, true), 0, "too short")
	end)

	T.test("night shift: the crate's chances add up, are readable, and it comes once a night", function()
		local sum = 0
		for _, odds in NightShiftConfig.Odds do
			sum += odds.Chance
		end
		T.near(sum, 1, 1e-9, "the chances add up")
		T.eq(NightShiftConfig.pick(0), "Coins")
		T.eq(NightShiftConfig.pick(0.69), "Coins")
		T.eq(NightShiftConfig.pick(0.71), "Ores")
		T.eq(NightShiftConfig.pick(0.96), "Relic")
		T.eq(NightShiftConfig.pick(0.9999999), "Relic")
		T.eq(NightShiftConfig.oddsText(), "Coins 70% · Ores 25% · Relic 5%")
		local crate = NightShiftConfig.Crate
		T.eq(crate.Every, 72000, "20 hours")
		T.eq(crate.MinAway, 3600, "an hour away")
		T.eq(crate.CoinSeconds, 600, "10 minutes of income")
		T.eq(crate.CoinMin, 2500)
		T.truthy(NightShiftConfig.earnsCrate({ CrateAt = 2e9 + 500, Ready = false }, 7200, 2e9), "a clock that ran ahead never locks it")
		T.truthy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = false }, crate.MinAway, 2e9), "a long enough absence")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = false }, crate.MinAway - 1, 2e9), "too short")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 2e9 - 60, Ready = false }, 7200, 2e9), "one earned a minute ago")
		T.truthy(NightShiftConfig.earnsCrate({ CrateAt = 2e9 - crate.Every, Ready = false }, 7200, 2e9), "the next night")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = true }, 7200, 2e9), "one waits already")
		T.eq(NightShiftConfig.coins(0), crate.CoinMin, "no podiums: the minimum")
		T.eq(NightShiftConfig.coins(100), 100 * crate.CoinSeconds, "10 minutes of income")
		T.eq(NightShiftConfig.coins(0 / 0), crate.CoinMin, "broken income")
		T.eq(NightShiftConfig.floorFor(1, false).Index, 1)
		T.eq(NightShiftConfig.floorFor(4, false).Index, 2, "the deepest floor its blaster mines")
		local last = MineFloors.List[#MineFloors.List]
		T.eq(NightShiftConfig.floorFor(99, true).Index, last.Index)
		for level = 5, 9 do
			local floor = NightShiftConfig.floorFor(level, false)
			T.falsy(floor.ViaElevator, `blaster {level} without the Elevator stays on the floors it can walk to`)
			T.truthy(floor.MinBlaster <= level)
		end
		T.eq(NightShiftConfig.floorFor(9, false).Index, 3, "floor 3 is the deepest on foot")
		T.eq(NightShiftConfig.floorFor(9, true).MinBlaster, 9, "with the Elevator: the floor of a blaster 9")
		for _, r in { 0, 0.3, 0.7, 0.999999 } do
			T.truthy(last.Ores[NightShiftConfig.pickOre(last, r)], "an ore of the floor's table")
		end
	end)

	-- the service with its neighbours replaced
	local function world(): any
		local w: any = { changed = 0, stored = {}, coins = {}, found = {}, income = 100, room = true, relic = true }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		w.player = { Name = "Mia", UserId = 7, Parent = true }
		w.data = {
			Upgrades = {},
			Storage = {},
			NightShift = { CrateAt = 0, Ready = false },
			Stats = {},
			BlasterLevel = 1,
		}
		patch(DataService, "get", function()
			return w.data
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(EconomyService, "award", function(_, amount, source)
			table.insert(w.coins, { amount, source })
			return amount
		end)
		patch(PenService, "store", function(_, desc)
			if w.room then
				table.insert(w.stored, desc)
			end
			return w.room
		end)
		patch(PodiumService, "incomeOf", function()
			return w.income
		end)
		patch(ArtifactService, "find", function(_, zone, _, id)
			if w.relic then
				table.insert(w.found, { zone, id })
				return { Id = id }
			end
			return nil
		end)
		patch(NightShiftService, "clock", function()
			return 2e9
		end)
		patch(NightShiftService, "random", function()
			return w.roll or 0.5
		end)
		function w.done()
			for k = #saved, 1, -1 do
				rawset(saved[k][1], saved[k][2], saved[k][3])
			end
		end
		return w
	end

	T.test("night shift service: one crate, kept until opened, pays each prize, never twice", function()
		local w = world()
		local ok, err = pcall(function()
			local night = w.data.NightShift
			local before = w.changed
			local first = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(first.Crate, true, "earned")
			T.eq(w.changed, before + 1, "saved when earned")
			T.eq(night.Ready, true)
			T.eq(night.CrateAt, 2e9)
			local again = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(again.Crate, true, "not opened: it still waits")
			before = w.changed
			T.eq(NightShiftService.open(w.player).Ok, true, "opens")
			T.eq(w.changed, before + 1, "saved when opened")
			T.eq(NightShiftService.open(w.player).Ok, false, "never twice")
			local tonight = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(tonight.Crate, false, "nothing new tonight")
			-- each prize
			w.coins = {}
			night.Ready = true
			w.roll = 0.1
			local coins = NightShiftService.open(w.player)
			T.eq(coins.Prize, "Coins")
			T.eq(coins.Amount, 100 * NightShiftConfig.Crate.CoinSeconds)
			T.eq(w.coins[1][1], coins.Amount)
			night.Ready = true
			w.roll = 0.8
			local ores = NightShiftService.open(w.player)
			T.eq(ores.Prize, "Ores")
			T.eq(ores.Ores, 3)
			T.eq(#w.stored, 3)
			T.eq(w.stored[1].K, "Raw", "dirty")
			T.truthy(MineFloors.List[1].Ores[w.stored[1].O], "from the player's floor")
			T.eq(w.data.Stats.WheelOres, 3, "the tutorial doesn't count them as the train's")
			night.Ready = true
			w.room = false
			w.coins = {}
			local full = NightShiftService.open(w.player)
			T.eq(full.Ores, 0, "a full pen")
			T.truthy(full.Amount > 0, "pays what they are worth")
			T.eq(w.coins[1][1], full.Amount)
			night.Ready = true
			w.roll = 0.99
			local relic = NightShiftService.open(w.player)
			T.eq(relic.Prize, "Relic")
			T.eq(#w.found, 1)
			night.Ready = true
			w.relic = false
			T.eq(NightShiftService.open(w.player).Prize, "Coins", "no relic: the coins")
			-- the floor: no Elevator, no ore of the floors only it reaches
			w.data.BlasterLevel = 9
			w.stored = {}
			w.room = true
			w.roll = 0.8
			night.Ready = true
			NightShiftService.open(w.player)
			T.truthy(MineFloors.List[3].Ores[w.stored[1].O], "floor 3's ore, not floor 6's")
			w.stored = {}
			w.data.Upgrades.Elevator = true
			night.Ready = true
			NightShiftService.open(w.player)
			T.truthy(MineFloors.List[#MineFloors.List].Ores[w.stored[1].O], "with the Elevator: the deep floor's")
			-- a full pen says so before the crate opens
			w.data.Storage = {}
			T.eq(NightShiftService.onReturn(w.player, w.data, 7200, false).PenFull, false)
			for _ = 1, 40 do
				table.insert(w.data.Storage, { K = "Clean", O = "Gold", G = "Clean" })
			end
			T.eq(NightShiftService.onReturn(w.player, w.data, 7200, false).PenFull, true)
		end)
		w.done()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("night shift flow: a prize is never lost", function()
		local Flow = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftFlow")
		local s = Flow.new()
		T.truthy(Flow.mayPress(s))
		T.truthy(Flow.mayClose(s))
		local token = Flow.press(s)
		T.falsy(Flow.mayPress(s), "one press")
		T.falsy(Flow.mayClose(s), "the window stays while the answer is on its way")
		T.eq(Flow.answer(s, { Ok = true }), "Prize")
		T.falsy(Flow.timeout(s, token), "a timeout after the answer does nothing")
		T.truthy(Flow.mayClose(s))
		T.falsy(Flow.mayPress(s), "opened")
		T.eq(Flow.answer(s, { Ok = false }), "Ignore", "a refusal never overwrites the prize")
		-- a dropped request: the button comes back
		Flow.show(s)
		T.truthy(Flow.mayPress(s), "a new return")
		token = Flow.press(s)
		T.truthy(Flow.timeout(s, token))
		T.truthy(Flow.mayClose(s))
		T.truthy(Flow.mayPress(s))
		local second = Flow.press(s)
		T.falsy(Flow.timeout(s, token), "the old timeout doesn't undo the new press")
		T.eq(Flow.answer(s, { Ok = true }), "Prize", "the late answer")
		T.falsy(Flow.timeout(s, second))
		-- refused with nothing shown
		Flow.show(s)
		Flow.press(s)
		T.eq(Flow.answer(s, { Ok = false }), "Nothing")
	end)

	T.test("night shift controller: first OpenUI listener, a panel, its pops", function()
		local fs = require("@lune/fs")
		local function source(name: string): string
			return fs.readFile(Loader.root .. "/src/client/" .. name .. ".luau")
		end
		local init = source("init.client")
		local hud = init:find('"HudController"', 1, true) :: number
		local night = init:find('"NightShiftController"', 1, true) :: number
		T.truthy(hud < night, "after the HUD")
		for _, other in { "PenController", "SellController", "WheelController", "CapsuleController", "TrainController" } do
			local at = init:find(`"{other}"`, 1, true)
			T.truthy(at and night < at, `before {other}: it must stay the first OpenUI listener`)
		end
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		T.truthy(table.find(MenuPanels.Names, "NightShiftController"), "popups wait for it")
		local controller = source("Controllers/NightShiftController")
		T.truthy(controller:find("Motion.pop(refs.Panel, refs.Dim)", 1, true), "UI motion on")
		T.truthy(controller:find("Motion.classicPop(refs.Panel, nil, 0.6, 0.3)", 1, true), "UI motion off")
		T.truthy(controller:find("High.Value + 20", 1, true), "B before the others")
		T.truthy(Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.NightShiftController"), "it loads")
	end)

	T.test("night shift controller: the real glue, a fake Net: a prize is never lost, other panels stay", function()
		local task = require("@lune/task")
		local Enum = require("@lune/roblox").Enum
		local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
		local Loading = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.Loading")
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
		local Sfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Sfx")
		local Players = Loader.game:GetService("Players")
		local CAS = Loader.game:GetService("ContextActionService")
		local GS = Loader.game:GetService("GuiService")
		local UIS = Loader.game:GetService("UserInputService")
		local listeners, sent, prizes, bound = {}, {}, {}, {}
		local panelUp, eggUp, controlled, loadingDone = false, false, false, true
		local closedOthers, closedAll = 0, 0
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local function button(name: string): any
			local b: any = { Name = name, handlers = {}, Visible = true, Active = true }
			b.Activated = {
				Connect = function(_, fn)
					table.insert(b.handlers, fn)
				end,
			}
			b.press = function()
				for _, fn in b.handlers do
					fn()
				end
			end
			b.IsDescendantOf = function()
				return true
			end
			return b
		end
		local refs: any = {
			Gui = {
				Enabled = false,
				SetAttribute = function() end,
				FindFirstChild = function()
					return nil
				end,
			},
			Dim = {},
			Panel = {},
			CrateCard = {},
			Collect = button("Collect"),
			Close = button("CloseHit"),
			Open = button("Open"),
		}
		local builds = 0
		patch(NightShiftView, "build", function()
			builds += 1
			return refs
		end)
		patch(NightShiftView, "fill", function() end)
		patch(NightShiftView, "setOpening", function() end)
		patch(NightShiftView, "setPrize", function(_, result)
			table.insert(prizes, result)
		end)
		patch(Net, "listen", function(name, fn)
			listeners[name] = fn
		end)
		patch(Net, "send", function(name)
			table.insert(sent, name)
		end)
		patch(Loading, "isDone", function()
			return loadingDone
		end)
		patch(Loading, "wait", function()
			while not loadingDone do
				task.wait(0.005)
			end
		end)
		patch(Motion, "enabled", function()
			return false
		end)
		patch(Motion, "classicPop", function() end)
		patch(Motion, "pop", function() end)
		patch(Sfx, "play", function() end)
		patch(MenuPanels, "otherOpen", function()
			return panelUp
		end)
		patch(MenuPanels, "controller", function(name)
			if name == "CapsuleController" then
				return {
					showing = function()
						return eggUp
					end,
				}
			end
			return nil
		end)
		patch(MenuPanels, "closeOthers", function()
			closedOthers += 1
		end)
		patch(MenuPanels, "closeAll", function()
			closedAll += 1
		end)
		patch(Players, "LocalPlayer", {
			WaitForChild = function()
				return {}
			end,
		})
		patch(CAS, "BindActionAtPriority", function(_, name, fn, _, priority)
			bound[name] = { fn = fn, priority = priority }
		end)
		patch(CAS, "UnbindAction", function(_, name)
			bound[name] = nil
		end)
		patch(UIS, "GamepadEnabled", true)
		patch(GS, "SelectedObject", nil)
		local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.NightShiftController")
		local timeout, panelWait = Controller.ResultTimeout, Controller.PanelWait
		patch(Controller, "controlsHeld", function()
			return controlled
		end)
		local ok, err = pcall(function()
			Controller.ResultTimeout = 0.02
			Controller.PanelWait = 0.01
			Controller.init()
			local KEY = "TerraForgeNightShiftClose"
			local function back(): any
				return bound[KEY].fn("x", Enum.UserInputState.Begin)
			end
			-- an answer with no window yet, another kind of OpenUI
			listeners.NightCrateResult({ Ok = true, Prize = "Coins", Amount = 1 })
			listeners.OpenUI("Pen", {})
			T.falsy(Controller.isOpen(), "another kind opens nothing")
			T.eq(builds, 0)
			-- open, close with B
			listeners.OpenUI("Offline", { Crate = true })
			T.truthy(Controller.isOpen(), "opens")
			T.eq(builds, 1)
			T.eq(rawget(GS, "SelectedObject"), refs.Collect, "a gamepad starts on Collect")
			T.eq(bound[KEY].priority, Enum.ContextActionPriority.High.Value + 20, "B before the others")
			T.eq(back(), Enum.ContextActionResult.Sink)
			T.falsy(Controller.isOpen(), "B closes")
			T.eq(bound[KEY], nil, "and lets go of the key")
			-- opening: one request, no way out, the prize shows, a refusal after it changes nothing
			listeners.OpenUI("Offline", { Crate = true })
			T.eq(builds, 1, "built once")
			refs.Open.press()
			refs.Open.press()
			T.eq(#sent, 1, "one request")
			refs.Collect.press()
			refs.Close.press()
			back()
			T.truthy(Controller.isOpen(), "no way out while the answer is on its way")
			table.clear(prizes)
			listeners.NightCrateResult({ Ok = true, Prize = "Coins", Amount = 5 })
			T.eq(#prizes, 1, "the prize shows")
			listeners.NightCrateResult({ Ok = false })
			T.eq(#prizes, 1, "a refusal never overwrites it")
			refs.Open.press()
			T.eq(#sent, 1, "no second request after a prize")
			refs.Collect.press()
			T.falsy(Controller.isOpen(), "Collect closes")
			-- a dropped request: the way out comes back, a late prize opens the window again
			listeners.OpenUI("Offline", { Crate = true })
			refs.Open.press()
			task.wait(0.06)
			refs.Close.press()
			T.falsy(Controller.isOpen(), "X closes after the timeout")
			table.clear(prizes)
			listeners.NightCrateResult({ Ok = true, Prize = "Relic", Artifact = "x" })
			T.eq(#prizes, 1)
			T.truthy(Controller.isOpen(), "a late prize opens the window")
			T.truthy(bound[KEY], "with its key")
			refs.Collect.press()
			-- another panel took the screen while it waited: the prize still shows
			listeners.OpenUI("Offline", { Crate = true })
			refs.Open.press()
			Controller.close()
			T.falsy(Controller.isOpen())
			listeners.NightCrateResult({ Ok = true, Prize = "Coins", Amount = 1 })
			T.truthy(Controller.isOpen(), "shown after the panel closed it")
			refs.Collect.press()
			-- refused with nothing shown: the window can close
			listeners.OpenUI("Offline", { Crate = true })
			refs.Open.press()
			table.clear(prizes)
			listeners.NightCrateResult({ Ok = false })
			T.eq(#prizes, 1, "it says so")
			refs.Collect.press()
			T.falsy(Controller.isOpen())
			-- the streak popup is up: the window waits, the popup stays
			panelUp = true
			listeners.OpenUI("Offline", { Crate = false })
			T.falsy(Controller.isOpen(), "waits while another panel is up")
			task.wait(0.03)
			T.falsy(Controller.isOpen(), "still waits")
			panelUp = false
			task.wait(0.03)
			T.truthy(Controller.isOpen(), "opens when it is gone")
			refs.Collect.press()
			-- an egg opening, then build mode: it waits for both
			eggUp = true
			listeners.OpenUI("Offline", { Crate = false })
			task.wait(0.03)
			T.falsy(Controller.isOpen(), "not over an egg opening")
			eggUp = false
			controlled = true
			task.wait(0.03)
			T.falsy(Controller.isOpen(), "nor over build mode or a close-up")
			controlled = false
			task.wait(0.03)
			T.truthy(Controller.isOpen(), "a free screen")
			refs.Collect.press()
			-- the loading screen first
			loadingDone = false
			listeners.OpenUI("Offline", { Crate = false })
			task.wait(0.03)
			T.falsy(Controller.isOpen(), "never under the loading screen")
			loadingDone = true
			task.wait(0.03)
			T.truthy(Controller.isOpen(), "after it")
			refs.Collect.press()
			T.eq(closedOthers, 0, "it never closes another panel")
			T.eq(closedAll, 0)
		end)
		Controller.ResultTimeout, Controller.PanelWait = timeout, panelWait
		for k = #saved, 1, -1 do
			rawset(saved[k][1], saved[k][2], saved[k][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("night shift: an old or broken save gets a clean record", function()
		T.eq(DataTemplate.Version, Migrations.Latest)
		T.eq(DataTemplate.NightShift.CrateAt, 0)
		T.eq(DataTemplate.NightShift.Ready, false)
		for _, junk in { "junk", { CrateAt = 0 / 0, Ready = "yes" }, { CrateAt = -5 } } do
			local save: any = { Version = 13, NightShift = junk }
			Migrations.run(save)
			T.eq(save.Version, Migrations.Latest)
			T.eq(save.NightShift.CrateAt, 0, "a clean time")
			T.eq(save.NightShift.Ready, false, "no crate from a broken save")
		end
		local kept: any = { Version = 13, NightShift = { CrateAt = 2e9, Ready = true } }
		Migrations.run(kept)
		T.eq(kept.NightShift.CrateAt, 2e9, "a good record stays")
		T.eq(kept.NightShift.Ready, true)
	end)

	T.test("night shift window: its texts, it fits a small phone, Open Crate only with a crate", function()
		T.eq(NightShiftView.barText(0.25, 8), "Your podiums kept earning at 25% · max 8 h")
		T.eq(NightShiftView.barText(0.5, 12), "Your podiums kept earning at 50% · max 12 h")
		T.eq(NightShiftView.barFraction(4 * 3600, 8), 0.5)
		T.eq(NightShiftView.barFraction(20 * 3600, 8), 1, "capped")
		local big, small = NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 3 })
		T.eq(big, "3 dirty ores")
		T.eq(small, "In your pen")
		T.eq(NightShiftView.prizeText({ Ok = false }), "NIGHT CRATE")
		local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
		local artifactId, artifact = next(ArtifactConfig.ById)
		local relicBig, relicSmall = NightShiftView.prizeText({ Ok = true, Prize = "Relic", Artifact = artifactId })
		T.eq(relicBig, "A relic!")
		T.eq(relicSmall, artifact.Name, "its name")
		T.truthy(NightShiftView.Size.Y * 0.62 <= 320, "a 320 pt tall phone at the HUD's smallest scale")
		T.truthy(NightShiftView.ButtonHeight * 0.62 >= 44, "44 pt buttons on a phone")
		T.truthy(NightShiftView.CloseHit * 0.62 >= 44, "and the X")
		T.truthy(NightShiftView.OddsSize * 0.62 >= 10, "the chances readable on a phone")
		T.eq(NightShiftView.crateText(true, false), "Free once a day")
		T.eq(NightShiftView.crateText(true, true), "Pen full: ores pay coins")
		T.eq(NightShiftView.crateText(false, false), "Once a day, after 1 h away")
		T.eq((NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 1 })), "1 dirty ore")
		T.eq((NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 0, Amount = 9000 })), "+$9K", "a full pen")
		local refs = NightShiftView.build()
		T.falsy(refs.Gui.Enabled, "starts hidden")
		T.falsy(refs.Close.Selectable, "a gamepad closes with B")
		T.falsy((refs.Close.Parent :: any).Selectable, "the drawn X is no dead stop for a gamepad")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 8, Rate = 0.25, Crate = true })
		T.truthy(refs.Open.Visible, "a crate waits")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 8, Rate = 0.25, Crate = false })
		T.falsy(refs.Open.Visible, "no crate: no button")
		T.eq(refs.CrateOdds.Text, NightShiftConfig.oddsText(), "the chances are on the crate")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 12, Rate = 0.5, Crate = true })
		T.eq((refs.Bar:FindFirstChild("Label") :: any).Text, NightShiftView.barText(0.5, 12), "the pass's bar")
		NightShiftView.setPrize(refs, { Ok = true, Prize = "Coins", Amount = 2500 })
		T.falsy(refs.Open.Visible, "opened")
		T.truthy(refs.CrateTitle.Text:find("2.5K", 1, true) ~= nil, refs.CrateTitle.Text)
	end)
end
