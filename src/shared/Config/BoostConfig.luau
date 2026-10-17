--[[
	Luck boosts (step 6, the side menu "Boosts"). Two kinds, each a timer
	saved as an os.time() second in data.Boosts (it runs in real time, also
	while you are offline; compare with workspace:GetServerTimeNow() on the
	client):

	  TripleLucky  (data.Boosts.TripleLuckyUntil) golem capsules: every golem
	               at least as rare as the capsule's LuckyFrom (Stone: Rare+,
	               Crystal: Epic+, Royal: Legendary+) is exactly 3 times as
	               likely; the other golems share the rest (CapsuleConfig.odds).
	  HexaLucky    (data.Boosts.HexaLuckyUntil) mining: the weight of each Rare
	               or rarer ore in a rock's ore roll is multiplied by 2.5, then
	               the chances are recomputed so they add up to 100 % (oreOdds).
	               It stacks with the Lucky enchant and Luck golems: the total
	               luck is StatConfig.oreLuck = (1 + their +%) x 2.5, at most x5.
	               OWNER: the name came from the brief; "Hexa" sounds like x6
	               while the effect is x2.5 - rename it or change Mult.

	How luck works in a rock (upgradeOre, exact): a rock's ores are rolled
	from the zone's plain weights when it grows, and the rock shows them
	(glints, health). When a chunk drops, luck only ever UPGRADES it: a Rare+
	ore stays what it is; a lower ore turns into a Rare+ ore of that zone with
	chance 1 - T/T' (T = the zone's total weight, T' = the total with luck),
	picked in proportion to the zone weights. Every chunk then has exactly
	the chances oreOdds(zone weights, luck) shows on the boost card.
	A zone without Rare+ ores (Outcrops) gets nothing from ore luck: the
	boost card shows each zone's before/after Rare+ chance (zoneEffects) and
	"No effect here" for those; a coin buy is refused ("NoEffect") when no
	zone the player can mine has a Rare+ ore (hasEffect).

	Where they come from: small coin versions (5 min, CoinOffers, BoostAction
	"BuyCoins" { Id }), Robux packs (15 min / 1 h, RobuxOffers, BoostAction
	"BuyRobux" { Id } -> PurchasePrompt) and the daily wheel (10 min).
	Coin prices: BasePrice x CapsuleConfig.levelScale(blaster level), so they
	grow with the game like the capsules (Triple Lucky 5 min = 10 Stone
	capsules at every level). They never read the income (it can be gamed by
	emptying the podiums before buying).
	Stacking: every new boost of the same kind adds its time to what is left;
	at most MaxStackSeconds (2 h) may be left after a coin buy or a wheel
	prize (a coin buy that would pass it is refused, "Full"; the wheel caps).
	A Robux pack is only offered while it fits; a receipt that arrives late
	still adds its full time (paid time is never lost); saves are capped at
	MaxSavedSeconds.

	Roblox rules: paid boosts that change the odds of random results must show
	the NEW odds in numbers before purchase: the boost card shows zoneOdds()
	per zone (zoneEffects for the summary) / CapsuleConfig.odds(id, true).
	Robux packs are paid random items; coin offers are too only while coins
	can be bought with Robux (isPaidRandom, MonetizationConfig.coinsBuyable).
	Paid random items are hidden where PolicyService
	ArePaidRandomItemsRestricted is true.
]]

local OreData = require(script.Parent.OreData)
local Rarity = require(script.Parent.Rarity)
local WorldLayout = require(script.Parent.WorldLayout)
local CapsuleConfig = require(script.Parent.CapsuleConfig)
local MonetizationConfig = require(script.Parent.MonetizationConfig)
local StatConfig = require(script.Parent.StatConfig)

export type Kind = {
	Id: string,
	Name: string,
	Field: string, -- the data.Boosts key (an os.time() second, 0 = never)
	Target: "Capsules" | "Mining",
	Mult: number, -- the luck multiplier while active
	MinRarity: string?, -- mining: the rarest ores it boosts start here
	Stat: string, -- StatConfig stat it sets while active
	Description: string,
	Color: Color3,
}

export type Offer = {
	Id: string,
	Boost: string, -- Kind id
	Seconds: number,
	BasePrice: number?, -- coin offers: coins at blaster levels 1-3 (x CapsuleConfig.levelScale)
	Product: string?, -- Robux offers: MonetizationConfig key
}

export type OddsLine = { Ore: string, Chance: number }
export type ZoneEffect = {
	Zone: string,
	Before: number, -- chance that a chunk is Rare or rarer now
	After: number, -- the same with the boost
	NoEffect: boolean, -- the zone has no Rare+ ore
}

local BoostConfig = {}

BoostConfig.MaxStackSeconds = 2 * 3600
BoostConfig.MaxSavedSeconds = 24 * 3600

