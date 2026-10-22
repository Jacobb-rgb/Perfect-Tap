--[[
	The SKY EGG's golems (islands chat proposal, 2026-10-22): a coin egg on
	the SKY HAVEN island with only three golems, better than the Crystal egg
	and still below the Robux eggs. PREVIEW LOOKS for the owner's pictures
	only: not real kinds (not in GolemConfig.List, never sold) until the
	owner says yes to the golems and the price; then they move into
	GolemConfig.List and CapsuleConfig gets its "Sky" entry.
	Costumes: Builders/LimitedGear/Sky.luau (Edition = "Sky").

	  Sky Sprite     Epic       Luck 0.11          84 %
	  Storm Warden   Legendary  MiningSpeed 0.26   14 %
	  Aether King    Mythic     Income 0.42         2 %
]]

local GolemConfig = require(script.Parent.Parent.GolemConfig)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function golem(entry: { [string]: any }): GolemConfig.Golem
	return (entry :: any) :: GolemConfig.Golem
end

return {
	golem({
		Id = "SkySprite",
		Name = "Sky Sprite",
		Rarity = "Epic",
		Body = rgb(236, 244, 255),
		Trim = rgb(130, 190, 240),
		Glow = rgb(110, 210, 255),
		Material = Enum.Material.SmoothPlastic,
		Accessory = "SkyPuff",
		Scale = 1.15,
		Bonus = { Type = "Luck", Value = 0.11 },
		Lore = "Born in a cloud over Sky Haven. It naps on the wind.",
		Edition = "Sky",
	}),
	golem({
		Id = "StormWarden",
		Name = "Storm Warden",
		Rarity = "Legendary",
		Body = rgb(70, 84, 118),
		Trim = rgb(40, 48, 74),
		Glow = rgb(255, 226, 80),
		Material = Enum.Material.Slate,
		Accessory = "StormArmor",
		Scale = 1.22,
		Bonus = { Type = "MiningSpeed", Value = 0.26 },
		Lore = "Guards the island's edge. Every step it takes is a thunderclap.",
		Edition = "Sky",
	}),
	golem({
		Id = "AetherKing",
		Name = "Aether King",
		Rarity = "Mythic",
		Body = rgb(250, 248, 240),
		Trim = rgb(255, 196, 56),
		Glow = rgb(120, 220, 255),
		Material = Enum.Material.SmoothPlastic,
		Accessory = "AetherWings",
		Scale = 1.3,
		Bonus = { Type = "Income", Value = 0.42 },
		Lore = "Rules the sky over Sky Haven. The clouds part where it walks.",
		Edition = "Sky",
	}),
}
