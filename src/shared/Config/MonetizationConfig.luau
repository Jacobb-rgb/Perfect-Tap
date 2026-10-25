--[[
	Every Robux game pass and developer product in one place (design v2,
	docs/DESIGN_V2_NOTES.md). The ids are placeholders (0) until the owner
	creates the passes/products on the Creator Dashboard and pastes the ids
	here (docs/COMPLIANCE.md 2.6).

	Rules for every caller:
	- A product whose Id is 0 is NOT live: show "Coming soon", never prompt a
	  purchase and never grant it (MonetizationConfig.isLive(id) is false).
	- Prompts and grants go only through MarketplaceService with these ids.
	  Step 8 (MonetizationService) holds the one ProcessReceipt and the game
	  pass checks. A feature that is asked to sell a Robux item answers the
	  client with PurchasePrompt { Product, Status }
	  (MonetizationConfig.promptStatus), and the one receipts gate
	  (src/server/Receipts.luau) turns "Prompt" into "ComingSoon" for every
	  product and pass, live id or not, until MonetizationService.start
	  calls Receipts.setReady(true): only when every live id has a handler
	  (MonetizationService.unhandled() is empty; ReceiptsAttribute tells the
	  clients).
	- PaidRandom = true: buying it gives a random result (Royal and limited capsules, the
	  Spin & Win wheel's bought spins) or
	  changes the odds of one (the Triple / Hexa Lucky packs, the Starbreaker
	  enchant's pass: ore luck and artifact chance), so it is hidden/disabled
	  for players whose PolicyService ArePaidRandomItemsRestricted is true
	  (src/server/Policy.luau), and the exact odds (for odds boosters: the
	  odds now and the NEW odds, BoostConfig.preview / CapsuleConfig.odds)
	  are shown in numbers before buying.
	- Coin packs (CoinsSmall .. CoinsMega): on since the owner's go
	  (2026-10-20), CoinPacksEnabled = true. With coins buyable for Robux,
	  every coin capsule and coin boost is a paid random item too
	  (CapsuleConfig.isPaidRandom, BoostConfig.isPaidRandom read
	  coinsBuyable(): hidden where restricted). Turning it off again: the
	  packs are never offered (promptStatus "Unknown") and those rules relax.
	- One-time things are game passes, never developer products: the two
	  Mythic enchants (EnchantHeartfire / EnchantStarbreaker) are passes, so
	  Roblox itself never sells them twice. Step 8 grants a pass's Enchant /
	  Perks when the player joins owning it (UserOwnsGamePassAsync) and on
	  PromptGamePassPurchaseFinished.
	- Prices (Robux) are for display; the Dashboard price is the real one:
	  keep them equal.
	- Grant names the MonetizationService handler that gives an entry
	  (register(grant, fn) for products, registerPass(grant, ...) for
	  passes; every entry has one, registered in its owner's init()):
	    "Perks"      passes: the entry's Perks list as player attributes
	                 (MonetizationService itself, src/server/Perks.luau)
	    "Enchant"    passes: the Mythic enchant, forever (EnchantService)
	    "Hoverboard" passes: the BoardId board (HoverboardService)
	    "RebirthWeapon" passes: the WeaponId star blaster (RebirthService;
	                 built from StarBlasterData, so the prices stay equal)
	    "Capsule"    products: Count golems of Capsule (CapsuleService)
	    "Boost"      products: Seconds of Boost, uncapped (BoostService)
	    "CoinPack"   products: coinPackAmount coins, only while
	                 CoinPacksEnabled (PodiumService: the income)
	    "BlasterLevel" products: the player's next blaster level, when it is
	                 within the entry's MinLevel..MaxLevel band (VaultService;
	                 a bought level never pays Rebirth stars)
	    "ServerBoost" products: Seconds of the ServerBoost effect for everyone
	                 on the server (ServerBoostService; not saved: it ends
	                 with the server)
	    "WheelSpins" products: Spins bought spins of the Spin & Win wheel,
	                 held in data.Wheel.Spins (WheelService). The prompt
	                 answers "Full" past WheelConfig.MaxSpins held; a receipt
	                 is never refused and always credits all of them
	    "StarterPack" products: the Starter Pack (StarterPackService): its
	                 Golem (paid, past the cap like a Royal capsule's), its
	                 coins (coinPackAmount: CoinSeconds of income, at least
	                 MinCoins) and its PodiumSkin + title, recorded in
	                 data.StarterPack.BoughtAt. Once = true: prompted only
	                 while not bought ("Owned" after) and in the offer window
	                 (StarterPackService.offerOpen); a second receipt of the
	                 same account (two prompts open at once) is still
	                 granted in full, never dropped
	  Every grant is recorded in data.Purchases[PurchaseId] = os.time() and
	  data.PurchaseLog[PurchaseId] = { Product = Key, At = os.time() }.

	Contract for step 8 (ProcessReceipt, developer products):
	- A receipt is never stranded: it is granted (on the server that holds the
	  session lock, saved first, then PurchaseGranted), or, when the item truly
	  can't be given, compensated with something of equal worth (never
	  coins while coinsBuyable() is false), and the
	  receipt is still answered PurchaseGranted. Paid golems are saved with
	  Paid = true and may pass the inventory cap (GolemConfig.add(golems,
	  kind, true, true): overCap up to MaxSaved, paid); paid boost time
	  is added uncapped (BoostConfig.extend capped = false) and kept on
	  every later load (Migrations clips only junk past
	  BoostConfig.MaxSavedSeconds, a year ahead). Past MaxSaved the golems that
	  don't fit are NEVER paid out as coins (Robux -> coins would be a coin
	  pack: coinsBuyable() and docs/COMPLIANCE.md 2.6a would have to change):
	  they wait in the save as a pending-golem credit (data.Golems.Pending:
	  the rolled kinds, Paid) and wake into the inventory as soon as there is
	  room (CapsuleService.grantProduct returns how many didn't fit).
	- Receipts that arrive "off policy" (a paid random product for a player
	  whose policy restricts it, a product whose id is 0 here, an unknown
	  product id) are still granted or compensated, never dropped, and logged
	  with the player id, product id and purchase id for review. A known
	  product is granted whatever the policy says. A receipt no entry matches
	  (id 0 here, unknown) or that its handler can't take yet (a coin pack
	  while CoinPacksEnabled is false, a golem credit past
	  GolemConfig.MaxPending) is answered NotProcessedYet: never
	  acknowledged without the item, so Roblox delivers it again and it is
	  granted once the id is pasted here / the handler can take it.
	- Clients can prompt any product themselves (exploiters, restricted
	  regions): the server never trusts that a prompt came from its own UI.
	- Royal capsules and Triple Lucky: the odds the player saw are the odds
	  they get. When the server answers "Prompted" for a Royal capsule it
	  stores { Product, TripleLucky = Bonuses.tripleLucky at that moment, At }
	  for the player (the latest prompt per product, kept PromptMemorySeconds);
	  ProcessReceipt opens the capsules with that stored TripleLucky state,
	  even if the boost has ended since (and with Triple Lucky when it runs
	  at the receipt: never worse odds than any card showed,
	  CapsuleService.grantProduct). With no stored prompt (a
	  purchase from the Store tab, another server, a rejoin) it uses the
	  state when the receipt is processed, and the capsule card always says
	  which odds a purchase uses ("Triple Lucky odds" / "normal odds").
	- A late result is still a result: the client shows a CapsuleResult /
	  WheelResult that arrives after its ResultTimeout (CapsuleConfig /
	  WheelConfig), and the State push always brings the saved truth.
]]

local OreData = require(script.Parent.OreData)
local StarBlasterData = require(script.Parent.StarBlasterData)
local WorldLayout = require(script.Parent.WorldLayout)

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
	Grant: string?, -- the MonetizationService handler that gives it (header: "Perks", "Capsule", ...)
	BoardId: string?, -- Grant "Hoverboard": the HoverboardData id it unlocks
	MinLevel: number?, -- Grant "BlasterLevel": the player's next blaster level must be
	MaxLevel: number?, -- within MinLevel..MaxLevel (the price band; VaultService)
	ServerBoost: string?, -- Grant "ServerBoost": the server-wide effect ("Luck")
	WeaponId: string?, -- Grant "RebirthWeapon": the StarBlasterData id it gives
	Spins: number?, -- Grant "WheelSpins": bought spins of the Spin & Win wheel (WheelService)
	Golem: string?, -- Grant "StarterPack": the GolemConfig kind it gives (one, fixed: not random)
	PodiumSkin: string?, -- Grant "StarterPack": the ArtifactConfig.PodiumSkins id it unlocks
	Once: boolean?, -- a developer product sold once per account ("Owned" after; StarterPackService)
}
-- (MonetizationService's name for a pass or product)
export type Entry = Product

local MonetizationConfig = {}

--[[
	The Glimmer Grotto's ore odds in numbers, from its node weights in
	WorldLayout (docs/COMPLIANCE.md 2.6 "Forge VIP and ore odds": a paid item
	that opens better odds says the odds before purchase). Built from the
	map data, so the Forgemaster's Pass text never goes stale.
]]
function MonetizationConfig.grottoOddsText(): string
	local zone = WorldLayout.ZoneById.Grotto
	if not zone then
		return ""
	end
	local total = 0
	local lines: { { Name: string, Weight: number, Order: number } } = {}
	for order, ore in OreData.List do
		local weight = zone.Ores[ore.Id]
		if type(weight) == "number" and weight > 0 then
			total += weight
			table.insert(lines, { Name = ore.Name, Weight = weight, Order = order })
		end
	end
	table.sort(lines, function(a, b)
		if a.Weight ~= b.Weight then
			return a.Weight > b.Weight
		end
		return a.Order < b.Order
	end)
	local parts: { string } = {}
	for _, line in lines do
		local pct = line.Weight / total * 100
		local text = if math.abs(pct - math.floor(pct + 0.5)) < 1e-9 then tostring(math.floor(pct + 0.5)) else string.format("%.1f", pct)
		table.insert(parts, `{text}% {line.Name}`)
	end
	return `Glimmer Grotto ore: {table.concat(parts, ", ")}.`
end

local LIST: { Product } = {
	---------------------------------------------------------------- game passes
	{
		Key = "BigPass",
		Grant = "Perks",
		Kind = "GamePass",
		Id = 0,
		Robux = 560,
		Name = "Forgemaster's Pass",
		Description = "Podiums 4 and 5, offline earnings for 12 hours, double carrying, the Glimmer Grotto and extra machine slots. "
			.. MonetizationConfig.grottoOddsText(),
		Perks = { "Podiums", "OfflineExtension", "StrongBack", "ForgeVip", "Workshop" },
	},
	{
		Key = "Podiums",
		Grant = "Perks",
		Kind = "GamePass",
		Id = 0,
		Robux = 100,
		Name = "Two More Podiums",
		Description = "Unlocks podiums 4 and 5 on your base.",
		Perks = { "Podiums" },
	},
	{
		Key = "OfflineExtension",
		Grant = "Perks",
		Kind = "GamePass",
		Id = 0,
		Robux = 99,
		Name = "Night Shift",
		Description = "Your podiums keep earning while you are away for up to 12 hours instead of 5.",
		Perks = { "OfflineExtension" },
	},
	{
		Key = "DoubleMoney",
		Grant = "Perks",
		Kind = "GamePass",
		Id = 0,
		Robux = 199,
		Name = "2x Money",
		Description = "Double coins forever: your podiums earn twice as much (offline too) and Tobin pays twice as much for everything you sell.",
		Perks = { "DoubleMoney" },
	},
	{
		Key = "TrainExpress",
		Grant = "Perks",
		Kind = "GamePass",
		Id = 0,
		Robux = 199,
		Name = "Express Train",
		Description = "Your ore train runs twice as fast and carries half as much again.",
		Perks = { "TrainExpress" },
	},
	-- the Robux hoverboard (HoverboardData): owned forever, so a pass. Owner 2026-10-25: the Neon
	-- Comet left and the Royal Phoenix became a coin board; the one Robux board is the Terra
	-- Forge Custom (no hoverboard pass id was ever made, so nobody owned the old two)
	{
		Key = "HoverboardCustom",
		Kind = "GamePass",
		Id = 0,
		Robux = 49,
		Name = "Terra Forge Custom Hoverboard",
		Description = "The fastest hoverboard, painted with Terra Forge doodles: speed 38, no carry slowdown, a rainbow trail.",
		Grant = "Hoverboard",
		BoardId = "TerraForgeCustom",
	},
	---------------------------------------------------------------- the Starter Pack
	-- (one per account, offered in the first hour of play: StarterPackService.
	-- Nothing random in it, so it is not a paid random item: no Triple Lucky,
	-- no capsule. Its coins are "coins for Robux": offered only while
	-- coinsBuyable(), like the coin packs.)
	{
		Key = "StarterPack",
		Grant = "StarterPack",
		Kind = "Product",
		Id = 0,
		Robux = 99,
		Name = "Starter Pack",
		Description = 'Once per player: the Rare golem Gilded Porter (+10% podium income), 20 minutes of your podium income in coins (at least 15,000) and the Pioneer podium skin with the title "Pioneer".',
		Golem = "GildedPorter",
		CoinSeconds = 1200,
		MinCoins = 15000,
		PodiumSkin = "Pioneer",
		Once = true,
	},
	---------------------------------------------------------------- golem capsules
	{
		Key = "RoyalCapsule1",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 49,
		Name = "Royal Egg",
		Description = "Wakes 1 golem from a Royal Capsule (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 1,
	},
	{
		Key = "RoyalCapsule3",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 139,
		Name = "Royal Egg x3",
		Description = "Wakes 3 golems from Royal Capsules (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 3,
	},
	{
		Key = "RoyalCapsule5",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 229,
		Name = "Royal Egg x5",
		Description = "Wakes 5 golems from Royal Capsules (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 5,
	},
	{
		Key = "RoyalCapsule10",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 429,
		Name = "Royal Egg x10",
		Description = "Wakes 10 golems from Royal Capsules (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Royal",
		Count = 10,
	},
	-- the LIMITED EDITION capsule (Config/LimitedGolems: sold only while its
	-- edition runs; a receipt is always granted)
	{
		Key = "DragonforgeCapsule1",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 99,
		Name = "Dragonforge Shard",
		Description = "Wakes 1 golem of the limited Dragonforge edition (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Dragonforge",
		Count = 1,
	},
	{
		Key = "DragonforgeCapsule3",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 249,
		Name = "Dragonforge Shard x3",
		Description = "Wakes 3 golems of the limited Dragonforge edition (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Dragonforge",
		Count = 3,
	},
	{
		Key = "DragonforgeCapsule10",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 799,
		Name = "Dragonforge Shard x10",
		Description = "Wakes 10 golems of the limited Dragonforge edition (odds shown before buying).",
		PaidRandom = true,
		Capsule = "Dragonforge",
		Count = 10,
	},
	{
		Key = "DragonforgeCapsule50",
		Grant = "Capsule",
		Kind = "Product",
		Id = 0,
		Robux = 3499,
		Name = "Dragonforge Shard x50",
		Description = "Wakes 50 golems of the limited Dragonforge edition (odds shown before buying). Golems that don't fit wake as soon as there is room.",
		PaidRandom = true,
		Capsule = "Dragonforge",
		Count = 50,
	},
	---------------------------------------------------------------- luck boosts
	{
		Key = "TripleLucky15",
		Grant = "Boost",
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
		Grant = "Boost",
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
		Grant = "Boost",
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
		Grant = "Boost",
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
		Grant = "Enchant",
		Kind = "GamePass",
		Id = 0,
		Robux = 20,
		Name = "Heartfire Enchant",
		Description = "The Mythic Heartfire enchant for your blaster, yours forever.",
		Enchant = "Heartfire",
	},
	{
		Key = "EnchantStarbreaker",
		Grant = "Enchant",
		Kind = "GamePass",
		Id = 0,
		Robux = 20,
		Name = "Starbreaker Enchant",
		Description = "The Mythic Starbreaker enchant for your blaster, yours forever: +75% ore luck, +50% artifact chance. Ore luck bonuses add up to at most +150% (new odds shown before buying).",
		PaidRandom = true,
		Enchant = "Starbreaker",
	},
	---------------------------------------------------------------- coin packs
	-- five tiers like popular simulators' stores (owner 2026-10-20); the
	-- bigger the pack, the more coins per Robux
	{
		Key = "CoinsSmall",
		Grant = "CoinPack",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 19,
		Name = "Handful of Coins",
		Description = "5 minutes of your podium income (at least 2,500 coins).",
		CoinSeconds = 300,
		MinCoins = 2500,
	},
	{
		Key = "CoinsMedium",
		Grant = "CoinPack",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 49,
		Name = "Pouch of Coins",
		Description = "15 minutes of your podium income (at least 10,000 coins).",
		CoinSeconds = 900,
		MinCoins = 10000,
	},
	{
		Key = "CoinsLarge",
		Grant = "CoinPack",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 99,
		Name = "Stack of Coins",
		Description = "40 minutes of your podium income (at least 30,000 coins).",
		CoinSeconds = 2400,
		MinCoins = 30000,
	},
	{
		Key = "CoinsHuge",
		Grant = "CoinPack",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 249,
		Name = "Sack of Coins",
		Description = "2 hours of your podium income (at least 100,000 coins).",
		CoinSeconds = 7200,
		MinCoins = 100000,
	},
	{
		Key = "CoinsMega",
		Grant = "CoinPack",
		Kind = "Product",
		CoinPack = true,
		Id = 0,
		Robux = 499,
		Name = "Chest of Coins",
		Description = "5 hours of your podium income (at least 300,000 coins).",
		CoinSeconds = 18000,
		MinCoins = 300000,
	},
	---------------------------------------------------------------- the blaster, by price band
	-- (the next level for Robux, like the Vault sells it for coins; the
	-- Store shows only the band of the player's next level)
	{
		Key = "BlasterNextA",
		Grant = "BlasterLevel",
		Kind = "Product",
		Id = 0,
		Robux = 49,
		Name = "Next Blaster",
		Description = "Your next blaster level (LV 2-4) right now. Every later rebirth starts your blaster 1 level higher (up to LV 9).",
		MinLevel = 2,
		MaxLevel = 4,
	},
	{
		Key = "BlasterNextB",
		Grant = "BlasterLevel",
		Kind = "Product",
		Id = 0,
		Robux = 99,
		Name = "Next Blaster",
		Description = "Your next blaster level (LV 5-7) right now. Every later rebirth starts your blaster 1 level higher (up to LV 9).",
		MinLevel = 5,
		MaxLevel = 7,
	},
	{
		Key = "BlasterNextC",
		Grant = "BlasterLevel",
		Kind = "Product",
		Id = 0,
		Robux = 199,
		Name = "Next Blaster",
		Description = "Your next blaster level (LV 8-9) right now. Every later rebirth starts your blaster 1 level higher (up to LV 9).",
		MinLevel = 8,
		MaxLevel = 9,
	},
	{
		Key = "BlasterNextD",
		Grant = "BlasterLevel",
		Kind = "Product",
		Id = 0,
		Robux = 399,
		Name = "Next Blaster",
		Description = "The top blaster (LV 10) right now. Every later rebirth starts your blaster 1 level higher (up to LV 9).",
		MinLevel = 10,
		MaxLevel = 10,
	},
	---------------------------------------------------------------- server luck
	{
		Key = "ServerLuck15",
		Grant = "ServerBoost",
		Kind = "Product",
		PaidRandom = true, -- better ore odds
		Id = 0,
		Robux = 49,
		Name = "Server Luck",
		Description = "x2 ore luck for everyone on this server while it runs: +15 minutes each time. With Hexa Lucky on, the bigger one counts.",
		ServerBoost = "Luck",
		Seconds = 900,
	},
	---------------------------------------------------------------- Spin & Win wheel spins
	-- (owner 2026-10-20: "yes, sell spins for Robux"; the left BUY SPINS panel
	-- of the wheel screen). A bought spin turns the same wheel as the free
	-- daily spin, so it is a paid random item: every segment's exact odds
	-- are on the wheel's face and in Details before buying, it is hidden and
	-- refused where paid random items are restricted (WheelService), and the
	-- free daily spin stays free. Bought spins are held in data.Wheel.Spins
	-- and never expire; the free spin is used first.
	{
		Key = "WheelSpins1",
		Grant = "WheelSpins",
		Kind = "Product",
		Id = 0,
		Robux = 25,
		Name = "1 Wheel Spin",
		Description = "1 spin of the Spin & Win wheel (odds shown before buying).",
		PaidRandom = true,
		Spins = 1,
	},
	{
		Key = "WheelSpins5",
		Grant = "WheelSpins",
		Kind = "Product",
		Id = 0,
		Robux = 99,
		Name = "5 Wheel Spins",
		Description = "5 spins of the Spin & Win wheel (odds shown before buying).",
		PaidRandom = true,
		Spins = 5,
	},
	{
		Key = "WheelSpins10",
		Grant = "WheelSpins",
		Kind = "Product",
		Id = 0,
		Robux = 179,
		Name = "10 Wheel Spins",
		Description = "10 spins of the Spin & Win wheel (odds shown before buying).",
		PaidRandom = true,
		Spins = 10,
	},
}
-- the five STAR blasters (StarBlasterData): one-time passes, kept through every rebirth;
-- they open at their rebirth count (a pass bought earlier waits). Keys StarComet ... StarSingularity.
for _, star in StarBlasterData.List do
	table.insert(LIST, {
		Key = "Star" .. star.Id,
		Kind = "GamePass",
		Id = 0,
		Robux = star.Robux,
		Name = star.Name,
		Description = `The {star.Name} star blaster: x{star.Mult} the power of your blaster level, kept forever. Opens at rebirth {star.Unlock}.`,
		Grant = "RebirthWeapon",
		WeaponId = star.Id,
	})
end

-- Coin packs: on since the owner's go (2026-10-20, "money for Robux").
-- It decides the paid-random-items rules (see the header).
MonetizationConfig.CoinPacksDefault = true -- what ships (specs switch CoinPacksEnabled to test both)
MonetizationConfig.CoinPacksEnabled = MonetizationConfig.CoinPacksDefault

-- Seconds a "Prompted" Royal capsule remembers the Triple Lucky state the
-- player saw (step 8 contract above).
MonetizationConfig.PromptMemorySeconds = 15 * 60
-- ReplicatedStorage attribute: true once step 8 grants receipts and passes
-- (src/server/Receipts.luau, Receipts.setReady). Until then no product is
-- prompted, live id or not, and the cards show "Coming soon".
MonetizationConfig.ReceiptsAttribute = "ReceiptsReady"

-- The 2x Money pass (perk "DoubleMoney"): podium income and sell value are
-- multiplied by this AFTER every capped bonus (StatConfig IncomePct cap 2,
-- SellPct cap 3), so the pass always doubles what the player earns
-- (Bonuses.moneyMult: EconomyService.addIncomeFactor and Bonuses.sellMult).
MonetizationConfig.MoneyPassPerk = "DoubleMoney"
MonetizationConfig.MoneyPassMult = 2

-- The Starter Pack offer (StarterPackService, StarterPackController): open
-- for the first Seconds of play (data.Stats.PlaySeconds) while not bought;
-- the small popup shows once per session after PopupAfter seconds of play.
MonetizationConfig.StarterOffer = { Seconds = 3600, PopupAfter = 300 }

MonetizationConfig.List = LIST
MonetizationConfig.Products = {} :: { [string]: Product }
for _, product in LIST do
	MonetizationConfig.Products[product.Key] = product
end
-- (the same map under MonetizationService's name)
MonetizationConfig.Entries = MonetizationConfig.Products

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
	return type(id) == "number" and id == id and id > 0 and id == math.floor(id) and id < 2 ^ 53
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

-- May `key` be prompted? (= keyLive: a real id; prompts also wait for the receipts gate)
function MonetizationConfig.canPrompt(key: any): boolean
	return MonetizationConfig.keyLive(key)
end

-- The entry with this id (of this kind, when given), or nil (0, junk and unknown ids never match).
function MonetizationConfig.byId(id: any, kind: Kind?): Product?
	if not MonetizationConfig.isLive(id) or id ~= math.floor(id) then
		return nil
	end
	for _, product in MonetizationConfig.Products do
		if product.Id == id and (kind == nil or product.Kind == kind) then
			return product
		end
	end
	return nil
end

-- Every entry of a kind, sorted by key (a stable order for checks and tests).
function MonetizationConfig.list(kind: Kind): { Product }
	local out: { Product } = {}
	for _, product in MonetizationConfig.Products do
		if product.Kind == kind then
			table.insert(out, product)
		end
	end
	table.sort(out, function(a: Product, b: Product): boolean
		return a.Key < b.Key
	end)
	return out
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
	if not product or ((product.CoinPack or product.CoinSeconds) and not MonetizationConfig.coinsBuyable()) then
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
