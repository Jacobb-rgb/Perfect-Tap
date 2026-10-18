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
	  bevelBox   Kenney's soft toy-plastic box: a full-width slab plus a lighter
	             inner slab that is narrower and shorter but reaches the full
	             height, so every long edge shows a wide lit step; `edges` fills
	             the two top long steps with wedges (real 45-degree chamfers),
	             `round` chamfers the top front edge the same way
	  band       a lower band whose bottom front / back corners are chamfered
	  receiver   the colored body: a bevelBox, optionally on a band (body
	             colored with a chamfered back, or Kenney's steel lower band)
	  chinBox    a steel nose / front block reaching down to its chin, only the
	             front third of the chin chamfered (a soft front, never a keel)
	  carry      the thick Kenney carry handle on top (bar + 2 posts)
	  post       a small square sight post
	  slot       Kenney's dark side slot with a small lever sticking out
	             (light grey ores: the slot glows in the ore glow instead)
	  litSlot    the same slot with a thin glowing strip inside (a vent)
	  core       a glowing power light framed by a bezel
	  stub       a short pistol barrel: a squared muzzle collar on the nose,
	             the dark bore just poking out of it, a glowing muzzle
	  barrel     a longer round barrel with a slim ore-colored tip ring
	  twin       over-under twin barrels in a round steel collar
	  skeleton   skeleton stock: two rods + a tilted butt plate
	  scope      a slim steel tube on a small dark mount, dark end rings and a
	             big glowing lens
	  pommel     the pad at the bottom of the grip (big, flush or slim)
	  guard      the trigger guard bar

	Every level is its own gun, bigger and fancier with the level
	(the part counts never drop, the test checks it):
	  1 Rusty      bare junk pistol (b without the handle): brown-red rust body
	               with chamfered edges on a worn iron band, corroded rear
	               chamfer, stubby chamfered nose, wood grip                     22 parts
	  2 Scrap      pistol (c): carry handle, a big steel front block running
	               down to the grip line as a front grip, body-colored pad      24
	  3 Spark      long low SMG (a): rounded rear tube, steel side panel with
	               the core, low handle, chamfered dark front, magazine         24
	  4 Ember      carbine (j): steel band, rear block, tall rounded nose,
	               magazine under the front, handle at the back                 24
	  5 Forgefire  bullpup (m): steel ramp, chamfered raked front, rear cap     25
	  6 Sunlance   (g): skeleton stock, steel band, hump, top shroud, hook      25
	  7 Stormlance (r): long body whose rear is the stock (chamfered, slim
	               butt pad), dark top rail, scope, raked shroud with a vent    25
	  8 Starlance  (p): skeleton stock, slim scope, body-colored magazine well,
	               steel handguard with a vent, two stacked tubes held by a
	               squared ore-colored muzzle block                             25
	  9 Royal      (d): solid angled stock, dark carry rail, long slim body
	               handguard with two stacked vents, twin barrels in a collar   25
	 10 Heartlance sniper (e): loop stock, scope, a framed glowing energy cell,
	               long twin barrels on an under-rail, muzzle brake            25
	Budget: <= 25 parts. Colors follow the ore the blaster was forged from
	(BlasterData.skin): body, stock and accents (levers, pads, muzzle collars,
	brake) in the ore colors, glows (core, muzzle, vents, lens, cell) in the
	ore glow, Kenney's light steel for front blocks, handles and magazines
	(dark steel next to light grey ores, with mid steel handles and posts so
	the top silhouette still reads); level 1 (or no ore) is the rusty starter.
	Bright glows are pulled toward the body color and darkened (by
	luminance), so neon never blooms into white blobs; the beam (Look.Glow,
	attribute Glow) keeps the ore's own glow.

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local KenneyBlaster = require(script.Parent.KenneyBlaster)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
-- (branch art/kenney-blasters, waiting for the owner's yes) build() makes the owner-approved
-- Kenney-shape blasters (Builders/KenneyBlaster); buildClassic() keeps the guns above for comparison
BlasterBuilder.MaxParts = KenneyBlaster.MaxParts
BlasterBuilder.ClassicMaxParts = 25
BlasterBuilder.Scale = 1.2 -- design studs -> held studs (level 1 is ~2.4 studs long, level 10 ~5.6)

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local SLOT = Color3.fromRGB(34, 34, 40) -- the dark side slots
local STEEL = Color3.fromRGB(150, 158, 180) -- Kenney's light blue-grey steel (front blocks, handles, magazines)
local STEEL_DARK = Color3.fromRGB(70, 73, 84) -- steel next to light grey ore bodies (two-tone instead of grey on grey)
local STEEL_MID = Color3.fromRGB(120, 124, 136) -- handles and posts next to light grey ore bodies (they stay visible)
local WOOD = Color3.fromRGB(92, 60, 40)
local RUST_RED = Color3.fromRGB(140, 82, 64) -- the starter's body is pulled toward this brown-red rust
local RUST_STEEL = Color3.fromRGB(100, 104, 114) -- the starter's cool, dark worn iron
local RUST_PATCH = Color3.fromRGB(96, 54, 36) -- the corroded rear chamfer (the only corroded part)

-- Cylinder whose axis runs along Z (Roblox cylinders run along X).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal -- barrels keep a little sheen
local PLASTIC = Enum.Material.SmoothPlastic

-- Wedge orientations (a WedgePart's slope faces -Z and up, the high edge at +Z).
local UP_FRONT = CFrame.identity -- the top-front corner is cut away
local UP_BACK = CFrame.Angles(0, math.pi, 0) -- the top-back corner is cut away
local DOWN_FRONT = CFrame.Angles(0, 0, math.pi) -- the bottom-front corner is cut away
local DOWN_BACK = CFrame.Angles(math.pi, 0, 0) -- the bottom-back corner is cut away
-- Long-edge chamfers: the wedge runs along Z, its slope faces up and out (+X / -X).
local EDGE_RIGHT = CFrame.Angles(0, -math.pi / 2, 0)
local EDGE_LEFT = CFrame.Angles(0, math.pi / 2, 0)

local BEVEL = 0.09 -- the step / chamfer of a bevelBox (design studs)
local OVERLAP = 0.015 -- slabs reach this far into the wedges next to them (no hairline seams)

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
	Trim: Color3, -- carry handles and sight posts
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

-- How a bevelBox is finished.
type BoxOpts = {
	flat: boolean?, -- a square bottom (the box sits on a band or a chin)
	edges: boolean?, -- real 45-degree chamfers on the two top long edges (2 wedges)
	round: boolean?, -- a 45-degree chamfer on the top front edge (1 wedge)
}

local PLAIN: BoxOpts = {}

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
		-- a desaturated brown-red rust body on cool, dark worn iron (no copper orange);
		-- the corrosion is only on the rear chamfer
		return {
			Level = info.Level,
			Rusty = true,
			Body = body:Lerp(RUST_RED, 0.85),
			Accent = Color3.fromRGB(112, 62, 42),
			Glow = glow,
			GlowSoft = softGlow(glow, 0.2),
			GlowCore = softGlow(glow, 0.05),
			Dark = darker(IRON, 0.25),
			Grip = WOOD,
			Steel = RUST_STEEL,
			Trim = RUST_STEEL,
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
		Trim = if greyish then STEEL_MID else STEEL,
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

--[[
	Kenney's soft toy-plastic box from two slabs: the main slab is full width and
	length but BEVEL lower at the top (and bottom), the inner slab (a little lighter,
	like a lit chamfer) is BEVEL narrower on each side and shorter at each end but
	reaches the full height. The cross section is stepped, so the long edges and the
	top end edges catch a wide highlight and the side silhouette has soft corners.
	opts.edges fills the two top long steps with wedges and opts.round the top front
	step, so those edges become real 45-degree chamfers. opts.flat keeps the bottom
	square (the box sits on a band or a chin).
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
	opts: BoxOpts?
): BasePart
	local o = opts or PLAIN
	local b = BEVEL
	local lit = lighter(color, 0.06)
	local main = slab(k, name, zBack, zFront, if o.flat then yBot else yBot + b, yTop - b, w, color, material)
	slab(k, name .. "Bevel", zBack - b, zFront + b, if o.flat then yBot + 0.02 else yBot, yTop, w - 2 * b, lit, material)
	if o.edges then
		local size = Vector3.new(zBack - zFront - 2 * b, b, b)
		local y, z = yTop - b / 2, (zBack + zFront) / 2
		k.part(name .. "Edge", CFrame.new(w / 2 - b / 2, y, z) * EDGE_RIGHT, size, lit, material, nil, "WedgePart")
		k.part(name .. "Edge", CFrame.new(-w / 2 + b / 2, y, z) * EDGE_LEFT, size, lit, material, nil, "WedgePart")
	end
	if o.round then
		wedge(k, name .. "Round", zFront + b, zFront, yTop - b, yTop, w - 2 * b, UP_FRONT, lit, material)
	end
	return main
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

-- A lower band from zBack to zFront whose bottom front / back corners are chamfered
-- (cf / cb deep, a wedge each); the slab reaches a little into the wedges.
local function band(
	k: Ctx,
	name: string,
	zBack: number,
	zFront: number,
	yBot: number,
	yTop: number,
	w: number,
	cf: number,
	cb: number,
	color: Color3,
	material: Enum.Material
)
	local back = if cb > 0 then zBack - cb + OVERLAP else zBack
	local front = if cf > 0 then zFront + cf - OVERLAP else zFront
	slab(k, name, back, front, yBot, yTop, w, color, material)
	if cf > 0 then
		wedge(k, name .. "ChamferF", zFront + cf, zFront, yBot, yTop, w, DOWN_FRONT, color, material)
	end
	if cb > 0 then
		wedge(k, name .. "ChamferB", zBack, zBack - cb, yBot, yTop, w, DOWN_BACK, color, material)
	end
end

--[[
	The colored body, h tall and w wide, a bevelBox (edges: real chamfers on the top
	long edges). It can sit on a band c tall (its bottom corners chamfered cf deep at
	the front and cb deep at the back); steelBelly turns that band into Kenney's steel
	lower strip (two-tone).
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
	steelBelly: boolean?,
	edges: boolean?
)
	local color, material = k.look.Body, k.look.BodyMaterial
	if c <= 0 or (cf <= 0 and cb <= 0 and not steelBelly) then
		bevelBox(k, "Body", zBack, zFront, 0, h, w, color, material, { edges = edges })
		return
	end
	bevelBox(k, "Body", zBack, zFront, c, h, w, color, material, { flat = true, edges = edges })
	band(k, "Belly", zBack, zFront, 0, c, w, cf, cb, if steelBelly then k.steel else color, if steelBelly then k.metal else material)
end

--[[
	A nose / front block from yBot to yTop that reaches all the way down to its chin:
	a bevelBox above yBot + chin and the chin band below it, only the front cf (about a
	third of the depth) chamfered. The front reads as Kenney's soft chamfered block,
	never as a keel or an arrowhead.
]]
local function chinBox(
	k: Ctx,
	name: string,
	zBack: number,
	zFront: number,
	yBot: number,
	yTop: number,
	w: number,
	chin: number,
	cf: number,
	color: Color3,
	material: Enum.Material,
	round: boolean?
)
	bevelBox(k, name, zBack, zFront, yBot + chin, yTop, w, color, material, { flat = true, round = round })
	band(k, name .. "Chin", zBack, zFront, yBot, yBot + chin, w, cf, 0, color, material)
end

-- Kenney's thick carry handle: a bar on two posts on top of the body (top at y = base).
local function carry(k: Ctx, zBack: number, zFront: number, base: number, height: number, color: Color3?)
	local c = color or k.look.Trim
	slab(k, "CarryBar", zBack + 0.02, zFront - 0.02, base + height - 0.12, base + height, 0.2, c, k.metal)
	slab(k, "CarryPost", zBack, zBack - 0.14, base - 0.04, base + height - 0.06, 0.16, c, k.metal)
	slab(k, "CarryPost", zFront + 0.14, zFront, base - 0.04, base + height - 0.06, 0.16, c, k.metal)
end

-- A small square sight post standing on y = base.
local function post(k: Ctx, z: number, base: number)
	slab(k, "Sight", z + 0.07, z - 0.07, base - 0.03, base + 0.12, 0.14, k.look.Trim, k.metal)
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

-- The glowing core: a power light framed by a bezel, through the body (seen on both sides).
local function core(k: Ctx, y: number, z: number, w: number, d: number, bezel: Color3?)
	disc(k, "CoreHousing", y, z, w + 0.04, d, bezel or k.steel, k.metal)
	disc(k, "Core", y, z, w + 0.06, d * 0.56, k.look.GlowCore, NEON)
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

-- A short pistol barrel (Kenney b / c / a / j): a squared muzzle collar on the nose face
-- (zFace), the dark bore poking just out of it, a glowing muzzle; returns the muzzle point.
local function stub(k: Ctx, y: number, zFace: number, d: number, collar: Color3): Vector3
	local look = k.look
	local zTip = zFace - 0.13
	tube(k, "Barrel", 0, y, zFace + 0.14, zTip, d, look.Dark, METAL)
	local half = d / 2 + 0.06
	slab(k, "MuzzleCollar", zFace + 0.02, zFace - 0.08, y - half, y + half, d + 0.12, collar, k.metal)
	tube(k, "MuzzleGlow", 0, y, zTip + 0.01, zTip - 0.03, d * 0.66, look.GlowCore, NEON)
	return Vector3.new(0, y, zTip - 0.08)
end

-- Dark round barrel + glowing muzzle disc (+ slim ore-colored tip ring); returns the muzzle point.
local function barrel(k: Ctx, name: string, x: number, y: number, zBack: number, zTip: number, d: number, ring: boolean): Vector3
	local look = k.look
	tube(k, name, x, y, zBack, zTip, d, look.Dark, METAL)
	if ring then
		tube(k, "MuzzleRing", x, y, zTip + 0.14, zTip + 0.02, d + 0.06, look.Accent, k.metal)
	end
	tube(k, "MuzzleGlow", x, y, zTip + 0.01, zTip - 0.03, d * 0.66, look.GlowCore, NEON)
	return Vector3.new(x, y, zTip - 0.08)
end

-- Over-under twin barrels from zBack to zTip at heights yTop / yBot, a round steel collar
-- around both (collarBack..collarFront) and a glowing bore in each; returns the muzzle point.
local function twin(
	k: Ctx,
	yTop: number,
	yBot: number,
	zBack: number,
	zTip: number,
	d: number,
	collarBack: number,
	collarFront: number
): Vector3
	local look = k.look
	local mid = (yTop + yBot) / 2
	tube(k, "Barrel", 0, yTop, zBack, zTip, d, look.Dark, METAL)
	tube(k, "Barrel2", 0, yBot, zBack, zTip, d, look.Dark, METAL)
	tube(k, "Collar", 0, mid, collarBack, collarFront, yTop - yBot + d + 0.14, k.steel, k.metal)
	tube(k, "MuzzleGlow", 0, yTop, zTip + 0.01, zTip - 0.03, d * 0.66, look.GlowCore, NEON)
	tube(k, "MuzzleGlow2", 0, yBot, zTip + 0.01, zTip - 0.03, d * 0.66, look.GlowCore, NEON)
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

--[[
	Scope: a slim steel tube on a small dark mount standing on the body top (base),
	dark end rings only a little wider than the tube (eye: also a rear ring) and a
	big glowing lens in the front ring.
]]
local function scope(k: Ctx, zBack: number, zFront: number, base: number, d: number, eye: boolean)
	local look = k.look
	local ring = d * 1.18
	local y = base + 0.06 + ring / 2
	local mid = (zBack + zFront) / 2
	slab(k, "ScopeMount", mid + 0.14, mid - 0.14, base - 0.02, y - d * 0.3, 0.16, look.Dark, k.metal)
	tube(k, "Scope", 0, y, zBack, zFront + 0.1, d, k.steel, k.metal)
	if eye then
		tube(k, "ScopeEye", 0, y, zBack + 0.02, zBack - 0.12, ring, look.Dark, k.metal)
	end
	tube(k, "ScopeBell", 0, y, zFront + 0.16, zFront, ring, look.Dark, k.metal)
	tube(k, "Lens", 0, y, zFront + 0.01, zFront - 0.03, d, look.GlowCore, NEON)
end

---------------------------------------------------------------- the ten guns

local GRIPS: { Grip } = {
	{ Z = 0.2, Length = 0.54, Width = 0.32, Depth = 0.4, Pad = FLUSH_PAD },
	{ Z = 0.22, Length = 0.56, Width = 0.32, Depth = 0.4, Pad = BIG_PAD },
	{ Z = 0.32, Length = 0.58, Width = 0.32, Depth = 0.4, Pad = FLUSH_PAD },
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
	-- 1 Rusty Blaster: a bare little junk pistol (blaster-b without the handle): a brown-red
	-- rust body with chamfered top edges on a worn iron band, the rear chamfer corroded, a
	-- stubby iron nose with a chamfered chin, a square sight post, a wood grip
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.6
		bevelBox(k, "Body", 0.44, -0.46, 0.2, 0.58, w, look.Body, look.BodyMaterial, { flat = true, edges = true })
		slab(k, "Belly", 0.22 + OVERLAP, -0.46, 0, 0.2, w, k.steel, k.metal)
		wedge(k, "Patch", 0.44, 0.22, 0, 0.2, w, DOWN_BACK, RUST_PATCH, Enum.Material.CorrodedMetal)
		chinBox(k, "Nose", -0.42, -0.7, -0.24, 0.56, w + 0.04, 0.26, 0.12, k.steel, k.metal, true)
		post(k, -0.53, 0.56)
		slot(k, 0.44, 0.3, -0.1, w, 0.06)
		core(k, 0.36, -0.28, w, 0.26)
		guard(k, 0.12, -0.46)
		pommel(k, look.Dark, k.metal)
		return stub(k, 0.3, -0.7, 0.24, look.Dark)
	end,
	-- 2 Scrap Blaster: pistol (blaster-c): a body-colored receiver with a chamfered back, the
	-- carry handle, a big steel front block running down to the grip line as a front grip
	-- (a deep C shape), a body-colored pad
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.5, -0.56, 0.62, w, 0.2, 0, 0.22, false, true)
		carry(k, 0.34, -0.24, 0.62, 0.24)
		chinBox(k, "Block", -0.5, -0.96, -0.6, 0.56, w + 0.06, 0.34, 0.14, k.steel, k.metal)
		post(k, -0.84, 0.56)
		slot(k, 0.48, 0.36, -0.14, w, 0.1)
		core(k, 0.32, -0.33, w, 0.26)
		guard(k, 0.14, -0.52)
		pommel(k, look.Body, look.BodyMaterial)
		return stub(k, 0.24, -0.96, 0.24, look.Accent)
	end,
	-- 3 Spark Blaster: a long low SMG (blaster-a): a slim body-colored tube running out past
	-- the back, a long steel side panel with a lit vent and a bolt, a dark top rail between two
	-- sight posts, a darker steel front with chamfered top and chin, a magazine under the front
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.6
		local front = darker(k.steel, 0.12)
		bevelBox(k, "Body", 0.62, -0.6, 0, 0.54, w, look.Body, look.BodyMaterial, { edges = true })
		tube(k, "RearTube", 0, 0.38, 0.96, 0.3, 0.3, look.Body, look.BodyMaterial)
		slab(k, "SidePanel", 0.48, -0.46, 0.1, 0.42, w + 0.06, k.steel, k.metal)
		litSlot(k, 0.26, 0.3, -0.36, w + 0.06)
		disc(k, "Bolt", 0.26, 0.4, w + 0.1, 0.09, look.Dark, k.metal)
		chinBox(k, "Front", -0.56, -0.94, -0.08, 0.6, w + 0.04, 0.2, 0.12, front, k.metal, true)
		slab(k, "Magazine", -0.44, -0.78, -0.46, 0.02, 0.4, k.steel, k.metal)
		slab(k, "TopRail", 0.5, -0.5, 0.52, 0.6, 0.3, look.Dark, k.metal)
		post(k, 0.4, 0.6)
		post(k, -0.72, 0.6)
		guard(k, 0.24, -0.46)
		pommel(k, k.steel, k.metal)
		return stub(k, 0.36, -0.94, 0.22, look.Accent)
	end,
	-- 4 Ember Blaster: carbine (blaster-j): body over a steel band, a small steel rear block,
	-- a tall steel nose with a rounded top and a sight post, a magazine under the front, the
	-- carry handle at the back
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.76, -0.62, 0.58, w, 0.2, 0, 0, true, true)
		slab(k, "RearBlock", 0.92, 0.72, 0.16, 0.46, w - 0.18, k.steel, k.metal)
		bevelBox(k, "Nose", -0.58, -0.96, 0, 0.72, w + 0.04, k.steel, k.metal, { round = true })
		post(k, -0.7, 0.72)
		slab(k, "Magazine", -0.12, -0.5, -0.56, 0.02, 0.42, k.steel, k.metal)
		carry(k, 0.56, 0.08, 0.58, 0.22)
		slot(k, 0.44, 0.28, -0.44, w, 0.02)
		core(k, 0.36, 0.5, w, 0.26)
		guard(k, 0.26, -0.12)
		pommel(k, look.Body, look.BodyMaterial)
		return stub(k, 0.36, -0.96, 0.24, look.Accent)
	end,
	-- 5 Forgefire Blaster: bullpup (blaster-m) with a steel top ramp + sight block, a round
	-- rear cap, a body-colored front with chamfered edges and a raked top, the barrel in a
	-- mouth over a raked chin
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 0.8, -0.5, 0.52, w, 0.16, 0, 0.2)
		tube(k, "RearCap", 0, 0.28, 1.12, 0.76, 0.42, look.Accent, look.BodyMaterial)
		wedge(k, "TopRamp", 0.72, 0.26, 0.5, 0.8, w - 0.14, UP_BACK, k.steel, k.metal)
		slab(k, "TopCover", 0.26, -0.5, 0.5, 0.8, w - 0.14, k.steel, k.metal)
		slab(k, "SightBlock", 0.06, -0.24, 0.78, 0.96, 0.16, look.Accent, k.metal)
		bevelBox(k, "Front", -0.44, -0.88, -0.02, 0.66, w + 0.04, look.Body, look.BodyMaterial, { edges = true })
		wedge(k, "FrontRake", -0.83, -1.06, 0.3, 0.66, w + 0.04, UP_FRONT, look.Body, look.BodyMaterial)
		slab(k, "LowerFront", -0.34, -0.82 - OVERLAP, -0.28, 0.0, w - 0.08, k.steel, k.metal)
		wedge(k, "LowerChin", -0.82, -1.0, -0.28, 0.0, w - 0.08, DOWN_FRONT, k.steel, k.metal)
		litSlot(k, 0.3, 0.64, 0.02, w)
		core(k, 0.4, -0.66, w + 0.04, 0.26)
		guard(k, 0.08, -0.34)
		pommel(k, look.Accent, k.metal)
		return barrel(k, "Barrel", 0, 0.18, -0.9, -1.3, 0.26, true)
	end,
	-- 6 Sunlance (blaster-g): short skeleton stock, body with chamfered edges over a steel band,
	-- steel hump, a top shroud with a hook over the barrel, a short steel foregrip
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		receiver(k, 0.62, -0.62, 0.6, w, 0.18, 0, 0.2, true, true)
		skeleton(k, 0.62, 0.5, 0.48, 0.16, 0.58, 0.58, 0.16, look.Body, look.BodyMaterial)
		slab(k, "Hump", 0.32, -0.18, 0.58, 0.84, w - 0.16, k.steel, k.metal)
		wedge(k, "HumpSlope", 0.52, 0.32, 0.58, 0.84, w - 0.16, UP_BACK, k.steel, k.metal)
		bevelBox(k, "Shroud", -0.18, -1.24, 0.42, 0.78, w - 0.12, k.steel, k.metal)
		slab(k, "ShroudHook", -1.1, -1.24, 0.22, 0.44, w - 0.22, k.steel, k.metal)
		slab(k, "Foregrip", -0.3 + OVERLAP, -0.7, -0.24, 0.02, w - 0.12, k.steel, k.metal)
		wedge(k, "ForeChin", -0.14, -0.3, -0.24, 0.02, w - 0.12, DOWN_BACK, k.steel, k.metal)
		slot(k, 0.32, 0.44, -0.2, w)
		core(k, 0.36, -0.42, w, 0.26)
		guard(k, 0.24, -0.3)
		pommel(k, look.Body, look.BodyMaterial)
		return barrel(k, "Barrel", 0, 0.3, -0.5, -1.62, 0.24, true)
	end,
	-- 7 Stormlance (blaster-r): a long body whose rear is the stock, its bottom-rear chamfered,
	-- a slim ore-colored butt pad, a dark top rail with the scope, a raked steel shroud with a
	-- lit vent, a forward-tilted magazine
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.64
		receiver(k, 1.38, -0.66, 0.64, w, 0.34, 0, 0.42)
		slab(k, "ButtPad", 1.46, 1.37, 0.36, 0.64, w - 0.12, look.Accent, k.metal)
		slab(k, "TopRail", 1.22, -0.5, 0.62, 0.69, 0.34, look.Dark, k.metal)
		scope(k, 0.5, -0.44, 0.69, 0.22, false)
		bevelBox(k, "Shroud", -0.6, -1.36, 0.08, 0.72, w + 0.04, k.steel, k.metal)
		wedge(k, "ShroudRake", -1.31, -1.62, 0.08, 0.72, w + 0.04, DOWN_FRONT, k.steel, k.metal)
		k.part("Magazine", CFrame.new(0, -0.25, -0.3) * CFrame.Angles(0.14, 0, 0), Vector3.new(0.44, 0.56, 0.38), k.steel, k.metal)
		litSlot(k, 0.44, -0.72, -1.24, w + 0.04)
		slot(k, 0.5, 1.2, 0.62, w)
		core(k, 0.47, 0.1, w, 0.26)
		guard(k, 0.42, -0.1)
		pommel(k, k.steel, k.metal)
		return barrel(k, "Barrel", 0, 0.3, -1.36, -1.86, 0.24, true)
	end,
	-- 8 Starlance (blaster-p): skeleton stock, a slim scope, a body-colored magazine well over
	-- a steel magazine, a steel handguard with a lit vent, two short stacked tubes held by a
	-- squared ore-colored muzzle block
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		bevelBox(k, "Body", 0.92, -0.6, 0, 0.62, w, look.Body, look.BodyMaterial)
		skeleton(k, 0.92, 0.6, 0.5, 0.12, 0.62, 0.64, 0.1, look.Body, look.BodyMaterial)
		scope(k, 0.58, -0.3, 0.62, 0.2, false)
		slab(k, "MagWell", 0.22, -0.3, -0.24, 0.02, w - 0.1, look.Body, look.BodyMaterial)
		slab(k, "Magazine", 0.16, -0.22, -0.6, -0.2, 0.42, k.steel, k.metal)
		bevelBox(k, "Handguard", -0.54, -1.42, 0.04, 0.62, 0.56, k.steel, k.metal)
		litSlot(k, 0.33, -0.66, -1.3, 0.56)
		tube(k, "Barrel", 0, 0.46, -1.3, -1.9, 0.17, look.Dark, METAL)
		tube(k, "Barrel2", 0, 0.22, -1.3, -1.9, 0.17, look.Dark, METAL)
		slab(k, "MuzzleBlock", -1.62, -1.76, 0.08, 0.6, 0.3, look.Accent, k.metal)
		tube(k, "MuzzleGlow", 0, 0.46, -1.89, -1.93, 0.12, look.GlowCore, NEON)
		tube(k, "MuzzleGlow2", 0, 0.22, -1.89, -1.93, 0.12, look.GlowCore, NEON)
		core(k, 0.32, 0.7, w, 0.24)
		guard(k, 0.52, 0.22)
		pommel(k, k.steel, k.metal)
		return Vector3.new(0, 0.34, -2.0)
	end,
	-- 9 Royal Sunlance (blaster-d): a solid angled stock (deeper toward the butt, a slim dark
	-- pad), a dark carry rail, a long slim body-colored handguard with two stacked lit vents,
	-- over-under twin barrels in a round steel collar
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.62
		bevelBox(k, "Body", 0.86, -0.56, 0, 0.64, w, look.Body, look.BodyMaterial)
		slab(k, "Stock", 1.42, 0.82, 0.32 - OVERLAP, 0.58, w - 0.26, look.Body, look.BodyMaterial)
		wedge(k, "StockTaper", 1.42, 0.82, 0.0, 0.32, w - 0.26, DOWN_FRONT, look.Body, look.BodyMaterial)
		slab(k, "ButtPad", 1.48, 1.41, 0.0, 0.58, w - 0.22, look.Dark, k.metal)
		carry(k, 0.56, -0.24, 0.64, 0.2, look.Dark)
		bevelBox(k, "Handguard", -0.5, -1.6, 0.1, 0.56, w - 0.08, look.Body, look.BodyMaterial)
		wedge(k, "HandguardRake", -1.55, -1.82, 0.1, 0.56, w - 0.08, UP_FRONT, look.Body, look.BodyMaterial)
		slab(k, "VentFrame", -0.66, -1.4, 0.18, 0.48, w - 0.06, SLOT, k.metal)
		slab(k, "Vent", -0.71, -1.35, 0.375, 0.425, w - 0.04, look.GlowSoft, NEON)
		slab(k, "Vent", -0.71, -1.35, 0.235, 0.285, w - 0.04, look.GlowSoft, NEON)
		slab(k, "Magazine", 0.26, -0.16, -0.6, 0.02, 0.44, k.steel, k.metal)
		core(k, 0.34, 0.5, w, 0.24)
		guard(k, 0.54, 0.24)
		pommel(k, k.steel, k.metal)
		return twin(k, 0.46, 0.22, -1.5, -2.26, 0.18, -2.0, -2.12)
	end,
	-- 10 Heartlance: long slim sniper (blaster-e): closed loop stock, scope, a glowing energy
	-- cell framed by a dark cap, a dark middle band and the round collar, long over-under
	-- barrels on a steel under-rail, a muzzle brake with one big glowing bore
	function(k: Ctx): Vector3
		local look = k.look
		local w = 0.6
		bevelBox(k, "Body", 0.84, -0.6, 0, 0.58, w, look.Body, look.BodyMaterial)
		-- the closed loop stock: top rod + bottom rod + butt, all in the accent color
		rod(k, "StockRod", Vector3.new(0, 0.5, 0.8), Vector3.new(0, 0.5, 1.5), 0.12, look.Accent, k.metal)
		rod(k, "StockRod", Vector3.new(0, 0.1, 0.8), Vector3.new(0, -0.02, 1.5), 0.12, look.Accent, k.metal)
		k.part("Butt", CFrame.new(0, 0.24, 1.56) * CFrame.Angles(0.1, 0, 0), Vector3.new(0.4, 0.7, 0.16), look.Accent, k.metal)
		scope(k, 0.62, -0.56, 0.58, 0.26, false)
		slab(k, "Handguard", -0.54, -1.2, 0.14, 0.54, 0.44, k.steel, k.metal)
		tube(k, "CellCap", 0, 0.34, -1.16, -1.26, 0.48, SLOT, k.metal)
		tube(k, "Cell", 0, 0.34, -1.24, -1.74, 0.36, look.GlowCore, NEON)
		tube(k, "CellBand", 0, 0.34, -1.45, -1.53, 0.42, SLOT, k.metal)
		tube(k, "Collar", 0, 0.34, -1.72, -1.86, 0.54, k.steel, k.metal)
		tube(k, "Barrel", 0, 0.44, -1.74, -2.7, 0.18, look.Dark, METAL)
		tube(k, "Barrel2", 0, 0.24, -1.74, -2.7, 0.18, look.Dark, METAL)
		slab(k, "UnderRail", -1.8, -2.64, 0.05, 0.16, 0.16, k.steel, k.metal)
		tube(k, "Brake", 0, 0.34, -2.6, -2.94, 0.44, look.Accent, k.metal)
		tube(k, "MuzzleGlow", 0, 0.34, -2.93, -2.97, 0.3, look.GlowCore, NEON)
		slab(k, "Magazine", 0.28, -0.12, -0.6, 0.02, 0.42, k.steel, k.metal)
		litSlot(k, 0.3, 0.62, -0.42, w)
		guard(k, 0.58, 0.28)
		pommel(k, look.Accent, k.metal)
		return Vector3.new(0, 0.34, -3.05)
	end,
}

function BlasterBuilder.buildClassic(level: any, oreId: string?): Tool
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

--[[
	The blaster tool of a level in an ore's look: the owner-approved Kenney
	Blaster Kit shapes with the Ore Glow skins (Builders/KenneyBlaster, at
	most BlasterBuilder.MaxParts parts). The Handle is an invisible block at
	the hand (Tool.Grip = identity: the barrel straight along the arm), every
	part is welded to it, the Muzzle attachment sits at the barrel's tip.
	From level 7 a slow GunFlame / GunSpark emitter rides along the gun.
]]
function BlasterBuilder.build(level: any, oreId: string?): Tool
	local info = BlasterData.get(level)
	local lv = info.Level
	local look = BlasterBuilder.look(lv, oreId)
	local ore = if look.Rusty or not oreId then "" else oreId
	local skin = KenneyBlaster.skin(lv, ore, look)

	local tool = Instance.new("Tool")
	tool.Name = BlasterBuilder.ToolName
	tool.ToolTip = BlasterData.displayName(lv, oreId)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.identity
	tool:SetAttribute("Level", lv)
	tool:SetAttribute("OreId", if oreId then oreId else "")
	tool:SetAttribute("Range", info.Range)
	tool:SetAttribute("Glow", look.Glow)

	local handle = Geo.make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.3, 0.6, 0.3),
		Color = skin.Base,
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = true,
		CastShadow = false,
		CFrame = CFrame.identity,
	})
	handle.Parent = tool
	local function part(name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, className: string?): BasePart
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or PLASTIC,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			CastShadow = false,
		})
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local anchors = KenneyBlaster.parts(lv, ore, skin, part)
	-- flames (hot ores) or sparks around the gun from level 7: slow, short-lived (phones)
	local fxCf, fxSize = KenneyBlaster.effects(lv)
	if fxCf and fxSize then
		local holder = part("Effects", fxCf, fxSize, skin.Glow)
		holder.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = if skin.Magma then "GunFlame" else "GunSpark"
		emitter.Texture = if skin.Magma
			then "rbxasset://textures/particles/fire_main.dds"
			else "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(skin.Glow)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Rate = if lv >= 10 then 8 else 5
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, if skin.Magma then 3 else 0.5, 0)
		emitter.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, if skin.Magma then 0.35 else 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = holder
	end
	-- where the beam leaves the barrel
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = anchors.Muzzle
	muzzle.Parent = handle
	return tool
end

--[[
	A level's black silhouette (the whole outline in one color, 8-23 parts):
	a Model of anchored, non-colliding parts in the gun's frame (the hand at
	the origin, the barrel along -Z). The Foundry's NEXT rack and the
	gallery's LV 11 use it.
]]
function BlasterBuilder.silhouette(level: any, color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "Silhouette"
	local lv = math.max(2, BlasterData.get(level).Level)
	KenneyBlaster.silhouette(lv, color or Color3.fromRGB(20, 18, 26), function(name, cf, size, c, material, className)
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = c,
			Material = material or PLASTIC,
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		})
		p.Parent = model
		return p
	end)
	return model
end

return BlasterBuilder
