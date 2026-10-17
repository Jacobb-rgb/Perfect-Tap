--[[
	Sky package: three big planets in the north sky (docs/plans/VISUAL_UPGRADE_PLAN.md,
	package Sky), styled after the Kenney Planets sprites (CC0, docs/art/kenney_refs/planets_kit.jpg):

	  PlanetViolet  a huge violet gas giant with wavy dark and light bands, a mint streak and a tilted ring (planet09 / planet01)
	  PlanetEmber   an orange-red world with wavy orange, crimson and maroon camouflage (planet02 / planet08)
	  PlanetTeal    a small pale-blue world with mint and green land and deep-water blotches (planet00 / planet03)

	Each planet is one big Ball (the body) plus "patch" Balls. A patch ball is
	much smaller than the body (radius <= 0.6 R) and its center sits so that
	only a cap of it pokes out of the body; the cap is a blotch in a second or
	third color. Every cap meets the surface it pokes out of at a steep angle
	(Planets.MinCrease, Planets.MinShadeCrease where a blotch crosses the
	shading), never at a grazing one, so the two surfaces never z-fight (far
	away the depth buffer cannot separate nearly tangent spheres).

	The camouflage is the sprites' look: caps of very different sizes (6-18
	degrees), jittered off their band and unevenly spaced, overlapping into
	wavy merged shapes that run from limb to limb and cover about two thirds
	of the face. Three tiers of lift keep the layers apart: the dark
	lower-right shading (SHADE) under the blotches (BASE) under the spots on
	the blotches (TOP); caps near the limb poke out less (LIMB) so the outline
	stays round. The gloss is two or three small elongated caps along the
	upper-left limb in the body color lightened 35%, translucent Neon (never
	a white blob). A slightly larger translucent Neon ball in a saturated body
	hue is the tight glowing rim; the gas giant's ring is one band of 20 flat
	blocks around its tilted equator, darker than the body.

	Colors are picked for the hazed result: 1300-1500 studs out the evening
	Atmosphere keeps only 40-50% of a part's own color and adds its own:
	warm (pink-orange) toward the sun, lavender-blue away from it. So every
	tone is Neon (glow is the part of the color that survives) and each
	planet hangs on the side of the sky whose haze suits it: the violet giant
	and its ring on the cool side (north-east), where deep violet stays
	violet; the ember world on the warm side (north-west), where it keeps its
	orange-red; the small blue world between them, north-north-west, in
	deep cyan tones that stay blue through the half-warm haze (bright cyan
	would glow white there). The sprites' deep tones need a thinner
	Atmosphere (LightingConfig, Lighting owner): at Density ~0.19 the same
	palette keeps ~60% of its own color 1500 studs out.

	Placement: the hero camera looks down at the town, so its sky is a band
	only ~11-13 degrees tall above the far land; the spawn camera stands on
	the plaza, where the SHOP and UPGRADES roofs, the floating islands and the
	massif fill the low sky. The planets sit in the hero frame's free corners
	and in the gap between the west island and the massif, every disc with its
	rim and ring wholly inside the hero frame; from the spawn none is behind
	the massif, an airship or a cloud, at most 15% of one dips behind a
	floating island or the balloon, and only a lower edge behind the town
	skyline (Planets.MaxSkylineCover; tests/LobbySky.spec.luau). Positions are bearing, elevation and angular
	size seen from the plaza, so the size on screen stays put if a distance
	changes. Unreachable decoration: no collision, no raycasts, no touch, no
	shadows, <= 40 parts each, no lights.

	Streaming: Persistent. StreamingTargetRadius is 384 studs, so with
	LevelOfDetail = StreamingMesh a planet 1500 studs out would never stream in
	and players would only ever see its low-detail imposter mesh (no Neon glow,
	no translucent rim, smeared blotches). The three planets are 120 parts at
	most, so they are cheap enough to keep streamed in.

	Pure builder: Instance creation only, deterministic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local NEON = Enum.Material.Neon
local BALL = Enum.PartType.Ball
local WHITE = Color3.new(1, 1, 1)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Local palette after the Kenney Planets sprites, picked for the hazed result
-- (see the header): the Neon tone here comes out about as the sprite tone
-- after the evening haze.
local P = {
	-- planet09 / planet01: violet gas giant (north-east, lavender haze)
	Violet = rgb(76, 12, 168),
	VioletDeep = rgb(30, 0, 72),
	VioletShade = rgb(16, 0, 40),
	Lilac = rgb(150, 104, 240),
	Mint = rgb(0, 160, 96),
	Ring = rgb(24, 0, 62),
	RimViolet = rgb(110, 40, 255),
	-- planet02 / planet08: orange-red world (north-west, warm haze)
	Rust = rgb(180, 10, 0),
	Orange = rgb(255, 80, 0),
	Crimson = rgb(220, 0, 30),
	Maroon = rgb(100, 0, 0),
	EmberShade = rgb(50, 0, 0),
	RimOrange = rgb(255, 60, 0),
	-- planet00 / planet03: pale-blue world (north-north-west, half-warm haze:
	-- bright cyan would glow white there, so the tones are deep)
	Ocean = rgb(0, 138, 212),
	OceanDeep = rgb(0, 104, 200),
	Mint2 = rgb(0, 176, 166),
	Leaf = rgb(0, 160, 105),
	Navy = rgb(0, 90, 170),
	RimCyan = rgb(0, 180, 240),
}

export type Patch = {
	Lon: number, -- degrees, 0 = the point facing the town, + = to the viewer's right
	Lat: number, -- degrees, + = up (on the tilted spin frame, or the face frame if Face)
	Size: number, -- angular radius of the cap on the body (degrees)
	Lift: number, -- how far the cap pokes out of the body at its middle (fraction of the radius)
	Color: Color3,
	Face: boolean?, -- placed on the town-facing frame (shade, gloss) instead of the spin frame
	Shade: boolean?, -- part of the dark lower-right shading (under the blotches)
	Transparency: number?, -- translucent Neon (the gloss)
}

export type Ring = {
	Inner: number, -- radii (fractions of the planet radius)
	Outer: number,
	Segments: number,
	Color: Color3,
}

export type Spec = {
	Name: string,
	Az: number, -- compass bearing from the plaza (0 = north = -Z, 90 = east)
	Dist: number, -- horizontal distance from the plaza
	Elev: number, -- elevation of the center seen from the plaza (degrees)
	Size: number, -- angular diameter of the body seen from the plaza (degrees)
	Roll: number, -- spin axis tilt seen from the town (degrees, + = top to the viewer's right)
	Lean: number, -- spin axis leaned toward the town (degrees): opens the ring
	Body: Color3,
	Rim: Color3,
	RimTransparency: number,
	Patches: { Patch },
	Ring: Ring?,
}

-- A ball of a planet in world orientation: `Offset` from the planet center.
export type Ball = {
	Name: string,
	Offset: Vector3,
	Radius: number,
	Color: Color3,
	Shade: boolean,
	Transparency: number,
}

local Planets = {}

Planets.Palette = P

-- the point the planets face (between the spawn and the plaza, eye height)
Planets.Town = Vector3.new(0, 30, 30)

-- Max parts per planet (mobile budget).
Planets.MaxParts = 40
-- A cap meets the surface it pokes out of at least this steeply (degrees).
Planets.MinCrease = 20
-- ... and a blotch crosses the shading at least this steeply.
Planets.MinShadeCrease = 30
-- A patch ball is at most this fraction of the body radius.
Planets.MaxPatchRadius = 0.6
--[[
	From the spawn, the town skyline (the SHOP / UPGRADES roofs, the Great
	Forge: their footprint boxes) may hide at most this fraction of a
	planet's disc. The hero frame tops out ~13 degrees up while those roofs
	reach ~9-11 degrees seen from the spawn, so a planet wholly inside the
	hero frame cannot clear them completely: only its lower edge may dip
	behind them. The floating islands and the balloon hide at most 15%.
]]
Planets.MaxSkylineCover = 0.55
--[[
	The rim: a translucent Neon ball RimScale x the body, its center pushed
	RimBack x the radius away from the town. Its front is hidden inside the
	body (it never veils the face) and it comes out of the body right at the
	silhouette, crossing it steeply: only a thin glowing edge shows.
]]
Planets.RimScale = 1.07
Planets.RimBack = 0.3
-- the gloss: the body color lightened this much, translucent Neon
Planets.GlossLighten = 0.35
Planets.GlossTransparency = 0.4

-- cap heights: shading under everything, blotches, spots on the blotches;
-- caps near the limb poke out less so the outline stays round
local SHADE, BASE, TOP, LIMB = 0.05, 0.12, 0.16, 0.08

--[[
	A cap: lon/lat of its middle, angular radius, color and lift (BASE by
	default).
]]
local function cap(lon: number, lat: number, size: number, color: Color3, lift: number?): Patch
	return { Lon = lon, Lat = lat, Size = size, Lift = lift or BASE, Color = color }
end

local function concat(...: { Patch }): { Patch }
	local out: { Patch } = {}
	for _, list in { ... } do
		for _, patch in list do
			table.insert(out, patch)
		end
	end
	return out
end

-- the dark lower-right limb (the sprites' shading), under the blotches
local function shade(color: Color3, list: { { number } }): { Patch }
	local out: { Patch } = {}
	for _, s in list do
		table.insert(out, { Lon = s[1], Lat = s[2], Size = s[3], Lift = SHADE, Color = color, Face = true, Shade = true })
	end
	return out
end

-- the gloss streak along the upper-left limb: a few small overlapping caps
-- in the body color lightened 35%, translucent Neon
local function gloss(body: Color3, list: { { number } }): { Patch }
	local color = body:Lerp(WHITE, Planets.GlossLighten)
	local out: { Patch } = {}
	for _, s in list do
		table.insert(out, {
			Lon = s[1],
			Lat = s[2],
			Size = s[3],
			Lift = TOP,
			Color = color,
			Face = true,
			Transparency = Planets.GlossTransparency,
		})
	end
	return out
end

Planets.Specs = {
	{
		-- the ringed gas giant in the hero frame's top-right corner, on the
		-- cool side right of the east island (planet09 / planet01)
		Name = "PlanetViolet",
		Az = 32.25,
		Dist = 1500,
		Elev = 9.2,
		Size = 7,
		Roll = -20,
		Lean = 26,
		Body = P.Violet,
		Rim = P.RimViolet,
		RimTransparency = 0.6,
		Patches = concat(shade(P.VioletShade, { { 58, -30, 15 } }), {
			-- the upper dark band: big uneven caps merging into one wavy
			-- band from limb to limb
			cap(-62, 30, 14, P.VioletDeep, LIMB),
			cap(-36, 35, 17, P.VioletDeep),
			cap(-8, 27, 14, P.VioletDeep),
			cap(18, 36, 16, P.VioletDeep),
			cap(46, 29, 13, P.VioletDeep, LIMB),
			-- the wide light band: three big caps of different sizes,
			-- offset from the dark bands, merging into the mint on the right
			cap(-62, 12, 8, P.Lilac, LIMB),
			cap(-40, 4, 19, P.Lilac),
			cap(-12, 9, 15, P.Lilac),
			cap(16, 2, 18, P.Lilac),
			cap(44, 7, 12, P.Mint, LIMB),
			-- the lower dark band
			cap(-52, -26, 15, P.VioletDeep, LIMB),
			cap(-22, -22, 17, P.VioletDeep),
			cap(10, -30, 14, P.VioletDeep),
			cap(34, -16, 8, P.VioletDeep),
			-- a mint streak low on the left (planet01)
			cap(-30, -50, 9, P.Mint),
		}, gloss(P.Violet, { { -50, 40, 4 }, { -40, 49, 3.5 } })),
		Ring = { Inner = 1.3, Outer = 1.75, Segments = 20, Color = P.Ring },
	},
	{
		-- the orange-red world in the hero frame's top-left corner, on the
		-- warm side left of the west island (planet02 / planet08)
		Name = "PlanetEmber",
		Az = 322.5,
		Dist = 1500,
		Elev = 8.9,
		Size = 6.75,
		Roll = 0,
		Lean = 0,
		Body = P.Rust,
		Rim = P.RimOrange,
		RimTransparency = 0.6,
		Patches = concat(shade(P.EmberShade, { { 62, -24, 14 }, { 36, -54, 15 } }), {
			-- the top: maroon blotches and a crimson one
			cap(-34, 58, 11, P.Maroon, LIMB),
			cap(-2, 54, 13, P.Maroon),
			cap(26, 60, 9, P.Crimson, LIMB),
			cap(48, 44, 10, P.Maroon, LIMB),
			-- the upper orange band: three blotches, each a big cap with
			-- smaller lobes, so the outline is wavy, not a bead string
			cap(-40, 25, 17, P.Orange),
			cap(-60, 16, 9, P.Orange, LIMB),
			cap(-26, 39, 8, P.Orange),
			cap(6, 21, 15, P.Orange),
			cap(23, 33, 9, P.Orange),
			cap(-10, 31, 7, P.Orange),
			cap(45, 17, 11, P.Orange, LIMB),
			cap(59, 28, 7, P.Orange, LIMB),
			-- the crimson middle with maroon islands
			cap(-52, -4, 12, P.Maroon, LIMB),
			cap(-30, 2, 10, P.Crimson),
			cap(-14, -7, 8, P.Maroon),
			cap(8, -2, 11, P.Crimson),
			cap(28, -1, 13, P.Maroon),
			cap(54, -8, 9, P.Crimson, LIMB),
			-- the lower orange band, falling to the right
			cap(-30, -30, 16, P.Orange),
			cap(-52, -22, 9, P.Orange, LIMB),
			cap(-12, -41, 8, P.Orange),
			cap(12, -34, 12, P.Orange),
			cap(28, -24, 7, P.Orange),
			-- the bottom
			cap(-26, -58, 12, P.Maroon, LIMB),
			cap(4, -60, 9, P.Crimson, LIMB),
			-- spots on the blotches
			cap(-48, 22, 6, P.Crimson, TOP),
			cap(12, 17, 6, P.Maroon, TOP),
			cap(-24, -34, 6, P.Maroon, TOP),
		}, gloss(P.Rust, { { -56, 36, 4 }, { -46, 46, 3.5 }, { -34, 54, 3 } })),
	},
	{
		-- the small pale-blue world between the west island and the massif
		-- (planet00 / planet03)
		Name = "PlanetTeal",
		Az = 338,
		Dist = 1500,
		Elev = 11,
		Size = 5,
		Roll = 0,
		Lean = 0,
		Body = P.Ocean,
		Rim = P.RimCyan,
		RimTransparency = 0.6,
		Patches = concat(shade(P.Navy, { { 62, -24, 14 }, { 36, -54, 15 } }), {
			-- the northern land: a big blotch with lobes and a smaller one
			cap(-40, 36, 16, P.Mint2),
			cap(-62, 26, 9, P.Mint2, LIMB),
			cap(-20, 48, 8, P.Mint2),
			cap(8, 40, 11, P.Mint2),
			cap(30, 48, 8, P.Mint2, LIMB),
			cap(48, 32, 10, P.Mint2, LIMB),
			cap(-8, 62, 9, P.Mint2, LIMB),
			-- the middle land, a long wavy run with lobes
			cap(-14, 6, 17, P.Mint2),
			cap(-40, -2, 10, P.Mint2),
			cap(-60, -10, 8, P.Mint2, LIMB),
			cap(12, 12, 9, P.Mint2),
			cap(30, 4, 13, P.Mint2),
			cap(54, 12, 8, P.Mint2, LIMB),
			-- the southern land
			cap(-44, -38, 14, P.Mint2),
			cap(-22, -32, 8, P.Mint2),
			cap(0, -44, 12, P.Mint2),
			cap(20, -34, 7, P.Mint2),
			cap(-64, -34, 8, P.Mint2, LIMB),
			cap(-20, -60, 8, P.Mint2, LIMB),
			-- small islands that break up the open water on the right
			cap(62, 42, 8, P.Mint2, LIMB),
			cap(40, 24, 7, P.Mint2),
			cap(-32, 60, 8, P.Mint2, LIMB),
			cap(14, -58, 8, P.Mint2, LIMB),
			-- green inside the land
			cap(-44, 32, 8, P.Leaf, TOP),
			cap(-8, 8, 9, P.Leaf, TOP),
			cap(34, 6, 6, P.Leaf, TOP),
			cap(-48, -42, 7, P.Leaf, TOP),
			-- deep water between the land
			cap(-30, 18, 7, P.OceanDeep),
			cap(16, 26, 8, P.OceanDeep),
			cap(46, -16, 9, P.OceanDeep),
			cap(-18, -18, 6, P.OceanDeep),
		}, gloss(P.Ocean, { { -56, 36, 4 }, { -46, 46, 3.5 }, { -34, 54, 3 } })),
	},
} :: { Spec }

-- Center of a planet from its bearing, distance and height.
function Planets.center(spec: Spec): Vector3
	local a = math.rad(spec.Az)
	return Vector3.new(math.sin(a) * spec.Dist, spec.Dist * math.tan(math.rad(spec.Elev)), -math.cos(a) * spec.Dist)
end

-- Diameter in studs from the angular size.
function Planets.diameter(spec: Spec): number
	return 2 * spec.Dist * math.tan(math.rad(spec.Size / 2))
end

--[[
	A patch ball: a ball whose center sits `d` from the body center toward
	the patch direction and whose radius `r` makes it poke out of the body
	by `lift * R` at the middle and meet the body surface `size` degrees
	from the middle (law of cosines on R, d and r).
]]
function Planets.capBall(radius: number, size: number, lift: number): (number, number)
	local p = 1 + lift
	local d = radius * (p * p - 1) / (2 * (p - math.cos(math.rad(size))))
	return d, radius * p - d
end

-- Angle (degrees) between two intersecting spheres' surfaces along their
-- intersection circle (radii a, b, centers `dist` apart): 0 = tangent.
function Planets.crease(a: number, b: number, dist: number): number
	local c = math.clamp((a * a + b * b - dist * dist) / (2 * a * b), -1, 1)
	local angle = math.deg(math.acos(c))
	return math.min(angle, 180 - angle)
end

-- Unit direction on the planet: lon/lat in degrees, 0/0 faces the town (-Z).
local function direction(lon: number, lat: number): Vector3
	local lo, la = math.rad(lon), math.rad(lat)
	return Vector3.new(-math.sin(lo) * math.cos(la), math.sin(la), -math.cos(lo) * math.cos(la))
end

-- The town-facing frame and the tilted spin frame (bands, ring) of a planet.
function Planets.frames(spec: Spec): (CFrame, CFrame)
	local center = Planets.center(spec)
	local faceFrame = CFrame.lookAt(center, Planets.Town)
	local spin = faceFrame * CFrame.Angles(0, 0, math.rad(-spec.Roll)) * CFrame.Angles(math.rad(-spec.Lean), 0, 0)
	return faceFrame, spin
end

-- Every ball of a planet (body first, then the patches in order).
function Planets.balls(spec: Spec): { Ball }
	local radius = Planets.diameter(spec) / 2
	local faceFrame, spin = Planets.frames(spec)
	local out: { Ball } = {
		{ Name = "Body", Offset = Vector3.zero, Radius = radius, Color = spec.Body, Shade = false, Transparency = 0 },
	}
	for i, patch in spec.Patches do
		local d, r = Planets.capBall(radius, patch.Size, patch.Lift)
		local frame = if patch.Face then faceFrame else spin
		table.insert(out, {
			Name = `Patch{i}`,
			Offset = frame:VectorToWorldSpace(direction(patch.Lon, patch.Lat) * d),
			Radius = r,
			Color = patch.Color,
			Shade = patch.Shade == true,
			Transparency = patch.Transparency or 0,
		})
	end
	return out
end

-- A Neon ball (the planets glow like moons: Neon keeps its color through the haze).
local function ball(parent: Instance, position: Vector3, diameter: number, color: Color3, transparency: number?): Part
	return Style.block(
		parent,
		CFrame.new(position),
		Vector3.new(diameter, diameter, diameter),
		color,
		NEON,
		Kit.far({ Shape = BALL, Transparency = transparency or 0 })
	)
end

-- Center of the rim ball: RimBack x the radius behind the body center.
function Planets.rimCenter(spec: Spec): Vector3
	local center = Planets.center(spec)
	local radius = Planets.diameter(spec) / 2
	return center + (center - Planets.Town).Unit * radius * Planets.RimBack
end

function Planets.planet(parent: Instance, spec: Spec): Model
	local m = Style.model(spec.Name, parent)
	local center = Planets.center(spec)
	local radius = Planets.diameter(spec) / 2
	local body: Part? = nil
	for _, b in Planets.balls(spec) do
		local p = ball(m, center + b.Offset, 2 * b.Radius, b.Color, b.Transparency)
		p.Name = b.Name
		body = body or p
	end
	-- thin glowing edge (the sprites' bright outline), set back behind the body
	local rim = ball(m, Planets.rimCenter(spec), 2 * radius * Planets.RimScale, spec.Rim, spec.RimTransparency)
	rim.Name = "Rim"

	-- the ring: one band of flat blocks around the tilted equator. Each
	-- block is as long as the polygon side at the outer radius (no notches
	-- on the outer edge); neighbors overlap toward the inner edge, which is
	-- invisible because every block has the same color and material.
	local ring = spec.Ring
	if ring then
		local _, spin = Planets.frames(spec)
		local inner, outer = ring.Inner * radius, ring.Outer * radius
		local mid = (inner + outer) / 2
		local n = ring.Segments
		local length = 2 * outer * math.tan(math.pi / n) + 1
		local thickness = math.max(2, radius * 0.01)
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * 2 * math.pi
			local cf = spin * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -mid)
			local seg = Style.block(m, cf, Vector3.new(length, thickness, outer - inner), ring.Color, NEON, Kit.far())
			seg.Name = "Ring"
		end
	end

	m.PrimaryPart = body
	Style.streaming(m, "Persistent")
	return m
end

-- All planets under one Model "Planets".
function Planets.build(parent: Instance, _rng: Rng.Rng): Model
	local m = Style.model("Planets", parent)
	for _, spec in Planets.Specs do
		Planets.planet(m, spec)
	end
	return m
end

return Planets
