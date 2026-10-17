--[[
	Placeable machines. Size = footprint in grid cells (X wide, Z deep) at
	rotation 0. Items go in by dropping or throwing them into the hopper on
	top, or by running a belt into any side except the output front (crates
	and Sell Chutes take every side). Results leave the front (the side
	facing the road at rotation 0), from the right front cell on 2-wide
	machines, straight into a machine standing there if it takes them.
	Grid maths (footprints, output cells, sides) lives in Machines/Grid.

	Design v2 (step 3, docs/plans/STEP3_PLAN.md): machines and their upgrades
	are bought in the Tech shop (EconomyConfig.TechShop). Upgrades are bought
	once per machine type and work on every placed machine of that type
	(saved in data.MachineUpgrades[machineId] = { Speed = level, Quality = level }):
	  Speed    every level takes SpeedPerLevel off the job time (speedMult)
	  Quality  Cleaning Plant only: the grade odds of QualityLevels[level + 1]
	The Auto Cleaner is shown as "Cleaning Plant" (its Id stays "AutoCleaner").
	The Iron Box and the pen's sorting billboard sort clean ore by
	data.KeepMode and data.KeepList (MachineData.Keep, MachineData.keeps).
]]

local GameConfig = require(script.Parent.GameConfig)
local OreData = require(script.Parent.OreData)
local Rarity = require(script.Parent.Rarity)

-- Machine upgrade prices, level 1 first (index = the level you buy).
export type UpgradePrices = { Speed: { number }?, Quality: { number }? }

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
	MaxGrade: string?, -- grade cap of GradeChances rolls (nil = Flawless)
	IsConveyor: boolean?,
	SlotFree: boolean?, -- doesn't use a machine slot (conveyors use conveyor slots)
	LoadText: string?, -- ActionText of the "Put In" prompt (shown while you carry something)
	WrongHint: string?, -- toast when the machine refuses an item
	ConveyorFaces: ("All" | "NoFront")?, -- sides a belt can feed (nil = belts never feed it)
	AcceptsForeign: boolean?, -- takes items owned by other players
	GradeChances: { [string]: number }?, -- output grade odds without upgrades (Cleaning Plant: QualityLevels[1])
	QualityLevels: { { [string]: number } }?, -- grade odds per Quality level (index = level + 1, Cleaning Plant)
	Upgrades: UpgradePrices?, -- Tech shop upgrades of this machine type (nil = none)
	Retired: boolean?, -- design v2 removed it: not sold, migrations take it off plots
}

local MachineData = {}

local FURNACE_HINT = "Furnaces melt CLEAN or CRUSHED ore. Clean dirty ore at your Cleaning Station first!"

-- Base upgrade price curves (exponential: players must not get everything at
-- once). Each machine scales them (cheap machines cheaper, big ones dearer).
local SPEED_CURVE = { 2000, 12000, 70000, 400000, 2.5e6 }
local QUALITY_CURVE = { 5000, 40000, 300000, 2e6, 15e6 }

local function scaled(curve: { number }, factor: number): { number }
	local list = {}
	for i, price in curve do
		list[i] = math.floor(price * factor + 0.5)
	end
	return list
end

-- Cleaning Plant grade odds per Quality level 0..5 (each adds up to 1).
local QUALITY_LEVELS: { { [string]: number } } = {
	{ Rough = 0.6, Clean = 0.4 },
	{ Rough = 0.5, Clean = 0.45, Pristine = 0.05 },
	{ Rough = 0.3, Clean = 0.5, Pristine = 0.2 },
	{ Rough = 0.15, Clean = 0.45, Pristine = 0.35, Flawless = 0.05 },
	{ Rough = 0.05, Clean = 0.35, Pristine = 0.45, Flawless = 0.15 },
	{ Clean = 0.2, Pristine = 0.5, Flawless = 0.3 },
}

