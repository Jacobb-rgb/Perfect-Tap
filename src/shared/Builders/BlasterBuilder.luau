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
	  receiver   the colored body; its bottom corners can be chamfered
	             (Body + Belly + a wedge per corner; the belly can be
	             Kenney's steel lower band)
	  carry      the thick Kenney carry handle on top (bar + 2 posts)
	  slot       Kenney's dark side slot with a small lever sticking out
	  litSlot    the same slot with a thin glowing strip inside (a vent)
	  core       a small glowing power light in a steel bezel
	  barrel     dark barrel (+ accent muzzle ring) + glowing muzzle disc
	  twin       over-under twin barrels poking out of a handguard, one
	             chunky accent collar over both tips, two glowing bores
	  skeleton   skeleton stock: two rods + a tilted butt plate
	  scope      dark tube, steel eyepiece ring and front bell, glowing lens,
	             one long rail mount
	  pommel     the wrap-around pad at the bottom of the grip
	  guard      the trigger guard bar
	  plus per-level steel noses and front blocks with raked / chamfered
	  corners (wedges), shrouds, handguards, magazines, humps, rails,
	  stocks, a cell and a coil collar.

	Every level is its own gun, bigger and fancier with the level
	(the part counts never drop, the test checks it):
	  1 Rusty      junk pistol, dark chamfered nose, rust patch (b)   20 parts
	  2 Scrap      raked top, big steel front block, colored pad (c)  21
	  3 Spark      SMG: rear tube, steel side panel, square barrel (a) 21
	  4 Ember      carbine: rear block, lower handguard (j)           21
	  5 Forgefire  bullpup: steel ramp, raked mouth, rear cap (m)     22
	  6 Sunlance   skeleton stock, hump, long top shroud + hook (g)   22
	  7 Stormlance scope, raked shroud, solid stock (r)               23
	  8 Starlance  long top rail, vented handguard, twin barrels (p)  25
	  9 Royal      raked body handguard, angled stock, scope (d)      25
	 10 Heartlance sniper: loop stock, inline cell, coil, brake (e)   25
	Budget: <= 25 parts. Colors follow the ore the blaster was forged from
	(BlasterData.skin): body, stock and accents (rings, levers, collars) in
	the ore colors, glows (core, muzzle, vents, lens, coil, cell) in the ore
	glow, Kenney's light steel for front blocks, handles and magazines;
	level 1 (or no ore) is the rusty starter. Big glowing pieces use a
	softer glow when the ore glow is very bright (no white bloom blobs).

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
BlasterBuilder.MaxParts = 25
BlasterBuilder.Scale = 1.2 -- design studs -> held studs (level 1 is ~2.4 studs long, level 10 ~5.5)

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local SLOT = Color3.fromRGB(34, 34, 40) -- the dark side slots
local STEEL = Color3.fromRGB(150, 158, 180) -- Kenney's light blue-grey steel (front blocks, handles, magazines)
local STEEL_DEEP = Color3.fromRGB(92, 96, 110) -- steel next to light grey ore bodies
local WOOD = Color3.fromRGB(110, 70, 42)
local RUST_STEEL = Color3.fromRGB(122, 116, 110)
local RUST_PATCH = Color3.fromRGB(96, 54, 34) -- the starter's crooked repair plate
local RUST_NOSE = Color3.fromRGB(66, 62, 60)

-- Cylinder whose axis runs along Z (Roblox cylinders run along X).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal -- barrels and scope tubes keep a little sheen

-- Wedge orientations (a WedgePart's slope faces -Z and up, the high edge at +Z).
local UP_FRONT = CFrame.identity -- the top-front corner is cut away
local UP_BACK = CFrame.Angles(0, math.pi, 0) -- the top-back corner is cut away
local DOWN_FRONT = CFrame.Angles(0, 0, math.pi) -- the bottom-front corner is cut away
local DOWN_BACK = CFrame.Angles(math.pi, 0, 0) -- the bottom-back corner is cut away

export type Look = {
	Level: number,
	Rusty: boolean,
	Body: Color3,
	Accent: Color3,
	Glow: Color3, -- small glowing discs (muzzle, lens, core) and the beam
	GlowSoft: Color3, -- bigger glowing pieces (vents, coil ring, cell)
	GlowCore: Color3, -- the core light (between the two)
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
local HAND_DOWN = 0.28 -- the hand sits this far below the top of the grip

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

-- Glowing pieces bloom into white blobs when the glow is very bright (pale, gold, green):
-- those get a glow pulled toward the body and darker. `amount` = how much dimmer in general.
local function softGlow(glow: Color3, body: Color3, amount: number): Color3
	local hue, sat, v = glow:ToHSV()
	local pale = v > 0.9 and sat < 0.5
	local yellowGreen = hue > 0.1 and hue < 0.45
	if pale or yellowGreen then
		return darker(glow:Lerp(body, 0.35), amount + 0.1)
	end
	return darker(glow, amount)
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
			GlowSoft = softGlow(glow, body, 0.3),
			GlowCore = softGlow(glow, body, 0.1),
			Dark = darker(IRON, 0.1),
			Grip = WOOD,
			Steel = RUST_STEEL,
			BodyMaterial = Enum.Material.CorrodedMetal,
			SteelMaterial = Enum.Material.CorrodedMetal,
		}
	end
	-- very dark ores (coal, obsidian) keep a readable body; very light ones keep contrast
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
		Accent = if v > 0.85 then darker(body, 0.28) elseif v < 0.32 then lighter(body, 0.5) else lighter(body, 0.35),
		Glow = glow,
		GlowSoft = softGlow(glow, body, 0.3),
		GlowCore = softGlow(glow, body, 0.1),
		Dark = if v < 0.32 then IRON_LIGHT else IRON,
		Grip = IRON:Lerp(body, 0.12),
		Steel = if greyish then STEEL_DEEP else STEEL,
		BodyMaterial = Enum.Material.SmoothPlastic,
		SteelMaterial = Enum.Material.SmoothPlastic, -- Kenney's steel is flat, like toy plastic
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

--[[
	The colored body, h tall and w wide. Its bottom corners can be chamfered
	(c tall, cf deep at the front, cb deep at the back): the Body sits above,
	the Belly below it is shortened and a wedge fills each chamfered corner.
	steelBelly turns the lower band into Kenney's steel strip.
]]
local function receiver(
	k: Ctx,
	zBack: number,
	zFront: number,
	h: number,
	w: number,
	c: number,
	cf: number,
	cb: number,
	steelBelly: boolean?
)
	local color, material = k.look.Body, k.look.BodyMaterial
	if cf <= 0 and cb <= 0 then
		slab(k, "Body", zBack, zFront, 0, h, w, color, material)
		return
	end
	local bellyColor = if steelBelly then k.steel else color
	local bellyMaterial = if steelBelly then k.metal else material
	slab(k, "Body", zBack, zFront, c, h, w, color, material)
	slab(k, "Belly", zBack - cb, zFront + cf, 0, c, w, bellyColor, bellyMaterial)
	if cf > 0 then
		wedge(k, "ChamferF", zFront + cf, zFront, 0, c, w, DOWN_FRONT, bellyColor, bellyMaterial)
	end
	if cb > 0 then
		wedge(k, "ChamferB", zBack, zBack - cb, 0, c, w, DOWN_BACK, bellyColor, bellyMaterial)
	end
end

-- Kenney's thick carry handle: a bar on two posts on top of the body (top at y = base).
local function carry(k: Ctx, zBack: number, zFront: number, base: number, height: number)
	slab(k, "CarryBar", zBack + 0.02, zFront - 0.02, base + height - 0.12, base + height, 0.2, k.steel, k.metal)
	slab(k, "CarryPost", zBack, zBack - 0.14, base - 0.04, base + height - 0.06, 0.16, k.steel, k.metal)
	slab(k, "CarryPost", zFront + 0.14, zFront, base - 0.04, base + height - 0.06, 0.16, k.steel, k.metal)
end

-- A small lever block sticking out of a slot on both sides.
local function lever(k: Ctx, y: number, z: number, w: number)
	k.part("Lever", CFrame.new(0, y, z), Vector3.new(w + 0.1, 0.13, 0.11), k.look.Accent, k.metal)
end

-- Kenney's dark side slot (through the body: seen on both sides) with an optional lever.
local function slot(k: Ctx, y: number, zBack: number, zFront: number, w: number, leverZ: number?)
	slab(k, "Slot", zBack, zFront, y - 0.04, y + 0.04, w + 0.02, SLOT, k.metal)
	if leverZ then
		lever(k, y, leverZ, w)
	end
end

-- A lit slot: a dark slot frame with a thin glowing strip inside (a vent).
local function litSlot(k: Ctx, y: number, zBack: number, zFront: number, w: number, leverZ: number?)
	slab(k, "VentFrame", zBack, zFront, y - 0.06, y + 0.06, w + 0.02, SLOT, k.metal)
	slab(k, "Vent", zBack - 0.05, zFront + 0.05, y - 0.025, y + 0.025, w + 0.04, k.look.GlowSoft, NEON)
	if leverZ then
		lever(k, y, leverZ, w)
	end
end

-- The glowing core: a small power light in a steel bezel, through the body (seen on both sides).
local function core(k: Ctx, y: number, z: number, w: number, d: number, bezel: Color3?)
	disc(k, "CoreHousing", y, z, w + 0.04, d, bezel or k.steel, k.metal)
	disc(k, "Core", y, z, w + 0.07, d * 0.55, k.look.GlowCore, NEON)
end

-- The trigger guard: a bar from the grip forward to the part in front.
local function guard(k: Ctx, zBack: number, zFront: number)
	slab(k, "Guard", zBack, zFront, -0.32, -0.22, 0.12, k.steel, k.metal)
end

-- The wrap-around pad at the bottom of the grip (a bit wider than the grip, wraps the front).
local function pommel(k: Ctx, color: Color3, material: Enum.Material)
	local cf = k.grip * CFrame.new(0, -k.gripLength / 2 + 0.04, -0.06)
	k.part("Pommel", cf, Vector3.new(GRIP_SIZE.X + 0.1, 0.16, GRIP_SIZE.Z + 0.16), color, material)
end

-- Dark barrel + glowing muzzle disc (+ accent ring); returns the muzzle point.
local function barrel(
	k: Ctx,
	name: string,
	x: number,
	y: number,
	zBack: number,
	zTip: number,
	d: number,
	ring: boolean,
	color: Color3?
): Vector3
	local look = k.look
	tube(k, name, x, y, zBack, zTip, d, color or look.Dark, if look.Rusty then k.metal else METAL)
	if ring then
		tube(k, "MuzzleRing", x, y, zTip + 0.16, zTip + 0.02, d + 0.1, look.Accent, k.metal)
	end
	tube(k, "MuzzleGlow", x, y, zTip + 0.01, zTip - 0.03, d * 0.64, look.Glow, NEON)
	return Vector3.new(x, y, zTip - 0.08)
end

-- Over-under twin barrels from zBack to zTip at heights yTop / yBot, one chunky accent
-- collar over both tips and a glowing bore in each; returns the muzzle point between them.
local function twin(k: Ctx, yTop: number, yBot: number, zBack: number, zTip: number, d: number): Vector3
	local look = k.look
	tube(k, "Barrel", 0, yTop, zBack, zTip, d, look.Dark, METAL)
	tube(k, "Barrel2", 0, yBot, zBack, zTip, d, look.Dark, METAL)
	slab(k, "Collar", zTip + 0.16, zTip - 0.01, yBot - d / 2 - 0.08, yTop + d / 2 + 0.08, d + 0.14, look.Accent, k.metal)
	tube(k, "MuzzleGlow", 0, yTop, zTip - 0.01, zTip - 0.05, d * 0.66, look.Glow, NEON)
	tube(k, "MuzzleGlow2", 0, yBot, zTip - 0.01, zTip - 0.05, d * 0.66, look.Glow, NEON)
	return Vector3.new(0, (yTop + yBot) / 2, zTip - 0.1)
end

-- Skeleton stock: two rods from the body back to a tilted butt plate (top at buttTop).
local function skeleton(
	k: Ctx,
	zFrom: number,
	length: number,
	yTop: number,
	yBot: number,
	buttTop: number,
	buttH: number,
	tilt: number,
	color: Color3,
	material: Enum.Material
)
	local zEnd = zFrom + length
	rod(k, "StockRod", Vector3.new(0, yTop, zFrom - 0.05), Vector3.new(0, buttTop - 0.1, zEnd), 0.11, k.steel, k.metal)
	rod(k, "StockRod", Vector3.new(0, yBot, zFrom - 0.05), Vector3.new(0, buttTop - buttH + 0.12, zEnd), 0.11, k.steel, k.metal)
	local butt = CFrame.new(0, buttTop - buttH / 2, zEnd + 0.05) * CFrame.Angles(tilt, 0, 0)
	k.part("Butt", butt, Vector3.new(0.42, buttH, 0.16), color, material)
end

-- Scope: dark tube, steel eyepiece ring and front bell, glowing lens, one low rail mount.
local function scope(k: Ctx, zBack: number, zFront: number, y: number, d: number, mountBack: number, mountFront: number, base: number)
	local look = k.look
	tube(k, "Scope", 0, y, zBack - 0.06, zFront + 0.16, d, look.Dark, METAL)
	tube(k, "ScopeEye", 0, y, zBack, zBack - 0.16, d * 1.3, k.steel, k.metal)
	tube(k, "ScopeBell", 0, y, zFront + 0.22, zFront, d * 1.45, k.steel, k.metal)
	tube(k, "Lens", 0, y, zFront + 0.01, zFront - 0.03, d * 0.9, look.Glow, NEON)
	slab(k, "ScopeMount", mountBack, mountFront, base - 0.04, y - d * 0.3, 0.14, k.steel, k.metal)
end

---------------------------------------------------------------- the ten guns

local GRIPS: { Grip } = {
	{ Z = 0.18, Length = 0.62 },
	{ Z = 0.2, Length = 0.62 },
	{ Z = 0.3, Length = 0.62 },
	{ Z = 0.3, Length = 0.64 },
	{ Z = 0.16, Length = 0.64 },
	{ Z = 0.26, Length = 0.64 },
	{ Z = 0.36, Length = 0.64 },
	{ Z = 0.44, Length = 0.64 },
	{ Z = 0.46, Length = 0.66 },
	{ Z = 0.5, Length = 0.66 },
}

-- Each design builds its parts (besides the Handle) and returns the muzzle point.
local DESIGNS: { (k: Ctx) -> Vector3 } = {
	-- 1 Rusty Blaster: a small junk pistol (blaster-b): steel lower band with a chamfered back,
	-- a dull dark nose with raked corners, a crooked rust patch with a bolt
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.5, -0.5, 0.62, w, 0.2, 0, 0.26, true)
		slab(k, "Nose", -0.46, -0.74, -0.14, 0.58, w + 0.04, RUST_NOSE, k.metal)
		wedge(k, "NoseRake", -0.74, -0.88, 0.36, 0.58, w + 0.04, UP_FRONT, RUST_NOSE, k.metal)
		wedge(k, "NoseChin", -0.46, -0.74, -0.32, -0.14, w + 0.04, DOWN_FRONT, RUST_NOSE, k.metal)
		carry(k, 0.32, -0.26, 0.62, 0.24)
		slot(k, 0.47, 0.06, -0.42, w, -0.18)
		core(k, 0.36, 0.3, w, 0.22)
		k.part(
			"Patch",
			CFrame.new(0, 0.21, -0.24) * CFrame.Angles(0.16, 0, 0),
			Vector3.new(w + 0.03, 0.22, 0.34),
			RUST_PATCH,
			look.BodyMaterial
		)
		disc(k, "Bolt", 0.25, -0.34, w + 0.07, 0.08, k.steel, k.metal)
		guard(k, 0.12, -0.48)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.24, -0.7, -1.06, 0.26, false, k.steel)
	end,
	-- 2 Scrap Blaster: raked top front, big chamfered steel front block with the barrel,
	-- body-colored magazine pad (blaster-c)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.52, -0.64, 0.64, w, 0.18, 0, 0.22)
		wedge(k, "BodyRake", -0.64, -0.86, 0.38, 0.64, w, UP_FRONT, look.Body, look.BodyMaterial)
		slab(k, "Block", -0.5, -0.92, -0.3, 0.4, w + 0.04, k.steel, k.metal)
		wedge(k, "BlockChin", -0.5, -0.92, -0.52, -0.3, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		disc(k, "Bolt", -0.14, -0.7, w + 0.08, 0.08, look.Dark, k.metal)
		wedge(k, "Sight", -0.36, -0.56, 0.64, 0.82, 0.12, UP_FRONT, k.steel, k.metal)
		carry(k, 0.36, -0.22, 0.64, 0.24)
		slot(k, 0.47, 0.3, -0.42, w, -0.08)
		core(k, 0.28, 0.3, w, 0.2)
		guard(k, 0.14, -0.52)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.1, -0.86, -1.14, 0.26, true)
	end,
	-- 3 Spark Blaster: SMG with a rear tube, a steel side panel with the core, a square steel
	-- barrel and a chamfered magazine (blaster-a)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		local front = darker(k.steel, 0.14)
		receiver(k, 0.72, -0.66, 0.64, w, 0.16, 0, 0.2)
		tube(k, "RearTube", 0, 0.42, 1.06, 0.64, 0.38, look.Body, look.BodyMaterial)
		slab(k, "SidePanel", 0.46, -0.48, 0.2, 0.5, w + 0.06, k.steel, k.metal)
		disc(k, "Bolt", 0.35, 0.34, w + 0.1, 0.08, look.Dark, k.metal)
		slab(k, "Front", -0.6, -0.94, 0.0, 0.76, w + 0.04, front, k.metal)
		wedge(k, "FrontChin", -0.6, -0.94, -0.18, 0.0, w + 0.04, DOWN_FRONT, front, k.metal)
		wedge(k, "Sight", -0.62, -0.8, 0.76, 0.92, 0.12, UP_FRONT, front, k.metal)
		slab(k, "Magazine", -0.22, -0.56, -0.56, 0.02, 0.42, k.steel, k.metal)
		wedge(k, "MagChin", -0.22, -0.56, -0.74, -0.56, 0.42, DOWN_FRONT, k.steel, k.metal)
		carry(k, 0.5, -0.46, 0.64, 0.22)
		core(k, 0.35, -0.1, w + 0.06, 0.24, look.Accent)
		guard(k, 0.24, -0.24)
		pommel(k, k.steel, k.metal)
		slab(k, "Barrel", -0.92, -1.32, 0.42, 0.68, 0.44, k.steel, k.metal)
		tube(k, "MuzzleGlow", 0, 0.55, -1.31, -1.35, 0.16, look.Glow, NEON)
		return Vector3.new(0, 0.55, -1.4)
	end,
	-- 4 Ember Blaster: carbine with a steel rear block, a tall raked steel nose with a sight,
	-- a steel lower handguard under the barrel, a slot with a lever (blaster-j)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.76, -0.7, 0.6, w, 0.18, 0, 0.22)
		slab(k, "RearBlock", 0.92, 0.72, 0.1, 0.5, w - 0.12, k.steel, k.metal)
		slab(k, "Nose", -0.64, -0.96, 0.04, 0.74, w + 0.04, k.steel, k.metal)
		wedge(k, "NoseRake", -0.96, -1.12, 0.52, 0.74, w + 0.04, UP_FRONT, k.steel, k.metal)
		wedge(k, "Sight", -0.68, -0.84, 0.74, 0.86, 0.12, UP_FRONT, k.steel, k.metal)
		slab(k, "Handguard", -0.42, -1.28, -0.22, 0.08, w - 0.1, k.steel, k.metal)
		slab(k, "Magazine", -0.04, -0.4, -0.62, -0.18, 0.42, k.steel, k.metal)
		carry(k, 0.62, 0.1, 0.6, 0.24)
		slot(k, 0.42, 0.28, -0.42, w, 0.04)
		core(k, 0.3, 0.52, w, 0.2)
		guard(k, 0.24, -0.06)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.42, -0.96, -1.4, 0.26, false)
	end,
	-- 5 Forgefire Blaster: bullpup with a steel top ramp + sight block, a round rear cap, a
	-- body-colored front with a raked top, the barrel in a mouth over a raked chin (blaster-m)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 0.8, -0.5, 0.52, w, 0.16, 0, 0.2)
		tube(k, "RearCap", 0, 0.28, 1.12, 0.76, 0.42, look.Accent, k.metal)
		wedge(k, "TopRamp", 0.72, 0.26, 0.5, 0.8, w - 0.14, UP_BACK, k.steel, k.metal)
		slab(k, "TopCover", 0.26, -0.5, 0.5, 0.8, w - 0.14, k.steel, k.metal)
		slab(k, "SightBlock", 0.06, -0.24, 0.78, 0.96, 0.16, look.Accent, k.metal)
		slab(k, "Front", -0.44, -0.88, -0.02, 0.66, w + 0.04, look.Body, look.BodyMaterial)
		wedge(k, "FrontRake", -0.88, -1.08, 0.3, 0.66, w + 0.04, UP_FRONT, look.Body, look.BodyMaterial)
		slab(k, "LowerFront", -0.34, -0.82, -0.28, 0.0, w - 0.08, k.steel, k.metal)
		wedge(k, "LowerChin", -0.82, -1.0, -0.28, 0.0, w - 0.08, DOWN_FRONT, k.steel, k.metal)
		litSlot(k, 0.3, 0.64, 0.02, w, 0.36)
		core(k, 0.4, -0.66, w + 0.04, 0.22)
		guard(k, 0.1, -0.36)
		pommel(k, look.Accent, k.metal)
		return barrel(k, "Barrel", 0, 0.18, -0.9, -1.3, 0.26, true)
	end,
	-- 6 Sunlance: short skeleton stock, steel hump, long top shroud with a front hook,
	-- a chamfered body-colored foregrip (blaster-g)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.62, -0.62, 0.6, w, 0.16, 0, 0.2)
		skeleton(k, 0.62, 0.56, 0.48, 0.14, 0.58, 0.6, 0.16, look.Body, look.BodyMaterial)
		slab(k, "Hump", 0.32, -0.18, 0.6, 0.86, w - 0.16, k.steel, k.metal)
		wedge(k, "HumpSlope", 0.52, 0.32, 0.6, 0.86, w - 0.16, UP_BACK, k.steel, k.metal)
		slab(k, "Shroud", -0.18, -1.42, 0.42, 0.78, w - 0.12, k.steel, k.metal)
		slab(k, "ShroudHook", -1.28, -1.42, 0.2, 0.44, w - 0.22, k.steel, k.metal)
		slab(k, "Foregrip", -0.3, -0.82, -0.24, 0.02, w - 0.08, look.Body, look.BodyMaterial)
		wedge(k, "ForeChin", -0.82, -1.0, -0.24, 0.02, w - 0.08, DOWN_FRONT, look.Body, look.BodyMaterial)
		slot(k, 0.3, 0.44, -0.2, w, 0.18)
		core(k, 0.3, -0.42, w, 0.22)
		guard(k, 0.2, -0.32)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.6, -1.2, -1.76, 0.24, true)
	end,
	-- 7 Stormlance: scope on a rail mount, raked steel shroud with a lit slot, forward-tilted
	-- magazine, solid stock with a heel (blaster-r)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 0.86, -0.66, 0.64, w, 0, 0, 0)
		slab(k, "Stock", 1.72, 0.82, 0.24, 0.6, w - 0.14, look.Body, look.BodyMaterial)
		wedge(k, "StockHeel", 1.72, 1.2, -0.04, 0.25, w - 0.16, DOWN_FRONT, look.Body, look.BodyMaterial)
		scope(k, 0.5, -0.46, 0.85, 0.22, 0.3, -0.24, 0.64)
		slab(k, "Shroud", -0.6, -1.36, 0.08, 0.72, w + 0.04, k.steel, k.metal)
		wedge(k, "ShroudRake", -1.36, -1.62, 0.08, 0.72, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		k.part("Magazine", CFrame.new(0, -0.25, -0.3) * CFrame.Angles(0.14, 0, 0), Vector3.new(0.44, 0.56, 0.38), k.steel, k.metal)
		litSlot(k, 0.44, -0.72, -1.24, w + 0.04)
		slot(k, 0.46, 0.7, 0.12, w, 0.4)
		core(k, 0.3, -0.36, w, 0.22)
		guard(k, 0.3, -0.1)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.3, -1.36, -1.86, 0.24, true)
	end,
	-- 8 Starlance: skeleton stock, long dark top rail with sights, a steel handguard with a lit
	-- slot, over-under twin barrels poking out with a collar, body-colored magazine (blaster-p)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.92, -0.6, 0.62, w, 0.16, 0, 0.2)
		skeleton(k, 0.92, 0.84, 0.5, 0.12, 0.6, 0.66, 0.12, look.Body, look.BodyMaterial)
		slab(k, "TopRail", 0.78, -1.44, 0.58, 0.7, 0.28, look.Dark, k.metal)
		wedge(k, "Sight", -1.16, -1.36, 0.7, 0.88, 0.12, UP_FRONT, k.steel, k.metal)
		slab(k, "Handguard", -0.54, -1.5, 0.04, 0.6, 0.52, k.steel, k.metal)
		wedge(k, "HandguardRake", -1.5, -1.64, 0.3, 0.6, 0.52, UP_FRONT, k.steel, k.metal)
		litSlot(k, 0.32, -0.66, -1.36, 0.52)
		slab(k, "Magazine", 0.08, -0.34, -0.56, 0.02, 0.44, look.Body, look.BodyMaterial)
		slot(k, 0.46, 0.4, -0.44, w, -0.2)
		core(k, 0.3, 0.62, w, 0.22)
		guard(k, 0.38, 0.1)
		pommel(k, k.steel, k.metal)
		return twin(k, 0.46, 0.2, -1.3, -1.84, 0.18)
	end,
	-- 9 Royal Sunlance: the body stretched forward into a raked handguard with a lit slot,
	-- an angled skeleton stock, the scope on a rail mount, twin barrels (blaster-d)
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.86, -0.56, 0.64, w, 0, 0, 0)
		slab(k, "Handguard", -0.5, -1.56, 0.1, 0.58, w - 0.08, look.Body, look.BodyMaterial)
		wedge(k, "HandguardRake", -1.56, -1.8, 0.1, 0.58, w - 0.08, UP_FRONT, look.Body, look.BodyMaterial)
		skeleton(k, 0.86, 0.86, 0.56, 0.08, 0.66, 0.56, 0.34, look.Body, look.BodyMaterial)
		scope(k, 0.56, -0.5, 0.89, 0.24, 0.36, -0.28, 0.64)
		slab(k, "Magazine", -0.12, -0.52, -0.6, 0.02, 0.44, k.steel, k.metal)
		litSlot(k, 0.36, -0.62, -1.4, w - 0.08, -0.74)
		core(k, 0.32, 0.5, w, 0.22)
		guard(k, 0.4, -0.1)
		pommel(k, look.Body, look.BodyMaterial)
		return twin(k, 0.46, 0.22, -1.5, -2.1, 0.18)
	end,
	-- 10 Heartlance: long slim sniper (blaster-e): closed loop stock, big scope, a long steel
	-- handguard with a glowing energy cell inline, a coil collar with a glowing ring, over-under
	-- barrels, a ported muzzle brake with the glow in front
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.6
		receiver(k, 0.84, -0.6, 0.58, w, 0, 0, 0)
		-- the closed loop stock: top rod + bottom rod + butt, all in the accent metal
		rod(k, "StockRod", Vector3.new(0, 0.5, 0.8), Vector3.new(0, 0.5, 1.66), 0.12, look.Accent, k.metal)
		rod(k, "StockRod", Vector3.new(0, 0.1, 0.8), Vector3.new(0, -0.02, 1.66), 0.12, look.Accent, k.metal)
		k.part("Butt", CFrame.new(0, 0.24, 1.72) * CFrame.Angles(0.1, 0, 0), Vector3.new(0.4, 0.7, 0.16), look.Accent, k.metal)
		scope(k, 0.62, -0.56, 0.86, 0.26, 0.4, -0.32, 0.58)
		-- the long handguard in two steel sections, the energy cell glowing inline between them
		slab(k, "Handguard", -0.54, -1.2, 0.14, 0.54, 0.44, k.steel, k.metal)
		tube(k, "Cell", 0, 0.34, -1.18, -1.58, 0.34, look.GlowSoft, NEON)
		slab(k, "HandguardFront", -1.56, -1.98, 0.14, 0.54, 0.44, k.steel, k.metal)
		tube(k, "Collar", 0, 0.34, -1.94, -2.12, 0.54, look.Accent, k.metal)
		tube(k, "CoilRing", 0, 0.34, -2.0, -2.05, 0.6, look.GlowSoft, NEON)
		tube(k, "Barrel", 0, 0.45, -1.8, -2.84, 0.17, look.Dark, METAL)
		tube(k, "Barrel2", 0, 0.23, -1.8, -2.84, 0.17, look.Dark, METAL)
		tube(k, "Brake", 0, 0.34, -2.66, -2.98, 0.48, look.Accent, k.metal)
		slab(k, "BrakePorts", -2.74, -2.88, 0.3, 0.38, 0.52, SLOT, k.metal)
		tube(k, "MuzzleGlow", 0, 0.34, -2.97, -3.01, 0.3, look.Glow, NEON)
		slab(k, "Magazine", -0.16, -0.56, -0.62, 0.02, 0.44, k.steel, k.metal)
		litSlot(k, 0.3, 0.62, -0.42, w)
		guard(k, 0.44, -0.14)
		pommel(k, look.Accent, k.metal)
		return Vector3.new(0, 0.34, -3.08)
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
