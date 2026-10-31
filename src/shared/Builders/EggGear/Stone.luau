--[[
	THE STONE EGG's golems (GolemConfig Family "Stone"): little miners and
	tinkers of polished stone (Marble in their ore's colour) in bronze
	armour (gauntlets, shoulder plates, a framed ember gem on the chest), a
	leather belt with a bronze buckle, a dark visor for the glowing eyes and
	a warm ember glow; EggGear explains
	the contract. Each keeps its old accessory's idea, cleaner:

	  PebbleGolem    (Common) a little cairn of pebbles on its head, a miner's pick on its back
	  TinTumbler     (Common) a polished tin pot for a helmet, a bronze band round it
	  CopperTinker   (Uncommon) brass goggles with glowing lenses on its forehead,
	                 a wrench in its hand, a tool pouch, a copper boiler on its back
	  CobaltDiver    (Rare) a diving helmet: a brass porthole the eyes glow through,
	                 bolts, a valve on top, an air tank on its back, weighted boots
	  EmberImp       (Rare, retired) bronze horns with ember tips, a tail with an
	                 ember tip, ember cracks on its chest, a bronze pitchfork
	  CoalChomper    (Epic) a stove for a belly (a glowing grate behind bars), a
	                 glowing mouth with two fangs, a smoke stack on its back,
	                 ember runes on its arms and a glowing coal in its hand
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

local BRONZE = rgb(206, 138, 70)
local BRONZE_DARK = rgb(140, 88, 46)
local BRASS = rgb(222, 176, 82)
local LEATHER = rgb(98, 66, 44)
local STEEL = rgb(186, 194, 206)
local EMBER = rgb(255, 128, 40)
local EMBER_HOT = rgb(255, 214, 120)
local IVORY = rgb(244, 234, 210)
local DARK = rgb(30, 26, 30)

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

-- the Stone egg's look every one of them wears (emblem = false: the
-- costume puts its own thing on the chest)
local function stone(c: Ctx, face: Clean.Face, emblem: boolean?)
	local body = c.Look.Body
	G.dress(c, {
		Skin = body,
		SkinMaterial = M.Marble,
		Torso = body:Lerp(c.Look.Trim, 0.6),
		Boots = c.Look.Trim,
		BootMaterial = M.Marble,
		Armour = BRONZE,
		ArmourMaterial = M.Metal,
		Belt = LEATHER,
		BeltMaterial = M.Fabric,
		Buckle = BRONZE,
		BuckleMaterial = M.Metal,
		Face = face,
		FaceColor = K.darker(body, 0.72),
	})
	G.pauldrons(c, BRONZE, M.Metal)
	G.collar(c, BRONZE, M.Metal)
	if emblem ~= false then
		G.emblem(c, BRONZE, M.Metal, c.Glow)
	end
end

---------------------------------------------------------------- the costumes

local function pebble(c: Ctx): number
	stone(c, "Visor")
	-- a little cairn of polished pebbles on its head
	if c.Room() >= 2 then
		T.ellipsoid(
			c.Model,
			"Pebble1",
			c.At(0.16, 2.8, 0.06) * CFrame.Angles(0, 0.4, 0.08),
			c.V(0.62, 0.28, 0.52),
			K.lighter(c.Look.Body, 0.12),
			M.Marble
		)
		T.ellipsoid(
			c.Model,
			"Pebble2",
			c.At(0.2, 3.0, 0.08) * CFrame.Angles(0, -0.3, -0.1),
			c.V(0.38, 0.2, 0.32),
			K.darker(c.Look.Trim, 0.05),
			M.Marble
		)
	end
	-- a miner's pick slung on its back
	if c.Room() >= 2 then
		-- (below the big head's overhang at the back)
		local a, b = Vector3.new(-0.42, 0.58, 0.49), Vector3.new(0.3, 1.2, 0.49)
		T.seg(c.Model, "PickHandle", T.P(c, a.X, a.Y, a.Z), T.P(c, b.X, b.Y, b.Z), 0.1 * c.S, 0.1 * c.S, LEATHER, M.Wood)
		-- (the head across the handle's top, in the back's plane)
		local across = Vector3.new(-(b.Y - a.Y), b.X - a.X, 0).Unit * 0.24
		local p0, p1 = b - across, b + across
		T.seg(c.Model, "PickHead", T.P(c, p0.X, p0.Y, p0.Z), T.P(c, p1.X, p1.Y, p1.Z), 0.12 * c.S, 0.12 * c.S, BRONZE, M.Metal)
	end
	return 3.1
end

local function tin(c: Ctx): number
	stone(c, "Visor")
	-- a polished tin pot for a helmet, a bronze band round it, its handle
	if c.Room() >= 4 then
		K.upright(c.Model, "Pot", c.At(0, 2.94, 0.02), 0.5 * c.S, 1.4 * c.S, STEEL, M.Metal)
		K.upright(c.Model, "PotRim", c.At(0, 2.7, 0.02), 0.08 * c.S, 1.62 * c.S, K.darker(STEEL, 0.18), M.Metal)
		K.upright(c.Model, "PotBand", c.At(0, 2.98, 0.02), 0.1 * c.S, 1.43 * c.S, BRONZE, M.Metal)
		K.part(c.Model, "PotHandle", c.At(0.86, 2.98, 0.02), c.V(0.38, 0.1, 0.16), BRONZE_DARK, M.Metal)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "PotKnob", c.At(0, 3.24, 0.02), c.V(0.2, 0.2, 0.2), BRONZE, M.Metal, BALL)
	end
	return 3.34
end

local function copper(c: Ctx): number
	stone(c, "Bare")
	-- brass goggles pushed up on the forehead: the brow is their strap
	T.redress(c, "Brow", c.At(0, 2.42, 0.0), c.V(1.54, 0.14, 1.34), LEATHER, M.Fabric)
	for i, x in { -0.3, 0.3 } do
		if c.Room() < 2 then
			break
		end
		K.facing(c.Model, "Goggle" .. i, c.At(x, 2.44, -0.7), 0.14 * c.S, 0.42 * c.S, BRASS, M.Metal)
		K.facing(c.Model, "Lens" .. i, c.At(x, 2.44, -0.775), 0.03 * c.S, 0.28 * c.S, EMBER, NEON)
	end
	-- a wrench in its right hand
	if c.Room() >= 2 then
		G.held(c, "Wrench", Vector3.new(0.86, 0.5, -0.3), Vector3.new(0.86, 1.4, -0.3), 0.1, STEEL, M.Metal)
		K.part(c.Model, "WrenchHead", c.At(0.86, 1.46, -0.3), c.V(0.34, 0.16, 0.1), STEEL, M.Metal)
	end
	-- a tool pouch on the belt, a little copper boiler on its back
	if c.Room() >= 1 then
		K.part(c.Model, "Pouch", c.At(-0.4, 0.56, -0.47), c.V(0.26, 0.24, 0.1), LEATHER, M.Fabric)
	end
	if c.Room() >= 2 then
		K.upright(c.Model, "Boiler", c.At(0, 1.02, 0.66), 0.62 * c.S, 0.46 * c.S, K.lighter(c.Look.Body, 0.1), M.Metal)
		K.upright(c.Model, "BoilerCap", c.At(0, 1.36, 0.66), 0.08 * c.S, 0.52 * c.S, BRASS, M.Metal)
	end
	return 2.76
end

local function cobalt(c: Ctx): number
	stone(c, "Bare")
	-- the diving helmet's porthole: a brass ring, the dark inside the eyes
	-- glow in, glass over them
	if c.Room() >= 3 then
		K.facing(c.Model, "VisorFrame", c.At(0, 2.05, -0.66), 0.1 * c.S, 1.08 * c.S, BRASS, M.Metal)
		K.facing(c.Model, "VisorInner", c.At(0, 2.05, -0.715), 0.02 * c.S, 0.88 * c.S, rgb(18, 24, 52))
		local glass = K.facing(c.Model, "VisorGlass", c.At(0, 2.05, -0.765), 0.02 * c.S, 0.9 * c.S, rgb(170, 220, 255), M.Glass)
		glass.Transparency = 0.55
	end
	for i, x in { -0.22, 0.22 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.05, -0.735), c.V(0.24, 0.2, 0.03), c.Glow, NEON)
	end
	-- four bolts round the porthole
	for i = 1, 4 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 0.5) * PI / 2
		K.part(c.Model, "Bolt" .. i, c.At(math.cos(a) * 0.5, 2.05 + math.sin(a) * 0.5, -0.72), c.V(0.1, 0.1, 0.1), BRASS, M.Metal, BALL)
	end
	-- the air valve on top
	if c.Room() >= 2 then
		K.upright(c.Model, "Valve", c.At(0, 2.8, 0), 0.2 * c.S, 0.3 * c.S, BRASS, M.Metal)
		K.upright(c.Model, "ValveWheel", c.At(0, 2.92, 0), 0.06 * c.S, 0.5 * c.S, BRONZE, M.Metal)
	end
	-- the air tank on its back, brass bands round it
	if c.Room() >= 1 then
		K.upright(c.Model, "Tank", c.At(0, 1.02, 0.66), 0.78 * c.S, 0.48 * c.S, K.lighter(c.Look.Body, 0.25), M.Metal)
	end
	for i, y in { 0.8, 1.24 } do
		if c.Room() < 1 then
			break
		end
		K.upright(c.Model, "TankBand" .. i, c.At(0, y, 0.66), 0.07 * c.S, 0.52 * c.S, BRASS, M.Metal)
	end
	-- weighted brass boots
	for i, x in { -0.3, 0.3 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Boot" .. i, c.At(x, 0.1, -0.04), c.V(0.5, 0.2, 0.6), BRASS, M.Metal)
	end
	return 2.95
end

local function ember(c: Ctx): number
	stone(c, "Visor")
	-- bronze horns with glowing ember tips
	local top = 2.7
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.seg(c.Model, `Horn{i}_1`, T.P(c, side * 0.46, 2.6, 0.05), T.P(c, side * 0.7, 2.98, 0.1), 0.24 * c.S, 0.24 * c.S, BRONZE, M.Metal)
		T.seg(c.Model, `Horn{i}_2`, T.P(c, side * 0.68, 2.94, 0.1), T.P(c, side * 0.74, 3.3, 0.2), 0.14 * c.S, 0.14 * c.S, EMBER, NEON)
		top = 3.36
	end
	-- a tail with an ember tip
	if c.Room() >= 3 then
		T.seg(c.Model, "Tail1", T.P(c, 0, 0.72, 0.4), T.P(c, 0.22, 0.5, 0.82), 0.14 * c.S, 0.14 * c.S, c.Look.Trim, M.Marble)
		T.seg(c.Model, "Tail2", T.P(c, 0.2, 0.5, 0.8), T.P(c, 0.42, 0.72, 1.12), 0.11 * c.S, 0.11 * c.S, c.Look.Trim, M.Marble)
		G.diamond(c.Model, "TailTip", c.At(0.46, 0.8, 1.16) * CFrame.Angles(0, PI / 2, 0), 0.26 * c.S, 0.06 * c.S, EMBER, NEON)
	end
	-- ember cracks glowing on the chest
	for i, k in { { -0.3, 1.24, 0.55 }, { 0.3, 0.86, -0.5 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Crack" .. i, c.At(k[1], k[2], -0.47) * CFrame.Angles(0, 0, k[3]), c.V(0.06, 0.24, 0.03), EMBER, NEON)
	end
	-- a bronze pitchfork in its right hand
	if c.Room() >= 5 then
		G.held(c, "Fork", Vector3.new(1.0, 0.12, -0.32), Vector3.new(1.0, 2.0, -0.32), 0.09, BRONZE_DARK, M.Metal)
		K.part(c.Model, "ForkBar", c.At(1.0, 2.0, -0.32), c.V(0.4, 0.08, 0.08), BRONZE, M.Metal)
		for i, dx in { -0.17, 0, 0.17 } do
			K.part(
				c.Model,
				"ForkTine" .. i,
				c.At(1.0 + dx, 2.16, -0.32),
				c.V(0.07, 0.3, 0.07),
				if i == 2 then EMBER else BRONZE,
				if i == 2 then NEON else M.Metal
			)
		end
	end
	return top
end

local function coal(c: Ctx): number
	stone(c, "Bare", false)
	-- the stove belly: a bronze door frame, the glowing grate behind three bars
	if c.Room() >= 1 then
		K.part(c.Model, "StoveDoor", c.At(0, 1.0, -0.445), c.V(0.8, 0.58, 0.05), BRONZE, M.Metal)
	end
	T.redress(c, "Core", c.At(0, 1.0, -0.475), c.V(0.62, 0.4, 0.03), EMBER, NEON)
	for i, y in { 0.88, 1.0, 1.12 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Grate" .. i, c.At(0, y, -0.495), c.V(0.66, 0.045, 0.03), DARK, M.Metal)
	end
	-- a glowing mouth with two fangs
	if c.Room() >= 3 then
		K.part(c.Model, "Mouth", c.At(0, 1.68, -0.665), c.V(0.62, 0.13, 0.03), EMBER, NEON)
		for i, x in { -0.18, 0.18 } do
			G.diamond(c.Model, "Fang" .. i, c.At(x, 1.74, -0.685), 0.12 * c.S, 0.04 * c.S, IVORY, M.Marble)
		end
	end
	-- a smoke stack on its back, a fire glowing in its top
	if c.Room() >= 4 then
		-- (the pipe runs from inside the body into the stack: it all stays on the body when it runs)
		T.seg(c.Model, "StackPipe", T.P(c, 0.34, 1.15, 0.15), T.P(c, 0.34, 1.15, 0.9), 0.22 * c.S, 0.22 * c.S, BRONZE_DARK, M.Metal)
		K.upright(c.Model, "Stack", c.At(0.34, 1.74, 0.84), 1.3 * c.S, 0.26 * c.S, BRONZE_DARK, M.Metal)
		K.upright(c.Model, "StackCap", c.At(0.34, 2.42, 0.84), 0.1 * c.S, 0.38 * c.S, BRONZE, M.Metal)
		K.upright(c.Model, "StackFire", c.At(0.34, 2.48, 0.84), 0.03 * c.S, 0.24 * c.S, EMBER, NEON)
	end
	-- ember runes on the arms
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Rune" .. i, c.At(side * 0.82, 1.12, -0.245) * CFrame.Angles(0, 0, side * 0.1), c.V(0.06, 0.3, 0.03), EMBER, NEON)
	end
	-- a glowing lump of coal in its left hand
	if c.Room() >= 2 then
		local lump = c.At(-0.9, 0.62, -0.42) * CFrame.Angles(0.5, 0.6, 0.3)
		K.part(c.Model, "Coal", lump, c.V(0.32, 0.28, 0.3), DARK, M.Slate)
		K.part(c.Model, "CoalGlow", lump * CFrame.new(0, 0, -0.14 * c.S), c.V(0.2, 0.16, 0.04), EMBER_HOT, NEON)
	end
	return 2.53
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
