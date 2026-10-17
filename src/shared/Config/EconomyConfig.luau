--[[
	Money in design v2: podiums earn coins every second, also while you are
	offline (at a lower rate, for a limited time). The Ore Pen on every base
	holds your ore (data.Storage). Unwanted ore is sold at the Sell stall in
	town (Tobin the miner).
	Income formula: ItemData.income(desc) * EconomyConfig.multiplier(...).
	The Tech shop (step 3) sells machines, machine upgrades, Bellows, slot
	upgrades and pen automation (TechShop, techItem, techPrice below).
]]

local MachineData = require(script.Parent.MachineData)

local EconomyConfig = {}

EconomyConfig.IncomeTick = 1 -- seconds between podium payouts
-- Podium income alone pushes a State snapshot at most this often; the HUD
-- counts the coins up from Income in between (other changes push at once).
EconomyConfig.StatePushSeconds = 10

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

-- Pen automation (Tech shop, data.Upgrades.PenAutomation): level 1 = the sorting
-- billboard at the pen (marks the ore types to keep, data.KeepList), level 2 =
-- also the train's Direct Unload (raw cargo goes onto the TRAIN chute cell,
-- BaseLayout.Chutes.Train, instead of into the pen).
EconomyConfig.PenAutomation = {
	Prices = { 25000, 250000 }, -- levels 1..2
	Billboard = 1, -- the level that brings the sorting billboard
	DirectUnload = 2, -- the level that brings Direct Unload
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

---------------------------------------------------------------- Tech shop

--[[
	Tech shop catalog (the UPGRADES stall in town; ShopBuy { Shop = "Tech",
	Item, Count?, Level? }). Item strings:
	  <machineId>                      a machine into data.MachineInventory
	                                   (MachineData.Buildable; Count 1..MaxCount,
	                                   price MachineData.Price each)
	  "Upgrade:<machineId>:Speed"      the next Speed level of a machine type
	  "Upgrade:<machineId>:Quality"    the next Quality level (Cleaning Plant)
	                                   (prices: MachineData Upgrades, saved in
	                                   data.MachineUpgrades[machineId])
	  "Bellows"                        data.Upgrades.Bellows (MachineData.Bellows)
	  "Slots"                          data.Upgrades.ExtraSlots (MachineData.SlotUpgrade)
	  "PenAutomation"                  data.Upgrades.PenAutomation (EconomyConfig.PenAutomation)
	Levelled items always buy exactly one level (Count is ignored), and only
	the Level the request names, which must be the next one (techQuote): a
	double tap or a lagging card never buys two levels in a row.
]]
export type TechKind = "Machine" | "Upgrade" | "Bellows" | "Slots" | "PenAutomation"
export type TechItem = {
	Item: string, -- the ShopBuy Item string
	Kind: TechKind,
	Section: "Machines" | "Upgrades" | "Base", -- tab in the shop view
	Machine: string?, -- machine id (Machine and Upgrade items)
	Upgrade: string?, -- "Speed" | "Quality" (Upgrade items)
	Prices: { number }?, -- price of each level, level 1 first (levelled items)
}

EconomyConfig.TechShop = {
	Shop = "Tech", -- ShopBuy.Shop
	MaxCount = 20, -- machines per ShopBuy
	MaxOwned = 999, -- a machine type in the inventory (as Migrations keeps it)
	Items = {} :: { TechItem }, -- in shop order
	ById = {} :: { [string]: TechItem }, -- Item string -> entry
}

local function addTech(entry: TechItem)
	table.insert(EconomyConfig.TechShop.Items, entry)
	EconomyConfig.TechShop.ById[entry.Item] = entry
end

for _, machine in MachineData.Buildable do
	addTech({ Item = machine.Id, Kind = "Machine", Section = "Machines", Machine = machine.Id })
end
for _, machine in MachineData.Buildable do
	for _, kind in MachineData.UpgradeKinds do
		local prices = MachineData.upgradePrices(machine.Id, kind)
		if prices then
			addTech({
				Item = `Upgrade:{machine.Id}:{kind}`,
				Kind = "Upgrade",
				Section = "Upgrades",
				Machine = machine.Id,
				Upgrade = kind,
				Prices = prices,
			})
		end
	end
end
addTech({ Item = "Bellows", Kind = "Bellows", Section = "Base", Prices = MachineData.Bellows.Prices })
addTech({ Item = "Slots", Kind = "Slots", Section = "Base", Prices = MachineData.SlotUpgrade.Prices })
addTech({ Item = "PenAutomation", Kind = "PenAutomation", Section = "Base", Prices = EconomyConfig.PenAutomation.Prices })

-- The catalog entry for a ShopBuy Item string, or nil when it isn't sold.
function EconomyConfig.techItem(item: any): TechItem?
	if type(item) ~= "string" or #item > 64 then
		return nil
	end
	return EconomyConfig.TechShop.ById[item]
end

local function wholeLevel(value: any, max: number): number
	local n = if type(value) == "number" and value == value then math.floor(value) else 0
	return math.clamp(n, 0, max)
end

-- A machine type's upgrade level in a save (0..MachineData.upgradeMax; broken values count as 0).
function EconomyConfig.upgradeLevel(data: { [string]: any }, machineId: string, kind: string): number
	local all = data.MachineUpgrades
	local record = if type(all) == "table" then all[machineId] else nil
	local level = if type(record) == "table" then record[kind] else nil
	return wholeLevel(level, MachineData.upgradeMax(machineId, kind))
end

-- Current level and top level of a levelled item in a save (machines: 0, 0).
function EconomyConfig.techLevel(entry: TechItem, data: { [string]: any }): (number, number)
	local prices = entry.Prices
	if not prices then
		return 0, 0
	end
	local max = #prices
	if entry.Kind == "Upgrade" then
		return EconomyConfig.upgradeLevel(data, entry.Machine :: string, entry.Upgrade :: string), max
	end
	local bought = data.Upgrades
	local field = if entry.Kind == "Bellows" then "Bellows" elseif entry.Kind == "Slots" then "ExtraSlots" else "PenAutomation"
	return wholeLevel(if type(bought) == "table" then bought[field] else nil, max), max
end

-- What buying `entry` costs now: a machine times `count` (whole 1..MaxCount,
-- default 1), or the next level of a levelled item. nil + "BadCount" | "Max".
function EconomyConfig.techPrice(entry: TechItem, data: { [string]: any }, count: any?): (number?, string?)
	if entry.Kind == "Machine" then
		local n = if count == nil then 1 else count
		if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > EconomyConfig.TechShop.MaxCount then
			return nil, "BadCount"
		end
		local machine = MachineData.ById[entry.Machine :: string]
		return machine.Price * n, nil
	end
	local level, max = EconomyConfig.techLevel(entry, data)
	if level >= max then
		return nil, "Max"
	end
	local prices = entry.Prices :: { number }
	return prices[level + 1], nil
end

-- The server's check of a ShopBuy: techPrice, and for levelled items the
-- payload's `level` (the level being bought, as shown on the card) must be
-- exactly the current level + 1 (missing or any other value: nil, "Stale").
-- nil + "BadCount" | "Max" | "Stale".
function EconomyConfig.techQuote(entry: TechItem, data: { [string]: any }, count: any?, level: any?): (number?, string?)
	local price, reason = EconomyConfig.techPrice(entry, data, count)
	if price == nil or entry.Prices == nil then
		return price, reason
	end
	local current = EconomyConfig.techLevel(entry, data)
	if level ~= current + 1 then
		return nil, "Stale"
	end
	return price, nil
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
