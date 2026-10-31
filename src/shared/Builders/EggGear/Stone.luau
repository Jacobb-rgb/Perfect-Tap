--[[
	THE STONE EGG's golems (GolemConfig Family "Stone"): little miners and
	tinkers in the egg's armour set (EggGear/Clean): plates of polished
	stone in their ore's colour over a rough dark under-suit, bronze trim, a
	leather belt, a bronze cog round the glowing core, the eyes in a dark
	visor, a warm ember glow. EggGear explains the contract. Each one's
	signature, readable small:

	  PebbleGolem    (Common) a crown of three stacked river stones, a pickaxe
	  TinTumbler     (Common) a polished tin pot for a helmet, a ladle
	  CopperTinker   (Uncommon) brass goggles with glowing lenses, a wrench, a
	                 big bronze cog on its back
	  CobaltDiver    (Rare) a brass diving helmet: a porthole the eyes glow
	                 through, side portholes, bolts, a valve; an air tank, brass boots
	  EmberImp       (Rare, retired) bronze horns with ember tips, a trident,
	                 a tail, little bat wings, ember cracks
	  CoalChomper    (Epic) a stove for a belly (a glowing grate behind bars),
	                 two chimneys smoking over its head, ember horns, a glowing
	                 mouth with fangs, ember runes, a lump of glowing coal
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)
local Clean = require(script.Parent.Clean)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Gear = Clean.Gear

local Stone = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local BRONZE = rgb(214, 140, 66)
local BRONZE_DARK = rgb(140, 88, 46)
local BRASS = rgb(226, 178, 80)
local LEATHER = rgb(98, 66, 44)
local WOOD = rgb(132, 88, 52)
local STEEL = rgb(190, 198, 210)
local EMBER = rgb(255, 128, 40)
local EMBER_HOT = rgb(255, 214, 120)
local IVORY = rgb(244, 234, 210)
local DARK = rgb(30, 26, 30)

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- the Stone egg's armour set (band = false: a hat brings its own rim)
local function stone(c: Ctx, face: Clean.Face, band: boolean?, plate: Color3?, boots: Color3?, guards: boolean?)
	local body = plate or c.Look.Body
	G.dress(c, {
		Plate = body,
		PlateMaterial = M.Marble,
		Suit = K.darker(body, 0.5),
		SuitMaterial = M.Slate,
		Metal = BRONZE,
		MetalMaterial = M.Metal,
		Belt = LEATHER,
		BeltMaterial = M.Fabric,
		Buckle = BRONZE,
		BuckleMaterial = M.Metal,
		Face = face,
		Band = band,
		Guards = guards,
		Boots = boots,
		BootMaterial = if boots then M.Metal else nil,
	})
end

-- a pair of horns: a bronze root, an ember tip
local function horns(c: Ctx, root: Vector3, mid: Vector3, tip: Vector3, w: number)
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			return
		end
		T.seg(
			c.Model,
			`Horn{i}_1`,
			T.P(c, side * root.X, root.Y, root.Z),
			T.P(c, side * mid.X, mid.Y, mid.Z),
			w * c.S,
			w * c.S,
			BRONZE,
			M.Metal
		)
		T.seg(
			c.Model,
			`Horn{i}_2`,
			T.P(c, side * mid.X, mid.Y, mid.Z),
			T.P(c, side * tip.X, tip.Y, tip.Z),
			w * 0.6 * c.S,
			w * 0.6 * c.S,
			EMBER,
			NEON
		)
	end
end

---------------------------------------------------------------- the costumes

local function pebble(c: Ctx): number
	stone(c, "Visor")
	G.cog(c, BRONZE, M.Metal, c.Glow)
	local body = c.Look.Body
	-- a crown of three stacked river stones
	if c.Room() >= 3 then
		T.ellipsoid(
			c.Model,
			"Pebble1",
			c.At(0.04, 2.86, 0.04) * CFrame.Angles(0, 0.3, 0.05),
			c.V(0.86, 0.34, 0.74),
			K.lighter(body, 0.18),
			M.Marble
		)
		T.ellipsoid(
			c.Model,
			"Pebble2",
			c.At(-0.05, 3.1, 0.05) * CFrame.Angles(0, -0.4, -0.08),
			c.V(0.6, 0.28, 0.52),
			K.darker(body, 0.25),
			M.Marble
		)
		T.ellipsoid(
			c.Model,
			"Pebble3",
			c.At(0.04, 3.31, 0.05) * CFrame.Angles(0, 0.6, 0.1),
			c.V(0.38, 0.22, 0.34),
			K.lighter(body, 0.35),
			M.Marble
		)
	end
	-- a little pickaxe in its right fist (clear of the big head)
	if c.Room() >= 3 then
		G.held(c, "PickHandle", V(1.04, 0.3, -0.32), V(1.04, 1.72, -0.32), 0.1, WOOD, M.Wood)
		T.seg(c.Model, "PickHead1", T.P(c, 0.9, 1.52, -0.32), T.P(c, 1.05, 1.72, -0.32), 0.12 * c.S, 0.11 * c.S, STEEL, M.Metal)
		T.seg(c.Model, "PickHead2", T.P(c, 1.03, 1.72, -0.32), T.P(c, 1.44, 1.5, -0.32), 0.12 * c.S, 0.11 * c.S, STEEL, M.Metal)
	end
	return 3.42
end

local function tin(c: Ctx): number
	stone(c, "Visor", false)
	G.cog(c, BRONZE, M.Metal, c.Glow)
	-- a polished tin pot for a helmet: a bronze rim, a handle, a knob
	if c.Room() >= 3 then
		K.upright(c.Model, "Pot", c.At(0, 2.95, 0.02), 0.52 * c.S, 1.44 * c.S, STEEL, M.Metal)
		K.upright(c.Model, "PotRim", c.At(0, 2.7, 0.02), 0.1 * c.S, 1.66 * c.S, BRONZE, M.Metal)
		K.part(c.Model, "PotHandle", c.At(-0.9, 2.98, 0.02), c.V(0.42, 0.1, 0.16), BRONZE_DARK, M.Metal)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "PotKnob", c.At(0, 3.26, 0.02), c.V(0.22, 0.22, 0.22), BRONZE, M.Metal, BALL)
	end
	-- a ladle in its right fist
	if c.Room() >= 2 then
		G.held(c, "Ladle", V(1.04, 0.3, -0.34), V(1.04, 1.64, -0.34), 0.08, STEEL, M.Metal)
		T.ellipsoid(c.Model, "LadleBowl", c.At(1.04, 1.72, -0.42) * CFrame.Angles(-0.6, 0, 0), c.V(0.36, 0.2, 0.36), STEEL, M.Metal)
	end
	return 3.37
