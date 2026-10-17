--[[
	Bonuses (steps 6-7): one place the services ask for a player's bonuses
	(MiningService: damage, reach, ore luck, twin drops, artifact chance;
	SellService: sell value; CarryService: walk speed and carry capacity; the
	gear package: magnet, pickup range, throw power, head lamp; capsules:
	Triple Lucky; EconomyService: podium income).

	- Providers: functions (player, data, now) -> a partial stat table
	  (StatConfig names). stats(player) sums every registered provider with
	  StatConfig.combine (Add stats summed, Mult stats multiplied, each total
	  capped at its Max). A provider that errors or returns junk counts as
	  nothing (warned once).
	- The five built-in providers read the save (pure config functions):
	    "Gear"        GearConfig.stats(data.Gear)
	    "Enchants"    EnchantConfig.stats(data.Enchants, data.BlasterLevel)
	    "Golems"      GolemConfig.stats(data.Golems, Golem Bond from enchants + collections)
	    "Boosts"      BoostConfig.stats(data.Boosts, now)
	    "Collections" ArtifactConfig.stats(data.Artifacts)
	  register(name, provider) replaces a provider of the same name (so a
	  package can never count one source twice) or adds a new source (passes,
	  rebirth, events). Packages ONLY call register: they never add income
	  bonuses to EconomyService themselves.
	- Podium income: this module adds ONE EconomyService income bonus, keyed
	  "Bonuses", that returns the capped IncomePct total of every provider
	  (incomePct). So golems, enchants, collections and any later provider
	  reach the podiums exactly once.
	- Cache: stats(player) is kept per player until the save changes
	  (DataService.onChanged -> invalidate), the next running boost runs out,
	  or MaxCacheSeconds pass, whichever comes first; register / unregister
	  clear every cache. A provider that depends on something outside the
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
local GearConfig = require(Shared.Config.GearConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
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
}

-- Puts the five built-in providers back (and drops every other one).
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
	return StatConfig.combine(partials)
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

-- Adds incomePct to EconomyService once (keyed: calling it again replaces it).
function Bonuses.attachIncome()
	EconomyService.addIncomeBonus(Bonuses.incomePct, Bonuses.IncomeKey)
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

-- The multiplier on Rare and rarer ore weights (1 = no luck, at most
-- StatConfig.MaxOreLuck).
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

-- What Tobin pays is multiplied by this.
function Bonuses.sellMult(stats: Stats): number
	return 1 + math.max(0, stats.SellPct or 0)
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

-- Studs in which your own loose items fly to you (0 = no magnet).
function Bonuses.magnetRadius(stats: Stats): number
	return math.max(0, stats.MagnetRadius or 0)
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
-- own `rolled` ore (BoostConfig.upgradeOre: a Rare+ ore stays, a lower one
-- may become a Rare+ ore of `weights`, exactly matching BoostConfig.oreOdds
-- with this luck). Without luck `random` is not called.
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
		OreLuckWithHexa = luckWithHexa, -- what OreLuck becomes with Hexa Lucky (boost cards)
		TripleLucky = Bonuses.tripleLucky(stats),
		HexaLucky = (stats.OreLuckMult or 1) > 1,
		TwinDrop = Bonuses.twinDrop(stats),
		ArtifactMult = 1 + math.max(0, stats.ArtifactPct or 0),
		SellMult = Bonuses.sellMult(stats),
		IncomePct = math.max(0, stats.IncomePct or 0),
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

-- A save change may change any bonus: drop the cached totals.
DataService.onChanged(function(player: Player)
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
