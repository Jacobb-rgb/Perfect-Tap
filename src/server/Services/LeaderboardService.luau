--[[
	LeaderboardService: the four lobby leaderboards (LeaderboardConfig) and
	the hours-played counter.

	Scores (one OrderedDataStore per board, LeaderboardConfig Store names,
	key = the player's UserId, value = LeaderboardConfig.encode):
	  MoneyPerSec  PodiumService.incomeOf (podium income per second now)
	  TotalEarned  data.TotalEarned
	  Artifacts    data.Stats.ArtifactsFound
	  HoursPlayed  data.Stats.PlaySeconds
	- A player's scores are written at most every WriteSeconds (120 s; the
	  first time WriteSeconds after joining) and once more when they leave
	  (the values of the final save, in their own thread so the save never
	  waits; it waits for a round write of the same player still running,
	  and BindToClose waits up to FinalWait for it). Only boards whose
	  stored number changed are written:
	    Growing boards (TotalEarned, Artifacts, HoursPlayed: they never go
	      down) are written with UpdateAsync keeping the bigger number, so
	      writes landing out of order (the leave write and a round write, or
	      two servers after a quick server hop) never lower a score.
	    MoneyPerSec (it goes down when podiums empty) is set; it is written
	      at least once per session, a 0 too, so an old entry from an
	      earlier session can't stay on the board.
	  Every request waits for DataStore budget
	  (GetRequestBudgetForRequestType), is pcall'd and tried Retries times
	  with a growing pause; a failed write is tried again on the next round.
	  A round write that ends after the player's leave started is not
	  remembered. Studio test players (UserId <= 0) are never written.
	- Every LeaderboardConfig.RefreshSeconds (60 s) the top
	  LeaderboardConfig.TopCount of each board is read (GetSortedAsync,
	  descending, one board at a time), and every player gets Leaderboards
	  { Live, Boards, Own } (Net.luau). A board that can't be read keeps its
	  last rows. A joining player gets the latest rows at once.
	- Names are DisplayNames (docs/COMPLIANCE.md 2.4): players on this server
	  by their own, the rest from one batched
	  UserService:GetUserInfosByUserIdsAsync call per refresh for every id
	  not cached yet (an id it doesn't return: Players:GetNameFromUserIdAsync;
	  else UnknownName, tried again after NameRetry seconds).
	- No DataStores (Studio without API access: DataService.isInMemory, or an
	  OrderedDataStore that can't be opened): Live = false and the boards
	  rank the players on this server (placeholder rows), so the boards can
	  be tested in Studio.

	Hours played: every PlayTick (60 s) each loaded player's
	data.Stats.PlaySeconds grows by the whole seconds since the last credit
	(the rest carries over; at most MaxCredit at once), and once more on
	leave, before the final save. DataService.changed follows each credit.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local PodiumService = require(script.Parent.PodiumService)

local LeaderboardService = {}

export type Row = { Rank: number, UserId: number, Name: string, Value: number }
export type BoardData = { Rows: { Row }, Ready: boolean }
export type Own = { Value: number, Rank: number? }
export type Payload = { Live: boolean, Boards: { [string]: BoardData }, Own: { [string]: Own } }
export type Write = { Board: string, Stored: number }

LeaderboardService.WriteSeconds = 120 -- a player's scores are written at most this often (and on leave)
LeaderboardService.WriteCheck = 10 -- how often the writer looks for players that are due
LeaderboardService.PlayTick = 60 -- PlaySeconds are credited this often
LeaderboardService.MaxCredit = 600 -- at most this many seconds in one credit (a stalled server)
LeaderboardService.Retries = 3
LeaderboardService.RetryWait = 2 -- seconds, times the attempt number
LeaderboardService.BudgetWait = 6 -- seconds a request waits for budget before giving up for this round
LeaderboardService.ReadGap = 1 -- seconds between two board reads
LeaderboardService.FinalWait = 20 -- BindToClose waits this long for the last writes
LeaderboardService.NameRetry = 300 -- a failed name lookup is tried again after this
LeaderboardService.MaxNames = 500 -- cached names (the cache starts over past this)
LeaderboardService.UnknownName = "Miner"
LeaderboardService.BusyWait = 15 -- the leave write waits this long for a round write still running
-- boards whose value never goes down: UpdateAsync keeps the bigger number
LeaderboardService.Growing = { TotalEarned = true, Artifacts = true, HoursPlayed = true } :: { [string]: boolean }

local live = false
local stores: { [string]: any } = {}
local tops: { [string]: BoardData } = {}
-- userId -> board -> the stored number this server last wrote
local written: { [number]: { [string]: number } } = {}
local lastWrite: { [Player]: number } = {}
local playCredit: { [Player]: number } = {}
local names: { [number]: string } = {}
local nameCount = 0
local nameFailedAt: { [number]: number } = {}
local inFlight = 0
-- userId -> the session (a number per load); a write that ends in another
-- session (or after the leave started) isn't remembered in `written`
local sessions: { [number]: number } = {}
local sessionCount = 0
local releasing: { [number]: boolean } = {}
-- userId -> round writes running now (the leave write waits for them)
local busy: { [number]: number } = {}

---------------------------------------------------------------- values

local function clean(value: any): number
	if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
		return 0
	end
	return value
end

-- A player's live value on one board (from their loaded save).
function LeaderboardService.valueOf(player: Player, data: { [string]: any }, boardId: string): number
	if boardId == "MoneyPerSec" then
		local ok, income = pcall(PodiumService.incomeOf, player, data)
		return if ok then clean(income) else 0
	elseif boardId == "TotalEarned" then
		return clean(data.TotalEarned)
	end
	local stats = data.Stats
	if type(stats) ~= "table" then
		return 0
	end
	if boardId == "Artifacts" then
		return clean(stats.ArtifactsFound)
	elseif boardId == "HoursPlayed" then
		return clean(stats.PlaySeconds)
	end
	return 0
end

-- Every board's live value for a player.
function LeaderboardService.values(player: Player, data: { [string]: any }): { [string]: number }
	local values = {}
	for _, board in LeaderboardConfig.Boards do
		values[board.Id] = LeaderboardService.valueOf(player, data, board.Id)
	end
	return values
end

---------------------------------------------------------------- hours played

-- Starts counting a player's time (on load).
function LeaderboardService.startPlay(player: Player, now: number)
	playCredit[player] = now
end

-- Adds the whole seconds since the last credit to data.Stats.PlaySeconds
-- (the fraction carries over). Returns the seconds added.
function LeaderboardService.creditPlayTime(player: Player, data: { [string]: any }, now: number): number
	local since = playCredit[player]
	if not since then
		return 0
	end
	local elapsed = now - since
	if elapsed ~= elapsed or elapsed <= 0 then
		return 0
	end
	local whole = math.floor(elapsed)
	if whole <= 0 then
		return 0
	end
	playCredit[player] = since + whole
	local stats = data.Stats
	if type(stats) ~= "table" then
		return 0
	end
	local add = math.min(whole, LeaderboardService.MaxCredit)
	stats.PlaySeconds = clean(stats.PlaySeconds) + add
	return add
end

---------------------------------------------------------------- DataStore requests

-- The request budget for a request type (0 when it can't be asked).
function LeaderboardService.budget(kind: Enum.DataStoreRequestType): number
	local ok, value = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return if ok and type(value) == "number" then value else 0
end

local function waitBudget(kind: Enum.DataStoreRequestType): boolean
	local waited = 0
	while LeaderboardService.budget(kind) < 1 do
		if waited >= LeaderboardService.BudgetWait then
			return false
		end
		task.wait(0.5)
		waited += 0.5
	end
	return true
end

-- Writes one score. True when the store took it (growing boards: the
-- store holds at least `stored` now).
function LeaderboardService.writeScore(boardId: string, userId: number, stored: number): boolean
	local store = stores[boardId]
	if not store then
		return false
	end
	local growing = LeaderboardService.Growing[boardId] == true
	for attempt = 1, LeaderboardService.Retries do
		-- (UpdateAsync reads and writes: both budgets)
		if
			waitBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync)
			and (not growing or waitBudget(Enum.DataStoreRequestType.GetAsync))
		then
			local ok, err = pcall(function()
				if growing then
					store:UpdateAsync(tostring(userId), function(old: any): number?
						-- never lower a score (writes may land out of order); nil = no write
						if type(old) == "number" and old >= stored then
							return nil
						end
						return stored
					end)
				else
					store:SetAsync(tostring(userId), stored)
				end
			end)
			if ok then
				return true
			end
			if attempt == LeaderboardService.Retries then
				warn(`[LeaderboardService] writing {boardId} for {userId} failed: {err}`)
			end
		end
		if attempt < LeaderboardService.Retries then
			task.wait(LeaderboardService.RetryWait * attempt)
		end
	end
	return false
end

-- The boards whose stored number differs from what this server last wrote
-- for the user this session: growing boards when the number grew (a 0
-- never needs writing), MoneyPerSec when it changed and always on the
-- session's first write (a 0 too: it replaces an old session's entry).
function LeaderboardService.dueWrites(userId: number, values: { [string]: number }): { Write }
	local known = written[userId]
	local due: { Write } = {}
	for _, board in LeaderboardConfig.Boards do
		local stored = LeaderboardConfig.encode(board.Id, values[board.Id])
		local before = if known then known[board.Id] else nil
		local isDue
		if LeaderboardService.Growing[board.Id] then
			isDue = stored > (before or 0)
		else
			isDue = before == nil or stored ~= before
		end
		if isDue then
			table.insert(due, { Board = board.Id, Stored = stored })
		end
	end
	return due
end

-- Writes a user's changed scores now (`final` = the leave write). Returns
-- how many were written.
function LeaderboardService.flushValues(userId: number, values: { [string]: number }, final: boolean?): number
	if not live or userId <= 0 then
		return 0
	end
	if not final and releasing[userId] then
		return 0
	end
	local session = sessions[userId]
	busy[userId] = (busy[userId] or 0) + 1
	local count = 0
	for _, item in LeaderboardService.dueWrites(userId, values) do
		if not final and releasing[userId] then
			break -- the leave write takes over
		end
		if LeaderboardService.writeScore(item.Board, userId, item.Stored) then
			count += 1
			-- remembered only while the same session goes on (a round write
			-- that ends after the leave started would bring the entry back)
			if final or (sessions[userId] == session and not releasing[userId]) then
				local known = written[userId]
				if not known then
					known = {}
					written[userId] = known
				end
				known[item.Board] = item.Stored
			end
		end
	end
	local left = (busy[userId] or 1) - 1
	if left > 0 then
		busy[userId] = left
	else
		busy[userId] = nil
	end
	return count
end

-- Writes a player's scores when WriteSeconds passed since the last time.
function LeaderboardService.flush(player: Player, now: number): number
	local data = DataService.get(player)
	if not data or not live or player.UserId <= 0 then
		return 0
	end
	local last = lastWrite[player]
	if last and now - last < LeaderboardService.WriteSeconds then
		return 0
	end
	lastWrite[player] = now
	return LeaderboardService.flushValues(player.UserId, LeaderboardService.values(player, data))
end

---------------------------------------------------------------- reading

-- A player's DisplayName (their username when it has none).
function LeaderboardService.displayName(player: Player): string
	local display: any = (player :: any).DisplayName
	if type(display) == "string" and display ~= "" then
		return display
	end
	return player.Name
end

local function remember(userId: number, name: string)
	if names[userId] == nil then
		if nameCount >= LeaderboardService.MaxNames then
			table.clear(names)
			nameCount = 0
		end
		nameCount += 1
	end
	names[userId] = name
	nameFailedAt[userId] = nil
end

-- DisplayNames of users (one web call; swappable for the tests). nil when
-- the call failed; users it doesn't know are missing from the map.
function LeaderboardService.fetchNames(ids: { number }): { [number]: string }?
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(ids)
	end)
	if not ok or type(infos) ~= "table" then
		return nil
	end
	local found: { [number]: string } = {}
	for _, info in infos :: { any } do
		if type(info) == "table" and type(info.Id) == "number" then
			local display, username = info.DisplayName, info.Username
			if type(display) == "string" and display ~= "" then
				found[info.Id] = display
			elseif type(username) == "string" and username ~= "" then
				found[info.Id] = username
			end
		end
	end
	return found
end

-- One user's name the old way (a user the batch didn't return; swappable).
function LeaderboardService.fetchName(userId: number): string?
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return if ok and type(result) == "string" and result ~= "" then result else nil
end

