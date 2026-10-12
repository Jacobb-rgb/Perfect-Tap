--[[
	Placeable machines. Size = footprint in grid cells (X wide, Z deep) at
	rotation 0. Machines take items from any side/top and push results out
	of their front (the side facing the road at rotation 0).
]]

export type Machine = {
	Id: string,
	Name: string,
	Description: string,
	Size: { number }, -- { cellsX, cellsZ }
	Price: number,
	Category: string, -- "Processing" | "Storage" | "Logistics" | "Selling"
	Order: number,
	Accepts: { [string]: boolean }?, -- item kinds the intake accepts
	Time: number?, -- seconds per item (before speed upgrades)
	Output: string?, -- item kind produced
	OutputCount: number?,
	MaxGrade: string?, -- Auto Cleaner cap
	IsConveyor: boolean?,
	SlotFree: boolean?, -- doesn't use a machine slot (conveyors use conveyor slots)
}

local MachineData = {}

MachineData.List = {
	{
		Id = "CleaningStation",
		Name = "Cleaning Station",
		Description = "Chisel, scrape and polish raw ore by hand. The better you clean, the more it's worth.",
		Size = { 3, 2 },
		Price = 250,
		Category = "Processing",
		Order = 1,
		Accepts = { Raw = true },
	},
	{
		Id = "StorageCrate",
		Name = "Storage Crate",
		Description = "Stores up to 60 items. Drop items in, take them out any time.",
		Size = { 2, 2 },
		Price = 150,
		Category = "Storage",
		Order = 2,
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true, Gear = true },
	},
	{
		Id = "ClayFurnace",
		Name = "Clay Furnace",
		Description = "Smelts clean or crushed ore into ingots.",
		Size = { 2, 2 },
		Price = 300,
		Category = "Processing",
		Order = 3,
		Accepts = { Clean = true, Crushed = true },
		Time = 6,
		Output = "Ingot",
		OutputCount = 1,
	},
	{
		Id = "Crusher",
		Name = "Crusher",
		Description = "Crushes 1 clean ore into 2 piles: twice the ingots.",
		Size = { 2, 2 },
		Price = 450,
		Category = "Processing",
		Order = 4,
		Accepts = { Clean = true },
		Time = 3,
		Output = "Crushed",
		OutputCount = 2,
	},
	{
		Id = "Anvil",
		Name = "Anvil",
		Description = "Hammer ingots into gear, the most valuable items in Terra.",
		Size = { 2, 2 },
		Price = 600,
		Category = "Processing",
		Order = 5,
		Accepts = { Ingot = true },
	},
	{
		Id = "AutoCleaner",
		Name = "Auto Cleaner",
		Description = "Cleans raw ore by itself. Fast, but never better than Clean grade.",
		Size = { 2, 2 },
		Price = 2500,
		Category = "Processing",
		Order = 6,
		Accepts = { Raw = true },
		Time = 8,
		Output = "Clean",
		OutputCount = 1,
		MaxGrade = "Clean",
	},
	{
		Id = "SellChute",
		Name = "Sell Chute",
		Description = "Sells anything that drops in. Pays the same as Pell.",
		Size = { 1, 1 },
		Price = 1200,
		Category = "Selling",
		Order = 7,
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true, Gear = true },
	},
	{
		Id = "BlastFurnace",
		Name = "Blast Furnace",
		Description = "A roaring furnace: smelts much faster than clay.",
		Size = { 3, 3 },
		Price = 6000,
		Category = "Processing",
		Order = 8,
		Accepts = { Clean = true, Crushed = true },
		Time = 2.5,
		Output = "Ingot",
		OutputCount = 1,
	},
	{
		Id = "Conveyor",
		Name = "Conveyor",
		Description = "Moves items in the direction of its arrows.",
		Size = { 1, 1 },
		Price = 25,
		Category = "Logistics",
		Order = 9,
		IsConveyor = true,
		SlotFree = true,
	},
} :: { Machine }

MachineData.ById = {} :: { [string]: Machine }
for _, machine in MachineData.List do
	MachineData.ById[machine.Id] = machine
end

-- New players get these placed for free (grid X, Z, rotation 0-3).
MachineData.StarterKit = {
	{ Id = "StorageCrate", X = 1, Z = 7, R = 0 },
	{ Id = "CleaningStation", X = 4, Z = 4, R = 0 },
	{ Id = "ClayFurnace", X = 8, Z = 4, R = 0 },
}

MachineData.BaseMachineSlots = 10
MachineData.SlotUpgrade = { Amount = 3, Prices = { 1000, 5000 } }
MachineData.WorkshopPassSlots = 6
MachineData.BaseConveyorSlots = 40
MachineData.WorkshopPassConveyors = 20

-- Bellows upgrade: each level makes machines 10% faster.
MachineData.Bellows = { Prices = { 500, 1500, 4000, 10000, 25000 }, SpeedPerLevel = 0.1 }

-- Footprint in cells after rotation.
function MachineData.footprint(machine: Machine, rotation: number): (number, number)
	if rotation % 2 == 1 then
		return machine.Size[2], machine.Size[1]
	end
	return machine.Size[1], machine.Size[2]
end

function MachineData.processTime(machine: Machine, bellowsLevel: number): number
	local base = machine.Time or 0
	return base * (1 - MachineData.Bellows.SpeedPerLevel * math.clamp(bellowsLevel, 0, #MachineData.Bellows.Prices))
end

return MachineData
