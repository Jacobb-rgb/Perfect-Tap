--[[
	EconomyService: the one place coins are earned (selling today; rewards
	and the step e shop build on it).

	award(player, amount, source) adds a whole number of coins to Coins and
	TotalEarned and tells the HUD. Amounts below 1 or above MAX_AWARD are
	ignored (a bug, never a real sale). Listeners (tutorial, badges,
	analytics) hear about every award with onEarned.
	ItemService.storeDesc still pays a full Storage directly (noted for step e).
]]

local DataService = require(script.Parent.DataService)

local EconomyService = {}

export type EarnedCallback = (Player, number, string) -> ...any

-- one award can never be bigger than this (the best gear sells for far less)
local MAX_AWARD = 1e7

local earnedCallbacks: { EarnedCallback } = {}

-- Listeners: (player, amount, source) after every award.
function EconomyService.onEarned(callback: EarnedCallback)
	table.insert(earnedCallbacks, callback)
end

function EconomyService.balance(player: Player): number
	local data = DataService.get(player)
	return if data then tonumber(data.Coins) or 0 else 0
end

-- Adds coins. Returns the new balance (0 when the player's data isn't loaded).
function EconomyService.award(player: Player, amount: number, source: string): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local whole = if type(amount) == "number" and amount == amount then math.floor(amount) else 0
	if whole < 1 then
		return tonumber(data.Coins) or 0
	end
	if whole > MAX_AWARD then
		warn(`[EconomyService] ignored an award of {whole} coins to {player.Name} ({source})`)
		return tonumber(data.Coins) or 0
	end
	data.Coins = (tonumber(data.Coins) or 0) + whole
	data.TotalEarned = (tonumber(data.TotalEarned) or 0) + whole
	DataService.changed(player)
	for _, callback in earnedCallbacks do
		task.spawn(callback, player, whole, source)
	end
	return data.Coins
end

return EconomyService
