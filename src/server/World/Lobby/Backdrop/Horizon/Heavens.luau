--[[
	The sky over the far sea (owner 2026-10-17: "on the sky just clouds, more
	of those planets and some constellations"):
	  MorePlanets     five more Kenney Planets worlds in the south and east
	                  sky, built by the Sky package's planet builder
	                  (Sky/Planets.planet): a green-and-blue garden world, a
	                  ringed desert world, a grey cratered moon, a mint world
	                  with violet swirls, a small rose world
	  Constellations  four star pictures of the game's tools high in the
	                  dusk: the Pickaxe, the Anvil, the Gem, the Hammer
	  SkyClouds       puffy cumulus over the south and east sea, under the
	                  planets
	Everything keeps out of the Sky package's windows (its three planets,
	the airship, the balloon, the sunset). Neon only, no lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Planets = require(script.Parent.Parent.Parent.Sky.Planets)
local Place = require(script.Parent.Place)

local C = Style.C
local NEON = Enum.Material.Neon

local Heavens = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------- planets

-- Camouflage streaks: rows of caps along latitudes (like Sky/Planets'
-- rows, simpler): each run is `Count` caps RunSpacing radii apart.
type Run = { Count: number, Color: Color3 }
type Row = { Lat: number, Offset: number, Runs: { Run } }
local function streaks(list: { Row }, size: number): { Planets.Patch }
	local out: { Planets.Patch } = {}
	for _, row in list do
		local per = 1 / math.cos(math.rad(row.Lat))
		local count = 0
		for _, run in row.Runs do
			count += run.Count
		end
		local span = (count - 1 + (#row.Runs - 1)) * size * Planets.RunSpacing * per
		local at = row.Offset - span / 2
		local k = 0
		for _, run in row.Runs do
			for j = 1, run.Count do
				local tapered = run.Count > 2 and (j == 1 or j == run.Count)
				table.insert(out, {
					Lon = at,
					Lat = row.Lat + (if k % 2 == 0 then 1.5 else -1.5),
					Size = if tapered then size * Planets.EndTaper else size,
					Lift = Planets.CapLift,
					Color = run.Color,
				})
				k += 1
				at += size * Planets.RunSpacing * per
			end
			at += size * Planets.RunSpacing * per
		end
	end
	return out
end

-- Raw Neon tones (the evening haze lightens and pinks them, see Sky/Planets).
local P = {
	Ocean = rgb(10, 70, 190),
	Leaf = rgb(10, 130, 50),
	Shore = rgb(150, 110, 30),
	RimBlue = rgb(40, 120, 255),
	Dune = rgb(150, 85, 25),
	DuneDark = rgb(90, 40, 10),
	DuneLight = rgb(210, 150, 60),
	DuneRing = rgb(200, 150, 90),
	RimDune = rgb(255, 140, 40),
	Moon = rgb(100, 100, 120),
	Crater = rgb(55, 55, 75),
	RimMoon = rgb(170, 170, 210),
	Mint = rgb(20, 160, 130),
	Swirl = rgb(85, 35, 170),
	MintLight = rgb(110, 225, 185),
	RimMint = rgb(40, 255, 200),
	Rose = rgb(140, 35, 70),
	RoseDark = rgb(80, 10, 35),
	RoseLight = rgb(230, 90, 130),
	RimRose = rgb(255, 80, 140),
}
Heavens.Palette = P

Heavens.PlanetSpecs = {
	{
		Name = "PlanetGarden",
		Az = 118,
		Dist = 780,
		Elev = 18,
		Size = 8.5,
		Roll = -15,
		Lean = 0,
		Body = P.Ocean,
		Rim = P.RimBlue,
		RimTransparency = 0.6,
		Patches = streaks({
			{ Lat = 46, Offset = -6, Runs = { { Count = 3, Color = P.Leaf }, { Count = 1, Color = P.Shore } } },
			{ Lat = 18, Offset = 10, Runs = { { Count = 2, Color = P.Shore }, { Count = 3, Color = P.Leaf } } },
			{ Lat = -10, Offset = -8, Runs = { { Count = 4, Color = P.Leaf } } },
			{ Lat = -40, Offset = 6, Runs = { { Count = 2, Color = P.Leaf }, { Count = 2, Color = P.Shore } } },
		}, 11),
	},
	{
		Name = "PlanetDune",
		Az = 172,
		Dist = 820,
		Elev = 26,
		Size = 7.5,
		Roll = 20,
		Lean = 22,
		Body = P.Dune,
		Rim = P.RimDune,
		RimTransparency = 0.6,
		Patches = streaks({
			{ Lat = 40, Offset = 4, Runs = { { Count = 3, Color = P.DuneDark }, { Count = 2, Color = P.DuneLight } } },
			{ Lat = 8, Offset = -6, Runs = { { Count = 2, Color = P.DuneLight }, { Count = 3, Color = P.DuneDark } } },
			{ Lat = -28, Offset = 8, Runs = { { Count = 3, Color = P.DuneDark } } },
		}, 10.5),
		Ring = { Inner = 1.3, Outer = 1.7, Segments = 24, Color = P.DuneRing },
	},
	{
		Name = "PlanetMoon",
		Az = 212,
		Dist = 760,
		Elev = 14,
		Size = 4.6,
		Roll = 0,
		Lean = 0,
		Body = P.Moon,
		Rim = P.RimMoon,
		RimTransparency = 0.65,
		Patches = {
			{ Lon = -20, Lat = 30, Size = 9, Lift = Planets.CapLift, Color = P.Crater },
			{ Lon = 18, Lat = 10, Size = 11, Lift = Planets.CapLift, Color = P.Crater },
			{ Lon = -12, Lat = -24, Size = 8, Lift = Planets.CapLift, Color = P.Crater },
			{ Lon = 30, Lat = -36, Size = 7, Lift = Planets.CapLift, Color = P.Crater },
		},
	},
	{
		Name = "PlanetMint",
		Az = 80,
		Dist = 760,
		Elev = 34,
		Size = 5.6,
		Roll = 24,
		Lean = 0,
		Body = P.Mint,
		Rim = P.RimMint,
		RimTransparency = 0.6,
		Patches = streaks({
			{ Lat = 34, Offset = 0, Runs = { { Count = 3, Color = P.Swirl }, { Count = 2, Color = P.MintLight } } },
			{ Lat = 0, Offset = 6, Runs = { { Count = 2, Color = P.MintLight }, { Count = 3, Color = P.Swirl } } },
			{ Lat = -34, Offset = -4, Runs = { { Count = 3, Color = P.Swirl } } },
		}, 11),
	},
	{
		Name = "PlanetRose",
		Az = 148,
		Dist = 720,
		Elev = 42,
		Size = 4,
		Roll = -20,
		Lean = 0,
		Body = P.Rose,
		Rim = P.RimRose,
		RimTransparency = 0.6,
		Patches = streaks({
			{ Lat = 30, Offset = 0, Runs = { { Count = 3, Color = P.RoseDark } } },
			{ Lat = -6, Offset = 4, Runs = { { Count = 2, Color = P.RoseLight }, { Count = 2, Color = P.RoseDark } } },
			{ Lat = -38, Offset = -4, Runs = { { Count = 2, Color = P.RoseDark } } },
		}, 11),
	},
} :: { Planets.Spec }

---------------------------------------------------------------- constellations

-- Star pictures: points (degrees across / up from the center as seen from
-- the plaza) and the lines between them.
type Picture = { Name: string, Az: number, Elev: number, Stars: { { number } }, Lines: { { number } } }

Heavens.Pictures = {
	{
		Name = "Pickaxe",
		Az = 100,
		Elev = 50,
		Stars = { { -6, 3.5 }, { -3, 5.5 }, { 0, 6 }, { 3, 5.5 }, { 6, 3.5 }, { 0, 0.5 }, { 0, -5.5 } },
		Lines = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 3, 6 }, { 6, 7 } },
	},
	{
		Name = "Anvil",
		Az = 152,
		Elev = 58,
		Stars = { { -7, 3 }, { 5, 3 }, { 8, 1.5 }, { -2, 0 }, { 2, 0 }, { -4, -3 }, { 4, -3 } },
		Lines = { { 1, 2 }, { 2, 3 }, { 1, 4 }, { 2, 5 }, { 4, 6 }, { 5, 7 }, { 6, 7 } },
	},
	{
		Name = "Gem",
		Az = 205,
		Elev = 48,
		Stars = { { -5, 2 }, { -2, 4.5 }, { 2, 4.5 }, { 5, 2 }, { 0, -5 } },
		Lines = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 1, 4 }, { 1, 5 }, { 4, 5 } },
	},
	{
		Name = "Hammer",
		Az = 28,
		Elev = 55,
		Stars = { { -5, 4 }, { 4, 4 }, { 4, 1 }, { -5, 1 }, { 0, 1 }, { 0, -7 } },
		Lines = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 5, 6 } },
	},
} :: { Picture }

