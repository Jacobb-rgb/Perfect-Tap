--[[
	GALAXY (limited edition, upcoming): the costumes of the set's 6 golems
	and the set's shard (GolemGearLimited explains the contract and the tools).

	  SpaceHelmet   Astro Cadet (Rare): a round glass bubble helmet with an
	                antenna, a jetpack with red fins and two thrusters blasting
	                flame, a control panel, moon boots, a tool pouch, its star
	                flag and a tiny satellite buddy with solar wings
	  Comet         Comet Cub (Rare): a blazing comet crashed on its head,
	                flight goggles, a red aviator scarf streaming back, a
	                short fiery cape, rocket boots with flame jets
	  Orbiters      Orbit Keeper (Epic): a glowing orbit ring of planets round
	                its head, a little sun over it, a constellation on its
	                chest, a brass telescope, a midnight star cloak with a
	                mantle and a star clasp, boots
	  StarHat       Cosmo Wizard (Epic): a tall star-spangled wizard hat, a
	                fluffy beard, a star staff, a spellbook with a floating
	                crystal ball, a long starry cape with a high pointed
	                collar and a glowing clasp, wizard shoes
	  StarCrown     Nova Guardian (Legendary): a gold crown with a nova star
	                and a winged helm, a ring of light behind its head, a star
	                shield, a sword of light, gold armour and greaves, a royal
	                cape with a nova clasp, embers
	  NebulaCrown   Nebula Titan (Mythic): a gold crown under an orbit ring of
	                planets, a nebula orb, a high cosmic collar, nebula wings
	                with glowing edges, a cosmic cape, a sceptre, a galaxy in
	                its chest, gold boots, a nebula cloud at its feet, embers
	                and its own light

	The shard: a GALAXY EGG: a glossy deep-space egg with nebula clouds,
	stars and a shine on its shell, a planet ring with two moons, gold star
	wings with glowing feathers, a gold star emblem, a comet and a little
	rocket zooming past, sparkles, a crystal tip and a gold stand.
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local Galaxy = {}

Galaxy.Faces = {} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local GOLD = rgb(255, 200, 60)
local GOLD_DARK = rgb(200, 140, 40)
local WHITE = rgb(246, 248, 255)
local SUIT = rgb(232, 236, 248)
local CHROME = rgb(196, 204, 222)
local STAR_WHITE = rgb(255, 252, 230)
local STAR_YELLOW = rgb(255, 226, 90)
local SPACE = rgb(22, 14, 58)
local MOON = rgb(206, 204, 226)
local MARS = rgb(236, 92, 64)
local SATURN = rgb(255, 186, 96)
local SATURN_RING = rgb(255, 230, 170)
local EARTH = rgb(70, 170, 255)
local BLUSH = rgb(255, 150, 190)
local FLAME_WHITE = rgb(255, 250, 220)
local FLAME_HOT = rgb(255, 214, 70)
local FLAME = rgb(255, 140, 30)
local EMBER = rgb(230, 60, 40)

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

-- an eight-point star facing -Z of `cf` (two squares, one turned 45 degrees)
local function star(parent: Instance, name: string, cf: CFrame, size: number, thick: number, color: Color3, material: Enum.Material?)
	K.part(parent, name .. "A", cf, Vector3.new(size, size, thick), color, material)
	K.part(parent, name .. "B", cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(size, size, thick), color, material)
end

-- a ball (unscaled golem units)
local function ball(c: Ctx, name: string, x: number, y: number, z: number, d: number, color: Color3, material: Enum.Material?): Part
	return K.part(c.Model, name, c.At(x, y, z), c.V(d, d, d), color, material, BALL)
end

-- a body part re-dressed and re-shaped (free: no new part)
local function reshape(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType)
	local p = c.Model:FindFirstChild(name)
	if p and p:IsA("Part") then
		p.Shape = shape
		p.CFrame = cf
		p.Size = size
		p.Color = color
		p.Material = material
	end
end

--[[
	A ring of `n` straight segments round the center `cf` (world), in its
	XZ plane: radius `r` and thickness `w` in world studs. Stops when `room`
	says the budget ran out. Returns the parts used.
]]
local function ring(
	parent: Instance,
	name: string,
	cf: CFrame,
	r: number,
	n: number,
	w: number,
	color: Color3,
	material: Enum.Material?,
	room: () -> number
): number
	local used = 0
	local reach = 1 + 0.5 * (2 * PI / n) * 0.35 -- a little past the joints
	for i = 1, n do
		if room() < 1 then
			break
		end
		local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
		local p0 = (cf * CFrame.new(math.cos(a0) * r, 0, math.sin(a0) * r)).Position
		local p1 = (cf * CFrame.new(math.cos(a1) * r, 0, math.sin(a1) * r)).Position
		local mid = (p0 + p1) / 2
		T.seg(parent, name .. i, mid + (p0 - mid) * reach, mid + (p1 - mid) * reach, w, w, color, material)
		used += 1
	end
	return used
end

-- a point on a ring (as `ring` lays it out) at angle `a`
local function onRing(cf: CFrame, r: number, a: number): CFrame
	return cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
end

---------------------------------------------------------------- body pieces

-- no stone brow (a cute face): it shrinks into the head
local function noBrow(c: Ctx)
	T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), c.Look.Body, M.Slate)
end

-- a slim brow ridge instead of the heavy stone brow
local function slimBrow(c: Ctx, color: Color3, material: Enum.Material)
	T.redress(c, "Brow", c.At(0, 2.3, -0.64) * CFrame.Angles(-0.25, 0, 0), c.V(1.4, 0.13, 0.22), color, material)
end

-- the shoulders: a cratered moon on the left, a glowing star on the right
local function cosmicShoulders(c: Ctx, moon: Color3, starColor: Color3)
	reshape(c, "Boulder", c.At(-0.66, 1.58, 0.1), c.V(0.5, 0.5, 0.5), moon, M.Slate, BALL)
	T.redress(c, "Crystal", c.At(0.64, 1.64, 0.1) * CFrame.Angles(0, 0, PI / 4), c.V(0.3, 0.3, 0.3), starColor, NEON)
end

-- blush under the eyes, a sparkle in each eye (z: the face's front)
local function cute(c: Ctx, z: number, sparkle: Enum.Material?)
	for i, x in { -0.46, 0.46 } do
		if c.Room() >= 1 then
			K.part(c.Model, "Blush" .. i, c.At(x, 1.8, z - 0.01), c.V(0.2, 0.09, 0.02), BLUSH, M.SmoothPlastic)
		end
	end
	if sparkle and c.Room() >= 2 then
		for i, x in { -0.34, 0.22 } do
			K.part(c.Model, "Sparkle" .. i, c.At(x, 2.07, z - 0.035), c.V(0.08, 0.08, 0.02), Color3.new(1, 1, 1), sparkle)
		end
	end
end

-- a gold belt (with a star buckle when there is room)
local function belt(c: Ctx, color: Color3, buckle: boolean)
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.6, 0), c.V(1.24, 0.12, 0.89), color, M.Foil)
	end
	if buckle and c.Room() >= 1 then
		diamond(c.Model, "Buckle", c.At(0, 0.6, -0.455), 0.18 * c.S, 0.18 * c.S, 0.04 * c.S, STAR_WHITE, M.Foil)
	end
end

