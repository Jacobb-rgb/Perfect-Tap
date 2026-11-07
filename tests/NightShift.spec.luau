--[[
	Night Shift (owner 2026-11-07): the offline rates, the crate's rules and
	chances, the machines finishing the pen's ore (no ore from nothing, kept
	and secret ores untouched, the pen's room), the service, the window.
]]

return function(T, Loader)
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local NightShiftConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.NightShiftConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local NightShiftLine = Loader.requirePath("ReplicatedStorage.Shared.Machines.NightShiftLine")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
	local NightShiftService = Loader.requirePath("ServerScriptService.Server.Services.NightShiftService")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local NightShiftView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftView")

	local function machines(...: string): { any }
		local list = {}
		for k, id in { ... } do
			list[k] = { Id = id, X = k, Z = 1, R = 0 }
		end
		return list
	end

	local function line(...: string): any
		return NightShiftLine.line({ PlacedMachines = machines(...), Upgrades = {} })
	end

	local function roll(): number
		return 0.5
	end

	local function noOdds(): any
		return nil
	end

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

	T.test("night shift line: clean ore becomes two bars, nothing appears from nothing", function()
		local storage: { any } = { { K = "Clean", O = "Coal", G = "Clean" } }
		local report = NightShiftLine.run(storage, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(#storage, 2, "the Crusher makes two")
		T.eq(storage[1].K, "Ingot")
		T.eq(storage[2].K, "Ingot")
		T.eq(storage[1].O, "Coal")
		T.eq(storage[1].G, "Clean", "the grade stays")
		T.eq(report.Total, 2)
		T.eq(report.Bars, 2)
		T.eq(report.Made["Ingot|Coal|Clean"].N, 2)
		local empty: { any } = {}
		T.eq(NightShiftLine.run(empty, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll).Total, 0, "an empty pen")
		T.eq(#empty, 0)
	end)

	T.test("night shift line: walks as far as the base has machines, never past the work", function()
		local raw: { any } = { { K = "Raw", O = "Coal" } }
		NightShiftLine.run(raw, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(raw[1].K, "Raw", "no cleaner: dirty stays dirty")
		local cleaned: { any } = { { K = "Raw", O = "Coal" } }
		local report = NightShiftLine.run(cleaned, line("AutoCleaner"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(cleaned[1].K, "Clean", "only a cleaner: clean")
		T.eq(report.Total, 1)
		T.eq(report.Bars, 0)
		local none: { any } = { { K = "Clean", O = "Coal", G = "Rough" } }
		T.eq(NightShiftLine.run(none, line(), 3600, 40, "RarePlus", {}, noOdds, roll).Total, 0, "no machines")
		T.eq(none[1].K, "Clean")
		local many: { any } = {}
		for _ = 1, 10 do
			table.insert(many, { K = "Crushed", O = "Coal", G = "Rough" })
		end
		local stage = line("ClayFurnace").Crushed
		local work = 3 / stage.PerSecond + 0.01 -- three jobs
		T.eq(NightShiftLine.run(many, line("ClayFurnace"), work, 40, "RarePlus", {}, noOdds, roll).Total, 3, "the work's jobs only")
		T.eq(many[4].K, "Crushed", "the rest waits")
		T.eq(#many, 10, "nothing lost")
		local two = line("ClayFurnace", "ClayFurnace").Crushed.PerSecond
		T.near(two, 2 * stage.PerSecond, 1e-9, "two furnaces, twice the jobs")
	end)

	T.test("night shift line: a Polisher or Extractor is no stage, whatever stands first", function()
		for _, ids in { { "Polisher", "Crusher", "ClayFurnace" }, { "Crusher", "CrystalExtractor", "ClayFurnace" } } do
			local storage: { any } = {}
			for _ = 1, 4 do
				table.insert(storage, { K = "Clean", O = "Coal", G = "Clean" })
			end
			local report = NightShiftLine.run(storage, line(table.unpack(ids)), 3600, 40, "RarePlus", {}, noOdds, roll)
			T.eq(report.Bars, 8, table.concat(ids, " + ") .. ": every piece a bar")
		end
		local fast = line("ClayFurnace", "BlastFurnace").Crushed
		T.eq(fast.Machine, "BlastFurnace", "the fastest does the work")
	end)

	T.test("night shift line: rare dirty ore waits for the player's own cleaning", function()
		local storage: { any } = { { K = "Raw", O = "Diamond" }, { K = "Raw", O = "Coal" } }
		local report = NightShiftLine.run(storage, line("AutoCleaner"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(storage[1].K, "Raw", "a rare one stays dirty")
		T.eq(storage[2].K, "Clean", "a common one is cleaned")
		T.truthy(report.Cleaned.Coal, "what came out of the dirt")
		T.falsy(report.Cleaned.Diamond)
		local listed: { any } = { { K = "Raw", O = "Coal" } }
		NightShiftLine.run(listed, line("AutoCleaner"), 3600, 40, "List", { Coal = true }, noOdds, roll)
		T.eq(listed[1].K, "Raw", "the player's keep list counts")
	end)

	T.test("night shift line: kept and secret ore stay, the pen's room holds", function()
		local kept: { any } = { { K = "Clean", O = "Gold", G = "Clean" } }
		NightShiftLine.run(kept, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(kept[1].K, "Clean", "a rare ore the player keeps for a podium")
		local cleanedKept: { any } = { { K = "Raw", O = "Gold" } }
		NightShiftLine.run(cleanedKept, line("AutoCleaner", "Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(cleanedKept[1].K, "Raw", "a rare dirty one waits for the player")
		NightShiftConfig.CleansKept = true
		local ok, err = pcall(function()
			local cleaned: { any } = { { K = "Raw", O = "Gold" } }
			NightShiftLine.run(cleaned, line("AutoCleaner", "Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
			T.eq(cleaned[1].K, "Clean", "the other way (CleansKept): cleaned, then kept")
		end)
		NightShiftConfig.CleansKept = false
		if not ok then
			error(err, 0)
		end
		local secret: { any } = { { K = "Clean", O = "HollowEye", G = "Flawless" }, { K = "Raw", O = "RainbowNova" } }
		local report = NightShiftLine.run(secret, line("AutoCleaner", "Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(report.Total, 0, "a secret ore never")
		T.eq(secret[1].K, "Clean")
		T.eq(secret[2].K, "Raw")
		local full: { any } = { { K = "Clean", O = "Coal", G = "Rough" } }
		local tight = NightShiftLine.run(full, line("Crusher", "ClayFurnace"), 3600, 1, "RarePlus", {}, noOdds, roll)
		T.eq(tight.Total, 0, "no room for the second piece: it stays clean")
		T.eq(#full, 1)
		T.eq(full[1].K, "Clean")
		local two: { any } = { { K = "Clean", O = "Coal", G = "Rough" } }
		T.eq(NightShiftLine.run(two, line("Crusher", "ClayFurnace"), 3600, 2, "RarePlus", {}, noOdds, roll).Bars, 2, "room for exactly two")
		T.eq(#two, 2)
		local over: { any } = { { K = "Crushed", O = "Coal", G = "Rough" }, { K = "Crushed", O = "Coal", G = "Rough" } }
		T.eq(
			NightShiftLine.run(over, line("ClayFurnace"), 3600, 1, "RarePlus", {}, noOdds, roll).Bars,
			2,
			"one piece for one: an over-full pen still works"
		)
		local broken: { any } = { "junk", { K = "Clean" }, { K = "Crushed", O = "Coal", G = "Rough", R = "x" } }
		T.eq(
			NightShiftLine.run(broken, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll).Total,
			0,
			"a broken entry stays"
		)
		T.eq(broken[1], "junk")
		T.eq(broken[3].K, "Crushed")
	end)

	-- a belt's rotation that feeds away from the yard
	local FEEDS = if BaseLayout.sourceFeeds(0) then 0 else 1

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
			Upgrades = { PenAutomation = 1 },
			PlacedMachines = machines("Crusher", "ClayFurnace"),
			Storage = { { K = "Clean", O = "Coal", G = "Clean" } },
			KeepMode = "RarePlus",
			KeepList = {},
			NightShift = { CrateAt = 0, Ready = false },
			Stats = {},
			BlasterLevel = 1,
		}
		local chute = BaseLayout.Chutes.Pen
		table.insert(w.data.PlacedMachines, { Id = "Conveyor", X = chute.X, Z = chute.Z, R = FEEDS })
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

	T.test("night shift service: the line needs the billboard on and a belt on the PEN chute", function()
		local w = world()
		local ok, err = pcall(function()
			local function run(): any
				w.data.Storage = { { K = "Clean", O = "Coal", G = "Clean" } }
				w.data.NightShift = { CrateAt = 2e9, Ready = false } -- no crate here
				return NightShiftService.onReturn(w.player, w.data, 3600, false)
			end
			local full = run()
			T.eq(full.Made.Total, 2, "billboard + belt")
			T.eq(full.Made.Bars, 2)
			T.eq(#full.Made.List, 1)
			T.eq(full.Made.List[1].N, 2)
			T.eq(full.Crate, false)
			T.eq(full.Why, nil)
			T.truthy(w.changed > 0, "saved")
			w.data.AutoSort = false
			T.eq(run().Why, "BillboardOff")
			w.data.AutoSort = nil
			w.data.Upgrades.PenAutomation = 0
			T.eq(run().Why, "NoBillboard")
			w.data.Upgrades.PenAutomation = 1
			local belt = table.remove(w.data.PlacedMachines)
			T.eq(run().Why, "NoBelt")
			T.eq(w.data.Storage[1].K, "Clean", "the ore stays")
			belt.R = BaseLayout.SinkRotation
			table.insert(w.data.PlacedMachines, belt)
			T.eq(run().Why, "NoBelt", "a belt facing the yard doesn't feed")
			belt.R = FEEDS
			belt.L = 1
			T.eq(run().Why, "NoBelt", "nor one on a platform's deck")
			belt.L = nil
			local placed = w.data.PlacedMachines
			w.data.PlacedMachines = { belt }
			T.eq(run().Why, "NoMachines")
			w.data.PlacedMachines = placed
			w.data.NightShift = { CrateAt = 2e9, Ready = false }
			w.data.Storage = { { K = "Clean", O = "Gold", G = "Clean" } }
			T.eq(NightShiftService.onReturn(w.player, w.data, 3600, false).Why, "Nothing", "only kept ore")
		end)
		w.done()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("night shift service: the work follows the capped absence and the rate", function()
		local w = world()
		local ok, err = pcall(function()
			w.data.PlacedMachines = machines("ClayFurnace")
			local chute = BaseLayout.Chutes.Pen
			table.insert(w.data.PlacedMachines, { Id = "Conveyor", X = chute.X, Z = chute.Z, R = FEEDS })
			local perSecond = NightShiftLine.line(w.data).Crushed.PerSecond
			local function count(seconds: number, extended: boolean): number
				w.data.Storage = {}
				for _ = 1, 280 do
					table.insert(w.data.Storage, { K = "Crushed", O = "Coal", G = "Rough" })
				end
				w.data.NightShift = { CrateAt = 2e9, Ready = false }
				local result = NightShiftService.onReturn(w.player, w.data, seconds, extended)
				return if result.Made then result.Made.Total else 0
			end
			T.eq(count(100 / perSecond / 0.25, false), 100, "the free rate")
			T.eq(count(100 / perSecond / 0.5, true), 100, "the pass's rate")
			local cap = math.floor(perSecond * 0.25 * 8 * 3600)
			T.eq(count(100 * 3600, false), math.min(cap, 280), "never past the 8 h")
		end)
		w.done()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("night shift service: one crate, kept until opened, pays each prize, never twice", function()
		local w = world()
		local ok, err = pcall(function()
			local night = w.data.NightShift
			local first = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(first.Crate, true, "earned")
			T.eq(night.Ready, true)
			T.eq(night.CrateAt, 2e9)
			w.data.Storage = {}
			local again = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(again.Crate, true, "not opened: it still waits")
			T.eq(NightShiftService.open(w.player).Ok, true, "opens")
			T.eq(NightShiftService.open(w.player).Ok, false, "never twice")
			local tonight = NightShiftService.onReturn(w.player, w.data, 7200, false)
			T.eq(tonight.Crate, false, "nothing new tonight")
			T.eq(tonight.Made, nil)
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

	T.test("night shift service: ore out of the dirt is discovered, quietly", function()
		local w = world()
		local Discovery = Loader.requirePath("ServerScriptService.Server.Discovery")
		local saved = Discovery.mark
		local marks = {}
		Discovery.mark = function(_, _, oreId, quiet)
			table.insert(marks, { oreId, quiet })
			return true
		end
		local ok, err = pcall(function()
			table.insert(w.data.PlacedMachines, { Id = "AutoCleaner", X = 9, Z = 9, R = 0 })
			w.data.Storage = { { K = "Raw", O = "Coal" } }
			NightShiftService.onReturn(w.player, w.data, 3600, false)
			T.eq(#marks, 1)
			T.eq(marks[1][1], "Coal")
			T.eq(marks[1][2], true, "no toast: the window tells it")
		end)
		Discovery.mark = saved
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
		T.eq(NightShiftView.barText(0.25, 8), "Your base kept working at 25% · max 8 h")
		T.eq(NightShiftView.barText(0.5, 12), "Your base kept working at 50% · max 12 h")
		T.eq(NightShiftView.barFraction(4 * 3600, 8), 0.5)
		T.eq(NightShiftView.barFraction(20 * 3600, 8), 1, "capped")
		T.eq(NightShiftView.machinesText({ Total = 46, Bars = 46 }), "+46 bars")
		T.eq(NightShiftView.machinesText({ Total = 12, Bars = 3 }), "+12 items", "some aren't bars yet")
		T.eq(NightShiftView.machinesText(nil), "+0 bars")
		local big, small = NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 3 })
		T.eq(big, "3 dirty ores")
		T.eq(small, "In your pen")
		T.eq(NightShiftView.prizeText({ Ok = false }), "NIGHT CRATE")
		T.truthy(NightShiftView.Size.Y * 0.62 <= 320, "a 320 pt tall phone at the HUD's smallest scale")
		T.truthy(NightShiftView.ButtonHeight * 0.62 >= 44, "44 pt buttons on a phone")
		T.truthy(NightShiftView.CloseHit * 0.62 >= 44, "and the X")
		T.truthy(NightShiftView.OddsSize * 0.62 >= 10, "the chances readable on a phone")
		T.eq(NightShiftView.machinesText({ Total = 1, Bars = 1 }), "+1 bar")
		T.eq(NightShiftView.machinesText({ Total = 1, Bars = 0 }), "+1 item")
		for _, why in { "NoBillboard", "BillboardOff", "NoBelt", "NoMachines", "Nothing" } do
			T.truthy(NightShiftView.Why[why], why .. " has its own line")
		end
		T.truthy(NightShiftView.whyText("NoBelt"):find("PEN", 1, true) ~= nil, "it names the chute")
		T.eq(NightShiftView.crateText(true, false), "Free once a day")
		T.eq(NightShiftView.crateText(true, true), "Pen full: ores pay coins")
		T.eq(NightShiftView.crateText(false, false), "Once a day, after 1 h away")
		T.eq((NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 1 })), "1 dirty ore")
		T.eq((NightShiftView.prizeText({ Ok = true, Prize = "Ores", Ores = 0, Amount = 9000 })), "+$9K", "a full pen")
		local refs = NightShiftView.build()
		T.falsy(refs.Gui.Enabled, "starts hidden")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 8, Rate = 0.25, Crate = true })
		T.truthy(refs.Open.Visible, "a crate waits")
		T.truthy(refs.Empty.Visible, "nothing collected: the hint")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 8, Rate = 0.25, Crate = true, Why = "NoBelt" })
		T.eq(refs.Empty.Text, NightShiftView.Why.NoBelt, "the true reason")
		T.eq(refs.Machines.Text, "+0 bars")
		T.eq(refs.MachinesTitle.Text, "Machines 25%")
		NightShiftView.fill(refs, {
			Amount = 5000,
			Seconds = 3600,
			Hours = 8,
			Rate = 0.25,
			Crate = false,
			Made = { Total = 2, Bars = 2, List = { { K = "Ingot", O = "Gold", G = "Clean", N = 2 } } },
		})
		T.falsy(refs.Open.Visible, "no crate: no button")
		T.falsy(refs.Empty.Visible)
		T.eq(#refs.Rows:GetChildren(), 1, "one row")
		T.eq(refs.Machines.Text, "+2 bars")
		T.truthy(refs.CrateOdds.Text:find("70%", 1, true) ~= nil, "the chances are on the crate")
		NightShiftView.setPrize(refs, { Ok = true, Prize = "Coins", Amount = 2500 })
		T.falsy(refs.Open.Visible, "opened")
		T.truthy(refs.CrateTitle.Text:find("2.5K", 1, true) ~= nil, refs.CrateTitle.Text)
	end)
end
