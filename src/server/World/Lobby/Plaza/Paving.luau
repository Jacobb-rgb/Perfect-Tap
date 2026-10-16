--[[
	Plaza paving (LOBBY_PLAN 6.3.1 + 6.3.3, restyled after concept v2,
	docs/art/lobby_concept_v2.webp): a round plaza of dark polished slate
	with concentric neon rings, and the spawn's launch-pad inlay.

	One collidable dark disc (r 36, top y 0.4) is the floor; on it lie four
	rings of polished slate tiles (SmoothPlastic + a little Reflectance)
	whose 0.32 gaps show the dark disc as seams. The wider gaps between the
	tile rings carry flat neon rings: an orange ring round the crystal's
	housing (r 14.2), a dashed blue ring (r 18.5), thin orange dashes
	(r 24.55) and the wide blue outer ring (r 30.6). A low dark metal curb
	(walk-through) with a blue neon top edge and orange glowing slots runs
	at r 35.6 and opens wherever a road or path enters and in front of the
	forge. Everything on the floor stays flat and below TownSpawn's top
	(0.45) except the spawn pad plate (<= 0.49, non-colliding).
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
local RINGS = {
	{ R0 = 14.6, R1 = 18.2, Count = 20, Phase = 0 },
	{ R0 = 18.8, R1 = 24.3, Count = 26, Phase = 0.5 },
	{ R0 = 24.8, R1 = 30, Count = 30, Phase = 0.25 },
	{ R0 = 31.2, R1 = 35, Count = 34, Phase = 0.6 },
}
-- Neon rings in the gaps: radius, width, segments, drawn fraction, color.
Paving.NeonRings = {
	{ Name = "InnerRing", R = 14.2, Width = 0.42, Segments = 30, Dash = 1.02, Color = K.NeonOrange },
	{ Name = "BlueDashRing", R = 18.5, Width = 0.26, Segments = 32, Dash = 0.72, Color = K.NeonBlue },
	{ Name = "OrangeDashRing", R = 24.55, Width = 0.18, Segments = 26, Dash = 0.4, Color = K.NeonOrange },
	{ Name = "OuterRing", R = 30.6, Width = 0.46, Segments = 40, Dash = 1.02, Color = K.NeonBlue },
}
Paving.CrystalFloorRadius = 13.8
local TILE_H = 0.08
local RING_Y = 0.405 -- neon ring centers (0.06 thick: tops at 0.435, flush with the tiles)
local INLAY_R = 9.2

local function inInlay(p: Vector3, spawn: Vector3, margin: number): boolean
	return (Vector3.new(p.X, 0, p.Z) - Vector3.new(spawn.X, 0, spawn.Z)).Magnitude < INLAY_R + margin
end

local function tile(m: Instance, cf: CFrame, size: Vector3, rng: Rng.Rng)
	Common.polish(Style.block(m, cf, size, Common.slate(rng), nil, Style.tiny()), rng)
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
			local depth = r1 - ring.R0 - 0.32
			local arc = TAU * rc / ring.Count
			local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * rc
			if not inInlay(p, spawn, -0.5) then
				local frame = CFrame.new(p.X, Common.TileTop - TILE_H / 2, p.Z) * CFrame.Angles(0, -a, 0)
				-- now and then a slab is cut in two (more seams, less repetition)
				if rng:chance(0.1) then
					local k = rng:range(0.35, 0.65)
					local l1 = arc * k - 0.32
					local l2 = arc * (1 - k) - 0.32
					local z1 = -arc / 2 + arc * k / 2
					local z2 = arc / 2 - arc * (1 - k) / 2
					tile(m, frame * CFrame.new(0, 0, z1), Vector3.new(depth, TILE_H, l1), rng)
					tile(m, frame * CFrame.new(0, 0, z2), Vector3.new(depth, TILE_H, l2), rng)
				else
					tile(m, frame, Vector3.new(depth, TILE_H, arc - 0.32), rng)
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
				return inInlay(p, spawn, 0.6)
			end,
		})
		for _, part in parts do
			part.Name = spec.Name
		end
	end
end

