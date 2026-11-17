--[[
	The Robux Shop's tabs and cards (shop v3, owner 2026-11-11: the "WOW"
	concept docs/art/shop_v3_concept/shop_wow.html, pictures in
	obrazky/novy_obchod_wow_2026-11-11): six tabs, each its own colour world
	(UI/ShopFx.Themes) and its own page of bright cards. Names, descriptions
	and prices come from MonetizationConfig; this file only says where each
	card sits and how it looks. Every word on a card is backed by the
	configs (no made-up offers: "BEST VALUE!" is only shown where the price
	per item really is the lowest, UI/StoreView.bestValue).

	A card sits on a tab (Section) in a Row (1, 2); the cards of a row share
	its width by their Span (default 1). A tab's page may open with a banner
	(Section.Banner: "Limited" = the limited golem edition, LimitedGolems;
	"Royal" = the Royal Egg's golems and odds). Looks:
	  Bundle     the Forgemaster's Pass: the crown, its lines, a gold price
	  Starter    the Starter Pack: its golem, coins and podium skin in slots
	  Coins      a coin pack: the coins at the player's income now, a price
	  Pass       a game pass: title, picture, short line, price (OWNED after)
	  Blaster    the next blaster level (the band of the player's level)
	  Star       a STAR blaster: the live gun, its power, "Opens at rebirth N"
	  Egg        Royal eggs x1 / x3 / x5 / x10 (odds first)
	  ServerLuck x2 ore luck for the whole server
	  Wheel      Spin & Win spins (Options: 1 / 5 / 10)
	  Luck       Triple / Hexa Lucky (Options: 15 min / 1 hour)
	  Enchant    a Mythic enchant's game pass
	  MoneyWide  the 2x Money pass as a wide band (the Cash tab)
	A card with several Keys shows the first that fits the player (the
	blaster: the price band of the player's next level). A card with Options
	has a buy button per option (each a MonetizationConfig key).

	Pictures: Model names a 3D model shown live in the game (cash_* from
	CashBuilder, capsule_<Id> / golem_<Kind> from GolemBuilder, train, the
	hoverboards, item_<Ore>, star_<Id>); Icon is its preview picture; Sheet
	names the shop icon sheet's picture (IconAssets.Shop) shown instead once
	the sheet is uploaded.
]]

local MonetizationConfig = require(script.Parent.MonetizationConfig)
local StarBlasterData = require(script.Parent.StarBlasterData)

export type CardSpec = {
	Id: string, -- the card's name in the view
	Keys: { string }, -- MonetizationConfig keys (the first that fits shows)
	Look: string, -- see the header
	Paint: string, -- UI/ShopFx.Cards name
	Icon: string, -- the preview picture of its Model (tools/preview/icons: the same model rendered)
	Model: string?, -- a live 3D model picture (see the header)
	Sheet: string?, -- the shop icon sheet's picture (IconAssets.Shop), once uploaded
	PictureScale: number?, -- Pass: a wide picture (the hoverboard) this much bigger
	Section: string, -- its tab
	Row: number,
	Span: number?, -- share of the row's width (default 1)
	Title: string?, -- instead of the product's Name
	Lines: { string }?, -- Bundle / Starter: what is inside
	LineIcons: { string }?, -- Bundle: a sheet picture before each line
	Big: string?, -- the big line ("x3", "LV +1")
	Note: string?, -- a line under the price (the blaster's rebirth rule)
	Short: string?, -- a short line on the card (the odds panel / product text has the rest)
	Odds: boolean?, -- tapping shows the odds panel first (paid random products always do)
	Star: string?, -- Star: the StarBlasterData id
	GlowColor: Color3?, -- Star: the card painted from the blaster's light
	Options: { string }?, -- several buy buttons (MonetizationConfig keys)
	Count: number?, -- Egg: how many eggs
	Gold: boolean?, -- a gold price button
}

export type Section = {
	Id: string,
	Title: string,
	Tab: string, -- the tab's word
	TabIcon: string, -- the tab's sheet picture (IconAssets.Shop)
	TabModel: string?, -- its live 3D picture until the sheet is uploaded (PictureModels)
	Banner: string?, -- "Limited" | "Royal": the page opens with it
	BannerHeight: number?, -- design units
	RowHeights: { number }, -- design units per row
}

local StoreConfig = {}

StoreConfig.Title = "Shop"

StoreConfig.Sections = {
	{
		Id = "Featured",
		Title = "FEATURED",
		Tab = "Featured",
		TabIcon = "star",
		TabModel = "pass_crown",
		Banner = "Limited",
		BannerHeight = 306,
		RowHeights = { 214 },
	},
	{
		Id = "Golems",
		Title = "GOLEMS",
		Tab = "Golems",
		TabIcon = "egg",
		TabModel = "capsule_Royal",
		Banner = "Royal",
		BannerHeight = 292,
		RowHeights = { 226 },
	},
	{
		Id = "Blasters",
		Title = "BLASTERS",
		Tab = "Blasters",
		TabIcon = "bolt_cyan",
		TabModel = "blaster",
		RowHeights = { 258, 258 },
	},
	{
		Id = "Passes",
		Title = "PASSES",
		Tab = "Passes",
		TabIcon = "ticket",
		TabModel = "podium",
		RowHeights = { 334, 170 },
	},
	{
		Id = "Boosts",
		Title = "BOOSTS",
		Tab = "Boosts",
		TabIcon = "clover",
		TabModel = "clover",
		RowHeights = { 258, 260 },
	},
	{
		Id = "Cash",
		Title = "CASH",
		Tab = "Cash",
		TabIcon = "cash",
		TabModel = "cash_stack",
		RowHeights = { 370, 140 },
	},
} :: { Section }

local function card(spec: CardSpec): CardSpec
	return spec
end

-- the Forgemaster's Pass's lines (its Perks: Podiums, OfflineExtension, StrongBack, ForgeVip, Workshop)
-- (owner 2026-11-17: the Glimmer Grotto is a VIP cave on every plot now, World/PlotCave)
local BIG_PASS_LINES = { "Podiums 4 and 5", "50% income while away, 12 h", "Double backpack space", "Plot VIP cave + machine slots" }
local BIG_PASS_ICONS = { "star", "moon", "backpack", "gem" }

StoreConfig.Cards = {
	---------------------------------------------------------------- FEATURED
	card({
		Id = "BigPass",
		Keys = { "BigPass" },
		Look = "Bundle",
		Paint = "Royal",
		Icon = "pass_crown",
		Model = "pass_crown",
		Sheet = "crown",
		Section = "Featured",
		Row = 1,
		Span = 1.75,
		Title = "Forgemaster's Pass",
		Odds = true, -- it opens the Glimmer Grotto: its ore odds show before the buy (COMPLIANCE "Forge VIP and ore odds")
		Lines = BIG_PASS_LINES,
		LineIcons = BIG_PASS_ICONS,
		Gold = true,
	}),
	-- the Starter Pack (one per player, in the first hour of play: StarterPackService;
	-- StoreController hides it once bought or when the offer is over)
	card({
		Id = "StarterPack",
		Keys = { "StarterPack" },
		Look = "Starter",
		Paint = "Pink",
		Icon = "golem_GildedPorter",
		Model = "golem_GildedPorter",
		Section = "Featured",
		Row = 1,
		Title = "Starter Pack",
		Lines = { "Rare golem Gilded Porter", "20 min of income in coins", "Pioneer podium skin + title" },
	}),
	---------------------------------------------------------------- GOLEMS (after the Royal Egg banner)
	card({
		Id = "Royal1",
		Keys = { "RoyalCapsule1" },
		Title = "Royal Egg",
		Look = "Egg",
		Paint = "Purple",
		Icon = "capsule_Royal",
		Model = "capsule_Royal",
		Section = "Golems",
		Row = 1,
		Count = 1,
		Big = "x1",
	}),
	card({
		Id = "Royal3",
		Keys = { "RoyalCapsule3" },
		Title = "Royal Egg",
		Look = "Egg",
		Paint = "Purple",
		Icon = "capsule_Royal",
		Model = "capsule_Royal",
		Section = "Golems",
		Row = 1,
		Count = 3,
		Big = "x3",
	}),
	card({
		Id = "Royal5",
		Keys = { "RoyalCapsule5" },
		Title = "Royal Egg",
		Look = "Egg",
		Paint = "Pink",
		Icon = "capsule_Royal",
		Model = "capsule_Royal",
		Section = "Golems",
		Row = 1,
		Count = 5,
		Big = "x5",
	}),
	card({
		Id = "Royal10",
		Keys = { "RoyalCapsule10" },
		Title = "Royal Egg",
		Look = "Egg",
		Paint = "Red",
		Icon = "capsule_Royal",
		Model = "capsule_Royal",
		Section = "Golems",
		Row = 1,
		Count = 10,
		Big = "x10",
	}),
	---------------------------------------------------------------- BLASTERS (the STAR blasters are added below)
	card({
		Id = "Blaster",
		Keys = { "BlasterNextA", "BlasterNextB", "BlasterNextC", "BlasterNextD" },
		Look = "Blaster",
		Paint = "Red",
		Icon = "blaster",
		Model = "blaster",
		Sheet = "blaster",
		Section = "Blasters",
		Row = 1,
		Span = 1.25,
		Title = "Next Blaster",
		Short = "Your next blaster level, right now",
		Big = "LV +1", -- (StoreController shows the levels: "LV 4 > LV 5")
		Note = "+1 rebirth start LV (max 9)",
	}),
	---------------------------------------------------------------- PASSES
	card({
		Id = "Podiums",
		Keys = { "Podiums" },
		Look = "Pass",
		Paint = "Orange",
		Icon = "podium",
		Model = "podium",
		Section = "Passes",
		Row = 1,
		Title = "Two More Podiums",
		Short = "Podiums 4 and 5 on your base",
	}),
	card({
		Id = "NightShift",
		Keys = { "OfflineExtension" },
		Look = "Pass",
		Paint = "Night",
		Icon = "item_Clean_Moonstone",
		Model = "item_Moonstone",
		Sheet = "moon",
		Section = "Passes",
		Row = 1,
		Short = "Podiums earn 50% while you are away, up to 12 h",
	}),
	card({
		Id = "DoubleMoney",
		Keys = { "DoubleMoney" },
		Look = "Pass",
		Paint = "Green",
		Icon = "cash_safe",
		Model = "cash_safe",
		Sheet = "cash",
		Section = "Passes",
		Row = 1,
		Title = "2x Money",
		Short = "Income and sales x2, forever",
	}),
	card({
		Id = "CustomBoard",
		Keys = { "HoverboardCustom" },
		Look = "Pass",
		Paint = "Rainbow",
		Icon = "board_TerraForgeCustom",
		Model = "board_TerraForgeCustom",
		PictureScale = 1.3,
		Section = "Passes",
		Row = 1,
		Title = "Custom Hoverboard",
		Short = "Speed 48 + rainbow trail",
	}),
	card({
		Id = "BigPassWide",
		Keys = { "BigPass" },
		Look = "Bundle",
		Paint = "Royal",
		Icon = "pass_crown",
		Model = "pass_crown",
		Sheet = "crown",
		Section = "Passes",
		Row = 2,
		Title = "Forgemaster's Pass",
		Odds = true,
		Lines = BIG_PASS_LINES,
		LineIcons = BIG_PASS_ICONS,
		Gold = true,
	}),
	---------------------------------------------------------------- BOOSTS
	card({
		Id = "ServerLuck",
		Keys = { "ServerLuck15" },
		Look = "ServerLuck",
		Paint = "Green",
		Icon = "luck_server",
		Model = "luck_server",
		Sheet = "clover",
		Section = "Boosts",
		Row = 1,
		Span = 1.9,
		Title = "Server Luck",
	}),
	card({
		Id = "WheelSpins",
		Keys = { "WheelSpins1" },
		Options = { "WheelSpins1", "WheelSpins5", "WheelSpins10" },
		Look = "Wheel",
		Paint = "Pink",
		Icon = "wheel",
		Sheet = "wheel",
		Section = "Boosts",
		Row = 1,
		Title = "Wheel Spins",
	}),
	card({
		Id = "TripleLucky15",
		Keys = { "TripleLucky15" },
		Options = { "TripleLucky15", "TripleLucky60" },
		Look = "Luck",
		Paint = "Teal",
		Icon = "clover",
		Model = "clover",
		Sheet = "clover_gold",
		Section = "Boosts",
		Row = 2,
		Title = "Triple Lucky",
		Big = "x3",
		Short = "Rarer golems from eggs",
	}),
	card({
		Id = "HexaLucky15",
		Keys = { "HexaLucky15" },
		Options = { "HexaLucky15", "HexaLucky60" },
		Look = "Luck",
		Paint = "Blue",
		Icon = "item_Clean_Diamond",
		Model = "item_Diamond",
		Sheet = "clover_rainbow",
		Section = "Boosts",
		Row = 2,
		Title = "Hexa Lucky",
		Big = "x2.5",
		Short = "Rarer ores while you mine",
	}),
	card({
		Id = "Heartfire",
		Keys = { "EnchantHeartfire" },
		Look = "Enchant",
		Paint = "Red",
		Icon = "item_Clean_Heartstone",
		Model = "item_Heartstone",
		Sheet = "heart_fire",
		Section = "Boosts",
		Row = 2,
		Title = "Heartfire",
	}),
	card({
		Id = "Starbreaker",
		Keys = { "EnchantStarbreaker" },
		Look = "Enchant",
		Paint = "Mythic",
		Icon = "item_Clean_CelestialCore",
		Model = "item_CelestialCore",
		Sheet = "star_break",
		Section = "Boosts",
		Row = 2,
		Title = "Starbreaker",
	}),
	---------------------------------------------------------------- CASH (five packs, the 2x Money band under them)
	card({
		Id = "CoinsSmall",
		Keys = { "CoinsSmall" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_bundle",
		Model = "cash_bundle",
		Sheet = "cash",
		Section = "Cash",
		Row = 1,
	}),
	card({
		Id = "CoinsMedium",
		Keys = { "CoinsMedium" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_pile",
		Model = "cash_pile",
		Sheet = "bag",
		Section = "Cash",
		Row = 1,
	}),
	card({
		Id = "CoinsLarge",
		Keys = { "CoinsLarge" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_stack",
		Model = "cash_stack",
		Sheet = "coins",
		Section = "Cash",
		Row = 1,
	}),
	card({
		Id = "CoinsHuge",
		Keys = { "CoinsHuge" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_sack",
		Model = "cash_sack",
		Sheet = "bag",
		Section = "Cash",
		Row = 1,
	}),
	card({
		Id = "CoinsMega",
		Keys = { "CoinsMega" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_safe",
		Model = "cash_safe",
		Sheet = "chest",
		Section = "Cash",
		Row = 1,
	}),
	card({
		Id = "DoubleMoneyWide",
		Keys = { "DoubleMoney" },
		Look = "MoneyWide",
		Paint = "Amber",
		Icon = "cash_safe",
		Model = "cash_safe",
		Sheet = "cash",
		Section = "Cash",
		Row = 2,
		Title = "2x Money",
		Short = "Your podiums earn twice as much, and sales pay twice as much, forever",
	}),
} :: { CardSpec }

-- the five STAR blasters (the blaster chat's passes): two beside the next level card, then a row of three
do
	local paints = { "Cyber", "Purple", "Teal", "Orange", "Mythic" }
	for i, star in StarBlasterData.List do
		local key = "Star" .. star.Id
		if MonetizationConfig.Products[key] then
			table.insert(StoreConfig.Cards, {
				Id = key,
				Keys = { key },
				Look = "Star",
				Paint = paints[i] or "Purple",
				GlowColor = star.Glow,
				Icon = "star_" .. star.Id,
				Model = "star_" .. star.Id,
				Section = "Blasters",
				Row = if i <= 2 then 1 else 2,
				Title = star.Name,
				Big = `x{star.Mult} POWER`,
				Note = `Opens at rebirth {star.Unlock}`,
				Star = star.Id,
			})
		end
	end
end

StoreConfig.ById = {} :: { [string]: CardSpec }
StoreConfig.SectionById = {} :: { [string]: Section }
for _, section in StoreConfig.Sections do
	StoreConfig.SectionById[section.Id] = section
end
for _, spec in StoreConfig.Cards do
	assert(StoreConfig.ById[spec.Id] == nil, "StoreConfig: two cards named " .. spec.Id)
	assert(StoreConfig.SectionById[spec.Section], "StoreConfig: unknown section " .. spec.Section)
	StoreConfig.ById[spec.Id] = spec
	for _, key in spec.Keys do
		assert(MonetizationConfig.Products[key], "StoreConfig: unknown product " .. key)
	end
	local options: { string } = spec.Options or {}
	for _, key in options do
		assert(MonetizationConfig.Products[key], "StoreConfig: unknown option " .. key)
	end
end

-- The rows of a section: row number -> its cards (config order).
function StoreConfig.rows(sectionId: string): { { CardSpec } }
	local rows: { { CardSpec } } = {}
	for _, spec in StoreConfig.Cards do
		if spec.Section == sectionId then
			local row = rows[spec.Row]
			if not row then
				row = {}
				rows[spec.Row] = row
			end
			table.insert(row, spec)
		end
	end
	-- (no holes: rows 1..n)
	local out: { { CardSpec } } = {}
	local keys: { number } = {}
	for n in rows do
		table.insert(keys, n)
	end
	table.sort(keys)
	for _, n in keys do
		table.insert(out, rows[n])
	end
	return out
end

-- Every product key a card can buy (its Keys and its Options, once each).
function StoreConfig.keysOf(spec: CardSpec): { string }
	local out: { string } = {}
	local options: { string } = spec.Options or {}
	for _, key in spec.Keys do
		if not table.find(out, key) then
			table.insert(out, key)
		end
	end
	for _, key in options do
		if not table.find(out, key) then
			table.insert(out, key)
		end
	end
	return out
end

-- Is `key` sold in the Shop? (StoreService only prompts these.)
function StoreConfig.sells(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	for _, spec in StoreConfig.Cards do
		if table.find(spec.Keys, key) or (spec.Options and table.find(spec.Options, key)) then
			return true
		end
	end
	return false
end

-- The tab card `id` sits on (nil: no such card).
function StoreConfig.sectionOf(id: string): string?
	local spec = StoreConfig.ById[id]
	return if spec then spec.Section else nil
end

-- The blaster band for a player whose blaster is at `level` (nil at the top
-- or for a band-less card): the entry whose MinLevel..MaxLevel holds level + 1.
function StoreConfig.blasterKey(spec: CardSpec, level: any): string?
	local nextLevel = (if type(level) == "number" and level == level then math.floor(level) else 1) + 1
	for _, key in spec.Keys do
		local product = MonetizationConfig.Products[key]
		if product.MinLevel and product.MaxLevel and nextLevel >= product.MinLevel and nextLevel <= product.MaxLevel then
			return key
		end
	end
	return nil
end

return StoreConfig
