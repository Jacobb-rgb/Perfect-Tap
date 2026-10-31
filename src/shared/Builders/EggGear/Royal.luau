--[[
	THE ROYAL EGG's golems (GolemConfig Family "Royal"; owner: royal =
	"divine"): the egg's armour set (EggGear/Clean) in their ore's metal
	over a darker under-suit, trimmed with gold (gauntlets, collar, rims,
	the belt), a gold crest with the glowing gem on the breastplate, the
	eyes in a dark visor; crests, crowns, halos and wings of light, like the
	Royal egg (pearl and gold, a halo). No capes (a cape is the Dragon
	King's alone). EggGear explains the contract. Each one's signature,
	readable small:

	  SilverSquire        (Uncommon) a closed silver helm with a red plume and a gold
	                      nose guard, a round shield, a sword
	  RoseKnight          (Rare) a closed rose helm with a gold crest and a rose, a big
	                      pearl kite shield, a sword, roses on its shoulders
	  GildedPorter        (Rare, retired) a velvet porter's cap with a miner's lamp, a
	                      pack of gold bars and coins on its back, a railway lantern
	  MoonstoneOracle     (Epic) a halo of moonlight, a gold crescent on its brow, a
	                      crescent staff with an orb, orbs floating round it
	  StormTitan          (Legendary) a crown of lightning, lightning rising from its
	                      shoulders, storm crystals on its back, sparks
	  CelestialSovereign  (Mythic) a gold crown of stars under a gold halo, wings of
	                      light, a star sceptre, stars floating round it, embers
	                      and its own light
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)
local Clean = require(script.Parent.Clean)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Gear = Clean.Gear

local Royal = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local GOLD = rgb(255, 198, 64)
local GOLD_DEEP = rgb(222, 150, 38)
local PEARL = rgb(234, 226, 212) -- (a warm pearl: a whiter one blooms into a blob)
local PLUME = rgb(214, 52, 60)
local BLADE = rgb(226, 232, 242)
local VELVET = rgb(150, 30, 52)
local SLIT = rgb(24, 16, 26)
local BOLT = rgb(255, 232, 110)
local STAR = rgb(255, 236, 150)
local LIGHT = rgb(255, 244, 200)

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- the Royal egg's armour set and its crest (band = false: a helm, a cap or
-- a crown brings its own rim; faceZ: the visor on a closed helm's front)
local function royal(c: Ctx, band: boolean?, faceZ: number?, guards: boolean?, plate: Color3?)
	local body = plate or c.Look.Body
	G.dress(c, {
		Plate = body,
		PlateMaterial = M.Metal,
		Head = K.lighter(body, 0.08),
		HeadMaterial = M.Metal,
		Suit = K.darker(body, 0.5),
		SuitMaterial = M.Metal,
		Metal = GOLD,
		MetalMaterial = M.Foil,
		Belt = GOLD,
		BeltMaterial = M.Foil,
		Buckle = c.Glow,
		BuckleMaterial = NEON,
		Face = "Visor",
		FaceZ = faceZ,
		Band = band,
		Guards = guards,
	})
	G.crest(c, GOLD, M.Foil, c.Glow)
end

-- a glowing gem lying on top of each shoulder plate (they swing with the arms)
local function shoulderGems(c: Ctx, color: Color3, size: number?)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			return
		end
		local at = Clean.shoulder(c, side) * CFrame.new(0, 0.23 * c.S, 0)
		G.diamond(c.Model, "PauldronGem" .. i, at * CFrame.Angles(PI / 2, 0, 0), (size or 0.22) * c.S, 0.05 * c.S, color, NEON)
	end
end

-- `n` lights floating round it at shoulder height (named Aura*: they stay with the body)
local function floating(c: Ctx, name: string, n: number, color: Color3, size: number, ball: boolean?)
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local a = (i - 1) / n * 2 * PI + 0.9
		local at = c.At(math.cos(a) * 1.3, 1.1 + i * 0.3, math.sin(a) * 1.05)
		if ball then
			K.part(c.Model, name .. i, at, c.V(size, size, size), color, NEON, BALL)
		else
			G.diamond(c.Model, name .. i, at * CFrame.Angles(0, a, 0), size * c.S, 0.07 * c.S, color, NEON)
		end
	end
end

-- a sword in the right fist (the blade up and forward, clear of the head)
local function sword(c: Ctx, guard: Color3)
	if c.Room() < 3 then
		return
	end
	T.seg(c.Model, "Blade", T.P(c, 0.94, 0.86, -0.22), T.P(c, 1.1, 2.42, -0.72), 0.2 * c.S, 0.05 * c.S, BLADE, M.Metal)
	T.seg(c.Model, "Guard", T.P(c, 0.66, 0.8, -0.16), T.P(c, 1.22, 0.86, -0.2), 0.1 * c.S, 0.1 * c.S, guard, M.Foil)
	K.part(c.Model, "Pommel", c.At(0.88, 0.42, -0.04), c.V(0.16, 0.16, 0.16), guard, M.Foil, BALL)
end

-- a closed helm over the whole head (GolemBuilder rounds it), a dark slit on its front
local function closedHelm(c: Ctx, color: Color3)
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), color, M.Metal)
	-- gold cheek plates on its sides
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(c.Model, "HelmGuard" .. i, c.At(side * 0.83, 1.98, -0.02), c.V(0.07, 0.8, 1.04), GOLD, M.Foil)
		end
	end
