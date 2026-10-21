--[[
	FROST TITANS (upcoming limited edition): the costumes of the set's 6
	golems and the set's shard (GolemGearLimited explains the contract and
	the tools).

	  IcicleHair    Frostling (Rare): spiky icicle hair growing out of a snow
	                cap with a snowflake clip, big sparkly eyes, pink cheeks,
	                a pink striped scarf streaming in the wind, snow boots
	                with fluffy cuffs, an ice pop, a jagged shard on its back
	  Beanie        Glacier Cub (Rare): a polar bear cub: a knitted red
	                beanie with a cream cuff, a stripe and a pom-pom, round
	                ears, a snout with a little black nose, a striped scarf,
	                red mittens and red snow boots, a snowball, and its pet
	                PENGUIN in a matching scarf and pom-pom
	  FrostHelm     Icebound Knight (Epic): a closed ice helm with a T visor,
	                a navy crown band, a glowing crystal crest and fins,
	                crystal pauldrons, a flared royal-blue cape with a snow-fur
	                collar and hem and a glowing clasp, a frost sword, a kite
	                shield with a rim and a glowing snowflake, armoured boots
	  SnowCloud     Blizzard Sage (Epic): a deep blue hood with a snow-fur
	                trim, a glowing gem and a tip down its back, its own snow
	                cloud floating over it with falling snowflakes, a beard of
	                icicles, a staff with a glowing snowflake, a long navy
	                cape with a glowing hem, a robe, an orb in its hand
	  IcicleCrown   Polar Titan (Legendary): a horned ice helm (a dome, a
	                navy band with a gem, a nose guard, great ivory horns,
	                three crown icicles), two curved ivory TUSKS, a royal fur
	                cape with an ermine collar and hem, huge ice crystal
	                shoulders, an ice war axe with a glowing blade, bracers,
	                fur boots, a snowflake on its chest, snow sparkles
	  AuroraCrown   Aurora Colossus (Mythic): the northern lights as three
	                ribbon arcs (green, cyan, violet) round an icicle crown
	                with a violet gem, a flared aurora cape with a fur collar
	                and a glowing green hem, big crystal wings (their lowest
	                blades glowing violet), crystal armour, an aurora
	                scepter, an aurora snowflake, sparkles and its own light

	The shard: a FROST EGG (a glossy ice egg like the egg games' eggs): a snow
	cap dripping over the tip with a glowing frost star on top, a glossy
	shine, little ice wings, ice crystals breaking out, a ribbon of the
	northern lights round the waist, a glowing snowflake emblem, frost
	sparkles, and an ice stand in a snowdrift ringed with crystals.
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local FrostTitans = {}

FrostTitans.Faces = {
	FrostHelm = "Closed",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local SNOW = rgb(250, 252, 255)
local ICE_PALE = rgb(210, 240, 255)
local ICE = rgb(150, 220, 255)
local ICE_CYAN = rgb(90, 210, 255)
local ICE_DEEP = rgb(50, 120, 220)
local NAVY = rgb(26, 44, 112)
local NAVY_DARK = rgb(14, 22, 60)
local SPARKLE = rgb(255, 255, 255)
local BLUSH = rgb(255, 150, 190)
local WOOL = rgb(222, 44, 66)
local CREAM = rgb(255, 246, 228)
local NOSE = rgb(30, 30, 44)
local SCARF_PINK = rgb(255, 104, 170)
local AURORA_GREEN = rgb(60, 255, 150)
local AURORA_CYAN = rgb(50, 220, 255)
local AURORA_VIOLET = rgb(176, 96, 255)

-- (the shared tools, filled by accessories / shard)
local T: Tools = nil :: any
local K: Kit = nil :: any

---------------------------------------------------------------- small shapes

-- a diamond (a square turned 45 degrees about its facing axis)
local function diamond(
	parent: Instance,
	name: string,
	cf: CFrame,
	w: number,
	h: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): Part
	return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, h, thick), color, material)
end

-- a crystal: a box with a diamond section along its Y axis
local function crystal(parent: Instance, name: string, cf: CFrame, w: number, h: number, color: Color3, material: Enum.Material?): Part
	return K.part(parent, name, cf * CFrame.Angles(0, PI / 4, 0), Vector3.new(w, h, w), color, material)
end

-- a golem-local crystal from base point b leaning by (rx, rz)
local function gcrystal(
	c: Ctx,
	name: string,
	b: Vector3,
	w: number,
	h: number,
	rx: number,
	rz: number,
	color: Color3,
	material: Enum.Material?
)
	local cf = c.At(b.X, b.Y, b.Z) * CFrame.Angles(rx, 0, rz) * CFrame.new(0, h * c.S / 2, 0)
	crystal(c.Model, name, cf, w * c.S, h * c.S, color, material)
end

--[[
	A pointed spike (an icicle, a hair spike, a crystal blade): a thick
	triangle from a base of width w round golem-local `base` to the `tip`.
	`side` (golem-local) is the base's direction (default: across the front).
	Up to 2 parts; returns the tip's height.
]]
local function spike(
	c: Ctx,
	name: string,
	base: Vector3,
	tip: Vector3,
	w: number,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	side: Vector3?
): number
	local room = c.Room()
	if room < 1 then
		return 0
	end
	local d = tip - base
	local across = side or d:Cross(Vector3.zAxis)
	if across.Magnitude < 1e-4 then
		across = Vector3.xAxis
	end
	across = across.Unit * (w / 2)
	local a, b = base - across, base + across
	T.tri(
		c.Model,
		name,
		T.P(c, a.X, a.Y, a.Z),
		T.P(c, b.X, b.Y, b.Z),
		T.P(c, tip.X, tip.Y, tip.Z),
		thick * c.S,
		color,
		material,
		math.min(room, 2)
	)
	return math.max(tip.Y, base.Y)
end

-- a snowflake: three bars crossing in the cf's facing plane (up to 3 parts)
local function snowflake(c: Ctx, name: string, cf: CFrame, size: number, bar: number, colors: { Color3 })
	for i = 1, 3 do
		if c.Room() < 1 then
			return
		end
		local cfi = cf * CFrame.Angles(0, 0, (i - 1) * PI / 3)
		K.part(c.Model, name .. i, cfi, c.V(bar, size, 0.03), colors[math.min(i, #colors)], NEON)
	end
end

local function ball(c: Ctx, name: string, x: number, y: number, z: number, d: number, color: Color3, material: Enum.Material?): Part
	return K.part(c.Model, name, c.At(x, y, z), c.V(d, d, d), color, material, BALL)
end

local function egg(c: Ctx, name: string, cf: CFrame, x: number, y: number, z: number, color: Color3, material: Enum.Material?): Part
	return T.ellipsoid(c.Model, name, cf, c.V(x, y, z), color, material)
end

-- an arc of segments in the plane facing the front, round golem-local
-- `center`, from angle a0 to a1 (0 = straight up, + = to the golem's right)
local function arc(c: Ctx, name: string, center: Vector3, radius: number, a0: number, a1: number, n: number, width: number, color: Color3)
	local function at(a: number, wobble: number): Vector3
		local r = radius + wobble
		return T.P(c, center.X + math.sin(a) * r, center.Y + math.cos(a) * r, center.Z)
	end
	for i = 1, n do
		if c.Room() < 1 then
			return
		end
		local t0, t1 = a0 + (a1 - a0) * (i - 1) / n, a0 + (a1 - a0) * i / n
		-- (each segment reaches a little past its joints; a gentle wave)
		local wob = if i % 2 == 0 then 0.06 else -0.04
		local a, b = at(t0, wob), at(t1, -wob)
		local dir = (b - a).Unit
		local p = T.seg(c.Model, name .. i, a - dir * 0.06 * c.S, b + dir * 0.06 * c.S, 0.05 * c.S, width * c.S, color, NEON)
		p.Transparency = 0.15
	end
end

---------------------------------------------------------------- body pieces

-- a frosty white brow (smaller than the stone one)
local function snowBrow(c: Ctx, w: number, h: number)
	T.redress(c, "Brow", c.At(0, 2.32, -0.66) * CFrame.Angles(-0.2, 0, 0), c.V(w, h, 0.22), SNOW, M.Snow)
end

local function noBrow(c: Ctx)
	T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), c.Look.Body, M.Snow)
end

-- big round sparkly eyes (2 sparkles when the budget allows)
local function bigEyes(c: Ctx, size: number)
	for i, x in { -0.3, 0.3 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.0, -0.68), c.V(size, size * 1.1, 0.06), c.Glow, NEON)
	end
	if c.Room() >= 2 then
		for i, x in { -0.3, 0.3 } do
			K.part(c.Model, "Sparkle" .. i, c.At(x - size * 0.22, 2.0 + size * 0.24, -0.715), c.V(0.09, 0.09, 0.02), SPARKLE, NEON)
		end
	end
end

local function cheeks(c: Ctx, y: number)
	if c.Room() >= 2 then
		for i, x in { -0.52, 0.52 } do
			K.part(c.Model, "Cheek" .. i, c.At(x, y, -0.665), c.V(0.24, 0.12, 0.02), BLUSH, M.SmoothPlastic)
		end
	end
end

-- the shoulder boulder and crystal re-dressed as two ice crystals jutting up
-- and out (k = size)
local function iceShoulders(c: Ctx, k: number, color: Color3, material: Enum.Material)
	for i, side in { -1, 1 } do
		T.redress(
			c,
			if i == 1 then "Boulder" else "Crystal",
			c.At(side * (0.82 + 0.06 * k), 1.5 + 0.4 * k, 0.04) * CFrame.Angles(0, 0, -side * 0.42) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.3 * k, 0.9 * k, 0.3 * k),
			color,
			material
		)
	end
end

-- snow boots: the legs re-coloured, a fluffy fur cuff round each top
local function boots(c: Ctx, color: Color3, material: Enum.Material, cuff: Color3?)
	for i, x in { -0.3, 0.3 } do
		T.recolor(c, "Leg" .. i, color, material)
		if cuff and c.Room() >= 1 then
			egg(c, "BootCuff" .. i, c.At(x, 0.48, 0.02), 0.58, 0.2, 0.66, cuff, M.Fabric)
		end
	end
end

--[[
	A cape hanging from the shoulders behind the golem: a fur collar round
	the neck (hides the top edge), the cloth leaning back a little, two
	wedges flaring it out at the bottom, a fur (or glowing) hem and a clasp
	gem on the chest. Up to 7 parts; skips pieces when the budget is short.
]]
-- a right triangle from ONE wedge: the right angle at world point
-- `corner`, the legs to `a` (the wedge's up) and `b`
local function rightTri(
	c: Ctx,
	name: string,
	corner: Vector3,
	a: Vector3,
	b: Vector3,
	thick: number,
	color: Color3,
	material: Enum.Material
)
	local up, back = a - corner, corner - b
	local y, z = up.Unit, back.Unit
	local cf = CFrame.fromMatrix((a + b) / 2, y:Cross(z), y, z)
	K.wedge(c.Model, name, cf, Vector3.new(thick, up.Magnitude, back.Magnitude), color, material)
end

type CapeOpts = {
	Top: number, -- the cloth's top (unscaled y)
	Bottom: number,
	Width: number, -- at the top
	Flare: number, -- how far each side flares out at the bottom
	Z: number, -- the cloth's top z (behind the back)
	Back: number, -- how much further back the bottom hangs
	Cloth: Color3,
	Material: Enum.Material?,
	Hem: Color3?,
	HemMaterial: Enum.Material?,
	Collar: Vector3?, -- the fur collar's size (unscaled)
	CollarColor: Color3?,
	Clasp: Color3?,
}

local function cape(c: Ctx, o: CapeOpts)
	local material = o.Material or M.Fabric
	local h = o.Top - o.Bottom
	local zb = o.Z + o.Back
	local tilt = math.atan2(o.Back, h)
	if o.Collar and c.Room() >= 1 then
		local s = o.Collar :: Vector3
		egg(c, "CapeCollar", c.At(0, 1.5, 0.06), s.X, s.Y, s.Z, o.CollarColor or SNOW, M.Fabric)
	end
	if c.Room() >= 1 then
		local cf = c.At(0, o.Bottom + h / 2, (o.Z + zb) / 2) * CFrame.Angles(-tilt, 0, 0)
		K.part(c.Model, "Cape", cf, c.V(o.Width, math.sqrt(h * h + o.Back * o.Back), 0.06), o.Cloth, material)
	end
	for i, side in { -1, 1 } do
		if c.Room() < 1 or o.Flare <= 0 then
			break
		end
		local x = side * o.Width / 2
		rightTri(
			c,
			"CapeFlare" .. i,
			T.P(c, x, o.Bottom, zb),
			T.P(c, x, o.Top, o.Z),
			T.P(c, x + side * o.Flare, o.Bottom, zb),
			0.06 * c.S,
			o.Cloth,
			material
		)
	end
	if o.Hem and c.Room() >= 1 then
		K.part(
			c.Model,
			"CapeHem",
			c.At(0, o.Bottom, zb),
			c.V(o.Width + 2 * o.Flare + 0.06, 0.16, 0.16),
			o.Hem :: Color3,
			o.HemMaterial or M.Fabric
		)
	end
	if o.Clasp and c.Room() >= 1 then
		diamond(c.Model, "Clasp", c.At(0, 1.42, -0.58), 0.2 * c.S, 0.2 * c.S, 0.06 * c.S, o.Clasp :: Color3, NEON)
	end
end

---------------------------------------------------------------- the costumes

local function frostling(c: Ctx): number
	snowBrow(c, 1.3, 0.14)
	iceShoulders(c, 0.7, ICE_PALE, M.Glass)
	-- the snow cap the hair grows from
	K.part(c.Model, "SnowCap", c.At(0, 2.75, 0.02), c.V(1.58, 0.14, 1.38), SNOW, M.Snow)
	-- spiky icicle hair: a front fan and a back pair, the middle the tallest
	local hair: { { any } } = {
		{ Vector3.new(0, 2.78, -0.16), Vector3.new(0.02, 3.9, -0.05), 0.58, ICE_PALE },
		{ Vector3.new(-0.38, 2.76, -0.12), Vector3.new(-0.78, 3.56, 0.0), 0.48, ICE },
		{ Vector3.new(0.38, 2.76, -0.12), Vector3.new(0.8, 3.56, 0.0), 0.48, ICE },
		{ Vector3.new(-0.62, 2.72, 0.2), Vector3.new(-1.12, 3.12, 0.3), 0.4, ICE_CYAN },
		{ Vector3.new(0.62, 2.72, 0.2), Vector3.new(1.12, 3.12, 0.3), 0.4, ICE_CYAN },
	}
	local top = 2.82
	for i, h in hair do
		top = math.max(top, spike(c, "Hair" .. i, h[1] :: Vector3, h[2] :: Vector3, h[3] :: number, 0.22, h[4] :: Color3, M.Glass))
	end
	-- a snowflake hair clip
	if c.Room() >= 1 then
		diamond(c.Model, "HairClip", c.At(0.5, 2.78, -0.7), 0.2 * c.S, 0.2 * c.S, 0.05 * c.S, c.Glow, NEON)
	end
	bigEyes(c, 0.3)
	cheeks(c, 1.78)
	-- the icy scarf: a wrap, a stripe, an end hanging down the front and
	-- a tail streaming back in the wind
	K.part(c.Model, "Scarf", c.At(0, 1.5, 0), c.V(1.38, 0.28, 1.02), SCARF_PINK, M.Fabric)
	if c.Room() >= 1 then
		K.part(c.Model, "ScarfStripe", c.At(0, 1.5, 0), c.V(1.4, 0.08, 1.04), SNOW, M.Fabric)
	end
	if c.Room() >= 2 then
		K.part(c.Model, "ScarfEnd", c.At(0.34, 1.12, -0.52) * CFrame.Angles(0, 0, 0.12), c.V(0.3, 0.62, 0.08), SCARF_PINK, M.Fabric)
		K.part(c.Model, "ScarfFringe", c.At(0.38, 0.8, -0.525) * CFrame.Angles(0, 0, 0.12), c.V(0.32, 0.1, 0.09), SNOW, M.Fabric)
	end
	spike(c, "ScarfTail", Vector3.new(-0.5, 1.5, 0.5), Vector3.new(-1.4, 1.74, 0.62), 0.28, 0.06, SCARF_PINK, M.Fabric, Vector3.yAxis)
	-- a snowflake on the chest (the core at its heart)
	T.redress(c, "Core", c.At(0, 1.0, -0.46) * CFrame.Angles(0, 0, PI / 4), c.V(0.14, 0.14, 0.04), SPARKLE, NEON)
	snowflake(c, "Flake", c.At(0, 1.0, -0.44), 0.5, 0.07, { c.Glow })
	-- snow boots with fluffy cuffs, frosty fists
	boots(c, rgb(80, 160, 235), M.Fabric, SNOW)
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, ICE_PALE, M.Glass)
	end
	-- an ice pop in the left hand: a stick, the pop, a frosty bite
	if c.Room() >= 3 then
		K.part(c.Model, "PopStick", c.At(-0.98, 0.96, -0.4), c.V(0.07, 0.42, 0.07), CREAM, M.Wood)
		K.part(c.Model, "Pop", c.At(-0.98, 1.36, -0.4), c.V(0.34, 0.5, 0.16), rgb(120, 200, 255), M.SmoothPlastic)
		K.part(c.Model, "PopTop", c.At(-0.98, 1.6, -0.4), c.V(0.36, 0.1, 0.18), SNOW, M.Snow)
	end
	-- a jagged ice shard on its back
	spike(c, "BackShard", Vector3.new(0.1, 0.9, 0.5), Vector3.new(0.3, 2.0, 0.62), 0.5, 0.2, ICE_CYAN, M.Glass)
	return top
end

-- a little penguin friend standing at the cub's side (feet at y 0)
local function penguin(c: Ctx, x: number, z: number)
	if c.Room() < 5 then
		return
	end
	local ink = rgb(34, 40, 62)
	local orange = rgb(255, 160, 40)
	egg(c, "PenguinBody", c.At(x, 0.46, z), 0.6, 0.9, 0.56, ink, M.SmoothPlastic)
	egg(c, "PenguinBelly", c.At(x, 0.46, z - 0.2), 0.44, 0.78, 0.22, SNOW, M.SmoothPlastic)
	K.part(c.Model, "PenguinBeak", c.At(x, 0.66, z - 0.33) * CFrame.Angles(0, PI / 4, 0), c.V(0.12, 0.08, 0.12), orange)
	K.part(c.Model, "PenguinFeet", c.At(x, 0.03, z - 0.14), c.V(0.4, 0.06, 0.24), orange)
	K.part(c.Model, "PenguinScarf", c.At(x, 0.6, z), c.V(0.56, 0.1, 0.52), WOOL, M.Fabric)
	if c.Room() >= 2 then
		for i, dx in { -0.1, 0.1 } do
			K.part(c.Model, "PenguinEye" .. i, c.At(x + dx, 0.76, z - 0.3), c.V(0.07, 0.08, 0.03), NOSE)
		end
	end
	if c.Room() >= 1 then
		ball(c, "PenguinPom", x, 0.95, z, 0.18, WOOL, M.Fabric)
	end
end

local function glacierCub(c: Ctx): number
	noBrow(c)
	-- the knitted beanie: cuff, crown, stripe, dome and the pom-pom
	K.part(c.Model, "BeanieCuff", c.At(0, 2.74, 0.02), c.V(1.62, 0.28, 1.42), CREAM, M.Fabric)
	K.part(c.Model, "Beanie", c.At(0, 2.96, 0.02), c.V(1.54, 0.2, 1.34), WOOL, M.Fabric)
	egg(c, "BeanieDome", c.At(0, 3.02, 0.02), 1.54, 0.76, 1.34, WOOL, M.Fabric)
	ball(c, "PomPom", 0, 3.48, 0.04, 0.52, CREAM, M.Fabric)
	local top = 3.74
	-- round bear ears poking out of the hat
	for i, side in { -1, 1 } do
		if c.Room() >= 2 then
			ball(c, "Ear" .. i, side * 0.62, 3.14, 0.1, 0.44, c.Look.Body, M.SmoothPlastic)
			K.part(c.Model, "EarIn" .. i, c.At(side * 0.64, 3.14, -0.1), c.V(0.22, 0.22, 0.04), BLUSH, M.SmoothPlastic, BALL)
		end
	end
	if c.Room() >= 1 then
		K.part(c.Model, "BeanieStripe", c.At(0, 3.0, 0.02), c.V(1.58, 0.08, 1.38), CREAM, M.Fabric)
	end
	-- the snout with a little black nose
	if c.Room() >= 2 then
		egg(c, "Snout", c.At(0, 1.74, -0.66), 0.62, 0.4, 0.3, SNOW, M.SmoothPlastic)
		egg(c, "Nose", c.At(0, 1.84, -0.81), 0.22, 0.14, 0.1, NOSE, M.SmoothPlastic)
	end
	bigEyes(c, 0.28)
	cheeks(c, 1.82)
	-- the striped scarf, its end hanging down the front
	if c.Room() >= 2 then
		K.part(c.Model, "Scarf", c.At(0, 1.5, 0), c.V(1.36, 0.26, 1.0), WOOL, M.Fabric)
		K.part(c.Model, "ScarfEnd", c.At(0.34, 1.12, -0.5) * CFrame.Angles(0, 0, 0.12), c.V(0.3, 0.62, 0.08), WOOL, M.Fabric)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "ScarfStripe", c.At(0, 1.5, 0), c.V(1.38, 0.08, 1.02), CREAM, M.Fabric)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "ScarfFringe", c.At(0.38, 0.8, -0.505) * CFrame.Angles(0, 0, 0.12), c.V(0.32, 0.1, 0.09), CREAM, M.Fabric)
	end
	-- red mittens with cream cuffs (the boulder and the crystal)
	for i, side in { -1, 1 } do
		T.recolor(c, "Fist" .. i, WOOL, M.Fabric)
		T.redress(c, if i == 1 then "Boulder" else "Crystal", c.At(side * 0.84, 0.92, -0.02), c.V(0.5, 0.14, 0.52), CREAM, M.Fabric)
	end
	-- a belly patch, red snow boots with cream cuffs
	if c.Room() >= 1 then
		egg(c, "Belly", c.At(0, 0.9, -0.42), 0.76, 0.66, 0.08, SNOW, M.SmoothPlastic)
	end
	boots(c, WOOL, M.Fabric, CREAM)
	-- its pet penguin (in a matching scarf and pom-pom)
	penguin(c, -1.32, -0.12)
	-- a snowball in the other mitten
	if c.Room() >= 1 then
		ball(c, "Snowball", 1.0, 0.86, -0.36, 0.36, SNOW, M.Snow)
	end
	return top
