--[[
	Flora water: the lily pond (left), the koi pond (right), the creek that
	joins them and the arched wooden bridge that carries the south road over
	the creek (LOBBY_PLAN 6.5 items 1-4). All water is non-collide over the
	solid ground (wading, never a hole); the bridge deck is walkable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

local Water = {}

-- The creek's water band (world z), shared by the ponds' rim gaps and the fences.
Water.CreekMinZ = 59
Water.CreekMaxZ = 65

local function creekGap(x0: number, x1: number): Kit.Gap
	return {
		Min = Vector3.new(math.min(x0, x1), 0, Water.CreekMinZ - 0.6),
		Max = Vector3.new(math.max(x0, x1), 0, Water.CreekMaxZ + 0.6),
	}
end

function Water.lilyPond(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("LilyPond")
	local c = piece.Center
	local m = Style.model("LilyPond", parent)
	local pond = Style.pond(m, c, piece.Size.X, piece.Size.Z, rng, { LilyPads = 5, Rim = false })
	pond.Name = "Pond"
	-- rim with a gap on the east side where the creek flows in
	Kit.rim(m, c, piece.Size.X, piece.Size.Z, rng, { creekGap(c.X + piece.Size.X / 2 - 3.5, c.X + piece.Size.X / 2 + 1) })
	-- cattails in the shallow corners
	Kit.cattails(m, c + Vector3.new(-8.6, 0, -4.2), rng, 3)
	Kit.cattails(m, c + Vector3.new(7.4, 0, 4.4), rng, 2)
	-- two small purple crystal clusters on the west bank (no light)
	Kit.smallCrystals(m, CFrame.new(c + Vector3.new(-11.6, 0, -5.4)) * CFrame.Angles(0, 0.4, 0), C.CrystalPurple, rng, 2.8)
	Kit.smallCrystals(m, CFrame.new(c + Vector3.new(-11.8, 0, 4.6)) * CFrame.Angles(0, -0.7, 0), C.CrystalViolet, rng, 2.2)
	-- pink flowers on the south bank corners
	Kit.flowerRing(m, c + Vector3.new(-12.4, 0, 7.6), 0.9, { C.FlowerPink, C.LeafPinkLight, C.FlowerWhite }, rng, 3)
	-- ground lantern on the north-west bank
	Style.lantern(m, CFrame.new(c + Vector3.new(-12.6, 0, -6.6)), { Kind = "Ground" })
	return m
end

function Water.koiPond(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("KoiPond")
	local c = piece.Center
	local m = Style.model("KoiPond", parent)
	local pond = Style.pond(m, c, piece.Size.X, piece.Size.Z, rng, { LilyPads = 4, Koi = 6, Rim = false })
	pond.Name = "Pond"
	Kit.rim(m, c, piece.Size.X, piece.Size.Z, rng, { creekGap(c.X - piece.Size.X / 2 - 1, c.X - piece.Size.X / 2 + 3.5) })
	-- stepping stones across the east end (walkable, just above the water)
	local stones = { { 5.2, -5.4 }, { 6.4, -2.6 }, { 5.6, 0.2 }, { 6.6, 3 }, { 5.4, 5.6 } }
	for i, s in stones do
		local size = rng:range(2, 2.5)
		local stone = Style.block(
			m,
			CFrame.new(c + Vector3.new(s[1], 0.45, s[2])) * CFrame.Angles(0, rng:range(-0.3, 0.3), 0),
			Vector3.new(size, 0.9, size * 0.9),
			Style.vary(if i % 2 == 0 then C.StoneLight else C.FlagLight, rng, 0.04),
			nil,
			Style.solid()
		)
		stone.Name = "SteppingStone"
	end
	-- two ground lanterns on the banks and a post lantern with the pond's light
	Style.lantern(m, CFrame.new(c + Vector3.new(-6, 0, -7.6)), { Kind = "Ground" })
	Style.lantern(m, CFrame.new(c + Vector3.new(4, 0, 7.6)), { Kind = "Ground" })
	Style.lantern(m, CFrame.new(c + Vector3.new(13.6, 0, -6.6)) * CFrame.Angles(0, math.pi * 0.75, 0), {
		Kind = "Post",
		Height = 7,
		Light = true,
		Range = 18,
		Brightness = 1.4,
	})
	return m
end

function Water.creek(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("Creek")
	local c = piece.Center
	local m = Style.model("Creek", parent)
	local length = piece.Size.X
	local width = Water.CreekMaxZ - Water.CreekMinZ
	local z = (Water.CreekMinZ + Water.CreekMaxZ) / 2
	Style.block(m, CFrame.new(c.X, 0.08, z), Vector3.new(length + 2, 0.16, width - 0.4), C.WaterDeep, nil, Style.tiny())
	Style.water(m, CFrame.new(c.X, 0.4, z), Vector3.new(length + 3, 0.5, width))
	-- bank stones on both banks, clear of the bridge
	for _, side in { -1, 1 } do
		for _, bankZ in { Water.CreekMinZ - 0.3, Water.CreekMaxZ + 0.3 } do
			local x = 6.6
			while x < length / 2 - 1.2 do
				local s = rng:range(1.4, 2)
				local h = rng:range(0.6, 1)
				Style.block(
					m,
					CFrame.new(c.X + side * x, h / 2, bankZ + rng:range(-0.25, 0.25)) * CFrame.Angles(0, rng:range(-0.35, 0.35), 0),
					Vector3.new(s, h, s * 0.9),
					Style.vary(if rng:chance(0.5) then C.Stone else C.StoneLight, rng, 0.05),
					nil,
					Style.solid()
				)
				x += rng:range(2.4, 3.2)
			end
		end
	end
	-- a lily pad drifting in the creek, west of the bridge
	local pad = c + Vector3.new(-9.5, 0.68, 0.8)
	local geo = Style.block(m, CFrame.new(pad), Vector3.new(1.8, 0.12, 1.8), C.LeafGreen, nil, Style.tiny())
	geo.Name = "LilyPad"
	return m
end

function Water.bridge(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("CreekBridge")
	local c = piece.Center
	local half = piece.Size.Z / 2
	local from = c - Vector3.new(0, 0, half)
	local to = c + Vector3.new(0, 0, half)
	local width = 10
	local m = Style.archBridge(parent, from, to, width, 2.4, rng, { Segments = 5 })
	m.Name = "CreekBridge"
	-- lamp boxes on the four tall end posts (light at the south end, toward the camera)
	for _, z in { from.Z, to.Z } do
		for _, side in { -1, 1 } do
			local top = CFrame.new(c.X + side * (width / 2 + 0.3), c.Y + 3.4, z)
			Kit.lampBox(m, top, 0.95, z == to.Z and side == 1)
		end
	end
	return m
end

function Water.build(parent: Instance, rng: Rng.Rng)
	Water.lilyPond(parent, Kit.sub(rng))
	Water.koiPond(parent, Kit.sub(rng))
	Water.creek(parent, Kit.sub(rng))
	Water.bridge(parent, Kit.sub(rng))
end

return Water
