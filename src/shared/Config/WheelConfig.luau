--[[
	The daily wheel of fortune (step 7, SPIN & WIN in town; the free spin is
	taken at the wheel's EmberChest / SpinWheel, WheelAction "Spin").
	The EmberChest hook belongs to the wheel alone: the old free 7-day
	Ember Chest streak is retired (docs/plans/V2_PLAN.md: "Daily Ember Chest
	-> Wheel of fortune"; data.Daily and the DailyClaim remote are gone).

	- One free spin every 24 h (plus the bought spins, below). data.Wheel.NextSpinAt is the os.time() second
	  the next free spin is ready (0 = ready now), so the timer keeps running
	  while the player is offline. A spin sets it to now + CooldownSeconds.
	- 8 segments with exact odds (sum 1), shown on the wheel SCREEN before
	  spinning (odds()), and the result is shown on that 8-segment screen
	  wheel. Colors are 8 of the lobby wheel's rainbow colors
	  (src/server/World/Lobby/Districts/Wheel.luau SEGMENTS). The big lobby
	  wheel is DECORATIVE ONLY: it has 10 equal segments with made-up icons
	  (a donut, crates) and must never be used to show a result or the odds.
	  Asked of the lobby owner: rebuild it with these 8 segments (labels and
	  colors) or keep it still and without prize icons, so nobody reads it as
	  the prize wheel.
	- Prizes:
	    Coins       Seconds x the player's podium income per second, at least Min
	    Boost       adds Seconds to that boost (BoostConfig.extend, capped)
	    Capsule     opens one capsule of that kind for free right away
	                (CapsuleConfig.roll + GolemConfig.add; the player's Triple
	                Lucky counts); with a full golem inventory the player gets
	                FallbackShare (25 %) of the capsule's coin price at their
	                blaster level instead (capsuleFallbackCoins)
	    Ore         one dirty (Raw) Rare-or-rarer ore into the Ore Pen (see
	                "Ore prize"); which ore it is stays secret until it is
	                cleaned (WheelResult only says DirtyOre = true). With a
	                full pen the player gets the prize's expected raw value
	                instead (oreFallbackCoins: the same for every ore, so
	                the coins don't tell which one it was)
	    Shards      Amount crystal shards (data.Shards)
	- Ore prize: from the Rare-or-rarer ores (BoostConfig.isLuckyOre) of the
	  zones the player's blaster can mine (BoostConfig.minableZones without
	  the VIP zones, for everyone: the free wheel never depends on a paid
	  pass, so the Forgemaster's Pass is no hidden odds booster), those with
	  an Income of at most
	  max(OrePrize.MinIncome, best found ore's Income x OrePrize.IncomeMult),
	  the OrePrize.Picks best of them, weighted OrePrize.Weights (the best one
	  is the least likely). oreOdds(context) is the exact nested list the
	  wheel screen shows under the segment. A day-1 player (blaster 1) wins a
	  Bronze chunk (the Quarry's Rare ore, 130 coins/s on a podium, worth far
	  more than the 500-coin segment); late players their top Rare+ ores. No
	  candidate at all (never with today's map: the Quarry has Bronze): the
	  Coins segment's prize instead.
	- Players who can't buy ANY capsule (paid random items restricted and
	  every capsule is a paid random item: CapsuleConfig.allRestricted) would
	  get nothing from Triple Lucky, so for them that segment pays coins
	  (Substitutes); segments(noCapsules) / odds(noCapsules) / pick(roll,
	  noCapsules) give the wheel they see and spin.
	- Bought spins (owner 2026-10-20: spins are sold for Robux, the wheel
	  screen's BUY SPINS panel: MonetizationConfig WheelSpins1 / 5 / 10, 25 /
	  99 / 179 R$, Packs below). With them the wheel is a PAID RANDOM ITEM:
	    * the exact odds are always visible: every segment's chance on the
	      wheel's face, and the whole list (what each pays this player, the
	      capsules' golem odds, the ore prize's odds) in Details, before any
	      buy and any spin;
	    * PolicyService gates them (src/server/Policy.luau): where paid random
	      items are restricted the BUY SPINS panel is hidden and a "Buy"
	      answers "Restricted" (never sold there), and spins bought earlier
	      are kept in the save but can't be spun there ("Restricted");
	    * a receipt is never refused: it always credits all its spins
	      (MaxSpins is only the prompt's "Full"; the receipt of a player who
	      is restricted now still credits, MonetizationService logs it);
	    * the free daily spin stays free for everyone (restricted players
	      too): it can't be bought, and it is always used first;
	    * a bought spin never swaps a golem for coins: with a full golem
	      inventory it is refused before it is used ("InventoryFull", the
	      spin stays saved) and a "Buy" answers "Full"; a full Ore Pen is
	      no reason to refuse: the ore row says "Ore Pen full: pays N coins
	      instead" on the BUY step and in Details (WheelView.detail), as the
	      capsule rows do for a full inventory (the free spin's coins);
	    * golems won with a bought spin are saved Paid = true and Locked
	      (like every golem bought with Robux).
	  data.Wheel.Spins = the bought spins held (whole >= 0); a bought spin
	  ignores the 24 h cooldown and leaves NextSpinAt alone.
	- No rewards for likes or favorites.
	- A rate-limited "Spin" is dropped without an answer (Net): the client
	  keeps ClientCooldown between requests and gives the button back after
	  ResultTimeout seconds, but a WheelResult that arrives later is still
	  shown (a slow first policy fetch or server lag: the spin happened) and
	  the State push brings the saved NextSpinAt either way.
	WheelResult { Segment, Id, Kind, Amount?, Boost?, Seconds?, Capsule?,
	Golem?, DirtyOre?, Coins?, NextSpinAt, Paid, Spins } tells the client where
	the wheel stops (Paid: a bought spin was used; Spins: bought spins left).
]]

local CapsuleConfig = require(script.Parent.CapsuleConfig)
local BoostConfig = require(script.Parent.BoostConfig)
local ItemData = require(script.Parent.ItemData)
local OreData = require(script.Parent.OreData)

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

-- What the ore prize needs to know about the player (the service builds it:
-- BlasterLevel = data.BlasterLevel, BestIncome = bestIncome(data.Discovered)).
-- No VIP flag: the free wheel's odds never depend on a paid pass.
export type OreContext = { BlasterLevel: number, BestIncome: number }
export type OreLine = { Ore: string, Chance: number }

local WheelConfig = {}

WheelConfig.CooldownSeconds = 24 * 3600
WheelConfig.SpinSeconds = 5 -- how long the wheel screen spins before showing the prize
WheelConfig.FastSpinSeconds = 1.2 -- the same with Fast Spin on (the player's setting, SettingsConfig.FastSpin)
-- bought spins held: a "Buy" past this answers "Full" (a receipt still credits past it)
WheelConfig.MaxSpins = 500
-- Migrations' junk guard on data.Wheel.Spins (no real purchase gets near it: 179 R$ per 10)
WheelConfig.MaxSavedSpins = 1_000_000
-- the BUY SPINS panel's rows, top to bottom (prices: MonetizationConfig)
WheelConfig.Packs = {
	{ Count = 1, Product = "WheelSpins1" },
	{ Count = 5, Product = "WheelSpins5" },
	{ Count = 10, Product = "WheelSpins10" },
} :: { { Count: number, Product: string } }
-- the right-hand panel shows what this segment can give (the rarest prize)
WheelConfig.JackpotId = "CrystalCapsule"
WheelConfig.ClientCooldown = 1 -- seconds between two "Spin" requests from the client
WheelConfig.ResultTimeout = 5 -- seconds the client waits for WheelResult
WheelConfig.FallbackShare = 0.25 -- share of a capsule's price paid when the golem inventory is full
-- the lobby hooks that open the wheel screen (the spin itself works from the side menu too)
WheelConfig.Tag = "EmberChest" -- the free daily chest at the top of the SPIN & WIN stairs
WheelConfig.ModelName = "SpinWheel"

WheelConfig.OrePrize = {
	IncomeMult = 3, -- at most this many times the best found ore's income
	MinIncome = 130, -- ...but always up to this (Bronze, the Quarry's Rare ore: a new player's prize)
	Picks = 3, -- the best few candidates
	Weights = { 1, 2, 3 }, -- best first: the best ore is the least likely
}

-- WheelAction / ActionResult reason codes -> text for the player
WheelConfig.Reasons = {
	NotReady = "No spins: buy some or wait for your free spin",
	Restricted = "Bought spins can't be used where you play. Your free spin comes every day.",
	-- a bought spin never swaps a capsule prize for coins: refused before it is used
	InventoryFull = "Your golem inventory is full: make room before using a bought spin",
	MaxSpins = "You hold the most spins you can: spin some first",
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
	{ Index = 3, Id = "StoneCapsule", Kind = "Capsule", Label = "Stone Egg", Odds = 0.15, Color = rgb(150, 120, 8), Capsule = "Stone" },
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
	{ Index = 7, Id = "OrePrize", Kind = "Ore", Label = "Ore Prize", Odds = 0.08, Color = rgb(100, 24, 140) },
	{
		Index = 8,
		Id = "CrystalCapsule",
		Kind = "Capsule",
		Label = "Crystal Egg",
		Odds = 0.05,
		Color = rgb(140, 24, 90),
		Capsule = "Crystal",
	},
} :: { Segment }

-- Segment id -> what that segment pays players who can't buy any capsule
-- (same place, odds and color on their wheel).
WheelConfig.Substitutes = {
	TripleLucky = {
		Index = 2,
		Id = "TripleLuckyCoins",
		Kind = "Coins",
		Label = "More Coins", -- its own name: segment 1 is "Coins" and pays less
		Odds = 0.12,
		Color = rgb(150, 70, 8),
		Seconds = 180,
		Min = 750,
	},
} :: { [string]: Segment }

WheelConfig.ById = {} :: { [string]: Segment }
for _, segment in WheelConfig.Segments do
	WheelConfig.ById[segment.Id] = segment
	local capsule = segment.Capsule
	assert(capsule == nil or CapsuleConfig.ById[capsule], "WheelConfig: unknown capsule")
	local boost = segment.Boost
	assert(boost == nil or BoostConfig.Kinds[boost], "WheelConfig: unknown boost")
end
for id, substitute in WheelConfig.Substitutes do
	local original = WheelConfig.ById[id]
	assert(original and original.Index == substitute.Index and original.Odds == substitute.Odds, "WheelConfig: bad substitute " .. id)
	WheelConfig.ById[substitute.Id] = substitute
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The 8 segments a player sees and spins (`noCapsules`: the player can't buy
-- any capsule, CapsuleConfig.allRestricted; then Substitutes apply).
function WheelConfig.segments(noCapsules: boolean?): { Segment }
	local list = {}
	for _, segment in WheelConfig.Segments do
		local substitute = if noCapsules then WheelConfig.Substitutes[segment.Id] else nil
		table.insert(list, substitute or segment)
	end
	return list
end

-- The segment odds for the wheel screen: { { Segment, Chance } } (sum 1).
function WheelConfig.odds(noCapsules: boolean?): { { Segment: Segment, Chance: number } }
	local list = {}
	for _, segment in WheelConfig.segments(noCapsules) do
		table.insert(list, { Segment = segment, Chance = segment.Odds })
	end
	return list
end

-- The segment for a roll in [0, 1).
function WheelConfig.pick(roll: number, noCapsules: boolean?): Segment
	local list = WheelConfig.segments(noCapsules)
	local acc = 0
	for _, segment in list do
		acc += segment.Odds
		if roll < acc then
			return segment
		end
	end
	return list[#list]
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

-- The bought spins a data.Wheel record holds (a whole number >= 0; junk = 0).
function WheelConfig.heldSpins(wheel: any): number
	local spins = if type(wheel) == "table" then wheel.Spins else nil
	if not finite(spins) or spins < 1 then
		return 0
	end
	return math.floor(spins)
end

-- The spins a player can spin now: the free one when it is ready, plus the
-- bought ones unless paid random items are restricted for them (SPIN (n)).
function WheelConfig.spinsNow(wheel: any, now: number, restricted: boolean): number
	local free = if WheelConfig.ready(if type(wheel) == "table" then wheel.NextSpinAt else nil, now) then 1 else 0
	return free + (if restricted then 0 else WheelConfig.heldSpins(wheel))
end

-- The BUY SPINS row for a spin count (1, 5, 10), nil for anything else.
function WheelConfig.packFor(count: any): { Count: number, Product: string }?
	for _, pack in WheelConfig.Packs do
		if pack.Count == count then
			return pack
		end
	end
	return nil
end

-- Coins a Coins segment pays at this podium income (0 for other segments).
function WheelConfig.coins(segment: Segment, incomePerSecond: number): number
	if segment.Kind ~= "Coins" then
		return 0
	end
	local income = if finite(incomePerSecond) and incomePerSecond > 0 then math.min(incomePerSecond, 1e27) else 0
	return math.max(segment.Min or 0, math.floor(income * (segment.Seconds or 0)))
end

---------------------------------------------------------------- the ore prize

-- The Income of the best ore in a data.Discovered record ({ [oreId] = true };
-- unknown ids and broken records count as nothing: 0).
function WheelConfig.bestIncome(discovered: any): number
	local best = 0
	if type(discovered) ~= "table" then
		return best
	end
	for oreId, found in discovered do
		local ore = if type(oreId) == "string" and found then OreData.ById[oreId] else nil
		-- (a SECRET ore found once never sets the prize: it is a jackpot, not the player's level)
		if ore and ore.Rarity ~= "Secret" and ore.Income > best then
			best = ore.Income
		end
	end
	return best
end

-- Exact odds of the ore prize for this player (see the header), in OreData
-- order (better last); sums to 1. Empty when no ore qualifies.
function WheelConfig.oreOdds(context: OreContext): { OreLine }
	local prize = WheelConfig.OrePrize
	local best = if finite(context.BestIncome) and context.BestIncome > 0 then context.BestIncome else 0
	local cap = math.max(prize.MinIncome, best * prize.IncomeMult)
	local seen: { [string]: boolean } = {}
	local candidates: { string } = {}
	-- never the VIP zones: a paid pass must not change a free random prize
	for _, zone in BoostConfig.minableZones(context.BlasterLevel, false) do
		for oreId, weight in zone.Ores do
			local ore = OreData.ById[oreId]
			if ore and weight > 0 and ore.Income <= cap and BoostConfig.isLuckyOre(oreId) and not seen[oreId] then
				seen[oreId] = true
				table.insert(candidates, oreId)
			end
		end
	end
	-- the best first (ties: OreData order)
	table.sort(candidates, function(a: string, b: string): boolean
		local ia, ib = OreData.ById[a].Income, OreData.ById[b].Income
		if ia ~= ib then
			return ia > ib
		end
		return a < b
	end)
	local weights: { [string]: number } = {}
	local total = 0
	for i = 1, math.min(prize.Picks, #candidates, #prize.Weights) do
		weights[candidates[i]] = prize.Weights[i]
		total += prize.Weights[i]
	end
	local list: { OreLine } = {}
	if total <= 0 then
		return list
	end
	for _, ore in OreData.List do
		local weight = weights[ore.Id]
		if weight then
			table.insert(list, { Ore = ore.Id, Chance = weight / total })
		end
	end
	return list
end

-- The ore prize for a roll in [0, 1) (nil: no ore qualifies, pay the Coins
-- segment's coins instead).
function WheelConfig.pickOre(roll: number, context: OreContext): string?
	local list = WheelConfig.oreOdds(context)
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

-- Coins instead of the ore when the pen is full: the prize's expected raw
-- value (what Tobin pays dirty, averaged over oreOdds), so the amount never
-- tells which ore it would have been. 0 when no ore qualifies.
function WheelConfig.oreFallbackCoins(context: OreContext): number
	local total = 0
	for _, line in WheelConfig.oreOdds(context) do
		total += line.Chance * ItemData.value("Raw", line.Ore)
	end
	return math.floor(total + 0.5)
end

-- Coins instead of a capsule when the golem inventory is full: FallbackShare
-- of its coin price at the player's blaster level (a Robux capsule counts as
-- a Crystal capsule). A share, so a full inventory is never the better deal.
function WheelConfig.capsuleFallbackCoins(capsuleId: string, blasterLevel: any): number
	local price = CapsuleConfig.price(capsuleId, 1, blasterLevel) or CapsuleConfig.price("Crystal", 1, blasterLevel) or 0
	return math.floor(price * WheelConfig.FallbackShare)
end

return WheelConfig
