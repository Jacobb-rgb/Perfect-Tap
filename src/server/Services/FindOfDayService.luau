--[[
	FindOfDayService: the best ore cleaned today on any server (owner 2026-11-07,
	Events/FindOfDay), shown only on the big iron billboard.

	- report(player, oreId, grade): CleaningService (a player's own cleaning) and
	  ProcessingService (a machine's) call it for every clean ore. No yields:
	  a better find becomes the best at once (Workspace attributes FindOfDay*,
	  which the clients read) and is written out by the next save round.
	- Every SaveEvery seconds, if there is a new best here: DataStore UpdateAsync
	  (key = the UTC day; the better of what is stored and ours stays) and one
	  MessagingService message to the other servers. Every RefreshEvery seconds
	  the stored best is read, for a server that started late or missed one.
	- A new UTC day starts empty. Only a DisplayName and an ore id leave the
	  server (docs/COMPLIANCE.md). Nothing is saved in a player's save.
	- In Studio nothing is stored or sent (the test hooks can swap both).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FindOfDay = require(Shared.Events.FindOfDay)

local FindOfDayService = {}

FindOfDayService.Topic = "TerraForgeFindOfDay"
FindOfDayService.StoreName = "TerraForgeFindOfDay"
FindOfDayService.SaveEvery = 30 -- seconds
FindOfDayService.RefreshEvery = 300 -- seconds
FindOfDayService.SubscribeRetry = { First = 5, Max = 300 }

local best: FindOfDay.Entry? = nil
local dirty = false

-- (tests) the wall clock, the cross-server calls
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

-- UpdateAsync on the day's key: `merge(stored) -> what to store`; returns what is stored now.
function FindOfDayService.update(day: number, merge: (any) -> any): any
	local store = game:GetService("DataStoreService"):GetDataStore(FindOfDayService.StoreName)
	return store:UpdateAsync(FindOfDayService.keyOf(day), merge)
end

function FindOfDayService.read(day: number): any
	local store = game:GetService("DataStoreService"):GetDataStore(FindOfDayService.StoreName)
	return (store:GetAsync(FindOfDayService.keyOf(day)))
end

function FindOfDayService.setAttribute(name: string, value: any)
	Workspace:SetAttribute(name, value)
end

local function show()
	local entry = best
	FindOfDayService.setAttribute("FindOfDayDay", if entry then entry.Day else nil)
	FindOfDayService.setAttribute("FindOfDayName", if entry then entry.Name else nil)
	FindOfDayService.setAttribute("FindOfDayOre", if entry then entry.Ore else nil)
	FindOfDayService.setAttribute("FindOfDayGrade", if entry then entry.Grade else nil)
end

-- An entry from anywhere: takes it if it beats today's best. True if it did.
local function offer(entry: FindOfDay.Entry?): boolean
	if not entry or not FindOfDay.better(entry, best, FindOfDay.day(FindOfDayService.clock())) then
		return false
	end
	best = entry
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
	local entry = FindOfDay.read({ Day = FindOfDay.day(FindOfDayService.clock()), Name = name, Ore = oreId, Grade = grade })
	if offer(entry) then
		dirty = true
	end
end

-- A message from another server.
function FindOfDayService.receive(message: any)
	offer(FindOfDay.read(if type(message) == "table" then message.Data else nil))
end

-- One save round: see the header. Yields. (pcall'd by the loop)
function FindOfDayService.save()
	local entry = FindOfDayService.current()
	if not dirty or not entry then
		dirty = false
		return
	end
	dirty = false
	local day = entry.Day
	local stored = FindOfDayService.update(day, function(old: any): any
		local before = FindOfDay.read(old)
		return if FindOfDay.better(entry, before, day) then entry else before
	end)
	local kept = FindOfDay.read(stored)
	if kept and kept.Name == entry.Name and kept.Ore == entry.Ore and kept.Grade == entry.Grade then
		FindOfDayService.publish(entry)
	else
		offer(kept) -- another server's is better
	end
end

-- One read round. Yields. (pcall'd by the loop)
function FindOfDayService.refresh()
	offer(FindOfDay.read(FindOfDayService.read(FindOfDay.day(FindOfDayService.clock()))))
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

function FindOfDayService.start()
	if not FindOfDayService.online() then
		task.spawn(function()
			while true do
				task.wait(FindOfDayService.SaveEvery)
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
	task.spawn(function()
		local ok, err = pcall(function()
			FindOfDayService.refresh()
		end)
		if not ok then
			warn(`[FindOfDayService] reading today's best failed: {err}`)
		end
		local sinceRefresh = 0
		while true do
			task.wait(FindOfDayService.SaveEvery)
			sinceRefresh += FindOfDayService.SaveEvery
			FindOfDayService.rollOver()
			local saved, saveErr = pcall(function()
				FindOfDayService.save()
			end)
			if not saved then
				dirty = true -- again next round
				warn(`[FindOfDayService] saving today's best failed: {saveErr}`)
			end
			if sinceRefresh >= FindOfDayService.RefreshEvery then
				sinceRefresh = 0
				local read, readErr = pcall(function()
					FindOfDayService.refresh()
				end)
				if not read then
					warn(`[FindOfDayService] reading today's best failed: {readErr}`)
				end
			end
		end
	end)
end

return FindOfDayService
