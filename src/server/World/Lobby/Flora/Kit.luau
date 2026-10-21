--[[
	Flora's local helpers on top of the shared Style kit: a placement
	registry (LobbyLayout.isFree + Flora's own taken spots + the sight-line
	rules of docs/plans/LOBBY_PLAN.md 6.5), lean voxel trees, pond rims with
	gaps, cattails, small crystals, lamp boxes and pumpkins.

	Pure builders (Instance creation only), deterministic from the rng.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local StreetLampPlan = require(script.Parent.Parent.Plaza.StreetLampPlan)

local C = Style.C
local NEON = Enum.Material.Neon

local Kit = {}

-- An independent random stream, so one section's changes never reshuffle another.
function Kit.sub(rng: Rng.Rng): Rng.Rng
	return Rng.new(rng:nextU32() + 1)
end

---------------------------------------------------------------- placement

export type Spot = { P: Vector3, R: number }
-- An axis-aligned keep-out rectangle in world XZ (town building sites).
export type Box = { Min: Vector2, Max: Vector2 }
export type Placer = { spots: { Spot }, boxes: { Box } }

-- Sight lines (LOBBY_PLAN 6.5): no tree within 6 studs of the south road
-- between z 36 and 100, nothing taller than 12 within 10 studs of the plaza curb.
Kit.SouthRoad = WorldLayout.Roads[1]
Kit.PlazaCurb = 35.6
Kit.LowZone = Kit.PlazaCurb + 10

function Kit.newPlacer(boxes: { Box }?): Placer
	return { spots = {}, boxes = boxes or {} }
end

--[[
	Clear aprons: the ground in front of a stall's front face, `Depth` studs
	deep and as wide as its footprint, where Flora puts nothing (no bush in
	the CAPSULES entrance, no tree crowding the ENCHANT door).
]]
export type Apron = { Id: string, Depth: number }
Kit.Aprons = {
	{ Id = "CapsuleStall", Depth = 4 },
	{ Id = "EnchantShop", Depth = 4 },
} :: { Apron }

-- The apron as an oriented rectangle on the ground (a footprint-like Piece).
function Kit.apronPiece(apron: Apron): LobbyLayout.Piece
	local piece = LobbyLayout.get(apron.Id)
	local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
	return {
		Id = apron.Id .. "Apron",
		Package = "Flora",
		Center = piece.Center + look * ((piece.Size.Z + apron.Depth) / 2),
		Size = Vector3.new(piece.Size.X, 0, apron.Depth),
		Facing = look,
		Note = "clear apron",
	}
end

-- Distance from a ground point to an apron (0 inside; Y ignored).
function Kit.apronDistance(apron: Apron, p: Vector3): number
	return LobbyLayout.distanceTo(Kit.apronPiece(apron), p)
end

-- Is a ground point at least `r` studs from every clear apron?
function Kit.apronClear(p: Vector3, r: number): boolean
	for _, apron in Kit.Aprons do
		if Kit.apronDistance(apron, p) < r then
			return false
		end
	end
	return true
end

-- Corners of a box footprint (world XZ, y = 0).
local function corners(piece: LobbyLayout.Piece): { Vector3 }
	local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local c = Vector3.new(piece.Center.X, 0, piece.Center.Z)
	local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
	return { c + right * hx + look * hz, c + right * hx - look * hz, c - right * hx - look * hz, c - right * hx + look * hz }
end

-- Do the projections of two point sets onto `axis` stay apart?
local function separated(a: { Vector3 }, b: { Vector3 }, axis: Vector3): boolean
	local a0, a1, b0, b1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in a do
		local t = p:Dot(axis)
		a0, a1 = math.min(a0, t), math.max(a1, t)
	end
	for _, p in b do
		local t = p:Dot(axis)
		b0, b1 = math.min(b0, t), math.max(b1, t)
	end
	return a1 < b0 or b1 < a0
end

--[[
	Exact XZ gap between an axis-aligned world box (lo..hi) and a piece's
	footprint (0 when they overlap). Two disjoint convex shapes are closest
	at a corner of one of them.
]]
function Kit.boxPieceGap(lo: Vector3, hi: Vector3, piece: LobbyLayout.Piece): number
	local box: Box = { Min = Vector2.new(lo.X, lo.Z), Max = Vector2.new(hi.X, hi.Z) }
	if piece.Radius then
		return math.max(0, Kit.boxDistance(box, piece.Center) - piece.Radius)
	end
	local rect = corners(piece)
	local quad = { Vector3.new(lo.X, 0, lo.Z), Vector3.new(hi.X, 0, lo.Z), Vector3.new(hi.X, 0, hi.Z), Vector3.new(lo.X, 0, hi.Z) }
	local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
	local axes = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), look, Vector3.new(-look.Z, 0, look.X) }
	local apart = false
	for _, axis in axes do
		apart = apart or separated(rect, quad, axis)
	end
	if not apart then
		return 0
	end
	local gap = math.huge
	for _, q in quad do
		gap = math.min(gap, LobbyLayout.distanceTo(piece, q))
	end
	for _, q in rect do
		gap = math.min(gap, Kit.boxDistance(box, q))
	end
	return gap
