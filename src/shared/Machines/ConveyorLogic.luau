--[[
	ConveyorLogic: pure belt layout rules. Which side rails open, which
	belts feed which machine, and which machine faces take belt items.

	- A belt's side rail opens when the neighbour on that side is a belt
	  whose front cell is this belt's cell (corners and T-joins).
	  Right = Grid.right(r), which is model +X, where RailR sits.
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

local function onPlot(x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < CELLS and z < CELLS
end

-- Cell in front of a 1x1 belt.
local function frontOf(entry: Entry): (number, number)
	local dx, dz = Grid.dir(entry.R)
	return entry.X + dx, entry.Z + dz
end

-- Belt entry -> which of its side rails are open.
function ConveyorLogic.openSides(entries: { Entry }): { [Entry]: Sides }
	local occupied = Placement.occupancy(entries)
	local result: { [Entry]: Sides } = {}
	local function feedsInto(gx: number, gz: number, target: Entry): boolean
		if not onPlot(gx, gz) then
			return false
		end
		local other = occupied[Grid.key(gx, gz)]
		if not other or other == target or not isConveyor(other) then
			return false
		end
		local fx, fz = frontOf(other)
		return fx == target.X and fz == target.Z
	end
	for _, entry in entries do
		if occupied[Grid.key(entry.X, entry.Z)] == entry and isConveyor(entry) then
			local rx, rz = Grid.right(entry.R)
			result[entry] = {
				Right = feedsInto(entry.X + rx, entry.Z + rz, entry),
				Left = feedsInto(entry.X - rx, entry.Z - rz, entry),
			}
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
		if occupied[Grid.key(entry.X, entry.Z)] == entry and isConveyor(entry) then
			local fx, fz = frontOf(entry)
			local target = if onPlot(fx, fz) then occupied[Grid.key(fx, fz)] else nil
			if target and not isConveyor(target) and ConveyorLogic.faceAllowed(target, entry.X, entry.Z) then
				table.insert(list, { Conveyor = entry, Target = target })
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
		if not seen[entry] and occupied[Grid.key(entry.X, entry.Z)] == entry and isConveyor(entry) then
			local fx, fz = frontOf(entry)
			local other = if onPlot(fx, fz) then occupied[Grid.key(fx, fz)] else nil
			if other and other ~= entry and isConveyor(other) then
				local ox, oz = frontOf(other)
				if ox == entry.X and oz == entry.Z then
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
