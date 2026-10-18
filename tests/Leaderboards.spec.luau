-- The lobby leaderboards under Lune: LeaderboardService's values per board,
-- the hours-played credit (whole seconds, the fraction carried, broken
-- saves, idle time skipped: requests and moves keep a player active),
-- which scores are due (only changed ones; growing boards never lowered,
-- MoneyPerSec once per session, a 0 too), the 120 s write gate, retries
-- and budget (a reserve for the player saves), Studio and Studio test
-- players never written, hidden users and removeUser (a fresh server
-- writes nothing before its first read of the hidden list), the final write on
-- leave (after LeaveDelay; a round write still running lands first and
-- isn't remembered), reading the top rows (batched DisplayNames, junk
-- keys, a failed read keeps the last rows), this server's ranking without
-- DataStores, the payload with your own rank; and LeaderboardView: the
-- payload check, the row texts, your estimated rank, one text size per
-- board, the board / panel builders (touch sizes, tabs). DataStores,
-- players and Net are small fakes.
return function(T, Loader)
	local task = require("@lune/task")
	local Vector3 = (require("@lune/roblox") :: any).Vector3
	local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local LeaderboardService = Loader.requirePath("ServerScriptService.Server.Services.LeaderboardService")
	local LeaderboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LeaderboardView")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")

	local lb = LeaderboardService._test
	-- the real batched name lookup (the worlds below swap in a fake)
	local realFetchNames = LeaderboardService.fetchNames

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

	-- A fake OrderedDataStore: SetAsync / UpdateAsync / GetSortedAsync with
	-- failures on demand (`sets` counts the write requests; onWrite runs
	-- inside a write, while it is on its way).
	local function fakeStore(): any
		local s: any = { values = {}, sets = 0, updates = 0, removes = 0, fail = 0, readFail = false, reads = 0, onWrite = nil }
		function s:RemoveAsync(key: string)
			self.removes += 1
			if self.fail > 0 then
				self.fail -= 1
				error("DataStore request was rejected")
			end
			self.values[key] = nil
		end
		function s:SetAsync(key: string, value: number)
			self.sets += 1
			if self.fail > 0 then
				self.fail -= 1
				error("DataStore request was rejected")
			end
			if self.onWrite then
				self.onWrite(key)
			end
			self.values[key] = value
		end
		function s:UpdateAsync(key: string, transform: (any) -> any)
			self.sets += 1
			self.updates += 1
			if self.fail > 0 then
				self.fail -= 1
				error("DataStore request was rejected")
			end
			if self.onWrite then
				self.onWrite(key)
			end
			local result = transform(self.values[key])
			if result ~= nil then
				self.values[key] = result
			end
			return result
		end
		function s:GetSortedAsync(ascending: boolean, size: number)
			self.reads += 1
			if self.readFail then
				error("502: API Services rejected request")
			end
			local list = {}
			for key, value in self.values do
				table.insert(list, { key = key, value = value })
			end
			table.sort(list, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local page = {}
			for i = 1, math.min(size, #list) do
				page[i] = list[i]
			end
			return {
				GetCurrentPage = function()
					return page
				end,
			}
		end
		return s
	end

	local function fakePlayer(userId: number, name: string): any
		return { UserId = userId, Name = name, Parent = true }
	end

	local function setup(liveOn: boolean): any
		local w: any = { fired = {}, changed = 0, players = {}, data = {}, stores = {}, income = {} }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return w.data[p]
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(PodiumService, "incomeOf", function(p)
			return w.income[p] or 0
		end)
		patch(Net, "fire", function(name, p, payload)
			table.insert(w.fired, { Name = name, Player = p, Payload = payload })
		end)
		patch(LeaderboardService, "players", function()
			return w.players
		end)
		patch(LeaderboardService, "budget", function()
			return 100
		end)
		patch(LeaderboardService, "fetchNames", function(ids: { number })
			w.nameCalls = (w.nameCalls or 0) + 1
			local found = {}
			for _, id in ids do
				found[id] = "User" .. id
			end
			return found
		end)
		patch(LeaderboardService, "fetchName", function(_userId: number)
			return nil
		end)
		patch(LeaderboardService, "RetryWait", 0)
		patch(LeaderboardService, "ReadGap", 0)
		patch(LeaderboardService, "BudgetWait", 0)
		patch(LeaderboardService, "LeaveDelay", 0)
		w.patch = patch
		lb.reset()
		lb.setLive(liveOn)
		if liveOn then
			for _, board in LeaderboardConfig.Boards do
				local store = fakeStore()
				w.stores[board.Id] = store
				lb.setStore(board.Id, store)
			end
		end
		w.add = function(userId: number, name: string): any
			local p = fakePlayer(userId, name)
			table.insert(w.players, p)
			w.data[p] = deepCopy(DataTemplate)
			return p
		end
		w.restore = function()
			lb.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, liveOn: boolean, fn: (any) -> ())
		T.test(name, function()
			local w = setup(liveOn)
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	---------------------------------------------------------------- values

	withWorld("leaderboards: a player's value on every board comes from the save", true, function(w)
		local p = w.add(11, "Ada")
		local d = w.data[p]
		d.TotalEarned = 4.5e6
		d.Stats.ArtifactsFound = 7
		d.Stats.PlaySeconds = 3600
		w.income[p] = 1300
		local v = LeaderboardService.values(p, d)
		T.eq(v.MoneyPerSec, 1300)
		T.eq(v.TotalEarned, 4.5e6)
		T.eq(v.Artifacts, 7)
		T.eq(v.HoursPlayed, 3600)
		-- junk never gets through
		d.TotalEarned = 0 / 0
		d.Stats = "broken"
		w.income[p] = math.huge
		local junk = LeaderboardService.values(p, d)
		for _, board in LeaderboardConfig.Boards do
			T.eq(junk[board.Id], 0, board.Id .. " junk")
		end
		-- PodiumService failing doesn't break the board
		rawset(PodiumService, "incomeOf", function()
			error("podiums broke")
		end)
		T.eq(LeaderboardService.valueOf(p, d, "MoneyPerSec"), 0)
	end)

	---------------------------------------------------------------- hours played

	withWorld("leaderboards: play time is credited in whole seconds, the fraction carries over", true, function(w)
		-- (always active here: the idle rule has its own test)
		w.patch(LeaderboardService, "ActiveWindow", math.huge)
		local p = w.add(12, "Bo")
		local d = w.data[p]
		LeaderboardService.startPlay(p, 100)
		T.eq(LeaderboardService.creditPlayTime(p, d, 100.4), 0, "under a second")
		T.eq(LeaderboardService.creditPlayTime(p, d, 161.4), 61)
		T.eq(LeaderboardService.creditPlayTime(p, d, 220), 59, "the 0.4 carried over")
		T.eq(LeaderboardService.creditPlayTime(p, d, 220.6), 0)
		T.eq(LeaderboardService.creditPlayTime(p, d, 221), 1)
		T.eq(d.Stats.PlaySeconds, 121, "exactly the time played")
		-- a stalled server: at most MaxCredit at once
		T.eq(LeaderboardService.creditPlayTime(p, d, 221 + 5000), LeaderboardService.MaxCredit)
		-- time going backwards or a broken counter
		T.eq(LeaderboardService.creditPlayTime(p, d, 10), 0)
		d.Stats.PlaySeconds = 0 / 0
		LeaderboardService.startPlay(p, 0)
		T.eq(LeaderboardService.creditPlayTime(p, d, 30), 30)
		T.eq(d.Stats.PlaySeconds, 30, "NaN starts over at 0")
		d.Stats = nil
		T.eq(LeaderboardService.creditPlayTime(p, d, 60), 0, "no Stats: nothing, no error")
		-- a player that never started has nothing to credit
		local q = w.add(13, "Cy")
		T.eq(LeaderboardService.creditPlayTime(q, w.data[q], 999), 0)
	end)

	withWorld("leaderboards: idle time isn't play time (requests and moves keep a player active)", true, function(w)
		local window = LeaderboardService.ActiveWindow
		local p = w.add(14, "Idle")
		local d = w.data[p]
		LeaderboardService.startPlay(p, 0)
		T.eq(LeaderboardService.creditPlayTime(p, d, 60), 60, "joining counts as activity")
		-- no request, no move: credited up to ActiveWindow after the last activity, then nothing
		T.eq(LeaderboardService.creditPlayTime(p, d, window + 200), window - 60, "up to the window's end")
		T.eq(LeaderboardService.creditPlayTime(p, d, window + 260), 0, "idle")
		T.eq(LeaderboardService.creditPlayTime(p, d, window + 320), 0, "still idle")
		T.eq(d.Stats.PlaySeconds, window)
		-- back (a request): the idle stretch is skipped, play counts from here
		LeaderboardService.markActive(p, window + 350)
		T.eq(LeaderboardService.creditPlayTime(p, d, window + 380), 30)
		T.eq(d.Stats.PlaySeconds, window + 30)
		-- back from idle before the next credit: the active time before the
		-- idle stretch is credited at once, the stretch itself never
		local changed = w.changed
		LeaderboardService.markActive(p, 2 * window + 400)
		T.eq(d.Stats.PlaySeconds, 2 * window, "the active tail up to the window's end")
		T.truthy(w.changed > changed, "DataService.changed")
		T.eq(LeaderboardService.creditPlayTime(p, d, 2 * window + 460), 60, "the idle stretch was skipped")
		-- moves: a flat step of MoveStuds counts; jumping in place or a shuffle doesn't
		local t = 2 * window + 460
		LeaderboardService.noteSpot(p, Vector3.new(0, 0, 0), t)
		LeaderboardService.noteSpot(p, Vector3.new(0, 12, 0), t + 400) -- a jump in place
		LeaderboardService.noteSpot(p, Vector3.new(1, 0, 1), t + 410) -- a shuffle
		T.eq(LeaderboardService.creditPlayTime(p, d, t + 500), window - 60, "only up to the window's end: no move counted")
		LeaderboardService.noteSpot(p, Vector3.new(1 + LeaderboardService.MoveStuds, 0, 1), t + 510)
		T.eq(LeaderboardService.creditPlayTime(p, d, t + 570), 60, "the step made the player active")
		LeaderboardService.noteSpot(p, nil, t + 600) -- no character: nothing, no error
		-- a player who isn't playing (not loaded) isn't tracked
		local q = w.add(15, "Gone")
		LeaderboardService.markActive(q, 10)
		LeaderboardService.noteSpot(q, Vector3.new(50, 0, 50), 10)
		T.eq(LeaderboardService.creditPlayTime(q, w.data[q], 100), 0)
	end)

	---------------------------------------------------------------- writes

	withWorld("leaderboards: only changed scores are written, MoneyPerSec once per session", true, function(w)
		local values = { MoneyPerSec = 0, TotalEarned = 2500, Artifacts = 0, HoursPlayed = 600 }
		local due = LeaderboardService.dueWrites(21, values)
		T.eq(#due, 3, "the session's first write: growing boards above 0, and MoneyPerSec")
		T.eq(due[1].Board, "MoneyPerSec")
		T.eq(due[1].Stored, 0, "a 0 replaces an old session's entry")
		T.eq(LeaderboardService.flushValues(21, values), 3)
		T.eq(w.stores.TotalEarned.values["21"], LeaderboardConfig.encode("TotalEarned", 2500))
		T.eq(w.stores.HoursPlayed.values["21"], 10, "minutes")
		T.eq(w.stores.MoneyPerSec.values["21"], 0)
		T.eq(w.stores.Artifacts.values["21"], nil, "a growing board's 0 is never written")
		T.eq(w.stores.TotalEarned.updates, 1, "growing boards: UpdateAsync")
		T.eq(w.stores.MoneyPerSec.updates, 0, "MoneyPerSec: SetAsync")
		T.eq(#LeaderboardService.dueWrites(21, values), 0, "nothing changed")
		T.eq(LeaderboardService.flushValues(21, values), 0)
		-- 30 more seconds of play: the same whole minute, nothing to write
		values.HoursPlayed = 630
		T.eq(#LeaderboardService.dueWrites(21, values), 0, "same minute")
		values.HoursPlayed = 660
		values.MoneyPerSec = 40
		T.eq(LeaderboardService.flushValues(21, values), 2)
		-- income gone: the 0 is written over the number we wrote
		values.MoneyPerSec = 0
		local again = LeaderboardService.dueWrites(21, values)
		T.eq(#again, 1)
		T.eq(again[1].Board, "MoneyPerSec")
		T.eq(again[1].Stored, 0)
		T.eq(LeaderboardService.flushValues(21, values), 1)
		T.eq(w.stores.MoneyPerSec.values["21"], 0)
		-- a new session writes MoneyPerSec again, even unchanged
		LeaderboardService.beginSession(21)
		local fresh = LeaderboardService.dueWrites(21, values)
		T.truthy(#fresh >= 1 and fresh[1].Board == "MoneyPerSec", "first write of the new session")
	end)

	withWorld("leaderboards: growing boards are never lowered (writes out of order)", true, function(w)
		-- another server (or a later write that landed first) stored more
		w.stores.TotalEarned.values["22"] = LeaderboardConfig.encode("TotalEarned", 9000)
		w.stores.HoursPlayed.values["22"] = 50
		T.eq(LeaderboardService.flushValues(22, { TotalEarned = 500, HoursPlayed = 600 }), 3, "the requests went through (and MoneyPerSec's first 0)")
		T.eq(w.stores.TotalEarned.values["22"], LeaderboardConfig.encode("TotalEarned", 9000), "the bigger score stays")
		T.eq(w.stores.HoursPlayed.values["22"], 50, "50 minutes stay over 10")
		-- a smaller value later in the same session isn't even sent
		local before = w.stores.TotalEarned.sets
		T.eq(LeaderboardService.flushValues(22, { TotalEarned = 400, HoursPlayed = 600 }), 0)
		T.eq(w.stores.TotalEarned.sets, before)
		-- a bigger one is
		T.eq(LeaderboardService.flushValues(22, { TotalEarned = 1e6, HoursPlayed = 600 }), 1)
		T.eq(w.stores.TotalEarned.values["22"], LeaderboardConfig.encode("TotalEarned", 1e6))
	end)

	withWorld("leaderboards: writes retry, give up without budget, never for test players", true, function(w)
		local store = w.stores.TotalEarned
		store.fail = 2
		T.truthy(LeaderboardService.writeScore("TotalEarned", 31, 5), "third try works")
		T.eq(store.sets, 3)
		store.fail = 99
		T.falsy(LeaderboardService.writeScore("TotalEarned", 32, 5), "all tries fail")
		T.eq(store.sets, 3 + LeaderboardService.Retries)
		-- a failed write is not remembered: the next round tries again
		store.fail = 99
		T.eq(LeaderboardService.flushValues(33, { TotalEarned = 10 }), 1, "only MoneyPerSec's 0 got through")
		T.eq((lb.written(33) :: any).TotalEarned, nil, "the failed one isn't remembered")
		store.fail = 0
		T.eq(LeaderboardService.flushValues(33, { TotalEarned = 10 }), 1)
		T.eq((lb.written(33) :: any).TotalEarned, LeaderboardConfig.encode("TotalEarned", 10))
		-- no budget: no request at all
		rawset(LeaderboardService, "budget", function()
			return 0
		end)
		local before = store.sets
		T.falsy(LeaderboardService.writeScore("TotalEarned", 34, 5))
		T.eq(store.sets, before, "waited for budget, sent nothing")
		rawset(LeaderboardService, "budget", function()
			return 100
		end)
		-- Studio test players (UserId <= 0) are never written
		T.eq(LeaderboardService.flushValues(-1, { TotalEarned = 1e9 }), 0)
		T.eq(LeaderboardService.flushValues(0, { TotalEarned = 1e9 }), 0)
		T.eq(store.values["-1"], nil)
		-- an unknown board has no store
		T.falsy(LeaderboardService.writeScore("Nope", 35, 5))
	end)

	withWorld("leaderboards: writes leave a budget reserve for the player saves", true, function(w)
		for i = 1, 3 do
			w.add(500 + i, "P" .. i)
		end
		T.eq(LeaderboardService.reserve(), LeaderboardService.ReserveBase + 3, "the base and one per player")
		local budgets: { [string]: number } = { GetAsync = 0, SetIncrementSortedAsync = 100 }
		rawset(LeaderboardService, "budget", function(kind: any): number
			return budgets[kind.Name] or 100
		end)
		-- exactly the reserve left: a growing board (UpdateAsync reads too) waits
		budgets.GetAsync = LeaderboardService.reserve()
		T.falsy(LeaderboardService.writeScore("TotalEarned", 501, 5), "the saves keep their GetAsync budget")
		T.eq(w.stores.TotalEarned.sets, 0)
		T.truthy(LeaderboardService.writeScore("MoneyPerSec", 501, 5), "SetAsync doesn't touch the saves' budget")
		budgets.GetAsync = LeaderboardService.reserve() + 1
		T.truthy(LeaderboardService.writeScore("TotalEarned", 501, 5), "one above the reserve")
		-- the board reads have their own budget (only the leaderboards use it)
		budgets.GetSortedAsync = 1
		T.truthy(LeaderboardService.readBoard("TotalEarned"))
		budgets.GetSortedAsync = 0
		T.eq(LeaderboardService.readBoard("TotalEarned"), nil)
	end)

	withWorld("leaderboards: Studio reads the boards but never writes them", true, function(w)
		lb.setWritable(false)
		local p = w.add(58, "Dev")
		w.data[p].TotalEarned = 1e9
		T.eq(LeaderboardService.flush(p, 1e6), 0)
		T.eq(LeaderboardService.flushValues(58, { TotalEarned = 1e9 }), 0)
		lb.release(p, w.data[p])
		T.eq(lb.inFlight(), 0, "no leave write")
		T.eq(w.stores.TotalEarned.sets, 0, "the live board never saw the developer")
		w.stores.TotalEarned.values = { ["9"] = LeaderboardConfig.encode("TotalEarned", 5000) }
		LeaderboardService.refresh()
		T.eq(lb.tops().TotalEarned.Rows[1].UserId, 9, "the live boards are read")
	end)

	withWorld("leaderboards: hidden users never show or get written; removeUser deletes a user", true, function(w)
		w.patch(LeaderboardConfig.Hidden, 66, true)
		local page = {
			{ key = "66", value = LeaderboardConfig.encode("TotalEarned", 1e12) },
			{ key = "67", value = LeaderboardConfig.encode("TotalEarned", 5) },
		}
		local rows = LeaderboardService.rowsFromPage("TotalEarned", page)
		T.eq(#rows, 1)
		T.eq(rows[1].UserId, 67)
		T.eq(rows[1].Rank, 1, "ranks close up")
		T.eq(LeaderboardService.pageSize(), LeaderboardConfig.TopCount + 1, "room for the hidden one on a page")
		T.eq(LeaderboardService.flushValues(66, { TotalEarned = 1e12 }), 0, "never written")
		local here = LeaderboardService.localRows("TotalEarned", {
			{ UserId = 66, Name = "Cheat", Value = 9e9 },
			{ UserId = 68, Name = "Fair", Value = 1 },
		})
		T.eq(#here, 1)
		T.eq(here[1].UserId, 68)
		-- removeUser: every board's entry goes (a failed request is retried), and the shown rows
		for _, board in LeaderboardConfig.Boards do
			w.stores[board.Id].values["69"] = 7
			w.stores[board.Id].values["70"] = 3
		end
		LeaderboardService.refresh()
		T.eq(lb.tops().Artifacts.Rows[1].UserId, 69)
		-- the runtime hidden list: a small DataStore and a MessagingService topic (fakes)
		local list: any = { values = {}, gets = 0, updates = 0 }
		function list:GetAsync(key: string): any
			self.gets += 1
			return self.values[key]
		end
		function list:UpdateAsync(key: string, transform: (any) -> any): any
			self.updates += 1
			local result = transform(self.values[key])
			if result ~= nil then
				self.values[key] = result
			end
			return result
		end
		local published = {}
		w.patch(LeaderboardService, "hiddenStoreOf", function()
			return list
		end)
		w.patch(LeaderboardService, "publishHidden", function(id: number): boolean
			table.insert(published, id)
			return true
		end)
		-- user 69 is online here and was written before
		T.truthy(LeaderboardService.flushValues(69, { TotalEarned = 50, Artifacts = 2, HoursPlayed = 3600, MoneyPerSec = 4 }) > 0)
		w.stores.Artifacts.fail = 1
		T.eq(LeaderboardService.removeUser(69), #LeaderboardConfig.Boards)
		T.truthy(LeaderboardService.isHidden(69), "hidden at runtime, no deploy")
		T.eq(published[1], 69, "the running servers are told")
		T.truthy(table.find(list.values[LeaderboardService.HiddenKey], 69), "saved for servers started later")
		for _, board in LeaderboardConfig.Boards do
			T.eq(w.stores[board.Id].values["69"], nil, board.Id .. " removed")
			T.eq(w.stores[board.Id].values["70"], 3, board.Id .. " others kept")
			for _, row in lb.tops()[board.Id].Rows do
				T.truthy(row.UserId ~= 69, board.Id .. " row gone")
			end
		end
		T.eq(lb.tops().Artifacts.Rows[1].UserId, 70)
		T.eq(lb.tops().Artifacts.Rows[1].Rank, 1)
		T.eq(w.stores.Artifacts.removes, 2, "retried once")
		-- an online user stays removed: the next rounds (any board due) write nothing
		local sets = 0
		for _, board in LeaderboardConfig.Boards do
			sets += w.stores[board.Id].sets
		end
		T.eq(LeaderboardService.flushValues(69, { TotalEarned = 99, Artifacts = 5, HoursPlayed = 7200, MoneyPerSec = 9 }), 0, "never written again")
		T.eq(LeaderboardService.flushValues(69, { TotalEarned = 99 }, true), 0, "not on leave either")
		local after = 0
		for _, board in LeaderboardConfig.Boards do
			after += w.stores[board.Id].sets
			T.eq(w.stores[board.Id].values["69"], nil, board.Id .. " stays removed")
		end
		T.eq(after, sets, "no write request at all")
		T.eq(LeaderboardService.pageSize(), LeaderboardConfig.TopCount + 2, "room for both hidden users")
		-- a server started later reads the saved list
		LeaderboardService.removeUser(71)
		T.eq(#list.values[LeaderboardService.HiddenKey], 2, "one entry per user")
		LeaderboardService.removeUser(71)
		T.eq(#list.values[LeaderboardService.HiddenKey], 2, "saved once")
		lb.reset()
		lb.setLive(true)
		T.falsy(LeaderboardService.isHidden(69), "a fresh server knows nothing yet")
		T.truthy(LeaderboardService.loadHidden(), "reads the list")
		T.truthy(LeaderboardService.isHidden(69) and LeaderboardService.isHidden(71), "both hidden")
		list.values[LeaderboardService.HiddenKey] = { "x", -3, 2.5, 72 }
		LeaderboardService.loadHidden()
		T.truthy(LeaderboardService.isHidden(72), "junk ids are skipped")
		T.falsy(LeaderboardService.isHidden(-3))
		for _, bad in { 0, -5, 1.5, 0 / 0 } do
			T.eq(LeaderboardService.removeUser(bad), 0)
		end
		-- the command bar's own copy opens the stores by name (none in Lune)
		T.eq(LeaderboardService.storeOf("Nope"), nil)
	end)

	withWorld("leaderboards: a fresh server writes nothing until it has read the hidden list", true, function(w)
		w.patch(LeaderboardService, "BusyWait", 0.5)
		-- a server started after removeUser(77): the saved list has 77, the first read fails
		local list: any = { values = { [LeaderboardService.HiddenKey] = { 77 } }, gets = 0, fail = 1 }
		function list:GetAsync(key: string): any
			self.gets += 1
			if self.fail > 0 then
				self.fail -= 1
				error("502: API Services rejected request")
			end
			return self.values[key]
		end
		w.patch(LeaderboardService, "hiddenStoreOf", function()
			return list
		end)
		lb.setHiddenLoaded(false)
		local cheat = w.add(77, "Cheat")
		local fair = w.add(78, "Fair")
		w.data[cheat].TotalEarned = 9e12
		w.data[fair].TotalEarned = 500
		local function sets(): number
			local n = 0
			for _, board in LeaderboardConfig.Boards do
				n += w.stores[board.Id].sets
			end
			return n
		end
		T.falsy(LeaderboardService.hiddenKnown())
		T.falsy(LeaderboardService.loadHidden(), "the first read fails")
		T.falsy(LeaderboardService.hiddenKnown())
		T.falsy(LeaderboardService.isHidden(77), "this server doesn't know 77 yet")
		-- the retry comes soon, not after HiddenSeconds
		T.eq(LeaderboardService.hiddenWait(1), LeaderboardService.HiddenRetry)
		T.eq(LeaderboardService.hiddenWait(2), 2 * LeaderboardService.HiddenRetry)
		T.eq(LeaderboardService.hiddenWait(50), LeaderboardService.HiddenRetryMax)
		T.truthy(LeaderboardService.HiddenRetryMax < LeaderboardService.HiddenSeconds)
		-- a write round meanwhile: nobody is written (77 is on the saved list)
		T.eq(LeaderboardService.flush(cheat, 1000), 0, "the removed user isn't written back")
		T.eq(LeaderboardService.flush(fair, 1000), 0, "nobody is, until the list is read")
		T.eq(LeaderboardService.flushValues(77, LeaderboardService.values(cheat, w.data[cheat])), 0)
		T.eq(sets(), 0, "no write request at all")
		-- a leave meanwhile waits for the list (BusyWait), then gives up without writing
		LeaderboardService.beginSession(77)
		lb.release(cheat, w.data[cheat])
		T.eq(lb.inFlight(), 1, "the leave write waits for the hidden list")
		local waited = 0
		while lb.inFlight() > 0 and waited < 3 do
			task.wait(0.1)
			waited += 0.1
		end
		T.eq(lb.inFlight(), 0)
		T.eq(sets(), 0, "skipped: the list never came")
		-- the retry reads the list: 77 stays off, the others are written at the next round
		T.truthy(LeaderboardService.loadHidden(), "the retry works")
		T.truthy(LeaderboardService.hiddenKnown())
		T.truthy(LeaderboardService.isHidden(77))
		T.eq(LeaderboardService.hiddenWait(3), LeaderboardService.HiddenSeconds, "then the usual pace")
		T.eq(LeaderboardService.flush(cheat, 1000 + LeaderboardService.WriteCheck), 0, "77 never")
		T.eq(LeaderboardService.flush(fair, 1000 + LeaderboardService.WriteCheck), 2, "the deferred round goes out at once")
		for _, board in LeaderboardConfig.Boards do
			T.eq(w.stores[board.Id].values["77"], nil, board.Id .. ": 77 stays removed")
		end
		T.eq(w.stores.TotalEarned.values["78"], LeaderboardConfig.encode("TotalEarned", 500))
		-- a leave once the list is known: written as usual (no wait)
		w.data[fair].TotalEarned = 800
		lb.release(fair, w.data[fair])
		T.eq(lb.inFlight(), 0)
		T.eq(w.stores.TotalEarned.values["78"], LeaderboardConfig.encode("TotalEarned", 800))
		-- a leave started before the read is written once the list comes (within BusyWait)
		lb.setHiddenLoaded(false)
		local late = w.add(79, "Late")
		w.data[late].TotalEarned = 300
		LeaderboardService.beginSession(79)
		lb.release(late, w.data[late])
		T.eq(lb.inFlight(), 1)
		T.truthy(LeaderboardService.loadHidden())
		waited = 0
		while lb.inFlight() > 0 and waited < 3 do
			task.wait(0.1)
			waited += 0.1
		end
		T.eq(lb.inFlight(), 0)
		T.eq(w.stores.TotalEarned.values["79"], LeaderboardConfig.encode("TotalEarned", 300), "written after the read")
	end)

	withWorld("leaderboards: a player's scores are written at most every WriteSeconds", true, function(w)
		local p = w.add(41, "Dee")
		w.data[p].TotalEarned = 100
		T.eq(LeaderboardService.flush(p, 1000), 2, "first round: TotalEarned and MoneyPerSec's first 0")
		w.data[p].TotalEarned = 200
		T.eq(LeaderboardService.flush(p, 1000 + LeaderboardService.WriteSeconds - 1), 0, "too soon")
		T.eq(w.stores.TotalEarned.values["41"], LeaderboardConfig.encode("TotalEarned", 100))
		T.eq(LeaderboardService.flush(p, 1000 + LeaderboardService.WriteSeconds), 1, "due again")
		T.eq(w.stores.TotalEarned.values["41"], LeaderboardConfig.encode("TotalEarned", 200))
		-- not loaded: nothing
		w.data[p] = nil
		T.eq(LeaderboardService.flush(p, 1e6), 0)
	end)

	withWorld("leaderboards: leaving credits the last seconds and writes the final scores", true, function(w)
		local p = w.add(51, "Eve")
		local d = w.data[p]
		d.TotalEarned = 9e12
		d.Stats.PlaySeconds = 7200
		LeaderboardService.startPlay(p, os.clock() - 90.5)
		lb.release(p, d)
		T.eq(d.Stats.PlaySeconds, 7290, "the last 90 s are in the final save")
		T.eq(lb.inFlight(), 0, "the write finished")
		T.eq(w.stores.TotalEarned.values["51"], LeaderboardConfig.encode("TotalEarned", 9e12))
		T.eq(w.stores.HoursPlayed.values["51"], 121, "7290 s = 121 whole minutes")
		T.eq(lb.written(51), nil, "forgotten after the final write")
		T.falsy(lb.releasing(51))
		-- a test player leaving: no write, no error
		local q = w.add(-2, "Player2")
		w.data[q].TotalEarned = 5
		lb.release(q, w.data[q])
		T.eq(w.stores.TotalEarned.values["-2"], nil)
	end)

	withWorld("leaderboards: a round write still running when the player leaves lands first and is forgotten", true, function(w)
		local p = w.add(56, "Max")
		local d = w.data[p]
		d.TotalEarned = 5000
		LeaderboardService.beginSession(56)
		LeaderboardService.startPlay(p, os.clock())
		-- the player leaves while the round's first write (MoneyPerSec) is on its way
		local released = false
		w.stores.MoneyPerSec.onWrite = function()
			if not released then
				released = true
				lb.release(p, d)
			end
		end
		local count = LeaderboardService.flushValues(56, LeaderboardService.values(p, d))
		T.eq(count, 1, "the write on its way lands; the rest is the leave write's")
		T.truthy(released)
		T.eq(lb.written(56), nil, "a write that ended after the leave began isn't remembered")
		T.eq(lb.inFlight(), 1, "the leave write waited for the round write")
		T.eq(w.stores.TotalEarned.values["56"], nil, "not yet")
		-- rounds skip a leaving player
		T.eq(LeaderboardService.flushValues(56, { TotalEarned = 7000 }), 0)
		local waited = 0
		while lb.inFlight() > 0 and waited < 3 do
			task.wait(0.1)
			waited += 0.1
		end
		T.eq(lb.inFlight(), 0, "the leave write finished")
		T.eq(w.stores.TotalEarned.values["56"], LeaderboardConfig.encode("TotalEarned", 5000))
		T.eq(w.stores.MoneyPerSec.values["56"], 0)
		T.eq(lb.written(56), nil, "nothing left behind")
		T.falsy(lb.releasing(56))
	end)

	withWorld("leaderboards: the leave write waits LeaveDelay (the final save goes first)", true, function(w)
		w.patch(LeaderboardService, "LeaveDelay", 0.2)
		local p = w.add(57, "Lea")
		local d = w.data[p]
		d.TotalEarned = 800
		LeaderboardService.beginSession(57)
		LeaderboardService.startPlay(p, os.clock())
		lb.release(p, d)
		T.eq(w.stores.TotalEarned.sets, 0, "nothing sent with the leave")
		T.eq(lb.inFlight(), 1, "on its way")
		local waited = 0
		while lb.inFlight() > 0 and waited < 3 do
			task.wait(0.05)
			waited += 0.05
		end
		T.eq(lb.inFlight(), 0)
		T.truthy(waited >= 0.15, "after the delay")
		T.eq(w.stores.TotalEarned.values["57"], LeaderboardConfig.encode("TotalEarned", 800))
	end)

	withWorld("leaderboards: without DataStores nothing is written", false, function(w)
		local p = w.add(61, "Fay")
		w.data[p].TotalEarned = 100
		T.eq(LeaderboardService.flushValues(61, { TotalEarned = 100 }), 0)
		T.eq(LeaderboardService.flush(p, 1e6), 0)
		lb.release(p, w.data[p])
		T.eq(lb.inFlight(), 0)
	end)

	---------------------------------------------------------------- reading

	T.test("leaderboards: rows from a sorted page (decode, junk keys, at most TopCount)", function()
		local page = {}
		for i = 1, 14 do
			table.insert(page, { key = tostring(1000 + i), value = LeaderboardConfig.encode("TotalEarned", 10 ^ (15 - i)) })
		end
		table.insert(page, 3, { key = "not a user", value = 5 })
		table.insert(page, 4, { key = "12.5", value = 5 })
		table.insert(page, 5, "junk")
		local rows = LeaderboardService.rowsFromPage("TotalEarned", page)
		T.eq(#rows, LeaderboardConfig.TopCount)
		for i, row in rows do
			T.eq(row.Rank, i, "ranks follow the page")
		end
		T.eq(rows[1].UserId, 1001)
		T.eq(rows[1].Value, 1e14, "decoded back")
		T.eq(rows[3].UserId, 1003, "junk entries skipped")
		T.eq(#LeaderboardService.rowsFromPage("TotalEarned", nil), 0)
		local hours = LeaderboardService.rowsFromPage("HoursPlayed", { { key = "7", value = 90 } })
		T.eq(hours[1].Value, 5400, "minutes back to seconds")
	end)

	withWorld("leaderboards: refresh reads every board, names the rows and sends them", true, function(w)
		local a = w.add(71, "Gil")
		local b = w.add(72, "Hal")
		w.stores.TotalEarned.values = { ["71"] = LeaderboardConfig.encode("TotalEarned", 500), ["9"] = LeaderboardConfig.encode("TotalEarned", 9000) }
		w.stores.Artifacts.values = { ["72"] = 3 }
		w.data[a].TotalEarned = 650
		LeaderboardService.refresh()
		local tops = lb.tops()
		for _, board in LeaderboardConfig.Boards do
			T.truthy(tops[board.Id] and tops[board.Id].Ready, board.Id .. " read")
			T.eq(w.stores[board.Id].reads, 1, "one read per board")
		end
		T.eq(tops.TotalEarned.Rows[1].UserId, 9)
		T.eq(tops.TotalEarned.Rows[1].Name, "User9")
		T.eq(tops.TotalEarned.Rows[2].UserId, 71)
		T.eq(tops.TotalEarned.Rows[2].Name, "Gil", "a player here: their own (display) name")
		T.eq(w.nameCalls, 1, "one batched name lookup for every board")
		LeaderboardService.refresh()
		T.eq(w.nameCalls, 1, "names are cached")
		-- everyone got a payload with their own values and ranks
		local sent: { [any]: any } = {}
		for _, f in w.fired do
			if f.Name == "Leaderboards" then
				sent[f.Player] = f.Payload
			end
		end
		T.truthy(sent[a] and sent[b], "both players")
		T.eq(sent[a].Live, true)
		T.eq(sent[a].Own.TotalEarned.Rank, 2)
		T.eq(sent[a].Own.TotalEarned.Value, 650, "the live value")
		T.eq(sent[a].Own.Artifacts.Rank, nil, "not on that board")
		T.eq(sent[b].Own.Artifacts.Rank, 1)
		-- a failed read keeps the last rows
		w.stores.TotalEarned.readFail = true
		LeaderboardService.refresh()
		T.eq(lb.tops().TotalEarned.Rows[1].UserId, 9, "kept")
	end)

	withWorld("leaderboards: names are DisplayNames, looked up in one batch", true, function(w)
		local here = w.add(301, "ada_miner")
		here.DisplayName = "Ada"
		local asked: { { number } } = {}
		rawset(LeaderboardService, "fetchNames", function(ids: { number })
			table.insert(asked, table.clone(ids))
			return { [302] = "Bea", [303] = "Cid" }
		end)
		local single = 0
		rawset(LeaderboardService, "fetchName", function(userId: number)
			single += 1
			return if userId == 304 then "dan_old" else nil
		end)
		LeaderboardService.resolveNames({ 301, 302, 303, 302, 304, 305 })
		T.eq(#asked, 1, "one batch")
		T.eq(#asked[1], 4, "players here and repeats aren't asked")
		T.eq(LeaderboardService.nameOf(301), "Ada", "the DisplayName of a player here")
		T.eq(LeaderboardService.nameOf(302), "Bea")
		T.eq(LeaderboardService.nameOf(304), "dan_old", "the batch didn't know it: one lookup")
		T.eq(LeaderboardService.nameOf(305), LeaderboardService.UnknownName)
		T.eq(single, 2, "only the ids the batch missed")
		-- known names and recent failures aren't asked again
		LeaderboardService.resolveNames({ 302, 303, 304, 305 })
		T.eq(#asked, 1)
		-- a failed batch: tried again next time, no one-by-one storm
		rawset(LeaderboardService, "fetchNames", function(ids: { number })
			table.insert(asked, table.clone(ids))
			return nil
		end)
		LeaderboardService.resolveNames({ 401, 402, 403 })
		T.eq(single, 2, "no single lookups after a failed batch")
		T.eq(LeaderboardService.nameOf(401), LeaderboardService.UnknownName)
		LeaderboardService.resolveNames({ 401 })
		T.eq(#asked, 3, "asked again")
		-- the real lookup without UserService (Lune) fails quietly
		T.eq(realFetchNames({ 1 }), nil)
		-- without DataStores the rows use DisplayNames too
		T.eq(LeaderboardService.displayName(here), "Ada")
		T.eq(LeaderboardService.displayName(w.add(306, "plain")), "plain", "no DisplayName: the username")
	end)

	withWorld("leaderboards: a board never read says so (Ready = false)", true, function(w)
		w.add(81, "Ivy")
		w.stores.MoneyPerSec.readFail = true
		LeaderboardService.refresh()
		local tops = lb.tops()
		T.eq(tops.MoneyPerSec.Ready, false)
		T.eq(#tops.MoneyPerSec.Rows, 0)
		T.eq(tops.TotalEarned.Ready, true)
	end)

	withWorld("leaderboards: without DataStores the boards rank this server's players", false, function(w)
		local a = w.add(91, "Jo")
		local b = w.add(92, "Kim")
		local c = w.add(-1, "Player1")
		w.data[a].TotalEarned = 300
		w.data[b].TotalEarned = 300
		w.data[c].TotalEarned = 1e6
		w.data[b].Stats.PlaySeconds = 0
		LeaderboardService.refresh()
		local rows = lb.tops().TotalEarned.Rows
		T.eq(#rows, 3)
		T.eq(rows[1].Name, "Player1", "Studio test players show here")
		T.eq(rows[2].UserId, 91, "a tie: lower UserId first")
		T.eq(rows[3].UserId, 92)
		T.eq(#lb.tops().HoursPlayed.Rows, 0, "zeros are left out")
		local payload = nil
		for _, f in w.fired do
			if f.Name == "Leaderboards" and f.Player == c then
				payload = f.Payload
			end
		end
		T.truthy(payload)
		T.eq(payload.Live, false)
		T.eq(payload.Own.TotalEarned.Rank, 1)
		-- more players than TopCount: the best TopCount
		local entries = {}
		for i = 1, 15 do
			table.insert(entries, { UserId = i, Name = "P" .. i, Value = i })
		end
		local top = LeaderboardService.localRows("Artifacts", entries)
		T.eq(#top, LeaderboardConfig.TopCount)
		T.eq(top[1].Value, 15)
		T.eq(top[LeaderboardConfig.TopCount].Value, 6)
	end)

	---------------------------------------------------------------- the view

	T.test("leaderboards view: the payload check keeps sane rows only", function()
		T.eq(LeaderboardView.sanitize(nil), nil)
		T.eq(LeaderboardView.sanitize({ Boards = 5 }), nil)
		local rows = {}
		for i = 1, 14 do
			table.insert(rows, { Rank = i, UserId = i, Name = string.rep("x", 80), Value = i * 10 })
		end
		table.insert(rows, 2, { Rank = 2, UserId = 0 / 0, Name = "nan", Value = 5 })
		table.insert(rows, 3, { Rank = 2, UserId = 3, Name = "inf", Value = math.huge })
		table.insert(rows, 4, "junk")
		local clean = LeaderboardView.sanitize({
			Live = false,
			Boards = { TotalEarned = { Rows = rows, Ready = true }, Bogus = { Rows = {} } },
			Own = { TotalEarned = { Value = 0 / 0, Rank = 3 }, Artifacts = "x" },
		})
		T.truthy(clean)
		T.eq(clean.Live, false)
		T.eq(#clean.Boards.TotalEarned.Rows, LeaderboardConfig.TopCount)
		T.eq(clean.Boards.TotalEarned.Rows[2].UserId, 2, "bad rows dropped")
		T.eq(#clean.Boards.TotalEarned.Rows[1].Name, LeaderboardView.MaxName)
		T.eq(clean.Boards.Bogus, nil)
		T.eq(clean.Own.TotalEarned.Value, 0)
		T.eq(clean.Own.TotalEarned.Rank, 3)
		T.eq(clean.Own.Artifacts, nil)
	end)

	T.test("leaderboards view: row texts, medals, your line and notes", function()
		local data = {
			Rows = {
				{ Rank = 1, UserId = 5, Name = "Top", Value = 2.5e6 },
				{ Rank = 2, UserId = 7, Name = "", Value = 1300 },
			},
			Ready = true,
		}
		local lines = LeaderboardView.lines("TotalEarned", data, { Value = 1300, Rank = 2 }, 7, 5, true)
		T.eq(#lines.Rows, 5)
		T.eq(lines.Rows[1].Value, "$2.5M")
		T.eq(lines.Rows[1].Medal, 1)
		T.eq(lines.Rows[2].Name, "Miner", "an empty name")
		T.truthy(lines.Rows[2].Mine, "your row")
		T.eq(lines.Rows[3].Name, LeaderboardView.Empty, "an empty place")
		T.eq(lines.Rows[3].Medal, nil, "no medal for an empty place")
		T.eq(lines.OwnRank, "#2")
		T.eq(lines.OwnValue, "$1.3K")
		T.eq(lines.Note, nil)
		local outside = LeaderboardView.lines("MoneyPerSec", data, { Value = 12 }, 99, 5, true)
		T.eq(outside.OwnRank, "~#3", "only two on the board: your live value makes you third")
		T.eq(outside.OwnValue, "+$12/s")
		local nothing = LeaderboardView.lines("HoursPlayed", nil, nil, 99, 5, true)
		T.eq(nothing.OwnRank, LeaderboardView.Empty)
		T.eq(nothing.OwnValue, "0.0 h")
		T.eq(LeaderboardView.lines("Artifacts", { Rows = {}, Ready = false }, nil, 1, 5, true).Note, "Loading...")
		T.eq(LeaderboardView.lines("Artifacts", data, nil, 1, 5, false).Note, LeaderboardView.LocalNote, "this server only")
	end)

	T.test("leaderboards view: your rank is estimated from your live value until the board catches up", function()
		local rows = {}
		for i = 1, LeaderboardConfig.TopCount do
			table.insert(rows, { Rank = i, UserId = 100 + i, Name = "P" .. i, Value = 1000 - i * 50 })
		end
		local data = { Rows = rows, Ready = true }
		-- 950, 900, 850 are worth more than 800
		T.eq(LeaderboardView.estimateRank("Artifacts", rows, 800, 1), 4)
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 800 }, 1, 5, true).OwnRank, "~#4")
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 5000 }, 1, 5, true).OwnRank, "~#1")
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 900 }, 1, 5, true).OwnRank, "~#2", "a tie: next to the equal row")
		-- below a full page: somewhere past it
		T.eq(LeaderboardView.estimateRank("Artifacts", rows, 100, 1), nil)
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 100 }, 1, 5, true).OwnRank, `#{LeaderboardConfig.TopCount + 1}+`)
		-- your own (older) row on the page doesn't count against you
		T.eq(LeaderboardView.estimateRank("Artifacts", rows, 800, 105), 4)
		-- the rank the server sent wins
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 800, Rank = 6 }, 1, 5, true).OwnRank, "#6")
		-- compared as the board stores it (hours: whole minutes)
		local hours = { { Rank = 1, UserId = 2, Name = "H", Value = 3660 } }
		T.eq(LeaderboardView.estimateRank("HoursPlayed", hours, 3659, 1), 2, "3659 s is stored as 60 minutes, below 61")
		T.eq(LeaderboardView.estimateRank("HoursPlayed", hours, 3719, 1), 1, "61 minutes: a tie")
		-- nothing to compare yet, or no value
		T.eq(LeaderboardView.lines("Artifacts", { Rows = {}, Ready = false }, { Value = 800 }, 1, 5, true).OwnRank, `#{LeaderboardConfig.TopCount + 1}+`)
		T.eq(LeaderboardView.estimateRank("Artifacts", rows, 0, 1), nil)
		T.eq(LeaderboardView.lines("Artifacts", data, { Value = 0 }, 1, 5, true).OwnRank, LeaderboardView.Empty)
		-- fewer entries than TopCount: right after the last one
		T.eq(LeaderboardView.estimateRank("Artifacts", { rows[1], rows[2] }, 1, 1), 3)
	end)

	T.test("leaderboards view: the board canvas and the panel build and fill", function()
		local board = LeaderboardConfig.ByIndex[1]
		local gui, canvas = LeaderboardView.surface(board)
		T.eq(gui.Face.Name, "Front")
		T.eq(#canvas.Rows, LeaderboardConfig.BoardRows)
		local lines = LeaderboardView.lines(board.Id, { Rows = { { Rank = 1, UserId = 1, Name = "A", Value = 5 } }, Ready = true }, nil, 2, LeaderboardConfig.BoardRows, false)
		LeaderboardView.fill(canvas, lines)
		T.eq(canvas.Rows[1].Name.Text, "A")
		T.truthy(canvas.Note.Visible, "the Studio note")
		T.eq(canvas.Rows[LeaderboardConfig.BoardRows].Name.Text, "", "the note takes the last row")
		-- long names and values shrink to fit their columns, short ones keep the full size
		T.eq(canvas.Width, LeaderboardView.BoardStuds * LeaderboardView.PixelsPerStud)
		local long = LeaderboardView.lines(
			"MoneyPerSec",
			{ Rows = { { Rank = 1, UserId = 1, Name = "Ab", Value = 5 }, { Rank = 2, UserId = 3, Name = "AVeryLongUsername_2024", Value = 1.23e15 } }, Ready = true },
			nil,
			2,
			LeaderboardConfig.BoardRows,
			true
		)
		LeaderboardView.fill(canvas, long)
		-- one size for every row's name and value: the rows stay even
		local size = canvas.Rows[1].Name.TextSize
		for i, row in canvas.Rows do
			T.eq(row.Name.TextSize, size, `row {i} name`)
			T.eq(row.Value.TextSize, size, `row {i} value`)
		end
		T.lt(size, canvas.TextSize, "a long value pulls every row down")
		T.truthy(size >= LeaderboardView.MinText)
		local valueW = canvas.Width * 0.94 * LeaderboardView.Columns.Value[2]
		T.le(LeaderboardView.textWidth(long.Rows[2].Value) * size, valueW + 1e-6, "values are never cut")
		-- a long name pulls the rows down only to NameFloor; past that it is cut off with "..."
		local named = LeaderboardView.lines(
			"Artifacts",
			{ Rows = { { Rank = 1, UserId = 1, Name = "Ab", Value = 5 }, { Rank = 2, UserId = 3, Name = "AVeryLongUsername_2024", Value = 7 } }, Ready = true },
			nil,
			2,
			LeaderboardConfig.BoardRows,
			true
		)
		LeaderboardView.fill(canvas, named)
		T.eq(canvas.Rows[1].Name.TextSize, math.max(LeaderboardView.MinText, math.floor(canvas.TextSize * LeaderboardView.NameFloor)))
		T.eq(canvas.Rows[2].Value.TextSize, canvas.Rows[1].Name.TextSize)
		T.eq(canvas.Rows[2].Name.TextTruncate.Name, "AtEnd")
		-- short rows keep the full size
		local short = LeaderboardView.lines("Artifacts", { Rows = { { Rank = 1, UserId = 1, Name = "Ab", Value = 5 } }, Ready = true }, nil, 2, LeaderboardConfig.BoardRows, true)
		LeaderboardView.fill(canvas, short)
		T.eq(canvas.Rows[1].Name.TextSize, canvas.TextSize)
		local nameW = canvas.Width * 0.94 * LeaderboardView.Columns.Name[2]
		local medium = LeaderboardView.fitSize("Forgekeeper_Ola", nameW, canvas.TextSize, LeaderboardView.MinText)
		T.le(LeaderboardView.textWidth("Forgekeeper_Ola") * medium, nameW + 1e-6)
		T.eq(LeaderboardView.fitSize("", 10, 20, 11), 20)
		-- the panel: tabs wrap around, each tab shows its own board
		local panel = LeaderboardView.buildPanel(true)
		T.eq(#panel.Canvases.TotalEarned.Rows, LeaderboardConfig.TopCount)
		T.eq(LeaderboardView.nextTab("MoneyPerSec", -1), "HoursPlayed")
		T.eq(LeaderboardView.nextTab("HoursPlayed", 1), "MoneyPerSec")
		LeaderboardView.setTab(panel, "Artifacts")
		T.eq(panel.Tab, "Artifacts")
		T.truthy(panel.Canvases.Artifacts.Root.Parent.Visible)
		T.falsy(panel.Canvases.MoneyPerSec.Root.Parent.Visible)
		LeaderboardView.setTab(panel, "Nope")
		T.eq(panel.Tab, "Artifacts", "unknown tab ignored")
	end)

	T.test("leaderboards view: the phone panel's buttons are 44 pt and it fits the screen", function()
		local panel = LeaderboardView.buildPanel(true)
		-- a 667 x 375 pt phone at the 0.62 floor, under a 58 pt top bar
		local scale = MenuPanel.PhoneScale
		local maxW, maxH = 667 / scale, (375 - 58) / scale
		LeaderboardView.layoutPanel(panel, true, maxW, maxH)
		for _, target in LeaderboardView.touchTargets(panel) do
			T.truthy(target.Size.Y.Offset * scale >= MenuPanel.MinTouch - 0.5, target.Name .. " tall enough")
			T.truthy(target.Size.X.Offset * scale >= MenuPanel.MinTouch - 0.5, target.Name .. " wide enough")
		end
		T.le(panel.Frame.Panel.Size.X.Offset, maxW)
		T.le(panel.Frame.Panel.Size.Y.Offset + panel.Frame.Panel.Position.Y.Offset, maxH)
	end)
end