--[[
	A CAPE hanging behind the body from the shoulders (z 0.68 at the top,
	`back` at the hem): the cloth, two flares spreading out at the hem
	(right-angled tri() wedges, so they show past the fists from the front),
	a hem trim across the bottom, and (when given) a mantle over the
	shoulders and a clasp under the chin. Added in that order while there is
	room. Returns the cape's frame (the cloth's center, unscaled offsets
	below are in its plane) for decorations on it.
]]
type CapeOpts = {
	Cloth: Color3,
	Flare: Color3?,
	Hem: Color3,
	HemMaterial: Enum.Material?,
	Mantle: Color3?,
	Clasp: Color3?,
	ClaspMaterial: Enum.Material?,
	Bottom: number?, -- the hem's height (unscaled)
	Width: number?,
	Spread: number?, -- how far each flare reaches past the cloth
	Back: number?, -- the hem's z
	Material: Enum.Material?,
}
local function cape(c: Ctx, o: CapeOpts): (CFrame, number, number)
	local top, bottom = 1.42, o.Bottom or 0.12
	local zTop, zBot = 0.69, o.Back or 0.92
	local width, spread = o.Width or 1.9, o.Spread or 0.42
	local material = o.Material or M.Fabric
	local len = math.sqrt((top - bottom) ^ 2 + (zBot - zTop) ^ 2)
	local tilt = math.atan2(zBot - zTop, top - bottom)
	local frame = c.At(0, (top + bottom) / 2, (zTop + zBot) / 2) * CFrame.Angles(-tilt, 0, 0)
	local function on(u: number, v: number, w: number): Vector3
		return (frame * CFrame.new(u * c.S, v * c.S, w * c.S)).Position
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Cape", frame, c.V(width, len, 0.06), o.Cloth, material)
	end
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		local x = side * width / 2
		T.tri(
			c.Model,
			"CapeFlare" .. i,
			on(x, len * 0.12, -0.005),
			on(x, -len / 2, -0.005),
			on(x + side * spread, -len / 2, -0.005),
			0.06 * c.S,
			o.Flare or o.Cloth,
			material,
			1
		)
	end
	if c.Room() >= 1 then
		K.part(
			c.Model,
			"CapeHem",
			frame * CFrame.new(0, (-len / 2 + 0.05) * c.S, -0.01 * c.S),
			c.V(width + 2 * spread, 0.1, 0.09),
			o.Hem,
			o.HemMaterial or M.Foil
		)
	end
	if o.Mantle and c.Room() >= 1 then
		K.part(c.Model, "Mantle", c.At(0, 1.47, 0.24), c.V(1.96, 0.14, 0.98), o.Mantle, material)
	end
	if o.Clasp and c.Room() >= 1 then
		diamond(c.Model, "Clasp", c.At(0, 1.36, -0.46), 0.2 * c.S, 0.2 * c.S, 0.06 * c.S, o.Clasp, o.ClaspMaterial or M.Foil)
	end
	return frame, width, len
end

-- chunky boots over the stone legs (a sole in `sole` when there is room)
local function boots(c: Ctx, color: Color3, material: Enum.Material, toe: Color3?)
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			K.part(c.Model, "Boot" .. i, c.At(x, 0.16, -0.04), c.V(0.52, 0.32, 0.64), color, material)
		end
	end
	if toe then
		for i, x in { -0.3, 0.3 } do
			if c.Room() >= 1 then
				K.part(c.Model, "Toe" .. i, c.At(x, 0.1, -0.33), c.V(0.54, 0.2, 0.12), toe, M.Foil)
			end
		end
	end
end

---------------------------------------------------------------- the costumes

local function astroCadet(c: Ctx): number
	noBrow(c)
	-- a slightly smaller, rounder head so the bubble helmet hugs it
	T.redress(c, "Head", c.At(0, 2.04, 0), c.V(1.36, 1.14, 1.16), c.Look.Body, M.SmoothPlastic)
	for i, x in { -0.27, 0.27 } do
		T.redress(c, "Eye" .. i, c.At(x, 2.0, -0.59), c.V(0.27, 0.3, 0.04), c.Glow, NEON)
	end
	-- shoulder pads in the trim
	for i, name in { "Boulder", "Crystal" } do
		local side = if i == 1 then -1 else 1
		reshape(c, name, c.At(side * 0.8, 1.42, 0), c.V(0.46, 0.2, 0.58), c.Look.Trim, M.SmoothPlastic, Enum.PartType.Block)
	end
	-- white gloves and the suit's control panel (the core is its middle button)
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, WHITE, M.SmoothPlastic)
	end
	T.redress(c, "Core", c.At(0, 1.02, -0.47), c.V(0.12, 0.12, 0.04), FLAME_HOT, NEON)
	-- the glass bubble helmet on its collar
	local bubble = T.ellipsoid(c.Model, "Helmet", c.At(0, 2.08, -0.02), c.V(2.22, 2.0, 2.12), rgb(200, 236, 255), M.Glass)
	bubble.Transparency = 0.66
	K.upright(c.Model, "Collar", c.At(0, 1.47, 0), 0.22 * c.S, 1.84 * c.S, SUIT, M.SmoothPlastic)
	-- a glossy shine on the glass
	local shine =
		T.ellipsoid(c.Model, "Shine", c.At(-0.5, 2.62, -0.62) * CFrame.Angles(0.5, 0.6, 0.5), c.V(0.5, 0.24, 0.08), WHITE, M.SmoothPlastic)
	shine.Transparency = 0.35
	local top = 3.08
	-- the antenna with its glowing tip
	if c.Room() >= 2 then
		T.seg(c.Model, "Antenna", T.P(c, 0.4, 2.95, 0.02), T.P(c, 0.52, 3.42, 0.06), 0.06 * c.S, 0.06 * c.S, CHROME, M.Metal)
		ball(c, "AntennaTip", 0.53, 3.48, 0.06, 0.2, c.Glow, NEON)
		top = 3.58
	end
	-- the backpack with two thrusters blasting flame
	if c.Room() >= 1 then
		K.part(c.Model, "Backpack", c.At(0, 1.05, 0.62), c.V(1.06, 0.86, 0.42), SUIT, M.SmoothPlastic)
	end
	for i, x in { -0.28, 0.28 } do
		if c.Room() >= 2 then
			K.upright(c.Model, "Thruster" .. i, c.At(x, 0.54, 0.66), 0.2 * c.S, 0.3 * c.S, CHROME, M.Metal)
			T.ellipsoid(c.Model, "Thrust" .. i, c.At(x, 0.28, 0.66), c.V(0.22, 0.42, 0.22), FLAME_HOT, NEON)
		end
	end
	-- the control panel: a plate and two more buttons
	if c.Room() >= 3 then
		K.part(c.Model, "Panel", c.At(0, 1.02, -0.44), c.V(0.62, 0.36, 0.05), c.Look.Trim, M.SmoothPlastic)
		K.part(c.Model, "ButtonL", c.At(-0.18, 1.02, -0.47), c.V(0.12, 0.12, 0.04), rgb(255, 70, 90), NEON)
		K.part(c.Model, "ButtonR", c.At(0.18, 1.02, -0.47), c.V(0.12, 0.12, 0.04), rgb(90, 255, 140), NEON)
	end
	belt(c, c.Look.Trim, false)
	-- its own flag on the backpack: a pole, a navy flag, a gold star
	if c.Room() >= 3 then
		T.seg(c.Model, "FlagPole", T.P(c, -0.42, 1.3, 0.78), T.P(c, -0.42, 2.9, 0.84), 0.05 * c.S, 0.05 * c.S, CHROME, M.Metal)
		K.part(c.Model, "Flag", c.At(-0.7, 2.7, 0.84), c.V(0.52, 0.34, 0.03), rgb(40, 50, 140), M.Fabric)
		diamond(c.Model, "FlagStar", c.At(-0.7, 2.7, 0.82), 0.16 * c.S, 0.16 * c.S, 0.03 * c.S, GOLD, M.Foil)
	end
	-- a gold star badge on the left shoulder pad
	if c.Room() >= 2 then
		star(c.Model, "Badge", c.At(-0.8, 1.42, -0.3), 0.2 * c.S, 0.04 * c.S, GOLD, M.Foil)
	end
	cute(c, -0.58, M.SmoothPlastic)
	-- chunky white moon boots with navy soles
	boots(c, WHITE, M.SmoothPlastic, nil)
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			K.part(c.Model, "Sole" .. i, c.At(x, 0.04, -0.04), c.V(0.56, 0.08, 0.68), c.Look.Trim, M.SmoothPlastic)
		end
	end
	-- red fins on the jetpack
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		local x = side * 0.53
		T.tri(
			c.Model,
			"Fin" .. i,
			T.P(c, x, 1.32, 0.72),
			T.P(c, x, 0.66, 0.72),
			T.P(c, side * 0.9, 0.66, 0.72),
			0.06 * c.S,
			MARS,
			M.SmoothPlastic,
			1
		)
	end
	-- a tiny satellite buddy orbiting over its shoulder: gold body, blue solar wings
	if c.Room() >= 3 then
		local sat = c.At(1.3, 2.86, -0.2) * CFrame.Angles(0.3, 0.5, 0.35)
		K.part(c.Model, "Satellite", sat, c.V(0.26, 0.26, 0.3), GOLD, M.Foil)
		K.part(c.Model, "SolarL", sat * CFrame.new(-0.3 * c.S, 0, 0), c.V(0.34, 0.2, 0.03), rgb(60, 110, 230), M.SmoothPlastic)
		K.part(c.Model, "SolarR", sat * CFrame.new(0.3 * c.S, 0, 0), c.V(0.34, 0.2, 0.03), rgb(60, 110, 230), M.SmoothPlastic)
	end
	-- a tool pouch on the belt
	if c.Room() >= 1 then
		K.part(c.Model, "Pouch", c.At(-0.42, 0.56, -0.47), c.V(0.28, 0.24, 0.12), c.Look.Trim, M.SmoothPlastic)
	end
	return top
