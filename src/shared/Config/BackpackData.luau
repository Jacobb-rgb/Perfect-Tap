--[[
	The backpacks (owner 2026-10-24: "batohy od nejhoršího po nejlepší", after
	the blue rune backpack in his reference picture). Ten packs, worst to
	best; each one holds more ore (start 5, top 1000, owner 2026-10-24) and
	looks richer. Owner on the first proposal: the starter sack out, every
	pack needs far more detail and effects ("mega efektové a stylové").

	Owner on v2: "nejsi tak clean a do detailu ani tak dobre vypadajici
	jako na tom obrazku": v3 builds every pack from clean rounded panels with
	rims, like the reference. One anatomy (BackpackBuilder): a round-cornered
	bag with a leather bottom, a rimmed flap wrapping over the top (an inner
	panel on the richer packs), straps with prong buckles, a rimmed front
	pocket and side pouches, a bedroll with spiral ends and padded straps
	over the shoulders. Each pack adds its own pieces (a star charm, a tin
	mug, a lantern, a spyglass, crystals, runes, ember chimneys, wings) and
	from the Leather Rucksack up its effects (BackpackFx: glints, rising
	runes, fire and smoke, stars, a light). The Rookie Pack is a school bag
	with an arched top.

	Colors: Body (the bag), Panel (the flap's inner panel: steel, lava,
	galaxy ...), Flap, Trim (the rims: dark piping on the cheap packs, brass,
	copper, steel, silver, gold on the rich ones), Leather (straps, bottom),
	Buckle (buckles, rivets), Roll (the bedroll), Gem (the emblem crystal's
	core), Glow (Neon: runes, glows, the light; ItemBuilder.glowColor keeps
	it from blooming white).

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
		Description = "A cute school bag with a star charm, a bottle and a mini pickaxe.",
		Size = Vector3.new(1.45, 1.6, 0.74),
		Colors = {
			Body = rgb(236, 214, 166),
			Panel = rgb(214, 120, 48),
			Flap = rgb(240, 140, 58),
			Trim = rgb(176, 90, 40),
			Leather = rgb(122, 76, 44),
			Buckle = rgb(250, 206, 90),
			Roll = rgb(236, 214, 166),
			Gem = rgb(255, 214, 80),
			Glow = rgb(255, 214, 80),
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
		Size = Vector3.new(1.55, 1.7, 0.82),
		Colors = {
			Body = rgb(196, 182, 124),
			Panel = rgb(120, 76, 44),
			Flap = rgb(142, 90, 52),
			Trim = rgb(96, 60, 34),
			Leather = rgb(104, 64, 36),
			Buckle = rgb(186, 190, 198),
			Roll = rgb(98, 156, 76),
			Gem = rgb(98, 156, 76),
			Glow = rgb(98, 156, 76),
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
		Size = Vector3.new(1.62, 1.8, 0.86),
		Colors = {
			Body = rgb(166, 104, 58),
			Panel = rgb(96, 56, 30),
			Flap = rgb(128, 76, 42),
			Trim = rgb(226, 180, 82),
			Leather = rgb(84, 50, 28),
			Buckle = rgb(234, 186, 84),
			Roll = rgb(96, 140, 72),
			Gem = rgb(234, 186, 84),
			Glow = rgb(255, 205, 100),
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
		Size = Vector3.new(1.72, 1.9, 0.9),
		Colors = {
			Body = rgb(120, 114, 72),
			Panel = rgb(86, 80, 50),
			Flap = rgb(112, 70, 42),
			Trim = rgb(206, 118, 64),
			Leather = rgb(82, 52, 30),
			Buckle = rgb(214, 126, 70),
			Roll = rgb(130, 132, 140),
			Gem = rgb(214, 126, 70),
			Glow = rgb(255, 170, 60),
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
		Size = Vector3.new(1.8, 1.98, 0.95),
		Colors = {
			Body = rgb(74, 88, 112),
			Panel = rgb(150, 158, 172),
			Flap = rgb(60, 72, 94),
			Trim = rgb(190, 198, 210),
			Leather = rgb(84, 56, 38),
			Buckle = rgb(200, 208, 220),
			Roll = rgb(98, 130, 172),
			Gem = rgb(40, 120, 230),
			Glow = rgb(61, 165, 255),
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
		Size = Vector3.new(1.85, 2.02, 0.96),
		Colors = {
			Body = rgb(58, 116, 86),
			Panel = rgb(34, 70, 52),
			Flap = rgb(48, 98, 72),
			Trim = rgb(232, 184, 84),
			Leather = rgb(114, 70, 40),
			Buckle = rgb(240, 194, 88),
			Roll = rgb(196, 62, 52),
			Gem = rgb(240, 194, 88),
			Glow = rgb(60, 230, 180),
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
		Size = Vector3.new(1.92, 2.1, 1.0),
		Colors = {
			Body = rgb(104, 60, 164),
			Panel = rgb(178, 150, 226),
			Flap = rgb(90, 50, 146),
			Trim = rgb(222, 226, 238),
			Leather = rgb(70, 44, 60),
			Buckle = rgb(232, 236, 246),
			Roll = rgb(182, 156, 220),
			Gem = rgb(110, 70, 255),
			Glow = rgb(178, 110, 255),
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
		Size = Vector3.new(2.0, 2.2, 1.0),
		Colors = {
			Body = rgb(46, 88, 200),
			Panel = rgb(20, 32, 88),
			Flap = rgb(42, 82, 192),
			Trim = rgb(240, 192, 82),
			Leather = rgb(124, 74, 42),
			Buckle = rgb(246, 198, 92),
			Roll = rgb(38, 72, 172),
			Gem = rgb(200, 244, 255),
			Glow = rgb(110, 215, 255),
		},
	},
	{
		Id = "EmberforgePack",
		Name = "Emberforge Pack",
		Order = 9,
		Rarity = "Legendary",
		Capacity = 600,
		Price = 120000000000,
		Description = "Obsidian with glowing lava cracks, gold horns and two burning chimneys.",
		Size = Vector3.new(2.04, 2.26, 1.05),
		Colors = {
			Body = rgb(46, 38, 46),
			Panel = rgb(26, 20, 26),
			Flap = rgb(36, 30, 36),
			Trim = rgb(240, 180, 66),
			Leather = rgb(100, 38, 28),
			Buckle = rgb(246, 190, 74),
			Roll = rgb(156, 38, 32),
			Gem = rgb(255, 100, 30),
			Glow = rgb(255, 50, 8),
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
		Size = Vector3.new(2.08, 2.3, 1.05),
		Colors = {
			Body = rgb(240, 236, 248),
			Panel = rgb(64, 34, 140),
			Flap = rgb(232, 226, 246),
			Trim = rgb(244, 200, 90),
			Leather = rgb(182, 142, 82),
			Buckle = rgb(248, 208, 100),
			Roll = rgb(122, 88, 214),
			Gem = rgb(130, 225, 255),
			Glow = rgb(165, 115, 255),
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
