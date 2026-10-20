--[[
	Step 8 badges and analytics under Lune, with a fake badge API and a fake
	analytics API: BadgeConfig is sane and data-driven, BadgeService awards
	only earned badges with real ids, asks Roblox once per badge per session,
	retries, caches in data.Badges, gives up on a broken badge and throttles;
	AnalyticsService logs the funnel once per step (step 1 only for new
	saves), blaster levels, discoveries, sums the coin flow per source and
	sends no free text.
]]
return function(T, Loader)
	local BadgeConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BadgeConfig")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local BadgeService = Loader.requirePath("ServerScriptService.Server.Services.BadgeService")
	local AnalyticsService = Loader.requirePath("ServerScriptService.Server.Services.AnalyticsService")

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

	-- a world: one player, its data, a fake clock, patched DataService
	local function world(): any
		local w: any = { now = 100, changed = 0 }
		w.player = { UserId = 777, Name = "Tester", Parent = true }
		w.data = deepCopy(DataTemplate)
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
		patch(EconomyService, "balance", function()
			return w.data.Coins
		end)
		w.restore = function()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	-- a test badge list with real ids (the shipped ids are 0 until the owner creates them)
	local function withIds(fn: () -> ())
		local old = {}
		for i, badge in BadgeConfig.List do
			old[i] = badge.Id
			badge.Id = 1000 + i
		end
		local ok, err = pcall(fn)
		for i, badge in BadgeConfig.List do
			badge.Id = old[i]
		end
		if not ok then
			error(err, 0)
		end
	end

	T.test("badges: config is sane and only rewards play", function()
		T.truthy(#BadgeConfig.List >= 8, "at least 8 badges")
		for _, badge in BadgeConfig.List do
			T.truthy(type(badge.Id) == "number" and badge.Id >= 0, badge.Key .. " id")
			T.truthy(#badge.Name > 0 and #badge.Description > 0, badge.Key .. " name and description")
			local lower = string.lower(badge.Key .. badge.Name .. badge.Description)
			for _, banned in { "like", "favorite", "favourite", "friend", "group", "visit", "welcome", "join" } do
				T.falsy(string.find(lower, banned, 1, true), `{badge.Key} is not a {banned} reward`)
			end
			-- a fresh save earns nothing
			T.falsy(badge.Check(deepCopy(DataTemplate)), badge.Key .. " is not earned by a new save")
		end
		-- id 0 = skipped even when earned
		local data = deepCopy(DataTemplate)
		data.Stats.OresMined = 5
		T.eq(#BadgeConfig.due(data), 0, "no due badges while every id is 0")
	end)

	T.test("badges: conditions read the save data", function()
		withIds(function()
			local data = deepCopy(DataTemplate)
			data.Stats.OresMined = 1
			data.Stats.OresCleaned = 1
			local due = BadgeConfig.due(data)
			T.truthy(table.find(due, "FirstOre") and table.find(due, "FirstClean"), "first ore and first clean")
			T.falsy(table.find(due, "FirstLegendary"), "no legendary yet")
			for _, ore in OreData.List do
				if ore.Rarity == "Legendary" then
					data.Discovered[ore.Id] = true
					break
				end
			end
			T.truthy(table.find(BadgeConfig.due(data), "FirstLegendary"), "a discovered legendary ore")
			data.Badges.FirstOre = true
			T.falsy(table.find(BadgeConfig.due(data), "FirstOre"), "cached badges are not due")
			data.TotalEarned = 2e6
			data.BlasterLevel = 10
			local more = BadgeConfig.due(data)
			T.truthy(table.find(more, "Tycoon") and table.find(more, "MaxBlaster"), "tycoon and max blaster")
		end)
	end)

	T.test("badges: awards once, asks Roblox once, retries, gives up on a broken badge", function()
		withIds(function()
			local w = world()
			BadgeService._test.reset()
			local calls = { has = {}, award = {} }
			local failAward: { [number]: boolean } = {}
			local flaky = 1 -- the first award call errors once
			BadgeService._test.setApi({
				has = function(_userId, id)
					calls.has[id] = (calls.has[id] or 0) + 1
					return id == BadgeConfig.ByKey.FirstClean.Id -- owned from an older save
				end,
				award = function(_userId, id)
					calls.award[id] = (calls.award[id] or 0) + 1
					if flaky > 0 then
						flaky -= 1
						error("HTTP 503")
					end
					if failAward[id] then
						error("badge disabled")
					end
					return true
				end,
				wait = function() end,
				now = function()
					return w.now
				end,
				spawn = function(fn)
					fn()
				end,
				delay = function(_s, fn)
					w.delayed = fn
				end,
			})
			local ok, err = pcall(function()
				w.data.Stats.OresMined = 1
				w.data.Stats.OresCleaned = 1
				w.data.Stats.FlawlessCleans = 1
				failAward[BadgeConfig.ByKey.FirstFlawless.Id] = true
				BadgeService.check(w.player)
				local ore, clean, flaw = BadgeConfig.ByKey.FirstOre, BadgeConfig.ByKey.FirstClean, BadgeConfig.ByKey.FirstFlawless
				T.truthy(w.data.Badges.FirstOre, "first ore awarded (after a retry)")
				T.truthy(w.data.Badges.FirstClean, "first clean found owned and cached")
				T.eq(calls.award[clean.Id], nil, "an owned badge is not awarded again")
				T.falsy(w.data.Badges.FirstFlawless, "a broken badge is not cached")
				T.truthy(w.changed >= 1, "DataService.changed after awarding")
				-- again: nothing is asked twice, the broken badge is tried once more, then left alone
				BadgeService.check(w.player)
				BadgeService.check(w.player)
				T.eq(calls.has[ore.Id], 1, "UserHasBadgeAsync once per badge per session")
				T.eq(calls.has[flaw.Id], 1, "even for the broken badge")
				local tries = calls.award[flaw.Id]
				BadgeService.check(w.player)
				T.eq(calls.award[flaw.Id], tries, "a badge that failed twice is left alone")
				T.eq(tries, BadgeService.MaxFailures * BadgeService.Retries, "retries per check")
				-- throttle: a request right after a check waits
				w.delayed = nil
				BadgeService.request(w.player)
				T.truthy(w.delayed, "a request inside the throttle is delayed")
				BadgeService.request(w.player)
			end)
			w.restore()
			BadgeService._test.reset()
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("analytics: funnel once per step, progression, coin flow, no free text", function()
		local w = world()
		AnalyticsService._test.reset()
		local log = { funnel = {}, progression = {}, custom = {}, economy = {} }
		AnalyticsService._test.setApi({
			funnel = function(_p, step, name)
				table.insert(log.funnel, { step, name })
			end,
			progression = function(_p, path, level)
				table.insert(log.progression, { path, level })
			end,
			custom = function(_p, name, value)
				table.insert(log.custom, { name, value })
			end,
			economy = function(_p, source, amount, balance, kind, sku)
				table.insert(log.economy, { source, amount, balance, kind, sku })
			end,
			now = function()
				return w.now
			end,
		})
		local ok, err = pcall(function()
			-- a new save logs step 1 at once
			AnalyticsService._test.begin(w.player, w.data)
			T.eq(#log.funnel, 1, "joined")
			T.eq(log.funnel[1][1], 1, "step 1")
			w.data.Stats.OresMined = 1
			AnalyticsService.observe(w.player)
			AnalyticsService.observe(w.player)
			T.eq(#log.funnel, 2, "first ore once")
			T.eq(log.funnel[2][2], "FirstOre", "named step")
			w.data.BlasterLevel = 3
			AnalyticsService.observe(w.player)
			T.eq(#log.progression, 2, "blaster levels 2 and 3")
			T.eq(log.progression[2][2], 3, "level 3")
			local s = AnalyticsService._test.session(w.player)
			AnalyticsService._test.add(s.earned, AnalyticsService.label("Podium"), 5)
			AnalyticsService._test.add(s.earned, AnalyticsService.label("Podium"), 7)
			AnalyticsService._test.add(s.spent, AnalyticsService.label("Machine: Crusher!"), 50)
			AnalyticsService._test.add(s.earned, "Bad", 0 / 0)
			w.data.Coins = 1234
			AnalyticsService.flush(w.player)
			T.eq(#log.economy, 2, "one event per source")
			local earned, spent
			for _, e in log.economy do
				if e[1] then
					earned = e
				else
					spent = e
				end
			end
			T.eq(earned[2], 12, "podium income summed")
			T.eq(earned[5], "Podium", "source sku")
			T.eq(spent[5], "MachineCrusher", "the reason cut to [A-Za-z0-9_]")
			T.eq(earned[3], 1234, "ending balance")
			T.eq(AnalyticsService.label(string.rep("x", 50)), string.rep("x", 32), "at most 32 characters")
			-- a returning save never logs its old steps
			AnalyticsService._test.reset()
			table.clear(log.funnel)
			w.data.Stats.PlaySeconds = 5000
			AnalyticsService._test.begin(w.player, w.data)
			AnalyticsService.observe(w.player)
			T.eq(#log.funnel, 0, "a returning player logs no old steps")
			-- throttle
			local s2 = AnalyticsService._test.session(w.player)
			for i = 1, AnalyticsService.MaxPerMinute + 10 do
				AnalyticsService._test.add(s2.earned, "S" .. i, 1)
			end
			table.clear(log.economy)
			AnalyticsService.flush(w.player)
			T.eq(#log.economy, AnalyticsService.MaxPerMinute, "at most MaxPerMinute events a minute")
		end)
		w.restore()
		AnalyticsService._test.reset()
		if not ok then
			error(err, 0)
		end
	end)
end
