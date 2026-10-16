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
	One cloud bank, a stepped voxel cumulus. `frame` = bottom center,
	LookVector = toward the plaza. Three rows of overlapping flat blocks:
	a wide base lit warm (CloudLight/CloudOrange toward the sun, CloudPink
	away), a narrower pink row, a small purple top (CloudPurple/SkyPurple);
	SkyTop shadow blocks behind and on the side away from the sun, light
	puffs under the front edge and, toward the sun, a golden glowing rim
	along the underside. About 11-16 parts.
]]
local function bank(m: Model, frame: CFrame, scale: number, warm: number, rng: Rng.Rng)
	-- saturated shades: the Atmosphere haze at 450-900 studs washes them
	-- toward orange, so the rows step from warm to a deep purple
	local lit = if warm > 0.75 then C.CloudLight elseif warm > 0.45 then C.CloudOrange else C.CloudPink
	local middle = if warm > 0.6 then C.CloudPink elseif rng:chance(0.3) then C.CloudPink else C.CloudPurple
	local top = if warm > 0.6 then C.CloudPurple elseif rng:chance(0.5) then C.SkyPurple else C.CloudPurple
	local depth = rng:range(30, 42) * scale
	local function row(count: number, minW: number, maxW: number, minH: number, maxH: number, y: number, center: number, z: number, color: Color3): (number, number)
		local widths = {}
		local span = 0
		for i = 1, count do
			widths[i] = rng:range(minW, maxW) * scale
			span += widths[i] * (if i < count then 0.7 else 1)
		end
		local x = center - span / 2
		local tallest = 0
		for _, w in widths do
			local h = rng:range(minH, maxH) * scale
			tallest = math.max(tallest, h)
			local d = depth * rng:range(0.75, 0.95) * (1 - math.abs(z))
			Kit.box(m, frame, Vector3.new(x + w / 2, y + h / 2, depth * z + rng:range(-2, 2)), Vector3.new(w, h, d), Style.vary(color, rng, 0.04))
			x += w * 0.7
		end
		return span, tallest
	end
	-- tall rows flush at the front: from the town the bank shows one big
	-- stepped face (warm below, pink in the middle, purple on top)
	local span1, h1 = row(rng:int(3, 4), 36, 58, 11, 15, 0, 0, 0, lit)
	local c2 = rng:range(-0.15, 0.15) * span1
	local span2, h2 = row(rng:int(2, 3), 24, 44, 13, 18, h1 - 1.5, c2, -0.04, middle)
	local c3 = c2 + rng:range(-0.2, 0.2) * span2
	row(rng:int(1, 2), 16, 30, 10, 16, h1 + h2 - 3, c3, 0.02, top)
	-- SkyTop shadow: a slab behind the upper rows and a flank on the side
	-- away from the sun, so every bank shows light, mid and dark shades
	Kit.box(m, frame, Vector3.new(c2, h1 + h2 * 0.4, depth * 0.4), Vector3.new(span2 * 0.85, h2 * 0.9, depth * 0.3), Style.vary(C.SkyTop, rng, 0.04))
	local away = frame:VectorToObjectSpace(Vector3.new(0.99, 0, -0.14))
	local shadowSide = if away.X >= 0 then 1 else -1
	Kit.box(
		m,
		frame,
		Vector3.new(c2 + shadowSide * span2 * 0.44, h1 + h2 * 0.42, -depth * 0.02),
		Vector3.new(span2 * 0.2, h2 * 0.8, depth * 0.72),
		Style.vary(C.SkyTop, rng, 0.05)
	)
	-- light puffs hanging under the front edge
	for _ = 1, rng:int(1, 2) do
		local pw = span1 * rng:range(0.12, 0.2)
		Kit.box(
			m,
			frame,
			Vector3.new(rng:range(-span1 * 0.35, span1 * 0.35), -rng:range(1.2, 2.4) * scale, -depth * rng:range(0.15, 0.3)),
			Vector3.new(pw, rng:range(3.5, 5.5) * scale, depth * rng:range(0.3, 0.45)),
			Style.vary(if warm > 0.5 then C.CloudLight else C.CloudPink, rng, 0.04)
		)
	end
	-- toward the sun the underside glows like the concept's golden rims
	if warm > 0.45 then
		Kit.glow(
			m,
			frame * CFrame.new(rng:range(-0.1, 0.1) * span1, -0.3, -depth * 0.4),
			Vector3.new(span1 * rng:range(0.5, 0.7), 1.2 * scale, depth * 0.2),
			C.CloudOrange,
			0.4
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
