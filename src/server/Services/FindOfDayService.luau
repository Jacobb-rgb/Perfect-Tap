--[[
	FindOfDayService: the best ore cleaned today on any server (owner 2026-11-07,
	Events/FindOfDay), shown only on the big iron billboard.

	- report(player, oreId, grade): CleaningService (a player's own cleaning) and
	  ProcessingService (a machine's) call it for every clean ore. No yields:
	  a better find becomes the best at once (Workspace attributes FindOfDay*,
	  which the clients read) and is written out by the next save round. A
	  player on the hidden list (LeaderboardService.isHidden: right to be
	  forgotten, cheaters) never goes up, from here or from another server.
	- Every SaveEvery seconds (round), if this server has a new best of its
	  own: a MemoryStore sorted map UpdateAsync (key = the UTC day, Expiry 2
	  days, so nothing about a player stays; the better of what is stored and
	  ours stays, a tie keeps the stored one) and, only if ours was kept, one
	  MessagingService message to the other servers. Every RefreshEvery
	  seconds the stored best is read, for a server that started late or
	  missed one. A received or stored entry that is as good or better is
	  taken (every server shows the same finder) and drops this server's own
	  waiting worse one: nothing is written or sent again.
	- A new UTC day starts empty. Only a DisplayName, the UserId, an ore id and
	  a grade leave the server (docs/COMPLIANCE.md 2.10). Nothing is saved in a
	  player's save. On shutdown the last find is written (BindToClose).
	- In Studio nothing is stored or sent (the test hooks can swap both).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FindOfDay = require(Shared.Events.FindOfDay)

local FindOfDayService = {}

FindOfDayService.Topic = "TerraForgeFindOfDay"
FindOfDayService.MapName = "TerraForgeFindOfDay"
FindOfDayService.Expiry = 2 * 86400 -- seconds a day's entry lives in the MemoryStore
FindOfDayService.SaveEvery = 30 -- seconds
FindOfDayService.RefreshEvery = 300 -- seconds
FindOfDayService.SubscribeRetry = { First = 5, Max = 300 }

local best: FindOfDay.Entry? = nil
local dirty = false

-- (tests) the wall clock, the cross-server calls, the hidden list
FindOfDayService.clock = os.time

function FindOfDayService.online(): boolean
	return not RunService:IsStudio()
end

function FindOfDayService.keyOf(day: number): string
	return `Day{day}`
end

function FindOfDayService.publish(entry: FindOfDay.Entry)
	game:GetService("MessagingService"):PublishAsync(FindOfDayService.Topic, entry)
end

--[[
	UpdateAsync on the day's key: `merge(stored) -> what to store, or nil to
	keep what is stored` (no write then). Expires after Expiry seconds.
]]
function FindOfDayService.update(day: number, merge: (any) -> any)
	local map = game:GetService("MemoryStoreService"):GetSortedMap(FindOfDayService.MapName)
	map:UpdateAsync(FindOfDayService.keyOf(day), function(old: any): any
		return merge(old)
	end, FindOfDayService.Expiry)
end

function FindOfDayService.read(day: number): any
	local map = game:GetService("MemoryStoreService"):GetSortedMap(FindOfDayService.MapName)
	return (map:GetAsync(FindOfDayService.keyOf(day)))
end

-- Is this player on the hidden list (LeaderboardService, looked up on use; false when it isn't there)?
function FindOfDayService.isHidden(userId: number): boolean
	local ok, hidden = pcall(function()
		local LeaderboardService = require(script.Parent.LeaderboardService) :: any
		return LeaderboardService.isHidden(userId)
	end)
	return ok and hidden == true
end

function FindOfDayService.setAttribute(name: string, value: any)
	Workspace:SetAttribute(name, value)
end

local function show()
	local entry = best
	FindOfDayService.setAttribute("FindOfDayDay", if entry then entry.Day else nil)
	FindOfDayService.setAttribute("FindOfDayUser", if entry then entry.UserId else nil)
	FindOfDayService.setAttribute("FindOfDayName", if entry then entry.Name else nil)
	FindOfDayService.setAttribute("FindOfDayOre", if entry then entry.Ore else nil)
	FindOfDayService.setAttribute("FindOfDayGrade", if entry then entry.Grade else nil)
end

--[[
	An entry from anywhere: takes it if it beats today's best (`own`: this
	server's find, it must be better; another server's or the store's: as good
	or better). True if it did. Taking another's drops this server's waiting
	find (it was worse): nothing to write or send again.
]]
local function offer(entry: FindOfDay.Entry?, own: boolean): boolean
	if not entry or FindOfDayService.isHidden(entry.UserId) then
		return false
	end
	local today = FindOfDay.day(FindOfDayService.clock())
	local takes = if own then FindOfDay.better(entry, best, today) else FindOfDay.atLeast(entry, best, today)
	if not takes then
		return false
	end
	best = entry
	dirty = own
	show()
	return true
end

-- The best now (nil: none today).
function FindOfDayService.current(): FindOfDay.Entry?
	local entry = best
	return if entry and entry.Day == FindOfDay.day(FindOfDayService.clock()) then entry else nil
end

-- See the header. Never yields.
function FindOfDayService.report(player: Player, oreId: any, grade: any)
	local name = player.DisplayName
	if type(name) ~= "string" then
		return
	end
	offer(
		FindOfDay.read({ Day = FindOfDay.day(FindOfDayService.clock()), UserId = player.UserId, Name = name, Ore = oreId, Grade = grade }),
		true
	)
end

-- A message from another server.
function FindOfDayService.receive(message: any)
	offer(FindOfDay.read(if type(message) == "table" then message.Data else nil), false)
end

-- One save round: see the header. Yields. (pcall'd by round)
function FindOfDayService.save()
	local entry = FindOfDayService.current()
	if not dirty or not entry then
		dirty = false
		return
	end
	dirty = false
	local day = entry.Day
	local kept: FindOfDay.Entry? = nil
	FindOfDayService.update(day, function(old: any): any
		local before = FindOfDay.read(old)
		if FindOfDay.better(entry, before, day) then
			kept = entry
			return entry
		end
		kept = before
		return nil -- the stored one stays (a tie too): no write
	end)
	if kept == entry then
		FindOfDayService.publish(entry)
	else
		offer(kept, false) -- the stored one is as good or better
	end
end

-- One read round. Yields. (pcall'd by round)
function FindOfDayService.refresh()
	offer(FindOfDay.read(FindOfDayService.read(FindOfDay.day(FindOfDayService.clock()))), false)
end

-- A new day: yesterday's best goes. True if it went.
function FindOfDayService.rollOver(): boolean
	local entry = best
	if entry and entry.Day ~= FindOfDay.day(FindOfDayService.clock()) then
		best = nil
		dirty = false
		show()
		return true
	end
	return false
end

--[[
	One loop round, SaveEvery seconds after the last (`sinceRefresh`: seconds
	since the last read; returns the new count): roll over, save (a failed save
	is tried again next round), read every RefreshEvery. Never throws.
]]
function FindOfDayService.round(sinceRefresh: number): number
	local since = sinceRefresh + FindOfDayService.SaveEvery
	FindOfDayService.rollOver()
	local saved, saveErr = pcall(function()
		FindOfDayService.save()
	end)
	if not saved then
		dirty = FindOfDayService.current() ~= nil -- again next round
		warn(`[FindOfDayService] saving today's best failed: {saveErr}`)
	end
	if since >= FindOfDayService.RefreshEvery then
		since = 0
		local read, readErr = pcall(function()
			FindOfDayService.refresh()
		end)
		if not read then
			warn(`[FindOfDayService] reading today's best failed: {readErr}`)
		end
	end
	return since
end

-- (tests)
function FindOfDayService.reset()
	best = nil
	dirty = false
	show()
end

function FindOfDayService.isDirty(): boolean
	return dirty
end

function FindOfDayService.init() end

-- (tests) the wait between rounds; the loop runs while it returns true
FindOfDayService.wait = function(seconds: number): boolean
	task.wait(seconds)
	return true
end

function FindOfDayService.start()
	if not FindOfDayService.online() then
		task.spawn(function()
			while FindOfDayService.wait(FindOfDayService.SaveEvery) do
				FindOfDayService.rollOver()
			end
		end)
		return
	end
	task.spawn(function()
		local wait = FindOfDayService.SubscribeRetry.First
		while true do
			local ok, err = pcall(function()
				game:GetService("MessagingService"):SubscribeAsync(FindOfDayService.Topic, FindOfDayService.receive)
			end)
			if ok then
				return
			end
			warn(`[FindOfDayService] listening to the other servers failed (again in {wait} s): {err}`)
			task.wait(wait)
			wait = math.min(wait * 2, FindOfDayService.SubscribeRetry.Max)
		end
	end)
	-- the last find of a closing server is written (the next round never comes)
	pcall(function()
		game:BindToClose(function()
			pcall(function()
				FindOfDayService.save()
			end)
		end)
	end)
	task.spawn(function()
		local ok, err = pcall(function()
			FindOfDayService.refresh()
		end)
		if not ok then
			warn(`[FindOfDayService] reading today's best failed: {err}`)
		end
		local sinceRefresh = 0
		while FindOfDayService.wait(FindOfDayService.SaveEvery) do
			sinceRefresh = FindOfDayService.round(sinceRefresh)
		end
	end)
end

return FindOfDayService
