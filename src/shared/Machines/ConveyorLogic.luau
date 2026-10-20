--[[
	ConveyorLogic: pure belt layout rules. Which side rails open, which
	belts feed which machine, and which machine faces take belt items.

	- A belt delivers into the cell in front of its front end (frontOf), on
	  its own level; a Belt Lift delivers up onto the deck (level 1). Cells
	  are looked up by cell and level (Placement.key), so a belt under a
	  platform and one on its deck never meet.
	- A flat belt's side rail opens when a belt on that side delivers into
	  this belt's cell (corners and T-joins; a Belt Lift arriving from the
	  side of a deck belt too). Right = Grid.right(r), which is model +X,
	  where RailR sits.
	- A feeder is a belt whose front cell is covered by a machine (not a
	  belt) that takes items from that face.
	- headOn lists belts pointing straight at each other. It's only a
	  warning for the build ghost, never a placement error.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local Grid = require(script.Parent.Grid)
local Placement = require(script.Parent.Placement)

local ConveyorLogic = {}

type Entry = Placement.Entry
export type Sides = { Left: boolean, Right: boolean }
export type Feeder = { Conveyor: Entry, Target: Entry }

local CELLS = GameConfig.PlotCells

local function isConveyor(entry: Entry): boolean
	local info = MachineData.ById[entry.Id]
	return info ~= nil and info.IsConveyor == true
end

local function isFlat(entry: Entry): boolean
	local info = MachineData.ById[entry.Id]
	return info ~= nil and info.IsConveyor == true and info.Slope == nil
end

local function onPlot(x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < CELLS and z < CELLS
end

--[[
	The cell a belt delivers into (in front of its front end, raw numbers)
	and that cell's level: a Belt Lift's is up on the deck (1), a Slide's on
	the ground (0), every other belt's on its own level.
]]
function ConveyorLogic.frontOf(entry: Entry): (number, number, number)
	local fx, fz = Grid.endCell(entry.Id, entry.X, entry.Z, entry.R, 1)
	local info = MachineData.ById[entry.Id]
	local slope = info and info.Slope
	local level = if slope == "Up" then 1 elseif slope == "Down" then 0 else Placement.levelOf(entry)
	return fx, fz, level
end

-- Does the belt hold its own cells (its min corner on its level)? A belt
-- overlapping an earlier one in a damaged layout doesn't count.
local function holds(occupied: { [number]: Entry }, entry: Entry): boolean
	return occupied[Placement.key(entry.X, entry.Z, Placement.levelOf(entry))] == entry
end

-- Belt entry -> which of its side rails are open (flat belts).
function ConveyorLogic.openSides(entries: { Entry }): { [Entry]: Sides }
	local occupied = Placement.occupancy(entries)
	-- (cell, level) key -> the belts delivering into it
	local into: { [number]: { Entry } } = {}
	for _, entry in entries do
		if isConveyor(entry) and holds(occupied, entry) then
			local fx, fz, level = ConveyorLogic.frontOf(entry)
			if onPlot(fx, fz) then
				local key = Placement.key(fx, fz, level)
				local list = into[key]
				if not list then
					list = {}
					into[key] = list
				end
				table.insert(list, entry)
			end
		end
	end
	local result: { [Entry]: Sides } = {}
	local none: { Entry } = {}
	for _, entry in entries do
		if isFlat(entry) and holds(occupied, entry) then
			local rx, rz = Grid.right(entry.R)
			local sides: Sides = { Left = false, Right = false }
			local feeding: { Entry } = into[Placement.key(entry.X, entry.Z, Placement.levelOf(entry))] or none
			for _, feeder in feeding do
				if feeder ~= entry then
					-- the feeder's own cell next to this one
					local fx, fz = ConveyorLogic.frontOf(feeder)
					local dx, dz = Grid.dir(feeder.R)
					local sx, sz = fx - dx, fz - dz
					if sx == entry.X + rx and sz == entry.Z + rz then
						sides.Right = true
					elseif sx == entry.X - rx and sz == entry.Z - rz then
						sides.Left = true
					end
				end
			end
			result[entry] = sides
		end
	end
	return result
end

-- Does `target` take items arriving from the cell (fromX, fromZ)? That cell
-- is where the item comes from: a belt, or the cell of a machine whose
-- output front touches `target`. 'All' faces always, 'NoFront' every side
-- but the output front, nil never.
function ConveyorLogic.faceAllowed(target: Entry, fromX: number, fromZ: number): boolean
	local info = MachineData.ById[target.Id]
	if not info or not info.ConveyorFaces then
		return false
	end
	local side = Grid.sideOf(target.Id, target.X, target.Z, target.R, fromX, fromZ)
	if not side then
		return false
	end
	if info.ConveyorFaces == "All" then
		return true
	end
	return side ~= "Front"
end

-- Every belt that pushes into a machine face that takes items.
function ConveyorLogic.feeders(entries: { Entry }): { Feeder }
	local occupied = Placement.occupancy(entries)
	local list: { Feeder } = {}
	for _, entry in entries do
		if isConveyor(entry) and holds(occupied, entry) then
			local fx, fz, level = ConveyorLogic.frontOf(entry)
			local target = if onPlot(fx, fz) then occupied[Placement.key(fx, fz, level)] else nil
			if target and not isConveyor(target) then
				local dx, dz = Grid.dir(entry.R)
				if ConveyorLogic.faceAllowed(target, fx - dx, fz - dz) then
					table.insert(list, { Conveyor = entry, Target = target })
				end
			end
		end
	end
	return list
end

-- Pairs of belts that point straight at each other ({a, b}, listed once).
function ConveyorLogic.headOn(entries: { Entry }): { { Entry } }
	local occupied = Placement.occupancy(entries)
	local found: { { Entry } } = {}
	local seen: { [Entry]: boolean } = {}
	for _, entry in entries do
		if not seen[entry] and isConveyor(entry) and holds(occupied, entry) then
			local fx, fz, level = ConveyorLogic.frontOf(entry)
			local other = if onPlot(fx, fz) then occupied[Placement.key(fx, fz, level)] else nil
			if other and other ~= entry and isConveyor(other) then
				-- does the other one deliver into this belt's front cell?
				local dx, dz = Grid.dir(entry.R)
				local ox, oz, otherLevel = ConveyorLogic.frontOf(other)
				if ox == fx - dx and oz == fz - dz and otherLevel == Placement.levelOf(entry) then
					seen[entry] = true
					seen[other] = true
					table.insert(found, { entry, other })
				end
			end
		end
	end
	return found
end

return ConveyorLogic
