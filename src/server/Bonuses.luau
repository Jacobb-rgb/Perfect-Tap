--[[
	Bonuses (steps 6-7): one place the services ask for a player's bonuses.
	Wired in P0: MiningService (damage, Overcharge, reach, ore luck, twin
	drops, artifact chance), SellService (sell value: every sale x sellMult),
	CarryService (walk speed, carry capacity, pickup range, throw power; the
	ONLY source of carry capacity, StateService shows the same number) and
	EconomyService (podium income). Left to their packages: the gear package
	(the Ore Magnet pull and the head lamp, from magnetRadius / lamp and
	State.Bonuses), the capsule package (Triple Lucky, tripleLucky).

	- Providers: functions (player, data, now) -> a partial stat table
	  (StatConfig names). stats(player) sums every registered provider with
	  StatConfig.combine (Add stats summed, Mult stats multiplied, each total
	  capped at its Max). A provider that errors or returns junk counts as
	  nothing (warned once).
	- The seven built-in providers read the save (pure config functions):
	    "Backpack"    CarryCapacity = the equipped pack's BackpackData.capacity
	                  (data.Backpacks.Equipped; owner 2026-10-24: the backpack)
	    "Gear"        GearConfig.stats(data.Gear)
	    "Enchants"    EnchantConfig.stats(data.Enchants, data.BlasterLevel)
	    "Golems"      GolemConfig.stats(data.Golems, Golem Bond from enchants + collections)
	    "Boosts"      BoostConfig.stats(data.Boosts, now)
	    "Collections" ArtifactConfig.stats(data.Artifacts)
	    "Rebirth"     RebirthConfig.stats(data.StarPerks) (the Star Shop perks)
	  register(name, provider) replaces a provider of the same name (so a
	  package can never count one source twice) or adds a new source (passes,
	  rebirth, events). Packages ONLY call register: they never add income
	  bonuses to EconomyService themselves.
	- Podium income: this module adds ONE EconomyService income bonus, keyed
	  "Bonuses", that returns the capped IncomePct total of every provider
	  (incomePct). So golems, enchants, collections and any later provider
	  reach the podiums exactly once.
	- The 2x Money pass (perk MonetizationConfig.MoneyPassPerk): a separate
	  multiplier OUTSIDE the StatConfig caps (IncomePct 2, SellPct 3), so it
	  always doubles: moneyMult(player) is added to EconomyService as the
	  income factor "MoneyPass", and compute(..., player) puts it in the
	  totals as MoneyMult, which sellMult multiplies in. A perk change goes
	  through DataService.changed (MonetizationService.applyPass), which
	  drops the cache.
	- Cache: stats(player) is kept per player until the save changes
	  (DataService.onChangedNow -> invalidate, inside changed() itself, so a
	  read right after a change never gets the old totals), the next running
	  boost runs out, or MaxCacheSeconds pass, whichever comes first;
	  register / unregister clear every cache. A provider that depends on something outside the
	  save (a game pass bought mid-session, an event) calls invalidate(player)
	  when that changes. The returned table is shared: read it, never write it.
	- The getters below turn totals into the numbers the services use.
	  summary(player) is the same as a flat table for the State snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local BoostConfig = require(Shared.Config.BoostConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local BackpackData = require(Shared.Config.BackpackData)
local GearConfig = require(Shared.Config.GearConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local StatConfig = require(Shared.Config.StatConfig)
local Perks = require(script.Parent.Perks)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)

local Bonuses = {}

export type Stats = { [string]: number }
export type Provider = (player: Player?, data: { [string]: any }, now: number) -> ...any

type Entry = { Name: string, Provider: Provider }
type Cached = { Stats: Stats, At: number, ValidUntil: number }

Bonuses.MaxCacheSeconds = 30
Bonuses.IncomeKey = "Bonuses" -- the EconomyService.addIncomeBonus key
Bonuses.MoneyKey = "MoneyPass" -- the EconomyService.addIncomeFactor key (2x Money)

local providers: { Entry } = {}
local warned: { [string]: boolean } = {}
-- weak keys: a player who left is forgotten with their Player object
local cache: { [any]: Cached } = setmetatable({}, { __mode = "k" }) :: any

-- Swappable for the Lune tests.
local clock: () -> number = os.time

-- Forgets a player's cached totals (the next stats() call recomputes them).
function Bonuses.invalidate(player: Player)
	cache[player] = nil
end

local function invalidateAll()
	table.clear(cache)
end

-- Adds a bonus source, or replaces the one with the same name.
function Bonuses.register(name: string, provider: Provider)
	invalidateAll()
	for _, entry in providers do
		if entry.Name == name then
			entry.Provider = provider
			return
		end
	end
	table.insert(providers, { Name = name, Provider = provider })
end

-- Removes a bonus source (tests, a feature switched off).
function Bonuses.unregister(name: string)
	invalidateAll()
	for i, entry in providers do
		if entry.Name == name then
			table.remove(providers, i)
			return
		end
	end
end

-- Golem Bond from the enchants and the completed collections.
local function bondOf(data: { [string]: any }): number
	local enchants = EnchantConfig.stats(data.Enchants, data.BlasterLevel)
	local collections = ArtifactConfig.stats(data.Artifacts)
	return (enchants.GolemBondPct or 0) + (collections.GolemBondPct or 0)
end

local BUILT_IN: { { Name: string, Provider: Provider } } = {
	{
		Name = "Backpack",
		Provider = function(_player, data, _now)
			local packs = data.Backpacks
			return { CarryCapacity = BackpackData.capacity(if type(packs) == "table" then packs.Equipped else nil) }
		end,
	},
	{
		Name = "Gear",
		Provider = function(_player, data, _now)
			return GearConfig.stats(data.Gear)
		end,
	},
	{
		Name = "Enchants",
		Provider = function(_player, data, _now)
			return EnchantConfig.stats(data.Enchants, data.BlasterLevel)
		end,
	},
	{
		Name = "Golems",
		Provider = function(_player, data, _now)
			return GolemConfig.stats(data.Golems, bondOf(data))
		end,
	},
	{
		Name = "Boosts",
		Provider = function(_player, data, now)
			return BoostConfig.stats(data.Boosts, now)
		end,
	},
	{
		Name = "Collections",
		Provider = function(_player, data, _now)
			return ArtifactConfig.stats(data.Artifacts)
		end,
	},
	{
		Name = "Rebirth",
		Provider = function(_player, data, _now)
			return RebirthConfig.stats(data.StarPerks)
		end,
	},
}

-- Puts the seven built-in providers back (and drops every other one).
function Bonuses.resetProviders()
	table.clear(providers)
	table.clear(warned)
	invalidateAll()
	for _, entry in BUILT_IN do
		Bonuses.register(entry.Name, entry.Provider)
	end
end
Bonuses.resetProviders()

-- One provider's partial stats (nil when it fails or returns junk).
local function run(entry: Entry, player: Player?, data: { [string]: any }, now: number): any
	local ok, result = pcall(entry.Provider, player, data, now)
	if ok and (result == nil or type(result) == "table") then
		return result
	end
	if not warned[entry.Name] then
		warned[entry.Name] = true
		warn(`[Bonuses] provider {entry.Name} failed: {if ok then "not a table" else tostring(result)}`)
	end
	return nil
end

-- Totals of every provider for a save (pure, never cached: the tests and
-- the cards). `data` may be nil (not loaded): the providers see an empty save.
function Bonuses.compute(data: { [string]: any }?, now: number, player: Player?): Stats
	local save = data or {}
	local partials = {}
	for _, entry in providers do
		local partial = run(entry, player, save, now)
		if partial then
			table.insert(partials, partial)
		end
	end
	local totals = StatConfig.combine(partials)
	-- (outside the caps: the 2x Money pass doubles the capped totals)
	totals.MoneyMult = Bonuses.moneyMult(player)
	return totals
end

-- The 2x Money pass multiplier of a player: MonetizationConfig.MoneyPassMult
-- with the pass's perk, else 1 (no player: 1).
function Bonuses.moneyMult(player: Player?): number
	if not player then
		return 1
	end
	-- (pcall: a stand-in player without attributes counts as no pass)
	local ok, has = pcall(Perks.has, player, MonetizationConfig.MoneyPassPerk)
	return if ok and has then MonetizationConfig.MoneyPassMult else 1
end

-- The partial stats of one source for a player (nil when the source isn't
-- registered). Not cached: for breakdowns on the bonus screen.
function Bonuses.source(player: Player, name: string): Stats?
	for _, entry in providers do
		if entry.Name == name then
			local data = DataService.get(player) or {}
			return StatConfig.combine({ run(entry, player, data, clock()) })
		end
	end
	return nil
end

-- Totals for a player (their save as it is now; cached, see the header).
function Bonuses.stats(player: Player): Stats
	local now = clock()
	local hit = cache[player]
	if hit and now >= hit.At and now < hit.ValidUntil then
		return hit.Stats
	end
	local data = DataService.get(player)
	local stats = Bonuses.compute(data, now, player)
	if data then
		local validUntil = now + Bonuses.MaxCacheSeconds
		local expiry = BoostConfig.nextExpiry(data.Boosts, now)
		if expiry and expiry < validUntil then
			validUntil = expiry
		end
		cache[player] = { Stats = stats, At = now, ValidUntil = validUntil }
	else
		cache[player] = nil
	end
	return stats
end

-- The player's capped podium income bonus share (0.1 = +10 %): the one
-- EconomyService income bonus this module adds (see the header).
function Bonuses.incomePct(player: Player): number
	return math.max(0, Bonuses.stats(player).IncomePct or 0)
end

-- Adds incomePct and the 2x Money factor to EconomyService once (keyed:
-- calling it again replaces them).
function Bonuses.attachIncome()
	EconomyService.addIncomeBonus(Bonuses.incomePct, Bonuses.IncomeKey)
	EconomyService.addIncomeFactor(Bonuses.moneyMult, Bonuses.MoneyKey)
end

---------------------------------------------------------------- getters (from totals)

-- Blaster damage multiplier; `lastStage` = the rock is in its last third (Overcharge).
function Bonuses.damageMult(stats: Stats, lastStage: boolean): number
	local mult = 1 + math.max(0, stats.DamagePct or 0)
	if lastStage then
		mult *= 1 + math.max(0, stats.OverchargePct or 0)
	end
	return mult
end

-- Extra blaster range (studs).
function Bonuses.reach(stats: Stats): number
	return math.max(0, stats.ReachStuds or 0)
end

-- The ore luck (1 = no luck, at most StatConfig.MaxOreLuck); each rarity's
-- weight multiplier is BoostConfig.rarityMult(rarity, oreLuck).
function Bonuses.oreLuck(stats: Stats): number
	return StatConfig.oreLuck(stats.OreLuckPct, stats.OreLuckMult)
end

-- Is Triple Lucky on (golem capsules)?
function Bonuses.tripleLucky(stats: Stats): boolean
	return (stats.CapsuleLuckMult or 1) > 1
end

-- Chance that a dropped ore drops a twin (0..0.5).
function Bonuses.twinDrop(stats: Stats): number
	return math.clamp(stats.TwinDropChance or 0, 0, 0.5)
end

-- Chance that breaking a rock in `zoneId` turns up an artifact.
function Bonuses.artifactChance(stats: Stats, zoneId: string): number
	return math.clamp(ArtifactConfig.rockChance(zoneId) * (1 + math.max(0, stats.ArtifactPct or 0)), 0, 1)
end

-- What Tobin pays is multiplied by this (the capped SellPct, then the 2x
-- Money pass on top).
function Bonuses.sellMult(stats: Stats): number
	local money = stats.MoneyMult
	local pass = if type(money) == "number" and money >= 1 and money <= MonetizationConfig.MoneyPassMult then money else 1
	return (1 + math.max(0, stats.SellPct or 0)) * pass
end

-- Coins Tobin pays for items whose base price adds up to `base`: base x
-- sellMult, rounded to whole coins (SellService pays this; the Sell view
-- shows math.floor(base x State.Bonuses.SellMult + 0.5)).
function Bonuses.sellAmount(stats: Stats, base: number): number
	if type(base) ~= "number" or base ~= base or base <= 0 then
		return 0
	end
	return math.floor(base * Bonuses.sellMult(stats) + 0.5)
end

-- Walk speed in studs/s with nothing carried (Boots base and Swift, times the
-- WalkSpeed golems).
function Bonuses.walkSpeed(stats: Stats): number
	local base = stats.WalkSpeed or 0
	if base <= 0 then
		base = GearConfig.value("Boots", 0)
	end
	return math.clamp(base * (1 + math.max(0, stats.WalkSpeedPct or 0)), 8, 50)
end

-- Walk speed while carrying `count` items (GearConfig: the slowdown is
-- capped, so a big backpack never cancels the boots). CarryService uses it.
function Bonuses.carryWalkSpeed(stats: Stats, count: number): number
	local items = if type(count) == "number" and count > 0 then count else 0
	local slow = math.min(items * GearConfig.CarrySlowPerItem, GearConfig.CarrySlowMax)
	return math.max(GearConfig.MinWalkSpeed, Bonuses.walkSpeed(stats) - slow)
end

-- Studs in which your own loose items fly to you (0 = no magnet). The
-- Magnetism enchant's MagnetBonus only adds to a real Ore Magnet (gear).
function Bonuses.magnetRadius(stats: Stats): number
	local base = math.max(0, stats.MagnetRadius or 0)
	if base <= 0 then
		return 0
	end
	local max = StatConfig.ById.MagnetRadius.Max or math.huge
	return math.min(max, base + math.max(0, stats.MagnetBonus or 0))
end

-- Studs you can grab an item from.
function Bonuses.pickupRange(stats: Stats): number
	return math.max(GearConfig.value("Gloves", 0), stats.PickupRange or 0)
end

-- Throw power multiplier.
function Bonuses.throwMult(stats: Stats): number
	return math.max(1, stats.ThrowMult or 1)
end

-- Items you can carry (the StrongBack perk doubles it).
function Bonuses.carryCapacity(stats: Stats, player: Player?): number
	local base = math.max(1, math.floor(stats.CarryCapacity or 1))
	return base * (if player and Perks.has(player, "StrongBack") then 2 else 1)
end

-- Head lamp range and brightness (0, 0 = no lamp).
function Bonuses.lamp(stats: Stats): (number, number)
	return math.max(0, stats.LampRange or 0), math.max(0, stats.LampBrightness or 0)
end

-- The ore a dropped chunk really is: ore luck only ever upgrades the rock's
-- own `rolled` ore (BoostConfig.upgradeOre: an ore whose share grows stays,
-- one whose share drops may become a rarer ore of `weights`, exactly
-- matching BoostConfig.oreOdds with this luck). Without luck `random` is
-- not called.
function Bonuses.rollOre(stats: Stats, weights: { [string]: number }, rolled: string, random: () -> number): string
	local luck = Bonuses.oreLuck(stats)
	if luck <= 1 then
		return rolled
	end
	return BoostConfig.upgradeOre(weights, luck, rolled, random)
end

-- The flat table the State snapshot sends (State.Bonuses): the numbers the
-- client shows and uses (lamp, magnet ring, walk speed, luck on boost cards).
-- Every value is the capped total the server applies.
function Bonuses.summary(player: Player): { [string]: any }
	local stats = Bonuses.stats(player)
	local lampRange, lampBrightness = Bonuses.lamp(stats)
	local luckPct = math.max(0, stats.OreLuckPct or 0)
	local _, luckWithHexa = BoostConfig.hexaLuck(luckPct)
	return {
		DamageMult = Bonuses.damageMult(stats, false),
		OverchargeMult = 1 + math.max(0, stats.OverchargePct or 0),
		Reach = Bonuses.reach(stats),
		OreLuck = Bonuses.oreLuck(stats),
		OreLuckPct = luckPct, -- the Lucky enchant + Luck golems part (capped)
		OreLuckMult = math.max(1, stats.OreLuckMult or 1), -- Hexa Lucky's part (capped)
		OreLuckWithHexa = luckWithHexa, -- what OreLuck becomes with Hexa Lucky (boost cards)
		TripleLucky = Bonuses.tripleLucky(stats),
		HexaLucky = (stats.OreLuckMult or 1) > 1,
		TwinDrop = Bonuses.twinDrop(stats),
		ArtifactMult = 1 + math.max(0, stats.ArtifactPct or 0),
		ArtifactPct = math.max(0, stats.ArtifactPct or 0), -- luck cards: BoostConfig.preview context
		SellMult = Bonuses.sellMult(stats),
		IncomePct = math.max(0, stats.IncomePct or 0),
		MoneyMult = stats.MoneyMult or 1, -- the 2x Money pass (income and sales)
		GolemBond = math.max(0, stats.GolemBondPct or 0),
		WalkSpeed = Bonuses.walkSpeed(stats),
		MagnetRadius = Bonuses.magnetRadius(stats),
		PickupRange = Bonuses.pickupRange(stats),
		ThrowMult = Bonuses.throwMult(stats),
		CarryCapacity = Bonuses.carryCapacity(stats, player),
		LampRange = lampRange,
		LampBrightness = lampBrightness,
	}
end

-- A save change may change any bonus: drop the cached totals at once (not at
-- the deferred onChanged flush: a read in the same frame must see the change).
DataService.onChangedNow(function(player: Player)
	Bonuses.invalidate(player)
end)
Bonuses.attachIncome()

-- Internals for the Lune tests only.
Bonuses._test = {
	setClock = function(fn: () -> number)
		clock = fn
		invalidateAll()
	end,
	reset = function()
		clock = os.time
		Bonuses.resetProviders()
	end,
	cached = function(player: any): boolean
		return cache[player] ~= nil
	end,
	names = function(): { string }
		local list = {}
		for _, entry in providers do
			table.insert(list, entry.Name)
		end
		return list
	end,
}

return Bonuses
