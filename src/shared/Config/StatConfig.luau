--[[
	Bonus stats (steps 6-7): the names every bonus source uses (gear,
	enchants, golems, boosts, artifact collections) and how they add up.
	src/server/Bonuses.luau sums the sources with combine(); the client uses
	describe() for card texts. A partial stat table is { [statName] = value }.

	Kind "Add": values are summed (default 0). Kind "Mult": multiplied (default 1).
	  DamagePct        + share of blaster damage (0.1 = +10 %)
	  OverchargePct    + share of damage while a rock is in its last third
	  ReachStuds       + blaster range (studs)
	  OreLuckPct       + share of the weight of Rare and rarer ores in rock rolls
	  OreLuckMult      x the weight of Rare and rarer ores (Hexa Lucky)
	  CapsuleLuckMult  x Triple Lucky on golem capsules (CapsuleConfig.odds)
	  TwinDropChance   chance that a dropped ore drops a twin chunk too
	  ArtifactPct      + share of the artifact chance of every rock
	  SellPct          + share of what Tobin pays
	  IncomePct        + share of podium income (Bonuses adds the capped total
	                   to EconomyService once, see Bonuses.incomePct)
	  GolemBondPct     + share of every equipped golem's bonus
	  WalkSpeed        walk speed in studs/s (Boots give the base, Swift adds)
	  WalkSpeedPct     + share of walk speed
	  MagnetRadius     studs in which your own loose items fly to you
	  PickupRange      studs you can grab an item from
	  ThrowMult        x throw power
	  CarryCapacity    items you can carry (the StrongBack perk doubles it)
	  LampRange        head lamp range (studs, 0 = no lamp)
	  LampBrightness   head lamp brightness

	Caps (Max, applied to each total by combine): they are real limits the
	best gear can reach, so the numbers on the cards are what the game
	applies (the UI shows the capped totals from State.Bonuses). Ore luck has
	one more cap on the product: oreLuck() = (1 + OreLuckPct) x OreLuckMult,
	at most MaxOreLuck (x5), so the odds on a Hexa Lucky card match the rolls.
	Today's highest sums (3 equipped golems with Golem Bond III + Golemworks):
	DamagePct ~3.0, OreLuckPct ~2.45 (capped 1.5), IncomePct ~2.1, SellPct ~1.3,
	WalkSpeedPct ~0.24, ArtifactPct 1.5, OverchargePct 1.3.
]]

export type StatKind = "Add" | "Mult"
export type StatFormat = "Percent" | "Studs" | "Times" | "Number" | "Speed"
export type Stat = {
	Id: string,
	Kind: StatKind,
	Label: string, -- "blaster damage"
	Format: StatFormat,
	Max: number?, -- the total never goes past this (nil = no cap)
}

local StatConfig = {}

StatConfig.List = {
	{ Id = "DamagePct", Kind = "Add", Label = "blaster damage", Format = "Percent", Max = 3 },
	{ Id = "OverchargePct", Kind = "Add", Label = "damage on a cracked rock's last third", Format = "Percent", Max = 3 },
	{ Id = "ReachStuds", Kind = "Add", Label = "blaster range", Format = "Studs", Max = 12 },
	{ Id = "OreLuckPct", Kind = "Add", Label = "rare ore luck", Format = "Percent", Max = 1.5 },
	{ Id = "OreLuckMult", Kind = "Mult", Label = "rare ore luck", Format = "Times", Max = 2.5 },
	{ Id = "CapsuleLuckMult", Kind = "Mult", Label = "capsule luck", Format = "Times", Max = 3 },
	{ Id = "TwinDropChance", Kind = "Add", Label = "chance of a twin chunk", Format = "Percent", Max = 0.5 },
	{ Id = "ArtifactPct", Kind = "Add", Label = "artifact chance", Format = "Percent", Max = 3 },
	{ Id = "SellPct", Kind = "Add", Label = "sell value", Format = "Percent", Max = 3 },
	{ Id = "IncomePct", Kind = "Add", Label = "podium income", Format = "Percent", Max = 3 },
	{ Id = "GolemBondPct", Kind = "Add", Label = "golem bonuses", Format = "Percent", Max = 1 },
	{ Id = "WalkSpeed", Kind = "Add", Label = "walk speed", Format = "Speed", Max = 40 },
	{ Id = "WalkSpeedPct", Kind = "Add", Label = "walk speed", Format = "Percent", Max = 0.5 },
	{ Id = "MagnetRadius", Kind = "Add", Label = "magnet radius", Format = "Studs", Max = 60 },
	{ Id = "PickupRange", Kind = "Add", Label = "pickup range", Format = "Studs", Max = 40 },
	{ Id = "ThrowMult", Kind = "Mult", Label = "throw power", Format = "Times", Max = 3 },
	{ Id = "CarryCapacity", Kind = "Add", Label = "carry capacity", Format = "Number", Max = 50 },
	{ Id = "LampRange", Kind = "Add", Label = "lamp range", Format = "Studs", Max = 120 },
	{ Id = "LampBrightness", Kind = "Add", Label = "lamp brightness", Format = "Number", Max = 10 },
} :: { Stat }

