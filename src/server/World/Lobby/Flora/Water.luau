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
Water.BridgeHalf = 5.6

local function bridgeGap(c: Vector3, sizeZ: number): Kit.Gap
	return {
		Min = Vector3.new(c.X - Water.BridgeHalf, 0, c.Z - sizeZ / 2 - 2),
		Max = Vector3.new(c.X + Water.BridgeHalf, 0, c.Z + sizeZ / 2 + 2),
	}
end

-- The koi pond's surface: deep teal (the light Water colour only shows as a
-- band of shallows along the rim).
Water.DeepTeal = Color3.fromRGB(20, 110, 150)
-- (lobby fix round 3) the ponds' water: teal-blue shallows over a deep
-- centre, a light polish (the round-2 water mirrored the sky into flat
-- blue puddles), a few neon glints and koi
Water.Shallows = Color3.fromRGB(40, 150, 200)
Water.Reflectance = 0.08
Water.Glint = Color3.fromRGB(170, 235, 255)

-- Retint a pond's water, then 3-4 thin neon glints on it and `koi` more koi.
local function dress(pond: Instance, c: Vector3, sizeX: number, sizeZ: number, koi: number, rng: Rng.Rng)
	for _, d in pond:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Water" then
			if d.Color ~= Water.DeepTeal then
				d.Color = Water.Shallows
			end
			d.Reflectance = Water.Reflectance
		end
	end
	for _ = 1, 4 do
		local q = c + Vector3.new(rng:range(-sizeX * 0.3, sizeX * 0.3), 0.69, rng:range(-sizeZ * 0.25, sizeZ * 0.25))
		Style.block(
			pond,
			CFrame.new(q) * CFrame.Angles(0, rng:range(-0.4, 0.4), 0),
			Vector3.new(rng:range(1.0, 1.8), 0.04, 0.16),
			Water.Glint,
			Enum.Material.Neon,
			Style.tiny({ Transparency = 0.3 })
		).Name =
			"Glint"
	end
	for i = 1, koi do
		local q = c + Vector3.new(rng:range(-sizeX * 0.3, sizeX * 0.3), 0.66, rng:range(-sizeZ * 0.22, sizeZ * 0.22))
		local fish = CFrame.new(q) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0)
		Style.block(pond, fish, Vector3.new(0.55, 0.3, 1.4), if i % 2 == 0 then C.FlowerWhite else C.LeafOrange, nil, Style.tiny()).Name =
			"Koi"
		Style.block(pond, fish * CFrame.new(0, 0, 0.85), Vector3.new(0.7, 0.12, 0.45), C.FlowerWhite, nil, Style.tiny())
	end
end

function Water.lilyPond(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("LilyPond")
	local c = piece.Center
	local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
	local m = Style.model("LilyPond", parent)
	local pond = Style.pond(m, c, piece.Size.X, piece.Size.Z, rng, { LilyPads = 4, Rim = false })
	pond.Name = "Pond"
	dress(pond, c, piece.Size.X, piece.Size.Z, 3, rng)
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
	-- the deep teal surface inset 1.2 studs inside the light shallows (the same
	-- cross shape as Style.pond's water, 0.02 higher)
	local inX, inZ = piece.Size.X - 2, piece.Size.Z - 2
	for _, size in { Vector3.new(inX - 2.4, 0.5, inZ * 0.7 - 2.4), Vector3.new(inX * 0.78 - 2.4, 0.5, inZ - 2.4) } do
		local deep = Style.water(pond, CFrame.new(c + Vector3.new(0, 0.42, 0)), size, Water.DeepTeal)
		deep.Name = "Water"
	end
	dress(pond, c, piece.Size.X, piece.Size.Z, 0, rng)
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
	-- two ground lanterns and a post lantern with the pond's light on the
	-- south bank, each 2.6 studs off the pond's bounds (never on the rim)
	Style.lantern(m, CFrame.new(c + Vector3.new(-13, 0, hz + 2.9)), { Kind = "Ground", Color = C.LampAmber })
	Style.lantern(m, CFrame.new(c + Vector3.new(9, 0, hz + 2.9)), { Kind = "Ground", Color = C.LampAmber })
	Style.lantern(m, CFrame.new(c + Vector3.new(hx - 4.5, 0, hz + 2.9)) * CFrame.Angles(0, math.pi, 0), {
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
	segments rising to a real crown (Water.BridgeRise over the water, each
	segment a gentle step), a dark arched stringer under each deck edge that
	follows the hump and reaches down to the water at the ends (so the arch
	reads from the high hero camera too, against the deep teal water),
	stepped railings (a post at every joint, a dark rail and a lighter cap
	rail that step up with the deck) and a tall post with a caged amber lamp
	at each end (neon, no light). Narrower than the road (8.4): the water
	shows wide on both sides of the deck.
]]
Water.BridgeRise = 3.6
Water.BridgeSegments = 8
Water.BridgeWidth = 8.4
function Water.bridge(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("CreekBridge")
	local c = piece.Center
	local half = piece.Size.Z / 2
	local from = c - Vector3.new(0, 0, half)
	local to = c + Vector3.new(0, 0, half)
	local width = Water.BridgeWidth
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
		-- the arched stringers: dark timber under both deck edges, deeper toward
		-- the ends (the arch springs from the banks)
		local mid = (i + 0.5) / n
		local depth = 1.0 + 1.4 * (2 * mid - 1) ^ 2
		for _, side in { -1, 1 } do
			Style.block(
				m,
				frame * CFrame.new(side * (width / 2 + 0.25), -depth / 2 + 0.2, 0),
				Vector3.new(0.7, depth, seg.Magnitude + 0.3),
				C.WoodDark,
				nil,
				Style.tiny()
			)
		end
	end
	-- stepped railings: a post at every joint (rising with the deck), a dark
	-- rail and a lighter cap rail from post to post
	for i = 0, n do
		local p = point(i / n)
		local tall = i == 0 or i == n
		for _, side in { -1, 1 } do
			local base = p + right * side * (width / 2 + 0.3)
			if tall then
				-- (the end lanterns stand just past the deck's ends, 2 studs off the pond)
				bridgeLantern(m, base + Vector3.new(0, 0, if i == 0 then -0.4 else 0.4), 4.4)
			else
				Style.block(m, CFrame.new(base + Vector3.new(0, 1.45, 0)), Vector3.new(0.6, 2.9, 0.6), C.WoodDark)
			end
		end
	end
	for i = 0, n - 1 do
		local a, b = point(i / n), point((i + 1) / n)
		for _, side in { -1, 1 } do
			for _, rail in { { Y = 2.5, W = 0.6, H = 0.5, Color = C.Wood } } do
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
