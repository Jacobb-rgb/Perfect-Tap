--[[
	The fixed parts of every base (design v2), in plot-local studs.

	Plot frame (WorldLayout.plotCFrame): origin = the pad's top center,
	LookVector = toward the road, so local -Z is the road side and local +Z
	the sea side. +X is the right hand when you face the road.
	The 12x12 machine grid covers x, z in -24..24. Behind it, on the sea
	side, lies the yard (z 25..56): the Ore Pen, the podiums, the Foundry
	and the train stop on the coastal railway (z ~62, world |x| ~165).
	Nothing here may overlap the machine grid (pieces()); only the three
	chute cells (Chutes) are fixtures on the grid itself, and the Foundry's
	receiver (FoundryIntake) reaches over the end of the FOUNDRY chute cell.
]]

local GameConfig = require(script.Parent.GameConfig)

export type Rect = { Center: Vector3, Size: Vector3 } -- Size.Y = height budget
export type ChuteKind = "Source" | "Sink"
export type Chute = {
	X: number,
	Z: number,
	Kind: ChuteKind,
	Label: string, -- short sign text (build-mode plate, in-world sign)
	Color: Color3, -- plate / sign color
	Hint: string, -- one line for the player (tooltips, the refused-placement toast)
}

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
	when a saved layout has it there (sanitize reason "Chute": its own toast).
	  Pen      Source  items sent from the Ore Pen (PenAction "Send") come out here
	  Train    Source  Direct Unload (Upgrades.PenAutomation 2): the train puts its
	                   dirty ore here instead of into the pen
	  Foundry  Sink    delivers into the Foundry (GameConfig, Foundry): ingots the
	                   next blaster level can use go into data.Foundry.Stock, every
	                   other item into the Ore Pen
	Sinks take only the plot owner's items. Another player's item is refused
	as at a machine ("Foreign": pushed off, back to its owner after
	GameConfig.ForeignItemReturn); it never lands in this player's pen or
	Foundry. A Sink takes:
	  - an item reaching the end of a belt on its cell whose front faces +Z
	    (SinkRotation, off the grid edge toward the yard);
	  - with NO belt on the cell, an item lying or rolling onto the cell (a
	    cheap box scan of the cell each GameConfig.IntakeTick, e.g. a furnace
	    whose output lands there). A belt on the cell facing any other way
	    just carries items across; nothing is taken from it.
	A Source only spawns an item onto a belt standing on its cell whose front
	is NOT SinkRotation (sourceFeeds: a belt running off the grid edge would
	drop the item loose in the yard), and only while that belt has room (the
	belt's direction decides the route). With no such belt, or a jammed one,
	nothing comes out: the pen's send queue waits, Direct Unload cargo goes
	into the pen as without the upgrade. A Source never drops an item loose
	(the Train chute is in the yard gate's walkway).
	Players must see the chutes (WP-Belts, shipped in the same merge as these
	contracts so the "Chute" refusal and toast always point at something
	visible): a colored plate with the Label in build mode (GridOverlay) and a
	small floor plate + sign per chute in the world (ConveyorService, per
	plot), both in the chute's Color; a Source's plate shows "Turn the belt
	away from the yard" while its belt faces SinkRotation.
]]
local BACK_ROW = GameConfig.PlotCells - 1
local CELL = GameConfig.CellSize
local GRID_HALF = GameConfig.PlotCells * CELL / 2

BaseLayout.Chutes = {
	Pen = {
		X = 3,
		Z = BACK_ROW,
		Kind = "Source",
		Label = "PEN",
		Color = Color3.fromRGB(72, 160, 255),
		Hint = "Items you send from your Ore Pen come out here.",
	},
	Train = {
		X = 6,
		Z = BACK_ROW,
		Kind = "Source",
		Label = "TRAIN",
		Color = Color3.fromRGB(96, 200, 110),
		Hint = "With Direct Unload, your train puts its dirty ore here.",
	},
	Foundry = {
		X = 9,
		Z = BACK_ROW,
		Kind = "Sink",
		Label = "FOUNDRY",
		Color = Color3.fromRGB(255, 120, 40),
		Hint = "Run a belt off this edge (or drop ingots here) to feed your Foundry.",
	},
} :: { [string]: Chute }

-- The chute names in a fixed order (loops, UI).
BaseLayout.ChuteNames = { "Pen", "Train", "Foundry" }

-- Grid rotation of a belt that delivers into a Sink chute: Grid.dir(2) = (0, 1), +Z.
BaseLayout.SinkRotation = 2

-- May a Source chute spawn onto a belt turned `r` on its cell? Not when the
-- belt runs off the grid edge into the yard (SinkRotation): the item would
-- fall off loose. Broken rotations count as no.
function BaseLayout.sourceFeeds(r: any): boolean
	return type(r) == "number" and r == math.floor(r) and r >= 0 and r <= 3 and r ~= BaseLayout.SinkRotation
end

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

--[[
	The Foundry's visible receiver at the FOUNDRY chute (FoundryService
	builds it per plot; PlotBuilder stays untouched): a hood over the end of
	the sink belt, leaning on the plot's back wall, with a pipe that goes
	down into the ground (the Foundry shows it coming back up). An ingot the
	chute takes flies into Mouth (a short client tween) instead of vanishing
	at the wall. Zone is the room the hood may use: the last stud of the
	chute cell (the belt still runs under it) up to the wall, kept left of
	the wall pillar at x ~15-17 (no other piece overlaps it).
]]
local foundryCell = BaseLayout.chuteLocal("Foundry")
BaseLayout.FoundryIntake = {
	Mouth = Vector3.new(foundryCell.X, 1.2, GRID_HALF - 0.4),
	Zone = rect(foundryCell.X - 0.4, GRID_HALF, 2.8, 3.5, 1.8),
}

return BaseLayout
