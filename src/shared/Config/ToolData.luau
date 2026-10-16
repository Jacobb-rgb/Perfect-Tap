--[[
	Carry upgrades (bought at Forgemaster Ulda's Tool Smithy).
	Mining tools are laser blasters now: see BlasterData.
]]

export type CarryLevel = {
	Level: number,
	Name: string,
	Capacity: number,
	Price: number,
}

local ToolData = {}

ToolData.CarryLevels = {
	{ Level = 1, Name = "Bare Hands", Capacity = 1, Price = 0 },
	{ Level = 2, Name = "Ore Sling", Capacity = 2, Price = 300 },
	{ Level = 3, Name = "Miner's Harness", Capacity = 3, Price = 1500 },
	{ Level = 4, Name = "Ore Frame", Capacity = 5, Price = 6000 },
	{ Level = 5, Name = "Titan Frame", Capacity = 8, Price = 25000 },
} :: { CarryLevel }

function ToolData.carryCapacity(level: number, hasStrongBack: boolean): number
	local info = ToolData.CarryLevels[math.clamp(level, 1, #ToolData.CarryLevels)]
	return info.Capacity * (if hasStrongBack then 2 else 1)
end

return ToolData
