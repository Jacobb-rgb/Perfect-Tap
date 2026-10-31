--[[
	THE CRYSTAL EGG's golems (GolemConfig Family "Crystal"): the egg's
	armour set (EggGear/Clean) in gem colours: smooth plates in their ore's
	colour (a lighter face) over a darker under-suit, silver trim, a silver
	frame holding a crystal over the glowing core, crystals growing from
	the shoulders, the eyes in a dark visor, a cool glow. EggGear explains
	the contract. Each one's signature, readable small:

	  JadeGardener        (Common) a big sprout on its head, vines wrapped round its arms
	  AmethystAcolyte     (Uncommon) a hood crowned with crystals, a glowing rune,
	                      an orb floating by its hand
	  QuartzSprite        (Rare) wings of clear quartz panes, a quartz tiara, sparkles
	  SapphireSage        (Epic) a halo of light, a silver staff with a sapphire, a
	                      crystal mantle rising behind its shoulders, floating sapphires
	  DiamondDuke         (Legendary) a silver crown of diamonds, diamond shoulders,
	                      a monocle, a cane, diamonds floating round it, sparkles
	  HeartstoneColossus  (Mythic, retired) a glowing heart in a silver frame, great
	                      crystal shoulders, a crown of crystal spikes, a heartstone
	                      cluster on its back, heart shards floating round it, embers
	                      and its own light
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)
local Clean = require(script.Parent.Clean)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Gear = Clean.Gear

local Crystal = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local SILVER = rgb(216, 224, 238)
local GEM = M.Glass -- (opaque glass: a gem's shine)
local LEAF = rgb(96, 200, 92)
local LEAF_DARK = rgb(52, 120, 56)
local VINE = rgb(40, 110, 52)
local CLEAR = rgb(222, 216, 255)
local LILAC = rgb(172, 140, 246)

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- the Crystal egg's armour set and its emblem (band = false: a hood brings its
-- own rim; ridge = false: a sprout grows where the ridge would be)
local function crystal(c: Ctx, plate: Color3, band: boolean?, emblem: boolean?, ridge: boolean?)
	G.dress(c, {
		Plate = plate,
		PlateMaterial = M.SmoothPlastic,
		Head = K.lighter(plate, 0.15),
		HeadMaterial = M.SmoothPlastic,
		Suit = K.darker(plate, 0.6),
		SuitMaterial = M.Marble,
		Metal = SILVER,
		MetalMaterial = M.Metal,
		Belt = SILVER,
		BeltMaterial = M.Metal,
		Buckle = c.Glow,
		BuckleMaterial = NEON,
		Face = "Visor",
		Band = band,
		Ridge = ridge,
	})
	if emblem ~= false then
		G.gemFrame(c, SILVER, M.Metal, K.lighter(plate, 0.2), c.Glow)
	end
end

-- crystals growing up and out of the shoulder plates (they swing with the
-- arms): the first on top, the next behind it, the third at the front
local SHOULDER_GEMS = {
	{ 0.12, 0.0, 0.45, 0.0, 1.0 }, -- (out, back, tilt out, tilt back, size)
	{ 0.04, 0.26, 0.3, 0.35, 0.8 },
	{ 0.2, -0.22, 0.75, -0.25, 0.7 },
}
local function shoulderGems(c: Ctx, color: Color3, h: number, count: number)
	for i, side in { -1, 1 } do
		for j = 1, count do
			if c.Room() < 1 then
				return
			end
			local k = SHOULDER_GEMS[j]
			local hh = h * k[5]
			local at = Clean.shoulder(c, side)
				* CFrame.new(side * k[1] * c.S, 0.16 * c.S, k[2] * c.S)
				* CFrame.Angles(k[4], 0, -side * k[3])
				* CFrame.new(0, hh * 0.4 * c.S, 0)
			G.shard(c, `PauldronGem{i}_{j}`, at, 0.2 * k[5], hh, color, GEM)
		end
	end
end

-- a gem on the forehead, over the visor
local function browGem(c: Ctx, color: Color3)
	if c.Room() >= 1 then
		G.diamond(c.Model, "BrowGem", c.At(0, 2.4, -0.69), 0.22 * c.S, 0.04 * c.S, color, NEON)
	end
end

-- `n` gems floating round it at shoulder height (named Aura*: they stay with the body)
local function floating(c: Ctx, name: string, n: number, color: Color3, size: number)
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local a = (i - 1) / n * 2 * PI + 0.5
		G.diamond(
			c.Model,
			name .. i,
			c.At(math.cos(a) * 1.3, 1.15 + i * 0.28, math.sin(a) * 1.05) * CFrame.Angles(0, a, 0),
			size * c.S,
			0.07 * c.S,
			color,
			NEON
		)
	end
end

---------------------------------------------------------------- the costumes

local function jade(c: Ctx): number
	crystal(c, c.Look.Body, true, true, false)
	-- a big sprout on its head
	if c.Room() >= 3 then
		K.part(c.Model, "Stem", c.At(0, 2.92, 0), c.V(0.11, 0.46, 0.11), LEAF_DARK)
		K.part(c.Model, "Leaf1", c.At(0.34, 3.18, 0) * CFrame.Angles(0, 0, 0.45), c.V(0.78, 0.08, 0.46), LEAF)
		K.part(c.Model, "Leaf2", c.At(-0.28, 3.1, 0) * CFrame.Angles(0, 0, -0.5), c.V(0.6, 0.08, 0.36), LEAF)
	end
	-- vines wrapped round its arms, a leaf on one
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Vine" .. i, c.At(side * 0.81, 1.0, 0) * CFrame.Angles(0, 0, side * 0.35), c.V(0.44, 0.08, 0.54), VINE)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "VineLeaf", c.At(0.98, 1.08, -0.2) * CFrame.Angles(0.3, 0, -0.6), c.V(0.3, 0.05, 0.2), LEAF)
	end
	return 3.36
end

local function amethyst(c: Ctx): number
	crystal(c, c.Look.Body, false)
	-- a smooth hood crowned with crystals (rounded like a helm; the head under it is rounded too)
	local hood = c.Look.Trim
	K.part(c.Model, "Helm", c.At(0, 2.2, 0.1), c.V(1.68, 1.14, 1.3), hood, M.SmoothPlastic)
	local head = c.Model:FindFirstChild("Head")
	if head then
		head:SetAttribute("Round", true)
	end
	G.crystal(c, "HoodCrystal1", V(0, 2.6, 0.3), V(0, 3.3, 0.55), 0.26, K.lighter(c.Look.Body, 0.2), GEM)
	G.crystal(c, "HoodCrystal2", V(-0.45, 2.6, 0.3), V(-0.75, 3.05, 0.5), 0.18, c.Look.Body, GEM)
	-- its silver rim and a glowing rune on it
	if c.Room() >= 2 then
		K.part(c.Model, "HoodRim", c.At(0, 2.66, -0.56), c.V(1.36, 0.1, 0.06), SILVER, M.Metal)
		G.diamond(c.Model, "Rune", c.At(0, 2.66, -0.6), 0.22 * c.S, 0.04 * c.S, c.Glow, NEON)
	end
	-- an orb floating by its left hand in a silver ring
	if c.Room() >= 2 then
		K.part(c.Model, "Orb", c.At(-1.14, 1.0, -0.42), c.V(0.36, 0.36, 0.36), c.Glow, NEON, BALL)
		K.upright(c.Model, "OrbRing", c.At(-1.14, 1.0, -0.42) * CFrame.Angles(0.5, 0, 0.3), 0.04 * c.S, 0.56 * c.S, SILVER, M.Metal)
	end
	return 3.3
end

local function quartz(c: Ctx): number
	crystal(c, rgb(190, 170, 246))
	-- a quartz tiara on the band
	for i, k in { { -0.3, 0.2 }, { 0, 0.32 }, { 0.3, 0.2 } } do
		if c.Room() < 1 then
			break
		end
		G.diamond(c.Model, "Tiara" .. i, c.At(k[1], 2.48 + k[2] * 0.3, -0.7), k[2] * c.S, 0.06 * c.S, CLEAR, GEM)
	end
	-- wings of clear quartz panes fanning from its back
	for i, side in { -1, 1 } do
		for j, k in { { 1.0, 2.5, 0.34, 1.0 }, { 1.3, 1.92, 0.3, 0.95 }, { 1.1, 1.34, 0.24, 0.88 } } do
			if c.Room() < 1 then
				break
			end
			T.seg(
				c.Model,
				`Wing{i}_{j}`,
				T.P(c, side * 0.2, 1.15, 0.5),
				T.P(c, side * k[1], k[2], k[4]),
				k[3] * c.S,
				0.06 * c.S,
				if j == 2 then CLEAR else LILAC,
				GEM
			)
		end
	end
	shoulderGems(c, CLEAR, 0.42, 1)
	-- glints in the wings
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		G.diamond(c.Model, `WingGlint{i}`, c.At(side * 0.7, 1.92, 0.86), 0.18 * c.S, 0.04 * c.S, c.Glow, NEON)
	end
	floating(c, "AuraSpark", 2, c.Glow, 0.16)
	return 3.0
end

local function sapphire(c: Ctx): number
	crystal(c, c.Look.Body)
	browGem(c, c.Glow)
	-- a halo of light over its head
	G.ring(c, "Halo", 3.14, 0.1, 0.56, 8, 0.08, c.Glow, NEON, 0.2)
	-- a silver staff crowned with a sapphire (clear of the head: it swings with the arm)
	if c.Room() >= 5 then
		G.held(c, "Staff", V(1.0, 0.1, -0.32), V(1.0, 2.3, -0.32), 0.09, SILVER, M.Metal)
		K.upright(c.Model, "StaffHead", c.At(1.0, 2.32, -0.32), 0.1 * c.S, 0.3 * c.S, SILVER, M.Metal)
		for i, side in { -1, 1 } do
			T.seg(
				c.Model,
				"StaffProng" .. i,
				T.P(c, 1.0, 2.34, -0.32),
				T.P(c, 1.0 + side * 0.16, 2.68, -0.32),
				0.05 * c.S,
				0.05 * c.S,
				SILVER,
				M.Metal
			)
		end
		G.shard(c, "Orb", c.At(1.0, 2.62, -0.32), 0.26, 0.46, c.Look.Body, GEM)
	end
	-- a crystal mantle rising behind its shoulders
	G.backCluster(c, "CrystalMantle", {
		{ -0.4, 1.1, -0.95, 2.2, 0.82, 0.22 },
		{ 0.4, 1.1, 0.95, 2.2, 0.82, 0.22 },
		{ -0.2, 1.05, -0.6, 2.45, 1.0, 0.18 },
		{ 0.2, 1.05, 0.6, 2.45, 1.0, 0.18 },
	}, K.lighter(c.Look.Body, 0.15), GEM)
	floating(c, "AuraGem", 2, c.Glow, 0.2)
	return 3.35
end

local function diamond(c: Ctx): number
	crystal(c, c.Look.Body)
	-- a silver crown of diamonds
	local top = G.crown(c, {
		Y = 2.84,
		Radius = 0.58,
		Height = 0.26,
		Points = 5,
		Point = 0.28,
		Color = SILVER,
		Material = M.Metal,
		PointColor = CLEAR,
		PointMaterial = GEM,
		Gems = { c.Glow, rgb(140, 220, 255), rgb(140, 220, 255) },
	})
	-- diamonds growing from its shoulders
	shoulderGems(c, K.lighter(c.Look.Body, 0.2), 0.5, 2)
	-- a monocle over its right eye (a silver rim behind the glowing eye, glass in front), its chain
	if c.Room() >= 3 then
		K.facing(c.Model, "Monocle", c.At(0.28, 2.02, -0.69), 0.02 * c.S, 0.42 * c.S, SILVER, M.Metal)
		local lens = K.facing(c.Model, "MonocleLens", c.At(0.28, 2.02, -0.725), 0.02 * c.S, 0.36 * c.S, rgb(220, 240, 255), M.Glass)
		lens.Transparency = 0.5
		T.seg(c.Model, "MonocleChain", T.P(c, 0.48, 1.94, -0.69), T.P(c, 0.36, 1.34, -0.49), 0.03 * c.S, 0.03 * c.S, SILVER, M.Metal)
	end
	-- a silver cane with a diamond knob
	if c.Room() >= 2 then
		G.held(c, "Cane", V(1.06, 0.04, -0.42), V(1.02, 1.12, -0.32), 0.08, SILVER, M.Metal)
		G.shard(c, "CaneGem", c.At(1.02, 1.2, -0.32), 0.22, 0.28, c.Look.Body, GEM)
	end
	-- diamonds floating round it, two on its back
	floating(c, "AuraDiamond", 3, rgb(200, 236, 255), 0.22)
	G.backCluster(c, "CrystalBack", { { -0.2, 1.0, -0.6, 2.0, 0.95, 0.22 }, { 0.2, 1.0, 0.55, 2.2, 1.05, 0.26 } }, c.Look.Body, GEM)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, rgb(200, 236, 255), 3, 0.14)
	end
	return top
