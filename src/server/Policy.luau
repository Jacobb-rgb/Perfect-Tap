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
]]

local Players = game:GetService("Players")

local Policy = {}

Policy.RestrictedAttribute = "PaidRandomRestricted"
Policy.TradingAttribute = "PaidTradingAllowed"

export type Info = { PaidRandomRestricted: boolean, PaidTradingAllowed: boolean, Known: boolean }

local cache: { [Player]: Info } = {}
local pending: { [Player]: boolean } = {}

local STRICT: Info = { PaidRandomRestricted = true, PaidTradingAllowed = false, Known = false }

-- Swappable for the Lune tests: returns the PolicyService info table.
local fetcher: (Player) -> any = function(player: Player): any
	return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
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
		end)
	end)
end

-- The cached answer (strict until a fetch succeeded). Never yields.
function Policy.cached(player: Player): Info
	return cache[player] or STRICT
end

-- Asks PolicyService (once per player; yields). Returns the answer.
function Policy.fetch(player: Player): Info
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
	end
	if player.Parent then
		cache[player] = info
		player:SetAttribute(Policy.RestrictedAttribute, info.PaidRandomRestricted)
		player:SetAttribute(Policy.TradingAttribute, info.PaidTradingAllowed)
	end
	return info
end

-- Starts a fetch without waiting (call on join).
function Policy.prefetch(player: Player)
	if cache[player] and cache[player].Known then
		return
	end
	task.spawn(Policy.fetch, player)
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
	reset = function()
		table.clear(cache)
		table.clear(pending)
	end,
}

return Policy
