--[[
	DataService: loads, autosaves and releases player data.

	- Session locking, retries and safe writes live in Data/ProfileStore.
	- Autosave every GameConfig.AutosaveInterval seconds.
	- On leave: other services get a chance to write last changes
	  (DataService.beforeRelease), then the profile is saved and unlocked.
	- On server shutdown (BindToClose) every profile is released in parallel.
	- In Studio without "Enable Studio Access to API Services", data lives in
	  memory only (a warning is printed) so you can still test.

	Other services: DataService.get(player) -> data table or nil (not loaded yet).
	After changing data call DataService.changed(player) so the client HUD updates.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local DataTemplate = require(script.Parent.Parent.Data.DataTemplate)
local Migrations = require(script.Parent.Parent.Data.Migrations)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)

local DataService = {}

local STORE_NAME = "TerraForge_PlayerData_v1"
local MAX_PURCHASE_IDS = 100

local profiles: { [Player]: ProfileStore.Profile } = {}
local loading: { [Player]: boolean } = {}
-- userId -> true while that user's final save is still being written.
-- A quick rejoin to the same server waits for it (no rollback).
local releasing: { [number]: boolean } = {}
local inFlight = 0 -- final saves in progress (BindToClose waits for these)
local loadedCallbacks: { (Player, { [string]: any }) -> ...any } = {}
local releaseCallbacks: { (Player, { [string]: any }) -> ...any } = {}
local changedCallbacks: { (Player) -> ...any } = {}
local shuttingDown = false
local store: any = nil
local inMemory = false

---------------------------------------------------------------- in-memory fallback

local MemoryStore = {}
MemoryStore.__index = MemoryStore
function MemoryStore.new()
	return setmetatable({ values = {} }, MemoryStore)
end
function MemoryStore.UpdateAsync(self: any, key: string, transform: (any) -> any)
	local result = transform(ProfileStore.deepCopy(self.values[key]))
	if result ~= nil then
		self.values[key] = ProfileStore.deepCopy(result)
	end
	return result
end

local function migrate(data: { [string]: any })
	-- Version 1 is the first release; Data/Migrations brings saves up to date.
	if type(data.Version) ~= "number" then
		data.Version = 1
	end
	-- keep the purchase history bounded
	local ids = {}
	for id, time in data.Purchases do
		table.insert(ids, { id = id, time = tonumber(time) or 0 })
	end
	if #ids > MAX_PURCHASE_IDS then
		table.sort(ids, function(a, b)
			return a.time > b.time
		end)
		for i = MAX_PURCHASE_IDS + 1, #ids do
			data.Purchases[ids[i].id] = nil
		end
	end
	-- type clean-up and version bump (idempotent, runs on every load)
	local report = Migrations.run(data)
	if report.Moved > 0 or report.Dropped > 0 then
		warn(`[DataService] save repaired: {report.Moved} moved, {report.Dropped} dropped`)
	end
end

local function waitForBudget()
	local waited = 0
	while
		not inMemory
		and DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1
		and waited < 20
	do
		task.wait(0.5)
		waited += 0.5
	end
end

local profileStore: any = nil

local function key(player: Player): string
	return "Player_" .. player.UserId
end

---------------------------------------------------------------- public API

function DataService.get(player: Player): { [string]: any }?
	local profile = profiles[player]
	if profile and not profile.Released then
		return profile.Data
	end
	return nil
end

function DataService.isLoaded(player: Player): boolean
	return DataService.get(player) ~= nil
end

-- Yields until the player's data is loaded (or timeout / player left).
function DataService.waitFor(player: Player, timeout: number?): { [string]: any }?
	local limit = timeout or 30
	local waited = 0
	while waited < limit and player.Parent do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.25)
		waited += 0.25
	end
	return DataService.get(player)
end

function DataService.onLoaded(callback: (Player, { [string]: any }) -> ...any)
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		if not profile.Released then
			task.spawn(callback, player, profile.Data)
		end
	end
end

-- Called (in order) right before a leaving player's data is saved for the last time.
function DataService.beforeRelease(callback: (Player, { [string]: any }) -> ...any)
	table.insert(releaseCallbacks, callback)
end

function DataService.onChanged(callback: (Player) -> ...any)
	table.insert(changedCallbacks, callback)
end

function DataService.changed(player: Player)
	for _, callback in changedCallbacks do
		task.spawn(callback, player)
	end