end

local function copper(c: Ctx): number
	stone(c, "Visor")
	G.cog(c, BRONZE, M.Metal, c.Glow)
	-- brass goggles on the forehead: the band round the head is their strap
	T.redress(c, "HeadBand", c.At(0, 2.46, 0), c.V(1.54, 0.14, 1.34), LEATHER, M.Fabric)
	for i, x in { -0.3, 0.3 } do
		if c.Room() < 2 then
			break
		end
		K.facing(c.Model, "Goggle" .. i, c.At(x, 2.48, -0.7), 0.14 * c.S, 0.46 * c.S, BRASS, M.Metal)
		K.facing(c.Model, "Lens" .. i, c.At(x, 2.48, -0.775), 0.03 * c.S, 0.3 * c.S, EMBER, NEON)
	end
	-- a wrench in its right fist
	if c.Room() >= 2 then
		G.held(c, "Wrench", V(1.04, 0.4, -0.32), V(1.04, 1.42, -0.32), 0.11, STEEL, M.Metal)
		K.part(c.Model, "WrenchHead", c.At(1.04, 1.5, -0.32), c.V(0.38, 0.2, 0.11), STEEL, M.Metal)
	end
	-- a big bronze cog on its back, on an axle out of the body (it stays on the body)
	if c.Room() >= 4 then
		T.seg(c.Model, "CogAxle", T.P(c, 0.5, 1.28, 0.2), T.P(c, 0.5, 1.28, 0.9), 0.14 * c.S, 0.14 * c.S, BRONZE_DARK, M.Metal)
		local at = c.At(0.62, 1.72, 0.82)
		K.facing(c.Model, "BackCog", at, 0.1 * c.S, 1.1 * c.S, BRONZE, M.Metal)
		K.part(c.Model, "BackCogTeeth1", at * CFrame.Angles(0, 0, PI / 8), c.V(1.36, 0.18, 0.1), BRONZE, M.Metal)
		K.part(c.Model, "BackCogTeeth2", at * CFrame.Angles(0, 0, PI / 8 + PI / 2), c.V(1.36, 0.18, 0.1), BRONZE, M.Metal)
	end
	return 2.62
end

