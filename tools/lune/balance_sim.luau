--[[
	Balance simulation: a typical player from the first minute to 10 hours.
	`lune run tools/lune/balance_sim.luau [calibrate] [override=file.json]` -> build/balance/sim.json (+ a
	summary on stdout); tools/balance/chart.mjs draws the chart and
	docs/BALANCE_SIM.md explains the model and the results.

	It reads the real config (OreData, BlasterData, ItemData, MachineData,
	EconomyConfig, ToolData (the Gear shop's Backpack levels and prices since
	steps 6-7), TrainConfig, MachineData power rules) and reads the mine
	floors straight from MineFloors.List (Ores / CrystalOres weights,
	MinBlaster gates, ViaElevator), the rock mix (SpawnChance, Seconds,
	OreCount: the floor's weakest blaster breaks a rock in ~4.5 s, ~3.3 ores
	per rock, 10 % Crystal rocks rolling from CrystalOres), the elevator price
	(2/3 of the blaster 7 forge) and the coin hoverboards (HoverboardData:
	walking x 16 / board speed, prices following their blaster level).
	A.FloorTables replaces the floors with a proposal of the same shape.

	Steps 6-7 (A.Steps67 = true, the default): the player also buys Boots,
	the coin enchants (put into the open slots where they help most), coin
	golem capsules (expected gain, equips the 3 golems that earn most),
	Hexa Lucky coin top-ups (when 5 minutes of it pay for themselves), the
	Crystal Extractor and comfort items (Lamp, Gloves, Magnet, Reach,
	Magnetism, Prospector: no income effect in the model, bought when they
	cost at most ComfortShare of the coins); finds artifacts (1 % per rock,
	deeper floors x1.25 / x1.5), gets shards from duplicates and the
	extractor, restores the last missing artifact of a collection and buys
	Epic / Legendary enchants with shards. Every bonus goes through the real
	config (GearConfig / EnchantConfig / GolemConfig / BoostConfig /
	ArtifactConfig .stats, StatConfig.combine caps) and acts on the model:
	DamagePct / OverchargePct on rock time, WalkSpeed(+Pct) on walking, ore
	luck on the ore draws (BoostConfig.rarityMult), TwinDropChance on ores per
	rock, SellPct on sales, IncomePct on podium income. Not modelled: the
	daily wheel, Robux items (Royal capsules, Robux boosts, the Mythic
	enchants), Triple Lucky, rebirths. The old IncomeMult / DamageMult /
	LuckMult / CleanSpeedMult hooks still multiply on top.

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
local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
local EnchantConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig")
local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
local LevelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LevelConfig")
local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")

-- The real rock mix (MineFloors): Small / Big / Crystal shares, seconds and ores per rock.
local spawn = MineFloors.SpawnChance
local smallShare = 1 - (spawn.Big or 0) - (spawn.Crystal or 0)
local mixSeconds = smallShare * MineFloors.Seconds.Small
	+ (spawn.Big or 0) * MineFloors.Seconds.Big
	+ (spawn.Crystal or 0) * MineFloors.Seconds.Crystal
local mixOres = smallShare * MineFloors.OreCount.Small
	+ (spawn.Big or 0) * MineFloors.OreCount.Big
	+ (spawn.Crystal or 0) * MineFloors.OreCount.Crystal

---------------------------------------------------------------- assumptions

local A = {
	Hours = 10,
	Step = 5, -- seconds per simulation step
	Players = 120, -- simulated players (seeds 1..N), medians reported
	RockSeconds = mixSeconds, -- the floor's weakest blaster per rock (MineFloors: Small / Big / Crystal mix)
	OresPerRock = mixOres,
	CrystalShare = spawn.Crystal or 0.1, -- Crystal rocks roll from the floor's CrystalOres
	RockWalk = 2.5, -- seconds from one rock to the next
	DropWalk = 12, -- seconds to carry a load to the floor's Mine Station (train) and back
	HandClean = 12, -- seconds per ore in the cleaning minigame (18 before the strong spray of 2026-10-25)
	CleanTrip = 30, -- seconds back from the base to the mine after a cleaning session (8 with the elevator)
	CleanBatch = 20, -- ores cleaned per session at the base
	TrainLoad = 5, -- seconds the train waits / loads at the station
	HandGrades = { Rough = 0.1, Clean = 0.4, Pristine = 0.35, Flawless = 0.15 }, -- a typical player
	Podiums = EconomyConfig.Podiums.Free, -- free podiums (owner 2026-10-24: 3; 4 and 5 are a Robux perk)
	-- the coin hoverboards: the blaster level each price follows (HoverboardData.priceFrom), in board order
	HoverboardLevels = { 3, 5, 7 },
	-- the floors: MineFloors.List, or a proposal (a list of { MinBlaster, ViaElevator, Ores = { [oreId] = weight },
	-- CrystalOres = { [oreId] = weight }, ZoneId? } in floor order)
	FloorTables = nil :: { any }?,
	Payback = 20 * 60, -- a machine or upgrade is bought when it pays back within this many seconds
	PolePrice = 500,
	MaxCleaners = 4,
	MaxFurnaces = 3,
	-- one Furnace (owner 2026-10-24): every furnace of the player is at the same tier (the Tech
	-- shop's Furnace Upgrade: Brick, Blast, Plasma), it smelts crushed piles only and the Crusher
	-- comes with the starter kit. false = the old roster (Clay + a Brick, a Blast, a Plasma Furnace,
	-- clean ore smelts too, the Crusher is bought).
	OneFurnace = true,
	Efficiency = 1, -- share of the player's own actions done well (mining, carrying, hand cleaning); machines run full
	BlasterCoins = nil :: { [number]: number }?, -- Foundry coin price per level instead of BlasterData's (Vault = 4x)
	ElevatorPrice = nil :: number?, -- nil = MineFloors' rule: 2/3 of the blaster 7 forge (the sim's price)
	StopLevel = nil :: number?, -- calibration: stop a run once this blaster level is reached...
	StopTime = nil :: number?, -- ...or after this many seconds
	ShopEvery = 30, -- seconds between machine / upgrade shopping decisions
	CalibratePlayers = 24, -- players per calibration run
	-- price / design options (override files; nil = today's config)
	MachinePrices = nil :: { [string]: number }?, -- machine id -> price instead of MachineData's
	EnchantCoinMult = nil :: { [string]: number }?, -- enchant rarity -> multiplier on the coin prices
	HexaForgeShare = nil :: number?, -- Hexa Lucky's coin offer: share of the next forge
	TrainCapacityExtra = nil :: { { Value: number, Price: number } }?, -- train capacity levels after the config's last
	TrainSpeedExtra = nil :: { { Value: number, Price: number } }?, -- train trip seconds levels after the config's last
	MachineUpgrades = true, -- buy the Tech shop's Speed / Quality upgrades (Auto Cleaner, Crusher): in the game since option 3
	TierPriceMult = nil :: { number }?, -- one Furnace: a multiplier per tier on the Furnace Upgrade prices
	UpgradePriceMult = nil :: { [string]: number }?, -- "Speed" / "Quality" -> multiplier on the upgrade prices
	UpgradeCurves = nil :: { [string]: { number } }?, -- "Speed" / "Quality" -> a new base curve (each machine keeps its factor)
	-- bonus hooks (steps 6-7: golems, boosts, enchants, gear, artifact sets): 1 = none
	IncomeMult = 1, -- podium income and every sale
	-- the player LEVEL (LevelConfig, owner 2026-10-21): XP from rocks, ores, cleans, sales,
	-- play time and buys; level-up coins; +BonusPerLevel podium income (outside the IncomePct cap)
	Levels = false,
	DamageMult = 1, -- blaster damage
	LuckMult = 1, -- the crystal-rock share (better ores)
	CleanSpeedMult = 1, -- Auto Cleaner speed
	-- steps 6-7 purchases and finds (see the header)
	Steps67 = true,
	ComfortShare = 0.1, -- comfort items are bought when they cost at most this share of the coins
	BaseWalk = 16, -- studs/s the walk times above assume (Boots 0)
	CapsulePrices = nil :: { [string]: number }?, -- coin capsule base price (x LevelScale) instead of CapsuleConfig's
	LevelScale = nil :: { number }?, -- capsule price multiplier per blaster level instead of CapsuleConfig's
	CrystalMode = "Mixed", -- a label only (the floors come from MineFloors / FloorTables; kept for old override files)
	-- the droppers (DropperConfig, 2026-10-21): buy the next dropper (one of each, in order) or a Money
	-- Laser (one: the droppers' belts merge before it, 2026-10-24) when it costs at most DropperMinutes
	-- of the current total income
	Droppers = false,
	DropperMinutes = 30,
	-- real ore on the belts (2026-10-24): the droppers earn when their Drops sell in a Sell Box.
	-- DropBeltSeconds: a Drop's ride from the dropper to the Sell Box (live Drops = droppers /
	-- DropEvery x this, capped at DropperConfig.MaxLiveDrops: a long line slows the droppers);
	-- DropLoss: the share that falls off a belt or waits too long (DropLife). 0 / 0 = the old passive income.
	DropBeltSeconds = 8,
	DropLoss = 0.03,
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

local floors = {}

-- One floor's ore chances before luck: the plain table and the crystal rocks
-- (CrystalShare x the old LuckMult hook) merged into { ore, p } (sum 1).
local function combined(ores: { { ore: any, w: number } }, crystal: { { ore: any, w: number } }): { { ore: any, p: number } }
	local share = math.min(1, A.CrystalShare * A.LuckMult)
	local out = {}
	for _, part in { { ores, 1 - share }, { crystal, share } } do
		local list, weight = part[1], part[2]
		local total = 0
		for _, e in list do
			total += e.w
		end
		for _, e in list do
			table.insert(out, { ore = e.ore, p = weight * e.w / total })
		end
	end
	return out
end

-- A { [oreId] = weight } table as a list (cheapest first; unknown ores skipped).
local function weighted(map: { [string]: number }): { { ore: any, w: number } }
	local list = {}
	for oreId, w in map do
		local ore = OreData.ById[oreId]
		if ore and w > 0 then
			table.insert(list, { ore = ore, w = w })
		end
	end
	table.sort(list, function(x, y)
		return x.ore.Income < y.ore.Income
	end)
	return list
end

-- The artifact zone of a floor: its WorldLayout zone, else the depth class of its gate.
local function artifactZone(def: any): string
	if def.ZoneId and WorldLayout.ZoneById[def.ZoneId] then
		return def.ZoneId
	end
	return if def.MinBlaster >= 5 then "DeepHollow" elseif def.MinBlaster >= 3 then "EmberCaves" else "Quarry"
end

-- The floors from MineFloors.List (or the proposal in A.FloorTables), in order.
local function buildFloors()
	table.clear(floors)
	for i, def in A.FloorTables or MineFloors.List do
		local ores, crystal = weighted(def.Ores), weighted(def.CrystalOres)
		floors[i] = {
			Index = i,
			Name = "Floor " .. i,
			Gate = def.MinBlaster,
			Elevator = def.ViaElevator == true,
			Ores = ores,
			Crystal = crystal,
			Odds = combined(ores, crystal),
			ArtifactZone = artifactZone(def),
			-- HP: the floor's weakest allowed (rusty) blaster needs RockSeconds (MineFloors.rockHealth)
			HP = BlasterData.damage(def.MinBlaster, "") * A.RockSeconds,
		}
	end
end

-- The first floor only the elevator reaches (nil: none).
local function elevatorFloor(): any
	for _, floor in floors do
		if floor.Elevator then
			return floor
		end
	end
	return nil
end

-- The floor's ore chances at ore luck `luck` (every ore's chance x
-- BoostConfig.rarityMult, normalised: what BoostConfig.oreOdds does).
local function luckyOdds(floor: any, luck: number): { { ore: any, p: number } }
	if luck <= 1 then
		return floor.Odds
	end
	local cache = floor.LuckCache
	if not cache then
		cache = {}
		floor.LuckCache = cache
	end
	local key = math.floor(luck * 1000 + 0.5)
	local hit = cache[key]
	if hit then
		return hit
	end
	local out, total = {}, 0
	for _, e in floor.Odds do
		local w = e.p * BoostConfig.rarityMult(e.ore.Rarity, luck)
		total += w
		table.insert(out, { ore = e.ore, p = w })
	end
	for _, e in out do
		e.p /= total
	end
	cache[key] = out
	return out
end

local function drawOre(rng: any, floor: any, luck: number): any
	local odds = luckyOdds(floor, luck)
	local roll = rng:range(0, 1)
	for _, e in odds do
		roll -= e.p
		if roll <= 0 then
			return e.ore
		end
	end
	return odds[#odds].ore
end

local function meanValue(floor: any, luck: number): number
	local sum = 0
	for _, e in luckyOdds(floor, luck) do
		sum += e.p * e.ore.Value
	end
	return sum
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

-- The Foundry coins of a blaster level in this run (A.BlasterCoins or BlasterData).
local function forgeCoins(level: number): number
	local entry = BlasterData.ByLevel[level]
	return (A.BlasterCoins and A.BlasterCoins[level]) or (entry and entry.Recipe and entry.Recipe.Coins) or 0
end

-- 2 significant digits, the way MineFloors and HoverboardData round their prices.
local function round2(raw: number): number
	if raw <= 0 then
		return 0
	end
	local step = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	return math.floor(raw / step + 0.5) * step
end

-- The elevator's price: 2/3 of the blaster 7 forge (MineFloors' rule) unless overridden.
local function elevatorPrice(): number
	return A.ElevatorPrice or round2(forgeCoins(7) * 2 / 3)
end

-- The coin hoverboards in order: { Price, Walk } (price follows its blaster level like
-- HoverboardData.priceFrom; Walk = the time factor against Boots 0 walking).
local function hoverboards(): { { Price: number, Walk: number } }
	local list = {}
	local i = 0
	for _, board in HoverboardData.List do
		if board.Kind == "Coins" and board.Price then
			i += 1
			local level = A.HoverboardLevels[i]
			local configCoins = if level then BlasterData.ByLevel[level].Recipe.Coins else 0
			local price = if level and configCoins > 0 then round2(board.Price / configCoins * forgeCoins(level)) else board.Price
			table.insert(list, { Price = price, Walk = A.BaseWalk / board.Speed })
		end
	end
	return list
end

local function machinePrice(id: string): number
	return (A.MachinePrices and A.MachinePrices[id]) or MachineData.ById[id].Price
end

local function enchantCoins(enchant: any, tier: number): number?
	local coins = EnchantConfig.nextPrice(enchant.Id, tier)
	local mult = A.EnchantCoinMult and A.EnchantCoinMult[enchant.Rarity]
	return if coins and mult then coins * mult else coins
end

-- Train levels: the config's list plus the option's extra levels.
local function trainList(list: { any }, extra: { any }?): { any }
	if not extra then
		return list
	end
	local out = table.clone(list)
	for _, level in extra do
		table.insert(out, level)
	end
	return out
end

local function trainCapacity(level: number): number
	local list = trainList(TrainConfig.Capacity, A.TrainCapacityExtra)
	return list[math.clamp(level + 1, 1, #list)].Value
end

local function trainTrip(level: number): number
	local list = trainList(TrainConfig.Speed, A.TrainSpeedExtra)
	return list[math.clamp(level + 1, 1, #list)].Value
end

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
		Crusher = A.OneFurnace == true, -- the starter kit's Crusher (one Furnace)
		Extractor = false,
		Upgrades = { CleanerSpeed = 0, CleanerQuality = 0, CrusherSpeed = 0 }, -- Tech shop levels (MachineUpgrades)
		Furnaces = { "ClayFurnace" }, -- the starter kit
		FurnaceTier = 0, -- one Furnace: the tier every furnace is at
		PowerOut = 0,
		PowerDemand = 0,
		Poles = 0,
		Podium = {} :: { number },
		IngotsReady = 0, -- ingots of the next blaster's rarity put aside
		Pending = 0, -- fractional ores carried between steps
		-- steps 6-7 (the save's shapes, so the real config helpers read them)
		Gear = { Boots = 0, HelmetLamp = 0, Backpack = 0, Gloves = 0, Magnet = 0 },
		Enchants = { Owned = {}, Slots = { "", "", "", "" } },
		Golems = { Owned = {}, Equipped = {}, NextId = 1 },
		Artifacts = { Found = {}, Chapters = {} },
		Shards = 0,
		ShardPending = 0,
		HexaUntil = 0, -- sim seconds
		Now = 0,
		Stats = nil :: any,
		Milestones = {} :: { [string]: number },
		Log = {} :: { any },
	}
end

-- A copy deep enough that a purchase applied to it leaves `p` untouched.
local function clonePlayer(p: any): any
	local q = table.clone(p)
	q.Furnaces = table.clone(p.Furnaces)
	q.Upgrades = table.clone(p.Upgrades)
	q.Gear = table.clone(p.Gear)
	q.Enchants = { Owned = table.clone(p.Enchants.Owned), Slots = table.clone(p.Enchants.Slots) }
	q.Golems = { Owned = table.clone(p.Golems.Owned), Equipped = table.clone(p.Golems.Equipped), NextId = p.Golems.NextId }
	q.Stats = nil
	return q
end

-- The bonus totals, the way src/server/Bonuses.luau sums them (cached until
-- a purchase clears p.Stats or Hexa Lucky starts / runs out). The gear,
-- enchant and collection parts are cached on their own (GearStats,
-- EnchantStats, CollectionStats: whoever changes one clears it).
local function statsOf(p: any): { [string]: number }
	local hexa = p.HexaUntil > p.Now
	if p.Stats and p.StatsHexa == hexa then
		return p.Stats
	end
	if not A.Steps67 then
		p.Stats = StatConfig.empty()
		p.StatsHexa = hexa
		return p.Stats
	end
	p.GearStats = p.GearStats or GearConfig.stats(p.Gear)
	p.EnchantStats = p.EnchantStats or EnchantConfig.stats(p.Enchants, p.Blaster)
	p.CollectionStats = p.CollectionStats or ArtifactConfig.stats(p.Artifacts)
	local enchants, collections = p.EnchantStats, p.CollectionStats
	local bond = math.min(1, (enchants.GolemBondPct or 0) + (collections.GolemBondPct or 0))
	local partials = {
		p.GearStats,
		enchants,
		GolemConfig.stats(p.Golems, bond),
		collections,
	}
	if hexa then
		table.insert(partials, { OreLuckMult = BoostConfig.Kinds.HexaLucky.Mult })
	end
	p.Stats = StatConfig.combine(partials)
	p.StatsHexa = hexa
	return p.Stats
end

local function luckOf(p: any): number
	local stats = statsOf(p)
	return StatConfig.oreLuck(stats.OreLuckPct, stats.OreLuckMult)
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
	if A.OneFurnace then
		local info = MachineData.info("ClayFurnace", p.FurnaceTier)
		local each = (info.Batch or 1) / (info.Time :: number)
		return #p.Furnaces * each * (if (info.Power or 0) > 0 then speed else 1)
	end
	for _, id in p.Furnaces do
		for _, f in FURNACES do
			if f.Id == id then
				rate += f.Rate * (if f.Power > 0 then speed else 1)
			end
		end
	end
	return rate
end

-- Walking time factor: the hoverboard or the boots (Bonuses.walkSpeed), whichever is faster.
local function walkMult(p: any): number
	local stats = statsOf(p)
	local base = if (stats.WalkSpeed or 0) > 0 then stats.WalkSpeed else A.BaseWalk
	local speed = math.clamp(base * (1 + (stats.WalkSpeedPct or 0)), 8, 50)
	local boots = A.BaseWalk / speed
	local hover = if p.Hover > 0 then hoverboards()[p.Hover].Walk else 1
	return math.min(boots, hover)
end

-- Ores per second the player delivers (mined, carried, through the train) and
-- cleans; raw ores per second sold dirty (the cleaners can't keep up); rocks
-- broken per second.
local function flow(p: any): (number, number, any, number)
	local floor = bestFloor(p)
	local stats = statsOf(p)
	local dps = BlasterData.damage(p.Blaster, p.BlasterOre) * A.DamageMult * (1 + (stats.DamagePct or 0))
	-- Overcharge speeds up the rock's last third (Bonuses.damageMult)
	local breakTime = floor.HP / dps * (2 / 3 + 1 / 3 / (1 + (stats.OverchargePct or 0)))
	local rockTime = breakTime + A.RockWalk * walkMult(p)
	local perRock = A.OresPerRock * (1 + (stats.TwinDropChance or 0))
	local perOre = (rockTime / perRock + A.DropWalk * walkMult(p) / ToolData.carryCapacity(p.Carry, false)) / A.Efficiency
	local cap = trainCapacity(p.TrainCap)
	local trainRate = cap / (trainTrip(p.TrainSpeed) + TrainConfig.ReturnSeconds + A.TrainLoad)
	if p.Cleaners == 0 then
		local trip = if p.Elevator then 8 else A.CleanTrip
		local handPerOre = perOre + (A.HandClean + trip / A.CleanBatch) / A.Efficiency
		local rate = math.min(1 / handPerOre, trainRate)
		return rate, 0, floor, rate / perRock
	end
	local delivered = math.min(1 / perOre, trainRate)
	local cleanTime = MachineData.ById.AutoCleaner.Time * MachineData.speedMult(p.Upgrades.CleanerSpeed)
	local cleanRate = p.Cleaners * A.CleanSpeedMult / cleanTime
	local cleaned = math.min(delivered, cleanRate)
	return cleaned, delivered - cleaned, floor, delivered / perRock
end

-- Crushed piles per second (the Crusher makes 2 per ore) and the extractor's shards per second.
local function crushRate(p: any, cleaned: number): number
	if not p.Crusher then
		return 0
	end
	return math.min(cleaned, 1 / (MachineData.ById.Crusher.Time * MachineData.speedMult(p.Upgrades.CrusherSpeed))) * 2
end

local function shardRate(p: any, cleaned: number): number
	if not p.Extractor then
		return 0
	end
	local extractor = MachineData.ById.CrystalExtractor
	local piles = math.min(crushRate(p, cleaned), powerSpeed(p) / extractor.Time)
	return piles * extractor.ShardChance
end

-- Coins per second from selling (expected), given the cleaned flow.
local function saleRate(p: any, cleaned: number, raw: number, floor: any): number
	local value = meanValue(floor, luckOf(p))
	local grade = if p.Cleaners > 0 then meanGradeMult(MachineData.gradeOdds(p.Upgrades.CleanerQuality)) else meanGradeMult(A.HandGrades)
	local f = furnaceRate(p)
	local perClean: number
	if p.Crusher then
		local crushIn = math.min(cleaned, 1 / (MachineData.ById.Crusher.Time * MachineData.speedMult(p.Upgrades.CrusherSpeed)))
		local crushed = crushIn * 2
		local ingots = math.min(crushed, f)
		local total = ingots * 1.25 + (crushed - ingots) * 0.75 + (cleaned - crushIn) * 1.0
		perClean = if cleaned > 0 then total / cleaned else 0
	else
		local ingots = math.min(cleaned, f)
		perClean = if cleaned > 0 then (ingots * 1.25 + (cleaned - ingots)) / cleaned else 0
	end
	local sell = 1 + (statsOf(p).SellPct or 0)
	return (cleaned * value * grade * perClean + raw * value * ItemData.Kinds.Raw.ValueMult) * A.IncomeMult * sell
end

local function podiumIncome(p: any): number
	local sum = 0
	for _, v in p.Podium do
		sum += v
	end
	local level = if A.Levels then LevelConfig.bonusFor(p.Level or 1) else 0
	return sum * A.IncomeMult * (1 + (statsOf(p).IncomePct or 0) + level)
end

local function incomeRate(p: any): number
	local cleaned, raw, floor = flow(p)
	return saleRate(p, cleaned, raw, floor) + podiumIncome(p)
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

-- Puts an owned enchant into a slot: a free open slot, else in place of the
-- slotted one whose swap earns most (only when the swap earns more).
local function placeEnchant(p: any, id: string)
	local slots = p.Enchants.Slots
	local open = EnchantConfig.unlockedSlots(p.Blaster)
	p.Stats = nil
	p.EnchantStats = nil
	for i = 1, open do
		if slots[i] == id then
			return
		end
	end
	for i = 1, open do
		if slots[i] == "" then
			slots[i] = id
			return
		end
	end
	local bestSlot, bestRate = nil, incomeRate(p)
	for i = 1, open do
		local old = slots[i]
		slots[i] = id
		p.Stats = nil
		p.EnchantStats = nil
		local rate = incomeRate(p)
		slots[i] = old
		p.Stats = nil
		p.EnchantStats = nil
		if rate > bestRate + 1e-9 then
			bestSlot, bestRate = i, rate
		end
	end
	if bestSlot then
		slots[bestSlot] = id
		p.Stats = nil
		p.EnchantStats = nil
	end
end

-- After a blaster level opens a slot: every owned enchant not slotted yet gets a go.
local function refillSlots(p: any)
	for id in p.Enchants.Owned do
		placeEnchant(p, id)
	end
end

-- What one golem of each kind earns alone (income per second), once per shopping step.
local function golemGains(p: any): { [string]: number }
	if p.GolemGains and p.Now - p.GolemGainsAt < 300 and p.GolemGainsBlaster == p.Blaster then
		return p.GolemGains -- refreshed every 5 minutes and on a new blaster
	end
	local q = clonePlayer(p)
	q.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
	local base = incomeRate(q)
	local gains = {}
	for _, golem in GolemConfig.List do
		q.Golems = { Owned = { { Id = 1, Kind = golem.Id } }, Equipped = { 1 }, NextId = 2 }
		q.Stats = nil
		gains[golem.Id] = incomeRate(q) - base
	end
	p.GolemGains, p.GolemGainsAt, p.GolemGainsBlaster = gains, p.Now, p.Blaster
	return gains
end

-- Equips the 3 owned golems that earn most alone.
local function equipGolems(p: any, gains: { [string]: number })
	local list = table.clone(p.Golems.Owned)
	table.sort(list, function(a: any, b: any): boolean
		return (gains[a.Kind] or 0) > (gains[b.Kind] or 0)
	end)
	local equipped = {}
	for i = 1, math.min(GolemConfig.EquipSlots, #list) do
		if (gains[list[i].Kind] or 0) > 0 then
			table.insert(equipped, list[i].Id)
		end
	end
	p.Golems.Equipped = equipped
	p.Stats = nil
end

-- Adds a golem; a full inventory drops the least useful unequipped one.
local function addGolem(p: any, kind: string, gains: { [string]: number })
	local golems = p.Golems
	if GolemConfig.room(golems) <= 0 then
		local worst, worstGain = nil, math.huge
		for i, entry in golems.Owned do
			if not table.find(golems.Equipped, entry.Id) and (gains[entry.Kind] or 0) < worstGain then
				worst, worstGain = i, gains[entry.Kind] or 0
			end
		end
		if worst then
			table.remove(golems.Owned, worst)
		end
	end
	GolemConfig.add(golems, kind)
end

local function capsulePrice(p: any, capsuleId: string, count: number): number
	local base = (A.CapsulePrices and A.CapsulePrices[capsuleId]) or CapsuleConfig.ById[capsuleId].Price
	local scale = if A.LevelScale then A.LevelScale[p.Blaster] else CapsuleConfig.levelScale(p.Blaster)
	return base * scale * (if count == 10 then 10 * CapsuleConfig.TenDiscount else count)
end

-- Expected income gain of opening one capsule: each golem that would make
-- the top 3 is tried on a copy.
local function capsuleGain(p: any, capsuleId: string, gains: { [string]: number }): number
	local weakest = if #p.Golems.Equipped < GolemConfig.EquipSlots then 0 else math.huge
	for _, id in p.Golems.Equipped do
		local entry = GolemConfig.find(p.Golems, id)
		if entry then
			weakest = math.min(weakest, gains[entry.Kind] or 0)
		end
	end
	local before = incomeRate(p)
	local expected = 0
	for _, line in CapsuleConfig.odds(capsuleId, false) do
		if (gains[line.Golem] or 0) > weakest then
			local q = clonePlayer(p)
			addGolem(q, line.Golem, gains)
			equipGolems(q, gains)
			expected += line.Chance * math.max(0, incomeRate(q) - before)
		end
	end
	return expected
end

-- Purchase candidates: { Name, Price, Apply(p, rng), Gain? (expected, else measured on a copy) }.
local function candidates(p: any): { any }
	local list = {}
	local carry = ToolData.CarryLevels[p.Carry + 1]
	if carry then
		table.insert(list, {
			Name = "Carry " .. carry.Name,
			Price = carry.Price,
			Apply = function(q)
				q.Carry += 1
				q.Gear.Backpack = q.Carry - 1
				q.GearStats = nil
			end,
		})
	end
	local cap = trainList(TrainConfig.Capacity, A.TrainCapacityExtra)[p.TrainCap + 2]
	if cap then
		table.insert(list, {
			Name = "Train capacity " .. cap.Value,
			Price = cap.Price,
			Apply = function(q)
				q.TrainCap += 1
			end,
		})
	end
	local speed = trainList(TrainConfig.Speed, A.TrainSpeedExtra)[p.TrainSpeed + 2]
	if speed then
		table.insert(list, {
			Name = "Train speed " .. speed.Value .. " s",
			Price = speed.Price,
			Apply = function(q)
				q.TrainSpeed += 1
			end,
		})
	end
	if p.Cleaners < A.MaxCleaners then
		table.insert(list, {
			Name = "Auto Cleaner #" .. (p.Cleaners + 1),
			Price = machinePrice("AutoCleaner"),
			Apply = function(q)
				q.Cleaners += 1
			end,
		})
	end
	-- the Tech shop's type upgrades (option MachineUpgrades)
	if A.MachineUpgrades then
		for _, up in
			{
				{ Key = "CleanerSpeed", Machine = "AutoCleaner", Kind = "Speed", Needs = p.Cleaners > 0 },
				{ Key = "CleanerQuality", Machine = "AutoCleaner", Kind = "Quality", Needs = p.Cleaners > 0 },
				{ Key = "CrusherSpeed", Machine = "Crusher", Kind = "Speed", Needs = p.Crusher },
			}
		do
			local prices = MachineData.upgradePrices(up.Machine, up.Kind)
			local mult = (A.UpgradePriceMult and A.UpgradePriceMult[up.Kind]) or 1
			local level = p.Upgrades[up.Key] + 1
			local price = prices and prices[level]
			local curve = A.UpgradeCurves and A.UpgradeCurves[up.Kind]
			if price and curve and prices then
				-- the machine's factor on the base curve, applied to the new curve
				local factor = prices[1] / MachineData.UpgradeCurves[up.Kind][1]
				price = curve[level] and curve[level] * factor or nil
			end
			price = if price then price * mult else nil
			if up.Needs and price then
				table.insert(list, {
					Name = up.Machine .. " " .. up.Kind .. " " .. (p.Upgrades[up.Key] + 1),
					Price = price,
					Cat = "Upgrades",
					Apply = function(q)
						q.Upgrades[up.Key] += 1
					end,
				})
			end
		end
	end
	if not p.Crusher then
		table.insert(list, {
			Name = "Crusher",
			Price = machinePrice("Crusher"),
			Apply = function(q)
				q.Crusher = true
			end,
		})
	end
	if A.OneFurnace then
		-- the Furnace Upgrade turns every furnace (more power for each), or one more furnace
		local tiers = MachineData.ById.ClayFurnace.Upgrades.Tier :: { number }
		local now = MachineData.info("ClayFurnace", p.FurnaceTier)
		if p.FurnaceTier < #tiers then
			local nextTier = MachineData.info("ClayFurnace", p.FurnaceTier + 1)
			local more = #p.Furnaces * ((nextTier.Power or 0) - (now.Power or 0))
			local extra, out = powerCost(p, more)
			local price = tiers[p.FurnaceTier + 1] * ((A.TierPriceMult and A.TierPriceMult[p.FurnaceTier + 1]) or 1)
			table.insert(list, {
				Name = "Furnace " .. nextTier.Name .. (if extra > 0 then " + power" else ""),
				Price = price + extra,
				Cat = "Upgrades",
				Apply = function(q)
					q.FurnaceTier += 1
					q.PowerDemand += more
					q.PowerOut += out
					if out > 0 then
						q.Poles = math.max(q.Poles, 2)
					end
				end,
			})
		end
		if #p.Furnaces < A.MaxFurnaces + 1 then
			local extra, out = powerCost(p, now.Power or 0)
			table.insert(list, {
				Name = "Furnace #" .. (#p.Furnaces + 1) .. (if extra > 0 then " + power" else ""),
				Price = machinePrice("ClayFurnace") + extra,
				Apply = function(q)
					table.insert(q.Furnaces, "ClayFurnace")
					q.PowerDemand += now.Power or 0
					q.PowerOut += out
					if out > 0 then
						q.Poles = math.max(q.Poles, 2)
					end
				end,
			})
		end
	elseif #p.Furnaces < A.MaxFurnaces + 1 then
		for _, f in FURNACES do
			if f.Id ~= "ClayFurnace" and not table.find(p.Furnaces, f.Id) then
				local extra, out = powerCost(p, f.Power)
				table.insert(list, {
					Name = f.Id .. (if extra > 0 then " + power" else ""),
					Price = machinePrice(f.Id) + extra,
					Apply = function(q)
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
	if not A.Steps67 then
		return list
	end
	-- steps 6-7 items that would have to earn more than twice today's income
	-- to pay back in time are skipped (saves the model a lot of work)
	local budget = incomeRate(p) * A.Payback * 2
	-- Boots (walking)
	local boots = GearConfig.nextPrice("Boots", p.Gear.Boots)
	if boots and boots <= budget then
		table.insert(list, {
			Name = "Boots " .. (p.Gear.Boots + 1),
			Price = boots,
			Cat = "Gear",
			Apply = function(q)
				q.Gear.Boots += 1
				q.GearStats = nil
				q.Stats = nil
			end,
		})
	end
	-- coin enchants that change the income (the comfort ones: comfortItems)
	for _, enchant in EnchantConfig.List do
		local tier = EnchantConfig.tierOf(p.Enchants, enchant.Id)
		local coins = enchantCoins(enchant, tier)
		if coins and not enchant.Product and coins <= budget then
			table.insert(list, {
				Name = enchant.Name .. " " .. EnchantConfig.TierNames[tier + 1],
				Price = coins,
				Cat = "Enchants",
				Apply = function(q)
					q.Enchants.Owned[enchant.Id] = tier + 1
					placeEnchant(q, enchant.Id)
				end,
			})
		end
	end
	-- coin golem capsules (one at a time; x10 when ten fit in the budget)
	for _, capsule in CapsuleConfig.List do
		if capsule.Currency == "Coins" and capsulePrice(p, capsule.Id, 1) <= budget then
			local gains = golemGains(p)
			local expected = capsuleGain(p, capsule.Id, gains)
			for _, count in { 10, 1 } do
				table.insert(list, {
					Name = capsule.Name .. " x" .. count,
					Price = capsulePrice(p, capsule.Id, count),
					Cat = "Capsules",
					Gain = expected * count * (if count == 10 then 0.8 else 1), -- later picks overlap the first ones
					Apply = function(q, rng)
						q.CapsulesOpened = (q.CapsulesOpened or 0) + count
						for _ = 1, count do
							local golem = CapsuleConfig.roll(capsule.Id, false, rng:range(0, 1))
							if golem then
								addGolem(q, golem, gains)
								local rarity = GolemConfig.ById[golem].Rarity
								q.NewGolems = q.NewGolems or {}
								q.NewGolems[rarity] = true
							end
						end
						equipGolems(q, gains)
					end,
				})
			end
		end
	end
	return list
end

-- Comfort items: no income effect in the model, bought when cheap enough.
local function comfortItems(p: any): { any }
	local list = {}
	if not A.Steps67 then
		return list
	end
	for _, line in { "HelmetLamp", "Gloves", "Magnet" } do
		local price = GearConfig.nextPrice(line, p.Gear[line])
		if price then
			table.insert(list, {
				Name = line .. " " .. (p.Gear[line] + 1),
				Price = price,
				Apply = function(q)
					q.Gear[line] += 1
					q.GearStats = nil
					q.Stats = nil
				end,
			})
		end
	end
	for _, id in { "Reach", "Magnetism", "Prospector" } do
		local tier = EnchantConfig.tierOf(p.Enchants, id)
		local coins = enchantCoins(EnchantConfig.ById[id], tier)
		if coins then
			table.insert(list, {
				Name = EnchantConfig.ById[id].Name .. " " .. EnchantConfig.TierNames[tier + 1],
				Price = coins,
				Apply = function(q)
					q.Enchants.Owned[id] = tier + 1
					placeEnchant(q, id)
				end,
			})
		end
	end
	if p.Crusher and not p.Extractor then
		local extractor = MachineData.ById.CrystalExtractor
		local extra, out = powerCost(p, extractor.Power or 0)
		table.insert(list, {
			Name = "Crystal Extractor" .. (if extra > 0 then " + power" else ""),
			Price = machinePrice("CrystalExtractor") + extra,
			Apply = function(q)
				q.Extractor = true
				q.PowerDemand += extractor.Power or 0
				q.PowerOut += out
				if out > 0 then
					q.Poles = math.max(q.Poles, 2)
				end
			end,
		})
	end
	return list
end

local function gain(p: any, apply: (any, any) -> (), before: number?): number
	before = before or incomeRate(p)
	local copy = clonePlayer(p)
	apply(copy, nil)
	return incomeRate(copy) - before
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

-- Steps 6-7 finds each step: artifacts from the rocks broken, shards from
-- duplicates and the extractor; shards restore an artifact or buy an enchant.
local function findAndSpendShards(p: any, rng: any, rocks: number, cleaned: number, floor: any, t: number)
	if not A.Steps67 then
		return
	end
	local stats = statsOf(p)
	local chance = ArtifactConfig.rockChance(floor.ArtifactZone) * (1 + (stats.ArtifactPct or 0))
	if rng:range(0, 1) < rocks * A.Step * chance then
		local id = ArtifactConfig.pick(floor.ArtifactZone, rng:range(0, 1))
		if id then
			local _, isNew, completed = ArtifactConfig.add(p.Artifacts, id)
			if isNew then
				mark(p, "Artifacts found: " .. ArtifactConfig.uniqueCount(p.Artifacts), t)
			else
				p.Shards += ArtifactConfig.DuplicateShards[ArtifactConfig.ById[id].Rarity]
			end
			if completed then
				mark(p, "Collection " .. ArtifactConfig.CollectionById[completed].Name, t)
				p.Stats = nil
				p.CollectionStats = nil
			end
		end
	end
	p.ShardPending += shardRate(p, cleaned) * A.Step
	if p.ShardPending >= 1 then
		local whole = math.floor(p.ShardPending)
		p.Shards += whole
		p.ShardPending -= whole
	end
	if t % A.ShopEvery ~= 0 then
		return
	end
	-- 1) the last missing artifact of a collection
	for _, collection in ArtifactConfig.Collections do
		local missing = ArtifactConfig.lastMissing(p.Artifacts, collection.Id)
		if missing then
			local price = ArtifactConfig.restoreQuote(p.Artifacts, missing, p.Blaster, p.Shards)
			if price and p.Shards >= price then
				p.Shards -= price
				ArtifactConfig.add(p.Artifacts, missing)
				p.Stats = nil
				p.CollectionStats = nil
				table.insert(p.Log, { T = t, What = "Restore " .. missing .. " (" .. price .. " shards)", Price = 0 })
				mark(p, "Collection " .. collection.Name, t)
			end
		end
	end
	-- 2) an Epic / Legendary enchant tier with shards, when it earns more
	for _, enchant in EnchantConfig.List do
		local tier = EnchantConfig.tierOf(p.Enchants, enchant.Id)
		local _, shards = EnchantConfig.nextPrice(enchant.Id, tier)
		if shards and p.Shards >= shards then
			local apply = function(q)
				q.Enchants.Owned[enchant.Id] = tier + 1
				placeEnchant(q, enchant.Id)
			end
			if gain(p, apply) > 0 or enchant.Id == "Prospector" then
				p.Shards -= shards
				apply(p)
				local name = enchant.Name .. " " .. EnchantConfig.TierNames[tier + 1]
				table.insert(p.Log, { T = t, What = name .. " (" .. shards .. " shards)", Price = 0 })
				mark(p, "Buy " .. name, t)
			end
		end
	end
end

-- The moments the report looks at (3h15 / 5h / 8h: the windows the integrator asked about).
local SNAPSHOTS = { 11700, 18000, 28800 }

local function snapshot(p: any): any
	local stats = statsOf(p)
	local equipped = {}
	for _, id in p.Golems.Equipped do
		local entry = GolemConfig.find(p.Golems, id)
		if entry then
			table.insert(equipped, entry.Kind)
		end
	end
	return {
		Blaster = p.Blaster,
		Income = incomeRate(p),
		DamagePct = stats.DamagePct,
		IncomePct = stats.IncomePct,
		SellPct = stats.SellPct,
		OreLuck = luckOf(p),
		TwinDrop = stats.TwinDropChance,
		Artifacts = ArtifactConfig.uniqueCount(p.Artifacts),
		Collections = #ArtifactConfig.completed(p.Artifacts),
		Shards = p.Shards,
		Golems = #p.Golems.Owned,
		Capsules = p.CapsulesOpened or 0,
		HexaBuys = p.HexaBuys or 0,
		Equipped = table.concat(equipped, ","),
		Spend = table.clone(p.Spend),
	}
end

-- Hexa Lucky (5 coin minutes) is topped up when 5 minutes of it pay for themselves.
local function hexaLucky(p: any, floor: any, coinsNeeded: number, reserve: number, t: number)
	if not A.Steps67 or p.HexaUntil - p.Now >= BoostConfig.CoinBuyBelow then
		return
	end
	local lucky = false
	for _, e in floor.Odds do
		if (BoostConfig.LuckPower[e.ore.Rarity] or 0) > 0 then
			lucky = true
		end
	end
	if not lucky then
		return
	end
	local offer = BoostConfig.OfferById.HexaLucky5
	-- ForgeShare of the next forge; at the top level, of the top level's own forge (BoostConfig.coinPrice)
	local forge = coinsNeeded
	if forge <= 0 then
		local top = BlasterData.MaxLevel
		forge = (A.BlasterCoins and A.BlasterCoins[top]) or BlasterData.ByLevel[top].Recipe.Coins
	end
	local share = A.HexaForgeShare or offer.ForgeShare or 0
	local price = math.max(offer.MinPrice or 0, math.floor(forge * share + 0.5))
	if p.Coins - reserve < price then
		return
	end
	local g = gain(p, function(q)
		q.HexaUntil = q.Now + offer.Seconds
	end)
	if g * offer.Seconds >= price then
		buy(p, "Hexa Lucky 5 min", price, t)
		p.Spend.Boosts = (p.Spend.Boosts or 0) + price
		p.Bought["Hexa Lucky 5 min"] = p.Bought["Hexa Lucky 5 min"] or t
		p.HexaUntil = math.max(p.HexaUntil, p.Now) + offer.Seconds
		p.HexaBuys = (p.HexaBuys or 0) + 1
		p.Stats = nil
	end
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return setmetatable(out, getmetatable(value))
end

-- `start`: a checkpoint (calibration) - the player, the clock, the random
-- state and the series at the moment a run stopped; the run continues from it.
-- The player LEVEL: XP for this step (the game's LevelConfig weights on the
-- model's flows), level ups pay their coins.
local function levelStep(p: any, rocks: number, cleaned: number, raw: number, t: number)
	if not A.Levels then
		return
	end
	local w = LevelConfig.ById
	local xp = A.Step
		* (
			rocks * w.RocksBroken.Xp
			+ (cleaned + raw) * w.OresMined.Xp
			+ cleaned * w.OresCleaned.Xp
			+ raw * w.ItemsSold.Xp
			+ w.PlaySeconds.Xp
		)
	xp += (p.BuysSeen and #p.Log - p.BuysSeen or 0) * w.Upgrades.Xp -- every buy: a machine, an upgrade, a level
	p.BuysSeen = #p.Log
	p.LevelRecord = p.LevelRecord or { Level = 1, Xp = 0, Seen = {}, Ready = true }
	for _, level in LevelConfig.add(p.LevelRecord, xp) do
		local coins = LevelConfig.coinsFor(level, podiumIncome(p))
		p.Coins += coins
		p.Earned += coins
		if level % 10 == 0 then
			mark(p, "Level " .. level, t)
		end
	end
	p.Level = p.LevelRecord.Level
end

local function simulate(seed: number, start: any?): any
	local rng = Rng.new(seed)
	local p = newPlayer()
	p.Spend = {}
	p.Bought = {}
	p.Snapshots = {}
	local series = {}
	local t = 0
	if start then
		p = deepCopy(start.Player)
		rng.state = start.RngState
		series = deepCopy(start.Series)
		t = start.T
	end
	local total = A.Hours * 3600
	local stopTime = A.StopTime or total
	while t < math.min(total, stopTime) do
		if A.StopLevel and p.Blaster >= A.StopLevel then
			break
		end
		p.Now = t
		local cleaned, raw, floor, rocks = flow(p)
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
		local luck = luckOf(p)
		while p.Pending >= 1 do
			p.Pending -= 1
			local ore = drawOre(rng, floor, luck)
			local grade = drawGrade(rng, if p.Cleaners > 0 then MachineData.gradeOdds(p.Upgrades.CleanerQuality) else A.HandGrades)
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
		if A.Droppers and p.Placed then
			-- the game's rule: a Drop sold in a Sell Box pays through the same income multiplier as the
			-- podiums; the owner's live-Drop cap and the losses on the belts slow it down
			local droppers = (p.DropperNext or 1) - 1
			local inFlight = droppers / DropperConfig.DropEvery * A.DropBeltSeconds
			local flow = if inFlight > 0 then math.min(1, DropperConfig.MaxLiveDrops / inFlight) else 1
			income += DropperConfig.placedIncome(p.Placed) * A.IncomeMult * (1 + (statsOf(p).IncomePct or 0)) * flow * (1 - A.DropLoss)
		end
		p.Coins += income * A.Step
		p.Earned += income * A.Step
		levelStep(p, rocks, cleaned, raw, t)
		findAndSpendShards(p, rng, rocks, cleaned, floor, t)
		t += A.Step

		-- 1) the next blaster: Foundry (ingots + coins) or the Vault (4x coins)
		if recipe then
			local vault = coinsNeeded * BlasterData.Vault.PriceMultiplier
			local bought = false
			if p.IngotsReady >= recipe.Ingots and p.Coins >= coinsNeeded then
				buy(p, "Blaster " .. (p.Blaster + 1) .. " (Foundry)", coinsNeeded, t)
				p.BlasterOre = floor.Ores[1].ore.Id
				bought = true
			elseif p.Coins >= vault then
				buy(p, "Blaster " .. (p.Blaster + 1) .. " (Vault)", vault, t)
				bought = true
			end
			if bought then
				p.Blaster += 1
				p.IngotsReady = 0
				p.Stats = nil
				p.EnchantStats = nil
				refillSlots(p) -- a new enchant slot may be open
				mark(p, "Blaster " .. p.Blaster, t)
			end
		end
		-- 1b) the droppers (off by default)
		if A.Droppers then
			p.Placed = p.Placed or {}
			p.DropperNext = p.DropperNext or 1
			p.Lasers = p.Lasers or 0
			local nextDropper = DropperConfig.List[p.DropperNext]
			local owned = p.DropperNext - 1
			local laser = DropperConfig.Laser
			local pick: { Id: string, Price: number, Name: string }? = nil
			if nextDropper then
				pick = { Id = nextDropper.Id, Price = nextDropper.Price, Name = nextDropper.Name }
			end
			-- (one laser on the merged line doubles every dropper: more add nothing)
			if p.Lasers < math.min(owned, 1) and (pick == nil or laser.Price < pick.Price) then
				pick = { Id = laser.Id, Price = laser.Price, Name = laser.Name }
			end
			if pick and pick.Price <= income * A.DropperMinutes * 60 and p.Coins >= pick.Price then
				buy(p, pick.Name, pick.Price, t)
				table.insert(p.Placed, { Id = pick.Id })
				if pick.Id == laser.Id then
					p.Lasers += 1
				else
					p.DropperNext += 1
				end
				mark(p, pick.Name, t)
			end
		end
		-- 2) the elevator once floor 4 is in reach
		local liftFloor = elevatorFloor()
		local liftPrice = elevatorPrice()
		if not p.Elevator and liftFloor and p.Blaster >= liftFloor.Gate and p.Coins >= liftPrice then
			buy(p, "Elevator", liftPrice, t)
			p.Elevator = true
			mark(p, "Elevator bought", t)
		end
		-- 3) hoverboards when they cost at most a quarter of the coins
		local hover = hoverboards()[p.Hover + 1]
		if hover and hover.Price <= p.Coins * 0.25 then
			buy(p, "Hoverboard " .. (p.Hover + 1), hover.Price, t)
			p.Hover += 1
			mark(p, "Hoverboard " .. p.Hover .. " ($" .. hover.Price .. ")", t)
		end
		-- 4) the best-paying machine / upgrade / steps 6-7 item that pays back
		-- in time, saving for the next blaster first when it is close
		local reserve = 0
		if recipe and p.IngotsReady >= recipe.Ingots then
			reserve = coinsNeeded
		end
		if t % A.ShopEvery == 0 then
			local bestScore, best = math.huge, nil
			local before = incomeRate(p)
			for _, c in candidates(p) do
				local g = c.Gain or gain(p, c.Apply, before)
				if g > 0 then
					local payback = c.Price / g
					if payback < A.Payback and payback < bestScore then
						bestScore, best = payback, c
					end
				end
			end
			-- while saving for the blaster, an item still gets bought when it pays
			-- back faster than the saving takes (it brings the blaster closer:
			-- (R + P) / (I + g) < R / I exactly when P / g < R / I)
			local saving = math.max(0, reserve - p.Coins) / math.max(income, 1e-9)
			local affordable = best and (p.Coins - reserve >= best.Price or (reserve > 0 and p.Coins >= best.Price and bestScore < saving))
			if best and affordable then
				buy(p, best.Name, best.Price, t)
				best.Apply(p, rng)
				p.Stats = nil
				if best.Cat then
					p.Spend[best.Cat] = (p.Spend[best.Cat] or 0) + best.Price
					p.Bought[best.Name] = p.Bought[best.Name] or t
				end
				if p.NewGolems then
					for rarity in p.NewGolems do
						mark(p, "First " .. rarity .. " golem", t)
					end
					p.NewGolems = nil
				end
			end
			-- 5) comfort items when they are cheap (one per shopping step)
			for _, c in comfortItems(p) do
				if c.Price <= (p.Coins - reserve) * A.ComfortShare then
					buy(p, c.Name, c.Price, t)
					c.Apply(p, rng)
					p.Stats = nil
					p.Spend.Comfort = (p.Spend.Comfort or 0) + c.Price
					p.Bought[c.Name] = p.Bought[c.Name] or t
					break
				end
			end
			-- 6) Hexa Lucky top-ups
			hexaLucky(p, floor, coinsNeeded, reserve, t)
		end
		for _, floor2 in floors do
			if p.Blaster >= floor2.Gate and (not floor2.Elevator or p.Elevator) then
				mark(p, floor2.Name, t)
			end
		end
		if t % 300 == 0 then
			table.insert(series, { T = t, Coins = p.Coins, Earned = p.Earned, Income = income, Podium = podiumIncome(p) })
		end
		for _, at in SNAPSHOTS do
			if t == at then
				p.Snapshots[tostring(at)] = snapshot(p)
			end
		end
	end
	return {
		Milestones = p.Milestones,
		Series = series,
		Log = p.Log,
		Final = p,
		Bought = p.Bought,
		Snapshots = p.Snapshots,
		Checkpoint = { Player = p, RngState = rng.state, Series = series, T = t },
	}
end

---------------------------------------------------------------- runs

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	return values[math.floor((#values + 1) / 2)]
end

local function runScenario(scenario: any, starts: { any }?): any
	for key, value in scenario do
		if key ~= "Name" then
			A[key] = value
		end
	end
	buildFloors()
	local runs = {}
	for seed = 1, A.Players do
		table.insert(runs, simulate(seed, starts and starts[seed]))
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
	-- steps 6-7: first purchase of each item (median time, share) and the snapshots
	local boughtKeys: { [string]: boolean } = {}
	for _, run in runs do
		for key in run.Bought do
			boughtKeys[key] = true
		end
	end
	local bought = {}
	for key in boughtKeys do
		local times = {}
		for _, run in runs do
			local t = run.Bought[key]
			if t then
				table.insert(times, t)
			end
		end
		table.insert(bought, { Key = key, Median = median(times), Share = #times / #runs })
	end
	table.sort(bought, function(a, b)
		return (a.Median or math.huge) < (b.Median or math.huge)
	end)
	local snapshots = {}
	for _, at in SNAPSHOTS do
		local key = tostring(at)
		local fields: { [string]: { number } } = {}
		local spend: { [string]: { number } } = {}
		local equipped: { [string]: number } = {}
		local count = 0
		for _, run in runs do
			local snap = run.Snapshots[key]
			if snap then
				count += 1
				for field, value in snap do
					if type(value) == "number" then
						fields[field] = fields[field] or {}
						table.insert(fields[field], value)
					end
				end
				for cat in { Gear = 1, Enchants = 1, Capsules = 1, Boosts = 1, Comfort = 1 } do
					spend[cat] = spend[cat] or {}
					table.insert(spend[cat], snap.Spend[cat] or 0)
				end
				equipped[snap.Equipped] = (equipped[snap.Equipped] or 0) + 1
			end
		end
		local out = { T = at, Players = count, Spend = {} }
		for field, values in fields do
			out[field] = median(values)
		end
		for cat, values in spend do
			out.Spend[cat] = median(values)
		end
		local top, topCount = "", 0
		for kinds, n in equipped do
			if n > topCount then
				top, topCount = kinds, n
			end
		end
		out.TopEquipped = top
		table.insert(snapshots, out)
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
		Bought = bought,
		Snapshots = snapshots,
		Runs = runs, -- dropped before saving (calibration reads the checkpoints)
	}
end

-- `calibrate`: Foundry coin prices per blaster level so the Typical player
-- reaches each level at the target time (binary search, one level at a time).
local TARGETS = { [2] = 180, [3] = 720, [4] = 1500, [5] = 2700, [6] = 4800, [7] = 7200, [8] = 11700, [9] = 18000, [10] = 28800 }
-- Each level's search starts every player from where they reached the level
-- before (checkpoints, with the final price of that level): the history up to
-- there doesn't depend on the price searched (saving for the next blaster and
-- the Hexa Lucky price only start at the level before).
local function calibrate(): { [number]: number }
	local prices: { [number]: number } = {}
	for level = 2, 10 do
		prices[level] = BlasterData.ByLevel[level].Recipe.Coins
	end
	local players = A.Players
	A.Players = A.CalibratePlayers or 24
	local starts: { any }? = nil
	local function run(level: number, stopTime: number): any
		return runScenario({
			Name = "Calibrate",
			Efficiency = 0.5,
			CrystalMode = "Mixed",
			BlasterCoins = prices,
			StopLevel = level,
			StopTime = stopTime,
		}, starts)
	end
	for level = 2, 10 do
		local lo, hi = math.log(prices[level] * 0.2), math.log(prices[level] * 2e4)
		for _ = 1, 16 do
			local mid = (lo + hi) / 2
			prices[level] = math.exp(mid)
			local result = run(level, TARGETS[level] * 1.05 + 60)
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
		-- the checkpoints for the next level: every player at the moment they reach this one
		local final = run(level, A.Hours * 3600)
		local nextStarts = {}
		for seed, r in final.Runs do
			nextStarts[seed] = r.Checkpoint
		end
		starts = nextStarts
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

local function clock(seconds: number?): string
	if not seconds then
		return "-"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = math.floor(seconds % 60)
	return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm %02ds", m, s)
end

-- Where the steps 6-7 prices sit: each item's price in minutes of the first
-- scenario's median income at the snapshot moments (3h15 / 5h / 8h), with
-- the blaster level the median player has then (capsule and boost prices
-- grow with it).
local function priceWindows(result: any): { any }
	local snaps = {}
	for _, snap in result.Snapshots or {} do
		if snap.Players > 0 and snap.Income then
			table.insert(snaps, snap)
		end
	end
	local rows = {}
	local function row(name: string, price: (number) -> number?)
		local out = { Item = name, Minutes = {}, Prices = {} }
		for i, snap in snaps do
			local value = price(math.floor(snap.Blaster or 1))
			out.Prices[i] = value
			out.Minutes[i] = if value then value / snap.Income / 60 else nil
		end
		table.insert(rows, out)
	end
	for _, line in GearConfig.Lines do
		row(line.Name .. " (all 5 levels)", function()
			local sum = 0
			for _, price in line.Prices do
				sum += price
			end
			return sum
		end)
	end
	for _, enchant in EnchantConfig.List do
		if not enchant.Product then
			for tier in enchant.Coins do
				row(enchant.Name .. " " .. EnchantConfig.TierNames[tier], function()
					return enchantCoins(enchant, tier - 1) or 0
				end)
			end
		end
	end
	for _, capsule in CapsuleConfig.List do
		if capsule.Currency == "Coins" then
			row(capsule.Name .. " x1", function(level)
				local base = (A.CapsulePrices and A.CapsulePrices[capsule.Id]) or capsule.Price
				local scale = if A.LevelScale then A.LevelScale[level] else CapsuleConfig.levelScale(level)
				return base * scale
			end)
		end
	end
	local prices = result.Prices or A.BlasterCoins
	local function forgeAfter(level: number): number
		local nextLevel = math.min(level + 1, BlasterData.MaxLevel)
		return (prices and prices[nextLevel]) or BlasterData.ByLevel[nextLevel].Recipe.Coins
	end
	for _, offer in BoostConfig.CoinOffers do
		row(offer.Id .. " (" .. offer.Seconds / 60 .. " min)", function(level)
			if offer.PriceCapsule then
				local capsule = CapsuleConfig.ById[offer.PriceCapsule]
				local scale = if A.LevelScale then A.LevelScale[level] else CapsuleConfig.levelScale(level)
				return math.max(offer.MinPrice or 0, capsule.Price * scale * (offer.PriceCount or 1))
			end
			local share = if offer.Id == "HexaLucky5" and A.HexaForgeShare then A.HexaForgeShare else offer.ForgeShare or 0
			return math.max(offer.MinPrice or 0, forgeAfter(level) * share)
		end)
	end
	row("Auto Cleaner", function()
		return machinePrice("AutoCleaner")
	end)
	row("Elevator", function()
		return elevatorPrice()
	end)
	return rows
end

if A.Steps67 and results[1] then
	results[1].PriceWindows = priceWindows(results[1])
end

for _, result in results do
	result.Runs = nil
end
fs.writeDir(root .. "/build/balance")
local outName = if process.args[1] == "calibrate" then "proposal.json" else "sim.json"
fs.writeFile(root .. "/build/balance/" .. outName, serde.encode("json", { Assumptions = A, Scenarios = results }, true))

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
	local function incomeAt(t: number): number?
		for _, point in result.Series do
			if point.T == t then
				return point.Income
			end
		end
		return nil
	end
	local i3, i5 = incomeAt(10800), incomeAt(18000)
	if i3 and i5 and i3 > 0 then
		result.Slope35 = i5 / i3
		print(string.format("  3h -> 5h income: %.3g/s -> %.3g/s (x%.2f)", i3, i5, i5 / i3))
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
	if A.Steps67 then
		print("  steps 6-7 items, first bought (median, share of players):")
		for _, m in result.Bought do
			print(string.format("    %-34s %10s  (%3d%%)", m.Key, clock(m.Median), math.floor(m.Share * 100 + 0.5)))
		end
		print("  steps 6-7 state (medians):")
		for _, snap in result.Snapshots do
			if snap.Players > 0 then
				print(
					string.format(
						"    %-8s blaster %d  income %.3g/s  damage +%d%%  income +%d%%  sell +%d%%  luck x%.2f  twin %d%%  artifacts %d  collections %d  shards %d  golems %d  capsules %d  hexa buys %d",
						clock(snap.T),
						snap.Blaster or 0,
						snap.Income or 0,
						math.floor((snap.DamagePct or 0) * 100 + 0.5),
						math.floor((snap.IncomePct or 0) * 100 + 0.5),
						math.floor((snap.SellPct or 0) * 100 + 0.5),
						snap.OreLuck or 1,
						math.floor((snap.TwinDrop or 0) * 100 + 0.5),
						snap.Artifacts or 0,
						snap.Collections or 0,
						snap.Shards or 0,
						snap.Golems or 0,
						snap.Capsules or 0,
						snap.HexaBuys or 0
					)
				)
				print(
					string.format(
						"             spent: gear %.3g  enchants %.3g  capsules %.3g  boosts %.3g  comfort %.3g   golems: %s",
						snap.Spend.Gear or 0,
						snap.Spend.Enchants or 0,
						snap.Spend.Capsules or 0,
						snap.Spend.Boosts or 0,
						snap.Spend.Comfort or 0,
						snap.TopEquipped
					)
				)
			end
		end
	end
	print("  purchases of the median player:")
	for _, entry in result.Log do
		print(string.format("    %-9s %-34s %14.0f", clock(entry.T), entry.What, entry.Price))
	end
end

if A.Steps67 and results[1] then
	local windows = results[1].PriceWindows
	print("== Where the steps 6-7 prices sit: minutes of " .. results[1].Name .. "'s median income")
	local header = "  " .. string.format("%-26s", "")
	for _, snap in results[1].Snapshots do
		if snap.Players > 0 then
			header ..= string.format(" %14s", "at " .. clock(snap.T) .. " (b" .. (snap.Blaster or 0) .. ")")
		end
	end
	print(header)
	for _, r in windows do
		local line = "  " .. string.format("%-26s", r.Item)
		for i in r.Minutes do
			local m = r.Minutes[i]
			line ..= string.format(" %14s", if m == nil then "-" elseif m < 0.1 then "<0.1" else string.format("%.1f", m))
		end
		print(line)
	end
end
