--[[
	SKY (the SKY EGG's golems, a proposal for the owner): the costumes of its
	three golems (GolemGearLimited explains the contract and the tools).

	  SkyPuff       Sky Sprite (Epic): a cloud for hair, big shiny eyes, a
	                little gold halo, small feathered wings, a cloud tail, a
	                star wand
	  StormArmor    Storm Sentinel (Legendary): storm-grey armour, a horned
	                storm helm with a glowing visor, thundercloud pauldrons,
	                a lightning spear, lightning running in its armour, a
	                storm cape, embers
	  AetherWings   Aether King (Mythic): pearl and gold, great angel wings
	                in two layers, a golden halo over a sky-gem crown, a
	                sky-blue royal cape, a sceptre with a sun orb, clouds at
	                its feet, embers and its own light

	The two HUGE golems (owner 2026-10-30, his Sky egg concept; GolemConfig
	Huge: Scale 3.2, HugeMaxParts; owner 2026-11-06: more lightning on both,
	clouds on the Titan too):
	  TitanArmor    Sky Titan: white and gold armour, a crowned white helm
	                with glowing ice eyes, big gold pauldrons with ice gems,
	                crystal wings of two-tone ice shards, a great golden
	                halo, a gold staff topped with an ice crystal, a chest
	                crystal, ice crystals floating round its legs, clouds on
	                its shoulders, arms, waist, feet and halo, ice lightning
	                from the halo and the staff to the ground, sparkles and
	                its own light
	  CloudStorm    Cloud Colossus: dark storm rock, a rock helm with glowing
	                blue eyes and a crown of rock spikes, huge cloud
	                shoulders, clouds wrapped round its arms, waist and feet,
	                blue lightning veins in the rock, great bolts from the
	                ring through the clouds and the fists to the ground and
	                out to the rocks floating round it, a storm ring over its
	                head with a cloud and a floating stone, storm motes and
	                its own light
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local Sky = {}

Sky.Faces = {
	SkyPuff = "Closed",
	StormArmor = "Closed",
	AetherWings = "Closed",
	TitanArmor = "Closed",
	CloudStorm = "Closed",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local GOLD = rgb(255, 200, 60)
local CLOUD = rgb(250, 252, 255)
local CLOUD_SHADE = rgb(214, 230, 248)
local SKY = rgb(110, 196, 255)
local SKY_DEEP = rgb(60, 130, 220)
local STORM = rgb(58, 66, 92)
local BLACK = rgb(40, 44, 60) -- (owner: black like the Storm Sentinel)
local BLACK_DEEP = rgb(26, 28, 40)
local STORM_CLOUD = rgb(160, 172, 205)
local STORM_DARK = rgb(34, 38, 56)
local BOLT = rgb(255, 230, 90)
-- the HUGE golems (the owner's concept palette)
local PEARL = rgb(236, 244, 255)
local TITAN_GOLD = rgb(255, 190, 55)
local HALO_GOLD = rgb(255, 214, 110)
local ICE = rgb(90, 215, 255)
local ICE_PALE = rgb(196, 238, 255)
local ICE_DEEP = rgb(70, 160, 240)
local STORM_ROCK = rgb(35, 48, 72)
local STORM_ROCK_DARK = rgb(20, 29, 48)
local STORM_BLUE = rgb(0, 125, 255)
local LIGHTNING = rgb(110, 205, 255)
local BOLT_HOT = rgb(226, 248, 255) -- the great bolts' white-hot blue
local THUNDERHEAD = rgb(238, 245, 255)
local THUNDERHEAD_SHADE = rgb(196, 214, 240)
local ICE_SKY = rgb(150, 222, 255)
local ROCK_MID = rgb(62, 82, 120)

local T: Tools = nil :: any
local K: Kit = nil :: any

local function diamond(parent: Instance, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?): Part
	return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, w, thick), color, material)
end

-- a puffy cloud of `n` balls round `center` (unscaled), `r` across
local function cloud(c: Ctx, name: string, center: Vector3, r: number, n: number, color: Color3)
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local a = (i - 1) / n * 2 * PI
		local d = if i == 1 then 0 else r * 0.45
		local size = r * (if i == 1 then 0.9 else 0.62)
		T.ellipsoid(
			c.Model,
			name .. i,
			c.At(center.X + math.cos(a) * d, center.Y + (if i % 2 == 0 then 0.08 else -0.04), center.Z + math.sin(a) * d * 0.7),
			c.V(size, size * 0.8, size * 0.85),
			if i % 3 == 0 then CLOUD_SHADE else color,
			M.SmoothPlastic
		)
	end
end

-- a wing of `n` smooth feathers on `side`, fanning up and out behind the shoulders
local function wing(c: Ctx, side: number, n: number, length: number, y: number, color: Color3, tip: Color3, layer: number)
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local l = length * (1 - (i - 1) * 0.16)
		local angle = (0.25 + (i - 1) * 0.38)
		local cf = c.At(side * (0.55 + l * 0.42 * math.cos(angle)), y + l * 0.42 * math.sin(angle), 0.55 + layer * 0.08)
			* CFrame.Angles(0, -side * 0.25, side * angle)
		T.ellipsoid(
			c.Model,
			`Feather{side > 0 and 2 or 1}_{layer}_{i}`,
			cf,
			c.V(l, 0.42, 0.1),
			if i == 1 then tip else color,
			M.SmoothPlastic
		)
	end
end

-- a ring of `n` segments (a halo) at height y, radius r, tilted
local function halo(c: Ctx, name: string, y: number, r: number, n: number, width: number, color: Color3, z: number?)
	local frame = c.At(0, y, z or 0.1) * CFrame.Angles(0.2, 0, 0)
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
		local p0 = (frame * CFrame.new(math.cos(a0) * r * c.S, 0, math.sin(a0) * r * c.S)).Position
		local p1 = (frame * CFrame.new(math.cos(a1) * r * c.S, 0, math.sin(a1) * r * c.S)).Position
		T.seg(c.Model, name .. i, p0, p1, width * c.S, width * c.S, color, NEON)
	end
end

-- a cape from the shoulders, flared, with a hem
local function cape(c: Ctx, color: Color3, hem: Color3, flare: number)
	if c.Room() < 1 then
		return
	end
	local yt, yb, zt, zb = 1.42, 0.12, 0.47, 0.85
	local tilt = math.atan((zb - zt) / (yt - yb))
	K.part(
		c.Model,
		"Cape",
		c.At(0, (yt + yb) / 2, (zt + zb) / 2) * CFrame.Angles(tilt, 0, 0),
		c.V(1.3, (yt - yb) * 1.04, 0.06),
		color,
		M.Fabric
	)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		T.tri(
			c.Model,
			"CapeFlare" .. i,
			T.P(c, side * 0.63, yt - 0.05, zt + 0.01),
			T.P(c, side * 0.63, yb, zb),
			T.P(c, side * (0.65 + flare), yb, zb + 0.04),
			0.06 * c.S,
			color,
			M.Fabric,
			1
		)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "CapeHem", c.At(0, yb + 0.05, zb + 0.01) * CFrame.Angles(tilt, 0, 0), c.V(1.3 + 2 * flare, 0.12, 0.09), hem, M.Foil)
	end
end

-- the knight's look every Sky golem shares (owner: "make them like the
-- Storm Sentinel, it is mega cool"): a closed helm, a glowing visor slit and a
-- brow ridge over it
local function knightHelm(c: Ctx, helm: Color3, brow: Color3, visor: Color3, material: Enum.Material)
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), helm, material)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.2, 0.03), visor, NEON)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.74) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.18, 0.26), brow, material)
end

