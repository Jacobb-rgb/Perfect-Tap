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
	Huge: Scale 2.2, HugeMaxParts):
	  TitanArmor    Sky Titan: white and gold armour, a crowned white helm
	                with glowing ice eyes, big gold pauldrons with ice gems,
	                crystal wings of two-tone ice shards, a great golden
	                halo, a gold staff topped with an ice crystal, a chest
	                crystal, ice crystals floating round its legs, sparkles
	                and its own light
	  CloudStorm    Cloud Colossus: dark storm rock, a rock helm with glowing
	                blue eyes and a crown of rock spikes, huge cloud
	                shoulders, clouds wrapped round its arms, waist and feet,
	                blue lightning veins in the rock, rocks floating round
	                it, a storm ring over its head with a cloud and a
	                floating stone, storm motes and its own light
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
local PEARL_SHADE = rgb(204, 218, 238)
local TITAN_GOLD = rgb(255, 190, 55)
local HALO_GOLD = rgb(255, 214, 110)
local ICE = rgb(90, 215, 255)
local ICE_PALE = rgb(196, 238, 255)
local ICE_DEEP = rgb(70, 160, 240)
local STORM_ROCK = rgb(35, 48, 72)
local STORM_ROCK_DARK = rgb(20, 29, 48)
local STORM_BLUE = rgb(0, 125, 255)
local LIGHTNING = rgb(110, 205, 255)
local THUNDERHEAD = rgb(238, 245, 255)
local THUNDERHEAD_SHADE = rgb(196, 214, 240)
local VISOR_DARK = rgb(24, 34, 62)

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

-- a right-angled triangle from one wedge: the right angle at `a`, its legs to `b` and `p` (world points)
local function rightTri(c: Ctx, name: string, a: Vector3, b: Vector3, p: Vector3, thick: number, color: Color3, material: Enum.Material)
	local up, along = b - a, p - a
	local y, z = up.Unit, -along.Unit
	K.wedge(
		c.Model,
		name,
		CFrame.fromMatrix(a + up / 2 + along / 2, y:Cross(z), y, z),
		Vector3.new(thick, up.Magnitude, along.Magnitude),
		color,
		material
	)
end

