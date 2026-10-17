--[[
	Luck boosts (step 6, the side menu "Boosts"). Two kinds, each a timer
	saved as an os.time() second in data.Boosts (it runs in real time, also
	while you are offline; compare with workspace:GetServerTimeNow() on the
	client):

	  TripleLucky  (data.Boosts.TripleLuckyUntil) golem capsules: every golem
	               at least as rare as the capsule's LuckyFrom (Stone: Rare+,
	               Crystal: Epic+, Royal: Legendary+) is exactly 3 times as
	               likely; the other golems share the rest (CapsuleConfig.odds).
	  HexaLucky    (data.Boosts.HexaLuckyUntil) mining: in every ore roll of a
	               rock the weight of each Rare or rarer ore is multiplied by
	               2.5, then the chances are recomputed so they add up to 100 %
	               (oreOdds). It stacks with the Lucky enchant and Luck golems
	               (their +% multiply the same weights: Bonuses.oreLuck).

	Where they come from: small coin versions (5 min, CoinOffers, BoostAction
	"BuyCoins" { Id }), Robux packs (15 min / 1 h, RobuxOffers, BoostAction
	"BuyRobux" { Id } -> PurchasePrompt) and the daily wheel (10 min).
	Stacking: every new boost of the same kind adds its time to what is left;
	at most MaxStackSeconds (2 h) may be left after a coin buy or a wheel
	prize (a coin buy that would pass it is refused, "Full"; the wheel caps).
	A Robux pack is only offered while it fits; a receipt that arrives late
	still adds its full time (paid time is never lost); saves are capped at
	MaxSavedSeconds.

	Roblox rules: paid boosts that change the odds of random results must show
	the NEW odds in numbers before purchase: the boost card shows oreOdds()
	(the zone the player is in, or a zone picker) / CapsuleConfig.odds(id, true).
	Both kinds count as paid random items (PaidRandom): hidden where
	PolicyService ArePaidRandomItemsRestricted is true.
]]

local OreData = require(script.Parent.OreData)
local Rarity = require(script.Parent.Rarity)
local WorldLayout = require(script.Parent.WorldLayout)
local MonetizationConfig = require(script.Parent.MonetizationConfig)

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
	PriceSeconds: number?, -- coin offers: costs this many seconds of podium income...
	MinPrice: number?, -- ...but at least this many coins
	Product: string?, -- Robux offers: MonetizationConfig key
}

export type OddsLine = { Ore: string, Chance: number }

local BoostConfig = {}

BoostConfig.MaxStackSeconds = 2 * 3600
BoostConfig.MaxSavedSeconds = 24 * 3600

-- BoostAction / ActionResult reason codes -> text for the player
BoostConfig.Reasons = {
	BadOffer = "That boost isn't sold here",
	Full = "That boost already has 2 hours left",
	NoCoins = "Not enough coins",
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
	{ Id = "TripleLucky5", Boost = "TripleLucky", Seconds = 300, PriceSeconds = 240, MinPrice = 2500 },
	{ Id = "HexaLucky5", Boost = "HexaLucky", Seconds = 300, PriceSeconds = 240, MinPrice = 2500 },
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

-- Coins a coin offer costs at this podium income (nil for other offers).
function BoostConfig.coinPrice(offerId: any, incomePerSecond: number): number?
	local offer = if type(offerId) == "string" then BoostConfig.OfferById[offerId] else nil
	if not offer or not offer.PriceSeconds then
		return nil
	end
	local income = if finite(incomePerSecond) and incomePerSecond > 0 then math.min(incomePerSecond, 1e27) else 0
	return math.max(offer.MinPrice or 0, math.ceil(income * offer.PriceSeconds))
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

-- Picks an ore for a roll in [0, 1) from weights with luck (nil for no weights).
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

return BoostConfig