end

---------------------------------------------------------------- the costumes

local function squire(c: Ctx): number
	royal(c, false, -0.705, false)
	-- a closed silver helm: a gold band, a gold nose guard over the visor, a red plume
	closedHelm(c, K.lighter(c.Look.Body, 0.2))
	if c.Room() >= 3 then
		K.part(c.Model, "HelmBand", c.At(0, 2.52, 0.02), c.V(1.66, 0.12, 1.46), GOLD, M.Foil)
		K.part(c.Model, "NoseGuard", c.At(0, 2.2, -0.73), c.V(0.12, 0.4, 0.04), GOLD, M.Foil)
		T.ellipsoid(c.Model, "Plume", c.At(0, 3.04, 0.22) * CFrame.Angles(0.35, 0, 0), c.V(0.22, 0.56, 1.0), PLUME, M.Fabric)
	end
	-- a round shield on the left arm: pearl, a gold rim and boss
	if c.Room() >= 3 then
		local shield = c.At(-1.1, 0.95, -0.2) * CFrame.Angles(0, PI / 5, 0)
		K.facing(c.Model, "ShieldRim", shield * CFrame.new(0, 0, 0.02 * c.S), 0.06 * c.S, 0.78 * c.S, GOLD, M.Foil)
		K.facing(c.Model, "Shield", shield, 0.08 * c.S, 0.68 * c.S, PEARL, M.Marble)
		K.part(c.Model, "ShieldBoss", shield * CFrame.new(0, 0, -0.06 * c.S), c.V(0.2, 0.2, 0.2), GOLD, M.Foil, BALL)
	end
	sword(c, GOLD)
	return 3.4
end