local STAR = rgb(255, 244, 214)
local LINE = rgb(190, 205, 255)
Heavens.StarDistance = 950

-- A point on the sky dome: bearing, elevation (degrees), distance.
local function dome(az: number, elev: number, dist: number): Vector3
	local e = math.rad(elev)
	local flat = Place.at(az, dist * math.cos(e), 0)
	return Vector3.new(flat.X, dist * math.sin(e), flat.Z)
end

local function picture(parent: Instance, spec: Picture)
	local m = Style.model(spec.Name, parent)
	local d = Heavens.StarDistance
	local center = dome(spec.Az, spec.Elev, d)
	-- a frame on the dome facing the town: X across, Y up the sky
	local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local unit = d * math.rad(1) -- studs per degree on the dome
	local points: { Vector3 } = {}
	for _, s in spec.Stars do
		table.insert(points, frame:PointToWorldSpace(Vector3.new(-s[1] * unit, s[2] * unit, 0)))
	end
	for i, p in points do
		local size = unit * (if i % 3 == 0 then 0.75 else 0.6)
		local cf = CFrame.lookAt(p, Vector3.new(0, 0, 0)) * CFrame.Angles(0, 0, math.pi / 4)
		Style.block(m, cf, Vector3.new(size, size, size * 0.3), STAR, NEON, Kit.far()).Name = "Star"
		Style.block(m, cf, Vector3.new(size * 2.4, size * 2.4, size * 0.2), STAR, NEON, Kit.far({ Transparency = 0.8 })).Name = "Glow"
	end
	for _, line in spec.Lines do
		local a, b = points[line[1]], points[line[2]]
		local cf = CFrame.lookAt((a + b) / 2, b)
		Style.block(
			m,
			cf,
			Vector3.new(unit * 0.12, unit * 0.12, (b - a).Magnitude - unit * 0.9),
			LINE,
			NEON,
			Kit.far({ Transparency = 0.55 })
		).Name =
			"Line"
	end
