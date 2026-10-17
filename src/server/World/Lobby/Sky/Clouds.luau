--[[
	Sky package: voxel cloud banks (docs/plans/LOBBY_PLAN.md 6.1 item 3,
	ART_DIRECTION section 7). A dozen rounded voxel cumulus mounds 450-780
	studs out: a low bank on the west horizon beside the setting sun, high
	clusters over the north-west and the north (the spawn looks up at them),
	and a few in the north-east right of the violet giant. They frame the
	three planets (Planets.luau) and the airship (Airship.luau) instead of
	covering them.

	A cluster (26 parts) is a mound, not a slab: a deep, lumpy base (two
	crossing slabs whose bottoms sit at two heights, so the underside is
	stepped), four lumps poking out of the base on every side (a lumpy
	outline from below too), six domes stepped inward like a pyramid
	(three, two, one), six small cubes on the dome shoulders, and the
	lighting painted in the colors the way the concept lights them: the
	tops are the lightest (CloudLight / CloudPink, warmer toward the sun),
	the base is pink (orange-pink toward the sun) and the purple shade only
	sits on the side away from the sun and on the lower back. Under the base
	a faint warm glow (two translucent Neon sheets, inset, 1.2 studs below
	the base so they never share a face with it) and a thin golden rim on the
	side toward the sun. Each cluster is turned 20-40 degrees away from the
	town so it shows a lit and a shaded face.

	No collision, no shadow, Persistent streaming; all of it stays outside
	the lobby area box and inside the CloudBanks footprint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

type Piece = LobbyLayout.Piece

local Clouds = {}

--[[
	Cluster spots: Az = compass bearing from the plaza in degrees (0 = north
	(-Z), 270 = west (-X)), Dist = studs from the plaza, Y = base height,
	Scale. The sun sits at bearing ~262, ~13 degrees up: the west bank stays
	under it and beside it. The planets (seen from the plaza) cover bearings
	~318-327 (ember), ~334-341 (teal) and ~24-46 (violet giant and its ring)
	from 3 to 16 degrees up, and the airship hangs at ~20 degrees bearing
	over the mountain: the clusters keep out of those windows.
]]
Clouds.Spots = {
	-- low bank on the west horizon, beside and under the sun (south of
	-- bearing ~265 the footprint ends, so the bank runs north of the sun)
	{ Az = 268, Dist = 780, Y = 30, Scale = 1.2 },
	{ Az = 282, Dist = 760, Y = 52, Scale = 1.1 },
	{ Az = 262, Dist = 740, Y = 2, Scale = 0.8 },
	-- the north-west mass left of the ember world, low and high
	{ Az = 296, Dist = 700, Y = 120, Scale = 1.1 },
	{ Az = 305, Dist = 760, Y = 215, Scale = 1.0 },
	{ Az = 307, Dist = 880, Y = 2, Scale = 0.85 },
	-- high over the ember and teal worlds and the mountain: above the hero
	-- camera's frame, in the spawn's upper sky
	{ Az = 326, Dist = 540, Y = 218, Scale = 0.95 },
	{ Az = 343, Dist = 520, Y = 240, Scale = 0.62 },
	{ Az = 358, Dist = 540, Y = 232, Scale = 0.8 },
	-- far over the peak, left of the airship
	{ Az = 352, Dist = 800, Y = 224, Scale = 0.9 },
	{ Az = 2, Dist = 820, Y = 228, Scale = 0.85 },
	-- north-east, high over the violet giant
	{ Az = 35, Dist = 590, Y = 240, Scale = 0.75 },
}

local SUN_AZ = 262

local function bearing(az: number): Vector3
	local r = math.rad(az)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

-- 0..1: how close a bearing is to the sun's.
local function sunward(az: number): number
	local diff = math.abs(((az - SUN_AZ + 180) % 360) - 180)
	return math.clamp(1 - diff / 70, 0, 1)
end

type Block = { X: number, Y: number, Z: number, W: number, H: number, D: number }

--[[
	One rounded cumulus mound. `frame` = bottom center of the cloud, LookVector
	= the side the town sees (already turned). `away` = +1 or -1, the frame X
	side that faces away from the sun. All sizes in studs. 23 parts.
]]
local function cumulus(m: Model, frame: CFrame, scale: number, warm: number, away: number, rng: Rng.Rng)
	local w = rng:range(120, 146) * scale
	local d = w * rng:range(0.74, 0.86)
	local h = w * rng:range(0.66, 0.74)
	local mirror = if rng:chance(0.5) then 1 else -1

	-- lit tops, pink middle, warm underside toward the sun, purple only in the shade
	local top = if warm > 0.5 then C.CloudLight else C.CloudPink:Lerp(C.CloudLight, 0.55)
	local mid = if warm > 0.5 then C.CloudPink:Lerp(C.CloudLight, 0.35) else C.CloudPink
	local base = if warm > 0.4 then C.CloudPink:Lerp(C.CloudOrange, 0.45) else C.CloudPink:Lerp(C.CloudPurple, 0.12)
	local shade = C.CloudPink:Lerp(C.CloudPurple, 0.62)

	-- a block by its bottom, in fractions: X of w, Z of d, Y (bottom) and H of h
	local function box(b: Block, color: Color3, amount: number?): Part
		local size = Vector3.new(b.W * w, b.H * h, b.D * d)
		local at = Vector3.new(b.X * w * mirror, b.Y * h + size.Y / 2, b.Z * d)
		return Kit.box(m, frame, at, size, Style.vary(color, rng, amount or 0.03))
	end
	local function jitter(b: Block): Block
		return {
			X = b.X + rng:range(-0.025, 0.025),
			Y = b.Y,
			Z = b.Z + rng:range(-0.03, 0.03),
			W = b.W * rng:range(0.9, 1.1),
			H = b.H,
			D = b.D * rng:range(0.9, 1.1),
		}
	end

	-- the underside: six puffs of different sizes in a rough ellipse, each
	-- with its bottom at its own height, so from below the cloud is a lumpy
	-- cluster of steps, not one flat plate
	local puffs: { Block } = {
		{ X = -0.2, Y = 0, Z = 0, W = 0.38, H = 0.28, D = 0.56 },
		{ X = 0.18, Y = 0.05, Z = 0.05, W = 0.36, H = 0.26, D = 0.5 },
		{ X = 0.02, Y = 0.08, Z = -0.3, W = 0.34, H = 0.24, D = 0.3 },
		{ X = 0.04, Y = 0.1, Z = 0.3, W = 0.42, H = 0.26, D = 0.28 },
		{ X = -0.41, Y = 0.13, Z = -0.05, W = 0.2, H = 0.22, D = 0.34 },
		{ X = 0.41, Y = 0.11, Z = 0.03, W = 0.2, H = 0.22, D = 0.32 },
	}
	for _, puff in puffs do
		box(jitter(puff), base, 0.04)
	end
	-- a faint warm glow under the lowest puff: inset 15%, 1.2 studs below it
	local low = puffs[1]
	Kit.glow(
		m,
		frame * CFrame.new(low.X * w * mirror, -1.2, low.Z * d),
		Vector3.new(low.W * w * 0.85, 0.3, low.D * d * 0.85),
		if warm > 0.4 then C.CloudOrange else C.CloudPink,
		0.75
	)

	-- six domes stepped inward like a pyramid: three, two, one
	local domes: { Block } = {
		{ X = 0, Y = 0.18, Z = 0, W = 0.46, H = 0.32, D = 0.66 },
		{ X = -0.3, Y = 0.22, Z = 0.05, W = 0.3, H = 0.26, D = 0.52 },
		{ X = 0.3, Y = 0.2, Z = -0.04, W = 0.32, H = 0.28, D = 0.54 },
		{ X = -0.1, Y = 0.46, Z = 0.02, W = 0.34, H = 0.22, D = 0.46 },
		{ X = 0.16, Y = 0.44, Z = -0.02, W = 0.26, H = 0.2, D = 0.4 },
		{ X = -0.02, Y = 0.64, Z = 0.03, W = 0.22, H = 0.16, D = 0.3 },
	}
	for i, dome in domes do
		local b = jitter(dome)
		box(b, if i <= 3 then mid else top)
		-- a small cube on each dome's shoulder breaks the straight top edge
		local s = rng:range(8, 14) * scale
		local side = if i % 2 == 0 then -1 else 1
		box({
			X = b.X + side * b.W * rng:range(0.2, 0.32),
			Y = b.Y + b.H - s * 0.2 / h,
			Z = b.Z + rng:range(-0.2, 0.2) * b.D,
			W = s * 1.3 / w,
			H = s / h,
			D = s * 1.2 / d,
		}, top, 0.04)
	end

	-- purple shade: the side away from the sun and the lower back
	Kit.box(
		m,
		frame,
		Vector3.new(away * w * 0.36, h * 0.38, d * 0.06),
		Vector3.new(w * 0.2, h * 0.3, d * 0.52),
		Style.vary(shade, rng, 0.04)
	)
	Kit.box(m, frame, Vector3.new(0, h * 0.24, d * 0.32), Vector3.new(w * 0.5, h * 0.22, d * 0.26), Style.vary(shade, rng, 0.04))
end

function Clouds.build(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	-- the footprint: Center +- Size/2 horizontally (Facing N, so axis-aligned)
	local minX, maxX = piece.Center.X - piece.Size.X / 2, piece.Center.X + piece.Size.X / 2
	local minZ, maxZ = piece.Center.Z - piece.Size.Z / 2, piece.Center.Z + piece.Size.Z / 2
	local area = LobbyLayout.Area
	local toSun = Vector3.new(LobbyLayout.SunDirection.X, 0, LobbyLayout.SunDirection.Z).Unit
	for _, spot in Clouds.Spots do
		local dir = bearing(spot.Az + rng:range(-1, 1))
		local p = dir * (spot.Dist + rng:range(-12, 12))
		local margin = 90 * spot.Scale
		local x = math.clamp(p.X, minX + margin, maxX - margin)
		local z = math.clamp(p.Z, minZ + margin, maxZ - margin)
		-- never inside the lobby area box (all spots are far outside anyway)
		assert(
			x < area.Min.X - margin or x > area.Max.X + margin or z < area.Min.Z - margin or z > area.Max.Z + margin,
			"cloud cluster inside the lobby area"
		)
		local center = Vector3.new(x, spot.Y + rng:range(-3, 3), z)
		-- face the town, then turn 20-40 degrees so a side face shows too
		local turn = math.rad(rng:range(20, 40)) * (if rng:chance(0.5) then 1 else -1)
		local frame = CFrame.lookAt(center, Vector3.new(0, center.Y, 0)) * CFrame.Angles(0, turn, 0)
		local away = if frame.RightVector:Dot(toSun) > 0 then -1 else 1
		local c = Style.model("Cloud", m)
		cumulus(c, frame, spot.Scale, sunward(spot.Az), away, rng)
	end
	Style.streaming(m, "Persistent")
	return m
end

return Clouds