end

local function iceKnight(c: Ctx): number
	-- the closed ice helm with a T visor and a navy brim
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), ICE_PALE, M.Ice)
	K.part(c.Model, "Slit", c.At(0, 2.02, -0.705), c.V(1.12, 0.22, 0.03), NAVY_DARK)
	K.part(c.Model, "SlitDown", c.At(0, 1.76, -0.705), c.V(0.18, 0.36, 0.03), NAVY_DARK)
	K.part(c.Model, "Brim", c.At(0, 2.26, -0.74) * CFrame.Angles(-0.2, 0, 0), c.V(1.68, 0.14, 0.14), NAVY, M.Metal)
	-- a crown band and a crest of three crystals, two swept fins
	if c.Room() >= 1 then
		K.part(c.Model, "HelmBand", c.At(0, 2.66, 0.02), c.V(1.66, 0.16, 1.46), NAVY, M.Metal)
	end
	local top = 2.78
	for i, k in { { -0.34, 0.42 }, { 0.02, 0.66 }, { 0.38, 0.42 } } do
		if c.Room() >= 1 then
			local h = k[2]
			diamond(
				c.Model,
				"Crest" .. i,
				c.At(0, 2.84, k[1]) * CFrame.Angles(0, PI / 2, 0),
				h * c.S,
				h * c.S,
				0.1 * c.S,
				if i == 2 then c.Glow else ICE_CYAN,
				if i == 2 then NEON else M.Glass
			)
			top = math.max(top, 2.84 + h * 0.71)
		end
	end
	for i, side in { -1, 1 } do
		top = math.max(
			top,
			spike(c, "Fin" .. i, Vector3.new(side * 0.82, 2.2, 0.12), Vector3.new(side * 1.24, 3.06, 0.42), 0.38, 0.12, ICE, M.Glass)
		)
	end
	-- crystal pauldrons: navy plates, the boulder and crystal as ice spikes
	iceShoulders(c, 0.85, ICE_CYAN, M.Glass)
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Pauldron" .. i,
				c.At(side * 0.8, 1.48, 0) * CFrame.Angles(0, 0, side * -0.3),
				c.V(0.62, 0.2, 0.66),
				NAVY,
				M.Metal
			)
		end
	end
	-- the knight's cape: deep blue, a snow-fur collar and hem, a glowing clasp
	cape(c, {
		Top = 1.44,
		Bottom = 0.1,
		Width = 1.42,
		Flare = 0.7,
		Z = 0.5,
		Back = 0.3,
		Cloth = rgb(36, 80, 210),
		Hem = SNOW,
		Collar = Vector3.new(1.4, 0.24, 1.04),
		Clasp = c.Glow,
	})
	-- the frost sword in the right fist: an ice blade with a glowing edge
	if c.Room() >= 4 then
		local a, b = T.P(c, 0.92, 0.9, -0.22), T.P(c, 1.08, 2.5, -0.76)
		T.seg(c.Model, "Blade", a, b, 0.26 * c.S, 0.07 * c.S, ICE, M.Glass)
		T.seg(c.Model, "BladeGlow", a, b, 0.07 * c.S, 0.09 * c.S, c.Glow, NEON)
		T.seg(c.Model, "Guard", T.P(c, 0.62, 0.88, -0.16), T.P(c, 1.22, 0.94, -0.3), 0.12 * c.S, 0.12 * c.S, NAVY, M.Metal)
		K.part(c.Model, "Pommel", c.At(0.88, 0.42, -0.06), c.V(0.16, 0.16, 0.16), ICE_CYAN, M.Glass, BALL)
		top = math.max(top, 2.6)
	end
	spike(c, "BladeTip", Vector3.new(1.08, 2.46, -0.76), Vector3.new(1.12, 2.82, -0.88), 0.26, 0.07, ICE, M.Glass)
	-- the kite shield on the left arm with a glowing snowflake and a rim
	if c.Room() >= 3 then
		local shield = c.At(-1.06, 1.0, -0.3) * CFrame.Angles(0, PI / 5, 0)
		K.part(c.Model, "Shield", shield, c.V(0.84, 0.62, 0.12), NAVY, M.Metal)
		diamond(c.Model, "ShieldPoint", shield * CFrame.new(0, -0.3 * c.S, 0), 0.6 * c.S, 0.6 * c.S, 0.11 * c.S, NAVY, M.Metal)
		K.part(c.Model, "ShieldRim", shield * CFrame.new(0, 0.28 * c.S, -0.01 * c.S), c.V(0.9, 0.1, 0.13), ICE_PALE, M.Ice)
		snowflake(c, "ShieldFlake", shield * CFrame.new(0, -0.08 * c.S, -0.075 * c.S), 0.5, 0.07, { c.Glow })
	end
	-- the breastplate (the core in front of it), a belt, armoured boots
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.08, -0.435), c.V(0.94, 0.62, 0.04), ICE_PALE, M.Ice)
	end
	T.redress(c, "Core", c.At(0, 1.1, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.28, 0.28, 0.04), c.Glow, NEON)
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.62, 0), c.V(1.24, 0.12, 0.89), NAVY, M.Metal)
	end
	boots(c, NAVY, M.Metal, nil)
	return top
