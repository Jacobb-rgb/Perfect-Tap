--[[
	Sky package: voxel cloud banks (docs/plans/LOBBY_PLAN.md 6.1 item 3,
	ART_DIRECTION section 7). Puffy stacked voxel cumulus clusters 450-780
	studs out, from the west (where the sun sets) through the north-west to
	the north-east, grouped into a few cloud masses: a low bank under the
	sun, a big west-north-west mass, clusters between the planets and a few
	high ones. They frame the three planets (Planets.luau) and the airship
	instead of covering them: every cluster keeps clear of the planets'
	middles, one low bank tucks under the violet giant's lower edge.

	A cluster (19 parts) is a long belly of two blocks (a stepped
	underside), three domes on it (big, middle, small; each a body block
	under a narrower cap), a crown cube, lumps on the belly ends, front
	puffs, cubes hanging under the belly, a warm glowing underside (the town
	looks up at it; the concept paints it pink/orange in the sunset light),
	warm lower parts and purple tops, a SkyTop shade flank on the side away
	from the sun and a golden glowing rim on the side toward it. Each
	cluster is turned 20-40 degrees away from the town so it shows a lit and
	a shaded face.

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
	Scale. The sun sits at bearing ~262, ~13 degrees up: no cluster in front
	of it. The planets sit at bearings ~326 (violet, 0-20 degrees up), ~27
	(teal, 5-20 up) and ~352 (ember, 15-23 up): the middle and high clusters
	sit between and above them, the low banks below.
]]
Clouds.Spots = {
	-- low bank on the west horizon, under the sun
	{ Az = 250, Dist = 780, Y = 40, Scale = 1.3 },
	{ Az = 263, Dist = 740, Y = 22, Scale = 1.1 },
	-- the big west-north-west mass
	{ Az = 284, Dist = 620, Y = 150, Scale = 1.25 },
	{ Az = 292, Dist = 570, Y = 118, Scale = 0.95 },
	{ Az = 299, Dist = 650, Y = 178, Scale = 0.85 },
	-- tucked under the violet giant's lower left edge
	{ Az = 311, Dist = 760, Y = 18, Scale = 1.1 },
	-- north, between the violet giant and the ember world
	{ Az = 341, Dist = 610, Y = 150, Scale = 1.05 },
	{ Az = 336, Dist = 560, Y = 204, Scale = 0.7 },
	-- right of the peak, between the ember world and the teal world
	{ Az = 14, Dist = 600, Y = 170, Scale = 0.85 },
	-- north-east, behind the airship
	{ Az = 41, Dist = 480, Y = 150, Scale = 0.85 },
	{ Az = 47, Dist = 450, Y = 124, Scale = 0.7 },
	-- high clusters (seen from the ground, above the planets)
	{ Az = 302, Dist = 470, Y = 238, Scale = 0.9 },
	{ Az = 322, Dist = 500, Y = 252, Scale = 0.75 },
	{ Az = 2, Dist = 470, Y = 232, Scale = 0.8 },
	{ Az = 26, Dist = 450, Y = 244, Scale = 0.75 },
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

type Dome = { X: number, W: number, H: number, Cap: Color3 }

--[[
	One puffy cumulus. `frame` = bottom center of the belly, LookVector = the
	side the town sees (already turned). `away` = +1 or -1, the frame X side
	that faces away from the sun.
	A long belly of two blocks (the right one's bottom a little higher: a
	stepped underside), three domes on it (a big one, a middle one, a small
	one; each a body block under a narrower cap block), a crown cube on the
	big dome, lumps on the belly ends, two puffs on the front, two cubes
	hanging under the belly, a warm neon sheet under each belly block, a
	SkyTop shade flank and a golden rim toward the sun. 19 parts.
]]
local function cumulus(m: Model, frame: CFrame, scale: number, warm: number, away: number, rng: Rng.Rng)
	local width = rng:range(112, 140) * scale
	local depth = rng:range(46, 58) * scale
	local height = rng:range(48, 60) * scale
	-- warm lower parts (lighter toward the sun), purple tops
	local belly = if warm > 0.7 then C.CloudLight elseif warm > 0.4 then C.CloudOrange else C.CloudPink
	local body = if warm > 0.55 then C.CloudPink else C.CloudPink:Lerp(C.CloudPurple, 0.16)
	local shoulder = C.CloudPink:Lerp(C.CloudPurple, if warm > 0.55 then 0.5 else 0.62)
	local crown = if warm > 0.55 then C.SkyPurple else C.CloudPurple
	local mirror = if rng:chance(0.5) then 1 else -1

	-- the belly: two long blocks, the second one's bottom raised a little
	local bellyH = height * 0.24
	local bellies = {
		{ X = -0.2 * width, W = width * 0.64, H = bellyH, Lift = 0, D = depth },
		{ X = 0.22 * width, W = width * 0.56, H = bellyH * 0.82, Lift = bellyH * 0.2, D = depth * 0.9 },
	}
	for i, b in bellies do
		local x = b.X * mirror
		Kit.box(
			m,
			frame,
			Vector3.new(x, b.Lift + b.H / 2, (i - 1) * depth * 0.04),
			Vector3.new(b.W, b.H, b.D),
			Style.vary(belly, rng, 0.035)
		)
		-- the warm glowing underside: a thin neon sheet just under the block,
		-- inset from the sides (from the side it is only a thin line)
		Kit.glow(
			m,
			frame * CFrame.new(x, b.Lift - 0.05, (i - 1) * depth * 0.04),
			Vector3.new(b.W * 0.9, 0.3, b.D * 0.86),
			if warm > 0.4 then C.CloudOrange else C.CloudPink,
			0.55 + (1 - warm) * 0.1
		)
	end
	-- lumps on the belly ends break the straight edges
	for _, side in { -1, 1 } do
		local s = bellyH * rng:range(0.9, 1.2)
		Kit.box(
			m,
			frame,
			Vector3.new(side * (width * 0.5 - s * 0.2), s * 0.42, rng:range(-0.2, 0.2) * depth),
			Vector3.new(s * 1.2, s, s * 1.4),
			Style.vary(belly, rng, 0.04)
		)
	end
	-- three domes: big, middle, small
	local domes: { Dome } = {
		{ X = -0.08, W = 0.42, H = rng:range(0.74, 0.86), Cap = crown },
		{ X = 0.25, W = 0.32, H = rng:range(0.5, 0.6), Cap = shoulder },
		{ X = -0.35, W = 0.24, H = rng:range(0.36, 0.44), Cap = shoulder },
	}
	local bigTop = Vector3.zero
	for i, dome in domes do
		local x = dome.X * width * mirror + rng:range(-0.03, 0.03) * width
		local w = dome.W * width
		local h = dome.H * height
		local bodyH = h * 0.58
		local capH = h * 0.42
		local z = rng:range(-0.08, 0.04) * depth
		local y0 = bellyH * 0.9
		Kit.box(m, frame, Vector3.new(x, y0 + bodyH / 2, z), Vector3.new(w, bodyH, depth * 0.84), Style.vary(body, rng, 0.035))
		local capX = x + rng:range(-0.12, 0.12) * w
		Kit.box(
			m,
			frame,
			Vector3.new(capX, y0 + bodyH + capH / 2 - 0.4, z + depth * 0.04),
			Vector3.new(w * rng:range(0.6, 0.72), capH, depth * 0.62),
			Style.vary(dome.Cap, rng, 0.035)
		)
		if i == 1 then
			bigTop = Vector3.new(capX, y0 + bodyH + capH, z)
		end
		-- a puff on the front of the two bigger domes (relief on the face the town sees)
		if i <= 2 then
			local s = h * rng:range(0.26, 0.32)
			Kit.box(
				m,
				frame,
				Vector3.new(x + rng:range(-0.25, 0.25) * w, y0 + s * 0.55, z - depth * 0.42 - s * 0.12),
				Vector3.new(s * 1.4, s, s),
				Style.vary(body, rng, 0.04)
			)
		end
	end
	-- a crown cube on the big dome
	local cs = height * rng:range(0.14, 0.18)
	Kit.box(
		m,
		frame,
		Vector3.new(bigTop.X + rng:range(-0.06, 0.06) * width, bigTop.Y + cs / 2 - 0.4, bigTop.Z),
		Vector3.new(cs * 1.5, cs, cs * 1.3),
		Style.vary(crown, rng, 0.04)
	)
	-- cubes hanging under the belly: a lumpy underside, not a flat slab
	for k = 1, 2 do
		local s = height * rng:range(0.13, 0.17)
		local x = (if k == 1 then -1 else 1) * width * rng:range(0.1, 0.3)
		Kit.box(
			m,
			frame,
			Vector3.new(x, -s * 0.3, rng:range(-0.15, 0.15) * depth),
			Vector3.new(s * 2.2, s, s * 1.6),
			Style.vary(belly, rng, 0.04)
		)
	end
	-- SkyTop shade flank on the side away from the sun
	Kit.box(
		m,
		frame,
		Vector3.new(away * (width * 0.36), height * 0.32, depth * 0.08),
		Vector3.new(width * 0.2, height * 0.36, depth * 0.72),
		Style.vary(C.SkyTop:Lerp(C.CloudPurple, 0.35), rng, 0.04)
	)
	-- the golden rim on the side toward the sun (strongest near the sun)
	Kit.glow(
		m,
		frame * CFrame.new(-away * (width * 0.5 + 0.3), bellyH * 0.6, -depth * 0.1),
		Vector3.new(0.6, bellyH * 0.9, depth * 0.66),
		C.CloudOrange,
		0.3 + (1 - warm) * 0.4
	)
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
		local margin = 85 * spot.Scale
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
