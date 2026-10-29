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
	-- Cleaning minigame (spray-washing, CleaningPatterns / SprayScoring)
	DirtThickness: number, -- how thick the dirt is (1 = a Common clump; more = longer to wash off)
	FragileSpots: number, -- glowing crystals in the dirt: spraying one point-blank too long cracks it
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
		DirtThickness = 1.0,
		FragileSpots = 0,
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
		DirtThickness = 1.12,
		FragileSpots = 0,
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
		DirtThickness = 1.25,
		FragileSpots = 2,
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
		DirtThickness = 1.4,
		FragileSpots = 3,
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
		DirtThickness = 1.55,
		FragileSpots = 4,
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
		DirtThickness = 1.7,
		FragileSpots = 5,
		Reveal = 3,
	},
	-- (owner 2026-10-29) Secret ores (SecretOreConfig) drop clean, so the mining and cleaning
	-- numbers only matter if one ever reaches a rock or a cleaner: they behave like Mythic.
	{
		Id = "Secret",
		Name = "Secret",
		Order = 7,
		Color = Color3.fromRGB(255, 120, 230),
		DarkColor = Color3.fromRGB(24, 14, 36),
		RespawnTime = 150,
		BonusChunkChance = 0.1,
		DirtThickness = 1.7,
		FragileSpots = 5,
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
