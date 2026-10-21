--[[
	An UPCOMING limited edition (owner's concept pick list, 2026-10-20):
	the FrostTitans set's 6 golem looks for the preview pictures only. Not in
	GolemConfig.List, not sold, no capsule: when the owner launches it, its
	golems move into GolemConfig.List (Edition = "FrostTitans"), it gets its capsule
	and products, and LimitedGolems.Current points at it.
	Costumes and shard: Builders/LimitedGear/FrostTitans.luau.
]]

local GolemConfig = require(script.Parent.Parent.GolemConfig)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

local function golem(entry: { [string]: any }): GolemConfig.Golem
	return (entry :: any) :: GolemConfig.Golem
end

return {
	Id = "FrostTitans",
	Title = "FROST TITANS",
	Tagline = "Golems from the frozen north!",
	Backdrop = {
		SkyTop = rgb(8, 20, 50),
		SkyHorizon = rgb(60, 200, 170),
		Ground = rgb(196, 222, 240),
		Accent = rgb(110, 255, 210),
		Title = { rgb(240, 255, 255), rgb(70, 190, 255) },
	},
	Golems = {
		golem({
			Id = "Frostling",
			Name = "Frostling",
			Rarity = "Rare",
			Body = rgb(130, 196, 245),
			Trim = rgb(80, 140, 200),
			Glow = rgb(60, 200, 255),
			Material = M.Ice,
			Accessory = "IcicleHair",
			Scale = 1.1,
			Bonus = { Type = "WalkSpeed", Value = 0.12 },
			Lore = "Its icicle hair never melts, not even next to the furnace.",
			Edition = "FrostTitans",
		}),
		golem({
			Id = "GlacierCub",
			Name = "Glacier Cub",
			Rarity = "Rare",
			Body = rgb(220, 240, 255),
			Trim = rgb(120, 170, 220),
			Glow = rgb(70, 170, 255),
			Material = M.Ice,
			Accessory = "Beanie",
			Scale = 1.1,
			Bonus = { Type = "SellValue", Value = 0.12 },
			Lore = "Made of ice, and still always cold. Grandma knitted the hat.",
			Edition = "FrostTitans",
		}),
		golem({
			Id = "IceKnight",
			Name = "Icebound Knight",
			Rarity = "Epic",
			Body = rgb(104, 164, 232),
			Trim = rgb(40, 90, 170),
			Glow = rgb(100, 230, 255),
			Material = M.Ice,
			Accessory = "FrostHelm",
			Scale = 1.15,
			Bonus = { Type = "MiningSpeed", Value = 0.18 },
			Lore = "Guards the glacier gates. Its sword is a very sharp icicle.",
			Edition = "FrostTitans",
		}),
		golem({
			Id = "BlizzardSage",
			Name = "Blizzard Sage",
			Rarity = "Epic",
			Body = rgb(74, 104, 200),
			Trim = rgb(40, 50, 120),
			Glow = rgb(140, 255, 240),
			Material = M.Ice,
			Accessory = "SnowCloud",
			Scale = 1.15,
			Bonus = { Type = "Luck", Value = 0.18 },
			Lore = "Carries its own little snow cloud. It snows only on bad luck.",
			Edition = "FrostTitans",
		}),
		golem({
			Id = "PolarTitan",
			Name = "Polar Titan",
			Rarity = "Legendary",
			Body = rgb(166, 214, 248),
			Trim = rgb(70, 130, 200),
			Glow = rgb(0, 210, 255),
			Material = M.Ice,
			Accessory = "IcicleCrown",
			Scale = 1.22,
			Bonus = { Type = "SellValue", Value = 0.3 },
			Lore = "King of the north: a horned ice helm, ivory tusks and an axe of glacier ice.",
			Edition = "FrostTitans",
		}),
		golem({
			Id = "AuroraColossus",
			Name = "Aurora Colossus",
			Rarity = "Mythic",
			Body = rgb(108, 176, 244),
			Trim = rgb(50, 70, 150),
			Glow = rgb(90, 255, 190),
			Material = M.Ice,
			Accessory = "AuroraCrown",
			Scale = 1.3,
			Bonus = { Type = "Income", Value = 0.5 },
			Lore = "The northern lights dance around its crown. Nobody has seen it melt.",
			Edition = "FrostTitans",
		}),
	},
}
