--[[
	Sky package: three big planets in the north sky (docs/plans/VISUAL_UPGRADE_PLAN.md,
	package Sky), styled after the Kenney Planets sprites (CC0, docs/art/kenney_refs/planets_kit.jpg):

	  PlanetViolet  a huge banded violet gas giant with a tilted two-band ring (planet09 / planet01)
	  PlanetTeal    a teal-green-blue world with mint and green blotches and ice caps (planet00 / planet03)
	  PlanetEmber   a small rust-red world with orange and maroon blotches (planet02 / planet08)

	Each planet is one big Ball (the body), a set of slightly larger
	"patch" Balls whose centers sit off the body's center so only a cap of
	each pokes out of the surface (the cap is a round blotch in a second or
	third color; overlapping caps make the irregular camouflage blotches of
	the sprites, caps on the spin axis make latitude bands), a slightly
	larger translucent Neon ball for the soft glowing rim, and for the
	gas giant a ring of thin flat blocks (two concentric polygon bands).

	They hang 1500-1550 studs out (the near end of the 1500-3000 band: the
	evening Atmosphere hazes far parts toward its Color/Decay, farther out
	they fade to ghosts), high over the sea from the north-west to the
	north-east so they frame the mountain in the hero and spawn views, far
	from the low west sun (bearing ~262): the violet giant left of the
	mountain, the small ember world high over the peak, the teal world
	behind the east floating island. Positions are given as bearing,
	elevation and angular size seen from the plaza, so the size on screen
	stays put if a distance changes. Unreachable decoration: no collision,
	no raycasts, no touch, no shadows, Lod streaming, <= 40 parts each.
	Pure builder: Instance creation only, deterministic from `rng`.
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

-- Local palette after the Kenney Planets sprites. The planets are Neon
-- (they glow like moons; at 1500+ studs the evening Atmosphere hazes
-- everything toward its Color/Decay, so plain plastic would fade to a ghost),
-- which is why the part colors are deeper and more saturated than the sprites:
-- glow + haze bring them back to the sprites' look.
local P = {
	-- planet09 / planet01: violet gas giant (north-west, warm haze)
	Violet = rgb(70, 10, 200),
	VioletDeep = rgb(20, 0, 120),
	VioletLight = rgb(130, 70, 230),
	Lilac = rgb(140, 106, 204),
	Mint = rgb(40, 190, 140),
	RingLight = rgb(176, 162, 212),
	RingDark = rgb(78, 24, 174),
	RimViolet = rgb(156, 118, 222),
	-- planet00 / planet03: teal-green-blue world (north-east, cool haze)
	Ocean = rgb(10, 108, 168),
	OceanDeep = rgb(6, 52, 140),
	Teal = rgb(80, 200, 150),
	Leaf = rgb(10, 150, 30),
	Ice = rgb(150, 196, 184),
	RimCyan = rgb(110, 190, 200),
	-- planet02 / planet08: rust-red world (north, high)
	Rust = rgb(170, 16, 8),
	Maroon = rgb(110, 6, 10),
	Orange = rgb(212, 70, 6),
	Peach = rgb(226, 142, 20),
	RimOrange = rgb(236, 132, 30),
}

export type Patch = {
	Lon: number, -- degrees, 0 = the point facing the town, + = to the viewer's right
	Lat: number, -- degrees on the planet's (tilted) spin axis, + = up
	Size: number, -- angular radius of the blotch on the surface (degrees)
	Lift: number, -- how far the patch pokes out at its middle (fraction of the radius)
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
	Roll: number, -- spin axis tilt seen from the town (degrees, + = top to the right)
	Lean: number, -- spin axis leaned toward the town (degrees): opens the ring
	Body: Color3,
	Rim: Color3,
	RimTransparency: number,
	Patches: { Patch },
	Rings: { Ring }?,
}

local Planets = {}

Planets.Palette = P

-- the point the planets face (between the spawn and the plaza, eye height)
Planets.Town = Vector3.new(0, 30, 30)

-- patch heights: base blotches, blotches on blotches, spots on top
local L1, L2, L3 = 0.025, 0.048, 0.07
-- streaks that sit between the bands use their own height
local LS = 0.036
-- small spots on top of everything (lakes, wisps)
local L4 = 0.09

Planets.Specs = {
	{
		-- the huge ringed gas giant left of the mountain (planet09 / planet01)
		Name = "PlanetViolet",
		Az = 326,
		Dist = 1500,
		Elev = 10,
		Size = 20,
		Roll = -20,
		Lean = 18,
		Body = P.Violet,
		Rim = P.RimViolet,
		RimTransparency = 0.88,
		Patches = {
			-- latitude bands: nested caps around both poles
			{ Lon = 0, Lat = 90, Size = 64, Lift = L1, Color = P.VioletLight },
			{ Lon = 0, Lat = 90, Size = 45, Lift = L2, Color = P.VioletDeep },
			{ Lon = 0, Lat = 90, Size = 22, Lift = L3, Color = P.Lilac },
			{ Lon = 0, Lat = -90, Size = 70, Lift = L1, Color = P.VioletDeep },
			{ Lon = 0, Lat = -90, Size = 48, Lift = L2, Color = P.Mint },
			-- long streaks along the equator: each two or three overlapping
			-- caps in a row (between the band lifts: no flicker)
			{ Lon = -44, Lat = 8, Size = 12, Lift = LS, Color = P.Lilac },
			{ Lon = -30, Lat = 6, Size = 13, Lift = LS, Color = P.Lilac },
			{ Lon = -16, Lat = 9, Size = 11, Lift = LS, Color = P.Lilac },
			{ Lon = 12, Lat = 3, Size = 11, Lift = LS, Color = P.Lilac },
			{ Lon = 26, Lat = 6, Size = 12, Lift = LS, Color = P.Lilac },
			{ Lon = -6, Lat = -10, Size = 10, Lift = LS, Color = P.Mint },
			{ Lon = 8, Lat = -12, Size = 9, Lift = LS, Color = P.Mint },
			{ Lon = 38, Lat = -14, Size = 9, Lift = LS, Color = P.VioletLight },
		},
		Rings = {
			{ Inner = 1.3, Outer = 1.5, Segments = 12, Color = P.RingDark },
			{ Inner = 1.56, Outer = 1.96, Segments = 12, Color = P.RingLight },
		},
	},
	{
		-- the teal-green-blue world behind the east floating island (planet00 / planet03)
		Name = "PlanetTeal",
		Az = 27,
		Dist = 1500,
		Elev = 12.5,
		Size = 15,
		Roll = 14,
		Lean = 0,
		Body = P.Ocean,
		Rim = P.RimCyan,
		RimTransparency = 0.88,
		Patches = {
			-- deep water
			{ Lon = 6, Lat = -2, Size = 24, Lift = L1, Color = P.OceanDeep },
			{ Lon = -60, Lat = -36, Size = 14, Lift = L1, Color = P.OceanDeep },
			-- mint land masses (several overlapping caps each: camouflage blotches)
			{ Lon = -32, Lat = 20, Size = 24, Lift = L2, Color = P.Teal },
			{ Lon = -6, Lat = 36, Size = 16, Lift = L2, Color = P.Teal },
			{ Lon = -20, Lat = 44, Size = 12, Lift = L2, Color = P.Teal },
			{ Lon = -50, Lat = 22, Size = 12, Lift = L2, Color = P.Teal },
			{ Lon = -46, Lat = -4, Size = 15, Lift = L2, Color = P.Teal },
			{ Lon = 30, Lat = -20, Size = 26, Lift = L2, Color = P.Teal },
			{ Lon = 18, Lat = -6, Size = 10, Lift = L2, Color = P.Teal },
			{ Lon = 50, Lat = 8, Size = 15, Lift = L2, Color = P.Teal },
			{ Lon = 8, Lat = -40, Size = 16, Lift = L2, Color = P.Teal },
			{ Lon = 46, Lat = -36, Size = 12, Lift = L2, Color = P.Teal },
			-- green inside the mint
			{ Lon = -30, Lat = 18, Size = 13, Lift = L3, Color = P.Leaf },
			{ Lon = 33, Lat = -24, Size = 14, Lift = L3, Color = P.Leaf },
			{ Lon = -3, Lat = 33, Size = 8, Lift = L3, Color = P.Leaf },
			{ Lon = 52, Lat = 4, Size = 8, Lift = L3, Color = P.Leaf },
			{ Lon = -44, Lat = -2, Size = 7, Lift = L3, Color = P.Leaf },
			-- lakes and pale cloud wisps on top
			{ Lon = -18, Lat = 26, Size = 5, Lift = L4, Color = P.Ocean },
			{ Lon = 22, Lat = -30, Size = 5, Lift = L4, Color = P.Ocean },
			{ Lon = 14, Lat = 12, Size = 7, Lift = L4, Color = P.Ice },
			{ Lon = -40, Lat = 40, Size = 6, Lift = L4, Color = P.Ice },
			{ Lon = 36, Lat = 30, Size = 6, Lift = L4, Color = P.Ice },
			-- ice caps
			{ Lon = 0, Lat = 90, Size = 22, Lift = L3, Color = P.Ice },
			{ Lon = 0, Lat = -90, Size = 18, Lift = L3, Color = P.Ice },
		},
	},
	{
		-- the small rust-red world high over the mountain (planet02 / planet08)
		Name = "PlanetEmber",
		Az = 352,
		Dist = 1550,
		Elev = 19,
		Size = 9,
		Roll = -10,
		Lean = 0,
		Body = P.Rust,
		Rim = P.RimOrange,
		RimTransparency = 0.86,
		Patches = {
			-- maroon lowlands
			{ Lon = -22, Lat = 22, Size = 30, Lift = L1, Color = P.Maroon },
			{ Lon = 30, Lat = -16, Size = 26, Lift = L1, Color = P.Maroon },
			{ Lon = -50, Lat = -30, Size = 16, Lift = L1, Color = P.Maroon },
			{ Lon = 50, Lat = 32, Size = 14, Lift = L1, Color = P.Maroon },
			-- orange highlands
			{ Lon = 8, Lat = 26, Size = 22, Lift = L2, Color = P.Orange },
			{ Lon = -36, Lat = -20, Size = 20, Lift = L2, Color = P.Orange },
			{ Lon = 42, Lat = 20, Size = 14, Lift = L2, Color = P.Orange },
			{ Lon = -10, Lat = -42, Size = 14, Lift = L2, Color = P.Orange },
			{ Lon = 24, Lat = 2, Size = 10, Lift = L2, Color = P.Orange },
			-- peach peaks
			{ Lon = 4, Lat = 30, Size = 10, Lift = L3, Color = P.Peach },
			{ Lon = -30, Lat = -24, Size = 9, Lift = L3, Color = P.Peach },
			{ Lon = 40, Lat = 22, Size = 6, Lift = L3, Color = P.Peach },
			{ Lon = -14, Lat = -40, Size = 6, Lift = L3, Color = P.Peach },
			-- rust holes and dark spots on top
			{ Lon = -6, Lat = 2, Size = 12, Lift = L3, Color = P.Rust },
			{ Lon = 12, Lat = 30, Size = 4, Lift = L4, Color = P.Maroon },
			{ Lon = -34, Lat = -18, Size = 4, Lift = L4, Color = P.Maroon },
		},
	},
} :: { Spec }

-- Max parts per planet (mobile budget).
Planets.MaxParts = 40

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

-- Unit direction on the planet: lon/lat in degrees, 0/0 faces the town (-Z).
local function direction(lon: number, lat: number): Vector3
	local lo, la = math.rad(lon), math.rad(lat)
	return Vector3.new(-math.sin(lo) * math.cos(la), math.sin(la), -math.cos(lo) * math.cos(la))
end

local function ball(
	parent: Instance,
	position: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	return Style.block(
		parent,
		CFrame.new(position),
		Vector3.new(diameter, diameter, diameter),
		color,
		material,
		Kit.far({ Shape = BALL, Transparency = transparency or 0 })
	)
end

function Planets.planet(parent: Instance, spec: Spec, rng: Rng.Rng): Model
	local m = Style.model(spec.Name, parent)
	local center = Planets.center(spec)
	local diameter = Planets.diameter(spec)
	local radius = diameter / 2
	-- facing the town; the spin frame carries the tilt (bands and ring)
	local face = CFrame.lookAt(center, Planets.Town)
	local spin = face * CFrame.Angles(0, 0, math.rad(spec.Roll)) * CFrame.Angles(math.rad(-spec.Lean), 0, 0)

	local body = ball(m, center, diameter, spec.Body, NEON)
	body.Name = "Body"
	for i, patch in spec.Patches do
		local d, r = Planets.capBall(radius, patch.Size, patch.Lift)
		local at = spin:PointToWorldSpace(direction(patch.Lon, patch.Lat) * d)
		local p = ball(m, at, 2 * r, patch.Color, NEON)
		p.Name = `Patch{i}`
	end
	-- soft glowing rim (the sprites' bright edge)
	local rim = ball(m, center, diameter * 1.1, spec.Rim, NEON, spec.RimTransparency)
	rim.Name = "Rim"

	-- ring bands: thin flat blocks around the spin axis
	local rings: { Ring } = spec.Rings or {}
	for k, ring in rings do
		local inner, outer = ring.Inner * radius, ring.Outer * radius
		local mid = (inner + outer) / 2
		local n = ring.Segments
		local length = 2 * outer * math.tan(math.pi / n)
		local thickness = math.max(1.5, radius * 0.008)
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * 2 * math.pi
			local cf = spin * CFrame.Angles(0, a, 0) * CFrame.new(0, (k - 1) * 0.6, -mid)
			local seg =
				Style.block(m, cf, Vector3.new(length, thickness, outer - inner), Style.vary(ring.Color, rng, 0.02), NEON, Kit.far())
			seg.Name = `Ring{k}`
		end
	end

	m.PrimaryPart = body
	Style.streaming(m, "Lod")
	return m
end

-- All planets under one Model "Planets".
function Planets.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Planets", parent)
	for _, spec in Planets.Specs do
		Planets.planet(m, spec, Rng.new(`Planets/{spec.Name}/{rng:int(1, 2147483646)}`))
	end
	return m
end

return Planets
