--[[
	Rarity tiers: colors, node behaviour and cleaning-minigame difficulty.
	Everything that scales with rarity lives here so balancing is one table.
]]

export type RarityInfo = {
	Id: string,
	Name: string,
	Order: number,
	Color: Color3,
	DarkColor: Color3,
	-- Mining
	RespawnTime: number, -- seconds before a shattered node regrows
	BonusChunkChance: number, -- chance of 1 extra chunk when the node shatters
	-- Cleaning minigame
	Cuts: number, -- number of chisel cuts
	Notches: number, -- how many of those cuts are V-shaped (two segments)
	Tolerance: number, -- allowed distance from the guide line (face radius units)
	MaxCutSpeed: number, -- faster than this (face radius units / s) = rough cut
	DirtGrid: number, -- dirt patches per side (N x N grid, clipped to the ore core)
	FragileSpots: number, -- glinting spots you should not scrape
	PolishTurns: number, -- full circles needed to polish
	Reveal: number, -- 1..3, how fancy the final reveal is
}

local Rarity = {}

Rarity.List = {
	{
		Id = "Common",
		Name = "Common",
		Order = 1,
		Color = Color3.fromRGB(201, 209, 217),
		DarkColor = Color3.fromRGB(92, 99, 107),
		RespawnTime = 18,
		BonusChunkChance = 0.35,
		Cuts = 2,
		Notches = 0,
		Tolerance = 0.11,
		MaxCutSpeed = 7,
		DirtGrid = 5,
		FragileSpots = 0,
		PolishTurns = 2.5,
		Reveal = 1,
	},
	{
		Id = "Uncommon",
		Name = "Uncommon",
		Order = 2,
		Color = Color3.fromRGB(94, 224, 106),
		DarkColor = Color3.fromRGB(32, 110, 44),
		RespawnTime = 28,
		BonusChunkChance = 0.3,
		Cuts = 3,
		Notches = 0,
		Tolerance = 0.095,
		MaxCutSpeed = 6.2,
		DirtGrid = 6,
		FragileSpots = 0,
		PolishTurns = 3,
		Reveal = 1,
	},
	{
		Id = "Rare",
		Name = "Rare",
		Order = 3,
		Color = Color3.fromRGB(61, 165, 255),
		DarkColor = Color3.fromRGB(20, 72, 140),
		RespawnTime = 45,
		BonusChunkChance = 0.25,
		Cuts = 3,
		Notches = 1,
		Tolerance = 0.082,
		MaxCutSpeed = 5.5,
		DirtGrid = 6,
		FragileSpots = 2,
		PolishTurns = 3.5,
		Reveal = 2,
	},
	{
		Id = "Epic",
		Name = "Epic",
		Order = 4,
		Color = Color3.fromRGB(180, 92, 255),
		DarkColor = Color3.fromRGB(80, 30, 130),
		RespawnTime = 65,
		BonusChunkChance = 0.2,
		Cuts = 4,
		Notches = 1,
		Tolerance = 0.072,
		MaxCutSpeed = 5,
		DirtGrid = 7,
		FragileSpots = 3,
		PolishTurns = 4,
		Reveal = 2,
	},
	{
		Id = "Legendary",
		Name = "Legendary",
		Order = 5,
		Color = Color3.fromRGB(255, 176, 32),
		DarkColor = Color3.fromRGB(140, 80, 0),
		RespawnTime = 95,
		BonusChunkChance = 0.15,
		Cuts = 5,
		Notches = 2,
		Tolerance = 0.062,
		MaxCutSpeed = 4.4,
		DirtGrid = 7,
		FragileSpots = 4,
		PolishTurns = 4.5,
		Reveal = 3,
	},
	{
		Id = "Mythic",
		Name = "Mythic",
		Order = 6,
		Color = Color3.fromRGB(255, 59, 122),
		DarkColor = Color3.fromRGB(130, 10, 50),
		RespawnTime = 150,
		BonusChunkChance = 0.1,
		Cuts = 6,
		Notches = 3,
		Tolerance = 0.052,
		MaxCutSpeed = 3.8,
		DirtGrid = 8,
		FragileSpots = 5,
		PolishTurns = 5,
		Reveal = 3,
	},
} :: { RarityInfo }

Rarity.ById = {} :: { [string]: RarityInfo }
for _, info in Rarity.List do
	Rarity.ById[info.Id] = info
end

function Rarity.get(id: string): RarityInfo
	local info = Rarity.ById[id]
	assert(info, "Unknown rarity: " .. tostring(id))
	return info
end

return Rarity
