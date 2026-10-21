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

	T.test("Levels: placed machines count by the most ever (no bulk buys, no place / pick up farming)", function()
		local data = save()
		LevelService.step(data, 0)
		-- 999 Conveyors bought into the build menu pay nothing (review HIGH 2026-10-22)
		data.MachineInventory = { Conveyor = 999, Crusher = 999 }
		T.eq(LevelService.step(data, 0), 0, "the build menu pays nothing")
		-- placing pays per machine standing, at most the build slots
		local slots = 12
		for _ = 1, slots do
			table.insert(data.PlacedMachines, { Id = "Conveyor" })
		end
		T.eq(LevelService.step(data, 0), slots * 10, "at most slots x 10")
		-- picking up and placing again pays nothing
		data.PlacedMachines = { { Id = "Conveyor" } }
		T.eq(LevelService.step(data, 0), 0)
		for _ = 2, slots do
			table.insert(data.PlacedMachines, { Id = "Conveyor" })
		end
		T.eq(LevelService.step(data, 0), 0, "back to the old high mark: nothing")
		-- droppers and the Money Laser earn money, not XP
		local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
		for id in DropperConfig.ById do
			table.insert(data.PlacedMachines, { Id = id })
		end
		table.insert(data.PlacedMachines, { Id = DropperConfig.Laser.Id })
		T.eq(LevelService.step(data, 0), 0, "droppers give no XP")
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

	T.test("Levels: Reduce motion: no flash, no rays, LEVEL UP! at full size", function()
		local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
		local view = LevelView.build()
		local m = { Level = 12, Coins = 500, Bonus = 0.11, Increase = 0.01, Milestone = false }
		for t = 0, LevelView.MomentSeconds, 0.1 do
			LevelView.poseMoment(view, t, m, true)
			T.eq(view.Flash.BackgroundTransparency, 1, "no flash at " .. t)
			T.eq(view.TitleScale.Scale, 1, "full size at " .. t)
			T.eq(view.Title.Rotation, 0, "no wobble")
			T.eq(view.Rays.Visible, false, "no rays")
		end
		LevelView.poseGlow(view, 0.95, 1.234, true)
		T.eq(view.BarScale.Scale, 1, "a steady bar")
	end)

	T.test("Levels: the INCOME row says what this level added, MAX at the cap", function()
		local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
		local label, amount = LevelView.incomeText({ Level = 12, Coins = 0, Bonus = 0.11, Increase = 0.01, Milestone = false })
		T.eq(label, "+1% INCOME")
		T.eq(amount, "11%")
		local capLabel, capAmount =
			LevelView.incomeText({ Level = 70, Coins = 0, Bonus = LevelConfig.BonusCap, Increase = 0, Milestone = false })
		T.eq(capLabel, "INCOME")
		T.eq(capAmount, "MAX 50%")
		T.near(LevelConfig.bonusFor(51) - LevelConfig.bonusFor(50), 0.01, 1e-9, "level 51 still adds")
		T.eq(LevelConfig.bonusFor(52) - LevelConfig.bonusFor(51), 0, "past the cap: nothing")
	end)

	T.test("leaderboards: every tab word fits its tab with five boards (PC and a 568 x 320 phone)", function()
		local LeaderboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LeaderboardView")
		local panel = LeaderboardView.buildPanel(false)
		-- PC, a 1366 x 768 window, a 568 x 320 phone (uiScale floor 0.62)
		for _, case in
			{
				{ Compact = false, W = math.huge, H = math.huge },
				{ Compact = false, W = 1366 / 1.07, H = 768 / 1.07 },
				{ Compact = true, W = 568 / 0.62, H = 320 / 0.62 },
			}
		do
			LeaderboardView.layoutPanel(panel, case.Compact, case.W, case.H)
			for _, board in LeaderboardConfig.Boards do
				local tab = panel.Tabs[board.Id]
				local holder = tab.Parent
				local tabW = if holder
						and holder:IsA("GuiObject")
						and holder.Size.X.Offset > 0
					then holder.Size.X.Offset
					else tab.Size.X.Offset
				local word = LeaderboardView.Short[board.Id] or board.Title
				T.le(
					LeaderboardView.textWidth(word) * tab.TextSize,
					tabW - LeaderboardView.TabPad + 1e-6,
					`{word} fits (compact {case.Compact})`
				)
				T.truthy(tab.TextSize >= LeaderboardView.MinText, word .. " stays readable")
			end
		end
	end)

	T.test("Levels: on a 568 x 320 phone the rewards end above the XP bar", function()
		local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
		T.eq(LevelView.fitFor((900 - 36) / 1.25), 1, "a PC screen: full size")
		local design = (320 - 36) / 0.62
		local k = LevelView.fitFor(design)
		T.truthy(k < 1, "smaller on the phone")
		local rowsBottom = LevelView.MomentTop + (LevelView.RowTop + 2 * LevelView.RowGap + 48) * k
		T.le(rowsBottom, design - LevelView.BarBottom - LevelView.BarHeight, "three rows end above the bar")
	end)
end
