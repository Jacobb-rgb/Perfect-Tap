--[[
	Rebirth "STAR FORGE" (the owner's pick, option B of
	docs/plans/REBIRTH_PROPOSAL.md): an optional restart that keeps your
	factory and pays Forge Stars, spent in the Star Shop on lasting perks.

	- Needs your blaster at MinBlaster or higher, FORGED at the Foundry in
	  this run (reachedOf: Stats.RunForged, which FoundryService raises and
	  the reset clears; the first run counts the blaster level as it is,
	  unless a level was bought with Robux in it: Stats.RunPaid, set by
	  VaultService.grantNext "Robux" (which first keeps the levels the grace
	  counted so far in RunForged) and by a start the Robux levels lift).
	  The top level is left to the Foundry while nothing was forged
	  (topBlocked: the Vault says "ForgeFirst", the STORE "Full"), and a save
	  that still got there unforged may rebirth for starsFor(reachedOf) (0).
	  Vault cases are bought with coins only, and Podium Keeper keeps the
	  income: counting them would make the stars a few minutes of idle
	  income each. Rebirth is never forced, never sold for Robux, and
	  nothing in it is random.
	- Resets (reset(), one step on the save): the earned coins, the blaster (level 1, or
	  Head Start's level, lifted one level per blaster level ever bought with
	  Robux: startFor, in that level's Vault look), the mine floors with it
	  (MineFloors opens them by blaster level) and the elevator, the machine
	  speed (Bellows and every Tech shop Speed / Quality level), the train's
	  capacity and speed, the Backpack, and every ore you own: the Ore Pen,
	  the podiums (unless Podium Keeper), the Foundry's ingots, the train's
	  cargo, the machines' queues, the placed droppers and Money Lasers (owner
	  decision pending: keep or lose droppers; lost for now, so their income
	  can't carry the new run) (RebirthService also takes your loose and
	  carried items out of the world). Dusty relics are artifacts, never
	  ore: the ones in those lists wait in the pen (RebirthService hands them
	  to the relic keeper, which adds them to the collection). The enchants
	  stay slotted, the paid ones (Enchants.Passes) moved first into the
	  slots the new blaster level opens.
	- Keeps: the placed factory (every machine and belt where it stands), the
	  machines in your inventory, machine slots, the pen size and automation,
	  the other gear lines, golems, enchants, artifacts, the codex,
	  hoverboards, shards, every Robux item, the unspent Robux-bought coins
	  (PaidCoins, below), stats and the leaderboard totals.
	- Robux blaster levels come back (owner 2026-10-20, "don't lose what you
	  paid for"): every level bought with Robux (Stats.BlastersPaid,
	  VaultService) lifts the fresh blaster of EVERY later rebirth one level
	  (startFor), up to MaxLevel - 1: one level is always left to forge at
	  the Foundry, or the next rebirth could never be earned. They never pay
	  stars (Stats.RunPaid).
	- Pays: starsFor(reachedOf), Rebirths + 1. Stats.BestBlaster keeps the
	  highest level ever reached: coin prices that grow with the blaster
	  follow it (BlasterData.priceLevel), so a rebirth never makes capsules
	  or coin boosts cheaper.
	- Coins bought with a Robux coin pack stay while unspent (owner
	  2026-10-20): data.PaidCoins counts them (0 <= PaidCoins <= Coins;
	  PodiumService's CoinPack grant adds to it, EconomyService.spend spends
	  them last, Migrations repairs it) and reset() keeps exactly
	  Coins = PaidCoins = min(PaidCoins, Coins). The packs are off today
	  (MonetizationConfig CoinPacksEnabled).

	Stars follow the blaster prices (the machines chat recalibrates them):
	MinStars at MinBlaster, MaxStars at the top level, and in between by how
	much of the way there the level's total Foundry coins are, on a log scale
	(starsCurve). A level that costs relatively more of the run gives more
	stars; no coin number is written here. tests/Rebirth.spec.luau pins the
	relationships, not the numbers.

	Star Shop perks (StarPerks = { [perkId] = level }; a level above this
	build's top or an unknown perk a newer build sold stays in the save,
	the readers clamp):
	  GoldenTouch   +10 % podium income and sell value per level (Bonuses)
	  HeadStart     start each rebirth with blaster LV 2 / 3 / 4
	  LuckyRocks    +5 % ore luck per level (Bonuses)
	  DeepPockets   +1 item carried per level (Bonuses)
	  ExpressRails  train trips 10 % shorter per level (Bonuses: TrainTimeCutPct)
	  PodiumKeeper  the podium ores stay through rebirths
	  PlotGlow      a glowing ribbon round your plot: each level unlocks a
	                colour (GlowColors), data.PlotGlow is the one you show
	                ("" = off; RebirthService builds it, cosmetic only)
	Pure: rules and save math only (server and client both read it).
]]

