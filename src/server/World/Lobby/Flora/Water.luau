--[[
	Flora water (LOBBY_PLAN 6.5 items 1-4, concept v1): the small lily
	pond left of the plaza at plaza depth, and the big koi pond in the
	foreground under the humped wooden bridge that carries the south road
	over it. All water is non-collide over the solid ground (wading, never
	a hole); the bridge deck is walkable, the koi pond's rim opens under it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

local Water = {}

-- The bridge's deck band (world x): the koi pond's rim opens under it.
Water.BridgeHalf = 6.6

local function bridgeGap(c: Vector3, sizeZ: number): Kit.Gap
	return {
		Min = Vector3.new(c.X - Water.BridgeHalf, 0, c.Z - sizeZ / 2 - 2),
		Max = Vector3.new(c.X + Water.BridgeHalf, 0, c.Z + sizeZ / 2 + 2),
	}
end

function Water.lilyPond(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("LilyPond")
	local c = piece.Center
	local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
	local m = Style.model("LilyPond", parent)
	local pond = Style.pond(m, c, piece.Size.X, piece.Size.Z, rng, { LilyPads = 4, Rim = false })
	pond.Name = "Pond"
	Kit.rim(m, c, piece.Size.X, piece.Size.Z, rng, {})
	-- cattails in the shallow corners
	Kit.cattails(m, c + Vector3.new(-hx + 2.6, 0, -hz + 2.4), rng, 3)
	Kit.cattails(m, c + Vector3.new(hx - 2.8, 0, hz - 2.2), rng, 2)
	-- a small purple crystal cluster on the west bank (no light)
	Kit.smallCrystals(m, CFrame.new(c + Vector3.new(-hx - 0.2, 0, -hz + 2.6)) * CFrame.Angles(0, 0.4, 0), C.CrystalPurpleDeep, rng, 2.4)
	-- pink flowers on the south-west bank corner
	Kit.flowerRing(m, c + Vector3.new(-hx + 1.6, 0, hz + 0.4), 0.9, { C.FlowerPink, C.LeafPinkLight, C.FlowerWhite }, rng, 3)
	return m
end

function Water.koiPond(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("KoiPond")
	local c = piece.Center
	local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
	local m = Style.model("KoiPond", parent)
	local pond = Style.pond(m, c, piece.Size.X, piece.Size.Z, rng, { LilyPads = 6, Koi = 8, Rim = false })
	pond.Name = "Pond"
	-- the stone rim opens under the bridge (the south road crosses there)
	Kit.rim(m, c, piece.Size.X, piece.Size.Z, rng, { bridgeGap(c, piece.Size.Z) })
	-- stepping stones across the east end (walkable, just above the water)
	local stones = { { hx - 4.2, -3.6 }, { hx - 3.2, -0.6 }, { hx - 4.4, 2.4 }, { hx - 3.4, 4.8 } }
	for i, st in stones do
		local size = rng:range(2, 2.4)
		local stone = Style.block(
			m,
			CFrame.new(c + Vector3.new(st[1], 0.45, st[2])) * CFrame.Angles(0, rng:range(-0.3, 0.3), 0),
			Vector3.new(size, 0.9, size * 0.9),
			Style.vary(if i % 2 == 0 then C.StoneLight else C.FlagLight, rng, 0.04),
			nil,
			Style.solid()
		)
		stone.Name = "SteppingStone"
	end
	-- cattails at both far ends and a little crystal cluster on the west bank
	Kit.cattails(m, c + Vector3.new(-hx + 2.4, 0, -hz + 2.2), rng, 3)
	Kit.cattails(m, c + Vector3.new(hx - 1.8, 0, hz - 1.6), rng, 2)
	Kit.smallCrystals(m, CFrame.new(c + Vector3.new(-hx + 1.2, 0, hz + 1.2)) * CFrame.Angles(0, -0.6, 0), C.CrystalPurpleDeep, rng, 2.2)
	-- two ground lanterns on the south bank and a post lantern with the pond's light
	Style.lantern(m, CFrame.new(c + Vector3.new(-11, 0, hz + 1.4)), { Kind = "Ground", Color = C.LampAmber })
	Style.lantern(m, CFrame.new(c + Vector3.new(11, 0, hz + 1.4)), { Kind = "Ground", Color = C.LampAmber })
	Style.lantern(m, CFrame.new(c + Vector3.new(hx + 1.6, 0, -hz + 1.4)) * CFrame.Angles(0, math.pi * 0.75, 0), {
		Kind = "Post",
		Height = 7,
		Light = true,
		Range = 18,
		Brightness = 1.2,
		Color = C.LampAmber,
	})
	return m
end

-- Lantern post at a bridge end: a dark timber post with a cap and a small
-- caged amber lamp on top (neon only, no light). 6 parts.
local function bridgeLantern(parent: Instance, foot: Vector3, h: number)
	local m = Style.model("Lantern", parent)
	Style.block(m, CFrame.new(foot + Vector3.new(0, h / 2, 0)), Vector3.new(0.9, h, 0.9), C.WoodDark)
	Style.block(m, CFrame.new(foot + Vector3.new(0, h + 0.15, 0)), Vector3.new(1.3, 0.3, 1.3), C.Wood, nil, Style.tiny())
	local glow = Style.block(
		m,
		CFrame.new(foot + Vector3.new(0, h + 0.75, 0)),
		Vector3.new(0.55, 0.7, 0.55),
		C.LampAmber,
		Enum.Material.Neon,
		Style.tiny()
	)
	glow.Name = "LanternGlow"
	for _, sx in { -1, 1 } do
		Style.block(m, CFrame.new(foot + Vector3.new(sx * 0.42, h + 0.75, 0)), Vector3.new(0.16, 0.95, 0.9), C.Iron, nil, Style.tiny())
	end
	Style.block(m, CFrame.new(foot + Vector3.new(0, h + 1.35, 0)), Vector3.new(1.2, 0.3, 1.2), C.Iron, nil, Style.tiny())
	m.PrimaryPart = glow
end

--[[
	The humped bridge over the koi pond (concept v1): a deck of plank
	segments rising to a real hump (Water.BridgeRise over the water, each
	segment a gentle step), dark timber side beams under it and an arched
	dark-timber railing on each side (posts at every segment joint, a rail
	that follows the hump and a lighter cap rail), a tall post with a caged
	amber lamp at each end (neon, no light). The water shows on both sides
	of the deck and under its arched side beams.
]]
Water.BridgeRise = 3.6
Water.BridgeSegments = 6
function Water.bridge(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("CreekBridge")
	local c = piece.Center
	local half = piece.Size.Z / 2
	local from = c - Vector3.new(0, 0, half)
	local to = c + Vector3.new(0, 0, half)
	local width = 10
	local m = Style.model("CreekBridge", parent)
	local n = Water.BridgeSegments
	local rise = Water.BridgeRise
	local length = to.Z - from.Z
	local function point(t: number): Vector3
		local y = rise * (1 - (2 * t - 1) ^ 2)
		return from + Vector3.new(0, y, length * t)
	end
	local thickness = 0.7
	local right = Vector3.new(1, 0, 0)
	for i = 0, n - 1 do
		local a, b = point(i / n), point((i + 1) / n)
		local seg = b - a
		local dir = seg.Unit
		local up = right:Cross(dir)
		if up.Y < 0 then
			up = -up
		end
		local frame = CFrame.fromMatrix((a + b) / 2 - up * (thickness / 2), right, up, -dir)
		local color = if i % 2 == 0 then C.Plank else C.WoodLight
		Style.block(m, frame, Vector3.new(width, thickness, seg.Magnitude + 0.35), Style.vary(color, rng, 0.03), nil, Style.solid())
		-- dark arched side beams under the deck edges
		for _, side in { -1, 1 } do
			Style.block(
				m,
				frame * CFrame.new(side * (width / 2 + 0.2), -0.45, 0),
				Vector3.new(0.6, 1.2, seg.Magnitude + 0.3),
				C.WoodDark,
				nil,
				Style.tiny()
			)
		end
	end
	-- arched dark timber railings: a post at every joint, a rail along the
	-- hump and a lighter cap rail on it
	for i = 0, n do
		local p = point(i / n)
		local tall = i == 0 or i == n
		for _, side in { -1, 1 } do
			local base = p + right * side * (width / 2 + 0.3)
			if tall then
				bridgeLantern(m, base, 4.4)
			else
				Style.block(m, CFrame.new(base + Vector3.new(0, 1.35, 0)), Vector3.new(0.6, 2.7, 0.6), C.WoodDark)
			end
		end
	end
	for i = 0, n - 1 do
		local a, b = point(i / n), point((i + 1) / n)
		for _, side in { -1, 1 } do
			for _, rail in { { Y = 2.3, W = 0.45, H = 0.4, Color = C.WoodDark }, { Y = 2.65, W = 0.6, H = 0.22, Color = C.Wood } } do
				local pa = a + right * side * (width / 2 + 0.3) + Vector3.new(0, rail.Y, 0)
				local pb = b + right * side * (width / 2 + 0.3) + Vector3.new(0, rail.Y, 0)
				local seg = pb - pa
				local frame = CFrame.fromMatrix((pa + pb) / 2, right, right:Cross(seg.Unit), -seg.Unit)
				Style.block(
					m,
					frame,
					Vector3.new(rail.W, rail.H, seg.Magnitude + 0.5),
					rail.Color,
					nil,
					Style.decor({ CastShadow = false })
				)
			end
		end
	end
	return m
end

function Water.build(parent: Instance, rng: Rng.Rng)
	Water.lilyPond(parent, Kit.sub(rng))
	Water.koiPond(parent, Kit.sub(rng))
	Water.bridge(parent, Kit.sub(rng))
end

return Water
