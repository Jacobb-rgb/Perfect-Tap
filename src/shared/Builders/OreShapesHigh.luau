--[[
	Ore looks for the Epic, Legendary and Mythic ores of the owner's ore picture
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

	Part budgets as the tests count them: the clean ore is an invisible Body
	plus the recipe, so a clean recipe makes at most 7 specs; the display adds
	3 orbiting motes for Mythic ores, so a Mythic display recipe makes at most
	11 specs (Epic and Legendary: 14). Every clean and display copy has at
	least one glowing part (Epic and up).
	The podium camera looks at an ore's +Z side; flat looks (moon, leaves,
	feather, heart) face +Z turned by FACE so they read from the front.
	Faceted looks are built from wedges, one shade per facet (see kite).
]]

local OreShapesHigh = {}

OreShapesHigh.Ores = {
	"Diamond",
	"Amethyst",
	"Obsidian",
	"CrystalRose",
	"StormPearl",
	"GalaxyStone",
	"RoyalAurum",
	"Sunstone",
	"Moonstone",
	"StormGem",
	"LeafGem",
	"VolcanicCore",
	"Aetherium",
	"PhoenixFeather",
	"DragonScale",
	"CelestialCore",
	"Heartstone",
}

-- the spec ItemBuilder makes for every part (see ItemBuilder.put)
type Spec = {
	Shape: string,
	CF: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	Neon: boolean,
}
type Tone = string | Color3
type Ctx = any
type Barb = { along: number, len: number, wide: number, tone: Tone }
type Kit = {
	P: (number, number, number) -> CFrame,
	A: (number, number, number) -> CFrame,
	V: (number, number, number) -> Vector3,
	block: (Ctx, CFrame, Vector3, Tone) -> Spec,
	wedge: (Ctx, CFrame, Vector3, Tone) -> Spec,
	ball: (Ctx, Vector3, number, Tone) -> Spec,
	cyl: (Ctx, CFrame, number, number, Tone) -> Spec,
	point: (Ctx, CFrame, number, Tone) -> Spec,
	beam: (Ctx, Vector3, Vector3, number, Tone) -> Spec,
	hexPrism: (Ctx, CFrame, number, number, { Tone }) -> (),
	onBall: (Vector3, number, Vector3, number?) -> Vector3,
	VertexUp: CFrame,
	UpCyl: CFrame,
}

local PI = math.pi
local BLACK = Color3.new(0, 0, 0)
local FACE = -0.3 -- flat looks turn this far (the podium shows ores turned +0.45)

-- Neon colour that keeps its hue under bloom (the same rule as ItemBuilder.glowColor).
local function glowOf(color: Color3): Color3
	local h, s, v = color:ToHSV()
	local safe = Color3.fromHSV(h, math.max(s, 0.62), math.min(v, 0.84))
	local luminance = 0.2126 * safe.R + 0.7152 * safe.G + 0.0722 * safe.B
	if luminance > 0.7 then
		safe = safe:Lerp(BLACK, 1 - 0.7 / luminance)
	end
	return safe
end

-- A part that glows in its own colour (gold rings), not the ore's glow.
local function lit(spec: Spec, color: Color3): Spec
	spec.Color = glowOf(color)
	spec.Material = Enum.Material.Neon
	spec.Reflectance = 0
	spec.Transparency = 0
	spec.Neon = true
	return spec
end

local function shiny(spec: Spec, reflectance: number): Spec
	spec.Reflectance = reflectance
	return spec
end