end

-- World XZ box of a part (rotation included), as min/max Vector3s.
function Kit.partBox(part: BasePart): (Vector3, Vector3)
	local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = part.CFrame:GetComponents()
	local s = part.Size
	local ex = math.abs(r00) * s.X / 2 + math.abs(r01) * s.Y / 2 + math.abs(r02) * s.Z / 2
	local ez = math.abs(r20) * s.X / 2 + math.abs(r21) * s.Y / 2 + math.abs(r22) * s.Z / 2
	local p = part.CFrame.Position
	return Vector3.new(p.X - ex, 0, p.Z - ez), Vector3.new(p.X + ex, 0, p.Z + ez)
end

-- Gap between a tree (trunk to crown) and every stall footprint (Districts pieces).
Kit.StallGap = 1.2

--[[
	Does every part of `model` keep Kit.StallGap off the stalls (Districts
	pieces: fences, walls, signs) and stay out of the clear aprons? The
	scatter builds a tree, checks it and takes it down again when it
	crowds a stall.
]]
function Kit.clearOfStalls(model: Instance): boolean
	local aprons = {}
	for _, apron in Kit.Aprons do
		table.insert(aprons, Kit.apronPiece(apron))
	end
	-- the whole model's box too (an L-shaped crown's box corner may come
	-- closer to a stall than any of its parts)
	local all0 = Vector3.new(math.huge, 0, math.huge)
	local all1 = Vector3.new(-math.huge, 0, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local lo, hi = Kit.partBox(d)
			all0 = Vector3.new(math.min(all0.X, lo.X), 0, math.min(all0.Z, lo.Z))
			all1 = Vector3.new(math.max(all1.X, hi.X), 0, math.max(all1.Z, hi.Z))
			for _, piece in LobbyLayout.Pieces do
				if piece.Package == "Districts" and LobbyLayout.isGroundPiece(piece) then
					if Kit.boxPieceGap(lo, hi, piece) < Kit.StallGap then
						return false
					end
				end
			end
			for _, apron in aprons do
				if Kit.boxPieceGap(lo, hi, apron) < 0.3 then
					return false
				end
			end
		end
	end
	if all0.X < math.huge then
		for _, piece in LobbyLayout.Pieces do
			if piece.Package == "Districts" and LobbyLayout.isGroundPiece(piece) then
				if Kit.boxPieceGap(all0, all1, piece) < Kit.StallGap then
					return false
				end
			end
		end
	end
	return true
end

-- Distance from a ground point to a keep-out box (0 inside; Y ignored).
function Kit.boxDistance(box: Box, p: Vector3): number
	local dx = math.max(box.Min.X - p.X, 0, p.X - box.Max.X)
	local dz = math.max(box.Min.Y - p.Z, 0, p.Z - box.Max.Y)
	return math.sqrt(dx * dx + dz * dz)
end

function Kit.take(placer: Placer, p: Vector3, r: number)
	table.insert(placer.spots, { P = Vector3.new(p.X, 0, p.Z), R = r })
end

--[[
	Free for a scattered thing of radius r (LobbyLayout.isFree and Flora's
	own spots). `reach` (optional, >= r) keeps a wider crown off the player
	bases and their yards as well.
]]
function Kit.free(placer: Placer, p: Vector3, r: number, reach: number?): boolean
	if not LobbyLayout.isFree(p, r) then
		return false
	end
	-- (2026-10-20) nothing scattered on a street lamp's spot, no crown through its pole
	if StreetLampPlan.near(p, math.max(r, reach or 0) + 1.2) then
		return false
	end
	if reach and reach > r then
		for _, plot in WorldLayout.Plots do
			if LobbyLayout.onBase(plot, p, reach) then
				return false
			end
		end
		local island = WorldLayout.Island
		if p.X < island.Min.X + reach or p.X > island.Max.X - reach or p.Z > island.Max.Z - reach then
			return false
		end
	end
	-- crowns (reach) and trunks (r) both stay clear of the town buildings
	-- (canopy radius + 2 studs: no crown cuts into a wall or a sign) and the stalls' aprons
	local clear = math.max(r, reach or 0) + (if reach then 2 else 0.5)
	for _, box in placer.boxes do
		if Kit.boxDistance(box, p) < clear then
			return false
		end
	end
	if not Kit.apronClear(p, clear) then
		return false
	end
	local flat = Vector3.new(p.X, 0, p.Z)
	for _, spot in placer.spots do
		if (flat - spot.P).Magnitude < r + spot.R then
			return false
		end
	end
	return true
end

-- Distance from a ground point to the south road strip.
function Kit.roadDistance(p: Vector3): number
	local road = Kit.SouthRoad
	return LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p)
