--[[
	Migrations repairs the daily / weekly quest record and the 7-day streak shapes
	(the lists themselves are rerolled by QuestLogic.refresh on load).
]]
return function(T, Loader)
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")

	T.test("quests migration: junk quest records and streaks are repaired, good ones kept", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Quests = "junk"
		data.Streak = { Day = 9, Last = 5 }
		Migrations.run(data)
		T.eq(type(data.Quests), "table")
		T.eq(data.Quests.Day, 0)
		T.eq(data.Streak.Day, 0, "day 9 is past the week")
		T.eq(data.Streak.Last, 0)
		for _, bad in { { Day = 2.5, Last = 1 }, { Day = 3, Last = 0 / 0 }, { Day = -1, Last = 4 }, "x" } do
			data.Streak = bad
			Migrations.run(data)
			T.eq(data.Streak.Day, 0)
			T.eq(data.Streak.Last, 0)
		end
		data.Streak = { Day = 4, Last = 20000 }
		data.Quests = { Day = 20000, Daily = {}, Week = 2857, Weekly = {} }
		Migrations.run(data)
		T.eq(data.Streak.Day, 4, "a good streak stays")
		T.eq(data.Streak.Last, 20000)
		T.eq(data.Quests.Day, 20000, "a good quest record stays")
	end)
end
