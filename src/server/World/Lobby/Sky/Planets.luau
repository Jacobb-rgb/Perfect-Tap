--[[
	Sky package: three big planets in the north sky (docs/plans/VISUAL_UPGRADE_PLAN.md,
	package Sky), styled after the Kenney Planets sprites (CC0, docs/art/kenney_refs/planets_kit.jpg):

	  PlanetViolet  a huge violet gas giant with lilac and deep-violet latitude bands, a wavy lilac
	                streak along the equator and a light warm-lilac tilted ring (planet09 / planet01)
	  PlanetEmber   an orange world with interlocking crimson, rust and light-orange camouflage
	                streaks falling to the right (planet02 / planet08)
	  PlanetTeal    a small ice-blue world with teal-mint and deep-blue camouflage (planet00 / planet03)

	Each planet is one big Neon Ball (the body) plus:
	  - camouflage streaks, laid out in rows along latitudes of the planet's tilted spin frame: each
	    streak is a chain of 2-4 low "cap" Balls whose centres sit 0.8 x the smaller cap radius apart
	    (well under half a cap diameter) with +-2 degrees of latitude jitter, the end caps smaller, so
	    neighbours merge into one elongated, tapered, wavy streak instead of a row of dots; a streak of
	    another color often abuts it (1.45 radii further: the two interlock, crossing steeply) and the
	    rest of the row continues after a gap of body color. Caps are 9-11.5 degrees (angular radius)
	    on the camouflaged worlds: with the 40-part budget, 4-8 degree caps would cover only about a
	    quarter of the face, Kenney camouflage covers about half. A cap ball sits so that only a low
	    cap of it pokes out (lift 0.04 of the radius), meeting the body at a steep angle
	    (Planets.MinCrease): no z-fighting, and the outline stays round;
	  - on the gas giant, latitude bands instead: thin Cylinder discs coaxial with the tilted spin
	    axis, each ~1.01-1.03 x the sphere chord at its latitude, showing 7-10% of the radius of rim,
	    alternating lilac and deep violet (planet09's clean bands);
	  - a gloss crescent: one thin translucent Neon Cylinder disc facing the town just in front of the
	    upper-left part of the face. Only its rim outside the curved surface shows, a crescent sliver
	    inside the upper-left limb (Kenney's soft sheen), and a darker shade crescent at the lower right;
	  - a slightly larger translucent Neon rim ball set back behind the body (the sprites' glowing edge);
	  - on the gas giant, a ring of Planets.RingSegments flat blocks around the tilted equator in a
	    light warm lilac, clearly lighter than the body.

	Colors are the sprites' colors AFTER the evening haze: the Atmosphere (LightingConfig.Presets.Surface,
	Density 0.26, Haze 0.9) mixes each far part with its own peach/lavender color, growing with the square
	of the distance. The raw Neon tones below were solved per planet against the preview's fog, ACES and
	color-correction chain, so that, seen from the plaza, they come out as the sprite tones: Ember orange
	#E87A2E / crimson #C82848 / rust #8C3018, Teal ice #CFEFFF / teal #2FC9B5 / deep blue (kept on the
	cyan side, never a blue that hazes into violet), Violet base #7A3CE0 / lilac #B48CFF / deep #3C1490
	(tests/LobbySky.spec.luau checks the hazed hues). Under the thinner Atmosphere requested from the
	Lighting owner (Density ~0.19, Haze ~0.5) they come out closer still to the sprite tones.

	Distance: 700-800 studs. The haze grows with the square of the distance: at 1500 studs only ~40% of a
	color survives (a salmon-pink "orange", a lavender "deep blue"), at 700-800 studs ~75% does. The
	planets still hang 2x farther out than the massif and the floating islands and 1.6x farther than the
	airship.

	Placement (checked against the real silhouettes of both preview cameras, the ring included): the
	ember world on the warm side left of the west island (hero: top left, wholly in the frame; spawn:
	above the SHOP), the gas giant on the cool side right of the east island and its waterfall (spawn:
	wholly visible; hero: bleeding off the right edge, a deliberate crop), and the small teal world just
	left of the massif peak, above it (spawn only: the hero frame's sky ends below the massif's top,
	so any spot the hero sees there hides behind the mountain from the spawn).

	Streaming: Persistent. StreamingTargetRadius is 384 studs, so with LevelOfDetail = StreamingMesh a
	planet 700+ studs out would never stream in and players would only ever see its low-detail imposter
	mesh (no Neon glow, no translucent rim, smeared blotches). The three planets are 120 parts at most,
	so they are cheap enough to keep streamed in (deviation from the brief's "Lod", recorded in
	docs/plans/VISUAL_UPGRADE_PLAN.md). Unreachable decoration: no collision, no raycasts, no touch, no
	shadows, <= 40 parts each, no lights.

	Pure builder: Instance creation only, deterministic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local NEON = Enum.Material.Neon
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Local palette: raw Neon tones that come out as the Kenney sprite tones after the evening haze
-- at each planet's distance and bearing (see the header; the hazed result is in the comment).
local P = {
	-- planet09 / planet01: violet gas giant (north-east, lavender haze, 700 studs)
	Violet = rgb(65, 30, 115), -- -> #844CE6 (base #7A3CE0)
	Lilac = rgb(80, 75, 250), -- -> #B38EFF (lilac streak #B48CFF)
	VioletDeep = rgb(30, 0, 65), -- -> #503AB0 (deep #3C1490)
	Ring = rgb(120, 95, 235), -- -> #D8A8FF, a light warm lilac, lighter than the body
	RimViolet = rgb(110, 60, 255),
	-- planet02 / planet08: orange world (north-west, warm haze, 800 studs):
	-- one hue, the bands only 10-15% darker than the body (no pepperoni spots)
	Orange = rgb(135, 65, 0), -- -> #FF8F55 (orange #E87A2E)
	Crimson = rgb(118, 57, 0), -- 12% darker bands
	Rust = rgb(112, 54, 0), -- 15% darker bands
	Flame = rgb(255, 100, 25), -- (the light orange streaks of round 1)
	RimOrange = rgb(255, 70, 0),
	-- (round 2) the ember body leans crimson-rust with bright Flame streaks
	EmberBody = rgb(122, 46, 6), -- crimson-rust body
	EmberBand = rgb(104, 39, 5), -- 15% darker bands
	EmberBandDark = rgb(98, 37, 5), -- 20% darker bands
	-- planet00 / planet03: ice-blue world (north, half-warm haze, 760 studs): every blue stays
	-- cyan-blue through the haze (no deep navy that turns lavender)
	Ice = rgb(100, 170, 255), -- -> #D0EEFF (ice #CFEFFF)
	Teal = rgb(87, 148, 222), -- the ice world's bands: its own hue, 13% darker
	Seafoam = rgb(92, 156, 234), -- 8% darker
	DeepBlue = rgb(84, 143, 214), -- 16% darker
	RimCyan = rgb(0, 110, 170), -- (round 2: darker, the world no longer reads near-white)
	-- (round 2) the teal world: a teal body, darker deep-blue bands, ice
	-- only as polar caps
	TealBody = rgb(36, 124, 200), -- a saturated teal-blue body (it stays blue through the haze)
	TealBand = rgb(32, 109, 176), -- 12% darker
	TealDeep = rgb(29, 101, 164), -- 18% darker
	-- (round 3) a real teal / seafoam world with darker deep-blue bands and
	-- one ice highlight band; a saturated orange ember world with crimson
	-- bands and small glowing flame spots
	Seafoam3 = rgb(0, 170, 175),
	SeaBand = rgb(0, 120, 150), -- deep blue-teal, darker
	SeaDeep = rgb(0, 104, 140), -- deep blue, darker still
	IceBand = rgb(150, 230, 240),
	EmberOrange = rgb(245, 72, 6),
	EmberCrimson = rgb(170, 30, 36),
	EmberCrimsonDark = rgb(140, 22, 30),
	EmberFlame = rgb(255, 170, 60),
}

export type Patch = {
	Lon: number, -- degrees, 0 = the point facing the town, + = to the viewer's right
	Lat: number, -- degrees, + = up (on the tilted spin frame)
	Size: number, -- angular radius of the cap on the body (degrees)
	Lift: number, -- how far the cap pokes out of the body at its middle (fraction of the radius)
	Color: Color3,
}

-- A latitude band: a thin Cylinder disc coaxial with the spin axis.
export type Band = {
	Lat: number, -- degrees
	Width: number, -- visible width of the band (fraction of the radius)
	Color: Color3,
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
	Roll: number, -- spin axis tilt seen from the town (degrees, + = top to the viewer's left: the streaks and
	-- the ring rise to the right; - = they fall to the right)
	Lean: number, -- spin axis leaned toward the town (degrees): opens the ring and the bands
	Body: Color3,
	Rim: Color3,
	RimTransparency: number,
	Patches: { Patch },
	Bands: { Band }?,
	Ring: Ring?,
	Terminator: boolean?, -- a darker disc on the side away from the sun (the night side)
}

-- A ball of a planet in world orientation: `Offset` from the planet center.
export type Ball = {
	Name: string,
	Offset: Vector3,
	Radius: number,
	Color: Color3,
}

-- A flat disc (a Roblox Cylinder, axis = the CFrame's X axis) in world space.
export type Disc = {
	Name: string,
	CFrame: CFrame,
	Diameter: number,
	Thickness: number,
	Color: Color3,
	Transparency: number,
}

local Planets = {}

Planets.Palette = P

-- the point the planets face (between the spawn and the plaza, eye height)
Planets.Town = Vector3.new(0, 30, 30)

-- Max parts per planet (mobile budget).
Planets.MaxParts = 40
-- A cap meets the body (or another cap of another color) at least this steeply (degrees).
Planets.MinCrease = 20
-- Caps: the largest angular radius (degrees) and how far a cap pokes out of the body (fraction of
-- the radius; <= 0.04 keeps the outline round, the creases stay >= MinCrease up to MaxCap).
Planets.MaxCap = 12
-- (round 3: 0.06, fewer and larger caps: the streaks read)
Planets.CapLift = 0.06
-- (round 3) a band disc never reaches more than this past the body (x R): no
-- band edge sticks out past the silhouette
Planets.BandReach = 1.02
--[[
	Camouflage rows: along a row, the caps of one streak sit RunSpacing x the smaller cap radius
	apart (well under half a cap diameter, so they merge into one elongated streak), a streak of
	another color that touches the one before it starts TouchSpacing radii further (the two
	interlock but cross steeply), and a streak after a gap of body color GapSpacing radii further.
	The end caps of a streak of 3+ are EndTaper smaller.
]]
Planets.RunSpacing = 0.8
Planets.TouchSpacing = 1.45
Planets.GapSpacing = 2.6
Planets.EndTaper = 0.8
-- a band disc's rim comes out of the surface at least this steeply (degrees): only its pole-side
-- part stands outside, the equator side stays inside the body
Planets.MinBandCrease = 10
--[[
	The rim: a translucent Neon ball RimScale x the body, its center pushed
	RimBack x the radius away from the town. Its front is hidden inside the
	body (it never veils the face) and it comes out of the body right at the
	silhouette, crossing it steeply: only a thin glowing edge shows.
]]
Planets.RimScale = 1.07
Planets.RimBack = 0.3
-- The ring of the gas giant.
Planets.RingSegments = 28
--[[
	Gloss and shade crescents: a thin translucent Neon disc facing the town, Offset x the radius from
	the face center toward the upper left (gloss) or the lower right (shade), Radius x the radius
	wide, Depth x the radius in front of the center. The curved surface hides it except where the
	surface falls behind it: between sqrt(1 - Depth^2) and Offset + Radius from the center, a thin
	crescent just inside the limb.
]]
Planets.Crescent = { Offset = 0.46, Radius = 0.5, Depth = 0.6, Thickness = 0.006 }
-- the terminator (night side) disc: offset toward the viewer's right (away
-- from the western sun), wider and set back further than the crescents
Planets.Terminator = { Offset = 0.4, Radius = 0.56, Depth = 0.55, Darken = 0.5, Transparency = 0.45 }
Planets.GlossLighten = 0.45
Planets.GlossTransparency = 0.45
Planets.ShadeDarken = 0.45
Planets.ShadeTransparency = 0.5

-- latitude jitter along a row (degrees, within +-2): wavy streak edges
local JITTER = { 0, 2, -1.5, 1, -2 }

export type Run = {
	Count: number, -- caps in this streak
	Color: Color3,
	Touch: boolean?, -- the next streak abuts this one (else a gap of body color follows)
}

-- A row of camouflage streaks along one latitude, centered on longitude `Offset`.
export type Row = {
	Lat: number,
	Offset: number,
	Runs: { Run },
}

--[[
	The caps of camouflage rows (cap radius `size`): each row is centered on its Offset, its
	streaks follow each other toward the viewer's right, the caps of one streak RunSpacing radii
	apart along the arc, the next streak TouchSpacing (touching) or GapSpacing (after a gap)
	radii further; every cap jittered off the row's latitude.
]]
local function rows(list: { Row }, size: number): { Patch }
	local out: { Patch } = {}
	local function capSize(run: Run, j: number): number
		local tapered = run.Count > 2 and (j == 1 or j == run.Count)
		return if tapered then size * Planets.EndTaper else size
	end
	-- arc from one cap of a streak to the next
	local function step(run: Run, j: number): number
		return Planets.RunSpacing * math.min(capSize(run, j), capSize(run, j + 1))
	end
	for _, row in list do
		local perDegree = 1 / math.cos(math.rad(row.Lat)) -- arc degrees -> longitude degrees
		local span = 0
		for i, run in row.Runs do
			for j = 1, run.Count - 1 do
				span += step(run, j) * perDegree
			end
			if i < #row.Runs then
				span += size * (if run.Touch then Planets.TouchSpacing else Planets.GapSpacing) * perDegree
			end
		end
		local at = row.Offset - span / 2
		local k = 0
		for i, run in row.Runs do
			for j = 1, run.Count do
				table.insert(out, {
					Lon = at,
					Lat = row.Lat + JITTER[k % #JITTER + 1],
					Size = capSize(run, j),
					Lift = Planets.CapLift,
					Color = run.Color,
				})
				k += 1
				if j < run.Count then
					at += step(run, j) * perDegree
				end
			end
			if i < #row.Runs then
				at += size * (if run.Touch then Planets.TouchSpacing else Planets.GapSpacing) * perDegree
			end
		end
	end
	return out
end

Planets.Specs = {
	{
		-- the ringed gas giant high in the spawn's upper-right sky, left of the
		-- east island and its waterfall (above the hero frame's top edge: the
		-- hero's sky right of the massif is too narrow for it)
		Name = "PlanetViolet",
		-- (round 2: lower and further east: in the hero frame's top-right sky
		-- right of the massif, and clear of the east island's waterfall from
		-- the spawn)
		-- (round 3: higher and a little further east: the east cliff cut its
		-- lower half and the east island's fall crossed its face; from the
		-- town and the spawn its centre and bottom now show over everything)
		Az = 38,
		Dist = 700,
		Elev = 10,
		Size = 4.6,
		Roll = 18,
		Lean = 26,
		Body = P.Violet,
		Rim = P.RimViolet,
		RimTransparency = 0.6,
		-- clean latitude bands (planet09), deep and lilac by turns
		Bands = {
			{ Lat = 30, Width = 0.07, Color = P.VioletDeep },
			{ Lat = 14, Width = 0.07, Color = P.Lilac },
			{ Lat = -14, Width = 0.09, Color = P.VioletDeep },
			{ Lat = -30, Width = 0.07, Color = P.Lilac },
		},
		-- a wavy lilac streak along the equator
		Patches = rows({
			{ Lat = 2, Offset = -8, Runs = { { Count = 3, Color = P.Lilac } } },
		}, 10),
		Ring = { Inner = 1.3, Outer = 1.72, Segments = Planets.RingSegments, Color = P.Ring },
	},
	{
		-- the orange world left of the massif in the hero's upper-left sky (out of
		-- the sunset sector): one hue with soft darker latitude bands, a darker
		-- terminator on the side away from the sun and a thin glowing rim shell
		Name = "PlanetEmber",
		-- (round 2: up in the spawn's empty top-centre sky, 14 degrees higher:
		-- clear of SHOP, the wheel and the terraces, wholly above the hero frame)
		-- (round 3: higher and farther (the same apparent size): clear sky
		-- between it, the teal world and the balloon, no beads on a string)
		-- (2026-10-25: the golden dragon's TERRA FORGE sign fills the spawn's
		-- top-centre sky: the world moved left of it and a little lower, 358/26
		-- -> 331/22, between the teal world and the balloon)
		Az = 331,
		Dist = 780,
		Elev = 22,
		Size = 5.75,
		Roll = -26,
		Lean = 18,
		Body = P.EmberOrange,
		Rim = P.RimOrange,
		RimTransparency = 0.66,
		Bands = {
			{ Lat = 40, Width = 0.1, Color = P.EmberCrimson },
			{ Lat = -18, Width = 0.12, Color = P.EmberCrimsonDark },
			{ Lat = -40, Width = 0.1, Color = P.EmberCrimson },
		},
		-- small glowing flame spots across the orange face
		Patches = rows({
			{ Lat = 10, Offset = -6, Runs = { { Count = 3, Color = P.EmberFlame } } },
			{ Lat = -28, Offset = 12, Runs = { { Count = 2, Color = P.EmberFlame } } },
		}, 10),
		Terminator = true,
	},
	{
		-- the small ice-blue world high in the spawn's upper-left sky, well off the
		-- spawn-to-forge axis, with soft single-hue bands
		Name = "PlanetTeal",
		-- (round 2: up-left of the balloon from the spawn, more than a
		-- diameter clear of it; above the hero frame)
		-- (round 3: farther out to the left and farther (the same apparent
		-- size): 20 degrees of clear sky between it and the balloon; the
		-- spawn frame's top edge drops toward its left side, so it stays at
		-- the balloon's height there)
		Az = 316,
		Dist = 760,
		Elev = 20,
		Size = 4.65,
		Roll = -14,
		Lean = 16,
		Body = P.Seafoam3,
		Rim = P.RimCyan,
		RimTransparency = 0.66,
		-- darker deep-blue bands, ice only as one highlight band
		Bands = {
			{ Lat = 34, Width = 0.12, Color = P.SeaDeep },
			{ Lat = 12, Width = 0.1, Color = P.IceBand },
			{ Lat = -14, Width = 0.12, Color = P.SeaBand },
			{ Lat = -34, Width = 0.1, Color = P.SeaDeep },
		},
		Patches = {},
		Terminator = true,
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
Planets.direction = direction

-- The town-facing frame and the tilted spin frame (streaks, bands, ring) of a planet.
-- (LookVector of the face frame = toward the town; the spin frame's Y axis is the spin axis.)
function Planets.frames(spec: Spec): (CFrame, CFrame)
	local center = Planets.center(spec)
	local faceFrame = CFrame.lookAt(center, Planets.Town)
	local spin = faceFrame * CFrame.Angles(0, 0, math.rad(-spec.Roll)) * CFrame.Angles(math.rad(-spec.Lean), 0, 0)
	return faceFrame, spin
end

-- Every ball of a planet (body first, then the caps in order).
function Planets.balls(spec: Spec): { Ball }
	local radius = Planets.diameter(spec) / 2
	local _, spin = Planets.frames(spec)
	local out: { Ball } = {
		{ Name = "Body", Offset = Vector3.zero, Radius = radius, Color = spec.Body },
	}
	for i, patch in spec.Patches do
		local d, r = Planets.capBall(radius, patch.Size, patch.Lift)
		table.insert(out, {
			Name = `Patch{i}`,
			Offset = spin:VectorToWorldSpace(direction(patch.Lon, patch.Lat) * d),
			Radius = r,
			Color = patch.Color,
		})
	end
	return out
end

--[[
	The latitude band discs. A band at latitude `Lat` shows `Width` (x R) of its rim: the disc's
	pole-side face sits at R sin(Lat) +- Width/2 (toward the pole) and its radius is the sphere's
	at the band's equator-side edge (R sin(Lat) -+ Width/2), so the rim comes out of the surface
	there and stands just outside it up to the pole-side face: a clean band ~1.01-1.03 x the chord
	at its latitude. The disc reaches BandInside x R further toward the equator, inside the body.
]]
Planets.BandInside = 0.05
function Planets.bandDiscs(spec: Spec): { Disc }
	local out: { Disc } = {}
	local bands = spec.Bands
	if not bands then
		return out
	end
	local radius = Planets.diameter(spec) / 2
	local _, spin = Planets.frames(spec)
	for i, band in bands do
		local side = if band.Lat >= 0 then 1 else -1
		local mid = math.abs(math.sin(math.rad(band.Lat)))
		local pole = (mid + band.Width / 2) * radius -- the pole-side face (height along the axis)
		local edge = (mid - band.Width / 2) * radius -- where the rim comes out of the surface
		local thickness = (band.Width + Planets.BandInside) * radius
		local discRadius = math.sqrt(radius * radius - edge * edge) * 1.004
		-- (round 3) its outermost corner (the pole-side face) stays within BandReach x R
		local reach = Planets.BandReach * radius
		discRadius = math.min(discRadius, math.sqrt(math.max(0, reach * reach - pole * pole)))
		table.insert(out, {
			Name = `Band{i}`,
			-- a Roblox cylinder's axis is its X axis: turn it onto the spin axis (Y)
			CFrame = spin * CFrame.new(0, side * (pole - thickness / 2), 0) * CFrame.Angles(0, 0, math.pi / 2),
			Diameter = 2 * discRadius,
			Thickness = thickness,
			Color = band.Color,
			Transparency = 0,
		})
	end
	return out
end

-- The gloss (upper left) and shade (lower right) crescents.
function Planets.crescents(spec: Spec): { Disc }
	local radius = Planets.diameter(spec) / 2
	local faceFrame = Planets.frames(spec)
	local k = Planets.Crescent
	local out: { Disc } = {}
	local function disc(name: string, sx: number, sy: number, color: Color3, transparency: number)
		local offset = Vector3.new(sx, sy, 0).Unit * k.Offset * radius
		-- the face frame looks at the town (-Z local): the disc sits Depth x R toward the town,
		-- its axis (local X after the turn) pointing at the town
		local cf = faceFrame * CFrame.new(offset.X, offset.Y, -k.Depth * radius) * CFrame.Angles(0, math.pi / 2, 0)
		table.insert(out, {
			Name = name,
			CFrame = cf,
			Diameter = 2 * k.Radius * radius,
			Thickness = math.max(0.3, k.Thickness * radius),
			Color = color,
			Transparency = transparency,
		})
	end
	-- the face frame's +X is the viewer's left
	disc("Gloss", 1, 1, spec.Body:Lerp(WHITE, Planets.GlossLighten), Planets.GlossTransparency)
	disc("Shade", -1, -1, spec.Body:Lerp(BLACK, Planets.ShadeDarken), Planets.ShadeTransparency)
	if spec.Terminator then
		-- the night side: a wider darker crescent on the side away from the low
		-- western sun (the viewer's right), behind the shade
		local t = Planets.Terminator
		local cf = faceFrame * CFrame.new(-t.Offset * radius, 0, -t.Depth * radius) * CFrame.Angles(0, math.pi / 2, 0)
		table.insert(out, {
			Name = "Terminator",
			CFrame = cf,
			Diameter = 2 * t.Radius * radius,
			Thickness = math.max(0.3, k.Thickness * radius),
			Color = spec.Body:Lerp(BLACK, t.Darken),
			Transparency = t.Transparency,
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

local function disc(parent: Instance, d: Disc): Part
	local p = Style.block(
		parent,
		d.CFrame,
		Vector3.new(d.Thickness, d.Diameter, d.Diameter),
		d.Color,
		NEON,
		Kit.far({ Shape = CYLINDER, Transparency = d.Transparency })
	)
	p.Name = d.Name
	return p
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
	for _, d in Planets.bandDiscs(spec) do
		disc(m, d)
	end
	for _, d in Planets.crescents(spec) do
		disc(m, d)
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
		local length = 2 * outer * math.tan(math.pi / n) + 0.5
		local thickness = math.max(1.5, radius * 0.02)
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