end

-- Distance from the plaza center (XZ).
function Kit.plazaDistance(p: Vector3): number
	return Vector3.new(p.X, 0, p.Z).Magnitude
end

-- May a tree whose crown reaches `reach` studs from its trunk stand at p?
function Kit.treeAllowed(p: Vector3, reach: number, height: number): boolean
	if p.Z > 30 and p.Z < 106 and Kit.roadDistance(p) < 6 + reach then
		return false
	end
	if Kit.plazaDistance(p) < Kit.LowZone + reach and height > 12 then
		return false
	end
	return true
end

---------------------------------------------------------------- trees

-- Rough sizes of Style.tree at a scale (crown reach from the trunk, top height).
function Kit.treeReach(scale: number): number
	return 5.6 * scale
end
function Kit.treeHeight(scale: number): number
	return 14.8 * scale
end

-- Leaf shades per tree kind ({ light, mid, dark }): Style.TreeKinds plus
-- a light cherry pink (the Style pinks read magenta-to-purple in the
-- evening light).
Kit.TreeShades = {
	Cherry = { Color3.fromRGB(255, 214, 234), Color3.fromRGB(252, 176, 212), Color3.fromRGB(232, 136, 186) },
} :: { [string]: { Color3 } }

function Kit.shades(kind: string): { Color3 }
	return Kit.TreeShades[kind] or Style.TreeKinds[kind] or Style.TreeKinds.Green
end

--[[
	One canopy cluster: a mid core, a light cap on top (set in from the
	core's faces, its top above the core's) and a dark underside slab (its
	sides inside the core's, its bottom under the core's), so no faces
	share a plane. `cf` = the core's center, `k` = the core's width. 3 parts.
]]
local function cluster(parent: Instance, cf: CFrame, k: number, shades: { Color3 }, rng: Rng.Rng)
	local p = Style.ghost()
	Style.block(parent, cf, Vector3.new(k, k * 0.8, k), Style.vary(shades[2], rng, 0.03), nil, p)
	local cap = cf * CFrame.new(rng:range(-0.08, 0.08) * k, k * 0.5, rng:range(-0.08, 0.08) * k)
	Style.block(parent, cap, Vector3.new(k * 0.7, k * 0.32, k * 0.7), Style.vary(shades[1], rng, 0.03), nil, p)
	Style.block(parent, cf * CFrame.new(0, -k * 0.42, 0), Vector3.new(k * 0.86, k * 0.16, k * 0.86), shades[3], nil, Style.tiny())
