--[[
	The fixed parts of every base (design v2), in plot-local studs.

	Plot frame (WorldLayout.plotCFrame): origin = the pad's top center,
	LookVector = toward the road, so local -Z is the road side and local +Z
	the sea side. +X is the right hand when you face the road.
	The 12x12 machine grid covers x, z in -24..24. Behind it, on the sea
	side, lies the yard (z 25..56): the Ore Pen, the podiums, the Foundry
	and the train stop on the coastal railway (z ~62, world |x| ~165).
	Nothing here may overlap the machine grid (pieces()); only the three
	chute cells (Chutes) are fixtures on the grid itself.
]]

local GameConfig = require(script.Parent.GameConfig)

export type Rect = { Center: Vector3, Size: Vector3 } -- Size.Y = height budget
export type ChuteKind = "Source" | "Sink"
export type Chute = { X: number, Z: number, Kind: ChuteKind }

local BaseLayout = {}

local function rect(cx: number, cz: number, sx: number, sy: number, sz: number): Rect
	return { Center = Vector3.new(cx, 0, cz), Size = Vector3.new(sx, sy, sz) }
end

-- The whole yard (ground pad, rails).
BaseLayout.Yard = rect(0, 40.5, 50, 0, 31)

-- Gap in the plot's back rail so players can walk from the grid into the yard.
BaseLayout.YardGate = { CenterX = 0, Width = 12 }

-- Fenced pen; anything you drop or throw inside goes into data.Storage.
BaseLayout.Pen = {
	Area = rect(-12, 37, 22, 3, 18), -- fence footprint (Size.Y = fence height)
	Intake = rect(-12, 37, 21, 8, 17), -- items inside this box are taken in
	PromptPoint = Vector3.new(-12, 3, 27.5), -- "Open Pen" / "Put In" prompts (at the gate)
	ShowMax = 24, -- loose-looking items the client shows inside the pen
}

-- Podium slots, left to right as seen from the grid. Slots 3 and 4 need the Podiums perk.
BaseLayout.Podiums = {
	rect(4, 31, 4, 9, 4),
	rect(10, 31, 4, 9, 4),
	rect(16, 31, 4, 9, 4),
	rect(22, 31, 4, 9, 4),
}
BaseLayout.PodiumOreHeight = 4.6 -- where the ore floats above the podium base

-- The Foundry (step 3): ingots in, stronger blasters out.
BaseLayout.Foundry = rect(13, 46, 18, 16, 14)

-- Train stop on the coastal railway (step 2). Its rail-side edge (z 59) keeps
-- 3 studs from the rail centerline, out of the trains' wheels (+-2.95).
BaseLayout.TrainStop = rect(0, 57, 34, 6, 4)
BaseLayout.RailZ = 62 -- rail centerline, plot-local (runs along X)

-- Reserved for the artifact museum (step 7).
BaseLayout.Museum = rect(-12, 51, 22, 10, 8)

-- Every fixed piece, for overlap tests.
function BaseLayout.pieces(): { [string]: Rect }
	local list: { [string]: Rect } = {
		Pen = BaseLayout.Pen.Area,
		Foundry = BaseLayout.Foundry,
		TrainStop = BaseLayout.TrainStop,
		Museum = BaseLayout.Museum,
	}
	for i, podium in BaseLayout.Podiums do
		list["Podium" .. i] = podium
	end
	return list
end

-- A world CFrame for a plot-local point (plotCF from WorldLayout.plotCFrame).
function BaseLayout.toWorld(plotCF: CFrame, localPos: Vector3): CFrame
	return plotCF * CFrame.new(localPos)
end

---------------------------------------------------------------- chutes

--[[
	Chute cells (step 3, docs/plans/STEP3_PLAN.md): three fixed cells on the
	back row of the machine grid (gz = PlotCells - 1, next to the yard; cell
	numbers as in Machines/Grid). Only belts may stand on them: Placement
	refuses every other machine there (reason "Chute") and moves one off
	when a saved layout has it there.
	  Pen      Source  items sent from the Ore Pen (PenAction "Send") appear here
	  Train    Source  Direct Unload (Upgrades.PenAutomation 2): the train drops
	                   raw ore here instead of into the pen
	  Foundry  Sink    a belt on this cell whose front faces +Z (SinkRotation,
	                   off the grid edge toward the yard) delivers into the
	                   Foundry; items that come to rest on the cell go in too
	A Source spawns its items on top of whatever belt stands on the cell
	(the belt's direction decides the route); with no belt they just lie there.
]]
local BACK_ROW = GameConfig.PlotCells - 1
local CELL = GameConfig.CellSize
local GRID_HALF = GameConfig.PlotCells * CELL / 2

BaseLayout.Chutes = {
	Pen = { X = 3, Z = BACK_ROW, Kind = "Source" },
	Train = { X = 6, Z = BACK_ROW, Kind = "Source" },
	Foundry = { X = 9, Z = BACK_ROW, Kind = "Sink" },
} :: { [string]: Chute }

-- The chute names in a fixed order (loops, UI).
BaseLayout.ChuteNames = { "Pen", "Train", "Foundry" }

-- Grid rotation of a belt that delivers into a Sink chute: Grid.dir(2) = (0, 1), +Z.
BaseLayout.SinkRotation = 2

local function chuteOf(name: string): Chute
	local chute = BaseLayout.Chutes[name]
	assert(chute, "Unknown chute " .. tostring(name))
	return chute
end

-- Grid cell (gx, gz) of a chute.
function BaseLayout.chuteCell(name: string): (number, number)
	local chute = chuteOf(name)
	return chute.X, chute.Z
end

-- Name of the chute on grid cell (gx, gz), or nil.
function BaseLayout.chuteAt(gx: number, gz: number): string?
	for _, name in BaseLayout.ChuteNames do
		local chute = BaseLayout.Chutes[name]
		if chute.X == gx and chute.Z == gz then
			return name
		end
	end
	return nil
end

-- Plot-local centre of a chute cell, on top of the pad (y = 0).
function BaseLayout.chuteLocal(name: string): Vector3
	local chute = chuteOf(name)
	return Vector3.new(-GRID_HALF + (chute.X + 0.5) * CELL, 0, -GRID_HALF + (chute.Z + 0.5) * CELL)
end

-- World CFrame of a chute cell's centre on top of the pad, turned like the
-- plot (plotCF from WorldLayout.plotCFrame / PlotService.plotCFrame).
function BaseLayout.chuteWorld(plotCF: CFrame, name: string): CFrame
	return plotCF * CFrame.new(BaseLayout.chuteLocal(name))
end

return BaseLayout
