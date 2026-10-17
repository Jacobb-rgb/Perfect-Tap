--[[
	Blaster proposal D "Ore Glow" (owner review 2026-10, after Hypershot skin
	references): sleeker, more realistic silhouettes (a sci-fi pistol, an
	AK-like carbine with a curved magazine and a skeleton stock, a marksman
	rifle with a suppressor) with a matte body and the ore glowing through it:

	  Magma   (hot ores, the rusty starter): a near-black body cracked into
	          plates, the cracks glow in the ore glow (lava); flames from level 7
	  Galaxy  (gem and sky ores): a deep ore-colored body with stars, soft
	          nebula spots and neon outlines along every edge; sparks from level 7

	The detail grows with the level: the rusty starter has a few dim cracks,
	from level 4 the full pattern and ore shards (Concepts.decorate), from
	level 7 particles, level 10 the densest pattern, a shard crown and gems.

	Scenes (tools/lune/export_scene.luau): "blaster_glow" (the guns floating
	in the sky), "blaster_glow_hold" (avatars holding them on the plaza).
	Shots: tools/preview/blaster_glow_shots.json. Prototype only.
]]

local roblox = require("@lune/roblox") :: any
local Concepts = require("./blaster_concepts")

local Glow = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local CF: any

local BLACK = C3.new(0, 0, 0)
local WHITE = C3.new(1, 1, 1)
local DARK = C3.fromRGB(34, 36, 42) -- rails, sights, stock bars
local GUNMETAL = C3.fromRGB(70, 74, 84) -- barrels

-- Ores whose blasters get the lava pattern (the rest get the galaxy pattern).
Glow.Magma = {
	[""] = true,
	Coal = true,
	Copper = true,
	Emberite = true,
	Ruby = true,
	Gold = true,
	Bloodstone = true,
	Solarite = true,
	Magmacore = true,
	RoyalAurum = true,
}

type Skin = {
	magma: boolean,
	tier: number,
	base: any, -- the matte body
	vein: any, -- lava cracks
	rim: any, -- the glowing rim around lava plates
	edge: any, -- galaxy outlines
	star: any,
	nebula: any,
	glow: any, -- muzzles, lenses, slots
	dark: any,
	metal: any,
	-- for Concepts.decorate
	shard: any,
	ore: any,
}

-- A body piece: a side-profile polygon (z, y) of width w, remembered for the skin pattern.
type Piece = { points: { { number } }, w: number, r: number }

local function skinFor(Loader: any, level: number, oreId: string): Skin
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local look = BlasterBuilder.look(level, oreId)
	local magma = look.Rusty or Glow.Magma[oreId] == true
	local tier = Concepts.tierOf(level)
	local ore = look.Body
	local glow = look.Glow
	-- the galaxy body: the ore's hue, deep and saturated (a night sky, not grey)
	local hue, sat = ore:ToHSV()
	local deep = C3.fromHSV(hue, math.max(sat, 0.25) * 0.75 + 0.2, 0.3)
	return {
		magma = magma,
		tier = tier,
		base = if magma then C3.fromRGB(26, 22, 24):Lerp(ore, 0.06) else deep,
		vein = if look.Rusty then glow:Lerp(BLACK, 0.42) else ore:Lerp(glow, 0.4),
		rim = glow:Lerp(ore, 0.5),
		edge = glow:Lerp(ore, 0.35),
		star = glow:Lerp(WHITE, 0.55),
		nebula = C3.fromHSV(hue, math.max(sat, 0.25) * 0.8 + 0.15, 0.62),
		glow = if look.Rusty then glow:Lerp(BLACK, 0.3) else glow,
		dark = DARK,
		metal = GUNMETAL,
		shard = if magma then ore:Lerp(glow, 0.5) else ore:Lerp(BLACK, 0.15),
		ore = ore,
	}
end

---------------------------------------------------------------- 2D helpers (side profile: { z, y })

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

