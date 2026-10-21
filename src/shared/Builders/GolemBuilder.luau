--[[
	Golem pets (step 7) built from parts: original chunky ore and metal
	golems in the proportions of Kenney's Mini Characters (a big head on a
	short body, stubby arms, short legs), dressed in the colors of their ore
	(GolemConfig: Body, Trim, Glow, Material) and built to read as living
	rock: a heavy stone brow over glowing eyes, rough rock-chunk fists, a
	boulder jutting from one shoulder, the ore's crystal growing from the
	other, a glowing ore vein cracking across the chest from its core, and
	rough stone where the ore's own material would look like plastic or
	glass (rockMaterial). Variants come from the golem's Accessory (helmets,
	goggles, a visor, crowns, a halo, horns, a leaf, a hood, crystals on the
	back). Legendary and Mythic golems (Premium) hover on a glowing aura
	disc in their glow color (the model's "Hover" attribute: how high the
	feet float over its base), so the Royal capsule's chase golems stand
	out in the reveal, the inventory and as followers. No lights (the
	client's one real light is the player's lamp, GearConfig.LampBudget).
	Pure: only creates Instances, so the Lune tests and preview renders use
	it too.

	  build(kind, base?, opts?)   a golem Model standing on `base` (its feet
	                              center, front = the CFrame's LookVector =
	                              local -Z, +Y up). At most MaxParts (20)
	                              parts: the body, the accessory, the aura,
	                              then the vein while the budget allows.
	                              LIMITED EDITION golems (GolemConfig
	                              Edition, Config/LimitedGolems) wear their
	                              set's themed gear (GolemGearLimited) and
	                              may use GolemConfig.LimitedMaxParts (by
	                              rarity) instead; their Height is measured
	                              from the parts.
	                              PrimaryPart = "Body" (the torso); the
	                              model's attribute "RootHeight" is the Body
	                              center's height above the base (the hover
	                              included), so a follower sets Body.CFrame =
	                              feet * CFrame.new(0, RootHeight, 0).
	                              Attributes "Golem" (kind), "Height" (studs,
	                              base to the top of the head gear) and
	                              "Hover" (studs; 0 unless Premium).
	    opts.Size     extra scale (1 = the golem's own Scale)
	    opts.Welded   followers (no PointLight): every part but Body is unanchored, massless
	                  and welded to the anchored Body (moving Body moves the
	                  golem: one CFrame write per frame)
	    No part collides, touches or is queried; only Body and Head cast
	    shadows. An unknown kind builds a plain stone golem (never errors).
	  capsule(capsuleId, base?)   the capsule for the opening animation: a
	                              pill of two halves, sub-models "Top" (light
	                              upper shell) and "Bottom" (colored lower
	                              shell with the glowing seam band), plus
	                              three glowing cracks "Crack1..3" in Bottom
	                              (Transparency 1 until the controller shows
	                              them). 12 parts: 9 seen and 3 invisible
	                              upright pivots at the pill's center, the
	                              PrimaryParts "Root" (the model), "TopRoot"
	                              and "BottomRoot" (the halves), so PivotTo
	                              moves them from the center. base = the
	                              pill's center, the window faces -Z.
]]

local CapsuleConfig = require(script.Parent.Parent.Config.CapsuleConfig)
local GolemConfig = require(script.Parent.Parent.Config.GolemConfig)
local GolemGearLimited = require(script.Parent.GolemGearLimited)
local LimitedUpcoming = require(script.Parent.Parent.Config.LimitedUpcoming)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local GolemBuilder = {}

export type Opts = { Size: number?, Welded: boolean? }

