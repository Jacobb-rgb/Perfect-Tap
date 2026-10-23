--[[
	Golem capsules (step 7): each holds a dormant golem core; opening one
	wakes a random golem (GolemConfig). Sold at the capsule stall in town
	(hook CapsuleStall, odds on its OddsBoard) and in the side menu.

	  Stone Capsule    coins, cheap         mostly Common golems
	  Crystal Capsule  coins, expensive     Uncommon..Mythic
	  Royal Capsule    Robux (placeholder)  Rare..Mythic, the best odds
	  Dragonforge      Robux, LIMITED       the Dragonforge set (Config/LimitedGolems):
	                                        only in the Robux shop's banner while
	                                        its edition runs; never at the stall

	- Exact odds per golem (each capsule's Odds sum to 1). Open 1, 3 or 10 at
	  once; x10 costs 10 x Price x TenDiscount (a small discount).
	- Coin prices grow with the player's blaster level (LevelScale, x1 at
	  levels 1-3 up to x1500 at level 10): income grows exponentially, so a
	  fixed price would be pocket change late in the game. The blaster level
	  never goes down and can't be gamed (income could: take the ores off the
	  podiums, buy, put them back), so no price here reads the income.
	- Triple Lucky (BoostConfig, data.Boosts.TripleLuckyUntil) on a capsule:
	  every golem whose rarity is at least the capsule's LuckyFrom (Stone:
	  Rare, Crystal: Epic, Royal: Legendary) becomes exactly 3 times as likely;
	  the other golems share what is left, keeping their proportions (they are
	  all scaled by (1 - 3 L) / (1 - L), L = the lucky golems' total chance).
	  The odds still sum to 1. odds(capsuleId, true) gives the new numbers for
	  the UI, which must show them before a Triple Lucky purchase.
	- Roblox rules: the Royal capsule (Robux) is a paid random item. Coin
	  capsules are one too exactly when coins can be bought with Robux
	  (MonetizationConfig.coinsBuyable(): the coin packs, off until the owner
	  decides). isPaidRandom() says which; those are hidden / disabled where
	  PolicyService ArePaidRandomItemsRestricted is true (src/server/Policy.luau).
	  Odds are shown before every open, paid or not. Capsules given free by the
	  daily wheel are not paid and may always be opened.
	- Limited capsules (Limited = a LimitedGolems set): shop-only (Stall
	  lists the others: the capsule panel's tabs and the stall's board), Robux
	  packs of 1 / 3 / 10 / 50 (MaxCount), prompted only while their edition
	  is on sale (LimitedGolems.onSale; "Ended" after), granted always.
	CapsuleAction ("Open", { Capsule, Count }) opens coin capsules; Royal and
	limited capsules are Robux products (the server answers with
	PurchasePrompt).
	A rate-limited "Open" is dropped without an answer (Net): the client keeps
	its own ClientCooldown between opens and gives the buttons back after
	ResultTimeout seconds. That does NOT mean nothing was spent: a slow
	handler (a first policy fetch, server lag) may still open the capsules,
	so a CapsuleResult that arrives later is still shown (the opening plays),
	and the coins and golems on screen always come from the State push.
	Royal capsules: the odds a receipt uses are the ones the player saw at
	the prompt (MonetizationConfig, the step 8 contract).
]]

local GolemConfig = require(script.Parent.GolemConfig)
local MonetizationConfig = require(script.Parent.MonetizationConfig)
local Rarity = require(script.Parent.Rarity)

export type Capsule = {
	Id: string,
	Name: string,
	Currency: "Coins" | "Robux",
	Price: number?, -- coins for one at blaster levels 1-3 (Coins capsules; x LevelScale)
	Products: { [number]: string }?, -- count -> MonetizationConfig key (Robux capsules)
	LuckyFrom: string, -- Triple Lucky triples every golem at least this rare
	Odds: { [string]: number }, -- golem id -> chance (sum 1)
	Color: Color3, -- shell color
	Glow: Color3, -- ring / core glow
	Description: string,
	Limited: string?, -- a LIMITED EDITION's capsule: the LimitedGolems set id (shop-only, see the header)
	Shell: Color3?, -- the top shell's color (default: Color lightened)
	Podium: boolean?, -- opens only beside its own podium (CapsuleService.nearPodium; the SKY EGG on Sky Haven)
	AnnounceFrom: string?, -- golems this rare are announced to the server (default CapsuleService.AnnounceFrom)
}

