--[[
	Gear (steps 6-7): four gear lines bought with coins at the Gear shop
	(the SHOP stall in town, hook ShopCounter). Each line has levels 0..5
	(0 = what everyone starts with) and an effect value per level; prices
	grow about x6 per level (the owner wants exponential costs).

	  Boots       walk speed (studs/s)              16 -> 18, 20, 22, 24, 26
	  HelmetLamp  head lamp range (studs) for dark   0 -> 18, 26, 34, 44, 56
	              caves, plus its brightness          0 -> 1.2 ... 2.6
	  (The Ore Backpack line left on 2026-10-24: the backpacks are their own
	  shop now, BackpackData / BackpackService; Migrations turned its level
	  into a pack, Version 9.)
	  Gloves      pickup range (studs)               11 -> 13, 15, 17, 20, 24
	              and throw power (x)               1.0 -> 1.08 ... 1.4
	  Magnet      radius (studs) in which your own    0 -> 14, 18, 24, 30, 38
	              mined ore flies into your hands while they have room
	              (not on or near bases, not what you dropped:
	              ItemService.Magnet). Every level reaches beyond the
	              grab reach without Gloves (11 + 2 slack), and level N
	              beyond Gloves level N, so each one fetches ore you
	              couldn't grab from where you stand; at the top it
	              reaches about as far as the blasters shoot (22-40).

	Walk speed: Boots level 0 is 16 studs/s, Roblox's default, on purpose
	(Boots I, 500 coins, gives the 18 everyone walked at before; saves from
	before the Gear shop get Boots I for free: Migrations). CarryService
	is the ONLY writer of Humanoid.WalkSpeed: Bonuses.walkSpeed (Boots, Swift,
	WalkSpeed golems); the backpack never slows you down (nothing is carried
	in the hands any more, owner 2026-10-24; CarrySlowPerItem / CarrySlowMax
	stay for HoverboardData.walkSpeed's count of 0). Anything that changes walk speed calls
	CarryService.refreshWalkSpeed(player) (a data change does it too).

	Head lamp budget (mobile, dark caves, 8 players): LampBudget. Only the
	LOCAL player's own lamp is a real light (one SpotLight, Shadows off,
	range LampRange, at most LampBudget.MaxLights); other players' lamps
	are a small Neon part on their helmet and cast no light. The lamp is
	built on each client from State.Bonuses (own) and the player attribute
	LampAttribute (others: the lamp level, set by the gear package).

	Saved as data.Gear = { Boots, HelmetLamp, Gloves, Magnet }
	(whole levels 0..MaxLevel; Migrations keeps higher levels and other
	lines a newer server may sell, every reader here clamps to MaxLevel). GearAction ("Buy", { Line, Level }) buys
	exactly the next level: Level must be the one the card shows (quote,
	"Stale" otherwise), so a double tap never buys two levels.
	The effects reach the game through src/server/Bonuses.luau (stats below).
]]

export type GearLine = {
	Id: string, -- the data.Gear key and the GearAction Line
	Name: string,
	Description: string,
	Primary: string, -- the stat value() returns by default
	Stats: { [string]: { number } }, -- per level, index 1 = level 0
	Prices: { number }, -- coins for levels 1..MaxLevel (index = level bought)
	Unit: string, -- how the primary value reads in the UI
	Icon: string, -- UI icon key
}

--[[
	What one gear line gives this player right now and at the next level,
	with EVERY bonus counted (Magnetism enchant, WalkSpeed golems, Swift,
	Strong Back...), as the server computes it (GearService.preview): the
	Gear shop's cards show these instead of the bare gear table. Main value:
	walk speed (Boots), lamp range (HelmetLamp), pickup
	range (Gloves), magnet radius (Magnet); Extra: lamp brightness, throw
	power. Next / ExtraNext are nil at the top level. A card uses the
	numbers only while its level is `Level`.
]]
export type LinePreview = {
	Level: number,
	Now: number,
	Next: number?,
	ExtraNow: number?,
	ExtraNext: number?,
}
export type Preview = { [string]: LinePreview }

local GearConfig = {}

GearConfig.MaxLevel = 5
-- studs from a ShopCounter's surface the server accepts a buy (like the Tech shop)
GearConfig.Range = 30
GearConfig.Tag = "ShopCounter"
-- carrying slows you down a little (see the header)
GearConfig.CarrySlowPerItem = 0.5
GearConfig.CarrySlowMax = 3
GearConfig.MinWalkSpeed = 10
-- head lamps (see the header)
GearConfig.LampBudget = {
	MaxLights = 1, -- real lights per client: the local player's lamp only
	Shadows = false, -- the lamp light never casts shadows
	OthersNeon = true, -- other players' lamps: a Neon part, no light
}
GearConfig.LampAttribute = "LampLevel" -- player attribute: HelmetLamp level (0 = none)

