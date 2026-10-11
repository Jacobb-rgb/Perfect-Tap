--[[
	Pickaxes and carry upgrades (bought at Forgemaster Ulda's Tool Smithy).
]]

export type Pickaxe = {
	Id: string,
	Name: string,
	Tier: number,
	Damage: number,
	Cooldown: number,
	Price: number,
	HeadColor: Color3,
	HeadMaterial: Enum.Material,
	Glow: boolean,
}

export type CarryLevel = {
	Level: number,
	Name: string,
	Capacity: number,
	Price: number,
}

local ToolData = {}

ToolData.Pickaxes = {
	{
		Id = "StonePick",
		Name = "Stone Pickaxe",
		Tier = 1,
		Damage = 2,
		Cooldown = 0.6,
		Price = 0,
		HeadColor = Color3.fromRGB(130, 128, 124),
		HeadMaterial = Enum.Material.Slate,
		Glow = false,
	},
	{
		Id = "CopperPick",
		Name = "Copper Pickaxe",
		Tier = 2,
		Damage = 3,
		Cooldown = 0.55,
		Price = 200,
		HeadColor = Color3.fromRGB(222, 120, 60),
		HeadMaterial = Enum.Material.Metal,
		Glow = false,
	},
	{
		Id = "IronPick",
		Name = "Iron Pickaxe",
		Tier = 3,
		Damage = 5,
		Cooldown = 0.5,
		Price = 900,
		HeadColor = Color3.fromRGB(176, 182, 194),
		HeadMaterial = Enum.Material.Metal,
		Glow = false,
	},
	{
		Id = "EmberPick",
		Name = "Emberite Pickaxe",
		Tier = 4,
		Damage = 8,
		Cooldown = 0.45,
		Price = 3500,
		HeadColor = Color3.fromRGB(255, 96, 36),
		HeadMaterial = Enum.Material.Metal,
		Glow = true,
	},
	{
		Id = "AzurePick",
		Name = "Azurium Pickaxe",
		Tier = 5,
		Damage = 12,
		Cooldown = 0.42,
		Price = 12000,
		HeadColor = Color3.fromRGB(52, 128, 255),
		HeadMaterial = Enum.Material.Metal,
		Glow = true,
	},
	{
		Id = "StormPick",
		Name = "Stormcore Pickaxe",
		Tier = 6,
		Damage = 18,
		Cooldown = 0.38,
		Price = 40000,
		HeadColor = Color3.fromRGB(122, 104, 255),
		HeadMaterial = Enum.Material.Metal,
		Glow = true,
	},
	{
		Id = "SolarPick",
		Name = "Solarite Pickaxe",
		Tier = 7,
		Damage = 28,
		Cooldown = 0.34,
		Price = 125000,
		HeadColor = Color3.fromRGB(255, 232, 140),
		HeadMaterial = Enum.Material.Metal,
		Glow = true,
	},
} :: { Pickaxe }

ToolData.PickaxeById = {} :: { [string]: Pickaxe }
for _, pickaxe in ToolData.Pickaxes do
	ToolData.PickaxeById[pickaxe.Id] = pickaxe
end

ToolData.CarryLevels = {
	{ Level = 1, Name = "Bare Hands", Capacity = 1, Price = 0 },
	{ Level = 2, Name = "Ore Sling", Capacity = 2, Price = 300 },
	{ Level = 3, Name = "Miner's Harness", Capacity = 3, Price = 1500 },
	{ Level = 4, Name = "Ore Frame", Capacity = 5, Price = 6000 },
	{ Level = 5, Name = "Titan Frame", Capacity = 8, Price = 25000 },
} :: { CarryLevel }

ToolData.DefaultPickaxe = "StonePick"

function ToolData.carryCapacity(level: number, hasStrongBack: boolean): number
	local info = ToolData.CarryLevels[math.clamp(level, 1, #ToolData.CarryLevels)]
	return info.Capacity * (if hasStrongBack then 2 else 1)
end

return ToolData
