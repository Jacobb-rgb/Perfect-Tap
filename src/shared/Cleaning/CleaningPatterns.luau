--[[
	Generates a cleaning job from (oreId, seed). Client and server run this
	with the same seed and get exactly the same guide lines, so the server
	can re-score the player's input on its own.

	Face coordinates: the rough ore face is roughly the unit disc.
	- Outline: convex rock silhouette (radius ~1).
	- Cuts: chisel guide polylines around the core. Each cut removes crust
	  "caps" (convex polygons) between the line and the outer edge.
	  Straight cut: one chord. Gable cut (rarer ores): two segments meeting
	  at a corner, so you must change direction mid-cut.
	- Core: what remains after all cuts (convex). Dirt patches sit on it.
	- Fragile spots: glinting crystals in the dirt. Don't scrape them.
]]

local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local Rng = require(script.Parent.Parent.Util.Rng)
local Geometry2D = require(script.Parent.Geometry2D)

local CleaningPatterns = {}

export type Cut = {
	Index: number,
	Kind: string, -- "Straight" | "Gable"
	Line: { Vector2 }, -- guide polyline
	Length: number,
	Caps: { { Vector2 } }, -- crust pieces this cut removes
	Normals: { Vector2 }, -- outward normals of the cut lines (for the "inside" side)
	Offsets: { number },
}

export type Dirt = { Index: number, Center: Vector2, Size: number, Fragile: boolean }

export type Pattern = {
	OreId: string,
	Seed: number,
	Rarity: string,
	Outline: { Vector2 },
	Cuts: { Cut },
	Core: { Vector2 },
	Dirt: { Dirt },
	DirtCount: number, -- non-fragile patches that must be scraped
	Tolerance: number,
	MaxCutSpeed: number,
	PolishTurns: number,
}

local MIN_CORE_DISTANCE = 0.42 -- no cut line comes closer to the center than this

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

-- Splits `remaining` by one or two half-planes. Returns caps + new remaining.
local function applyHalfPlanes(remaining: { Vector2 }, normals: { Vector2 }, offsets: { number }): ({ { Vector2 } }, { Vector2 })
	local caps = {}
	local rest = remaining
	for i, n in normals do
		local cap = Geometry2D.clip(rest, n, offsets[i], false)
		if #cap >= 3 and math.abs(Geometry2D.area(cap)) > 1e-4 then
			table.insert(caps, cap)
		end
		rest = Geometry2D.clip(rest, n, offsets[i], true)
	end
	return caps, rest
end

local MIN_STRAIGHT_LENGTH = 0.6

local function straightCut(remaining: { Vector2 }, direction: Vector2, distance: number): (Cut?, { Vector2 })
	local n = direction.Unit
	local c = distance
	local point = n * c
	local tangent = Geometry2D.perp(n)
	local tMin, tMax = Geometry2D.lineSpan(remaining, point, tangent)
	-- a short chord removes a tiny sliver: move the line inward a bit (never past the core limit)
	while (not tMin or not tMax or (tMax :: number) - (tMin :: number) < MIN_STRAIGHT_LENGTH) and c - 0.06 >= MIN_CORE_DISTANCE do
		c -= 0.06
		point = n * c
		tMin, tMax = Geometry2D.lineSpan(remaining, point, tangent)
	end
	if not tMin or not tMax or (tMax :: number) - (tMin :: number) < MIN_STRAIGHT_LENGTH then
		return nil, remaining
	end
	local a = point + tangent * (tMin :: number)
	local b = point + tangent * (tMax :: number)
	local caps, rest = applyHalfPlanes(remaining, { n }, { c })
	if #caps == 0 then
		return nil, remaining
	end
	local line = { a, b }
	return {
		Index = 0,
		Kind = "Straight",
		Line = line,
		Length = Geometry2D.polylineLength(line),
		Caps = caps,
		Normals = { n },
		Offsets = { c },
	},
		rest
end