end

local function cometCub(c: Ctx): number
	-- flight goggles pushed up on the forehead (the brow is their strap)
	T.redress(c, "Brow", c.At(0, 2.44, 0), c.V(1.56, 0.2, 1.36), rgb(90, 50, 30), M.Fabric)
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 2 then
			K.facing(c.Model, "GoggleRim" .. i, c.At(x, 2.46, -0.7), 0.12 * c.S, 0.44 * c.S, GOLD_DARK, M.Metal)
			local lens = K.facing(c.Model, "Goggle" .. i, c.At(x, 2.46, -0.76), 0.04 * c.S, 0.32 * c.S, rgb(120, 230, 255), M.Glass)
			lens.Transparency = 0.15
		end
	end
	-- meteor rock shoulders: a charred boulder, a burning crystal
	T.recolor(c, "Boulder", rgb(70, 46, 40), M.Basalt)
	T.recolor(c, "Crystal", FLAME, NEON)
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, rgb(90, 56, 44), M.Basalt)
	end
	-- the comet: a white-hot core in a yellow glow on the head
	local head = Vector3.new(0.18, 3.0, -0.18)
	ball(c, "CometCore", head.X, head.Y, head.Z, 0.6, FLAME_WHITE, NEON)
	local coma = T.ellipsoid(c.Model, "Coma", c.At(head.X, head.Y, head.Z), c.V(0.96, 0.92, 0.96), FLAME_HOT, NEON)
	coma.Transparency = 0.45
	-- its fiery tail swooshing up and back, hot to cool
	local tail: { { any } } = {
		{ Vector3.new(0.02, 3.22, 0.22), 0.86, FLAME_HOT, 0.15 },
		{ Vector3.new(-0.22, 3.52, 0.6), 0.74, FLAME, 0.2 },
		{ Vector3.new(-0.48, 3.86, 0.94), 0.58, rgb(255, 104, 34), 0.28 },
		{ Vector3.new(-0.72, 4.18, 1.22), 0.42, EMBER, 0.36 },
	}
	local top = head.Y + 0.48
	local prev = head
	for i, k in tail do
		if c.Room() < 1 then
			break
		end
		local p, d = k[1] :: Vector3, k[2] :: number
		local cf = CFrame.lookAt(T.P(c, prev.X, prev.Y, prev.Z), T.P(c, p.X, p.Y, p.Z))
		local at = cf.Rotation + T.P(c, p.X, p.Y, p.Z)
		local blob =
			T.ellipsoid(c.Model, "Tail" .. i, at, c.V(d, d * 0.9, d * 1.6), k[3] :: Color3, if i < 4 then NEON else M.SmoothPlastic)
		blob.Transparency = k[4] :: number
		top = math.max(top, p.Y + d * 0.5)
		prev = p
	end
	-- bright streaks flying off the tail
	for i, k in { { 0.42, 3.1, 0.1, 0.12, 3.9, 0.9 }, { -0.12, 2.96, 0.3, -0.62, 3.6, 1.2 } } do
		if c.Room() < 1 then
			break
		end
		T.seg(c.Model, "Streak" .. i, T.P(c, k[1], k[2], k[3]), T.P(c, k[4], k[5], k[6]), 0.05 * c.S, 0.05 * c.S, FLAME_WHITE, NEON)
	end
	-- sparks round the comet
	for i, k in { { 0.82, 3.42, -0.1, 0.18 }, { -0.66, 3.2, -0.2, 0.14 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "Spark" .. i, c.At(k[1], k[2], k[3]), k[4] * c.S, k[4] * c.S, 0.04 * c.S, STAR_YELLOW, NEON)
		end
	end
	-- two little meteors tagging along
	for i, k in { { -0.9, 2.86, 0.1, 0.26 }, { 1.0, 2.56, 0.2, 0.2 } } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Meteor" .. i,
				c.At(k[1], k[2], k[3]) * CFrame.Angles(0.5, 0.7, 0.3),
				c.V(k[4], k[4], k[4]),
				rgb(110, 72, 60),
				M.Basalt
			)
		end
	end
	-- meteor cracks glowing in its body
	for i, k in { { -0.3, 1.18, -0.43, 0.6, 0.3 }, { 0.34, 0.78, -0.43, -0.5, 0.26 } } do
		if c.Room() >= 1 then
			K.part(c.Model, "Crack" .. i, c.At(k[1], k[2], k[3]) * CFrame.Angles(0, 0, k[4]), c.V(0.06, k[5], 0.03), FLAME_HOT, NEON)
		end
	end
	-- a pale belly plate with the core in it
	if c.Room() >= 1 then
		K.part(c.Model, "Belly", c.At(0, 0.9, -0.432), c.V(0.64, 0.52, 0.03), rgb(255, 214, 160), M.SmoothPlastic)
	end
	T.redress(c, "Core", c.At(0, 0.92, -0.46) * CFrame.Angles(0, 0, PI / 4), c.V(0.26, 0.26, 0.04), c.Glow, NEON)
	cute(c, -0.65, nil)
	-- a red aviator scarf, its ends streaming back in the comet's wind
	local scarf, scarfEnd = rgb(220, 44, 50), rgb(255, 110, 40)
	if c.Room() >= 1 then
		K.part(c.Model, "Scarf", c.At(0, 1.42, 0.02), c.V(1.3, 0.2, 0.96), scarf, M.Fabric)
	end
	if c.Room() >= 2 then
		T.seg(c.Model, "ScarfEnd1", T.P(c, -0.3, 1.42, 0.5), T.P(c, -0.86, 1.5, 1.04), 0.06 * c.S, 0.3 * c.S, scarf, M.Fabric)
		T.seg(c.Model, "ScarfEnd2", T.P(c, -0.86, 1.5, 1.04), T.P(c, -1.36, 1.74, 1.3), 0.06 * c.S, 0.24 * c.S, scarfEnd, M.Fabric)
	end
	-- rocket boots with little jets of flame at the heels
	boots(c, rgb(84, 84, 104), M.Metal, nil)
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			T.ellipsoid(c.Model, "Jet" .. i, c.At(x, 0.16, 0.44), c.V(0.22, 0.22, 0.34), FLAME_HOT, NEON)
		end
	end
	-- a short fiery cape with a gold hem
	cape(c, { Cloth = rgb(200, 50, 40), Flare = FLAME, Hem = GOLD, Bottom = 0.36, Width = 1.8, Spread = 0.4, Back = 0.88 })
	return top