end

local function heartstone(c: Ctx): number
	local deep = c.Look.Body
	crystal(c, deep, true, false)
	-- a glowing heart in a silver frame (the core is its point, two balls its top)
	if c.Room() >= 1 then
		G.diamond(c.Model, "CorePlate", c.At(0, 1.02, -0.495), 0.5 * c.S, 0.04 * c.S, SILVER, M.Metal)
	end
	T.redress(c, "Core", c.At(0, 0.98, -0.525) * CFrame.Angles(0, 0, PI / 4), c.V(0.26, 0.26, 0.03), c.Glow, NEON)
	for i, x in { -0.09, 0.09 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Heart" .. i, c.At(x, 1.1, -0.515), c.V(0.2, 0.2, 0.06), c.Glow, NEON, BALL)
	end
	-- great crystal shoulders
	shoulderGems(c, deep, 0.62, 3)
	-- a crown of crystal spikes
	for i, k in { { -0.42, 0.32, 0.4 }, { -0.2, 0.46, 0.18 }, { 0, 0.58, 0 }, { 0.2, 0.46, -0.18 }, { 0.42, 0.32, -0.4 } } do
		if c.Room() < 1 then
			break
		end
		G.shard(c, "Spike" .. i, c.At(k[1], 2.7 + k[2] * 0.4, -0.2) * CFrame.Angles(0, 0, k[3]), 0.18, k[2], deep, GEM)
	end
	-- the great heartstone cluster on its back, a glowing one among them
	G.backCluster(c, "CrystalBack", {
		{ 0, 1.0, 0, 2.6, 1.2, 0.36 },
		{ -0.25, 1.0, -0.8, 2.3, 1.05, 0.28 },
		{ 0.25, 1.0, 0.8, 2.3, 1.05, 0.28 },
		{ -0.3, 0.8, -1.0, 1.6, 0.85, 0.22 },
		{ 0.3, 0.8, 1.0, 1.6, 0.85, 0.22 },
	}, deep, GEM)
	G.backCluster(c, "CrystalGlow", { { 0.14, 1.0, 0.42, 2.1, 1.12, 0.12 } }, c.Glow, NEON)
	-- heart shards floating round it, gems on its boots
	floating(c, "AuraShard", 3, c.Glow, 0.22)
	for i, x in { -0.3, 0.3 } do
		if c.Room() < 1 then
			break
		end
		G.diamond(c.Model, "BootGem" .. i, c.At(x, 0.16, -0.38), 0.16 * c.S, 0.04 * c.S, c.Glow, NEON)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 4)
		T.light(body, c.Glow, 8, 1.1)
	end
	return 3.5
end

function Crystal.costumes(kit: Kit, tools: Tools, gear: Gear): { [string]: (Ctx) -> number }
	K, T, G = kit, tools, gear
	return {
		JadeGardener = jade,
		AmethystAcolyte = amethyst,
		QuartzSprite = quartz,
		SapphireSage = sapphire,
		DiamondDuke = diamond,
		HeartstoneColossus = heartstone,
	}
end

return Crystal