---------------------------------------------------------------- the costumes

local function skySprite(c: Ctx): number
	-- a wind knight: a white helm with a sky-blue visor, wing crests, cloud pauldrons
	knightHelm(c, BLACK, BLACK_DEEP, SKY, M.Metal)
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		-- little wing crests on the helm's sides, white with sky-blue tips
		T.ellipsoid(
			c.Model,
			`Crest{i}_1`,
			c.At(side * 0.88, 2.55, 0.15) * CFrame.Angles(0, 0, side * 0.9),
			c.V(0.9, 0.3, 0.1),
			CLOUD,
			M.SmoothPlastic
		)
		T.ellipsoid(c.Model, `Crest{i}_2`, c.At(side * 1.05, 2.8, 0.2) * CFrame.Angles(0, 0, side * 1.25), c.V(0.6, 0.2, 0.08), SKY, NEON)
	end
	T.redress(c, "Boulder", c.At(-0.82, 1.5, 0.02), c.V(0.6, 0.3, 0.66), BLACK_DEEP, M.Metal)
	T.redress(c, "Crystal", c.At(0.82, 1.5, 0.02), c.V(0.6, 0.3, 0.66), BLACK_DEEP, M.Metal)
	for _, side in { -1, 1 } do
		cloud(c, `Pauldron{side > 0 and 2 or 1}_`, Vector3.new(side * 0.9, 1.82, 0.0), 0.95, 3, STORM_CLOUD)
	end
	-- wind runes running in the armour, a sky core
	for i, k in { { -0.25, 1.15, 0.5 }, { 0.15, 0.95, -0.5 }, { -0.1, 0.75, 0.5 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Rune" .. i, c.At(k[1], k[2], -0.44) * CFrame.Angles(0, 0, k[3]), c.V(0.07, 0.26, 0.03), SKY, NEON)
	end
	T.redress(c, "Core", c.At(0, 1.2, -0.45) * CFrame.Angles(0, 0, PI / 4), c.V(0.28, 0.28, 0.05), SKY, NEON)
	-- a wind lance with a star head
	if c.Room() >= 3 then
		T.seg(c.Model, "Lance", T.P(c, 1.0, 0.0, -0.25), T.P(c, 1.0, 2.6, -0.25), 0.1 * c.S, 0.1 * c.S, BLACK_DEEP, M.Metal)
		local star = c.At(1.0, 2.8, -0.25)
		diamond(c.Model, "LanceStar1", star, 0.42 * c.S, 0.08 * c.S, rgb(255, 240, 140), NEON)
		K.part(c.Model, "LanceStar2", star, c.V(0.42, 0.42, 0.08), rgb(255, 240, 140), NEON)
	end
	-- small feathered wings, a sky cape, a little halo
	for _, side in { -1, 1 } do
		wing(c, side, 3, 1.2, 1.25, BLACK, SKY, 1)
	end
	cape(c, rgb(36, 56, 100), SKY, 0.45)
	halo(c, "Halo", 3.25, 0.45, 8, 0.07, GOLD)
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, BLACK_DEEP, M.Metal)
	end
	return 3.4
end

local function stormWarden(c: Ctx): number
	-- storm armour: the helm with horns and a glowing visor
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), STORM, M.Metal)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.2, 0.03), BOLT, NEON)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.74) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.18, 0.26), STORM_DARK, M.Metal)
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.seg(
			c.Model,
			`Horn{i}_1`,
			T.P(c, side * 0.7, 2.55, 0.05),
			T.P(c, side * 1.0, 2.95, 0.15),
			0.22 * c.S,
			0.22 * c.S,
			STORM_DARK,
			M.Metal
		)
		T.seg(c.Model, `Horn{i}_2`, T.P(c, side * 1.0, 2.95, 0.15), T.P(c, side * 1.05, 3.45, 0.35), 0.14 * c.S, 0.14 * c.S, BOLT, NEON)
	end
	-- thundercloud pauldrons with a bolt in each
	T.redress(c, "Boulder", c.At(-0.82, 1.5, 0.02), c.V(0.6, 0.3, 0.66), STORM_DARK, M.Metal)
	T.redress(c, "Crystal", c.At(0.82, 1.5, 0.02), c.V(0.6, 0.3, 0.66), STORM_DARK, M.Metal)
	for _, side in { -1, 1 } do
		cloud(c, `Thunder{side > 0 and 2 or 1}_`, Vector3.new(side * 0.9, 1.82, 0.0), 0.95, 3, rgb(160, 172, 205))
	end
	-- lightning running in the armour
	for i, k in { { -0.25, 1.15, 0.5 }, { 0.15, 0.95, -0.5 }, { -0.1, 0.75, 0.5 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Bolt" .. i, c.At(k[1], k[2], -0.44) * CFrame.Angles(0, 0, k[3]), c.V(0.07, 0.26, 0.03), BOLT, NEON)
	end
	T.redress(c, "Core", c.At(0, 1.2, -0.45) * CFrame.Angles(0, 0, PI / 4), c.V(0.28, 0.28, 0.05), BOLT, NEON)
	-- the lightning spear in the right fist: a shaft, a zigzag bolt head
	if c.Room() >= 4 then
		T.seg(c.Model, "Spear", T.P(c, 1.0, 0.0, -0.25), T.P(c, 1.0, 2.6, -0.25), 0.1 * c.S, 0.1 * c.S, STORM_DARK, M.Metal)
		local zig =
			{ Vector3.new(1.0, 2.55, -0.25), Vector3.new(1.18, 2.85, -0.25), Vector3.new(0.92, 3.05, -0.25), Vector3.new(1.08, 3.4, -0.25) }
		for i = 1, #zig - 1 do
			T.seg(
				c.Model,
				"SpearBolt" .. i,
				T.P(c, zig[i].X, zig[i].Y, zig[i].Z),
				T.P(c, zig[i + 1].X, zig[i + 1].Y, zig[i + 1].Z),
				0.12 * c.S,
				0.06 * c.S,
				BOLT,
				NEON
			)
		end
	end
	-- a storm cape
	cape(c, rgb(46, 56, 96), BOLT, 0.5)
	-- storm fists
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, STORM_DARK, M.Metal)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, BOLT, 4)
	end
	return 3.5
