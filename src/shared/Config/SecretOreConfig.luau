--[[
	SECRET ores (owner 2026-10-29, PS99-style "secret" finds): every ore that
	drops from a rock may instead be a secret ore, with a tiny chance. Each
	mine floor has its own secret (Floor = a MineFloors Id); Rainbow Nova
	(Floor = nil) can come from any floor. The chance is "1 in OneIn" per ore
	that drops, before luck. Secret ores are OreData entries with Rarity
	"Secret" (looks: Builders/SecretOreShapes); they never sit in a rock's
	weights, they drop clean and Flawless (Grade).

	Balance (tools/lune/balance_sim.luau, Typical player): ores mined per floor
	Ember Caves ~380, Deep Hollow ~2,100, Sunken Palace ~1,200, Stormglass
	Rift ~2,200, then the Heartstone Core ~2,800 an hour: about 1 secret in the
	first 3 hours, ~1.3 by 8 h.
]]

local SecretOreConfig = {}

export type Secret = {
	Ore: string, -- OreData Id (Rarity "Secret")
	Floor: string?, -- MineFloors Id; nil = every floor
	OneIn: number, -- the chance per dropped ore before luck: 1 / OneIn
}

SecretOreConfig.List = {
	{ Ore = "FrostflameCrystal", Floor = "EmberCaves", OneIn = 2000 },
	{ Ore = "HollowEye", Floor = "DeepHollow", OneIn = 4000 },
	{ Ore = "TidecrownPearl", Floor = "SunkenPalace", OneIn = 8000 },
	{ Ore = "CagedLightning", Floor = "StormglassRift", OneIn = 15000 },
	{ Ore = "HeartOfTerra", Floor = "HeartstoneCore", OneIn = 40000 },
	{ Ore = "RainbowNova", Floor = nil, OneIn = 1000000 },
} :: { Secret }

-- The grade a secret ore drops with (it is born clean and shining).
SecretOreConfig.Grade = "Flawless"

SecretOreConfig.ByOre = {} :: { [string]: Secret }
for _, secret in SecretOreConfig.List do
	SecretOreConfig.ByOre[secret.Ore] = secret
end

function SecretOreConfig.isSecret(oreId: any): boolean
	return type(oreId) == "string" and SecretOreConfig.ByOre[oreId] ~= nil
end

-- The secrets an ore dropped on this floor can turn into (its own + the every-floor ones).
function SecretOreConfig.forFloor(floorId: string?): { Secret }
	local list = {}
	for _, secret in SecretOreConfig.List do
		if secret.Floor == nil or (floorId ~= nil and secret.Floor == floorId) then
			table.insert(list, secret)
		end
	end
	return list
end

-- "1 in 4,000" (thousands with commas, as the odds panels show it).
function SecretOreConfig.chanceText(oneIn: number): string
	local digits = tostring(math.floor(oneIn + 0.5))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "1 in " .. out
end

return SecretOreConfig
