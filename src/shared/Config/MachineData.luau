--[[
	Placeable machines. Size = footprint in grid cells (X wide, Z deep) at
	rotation 0. Items go in by dropping or throwing them into the hopper on
	top, or by running a belt into any side except the output front (crates
	and Sell Chutes take every side). Results leave the front (the side
	facing the road at rotation 0), from the right front cell on 2-wide
	machines, straight into a machine standing there if it takes them.
	Grid maths (footprints, output cells, sides) lives in Machines/Grid.
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
	LoadText: string?, -- ActionText of the "Put In" prompt (shown while you carry something)
	WrongHint: string?, -- toast when the machine refuses an item
	ConveyorFaces: ("All" | "NoFront")?, -- sides a belt can feed (nil = belts never feed it)
	AcceptsForeign: boolean?, -- takes items owned by other players
	GradeChances: { [string]: number }?, -- output grade odds (Auto Cleaner)
	Retired: boolean?, -- design v2 removed it: not sold, migrations take it off plots
}

local MachineData = {}

local FURNACE_HINT = "Furnaces melt CLEAN or CRUSHED ore. Clean raw ore at your Cleaning Station first!"

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
		Retired = true, -- design v2 (see MachineData.Retired)
		Name = "Storage Crate",
		Description = "Adds 60 item spaces to your storage (all crates share one store). Drop items in, take them out any time.",
		Size = { 2, 2 },
		Price = 150,
		Category = "Storage",
		Order = 2,
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true, Gear = true },
		LoadText = "Store Items",
		ConveyorFaces = "All",
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
		LoadText = "Smelt Ore",
		WrongHint = FURNACE_HINT,
		ConveyorFaces = "NoFront",
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
		LoadText = "Crush Ore",
		WrongHint = "The Crusher only takes CLEAN ore.",
		ConveyorFaces = "NoFront",
	},
	{
		Id = "Anvil",
		Retired = true, -- design v2 (see MachineData.Retired)
		Name = "Anvil",
		Description = "Hammer ingots of one ore into gear, the most valuable items in Terra.",
		Size = { 2, 2 },
		Price = 600,
		Category = "Processing",
		Order = 5,
		Accepts = { Ingot = true },
		WrongHint = "The Anvil only takes INGOTS of one ore. Smelt ore in a Furnace first!",
		ConveyorFaces = "NoFront",
	},
	{
		Id = "AutoCleaner",
		Name = "Auto Cleaner",
		Description = "Cleans raw ore by itself: 60% Rough, 40% Clean. Your own hands can do better.",
		Size = { 2, 2 },
		Price = 2500,
		Category = "Processing",
		Order = 6,
		Accepts = { Raw = true },
		Time = 8,
		Output = "Clean",
		OutputCount = 1,
		MaxGrade = "Clean",
		LoadText = "Auto-Clean",
		WrongHint = "The Auto Cleaner only takes RAW ore.",
		ConveyorFaces = "NoFront",
		GradeChances = { Rough = 0.6, Clean = 0.4 },
	},
	{
		Id = "SellChute",
		Retired = true, -- design v2 (see MachineData.Retired)
		Name = "Sell Chute",
		Description = "Sells anything that drops in and pays the item's owner, the same as Pell.",
		Size = { 1, 1 },
		Price = 1200,
		Category = "Selling",
		Order = 7,
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true, Gear = true },
		LoadText = "Sell Items",
		ConveyorFaces = "All",
		AcceptsForeign = true,
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
		LoadText = "Smelt Ore",
		WrongHint = FURNACE_HINT,
		ConveyorFaces = "NoFront",
	},
	{
		Id = "Conveyor",
		Name = "Conveyor",
		Description = "Moves items in the direction of its arrows. You can walk through belts.",
		Size = { 1, 1 },
		Price = 25,
		Category = "Logistics",
		Order = 9,
		IsConveyor = true,
		SlotFree = true,
	},
} :: { Machine }

MachineData.ById = {} :: { [string]: Machine }
-- Machines design v2 removed (the Ore Pen replaced the Storage Crate, Tobin's
-- Sell stall the Sell Chute, the Foundry the Anvil). Kept here so old saves
-- and the builders still know them; Migrations refunds and removes them.
MachineData.Retired = {} :: { [string]: boolean }
-- Machines a player can buy and place.
MachineData.Buildable = {} :: { Machine }
for _, machine in MachineData.List do
	MachineData.ById[machine.Id] = machine
	if machine.Retired then
		MachineData.Retired[machine.Id] = true
	else
		table.insert(MachineData.Buildable, machine)
	end
end

-- New players get these placed for free (grid X, Z, rotation 0-3).
MachineData.StarterKit = {
	{ Id = "CleaningStation", X = 4, Z = 4, R = 0 },
	{ Id = "ClayFurnace", X = 8, Z = 4, R = 0 },
}

MachineData.BaseMachineSlots = 10
MachineData.SlotUpgrade = { Amount = 3, Prices = { 1000, 5000 } }
MachineData.WorkshopPassSlots = 6
MachineData.BaseConveyorSlots = 40
MachineData.WorkshopPassConveyors = 20

-- Finished items a machine holds while its front is blocked.
MachineData.MaxOutBuffer = 4

-- Machine slots: 10 base, +3 per slot upgrade bought (2 exist), +6 with the
-- Workshop pass. Gives 10 / 13 / 16, or 22 with everything.
function MachineData.machineSlots(extraBought: number, workshop: boolean): number
	local bought = math.clamp(math.floor(tonumber(extraBought) or 0), 0, #MachineData.SlotUpgrade.Prices)
	return MachineData.BaseMachineSlots
		+ MachineData.SlotUpgrade.Amount * bought
		+ (if workshop then MachineData.WorkshopPassSlots else 0)
end

-- Conveyor slots: 40, or 60 with the Workshop pass.
function MachineData.conveyorSlots(workshop: boolean): number
	return MachineData.BaseConveyorSlots + (if workshop then MachineData.WorkshopPassConveyors else 0)
end

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
