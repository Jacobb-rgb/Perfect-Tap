--[[
	Sky package: voxel cloud banks (docs/plans/LOBBY_PLAN.md 6.1 item 3,
	ART_DIRECTION section 7). Flat clusters of big blocks 450-900 studs out,
	120-240 high, from the west (where the sun sets) through the north-west
	to the north and a few in the north-east. Each block is a lit body
	(CloudLight/CloudOrange near the sun, CloudPink further away) under a
	purple cap (CloudPurple/SkyPurple), on a warm underside slab, so from
	the town the clouds read pink and orange below and purple on top.
	No collision, no shadow, Persistent streaming; all of it stays outside
	the lobby area box.
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
	Cloud bank spots: Az = compass bearing from the plaza in degrees (0 =
	north (-Z), 270 = west (-X)), Dist = studs from the plaza, Y = base
	height, Scale. Three bands: big low banks on the horizon (far), a middle
	band and a few high clusters (nearer). The sun sits at bearing ~262,
	~13 degrees up: the bank under it stays low, the others leave it free.
]]
Clouds.Spots = {
	-- horizon band
	{ Az = 262, Dist = 720, Y = 90, Scale = 1.0 },
	{ Az = 279, Dist = 700, Y = 112, Scale = 1.3 },
	{ Az = 302, Dist = 720, Y = 122, Scale = 1.4 },
	{ Az = 327, Dist = 700, Y = 110, Scale = 1.35 },
	{ Az = 351, Dist = 720, Y = 124, Scale = 1.4 },
	{ Az = 17, Dist = 700, Y = 116, Scale = 1.3 },
	-- middle band
	{ Az = 256, Dist = 560, Y = 190, Scale = 0.9 },
	{ Az = 287, Dist = 580, Y = 176, Scale = 1.05 },
	{ Az = 313, Dist = 620, Y = 204, Scale = 1.1 },
	{ Az = 337, Dist = 560, Y = 168, Scale = 1.0 },
	{ Az = 359, Dist = 600, Y = 198, Scale = 1.1 },
	{ Az = 24, Dist = 560, Y = 172, Scale = 0.95 },
	{ Az = 40, Dist = 520, Y = 194, Scale = 0.8 },
	-- high clusters
	{ Az = 296, Dist = 470, Y = 236, Scale = 0.8 },
	{ Az = 341, Dist = 450, Y = 232, Scale = 0.75 },
	{ Az = 8, Dist = 470, Y = 238, Scale = 0.8 },
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

--[[
	One cloud bank, a puffy voxel cumulus with volume and two tones.
	`frame` = bottom center, LookVector = toward the plaza. A flat lit base
	(CloudLight/CloudOrange toward the sun, CloudPink away) with a glowing
	under-rim, then a dome of 5-7 puffs, tallest in the middle, each split
	into a warm lower half (CloudPink, or the lit tone near the sun) and a
	purple upper half (CloudPurple/SkyPurple); puffs stick out toward the
	town by different amounts so their faces catch different light. Two
	small crowns on top, a SkyTop shadow flank on the side away from the
	sun and, toward the sun, a golden glowing rim along the underside.
	About 16-20 parts.
]]
local function bank(m: Model, frame: CFrame, scale: number, warm: number, rng: Rng.Rng)
	local lit = if warm > 0.75 then C.CloudLight elseif warm > 0.45 then C.CloudOrange else C.CloudPink
	-- warm lower halves everywhere (pink, orange toward the sun), purple tops
	local lower = if warm > 0.75 then C.CloudOrange elseif warm > 0.45 then C.CloudLight else C.CloudPink
	local top = if warm > 0.6 then C.CloudPurple elseif rng:chance(0.5) then C.SkyPurple else C.CloudPurple
	local width = rng:range(100, 140) * scale
	local depth = rng:range(36, 48) * scale
	local half = width / 2
	local baseH = 6 * scale
	-- flat lit base and a glowing under-rim: the town looks up at the
	-- undersides, which the concept paints pink/orange in the sunset light
	-- (the low sun cannot reach them, so the rim glows on its own)
	Kit.box(m, frame, Vector3.new(0, baseH / 2, 0), Vector3.new(width, baseH, depth), Style.vary(lit, rng, 0.04))
	Kit.glow(
		m,
		frame * CFrame.new(rng:range(-0.06, 0.06) * width, -0.8 * scale, -depth * 0.08),
		Vector3.new(width * rng:range(0.72, 0.88), 1.6 * scale, depth * 0.8),
		if warm > 0.45 then C.CloudOrange else C.CloudPink,
		0.45 + (1 - warm) * 0.2
	)
	-- the dome of puffs
	local n = rng:int(5, 7)
	local tallest = 0
	local tallestX = 0
	for i = 1, n do
		local t = (i - 0.5) / n * 2 - 1
		local dome = math.sqrt(math.max(0.12, 1 - t * t))
		local w = width / n * rng:range(1.3, 1.7)
		local h = (12 + 28 * dome) * scale * rng:range(0.85, 1.15)
		local x = t * (half - w / 3)
		local z = rng:range(-0.22, 0.12) * depth
		local d = depth * rng:range(0.55, 0.85)
		local lowH = h * rng:range(0.58, 0.72)
		Kit.box(m, frame, Vector3.new(x, baseH + lowH / 2 - 0.5, z), Vector3.new(w, lowH, d), Style.vary(lower, rng, 0.04))
		Kit.box(
			m,
			frame,
			Vector3.new(x + rng:range(-0.1, 0.1) * w, baseH + lowH + (h - lowH) / 2 - 1, z + d * 0.06),
			Vector3.new(w * rng:range(0.75, 0.9), h - lowH, d * 0.86),
			Style.vary(top, rng, 0.04)
		)
		if h > tallest then
			tallest, tallestX = h, x
		end
	end
	-- two small crowns on the tallest part
	for k = 1, 2 do
		local w = width * rng:range(0.1, 0.16)
		local h = rng:range(6, 10) * scale
		Kit.box(
			m,
			frame,
			Vector3.new(tallestX + (k - 1.5) * w * 1.1, baseH + tallest + h / 2 - 2, rng:range(-0.1, 0.1) * depth),
			Vector3.new(w, h, depth * 0.45),
			Style.vary(if k == 1 then top else C.SkyPurple, rng, 0.04)
		)
	end
	-- SkyTop shadow flank on the side away from the sun
	local away = frame:VectorToObjectSpace(Vector3.new(0.99, 0, -0.14))
	local shadowSide = if away.X >= 0 then 1 else -1
	Kit.box(
		m,
		frame,
		Vector3.new(shadowSide * half * 0.82, baseH + tallest * 0.3, depth * 0.08),
		Vector3.new(width * 0.18, tallest * 0.55, depth * 0.7),
		Style.vary(C.SkyTop, rng, 0.05)
	)
	-- the concept's golden rims: a glowing band along the town-facing lower
	-- edge of the base, strongest toward the sun (the faces the town sees
	-- turn away from the low sun, so the rim carries the sunset light)
	if warm > 0.2 then
		Kit.glow(
			m,
			frame * CFrame.new(rng:range(-0.1, 0.1) * width, 1.1 * scale, -depth / 2 - 0.4),
			Vector3.new(width * rng:range(0.6, 0.8), 2 * scale, 0.8),
			C.CloudOrange,
			0.25 + (1 - warm) * 0.45
		)
	end
end

function Clouds.build(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	-- the footprint: Center +- Size/2 horizontally (Facing N, so axis-aligned)
	local minX, maxX = piece.Center.X - piece.Size.X / 2, piece.Center.X + piece.Size.X / 2
	local minZ, maxZ = piece.Center.Z - piece.Size.Z / 2, piece.Center.Z + piece.Size.Z / 2
	local area = LobbyLayout.Area
	for _, spot in Clouds.Spots do
		local dir = bearing(spot.Az + rng:range(-1.5, 1.5))
		local p = dir * (spot.Dist + rng:range(-20, 20))
		local margin = 105 * spot.Scale
		local x = math.clamp(p.X, minX + margin, maxX - margin)
		local z = math.clamp(p.Z, minZ + margin, maxZ - margin)
		-- never inside the lobby area box (all spots are far outside anyway)
		assert(
			x < area.Min.X - margin or x > area.Max.X + margin or z < area.Min.Z - margin or z > area.Max.Z + margin,
			"cloud cluster inside the lobby area"
		)
		local center = Vector3.new(x, spot.Y + rng:range(-4, 4), z)
		local frame = CFrame.lookAt(center, Vector3.new(0, center.Y, 0))
		local c = Style.model("Cloud", m)
		bank(c, frame, spot.Scale, sunward(spot.Az), rng)
	end
	Style.streaming(m, "Persistent")
	return m
end

return Clouds
