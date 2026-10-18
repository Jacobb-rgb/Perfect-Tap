--[[
	Every Robux game pass and developer product in one place (design v2,
	docs/DESIGN_V2_NOTES.md). The ids are placeholders (0) until the owner
	creates the passes/products on the Creator Dashboard and pastes the ids
	here (docs/COMPLIANCE.md 2.6).

	Rules for every caller:
	- A product whose Id is 0 is NOT live: show "Coming soon", never prompt a
	  purchase and never grant it (MonetizationConfig.isLive(id) is false).
	- Prompts and grants go only through MarketplaceService with these ids.
	  The real ProcessReceipt / game pass checks arrive in step 8
	  (MonetizationService). Until then a feature that is asked to sell a Robux
	  item answers the client with PurchasePrompt { Product, Status }
	  (MonetizationConfig.promptStatus).
	- PaidRandom = true: buying it gives a random result (Royal capsules) or
	  changes the odds of one (the Triple / Hexa Lucky packs, the Starbreaker
	  enchant's pass: ore luck and artifact chance), so it is hidden/disabled
	  for players whose PolicyService ArePaidRandomItemsRestricted is true
	  (src/server/Policy.luau), and the exact odds (for odds boosters: the
	  odds now and the NEW odds, BoostConfig.preview / CapsuleConfig.odds)
	  are shown in numbers before buying.
	- Coin packs (CoinsSmall/Medium/Large) wait for the owner: the design notes
	  say "Money comes only from podiums", so CoinPacksEnabled is false. While
	  it is false the packs are never offered (promptStatus "Unknown") and
	  coins can't be bought with Robux, so coin capsules and coin boosts are
	  NOT paid random items (CapsuleConfig.isPaidRandom, BoostConfig.isPaidRandom
	  read coinsBuyable()). Turning it on makes every coin capsule and coin
	  boost a paid random item at once (hidden where restricted).
	- One-time things are game passes, never developer products: the two
	  Mythic enchants (EnchantHeartfire / EnchantStarbreaker) are passes, so
	  Roblox itself never sells them twice. Step 8 grants a pass's Enchant /
	  Perks when the player joins owning it (UserOwnsGamePassAsync) and on
	  PromptGamePassPurchaseFinished.
	- Prices (Robux) are for display; the Dashboard price is the real one:
	  keep them equal.

	Contract for step 8 (ProcessReceipt, developer products):
	- A receipt is never stranded: it is granted (on the server that holds the
	  session lock, saved first, then PurchaseGranted), or, when the item truly
	  can't be given, compensated with something of equal worth, and the
	  receipt is still answered PurchaseGranted. Paid golems are saved with
	  Paid = true and may pass the inventory cap (GolemConfig.add(golems,
	  kind, true, true): overCap up to MaxSaved, paid); paid boost time
	  is added uncapped (BoostConfig.extend capped = false). Past MaxSaved a
	  capsule is refunded as coins (CapsuleConfig.price of a Crystal capsule
	  at the player's blaster level per golem).
	- Receipts that arrive "off policy" (a paid random product for a player
	  whose policy restricts it, a product whose id is 0 here, an unknown
	  product id) are still granted or compensated, never dropped, and logged
	  with the player id, product id and purchase id for review.
	- Clients can prompt any product themselves (exploiters, restricted
	  regions): the server never trusts that a prompt came from its own UI.
	- Royal capsules and Triple Lucky: the odds the player saw are the odds
	  they get. When the server answers "Prompted" for a Royal capsule it
	  stores { Product, TripleLucky = Bonuses.tripleLucky at that moment, At }
	  for the player (the latest prompt per product, kept PromptMemorySeconds);
	  ProcessReceipt opens the capsules with that stored TripleLucky state,
	  even if the boost has started or ended since. With no stored prompt (a
	  purchase from the Store tab, another server, a rejoin) it uses the
	  state when the receipt is processed, and the capsule card always says
	  which odds a purchase uses ("Triple Lucky odds" / "normal odds").
	- A late result is still a result: the client shows a CapsuleResult /
	  WheelResult that arrives after its ResultTimeout (CapsuleConfig /
	  WheelConfig), and the State push always brings the saved truth.
]]

export type Kind = "GamePass" | "Product"

export type Product = {
	Key: string, -- the key in Products (PurchasePrompt.Product)
	Kind: Kind,
	Id: number, -- 0 = placeholder (not live)
	Robux: number, -- display price
	Name: string,
	Description: string,
	Perks: { string }?, -- game passes: Perks ids the pass grants (src/server/Perks.luau)
	PaidRandom: boolean?, -- random result / changes odds: PolicyService rules
	CoinPack: boolean?, -- coins for Robux (off while CoinPacksEnabled is false)
	-- what a product gives (read by the step 8 receipt handler and the UI)
	Capsule: string?, -- CapsuleConfig id
	Count: number?, -- capsules opened
	Boost: string?, -- BoostConfig kind
	Seconds: number?, -- boost seconds
	Enchant: string?, -- EnchantConfig id (a game pass that grants the enchant)
	CoinSeconds: number?, -- coin packs: seconds of the player's podium income...
	MinCoins: number?, -- ...but at least this many coins
}

local MonetizationConfig = {}

local LIST: { Product } = {
	---------------------------------------------------------------- game passes
	{
		Key = "BigPass",
		Kind = "GamePass",
		Id = 0,
		Robux = 560,
		Name = "Forgemaster's Pass",
		Description = "Podiums 3 and 4, offline earnings for 12 hours, double carrying, the Glimmer Grotto and extra machine slots.",
		Perks = { "Podiums", "OfflineExtension", "StrongBack", "ForgeVip", "Workshop" },
	},
	{
		Key = "Podiums",
		Kind = "GamePass",
		Id = 0,
		Robux = 100,
		Name = "Two More Podiums",
		Description = "Unlocks podiums 3 and 4 on your base.",
		Perks = { "Podiums" },
	},
	{
		Key = "OfflineExtension",
		Kind = "GamePass",
		Id = 0,
		Robux = 99,
		Name = "Night Shift",
		Description = "Your podiums keep earning while you are away for up to 12 hours instead of 5.",
		Perks = { "OfflineExtension" },
	},
	{
		Key = "TrainExpress",
		Kind = "GamePass",
		Id = 0,
		Robux = 199,
		Name = "Express Train",
		Description = "Your ore train runs twice as fast and carries half as much again.",
		Perks = { "TrainExpress" },
	},
	---------------------------------------------------------------- golem capsules
	{
		Key = "RoyalCapsule1",
		Kind = "Product",
		Id = 0,
		Robux = 49,
		Name = "Royal Capsule",
		Description = "Wakes 1 golem from a Royal Capsule (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 1,
	},
	{
		Key = "RoyalCapsule3",
		Kind = "Product",
		Id = 0,
		Robux = 139,
		Name = "Royal Capsule x3",
		Description = "Wakes 3 golems from Royal Capsules (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 3,
	},
	{
		Key = "RoyalCapsule10",
		Kind = "Product",
		Id = 0,
		Robux = 429,
		Name = "Royal Capsule x10",
		Description = "Wakes 10 golems from Royal Capsules (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 10,
	},
	---------------------------------------------------------------- luck boosts
	{
		Key = "TripleLucky15",
		Kind = "Product",
		Id = 0,
		Robux = 39,
		Name = "Triple Lucky (15 min)",
		Description = "Golem capsules: the rarest golems are 3 times as likely for 15 minutes (new odds shown before buying).",
		PaidRandom = true,
		Boost = "TripleLucky",
		Seconds = 900,
	},
	{
		Key = "TripleLucky60",
		Kind = "Product",
		Id = 0,
		Robux = 129,
		Name = "Triple Lucky (1 hour)",
		Description = "Golem capsules: the rarest golems are 3 times as likely for 1 hour (new odds shown before buying).",
		PaidRandom = true,
		Boost = "TripleLucky",
		Seconds = 3600,
	},
	{
		Key = "HexaLucky15",
		Kind = "Product",
		Id = 0,
		Robux = 39,
		Name = "Hexa Lucky (15 min)",
		Description = "Mining: ore luck x2.5 for 15 minutes. Rare ores weigh x2.5, Epic x4, Legendary x6.3, Mythic x9.9 (new odds shown before buying).",
		PaidRandom = true,
		Boost = "HexaLucky",
		Seconds = 900,
	},
	{
		Key = "HexaLucky60",
		Kind = "Product",
		Id = 0,
		Robux = 129,
		Name = "Hexa Lucky (1 hour)",
		Description = "Mining: ore luck x2.5 for 1 hour. Rare ores weigh x2.5, Epic x4, Legendary x6.3, Mythic x9.9 (new odds shown before buying).",
		PaidRandom = true,
		Boost = "HexaLucky",
		Seconds = 3600,
	},
	---------------------------------------------------------------- the two rarest enchants (one-time: game passes)
	{
		Key = "EnchantHeartfire",
		Kind = "GamePass",
		Id = 0,
		Robux = 20,
		Name = "Heartfire Enchant",
		Description = "The Mythic Heartfire enchant for your blaster, yours forever.",
		Enchant = "Heartfire",
	},
	{
		Key = "EnchantStarbreaker",
		Kind = "GamePass",
		Id = 0,
		Robux = 20,
		Name = "Starbreaker Enchant",
		Description = "The Mythic Starbreaker enchant for your blaster, yours forever: +75% ore luck, +50% artifact chance (new odds shown before buying).",
		PaidRandom = true,
		Enchant = "Starbreaker",
	},
	---------------------------------------------------------------- coin packs
	{
		Key = "CoinsSmall",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 49,
		Name = "Pouch of Coins",
		Description = "10 minutes of your podium income (at least 5,000 coins).",
		CoinSeconds = 600,
		MinCoins = 5000,
	},
	{
		Key = "CoinsMedium",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 149,
		Name = "Chest of Coins",
		Description = "40 minutes of your podium income (at least 25,000 coins).",
		CoinSeconds = 2400,
		MinCoins = 25000,
	},
	{
		Key = "CoinsLarge",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 399,
		Name = "Vault of Coins",
		Description = "2 hours of your podium income (at least 100,000 coins).",
		CoinSeconds = 7200,
		MinCoins = 100000,
	},
}

-- Coin packs wait for the owner's decision (see the header). Keep false
-- until the owner confirms them; it decides the paid-random-items rules.
MonetizationConfig.CoinPacksEnabled = false

-- Seconds a "Prompted" Royal capsule remembers the Triple Lucky state the
-- player saw (step 8 contract above).
MonetizationConfig.PromptMemorySeconds = 15 * 60

MonetizationConfig.List = LIST
MonetizationConfig.Products = {} :: { [string]: Product }
for _, product in LIST do
	MonetizationConfig.Products[product.Key] = product
end

-- PurchasePrompt.Status codes -> text for the player
MonetizationConfig.StatusText = {
	ComingSoon = "Coming soon!",
	Restricted = "This isn't available where you play.",
	Prompted = "",
	Owned = "You already own this.",
	Full = "You can't hold more of this right now.",
	Unknown = "That isn't sold here.",
} :: { [string]: string }

-- A real (non-placeholder) pass/product id.
function MonetizationConfig.isLive(id: any): boolean
	return type(id) == "number" and id == id and id ~= 0
end

function MonetizationConfig.get(key: any): Product?
	return if type(key) == "string" then MonetizationConfig.Products[key] else nil
end

-- Can coins be bought with Robux? (coin packs on). When true, everything
-- random that costs coins is a paid random item too.
function MonetizationConfig.coinsBuyable(): boolean
	return MonetizationConfig.CoinPacksEnabled == true
end

-- Is the product behind `key` live?
function MonetizationConfig.keyLive(key: any): boolean
	local product = MonetizationConfig.get(key)
	return product ~= nil and MonetizationConfig.isLive(product.Id)
end

-- What to answer when a player asks to buy `key` (PurchasePrompt.Status):
-- "Unknown" (no such product, or a coin pack while coin packs are off),
-- "Restricted" (paid random item and the player's policy restricts them;
-- also when the policy is not known yet), "Owned" (a pass they own, or a
-- Mythic enchant they already have), "Full" (the feature can't take it now:
-- boost at its cap, golem inventory full), "ComingSoon" (placeholder id),
-- else "Prompt" (the caller prompts MarketplaceService - PromptGamePassPurchase
-- for a GamePass, PromptProductPurchase for a Product - and sends "Prompted").
function MonetizationConfig.promptStatus(key: any, restricted: boolean, owned: boolean?, full: boolean?): string
	local product = MonetizationConfig.get(key)
	if not product or (product.CoinPack and not MonetizationConfig.coinsBuyable()) then
		return "Unknown"
	end
	if product.PaidRandom and restricted then
		return "Restricted"
	end
	if owned then
		return "Owned"
	end
	if full then
		return "Full"
	end
	if not MonetizationConfig.isLive(product.Id) then
		return "ComingSoon"
	end
	return "Prompt"
end

-- Coins a coin pack gives at this podium income (nil for other products).
function MonetizationConfig.coinPackAmount(key: any, incomePerSecond: number): number?
	local product = MonetizationConfig.get(key)
	if not product or not product.CoinSeconds then
		return nil
	end
	local income = if type(incomePerSecond) == "number"
			and incomePerSecond == incomePerSecond
			and incomePerSecond > 0
		then math.min(incomePerSecond, 1e27)
		else 0
	return math.max(product.MinCoins or 0, math.floor(income * product.CoinSeconds))
end

return MonetizationConfig
