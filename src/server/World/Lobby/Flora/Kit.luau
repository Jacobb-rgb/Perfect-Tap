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
	local clear = math.max(r, reach or 0) + 0.5
	for _, box in placer.boxes do
		if Kit.boxDistance(box, p) < clear then
			return false
		end
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

--[[
	Hero tree: like Style.tree but the second crown is a lean lump cluster,
	so a big tree costs ~20 parts instead of ~25. `scale` 1.2-1.6.
	`sideX` (+1 / -1, optional) puts the side crown toward world +X / -X.
]]
function Kit.bigTree(parent: Instance, base: CFrame, kind: string, rng: Rng.Rng, scale: number, sideX: number?): Model
	local s = scale
	local m = Style.model("Tree", parent)
	local shades = Style.TreeKinds[kind] or Style.TreeKinds.Green
	local turns = rng:int(0, 3)
	local frame = base * CFrame.Angles(0, if sideX then 0 else turns * math.pi / 2, 0)
	local h = rng:range(6, 6.8) * s
	local tw = 1.7 * s
	local trunk = Style.block(m, frame * CFrame.new(0, h / 2, 0), Vector3.new(tw, h, tw), Style.vary(C.Trunk, rng, 0.04))
	trunk.Name = "Trunk"
	Style.block(m, frame * CFrame.new(tw * 0.55, 0.4 * s, 0), Vector3.new(tw * 0.6, 0.8 * s, tw * 0.6), C.TrunkDark, nil, Style.tiny())
	Style.block(m, frame * CFrame.new(-tw * 0.7, h * 0.62, 0), Vector3.new(tw * 0.9, tw * 0.5, tw * 0.5), C.Trunk, nil, Style.tiny())
	local size = rng:range(7.6, 8.4) * s
	Style.canopy(m, frame * CFrame.new(0, h + size * 0.22, 0), size, shades, rng)
	-- side crown: core, cap and two lumps
	local side = if rng:chance(0.5) then 1 else -1
	if sideX then
		side = if sideX > 0 then 1 else -1
	end
	local at = frame * CFrame.new(side * size * 0.58, h + size * 0.04, size * 0.18)
	local k = size * 0.5
	local p = Style.ghost()
	Style.block(m, at, Vector3.new(k, k * 0.8, k), Style.vary(shades[2], rng, 0.03), nil, p)
	Style.block(m, at * CFrame.new(0, k * 0.45, 0), Vector3.new(k * 0.66, k * 0.3, k * 0.66), Style.vary(shades[1], rng, 0.03), nil, p)
	Style.block(
		m,
		at * CFrame.new(side * k * 0.45, -k * 0.1, -k * 0.2),
		Vector3.new(k * 0.55, k * 0.5, k * 0.55),
		Style.vary(shades[3], rng, 0.04),
		nil,
		p
	)
	Style.block(
		m,
		at * CFrame.new(0, -k * 0.05, k * 0.45),
		Vector3.new(k * 0.5, k * 0.45, k * 0.5),
		Style.vary(shades[1], rng, 0.04),
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
	local steps = math.floor((sizeX + sizeZ) * 2 / 3.1)
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
			local s = rng:range(2.1, 2.9)
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

-- Small crystal cluster without a light: a dark rock and 2 neon crystals.
function Kit.smallCrystals(parent: Instance, base: CFrame, color: Color3, rng: Rng.Rng, size: number?)
	local s = size or 2.6
	local m = Style.model("Crystals", parent)
	Style.block(m, base * CFrame.new(0, s * 0.12, 0), Vector3.new(s * 0.6, s * 0.24, s * 0.5), C.StoneDeep, nil, Style.decor())
	Style.crystal(m, base * CFrame.new(0, s * 0.15, 0) * CFrame.Angles(rng:range(-0.1, 0.1), 0, 0.12), s, s * 0.3, color)
	Style.crystal(
		m,
		base * CFrame.new(s * 0.22, s * 0.1, s * 0.05) * CFrame.Angles(0, 0, -0.45),
		s * 0.6,
		s * 0.22,
		color:Lerp(Color3.new(1, 1, 1), 0.25)
	)
end

---------------------------------------------------------------- small props

-- Lamp box on top of a post (bridge newels, boardwalk posts): neon cube + iron hat. 2 parts.
function Kit.lampBox(parent: Instance, top: CFrame, size: number?, light: boolean?): Part
	local s = size or 0.9
	local glow = Style.block(parent, top * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), C.Lamp, NEON, Style.tiny())
	glow.Name = "LanternGlow"
	Style.block(parent, top * CFrame.new(0, s + 0.15, 0), Vector3.new(s * 1.35, 0.3, s * 1.35), C.Iron, nil, Style.tiny())
	if light then
		Style.light(glow, C.Lamp, 16, 1.3)
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
	for i = 1, count or 3 do
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
