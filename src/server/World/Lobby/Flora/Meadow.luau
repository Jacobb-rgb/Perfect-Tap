--[[
	Meadow (owner 2026-10-18: "grass with flowers on the green places outside
	the plots, fences along the roads and the lawns with trees"):

	  Fences    low wooden fences (the Kenney Fantasy Town fence look) where a
	            road or path meets a lawn, in short runs with gaps to walk through
	  Lawn      grass tufts, lighter and darker grass patches and flower beds
	            (yellow, white, purple, pink) clustered over the free lawns

	It runs last (WorldBuilder, after the lobby, the plots and the railway) and
	only uses ground nothing else stands on: every built part near the ground
	is indexed on an 8-stud grid and a spot is free when no part overlaps it
	(Land.Ground and flat green lawn slabs count as ground). The plots and
	their yards, the keep-outs, the spawn and the Blaster Vault's approach
	(the owner's vault frame), the town buildings' sites and the clear aprons
	in front of the stalls (Flora.Kit) stay clear. (No new trees: the town's
	tree belts already line the lawns, and new crowns would break the stall,
	sign and railway clearances.) Pure decoration: no collision, no
	raycasts, no shadows, no lights. Parented to Emberfall.Lobby.Flora.Meadow
	(Flora's budget).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Parent.Plaza.Common)
local Kit = require(script.Parent.Kit)
local Town = require(script.Parent.Town)

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

-- Every visible part of `map` near the ground (y -0.5..16), but the ground itself.
function Meadow.index(map: Instance): Index
	local index: Index = { Cells = {}, Ground = nil }
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local box = bounds(d)
			local parent = d.Parent
			if d.Name == "Ground" and parent and parent.Name == "Land" then
				index.Ground = box
			elseif box.Max.Y > -0.5 and box.Min.Y < 16 and box.Max.X - box.Min.X < 600 and not isLawn(d, box) then
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
			local offset = s.Width / 2 + 1.4
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
	fences(m, index, Rng.new(`Meadow/Fences/{rng:nextU32()}`))
	lawn(m, index, Rng.new(`Meadow/Lawn/{rng:nextU32()}`))
	decorate(m)
	return m
end

return Meadow