local DropperConfig = require(script.Parent.DropperConfig)
local BlasterData = require(script.Parent.BlasterData)
local EnchantConfig = require(script.Parent.EnchantConfig)

export type Perk = {
	Id: string,
	Name: string,
	Text: string, -- what one level does
	Costs: { number }, -- stars for level 1, 2, ...
	Stats: { [string]: number }?, -- Bonuses stats per level (StatConfig names)
}

local RebirthConfig = {}

-- the lowest blaster level a rebirth needs (4 levels below the top)
RebirthConfig.MinBlaster = BlasterData.MaxLevel - 4
RebirthConfig.MinStars = 2 -- a rebirth at MinBlaster
RebirthConfig.MaxStars = 10 -- a rebirth at the top level
RebirthConfig.ConfirmSeconds = 4 -- the REBIRTH! button's "SURE?" waits this long for the second press
RebirthConfig.Reasons = { "NoData", "Locked", "NotForged", "Busy", "Failed", "BadPerk", "Max", "NoStars" }

RebirthConfig.Perks = {
	{
		Id = "GoldenTouch",
		Name = "Golden Touch",
		Text = "+10% podium and sell money (up to the bonus caps)",
		Costs = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		Stats = { IncomePct = 0.1, SellPct = 0.1 },
	},
	{
		Id = "HeadStart",
		Name = "Head Start",
		Text = "start each rebirth with a better blaster",
		Costs = { 3, 6, 10 },
	},
	{
		Id = "LuckyRocks",
		Name = "Lucky Rocks",
		Text = "+5% ore luck (up to the luck cap)",
		Costs = { 2, 2, 2, 2, 2 },
		Stats = { OreLuckPct = 0.05 },
	},
	{
		Id = "DeepPockets",
		Name = "Deep Pockets",
		Text = "+1 item carried",
		Costs = { 2, 3, 4 },
		Stats = { CarryCapacity = 1 },
	},
	{
		Id = "ExpressRails",
		Name = "Express Rails",
		Text = "train trips 10% shorter",
		Costs = { 2, 2, 2 },
		Stats = { TrainTimeCutPct = 0.1 },
	},
	{
		Id = "PodiumKeeper",
		Name = "Podium Keeper",
		Text = "your podium ores stay through rebirths",
		Costs = { 6 },
	},
	{
		Id = "PlotGlow",
		Name = "Plot Glow",
		Text = "a glowing ribbon round your plot, a new colour per level",
		Costs = { 1, 1, 1, 1, 1 },
	},
} :: { Perk }

export type GlowColor = { Id: string, Name: string, Color: Color3 }

-- The Plot Glow colours, one per PlotGlow level (Prism: a rainbow round the plot).
RebirthConfig.GlowColors = {
	{ Id = "Bronze", Name = "Bronze", Color = Color3.fromRGB(214, 132, 62) },
	{ Id = "Silver", Name = "Silver", Color = Color3.fromRGB(206, 218, 236) },
	{ Id = "Gold", Name = "Gold", Color = Color3.fromRGB(255, 206, 72) },
	{ Id = "Diamond", Name = "Diamond", Color = Color3.fromRGB(120, 232, 255) },
	{ Id = "Prism", Name = "Prism", Color = Color3.fromRGB(200, 120, 255) },
} :: { GlowColor }

