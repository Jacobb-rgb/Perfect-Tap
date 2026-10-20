--[[
	The owner-approved blasters (2026-10-17): the Kenney Blaster Kit shapes of
	the ten levels (b, c, a, j, m, g, r, p, d, e) with the "Ore Glow" skins,
	light enough for every player to hold one on a phone (the preview
	prototype is tools/lune/lib/blaster_kenney.luau: 139-408 parts a gun;
	here at most KenneyBlaster.MaxParts).

	  shape    Builders/KenneyShapes (tools/kenney/blaster_lite.py): side-profile
	           regions extruded to their width, as boxes and wedges, in the
	           kit's roles: body = the ore's matte body, light = a second body
	           tone, mid / dark = gunmetal
	  skin     Magma (hot ores and the rusty starter, CaseBuilder.HotOres): a
	           near-black body with glowing lava cracks and a glowing rim;
	           Galaxy (the other ores): a deep ore-colored body with stars and
	           a glowing outline. The rim and the pattern sit on the biggest
	           body panel and show on both sides.
	  detail   grows with the level: 4+ an ore crystal cluster on top, 7+ more
	           crystals (top, both sides) and flames / sparks around the gun,
	           10 a crown of crystals around the barrel
	  holding  the Handle is an invisible block at the hand point (Tool.Grip
	           = identity: the barrel along the arm), every part is welded to
	           it, the Muzzle attachment sits at the barrel's tip and a glowing
	           MuzzleGlow plate caps the bore (Effects/BlasterFx uses both)

	Every level is scaled to its own length (KenneyBlaster.length: ~2.2
	studs at level 1 up to ~5.9 at level 10), so the guns grow evenly.
	Pure: Instance creation only.
]]

local CaseBuilder = require(script.Parent.CaseBuilder)
local Geo = require(script.Parent.Geo)
local Shapes = require(script.Parent.KenneyShapes)

local KenneyBlaster = {}

-- the ten levels, then the five STAR blasters (Config/StarBlasterData: shape 10 + Index)
KenneyBlaster.Models = {
	"blaster-b",
	"blaster-c",
	"blaster-a",
	"blaster-j",
	"blaster-m",
	"blaster-g",
	"blaster-r",
	"blaster-p",
	"blaster-d",
	"blaster-e",
	"blaster-h",
	"blaster-l",
	"blaster-f",
	"blaster-o",
	"blaster-q",
}
KenneyBlaster.MaxParts = 90 -- per gun, every level (phones: every player holds one)
KenneyBlaster.ShortLength = 2.2 -- level 1's length (studs)
KenneyBlaster.LongLength = 5.9 -- level 10's length

-- Hand points on the grips (Kenney meters, z then y), measured from the side profiles.
KenneyBlaster.Hands = {
	["blaster-b"] = { 0.07, -0.095 },
	["blaster-c"] = { 0.13, -0.03 },
	["blaster-a"] = { 0.18, -0.14 },
	["blaster-j"] = { 0.2, -0.01 },
	["blaster-m"] = { 0.18, -0.08 },
	["blaster-g"] = { 0.24, -0.05 },
	["blaster-r"] = { 0.19, 0.02 },
	["blaster-p"] = { 0.21, -0.02 },
	["blaster-d"] = { 0.14, -0.02 },
	["blaster-e"] = { 0.97, -0.06 },
	-- the star blasters (on the rear grip's top, like the levels')
	["blaster-h"] = { 0.24, -0.07 },
	["blaster-l"] = { 0.15, -0.03 },
	["blaster-f"] = { 0.32, -0.04 },
	["blaster-o"] = { 0.115, -0.03 }, -- (on the rear grip, z 0.085-0.145)
	["blaster-q"] = { 0.25, -0.03 },
} :: { [string]: { number } }

local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local MID = Color3.fromRGB(52, 55, 64)
local DARK = Color3.fromRGB(28, 29, 34)
local SLIVER = 0.012 -- studs: thinner prims are skipped