-- BoostAction / ActionResult reason codes -> text for the player
BoostConfig.Reasons = {
	BadOffer = "That boost isn't sold here",
	Full = "That boost already has 2 hours left",
	NoCoins = "Not enough coins",
	NoEffect = "No effect yet: none of your mines has Rare ores",
	Restricted = "Boosts aren't available where you play",
	Robux = "Robux purchase", -- the server answers with PurchasePrompt instead
} :: { [string]: string }

BoostConfig.Kinds = {
	TripleLucky = {
		Id = "TripleLucky",
		Name = "Triple Lucky",
		Field = "TripleLuckyUntil",
		Target = "Capsules",
		Mult = 3,
		Stat = "CapsuleLuckMult",
		Description = "Golem capsules: the rarest golems in every capsule are 3x as likely.",
		Color = Color3.fromRGB(90, 220, 120),
	},
	HexaLucky = {
		Id = "HexaLucky",
		Name = "Hexa Lucky",
		Field = "HexaLuckyUntil",
		Target = "Mining",
		Mult = 2.5,
		MinRarity = "Rare",
		Stat = "OreLuckMult",
		Description = "Mining: Rare and rarer ores weigh 2.5x as much in every rock you break.",
		Color = Color3.fromRGB(255, 196, 60),
	},
} :: { [string]: Kind }
BoostConfig.KindIds = { "TripleLucky", "HexaLucky" }

-- rarity order from which ore luck applies (Hexa Lucky's MinRarity: Rare; the
-- Lucky enchant and Luck golems boost the same ores)
BoostConfig.OreLuckFrom = Rarity.ById[BoostConfig.Kinds.HexaLucky.MinRarity or "Rare"].Order

BoostConfig.CoinOffers = {
	-- 10 Stone capsules' worth at every blaster level
	{ Id = "TripleLucky5", Boost = "TripleLucky", Seconds = 300, BasePrice = 25000 },
	{ Id = "HexaLucky5", Boost = "HexaLucky", Seconds = 300, BasePrice = 5000 },
} :: { Offer }

BoostConfig.RobuxOffers = {
	{ Id = "TripleLucky15", Boost = "TripleLucky", Seconds = 900, Product = "TripleLucky15" },
	{ Id = "TripleLucky60", Boost = "TripleLucky", Seconds = 3600, Product = "TripleLucky60" },
	{ Id = "HexaLucky15", Boost = "HexaLucky", Seconds = 900, Product = "HexaLucky15" },
	{ Id = "HexaLucky60", Boost = "HexaLucky", Seconds = 3600, Product = "HexaLucky60" },
} :: { Offer }

BoostConfig.OfferById = {} :: { [string]: Offer }
for _, list in { BoostConfig.CoinOffers, BoostConfig.RobuxOffers } do
	for _, offer in list do
		BoostConfig.OfferById[offer.Id] = offer
		assert(BoostConfig.Kinds[offer.Boost], "BoostConfig: unknown boost " .. offer.Boost)
		local product = offer.Product
		if product then
			local info = MonetizationConfig.Products[product]
			assert(info and info.Boost == offer.Boost and info.Seconds == offer.Seconds, "BoostConfig: product mismatch " .. product)
		end
	end
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The saved until-time of a kind in a data.Boosts record (broken = 0).
function BoostConfig.untilOf(boosts: any, kindId: string): number
	local kind = BoostConfig.Kinds[kindId]
	local v = if kind and type(boosts) == "table" then boosts[kind.Field] else nil
	return if finite(v) and v > 0 then v else 0
end

-- Seconds left of a boost at `now` (0 when off).
function BoostConfig.remaining(boosts: any, kindId: string, now: number): number
	return math.max(0, BoostConfig.untilOf(boosts, kindId) - now)
end

function BoostConfig.active(boosts: any, kindId: string, now: number): boolean
	return BoostConfig.remaining(boosts, kindId, now) > 0
end

-- The next moment after `now` a running boost runs out (nil when none runs).
function BoostConfig.nextExpiry(boosts: any, now: number): number?
	local soonest: number? = nil
	for _, kindId in BoostConfig.KindIds do
		local untilTime = BoostConfig.untilOf(boosts, kindId)
		if untilTime > now and (soonest == nil or untilTime < soonest) then
			soonest = untilTime
		end
	end
	return soonest
end

-- Can `seconds` more be added without passing MaxStackSeconds?
function BoostConfig.canExtend(boosts: any, kindId: string, seconds: number, now: number): boolean
	return BoostConfig.Kinds[kindId] ~= nil and BoostConfig.remaining(boosts, kindId, now) + seconds <= BoostConfig.MaxStackSeconds
end