--[[
	A crystal shard from `root` (unscaled) along `angle` in the golem's
	back plane (0 = straight out on `side`, pi / 2 = up), swept back by
	`sweep` per unit of length: two right-angled halves (one wedge each), a
	light facet and a deep one (`deep` nil: the light half alone),
	`thickness` thick (unscaled, default 0.07).
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
	light: Color3,
	deep: Color3?,
	material: Enum.Material,
	thickness: number?
)
	if c.Room() < (if deep then 2 else 1) then
		return
	end
	-- (perp is square to the shard's axis: each half is right-angled at the root)
	local dir = Vector3.new(side * math.cos(angle), math.sin(angle), sweep) * length
	local perp = Vector3.new(-side * math.sin(angle), math.cos(angle), 0) * (width / 2)
	local a = T.P(c, root.X, root.Y, root.Z)
	local tip = T.P(c, root.X + dir.X, root.Y + dir.Y, root.Z + dir.Z)
	local thick = (thickness or 0.07) * c.S
	rightTri(c, name .. "L", a, T.P(c, root.X + perp.X, root.Y + perp.Y, root.Z + perp.Z), tip, thick, light, material)
	if deep then
		rightTri(c, name .. "D", a, T.P(c, root.X - perp.X, root.Y - perp.Y, root.Z - perp.Z), tip, thick, deep, material)
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

local function skyTitan(c: Ctx): number
	-- white and gold armour (no part cost): a pearl marble body (still stone: a golem), gold fists and
	-- shoulder plates, the chest crystal
	for _, name in { "Body", "Head", "Arm1", "Arm2", "Leg1", "Leg2" } do
		T.recolor(c, name, PEARL, M.Marble)
	end
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, TITAN_GOLD, M.Foil)
	end
	T.redress(c, "Boulder", c.At(-0.84, 1.5, 0.02), c.V(0.7, 0.3, 0.76), TITAN_GOLD, M.Foil)
	T.redress(c, "Crystal", c.At(0.84, 1.5, 0.02), c.V(0.7, 0.3, 0.76), TITAN_GOLD, M.Foil)
	T.redress(c, "Core", c.At(0, 1.06, -0.5) * CFrame.Angles(0, 0, PI / 4), c.V(0.34, 0.34, 0.05), ICE, NEON)
	-- the crowned helm: pearl with a gold brow and cheek guards, a dark slit its ice eyes glow through
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), PEARL, M.Marble)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.26, 0.03), VISOR_DARK, M.SmoothPlastic)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.74) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.18, 0.26), TITAN_GOLD, M.Foil)
	for i, side in { -1, 1 } do
		K.part(c.Model, "HelmCheek" .. i, c.At(side * 0.69, 1.84, -0.7), c.V(0.24, 0.6, 0.08), TITAN_GOLD, M.Foil)
	end
	K.upright(c.Model, "CrownBand", c.At(0, 2.9, 0), 0.3 * c.S, 1.36 * c.S, TITAN_GOLD, M.Foil)
	for i = 1, 5 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.6
		local h = if i == 3 then 0.62 else 0.44
		diamond(
			c.Model,
			"CrownPoint" .. i,
			c.At(math.sin(a) * 0.66, 3.08, -math.cos(a) * 0.66) * CFrame.Angles(0, -a, 0),
			h * c.S,
			0.08 * c.S,
			TITAN_GOLD,
			M.Foil
		)
	end
	for i, a in { -0.6, 0, 0.6 } do
		if c.Room() < 1 then
			break
		end
		diamond(
			c.Model,
			"CrownGem" .. i,
			c.At(math.sin(a) * 0.7, 2.9, -math.cos(a) * 0.7) * CFrame.Angles(0, -a, 0),
			(if i == 2 then 0.17 else 0.13) * c.S,
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
	-- crystal wings: long two-tone ice shards fanning up and out behind the shoulders
	local wingShards = {
		{ 0.1, 1.35, 0.5 },
		{ 0.45, 2.05, 0.62 },
		{ 0.8, 2.7, 0.7 },
		{ 1.1, 2.65, 0.66 },
		{ 1.38, 2.2, 0.56 },
	}
	for i, side in { -1, 1 } do
		for k, w in wingShards do
			local root = Vector3.new(side * (0.42 + k * 0.03), 1.5 + k * 0.05, 0.5 + k * 0.035)
			shard(c, `Wing{i}_{k}`, root, side, w[1], w[2], w[3], 0.15, ICE_PALE, ICE_DEEP, M.SmoothPlastic)
		end
	end
	-- the great golden halo behind the crown
	halo(c, "Halo", 3.85, 0.92, 14, 0.1, HALO_GOLD, 0.25)
	-- gold pauldrons with a pearl rim and an ice gem
	for i, side in { -1, 1 } do
		if c.Room() < 3 then
			break
		end
		T.ellipsoid(
			c.Model,
			`Pauldron{i}_1`,
			c.At(side * 0.98, 1.66, 0.02) * CFrame.Angles(0, 0, side * -0.25),
			c.V(0.98, 0.66, 0.98),
			TITAN_GOLD,
			M.Foil
		)
		K.part(
			c.Model,
			`Pauldron{i}_2`,
			c.At(side * 1.02, 1.42, 0.02) * CFrame.Angles(0, 0, side * -0.3),
			c.V(0.82, 0.14, 0.92),
			PEARL,
			M.SmoothPlastic
		)
		diamond(c.Model, `Pauldron{i}_3`, c.At(side * 1.0, 1.68, -0.48), 0.22 * c.S, 0.06 * c.S, ICE_DEEP, NEON)
	end
	-- a gold breastplate framing the chest crystal, a gold belt with an ice buckle, a tabard
	if c.Room() >= 2 then
		K.part(c.Model, "Breastplate", c.At(0, 1.1, -0.45), c.V(1.0, 0.62, 0.05), TITAN_GOLD, M.Foil)
		diamond(c.Model, "CoreFrame", c.At(0, 1.06, -0.475), 0.5 * c.S, 0.04 * c.S, PEARL, M.SmoothPlastic)
	end
	if c.Room() >= 4 then
		K.part(c.Model, "Belt", c.At(0, 0.6, 0), c.V(1.26, 0.16, 0.92), TITAN_GOLD, M.Foil)
		diamond(c.Model, "Buckle", c.At(0, 0.6, -0.47), 0.24 * c.S, 0.05 * c.S, ICE_DEEP, NEON)
		K.part(c.Model, "Tabard", c.At(0, 0.36, -0.36) * CFrame.Angles(0.1, 0, 0), c.V(0.42, 0.44, 0.05), PEARL_SHADE, M.SmoothPlastic)
		K.part(c.Model, "TabardHem", c.At(0, 0.15, -0.385) * CFrame.Angles(0.1, 0, 0), c.V(0.46, 0.07, 0.06), TITAN_GOLD, M.Foil)
	end
	-- the gold staff in the right fist, an ice crystal in its crescent
	if c.Room() >= 5 then
		local x, z = 1.18, -0.5
		T.seg(c.Model, "Staff", T.P(c, x, 0.0, z), T.P(c, x, 3.2, z), 0.12 * c.S, 0.12 * c.S, TITAN_GOLD, M.Foil)
		K.upright(c.Model, "StaffCap", c.At(x, 3.2, z), 0.12 * c.S, 0.26 * c.S, TITAN_GOLD, M.Foil)
		for i, side in { -1, 1 } do
			T.seg(
				c.Model,
				"StaffProng" .. i,
				T.P(c, x, 3.2, z),
				T.P(c, x + side * 0.26, 3.66, z),
				0.09 * c.S,
				0.09 * c.S,
				TITAN_GOLD,
				M.Foil
			)
		end
		gem(c, "StaffGem", c.At(x, 3.58, z), 0.22, 0.5, ICE_DEEP, NEON)
	end
	-- gold boots and bracers
	for i, x in { -0.3, 0.3 } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Boot" .. i, c.At(x, 0.1, -0.05), c.V(0.52, 0.2, 0.64), TITAN_GOLD, M.Foil)
	end
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		K.part(
			c.Model,
			"Bracer" .. i,
			c.At(side * 0.82, 0.94, 0) * CFrame.Angles(0, 0, side * 0.1),
			c.V(0.44, 0.14, 0.54),
			TITAN_GOLD,
			M.Foil
		)
	end
	-- ice crystals floating round its legs (little cubes standing on a corner)
	for i, k in { { -1.35, 0.55, -0.3 }, { 1.55, 0.95, 0.35 }, { -1.6, 1.2, 0.45 }, { 1.35, 0.4, -0.4 } } do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "CrystalBit" .. i, c.At(k[1], k[2], k[3]) * CFrame.Angles(0.62, PI / 4 + i, 0), c.V(0.2, 0.2, 0.2), ICE_DEEP, NEON)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, ICE, 5, 0.3)
		T.light(body, ICE, 12, 1.3)
	end
	return 4.0