-- Walk-through dark metal curb on the plaza rim, open at every entrance:
-- a blue neon strip along its outer top edge, and every third block a
-- taller post with an orange glowing slot facing the plaza.
local function curb(m: Model, center: Vector3, rng: Rng.Rng)
	local count = 50
	local step = TAU / count
	local arc = TAU * Common.CurbRadius / count
	for i = 0, count - 1 do
		local a = (i + 0.5) * step
		if not (Common.isEntrance(a) or Common.isEntrance(a - step * 0.5) or Common.isEntrance(a + step * 0.5)) then
			local post = i % 3 == 0
			local h = if post then 1.2 else 0.85
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
				K.NeonBlue,
				NEON,
				Style.tiny()
			)
			edge.Name = "CurbGlow"
			if post then
				Style.block(m, frame * CFrame.new(-0.62, 0.08, 0), Vector3.new(0.1, 0.36, arc * 0.5), K.NeonOrange, NEON, Style.tiny())
			end
		end
	end
end

--[[
	Launch pad around TownSpawn (Town.luau builds the 8x8 pad at the
	center, top 0.45): a polished dark slate disc, a blue neon octagon at
	its rim, a dark metal plate with a blue neon frame laid flush on the
	spawn pad, orange ticks E/S/W and a glowing double chevron pointing
	north to the Great Forge. All flat (<= 0.49), no collision.
]]
local function spawnInlay(m: Model, spawn: Vector3)
	local c = Vector3.new(spawn.X, 0, spawn.Z)
	local disc = Geo.cylinder(m, c + Vector3.new(0, 0.405, 0), 0.08, INLAY_R * 2, K.SlateDark, SMOOTH, Style.tiny())
	disc.Name = "SpawnInlay"
	Common.polish(disc)
	Common.ring(m, c, INLAY_R - 0.45, 0.26, 0.44, 0.06, 8, K.NeonBlue, { Phase = 0.5 })
	-- the plate over the spawn pad and its neon frame
	Style.block(m, CFrame.new(c + Vector3.new(0, 0.465, 0)), Vector3.new(8.2, 0.03, 8.2), K.Metal, nil, Style.tiny())
	for _, s in { -1, 1 } do
		Style.block(m, CFrame.new(c + Vector3.new(0, 0.475, s * 3.9)), Vector3.new(8, 0.03, 0.2), K.NeonBlue, NEON, Style.tiny())
		Style.block(m, CFrame.new(c + Vector3.new(s * 3.9, 0.475, 0)), Vector3.new(0.2, 0.03, 7.6), K.NeonBlue, NEON, Style.tiny())
	end
	-- orange ticks east, south and west
	for _, deg in { 0, 90, 180 } do
		local a = math.rad(deg)
		local frame = CFrame.new(c) * CFrame.Angles(0, -a, 0) * CFrame.new(6.9, 0.44, 0)
		Style.block(m, frame, Vector3.new(1.6, 0.06, 0.42), K.NeonOrange, NEON, Style.tiny())
	end
	-- double chevron toward the forge (north, -Z)
	for _, d in { 8, 6.6 } do
		local tip = c + Vector3.new(0, 0.44, -d)
		Common.chevron(m, CFrame.lookAt(tip, tip + Vector3.new(0, 0, -1)), 2.3, 0.5, K.NeonOrange)
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
		K.SlateDeep,
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
				Vector3.new(w - 0.32, TILE_H, zTop - zBottom),
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

-- Gold carts and crates at the plaza rim (as in the concept), off the spawn view's corners.
local function rimProps(m: Model, center: Vector3, rng: Rng.Rng)
	local props = Style.model("RimProps", m)
	for _, deg in { 36, 144 } do
		local a = math.rad(deg)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * 33.4
		-- carts roll along the rim (tangent)
		local base = CFrame.lookAt(
			Vector3.new(p.X, Common.TileTop, p.Z),
			Vector3.new(p.X, Common.TileTop, p.Z) + Vector3.new(-math.sin(a), 0, math.cos(a))
		)
		Style.mineCart(props, base, rng, { Load = "Gold" })
	end
	for _, deg in { 45, 135 } do
		local a = math.rad(deg)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * 33.6
		Style.crate(props, CFrame.new(p.X, Common.TileTop, p.Z), rng, 2.4)
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
		K.SlateDeep,
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
	spawnInlay(Style.model("SpawnInlay", parent), spawn)
	forgeApron(Style.model("ForgeApron", m), rng)
	rimProps(m, center, rng)
end

return Paving
