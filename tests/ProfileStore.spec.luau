-- DataStore safety: session locking, stale locks, retries, no overwrites.
return function(T, Loader)
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")

	local function deepCopy(v)
		return ProfileStore.deepCopy(v)
	end

	-- Fake DataStore: UpdateAsync semantics (transform may cancel by returning nil),
	-- optional failure injection.
	local function fakeStore()
		local s = { values = {}, failNext = 0, calls = 0 }
		function s:UpdateAsync(key, transform)
			self.calls += 1
			if self.failNext > 0 then
				self.failNext -= 1
				error("DataStore request was throttled")
			end
			local result = transform(deepCopy(self.values[key]))
			if result ~= nil then
				self.values[key] = deepCopy(result)
			end
			return result
		end
		return s
	end

	local clock = { t = 1000 }
	local function now()
		return clock.t
	end
	local function wait(seconds)
		clock.t += seconds
	end

	local template = { Coins = 0, Stats = { Mined = 0 }, Discovered = {} }

	local function server(store, jobId)
		return ProfileStore.new({
			Store = store,
			JobId = jobId,
			Template = template,
			Now = now,
			Wait = wait,
			LockRetries = 3,
			LockRetryDelay = 5,
			StaleLockSeconds = 600,
			CallRetries = 3,
		})
	end

	T.test("ProfileStore: new player gets template data and a lock", function()
		local store = fakeStore()
		local a = server(store, "A")
		local profile = a:load("P1")
		T.truthy(profile, "loaded")
		T.eq(profile.Data.Coins, 0)
		T.eq(store.values.P1.Lock.JobId, "A")
	end)

	T.test("ProfileStore: save persists, release unlocks, next server loads same data", function()
		local store = fakeStore()
		local a, b = server(store, "A"), server(store, "B")
		local p = a:load("P1")
		p.Data.Coins = 250
		T.truthy(a:save(p, false), "save ok")
		T.eq(store.values.P1.Data.Coins, 250)
		T.truthy(a:save(p, true), "release ok")
		T.eq(store.values.P1.Lock, nil, "lock cleared")
		local q = b:load("P1")
		T.truthy(q, "B loads after release")
		T.eq(q.Data.Coins, 250)
	end)

	T.test("ProfileStore: a live lock blocks another server", function()
		local store = fakeStore()
		local a, b = server(store, "A"), server(store, "B")
		local p = a:load("P1")
		T.truthy(p)
		local q, reason = b:load("P1")
		T.eq(q, nil, "B must not load while A holds a fresh lock")
		T.eq(reason, "locked")
		T.eq(store.values.P1.Lock.JobId, "A", "lock untouched")
	end)

	T.test("ProfileStore: a stale lock (crashed server) is taken over", function()
		local store = fakeStore()
		local a, b = server(store, "A"), server(store, "B")
		local p = a:load("P1")
		p.Data.Coins = 77
		a:save(p, false)
		clock.t += 700 -- A crashed, no refresh for 700s
		local q = b:load("P1")
		T.truthy(q, "B takes over")
		T.eq(q.Data.Coins, 77, "keeps last saved data")
		T.eq(store.values.P1.Lock.JobId, "B")
	end)

	T.test("ProfileStore: after losing the session the old server never overwrites", function()
		local store = fakeStore()
		local a, b = server(store, "A"), server(store, "B")
		local p = a:load("P1")
		clock.t += 700
		local q = b:load("P1")
		q.Data.Coins = 999
		b:save(q, false)
		p.Data.Coins = 1 -- stale server tries to write old data
		T.falsy(a:save(p, false), "A save refused")
		T.truthy(p.SessionLost, "A knows it lost the session")
		T.eq(store.values.P1.Data.Coins, 999, "B's data kept")
	end)

	T.test("ProfileStore: transient errors are retried", function()
		local store = fakeStore()
		local a = server(store, "A")
		store.failNext = 2
		local p = a:load("P1")
		T.truthy(p, "loaded after 2 failures")
		store.failNext = 2
		p.Data.Coins = 5
		T.truthy(a:save(p, false), "saved after 2 failures")
		store.failNext = 5
		T.falsy(a:save(p, false), "gives up after CallRetries")
	end)

	T.test("ProfileStore: reconcile adds new fields and keeps old values", function()
		local store = fakeStore()
		store.values.P1 = { Data = { Coins = 40, Stats = { Mined = 3 } } }
		local a = server(store, "A")
		local p = a:load("P1")
		T.eq(p.Data.Coins, 40)
		T.eq(p.Data.Stats.Mined, 3)
		T.truthy(type(p.Data.Discovered) == "table", "new field added")
	end)

	T.test("ProfileStore: released profile cannot be saved again", function()
		local store = fakeStore()
		local a = server(store, "A")
		local p = a:load("P1")
		T.truthy(a:save(p, true))
		p.Data.Coins = 12345
		T.falsy(a:save(p, false), "no writes after release")
		T.eq(store.values.P1.Data.Coins, 0)
	end)
end
