--[[
	Sky package: voxel cloud banks (docs/plans/LOBBY_PLAN.md 6.1 item 3,
	ART_DIRECTION section 7). Rounded voxel cumulus clusters and long thin
	stratus streaks 450-900 studs out, lit like the concept's sunset banks.

	A cumulus cluster (24 parts) is a mound, not a slab:
	  - six underside puffs of different sizes in a rough ellipse, each with
	    its bottom at its own height, so from below it is a lumpy cluster of
	    steps, not one flat plate;
	  - under every puff a lit skirt: an inset translucent Neon sheet
	    (CloudOrange toward the sun, peach-pink away from it, Transparency
	    0.3-0.45) 1.2 studs below the puff's bottom (never sharing a face with
	    it), so seen from the plaza the undersides glow warm like the
	    concept's, instead of the dark bottom faces the low sun never reaches;
	  - six domes stepped inward like a pyramid (three, two, one), lit tops
	    (CloudLight / CloudPink, warmer toward the sun);
	  - four small cubes on the dome shoulders that break the straight top
	    edges;
	  - two purple shade blocks, only on the side away from the sun and the
	    upper back.
	Each cluster is turned 20-40 degrees away from the town so it shows a lit
	and a shaded face.

	A stratus streak (7 parts) is a long thin bank high in the sky: four flat
	puffs along it at different heights (a stepped underside and a hump in
	the middle) with lit skirts under the three lowest (the glowing
	underside of an evening stratus).

	Spots: a low bank on the west horizon beside the setting sun, a big low
	mass in the north-west, and over the plaza a mix of small high clusters
	and larger lower ones at many heights (Y 6-270, Scale 0.5-1.55), with the
	stratus streaks above them (Y 270-300, two nearly overhead) filling the
	upper sky. Every cluster
	is either wholly above the hero camera's frame or wholly inside it (no
	cloud bottoms poking in at its top edge), and none covers a planet
	(Planets.luau), the airship (Airship.luau) or the balloon.

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

-- the lit undersides: deep sunset orange toward the sun, a warmer coral
-- away from it (Neon brightens them: CloudOrange itself would glow nearly
-- white)
local GLOW_WARM = Color3.fromRGB(255, 104, 34)
local GLOW_ROSE = Color3.fromRGB(255, 96, 64)
-- skirt transparency (lit undersides)
Clouds.SkirtTransparency = 0.4
-- skirt offset below the block above it (studs): never a shared face
Clouds.SkirtGap = 1.2

export type Spot = { Az: number, Dist: number, Y: number, Scale: number }
export type Streak = { Az: number, Dist: number, Y: number, Length: number }

--[[
	Cluster spots: Az = compass bearing from the plaza in degrees (0 = north
	(-Z), 270 = west (-X)), Dist = studs from the plaza, Y = base height,
	Scale. The sun sits at bearing ~262, ~13 degrees up: the west bank stays
	under it and beside it. The planets (seen from the plaza) sit at bearings
	~318-327 (ember), ~335-341 (teal) and ~22-43 (violet giant and its ring)
	3-15 degrees up, the airship at ~20 degrees bearing ~17 degrees up over
	the mountain and the balloon at ~-28 bearing ~30 degrees up from the
	spawn: the clusters keep out of those windows. A cluster high over the
	plaza has its base above the hero frame's top edge (~11 degrees up from
	the hero camera), so the hero never shows only its bottom.
]]
Clouds.Spots = {
	-- low bank on the west horizon, beside and under the sun (south of
	-- bearing ~265 the footprint ends, so the bank runs north of the sun)
	{ Az = 268, Dist = 780, Y = 30, Scale = 1.2 },
	{ Az = 282, Dist = 760, Y = 64, Scale = 1.0 },
	{ Az = 262, Dist = 740, Y = 6, Scale = 0.8 },
	-- a big low mass in the north-west and a small high one over it
	{ Az = 296, Dist = 720, Y = 96, Scale = 1.55 },
	{ Az = 307, Dist = 640, Y = 262, Scale = 0.5 },
	{ Az = 312, Dist = 880, Y = 6, Scale = 0.9 },
	-- over the plaza, seen from the spawn, in three tiers: larger mounds
	-- left of the balloon, over the forge and right of the east island,
	-- smaller ones between them and one low and far over the massif's left
	-- shoulder (the streaks below fill the top tier)
	{ Az = 318, Dist = 560, Y = 194, Scale = 0.75 },
	{ Az = 346, Dist = 760, Y = 250, Scale = 0.6 },
	{ Az = 357, Dist = 610, Y = 268, Scale = 0.5 },
	{ Az = 8, Dist = 500, Y = 206, Scale = 0.7 },
	{ Az = 22, Dist = 560, Y = 262, Scale = 0.55 },
	{ Az = 36, Dist = 520, Y = 226, Scale = 0.62 },
}

