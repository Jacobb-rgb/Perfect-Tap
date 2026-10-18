--[[
	Ore looks for the Common, Uncommon and Rare ores of the owner's ore picture
	(docs/art/ores_reference.webp, 2026-10-18): one recipe per ore, keyed by
	the ore Id (OreData Shape = Id). ItemBuilder calls register() with its
	recipe table and the kit of helpers; a recipe gets the build context `c`:
	  c.Full   true = the podium / pen display copy (more detail, <= 14 parts),
	           false = the physical clean ore (<= 8 parts)
	  c.Order  rarity order (1 Common .. 6 Mythic), c.Rng (seeded), c.Pal (colours)
	and builds in unit space: bottom centre at the origin, about 2 studs big.
	Kit: P(x,y,z) position, A(rx,ry,rz) angles, V(x,y,z) size,
	block / wedge (c, cf, size, tone), ball (c, pos, d, tone),
	cyl (c, cf, height, d, tone) along cf.UpVector, point (c, cf, size, tone)
	a cube on its corner (crystal tip), beam (c, a, b, width, tone),
	hexPrism (c, cf, radius, height, {tones}), onBall (center, d, dir, inset?).
	Tones: "Main" "Light" "Dark" "Base" "Vein" "Tip" "Neon" "NeonDark" "Glass"
	or a Color3 (see ItemBuilder.resolve).

	Budgets: the clean ore is the recipe plus an invisible Body, so a recipe
	with c.Full = false makes at most 7 parts; the display copy at most 14.
	Front = +Z, right = +X (the podium and the showcase turn the ore a little).
	Rarity: Common ores never use Neon tones ("Vein" is dull, "Tip" is the light
	shade); Uncommon ores glow faintly through "Vein"; Rare ores glow on "Tip"
	and "Vein".
]]

local OreShapesLow = {}

OreShapesLow.Ores = {
	"Coal",
	"Copper",
	"Tin",
	"Iron",
	"Quartz",
	"Oakwood",
	"Honeycomb",
	"LeafOre",
	"Frostbite",
	"Emberite",
	"Cobalt",
	"Bogwood",
	"Amber",
	"Bronze",
	"Silver",
	"Gold",
	"Jade",
	"Sapphire",
	"DragonEgg",
}

-- Extra size per ore (1 = as built), so the compact looks fill their plinth like the rest.
OreShapesLow.Scale = {
	Tin = 1.1,
	Quartz = 1.05,
	Honeycomb = 1.25,
	Frostbite = 1.05,
	Emberite = 1.12,
	Cobalt = 1.05,
	Bogwood = 1.05,
	Amber = 1.12,
	Silver = 1.2,
	Gold = 1.08,
	Jade = 1.05,
	Sapphire = 1.1,
	DragonEgg = 1.3,
} :: { [string]: number }

type Tone = string | Color3

-- typed rows for the recipe tables
type Lump = { cf: CFrame, size: Vector3, tone: Tone }
type Spike = { phi: number, r: number, tilt: number, w: number, len: number, body: Tone, tip: Tone }
type Gem = { pos: Vector3, s: number, tone: Tone }
type Ring = { r: number, y: number, s: number, count: number, start: number }

local function lump(cf: CFrame, size: Vector3, tone: Tone): Lump
	return { cf = cf, size = size, tone = tone }
end

local function spike(phi: number, r: number, tilt: number, w: number, len: number, body: Tone, tip: Tone): Spike
	return { phi = phi, r = r, tilt = tilt, w = w, len = len, body = body, tip = tip }
end

local function gem(pos: Vector3, s: number, tone: Tone): Gem
	return { pos = pos, s = s, tone = tone }
end

-- Points of a heap: rings of `count` lumps at radius r and height y (angle 0 = front).
local function heap(rings: { Ring }): { Gem }
	local list: { Gem } = {}
	for _, ring in rings do
		for k = 0, ring.count - 1 do
			local a = ring.start + k * math.pi * 2 / ring.count
			table.insert(list, gem(Vector3.new(ring.r * math.sin(a), ring.y, ring.r * math.cos(a)), ring.s, "Main"))
		end
	end
	return list
end

-- Shared colours (not ore colours: bees, leaves, moss, frost).
local BEE_YELLOW = Color3.fromRGB(255, 208, 52)
local BEE_BLACK = Color3.fromRGB(36, 30, 28)
local BEE_WING = Color3.fromRGB(232, 244, 255)
local COAL_SHINE = Color3.fromRGB(72, 72, 78)
local OAK_LEAF = Color3.fromRGB(110, 196, 60)
local OAK_LEAF_DARK = Color3.fromRGB(72, 156, 46)
local OAK_MOSS = Color3.fromRGB(92, 176, 52)
local OAK_RINGS = Color3.fromRGB(214, 168, 106)
local OAK_EDGE = Color3.fromRGB(106, 68, 40)
local BOG_LEAF = Color3.fromRGB(86, 158, 56)
local BOG_MOSS = Color3.fromRGB(56, 108, 42)
local BOG_RINGS = Color3.fromRGB(140, 104, 70)
local BOG_EDGE = Color3.fromRGB(70, 50, 32)
local FROST = Color3.fromRGB(228, 244, 255)
local COBALT_ROOT = Color3.fromRGB(30, 24, 42)
local JADE_MOSS = Color3.fromRGB(64, 132, 56)

