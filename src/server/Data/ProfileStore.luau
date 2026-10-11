--[[
	Session-locked player profiles on top of a DataStore (pure logic, no
	Roblox services, so it is unit-tested in Lune with a fake store).

	Saved value shape:
	  { Data = {...player data...}, Lock = { JobId = "...", Time = os.time() }? , Saved = os.time() }

	Rules:
	- load(): takes the lock with UpdateAsync. If another live server holds
	  it, wait and retry (that server is probably still saving the player who
	  just hopped). A lock that has not been refreshed for StaleLockSeconds is
	  from a crashed server and gets taken over.
	- save(): only writes if we still own the lock (never overwrite a newer
	  session). Refreshes the lock time.
	- release(): final save that clears the lock.
	- Every DataStore call is retried with exponential backoff.
]]

export type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> any,
}

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
}

export type Profile = {
	Key: string,
	Data: { [string]: any },
	Released: boolean,
	LoadedAt: number,
	LastSave: number,
	Saving: boolean,
	SessionLost: boolean,
}

local ProfileStore = {}
ProfileStore.__index = ProfileStore

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

function ProfileStore.new(options: Options)
	local self = setmetatable({}, ProfileStore)
	self.options = options
	self.lockRetries = options.LockRetries or 6
	self.lockRetryDelay = options.LockRetryDelay or 5
	self.staleLock = options.StaleLockSeconds or 600
	self.callRetries = options.CallRetries or 4
	return self
end

-- Runs one UpdateAsync with retries. Returns ok, error message.
function ProfileStore._update(self: any, key: string, transform: (any) -> any): (boolean, string?)
	local options = self.options
	local lastError = nil
	for attempt = 1, self.callRetries do
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
		if attempt < self.callRetries then
			options.Wait(math.min(2 ^ (attempt - 1), 8))
		end
	end
	return false, lastError
end

--[[
	Loads and locks a profile.
	Returns profile or nil + reason ("locked" | "error: ...").
]]
function ProfileStore.load(self: any, key: string): (Profile?, string?)
	local options = self.options
	for attempt = 1, self.lockRetries do
		local loadedData: { [string]: any }? = nil
		local lockedByOther = false
		local ok, err = self:_update(key, function(old): any
			loadedData = nil
			lockedByOther = false
			local now = options.Now()
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= options.JobId then
				local age = now - (tonumber(old.Lock.Time) or 0)
				local isLastAttempt = attempt == self.lockRetries
				-- a fresh lock belongs to a live server: wait for it, unless it is stale
				if age < self.staleLock and not (isLastAttempt and age >= self.staleLock / 2) then
					lockedByOther = true
					return nil -- cancel the write
				end
			end
			local data = if type(old) == "table" and type(old.Data) == "table" then old.Data else deepCopy(options.Template)
			loadedData = data
			return { Data = data, Lock = { JobId = options.JobId, Time = now }, Saved = now }
		end)
		if not ok then
			return nil, "error: " .. tostring(err)
		end
		if loadedData then
			local data = loadedData :: { [string]: any }
			reconcile(data, options.Template)
			if options.Migrate then
				options.Migrate(data)
			end
			local now = options.Now()
			return {
				Key = key,
				Data = data,
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
	Returns true on success. If another server took the session, sets
	profile.SessionLost and returns false without writing.
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
	local ok = self:_update(profile.Key, function(old): any
		lost = false
		if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= options.JobId then
			lost = true
			return nil
		end
		local now = options.Now()
		return {
			Data = profile.Data,
			Lock = if release then nil else { JobId = options.JobId, Time = now },
			Saved = now,
		}
	end)
	profile.Saving = false
	if lost then
		profile.SessionLost = true
		profile.Released = true
		return false
	end
	if ok then
		profile.LastSave = options.Now()
		if release then
			profile.Released = true
		end
		return true
	end
	return false
end

return ProfileStore
