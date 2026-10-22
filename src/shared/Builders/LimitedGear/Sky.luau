--[[
	SKY (the SKY EGG's golems, a proposal for the owner): the costumes of its
	three golems (GolemGearLimited explains the contract and the tools).

	  SkyPuff       Sky Sprite (Epic): a cloud for hair, big shiny eyes, a
	                little gold halo, small feathered wings, a cloud tail, a
	                star wand
	  StormArmor    Storm Warden (Legendary): storm-grey armour, a horned
	                storm helm with a glowing visor, thundercloud pauldrons,
	                a lightning spear, lightning running in its armour, a
	                storm cape, embers
	  AetherWings   Aether King (Mythic): pearl and gold, great angel wings
	                in two layers, a golden halo over a sky-gem crown, a
	                sky-blue royal cape, a sceptre with a sun orb, clouds at
	                its feet, embers and its own light
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local Sky = {}

Sky.Faces = {
	StormArmor = "Closed",
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
local STORM_DARK = rgb(34, 38, 56)
local BOLT = rgb(255, 230, 90)
local PUPIL = rgb(24, 30, 50)

local T: Tools = nil :: any
local K: Kit = nil :: any

local function diamond(parent: Instance, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?): Part
	return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, w, thick), color, material)
end

-- big shiny eyes: slit pupils and a white sparkle each
local function eyes(c: Ctx, iris: Color3)
	for i, x in { -0.29, 0.29 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.0, -0.68), c.V(0.32, 0.3, 0.06), iris, NEON)
		if c.Room() >= 2 then
			K.part(c.Model, "Pupil" .. i, c.At(x, 1.99, -0.715), c.V(0.08, 0.22, 0.02), PUPIL)
			K.part(c.Model, "Sparkle" .. i, c.At(x - 0.07, 2.07, -0.722), c.V(0.07, 0.07, 0.02), Color3.new(1, 1, 1), NEON)
		end
	end
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

---------------------------------------------------------------- the costumes

local function skySprite(c: Ctx): number
	T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), c.Look.Body, M.SmoothPlastic)
	T.redress(c, "Boulder", c.At(-0.62, 1.5, 0.1), c.V(0.4, 0.34, 0.4), CLOUD_SHADE, M.SmoothPlastic)
	T.redress(c, "Crystal", c.At(0.62, 1.5, 0.1), c.V(0.4, 0.34, 0.4), CLOUD_SHADE, M.SmoothPlastic)
	T.redress(c, "Core", c.At(0, 1.08, -0.445) * CFrame.Angles(0, 0, PI / 4), c.V(0.3, 0.3, 0.06), c.Glow, NEON)
	eyes(c, SKY)
	-- a cloud for hair
	cloud(c, "Puff", Vector3.new(0, 2.85, 0.05), 1.0, 6, CLOUD)
	-- a little gold halo
	halo(c, "Halo", 3.45, 0.42, 8, 0.07, GOLD)
	-- small feathered wings
	for _, side in { -1, 1 } do
		wing(c, side, 3, 1.1, 1.25, CLOUD, SKY, 1)
	end
	-- pink cheeks
	for i, x in { -0.5, 0.5 } do
		if c.Room() >= 1 then
			K.part(c.Model, "Blush" .. i, c.At(x, 1.8, -0.665), c.V(0.2, 0.1, 0.02), rgb(255, 160, 190), M.SmoothPlastic)
		end
	end
	-- a star wand in the right fist
	if c.Room() >= 3 then
		T.seg(c.Model, "Wand", T.P(c, 0.9, 0.6, -0.2), T.P(c, 1.05, 1.9, -0.45), 0.08 * c.S, 0.08 * c.S, GOLD, M.Foil)
		local star = c.At(1.07, 2.05, -0.48)
		diamond(c.Model, "WandStar1", star, 0.36 * c.S, 0.08 * c.S, rgb(255, 240, 140), NEON)
		K.part(c.Model, "WandStar2", star, c.V(0.36, 0.36, 0.08), rgb(255, 240, 140), NEON)
	end
	-- a cloud under its feet
	cloud(c, "Floor", Vector3.new(0, 0.05, 0.05), 1.2, 4, CLOUD)
	return 3.6
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
	T.redress(c, "Brow", c.At(0, 2.3, -0.645) * CFrame.Angles(-0.2, 0, 0), c.V(1.3, 0.1, 0.18), GOLD, M.Foil)
	T.redress(c, "Boulder", c.At(-0.8, 1.48, 0.02), c.V(0.62, 0.22, 0.7), GOLD, M.Foil)
	T.redress(c, "Crystal", c.At(0.8, 1.48, 0.02), c.V(0.62, 0.22, 0.7), GOLD, M.Foil)
	eyes(c, SKY)
	-- great angel wings in two layers
	for _, side in { -1, 1 } do
		wing(c, side, 4, 2.0, 1.15, CLOUD, GOLD, 1)
	end
	for _, side in { -1, 1 } do
		wing(c, side, 3, 1.5, 1.05, CLOUD_SHADE, SKY, 2)
	end
	-- the sky-gem crown and a golden halo over it
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
	-- a sky-blue royal cape with a gold hem
	cape(c, SKY_DEEP, GOLD, 0.6)
	-- gold armour and a sceptre with a sun orb
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.06, -0.435), c.V(0.96, 0.66, 0.04), GOLD, M.Foil)
	end
	T.redress(c, "Core", c.At(0, 1.08, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.32, 0.32, 0.04), SKY, NEON)
	if c.Room() >= 3 then
		T.seg(c.Model, "Staff", T.P(c, 1.08, 0.05, -0.42), T.P(c, 1.08, 2.3, -0.42), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		diamond(c.Model, "StaffHead", c.At(1.08, 2.4, -0.42), 0.4 * c.S, 0.12 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Orb", c.At(1.08, 2.66, -0.42), c.V(0.38, 0.38, 0.38), rgb(255, 240, 160), NEON, BALL)
	end
	-- clouds at its feet
	cloud(c, "Floor", Vector3.new(0, 0.05, 0.05), 1.5, 5, CLOUD)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, GOLD, 5)
		T.light(body, SKY, 8, 1.2)
	end
	return 4.0
end

function Sky.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		SkyPuff = skySprite,
		StormArmor = stormWarden,
		AetherWings = aetherKing,
	}
end

return Sky
