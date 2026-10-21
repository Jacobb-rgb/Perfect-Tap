--[[
	Migrations repairs the player LEVEL record on every load (LevelConfig.sanitize),
	also on a save that is already at the latest version.
]]
return function(T, Loader)
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local LevelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LevelConfig")

	local function fresh(): any
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = Migrations.Latest
		return data
	end

	T.test("level migration: the template record is kept as it is", function()
		local data = fresh()
		Migrations.run(data)
		T.eq(data.Level.Level, 1)
		T.eq(data.Level.Xp, 0)
		T.eq(data.Level.Ready, false)
		T.eq(data.Version, Migrations.Latest)
	end)

	T.test("level migration: NaN, negative, fractional and huge levels on a latest save", function()
		for _, case in
			{
				{ In = 0 / 0, Out = 1 },
				{ In = -7, Out = 1 },
				{ In = 12.9, Out = 12 },
				{ In = math.huge, Out = 1 },
				{ In = 1e9, Out = LevelConfig.MaxLevel },
				{ In = "12", Out = 1 },
			}
		do
			local data = fresh()
			data.Level = { Level = case.In, Xp = 10, Seen = {}, Ready = true }
			Migrations.run(data)
			T.eq(data.Level.Level, case.Out, "level " .. tostring(case.In))
		end
	end)

	T.test("level migration: XP stays in 0..need, fractions kept", function()
		local data = fresh()
		data.Level = { Level = 3, Xp = 12.5, Seen = {}, Ready = true }
		Migrations.run(data)
		T.eq(data.Level.Xp, 12.5, "play time gives fractions")
		data.Level.Xp = -4
		Migrations.run(data)
		T.eq(data.Level.Xp, 0)
		data.Level.Xp = 0 / 0
		Migrations.run(data)
		T.eq(data.Level.Xp, 0)
		data.Level.Xp = 1e12
		Migrations.run(data)
		T.eq(data.Level.Xp, LevelConfig.need(3))
	end)

	T.test("level migration: junk records and Seen keys", function()
		local data = fresh()
		data.Level = "junk"
		Migrations.run(data)
		T.eq(type(data.Level), "table")
		T.eq(data.Level.Level, 1)
		T.eq(data.Level.Ready, false, "a rebuilt record backfills on its first look")
		data.Level =
			{ Level = 5, Xp = 1, Seen = { RocksBroken = 0 / 0, OresMined = -3, Bogus = 4, [1] = 2, PlaySeconds = 90.5 }, Ready = true }
		Migrations.run(data)
		local seen = data.Level.Seen
		T.eq(seen.RocksBroken, 0)
		T.eq(seen.OresMined, 0)
		T.eq(seen.Bogus, nil)
		T.eq(seen[1], nil)
		T.eq(seen.PlaySeconds, 90.5)
		data.Level.Seen = "x"
		Migrations.run(data)
		T.eq(type(data.Level.Seen), "table")
	end)
end