-- Looks up every name the rows need that isn't known yet: players here by
-- their DisplayName, the rest in one batched call (users it doesn't return
-- one by one, then UnknownName until NameRetry passed). A failed batch is
-- tried again on the next refresh.
function LeaderboardService.resolveNames(ids: { number })
	local online: { [number]: Player } = {}
	for _, player in LeaderboardService.players() do
		online[player.UserId] = player
	end
	local now = os.clock()
	local wanted: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, userId in ids do
		if not seen[userId] then
			seen[userId] = true
			local here = online[userId]
			if here then
				remember(userId, LeaderboardService.displayName(here))
			elseif names[userId] == nil then
				local failed = nameFailedAt[userId]
				if not failed or now - failed >= LeaderboardService.NameRetry then
					table.insert(wanted, userId)
				end
			end
		end
	end
	if #wanted == 0 then
		return
	end
	local found = LeaderboardService.fetchNames(wanted)
	if not found then
		return
	end
	for _, userId in wanted do
		local name = found[userId] or LeaderboardService.fetchName(userId)
		if name then
			remember(userId, name)
		else
			nameFailedAt[userId] = now
		end
	end
end

-- A row's name (resolveNames looked it up; UnknownName when it couldn't).
function LeaderboardService.nameOf(userId: number): string
	return names[userId] or LeaderboardService.UnknownName
