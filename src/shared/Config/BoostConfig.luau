--[[
	Luck boosts (step 6, the side menu "Boosts"). Two kinds, each a timer
	saved as an os.time() second in data.Boosts (it runs in real time, also
	while you are offline; compare with workspace:GetServerTimeNow() on the
	client):

	  TripleLucky  (data.Boosts.TripleLuckyUntil) golem capsules: every golem
	               at least as rare as the capsule's LuckyFrom (Stone: Rare+,
	               Crystal: Epic+, Royal: Legendary+) is exactly 3 times as
	               likely; the other golems share the rest (CapsuleConfig.odds).
	  HexaLucky    (data.Boosts.HexaLuckyUntil) mining: ore luck x2.5, which
	               multiplies the weight of each ore in a rock's ore roll by
	               rarity: Rare x2.5, Epic x3.95, Legendary x6.25, Mythic x9.88
	               (luckTable; Common and Uncommon x1), then the chances are
	               recomputed so they add up to 100 % (oreOdds).
	               OWNER: the name came from the brief; Legendary ores are
	               about x6 ("Hexa") - rename it or change Mult if you like.

	Ore luck (one number L >= 1, StatConfig.oreLuck: (1 + OreLuckPct) x
	OreLuckMult, at most x6.25, which never cuts Hexa Lucky's x2.5): the
	Lucky and Starbreaker enchants and the Luck
	golems add to OreLuckPct, Hexa Lucky multiplies. It GROWS WITH RARITY:
	an ore's weight is multiplied by L ^ LuckPower[its rarity] (Rare 1, Epic
	1.5, Legendary 2, Mythic 2.5), so luck still matters where most ores are
	already Rare+ (Deep Hollow: Hexa Lucky takes Mythic from 0.17 % to 0.59 %,
	Legendary from 3.7 % to 8.0 %).

	How luck works in a rock (upgradeOre, exact): a rock's ores are rolled
	from the zone's plain weights when it grows, and the rock shows them
	(glints, health). When a chunk drops, luck only ever UPGRADES it. With
	the plain chances p and the lucky chances p' (oreOdds), an ore whose
	share grows (p' >= p) always stays what it is; an ore whose share drops
	(p' < p) stays with chance p'/p and otherwise becomes one of the ores
	whose share grows, picked in proportion to their gain (p' - p). The
	multipliers never fall with rarity, so a dropping ore is always less rare
	than every growing one: a change is always an upgrade, and every chunk
	has exactly the chances oreOdds(zone weights, luck) shows on the card.
	A zone without Rare+ ores (Outcrops) gets nothing from ore luck: the
	cards show "No effect here" for it (zoneEffects); a coin buy of Hexa
	Lucky is refused ("NoEffect") when no zone the player can mine has a
	Rare+ ore (hasEffect).

	Where boosts come from: small coin versions (5 min, CoinOffers,
	BoostAction "BuyCoins" { Id }), Robux packs (15 min / 1 h, RobuxOffers,
	BoostAction "BuyRobux" { Id } -> PurchasePrompt) and the daily wheel
	(10 min).
	Coin prices (coinPrice / coinQuote; they never read the income, which can
	be gamed by emptying the podiums before buying):
	  TripleLucky5  2 Crystal capsules at the player's blaster level (Triple
	                Lucky pays off on Crystal and Royal capsules, so it is
	                priced against them: 2 h of it costs 48 Crystal capsules)
	  HexaLucky5    20 % of the player's next blaster forge (the level-10
	                forge at the top), at least 2,500 coins: it grows with
	                the mines the player can reach
	Coins only TOP UP a boost: a coin offer is sold only while less than
	CoinBuyBelow (10 min) of that boost is left ("CoinLimit"), so coins keep
	at most 15 minutes running; longer runs come from the Robux packs and
	the wheel.
	Stacking: every new boost of the same kind adds its time to what is left;
	at most MaxStackSeconds (2 h) may be left after a coin buy or a wheel
	prize (the wheel caps). A Robux pack is only offered while it fits; a
	receipt that arrives late still adds its full time, uncapped (paid time
	is never lost: Migrations only clips junk beyond MaxSavedSeconds, a
	year ahead, never a real purchase).

	Roblox rules: anything bought (Robux or coins) that changes the odds of
	random results must show the NEW odds in numbers before purchase. A Hexa
	Lucky card shows preview(context, { OreLuckMult = Mult }): per zone the
	chance of each rarity now and with the boost, and zoneOdds() per ore on
	"Details"; a Triple Lucky card shows CapsuleConfig.odds(id, true) next to
	odds(id, false). The odds-boosting enchants (EnchantConfig OddsBoost:
	Lucky, Prospector, Starbreaker) use the same preview with
	EnchantConfig.nextDelta, artifact chances included.
	Robux packs are paid random items; coin offers are too only while coins
	can be bought with Robux (isPaidRandom, MonetizationConfig.coinsBuyable).
	Paid random items are hidden where PolicyService
	ArePaidRandomItemsRestricted is true.
]]