-- Adds `seconds` to a boost (from now, or from its end when it is running)
-- and writes the record. `capped`: never past MaxStackSeconds from now (coin
-- buys check canExtend first; the wheel just caps); a Robux receipt passes
-- false (paid time is never lost). Returns the new until-time (0 for an
-- unknown kind).
function BoostConfig.extend(boosts: { [string]: any }, kindId: string, seconds: number, now: number, capped: boolean): number
	local kind = BoostConfig.Kinds[kindId]
	if not kind or not finite(seconds) or seconds <= 0 then
		return BoostConfig.untilOf(boosts, kindId)
	end
	local start = math.max(now, BoostConfig.untilOf(boosts, kindId))
	local untilTime = start + seconds
	if capped then
		untilTime = math.min(untilTime, now + BoostConfig.MaxStackSeconds)
	end
	untilTime = math.max(BoostConfig.untilOf(boosts, kindId), untilTime)
	boosts[kind.Field] = math.floor(untilTime)
	return boosts[kind.Field]
end

-- Coins a coin offer costs at this blaster level (nil for other offers).
function BoostConfig.coinPrice(offerId: any, blasterLevel: any): number?
	local offer = if type(offerId) == "string" then BoostConfig.OfferById[offerId] else nil
	local base = if offer then offer.BasePrice else nil
	if base == nil then
		return nil
	end
	return base * CapsuleConfig.levelScale(blasterLevel)
end

-- Is buying this offer a paid random item? Robux packs always; coin offers
-- only while coins can be bought with Robux. Unknown offer: true (strict).
function BoostConfig.isPaidRandom(offerId: any): boolean
	local offer = if type(offerId) == "string" then BoostConfig.OfferById[offerId] else nil
	if not offer or offer.Product ~= nil then
		return true
	end
	return MonetizationConfig.coinsBuyable()
end