--[[
	Stratus streaks: long thin banks high over the plaza (the top tier of
	the spawn's sky, above the balloon's left, over the forge and over the
	east island), two nearly overhead and one low over the western sea.
	Length in studs.
]]
Clouds.Streaks = {
	{ Az = 314, Dist = 440, Y = 272, Length = 170 },
	{ Az = 350, Dist = 470, Y = 296, Length = 200 },
	{ Az = 33, Dist = 460, Y = 292, Length = 170 },
	{ Az = 290, Dist = 820, Y = 180, Length = 220 },
	-- two nearly overhead, north of the lobby box (seen when looking up)
	{ Az = 350, Dist = 230, Y = 300, Length = 160 },
	{ Az = 24, Dist = 260, Y = 296, Length = 150 },
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
	side that faces away from the sun. All sizes in studs. 24 parts: 6 puffs,
	6 lit skirts, 6 domes, 4 shoulder cubes, 2 shade blocks.
]]
local function cumulus(m: Model, frame: CFrame, scale: number, warm: number, away: number, rng: Rng.Rng)
	local w = rng:range(120, 146) * scale
	local d = w * rng:range(0.74, 0.86)
	local h = w * rng:range(0.66, 0.74)
	local mirror = if rng:chance(0.5) then 1 else -1

	-- lit tops, pink middle, warm underside toward the sun, purple only in the shade
	local top = if warm > 0.5 then C.CloudLight else C.CloudPink:Lerp(C.CloudLight, 0.55)
	local mid = if warm > 0.5 then C.CloudPink:Lerp(C.CloudLight, 0.35) else C.CloudPink
	local base = if warm > 0.4 then C.CloudPink:Lerp(C.CloudOrange, 0.45) else C.CloudPink:Lerp(C.CloudOrange, 0.2)
	local shade = C.CloudPink:Lerp(C.CloudPurple, 0.62)
	local glow = if warm > 0.3 then GLOW_WARM else GLOW_ROSE

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
	-- with its bottom at its own height, and a lit skirt under each one
	local puffs: { Block } = {
		{ X = -0.2, Y = 0, Z = 0, W = 0.38, H = 0.28, D = 0.56 },
		{ X = 0.18, Y = 0.05, Z = 0.05, W = 0.36, H = 0.26, D = 0.5 },
		{ X = 0.02, Y = 0.08, Z = -0.3, W = 0.34, H = 0.24, D = 0.3 },
		{ X = 0.04, Y = 0.1, Z = 0.3, W = 0.42, H = 0.26, D = 0.28 },
		{ X = -0.41, Y = 0.13, Z = -0.05, W = 0.2, H = 0.22, D = 0.34 },
		{ X = 0.41, Y = 0.11, Z = 0.03, W = 0.2, H = 0.22, D = 0.32 },
	}
	for _, puff in puffs do
		local b = jitter(puff)
		box(b, base, 0.04)
		local skirt = Kit.glow(
			m,
			frame * CFrame.new(b.X * w * mirror, b.Y * h - Clouds.SkirtGap - 0.15, b.Z * d),
			Vector3.new(b.W * w * 0.9, 0.3, b.D * d * 0.9),
			Style.vary(glow, rng, 0.03),
			Clouds.SkirtTransparency
		)
		skirt.Name = "Skirt"
	end

	-- six domes stepped inward like a pyramid: three, two, one; a small cube
	-- on the shoulder of the four biggest breaks the straight top edge
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
		if i <= 4 then
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
	end

	-- purple shade: the side away from the sun and the upper back
	Kit.box(
		m,
		frame,
		Vector3.new(away * w * 0.36, h * 0.4, d * 0.06),
		Vector3.new(w * 0.2, h * 0.28, d * 0.52),
		Style.vary(shade, rng, 0.04)
	)
	Kit.box(m, frame, Vector3.new(0, h * 0.42, d * 0.3), Vector3.new(w * 0.46, h * 0.24, d * 0.26), Style.vary(shade, rng, 0.04))
end