end

-- Rows from a GetSortedAsync page ({ { key, value } }, best first), names empty.
function LeaderboardService.rowsFromPage(boardId: string, page: any): { Row }
	local rows: { Row } = {}
	if type(page) ~= "table" then
		return rows
	end
	for _, entry in page do
		if #rows >= LeaderboardConfig.TopCount then
			break
		end
		if type(entry) == "table" then
			local userId = tonumber(entry.key)
			local value = LeaderboardConfig.decode(boardId, entry.value)
			if userId and userId == math.floor(userId) and value > 0 then
				table.insert(rows, { Rank = #rows + 1, UserId = userId, Name = "", Value = value })
			end
		end
	end
	return rows
end

-- Reads a board's top rows (nil when it can't be read right now).
function LeaderboardService.readBoard(boardId: string): { Row }?
	local store = stores[boardId]
	if not store or not waitBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return nil
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, LeaderboardConfig.TopCount)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn(`[LeaderboardService] reading {boardId} failed: {result}`)
		return nil
	end
	return LeaderboardService.rowsFromPage(boardId, result)
end

-- This server's players ranked by their live values (the boards without DataStores).
function LeaderboardService.localRows(boardId: string, entries: { { UserId: number, Name: string, Value: number } }): { Row }
	local list = {}
	for _, entry in entries do
		if entry.Value > 0 then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	local rows: { Row } = {}
	for i, entry in list do
		if i > LeaderboardConfig.TopCount then
			break
		end
		-- the stored precision, like a real board
		local value = LeaderboardConfig.decode(boardId, LeaderboardConfig.encode(boardId, entry.Value))
		table.insert(rows, { Rank = i, UserId = entry.UserId, Name = entry.Name, Value = value })
	end
	return rows
