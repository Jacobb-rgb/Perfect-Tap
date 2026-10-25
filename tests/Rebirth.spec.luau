--[[
	Rebirth "STAR FORGE" (RebirthConfig, RebirthService) under Lune.
	The rules pin relationships, not numbers (the machines chat recalibrates
	the blaster prices): the stars follow the blaster coin scale, the Star
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
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
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
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local PlotGlow = Loader.requirePath("ServerScriptService.Server.World.PlotGlow")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local roblox = require("@lune/roblox") :: any

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
			{ Id = "Sorter", X = 4, Z = 1, R = 1, C = 3, L = 1 }, -- on a platform's deck
			-- a dusty relic queued at the Restoration Table
			{ Id = "RestorationTable", X = 7, Z = 1, R = 0, In = { { K = "Relic", O = "CrownCoin" } } },
		}
		data.StarterKitGiven = true
		data.Storage = { { K = "Clean", O = "Gold", G = "Pristine" }, { K = "Raw", O = "Coal" }, { K = "Relic", O = "AncientGear" } }
		data.Podiums = { "Clean|Gold|Pristine|", "", "Clean|Copper|Rough|", "", "" }
		data.Train = {
			CapacityLevel = 3,
			SpeedLevel = 4,
			Cargo = { { K = "Raw", O = "Coal" }, { K = "Relic", O = "MinersLamp" } },
			TripCargo = {},
			TripDepartAt = 0,
			TripArriveAt = 0,
		}
		data.Gear = { Boots = 3, HelmetLamp = 2, Backpack = 4, Gloves = 1, Magnet = 2 }
		-- slot 2 holds a paid enchant (a game pass gave it)
		data.Enchants = { Owned = { Lucky = 2, Midas = 3 }, Slots = { "Lucky", "Midas", "", "" }, Passes = { Midas = true } }
		data.Golems = { Owned = { { Id = 1, Kind = "PebbleGolem" } }, Equipped = { 1 }, NextId = 2 }
		data.Artifacts = { Found = { CrownCoin = 2 }, Chapters = {} }
		data.Discovered = { Gold = true, Coal = true }
		data.Hoverboards = { Owned = { Comet = true }, Equipped = "Comet", Passes = {} }
		data.RebirthWeapons = { Comet = true, Nebula = true } -- star blasters (one by a pass)
		data.RebirthWeaponPasses = { Nebula = true }
		data.StarBlaster = "Comet"
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
			return BlasterData.coins(level)
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
		-- the pen keeps only dusty relics (artifacts, never ore): from the pen, the train and the queues
		T.eq(#data.Storage, 3, "the pen holds just the relics")
		for _, item in data.Storage do
			T.eq(item.K, "Relic", "only relics")
		end
		T.eq(data.Foundry, nil, "no Foundry record (v8)")
		T.eq(data.Stats.RunIncome, 0, "the reset clears the run's price floor (RebirthService writes the kept income)")
		for i = 1, 5 do
			T.eq(data.Podiums[i], "", "podium " .. i)
		end
		T.eq(data.PlacedMachines[1].In, nil, "queues")
		T.eq(data.PlacedMachines[1].Out, nil)
		-- kept: the factory and everything outside the list
		T.eq(#data.PlacedMachines, 3, "the factory stays")
		T.eq(data.PlacedMachines[2].C, 3, "machine settings stay")
		T.eq(data.PlacedMachines[2].L, 1, "a deck machine stays on its deck")
		T.eq(data.PlacedMachines[1].X, 1)
		for _, key in
			{
				"Shards",
				"TotalEarned",
				"MachineInventory",
				"StarterKitGiven",
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
				"RebirthWeapons",
				"RebirthWeaponPasses",
				"StarBlaster",
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
		-- the enchants stay slotted, the paid one first (blaster LV 1 opens slot 1 only)
		T.eq(data.Enchants.Slots[1], "Midas", "the paid enchant takes the open slot")
		T.eq(data.Enchants.Slots[2], "Lucky", "the other waits in a slot that opens later")
		T.truthy(deepEqual(data.Enchants.Owned, before.Enchants.Owned), "every enchant owned still")
		T.truthy(deepEqual(data.Enchants.Passes, before.Enchants.Passes), "pass records untouched")
		-- the best level is kept for the prices, the run starts with nothing forged
		T.eq(data.Stats.BestBlaster, 8)
		T.eq(data.Stats.RunForged, 0)
		-- a rebirth right away is locked (blaster 1)
		T.eq(select(2, RebirthConfig.canRebirth(data)), "Locked")
		-- the next one adds up (a level bought with coins this run), and the save stays clean through Migrations
		data.BlasterLevel = TOP
		data.Stats.RunForged = TOP
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

	T.test("Rebirth: no star farming with Vault levels; a rebirth never makes a coin price cheaper", function()
		-- the first run counts the blaster as it is (players from before rebirth keep their way there)
		local data = midRun()
		data.StarPerks = { PodiumKeeper = 1 }
		T.eq(RebirthConfig.reachedOf(data), 8, "first run: the level as it is")
		local function prices(save: any): { number }
			local level = BlasterData.priceLevel(save)
			local list = {}
			for _, capsule in CapsuleConfig.List do
				local price = CapsuleConfig.price(capsule.Id, 10, level)
				if price then
					table.insert(list, price)
				end
			end
			for _, offer in BoostConfig.CoinOffers do
				local price = BoostConfig.coinPrice(offer.Id, level)
				if price then
					table.insert(list, price)
				end
			end
			table.insert(list, WheelConfig.capsuleFallbackCoins("Crystal", level))
			return list
		end
		local before = prices(data)
		T.truthy(#before > 2, "some coin prices to compare")
		RebirthConfig.reset(data)
		T.truthy(deepEqual(prices(data), before), "the same coin prices right after the rebirth (BlasterData.priceLevel)")
		-- run 2: Vault cases up to MinBlaster (coins only, the kept podiums pay for them)
		data.BlasterLevel = MIN
		T.eq(RebirthConfig.reachedOf(data), 0, "nothing bought with coins this run")
		local ok, reason = RebirthConfig.canRebirth(data)
		T.falsy(ok)
		T.eq(reason, "NotForged", "levels that came another way (a lifted start) don't count after the first rebirth")
		T.eq(RebirthConfig.starsFor(RebirthConfig.reachedOf(data)), 0)
		-- bought with coins at the Vault: it counts (never above the level held)
		data.Stats.RunForged = MIN
		T.truthy(RebirthConfig.canRebirth(data))
		data.Stats.RunForged = TOP
		T.eq(RebirthConfig.reachedOf(data), MIN, "at most the level held")
		T.eq(RebirthConfig.reset(data), RebirthConfig.starsFor(MIN))
		T.truthy(deepEqual(prices(data), before), "still the same prices two rebirths on")
		T.eq(data.Stats.BestBlaster, 8, "never lowered")
	end)

	T.test("Rebirth: Plot Glow colours unlock by level, the pick cycles, a buy shows the new one", function()
		T.eq(#RebirthConfig.GlowColors, #RebirthConfig.ById.PlotGlow.Costs, "one colour per level")
		local data: any = { Stars = 5, StarPerks = {}, PlotGlow = "" }
		T.truthy(RebirthConfig.glowUnlocked(data.StarPerks, ""), "off is always allowed")
		T.falsy(RebirthConfig.glowUnlocked(data.StarPerks, "Bronze"), "nothing unlocked yet")
		T.eq(RebirthConfig.nextGlow(data.StarPerks, ""), "", "nothing to cycle to")
		T.eq(RebirthConfig.buy(data, "PlotGlow"), 1)
		T.eq(data.PlotGlow, "Bronze", "the new colour shows at once")
		RebirthConfig.buy(data, "PlotGlow")
		T.eq(data.PlotGlow, "Silver")
		T.eq(RebirthConfig.nextGlow(data.StarPerks, "Silver"), "", "after the last unlocked: off")
		T.eq(RebirthConfig.nextGlow(data.StarPerks, ""), "Bronze", "then from the first again")
		T.eq(RebirthConfig.nextGlow(data.StarPerks, "Bronze"), "Silver")
		T.falsy(RebirthConfig.glowUnlocked(data.StarPerks, "Prism"))
		data.PlotGlow = "Prism" -- (a newer build's pick, or junk): shown as off here
		T.eq(RebirthConfig.glowOf(data), "")
		data.PlotGlow = "Silver"
		T.eq(RebirthConfig.glowOf(data), "Silver")
		T.eq(RebirthConfig.stats(data.StarPerks).IncomePct, nil, "cosmetic: no stats")
	end)

	T.test("Rebirth: the Plot Glow model: 8 neon parts on the walls, safe for phones", function()
		local folder = roblox.Instance.new("Folder")
		local cf = Loader.CFrame.new(40, 0, -60)
		T.eq(PlotGlow.build(folder, cf, ""), nil, "off: nothing")
		T.eq(PlotGlow.build(folder, cf, "Nope"), nil, "unknown: nothing")
		for _, color in RebirthConfig.GlowColors do
			local model = PlotGlow.build(folder, cf, color.Id)
			T.truthy(model, color.Id)
			T.eq(model.Name, PlotGlow.Name)
			T.eq(model:GetAttribute("Color"), color.Id)
			local parts, hues = 0, {}
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					parts += 1
					hues[part.Color:ToHex()] = true
					T.eq(part.Material, roblox.Enum.Material.Neon)
					T.truthy(
						part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch and not part.CastShadow,
						"decor only"
					)
					local p = cf:PointToObjectSpace(part.CFrame.Position)
					T.truthy(
						math.abs(p.X) <= PlotBuilder.WallLine + 0.5 and math.abs(p.Z) <= PlotBuilder.WallLine + 0.5,
						"on the pad's border"
					)
					T.truthy(p.Y > 2 and p.Y < 5, "on the walls, under head height")
				end
			end
			T.eq(parts, PlotGlow.MaxParts, color.Id .. " part count")
			local distinct = 0
			for _ in hues do
				distinct += 1
			end
			if color.Id == "Prism" then
				T.truthy(distinct >= 4, "Prism is a rainbow")
			else
				T.eq(distinct, 1, color.Id .. " is one colour")
			end
			model:Destroy()
		end
	end)

	T.test("Rebirth: Robux blaster levels never pay stars and come back at every rebirth", function()
		-- a first run with a level bought with Robux counts only the levels bought with coins
		local data = midRun()
		data.Stats.RunPaid = true
		T.eq(RebirthConfig.reachedOf(data), 0, "the first-run grace is gone once a level was bought")
		T.eq(select(2, RebirthConfig.canRebirth(data)), "NotForged")
		data.Stats.RunForged = 7
		T.eq(RebirthConfig.reachedOf(data), 7, "forged levels still count")
		-- every Robux level lifts the fresh blaster one level, at every rebirth
		data.Stats.BlastersPaid = 2
		T.eq(RebirthConfig.startFor(data), 3)
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, 3, "LV 1 + 2 Robux levels")
		T.eq(data.BlasterOre, BlasterData.vaultOre(3))
		T.eq(data.Stats.BlastersPaid, 2, "kept: they come back next time too")
		T.eq(data.Stats.RunPaid, true, "the lifted run is paid (no stars for it)")
		T.eq(RebirthConfig.reachedOf(data), 0, "the lifted level isn't forged: no stars for it")
		data.BlasterLevel = TOP
		data.Stats.RunForged = TOP
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, 3, "the second rebirth lifts it again")
		-- with Head Start, never past MaxLevel - 1: a level is left to forge, so a rebirth can be earned again
		data.StarPerks = { HeadStart = 3 }
		data.Stats.BlastersPaid = 40
		data.BlasterLevel = TOP
		data.Stats.RunForged = TOP
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, TOP - 1)
		data.BlasterLevel = TOP
		data.Stats.RunForged = TOP
		T.truthy(RebirthConfig.canRebirth(data), "forging the top level earns the next rebirth")
		-- Head Start alone: an unpaid run
		data.Stats.BlastersPaid = 0
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, RebirthConfig.HeadStartLevels[3])
		T.eq(data.Stats.RunPaid, false)
		T.eq(RebirthConfig.startFor({ Stats = { BlastersPaid = 0 / 0 } }), 1, "junk")
		T.eq(RebirthConfig.startFor(nil), 1)
		-- Head Start adds nothing once the Robux levels reach the cap: not sold then
		local capped = midRun()
		capped.Stars = 99
		capped.Stats.BlastersPaid = 8
		T.eq(select(2, RebirthConfig.quote(capped, "HeadStart")), "Max")
		capped.Stats.BlastersPaid = 5
		capped.StarPerks = { HeadStart = 2 }
		T.eq(
			RebirthConfig.quote(capped, "HeadStart"),
			RebirthConfig.nextCost(capped.StarPerks, "HeadStart"),
			"LV 3 + 5 < 9: it still helps"
		)
		T.eq(RebirthConfig.quote(capped, "GoldenTouch"), RebirthConfig.nextCost(capped.StarPerks, "GoldenTouch"), "other perks unchanged")
	end)

	T.test("Rebirth: a save stuck at the top level with nothing forged may still rebirth, for no stars", function()
		-- (the coin Vault could sell LV 10 on a rebirth run before topBlocked existed)
		local data = midRun()
		data.Rebirths = 2
		data.BlasterLevel = TOP
		data.Stats.RunForged = 3
		T.truthy(RebirthConfig.canRebirth(data), "not locked out for good")
		local stars, count = RebirthConfig.reset(data)
		T.eq(stars, 0, "no stars: no coin level")
		T.eq(count, 3)
		-- below the top, a run without a coin level still has to buy one
		data.BlasterLevel = TOP - 1
		data.Stats.RunForged = 0
		T.eq(select(2, RebirthConfig.canRebirth(data)), "NotForged")
		T.truthy(RebirthConfig.topBlocked(data), "and the STORE leaves the top level to the coin Vault")
		T.falsy(RebirthConfig.topBlockedFor(TOP - 2, 0), "only the step to the top waits")
	end)

	T.test("Rebirth: Head Start and Podium Keeper", function()
		local data = midRun()
		data.StarPerks = { HeadStart = 3, PodiumKeeper = 1 }
		RebirthConfig.reset(data)
		T.eq(data.BlasterLevel, RebirthConfig.HeadStartLevels[3], "starts with Head Start's level")
		T.eq(data.BlasterOre, BlasterData.vaultOre(data.BlasterLevel), "in that level's Vault look")
		T.eq(data.Podiums[1], "Clean|Gold|Pristine|", "the podium ores stay")
		T.eq(data.Podiums[3], "Clean|Copper|Rough|")
		T.eq(#data.Storage, 3, "the pen still empties (only the relics wait there)")
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
			{ State = "Loose", Owner = 4401, Kind = "Raw" },
			{ State = "Carried", Owner = 4401, Kind = "Clean" },
			{ State = "Consumed", Owner = 4401, Kind = "Raw" },
			{ State = "Carried", Owner = 4401, Kind = "Relic", OreId = "GoldenIdol" },
		}
		w.stashed, w.kept = {}, {}
		patch(ItemService, "stash", function(record)
			table.insert(w.stashed, record)
			record.State = "Consumed"
			return true
		end)
		patch(ItemService, "keepRelic", function(_, artifactId)
			table.insert(w.kept, artifactId)
			return true
		end)
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
		T.eq(#w.destroyed, 2, "the loose and the carried ore left the world (the consumed one was gone)")
		T.eq(#w.stashed, 1, "the carried relic was stashed (the keeper adds it to the collection)")
		T.eq(w.stashed[1].OreId, "GoldenIdol")
		table.sort(w.kept)
		T.eq(
			table.concat(w.kept, ","),
			"AncientGear,CrownCoin,MinersLamp",
			"the relics from the pen, the train and the Restoration Table went to the keeper"
		)
		T.eq(#w.data.Storage, 0, "nothing left in the pen")
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

	withWorld("RebirthService: the run's Vault prices have a floor of the income the factory kept", function(w)
		-- (owner 2026-10-24, no Foundry: the droppers stay through a rebirth, so the low
		-- levels would cost seconds of their income and the stars would farm)
		local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
		local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
		local dropper = DropperConfig.List[1]
		table.insert(w.data.PlacedMachines, { Id = dropper.Id, X = 12, Z = 12, R = 0 })
		RebirthService._test.action(w.player, { Action = "Rebirth" })
		T.truthy(w.results[#w.results].Ok, "rebirthed")
		local kept = DropperConfig.placedIncome(w.data.PlacedMachines) * EconomyService.incomeMultiplier(w.player)
			+ PodiumService.incomeOf(w.player, w.data)
		T.truthy(kept >= dropper.Income, "the dropper's income counts")
		T.near(w.data.Stats.RunIncome, kept, kept * 1e-9, "Stats.RunIncome = the income the factory kept")
		T.near(RebirthConfig.runIncomeOf(w.data), kept, kept * 1e-9)
		T.near(RebirthService.snapshot(w.data).RunIncome, kept, kept * 1e-9, "the client sees the floor (VaultView)")
		-- the Vault charges at least that much income for LV 2 now
		local floor = kept * BlasterData.Vault.RunSeconds[2] * BlasterData.Vault.RunShare
		T.truthy((BlasterData.vaultPrice(2, RebirthConfig.runIncomeOf(w.data)) :: number) >= floor, "LV 2 costs the floor")
	end)

	withWorld("RebirthService: packing the droppers before a rebirth doesn't lower the floor for long", function(w)
		-- (review 2026-10-25: the floor was a snapshot; it is the run's high-water mark now)
		local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
		local dropper = DropperConfig.List[#DropperConfig.List]
		-- packed into the Build menu before the rebirth: nothing placed earns
		w.data.MachineInventory[dropper.Id] = 2
		RebirthService._test.action(w.player, { Action = "Rebirth" })
		T.truthy(w.results[#w.results].Ok, "rebirthed")
		local low = RebirthConfig.runIncomeOf(w.data)
		T.lt(low, dropper.Income, "the snapshot at the rebirth saw no dropper")
		-- placed again right after: the next income tick (or a Vault buy) raises the floor
		table.insert(w.data.PlacedMachines, { Id = dropper.Id, X = 12, Z = 12, R = 0 })
		table.insert(w.data.PlacedMachines, { Id = dropper.Id, X = 12, Z = 10, R = 0 })
		T.truthy(PodiumService.raiseRunIncome(w.player, w.data), "raised")
		local high = RebirthConfig.runIncomeOf(w.data)
		T.near(high, PodiumService.keptIncome(w.player, w.data), high * 1e-9, "the factory's income now")
		T.truthy(high >= 2 * dropper.Income, "both droppers count")
		local floor = high * BlasterData.Vault.RunSeconds[2] * BlasterData.Vault.RunShare
		T.truthy((BlasterData.vaultPrice(2, high) :: number) >= floor, "LV 2 costs the floor again")
		-- packed again: the floor stays (a high-water mark, never lower)
		table.clear(w.data.PlacedMachines)
		T.falsy(PodiumService.raiseRunIncome(w.player, w.data), "nothing to raise")
		T.eq(RebirthConfig.runIncomeOf(w.data), high, "the floor never drops in a run")
		-- the first run has no floor
		local first = ProfileStore.deepCopy(w.data)
		first.Rebirths = 0
		first.Stats.RunIncome = 0
		table.insert(first.PlacedMachines, { Id = dropper.Id, X = 12, Z = 12, R = 0 })
		T.falsy(PodiumService.raiseRunIncome(w.player, first), "no floor before the first rebirth")
		T.eq(first.Stats.RunIncome, 0)
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
		w.data.Stats.RunForged = TOP
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

	withWorld("RebirthService: the Plot Glow follows the save; the crystal prompt opens the window", function(w)
		local plot = roblox.Instance.new("Model")
		rawset(PlotService, "model", function()
			return plot
		end)
		rawset(PlotService, "plotCFrame", function()
			return Loader.CFrame.new()
		end)
		local action = RebirthService._test.action
		w.data.Stars = 3
		action(w.player, { Action = "Glow", Color = "Bronze" })
		T.eq(w.results[#w.results].Reason, "Locked", "not unlocked yet")
		action(w.player, { Action = "Buy", Perk = "PlotGlow" })
		T.truthy(w.results[#w.results].Ok)
		local shown = plot:FindFirstChild(PlotGlow.Name)
		T.truthy(shown, "built at once")
		T.eq(shown:GetAttribute("Color"), "Bronze")
		action(w.player, { Action = "Glow", Color = "" })
		T.truthy(w.results[#w.results].Ok)
		T.eq(plot:FindFirstChild(PlotGlow.Name), nil, "off: gone")
		T.eq(w.data.PlotGlow, "")
		action(w.player, { Action = "Glow", Color = "Bronze" })
		T.eq(plot:FindFirstChild(PlotGlow.Name):GetAttribute("Color"), "Bronze", "back on")
		action(w.player, { Action = "Glow", Color = 5 })
		T.eq(w.results[#w.results].Reason, "Locked", "junk")
		T.eq(w.data.PlotGlow, "Bronze", "junk changes nothing")
		-- the crystal prompt
		local ring = roblox.Instance.new("Model")
		local prompt = RebirthService.setupCrystal(ring, roblox.Vector3.new(0, 0, 0), 0.43)
		T.eq(prompt.ActionText, "Star Forge")
		T.eq(prompt.KeyboardKeyCode, PromptConfig.Keys.Main.Keyboard)
		T.eq(prompt.GamepadKeyCode, PromptConfig.Keys.Main.Gamepad)
		T.eq(prompt.MaxActivationDistance, RebirthService.CrystalRange)
		local anchor = ring:FindFirstChild(RebirthService.CrystalPrompt)
		T.truthy(anchor and anchor.Transparency == 1 and anchor.Anchored and not anchor.CanCollide, "an invisible anchor")
		T.near(anchor.CFrame.Position.Y, 3.43, 1e-3, "chest height over the plaza tiles")
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

	T.test("Rebirth: Robux-bought coins that are still unspent stay; bought coins are spent last", function()
		local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
		-- the reset keeps only PaidCoins (never more than the balance)
		local data = midRun()
		data.PaidCoins = 1.5e6
		RebirthConfig.reset(data)
		T.eq(data.Coins, 1.5e6, "the unspent bought coins stay")
		T.eq(data.PaidCoins, 1.5e6)
		local poor = midRun()
		poor.Coins = 200
		poor.PaidCoins = 5000
		RebirthConfig.reset(poor)
		T.eq(poor.Coins, 200, "never more than the balance")
		T.eq(poor.PaidCoins, 200)
		local none = midRun()
		RebirthConfig.reset(none)
		T.eq(none.Coins, 0, "earned coins go")
		T.eq(none.PaidCoins, 0)
		-- Migrations: junk and too-big values are repaired
		local junk = ProfileStore.deepCopy(DataTemplate)
		junk.Coins = 100
		junk.PaidCoins = 0 / 0
		Migrations.run(junk)
		T.eq(junk.PaidCoins, 0)
		junk.PaidCoins = 500
		Migrations.run(junk)
		T.eq(junk.PaidCoins, 100, "PaidCoins <= Coins")
		-- spending takes the earned coins first
		local player = { Name = "Payer", UserId = 41 }
		local wallet = ProfileStore.deepCopy(DataTemplate)
		wallet.Coins = 1000
		wallet.PaidCoins = 600
		local oldGet, oldChanged = DataService.get, DataService.changed
		DataService.get = function(p: any)
			return if p == player then wallet else nil
		end :: any
		DataService.changed = function() end :: any
		local ok, err = pcall(function()
			T.truthy(EconomyService.spend(player :: any, 300, "test"))
			T.eq(wallet.Coins, 700)
			T.eq(wallet.PaidCoins, 600, "300 earned coins went first")
			T.truthy(EconomyService.spend(player :: any, 400, "test"))
			T.eq(wallet.Coins, 300)
			T.eq(wallet.PaidCoins, 300, "then the bought ones")
		end)
		DataService.get, DataService.changed = oldGet, oldChanged
		if not ok then
			error(err, 0)
		end
	end)
end