GolemBuilder.MaxParts = 20
-- (a limited edition golem's budget: GolemConfig.LimitedMaxParts by rarity)
GolemBuilder.CapsuleParts = 12 -- 9 visible + 3 invisible pivots
-- a limited edition's SHARD (its set's egg, GolemGearLimited.shard) instead
-- of the pill: only one is ever built at a time (the opening, a picture)
GolemBuilder.ShardMaxParts = 56
GolemBuilder.PremiumFrom = "Legendary" -- golems this rare hover on an aura
GolemBuilder.Hover = 0.25 -- how high a Premium golem's feet float (unscaled)
GolemBuilder.AuraSize = 2.3 -- the aura disc's diameter (unscaled)
-- the golem's own proportions at Scale 1 (studs): feet at 0
GolemBuilder.LegHeight = 0.5
GolemBuilder.BodySize = Vector3.new(1.2, 0.95, 0.85)
GolemBuilder.HeadSize = Vector3.new(1.5, 1.25, 1.3)
GolemBuilder.HeadBottom = 1.45 -- legs (0.5) + body (0.95)
GolemBuilder.CapsuleRadius = 1.2
GolemBuilder.CapsuleHeight = 4.4 -- tip to tip

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local STONE = rgb(132, 126, 118)
local STEEL = rgb(178, 184, 196)
local BRASS = rgb(214, 170, 74)
local GLASS = rgb(170, 230, 255)
local LEAF = rgb(96, 200, 92)
local LEAF_DARK = rgb(52, 120, 56)
local PLUME = rgb(214, 52, 60)
local LAMP_YELLOW = rgb(255, 196, 40)
local LAMP_LIGHT = rgb(255, 244, 190)
local GOLD = rgb(255, 196, 56)
local DARK = rgb(26, 22, 26)

-- Ore materials that would look odd on a whole body (see-through,
-- blinding or plain plastic), by name: such a golem is rough stone in its
-- ore's color (a ruby golem is red rock), its crystals glass.
local STONE_MATERIALS: { [string]: boolean } = { Glass = true, Neon = true, ForceField = true, SmoothPlastic = true, Plastic = true }

local function bodyMaterial(material: Enum.Material): Enum.Material
	return if STONE_MATERIALS[material.Name] then Enum.Material.Slate else material
end

-- The rough bits (fists, brow, the shoulder boulder): stone, but metal
-- golems keep their metal.
local function rockMaterial(material: Enum.Material): Enum.Material
	local name = material.Name
	return if name == "Metal" or name == "Foil" or name == "DiamondPlate" then Enum.Material.Metal else Enum.Material.Slate
end

-- Neon in a near-white color blooms into a white blob: eyes and cores get
-- a slightly deeper shade of such a glow.
local function glowShade(c: Color3): Color3
	if math.min(c.R, c.G, c.B) > 0.7 then
		return c:Lerp(Color3.new(c.R * 0.55, c.G * 0.6, c.B * 0.75), 0.45)
	end
	return c
end

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local instance: any = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

-- One plain part (decor flags; anchored until welded).
local function part(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	return make("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Massless = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Shape = shape or Enum.PartType.Block,
		Material = material or Enum.Material.SmoothPlastic,
		Color = color,
		Size = size,
		CFrame = cf,
	}, parent)
end

