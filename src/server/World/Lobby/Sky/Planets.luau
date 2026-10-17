--[[
	Sky package: three big planets in the north sky (docs/plans/VISUAL_UPGRADE_PLAN.md,
	package Sky), styled after the Kenney Planets sprites (CC0, docs/art/kenney_refs/planets_kit.jpg):

	  PlanetViolet  a huge violet gas giant with dark and light blotchy bands and a tilted ring (planet09 / planet01)
	  PlanetEmber   an orange-red world with diagonal orange, maroon and crimson streaks (planet02 / planet08)
	  PlanetTeal    a small blue world with diagonal mint/green land streaks (planet00 / planet03)

	Each planet is one big Ball (the body) plus "patch" Balls. A patch ball is
	much smaller than the body (radius <= 0.6 R) and its center sits so that
	only a cap of it pokes out of the body; the cap is a blotch in a second or
	third color. Every cap meets the surface it pokes out of at a steep angle
	(Planets.MinCrease), never at a grazing one, so the two surfaces never
	z-fight (far away the depth buffer cannot separate nearly tangent
	spheres). Rows of caps make the gas giant's bands, chains of 3-4 caps along
	a ~30 degree diagonal make the camouflage streaks of the small worlds, a
	few dark caps along the lower-right limb shade it (the sprites' darker
	lower right) and one small pale cap is the top-left highlight. A slightly
	larger translucent Neon ball is the soft glowing rim; the gas giant's ring
	is one band of flat blocks around its tilted equator.

	Colors are picked for the hazed result: 1500 studs out the evening
	Atmosphere keeps only about a third of a part's own color and adds its
	own: warm (pink-orange) toward the sun, lavender-blue away from it. So
	every tone is Neon (glow is the part of the color that survives; a dark
	SmoothPlastic tone turns into the bare haze color, a hole in the planet),
	the dark tones are deep saturated hues instead of near-black, and each
	planet hangs on the side of the sky whose haze suits it: the violet giant
	on the cool side (north-east), where its dark bands stay deep violet, the
	ember world on the warm side (north-west), where it keeps its orange (on
	the cool side the haze would turn it pink), and the small blue world
	beside it. Even so the haze pales them to pastel; the sprites' deep
	tones need a thinner Atmosphere (LightingConfig, Lighting owner).

	Placement: the hero camera looks down at the town, so its sky is a band
	only ~11 degrees tall above the mountain; the spawn camera stands on the
	plaza, where the shops, the floating islands and the massif hide the low
	sky. The planets sit where both see them: the ember and the blue world
	left of the mountain, the violet giant right of it (the east island hangs
	in front of its lower left from the spawn), each at least 75% inside the
	hero frame and never behind the massif from the spawn (tests/LobbySky).
	Positions are bearing, elevation and angular size seen from the plaza, so
	the size on screen stays put if a distance changes. Unreachable
	decoration: no collision, no raycasts, no touch, no shadows, <= 40 parts
	each, no lights.

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

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Local palette after the Kenney Planets sprites, picked for the hazed result
-- (see the header).
local P = {
	-- planet09 / planet01: violet gas giant (north-east, lavender haze)
	Violet = rgb(100, 20, 250),
	VioletDeep = rgb(30, 0, 100),
	VioletShade = rgb(20, 0, 70),
	Lilac = rgb(140, 90, 250),
	LilacPale = rgb(240, 220, 255),
	Mint = rgb(80, 230, 180),
	Ring = rgb(70, 10, 220),
	RimViolet = rgb(170, 130, 255),
	-- planet02 / planet08: orange-red world (north-west, warm haze)
	Rust = rgb(210, 40, 0),
	Orange = rgb(255, 130, 0),
	Maroon = rgb(110, 0, 0),
	Crimson = rgb(240, 0, 40),
	EmberShade = rgb(70, 0, 8),
	Peach = rgb(255, 200, 140),
	RimOrange = rgb(255, 140, 50),
	-- planet00 / planet03: blue-teal world (north-west, beside the ember world)
	Ocean = rgb(0, 76, 236),
	OceanDeep = rgb(0, 20, 150),
	Mint2 = rgb(0, 196, 146),
	Leaf = rgb(0, 150, 50),
	Ice = rgb(210, 236, 255),
	Wisp = rgb(120, 190, 240),
	Navy = rgb(0, 0, 80),
	RimCyan = rgb(120, 220, 255),
}

export type Patch = {
	Lon: number, -- degrees, 0 = the point facing the town, + = to the viewer's right
	Lat: number, -- degrees, + = up (on the tilted spin frame, or the face frame if Face)
	Size: number, -- angular radius of the cap on the body (degrees)
	Lift: number, -- how far the cap pokes out of the body at its middle (fraction of the radius)
	Color: Color3,
	Face: boolean?, -- placed on the town-facing frame (shade, highlight) instead of the spin frame
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
}

local Planets = {}

Planets.Palette = P

-- the point the planets face (between the spawn and the plaza, eye height)
Planets.Town = Vector3.new(0, 30, 30)

-- Max parts per planet (mobile budget).
Planets.MaxParts = 40
-- A cap meets the surface it pokes out of at least this steeply (degrees).
Planets.MinCrease = 20
-- A patch ball is at most this fraction of the body radius.
Planets.MaxPatchRadius = 0.6
--[[
	The rim: a translucent Neon ball RimScale x the body, its center pushed
	RimBack x the radius away from the town. Its front is hidden inside the
	body (it never veils the face) and it comes out of the body right at the
	silhouette, crossing it steeply: only a soft glowing halo shows.
]]
Planets.RimScale = 1.15
Planets.RimBack = 0.45

--[[
	A row of caps along one latitude (a band): `lons` are the cap middles.
]]
local function row(lat: number, lons: { number }, size: number, lift: number, color: Color3): { Patch }
	local out: { Patch } = {}
	for _, lon in lons do
		table.insert(out, { Lon = lon, Lat = lat, Size = size, Lift = lift, Color = color })
	end
	return out
end

--[[
	A streak: `count` overlapping caps from (lon, lat) along `angle` degrees
	(0 = to the viewer's right, + = up), `step` degrees apart; the end caps
	are a bit smaller so the streak tapers.
]]
local function streak(
	lon: number,
	lat: number,
	angle: number,
	count: number,
	step: number,
	size: number,
	lift: number,
	color: Color3
): { Patch }
	local out: { Patch } = {}
	local a = math.rad(angle)
	for i = 0, count - 1 do
		local taper = if i == 0 or i == count - 1 then 0.8 else 1
		table.insert(out, {
			Lon = lon + math.cos(a) * step * i,
			Lat = lat + math.sin(a) * step * i,
			Size = size * taper,
			Lift = lift,
			Color = color,
		})
	end
	return out
end

-- Shading and highlight caps on the town-facing frame.
local function face(list: { Patch }): { Patch }
	for _, patch in list do
		patch.Face = true
	end
	return list
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

-- cap heights: shading under everything, blotches, spots on the blotches
local SHADE, BASE, TOP = 0.08, 0.1, 0.13

-- the dark lower-right limb (the sprites' shading), under the blotches
local function shade(color: Color3): { Patch }
	return face({
		{ Lon = 56, Lat = -4, Size = 20, Lift = SHADE, Color = color },
		{ Lon = 42, Lat = -36, Size = 20, Lift = SHADE, Color = color },
		{ Lon = 10, Lat = -56, Size = 18, Lift = SHADE, Color = color },
	})
end

-- the pale top-left highlight
local function highlight(color: Color3): { Patch }
	return face({ { Lon = -34, Lat = 36, Size = 6, Lift = TOP, Color = color } })
end

Planets.Specs = {
	{
		-- the huge ringed gas giant right of the mountain, on the cool side (planet09 / planet01)
		Name = "PlanetViolet",
		Az = 35,
		Dist = 1500,
		Elev = 8.5,
		Size = 11.5,
		Roll = 12,
		Lean = 26,
		Body = P.Violet,
		Rim = P.RimViolet,
		RimTransparency = 0.75,
		Patches = concat(
			shade(P.VioletShade),
			-- bands: dark, light, dark, light (blotchy rows of overlapping caps)
			row(34, { -32, -16, 0, 16, 32 }, 9, BASE, P.VioletDeep),
			row(13, { -38, -22, -6, 10, 26 }, 9, BASE, P.Lilac),
			row(-10, { -26, -10, 6, 22 }, 9, BASE, P.VioletDeep),
			row(-31, { -18, -2, 14 }, 8, BASE, P.Lilac),
			-- one small mint streak (planet01)
			{ { Lon = -20, Lat = -50, Size = 6, Lift = BASE, Color = P.Mint } },
			highlight(P.LilacPale)
		),
		Ring = { Inner = 1.34, Outer = 1.86, Segments = 16, Color = P.Ring },
	},
	{
		-- the orange-red world left of the mountain, on the warm side (planet02 / planet08)
		Name = "PlanetEmber",
		Az = 322.5,
		Dist = 1500,
		Elev = 9.5,
		Size = 9.5,
		Roll = 0,
		Lean = 0,
		Body = P.Rust,
		Rim = P.RimOrange,
		RimTransparency = 0.75,
		Patches = concat(
			shade(P.EmberShade),
			-- orange, maroon and crimson camouflage streaks, ~30 degrees diagonal
			streak(-58, 4, 30, 4, 14, 11, BASE, P.Orange),
			streak(-24, -38, 30, 4, 14, 11, BASE, P.Orange),
			streak(-44, -24, 30, 3, 13, 9, BASE, P.Maroon),
			streak(-10, 18, 30, 3, 13, 9, BASE, P.Maroon),
			streak(12, -22, 30, 3, 12, 8, BASE, P.Crimson),
			highlight(P.Peach)
		),
	},
	{
		-- the small blue-teal world between the ember world and the west island (planet00 / planet03)
		Name = "PlanetTeal",
		Az = 337.5,
		Dist = 1500,
		Elev = 12,
		Size = 6.5,
		Roll = 0,
		Lean = 0,
		Body = P.Ocean,
		Rim = P.RimCyan,
		RimTransparency = 0.75,
		Patches = concat(
			shade(P.Navy),
			-- deep water
			{
				{ Lon = 8, Lat = 6, Size = 12, Lift = BASE, Color = P.OceanDeep },
				{ Lon = -40, Lat = -40, Size = 10, Lift = BASE, Color = P.OceanDeep },
			},
			-- mint land streaks (~30 degrees diagonal) with green inside
			streak(-60, -4, 30, 4, 14, 11, BASE, P.Mint2),
			streak(-22, -44, 30, 4, 14, 11, BASE, P.Mint2),
			streak(-4, 30, 30, 3, 13, 9, BASE, P.Mint2),
			streak(-48, 4, 30, 2, 14, 6, TOP, P.Leaf),
			streak(-12, -36, 30, 2, 14, 6, TOP, P.Leaf),
			-- a pale cloud wisp and the highlight
			{ { Lon = 28, Lat = 24, Size = 6, Lift = TOP, Color = P.Wisp } },
			highlight(P.Ice)
		),
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

-- Every opaque ball of a planet (body first, then the patches in order).
function Planets.balls(spec: Spec): { Ball }
	local radius = Planets.diameter(spec) / 2
	local faceFrame, spin = Planets.frames(spec)
	local out: { Ball } = {
		{ Name = "Body", Offset = Vector3.zero, Radius = radius, Color = spec.Body },
	}
	for i, patch in spec.Patches do
		local d, r = Planets.capBall(radius, patch.Size, patch.Lift)
		local frame = if patch.Face then faceFrame else spin
		table.insert(out, {
			Name = `Patch{i}`,
			Offset = frame:VectorToWorldSpace(direction(patch.Lon, patch.Lat) * d),
			Radius = r,
			Color = patch.Color,
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
		local p = ball(m, center + b.Offset, 2 * b.Radius, b.Color)
		p.Name = b.Name
		body = body or p
	end
	-- soft glowing halo (the sprites' bright edge), set back behind the body
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
