--[[
	Sky package: voxel cloud banks (docs/plans/LOBBY_PLAN.md 6.1 item 3,
	ART_DIRECTION section 7). Rounded voxel cumulus mounds 500-1000 studs out,
	grouped into banks and lit like the concept's sunset banks. No flat
	slabs, no long planks: every cloud block is at most ~3x as long as it is
	tall.

	Lobby fix round 2: the clouds are OPAQUE (no see-through pink glass, no
	inner faces showing over the plaza, no transparent overdraw on phones)
	and lean: a cumulus is 11 merged blocks, two-tone like the concept's
	sunset banks:
	  - three underside puffs of different sizes, each with its bottom at
	    its own height (a lumpy, stepped underside), in an opaque warm
	    sunset glow colour (GLOW_WARM toward the sun, GLOW_ROSE away);
	  - four mid domes and three smaller top domes stepped inward like a
	    pyramid in the lighter CloudPink (CloudLight toward the sun);
	  - one shoulder cube that breaks the straight top edge.
	Each cluster is turned 20-40 degrees away from the town so it shows a lit
	and a shaded face.

	Banks (Clouds.Spots, 12 clusters):
	  - the sunset bank on the west horizon beside the sun and a big low mass
	    in the north-west;
	  - low horizon banks the hero camera sees on both sides of the massif;
	  - loose high banks over the plaza, seen from the spawn: upper left, top
	    centre over the massif and upper right over the east island;
	  - one distant bank low on the south horizon (lobby_south).
	None covers a planet (Planets.luau), the airship (Airship.luau) or the
	balloon in the hero and spawn shots (tests/LobbySky.spec.luau).

	SmoothPlastic, no collision, no query, no touch, no shadow, Persistent
	streaming; all of it stays outside the lobby area box and inside the
	CloudBanks footprint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C
local WHITE = Color3.new(1, 1, 1)

type Piece = LobbyLayout.Piece

local Clouds = {}

-- the warm undersides: deep sunset orange toward the sun, a warmer rose
-- away from it (opaque SmoothPlastic, a touch of CloudPink so they read
-- as lit cloud, not as orange bricks)
-- (lobby fix round 3: the rust-brown undersides read as roof bricks: a
-- peach / coral pink glow at 0.6, the shade blocks a light lilac instead of
-- Style's CloudPurple (a local override, Style stays as it is))
local GLOW_WARM = Color3.fromRGB(255, 160, 140)
local GLOW_ROSE = Color3.fromRGB(255, 150, 160)
Clouds.Underside = {
	Warm = GLOW_WARM,
	Rose = GLOW_ROSE,
}
Clouds.Shade = Color3.fromRGB(186, 150, 226)
-- opaque bodies (round 1's 0.2 / 0.4 showed dirty pink glass), soft
-- see-through glowing skirts (round 3)
Clouds.Transparency = 0
Clouds.SkirtTransparency = 0.6
Clouds.Material = Enum.Material.SmoothPlastic
Clouds.PartsPerCloud = 11

export type Spot = { Az: number, Dist: number, Y: number, Scale: number, Skirts: boolean? }

--[[
	Cluster spots: Az = compass bearing from the plaza in degrees (0 = north
	(-Z), 270 = west (-X)), Dist = studs from the plaza, Y = base height,
	Scale. The sun sits at bearing ~262, ~13 degrees up: the west bank stays
	under it and beside it. The planets keep their windows clear (Planets.luau
	Specs), the airship flies at ~20 degrees bearing ~17 degrees up over the
	mountain and the balloon hangs at ~-27 bearing from the spawn.
]]
-- (lobby fix round 3: 8 clusters instead of 11, higher and farther out; no
-- glowing skirts on the high banks the spawn and plaza cameras look up at;
-- the spawn's upper right stays clear for the airship)
Clouds.Spots = {
	-- the sunset bank on the west horizon, beside and under the sun, and a
	-- big mass in the north-west
	{ Az = 268, Dist = 900, Y = 46, Scale = 1.2 },
	{ Az = 294, Dist = 860, Y = 120, Scale = 1.4 },
	-- the north-west horizon: a big far mound left of the hero frame
	{ Az = 330, Dist = 1100, Y = 30, Scale = 1.0 },
	-- the north-east horizon right of the massif
	{ Az = 41, Dist = 760, Y = 30, Scale = 0.6 },
	-- high banks of the spawn's sky: upper left (the top centre stays clear
	-- for the ember world)
	{ Az = 300, Dist = 760, Y = 330, Scale = 0.6, Skirts = false },
	-- one high bank far over the east (right of the airship)
	{ Az = 62, Dist = 640, Y = 300, Scale = 0.5, Skirts = false },
	-- the distant bank on the south horizon (lobby_south's empty sky)
	{ Az = 196, Dist = 700, Y = 40, Scale = 0.95 },
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
	= the side the town sees (already turned). All sizes in studs. 11 opaque
	parts: 3 warm underside puffs, 4 mid domes, 3 top domes, 1 shoulder cube.
]]
local function cumulus(m: Model, frame: CFrame, scale: number, warm: number, rng: Rng.Rng, skirts: boolean)
	local w = rng:range(120, 146) * scale
	local d = w * rng:range(0.74, 0.86)
	-- (round 3: thinner, flatter layers)
	local h = w * rng:range(0.46, 0.54)
	local mirror = if rng:chance(0.5) then 1 else -1

	-- the two tones: a warm glowing underside, light pink domes (lighter on top)
	local under = if warm > 0.3 then Clouds.Underside.Warm else Clouds.Underside.Rose
	local mid = if warm > 0.5 then C.CloudPink:Lerp(C.CloudLight, 0.45) else C.CloudPink:Lerp(WHITE, 0.12)
	local top = if warm > 0.5 then C.CloudLight else C.CloudPink:Lerp(WHITE, 0.32)

	-- a block by its bottom, in fractions: X of w, Z of d, Y (bottom) and H of h
	local function box(b: Block, color: Color3, amount: number?): Part
		local size = Vector3.new(b.W * w, b.H * h, b.D * d)
		local at = Vector3.new(b.X * w * mirror, b.Y * h + size.Y / 2, b.Z * d)
		local part = Kit.box(m, frame, at, size, Style.vary(color, rng, amount or 0.03), Clouds.Material)
		part.Transparency = Clouds.Transparency
		return part
	end
	local function jitter(b: Block): Block
		return {
			X = b.X + rng:range(-0.025, 0.025),
			Y = b.Y,
			Z = b.Z + rng:range(-0.03, 0.03),
			W = b.W * rng:range(0.92, 1.08),
			H = b.H,
			D = b.D * rng:range(0.92, 1.08),
		}
	end

	-- the underside: three merged puffs, each bottom at its own height
	local puffs: { Block } = {
		{ X = -0.22, Y = 0, Z = 0.02, W = 0.5, H = 0.3, D = 0.78 },
		{ X = 0.2, Y = 0.06, Z = -0.04, W = 0.48, H = 0.28, D = 0.72 },
		{ X = 0.02, Y = 0.12, Z = 0.12, W = 0.84, H = 0.24, D = 0.5 },
	}
	if skirts then
		for _, puff in puffs do
			local b = box(jitter(puff), under, 0.03)
			b.Name = "Underside"
			b.Transparency = Clouds.SkirtTransparency
		end
	end

	-- four mid domes and three top domes stepped inward like a pyramid; a
	-- shoulder cube breaks the straight top edge
	local domes: { Block } = {
		{ X = 0, Y = 0.22, Z = 0, W = 0.48, H = 0.32, D = 0.68 },
		{ X = -0.3, Y = 0.24, Z = 0.05, W = 0.3, H = 0.28, D = 0.56 },
		{ X = 0.3, Y = 0.22, Z = -0.04, W = 0.32, H = 0.28, D = 0.56 },
		{ X = 0.02, Y = 0.3, Z = 0.24, W = 0.6, H = 0.22, D = 0.3 },
		{ X = -0.1, Y = 0.5, Z = 0.02, W = 0.36, H = 0.22, D = 0.46 },
		{ X = 0.17, Y = 0.47, Z = -0.02, W = 0.28, H = 0.2, D = 0.4 },
		{ X = -0.02, Y = 0.66, Z = 0.03, W = 0.22, H = 0.16, D = 0.3 },
	}
	for i, dome in domes do
		-- (round 3: the lowest dome in the light lilac shade, no dark purple)
		box(jitter(dome), if i == 4 then Clouds.Shade elseif i <= 3 then mid else top)
	end
	local s = rng:range(10, 16) * scale
	box({ X = 0.3, Y = 0.46, Z = rng:range(-0.15, 0.15), W = s * 1.3 / w, H = s / h, D = s * 1.2 / d }, top, 0.04)
end

function Clouds.build(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	-- the footprint: Center +- Size/2 horizontally (Facing N, so axis-aligned)
	local minX, maxX = piece.Center.X - piece.Size.X / 2, piece.Center.X + piece.Size.X / 2
	local minZ, maxZ = piece.Center.Z - piece.Size.Z / 2, piece.Center.Z + piece.Size.Z / 2
	local area = LobbyLayout.Area
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
		local c = Style.model("Cloud", m)
		cumulus(c, frame, spot.Scale, sunward(spot.Az), rng, spot.Skirts ~= false)
	end
	Style.streaming(m, "Persistent")
	return m
end

return Clouds
