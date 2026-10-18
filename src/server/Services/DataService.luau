--[[
	DataService: loads, autosaves and releases player data.

	- Session locking, retries and safe writes live in Data/ProfileStore.
	- Autosave every GameConfig.AutosaveInterval seconds.
	- On leave: other services get a chance to write last changes
	  (DataService.beforeRelease), then the profile is saved and unlocked.
	- On server shutdown (BindToClose) every profile is released in parallel;
	  the wait counts every release from its first callback and every load
	  still running (a player who left while loading is put back too), and
	  the stores go urgent (fewer retries, short pauses) to fit the time.
	- Session locking details (docs/SAVE_AUDIT.md): a SessionId per load,
	  malformed / newer saves refused untouched, unstorable values repaired
	  at their path (ProfileStore). A load that fails kicks the player
	  (DataService.kickText): nobody plays on the template. The autosave also
	  refreshes the lock; GameConfig.StaleLockSeconds without one = a crashed
	  server.
	- Studio saves into its own store (DataService.storeName) unless
	  GameConfig.StudioLiveData; test players (UserId <= 0) live in memory.
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
local STUDIO_STORE_NAME = "TerraForge_PlayerData_Studio"
local MAX_PURCHASE_IDS = 100
local PURCHASE_KEEP_SECONDS = 30 * 86400 -- receipt ids younger than this are never trimmed

local profiles: { [Player]: ProfileStore.Profile } = {}
local loading: { [Player]: boolean } = {}
-- userId -> true while that user's final save is still being written.
-- A quick rejoin to the same server waits for it (no rollback).
local releasing: { [number]: boolean } = {}
local closing: { [any]: boolean } = {} -- profiles whose release has started (never twice)
local inFlight = 0 -- loads and releases in progress (BindToClose waits for these)
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

-- The DataStore for this server: Studio gets its own unless `live` (GameConfig.StudioLiveData).
function DataService.storeName(isStudio: boolean, live: boolean): string
	return if isStudio and not live then STUDIO_STORE_NAME else STORE_NAME
end

-- Is this user's data written to a DataStore? Studio test players (UserId <= 0) stay in memory.
function DataService.persists(userId: number): boolean
	return userId > 0
end

-- What a player whose save couldn't be loaded is told (ProfileStore.load reasons).
function DataService.kickText(reason: string?): string
	if reason == "locked" then
		return "Your Terra Forge data is still being saved on another server. Please rejoin in a minute."
	elseif reason == "newer" then
		return "The game just updated, please rejoin"
	elseif reason == "malformed" then
		return "Terra Forge couldn't read your save safely, so nothing was changed. Please rejoin later."
	elseif type(reason) == "string" and string.sub(reason, 1, 15) == "error: migrate:" then
		return "Terra Forge couldn't prepare your save, so nothing was changed. Please rejoin later."
	end
	return "Terra Forge could not load your data (Roblox servers are busy). Please rejoin."
end

--[[
	Keeps the purchase-id history bounded: the newest MAX_PURCHASE_IDS stay,
	and an id younger than PURCHASE_KEEP_SECONDS always stays (Roblox may
	still deliver that receipt again; the id is what stops a second grant).
	Returns false when `purchases` isn't a table (nothing to trim).
]]
function DataService.trimPurchases(purchases: any, now: number): boolean
	if type(purchases) ~= "table" then
		return false
	end
	local ids = {}
	for id, time in purchases do
		table.insert(ids, { id = id, time = tonumber(time) or 0 })
	end
	if #ids <= MAX_PURCHASE_IDS then
		return true
	end
	table.sort(ids, function(a, b)
		return a.time > b.time
	end)
	for i = MAX_PURCHASE_IDS + 1, #ids do
		if now - ids[i].time > PURCHASE_KEEP_SECONDS then
			purchases[ids[i].id] = nil
		end
	end
	return true
end

local function migrate(data: { [string]: any })
	-- Version 1 is the first release; Data/Migrations brings saves up to date.
	if type(data.Version) ~= "number" then
		data.Version = 1
	end
	-- keep the purchase history bounded
	if not DataService.trimPurchases(data.Purchases, os.time()) then
		warn("[DataService] Purchases was not a table: reset")
		data.Purchases = {}
	end
	-- type clean-up and version bump (idempotent, runs on every load)
	local report = Migrations.run(data)
	if report.Moved > 0 or report.Dropped > 0 then
		warn(`[DataService] save repaired: {report.Moved} moved, {report.Dropped} dropped`)
	end
end

local function waitForBudget()
	local waited = 0
	local limit = if shuttingDown then 3 else 20 -- at shutdown every second counts
	while not inMemory and DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 and waited < limit do
		task.wait(0.5)
		waited += 0.5
	end
end

local profileStore: any = nil -- the DataStore (or memory when DataStores are unavailable)
local memoryProfileStore: any = nil -- test players (UserId <= 0): never a real store

-- The store a user's profile lives in.
local function storeFor(userId: number): any
	return if DataService.persists(userId) then profileStore else memoryProfileStore
end

-- Logs what ProfileStore.repair had to fix before a save (the save still goes through).
local function onRepair(profileKey: string, problems: { ProfileStore.Problem })
	local lines = {}
	for _, problem in problems do
		table.insert(lines, `{problem.Path}: {problem.Problem}`)
	end
	warn(`[DataService] {profileKey}: repaired before saving: {table.concat(lines, "; ")}`)
end

local function makeStore(dataStore: any, budget: boolean): any
	return ProfileStore.new({
		Store = dataStore,
		JobId = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(math.random(1, 1e9)),
		Template = DataTemplate,
		Now = os.time,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
		BeforeRequest = if budget then waitForBudget else nil,
		StaleLockSeconds = GameConfig.StaleLockSeconds,
		Migrate = migrate,
		LatestVersion = Migrations.Latest,
		OnRepair = onRepair,
	})
end

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
	return storeFor(player.UserId):save(profile, false)
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

-- Final save with a few retries (fewer and quicker at shutdown). The caller counts it in inFlight.
local function finalSave(userId: number, profile: ProfileStore.Profile)
	local store = storeFor(userId)
	local attempts = if shuttingDown then 2 else 4
	local ok = false
	for attempt = 1, attempts do
		if profile.Released or profile.SessionLost then
			ok = true
			break
		end
		ok = store:save(profile, true)
		if ok or profile.SessionLost then
			break
		end
		if attempt < attempts then
			task.wait(if shuttingDown then 0.5 else 2 * attempt)
		end
	end
	if not ok then
		warn("[DataService] final save failed for user " .. userId)
	end
end

-- The callbacks and the final save of one profile, counted in inFlight from the very start.
local function release(player: Player, profile: ProfileStore.Profile)
	if closing[profile] then
		return
	end
	closing[profile] = true
	local userId = player.UserId
	releasing[userId] = true
	inFlight += 1
	runReleaseCallbacks(player, profile)
	if profiles[player] == profile then
		profiles[player] = nil
	end
	if not profile.Released then
		finalSave(userId, profile)
	end
	closing[profile] = nil
	inFlight -= 1
	releasing[userId] = nil
end

local function loadPlayer(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	inFlight += 1 -- a load running at shutdown is waited for (and put back)
	-- rejoined while the last session is still saving: wait for it first
	local waited = 0
	while releasing[player.UserId] and waited < 40 and player.Parent do
		task.wait(0.25)
		waited += 0.25
	end
	local store = storeFor(player.UserId)
	local called, profile, reason = pcall(store.load, store, key(player))
	loading[player] = nil
	if not called then
		reason = "error: " .. tostring(profile)
		profile = nil
	end
	if not profile then
		warn(`[DataService] could not load {player.Name}: {reason}`)
		if player.Parent then
			player:Kick(DataService.kickText(reason))
		end
		inFlight -= 1
		return
	end
	if not player.Parent or shuttingDown then
		-- left while loading (or the server is closing): put the lock back right away
		finalSave(player.UserId, profile)
		inFlight -= 1
		return
	end
	profiles[player] = profile
	inFlight -= 1
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile.Data)
	end
	DataService.changed(player)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	if profile then
		release(player, profile)
	end
end

-- BindToClose: every profile released in parallel; waits for those and for loads still running.
local function shutdown()
	shuttingDown = true
	for _, store in { profileStore, memoryProfileStore } do
		if store then
			store:setUrgent(true)
		end
	end
	for player, profile in profiles do
		task.spawn(release, player, profile)
	end
	-- Roblox allows ~30 seconds here
	task.wait()
	local waited = 0
	while inFlight > 0 and waited < 27 do
		task.wait(0.25)
		waited += 0.25
	end
end

function DataService.init()
	local isStudio = RunService:IsStudio()
	if isStudio and not GameConfig.SaveInStudio then
		inMemory = true
	else
		local name = DataService.storeName(isStudio, GameConfig.StudioLiveData == true)
		if isStudio then
			print(`[DataService] Studio saves into the DataStore "{name}"`)
		end
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(name)
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
		warn(
			"[DataService] DataStores unavailable: progress is NOT saved in this session. (Studio: Game Settings > Security > Enable Studio Access to API Services)"
		)
	end

	profileStore = makeStore(store, not inMemory)
	memoryProfileStore = makeStore(MemoryStore.new(), false)

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	game:BindToClose(shutdown)
end

function DataService.start()
	-- autosave, spread over the interval so all players are not saved in the
	-- same second; one round takes AutosaveInterval, so every player's lock is
	-- refreshed about that often (well inside GameConfig.StaleLockSeconds)
	while true do
		local list = {}
		for player in profiles do
			table.insert(list, player)
		end
		local gap = GameConfig.AutosaveInterval / (#list + 1)
		task.wait(gap)
		for _, player in list do
			local profile = profiles[player]
			if profile and not profile.Released and not shuttingDown then
				task.spawn(function()
					storeFor(player.UserId):save(profile, false)
					if profile.SessionLost and player.Parent then
						player:Kick("Your Terra Forge session was opened on another server.")
					end
				end)
			end
			task.wait(gap)
		end
	end
end

-- Internals for the Lune tests only (tests/SaveSafety.spec.luau).
DataService._test = {
	loadPlayer = loadPlayer,
	releasePlayer = releasePlayer,
	shutdown = shutdown,
	inFlight = function(): number
		return inFlight
	end,
	-- Runs `fn` with `store` as the DataStore profile store and a clean state, then puts everything back.
	isolate = function(store: any, fn: () -> ())
		local saved = {
			profileStore,
			memoryProfileStore,
			profiles,
			loading,
			releasing,
			closing,
			inFlight,
			shuttingDown,
			inMemory,
			loadedCallbacks,
			releaseCallbacks,
			changedCallbacks,
		}
		profileStore = store
		memoryProfileStore = ProfileStore.new({
			Store = MemoryStore.new() :: any,
			JobId = "test-memory",
			Template = DataTemplate,
			Now = os.time,
			Wait = function(seconds: number)
				task.wait(math.min(seconds, 0.01))
			end,
			StaleLockSeconds = GameConfig.StaleLockSeconds,
			LatestVersion = Migrations.Latest,
		})
		profiles, loading, releasing, closing = {}, {}, {}, {}
		inFlight, shuttingDown, inMemory = 0, false, false
		loadedCallbacks, releaseCallbacks, changedCallbacks = {}, {}, {}
		local ok, err = pcall(fn :: any)
		profileStore, memoryProfileStore = saved[1], saved[2]
		profiles, loading, releasing, closing = saved[3], saved[4], saved[5], saved[6]
		inFlight, shuttingDown, inMemory = saved[7], saved[8], saved[9]
		loadedCallbacks, releaseCallbacks, changedCallbacks = saved[10], saved[11], saved[12]
		if not ok then
			error(err, 0)
		end
	end,
}

return DataService