local ArtifactConfig = require(script.Parent.ArtifactConfig)
local BlasterData = require(script.Parent.BlasterData)
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
	Stat: string, -- StatConfig stat it sets while active
	Description: string,
	Color: Color3,
}

export type Offer = {
	Id: string,
	Boost: string, -- Kind id
	Seconds: number,
	-- coin offers (see coinPrice): Count capsules of PriceCapsule at the
	-- player's blaster level, or ForgeShare of the next blaster forge (at
	-- least MinPrice)
	PriceCapsule: string?,
	PriceCount: number?,
	ForgeShare: number?,
	MinPrice: number?,
	Product: string?, -- Robux offers: MonetizationConfig key
}

export type OddsLine = { Ore: string, Chance: number }
export type RarityLine = { Rarity: string, Before: number, After: number }
export type ZoneEffect = {
	Zone: string,
	Before: number, -- chance that a chunk is Rare or rarer now
	After: number, -- the same with the boost
	Rarities: { RarityLine }, -- per lucky rarity found in the zone (Rare first, Mythic last)
	NoEffect: boolean, -- the zone has no Rare+ ore
}
export type ArtifactEffect = { Zone: string, Before: number, After: number }
-- What a luck card compares (the numbers from State.Bonuses, capped totals).
export type LuckContext = {
	BlasterLevel: number,
	Vip: boolean?,
	OreLuckPct: number, -- State.Bonuses.OreLuckPct
	OreLuckMult: number, -- State.Bonuses.OreLuckMult (2.5 while Hexa Lucky runs)
	ArtifactPct: number, -- State.Bonuses.ArtifactPct
}
export type OddsPreview = {
	LuckBefore: number,
	LuckAfter: number,
	Zones: { ZoneEffect },
	Artifacts: { ArtifactEffect }, -- chance per rock of an artifact, per minable zone
}

local BoostConfig = {}

BoostConfig.MaxStackSeconds = 2 * 3600
-- A junk guard, never a gameplay cap: Migrations only clips a saved boost
-- that ends more than this far ahead (broken or hacked values). Paid time
-- (Robux packs, step 8: BoostService.add capped = false) is never lost, so
-- this sits far above anything a player can buy on purpose (a year of
-- boost is 8,760 hour packs).
BoostConfig.MaxSavedSeconds = 365 * 24 * 3600
-- a coin offer is sold only while less than this is left of that boost
BoostConfig.CoinBuyBelow = 600

-- Ore luck L multiplies an ore's weight by L ^ LuckPower[rarity] (header).
-- Never falling with rarity: that keeps every luck change an upgrade.
BoostConfig.LuckPower = {
	Common = 0,
	Uncommon = 0,
	Rare = 1,
	Epic = 1.5,
	Legendary = 2,
	Mythic = 2.5,
} :: { [string]: number }

-- BoostAction / ActionResult reason codes -> text for the player
BoostConfig.Reasons = {
	BadOffer = "That boost isn't sold here",
	Full = "That boost already has 2 hours left",
	CoinLimit = "Coins top a boost up only when less than 10 minutes are left",
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
		Stat = "OreLuckMult",
		Description = "Mining: ore luck x2.5. Rare ores weigh x2.5, Epic x4, Legendary x6.3 and Mythic x9.9 in every rock you break.",
		Color = Color3.fromRGB(255, 196, 60),
	},
} :: { [string]: Kind }
BoostConfig.KindIds = { "TripleLucky", "HexaLucky" }

