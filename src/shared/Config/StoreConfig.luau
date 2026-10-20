--[[
	The Robux STORE window's cards (owner 2026-10-20: "like the store in the
	photos": one long row of dark cards with glowing borders that scrolls
	sideways). Names, descriptions and prices come from MonetizationConfig;
	this file only says where each card sits and how it looks.

	The cards sit on a grid: Col / Row from the left / top, Cols / Rows how
	many cells they span (StoreConfig.Rows rows; a column is Unit design
	units wide). Looks:
	  Bundle   a big feature card: title, "Includes:" lines, picture, price
	  Coins    the amount on top (from the player's income), picture, price
	  Boost    title, picture, a big effect line ("x2") and a gold note
	  Item     title, picture on the left, the description on the right
	  Capsule  title, picture, the count; tapping shows the odds first
	  Star     a STAR blaster (StarBlasterData, its pass): the live gun, its
	           power, "Opens at rebirth N" until the player's rebirths reach it
	A card with several Keys shows the first that fits the player (the
	blaster: the price band of the player's next level).
]]

local MonetizationConfig = require(script.Parent.MonetizationConfig)
local StarBlasterData = require(script.Parent.StarBlasterData)

export type CardSpec = {
	Id: string, -- the card's name in the view
	Keys: { string }, -- MonetizationConfig keys (the first that fits shows)
	Look: string, -- "Bundle" | "Coins" | "Boost" | "Item" | "Capsule"
	Glow: string, -- CardTheme.Glows name
	Icon: string, -- the 3D icon (IconAssets / tools/preview/icons)
	Col: number,
	Row: number,
	Cols: number,
	Rows: number,
	Title: string?, -- instead of the product's Name
	Lines: { string }?, -- Bundle: the "Includes:" lines
	Big: string?, -- Boost: the big effect line
	Note: string?, -- Boost / Capsule: the gold line under it
	Short: string?, -- Item: a shorter text than the product's description (the odds panel shows the rest)
	Odds: boolean?, -- tapping shows the odds panel first (paid random products always do)
	Star: string?, -- Star: the StarBlasterData id
	GlowColor: Color3?, -- instead of a CardTheme glow: the border in this colour
}

local StoreConfig = {}

StoreConfig.Title = "Store"
StoreConfig.Rows = 2
StoreConfig.Unit = 76 -- design units per grid column
StoreConfig.RowHeight = 226
StoreConfig.Gap = 12

local function card(spec: CardSpec): CardSpec
	return spec
end

StoreConfig.Cards = {
	-- the feature bundle
	card({
		Id = "BigPass",
		Keys = { "BigPass" },
		Look = "Bundle",
		Glow = "Orange",
		Icon = "pass_crown",
		Col = 0,
		Row = 0,
		Cols = 6,
		Rows = 2,
		Title = "Forgemaster's Pass",
		Odds = true, -- it opens the Glimmer Grotto: its ore odds show before the buy (COMPLIANCE "Forge VIP and ore odds")
		Lines = { "Podiums 3 and 4", "12 h offline earnings", "Double carrying", "The Glimmer Grotto", "Extra machine slots" },
	}),
	-- coins: three on top, two wide ones under them (like the photos)
	card({ Id = "CoinsSmall", Keys = { "CoinsSmall" }, Look = "Coins", Glow = "Orange", Icon = "coin", Col = 6, Row = 0, Cols = 2, Rows = 1 }),
	card({ Id = "CoinsMedium", Keys = { "CoinsMedium" }, Look = "Coins", Glow = "Orange", Icon = "coins", Col = 8, Row = 0, Cols = 2, Rows = 1 }),
	card({ Id = "CoinsLarge", Keys = { "CoinsLarge" }, Look = "Coins", Glow = "Orange", Icon = "coin_pile", Col = 10, Row = 0, Cols = 2, Rows = 1 }),
	card({ Id = "CoinsHuge", Keys = { "CoinsHuge" }, Look = "Coins", Glow = "Orange", Icon = "coin_sack", Col = 6, Row = 1, Cols = 3, Rows = 1 }),
	card({ Id = "CoinsMega", Keys = { "CoinsMega" }, Look = "Coins", Glow = "Gold", Icon = "coin_chest", Col = 9, Row = 1, Cols = 3, Rows = 1 }),
	-- luck
	card({
		Id = "ServerLuck",
		Keys = { "ServerLuck15" },
		Look = "Boost",
		Glow = "Green",
		Icon = "luck_server",
		Col = 12,
		Row = 0,
		Cols = 4,
		Rows = 2,
		Big = "1x → 2x",
		Note = "+15 mins!",
	}),
	card({ Id = "TripleLucky15", Keys = { "TripleLucky15" }, Look = "Item", Glow = "Rainbow", Icon = "clover", Col = 16, Row = 0, Cols = 5, Rows = 1, Title = "Triple Lucky" }),
	card({ Id = "HexaLucky15", Keys = { "HexaLucky15" }, Look = "Item", Glow = "Blue", Icon = "rainbow", Col = 16, Row = 1, Cols = 5, Rows = 1, Title = "Hexa Lucky" }),
	-- golem capsules ("eggs")
	card({ Id = "Royal1", Keys = { "RoyalCapsule1" }, Look = "Capsule", Glow = "Purple", Icon = "capsule_Royal", Col = 21, Row = 0, Cols = 3, Rows = 1, Note = "x1" }),
	card({ Id = "Royal3", Keys = { "RoyalCapsule3" }, Look = "Capsule", Glow = "Purple", Icon = "capsule_Royal", Col = 24, Row = 0, Cols = 3, Rows = 1, Note = "x3" }),
	card({ Id = "Royal5", Keys = { "RoyalCapsule5" }, Look = "Capsule", Glow = "Red", Icon = "capsule_Royal", Col = 21, Row = 1, Cols = 3, Rows = 1, Note = "x5" }),
	card({ Id = "Royal10", Keys = { "RoyalCapsule10" }, Look = "Capsule", Glow = "Gold", Icon = "capsule_Royal", Col = 24, Row = 1, Cols = 3, Rows = 1, Note = "x10" }),
	-- the blaster (the band of the player's next level)
	card({
		Id = "Blaster",
		Keys = { "BlasterNextA", "BlasterNextB", "BlasterNextC", "BlasterNextD" },
		Look = "Boost",
		Glow = "Red",
		Icon = "blaster",
		Col = 27,
		Row = 0,
		Cols = 4,
		Rows = 2,
		Title = "Next Blaster",
		Big = "LV +1", -- (StoreController shows the next level: "LV 5")
		Note = "+1 start LV every rebirth",
	}),
	-- passes and boards
	card({ Id = "Podiums", Keys = { "Podiums" }, Look = "Item", Glow = "Orange", Icon = "podium", Col = 31, Row = 0, Cols = 5, Rows = 1 }),
	card({ Id = "NightShift", Keys = { "OfflineExtension" }, Look = "Item", Glow = "Blue", Icon = "moon", Col = 31, Row = 1, Cols = 5, Rows = 1 }),
	card({ Id = "Comet", Keys = { "HoverboardComet" }, Look = "Item", Glow = "Blue", Icon = "hoverboard", Col = 36, Row = 0, Cols = 5, Rows = 1, Title = "Neon Comet" }),
	card({ Id = "Phoenix", Keys = { "HoverboardPhoenix" }, Look = "Item", Glow = "Purple", Icon = "hoverboard", Col = 36, Row = 1, Cols = 5, Rows = 1, Title = "Royal Phoenix" }),
	card({ Id = "Train", Keys = { "TrainExpress" }, Look = "Item", Glow = "Green", Icon = "train", Col = 41, Row = 0, Cols = 5, Rows = 1 }),
	card({ Id = "Heartfire", Keys = { "EnchantHeartfire" }, Look = "Item", Glow = "Red", Icon = "enchant_Heartfire", Col = 41, Row = 1, Cols = 5, Rows = 1 }),
	card({
		Id = "Starbreaker",
		Keys = { "EnchantStarbreaker" },
		Look = "Item",
		Glow = "Rainbow",
		Icon = "enchant_Starbreaker",
		Col = 46,
		Row = 0,
		Cols = 4,
		Rows = 2,
		Short = "The Mythic enchant, yours forever: +75% ore luck, +50% artifact chance. Tap for the new odds.",
	}),
} :: { CardSpec }

-- the five STAR blasters (the blaster chat's passes): two rows at the end of the row
do
	local col = StoreConfig.Cards[#StoreConfig.Cards].Col + StoreConfig.Cards[#StoreConfig.Cards].Cols
	for i, star in StarBlasterData.List do
		local key = "Star" .. star.Id
		if MonetizationConfig.Products[key] then
			table.insert(StoreConfig.Cards, {
				Id = key,
				Keys = { key },
				Look = "Star",
				Glow = "Purple",
				GlowColor = star.Glow,
				Icon = "star_" .. star.Id,
				Col = col + ((i - 1) // 2) * 4,
				Row = (i - 1) % 2,
				Cols = 4,
				Rows = 1,
				Title = star.Name,
				Big = `x{star.Mult} power`,
				Note = `Opens at rebirth {star.Unlock}`,
				Star = star.Id,
			})
		end
	end
end

StoreConfig.ById = {} :: { [string]: CardSpec }
for _, spec in StoreConfig.Cards do
	assert(StoreConfig.ById[spec.Id] == nil, "StoreConfig: two cards named " .. spec.Id)
	StoreConfig.ById[spec.Id] = spec
	for _, key in spec.Keys do
		assert(MonetizationConfig.Products[key], "StoreConfig: unknown product " .. key)
	end
end

-- Grid columns the store spans.
function StoreConfig.columns(): number
	local last = 0
	for _, spec in StoreConfig.Cards do
		last = math.max(last, spec.Col + spec.Cols)
	end
	return last
end

-- Is `key` sold in the Store? (StoreService only prompts these.)
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