end

---------------------------------------------------------------- sending

-- The players in the game (swappable for the Lune tests).
function LeaderboardService.players(): { Player }
	return Players:GetPlayers()
end

-- What one player gets: the boards and their own values and ranks.
function LeaderboardService.payloadFor(player: Player, data: { [string]: any }?): Payload
	local values = if data then LeaderboardService.values(player, data) else {}
	local own: { [string]: Own } = {}
	for _, board in LeaderboardConfig.Boards do
		local rank: number? = nil
		local top = tops[board.Id]
		if top then
			for _, row in top.Rows do
				if row.UserId == player.UserId then
					rank = row.Rank
					break
				end
			end
		end
		own[board.Id] = { Value = values[board.Id] or 0, Rank = rank }
	end
	return { Live = live, Boards = tops, Own = own }
end

function LeaderboardService.send(player: Player)
	local data = DataService.get(player)
	if data then
		Net.fire("Leaderboards", player, LeaderboardService.payloadFor(player, data))
	end
end

function LeaderboardService.broadcast()
	for _, player in LeaderboardService.players() do
		LeaderboardService.send(player)
	end
end

-- Reads every board (or ranks this server's players without DataStores) and sends the result.
function LeaderboardService.refresh()
	if live then
		local read: { [string]: { Row } } = {}
		local ids: { number } = {}
		for i, board in LeaderboardConfig.Boards do
			local rows = LeaderboardService.readBoard(board.Id)
			if rows then
				read[board.Id] = rows
				for _, row in rows do
					table.insert(ids, row.UserId)
				end
			end
			if i < #LeaderboardConfig.Boards then
				task.wait(LeaderboardService.ReadGap)
			end
		end
		-- every board's names in one lookup
		local ok, err = pcall(function()
			LeaderboardService.resolveNames(ids)
		end)
		if not ok then
			warn(`[LeaderboardService] name lookup failed: {err}`)
		end
		for _, board in LeaderboardConfig.Boards do
			local rows = read[board.Id]
			if rows then
				for _, row in rows do
					row.Name = LeaderboardService.nameOf(row.UserId)
				end
				tops[board.Id] = { Rows = rows, Ready = true }
			elseif not tops[board.Id] then
				tops[board.Id] = { Rows = {}, Ready = false }
			end
		end
	else
		local players = {}
		for _, player in LeaderboardService.players() do
			local data = DataService.get(player)
			if data then
				table.insert(players, { Player = player, Values = LeaderboardService.values(player, data) })
			end
		end
		for _, board in LeaderboardConfig.Boards do
			local entries = {}
			for _, p in players do
				table.insert(entries, { UserId = p.Player.UserId, Name = LeaderboardService.displayName(p.Player), Value = p.Values[board.Id] or 0 })
			end
			tops[board.Id] = { Rows = LeaderboardService.localRows(board.Id, entries), Ready = true }
		end
	end
	LeaderboardService.broadcast()
end

---------------------------------------------------------------- lifecycle

local function openStores(): boolean
	if DataService.isInMemory() then
		return false
	end
	for _, board in LeaderboardConfig.Boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.Store)
		end)
		if not ok or store == nil then
			warn(`[LeaderboardService] no OrderedDataStore {board.Store}: the boards rank this server only`)
			table.clear(stores)
			return false
		end
		stores[board.Id] = store
	end
	return true
