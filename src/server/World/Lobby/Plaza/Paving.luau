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

local K = Common.Colors
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local TAU = 2 * math.pi

local Paving = {}

-- Slate tile rings: inner/outer radius, tiles per ring, phase (fraction of a tile).
-- (rings 1 and 2 only meet at a seam; the gaps after rings 2 and 3 carry neon rings)
local RINGS = {
	{ R0 = 14.62, R1 = 19.0, Count = 20, Phase = 0 },
	{ R0 = 19.0, R1 = 24.12, Count = 26, Phase = 0.5 },
	{ R0 = 24.98, R1 = 30.14, Count = 30, Phase = 0.25 },
	{ R0 = 30.98, R1 = 35, Count = 34, Phase = 0.6 },
}
-- Neon rings in the gaps: radius (polygon corners), width, segments, drawn
-- fraction (> 1: the chords overlap, a continuous ring), color.
Paving.NeonRings = {
	{ Name = "InnerRing", R = 14.2, Width = 0.6, Segments = 24, Dash = 1.04, Color = K.RingOrange },
	{ Name = "OrangeRing", R = 24.62, Width = 0.65, Segments = 30, Dash = 1.04, Color = K.RingOrange },
	{ Name = "OuterRing", R = 30.62, Width = 0.5, Segments = 32, Dash = 0.8, Color = K.NeonBlueDeep },
}
Paving.CrystalFloorRadius = 13.8
local TILE_H = 0.08
local RING_Y = 0.405 -- neon ring centers (0.06 thick: tops at 0.435, flush with the tiles)
local PAD_HALF = 4 -- TownSpawn is 8 x 8 (top 0.45)

-- Is this floor point under the TownSpawn pad (hidden by it)?
local function underPad(p: Vector3, spawn: Vector3, margin: number): boolean
	return math.abs(p.X - spawn.X) < PAD_HALF + margin and math.abs(p.Z - spawn.Z) < PAD_HALF + margin
end

local function tile(m: Instance, cf: CFrame, size: Vector3, rng: Rng.Rng)
	Common.polish(Style.block(m, cf, size, Common.slate(rng), nil, Style.tiny()))
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
					tile(m, frame * CFrame.new(0, 0, z1), Vector3.new(depth, TILE_H, l1), rng)
					tile(m, frame * CFrame.new(0, 0, z2), Vector3.new(depth, TILE_H, l2), rng)
				else
					tile(m, frame, Vector3.new(depth, TILE_H, arc - Common.Seam), rng)
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

-- Walk-through dark metal curb on the plaza rim, open at every entrance:
-- a blue neon strip along its outer top edge, and every third block a
-- slightly taller post with an orange glowing slot facing the plaza. Low
-- (0.4 / 0.55 over the plaza floor), so legs barely clip through it.
local function curb(m: Model, center: Vector3, rng: Rng.Rng)
	local count = 50
	local step = TAU / count
	local arc = TAU * Common.CurbRadius / count
	for i = 0, count - 1 do
		local a = (i + 0.5) * step
		if not (Common.isEntrance(a) or Common.isEntrance(a - step * 0.5) or Common.isEntrance(a + step * 0.5)) then
			local post = i % 3 == 0
			local h = if post then 0.95 else 0.8
			local frame = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(Common.CurbRadius, h / 2, 0)
			Style.block(
				m,
				frame,
				Vector3.new(1.2, h, arc + 0.05),
				Style.vary(if post then K.MetalDark else K.Metal, rng, 0.04),
				nil,
				Style.ghost()
			)
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
				Style.block(m, frame * CFrame.new(-0.62, h / 2 - 0.2, 0), Vector3.new(0.1, 0.2, arc * 0.5), K.SlotAmber, NEON, Style.tiny())
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
	for _, part in Common.ring(m, c, 3.1, 0.14, 0.488, 0.02, 12, K.NeonBlueDeep, { Phase = 0.5, Dash = 0.45 }) do
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
			Style.block(m, CFrame.new(x, 0.42, (zTop + front) / 2), Vector3.new(0.9, 0.08, len), K.MetalDark, nil, Style.tiny())
			Style.block(m, CFrame.new(x, 0.45, (zTop + front) / 2), Vector3.new(0.28, 0.06, len - 0.2), K.NeonOrange, NEON, Style.tiny())
		end
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
end

return Paving
