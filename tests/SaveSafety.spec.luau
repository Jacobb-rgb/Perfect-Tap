-- Save-data safety (docs/SAVE_AUDIT.md): every scenario the audit found or
-- reproduced, and every scenario of its adversarial review (R1-R4, A, C,
-- the autosave schedule), against the real ProfileStore / DataService with
-- a fake DataStore that encodes like Roblox (it rejects what a real
-- DataStore rejects: userdata, functions, mixed or gapped tables,
-- non-string keys, invalid UTF-8, loops; like Roblox it takes NaN / inf;
-- values are copied through JSON). Options: delay (UpdateAsync yields
-- first, like the real network read), hang (requests wait until it is
-- cleared), rerun (the transform runs twice, as Roblox may).
--   #3  a late save never writes over a newer session (SessionId lock, nil lock = lost)
--   #6  a malformed stored value is never replaced with the template
--   #2  an unstorable value is repaired or dropped at its path, the rest saves
--   #4  a failing migration releases only its own lock, data untouched
--   #5  crashed-server locks expire after StaleLockSeconds (180 s in the game)
--   #1  a save from a newer version is refused untouched (no lock taken)
--   #7  Studio uses its own store; test players (UserId <= 0) never touch it
--   #8  the purchase-id trim never drops ids younger than 30 days
--   #9 / #13  shutdown waits for every final save (left-while-loading, yielding callbacks)
--   #10 shutdown saves are quick even when the store keeps failing
return function(T, Loader)
	local serde = require("@lune/serde")
	local task = require("@lune/task")
	local roblox = require("@lune/roblox") :: any
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")

	---------------------------------------------------------------- a Roblox-like store

	-- Throws like a DataStore write would for values it can't store.
	local function checkStorable(value: any, path: string, ancestors: { [any]: boolean })
		local kind = type(value)
		if kind == "number" then
			-- Roblox's engine DataStores take NaN / inf (they come back as NaN / inf)
		elseif kind == "string" then
			if utf8.len(value) == nil then
				error(`104: invalid UTF-8 at {path}`)
			end
		elseif kind == "table" then
			if ancestors[value] then
				error(`104: cyclic table at {path}`)
			end
			ancestors[value] = true
			local numbers, strings, maxIndex = 0, 0, 0
			for k, v in value do
				if type(k) == "number" then
					numbers += 1
					if k ~= math.floor(k) or k < 1 then
						error(`104: Cannot convert mixed or non-array tables: keys must be strings ({path})`)
					end
					maxIndex = math.max(maxIndex, k)
				elseif type(k) == "string" then
					strings += 1
					if utf8.len(k) == nil then
						error(`104: invalid UTF-8 key at {path}`)
					end
				else
					error(`104: Cannot convert mixed or non-array tables: keys must be strings ({path})`)
				end
				checkStorable(v, `{path}.{tostring(k)}`, ancestors)
			end
			if numbers > 0 and (strings > 0 or maxIndex ~= numbers) then
				error(`104: Cannot convert mixed or non-array tables: keys must be strings ({path})`)
			end
			ancestors[value] = nil
		elseif kind ~= "boolean" and kind ~= "nil" then
			error(`104: Cannot store {typeof(value)} in data store ({path})`)
		end
	end

	local clock = { t = 50000 }

	local function robloxStore()
		local s = {
			values = {},
			updated = {}, -- key -> ms of the last write (DataStoreKeyInfo.UpdatedTime, Roblox's clock)
			writes = 0,
			failAll = false,
			delay = 0,
			after = 0,
			hang = false,
			rerun = false,
			keyInfo = false,
			calls = 0,
		}
		function s:UpdateAsync(key: string, transform: (any) -> any): any
			self.calls += 1
			if self.delay > 0 then
				task.wait(self.delay)
			end
			while self.hang do
				task.wait(0.01)
			end
			if self.failAll then
				error("502: API Services rejected request")
			end
			local old = self.values[key]
			local info = if self.keyInfo and self.updated[key] then { UpdatedTime = self.updated[key] } else nil
			if self.rerun then
				-- Roblox may call the transform again (a conflicting write): the first result is thrown away
				transform(if old ~= nil then serde.decode("json", old) else nil, info)
			end
			local result = transform(if old ~= nil then serde.decode("json", old) else nil, info)
			if result ~= nil then
				checkStorable(result, key, {})
				self.values[key] = serde.encode("json", result)
				self.updated[key] = clock.t * 1000
				self.writes += 1
			end
			if self.after > 0 then
				task.wait(self.after) -- the write's round trip: the caller hears back later
			end
			return result
		end
		function s:get(key: string): any
			local raw = self.values[key]
			return if raw ~= nil then serde.decode("json", raw) else nil
		end
		function s:put(key: string, value: any)
			self.values[key] = serde.encode("json", value)
		end
		return s
	end

	local function now(): number
		return clock.t
	end
	local function fakeWait(seconds: number)
		clock.t += seconds
	end

	local template = { Version = 3, Coins = 0, Stats = { Mined = 0 }, Storage = {}, Purchases = {} }

	local function server(store: any, jobId: string, extra: { [string]: any }?): any
		local options: { [string]: any } = {
			Store = store,
			JobId = jobId,
			Template = template,
			Now = now,
			Wait = fakeWait,
			LockRetries = 3,
			LockRetryDelay = 5,
			StaleLockSeconds = 180,
			CallRetries = 3,
			LatestVersion = 3,
		}
		for k, v in extra or {} do
			options[k] = v
		end
		return ProfileStore.new(options)
	end

	---------------------------------------------------------------- #3 / #6: the lock

	T.test("SaveSafety #3: a late save after the lock was cleared by a newer session never writes", function()
		local store = robloxStore()
		local a, b = server(store, "A"), server(store, "B")
		local pa = a:load("P")
		pa.Data.Coins = 10
		T.truthy(a:save(pa, false), "A saves while it owns the session")
		clock.t += 200 -- A is stuck (DataStore outage): its lock goes stale
		local pb = b:load("P")
		T.truthy(pb, "B takes the stale lock over")
		pb.Data.Coins = 500
		T.truthy(b:save(pb, true), "B plays and leaves: the lock is cleared")
		T.eq(store:get("P").Lock, nil, "nil lock after B's release")
		pa.Data.Coins = 11
		T.falsy(a:save(pa, true), "A's late final save is refused")
		T.truthy(pa.SessionLost, "A knows it lost the session")
		T.eq(store:get("P").Data.Coins, 500, "B's progress stays")
	end)

	T.test("SaveSafety #3: two sessions on the same server are told apart", function()
		local store = robloxStore()
		local a = server(store, "A")
		local first = a:load("P")
		first.Data.Coins = 7
		-- while the first session is live here, a second load of the key waits like for any other server
		local blocked, reason = a:load("P")
		T.eq(blocked, nil, "a live session on this server blocks a second load")
		T.eq(reason, "locked")
		-- its final save gave up (DataService forgets it): the rejoin may take the lock at once
		a:forget(first)
		local second = a:load("P")
		T.truthy(second, "the same server loads again at once")
		T.truthy(first.SessionId ~= second.SessionId, "each load has its own SessionId")
		second.Data.Coins = 70
		T.truthy(a:save(second, false), "the new session saves")
		first.Data.Coins = 8
		T.falsy(a:save(first, true), "the old session can't write any more")
		T.eq(store:get("P").Data.Coins, 70, "the new session's data stays")
	end)

	T.test("SaveSafety #3: a stuck save never writes after another server took over", function()
		local store = robloxStore()
		local a, b = server(store, "A"), server(store, "B")
		local pa = a:load("P")
		clock.t += 200
		local pb = b:load("P")
		pb.Data.Coins = 99
		b:save(pb, false)
		pa.Data.Coins = 1
		T.falsy(a:save(pa, false), "refused: another session's lock")
		T.eq(store:get("P").Data.Coins, 99)
		T.eq(store:get("P").Lock.SessionId, pb.SessionId, "B's lock untouched")
	end)

	T.test("SaveSafety #6: a malformed stored value is never replaced with the template", function()
		for _, bad in { "garbage", { Data = 5 }, { Data = "oops" }, {}, { Lock = { JobId = "X", Time = 1 } }, 42 } do
			local store = robloxStore()
			store:put("P", bad)
			local before = store.values.P
			local a = server(store, "A")
			local profile, reason = a:load("P")
			T.eq(profile, nil, "refused: " .. before)
			T.eq(reason, "malformed", "the reason")
			T.eq(store.values.P, before, "the stored value is untouched: " .. before)
		end
		-- a new player (nothing stored) still gets the template
		local store = robloxStore()
		local profile = server(store, "A"):load("New")
		T.truthy(profile, "new player")
		T.eq(profile.Data.Coins, 0)
	end)

	---------------------------------------------------------------- #2: storable

	T.test("SaveSafety #2: storable() names the first bad path; good saves pass", function()
		local good = { Coins = 5, Name = "Forge", List = { 1, 2, 3 }, Map = { a = true }, Empty = {} }
		local ok, problems = ProfileStore.storable(good)
		T.truthy(ok, "a clean save is storable")
		T.eq(#problems, 0)
		local bad = { Coins = 0 / 0, Stats = { Mined = math.huge } }
		local ok2, problems2 = ProfileStore.storable(bad)
		T.falsy(ok2, "NaN is reported (Roblox stores it, but no reader can use it)")
		T.truthy(#problems2 >= 2, "both bad numbers reported")
		T.truthy(string.find(problems2[1].Path .. problems2[2].Path, "Coins", 1, true) ~= nil, "the path names the field")
		T.eq(bad.Coins ~= bad.Coins, true, "storable() itself changes nothing")
	end)

	T.test("SaveSafety #2: one bad value no longer blocks the save; it is repaired at its path", function()
		local store = robloxStore()
		local logged = {}
		local a = server(store, "A", {
			OnRepair = function(key: string, problems: { any })
				table.insert(logged, { Key = key, Problems = problems })
			end,
		})
		local p = a:load("P")
		p.Data.Coins = 1234
		p.Data.Stats.Mined = 0 / 0 -- NaN
		p.Data.Stats.Speed = -math.huge
		p.Data.Storage = { { K = "Clean", O = "Gold" }, { K = "Clean", O = "Jade" } }
		p.Data.Storage[4] = { K = "Raw", O = "Copper" } -- a gap at [3]
		p.Data.Spot = roblox.Vector3.new(1, 2, 3) -- userdata
		p.Data.Fn = function() end
		p.Data.Mixed = { 10, 20, Name = "x" }
		p.Data.Keys = { [true] = 1, ok = 2 }
		p.Data.Text = "bad \255 text"
		local cyclic = { Name = "loop" }
		cyclic.Self = cyclic
		p.Data.Cycle = cyclic
		T.truthy(a:save(p, false), "the save goes through")
		local saved = store:get("P").Data
		T.eq(saved.Coins, 1234, "the good fields are saved")
		T.eq(saved.Stats.Mined, 0, "NaN -> 0")
		T.eq(saved.Stats.Speed, 0, "-inf -> 0")
		T.eq(#saved.Storage, 3, "the gap is closed: nothing lost")
		T.eq(saved.Storage[3].O, "Copper", "the items keep their order")
		T.eq(saved.Spot, nil, "the Vector3 is dropped")
		T.eq(saved.Fn, nil, "the function is dropped")
		T.eq(saved.Mixed["1"], 10, "mixed table: number keys kept as text")
		T.eq(saved.Mixed.Name, "x")
		T.eq(saved.Keys.ok, 2, "a boolean key is dropped, the rest kept")
		T.eq(saved.Text, nil, "invalid UTF-8 text is dropped")
		T.eq(saved.Cycle.Name, "loop", "the cyclic table is kept...")
		T.eq(saved.Cycle.Self, nil, "...without its loop")
		T.eq(#logged, 1, "the repair is reported once")
		T.eq(logged[1].Key, "P")
		T.truthy(#logged[1].Problems >= 9, "every bad path is listed")
		-- the in-memory data is repaired too, so the next save is clean
		T.eq(p.Data.Stats.Mined, 0, "repaired in memory")
		logged = {}
		T.truthy(a:save(p, false), "next save")
		T.eq(#logged, 0, "nothing more to repair")
	end)

	---------------------------------------------------------------- #4: a failing migration

	T.test("SaveSafety #4: a migration error releases only our lock and keeps the data", function()
		local store = robloxStore()
		store:put("P", { Data = { Version = 3, Coins = 321, Purchases = "broken" }, Saved = 1 })
		local before = store:get("P").Data
		local a = server(store, "A", {
			Migrate = function(data: { [string]: any })
				for _ in data.Purchases do -- throws on a string, like the old trim
				end
			end,
		})
		local profile, reason = a:load("P")
		T.eq(profile, nil, "not loaded")
		T.truthy(
			type(reason) == "string" and string.find(reason, "migrate", 1, true) ~= nil,
			"reason names the migration: " .. tostring(reason)
		)
		local after = store:get("P")
		T.eq(after.Lock, nil, "our lock is released at once (no 10-minute lockout)")
		T.eq(after.Data.Coins, before.Coins, "the data is untouched")
		T.eq(after.Data.Purchases, "broken", "even the broken field (for a support fix)")
	end)

	T.test("SaveSafety #4: releasing after a failed migration never clears another server's lock", function()
		local store = robloxStore()
		local b = server(store, "B")
		local a = server(store, "A", {
			Migrate = function()
				-- while A migrates, the lock was taken over by B (simulated): A must not clear it
				local held = store:get("P")
				held.Lock = { JobId = "B", SessionId = "B-1", Time = now() }
				store:put("P", held)
				error("boom")
			end,
		})
		local profile = a:load("P")
		T.eq(profile, nil)
		T.eq(store:get("P").Lock.SessionId, "B-1", "B's lock stays")
		local _ = b
	end)

	---------------------------------------------------------------- #5: crashed servers

	T.test("SaveSafety #5: a crashed server's lock expires after StaleLockSeconds", function()
		T.eq(GameConfig.AutosaveInterval, 60, "the lock is refreshed every 60 s")
		T.eq(GameConfig.StaleLockSeconds, 180, "and counts as dead after 3 missed saves")
		local store = robloxStore()
		local a, b = server(store, "A"), server(store, "B")
		local pa = a:load("P")
		pa.Data.Coins = 40
		a:save(pa, false)
		clock.t += 30 -- crashed 30 s after its last save: a fresh lock
		local early = b:load("P")
		T.eq(early, nil, "a fresh lock still blocks (B waited 3 x 5 s)")
		clock.t += 181
		local late = b:load("P")
		T.truthy(late, "after StaleLockSeconds the lock is taken over")
		T.eq(late.Data.Coins, 40, "with the last saved data")
	end)

	T.test("SaveSafety #5: a younger lock is never taken over, not even on the last try", function()
		-- a live server whose final save is slow keeps its session: what it still writes isn't lost
		local store = robloxStore()
		local a, b = server(store, "A"), server(store, "B")
		local pa = a:load("P")
		clock.t += 100 -- older than half of StaleLockSeconds, younger than all of it
		local q, reason = b:load("P")
		T.eq(q, nil, "B waits and gives up")
		T.eq(reason, "locked")
		pa.Data.Coins = 64
		T.truthy(a:save(pa, true), "A's slow final save still lands")
		T.eq(store:get("P").Data.Coins, 64)
		T.truthy(b:load("P"), "and B loads it next")
	end)

	---------------------------------------------------------------- #1: newer saves

	T.test("SaveSafety #1: a save from a newer version is refused untouched, no lock taken", function()
		local store = robloxStore()
		store:put("P", { Data = { Version = 4, Coins = 9, BlasterLevel = 12 }, Saved = 1 })
		local before = store.values.P
		local a = server(store, "A")
		local profile, reason = a:load("P")
		T.eq(profile, nil, "refused")
		T.eq(reason, "newer", "the reason")
		T.eq(store.values.P, before, "byte for byte untouched")
		-- the same version (or older) loads
		store:put("P", { Data = { Version = 3, Coins = 9 }, Saved = 1 })
		T.truthy(a:load("P"), "version 3 loads")
		T.eq(DataService.kickText("newer"), "The game just updated, please rejoin", "the kick text")
	end)

	---------------------------------------------------------------- #7: Studio

	T.test("SaveSafety #7: Studio uses its own store unless asked; test players never touch a real store", function()
		T.eq(DataService.storeName(false, false), "TerraForge_PlayerData_v1", "live game")
		T.eq(DataService.storeName(false, true), "TerraForge_PlayerData_v1", "the flag only matters in Studio")
		T.eq(DataService.storeName(true, false), "TerraForge_PlayerData_Studio", "Studio: its own store")
		T.eq(DataService.storeName(true, true), "TerraForge_PlayerData_v1", "Studio with StudioLiveData")
		T.eq(GameConfig.StudioLiveData, false, "off by default")
		T.falsy(DataService.persists(-1), "a Studio test player (UserId -1) is kept in memory")
		T.falsy(DataService.persists(0), "UserId 0 too")
		T.truthy(DataService.persists(123), "real players are saved")
	end)

	---------------------------------------------------------------- #8: the purchase-id trim

	T.test("SaveSafety #8: the purchase trim keeps the newest 100 and never drops ids younger than 30 days", function()
		local nowT = 1_800_000_000
		local purchases = {}
		for i = 1, 150 do
			purchases["old" .. i] = nowT - 40 * 86400 - i -- 40+ days old
		end
		for i = 1, 120 do
			purchases["new" .. i] = nowT - i * 60 -- the last two hours
		end
		DataService.trimPurchases(purchases, nowT)
		local newKept, oldKept = 0, 0
		for id in purchases do
			if string.sub(id, 1, 3) == "new" then
				newKept += 1
			else
				oldKept += 1
			end
		end
		T.eq(newKept, 120, "every id younger than 30 days stays (even past 100)")
		T.eq(oldKept, 0, "old ones beyond the newest 100 go")
		local few = { a = nowT - 90 * 86400, b = nowT - 1 }
		DataService.trimPurchases(few, nowT)
		T.truthy(few.a and few.b, "under 100 ids nothing is trimmed")
		T.eq(DataService.trimPurchases("broken", nowT), false, "a non-table is reported, not iterated")
	end)

	---------------------------------------------------------------- #9 / #13 / #10: shutdown

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "P" .. userId, Parent = true, kicked = nil }
		function p:Kick(message: string)
			self.kicked = message
		end
		return p
	end

	local function realWaitServer(store: any, jobId: string): any
		return ProfileStore.new({
			Store = store,
			JobId = jobId,
			Template = template,
			Now = now,
			Wait = function(seconds: number)
				task.wait(math.min(seconds, 0.01))
			end,
			LockRetries = 2,
			LockRetryDelay = 0.01,
			StaleLockSeconds = 180,
			CallRetries = 3,
			LatestVersion = 3,
		})
	end

	T.test("SaveSafety #13: shutdown waits for a final save behind a yielding beforeRelease callback", function()
		local store = robloxStore()
		local ps = realWaitServer(store, "S")
		DataService._test.isolate(ps, function()
			local player = fakePlayer(501)
			DataService._test.loadPlayer(player)
			local data = DataService.get(player)
			T.truthy(data, "loaded")
			data.Coins = 777
			DataService.beforeRelease(function()
				task.wait(0.05) -- a callback that yields
			end)
			DataService._test.shutdown()
			local saved = store:get("Player_501")
			T.eq(saved.Data.Coins, 777, "the final save landed before shutdown returned")
			T.eq(saved.Lock, nil, "and released the lock")
		end)
	end)

	T.test("SaveSafety #9: shutdown waits for a player who left while loading", function()
		local store = robloxStore()
		store.delay = 0.05 -- every request takes a moment
		local ps = realWaitServer(store, "S")
		DataService._test.isolate(ps, function()
			local player = fakePlayer(502)
			task.spawn(DataService._test.loadPlayer, player)
			task.wait(0.01) -- the load request is on its way
			player.Parent = nil -- left while loading
			DataService._test.shutdown()
			local saved = store:get("Player_502")
			T.truthy(saved == nil or saved.Lock == nil, "no lock left behind for a player who is gone")
			T.eq(DataService._test.inFlight(), 0, "nothing in flight")
		end)
	end)

	T.test("SaveSafety #10: shutdown saves stay quick when the store keeps failing", function()
		local store = robloxStore()
		local ps = realWaitServer(store, "S")
		DataService._test.isolate(ps, function()
			local player = fakePlayer(503)
			DataService._test.loadPlayer(player)
			store.failAll = true
			local started = os.clock()
			DataService._test.shutdown()
			T.truthy(os.clock() - started < 5, `gave up quickly ({os.clock() - started} s)`)
			T.eq(DataService._test.inFlight(), 0, "nothing left in flight")
		end)
	end)

	T.test("SaveSafety: a test player (UserId <= 0) loads and saves in memory only", function()
		local store = robloxStore()
		local ps = realWaitServer(store, "S")
		DataService._test.isolate(ps, function()
			local player = fakePlayer(-1)
			DataService._test.loadPlayer(player)
			T.truthy(DataService.get(player), "the test player has data")
			DataService.get(player).Coins = 5
			T.truthy(DataService.saveNow(player), "saves (in memory)")
			DataService._test.shutdown()
			T.eq(store.writes, 0, "the real store never saw it")
		end)
	end)

	T.test("SaveSafety: kick texts for every load failure", function()
		T.eq(DataService.kickText("locked"), "Your Terra Forge data is still being saved. Please rejoin in a minute.")
		T.eq(DataService.kickText("newer"), "The game just updated, please rejoin")
		T.truthy(#DataService.kickText("malformed") > 10, "malformed")
		T.truthy(#DataService.kickText("error: migrate: x") > 10, "migrate")
		T.truthy(#DataService.kickText("error: 502") > 10, "busy")
	end)

	---------------------------------------------------------------- the review (R1-R4, A, C, autosave)

	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")

	-- a ProfileStore with quick real waits; `retries` lock tries 0.01 s apart
	local function lifeServer(store: any, jobId: string, retries: number?): any
		return ProfileStore.new({
			Store = store,
			JobId = jobId,
			Template = template,
			Now = now,
			Wait = function(seconds: number)
				task.wait(math.min(seconds, 0.01))
			end,
			LockRetries = retries or 2,
			LockRetryDelay = 0.01,
			StaleLockSeconds = 180,
			CallRetries = 3,
			LatestVersion = 3,
		})
	end

	local function quickTimings(releaseWait: number, callbackLimit: number?)
		DataService._test.setTimings(releaseWait, function(seconds: number)
			task.wait(math.min(seconds, 0.01))
		end, callbackLimit)
	end

	local function waitUntil(condition: () -> boolean, limit: number?): boolean
		local waited = 0
		while not condition() and waited < (limit or 2) do
			task.wait(0.01)
			waited += 0.01
		end
		return condition()
	end

	T.test("SaveSafety R1: leaving during a load and rejoining the same server: the live session keeps its lock", function()
		local store = robloxStore()
		store:put("Player_601", { Data = { Version = 3, Coins = 100 }, Lock = { JobId = "X", SessionId = "X#1", Time = now() }, Saved = 1 })
		local ps = lifeServer(store, "S", 400) -- keeps retrying while X holds the lock
		DataService._test.isolate(ps, function()
			quickTimings(1)
			local p1 = fakePlayer(601)
			task.spawn(DataService._test.loadPlayer, p1)
			task.wait(0.05) -- P1's load waits on X's lock
			p1.Parent = nil -- P1 gives up and leaves...
			local p2 = fakePlayer(601) -- ...and rejoins the same server
			task.spawn(DataService._test.loadPlayer, p2)
			task.wait(0.05)
			local held = store:get("Player_601")
			held.Lock = nil -- X releases
			store:put("Player_601", held)
			T.truthy(
				waitUntil(function()
					return DataService.get(p2) ~= nil
				end),
				"P2 loads"
			)
			task.wait(0.1) -- (P1's stale load had every chance to take the lock)
			T.eq(DataService.get(p1), nil, "P1 never got a session")
			local lock = store:get("Player_601").Lock
			T.truthy(lock and string.sub(lock.SessionId, 1, 2) == "S#", "the lock is this server's")
			DataService.get(p2).Coins = 999
			T.truthy(DataService.saveNow(p2), "P2's session still owns the lock")
			T.eq(store:get("Player_601").Data.Coins, 999, "P2's progress is saved")
			T.eq(p2.kicked, nil, "P2 plays on")
		end)
	end)

	T.test("SaveSafety R2: a rejoin while the last final save hangs is told to rejoin, the final save lands", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(0.2)
			local p1 = fakePlayer(602)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 100
			T.truthy(DataService.saveNow(p1), "100 saved")
			DataService.get(p1).Coins = 500 -- not saved yet
			store.hang = true -- the final save's request hangs (throttle queue / outage)
			p1.Parent = nil
			task.spawn(DataService._test.releasePlayer, p1)
			task.wait(0.05)
			local p2 = fakePlayer(602)
			DataService._test.loadPlayer(p2) -- waits 0.2 s on the release, then gives up
			T.eq(DataService.get(p2), nil, "no stale load while the last session is still saving")
			T.eq(p2.kicked, DataService.kickText("locked"), "told to rejoin in a minute")
			store.hang = false
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"the release finishes"
			)
			local saved = store:get("Player_602")
			T.eq(saved.Data.Coins, 500, "the hanging final save landed: nothing lost")
			T.eq(saved.Lock, nil, "and released")
			local p3 = fakePlayer(602)
			DataService._test.loadPlayer(p3)
			T.eq(DataService.get(p3).Coins, 500, "the next rejoin loads it")
		end)
	end)

	T.test("SaveSafety R2b: leaving while waiting on the last final save starts no load", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(5)
			local p1 = fakePlayer(603)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 555
			store.hang = true
			p1.Parent = nil
			task.spawn(DataService._test.releasePlayer, p1)
			task.wait(0.05)
			local p2 = fakePlayer(603)
			task.spawn(DataService._test.loadPlayer, p2)
			task.wait(0.05)
			p2.Parent = nil -- leaves while waiting
			task.wait(0.05)
			store.hang = false
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"everything settles"
			)
			local saved = store:get("Player_603")
			T.eq(saved.Data.Coins, 555, "the old final save landed")
			T.eq(saved.Lock, nil, "no lock left by the waiting load")
			T.eq(p2.kicked, nil, "nobody to kick")
		end)
	end)

	T.test("SaveSafety R3: a yielding beforeRelease callback: the autosave no longer refreshes the departed lock", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(1)
			DataService._test.setClock(now)
			local p = fakePlayer(604)
			DataService._test.loadPlayer(p)
			local lockTime = store:get("Player_604").Lock.Time
			DataService.beforeRelease(function()
				task.wait(0.2)
			end)
			-- (during PlayerRemoving the player is still parented: only the release itself can stop the autosave)
			task.spawn(DataService._test.releasePlayer, p)
			task.wait(0.02) -- inside the callback
			clock.t += 500
			DataService._test.autosaveStep(clock.t)
			task.wait(0.05)
			T.eq(store:get("Player_604").Lock.Time, lockTime, "no autosave for a player who left")
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"the release finishes"
			)
			T.eq(store:get("Player_604").Lock, nil, "and releases the lock")
		end)
	end)

	T.test("SaveSafety R3: a hanging beforeRelease callback can't hold the final save back for ever", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(1, 0.2) -- (the game gives the callbacks 5 s)
			local p = fakePlayer(605)
			DataService._test.loadPlayer(p)
			DataService.get(p).Coins = 42
			DataService.beforeRelease(function()
				task.wait(1) -- stuck (longer than the limit)
			end)
			p.Parent = nil
			local started = os.clock()
			DataService._test.releasePlayer(p)
			T.truthy(os.clock() - started < 0.6, `the final save started after the callback limit ({os.clock() - started} s)`)
			T.eq(store:get("Player_605").Data.Coins, 42, "saved")
		end)
	end)

	T.test("SaveSafety R4: saveNow finding the session lost kicks the player (no zombie)", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			local p = fakePlayer(606)
			DataService._test.loadPlayer(p)
			local held = store:get("Player_606")
			held.Lock = { JobId = "B", SessionId = "B#1", Time = now() } -- another server took over
			store:put("Player_606", held)
			DataService.get(p).Coins = 7
			T.falsy(DataService.saveNow(p), "refused")
			T.eq(p.kicked, "Your Terra Forge session was opened on another server.", "kicked at once")
			T.eq(store:get("Player_606").Lock.SessionId, "B#1", "B's session untouched")
		end)
	end)

	T.test("SaveSafety A: a bad value written while the request waits can't fail the save", function()
		local store = robloxStore()
		store.delay = 0.02 -- the request yields before the transform, like the real network read
		local a = lifeServer(store, "A")
		local p = a:load("P")
		local writing = true
		task.spawn(function()
			while writing do
				p.Data.Spot = roblox.Vector3.new(1, 2, 3) -- a buggy writer, every 5 ms
				task.wait(0.005)
			end
		end)
		p.Data.Coins = 77
		local ok = a:save(p, false)
		writing = false
		T.truthy(ok, "saved: the repair runs inside the transform, on what is written")
		T.eq(store:get("P").Data.Coins, 77)
		T.eq(store:get("P").Data.Spot, nil, "the Vector3 never reaches the store")
	end)

	T.test("SaveSafety: UpdateAsync running a transform twice changes nothing", function()
		local store = robloxStore()
		store.rerun = true
		local a = lifeServer(store, "A")
		local p = a:load("P")
		T.truthy(p, "load")
		T.eq(store:get("P").Lock.SessionId, p.SessionId, "one session, the one returned")
		p.Data.Storage = { { K = "Raw", O = "Coal" } }
		p.Data.Storage[3] = { K = "Raw", O = "Iron" }
		T.truthy(a:save(p, false), "save")
		T.eq(#store:get("P").Data.Storage, 2, "repaired once, nothing duplicated or lost")
		T.truthy(a:save(p, true), "release")
		T.eq(store:get("P").Lock, nil)
	end)

	T.test("SaveSafety C: one save version: DataTemplate.Version == Migrations.Latest, and a slip never locks players out", function()
		T.eq(DataTemplate.Version, Migrations.Latest, "bump DataTemplate.Version and Migrations.Latest together")
		T.eq(DataService.latestVersion(), Migrations.Latest, "the gate's version")
		-- if they ever diverge, the gate takes the higher one: a new player's save loads again
		local real = DataTemplate.Version
		DataTemplate.Version = Migrations.Latest + 1
		local ok, err = pcall(function()
			local store = robloxStore()
			local server2 = ProfileStore.new({
				Store = store,
				JobId = "S",
				Template = DataTemplate,
				Now = now,
				Wait = fakeWait,
				LatestVersion = DataService.latestVersion(),
				Migrate = function(data)
					Migrations.run(data)
				end,
			})
			local first = server2:load("New")
			T.truthy(first, "first join")
			T.truthy(server2:save(first, true), "leaves")
			local second, reason = server2:load("New")
			T.truthy(second, "second join on the same build: " .. tostring(reason))
		end)
		DataTemplate.Version = real
		if not ok then
			error(err, 0)
		end
	end)

	T.test("SaveSafety: a load still waiting at shutdown stops at once and takes no lock", function()
		local store = robloxStore()
		store:put("Player_607", { Data = { Version = 3, Coins = 1 }, Lock = { JobId = "X", SessionId = "X#1", Time = now() }, Saved = 1 })
		local ps = lifeServer(store, "S", 400)
		DataService._test.isolate(ps, function()
			local p = fakePlayer(607)
			task.spawn(DataService._test.loadPlayer, p)
			task.wait(0.05)
			local started = os.clock()
			local calls = store.calls
			DataService._test.shutdown()
			T.truthy(os.clock() - started < 1, `shutdown didn't wait for the retries ({os.clock() - started} s)`)
			T.truthy(store.calls - calls <= 2, "at most the request already on its way")
			T.eq(store:get("Player_607").Lock.SessionId, "X#1", "X's lock untouched, none taken")
		end)
	end)

	T.test("SaveSafety: old-format locks (no SessionId) get the old stale time; a lock dated ahead is fresh", function()
		local store = robloxStore()
		local b = server(store, "B")
		store:put("P", { Data = { Version = 3, Coins = 3 }, Lock = { JobId = "Old", Time = now() - 200 }, Saved = 1 })
		T.eq(b:load("P"), nil, "an old server's lock 200 s old is still live (its autosave ran every ~160-195 s)")
		store:put("P", { Data = { Version = 3, Coins = 3 }, Lock = { JobId = "Old", Time = now() - 601 }, Saved = 1 })
		T.truthy(b:load("P"), "after 600 s it is stale")
		store:put("Q", { Data = { Version = 3, Coins = 3 }, Lock = { JobId = "Skewed", SessionId = "Z#1", Time = now() + 120 }, Saved = 1 })
		T.eq(b:load("Q"), nil, "a lock 2 minutes ahead (a fast clock) is fresh: waited for")
		store:put(
			"Q",
			{ Data = { Version = 3, Coins = 3 }, Lock = { JobId = "Skewed", SessionId = "Z#1", Time = now() + 180 + 3601 }, Saved = 1 }
		)
		T.truthy(b:load("Q"), "a lock dated absurdly far ahead is a broken clock: taken over")
	end)

	T.test("SaveSafety #5/#12: the real autosave keeps every lock fresh and retries a failed refresh soon", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			DataService._test.setClock(now)
			local interval = GameConfig.AutosaveInterval
			local players = {}
			local lastLock = {}
			local worst = 0
			local function join(id: number)
				local p = fakePlayer(id)
				DataService._test.loadPlayer(p)
				players[id] = p
				lastLock[id] = store:get("Player_" .. id).Lock.Time
			end
			local function check()
				for id, p in players do
					if p.Parent then
						local lock = store:get("Player_" .. id).Lock
						if lock.Time ~= lastLock[id] then
							worst = math.max(worst, lock.Time - lastLock[id])
							lastLock[id] = lock.Time
						end
						worst = math.max(worst, clock.t - lastLock[id])
					end
				end
			end
			join(701)
			join(702)
			-- 10 minutes in 5 s steps; players join and leave mid-round; one minute of failures
			for step = 1, 120 do
				clock.t += 5
				if step == 7 then
					join(703) -- right after a round
				elseif step == 30 then
					players[702].Parent = nil
					DataService._test.releasePlayer(players[702])
					players[702] = nil
				elseif step == 50 then
					store.failAll = true
				elseif step == 54 then
					store.failAll = false
				end
				DataService._test.autosaveStep(clock.t)
				task.wait(0.005)
				if not store.failAll then
					check()
				end
			end
			-- worst case: due inside the 20 s outage, retried every 15 s, checked every 5 s
			T.truthy(worst <= interval + 20 + 15 + 5, `every lock refreshed within {worst} s (a 20 s outage included)`)
			T.truthy(worst < GameConfig.StaleLockSeconds, "never near the stale time")
			-- a failed refresh is tried again soon, not a whole interval later
			local id = 701
			local due = DataService._test.nextSave(players[id])
			T.truthy(due ~= nil, "scheduled")
		end)
	end)

	---------------------------------------------------------------- review round 2 (S1, S2, S4, S6, H2, H3, H6)

	T.test("SaveSafety R1 (write round trip): a same-server load during the lock write waits; the first keeps its lock", function()
		local store = robloxStore()
		store.after = 0.03 -- the write's round trip: the lock is stored before the caller hears back
		local ps = lifeServer(store, "S", 400)
		local first
		task.spawn(function()
			first = ps:load("Player_611")
		end)
		task.wait(0.01) -- the first load's lock is written, its answer still on the way
		ps.lockRetries = 2 -- (the second load on the same server gives up quickly)
		local second, reason = ps:load("Player_611")
		T.eq(second, nil, "the second load waits on the live session")
		T.eq(reason, "locked")
		T.truthy(
			waitUntil(function()
				return first ~= nil
			end),
			"the first load finishes"
		)
		T.eq(store:get("Player_611").Lock.SessionId, first.SessionId, "its lock is untouched")
	end)

	T.test("SaveSafety R2b (release running): leaving while the last final save runs starts no load", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(5)
			local p1 = fakePlayer(612)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 321
			store.after = 0.2 -- the final save's answer takes a while
			p1.Parent = nil
			task.spawn(DataService._test.releasePlayer, p1)
			task.wait(0.02)
			local p2 = fakePlayer(612)
			task.spawn(DataService._test.loadPlayer, p2)
			task.wait(0.05) -- P2 waits on the running release...
			p2.Parent = nil -- ...and leaves
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"everything settles"
			)
			store.after = 0
			local saved = store:get("Player_612")
			T.eq(saved.Data.Coins, 321, "the final save landed")
			T.eq(saved.Lock, nil, "no lock taken for P2")
		end)
	end)

	T.test("SaveSafety S1: a player who leaves during the lock write's round trip gets the lock put back", function()
		local store = robloxStore()
		store.after = 0.05
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			local p = fakePlayer(613)
			task.spawn(DataService._test.loadPlayer, p)
			task.wait(0.02) -- the transform ran (lock written), the answer is on its way
			p.Parent = nil
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"settles"
			)
			local saved = store:get("Player_613")
			T.truthy(saved, "the lock had been written")
			T.eq(saved.Lock, nil, "and was put back: no 180 s lockout elsewhere")
		end)
	end)

	T.test("SaveSafety S2: a final save that fails is forgotten: a rejoin loads the stored copy at once", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(1)
			local p1 = fakePlayer(614)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 50
			T.truthy(DataService.saveNow(p1), "50 stored")
			store.failAll = true
			p1.Parent = nil
			DataService._test.releasePlayer(p1) -- every attempt fails
			store.failAll = false
			local p2 = fakePlayer(614)
			DataService._test.loadPlayer(p2)
			T.truthy(DataService.get(p2), "the rejoin loads at once (no 3-minute 'locked' loop)")
			T.eq(DataService.get(p2).Coins, 50, "the last stored copy")
			T.eq(p2.kicked, nil)
		end)
	end)

	T.test("SaveSafety S4: a failed autosave is retried within 15 s, then the next one is a full interval later", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			DataService._test.setClock(now)
			DataService._test.setRandom(function()
				return 1 -- the first autosave a full interval after joining
			end)
			local p = fakePlayer(615)
			DataService._test.loadPlayer(p)
			local start = clock.t
			T.eq(DataService._test.nextSave(p), start + GameConfig.AutosaveInterval, "first save a full interval in")
			local lockTime = store:get("Player_615").Lock.Time
			clock.t = start + GameConfig.AutosaveInterval
			store.failAll = true -- an outage longer than the save's own retries
			DataService._test.autosaveStep(clock.t)
			T.truthy(
				waitUntil(function()
					local due = DataService._test.nextSave(p)
					return due ~= nil and due <= clock.t + 15
				end),
				"rescheduled"
			)
			T.truthy(DataService._test.nextSave(p) - clock.t <= 15, "tried again within 15 s, not a whole interval later")
			T.eq(store:get("Player_615").Lock.Time, lockTime, "(the lock wasn't refreshed)")
			store.failAll = false
			clock.t = DataService._test.nextSave(p)
			DataService._test.autosaveStep(clock.t)
			T.truthy(
				waitUntil(function()
					return store:get("Player_615").Lock.Time == clock.t
				end),
				"the retry refreshes the lock"
			)
			T.truthy(
				waitUntil(function()
					return DataService._test.nextSave(p) == clock.t + GameConfig.AutosaveInterval
				end),
				"and the next save is a full interval later"
			)
		end)
	end)

	T.test("SaveSafety S6: an autosave that finds another server's lock kicks the player and leaves that lock alone", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			DataService._test.setClock(now)
			DataService._test.setRandom(function()
				return 0
			end)
			local p = fakePlayer(616)
			DataService._test.loadPlayer(p)
			local held = store:get("Player_616")
			held.Lock = { JobId = "B", SessionId = "B#9", Time = now() }
			store:put("Player_616", held)
			clock.t += GameConfig.AutosaveInterval
			DataService._test.autosaveStep(clock.t)
			T.truthy(
				waitUntil(function()
					return p.kicked ~= nil
				end),
				"kicked"
			)
			T.eq(p.kicked, "Your Terra Forge session was opened on another server.")
			T.eq(store:get("Player_616").Lock.SessionId, "B#9", "B's lock untouched")
		end)
	end)

	T.test("SaveSafety H2: with the key's UpdatedTime, a writer's clock skew doesn't decide a lock's age", function()
		local store = robloxStore()
		store.keyInfo = true
		local a = server(store, "A")
		local b = server(store, "B")
		T.truthy(a:load("P"), "A loads")
		-- A's clock runs 2 minutes fast: its lock says now + 120, but the key was written just now
		local held = store:get("P")
		held.Lock.Time = now() + 120
		store:put("P", held)
		store.updated.P = clock.t * 1000
		T.eq(b:load("P"), nil, "B waits: the key was written seconds ago (Roblox's clock)")
		clock.t += 181
		T.truthy(b:load("P"), "after StaleLockSeconds on Roblox's clock it is stale, whatever Lock.Time says")
	end)

	T.test("SaveSafety H3: a live session on this server always blocks a second load, however old its lock", function()
		local store = robloxStore()
		local a = server(store, "A")
		local first = a:load("P")
		clock.t += 400 -- its refreshes failed for minutes; it is still live here
		local second, reason = a:load("P")
		T.eq(second, nil, "never taken while live here")
		T.eq(reason, "locked")
		first.Data.Coins = 555
		T.truthy(a:save(first, true), "the live session's final save still lands")
		T.eq(store:get("P").Data.Coins, 555)
	end)

	T.test("SaveSafety H3: two Player objects of one user (PlayerAdded first): the old live session keeps its lock", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(0.2)
			DataService._test.setClock(now)
			local p1 = fakePlayer(617)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 555
			clock.t += 400 -- no refresh for minutes (an outage just ended)
			local p2 = fakePlayer(617) -- the second device joins before P1 is removed
			DataService._test.loadPlayer(p2)
			T.eq(DataService.get(p2), nil, "P2 doesn't take P1's live session")
			T.truthy(p2.kicked ~= nil, "P2 is told to rejoin")
			p1.Parent = nil
			DataService._test.releasePlayer(p1)
			T.eq(store:get("Player_617").Data.Coins, 555, "P1's progress lands")
		end)
	end)

	T.test("SaveSafety H6: a final save hung for longer than a lock lives no longer locks the rejoin out", function()
		local store = robloxStore()
		local ps = lifeServer(store, "S")
		DataService._test.isolate(ps, function()
			quickTimings(0.1)
			DataService._test.setClock(now)
			local p1 = fakePlayer(618)
			DataService._test.loadPlayer(p1)
			DataService.get(p1).Coins = 10
			T.truthy(DataService.saveNow(p1))
			store.hang = true -- the final save's request doesn't come back
			p1.Parent = nil
			task.spawn(DataService._test.releasePlayer, p1)
			task.wait(0.02)
			local early = fakePlayer(618)
			DataService._test.loadPlayer(early)
			T.truthy(early.kicked ~= nil, "a quick rejoin is told to wait")
			clock.t += GameConfig.StaleLockSeconds + 1
			-- meanwhile another server took the stale lock over, played and left
			local value = serde.decode("json", store.values["Player_618"])
			value.Lock = nil
			value.Data.Coins = 20
			store.values["Player_618"] = serde.encode("json", value)
			store.hang = false -- (the hung request finally gets through: refused, its session is gone)
			local late = fakePlayer(618)
			DataService._test.loadPlayer(late)
			T.truthy(DataService.get(late), "after StaleLockSeconds the rejoin loads (load's lock rules decide)")
			T.eq(DataService.get(late).Coins, 20, "the newest stored copy")
			T.truthy(
				waitUntil(function()
					return DataService._test.inFlight() == 0
				end),
				"settles"
			)
			T.eq(store:get("Player_618").Data.Coins, 20, "the hung save never wrote over it")
		end)
	end)
end