function OreShapesHigh.register(shapes: { [string]: (any) -> () }, kit: any)
	local K: Kit = kit
	local P, A, V = K.P, K.A, K.V
	local block, wedge, ball, cyl, point, beam = K.block, K.wedge, K.ball, K.cyl, K.point, K.beam
	local onBall = K.onBall
	local VERTEX_UP = K.VertexUp

	---------------------------------------------------------------- local helpers

	-- A corner of point(cf, size): (1, 1, 1) is the top, (-1, -1, -1) the bottom.
	local function corner(cf: CFrame, size: number, x: number, y: number, z: number): Vector3
		local h = size / 2
		return (cf * VERTEX_UP * P(x * h, y * h, z * h)).Position
	end

	-- A flat band from a to b (a ring segment); `axis` is the ring's axis.
	local function band(c: Ctx, a: Vector3, b: Vector3, w: number, h: number, axis: Vector3, tone: Tone): Spec
		local len = (b - a).Magnitude
		return block(c, CFrame.lookAt((a + b) / 2, b, axis), V(w, h, len + w * 0.6), tone)
	end

	-- An arc of n bands in cf's XZ plane (angle 0 = +X, PI/2 = +Z), radius r.
	local function ring(c: Ctx, cf: CFrame, r: number, a0: number, a1: number, n: number, w: number, h: number, tones: { Tone })
		local axis = cf.UpVector
		for k = 0, n - 1 do
			local t0 = a0 + (a1 - a0) * k / n
			local t1 = a0 + (a1 - a0) * (k + 1) / n
			local p0 = (cf * P(math.cos(t0) * r, 0, math.sin(t0) * r)).Position
			local p1 = (cf * P(math.cos(t1) * r, 0, math.sin(t1) * r)).Position
			band(c, p0, p1, w, h, axis, tones[k % #tones + 1])
		end
	end

	--[[
		Sharp shard: a wedge standing in the picture plane of `frame` (frame X =
		across, Y = up, Z = towards the viewer = thickness t). frame = bottom
		centre; dir = 1 puts the tall side and the tip on the right, -1 on the left.
	]]
	local function shard(c: Ctx, frame: CFrame, h: number, d: number, t: number, dir: number, tone: Tone): Spec
		return wedge(c, frame * P(0, h / 2, 0) * A(0, dir * PI / 2, 0), V(t, h, d), tone)
	end

	-- A glowing line along a shard's slope, on its front face.
	local function shardEdge(c: Ctx, frame: CFrame, h: number, d: number, t: number, dir: number, w: number, tone: Tone): Spec
		local a = (frame * P(-dir * (d / 2 - 0.04), 0.06, t / 2)).Position
		local b = (frame * P(dir * (d / 2 - 0.02), h - 0.04, t / 2)).Position
		return beam(c, a, b, w, tone)
	end

	-- Two shards back to back: a symmetric pointed fin `half` wide on each side.
	local function fin(c: Ctx, frame: CFrame, h: number, half: number, t: number, left: Tone, right: Tone)
		shard(c, frame * P(-half / 2, 0, 0), h, half, t, 1, left)
		shard(c, frame * P(half / 2, 0, 0), h, half, t, -1, right)
	end

	--[[
		A faceted kite (gem, leaf, feather vane) in the picture plane of `frame`:
		widest `low` above the base, its tip `high` above that, `half` wide on
		each side. Four wedges (upper left, upper right, lower left, lower right
		tones); `bevel` turns each half back about the middle line so the face
		has a ridge and every facet catches the light its own way.
	]]
	local function kite(c: Ctx, frame: CFrame, low: number, high: number, half: number, t: number, tones: { Tone }, bevel: number?)
		local b = bevel or 0
		local mid = frame * P(0, low, 0)
		local left = mid * A(0, -b, 0)
		local right = mid * A(0, b, 0)
		local flip = A(0, 0, PI)
		shard(c, left * P(-half / 2, 0, 0), high, half, t, 1, tones[1])
		shard(c, right * P(half / 2, 0, 0), high, half, t, -1, tones[2])
		shard(c, left * flip * P(half / 2, 0, 0), low, half, t, -1, tones[3])
		shard(c, right * flip * P(-half / 2, 0, 0), low, half, t, 1, tones[4])
	end

	-- Crystal: a prism (w across, d deep, facing base's +Z) with a two-tone point on top.
	local function crystal(c: Ctx, base: CFrame, w: number, d: number, len: number, tipH: number, body: Tone, left: Tone, right: Tone)
		block(c, base * P(0, len / 2, 0), V(w, len, d), body)
		fin(c, base * P(0, len, 0), tipH, w / 2, d, left, right)
	end

	-- A smaller crystal whose point is cut on a slant (dir = the side of the tip).
	local function crystalCut(c: Ctx, base: CFrame, w: number, d: number, len: number, tipH: number, dir: number, body: Tone, tip: Tone)
		block(c, base * P(0, len / 2, 0), V(w, len, d), body)
		shard(c, base * P(0, len, 0), tipH, w, d, dir, tip)
	end

	-- A pointed petal or scale: a square tile turned 45 degrees, `around` the Y axis at
	-- `radius` and `y`, leaning out by `tilt`.
	local function petal(c: Ctx, around: number, radius: number, y: number, tilt: number, size: number, thick: number, tone: Tone): Spec
		local cf = A(0, around, 0) * P(0, y, radius) * A(tilt, 0, 0) * P(0, size * 0.5, 0) * A(0, 0, PI / 4)
		return block(c, cf, V(size, size, thick), tone)
	end

	-- A zigzag lightning bolt through points given in `frame`.
	local function bolt(c: Ctx, frame: CFrame, pts: { Vector3 }, w: number, tone: Tone)
		for i = 1, #pts - 1 do
			beam(c, (frame * CFrame.new(pts[i])).Position, (frame * CFrame.new(pts[i + 1])).Position, w, tone)
		end
	end

	-- A loose crystal chip on the ground: one wedge standing up (a cube on its corner
	-- reads as a cube when it stands alone).
	local function chip(c: Ctx, x: number, z: number, yaw: number, h: number, w: number, tone: Tone): Spec
		return shard(c, P(x, 0, z) * A(0, yaw, 0), h, w, w * 0.8, 1, tone)
	end

	-- A little heart (a square on its corner and two round lobes) facing cf's +Z.
	local function miniHeart(c: Ctx, cf: CFrame, s: number, tone: Tone)
		block(c, cf * A(0, 0, PI / 4), V(s, s, s * 0.6), tone)
		local o = s * 0.3536
		ball(c, (cf * P(-o, o, 0)).Position, s, tone)
		ball(c, (cf * P(o, o, 0)).Position, s, tone)
	end

	---------------------------------------------------------------- Epic

	-- Diamond: a white brilliant gem standing on its point, clear crystals at its foot.
	shapes.Diamond = function(c: Ctx)
		local base = A(0, -0.25, 0)
		local low, high, half, t = 1.12, 0.66, 0.66, 0.3
		-- two faceted kites crossed at right angles: a gem with a shade on every facet
		kite(c, base, low, high, half, t, { "Light", "Main", "Main", "Dark" }, 0.35)
		if c.Full then
			kite(c, base * A(0, PI / 2, 0), low, high, half * 0.9, t, { "Main", "Light", "Dark", "Main" }, 0.35)
		else
			fin(c, base * A(0, PI / 2, 0) * P(0, low, 0) * A(0, 0, PI), low, half * 0.9, t, "Dark", "Main")
		end
		point(c, P(0.78, 1.45, 0.1) * A(0, 0.5, 0), 0.18, "Tip")
		if c.Full then
			crystalCut(c, P(0.62, 0, 0.22) * A(0, -0.5, -0.5), 0.26, 0.22, 0.3, 0.26, 1, "Glass", "Light")
			crystalCut(c, P(-0.6, 0, 0.18) * A(0, 0.6, 0.5), 0.24, 0.2, 0.26, 0.22, -1, "Glass", "Light")
			point(c, P(-0.6, 1.62, -0.2) * A(0, 0.9, 0), 0.13, "Tip")
		end
	end

	-- Amethyst: tall violet crystal points.
	shapes.Amethyst = function(c: Ctx)
		local main = P(0.04, 0, 0) * A(0, -0.25, -0.07)
		crystal(c, main, 0.56, 0.46, 1.12, 0.46, "Main", "Light", "Main")
		block(c, main * P(0.28, 0.56, 0.23), V(0.06, 1.06, 0.06), "Neon") -- a glowing edge
		crystalCut(c, P(-0.42, 0, 0.06) * A(0, 0.45, 0.42), 0.42, 0.36, 0.66, 0.36, -1, "Main", "Light")
		chip(c, 0.7, 0.32, 0.6, 0.3, 0.2, "Light")
		if c.Full then
			crystalCut(c, P(0.44, 0, -0.04) * A(0, -0.65, -0.44), 0.4, 0.34, 0.62, 0.34, 1, "Dark", "Light")
			crystal(c, P(-0.08, 0, -0.3) * A(-0.3, 0.5, 0.18), 0.4, 0.34, 0.78, 0.3, "Dark", "Main", "Dark")
			crystalCut(c, P(0.28, 0, 0.36) * A(0.45, -0.3, -0.35), 0.3, 0.26, 0.3, 0.24, 1, "Light", "Light")
		end
	end

	-- Obsidian: black glass shards, sharp as knives, glowing violet edges.
	shapes.Obsidian = function(c: Ctx)
		local f = A(0, FACE, 0)
		block(c, f * P(0, 0.12, 0.05) * A(0, 0.3, 0), V(1.1, 0.24, 0.7), "Dark")
		local mid = f * P(0.02, 0.1, 0) * A(0, 0, -0.06)
		fin(c, mid, 1.7, 0.36, 0.5, "Main", "Light")
		local left = f * P(-0.38, 0.1, -0.08) * A(0, 0, 0.32)
		shard(c, left, 1.25, 0.4, 0.42, -1, "Light")
		shardEdge(c, left, 1.25, 0.4, 0.42, -1, 0.05, "Neon")
		local right = f * P(0.4, 0.1, 0.04) * A(0, 0, -0.36)
		shard(c, right, 1.15, 0.4, 0.44, 1, "Main")
		shardEdge(c, right, 1.15, 0.4, 0.44, 1, 0.05, "Neon")
		if c.Full then
			shardEdge(c, mid * P(-0.18, 0, 0), 1.7, 0.36, 0.5, 1, 0.05, "Neon")
			shardEdge(c, mid * P(0.18, 0, 0), 1.7, 0.36, 0.5, -1, 0.05, "Neon")
			fin(c, f * P(0.05, 0.1, -0.24) * A(0, PI / 2, 0) * A(0, 0, 0.1), 1.3, 0.3, 0.4, "Dark", "Main")
			shard(c, f * P(-0.64, 0.05, 0.25) * A(0, 0.5, 0.5), 0.55, 0.3, 0.3, -1, "Main")
			shard(c, f * P(0.68, 0.05, 0.22) * A(0, -0.4, -0.5), 0.5, 0.28, 0.3, 1, "Light")
			block(c, f * P(0.1, 0.24, 0.4) * A(0, 0.3, 0), V(0.6, 0.03, 0.05), "Neon")
		end
	end

	-- Crystal Rose: a pink rose of crystal petals.
	shapes.CrystalRose = function(c: Ctx)
		local outer = if c.Full then 5 else 3
		for k = 0, outer - 1 do
			petal(c, k * 2 * PI / outer + 0.3, 0.3, 0.1, 1.0, 0.72, 0.14, "Dark")
		end
		local middle = if c.Full then 4 else 2
		for k = 0, middle - 1 do
			petal(c, k * 2 * PI / middle + 0.9, 0.17, 0.24, 0.5, 0.66, 0.14, "Main")
		end
		if c.Full then
			for k = 0, 2 do
				petal(c, k * 2 * PI / 3 + 0.1, 0.08, 0.4, 0.2, 0.54, 0.14, "Light")
			end
		end
		point(c, P(0, 0.8, 0) * A(0, 0.4, 0), 0.44, "Light")
		ball(c, V(0, 1.06, 0), 0.16, "Neon")
	end

	-- Storm Pearl: a glowing pale pearl wrapped in swirling light.
	shapes.StormPearl = function(c: Ctx)
		local center = V(0, 0.82, 0)
		local d = 1.3
		ball(c, center, d, "Main")
		ball(c, onBall(center, d, V(-0.5, 0.55, 0.65), 0.16), 0.46, "Light")
		cyl(c, CFrame.new(center) * A(0.6, 0, 0.75), 0.06, d + 0.07, "Neon")
		local swirl = CFrame.new(center + V(0, -0.22, 0)) * A(0.22, 0, -0.14)
		if c.Full then
			cyl(c, CFrame.new(center) * A(-0.5, 0.5, -0.95), 0.05, d + 0.06, "NeonDark")
			ring(c, swirl, 0.98, 0, 2 * PI, 8, 0.1, 0.05, { "Neon", "NeonDark" })
			point(c, CFrame.new(center + V(0.95, 0.42, 0.25)), 0.12, "Neon")
			point(c, CFrame.new(center + V(-0.88, 0.62, -0.2)), 0.1, "Neon")
		else
			cyl(c, swirl, 0.03, 1.9, "NeonDark").Transparency = 0.5
			point(c, CFrame.new(center + V(0.9, 0.4, 0.25)), 0.12, "Neon")
			point(c, CFrame.new(center + V(-0.86, 0.6, -0.2)), 0.1, "Neon")
		end
	end

	-- Galaxy Stone: a violet planet with a ring and a little moon.
	shapes.GalaxyStone = function(c: Ctx)
		local center = V(0, 0.76, 0)
		local d = 1.32
		ball(c, center, d, "Main")
		ball(c, onBall(center, d, V(-0.55, 0.45, 0.7), 0.16), 0.5, "Light")
		local ringCf = CFrame.new(center) * A(0.32, 0, -0.26)
		cyl(c, ringCf, 0.03, 1.95, "Neon").Transparency = 0.35
		local moon = center + V(0.74, 0.56, 0.22)
		shiny(ball(c, moon, 0.34, Color3.fromRGB(70, 140, 255)), 0.15)
		for _, dir in { V(0.3, 0.6, 0.75), V(-0.2, 0.2, 0.95), V(0.6, -0.1, 0.75) } do
			point(c, CFrame.new(onBall(center, d, dir)), 0.1, "Neon")
		end
		if c.Full then
			cyl(c, CFrame.new(moon) * A(0.45, 0, 0.5), 0.03, 0.54, "NeonDark")
			point(c, CFrame.new(center + V(0.98, 0.98, -0.15)) * A(0, 0, -0.6), 0.22, "Neon")
			chip(c, 0.42, 0.42, 0.5, 0.36, 0.26, "Dark")
			chip(c, -0.5, 0.32, 2.4, 0.3, 0.22, "Main")
			point(c, CFrame.new(onBall(center, d, V(-0.7, 0.5, 0.3))), 0.09, "Neon")
		end
	end

	---------------------------------------------------------------- Legendary

	-- Royal Aurum: a black faceted gem with glowing gold edges.
	shapes.RoyalAurum = function(c: Ctx)
		local gold = Color3.fromRGB(255, 184, 46)
		local a = 1.15
		local g = P(-0.12, 0.92, 0) * A(0.15, 0.5, 0.12)
		point(c, g, a, "Main")
		-- gold facets: the same rhombohedron turned 60 degrees, a little smaller
		shiny(point(c, g * A(0, PI / 3, 0), a * 0.9, gold), 0.25)
		-- glowing gold edges down from the top corner
		for _, e in { V(-1, 1, 1), V(1, -1, 1), V(1, 1, -1) } do
			beam(c, corner(g, a, 1, 1, 1), corner(g, a, e.X, e.Y, e.Z), 0.07, "Neon")
		end
		local g2 = P(0.64, 0.42, -0.12) * A(-0.2, 1.4, -0.25)
		point(c, g2, 0.6, "Main")
		if c.Full then
			shiny(point(c, g2 * A(0, PI / 3, 0), 0.54, gold), 0.25)
			beam(c, corner(g, a, -1, 1, 1), corner(g, a, -1, -1, 1), 0.06, "Neon")
			beam(c, corner(g, a, 1, -1, 1), corner(g, a, -1, -1, 1), 0.06, "Neon")
			beam(c, corner(g, a, 1, -1, 1), corner(g, a, 1, -1, -1), 0.06, "Neon")
			beam(c, corner(g2, 0.6, 1, 1, 1), corner(g2, 0.6, -1, 1, 1), 0.05, "Neon")
			shiny(chip(c, -0.72, 0.32, 2.6, 0.42, 0.3, gold), 0.25)
			shiny(chip(c, 0.2, 0.62, 0.9, 0.3, 0.24, gold), 0.25)
			point(c, P(-0.8, 1.3, -0.1) * A(0, 0.4, 0), 0.12, "Neon")
		else
			shiny(chip(c, -0.72, 0.32, 2.6, 0.42, 0.3, gold), 0.25)
		end
	end

	-- Sunstone: a golden sun gem: a faceted disc, saw-tooth rays all round, a bright heart.
	shapes.Sunstone = function(c: Ctx)
		local sun = A(0, FACE, 0) * P(0, 1.0, 0)
		cyl(c, sun * A(PI / 2, 0, 0), 0.46, 1.08, "Main")
		-- the cut face: an octagon of two squares, a glowing gem in its middle
		block(c, sun * P(0, 0, 0.2) * A(0, 0, PI / 8), V(0.7, 0.7, 0.14), "Light")
		point(c, sun * P(0, 0, 0.3) * A(0.3, 0.2, 0), 0.26, "Neon")
		local count = if c.Full then 8 else 4
		for k = 0, count - 1 do
			local a = k * 2 * PI / count + 0.2
			-- each ray leans the same way round: a sun that seems to spin
			local ray = sun * A(0, 0, a - PI / 2) * P(0, 0.42, 0)
			shard(c, ray, 0.5, 0.36, if k % 2 == 0 then 0.34 else 0.28, 1, if k % 2 == 0 then "Light" else "Main")
		end
		if c.Full then
			block(c, sun * P(0, 0, 0.21) * A(0, 0, PI / 8 + PI / 4), V(0.7, 0.7, 0.12), "Main")
			shiny(ball(c, V(0.72, 0.1, 0.42), 0.2, "Light"), 0.2)
			shiny(ball(c, V(-0.66, 0.08, 0.5), 0.16, "Main"), 0.2)
		end
	end

	-- Moonstone: a pale blue crescent moon of crystal.
	shapes.Moonstone = function(c: Ctx)
		local face = P(0.1, 1.04, 0) * A(0, FACE, 0)
		local outer, depth = 0.98, 0.52
		local a0, a1 = math.rad(55), math.rad(305)
		local n = if c.Full then 7 else 4
		local span = (a1 - a0) / n
		local function width(t: number): number
			return 0.24 + 0.4 * math.sin(t * PI)
		end
		local glowAt = if c.Full then 3 else 1
		for k = 0, n - 1 do
			local w = width((k + 0.5) / n)
			local am = a0 + span * (k + 0.5)
			local len = 2 * outer * math.sin(span / 2) + 0.05
			-- the outer edge is a circle, the inner edge thins towards the horns
			local tone = if k == glowAt then "Light" elseif k % 2 == 0 then "Main" else "Dark"
			block(c, face * A(0, 0, am) * P(outer - w / 2, 0, 0), V(w, len, depth), tone)
			if k == glowAt then
				block(c, face * A(0, 0, am) * P(outer - w - 0.01, 0, 0), V(0.05, len * 0.9, depth * 0.7), "NeonDark")
			end
		end
		-- pointed horns
		local wEnd = width(0.5 / n)
		local hornLen = 0.36
		local top = face * A(0, 0, a0) * P(outer - wEnd / 2, 0, 0)
		wedge(c, top * A(0, -PI / 2, 0) * A(PI, 0, 0) * P(0, hornLen / 2, 0), V(depth, hornLen, wEnd), "Light")
		local bottom = face * A(0, 0, a1) * P(outer - wEnd / 2, 0, 0)
		wedge(c, bottom * A(0, PI / 2, 0) * P(0, hornLen / 2, 0), V(depth, hornLen, wEnd), "Light")
		if c.Full then
			chip(c, -0.62, 0.32, 2.5, 0.44, 0.3, "Light")
			chip(c, 0.52, 0.3, 0.6, 0.38, 0.26, "Main")
			point(c, P(-0.95, 0.7, 0.05) * A(0, 0.3, 0.4), 0.2, "Tip")
			chip(c, 0.05, -0.35, 1.2, 0.34, 0.28, "Dark")
		end
	end

	-- Storm Gem: blue crystal points with lightning bolts.
	shapes.StormGem = function(c: Ctx)
		local main = P(0.12, 0, 0.02) * A(0, -0.35, -0.24)
		crystal(c, main, 0.66, 0.5, 1.18, 0.55, "Main", "Light", "Main")
		crystalCut(c, P(-0.34, 0, -0.12) * A(-0.1, 0.4, 0.26), 0.46, 0.4, 0.8, 0.4, -1, "Dark", "Light")
		local f = A(0, FACE, 0)
		bolt(c, f * P(-0.84, 0, 0.1), { V(0.12, 1.6, 0), V(-0.1, 1.18, 0), V(0.1, 1.1, 0) }, 0.09, "Neon")
		if c.Full then
			crystalCut(c, P(-0.46, 0, 0.32) * A(0.45, 0.6, 0.5), 0.32, 0.28, 0.36, 0.28, -1, "Main", "Light")
			crystalCut(c, P(0.56, 0, 0.28) * A(0.35, -0.4, -0.55), 0.34, 0.3, 0.42, 0.3, 1, "Light", "Light")
			beam(c, (f * P(-0.74, 1.1, 0.1)).Position, (f * P(-0.94, 0.7, 0.1)).Position, 0.09, "Neon")
			bolt(c, f * P(0.94, 0, 0), { V(0.06, 1.36, 0), V(-0.12, 1.0, 0), V(0.08, 0.92, 0) }, 0.09, "Neon")
		end
	end

	-- Leaf Gem: bright green crystal leaves.
	shapes.LeafGem = function(c: Ctx)
		local f = A(0, FACE, 0)
		local leaf = f * P(0.06, 0.04, 0.16) * A(0, 0, -0.55)
		kite(c, leaf, 0.78, 1.05, 0.56, 0.18, { "Light", "Main", "Main", "Dark" }, 0.3)
		beam(c, (leaf * P(0, 0.08, 0.12)).Position, (leaf * P(0, 1.76, 0.12)).Position, 0.06, "Neon")
		-- the crystal leaf behind it
		local back = f * P(-0.3, 0.04, -0.2) * A(0, 0.35, 0.22)
		if c.Full then
			kite(c, back, 0.6, 1.0, 0.42, 0.3, { "Main", "Light", "Dark", "Main" }, 0.35)
		else
			fin(c, back, 1.6, 0.36, 0.3, "Light", "Main")
		end
		if c.Full then
			local function tile(cf: CFrame, s: number, tone: Tone)
				block(c, f * cf * A(0, 0, PI / 4), V(s, s, 0.08), tone)
			end
			tile(P(-0.84, 1.02, 0.05) * A(0, 0, 0.5), 0.36, "Light")
			tile(P(-0.7, 0.46, 0.2) * A(0.3, 0, 0.9), 0.32, "Main")
			tile(P(0.94, 0.42, 0.1) * A(0, 0, -0.7), 0.34, "Light")
			chip(c, -0.4, 0.42, 2.2, 0.36, 0.26, "Main")
			point(c, f * P(-0.86, 1.52, 0) * A(0, 0.6, 0), 0.12, "Tip")
		end
	end

	-- Volcanic Core: a black lava rock, glowing cracks between its lumps.
	shapes.VolcanicCore = function(c: Ctx)
		local center = V(0, 0.82, 0)
		ball(c, center, if c.Full then 1.5 else 1.3, "Neon")
		-- round rock lumps sunk into the molten ball at the corners of an icosahedron:
		-- the lava glows in the seams between them (a lumpy boulder)
		local g = 1.618
		local dirs = {
			V(0, 1, g),
			V(1, g, 0),
			V(-1, g, 0),
			V(g, 0, 1),
			V(-g, 0, 1),
			V(0, -1, g),
			V(0, 1, -g),
			V(g, 0, -1),
			V(-g, 0, -1),
			V(0, -1, -g),
			V(1, -g, 0),
			V(-1, -g, 0),
		}
		local tones: { Tone } = { "Main", "Dark", "Light", "Main", "Dark", "Main" }
		if c.Full then
			for i = 1, 12 do
				local size = if i % 3 == 0 then 0.76 else 0.8
				ball(c, center + dirs[i].Unit * 0.5, size, tones[(i - 1) % #tones + 1])
			end
		else
			-- the loose ore: six bigger lumps on the six sides, lava glowing where they meet
			local axes = { V(0, 1, 0), V(0, -1, 0), V(1, 0, 0.2), V(-1, 0, -0.2), V(-0.2, 0, 1), V(0.2, 0, -1) }
			for i, dir in axes do
				ball(c, center + dir.Unit * 0.44, 0.98, tones[i])
			end
		end
		if c.Full then
			block(c, P(0.92, 0.14, 0.44) * A(0.4, 0.6, 0.3), V(0.28, 0.26, 0.26), "Dark")
		end
	end

	---------------------------------------------------------------- Mythic

	-- Aetherium: a violet crystal cluster inside a swirl of light.
	shapes.Aetherium = function(c: Ctx)
		crystal(c, P(0.04, 0, 0) * A(0, -0.3, -0.1), 0.6, 0.5, 1.05, 0.55, "Main", "Light", "Main")
		crystalCut(c, P(-0.4, 0, -0.05) * A(0, 0.5, 0.38), 0.52, 0.44, 0.62, 0.4, -1, "Light", "Light")
		-- the swirl: an open ribbon of light round the cluster, low at the front left,
		-- high at the back right
		local swirl = P(0, 0.82, 0.05) * A(0.36, 0, -0.3)
		if c.Full then
			crystalCut(c, P(0.42, 0, -0.12) * A(0, -0.5, -0.36), 0.48, 0.4, 0.58, 0.38, 1, "Dark", "Main")
			ring(c, swirl, 1.0, -0.7, 3.5, 4, 0.09, 0.17, { "Neon" })
		else
			ring(c, swirl, 1.0, 0.2, 2.9, 2, 0.09, 0.17, { "Neon" })
		end
	end

	-- Phoenix Feather: a fiery feather and a small red gem.
	shapes.PhoenixFeather = function(c: Ctx)
		local ruby = Color3.fromRGB(226, 34, 50)
		local yellow = Color3.fromRGB(255, 196, 60)
		local orange = Color3.fromRGB(250, 118, 28)
		local red = Color3.fromRGB(232, 58, 32)
		local f = A(0, FACE, 0)
		local quill = f * P(-0.62, 0.04, 0.02) * A(0, 0, -0.62)
		-- the vane: a long faceted kite, golden by the quill, orange to red towards the tip
		kite(c, quill * P(0, 0.08, 0), 0.72, 1.5, 0.56, 0.12, { orange, red, yellow, yellow }, 0.2)
		beam(c, (quill * P(0, 0, 0.08)).Position, (quill * P(0, 2.2, 0.08)).Position, 0.05, "NeonDark")
		-- flame licks: barbs that stick out of the vane's edges, up and outwards
		local barbs: { Barb } = if c.Full
			then {
				{ along = 0.58, len = 0.82, wide = 0.28, tone = yellow },
				{ along = 1.38, len = 0.7, wide = 0.24, tone = red },
			}
			else { { along = 0.58, len = 0.82, wide = 0.28, tone = yellow } }
		for _, b in barbs do
			for _, side in { 1, -1 } do
				if c.Full or side == -1 then
					local frame = quill * P(0, b.along, 0) * A(0, 0, -side * 0.72)
					shard(c, frame, b.len, b.wide, 0.1, -side, b.tone)
				end
			end
		end
		-- the small ruby: two rhombohedra turned apart, a faceted stone
		local gem = P(0.7, 0.2, 0.32) * A(0, 0.4, 0)
		shiny(point(c, gem, 0.34, ruby), 0.2)
		if c.Full then
			shiny(point(c, gem * A(0, PI / 3, 0), 0.3, Color3.fromRGB(255, 92, 92)), 0.2)
		end
	end

	-- Dragon Scale: round dark scales row on row over glowing lava, flames at its sides.
	shapes.DragonScale = function(c: Ctx)
		local f = A(0, FACE, 0)
		-- the lava the scales lie on (it glows in every gap between them)
		ball(c, (f * P(0, 0.56, -0.24)).Position, 1.04, "Neon")
		-- fish-scale rows: each row lies over the top of the row below, so only the lower
		-- curve of every scale shows; side scales turn outwards and upper rows lean back,
		-- so the scales wrap round a mound. (x, y, size) in the face's frame
		local scales = {
			V(-0.5, 0.3, 0.54),
			V(0, 0.3, 0.54),
			V(0.5, 0.3, 0.54),
			V(-0.26, 0.62, 0.5),
			V(0.26, 0.62, 0.5),
		}
		if c.Full then
			table.insert(scales, V(0, 0.92, 0.46))
			table.insert(scales, V(0, 1.16, 0.34))
		end
		for i, s in scales do
			local row = (s.Y - 0.3) / 0.3
			local cf = f * P(s.X, s.Y, 0.3 + row * 0.02 - math.abs(s.X) * 0.3) * A(-0.22 - row * 0.12, s.X * 0.9, 0)
			cyl(c, cf * A(PI / 2, 0, 0), 0.12, s.Z, if i == 2 or i == 6 then "Main" else "Light")
		end
		if c.Full then
			shard(c, f * P(-0.66, 0.04, 0) * A(0, 0, 0.12), 1.0, 0.32, 0.12, -1, "Neon")
			shard(c, f * P(0.68, 0.04, -0.05) * A(0, 0, -0.12), 1.15, 0.34, 0.12, 1, "NeonDark")
		else
			shard(c, f * P(0.66, 0.04, 0) * A(0, 0, -0.12), 0.8, 0.28, 0.1, 1, "NeonDark")
		end
	end

	-- Celestial Core: a blue orb held in golden orbit rings.
	shapes.CelestialCore = function(c: Ctx)
		local gold = Color3.fromRGB(255, 188, 60)
		local center = V(0, 0.92, 0)
		local d = 1.16
		ball(c, center, d, "Main")
		ball(c, onBall(center, d, V(-0.5, 0.55, 0.65), 0.15), 0.42, "Light")
		local orbit = CFrame.new(center) * A(0.42, 0, 0.32)
		lit(cyl(c, CFrame.new(center) * A(-0.75, 0.2, -0.55), 0.06, d + 0.14, gold), gold)
		if c.Full then
			ring(c, orbit, 0.95, 0, 2 * PI, 6, 0.07, 0.05, { gold })
			point(c, orbit * P(0, 0, 0.95), 0.22, "Tip")
			ball(c, center, d + 0.06, "Glass")
		else
			shiny(cyl(c, orbit, 0.05, 1.5, gold), 0.25)
			point(c, orbit * P(0, 0, 0.72), 0.2, "Tip")
			point(c, orbit * P(-0.72, 0, 0), 0.18, "Tip")
			chip(c, 0.5, 0.42, 0.4, 0.3, 0.2, "Light")
		end
	end

	-- Heartstone Shard: a pink crystal heart, little hearts floating round it.
	shapes.Heartstone = function(c: Ctx)
		local f = A(0, FACE, 0)
		local r, t = 0.48, 0.6
		local top = f * P(0, 1.1, 0) -- the line through the lobes' centres
		-- the point: a V of two facets (light left, deep right) with a ridge down the middle
		local down = top * A(0, 0, PI)
		shard(c, down * A(0, 0.25, 0) * P(0.44, 0, 0), 1.04, 0.88, t, -1, "Main")
		shard(c, down * A(0, -0.25, 0) * P(-0.44, 0, 0), 1.04, 0.88, t, 1, "Dark")
		-- round lobes
		cyl(c, top * P(-0.4, 0, -0.04) * A(PI / 2, 0, 0), t, r * 2, "Light")
		cyl(c, top * P(0.4, 0, -0.04) * A(PI / 2, 0, 0), t, r * 2, "Main")
		block(c, top * P(0, -0.2, t / 2 + 0.02) * A(0, 0, PI / 4), V(0.2, 0.2, 0.06), "Neon")
		if c.Full then
			miniHeart(c, f * P(-0.98, 1.42, 0.1), 0.26, "Light")
			miniHeart(c, f * P(0.95, 1.7, -0.05), 0.22, "Tip")
		else
			chip(c, -0.72, 0.2, 2.6, 0.42, 0.3, "Light")
			chip(c, 0.72, 0.18, 0.5, 0.36, 0.26, "Main")
		end
	end
end

return OreShapesHigh