function OreShapesLow.register(shapes: { [string]: (any) -> () }, kit: any)
	local P = kit.P :: (number, number, number) -> CFrame
	local A = kit.A :: (number, number, number) -> CFrame
	local V = kit.V :: (number, number, number) -> Vector3
	local block = kit.block
	local wedge = kit.wedge
	local ball = kit.ball
	local cyl = kit.cyl
	local point = kit.point
	local beam = kit.beam
	local hexPrism = kit.hexPrism
	local onBall = kit.onBall :: (Vector3, number, Vector3, number?) -> Vector3

	------------------------------------------------------------ local helpers

	-- Bottom centre of a crystal that stands at angle `phi` around the middle
	-- (0 = front, +Z), `r` out, leaning `tilt` outward; lifted so its lowest
	-- corner (a body `w` wide, turned 45 degrees) stays on the ground.
	local function fan(phi: number, r: number, tilt: number, w: number): CFrame
		local lift = 0.707 * w * math.sin(tilt)
		return CFrame.new(r * math.sin(phi), lift, r * math.cos(phi)) * CFrame.Angles(0, phi, 0) * CFrame.Angles(tilt, 0, 0)
	end

	-- A crystal on `base` (its bottom centre, axis = base.UpVector): a square
	-- body turned 45 degrees and a three-sided point sunk into its top (2 parts).
	local function crystal(c: any, base: CFrame, w: number, len: number, body: Tone, tip: Tone, tipSize: number?)
		local s = tipSize or w * 0.92
		block(c, base * P(0, len / 2, 0) * A(0, math.pi / 4, 0), V(w, len, w), body)
		point(c, base * P(0, len - s * 0.22, 0), s, tip)
	end

	local function spikes(c: any, list: { Spike }, count: number)
		for i = 1, math.min(count, #list) do
			local s = list[i]
			crystal(c, fan(s.phi, s.r, s.tilt, s.w), s.w, s.len, s.body, s.tip)
		end
	end

	-- A flat crystal leaf: two wedges back to back (a pointed blade, folded a
	-- little along its middle so the halves catch the light differently).
	-- base = bottom centre; the blade's face looks along base.LookVector's opposite (+Z).
	local function blade(c: any, base: CFrame, halfWidth: number, height: number, thick: number, fold: number, a: Tone, b: Tone)
		local mid = base * P(0, height / 2, 0) * A(0, math.pi / 2, 0)
		local size = V(thick, height, halfWidth)
		wedge(c, mid * A(0, fold, 0) * P(0, 0, -halfWidth / 2), size, a)
		wedge(c, mid * A(0, math.pi - fold, 0) * P(0, 0, -halfWidth / 2), size, b)
	end

	-- A chunky faceted rock: a block and the same block turned 45 degrees (2 parts).
	local function rock(c: any, pos: Vector3, s: number, turn: number, tone: Tone, facet: Tone)
		local cf = CFrame.new(pos) * A(0.2 * math.sin(turn * 3), turn, 0.18 * math.cos(turn * 2))
		block(c, cf, V(s, s * 0.8, s * 0.92), tone)
		block(c, cf * A(0.3, math.pi / 4, 0.25), V(s * 0.88, s * 0.86, s * 0.84), facet)
	end

	-- A cave bee resting beside a gem (head toward -X of cf). parts: 3 = body,
	-- stripe and a wing (clean ore), 4 = + head, 6 = + a second stripe and wing.
	local function bee(c: any, cf: CFrame, parts: number)
		ball(c, cf.Position, 0.4, BEE_YELLOW)
		cyl(c, cf * P(0.03, 0, 0) * A(0, 0, -math.pi / 2), 0.08, 0.41, BEE_BLACK)
		local wingA = block(c, cf * P(0.04, 0.22, 0.1) * A(0.55, 0.2, 0.35), V(0.34, 0.025, 0.19), BEE_WING)
		wingA.Transparency = 0.2
		if parts >= 4 then
			ball(c, (cf * P(-0.22, 0.04, 0)).Position, 0.22, BEE_BLACK)
		end
		if parts >= 6 then
			cyl(c, cf * P(0.13, 0, 0) * A(0, 0, -math.pi / 2), 0.07, 0.36, BEE_BLACK)
			local wingB = block(c, cf * P(0.04, 0.22, -0.1) * A(-0.55, -0.2, 0.35), V(0.34, 0.025, 0.19), BEE_WING)
			wingB.Transparency = 0.2
		end
	end

	-- A six-sided crystal: a hexagonal prism (3 parts) with a point whose three
	-- upper corners sit on the prism's rim (1 part). cf = the prism's centre.
	local function hexCrystal(c: any, cf: CFrame, r: number, h: number, tones: { Tone }, tip: Tone)
		hexPrism(c, cf, r, h, tones)
		local s = r * 1.2
		point(c, cf * P(0, h / 2 - s * 0.24, 0), s, tip)
	end

	-- A flame-like shard: a slab with a slanted wedge tip (2 parts); the tip's
	-- high edge is on base's -Z side.
	local function shard(c: any, base: CFrame, w: number, d: number, len: number, tipLen: number, body: Tone, tip: Tone)
		block(c, base * P(0, len / 2, 0), V(w, len, d), body)
		wedge(c, base * P(0, len + tipLen / 2, 0) * A(0, math.pi, 0), V(w, tipLen, d), tip)
	end

	-- A cylinder disc lying on a surface, its axis along `normal` (carvings, eyes).
	local function disc(c: any, pos: Vector3, normal: Vector3, height: number, d: number, tone: Tone)
		local n = normal.Unit
		cyl(c, CFrame.lookAt(pos, pos + n) * A(-math.pi / 2, 0, 0), height, d, tone)
	end

	-- A small leaf: a thin square turned so a corner points along the leaf (1 part).
	local function leaf(c: any, cf: CFrame, len: number, tone: Tone)
		block(c, cf * A(0, math.pi / 4, 0), V(len * 0.62, 0.05, len * 0.62), tone)
	end

	-- A six-armed snowflake facing the front (3 parts).
	local function snowflake(c: any, center: Vector3, len: number)
		for k = 0, 2 do
			block(c, CFrame.new(center) * A(0, 0, k * math.pi / 3), V(len, 0.05, 0.05), FROST)
		end
	end

	-- An eight-sided log along cf.UpVector (cf = its middle) with a light cut end
	-- at +Y: 3 parts.
	local function log8(c: any, cf: CFrame, len: number, d: number, tone: Tone, edge: Tone, rings: Color3)
		block(c, cf, V(d, len, d), tone)
		block(c, cf * A(0, math.pi / 4, 0), V(d, len - 0.04, d), edge)
		cyl(c, cf * P(0, len / 2, 0), 0.05, d * 0.94, rings)
	end

	------------------------------------------------------------ Common

	-- Coal: a dome of glossy black faceted lumps.
	shapes.Coal = function(c)
		local lumps = heap({
			{ r = 0, y = 0.48, s = 0.74, count = 1, start = 0 },
			{ r = 0.36, y = 0.72, s = 0.5, count = 3, start = 0.5 },
			{ r = 0, y = 1.12, s = 0.46, count = 1, start = 0 },
			{ r = 0.62, y = 0.24, s = 0.5, count = 6, start = 0.25 },
			{ r = 0.22, y = 0.98, s = 0.4, count = 2, start = 2.2 },
		})
		-- the clean ore keeps the core, the middle ring, the top and the front of the bottom ring
		local keep: { number } = if c.Full then { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } else { 1, 2, 3, 4, 5, 6, 10 }
		local tones: { Tone } = { "Main", "Dark", COAL_SHINE }
		for _, i in keep do
			local g = lumps[i]
			local cf = CFrame.new(g.pos) * A(0.5 + 0.3 * math.sin(i * 1.7), i * 1.13, 0.4 + 0.25 * math.cos(i * 2.3))
			-- every other lump stands on a corner: more facets, less "box"
			local spec = if i % 2 == 0
				then point(c, cf, g.s * 0.8, tones[i % 3 + 1])
				else block(c, cf, V(g.s, g.s * 0.84, g.s * 0.92), tones[i % 3 + 1])
			spec.Reflectance = 0.1 -- glossy coal
		end
	end

	-- Copper: a wide, low heap of small orange-brown faceted nuggets.
	shapes.Copper = function(c)
		local nuggets = heap({
			{ r = 0, y = 0.74, s = 0.42, count = 1, start = 0 },
			{ r = 0.32, y = 0.46, s = 0.44, count = 3, start = 0.3 },
			{ r = 0.7, y = 0.2, s = 0.42, count = 7, start = 0.1 },
		})
		table.insert(nuggets, gem(V(1.04, 0.07, 0.46), 0.16, "Main"))
		table.insert(nuggets, gem(V(-0.92, 0.07, 0.66), 0.14, "Main"))
		local keep: { number } = if c.Full then { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } else { 1, 2, 3, 4, 5, 7, 10 }
		local tones: { Tone } = { "Main", "Light", "Main", "Dark" }
		for _, i in keep do
			local g = nuggets[i]
			local tone = tones[i % 4 + 1]
			-- two of three nuggets stand on a corner (gem-like facets)
			local spec = if i % 3 ~= 0
				then point(c, CFrame.new(g.pos + V(0, 0.03, 0)) * A(0.35 * math.sin(i), i * 1.37, 0.3 * math.cos(i)), g.s * 0.84, tone)
				else block(c, CFrame.new(g.pos) * A(0.6, i * 1.37, 0.45), V(g.s, g.s * 0.82, g.s * 0.9), tone)
			spec.Reflectance = 0.05 -- a soft sheen: no sun glints that could pass for a glow
		end
	end

	-- Tin: pale silver cubes grown on top of each other.
	shapes.Tin = function(c)
		local cubes = {
			lump(P(0.24, 0.36, -0.2) * A(0, 0.3, 0), V(0.72, 0.72, 0.72), "Main"),
			lump(P(0.14, 1.0, -0.24) * A(0.06, 0.62, -0.05), V(0.6, 0.6, 0.6), "Light"),
			lump(P(-0.46, 0.3, 0.06) * A(0, -0.22, 0.04), V(0.6, 0.6, 0.6), "Light"),
			lump(P(0.62, 0.22, 0.44) * A(0, 0.78, 0), V(0.44, 0.44, 0.44), "Main"),
			lump(P(-0.06, 0.17, 0.58) * A(0, 0.15, 0), V(0.34, 0.34, 0.34), "Light"),
			-- display only
			lump(P(-0.58, 0.78, -0.3) * A(0.05, 0.4, 0.06), V(0.38, 0.38, 0.38), "Main"),
			lump(P(-0.62, 0.11, 0.6) * A(0, 0.6, 0), V(0.22, 0.22, 0.22), "Main"),
			lump(P(0.86, 0.1, -0.12) * A(0, 0.2, 0), V(0.2, 0.2, 0.2), "Light"),
			lump(P(0.62, 0.45, 0.44) * A(0, 0.78, 0), V(0.38, 0.03, 0.38), "Light"),
			lump(P(0.24, 0.73, -0.2) * A(0, 0.3, 0), V(0.62, 0.03, 0.62), "Light"),
		}
		for i = 1, if c.Full then #cubes else 5 do
			local q = cubes[i]
			local spec = block(c, q.cf, q.size, q.tone)
			spec.Reflectance = 0.05 -- a soft sheen, no sun glare on the pale metal
		end
	end

	-- Iron: one heavy grey block with a groove on top and darker faces.
	shapes.Iron = function(c)
		local m = P(0, 0.5, 0) * A(0.06, 0.4, 0.1)
		local function slab(cf: CFrame, size: Vector3, tone: Tone)
			local spec = block(c, cf, size, tone)
			spec.Reflectance = 0.05 -- a soft sheen, no sun glare
		end
		slab(m, V(1.5, 0.8, 1.0), "Main")
		slab(m * P(0.02, 0.48, -0.27), V(1.36, 0.18, 0.4), "Light")
		slab(m * P(-0.08, 0.48, 0.3), V(1.18, 0.18, 0.34), "Light")
		slab(m * P(0, 0.41, 0.02), V(1.3, 0.04, 0.3), "Dark")
		slab(m * P(0.76, -0.04, 0.02), V(0.04, 0.62, 0.8), "Dark")
		slab(m * P(0.3, -0.1, 0.51), V(0.6, 0.4, 0.04), "Dark")
		slab(m * P(-0.62, 0.52, 0.0) * A(0, 0, 0.3), V(0.38, 0.3, 0.9), "Light")
		if c.Full then
			slab(P(0.72, 0.2, 0.42) * A(0.1, 0.9, 0.15), V(0.5, 0.42, 0.46), "Dark")
			slab(P(0.72, 0.42, 0.42) * A(0.1, 0.9, 0.15), V(0.4, 0.04, 0.36), "Light")
			slab(m * P(0.5, 0.48, 0.02) * A(0, 0.1, 0), V(0.16, 0.16, 0.5), "Light")
			point(c, P(-0.82, 0.1, 0.5) * A(0.4, 0.7, 0.3), 0.22, "Main")
			point(c, P(-0.3, 0.08, 0.72) * A(0.2, 1.4, 0.6), 0.17, "Dark")
		end
	end

	-- Quartz: white crystal spikes fanning out to the sides.
	shapes.Quartz = function(c)
		local list = {
			spike(0.0, 0.0, 0.06, 0.38, 1.45, "Light", "Tip"),
			spike(-1.45, 0.22, 0.42, 0.32, 1.15, "Main", "Tip"),
			spike(1.5, 0.22, 0.46, 0.31, 1.08, "Main", "Tip"),
			spike(-2.5, 0.2, 0.3, 0.28, 0.98, "Light", "Tip"),
			spike(2.35, 0.2, 0.34, 0.27, 1.2, "Main", "Tip"),
			spike(-1.1, 0.42, 0.88, 0.24, 0.7, "Light", "Tip"),
			spike(1.05, 0.42, 0.92, 0.23, 0.62, "Light", "Tip"),
		}
		spikes(c, list, if c.Full then 7 else 3)
		if not c.Full then
			point(c, P(0.1, 0.12, 0.5) * A(0.5, 0.4, 0.3), 0.24, "Light")
		end
	end

	-- Oakwood: a short eight-sided log lying on its side, moss on top, leaves around.
	shapes.Oakwood = function(c)
		-- the log's axis runs to the right and back, rising; its local -X is "up"
		local log = P(0, 0.44, 0) * A(0, 0.5, 0) * A(0, 0, -1.22)
		local function top(along: number, side: number): Vector3
			return (log * P(-0.36, along, side)).Position
		end
		log8(c, log, 1.66, 0.7, "Main", OAK_EDGE, OAK_RINGS)
		-- a moss blanket on top with soft lumps
		block(c, log * P(-0.32, 0.02, 0), V(0.2, 1.3, 0.56), OAK_MOSS)
		ball(c, top(0.34, 0.08), 0.54, OAK_MOSS)
		local leaves = {
			lump(P(-0.66, 0.12, 0.44) * A(0.4, 0.4, 0.3), V(0.44, 0, 0), OAK_LEAF),
			lump(P(0.62, 1.04, -0.42) * A(0.8, 0.2, -0.6), V(0.42, 0, 0), OAK_LEAF),
			-- display only
			lump(P(0.56, 0.12, 0.5) * A(-0.4, 1.1, 0.4), V(0.42, 0, 0), OAK_LEAF_DARK),
			lump(P(-0.24, 0.12, -0.6) * A(-0.4, 2.2, 0.3), V(0.42, 0, 0), OAK_LEAF_DARK),
			lump(P(0.9, 0.84, -0.12) * A(-0.6, 0.8, 0.9), V(0.36, 0, 0), OAK_LEAF),
			lump(P(-0.94, 0.3, 0.06) * A(0.3, 2.6, -1.0), V(0.38, 0, 0), OAK_LEAF),
		}
		for i = 1, if c.Full then #leaves else 2 do
			local l = leaves[i]
			leaf(c, l.cf, l.size.X, l.tone)
		end
		if c.Full then
			ball(c, top(-0.3, -0.06), 0.42, OAK_LEAF_DARK)
			ball(c, top(0.7, 0.12), 0.32, OAK_LEAF)
			cyl(c, log * P(0, 0.84, 0), 0.06, 0.26, OAK_EDGE)
		end
	end

	-- Honeycomb: a six-sided golden chunk of honey with its cells on the front, a bee on top.
	shapes.Honeycomb = function(c)
		local r, h = 0.6, 0.66
		-- lying on a flat side, its cell face turned to the front and a little up
		local comb = P(-0.1, 0.6, 0) * A(0, -0.35, 0) * A(math.pi / 2 - 0.3, 0, 0)
		hexPrism(c, comb, r, h, { "Main", "Light", "Main" })
		local cells = { V(0, 0, 0) }
		for k = 0, 5 do
			local a = k * math.pi / 3 + math.pi / 6
			table.insert(cells, V(0.31 * math.cos(a), 0, 0.31 * math.sin(a)))
		end
		for i = 1, if c.Full then 7 else 1 do
			cyl(c, comb * P(cells[i].X, h / 2, cells[i].Z), 0.08, 0.25, "Dark")
		end
		bee(c, P(0.5, 1.14, 0.06) * A(0, -0.5, 0.12), if c.Full then 4 else 3)
	end

	------------------------------------------------------------ Uncommon

	-- Leaf Ore: broad green crystal leaves fanning out from one root.
	shapes.LeafOre = function(c)
		local blades = {
			{ base = fan(0.15, 0, 0.1, 0.2), hw = 0.4, h = 1.35, a = "Light", b = "Main" },
			{ base = fan(-1.2, 0.14, 0.62, 0.2), hw = 0.38, h = 1.1, a = "Main", b = "Dark" },
			{ base = fan(1.25, 0.14, 0.66, 0.2), hw = 0.37, h = 1.05, a = "Light", b = "Main" },
			{ base = fan(-2.5, 0.12, 0.5, 0.2), hw = 0.34, h = 1.0, a = "Main", b = "Light" },
			{ base = fan(2.4, 0.12, 0.55, 0.2), hw = 0.33, h = 0.95, a = "Dark", b = "Main" },
			{ base = fan(-0.1, 0.24, 0.9, 0.2), hw = 0.3, h = 0.7, a = "Light", b = "Main" },
		}
		for i = 1, if c.Full then #blades else 3 do
			local bl = blades[i]
			blade(c, bl.base, bl.hw, bl.h, 0.2, 0.42, bl.a, bl.b)
		end
		-- small leaves at the root, glowing faintly
		wedge(c, fan(-0.75, 0.5, 1.05, 0.1) * P(0, 0.2, 0), V(0.1, 0.4, 0.26), "Vein")
		if c.Full then
			wedge(c, fan(0.85, 0.5, 1.1, 0.1) * P(0, 0.18, 0) * A(0, math.pi, 0), V(0.1, 0.36, 0.24), "Vein")
		end
	end

	-- Frostbite: light-blue ice crystals with snowflakes around them.
	shapes.Frostbite = function(c)
		crystal(c, P(0.04, 0, -0.04) * A(0, 0.3, -0.1), 0.54, 1.35, "Main", "Vein", 0.52)
		local list = {
			spike(-1.2, 0.28, 0.5, 0.36, 0.85, "Light", FROST),
			spike(1.4, 0.3, 0.55, 0.33, 0.75, "Light", FROST),
			spike(2.6, 0.22, 0.35, 0.32, 0.95, "Main", FROST),
		}
		spikes(c, list, if c.Full then 3 else 2)
		if c.Full then
			snowflake(c, V(0.72, 1.42, 0.14), 0.42)
			snowflake(c, V(-0.68, 1.18, 0.12), 0.32)
		else
			point(c, P(0.36, 0.1, 0.5) * A(0.4, 0.6, 0.2), 0.2, FROST)
		end
	end

	-- Emberite: a heap of red flame-shaped shards, their tips glowing.
	shapes.Emberite = function(c)
		local rocks = {
			lump(P(-0.36, 0.22, 0.12) * A(0.4, 0.5, 0.3), V(0.56, 0.46, 0.52), "Dark"),
			lump(P(0.38, 0.2, 0.06) * A(-0.3, 1.2, 0.35), V(0.52, 0.44, 0.5), "Main"),
			lump(P(0.02, 0.2, -0.38) * A(0.3, 2.0, -0.3), V(0.5, 0.42, 0.48), "Dark"),
		}
		for i = 1, if c.Full then 3 else 1 do
			local l = rocks[i]
			block(c, l.cf, l.size, l.tone)
		end
		local shards = {
			{ base = fan(0.3, 0.02, 0.06, 0.4), w = 0.42, d = 0.36, len = 0.72, tip = 0.5, body = "Main", glow = "Vein" },
			{ base = fan(-1.3, 0.3, 0.45, 0.34), w = 0.36, d = 0.3, len = 0.48, tip = 0.42, body = "Light", glow = "Main" },
			{ base = fan(1.25, 0.32, 0.5, 0.34), w = 0.34, d = 0.3, len = 0.42, tip = 0.4, body = "Main", glow = "Vein" },
			{ base = fan(2.9, 0.26, 0.35, 0.32), w = 0.34, d = 0.3, len = 0.58, tip = 0.42, body = "Dark", glow = "Light" },
			{ base = fan(0.45, 0.42, 0.72, 0.28), w = 0.3, d = 0.26, len = 0.26, tip = 0.32, body = "Light", glow = "Vein" },
		}
		for i = 1, if c.Full then 5 else 3 do
			local s = shards[i]
			shard(c, s.base, s.w, s.d, s.len, s.tip, s.body, s.glow)
		end
		if c.Full then
			point(c, P(-0.22, 1.18, -0.06) * A(-0.1, 1.3, 0.2), 0.16, "Vein")
		end
	end

	-- Cobalt: dark blue-violet crystals on black roots that curl out glowing.
	shapes.Cobalt = function(c)
		block(c, P(0, 0.14, 0) * A(0, 0.3, 0), V(1.1, 0.28, 0.92), COBALT_ROOT)
		crystal(c, P(-0.05, 0.12, 0) * A(0, 0.4, 0) * A(0, 0, -0.32), 0.52, 1.05, "Main", "Light")
		crystal(c, P(-0.3, 0.12, -0.12) * A(0, 1.0, 0) * A(0, 0, 0.18), 0.42, 0.95, "Dark", "Main")
		if c.Full then
			crystal(c, P(0.32, 0.12, 0.22) * A(0, 0.2, 0) * A(0, 0, -0.72), 0.38, 0.72, "Light", "Main")
			point(c, P(-0.1, 0.3, 0.46) * A(0.5, 0.4, 0.3), 0.26, "Dark")
		end
		local roots = {
			{ V(-0.42, 0.22, 0.14), V(-0.86, 0.5, 0.22), V(-0.74, 0.98, 0.14) },
			{ V(0.48, 0.22, -0.18), V(0.9, 0.36, -0.08), V(0.98, 0.74, 0.12) },
			{ V(-0.22, 0.26, -0.36), V(-0.36, 0.82, -0.6), V(-0.12, 1.22, -0.52) },
		}
		for i = 1, if c.Full then 3 else 1 do
			local root = roots[i]
			beam(c, root[1], root[2], 0.12, "Vein")
			beam(c, root[2], root[3], 0.09, "Vein")
		end
	end

	-- Bogwood: a dark swamp log standing steep, thick moss, a glowing vine and drips.
	shapes.Bogwood = function(c)
		-- the log's axis rises steeply to the right and back; its local -X is "up"
		local log = P(0, 0.78, 0) * A(0, 0.5, 0) * A(0, 0, -0.78)
		log8(c, log, 1.6, 0.76, "Main", BOG_EDGE, BOG_RINGS)
		ball(c, (log * P(-0.2, 0.72, 0.04)).Position, 0.56, BOG_MOSS)
		local R = 0.5
		local vine = {
			(log * P(R * math.cos(0.4), -0.62, R * math.sin(0.4))).Position,
			(log * P(R * math.cos(1.2), -0.32, R * math.sin(1.2))).Position,
			(log * P(R * math.cos(2.0), -0.02, R * math.sin(2.0))).Position,
			(log * P(R * math.cos(2.8), 0.3, R * math.sin(2.8))).Position,
		}
		for i = 1, if c.Full then 3 else 1 do
			beam(c, vine[i], vine[i + 1], 0.12, "Vein")
		end
		local leaves = {
			lump(P(0.66, 1.5, -0.3) * A(0.6, 0.3, -0.8), V(0.44, 0, 0), BOG_LEAF),
			lump(P(-0.68, 0.12, 0.34) * A(0.4, 0.6, 0.4), V(0.44, 0, 0), BOG_LEAF),
			-- display only
			lump(P(0.34, 1.62, -0.16) * A(-0.6, 1.2, 0.9), V(0.38, 0, 0), BOG_LEAF),
			lump(P(0.46, 0.12, 0.5) * A(0.4, -0.6, -0.35), V(0.4, 0, 0), BOG_MOSS),
		}
		for i = 1, if c.Full then 4 else 2 do
			local l = leaves[i]
			leaf(c, l.cf, l.size.X, l.tone)
		end
		if c.Full then
			ball(c, (log * P(-0.3, 0.16, -0.08)).Position, 0.42, BOG_MOSS)
			local drip = (log * P(0.42, 0.12, 0.14)).Position
			beam(c, drip, drip - V(0, 0.38, 0), 0.07, BOG_MOSS)
			local drip2 = (log * P(0.42, -0.3, -0.16)).Position
			beam(c, drip2, drip2 - V(0, 0.28, 0), 0.06, BOG_MOSS)
		end
	end

	-- Amber: a fat six-sided golden drop with a pointed top, light leaking out of it, a bee resting on it.
	shapes.Amber = function(c)
		local base = P(-0.1, 0, 0) * A(0, 0.25, 0)
		if c.Full then
			hexCrystal(c, base * P(0, 0.46, 0), 0.56, 0.92, { "Main", "Light", "Main" }, "Light")
			-- a glowing heart that shows as a seam down the front and back facets
			block(c, base * P(0, 0.46, 0), V(0.34, 0.84, 1.02), "Vein")
			point(c, P(-0.76, 0.1, 0.42) * A(0.3, 0.5, 0.2), 0.22, "Light")
			point(c, P(-0.34, 0.08, 0.7) * A(0.2, 1.2, 0.4), 0.16, "Main")
			point(c, P(0.38, 0.08, 0.7) * A(0.4, 0.3, 0.6), 0.14, "Light")
			bee(c, P(0.54, 0.72, 0.38) * A(0, -0.7, 0.1), 6)
		else
			crystal(c, base, 0.74, 0.84, "Main", "Light", 0.7)
			block(c, base * P(0, 0.42, 0), V(0.4, 0.8, 0.86), "Vein")
			bee(c, P(0.46, 0.66, 0.36) * A(0, -0.7, 0.1), 3)
			point(c, P(-0.62, 0.1, 0.4) * A(0.3, 0.5, 0.2), 0.18, "Light")
		end
	end

	------------------------------------------------------------ Rare

	-- Bronze: big brown faceted rocks with glowing glints.
	shapes.Bronze = function(c)
		local rocks = {
			gem(V(0.02, 0.86, -0.06), 0.74, "Main"),
			gem(V(-0.52, 0.36, 0.1), 0.7, "Dark"),
			gem(V(0.52, 0.38, 0.0), 0.72, "Main"),
			gem(V(0.06, 0.32, 0.5), 0.6, "Dark"),
			gem(V(0.08, 0.34, -0.52), 0.62, "Main"),
		}
		for i = 1, if c.Full then 5 else 3 do
			local g = rocks[i]
			rock(c, g.pos, g.s, i * 1.1, g.tone, if g.tone == "Dark" then "Main" else "Light")
		end
		point(c, P(0.12, 1.2, 0.1) * A(0.2, 0.5, 0.1), 0.16, "Tip")
		if c.Full then
			point(c, P(0.66, 0.66, 0.16) * A(0.3, 1.1, -0.2), 0.14, "Tip")
			point(c, P(-0.76, 0.1, 0.56) * A(0.4, 0.6, 0.3), 0.22, "Main")
			point(c, P(0.72, 0.08, 0.52) * A(0.2, 1.3, 0.5), 0.18, "Light")
		end
	end

	-- Silver: a tall six-sided silver column with spikes around it.
	shapes.Silver = function(c)
		if c.Full then
			hexCrystal(c, P(0, 0.64, 0) * A(0, 0.2, 0.03), 0.3, 1.28, { "Main", "Light", "Dark" }, "Tip")
		else
			crystal(c, CFrame.new(), 0.48, 1.28, "Main", "Tip", 0.44)
		end
		local list = {
			spike(-0.95, 0.3, 0.34, 0.29, 1.0, "Light", "Tip"),
			spike(1.05, 0.3, 0.4, 0.28, 0.9, "Main", "Light"),
			spike(-2.2, 0.28, 0.3, 0.27, 1.1, "Main", "Light"),
			spike(2.3, 0.28, 0.34, 0.26, 0.95, "Light", "Tip"),
		}
		spikes(c, list, if c.Full then 4 else 2)
		point(c, P(-0.42, 0.12, 0.5) * A(0.4, 0.6, 0.5), 0.24, "Light")
		if c.Full then
			point(c, P(0.45, 0.1, 0.48) * A(0.3, 1.4, 0.2), 0.2, "Main")
		end
	end

	-- Gold: a fat golden column, smaller points leaning out, nuggets at its foot.
	shapes.Gold = function(c)
		if c.Full then
			hexCrystal(c, P(-0.06, 0.5, 0) * A(0.04, 0.3, 0.06), 0.42, 1.0, { "Main", "Light", "Dark" }, "Light")
		else
			crystal(c, P(-0.06, 0, 0) * A(0.04, 0.3, 0.06), 0.68, 1.0, "Main", "Light", 0.62)
		end
		local list = {
			spike(1.35, 0.42, 0.5, 0.34, 0.8, "Light", "Light"),
			spike(-1.4, 0.4, 0.45, 0.3, 0.62, "Main", "Tip"),
			spike(2.4, 0.3, 0.35, 0.3, 0.95, "Dark", "Light"),
			spike(-2.3, 0.3, 0.5, 0.24, 0.55, "Light", "Tip"),
		}
		spikes(c, list, if c.Full then 4 else 2)
		point(c, P(-0.32, 0.15, 0.52) * A(0.4, 0.5, 0.3), 0.3, "Light")
		if c.Full then
			point(c, P(0.36, 0.12, 0.56) * A(0.2, 1.2, 0.5), 0.26, "Main")
		end
	end

	-- Jade: a smooth green stone with a coiled swirl carved on its front, glowing at its heart.
	shapes.Jade = function(c)
		local body, bodyD = V(-0.16, 0.58, 0), 1.16
		local tail, tailD = V(0.44, 0.44, -0.08), 0.9
		ball(c, body, bodyD, "Main")
		ball(c, tail, tailD, "Main")
		ball(c, V(-0.62, 0.98, 0.1), 0.52, "Light") -- the coil's head
		-- the swirl: rings that shift a little each step, so they wind inward
		local n = V(-0.05, 0.25, 1).Unit
		local surface = onBall(body, bodyD, n, 0)
		local side = n:Cross(V(0, 1, 0)).Unit
		local up = side:Cross(n).Unit
		disc(c, surface - n * 0.1, n, 0.24, 0.7, "Dark")
		disc(c, surface + side * 0.04 + up * 0.03, n, 0.14, 0.5, "Light")
		disc(c, surface + n * 0.04 + side * 0.08 + up * 0.05, n, 0.12, 0.3, "Dark")
		ball(c, surface + n * 0.08 + side * 0.1 + up * 0.06, 0.15, "Vein")
		if c.Full then
			local eye = V(0.7, 0.2, 0.7)
			disc(c, onBall(tail, tailD, eye, 0.04), eye, 0.14, 0.34, "Dark")
			ball(c, onBall(tail, tailD, eye, -0.04), 0.13, "Vein")
			ball(c, V(0.86, 0.2, 0.32), 0.4, "Light")
			point(c, P(0.56, 0.08, 0.6) * A(0.3, 0.5, 0.2), 0.2, JADE_MOSS)
			point(c, P(-0.72, 0.07, -0.42) * A(0.2, 1.2, 0.4), 0.18, JADE_MOSS)
		end
	end

	-- Sapphire: a burst of blue crystal spikes around one tall point.
	shapes.Sapphire = function(c)
		crystal(c, CFrame.new() * A(0, 0.3, 0), 0.38, 1.45, "Main", "Tip")
		local list: { Spike } = {}
		for k = 0, 5 do
			local even = k % 2 == 0
			local phi = k * math.pi / 3 + 0.25
			table.insert(
				list,
				spike(
					phi,
					0.2,
					if even then 0.58 else 0.72,
					if even then 0.27 else 0.24,
					if even then 0.98 else 0.78,
					if even then "Light" else "Dark",
					if even then "Tip" else "Light"
				)
			)
		end
		if c.Full then
			spikes(c, list, 6)
		else
			spikes(c, { list[1], list[4] }, 2)
			point(c, P(0.4, 0.1, 0.4) * A(0.3, 0.8, 0.4), 0.2, "Light")
		end
	end

	-- Dragon Egg: a pale blue egg covered in rounded scales, a glowing seam round its middle.
	shapes.DragonEgg = function(c)
		local low, lowD = V(0, 0.6, 0), 1.2
		local high, highD = V(0, 0.95, 0), 0.98
		ball(c, low, lowD, "Dark")
		ball(c, high, highD, "Main")
		cyl(c, P(0, 0.8, 0), 0.05, 1.19, "Vein")
		-- scales in rows (angle 0 = front), each row turned half a scale from the one below
		local rows = {
			{ center = low, d = lowD, elev = -0.15, count = 5, start = 0.2, size = 0.58 },
			{ center = low, d = lowD, elev = 0.62, count = 4, start = 0.85, size = 0.54 },
			{ center = high, d = highD, elev = 0.72, count = 2, start = 0.3, size = 0.46 },
		}
		local n = 0
		for _, row in rows do
			for k = 0, row.count - 1 do
				n += 1
				local a = row.start + k * math.pi * 2 / row.count
				local front = math.cos(a) > 0.2
				if c.Full or (front and n <= 9) then
					local dir = V(math.sin(a) * math.cos(row.elev), math.sin(row.elev), math.cos(a) * math.cos(row.elev))
					ball(c, onBall(row.center, row.d, dir, 0.2), row.size, if n % 2 == 0 then "Light" else "Main")
				end
			end
		end
	end

	-- In the picture every ore fills its plinth about the same: compact recipes
	-- are grown a little (positions and sizes around the bottom centre).
	for oreId, k in OreShapesLow.Scale do
		local inner = shapes[oreId]
		shapes[oreId] = function(c)
			local first = #c.Specs + 1
			inner(c)
			for i = first, #c.Specs do
				local spec = c.Specs[i]
				spec.CF = CFrame.new(spec.CF.Position * k) * spec.CF.Rotation
				spec.Size *= k
			end
		end
	end
end

return OreShapesLow
