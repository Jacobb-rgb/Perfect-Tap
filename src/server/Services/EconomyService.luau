--[[
	EconomyService: the one place coins change (design v2).

	- award(player, amount, source): adds coins (fractions allowed: podium
	  income is per second) to Coins and TotalEarned, tells the HUD and the
	  onEarned listeners (tutorial, badges, analytics, leaderboards).
	- spend(player, amount, reason): takes coins if the player has enough.
	- Podium income, offline earnings and the per-second tick are added by
	  the base package (PodiumService); selling by SellService. They all go
	  through award, so nothing else ever writes data.Coins.
	Amounts that are not finite, below 0.001 or above EconomyConfig.MaxAward
	are ignored (a bug, never a real payout).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

export type EarnedCallback = (Player, number, string) -> ...any
export type SpentCallback = (Player, number, string) -> ...any

local MIN_AMOUNT = 0.001

local earnedCallbacks: { EarnedCallback } = {}
local spentCallbacks: { SpentCallback } = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Listeners: (player, amount, source) after every award.
function EconomyService.onEarned(callback: EarnedCallback)
	table.insert(earnedCallbacks, callback)
end

-- Listeners: (player, amount, reason) after every successful spend.
function EconomyService.onSpent(callback: SpentCallback)
	table.insert(spentCallbacks, callback)
end

function EconomyService.balance(player: Player): number
	local data = DataService.get(player)
	local coins = if data then data.Coins else 0
	return if finite(coins) then coins else 0
end

-- Adds coins. Returns the new balance (0 when the player's data isn't loaded).
-- `quiet` skips DataService.changed (the per-second podium tick batches it).
function EconomyService.award(player: Player, amount: number, source: string, quiet: boolean?): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	if not finite(amount) or amount < MIN_AMOUNT then
		return EconomyService.balance(player)
	end
	if amount > EconomyConfig.MaxAward then
		warn(`[EconomyService] ignored an award of {amount} coins to {player.Name} ({source})`)
		return EconomyService.balance(player)
	end
	data.Coins = EconomyService.balance(player) + amount
	data.TotalEarned = (if finite(data.TotalEarned) then data.TotalEarned else 0) + amount
	if not quiet then
		DataService.changed(player)
	end
	for _, callback in earnedCallbacks do
		task.spawn(callback, player, amount, source)
	end
	return data.Coins
end

-- Takes `amount` coins when the player has them. Returns true when paid.
function EconomyService.spend(player: Player, amount: number, reason: string): boolean
	local data = DataService.get(player)
	if not data or not finite(amount) or amount < 0 then
		return false
	end
	local balance = EconomyService.balance(player)
	if balance < amount then
		return false
	end
	data.Coins = balance - amount
	DataService.changed(player)
	for _, callback in spentCallbacks do
		task.spawn(callback, player, amount, reason)
	end
	return true
end

function EconomyService.canAfford(player: Player, amount: number): boolean
	return finite(amount) and EconomyService.balance(player) >= amount
end

return EconomyService