MachineData.List = {
	{
		Id = "CleaningStation",
		Name = "Cleaning Station",
		Description = "Chisel, scrape and polish raw ore by hand. The better you clean, the more it's worth.",
		Size = { 3, 2 },
		Price = 250,
		Category = "Processing",
		Order = 2,
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
		Order = 90,
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true, Gear = true },
		LoadText = "Store Items",
		ConveyorFaces = "All",
	},
	{
		Id = "ClayFurnace",
		Name = "Clay Furnace",
		Description = "Smelts clean or crushed ore into ingots.",
		Size = { 2, 2 },
		Price = 500,
		Category = "Processing",
		Order = 3,
		Accepts = { Clean = true, Crushed = true },
		Time = 6,
		Output = "Ingot",
		OutputCount = 1,
		LoadText = "Smelt Ore",
		WrongHint = FURNACE_HINT,
		ConveyorFaces = "NoFront",
		Upgrades = { Speed = scaled(SPEED_CURVE, 0.5) },
	},
	{
		Id = "Crusher",
		Name = "Crusher",
		Description = "Crushes 1 clean ore into 2 piles: twice the ingots.",
		Size = { 2, 2 },
		Price = 1500,
		Category = "Processing",
		Order = 4,
		Accepts = { Clean = true },
		Time = 3,
		Output = "Crushed",
		OutputCount = 2,
		LoadText = "Crush Ore",
		WrongHint = "The Crusher only takes CLEAN ore.",
		ConveyorFaces = "NoFront",
		Upgrades = { Speed = scaled(SPEED_CURVE, 1) },
	},
	{
		Id = "Anvil",
		Retired = true, -- design v2 (see MachineData.Retired)
		Name = "Anvil",
		Description = "Hammer ingots of one ore into gear, the most valuable items in Terra.",
		Size = { 2, 2 },
		Price = 600,
		Category = "Processing",
		Order = 91,
		Accepts = { Ingot = true },
		WrongHint = "The Anvil only takes INGOTS of one ore. Smelt ore in a Furnace first!",
		ConveyorFaces = "NoFront",
	},
	{
		Id = "AutoCleaner",
		Name = "Cleaning Plant",
		Description = "Cleans dirty ore by itself, no scrubbing needed. Upgrade it to clean faster and better, up to Flawless.",
		Size = { 2, 2 },
		Price = 5000,
		Category = "Processing",
		Order = 5,
		Accepts = { Raw = true },
		Time = 8,
		Output = "Clean",
		OutputCount = 1,
		LoadText = "Auto-Clean",
		WrongHint = "The Cleaning Plant only takes DIRTY ore.",
		ConveyorFaces = "NoFront",
		GradeChances = QUALITY_LEVELS[1],
		QualityLevels = QUALITY_LEVELS,
		Upgrades = { Speed = scaled(SPEED_CURVE, 1), Quality = scaled(QUALITY_CURVE, 1) },
	},
	{
		Id = "IronBox",
		Name = "Iron Box",
		Description = "Shows what comes out of your Cleaning Plant. Clean ore you keep goes to your Ore Pen, everything else rolls out the front onto your belts.",
		Size = { 2, 2 },
		Price = 12000,
		Category = "Processing",
		Order = 6,
		-- only clean ore is kept or sent on by the player's setting; dirty ore,
		-- crushed ore and ingots always pass on (MachineData.keeps)
		Accepts = { Raw = true, Clean = true, Crushed = true, Ingot = true },
		-- seconds to show and sort one item before upgrades: long enough that every
		-- Speed level still counts with full Bellows (0.2 x 4 s = 0.8 s > MinProcessTime)
		Time = 4,
		LoadText = "Sort",
		WrongHint = "The Iron Box sorts ore, crushed ore and ingots.",
		ConveyorFaces = "NoFront",
		Upgrades = { Speed = scaled(SPEED_CURVE, 1) },
	},
	{
		Id = "SellChute",
		Retired = true, -- design v2 (see MachineData.Retired)
		Name = "Sell Chute",
		Description = "Sells anything that drops in and pays the item's owner, the same as Tobin.",
		Size = { 1, 1 },
		Price = 1200,
		Category = "Selling",
		Order = 92,
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
		Price = 30000,
		Category = "Processing",
		Order = 7,
		Accepts = { Clean = true, Crushed = true },
		Time = 2.5,
		Output = "Ingot",
		OutputCount = 1,
		LoadText = "Smelt Ore",
		WrongHint = FURNACE_HINT,
		ConveyorFaces = "NoFront",
		Upgrades = { Speed = scaled(SPEED_CURVE, 4) },
	},
	{
		Id = "Conveyor",
		Name = "Conveyor",
		Description = "Moves items in the direction of its arrows. You can walk through belts.",
		Size = { 1, 1 },
		Price = 25,
		Category = "Logistics",
		Order = 1,
		IsConveyor = true,
		SlotFree = true,
	},
} :: { Machine }