-- GearAction / ActionResult reason codes -> text for the player
GearConfig.Reasons = {
	BadItem = "That isn't sold here",
	Max = "Already at the top level",
	Stale = "The card was out of date, try again",
	NoCoins = "Not enough coins",
	TooFar = "Go to the SHOP stall to buy gear",
} :: { [string]: string }

GearConfig.Lines = {
	{
		Id = "Boots",
		Name = "Miner's Boots",
		Description = "Walk faster everywhere.",
		Primary = "WalkSpeed",
		Stats = { WalkSpeed = { 16, 18, 20, 22, 24, 26 } },
		Prices = { 500, 3000, 18000, 110000, 650000 },
		Unit = "walk speed",
		Icon = "Boots",
	},
	{
		Id = "HelmetLamp",
		Name = "Helmet Lamp",
		Description = "A head lamp that lights up dark caves.",
		Primary = "LampRange",
		Stats = {
			LampRange = { 0, 18, 26, 34, 44, 56 },
			LampBrightness = { 0, 1.2, 1.5, 1.8, 2.2, 2.6 },
		},
		Prices = { 400, 2400, 15000, 90000, 540000 },
		Unit = "studs of light",
		Icon = "Helmet",
	},
	{
		Id = "Gloves",
		Name = "Grip Gloves",
		Description = "Grab ore from further away and throw it harder.",
		Primary = "PickupRange",
		Stats = {
			PickupRange = { 11, 13, 15, 17, 20, 24 },
			ThrowMult = { 1, 1.08, 1.16, 1.24, 1.32, 1.4 },
		},
		Prices = { 600, 3600, 22000, 130000, 800000 },
		Unit = "studs reach",
		Icon = "Gloves",
	},
	{
		Id = "Magnet",
		Name = "Ore Magnet",
		-- (ItemService: into your hands while they have room; off bases, never what you dropped or threw)
		Description = "Mined ore flies into your hands if there's room. Not on bases.",
		Primary = "MagnetRadius",
		Stats = { MagnetRadius = { 0, 14, 18, 24, 30, 38 } },
		Prices = { 1500, 9000, 55000, 330000, 2000000 },
		Unit = "studs pull",
		Icon = "Magnet",
	},
} :: { GearLine }

GearConfig.ById = {} :: { [string]: GearLine }
GearConfig.LineIds = {} :: { string } -- in shop order
for _, line in GearConfig.Lines do
	GearConfig.ById[line.Id] = line
	table.insert(GearConfig.LineIds, line.Id)
end

-- A whole level 0..MaxLevel (broken values count as 0).
function GearConfig.clampLevel(level: any): number
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	return math.clamp(n, 0, GearConfig.MaxLevel)
end

-- The saved level of a line in a data.Gear record (any shape: broken = 0).
function GearConfig.level(gear: any, lineId: string): number
	return GearConfig.clampLevel(if type(gear) == "table" then gear[lineId] else nil)
end

-- The effect value of a line at a level (the line's Primary stat unless
-- `stat` names another one). Unknown line or stat: 0.
function GearConfig.value(lineId: string, level: any, stat: string?): number
	local line = GearConfig.ById[lineId]
	if not line then
		return 0
	end
	local values = line.Stats[stat or line.Primary]
	if not values then
		return 0
	end
	return values[GearConfig.clampLevel(level) + 1]
end

-- Price of the level after `level` (nil at the top level or for an unknown line).
function GearConfig.nextPrice(lineId: string, level: any): number?
	local line = GearConfig.ById[lineId]
	if not line then
		return nil
	end
	return line.Prices[GearConfig.clampLevel(level) + 1]
end

-- The server's check of a GearAction "Buy": the price of the next level of
-- `lineId` for this save, when `level` (from the client: the level being
-- bought, as the card shows it) is exactly current + 1.
-- nil + "BadItem" | "Max" | "Stale" (GearConfig.Reasons).
function GearConfig.quote(gear: any, lineId: any, level: any): (number?, string?)
	if type(lineId) ~= "string" or not GearConfig.ById[lineId] then
		return nil, "BadItem"
	end
	local current = GearConfig.level(gear, lineId)
	if current >= GearConfig.MaxLevel then
		return nil, "Max"
	end
	if level ~= current + 1 then
		return nil, "Stale"
	end
	return GearConfig.nextPrice(lineId, current), nil
end

-- What a data.Gear record gives (Bonuses stats, see src/server/Bonuses.luau).
-- Absolute values: WalkSpeed, PickupRange, MagnetRadius,
-- LampRange and LampBrightness include the level-0 base; ThrowMult is a
-- multiplier. A missing record counts as all levels 0.
function GearConfig.stats(gear: any): { [string]: number }
	local out: { [string]: number } = {}
	for _, line in GearConfig.Lines do
		local level = GearConfig.level(gear, line.Id)
		for stat, values in line.Stats do
			out[stat] = values[level + 1]
		end
	end
	return out
end

return GearConfig