end

local function orbitKeeper(c: Ctx): number
	slimBrow(c, c.Look.Trim, M.Slate)
	cosmicShoulders(c, MOON, STAR_YELLOW)
	-- the orbit ring round the head, tipped to the right
	local center = c.At(0, 2.8, 0) * CFrame.Angles(-0.14, 0, 0.26)
	local r = 1.38 * c.S
	ring(c.Model, "Orbit", center, r, 10, 0.09 * c.S, rgb(120, 240, 255), NEON, c.Room)
	-- what rides the ring: a ringed planet, a red planet, a cratered moon
	if c.Room() >= 2 then
		local at = onRing(center, r, PI * 0.82)
		K.part(c.Model, "Saturn", at, c.V(0.5, 0.5, 0.5), SATURN, M.SmoothPlastic, BALL)
		K.upright(c.Model, "SaturnRing", at * CFrame.Angles(0.35, 0, -0.3), 0.04 * c.S, 0.86 * c.S, SATURN_RING, M.SmoothPlastic)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Mars", onRing(center, r, PI * 0.18), c.V(0.36, 0.36, 0.36), MARS, M.SmoothPlastic, BALL)
	end
	if c.Room() >= 2 then
		local at = onRing(center, r, PI * 1.5)
		K.part(c.Model, "Moon", at, c.V(0.4, 0.4, 0.4), EARTH, M.SmoothPlastic, BALL)
		K.part(
			c.Model,
			"MoonSpot",
			at * CFrame.new(-0.06 * c.S, 0.07 * c.S, -0.13 * c.S),
			c.V(0.16, 0.16, 0.16),
			rgb(110, 220, 120),
			M.SmoothPlastic,
			BALL
		)
	end
	-- a little sun hovering over the head
	local top = 3.0
	if c.Room() >= 2 then
		ball(c, "Sun", 0, 3.22, 0, 0.42, STAR_YELLOW, NEON)
		local glow = T.ellipsoid(c.Model, "SunGlow", c.At(0, 3.22, 0), c.V(0.7, 0.7, 0.7), FLAME_HOT, M.SmoothPlastic)
		glow.Transparency = 0.6
		top = 3.57
	end
	-- a constellation on the chest: three stars and the lines between them
	local dots = { Vector3.new(-0.3, 1.24, -0.44), Vector3.new(0.06, 1.0, -0.44), Vector3.new(0.32, 1.26, -0.44) }
	if c.Room() >= 2 then
		for i = 1, 2 do
			local a, b = dots[i], dots[i + 1]
			T.seg(
				c.Model,
				"Line" .. i,
				T.P(c, a.X, a.Y, a.Z + 0.01),
				T.P(c, b.X, b.Y, b.Z + 0.01),
				0.03 * c.S,
				0.02 * c.S,
				rgb(200, 220, 255)
			)
		end
	end
	for i, p in dots do
		if c.Room() >= 1 then
			diamond(c.Model, "Dot" .. i, c.At(p.X, p.Y, p.Z - 0.02), 0.13 * c.S, 0.13 * c.S, 0.03 * c.S, STAR_WHITE, NEON)
		end
	end
	T.redress(c, "Core", c.At(0, 0.78, -0.44) * CFrame.Angles(0, 0, PI / 4), c.V(0.2, 0.2, 0.05), c.Glow, NEON)
	-- a brass telescope in the right fist
	if c.Room() >= 2 then
		local a, b = T.P(c, 0.9, 0.62, 0.1), T.P(c, 1.1, 1.5, -0.55)
		T.seg(c.Model, "Telescope", a, b, 0.2 * c.S, 0.2 * c.S, GOLD_DARK, M.Metal)
		T.seg(c.Model, "TelescopeLens", b, b + (b - a).Unit * 0.3 * c.S, 0.28 * c.S, 0.28 * c.S, GOLD, M.Foil)
	end
	belt(c, rgb(80, 40, 150), true)
	cute(c, -0.65, M.SmoothPlastic)
	-- the astronomer's star cloak: midnight cloth, silver hem, a purple
	-- mantle and a star clasp, stars glowing on its flares
	local frame, width, len = cape(c, {
		Cloth = rgb(30, 26, 92),
		Hem = rgb(200, 214, 255),
		Mantle = c.Look.Trim,
		Clasp = STAR_YELLOW,
		Width = 1.9,
		Spread = 0.46,
	})
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			local at = frame * CFrame.new(side * (width / 2 + 0.14) * c.S, -len * 0.36 * c.S, -0.05 * c.S)
			diamond(c.Model, "CapeStar" .. i, at, 0.14 * c.S, 0.14 * c.S, 0.03 * c.S, STAR_WHITE, NEON)
		end
	end
	boots(c, rgb(40, 30, 90), M.SmoothPlastic, nil)
	return top
end