export type Skin = {
	Magma: boolean,
	Tier: number, -- 0 (levels 1-3), 1 (4-6), 2 (7-9), 3 (10)
	Base: Color3, -- the matte body
	Second: Color3, -- the kit's light parts
	Vein: Color3, -- lava cracks
	Rim: Color3, -- the glowing outline of the main panel
	Star: Color3,
	Glow: Color3, -- muzzle, effects
	Shard: Color3, -- the crystals
	ShardTip: Color3,
}

-- A glow line: very bright colors are pulled down so neon shows its color, not white.
local function tame(c: Color3): Color3
	local luma = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return c:Lerp(BLACK, math.max(0, luma - 0.55) * 0.9)
end

function KenneyBlaster.tier(level: number): number
	return if level >= 10 then 3 elseif level >= 7 then 2 elseif level >= 4 then 1 else 0
end

--[[
	The Ore Glow skin of a level in an ore (look = BlasterBuilder.look: the
	ore's body and glow colors, Rusty for the starter).
]]
function KenneyBlaster.skin(level: number, oreId: string, look: { Body: Color3, Glow: Color3, Rusty: boolean }): Skin
	local magma = look.Rusty or CaseBuilder.HotOres[oreId] == true
	local ore, glow = look.Body, look.Glow
	local hue, sat = ore:ToHSV()
	local base = if magma then Color3.fromRGB(26, 22, 24):Lerp(ore, 0.06) else Color3.fromHSV(hue, math.max(sat, 0.25) * 0.75 + 0.2, 0.3)
	local shard = if magma then ore:Lerp(glow, 0.5) else ore:Lerp(BLACK, 0.15)
	return {
		Magma = magma,
		Tier = KenneyBlaster.tier(level),
		Base = base,
		Second = if magma then Color3.fromRGB(40, 36, 38) else Color3.fromHSV(hue, sat, 0.4),
		Vein = tame(if look.Rusty then glow:Lerp(BLACK, 0.42) else ore:Lerp(glow, 0.4)),
		Rim = tame(if magma then glow:Lerp(ore, 0.5) else glow:Lerp(ore, 0.35)),
		Star = glow:Lerp(WHITE, 0.55),
		Glow = if look.Rusty then glow:Lerp(BLACK, 0.3) else glow,
		Shard = shard,
		ShardTip = shard:Lerp(glow, 0.45),
	}
end

-- The model of a level (levels clamp to 1-10).
function KenneyBlaster.model(level: number): string
	return KenneyBlaster.Models[math.clamp(level, 1, #KenneyBlaster.Models)]
end

-- The STAR blasters' (models 11-15) held size: the envelope of the biggest level bodies
-- (LV 7 / LV 9), so a stubby Kenney shape never grows into the character (studs).
KenneyBlaster.StarFit = { Height = 2.3, Width = 1.25, Behind = 1.9 }

-- Kenney meters -> held studs for a level: every gun gets its level's length. A STAR
-- blaster gets LV 10's length unless that makes it taller, wider or longer behind the
-- hand than StarFit (bounds = z, y, x min / max).
function KenneyBlaster.scale(level: number): number
	local name = KenneyBlaster.model(level)
	local b = Shapes[name].bounds
	local t = (math.clamp(level, 1, 10) - 1) / 9
	local length = KenneyBlaster.ShortLength + (KenneyBlaster.LongLength - KenneyBlaster.ShortLength) * t
	local S = length / (b[2] - b[1])
	if level > 10 then
		local fit = KenneyBlaster.StarFit
		local behind = math.max(b[2] - KenneyBlaster.Hands[name][1], 1e-3)
		S = math.min(S, fit.Height / (b[4] - b[3]), fit.Width / (b[6] - b[5]), fit.Behind / behind)
	end
	return S
end

---------------------------------------------------------------- 2D helpers (side profile: z, y)

-- Even-odd point in a polygon with holes (loops of { z, y, z, y, ... }).
local function inside(loops: { { number } }, z: number, y: number): boolean
	local hit = false
	for _, L in loops do
		local n = #L // 2
		local j = n
		for i = 1, n do
			local zi, yi, zj, yj = L[2 * i - 1], L[2 * i], L[2 * j - 1], L[2 * j]
			if (yi > y) ~= (yj > y) and z < (zj - zi) * (y - yi) / (yj - yi) + zi then
				hit = not hit
			end
			j = i
		end
	end
	return hit
end

local function deepInside(loops: { { number } }, z: number, y: number, m: number): boolean
	return inside(loops, z, y)
		and inside(loops, z + m, y)
		and inside(loops, z - m, y)
		and inside(loops, z, y + m)
		and inside(loops, z, y - m)
end

local function area(loops: { { number } }): number
	local a = 0
	for _, L in loops do
		local n = #L // 2
		for i = 1, n do
			local j = i % n + 1
			a += L[2 * i - 1] * L[2 * j] - L[2 * j - 1] * L[2 * i]
		end
	end
	return math.abs(a / 2)
end

local function bbox(loops: { { number } }): (number, number, number, number)
	local z0, z1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, L in loops do
		for i = 1, #L, 2 do
			z0, z1 = math.min(z0, L[i]), math.max(z1, L[i])
			y0, y1 = math.min(y0, L[i + 1]), math.max(y1, L[i + 1])
		end
	end
	return z0, z1, y0, y1
end

-- A seeded random generator (every gun of a level / ore looks the same every time).
local function rng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- The right-angle corner of a WedgePart sits at local (+Z, -Y); these turn it to the other corners.
local function wedgeTurn(sz: number, sy: number): CFrame
	if sz > 0 and sy < 0 then
		return CFrame.identity
	elseif sz < 0 and sy < 0 then
		return CFrame.Angles(0, math.pi, 0)
	elseif sz > 0 then
		return CFrame.Angles(0, 0, math.pi)
	end
	return CFrame.Angles(math.pi, 0, 0)
end

---------------------------------------------------------------- the build

export type PartFn = (name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, className: string?) -> BasePart

-- Boxes, wedges and triangles of a region (x = its center, w = its width; `at` maps meters to the gun frame).
local function prims(
	list: { { any } },
	x: number,
	w: number,
	color: Color3,
	S: number,
	at: (number, number, number) -> Vector3,
	part: PartFn
)
	for _, p in list do
		local kind = p[1]
		if kind == "b" then
			local z0, z1, y0, y1 = p[2] :: number, p[3] :: number, p[4] :: number, p[5] :: number
			if (z1 - z0) * S >= SLIVER and (y1 - y0) * S >= SLIVER then
				local c = at(x, (y0 + y1) / 2, (z0 + z1) / 2)
				part("Body", CFrame.new(c), Vector3.new(w, (y1 - y0) * S, (z1 - z0) * S), color, PLASTIC)
			end
		elseif kind == "t" then
			local pz, py, az, by = p[2] :: number, p[3] :: number, p[4] :: number, p[7] :: number
			if math.abs(by - py) * S >= SLIVER and math.abs(az - pz) * S >= SLIVER then
				local c = at(x, (py + by) / 2, (pz + az) / 2)
				part(
					"Bevel",
					CFrame.new(c) * wedgeTurn(pz - az, py - by),
					Vector3.new(w, math.abs(by - py) * S, math.abs(az - pz) * S),
					color,
					PLASTIC,
					"WedgePart"
				)
			end
		else
			-- any triangle: two wedges (Geo.triangle's split, built through `part`)
			local a = at(x, p[3] :: number, p[2] :: number)
			local bb = at(x, p[5] :: number, p[4] :: number)
			local c = at(x, p[7] :: number, p[6] :: number)
			local folder = Instance.new("Folder")
			for _, wedge in Geo.triangle(folder, a, bb, c, w, color, PLASTIC) do
				part("Bevel", wedge.CFrame, wedge.Size, color, PLASTIC, "WedgePart")
			end
			folder:Destroy()
		end
	end
end

-- The gun frame of a level: its scale and the meters -> studs mapping (the hand at the origin).
local function frameOf(level: number): (Shapes.Shape, number, number, (number, number, number) -> Vector3)
	local name = KenneyBlaster.model(level)
	local shape = Shapes[name]
	local S = KenneyBlaster.scale(level)
	local hand = KenneyBlaster.Hands[name]
	local hz, hy = hand[1] * S, hand[2] * S
	local function at(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y * S - hy, z * S - hz)
	end
	return shape, S, (shape.bounds[5] + shape.bounds[6]) / 2, at
end

--[[
	A level's whole outline as one block of color (the full width): black
	rack silhouettes (the Foundry's next level). 8-23
	parts. Same frame as the gun (the hand at the origin).
]]
function KenneyBlaster.silhouette(level: number, color: Color3, part: PartFn)
	local shape, S, _, at = frameOf(level)
	local b = shape.bounds
	prims(shape.silhouette, 0, (b[6] - b[5]) * S, color, S, at, part)
end

export type Anchors = {
	Hand: Vector3, -- held studs, in the gun's frame (barrel -Z, the hand will be the Handle)
	Muzzle: Vector3,
	Top: Vector3?, -- on top of the main panel (crystals)
	Side: Vector3?, -- the main panel's side face (+X)
	BarrelY: number,
	BarrelZ: number,
	BarrelR: number,
}

--[[
	Builds the gun's parts with `part` (which welds them; frame: the barrel
	along -Z, +Y up, the hand at the origin). Returns the anchors (held studs,
	same frame) for the Muzzle.
]]
function KenneyBlaster.parts(level: number, oreId: string, skin: Skin, part: PartFn): Anchors
	local shape, S, cx, at = frameOf(level)
	local b = shape.bounds
	local hand = KenneyBlaster.Hands[KenneyBlaster.model(level)]
	local hz, hy = hand[1] * S, hand[2] * S
	local colors: { [string]: Color3 } = { body = skin.Base, light = skin.Second, mid = MID, dark = DARK }
	local main: Shapes.Region? = nil
	local mainArea = 0
	for _, region in shape.regions do
		local color = colors[region.role] or MID
		prims(region.prims, (region.c - cx) * S, region.w * S, color, S, at, part)
		if region.role == "body" then
			local a = area(region.loops)
			if a > mainArea then
				main, mainArea = region, a
			end
		end
	end

	-- the barrel's tip: the front of the gun, at the height of the front-most boxes
	local zFront = b[1]
	local sum, n = 0, 0
	for _, region in shape.regions do
		for _, p in region.prims do
			if p[1] == "b" and (p[2] :: number) <= zFront + 0.02 then
				sum += ((p[4] :: number) + (p[5] :: number)) / 2
				n += 1
			end
		end
	end
	local muzzleY = if n > 0 then sum / n else (b[3] + b[4]) / 2
	local muzzle = at(0, muzzleY, zFront)
	local anchors: Anchors = { Hand = Vector3.zero, Muzzle = muzzle, BarrelY = muzzle.Y, BarrelZ = muzzle.Z, BarrelR = 0.05 * S }
	part("MuzzleGlow", CFrame.new(muzzle + Vector3.new(0, 0, 0.03)), Vector3.new(0.05 * S, 0.05 * S, 0.04), skin.Glow, NEON)

	-- the skin on the biggest body panel: a glowing rim (the longest edges) and lava cracks / stars
	local panel = main
	if panel then
		local x = (panel.c - cx) * S
		local through = panel.w * S + 0.03 -- shows on both sides
		local loops: { { number } } = {}
		for _, L in panel.loops do
			local s: { number } = {}
			for i, v in L do
				s[i] = v * S
			end
			table.insert(loops, s)
		end
		local function strip(z0: number, y0: number, z1: number, y1: number, thick: number, color: Color3, label: string)
			local dz, dy = z1 - z0, y1 - y0
			local len = math.sqrt(dz * dz + dy * dy)
			if len < 0.05 then
				return
			end
			local mid = Vector3.new(x, (y0 + y1) / 2 - hy, (z0 + z1) / 2 - hz)
			local up = Vector3.new(0, -dz / len, dy / len)
			part(label, CFrame.fromMatrix(mid, Vector3.xAxis, up), Vector3.new(through, thick, len + thick * 0.5), color, NEON)
		end
		-- the rim: the longest outline edges, moved in a little
		local d = 0.012 * S
		local edges: { { number } } = {}
		for _, L in loops do
			local m = #L // 2
			for i = 1, m do
				local j = i % m + 1
				local z0, y0, z1, y1 = L[2 * i - 1], L[2 * i], L[2 * j - 1], L[2 * j]
				local len = math.sqrt((z1 - z0) ^ 2 + (y1 - y0) ^ 2)
				if len > d * 4 then
					table.insert(edges, { z0, y0, z1, y1, len })
				end
			end
		end
		table.sort(edges, function(e1, e2)
			return e1[5] > e2[5]
		end)
		local rimThick = (if skin.Tier == 0 then 0.016 else 0.022) * S / 4
		for k = 1, math.min(6, #edges) do
			local e = edges[k]
			local z0, y0, z1, y1, len = e[1], e[2], e[3], e[4], e[5]
			local tz, ty = (z1 - z0) / len, (y1 - y0) / len
			local nz, ny = -ty, tz
			local mz, my = (z0 + z1) / 2, (y0 + y1) / 2
			if not inside(loops, mz + nz * d * 1.5, my + ny * d * 1.5) then
				nz, ny = -nz, -ny
			end
			strip(z0 + tz * d + nz * d, y0 + ty * d + ny * d, z1 - tz * d + nz * d, y1 - ty * d + ny * d, rimThick, skin.Rim, "Rim")
		end
		-- the pattern: a few lava cracks (magma) or stars (galaxy), more with the level
		local rand = rng(level * 7919 + #oreId * 104729 + 31)
		local count = ({ 2, 3, 4, 5 })[skin.Tier + 1]
		local z0, z1, y0, y1 = bbox(loops)
		local margin = 0.04 * S / 4
		for _ = 1, count do
			local cz: number?, cy: number? = nil, nil
			for _ = 1, 40 do
				local z, y = z0 + (z1 - z0) * rand(), y0 + (y1 - y0) * rand()
				if deepInside(loops, z, y, margin) then
					cz, cy = z, y
					break
				end
			end
			if cz and cy then
				if skin.Magma then
					-- a crack: a jagged line through the point, cut where it leaves the panel
					local angle = rand() * math.pi
					local half = (0.03 + rand() * 0.04) * S
					local ez, ey = math.cos(angle) * half, math.sin(angle) * half
					local t0, t1 = -1, 1
					while t0 < -0.1 and not deepInside(loops, cz + ez * t0, cy + ey * t0, margin) do
						t0 += 0.1
					end
					while t1 > 0.1 and not deepInside(loops, cz + ez * t1, cy + ey * t1, margin) do
						t1 -= 0.1
					end
					strip(cz + ez * t0, cy + ey * t0, cz + ez * t1, cy + ey * t1, (0.024 + 0.003 * skin.Tier) * S / 4, skin.Vein, "Crack")
				else
					local s = (0.025 + rand() * 0.03) * S / 4
					part(
						"Star",
						CFrame.new(x, cy - hy, cz - hz) * CFrame.Angles(math.pi / 4, 0, 0),
						Vector3.new(through + 0.01, s, s),
						skin.Star,
						NEON
					)
				end
			end
		end
		local pz0, pz1, py0, py1 = bbox(loops)
		local zt = pz0 + (pz1 - pz0) * 0.62
		-- the top of the gun over the panel (for the crystals)
		local topY = py1
		for _, region in shape.regions do
			for _, p in region.prims do
				if p[1] == "b" and (p[2] :: number) * S <= zt and zt <= (p[3] :: number) * S then
					topY = math.max(topY, (p[5] :: number) * S)
				end
			end
		end
		anchors.Top = Vector3.new(0, topY - hy, zt - hz)
		anchors.Side = Vector3.new(x + panel.w * S / 2, (py0 + py1) / 2 - hy, pz0 + (pz1 - pz0) * 0.3 - hz)
	end

	-- the crystals: a cluster on top from level 4, crystals on both sides from 7, a crown at 10
	local function shard(base: Vector3, up: Vector3, s: number, length: number)
		local hint = if math.abs(up.X) > 0.9 then Vector3.zAxis else Vector3.xAxis
		local right = (hint - up * hint:Dot(up)).Unit
		local cf = CFrame.fromMatrix(base, right, up) * CFrame.Angles(0, math.pi / 4, 0)
		local column = length * 0.66
		part("Crystal", cf * CFrame.new(0, column / 2, 0), Vector3.new(s, column, s), skin.Shard, NEON)
		part(
			"CrystalTip",
			cf * CFrame.new(0, column + (length - column) / 2, 0),
			Vector3.new(s * 0.7, length - column, s * 0.7),
			skin.ShardTip,
			NEON
		)
	end
	local tier = skin.Tier
	local k = S / 4 -- the prototype's design studs -> this gun's studs
	local top, side = anchors.Top, anchors.Side
	if tier >= 1 and top then
		local size = (0.36 + 0.14 * tier) * k
		shard(top - Vector3.yAxis * 0.04 * k, Vector3.yAxis, size * 0.3, size)
		shard(top + Vector3.new(0, -0.04 * k, -size * 0.2), Vector3.new(0, 1, -0.75).Unit, size * 0.24, size * 0.66)
		if tier >= 2 then
			shard(top + Vector3.new(0, -0.04 * k, size * 0.18), Vector3.new(0, 1, 0.6).Unit, size * 0.2, size * 0.5)
		end
	end
	if tier >= 2 and side then
		for _, sx in { -1, 1 } do
			local p = Vector3.new(side.X * sx, side.Y, side.Z)
			local out = Vector3.new(sx, 0.5, 0).Unit
			shard(p - out * 0.04 * k, out, (0.26 + 0.06 * tier) * 0.25 * k, (0.26 + 0.06 * tier) * k)
		end
	end
	if tier >= 3 then
		-- the crown: crystals around the barrel, swept forward
		local r = anchors.BarrelR * 1.4
		for i = 0, 3 do
			local t = i / 4 * math.pi * 2 + math.pi / 4
			local o = Vector3.new(math.cos(t), math.sin(t), 0)
			local base = Vector3.new(0, anchors.BarrelY, anchors.BarrelZ + 0.35 * k) + o * r
			local dir = (o * 0.8 + Vector3.new(0, 0, -1)).Unit
			local hint = if math.abs(dir.X) > 0.9 then Vector3.zAxis else Vector3.xAxis
			local right = (hint - dir * hint:Dot(dir)).Unit
			part(
				"CrownCrystal",
				CFrame.fromMatrix(base + dir * 0.18 * k, right, dir),
				Vector3.new(0.09 * k, 0.4 * k, 0.09 * k),
				skin.ShardTip,
				NEON
			)
		end
	end
	return anchors
end

--[[
	The flames (magma) or sparks (galaxy) around the gun from level 7: one
	invisible part along the gun with a slow ParticleEmitter (GunFlame /
	GunSpark). Returns the emitter part's frame and size.
]]
function KenneyBlaster.effects(level: number): (CFrame?, Vector3?)
	if KenneyBlaster.tier(level) < 2 then
		return nil, nil
	end
	local name = KenneyBlaster.model(level)
	local shape = Shapes[name]
	local S = KenneyBlaster.scale(level)
	local b = shape.bounds
	local hand = KenneyBlaster.Hands[name]
	local center = Vector3.new(0, (b[3] + b[4]) / 2 * S - hand[2] * S, (b[1] + b[2]) / 2 * S - hand[1] * S)
	return CFrame.new(center), Vector3.new(0.4, (b[4] - b[3]) * S, (b[2] - b[1]) * S * 0.85)
end

return KenneyBlaster
