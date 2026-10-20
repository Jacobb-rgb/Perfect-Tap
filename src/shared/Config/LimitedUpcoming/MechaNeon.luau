--[[
	An UPCOMING limited edition (owner's concept pick list, 2026-10-20):
	the MechaNeon set's 6 golem looks for the preview pictures only. Not in
	GolemConfig.List, not sold, no capsule: when the owner launches it, its
	golems move into GolemConfig.List (Edition = "MechaNeon"), it gets its capsule
	and products, and LimitedGolems.Current points at it.
	Costumes and shard: Builders/LimitedGear/MechaNeon.luau.
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
	Id = "MechaNeon",
	Title = "MECHA NEON",
	Tagline = "Chrome golems with neon power!",
	Backdrop = {
		SkyTop = rgb(14, 8, 40),
		SkyHorizon = rgb(220, 40, 170),
		Ground = rgb(28, 26, 44),
		Accent = rgb(0, 240, 255),
		Title = { rgb(120, 255, 255), rgb(255, 60, 200) },
	},
	Golems = {
		golem({
			Id = "BoltBot",
			Name = "Bolt Bot",
			Rarity = "Rare",
			Body = rgb(196, 204, 220),
			Trim = rgb(70, 76, 96),
			Glow = rgb(0, 230, 255),
			Material = M.Metal,
			Accessory = "NeonVisor",
			Scale = 1.1,
			Bonus = { Type = "MiningSpeed", Value = 0.12 },
			Lore = "Beeps when it finds ore. Beeps louder when it finds gold.",
			Edition = "MechaNeon",
		}),
		golem({
			Id = "BeatBot",
			Name = "Beat Bot",
			Rarity = "Rare",
			Body = rgb(255, 210, 60),
			Trim = rgb(60, 56, 80),
			Glow = rgb(255, 60, 200),
			Material = M.Metal,
			Accessory = "Headset",
			Scale = 1.1,
			Bonus = { Type = "WalkSpeed", Value = 0.12 },
			Lore = "Always dancing to music nobody else can hear.",
			Edition = "MechaNeon",
		}),
		golem({
			Id = "LaserRanger",
			Name = "Laser Ranger",
			Rarity = "Epic",
			Body = rgb(230, 236, 246),
			Trim = rgb(40, 70, 170),
			Glow = rgb(0, 255, 170),
			Material = M.Metal,
			Accessory = "MechaCrest",
			Scale = 1.15,
			Bonus = { Type = "Luck", Value = 0.18 },
			Lore = "Its scanner sees through rock. Hidden gems can't hide from it.",
			Edition = "MechaNeon",
		}),
		golem({
			Id = "RocketRex",
			Name = "Rocket Rex",
			Rarity = "Epic",
			Body = rgb(220, 50, 60),
			Trim = rgb(50, 46, 66),
			Glow = rgb(255, 230, 60),
			Material = M.Metal,
			Accessory = "Rockets",
			Scale = 1.15,
			Bonus = { Type = "MiningSpeed", Value = 0.18 },
			Lore = "Two rocket pods on its shoulders. They launch confetti.",
			Edition = "MechaNeon",
		}),
		golem({
			Id = "JetStriker",
			Name = "Jet Striker",
			Rarity = "Legendary",
			Body = rgb(72, 88, 130),
			Trim = rgb(24, 26, 40),
			Glow = rgb(0, 220, 255),
			Material = M.Metal,
			Accessory = "JetPack",
			Scale = 1.22,
			Bonus = { Type = "WalkSpeed", Value = 0.3 },
			Lore = "Its jet boots are always on. It hasn't touched the ground in years.",
			Edition = "MechaNeon",
		}),
		golem({
			Id = "OmegaMech",
			Name = "Omega Mech",
			Rarity = "Mythic",
			Body = rgb(236, 240, 250),
			Trim = rgb(30, 32, 52),
			Glow = rgb(255, 40, 190),
			Material = M.Metal,
			Accessory = "OmegaFrame",
			Scale = 1.3,
			Bonus = { Type = "Income", Value = 0.5 },
			Lore = "The last and greatest golem of the neon city. Its core runs on starlight.",
			Edition = "MechaNeon",
		}),
	},
}