local function rose(c: Ctx): number
	royal(c, false, nil, false)
	-- the closed rose helm, the eyes glowing through its slit under a gold brow
	closedHelm(c, K.lighter(c.Look.Body, 0.08))
	if c.Room() >= 1 then
		K.part(c.Model, "Slit", c.At(0, 2.04, -0.705), c.V(1.12, 0.26, 0.03), SLIT)
	end
	for i, x in { -0.28, 0.28 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.04, -0.73), c.V(0.26, 0.17, 0.03), c.Glow, NEON)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "HelmBrow", c.At(0, 2.3, -0.73) * CFrame.Angles(-0.3, 0, 0), c.V(1.42, 0.14, 0.16), GOLD, M.Foil)
	end
	-- a gold crest with a rose at its front
	if c.Room() >= 3 then
		K.part(c.Model, "HelmCrest", c.At(0, 2.98, 0.08), c.V(0.12, 0.44, 1.1), GOLD, M.Foil)
		G.diamond(c.Model, "Rose1", c.At(0, 3.0, -0.52) * CFrame.Angles(0, PI / 2, 0), 0.3 * c.S, 0.12 * c.S, c.Look.Body, M.SmoothPlastic)
		G.diamond(c.Model, "Rose2", c.At(0, 3.0, -0.52), 0.18 * c.S, 0.16 * c.S, c.Glow, NEON)
	end
	-- a big pearl kite shield on the left arm, a glowing rose on it, on a gold rim
	if c.Room() >= 4 then
		local shield = c.At(-1.1, 0.98, -0.3) * CFrame.Angles(0, PI / 5, 0)
		K.part(c.Model, "ShieldRim", shield * CFrame.new(0, 0, 0.03 * c.S), c.V(0.98, 0.78, 0.08), GOLD, M.Foil)
		K.part(c.Model, "Shield", shield, c.V(0.9, 0.7, 0.1), PEARL, M.Marble)
		G.diamond(c.Model, "ShieldPoint", shield * CFrame.new(0, -0.34 * c.S, 0), 0.64 * c.S, 0.1 * c.S, PEARL, M.Marble)
		G.diamond(c.Model, "ShieldRose", shield * CFrame.new(0, -0.08 * c.S, -0.06 * c.S), 0.28 * c.S, 0.03 * c.S, c.Glow, NEON)
	end
	sword(c, GOLD)
	shoulderGems(c, c.Glow)
	return 3.4
end

