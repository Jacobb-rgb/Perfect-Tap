--[[
	The fixed parts of every base (design v2), in plot-local studs.

	Plot frame (WorldLayout.plotCFrame): origin = the pad's top center,
	LookVector = toward the road, so local -Z is the road side and local +Z
	the sea side. +X is the right hand when you face the road.
	The machine grid (GameConfig.PlotCells square, 12x12 = 48 studs today)
	covers x, z in -GRID_HALF..GRID_HALF (-24..24). Behind it, on the sea
	side, lies the yard (z YARD_Z0..YARD_Z0 + 31, 25..56 today): the Ore
	Pen, the podiums and the yard's own Cleaning Station; behind it the
	strip where the coastal railway ran (RailZ, 62 today, world |x| ~165:
	kept clear; the train went 2026-11-17). (The Foundry stood where the
	station is until the owner's 2026-10-24 playtest: blasters come from
	the Vault only.)
	Nothing here may overlap the machine grid (pieces()); only the chute
	cell (Chutes) is a fixture on the grid itself.
	(bigger plots) Everything here derives from PlotCells: the yard keeps its
	depth and moves out with the grid's back edge, and every piece keeps its
	plot-local x, so the chutes, the pen gate and the yard gate stay lined
	up at any (even) grid size.
]]

local GameConfig = require(script.Parent.GameConfig)

export type Rect = { Center: Vector3, Size: Vector3 } -- Size.Y = height budget
export type ChuteKind = "Source" -- (the FOUNDRY chute was a "Sink"; it went with the Foundry)
export type Chute = {
	X: number,
	Z: number,
	Kind: ChuteKind,
	Label: string, -- short sign text (build-mode plate, in-world sign)
	Color: Color3, -- plate / sign color
	Hint: string, -- one line for the player (tooltips, the refused-placement toast)
}

local BaseLayout = {}

local CELL = GameConfig.CellSize
local GRID_HALF = GameConfig.PlotCells * CELL / 2
-- the grid grows by the same number of cells on each side
assert(GameConfig.PlotCells % 2 == 0, "GameConfig.PlotCells must be even")
-- The yard's front edge (plot-local z): the pad's back wall line, 25 at 12 cells.
local YARD_Z0 = GRID_HALF + 1
-- Cells a 12-cell layout moves across (+X) so it keeps its plot-local x on a
-- bigger grid (0 at 12 cells); along z it moves PlotCells - 12 to keep its
-- distance from the back wall.
local GRID_SHIFT = (GameConfig.PlotCells - 12) / 2

BaseLayout.YardZ0 = YARD_Z0
BaseLayout.GridShift = GRID_SHIFT

local function rect(cx: number, cz: number, sx: number, sy: number, sz: number): Rect
	return { Center = Vector3.new(cx, 0, cz), Size = Vector3.new(sx, sy, sz) }
end

-- The whole yard (ground pad, rails): as wide as the pad (PlotBuilder's long
-- side walls run on along both its sides).
BaseLayout.Yard = rect(0, YARD_Z0 + 15.5, 2 * (GRID_HALF + 1), 0, 31)

-- Gap in the plot's back rail so players can walk from the grid into the yard.
BaseLayout.YardGate = { CenterX = 0, Width = 12 }

