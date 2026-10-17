--[[
	The far ring around the map (owner 2026-10-17: "no void"):
	  OuterSea   ten sea strips from where Land.luau's sea ends (850 studs past
	             the island) out to ~3000 studs, so the sea's square edge is
	             never in view, from the heights either
	  CloudRing  low pastel cloud banks sitting on the horizon all around,
	             leaving the sunset (bearings 236-300) and the Sky package's
	             own north-west mounds (318-338) open
	Unreachable decoration, no lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Place = require(script.Parent.Place)

local C = Style.C

local Ring = {}

-- Land.luau's sea: the island box (Min.X - 6, Min.Z - 30)..(Max.X + 6,
-- Max.Z + 6) plus 850 studs on every side. Keep in step with Land.luau.
local LAND_SEA_FAR = 850
-- How far past that the outer sea reaches (each strip stays under Roblox's
-- 2048-stud part size limit).
Ring.Reach = 2000

local SUN_AZ = 262

-- Sea strips filling the frame between the inner box (the Land sea) and the
-- outer box. Returns { { min, max } }.
function Ring.seaStrips(): { { Vector3 } }
	local island = WorldLayout.Island
	local y0, y1 = Place.Sea - 2, Place.Sea
	local ix0, ix1 = island.Min.X - 6 - LAND_SEA_FAR, island.Max.X + 6 + LAND_SEA_FAR
	local iz0, iz1 = island.Min.Z - 30 - LAND_SEA_FAR, island.Max.Z + 6 + LAND_SEA_FAR
	local ox0, ox1 = ix0 - Ring.Reach, ix1 + Ring.Reach
	local oz0, oz1 = iz0 - Ring.Reach, iz1 + Ring.Reach
	local strips: { { Vector3 } } = {}
	-- north and south bands span the full width in three strips each
	for _, band in { { oz0, iz0 }, { iz1, oz1 } } do
		for i = 0, 2 do
			local xa = ox0 + (ox1 - ox0) * i / 3
			local xb = ox0 + (ox1 - ox0) * (i + 1) / 3
			table.insert(strips, { Vector3.new(xa, y0, band[1]), Vector3.new(xb, y1, band[2]) })
		end
	end
	-- west and east bands between them in two strips each
	for _, band in { { ox0, ix0 }, { ix1, ox1 } } do
		for i = 0, 1 do
			local za = iz0 + (iz1 - iz0) * i / 2
			local zb = iz0 + (iz1 - iz0) * (i + 1) / 2
			table.insert(strips, { Vector3.new(band[1], y0, za), Vector3.new(band[2], y1, zb) })
		end
	end
	return strips
end

local function outerSea(parent: Instance)
	local m = Style.model("OuterSea", parent)
	for _, strip in Ring.seaStrips() do
		local a, b = strip[1], strip[2]
		local sea = Style.block(
			m,
			CFrame.new((a + b) / 2),
			b - a,
			C.Sea,
			Enum.Material.SmoothPlastic,
			Kit.far({ Reflectance = 0.2 })
		)
		sea.Name = "Sea"
	end
end

-- 0..1: how close a bearing is to the sun's.
local function sunward(az: number): number
	local diff = math.abs(((az - SUN_AZ + 180) % 360) - 180)
	return math.clamp(1 - diff / 90, 0, 1)
end

-- An octagonal puff: a square block and its twin turned 45 degrees (from
-- any side the outline reads round). 2 parts.
local function puff(m: Model, frame: CFrame, at: Vector3, w: number, h: number, color: Color3, rng: Rng.Rng)
	local cf = frame * CFrame.new(at)
	Style.block(m, cf, Vector3.new(w, h, w), Style.vary(color, rng, 0.03), nil, Kit.far())
	Style.block(m, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.92, h * 0.94, w * 0.92), Style.vary(color, rng, 0.03), nil, Kit.far())
end

-- One low cumulus bank on the water: a wide rounded base, three mounds and
-- a crown puff, lit tops paler and warmer toward the sun. 10 parts.
local function bank(m: Model, az: number, dist: number, rng: Rng.Rng)
	local p = Place.at(az, dist, Place.Sea - 8)
	local toTown = Vector3.new(-p.X, 0, -p.Z).Unit
	local frame = CFrame.lookAt(p, p + toTown)
	local warm = sunward(az)
	local base = C.CloudPink:Lerp(C.CloudPurple, 0.45 - warm * 0.25)
	local mid = C.CloudPink:Lerp(C.CloudOrange, warm * 0.4)
	local top = C.CloudLight:Lerp(C.CloudPink, 0.35 - warm * 0.2)
	local w = rng:range(300, 420)
	local h = rng:range(22, 30)
	puff(m, frame, Vector3.new(0, h / 2, 0), w * 0.42, h, base, rng)
	for i, k in { -1, 1 } do
		local mw = w * rng:range(0.24, 0.3)
		local mh = rng:range(34, 52) * (if i == 1 then 1 else 0.85)
		puff(m, frame, Vector3.new(k * w * 0.27, mh / 2, rng:range(-12, 12)), mw, mh, if i == 1 then mid else base:Lerp(mid, 0.5), rng)
	end
	local cw = w * rng:range(0.3, 0.36)
	local ch = rng:range(56, 80)
	puff(m, frame, Vector3.new(rng:range(-20, 20), ch / 2, rng:range(-8, 8)), cw, ch, mid, rng)
	puff(m, frame, Vector3.new(rng:range(-14, 14), ch + 8, rng:range(-6, 6)), cw * 0.62, 26, top, rng)
end

local function cloudRing(parent: Instance, rng: Rng.Rng)
	local m = Style.model("CloudRing", parent)
	local az = rng:range(0, 6)
	while az < 360 do
		local open = (az > 236 and az < 300) or (az > 318 and az < 338)
		if not open then
			bank(m, az, rng:range(1250, 1500), rng)
		end
		az += rng:range(18, 24)
	end
end

function Ring.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Ring", parent)
	outerSea(m)
	cloudRing(m, rng)
	return m
end

return Ring