end

--[[
	Hero tree (concept v1 voxel trees): a visible trunk with a root and two
	branch stubs carrying four offset canopy clusters of smaller voxels (the
	top one over the trunk, two lower ones out to the sides, one to the
	back), each light on top and dark underneath. `scale` 1-1.6; `sideX`
	(+1 / -1, optional) puts the big side cluster toward world +X / -X.
	~16 parts.
]]
function Kit.bigTree(parent: Instance, base: CFrame, kind: string, rng: Rng.Rng, scale: number, sideX: number?): Model
	local s = scale
	local m = Style.model("Tree", parent)
	local shades = Kit.shades(kind)
	local frame = base * CFrame.Angles(0, if sideX then 0 else rng:int(0, 3) * math.pi / 2, 0)
	local h = rng:range(6.4, 7.0) * s
	local tw = 1.4 * s
	local trunk = Style.block(m, frame * CFrame.new(0, h / 2, 0), Vector3.new(tw, h, tw), Style.vary(C.Trunk, rng, 0.04))
	trunk.Name = "Trunk"
	Style.block(
		m,
		frame * CFrame.new(tw * 0.55, 0.4 * s, 0.1 * s),
		Vector3.new(tw * 0.6, 0.8 * s, tw * 0.6),
		C.TrunkDark,
		nil,
		Style.tiny()
	)
	local side = if rng:chance(0.5) then 1 else -1
	if sideX then
		side = if sideX > 0 then 1 else -1
	end
	-- branch stubs toward the two side clusters
	Style.block(
		m,
		frame * CFrame.new(side * tw * 0.9, h * 0.78, 0.3 * s),
		Vector3.new(tw * 1.1, tw * 0.45, tw * 0.45),
		C.Trunk,
		nil,
		Style.tiny()
	)
	Style.block(
		m,
		frame * CFrame.new(-side * tw * 0.8, h * 0.88, -0.4 * s),
		Vector3.new(tw * 0.9, tw * 0.4, tw * 0.4),
		C.TrunkDark,
		nil,
		Style.tiny()
	)
	local clusters = {
		{ X = 0.2, Y = 2.7, Z = 0.1, K = 4.6 },
		{ X = side * 3.3, Y = 0.9, Z = 0.7, K = 3.9 },
		{ X = -side * 2.6, Y = 1.4, Z = -1.0, K = 3.5 },
		{ X = side * 0.6, Y = 0.5, Z = -2.7, K = 3.2 },
	}
	for _, c in clusters do
		local k = c.K * s * rng:range(0.94, 1.06)
		cluster(m, frame * CFrame.new(c.X * s, h + c.Y * s, c.Z * s), k, shades, rng)
	end
	return m
end