end

local function aetherKing(c: Ctx): number
	-- the sky king: a pearl helm with a sky visor under a gold crown and halo
	knightHelm(c, BLACK, GOLD, SKY, M.Metal)
	T.redress(c, "Boulder", c.At(-0.82, 1.5, 0.02), c.V(0.66, 0.3, 0.72), GOLD, M.Foil)
	T.redress(c, "Crystal", c.At(0.82, 1.5, 0.02), c.V(0.66, 0.3, 0.72), GOLD, M.Foil)
	-- golden wing crests on the helm
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.ellipsoid(
			c.Model,
			`Crest{i}_1`,
			c.At(side * 0.92, 2.6, 0.15) * CFrame.Angles(0, 0, side * 0.85),
			c.V(1.0, 0.32, 0.1),
			GOLD,
			M.Foil
		)
		T.ellipsoid(c.Model, `Crest{i}_2`, c.At(side * 1.12, 2.9, 0.2) * CFrame.Angles(0, 0, side * 1.2), c.V(0.7, 0.22, 0.08), SKY, NEON)
	end
	-- great angel wings in two layers
	for _, side in { -1, 1 } do
		wing(c, side, 4, 2.0, 1.15, BLACK, GOLD, 1)
	end
	for _, side in { -1, 1 } do
		wing(c, side, 3, 1.5, 1.05, BLACK_DEEP, SKY, 2)
	end
	-- the sky-gem crown on the helm and a golden halo over it
	K.upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.3 * c.S, 1.3 * c.S, GOLD, M.Foil)
	for i = 1, 5 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.62
		local h = if i == 3 then 0.5 else 0.36
		diamond(
			c.Model,
			"CrownPoint" .. i,
			c.At(math.sin(a) * 0.62, 3.06, -math.cos(a) * 0.62) * CFrame.Angles(0, -a, 0),
			h * c.S,
			0.08 * c.S,
			GOLD,
			M.Foil
		)
	end
	for i, a in { -0.62, 0, 0.62 } do
		if c.Room() < 1 then
			break
		end
		diamond(
			c.Model,
			"CrownGem" .. i,
			c.At(math.sin(a) * 0.66, 2.86, -math.cos(a) * 0.66) * CFrame.Angles(0, -a, 0),
			0.16 * c.S,
			0.05 * c.S,
			if i == 2 then SKY else rgb(180, 120, 255),
			NEON
		)
	end
	halo(c, "Halo", 3.7, 0.6, 10, 0.09, GOLD)
	-- sky light running in the gold armour
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.06, -0.435), c.V(0.96, 0.66, 0.04), GOLD, M.Foil)
	end
	for i, k in { { -0.25, 1.2, 0.5 }, { 0.25, 0.95, -0.5 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Rune" .. i, c.At(k[1], k[2], -0.46) * CFrame.Angles(0, 0, k[3]), c.V(0.07, 0.26, 0.03), SKY, NEON)
	end
	T.redress(c, "Core", c.At(0, 1.08, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.32, 0.32, 0.04), SKY, NEON)
	-- a sky-blue royal cape, a sceptre with a sun orb, clouds at its feet
	cape(c, SKY_DEEP, GOLD, 0.6)
	if c.Room() >= 3 then
		T.seg(c.Model, "Staff", T.P(c, 1.08, 0.05, -0.42), T.P(c, 1.08, 2.3, -0.42), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		diamond(c.Model, "StaffHead", c.At(1.08, 2.4, -0.42), 0.4 * c.S, 0.12 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Orb", c.At(1.08, 2.66, -0.42), c.V(0.38, 0.38, 0.38), rgb(255, 240, 160), NEON, BALL)
	end
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, GOLD, M.Foil)
	end
	cloud(c, "Floor", Vector3.new(0, 0.32, 0.05), 1.5, 5, CLOUD) -- (the clouds' feet on the base)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, GOLD, 5)
		T.light(body, SKY, 8, 1.2)
	end
	return 4.0
end

---------------------------------------------------------------- the HUGE golems

-- an ice crystal: an upright prism turned to show its edge (w across, h tall, unscaled)
local function gem(c: Ctx, name: string, cf: CFrame, w: number, h: number, color: Color3, material: Enum.Material): Part
	return K.part(c.Model, name, cf * CFrame.Angles(0, PI / 4, 0), c.V(w, h, w), color, material)
end

-- a cube standing on a corner (a floating gem or rock chunk), `w` across (unscaled)
local function chunk(c: Ctx, name: string, cf: CFrame, w: Vector3, color: Color3, material: Enum.Material): Part
	return K.part(c.Model, name, cf * CFrame.Angles(0.62, PI / 4, 0), c.V(w.X, w.Y, w.Z), color, material)
end

-- a right-angled triangle from one wedge: the right angle at `a`, its legs to `b` and `p` (world points)
local function rightTri(
	c: Ctx,
	name: string,
	a: Vector3,
	b: Vector3,
	p: Vector3,
	thick: number,
	color: Color3,
	material: Enum.Material
): BasePart
	local up, along = b - a, p - a
	local y, z = up.Unit, -along.Unit
	return K.wedge(
		c.Model,
		name,
		CFrame.fromMatrix(a + up / 2 + along / 2, y:Cross(z), y, z),
		Vector3.new(thick, up.Magnitude, along.Magnitude),
		color,
		material
	)
end

-- how a shard looks: its light half (Clear: see-through), an optional second
-- half (Deep, DeepShare of the light half's width: a narrow Neon one is a
-- glowing edge), its thickness (unscaled)
type ShardLook = {
	Light: Color3,
	Material: Enum.Material,
	Clear: number?,
	Deep: Color3?,
	DeepMaterial: Enum.Material?,
	DeepShare: number?,
	Thick: number?,
}

--[[
	A crystal shard from `root` (unscaled) along `angle` in the golem's
	back plane (0 = straight out on `side`, pi / 2 = up), swept back by
	`sweep` per unit of length: two right-angled halves of one wedge each
	(see ShardLook).
]]
local function shard(
	c: Ctx,
	name: string,
	root: Vector3,
	side: number,
	angle: number,
	length: number,
	width: number,
	sweep: number,
	look: ShardLook
)
	local deep = look.Deep
	if c.Room() < (if deep then 2 else 1) then
		return
	end
	-- (perp is square to the shard's axis: each half is right-angled at the root)
	local dir = Vector3.new(side * math.cos(angle), math.sin(angle), sweep) * length
	local perp = Vector3.new(-side * math.sin(angle), math.cos(angle), 0) * (width / 2)
	local a = T.P(c, root.X, root.Y, root.Z)
	local tip = T.P(c, root.X + dir.X, root.Y + dir.Y, root.Z + dir.Z)
	local thick = (look.Thick or 0.07) * c.S
	local up = T.P(c, root.X + perp.X, root.Y + perp.Y, root.Z + perp.Z)
	local light = rightTri(c, name .. "L", a, up, tip, thick, look.Light, look.Material)
	light.Transparency = look.Clear or 0
	if deep then
		local k = look.DeepShare or 1
		local down = T.P(c, root.X - perp.X * k, root.Y - perp.Y * k, root.Z - perp.Z * k)
		rightTri(c, name .. "D", a, down, tip, thick, deep, look.DeepMaterial or look.Material)
	end
end

-- puffs of cloud { x, y, z, size } (unscaled), every third one a shade darker
local function puffs(c: Ctx, name: string, list: { { number } }, color: Color3, shade: Color3)
	for i, k in list do
		if c.Room() < 1 then
			return
		end
		T.ellipsoid(
			c.Model,
			name .. i,
			c.At(k[1], k[2], k[3]),
			c.V(k[4], k[4] * 0.82, k[4] * 0.9),
			if i % 3 == 0 then shade else color,
			M.SmoothPlastic
		)
	end
end

-- a zigzag of glowing segments through the points { x, y } at depth z (unscaled)
local function zigzag(c: Ctx, name: string, points: { { number } }, z: number, width: number, color: Color3)
	for i = 1, #points - 1 do
		if c.Room() < 1 then
			return
		end
		local a, b = points[i], points[i + 1]
		T.seg(c.Model, name .. i, T.P(c, a[1], a[2], z), T.P(c, b[1], b[2], z), width * c.S, 0.03 * c.S, color, NEON)
	end
end

-- a bolt of glowing segments through the points { x, y, z } (unscaled), square so it reads from every side
local function bolt(c: Ctx, name: string, points: { { number } }, width: number, color: Color3)
	for i = 1, #points - 1 do
		if c.Room() < 1 then
			return
		end
		local a, b = points[i], points[i + 1]
		T.seg(c.Model, name .. i, T.P(c, a[1], a[2], a[3]), T.P(c, b[1], b[2], b[3]), width * c.S, width * c.S, color, NEON)
	end
end

-- a plate (unscaled box) when there is room
local function plate(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part?
	if c.Room() < 1 then
		return nil
	end
	return K.part(c.Model, name, cf, c.V(size.X, size.Y, size.Z), color, material)
end

-- the Sky Titan's crystal wings: ice shards, every other one with a glowing edge (a long layer, a short one in front)
local WING_EDGE: ShardLook = { Light = ICE_PALE, Material = M.SmoothPlastic, Deep = ICE, DeepMaterial = NEON, DeepShare = 0.3 }
local WING_FACET: ShardLook = { Light = ICE_SKY, Material = M.SmoothPlastic, Deep = ICE_DEEP, DeepShare = 0.8 }
local TITAN_WING = {
	{ 0.12, 1.5, 0.7 },
	{ 0.36, 2.05, 0.8 },
	{ 0.6, 2.5, 0.88 },
	{ 0.84, 2.8, 0.92 },
	{ 1.06, 2.75, 0.88 },
	{ 1.27, 2.45, 0.8 },
	{ 1.48, 1.95, 0.7 },
}
-- the Cloud Colossus's crown of rock shards
local ROCK_SPIKE: ShardLook = { Light = ROCK_MID, Material = M.Slate, Deep = STORM_ROCK_DARK, Thick = 0.3 }
local TITAN_WING_INNER = { { 0.48, 1.4, 0.56 }, { 0.78, 1.75, 0.6 }, { 1.04, 1.75, 0.58 }, { 1.26, 1.4, 0.5 } }

local function skyTitan(c: Ctx): number
	-- white and gold armour (no part cost): a pearl marble body (still stone: a golem),
	-- gold gauntlets and shoulder plates, the big chest crystal
	for _, name in { "Body", "Head", "Arm1", "Arm2", "Leg1", "Leg2" } do
		T.recolor(c, name, PEARL, M.Marble)
	end
	for i, side in { -1, 1 } do
		T.redress(
			c,
			"Fist" .. i,
			c.At(side * 0.88, 0.68, -0.04) * CFrame.Angles(0.3, side * 0.45, side * 0.2),
			c.V(0.56, 0.5, 0.54),
			TITAN_GOLD,
			M.Foil
		)
	end
	T.redress(c, "Boulder", c.At(-0.84, 1.5, 0.02), c.V(0.72, 0.3, 0.78), TITAN_GOLD, M.Foil)
	T.redress(c, "Crystal", c.At(0.84, 1.5, 0.02), c.V(0.72, 0.3, 0.78), TITAN_GOLD, M.Foil)
	T.redress(c, "Core", c.At(0, 1.08, -0.56) * CFrame.Angles(0, 0, PI / 4), c.V(0.42, 0.42, 0.08), ICE, NEON)
	-- the crowned helm: pearl, a gold face-guard (brow, nose guard, cheeks) round the glowing visor
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), PEARL, M.Marble)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.26, 0.03), ICE_DEEP, NEON)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.74) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.18, 0.26), TITAN_GOLD, M.Foil)
	-- (a knight's T: the nose guard splits the visor into two glowing eye slits)
	K.part(c.Model, "HelmGuard", c.At(0, 1.86, -0.74), c.V(0.16, 0.7, 0.07), TITAN_GOLD, M.Foil)
	for i, side in { -1, 1 } do
		K.part(c.Model, "HelmCheek" .. i, c.At(side * 0.68, 1.9, -0.73), c.V(0.26, 0.66, 0.07), TITAN_GOLD, M.Foil)
	end
	-- a tall gold crown with ice gems
	K.upright(c.Model, "CrownBand", c.At(0, 2.9, 0), 0.3 * c.S, 1.4 * c.S, TITAN_GOLD, M.Foil)
	for i = 1, 7 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 4) * 0.42
		local h = ({ 0.38, 0.44, 0.52, 0.68, 0.52, 0.44, 0.38 })[i]
		diamond(
			c.Model,
			"CrownPoint" .. i,
			c.At(math.sin(a) * 0.68, 3.08, -math.cos(a) * 0.68) * CFrame.Angles(0, -a, 0),
			h * c.S,
			0.08 * c.S,
			TITAN_GOLD,
			M.Foil
		)
	end
	for i, a in { -0.84, 0, 0.84 } do
		if c.Room() < 1 then
			break
		end
		diamond(
			c.Model,
			"CrownGem" .. i,
			c.At(math.sin(a) * 0.72, 2.9, -math.cos(a) * 0.72) * CFrame.Angles(0, -a, 0),
			(if i == 2 then 0.2 else 0.15) * c.S,
			0.05 * c.S,
			ICE_DEEP,
			NEON
		)
	end
	-- gold wing crests on the helm's sides, tipped with ice
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.ellipsoid(
			c.Model,
			`Crest{i}_1`,
			c.At(side * 0.92, 2.6, 0.15) * CFrame.Angles(0, 0, side * 0.85),
			c.V(1.0, 0.3, 0.1),
			TITAN_GOLD,
			M.Foil
		)
		T.ellipsoid(c.Model, `Crest{i}_2`, c.At(side * 1.12, 2.9, 0.2) * CFrame.Angles(0, 0, side * 1.2), c.V(0.7, 0.22, 0.08), ICE, NEON)
	end
	-- the great golden halo behind the crown
	halo(c, "Halo", 3.88, 0.98, 16, 0.1, HALO_GOLD, 0.25)
	-- big layered pauldrons: a gold dome over a gold and a pearl tier, an ice inset and a crystal on top
	for i, side in { -1, 1 } do
		if c.Room() < 5 then
			break
		end
		T.ellipsoid(
			c.Model,
			`Pauldron{i}_1`,
			c.At(side * 1.06, 1.74, 0.02) * CFrame.Angles(0, 0, side * -0.25),
			c.V(1.22, 0.8, 1.16),
			TITAN_GOLD,
			M.Foil
		)
		K.part(
			c.Model,
			`Pauldron{i}_2`,
			c.At(side * 1.18, 1.46, 0.02) * CFrame.Angles(0, 0, side * -0.36),
			c.V(1.0, 0.12, 1.1),
			TITAN_GOLD,
			M.Foil
		)
		K.part(
			c.Model,
			`Pauldron{i}_3`,
			c.At(side * 1.28, 1.28, 0.02) * CFrame.Angles(0, 0, side * -0.46),
			c.V(0.8, 0.1, 1.0),
			PEARL,
			M.Marble
		)
		diamond(c.Model, `Pauldron{i}_4`, c.At(side * 1.06, 1.76, -0.58), 0.28 * c.S, 0.06 * c.S, ICE, NEON)
		gem(c, `Pauldron{i}_5`, c.At(side * 1.18, 2.2, 0.05) * CFrame.Angles(0, 0, side * -0.3), 0.2, 0.5, ICE_SKY, M.SmoothPlastic)
	end
	-- the chest plate, gold on its edges, the ice crystal set in a gold frame; a back plate
	-- (named Body*: a running golem's limbs leave them on the torso, GolemGait.BodyNames)
	plate(c, "BodyPlate", c.At(0, 1.03, -0.47), Vector3.new(1.38, 0.68, 0.1), PEARL, M.Marble)
	plate(c, "BodyTrim1", c.At(0, 1.33, -0.48), Vector3.new(1.42, 0.08, 0.13), TITAN_GOLD, M.Foil)
	plate(c, "BodyTrim2", c.At(0, 0.7, -0.48), Vector3.new(1.42, 0.08, 0.13), TITAN_GOLD, M.Foil)
	for i, side in { -1, 1 } do
		plate(c, "BodyTrim" .. (i + 2), c.At(side * 0.7, 1.03, -0.48), Vector3.new(0.08, 0.68, 0.13), TITAN_GOLD, M.Foil)
	end
	if c.Room() >= 1 then
		diamond(c.Model, "CoreFrame", c.At(0, 1.08, -0.535), 0.62 * c.S, 0.04 * c.S, TITAN_GOLD, M.Foil)
	end
	plate(c, "BodyBack", c.At(0, 1.0, 0.47), Vector3.new(1.3, 0.72, 0.08), PEARL, M.Marble)
	-- crystal wings: long glass shards with glowing edges fanning up and out behind the shoulders
	for i, side in { -1, 1 } do
		for k, w in TITAN_WING do
			local root = Vector3.new(side * (0.5 + k * 0.05), 1.52 + k * 0.05, 0.56 + k * 0.03)
			shard(c, `Wing{i}_{k}`, root, side, w[1], w[2], w[3], 0.15, if k % 2 == 1 then WING_EDGE else WING_FACET)
		end
	end
	-- the tall gold staff in the right fist: rings on its shaft, a crescent holding a big ice crystal
	if c.Room() >= 10 then
		local x, z = 1.24, -0.54
		T.seg(c.Model, "Staff", T.P(c, x, 0.0, z), T.P(c, x, 3.46, z), 0.13 * c.S, 0.13 * c.S, TITAN_GOLD, M.Foil)
		for i, y in { 1.35, 2.6 } do
			K.upright(c.Model, "StaffRing" .. i, c.At(x, y, z), 0.08 * c.S, 0.22 * c.S, TITAN_GOLD, M.Foil)
		end
		K.upright(c.Model, "StaffCap", c.At(x, 3.46, z), 0.14 * c.S, 0.3 * c.S, TITAN_GOLD, M.Foil)
		for i, side in { -1, 1 } do
			local tip = T.P(c, x + side * 0.32, 3.84, z)
			T.seg(c.Model, `StaffProng{i}_1`, T.P(c, x, 3.46, z), tip, 0.1 * c.S, 0.1 * c.S, TITAN_GOLD, M.Foil)
			T.seg(c.Model, `StaffProng{i}_2`, tip, T.P(c, x + side * 0.2, 4.2, z), 0.08 * c.S, 0.08 * c.S, TITAN_GOLD, M.Foil)
		end
		diamond(c.Model, "StaffGem", c.At(x, 3.98, z), 0.5 * c.S, 0.26 * c.S, ICE, NEON)
		local shell = diamond(c.Model, "StaffGemShell", c.At(x, 3.98, z + 0.02), 0.7 * c.S, 0.14 * c.S, ICE_SKY, M.Glass)
		shell.Transparency = 0.4
	end
	-- a gold belt with an ice buckle, pearl tassets with gold hems
	plate(c, "Belt", c.At(0, 0.6, 0), Vector3.new(1.34, 0.16, 0.98), TITAN_GOLD, M.Foil)
	if c.Room() >= 1 then
		diamond(c.Model, "Buckle", c.At(0, 0.6, -0.5), 0.26 * c.S, 0.05 * c.S, ICE_DEEP, NEON)
	end
	for i, x in { -0.36, 0, 0.36 } do
		local tall = if x == 0 then 0.36 else 0.3
		plate(c, "Tasset" .. i, c.At(x, 0.58 - tall / 2, -0.38) * CFrame.Angles(0.12, 0, 0), Vector3.new(0.34, tall, 0.06), PEARL, M.Marble)
		plate(
			c,
			"TassetHem" .. i,
			c.At(x, 0.58 - tall, -0.4) * CFrame.Angles(0.12, 0, 0),
			Vector3.new(0.36, 0.06, 0.08),
			TITAN_GOLD,
			M.Foil
		)
	end
	-- gauntlet cuffs, gold greaves and boots
	for i, side in { -1, 1 } do
		plate(
			c,
			"Bracer" .. i,
			c.At(side * 0.82, 0.94, 0) * CFrame.Angles(0, 0, side * 0.1),
			Vector3.new(0.48, 0.16, 0.58),
			TITAN_GOLD,
			M.Foil
		)
	end
	for i, x in { -0.3, 0.3 } do
		plate(c, "Boot" .. i, c.At(x, 0.08, -0.06), Vector3.new(0.52, 0.16, 0.66), TITAN_GOLD, M.Foil)
		plate(c, "Greave" .. i, c.At(x, 0.22, -0.27), Vector3.new(0.38, 0.14, 0.05), TITAN_GOLD, M.Foil)
	end
	-- a short inner layer of wing shards in front of the long one
	for i, side in { -1, 1 } do
		for k, w in TITAN_WING_INNER do
			shard(
				c,
				`WingInner{i}_{k}`,
				Vector3.new(side * 0.62, 1.6, 0.5),
				side,
				w[1],
				w[2],
				w[3],
				0.1,
				if k % 2 == 1 then WING_FACET else WING_EDGE
			)
		end
	end
	-- ice shards floating round it
	for i, k in
		{ { -1.45, 0.55, -0.3 }, { 1.7, 0.95, 0.35 }, { -1.75, 1.3, 0.45 }, { 1.5, 0.4, -0.45 }, { -1.3, 2.5, 0.5 }, { 1.85, 2.2, 0.2 } }
	do
		if c.Room() < 1 then
			break
		end
		local glow = i % 2 == 1
		chunk(
			c,
			"CrystalBit" .. i,
			c.At(k[1], k[2], k[3]) * CFrame.Angles(0, i, 0),
			Vector3.new(0.2, 0.32, 0.2),
			if glow then ICE_DEEP else ICE_SKY,
			if glow then NEON else M.SmoothPlastic
		)
	end
	-- clouds like the Colossus's (owner 2026-11-06): behind the pauldrons and round the forearms
	-- (Pauldron*: they swing with that arm), the waist and the feet (Body*), on the halo's back
	for i, side in { -1, 1 } do
		puffs(c, `Pauldron{i}_Cloud`, {
			{ side * 1.5, 1.48, 0.12, 0.74 },
			{ side * 1.2, 1.18, 0.46, 0.66 },
			{ side * 1.66, 1.84, 0.36, 0.62 },
			{ side * 0.98, 1.92, 0.58, 0.64 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
		puffs(c, `Pauldron{i}_Wrap`, {
			{ side * 1.2, 0.94, 0.14, 0.5 },
			{ side * 0.62, 0.98, 0.26, 0.42 },
			{ side * 1.04, 1.02, -0.36, 0.42 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
	end
	puffs(c, "BodyCloud", {
		{ -0.8, 0.55, 0.05, 0.56 },
		{ 0.8, 0.55, 0.05, 0.56 },
		{ -0.42, 0.52, 0.45, 0.52 },
		{ 0.42, 0.52, 0.45, 0.52 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	puffs(c, "BodyMist", {
		{ -0.72, 0.12, -0.05, 0.58 },
		{ 0.72, 0.12, -0.05, 0.58 },
		{ -0.35, 0.1, -0.5, 0.46 },
		{ 0.35, 0.1, -0.5, 0.46 },
		{ 0, 0.12, 0.5, 0.6 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	puffs(c, "HaloCloud", {
		{ -0.72, 3.95, 0.5, 0.5 },
		{ 0.72, 3.95, 0.5, 0.5 },
		{ 0, 4.05, 0.75, 0.56 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	-- ice lightning: from the halo down both sides, round the staff, through the chest, down the
	-- arms to the ground (BodyStorm*: on the torso; Pauldron*: with that arm)
	bolt(
		c,
		"BodyStorm1_",
		{ { -0.95, 3.72, -0.05 }, { -1.32, 3.36, -0.2 }, { -1.06, 3.0, -0.3 }, { -1.46, 2.64, -0.4 }, { -1.26, 2.3, -0.5 } },
		0.07,
		BOLT_HOT
	)
	bolt(c, "BodyStorm2_", { { 0.9, 3.7, -0.05 }, { 0.72, 3.4, -0.3 }, { 0.98, 3.1, -0.42 }, { 0.82, 2.78, -0.66 } }, 0.06, ICE)
	bolt(
		c,
		"Pauldron2_StaffBolt",
		{ { 1.24, 3.72, -0.54 }, { 1.56, 3.36, -0.6 }, { 1.32, 3.0, -0.64 }, { 1.62, 2.62, -0.6 }, { 1.38, 2.26, -0.62 } },
		0.06,
		BOLT_HOT
	)
	for i, side in { -1, 1 } do
		zigzag(
			c,
			`BodyBolt{i}_`,
			{ { side * 0.62, 1.27 }, { side * 0.42, 1.12 }, { side * 0.54, 0.96 }, { side * 0.36, 0.78 } },
			-0.56,
			0.05,
			ICE
		)
		bolt(
			c,
			`Pauldron{i}_Arc`,
			{ { side * 1.62, 1.5, -0.32 }, { side * 1.42, 1.24, -0.46 }, { side * 1.56, 1.0, -0.44 }, { side * 1.24, 0.72, -0.5 } },
			0.05,
			ICE
		)
		bolt(
			c,
			`Pauldron{i}_Strike`,
			{ { side * 1.0, 0.36, -0.42 }, { side * 1.22, 0.2, -0.62 }, { side * 1.06, 0.04, -0.76 } },
			0.05,
			BOLT_HOT
		)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, ICE, 5, 0.4)
		T.light(body, ICE, 16, 1.4)
	end
	return 4.2
end

local function cloudColossus(c: Ctx): number
	-- heavy storm rock (no part cost): thick arms and legs, big rock fists, bright eyes, the lightning core
	for i, side in { -1, 1 } do
		T.redress(c, "Arm" .. i, c.At(side * 0.84, 1.1, 0) * CFrame.Angles(0, 0, side * 0.1), c.V(0.5, 0.66, 0.58), STORM_ROCK, M.Slate)
		T.redress(c, "Leg" .. i, c.At(side * 0.31, 0.25, 0.02), c.V(0.5, 0.5, 0.6), STORM_ROCK_DARK, M.Slate)
		T.redress(
			c,
			"Fist" .. i,
			c.At(side * 0.94, 0.6, -0.06) * CFrame.Angles(0.2, side * 0.3, side * 0.12),
			c.V(0.72, 0.64, 0.68),
			STORM_ROCK,
			M.Slate
		)
	end
	T.recolor(c, "Head", STORM_ROCK, M.Slate)
	for _, name in { "Eye1", "Eye2" } do
		T.recolor(c, name, LIGHTNING, NEON)
	end
	T.redress(c, "Boulder", c.At(-0.88, 1.52, 0.02), c.V(0.8, 0.36, 0.84), STORM_ROCK_DARK, M.Slate)
	T.redress(c, "Crystal", c.At(0.88, 1.52, 0.02), c.V(0.8, 0.36, 0.84), STORM_ROCK_DARK, M.Slate)
	T.redress(c, "Core", c.At(0, 1.0, -0.58) * CFrame.Angles(0, 0, PI / 4), c.V(0.4, 0.4, 0.06), LIGHTNING, NEON)
	-- a rock head: a heavy brow and jaw, the dark slit its blue eyes glow through
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), STORM_ROCK, M.Slate)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.26, 0.03), STORM_ROCK_DARK, M.Slate)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.75) * CFrame.Angles(-0.3, 0, 0), c.V(1.58, 0.22, 0.3), STORM_ROCK_DARK, M.Slate)
	K.part(c.Model, "Jaw", c.At(0, 1.64, -0.66) * CFrame.Angles(0.08, 0, 0), c.V(1.2, 0.34, 0.2), STORM_ROCK_DARK, M.Slate)
	for i, side in { -1, 1 } do
		K.part(
			c.Model,
			"Cheek" .. i,
			c.At(side * 0.64, 1.9, -0.68) * CFrame.Angles(0, side * 0.2, side * 0.1),
			c.V(0.34, 0.42, 0.16),
			ROCK_MID,
			M.Slate
		)
	end
	-- a crown of rock shards
	for i, k in { { -0.56, 0.42 }, { -0.28, 0.56 }, { 0, 0.62 }, { 0.28, 0.56 }, { 0.56, 0.42 } } do
		local side = if k[1] < 0 then -1 else 1
		local tilt = if k[1] == 0 then PI / 2 else PI / 2 - 0.3
		shard(c, "Spike" .. i, Vector3.new(k[1], 2.72, 0.1), side, tilt, k[2], 0.4, 0, ROCK_SPIKE)
	end
	-- the storm ring over the head, a cloud crown riding on it, a stone floating under the cloud
	halo(c, "StormRing", 3.9, 1.02, 14, 0.12, LIGHTNING, 0.1)
	puffs(c, "RingCloud", {
		{ 0, 4.16, 0.08, 0.68 },
		{ -0.42, 4.06, 0.15, 0.5 },
		{ 0.44, 4.08, 0.12, 0.48 },
		{ -0.16, 4.32, 0.12, 0.42 },
		{ 0.2, 4.3, 0.2, 0.4 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	if c.Room() >= 1 then
		chunk(c, "RingStone", c.At(0, 3.72, 0.08), Vector3.new(0.28, 0.28, 0.28), STORM_ROCK_DARK, M.Slate)
	end
	-- huge thunderclouds on the shoulders
	for i, side in { -1, 1 } do
		puffs(c, `Pauldron{i}_`, {
			{ side * 1.05, 1.78, 0.05, 1.15 },
			{ side * 1.5, 1.6, -0.12, 0.88 },
			{ side * 0.8, 2.08, 0.25, 0.8 },
			{ side * 1.3, 2.12, 0.3, 0.78 },
			{ side * 1.1, 1.42, -0.42, 0.74 },
			{ side * 1.6, 1.98, 0.38, 0.64 },
			{ side * 0.86, 1.6, 0.48, 0.7 },
			{ side * 1.38, 1.38, 0.38, 0.62 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
	end
	-- the body of chunky storm-rock blocks: chest, belly, flanks, back, a rock waist (named
	-- Body*: a running golem's limbs leave them on the torso, GolemGait.BodyNames)
	for i, side in { -1, 1 } do
		plate(
			c,
			"BodyPec" .. i,
			c.At(side * 0.33, 1.2, -0.47) * CFrame.Angles(0.05, side * -0.08, side * 0.06),
			Vector3.new(0.62, 0.42, 0.18),
			ROCK_MID,
			M.Slate
		)
	end
	for i, k in { { -0.24, 0.82, -0.08 }, { 0.24, 0.84, 0.1 }, { 0, 0.64, 0.04 } } do
		plate(
			c,
			"BodyAb" .. i,
			c.At(k[1], k[2], -0.46) * CFrame.Angles(0, 0, k[3]),
			Vector3.new(0.4, 0.24, 0.14),
			if i == 3 then STORM_ROCK_DARK else ROCK_MID,
			M.Slate
		)
	end
	for i, side in { -1, 1 } do
		plate(
			c,
			"BodyFlank" .. i,
			c.At(side * 0.66, 0.96, 0) * CFrame.Angles(0, 0, side * 0.08),
			Vector3.new(0.22, 0.72, 0.8),
			STORM_ROCK,
			M.Slate
		)
		plate(
			c,
			"BodyBack" .. i,
			c.At(side * 0.28, 1.06, 0.47) * CFrame.Angles(0, 0, side * -0.06),
			Vector3.new(0.56, 0.6, 0.16),
			STORM_ROCK_DARK,
			M.Slate
		)
	end
	plate(c, "BodyWaist", c.At(0, 0.52, 0), Vector3.new(1.38, 0.2, 0.94), STORM_ROCK_DARK, M.Slate)
	-- blue lightning cracking the rock: the chest, the arms, the legs, the fists, the brow
	zigzag(c, "Bolt", { { -0.52, 1.36 }, { -0.3, 1.2 }, { -0.42, 1.02 }, { -0.16, 0.86 }, { -0.24, 0.66 } }, -0.575, 0.08, BOLT_HOT)
	zigzag(c, "BoltR", { { 0.5, 1.34 }, { 0.3, 1.16 }, { 0.4, 0.96 }, { 0.18, 0.78 } }, -0.575, 0.08, BOLT_HOT)
	for i, side in { -1, 1 } do
		zigzag(c, `ArmBolt{i}_`, { { side * 0.8, 1.38 }, { side * 0.92, 1.16 }, { side * 0.78, 0.96 } }, -0.3, 0.05, LIGHTNING)
		zigzag(
			c,
			`LegBolt{i}_`,
			{ { side * 0.42, 0.48 }, { side * 0.28, 0.3 }, { side * 0.4, 0.26 }, { side * 0.24, 0.04 } },
			-0.29,
			0.05,
			LIGHTNING
		)
		if c.Room() >= 2 then
			local fist = c.At(side * 0.94, 0.6, -0.06) * CFrame.Angles(0.2, side * 0.3, side * 0.12)
			K.part(
				c.Model,
				"FistBolt" .. i,
				fist * CFrame.new(0, 0, -0.345 * c.S) * CFrame.Angles(0, 0, side * 0.7),
				c.V(0.05, 0.56, 0.03),
				LIGHTNING,
				NEON
			)
			K.part(c.Model, "Knuckle" .. i, fist * CFrame.new(0, 0.18 * c.S, -0.3 * c.S), c.V(0.6, 0.2, 0.16), STORM_ROCK_DARK, M.Slate)
		end
	end
	zigzag(c, "BrowBolt", { { 0.42, 2.66 }, { 0.26, 2.5 }, { 0.38, 2.44 }, { 0.22, 2.3 } }, -0.72, 0.05, LIGHTNING)
	zigzag(c, "BrowBoltL", { { -0.42, 2.66 }, { -0.26, 2.5 }, { -0.38, 2.44 }, { -0.22, 2.3 } }, -0.72, 0.05, LIGHTNING)
	-- big rocks orbiting it, some cracked with lightning (the low ones closer in: the
	-- follower walks no further aside than it must, GolemFit)
	local rocks = {
		{ -2.0, 2.55, 0.2, 0.56 },
		{ 1.95, 2.75, -0.1, 0.5 },
		{ -1.85, 1.1, -0.45, 0.44 },
		{ 1.85, 1.3, 0.45, 0.5 },
		{ -1.5, 0.4, 0.6, 0.38 },
		{ 1.55, 0.45, -0.6, 0.4 },
		{ -1.0, 3.45, 0.55, 0.38 },
		{ 1.1, 3.5, 0.5, 0.36 },
		{ -1.55, 3.0, -0.6, 0.3 },
		{ 1.6, 3.1, 0.7, 0.3 },
	}
	for i, k in rocks do
		if c.Room() < 1 then
			break
		end
		local cf = c.At(k[1], k[2], k[3]) * CFrame.Angles(0, i * 0.9, i * 0.35)
		chunk(
			c,
			"BoulderRock" .. i,
			cf,
			Vector3.new(k[4], k[4] * 0.85, k[4] * 0.9),
			if i % 3 == 0 then ROCK_MID else STORM_ROCK_DARK,
			M.Slate
		)
		if i <= 5 and c.Room() >= 1 then
			K.part(
				c.Model,
				`BoulderRock{i}Vein`,
				cf * CFrame.Angles(0.62, PI / 4, 0.5),
				c.V(k[4] * 1.04, 0.05, k[4] * 0.94),
				LIGHTNING,
				NEON
			)
		end
	end
	-- clouds wrapped round the forearms (named Pauldron*: they swing with that arm), the waist
	-- and the feet (Body*: they stay on the torso)
	for i, side in { -1, 1 } do
		puffs(c, `Pauldron{i}_Wrap`, {
			{ side * 0.62, 0.98, -0.26, 0.54 },
			{ side * 1.16, 0.96, -0.12, 0.54 },
			{ side * 0.98, 1.04, 0.34, 0.5 },
			{ side * 0.6, 1.02, 0.28, 0.46 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
	end
	puffs(c, "BodyCloud", {
		{ -0.8, 0.6, 0.0, 0.62 },
		{ 0.8, 0.6, 0.0, 0.62 },
		{ -0.4, 0.58, 0.46, 0.56 },
		{ 0.42, 0.58, 0.46, 0.56 },
		{ -0.62, 0.54, -0.38, 0.46 },
		{ 0.64, 0.54, -0.38, 0.46 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	puffs(c, "BodyMist", {
		{ -0.7, 0.14, 0.1, 0.54 },
		{ 0.7, 0.14, 0.1, 0.54 },
		{ 0, 0.12, 0.48, 0.58 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	-- the storm (owner 2026-11-06: more lightning): great forked bolts from the ring to the cloud
	-- shoulders (BodyStorm*, BodyFork*: on the torso), through the clouds, on to the fists and from
	-- the fists to the ground (Pauldron*: with that arm), arcs out to the rocks (Boulder*: on the torso)
	for i, side in { -1, 1 } do
		bolt(
			c,
			`BodyStorm{i}_`,
			{
				{ side * 0.95, 3.8, -0.1 },
				{ side * 1.32, 3.42, -0.28 },
				{ side * 1.06, 3.04, -0.38 },
				{ side * 1.46, 2.64, -0.48 },
				{ side * 1.24, 2.28, -0.62 },
			},
			0.08,
			BOLT_HOT
		)
		bolt(
			c,
			`BodyFork{i}_`,
			{ { side * 1.06, 3.04, -0.38 }, { side * 0.86, 2.86, -0.62 }, { side * 0.96, 2.62, -0.74 } },
			0.05,
			LIGHTNING
		)
		bolt(
			c,
			`Pauldron{i}_CloudBolt`,
			{ { side * 0.92, 2.1, -0.46 }, { side * 1.2, 1.92, -0.66 }, { side * 1.04, 1.72, -0.76 }, { side * 1.36, 1.5, -0.86 } },
			0.06,
			BOLT_HOT
		)
		bolt(
			c,
			`Pauldron{i}_Arc`,
			{ { side * 1.74, 1.68, -0.38 }, { side * 1.5, 1.34, -0.62 }, { side * 1.68, 1.04, -0.58 }, { side * 1.3, 0.72, -0.6 } },
			0.06,
			LIGHTNING
		)
		bolt(
			c,
			`Pauldron{i}_Strike`,
			{ { side * 1.02, 0.34, -0.46 }, { side * 1.26, 0.2, -0.66 }, { side * 1.08, 0.04, -0.8 } },
			0.06,
			BOLT_HOT
		)
	end
	for i, arc in
		{
			{ { -1.85, 2.35, 0.2 }, { -1.72, 2.2, 0.02 }, { -1.62, 1.98, 0.1 } },
			{ { 1.8, 2.55, -0.1 }, { 1.92, 2.3, 0.06 }, { 1.66, 2.02, 0.1 } },
			{ { -1.78, 1.26, -0.42 }, { -1.86, 1.44, -0.3 }, { -1.6, 1.52, -0.2 } },
			{ { 1.78, 1.46, 0.4 }, { 1.92, 1.62, 0.28 }, { 1.62, 1.72, 0.1 } },
		}
	do
		bolt(c, `BoulderArc{i}_`, arc, 0.05, LIGHTNING)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, LIGHTNING, 6, 0.4)
		T.light(body, STORM_BLUE, 16, 1.5)
	end
	return 4.4
end

function Sky.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		SkyPuff = skySprite,
		StormArmor = stormWarden,
		AetherWings = aetherKing,
		TitanArmor = skyTitan,
		CloudStorm = cloudColossus,
	}
end

return Sky