-- What the running boosts give (Bonuses stats).
function BoostConfig.stats(boosts: any, now: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, kindId in BoostConfig.KindIds do
		if BoostConfig.active(boosts, kindId, now) then
			local kind = BoostConfig.Kinds[kindId]
			out[kind.Stat] = kind.Mult
		end
	end
	return out
end

---------------------------------------------------------------- ore odds

-- Does ore luck boost this ore (Rare or rarer)?
function BoostConfig.isLuckyOre(oreId: string): boolean
	local ore = OreData.ById[oreId]
	local info = if ore then Rarity.ById[ore.Rarity] else nil
	return info ~= nil and info.Order >= BoostConfig.OreLuckFrom
end

-- The ore luck with and without Hexa Lucky for a player whose other luck is
-- `oreLuckPct` (Lucky enchant + Luck golems, capped): what a Hexa Lucky card
-- compares. Both are StatConfig.oreLuck (at most StatConfig.MaxOreLuck).
function BoostConfig.hexaLuck(oreLuckPct: number): (number, number)
	local hexa = BoostConfig.Kinds.HexaLucky.Mult
	return StatConfig.oreLuck(oreLuckPct, 1), StatConfig.oreLuck(oreLuckPct, hexa)
end

-- Ore weights with luck: every Rare or rarer ore's weight x `luck`
-- (luck <= 1 or not finite: the weights unchanged). Unknown ores and
-- weights that aren't > 0 are left out.
function BoostConfig.oreWeights(weights: { [string]: number }, luck: number): { [string]: number }
	local mult = if finite(luck) and luck > 1 then luck else 1
	local out: { [string]: number } = {}
	for oreId, weight in weights do
		if OreData.ById[oreId] and finite(weight) and weight > 0 then
			out[oreId] = if BoostConfig.isLuckyOre(oreId) then weight * mult else weight
		end
	end
	return out
end

-- Exact chance of each ore in one ore roll with these weights and luck,
-- in OreData order (rarer last). Sums to 1 (empty for no weights).
function BoostConfig.oreOdds(weights: { [string]: number }, luck: number): { OddsLine }
	local boosted = BoostConfig.oreWeights(weights, luck)
	local total = 0
	for _, weight in boosted do
		total += weight
	end
	local list: { OddsLine } = {}
	if total <= 0 then
		return list
	end
	for _, ore in OreData.List do
		local weight = boosted[ore.Id]
		if weight then
			table.insert(list, { Ore = ore.Id, Chance = weight / total })
		end
	end
	return list
end

-- oreOdds for a zone (WorldLayout.Zones id); empty for an unknown zone.
function BoostConfig.zoneOdds(zoneId: string, luck: number): { OddsLine }
	local zone = WorldLayout.ZoneById[zoneId]
	if not zone then
		return {}
	end
	return BoostConfig.oreOdds(zone.Ores, luck)
end

-- Picks an ore for a roll in [0, 1) straight from the weights with luck (nil
-- for no weights). A fresh roll: MiningService uses upgradeOre instead.
function BoostConfig.rollOre(weights: { [string]: number }, luck: number, roll: number): string?
	local list = BoostConfig.oreOdds(weights, luck)
	local acc = 0
	for _, line in list do
		acc += line.Chance
		if roll < acc then
			return line.Ore
		end
	end
	local last = list[#list]
	return if last then last.Ore else nil
end

-- The plain totals of the weights: (lower ores, Rare and rarer ores).
local function totals(weights: { [string]: number }): (number, number)
	local low, rare = 0, 0
	for oreId, weight in BoostConfig.oreWeights(weights, 1) do
		if BoostConfig.isLuckyOre(oreId) then
			rare += weight
		else
			low += weight
		end
	end
	return low, rare
end

-- Chance that a chunk whose rock rolled a lower ore is upgraded (1 - T/T',
-- see the header). 0 without luck, without Rare+ ores or without lower ores.
function BoostConfig.upgradeChance(weights: { [string]: number }, luck: number): number
	if not finite(luck) or luck <= 1 then
		return 0
	end
	local low, rare = totals(weights)
	if low <= 0 or rare <= 0 then
		return 0
	end
	local plain = low + rare
	return 1 - plain / (low + rare * luck)
end

-- Chance that a chunk is Rare or rarer with these weights and luck.
function BoostConfig.rareShare(weights: { [string]: number }, luck: number): number
	local low, rare = totals(weights)
	local mult = if finite(luck) and luck > 1 then luck else 1
	local total = low + rare * mult
	return if total > 0 then rare * mult / total else 0
end

-- The ore a dropped chunk really is (exact coupling, see the header): the
-- rock's `rolled` ore stays when there is no luck, when it is Rare or rarer,
-- or when it isn't one of `weights`; else with upgradeChance it becomes a
-- Rare+ ore of `weights` picked in proportion to its weight. `random` is
-- called only when an upgrade is possible (once, plus once for the pick).
function BoostConfig.upgradeOre(weights: { [string]: number }, luck: number, rolled: string, random: () -> number): string
	if BoostConfig.isLuckyOre(rolled) then
		return rolled
	end
	local plain = BoostConfig.oreWeights(weights, 1)
	if plain[rolled] == nil then
		return rolled
	end
	local chance = BoostConfig.upgradeChance(weights, luck)
	if chance <= 0 or random() >= chance then
		return rolled
	end
	local rare = {}
	local total = 0
	for _, ore in OreData.List do
		local weight = plain[ore.Id]
		if weight and BoostConfig.isLuckyOre(ore.Id) then
			table.insert(rare, ore.Id)
			total += weight
		end
	end
	local target = random() * total
	for _, oreId in rare do
		target -= plain[oreId]
		if target < 0 then
			return oreId
		end
	end
	return rare[#rare] or rolled
end

-- The zones a player can mine at this blaster level (VIP zones with `vip`), in
-- WorldLayout order (zones without ores are left out).
function BoostConfig.minableZones(blasterLevel: any, vip: boolean?): { WorldLayout.Zone }
	local level = if finite(blasterLevel) then blasterLevel else 1
	local list = {}
	for _, zone in WorldLayout.Zones do
		if next(zone.Ores) ~= nil and zone.MinBlaster <= level and (vip or not zone.VipOnly) then
			table.insert(list, zone)
		end
	end
	return list
end

-- A Hexa Lucky card's summary: per minable zone the Rare+ chance now and with
-- the boost (luck values from hexaLuck), NoEffect for zones without Rare+ ores.
function BoostConfig.zoneEffects(blasterLevel: any, vip: boolean?, luckNow: number, luckWith: number): { ZoneEffect }
	local list: { ZoneEffect } = {}
	for _, zone in BoostConfig.minableZones(blasterLevel, vip) do
		local _, rare = totals(zone.Ores)
		table.insert(list, {
			Zone = zone.Id,
			Before = BoostConfig.rareShare(zone.Ores, luckNow),
			After = BoostConfig.rareShare(zone.Ores, luckWith),
			NoEffect = rare <= 0,
		})
	end
	return list
end

-- Does a boost do anything for this player? Triple Lucky: always (capsules);
-- Hexa Lucky: when a zone they can mine has a Rare+ ore. Unknown kind: false.
function BoostConfig.hasEffect(kindId: string, blasterLevel: any, vip: boolean?): boolean
	local kind = BoostConfig.Kinds[kindId]
	if not kind then
		return false
	end
	if kind.Target ~= "Mining" then
		return true
	end
	for _, zone in BoostConfig.minableZones(blasterLevel, vip) do
		local _, rare = totals(zone.Ores)
		if rare > 0 then
			return true
		end
	end
	return false
end

return BoostConfig