end

-- A new session for a user (on load): the next write is its first.
function LeaderboardService.beginSession(userId: number)
	sessionCount += 1
	sessions[userId] = sessionCount
	releasing[userId] = nil
	written[userId] = nil
end

local function forget(userId: number, session: number?)
	-- (a new session of the same user on this server keeps its own state)
	if sessions[userId] == session then
		written[userId] = nil
		releasing[userId] = nil
		sessions[userId] = nil
	end
end

-- A leaving player: the last seconds of play go into the final save, then
-- the scores of that save are written in their own thread.
local function onRelease(player: Player, data: { [string]: any })
	LeaderboardService.creditPlayTime(player, data, os.clock())
	local values = LeaderboardService.values(player, data)
	playCredit[player] = nil
	lastWrite[player] = nil
	local userId = player.UserId
	local session = sessions[userId]
	if not live or userId <= 0 then
		forget(userId, session)
		return
	end
	-- round writes stop and aren't remembered from here on
	releasing[userId] = true
	inFlight += 1
	task.spawn(function()
		-- a round write still running lands first (MoneyPerSec is set: the
		-- leave write must be the last)
		local waited = 0
		while busy[userId] and waited < LeaderboardService.BusyWait do
			task.wait(0.25)
			waited += 0.25
		end
		local ok, err = pcall(LeaderboardService.flushValues, userId, values, true)
		if not ok then
			warn(`[LeaderboardService] final write for {userId} failed: {err}`)
		end
		forget(userId, session)
		inFlight -= 1
	end)
