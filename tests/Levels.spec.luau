-- The player LEVEL (owner 2026-10-21): XP from the save's counters, the curve, the
-- rewards, the silent backfill of old saves, no XP farming, the LEVEL board, the
-- level-up moment's poses.
return function(T, Loader)
	local LevelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LevelConfig")
	local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
	local LevelService = Loader.requirePath("ServerScriptService.Server.Services.LevelService")

	local function save(): { [string]: any }
		return {
			Stats = { RocksBroken = 0, OresMined = 0, PlaySeconds = 0 },
			Discovered = {},
			MachineInventory = {},
			PlacedMachines = {},
			Golems = { Owned = {} },
			Upgrades = { Bellows = 0, Elevator = false },
			MachineUpgrades = {},
			Gear = { Boots = 0 },
			Train = { CapacityLevel = 0, SpeedLevel = 0 },
			Enchants = { Owned = {} },
			BlasterLevel = 1,
			Rebirths = 0,
			Level = { Level = 1, Xp = 0, Seen = {}, Ready = true },
		}
	end

	T.test("Levels: the curve grows, starts at 80 XP, whole fives", function()
		T.eq(LevelConfig.need(1), 80)
		local last = 0
		for level = 1, 200 do
			local need = LevelConfig.need(level)
			T.truthy(need > last, "grows at " .. level)
			T.eq(need % 5, 0, "a whole five")
			last = need
		end
		T.eq(LevelConfig.totalFor(1), 0)
		T.eq(LevelConfig.totalFor(3), LevelConfig.need(1) + LevelConfig.need(2))
	end)

	T.test("Levels: add carries the rest over and can cross several levels", function()
		local record = LevelConfig.sanitize({ Level = { Level = 1, Xp = 0 } })
		local ups = LevelConfig.add(record, LevelConfig.need(1) + LevelConfig.need(2) + 7)
		T.eq(#ups, 2)
		T.eq(ups[1], 2)
		T.eq(ups[2], 3)
		T.eq(record.Level, 3)
		T.eq(record.Xp, 7)
		local top = LevelConfig.sanitize({ Level = { Level = LevelConfig.MaxLevel, Xp = 50 } })
		T.eq(#LevelConfig.add(top, 1e9), 0, "nothing past the max")
		T.eq(top.Xp, 0)
	end)

	T.test("Levels: sanitize repairs junk", function()
		local data = { Level = { Level = -5, Xp = 0 / 0, Seen = { Bogus = 3, RocksBroken = "x", OresMined = 4 }, Ready = "yes" } }
		local r = LevelConfig.sanitize(data)
		T.eq(r.Level, 1)
		T.eq(r.Xp, 0)
		T.eq(r.Seen.Bogus, nil)
		T.eq(r.Seen.RocksBroken, nil)
		T.eq(r.Seen.OresMined, 4)
		T.eq(r.Ready, false)
		T.eq(LevelConfig.sanitize({}).Level, 1, "no record: a new one")
	end)

	T.test("Levels: XP for what grew, nothing twice", function()
		local data = save()
		LevelService.step(data, 0) -- first look: baselines
		data.Stats.RocksBroken = 10
		data.Stats.OresMined = 5
		local gained = LevelService.step(data, 0)
		T.eq(gained, 10 * 3 + 5 * 1)
		T.eq(LevelService.step(data, 0), 0, "nothing new, nothing paid")
		data.Stats.PlaySeconds = 60
		T.near(LevelService.step(data, 0), 2, 1e-9, "a minute of active play")
	end)

	T.test("Levels: machines and golems count by the most ever (no place / pick up farming)", function()
		local data = save()
		LevelService.step(data, 0)
		data.MachineInventory = { Conveyor = 3 }
		T.eq(LevelService.step(data, 0), 30)
		-- placing them: inventory -> placed, the same machines
		data.MachineInventory = { Conveyor = 1 }
		data.PlacedMachines = { { Id = "Conveyor" }, { Id = "Conveyor" } }
		T.eq(LevelService.step(data, 0), 0)
		-- selling one and buying it back pays nothing either
		data.MachineInventory = {}
		LevelService.step(data, 0)
		data.MachineInventory = { Conveyor = 1 }
		T.eq(LevelService.step(data, 0), 0)
	end)

	T.test("Levels: a rebirth set-back counts again from there, the level stays", function()
		local data = save()
		LevelService.step(data, 0)
		data.BlasterLevel = 5
		data.Gear.Boots = 3
		T.eq(LevelService.step(data, 0), 4 * 50 + 3 * 20)
		local level = data.Level.Level
		-- the rebirth
		data.BlasterLevel = 1
		data.Gear.Boots = 0
		data.Rebirths = 1
		T.eq(LevelService.step(data, 0), 250, "the rebirth pays, the set-backs don't take")
		T.truthy(data.Level.Level >= level, "the level never drops")
		data.BlasterLevel = 2
		T.eq(LevelService.step(data, 0), 50, "climbing again pays again")
	end)

	T.test("Levels: an old save backfills silently (no coins, no moment)", function()
		local data = save()
		data.Level = nil
		data.Stats.RocksBroken = 400
		data.Discovered = { Coal = true, Copper = true }
		local gained, ups, changed = LevelService.step(data, 1000)
		T.eq(gained, 0)
		T.eq(#ups, 0)
		T.truthy(changed)
		T.truthy(data.Level.Ready)
		T.truthy(data.Level.Level > 1, "a fair start: level " .. data.Level.Level)
		T.eq(LevelConfig.totalFor(data.Level.Level) + data.Level.Xp, 400 * 3 + 2 * 30)
		T.eq(LevelService.step(data, 0), 0, "and nothing counted twice after it")
	end)

	T.test("Levels: level ups pay coins (bigger with income, x5 every 10th) and +1 % income", function()
		local data = save()
		LevelService.step(data, 0)
		data.Stats.RocksBroken = 27 -- 81 XP: level 2
		local _, ups = LevelService.step(data, 0)
		T.eq(#ups, 1)
		T.eq(ups[1].Level, 2)
		T.eq(ups[1].Coins, LevelConfig.CoinsPerLevel * 2)
		T.near(ups[1].Bonus, 0.01, 1e-9)
		T.eq(LevelConfig.coinsFor(3, 1000), 1000 * LevelConfig.IncomeSeconds, "late game: income seconds")
		T.eq(LevelConfig.coinsFor(10, 0), LevelConfig.CoinsPerLevel * 10 * LevelConfig.MilestoneFactor)
		T.near(LevelConfig.bonusFor(1), 0, 1e-9)
		T.near(LevelConfig.bonusFor(400), LevelConfig.BonusCap, 1e-9, "capped")
	end)

	T.test("Levels: the LEVEL board is board 5, whole levels, never down", function()
		local board = LeaderboardConfig.ById.Level
		T.truthy(board)
		T.eq(board.Index, 5)
		T.eq(LeaderboardConfig.ByIndex[5], board)
		T.eq(LeaderboardConfig.decode("Level", LeaderboardConfig.encode("Level", 42)), 42)
		T.eq(LeaderboardConfig.format("Level", 42), "LV 42")
		local LeaderboardService = Loader.requirePath("ServerScriptService.Server.Services.LeaderboardService")
		T.eq(LeaderboardService.valueOf(nil :: any, { Level = { Level = 17 } }, "Level"), 17)
		T.eq(LeaderboardService.Growing.Level, true)
	end)

	T.test("Levels: the moment and the burst pose without errors at every moment", function()
		local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
		local LevelBurst = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.LevelBurst")
		local roblox = require("@lune/roblox") :: any
		local view = LevelView.build()
		local model = roblox.Instance.new("Model")
		local burst = LevelBurst.build(model, roblox.CFrame.new(0, 0, 0), true)
		for t = -0.1, LevelView.MomentSeconds + 0.1, 0.05 do
			LevelView.poseMoment(view, t, { Level = 20, Coins = 12345, Bonus = 0.19, Milestone = true })
			LevelView.poseGlow(view, (t % 1), t)
			LevelBurst.pose(burst, t)
		end
		LevelView.setBar(view, 12, 0.5, 300, 600)
		T.eq(view.XpText.Text, "300 / 600 XP")
		T.eq(view.BadgeLevel.Text, "12")
		LevelView.hideMoment(view)
		T.eq(view.Moment.Visible, false)
	end)
end
