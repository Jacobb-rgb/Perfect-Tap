--[[
	Meadow (owner 2026-10-18: "grass with flowers on the green places outside
	the plots, fences along the roads and the lawns with trees"):

	  Fences    low wooden fences (the Kenney Fantasy Town fence look) where a
	            road or path meets a lawn, in short runs with gaps to walk through
	  Ponds     up to five ponds with lily pads and reeds on the bigger free
	            lawns (one at the end of the hamlet lane, where the MAP hamlet stood)
	  Jungle    light jungle trees (the Blaster Vault's look, 14 parts each) on
	            the free lawns and on the grassy tops of the Land mountains
	  Lawn      grass tufts, lighter and darker grass patches, flower beds
	            (yellow, white, purple, pink) clustered over the free lawns,
	            bushes and small rocks; a glowing lantern on every fence end
	  Life      koi circling in every pond, butterflies over a few flower
	            beds (tag Spin, client-side, ~60 moving parts in all)
	  South     the lawn behind the Blaster Vault, where the bigger plots
	            first left a sea bay (owner 2026-10-22): a koi pond, voxel
	            trees and its share of the lawn's pieces (Meadow.SouthLawn)

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
local StreetLampPlan = require(script.Parent.Parent.Plaza.StreetLampPlan)
local Kit = require(script.Parent.Kit)
local Town = require(script.Parent.Town)
local Railway = require(script.Parent.Parent.Parent.Railway)
local Planets = require(script.Parent.Parent.Sky.Planets)

local C = Style.C

local Meadow = {}

-- Where the meadow may grow (the town ground: 2 studs inside the island's
-- coasts, x +-168 and z 148 at 12 cells) and what stays clear.
Meadow.Area = {
	Min = Vector3.new(WorldLayout.Island.Min.X + 2, 0, -118),
	Max = Vector3.new(WorldLayout.Island.Max.X - 2, 0, WorldLayout.Island.Max.Z - 2),
}
Meadow.VaultClear = { Min = Vector3.new(-28, 0, 72), Max = Vector3.new(28, 0, 156) }
Meadow.SpawnClear = 12
-- the bridge garden under and behind THE GREAT FORGE's roof (Plaza/BridgeGarden, owner 2026-10-20)
Meadow.BridgeGarden = { Min = Vector3.new(-22, 0, -114), Max = Vector3.new(22, 0, -38) }
--[[
	The lawn behind the Blaster Vault (owner 2026-10-22: "don't leave that gap
	in the middle, put island there too"): the bigger plots first left a sea
	bay there, between the plot roads from the 12-cell south coast (z 150) to
	the south coast; now it is island like the lawns either side. Its look is
	planned (southLawn below): a koi pond in the middle, voxel trees at its
	sides (autumn toward the MINE in the west, pink and green toward the
	hamlet in the east, like the woods either side), flower beds, grass
	tufts, patches, bushes and stones. The town's passes (and the wilds) keep
	out of it, and its lawn pieces count toward Meadow.Max (phones: no budget
	raise), so the town's capped lawn thins by about a quarter (see
	Meadow.Max). x +-52 meets the town's lawn
	beside the plot roads (the MINE yard's rails reach x -59). nil at 12
	cells, where the south coast is z 150.
]]
Meadow.SouthLawn = if WorldLayout.PlotGrid.SouthShift > 0
	then { Min = Vector3.new(-52, 0, 150), Max = Vector3.new(52, 0, Meadow.Area.Max.Z) }
	else nil
-- (phone trims 2026-10-18: fewer tufts, flower beds of 3 single-block flowers on a 1-part mound)
-- (2026-10-22: the lawn behind the Vault takes its share of these, Meadow.SouthLawnMax, and
-- 28 tufts went for its pond and trees: phones. The town's lawn, measured after the wilds
-- clear their spots, went from ~750 parts to ~550: tufts 100 -> 58, flower beds 47 -> 34,
-- patches 60 -> 52, bushes 36 -> 30, rocks 24 -> 20. Giving it back costs ~200 parts of
-- Flora's lobby budget and the map's, which have ~50 and ~110 left: the owner's call.)
Meadow.Max = { Tufts = 72, Flowers = 50, Patches = 60, Bushes = 36, Rocks = 24 }
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
-- fence line past the road edge (2026-10-20: behind the street lamps' feet, so the runs pass them)
Meadow.FenceOffset = if StreetLampPlan.Enabled then 2.8 else 2

local FLOWERS = { C.FlowerYellow, C.FlowerWhite, C.FlowerPurple, C.LeafPink, C.LeafPinkLight }

---------------------------------------------------------------- free ground index

type Box = { Min: Vector3, Max: Vector3 }
local CELL = 8
local TOWN_NORTH_Z = -122 -- the town ground's north edge (the quarry rim road)

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

-- Every visible part of `map` from the ground up (y -0.5..160), but the ground
-- itself (and but `skip`'s parts: Flora/Wilds lets its pieces replace the lawn's).
function Meadow.index(map: Instance, skip: Instance?): Index
	local index: Index = { Cells = {}, Ground = nil }
	local skipped: { [Instance]: boolean } = {}
	if skip then
		for _, d in skip:GetDescendants() do
			skipped[d] = true
		end
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not skipped[d] then
			local box = bounds(d)
			local parent = d.Parent
			if d.Name == "Ground" and parent and parent.Name == "Land" then
				-- the town ground (the strips beside the quarry, north of the
				-- town (z -122), are not the town's)
				if box.Max.Z > TOWN_NORTH_Z + 1 then
					local g = index.Ground
					index.Ground = if g
						then {
							Min = Vector3.new(math.min(g.Min.X, box.Min.X), math.min(g.Min.Y, box.Min.Y), math.min(g.Min.Z, box.Min.Z)),
							Max = Vector3.new(math.max(g.Max.X, box.Max.X), math.max(g.Max.Y, box.Max.Y), math.max(g.Max.Z, box.Max.Z)),
						}
						else box
				end
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

-- Allowed for the meadow at all: in the town area (or `area`), off the plots
-- and their yards, the keep-outs, the spawn, the vault approach and the
-- planned lawn behind the Vault (but for its own pass, `area` = Meadow.SouthLawn).
function Meadow.allowed(p: Vector3, r: number, area: Box?): boolean
	if not inBox(p, area or Meadow.Area, -r) or inBox(p, Meadow.VaultClear, r) or inBox(p, Meadow.BridgeGarden, r) then
		return false
	end
	-- (the lawn behind the Vault out to the coast: the wilds' secrets may use the ground's edge)
	local south = Meadow.SouthLawn
	if south and area ~= south and p.X > south.Min.X - r and p.X < south.Max.X + r and p.Z > south.Min.Z - r then
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

-- Adds every part of `model` to the index (other builders that run before
-- the meadow use this too: Plaza/Life, Flora/Stream).
Meadow.track = track

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
Meadow.MinPonds = 3 -- tests/Meadow.spec.luau (owner: "more ponds")
-- the size a pond shrinks to where its drawn size finds no room (the town's
-- lawns are full: the stream, the plaza life and the outcrop clearances took
-- the old spots)
Meadow.SmallPond = Vector2.new(7.5, 6.5)
Meadow.MaxLobbyTrees = 22
-- (bigger plots) no lobby jungle trees south of the 12-cell island's south coast:
-- the south band's new lawns keep their ponds and meadow (phones; the lawn
-- behind the Vault plants its own trees, Meadow.SouthLawn)
Meadow.LobbyTreesMaxZ = WorldLayout.Island.Max.Z - WorldLayout.PlotGrid.SouthShift
Meadow.MaxMountainTrees = 40
-- The pond the hamlet lane (LobbyLayout HamletLane / ToMap) now leads to,
-- where the MAP tower and its hamlet stood (the south band: it moves south
-- with the plot columns, WorldLayout.PlotGrid.SouthShift).
Meadow.LanePond = { Center = Vector3.new(101, 0, 127 + WorldLayout.PlotGrid.SouthShift), Size = Vector2.new(17, 12) }

local AUTUMN = { "Yellow", "Orange", "Pink", "Red" }

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

-- Would a tree crown at `p` (trunk h, canopy R) hide one of the Sky
-- package's planets from the town (Planets.Town)?
local function hidesPlanet(p: Vector3, h: number, R: number): boolean
	local crown = p + Vector3.new(0, h + 5, 0)
	local toCrown = crown - Planets.Town
	local crownAngle = math.asin(math.min(1, (R + 3) / math.max(toCrown.Magnitude, 1)))
	for _, spec in Planets.Specs do
		local toPlanet = Planets.center(spec) - Planets.Town
		local ringed = if spec.Ring then spec.Ring.Outer else 1.1
		local planetAngle = math.atan(Planets.diameter(spec) / 2 * ringed / toPlanet.Magnitude)
		local apart = math.acos(math.clamp(toPlanet.Unit:Dot(toCrown.Unit), -1, 1))
		if apart < crownAngle + planetAngle + 0.03 then
			return true
		end
	end
	return false
end

-- A light jungle tree in the Vault's blocky Minecraft-jungle style: a root
-- flare and a thick trunk, three octagonal canopy layers, two branches with
-- leaf clumps, two hanging vines. 14 parts.
local function jungleTree(parent: Instance, base: Vector3, h: number, R: number, rng: Rng.Rng, tint: { Color3 }?): Model
	local m = Style.model("JungleTree", parent)
	-- leaf, lit leaf (an autumn tree takes a Style.TreeKinds palette, like the concept's colourful crowns)
	local leaf = if tint then tint[2] else JUNGLE.Leaf
	local leafLight = if tint then tint[1] else JUNGLE.LeafLight
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
		local a, b = if i == 2 then leafLight else leaf, if i == 2 then leaf else leafLight
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
		Style.block(m, CFrame.new(tip + Vector3.new(0, 0.6, 0)), Vector3.new(R * 0.55, R * 0.4, R * 0.55), leaf)
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
-- A small turning group around an invisible hub (tag Spin: the client's
-- DecorController turns and bobs it; Atomic so its parts stream together).
local function spinner(parent: Instance, name: string, hub: Vector3, speed: number, bob: number, bobSpeed: number): (Model, Part)
	local m = Style.model(name, parent)
	local core = Style.block(m, CFrame.new(hub), Vector3.new(0.4, 0.4, 0.4), C.Foam, nil, Style.tiny({ Transparency = 1 }))
	core.Name = "Hub"
	m.PrimaryPart = core
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", speed)
	m:SetAttribute("BobHeight", bob)
	m:SetAttribute("BobSpeed", bobSpeed)
	Style.streaming(m, "Atomic")
	return m, core
end

-- A frame at `off` from a hub facing along the circle the hub turns it on
-- (a hub turning by +angle moves a point (x, z) along (z, -x)).
local function onCircle(hub: Vector3, off: Vector3): CFrame
	local p = hub + off
	return CFrame.lookAt(p, p + Vector3.new(off.Z, 0, -off.X).Unit)
end

-- Two koi circling under the pond's surface: body and tail. 5 parts.
local KOI = { Color3.fromRGB(255, 122, 40), Color3.fromRGB(250, 240, 230) }
local function koi(parent: Instance, center: Vector3, r: number, rng: Rng.Rng)
	-- (just at the surface, like the concept's koi)
	local hub = center + Vector3.new(0, 0.7, 0)
	local m = spinner(parent, "Koi", hub, rng:range(0.25, 0.4), 0.04, 1)
	for i = 0, 1 do
		local a = i * math.pi + rng:range(-0.3, 0.3)
		local cf = onCircle(hub, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		Style.block(m, cf, Vector3.new(0.55, 0.22, 1.3), KOI[i + 1], nil, Style.tiny())
		Style.block(m, cf * CFrame.new(0, 0, 0.85), Vector3.new(0.6, 0.12, 0.45), KOI[2 - i], nil, Style.tiny())
	end
end

local function pond(parent: Instance, center: Vector3, sx: number, sz: number, rng: Rng.Rng): Model
	local m = Style.pond(parent, center, sx, sz, rng)
	koi(m, center, math.min(sx, sz) * 0.22, rng)
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
	local made = 0
	local function try(p: Vector3, sx: number, sz: number): boolean
		local r = math.max(sx, sz) / 2 + 1.5
		-- (ponds are low: unlike the trees they may sit in the core's lawns)
		if not Meadow.allowed(p, r) or zoned(p, r, { Meadow.KoiBridge, Meadow.VaultZone, Meadow.ForgeBack }) or nearRail(p, r) then
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
		made += 1
		return true
	end
	if not try(Meadow.LanePond.Center, Meadow.LanePond.Size.X, Meadow.LanePond.Size.Y) then
		-- the stream's pond (Flora/Stream) is there now: keep the others as far off it
		table.insert(placed, Meadow.LanePond.Center)
	end
	-- a fine grid: the free lawn left between the town's pieces comes in small windows
	local spots: { Vector3 } = {}
	local x = Meadow.Area.Min.X + 10
	while x < Meadow.Area.Max.X - 10 do
		local z = Meadow.Area.Min.Z + 10
		while z < Meadow.Area.Max.Z - 10 do
			table.insert(spots, Vector3.new(x + rng:range(-1, 1), 0, z + rng:range(-1, 1)))
			z += 3
		end
		x += 3
	end
	for i = #spots, 2, -1 do
		local j = rng:int(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	for _, p in spots do
		if made >= Meadow.MaxPonds then
			break
		end
		local sx, sz = rng:range(9, 13), rng:range(7, 9)
		if not try(p, sx, sz) then
			try(p, Meadow.SmallPond.X, Meadow.SmallPond.Y)
		end
	end
	return m
end

-- (Plaza/BridgeGarden plants the same jungle trees)
Meadow.jungleTree = jungleTree

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
		if p.Z > Meadow.LobbyTreesMaxZ then
			continue
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
			and not hidesPlanet(p, h, R)
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
				and not hidesPlanet(p, h, R)
			then
				-- about a third of the mountain trees wear autumn colours
				local tint: { Color3 }? = nil
				if rng:chance(0.35) then
					tint = Style.TreeKinds[AUTUMN[rng:int(1, #AUTUMN)]]
				end
				track(index, jungleTree(m, p, h, R, rng, tint))
				table.insert(placed, p)
				count += 1
			end
		end
	end
	return m
end

-- A small glowing lantern on a fence's end and middle posts (the concept's
-- warm lights along every fence): an amber glass and an iron cap. 2 parts,
-- glow only (no light).
local function fenceLantern(parent: Instance, foot: Vector3)
	local m = Style.model("FenceLantern", parent)
	local h = Meadow.FenceHeight
	-- (phones: 2 parts, an amber glass and an iron cap; the post carries it)
	local glass = Style.block(
		m,
		CFrame.new(foot + Vector3.new(0, h + 0.5, 0)),
		Vector3.new(0.85, 1, 0.85),
		Common.Colors.AmberGlass,
		Enum.Material.Neon,
		Style.tiny()
	)
	glass.Name = "LanternGlow"
	Style.block(m, CFrame.new(foot + Vector3.new(0, h + 1.1, 0)), Vector3.new(1.1, 0.22, 1.1), C.Iron, nil, Style.tiny())
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
			-- (past the road's edge border and the street lamps' feet)
			local offset = s.Width / 2 + Meadow.FenceOffset
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
					for _, q in { pa, (pa + pb) / 2, pb } do
						fenceLantern(m, q)
					end
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

--[[
	The lawn's flat pieces (the grass patches and the flower beds' mounds)
	stand a little off the ground: their tops would share a plane with Land's
	tint patches (tops at y 0.12) and with each other where two overlap, and
	two coplanar faces of different shades flicker as the camera moves
	(z-fighting). Each one takes the lowest of Meadow.FlatLifts that no
	overlapping flat piece of the same lawn has taken.
]]
Meadow.FlatLifts = { 0.03, 0.06, 0.09, 0.12 }
type Flat = { At: Vector3, R: number, Top: number }

-- The lift for a flat piece w wide and h tall at `p` (recorded in `flats`).
local function flatLift(flats: { Flat }, p: Vector3, w: number, h: number): number
	-- (a w x w square at any turn stays inside the square of this half-size round p: two
	-- pieces clash when those squares overlap, as their world boxes may)
	local r = w * 0.71
	local lifts = Meadow.FlatLifts
	local chosen = lifts[#lifts]
	for _, lift in lifts do
		local clash = false
		for _, f in flats do
			if math.abs(f.Top - (h + lift)) < 0.01 and math.abs(p.X - f.At.X) < r + f.R and math.abs(p.Z - f.At.Z) < r + f.R then
				clash = true
				break
			end
		end
		if not clash then
			chosen = lift
			break
		end
	end
	table.insert(flats, { At = p, R = r, Top = h + chosen })
	return chosen
end

-- A flat patch (octagonal: a square and its twin turned 45 degrees), `lift`
-- studs off the ground.
local function patch(parent: Instance, p: Vector3, w: number, h: number, color: Color3, rng: Rng.Rng, octagon: boolean?, lift: number?)
	local cf = CFrame.new(p + Vector3.new(0, h / 2 + (lift or 0), 0)) * CFrame.Angles(0, rng:range(0, math.pi / 2), 0)
	Style.block(parent, cf, Vector3.new(w, h, w * rng:range(0.75, 1)), color, nil, Style.tiny())
	if octagon then
		Style.block(parent, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.85, h * 0.98, w * 0.7), color, nil, Style.tiny())
	end
end

-- A grass tuft: two blades fanned out, one taller. 2 parts.
local function tuft(parent: Instance, p: Vector3, rng: Rng.Rng)
	local h = rng:range(1.3, 2.1)
	local color = Style.vary(if rng:chance(0.5) then C.GrassLight else C.LeafGreenLight, rng, 0.06)
	local base = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
	for _, i in { -0.5, 0.5 } do
		local bh = h * (if i < 0 then 1 else 0.75)
		local blade = base * CFrame.Angles(0, 0, math.rad(i * 30)) * CFrame.new(i * 0.4, bh / 2, 0)
		Style.block(parent, blade, Vector3.new(0.28, bh, 0.5), color, nil, Style.tiny())
	end
end

-- A flower bed: a leafy mound and 4-6 flowers (a plus-shaped head on top).
local function flowerBed(parent: Instance, p: Vector3, color: Color3, rng: Rng.Rng, flats: { Flat })
	local w = rng:range(2.4, 3.2)
	local mound = Style.vary(C.LeafGreenDark, rng, 0.05)
	patch(parent, p, w, 0.45, mound, rng, nil, flatLift(flats, p, w, 0.45))
	for _ = 1, 3 do
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

type LawnCounts = { Tufts: number, Flowers: number, Patches: number, Bushes: number, Rocks: number }
type Near = { At: Vector3, R: number }

-- Is `p` within R of one of `near`'s points?
local function close(p: Vector3, near: { Near }): boolean
	for _, q in near do
		if Vector3.new(p.X - q.At.X, 0, p.Z - q.At.Z).Magnitude < q.R then
			return true
		end
	end
	return false
end

-- The lawn pieces over `area` (the town: Meadow.Area; the lawn behind the
-- Vault: Meadow.SouthLawn, only `near` its pond and trees) up to `caps`;
-- `count` holds what is already placed (it counts on). Returns the model and
-- the flower beds' spots.
local function lawn(parent: Instance, index: Index, rng: Rng.Rng, area: Box, caps: LawnCounts, count: LawnCounts, near: { Near }?)
	local m = Style.model("Lawn", parent)
	local seed = rng:range(0, 10)
	local function allowed(p: Vector3, r: number): boolean
		return Meadow.allowed(p, r, area)
	end
	-- every free spot first, then shuffled: the caps thin the whole town
	-- evenly instead of filling the west side first
	local spots: { Vector3 } = {}
	local x = area.Min.X + 2
	while x < area.Max.X - 2 do
		local z = area.Min.Z + 2
		while z < area.Max.Z - 2 do
			local p = Vector3.new(x + rng:range(-1.4, 1.4), 0, z + rng:range(-1.4, 1.4))
			if allowed(p, 1.6) and (not near or close(p, near)) and Meadow.free(index, p, 1.6, 2.5) then
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
	local beds: { Vector3 } = {}
	local flats: { Flat } = {}
	for _, p in spots do
		local n = patchNoise(p.X, p.Z, seed)
		local roll = rng:next()
		-- bushes and small rocks (the concept's busy ground), a few of each first
		if roll > 0.9 and count.Bushes < caps.Bushes and allowed(p, 2.4) and Meadow.free(index, p, 2, 3) then
			Style.bush(m, p, Style.vary(if rng:chance(0.7) then C.LeafGreen else C.LeafGreenDark, rng, 0.05), rng, rng:range(1.8, 2.6))
			count.Bushes += 1
			continue
		elseif roll > 0.84 and count.Rocks < caps.Rocks and allowed(p, 1.8) then
			local s = rng:range(1, 1.8)
			local cf = CFrame.new(p + Vector3.new(0, s * 0.35, 0)) * CFrame.Angles(0, rng:range(0, math.pi), rng:range(-0.2, 0.2))
			Style.block(m, cf, Vector3.new(s * 1.3, s * 0.8, s), Style.vary(C.Stone, rng, 0.06), nil, Style.tiny())
			Style.block(
				m,
				cf * CFrame.new(s * 0.6, -s * 0.15, s * 0.3),
				Vector3.new(s * 0.6, s * 0.5, s * 0.6),
				Style.vary(C.StoneLight, rng, 0.06),
				nil,
				Style.tiny()
			)
			count.Rocks += 1
			continue
		end
		-- (each kind checks its own reach against the sites and aprons)
		if n > 0.58 and roll < 0.7 and count.Flowers < caps.Flowers and allowed(p, 2.4) then
			flowerBed(m, p, FLOWERS[math.floor(n * 97 + p.X * 0.013) % #FLOWERS + 1], rng, flats)
			table.insert(beds, p)
			count.Flowers += 1
		elseif roll < 0.25 and count.Patches < caps.Patches and allowed(p, 3.6) and Meadow.free(index, p, 2.8, 1) then
			local shade = if rng:chance(0.5) then C.GrassLight else C.GrassDark
			local w = rng:range(3, 5.5)
			local color = Style.vary(shade, rng, 0.04)
			patch(m, p, w, 0.12, color, rng, nil, flatLift(flats, p, w, 0.12))
			count.Patches += 1
		elseif roll < 0.75 and count.Tufts < caps.Tufts then
			tuft(m, p, rng)
			count.Tufts += 1
		end
	end
	return m, beds
end

-- Butterflies fluttering in small circles over a few flower beds (at most
-- `most`), spread over the town: 2-3 each, two wings per butterfly.
Meadow.ButterflyBeds = 6
local WINGS = { C.FlowerYellow, C.FlowerWhite, C.LeafPinkLight, C.CrystalCyan }
local function butterflies(parent: Instance, beds: { Vector3 }, rng: Rng.Rng, most: number)
	local m = Style.model("Butterflies", parent)
	local chosen: { Vector3 } = {}
	for _, p in beds do
		if #chosen >= most then
			break
		end
		local far = true
		for _, q in chosen do
			far = far and (p - q).Magnitude > 40
		end
		-- (their circles reach 2.2 studs out: never over a road)
		if far and Common.offStrips(p, 2.6) then
			table.insert(chosen, p)
		end
	end
	for _, p in chosen do
		local hub = p + Vector3.new(0, 2.4, 0)
		local group = spinner(m, "Flutter", hub, rng:range(0.7, 1.1), 0.5, rng:range(1.5, 2.2))
		for i = 1, rng:int(2, 3) do
			local a = i * 2.2 + rng:range(-0.4, 0.4)
			local r = rng:range(1.2, 2.2)
			local cf = onCircle(hub, Vector3.new(math.cos(a) * r, rng:range(-0.4, 0.5), math.sin(a) * r))
			local color = WINGS[rng:int(1, #WINGS)]
			for _, side in { -1, 1 } do
				local wing = cf * CFrame.new(side * 0.32, 0.1, 0) * CFrame.Angles(0, 0, side * math.rad(35))
				Style.block(group, wing, Vector3.new(0.65, 0.06, 0.55), color, nil, Style.tiny())
			end
		end
	end
	return m
end

---------------------------------------------------------------- the lawn behind the Vault

-- (Meadow.SouthLawn) Its pond in the middle, on the south road's line, and
-- its trees: Flora's lean voxel trees like the woods either side, autumn
-- toward the MINE in the west, pink and green toward the hamlet in the
-- east, south of the Vault's own jungle crowns (z ~171). Each one moves a
-- little where its spot is taken.
Meadow.SouthPond = { Center = Vector3.new(0, 0, 189), Size = Vector2.new(20, 13) }
Meadow.SouthTrees = {
	{ At = Vector3.new(-43, 0, 181), Kind = "Yellow", Scale = 1.1 },
	{ At = Vector3.new(-29, 0, 199), Kind = "Orange", Scale = 1.0 },
	{ At = Vector3.new(-44, 0, 203), Kind = "Orange", Scale = 1.15 },
	{ At = Vector3.new(43, 0, 182), Kind = "Pink", Scale = 1.1 },
	{ At = Vector3.new(30, 0, 198), Kind = "Green", Scale = 1.0 },
	{ At = Vector3.new(45, 0, 204), Kind = "Pink", Scale = 1.15 },
	-- and a smaller pair between the Vault's back and the pond
	{ At = Vector3.new(-14, 0, 176), Kind = "Green", Scale = 0.9 },
	{ At = Vector3.new(14, 0, 177), Kind = "Red", Scale = 0.9 },
} :: { { At: Vector3, Kind: string, Scale: number } }
-- its share of the lawn's caps (Meadow.Max: the town's lawn gets the rest),
-- round its pond and its trees (Meadow.SouthNear studs past their edges);
-- per free lawn spot (~280 there, ~710 in the town) it is no denser than the
-- town's lawn, so a smaller share would only thin it below the town's look
Meadow.SouthLawnMax = { Tufts = 14, Flowers = 12, Patches = 8, Bushes = 6, Rocks = 4 }
Meadow.SouthNear = 8

-- A spot at `at` or a little off it (rings of 8, 2 studs apart) where a
-- piece of radius r and height top fits in the lawn behind the Vault (`south`).
local function southSpot(index: Index, south: Box, at: Vector3, r: number, top: number): Vector3?
	for ring = 0, 3 do
		for k = 0, if ring == 0 then 0 else 7 do
			local a = k * math.pi / 4
			local p = at + Vector3.new(math.cos(a), 0, math.sin(a)) * (ring * 2)
			if Meadow.allowed(p, r, south) and not nearRail(p, r) and Meadow.free(index, p, r, top) then
				return p
			end
		end
	end
	return nil
end

-- Builds the lawn behind the Vault (nothing at 12 cells); returns what its
-- lawn pieces took of the caps.
local function southLawn(parent: Instance, index: Index, rng: Rng.Rng): LawnCounts
	local count = { Tufts = 0, Flowers = 0, Patches = 0, Bushes = 0, Rocks = 0 }
	local south = Meadow.SouthLawn
	if not south then
		return count
	end
	local m = Style.model("SouthLawn", parent)
	local near: { Near } = {}
	local spec = Meadow.SouthPond
	local r = math.max(spec.Size.X, spec.Size.Y) / 2 + 1.5
	local at = southSpot(index, south, spec.Center, r, 4)
	if at then
		track(index, pond(m, at, spec.Size.X, spec.Size.Y, rng))
		table.insert(near, { At = at, R = r + Meadow.SouthNear })
	end
	for _, t in Meadow.SouthTrees do
		local reach = Kit.treeReach(t.Scale) + 0.6
		local p = southSpot(index, south, t.At, reach, Kit.treeHeight(t.Scale) + 2)
		if p then
			local tree = Kit.leanTree(m, CFrame.new(p), t.Kind, rng, t.Scale)
			track(index, tree)
			table.insert(near, { At = p, R = reach + Meadow.SouthNear })
			-- a bush at its feet, toward the lawn's middle
			local foot = p + Vector3.new(-math.sign(p.X) * (reach + 1.2), 0, rng:range(-2, 2))
			if count.Bushes < Meadow.SouthLawnMax.Bushes and Meadow.allowed(foot, 2.2, south) and Meadow.free(index, foot, 2, 3) then
				local shade = Kit.shades(t.Kind)[3]
				Style.bush(m, foot, Style.vary(if rng:chance(0.5) then C.LeafGreenDark else shade, rng, 0.05), rng, rng:range(1.8, 2.4))
				count.Bushes += 1
			end
		end
	end
	local _, beds = lawn(m, index, rng, south, Meadow.SouthLawnMax, count, near)
	-- and butterflies over one of its flower beds
	butterflies(m, beds, rng, 1)
	return count
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
	local lawnRng = Rng.new(`Meadow/Lawn/{rng:nextU32()}`)
	local butterflyRng = Rng.new(`Meadow/Butterflies/{rng:nextU32()}`)
	-- the lawn behind the Vault first: its pieces count toward the town's caps
	local count = southLawn(m, index, Rng.new(`Meadow/SouthLawn/{rng:nextU32()}`))
	local _, beds = lawn(m, index, lawnRng, Meadow.Area, Meadow.Max, count)
	butterflies(m, beds, butterflyRng, Meadow.ButterflyBeds)
	decorate(m)
	return m
end

return Meadow