--[[
	Low-part voxel tree for the town-edge belts: a slim trunk and a crown of
	four blocks in three shades (a mid core, a light cap, a dark lower lump
	and a mid lump to one side). `lean` (a world XZ unit vector, optional)
	puts the lumps on that side only (the belt's plot-side row keeps its
	crown off the bases). 5-6 parts; every crown part stands over 5 studs.
]]
function Kit.beltTree(parent: Instance, base: CFrame, kind: string, rng: Rng.Rng, scale: number, lean: Vector3?, lift: number?): Model
	local s = scale
	local m = Style.model("Tree", parent)
	local shades = Kit.shades(kind)
	-- `lift`: a taller trunk by the roads, so the crown clears head height
	local h = rng:range(4.8, 5.6) * s + (lift or 0)
	local tw = 1.0 * s
	local trunk = Style.block(m, base * CFrame.new(0, h / 2, 0), Vector3.new(tw, h, tw), Style.vary(C.Trunk, rng, 0.04))
	trunk.Name = "Trunk"
	local size = rng:range(4.4, 5.2) * s
	local cf = base * CFrame.new(0, h + size * 0.34, 0)
	local p = Style.ghost()
	Style.block(m, cf, Vector3.new(size, size * 0.8, size), Style.vary(shades[2], rng, 0.03), nil, p)
	Style.block(
		m,
		cf * CFrame.new(rng:range(-0.08, 0.08) * size, size * 0.5, rng:range(-0.08, 0.08) * size),
		Vector3.new(size * 0.66, size * 0.3, size * 0.66),
		Style.vary(shades[1], rng, 0.03),
		nil,
		p
	)
	-- two side lumps: a dark one low, a mid one higher on the other side
	local dirs = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	local first = rng:int(1, 4)
	local d1 = dirs[first]
	local d2 = dirs[(first + 1) % 4 + 1]
	if lean then
		-- lumps along the belt and toward `lean` only
		d1 = Vector3.new(0, 0, if rng:chance(0.5) then 1 else -1)
		d2 = lean
	end
	local k1 = size * rng:range(0.5, 0.58)
	Style.block(
		m,
		cf * CFrame.new(d1 * size * 0.48 + Vector3.new(0, -size * 0.14, 0)),
		Vector3.new(k1, k1 * 0.86, k1),
		Style.vary(shades[3], rng, 0.04),
		nil,
		p
	)
	local k2 = size * rng:range(0.44, 0.52)
	Style.block(
		m,
		cf * CFrame.new(d2 * size * 0.46 + Vector3.new(0, size * 0.12, 0)),
		Vector3.new(k2, k2 * 0.86, k2),
		Style.vary(shades[2], rng, 0.05),
		nil,
		p
	)
	return m
end

--[[
	Lean voxel tree for the scatter (~8 parts): trunk, root, a crown core
	with a light cap, three side lumps and a dark underside. Reads like
	Style.tree from a distance at a third of the cost.
]]
function Kit.leanTree(parent: Instance, base: CFrame, kind: string, rng: Rng.Rng, scale: number?): Model
	local s = scale or 1
	local m = Style.model("Tree", parent)
	local shades = Style.TreeKinds[kind] or Style.TreeKinds.Green
	local light, mid, dark = shades[1], shades[2], shades[3]
	local frame = base * CFrame.Angles(0, rng:int(0, 3) * math.pi / 2, 0)
	local h = rng:range(5.8, 7) * s
	local tw = 1.6 * s
	local trunk = Style.block(m, frame * CFrame.new(0, h / 2, 0), Vector3.new(tw, h, tw), Style.vary(C.Trunk, rng, 0.04))
	trunk.Name = "Trunk"
	Style.block(m, frame * CFrame.new(tw * 0.55, 0.35 * s, 0), Vector3.new(tw * 0.6, 0.7 * s, tw * 0.6), C.TrunkDark, nil, Style.tiny())
	local size = rng:range(7.4, 8.6) * s
	local cf = frame * CFrame.new(0, h + size * 0.22, 0)
	local p = Style.ghost()
	Style.block(m, cf, Vector3.new(size, size * 0.78, size), Style.vary(mid, rng, 0.03), nil, p)
	Style.block(
		m,
		cf * CFrame.new(rng:range(-0.1, 0.1) * size, size * 0.42, rng:range(-0.1, 0.1) * size),
		Vector3.new(size * 0.64, size * 0.32, size * 0.64),
		Style.vary(light, rng, 0.03),
		nil,
		p
	)
	local sides = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local start = rng:int(0, 3)
	for i = 1, 3 do
		local d = sides[(start + i) % 4 + 1]
		local k = size * rng:range(0.44, 0.56)
		local y = rng:range(-0.2, 0.2) * size
		local lateral = rng:range(-0.22, 0.22) * size
		local offset = Vector3.new(d[1] * size * 0.5 + d[2] * lateral, y, d[2] * size * 0.5 + d[1] * lateral)
		local color = if y < -0.05 * size then dark elseif i == 2 then light else mid
		Style.block(m, cf * CFrame.new(offset), Vector3.new(k, k * 0.9, k), Style.vary(color, rng, 0.04), nil, p)
	end
	Style.block(m, cf * CFrame.new(0, -size * 0.37, 0), Vector3.new(size * 0.84, size * 0.1, size * 0.84), dark, nil, Style.tiny())
	return m
