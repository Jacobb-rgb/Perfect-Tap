--[[
	The daily wheel of fortune (step 7, SPIN & WIN in town; the free spin is
	taken at the wheel's EmberChest / SpinWheel, WheelAction "Spin").

	- One free spin every 24 h. data.Wheel.NextSpinAt is the os.time() second
	  the next free spin is ready (0 = ready now), so the timer keeps running
	  while the player is offline. A spin sets it to now + CooldownSeconds.
	- 8 segments with exact odds (sum 1), shown on the wheel screen before
	  spinning (odds()). Colors match the lobby wheel's rainbow segments
	  (src/server/World/Lobby/Districts/Wheel.luau SEGMENTS; the lobby wheel has
	  10 decorative segments, the wheel screen uses these 8 of its colors).
	- Prizes:
	    Coins       Seconds x the player's podium income per second, at least Min
	    Boost       adds Seconds to that boost (BoostConfig.extend, capped)
	    Capsule     opens one capsule of that kind for free right away
	                (CapsuleConfig.roll + GolemConfig.add; the player's Triple
	                Lucky counts); with a full golem inventory the player gets
	                the capsule's coin price instead
	    Ore         one dirty (Raw) ore of Rare or better (OreWeights) into the
	                Ore Pen; with a full pen the player gets what Tobin pays
	                for it (ItemData.value("Raw", ore)) instead
	    Shards      Amount crystal shards (data.Shards)
	- The spin is free and can't be bought, so it isn't a paid random item;
	  its odds are still shown (Roblox: odds for any random reward). There are
	  no paid spins and no rewards for likes or favorites.
	WheelResult { Segment, Id, Kind, Amount?, Boost?, Seconds?, Capsule?,
	Golem?, Ore?, Coins?, NextSpinAt } tells the client where the wheel stops.
]]

local CapsuleConfig = require(script.Parent.CapsuleConfig)
local BoostConfig = require(script.Parent.BoostConfig)
local ItemData = require(script.Parent.ItemData)
local OreData = require(script.Parent.OreData)
local Rarity = require(script.Parent.Rarity)

export type PrizeKind = "Coins" | "Boost" | "Capsule" | "Ore" | "Shards"

export type Segment = {
	Index: number, -- 1..8, clockwise from the top
	Id: string,
	Kind: PrizeKind,
	Label: string, -- short text on the wheel
	Odds: number,
	Color: Color3,
	Seconds: number?, -- Coins: seconds of income; Boost: boost seconds
	Min: number?, -- Coins: at least this many coins
	Boost: string?, -- BoostConfig kind
	Capsule: string?, -- CapsuleConfig id
	Amount: number?, -- Shards
}

local WheelConfig = {}

WheelConfig.CooldownSeconds = 24 * 3600
WheelConfig.SpinSeconds = 5 -- how long the wheel screen spins before showing the prize
-- the lobby hooks that open the wheel screen (the spin itself works from the side menu too)
WheelConfig.Tag = "EmberChest" -- the free daily chest at the top of the SPIN & WIN stairs
WheelConfig.ModelName = "SpinWheel"

-- WheelAction / ActionResult reason codes -> text for the player
WheelConfig.Reasons = {
	NotReady = "Your next free spin isn't ready yet",
} :: { [string]: string }

local rgb = Color3.fromRGB

WheelConfig.Segments = {
	{ Index = 1, Id = "Coins", Kind = "Coins", Label = "Coins", Odds = 0.3, Color = rgb(130, 16, 26), Seconds = 120, Min = 500 },
	{
		Index = 2,
		Id = "TripleLucky",
		Kind = "Boost",
		Label = "Triple Lucky 10m",
		Odds = 0.12,
		Color = rgb(150, 70, 8),
		Boost = "TripleLucky",
		Seconds = 600,
	},
	{ Index = 3, Id = "StoneCapsule", Kind = "Capsule", Label = "Stone Capsule", Odds = 0.15, Color = rgb(150, 120, 8), Capsule = "Stone" },
	{ Index = 4, Id = "Shards", Kind = "Shards", Label = "25 Shards", Odds = 0.1, Color = rgb(14, 110, 46), Amount = 25 },
	{ Index = 5, Id = "BigCoins", Kind = "Coins", Label = "Big Coins", Odds = 0.08, Color = rgb(8, 112, 122), Seconds = 600, Min = 2500 },
	{
		Index = 6,
		Id = "HexaLucky",
		Kind = "Boost",
		Label = "Hexa Lucky 10m",
		Odds = 0.12,
		Color = rgb(18, 60, 150),
		Boost = "HexaLucky",
		Seconds = 600,
	},
	{ Index = 7, Id = "RareOre", Kind = "Ore", Label = "Rare Ore", Odds = 0.08, Color = rgb(100, 24, 140) },
	{
		Index = 8,
		Id = "CrystalCapsule",
		Kind = "Capsule",
		Label = "Crystal Capsule",
		Odds = 0.05,
		Color = rgb(140, 24, 90),
		Capsule = "Crystal",
	},
} :: { Segment }

-- The dirty ore the RareOre segment gives (weights; all Rare or better).
WheelConfig.OreWeights = {
	Gold = 30,
	Ruby = 25,
	Azurium = 18,
	Sapphire = 12,
	Emerald = 8,
	Diamond = 4,
	Verdantine = 2,
	Obsidian = 1,
} :: { [string]: number }

WheelConfig.ById = {} :: { [string]: Segment }
for _, segment in WheelConfig.Segments do
	WheelConfig.ById[segment.Id] = segment
	local capsule = segment.Capsule
	assert(capsule == nil or CapsuleConfig.ById[capsule], "WheelConfig: unknown capsule")
	local boost = segment.Boost
	assert(boost == nil or BoostConfig.Kinds[boost], "WheelConfig: unknown boost")
end
for oreId in WheelConfig.OreWeights do
	local ore = OreData.ById[oreId]
	assert(ore and Rarity.ById[ore.Rarity].Order >= Rarity.ById.Rare.Order, "WheelConfig: ore prize must be Rare+ " .. oreId)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The segment odds for the wheel screen: { { Segment, Chance } } (sum 1).
function WheelConfig.odds(): { { Segment: Segment, Chance: number } }
	local list = {}
	for _, segment in WheelConfig.Segments do
		table.insert(list, { Segment = segment, Chance = segment.Odds })
	end
	return list
end

-- The segment for a roll in [0, 1).
function WheelConfig.pick(roll: number): Segment
	local acc = 0
	for _, segment in WheelConfig.Segments do
		acc += segment.Odds
		if roll < acc then
			return segment
		end
	end
	return WheelConfig.Segments[#WheelConfig.Segments]
end

-- Is the free spin ready? (`nextSpinAt` from data.Wheel; broken = ready)
function WheelConfig.ready(nextSpinAt: any, now: number): boolean
	return not finite(nextSpinAt) or now >= nextSpinAt
end

-- Seconds until the next free spin (0 when ready).
function WheelConfig.secondsLeft(nextSpinAt: any, now: number): number
	if not finite(nextSpinAt) then
		return 0
	end
	return math.max(0, nextSpinAt - now)
end

-- Coins a Coins segment pays at this podium income (0 for other segments).
function WheelConfig.coins(segment: Segment, incomePerSecond: number): number
	if segment.Kind ~= "Coins" then
		return 0
	end
	local income = if finite(incomePerSecond) and incomePerSecond > 0 then math.min(incomePerSecond, 1e27) else 0
	return math.max(segment.Min or 0, math.floor(income * (segment.Seconds or 0)))
end

-- The RareOre segment's ore for a roll in [0, 1).
function WheelConfig.pickOre(roll: number): string
	local keys = {}
	local total = 0
	for oreId, weight in WheelConfig.OreWeights do
		table.insert(keys, oreId)
		total += weight
	end
	table.sort(keys, function(a: string, b: string): boolean
		return OreData.ById[a].Income < OreData.ById[b].Income
	end)
	local target = roll * total
	for _, oreId in keys do
		target -= WheelConfig.OreWeights[oreId]
		if target < 0 then
			return oreId
		end
	end
	return keys[#keys]
end

-- Coins instead of the ore when the pen is full: what Tobin pays for it dirty.
function WheelConfig.oreFallbackCoins(oreId: string): number
	return ItemData.value("Raw", oreId)
end

-- Coins instead of a capsule when the golem inventory is full: its coin price
-- (a Robux capsule pays the Crystal capsule's price).
function WheelConfig.capsuleFallbackCoins(capsuleId: string): number
	return CapsuleConfig.price(capsuleId, 1) or CapsuleConfig.price("Crystal", 1) or 0
end

return WheelConfig
