--[[
	Roads, paths and lanterns (LOBBY_PLAN 6.3.5 + 6.3.6, near the plaza
	restyled after concept v2).

	Every WorldLayout road and LobbyLayout path as a flat, non-collide strip
	over the solid ground. The walkways that leave the plaza (the south road
	up to the creek bridge, the spurs, the forge paths and the four district
	paths) are dark neon walkways (Common.walkway: polished slate panels,
	dark metal borders with orange neon edge strips, a dark metal threshold
	ramp at the plaza rim) and the south walkway carries bold glowing double
	chevrons pointing to the forge; the south road past the
	bridge and ToScanner stay cobble (Common.path), the plot roads, the rim
	road, ToMine and ToNextArea dirt. The south road stops at the creek
	bridge (Flora builds the bridge).

	Lanterns every ~19 studs, alternating sides, along the south road, the
	spurs, the forge paths and the rim road: dark metal lantern pillars with
	glowing orange slots along the neon walkways, wooden Post lanterns on
	the far roads; a pair of lantern pillars at the south, east and west
	plaza entrances (the forge's stair cheeks carry the north pair). Five of
	them carry a PointLight (one at the east and west entrances, three on
	the roads); the south pair glows without a light, so the dark walkway
	near the spawn stays dark.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local Roads = {}

local LANTERN_EVERY = 19
-- Roads that get Post lanterns, with the distance of the first one from the road start.
local LANTERN_ROADS = {
	-- the gate pillars stand at the road start (z 44); Flora lights the bridge
	-- and the ToScanner/ToMine junctions (z 75-80), so the posts start at z 95
	SouthRoad = 59,
	EastSpur = 9,
	WestSpur = 9,
	ForgePathEast = 13,
	ForgePathWest = 13,
	RimRoad = 10,
}
-- No road lanterns along the south road over the creek: Flora's arched bridge
-- has lamp boxes on its end posts and lamp fences at x +-5.3..13 there.
Roads.SouthRoadDarkZ = { 52, 72 }
-- Post lanterns that carry a light: the one nearest to this point on each road.
local LIT_POSTS = {
	SouthRoad = Vector3.new(0, 0, 100),
	EastSpur = Vector3.new(44, 0, 0),
	WestSpur = Vector3.new(-44, 0, 0),
}

-- Plaza entrances: two Pillar lanterns each (center, half spacing across, lit?).
-- The south pair stands a little down the road, behind the spawn camera, and
-- stays unlit (glow only), so the dark walkway is not washed out; the forge
-- side has no pair here: the Great Forge's stair cheeks carry two lit
-- lantern pillars (GreatForge.luau), clear of the banners.
local ENTRANCES = {
	{ Center = Vector3.new(0, 0, 44), Across = Vector3.new(7.3, 0, 0), Lit = { false, false } },
	{ Center = Vector3.new(37.6, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { true, false } },
	{ Center = Vector3.new(-37.6, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { false, true } },
}

local function onPlaza(p: Vector3, margin: number): boolean
	return Vector3.new(p.X, 0, p.Z).Magnitude < Common.PlazaRadius + margin
end

-- The pieces of a strip that are actually paved (the south road stops at the bridge).
local function segments(s: Common.Strip): { { From: Vector3, To: Vector3 } }
	if s.Id ~= "SouthRoad" then
		return { { From = s.From, To = s.To } }
	end
	local bridge = LobbyLayout.get("CreekBridge")
	local z0 = bridge.Center.Z - bridge.Size.Z / 2 + 1 -- the road reaches 1 stud under each bridge end
	local z1 = bridge.Center.Z + bridge.Size.Z / 2 - 1
	local half = s.Width / 2
	return {
		{ From = s.From, To = Vector3.new(s.From.X, 0, z0 - half) },
		{ From = Vector3.new(s.To.X, 0, z1 + half), To = s.To },
	}
end

-- Glowing chevrons on the south walkway, pointing north to the forge
-- (z of each arrow's front tip): the concept v2 arrow, two bold, wide
-- deep-orange chevrons nested close together (on a dark backing chevron),
-- so they stay orange under bloom and lead the eye to the crystal.
Roads.ChevronZ = { 39.5, 47 }
Roads.ChevronSize = 4.2
Roads.ChevronThickness = 0.95
Roads.ChevronGap = 1.9

local function chevrons(m: Model, s: Common.Strip)
	for _, z in Roads.ChevronZ do
		local y = s.Lift + Common.WalkwayTop.Neon - 0.03
		local tip = Vector3.new(s.From.X, y, z)
		local cf = CFrame.lookAt(tip, tip + Vector3.new(0, 0, -1))
		for _, part in Common.doubleChevron(m, cf, Roads.ChevronSize, Roads.ChevronThickness, Roads.ChevronGap, Common.Colors.Chevron) do
			part.Name = "Chevron"
		end
		-- the dark backing: one wide chevron under both strokes (flush with the panels)
		local back = cf * CFrame.new(0, -0.025, Roads.ChevronGap / 2)
		local backThick = Roads.ChevronThickness + Roads.ChevronGap * math.sin(Common.ChevronSpread) + 0.7
		for _, part in Common.chevron(m, back, Roads.ChevronSize + 1.4, backThick, Common.Colors.SlateDeep, 0.04, Common.ChevronSpread) do
			part.Material = Enum.Material.SmoothPlastic
			part.Name = "ChevronBacking"
		end
	end
end

-- Walkways that leave the plaza rim head-on: a threshold ramp bridges the
-- step from the plaza floor down to their panels.
local THRESHOLDS = { SouthRoad = true, EastSpur = true, WestSpur = true, ToWheel = true, ToFossil = true }

local function paveAll(parent: Instance, rng: Rng.Rng)
	local m = Style.model("Roads", parent)
	for _, s in Common.strips() do
		local cobble = s.Kind == "Cobble"
		-- curb stones along the first ~20 studs of cobble strips that leave the plaza
		local nearPlaza = onPlaza(s.From, 6)
		for i, seg in segments(s) do
			if s.Neon and i == 1 then
				local walk = Common.walkway(m, seg.From, seg.To, s.Width, rng, {
					Name = s.Id,
					Lift = s.Lift,
					Self = s.Id,
					EdgeInset = if s.Id == "SouthRoad" then 0 else 0.5,
					-- the long forge side paths get longer slabs (fewer parts)
					RowScale = if s.Id == "ForgePathEast" or s.Id == "ForgePathWest" then 1.35 else nil,
					Threshold = THRESHOLDS[s.Id] == true,
				})
				if s.Id == "SouthRoad" then
					chevrons(walk, s)
				end
				continue
			end
			Common.path(m, seg.From, seg.To, s.Width, rng, {
				Kind = s.Kind,
				Name = s.Id,
				Lift = s.Lift,
				TileEvery = if cobble then 4.5 elseif s.Main then 10 else 8,
				CurbUntil = if cobble and nearPlaza and seg.From == s.From then 20 + s.Width / 2 + 6 else 0,
				CurbSkip = function(p: Vector3): boolean
					return onPlaza(p, 1.2)
				end,
			})
		end
	end
end

-- First free lantern spot near `p` (sliding along the road, then the other side).
local function lanternSpot(s: Common.Strip, t: number, side: number, length: number): (Vector3?, number)
	local dir = Vector3.new(s.To.X - s.From.X, 0, s.To.Z - s.From.Z).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local offset = s.Width / 2 + 1.5
	for _, sd in { side, -side } do
		for _, shift in { 0, 2, -2, 4, -4, 6, -6 } do
			local tt = t + shift
			if tt > 1 and tt < length - 1 then
				local p = Vector3.new(s.From.X, 0, s.From.Z) + dir * tt + right * sd * offset
				local bridge = s.Id == "SouthRoad" and p.Z >= Roads.SouthRoadDarkZ[1] and p.Z <= Roads.SouthRoadDarkZ[2]
				if not bridge and not onPlaza(p, 3) and Common.isClear(p, 1.3) and Common.offStrips(p, 0.9) then
					return p, sd
				end
			end
		end
	end
	return nil, side
end

local function roadLanterns(parent: Instance)
	local m = Style.model("RoadLanterns", parent)
	for _, s in Common.strips() do
		local first = LANTERN_ROADS[s.Id]
		if first then
			local length = (Vector3.new(s.To.X, 0, s.To.Z) - Vector3.new(s.From.X, 0, s.From.Z)).Magnitude
			local dir = Vector3.new(s.To.X - s.From.X, 0, s.To.Z - s.From.Z).Unit
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local placed: { { P: Vector3, Side: number } } = {}
			local t = first
			local k = 0
			while t < length - 1 do
				local p, side = lanternSpot(s, t, if k % 2 == 0 then 1 else -1, length)
				if p then
					table.insert(placed, { P = p, Side = side })
				end
				k += 1
				t += LANTERN_EVERY
			end
			local litAt = LIT_POSTS[s.Id]
			local litIndex = 0
			if litAt then
				local best = math.huge
				for i, entry in placed do
					local d = (entry.P - litAt).Magnitude
					if d < best then
						best, litIndex = d, i
					end
				end
			end
			for i, entry in placed do
				-- the lamp arm / the glowing slots face the road (LookVector = toward the road)
				local look = -right * entry.Side
				local base = CFrame.lookAt(entry.P, entry.P + look)
				local lit = i == litIndex
				-- dark metal pillars along the neon walkways (the south road's lie past the bridge)
				if s.Neon and not (s.Id == "SouthRoad" and entry.P.Z > Roads.SouthRoadDarkZ[1]) then
					Common.pillarLantern(m, base, { Height = 4.2, Light = lit, Range = 18, Brightness = 1.4 })
				else
					Style.lantern(m, base, { Kind = "Post", Light = lit, Range = 18, Brightness = 1.4 })
				end
			end
		end
	end
end

local function entranceLanterns(parent: Instance)
	local m = Style.model("EntranceLanterns", parent)
	for _, e in ENTRANCES do
		for i, side in { -1, 1 } do
			local p = e.Center + e.Across * side
			local lit = e.Lit[i]
			Common.pillarLantern(m, CFrame.lookAt(p, Vector3.new(0, 0, 0)), {
				Height = 4.8,
				Light = lit,
				Range = 18,
				Brightness = 1.4,
			})
		end
	end
end

function Roads.build(parent: Instance, rng: Rng.Rng)
	paveAll(parent, rng)
	roadLanterns(parent)
	entranceLanterns(parent)
end

return Roads
