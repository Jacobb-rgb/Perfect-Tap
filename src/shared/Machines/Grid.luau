--[[
	Grid: pure plot-grid maths, the single source for footprints, rotation,
	output cells and sides. No Roblox services, so the Lune tests run it.

	Plot-local space: origin = plot pad top centre, the road is at -Z.
	Cell (x, z) covers local X from -half + x*cell to -half + (x+1)*cell
	(same for Z), so x grows toward +X and z toward +Z (away from the road).
	A machine entry {X, Z, R} is its min corner cell plus a rotation 0-3.

	Rotation r turns the model by -r * 90 degrees around Y. Its front (model
	-Z, where results come out) then points along Grid.dir(r):
	  r0 (0,-1) toward the road, r1 (1,0), r2 (0,1), r3 (-1,0).
	Right is the machine's right hand when looking out of its front
	(model +X).
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MachineData = require(script.Parent.Parent.Config.MachineData)

local Grid = {}

export type Side = "Front" | "Back" | "Left" | "Right"

local CELL = GameConfig.CellSize
local CELLS = GameConfig.PlotCells
local HALF = CELLS * CELL / 2

-- Machines without a front output: the Cleaning Station uses its tray,
-- the Sell Chute and belts never push anything out.
local NO_FRONT_OUTPUT = {
	CleaningStation = true,
	SellChute = true,
	Conveyor = true,
	-- the roster: belts, side outputs (Splitter, Sorter), hand-over (Robot
	-- Arm), selling and power make nothing come out of the front
	ExpressConveyor = true,
	Splitter = true,
	Sorter = true,
	RobotArm = true,
	SellBox = true,
	PowerPole = true,
	SolarPanel = true,
	WindTurbine = true,
	FusionReactor = true,
	-- platforms: a deck carries, the Belt Lift and the Slide are belts
	Platform = true,
	BeltLift = true,
	Slide = true,
}

local DIRS = {
	[0] = { 0, -1 },
	[1] = { 1, 0 },
	[2] = { 0, 1 },
	[3] = { -1, 0 },
}

local function machine(id: string): MachineData.Machine
	local info = MachineData.ById[id]
	assert(info, "Unknown machine " .. tostring(id))
	return info
end

local function rot(r: number): number
	return math.floor(r) % 4
end

-- Footprint in cells (width along X, depth along Z) after rotation.
function Grid.footprint(id: string, r: number): (number, number)
	local size = machine(id).Size
	if rot(r) % 2 == 1 then
		return size[2], size[1]
	end
	return size[1], size[2]
end

-- One number per cell (z * PlotCells + x). Only meaningful for cells on the plot.
function Grid.key(x: number, z: number): number
	return z * CELLS + x
end

-- Direction the machine's front faces, in cells.
function Grid.dir(r: number): (number, number)
	local d = DIRS[rot(r)]
	return d[1], d[2]
end

-- The machine's right-hand direction, in cells (model +X).
function Grid.right(r: number): (number, number)
	local dx, dz = Grid.dir(r)
	return -dz, dx
end

-- Plot-local height of a level (0 = the plot pad, 1 = a platform's deck top).
function Grid.levelY(level: number?): number
	return (if level == 1 then 1 else 0) * MachineData.DeckHeight
end

-- Plot-local CFrame of a footprint centre, turned to face Grid.dir(r), on
-- `level` (nil / 0 = the pad, 1 = a deck: MachineData.DeckHeight up).
-- PlotService.footprintCFrame and the build-mode ghost both use this.
function Grid.localCFrame(id: string, x: number, z: number, r: number, level: number?): CFrame
	local w, d = Grid.footprint(id, r)
	return CFrame.new(-HALF + (x + w / 2) * CELL, Grid.levelY(level), -HALF + (z + d / 2) * CELL)
		* CFrame.Angles(0, -rot(r) * math.pi / 2, 0)
end

-- Cell under a plot-local position, or nil when it's off the grid.
function Grid.cellFromLocal(p: Vector3): (number?, number?)
	local x = math.floor((p.X + HALF) / CELL)
	local z = math.floor((p.Z + HALF) / CELL)
	if x ~= x or z ~= z or x < 0 or z < 0 or x >= CELLS or z >= CELLS then
		return nil, nil
	end
	return x, z
end

-- Model-local position of the Output attachment (relative to the model
-- pivot), or nil for machines without a front output. It sits in the
-- middle column (the right one of the two middle columns on 2-wide
-- machines), 0.5 studs in front of the footprint, 1.8 studs up.
-- Machines with nothing coming out of the front (outputLocal and outputCell agree):
-- NO_FRONT_OUTPUT. (The droppers and the Money Laser push their Drops out of the front.)
local function noFront(id: string, _info: MachineData.Machine): boolean
	return NO_FRONT_OUTPUT[id] == true
end

function Grid.outputLocal(id: string): Vector3?
	local info = machine(id)
	if noFront(id, info) then
		return nil
	end
	local w, d = info.Size[1], info.Size[2]
	local column = math.floor(w / 2)
	return Vector3.new(-w * CELL / 2 + (column + 0.5) * CELL, 1.8, -(d * CELL / 2) - 0.5)
end

-- Side outputs (MachineData SideOutputs: Splitter, Sorter): `side` -1 = the
-- machine's left, 1 = its right (Grid.right). Model-local point of the
-- OutputL / OutputR attachment: 0.5 studs outside the footprint, level
-- with the front row, 1.4 studs up (an item spawned there drops onto a
-- belt in the side cell).
function Grid.sideOutputLocal(id: string, side: number): Vector3
	local info = machine(id)
	local w, d = info.Size[1], info.Size[2]
	return Vector3.new(side * (w * CELL / 2 + 0.5), 1.4, -(d * CELL / 2) + CELL / 2)
end

-- The cell beside the machine's front row on `side` (-1 left, 1 right).
function Grid.sideOutputCell(id: string, x: number, z: number, r: number, side: number): (number, number)
	local fw, fd = Grid.footprint(id, r)
	local info = machine(id)
	local w, d = info.Size[1], info.Size[2]
	local dx, dz = Grid.dir(r)
	local rx, rz = Grid.right(r)
	local across = side * (w / 2 + 0.5)
	local ahead = d / 2 - 0.5
	local px = x + fw / 2 + across * rx + ahead * dx
	local pz = z + fd / 2 + across * rz + ahead * dz
	return math.floor(px), math.floor(pz)
end

-- The cell the output lands in (just in front of the output column).
-- It may be off the plot: the raw cell numbers are returned anyway.
function Grid.outputCell(id: string, x: number, z: number, r: number): (number?, number?)
	local info = machine(id)
	if noFront(id, info) then
		return nil, nil
	end
	local w, d = info.Size[1], info.Size[2]
	local fw, fd = Grid.footprint(id, r)
	local dx, dz = Grid.dir(r)
	local rx, rz = Grid.right(r)
	-- in cell units: centre of the footprint, then along "right" to the
	-- output column and along "front" to the middle of the next cell
	local across = math.floor(w / 2) + 0.5 - w / 2
	local ahead = d / 2 + 0.5
	local px = x + fw / 2 + across * rx + ahead * dx
	local pz = z + fd / 2 + across * rz + ahead * dz
	return math.floor(px), math.floor(pz)
end

-- The cell just in front of (`ahead` 1) or behind (`ahead` -1) the
-- footprint, in line with its output column (the middle of a 1-wide belt
-- or slope). Raw numbers: it may be off the plot. Unlike outputCell this
-- answers for every machine (the Belt Lift's top end, the Slide's back).
function Grid.endCell(id: string, x: number, z: number, r: number, ahead: number): (number, number)
	local info = machine(id)
	local w, d = info.Size[1], info.Size[2]
	local fw, fd = Grid.footprint(id, r)
	local dx, dz = Grid.dir(r)
	local rx, rz = Grid.right(r)
	local across = math.floor(w / 2) + 0.5 - w / 2
	local along = (if ahead < 0 then -1 else 1) * (d / 2 + 0.5)
	local px = x + fw / 2 + across * rx + along * dx
	local pz = z + fd / 2 + across * rz + along * dz
	return math.floor(px), math.floor(pz)
end

-- Which side of a machine the cell (gx, gz) touches, from the machine's
-- point of view, or nil when the cell isn't directly next to its footprint
-- (inside it, diagonal, or further away).
function Grid.sideOf(id: string, x: number, z: number, r: number, gx: number, gz: number): Side?
	local w, d = Grid.footprint(id, r)
	local sx, sz = 0, 0
	if gx >= x and gx < x + w then
		if gz == z - 1 then
			sz = -1
		elseif gz == z + d then
			sz = 1
		else
			return nil
		end
	elseif gz >= z and gz < z + d then
		if gx == x - 1 then
			sx = -1
		elseif gx == x + w then
			sx = 1
		else
			return nil
		end
	else
		return nil
	end
	local dx, dz = Grid.dir(r)
	local rx, rz = Grid.right(r)
	if sx == dx and sz == dz then
		return "Front"
	elseif sx == -dx and sz == -dz then
		return "Back"
	elseif sx == rx and sz == rz then
		return "Right"
	end
	return "Left"
end

return Grid
