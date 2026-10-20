-- DataService.changed (docs/SERVER_PERF_AUDIT.md #2): changed() only marks the
-- player; ONE deferred flush per player per frame runs every onChanged
-- listener once, in registration order, each isolated (an error or a yield
-- never stops the others), and skips a player whose data is gone.
-- onChangedNow listeners (Bonuses' cache) still run inside changed() itself.
return function(T, Loader)
	local task = require("@lune/task")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "P" .. userId, Parent = true, kicked = nil }
		function p:Kick(message: string)
			self.kicked = message
		end
		return p
	end

	-- Bounded wait (by iterations: a slow machine only waits longer in real time).
	local function waitUntil(condition: () -> boolean, limit: number?): boolean
		local waited = 0
		while not condition() and waited < (limit or 10) do
			task.wait(0.01)
			waited += 0.01
		end
		return condition()
	end

	-- Lets the deferred flush run. Lune's task.wait() can (rarely, ~1 in 3000)
	-- resume before a deferred thread ran, so wait for `check` itself (bounded),
	-- then a few more steps before checking that nothing else ran.
	local function settle(check: () -> boolean)
		T.truthy(waitUntil(check), "the deferred flush ran")
		for _ = 1, 3 do
			task.wait()
		end
	end

	-- A loaded test player (UserId <= 0: in memory) inside DataService's test isolation.
	local function withPlayer(name: string, fn: (any, { string }) -> ())
		T.test(name, function()
			DataService._test.isolate(nil, function()
				local calls: { string } = {}
				local flushes = 0
				DataService.onChanged(function() -- (records nothing in `calls`)
					flushes += 1
				end)
				local p = fakePlayer(-7)
				DataService._test.loadPlayer(p)
				T.truthy(DataService.get(p), "loaded")
				settle(function()
					return flushes >= 1 -- the load's own changed()
				end)
				fn(p, calls)
			end)
		end)
	end

	withPlayer("DataChanged: many changes in one frame call each listener once, in registration order", function(p, calls)
		DataService.onChanged(function(player)
			table.insert(calls, if player == p then "a" else "a(wrong player)")
		end)
		DataService.onChanged(function()
			table.insert(calls, "b")
		end)
		DataService.onChanged(function()
			table.insert(calls, "c")
		end)
		for _ = 1, 25 do
			DataService.changed(p)
		end
		T.eq(#calls, 0, "nothing runs inside changed()")
		settle(function()
			return #calls >= 3
		end)
		T.eq(table.concat(calls, ","), "a,b,c", "one call each, in order")
		settle(function()
			return true
		end)
		T.eq(#calls, 3, "and nothing more later")
	end)

	withPlayer("DataChanged: changes in different frames call each listener once per frame", function(p, calls)
		local again = true
		DataService.onChanged(function(player)
			table.insert(calls, "a")
			if again then
				again = false
				DataService.changed(player) -- a listener's own change (Tutorial's reward) gets a flush of its own
			end
		end)
		DataService.onChanged(function()
			table.insert(calls, "b")
		end)
		DataService.changed(p)
		DataService.changed(p)
		settle(function()
			return #calls >= 4 -- the listener's own change is flushed too
		end)
		T.eq(table.concat(calls, ","), "a,b,a,b", "once per flush")
		table.clear(calls)
		-- three frames (each waits for its flush): one call each per frame
		DataService.changed(p)
		settle(function()
			return #calls >= 2
		end)
		DataService.changed(p)
		DataService.changed(p)
		settle(function()
			return #calls >= 4
		end)
		DataService.changed(p)
		settle(function()
			return #calls >= 6
		end)
		T.eq(table.concat(calls, ","), "a,b,a,b,a,b", "three frames, three calls each")
	end)

	withPlayer("DataChanged: an error or a yield in one listener never stops the others", function(p, calls)
		local gate = false
		DataService.onChanged(function()
			table.insert(calls, "slow")
			local since = os.clock()
			while not gate and os.clock() - since < 30 do
				task.wait()
			end
			table.insert(calls, "slow done")
		end)
		DataService.onChanged(function()
			table.insert(calls, "boom")
			error("a broken listener")
		end)
		DataService.onChanged(function()
			table.insert(calls, "last")
		end)
		DataService.changed(p)
		settle(function()
			return #calls >= 3
		end)
		T.eq(table.concat(calls, ","), "slow,boom,last", "the yield and the error held nobody up")
		-- the next frame's flush runs every listener again (the yielded one is still waiting)
		DataService.changed(p)
		settle(function()
			return #calls >= 6
		end)
		T.eq(table.concat(calls, ","), "slow,boom,last,slow,boom,last", "a second flush runs them all")
		gate = true
		T.truthy(
			waitUntil(function()
				return #calls >= 8
			end),
			"the yielded calls finish"
		)
		T.eq(calls[7], "slow done")
		T.eq(calls[8], "slow done")
		table.clear(calls)
		DataService.changed(p)
		settle(function()
			return #calls >= 4
		end)
		T.eq(table.concat(calls, ","), "slow,slow done,boom,last", "after the yields, listeners run in order again")
	end)

	withPlayer("DataChanged: a player whose data is gone by the flush is skipped", function(p, calls)
		DataService.onChanged(function(player)
			table.insert(calls, player.Name)
		end)
		DataService.changed(p)
		p.Parent = nil
		DataService._test.releasePlayer(p) -- saved and released before the frame ends
		T.eq(DataService.get(p), nil, "the data is gone")
		DataService.changed(fakePlayer(-8)) -- never loaded
		-- another player in the same frame still gets the flush (flushes run in order:
		-- once q's ran, the ones before it had their chance)
		local q = fakePlayer(-9)
		DataService._test.loadPlayer(q)
		DataService.changed(p)
		DataService.changed(q)
		settle(function()
			return #calls >= 1
		end)
		T.eq(table.concat(calls, ","), "P-9", "only the player with data: none for a departed or never loaded one")
	end)

	withPlayer("DataChanged: onChangedNow runs inside every changed() call; its error is contained", function(p, calls)
		DataService.onChangedNow(function()
			table.insert(calls, "now")
		end)
		DataService.onChangedNow(function()
			error("a broken cache hook")
		end)
		DataService.onChanged(function()
			table.insert(calls, "later")
		end)
		DataService.changed(p)
		T.eq(table.concat(calls, ","), "now", "at once, before changed() returns")
		DataService.changed(p)
		T.eq(table.concat(calls, ","), "now,now", "on every call (not coalesced)")
		settle(function()
			return #calls >= 3
		end)
		T.eq(table.concat(calls, ","), "now,now,later", "the deferred listener once")
	end)

	T.test("DataChanged: Bonuses drops its cache inside changed() (a read right after a change is fresh)", function()
		local p = fakePlayer(-11)
		local realGet = DataService.get
		local data = { Gear = {}, Golems = {}, Boosts = {}, Artifacts = {} }
		DataService.get = function(player: any): any
			return if player == p then data else realGet(player)
		end
		local ok, err = pcall(function()
			Bonuses.stats(p)
			T.truthy(Bonuses._test.cached(p), "cached")
			DataService.changed(p)
			T.falsy(Bonuses._test.cached(p), "dropped before changed() returned")
		end)
		DataService.get = realGet -- (the deferred flush then finds no data for p: skipped)
		Bonuses.invalidate(p)
		if not ok then
			error(err, 0)
		end
	end)
end