end

function LeaderboardService.init()
	DataService.onLoaded(function(player: Player, _data: { [string]: any })
		local now = os.clock()
		LeaderboardService.startPlay(player, now)
		lastWrite[player] = now
		LeaderboardService.beginSession(player.UserId)
		if live then
			LeaderboardService.send(player)
		else
			-- this server's ranking changes with every player: redo it
			task.defer(function()
				pcall(LeaderboardService.refresh)
			end)
		end
	end)
	-- (a player who never loaded has no entries to clean up)
	DataService.beforeRelease(onRelease)
	game:BindToClose(function()
		task.wait()
		local waited = 0
		while inFlight > 0 and waited < LeaderboardService.FinalWait do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

function LeaderboardService.start()
	live = openStores()
	-- hours played
	task.spawn(function()
		while true do
			task.wait(LeaderboardService.PlayTick)
			local now = os.clock()
			for _, player in LeaderboardService.players() do
				local data = DataService.get(player)
				if data and LeaderboardService.creditPlayTime(player, data, now) > 0 then
					DataService.changed(player)
				end
			end
		end
	end)
	-- score writes
	task.spawn(function()
		while true do
			task.wait(LeaderboardService.WriteCheck)
			for _, player in LeaderboardService.players() do
				if player.Parent then
					local ok, err = pcall(LeaderboardService.flush, player, os.clock())
					if not ok then
						warn(`[LeaderboardService] write round failed: {err}`)
					end
				end
			end
		end
	end)
	-- reading the boards
	while true do
		local refresh: any = LeaderboardService.refresh
		local ok, err = pcall(refresh)
		if not ok then
			warn(`[LeaderboardService] refresh failed: {err}`)
		end
		task.wait(LeaderboardConfig.RefreshSeconds)
	end
end

---------------------------------------------------------------- tests

LeaderboardService._test = {
	reset = function()
		live = false
		table.clear(stores)
		table.clear(tops)
		table.clear(written)
		table.clear(lastWrite)
		table.clear(playCredit)
		table.clear(names)
		table.clear(nameFailedAt)
		table.clear(sessions)
		table.clear(releasing)
		table.clear(busy)
		nameCount = 0
		inFlight = 0
		sessionCount = 0
	end,
	setLive = function(on: boolean)
		live = on
	end,
	setStore = function(boardId: string, store: any)
		stores[boardId] = store
	end,
	tops = function(): { [string]: BoardData }
		return tops
	end,
	written = function(userId: number): { [string]: number }?
		return written[userId]
	end,
	release = onRelease,
	inFlight = function(): number
		return inFlight
	end,
	releasing = function(userId: number): boolean
		return releasing[userId] == true
	end,
	setBusy = function(userId: number, count: number?)
		if count then
			busy[userId] = count
		else
			busy[userId] = nil
		end
	end,
	names = function(): { [number]: string }
		return names
	end,
}

return LeaderboardService
