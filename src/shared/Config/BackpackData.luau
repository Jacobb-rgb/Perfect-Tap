--[[
	The backpacks (owner 2026-10-24: "batohy od nejhoršího po nejlepší", after
	the blue rune backpack in his reference picture). Ten packs, worst to
	best; each one holds more ore (start 5, top 1000, owner 2026-10-24) and
	looks richer: a burlap sack, then canvas, leather, iron, brass, crystal,
	the rune pack from the picture, the ember forge pack and the star pack.

	Every pack after the sack shares one anatomy (BackpackBuilder): a body, a
	flap over the top with a clasp or gem, a front pocket with two straps and
	buckles, side pockets, a bedroll on top and a leather bottom. Higher packs
	add trim, rivets, glowing runes, crystals and finally a halo and wings.

	Colors: Body (the bag), Panel (darker inset panels / seams), Flap, Trim
	(edge strips, from the Iron-Bound Pack up), Leather (straps, bottom),
	Buckle (buckles, rivets), Roll (the bedroll), Gem (the clasp gem's body),
	Glow (Neon: runes, the gem's light; ItemBuilder.glowColor keeps it from
	blooming white).

	PROPOSAL (art/backpacks): capacities and coin prices are a first guess
	on the 6-floor curve (BALANCE_SIM.md: blaster 4 ~710K at 27 min, blaster
	6 ~73M at 1h20, blaster 8 ~2.2B at 3h16, blaster 10 ~290B at 8 h); the
	balance sim tunes them once the backpack inventory is in the game.
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
	Order: number, -- 1 = the starter sack
	Rarity: string, -- Rarity.ById key (card and name colour)
	Capacity: number, -- ore chunks it holds
	Price: number, -- coins (0 = everyone starts with it)
	Description: string,
	Size: Vector3, -- the bag body (X wide, Y tall, Z deep), for the builder
	Colors: Colors,
}

local rgb = Color3.fromRGB

local BackpackData = {}

BackpackData.StarterId = "BurlapSack"

BackpackData.List = {
	{
		Id = "BurlapSack",
		Name = "Burlap Sack",
		Order = 1,
		Rarity = "Common",
		Capacity = 5,
		Price = 0,
		Description = "An old ore sack tied with rope. Better than nothing.",
		Size = Vector3.new(1.35, 1.3, 0.85),
		Colors = {
			Body = rgb(196, 160, 112),
			Panel = rgb(156, 122, 80),
			Flap = rgb(176, 140, 94),
			Trim = rgb(156, 122, 80),
			Leather = rgb(120, 84, 52),
			Buckle = rgb(120, 84, 52),
			Roll = rgb(176, 140, 94),
			Gem = rgb(176, 140, 94),
			Glow = rgb(176, 140, 94),
		},
	},
	{
		Id = "CanvasPack",
		Name = "Canvas Pack",
		Order = 2,
		Rarity = "Common",
		Capacity = 15,
		Price = 250,
		Description = "A sturdy canvas pack with a leather flap and a tin mug.",
		Size = Vector3.new(1.45, 1.6, 0.8),
		Colors = {
			Body = rgb(214, 196, 150),
			Panel = rgb(176, 156, 110),
			Flap = rgb(146, 96, 58),
			Trim = rgb(146, 96, 58),
			Leather = rgb(120, 76, 44),
			Buckle = rgb(150, 154, 160),
			Roll = rgb(176, 156, 110),
			Gem = rgb(150, 154, 160),
			Glow = rgb(150, 154, 160),
		},
	},
	{
		Id = "LeatherRucksack",
		Name = "Leather Rucksack",
		Order = 3,
		Rarity = "Uncommon",
		Capacity = 30,
		Price = 5000,
		Description = "Brown leather, brass buckles and a bedroll for long digs.",
		Size = Vector3.new(1.55, 1.75, 0.85),
		Colors = {
			Body = rgb(156, 98, 56),
			Panel = rgb(118, 70, 38),
			Flap = rgb(118, 70, 38),
			Trim = rgb(96, 58, 32),
			Leather = rgb(92, 56, 32),
			Buckle = rgb(226, 178, 78),
			Roll = rgb(98, 140, 72),
			Gem = rgb(226, 178, 78),
			Glow = rgb(226, 178, 78),
		},
	},
	{
		Id = "MinersPack",
		Name = "Miner's Pack",
		Order = 4,
		Rarity = "Uncommon",
		Capacity = 60,
		Price = 120000,
		Description = "A miner's pack with copper rivets, a rope and a lantern.",
		Size = Vector3.new(1.65, 1.85, 0.9),
		Colors = {
			Body = rgb(110, 104, 70),
			Panel = rgb(84, 78, 50),
			Flap = rgb(104, 66, 40),
			Trim = rgb(196, 112, 62),
			Leather = rgb(84, 52, 30),
			Buckle = rgb(208, 120, 66),
			Roll = rgb(126, 128, 134),
			Gem = rgb(208, 120, 66),
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
		Description = "Iron corners, rivets and a blue gem clasp. Built to last.",
		Size = Vector3.new(1.75, 1.95, 0.95),
		Colors = {
			Body = rgb(70, 82, 102),
			Panel = rgb(52, 60, 76),
			Flap = rgb(58, 68, 86),
			Trim = rgb(150, 158, 170),
			Leather = rgb(82, 54, 36),
			Buckle = rgb(176, 184, 196),
			Roll = rgb(96, 128, 168),
			Gem = rgb(40, 110, 210),
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
		Description = "Brass trim, a map tube and a compass that points to ore.",
		Size = Vector3.new(1.8, 2.0, 0.95),
		Colors = {
			Body = rgb(62, 112, 84),
			Panel = rgb(44, 84, 62),
			Flap = rgb(50, 94, 70),
			Trim = rgb(226, 178, 78),
			Leather = rgb(110, 68, 38),
			Buckle = rgb(236, 190, 84),
			Roll = rgb(186, 62, 52),
			Gem = rgb(236, 190, 84),
			Glow = rgb(80, 220, 170),
		},
	},
	{
		Id = "AmethystPack",
		Name = "Amethyst Pack",
		Order = 7,
		Rarity = "Epic",
		Capacity = 275,
		Price = 900000000,
		Description = "Silver trim and a glowing amethyst cluster on the flap.",
		Size = Vector3.new(1.85, 2.05, 1.0),
		Colors = {
			Body = rgb(98, 58, 150),
			Panel = rgb(70, 38, 112),
			Flap = rgb(84, 48, 132),
			Trim = rgb(214, 218, 230),
			Leather = rgb(70, 46, 54),
			Buckle = rgb(226, 230, 240),
			Roll = rgb(176, 150, 214),
			Gem = rgb(170, 90, 255),
			Glow = rgb(190, 100, 255),
		},
	},
	{
		Id = "RuneboundPack",
		Name = "Runebound Pack",
		Order = 8,
		Rarity = "Epic",
		Capacity = 400,
		Price = 12000000000,
		Description = "Royal blue with gold trim, glowing runes and a star crystal.",
		Size = Vector3.new(1.95, 2.1, 1.0),
		Colors = {
			Body = rgb(40, 74, 168),
			Panel = rgb(26, 46, 112),
			Flap = rgb(34, 62, 150),
			Trim = rgb(236, 186, 84),
			Leather = rgb(126, 74, 40),
			Buckle = rgb(240, 192, 88),
			Roll = rgb(58, 104, 210),
			Gem = rgb(200, 236, 255),
			Glow = rgb(90, 200, 255),
		},
	},
	{
		Id = "EmberforgePack",
		Name = "Emberforge Pack",
		Order = 9,
		Rarity = "Legendary",
		Capacity = 600,
		Price = 120000000000,
		Description = "Obsidian plates with lava seams, gold and two ember chimneys.",
		Size = Vector3.new(2.0, 2.2, 1.05),
		Colors = {
			Body = rgb(40, 34, 40),
			Panel = rgb(24, 20, 26),
			Flap = rgb(32, 26, 32),
			Trim = rgb(236, 176, 64),
			Leather = rgb(96, 36, 26),
			Buckle = rgb(244, 186, 70),
			Roll = rgb(150, 36, 30),
			Gem = rgb(255, 120, 40),
			Glow = rgb(255, 110, 20),
		},
	},
	{
		Id = "StarforgePack",
		Name = "Starforge Pack",
		Order = 10,
		Rarity = "Mythic",
		Capacity = 1000,
		Price = 600000000000,
		Description = "Pearl and gold with a star crystal, star shards and wings.",
		Size = Vector3.new(2.05, 2.25, 1.05),
		Colors = {
			Body = rgb(236, 232, 244),
			Panel = rgb(70, 40, 140),
			Flap = rgb(92, 56, 176),
			Trim = rgb(240, 196, 84),
			Leather = rgb(176, 136, 76),
			Buckle = rgb(246, 204, 96),
			Roll = rgb(232, 226, 246),
			Gem = rgb(120, 220, 255),
			Glow = rgb(150, 110, 255),
		},
	},
} :: { Backpack }

BackpackData.ById = {} :: { [string]: Backpack }
BackpackData.Ids = {} :: { string } -- worst to best
for _, pack in BackpackData.List do
	BackpackData.ById[pack.Id] = pack
	table.insert(BackpackData.Ids, pack.Id)
end

return BackpackData
