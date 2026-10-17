-- The lobby leaderboards under Lune: LeaderboardService's values per board,
-- the hours-played credit (whole seconds, the fraction carried, broken
-- saves), which scores are due (only changed ones, zeros only over our own
-- writes), the 120 s write gate, retries and budget, Studio test players
-- never written, the final write on leave, reading the top rows (names,
-- junk keys, a failed read keeps the last rows), this server's ranking
-- without DataStores, the payload with your own rank; and LeaderboardView:
-- the payload check, the row texts, the board / panel builders (touch
-- sizes, tabs). DataStores, players and Net are small fakes.
return function(T, Loader)
	local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local LeaderboardService = Loader.requirePath("ServerScriptService.Server.Services.LeaderboardService")
	local LeaderboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LeaderboardView")
	local MenuPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MenuPanel")

	local lb = LeaderboardService._test

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

	-- A fake OrderedDataStore: SetAsync / GetSortedAsync with failures on demand.
	local function fakeStore(): any
		local s: any = { values = {}, sets = 0, fail = 0, readFail = false, reads = 0 }
		function s:SetAsync(key: string, value: number)
			self.sets += 1
			if self.fail > 0 then
				self.fail -= 1
				error("DataStore request was rejected")
			end
			self.values[key] = value
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
		patch(LeaderboardService, "nameOf", function(userId: number)
			return "User" .. userId
		end)
		patch(LeaderboardService, "RetryWait", 0)
		patch(LeaderboardService, "ReadGap", 0)
		patch(LeaderboardService, "BudgetWait", 0)
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

	---------------------------------------------------------------- writes

	withWorld("leaderboards: only changed scores are written, zeros only over our own", true, function(w)
		local values = { MoneyPerSec = 0, TotalEarned = 2500, Artifacts = 0, HoursPlayed = 600 }
		local due = LeaderboardService.dueWrites(21, values)
		T.eq(#due, 2, "a new player: only boards above 0")
		T.eq(LeaderboardService.flushValues(21, values), 2)
		T.eq(w.stores.TotalEarned.values["21"], LeaderboardConfig.encode("TotalEarned", 2500))
		T.eq(w.stores.HoursPlayed.values["21"], 10, "minutes")
		T.eq(w.stores.MoneyPerSec.values["21"], nil)
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
		T.eq(LeaderboardService.flushValues(33, { TotalEarned = 10 }), 0)
		store.fail = 0
		T.eq(LeaderboardService.flushValues(33, { TotalEarned = 10 }), 1)
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

	withWorld("leaderboards: a player's scores are written at most every WriteSeconds", true, function(w)
		local p = w.add(41, "Dee")
		w.data[p].TotalEarned = 100
		T.eq(LeaderboardService.flush(p, 1000), 1, "first round")
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
		-- a test player leaving: no write, no error
		local q = w.add(-2, "Player2")
		w.data[q].TotalEarned = 5
		lb.release(q, w.data[q])
		T.eq(w.stores.TotalEarned.values["-2"], nil)
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
		T.eq(outside.OwnRank, `#{LeaderboardConfig.TopCount}+`)
		T.eq(outside.OwnValue, "+$12/s")
		local nothing = LeaderboardView.lines("HoursPlayed", nil, nil, 99, 5, true)
		T.eq(nothing.OwnRank, LeaderboardView.Empty)
		T.eq(nothing.OwnValue, "0.0 h")
		T.eq(LeaderboardView.lines("Artifacts", { Rows = {}, Ready = false }, nil, 1, 5, true).Note, "Loading...")
		T.truthy(LeaderboardView.lines("Artifacts", data, nil, 1, 5, false).Note, "Studio note")
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
		T.eq(canvas.Rows[1].Name.TextSize, canvas.TextSize, "a short name")
		T.lt(canvas.Rows[2].Name.TextSize, canvas.TextSize, "a long name shrinks")
		T.truthy(canvas.Rows[2].Name.TextSize >= LeaderboardView.MinText, "never below MinText")
		-- past MinText the label cuts the name off with "..."
		T.eq(canvas.Rows[2].Name.TextSize, LeaderboardView.MinText)
		T.eq(canvas.Rows[2].Name.TextTruncate.Name, "AtEnd")
		local nameW = canvas.Width * 0.94 * LeaderboardView.Columns.Name[2]
		local medium = LeaderboardView.fitSize("Forgekeeper_Ola", nameW, canvas.TextSize, LeaderboardView.MinText)
		T.le(LeaderboardView.textWidth("Forgekeeper_Ola") * medium, nameW + 1e-6)
		local valueW = canvas.Width * 0.94 * LeaderboardView.Columns.Value[2]
		T.le(LeaderboardView.textWidth(long.Rows[2].Value) * canvas.Rows[2].Value.TextSize, valueW + 1e-6)
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