end

---------------------------------------------------------------- water

--[[
	Stone-cube rim around a rounded rectangle (like Style.pond's rim) that
	skips every cube inside one of the `gaps` boxes ({ Min, Max } in world
	XZ), so a creek can run into the pond. Returns the rim cubes.
]]
export type Gap = { Min: Vector3, Max: Vector3 }

function Kit.rim(parent: Instance, center: Vector3, sizeX: number, sizeZ: number, rng: Rng.Rng, gaps: { Gap }, color: Color3?): { Part }
	local parts = {}
	-- (round 2: bigger stones, fewer of them)
	local steps = math.floor((sizeX + sizeZ) * 2 / 3.9)
	for i = 0, steps - 1 do
		local a = i / steps * 2 * math.pi
		local cx, sz = math.cos(a), math.sin(a)
		local rx = math.sign(cx) * math.abs(cx) ^ 0.5
		local rz = math.sign(sz) * math.abs(sz) ^ 0.5
		local p = center + Vector3.new(rx * sizeX / 2, 0, rz * sizeZ / 2)
		local skip = false
		for _, gap in gaps do
			if p.X >= gap.Min.X and p.X <= gap.Max.X and p.Z >= gap.Min.Z and p.Z <= gap.Max.Z then
				skip = true
			end
		end
		if not skip then
			local s = rng:range(2.6, 3.4)
			local h = rng:range(0.8, 1.3)
			local shade = if i % 4 == 0 then C.StoneLight elseif i % 4 == 2 then C.StoneDark else (color or C.Stone)
			table.insert(
				parts,
				Style.block(
					parent,
					CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, -a, 0),
					Vector3.new(s, h, s * 1.1),
					Style.vary(shade, rng, 0.05),
					nil,
					Style.solid()
				)
			)
		end
	end
	return parts
end

-- A clump of 2-3 cattails (dark green stalks with brown heads) standing in shallow water.
function Kit.cattails(parent: Instance, at: Vector3, rng: Rng.Rng, count: number?)
	for i = 1, count or 3 do
		local q = at + Vector3.new(rng:range(-0.8, 0.8), 0, rng:range(-0.8, 0.8))
		local h = rng:range(2.2, 3.2)
		local tilt = CFrame.Angles(rng:range(-0.12, 0.12), 0, rng:range(-0.12, 0.12))
		local foot = CFrame.new(q) * tilt
		Style.block(parent, foot * CFrame.new(0, h / 2, 0), Vector3.new(0.25, h, 0.25), C.LeafGreenDark, nil, Style.tiny())
		if i <= 2 then
			Style.block(parent, foot * CFrame.new(0, h - 0.3, 0), Vector3.new(0.45, 0.8, 0.45), C.Trunk, nil, Style.tiny())
		end
	end
end

-- Small crystal cluster without a light: a dark rock and 2 neon crystals
-- in a deep body color with barely lighter tips (pale tints bloom to
-- pastel or white).
Kit.CrystalTipLerp = 0.12
function Kit.smallCrystals(parent: Instance, base: CFrame, color: Color3, rng: Rng.Rng, size: number?)
	local s = size or 2.6
	local m = Style.model("Crystals", parent)
	Style.block(m, base * CFrame.new(0, s * 0.12, 0), Vector3.new(s * 0.6, s * 0.24, s * 0.5), C.StoneDeep, nil, Style.decor())
	Style.crystal(
		m,
		base * CFrame.new(0, s * 0.15, 0) * CFrame.Angles(rng:range(-0.1, 0.1), 0, 0.12),
		s,
		s * 0.3,
		color,
		nil,
		Kit.CrystalTipLerp
	)
	Style.crystal(
		m,
		base * CFrame.new(s * 0.22, s * 0.1, s * 0.05) * CFrame.Angles(0, 0, -0.45),
		s * 0.6,
		s * 0.22,
		color:Lerp(Color3.new(1, 1, 1), 0.08),
		nil,
		Kit.CrystalTipLerp
	)
