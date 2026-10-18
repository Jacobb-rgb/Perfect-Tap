--[[
	Balance simulation: a typical player from the first minute to 10 hours.
	`lune run tools/lune/balance_sim.luau [calibrate] [override=file.json]` -> build/balance/sim.json (+ a
	summary on stdout); tools/balance/chart.mjs draws the chart and
	docs/BALANCE_SIM.md explains the model and the results.

	It reads the real config (OreData, BlasterData, ItemData, MachineData,
	EconomyConfig, ToolData, TrainConfig, MachineData power rules) and models
	the mine floors the way the mine-floors chat built them (branch
	art/mine-floors, MineFloors.luau): 5 floors with blaster gates 1/3/5/7/9,
	floors 4-5 only by the elevator ($500K), rocks that the floor's weakest
	allowed blaster breaks in about 4.5 s, 3.3 ores per rock, 10 % crystal
	rocks rolling from the next rarity. Floor ore tables follow its plan:
	floor N = the Nth rarity (Common .. Legendary), crystals one rarity up
	(floor 5's crystals = Mythic). Hoverboards ($5K / $80K / $1.5M) shorten
	walking. Golems, boosts and rebirths are not on main yet: not modelled.

	Everything the player does is an expected-value loop per 5 s step with
	random ore draws (seeded), run for many players; medians are reported.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local root = process.cwd
local Loader = require("./lib/loader")
Loader.init(root)

local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

---------------------------------------------------------------- assumptions

local A = {
	Hours = 10,
	Step = 5, -- seconds per simulation step
	Players = 120, -- simulated players (seeds 1..N), medians reported
	RockSeconds = 0.6 * 4 + 0.3 * 5 + 0.1 * 6, -- the floor's weakest blaster per rock (Small/Big/Crystal mix)
	OresPerRock = 0.6 * 3 + 0.3 * 4 + 0.1 * 3,
	CrystalShare = 0.1, -- rocks rolling from the next rarity
	RockWalk = 2.5, -- seconds from one rock to the next
	DropWalk = 12, -- seconds to carry a load to the floor's Mine Station (train) and back
	HandClean = 18, -- seconds per ore in the cleaning minigame
	CleanTrip = 30, -- seconds back from the base to the mine after a cleaning session (8 with the elevator)
	CleanBatch = 20, -- ores cleaned per session at the base
	TrainLoad = 5, -- seconds the train waits / loads at the station
	HandGrades = { Rough = 0.1, Clean = 0.4, Pristine = 0.35, Flawless = 0.15 }, -- a typical player
	Podiums = 2, -- free podiums (3 and 4 are a Robux perk)
	Hoverboards = { { Price = 5000, Walk = 0.8 }, { Price = 80000, Walk = 0.65 }, { Price = 1.5e6, Walk = 0.5 } },
	Elevator = 500000,
	FloorGates = { 1, 3, 5, 7, 9 },
	FloorElevator = { false, false, false, true, true },
	Payback = 20 * 60, -- a machine or upgrade is bought when it pays back within this many seconds
	PolePrice = 500,
	MaxCleaners = 4,
	MaxFurnaces = 3,
	Efficiency = 1, -- share of the player's own actions done well (mining, carrying, hand cleaning); machines run full
	BlasterCoins = nil :: { [number]: number }?, -- Foundry coin price per level instead of BlasterData's (Vault = 4x)
	ElevatorPrice = nil :: number?,
	StopLevel = nil :: number?, -- calibration: stop a run once this blaster level is reached...
	StopTime = nil :: number?, -- ...or after this many seconds
	ShopEvery = 30, -- seconds between machine / upgrade shopping decisions
	-- bonus hooks (steps 6-7: golems, boosts, enchants, gear, artifact sets): 1 = none
	IncomeMult = 1, -- podium income and every sale
	DamageMult = 1, -- blaster damage
	LuckMult = 1, -- the crystal-rock share (better ores)
	CleanSpeedMult = 1, -- Auto Cleaner speed
	CrystalMode = "Mixed", -- "Mixed": crystals = the floor's best 3 ores (70 %) + the next rarity's cheapest 3 (30 %); "NextRarity"
}

-- Scenarios run one after the other (each overrides some assumptions).
local SCENARIOS = {
	{ Name = "Typical", Efficiency = 0.5, CrystalMode = "Mixed" },
	{ Name = "Skilled", Efficiency = 0.8, CrystalMode = "Mixed" },
	{ Name = "Casual", Efficiency = 0.3, CrystalMode = "Mixed" },
}

---------------------------------------------------------------- floors

local rarityOrder: { [string]: number } = {}
for _, r in Rarity.List do
	rarityOrder[r.Id] = r.Order
end
local byRarity: { [number]: { any } } = {}
for _, ore in OreData.List do
	local o = rarityOrder[ore.Rarity]
	byRarity[o] = byRarity[o] or {}
	table.insert(byRarity[o], ore)
end

-- Weighted table of one rarity: cheaper ores are commoner (weight 1 / rank^0.8).
local function tableOf(order: number): { { ore: any, w: number } }
	local list = {}
	for i, ore in byRarity[order] or {} do
		table.insert(list, { ore = ore, w = 1 / i ^ 0.8 })
	end
	return list
end

-- Crystal rocks: the floor's best 3 ores (70 %) and the next rarity's cheapest 3 (30 %).
local function crystalTable(order: number): { { ore: any, w: number } }
	if A.CrystalMode == "NextRarity" then
		return tableOf(math.min(6, order + 1))
	end
	local list = {}
	local own = byRarity[order] or {}
	for i = math.max(1, #own - 2), #own do
		table.insert(list, { ore = own[i], w = 0.7 / 3 })
	end
	local up = byRarity[math.min(6, order + 1)] or {}
	if order < 6 then
		for i = 1, math.min(3, #up) do
			table.insert(list, { ore = up[i], w = 0.3 / 3 })
		end
	end
	return list
end

local floors = {}
local function buildFloors()
	for i = 1, 5 do
		floors[i] = {
			Index = i,
			Gate = A.FloorGates[i],
			Elevator = A.FloorElevator[i],
			Ores = tableOf(i),
			Crystal = crystalTable(i),
			-- HP: the floor's weakest allowed (rusty) blaster needs RockSeconds
			HP = BlasterData.damage(A.FloorGates[i], "") * A.RockSeconds,
		}
	end
end

local function pick(rng: any, list: { { ore: any, w: number } }): any
	local total = 0
	for _, e in list do
		total += e.w
	end
	local roll = rng:range(0, total)
	for _, e in list do
		roll -= e.w
		if roll <= 0 then
			return e.ore
		end
	end
	return list[#list].ore
end

local function drawOre(rng: any, floor: any): any
	if rng:range(0, 1) < math.min(1, A.CrystalShare * A.LuckMult) then
		return pick(rng, floor.Crystal)
	end
	return pick(rng, floor.Ores)
end

local function meanValue(floor: any): number
	local function avg(list: { { ore: any, w: number } }): number
		local total, sum = 0, 0
		for _, e in list do
			total += e.w
			sum += e.w * e.ore.Value
		end
		return sum / total
	end
	return avg(floor.Ores) * (1 - A.CrystalShare) + avg(floor.Crystal) * A.CrystalShare
end

local function drawGrade(rng: any, odds: { [string]: number }): string
	local roll = rng:range(0, 1)
	for _, g in ItemData.Grades do
		roll -= odds[g.Id] or 0
		if roll <= 0 then
			return g.Id
		end
	end
	return "Rough"
end

local function meanGradeMult(odds: { [string]: number }): number
	local sum = 0
	for _, g in ItemData.Grades do
		sum += (odds[g.Id] or 0) * g.Mult
	end
	return sum
end

---------------------------------------------------------------- the player

local FURNACES = {
	{ Id = "ClayFurnace", Rate = 1 / MachineData.ById.ClayFurnace.Time, Power = 0 },
	{ Id = "BrickFurnace", Rate = 1 / MachineData.ById.BrickFurnace.Time, Power = MachineData.ById.BrickFurnace.Power or 0 },
	{ Id = "BlastFurnace", Rate = 1 / MachineData.ById.BlastFurnace.Time, Power = MachineData.ById.BlastFurnace.Power or 0 },
	{ Id = "PlasmaFurnace", Rate = 2 / MachineData.ById.PlasmaFurnace.Time, Power = MachineData.ById.PlasmaFurnace.Power or 0 },
}
local GENERATORS = {
	{ Id = "SolarPanel", Out = MachineData.ById.SolarPanel.PowerOut, Price = MachineData.ById.SolarPanel.Price },
	{ Id = "WindTurbine", Out = MachineData.ById.WindTurbine.PowerOut, Price = MachineData.ById.WindTurbine.Price },
	{ Id = "FusionReactor", Out = MachineData.ById.FusionReactor.PowerOut, Price = MachineData.ById.FusionReactor.Price },
}

local function newPlayer(): any
	return {
		Coins = 0,
		Earned = 0,
		Blaster = 1,
		BlasterOre = "",
		Carry = 1,
		TrainCap = 0, -- levels
		TrainSpeed = 0,
		Hover = 0,
		Elevator = false,
		Cleaners = 0,
		Crusher = false,
		Furnaces = { "ClayFurnace" }, -- the starter kit
		PowerOut = 0,
		PowerDemand = 0,
		Poles = 0,
		Podium = {} :: { number },
		IngotsReady = 0, -- ingots of the next blaster's rarity put aside
		Pending = 0, -- fractional ores carried between steps
		Milestones = {} :: { [string]: number },
		Log = {} :: { any },
	}
end

local function bestFloor(p: any): any
	local best = floors[1]
	for _, floor in floors do
		if p.Blaster >= floor.Gate and (not floor.Elevator or p.Elevator) then
			best = floor
		end
	end
	return best
end

local function powerSpeed(p: any): number
	if p.PowerDemand <= 0 then
		return 1
	end
	if p.PowerOut <= 0 then
		return MachineData.PowerRules.UnpoweredSpeed
	end
	return MachineData.powerSpeed(p.PowerOut, p.PowerDemand)
end

local function furnaceRate(p: any): number
	local rate = 0
	local speed = powerSpeed(p)
	for _, id in p.Furnaces do
		for _, f in FURNACES do
			if f.Id == id then
				rate += f.Rate * (if f.Power > 0 then speed else 1)
			end
		end
	end
	return rate
end

local function walkMult(p: any): number
	return if p.Hover > 0 then A.Hoverboards[p.Hover].Walk else 1
end

-- Ores per second the player delivers (mined, carried, through the train) and
-- cleans; raw ores per second sold dirty (the cleaners can't keep up).
local function flow(p: any): (number, number, any)
	local floor = bestFloor(p)
	local dps = BlasterData.damage(p.Blaster, p.BlasterOre) * A.DamageMult
	local rockTime = floor.HP / dps + A.RockWalk * walkMult(p)
	local perOre = (rockTime / A.OresPerRock + A.DropWalk * walkMult(p) / ToolData.carryCapacity(p.Carry, false)) / A.Efficiency
	local cap = TrainConfig.capacity(p.TrainCap, false)
	local trainRate = cap / (TrainConfig.tripSeconds(p.TrainSpeed, false) + TrainConfig.ReturnSeconds + A.TrainLoad)
	if p.Cleaners == 0 then
		local trip = if p.Elevator then 8 else A.CleanTrip
		local handPerOre = perOre + (A.HandClean + trip / A.CleanBatch) / A.Efficiency
		local rate = math.min(1 / handPerOre, trainRate)
		return rate, 0, floor
	end
	local delivered = math.min(1 / perOre, trainRate)
	local cleanRate = p.Cleaners * A.CleanSpeedMult / MachineData.ById.AutoCleaner.Time
	local cleaned = math.min(delivered, cleanRate)
	return cleaned, delivered - cleaned, floor
end

-- Coins per second from selling (expected), given the cleaned flow.
local function saleRate(p: any, cleaned: number, raw: number, floor: any): number
	local value = meanValue(floor)
	local grade = if p.Cleaners > 0 then meanGradeMult(MachineData.gradeOdds(0)) else meanGradeMult(A.HandGrades)
	local f = furnaceRate(p)
	local perClean: number
	if p.Crusher then
		local crushIn = math.min(cleaned, 1 / MachineData.ById.Crusher.Time)
		local crushed = crushIn * 2
		local ingots = math.min(crushed, f)
		local total = ingots * 1.25 + (crushed - ingots) * 0.75 + (cleaned - crushIn) * 1.0
		perClean = if cleaned > 0 then total / cleaned else 0
	else
		local ingots = math.min(cleaned, f)
		perClean = if cleaned > 0 then (ingots * 1.25 + (cleaned - ingots)) / cleaned else 0
	end
	return (cleaned * value * grade * perClean + raw * value * ItemData.Kinds.Raw.ValueMult) * A.IncomeMult
end

local function podiumIncome(p: any): number
	local sum = 0
	for _, v in p.Podium do
		sum += v
	end
	return sum * A.IncomeMult
end

-- The cheapest generators that cover `demand` power from what the player has.
local function powerCost(p: any, extraDemand: number): (number, number)
	local need = p.PowerDemand + extraDemand - p.PowerOut
	if need <= 0 then
		return 0, 0
	end
	local best, bestOut = math.huge, 0
	for _, g in GENERATORS do
		local count = math.ceil(need / g.Out)
		local price = count * g.Price + (if p.Poles == 0 then 2 * A.PolePrice else 0)
		if price < best then
			best, bestOut = price, count * g.Out
		end
	end
	return best, bestOut
end

-- Purchase candidates: { name, price, apply(p) }.
local function candidates(p: any): { any }
	local list = {}
	local carry = ToolData.CarryLevels[p.Carry + 1]
	if carry then
		table.insert(list, {
			"Carry " .. carry.Name,
			carry.Price,
			function(q)
				q.Carry += 1
			end,
		})
	end
	local cap = TrainConfig.Capacity[p.TrainCap + 2]
	if cap then
		table.insert(list, {
			"Train capacity " .. cap.Value,
			cap.Price,
			function(q)
				q.TrainCap += 1
			end,
		})
	end
	local speed = TrainConfig.Speed[p.TrainSpeed + 2]
	if speed then
		table.insert(list, {
			"Train speed " .. speed.Value .. " s",
			speed.Price,
			function(q)
				q.TrainSpeed += 1
			end,
		})
	end
	if p.Cleaners < A.MaxCleaners then
		table.insert(list, {
			"Auto Cleaner #" .. (p.Cleaners + 1),
			MachineData.ById.AutoCleaner.Price,
			function(q)
				q.Cleaners += 1
			end,
		})
	end
	if not p.Crusher then
		table.insert(list, {
			"Crusher",
			MachineData.ById.Crusher.Price,
			function(q)
				q.Crusher = true
			end,
		})
	end
	if #p.Furnaces < A.MaxFurnaces + 1 then
		for _, f in FURNACES do
			if f.Id ~= "ClayFurnace" and not table.find(p.Furnaces, f.Id) then
				local extra, out = powerCost(p, f.Power)
				table.insert(list, {
					f.Id .. (if extra > 0 then " + power" else ""),
					MachineData.ById[f.Id].Price + extra,
					function(q)
						table.insert(q.Furnaces, f.Id)
						q.PowerDemand += f.Power
						q.PowerOut += out
						if out > 0 then
							q.Poles = math.max(q.Poles, 2)
						end
					end,
				})
				break -- one furnace tier at a time, in order
			end
		end
	end
	return list
end

local function gain(p: any, apply: (any) -> ()): number
	local cleaned, raw, floor = flow(p)
	local before = saleRate(p, cleaned, raw, floor)
	local copy = table.clone(p)
	copy.Furnaces = table.clone(p.Furnaces)
	apply(copy)
	local cleaned2, raw2, floor2 = flow(copy)
	return saleRate(copy, cleaned2, raw2, floor2) - before
end

local function mark(p: any, key: string, t: number)
	if p.Milestones[key] == nil then
		p.Milestones[key] = t
	end
end

local function buy(p: any, name: string, price: number, t: number)
	p.Coins -= price
	table.insert(p.Log, { T = t, What = name, Price = price })
	if name:find("Furnace", 1, true) or name:find("Cleaner", 1, true) or name == "Crusher" then
		mark(p, "First machine bought", t)
	end
end

local function simulate(seed: number): any
	local rng = Rng.new(seed)
	local p = newPlayer()
	local series = {}
	local t = 0
	local total = A.Hours * 3600
	local stopTime = A.StopTime or total
	while t < math.min(total, stopTime) do
		if A.StopLevel and p.Blaster >= A.StopLevel then
			break
		end
		local cleaned, raw, floor = flow(p)
		-- this step's cleaned ores: podium candidates, foundry ingots
		p.Pending += cleaned * A.Step
		local next = BlasterData.ByLevel[p.Blaster + 1]
		local recipe = next and next.Recipe
		local coinsNeeded = if recipe
				and A.BlasterCoins
				and A.BlasterCoins[p.Blaster + 1]
			then A.BlasterCoins[p.Blaster + 1]
			elseif recipe then recipe.Coins
			else 0
		while p.Pending >= 1 do
			p.Pending -= 1
			local ore = drawOre(rng, floor)
			local grade = drawGrade(rng, if p.Cleaners > 0 then MachineData.gradeOdds(0) else A.HandGrades)
			local income = ore.Income * ItemData.gradeMult(grade)
			mark(p, "First podium filled", t)
			if #p.Podium < A.Podiums then
				table.insert(p.Podium, income)
			else
				table.sort(p.Podium)
				if income > p.Podium[1] then
					p.Podium[1] = income
				end
			end
			-- an ingot of the next blaster's rarity goes to the Foundry stock
			if recipe and #p.Furnaces > 0 and rarityOrder[ore.Rarity] >= rarityOrder[recipe.MinRarity] then
				p.IngotsReady = math.min(recipe.Ingots, p.IngotsReady + 1)
			end
		end
		local income = saleRate(p, cleaned, raw, floor) + podiumIncome(p)
		p.Coins += income * A.Step
		p.Earned += income * A.Step
		t += A.Step

		-- 1) the next blaster: Foundry (ingots + coins) or the Vault (4x coins)
		if recipe then
			local vault = coinsNeeded * BlasterData.Vault.PriceMultiplier
			if p.IngotsReady >= recipe.Ingots and p.Coins >= coinsNeeded then
				buy(p, "Blaster " .. (p.Blaster + 1) .. " (Foundry)", coinsNeeded, t)
				p.Blaster += 1
				p.IngotsReady = 0
				p.BlasterOre = floor.Ores[1].ore.Id
				mark(p, "Blaster " .. p.Blaster, t)
			elseif p.Coins >= vault then
				buy(p, "Blaster " .. (p.Blaster + 1) .. " (Vault)", vault, t)
				p.Blaster += 1
				p.IngotsReady = 0
				mark(p, "Blaster " .. p.Blaster, t)
			end
		end
		-- 2) the elevator once floor 4 is in reach
		local elevatorPrice = A.ElevatorPrice or A.Elevator
		if not p.Elevator and p.Blaster >= floors[4].Gate and p.Coins >= elevatorPrice then
			buy(p, "Elevator", elevatorPrice, t)
			p.Elevator = true
			mark(p, "Elevator bought", t)
		end
		-- 3) hoverboards when they cost at most a quarter of the coins
		local hover = A.Hoverboards[p.Hover + 1]
		if hover and hover.Price <= p.Coins * 0.25 then
			buy(p, "Hoverboard " .. (p.Hover + 1), hover.Price, t)
			p.Hover += 1
			mark(p, "Hoverboard " .. p.Hover .. " ($" .. hover.Price .. ")", t)
		end
		-- 4) the best-paying machine / upgrade that pays back in time, saving
		-- for the next blaster first when it is close
		local reserve = 0
		if recipe and p.IngotsReady >= recipe.Ingots then
			reserve = coinsNeeded
		end
		local bestScore, best = math.huge, nil
		for _, c in (if t % A.ShopEvery == 0 then candidates(p) else {}) do
			local g = gain(p, c[3])
			if g > 0 then
				local payback = c[2] / g
				if payback < A.Payback and payback < bestScore then
					bestScore, best = payback, c
				end
			end
		end
		if best and p.Coins - reserve >= best[2] then
			buy(p, best[1], best[2], t)
			best[3](p)
		end
		for i, floor2 in floors do
			if p.Blaster >= floor2.Gate and (not floor2.Elevator or p.Elevator) then
				mark(p, "Floor " .. i, t)
			end
		end
		if t % 300 == 0 then
			table.insert(series, { T = t, Coins = p.Coins, Earned = p.Earned, Income = income, Podium = podiumIncome(p) })
		end
	end
	return { Milestones = p.Milestones, Series = series, Log = p.Log, Final = p }
end

---------------------------------------------------------------- runs

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	return values[math.floor((#values + 1) / 2)]
end

local function runScenario(scenario: any): any
	for key, value in scenario do
		if key ~= "Name" then
			A[key] = value
		end
	end
	buildFloors()
	local runs = {}
	for seed = 1, A.Players do
		table.insert(runs, simulate(seed))
	end
	-- milestone -> median seconds and the share of players who reach it
	local keys: { [string]: boolean } = {}
	for _, run in runs do
		for key in run.Milestones do
			keys[key] = true
		end
	end
	local milestones = {}
	for key in keys do
		local times = {}
		for _, run in runs do
			local t = run.Milestones[key]
			if t then
				table.insert(times, t)
			end
		end
		table.insert(milestones, { Key = key, Median = median(times), Share = #times / #runs })
	end
	table.sort(milestones, function(a, b)
		return (a.Median or math.huge) < (b.Median or math.huge)
	end)
	local series = {}
	local length = math.huge
	for _, run in runs do
		length = math.min(length, #run.Series)
	end
	for i = 1, (if length == math.huge then 0 else length) do
		local point = runs[1].Series[i]
		local coins, earned, income, podium = {}, {}, {}, {}
		for _, run in runs do
			local sp = run.Series[i]
			table.insert(coins, sp.Coins)
			table.insert(earned, sp.Earned)
			table.insert(income, sp.Income)
			table.insert(podium, sp.Podium)
		end
		series[i] = { T = point.T, Coins = median(coins), Earned = median(earned), Income = median(income), Podium = median(podium) }
	end
	table.sort(runs, function(a, b)
		return a.Final.Earned < b.Final.Earned
	end)
	local typical = runs[math.floor((#runs + 1) / 2)]
	return {
		Name = scenario.Name,
		Efficiency = A.Efficiency,
		CrystalMode = A.CrystalMode,
		Milestones = milestones,
		Series = series,
		Log = typical.Log,
	}
end

-- `calibrate`: Foundry coin prices per blaster level so the Typical player
-- reaches each level at the target time (binary search, one level at a time).
local TARGETS = { [2] = 180, [3] = 720, [4] = 1500, [5] = 2700, [6] = 4800, [7] = 7200, [8] = 11700, [9] = 18000, [10] = 28800 }
local function calibrate(): { [number]: number }
	local prices: { [number]: number } = {}
	for level = 2, 10 do
		prices[level] = BlasterData.ByLevel[level].Recipe.Coins
	end
	local players = A.Players
	A.Players = 24
	for level = 2, 10 do
		local lo, hi = math.log(prices[level] * 0.2), math.log(prices[level] * 2e4)
		for _ = 1, 16 do
			local mid = (lo + hi) / 2
			prices[level] = math.exp(mid)
			local result = runScenario({
				Name = "Calibrate",
				Efficiency = 0.5,
				CrystalMode = "Mixed",
				BlasterCoins = prices,
				StopLevel = level,
				StopTime = TARGETS[level] * 1.05 + 60,
			})
			local reached: number? = nil
			for _, m in result.Milestones do
				if m.Key == "Blaster " .. level and m.Share >= 0.5 then
					reached = m.Median
				end
			end
			if reached and reached < TARGETS[level] then
				lo = mid
			else
				hi = mid
			end
		end
		-- a round price (2 significant digits)
		local raw = math.exp((lo + hi) / 2)
		local magnitude = 10 ^ math.floor(math.log10(raw) - 1)
		prices[level] = math.floor(raw / magnitude + 0.5) * magnitude
		print(string.format("  blaster %d: %.0f coins (target %ds)", level, prices[level], TARGETS[level]))
	end
	A.Players = players
	A.StopLevel = nil
	A.StopTime = nil
	return prices
end

-- `override=file.json`: a JSON object merged into the assumptions (any key of A,
-- e.g. IncomeMult, BlasterCoins = { "4": 400000 }, Podiums); a "Scenarios" list
-- replaces the scenario list. Works with and without `calibrate`.
for _, arg in process.args do
	local file = string.match(arg, "^override=(.+)$")
	if file then
		local override = serde.decode("json", fs.readFile(file))
		for key, value in override do
			if key == "Scenarios" then
				SCENARIOS = value
			elseif key == "BlasterCoins" then
				local prices = {}
				for level, coins in value do
					prices[tonumber(level) :: number] = coins
				end
				A.BlasterCoins = prices
			else
				A[key] = value
			end
		end
		print("override: " .. file)
	end
end

local results = {}
if process.args[1] == "calibrate" then
	print("Calibrating blaster prices for the Typical player...")
	local prices = calibrate()
	for _, name in { "Typical", "Skilled", "Casual" } do
		local efficiency = if name == "Typical" then 0.5 elseif name == "Skilled" then 0.8 else 0.3
		table.insert(
			results,
			runScenario({ Name = "Proposal " .. name, Efficiency = efficiency, CrystalMode = "Mixed", BlasterCoins = prices })
		)
	end
	results[1].Prices = prices
else
	for _, scenario in SCENARIOS do
		table.insert(results, runScenario(scenario))
	end
end

fs.writeDir(root .. "/build/balance")
local outName = if process.args[1] == "calibrate" then "proposal.json" else "sim.json"
fs.writeFile(root .. "/build/balance/" .. outName, serde.encode("json", { Assumptions = A, Scenarios = results }, true))

local function clock(seconds: number?): string
	if not seconds then
		return "-"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = math.floor(seconds % 60)
	return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm %02ds", m, s)
end
for _, result in results do
	print(
		string.format(
			"== %s (efficiency %.1f, crystals %s): milestones, median of %d players",
			result.Name,
			result.Efficiency,
			result.CrystalMode,
			A.Players
		)
	)
	for _, m in result.Milestones do
		print(string.format("  %-34s %10s  (%3d%% reach it)", m.Key, clock(m.Median), math.floor(m.Share * 100 + 0.5)))
	end
	print("  income per second (median):")
	for _, point in result.Series do
		if point.T == 600 or point.T == 1800 or point.T % 7200 == 3600 then
			print(
				string.format(
					"    %-8s income %14.0f/s  podiums %14.0f/s  coins %16.0f",
					clock(point.T),
					point.Income,
					point.Podium,
					point.Coins
				)
			)
		end
	end
	print("  purchases of the median player:")
	for _, entry in result.Log do
		print(string.format("    %-9s %-34s %14.0f", clock(entry.T), entry.What, entry.Price))
	end
end
