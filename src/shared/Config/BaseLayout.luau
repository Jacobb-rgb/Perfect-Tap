--[[
	The fixed parts of every base (design v2), in plot-local studs.

	Plot frame (WorldLayout.plotCFrame): origin = the pad's top center,
	LookVector = toward the road, so local -Z is the road side and local +Z
	the sea side. +X is the right hand when you face the road.
	The 12x12 machine grid covers x, z in -24..24. Behind it, on the sea
	side, lies the yard (z 25..56): the Ore Pen, the podiums, the Foundry
	and the train stop on the coastal railway (z ~62, world |x| ~165).
	Nothing here may overlap the machine grid.
]]

export type Rect = { Center: Vector3, Size: Vector3 } -- Size.Y = height budget

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

-- Train stop on the coastal railway (step 2).
BaseLayout.TrainStop = rect(0, 57.5, 34, 6, 5)
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

return BaseLayout