-- The highest total rare ore luck (the product, see the header).
StatConfig.MaxOreLuck = 5

StatConfig.ById = {} :: { [string]: Stat }
for _, stat in StatConfig.List do
	StatConfig.ById[stat.Id] = stat
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The neutral totals: every Add stat 0, every Mult stat 1.
function StatConfig.empty(): { [string]: number }
	local out: { [string]: number } = {}
	for _, stat in StatConfig.List do
		out[stat.Id] = if stat.Kind == "Mult" then 1 else 0
	end
	return out
end

-- Adds one partial stat table into `totals` (unknown names and values that
-- aren't finite are skipped; Mult values must be > 0). Returns `totals`.
function StatConfig.add(totals: { [string]: number }, partial: any): { [string]: number }
	if type(partial) ~= "table" then
		return totals
	end
	for id, value in partial do
		local stat = if type(id) == "string" then StatConfig.ById[id] else nil
		if stat and finite(value) then
			if stat.Kind == "Mult" then
				if value > 0 then
					totals[id] = (totals[id] or 1) * value
				end
			else
				totals[id] = (totals[id] or 0) + value
			end
		end
	end
	return totals
end

-- The multiplier on Rare and rarer ore weights from the two luck totals:
-- (1 + pct) x mult, between 1 (no luck) and MaxOreLuck. Broken values count
-- as no luck. Bonuses.oreLuck and the boost cards both use this.
function StatConfig.oreLuck(pct: any, mult: any): number
	local p = if finite(pct) and pct > 0 then pct else 0
	local m = if finite(mult) and mult > 0 then mult else 1
	return math.clamp((1 + p) * m, 1, StatConfig.MaxOreLuck)
end

-- Sums partial stat tables and clamps every total to its Max.
function StatConfig.combine(partials: { any }): { [string]: number }
	local totals = StatConfig.empty()
	for _, partial in partials do
		StatConfig.add(totals, partial)
	end
	for _, stat in StatConfig.List do
		local max = stat.Max
		if max then
			totals[stat.Id] = math.min(totals[stat.Id], max)
		end
	end
	return totals
end

local function trimNumber(value: number): string
	local text = string.format("%.2f", value)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return text
end

-- Card text for one stat value: "+10% blaster damage", "+4 studs blaster range",
-- "x2.5 rare ore luck", "+2 walk speed".
function StatConfig.describe(statId: string, value: number): string
	local stat = StatConfig.ById[statId]
	if not stat then
		return ""
	end
	if stat.Format == "Percent" then
		return `+{trimNumber(value * 100)}% {stat.Label}`
	elseif stat.Format == "Times" then
		return `x{trimNumber(value)} {stat.Label}`
	elseif stat.Format == "Studs" then
		return `+{trimNumber(value)} studs {stat.Label}`
	end
	return `+{trimNumber(value)} {stat.Label}`
end

return StatConfig