MachineData.ById = {} :: { [string]: Machine }
-- Machines design v2 removed (the Ore Pen replaced the Storage Crate, Tobin's
-- Sell stall the Sell Chute, the Foundry the Anvil). Kept here so old saves
-- and the builders still know them; Migrations refunds and removes them.
MachineData.Retired = {} :: { [string]: boolean }
-- Machines a player can buy and place, in Tech shop / build tray order (Order).
MachineData.Buildable = {} :: { Machine }
for _, machine in MachineData.List do
	MachineData.ById[machine.Id] = machine
	if machine.Retired then
		MachineData.Retired[machine.Id] = true
	else
		table.insert(MachineData.Buildable, machine)
	end
end
table.sort(MachineData.Buildable, function(a: Machine, b: Machine): boolean
	return a.Order < b.Order
end)

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

-- Most machines of one type data.MachineInventory holds (DataStore safety).
-- The Tech shop refuses a buy past it ("MaxOwned"), Placement refunds a
-- machine packed up past it (Placement.addInventory) and Migrations caps
-- a bigger saved count to it: a machine is never lost to the cap.
MachineData.MaxInventory = 999

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

---------------------------------------------------------------- upgrades

MachineData.UpgradeKinds = { "Speed", "Quality" }
-- The base curves the machines scale (level 1 first).
MachineData.UpgradeCurves = { Speed = SPEED_CURVE, Quality = QUALITY_CURVE }
-- Each Speed level takes this share of the base job time off (level 5: 60%).
MachineData.SpeedPerLevel = 0.12

local function wholeLevel(level: any, max: number): number
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	return math.clamp(n, 0, max)
end

-- Price list of an upgrade ("Speed" | "Quality") of a machine type, or nil
-- when that machine has no such upgrade.
function MachineData.upgradePrices(machineId: string, kind: string): { number }?
	local machine = MachineData.ById[machineId]
	local upgrades = machine and machine.Upgrades
	if not upgrades then
		return nil
	end
	if kind == "Speed" then
		return upgrades.Speed
	elseif kind == "Quality" then
		return upgrades.Quality
	end
	return nil
end

-- Highest level of an upgrade for a machine type (0 = it has none).
function MachineData.upgradeMax(machineId: string, kind: string): number
	local prices = MachineData.upgradePrices(machineId, kind)
	return if prices then #prices else 0
end

