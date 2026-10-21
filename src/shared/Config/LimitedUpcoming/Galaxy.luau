--[[
	An UPCOMING limited edition (owner's concept pick list, 2026-10-20):
	the Galaxy set's 6 golem looks for the preview pictures only. Not in
	GolemConfig.List, not sold, no capsule: when the owner launches it, its
	golems move into GolemConfig.List (Edition = "Galaxy"), it gets its capsule
	and products, and LimitedGolems.Current points at it.
	Costumes and shard: Builders/LimitedGear/Galaxy.luau.
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
	Id = "Galaxy",
	Title = "GALAXY GOLEMS",
	Tagline = "Golems from beyond the stars!",
	Backdrop = {
		SkyTop = rgb(10, 8, 34),
		SkyHorizon = rgb(120, 50, 170),
		Ground = rgb(36, 32, 70),
		Accent = rgb(80, 230, 255),
		Title = { rgb(150, 248, 255), rgb(170, 90, 255) },
	},
	Golems = {
		golem({
			Id = "AstroCadet",
			Name = "Astro Cadet",
			Rarity = "Rare",
			Body = rgb(226, 232, 248),
			Trim = rgb(70, 90, 170),
			Glow = rgb(90, 230, 255),
			Material = M.Slate,
			Accessory = "SpaceHelmet",
			Scale = 1.1,
			Bonus = { Type = "WalkSpeed", Value = 0.12 },
			Lore = "Its first space walk was yesterday. It still won't take the helmet off.",
			Edition = "Galaxy",
		}),
		golem({
			Id = "CometCub",
			Name = "Comet Cub",
			Rarity = "Rare",
			Body = rgb(250, 150, 60),
			Trim = rgb(150, 70, 30),
			Glow = rgb(255, 226, 100),
			Material = M.Slate,
			Accessory = "Comet",
			Scale = 1.1,
			Bonus = { Type = "MiningSpeed", Value = 0.12 },
			Lore = "Fell from the sky with a comet on its head. The comet stayed.",
			Edition = "Galaxy",
		}),
		golem({
			Id = "OrbitKeeper",
			Name = "Orbit Keeper",
			Rarity = "Epic",
			Body = rgb(110, 60, 190),
			Trim = rgb(56, 28, 110),
			Glow = rgb(120, 240, 255),
			Material = M.Slate,
			Accessory = "Orbiters",
			Scale = 1.15,
			Bonus = { Type = "Luck", Value = 0.18 },
			Lore = "Two tiny moons circle its head. It knows both of them by name.",
			Edition = "Galaxy",
		}),
		golem({
			Id = "CosmoWizard",
			Name = "Cosmo Wizard",
			Rarity = "Epic",
			Body = rgb(46, 40, 130),
			Trim = rgb(24, 20, 70),
			Glow = rgb(255, 120, 230),
			Material = M.Slate,
			Accessory = "StarHat",
			Scale = 1.15,
			Bonus = { Type = "SellValue", Value = 0.2 },
			Lore = "Reads the stars like a shopping list. The stars say: sell now.",
			Edition = "Galaxy",
		}),
		golem({
			Id = "NovaGuardian",
			Name = "Nova Guardian",
			Rarity = "Legendary",
			Body = rgb(40, 56, 150),
			Trim = rgb(220, 170, 60),
			Glow = rgb(80, 240, 255),
			Material = M.Slate,
			Accessory = "StarCrown",
			Scale = 1.22,
			Bonus = { Type = "Luck", Value = 0.3 },
			Lore = "Born in a star's last flash. A ring of light still follows it.",
			Edition = "Galaxy",
		}),
		golem({
			Id = "NebulaTitan",
			Name = "Nebula Titan",
			Rarity = "Mythic",
			Body = rgb(100, 44, 176),
			Trim = rgb(40, 16, 86),
			Glow = rgb(255, 110, 240),
			Material = M.Slate,
			Accessory = "NebulaCrown",
			Scale = 1.3,
			Bonus = { Type = "Income", Value = 0.5 },
			Lore = "Made of a whole nebula, squeezed very small. Planets orbit its crown.",
			Edition = "Galaxy",
		}),
	},
}
