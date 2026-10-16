--[[
	Builds the laser Blaster tool (design v2, replaces the pickaxe): chunky,
	toy-like guns after the Kenney Blaster Kit (blaster-a ... blaster-r, CC0),
	rebuilt from parts (never meshes).

	Design frame (studs): the barrel points along -Z, +Y is up, +X is the
	gun's right side, the body's bottom is y = 0. The Handle is the pistol
	grip, tilted back like a real grip; Tool.Grip puts the hand on it and
	keeps the barrel straight along the arm (in the R15 tool pose the grip
	attachment's -Z points forward). Muzzle = Attachment on the Handle at the
	barrel tip (the client beam starts there). Long guns keep their stock end
	within ~1.1 studs behind the hand, so it rests over the forearm and does
	not sink into the shoulder in the R15 hold.

	Kit pieces, all shared by the levels:
	  bevelBox   Kenney's soft toy-plastic box: a full-width slab plus an
	             inner slab that is narrower and shorter but reaches the full
	             height, so every long edge shows a small lit step (bevel)
	  receiver   the colored body (a bevelBox); its bottom corners can be
	             chamfered (Body + Belly + a wedge per corner) and the belly
	             can be Kenney's steel lower band (two-tone, like b / c / j)
	  carry      the thick Kenney carry handle on top (bar + 2 posts)
	  slot       Kenney's dark side slot with a small lever sticking out
	             (light grey ores: the slot glows in the ore glow instead)
	  litSlot    the same slot with a thin glowing strip inside (a vent)
	  core       a small glowing power light framed by a steel bezel
	  barrel     dark round barrel (+ a slim accent tip ring) + glowing muzzle disc
	  twin       over-under twin barrels poking out of a handguard, a round
	             steel collar around both, a glowing bore in each
	  skeleton   skeleton stock: two rods + a tilted butt plate
	  scope      dark tube, steel eyepiece ring and front bell seated on the
	             body, glowing lens
	  pommel     the pad at the bottom of the grip: big wrap-around pads on
	             the pistols, small flush pads on the carbines, slim grips
	             with small pads on the rifles
	  guard      the trigger guard bar
	  plus per-level steel noses and front blocks (bevelled, with chamfered
	  chins and sight fins), shrouds, handguards, magazines, humps, stocks,
	  an energy cell framed by a dark cap and the collar, a muzzle brake.

	Every level is its own gun, bigger and fancier with the level
	(the part counts never drop, the test checks it):
	  1 Rusty      pistol (b): light rust body on a steel band, steel nose    21 parts
	  2 Scrap      pistol (c): steel band, big steel block with a chin        21
	  3 Spark      SMG (a): rear tube, steel side panel, dark front           22
	  4 Ember      carbine (j): steel band, rear block, nose with a sight     22
	  5 Forgefire  bullpup (m): steel ramp, raked mouth, rear cap, vent       23
	  6 Sunlance   (g): skeleton stock, steel band, hump, top shroud, hook    24
	  7 Stormlance (r): scope, raked shroud with a vent, stock + butt pad     24
	  8 Starlance  (p): skeleton stock, short scope, vented handguard, twin   25
	  9 Royal      (d): raked body handguard, angled stock, scope, twin       25
	 10 Heartlance sniper (e): loop stock, framed energy cell, long exposed
	               twin barrels, muzzle brake with two bores                  25
	Budget: <= 25 parts. Colors follow the ore the blaster was forged from
	(BlasterData.skin): body, stock and accents (levers, pads, brake) in the
	ore colors, glows (core, muzzle, vents, lens, cell) in the ore glow,
	Kenney's light steel for front blocks, handles and magazines (dark steel
	next to light grey ores); level 1 (or no ore) is the rusty starter.
	Bright glows are pulled toward the body color and darkened (by
	luminance), so neon never blooms into white blobs; the beam (Look.Glow,
	attribute Glow) keeps the ore's own glow.

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
BlasterBuilder.MaxParts = 25
BlasterBuilder.Scale = 1.2 -- design studs -> held studs (level 1 is ~2.4 studs long, level 10 ~5.6)

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local SLOT = Color3.fromRGB(34, 34, 40) -- the dark side slots
local STEEL = Color3.fromRGB(150, 158, 180) -- Kenney's light blue-grey steel (front blocks, handles, magazines)
local STEEL_DARK = Color3.fromRGB(70, 73, 84) -- steel next to light grey ore bodies (two-tone instead of grey on grey)
local WOOD = Color3.fromRGB(110, 70, 42)
local RUST_WARM = Color3.fromRGB(198, 108, 56) -- the starter's body is pulled toward this warm rust
local RUST_STEEL = Color3.fromRGB(140, 132, 124) -- the starter's light worn steel
local RUST_PATCH = Color3.fromRGB(122, 66, 38) -- the rust patch on the starter's nose (the only corroded part)

-- Cylinder whose axis runs along Z (Roblox cylinders run along X).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal -- barrels and scope tubes keep a little sheen
local PLASTIC = Enum.Material.SmoothPlastic

-- Wedge orientations (a WedgePart's slope faces -Z and up, the high edge at +Z).
local UP_FRONT = CFrame.identity -- the top-front corner is cut away
local UP_BACK = CFrame.Angles(0, math.pi, 0) -- the top-back corner is cut away
local DOWN_FRONT = CFrame.Angles(0, 0, math.pi) -- the bottom-front corner is cut away
local DOWN_BACK = CFrame.Angles(math.pi, 0, 0) -- the bottom-back corner is cut away

local BEVEL = 0.05 -- the step of a bevelBox (design studs)

export type Look = {
	Level: number,
	Rusty: boolean,
	Body: Color3,
	Accent: Color3,
	Glow: Color3, -- the ore's own glow: the beam color (attribute Glow)
	GlowSoft: Color3, -- bigger glowing pieces (vents, lit slots)
	GlowCore: Color3, -- small glowing pieces (core, muzzle, lens, cell)
	Dark: Color3,
	Grip: Color3,
	Steel: Color3,
	BodyMaterial: Enum.Material,
	SteelMaterial: Enum.Material,
	LitSlots: boolean, -- light grey bodies: the side slots glow (one clear color accent)
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
	gripInfo: Grip,
}

-- The pad at the bottom of a grip: its size and how far it sits forward / up from the grip's end.
type Pad = { Size: Vector3, Forward: number, Up: number }

-- The grip of a level: top center at (0, GRIP_TOP, Z), Length long, Width x Depth thick.
type Grip = { Z: number, Length: number, Width: number, Depth: number, Pad: Pad }

local GRIP_TOP = 0.06
local GRIP_TILT = 0.28 -- radians, the bottom leans back
local HAND_DOWN = 0.28 -- the hand sits this far below the top of the grip

-- Kenney's grip pads: big wrap-around pads on the pistols (b, c), small flush pads on the
-- carbines, slim grips with a small pad on the rifles (d, e, p).
local BIG_PAD: Pad = { Size = Vector3.new(0.44, 0.16, 0.56), Forward = 0.06, Up = 0.04 }
local FLUSH_PAD: Pad = { Size = Vector3.new(0.36, 0.1, 0.46), Forward = 0.02, Up = 0.03 }
local SLIM_PAD: Pad = { Size = Vector3.new(0.34, 0.12, 0.44), Forward = 0.03, Up = 0.04 }

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

local function luma(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

--[[
	Neon blooms into a white blob when all three channels are high (bright cyan, gold,
	mint and pale glows). Decided by luminance: the brighter the glow, the more it is
	saturated (one channel drops, so it glows in its color instead of white) and a
	little dimmed; near-white glows (diamond, quartz) only get a hint of their hue and
	are dimmed more. `amount` = how much dimmer in general.
]]
local function softGlow(glow: Color3, amount: number): Color3
	local hue, sat, v = glow:ToHSV()
	local bright = math.clamp((luma(glow) - 0.4) / 0.35, 0, 1)
	local colored = math.clamp((sat - 0.08) / 0.2, 0, 1)
	local target = 0.35 + 0.5 * colored
	local s = sat + math.max(0, target - sat) * bright
	local dim = amount + (0.25 + 0.08 * (1 - colored)) * bright
	return Color3.fromHSV(hue, s, v * (1 - dim))
end

-- The colors of a blaster (also used for the beam color: Look.Glow).
function BlasterBuilder.look(level: any, oreId: string?): Look
	local info = BlasterData.get(level)
	local rusty = info.Level <= 1 or not oreId or oreId == ""
	local body, glow = BlasterData.skin(if rusty then "" else oreId)
	if rusty then
		-- a light warm rust body that reads at game distance; the corrosion is only on the patch
		local rust = lighter(body, 0.12):Lerp(RUST_WARM, 0.5)
		return {
			Level = info.Level,
			Rusty = true,
			Body = rust,
			Accent = Color3.fromRGB(122, 74, 46),
			Glow = glow,
			GlowSoft = softGlow(glow, 0.2),
			GlowCore = softGlow(glow, 0.05),
			Dark = darker(IRON, 0.25),
			Grip = WOOD,
			Steel = RUST_STEEL,
			BodyMaterial = PLASTIC,
			SteelMaterial = PLASTIC,
			LitSlots = false,
		}
	end
	-- very dark ores (coal, obsidian) keep a readable body
	local _, sat, v = body:ToHSV()
	if v < 0.32 then
		body = lighter(body, 0.18)
	end
	-- light grey bodies (silver, iron, quartz, diamond, moonstone): dark steel and glowing slots,
	-- so the gun stays two-tone and keeps one clear color accent
	local greyish = sat < 0.3 and v > 0.5
	return {
		Level = info.Level,
		Rusty = false,
		Body = body,
		-- accents are a darker body color (a lighter one vanished next to the body)
		Accent = if v < 0.45 then lighter(body, 0.45) else darker(body, if v > 0.85 then 0.3 else 0.25),
		Glow = glow,
		GlowSoft = softGlow(glow, 0.2),
		GlowCore = softGlow(glow, 0.05),
		Dark = if v < 0.32 then IRON_LIGHT elseif greyish then darker(IRON, 0.3) else IRON,
		Grip = IRON:Lerp(body, 0.12),
		Steel = if greyish then STEEL_DARK else STEEL,
		BodyMaterial = PLASTIC,
		SteelMaterial = PLASTIC, -- Kenney's steel is flat, like toy plastic
		LitSlots = greyish,
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

--[[
	Kenney's soft toy-plastic box from two slabs: the main slab is full width and
	length but BEVEL lower at the top (and bottom), the inner slab is BEVEL narrower
	on each side and shorter at each end but reaches the full height. The cross
	section is stepped, so the long edges and the top end edges catch a thin
	highlight and the side silhouette has soft corners. flatBottom keeps the bottom
	square (the box sits on a belly band).
]]
local function bevelBox(
	k: Ctx,
	name: string,
	zBack: number,
	zFront: number,
	yBot: number,
	yTop: number,
	w: number,
	color: Color3,
	material: Enum.Material?,
	flatBottom: boolean?
): BasePart
	local b = BEVEL
	local main = slab(k, name, zBack, zFront, if flatBottom then yBot else yBot + b, yTop - b, w, color, material)
	slab(k, name .. "Bevel", zBack - b, zFront + b, if flatBottom then yBot + 0.02 else yBot, yTop, w - 2 * b, color, material)
	return main
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
	The colored body, h tall and w wide, a bevelBox. Its bottom corners can be
	chamfered (c tall, cf deep at the front, cb deep at the back): the Body sits
	above, the Belly below it is shortened and a wedge fills each chamfered corner.
	steelBelly turns the lower band into Kenney's steel strip (two-tone).
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
	if c <= 0 or (cf <= 0 and cb <= 0 and not steelBelly) then
		bevelBox(k, "Body", zBack, zFront, 0, h, w, color, material)
		return
	end
	local bellyColor = if steelBelly then k.steel else color
	local bellyMaterial = if steelBelly then k.metal else material
	bevelBox(k, "Body", zBack, zFront, c, h, w, color, material, true)
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
-- On light grey bodies the slot glows instead (the ore's color accent).
local function slot(k: Ctx, y: number, zBack: number, zFront: number, w: number, leverZ: number?)
	if k.look.LitSlots then
		slab(k, "Slot", zBack, zFront, y - 0.035, y + 0.035, w + 0.02, k.look.GlowSoft, NEON)
	else
		slab(k, "Slot", zBack, zFront, y - 0.04, y + 0.04, w + 0.02, SLOT, k.metal)
	end
	if leverZ then
		lever(k, y, leverZ, w)
	end
end

-- A lit slot: a dark slot frame with a thin glowing strip inside (a vent).
local function litSlot(k: Ctx, y: number, zBack: number, zFront: number, w: number)
	slab(k, "VentFrame", zBack, zFront, y - 0.06, y + 0.06, w + 0.02, SLOT, k.metal)
	slab(k, "Vent", zBack - 0.05, zFront + 0.05, y - 0.025, y + 0.025, w + 0.04, k.look.GlowSoft, NEON)
end

-- The glowing core: a small power light framed by a steel bezel, through the body (seen on both sides).
local function core(k: Ctx, y: number, z: number, w: number, d: number, bezel: Color3?)
	disc(k, "CoreHousing", y, z, w + 0.04, d, bezel or k.steel, k.metal)
	disc(k, "Core", y, z, w + 0.06, d * 0.5, k.look.GlowCore, NEON)
end

-- The trigger guard: a bar from the grip forward to the part in front.
local function guard(k: Ctx, zBack: number, zFront: number)
	slab(k, "Guard", zBack, zFront, -0.32, -0.22, 0.12, k.steel, k.metal)
end

-- The pad at the bottom of the grip (big wrap-around, flush or slim, per level).
local function pommel(k: Ctx, color: Color3, material: Enum.Material)
	local pad = k.gripInfo.Pad
	local cf = k.grip * CFrame.new(0, -k.gripInfo.Length / 2 + pad.Up, -pad.Forward)
	k.part("Pommel", cf, pad.Size, color, material)
end

-- Dark round barrel + glowing muzzle disc (+ steel muzzle ring); returns the muzzle point.
local function barrel(k: Ctx, name: string, x: number, y: number, zBack: number, zTip: number, d: number, ring: boolean): Vector3
	local look = k.look
	tube(k, name, x, y, zBack, zTip, d, look.Dark, METAL)
	if ring then
		tube(k, "MuzzleRing", x, y, zTip + 0.14, zTip + 0.02, d + 0.06, look.Accent, k.metal)
	end
	tube(k, "MuzzleGlow", x, y, zTip + 0.01, zTip - 0.03, d * 0.6, look.GlowCore, NEON)
	return Vector3.new(x, y, zTip - 0.08)
end

-- Over-under twin barrels from zBack to zTip at heights yTop / yBot, a round steel collar
-- around both (collarBack..collarFront) and a glowing bore in each; returns the muzzle point.
local function twin(k: Ctx, yTop: number, yBot: number, zBack: number, zTip: number, d: number, collarBack: number, collarFront: number): Vector3
	local look = k.look
	local mid = (yTop + yBot) / 2
	tube(k, "Barrel", 0, yTop, zBack, zTip, d, look.Dark, METAL)
	tube(k, "Barrel2", 0, yBot, zBack, zTip, d, look.Dark, METAL)
	tube(k, "Collar", 0, mid, collarBack, collarFront, yTop - yBot + d + 0.14, k.steel, k.metal)
	tube(k, "MuzzleGlow", 0, yTop, zTip + 0.01, zTip - 0.03, d * 0.62, look.GlowCore, NEON)
	tube(k, "MuzzleGlow2", 0, yBot, zTip + 0.01, zTip - 0.03, d * 0.62, look.GlowCore, NEON)
	return Vector3.new(0, mid, zTip - 0.1)
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

-- Scope: dark tube, a steel eyepiece ring and front bell seated on the body top (base), glowing lens.
local function scope(k: Ctx, zBack: number, zFront: number, base: number, d: number)
	local look = k.look
	local ring = d * 1.4
	local y = base + ring / 2 - 0.01
	tube(k, "Scope", 0, y, zBack - 0.06, zFront + 0.12, d, look.Dark, METAL)
	tube(k, "ScopeEye", 0, y, zBack, zBack - 0.16, ring, k.steel, k.metal)
	tube(k, "ScopeBell", 0, y, zFront + 0.2, zFront, ring, k.steel, k.metal)
	tube(k, "Lens", 0, y, zFront + 0.01, zFront - 0.03, d * 0.86, look.GlowCore, NEON)
end

---------------------------------------------------------------- the ten guns

local GRIPS: { Grip } = {
	{ Z = 0.2, Length = 0.54, Width = 0.32, Depth = 0.4, Pad = BIG_PAD },
	{ Z = 0.22, Length = 0.56, Width = 0.32, Depth = 0.4, Pad = BIG_PAD },
	{ Z = 0.32, Length = 0.58, Width = 0.32, Depth = 0.4, Pad = BIG_PAD },
	{ Z = 0.34, Length = 0.62, Width = 0.3, Depth = 0.38, Pad = FLUSH_PAD },
	{ Z = 0.16, Length = 0.62, Width = 0.3, Depth = 0.38, Pad = FLUSH_PAD },
	{ Z = 0.32, Length = 0.62, Width = 0.3, Depth = 0.38, Pad = FLUSH_PAD },
	{ Z = 0.5, Length = 0.62, Width = 0.3, Depth = 0.38, Pad = FLUSH_PAD },
	{ Z = 0.6, Length = 0.64, Width = 0.26, Depth = 0.36, Pad = SLIM_PAD },
	{ Z = 0.62, Length = 0.64, Width = 0.26, Depth = 0.36, Pad = SLIM_PAD },
	{ Z = 0.66, Length = 0.66, Width = 0.26, Depth = 0.36, Pad = SLIM_PAD },
}

-- Each design builds its parts (besides the Handle) and returns the muzzle point.
local DESIGNS: { (k: Ctx) -> Vector3 } = {
	-- 1 Rusty Blaster: a small junk pistol (blaster-b): light rust body on a steel lower band
	-- with a chamfered back, a light steel nose with a chamfered chin, a sight fin and a crooked
	-- corroded patch, the dark barrel mouth in it
	function(k: Ctx): Vector3
		local w = 0.62
		receiver(k, 0.5, -0.54, 0.62, w, 0.24, 0, 0.26, true)
		bevelBox(k, "Nose", -0.48, -0.84, -0.1, 0.58, w + 0.04, k.steel, k.metal)
		wedge(k, "NoseChin", -0.48, -0.84, -0.28, -0.1, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		wedge(k, "Sight", -0.54, -0.7, 0.58, 0.74, 0.12, UP_FRONT, k.steel, k.metal)
		carry(k, 0.32, -0.26, 0.62, 0.24)
		slot(k, 0.47, 0.34, -0.16, w, 0.1)
		core(k, 0.4, -0.33, w, 0.2)
		k.part(
			"Patch",
			CFrame.new(0, 0.04, -0.68) * CFrame.Angles(0.22, 0, 0),
			Vector3.new(w + 0.07, 0.15, 0.2),
			RUST_PATCH,
			Enum.Material.CorrodedMetal
		)
		guard(k, 0.12, -0.5)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.28, -0.76, -1.06, 0.32, false)
	end,
	-- 2 Scrap Blaster: pistol (blaster-c): steel lower band, a big steel front block with a
	-- chamfered chin down to the guard line and a sight fin, body-colored pad, muzzle ring
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.52, -0.62, 0.64, w, 0.2, 0, 0.22, true)
		bevelBox(k, "Block", -0.5, -0.94, -0.2, 0.58, w + 0.04, k.steel, k.metal)
		wedge(k, "BlockChin", -0.5, -0.94, -0.42, -0.2, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		wedge(k, "Sight", -0.6, -0.78, 0.58, 0.78, 0.12, UP_FRONT, k.steel, k.metal)
		carry(k, 0.36, -0.22, 0.64, 0.24)
		slot(k, 0.48, 0.36, -0.2, w, 0.1)
		core(k, 0.38, -0.36, w, 0.2)
		guard(k, 0.14, -0.5)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.2, -0.86, -1.16, 0.3, true)
	end,
	-- 3 Spark Blaster: SMG (blaster-a) with a rear tube, a steel side panel with the core,
	-- a darker steel front flush with the body with a sight fin, a round barrel, a short magazine
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		local front = darker(k.steel, 0.14)
		receiver(k, 0.72, -0.66, 0.64, w, 0.16, 0, 0.2)
		tube(k, "RearTube", 0, 0.42, 1.06, 0.64, 0.38, look.Body, look.BodyMaterial)
		slab(k, "SidePanel", 0.46, -0.48, 0.2, 0.5, w + 0.06, k.steel, k.metal)
		bevelBox(k, "Front", -0.6, -0.94, 0.0, 0.62, w + 0.04, front, k.metal)
		wedge(k, "FrontChin", -0.6, -0.94, -0.18, 0.0, w + 0.04, DOWN_FRONT, front, k.metal)
		wedge(k, "Sight", -0.66, -0.82, 0.62, 0.78, 0.12, UP_FRONT, front, k.metal)
		slab(k, "Magazine", -0.24, -0.56, -0.38, 0.02, 0.42, k.steel, k.metal)
		carry(k, 0.5, -0.46, 0.64, 0.22)
		core(k, 0.35, -0.1, w + 0.06, 0.24, look.Accent)
		guard(k, 0.24, -0.24)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.36, -0.9, -1.3, 0.24, true)
	end,
	-- 4 Ember Blaster: carbine (blaster-j): body over a steel band, a small steel rear block,
	-- a steel nose just above the body with a sight fin, a steel magazine under the front
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.76, -0.66, 0.6, w, 0.2, 0, 0.22, true)
		slab(k, "RearBlock", 0.9, 0.72, 0.18, 0.44, w - 0.18, k.steel, k.metal)
		bevelBox(k, "Nose", -0.62, -0.96, 0.0, 0.64, w + 0.04, k.steel, k.metal)
		wedge(k, "Sight", -0.68, -0.84, 0.64, 0.8, 0.12, UP_FRONT, k.steel, k.metal)
		slab(k, "Magazine", -0.12, -0.5, -0.54, 0.02, 0.42, k.steel, k.metal)
		carry(k, 0.56, 0.06, 0.6, 0.24)
		slot(k, 0.44, 0.28, -0.44, w, 0.02)
		core(k, 0.34, 0.52, w, 0.2)
		guard(k, 0.26, -0.12)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.34, -0.9, -1.34, 0.26, true)
	end,
	-- 5 Forgefire Blaster: bullpup (blaster-m) with a steel top ramp + sight block, a round
	-- rear cap, a body-colored front with a raked top, the barrel in a mouth over a raked chin
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 0.8, -0.5, 0.52, w, 0.16, 0, 0.2)
		tube(k, "RearCap", 0, 0.28, 1.12, 0.76, 0.42, look.Accent, look.BodyMaterial)
		wedge(k, "TopRamp", 0.72, 0.26, 0.5, 0.8, w - 0.14, UP_BACK, k.steel, k.metal)
		slab(k, "TopCover", 0.26, -0.5, 0.5, 0.8, w - 0.14, k.steel, k.metal)
		slab(k, "SightBlock", 0.06, -0.24, 0.78, 0.96, 0.16, look.Accent, k.metal)
		bevelBox(k, "Front", -0.44, -0.88, -0.02, 0.66, w + 0.04, look.Body, look.BodyMaterial)
		wedge(k, "FrontRake", -0.83, -1.06, 0.3, 0.66, w + 0.04, UP_FRONT, look.Body, look.BodyMaterial)
		slab(k, "LowerFront", -0.34, -0.82, -0.28, 0.0, w - 0.08, k.steel, k.metal)
		wedge(k, "LowerChin", -0.82, -1.0, -0.28, 0.0, w - 0.08, DOWN_FRONT, k.steel, k.metal)
		litSlot(k, 0.3, 0.64, 0.02, w)
		core(k, 0.4, -0.66, w + 0.04, 0.22)
		guard(k, 0.08, -0.34)
		pommel(k, look.Accent, k.metal)
		return barrel(k, "Barrel", 0, 0.18, -0.9, -1.3, 0.26, true)
	end,
	-- 6 Sunlance (blaster-g): short skeleton stock, body over a steel band, steel hump, a top
	-- shroud with a hook over the barrel, a short steel foregrip raked at the back
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.62, -0.62, 0.6, w, 0.18, 0, 0.2, true)
		skeleton(k, 0.62, 0.5, 0.48, 0.16, 0.58, 0.58, 0.16, look.Body, look.BodyMaterial)
		slab(k, "Hump", 0.32, -0.18, 0.58, 0.84, w - 0.16, k.steel, k.metal)
		wedge(k, "HumpSlope", 0.52, 0.32, 0.58, 0.84, w - 0.16, UP_BACK, k.steel, k.metal)
		bevelBox(k, "Shroud", -0.18, -1.24, 0.42, 0.78, w - 0.12, k.steel, k.metal)
		slab(k, "ShroudHook", -1.1, -1.24, 0.22, 0.44, w - 0.22, k.steel, k.metal)
		slab(k, "Foregrip", -0.3, -0.7, -0.24, 0.02, w - 0.12, k.steel, k.metal)
		wedge(k, "ForeChin", -0.14, -0.3, -0.24, 0.02, w - 0.12, DOWN_BACK, k.steel, k.metal)
		slot(k, 0.32, 0.44, -0.2, w, 0.18)
		core(k, 0.36, -0.42, w, 0.22)
		guard(k, 0.24, -0.3)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.3, -0.5, -1.62, 0.24, true)
	end,
	-- 7 Stormlance (blaster-r): scope, raked steel shroud with a lit vent, forward-tilted
	-- magazine, a narrow stock with a dark butt pad
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 0.86, -0.66, 0.64, w, 0, 0, 0)
		slab(k, "Stock", 1.42, 0.82, 0.22, 0.58, w - 0.24, look.Body, look.BodyMaterial)
		slab(k, "ButtPad", 1.52, 1.4, -0.04, 0.64, w - 0.16, look.Dark, k.metal)
		scope(k, 0.5, -0.46, 0.64, 0.22)
		bevelBox(k, "Shroud", -0.6, -1.36, 0.08, 0.72, w + 0.04, k.steel, k.metal)
		wedge(k, "ShroudRake", -1.31, -1.62, 0.08, 0.72, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		k.part("Magazine", CFrame.new(0, -0.25, -0.3) * CFrame.Angles(0.14, 0, 0), Vector3.new(0.44, 0.56, 0.38), k.steel, k.metal)
		litSlot(k, 0.44, -0.72, -1.24, w + 0.04)
		slot(k, 0.46, 0.7, 0.12, w, 0.4)
		core(k, 0.3, -0.36, w, 0.22)
		guard(k, 0.42, -0.1)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.3, -1.36, -1.86, 0.24, true)
	end,
	-- 8 Starlance (blaster-p): skeleton stock, a short scope, a steel handguard with a lit
	-- slot, a steel magazine, over-under twin barrels poking out through a round collar
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.92, -0.6, 0.62, w, 0, 0, 0)
		skeleton(k, 0.92, 0.52, 0.5, 0.12, 0.6, 0.62, 0.12, look.Body, look.BodyMaterial)
		scope(k, 0.62, -0.28, 0.62, 0.2)
		slab(k, "Handguard", -0.54, -1.5, 0.04, 0.58, 0.52, k.steel, k.metal)
		wedge(k, "HandguardRake", -1.5, -1.64, 0.3, 0.58, 0.52, UP_FRONT, k.steel, k.metal)
		litSlot(k, 0.32, -0.66, -1.36, 0.52)
		slab(k, "Magazine", 0.26, -0.14, -0.56, 0.02, 0.44, k.steel, k.metal)
		slot(k, 0.46, 0.44, -0.44, w)
		core(k, 0.3, 0.72, w, 0.22)
		guard(k, 0.52, 0.24)
		pommel(k, k.steel, k.metal)
		return twin(k, 0.46, 0.22, -1.3, -2.02, 0.17, -1.78, -1.9)
	end,
	-- 9 Royal Sunlance (blaster-d): the body stretched forward into a raked handguard with
	-- a lit slot, an angled skeleton stock, the scope, a steel magazine, twin barrels
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.86, -0.56, 0.64, w, 0, 0, 0)
		bevelBox(k, "Handguard", -0.5, -1.56, 0.1, 0.58, w - 0.08, look.Body, look.BodyMaterial)
		wedge(k, "HandguardRake", -1.51, -1.8, 0.1, 0.58, w - 0.08, UP_FRONT, look.Body, look.BodyMaterial)
		skeleton(k, 0.86, 0.57, 0.56, 0.08, 0.66, 0.56, 0.34, look.Body, look.BodyMaterial)
		scope(k, 0.56, -0.5, 0.64, 0.24)
		slab(k, "Magazine", 0.26, -0.16, -0.6, 0.02, 0.44, k.steel, k.metal)
		litSlot(k, 0.36, -0.62, -1.4, w - 0.08)
		core(k, 0.32, 0.5, w, 0.22)
		guard(k, 0.54, 0.24)
		pommel(k, k.steel, k.metal)
		return twin(k, 0.46, 0.22, -1.5, -2.2, 0.17, -1.96, -2.08)
	end,
	-- 10 Heartlance: long slim sniper (blaster-e): closed loop stock, big scope, a steel
	-- handguard, a glowing energy cell framed by a dark cap and the round collar, long exposed
	-- over-under barrels, a muzzle brake with a glowing bore per barrel
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.6
		receiver(k, 0.84, -0.6, 0.58, w, 0, 0, 0)
		-- the closed loop stock: top rod + bottom rod + butt, all in the accent color
		rod(k, "StockRod", Vector3.new(0, 0.5, 0.8), Vector3.new(0, 0.5, 1.5), 0.12, look.Accent, k.metal)
		rod(k, "StockRod", Vector3.new(0, 0.1, 0.8), Vector3.new(0, -0.02, 1.5), 0.12, look.Accent, k.metal)
		k.part("Butt", CFrame.new(0, 0.24, 1.56) * CFrame.Angles(0.1, 0, 0), Vector3.new(0.4, 0.7, 0.16), look.Accent, k.metal)
		scope(k, 0.62, -0.56, 0.58, 0.26)
		slab(k, "Handguard", -0.54, -1.2, 0.14, 0.54, 0.44, k.steel, k.metal)
		-- the energy cell: a lit window between a dark cap and the collar that holds the barrels
		tube(k, "CellCap", 0, 0.34, -1.16, -1.26, 0.48, SLOT, k.metal)
		tube(k, "Cell", 0, 0.34, -1.24, -1.62, 0.36, look.GlowCore, NEON)
		tube(k, "Collar", 0, 0.34, -1.6, -1.74, 0.52, k.steel, k.metal)
		tube(k, "Barrel", 0, 0.43, -1.62, -2.66, 0.15, look.Dark, METAL)
		tube(k, "Barrel2", 0, 0.25, -1.62, -2.66, 0.15, look.Dark, METAL)
		tube(k, "Brake", 0, 0.34, -2.58, -2.9, 0.4, look.Accent, k.metal)
		slab(k, "BrakePorts", -2.66, -2.82, 0.31, 0.37, 0.44, SLOT, k.metal)
		tube(k, "MuzzleGlow", 0, 0.43, -2.89, -2.93, 0.1, look.GlowCore, NEON)
		tube(k, "MuzzleGlow2", 0, 0.25, -2.89, -2.93, 0.1, look.GlowCore, NEON)
		slab(k, "Magazine", 0.28, -0.12, -0.6, 0.02, 0.42, k.steel, k.metal)
		litSlot(k, 0.3, 0.62, -0.42, w)
		guard(k, 0.58, 0.28)
		pommel(k, look.Accent, k.metal)
		return Vector3.new(0, 0.34, -3.0)
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
		Size = Vector3.new(grip.Width, grip.Length, grip.Depth) * s,
		Color = look.Grip,
		Material = if look.Rusty then Enum.Material.Wood else PLASTIC,
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
			Material = material or PLASTIC,
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
		gripInfo = grip,
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