local function cosmoWizard(c: Ctx): number
	local hat = rgb(96, 54, 200)
	local hatDark = rgb(64, 34, 150)
	-- fluffy white brows, beard and moustache
	T.redress(c, "Brow", c.At(0, 2.3, -0.66) * CFrame.Angles(-0.2, 0, 0), c.V(1.3, 0.16, 0.18), WHITE, M.Fabric)
	T.ellipsoid(c.Model, "Beard", c.At(0, 1.56, -0.66), c.V(1.04, 0.92, 0.4), WHITE, M.Fabric)
	cosmicShoulders(c, MOON, c.Glow)
	-- the hat: brim, gold band, a stepped cone, a bent tip, a star on it
	K.upright(c.Model, "Brim", c.At(0, 2.74, 0), 0.1 * c.S, 2.1 * c.S, hatDark, M.Fabric)
	K.upright(c.Model, "HatBand", c.At(0, 2.88, 0), 0.18 * c.S, 1.36 * c.S, GOLD, M.Foil)
	local cone = { { 0, 2.98, 0.38, 1.3 }, { 0.04, 3.32, 0.34, 1.0 }, { 0.1, 3.62, 0.3, 0.72 }, { 0.18, 3.88, 0.26, 0.46 } }
	for i, k in cone do
		if c.Room() >= 1 then
			K.upright(c.Model, "Hat" .. i, c.At(k[1], k[2], 0.02 * i), k[3] * c.S, k[4] * c.S, hat, M.Fabric)
		end
	end
	local top = 4.05
	if c.Room() >= 1 then
		T.seg(c.Model, "HatTip", T.P(c, 0.16, 3.98, 0.08), T.P(c, 0.62, 4.22, 0.1), 0.24 * c.S, 0.24 * c.S, hat, M.Fabric)
	end
	if c.Room() >= 2 then
		star(c.Model, "TipStar", c.At(0.7, 4.24, 0.1), 0.3 * c.S, 0.06 * c.S, STAR_YELLOW, NEON)
		top = 4.42
	end
	-- a crescent moon on the front of the hat (a gold disc half hidden by a hat one)
	if c.Room() >= 2 then
		K.facing(c.Model, "Moon", c.At(0, 3.26, -0.54), 0.05 * c.S, 0.44 * c.S, GOLD, M.Foil)
		K.facing(c.Model, "MoonCut", c.At(0.1, 3.32, -0.56), 0.05 * c.S, 0.38 * c.S, hat, M.Fabric)
	end
	-- stars spangled on the hat
	for i, k in { { -0.42, 3.0, -0.6, 0.2 }, { 0.3, 3.6, -0.34, 0.16 }, { 0.36, 3.04, -0.58, 0.14 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "HatStar" .. i, c.At(k[1], k[2], k[3]), k[4] * c.S, k[4] * c.S, 0.04 * c.S, STAR_WHITE, NEON)
		end
	end
	-- the beard's pointed tip
	if c.Room() >= 1 then
		diamond(c.Model, "BeardTip", c.At(0, 1.12, -0.7), 0.42 * c.S, 0.42 * c.S, 0.2 * c.S, WHITE, M.Fabric)
	end
	-- the staff with a glowing star in the right fist
	if c.Room() >= 4 then
		T.seg(c.Model, "Staff", T.P(c, 0.96, 0.05, -0.22), T.P(c, 0.96, 2.62, -0.22), 0.1 * c.S, 0.1 * c.S, rgb(140, 90, 60), M.Wood)
		star(c.Model, "StaffStar", c.At(0.96, 2.86, -0.22), 0.46 * c.S, 0.1 * c.S, c.Glow, NEON)
		local glow = T.ellipsoid(c.Model, "StaffGlow", c.At(0.96, 2.86, -0.22), c.V(0.8, 0.8, 0.8), c.Glow, NEON)
		glow.Transparency = 0.7
		top = math.max(top, 3.26)
	end
	-- the starry robe round its middle
	if c.Room() >= 1 then
		K.part(c.Model, "Robe", c.At(0, 0.72, 0), c.V(1.28, 0.52, 0.93), hat, M.Fabric)
	end
	for i, k in { { -0.3, 0.66 }, { 0.28, 0.8 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "RobeStar" .. i, c.At(k[1], k[2], -0.47), 0.14 * c.S, 0.14 * c.S, 0.03 * c.S, GOLD, M.Foil)
		end
	end
	-- the spellbook in the left fist
	if c.Room() >= 2 then
		local book = c.At(-0.98, 0.86, -0.36) * CFrame.Angles(0, 0.4, 0.1)
		K.part(c.Model, "Book", book, c.V(0.18, 0.62, 0.5), rgb(200, 40, 90), M.SmoothPlastic)
		K.part(c.Model, "Pages", book * CFrame.new(0.03 * c.S, 0, 0), c.V(0.16, 0.56, 0.46), rgb(255, 244, 214), M.SmoothPlastic)
	end
	-- the long starry wizard cape: violet cloth, a gold hem, a star clasp
	cape(c, {
		Cloth = hat,
		Flare = hatDark,
		Hem = GOLD,
		Mantle = hatDark,
		Clasp = c.Glow,
		ClaspMaterial = NEON,
		Bottom = 0.06,
		Width = 1.96,
		Spread = 0.5,
		Back = 0.98,
	})
	-- the tall pointed collar standing behind the head
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		T.tri(
			c.Model,
			"Collar" .. i,
			T.P(c, side * 0.12, 1.5, 0.74),
			T.P(c, side * 0.98, 1.5, 0.74),
			T.P(c, side * 0.98, 2.64, 0.86),
			0.06 * c.S,
			hatDark,
			M.Fabric,
			1
		)
	end
	-- a crystal ball floating over the spellbook, a star glowing inside
	if c.Room() >= 2 then
		local orb = c.At(-1.02, 1.62, -0.42)
		local glass = K.part(c.Model, "CrystalBall", orb, c.V(0.46, 0.46, 0.46), rgb(190, 230, 255), M.Glass, BALL)
		glass.Transparency = 0.35
		diamond(c.Model, "BallStar", orb, 0.16 * c.S, 0.16 * c.S, 0.16 * c.S, c.Glow, NEON)
	end
	-- curly wizard shoes
	boots(c, hatDark, M.Fabric, nil)
	-- magic sparkles in the air
	for i, k in { { -1.1, 2.4, -0.3 }, { -0.9, 3.3, -0.2 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "Magic" .. i, c.At(k[1], k[2], k[3]), 0.16 * c.S, 0.16 * c.S, 0.04 * c.S, c.Glow, NEON)
		end
	end
	return top
end

local function novaGuardian(c: Ctx): number
	slimBrow(c, GOLD, M.Foil)
	cosmicShoulders(c, GOLD, c.Glow)
	-- the halo: a ring of light standing behind the head, gold stars on it
	local halo = c.At(0, 2.42, 0.82) * CFrame.Angles(PI / 2, 0, 0)
	local r = 1.08 * c.S
	ring(c.Model, "Halo", halo, r, 10, 0.1 * c.S, c.Glow, NEON, c.Room)
	for i = 1, 4 do
		if c.Room() < 1 then
			break
		end
		local at = onRing(halo, r, (i - 1) * PI / 2 + PI / 4)
		diamond(c.Model, "HaloStar" .. i, CFrame.new(at.Position), 0.26 * c.S, 0.26 * c.S, 0.06 * c.S, GOLD, M.Foil)
	end
	-- the crown: a gold band, five points, a nova star in front
	K.upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.3 * c.S, 1.36 * c.S, GOLD, M.Foil)
	for i = 1, 5 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.62
		local x, z = math.sin(a) * 0.62, -math.cos(a) * 0.62
		local h = if i == 3 then 0.5 else 0.36
		diamond(c.Model, "CrownPoint" .. i, c.At(x, 3.06, z) * CFrame.Angles(0, -a, 0), h * c.S, h * c.S, 0.08 * c.S, GOLD, M.Foil)
	end
	local top = 3.6
	if c.Room() >= 2 then
		star(c.Model, "Nova", c.At(0, 2.92, -0.72), 0.4 * c.S, 0.06 * c.S, STAR_WHITE, NEON)
	end
	-- the star shield on the left arm: gold star, blue star, a glowing gem
	if c.Room() >= 5 then
		local shield = c.At(-1.1, 1.0, -0.3) * CFrame.Angles(0, PI / 5, 0)
		star(c.Model, "Shield", shield, 0.92 * c.S, 0.12 * c.S, GOLD, M.Foil)
		star(c.Model, "ShieldIn", shield * CFrame.new(0, 0, -0.04 * c.S), 0.58 * c.S, 0.08 * c.S, c.Look.Body, M.SmoothPlastic)
		K.part(c.Model, "ShieldGem", shield * CFrame.new(0, 0, -0.1 * c.S), c.V(0.24, 0.24, 0.24), c.Glow, NEON, BALL)
	end
	-- the sword of light in the right fist
	if c.Room() >= 3 then
		T.seg(c.Model, "Blade", T.P(c, 0.92, 0.84, -0.2), T.P(c, 1.06, 2.5, -0.8), 0.2 * c.S, 0.06 * c.S, rgb(170, 250, 255), NEON)
		T.seg(c.Model, "Guard", T.P(c, 0.62, 0.8, -0.16), T.P(c, 1.22, 0.86, -0.2), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Pommel", c.At(0.9, 0.42, -0.04), c.V(0.16, 0.16, 0.16), GOLD, M.Foil, BALL)
	end
	-- gold armour: breastplate with a star, pauldrons, a belt
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.06, -0.435), c.V(0.96, 0.66, 0.04), GOLD, M.Foil)
	end
	T.redress(c, "Core", c.At(0, 1.08, -0.47), c.V(0.3, 0.3, 0.04), c.Glow, NEON)
	if c.Room() >= 1 then
		K.part(c.Model, "CoreB", c.At(0, 1.08, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.3, 0.3, 0.04), c.Glow, NEON)
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Pauldron" .. i,
				c.At(side * 0.8, 1.44, 0) * CFrame.Angles(0, 0, side * -0.3),
				c.V(0.54, 0.16, 0.6),
				GOLD_DARK,
				M.Foil
			)
		end
	end
	-- the royal cape: deep blue, gold-edged flares, a gold hem, a nova clasp
	cape(c, {
		Cloth = rgb(24, 30, 110),
		Flare = rgb(36, 46, 150),
		Hem = GOLD,
		Clasp = c.Glow,
		ClaspMaterial = NEON,
		Bottom = 0.04,
		Width = 2.0,
		Spread = 0.56,
		Back = 1.0,
	})
	-- the winged helm: gold wings sweeping up from the sides of the head
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.tri(
			c.Model,
			"HelmWing" .. i,
			T.P(c, side * 0.77, 1.98, 0.05),
			T.P(c, side * 0.77, 2.62, 0.2),
			T.P(c, side * 1.32, 3.16, 0.46),
			0.06 * c.S,
			GOLD,
			M.Foil,
			2
		)
	end
	-- gold greaves
	boots(c, GOLD_DARK, M.Foil, nil)
	belt(c, GOLD_DARK, false)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 4)
	end
	return top
