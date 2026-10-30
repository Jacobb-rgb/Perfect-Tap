--[[
	SECRET ores (owner 2026-10-29, PS99-style "secret" finds): every ore that
	drops from a rock may instead be a secret ore, with a tiny chance. Each
	mine floor has its own secret (Floor = a MineFloors Id); Rainbow Nova
	(Floor = nil) can come from any floor. The chance is "1 in OneIn" per ore
	that drops, before luck. Secret ores are OreData entries with Rarity
	"Secret" (looks: Builders/SecretOreShapes); they never sit in a rock's
	weights. Owner 2026-10-29 (answers to the concept): a secret drops as a
	SPARKLY dirty ore (rainbow glints: "something special inside") and the
	jackpot plays when the player cleans it; it comes out Flawless (Grade).
	Luck raises the chance by its square root (BoostConfig.LuckPower.Secret:
	at most x2.5). Rainbow Nova is announced on every server.
	Stars = how big the jackpot is (Effects/SecretReveal: rarer = bigger).

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
	Stars: number, -- 1..3: the jackpot's size (more shockwaves, rays, a longer show)
}

SecretOreConfig.List = {
	{ Ore = "FrostflameCrystal", Floor = "EmberCaves", OneIn = 2000, Stars = 1 },
	{ Ore = "HollowEye", Floor = "DeepHollow", OneIn = 4000, Stars = 1 },
	{ Ore = "TidecrownPearl", Floor = "SunkenPalace", OneIn = 8000, Stars = 1 },
	{ Ore = "CagedLightning", Floor = "StormglassRift", OneIn = 15000, Stars = 2 },
	{ Ore = "HeartOfTerra", Floor = "HeartstoneCore", OneIn = 40000, Stars = 2 },
	{ Ore = "RainbowNova", Floor = nil, OneIn = 1000000, Stars = 3 },
} :: { Secret }

-- The secret rainbow, red to violet (SecretOreShapes.Rainbow, SecretOreFx.Rainbow: the same six).
SecretOreConfig.Rainbow = {
	Color3.fromRGB(255, 70, 96),
	Color3.fromRGB(255, 156, 48),
	Color3.fromRGB(255, 228, 64),
	Color3.fromRGB(80, 236, 120),
	Color3.fromRGB(64, 156, 255),
	Color3.fromRGB(176, 92, 255),
}

-- The grade a secret ore comes out of the cleaning with.
SecretOreConfig.Grade = "Flawless"

SecretOreConfig.ByOre = {} :: { [string]: Secret }
for _, secret in SecretOreConfig.List do
	SecretOreConfig.ByOre[secret.Ore] = secret
end

-- Luck (StatConfig.oreLuck: x1 .. x6.25) raises a secret's chance by its square root, at most x2.5.
SecretOreConfig.LuckPower = 0.5
SecretOreConfig.MaxLuckMult = 2.5

-- The chance multiplier at ore luck `luck` (broken or below x1: x1).
function SecretOreConfig.luckMult(luck: any): number
	if type(luck) ~= "number" or luck ~= luck or luck <= 1 or luck == math.huge then
		return 1 -- broken luck counts as none (like BoostConfig)
	end
	return math.min(luck ^ SecretOreConfig.LuckPower, SecretOreConfig.MaxLuckMult)
end

-- The chance (0..1) that a dropped ore turns into this secret at ore luck `luck`.
function SecretOreConfig.chance(secret: Secret, luck: any): number
	return SecretOreConfig.luckMult(luck) / secret.OneIn
end

-- "1 in N" with luck applied (what the odds panels show; N rounded to a whole number).
function SecretOreConfig.oddsText(secret: Secret, luck: any): string
	return SecretOreConfig.chanceText(math.max(1, math.floor(secret.OneIn / SecretOreConfig.luckMult(luck) + 0.5)))
end

--[[
	The server's roll for one dropped ore on floor `floorId`: the secret it
	turns into, or nil. The rarest is rolled first (Rainbow Nova, then the
	floor's own), one draw each from `random` (0..1).
]]
function SecretOreConfig.roll(floorId: string?, luck: any, random: () -> number): string?
	local list = SecretOreConfig.forFloor(floorId)
	table.sort(list, function(a, b)
		return a.OneIn > b.OneIn
	end)
	for _, secret in list do
		if random() < SecretOreConfig.chance(secret, luck) then
			return secret.Ore
		end
	end
	return nil
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