RebirthConfig.ById = {} :: { [string]: Perk }
for _, perk in RebirthConfig.Perks do
	RebirthConfig.ById[perk.Id] = perk
end

-- the blaster level each Head Start level starts a rebirth with
RebirthConfig.HeadStartLevels = { 2, 3, 4 }

-- A star amount in words for the players ("1 star", "12 stars"): the owner's
-- "text only", no emoji (NoEmoji.spec). Buttons use string.upper of it.
function RebirthConfig.starsText(count: number): string
	return if count == 1 then "1 star" else `{count} stars`
end

---------------------------------------------------------------- stars

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The Foundry coins of every level up to `level` (level 1 is free).
function RebirthConfig.coinsTo(level: number, coinsOf: ((number) -> number)?): number
	local total = 0
	for lv = 2, level do
		if coinsOf then
			total += coinsOf(lv)
		else
			local blaster = BlasterData.ByLevel[lv]
			total += if blaster and blaster.Recipe then blaster.Recipe.Coins else 0
		end
	end
	return total
end

--[[
	The stars of each level MinBlaster..top for a price list (`coinsOf(level)`
	= that level's Foundry coins; nil = BlasterData): MinStars at MinBlaster,
	MaxStars at the top, the levels between by log(total coins to the level /
	total to MinBlaster) over the same for the top, rounded, never fewer than
	the level below. Returns { [level] = stars }.
]]
function RebirthConfig.starsCurve(coinsOf: ((number) -> number)?): { [number]: number }
	local low, top = RebirthConfig.MinBlaster, BlasterData.MaxLevel
	local base = math.max(RebirthConfig.coinsTo(low, coinsOf), 1)
	local span = math.log(math.max(RebirthConfig.coinsTo(top, coinsOf), base * 2) / base)
	local curve: { [number]: number } = {}
	local last = RebirthConfig.MinStars
	for level = low, top do
		local share = math.clamp(math.log(math.max(RebirthConfig.coinsTo(level, coinsOf), base) / base) / span, 0, 1)
		local stars = RebirthConfig.MinStars + math.floor((RebirthConfig.MaxStars - RebirthConfig.MinStars) * share + 0.5)
		last = math.max(last, stars)
		curve[level] = last
	end
	curve[top] = RebirthConfig.MaxStars
	return curve
end

local curve = RebirthConfig.starsCurve()

-- The Forge Stars a rebirth at this blaster level pays (0 below MinBlaster).
function RebirthConfig.starsFor(level: any): number
	if not finite(level) then
		return 0
	end
	local lv = math.min(math.floor(level), BlasterData.MaxLevel)
	return curve[lv] or 0
end

---------------------------------------------------------------- perks

-- A perk's level in a save's StarPerks (0..its top: a higher saved level reads as the top).
function RebirthConfig.levelOf(perks: any, id: string): number
	local perk = RebirthConfig.ById[id]
	local v = if perk and type(perks) == "table" then perks[id] else nil
	if not perk or not finite(v) or v < 1 then
		return 0
	end
	return math.min(math.floor(v), #perk.Costs)
end

-- The stars the next level of a perk costs (nil at its top or for an unknown perk).
function RebirthConfig.nextCost(perks: any, id: string): number?
	local perk = RebirthConfig.ById[id]
	if not perk then
		return nil
	end
	return perk.Costs[RebirthConfig.levelOf(perks, id) + 1]
end

-- Every star a whole Star Shop costs.
function RebirthConfig.shopTotal(): number
	local total = 0
	for _, perk in RebirthConfig.Perks do
		for _, cost in perk.Costs do
			total += cost
		end
	end
	return total
end

-- A save's unspent stars (whole, >= 0).
function RebirthConfig.starsOf(data: any): number
	local v = if type(data) == "table" then data.Stars else nil
	return if finite(v) and v > 0 then math.floor(v) else 0
end

-- The cost of buying the next level of `id` for this save, or nil + "BadPerk" | "Max" | "NoStars".
-- (Head Start is "Max" once the Robux levels already lift the start to MaxLevel - 1: it would add nothing.)
function RebirthConfig.quote(data: any, id: any): (number?, string?)
	if type(id) ~= "string" or not RebirthConfig.ById[id] then
		return nil, "BadPerk"
	end
	if id == "HeadStart" and RebirthConfig.startFor(data) >= BlasterData.MaxLevel - 1 then
		return nil, "Max"
	end
	local perks = if type(data) == "table" then data.StarPerks else nil
	local cost = RebirthConfig.nextCost(perks, id)
	if not cost then
		return nil, "Max"
	end
	if RebirthConfig.starsOf(data) < cost then
		return nil, "NoStars"
	end
	return cost, nil
end

-- Buys the next level of `id` (after quote said yes). Returns the new level.
function RebirthConfig.buy(data: { [string]: any }, id: string): number
	local cost = RebirthConfig.quote(data, id) :: number
	local perks = data.StarPerks
	if type(perks) ~= "table" then
		perks = {}
		data.StarPerks = perks
	end
	local level = RebirthConfig.levelOf(perks, id) + 1
	perks[id] = level
	data.Stars = RebirthConfig.starsOf(data) - cost
	if id == "PlotGlow" then
		-- a new colour shows at once (the COLOR button picks another)
		data.PlotGlow = RebirthConfig.GlowColors[level].Id
	end
	return level
end

-- The Bonuses stats of a save's perks (a partial StatConfig table).
function RebirthConfig.stats(perks: any): { [string]: number }
	local out: { [string]: number } = {}
	for _, perk in RebirthConfig.Perks do
		local level = RebirthConfig.levelOf(perks, perk.Id)
		if level > 0 and perk.Stats then
			for stat, value in perk.Stats do
				out[stat] = (out[stat] or 0) + value * level
			end
		end
	end
	return out
end

-- Is a Plot Glow colour unlocked for these perks? ("" = off: always)
function RebirthConfig.glowUnlocked(perks: any, colorId: any): boolean
	if colorId == "" then
		return true
	end
	local level = RebirthConfig.levelOf(perks, "PlotGlow")
	for i, color in RebirthConfig.GlowColors do
		if color.Id == colorId then
			return i <= level
		end
	end
	return false
end

-- The Plot Glow colour a save shows: its pick when unlocked, else "" (off).
function RebirthConfig.glowOf(data: any): string
	if type(data) ~= "table" or type(data.PlotGlow) ~= "string" then
		return ""
	end
	return if RebirthConfig.glowUnlocked(data.StarPerks, data.PlotGlow) then data.PlotGlow else ""
end

-- The next pick after `current`: "" (off), then every unlocked colour in order, then off again.
function RebirthConfig.nextGlow(perks: any, current: any): string
	local level = RebirthConfig.levelOf(perks, "PlotGlow")
	local index = 0
	for i, color in RebirthConfig.GlowColors do
		if color.Id == current then
			index = i
		end
	end
	if index + 1 <= level then
		return RebirthConfig.GlowColors[index + 1].Id
	end
	return ""
end

-- The blaster level a rebirth starts you with from Head Start alone.
function RebirthConfig.startLevel(perks: any): number
	local level = RebirthConfig.levelOf(perks, "HeadStart")
	return if level > 0 then RebirthConfig.HeadStartLevels[level] else 1
end

-- Blaster levels the save ever bought with Robux (Stats.BlastersPaid, whole, >= 0).
function RebirthConfig.paidOf(data: any): number
	local stats = if type(data) == "table" then data.Stats else nil
	local v = if type(stats) == "table" then stats.BlastersPaid else nil
	return if finite(v) and v > 0 then math.floor(v) else 0
end

-- The blaster level a rebirth starts this save with: Head Start's, plus one
-- per Robux level, up to MaxLevel - 1 (a level is left to forge).
function RebirthConfig.startFor(data: any): number
	local base = RebirthConfig.startLevel(if type(data) == "table" then data.StarPerks else nil)
	return math.max(base, math.min(base + RebirthConfig.paidOf(data), BlasterData.MaxLevel - 1))
end

---------------------------------------------------------------- the rebirth

-- A save's rebirth count (whole, >= 0).
function RebirthConfig.countOf(data: any): number
	local v = if type(data) == "table" then data.Rebirths else nil
	return if finite(v) and v > 0 then math.floor(v) else 0
end

-- The blaster level this run counts for the stars: the highest one forged at
-- the Foundry in it (Stats.RunForged, at most the level now); the first run
-- (no rebirth yet) counts the blaster level as it is.
function RebirthConfig.reachedOf(data: any): number
	if type(data) ~= "table" then
		return 0
	end
	local level = BlasterData.get(data.BlasterLevel).Level
	local stats = data.Stats
	local paid = type(stats) == "table" and stats.RunPaid == true
	if RebirthConfig.countOf(data) == 0 and not paid then
		return level
	end
	local run = if type(stats) == "table" then stats.RunForged else nil
	return if finite(run) and run > 0 then math.min(math.floor(run), level) else 0
end

-- Can this save rebirth now? (false + "NoData" | "Locked" (the blaster is
-- below MinBlaster) | "NotForged" (it is, but this run forged no such level))
function RebirthConfig.canRebirth(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "NoData"
	end
	local level = BlasterData.get(data.BlasterLevel).Level
	if level < RebirthConfig.MinBlaster then
		return false, "Locked"
	end
	-- (at the top level nothing is left to forge: a save that got there unforged (Vault
	-- cases before topBlocked existed) may rebirth for starsFor(reachedOf), 0 stars)
	if RebirthConfig.reachedOf(data) < RebirthConfig.MinBlaster and level < BlasterData.MaxLevel then
		return false, "NotForged"
	end
	return true, nil
end

-- Would buying the next blaster level (Vault coins, Robux) make the top level with no
-- rebirth level forged this run? Then nothing would be left to forge and the run could
-- never rebirth with stars: the Vault and the STORE leave that level to the Foundry.
function RebirthConfig.topBlockedFor(level: number, reached: number): boolean
	return level + 1 == BlasterData.MaxLevel and reached < RebirthConfig.MinBlaster
end

function RebirthConfig.topBlocked(data: any): boolean
	if type(data) ~= "table" then
		return false
	end
	return RebirthConfig.topBlockedFor(BlasterData.get(data.BlasterLevel).Level, RebirthConfig.reachedOf(data))
end

local function record(data: { [string]: any }, key: string): { [string]: any }
	local t = data[key]
	if type(t) ~= "table" then
		t = {}
		data[key] = t
	end
	return t
end

--[[
	The rebirth on the save (after canRebirth said yes), in one step: the
	resets and the stars of the header. Returns the stars it paid and the new
	rebirth count. Runtime state (items in the world, spawned machines, the
	train on its way) is RebirthService's job.
]]
function RebirthConfig.reset(data: { [string]: any }): (number, number)
	local level = BlasterData.get(data.BlasterLevel).Level
	local stars = RebirthConfig.starsFor(RebirthConfig.reachedOf(data))
	local perks = data.StarPerks
	local stats = record(data, "Stats")
	-- the highest level ever (BlasterData.priceLevel: prices never drop), a new run
	stats.BestBlaster = math.max(if finite(stats.BestBlaster) then math.floor(stats.BestBlaster) else 0, level)
	stats.RunForged = 0
	stats.RunPaid = false
	-- dusty relics are artifacts: they wait in the pen (RebirthService hands them to the keeper)
	local relics = {}
	local function keepRelics(list: any)
		if type(list) == "table" then
			for _, item in list do
				if type(item) == "table" and item.K == "Relic" and type(item.O) == "string" then
					table.insert(relics, { K = "Relic", O = item.O, G = item.G, R = item.R })
				end
			end
		end
	end
	keepRelics(data.Storage)
	if type(data.Train) == "table" then
		keepRelics(data.Train.Cargo)
		keepRelics(data.Train.TripCargo)
	end
	if type(data.PlacedMachines) == "table" then
		for _, entry in data.PlacedMachines do
			if type(entry) == "table" then
				keepRelics(entry.In)
				keepRelics(entry.Out)
			end
		end
	end
	-- money and the blaster (the floors and the enchant slots follow the blaster level)
	-- only Robux-bought coins that are still unspent stay (owner 2026-10-20)
	local paidCoins = data.PaidCoins
	local coins = data.Coins
	local keep = if type(paidCoins) == "number" and paidCoins == paidCoins and paidCoins > 0 then paidCoins else 0
	if type(coins) == "number" and coins == coins then
		keep = math.min(keep, math.max(coins, 0))
	else
		keep = 0
	end
	data.Coins = keep
	data.PaidCoins = keep
	data.ShardRolls = 0
	-- the Robux blaster levels come back: they lift the new blaster (no stars for them)
	local start = RebirthConfig.startFor(data)
	if start > RebirthConfig.startLevel(perks) then
		stats.RunPaid = true
	end
	data.BlasterLevel = start
	data.BlasterOre = if start > 1 then BlasterData.vaultOre(start) else ""
	-- machine speed, the elevator, the train, the backpack
	local upgrades = record(data, "Upgrades")
	upgrades.Bellows = 0
	upgrades.Elevator = false
	data.MachineUpgrades = {}
	local train = record(data, "Train")
	train.CapacityLevel = 0
	train.SpeedLevel = 0
	train.Cargo = {}
	train.TripCargo = {}
	train.TripDepartAt = 0
	train.TripArriveAt = 0
	record(data, "Gear").Backpack = 0
	-- every ore you own (the factory itself stays where it stands)
	data.Storage = relics
	record(data, "Foundry").Stock = {}
	if RebirthConfig.levelOf(perks, "PodiumKeeper") < 1 and type(data.Podiums) == "table" then
		for i, key in data.Podiums do
			if type(key) == "string" then
				data.Podiums[i] = ""
			end
		end
	end
	if type(data.PlacedMachines) == "table" then
		for _, entry in data.PlacedMachines do
			if type(entry) == "table" then
				entry.In = nil
				entry.Out = nil
			end
		end
		-- the droppers and Money Lasers come down, like the podiums' ore (owner
		-- decision pending: keep or lose droppers); not back to the Build menu,
		-- placing them again would keep their income
		local list = data.PlacedMachines
		for i = #list, 1, -1 do
			local entry = list[i]
			local id = if type(entry) == "table" then entry.Id else nil
			if type(id) == "string" and (DropperConfig.ById[id] or id == DropperConfig.Laser.Id) then
				table.remove(list, i)
			end
		end
	end
	-- ...and the ones packed into the Build menu before the rebirth go too (no zero keys)
	local inventory = data.MachineInventory
	if type(inventory) == "table" then
		for id in DropperConfig.ById do
			inventory[id] = nil
		end
		inventory[DropperConfig.Laser.Id] = nil
	end
	-- the enchants stay slotted: the paid ones first, into the slots the new level opens
	local enchants = data.Enchants
	if type(enchants) == "table" and type(enchants.Slots) == "table" then
		local slots = enchants.Slots
		local passes = if type(enchants.Passes) == "table" then enchants.Passes else {}
		local ordered = {}
		for _, paid in { true, false } do
			for i = 1, EnchantConfig.MaxSlots do
				local id = slots[i]
				if type(id) == "string" and id ~= "" and (passes[id] == true) == paid then
					table.insert(ordered, id)
				end
			end
		end
		for i = 1, EnchantConfig.MaxSlots do
			slots[i] = ordered[i] or ""
		end
	end
	-- the reward
	data.Stars = RebirthConfig.starsOf(data) + stars
	local count = RebirthConfig.countOf(data) + 1
	data.Rebirths = count
	stats.StarsEarned = (if finite(stats.StarsEarned) and stats.StarsEarned > 0 then math.floor(stats.StarsEarned) else 0) + stars
	return stars, count
end

return RebirthConfig