-- Fenced pen; anything you drop or throw inside goes into data.Storage. Its
-- right edge stays at x -1 (PenService's board, IronBoxService.boardPoint); a
-- bigger grid widens it toward the left yard wall, which closes it
-- (PlotBuilder's pen). The gate keeps x -12, next to the PEN chute (x -10).
BaseLayout.Pen = {
	Area = rect(-GRID_HALF / 2, YARD_Z0 + 12, GRID_HALF - 2, 3, 18), -- fence footprint (Size.Y = fence height)
	Intake = rect(-GRID_HALF / 2, YARD_Z0 + 12, GRID_HALF - 3, 8, 17), -- items inside this box are taken in
	PromptPoint = Vector3.new(-12, 3, YARD_Z0 + 2.5), -- "Open Pen" / "Put In" prompts (at the gate)
	ShowMax = 24, -- loose-looking items the client shows inside the pen
}

-- Podium slots, left to right as seen from the grid. Slots 1-3 are free, 4 and 5 need the
-- Podiums perk (owner 2026-10-24: three free, two for Robux).
BaseLayout.Podiums = {
	rect(4, YARD_Z0 + 6, 4, 9, 4),
	rect(10, YARD_Z0 + 6, 4, 9, 4),
	rect(16, YARD_Z0 + 6, 4, 9, 4),
	rect(22, YARD_Z0 + 6, 4, 9, 4),
	rect(28, YARD_Z0 + 6, 4, 9, 4),
}
BaseLayout.PodiumOreHeight = 4.6 -- where the ore floats above the podium base

-- The yard's own Cleaning Station (owner 2026-10-24: "put the cleaner you use yourself where
-- the Foundry was"): CleaningService builds the station there for the plot's owner (no grid
-- cell, no save entry). Center = the footprint's centre on the ground (the machine model's
-- pivot), R = its rotation like a placed machine's (0: the front, with the prompt and the
-- camera, faces the podiums and the grid); Scale = how much bigger than a placed one it stands
-- (owner 2026-11-13: "strasne malinkej, zvets ho o dost"; it still keeps the podiums' row and the
-- train stop clear, with room to stand in front); Area = its footprint (3 x 2 cells, scaled) for
-- overlap tests.
-- (owner 2026-11-14: "dej ji uplne do prava do rohu": the yard's free back corner, by the rail
-- side and the podiums' far end, its back a stud short of the train stop's line, a stud clear of
-- the fence's 45-degree corner wall)
BaseLayout.CleaningStation = {
	Center = Vector3.new(GRID_HALF + 1 - 1.6 * 6 - 1.8, 0, YARD_Z0 + 29.8 - 1.6 * 4 - 1),
	R = 0,
	Scale = 1.6,
	Area = rect(GRID_HALF + 1 - 1.6 * 6 - 1.8, YARD_Z0 + 29.8 - 1.6 * 4 - 1, 12 * 1.6, 10, 8 * 1.6),
}

-- Where the coastal railway's centerline ran behind the yard, plot-local (along X). The train
-- and its stops went 2026-11-17; the lobby keeps the strip behind every yard clear to here
-- (PlotBuilder.yardBounds, LobbyLayout), so nothing else moves.
BaseLayout.RailZ = YARD_Z0 + 37

-- Reserved for the artifact museum (step 7): it keeps its place by the left
-- yard wall (x -12 at 12 cells), so its look and part count never change.
BaseLayout.Museum = rect(-(GRID_HALF + 1) + 13, YARD_Z0 + 26, 22, 10, 8)

--[[
	The VIP cave behind every yard (owner 2026-11-17: in place of the VIP mine at the quarry, "a
	little cave on every plot where the train unloaded ore ... it opens only with the pass", built
	"in the rainbow mountain style with waterfalls round it"; only the plot's owner with the
	Forgemaster's Pass goes in, 5 rocks of the Glimmer Grotto's ore inside). Plot-local:
	  Door   the glowing curtain in the middle of the back wall (PlotBuilder.BackWallZ), tagged
	         VipDoor: solid for everyone but the owner who has the pass (AccessController)
	  Room   the cave inside the mound, from the back wall back to the island's edge
	  Mound  the rainbow voxel mountain round it (World/PlotCave)
	  Rocks  the 5 rock spots, past the yard's pickup margin (ItemService.onBase)
]]
BaseLayout.VipCave = {
	-- (owner 2026-11-17 evening: "widen the VIP cave a bit, it's terribly narrow in there") a wide
	-- door, a room 40 across, 18 deep and 12 high
	Door = { CenterX = 0, Width = 10, Height = 8.6 },
	-- (it runs back past the island's edge: World/PlotCave opens Land's boundary wall and lowers the
	-- coastal rocks there, its own walls close it)
	Room = { Min = Vector3.new(-20, 0, 64.2), Max = Vector3.new(20, 12, 84) },
	Mound = { Min = Vector3.new(-27, 0, 63.8), Max = Vector3.new(27, 27, 90) },
	-- (round an open middle: two by the front corners, three along the back)
	Rocks = {
		Vector3.new(-15, 0, 70.4),
		Vector3.new(-12, 0, 79.2),
		Vector3.new(0, 0, 79.2),
		Vector3.new(12, 0, 79.2),
		Vector3.new(15, 0, 70.4),
	},
	-- (owner: "put the new ore in there", his Meshy rocks) each spot's rock is that floor's model of
	-- that kind (RockBuilder: the Deep Hollow's blue geodes, Azure Shards and its Golden Rock); the
	-- grotto's ores, health and rules stay (MiningService)
	RockFloor = "DeepHollow",
	RockKinds = { "Geode", "Crystal", "Golden", "Crystal", "Geode" },
	-- (owner 2026-11-17 night: "add two more ores in the middle, from location 4") two of the Sunken
	-- Palace's rocks (mine floor 4) in the middle, as on that floor: its ores, its health and its
	-- blaster level (7), its Meshy models (Royal Shard, Geode); a way in from the door between them
	FloorRocks = {
		{ At = Vector3.new(-6, 0, 72), Floor = 4, Kind = "Crystal" },
		{ At = Vector3.new(6, 0, 72), Floor = 4, Kind = "Geode" },
	},
	-- (owner: "a chance there, but really small, that an ore of locations 5 and 6 drops") every ore a
	-- cave rock rolls, each time it grows back, may be one of these floors' ores instead (half each);
	-- the Forgemaster's Pass says so before the buy (MonetizationConfig.grottoOddsText)
	Rare = { Floors = { "StormglassRift", "HeartstoneCore" }, Chance = 0.005 },
}

-- Every fixed piece, for overlap tests.
function BaseLayout.pieces(): { [string]: Rect }
	local list: { [string]: Rect } = {
		Pen = BaseLayout.Pen.Area,
		CleaningStation = BaseLayout.CleaningStation.Area,
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
	Chute cells (step 3, docs/plans/STEP3_PLAN.md): a fixed cell on the
	back row of the machine grid (gz = PlotCells - 1, next to the yard; cell
	numbers as in Machines/Grid). Only belts may stand on them: Placement
	refuses every other machine there (reason "Chute") and moves one off
	when a saved layout has it there (sanitize reason "Chute": its own toast).
	  Pen      Source  items sent from the Ore Pen (PenAction "Send") come out here
	(The FOUNDRY chute, a Sink into the Foundry, went with the Foundry
	(owner 2026-10-24), and the TRAIN chute, the train's Direct Unload, with
	the train (owner 2026-11-17); a belt on an old chute cell is an ordinary
	belt.)
	A Source only spawns an item onto a belt standing on its cell whose front
	is NOT SinkRotation (sourceFeeds: a belt running off the grid edge would
	drop the item loose in the yard), and only while that belt has room (the
	belt's direction decides the route). With no such belt, or a jammed one,
	nothing comes out: the pen's send queue waits. A Source never drops an
	item loose.
	Players must see the chutes (WP-Belts, shipped in the same merge as these
	contracts so the "Chute" refusal and toast always point at something
	visible): a colored plate with the Label in build mode (GridOverlay) and a
	small floor plate + sign per chute in the world (ConveyorService, per
	plot), both in the chute's Color; a Source's plate shows "Turn the belt
	away from the yard" while its belt faces SinkRotation.
]]
local BACK_ROW = GameConfig.PlotCells - 1

-- X: 3 at 12 cells (+ GRID_SHIFT on a bigger grid): plot-local x -10 at any size, in line
-- with the pen gate.
BaseLayout.Chutes = {
	Pen = {
		X = 3 + GRID_SHIFT,
		Z = BACK_ROW,
		Kind = "Source",
		Label = "PEN",
		Color = Color3.fromRGB(72, 160, 255),
		Hint = "Items you send from your Ore Pen come out here.",
	},
} :: { [string]: Chute }

-- The chute names in a fixed order (loops, UI).
BaseLayout.ChuteNames = { "Pen" }

-- Grid rotation of a belt that runs off the grid's back edge toward the yard: Grid.dir(2) = (0, 1), +Z
-- (the old FOUNDRY Sink's direction; a Source refuses a belt turned so, sourceFeeds).
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

return BaseLayout
