--[[
	Money in design v2: podiums earn coins every second, also while you are
	offline (at a lower rate, for a limited time). The Ore Pen on every base
	holds your ore (data.Storage). Unwanted ore is sold at the Sell stall in
	town (Tobin the miner).
	Income formula: ItemData.income(desc) * EconomyConfig.multiplier(...).
]]

local EconomyConfig = {}

EconomyConfig.IncomeTick = 1 -- seconds between podium payouts

EconomyConfig.Podiums = {
	Free = 2, -- every base
	Max = 4, -- podiums 3 and 4 come with the Podiums perk (Robux)
	Kinds = { Clean = true }, -- only cleaned ore can go on a podium
}

EconomyConfig.Offline = {
	Rate = 0.5, -- share of the normal income while offline
	BaseHours = 5,
	ExtendedHours = 12, -- with the OfflineExtension perk (big pass or 99 R$)
	MinSeconds = 60, -- shorter absences pay nothing (and show no popup)
}

EconomyConfig.Pen = {
	BaseCapacity = 40,
	PerLevel = 20, -- each pen upgrade adds this much room
	Prices = { 1500, 12000, 90000, 600000, 4e6, 25e6, 150e6 }, -- pen upgrade levels 1..7
	-- level 7 = 40 + 7 * 20 = 180; the DataStore cap (GameConfig.MaxStoredItems) is 300
}

EconomyConfig.Sell = {
	MaxPerRequest = 50, -- items one Sell request can sell
	ComboWindow = 0.8, -- sales closer together than this count as one combo (popups)
}

-- Big numbers: one award can never be bigger than this (a bug, never a real payout).
EconomyConfig.MaxAward = 1e30

-- Total income multiplier from boosts (golems, passes, rebirths arrive in later steps).
function EconomyConfig.multiplier(bonuses: { number }?): number
	local total = 1
	if bonuses then
		for _, bonus in bonuses do
			total += bonus
		end
	end
	return total
end

-- Pen capacity for a pen level (0 = the starting pen).
function EconomyConfig.penCapacity(level: any, hardCap: number): number
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	n = math.clamp(n, 0, #EconomyConfig.Pen.Prices)
	return math.min(hardCap, EconomyConfig.Pen.BaseCapacity + EconomyConfig.Pen.PerLevel * n)
end

-- Coins earned offline: `seconds` away at `incomePerSecond`, capped by hours.
function EconomyConfig.offlineEarnings(incomePerSecond: number, seconds: number, extended: boolean): number
	local o = EconomyConfig.Offline
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < o.MinSeconds then
		return 0
	end
	if type(incomePerSecond) ~= "number" or incomePerSecond ~= incomePerSecond or incomePerSecond <= 0 then
		return 0
	end
	local cap = (if extended then o.ExtendedHours else o.BaseHours) * 3600
	return incomePerSecond * o.Rate * math.min(seconds, cap)
end

return EconomyConfig