-- A cylinder whose axis runs along `cf`'s Y (Roblox cylinders run along X).
local function upright(
	parent: Instance,
	name: string,
	cf: CFrame,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return part(
		parent,
		name,
		cf * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A cylinder whose axis runs along `cf`'s Z (lenses and lamps facing front).
local function facing(
	parent: Instance,
	name: string,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return part(
		parent,
		name,
		cf * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(length, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(DARK, amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(WHITE, amount)
end

-- The look of a kind (a plain stone golem for an unknown kind).
local function lookOf(kind: string): GolemConfig.Golem
	local golem = GolemConfig.ById[kind] or LimitedUpcoming.ById[kind]
	if golem then
		return golem
	end
	return {
		Id = kind,
		Name = "Golem",
		Rarity = "Common",
		Body = STONE,
		Trim = darker(STONE, 0.35),
		Glow = rgb(255, 170, 90),
		Material = Enum.Material.Slate,
		Accessory = "None",
		Scale = 1,
		Bonus = { Type = "Income", Value = 0 },
		Lore = "",
	} :: any
end

---------------------------------------------------------------- accessories

type Ctx = {
	Model: Model,
	-- (positions are unscaled units from the feet: At / V scale them and add the hover)
	At: (x: number, y: number, z: number) -> CFrame,
	V: (x: number, y: number, z: number) -> Vector3,
	Look: GolemConfig.Golem,
	S: number, -- the scale (studs per unit)
	Glow: Color3, -- the glow for Neon parts (glowShade)
	Top: number, -- the top of the head (unscaled units)
	Room: () -> number, -- parts the gear may still add (the budget minus the aura)
}

-- Gear that covers the face: "Closed" (a closed helm: no brow, the eyes a
-- little forward, glowing through the slit) or "Visor" (no brow).
GolemBuilder.Faces = {
	KnightHelm = "Closed",
	Visor = "Visor",
} :: { [string]: string }
for name, face in GolemGearLimited.Faces do
	GolemBuilder.Faces[name] = face
end

-- Each returns the top of what it added (unscaled), for the model's Height.
local ACCESSORIES: { [string]: (Ctx) -> number } = {}

ACCESSORIES.None = function(c)
	-- a stone chip on the head (silhouette)
	part(c.Model, "Chip", c.At(-0.32, 2.76, 0.12) * CFrame.Angles(0.3, 0.6, 0.25), c.V(0.42, 0.26, 0.38), c.Look.Trim)
	return 2.95
end

ACCESSORIES.Goggles = function(c)
	-- pushed up onto the stone brow
	part(c.Model, "Strap", c.At(0, 2.6, 0), c.V(1.56, 0.18, 1.36), darker(c.Look.Trim, 0.3))
	for i, x in { -0.3, 0.3 } do
		facing(c.Model, "Goggle" .. i, c.At(x, 2.64, -0.76), 0.16 * c.S, 0.46 * c.S, BRASS, Enum.Material.Metal)
		facing(c.Model, "Lens" .. i, c.At(x, 2.64, -0.85), 0.04 * c.S, 0.32 * c.S, GLASS, Enum.Material.Glass)
	end
	return 2.88
end

ACCESSORIES.PotHelmet = function(c)
	upright(c.Model, "Pot", c.At(0, 2.92, 0.02), 0.5 * c.S, 1.42 * c.S, STEEL, Enum.Material.Metal)
	upright(c.Model, "PotRim", c.At(0, 2.69, 0.02), 0.08 * c.S, 1.66 * c.S, darker(STEEL, 0.2), Enum.Material.Metal)
	part(c.Model, "PotHandle", c.At(0.86, 2.95, 0.02), c.V(0.42, 0.12, 0.14), darker(STEEL, 0.3), Enum.Material.Metal)
	return 3.17
end

ACCESSORIES.CrystalBack = function(c)
	local crystals = {
		{ -0.36, 1.62, 0.5, 0.3, 0.8, -0.45, 0.35 },
		{ 0.12, 1.85, 0.58, 0.38, 1.15, 0.05, 0.42 },
		{ 0.5, 1.5, 0.48, 0.26, 0.62, 0.5, 0.3 },
		{ -0.12, 2.72, 0.42, 0.26, 0.62, -0.25, 0.3 },
	}
	for i, k in crystals do
		part(
			c.Model,
			"Crystal" .. i,
			c.At(k[1], k[2], k[3]) * CFrame.Angles(k[7], 0, k[6]) * CFrame.Angles(0, math.pi / 4, 0),
			c.V(k[4], k[5], k[4]),
			c.Look.Glow,
			Enum.Material.Glass
		)
	end
	return 3.0
end

ACCESSORIES.SquireHelm = function(c)
	part(c.Model, "Helm", c.At(0, 2.76, 0.02), c.V(1.62, 0.46, 1.4), STEEL, Enum.Material.Metal)
	part(c.Model, "NoseGuard", c.At(0, 2.16, -0.8), c.V(0.14, 0.5, 0.08), darker(STEEL, 0.15), Enum.Material.Metal)
	part(c.Model, "Plume", c.At(0, 3.18, 0.12), c.V(0.18, 0.46, 0.78), PLUME)
	return 3.41
end

ACCESSORIES.Hood = function(c)
	part(c.Model, "Hood", c.At(0, 2.42, 0.12), c.V(1.68, 0.9, 1.3), c.Look.Trim)
	part(c.Model, "HoodPeak", c.At(0, 2.92, 0.2), c.V(1.2, 0.2, 1.0), darker(c.Look.Trim, 0.15))
	part(c.Model, "Rune", c.At(0, 2.68, -0.54) * CFrame.Angles(0, 0, math.pi / 4), c.V(0.2, 0.2, 0.06), c.Glow, Enum.Material.Neon)
	return 3.02
end

ACCESSORIES.Leaf = function(c)
	part(c.Model, "Stem", c.At(0, 2.86, 0), c.V(0.09, 0.34, 0.09), LEAF_DARK)
	part(c.Model, "Leaf1", c.At(0.22, 3.04, 0) * CFrame.Angles(0, 0, 0.45), c.V(0.52, 0.07, 0.32), LEAF)
	part(c.Model, "Leaf2", c.At(-0.17, 2.98, 0) * CFrame.Angles(0, 0, -0.5), c.V(0.36, 0.07, 0.24), LEAF)
	return 3.2
end

ACCESSORIES.Horns = function(c)
	for i, side in { -1, 1 } do
		part(c.Model, "HornBase" .. i, c.At(side * 0.5, 2.82, 0.05) * CFrame.Angles(0, 0, side * -0.25), c.V(0.3, 0.34, 0.3), c.Look.Trim)
		part(
			c.Model,
			"HornTip" .. i,
			c.At(side * 0.62, 3.1, 0.05) * CFrame.Angles(0, 0, side * -0.45),
			c.V(0.18, 0.36, 0.18),
			c.Glow,
			Enum.Material.Neon
		)
	end
	return 3.3
end

ACCESSORIES.Visor = function(c)
	part(c.Model, "VisorFrame", c.At(0, 2.04, -0.69), c.V(1.36, 0.88, 0.06), BRASS, Enum.Material.Metal)
	local glass = part(c.Model, "VisorGlass", c.At(0, 2.04, -0.74), c.V(1.18, 0.7, 0.06), GLASS, Enum.Material.Glass)
	glass.Transparency = 0.35
	upright(c.Model, "Valve", c.At(0, 2.8, 0), 0.16 * c.S, 0.4 * c.S, BRASS, Enum.Material.Metal)
	return 2.88
end

ACCESSORIES.LampHelmet = function(c)
	part(c.Model, "Helmet", c.At(0, 2.84, 0.02), c.V(1.6, 0.44, 1.4), LAMP_YELLOW)
	part(c.Model, "Brim", c.At(0, 2.64, -0.04), c.V(1.74, 0.08, 1.56), darker(LAMP_YELLOW, 0.2))
	facing(c.Model, "Lamp", c.At(0, 2.88, -0.74), 0.22 * c.S, 0.42 * c.S, BRASS, Enum.Material.Metal)
	facing(c.Model, "LampLens", c.At(0, 2.88, -0.86), 0.04 * c.S, 0.3 * c.S, LAMP_LIGHT, Enum.Material.Neon)
	return 3.06
end

ACCESSORIES.KnightHelm = function(c)
	-- the closed helm covers the whole head; the eyes glow through its slit
	part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), lighter(c.Look.Trim, 0.15), Enum.Material.Metal)
	part(c.Model, "Slit", c.At(0, 2.06, -0.71), c.V(1.12, 0.24, 0.04), DARK)
	part(c.Model, "Crest", c.At(0, 2.94, 0.05), c.V(0.14, 0.42, 1.1), c.Look.Glow)
	return 3.15
end

ACCESSORIES.Halo = function(c)
	-- a pentagon of glowing bars (five parts: the budget)
	local r = 0.55
	local side = 2 * r * math.tan(math.pi / 5) + 0.04
	for i = 1, 5 do
		local a = (i - 0.5) * 2 * math.pi / 5
		part(
			c.Model,
			"Halo" .. i,
			c.At(math.cos(a) * r, 3.12, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0),
			c.V(side, 0.08, 0.12),
			c.Glow,
			Enum.Material.Neon
		)
	end
	return 3.2
end

ACCESSORIES.Crown = function(c)
	upright(c.Model, "CrownBand", c.At(0, 2.84, 0), 0.24 * c.S, 1.08 * c.S, GOLD, Enum.Material.Foil)
	for i, k in { { -0.36, -0.22, 0.6 }, { 0, -0.42, 0 }, { 0.36, -0.22, -0.6 } } do
		part(
			c.Model,
			"CrownPoint" .. i,
			c.At(k[1], 3.03, k[2]) * CFrame.Angles(0, k[3], 0) * CFrame.Angles(0, 0, math.pi / 4),
			c.V(0.22, 0.22, 0.08),
			GOLD,
			Enum.Material.Foil
		)
	end
	part(c.Model, "CrownGem", c.At(0, 2.85, -0.55) * CFrame.Angles(0, 0, math.pi / 4), c.V(0.16, 0.16, 0.06), c.Glow, Enum.Material.Neon)
	return 3.18
end

-- (a wedge: its slope faces -Z and up, the tall side at +Z)
local function wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	return make("WedgePart", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Massless = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = material or Enum.Material.SmoothPlastic,
		Color = color,
		Size = size,
		CFrame = cf,
	}, parent)
end

-- the limited edition gear (GolemGearLimited)
local KIT = {
	part = part,
	upright = upright,
	facing = facing,
	wedge = wedge,
	darker = darker,
	lighter = lighter,
}
for name, add in GolemGearLimited.accessories(KIT) do
	ACCESSORIES[name] = add :: any
end

---------------------------------------------------------------- golems

-- The part budget of a kind: GolemConfig.LimitedMaxParts[rarity] for a
-- limited edition golem (an upcoming set's preview look too).
function GolemBuilder.budget(kind: string): number
	local golem = GolemConfig.ById[kind] or LimitedUpcoming.ById[kind]
	if golem and golem.Edition ~= nil then
		return GolemConfig.LimitedMaxParts[golem.Rarity] or GolemConfig.MaxParts
	end
	return GolemBuilder.MaxParts
end

-- A golem Model (see the header).
function GolemBuilder.build(kind: string, base: CFrame?, opts: Opts?): Model
	local look = lookOf(kind)
	local size = math.clamp(if opts and type(opts.Size) == "number" and opts.Size == opts.Size then opts.Size else 1, 0.05, 20)
	local s = (look.Scale or 1) * size
	local ground = base or CFrame.new()
	local premium = GolemBuilder.premium(kind)
	local budget = GolemBuilder.budget(kind)
	local hover = if premium then GolemBuilder.Hover else 0
	-- the feet (Premium golems float `hover` over the base)
	local feet = ground * CFrame.new(0, hover * s, 0)
	local model = Instance.new("Model")
	model.Name = "Golem"
	local function at(x: number, y: number, z: number): CFrame
		return feet * CFrame.new(x * s, y * s, z * s)
	end
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x * s, y * s, z * s)
	end
	local material = bodyMaterial(look.Material)
	local rock = rockMaterial(look.Material)
	local body = look.Body
	local trim = look.Trim
	local glow = glowShade(look.Glow)
	local crystalMaterial = if look.Material.Name == "Glass" then Enum.Material.Glass else Enum.Material.SmoothPlastic

	-- legs
	for i, x in { -0.3, 0.3 } do
		part(model, "Leg" .. i, at(x, 0.25, 0.02), v(0.44, 0.5, 0.52), trim, rock)
	end
	-- the torso (PrimaryPart) and its glowing core
	local bodyY = GolemBuilder.LegHeight + GolemBuilder.BodySize.Y / 2
	local torso = part(model, "Body", at(0, bodyY, 0), v(1.2, 0.95, 0.85), body, material)
	torso.CastShadow = true
	part(model, "Core", at(0, 0.98, -0.44) * CFrame.Angles(0, 0, math.pi / 4), v(0.26, 0.26, 0.06), glow, Enum.Material.Neon)
	-- stubby arms ending in rough rock-chunk fists (turned, so they read as stones)
	local arm = body:Lerp(trim, 0.3)
	for i, side in { -1, 1 } do
		part(model, "Arm" .. i, at(side * 0.8, 1.12, 0) * CFrame.Angles(0, 0, side * 0.1), v(0.38, 0.62, 0.48), arm, material)
		part(model, "Fist" .. i, at(side * 0.86, 0.68, -0.03) * CFrame.Angles(0.3, side * 0.45, side * 0.2), v(0.5, 0.46, 0.48), trim, rock)
	end
	-- the big head under a heavy stone brow, two glowing eyes in its shadow
	local headY = GolemBuilder.HeadBottom + GolemBuilder.HeadSize.Y / 2
	local head = part(model, "Head", at(0, headY, 0), v(1.5, 1.25, 1.3), lighter(body, 0.05), material)
	head.CastShadow = true
	-- (a closed helm or a diving visor covers the face: no brow under it)
	local face = GolemBuilder.Faces[look.Accessory]
	local closed = face == "Closed"
	if face == nil then
		part(model, "Brow", at(0, 2.36, -0.6) * CFrame.Angles(-0.3, 0, 0), v(1.58, 0.3, 0.36), darker(trim, 0.1), rock)
	end
	local eyeZ = if closed then -0.75 else -0.68
	for i, x in { -0.28, 0.28 } do
		part(model, "Eye" .. i, at(x, 2.02, eyeZ), v(0.25, 0.2, 0.06), glow, Enum.Material.Neon)
	end
	-- a boulder jutting from the left shoulder, the ore's crystal growing from the right
	part(model, "Boulder", at(-0.6, 1.52, 0.14) * CFrame.Angles(0.35, 0.6, 0.45), v(0.56, 0.44, 0.5), trim, rock)
	part(
		model,
		"Crystal",
		at(0.56, 1.66, 0.22) * CFrame.Angles(0.25, 0.785, -0.5) * CFrame.Angles(0, math.pi / 4, 0),
		v(0.26, 0.66, 0.26),
		lighter(look.Glow, 0.1),
		crystalMaterial
	)
	-- the gear
	local function room(): number
		return budget - GolemBuilder.partCount(model) - (if premium then 1 else 0)
	end
	local ctx: Ctx = {
		Model = model,
		At = at,
		V = v,
		Look = look,
		S = s,
		Glow = glow,
		Top = GolemBuilder.HeadBottom + GolemBuilder.HeadSize.Y,
		Room = room,
	}
	local add = ACCESSORIES[look.Accessory] or ACCESSORIES.None
	local top = math.max(ctx.Top, add(ctx))
	-- Premium: the aura disc under the floating feet (on the base)
	if premium then
		local aura =
			upright(model, "Aura", ground * CFrame.new(0, 0.025 * s, 0), 0.05 * s, GolemBuilder.AuraSize * s, glow, Enum.Material.Neon)
		aura.Transparency = 0.35
	end
	-- a glowing ore vein cracking the chest above the core, while the budget allows
	if GolemBuilder.partCount(model) < budget then
		part(model, "Vein", at(-0.4, 1.27, -0.435) * CFrame.Angles(0, 0, 0.6), v(0.06, 0.3, 0.04), glow, Enum.Material.Neon)
	end
	-- a limited edition golem's gear (wings, hats, halos) is too varied to
	-- guess: its Height is measured from its parts
	if look.Edition ~= nil then
		top = GolemBuilder.topOver(model, feet) / s
	end

	model.PrimaryPart = torso
	model:SetAttribute("Golem", kind)
	model:SetAttribute("RootHeight", (bodyY + hover) * s)
	model:SetAttribute("Height", (top + hover) * s)
	model:SetAttribute("Hover", hover * s)
	if opts and opts.Welded then
		-- a follower keeps no light (the opening and the pictures do): many
		-- followers may walk round one phone, lights cost the most
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") then
				d:Destroy()
			end
		end
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= torso then
				child.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = torso
				weld.Part1 = child
				weld.Parent = child
			end
		end
	end
	return model
end

-- Is `kind` a Premium golem (Legendary or rarer: it hovers on an aura)?
function GolemBuilder.premium(kind: string): boolean
	local golem = GolemConfig.ById[kind] or LimitedUpcoming.ById[kind]
	if not golem then
		return false
	end
	local info = Rarity.ById[GolemBuilder.PremiumFrom]
	local own = Rarity.ById[golem.Rarity]
	return info ~= nil and own ~= nil and own.Order >= info.Order
end

-- The highest point of a model's parts over `ground` (studs, along its up).
function GolemBuilder.topOver(model: Instance, ground: CFrame): number
	local top = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = ground:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			local up = math.abs(rel.RightVector.Y) * h.X + math.abs(rel.UpVector.Y) * h.Y + math.abs(rel.LookVector.Y) * h.Z
			top = math.max(top, rel.Position.Y + up)
		end
	end
	return top
end

-- Parts in a golem model (the budget the tests check).
function GolemBuilder.partCount(model: Instance): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------- capsules

-- The capsule for the opening animation (see the header).
function GolemBuilder.capsule(capsuleId: string, base: CFrame?): Model
	local capsule = CapsuleConfig.ById[capsuleId]
	if capsule and capsule.Limited and GolemGearLimited.shard(capsule.Limited, KIT) then
		local model = GolemBuilder.shard(capsule.Limited, base, capsule.Color, capsule.Glow)
		model:SetAttribute("Capsule", capsuleId)
		return model
	end
	local color = if capsule then capsule.Color else STONE
	local glow = if capsule then capsule.Glow else rgb(255, 170, 80)
	local center = base or CFrame.new()
	local r = GolemBuilder.CapsuleRadius
	local mid = GolemBuilder.CapsuleHeight / 2 - r -- half the straight part
	local model = Instance.new("Model")
	model.Name = "Capsule"
	local top = Instance.new("Model")
	top.Name = "Top"
	top.Parent = model
	local bottom = Instance.new("Model")
	bottom.Name = "Bottom"
	bottom.Parent = model
	-- invisible upright pivots at the pill's center: PivotTo on the capsule or
	-- a half moves it from there (the shells are cylinders lying on their side)
	local function pivot(parent: Instance, name: string): Part
		local p = part(parent, name, center, Vector3.new(0.2, 0.2, 0.2), color)
		p.Transparency = 1
		return p
	end
	local root = pivot(model, "Root")
	local shell = if capsule and capsule.Shell then capsule.Shell else lighter(color, 0.55)
	upright(top, "Shell", center * CFrame.new(0, mid / 2, 0), mid, 2 * r, shell)
	part(top, "Dome", center * CFrame.new(0, mid, 0), Vector3.new(2 * r, 2 * r, 2 * r), shell, nil, Enum.PartType.Ball)
	-- a small window on the front of the top shell
	part(top, "Window", center * CFrame.new(0, mid * 0.6, -r + 0.02), Vector3.new(0.5, 0.5, 0.06), lighter(glow, 0.25), Enum.Material.Neon)
	top.PrimaryPart = pivot(top, "TopRoot")
	upright(bottom, "Shell", center * CFrame.new(0, -mid / 2, 0), mid, 2 * r, color)
	part(bottom, "Base", center * CFrame.new(0, -mid, 0), Vector3.new(2 * r, 2 * r, 2 * r), color, nil, Enum.PartType.Ball)
	upright(bottom, "Band", center, 0.22, 2 * r + 0.12, glow, Enum.Material.Neon)
	-- cracks on the lower shell, hidden until the capsule shakes
	for i, k in { { -0.5, -0.45, 0.5 }, { 0.35, -0.75, -0.6 }, { 0.05, -1.05, 0.35 } } do
		local a = math.asin(math.clamp(k[1] / r, -1, 1))
		local crack = part(
			bottom,
			"Crack" .. i,
			center * CFrame.new(math.sin(a) * (r + 0.01), k[2], -math.cos(a) * (r + 0.01)) * CFrame.Angles(0, -a, k[3]),
			Vector3.new(0.08, 0.7, 0.04),
			lighter(glow, 0.3),
			Enum.Material.Neon
		)
		crack.Transparency = 1
	end
	bottom.PrimaryPart = pivot(bottom, "BottomRoot")
	model.PrimaryPart = root
	model:SetAttribute("Capsule", capsuleId)
	return model
end

-- A limited edition's SHARD (its set's egg-shaped capsule: GolemGearLimited)
-- with the capsule's contract: sub-models "Top" and "Bottom" with upright
-- invisible pivots "TopRoot" / "BottomRoot" and the model's "Root" at the
-- center, a Neon "Band" and hidden "Crack1..3" in Bottom; at most
-- ShardMaxParts. base = the shard's center, its front faces -Z. A set
-- without a shard (or an unknown one) builds a plain egg-less pill frame.
function GolemBuilder.shard(setId: string, base: CFrame?, color: Color3?, glow: Color3?): Model
	local center = base or CFrame.new()
	local tint = color or STONE
	local model = Instance.new("Model")
	model.Name = "Capsule"
	local top = Instance.new("Model")
	top.Name = "Top"
	top.Parent = model
	local bottom = Instance.new("Model")
	bottom.Name = "Bottom"
	bottom.Parent = model
	local function pivot(parent: Instance, name: string): Part
		local p = part(parent, name, center, Vector3.new(0.2, 0.2, 0.2), tint)
		p.Transparency = 1
		return p
	end
	model.PrimaryPart = pivot(model, "Root")
	top.PrimaryPart = pivot(top, "TopRoot")
	bottom.PrimaryPart = pivot(bottom, "BottomRoot")
	local build = GolemGearLimited.shard(setId, KIT)
	if build then
		build({
			Top = top,
			Bottom = bottom,
			Center = center,
			Color = tint,
			Glow = glow or rgb(255, 170, 80),
			Room = function(): number
				return GolemBuilder.ShardMaxParts - GolemBuilder.partCount(model)
			end,
		})
	end
	for i = 1, 3 do
		local crack = bottom:FindFirstChild("Crack" .. i)
		if crack and crack:IsA("BasePart") then
			crack.Transparency = 1
		end
	end
	model:SetAttribute("Shard", setId)
	return model
end

return GolemBuilder
