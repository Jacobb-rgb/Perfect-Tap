-- The first-time tutorial: TutorialConfig's steps and checks (in order, out
-- of order, an old save, broken saved steps), its layout points,
-- TutorialService (signals, the reward once and only for finishing, Skip,
-- "Got it" on an info step, junk input, the funnel listener, a broken save
-- table) and TutorialView's layout (PC, phones, tablet, TV: on screen, clear
-- of the teleport bar and the right-side menu, touch buttons >= 44 pt).
-- Save data, players and Net are small fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local TutorialService = Loader.requirePath("ServerScriptService.Server.Services.TutorialService")
	local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")

	local tut = TutorialService._test
	local TOTAL = TutorialConfig.Total

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function fresh(): any
		local data = deepCopy(DataTemplate)
		for _, entry in MachineData.StarterKit do
			table.insert(data.PlacedMachines, { Id = entry.Id, X = entry.X, Z = entry.Z, R = 0 })
		end
		return data
	end

	-- each step's own progress, in order (what a player does for it)
	local DO = {
		Station = function(_data: any, signals: any)
			signals.NearStation = true
		end,
		Mine = function(data: any, signals: any)
			data.Stats.OresMined += 1
			signals.Carrying = 1
		end,
		Load = function(data: any, signals: any)
			signals.Carrying = 0
			table.insert(data.Train.Cargo, { O = "Copper" })
		end,
		Train = function(data: any, _signals: any)
			data.Train.Cargo = {}
			data.Stats.TrainTrips += 1
			table.insert(data.Storage, { O = "Copper" })
		end,
		Clean = function(data: any, _signals: any)
			data.Stats.OresCleaned += 1
		end,
		Podium = function(data: any, _signals: any)
			data.Podiums[1] = "Copper|Clean"
		end,
		Grow = function(data: any, _signals: any)
			data.Stats.ItemsSold += 1
		end,
		Blaster = function(data: any, _signals: any)
			data.BlasterLevel = 2
		end,
		Golems = function(data: any, _signals: any)
			data.Stats.CapsulesOpened += 1
		end,
		Wheel = function(data: any, _signals: any)
			data.Stats.WheelSpins += 1
		end,
		Platforms = function(data: any, _signals: any)
			table.insert(data.PlacedMachines, { Id = "Platform", X = 9, Z = 9, R = 0 })
		end,
	}

	---------------------------------------------------------------- config

	T.test("Tutorial: the steps are complete, short and point somewhere", function()
		T.eq(TOTAL, 11, "eight task steps, the two steps 6-7 hints and the platform hint")
		T.truthy(TutorialConfig.ById.Golems.Optional and TutorialConfig.ById.Wheel.Optional, "the hints are info steps (GOT IT)")
		T.eq(TutorialConfig.ById.Golems.UiTarget, "Golems", "the golem hint points at the side menu's GOLEMS")
		local seen = {}
		for index, step in TutorialConfig.Steps do
			T.falsy(seen[step.Id], "unique id " .. step.Id)
			seen[step.Id] = true
			T.eq(TutorialConfig.ById[step.Id], step, "ById " .. step.Id)
			T.truthy(DO[step.Id], "the test knows how to do " .. step.Id)
			T.truthy(#step.Title > 0 and #step.Title <= 22, step.Id .. ": a short title")
			T.truthy(#step.Text > 0 and #step.Text <= 90, step.Id .. ": simple, short text")
			T.eq(type(step.done), "function", step.Id .. ": has a check")
			if step.Hint then
				for _, input in { "Mouse", "Touch", "Gamepad" } do
					local hint = step.Hint[input]
					T.truthy(type(hint) == "string" and #hint > 0 and #hint <= 34, `{step.Id}: a short {input} hint`)
				end
			end
			if not step.Optional then
				T.truthy(step.Target, step.Id .. ": a task step points somewhere")
			end
			for _, target in { step.Target, step.EmptyTarget } do
				T.truthy(TutorialConfig.TargetNames[target], `{step.Id}: {target} has a name`)
			end
			T.eq(TutorialConfig.get(index), step, "get " .. index)
		end
		T.eq(TutorialConfig.get(TOTAL + 1), nil, "nothing past the end")
		for _, entry in MachineData.StarterKit do
			T.eq(TutorialConfig.StarterIds[entry.Id], 1, entry.Id .. " is a starter machine")
		end
		T.eq(TutorialConfig.StarterIds.CleaningStation, 1, "the old kit's station too")
		T.eq(TutorialConfig.counter(3), "3 / " .. TOTAL, "the counter")
		T.eq(TutorialConfig.counter(TOTAL + 1), TOTAL .. " / " .. TOTAL, "the counter stops at the end")
	end)

	T.test("Tutorial: a fresh save walks the steps one by one", function()
		local data, signals = fresh(), {}
		T.eq(TutorialConfig.advance(1, data, signals), 1, "a fresh save starts at step 1")
		for index, step in TutorialConfig.Steps do
			T.eq(TutorialConfig.advance(index, data, signals), index, step.Id .. " waits")
			DO[step.Id](data, signals)
			T.eq(TutorialConfig.advance(index, data, signals), index + 1, step.Id .. " done -> the next")
		end
		T.eq(TutorialConfig.advance(TOTAL + 1, data, signals), TOTAL + 1, "all done stays done")
	end)

	T.test("Tutorial: steps done out of order are not asked again", function()
		local data, signals = fresh(), {}
		DO.Grow(data, signals)
		DO.Blaster(data, signals)
		T.eq(TutorialConfig.advance(1, data, signals), 1, "selling first doesn't skip the mining steps")
		DO.Station(data, signals)
		DO.Mine(data, signals)
		DO.Load(data, signals)
		DO.Train(data, signals)
		DO.Clean(data, signals)
		T.eq(TutorialConfig.advance(1, data, signals), 6, "up to the podium")
		DO.Podium(data, signals)
		T.eq(TutorialConfig.advance(6, data, signals), 9, "Grow and Blaster were done before: on to the golem hint")
		DO.Golems(data, signals)
		T.eq(TutorialConfig.advance(9, data, signals), 10, "a golem woken: the hint passes by itself")
		DO.Wheel(data, signals)
		T.eq(TutorialConfig.advance(10, data, signals), 11, "a spin: the wheel hint too")
		DO.Platforms(data, signals)
		T.eq(TutorialConfig.advance(11, data, signals), TOTAL + 1, "a platform built: the platform hint too")
		-- carrying the ore home by hand (no train) passes Load and Train
		local walk, s2 = fresh(), {}
		DO.Station(walk, s2)
		DO.Mine(walk, s2)
		T.eq(TutorialConfig.advance(1, walk, s2), 3, "waiting at Load")
		table.insert(walk.Storage, { O = "Copper" })
		T.eq(TutorialConfig.advance(3, walk, s2), 5, "the pen took it: on to cleaning")
		-- an old save that has played a lot is done at once
		local old, s3 = fresh(), {}
		for _, step in TutorialConfig.Steps do
			if step.Id ~= "Station" and step.Id ~= "Mine" then
				DO[step.Id](old, s3)
			end
		end
		old.Stats.OresMined = 40
		T.eq(TutorialConfig.advance(1, old, {}), TOTAL + 1, "an old save is done without the signals")
	end)

	T.test("Tutorial: the daily wheel's ore prize skips no step", function()
		-- WheelService: a dirty ore straight into the pen, Stats.WheelOres + 1
		local function wheelOre(data: any)
			table.insert(data.Storage, { K = "Raw", O = "Bronze" })
			data.Stats.WheelOres += 1
		end
		local data, signals = fresh(), {}
		wheelOre(data)
		T.eq(TutorialConfig.advance(1, data, signals), 1, "a fresh save with a wheel ore stays on step 1")
		DO.Station(data, signals)
		T.eq(TutorialConfig.advance(1, data, signals), 2, "the mine step")
		DO.Mine(data, signals)
		T.eq(TutorialConfig.advance(2, data, signals), 3, "mining with the wheel ore in the pen: on to the hopper, not to cleaning")
		DO.Load(data, signals)
		T.eq(TutorialConfig.advance(3, data, signals), 4, "the train step")
		DO.Train(data, signals)
		T.eq(TutorialConfig.advance(4, data, signals), 5, "the train brought it home: clean")
		-- cleaning the wheel ore before mining teaches cleaning, not the mine
		local early = fresh()
		wheelOre(early)
		table.remove(early.Storage, 1)
		early.Stats.OresCleaned = 1
		T.eq(TutorialConfig.advance(1, early, {}), 1, "a cleaned wheel ore skips nothing")
		early.Stats.OresCleaned = 2
		T.eq(TutorialConfig.advance(1, early, {}), 6, "a second cleaned ore came out of a rock: an old hand")
		-- ore carried home by hand still counts, next to a wheel ore
		local walk, s2 = fresh(), {}
		wheelOre(walk)
		DO.Station(walk, s2)
		DO.Mine(walk, s2)
		T.eq(TutorialConfig.advance(1, walk, s2), 3, "waiting at Load")
		table.insert(walk.Storage, { K = "Raw", O = "Copper" })
		T.eq(TutorialConfig.advance(3, walk, s2), 5, "more in the pen than the wheel gave: on to cleaning")
	end)

	T.test("Tutorial: the checks read broken saves safely", function()
		T.eq(TutorialConfig.clamp(nil), 1, "nil")
		T.eq(TutorialConfig.clamp(0 / 0), 1, "NaN")
		T.eq(TutorialConfig.clamp(-3), 1, "negative")
		T.eq(TutorialConfig.clamp(2.7), 2, "fraction")
		T.eq(TutorialConfig.clamp(99), TOTAL + 1, "past the end")
		T.eq(TutorialConfig.clamp("4"), 1, "a string")
		local broken: any = { Stats = "x", Train = 5, Storage = "y", Podiums = { 1, true }, BlasterLevel = "9" }
		T.eq(TutorialConfig.advance(1, broken, nil), 1, "junk data passes nothing")
		broken.Stats = { OresMined = 0 / 0, OresCleaned = "3" }
		T.eq(TutorialConfig.advance(1, broken, {}), 1, "NaN and string stats count as 0")
		local data = fresh()
		T.falsy(TutorialConfig.machinesBought(data), "the starter kit is not a purchase")
		-- an old save: the kit's Cleaning Station still on the grid (review 2026-10-25)
		table.insert(data.PlacedMachines, { Id = "CleaningStation", X = 6, Z = 8, R = 0 })
		T.falsy(TutorialConfig.machinesBought(data), "the old kit's station is not a purchase")
		data.MachineInventory.Crusher = 1
		T.truthy(TutorialConfig.machinesBought(data), "a machine in the inventory")
		data.MachineInventory.Crusher = 0
		table.insert(data.PlacedMachines, { Id = "Crusher", X = 1, Z = 1, R = 0 })
		T.truthy(TutorialConfig.machinesBought(data), "a second Crusher is a purchase")
		local belt = fresh()
		table.insert(belt.PlacedMachines, { Id = "Conveyor", X = 1, Z = 1, R = 0 })
		T.truthy(TutorialConfig.machinesBought(belt), "a belt is a purchase")
		local podium = fresh()
		podium.Stats.PodiumEarned = 3
		T.truthy(TutorialConfig.podium(podium), "a podium that earned before counts (taken off since)")
		local bought = fresh()
		bought.Stats.BlastersBought = 1
		T.truthy(TutorialConfig.blaster(bought), "a blaster from the Vault counts")
	end)

	T.test("Tutorial: the guide's layout points are where the things are", function()
		local station = TutorialConfig.layoutPoint("Station", nil)
		T.truthy(station, "the station needs no plot")
		T.le((station - TrainConfig.Station.Platform.Center).Magnitude, 4, "the station point")
		T.le((TutorialConfig.layoutPoint("Hopper", nil) - TrainConfig.Station.Hopper).Magnitude, 4, "the hopper point")
		local rock = TutorialConfig.layoutPoint("Rock", nil)
		local q = WorldLayout.Quarry
		T.truthy(rock.X >= q.Min.X and rock.X <= q.Max.X and rock.Z >= q.Min.Z and rock.Z <= q.Max.Z, "the rock point is in the quarry")
		T.eq(TutorialConfig.layoutPoint("Pen", nil), nil, "no plot, no pen point")
		T.eq(TutorialConfig.layoutPoint("Sell", 1), nil, "the lobby stall has no layout point")
		-- the Blaster step points at the Vault (owner 2026-10-24: no Foundry), with or without a plot
		local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
		local vault = TutorialConfig.layoutPoint("Vault", nil)
		T.truthy(vault and (vault - LobbyLayout.get("BlasterVault").Center).Magnitude < 5, "the Vault's layout point")
		T.eq(TutorialConfig.Tags.Vault, "VaultCounter", "the guide looks for the Vault's counter")
		T.eq(TutorialConfig.Tags.Foundry, nil)
		for _, plot in WorldLayout.Plots do
			for _, target in { "Pen", "Podium", "Cleaning" } do
				local at = TutorialConfig.layoutPoint(target, plot.Id)
				T.truthy(at, `plot {plot.Id} {target}`)
				T.le((at - plot.Center).Magnitude, 70, `plot {plot.Id} {target} is on that plot`)
				for _, other in WorldLayout.Plots do
					if other.Id ~= plot.Id then
						T.truthy(
							(at - plot.Center).Magnitude < (at - other.Center).Magnitude,
							`plot {plot.Id} {target} is nearest its own plot`
						)
					end
				end
			end
		end
	end)

	---------------------------------------------------------------- the service

	local function fakePlayer(): any
		local p: any = { UserId = 812, Name = "Learner", Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		return p
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w: any = { pushes = {}, steps = {}, changed = 0 }
			w.player = fakePlayer()
			w.data = fresh()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(DataService, "changed", function()
				w.changed += 1
			end)
			patch(Net, "fire", function(event, p, payload)
				if event == "Tutorial" and p == w.player then
					table.insert(w.pushes, payload)
				end
			end)
			tut.reset()
			w.last = function(): any
				return w.pushes[#w.pushes]
			end
			w.step = function(): number
				return w.data.Tutorial.Step
			end
			w.standAt = function(position: any)
				w.player.root.Position = position
				w.player.root.CFrame = CFrame.new(position)
			end
			-- the server's view of one step's progress
			w.play = function(id: string)
				local signals = {}
				DO[id](w.data, signals)
				if signals.NearStation then
					w.standAt(TrainConfig.Station.Platform.Center + Vector3.new(4, 3, 4))
					T.truthy(TutorialService.nearStation(w.player), "standing at the station")
					tut.signals(w.player).NearStation = true
				end
				if signals.Carrying ~= nil then
					w.player.attrs.CarryCount = signals.Carrying
				end
				TutorialService.evaluate(w.player)
			end
			local ok, err = pcall(fn, w)
			tut.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	withWorld("TutorialService: a new player plays through and gets the reward once", function(w)
		local heard = {}
		-- (a listener stays registered for the rest of the run: it only records this player)
		TutorialService.onStep(function(p: any, info: any)
			if p == w.player then
				table.insert(heard, info)
			end
		end)
		tut.loaded(w.player, w.data)
		T.eq(#w.pushes, 1, "one push on load")
		T.eq(w.last().How, "Load", "the load push")
		T.eq(w.last().Step, 1, "step 1")
		T.eq(w.last().Total, TOTAL, "the total")
		T.falsy(w.last().Done, "not done")
		w.standAt(Vector3.new(0, 0, 26))
		T.falsy(TutorialService.nearStation(w.player), "the spawn is far from the station")
		TutorialService.evaluate(w.player)
		T.eq(w.step(), 1, "nothing happens without progress")
		T.eq(#w.pushes, 1, "no push without a change")
		for index, step in TutorialConfig.Steps do
			T.eq(w.step(), index, "on " .. step.Id)
			w.play(step.Id)
			if index < TOTAL then
				T.eq(w.step(), index + 1, step.Id .. " -> the next step")
				T.eq(w.last().How, "Step", step.Id .. " pushes a Step")
				T.eq(w.last().Step, index + 1, "the pushed step")
			end
		end
		T.truthy(w.data.Tutorial.Done, "done")
		T.eq(w.last().How, "Done", "the finish push")
		T.eq(w.last().Reward, TutorialConfig.Reward, "the reward in the push")
		T.eq(w.data.Coins, TutorialConfig.Reward, "the reward was paid")
		T.eq(#heard, TOTAL, "the funnel heard every step")
		T.eq(heard[#heard].How, "Done", "the last one is Done")
		T.falsy(heard[1].CatchUp, "live steps are not catch-up")
		-- nothing more after the end
		local pushes = #w.pushes
		TutorialService.evaluate(w.player)
		tut.action(w.player, "Skip")
		tut.action(w.player, "Ack")
		T.eq(#w.pushes, pushes, "a done tutorial stays quiet")
		T.eq(w.data.Coins, TutorialConfig.Reward, "paid once")
	end)

	withWorld("TutorialService: an old save catches up silently, without the reward", function(w)
		for _, step in TutorialConfig.Steps do
			if step.Id ~= "Station" and step.Id ~= "Mine" then
				DO[step.Id](w.data, {})
			end
		end
		w.data.Stats.OresMined = 12
		-- another service's load callback saves first (the starter kit): not live progress
		TutorialService.evaluate(w.player)
		T.falsy(w.data.Tutorial.Done, "nothing before the load check")
		T.eq(#w.pushes, 0, "no push before the load check")
		tut.loaded(w.player, w.data)
		T.truthy(w.data.Tutorial.Done, "done at once")
		T.eq(w.data.Coins, 0, "no reward for steps done before the tutorial existed")
		T.eq(#w.pushes, 1, "only the load push")
		T.eq(w.last().How, "Load", "pushed as the load state")
		T.truthy(w.last().Done, "the load push says done")
	end)

	withWorld("TutorialService: halfway saves resume where they were", function(w)
		w.data.Tutorial = { Step = 4, Done = false }
		w.play("Station")
		w.data.Stats.OresMined = 3
		table.insert(w.data.Train.TripCargo, { O = "Copper" })
		tut.loaded(w.player, w.data)
		T.eq(w.step(), 4, "the train is on its way: still step 4")
		w.data.Train.TripCargo = {}
		table.insert(w.data.Storage, { O = "Copper" })
		TutorialService.evaluate(w.player)
		T.eq(w.step(), 5, "it arrived")
		-- a broken saved table is repaired
		w.data.Tutorial = "broken"
		TutorialService.evaluate(w.player)
		T.eq(type(w.data.Tutorial), "table", "repaired")
		T.eq(w.step(), 5, "and caught up again")
		w.data.Tutorial = { Step = 0 / 0, Done = "yes" }
		TutorialService.evaluate(w.player)
		T.eq(w.data.Tutorial.Done, false, "Done must be true, not truthy")
		T.eq(w.step(), 5, "NaN step -> walked from 1 to 5")
		-- past the end but not marked done: a newer build's step (it has more), left as it is
		w.data.Tutorial = { Step = TOTAL + 4, Done = false }
		local coins = w.data.Coins
		TutorialService.evaluate(w.player)
		T.falsy(w.data.Tutorial.Done, "not finished here (docs/SAVE_AUDIT.md #1(b))")
		T.eq(w.data.Tutorial.Step, TOTAL + 4, "the newer build's step stays")
		T.eq(w.data.Coins, coins, "no reward")
		tut.loaded(w.player, w.data)
		T.eq(w.data.Tutorial.Step, TOTAL + 4, "a load keeps it too")
		T.eq(TutorialService.stepOf(w.player), TOTAL + 4, "(no step of this build: no bubble)")
		tut.action(w.player, "Ack")
		T.eq(w.data.Tutorial.Step, TOTAL + 4, "Ack changes nothing")
		w.data.Tutorial = { Step = 1e9, Done = false }
		TutorialService.evaluate(w.player)
		T.eq(w.data.Tutorial.Step, 99, "junk is capped")
	end)

	withWorld("TutorialService: Skip ends it without a reward, junk is ignored", function(w)
		tut.loaded(w.player, w.data)
		for _, junk in { 5, {}, "skip", "SkipSkipSkip", "Ack", "Done" } do
			tut.action(w.player, junk)
		end
		T.eq(#w.pushes, 1, "junk and Ack on a task step change nothing")
		T.falsy(w.data.Tutorial.Done, "still on")
		tut.action(w.player, "Skip")
		T.truthy(w.data.Tutorial.Done, "skipped")
		T.eq(w.last().How, "Skip", "the skip push")
		T.eq(w.last().Reward, nil, "no reward in the push")
		T.eq(w.data.Coins, 0, "no coins")
		local changed = w.changed
		for _, step in TutorialConfig.Steps do
			w.play(step.Id)
		end
		T.eq(w.data.Coins, 0, "doing the steps after a skip pays nothing")
		T.eq(w.changed, changed, "and saves nothing")
	end)

	withWorld("TutorialService: an info step waits for Got it", function(w)
		local used = false
		local hint = {
			Id = "TestHint",
			Title = "Golems",
			Text = "Golems help you mine.",
			Optional = true,
			done = function()
				return used -- the player hasn't used the feature yet
			end,
		}
		table.insert(TutorialConfig.Steps, 3, hint)
		TutorialConfig.Total += 1
		local ok, err = pcall(function()
			tut.loaded(w.player, w.data)
			w.play("Station")
			w.play("Mine")
			T.eq(w.step(), 3, "stops at the hint")
			DO.Load(w.data, {})
			TutorialService.evaluate(w.player)
			T.eq(w.step(), 3, "later progress doesn't pass the hint")
			tut.action(w.player, "Ack")
			T.eq(w.step(), 5, "Got it: past the hint and the Load step already done")
			tut.action(w.player, "Ack")
			T.eq(w.step(), 5, "Ack on a task step does nothing")
			-- a hint whose feature was already used passes by itself
			table.insert(TutorialConfig.Steps, 6, hint)
			TutorialConfig.Total += 1
			used = true
			DO.Train(w.data, {})
			DO.Clean(w.data, {})
			TutorialService.evaluate(w.player)
			T.eq(w.step(), 8, "past Train, the used hint and Clean: waiting at Podium")
		end)
		-- take every test hint out again (also after a failure)
		for i = #TutorialConfig.Steps, 1, -1 do
			if TutorialConfig.Steps[i] == hint then
				table.remove(TutorialConfig.Steps, i)
			end
		end
		TutorialConfig.Total = #TutorialConfig.Steps
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("TutorialService: the station signal needs the character there", function(w)
		tut.loaded(w.player, w.data)
		w.standAt(TrainConfig.Station.Platform.Center + Vector3.new(TutorialConfig.StationRadius + 5, 0, 0))
		T.falsy(TutorialService.nearStation(w.player), "just outside the radius")
		w.standAt(TrainConfig.Station.Platform.Center + Vector3.new(TutorialConfig.StationRadius - 5, 0, 0))
		T.truthy(TutorialService.nearStation(w.player), "inside the radius")
		w.player.humanoid.Health = 0
		T.falsy(TutorialService.nearStation(w.player), "a dead character is nowhere")
		w.player.humanoid.Health = 100
		w.player.attrs.CarryCount = 2
		TutorialService.evaluate(w.player)
		T.eq(w.step(), 1, "carrying doesn't pass the Station step")
		T.eq(TutorialService.stepOf(w.player), 1, "stepOf")
	end)

	---------------------------------------------------------------- the view

	local SCREENS = {
		{ Name = "PC 1280x720", Size = Vector2.new(1280, 720), Touch = false },
		{ Name = "PC 1920x1080", Size = Vector2.new(1920, 1080), Touch = false },
		{ Name = "TV 1920x1080", Size = Vector2.new(1920, 1080), Touch = false, TenFoot = true },
		{ Name = "phone 667x375", Size = Vector2.new(667, 375), Touch = true },
		{ Name = "phone 568x320", Size = Vector2.new(568, 320), Touch = true },
		{ Name = "phone 844x390", Size = Vector2.new(844, 390), Touch = true },
		{ Name = "tablet 1024x768", Size = Vector2.new(1024, 768), Touch = true },
	}

	-- HudController.uiScale for a screen
	local function uiScale(size: any): number
		return math.clamp(math.min(size.Y / 720, size.X / 1100), 0.62, 1.25)
	end

	T.test("TutorialView: the bubble fits every screen and keeps clear of the HUD", function()
		local refs = TutorialView.build()
		for _, screen in SCREENS do
			local scale = uiScale(screen.Size)
			local w, h = screen.Size.X / scale, screen.Size.Y / scale
			-- the right-side menu with BUILD and the elevator icon (2 buttons of 64, gap 10)
			local menuTop = h / 2 - (64 * 2 + 10) / 2
			local layout = TutorialView.layout(scale, screen.Size, screen.Touch, screen.TenFoot, menuTop)
			TutorialView.apply(refs, layout)
			local left = layout.Position.X - layout.AnchorPoint.X * layout.Width
			local top = layout.Position.Y - layout.AnchorPoint.Y * layout.Height
			local right, bottom = left + layout.Width, top + layout.Height
			T.truthy(left >= 0 and top >= 0 and right <= w and bottom <= h, `{screen.Name}: on screen`)
			T.le(layout.BodyHeight, TutorialView.BodyTouch, `{screen.Name}: text height`)
			T.truthy(layout.BodyHeight >= TutorialView.BodyMin, `{screen.Name}: room for two lines`)
			if screen.TenFoot then
				T.truthy(w - right >= w * 0.05 - 0.01 and h - bottom >= h * 0.05 - 0.01, `{screen.Name}: in the title-safe area`)
			end
			if screen.Touch then
				T.eq(layout.AnchorPoint, Vector2.new(1, 0), `{screen.Name}: top right on touch`)
				-- clear of the teleport bar
				local bar = TeleportView.layout(scale, screen.Size.X)
				local barRight = w / 2 + (TeleportView.barWidth(bar, 3) + 44 + bar.Gap) / 2
				T.truthy(left >= barRight, `{screen.Name}: right of the teleport bar ({left} >= {barRight})`)
				T.le(bottom, menuTop, `{screen.Name}: above the right-side menu`)
				-- the jump button and the thumbstick live in the bottom half
				T.le(bottom, h * 0.55, `{screen.Name}: out of the thumbs' way`)
				for _, target in TutorialView.touchTargets(refs, scale) do
					T.truthy(target.Width >= 44 and target.Height >= 44, `{screen.Name}: {target.Name} is >= 44 pt`)
				end
			else
				T.eq(layout.AnchorPoint, Vector2.new(1, 1), `{screen.Name}: bottom right`)
				T.truthy(top >= h / 2 + (64 * 4 + 30) / 2, `{screen.Name}: under a 4-button right-side menu`)
				T.truthy(left >= w / 2 + 130 + 8, `{screen.Name}: right of the carry slots`)
			end
			-- the buttons stay inside the bubble
			local skip = refs.Skip.Parent
			T.truthy(skip.Position.Y.Offset + skip.Size.Y.Offset <= layout.Height, `{screen.Name}: SKIP inside the bubble`)
			T.truthy(skip.Position.X.Offset + skip.Size.X.Offset <= layout.Width, `{screen.Name}: SKIP inside (x)`)
			T.truthy(refs.Ack.Parent.Position.X.Offset >= refs.Hint.Position.X.Offset, `{screen.Name}: GOT IT right of the hint's start`)
		end
		refs.Gui:Destroy()
	end)

	-- the FREE SPIN! chip's box (WheelView.chipRect) against the bubble's
	local function overlaps(aMin: any, aSize: any, bMin: any, bSize: any): boolean
		return aMin.X < bMin.X + bSize.X and bMin.X < aMin.X + aSize.X and aMin.Y < bMin.Y + bSize.Y and bMin.Y < aMin.Y + aSize.Y
	end

	T.test("TutorialView: the touch bubble and the FREE SPIN! chip never show in the same spot", function()
		local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
		for _, screen in SCREENS do
			local scale = uiScale(screen.Size)
			local h = screen.Size.Y / scale
			local menuTop = h / 2 - (64 * 2 + 10) / 2
			local layout = TutorialView.layout(scale, screen.Size, screen.Touch, screen.TenFoot, menuTop)
			local bubbleMin = Vector2.new(
				layout.Position.X - layout.AnchorPoint.X * layout.Width,
				layout.Position.Y - layout.AnchorPoint.Y * layout.Height
			)
			local bubbleSize = Vector2.new(layout.Width, layout.Height)
			local chipMin, chipSize = WheelView.chipRect(scale, screen.Size)
			local shared = overlaps(bubbleMin, bubbleSize, chipMin, chipSize)
			if screen.Touch then
				-- the top row right of the teleport bar: the chip's spot too (568x320, 667x375, 1024x768...)
				T.truthy(layout.Touch, `{screen.Name}: the bubble is in the top row`)
				T.falsy(
					WheelView.chipVisible(true, false, false, false, layout.Touch),
					`{screen.Name}: a ready chip waits while the bubble shows there`
				)
				T.truthy(WheelView.chipVisible(true, false, false, false, false), `{screen.Name}: and comes back after it`)
			else
				-- PC / TV: the bubble is in the bottom-right corner, the chip may show with it
				T.falsy(shared, `{screen.Name}: the bubble is clear of the chip`)
				T.falsy(layout.Touch)
			end
		end
		-- the controllers are wired up (the bubble's spot changes -> the chip steps aside at once)
		local fs = require("@lune/fs")
		local tutorial = fs.readFile("src/client/Controllers/TutorialController.luau")
		T.truthy(tutorial:find("function TutorialController.inTopRow(): boolean", 1, true), "inTopRow")
		T.truthy(tutorial:find("return visible and touchLayout", 1, true), "the bubble shows with the touch layout")
		T.truthy(tutorial:find("function TutorialController.onTopRowChanged(", 1, true), "onTopRowChanged")
	end)

	T.test("TutorialView: an open panel other than the steps' own hides the bubble (and frees R3)", function()
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		T.falsy(TutorialView.panelHides({}), "no panel open")
		for _, name in TutorialView.StepPanels do
			T.truthy(table.find(MenuPanels.Names, name), name .. " is a panel")
			T.falsy(TutorialView.panelHides({ name }), name .. ": a step sends you there, the bubble stays")
		end
		for _, name in
			{
				"CodexController",
				"GolemController",
				"ArtifactController",
				"BoostController",
				"SettingsController",
				"LeaderboardController",
				"WheelController",
				"CapsuleController",
				"EnchantController",
				"GearShopController",
			}
		do
			T.truthy(table.find(MenuPanels.Names, name), name .. " is a panel")
			T.truthy(TutorialView.panelHides({ name }), name .. " hides the bubble")
			T.truthy(TutorialView.panelHides({ "PenController", name }), name .. " hides it next to a step's panel too")
		end
		local fs = require("@lune/fs")
		local tutorial = fs.readFile("src/client/Controllers/TutorialController.luau")
		T.truthy(tutorial:find("TutorialView.panelHides(openPanels())", 1, true), "the controller blocks on open panels")
		T.truthy(tutorial:find("setBound(show)", 1, true), "R3 is bound only while the bubble shows")
	end)

	T.test("TutorialView: a step fills the bubble; SKIP asks once more", function()
		local refs = TutorialView.build()
		T.eq(refs.Gui.Name, "TerraForgeTutorial", "its own ScreenGui")
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "scaled with the HUD")
		T.eq(refs.Gui.DisplayOrder, 4, "under the HUD (5), over the crosshair (3)")
		local step = TutorialConfig.ById.Load
		TutorialView.setStep(refs, 3, step, step.Hint.Touch)
		T.eq(refs.Counter.Text, "3 / " .. TOTAL, "the counter")
		T.eq(refs.Title.Text, "LOAD THE TRAIN", "the title")
		T.eq(refs.Body.Text, step.Text, "the text")
		T.eq(refs.Hint.Text, step.Hint.Touch, "the hint")
		T.truthy(refs.Hint.Visible, "the hint shows on a task step")
		T.falsy(refs.Ack.Parent.Visible, "no GOT IT on a task step")
		TutorialView.setSkipAsk(refs, true)
		T.eq(refs.Skip.Text, "SURE?", "asks")
		TutorialView.setStep(refs, 4, {
			Id = "Hint",
			Title = "Golems",
			Text = "Golems help.",
			Optional = true,
			done = function()
				return true
			end,
		}, nil)
		T.eq(refs.Skip.Text, "SKIP", "a new step resets SKIP")
		T.truthy(refs.Ack.Parent.Visible, "GOT IT on an info step")
		T.falsy(refs.Hint.Visible, "no hint line there")
		TutorialView.setGlyph(refs, "rbxasset://r3.png", true)
		T.truthy(refs.PadGlyph.Visible, "the pad glyph shows")
		T.eq(refs.PadGlyph.Position.X.Offset, refs.Ack.Parent.Position.X.Offset, "on GOT IT")
		TutorialView.setGlyph(refs, "", false)
		T.falsy(refs.PadGlyph.Visible, "hidden without an image")
		T.eq(TutorialView.doneText(250), "Nice work, miner! +250 coins", "the finish line")
		T.eq(TutorialView.doneText(nil), "Nice work, miner!", "without a reward")
		refs.Gui:Destroy()
	end)

	T.test("TutorialView: the side-menu arrow sits right of the menu, level with its button", function()
		local refs = TutorialView.build()
		T.truthy(refs.Pointer, "the arrow exists")
		T.falsy(refs.Pointer.Visible, "hidden until a step names a side-menu button")
		-- a button at (12, 150) px, 84 x 64, the gui at (0, 36), scale 1.25; the column ends at 200 px
		local spot = TutorialView.pointerSpot(Vector2.new(12, 150), Vector2.new(84, 64), Vector2.new(0, 36), 1.25, 200)
		T.near(spot.X, 200 / 1.25 + TutorialView.PointerGap, 1e-3, "right of the whole column (a grid's other buttons stay clear)")
		T.near(spot.Y, (150 + 32 - 36) / 1.25, 1e-3, "level with the button's middle")
		local alone = TutorialView.pointerSpot(Vector2.new(12, 150), Vector2.new(84, 64), Vector2.new(0, 36), 1.25, nil)
		T.near(alone.X, 96 / 1.25 + TutorialView.PointerGap, 1e-3, "no column: right of the button")
		refs.Gui:Destroy()
	end)
end
