--[[
	Plaza paving (LOBBY_PLAN 6.3.1 + 6.3.3, restyled after concept v2,
	docs/art/lobby_concept_v2.webp): a round plaza of dark polished slate
	with concentric neon rings, and the spawn pad dressed as a slate slab
	with a quiet ring of blue dashes and a bold double chevron to the forge.

	One collidable dark disc (r 36, top y 0.4) is the floor; on it lie four
	rings of dark wet blue-grey slate tiles (SmoothPlastic, all with the
	same little Reflectance: one polished floor, a few lighter accent slabs)
	whose thin 0.14 gaps show the dark disc as seams. The wider gaps between
	the tile rings carry bold flat neon rings (concept v2): a continuous
	deep-orange ring round the crystal's housing (r 14.2), a second
	continuous orange ring (r 24.6) and the blue outer ring of long dashes
	(r 30.6), a deep saturated blue that stays blue under bloom. The rings
	and tiles run on through the spawn area (only what TownSpawn would hide
	is left out). A low dark metal curb (walk-through, at most 0.55 above
	the floor) with a deep-blue neon top edge and orange glowing slots runs
	at r 35.6 and opens wherever a road or path enters and in front of the
	forge. Everything on the floor stays flat and below TownSpawn's top
	(0.45) except the spawn pad cover (<= 0.5, non-colliding).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local K = Common.Colors
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local TAU = 2 * math.pi

local Paving = {}

-- Slate tile rings: inner/outer radius, tiles per ring, phase (fraction of a tile).
-- (rings 1 and 2 only meet at a seam; the gaps after rings 2 and 3 carry neon rings)
local RINGS = {
	{ R0 = 14.8, R1 = 19.0, Count = 20, Phase = 0 },
	{ R0 = 19.0, R1 = 23.9, Count = 26, Phase = 0.5 },
	{ R0 = 25.35, R1 = 29.45, Count = 30, Phase = 0.25 },
	{ R0 = 31.1, R1 = 35, Count = 34, Phase = 0.6 },
}
-- Neon rings in the gaps: radius (polygon corners), width, segments, drawn
-- fraction (> 1: the chords overlap, a continuous ring), color. Bold and
-- wide (concept v2), the blue one in long dashes: they read as neon rings,
-- not as lane markings.
Paving.NeonRings = {
	{ Name = "InnerRing", R = 14.35, Width = 1.0, Segments = 24, Dash = 1.04, Color = K.RingOrange },
	{ Name = "OrangeRing", R = 24.62, Width = 1.3, Segments = 30, Dash = 1.04, Color = K.RingOrange },
	{ Name = "OuterRing", R = 30.62, Width = 1.0, Segments = 16, Dash = 0.92, Color = K.NeonBlueDeep },
}
Paving.CrystalFloorRadius = 13.65
local TILE_H = 0.08
local RING_Y = 0.405 -- neon ring centers (0.06 thick: tops at 0.435, flush with the tiles)
local PAD_HALF = 4 -- TownSpawn is 8 x 8 (top 0.45)

-- Is this floor point under the TownSpawn pad (hidden by it)?
local function underPad(p: Vector3, spawn: Vector3, margin: number): boolean
	return math.abs(p.X - spawn.X) < PAD_HALF + margin and math.abs(p.Z - spawn.Z) < PAD_HALF + margin
end

local function tile(m: Instance, cf: CFrame, size: Vector3, rng: Rng.Rng, color: Color3?)
	Common.polish(Style.block(m, cf, size, color or Common.slate(rng), nil, Style.tiny()))
end

local function slateTiles(m: Model, center: Vector3, spawn: Vector3, rng: Rng.Rng)
	for ringIndex, ring in RINGS do
		local outerRing = ringIndex == #RINGS
		for i = 0, ring.Count - 1 do
			local a = (i + ring.Phase) / ring.Count * TAU
			-- the outer ring reaches the plaza edge where the curb is open
			local r1 = ring.R1
			if outerRing and Common.isEntrance(a, 1.5) then
				r1 = Common.PlazaRadius - 0.1
			end
			local rc = (ring.R0 + r1) / 2
			local depth = r1 - ring.R0 - Common.Seam
			local arc = TAU * rc / ring.Count
			local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * rc
			if not underPad(p, spawn, -0.8) then
				local frame = CFrame.new(p.X, Common.TileTop - TILE_H / 2, p.Z) * CFrame.Angles(0, -a, 0)
				-- now and then a slab is cut in two (more seams, less repetition)
				if rng:chance(0.1) then
					local k = rng:range(0.35, 0.65)
					local l1 = arc * k - Common.Seam
					local l2 = arc * (1 - k) - Common.Seam
					local z1 = -arc / 2 + arc * k / 2
					local z2 = arc / 2 - arc * (1 - k) / 2
					tile(m, frame * CFrame.new(0, 0, z1), Vector3.new(depth, TILE_H, l1), rng, Common.courseSlate(ringIndex, i, rng))
					tile(m, frame * CFrame.new(0, 0, z2), Vector3.new(depth, TILE_H, l2), rng, Common.courseSlate(ringIndex, i + 1, rng))
				else
					tile(m, frame, Vector3.new(depth, TILE_H, arc - Common.Seam), rng, Common.courseSlate(ringIndex, i, rng))
				end
			end
		end
	end
end

-- The concentric neon rings (flat, in the gaps between the tile rings).
local function neonRings(m: Model, center: Vector3, spawn: Vector3)
	for _, spec in Paving.NeonRings do
		local parts = Common.ring(m, center, spec.R, spec.Width, RING_Y, 0.06, spec.Segments, spec.Color, {
			Dash = spec.Dash,
			Skip = function(p: Vector3): boolean
				return underPad(p, spawn, 0)
			end,
		})
		for _, part in parts do
			part.Name = spec.Name
		end
	end
end

Paving.CurbBlocks = 50
Paving.CurbDepth = 1.2

-- Ground corners and edge midpoints of curb block i (y = 0).
function Paving.curbBlockPoints(center: Vector3, i: number): { Vector3 }
	local step = TAU / Paving.CurbBlocks
	local arc = TAU * Common.CurbRadius / Paving.CurbBlocks
	local frame = CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, -(i + 0.5) * step, 0) * CFrame.new(Common.CurbRadius, 0, 0)
	local out = {}
	for _, x in { -Paving.CurbDepth / 2, 0, Paving.CurbDepth / 2 } do
		for _, z in { -arc / 2, 0, arc / 2 } do
			table.insert(out, (frame * CFrame.new(x, 0, z)).Position)
		end
	end
	return out
end

-- Does curb block i stand on another package's footprint (a stall straddling the rim)?
local function onFootprint(center: Vector3, i: number): boolean
	for _, p in Paving.curbBlockPoints(center, i) do
		for _, piece in LobbyLayout.Pieces do
			if
				piece.Package ~= "Plaza"
				and not piece.Walkable
				and LobbyLayout.isGroundPiece(piece)
				and LobbyLayout.distanceTo(piece, p) < 0.1
			then
				return true
			end
		end
	end
	return false
end

-- Walk-through dark metal curb on the plaza rim, open at every entrance:
-- a blue neon strip along its outer top edge, and every third block a
-- slightly taller post with an orange glowing slot facing the plaza (a
-- post that would stand on a stall's footprint, like the GuildBoard's
-- behind the board, moves to the next clear block). Low (0.4 / 0.55 over
-- the plaza floor), so legs barely clip through it.
local function curb(m: Model, center: Vector3, rng: Rng.Rng)
	local count = Paving.CurbBlocks
	local step = TAU / count
	local arc = TAU * Common.CurbRadius / count
	local function open(i: number): boolean
		local a = (i + 0.5) * step
		return not (Common.isEntrance(a) or Common.isEntrance(a - step * 0.5) or Common.isEntrance(a + step * 0.5))
	end
	local posts: { [number]: boolean } = {}
	for i = 0, count - 1, 3 do
		if open(i) then
			for _, j in { i, i + 1, i - 1 } do
				local k = j % count
				if open(k) and not onFootprint(center, k) then
					posts[k] = true
					break
				end
			end
		end
	end
	for i = 0, count - 1 do
		local a = (i + 0.5) * step
		if open(i) then
			local post = posts[i] == true
			local h = if post then 0.95 else 0.8
			local frame = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(Common.CurbRadius, h / 2, 0)
			local block = Style.block(
				m,
				frame,
				Vector3.new(Paving.CurbDepth, h, arc + 0.05),
				Style.vary(if post then K.MetalDark else K.Metal, rng, 0.04),
				nil,
				Style.ghost()
			)
			if post then
				block.Name = "CurbPost"
			end
			local edge = Style.block(
				m,
				frame * CFrame.new(0.46, h / 2 - 0.05, 0),
				Vector3.new(0.32, 0.14, arc + 0.06),
				K.NeonBlueDeep,
				NEON,
				Style.tiny()
			)
			edge.Name = "CurbGlow"
			if post then
				local slot = Style.block(
					m,
					frame * CFrame.new(-0.62, h / 2 - 0.2, 0),
					Vector3.new(0.1, 0.2, arc * 0.5),
					K.SlotAmber,
					NEON,
					Style.tiny()
				)
				slot.Name = "CurbSlot"
			end
		end
	end
end

--[[
	The spawn pad (Town.luau builds TownSpawn, 8 x 8, top 0.45, a light
	flagstone color) dressed to match the plaza: a dark seam plate on it,
	one big slate slab with a quiet ring of short deep-blue dashes (it does
	not compete with the crystal), and north of it the concept's bold
	double chevron pointing to the Great Forge. All flat (<= 0.5), no
	collision; the plaza tiles and rings run on around it.
]]
local function spawnInlay(m: Model, spawn: Vector3, rng: Rng.Rng)
	local c = Vector3.new(spawn.X, 0, spawn.Z)
	local plate = Style.block(m, CFrame.new(c + Vector3.new(0, 0.46, 0)), Vector3.new(8.3, 0.02, 8.3), K.SlateDark, nil, Style.tiny())
	plate.Name = "SpawnInlay"
	local tile = Style.block(m, CFrame.new(c + Vector3.new(0, 0.4825, 0)), Vector3.new(7.9, 0.025, 7.9), K.Slate, nil, Style.tiny())
	tile.Reflectance = Common.TileReflectance
	-- six quiet arcs (not a dashed lane marking round the spawn)
	for _, part in Common.ring(m, c, 3.1, 0.07, 0.488, 0.02, 6, K.NeonBlueDeep, { Phase = 0.5, Dash = 0.5 }) do
		part.Name = "SpawnRing"
	end
	-- the double chevron toward the forge (north, -Z), on the plaza tiles
	local tip = c + Vector3.new(0, 0.44, -8.6)
	for _, part in Common.doubleChevron(m, CFrame.lookAt(tip, tip + Vector3.new(0, 0, -1)), 3.4, 0.8, 1.6, K.Chevron) do
		part.Name = "SpawnChevron"
	end
end

-- Slate walk between the plaza rim and the forge stairs, with orange neon
-- edge strips that lead the eye up the steps.
local function forgeApron(m: Model, rng: Rng.Rng)
	local forge = LobbyLayout.get("GreatForge")
	local front = forge.Center.Z + forge.Size.Z / 2 -- z of the forge front (-38)
	local half = Common.ForgeApproach + 0.5
	local r = Common.PlazaRadius - 0.1
	local z0 = -math.sqrt(r * r - half * half) + 0.6
	Style.block(
		m,
		CFrame.new(0, 0.24, (z0 + front) / 2),
		Vector3.new(half * 2, 0.3, z0 - front),
		K.SlateDark,
		nil,
		Style.tiny({ CanQuery = true })
	)
	local cols = 4
	local w = half * 2 / cols
	for i = 0, cols - 1 do
		local x0 = -half + i * w
		local x1 = x0 + w
		local nearX = math.min(math.abs(x0), math.abs(x1))
		if x0 < 0 and x1 > 0 then
			nearX = 0
		end
		local zTop = -math.sqrt(r * r - nearX * nearX) - 0.15
		local zBottom = front + 0.15
		if zTop - zBottom > 0.6 then
			tile(
				m,
				CFrame.new((x0 + x1) / 2, Common.TileTop - TILE_H / 2, (zTop + zBottom) / 2),
				Vector3.new(w - Common.Seam, TILE_H, zTop - zBottom),
				rng
			)
		end
	end
	for _, s in { -1, 1 } do
		local x = s * (half - 0.45)
		local zTop = -math.sqrt(r * r - x * x)
		local len = zTop - front
		if len > 0.8 then
			Style.block(m, CFrame.new(x, 0.42, (zTop + front) / 2), Vector3.new(0.65, 0.08, len), K.MetalDark, nil, Style.tiny())
			Style.block(m, CFrame.new(x, 0.45, (zTop + front) / 2), Vector3.new(0.2, 0.06, len - 0.2), K.NeonOrange, NEON, Style.tiny())
		end
	end
end

--[[
	Slate aprons from the plaza rim to the stall facades (concept v2: the
	polished paving runs up to every module, no lawn wedges in front of
	SHOP, UPGRADES, CAPSULES and the HALL OF FAME): one slab per facade from
	its front face toward the plaza, long enough that a front corner reaches
	under the plaza disc (at most 16), a little below the walkways (they
	run on top of it), with a thin deep-blue neon curb along its sides and
	its far end where the paving meets the grass. 4 parts each.
]]
Paving.ApronTop = 0.24
Paving.Aprons = { "Shop", "Upgrades", "CapsuleStall", "HallOfFame" }
local function apronLength(front: Vector3, look: Vector3, right: Vector3, halfW: number): number
	local best = 16
	for _, side in { -1, 1 } do
		local corner = front + right * side * halfW
		-- smallest L with |corner + look L| <= r
		local r = Common.PlazaRadius - 0.8
		local b = corner:Dot(look)
		local disc = b * b - (corner:Dot(corner) - r * r)
		if disc >= 0 then
			local l = -b - math.sqrt(disc)
			if l > 0 then
				best = math.min(best, l + 1)
			end
		end
	end
	return best
end

local function facadeAprons(m: Model, rng: Rng.Rng)
	for _, id in Paving.Aprons do
		local piece = LobbyLayout.get(id)
		local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
		local right = Vector3.new(-look.Z, 0, look.X)
		local front = Vector3.new(piece.Center.X, 0, piece.Center.Z) + look * (piece.Size.Z / 2)
		local halfW = piece.Size.X / 2
		local length = apronLength(front, look, right, halfW)
		local mid = front + look * (length / 2)
		local frame = CFrame.fromMatrix(Vector3.new(mid.X, Paving.ApronTop - 0.1, mid.Z), right, Vector3.new(0, 1, 0), -look)
		local slab = Style.block(m, frame, Vector3.new(halfW * 2, 0.2, length), Style.vary(K.Slate, rng, 0.02), nil, Style.tiny())
		slab.Name = "Apron"
		Common.polish(slab)
		-- the neon curb where the paving meets the grass: both sides and the far end
		for _, side in { -1, 1 } do
			local edge = Style.block(
				m,
				frame * CFrame.new(side * (halfW - 0.1), 0.12, 0),
				Vector3.new(0.18, 0.06, length - 0.1),
				K.NeonBlueDeep,
				NEON,
				Style.tiny()
			)
			edge.Name = "ApronCurb"
		end
		local tip = Style.block(
			m,
			frame * CFrame.new(0, 0.12, -length / 2 + 0.1),
			Vector3.new(halfW * 2 - 0.2, 0.06, 0.18),
			K.NeonBlueDeep,
			NEON,
			Style.tiny()
		)
		tip.Name = "ApronCurb"
	end
end

--[[
	Dark metal planter boxes round the plaza rim between the entrances
	(concept v2's planters): a dark box with a blue neon lip and two or
	three voxel bush blocks on it. Out of the walking ring (r 33.6),
	clear of every road, path and stall. 5 parts each.
]]
Paving.PlanterRadius = 33.6
Paving.PlanterAngles = { 48, 68, 118, 145, 165, 300 }
local function planterBox(m: Model, base: CFrame, rng: Rng.Rng, length: number)
	local box = Style.block(m, base * CFrame.new(0, 0.7, 0), Vector3.new(1.5, 1.4, length), K.MetalDark, nil, Style.solid())
	box.Name = "Planter"
	Style.block(m, base * CFrame.new(0, 1.42, 0), Vector3.new(1.62, 0.1, length + 0.12), K.NeonBlueDeep, NEON, Style.tiny()).Name =
		"PlanterLip"
	local shades = { C.LeafGreen, C.LeafGreenDark, C.LeafGreenLight }
	for i = 1, 3 do
		local k = rng:range(0.9, 1.3)
		local z = (i - 2) * length * 0.3 + rng:range(-0.15, 0.15)
		Style.block(
			m,
			base * CFrame.new(rng:range(-0.1, 0.1), 1.4 + k * 0.4, z),
			Vector3.new(k, k * 0.8, k),
			Style.vary(shades[i], rng, 0.05),
			nil,
			Style.tiny()
		)
	end
end

local function planters(m: Model, rng: Rng.Rng)
	for _, deg in Paving.PlanterAngles do
		local a = math.rad(deg)
		local p = Vector3.new(math.cos(a), 0, math.sin(a)) * Paving.PlanterRadius
		if not Common.isEntrance(a, 3) and Common.isClear(p, 1.6) and Common.offStrips(p, 1.6) then
			planterBox(m, CFrame.new(p) * CFrame.Angles(0, -a, 0), rng, 2.8)
		end
	end
end

-- Two gold ore carts on the lawn beside the SHOP's and the UPGRADES' far
-- ends (concept v2's mine carts), off the showcases and the paths.
local function oreCarts(m: Model, rng: Rng.Rng)
	for _, id in { "Shop", "Upgrades" } do
		local piece = LobbyLayout.get(id)
		local look = Vector3.new(piece.Facing.X, 0, piece.Facing.Z).Unit
		local right = Vector3.new(-look.Z, 0, look.X)
		-- the module's north end (Shop: local -X, Upgrades: local +X)
		local side = if id == "Shop" then -1 else 1
		local p = Vector3.new(piece.Center.X, 0, piece.Center.Z) + right * side * (piece.Size.X / 2 + 2.6) + look * 4
		local cart = Style.mineCart(m, CFrame.lookAt(p, p + right) * CFrame.Angles(0, 0.35 * side, 0), rng, { Load = "Gold" })
		cart.Name = "OreCart"
	end
end

function Paving.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("Plaza")
	local center = piece.Center
	local spawn = LobbyLayout.get("SpawnPad").Center
	local m = Style.model("Paving", parent)
	local floor = Geo.cylinder(
		m,
		center + Vector3.new(0, Common.FloorTop - 0.3, 0),
		0.6,
		Common.PlazaRadius * 2,
		K.SlateDark,
		SMOOTH,
		Style.solid({ CastShadow = false })
	)
	floor.Name = "PlazaFloor"
	-- the polished dark disc under the crystal's housing
	local inner = Geo.cylinder(
		m,
		center + Vector3.new(0, Common.TileTop - 0.04, 0),
		0.08,
		Paving.CrystalFloorRadius * 2,
		K.SlateDark,
		SMOOTH,
		Style.tiny()
	)
	inner.Name = "CrystalFloor"
	Common.polish(inner)
	slateTiles(m, center, spawn, rng)
	neonRings(Style.model("NeonRings", m), center, spawn)
	curb(Style.model("Curb", m), center, rng)
	spawnInlay(Style.model("SpawnInlay", parent), spawn, rng)
	forgeApron(Style.model("ForgeApron", m), rng)
	facadeAprons(Style.model("Aprons", m), rng)
	planters(Style.model("Planters", parent), rng)
	oreCarts(Style.model("OreCarts", parent), rng)
end

return Paving
