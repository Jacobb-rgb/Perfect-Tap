--[[
	DataService: loads, autosaves and releases player data.

	- Session locking, retries and safe writes live in Data/ProfileStore.
	- Autosave: each profile saves AutosaveInterval after its last save
	  (checked every AUTOSAVE_CHECK seconds; the save also refreshes the
	  lock). A failed save is warned about and tried again after
	  AUTOSAVE_RETRY. A save that finds the session lost (any save:
	  autosave, saveNow) kicks the player.
	- One load per user on this server; a load stops (and never takes a
	  lock) once its player left or the server is closing. A rejoin waits up
	  to RELEASE_WAIT for its last session's final save and is told to
	  rejoin later if it is still running (it never loads an older copy).
	- Release: no autosave once it started; the beforeRelease callbacks get
	  CALLBACK_LIMIT seconds, then the final save starts anyway.
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

local LEGACY_STALE_SECONDS = 600 -- locks of servers from before the SessionId (their autosave ran every ~160-195 s)
local RELEASE_WAIT = 40 -- a rejoin waits this long for its last session's final save, then is told to rejoin later
local CALLBACK_LIMIT = 5 -- seconds the beforeRelease callbacks get before the final save starts anyway
local AUTOSAVE_CHECK = 5 -- seconds between autosave checks (each profile saves AutosaveInterval after its last save)
local AUTOSAVE_RETRY = 15 -- a failed autosave (the lock refresh) is tried again this soon
local SESSION_LOST_TEXT = "Your Terra Forge session was opened on another server."

local profiles: { [Player]: ProfileStore.Profile } = {}
local loading: { [number]: boolean } = {} -- userId -> a load is running (one per user on this server)
-- userId -> final saves of that user still being written (a counter: two
-- quick sessions can release at once). A rejoin to the same server waits.
local releasing: { [number]: number } = {}
local closing: { [any]: number } = {} -- profile -> clock() its release started (never twice, no autosave)
local nextSave: { [any]: number } = {} -- profile -> clock() of its next autosave
local inFlight = 0 -- loads and releases in progress (BindToClose waits for these)
local clock = os.clock -- (swappable in the Lune tests)
local random = math.random -- (swappable in the Lune tests: the first autosave's offset)
local releaseWait = RELEASE_WAIT -- (shorter in the Lune tests)
local callbackLimit = CALLBACK_LIMIT -- (shorter in the Lune tests)
local pause = function(seconds: number)
	task.wait(seconds)
end
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
		return "Your Terra Forge data is still being saved. Please rejoin in a minute."
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

-- The highest save Version this server understands. DataTemplate.Version and
-- Migrations.Latest must be equal (tests/SaveSafety.spec checks it); the max
-- keeps a slip from refusing this server's own saves.
function DataService.latestVersion(): number
	return math.max(DataTemplate.Version, Migrations.Latest)
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
		LegacyStaleSeconds = LEGACY_STALE_SECONDS,
		Migrate = migrate,
		LatestVersion = DataService.latestVersion(),
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

-- After any save: a session another server took over ends here (the player is told and leaves).
local function afterSave(player: Player, profile: ProfileStore.Profile, ok: boolean)
	if not ok and profile.SessionLost and player.Parent then
		player:Kick(SESSION_LOST_TEXT)
	end
end

-- Saves right now (used after purchases). Returns true when the write succeeded.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or profile.Released then
		return false
	end
	local ok = storeFor(player.UserId):save(profile, false)
	if ok then
		nextSave[profile] = clock() + GameConfig.AutosaveInterval
	end
	afterSave(player, profile, ok)
	return ok
end

function DataService.isInMemory(): boolean
	return inMemory
end

---------------------------------------------------------------- lifecycle

-- The beforeRelease callbacks, in order, at most CALLBACK_LIMIT seconds in all (the final save must start).
local function runReleaseCallbacks(player: Player, profile: ProfileStore.Profile)
	local done = false
	task.spawn(function()
		for _, callback in releaseCallbacks do
			local ok, err = pcall(callback, player, profile.Data)
			if not ok then
				warn("[DataService] beforeRelease callback failed: " .. tostring(err))
			end
		end
		done = true
	end)
	local waited = 0
	while not done and waited < callbackLimit do
		task.wait(0.05)
		waited += 0.05
	end
	if not done then
		warn(`[DataService] beforeRelease callbacks of {player.Name} took over {callbackLimit} s: saving anyway`)
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
			pause(if shuttingDown then 0.5 else 2 * attempt)
		end
	end
	if not ok then
		warn("[DataService] final save failed for user " .. userId)
		-- give up on it here: a rejoin may load the last stored copy
		store:forget(profile)
	end
end

-- Has every running release of this user been going for longer than a lock can live?
local function releaseHung(userId: number): boolean
	local any = false
	local name = "Player_" .. userId
	for profile, started in closing do
		if profile.Key == name then
			any = true
			if clock() - started < GameConfig.StaleLockSeconds then
				return false
			end
		end
	end
	return any
end

local function addReleasing(userId: number, delta: number)
	local n = (releasing[userId] or 0) + delta
	if n > 0 then
		releasing[userId] = n
	else
		releasing[userId] = nil
	end
end

-- The callbacks and the final save of one profile, counted in inFlight from the very start.
local function release(player: Player, profile: ProfileStore.Profile)
	if closing[profile] then
		return
	end
	closing[profile] = clock() -- no autosave from here on (the callbacks may still yield)
	nextSave[profile] = nil
	local userId = player.UserId
	addReleasing(userId, 1)
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
	addReleasing(userId, -1)
end

local function loadPlayer(player: Player)
	if profiles[player] then
		return
	end
	local userId = player.UserId
	inFlight += 1 -- a load running at shutdown is waited for (and put back)
	local function finish()
		inFlight -= 1
	end
	-- one load per user: an earlier Player object of this user (left and
	-- rejoined while loading) stops its load once it sees it has left
	while loading[userId] and player.Parent do
		task.wait(0.25)
	end
	if loading[userId] or not player.Parent or profiles[player] then
		finish()
		return
	end
	loading[userId] = true
	-- rejoined while the last session is still saving: wait for it; never load past it
	local waited = 0
	while releasing[userId] and not releaseHung(userId) and waited < releaseWait and player.Parent do
		task.wait(0.25)
		waited += 0.25
	end
	if not player.Parent then
		loading[userId] = nil
		finish()
		return
	end
	if releasing[userId] and releaseHung(userId) then
		-- a final save stuck for longer than a lock can live: give it up; load's lock rules decide
		for profile in closing do
			if profile.Key == key(player) then
				storeFor(userId):forget(profile)
			end
		end
		warn(`[DataService] {player.Name}: a final save has hung for over {GameConfig.StaleLockSeconds} s, given up`)
	elseif releasing[userId] then
		loading[userId] = nil
		warn(`[DataService] {player.Name} rejoined while their last save is still being written`)
		player:Kick(DataService.kickText("locked"))
		finish()
		return
	end
	local store = storeFor(userId)
	local function gone(): boolean
		return not player.Parent or shuttingDown
	end
	local called, profile, reason = pcall(store.load, store, key(player), gone)
	loading[userId] = nil
	if not called then
		reason = "error: " .. tostring(profile)
		profile = nil
	end
	if not profile then
		if reason ~= "gone" then
			warn(`[DataService] could not load {player.Name}: {reason}`)
			if player.Parent then
				player:Kick(DataService.kickText(reason))
			end
		end
		finish()
		return
	end
	if not player.Parent or shuttingDown then
		-- left (or the server started closing) after the lock was taken: put it back right away
		-- (counted like a release: releaseHung and the rejoin's give-up cover a hung put-back too)
		closing[profile] = clock()
		addReleasing(userId, 1)
		finalSave(userId, profile)
		addReleasing(userId, -1)
		closing[profile] = nil
		finish()
		return
	end
	profiles[player] = profile
	-- the first autosave somewhere in the next interval (spreads the players out)
	nextSave[profile] = clock() + GameConfig.AutosaveInterval * (0.5 + random() * 0.5)
	finish()
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

-- One autosave check: every profile whose time has come saves (it also
-- refreshes its lock). A failed save is warned about and tried again after
-- AUTOSAVE_RETRY; a lost session kicks the player.
local function autosaveStep(now: number)
	if shuttingDown then
		return
	end
	for player, profile in profiles do
		local due = nextSave[profile]
		if due and now >= due and not closing[profile] and not profile.Released and not profile.Saving and player.Parent then
			nextSave[profile] = now + GameConfig.AutosaveInterval
			task.spawn(function()
				local ok = storeFor(player.UserId):save(profile, false)
				if ok then
					if nextSave[profile] then
						nextSave[profile] = clock() + GameConfig.AutosaveInterval
					end
				elseif not profile.SessionLost then
					warn(`[DataService] autosave failed for {player.Name}: trying again in {AUTOSAVE_RETRY} s`)
					if nextSave[profile] then
						nextSave[profile] = clock() + AUTOSAVE_RETRY
					end
				end
				afterSave(player, profile, ok)
			end)
		end
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
	-- each profile saves AutosaveInterval after its last save (its own
	-- schedule, so a join right after a round never waits two rounds)
	while true do
		task.wait(AUTOSAVE_CHECK)
		autosaveStep(clock())
	end
end

-- Internals for the Lune tests only (tests/SaveSafety.spec.luau).
DataService._test = {
	loadPlayer = loadPlayer,
	releasePlayer = releasePlayer,
	shutdown = shutdown,
	autosaveStep = autosaveStep,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	-- shorter waits for the tests: the rejoin wait and the pauses between final-save attempts
	setRandom = function(fn: () -> number)
		random = fn
	end,
	setTimings = function(wait: number, pauseFn: (number) -> (), callbacks: number?)
		releaseWait = wait
		pause = pauseFn
		callbackLimit = callbacks or CALLBACK_LIMIT
	end,
	nextSave = function(player: Player): number?
		local profile = profiles[player]
		return if profile then nextSave[profile] else nil
	end,
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
			nextSave,
			clock,
			random,
			releaseWait,
			pause,
			callbackLimit,
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
		profiles, loading, releasing, closing, nextSave = {}, {}, {}, {}, {}
		inFlight, shuttingDown, inMemory = 0, false, false
		loadedCallbacks, releaseCallbacks, changedCallbacks = {}, {}, {}
		local ok, err = pcall(fn :: any)
		profileStore, memoryProfileStore = saved[1], saved[2]
		profiles, loading, releasing, closing, nextSave = saved[3], saved[4], saved[5], saved[6], saved[7]
		clock, random, releaseWait, pause, callbackLimit = saved[8], saved[9], saved[10], saved[11], saved[12]
		inFlight, shuttingDown, inMemory = saved[13], saved[14], saved[15]
		loadedCallbacks, releaseCallbacks, changedCallbacks = saved[16], saved[17], saved[18]
		if not ok then
			error(err, 0)
		end
	end,
}

return DataService