local function porter(c: Ctx): number
	-- (a deeper gold than its trim: the gold trim stays apart from the plates)
	royal(c, false, nil, true, rgb(214, 150, 34))
	-- a velvet porter's cap on a gold brim, a miner's lamp on it
	if c.Room() >= 5 then
		K.upright(c.Model, "Helmet", c.At(0, 2.84, 0.02), 0.32 * c.S, 1.5 * c.S, VELVET, M.Fabric)
		T.ellipsoid(c.Model, "HelmetDome", c.At(0, 2.98, 0.02), c.V(1.48, 0.5, 1.48), VELVET, M.Fabric)
		K.upright(c.Model, "Brim", c.At(0, 2.68, 0.0), 0.08 * c.S, 1.72 * c.S, GOLD_DEEP, M.Foil)
		K.facing(c.Model, "Lamp", c.At(0, 2.88, -0.74), 0.22 * c.S, 0.42 * c.S, GOLD_DEEP, M.Foil)
		K.facing(c.Model, "LampLens", c.At(0, 2.88, -0.86), 0.04 * c.S, 0.3 * c.S, rgb(255, 244, 190), NEON)
	end
	-- a pack of gold on its back: gold bars and coins over the top, straps over the chest
	if c.Room() >= 5 then
		K.part(c.Model, "Pack", c.At(0, 0.98, 0.7), c.V(0.9, 0.72, 0.42), VELVET, M.Fabric)
		K.part(c.Model, "GoldBar1", c.At(-0.18, 1.36, 0.8) * CFrame.Angles(0.25, 0, 0.12), c.V(0.18, 0.36, 0.14), GOLD, M.Foil)
		K.part(c.Model, "GoldBar2", c.At(0.12, 1.34, 0.82) * CFrame.Angles(0.3, 0, -0.18), c.V(0.18, 0.34, 0.14), GOLD, M.Foil)
		K.upright(c.Model, "Coin1", c.At(0.34, 1.36, 0.72) * CFrame.Angles(0.4, 0, 0.3), 0.06 * c.S, 0.3 * c.S, GOLD, M.Foil)
		K.upright(c.Model, "Coin2", c.At(-0.38, 1.36, 0.7) * CFrame.Angles(-0.3, 0, -0.3), 0.06 * c.S, 0.28 * c.S, GOLD, M.Foil)
	end
	for i, x in { -0.36, 0.36 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Strap" .. i, c.At(x, 1.0, -0.485), c.V(0.1, 0.66, 0.03), VELVET, M.Fabric)
	end
	-- a railway lantern in its left hand
	if c.Room() >= 2 then
		K.part(c.Model, "Lantern", c.At(-0.9, 0.38, -0.3), c.V(0.28, 0.34, 0.28), GOLD_DEEP, M.Foil)
		K.part(c.Model, "LanternLight", c.At(-0.9, 0.38, -0.3), c.V(0.2, 0.22, 0.32), rgb(255, 226, 140), NEON)
	end
	return 3.25
end

local function moonstone(c: Ctx): number
	royal(c)
	-- a halo of moonlight
	G.ring(c, "Halo", 3.22, 0.1, 0.58, 8, 0.08, c.Glow, NEON, 0.2)
	-- a gold crescent rising from its brow, a moonstone in its cup
	local arc = {
		V(-0.44, 3.12, -0.68),
		V(-0.38, 2.8, -0.68),
		V(0, 2.62, -0.68),
		V(0.38, 2.8, -0.68),
		V(0.44, 3.12, -0.68),
	}
	for i = 1, #arc - 1 do
		if c.Room() < 1 then
			break
		end
		local a, b = arc[i], arc[i + 1]
		local w = if i == 1 or i == 4 then 0.09 else 0.16
		local dir = (b - a).Unit
		local from, to = a - dir * (w * 0.4), b + dir * (w * 0.4)
		T.seg(c.Model, "Crescent" .. i, T.P(c, from.X, from.Y, from.Z), T.P(c, to.X, to.Y, to.Z), w * c.S, 0.08 * c.S, GOLD, M.Foil)
	end
	if c.Room() >= 1 then
		G.diamond(c.Model, "Moonstone", c.At(0, 2.84, -0.7), 0.22 * c.S, 0.05 * c.S, c.Glow, NEON)
	end
	-- a crescent staff with a glowing orb (clear of the head: it swings with the arm)
	if c.Room() >= 5 then
		G.held(c, "Staff", V(1.04, 0.1, -0.32), V(1.04, 2.56, -0.32), 0.09, GOLD, M.Foil)
		local tips = { V(0.86, 2.78, -0.32), V(0.92, 2.44, -0.32), V(1.16, 2.44, -0.32), V(1.22, 2.78, -0.32) }
		for i = 1, 3 do
			local a, b = tips[i], tips[i + 1]
			T.seg(c.Model, "StaffMoon" .. i, T.P(c, a.X, a.Y, a.Z), T.P(c, b.X, b.Y, b.Z), 0.08 * c.S, 0.07 * c.S, GOLD, M.Foil)
		end
		K.part(c.Model, "Orb", c.At(1.04, 2.66, -0.32), c.V(0.24, 0.24, 0.24), c.Glow, NEON, BALL)
	end
	-- orbs floating round it, moonstones on its shoulders
	floating(c, "AuraOrb", 2, c.Glow, 0.24, true)
	shoulderGems(c, c.Glow)
	return 3.4
end

local function storm(c: Ctx): number
	royal(c)
	-- a crown of lightning
	local top = G.crown(c, {
		Y = 2.84,
		Radius = 0.6,
		Height = 0.26,
		Points = 5,
		Point = 0.3,
		Color = GOLD,
		Material = M.Foil,
		PointColor = BOLT,
		PointMaterial = NEON,
		Gems = { c.Glow, c.Glow, c.Glow },
	})
	-- lightning rising from its shoulders, gold spikes on them
	for i, side in { -1, 1 } do
		if c.Room() < 3 then
			break
		end
		local zig = { V(1.02, 1.5, 0.06), V(1.2, 1.82, 0.04), V(1.06, 1.98, 0.02), V(1.24, 2.36, 0) }
		for j = 1, #zig - 1 do
			local a, b = zig[j], zig[j + 1]
			T.seg(
				c.Model,
				`PauldronBolt{i}_{j}`,
				T.P(c, side * a.X, a.Y, a.Z),
				T.P(c, side * b.X, b.Y, b.Z),
				0.12 * c.S,
				0.06 * c.S,
				BOLT,
				NEON
			)
		end
	end
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		local base = Clean.shoulder(c, side) * CFrame.new(side * 0.1 * c.S, 0.2 * c.S, 0)
		local tip = base * CFrame.new(side * 0.22 * c.S, 0.34 * c.S, 0)
		T.seg(c.Model, "PauldronSpike" .. i, base.Position, tip.Position, 0.14 * c.S, 0.14 * c.S, GOLD, M.Foil)
	end
	-- storm crystals on its back, lightning between them
	G.backCluster(c, "CrystalBack", {
		{ 0, 1.0, 0, 2.6, 1.2, 0.32 },
		{ -0.25, 1.0, -0.8, 2.3, 1.05, 0.26 },
		{ 0.25, 1.0, 0.8, 2.3, 1.05, 0.26 },
		{ -0.3, 0.8, -1.0, 1.6, 0.85, 0.2 },
		{ 0.3, 0.8, 1.0, 1.6, 0.85, 0.2 },
	}, c.Look.Body, M.Glass)
	-- lightning in its gauntlets, storm orbs floating round it
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Bolt" .. i, c.At(side * 0.85, 0.66, -0.29) * CFrame.Angles(0, 0, side * 0.6), c.V(0.06, 0.32, 0.03), BOLT, NEON)
	end
	floating(c, "AuraOrb", 2, c.Glow, 0.22, true)
	shoulderGems(c, c.Glow)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, BOLT, 4, 0.16)
	end
	return top