export type OddsLine = { Golem: string, Chance: number }

local CapsuleConfig = {}

CapsuleConfig.Counts = { 1, 3, 10 }
CapsuleConfig.MaxCount = 50 -- the biggest pack (a limited capsule x50; Robux only)
-- A Robux pack is prompted while the inventory has room for this many of it
-- (all of a small one): paid golems may pass InventoryCap up to MaxSaved and
-- the rest wait in the pending-golem credit (CapsuleService), so a x50 pack
-- doesn't need 50 free places.
CapsuleConfig.PromptRoom = 10
CapsuleConfig.TenDiscount = 0.9 -- x10 pays 9 capsules' price
CapsuleConfig.TripleLucky = 3
CapsuleConfig.ClientCooldown = 1 -- seconds between two "Open" requests from the client
CapsuleConfig.ResultTimeout = 5 -- seconds the client waits for CapsuleResult

-- Coin price multiplier per blaster level (index = level 1..10; see the header).
CapsuleConfig.LevelScale = { 1, 1, 1, 2, 5, 15, 50, 150, 500, 1500 }

-- CapsuleAction / ActionResult reason codes -> text for the player
CapsuleConfig.Reasons = {
	BadCapsule = "That capsule isn't sold here",
	BadCount = "Open 1, 3 or 10 at once",
	NoCoins = "Not enough coins",
	InventoryFull = "Your golem inventory is full: delete some golems first",
	Restricted = "Capsules aren't available where you play",
	Robux = "Robux purchase", -- the server answers with PurchasePrompt instead
	Ended = "This limited edition has ended", -- a limited capsule after its edition (LimitedGolems)
	Podium = "Climb to SKY HAVEN to open it", -- a podium-only egg opened away from its podium
} :: { [string]: string }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

