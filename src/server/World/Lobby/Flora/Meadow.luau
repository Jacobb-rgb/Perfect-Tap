--[[
	Meadow (owner 2026-10-18: "grass with flowers on the green places outside
	the plots, fences along the roads and the lawns with trees"):

	  Fences    low wooden fences (the Kenney Fantasy Town fence look) where a
	            road or path meets a lawn, in short runs with gaps to walk through
	  Ponds     up to five ponds with lily pads and reeds on the bigger free
	            lawns (one at the end of the hamlet lane, where the MAP hamlet stood)
	  Jungle    light jungle trees (the Blaster Vault's look, 14 parts each) on
	            the free lawns and on the grassy tops of the Land mountains
	  Lawn      grass tufts, lighter and darker grass patches and flower beds
	            (yellow, white, purple, pink) clustered over the free lawns

	It runs last (WorldBuilder, after the lobby, the plots and the railway) and
	only uses ground nothing else stands on: every built part near the ground
	is indexed on an 8-stud grid and a spot is free when no part overlaps it
	(Land.Ground and flat green lawn slabs count as ground). The plots and
	their yards, the keep-outs, the spawn and the Blaster Vault's approach
	(the owner's vault frame), the town buildings' sites and the clear aprons
	in front of the stalls (Flora.Kit) stay clear; the ponds and trees also keep
	out of the plaza views, the ground behind the Great Forge, the koi pond and
	the bridge, the vault with its statues and trees, and the railway lines,
	and their crowns check the whole height they reach. Pure decoration: no collision, no
	raycasts, no shadows, no lights. Parented to Emberfall.Lobby.Flora.Meadow
	(Flora's budget).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Parent.Plaza.Common)
local Kit = require(script.Parent.Kit)
local Town = require(script.Parent.Town)
local Railway = require(script.Parent.Parent.Parent.Railway)

local C = Style.C

local Meadow = {}

-- Where the meadow may grow (the town ground) and what stays clear.
Meadow.Area = { Min = Vector3.new(-168, 0, -118), Max = Vector3.new(168, 0, 148) }
Meadow.VaultClear = { Min = Vector3.new(-28, 0, 72), Max = Vector3.new(28, 0, 156) }
Meadow.SpawnClear = 12
Meadow.Max = { Tufts = 140, Flowers = 50, Patches = 60 }
-- Roads and paths that get fences (the walkways at the plaza's stalls and the
-- south road to the vault do not).
Meadow.FencedStrips = {
	EastPlotRoad = true,
	WestPlotRoad = true,
	RimRoad = true,
	ForgePathEast = true,
	ForgePathWest = true,
	EastSpur = true,
	WestSpur = true,
	ToScanner = true,
	MineLane = true,
}
Meadow.FenceRun = 20 -- longest fence piece; a 3-stud gap follows each
Meadow.FenceHeight = 2.4

local FLOWERS = { C.FlowerYellow, C.FlowerWhite, C.FlowerPurple, C.LeafPink, C.LeafPinkLight }

---------------------------------------------------------------- free ground index

type Box = { Min: Vector3, Max: Vector3 }
local CELL = 8

local function bounds(part: BasePart): Box
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local h = Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
	return { Min = cf.Position - h, Max = cf.Position + h }
end

local function cellKey(ix: number, iz: number): number
	return (ix + 2000) * 100000 + (iz + 2000)
end

export type Index = { Cells: { [number]: { Box } }, Ground: Box? }

local function add(index: Index, box: Box)
	for ix = math.floor(box.Min.X / CELL), math.floor(box.Max.X / CELL) do
		for iz = math.floor(box.Min.Z / CELL), math.floor(box.Max.Z / CELL) do
			local k = cellKey(ix, iz)
			local list = index.Cells[k]
			if not list then
				list = {}
				index.Cells[k] = list
			end
			table.insert(list, box)
		end
	end
end

-- Flat green slabs are lawn, not obstacles.
local function isLawn(part: BasePart, box: Box): boolean
	local c = part.Color
	return box.Max.Y <= 0.65 and part.Size.Y <= 0.6 and c.G > c.R + 0.08 and c.G > c.B + 0.05
end

-- Every visible part of `map` from the ground up (y -0.5..160), but the ground itself.
function Meadow.index(map: Instance): Index
	local index: Index = { Cells = {}, Ground = nil }
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local box = bounds(d)
			local parent = d.Parent
			if d.Name == "Ground" and parent and parent.Name == "Land" then
				index.Ground = box
			elseif box.Max.Y > -0.5 and box.Min.Y < 160 and box.Max.X - box.Min.X < 600 and not isLawn(d, box) then
				add(index, box)
			end
		end
	end
	return index
end

-- Is the ground spot `p` (radius r, up to `top` studs high) free?
function Meadow.free(index: Index, p: Vector3, r: number, top: number): boolean
	local ground = index.Ground
	if not ground or p.X - r < ground.Min.X or p.X + r > ground.Max.X or p.Z - r < ground.Min.Z or p.Z + r > ground.Max.Z then
		return false
	end
	if math.abs(ground.Max.Y) > 0.2 then
		return false
	end
	for ix = math.floor((p.X - r) / CELL), math.floor((p.X + r) / CELL) do
		for iz = math.floor((p.Z - r) / CELL), math.floor((p.Z + r) / CELL) do
			local list: { Box } = index.Cells[cellKey(ix, iz)] or {}
			for _, b in list do
				if
					b.Min.X < p.X + r
					and b.Max.X > p.X - r
					and b.Min.Z < p.Z + r
					and b.Max.Z > p.Z - r
					and b.Min.Y < top
					and b.Max.Y > 0.03
				then
					return false
				end
			end
		end
	end
	return true
end

-- Is the column around `p` (radius r) free between heights yLo and yHi?
function Meadow.freeBand(index: Index, p: Vector3, r: number, yLo: number, yHi: number): boolean
	for ix = math.floor((p.X - r) / CELL), math.floor((p.X + r) / CELL) do
		for iz = math.floor((p.Z - r) / CELL), math.floor((p.Z + r) / CELL) do
			local list: { Box } = index.Cells[cellKey(ix, iz)] or {}
			for _, b in list do
				if
					b.Min.X < p.X + r
					and b.Max.X > p.X - r
					and b.Min.Z < p.Z + r
					and b.Max.Z > p.Z - r
					and b.Min.Y < yHi
					and b.Max.Y > yLo
				then
					return false
				end
			end
		end
	end
	return true
end

local function inBox(p: Vector3, box: { Min: Vector3, Max: Vector3 }, margin: number): boolean
	return p.X > box.Min.X - margin and p.X < box.Max.X + margin and p.Z > box.Min.Z - margin and p.Z < box.Max.Z + margin
end

-- Allowed for the meadow at all: in the town area, off the plots and their
-- yards, the keep-outs, the spawn and the vault approach.
function Meadow.allowed(p: Vector3, r: number): boolean
	if not inBox(p, Meadow.Area, -r) or inBox(p, Meadow.VaultClear, r) then
		return false
	end
	if Vector3.new(p.X - WorldLayout.SpawnPoint.X, 0, p.Z - WorldLayout.SpawnPoint.Z).Magnitude < Meadow.SpawnClear + r then
		return false
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, r + 1) then
			return false
		end
	end
	-- the ore outcrops: their rocks grow there at runtime (not in the index)
	local flat = Vector3.new(p.X, 0, p.Z)
	for _, spot in WorldLayout.OutcropSpots do
		if (flat - Vector3.new(spot.X, 0, spot.Z)).Magnitude < r + 6 then
			return false
		end
	end
	for _, site in Town.Sites do
		if p.X > site.Min.X - r - 0.5 and p.X < site.Max.X + r + 0.5 and p.Z > site.Min.Y - r - 0.5 and p.Z < site.Max.Y + r + 0.5 then
			return false
		end
	end
	for _, apron in Kit.Aprons do
		if Kit.apronDistance(apron, p) < r + 0.5 then
			return false
		end
	end
	return not WorldLayout.isKeepOut(p, r)
end

local function track(index: Index, model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			add(index, bounds(d))
		end
	end
end

local function decorate(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

---------------------------------------------------------------- pieces

---------------------------------------------------------------- ponds and jungle trees

-- (owner 2026-10-18: "more ponds, more forest, jungle trees all over the map")
-- Zones they keep out of, on top of Meadow.allowed: the plaza and the stalls
-- (the spawn and hero views), the ground behind the Great Forge, the koi pond
-- and the south road's bridge, the Blaster Vault with its statues and trees
-- (the owner's vault frame).
Meadow.Core = { Min = Vector3.new(-48, 0, -60), Max = Vector3.new(48, 0, 64) }
Meadow.ForgeBack = { Min = Vector3.new(-30, 0, -120), Max = Vector3.new(30, 0, -20) }
Meadow.KoiBridge = { Min = Vector3.new(-32, 0, 20), Max = Vector3.new(32, 0, 80) }
Meadow.VaultZone = { Min = Vector3.new(-72, 0, 58), Max = Vector3.new(72, 0, 160) }
Meadow.MaxPonds = 5
Meadow.MaxLobbyTrees = 22
Meadow.MaxMountainTrees = 40
-- The pond the hamlet lane (LobbyLayout HamletLane / ToMap) now leads to,
-- where the MAP tower and its hamlet stood.
Meadow.LanePond = { Center = Vector3.new(101, 0, 127), Size = Vector2.new(17, 12) }

-- the Blaster Vault's jungle tree colours (Vault/Kit)
local JUNGLE = {
	Bark = Color3.fromRGB(104, 76, 50),
	BarkDark = Color3.fromRGB(74, 52, 36),
	Leaf = Color3.fromRGB(48, 124, 42),
	LeafLight = Color3.fromRGB(78, 158, 56),
	Vine = Color3.fromRGB(38, 102, 34),
}

local function zoned(p: Vector3, margin: number, zones: { { Min: Vector3, Max: Vector3 } }): boolean
	for _, z in zones do
		if inBox(p, z, margin) then
			return true
		end
	end
	return false
end

-- The visible railway lines as flat segments (cached).
local railSegments: { { Vector3 } }? = nil
local function nearRail(p: Vector3, r: number): boolean
	if not railSegments then
		local list: { { Vector3 } } = {}
		local ok, lines = pcall(function()
			return Railway.visibleLines()
		end)
		if ok then
			for _, points in lines do
				for i = 1, #points - 1 do
					table.insert(list, { points[i], points[i + 1] })
				end
			end
		end
		railSegments = list
	end
	for _, seg in railSegments :: { { Vector3 } } do
		local a = Vector3.new(seg[1].X, 0, seg[1].Z)
		local b = Vector3.new(seg[2].X, 0, seg[2].Z)
		local q = Vector3.new(p.X, 0, p.Z)
		local ab = b - a
		local t = if ab.Magnitude > 1e-6 then math.clamp((q - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		if (a + ab * t - q).Magnitude < r + 5 then
			return true
		end
	end
	return false
end

-- A light jungle tree in the Vault's blocky Minecraft-jungle style: a root
-- flare and a thick trunk, three octagonal canopy layers, two branches with
-- leaf clumps, two hanging vines. 14 parts.
local function jungleTree(parent: Instance, base: Vector3, h: number, R: number, rng: Rng.Rng): Model
	local m = Style.model("JungleTree", parent)
	local T = math.clamp(h * 0.12, 2.2, 3.6)
	Style.block(
		m,
		CFrame.new(base + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, rng:range(0, 1.5), 0),
		Vector3.new(T * 1.6, 1.6, T * 1.6),
		JUNGLE.BarkDark
	)
	Style.block(m, CFrame.new(base + Vector3.new(0, h / 2, 0)), Vector3.new(T, h, T), Style.vary(JUNGLE.Bark, rng, 0.04))
	local y = h
	for i, k in { 1, 0.78, 0.48 } do
		local w = 2 * R * k
		local th = 3.4
		local c = base + Vector3.new(rng:range(-1, 1), y + th / 2 - 0.5, rng:range(-1, 1))
		local a, b = if i == 2 then JUNGLE.LeafLight else JUNGLE.Leaf, if i == 2 then JUNGLE.Leaf else JUNGLE.LeafLight
		Style.block(m, CFrame.new(c), Vector3.new(w, th, w), Style.vary(a, rng, 0.04))
		Style.block(
			m,
			CFrame.new(c) * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(w * 0.92, th * 0.96, w * 0.92),
			Style.vary(b, rng, 0.04)
		)
		y += th - 0.4
	end
	for i = 0, 1 do
		local ang = rng:range(0, math.pi * 2) + i * math.pi
		local d = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local from = base + Vector3.new(0, h * (0.55 + 0.15 * i), 0)
		local tip = from + Vector3.new(0, 2.5, 0) + d * (R * 0.75)
		Style.block(m, CFrame.lookAt((from + tip) / 2, tip), Vector3.new(1.1, 1.1, (tip - from).Magnitude), JUNGLE.Bark)
		Style.block(m, CFrame.new(tip + Vector3.new(0, 0.6, 0)), Vector3.new(R * 0.55, R * 0.4, R * 0.55), JUNGLE.Leaf)
	end
	for _ = 1, 2 do
		local ang = rng:range(0, math.pi * 2)
		local r = R * rng:range(0.65, 0.9)
		local len = rng:range(4, 9)
		Style.block(
			m,
			CFrame.new(base + Vector3.new(math.cos(ang) * r, h - 0.5 - len / 2, math.sin(ang) * r)),
			Vector3.new(0.5, len, 0.4),
			JUNGLE.Vine
		)
	end
	return m
end

-- A pond: Style.pond (deep water, water, a rim of stones) with lily pads and reeds.
local function pond(parent: Instance, center: Vector3, sx: number, sz: number, rng: Rng.Rng): Model
	local m = Style.pond(parent, center, sx, sz, rng)
	for _ = 1, 3 do
		local q = center + Vector3.new(rng:range(-sx * 0.3, sx * 0.3), 0.7, rng:range(-sz * 0.25, sz * 0.25))
		Geo.cylinder(m, q, 0.12, rng:range(1.6, 2.6), C.LeafGreen, nil, Style.tiny())
	end
	for _ = 1, 2 do
		local edge = Vector3.new(rng:range(-sx * 0.35, sx * 0.35), 0, (if rng:chance(0.5) then 1 else -1) * (sz / 2 - 1.4))
		for k = 1, 3 do
			local q = center + edge + Vector3.new(k * 0.5 - 1, 0, rng:range(-0.4, 0.4))
			local h = rng:range(2, 3.2)
			Style.block(m, CFrame.new(q + Vector3.new(0, h / 2, 0)), Vector3.new(0.22, h, 0.22), C.GrassDark, nil, Style.tiny())
			if k == 2 then
				Style.block(m, CFrame.new(q + Vector3.new(0, h + 0.3, 0)), Vector3.new(0.4, 0.8, 0.4), C.TrunkDark, nil, Style.tiny())
			end
		end
	end
	return m
end

local function ponds(parent: Instance, index: Index, rng: Rng.Rng)
	local m = Style.model("Ponds", parent)
	local placed: { Vector3 } = {}
	local function try(p: Vector3, sx: number, sz: number): boolean
		local r = math.max(sx, sz) / 2 + 1.5
		-- (ponds are low: unlike the trees they may sit in the core's lawns)
		if not Meadow.allowed(p, r) or zoned(p, r, { Meadow.KoiBridge, Meadow.VaultZone }) or nearRail(p, r) then
			return false
		end
		if not Meadow.free(index, p, r, 4) then
			return false
		end
		for _, q in placed do
			if (p - q).Magnitude < 32 then
				return false
			end
		end
		track(index, pond(m, p, sx, sz, rng))
		table.insert(placed, p)
		return true
	end
	try(Meadow.LanePond.Center, Meadow.LanePond.Size.X, Meadow.LanePond.Size.Y)
	local spots: { Vector3 } = {}
	local x = Meadow.Area.Min.X + 10
	while x < Meadow.Area.Max.X - 10 do
		local z = Meadow.Area.Min.Z + 10
		while z < Meadow.Area.Max.Z - 10 do
			table.insert(spots, Vector3.new(x + rng:range(-2, 2), 0, z + rng:range(-2, 2)))
			z += 6
		end
		x += 6
	end
	for i = #spots, 2, -1 do
		local j = rng:int(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	for _, p in spots do
		if #placed >= Meadow.MaxPonds then
			break
		end
		try(p, rng:range(9, 13), rng:range(7, 9))
	end
	return m
end

local function jungle(parent: Instance, map: Instance, index: Index, rng: Rng.Rng)
	local m = Style.model("Jungle", parent)
	local placed: { Vector3 } = {}
	local function spaced(p: Vector3, d: number): boolean
		for _, q in placed do
			if Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude < d then
				return false
			end
		end
		return true
	end
	-- the town's free lawns
	local spots: { Vector3 } = {}
	local x = Meadow.Area.Min.X + 6
	while x < Meadow.Area.Max.X - 6 do
		local z = Meadow.Area.Min.Z + 6
		while z < Meadow.Area.Max.Z - 6 do
			table.insert(spots, Vector3.new(x + rng:range(-2, 2), 0, z + rng:range(-2, 2)))
			z += 6
		end
		x += 6
	end
	for i = #spots, 2, -1 do
		local j = rng:int(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local lobby = 0
	for _, p in spots do
		if lobby >= Meadow.MaxLobbyTrees then
			break
		end
		-- (the town's lawns are small: smaller jungle trees than on the mountains)
		local h, R = rng:range(11, 15), rng:range(3.8, 4.8)
		local reach = R + 0.6
		if
			spaced(p, 2 * R + 3)
			and Meadow.allowed(p, reach)
			and not zoned(p, reach, { Meadow.Core, Meadow.ForgeBack, Meadow.KoiBridge, Meadow.VaultZone })
			and not nearRail(p, reach)
			and Meadow.free(index, p, reach, h + 10)
		then
			track(index, jungleTree(m, p, h, R, rng))
			table.insert(placed, p)
			lobby += 1
		end
	end
	-- the grassy tops of the Land mountains around the island
	local land = map:FindFirstChild("Land")
	local mountains = land and land:FindFirstChild("Mountains")
	if mountains then
		local caps: { BasePart } = {}
		for _, d in mountains:GetDescendants() do
			if d:IsA("BasePart") then
				local c = d.Color
				if d.Size.Y <= 1.2 and d.Size.X >= 10 and d.Size.Z >= 10 and c.G > c.R + 0.1 and c.G > c.B + 0.05 then
					table.insert(caps, d)
				end
			end
		end
		table.sort(caps, function(a: BasePart, b: BasePart): boolean
			local pa, pb = a.CFrame.Position, b.CFrame.Position
			return if pa.X ~= pb.X then pa.X < pb.X else pa.Z < pb.Z
		end)
		for i = #caps, 2, -1 do
			local j = rng:int(1, i)
			caps[i], caps[j] = caps[j], caps[i]
		end
		local count = 0
		for _, cap in caps do
			if count >= Meadow.MaxMountainTrees then
				break
			end
			local top = cap.CFrame.Position.Y + cap.Size.Y / 2
			local p = Vector3.new(
				cap.CFrame.Position.X + rng:range(-cap.Size.X * 0.25, cap.Size.X * 0.25),
				top,
				cap.CFrame.Position.Z + rng:range(-cap.Size.Z * 0.25, cap.Size.Z * 0.25)
			)
			local h, R = rng:range(18, 30), rng:range(7, 10)
			if
				spaced(p, 2 * R + 4)
				and not inBox(p, Meadow.Area, 4)
				and not WorldLayout.isKeepOut(p, R)
				and not nearRail(p, R + 2)
				and Meadow.freeBand(index, p, R + 1, top + 0.05, top + h + 12)
			then
				track(index, jungleTree(m, p, h, R, rng))
				table.insert(placed, p)
				count += 1
			end
		end
	end
	return m
end

local function fences(parent: Instance, index: Index, rng: Rng.Rng)
	local m = Style.model("Fences", parent)
	for _, s in Common.strips() do
		if not Meadow.FencedStrips[s.Id] then
			continue
		end
		local delta = Vector3.new(s.To.X - s.From.X, 0, s.To.Z - s.From.Z)
		local length = delta.Magnitude
		local dir = delta / length
		local right = Vector3.new(-dir.Z, 0, dir.X)
		for _, side in { -1, 1 } do
			-- (past the main roads' kerbs: half + 0.4 +- 0.4)
			local offset = s.Width / 2 + 2
			local runs: { { number } } = {}
			local start: number? = nil
			local t = 0
			while t <= length + 0.01 do
				local p = Vector3.new(s.From.X, 0, s.From.Z) + dir * t + right * side * offset
				local lawn = p + right * side * 1.6
				local ok = Meadow.allowed(p, 1)
					and Vector3.new(p.X, 0, p.Z).Magnitude > Common.PlazaRadius + 6
					and Common.offStrips(p, 1)
					and Meadow.free(index, p, 0.7, 3.2)
					and Meadow.free(index, lawn, 0.9, 3)
				if ok and not start then
					start = t
				elseif not ok and start then
					table.insert(runs, { start, t - 1 })
					start = nil
				end
				t += 1
			end
			if start then
				table.insert(runs, { start, length })
			end
			for _, run in runs do
				local a = run[1]
				while run[2] - a >= 5 do
					local b = math.min(run[2], a + Meadow.FenceRun)
					local pa = Vector3.new(s.From.X, 0, s.From.Z) + dir * a + right * side * offset
					local pb = Vector3.new(s.From.X, 0, s.From.Z) + dir * b + right * side * offset
					local fence = Style.fence(m, pa, pb, {
						Height = Meadow.FenceHeight,
						PostEvery = 4,
						Rails = 2,
						PostColor = C.WoodDark,
						RailColor = Style.vary(C.Wood, rng, 0.04),
					})
					track(index, fence)
					a = b + 3
				end
			end
		end
	end
	return m
end

-- An octagonal flat patch (a square and its twin turned 45 degrees).
local function patch(parent: Instance, p: Vector3, w: number, h: number, color: Color3, rng: Rng.Rng)
	local cf = CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:range(0, math.pi / 2), 0)
	Style.block(parent, cf, Vector3.new(w, h, w * rng:range(0.75, 1)), color, nil, Style.tiny())
	Style.block(parent, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.85, h * 0.98, w * 0.7), color, nil, Style.tiny())
end

-- A grass tuft: three blades fanned out, the middle one tallest.
local function tuft(parent: Instance, p: Vector3, rng: Rng.Rng)
	local h = rng:range(1.3, 2.1)
	local color = Style.vary(if rng:chance(0.5) then C.GrassLight else C.LeafGreenLight, rng, 0.06)
	local base = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
	for i = -1, 1 do
		local bh = h * (if i == 0 then 1 else 0.72)
		local blade = base * CFrame.Angles(0, 0, math.rad(i * 18)) * CFrame.new(i * 0.25, bh / 2, 0)
		Style.block(parent, blade, Vector3.new(0.28, bh, 0.5), color, nil, Style.tiny())
	end
end

-- A flower bed: a leafy mound and 4-6 flowers (a plus-shaped head on top).
local function flowerBed(parent: Instance, p: Vector3, color: Color3, rng: Rng.Rng)
	patch(parent, p, rng:range(2.4, 3.2), 0.45, Style.vary(C.LeafGreenDark, rng, 0.05), rng)
	for _ = 1, rng:int(3, 5) do
		local q = p + Vector3.new(rng:range(-1.1, 1.1), rng:range(0.75, 1.15), rng:range(-1.1, 1.1))
		local s = rng:range(0.75, 1.0)
		local head = CFrame.new(q) * CFrame.Angles(0, rng:range(0, math.pi), 0)
		local c = Style.vary(color, rng, 0.05)
		Style.block(parent, head, Vector3.new(s, 0.28, s * 0.38), c, nil, Style.tiny())
		Style.block(parent, head * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(s, 0.28, s * 0.38), c, nil, Style.tiny())
	end
end

-- Cheap smooth noise in 0..1 for clustering the flowers into patches.
local function patchNoise(x: number, z: number, seed: number): number
	return (math.sin(x * 0.09 + seed) * math.cos(z * 0.11 - seed * 0.7) + math.sin((x + z) * 0.05 + seed * 1.3)) * 0.25 + 0.5
end

local function lawn(parent: Instance, index: Index, rng: Rng.Rng)
	local m = Style.model("Lawn", parent)
	local seed = rng:range(0, 10)
	-- every free spot first, then shuffled: the caps thin the whole town
	-- evenly instead of filling the west side first
	local spots: { Vector3 } = {}
	local x = Meadow.Area.Min.X + 2
	while x < Meadow.Area.Max.X - 2 do
		local z = Meadow.Area.Min.Z + 2
		while z < Meadow.Area.Max.Z - 2 do
			local p = Vector3.new(x + rng:range(-1.4, 1.4), 0, z + rng:range(-1.4, 1.4))
			if Meadow.allowed(p, 1.6) and Meadow.free(index, p, 1.6, 2.5) then
				table.insert(spots, p)
			end
			z += 3.5
		end
		x += 3.5
	end
	for i = #spots, 2, -1 do
		local j = rng:int(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local count = { Tufts = 0, Flowers = 0, Patches = 0 }
	for _, p in spots do
		local n = patchNoise(p.X, p.Z, seed)
		local roll = rng:next()
		-- (each kind checks its own reach against the sites and aprons)
		if n > 0.58 and roll < 0.7 and count.Flowers < Meadow.Max.Flowers and Meadow.allowed(p, 2.4) then
			flowerBed(m, p, FLOWERS[math.floor(n * 97 + p.X * 0.013) % #FLOWERS + 1], rng)
			count.Flowers += 1
		elseif roll < 0.25 and count.Patches < Meadow.Max.Patches and Meadow.allowed(p, 3.6) and Meadow.free(index, p, 2.8, 1) then
			local shade = if rng:chance(0.5) then C.GrassLight else C.GrassDark
			patch(m, p, rng:range(3, 5.5), 0.12, Style.vary(shade, rng, 0.04), rng)
			count.Patches += 1
		elseif roll < 0.75 and count.Tufts < Meadow.Max.Tufts then
			tuft(m, p, rng)
			count.Tufts += 1
		end
	end
	return m
end

-- Builds the meadow into `map`'s Emberfall.Lobby.Flora (or the map if the
-- lobby is missing).
function Meadow.build(map: Instance, rng: Rng.Rng): Model
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	local flora = lobby and lobby:FindFirstChild("Flora")
	local m = Style.model("Meadow", flora or map)
	local index = Meadow.index(map)
	ponds(m, index, Rng.new(`Meadow/Ponds/{rng:nextU32()}`))
	fences(m, index, Rng.new(`Meadow/Fences/{rng:nextU32()}`))
	jungle(m, map, index, Rng.new(`Meadow/Jungle/{rng:nextU32()}`))
	lawn(m, index, Rng.new(`Meadow/Lawn/{rng:nextU32()}`))
	decorate(m)
	return m
end

return Meadow
