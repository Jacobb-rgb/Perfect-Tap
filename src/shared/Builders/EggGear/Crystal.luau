--[[
	THE CRYSTAL EGG's golems (GolemConfig Family "Crystal"): clean light
	bodies (polished stone in a pale shade of their ore), gem plates in the
	ore's own colour (shoulders, boots), crystals growing from the shoulder
	plates, a visor of the dark gem for the glowing eyes, silver trim
	(gauntlets, the belt, the emblem's frame) and a cool glow; EggGear
	explains the contract. Each
	keeps its old accessory's idea, cleaner:

	  JadeGardener        (Common) a sprouting leaf, a jade gem on its circlet
	  AmethystAcolyte     (Uncommon) a smooth hood with a silver rim and a glowing rune
	  QuartzSprite        (Rare) wings of clear quartz panes, a quartz tiara
	  SapphireSage        (Epic) a halo of light, a silver staff with a sapphire
	  DiamondDuke         (Legendary) a silver crown of diamonds, a monocle, a cane, sparkles
	  HeartstoneColossus  (Mythic, retired) a great heartstone cluster on its back,
	                      a glowing heart on its chest, a crown of crystal spikes,
	                      heart shards floating round it, embers and its own light
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
local CLEAR = rgb(214, 208, 255)
local LILAC = rgb(172, 140, 246)

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

-- the Crystal egg's look every one of them wears; `gem` = the gem plates'
-- colour (the ore's), rims = silver rims under the shoulder plates
local function crystal(c: Ctx, gem: Color3, rims: boolean, skin: Color3?)
	G.dress(c, {
		Skin = skin or K.lighter(c.Look.Body, 0.3),
		SkinMaterial = M.Marble,
		Torso = (skin or K.lighter(c.Look.Body, 0.3)):Lerp(gem, 0.6),
		Boots = gem,
		BootMaterial = M.Marble,
		Armour = SILVER,
		ArmourMaterial = M.Metal,
		Belt = SILVER,
		BeltMaterial = M.Metal,
		Buckle = c.Glow,
		BuckleMaterial = NEON,
		Face = "Visor",
		FaceColor = K.darker(gem, 0.6),
	})
	G.pauldrons(c, gem, GEM, if rims then SILVER else nil, M.Metal)
	G.collar(c, SILVER, M.Metal)
	G.emblem(c, SILVER, M.Metal, c.Glow)
end

-- a crystal growing up and out of each shoulder plate (it swings with the arm)
local function shoulderGems(c: Ctx, color: Color3, h: number, second: boolean?)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			return
		end
		G.shard(c, "PauldronGem" .. i, c.At(side * 0.92, 1.58 + h * 0.32, 0.06) * CFrame.Angles(0, 0, -side * 0.45), 0.2, h, color, GEM)
		if second and c.Room() >= 1 then
			G.shard(
				c,
				"PauldronGem" .. i .. "b",
				c.At(side * 0.74, 1.58 + h * 0.24, 0.2) * CFrame.Angles(0.25, 0, -side * 0.2),
				0.16,
				h * 0.7,
				color,
				GEM
			)
		end
	end
end

-- a gem on the forehead
local function browGem(c: Ctx, color: Color3)
	if c.Room() >= 1 then
		G.diamond(c.Model, "BrowGem", c.At(0, 2.4, -0.67), 0.2 * c.S, 0.04 * c.S, color, NEON)
	end
end

---------------------------------------------------------------- the costumes

local function jade(c: Ctx): number
	crystal(c, c.Look.Body, false)
	-- the sprouting leaf on its head
	if c.Room() >= 3 then
		K.part(c.Model, "Stem", c.At(0, 2.86, 0), c.V(0.09, 0.34, 0.09), LEAF_DARK)
		K.part(c.Model, "Leaf1", c.At(0.24, 3.05, 0) * CFrame.Angles(0, 0, 0.45), c.V(0.54, 0.07, 0.34), LEAF)
		K.part(c.Model, "Leaf2", c.At(-0.18, 2.99, 0) * CFrame.Angles(0, 0, -0.5), c.V(0.38, 0.07, 0.26), LEAF)
	end
	shoulderGems(c, c.Look.Body, 0.36)
	browGem(c, c.Glow)
	return 3.2
end

local function amethyst(c: Ctx): number
	crystal(c, c.Look.Body, false)
	-- a smooth hood (rounded like a helm; the head under it is rounded too)
	local hood = c.Look.Trim
	K.part(c.Model, "Helm", c.At(0, 2.2, 0.1), c.V(1.68, 1.14, 1.3), hood, M.Fabric)
	local head = c.Model:FindFirstChild("Head")
	if head then
		head:SetAttribute("Round", true)
	end
	if c.Room() >= 1 then
		G.diamond(c.Model, "HoodTip", c.At(0, 2.74, 0.42) * CFrame.Angles(0, PI / 2, 0), 0.5 * c.S, 0.1 * c.S, hood, M.Fabric)
	end
	-- its silver rim and a glowing rune on it
	if c.Room() >= 2 then
		K.part(c.Model, "HoodRim", c.At(0, 2.66, -0.555), c.V(1.36, 0.1, 0.06), SILVER, M.Metal)
		G.diamond(c.Model, "Rune", c.At(0, 2.66, -0.6), 0.22 * c.S, 0.04 * c.S, c.Glow, NEON)
	end
	shoulderGems(c, c.Look.Body, 0.4)
	return 3.0
end

local function quartz(c: Ctx): number
	crystal(c, LILAC, true, rgb(222, 216, 240))
	-- a quartz tiara on the circlet
	for i, k in { { -0.3, 0.18 }, { 0, 0.28 }, { 0.3, 0.18 } } do
		if c.Room() < 1 then
			break
		end
		G.diamond(c.Model, "Tiara" .. i, c.At(k[1], 2.4 + k[2] * 0.4, -0.7), k[2] * c.S, 0.06 * c.S, CLEAR, GEM)
	end
	-- wings of clear quartz panes fanning from its back
	for i, side in { -1, 1 } do
		for j, k in { { 0.98, 2.42, 0.32, 1.0 }, { 1.24, 1.9, 0.28, 0.95 }, { 1.06, 1.36, 0.22, 0.88 } } do
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
	shoulderGems(c, CLEAR, 0.4)
	-- glints in the wings
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		G.diamond(c.Model, `WingGlint{i}`, c.At(side * 0.66, 1.9, 0.86), 0.16 * c.S, 0.04 * c.S, c.Glow, NEON)
	end
	return 3.0
end

local function sapphire(c: Ctx): number
	crystal(c, c.Look.Body, true)
	browGem(c, c.Glow)
	-- a halo of light over its head
	G.ring(c, "Halo", 3.12, 0.1, 0.55, 8, 0.07, c.Glow, NEON, 0.2)
	-- a silver staff crowned with a sapphire
	if c.Room() >= 5 then
		G.held(c, "Staff", Vector3.new(0.98, 0.1, -0.32), Vector3.new(0.98, 2.3, -0.32), 0.09, SILVER, M.Metal)
		K.upright(c.Model, "StaffHead", c.At(0.98, 2.32, -0.32), 0.1 * c.S, 0.3 * c.S, SILVER, M.Metal)
		for i, side in { -1, 1 } do
			T.seg(
				c.Model,
				"StaffProng" .. i,
				T.P(c, 0.98, 2.34, -0.32),
				T.P(c, 0.98 + side * 0.16, 2.66, -0.32),
				0.05 * c.S,
				0.05 * c.S,
				SILVER,
				M.Metal
			)
		end
		G.shard(c, "Orb", c.At(0.98, 2.6, -0.32), 0.24, 0.42, c.Look.Body, GEM)
	end
	shoulderGems(c, c.Look.Body, 0.44)
	-- two sapphires on its back
	G.backCluster(c, "CrystalBack", { { -0.2, 1.0, -0.55, 1.95, 0.95, 0.2 }, { 0.2, 1.0, 0.5, 2.1, 1.0, 0.24 } }, c.Look.Body, GEM)
	return 3.3
end

local function diamond(c: Ctx): number
	crystal(c, c.Look.Body, true)
	-- a silver crown of diamonds
	local top = G.crown(c, {
		Y = 2.82,
		Radius = 0.56,
		Height = 0.24,
		Points = 5,
		Point = 0.24,
		Color = SILVER,
		Material = M.Metal,
		Gems = { c.Glow, rgb(140, 220, 255), rgb(140, 220, 255) },
	})
	-- a monocle over its right eye (a silver rim behind the glowing eye, glass in front), its chain
	if c.Room() >= 3 then
		K.facing(c.Model, "Monocle", c.At(0.28, 2.02, -0.69), 0.02 * c.S, 0.42 * c.S, SILVER, M.Metal)
		local lens = K.facing(c.Model, "MonocleLens", c.At(0.28, 2.02, -0.725), 0.02 * c.S, 0.36 * c.S, rgb(220, 240, 255), M.Glass)
		lens.Transparency = 0.5
		T.seg(c.Model, "MonocleChain", T.P(c, 0.48, 1.94, -0.69), T.P(c, 0.36, 1.32, -0.47), 0.03 * c.S, 0.03 * c.S, SILVER, M.Metal)
	end
	shoulderGems(c, c.Look.Body, 0.42, true)
	-- a silver cane with a diamond knob
	if c.Room() >= 2 then
		G.held(c, "Cane", Vector3.new(0.88, 0.04, -0.4), Vector3.new(0.86, 1.1, -0.32), 0.08, SILVER, M.Metal)
		G.shard(c, "CaneGem", c.At(0.86, 1.18, -0.32), 0.2, 0.26, c.Look.Body, GEM)
	end
	-- diamonds on its back
	G.backCluster(c, "CrystalBack", { { -0.2, 1.0, -0.6, 2.0, 0.95, 0.22 }, { 0.2, 1.0, 0.55, 2.2, 1.05, 0.26 } }, c.Look.Body, GEM)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, rgb(200, 236, 255), 3, 0.14)
	end
	return top
end

local function heartstone(c: Ctx): number
	local deep = c.Look.Body
	crystal(c, deep, true)
	-- a glowing heart on the chest (the core is its point, two balls its top)
	T.redress(c, "Core", c.At(0, 1.0, -0.505) * CFrame.Angles(0, 0, PI / 4), c.V(0.28, 0.28, 0.03), c.Glow, NEON)
	for i, x in { -0.1, 0.1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Heart" .. i, c.At(x, 1.12, -0.49), c.V(0.22, 0.22, 0.06), c.Glow, NEON, BALL)
	end
	-- a crown of crystal spikes
	for i, k in { { -0.42, 0.3, 0.4 }, { -0.2, 0.42, 0.18 }, { 0, 0.52, 0 }, { 0.2, 0.42, -0.18 }, { 0.42, 0.3, -0.4 } } do
		if c.Room() < 1 then
			break
		end
		G.shard(c, "Spike" .. i, c.At(k[1], 2.7 + k[2] * 0.4, -0.2) * CFrame.Angles(0, 0, k[3]), 0.18, k[2], deep, GEM)
	end
	-- the great heartstone cluster on its back, a glowing one among them
	G.backCluster(c, "CrystalBack", {
		{ 0, 1.0, 0, 2.55, 1.2, 0.36 },
		{ -0.25, 1.0, -0.78, 2.25, 1.05, 0.28 },
		{ 0.25, 1.0, 0.78, 2.25, 1.05, 0.28 },
		{ -0.3, 0.8, -0.98, 1.55, 0.85, 0.22 },
		{ 0.3, 0.8, 0.98, 1.55, 0.85, 0.22 },
	}, deep, GEM)
	G.backCluster(c, "CrystalGlow", { { 0.14, 1.0, 0.4, 2.05, 1.12, 0.12 } }, c.Glow, NEON)
	shoulderGems(c, deep, 0.46, true)
	-- heart shards floating round it (they stay with the body)
	for i = 1, 3 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 1) / 3 * 2 * PI + 0.5
		G.diamond(
			c.Model,
			"AuraShard" .. i,
			c.At(math.cos(a) * 1.25, 1.2 + i * 0.25, math.sin(a) * 1.0) * CFrame.Angles(0, a, 0),
			0.2 * c.S,
			0.06 * c.S,
			c.Glow,
			NEON
		)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 4)
		T.light(body, c.Glow, 8, 1.1)
	end
	return 3.3
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