CapsuleConfig.List = {
	{
		Id = "Stone",
		Name = "Stone Egg",
		Currency = "Coins",
		Price = 2500,
		LuckyFrom = "Rare",
		Color = rgb(150, 140, 130),
		Glow = rgb(255, 170, 80),
		Description = "A rough stone shell. Mostly common golems sleep inside.",
		Odds = {
			PebbleGolem = 0.25,
			CopperTinker = 0.22,
			CoalChomper = 0.18,
			TinTumbler = 0.15,
			QuartzSprite = 0.06,
			SilverSquire = 0.05,
			AmethystAcolyte = 0.03,
			JadeGardener = 0.025,
			EmberImp = 0.015,
			CobaltDiver = 0.01,
			GildedPorter = 0.007,
			RoseKnight = 0.002,
			SapphireSage = 0.0007,
			DiamondDuke = 0.0003,
		},
	},
	{
		Id = "Crystal",
		Name = "Crystal Egg",
		Currency = "Coins",
		Price = 750000,
		LuckyFrom = "Epic",
		Color = rgb(120, 200, 255),
		Glow = rgb(170, 120, 255),
		Description = "A glowing crystal shell. No common golems, and a whisper of Mythic.",
		Odds = {
			QuartzSprite = 0.2,
			SilverSquire = 0.17,
			AmethystAcolyte = 0.14,
			JadeGardener = 0.12,
			EmberImp = 0.1,
			CobaltDiver = 0.08,
			GildedPorter = 0.06,
			RoseKnight = 0.05,
			SapphireSage = 0.035,
			DiamondDuke = 0.025,
			StormTitan = 0.012,
			MoonstoneOracle = 0.007,
			CelestialSovereign = 0.0007,
			HeartstoneColossus = 0.0003,
		},
	},
	{
		Id = "Royal",
		Name = "Royal Egg",
		Currency = "Robux",
		Products = { [1] = "RoyalCapsule1", [3] = "RoyalCapsule3", [5] = "RoyalCapsule5", [10] = "RoyalCapsule10" }, -- (x5: the Store)
		LuckyFrom = "Legendary",
		Color = rgb(255, 196, 60),
		Glow = rgb(255, 90, 120),
		Description = "Sealed with the Ember Kings' crest. Rare golems or better, every time.",
		Odds = {
			EmberImp = 0.22,
			CobaltDiver = 0.18,
			GildedPorter = 0.15,
			RoseKnight = 0.14,
			SapphireSage = 0.11,
			DiamondDuke = 0.09,
			StormTitan = 0.05,
			MoonstoneOracle = 0.04,
			CelestialSovereign = 0.012,
			HeartstoneColossus = 0.008,
		},
	},
	{
		-- the SKY EGG on the Sky Haven island (islands chat + owner 2026-10-22):
		-- three golems only, better than Crystal, still below the Robux eggs
		Id = "Sky",
		Name = "Sky Egg",
		Currency = "Coins",
		Price = 3000000,
		LuckyFrom = "Legendary",
		-- (the parkour's prize: opened only at the top of SKY HAVEN; false = anywhere)
		Podium = true,
		AnnounceFrom = "Mythic", -- (a x10 would toast a Legendary 82 % of the time)
		Color = rgb(44, 48, 66),
		Glow = rgb(110, 210, 255),
		Description = "A storm knight's egg from Sky Haven. Only three golems sleep inside.",
		Odds = {
			SkySprite = 0.84,
			StormSentinel = 0.14,
			AetherKing = 0.02,
		},
	},
	{
		Id = "Dragonforge",
		Name = "Dragonforge Shard",
		Currency = "Robux",
		Products = {
			[1] = "DragonforgeCapsule1",
			[3] = "DragonforgeCapsule3",
			[10] = "DragonforgeCapsule10",
			[50] = "DragonforgeCapsule50",
		},
		Limited = "Dragonforge",
		LuckyFrom = "Legendary",
		Color = rgb(56, 30, 36),
		Shell = rgb(232, 120, 40),
		Glow = rgb(255, 120, 30),
		Description = "A dragon egg from the heart of the volcano. LIMITED EDITION: the Dragonforge golems, only while the edition runs.",
		Odds = {
			CinderWhelp = 0.34,
			EmberHatchling = 0.28,
			ScaleKnight = 0.2,
			Flamewing = 0.12,
			MagmaWyvern = 0.05,
			DragonKing = 0.01,
		},
	},
} :: { Capsule }

CapsuleConfig.ById = {} :: { [string]: Capsule }
-- The capsules of the stall and the capsule panel: every one but the limited editions'.
CapsuleConfig.Stall = {} :: { Capsule }
for _, capsule in CapsuleConfig.List do
	CapsuleConfig.ById[capsule.Id] = capsule
	if capsule.Limited == nil then
		table.insert(CapsuleConfig.Stall, capsule)
	else
		assert(capsule.Currency == "Robux" and capsule.Products, "CapsuleConfig: a limited capsule is a Robux one " .. capsule.Id)
	end
	for golemId in capsule.Odds do
		assert(GolemConfig.ById[golemId], `CapsuleConfig: unknown golem {golemId} in {capsule.Id}`)
	end
	assert(Rarity.ById[capsule.LuckyFrom], "CapsuleConfig: bad LuckyFrom " .. capsule.LuckyFrom)
	if capsule.Products then
		for _, key in capsule.Products do
			assert(MonetizationConfig.Products[key], "CapsuleConfig: unknown product " .. key)
		end
	end
end

-- Is opening this capsule a paid random item? Robux capsules always; coin
-- capsules only while coins can be bought with Robux (see the header).
-- Unknown capsule: true (the strict answer).
function CapsuleConfig.isPaidRandom(capsuleId: string): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule or capsule.Currency == "Robux" then
		return true
	end
	return MonetizationConfig.coinsBuyable()
end

-- Can't a player whose paid-random policy is `restricted` buy ANY capsule?
-- (Then Triple Lucky is worth nothing to them: WheelConfig swaps that prize.)
function CapsuleConfig.allRestricted(restricted: boolean): boolean
	if not restricted then
		return false
	end
	for _, capsule in CapsuleConfig.List do
		if not CapsuleConfig.isPaidRandom(capsule.Id) then
			return false
		end
	end
	return true
end

-- The coin price multiplier for a blaster level (broken = level 1; above the
-- table = its last entry).
function CapsuleConfig.levelScale(blasterLevel: any): number
	local scale = CapsuleConfig.LevelScale
	local level = if type(blasterLevel) == "number" and blasterLevel == blasterLevel then math.floor(blasterLevel) else 1
	return scale[math.clamp(level, 1, #scale)]
end

function CapsuleConfig.validCount(count: any): boolean
	return table.find(CapsuleConfig.Counts, count) ~= nil
end

-- Coins for opening `count` (1, 3 or 10) coin capsules at a blaster level
-- (nil = level 1): Price x LevelScale per capsule, x10 with TenDiscount.
-- nil for Robux capsules or a bad count.
function CapsuleConfig.price(capsuleId: string, count: any, blasterLevel: any?): number?
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule or capsule.Currency ~= "Coins" or not CapsuleConfig.validCount(count) then
		return nil
	end
	local each = (capsule.Price :: number) * CapsuleConfig.levelScale(blasterLevel)
	if count == 10 then
		return math.floor(each * 10 * CapsuleConfig.TenDiscount + 0.5)
	end
	return each * count
end

-- The MonetizationConfig key for buying `count` Robux capsules (nil otherwise).
function CapsuleConfig.product(capsuleId: string, count: any): string?
	local capsule = CapsuleConfig.ById[capsuleId]
	local products = if capsule then capsule.Products else nil
	if not products or type(count) ~= "number" then
		return nil
	end
	return products[count]
end

-- Exact odds of every golem in a capsule, in GolemConfig order (rarer last),
-- with Triple Lucky applied when `tripleLucky` (see the header). Each list
-- sums to 1. Unknown capsule: an empty list.
function CapsuleConfig.odds(capsuleId: string, tripleLucky: boolean): { OddsLine }
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule then
		return {}
	end
	local from = Rarity.ById[capsule.LuckyFrom].Order
	local lucky = 0
	for golemId, chance in capsule.Odds do
		if GolemConfig.order(golemId) >= from then
			lucky += chance
		end
	end
	-- lucky golems x3 (never past the whole: 3 L <= 1 for every capsule here)
	local mult = if tripleLucky and lucky > 0 then math.min(CapsuleConfig.TripleLucky, 1 / lucky) else 1
	local rest = if lucky < 1 then (1 - lucky * mult) / (1 - lucky) else 0
	local list: { OddsLine } = {}
	for _, golem in GolemConfig.List do
		local chance = capsule.Odds[golem.Id]
		if chance then
			local boosted = if GolemConfig.order(golem.Id) >= from then chance * mult else chance * rest
			table.insert(list, { Golem = golem.Id, Chance = boosted })
		end
	end
	return list
end

-- Chance per rarity (for the summary row on the odds board).
function CapsuleConfig.rarityOdds(capsuleId: string, tripleLucky: boolean): { [string]: number }
	local out: { [string]: number } = {}
	for _, line in CapsuleConfig.odds(capsuleId, tripleLucky) do
		local rarity = GolemConfig.ById[line.Golem].Rarity
		out[rarity] = (out[rarity] or 0) + line.Chance
	end
	return out
end

-- The golem for a roll in [0, 1) (odds order; the last one when rounding leaves a gap).
function CapsuleConfig.roll(capsuleId: string, tripleLucky: boolean, roll: number): string?
	local list = CapsuleConfig.odds(capsuleId, tripleLucky)
	local acc = 0
	for _, line in list do
		acc += line.Chance
		if roll < acc then
			return line.Golem
		end
	end
	local last = list[#list]
	return if last then last.Golem else nil
end

return CapsuleConfig
