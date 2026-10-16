--[[
	Builds the laser Blaster tool (design v2, replaces the pickaxe): chunky,
	toy-like guns after the Kenney Blaster Kit (blaster-a ... blaster-r, CC0),
	rebuilt from parts (never meshes).

	Design frame (studs): the barrel points along -Z, +Y is up, +X is the
	gun's right side, the body's bottom is y = 0. The Handle is the pistol
	grip, tilted back like a real grip; Tool.Grip puts the hand on it and
	keeps the barrel straight along the arm (in the R15 tool pose the grip
	attachment's -Z points forward). Muzzle = Attachment on the Handle at the
	barrel tip (the client beam starts there).

	Kit pieces, all shared by the levels:
	  receiver   the colored body, a box with chamfered top edges (4 parts)
	  carry      the Kenney carry handle on top (3 parts)
	  barrel     dark barrel + accent muzzle ring + glowing muzzle disc
	  core       the glowing core disc on both sides, in a dark housing ring
	  vent       a glowing side slot (Kenney's charging slot)
	  stock      skeleton rods + a tilted butt plate
	  scope      dark tube, steel bell, glowing lens, steel mount
	  pommel     a chunky grip foot; guard: the trigger guard bar
	  plus per-level steel noses, shrouds (raked fronts are wedges),
	  magazines, rails, humps, twin barrels + clamp, coils and cells

	Every level is its own gun, bigger and fancier with the level
	(the part counts never drop, the test checks it):
	  1 Rusty      small pistol (blaster-b)                 16 parts, ~1.9 studs
	  2 Scrap      compact with a mag well (c / k)           18
	  3 Spark      SMG, side panel, rear tube (a)            18
	  4 Ember      carbine, hump, lower rail (j)             20
	  5 Forgefire  bullpup, sloped top, fins (m)             20
	  6 Sunlance   skeleton stock, long top shroud (g)       20
	  7 Stormlance scope, raked shroud, solid stock (r)      23
	  8 Starlance  twin barrels, stock, carry handle (p)     23
	  9 Royal      long rifle: twin, scope on a rail (d / f) 24
	 10 Heartlance sniper: twin, coils, brake, cells (e)     25 parts, ~5.7 studs
	Budget: <= 25 parts. Colors follow the ore the blaster was forged from
	(BlasterData.skin): body, stock and accents (barrel rings, clamps) in the
	ore colors, glows (core, muzzle, vents, lens, coils, cells) in the ore
	glow, Kenney's light steel for front blocks, handles and magazines;
	level 1 (or no ore) is the rusty starter.

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
BlasterBuilder.MaxParts = 25
BlasterBuilder.Scale = 1 -- design studs -> held studs (level 1 is ~1.9 studs long, level 10 ~5.7)

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local STEEL = Color3.fromRGB(150, 158, 180) -- Kenney's light blue-grey steel (front blocks, handles, magazines)
local STEEL_DEEP = Color3.fromRGB(92, 96, 110) -- steel next to light grey ore bodies
local WOOD = Color3.fromRGB(110, 70, 42)
local RUST_STEEL = Color3.fromRGB(116, 114, 112)

-- Cylinder whose axis runs along Z (Roblox cylinders run along X).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

-- Wedge orientations (a WedgePart's slope faces -Z and up, the high edge at +Z).
local UP_FRONT = CFrame.identity -- slope faces up and forward
local UP_BACK = CFrame.Angles(0, math.pi, 0) -- slope faces up and back
local DOWN_FRONT = CFrame.Angles(0, 0, math.pi) -- slope faces down and forward (the top sticks out front)

export type Look = {
	Level: number,
	Rusty: boolean,
	Body: Color3,
	Accent: Color3,
	Glow: Color3,
	Dark: Color3,
	Grip: Color3,
	Steel: Color3,
	BodyMaterial: Enum.Material,
	SteelMaterial: Enum.Material,
}

type PartFn = (
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	className: string?
) -> BasePart

-- What a level design gets: the colors, the grip and a part maker (welded to the Handle).
type Ctx = {
	look: Look,
	part: PartFn,
	steel: Color3,
	metal: Enum.Material,
	grip: CFrame, -- the Handle in the design frame
	gripLength: number,
}

-- The grip of a level: top center at (0, GRIP_TOP, Z), Length long.
type Grip = { Z: number, Length: number }

local GRIP_TOP = 0.06
local GRIP_TILT = 0.28 -- radians, the bottom leans back
local GRIP_SIZE = Vector3.new(0.32, 1, 0.4) -- Y is replaced by the level's grip length
local HAND_DOWN = 0.3 -- the hand sits this far below the top of the grip

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

-- The colors of a blaster (also used for the beam color: Look.Glow).
function BlasterBuilder.look(level: any, oreId: string?): Look
	local info = BlasterData.get(level)
	local rusty = info.Level <= 1 or not oreId or oreId == ""
	local body, glow = BlasterData.skin(if rusty then "" else oreId)
	if rusty then
		return {
			Level = info.Level,
			Rusty = true,
			Body = body,
			Accent = Color3.fromRGB(186, 140, 92),
			Glow = glow,
			Dark = darker(IRON, 0.1),
			Grip = WOOD,
			Steel = RUST_STEEL,
			BodyMaterial = Enum.Material.CorrodedMetal,
			SteelMaterial = Enum.Material.CorrodedMetal,
		}
	end
	-- very dark ores (coal) keep a readable body; very light ones keep contrast
	local _, sat, v = body:ToHSV()
	if v < 0.32 then
		body = lighter(body, 0.18)
	end
	-- light grey bodies (silver, iron, quartz, diamond) get the deep steel so the parts stay apart
	local greyish = sat < 0.3 and v > 0.5
	return {
		Level = info.Level,
		Rusty = false,
		Body = body,
		Accent = if v > 0.85 then darker(body, 0.28) else lighter(body, 0.35),
		Glow = glow,
		Dark = if v < 0.32 then IRON_LIGHT else IRON,
		Grip = IRON:Lerp(body, 0.12),
		Steel = if greyish then STEEL_DEEP else STEEL,
		BodyMaterial = Enum.Material.SmoothPlastic,
		SteelMaterial = Enum.Material.Metal,
	}
end

---------------------------------------------------------------- kit pieces

-- A box from its extents (centered on x = 0).
local function slab(
	k: Ctx,
	name: string,
	zBack: number,
	zFront: number,
	yBot: number,
	yTop: number,
	w: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return k.part(
		name,
		CFrame.new(0, (yBot + yTop) / 2, (zBack + zFront) / 2),
		Vector3.new(w, yTop - yBot, zBack - zFront),
		color,
		material
	)
end

-- A wedge from its extents; `facing` is one of the wedge orientations above.
local function wedge(
	k: Ctx,
	name: string,
	zBack: number,
	zFront: number,
	yBot: number,
	yTop: number,
	w: number,
	facing: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local cf = CFrame.new(0, (yBot + yTop) / 2, (zBack + zFront) / 2) * facing
	return k.part(name, cf, Vector3.new(w, yTop - yBot, zBack - zFront), color, material, nil, "WedgePart")
end

-- A cylinder along Z.
local function tube(
	k: Ctx,
	name: string,
	x: number,
	y: number,
	zBack: number,
	zFront: number,
	d: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return k.part(name, CFrame.new(x, y, (zBack + zFront) / 2) * ALONG_Z, Vector3.new(zBack - zFront, d, d), color, material, CYL)
end

-- A cylinder along X (through the body, seen on both sides).
local function disc(
	k: Ctx,
	name: string,
	y: number,
	z: number,
	length: number,
	d: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return k.part(name, CFrame.new(0, y, z), Vector3.new(length, d, d), color, material, CYL)
end

-- A square rod from a to b (both on x = 0).
local function rod(k: Ctx, name: string, a: Vector3, b: Vector3, thick: number, color: Color3, material: Enum.Material?): BasePart
	local d = b - a
	local angle = math.atan2(-d.Y, d.Z)
	local cf = CFrame.new((a + b) / 2) * CFrame.Angles(angle, 0, 0)
	return k.part(name, cf, Vector3.new(thick, thick, d.Magnitude + thick * 0.6), color, material)
end

-- The colored body: a box with chamfered top edges (Body, BodyTop, BevelL, BevelR).
local function receiver(k: Ctx, zBack: number, zFront: number, h: number, w: number, c: number)
	local color, material = k.look.Body, k.look.BodyMaterial
	local zc = (zBack + zFront) / 2
	local len = zBack - zFront
	slab(k, "Body", zBack, zFront, 0, h - c, w, color, material)
	slab(k, "BodyTop", zBack, zFront, h - c, h, w - 2 * c, color, material)
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * (w - c) / 2, h - c / 2, zc) * CFrame.Angles(0, -side * math.pi / 2, 0)
		k.part(if side < 0 then "BevelL" else "BevelR", cf, Vector3.new(len, c, c), color, material, nil, "WedgePart")
	end
end

-- Kenney's carry handle: two posts and a bar on top of the body (top at y = base).
local function carry(k: Ctx, zBack: number, zFront: number, base: number, height: number)
	local t = 0.12
	slab(k, "CarryBar", zBack, zFront, base + height - 0.08, base + height, t + 0.02, k.steel, k.metal)
	slab(k, "CarryPost", zBack, zBack - 0.09, base - 0.04, base + height - 0.04, t, k.steel, k.metal)
	slab(k, "CarryPost", zFront + 0.09, zFront, base - 0.04, base + height - 0.04, t, k.steel, k.metal)
end

-- Barrel + glowing muzzle disc (+ accent ring); returns the muzzle point.
local function barrel(k: Ctx, name: string, x: number, y: number, zBack: number, zTip: number, d: number, ring: boolean): Vector3
	local look = k.look
	tube(k, name, x, y, zBack, zTip, d, look.Dark, k.metal)
	if ring then
		tube(k, if name == "Barrel2" then "MuzzleRing2" else "MuzzleRing", x, y, zTip + 0.16, zTip + 0.02, d + 0.1, look.Accent, k.metal)
	end
	local glowD = d * 0.64
	tube(k, if name == "Barrel2" then "MuzzleGlow2" else "MuzzleGlow", x, y, zTip + 0.01, zTip - 0.03, glowD, look.Glow, NEON)
	return Vector3.new(x, y, zTip - 0.08)
end

-- The glowing core: a small disc through the body (seen on both sides) in a dark housing ring.
local function core(k: Ctx, y: number, z: number, w: number, d: number)
	disc(k, "CoreHousing", y, z, w + 0.04, d + 0.12, k.look.Dark, k.metal)
	disc(k, "Core", y, z, w + 0.07, d * 0.75, k.look.Glow, NEON)
end

-- A glowing side slot (Kenney's charging slot), through the body.
local function vent(k: Ctx, y: number, zBack: number, zFront: number, w: number)
	slab(k, "Vent", zBack, zFront, y - 0.045, y + 0.045, w + 0.03, k.look.Glow, NEON)
end

-- The trigger guard: a steel bar from the grip forward to the part in front.
local function guard(k: Ctx, zBack: number, zFront: number)
	slab(k, "Guard", zBack, zFront, -0.31, -0.23, 0.12, k.steel, k.metal)
end

-- A chunky foot at the bottom of the grip.
local function pommel(k: Ctx, color: Color3, material: Enum.Material)
	local cf = k.grip * CFrame.new(0, -k.gripLength / 2 + 0.05, 0.03)
	k.part("Pommel", cf, Vector3.new(GRIP_SIZE.X + 0.08, 0.16, GRIP_SIZE.Z + 0.12), color, material)
end

-- Skeleton stock: one or two rods from the body back to a tilted butt plate.
local function stock(k: Ctx, zFrom: number, length: number, yTop: number, yBot: number, buttH: number, twoRods: boolean)
	local look = k.look
	local zEnd = zFrom + length
	local buttTop = yTop + 0.06
	rod(
		k,
		"StockRod",
		Vector3.new(0, yTop, zFrom - 0.05),
		Vector3.new(0, buttTop - 0.12, zEnd),
		if twoRods then 0.11 else 0.15,
		k.steel,
		k.metal
	)
	if twoRods then
		rod(k, "StockRod", Vector3.new(0, yBot, zFrom - 0.05), Vector3.new(0, buttTop - buttH + 0.16, zEnd), 0.11, k.steel, k.metal)
	end
	local butt = CFrame.new(0, buttTop - buttH / 2, zEnd + 0.05) * CFrame.Angles(0.16, 0, 0)
	k.part("Butt", butt, Vector3.new(0.4, buttH, 0.17), look.Body, look.BodyMaterial)
end

-- Scope: dark tube, steel front bell with a glowing lens, steel mount.
local function scope(k: Ctx, zBack: number, zFront: number, y: number, d: number, mountZ: number, base: number)
	local look = k.look
	tube(k, "Scope", 0, y, zBack, zFront + 0.2, d, look.Dark, k.metal)
	tube(k, "ScopeBell", 0, y, zFront + 0.24, zFront, d * 1.5, k.steel, k.metal)
	tube(k, "Lens", 0, y, zFront + 0.01, zFront - 0.03, d * 1.12, look.Glow, NEON)
	slab(k, "ScopeMount", mountZ + 0.16, mountZ - 0.16, base - 0.04, y - d * 0.3, 0.14, k.steel, k.metal)
end

---------------------------------------------------------------- the ten guns

local GRIPS: { Grip } = {
	{ Z = 0.18, Length = 0.78 },
	{ Z = 0.2, Length = 0.8 },
	{ Z = 0.3, Length = 0.8 },
	{ Z = 0.3, Length = 0.82 },
	{ Z = 0.16, Length = 0.82 },
	{ Z = 0.26, Length = 0.82 },
	{ Z = 0.36, Length = 0.84 },
	{ Z = 0.44, Length = 0.84 },
	{ Z = 0.46, Length = 0.86 },
	{ Z = 0.5, Length = 0.86 },
}

-- Each design builds its parts (besides the Handle) and returns the muzzle point.
local DESIGNS: { (k: Ctx) -> Vector3 } = {
	-- 1 Rusty Blaster: a small chunky pistol (blaster-b)
	function(k: Ctx): Vector3
		receiver(k, 0.5, -0.6, 0.62, 0.54, 0.14)
		slab(k, "Nose", -0.56, -0.92, -0.32, 0.66, 0.58, k.steel, k.metal)
		slab(k, "Sight", -0.78, -0.9, 0.64, 0.8, 0.1, k.steel, k.metal)
		core(k, 0.32, -0.16, 0.54, 0.2)
		guard(k, 0.06, -0.58)
		carry(k, 0.3, -0.22, 0.62, 0.2)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.42, -0.88, -1.14, 0.26, false)
	end,
	-- 2 Scrap Blaster: compact, steel rear cap, body-colored mag well, sight (blaster-c / k)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.5, -0.72, 0.64, 0.56, 0.14)
		slab(k, "RearCap", 0.62, 0.46, 0.06, 0.56, 0.5, k.steel, k.metal)
		slab(k, "Nose", -0.68, -1.0, 0.02, 0.7, 0.6, k.steel, k.metal)
		slab(k, "MagWell", -0.34, -0.72, -0.56, 0.04, 0.5, look.Body, look.BodyMaterial)
		slab(k, "Sight", -0.86, -1.0, 0.68, 0.84, 0.1, k.steel, k.metal)
		core(k, 0.34, -0.12, 0.56, 0.2)
		guard(k, 0.08, -0.36)
		carry(k, 0.34, -0.28, 0.64, 0.2)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.44, -0.96, -1.22, 0.26, false)
	end,
	-- 3 Spark Blaster: SMG with a steel side panel, rear tube and magazine (blaster-a)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.7, -0.76, 0.66, 0.58, 0.15)
		tube(k, "RearTube", 0, 0.44, 1.04, 0.6, 0.4, look.Body, look.BodyMaterial)
		slab(k, "SidePanel", 0.44, -0.56, 0.16, 0.5, 0.62, k.steel, k.metal)
		slab(k, "Nose", -0.72, -1.02, -0.14, 0.74, 0.62, k.steel, k.metal)
		slab(k, "Magazine", -0.4, -0.78, -0.66, 0.0, 0.42, k.steel, k.metal)
		slab(k, "Sight", -0.86, -1.0, 0.72, 0.88, 0.1, k.steel, k.metal)
		core(k, 0.33, -0.06, 0.62, 0.2)
		guard(k, 0.18, -0.42)
		carry(k, 0.5, -0.5, 0.66, 0.18)
		slab(k, "Barrel", -0.96, -1.32, 0.42, 0.68, 0.44, k.steel, k.metal)
		tube(k, "MuzzleGlow", 0, 0.55, -1.31, -1.35, 0.18, look.Glow, NEON)
		return Vector3.new(0, 0.55, -1.4)
	end,
	-- 4 Ember Blaster: carbine with a steel hump, lower rail, big magazine (blaster-j)
	function(k: Ctx): Vector3
		receiver(k, 0.76, -0.86, 0.62, 0.58, 0.15)
		slab(k, "RearPlate", 0.9, 0.72, 0.08, 0.54, 0.52, k.steel, k.metal)
		slab(k, "Hump", -0.04, -0.52, 0.6, 0.8, 0.42, k.steel, k.metal)
		slab(k, "Nose", -0.82, -1.12, -0.06, 0.78, 0.62, k.steel, k.metal)
		slab(k, "LowerRail", -0.42, -1.12, -0.2, 0.02, 0.44, k.steel, k.metal)
		slab(k, "Magazine", -0.16, -0.6, -0.8, -0.1, 0.42, k.steel, k.metal)
		slab(k, "Sight", -0.98, -1.12, 0.76, 0.94, 0.1, k.steel, k.metal)
		core(k, 0.34, -0.64, 0.58, 0.2)
		vent(k, 0.34, 0.46, 0.04, 0.58)
		guard(k, 0.18, -0.18)
		carry(k, 0.62, 0.12, 0.62, 0.2)
		return barrel(k, "Barrel", 0, 0.48, -1.08, -1.44, 0.26, false)
	end,
	-- 5 Forgefire Blaster: bullpup with a sloped steel top, fins and a round rear cap (blaster-m)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.8, -0.8, 0.56, 0.6, 0.15)
		wedge(k, "TopRamp", 0.66, 0.2, 0.5, 0.82, 0.48, UP_BACK, k.steel, k.metal)
		slab(k, "TopCover", 0.2, -0.5, 0.5, 0.82, 0.48, k.steel, k.metal)
		slab(k, "Front", -0.78, -1.12, -0.2, 0.92, 0.62, look.Body, look.BodyMaterial)
		tube(k, "RearCap", 0, 0.3, 1.12, 0.78, 0.46, look.Accent, k.metal)
		slab(k, "Fin", -0.02, -0.12, 0.8, 1.02, 0.08, look.Accent, k.metal)
		slab(k, "Fin", -0.3, -0.4, 0.8, 1.02, 0.08, look.Accent, k.metal)
		slab(k, "LowerFront", -0.3, -0.8, -0.26, 0.04, 0.5, k.steel, k.metal)
		slab(k, "Sight", -0.96, -1.1, 0.9, 1.06, 0.1, k.steel, k.metal)
		core(k, 0.28, -0.56, 0.6, 0.2)
		vent(k, 0.28, 0.5, 0.0, 0.6)
		guard(k, 0.03, -0.32)
		return barrel(k, "Barrel", 0, 0.62, -1.08, -1.46, 0.28, true)
	end,
	-- 6 Sunlance: short skeleton stock, steel hump, long top shroud, foregrip (blaster-g)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.6, -0.72, 0.62, 0.6, 0.15)
		stock(k, 0.6, 0.62, 0.48, 0.12, 0.78, true)
		slab(k, "Hump", 0.24, -0.2, 0.6, 0.86, 0.44, k.steel, k.metal)
		wedge(k, "HumpSlope", -0.2, -0.4, 0.6, 0.86, 0.44, UP_FRONT, k.steel, k.metal)
		slab(k, "Shroud", -0.4, -1.5, 0.4, 0.78, 0.46, k.steel, k.metal)
		slab(k, "Foregrip", -0.4, -0.96, -0.26, 0.04, 0.52, look.Body, look.BodyMaterial)
		pommel(k, look.Body, look.BodyMaterial)
		core(k, 0.3, -0.2, 0.6, 0.22)
		vent(k, 0.59, -0.62, -1.2, 0.46)
		guard(k, 0.12, -0.42)
		return barrel(k, "Barrel", 0, 0.59, -1.44, -1.72, 0.26, true)
	end,
	-- 7 Stormlance: scope, raked steel shroud, magazine, lower hook, solid stock (blaster-r)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.86, -0.7, 0.64, 0.6, 0.15)
		slab(k, "Stock", 1.8, 0.84, 0.26, 0.6, 0.46, look.Body, look.BodyMaterial)
		wedge(k, "StockHeel", 1.8, 1.2, -0.24, 0.27, 0.46, DOWN_FRONT, look.Body, look.BodyMaterial)
		slab(k, "TopRail", 0.52, -0.42, 0.62, 0.7, 0.26, look.Dark, k.metal)
		scope(k, 0.46, -0.56, 1.0, 0.22, -0.02, 0.7)
		slab(k, "Shroud", -0.62, -1.42, 0.1, 0.68, 0.56, k.steel, k.metal)
		wedge(k, "ShroudRake", -1.42, -1.7, 0.1, 0.68, 0.56, DOWN_FRONT, k.steel, k.metal)
		slab(k, "Magazine", -0.08, -0.54, -0.82, 0.02, 0.44, k.steel, k.metal)
		slab(k, "LowerRail", -0.5, -1.38, -0.22, -0.08, 0.2, k.steel, k.metal)
		core(k, 0.32, 0.24, 0.6, 0.22)
		vent(k, 0.44, -0.74, -1.3, 0.56)
		guard(k, 0.22, -0.1)
		return barrel(k, "Barrel", 0, 0.3, -1.4, -1.86, 0.24, true)
	end,
	-- 8 Starlance: twin barrels with a clamp, skeleton stock, carry handle, mag well (blaster-p)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.96, -0.76, 0.64, 0.6, 0.15)
		stock(k, 0.96, 0.92, 0.5, 0.1, 0.92, true)
		carry(k, 0.62, 0.0, 0.64, 0.2)
		slab(k, "Nose", -0.72, -0.98, 0.06, 0.68, 0.6, k.steel, k.metal)
		slab(k, "MagWell", -0.1, -0.6, -0.4, 0.02, 0.56, look.Body, look.BodyMaterial)
		slab(k, "Magazine", -0.14, -0.52, -0.86, -0.36, 0.42, k.steel, k.metal)
		slab(k, "Clamp", -1.42, -1.54, 0.24, 0.6, 0.58, look.Accent, k.metal)
		vent(k, 0.34, -0.06, -0.56, 0.6)
		core(k, 0.34, 0.36, 0.6, 0.22)
		guard(k, 0.32, -0.12)
		local a = barrel(k, "Barrel", -0.14, 0.42, -0.9, -1.84, 0.2, false)
		local b = barrel(k, "Barrel2", 0.14, 0.42, -0.9, -1.84, 0.2, false)
		return (a + b) / 2
	end,
	-- 9 Royal Sunlance: long rifle, twin barrels, scope on a rail, stock (blaster-d / f)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 0.96, -0.9, 0.66, 0.62, 0.16)
		stock(k, 0.96, 0.94, 0.52, 0.1, 0.96, true)
		slab(k, "TopRail", 0.62, -0.62, 0.64, 0.72, 0.26, look.Dark, k.metal)
		scope(k, 0.56, -0.58, 1.06, 0.24, 0.0, 0.72)
		slab(k, "Nose", -0.86, -1.16, 0.04, 0.72, 0.62, k.steel, k.metal)
		slab(k, "Magazine", -0.2, -0.62, -0.82, 0.02, 0.44, k.steel, k.metal)
		slab(k, "Clamp", -1.92, -2.04, 0.26, 0.62, 0.6, look.Accent, k.metal)
		vent(k, 0.24, -0.88, -1.14, 0.62)
		core(k, 0.32, 0.3, 0.62, 0.22)
		guard(k, 0.34, -0.2)
		local a = barrel(k, "Barrel", -0.15, 0.44, -1.0, -2.34, 0.21, false)
		local b = barrel(k, "Barrel2", 0.15, 0.44, -1.0, -2.34, 0.21, false)
		return (a + b) / 2
	end,
	-- 10 Heartlance: sniper with long twin barrels, a glowing coil, a muzzle brake, big scope, energy cells (blaster-e)
	function(k: Ctx): Vector3
		local look = k.look
		receiver(k, 1.0, -0.96, 0.68, 0.64, 0.16)
		stock(k, 1.0, 1.0, 0.54, 0.1, 1.0, false)
		scope(k, 0.64, -0.66, 1.1, 0.26, 0.0, 0.68)
		slab(k, "Nose", -0.92, -1.22, 0.04, 0.74, 0.64, k.steel, k.metal)
		slab(k, "Magazine", -0.2, -0.64, -0.84, 0.02, 0.46, k.steel, k.metal)
		slab(k, "Coil", -1.86, -1.94, 0.25, 0.65, 0.62, look.Glow, NEON)
		slab(k, "Coil", -2.12, -2.2, 0.25, 0.65, 0.62, look.Glow, NEON)
		slab(k, "Brake", -2.7, -2.96, 0.22, 0.68, 0.66, look.Accent, k.metal)
		for _, side in { -1, 1 } do
			k.part("Cell", CFrame.new(side * 0.38, 0.3, -0.24) * ALONG_Z, Vector3.new(0.64, 0.18, 0.18), look.Glow, NEON, CYL)
		end
		core(k, 0.34, 0.4, 0.64, 0.22)
		guard(k, 0.38, -0.2)
		local a = barrel(k, "Barrel", -0.15, 0.45, -1.06, -3.0, 0.22, false)
		local b = barrel(k, "Barrel2", 0.15, 0.45, -1.06, -3.0, 0.22, false)
		return (a + b) / 2
	end,
}

