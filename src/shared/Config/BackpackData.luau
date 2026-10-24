--[[
	The backpacks (owner 2026-10-24: "batohy od nejhoršího po nejlepší", after
	the blue rune backpack in his reference picture). Ten packs, worst to
	best; each one holds more ore (start 5, top 1000, owner 2026-10-24) and
	looks richer. Owner on the first proposal: the starter sack out, every
	pack needs far more detail and effects ("mega efektové a stylové").

	Every pack shares one anatomy (BackpackBuilder): a body with a lighter
	bulging front and round edges, a flap folded over the top (stitched edge,
	a contrasting inset panel, a round tongue with the emblem), a front
	pocket with a round bottom, straps with prong buckles, side pockets, a
	bedroll with spiral ends and padded straps over the shoulders. Each pack
	adds its own pieces (a mini pickaxe, a lantern, a spyglass, crystals,
	runes, ember chimneys, wings) and from the Miner's Pack up its effects
	(BackpackFx: glints, rising runes, fire and smoke, stars, a light).

	Colors: Body (the bag), Panel (the flap's inset / plates / galaxy),
	Flap, Trim (edge posts and strips on trimmed packs), Leather (straps,
	bottom), Buckle (buckles, rivets, metal bits), Roll (the bedroll), Gem
	(the emblem crystal's core), Glow (Neon: runes, glows, the light;
	ItemBuilder.glowColor keeps it from blooming white), Stitch (seams).

	PROPOSAL (art/backpacks): capacities and coin prices are a first guess
	on the 6-floor curve (BALANCE_SIM.md: blaster 4 ~710K at 27 min, blaster
	6 ~73M at 1h20, blaster 8 ~2.2B at 3h16, blaster 10 ~290B at 8 h); the
	balance sim tunes them once the backpack inventory is in the game.
	Coins only (owner 2026-10-24: no Robux backpacks).
]]

export type Colors = {
	Body: Color3,
	Panel: Color3,
	Flap: Color3,
	Trim: Color3,
	Leather: Color3,
	Buckle: Color3,
	Roll: Color3,
	Gem: Color3,
	Glow: Color3,
	Stitch: Color3,
}

export type Backpack = {
	Id: string,
	Name: string,
	Order: number, -- 1 = the starter pack
	Rarity: string, -- Rarity.ById key (card and name colour)
	Capacity: number, -- ore chunks it holds
	Price: number, -- coins (0 = everyone starts with it)
	Description: string,
	Size: Vector3, -- the bag body (X wide, Y tall, Z deep), for the builder
	Colors: Colors,
}

local rgb = Color3.fromRGB

local BackpackData = {}

BackpackData.StarterId = "RookiePack"

BackpackData.List = {
	{
		Id = "RookiePack",
		Name = "Rookie Pack",
		Order = 1,
		Rarity = "Common",
		Capacity = 5,
		Price = 0,
		Description = "A cute canvas school bag with a star charm and a mini pickaxe.",
		Size = Vector3.new(1.4, 1.6, 0.74),
		Colors = {
			Body = rgb(232, 210, 160),
			Panel = rgb(176, 146, 98),
			Flap = rgb(156, 98, 56),
			Trim = rgb(156, 98, 56),
			Leather = rgb(112, 70, 40),
			Buckle = rgb(172, 176, 184),
			Roll = rgb(176, 146, 98),
			Gem = rgb(240, 150, 60),
			Glow = rgb(240, 150, 60),
			Stitch = rgb(250, 236, 204),
		},
	},
	{
		Id = "TrailPack",
		Name = "Trail Pack",
		Order = 2,
		Rarity = "Common",
		Capacity = 15,
		Price = 250,
		Description = "Khaki canvas, a green bedroll, a tin mug and a leaf charm.",
		Size = Vector3.new(1.5, 1.66, 0.82),
		Colors = {
			Body = rgb(184, 172, 116),
			Panel = rgb(148, 136, 88),
			Flap = rgb(132, 84, 50),
			Trim = rgb(132, 84, 50),
			Leather = rgb(104, 64, 36),
			Buckle = rgb(176, 180, 188),
			Roll = rgb(96, 150, 74),
			Gem = rgb(96, 150, 74),
			Glow = rgb(96, 150, 74),
			Stitch = rgb(244, 232, 196),
		},
	},
	{
		Id = "LeatherRucksack",
		Name = "Leather Rucksack",
		Order = 3,
		Rarity = "Uncommon",
		Capacity = 30,
		Price = 5000,
		Description = "Brown leather, brass buckles, a brass shield and a canteen.",
		Size = Vector3.new(1.6, 1.78, 0.86),
		Colors = {
			Body = rgb(160, 100, 56),
			Panel = rgb(110, 64, 34),
			Flap = rgb(124, 74, 40),
			Trim = rgb(226, 178, 78),
			Leather = rgb(88, 52, 30),
			Buckle = rgb(230, 182, 80),
			Roll = rgb(98, 140, 72),
			Gem = rgb(230, 182, 80),
			Glow = rgb(255, 200, 90),
			Stitch = rgb(244, 214, 160),
		},
	},
	{
		Id = "MinersPack",
		Name = "Miner's Pack",
		Order = 4,
		Rarity = "Uncommon",
		Capacity = 60,
		Price = 120000,
		Description = "A miner's pack with a lantern, a pickaxe, a rope and ore spilling out.",
		Size = Vector3.new(1.7, 1.88, 0.9),
		Colors = {
			Body = rgb(112, 108, 70),
			Panel = rgb(82, 78, 50),
			Flap = rgb(108, 68, 40),
			Trim = rgb(198, 114, 62),
			Leather = rgb(84, 52, 30),
			Buckle = rgb(210, 122, 66),
			Roll = rgb(128, 130, 138),
			Gem = rgb(210, 122, 66),
			Glow = rgb(255, 170, 60),
			Stitch = rgb(232, 220, 170),
		},
	},
	{
		Id = "IronboundPack",
		Name = "Iron-Bound Pack",
		Order = 5,
		Rarity = "Rare",
		Capacity = 100,
		Price = 2500000,
		Description = "Steel plates and bands, a chained blue gem and blue crystals.",
		Size = Vector3.new(1.78, 1.96, 0.95),
		Colors = {
			Body = rgb(72, 84, 106),
			Panel = rgb(138, 146, 160),
			Flap = rgb(58, 68, 88),
			Trim = rgb(150, 158, 172),
			Leather = rgb(82, 54, 36),
			Buckle = rgb(186, 194, 206),
			Roll = rgb(96, 128, 170),
			Gem = rgb(40, 120, 230),
			Glow = rgb(61, 165, 255),
			Stitch = rgb(200, 214, 232),
		},
	},
	{
		Id = "ExplorersPack",
		Name = "Explorer's Pack",
		Order = 6,
		Rarity = "Rare",
		Capacity = 175,
		Price = 60000000,
		Description = "Brass trim, a glowing compass, a map tube, a spyglass and a plume.",
		Size = Vector3.new(1.82, 2.0, 0.96),
		Colors = {
			Body = rgb(56, 110, 82),
			Panel = rgb(38, 78, 58),
			Flap = rgb(46, 92, 68),
			Trim = rgb(228, 180, 80),
			Leather = rgb(112, 68, 38),
			Buckle = rgb(238, 192, 86),
			Roll = rgb(190, 60, 50),
			Gem = rgb(236, 190, 84),
			Glow = rgb(60, 230, 180),
			Stitch = rgb(232, 224, 180),
		},
	},
	{
		Id = "AmethystPack",
		Name = "Amethyst Pack",
		Order = 7,
		Rarity = "Epic",
		Capacity = 275,
		Price = 900000000,
		Description = "Silver filigree and amethyst crystals growing from the flap and the top.",
		Size = Vector3.new(1.88, 2.06, 1.0),
		Colors = {
			Body = rgb(98, 56, 152),
			Panel = rgb(170, 140, 220),
			Flap = rgb(80, 44, 130),
			Trim = rgb(216, 220, 232),
			Leather = rgb(66, 42, 56),
			Buckle = rgb(228, 232, 242),
			Roll = rgb(178, 152, 216),
			Gem = rgb(96, 64, 255),
			Glow = rgb(170, 100, 255),
			Stitch = rgb(226, 214, 250),
		},
	},
	{
		Id = "RuneboundPack",
		Name = "Runebound Pack",
		Order = 8,
		Rarity = "Epic",
		Capacity = 400,
		Price = 12000000000,
		Description = "Royal blue and gold, glowing runes and a star crystal in a rune ring.",
		Size = Vector3.new(1.95, 2.12, 1.0),
		Colors = {
			Body = rgb(40, 76, 172),
			Panel = rgb(22, 38, 98),
			Flap = rgb(34, 62, 150),
			Trim = rgb(238, 188, 84),
			Leather = rgb(128, 74, 40),
			Buckle = rgb(242, 194, 90),
			Roll = rgb(58, 104, 210),
			Gem = rgb(170, 236, 255),
			Glow = rgb(80, 200, 255),
			Stitch = rgb(150, 200, 255),
		},
	},
	{
		Id = "EmberforgePack",
		Name = "Emberforge Pack",
		Order = 9,
		Rarity = "Legendary",
		Capacity = 600,
		Price = 120000000000,
		Description = "Obsidian plates with lava seams, gold horns and two burning chimneys.",
		Size = Vector3.new(2.0, 2.2, 1.05),
		Colors = {
			Body = rgb(44, 36, 42),
			Panel = rgb(26, 22, 28),
			Flap = rgb(34, 28, 34),
			Trim = rgb(238, 178, 64),
			Leather = rgb(98, 36, 26),
			Buckle = rgb(246, 188, 72),
			Roll = rgb(152, 36, 30),
			Gem = rgb(255, 120, 30),
			Glow = rgb(255, 110, 20),
			Stitch = rgb(255, 150, 60),
		},
	},
	{
		Id = "StarforgePack",
		Name = "Starforge Pack",
		Order = 10,
		Rarity = "Mythic",
		Capacity = 1000,
		Price = 600000000000,
		Description = "Pearl and gold, a galaxy flap, a star crystal, orbiting stars and wings.",
		Size = Vector3.new(2.05, 2.25, 1.05),
		Colors = {
			Body = rgb(238, 234, 246),
			Panel = rgb(62, 32, 132),
			Flap = rgb(92, 56, 176),
			Trim = rgb(242, 198, 86),
			Leather = rgb(178, 138, 78),
			Buckle = rgb(248, 206, 98),
			Roll = rgb(234, 228, 248),
			Gem = rgb(120, 220, 255),
			Glow = rgb(160, 110, 255),
			Stitch = rgb(255, 226, 150),
		},
	},
} :: { Backpack }

BackpackData.ById = {} :: { [string]: Backpack }
BackpackData.Ids = {} :: { string } -- worst to best
for _, pack in BackpackData.List do
	BackpackData.ById[pack.Id] = pack
	table.insert(BackpackData.Ids, pack.Id)
end

--[[
	Ore chunks a pack holds: the one place the inventory reads capacity from
	(the "Návrhy strojů" BackpackService, data.Backpacks.Equipped; its Robux
	"double carrying" perk multiplies on its side). An unknown or missing id
	counts as the free starter pack. Ids are saved: keep them stable.
]]
function BackpackData.capacity(id: any): number
	local pack = if type(id) == "string" then BackpackData.ById[id] else nil
	return (pack or BackpackData.ById[BackpackData.StarterId]).Capacity
end

return BackpackData