BoostConfig.CoinOffers = {
	{ Id = "TripleLucky5", Boost = "TripleLucky", Seconds = 300, PriceCapsule = "Crystal", PriceCount = 2 },
	{ Id = "HexaLucky5", Boost = "HexaLucky", Seconds = 300, ForgeShare = 0.2, MinPrice = 2500 },
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
		else
			local capsule = offer.PriceCapsule
			assert(
				(capsule ~= nil and CapsuleConfig.ById[capsule] ~= nil and (offer.PriceCount or 0) > 0) or (offer.ForgeShare or 0) > 0,
				"BoostConfig: coin offer without a price " .. offer.Id
			)
		end
	end
end
for _, info in Rarity.List do
	assert(BoostConfig.LuckPower[info.Id], "BoostConfig: no LuckPower for " .. info.Id)
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
-- buys check coinQuote first; the wheel just caps); a Robux receipt passes
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

-- Coins a coin offer costs at this blaster level (nil for other offers):
-- PriceCount capsules of PriceCapsule (CapsuleConfig.price at that level),
-- or ForgeShare of the next blaster forge's coins (the top level's own
-- forge at the top), at least MinPrice.
function BoostConfig.coinPrice(offerId: any, blasterLevel: any): number?
	local offer = if type(offerId) == "string" then BoostConfig.OfferById[offerId] else nil
	if not offer or offer.Product ~= nil then
		return nil
	end
	local capsule = offer.PriceCapsule
	if capsule then
		local each = CapsuleConfig.price(capsule, 1, blasterLevel) or 0
		return math.max(offer.MinPrice or 0, each * (offer.PriceCount or 1))
	end
	local level = BlasterData.get(blasterLevel).Level
	local upcoming = BlasterData.get(math.min(level + 1, BlasterData.MaxLevel))
	local recipe = upcoming.Recipe
	local forge = if recipe then recipe.Coins else 0
	return math.max(offer.MinPrice or 0, math.floor(forge * (offer.ForgeShare or 0) + 0.5))
end

-- The server's check of a BoostAction "BuyCoins": the price for this
-- player, or nil + "BadOffer" | "NoEffect" | "CoinLimit" | "Full"
-- (Reasons). The caller then checks the coins ("NoCoins"), pays and
-- extend()s with capped = true, all without yielding.
function BoostConfig.coinQuote(boosts: any, offerId: any, blasterLevel: any, vip: boolean?, now: number): (number?, string?)
	local offer = if type(offerId) == "string" then BoostConfig.OfferById[offerId] else nil
	if not offer or offer.Product ~= nil then
		return nil, "BadOffer"
	end
	if not BoostConfig.hasEffect(offer.Boost, blasterLevel, vip) then
		return nil, "NoEffect"
	end
	if BoostConfig.remaining(boosts, offer.Boost, now) >= BoostConfig.CoinBuyBelow then
		return nil, "CoinLimit"
	end
	if not BoostConfig.canExtend(boosts, offer.Boost, offer.Seconds, now) then
		return nil, "Full"
	end
	return BoostConfig.coinPrice(offer.Id, blasterLevel), nil
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

local function cleanLuck(luck: any): number
	return if finite(luck) and luck > 1 then luck else 1
end

-- The weight multiplier of a rarity at ore luck `luck` (1 without luck or
-- for an unknown rarity): luck ^ LuckPower[rarity].
function BoostConfig.rarityMult(rarityId: string, luck: number): number
	local power = BoostConfig.LuckPower[rarityId]
	if not power or power <= 0 then
		return 1
	end
	return cleanLuck(luck) ^ power
end

-- The weight multiplier of an ore at ore luck `luck` (1 for an unknown ore).
function BoostConfig.oreMult(oreId: string, luck: number): number
	local ore = OreData.ById[oreId]
	return if ore then BoostConfig.rarityMult(ore.Rarity, luck) else 1
end

-- Does ore luck boost this ore (Rare or rarer)?
function BoostConfig.isLuckyOre(oreId: string): boolean
	local ore = OreData.ById[oreId]
	local power = if ore then BoostConfig.LuckPower[ore.Rarity] else nil
	return power ~= nil and power > 0
end

-- The multiplier of each lucky rarity at this luck, Rare first (for cards:
-- "Rare x2.5, Epic x4, Legendary x6.3, Mythic x9.9").
function BoostConfig.luckTable(luck: number): { { Rarity: string, Mult: number } }
	local list = {}
	for _, info in Rarity.List do
		if (BoostConfig.LuckPower[info.Id] or 0) > 0 then
			table.insert(list, { Rarity = info.Id, Mult = BoostConfig.rarityMult(info.Id, luck) })
		end
	end
	return list
end

