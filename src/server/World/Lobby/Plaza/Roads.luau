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

	Lanterns every ~32 studs, alternating sides, along the spurs, the forge
	paths, the ROCK SCANNER path and the MINE lane: dark metal lantern pillars with
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
local WorldLayout = require(Shared.Config.WorldLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)
local StreetLampPlan = require(script.Parent.StreetLampPlan)

local Roads = {}

local LANTERN_EVERY = 32 -- (lobby fix round 2: 19 -> 32, fewer parts, the walkways still lit)
-- Roads that get Post lanterns, with the distance of the first one from the road start.
local LANTERN_ROADS = {
	-- (the south road ends at the Blaster Vault's steps, z 79: the gate
	-- pillars stand at its start, Flora lights the bridge and the vault's
	-- approach, so it has no posts)
	-- one post half way to the ROCK SCANNER, one where the MINE lane leaves
	-- the west plot road
	ToScanner = 14,
	MineLane = 3,
	EastSpur = 9,
	-- (the west spur's first lantern stands on the SHOP's side: it starts past
	-- the SHOP's south end, 2+ studs clear of its porch showcases)
	WestSpur = 15,
	ForgePathEast = 13,
	ForgePathWest = 13,
	-- (round 2: no posts along the quarry rim road: the Backdrop's lamps
	-- light the rim, the parts went into the town)
}
-- No road lanterns along the south road over the creek: Flora's arched bridge
-- has lamp boxes on its end posts and lamp fences at x +-5.3..13 there.
Roads.SouthRoadDarkZ = { 36, 66 }
-- Post lanterns that carry a light: the one nearest to this point on each road.
-- (the MINE lane sits in the south band: it moves south with the plot columns)
local LIT_POSTS = {
	MineLane = Vector3.new(-64, 0, 121 + WorldLayout.PlotGrid.SouthShift),
	EastSpur = Vector3.new(44, 0, 0),
	WestSpur = Vector3.new(-44, 0, 0),
}

-- Plaza entrances: two Pillar lanterns each (center, half spacing across, lit?).
-- The south pair stands a little down the road, behind the spawn camera, and
-- stays unlit (glow only), so the dark walkway is not washed out; the forge
-- side has no pair here: the Great Forge's stair cheeks carry two lit
-- lantern pillars (GreatForge.luau), clear of the banners.
-- (the south pair stands at the plaza rim beside the bridge's foot, 2 studs
-- off the koi pond and well clear of the spawn pad and the default camera)
type Entrance = { Center: Vector3, Across: Vector3, Lit: { boolean }, Height: number, Sides: { number }? }
local ENTRANCES: { Entrance } = {
	{ Center = Vector3.new(0, 0, 37.4), Across = Vector3.new(9, 0, 0), Lit = { false, false }, Height = 6.4 },
	{ Center = Vector3.new(37.6, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { true, false }, Height = 4.8 },
	-- (the west pair stands a little further out: Tobin's Sell stall sits
	-- south of the SHOP's door lane at the plaza rim; round 3: only its north
	-- lantern, CAPSULES' front stands where the south one was)
	{ Center = Vector3.new(-40.5, 0, 0), Across = Vector3.new(0, 0, 7.3), Lit = { true, false }, Height = 4.8, Sides = { -1 } },
}
-- (round 2: the koi pond took the entry planters' spot; the plaza's own
-- planters flank the chevron path instead, Paving.luau)
Roads.EntryPlanters = {} :: { Vector3 }

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
	-- (the koi pond sits right at the plaza rim: the walkway reaches at least
	-- 2.5 studs past the rim, under the bridge's foot)
	return {
		{ From = s.From, To = Vector3.new(s.From.X, 0, math.max(z0 - half, s.From.Z + 2.5)) },
		{ From = Vector3.new(s.To.X, 0, z1 + half), To = s.To },
	}
end

-- Glowing chevrons on the south walkway, pointing north to the forge
-- (z of each arrow's front tip): the concept v2 arrow, two bold, wide
-- deep-orange chevrons nested close together (on a dark backing chevron),
-- so they stay orange under bloom and lead the eye to the crystal.
Roads.ChevronZ = { 36.6 } -- (between the plaza rim and the bridge's foot)
Roads.ChevronSize = 2.8
Roads.ChevronThickness = 0.66 -- bold but not a road marking (30% thinner than round 1)
Roads.ChevronGap = 1.1

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

--[[
	The main roads (the two plot roads and the rim road; owner 2026-10-18:
	"make the roads cooler"): stone-paved like the cobble roads, with a dark
	kerb along both edges (broken where another road or path joins) and a
	small glowing amber stud on the kerb every StudEvery studs, so the roads
	light up at sunset like the plaza's neon walkways.
]]
Roads.StudEvery = 12
Roads.KerbColor = Color3.fromRGB(70, 66, 74)
local function roadEdges(parent: Instance, s: Common.Strip, r: Rng.Rng)
	local m = Style.model(s.Id .. "Edges", parent)
	local delta = Vector3.new(s.To.X - s.From.X, 0, s.To.Z - s.From.Z)
	local length = delta.Magnitude
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local half = s.Width / 2
	local y = (s.Lift or 0) + 0.2
	for _, side in { -1, 1 } do
		-- kerb runs: skip where another strip meets this edge
		local runs: { { number } } = {}
		local start: number? = nil
		local t = -half
		while t <= length + half + 0.01 do
			local p = s.From + dir * t + right * side * (half + 0.4)
			local joined = onPlaza(p, 0.5)
			for _, other in Common.strips() do
				if other.Id ~= s.Id and LobbyLayout.distanceToStrip(other.From, other.To, other.Width, p) < 0.6 then
					joined = true
					break
				end
			end
			if not joined and not start then
				start = t
			elseif joined and start then
				table.insert(runs, { start, t - 0.5 })
				start = nil
			end
			t += 0.5
		end
		if start then
			table.insert(runs, { start, length + half })
		end
		for _, run in runs do
			local a, b = run[1], run[2]
			if b - a < 1.5 then
				continue
			end
			local mid = s.From + dir * ((a + b) / 2) + right * side * (half + 0.4)
			local frame = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X, y, mid.Z) + dir)
			local kerb = Style.block(m, frame, Vector3.new(0.8, 0.4, b - a), Style.vary(Roads.KerbColor, r, 0.04), nil, Style.tiny())
			kerb.Name = "Kerb"
			-- glowing studs along the kerb
			local count = math.floor((b - a) / Roads.StudEvery)
			for i = 1, count do
				local tt = a + (b - a) * i / (count + 1)
				local q = s.From + dir * tt + right * side * (half + 0.4)
				local stud = Style.block(
					m,
					CFrame.lookAt(Vector3.new(q.X, y + 0.24, q.Z), Vector3.new(q.X, y + 0.24, q.Z) + dir),
					Vector3.new(0.45, 0.1, 0.9),
					Common.Colors.Amber,
					Enum.Material.Neon,
					Style.tiny()
				)
				stud.Name = "RoadStud"
			end
		end
	end
	return m
end

-- Walkways that leave the plaza rim head-on: a threshold ramp bridges the
-- step from the plaza floor down to their panels.
local THRESHOLDS = { SouthRoad = true, EastSpur = true, WestSpur = true, ToWheel = true, ToDroppers = true }
-- Long walkways with longer floor panels (fewer parts).
local LONG_SLABS = {
	ForgePathEast = true,
	ForgePathWest = true,
	EastPlotRoad = true,
	WestPlotRoad = true,
	RimRoad = true,
	ToNextArea = true,
}

local function paveAll(parent: Instance, rng: Rng.Rng)
	local m = Style.model("Roads", parent)
	-- kerbs and studs of the main roads (their own model: the Roads model
	-- holds exactly one strip model per road segment)
	local edges = Style.model("RoadEdges", parent)
	for _, s in Common.strips() do
		local cobble = s.Kind == "Cobble"
		-- curb stones along the first ~20 studs of cobble strips that leave the plaza
		local nearPlaza = onPlaza(s.From, 6)
		for i, seg in segments(s) do
			if s.Neon then
				local walk = Common.walkway(m, seg.From, seg.To, s.Width, rng, {
					Name = s.Id,
					Lift = s.Lift,
					Self = s.Id,
					EdgeInset = if s.Id == "SouthRoad" then 0 else 0.5,
					-- the long roads get longer slabs (fewer parts)
					RowScale = if LONG_SLABS[s.Id] then 1.35 else nil,
					-- (the south road's second piece starts past the bridge, far from the rim)
					Threshold = THRESHOLDS[s.Id] == true and i == 1,
				})
				if s.Id == "SouthRoad" and i == 1 then
					chevrons(walk, s)
				end
				continue
			end
			-- the main dirt roads are paved now, with kerbs and glowing studs
			local main = s.Main and not cobble
			Common.path(m, seg.From, seg.To, s.Width, rng, {
				Kind = if main then "Cobble" else s.Kind,
				Name = s.Id,
				Lift = s.Lift,
				-- (the other dirt paths: a few loose plates)
				TileEvery = if cobble or main then 4.5 else 8,
				CurbUntil = if cobble and nearPlaza and seg.From == s.From then 20 + s.Width / 2 + 6 else 0,
				CurbSkip = function(p: Vector3): boolean
					return onPlaza(p, 1.2)
				end,
			})
			if main then
				roadEdges(edges, s, rng)
			end
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
				-- (round 2: never inside the Great Forge's own footprint either)
				local forge = LobbyLayout.distanceTo(LobbyLayout.get("GreatForge"), p) < 1.5
				if not bridge and not forge and not onPlaza(p, 3) and Common.isClear(p, 1.3) and Common.offStrips(p, 0.9) then
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
					Style.lantern(m, base, { Kind = "Post", Light = lit, Range = 18, Brightness = 1.2, Color = Style.C.LampAmber })
				end
			end
		end
	end
end

local function entranceLanterns(parent: Instance)
	local m = Style.model("EntranceLanterns", parent)
	for _, e in ENTRANCES do
		for i, side in { -1, 1 } do
			if e.Sides and not table.find(e.Sides, side) then
				continue
			end
			local p = e.Center + e.Across * side
			local lit = e.Lit[i]
			Common.pillarLantern(m, CFrame.lookAt(p, Vector3.new(0, 0, 0)), {
				Height = e.Height,
				Light = lit,
				Range = 18,
				Brightness = 1.4,
			})
		end
	end
end

-- A dark metal planter with a blue neon lip and a small voxel tree (a
-- trunk, a leafy cube and a lighter cap). 6 parts.
local function entryPlanter(parent: Instance, at: Vector3, rng: Rng.Rng)
	local m = Style.model("EntryPlanter", parent)
	local K = Common.Colors
	local C = Style.C
	local base = CFrame.new(at)
	Style.block(m, base * CFrame.new(0, 0.8, 0), Vector3.new(2.6, 1.6, 2.6), K.MetalDark, nil, Style.solid()).Name = "Planter"
	Style.block(m, base * CFrame.new(0, 1.62, 0), Vector3.new(2.72, 0.1, 2.72), K.NeonBlueDeep, Enum.Material.Neon, Style.tiny())
	Style.block(m, base * CFrame.new(0, 1.66, 0), Vector3.new(2.3, 0.1, 2.3), C.DirtDark, nil, Style.tiny())
	Style.block(m, base * CFrame.new(0, 2.6, 0), Vector3.new(0.5, 1.9, 0.5), C.Trunk, nil, Style.tiny())
	local k = rng:range(2.4, 2.7)
	Style.block(
		m,
		base * CFrame.new(0, 3.3 + k * 0.4, 0),
		Vector3.new(k, k * 0.8, k),
		Style.vary(C.LeafGreen, rng, 0.04),
		nil,
		Style.ghost()
	)
	Style.block(
		m,
		base * CFrame.new(rng:range(-0.2, 0.2), 3.3 + k * 0.85, rng:range(-0.2, 0.2)),
		Vector3.new(k * 0.66, k * 0.32, k * 0.66),
		Style.vary(C.LeafGreenLight, rng, 0.04),
		nil,
		Style.tiny()
	)
end

--[[
	The DROPPERS apron (owner 2026-10-23: "a half circle in front of the
	house, of the path's material"): a half-round walkway in front of the
	porch, its straight edge along the porch front, its round edge meeting
	the ToDroppers walkway. The walkway's look: a dark slate base, two rings
	of polished slate panels, a dark metal border with an orange neon strip
	round the arc.
]]
local function droppersApron(parent: Instance, rng: Rng.Rng)
	local apron = LobbyLayout.DroppersApron
	local m = Style.model("DroppersApron", parent)
	local front = LobbyLayout.get("DroppersHouse").Facing.Unit
	local K = Common.Colors
	local top = Common.WalkwayTop
	local r, back = apron.Radius, apron.Back
	-- a ground frame on the straight edge's middle, local -Z = toward the round edge
	local look = CFrame.lookAt(apron.Center, apron.Center + front)
	local function ray(angle: number, dist: number, y: number): CFrame
		-- angle 0 = straight out from the porch, -90..90 degrees
		return look * CFrame.Angles(0, angle, 0) * CFrame.new(0, y, -dist)
	end
	local function base(c: CFrame, size: Vector3)
		Style.block(m, c, size, K.SlateDark, nil, Style.tiny({ CanQuery = true })).Name = "ApronBase"
	end
	local function panel(c: CFrame, size: Vector3, color: Color3)
		local tile = Style.block(m, c, size, color, nil, Style.tiny())
		tile.Reflectance = Common.TileReflectance
		tile.Name = "WalkPanel"
	end
	local function edge(c: CFrame, len: number)
		-- (local X along the edge)
		Style.block(m, c * CFrame.new(0, top.Border - 0.05, 0), Vector3.new(len + 0.1, 0.1, 0.65), K.MetalDark, nil, Style.tiny())
		local glow = Style.block(
			m,
			c * CFrame.new(0, top.Neon - 0.03, 0),
			Vector3.new(len - 0.1, 0.06, 0.2),
			K.NeonOrange,
			Enum.Material.Neon,
			Style.tiny()
		)
		glow.Name = "EdgeGlow"
	end
	-- the dark slate base (the seams between the panels): 8 sectors as wide
	-- as the round edge (they overlap toward the middle, one color) and the
	-- straight strip back to the house wall, so the apron is a clean U
	local count = 8
	local step = math.pi / count
	for i = 0, count - 1 do
		local angle = -math.pi / 2 + (i + 0.5) * step
		base(ray(angle, r / 2, top.Slab - 0.15), Vector3.new(2 * r * math.tan(step / 2), 0.3, r))
	end
	base(look * CFrame.new(0, top.Slab - 0.15, back / 2), Vector3.new(2 * r, 0.3, back))
	-- a round band of curved panels along the edge, then the walkways' grid inside it
	local band0, band1 = r - 2.6, r - 0.8
	local bands = 10
	local bandStep = math.pi / bands
	for i = 0, bands - 1 do
		local angle = -math.pi / 2 + (i + 0.5) * bandStep
		panel(
			ray(angle, (band0 + band1) / 2, top.Panel - 0.03),
			Vector3.new(2 * band0 * math.tan(bandStep / 2) - 0.2, 0.06, band1 - band0 - 0.2),
			Common.courseSlate(1, i, rng)
		)
	end
	local pitch, seam = 2.8, 0.2
	local inside = band0 - 0.15
	local porch = apron.PorchHalf
	for row = -3, 4 do
		for col = -5, 5 do
			local x, z = col * pitch, (row + 0.5) * pitch
			local fx = math.abs(x) + pitch / 2
			local ok
			if z > 0 then
				local fz = z + pitch / 2
				ok = fx * fx + fz * fz <= inside * inside
			else
				-- the straight strip either side of the porch, back to the wall
				ok = z - pitch / 2 >= -back + 0.1 and fx <= r - 0.8 and math.abs(x) - pitch / 2 >= porch
			end
			if ok then
				panel(
					look * CFrame.new(x, top.Panel - 0.03, -z),
					Vector3.new(pitch - seam, 0.06, pitch - seam),
					Common.courseSlate(row, col, rng)
				)
			end
		end
	end
	-- the edge: a dark metal border with its orange neon strip round the arc
	-- and straight on along both sides to the wall
	for i = 0, count - 1 do
		local angle = -math.pi / 2 + (i + 0.5) * step
		local at = r - 0.45
		edge(ray(angle, at, 0), 2 * at * math.tan(step / 2))
	end
	for _, sd in { -1, 1 } do
		edge(look * CFrame.new(sd * (r - 0.45), 0, back / 2) * CFrame.Angles(0, math.pi / 2, 0), back)
	end
end

function Roads.build(parent: Instance, rng: Rng.Rng)
	paveAll(parent, rng)
	droppersApron(parent, rng)
	-- (2026-10-20: the street lamps along every road replace the road lanterns, StreetLamps.luau)
	if not StreetLampPlan.Enabled then
		roadLanterns(parent)
	end
	entranceLanterns(parent)
	local planters = Style.model("EntryPlanters", parent)
	for _, at in Roads.EntryPlanters do
		entryPlanter(planters, at, rng)
	end
end

return Roads