local function cobalt(c: Ctx): number
	stone(c, "Bare", false, nil, BRASS, false)
	G.cog(c, BRONZE, M.Metal, c.Glow)
	-- the brass diving helmet: a rounded box over the head under a dome
	K.part(c.Model, "Helm", c.At(0, 2.1, 0), c.V(1.66, 1.4, 1.5), BRASS, M.Metal)
	if c.Room() >= 1 then
		T.ellipsoid(c.Model, "HelmDome", c.At(0, 2.8, 0), c.V(1.58, 0.6, 1.42), BRASS, M.Metal)
	end
	-- its porthole: a dark ring, the eyes glowing behind glass
	if c.Room() >= 3 then
		K.facing(c.Model, "VisorFrame", c.At(0, 2.08, -0.77), 0.1 * c.S, 0.98 * c.S, BRONZE_DARK, M.Metal)
		K.facing(c.Model, "VisorInner", c.At(0, 2.08, -0.83), 0.02 * c.S, 0.8 * c.S, rgb(16, 22, 48))
		local glass = K.facing(c.Model, "VisorGlass", c.At(0, 2.08, -0.875), 0.02 * c.S, 0.82 * c.S, rgb(170, 220, 255), M.Glass)
		glass.Transparency = 0.55
	end
	for i, x in { -0.2, 0.2 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.08, -0.85), c.V(0.24, 0.2, 0.03), c.Glow, NEON)
	end
	for i = 1, 4 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 0.5) * PI / 2
		K.part(
			c.Model,
			"Bolt" .. i,
			c.At(math.cos(a) * 0.52, 2.08 + math.sin(a) * 0.52, -0.82),
			c.V(0.11, 0.11, 0.11),
			BRONZE,
			M.Metal,
			BALL
		)
	end
	-- side portholes, the air valve on top
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.facing(
			c.Model,
			"SidePort" .. i,
			c.At(side * 0.84, 2.1, 0) * CFrame.Angles(0, PI / 2, 0),
			0.04 * c.S,
			0.46 * c.S,
			rgb(40, 60, 110),
			M.Glass
		)
	end
	if c.Room() >= 2 then
		K.upright(c.Model, "Valve", c.At(0, 3.14, 0), 0.18 * c.S, 0.3 * c.S, BRONZE, M.Metal)
		K.upright(c.Model, "ValveWheel", c.At(0, 3.24, 0), 0.06 * c.S, 0.52 * c.S, BRONZE_DARK, M.Metal)
	end
	-- the air tank on its back (below the helmet), brass bands round it
	if c.Room() >= 1 then
		K.upright(c.Model, "Tank", c.At(0, 0.95, 0.7), 0.76 * c.S, 0.5 * c.S, K.lighter(c.Look.Body, 0.25), M.Metal)
	end
	for i, y in { 0.74, 1.16 } do
		if c.Room() < 1 then
			break
		end
		K.upright(c.Model, "TankBand" .. i, c.At(0, y, 0.7), 0.07 * c.S, 0.54 * c.S, BRASS, M.Metal)
	end
	return 3.27
end

