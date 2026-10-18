--[[
	DEPRECATED shim (steps 6-7): carrying is the Backpack gear line now
	(GearConfig, data.Gear.Backpack, bought at the Gear shop). data.CarryLevel
	is gone: Migrations folds it into Gear.Backpack (old CarryLevel N =
	Backpack level N - 1, the capacities match). New code reads
	GearConfig.carryCapacity(data.Gear, strongBack) or Bonuses.

	The old API keeps working on old CarryLevel numbers (1-based):
	CarryLevels[N] is Backpack level N - 1, carryCapacity(N, strong) its capacity.
	Mining tools are laser blasters now: see BlasterData.
]]

local GearConfig = require(script.Parent.GearConfig)

export type CarryLevel = {
	Level: number,
	Name: string,
	Capacity: number,
	Price: number,
}

local ToolData = {}

local BACKPACK = GearConfig.ById.Backpack

ToolData.CarryLevels = {} :: { CarryLevel }
for level = 0, GearConfig.MaxLevel do
	table.insert(ToolData.CarryLevels, {
		Level = level + 1,
		Name = if level == 0 then "Bare Hands" else `{BACKPACK.Name} {level}`,
		Capacity = GearConfig.value("Backpack", level),
		Price = if level == 0 then 0 else BACKPACK.Prices[level],
	})
end

-- Capacity of an old CarryLevel (1-based; broken values count as 1).
function ToolData.carryCapacity(level: any, hasStrongBack: boolean): number
	local n = if type(level) == "number" and level == level then math.floor(level) else 1
	local info = ToolData.CarryLevels[math.clamp(n, 1, #ToolData.CarryLevels)]
	return info.Capacity * (if hasStrongBack then 2 else 1)
end

return ToolData
