--[[
	Rebirth "STAR FORGE" (RebirthConfig, RebirthService) under Lune.
	The rules pin relationships, not numbers (the machines chat recalibrates
	the blaster prices): the stars follow the Foundry coin curve, the Star
	Shop is a goal of many rebirths whose cheapest perk the first rebirth
	pays for, Head Start never skips the run, no perk outgrows its stat cap.
	The reset resets exactly the header's list and keeps everything else.
	The service: refusals, the whole rebirth in one step (items out of the
	world, the train and podiums start over), a re-entrant rebirth is Busy,
	the Star Shop, junk input, the ForgeStars attribute. Save data, players
	and Net are small fakes.
]]
return function(T, Loader)
	local task = require("@lune/task")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local TrainService = Loader.requirePath("ServerScriptService.Server.Services.TrainService")
	local RebirthService = Loader.requirePath("ServerScriptService.Server.Services.RebirthService")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")

	local MIN, TOP = RebirthConfig.MinBlaster, BlasterData.MaxLevel

	local function deepEqual(a: any, b: any): boolean
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	-- A save in the middle of a run: blaster 8, coins, upgrades, ore everywhere, a factory.
	local function midRun(): { [string]: any }
		local data = ProfileStore.deepCopy(DataTemplate)
		Migrations.run(data)
		data.Coins = 4.2e9
		data.Shards = 37
		data.ShardRolls = 5
		data.TotalEarned = 9e9
		data.BlasterLevel = 8
		data.BlasterOre = "Obsidian"
		data.Upgrades = { Bellows = 3, ExtraSlots = 2, PenLevel = 4, PenAutomation = 2, Elevator = true }
		data.MachineUpgrades = { Crusher = { Speed = 3, Quality = 2 } }
		data.MachineInventory = { Conveyor = 12 }
		data.PlacedMachines = {
			{ Id = "Crusher", X = 1, Z = 1, R = 0, In = { { K = "Raw", O = "Gold" } }, Out = { { K = "Crushed", O = "Gold" } } },
			{ Id = "Sorter", X = 4, Z = 1, R = 1, C = 3 },
		}
		data.StarterKitGiven = true
		data.Storage = { { K = "Clean", O = "Gold", G = "Pristine" }, { K = "Raw", O = "Coal" } }
		data.Podiums = { "Clean|Gold|Pristine|", "", "Clean|Copper|Rough|", "" }
		data.Foundry.Stock = { { K = "Ingot", O = "Gold", G = "Clean" } }
		data.Train =
			{ CapacityLevel = 3, SpeedLevel = 4, Cargo = { { K = "Raw", O = "Coal" } }, TripCargo = {}, TripDepartAt = 0, TripArriveAt = 0 }
		data.Gear = { Boots = 3, HelmetLamp = 2, Backpack = 4, Gloves = 1, Magnet = 2 }
		data.Enchants = { Owned = { Lucky = 2 }, Slots = { "Lucky", "", "", "" } }
		data.Golems = { Owned = { { Id = 1, Kind = "PebbleGolem" } }, Equipped = { 1 }, NextId = 2 }
		data.Artifacts = { Found = { CrownCoin = 2 }, Chapters = {} }
		data.Discovered = { Gold = true, Coal = true }
		data.Hoverboards = { Owned = { Comet = true }, Equipped = "Comet", Passes = {} }
		data.KeepMode = "List"
		data.KeepList = { Gold = true }
		data.Stats.OresMined = 500
		return data
	end

	---------------------------------------------------------------- the rules

	T.test("Rebirth: the stars follow the blaster prices (relationships, not numbers)", function()
		for level = 1, MIN - 1 do
			T.eq(RebirthConfig.starsFor(level), 0, "no stars below MinBlaster (" .. level .. ")")
		end
		T.eq(RebirthConfig.starsFor(MIN), RebirthConfig.MinStars, "MinStars at MinBlaster")
		T.eq(RebirthConfig.starsFor(TOP), RebirthConfig.MaxStars, "MaxStars at the top")
		T.eq(RebirthConfig.starsFor(TOP + 3), RebirthConfig.MaxStars, "a newer build's level reads as the top")
		T.eq(RebirthConfig.starsFor(0 / 0), 0, "junk")
		for level = MIN + 1, TOP do
			T.truthy(RebirthConfig.starsFor(level) >= RebirthConfig.starsFor(level - 1), "never fewer stars at level " .. level)
		end
		T.truthy(RebirthConfig.MinBlaster < TOP, "a rebirth comes before the top level")
		-- derived from the prices: scaling every price keeps the curve
		local real = RebirthConfig.starsCurve()
		local function priceOf(level: number): number
			return BlasterData.ByLevel[level].Recipe.Coins
		end
		local scaled = RebirthConfig.starsCurve(function(level)
			return priceOf(level) * 10
		end)
		T.truthy(deepEqual(real, scaled), "x10 every price: the same stars")
		-- a level that costs relatively more of the run never pays fewer stars
		for level = MIN + 1, TOP - 1 do
			local dearer = RebirthConfig.starsCurve(function(lv)
				return if lv == level then priceOf(lv) * 8 else priceOf(lv)
			end)
			T.truthy(dearer[level] >= real[level], "a dearer level " .. level .. " pays at least as many stars")
		end
		-- a flat curve (every level the same price) still runs MinStars .. MaxStars
		local flat = RebirthConfig.starsCurve(function()
			return 1000
		end)
		T.eq(flat[MIN], RebirthConfig.MinStars)
		T.eq(flat[TOP], RebirthConfig.MaxStars)
	end)

	T.test("Rebirth: the Star Shop is a goal of many rebirths, its first perk within one", function()
		local typical = RebirthConfig.starsFor(math.min(MIN + 2, TOP))
		local rebirths = RebirthConfig.shopTotal() / typical
		T.truthy(rebirths >= 8 and rebirths <= 25, `the whole shop takes 8-25 typical rebirths (now {rebirths})`)
		local cheapest = math.huge
		for _, perk in RebirthConfig.Perks do
			cheapest = math.min(cheapest, perk.Costs[1])
			T.truthy(#perk.Costs >= 1, perk.Id .. " has levels")
			for i = 2, #perk.Costs do
				T.truthy(perk.Costs[i] >= perk.Costs[i - 1], perk.Id .. " never gets cheaper")
			end
			if perk.Stats then
				for stat, value in perk.Stats do
					local def = StatConfig.ById[stat]
					T.truthy(def, perk.Id .. ": " .. stat .. " is a StatConfig stat")
					T.truthy(value * #perk.Costs <= (def.Max :: number) + 1e-9, perk.Id .. " stays within the " .. stat .. " cap")
				end
			end
		end
		T.truthy(cheapest <= RebirthConfig.MinStars, "the first rebirth can buy something")
		-- Head Start never skips the run: you still forge your way to MinBlaster
		for _, level in RebirthConfig.HeadStartLevels do
			T.truthy(level < MIN, "Head Start LV " .. level .. " is below MinBlaster")
		end
		T.eq(#RebirthConfig.HeadStartLevels, #RebirthConfig.ById.HeadStart.Costs, "one start level per Head Start level")
	end)

	T.test("Rebirth: quote, buy and the readers of the Star Shop", function()
		local data = { Stars = 3, StarPerks = {} }
		T.eq(select(2, RebirthConfig.quote(data, "Nope")), "BadPerk")
		T.eq(select(2, RebirthConfig.quote(data, 5)), "BadPerk")
		T.eq(select(2, RebirthConfig.quote(data, "PodiumKeeper")), "NoStars", "6 stars needed")
		T.eq(RebirthConfig.quote(data, "GoldenTouch"), 1)
		T.eq(RebirthConfig.buy(data, "GoldenTouch"), 1)
		T.eq(data.Stars, 2)
		T.eq(RebirthConfig.buy(data, "GoldenTouch"), 2)
		T.eq(data.Stars, 1)
		T.eq(data.StarPerks.GoldenTouch, 2)
		local stats = RebirthConfig.stats(data.StarPerks)
		T.near(stats.IncomePct, 0.2, 1e-9, "+20% income")
		T.near(stats.SellPct, 0.2, 1e-9, "+20% sell value")
		-- a newer build's level and perk stay in the save, read as this build's top / ignored
		data.StarPerks = { DeepPockets = 9, StarMagnet = 4 }
		T.eq(RebirthConfig.levelOf(data.StarPerks, "DeepPockets"), 3, "read as the top")
		T.eq(RebirthConfig.stats(data.StarPerks).CarryCapacity, 3)
		T.eq(select(2, RebirthConfig.quote({ Stars = 99, StarPerks = data.StarPerks }, "DeepPockets")), "Max")
		T.eq(RebirthConfig.stats(data.StarPerks).StarMagnet, nil, "an unknown perk gives nothing here")
		-- Express Rails reaches the train through TrainConfig, half at most
		local base = TrainConfig.tripSeconds(0, false)
		T.near(TrainConfig.tripSeconds(0, false, 0.3), math.max(TrainConfig.MinTripSeconds, base * 0.7), 1e-9)
		T.near(TrainConfig.tripSeconds(0, false, 9), math.max(TrainConfig.MinTripSeconds, base * 0.5), 1e-9, "capped at half")
		T.eq(TrainConfig.tripSeconds(0, false, 0 / 0), base, "junk cut")
		-- the perks reach Bonuses (the built-in "Rebirth" provider)
		local save = ProfileStore.deepCopy(DataTemplate)
		save.StarPerks = { GoldenTouch = 3, LuckyRocks = 2, DeepPockets = 1, ExpressRails = 2 }
		local totals = Bonuses.compute(save, 0, nil)
		T.near(totals.IncomePct, 0.3, 1e-9, "Golden Touch III")
		T.near(totals.OreLuckPct, 0.1, 1e-9, "Lucky Rocks II")
		T.near(totals.TrainTimeCutPct, 0.2, 1e-9, "Express Rails II")
		T.near(totals.CarryCapacity - Bonuses.compute(ProfileStore.deepCopy(DataTemplate), 0, nil).CarryCapacity, 1, 1e-9, "Deep Pockets I")
	end)

	T.test("Rebirth: the reset resets exactly its list and keeps everything else", function()
		local data = midRun()
		T.eq(select(2, RebirthConfig.canRebirth({ BlasterLevel = MIN - 1 })), "Locked")
		T.eq(select(2, RebirthConfig.canRebirth(nil)), "NoData")
		T.truthy(RebirthConfig.canRebirth(data))
		local before = ProfileStore.deepCopy(data)
		local stars, count = RebirthConfig.reset(data)
		T.eq(stars, RebirthConfig.starsFor(8), "the stars of blaster 8")
		T.eq(count, 1)
		T.eq(data.Rebirths, 1)
		T.eq(data.Stars, stars)
		T.eq(data.Stats.StarsEarned, stars)
		-- reset
		T.eq(data.Coins, 0)
		T.eq(data.ShardRolls, 0)
		T.eq(data.BlasterLevel, 1)
		T.eq(data.BlasterOre, "", "the rusty starter")
		T.eq(data.Upgrades.Bellows, 0, "machine speed")
		T.eq(data.Upgrades.Elevator, false, "the elevator")
		T.truthy(deepEqual(data.MachineUpgrades, {}), "Tech shop levels")
		T.eq(data.Train.CapacityLevel, 0)
		T.eq(data.Train.SpeedLevel, 0)
		T.eq(#data.Train.Cargo, 0)
		T.eq(data.Gear.Backpack, 0, "the backpack")
		T.eq(#data.Storage, 0, "the pen")
		T.eq(#data.Foundry.Stock, 0, "the Foundry's ingots")
		for i = 1, 4 do
			T.eq(data.Podiums[i], "", "podium " .. i)
		end
		T.eq(data.PlacedMachines[1].In, nil, "queues")
		T.eq(data.PlacedMachines[1].Out, nil)
		-- kept: the factory and everything outside the list
		T.eq(#data.PlacedMachines, 2, "the factory stays")
		T.eq(data.PlacedMachines[2].C, 3, "machine settings stay")
		T.eq(data.PlacedMachines[1].X, 1)
		for _, key in
			{
				"Shards",
				"TotalEarned",
				"MachineInventory",
				"StarterKitGiven",
				"Enchants",
				"Golems",
				"Artifacts",
				"Discovered",
				"Hoverboards",
				"KeepMode",
				"KeepList",
				"OreCodex",
				"Settings",
				"Tutorial",
				"Purchases",
			}
		do
			T.truthy(deepEqual(before[key], data[key]), key .. " is kept")
		end
		for _, key in { "ExtraSlots", "PenLevel", "PenAutomation" } do
			T.eq(data.Upgrades[key], before.Upgrades[key], key .. " is kept")
		end
		for _, key in { "Boots", "HelmetLamp", "Gloves", "Magnet" } do
			T.eq(data.Gear[key], before.Gear[key], key .. " is kept")
		end
		T.eq(data.Stats.OresMined, 500, "stats stay")
		-- a rebirth right away is locked (blaster 1)
		T.eq(select(2, RebirthConfig.canRebirth(data)), "Locked")
		-- the next one adds up, and the save stays clean through Migrations
		data.BlasterLevel = TOP
		local more = RebirthConfig.reset(data)
		T.eq(more, RebirthConfig.MaxStars)
		T.eq(data.Rebirths, 2)
		T.eq(data.Stars, stars + more)
		T.eq(data.Stats.StarsEarned, stars + more)
		local copy = ProfileStore.deepCopy(data)
		local report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "Migrations leaves a rebirthed save alone")
		T.eq(report.Dropped, 0)
	end)

	T.test("Rebirth: Head Start and Podium Keeper", function()
		local data = midRun()
		data.StarPerks = { HeadStart = 3, PodiumKeeper = 1 }
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, RebirthConfig.HeadStartLevels[3], "starts with Head Start's level")
		T.eq(data.BlasterOre, BlasterData.vaultOre(data.BlasterLevel), "in that level's Vault look")
		T.eq(data.Podiums[1], "Clean|Gold|Pristine|", "the podium ores stay")
		T.eq(data.Podiums[3], "Clean|Copper|Rough|")
		T.eq(#data.Storage, 0, "the pen still empties")
	end)

	---------------------------------------------------------------- the service

	local function world(): any
		local w: any = { results = {}, changed = 0, saves = 0, destroyed = {}, trainResets = 0, refreshed = 0, reloads = 0 }
		w.data = midRun()
		w.player = { UserId = 4401, Name = "Reborn", Parent = true, attrs = {} }
		w.player.GetAttribute = function(self, key)
			return self.attrs[key]
		end
		w.player.SetAttribute = function(self, key, value)
			self.attrs[key] = value
		end
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
		patch(DataService, "saveNow", function()
			w.saves += 1
			return true
		end)
		patch(Net, "fire", function(name, p, a)
			if name == "RebirthResult" and p == w.player then
				table.insert(w.results, a)
			end
		end)
		w.items = {
			{ State = "Loose", Owner = 4401 },
			{ State = "Carried", Owner = 4401 },
			{ State = "Consumed", Owner = 4401 },
		}
		patch(ItemService, "ownedBy", function(userId)
			return if userId == 4401 then w.items else {}
		end)
		patch(ItemService, "destroy", function(record)
			table.insert(w.destroyed, record)
			record.State = "Consumed"
		end)
		patch(PlotService, "reload", function(_, between)
			w.reloads += 1
			between()
		end)
		patch(PlotService, "plotOf", function()
			return 3
		end)
		patch(PlotService, "sendHome", function() end)
		patch(PodiumService, "refreshPlot", function()
			w.refreshed += 1
		end)
		patch(TrainService, "resetRun", function()
			w.trainResets += 1
		end)
		w.settledAt = {}
		patch(PodiumService, "settleOffline", function()
			-- the waiting welcome-back payout is settled before the coins reset
			table.insert(w.settledAt, w.data.Coins)
		end)
		w.riding = false
		patch(ElevatorService, "isRiding", function()
			return w.riding
		end)
		patch(RebirthService, "MomentSeconds", 0) -- (Lune waits for every delayed thread)
		RebirthService._test.reset()
		w.restore = function()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			RebirthService._test.reset()
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = world()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	withWorld("RebirthService: a rebirth in one step: items out, the plot and the train start over", function(w)
		local action = RebirthService._test.action
		action(w.player, { Action = "Rebirth" })
		local result = w.results[#w.results]
		T.truthy(result and result.Ok, "rebirthed")
		T.eq(result.Stars, RebirthConfig.starsFor(8))
		T.eq(result.Rebirths, 1)
		T.eq(w.reloads, 1, "the plot came down and up once")
		T.eq(#w.destroyed, 2, "the loose and the carried item left the world (the consumed one was gone)")
		T.eq(w.trainResets, 1, "the train starts over")
		T.eq(w.refreshed, 1, "the podiums redraw")
		T.eq(#w.settledAt, 1, "the welcome-back payout was settled")
		T.eq(w.settledAt[1], 4.2e9, "...before the coins reset (it can't land in the new run)")
		T.truthy(w.changed >= 1, "changed")
		T.eq(w.data.Coins, 0)
		T.eq(w.data.Rebirths, 1)
		T.eq(w.player.attrs[RebirthService.StarsAttribute], result.Stars, "the gold star over the name")
		task.wait()
		T.eq(w.saves, 1, "saved right away")
		-- blaster 1 now: locked, nothing changes
		local coins = w.data.Coins
		action(w.player, { Action = "Rebirth" })
		T.eq(w.results[#w.results].Reason, "Locked")
		T.eq(w.reloads, 1, "no second reload")
		T.eq(w.data.Coins, coins)
		-- the snapshot
		local snap = RebirthService.snapshot(w.data)
		T.eq(snap.Count, 1)
		T.eq(snap.Stars, result.Stars)
		T.eq(snap.Ready, false)
		T.eq(snap.StarsNow, 0)
		T.eq(snap.MinBlaster, MIN)
	end)

	withWorld("RebirthService: a rebirth inside a rebirth is Busy; a failure leaves the rebirth free again", function(w)
		local inner: any = nil
		rawset(PlotService, "reload", function(_, between)
			w.reloads += 1
			inner = table.pack(RebirthService.rebirth(w.player))
			between()
		end)
		local ok = RebirthService.rebirth(w.player)
		T.truthy(ok, "the outer one went through")
		T.eq(inner[1], false)
		T.eq(inner[2], "Busy", "the inner one is refused")
		T.eq(w.data.Rebirths, 1, "one rebirth")
		-- a failing step: refused, and the next try is not stuck on Busy
		w.data.BlasterLevel = TOP
		rawset(PlotService, "reload", function()
			error("plot broke")
		end)
		local failed, reason = RebirthService.rebirth(w.player)
		T.falsy(failed)
		T.eq(reason, "Failed", "taking the plot down broke: nothing paid")
		rawset(PlotService, "reload", function(_, between)
			between()
		end)
		T.truthy(RebirthService.rebirth(w.player), "free again")
	end)

	withWorld("RebirthService: not during an elevator ride; a failing step after the reset still reports the rebirth", function(w)
		w.riding = true
		local ok, reason = RebirthService.rebirth(w.player)
		T.falsy(ok)
		T.eq(reason, "Busy", "the ride would land after the trip home")
		T.eq(w.data.Rebirths, 0, "nothing changed")
		T.eq(w.reloads, 0)
		w.riding = false
		rawset(TrainService, "resetRun", function()
			error("train broke")
		end)
		local done, stars = RebirthService.rebirth(w.player)
		T.truthy(done, "the rebirth happened and says so")
		T.eq(stars, RebirthConfig.starsFor(8))
		T.eq(w.refreshed, 1, "the later steps still ran")
		task.wait()
		T.eq(w.saves, 1, "and it was saved")
	end)

	withWorld("RebirthService: the Star Shop and junk input", function(w)
		local action = RebirthService._test.action
		w.data.Stars = 3
		action(w.player, { Action = "Buy", Perk = "GoldenTouch" })
		local result = w.results[#w.results]
		T.truthy(result.Ok)
		T.eq(result.Level, 1)
		T.eq(w.data.Stars, 2)
		action(w.player, { Action = "Buy", Perk = "PodiumKeeper" })
		T.eq(w.results[#w.results].Reason, "NoStars")
		action(w.player, { Action = "Buy", Perk = "Nope" })
		T.eq(w.results[#w.results].Reason, "BadPerk")
		local count = #w.results
		for _, junk in { nil, 5, "Rebirth", {}, { Action = 5 }, { Action = string.rep("R", 40) }, { Action = "Explode" } } do
			action(w.player, junk)
		end
		T.eq(#w.results, count, "junk gets no answer and changes nothing")
		T.eq(w.data.Stars, 2)
		T.eq(w.data.Rebirths, 0)
	end)
end
