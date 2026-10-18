--[[
	PolicyService wrapper (docs/COMPLIANCE.md 2.2): one place to ask whether
	a player may use paid random items (golem capsules, luck boosts).

	- fetch(player) asks PolicyService:GetPolicyInfoForPlayerAsync once (it
	  yields; pcall'd) and caches the answer. If the call fails, the strict
	  values are assumed: paid random items restricted, paid item trading not
	  allowed. A failed call is tried again on the next fetch.
	- The answer is also set as server-written player attributes the client
	  reads to hide / disable items: "PaidRandomRestricted" (true / false) and
	  "PaidTradingAllowed". No attribute yet = unknown: the client treats it
	  as restricted.
	- paidRandomRestricted(player) yields on the first call (fetch); call
	  prefetch(player) when the player joins (several services may: it only
	  asks once). Handlers must check it BEFORE the quote / spend / write step
	  (that step must not yield).
	- prefetch keeps trying while the answer isn't known: after a failed call
	  it tries again after RetrySeconds (10, 30, 120 s, then every 300 s) as
	  long as the player is in the game, and updates the attributes when a
	  call succeeds. (The client hides paid random items while it thinks the
	  player is restricted, so it would never send the request that triggers
	  a fetch: without these retries one failed call on join would restrict
	  the player for the whole session.)
	- After a failed call, fetch() keeps returning the strict answer without
	  asking again while prefetch's retry loop runs, or for RefetchSeconds
	  when no loop runs (security audit S1: a client spamming requests during
	  a PolicyService outage must not multiply the API calls and warnings).
]]

local Players = game:GetService("Players")

local Policy = {}

Policy.RestrictedAttribute = "PaidRandomRestricted"
Policy.TradingAttribute = "PaidTradingAllowed"

export type Info = { PaidRandomRestricted: boolean, PaidTradingAllowed: boolean, Known: boolean }

local cache: { [Player]: Info } = {}
local pending: { [Player]: boolean } = {}
local retrying: { [Player]: boolean } = {}
local failedAt: { [Player]: number } = {}

-- Seconds to wait before each retry after a failed call (the last repeats).
Policy.RetrySeconds = { 10, 30, 120, 300 }
-- After a failed call, requests outside the retry loop wait this long before asking again.
Policy.RefetchSeconds = 10

local STRICT: Info = { PaidRandomRestricted = true, PaidTradingAllowed = false, Known = false }

-- Swappable for the Lune tests: returns the PolicyService info table.
local fetcher: (Player) -> any = function(player: Player): any
	return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
end

-- Swappable for the Lune tests: seconds for RefetchSeconds.
local clock: () -> number = os.clock

-- Swappable for the Lune tests: runs `fn` after `seconds`.
local schedule: (seconds: number, fn: () -> ()) -> () = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

-- Forget a leaving player (connected on the first fetch).
local hooked = false
local function hookLeaving()
	if hooked then
		return
	end
	hooked = true
	pcall(function()
		Players.PlayerRemoving:Connect(function(player: Player)
			cache[player] = nil
			pending[player] = nil
			retrying[player] = nil
			failedAt[player] = nil
		end)
	end)
end

-- The cached answer (strict until a fetch succeeded). Never yields.
function Policy.cached(player: Player): Info
	return cache[player] or STRICT
end

-- The PolicyService call itself (one at a time per player; yields).
local function ask(player: Player): Info
	hookLeaving()
	local known = cache[player]
	if known and known.Known then
		return known
	end
	while pending[player] do
		task.wait(0.1)
	end
	known = cache[player]
	if known and known.Known then
		return known
	end
	pending[player] = true
	local ok, result = pcall(fetcher, player)
	pending[player] = nil
	local info: Info
	if ok and type(result) == "table" then
		info = {
			PaidRandomRestricted = result.ArePaidRandomItemsRestricted ~= false,
			PaidTradingAllowed = result.IsPaidItemTradingAllowed == true,
			Known = true,
		}
	else
		warn(`[Policy] PolicyService failed for {player.Name}: {tostring(result)} (strict rules apply)`)
		info = STRICT
		failedAt[player] = clock()
	end
	if player.Parent then
		cache[player] = info
		player:SetAttribute(Policy.RestrictedAttribute, info.PaidRandomRestricted)
		player:SetAttribute(Policy.TradingAttribute, info.PaidTradingAllowed)
	end
	return info
end

-- Asks PolicyService (once per player; yields). Returns the answer. After a
-- failed call the strict answer comes back without a new call while the
-- retry loop runs or for RefetchSeconds (see the header).
function Policy.fetch(player: Player): Info
	local known = cache[player]
	if known and not known.Known then
		local last = failedAt[player]
		if retrying[player] or (last and clock() - last < Policy.RefetchSeconds) then
			return known
		end
	end
	return ask(player)
end

-- One try of a prefetch; after a failure the next one is scheduled (see the header).
local function attempt(player: Player, tries: number)
	if not player.Parent then
		retrying[player] = nil
		return
	end
	if ask(player).Known then
		retrying[player] = nil
		return
	end
	local delays = Policy.RetrySeconds
	local seconds = delays[math.min(tries + 1, #delays)]
	schedule(seconds, function()
		attempt(player, tries + 1)
	end)
end

-- Starts a fetch without waiting (call on join); retried until it is known.
function Policy.prefetch(player: Player)
	if (cache[player] and cache[player].Known) or retrying[player] then
		return
	end
	retrying[player] = true
	task.spawn(attempt, player, 0)
end

-- May this player NOT use paid random items? Yields on the first call.
function Policy.paidRandomRestricted(player: Player): boolean
	return Policy.fetch(player).PaidRandomRestricted
end

-- Internals for the Lune tests only.
Policy._test = {
	setFetcher = function(fn: (Player) -> any)
		fetcher = fn
	end,
	setSchedule = function(fn: (number, () -> ()) -> ())
		schedule = fn
	end,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	reset = function()
		table.clear(cache)
		table.clear(pending)
		table.clear(retrying)
		table.clear(failedAt)
		clock = os.clock
		schedule = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end
	end,
}

return Policy