end

local function cloudColossus(c: Ctx): number
	-- dark storm rock (no part cost): the arms, legs, head and big rock fists, bright eyes
	for _, name in { "Arm1", "Arm2", "Head" } do
		T.recolor(c, name, STORM_ROCK, M.Slate)
	end
	for _, name in { "Leg1", "Leg2" } do
		T.recolor(c, name, STORM_ROCK_DARK, M.Slate)
	end
	for _, name in { "Eye1", "Eye2" } do
		T.recolor(c, name, LIGHTNING, NEON)
	end
	for i, side in { -1, 1 } do
		T.redress(
			c,
			"Fist" .. i,
			c.At(side * 0.9, 0.64, -0.06) * CFrame.Angles(0.2, side * 0.3, side * 0.12),
			c.V(0.6, 0.54, 0.56),
			STORM_ROCK,
			M.Slate
		)
	end
	T.redress(c, "Boulder", c.At(-0.84, 1.5, 0.02), c.V(0.72, 0.32, 0.78), STORM_ROCK_DARK, M.Slate)
	T.redress(c, "Crystal", c.At(0.84, 1.5, 0.02), c.V(0.72, 0.32, 0.78), STORM_ROCK_DARK, M.Slate)
	T.redress(c, "Core", c.At(0, 1.04, -0.5) * CFrame.Angles(0, 0, PI / 4), c.V(0.36, 0.36, 0.05), LIGHTNING, NEON)
	-- a rock helm, a dark slit its blue eyes glow through, a crown of rock shards
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), STORM_ROCK, M.Slate)
	K.part(c.Model, "Visor", c.At(0, 2.02, -0.715), c.V(1.12, 0.26, 0.03), STORM_ROCK_DARK, M.Slate)
	K.part(c.Model, "HelmBrow", c.At(0, 2.32, -0.74) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.18, 0.26), STORM_ROCK_DARK, M.Slate)
	for i, k in { { -0.5, 0.5 }, { -0.18, 0.72 }, { 0.2, 0.66 }, { 0.52, 0.46 } } do
		local side = if k[1] < 0 then -1 else 1
		shard(c, "Spike" .. i, Vector3.new(k[1], 2.7, 0.1), side, PI / 2 - 0.25, k[2], 0.4, 0, STORM_ROCK, STORM_ROCK_DARK, M.Slate, 0.3)
	end
	-- huge thunderclouds on the shoulders
	for i, side in { -1, 1 } do
		puffs(c, `Pauldron{i}_`, {
			{ side * 1.02, 1.74, 0.05, 1.05 },
			{ side * 1.42, 1.58, -0.12, 0.8 },
			{ side * 0.78, 2.0, 0.22, 0.74 },
			{ side * 1.24, 2.06, 0.28, 0.72 },
			{ side * 1.08, 1.42, -0.36, 0.68 },
			{ side * 1.5, 1.92, 0.36, 0.6 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
	end
	-- the storm ring over the head, a cloud riding on it, a stone floating in it
	halo(c, "StormRing", 3.72, 0.95, 12, 0.11, LIGHTNING, 0.1)
	puffs(
		c,
		"RingCloud",
		{ { 0, 4.02, 0.08, 0.6 }, { -0.34, 3.94, 0.14, 0.44 }, { 0.36, 3.96, 0.12, 0.42 } },
		THUNDERHEAD,
		THUNDERHEAD_SHADE
	)
	if c.Room() >= 1 then
		K.part(c.Model, "RingStone", c.At(0, 3.56, 0.08) * CFrame.Angles(0.62, PI / 4, 0), c.V(0.26, 0.26, 0.26), STORM_ROCK_DARK, M.Slate)
	end
	-- blue lightning running in the rock: the chest, the arms, the legs, the fists
	zigzag(c, "Bolt", { { -0.38, 1.36 }, { -0.14, 1.18 }, { -0.3, 0.92 }, { -0.06, 0.66 } }, -0.45, 0.06, LIGHTNING)
	zigzag(c, "BoltR", { { 0.4, 1.32 }, { 0.16, 1.12 }, { 0.32, 0.86 } }, -0.45, 0.06, LIGHTNING)
	for i, side in { -1, 1 } do
		zigzag(c, `ArmBolt{i}_`, { { side * 0.76, 1.36 }, { side * 0.86, 1.16 }, { side * 0.74, 0.98 } }, -0.26, 0.05, LIGHTNING)
		zigzag(
			c,
			`LegBolt{i}_`,
			{ { side * 0.38, 0.48 }, { side * 0.26, 0.28 }, { side * 0.37, 0.25 }, { side * 0.23, 0.04 } },
			-0.25,
			0.05,
			LIGHTNING
		)
		-- a crack of lightning across the fist's front
		if c.Room() >= 1 then
			local fist = c.At(side * 0.9, 0.64, -0.06) * CFrame.Angles(0.2, side * 0.3, side * 0.12)
			K.part(
				c.Model,
				"FistBolt" .. i,
				fist * CFrame.new(0, 0, -0.285 * c.S) * CFrame.Angles(0, 0, side * 0.7),
				c.V(0.05, 0.5, 0.03),
				LIGHTNING,
				NEON
			)
		end
	end
	-- rocks floating round it (on a corner), some cracked with lightning
	local rocks = {
		{ -1.95, 2.55, 0.2, 0.42 },
		{ 1.9, 2.7, -0.1, 0.38 },
		{ -2.1, 1.2, -0.2, 0.34 },
		{ 2.15, 1.35, 0.3, 0.4 },
		{ -1.7, 0.35, 0.5, 0.3 },
		{ 1.75, 0.5, -0.45, 0.32 },
		{ -0.95, 3.3, 0.55, 0.3 },
		{ 1.05, 3.35, 0.5, 0.28 },
	}
	for i, k in rocks do
		if c.Room() < 1 then
			break
		end
		local cf = c.At(k[1], k[2], k[3]) * CFrame.Angles(0.62, PI / 4 + i * 0.9, i * 0.35)
		K.part(
			c.Model,
			"BoulderRock" .. i,
			cf,
			c.V(k[4], k[4] * 0.85, k[4] * 0.9),
			if i % 3 == 0 then STORM_ROCK else STORM_ROCK_DARK,
			M.Slate
		)
		if i <= 4 and c.Room() >= 1 then
			K.part(c.Model, `BoulderRock{i}Vein`, cf * CFrame.Angles(0, 0, 0.5), c.V(k[4] * 1.04, 0.05, k[4] * 0.94), LIGHTNING, NEON)
		end
	end
	-- clouds wrapped round the forearms, the waist and the feet
	for i, side in { -1, 1 } do
		puffs(c, `Wrap{i}_`, {
			{ side * 0.6, 1.0, -0.22, 0.5 },
			{ side * 1.1, 0.98, -0.1, 0.5 },
			{ side * 0.92, 1.04, 0.3, 0.46 },
			{ side * 0.6, 1.02, 0.26, 0.44 },
		}, THUNDERHEAD, THUNDERHEAD_SHADE)
	end
	puffs(c, "CloudBelt", {
		{ -0.7, 0.62, 0.04, 0.56 },
		{ 0.7, 0.62, 0.04, 0.56 },
		{ -0.3, 0.6, 0.42, 0.5 },
		{ 0.32, 0.6, 0.42, 0.5 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	puffs(c, "CloudFeet", {
		{ -0.64, 0.14, 0.08, 0.5 },
		{ 0.64, 0.14, 0.08, 0.5 },
		{ 0, 0.12, 0.44, 0.52 },
	}, THUNDERHEAD, THUNDERHEAD_SHADE)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, LIGHTNING, 6, 0.3)
		T.light(body, STORM_BLUE, 12, 1.4)
	end
	return 4.0
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
