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
	  waits; BindToClose waits up to FinalWait for them). Only boards whose
	  stored number changed are written. Every request waits for DataStore
	  budget (GetRequestBudgetForRequestType), is pcall'd and tried Retries
	  times with a growing pause; a failed write is tried again on the next
	  round. Studio test players (UserId <= 0) are never written.
	- Every LeaderboardConfig.RefreshSeconds (60 s) the top
	  LeaderboardConfig.TopCount of each board is read (GetSortedAsync,
	  descending, one board at a time), names come from
	  Players:GetNameFromUserIdAsync (cached; a failed lookup is tried again
	  after NameRetry seconds), and every player gets Leaderboards
	  { Live, Boards, Own } (Net.luau). A board that can't be read keeps its
	  last rows. A joining player gets the latest rows at once.
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

-- Writes one score. True when the store took it.
function LeaderboardService.writeScore(boardId: string, userId: number, stored: number): boolean
	local store = stores[boardId]
	if not store then
		return false
	end
	for attempt = 1, LeaderboardService.Retries do
		if waitBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
			local ok, err = pcall(function()
				store:SetAsync(tostring(userId), stored)
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
-- for the user (a zero is only written over a number this server wrote).
function LeaderboardService.dueWrites(userId: number, values: { [string]: number }): { Write }
	local known = written[userId]
	local due: { Write } = {}
	for _, board in LeaderboardConfig.Boards do
		local stored = LeaderboardConfig.encode(board.Id, values[board.Id])
		local before = if known then known[board.Id] else nil
		if stored ~= before and (stored > 0 or before ~= nil) then
			table.insert(due, { Board = board.Id, Stored = stored })
		end
	end
	return due
end

-- Writes a user's changed scores now. Returns how many were written.
function LeaderboardService.flushValues(userId: number, values: { [string]: number }): number
	if not live or userId <= 0 then
		return 0
	end
	local count = 0
	for _, item in LeaderboardService.dueWrites(userId, values) do
		if LeaderboardService.writeScore(item.Board, userId, item.Stored) then
			local known = written[userId]
			if not known then
				known = {}
				written[userId] = known
			end
			known[item.Board] = item.Stored
			count += 1
		end
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

-- A player's name for a row (players here, then the cache, then Roblox).
function LeaderboardService.nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	local name: string? = if online then online.Name else nil
	if not name then
		local failed = nameFailedAt[userId]
		if failed and os.clock() - failed < LeaderboardService.NameRetry then
			return LeaderboardService.UnknownName
		end
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and type(result) == "string" and result ~= "" then
			name = result
		else
			nameFailedAt[userId] = os.clock()
			return LeaderboardService.UnknownName
		end
	end
	if nameCount >= LeaderboardService.MaxNames then
		table.clear(names)
		nameCount = 0
	end
	local found = name :: string
	names[userId] = found
	nameCount += 1
	nameFailedAt[userId] = nil
	return found
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
		for i, board in LeaderboardConfig.Boards do
			local rows = LeaderboardService.readBoard(board.Id)
			if rows then
				for _, row in rows do
					row.Name = LeaderboardService.nameOf(row.UserId)
				end
				tops[board.Id] = { Rows = rows, Ready = true }
			elseif not tops[board.Id] then
				tops[board.Id] = { Rows = {}, Ready = false }
			end
			if i < #LeaderboardConfig.Boards then
				task.wait(LeaderboardService.ReadGap)
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
				table.insert(entries, { UserId = p.Player.UserId, Name = p.Player.Name, Value = p.Values[board.Id] or 0 })
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

-- A leaving player: the last seconds of play go into the final save, then
-- the scores of that save are written in their own thread.
local function onRelease(player: Player, data: { [string]: any })
	LeaderboardService.creditPlayTime(player, data, os.clock())
	local values = LeaderboardService.values(player, data)
	playCredit[player] = nil
	lastWrite[player] = nil
	local userId = player.UserId
	if not live or userId <= 0 then
		written[userId] = nil
		return
	end
	inFlight += 1
	task.spawn(function()
		local ok, err = pcall(LeaderboardService.flushValues, userId, values)
		if not ok then
			warn(`[LeaderboardService] final write for {userId} failed: {err}`)
		end
		written[userId] = nil
		inFlight -= 1
	end)
end

function LeaderboardService.init()
	DataService.onLoaded(function(player: Player, _data: { [string]: any })
		local now = os.clock()
		LeaderboardService.startPlay(player, now)
		lastWrite[player] = now
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
		nameCount = 0
		inFlight = 0
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
}

return LeaderboardService
