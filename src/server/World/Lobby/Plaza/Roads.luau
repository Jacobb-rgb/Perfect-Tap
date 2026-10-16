--[[
	Roads, paths and lanterns (LOBBY_PLAN 6.3.5 + 6.3.6).

	Every WorldLayout road and LobbyLayout path as a flat, non-collide strip
	over the solid ground (Common.path): the south road, the spurs, the
	forge paths and the district paths in cobble (curb stones near the
	plaza), the plot roads, the rim road, ToMine and ToNextArea in dirt.
	The south road stops at the creek bridge (Flora builds the bridge).

	Lanterns: Post lanterns every ~19 studs, alternating sides, along the
	south road, the spurs, the forge paths and the rim road; a pair of
	Pillar lanterns at each of the four plaza entrances. Seven of them carry
	a PointLight (four at the entrances, three on the roads).
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
local ENTRANCES = {
	-- the south pair stands a little down the road, behind the spawn camera
	{ Center = Vector3.new(0, 0, 44), Across = Vector3.new(7.3, 0, 0), Lit = { true, true } },
	{ Center = Vector3.new(37.6, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { true, false } },
	{ Center = Vector3.new(-37.6, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { false, true } },
	{ Center = Vector3.new(0, 0, -35.4), Across = Vector3.new(12.6, 0, 0), Lit = { false, false } },
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

local function paveAll(parent: Instance, rng: Rng.Rng)
	local m = Style.model("Roads", parent)
	for _, s in Common.strips() do
		local cobble = s.Kind == "Cobble"
		-- curb stones along the first ~20 studs of cobble strips that leave the plaza
		local nearPlaza = onPlaza(s.From, 6)
		for _, seg in segments(s) do
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
				-- the lamp arm reaches over the road (LookVector = toward the road)
				local look = -right * entry.Side
				local base = CFrame.lookAt(entry.P, entry.P + look)
				Style.lantern(m, base, { Kind = "Post", Light = i == litIndex, Range = 18, Brightness = 1.4 })
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
			Style.lantern(m, CFrame.lookAt(p, Vector3.new(0, 0, 0)), {
				Kind = "Pillar",
				Height = 4.6,
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