end

-- Saves right now (used after purchases). Returns true when the write succeeded.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or profile.Released then
		return false
	end
	return profileStore:save(profile, false)
end

function DataService.isInMemory(): boolean
	return inMemory
end

---------------------------------------------------------------- lifecycle

local function runReleaseCallbacks(player: Player, profile: ProfileStore.Profile)
	for _, callback in releaseCallbacks do
		local ok, err = pcall(callback, player, profile.Data)
		if not ok then
			warn("[DataService] beforeRelease callback failed: " .. tostring(err))
		end
	end
end

local function loadPlayer(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	-- rejoined while the last session is still saving: wait for it first
	local waited = 0
	while releasing[player.UserId] and waited < 40 and player.Parent do
		task.wait(0.25)
		waited += 0.25
	end
	local profile, reason = profileStore:load(key(player))
	loading[player] = nil
	if not profile then
		warn(`[DataService] could not load {player.Name}: {reason}`)
		if player.Parent then
			if reason == "locked" then
				player:Kick("Your Terra Forge data is still being saved on another server. Please rejoin in a minute.")
			else
				player:Kick("Terra Forge could not load your data (Roblox servers are busy). Please rejoin.")
			end
		end
		return
	end
	if not player.Parent or shuttingDown then
		-- left while loading: put the lock back right away
		profileStore:save(profile, true)
		return
	end
	profiles[player] = profile
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile.Data)
	end
	DataService.changed(player)
end

-- Final save with a few retries. Keeps `releasing` set until it is done.
local function finalSave(userId: number, profile: ProfileStore.Profile)
	releasing[userId] = true
	inFlight += 1
	local ok = false
	for attempt = 1, 4 do
		if profile.Released or profile.SessionLost then
			ok = true
			break
		end
		ok = profileStore:save(profile, true)
		if ok or profile.SessionLost then
			break
		end
		task.wait(2 * attempt)
	end
	if not ok then
		warn("[DataService] final save failed for user " .. userId)
	end
	inFlight -= 1
	releasing[userId] = nil
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	runReleaseCallbacks(player, profile)
	profiles[player] = nil
	if not profile.Released then
		finalSave(player.UserId, profile)
	end
end

function DataService.init()
	local isStudio = RunService:IsStudio()
	if isStudio and not GameConfig.SaveInStudio then
		inMemory = true
	else
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if ok then
			store = result
			-- Studio without API access fails on the first request, so probe once.
			if isStudio then
				local probeOk = pcall(function()
					(store :: any):GetAsync("__probe")
				end)
				if not probeOk then
					inMemory = true
				end
			end
		else
			inMemory = true
		end
	end
	if inMemory then
		store = MemoryStore.new()
		warn("[DataService] DataStores unavailable: progress is NOT saved in this session. (Studio: Game Settings > Security > Enable Studio Access to API Services)")
	end

	profileStore = ProfileStore.new({
		Store = store,
		JobId = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(math.random(1, 1e9)),
		Template = DataTemplate,
		Now = os.time,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
		BeforeRequest = waitForBudget,
		StaleLockSeconds = math.max(600, GameConfig.AutosaveInterval * 5),
		Migrate = migrate,
	})

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	game:BindToClose(function()
		shuttingDown = true
		for player, profile in profiles do
			task.spawn(function()
				runReleaseCallbacks(player, profile)
				profiles[player] = nil
				if not profile.Released then
					finalSave(player.UserId, profile)
				end
			end)
		end
		-- wait for every final save, including players who left just before
		-- the shutdown (Roblox allows ~30 seconds here)
		task.wait()
		local waited = 0
		while inFlight > 0 and waited < 27 do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

function DataService.start()
	-- autosave, spread out so all players are not saved in the same second
	while true do
		task.wait(GameConfig.AutosaveInterval)
		local list = {}
		for player in profiles do
			table.insert(list, player)
		end
		local gap = if #list > 0 then math.min(5, GameConfig.AutosaveInterval / (#list + 1)) else 0
		for _, player in list do
			local profile = profiles[player]
			if profile and not profile.Released and not shuttingDown then
				task.spawn(function()
					profileStore:save(profile, false)
					if profile.SessionLost and player.Parent then
						player:Kick("Your Terra Forge session was opened on another server.")
					end
				end)
			end
			task.wait(gap)
		end
	end
end

return DataService