end

---------------------------------------------------------------- small props

-- Lamp box on top of a post (bridge newels, boardwalk posts): neon cube + iron hat. 2 parts.
function Kit.lampBox(parent: Instance, top: CFrame, size: number?, light: boolean?): Part
	local s = size or 0.9
	local glow = Style.block(parent, top * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), C.LampAmber, NEON, Style.tiny())
	glow.Name = "LanternGlow"
	Style.block(parent, top * CFrame.new(0, s + 0.15, 0), Vector3.new(s * 1.35, 0.3, s * 1.35), C.Iron, nil, Style.tiny())
	if light then
		Style.light(glow, C.LampAmber, 16, 1.1)
	end
	return glow
end

-- Voxel pumpkin: an orange cube with a darker band and a stem. 2-3 parts.
function Kit.pumpkin(parent: Instance, at: Vector3, rng: Rng.Rng, size: number?)
	local s = size or rng:range(1.1, 1.6)
	local yaw = CFrame.Angles(0, rng:range(-0.4, 0.4), 0)
	local base = CFrame.new(at) * yaw
	Style.block(
		parent,
		base * CFrame.new(0, s * 0.4, 0),
		Vector3.new(s, s * 0.8, s),
		Style.vary(C.LeafOrange, rng, 0.05),
		nil,
		Style.decor()
	)
	Style.block(parent, base * CFrame.new(0, s * 0.85, 0), Vector3.new(0.25, 0.4, 0.25), C.LeafGreenDark, nil, Style.tiny())
	if s > 1.3 then
		Style.block(
			parent,
			base * CFrame.new(0, s * 0.4, 0),
			Vector3.new(s * 0.35, s * 0.82, s + 0.08),
			C.LeafOrangeDark,
			nil,
			Style.tiny()
		)
	end
end

--[[
	Flower patch that still reads from the hero camera: a low dark leaf
	cushion with 3-4 chunky flower cubes on and around it. 4-5 parts.
]]
function Kit.flowerPatch(parent: Instance, center: Vector3, color: Color3, rng: Rng.Rng, count: number?)
	local yaw = CFrame.Angles(0, rng:int(0, 3) * math.pi / 2, 0)
	local base = CFrame.new(center) * yaw
	local w, d = rng:range(1.8, 2.4), rng:range(1.5, 2.1)
	Style.block(parent, base * CFrame.new(0, 0.25, 0), Vector3.new(w, 0.5, d), Style.vary(C.LeafGreenDark, rng, 0.05), nil, Style.tiny())
	-- (round 3: half as many loose flower cubes)
	for i = 1, math.max(1, math.ceil((count or 3) / 2)) do
		local s = rng:range(0.6, 0.85)
		local on = i <= 2
		local q = if on
			then Vector3.new(rng:range(-w, w) * 0.3, 0.5 + s / 2, rng:range(-d, d) * 0.3)
			else Vector3.new(rng:range(-w, w) * 0.75, s / 2, rng:range(-d, d) * 0.75)
		Style.block(parent, base * CFrame.new(q), Vector3.new(s, s, s), Style.vary(color, rng, 0.05), nil, Style.tiny())
	end
end

-- Flower ring of single cubes around a point (hero tree feet).
function Kit.flowerRing(parent: Instance, center: Vector3, radius: number, colors: { Color3 }, rng: Rng.Rng, count: number)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:range(-0.2, 0.2)
		local r = radius + rng:range(-0.4, 0.4)
		local q = center + Vector3.new(math.cos(a) * r, 0.35, math.sin(a) * r)
		local s = rng:range(0.55, 0.75)
		Style.block(parent, CFrame.new(q), Vector3.new(s, s, s), Style.vary(colors[(i - 1) % #colors + 1], rng, 0.05), nil, Style.tiny())
	end
end

return Kit