local function ember(c: Ctx): number
	stone(c, "Visor")
	G.cog(c, BRONZE, M.Metal, c.Glow)
	horns(c, V(0.46, 2.6, 0.05), V(0.72, 2.98, 0.1), V(0.8, 3.38, 0.22), 0.25)
	-- a bronze trident in its right fist
	if c.Room() >= 5 then
		G.held(c, "Fork", V(1.04, 0.12, -0.34), V(1.04, 2.1, -0.34), 0.09, BRONZE_DARK, M.Metal)
		K.part(c.Model, "ForkBar", c.At(1.04, 2.1, -0.34), c.V(0.42, 0.08, 0.08), BRONZE, M.Metal)
		for i, dx in { -0.17, 0, 0.17 } do
			local hot = i == 2
			K.part(
				c.Model,
				"ForkTine" .. i,
				c.At(1.04 + dx, 2.28, -0.34),
				c.V(0.07, 0.34, 0.07),
				if hot then EMBER else BRONZE,
				if hot then NEON else M.Metal
			)
		end
	end
	-- a tail with an ember spade
	if c.Room() >= 3 then
		T.seg(c.Model, "Tail1", T.P(c, 0, 0.74, 0.4), T.P(c, 0.24, 0.5, 0.84), 0.15 * c.S, 0.15 * c.S, K.darker(c.Look.Body, 0.5), M.Slate)
		T.seg(
			c.Model,
			"Tail2",
			T.P(c, 0.22, 0.5, 0.82),
			T.P(c, 0.46, 0.76, 1.14),
			0.12 * c.S,
			0.12 * c.S,
			K.darker(c.Look.Body, 0.5),
			M.Slate
		)
		G.diamond(c.Model, "TailTip", c.At(0.5, 0.86, 1.18) * CFrame.Angles(0, PI / 2, 0), 0.3 * c.S, 0.06 * c.S, EMBER, NEON)
	end
	-- little bat wings on its back
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		G.diamond(
			c.Model,
			"Wing" .. i,
			c.At(side * 0.62, 1.14, 0.6) * CFrame.Angles(0, side * 0.6, 0),
			0.62 * c.S,
			0.05 * c.S,
			K.darker(c.Look.Body, 0.35),
			M.SmoothPlastic
		)
	end
	-- ember cracks on the breastplate
	for i, k in { { -0.32, 1.18, 0.55 }, { 0.32, 0.82, -0.5 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Crack" .. i, c.At(k[1], k[2], -0.49) * CFrame.Angles(0, 0, k[3]), c.V(0.06, 0.24, 0.03), EMBER, NEON)
	end
	return 3.45
end

local function coal(c: Ctx): number
	local plate = rgb(66, 62, 72)
	stone(c, "Bare", true, plate)
	-- the stove belly: a bronze door frame, the glowing grate behind three bars
	if c.Room() >= 1 then
		K.part(c.Model, "StoveDoor", c.At(0, 0.98, -0.49), c.V(0.76, 0.52, 0.04), BRONZE, M.Metal)
	end
	T.redress(c, "Core", c.At(0, 0.98, -0.515), c.V(0.6, 0.38, 0.02), EMBER, NEON)
	for i, y in { 0.86, 0.98, 1.1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Grate" .. i, c.At(0, y, -0.53), c.V(0.64, 0.045, 0.03), DARK, M.Metal)
	end
	-- two chimneys smoking over its head, on pipes out of its back (they stay on the body)
	for i, side in { -1, 1 } do
		if c.Room() < 4 then
			break
		end
		local x = side * 0.56
		T.seg(c.Model, "StackPipe" .. i, T.P(c, x, 1.2, 0.2), T.P(c, x, 1.2, 0.96), 0.2 * c.S, 0.2 * c.S, BRONZE_DARK, M.Metal)
		K.upright(c.Model, "Stack" .. i, c.At(x, 2.16, 0.86), 2.1 * c.S, 0.27 * c.S, BRONZE_DARK, M.Metal)
		K.upright(c.Model, "StackCap" .. i, c.At(x, 3.23, 0.86), 0.1 * c.S, 0.38 * c.S, BRONZE, M.Metal)
		K.upright(c.Model, "StackFire" .. i, c.At(x, 3.29, 0.86), 0.03 * c.S, 0.24 * c.S, EMBER, NEON)
	end
	-- short ember horns
	horns(c, V(0.5, 2.62, -0.05), V(0.68, 2.88, -0.05), V(0.74, 3.1, 0.05), 0.22)
	-- a glowing mouth with two fangs
	if c.Room() >= 3 then
		K.part(c.Model, "Mouth", c.At(0, 1.68, -0.665), c.V(0.62, 0.13, 0.03), EMBER, NEON)
		for i, x in { -0.18, 0.18 } do
			G.diamond(c.Model, "Fang" .. i, c.At(x, 1.74, -0.685), 0.12 * c.S, 0.04 * c.S, IVORY, M.Marble)
		end
	end
	-- a glowing lump of coal in its left hand
	if c.Room() >= 2 then
		local lump = c.At(-0.92, 0.62, -0.42) * CFrame.Angles(0.5, 0.6, 0.3)
		K.part(c.Model, "Coal", lump, c.V(0.34, 0.3, 0.32), DARK, M.Slate)
		K.part(c.Model, "CoalGlow", lump * CFrame.new(0, 0, -0.15 * c.S), c.V(0.22, 0.17, 0.04), EMBER_HOT, NEON)
	end
	-- ember runes down the dark arms
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Rune" .. i, c.At(side * 0.82, 1.06, -0.245) * CFrame.Angles(0, 0, side * 0.1), c.V(0.06, 0.26, 0.03), EMBER, NEON)
	end
	return 3.11
end

function Stone.costumes(kit: Kit, tools: Tools, gear: Gear): { [string]: (Ctx) -> number }
	K, T, G = kit, tools, gear
	return {
		PebbleGolem = pebble,
		TinTumbler = tin,
		CopperTinker = copper,
		CobaltDiver = cobalt,
		EmberImp = ember,
		CoalChomper = coal,
	}
end

return Stone
