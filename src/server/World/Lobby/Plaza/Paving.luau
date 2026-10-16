--[[
	Plaza paving (LOBBY_PLAN 6.3.1 + 6.3.3): the round flagstone plaza and
	the spawn's compass-rose inlay.

	One collidable FlagDark disc (r 36, top y 0.4) is the floor; on it lie
	rings of flagstones (Flag, FlagLight, Cobble shades) whose 0.35 gaps
	show the dark disc as mortar seams. The gaps between the rings are the
	FlagDark bands at r 18-19 and r 30-31.2; the FlagLight disc (r 14)
	carries the fire crystal. A low StoneDark curb (walk-through) runs at
	r 35.6 and opens wherever a road or path enters and in front of the
	forge. Flagstone tops stay below TownSpawn's top (0.45).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local SMOOTH = Enum.Material.SmoothPlastic
local TAU = 2 * math.pi

local Paving = {}

-- Flagstone rings: inner/outer radius, stones per ring, phase (fraction of a stone).
local RINGS = {
	{ R0 = 14.3, R1 = 18, Count = 22, Phase = 0 },
	{ R0 = 19, R1 = 24.4, Count = 28, Phase = 0.5 },
	{ R0 = 24.75, R1 = 30, Count = 32, Phase = 0.25 },
	{ R0 = 31.2, R1 = 35, Count = 36, Phase = 0.6 },
}
local TILE_H = 0.08
local INLAY_R = 9.2

local function tileColor(rng: Rng.Rng): Color3
	local roll = rng:next()
	local color = if roll < 0.6 then C.Flag elseif roll < 0.82 then C.FlagLight elseif roll < 0.94 then C.Cobble else C.StoneLight
	return Style.vary(color, rng, 0.05)
end

local function flagstones(m: Model, center: Vector3, spawn: Vector3, rng: Rng.Rng)
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
			local depth = r1 - ring.R0 - 0.35
			local arc = TAU * rc / ring.Count
			local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * rc
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(spawn.X, 0, spawn.Z)).Magnitude > INLAY_R - 0.5 then
				-- now and then a stone is split in two (worn, uneven paving)
				local frame = CFrame.new(p.X, Common.TileTop - TILE_H / 2, p.Z) * CFrame.Angles(0, -a, 0)
				if rng:chance(0.12) then
					local k = rng:range(0.35, 0.65)
					local l1 = arc * k - 0.4
					local l2 = arc * (1 - k) - 0.4
					local z1 = -arc / 2 + arc * k / 2
					local z2 = arc / 2 - arc * (1 - k) / 2
					Style.block(m, frame * CFrame.new(0, 0, z1), Vector3.new(depth, TILE_H, l1), tileColor(rng), nil, Style.tiny())
					Style.block(m, frame * CFrame.new(0, 0, z2), Vector3.new(depth, TILE_H, l2), tileColor(rng), nil, Style.tiny())
				else
					Style.block(m, frame, Vector3.new(depth, TILE_H, arc - 0.4), tileColor(rng), nil, Style.tiny())
				end
			end
		end
	end
end

-- Walk-through curb blocks on the plaza rim, open at every entrance, with
-- a rhythm of small ground lamps.
local function curb(m: Model, center: Vector3, rng: Rng.Rng)
	local count = 50
	local step = TAU / count
	for i = 0, count - 1 do
		local a = (i + 0.5) * step
		if not (Common.isEntrance(a) or Common.isEntrance(a - step * 0.5) or Common.isEntrance(a + step * 0.5)) then
			local h = if i % 3 == 0 then 1.15 else 0.9
			local frame = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(Common.CurbRadius, h / 2, 0)
			local arc = TAU * Common.CurbRadius / count
			Style.block(m, frame, Vector3.new(1.2, h, arc + 0.05), Style.vary(C.StoneDark, rng, 0.06), nil, Style.ghost())
			-- a small lamp on every fourth block (not on the south arc, right in
			-- front of the spawn camera), a lighter top on every other one
			if i % 4 == 1 and math.sin(a) < 0.75 then
				Style.lantern(m, frame * CFrame.new(0, h / 2, 0), { Kind = "Ground" })
			elseif i % 2 == 0 then
				Style.block(
					m,
					frame * CFrame.new(0, h / 2 + 0.06, 0),
					Vector3.new(1.0, 0.12, arc * 0.8),
					Style.vary(C.Stone, rng, 0.05),
					nil,
					Style.tiny()
				)
			end
		end
	end
end

--[[
	Compass rose around TownSpawn (Town.luau builds the 8x8 pad at the
	center, top 0.45): a FlagLight disc, an octagonal brass frame, brass
	rays N/E/S/W from the pad edge, shorter light rays on the diagonals and
	a brass arrow tip pointing at the forge. All flat (<= 0.47), no
	collision, nothing above y 0.6.
]]
local function spawnInlay(m: Model, spawn: Vector3)
	local c = Vector3.new(spawn.X, 0, spawn.Z)
	Geo.cylinder(m, c + Vector3.new(0, 0.405, 0), 0.08, INLAY_R * 2, C.Flag, SMOOTH, Style.tiny()).Name = "SpawnInlay"
	local top = 0.47
	local ringR = INLAY_R - 0.7
	for i = 0, 7 do
		local a = i * TAU / 8 + TAU / 16
		local len = 2 * ringR * math.tan(math.pi / 8) + 0.5
		local frame = CFrame.new(c) * CFrame.Angles(0, -a, 0) * CFrame.new(ringR * math.cos(math.pi / 8), top - 0.04, 0)
		Style.block(m, frame, Vector3.new(0.4, 0.08, len), C.Brass, SMOOTH, Style.tiny())
	end
	for i = 0, 7 do
		local a = i * TAU / 8
		local long = i % 2 == 0
		local r0 = if long then 4.3 else 5.9
		local r1 = if long then ringR - 0.4 else ringR - 1.4
		local frame = CFrame.new(c) * CFrame.Angles(0, -a, 0) * CFrame.new((r0 + r1) / 2, top - 0.04, 0)
		Style.block(
			m,
			frame,
			Vector3.new(r1 - r0, 0.08, if long then 0.7 else 0.45),
			if long then C.Brass else C.Flag,
			SMOOTH,
			Style.tiny()
		)
	end
	-- arrow tip at the north ray (toward the Great Forge)
	-- (a wedge turned a quarter about Z lies flat: its right angle at the
	-- centerline and the base edge, the tip at local -Z = north)
	local tip = CFrame.new(c + Vector3.new(0, top - 0.04, -(ringR + 0.7)))
	local size = Vector3.new(0.08, 1.2, 1.8)
	Geo.wedge(m, tip * CFrame.new(0.6, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2), size, C.Gold, SMOOTH, Style.tiny())
	Geo.wedge(m, tip * CFrame.new(-0.6, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), size, C.Gold, SMOOTH, Style.tiny())
end

-- Flagstone apron between the plaza rim and the forge steps.
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
		C.FlagDark,
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
			Style.block(
				m,
				CFrame.new((x0 + x1) / 2, Common.TileTop - TILE_H / 2, (zTop + zBottom) / 2),
				Vector3.new(w - 0.35, TILE_H, zTop - zBottom),
				tileColor(rng),
				nil,
				Style.tiny()
			)
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
		C.FlagDark,
		SMOOTH,
		Style.solid({ CastShadow = false })
	)
	floor.Name = "PlazaFloor"
	local inner = Geo.cylinder(m, center + Vector3.new(0, Common.TileTop - 0.04, 0), 0.08, 28, C.FlagLight, SMOOTH, Style.tiny())
	inner.Name = "CrystalFloor"
	flagstones(m, center, spawn, rng)
	curb(Style.model("Curb", m), center, rng)
	spawnInlay(Style.model("SpawnInlay", parent), spawn)
	forgeApron(Style.model("ForgeApron", m), rng)
	rimProps(m, center, rng)
end

return Paving