function BlasterBuilder.build(level: any, oreId: string?): Tool
	local info = BlasterData.get(level)
	local look = BlasterBuilder.look(info.Level, oreId)
	local lv = info.Level
	local s = BlasterBuilder.Scale
	local function scaled(cf: CFrame): CFrame
		return CFrame.new(cf.Position * s) * cf.Rotation
	end
	local grip = GRIPS[lv]
	local handleDesign = CFrame.new(0, GRIP_TOP, grip.Z) * CFrame.Angles(-GRIP_TILT, 0, 0) * CFrame.new(0, -grip.Length / 2 + 0.02, 0)
	local handleCf = scaled(handleDesign)
	local hand = (handleDesign * CFrame.new(0, grip.Length / 2 - HAND_DOWN, 0)).Position

	local tool = Instance.new("Tool")
	tool.Name = BlasterBuilder.ToolName
	tool.ToolTip = BlasterData.displayName(lv, oreId)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	-- the hand on the grip, the barrel straight along the arm
	tool.Grip = handleCf:Inverse() * CFrame.new(hand * s)
	tool:SetAttribute("Level", lv)
	tool:SetAttribute("OreId", if oreId then oreId else "")
	tool:SetAttribute("Range", info.Range)
	tool:SetAttribute("Glow", look.Glow)

	local handle = Geo.make("Part", {
		Name = "Handle",
		Size = Vector3.new(GRIP_SIZE.X, grip.Length, GRIP_SIZE.Z) * s,
		Color = look.Grip,
		Material = if look.Rusty then Enum.Material.Wood else Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = true,
		CastShadow = false,
		CFrame = handleCf,
	})
	handle.Parent = tool

	local function part(
		name: string,
		cf: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?,
		className: string?
	): BasePart
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = scaled(cf),
			Size = size * s,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			CastShadow = false,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	local k: Ctx = {
		look = look,
		part = part,
		steel = look.Steel,
		metal = look.SteelMaterial,
		grip = handleDesign,
		gripLength = grip.Length,
	}
	local tip = DESIGNS[lv](k)

	-- where the beam leaves the barrel (between the twin barrels from level 8)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = handleCf:PointToObjectSpace(tip * s)
	muzzle.Parent = handle
	return tool
end

return BlasterBuilder