end

local function celestial(c: Ctx): number
	royal(c)
	-- a gold crown of stars and a gold halo over it
	local top = G.crown(c, {
		Y = 2.84,
		Radius = 0.6,
		Height = 0.28,
		Points = 5,
		Point = 0.3,
		Color = GOLD,
		Material = M.Foil,
		Gems = { c.Glow, STAR, STAR },
	})
	G.ring(c, "Halo", 3.58, 0.16, 0.62, 8, 0.09, GOLD, NEON, 0.25)
	-- wings of light: a gold feather and two of light on each side
	for i, side in { -1, 1 } do
		for j = 1, 3 do
			if c.Room() < 1 then
				break
			end
			local l = 1.25 - (j - 1) * 0.22
			local angle = 0.3 + (j - 1) * 0.42
			T.ellipsoid(
				c.Model,
				`Wing{i}_{j}`,
				c.At(side * (0.5 + l * 0.42 * math.cos(angle)), 1.25 + l * 0.42 * math.sin(angle), 0.6)
					* CFrame.Angles(0, -side * 0.25, side * angle),
				c.V(l, 0.36, 0.08),
				if j == 1 then GOLD else LIGHT,
				if j == 1 then M.Foil else NEON
			)
		end
	end
	-- a star sceptre in the right hand (its star over the head's top: clear of it)
	if c.Room() >= 4 then
		G.held(c, "Staff", V(1.0, 0.1, -0.32), V(1.0, 2.62, -0.32), 0.09, GOLD, M.Foil)
		K.part(c.Model, "StaffHead", c.At(1.0, 2.66, -0.32), c.V(0.24, 0.12, 0.24), GOLD, M.Foil)
		G.diamond(c.Model, "Star1", c.At(1.0, 2.94, -0.32), 0.42 * c.S, 0.08 * c.S, STAR, NEON)
		K.part(c.Model, "Star2", c.At(1.0, 2.94, -0.32), c.V(0.42, 0.42, 0.08), STAR, NEON)
	end
	-- stars floating round it, stars on its shoulders
	floating(c, "AuraStar", 3, STAR, 0.22)
	shoulderGems(c, STAR)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, GOLD, 4)
		T.light(body, c.Glow, 8, 1.1)
	end
	return top
end

function Royal.costumes(kit: Kit, tools: Tools, gear: Gear): { [string]: (Ctx) -> number }
	K, T, G = kit, tools, gear
	return {
		SilverSquire = squire,
		RoseKnight = rose,
		GildedPorter = porter,
		MoonstoneOracle = moonstone,
		StormTitan = storm,
		CelestialSovereign = celestial,
	}
end

return Royal
