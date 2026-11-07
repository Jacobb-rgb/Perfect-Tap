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
		T.eq(NightShiftConfig.oddsText(), "Coins 70% · 3 dirty ores 25% · A relic 5%")
		local crate = NightShiftConfig.Crate
		T.truthy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = false }, crate.MinAway, 2e9), "a long enough absence")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = false }, crate.MinAway - 1, 2e9), "too short")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 2e9 - 60, Ready = false }, 7200, 2e9), "one earned a minute ago")
		T.truthy(NightShiftConfig.earnsCrate({ CrateAt = 2e9 - crate.Every, Ready = false }, 7200, 2e9), "the next night")
		T.falsy(NightShiftConfig.earnsCrate({ CrateAt = 0, Ready = true }, 7200, 2e9), "one waits already")
		T.eq(NightShiftConfig.coins(0), crate.CoinMin, "no podiums: the minimum")
		T.eq(NightShiftConfig.coins(100), 100 * crate.CoinSeconds, "10 minutes of income")
		T.eq(NightShiftConfig.coins(0 / 0), crate.CoinMin, "broken income")
		T.eq(NightShiftConfig.floorFor(1).Index, 1)
		T.eq(NightShiftConfig.floorFor(4).Index, 2, "the deepest floor its blaster mines")
		local last = MineFloors.List[#MineFloors.List]
		T.eq(NightShiftConfig.floorFor(99).Index, last.Index)
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

	T.test("night shift line: kept and secret ore stay, the pen's room holds", function()
		local kept: { any } = { { K = "Clean", O = "Gold", G = "Clean" } }
		NightShiftLine.run(kept, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(kept[1].K, "Clean", "a rare ore the player keeps for a podium")
		local cleanedKept: { any } = { { K = "Raw", O = "Gold" } }
		NightShiftLine.run(cleanedKept, line("AutoCleaner", "Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll)
		T.eq(cleanedKept[1].K, "Clean", "cleaned, then kept")
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
		local broken: { any } = { "junk", { K = "Clean" }, { K = "Crushed", O = "Coal", G = "Rough", R = "x" } }
		T.eq(
			NightShiftLine.run(broken, line("Crusher", "ClayFurnace"), 3600, 40, "RarePlus", {}, noOdds, roll).Total,
			0,
			"a broken entry stays"
		)
		T.eq(broken[1], "junk")
		T.eq(broken[3].K, "Crushed")
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
		table.insert(w.data.PlacedMachines, { Id = "Conveyor", X = chute.X, Z = chute.Z, R = 0 })
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
			T.truthy(w.changed > 0, "saved")
			w.data.AutoSort = false
			T.eq(run(), nil, "switched off")
			w.data.AutoSort = nil
			w.data.Upgrades.PenAutomation = 0
			T.eq(run(), nil, "no billboard")
			w.data.Upgrades.PenAutomation = 1
			table.remove(w.data.PlacedMachines)
			T.eq(run(), nil, "no belt on the chute")
			T.eq(w.data.Storage[1].K, "Clean", "the ore stays")
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
			table.insert(w.data.PlacedMachines, { Id = "Conveyor", X = chute.X, Z = chute.Z, R = 0 })
			local perSecond = NightShiftLine.line(w.data).Crushed.PerSecond
			local function count(seconds: number, extended: boolean): number
				w.data.Storage = {}
				for _ = 1, 280 do
					table.insert(w.data.Storage, { K = "Crushed", O = "Coal", G = "Rough" })
				end
				w.data.NightShift = { CrateAt = 2e9, Ready = false }
				local result = NightShiftService.onReturn(w.player, w.data, seconds, extended)
				return if result then result.Made.Total else 0
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
			T.eq(NightShiftService.onReturn(w.player, w.data, 7200, false), nil, "nothing new tonight")
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
		end)
		w.done()
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
		local refs = NightShiftView.build()
		T.falsy(refs.Gui.Enabled, "starts hidden")
		NightShiftView.fill(refs, { Amount = 5000, Seconds = 3600, Hours = 8, Rate = 0.25, Crate = true })
		T.truthy(refs.Open.Visible, "a crate waits")
		T.truthy(refs.Empty.Visible, "nothing collected: the hint")
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
