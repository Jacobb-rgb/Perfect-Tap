--[[
	Player LEVEL (owner 2026-10-21: "add levels, it adds to the fun", the
	"make level ups juicy" reel; XP for everything, coins + a small income
	bonus per level, a HALL OF FAME board for the highest level).

	XP comes from what the save already counts: no service has to call in.
	LevelService looks at counters(data) every TickSeconds and pays XP for
	what grew since the last look (data.Level.Seen keeps the last look, so
	nothing counts twice, also over sessions). Weights below: one rock
	broken = 3 XP, one forged blaster = 60 XP, a minute of active play = 2
	XP...
	- Counters that a rebirth sets back (blaster level, gear, train,
	  machine upgrades) re-baseline when they drop: climbing again pays
	  again (a new run is real progress).
	- Machines and golems count by the most you ever had (Seen keeps the
	  high mark), so placing / picking up, deleting and buying back never
	  farms XP.
	- A save from before levels (Ready = false) gets its XP from what it
	  did so far at once, silently (no coins, no moment): veterans start at
	  a fair level.

	The level never resets (rebirth keeps it). Level L -> L + 1 needs
	need(L) XP. Each level up pays coins: the bigger of CoinsPerLevel * L
	and IncomeSeconds of the player's podium income, every MilestoneEvery
	(10th) level MilestoneFactor times that. And +BonusPerLevel podium
	income per level (EconomyService.addIncomeBonus "Level"), at most
	BonusCap.
]]

local LevelConfig = {}

LevelConfig.MaxLevel = 500
LevelConfig.TickSeconds = 1 -- how often LevelService looks at the counters
-- need(L) = round to 5 of Base + Grow * (L - 1) ^ Power
LevelConfig.Base = 80
LevelConfig.Grow = 25
LevelConfig.Power = 1.45

LevelConfig.CoinsPerLevel = 25
LevelConfig.IncomeSeconds = 45
LevelConfig.MilestoneEvery = 10
LevelConfig.MilestoneFactor = 5
LevelConfig.BonusPerLevel = 0.01 -- +1 % podium income per level
LevelConfig.BonusCap = 0.5 -- at most +50 % (level 51)
-- the burst only plays for a gain this big at once (the silent start of an old save never does)
LevelConfig.MaxShownLevels = 5

export type Source = {
	Id: string,
	Xp: number, -- XP per one unit of the counter
	High: boolean?, -- counts by the highest value ever (never re-baselines)
}

-- counter id -> XP per unit (see counters below for what each one reads)
LevelConfig.Sources = {
	{ Id = "RocksBroken", Xp = 3 },
	{ Id = "OresMined", Xp = 1 },
	{ Id = "OresCleaned", Xp = 4 },
	{ Id = "FlawlessCleans", Xp = 10 },
	{ Id = "IngotsSmelted", Xp = 2 },
	{ Id = "BlastersForged", Xp = 60 },
	{ Id = "BlastersBought", Xp = 40 },
	{ Id = "ItemsSold", Xp = 1 },
	{ Id = "TrainTrips", Xp = 8 },
	{ Id = "PlaySeconds", Xp = 1 / 30 }, -- active time only (LeaderboardService)
	{ Id = "ArtifactsFound", Xp = 20 },
	{ Id = "CapsulesOpened", Xp = 15 },
	{ Id = "WheelSpins", Xp = 10 },
	{ Id = "StarsEarned", Xp = 25 },
	{ Id = "Discovered", Xp = 30 }, -- new ores in the codex
	{ Id = "Machines", Xp = 10, High = true }, -- machines owned (placed + in the build menu)
	{ Id = "Golems", Xp = 10, High = true }, -- golems owned
	{ Id = "Upgrades", Xp = 15 }, -- Tech shop levels: Bellows, slots, pen, automation, elevator, machine upgrades
	{ Id = "Gear", Xp = 20 }, -- gear levels
	{ Id = "Train", Xp = 20 }, -- train capacity + speed levels
	{ Id = "Enchants", Xp = 15, High = true }, -- enchant tiers owned (the most ever)
	{ Id = "Blaster", Xp = 50 }, -- blaster levels this run
	{ Id = "Rebirths", Xp = 250 },
} :: { Source }

LevelConfig.ById = {} :: { [string]: Source }
for _, source in LevelConfig.Sources do
	LevelConfig.ById[source.Id] = source
end