end

local function blizzardSage(c: Ctx): number
	-- bushy snow brows
	T.redress(c, "Brow", c.At(0, 2.33, -0.66) * CFrame.Angles(-0.25, 0, 0), c.V(1.5, 0.22, 0.3), SNOW, M.Snow)
	-- the deep blue hood with a snow-fur trim, a glowing gem and a tip
	-- drooping down the back
	local hood = rgb(40, 58, 150)
	K.part(c.Model, "Hood", c.At(0, 2.15, 0.22), c.V(1.74, 1.3, 1.04), hood, M.Fabric)
	K.part(c.Model, "HoodTrim", c.At(0, 2.8, -0.32), c.V(1.9, 0.24, 0.24), SNOW, M.Fabric)
	for i, side in { -1, 1 } do
		K.part(c.Model, "HoodSide" .. i, c.At(side * 0.89, 2.14, -0.32), c.V(0.24, 1.28, 0.24), SNOW, M.Fabric)
	end
	diamond(c.Model, "HoodGem", c.At(0, 2.8, -0.45), 0.22 * c.S, 0.22 * c.S, 0.06 * c.S, c.Glow, NEON)
	spike(c, "HoodTip", Vector3.new(0, 2.66, 0.72), Vector3.new(0.1, 1.86, 1.3), 0.6, 0.12, hood, M.Fabric)
	-- its own snow cloud floating over its head, snowflakes falling from it
	local cloud: { { number } } = {
		{ 0, 3.52, 0.05, 0.82 },
		{ -0.5, 3.4, 0.0, 0.62 },
		{ 0.52, 3.42, 0.02, 0.66 },
		{ 0.12, 3.74, 0.24, 0.6 },
		{ -0.24, 3.36, -0.26, 0.5 },
	}
	local top = 2.92
	for i, k in cloud do
		if c.Room() < 1 then
			break
		end
		ball(c, "Cloud" .. i, k[1], k[2], k[3], k[4], if i == 2 then rgb(226, 236, 250) else SNOW, M.SmoothPlastic)
		top = math.max(top, k[2] + k[4] / 2)
	end
	for i, k in { { -0.62, 3.06, -0.4 }, { 0.3, 3.08, -0.5 }, { 0.7, 2.98, -0.3 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "Snowflake" .. i, c.At(k[1], k[2], k[3]), 0.13 * c.S, 0.13 * c.S, 0.04 * c.S, SPARKLE, NEON)
		end
	end
	-- the beard: a mustache, a snowy chin and icicles hanging from it
	if c.Room() >= 3 then
		for i, side in { -1, 1 } do
			egg(c, "Mustache" .. i, c.At(side * 0.2, 1.76, -0.7) * CFrame.Angles(0, 0, side * 0.3), 0.48, 0.2, 0.16, SNOW, M.Snow)
		end
		egg(c, "Beard", c.At(0, 1.5, -0.7), 0.9, 0.56, 0.22, SNOW, M.Snow)
	end
	for i, k in { { -0.24, 0.22, 1.0 }, { 0, 0.28, 0.74 }, { 0.24, 0.22, 1.0 } } do
		spike(c, "Icicle" .. i, Vector3.new(k[1], 1.36, -0.76), Vector3.new(k[1] * 0.9, k[3], -0.78), k[2], 0.14, ICE_PALE, M.Glass)
	end
	-- the staff with a crystal snowflake in the right fist
	if c.Room() >= 2 then
		T.seg(c.Model, "Staff", T.P(c, 0.94, 0.05, -0.22), T.P(c, 0.94, 2.62, -0.22), 0.12 * c.S, 0.12 * c.S, ICE_PALE, M.Glass)
		K.part(c.Model, "StaffOrb", c.At(0.94, 2.86, -0.22), c.V(0.2, 0.2, 0.2), SPARKLE, NEON, BALL)
		top = math.max(top, 3.12)
	end
	snowflake(c, "StaffFlake", c.At(0.94, 2.86, -0.22), 0.56, 0.07, { c.Glow })
	-- the long cape: deep blue, a snow mantle, a glowing hem and clasp
	cape(c, {
		Top = 1.44,
		Bottom = 0.06,
		Width = 1.44,
		Flare = 0.55,
		Z = 0.5,
		Back = 0.28,
		Cloth = NAVY,
		Hem = c.Glow,
		HemMaterial = NEON,
		Collar = Vector3.new(1.46, 0.26, 1.06),
		Clasp = c.Glow,
	})
	-- the robe with a glowing hem
	if c.Room() >= 2 then
		K.part(c.Model, "Robe", c.At(0, 0.5, 0), c.V(1.3, 0.42, 0.94), NAVY, M.Fabric)
		K.part(c.Model, "RobeHem", c.At(0, 0.32, 0), c.V(1.32, 0.06, 0.96), c.Glow, NEON)
	end
	T.redress(c, "Core", c.At(0, 1.12, -0.5) * CFrame.Angles(0, 0, PI / 4), c.V(0.2, 0.2, 0.06), c.Glow, NEON)
	-- frosty shoulders, a glowing orb in the left hand
	iceShoulders(c, 0.6, ICE_PALE, M.Glass)
	if c.Room() >= 1 then
		ball(c, "HandOrb", -0.98, 0.98, -0.3, 0.32, c.Glow, NEON)
	end
	return top
end

-- a crown of `n` icicles round an ice band; returns the top
local function iceCrown(c: Ctx, n: number, tallest: number, y: number, bandColor: Color3, colors: { Color3 }): number
	-- (a box band hugging the top of the square head)
	K.part(c.Model, "CrownBand", c.At(0, y - 0.1, 0.0), c.V(1.64, 0.26, 1.44), bandColor, M.Metal)
	local top = y
	for i = 1, n do
		local t = (i - 1) / (n - 1) * 2 - 1 -- -1 .. 1 across the front
		local a = t * 1.25
		local h = tallest * (1 - 0.38 * math.abs(t))
		local out = Vector3.new(math.sin(a), 0, -math.cos(a))
		local base = Vector3.new(out.X * 0.68, y, out.Z * 0.56)
		local tip = base + Vector3.new(0, h, 0) + out * 0.16
		local color = colors[(i - 1) % #colors + 1]
		top = math.max(
			top,
			spike(
				c,
				"CrownSpike" .. i,
				base,
				tip,
				0.34,
				0.1,
				color,
				if color == c.Glow then NEON else M.Glass,
				Vector3.new(-out.Z, 0, out.X)
			)
		)
	end
	return top
end

local function polarTitan(c: Ctx): number
	snowBrow(c, 1.56, 0.26)
	local ivory = rgb(252, 244, 226)
	-- the horned ice helm: a dome, a navy band with a gem, a nose guard,
	-- great curved horns, three little crown spikes on the front
	egg(c, "HelmDome", c.At(0, 2.74, 0.02), 1.64, 0.74, 1.44, ICE_PALE, M.Ice)
	K.part(c.Model, "HelmBand", c.At(0, 2.62, 0.02), c.V(1.66, 0.22, 1.46), NAVY, M.Metal)
	K.part(c.Model, "NoseGuard", c.At(0, 2.24, -0.7), c.V(0.14, 0.5, 0.06), NAVY, M.Metal)
	diamond(c.Model, "HelmGem", c.At(0, 2.64, -0.745), 0.2 * c.S, 0.2 * c.S, 0.05 * c.S, c.Glow, NEON)
	local top = 3.1
	for i, side in { -1, 1 } do
		if c.Room() >= 3 then
			T.seg(
				c.Model,
				"Horn" .. i,
				T.P(c, side * 0.72, 2.62, 0.04),
				T.P(c, side * 1.2, 2.86, 0.0),
				0.26 * c.S,
				0.26 * c.S,
				ivory,
				M.SmoothPlastic
			)
			top = math.max(
				top,
				spike(
					c,
					"HornTip" .. i,
					Vector3.new(side * 1.12, 2.84, 0.0),
					Vector3.new(side * 1.36, 3.6, -0.06),
					0.24,
					0.2,
					ivory,
					M.SmoothPlastic
				)
			)
		end
	end
	for i, x in { -0.36, 0, 0.36 } do
		if c.Room() >= 1 then
			top = math.max(
				top,
				spike(
					c,
					"CrownSpike" .. i,
					Vector3.new(x, 2.98, -0.5),
					Vector3.new(x * 1.1, if x == 0 then 3.5 else 3.3, -0.56),
					0.24,
					0.08,
					if x == 0 then ICE_CYAN else ICE_PALE,
					M.Glass
				)
			)
		end
	end
	-- two great ivory tusks curving out of the jaw
	for i, side in { -1, 1 } do
		if c.Room() >= 2 then
			T.seg(
				c.Model,
				"Tusk" .. i,
				T.P(c, side * 0.3, 1.72, -0.68),
				T.P(c, side * 0.5, 1.3, -0.94),
				0.16 * c.S,
				0.16 * c.S,
				ivory,
				M.SmoothPlastic
			)
			spike(
				c,
				"TuskTip" .. i,
				Vector3.new(side * 0.5, 1.28, -0.94),
				Vector3.new(side * 0.64, 1.66, -1.2),
				0.16,
				0.14,
				ivory,
				M.SmoothPlastic
			)
		end
	end
	-- the royal fur cape: deep blue with an ermine collar and hem
	cape(c, {
		Top = 1.44,
		Bottom = 0.02,
		Width = 1.6,
		Flare = 0.75,
		Z = 0.52,
		Back = 0.32,
		Cloth = NAVY,
		Hem = SNOW,
		Collar = Vector3.new(1.72, 0.42, 1.24),
		Clasp = c.Glow,
	})
	-- huge ice crystal shoulders with snow caps and a shard each
	iceShoulders(c, 1.2, ICE, M.Glass)
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			gcrystal(c, "ShoulderShard" .. i, Vector3.new(side * 0.98, 1.5, -0.12), 0.24, 0.62, -0.2, -side * 0.95, ICE_CYAN, M.Glass)
		end
	end
	-- the ice war axe in the right fist: a haft, a glowing double blade, a spike
	if c.Room() >= 4 then
		T.seg(c.Model, "AxeHaft", T.P(c, 0.92, 0.3, -0.3), T.P(c, 1.0, 2.5, -0.46), 0.12 * c.S, 0.12 * c.S, rgb(120, 84, 60), M.Wood)
		K.part(c.Model, "AxeHead", c.At(1.0, 2.14, -0.44), c.V(0.24, 0.34, 0.22), NAVY, M.Metal)
		diamond(c.Model, "AxeGlow", c.At(1.4, 2.14, -0.41), 0.86 * c.S, 0.86 * c.S, 0.06 * c.S, rgb(40, 150, 255), NEON)
		diamond(c.Model, "AxeBlade", c.At(1.35, 2.14, -0.47), 0.76 * c.S, 0.76 * c.S, 0.08 * c.S, ICE_PALE, M.Ice)
		top = math.max(top, 2.55)
	end
	spike(c, "AxeSpike", Vector3.new(0.96, 2.14, -0.44), Vector3.new(0.6, 2.24, -0.44), 0.2, 0.1, ICE_PALE, M.Glass)
	-- frost fists with navy bracers, fur boots
	for i, side in { -1, 1 } do
		T.recolor(c, "Fist" .. i, ICE_PALE, M.Glass)
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Bracer" .. i,
				c.At(side * 0.84, 0.94, -0.02) * CFrame.Angles(0, 0, side * 0.1),
				c.V(0.5, 0.14, 0.56),
				NAVY,
				M.Metal
			)
		end
	end
	boots(c, rgb(120, 150, 200), M.Fabric, SNOW)
	-- a snowflake on the chest, a belt with an ice buckle
	T.redress(c, "Core", c.At(0, 1.02, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.16, 0.16, 0.04), SPARKLE, NEON)
	snowflake(c, "Flake", c.At(0, 1.02, -0.45), 0.56, 0.08, { c.Glow })
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.6, 0), c.V(1.24, 0.12, 0.89), NAVY, M.Metal)
	end
	if c.Room() >= 1 then
		diamond(c.Model, "Buckle", c.At(0, 0.6, -0.46), 0.2 * c.S, 0.2 * c.S, 0.05 * c.S, ICE_CYAN, M.Glass)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, rgb(200, 245, 255), 5, 0.2)
	end
	return top