-- The ore luck with and without Hexa Lucky for a player whose other luck is
-- `oreLuckPct` (Lucky enchant + Luck golems, capped): what a Hexa Lucky card
-- compares. Both are StatConfig.oreLuck (at most StatConfig.MaxOreLuck).
function BoostConfig.hexaLuck(oreLuckPct: number): (number, number)
	local hexa = BoostConfig.Kinds.HexaLucky.Mult
	return StatConfig.oreLuck(oreLuckPct, 1), StatConfig.oreLuck(oreLuckPct, hexa)
end

-- Ore weights with luck: every ore's weight x oreMult (luck <= 1 or not
-- finite: the weights unchanged). Unknown ores and weights that aren't > 0
-- are left out.
function BoostConfig.oreWeights(weights: { [string]: number }, luck: number): { [string]: number }
	local out: { [string]: number } = {}
	for oreId, weight in weights do
		if OreData.ById[oreId] and finite(weight) and weight > 0 then
			out[oreId] = weight * BoostConfig.oreMult(oreId, luck)
		end
	end
	return out
end

local function totalOf(weights: { [string]: number }): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	return total
end

-- Exact chance of each ore in one ore roll with these weights and luck,
-- in OreData order (rarer last). Sums to 1 (empty for no weights).
function BoostConfig.oreOdds(weights: { [string]: number }, luck: number): { OddsLine }
	local boosted = BoostConfig.oreWeights(weights, luck)
	local total = totalOf(boosted)
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

-- A share that is this close to 1 (or a gain this close to 0, relative)
-- is rounding noise: the ore keeps its share.
local NOISE = 1e-12

-- Chance that a dropped chunk of `oreId` (a lower ore when nil: x1) keeps
-- its ore with this luck: min(1, p'/p) = min(1, mult x T / T'), T and T'
-- the plain and lucky total weights. 1 without luck or for an ore that
-- isn't one of `weights` (with an `oreId`).
function BoostConfig.keepChance(weights: { [string]: number }, luck: number, oreId: string?): number
	local plain = BoostConfig.oreWeights(weights, 1)
	if oreId ~= nil and plain[oreId] == nil then
		return 1
	end
	local total = totalOf(plain)
	local lucky = totalOf(BoostConfig.oreWeights(weights, luck))
	if total <= 0 or lucky <= 0 then
		return 1
	end
	local mult = if oreId then BoostConfig.oreMult(oreId, luck) else 1
	local keep = mult * total / lucky
	return if keep >= 1 - NOISE then 1 else keep
end

-- Chance that a dropped chunk of `oreId` (a lower ore when nil) is upgraded
-- (1 - keepChance). 0 without luck, for an ore whose share grows, or in a
-- zone where every ore weighs the same multiplier.
function BoostConfig.upgradeChance(weights: { [string]: number }, luck: number, oreId: string?): number
	return 1 - BoostConfig.keepChance(weights, luck, oreId)
end

