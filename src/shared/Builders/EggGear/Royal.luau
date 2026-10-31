--[[
	THE ROYAL EGG's golems (GolemConfig Family "Royal"; owner: royal =
	"divine"): armour of their ore's metal trimmed with gold, like the
	Royal egg (pearl and gold, a halo): shoulder plates on gold rims, a
	gold collar, a gold-framed gem on the chest, gold gauntlets, a gold belt with a glowing
	gem, a dark visor for the glowing eyes; crests, crowns and halos. No capes (a
	cape is the Dragon King's alone). EggGear explains the contract. Each
	keeps its old accessory's idea, cleaner:

	  SilverSquire        (Uncommon) a rounded squire's helm with a red plume, a gold nose guard
	  RoseKnight          (Rare) a closed rose helm (the eyes glow through its slit), a gold crest
	                      with a rose, a pearl kite shield, a sword
	  GildedPorter        (Rare, retired) a velvet porter's cap with a miner's lamp, a satchel of gold
	                      coins on its back, a railway lantern
	  MoonstoneOracle     (Epic) a halo of moonlight, a gold crescent with a moonstone, an orb staff
	  StormTitan          (Legendary) a storm helm with gold wing crests and a lightning crest,
	                      storm crystals on its back, lightning in its gauntlets, sparks
	  CelestialSovereign  (Mythic) a gold crown of stars under a gold halo, small gold angel
	                      wings, a star sceptre, stars floating round it, embers and its own light
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

local K: Kit = nil :: any
local T: Tools = nil :: any
local G: Gear = nil :: any

-- the Royal egg's look every one of them wears (`gold`: the trim's gold,
-- deeper on a golden golem)
local function royal(c: Ctx, gold: Color3?)
	local trim = gold or GOLD
	G.dress(c, {
		Skin = K.lighter(c.Look.Body, 0.12),
		SkinMaterial = M.Metal,
		Torso = c.Look.Body:Lerp(c.Look.Trim, 0.45),
		Boots = c.Look.Trim,
		BootMaterial = M.Metal,
		Armour = GOLD, -- (the egg's gauntlets, the same on every one)
		ArmourMaterial = M.Foil,
		Belt = trim,
		BeltMaterial = M.Foil,
		Buckle = c.Glow,
		BuckleMaterial = NEON,
		Face = "Visor",
		FaceColor = SLIT,
	})
	G.pauldrons(c, K.lighter(c.Look.Body, 0.22), M.Metal, trim, M.Foil)
	G.collar(c, trim, M.Foil)
	G.emblem(c, trim, M.Foil, c.Glow)
end

-- a glowing gem on top of each shoulder plate (they swing with the arms)
local function shoulderGems(c: Ctx, color: Color3)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			return
		end
		local at = c.At(side * 0.8, 1.42, 0) * CFrame.Angles(0, 0, -side * 0.25) * CFrame.new(0, 0.2 * c.S, 0)
		G.diamond(c.Model, "PauldronGem" .. i, at * CFrame.Angles(PI / 2, 0, 0), 0.2 * c.S, 0.04 * c.S, color, NEON)
	end
end

-- a rounded half helm over the top of the head (the head under it is rounded too)
local function halfHelm(c: Ctx, color: Color3)
	K.part(c.Model, "Helm", c.At(0, 2.56, 0.02), c.V(1.6, 0.46, 1.42), color, M.Metal)
	local head = c.Model:FindFirstChild("Head")
	if head then
		head:SetAttribute("Round", true)
	end
end

---------------------------------------------------------------- the costumes

local function squire(c: Ctx): number
	royal(c)
	halfHelm(c, K.lighter(c.Look.Body, 0.25))
	-- a gold nose guard over the visor, a red plume
	if c.Room() >= 1 then
		K.part(c.Model, "NoseGuard", c.At(0, 2.16, -0.69), c.V(0.12, 0.36, 0.05), GOLD, M.Foil)
	end
	if c.Room() >= 1 then
		T.ellipsoid(c.Model, "Plume", c.At(0, 2.98, 0.22) * CFrame.Angles(0.35, 0, 0), c.V(0.2, 0.5, 0.95), PLUME, M.Fabric)
	end
	return 3.2
end

local function rose(c: Ctx): number
	royal(c)
	-- the closed rose helm, the eyes glowing through its slit under a gold brow
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), K.lighter(c.Look.Body, 0.08), M.Metal)
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
	if c.Room() >= 2 then
		K.part(c.Model, "Crest", c.At(0, 2.96, 0.08), c.V(0.12, 0.4, 1.1), GOLD, M.Foil)
		G.diamond(c.Model, "Rose", c.At(0, 2.98, -0.5) * CFrame.Angles(0, PI / 2, 0), 0.24 * c.S, 0.1 * c.S, c.Look.Body, NEON)
	end
	-- a pearl kite shield on the left arm with a glowing rose, on a gold rim
	if c.Room() >= 4 then
		local shield = c.At(-1.06, 0.98, -0.3) * CFrame.Angles(0, PI / 5, 0)
		K.part(c.Model, "ShieldRim", shield * CFrame.new(0, 0, 0.03 * c.S), c.V(0.88, 0.7, 0.08), GOLD, M.Foil)
		K.part(c.Model, "Shield", shield, c.V(0.8, 0.62, 0.1), PEARL, M.Marble)
		G.diamond(c.Model, "ShieldPoint", shield * CFrame.new(0, -0.3 * c.S, 0), 0.57 * c.S, 0.1 * c.S, PEARL, M.Marble)
		G.diamond(c.Model, "ShieldRose", shield * CFrame.new(0, -0.08 * c.S, -0.06 * c.S), 0.24 * c.S, 0.03 * c.S, c.Glow, NEON)
	end
	-- a sword in the right fist
	if c.Room() >= 3 then
		local from, to = T.P(c, 0.92, 0.86, -0.22), T.P(c, 1.08, 2.4, -0.72)
		T.seg(c.Model, "Blade", from, to, 0.2 * c.S, 0.05 * c.S, BLADE, M.Metal)
		T.seg(c.Model, "Guard", T.P(c, 0.66, 0.8, -0.16), T.P(c, 1.2, 0.86, -0.2), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Pommel", c.At(0.88, 0.42, -0.04), c.V(0.16, 0.16, 0.16), GOLD, M.Foil, BALL)
	end
	return 3.2
end

local function porter(c: Ctx): number
	royal(c, GOLD_DEEP)
	-- a velvet porter's cap on a gold brim, a miner's lamp on it
	if c.Room() >= 5 then
		K.upright(c.Model, "Helmet", c.At(0, 2.84, 0.02), 0.32 * c.S, 1.5 * c.S, VELVET, M.Fabric)
		T.ellipsoid(c.Model, "HelmetDome", c.At(0, 2.98, 0.02), c.V(1.48, 0.5, 1.48), VELVET, M.Fabric)
		K.upright(c.Model, "Brim", c.At(0, 2.68, 0.0), 0.07 * c.S, 1.7 * c.S, GOLD_DEEP, M.Foil)
		K.facing(c.Model, "Lamp", c.At(0, 2.88, -0.74), 0.22 * c.S, 0.42 * c.S, GOLD_DEEP, M.Foil)
		K.facing(c.Model, "LampLens", c.At(0, 2.88, -0.86), 0.04 * c.S, 0.3 * c.S, rgb(255, 244, 190), NEON)
	end
	-- a velvet satchel of gold coins on its back
	if c.Room() >= 3 then
		T.ellipsoid(c.Model, "Satchel", c.At(0, 0.98, 0.66), c.V(0.86, 0.74, 0.5), VELVET, M.Fabric)
		K.upright(c.Model, "Coin1", c.At(0.14, 1.28, 0.7) * CFrame.Angles(0.3, 0, 0.2), 0.06 * c.S, 0.3 * c.S, GOLD, M.Foil)
		K.upright(c.Model, "Coin2", c.At(-0.12, 1.3, 0.64) * CFrame.Angles(-0.2, 0, -0.3), 0.06 * c.S, 0.28 * c.S, GOLD, M.Foil)
	end
	-- a railway lantern in its left hand
	if c.Room() >= 2 then
		K.part(c.Model, "Lantern", c.At(-0.88, 0.38, -0.3), c.V(0.26, 0.32, 0.26), GOLD_DEEP, M.Foil)
		K.part(c.Model, "LanternLight", c.At(-0.88, 0.38, -0.3), c.V(0.2, 0.22, 0.3), rgb(255, 226, 140), NEON)
	end
	return 3.25
end

local function moonstone(c: Ctx): number
	royal(c)
	-- a halo of moonlight
	G.ring(c, "Halo", 3.2, 0.1, 0.56, 8, 0.07, c.Glow, NEON, 0.2)
	-- a gold crescent moon rising from its forehead, a moonstone in its cup
	local arc = {
		Vector3.new(-0.46, 3.14, -0.68),
		Vector3.new(-0.44, 2.86, -0.68),
		Vector3.new(-0.26, 2.66, -0.68),
		Vector3.new(0, 2.6, -0.68),
		Vector3.new(0.26, 2.66, -0.68),
		Vector3.new(0.44, 2.86, -0.68),
		Vector3.new(0.46, 3.14, -0.68),
	}
	for i = 1, #arc - 1 do
		if c.Room() < 1 then
			break
		end
		local a, b = arc[i], arc[i + 1]
		local w = if i == 1 or i == 6 then 0.08 elseif i == 2 or i == 5 then 0.13 else 0.16
		local dir = (b - a).Unit
		local from, to = a - dir * (w * 0.4), b + dir * (w * 0.4)
		T.seg(c.Model, "Crescent" .. i, T.P(c, from.X, from.Y, from.Z), T.P(c, to.X, to.Y, to.Z), w * c.S, 0.08 * c.S, GOLD, M.Foil)
	end
	if c.Room() >= 1 then
		G.diamond(c.Model, "Moonstone", c.At(0, 2.84, -0.7), 0.22 * c.S, 0.05 * c.S, c.Glow, NEON)
	end
	-- an oracle's staff with a glowing orb in a gold cup
	if c.Room() >= 3 then
		G.held(c, "Staff", Vector3.new(0.98, 0.1, -0.32), Vector3.new(0.98, 2.3, -0.32), 0.09, GOLD, M.Foil)
		K.upright(c.Model, "StaffHead", c.At(0.98, 2.34, -0.32), 0.12 * c.S, 0.32 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Orb", c.At(0.98, 2.56, -0.32), c.V(0.34, 0.34, 0.34), c.Glow, NEON, BALL)
	end
	shoulderGems(c, c.Glow)
	return 3.3
end

local function storm(c: Ctx): number
	royal(c)
	-- a storm helm: gold wing crests, a lightning crest on top
	halfHelm(c, c.Look.Trim)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		T.ellipsoid(
			c.Model,
			"HelmWing" .. i,
			c.At(side * 0.86, 2.68, 0.12) * CFrame.Angles(0, 0, side * 0.75),
			c.V(0.8, 0.26, 0.1),
			GOLD,
			M.Foil
		)
	end
	local zig = { Vector3.new(0, 2.76, -0.1), Vector3.new(0.1, 3.0, 0.0), Vector3.new(-0.06, 3.14, 0.1), Vector3.new(0.06, 3.42, 0.2) }
	for i = 1, #zig - 1 do
		if c.Room() < 1 then
			break
		end
		local a, b = zig[i], zig[i + 1]
		T.seg(c.Model, "HelmBolt" .. i, T.P(c, a.X, a.Y, a.Z), T.P(c, b.X, b.Y, b.Z), 0.12 * c.S, 0.06 * c.S, BOLT, NEON)
	end
	-- storm crystals on its back, lightning between them
	G.backCluster(c, "CrystalBack", {
		{ 0, 1.0, 0, 2.6, 1.2, 0.32 },
		{ -0.25, 1.0, -0.8, 2.3, 1.05, 0.26 },
		{ 0.25, 1.0, 0.8, 2.3, 1.05, 0.26 },
		{ -0.3, 0.8, -1.0, 1.6, 0.85, 0.2 },
		{ 0.3, 0.8, 1.0, 1.6, 0.85, 0.2 },
	}, c.Look.Body, M.Glass)
	for i, k in { { -0.2, 1.3, 0.4 }, { 0.2, 1.36, -0.4 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "CrystalBolt" .. i, c.At(k[1], k[2], 0.7) * CFrame.Angles(0, 0, k[3]), c.V(0.06, 0.4, 0.04), BOLT, NEON)
	end
	-- lightning in its gauntlets
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Bolt" .. i, c.At(side * 0.85, 0.66, -0.29) * CFrame.Angles(0, 0, side * 0.6), c.V(0.06, 0.32, 0.03), BOLT, NEON)
	end
	shoulderGems(c, c.Glow)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, BOLT, 4, 0.16)
	end
	return 3.5
end

local function celestial(c: Ctx): number
	royal(c)
	-- a gold crown of stars and a gold halo over it
	local top = G.crown(c, {
		Y = 2.84,
		Radius = 0.58,
		Height = 0.26,
		Points = 5,
		Point = 0.26,
		Color = GOLD,
		Material = M.Foil,
		Gems = { c.Glow, rgb(255, 240, 160), rgb(255, 240, 160) },
	})
	G.ring(c, "Halo", 3.55, 0.16, 0.6, 8, 0.08, GOLD, NEON, 0.25)
	-- small gold angel wings
	for i, side in { -1, 1 } do
		for j = 1, 3 do
			if c.Room() < 1 then
				break
			end
			local l = 1.0 - (j - 1) * 0.2
			local angle = 0.35 + (j - 1) * 0.4
			T.ellipsoid(
				c.Model,
				`Wing{i}_{j}`,
				c.At(side * (0.5 + l * 0.4 * math.cos(angle)), 1.3 + l * 0.4 * math.sin(angle), 0.56)
					* CFrame.Angles(0, -side * 0.25, side * angle),
				c.V(l, 0.34, 0.08),
				if j == 1 then GOLD else PEARL,
				if j == 1 then M.Foil else M.Marble
			)
		end
	end
	-- a star sceptre in the right hand
	if c.Room() >= 4 then
		G.held(c, "Staff", Vector3.new(1.0, 0.1, -0.32), Vector3.new(1.0, 2.62, -0.32), 0.09, GOLD, M.Foil)
		K.part(c.Model, "StaffHead", c.At(1.0, 2.66, -0.32), c.V(0.24, 0.12, 0.24), GOLD, M.Foil)
		G.diamond(c.Model, "Star1", c.At(1.0, 2.94, -0.32), 0.42 * c.S, 0.08 * c.S, c.Glow, NEON)
		K.part(c.Model, "Star2", c.At(1.0, 2.94, -0.32), c.V(0.42, 0.42, 0.08), c.Glow, NEON)
	end
	-- stars floating round it (they stay with the body)
	for i = 1, 3 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 1) / 3 * 2 * PI + 0.9
		G.diamond(
			c.Model,
			"AuraStar" .. i,
			c.At(math.cos(a) * 1.3, 1.1 + i * 0.3, math.sin(a) * 1.05),
			0.22 * c.S,
			0.06 * c.S,
			rgb(255, 236, 150),
			NEON
		)
	end
	shoulderGems(c, c.Glow)
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
