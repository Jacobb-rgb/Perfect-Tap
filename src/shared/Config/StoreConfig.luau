--[[
	The Robux Shop's cards (owner 2026-10-20 evening: "change the shop
	completely, like this", his egg-game photos): sections one under the
	other ("-- MONEY --", "-- PASSES --"...) in a window that scrolls down,
	bright painted cards, a tab per section right of the window. Names,
	descriptions and prices come from MonetizationConfig; this file only
	says where each card sits and how it looks.

	A card sits in a Section, on a Row (1, 2...); the cards of a row share
	its width by their Span (default 1). Looks:
	  Bundle   the big feature card: title, "Includes:" lines, picture, price
	  Coins    the coins it gives (from the player's income), the cash picture, price
	  Boost    title, picture, a big effect line ("x2 LUCK") and a note
	  Item     picture on the left, title and description on the right, price
	  Capsule  picture, the count ("x5"); tapping shows the odds first
	  Star     a STAR blaster (StarBlasterData, its pass): the live gun, its
	           power, "Opens at rebirth N" until the player's rebirths reach it
	A card with several Keys shows the first that fits the player (the
	blaster: the price band of the player's next level).

	Pictures: Model names a 3D model shown live in the game (cash_* from
	CashBuilder, capsule_<Id> / golem_<Kind> from GolemBuilder, train, the
	hoverboards, star_<Id>); Icon is the picture name for the previews and
	the uploaded icon sheets (IconAssets).
]]

local MonetizationConfig = require(script.Parent.MonetizationConfig)
local StarBlasterData = require(script.Parent.StarBlasterData)

export type CardSpec = {
	Id: string, -- the card's name in the view
	Keys: { string }, -- MonetizationConfig keys (the first that fits shows)
	Look: string, -- "Bundle" | "Coins" | "Boost" | "Item" | "Capsule" | "Star"
	Paint: string, -- PopTheme.Paints name, or "Rainbow"
	Icon: string, -- the picture (IconAssets / tools/preview/icons)
	Model: string?, -- a live 3D model picture (see the header)
	Section: string,
	Row: number,
	Span: number?, -- share of the row's width (default 1)
	Title: string?, -- instead of the product's Name
	Lines: { string }?, -- Bundle: the "Includes:" lines
	Big: string?, -- Boost / Capsule: the big line
	Note: string?, -- Boost / Star: the line under it
	Short: string?, -- Item: a shorter text than the product's description (the odds panel shows the rest)
	Odds: boolean?, -- tapping shows the odds panel first (paid random products always do)
	Star: string?, -- Star: the StarBlasterData id
	Ribbon: string?, -- a tilted gold ribbon on the corner ("BEST VALUE!")
	GlowColor: Color3?, -- Star: the card painted from the blaster's light
}

export type Section = {
	Id: string,
	Title: string, -- "-- MONEY --"
	Colors: string, -- PopTheme.Titles name
	Tab: string, -- the tab's word
	TabIcon: string,
	TabPaint: string,
	TabModel: string?, -- the tab's live 3D picture (PictureModels), else TabIcon
	RowHeight: number, -- design units
	BigRow: number?, -- a taller first row (the feature card)
}

local StoreConfig = {}

StoreConfig.Title = "Shop"

StoreConfig.Sections = {
	{ Id = "Featured", Title = "FEATURED", Colors = "Gold", Tab = "Featured", TabIcon = "pass_crown", TabModel = "pass_crown", TabPaint = "Yellow", RowHeight = 300 },
	{ Id = "Money", Title = "MONEY", Colors = "Green", Tab = "Money", TabIcon = "cash_stack", TabModel = "cash_stack", TabPaint = "Green", RowHeight = 236 },
	{ Id = "Luck", Title = "LUCK", Colors = "Cyan", Tab = "Luck", TabIcon = "clover", TabModel = "luck_server", TabPaint = "Teal", RowHeight = 250 },
	{ Id = "Eggs", Title = "GOLEM CAPSULES", Colors = "Magenta", Tab = "Eggs", TabIcon = "capsule_Royal", TabModel = "capsule_Royal", TabPaint = "Purple", RowHeight = 236 },
	{ Id = "Blasters", Title = "BLASTERS", Colors = "Red", Tab = "Blasters", TabIcon = "blaster", TabModel = "blaster", TabPaint = "Red", RowHeight = 250 },
	{ Id = "Passes", Title = "PASSES", Colors = "Gold", Tab = "Passes", TabIcon = "podium", TabModel = "podium", TabPaint = "Orange", RowHeight = 196 },
} :: { Section }

local function card(spec: CardSpec): CardSpec
	return spec
end

StoreConfig.Cards = {
	-- the feature bundle
	card({
		Id = "BigPass",
		Keys = { "BigPass" },
		Look = "Bundle",
		Paint = "Rainbow",
		Icon = "pass_crown",
		Model = "pass_crown",
		Section = "Featured",
		Row = 1,
		Title = "FORGEMASTER'S PASS",
		Odds = true, -- it opens the Glimmer Grotto: its ore odds show before the buy (COMPLIANCE "Forge VIP and ore odds")
		Lines = { "Podiums 3 and 4", "12 h offline earnings", "Double carrying", "The Glimmer Grotto", "Extra machine slots" },
	}),
	-- the Starter Pack (one per player, in the first hour of play: StarterPackService;
	-- StoreController hides it once bought or when the offer is over)
	card({
		Id = "StarterPack",
		Keys = { "StarterPack" },
		Look = "Bundle",
		Paint = "Teal",
		Icon = "golem_GildedPorter",
		Model = "golem_GildedPorter",
		Section = "Featured",
		Row = 2,
		Title = "STARTER PACK",
		Lines = { "Rare golem Gilded Porter", "20 min of income in coins", "Pioneer podium skin + title" },
	}),
	-- money: three on top, the 2x Money pass and two wide ones under them (like the photos)
	card({ Id = "CoinsSmall", Keys = { "CoinsSmall" }, Look = "Coins", Paint = "Green", Icon = "cash_bundle", Model = "cash_bundle", Section = "Money", Row = 1 }),
	card({ Id = "CoinsMedium", Keys = { "CoinsMedium" }, Look = "Coins", Paint = "Green", Icon = "cash_pile", Model = "cash_pile", Section = "Money", Row = 1 }),
	card({ Id = "CoinsLarge", Keys = { "CoinsLarge" }, Look = "Coins", Paint = "Green", Icon = "cash_stack", Model = "cash_stack", Section = "Money", Row = 1 }),
	card({
		Id = "DoubleMoney",
		Keys = { "DoubleMoney" },
		Look = "Boost",
		Paint = "Yellow",
		Icon = "cash_safe",
		Model = "cash_safe",
		Section = "Money",
		Row = 2,
		Title = "2x Money",
		Big = "x2 MONEY",
		Note = "Income + sales, forever",
	}),
	card({ Id = "CoinsHuge", Keys = { "CoinsHuge" }, Look = "Coins", Paint = "Green", Icon = "cash_sack", Model = "cash_sack", Section = "Money", Row = 2 }),
	card({
		Id = "CoinsMega",
		Keys = { "CoinsMega" },
		Look = "Coins",
		Paint = "Green",
		Icon = "cash_safe",
		Model = "cash_safe",
		Section = "Money",
		Row = 2,
		Ribbon = "BEST VALUE!",
	}),
	-- luck
	card({
		Id = "ServerLuck",
		Keys = { "ServerLuck15" },
		Look = "Boost",
		Paint = "Teal",
		Icon = "luck_server",
		Model = "luck_server",
		Section = "Luck",
		Row = 1,
		Title = "Server Luck",
		Big = "x2 LUCK",
		Note = "For everyone! +15 min",
	}),
	card({ Id = "TripleLucky15", Keys = { "TripleLucky15" }, Look = "Boost", Paint = "Yellow", Icon = "clover", Model = "clover", Section = "Luck", Row = 1, Title = "Triple Lucky", Big = "x3", Note = "Rarer golems, 15 min" }),
	card({ Id = "HexaLucky15", Keys = { "HexaLucky15" }, Look = "Boost", Paint = "Blue", Icon = "rainbow", Model = "item_Diamond", Section = "Luck", Row = 1, Title = "Hexa Lucky", Big = "x2.5", Note = "Rarer ores, 15 min" }),
	-- golem capsules ("eggs")
	card({ Id = "Royal1", Keys = { "RoyalCapsule1" }, Title = "Royal Egg", Look = "Capsule", Paint = "Purple", Icon = "capsule_Royal", Model = "capsule_Royal", Section = "Eggs", Row = 1, Big = "x1" }),
	card({ Id = "Royal3", Keys = { "RoyalCapsule3" }, Title = "Royal Egg", Look = "Capsule", Paint = "Purple", Icon = "capsule_Royal", Model = "capsule_Royal", Section = "Eggs", Row = 1, Big = "x3" }),
	card({ Id = "Royal5", Keys = { "RoyalCapsule5" }, Title = "Royal Egg", Look = "Capsule", Paint = "Pink", Icon = "capsule_Royal", Model = "capsule_Royal", Section = "Eggs", Row = 1, Big = "x5" }),
	card({
		Id = "Royal10",
		Keys = { "RoyalCapsule10" },
		Title = "Royal Egg",
		Look = "Capsule",
		Paint = "Pink",
		Icon = "capsule_Royal",
		Model = "capsule_Royal",
		Section = "Eggs",
		Row = 1,
		Big = "x10",
		Ribbon = "BEST VALUE!",
	}),
	-- the blaster (the band of the player's next level)
	card({
		Id = "Blaster",
		Keys = { "BlasterNextA", "BlasterNextB", "BlasterNextC", "BlasterNextD" },
		Look = "Boost",
		Paint = "Red",
		Icon = "blaster",
		Model = "blaster",
		Section = "Blasters",
		Row = 1,
		Title = "Next Blaster",
		Big = "LV +1", -- (StoreController shows the next level: "LV 5")
		Note = "+1 rebirth start LV (max 9)",
	}),
	-- passes and boards
	card({ Id = "Podiums", Keys = { "Podiums" }, Look = "Item", Paint = "Orange", Icon = "podium", Model = "podium", Section = "Passes", Row = 1 }),
	card({ Id = "NightShift", Keys = { "OfflineExtension" }, Look = "Item", Paint = "Blue", Icon = "moon", Model = "item_Moonstone", Section = "Passes", Row = 1 }),
	card({ Id = "Comet", Keys = { "HoverboardComet" }, Look = "Item", Paint = "Teal", Icon = "hoverboard", Model = "board_NeonComet", Section = "Passes", Row = 2, Title = "Neon Comet" }),
	card({ Id = "Phoenix", Keys = { "HoverboardPhoenix" }, Look = "Item", Paint = "Purple", Icon = "hoverboard", Model = "board_RoyalPhoenix", Section = "Passes", Row = 2, Title = "Royal Phoenix" }),
	card({ Id = "Train", Keys = { "TrainExpress" }, Look = "Item", Paint = "Green", Icon = "train", Model = "train", Section = "Passes", Row = 3 }),
	card({ Id = "Heartfire", Keys = { "EnchantHeartfire" }, Look = "Item", Paint = "Red", Icon = "enchant_Heartfire", Model = "item_Heartstone", Section = "Passes", Row = 3 }),
	card({
		Id = "Starbreaker",
		Keys = { "EnchantStarbreaker" },
		Look = "Item",
		Paint = "Rainbow",
		Icon = "enchant_Starbreaker",
		Model = "item_CelestialCore",
		Section = "Passes",
		Row = 4,
		Short = "The Mythic enchant, yours forever: +75% ore luck, +50% artifact chance. Tap for the new odds.",
	}),
} :: { CardSpec }

-- the five STAR blasters (the blaster chat's passes): beside the next level card, then a row of three
do
	for i, star in StarBlasterData.List do
		local key = "Star" .. star.Id
		if MonetizationConfig.Products[key] then
			table.insert(StoreConfig.Cards, {
				Id = key,
				Keys = { key },
				Look = "Star",
				Paint = "Purple",
				GlowColor = star.Glow,
				Icon = "star_" .. star.Id,
				Model = "star_" .. star.Id,
				Section = "Blasters",
				Row = if i <= 2 then 1 else 2,
				Title = star.Name,
				Big = `x{star.Mult} power`,
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

-- Is `key` sold in the Shop? (StoreService only prompts these.)
function StoreConfig.sells(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	for _, spec in StoreConfig.Cards do
		if table.find(spec.Keys, key) then
			return true
		end
	end
	return false
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