-- The ores whose share grows with this luck and by how much (p' - p), in
-- OreData order; the upgrade targets of upgradeOre.
function BoostConfig.gains(weights: { [string]: number }, luck: number): { OddsLine }
	local list: { OddsLine } = {}
	local plain = BoostConfig.oreWeights(weights, 1)
	local lucky = BoostConfig.oreWeights(weights, luck)
	local total, luckyTotal = totalOf(plain), totalOf(lucky)
	if total <= 0 or luckyTotal <= 0 then
		return list
	end
	for _, ore in OreData.List do
		local w = plain[ore.Id]
		if w then
			local before, after = w / total, lucky[ore.Id] / luckyTotal
			if after - before > NOISE * after then
				table.insert(list, { Ore = ore.Id, Chance = after - before })
			end
		end
	end
	return list
end

-- The ore a dropped chunk really is (exact coupling, see the header): the
-- rock's `rolled` ore stays when its share doesn't drop with this luck (or
-- it isn't one of `weights`); else a roll below upgradeChance turns it into
-- one of the gains() ores, picked in proportion to its gain. `random` is
-- called only when the ore may change (once, plus once for the pick).
function BoostConfig.upgradeOre(weights: { [string]: number }, luck: number, rolled: string, random: () -> number): string
	local plain = BoostConfig.oreWeights(weights, 1)
	if plain[rolled] == nil then
		return rolled
	end
	local chance = BoostConfig.upgradeChance(weights, luck, rolled)
	if chance <= 0 or random() >= chance then
		return rolled
	end
	local targets = BoostConfig.gains(weights, luck)
	local total = 0
	for _, line in targets do
		total += line.Chance
	end
	if total <= 0 then
		return rolled
	end
	local target = random() * total
	for _, line in targets do
		target -= line.Chance
		if target < 0 then
			return line.Ore
		end
	end
	return targets[#targets].Ore
end

-- Chance of each rarity in one ore roll with these weights and luck.
function BoostConfig.rarityShares(weights: { [string]: number }, luck: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, line in BoostConfig.oreOdds(weights, luck) do
		local rarity = OreData.ById[line.Ore].Rarity
		out[rarity] = (out[rarity] or 0) + line.Chance
	end
	return out
end

-- Chance that a chunk is Rare or rarer with these weights and luck.
function BoostConfig.rareShare(weights: { [string]: number }, luck: number): number
	local share = 0
	for _, line in BoostConfig.oreOdds(weights, luck) do
		if BoostConfig.isLuckyOre(line.Ore) then
			share += line.Chance
		end
	end
	return share
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

-- A luck card's summary: per minable zone the Rare+ chance and the chance
-- of each lucky rarity in it, at luck `luckNow` and `luckWith`; NoEffect for
-- zones without Rare+ ores.
function BoostConfig.zoneEffects(blasterLevel: any, vip: boolean?, luckNow: number, luckWith: number): { ZoneEffect }
	local list: { ZoneEffect } = {}
	for _, zone in BoostConfig.minableZones(blasterLevel, vip) do
		local before = BoostConfig.rarityShares(zone.Ores, luckNow)
		local after = BoostConfig.rarityShares(zone.Ores, luckWith)
		local rarities: { RarityLine } = {}
		for _, info in Rarity.List do
			if (BoostConfig.LuckPower[info.Id] or 0) > 0 and before[info.Id] then
				table.insert(rarities, { Rarity = info.Id, Before = before[info.Id], After = after[info.Id] or 0 })
			end
		end
		table.insert(list, {
			Zone = zone.Id,
			Before = BoostConfig.rareShare(zone.Ores, luckNow),
			After = BoostConfig.rareShare(zone.Ores, luckWith),
			Rarities = rarities,
			NoEffect = #rarities == 0,
		})
	end
	return list
end

-- What a luck card shows before ANY buy that changes odds (Hexa Lucky
-- coins or Robux, the OddsBoost enchants for coins, shards or Robux): the
-- player's luck and artifact chances now and with `add` ({ OreLuckPct?,
-- OreLuckMult?, ArtifactPct? }, e.g. { OreLuckMult = 2.5 } for Hexa Lucky
-- or EnchantConfig.nextDelta), every total capped like Bonuses does.
function BoostConfig.preview(context: LuckContext, add: { [string]: number }): OddsPreview
	local function cap(id: string, value: number): number
		local max = StatConfig.ById[id].Max
		return if max then math.min(value, max) else value
	end
	local function num(v: any, default: number): number
		return if finite(v) then v else default
	end
	local pct = math.max(0, num(context.OreLuckPct, 0))
	local mult = math.max(1, num(context.OreLuckMult, 1))
	local art = math.max(0, num(context.ArtifactPct, 0))
	local pctAfter = cap("OreLuckPct", pct + math.max(0, num(add.OreLuckPct, 0)))
	local multAfter = cap("OreLuckMult", mult * math.max(1, num(add.OreLuckMult, 1)))
	local artAfter = cap("ArtifactPct", art + math.max(0, num(add.ArtifactPct, 0)))
	local luckBefore = StatConfig.oreLuck(pct, mult)
	local luckAfter = StatConfig.oreLuck(pctAfter, multAfter)
	local artifacts: { ArtifactEffect } = {}
	for _, zone in BoostConfig.minableZones(context.BlasterLevel, context.Vip) do
		local chance = ArtifactConfig.rockChance(zone.Id)
		table.insert(artifacts, {
			Zone = zone.Id,
			Before = math.clamp(chance * (1 + art), 0, 1),
			After = math.clamp(chance * (1 + artAfter), 0, 1),
		})
	end
	return {
		LuckBefore = luckBefore,
		LuckAfter = luckAfter,
		Zones = BoostConfig.zoneEffects(context.BlasterLevel, context.Vip, luckBefore, luckAfter),
		Artifacts = artifacts,
	}
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
		for oreId in zone.Ores do
			if BoostConfig.isLuckyOre(oreId) then
				return true
			end
		end
	end
	return false
end

return BoostConfig
