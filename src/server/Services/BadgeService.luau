--[[
	BadgeService (V2_PLAN step 8): awards the BadgeConfig badges from the
	player's save data, with no hooks in other services.

	- Listens to DataService.onLoaded / onChanged and EconomyService.onEarned;
	  each asks for a check, at most one per BadgeService.Throttle seconds per
	  player (a burst of changes runs one check right after the throttle).
	- A check awards every badge BadgeConfig.due(data) lists (earned, real id,
	  not cached in data.Badges). Before the first award attempt of a badge in a
	  session it asks Roblox once (UserHasBadgeAsync) whether the player owns it
	  already (an older save, another device): then it only caches it.
	- Every Roblox call runs in pcall with BadgeService.Retries tries and a
	  growing wait; a badge that still fails is left alone for the rest of the
	  session after BadgeService.MaxFailures failed checks (a disabled badge
	  never spams the badge API).
	- A badge awarded (or found owned) is cached in data.Badges[Key] = true
	  and DataService.changed tells the rest of the game.
	Badge ids of 0 are skipped (BadgeConfig).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxBadges = game:GetService("BadgeService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeConfig = require(Shared.Config.BadgeConfig)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local BadgeService = {}

BadgeService.Throttle = 2 -- seconds between checks per player
BadgeService.Retries = 3 -- tries per Roblox call
BadgeService.MaxFailures = 2 -- failed checks per badge per session before giving up

export type Api = {
	has: (userId: number, badgeId: number) -> boolean,
	award: (userId: number, badgeId: number) -> boolean,
	wait: (seconds: number) -> (),
	now: () -> number,
	spawn: (fn: () -> ()) -> (),
	delay: (seconds: number, fn: () -> ()) -> (),
}

local api: Api = {
	has = function(userId: number, badgeId: number): boolean
		return RobloxBadges:UserHasBadgeAsync(userId, badgeId)
	end,
	award = function(userId: number, badgeId: number): boolean
		return RobloxBadges:AwardBadge(userId, badgeId)
	end,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
	now = os.clock,
	spawn = function(fn: () -> ())
		task.spawn(fn)
	end,
	delay = function(seconds: number, fn: () -> ())
		task.delay(seconds, fn)
	end,
}

type Session = {
	asked: { [string]: boolean }, -- UserHasBadgeAsync done this session
	failures: { [string]: number },
	busy: boolean,
	again: boolean, -- a check was asked for while one was running
	last: number, -- time of the last check
	scheduled: boolean,
}
local sessions: { [Player]: Session } = {}

local function session(player: Player): Session
	local s = sessions[player]
	if not s then
		s = { asked = {}, failures = {}, busy = false, again = false, last = -math.huge, scheduled = false }
		sessions[player] = s
	end
	return s
end

-- `fn` in pcall up to Retries times with a growing wait. (ok, result)
local function retry(fn: () -> boolean): (boolean, boolean)
	for attempt = 1, BadgeService.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result == true
		end
		if attempt < BadgeService.Retries then
			api.wait(0.5 * 2 ^ (attempt - 1))
		end
	end
	return false, false
end

-- Awards every due badge now (yields on the badge API).
function BadgeService.check(player: Player)
	local s = session(player)
	if s.busy then
		s.again = true
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	s.busy = true
	s.last = api.now()
	if type(data.Badges) ~= "table" then
		data.Badges = {}
	end
	local changed = false
	for _, key in BadgeConfig.due(data) do
		local badge = BadgeConfig.ByKey[key]
		if (s.failures[key] or 0) >= BadgeService.MaxFailures then
			continue
		end
		local owned = false
		if not s.asked[key] then
			s.asked[key] = true
			local ok, has = retry(function()
				return api.has(player.UserId, badge.Id)
			end)
			owned = ok and has
		end
		if not owned then
			local ok, awarded = retry(function()
				return api.award(player.UserId, badge.Id)
			end)
			owned = ok and awarded
		end
		if owned then
			data.Badges[key] = true
			changed = true
		else
			s.failures[key] = (s.failures[key] or 0) + 1
		end
	end
	s.busy = false
	if changed and player.Parent then
		DataService.changed(player)
	end
	if s.again then
		s.again = false
		BadgeService.request(player)
	end
end

-- Asks for a check, throttled per player.
function BadgeService.request(player: Player)
	local s = session(player)
	if s.scheduled then
		return
	end
	local wait = BadgeService.Throttle - (api.now() - s.last)
	if wait <= 0 then
		api.spawn(function()
			BadgeService.check(player)
		end)
	else
		s.scheduled = true
		api.delay(wait, function()
			s.scheduled = false
			if sessions[player] == s and player.Parent then
				BadgeService.check(player)
			end
		end)
	end
end

function BadgeService.init()
	DataService.onLoaded(function(player: Player)
		BadgeService.request(player)
	end)
	DataService.onChanged(function(player: Player)
		BadgeService.request(player)
	end)
	EconomyService.onEarned(function(player: Player)
		BadgeService.request(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

BadgeService._test = {
	setApi = function(fake: Api)
		api = fake
	end,
	reset = function()
		table.clear(sessions)
	end,
	session = session,
}

return BadgeService