end

local function auroraColossus(c: Ctx): number
	snowBrow(c, 1.4, 0.16)
	-- the ice crown, its middle icicle glowing
	local top = iceCrown(c, 5, 1.0, 2.76, NAVY, { ICE_PALE, ICE_CYAN, c.Glow, ICE_CYAN, ICE_PALE })
	diamond(c.Model, "CrownGem", c.At(0, 2.66, -0.74), 0.24 * c.S, 0.24 * c.S, 0.05 * c.S, AURORA_VIOLET, NEON)
	-- the northern lights: three ribbon arcs round the head
	local halo = Vector3.new(0, 2.3, 0.62)
	arc(c, "AuroraGreen", halo, 1.25, -1.3, 1.3, 3, 0.2, AURORA_GREEN)
	arc(c, "AuroraCyan", halo, 1.5, -1.2, 1.2, 3, 0.18, AURORA_CYAN)
	arc(c, "AuroraViolet", halo, 1.76, -1.1, 1.1, 3, 0.16, AURORA_VIOLET)
	top = math.max(top, halo.Y + 1.76 + 0.1)
	-- the aurora cape: deep violet-blue, a snow-fur collar, a glowing green hem
	cape(c, {
		Top = 1.44,
		Bottom = 0.04,
		Width = 1.56,
		Flare = 0.8,
		Z = 0.5,
		Back = 0.34,
		Cloth = rgb(90, 60, 210),
		Hem = AURORA_GREEN,
		HemMaterial = NEON,
		Collar = Vector3.new(1.7, 0.36, 1.2),
		Clasp = AURORA_CYAN,
	})
	-- crystal wings behind the cape: three blades each, pale ice into violet
	local R = Vector3.new(0.3, 1.36, 0.72)
	local feathers: { { any } } = {
		{ Vector3.new(1.9, 3.5, 0.98), Vector3.new(1.0, 2.6, 0.86), rgb(200, 244, 255) },
		{ Vector3.new(2.45, 2.6, 1.02), Vector3.new(1.3, 1.8, 0.9), rgb(140, 214, 255) },
		{ Vector3.new(2.1, 1.3, 0.98), Vector3.new(1.0, 0.86, 0.84), rgb(160, 120, 255) },
	}
	for j, f in feathers do
		for i, side in { -1, 1 } do
			local room = c.Room()
			if room < 1 then
				break
			end
			local m = Vector3.new(side, 1, 1)
			local a, b = R * m, (f[1] :: Vector3) * m
			local p = (f[2] :: Vector3) * m
			T.tri(
				c.Model,
				`Wing{i}_{j}`,
				T.P(c, a.X, a.Y, a.Z),
				T.P(c, b.X, b.Y, b.Z),
				T.P(c, p.X, p.Y, p.Z),
				0.08 * c.S,
				f[3] :: Color3,
				if j == 3 then NEON else M.Ice,
				math.min(room, 2)
			)
		end
	end
	-- crystal armour: an ice breastplate, the aurora snowflake, navy plates
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.02, -0.435), c.V(0.96, 0.6, 0.04), ICE_PALE, M.Glass)
	end
	T.redress(c, "Core", c.At(0, 1.02, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.16, 0.16, 0.04), SPARKLE, NEON)
	snowflake(c, "Flake", c.At(0, 1.02, -0.46), 0.52, 0.08, { AURORA_GREEN, AURORA_CYAN, AURORA_VIOLET })
	iceShoulders(c, 1.1, ICE_CYAN, M.Glass)
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Pauldron" .. i,
				c.At(side * 0.8, 1.48, 0) * CFrame.Angles(0, 0, side * -0.3),
				c.V(0.62, 0.2, 0.66),
				NAVY,
				M.Metal
			)
		end
		if c.Room() >= 1 then
			gcrystal(c, "ShoulderShard" .. i, Vector3.new(side * 0.98, 1.5, -0.1), 0.22, 0.56, -0.2, -side * 1.0, ICE_PALE, M.Glass)
		end
	end
	for i, side in { -1, 1 } do
		T.recolor(c, "Fist" .. i, ICE_PALE, M.Glass)
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Bracer" .. i,
				c.At(side * 0.84, 0.94, -0.02) * CFrame.Angles(0, 0, side * 0.1),
				c.V(0.5, 0.14, 0.56),
				NAVY,
				M.Metal
			)
		end
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.6, 0), c.V(1.24, 0.12, 0.89), NAVY, M.Metal)
	end
	if c.Room() >= 1 then
		diamond(c.Model, "BeltGem", c.At(0, 0.6, -0.46), 0.2 * c.S, 0.2 * c.S, 0.05 * c.S, AURORA_VIOLET, NEON)
	end
	boots(c, NAVY, M.Metal, nil)
	-- the aurora scepter in the right fist: an ice rod, a crystal, a glowing orb
	if c.Room() >= 3 then
		T.seg(c.Model, "Scepter", T.P(c, 0.96, 0.2, -0.36), T.P(c, 1.04, 2.3, -0.56), 0.12 * c.S, 0.12 * c.S, NAVY, M.Metal)
		gcrystal(c, "ScepterCrystal", Vector3.new(1.04, 2.2, -0.56), 0.4, 0.8, 0, 0, ICE_CYAN, M.Ice)
		ball(c, "ScepterOrb", 1.04, 2.6, -0.56, 0.34, AURORA_GREEN, NEON)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, rgb(170, 255, 230), 6, 0.2)
		T.light(body, c.Glow, 8, 1.2)
	end
	return top
