--[[
	Session-locked player profiles on top of a DataStore (pure logic, no
	Roblox services, so it is unit-tested in Lune with a fake store).

	Saved value shape:
	  { Data = {...player data...}, Lock = { JobId, SessionId, Time }?, Saved = os.time() }

	Rules (docs/SAVE_AUDIT.md):
	- load(key, shouldStop?): takes the lock with UpdateAsync. If another
	  live session holds it, wait and retry (that server is probably still
	  saving the player who just hopped). A lock not refreshed for
	  StaleLockSeconds is from a crashed server and gets taken over; a younger
	  one never is (a live server with a slow final save keeps its session,
	  so nothing it still writes is lost). Old-format locks (no SessionId:
	  servers from before this code) count as stale only after
	  LegacyStaleSeconds (their autosave was every ~160-195 s). A lock time
	  more than FutureSlack seconds in the future (a broken clock) counts as
	  stale. A lock of this same server is taken at once only when its
	  session isn't live here any more (an earlier session whose final save
	  gave up: forget); a live one here is waited for like any other.
	  shouldStop() (the player left, the server is closing) ends the retries
	  and is checked again right before the lock would be written: a load
	  for someone who is gone never takes a lock ("gone").
	  Refused without writing anything (no lock taken):
	    "malformed"  a stored value that isn't { Data = table, ... }: never
	                 replaced with the template (the template is only for a
	                 key with nothing stored: a new player)
	    "newer"      Data.Version above LatestVersion: a save from a newer
	                 server must not be "repaired" by this older one
	  Every load gets its own SessionId (JobId + a counter): two sessions on
	  the same server are told apart. A loaded session stays live here (one
	  per key) until its release succeeds, it is lost or it is forgotten.
	  Migrate (and the template reconcile) run after the lock was taken; if
	  they throw, only our own lock is cleared again (data untouched) and
	  load returns nil, "error: migrate: ...".
	- save(): writes only while the stored lock is ours (the same
	  SessionId). Another session's lock, or no lock at all (someone took
	  the session over and already released it), means the session is lost:
	  nothing is written, profile.SessionLost. Refreshes the lock time.
	  repair() runs inside the UpdateAsync transform, on exactly the value
	  being written (a value changed while the request waited is repaired
	  too); OnRepair reports what it changed.
	- release(): final save that clears the lock.
	- forget(profile): DataService gave up on a session (its final save kept
	  failing): it no longer blocks a new session of the same key here.
	- Every DataStore call is retried with exponential backoff (shorter
	  while urgent: setUrgent, for server shutdown).

	storable(data) / repair(data): what a DataStore can't hold (or the game
	can't use), by path. A DataStore write fails as a whole for one value it
	can't hold, so one slip would block every save of that player; repair
	fixes it at its path instead:
	  NaN / inf                     -> 0 (Roblox stores them, but no reader can use them)
	  invalid UTF-8 text            -> dropped
	  userdata, functions, threads  -> dropped (Vector3, Instance, ...)
	  non-string, non-number keys   -> dropped
	  a list with gaps              -> closed up (the items keep their order)
	  a table with number and text keys -> the number keys become text
	  a table inside itself (a loop) -> the inner reference dropped
]]

export type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> any,
}

export type Problem = { Path: string, Problem: string }

export type Options = {
	Store: StoreLike,
	JobId: string,
	Template: { [string]: any },
	Now: () -> number,
	Wait: (seconds: number) -> (),
	BeforeRequest: (() -> ())?, -- e.g. wait for DataStore budget
	LockRetries: number?, -- how often load() retries while locked
	LockRetryDelay: number?, -- seconds between those retries
	StaleLockSeconds: number?, -- lock older than this = crashed server
	CallRetries: number?, -- retries per DataStore call on errors
	Migrate: ((data: { [string]: any }) -> ())?,
	LatestVersion: number?, -- saves with a higher Data.Version are refused ("newer")
	LegacyStaleSeconds: number?, -- stale age of an old-format lock (no SessionId), default 600
	OnRepair: ((key: string, problems: { Problem }) -> ())?, -- what repair() changed before a save
}