--[[
	One stratus streak. `frame` = bottom center, LookVector = toward the town
	(the streak runs along the frame X axis). 7 parts: four flat puffs along
	the streak at different heights (a stepped underside and a hump in the
	middle, not one plank) and lit skirts under the three lowest.
]]
local function stratus(m: Model, frame: CFrame, length: number, warm: number, rng: Rng.Rng)
	-- narrow for its length: seen from below at 25-30 degrees its pink sides
	-- show as much as its glowing underside, so it reads as a streak, not a
	-- floating panel
	local depth = length * rng:range(0.13, 0.17)
	local top = if warm > 0.5 then C.CloudLight else C.CloudPink:Lerp(C.CloudLight, 0.5)
	local low = if warm > 0.4 then C.CloudPink:Lerp(C.CloudOrange, 0.4) else C.CloudPink
	local glow = if warm > 0.3 then GLOW_WARM else GLOW_ROSE
	local side = if rng:chance(0.5) then 1 else -1
	local puffs = {
		-- { x, bottom, z, length, height, depth } in fractions of the length /
		-- studs: overlapping lumps whose bottoms step by several studs, so
		-- their pink sides show between the glowing undersides
		{ -0.28 * side, 0, 0.3, 0.44, 10, 0.8 },
		{ 0.06 * side, -4, -0.25, 0.38, 11, 1 },
		{ 0.34 * side, 2.5, 0.35, 0.3, 9, 0.75 },
		{ -0.04 * side, 6, 0.1, 0.36, 8, 0.7 },
	}
	for i, p in puffs do
		local size = Vector3.new(length * p[4] * rng:range(0.92, 1.08), p[5], depth * p[6] * rng:range(0.85, 1.15))
		-- each lump turned a little off the streak, so the outline is ragged
		local cf = frame * CFrame.new(length * p[1], 0, depth * p[3]) * CFrame.Angles(0, math.rad(rng:range(-9, 9)), 0)
		Style.block(m, cf * CFrame.new(0, p[2] + p[5] / 2, 0), size, Style.vary(if i == 4 then top else low, rng, 0.03), nil, Kit.far())
		if i <= 3 then
			local skirt = Kit.glow(
				m,
				cf * CFrame.new(0, p[2] - Clouds.SkirtGap - 0.15, 0),
				Vector3.new(size.X * 0.9, 0.3, size.Z * 0.88),
				Style.vary(glow, rng, 0.03),
				Clouds.SkirtTransparency
			)
			skirt.Name = "Skirt"
		end
	end
end

function Clouds.build(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	-- the footprint: Center +- Size/2 horizontally (Facing N, so axis-aligned)
	local minX, maxX = piece.Center.X - piece.Size.X / 2, piece.Center.X + piece.Size.X / 2
	local minZ, maxZ = piece.Center.Z - piece.Size.Z / 2, piece.Center.Z + piece.Size.Z / 2
	local area = LobbyLayout.Area
	local toSun = Vector3.new(LobbyLayout.SunDirection.X, 0, LobbyLayout.SunDirection.Z).Unit
	local function place(az: number, dist: number, margin: number): (number, number)
		local p = bearing(az) * dist
		local x = math.clamp(p.X, minX + margin, maxX - margin)
		local z = math.clamp(p.Z, minZ + margin, maxZ - margin)
		-- never inside the lobby area box (all spots are far outside anyway)
		assert(
			x < area.Min.X - margin or x > area.Max.X + margin or z < area.Min.Z - margin or z > area.Max.Z + margin,
			"cloud inside the lobby area"
		)
		return x, z
	end
	for _, spot in Clouds.Spots do
		local x, z = place(spot.Az + rng:range(-1, 1), spot.Dist + rng:range(-12, 12), 90 * spot.Scale)
		local center = Vector3.new(x, spot.Y + rng:range(-3, 3), z)
		-- face the town, then turn 20-40 degrees so a side face shows too
		local turn = math.rad(rng:range(20, 40)) * (if rng:chance(0.5) then 1 else -1)
		local frame = CFrame.lookAt(center, Vector3.new(0, center.Y, 0)) * CFrame.Angles(0, turn, 0)
		local away = if frame.RightVector:Dot(toSun) > 0 then -1 else 1
		local c = Style.model("Cloud", m)
		cumulus(c, frame, spot.Scale, sunward(spot.Az), away, rng)
	end
	for _, streak in Clouds.Streaks do
		local x, z = place(streak.Az, streak.Dist, streak.Length * 0.55)
		local center = Vector3.new(x, streak.Y, z)
		-- broadside to the town, a little skewed
		local frame = CFrame.lookAt(center, Vector3.new(0, center.Y, 0)) * CFrame.Angles(0, math.rad(rng:range(-14, 14)), 0)
		local c = Style.model("Stratus", m)
		stratus(c, frame, streak.Length, sunward(streak.Az), rng)
	end
	Style.streaming(m, "Persistent")
	return m
end

return Clouds