end

---------------------------------------------------------------- clouds

type Cloud = { Az: number, Dist: number, Y: number, Scale: number }
Heavens.Clouds = {
	{ Az = 96, Dist = 620, Y = 120, Scale = 1 },
	{ Az = 132, Dist = 560, Y = 96, Scale = 0.8 },
	{ Az = 160, Dist = 640, Y = 150, Scale = 1.1 },
	{ Az = 188, Dist = 600, Y = 110, Scale = 0.9 },
	{ Az = 226, Dist = 660, Y = 140, Scale = 1 },
	{ Az = 66, Dist = 680, Y = 170, Scale = 0.8 },
} :: { Cloud }

-- An octagonal puff: a square block and its twin turned 45 degrees.
local function puff(m: Model, cf: CFrame, w: number, h: number, color: Color3, rng: Rng.Rng)
	Style.block(m, cf, Vector3.new(w, h, w), Style.vary(color, rng, 0.03), nil, Kit.far())
	Style.block(
		m,
		cf * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(w * 0.92, h * 0.94, w * 0.92),
		Style.vary(color, rng, 0.03),
		nil,
		Kit.far()
	)
end

-- A cumulus: a flat lit-orange underside, three mounds, a pale crown. 10 parts.
local function cloud(parent: Instance, name: string, spec: Cloud, rng: Rng.Rng)
	local m = Style.model(name, parent)
	local p = Place.at(spec.Az, spec.Dist, spec.Y)
	local frame = CFrame.lookAt(p, Vector3.new(0, spec.Y, 0))
	local s = spec.Scale
	puff(m, frame * CFrame.new(0, 0, 0), 70 * s, 10 * s, C.CloudPink:Lerp(C.CloudOrange, 0.5), rng)
	for _, x in { -32, 0, 32 } do
		local w = rng:range(40, 56) * s * (if x == 0 then 1.25 else 1)
		local h = rng:range(22, 32) * s * (if x == 0 then 1.3 else 1)
		puff(m, frame * CFrame.new(x * s + rng:range(-5, 5), 5 * s + h / 2, rng:range(-6, 6)), w, h, C.CloudPink, rng)
	end
	puff(m, frame * CFrame.new(rng:range(-8, 8), 52 * s, 0), 34 * s, 18 * s, C.CloudLight, rng)
end

function Heavens.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Heavens", parent)
	local planets = Style.model("MorePlanets", m)
	for _, spec in Heavens.PlanetSpecs do
		Planets.planet(planets, spec)
	end
	local stars = Style.model("Constellations", m)
	for _, spec in Heavens.Pictures do
		picture(stars, spec)
	end
	local clouds = Style.model("SkyClouds", m)
	for i, spec in Heavens.Clouds do
		cloud(clouds, `Cloud{i}`, spec, Rng.new(`Horizon/Clouds/{i}/{rng:nextU32()}`))
	end
	return m
end

return Heavens