end

local function nebulaTitan(c: Ctx): number
	slimBrow(c, c.Look.Trim, M.Slate)
	-- the shoulders: a cratered moon and a ringed planet
	reshape(c, "Boulder", c.At(-0.68, 1.6, 0.08), c.V(0.54, 0.54, 0.54), MOON, M.Slate, BALL)
	reshape(c, "Crystal", c.At(0.68, 1.6, 0.08), c.V(0.48, 0.48, 0.48), rgb(90, 220, 255), M.SmoothPlastic, BALL)
	-- the crown: a gold band, five points, three gems
	K.upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.3 * c.S, 1.36 * c.S, GOLD, M.Foil)
	for i = 1, 5 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.62
		local x, z = math.sin(a) * 0.62, -math.cos(a) * 0.62
		local h = if i == 3 then 0.52 else 0.38
		diamond(c.Model, "CrownPoint" .. i, c.At(x, 3.06, z) * CFrame.Angles(0, -a, 0), h * c.S, h * c.S, 0.08 * c.S, GOLD, M.Foil)
	end
	for i, a in { -0.62, 0, 0.62 } do
		if c.Room() < 1 then
			break
		end
		local x, z = math.sin(a) * 0.68, -math.cos(a) * 0.68
		local gem = if i == 2 then rgb(110, 240, 255) else c.Glow
		diamond(c.Model, "CrownGem" .. i, c.At(x, 2.86, z) * CFrame.Angles(0, -a, 0), 0.16 * c.S, 0.16 * c.S, 0.05 * c.S, gem, NEON)
	end
	-- the nebula orb over the crown
	local top = 3.6
	if c.Room() >= 2 then
		ball(c, "Orb", 0, 3.42, 0, 0.42, rgb(255, 150, 250), NEON)
		local glow = T.ellipsoid(c.Model, "OrbGlow", c.At(0, 3.42, 0), c.V(0.76, 0.76, 0.76), rgb(150, 110, 255), M.SmoothPlastic)
		glow.Transparency = 0.55
		top = 3.8
	end
	-- the orbit ring of planets round the crown
	local center = c.At(0, 3.0, 0.05) * CFrame.Angles(-0.18, 0, 0.22)
	local r = 1.3 * c.S
	ring(c.Model, "Orbit", center, r, 10, 0.08 * c.S, rgb(170, 200, 255), NEON, c.Room)
	if c.Room() >= 2 then
		local at = onRing(center, r, PI * 0.85)
		K.part(c.Model, "Saturn", at, c.V(0.46, 0.46, 0.46), SATURN, M.SmoothPlastic, BALL)
		K.upright(c.Model, "SaturnRing", at * CFrame.Angles(0.35, 0, -0.3), 0.04 * c.S, 0.82 * c.S, SATURN_RING, M.SmoothPlastic)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Planet", onRing(center, r, PI * 0.15), c.V(0.36, 0.36, 0.36), EARTH, M.SmoothPlastic, BALL)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Moonlet", onRing(center, r, PI * 1.45), c.V(0.26, 0.26, 0.26), MARS, M.SmoothPlastic, BALL)
	end
	-- the high cosmic collar behind the head and the cape
	if c.Room() >= 2 then
		K.part(c.Model, "Collar", c.At(0, 2.3, 0.78) * CFrame.Angles(-0.2, 0, 0), c.V(2.5, 1.8, 0.08), rgb(56, 26, 120), M.Fabric)
		K.part(c.Model, "CollarRim", c.At(0, 3.18, 0.96) * CFrame.Angles(-0.2, 0, 0), c.V(2.56, 0.12, 0.12), GOLD, M.Foil)
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			local cf = c.At(side * 1.26, 3.22, 0.97) * CFrame.Angles(-0.2, 0, 0)
			diamond(c.Model, "CollarPoint" .. i, cf, 0.34 * c.S, 0.34 * c.S, 0.1 * c.S, GOLD, M.Foil)
		end
	end
	-- the cosmic cape: deep space cloth, nebula-violet flares, a gold hem
	cape(c, {
		Cloth = SPACE,
		Flare = rgb(80, 30, 150),
		Hem = GOLD,
		Bottom = 0.04,
		Width = 2.04,
		Spread = 0.6,
		Back = 1.02,
	})
	-- nebula wings fanning out behind the collar: a violet sail, a pink one
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		T.tri(
			c.Model,
			"Wing" .. i,
			T.P(c, side * 0.5, 2.3, 1.06),
			T.P(c, side * 2.0, 3.4, 1.24),
			T.P(c, side * 1.6, 1.5, 1.18),
			0.05 * c.S,
			rgb(120, 70, 230),
			M.SmoothPlastic,
			2
		)
	end
	-- their glowing pink leading edges
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			T.seg(
				c.Model,
				"WingEdge" .. i,
				T.P(c, side * 0.5, 2.3, 1.04),
				T.P(c, side * 2.04, 3.43, 1.22),
				0.1 * c.S,
				0.1 * c.S,
				rgb(255, 120, 230),
				NEON
			)
		end
	end
	-- the sceptre with a ringed planet in the right fist
	if c.Room() >= 3 then
		T.seg(c.Model, "Staff", T.P(c, 0.98, 0.05, -0.22), T.P(c, 0.98, 2.3, -0.22), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		local head = c.At(0.98, 2.56, -0.22)
		K.part(c.Model, "SceptrePlanet", head, c.V(0.5, 0.5, 0.5), rgb(80, 220, 255), M.SmoothPlastic, BALL)
		K.upright(c.Model, "SceptreRing", head * CFrame.Angles(0.4, 0, 0.35), 0.04 * c.S, 0.96 * c.S, GOLD, M.Foil)
		top = math.max(top, 2.85)
	end
	-- the galaxy in its chest: a dark plate, a pink core, a spiral of light
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.06, -0.435), c.V(0.96, 0.66, 0.04), SPACE, M.SmoothPlastic)
	end
	T.redress(c, "Core", c.At(0, 1.06, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.26, 0.26, 0.04), rgb(255, 200, 255), NEON)
	-- the galaxy's glowing disc round the core, a paler inner swirl
	for i, k in { { 0.82, 0.44, 0.4, 0.35 }, { 0.5, 0.26, -0.5, 0.2 } } do
		if c.Room() >= 1 then
			local disc = T.ellipsoid(
				c.Model,
				"Galaxy" .. i,
				c.At(0, 1.06, -0.45 - 0.008 * i) * CFrame.Angles(0, 0, k[3]),
				c.V(k[1], k[2], 0.03),
				if i == 1 then c.Glow else rgb(190, 160, 255),
				NEON
			)
			disc.Transparency = k[4]
		end
	end
	belt(c, GOLD, false)
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Bracer" .. i,
				c.At(side * 0.82, 0.98, 0) * CFrame.Angles(0, 0, side * 0.1),
				c.V(0.42, 0.14, 0.52),
				GOLD,
				M.Foil
			)
		end
	end
	-- the nebula cloud at its feet (it floats on it)
	if c.Room() >= 2 then
		local pink = T.ellipsoid(
			c.Model,
			"NebulaA",
			c.At(-0.1, 0.32, 0.05) * CFrame.Angles(0, 0.4, 0.08),
			c.V(2.1, 0.5, 1.5),
			rgb(255, 90, 220),
			NEON
		)
		pink.Transparency = 0.45
		local blue =
			T.ellipsoid(c.Model, "NebulaB", c.At(0.2, 0.5, 0) * CFrame.Angles(0, -0.5, -0.1), c.V(1.7, 0.34, 1.3), rgb(90, 140, 255), NEON)
		blue.Transparency = 0.45
	end
	-- stars in its nebula skin
	for i, k in { { -0.84, 1.32, -0.25, 0.12 }, { 0.42, 0.62, -0.44, 0.1 }, { -0.42, 2.38, -0.66, 0.1 } } do
		if c.Room() >= 1 then
			diamond(c.Model, "Speck" .. i, c.At(k[1], k[2], k[3]), k[4] * c.S, k[4] * c.S, 0.03 * c.S, STAR_WHITE, NEON)
		end
	end
	-- gold boots with violet toes
	boots(c, GOLD, M.Foil, nil)
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 5)
		T.light(body, c.Glow, 8, 1.2)
	end
	return top