local function gableCut(remaining: { Vector2 }, direction: Vector2, apexDistance: number, spread: number): (Cut?, { Vector2 })
	local out = direction.Unit
	local apex = out * apexDistance
	if not Geometry2D.containsConvex(remaining, apex) then
		return nil, remaining
	end
	local n1 = Geometry2D.rotate(out, spread)
	local n2 = Geometry2D.rotate(out, -spread)
	local c1, c2 = n1:Dot(apex), n2:Dot(apex)
	if c1 < MIN_CORE_DISTANCE or c2 < MIN_CORE_DISTANCE then
		return nil, remaining
	end
	-- arm along line 2 (the part inside half-plane 1), then along line 1
	local function arm(n: Vector2, other: Vector2, otherC: number): Vector2?
		local tangent = Geometry2D.perp(n)
		local tMin, tMax = Geometry2D.lineSpan(remaining, apex, tangent)
		if not tMin or not tMax then
			return nil
		end
		local candidates = { apex + tangent * (tMin :: number), apex + tangent * (tMax :: number) }
		for _, p in candidates do
			if other:Dot(p) <= otherC + 1e-6 and (p - apex).Magnitude > 0.15 then
				return p
			end
		end
		return nil
	end
	local startPoint = arm(n2, n1, c1)
	local endPoint = arm(n1, n2, c2)
	if not startPoint or not endPoint then
		return nil, remaining
	end
	local caps, rest = applyHalfPlanes(remaining, { n1, n2 }, { c1, c2 })
	if #caps == 0 then
		return nil, remaining
	end
	local line = { startPoint :: Vector2, apex, endPoint :: Vector2 }
	return {
		Index = 0,
		Kind = "Gable",
		Line = line,
		Length = Geometry2D.polylineLength(line),
		Caps = caps,
		Normals = { n1, n2 },
		Offsets = { c1, c2 },
	},
		rest
end

function CleaningPatterns.generate(oreId: string, seed: number): Pattern
	local ore = OreData.get(oreId)
	local rarity = Rarity.get(ore.Rarity)
	local rng = Rng.new(seed)
	local outline = makeOutline(rng)
	local remaining = outline
	local cuts: { Cut } = {}

	-- decide which cuts are gables
	local gables = {}
	local order = {}
	for i = 1, rarity.Cuts do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = rng:int(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for i = 1, rarity.Notches do
		gables[order[i]] = true
	end

	local baseAngle = rng:range(0, math.pi * 2)
	for k = 1, rarity.Cuts do
		local angle = baseAngle + (k - 1) / rarity.Cuts * math.pi * 2 + rng:range(-0.2, 0.2)
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		local cut, rest = nil, remaining
		if gables[k] then
			cut, rest = gableCut(remaining, direction, rng:range(0.66, 0.74), rng:range(0.5, 0.72))
		end
		if not cut then
			local tilt = rng:range(-0.22, 0.22)
			cut, rest = straightCut(remaining, Geometry2D.rotate(direction, tilt), rng:range(0.5, 0.62))
		end
		if cut then
			cut.Index = #cuts + 1
			table.insert(cuts, cut)
			remaining = rest
		end
	end

	-- dirt grid clipped to the core, a few fragile crystals in it
	local dirt: { Dirt } = {}
	local n = rarity.DirtGrid
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in remaining do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
	end
	local cellX = (maxX - minX) / n
	local cellY = (maxY - minY) / n
	local size = math.min(cellX, cellY) * 1.08
	for gx = 0, n - 1 do
		for gy = 0, n - 1 do
			local center = Vector2.new(minX + (gx + 0.5) * cellX, minY + (gy + 0.5) * cellY)
			if Geometry2D.containsConvex(remaining, center) then
				table.insert(dirt, { Index = #dirt + 1, Center = center, Size = size, Fragile = false })
			end
		end
	end
	-- turn some inner patches into fragile spots
	local candidates = {}
	for _, d in dirt do
		if d.Center.Magnitude < 0.4 then
			table.insert(candidates, d)
		end
	end
	for _ = 1, math.min(rarity.FragileSpots, #candidates) do
		local index = rng:int(1, #candidates)
		candidates[index].Fragile = true
		table.remove(candidates, index)
	end
	local dirtCount = 0
	for _, d in dirt do
		if not d.Fragile then
			dirtCount += 1
		end
	end

	return {
		OreId = oreId,
		Seed = seed,
		Rarity = rarity.Id,
		Outline = outline,
		Cuts = cuts,
		Core = remaining,
		Dirt = dirt,
		DirtCount = dirtCount,
		Tolerance = rarity.Tolerance,
		MaxCutSpeed = rarity.MaxCutSpeed,
		PolishTurns = rarity.PolishTurns,
	}
end

return CleaningPatterns