local function area(points: { { number } }): number
	local a = 0
	for i = 1, #points do
		local p, q = points[i], points[i % #points + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

-- The convex polygon shrunk by d (every edge moved inward).
local function inset(points: { { number } }, d: number): { { number } }
	local n = #points
	local sign = if area(points) > 0 then 1 else -1
	local lines = {}
	for i = 1, n do
		local a, b = points[i], points[i % n + 1]
		local du, dv = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(du * du + dv * dv)
		du, dv = du / len, dv / len
		lines[i] = { a[1] - dv * sign * d, a[2] + du * sign * d, du, dv }
	end
	local out = {}
	for i = 1, n do
		local l1, l2 = lines[(i - 2) % n + 1], lines[i]
		local cross = l1[3] * l2[4] - l1[4] * l2[3]
		if math.abs(cross) < 1e-6 then
			out[i] = { l2[1], l2[2] }
		else
			local t = ((l2[1] - l1[1]) * l2[4] - (l2[2] - l1[2]) * l2[3]) / cross
			out[i] = { l1[1] + l1[3] * t, l1[2] + l1[4] * t }
		end
	end
	return out
end

local function inside(points: { { number } }, z: number, y: number): boolean
	local sign = if area(points) > 0 then 1 else -1
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		if ((b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (z - a[1])) * sign < 0 then
			return false
		end
	end
	return true
end

local function randomInside(points: { { number } }, rand: () -> number): (number, number)
	local z0, z1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		z0, z1 = math.min(z0, p[1]), math.max(z1, p[1])
		y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
	end
	for _ = 1, 60 do
		local z, y = z0 + (z1 - z0) * rand(), y0 + (y1 - y0) * rand()
		if inside(points, z, y) then
			return z, y
		end
	end
	return (z0 + z1) / 2, (y0 + y1) / 2
end

-- Clips a convex polygon of { z, y, tag } (tag = the edge from this vertex) to the side of the
-- line through m with normal n where dot(p - m, n) <= 0; the new edge gets `tag`.
local function clip(poly: { { number } }, mz: number, my: number, nz: number, ny: number, tag: number): { { number } }
	local out = {}
	local count = #poly
	for i = 1, count do
		local a, b = poly[i], poly[i % count + 1]
		local da = (a[1] - mz) * nz + (a[2] - my) * ny
		local db = (b[1] - mz) * nz + (b[2] - my) * ny
		if da <= 0 then
			table.insert(out, { a[1], a[2], a[3] })
			if db > 0 then
				local t = da / (da - db)
				table.insert(out, { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, tag })
			end
		elseif db <= 0 then
			local t = da / (da - db)
			table.insert(out, { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] })
		end
	end
	return out
end

-- The inner edges of a Voronoi split of a convex polygon into `count` plates (the lava cracks).
local function cracks(points: { { number } }, count: number, rand: () -> number): { { number } }
	local seeds = {}
	for i = 1, count do
		local z, y = randomInside(points, rand)
		seeds[i] = { z, y }
	end
	local edges = {}
	for i, si in seeds do
		local poly = {}
		for _, p in points do
			table.insert(poly, { p[1], p[2], 0 })
		end
		for j, sj in seeds do
			if j ~= i and #poly >= 3 then
				poly = clip(poly, (si[1] + sj[1]) / 2, (si[2] + sj[2]) / 2, sj[1] - si[1], sj[2] - si[2], j)
			end
		end
		for k = 1, #poly do
			local a, b = poly[k], poly[k % #poly + 1]
			if a[3] > i then
				table.insert(edges, { a[1], a[2], b[1], b[2] })
			end
		end
	end
	return edges
end

---------------------------------------------------------------- skin patterns

-- A straight strip from (z0, y0) to (z1, y1) through the whole piece (it shows on both sides).
local function strip(K: any, z0: number, y0: number, z1: number, y1: number, thick: number, w: number, color: any, transparency: number?)
	local dz, dy = z1 - z0, y1 - y0
	local len = math.sqrt(dz * dz + dy * dy)
	if len < 0.02 then
		return
	end
	local up = V3.new(0, -dz / len, dy / len)
	local p = K.part(
		"Part",
		CF.fromMatrix(V3.new(0, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(1, 0, 0), up),
		V3.new(w, thick, len + thick * 0.6),
		color,
		NEON
	)
	if transparency then
		p.Transparency = transparency
	end
end

local function pattern(K: any, skin: Skin, piece: Piece, rand: () -> number)
	local a = math.abs(area(piece.points))
	local inner = inset(piece.points, piece.r + 0.05)
	if math.abs(area(inner)) < 0.01 then
		return
	end
	local through = piece.w + 0.014
	if skin.magma then
		-- lava: the body cracks into plates inside a glowing rim; more plates with the level
		for i = 1, #inner do
			local p, q = inner[i], inner[i % #inner + 1]
			strip(
				K,
				p[1],
				p[2],
				q[1],
				q[2],
				if skin.tier == 0 then 0.016 else 0.022,
				through,
				if skin.tier == 0 then skin.vein else skin.rim
			)
		end
		local density = ({ [0] = 5, [1] = 12, [2] = 14, [3] = 17 })[skin.tier]
		local count = math.clamp(math.floor(a * density + 0.5), 2, 20)
		local base = if skin.tier == 0 then 0.024 else 0.026 + 0.003 * skin.tier
		for _, e in cracks(inner, count, rand) do
			local z0, y0, z1, y1 = e[1], e[2], e[3], e[4]
			local dz, dy = z1 - z0, y1 - y0
			local len = math.sqrt(dz * dz + dy * dy)
			local thick = base * (0.7 + rand() * 0.6)
			if len > 0.22 then
				-- a kink in the middle so the crack is not ruler straight
				local j = (rand() - 0.5) * 0.25 * len
				local mz, my = (z0 + z1) / 2 - dy / len * j, (y0 + y1) / 2 + dz / len * j
				if inside(inner, mz, my) then
					strip(K, z0, y0, mz, my, thick, through, skin.vein)
					strip(K, mz, my, z1, y1, thick * 0.85, through, skin.vein)
					continue
				end
			end
			strip(K, z0, y0, z1, y1, thick, through, skin.vein)
		end
	else
		-- galaxy: neon outlines along the edges, stars, a soft nebula spot on big pieces
		for i = 1, #inner do
			local p, q = inner[i], inner[i % #inner + 1]
			strip(K, p[1], p[2], q[1], q[2], 0.02, through, skin.edge)
		end
		local stars = math.clamp(math.floor(a * (5 + 2 * skin.tier) + 0.5), 1, 12)
		for _ = 1, stars do
			local z, y = randomInside(inner, rand)
			local s = 0.025 + rand() * 0.03
			K.boxCF(CF.new(0, y, z) * CF.Angles(math.pi / 4, 0, 0), V3.new(through + 0.004, s, s), skin.star, NEON)
		end
		if a > 0.3 then
			local spots = if skin.tier >= 2 then 2 else 1
			for _ = 1, spots do
				local z, y = randomInside(inset(inner, 0.08), rand)
				local d = 0.14 + rand() * 0.1
				K.cylCF(CF.new(0, y, z), piece.w + 0.008, d, skin.nebula, NEON).Transparency = 0.7
			end
		end
	end
end

---------------------------------------------------------------- gun designs (design frame, held studs)

local function piece(K: any, pieces: { Piece }, points: { { number } }, w: number, r: number, color: any)
	if r > 0 then
		K.rpoly(points, w, r, color)
	else
		K.prism(points, w, color)
	end
	table.insert(pieces, { points = points, w = w, r = r })
end

-- A bar between two side-profile points (stock struts), t thick, w wide.
local function bar(K: any, z0: number, y0: number, z1: number, y1: number, t: number, w: number, color: any)
	local dz, dy = z1 - z0, y1 - y0
	local len = math.sqrt(dz * dz + dy * dy)
	local up = V3.new(0, -dz / len, dy / len)
	K.part("Part", CF.fromMatrix(V3.new(0, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(1, 0, 0), up), V3.new(w, t, len + t), color)
end

local D = {}

function D.pistol(K: any, c: Skin, P: { Piece })
	piece(K, P, { { -1.28, 0.30 }, { 0.56, 0.30 }, { 0.56, 0.64 }, { 0.46, 0.76 }, { -1.14, 0.76 }, { -1.28, 0.62 } }, 0.32, 0.03, c.base)
	piece(K, P, { { -1.08, 0.32 }, { 0.50, 0.32 }, { 0.50, 0.08 }, { -0.52, 0.04 }, { -0.98, 0.08 }, { -1.08, 0.16 } }, 0.28, 0.03, c.base)
	-- compensator and glowing bore
	K.rpoly({ { -1.42, 0.40 }, { -1.26, 0.38 }, { -1.26, 0.72 }, { -1.42, 0.70 } }, 0.30, 0.03, c.dark)
	K.tube(-1.43, -1.38, 0.55, 0.12, c.glow, NEON)
	K.box(-1.18, -1.08, 0.76, 0.84, 0.06, c.dark)
	K.box(0.36, 0.50, 0.76, 0.84, 0.18, c.dark)
	piece(K, P, { { -0.02, 0.10 }, { 0.44, 0.10 }, { 0.66, -0.86 }, { 0.22, -0.92 } }, 0.30, 0.05, c.base)
	K.rpoly({ { 0.18, -0.86 }, { 0.66, -0.80 }, { 0.68, -0.94 }, { 0.20, -1.00 } }, 0.32, 0.02, c.dark)
	-- trigger guard, a glowing trigger
	K.prism({ { -0.56, 0.06 }, { -0.46, 0.06 }, { -0.40, -0.24 }, { -0.52, -0.24 } }, 0.1, c.dark)
	K.box(-0.50, 0.02, -0.26, -0.19, 0.1, c.dark)
	K.boxCF(CF.new(0, -0.06, -0.22) * CF.Angles(-0.25, 0, 0), V3.new(0.05, 0.22, 0.05), c.glow, NEON)
	return { hand = V3.new(0, -0.20, 0.28), support = V3.new(0, -0.55, 0.36), muzzle = V3.new(0, 0.55, -1.43) }
end

function D.carbine(K: any, c: Skin, P: { Piece })
	-- receiver with a ribbed dark dust cover
	piece(K, P, { { -1.30, 0.20 }, { 0.80, 0.20 }, { 0.80, 0.60 }, { 0.68, 0.72 }, { -1.16, 0.72 }, { -1.30, 0.62 } }, 0.30, 0.03, c.base)
	K.rpoly({ { -0.95, 0.70 }, { 0.62, 0.70 }, { 0.58, 0.80 }, { -0.90, 0.80 } }, 0.22, 0.03, c.dark)
	-- an angular handguard, the gas tube and the front sight over it
	piece(K, P, { { -2.55, 0.30 }, { -1.30, 0.24 }, { -1.30, 0.70 }, { -2.42, 0.68 }, { -2.55, 0.58 } }, 0.28, 0.03, c.base)
	K.tube(-2.75, -1.30, 0.80, 0.10, c.dark)
	K.prism({ { -3.02, 0.42 }, { -2.80, 0.42 }, { -2.84, 0.92 }, { -2.96, 0.92 } }, 0.12, c.dark)
	-- barrel and a slotted muzzle brake
	K.tube(-3.40, -2.50, 0.48, 0.12, c.metal, METAL)
	K.rpoly({ { -3.72, 0.36 }, { -3.36, 0.36 }, { -3.36, 0.60 }, { -3.72, 0.60 } }, 0.22, 0.05, c.dark)
	for i = 0, 2 do
		local z = -3.64 + i * 0.1
		K.box(z - 0.02, z + 0.02, 0.43, 0.53, 0.225, c.glow, NEON)
	end
	K.tube(-3.73, -3.70, 0.48, 0.09, c.glow, NEON)
	-- a low reflex sight
	K.rpoly({ { -0.55, 0.80 }, { -0.05, 0.80 }, { -0.10, 1.06 }, { -0.50, 1.06 } }, 0.22, 0.03, c.dark)
	K.box(-0.57, -0.53, 0.86, 1.0, 0.16, c.glow, NEON)
	-- a curved magazine in three angled segments
	piece(K, P, { { -0.62, 0.22 }, { -0.20, 0.22 }, { -0.24, -0.20 }, { -0.68, -0.16 } }, 0.24, 0, c.base)
	piece(K, P, { { -0.68, -0.16 }, { -0.24, -0.20 }, { -0.38, -0.58 }, { -0.82, -0.50 } }, 0.24, 0, c.base)
	piece(K, P, { { -0.82, -0.50 }, { -0.38, -0.58 }, { -0.60, -0.94 }, { -1.02, -0.80 } }, 0.24, 0, c.base)
	-- pistol grip, trigger guard
	piece(K, P, { { 0.12, 0.22 }, { 0.52, 0.22 }, { 0.72, -0.70 }, { 0.34, -0.76 } }, 0.28, 0.05, c.base)
	K.prism({ { -0.22, 0.22 }, { -0.14, 0.22 }, { -0.12, -0.20 }, { -0.20, -0.20 } }, 0.1, c.dark)
	K.box(-0.18, 0.16, -0.22, -0.15, 0.1, c.dark)
	K.boxCF(CF.new(0, 0.02, -0.02) * CF.Angles(-0.25, 0, 0), V3.new(0.05, 0.2, 0.05), c.glow, NEON)
	-- skeleton stock: two bars, a brace, a butt plate
	bar(K, 0.80, 0.62, 2.00, 0.58, 0.11, 0.22, c.dark)
	bar(K, 0.80, 0.26, 1.95, 0.04, 0.11, 0.22, c.dark)
	bar(K, 1.00, 0.30, 1.62, 0.56, 0.08, 0.20, c.dark)
	piece(K, P, { { 1.92, -0.10 }, { 2.12, -0.06 }, { 2.12, 0.72 }, { 1.92, 0.70 } }, 0.26, 0.04, c.base)
	return {
		hand = V3.new(0, -0.18, 0.36),
		support = V3.new(0, 0.26, -1.55),
		muzzle = V3.new(0, 0.48, -3.73),
		stock = V3.new(0, 0.32, 2.12),
		top = V3.new(0, 0.80, 0.30),
		side = V3.new(0.15, 0.46, -0.50),
		stockTop = V3.new(0, 0.64, 1.45),
		barrel = { z0 = -3.36, z1 = -2.60, y = 0.48, d = 0.12 },
		crown = { z = -2.62, r = 0.07 },
	}
end

function D.rifle(K: any, c: Skin, P: { Piece })
	-- receiver, lower, a long handguard with dark slots
	piece(K, P, { { -1.55, 0.22 }, { 1.05, 0.22 }, { 1.05, 0.66 }, { 0.95, 0.80 }, { -1.40, 0.80 }, { -1.55, 0.70 } }, 0.32, 0.03, c.base)
	piece(K, P, { { -0.95, 0.24 }, { 0.80, 0.24 }, { 0.80, 0.06 }, { -0.70, 0.00 }, { -0.95, 0.08 } }, 0.28, 0.03, c.base)
	piece(K, P, { { -3.45, 0.30 }, { -1.55, 0.24 }, { -1.55, 0.76 }, { -3.30, 0.76 }, { -3.45, 0.64 } }, 0.30, 0.03, c.base)
	-- barrel and a long suppressor with glowing rings
	K.tube(-3.90, -3.40, 0.50, 0.14, c.metal, METAL)
	K.tube(-4.80, -3.85, 0.50, 0.30, c.dark)
	for i = 0, 2 do
		local z = -4.6 + i * 0.25
		K.tube(z - 0.02, z + 0.02, 0.50, 0.31, c.glow, NEON)
	end
	K.tube(-4.81, -4.78, 0.50, 0.12, c.glow, NEON)
	-- top rail, scope with turrets and a glowing ring
	K.box(-1.45, 0.90, 0.80, 0.86, 0.18, c.dark)
	K.box(-0.95, -0.75, 0.84, 1.0, 0.16, c.dark)
	K.box(0.15, 0.35, 0.84, 1.0, 0.16, c.dark)
	K.tube(-1.20, 0.65, 1.10, 0.26, c.dark)
	K.tube(-1.50, -1.15, 1.10, 0.36, c.dark)
	K.tube(-1.51, -1.47, 1.10, 0.28, c.glow, NEON)
	K.tube(0.60, 0.80, 1.10, 0.30, c.dark)
	K.cylCF(CF.new(0, 1.28, -0.30) * CF.Angles(0, 0, math.pi / 2), 0.14, 0.16, c.dark)
	K.cylCF(CF.new(0.17, 1.10, -0.30), 0.12, 0.16, c.dark)
	K.tube(-0.70, -0.62, 1.10, 0.27, c.glow, NEON)
	-- box magazine, grip, trigger guard
	piece(K, P, { { -0.72, 0.06 }, { -0.28, 0.06 }, { -0.34, -0.62 }, { -0.80, -0.56 } }, 0.24, 0.03, c.base)
	piece(K, P, { { 0.22, 0.08 }, { 0.64, 0.08 }, { 0.86, -0.80 }, { 0.46, -0.86 } }, 0.28, 0.05, c.base)
	K.prism({ { -0.12, 0.06 }, { -0.04, 0.06 }, { -0.02, -0.24 }, { -0.10, -0.24 } }, 0.1, c.dark)
	K.box(-0.08, 0.26, -0.26, -0.19, 0.1, c.dark)
	K.boxCF(CF.new(0, -0.08, 0.10) * CF.Angles(-0.25, 0, 0), V3.new(0.05, 0.2, 0.05), c.glow, NEON)
	-- precision stock: cheek riser, two struts, a butt plate
	piece(K, P, { { 1.00, 0.56 }, { 2.20, 0.60 }, { 2.20, 0.86 }, { 1.10, 0.84 } }, 0.26, 0.04, c.base)
	bar(K, 1.00, 0.26, 2.15, -0.02, 0.12, 0.24, c.dark)
	bar(K, 1.20, 0.32, 1.80, 0.58, 0.09, 0.20, c.dark)
	piece(K, P, { { 2.15, -0.18 }, { 2.36, -0.14 }, { 2.36, 0.88 }, { 2.15, 0.86 } }, 0.28, 0.04, c.base)
	return {
		hand = V3.new(0, -0.18, 0.44),
		support = V3.new(0, 0.26, -1.85),
		muzzle = V3.new(0, 0.50, -4.81),
		stock = V3.new(0, 0.36, 2.36),
		top = V3.new(0, 0.76, -2.40),
		side = V3.new(0.16, 0.48, -0.30),
		stockTop = V3.new(0, 0.86, 1.62),
		barrel = { z0 = -3.84, z1 = -3.40, y = 0.50, d = 0.14 },
		crown = { z = -3.45, r = 0.08 },
	}
end

-- The effects box around the gun body (an invisible part with a ParticleEmitter).
local function effects(K: any, skin: Skin, kind: string)
	if skin.tier < 2 then
		return
	end
	local size = if kind == "rifle" then V3.new(0.5, 1.2, 4.2) else V3.new(0.5, 1.1, 3.2)
	local center = if kind == "rifle" then V3.new(0, 0.4, -0.9) else V3.new(0, 0.35, -0.6)
	local holder = K.part("Part", CF.new(center), size, skin.glow)
	holder.Transparency = 1
	holder.Name = "Effects"
	local emitter = roblox.Instance.new("ParticleEmitter")
	emitter.Name = if skin.magma then "GunFlame" else "GunSpark"
	emitter.Texture = if skin.magma
		then "rbxasset://textures/particles/fire_main.dds"
		else "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = roblox.ColorSequence.new(skin.glow)
	emitter.Parent = holder
end

local ARCHETYPE = { pistol = D.pistol, carbine = D.carbine, rifle = D.rifle }

local function archetype(level: number): string
	return if level >= 7 then "rifle" elseif level >= 4 then "carbine" else "pistol"
end

-- Builds a proposal D blaster in its design frame. Returns the model, its anchors and archetype.
function Glow.gun(Loader: any, level: number, oreId: string): (any, any, string)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local model = roblox.Instance.new("Model")
	model.Name = "Glow" .. level .. oreId
	local K = Concepts.kit(model)
	local skin = skinFor(Loader, level, oreId)
	local kind = archetype(level)
	local pieces: { Piece } = {}
	local anchors = ARCHETYPE[kind](K, skin, pieces)
	local rand = rng(level * 7919 + #oreId * 104729 + 17)
	for _, p in pieces do
		pattern(K, skin, p, rand)
	end
	-- ore shards: tips a little softer than the glow, so they keep their color
	Concepts.decorate(K, { shard = skin.shard, glow = skin.shard:Lerp(skin.glow, 0.45), ore = skin.ore }, skin.tier, anchors)
	effects(K, skin, kind)
	return model, anchors, kind
end

---------------------------------------------------------------- scenes

-- The guns of the showcase: { level, ore, display scale }.
Glow.Lineup = {
	{ 1, "", 1.9 },
	{ 4, "Amethyst", 1.45 },
	{ 7, "Emberite", 1.2 },
	{ 10, "Stormcore", 1.2 },
	{ 10, "Magmacore", 1.2 },
}

-- "blaster_glow": the lineup floating in the evening sky (no world, only the sky dome).
function Glow.build(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterGlow"
	root.Parent = parent
	local spots = {
		V3.new(-9.0, 205.2, 0),
		V3.new(0.0, 205.2, 0),
		V3.new(10.0, 205.2, 0),
		V3.new(-5.2, 200.6, 1.0),
		V3.new(6.2, 200.6, 1.0),
	}
	for i, entry in Glow.Lineup do
		local model = Glow.gun(Loader, entry[1], entry[2])
		Concepts.present(model, CF.new(spots[i]) * CF.Angles(0, -1.3, 0) * CF.Angles(0.08, 0, 0.04), entry[3], root)
	end
	-- one gun alone for close-ups (far to the side)
	for i, entry in { { 10, "Magmacore" }, { 10, "Stormcore" }, { 7, "Emberite" }, { 4, "Amethyst" } } do
		local model = Glow.gun(Loader, entry[1], entry[2])
		Concepts.present(model, CF.new(100 + i * 40, 200, 0) * CF.Angles(0, -1.25, 0) * CF.Angles(0.1, 0, 0.05), 1.5, root)
	end
	return root
end

-- "blaster_glow_hold": the world, three avatars on the plaza with the two-handed pose.
function Glow.buildHold(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	WorldBuilder.build(parent)
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterGlowHold"
	root.Parent = parent
	local K = Concepts.kit(root)
	local AIM = V3.new(1, 0, 0.3)
	for i, entry in { { 10, "Magmacore" }, { 10, "Stormcore" }, { 7, "Emberite" } } do
		local feet = V3.new(-13 + (i - 1) * 11, 0, 22)
		local model, anchors, kind = Glow.gun(Loader, entry[1], entry[2])
		Concepts.holdModel(K, root, feet, AIM, model, anchors, kind, "aim", Concepts.Outfits[i])
	end
	return root
end

-- Shared with the Kenney shape gallery (tools/lune/lib/blaster_kenney.luau).
Glow.skinFor = skinFor
Glow.cracks = cracks
Glow.rng = rng

return Glow
