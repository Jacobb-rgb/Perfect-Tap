--[[
	Generates a spray-washing job from (oreId, seed). Client and server run
	this with the same seed and get exactly the same dirt, so the server can
	replay the player's spray on its own (SprayScoring).

	Face coordinates: the dirty clump's face is roughly the unit disc, the ore
	(or a dusty relic) waits under the dirt.
	- Outline: convex silhouette of the clump (radius ~1).
	- Cells: a Grid x Grid square grid over [-1, 1]^2, clipped to the outline.
	  Each cell holds Amount seconds of dirt (sprayed point-blank at full
	  strength): thicker in the middle, thicker on rarer ores
	  (Rarity.DirtThickness).
	- Crystals: glowing crystals sticking out of the dirt (Rarity.FragileSpots)
	  on a clean pale base (their cell has no dirt). Spraying one point-blank
	  for too long cracks it.
	- Required: how many cells must come clean; the last few specks wash off
	  by themselves (FinishAt), so nobody hunts for one stray speck.
]]

local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local Rng = require(script.Parent.Parent.Util.Rng)
local Geometry2D = require(script.Parent.Geometry2D)

local CleaningPatterns = {}

CleaningPatterns.Grid = 14 -- cells per side over [-1, 1]
CleaningPatterns.CellDirt = 0.16 -- seconds of point-blank spray a Common cell needs (before the middle bonus)
CleaningPatterns.FinishAt = 0.98 -- share of the cells that must come clean
CleaningPatterns.CrystalZone = 0.6 -- crystals sit this close to the middle
CleaningPatterns.CrystalGap = 0.32 -- face units between two crystals

export type Cell = { Index: number, Gx: number, Gy: number, Center: Vector2, Amount: number }
export type Crystal = { Index: number, Center: Vector2 }

export type Pattern = {
	OreId: string,
	Seed: number,
	Rarity: string,
	Outline: { Vector2 },
	Grid: number,
	Origin: Vector2, -- the grid's lower-left corner
	CellSize: number,
	Cells: { Cell },
	CellAt: { [number]: number }, -- Gx * Grid + Gy -> cell index (cells inside the outline only)
	Crystals: { Crystal },
	TotalAmount: number,
	Required: number, -- clean cells that finish the job
}

local function makeOutline(rng: Rng.Rng): { Vector2 }
	local count = 9
	local points = {}
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + rng:range(-0.1, 0.1)
		local radius = rng:range(0.92, 1.0)
		table.insert(points, Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius))
	end
	return points
end

function CleaningPatterns.key(grid: number, gx: number, gy: number): number
	return gx * grid + gy
end

function CleaningPatterns.generate(oreId: string, seed: number): Pattern
	local ore = OreData.get(oreId)
	local rarity = Rarity.get(ore.Rarity)
	local rng = Rng.new(seed)
	local outline = makeOutline(rng)
	local grid = CleaningPatterns.Grid
	local cellSize = 2 / grid
	local origin = Vector2.new(-1, -1)

	-- every grid cell whose middle is on the clump
	local spots: { { Gx: number, Gy: number, Center: Vector2 } } = {}
	for gx = 0, grid - 1 do
		for gy = 0, grid - 1 do
			local center = origin + Vector2.new((gx + 0.5) * cellSize, (gy + 0.5) * cellSize)
			if Geometry2D.containsConvex(outline, center) then
				table.insert(spots, { Gx = gx, Gy = gy, Center = center })
			end
		end
	end

	-- crystals near the middle, apart from each other; their cells stay dirt-free
	local crystals: { Crystal } = {}
	local crystalCell: { [number]: boolean } = {}
	local candidates = {}
	for i, spot in spots do
		if spot.Center.Magnitude < CleaningPatterns.CrystalZone then
			table.insert(candidates, i)
		end
	end
	local wanted = rarity.FragileSpots
	while #crystals < wanted and #candidates > 0 do
		local pick = rng:int(1, #candidates)
		local spotIndex = candidates[pick]
		table.remove(candidates, pick)
		local center = spots[spotIndex].Center
		local free = true
		for _, c in crystals do
			if (c.Center - center).Magnitude < CleaningPatterns.CrystalGap then
				free = false
				break
			end
		end
		if free then
			table.insert(crystals, { Index = #crystals + 1, Center = center })
			crystalCell[spotIndex] = true
		end
	end

	-- dirt: thicker in the middle, a little uneven
	local cells: { Cell } = {}
	local cellAt: { [number]: number } = {}
	local total = 0
	for i, spot in spots do
		local r2 = math.min(1, spot.Center.Magnitude ^ 2)
		local amount = CleaningPatterns.CellDirt * rarity.DirtThickness * (0.8 + 0.4 * (1 - r2)) * rng:range(0.85, 1.15)
		if not crystalCell[i] then
			local cell: Cell = { Index = #cells + 1, Gx = spot.Gx, Gy = spot.Gy, Center = spot.Center, Amount = amount }
			table.insert(cells, cell)
			cellAt[CleaningPatterns.key(grid, spot.Gx, spot.Gy)] = cell.Index
			total += amount
		end
	end

	return {
		OreId = oreId,
		Seed = seed,
		Rarity = rarity.Id,
		Outline = outline,
		Grid = grid,
		Origin = origin,
		CellSize = cellSize,
		Cells = cells,
		CellAt = cellAt,
		Crystals = crystals,
		TotalAmount = total,
		Required = math.ceil(#cells * CleaningPatterns.FinishAt),
	}
end

return CleaningPatterns