export type Profile = {
	Key: string,
	Data: { [string]: any },
	SessionId: string,
	Released: boolean,
	LoadedAt: number,
	LastSave: number,
	Saving: boolean,
	SessionLost: boolean,
}

local ProfileStore = {}
ProfileStore.__index = ProfileStore

ProfileStore.MaxDepth = 40 -- deeper tables are not stored (no save comes near it)
ProfileStore.MaxProblems = 25 -- reported per repair (the rest is still repaired)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end
ProfileStore.deepCopy = deepCopy

-- Adds missing template fields (recursively) without touching existing ones.
local function reconcile(data: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			-- only reconcile "record" tables, not maps/arrays that start empty
			local isRecord = true
			for k in value do
				if type(k) ~= "string" then
					isRecord = false
					break
				end
			end
			if isRecord then
				reconcile(data[key], value)
			end
		end
	end
end
ProfileStore.reconcile = reconcile

---------------------------------------------------------------- storable / repair

local function pathOf(path: string, key: any): string
	if type(key) == "number" then
		return `{path}[{key}]`
	end
	local text = tostring(key)
	return if path == "" then text else `{path}.{text}`
end

-- Walks `value` and fixes (fix = true) or only reports what a DataStore can't store.
local function walk(t: { [any]: any }, path: string, depth: number, ancestors: { [any]: boolean }, fix: boolean, problems: { Problem })
	local function report(at: string, problem: string)
		table.insert(problems, { Path = at, Problem = problem })
	end
	ancestors[t] = true
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	for _, k in keys do
		local v = t[k]
		local at = pathOf(path, k)
		local kk = type(k)
		if kk ~= "string" and kk ~= "number" then
			report(at, "a " .. kk .. " key")
			if fix then
				t[k] = nil
			end
			continue
		end
		if (kk == "string" and utf8.len(k) == nil) or (kk == "number" and k ~= k) then
			report(at, "a broken key")
			if fix then
				t[k] = nil
			end
			continue
		end
		local kind = type(v)
		if kind == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				report(at, "NaN or infinity (now 0)")
				if fix then
					t[k] = 0
				end
			end
		elseif kind == "string" then
			if utf8.len(v) == nil then
				report(at, "invalid text (dropped)")
				if fix then
					t[k] = nil
				end
			end
		elseif kind == "table" then
			if ancestors[v] then
				report(at, "a table inside itself (dropped)")
				if fix then
					t[k] = nil
				end
			elseif depth >= ProfileStore.MaxDepth then
				report(at, "nested too deep (dropped)")
				if fix then
					t[k] = nil
				end
			else
				walk(v, at, depth + 1, ancestors, fix, problems)
			end
		elseif kind ~= "boolean" then
			report(at, `a {typeof(v)} (dropped)`)
			if fix then
				t[k] = nil
			end
		end
	end
	ancestors[t] = nil
	-- the table's own shape: a list 1..n, or text keys only
	local numbers: { number } = {}
	local strings = 0
	for k in t do
		if type(k) == "number" then
			table.insert(numbers, k)
		elseif type(k) == "string" then
			strings += 1
		end
	end
	if #numbers == 0 then
		return
	end
	if strings > 0 then
		report(path, "number and text keys mixed (number keys now text)")
		if fix then
			for _, k in numbers do
				local text = tostring(k)
				if t[text] == nil then
					t[text] = t[k]
				else
					report(pathOf(path, k), "number key clashed with a text key (dropped)")
				end
				t[k] = nil
			end
		end
		return
	end
	table.sort(numbers)
	local isList = true
	for i, k in numbers do
		if k ~= i then
			isList = false
			break
		end
	end
	if not isList then
		report(path, "a list with gaps (closed up)")
		if fix then
			local values = {}
			for _, k in numbers do
				table.insert(values, t[k])
			end
			for _, k in numbers do
				t[k] = nil
			end
			for i, v in values do
				t[i] = v
			end
		end
	end
end

-- Can `data` be written to a DataStore as it is? Returns ok and the problems (paths).
function ProfileStore.storable(data: any): (boolean, { Problem })
	local problems: { Problem } = {}
	if type(data) == "table" then
		walk(data, "", 0, {}, false, problems)
	end
	return #problems == 0, problems
end

-- Makes `data` storable in place (see the header). Returns what it changed.
function ProfileStore.repair(data: any): { Problem }
	local problems: { Problem } = {}
	if type(data) == "table" then
		walk(data, "", 0, {}, true, problems)
	end
	return problems
end

---------------------------------------------------------------- the store

ProfileStore.FutureSlack = 60 -- a lock time this far ahead of our clock is broken: stale

function ProfileStore.new(options: Options)
	local self = setmetatable({}, ProfileStore)
	self.options = options
	self.lockRetries = options.LockRetries or 6
	self.lockRetryDelay = options.LockRetryDelay or 5
	self.staleLock = options.StaleLockSeconds or 600
	self.legacyStale = options.LegacyStaleSeconds or math.max(600, self.staleLock)
	self.callRetries = options.CallRetries or 4
	self.urgent = false
	self.sessions = 0
	self.live = {} :: { [string]: string } -- key -> the SessionId live on this server
	return self
end

-- Server shutdown: fewer retries and short pauses, so every final save fits the time left.
function ProfileStore.setUrgent(self: any, urgent: boolean)
	self.urgent = urgent
end

-- Is a session of `key` live on this server?
function ProfileStore.isLive(self: any, key: string): boolean
	return self.live[key] ~= nil
end

local function endSession(self: any, key: string, sessionId: string)
	if self.live[key] == sessionId then
		self.live[key] = nil
	end
end

-- DataService gave up on this session (its final save kept failing): a new
-- session of the same key on this server may take its lock over.
function ProfileStore.forget(self: any, profile: Profile)
	endSession(self, profile.Key, profile.SessionId)
end

-- Runs one UpdateAsync with retries. Returns ok, error message.
function ProfileStore._update(self: any, key: string, transform: (any) -> any): (boolean, string?)
	local options = self.options
	local lastError = nil
	local tries = if self.urgent then math.min(self.callRetries, 2) else self.callRetries
	for attempt = 1, tries do
		if options.BeforeRequest then
			options.BeforeRequest()
		end
		local ok, err = pcall(function()
			options.Store:UpdateAsync(key, function(old)
				return transform(old)
			end)
		end)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		if attempt < tries then
			options.Wait(if self.urgent then 0.5 else math.min(2 ^ (attempt - 1), 8))
		end
	end
	return false, lastError
end

-- Is the stored record locked by this session?
local function ownedBy(old: any, sessionId: string): boolean
	return type(old) == "table" and type(old.Lock) == "table" and old.Lock.SessionId == sessionId
end

-- Clears our own lock again (data untouched); another session's lock stays.
function ProfileStore._releaseLock(self: any, key: string, sessionId: string): boolean
	local ok = self:_update(key, function(old): any
		if not ownedBy(old, sessionId) then
			return nil
		end
		old.Lock = nil
		return old
	end)
	return ok
end

-- Must load() wait for this lock (true), or may it take it over (false)?
function ProfileStore._blocks(self: any, key: string, lock: { [string]: any }, now: number): boolean
	local options = self.options
	if lock.JobId == options.JobId then
		-- this server's own lock: wait only while that session is live here
		local liveId = self.live[key]
		if liveId == nil or liveId ~= lock.SessionId then
			return false
		end
	end
	local age = now - (tonumber(lock.Time) or 0)
	if age < -ProfileStore.FutureSlack then
		return false -- a lock from the future: a broken clock, never refreshed for real
	end
	local stale = if lock.SessionId == nil then self.legacyStale else self.staleLock
	return age < stale
end

--[[
	Loads and locks a profile. `shouldStop` (optional) ends the attempt when it
	returns true: before every try and right before the lock is written.
	Returns profile or nil + reason ("locked" | "gone" | "malformed" |
	"newer" | "error: ..." | "error: migrate: ...").
]]
function ProfileStore.load(self: any, key: string, shouldStop: (() -> boolean)?): (Profile?, string?)
	local options = self.options
	self.sessions += 1
	local sessionId = `{options.JobId}#{self.sessions}#{options.Now()}`
	for attempt = 1, self.lockRetries do
		if shouldStop and shouldStop() then
			return nil, "gone"
		end
		local loadedData: { [string]: any }? = nil
		local lockedByOther = false
		local refused: string? = nil
		local ok, err = self:_update(key, function(old): any
			loadedData = nil
			lockedByOther = false
			refused = nil
			local now = options.Now()
			-- nothing stored = a new player; anything else must be a proper record
			if old ~= nil and (type(old) ~= "table" or type(old.Data) ~= "table") then
				refused = "malformed"
				return nil
			end
			if old ~= nil and options.LatestVersion then
				local version = old.Data.Version
				if type(version) == "number" and version > options.LatestVersion then
					refused = "newer"
					return nil
				end
			end
			if old ~= nil and type(old.Lock) == "table" and self:_blocks(key, old.Lock, now) then
				lockedByOther = true
				return nil -- cancel the write
			end
			if shouldStop and shouldStop() then
				refused = "gone" -- never take a lock for someone who left
				return nil
			end
			local data = if old ~= nil then old.Data else deepCopy(options.Template)
			loadedData = data
			return { Data = data, Lock = { JobId = options.JobId, SessionId = sessionId, Time = now }, Saved = now }
		end)
		if not ok then
			return nil, "error: " .. tostring(err)
		end
		if refused then
			return nil, refused
		end
		if loadedData then
			local data = loadedData :: { [string]: any }
			self.live[key] = sessionId
			local prepared, problem = pcall(function()
				reconcile(data, options.Template)
				if options.Migrate then
					options.Migrate(data)
				end
			end)
			if not prepared then
				-- the save stays as it was; free the session so the player isn't locked out
				endSession(self, key, sessionId)
				self:_releaseLock(key, sessionId)
				return nil, "error: migrate: " .. tostring(problem)
			end
			local now = options.Now()
			return {
				Key = key,
				Data = data,
				SessionId = sessionId,
				Released = false,
				LoadedAt = now,
				LastSave = now,
				Saving = false,
				SessionLost = false,
			},
				nil
		end
		if lockedByOther and attempt < self.lockRetries then
			options.Wait(self.lockRetryDelay)
		end
	end
	return nil, "locked"
end

--[[
	Saves the profile. With release = true the lock is cleared (player left).
	Returns true on success. If the stored lock isn't this session's any more
	(another session holds it, or it was cleared), sets profile.SessionLost
	and returns false without writing.
]]
function ProfileStore.save(self: any, profile: Profile, release: boolean?): boolean
	local options = self.options
	if profile.Released then
		return false
	end
	-- one save at a time per profile
	local waited = 0
	while profile.Saving and waited < 30 do
		options.Wait(0.2)
		waited += 0.2
	end
	if profile.Released then
		return false
	end
	profile.Saving = true
	local lost = false
	local problems: { Problem } = {}
	local ok = self:_update(profile.Key, function(old): any
		lost = false
		if not ownedBy(old, profile.SessionId) then
			lost = true
			return nil
		end
		-- repaired right here: exactly what is written can be stored (no yield in between)
		problems = ProfileStore.repair(profile.Data)
		local now = options.Now()
		return {
			Data = profile.Data,
			Lock = if release then nil else { JobId = options.JobId, SessionId = profile.SessionId, Time = now },
			Saved = now,
		}
	end)
	profile.Saving = false
	if #problems > 0 and options.OnRepair then
		local shown = {}
		for i = 1, math.min(#problems, ProfileStore.MaxProblems) do
			shown[i] = problems[i]
		end
		pcall(options.OnRepair, profile.Key, shown)
	end
	if lost then
		profile.SessionLost = true
		profile.Released = true
		endSession(self, profile.Key, profile.SessionId)
		return false
	end
	if ok then
		profile.LastSave = options.Now()
		if release then
			profile.Released = true
			endSession(self, profile.Key, profile.SessionId)
		end
		return true
	end
	return false
end

return ProfileStore