local function num(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 0
	end
	return value
end

local function sumValues(record: any): number
	local total = 0
	if type(record) == "table" then
		for _, value in record do
			if type(value) == "number" then
				total += num(value)
			elseif value == true then
				total += 1
			end
		end
	end
	return total
end

local function count(record: any): number
	local n = 0
	if type(record) == "table" then
		for _ in record do
			n += 1
		end
	end
	return n
end

-- Every counter's value in a save (whole or fractional numbers >= 0).
function LevelConfig.counters(data: { [string]: any }): { [string]: number }
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local out: { [string]: number } = {}
	for _, id in
		{
			"RocksBroken",
			"OresMined",
			"OresCleaned",
			"FlawlessCleans",
			"IngotsSmelted",
			"BlastersForged",
			"BlastersBought",
			"ItemsSold",
			"TrainTrips",
			"PlaySeconds",
			"ArtifactsFound",
			"CapsulesOpened",
			"WheelSpins",
			"StarsEarned",
		}
	do
		out[id] = num(stats[id])
	end
	local discovered = 0
	if type(data.Discovered) == "table" then
		for _, on in data.Discovered do
			if on == true then
				discovered += 1
			end
		end
	end
	out.Discovered = discovered
	out.Machines = sumValues(data.MachineInventory) + count(data.PlacedMachines)
	local golems = if type(data.Golems) == "table" then data.Golems.Owned else nil
	out.Golems = count(golems)
	local upgrades = 0
	if type(data.Upgrades) == "table" then
		upgrades = sumValues(data.Upgrades)
	end
	if type(data.MachineUpgrades) == "table" then
		for _, levels in data.MachineUpgrades do
			upgrades += sumValues(levels)
		end
	end
	out.Upgrades = upgrades
	out.Gear = sumValues(data.Gear)
	local train = if type(data.Train) == "table" then data.Train else {}
	out.Train = num(train.CapacityLevel) + num(train.SpeedLevel)
	local enchants = if type(data.Enchants) == "table" then data.Enchants.Owned else nil
	out.Enchants = sumValues(enchants)
	out.Blaster = math.max(num(data.BlasterLevel) - 1, 0)
	out.Rebirths = num(data.Rebirths)
	return out
end

-- XP needed to go from level `level` to the next one.
function LevelConfig.need(level: number): number
	local l = math.clamp(math.floor(num(level)), 1, LevelConfig.MaxLevel)
	local raw = LevelConfig.Base + LevelConfig.Grow * (l - 1) ^ LevelConfig.Power
	return math.floor(raw / 5 + 0.5) * 5
end

-- Total XP from level 1 to reach `level`.
function LevelConfig.totalFor(level: number): number
	local total = 0
	for l = 1, math.clamp(math.floor(num(level)), 1, LevelConfig.MaxLevel) - 1 do
		total += LevelConfig.need(l)
	end
	return total
end

export type Record = { Level: number, Xp: number, Seen: { [string]: number }, Ready: boolean }

-- A save's Level record made sane in place (and returned).
function LevelConfig.sanitize(data: { [string]: any }): Record
	local record = data.Level
	if type(record) ~= "table" then
		record = {}
		data.Level = record
	end
	local level = num(record.Level)
	record.Level = math.clamp(math.floor(level), 1, LevelConfig.MaxLevel)
	local xp = num(record.Xp)
	record.Xp = if record.Level >= LevelConfig.MaxLevel then 0 else math.min(xp, LevelConfig.need(record.Level))
	if type(record.Seen) ~= "table" then
		record.Seen = {}
	end
	for key, value in record.Seen do
		if type(key) ~= "string" or not LevelConfig.ById[key] or type(value) ~= "number" then
			record.Seen[key] = nil
		else
			record.Seen[key] = num(value)
		end
	end
	record.Ready = record.Ready == true
	return record :: Record
end

-- The XP for what grew since the last look; moves Seen up to now.
-- A counter seen for the first time (a new source) only sets its baseline.
function LevelConfig.collect(record: Record, now: { [string]: number }): number
	local gained = 0
	for _, source in LevelConfig.Sources do
		local value = now[source.Id] or 0
		local seen = record.Seen[source.Id]
		if seen == nil then
			record.Seen[source.Id] = value
		elseif value > seen then
			gained += (value - seen) * source.Xp
			record.Seen[source.Id] = value
		elseif value < seen and not source.High then
			record.Seen[source.Id] = value -- a rebirth set it back: count again from here
		end
	end
	return gained
end

-- XP for everything a save did before levels existed (its first look).
function LevelConfig.backfill(now: { [string]: number }): number
	local total = 0
	for _, source in LevelConfig.Sources do
		total += (now[source.Id] or 0) * source.Xp
	end
	return total
end

-- Adds XP; returns the levels gained, in order (empty when none).
function LevelConfig.add(record: Record, xp: number): { number }
	local ups = {}
	if record.Level >= LevelConfig.MaxLevel then
		record.Xp = 0
		return ups
	end
	record.Xp += num(xp)
	while record.Level < LevelConfig.MaxLevel and record.Xp >= LevelConfig.need(record.Level) do
		record.Xp -= LevelConfig.need(record.Level)
		record.Level += 1
		table.insert(ups, record.Level)
	end
	if record.Level >= LevelConfig.MaxLevel then
		record.Xp = 0
	end
	return ups
end

function LevelConfig.isMilestone(level: number): boolean
	return level % LevelConfig.MilestoneEvery == 0
end

-- Coins for reaching `level` with `incomePerSec` podium income.
function LevelConfig.coinsFor(level: number, incomePerSec: number): number
	local coins = math.max(LevelConfig.CoinsPerLevel * level, num(incomePerSec) * LevelConfig.IncomeSeconds)
	if LevelConfig.isMilestone(level) then
		coins *= LevelConfig.MilestoneFactor
	end
	return math.floor(coins)
end

-- The podium income bonus share at `level` (0.05 = +5 %).
function LevelConfig.bonusFor(level: number): number
	local l = math.clamp(math.floor(num(level)), 1, LevelConfig.MaxLevel)
	return math.min((l - 1) * LevelConfig.BonusPerLevel, LevelConfig.BonusCap)
end

return LevelConfig
