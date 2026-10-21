-- Daily / weekly quests and the 7-day login streak (docs/plans/DAILY_QUESTS_PLAN.md):
-- QuestLogic (UTC days / weeks, seeded stable rolls, level scaling, deltas,
-- claims, the streak), QuestService (claims once, rewards, the paid-random
-- substitutes, day 7's capsule waits for room, junk input), Net limits and
-- QuestView (every screen fits, 44 pt touch targets, exact odds, no emoji).
return function(T, Loader)
	local QuestConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.QuestConfig")
	local QuestLogic = Loader.requirePath("ReplicatedStorage.Shared.Quests.QuestLogic")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local QuestService = Loader.requirePath("ServerScriptService.Server.Services.QuestService")
	local QuestView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.QuestView")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")

	local DAY = 86400
	-- 2027-01-04 00:00 UTC is a Monday (day 20822)
	local MONDAY = 20822 * DAY
	local NOW = MONDAY + 3 * DAY + 10 * 3600 -- Thursday 10:00 UTC

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

	local function ctx(over: { [string]: any }?): any
		local c = { UserId = 4242, Now = NOW, Level = 1, Income = 0, Stats = {}, Capsules = true }
		for k, v in over or {} do
			c[k] = v
		end
		return c
	end

	---------------------------------------------------------------- QuestLogic

	T.test("Quests: UTC days and Monday weeks", function()
		T.eq(QuestLogic.day(MONDAY), 20822)
		T.eq(QuestLogic.day(MONDAY - 1), 20821, "a second before midnight is yesterday")
		T.eq(QuestLogic.week(MONDAY), QuestLogic.week(MONDAY + 6 * DAY + DAY - 1), "Monday..Sunday one week")
		T.eq(QuestLogic.week(MONDAY - 1) + 1, QuestLogic.week(MONDAY), "the week changes on Monday 00:00 UTC")
		T.eq(QuestLogic.dailyLeft(NOW), 14 * 3600)
		T.eq(QuestLogic.weeklyLeft(NOW), 3 * DAY + 14 * 3600, "Thursday 10:00 -> Monday 00:00")
		T.eq(QuestLogic.countdown(5 * 3600 + 12 * 60), "5h 12m")
		T.eq(QuestLogic.countdown(3 * DAY + 4 * 3600), "3d 4h")
		T.eq(QuestLogic.countdown(20), "1m")
	end)

	T.test("Quests: goals are round and grow with the blaster level", function()
		T.eq(QuestLogic.nice(7), 7)
		T.eq(QuestLogic.nice(25.4), 25)
		T.eq(QuestLogic.nice(48.6), 50)
		T.eq(QuestLogic.nice(172), 170)
		T.eq(QuestLogic.nice(3456), 3500)
		local mine = QuestConfig.ById.Mine
		T.eq(QuestLogic.goal(mine, 1, 0), 100)
		T.lt(QuestLogic.goal(mine, 1, 0), QuestLogic.goal(mine, 10, 0), "more ores at a stronger blaster")
		T.eq(QuestLogic.goal(QuestConfig.ById.Smelt, 1, 0), nil, "smelting needs blaster 2")
		T.eq(QuestLogic.goal(QuestConfig.ById.Podium, 5, 0), nil, "no podium quest without income")
		T.eq(QuestLogic.goal(QuestConfig.ById.Podium, 5, 10), 9000, "900 s of 10/s")
		-- every daily is ~10-20 min, every weekly ~10x a daily (same kinds)
		for _, w in QuestConfig.Weekly do
			for _, d in QuestConfig.Daily do
				if d.Stat == w.Stat and d.Amount and w.Amount then
					local ratio = w.Amount / d.Amount
					T.truthy(ratio >= 6 and ratio <= 15, `{w.Id}: ~10x the daily ({ratio})`)
				end
			end
		end
	end)

	T.test("Quests: the seeded roll is stable, has no repeats and respects the offer", function()
		local a = QuestLogic.roll("Daily", ctx({ Level = 3, Income = 50 }))
		local b = QuestLogic.roll("Daily", ctx({ Level = 3, Income = 50, Now = NOW + 3600 }))
		T.eq(#a, QuestConfig.DailyCount)
		for i = 1, #a do
			T.eq(a[i].Id, b[i].Id, "same player, same day: same quests")
			T.eq(a[i].Goal, b[i].Goal)
		end
		local seen = {}
		for _, e in a do
			T.falsy(seen[e.Id], "no quest twice")
			seen[e.Id] = true
		end
		-- across players and days the picks vary
		local different = false
		for day = 1, 20 do
			local other = QuestLogic.roll("Daily", ctx({ Level = 3, Income = 50, Now = NOW + day * DAY }))
			for i = 1, #a do
				if other[i].Id ~= a[i].Id then
					different = true
				end
			end
		end
		T.truthy(different, "other days get other quests")
		-- the offer: no capsule quests where restricted, no podium quest at 0 income, no smelting at level 1
		for day = 0, 60 do
			local list = QuestLogic.roll("Daily", ctx({ Now = NOW + day * DAY, Capsules = false }))
			for _, e in list do
				T.truthy(e.Id ~= "Capsules" and e.Id ~= "Podium" and e.Id ~= "Smelt", `day {day}: {e.Id} offered`)
			end
			local weekly = QuestLogic.roll("Weekly", ctx({ Now = NOW + day * 7 * DAY, Capsules = false }))
			T.eq(#weekly, 1)
			T.truthy(weekly[1].Id ~= "WCapsules" and weekly[1].Id ~= "WPodium", "weekly offer")
		end
	end)

	T.test("Quests: progress is a delta from when the quest was given", function()
		local record: any = { Day = 0, Daily = {}, Week = 0, Weekly = {} }
		local stats = { OresMined = 500, RocksBroken = 200, OresCleaned = 30, ItemsSold = 90, TrainTrips = 12, WheelSpins = 3 }
		T.truthy(QuestLogic.refresh(record, ctx({ Stats = stats })))
		T.falsy(QuestLogic.refresh(record, ctx({ Stats = stats, Now = NOW + 60 })), "same day: unchanged")
		for _, e in record.Daily do
			T.eq(QuestLogic.progress(e, stats), 0, e.Id .. " starts at 0")
		end
		local e = record.Daily[1]
		local stat = QuestConfig.ById[e.Id].Stat
		local more = table.clone(stats)
		more[stat] = (stats[stat] or 0) + e.Goal + 50
		T.eq(QuestLogic.progress(e, more), e.Goal, "capped at the goal")
		-- not done -> NotDone; done -> claimed once
		local _, reason = QuestLogic.claim(record, "Daily", 1, stats, record.Day)
		T.eq(reason, "NotDone")
		local entry = QuestLogic.claim(record, "Daily", 1, more, record.Day)
		T.truthy(entry and entry.Claimed)
		_, reason = QuestLogic.claim(record, "Daily", 1, more, record.Day)
		T.eq(reason, "Claimed")
		_, reason = QuestLogic.claim(record, "Daily", 2, more, record.Day - 1)
		T.eq(reason, "Stale", "yesterday's list")
		_, reason = QuestLogic.claim(record, "Daily", 9, more, nil)
		T.eq(reason, "BadQuest")
		-- a rolled-back counter moves the base down, never a negative progress
		local lower = table.clone(more)
		lower[stat] = 1
		T.truthy(QuestLogic.refresh(record, ctx({ Stats = lower, Now = NOW + 60 })))
		T.eq(record.Daily[1].Base, 1)
		-- a new UTC day: new quests, all unclaimed
		T.truthy(QuestLogic.refresh(record, ctx({ Stats = more, Now = NOW + DAY })))
		T.eq(record.Day, QuestLogic.day(NOW + DAY))
		for _, x in record.Daily do
			T.falsy(x.Claimed)
		end
		-- broken saves are rerolled
		local broken: any =
			{ Day = record.Day, Daily = { { Id = "Nope", Base = 0, Goal = 1, Claimed = false } }, Week = record.Week, Weekly = "x" }
		T.truthy(QuestLogic.refresh(broken, ctx({ Now = NOW + DAY })))
		T.eq(#broken.Daily, QuestConfig.DailyCount)
		T.eq(#broken.Weekly, 1)
	end)

	T.test("Quests: the login streak grows, waits a day, resets after a miss and wraps after 7", function()
		local s: any = { Day = 0, Last = 0 }
		T.eq(QuestLogic.streakNext(s, NOW), 1, "a new player starts at day 1")
		T.eq(QuestLogic.streakClaim(s, NOW), 1)
		T.eq(QuestLogic.streakNext(s, NOW + 3600), nil, "once per UTC day")
		T.eq(QuestLogic.streakClaim(s, NOW + 3600), nil)
		for d = 2, 7 do
			T.eq(QuestLogic.streakClaim(s, NOW + (d - 1) * DAY), d)
		end
		T.eq(QuestLogic.streakClaim(s, NOW + 7 * DAY), 1, "after day 7 it starts again")
		T.eq(QuestLogic.streakClaim(s, NOW + 8 * DAY), 2)
		T.eq(QuestLogic.streakNext(s, NOW + 10 * DAY), 1, "a missed day: back to day 1")
		T.eq(QuestLogic.streakNext({ Day = "x", Last = 0 / 0 }, NOW), 1, "junk saves are day 1")
		local today, done, can = QuestLogic.streakCells({ Day = 3, Last = QuestLogic.day(NOW) - 1 }, NOW)
		T.eq(today, 4)
		T.eq(done, 3)
		T.truthy(can)
		today, done, can = QuestLogic.streakCells({ Day = 4, Last = QuestLogic.day(NOW) }, NOW)
		T.eq(today, 4)
		T.eq(done, 4)
		T.falsy(can)
	end)

	T.test("Quests: rewards are never Robux-only, coins have a floor, the day-7 capsule is a free coin capsule", function()
		T.eq(#QuestConfig.Streak, 7)
		for _, list in { QuestConfig.Streak, { QuestConfig.DailyReward, QuestConfig.WeeklyReward } } do
			for _, r in list do
				if r.Capsule then
					local capsule = CapsuleConfig.ById[r.Capsule]
					T.truthy(capsule and capsule.Currency == "Coins", "a free coin capsule, never a Robux one")
					T.truthy(#CapsuleConfig.odds(r.Capsule, false) > 0, "its odds can be shown")
				end
				if r.Boost then
					T.truthy(BoostConfig.Kinds[r.Boost] ~= nil, r.Boost)
				end
			end
		end
		T.truthy(QuestConfig.Streak[7].Capsule ~= nil, "day 7: a golem capsule")
		T.eq(QuestLogic.coins(600, 0, 1), QuestConfig.MinCoins, "a new player still gets coins")
		T.eq(QuestLogic.coins(600, 100, 1), 60000, "10 minutes of income")
		T.lt(QuestLogic.coinFloor(600, 2), QuestLogic.coinFloor(600, 6), "the floor grows with the blaster")
		T.eq(QuestLogic.coins(600, 0 / 0, 3), QuestLogic.coinFloor(600, 3), "NaN income: the floor")
	end)

	---------------------------------------------------------------- QuestService

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "Quester" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function withQuests(name: string, body: (any) -> ())
		T.test(name, function()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			local w: any = { replies = {}, income = 0, restricted = false, now = NOW, grants = {} }
			w.player = fakePlayer(777)
			w.data = deepCopy(DataTemplate)
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(DataService, "changed", function()
				w.changed = (w.changed or 0) + 1
			end)
			patch(Net, "fire", function(event: string, p: any, a: any, b: any)
				table.insert(w.replies, { Event = event, Player = p, A = a, B = b })
			end)
			patch(Policy, "paidRandomRestricted", function()
				return w.restricted
			end)
			patch(Policy, "cached", function()
				return { PaidRandomRestricted = w.restricted, PaidTradingAllowed = false, Known = true }
			end)
			patch(PodiumService, "incomeOf", function()
				return w.income
			end)
			QuestService._test.reset()
			QuestService._test.setClock(function()
				return w.now
			end)
			QuestService._test.setCapsules({
				grantFree = function(_p: any, capsuleId: string)
					table.insert(w.grants, capsuleId)
					local entry = GolemConfig.add(w.data.Golems, "QuartzSprite", false, false)
					return { Capsule = capsuleId, Count = 1, Golems = { { Id = entry.Id, Kind = entry.Kind } }, Free = true }
				end,
			})
			Bonuses._test.reset()
			w.act = function(action: string, payload: any): (any, any)
				local before = #w.replies
				QuestService._test.action(w.player, action, payload)
				local reward, result
				for i = before + 1, #w.replies do
					local r = w.replies[i]
					if r.Event == "QuestReward" then
						reward = r.A
					elseif r.Event == "ActionResult" then
						result = r.A
					end
				end
				return reward, result
			end
			local ok, err = pcall(body, w)
			QuestService._test.reset()
			Bonuses._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	withQuests("QuestService: a finished daily pays once, an unfinished one is refused", function(w)
		QuestService.ensure(w.player, w.data)
		local q = w.data.Quests
		T.eq(#q.Daily, QuestConfig.DailyCount)
		local reward, result = w.act("Claim", { Kind = "Daily", Index = 1, Day = q.Day })
		T.eq(reward, nil)
		T.eq(result.Reason, "NotDone")
		local entry = q.Daily[1]
		local stat = QuestConfig.ById[entry.Id].Stat
		w.data.Stats[stat] = (w.data.Stats[stat] or 0) + entry.Goal
		local coins, shards = w.data.Coins, w.data.Shards
		reward, result = w.act("Claim", { Kind = "Daily", Index = 1, Day = q.Day })
		T.truthy(result.Ok)
		T.eq(reward.Kind, "Daily")
		T.eq(w.data.Coins - coins, QuestConfig.MinCoins, "the floor at income 0")
		T.eq(w.data.Shards - shards, QuestConfig.DailyReward.Shards)
		T.truthy(entry.Claimed)
		reward, result = w.act("Claim", { Kind = "Daily", Index = 1, Day = q.Day })
		T.eq(reward, nil)
		T.eq(result.Reason, "Claimed", "never twice")
	end)

	withQuests("QuestService: the weekly gives Triple Lucky, or coins where capsules are restricted", function(w)
		w.income = 10
		QuestService.ensure(w.player, w.data)
		local entry = w.data.Quests.Weekly[1]
		local stat = QuestConfig.ById[entry.Id].Stat
		w.data.Stats[stat] = (w.data.Stats[stat] or 0) + entry.Goal
		local reward = w.act("Claim", { Kind = "Weekly", Week = w.data.Quests.Week })
		T.eq(reward.Boost, "TripleLucky")
		T.eq(reward.Seconds, QuestConfig.WeeklyReward.BoostSeconds)
		T.eq(BoostConfig.untilOf(w.data.Boosts, "TripleLucky"), NOW + QuestConfig.WeeklyReward.BoostSeconds)
		T.eq(reward.Coins, 36000, "an hour of 10/s")
		-- next week, a restricted player: coins instead of the boost
		w.now = NOW + 7 * DAY
		w.restricted = true
		local restrictedAll = CapsuleConfig.allRestricted(true)
		QuestService.ensure(w.player, w.data)
		entry = w.data.Quests.Weekly[1]
		stat = QuestConfig.ById[entry.Id].Stat
		w.data.Stats[stat] = (w.data.Stats[stat] or 0) + entry.Goal
		reward = w.act("Claim", { Kind = "Weekly" })
		if restrictedAll then
			T.eq(reward.Boost, nil)
			T.eq(reward.Coins, 36000 + QuestConfig.LuckyFallbackSeconds * 10)
		else
			T.eq(reward.Boost, "TripleLucky")
		end
	end)

	withQuests("QuestService: the streak pays day by day, day 7 opens a free capsule or waits for room", function(w)
		local reward, result = w.act("Streak")
		T.eq(reward.Day, 1)
		T.truthy(reward.Coins and reward.Coins > 0)
		reward, result = w.act("Streak")
		T.eq(result.Reason, "Tomorrow", "once a day")
		for d = 2, 6 do
			w.now = NOW + (d - 1) * DAY
			reward = w.act("Streak")
			T.eq(reward.Day, d)
		end
		-- day 7 with a full golem inventory: refused, the day stays claimable
		w.now = NOW + 6 * DAY
		for _ = 1, GolemConfig.room(w.data.Golems) do
			GolemConfig.add(w.data.Golems, "PebbleGolem", false, false)
		end
		local coins = w.data.Coins
		reward, result = w.act("Streak")
		T.eq(reward, nil)
		T.eq(result.Reason, "InventoryFull")
		T.eq(w.data.Coins, coins, "nothing paid instead")
		T.eq(w.data.Streak.Day, 6)
		T.eq(#w.grants, 0)
		-- room made: the capsule opens through the free grant
		table.remove(w.data.Golems.Owned, 1)
		reward = w.act("Streak")
		T.eq(reward.Day, 7)
		T.eq(w.grants[1], "Crystal")
		T.truthy(reward.Golem ~= nil)
		T.eq(reward.Shards, 50)
		w.now = NOW + 7 * DAY
		T.eq(w.act("Streak").Day, 1, "a new week of days")
	end)

	withQuests("QuestService: junk input is dropped, the provider sends the view", function(w)
		for _, payload in
			{
				nil,
				"x",
				{ Kind = "Daily", Index = 0 },
				{ Kind = "Daily", Index = 1.5 },
				{ Kind = "Monthly" },
				{ Kind = "Daily", Index = 0 / 0 },
			}
		do
			local before = #w.replies
			QuestService._test.action(w.player, "Claim", payload)
			T.eq(#w.replies, before, "dropped")
		end
		QuestService._test.action(w.player, "Nope", {})
		local snapshot: any = {}
		QuestService._test.provide(w.player, w.data, snapshot)
		local view = snapshot.Quests
		T.eq(#view.Daily, QuestConfig.DailyCount)
		T.eq(#view.Weekly, 1)
		T.eq(#view.Streak.Days, 7)
		T.truthy(view.Streak.CanClaim)
		T.eq(QuestLogic.claimable(view), 1, "the streak day")
		T.eq(view.DailyEnds, NOW + QuestLogic.dailyLeft(NOW))
	end)

	T.test("Quests: the Net remote is rate limited, the save fields exist", function()
		local limit = Net.Events.QuestAction
		T.truthy(limit and limit.Rate <= 2 and limit.Burst <= 4)
		T.eq(Net.Events.QuestReward, false)
		T.eq(type(DataTemplate.Quests), "table")
		T.eq(DataTemplate.Streak.Day, 0)
		local found = false
		for _, entry in SideMenuView.Entries do
			found = found or entry.Id == "Quests"
		end
		T.truthy(found, "the side menu's QUESTS tile")
		T.truthy(table.find(MenuPanels.Names, "QuestController") ~= nil, "one panel at a time")
	end)

	---------------------------------------------------------------- QuestView

	local function sampleView(): any
		local record: any = {}
		local stats =
			{ OresMined = 0, RocksBroken = 0, OresCleaned = 0, ItemsSold = 0, TrainTrips = 0, PodiumEarned = 0, CapsulesOpened = 0 }
		QuestLogic.refresh(record, ctx({ Level = 4, Income = 1840, Stats = stats }))
		local more = table.clone(stats)
		local first = record.Daily[1]
		more[QuestConfig.ById[first.Id].Stat] = first.Goal
		return QuestLogic.view(record, { Day = 2, Last = QuestLogic.day(NOW) - 1 }, more, NOW, 4, 1840, Format.money)
	end

	local function pt(size: number, fit: number): number
		return size * fit * 0.62
	end

	T.test("QuestView: every screen fits and phone buttons are 44 pt", function()
		local screens = {
			{ Name = "phone 568x320", Compact = true, W = 568 / 0.62, H = (320 - 58) / 0.62 },
			{ Name = "phone 844x390", Compact = true, W = 844 / 0.62, H = (390 - 58) / 0.62 },
			{ Name = "PC 1280x720", Compact = false, W = 1280, H = 720 - 36 },
			{ Name = "PC 1920x1080", Compact = false, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
		}
		for _, s in screens do
			local refs = QuestView.build()
			QuestView.layout(refs, s.W, s.H, s.Compact)
			QuestView.setView(refs, sampleView(), NOW)
			local size = refs.Window.Root.Size
			T.truthy(size.X.Offset * refs.Fit <= s.W and size.Y.Offset * refs.Fit <= s.H, `{s.Name}: the window fits`)
			local popup = QuestView.buildPopup()
			QuestView.layoutPopup(popup, s.W, s.H, s.Compact)
			QuestView.setPopup(popup, sampleView())
			local psize = popup.Window.Root.Size
			T.truthy(psize.X.Offset * popup.Fit <= s.W and psize.Y.Offset * popup.Fit <= s.H, `{s.Name}: the popup fits`)
			-- nothing overlaps: ODDS above the day cells, every CLAIM inside its card
			local odds = refs.OddsButton
			T.le(odds.Position.Y.Offset + odds.Size.Y.Offset, refs.Lower.Position.Y.Offset, `{s.Name}: ODDS above the cells`)
			for _, q in refs.Quests do
				T.le(q.Claim.Size.Y.Offset, q.Card.Size.Y.Offset - 8, `{s.Name}: CLAIM inside its card`)
			end
			T.le(refs.Lower.Position.Y.Offset + refs.Lower.Size.Y.Offset, refs.Scroller.CanvasSize.Y.Offset, `{s.Name}: the list scrolls to the end`)
			if s.Compact then
				for _, q in refs.Quests do
					T.truthy(pt(q.Claim.Size.Y.Offset, refs.Fit) >= 44 - 0.01, `{s.Name}: CLAIM >= 44 pt`)
				end
				T.truthy(pt(refs.Window.Close.Size.Y.Offset, refs.Fit) >= 44 - 0.01, `{s.Name}: X >= 44 pt`)
				T.truthy(pt(refs.OddsButton.Size.Y.Offset, refs.Fit) >= 44 - 0.01, `{s.Name}: ODDS >= 44 pt`)
				T.truthy(pt(popup.Claim.Size.Y.Offset, popup.Fit) >= 44 - 0.01, `{s.Name}: popup CLAIM >= 44 pt`)
				T.truthy(pt(popup.Window.Close.Size.Y.Offset, popup.Fit) >= 44 - 0.01, `{s.Name}: popup X >= 44 pt`)
				local cell = popup.Days[1].Button.Size
				T.truthy(pt(cell.Y.Offset, popup.Fit) >= 44, `{s.Name}: day cells >= 44 pt`)
			end
		end
	end)

	T.test("QuestView: the view draws claimable / claimed states and today's cell", function()
		local refs = QuestView.build()
		local v = sampleView()
		QuestView.setView(refs, v, NOW)
		local first = refs.Quests[1]
		T.truthy(first.Claim.Active and first.Claim.Selectable, "a finished quest's CLAIM")
		T.falsy(refs.Quests[2].Claim.Active, "an unfinished one can't be pressed")
		T.truthy(refs.Days[3].ClaimTag.Visible, "day 3 waits")
		T.truthy(refs.Days[1].Done.Visible and refs.Days[2].Done.Visible)
		T.falsy(refs.Days[4].Done.Visible)
		T.truthy(refs.DailyTimer.Text:find("14h", 1, true) ~= nil, refs.DailyTimer.Text)
		v.Daily[1].Claimed = true
		QuestView.setView(refs, v, NOW)
		T.truthy(first.Done.Visible)
		T.falsy(first.Claim.Visible)
		T.eq(
			QuestView.rewardText({ Coins = 1500, Shards = 10, Boost = "TripleLucky", BoostSeconds = 900 }),
			"+$1.5K  +10 Shards  +Triple Lucky 15m"
		)
	end)

	T.test("QuestView: the day-7 odds are exact and add up to 100%", function()
		local text = QuestView.oddsLines(false)
		local total = 0
		for _, line in CapsuleConfig.odds("Crystal", false) do
			total += line.Chance
			local golem = GolemConfig.ById[line.Golem]
			T.truthy(text:find(golem.Name, 1, true) ~= nil, golem.Name .. " listed")
		end
		T.near(total, 1, 1e-6)
		T.truthy(QuestView.oddsLines(true):find("Triple Lucky", 1, true) ~= nil)
	end)

	T.test("Quests: text only, no emoji anywhere (owner)", function()
		local function ascii(text: string, where: string)
			for _, code in utf8.codes(text) do
				T.truthy(code < 0x2000, `{where}: no emoji ({text})`)
			end
		end
		for _, list in { QuestConfig.Daily, QuestConfig.Weekly } do
			for _, def in list do
				ascii(def.Text .. def.Short, def.Id)
			end
		end
		for _, d in QuestConfig.Streak do
			ascii(d.Label, "day " .. d.Day)
		end
		for _, text in QuestConfig.Reasons do
			ascii(text, "reason")
		end
		local refs = QuestView.build()
		QuestView.setView(refs, sampleView(), NOW)
		for _, node in refs.Gui:GetDescendants() do
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				ascii(node.Text, node.Name)
			end
		end
	end)
end