end

function Galaxy.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		SpaceHelmet = astroCadet,
		Comet = cometCub,
		Orbiters = orbitKeeper,
		StarHat = cosmoWizard,
		StarCrown = novaGuardian,
		NebulaCrown = nebulaTitan,
	}
end

---------------------------------------------------------------- the shard

--[[
	The GALAXY EGG shard (units: studs, the shard's center at s.Center, the
	front -Z): a sphere below the waist and a tall ellipsoid above it (an
	egg's shape, the halves of the opening) in glossy deep space, nebula
	clouds and stars on the shell, a planet ring with two moons, a gold star
	emblem, a comet, a crystal tip and a gold stand.
]]
function Galaxy.shard(kit: Kit, tools: Tools, s: Shard)
	K, T = kit, tools
	local C = s.Center
	local r = 1.25
	local topCenter = 0.4 * r
	local function at(x: number, y: number, z: number): CFrame
		return C * CFrame.new(x, y, z)
	end
	local function P(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- a point on the shell's surface (the upper ellipsoid above the waist,
	-- the sphere below) toward (x, y) on the front (-Z), pushed out by `out`
	local function surface(x: number, y: number, out: number): CFrame
		local rr
		if y > 0 then
			local yy = (y - topCenter) / (1.4 * r)
			rr = r * math.sqrt(math.max(1 - yy * yy, 0))
		else
			rr = math.sqrt(math.max(r * r - y * y, 0))
		end
		local z = -math.sqrt(math.max(rr * rr - x * x, 0)) - out
		local p = P(x, y, z)
		return CFrame.lookAt(p, P(x * 2, y, z * 2))
	end
	local deep = rgb(56, 32, 150)
	local deepLow = rgb(34, 22, 104)
	local glow = s.Glow

	-- Bottom: the round lower shell, the glowing band at the waist, the cracks
	T.ellipsoid(s.Bottom, "Shell", at(0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), deepLow, M.SmoothPlastic)
	K.upright(s.Bottom, "Band", at(0, 0.02, 0), 0.16, 2 * r + 0.06, glow, NEON)
	for i, k in { { -0.55, -0.35, 0.5 }, { 0.42, -0.62, -0.6 }, { 0.06, -0.9, 0.35 } } do
		local a = math.asin(math.clamp(k[1] / r, -1, 1))
		local y = k[2]
		local rr = math.sqrt(math.max(r * r - y * y, 0))
		K.part(
			s.Bottom,
			"Crack" .. i,
			at(math.sin(a) * (rr + 0.02), y, -math.cos(a) * (rr + 0.02)) * CFrame.Angles(0, -a, k[3]),
			Vector3.new(0.09, 0.62, 0.04),
			K.lighter(glow, 0.3),
			NEON
		)
	end
	-- the gold stand: a cup under the egg, a foot, three star-tipped prongs
	K.upright(s.Bottom, "Cup", at(0, -r + 0.14, 0), 0.26, 1.56, GOLD, M.Foil)
	K.upright(s.Bottom, "Foot", at(0, -r - 0.12, 0), 0.22, 2.2, GOLD_DARK, M.Foil)
	for i = 1, 3 do
		if s.Room() < 1 then
			break
		end
		local a = (i - 1) * 2 * PI / 3 + PI -- front first
		local dx, dz = math.sin(a), math.cos(a)
		T.seg(s.Bottom, "Prong" .. i, P(dx * 0.7, -r + 0.1, dz * 0.7), P(dx * 1.3, -0.3, dz * 1.3), 0.16, 0.16, GOLD, M.Foil)
	end
	-- stars on the lower shell
	for i, k in { { -0.62, -0.5, 0.12 }, { 0.5, -0.32, 0.1 }, { -0.05, -0.75, 0.09 } } do
		if s.Room() < 1 then
			break
		end
		K.part(s.Bottom, "LowStar" .. i, surface(k[1], k[2], -0.02), Vector3.new(k[3], k[3], k[3]), STAR_WHITE, NEON, BALL)
	end

	-- Top: the tall upper shell
	T.ellipsoid(s.Top, "Shell", at(0, topCenter, 0), Vector3.new(2 * r, 2.8 * r, 2 * r), deep, M.SmoothPlastic)
	-- nebula clouds hugging the shell (flat glowing ellipsoids on the surface)
	for i, k in
		{
			{ -0.62, 0.95, 1.2, 0.8, 0.5 },
			{ 0.55, 0.45, 1.1, 0.7, -0.4 },
			{ 0.1, 1.75, 0.9, 0.6, 0.2 },
		}
	do
		if s.Room() < 1 then
			break
		end
		local cf = surface(k[1], k[2], -0.06) * CFrame.Angles(0, 0, k[5])
		local tint = ({ rgb(255, 90, 210), rgb(80, 160, 255), rgb(170, 90, 255) })[i]
		local cloud = T.ellipsoid(s.Top, "Nebula" .. i, cf, Vector3.new(k[3], k[4], 0.24), tint, M.SmoothPlastic)
		cloud.Transparency = 0.2
	end
	-- the planet ring round the egg: a wide pale ring and a glowing inner one
	local ringCf = at(0, 0.5, 0) * CFrame.Angles(-0.28, 0, 0.18)
	local outer = K.upright(s.Top, "RingOuter", ringCf, 0.05, 3.9, rgb(255, 214, 150), M.SmoothPlastic)
	outer.Transparency = 0.15
	K.upright(s.Top, "RingInner", ringCf, 0.09, 3.1, K.darker(glow, 0.15), M.SmoothPlastic)
	-- two moons riding the ring
	for i, k in { { -1.7, 0.18, -0.6, 0.42 }, { 1.72, 0.0, 0.5, 0.34 } } do
		if s.Room() < 1 then
			break
		end
		local p = ringCf * CFrame.new(k[1], 0, k[3])
		K.part(
			s.Top,
			"Moon" .. i,
			p * CFrame.new(0, k[2], 0),
			Vector3.new(k[4], k[4], k[4]),
			if i == 1 then MARS else MOON,
			M.SmoothPlastic,
			BALL
		)
	end
	-- the gold star emblem on the front with a glowing heart
	if s.Room() >= 3 then
		local emblem = surface(0, 1.1, 0.02)
		star(s.Top, "Emblem", emblem, 0.7, 0.1, GOLD, M.Foil)
		star(s.Top, "EmblemCore", emblem * CFrame.new(0, 0, -0.05), 0.38, 0.08, STAR_WHITE, NEON)
	end
	-- stars scattered on the shell
	for i, k in { { -0.35, 1.55, 0.14 }, { 0.62, 1.35, 0.11 }, { -0.85, 0.35, 0.1 }, { 0.3, 2.1, 0.09 }, { 0.92, 0.85, 0.1 } } do
		if s.Room() < 1 then
			break
		end
		local cf = surface(k[1], k[2], -0.01)
		diamond(s.Top, "Star" .. i, cf, k[3] * 1.6, k[3] * 1.6, 0.05, STAR_WHITE, NEON)
	end
	-- the crystal tip: a glowing prism with a pointed cap, two small ones
	local tipY = topCenter + 1.4 * r
	if s.Room() >= 7 then
		local cyan = rgb(140, 240, 255)
		K.part(s.Top, "Crystal", at(0, tipY + 0.02, 0) * CFrame.Angles(0, PI / 4, 0), Vector3.new(0.42, 0.5, 0.42), cyan, NEON)
		local w = 0.3
		T.tri(s.Top, "CrystalCapX", P(-w, tipY + 0.26, 0), P(w, tipY + 0.26, 0), P(0, tipY + 0.82, 0), 0.3, cyan, NEON)
		T.tri(s.Top, "CrystalCapZ", P(0, tipY + 0.26, -w), P(0, tipY + 0.26, w), P(0, tipY + 0.82, 0), 0.3, K.lighter(cyan, 0.3), NEON)
		K.part(
			s.Top,
			"CrystalL",
			at(-0.3, tipY - 0.12, 0.02) * CFrame.Angles(0, 0, 0.5) * CFrame.Angles(0, PI / 4, 0),
			Vector3.new(0.26, 0.56, 0.26),
			rgb(255, 130, 230),
			NEON
		)
		K.part(
			s.Top,
			"CrystalR",
			at(0.3, tipY - 0.14, -0.02) * CFrame.Angles(0, 0, -0.5) * CFrame.Angles(0, PI / 4, 0),
			Vector3.new(0.24, 0.5, 0.24),
			rgb(170, 120, 255),
			NEON
		)
	end
	-- a comet streaking past the shoulder of the egg
	if s.Room() >= 3 then
		local head = P(1.22, 1.35, -0.62)
		local back = P(2.2, 1.75, 0.1)
		K.part(s.Top, "Comet", CFrame.new(head), Vector3.new(0.42, 0.42, 0.42), FLAME_WHITE, NEON, BALL)
		local dir = CFrame.lookAt(head, back)
		local tail1 = T.ellipsoid(s.Top, "CometTail1", dir * CFrame.new(0, 0, -0.38), Vector3.new(0.32, 0.32, 0.8), FLAME_HOT, NEON)
		tail1.Transparency = 0.25
		local tail2 = T.ellipsoid(s.Top, "CometTail2", dir * CFrame.new(0, 0, -0.95), Vector3.new(0.22, 0.22, 0.7), FLAME, NEON)
		tail2.Transparency = 0.45
	end
	-- the glossy shine on the shell (a pet-egg highlight)
	if s.Room() >= 1 then
		local shine = T.ellipsoid(
			s.Top,
			"Shine",
			surface(-0.55, 1.45, 0.0) * CFrame.Angles(0, 0, 0.5),
			Vector3.new(0.22, 0.62, 0.08),
			WHITE,
			M.SmoothPlastic
		)
		shine.Transparency = 0.25
	end
	-- golden star wings on its sides: a gold sail and a glowing inner feather
	for i, side in { -1, 1 } do
		if s.Room() < 2 then
			break
		end
		local root = P(side * 1.05, 0.7, 0.25)
		T.tri(s.Top, "Wing" .. i, root, P(side * 2.35, 2.05, 0.55), P(side * 2.0, 0.3, 0.5), 0.08, GOLD, M.Foil, 2)
	end
	for i, side in { -1, 1 } do
		if s.Room() < 1 then
			break
		end
		T.seg(s.Top, "WingGlow" .. i, P(side * 1.15, 0.8, 0.2), P(side * 2.2, 1.85, 0.48), 0.12, 0.12, rgb(255, 120, 220), NEON)
	end
	-- sparkles floating round it
	for i, k in { { -1.65, 2.35, -0.3, 0.3 }, { 1.75, -0.35, -0.5, 0.24 }, { -1.45, -0.7, -0.6, 0.2 } } do
		if s.Room() < 1 then
			break
		end
		diamond(s.Top, "Sparkle" .. i, at(k[1], k[2], k[3]), k[4], k[4], 0.05, STAR_WHITE, NEON)
	end
	-- a little rocket zooming round the ring
	if s.Room() >= 2 then
		local rocket = at(-1.95, 0.9, -0.55) * CFrame.Angles(0, 0, 0.9)
		K.upright(s.Top, "Rocket", rocket, 0.5, 0.22, WHITE, M.SmoothPlastic)
		T.ellipsoid(s.Top, "RocketFlame", rocket * CFrame.new(0, -0.36, 0), Vector3.new(0.16, 0.3, 0.16), FLAME_HOT, NEON)
	end
	local band = s.Bottom:FindFirstChild("Band")
	if band and band:IsA("BasePart") then
		T.embers(band, glow, 6, 0.25)
	end
end

return Galaxy