-- Job time multiplier of a Speed level (clamped to 0..5): 1, 0.88, 0.76 ... 0.4.
function MachineData.speedMult(level: any): number
	return 1 - MachineData.SpeedPerLevel * wholeLevel(level, #SPEED_CURVE)
end

-- Cleaning Plant grade odds at a Quality level (clamped to 0..5). The
-- returned table is shared config: read it, never change it.
function MachineData.gradeOdds(level: any): { [string]: number }
	return QUALITY_LEVELS[wholeLevel(level, #QUALITY_LEVELS - 1) + 1]
end

---------------------------------------------------------------- keeping

--[[
	What the Iron Box keeps (into the Ore Pen) and what it sends on (out of
	its front), and what the pen's sorting billboard marks as kept (PenAction
	"Send" Filter "Unkept" sends the rest). Only CLEAN ore is ever sorted,
	because only clean ore can go on a podium (EconomyConfig.Podiums.Kinds):
	  Raw      dirty ore is never kept: it always passes on (the box can't see
	           through the dirt, so nobody peeks at rare dirty ore)
	  Crushed  never kept: always passes on (on to a furnace)
	  Ingot    never kept: always passes on (on to the Foundry, which needs the
	           rare ones for blaster levels 6-10)
	  Clean    kept or sent on by the player's setting (below)
	  other    (old Gear) always counts as kept (it stays in the pen)
	One setting per player:
	  data.KeepMode  "RarePlus"  keep ores of rarity Keep.RareFrom and better (the default)
	                 "List"      the player's own choices: data.KeepList[oreId] = true
	                             (keep) or false (send on); an ore the player never
	                             set follows the RarePlus rule, so a first-ever
	                             Mythic is kept, never smelted by surprise. An
	                             empty list keeps the same as "RarePlus".
	                 "All"       keep every clean ore
	  data.KeepList  { [oreId] = boolean }, only read in "List" mode
]]
export type KeepMode = "RarePlus" | "List" | "All"

MachineData.Keep = {
	Modes = { "RarePlus", "List", "All" } :: { KeepMode }, -- in UI order
	Default = "RarePlus" :: KeepMode, -- a new player's mode (DataTemplate.KeepMode)
	RareFrom = "Rare", -- the lowest rarity "RarePlus" keeps (and "List" for ores not on the list)
}

-- Item kinds that always pass on (never kept), see above.
local PASSING_KINDS = { Raw = true, Crushed = true, Ingot = true }

-- Is `mode` one of Keep.Modes?
function MachineData.isKeepMode(mode: any): boolean
	return type(mode) == "string" and table.find(MachineData.Keep.Modes, mode :: KeepMode) ~= nil
end

-- Does the player keep CLEAN ore of this ore id (the Iron Box view's toggles
-- show this)? An unknown mode counts as Keep.Default, an unknown ore is never kept.
function MachineData.keepsOre(mode: any, keepList: any, oreId: any): boolean
	local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
	if not ore then
		return false
	end
	local m: KeepMode = if MachineData.isKeepMode(mode) then mode else MachineData.Keep.Default
	if m == "All" then
		return true
	elseif m == "List" and type(keepList) == "table" then
		local choice = keepList[ore.Id]
		if type(choice) == "boolean" then
			return choice
		end
	end
	local rarity = Rarity.ById[ore.Rarity]
	return rarity ~= nil and rarity.Order >= Rarity.get(MachineData.Keep.RareFrom).Order
end

-- Does the player keep this item (Iron Box: to the pen; pen: stays)?
-- `mode` and `keepList` are data.KeepMode and data.KeepList.
function MachineData.keeps(mode: any, keepList: any, desc: any): boolean
	if type(desc) ~= "table" or type(desc.K) ~= "string" or PASSING_KINDS[desc.K] then
		return false
	end
	if desc.K ~= "Clean" then
		return true
	end
	return MachineData.keepsOre(mode, keepList, desc.O)
end

---------------------------------------------------------------- job time

-- Seconds one job takes with the owner's Bellows level and the machine
-- type's Speed level, never below GameConfig.MinProcessTime (0 for
-- machines without a Time). Broken levels count as 0.
function MachineData.processTime(machine: Machine, bellowsLevel: any, speedLevel: any?): number
	local base = machine.Time or 0
	if not (base > 0) then
		return 0
	end
	local bellows = 1 - MachineData.Bellows.SpeedPerLevel * wholeLevel(bellowsLevel, #MachineData.Bellows.Prices)
	return math.max(GameConfig.MinProcessTime, base * bellows * MachineData.speedMult(speedLevel))
end

return MachineData