end

function FrostTitans.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		IcicleHair = frostling,
		Beanie = glacierCub,
		FrostHelm = iceKnight,
		SnowCloud = blizzardSage,
		IcicleCrown = polarTitan,
		AuroraCrown = auroraColossus,
	}
end

---------------------------------------------------------------- the shard

--[[
	The FROST EGG shard (units: studs, the shard's center at s.Center, the
	front -Z): a sphere below the waist and a tall ellipsoid above it (the
	halves of the opening). Glossy ice, a snow cap on the tip, crystals
	breaking out, the northern lights round the waist, a snowflake emblem,
	an ice stand in a snowdrift.
]]
function FrostTitans.shard(kit: Kit, tools: Tools, s: Shard)
	K, T = kit, tools
	local C = s.Center
	local r = 1.25
	local topCenter = 0.4 * r
	local topHalf = 1.4 * r
	local function at(x: number, y: number, z: number): CFrame
		return C * CFrame.new(x, y, z)
	end
	-- the shell's radius at height y (sphere below 0, the ellipsoid above)
	local function radius(y: number): number
		if y < 0 then
			return math.sqrt(math.max(r * r - y * y, 0))
		end
		local yy = (y - topCenter) / topHalf
		return r * math.sqrt(math.max(1 - yy * yy, 0))
	end
	-- a frame on the shell at height y and angle a (0 = front, + = right):
	-- its -Z (LookVector) points out of the shell
	local function surf(y: number, a: number, lift: number): CFrame
		local rr = radius(y)
		local dx, dz = math.sin(a), -math.cos(a)
		local p = at(dx * rr, y, dz * rr).Position
		local ny = if y < 0 then y / r else (y - topCenter) / (topHalf * topHalf) * r
		local n = C:VectorToWorldSpace(Vector3.new(dx * rr / r, ny, dz * rr / r)).Unit
		return CFrame.lookAt(p + n * lift, p + n * (lift + 1))
	end
	local shellTop = rgb(132, 200, 255)
	local shellLow = rgb(76, 140, 236)

	-- Bottom: the round lower shell, the aurora band, the cracks
	T.ellipsoid(s.Bottom, "Shell", at(0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), shellLow, M.SmoothPlastic)
	K.upright(s.Bottom, "Band", at(0, 0.02, 0), 0.2, 2 * r + 0.08, AURORA_GREEN, NEON)
	K.upright(s.Bottom, "BandViolet", at(0, -0.17, 0), 0.12, 2 * radius(-0.17) + 0.08, AURORA_VIOLET, NEON)
	for i, k in { { -0.5, -0.45, 0.5 }, { 0.55, -0.6, -0.6 }, { 0.05, -0.85, 0.3 } } do
		K.part(s.Bottom, "Crack" .. i, surf(k[2], k[1], 0.02) * CFrame.Angles(0, 0, k[3]), Vector3.new(0.09, 0.6, 0.04), SPARKLE, NEON)
	end
	-- the ice stand in a snowdrift, ringed with little crystals
	K.upright(s.Bottom, "Stand", at(0, -r - 0.12, 0), 0.3, 2.2, ICE_DEEP, M.Glass)
	K.upright(s.Bottom, "StandRim", at(0, -r + 0.06, 0), 0.08, 2.3, SNOW, M.Snow)
	T.ellipsoid(s.Bottom, "Snowdrift", at(0, -r + 0.06, 0), Vector3.new(1.9, 0.5, 1.9), SNOW, M.Snow)
	for i = 1, 6 do
		if s.Room() < 1 then
			break
		end
		local a = (i - 0.5) * PI / 3
		local dx, dz = math.sin(a), -math.cos(a)
		local cf = at(dx * 1.08, -r - 0.02, dz * 1.08) * CFrame.Angles(dz * 0.35, 0, dx * -0.35)
		crystal(s.Bottom, "StandCrystal" .. i, cf * CFrame.new(0, 0.24, 0), 0.22, if i % 2 == 0 then 0.62 else 0.46, ICE_CYAN, M.Glass)
	end
	-- frost spots on the lower shell
	for i, k in { { -0.62, -0.5, 0.18 }, { 0.3, -0.42, 0.14 }, { 0.75, -0.75, 0.12 } } do
		if s.Room() < 1 then
			break
		end
		local cf = surf(k[2], k[1], 0.01) * CFrame.Angles(0, 0, PI / 4)
		K.part(s.Bottom, "Spot" .. i, cf, Vector3.new(k[3] * 2, k[3] * 2, 0.04), SNOW, M.SmoothPlastic)
	end

	-- Top: the tall upper shell
	T.ellipsoid(s.Top, "Shell", at(0, topCenter, 0), Vector3.new(2 * r, 2 * topHalf, 2 * r), shellTop, M.SmoothPlastic)
	K.upright(s.Top, "BandCyan", at(0, 0.2, 0), 0.12, 2 * radius(0.2) + 0.08, AURORA_CYAN, NEON)
	-- the snow cap on the tip, dripping
	local tipY = topCenter + topHalf
	T.ellipsoid(s.Top, "SnowCap", at(0, tipY - 0.3, 0), Vector3.new(1.72, 1.1, 1.72), SNOW, M.Snow)
	for i, k in { { -0.75, 0.62 }, { 0.2, 0.76 }, { 0.95, 0.56 } } do
		if s.Room() < 1 then
			break
		end
		local y = tipY - 0.56
		T.ellipsoid(s.Top, "Drip" .. i, surf(y, k[1], -0.02), Vector3.new(0.34, k[2], 0.3), SNOW, M.Snow)
	end
	-- pointed ice crystals breaking out of the shell (y, angle, base width,
	-- length, glow?): thick triangles leaning up and out
	local up = C.UpVector
	for i, k in
		{
			{ 0.85, 1.3, 0.62, 1.15, 0 },
			{ 0.55, -1.35, 0.56, 1.0, 0 },
			{ 1.45, -0.8, 0.36, 0.62, 1 },
			{ 0.2, 1.95, 0.42, 0.72, 1 },
			{ 1.6, 0.85, 0.32, 0.5, 0 },
			{ -0.45, -1.95, 0.42, 0.66, 0 },
		}
	do
		local room = s.Room()
		if room < 1 then
			break
		end
		local parent = if k[1] < 0 then s.Bottom else s.Top
		local f = surf(k[1], k[2], -0.08)
		local dir = (f.LookVector * 0.7 + up * 0.7).Unit
		local across = f.UpVector * (k[3] / 2)
		local tip = f.Position + dir * k[4]
		local color = if k[5] == 1 then AURORA_CYAN else ICE_PALE
		local material = if k[5] == 1 then NEON else M.Glass
		T.tri(parent, "Ice" .. i, f.Position - across, f.Position + across, tip, 0.2, color, material, math.min(room, 2))
	end
	-- the snowflake emblem on the front: a navy disc, three glowing bars
	if s.Room() >= 5 then
		local e = surf(0.85, 0, 0.02)
		K.part(
			s.Top,
			"EmblemDisc",
			e * CFrame.Angles(0, PI / 2, 0),
			Vector3.new(0.08, 0.92, 0.92),
			NAVY,
			M.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		for i = 1, 3 do
			K.part(
				s.Top,
				"EmblemBar" .. i,
				e * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, 0, (i - 1) * PI / 3),
				Vector3.new(0.1, 0.74, 0.05),
				SPARKLE,
				NEON
			)
		end
		diamond(s.Top, "EmblemGem", e * CFrame.new(0, 0, -0.07), 0.2, 0.2, 0.05, AURORA_CYAN, NEON)
	end
	-- the glossy shine on the upper shell (the egg games' highlight)
	if s.Room() >= 1 then
		local shine =
			T.ellipsoid(s.Top, "Shine", surf(0.95, -0.62, 0.0) * CFrame.Angles(0, 0, -0.35), Vector3.new(0.26, 0.72, 0.05), SPARKLE)
		shine.Transparency = 0.3
	end
	-- a glowing star of frost on the snow cap's tip
	if s.Room() >= 2 then
		local star = at(0, tipY + 0.62, 0)
		diamond(s.Top, "Star", star, 0.5, 0.5, 0.08, SPARKLE, NEON)
		diamond(s.Top, "StarSide", star * CFrame.Angles(0, PI / 2, 0), 0.5, 0.5, 0.08, AURORA_CYAN, NEON)
	end
	-- little ice wings swept up from the sides
	for i, side in { -1, 1 } do
		local room = s.Room()
		if room < 1 then
			break
		end
		T.tri(
			s.Top,
			"Wing" .. i,
			at(side * (r - 0.08), 0.0, 0.25).Position,
			at(side * (r - 0.02), 0.9, 0.25).Position,
			at(side * (r + 1.0), 1.55, 0.45).Position,
			0.1,
			ICE_PALE,
			M.Ice,
			math.min(room, 2)
		)
	end
	-- frost sparkles
	for i, k in { { 1.25, -0.6, 0.16 }, { 0.45, 0.75, 0.13 }, { 1.7, 0.3, 0.12 } } do
		if s.Room() < 1 then
			break
		end
		diamond(s.Top, "Sparkle" .. i, surf(k[1], k[2], 0.01), k[3], k[3], 0.04, SPARKLE, NEON)
	end
	local band = s.Bottom:FindFirstChild("Band")
	if band and band:IsA("BasePart") then
		T.embers(band, rgb(200, 250, 255), 6, 0.22)
	end
end

return FrostTitans
