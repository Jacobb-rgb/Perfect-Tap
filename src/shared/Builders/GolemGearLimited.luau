--[[
	The LIMITED EDITION golems' gear (PROTOTYPE, Config/LimitedGolems): the
	accessories of the four themed sets, registered into GolemBuilder's
	ACCESSORIES (GolemBuilder calls GolemGearLimited.accessories with its own
	part helpers). Pure: only creates Instances.

	Every accessory follows GolemBuilder's contract: it adds its parts to
	c.Model (positions in unscaled golem units from the feet: c.At / c.V)
	and returns the top of what it added. Some also re-dress the body's own
	parts (Boulder, Crystal, Brow: shoulder spikes, pads, ice shards, snow
	brows) so a theme reads at no part cost. Parts beyond the first few are
	added in priority order only while c.Room() says the golem's part budget
	allows (a limited golem: GolemBuilder.LimitedMaxParts; a capsule golem
	wearing this gear: GolemBuilder.MaxParts), so every accessory builds on
	every golem.

	  A Dragonforge   DragonHorns, DragonEgg, DragonHelm, DragonWings, DragonCrown
	  B Galaxy        SpaceHelmet, Comet, Orbiters, StarHat, StarCrown, NebulaCrown
	  C Mecha Neon    NeonVisor, Headset, MechaCrest, Rockets, JetPack, OmegaFrame
	  D Frost Titans  IcicleHair, Beanie, FrostHelm, SnowCloud, IcicleCrown, AuroraCrown

	When the owner picks one theme, delete the other three sections here and
	their names in GolemConfig.Accessories / Faces.
]]

local GolemConfig = require(script.Parent.Parent.Config.GolemConfig)

local GolemGearLimited = {}

-- (GolemBuilder's Ctx: the golem being built)
export type Ctx = {
	Model: Model,
	At: (x: number, y: number, z: number) -> CFrame,
	V: (x: number, y: number, z: number) -> Vector3,
	Look: GolemConfig.Golem,
	S: number, -- the scale (studs per unit)
	Glow: Color3, -- the glow for Neon parts
	Top: number, -- the top of the head (unscaled units)
	Room: () -> number, -- parts the gear may still add (the budget minus the aura)
}

-- GolemBuilder's part helpers.
export type Kit = {
	part: (
		parent: Instance,
		name: string,
		cf: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?
	) -> Part,
	upright: (
		parent: Instance,
		name: string,
		cf: CFrame,
		height: number,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	) -> Part,
	facing: (parent: Instance, name: string, cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?) -> Part,
	wedge: (parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?) -> BasePart,
	darker: (c: Color3, amount: number) -> Color3,
	lighter: (c: Color3, amount: number) -> Color3,
}

-- Gear that covers the face (GolemBuilder.Faces): "Closed" = no stone brow,
-- the eyes sit a little forward (they glow through a slit or over a visor).
GolemGearLimited.Faces = {
	DragonHelm = "Closed",
	NeonVisor = "Closed",
	MechaCrest = "Closed",
	JetPack = "Closed",
	OmegaFrame = "Closed",
	FrostHelm = "Closed",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local PI = math.pi

local GOLD = rgb(255, 196, 56)
local IVORY = rgb(240, 226, 196)
local SHELL = rgb(252, 242, 218)
local DARK_GLASS = rgb(18, 22, 34)
local CHROME = rgb(214, 220, 232)
local ICE = rgb(196, 242, 255)
local SNOW = rgb(246, 250, 255)
local WOOL_RED = rgb(226, 54, 66)
local MOON = rgb(206, 200, 226)

function GolemGearLimited.accessories(kit: Kit): { [string]: (Ctx) -> number }
	local part, upright, facing, wedge = kit.part, kit.upright, kit.facing, kit.wedge
	local darker, lighter = kit.darker, kit.lighter
	local A: { [string]: (Ctx) -> number } = {}

	-- one of the body's own parts, re-dressed (nil when it isn't there)
	local function redress(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?)
		local p = c.Model:FindFirstChild(name)
		if p and p:IsA("Part") then
			p.CFrame = cf
			p.Size = size
			p.Color = color
			p.Material = material
			p.Shape = shape or Enum.PartType.Block
		end
	end

	-- a small glowing diamond on a front face (stars, gems, cracks)
	local function diamond(c: Ctx, name: string, x: number, y: number, z: number, size: number, color: Color3?)
		part(c.Model, name, c.At(x, y, z) * CFrame.Angles(0, 0, PI / 4), c.V(size, size, 0.05), color or c.Glow, NEON)
	end

	-- a cylinder along X (ear cups, ear lights)
	local function sideways(
		c: Ctx,
		name: string,
		x: number,
		y: number,
		z: number,
		length: number,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	)
		part(c.Model, name, c.At(x, y, z), c.V(length, diameter, diameter), color, material, CYLINDER)
	end

	local function ball(
		c: Ctx,
		name: string,
		x: number,
		y: number,
		z: number,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	): Part
		return part(c.Model, name, c.At(x, y, z), c.V(diameter, diameter, diameter), color, material, BALL)
	end

	---------------------------------------------------------------- A: Dragonforge

	-- every dragon: shoulder spikes (the boulder in the trim, the crystal glowing like lava)
	local function dragonBody(c: Ctx)
		redress(
			c,
			"Boulder",
			c.At(-0.62, 1.66, 0.08) * CFrame.Angles(0, 0, 0.55) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.3, 0.62, 0.3),
			c.Look.Trim,
			M.Slate
		)
		redress(
			c,
			"Crystal",
			c.At(0.62, 1.66, 0.08) * CFrame.Angles(0, 0, -0.55) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.3, 0.62, 0.3),
			c.Glow,
			NEON
		)
	end

	-- one curved horn on `side`: a thick base growing out of the head's
	-- side, a tip curving up (2 parts). Returns its top (unscaled).
	local function horn(
		c: Ctx,
		i: number,
		side: number,
		x: number,
		y: number,
		z: number,
		length: number,
		base: Color3,
		tip: Color3,
		tipMaterial: Enum.Material
	): number
		local s = c.S
		local root = c.At(side * x, y, z) * CFrame.Angles(0.2, 0, -side * 1.05)
		local h1, h2 = 0.42 * length, 0.46 * length
		part(c.Model, "HornBase" .. i, root * CFrame.new(0, h1 / 2 * s, 0), c.V(0.3, h1, 0.3), base, M.Slate)
		local bend = root * CFrame.new(0, h1 * s, 0) * CFrame.Angles(0.15, 0, side * 0.95)
		part(c.Model, "HornTip" .. i, bend * CFrame.new(0, h2 / 2 * s, 0), c.V(0.2, h2, 0.2), tip, tipMaterial)
		return y + h1 * 0.5 + h2 * 0.99
	end

	local function horns(
		c: Ctx,
		x: number,
		y: number,
		z: number,
		length: number,
		base: Color3,
		tip: Color3,
		tipMaterial: Enum.Material
	): number
		local top = 0
		for i, side in { -1, 1 } do
			top = horn(c, i, side, x, y, z, length, base, tip, tipMaterial)
		end
		return top
	end

	-- a dragon snout on the lower face with two glowing nostrils (3 parts)
	local function snout(c: Ctx)
		part(c.Model, "Snout", c.At(0, 1.74, -0.74), c.V(0.78, 0.38, 0.24), lighter(c.Look.Body, 0.08), M.Slate)
		for i, x in { -0.16, 0.16 } do
			part(c.Model, "Nostril" .. i, c.At(x, 1.8, -0.87), c.V(0.1, 0.08, 0.04), c.Glow, NEON)
		end
	end

	-- A bat wing's frame on `side`: the shoulder blade (turned a little
	-- back), the arm direction (shoulder -> wrist, `angle` over the
	-- horizontal) and the outer edge's (wrist -> tip), unscaled.
	local function wingFrame(c: Ctx, side: number, angle: number): (CFrame, Vector3, Vector3)
		local root = c.At(side * 0.3, 1.5, 0.48) * CFrame.Angles(0, -side * 0.22, 0)
		return root, Vector3.new(side * math.cos(angle), math.sin(angle), 0), Vector3.new(side * math.sin(angle), -math.cos(angle), 0)
	end

	-- A bat wing on `side`: the arm bone runs from the shoulder blade up and
	-- out to the wrist (`arm` long), the outer edge from the wrist down and
	-- out to the tip (`finger` long); the membrane is the right-angled wedge
	-- between them (its right angle the wrist). 2 parts. Returns the wrist's
	-- height (unscaled).
	local function wing(
		c: Ctx,
		i: number,
		side: number,
		arm: number,
		finger: number,
		angle: number,
		membrane: Color3,
		bone: Color3,
		boneMaterial: Enum.Material
	): number
		local s = c.S
		local root, up, out = wingFrame(c, side, angle)
		local center = (up * arm + out * finger) * (s / 2)
		wedge(
			c.Model,
			"Wing" .. i,
			root * CFrame.fromMatrix(center, out:Cross(up), out, up),
			Vector3.new(0.06, finger, arm) * s,
			membrane,
			M.Slate
		)
		part(
			c.Model,
			"WingBone" .. i,
			root * CFrame.new(up * (arm * s / 2)) * CFrame.Angles(0, 0, side * angle),
			c.V(arm + 0.1, 0.12, 0.12),
			bone,
			boneMaterial
		)
		return 1.5 + arm * math.sin(angle) + 0.1
	end

	-- A second membrane hanging from a wing's tip (a two-pointed wing):
	-- right-angled at the tip, one leg back to the shoulder. 1 part.
	local function wingLobe(c: Ctx, i: number, side: number, arm: number, finger: number, angle: number, membrane: Color3)
		local s = c.S
		local root, up, out = wingFrame(c, side, angle)
		local tip = up * arm + out * finger
		local back = tip.Unit
		local down = Vector3.new(side * back.Y, -side * back.X, 0)
		local length = finger * 0.8
		wedge(
			c.Model,
			"WingLobe" .. i,
			root * CFrame.fromMatrix((tip + down * length) * (s / 2), down:Cross(back), down, back),
			Vector3.new(0.05, length, tip.Magnitude) * s,
			darker(membrane, 0.22),
			M.Slate
		)
	end

	A.DragonHorns = function(c)
		dragonBody(c)
		local top = horns(c, 0.66, 2.5, 0.1, 1, IVORY, IVORY, M.Slate)
		if c.Room() >= 3 then
			snout(c)
		end
		return top
	end

	A.DragonEgg = function(c)
		dragonBody(c)
		-- the top of the shell sits on the head like a cap, its broken rim zigzags over the forehead
		ball(c, "Shell", 0, 2.66, 0.02, 1.5, SHELL, M.SmoothPlastic)
		for i, x in { -0.5, -0.17, 0.17, 0.5 } do
			if c.Room() >= 1 then
				part(
					c.Model,
					"ShellPoint" .. i,
					c.At(x, 2.56, -0.69) * CFrame.Angles(0, 0, PI / 4),
					c.V(0.28, 0.28, 0.06),
					SHELL,
					M.SmoothPlastic
				)
			end
		end
		-- orange spots on the shell
		for i, k in { { -0.3, 3.0, -0.52, 0.3 }, { 0.34, 3.2, -0.34, 0.24 }, { 0.05, 3.38, 0.1, 0.22 } } do
			if c.Room() >= 1 then
				ball(c, "Spot" .. i, k[1], k[2], k[3], k[4], rgb(240, 120, 40), M.SmoothPlastic)
			end
		end
		return 2.66 + 0.75
	end

	A.DragonHelm = function(c)
		dragonBody(c)
		-- a closed helm of dragon scales; the eyes glow through its slit
		part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), c.Look.Trim, M.Metal)
		part(c.Model, "Slit", c.At(0, 2.06, -0.71), c.V(1.12, 0.24, 0.04), rgb(20, 14, 18))
		local top = horns(c, 0.72, 2.4, 0.1, 1.3, GOLD, IVORY, M.Slate)
		-- a glowing crest of scales over the top
		for i, z in { -0.25, 0.25 } do
			if c.Room() >= 1 then
				part(c.Model, "Crest" .. i, c.At(0, 2.86, z) * CFrame.Angles(PI / 4, 0, 0), c.V(0.1, 0.34, 0.34), c.Glow, NEON)
			end
		end
		return top
	end

	A.DragonWings = function(c)
		dragonBody(c)
		local premium = c.Look.Rarity == "Legendary" or c.Look.Rarity == "Mythic"
		local arm, finger = if premium then 1.4 else 1.25, if premium then 1.25 else 1.05
		local membrane = c.Look.Trim:Lerp(c.Look.Glow, if premium then 0.32 else 0.5)
		if premium then
			-- lava hands
			for _, name in { "Fist1", "Fist2" } do
				local fist = c.Model:FindFirstChild(name)
				if fist and fist:IsA("BasePart") then
					fist.Color = c.Look.Trim:Lerp(c.Look.Glow, 0.7)
					fist.Material = NEON
				end
			end
		end
		local top = 0
		for i, side in { -1, 1 } do
			top = wing(c, i, side, arm, finger, 0.9, membrane, c.Glow, NEON)
		end
		-- small horns
		if c.Room() >= 4 then
			top = math.max(top, horns(c, 0.66, 2.5, 0.1, 0.85, IVORY, IVORY, M.Slate))
		end
		if premium then
			for i, side in { -1, 1 } do
				if c.Room() >= 1 then
					wingLobe(c, i, side, arm, finger, 0.9, membrane)
				end
			end
		end
		if c.Room() >= 3 then
			snout(c)
		end
		return top
	end

	A.DragonCrown = function(c)
		dragonBody(c)
		-- the Dragon King: a big gold crown, gold-boned wings, ivory horns
		upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.28 * c.S, 1.2 * c.S, GOLD, M.Foil)
		local top = 0
		for i, side in { -1, 1 } do
			top = wing(c, i, side, 1.6, 1.4, 0.88, rgb(150, 26, 34), GOLD, M.Foil)
		end
		for i, k in { { -0.4, -0.25, 0.6 }, { 0, -0.46, 0 }, { 0.4, -0.25, -0.6 } } do
			if c.Room() >= 1 then
				part(
					c.Model,
					"CrownPoint" .. i,
					c.At(k[1], 3.08, k[2]) * CFrame.Angles(0, k[3], 0) * CFrame.Angles(0, 0, PI / 4),
					c.V(0.28, 0.28, 0.08),
					GOLD,
					M.Foil
				)
			end
		end
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				wingLobe(c, i, side, 1.6, 1.4, 0.88, rgb(150, 26, 34))
			end
		end
		if c.Room() >= 4 then
			horns(c, 0.66, 2.5, 0.1, 0.9, IVORY, IVORY, M.Slate)
		end
		if c.Room() >= 1 then
			part(c.Model, "CrownGem", c.At(0, 2.86, -0.61) * CFrame.Angles(0, 0, PI / 4), c.V(0.18, 0.18, 0.06), c.Glow, NEON)
		end
		return math.max(top, 3.3)
	end

	---------------------------------------------------------------- B: Galaxy

	-- every space golem: a little moon on one shoulder, a star on the other
	local function cosmicBody(c: Ctx)
		redress(c, "Boulder", c.At(-0.62, 1.6, 0.12), c.V(0.5, 0.5, 0.5), MOON, M.Slate, BALL)
		redress(c, "Crystal", c.At(0.6, 1.66, 0.14) * CFrame.Angles(0, 0, PI / 4), c.V(0.34, 0.34, 0.34), lighter(c.Look.Glow, 0.15), NEON)
	end

	-- star specks on the chest, while the budget allows
	local function specks(c: Ctx, list: { { number } })
		for i, k in list do
			if c.Room() >= 1 then
				diamond(c, "Speck" .. i, k[1], k[2], -0.45, k[3], lighter(c.Glow, 0.3))
			end
		end
	end

	-- a planet ring: a thin glowing disc round the head (the head hides its middle)
	local function planetRing(c: Ctx, y: number, diameter: number, color: Color3, transparency: number, tilt: number): Part
		local ring = upright(c.Model, "Ring", c.At(0, y, 0) * CFrame.Angles(tilt, 0, 0.16), 0.04 * c.S, diameter * c.S, color, NEON)
		ring.Transparency = transparency
		return ring
	end

	A.SpaceHelmet = function(c)
		cosmicBody(c)
		-- a glass bubble round the head on a white collar
		local bubble = ball(c, "Bubble", 0, 2.12, 0, 2.3, rgb(200, 236, 255), M.Glass)
		bubble.Transparency = 0.6
		upright(c.Model, "Collar", c.At(0, 1.46, 0), 0.18 * c.S, 1.56 * c.S, CHROME, M.Metal)
		if c.Room() >= 2 then
			part(c.Model, "Antenna", c.At(0.42, 3.24, 0.1) * CFrame.Angles(0, 0, -0.25), c.V(0.07, 0.42, 0.07), CHROME, M.Metal)
			ball(c, "AntennaTip", 0.48, 3.48, 0.1, 0.2, c.Glow, NEON)
		end
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 3.58
	end

	A.Comet = function(c)
		cosmicBody(c)
		-- a comet sits on the head, its glowing tail streams up and away
		ball(c, "Comet", -0.22, 2.98, -0.15, 0.56, c.Glow, NEON)
		for i, k in { { 0.16, 3.22, 0.0, 0.44, 0.15 }, { 0.5, 3.46, 0.12, 0.34, 0.35 }, { 0.8, 3.68, 0.22, 0.24, 0.55 } } do
			if c.Room() >= 1 then
				local tail = ball(c, "Tail" .. i, k[1], k[2], k[3], k[4], lighter(c.Glow, 0.2 + i * 0.1), NEON)
				tail.Transparency = k[5]
			end
		end
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 3.82
	end

	A.Orbiters = function(c)
		cosmicBody(c)
		planetRing(c, 2.5, 2.7, c.Glow, 0.6, 0.32)
		-- two little moons riding the ring
		if c.Room() >= 2 then
			ball(c, "MoonA", -1.22, 2.36, -0.45, 0.44, rgb(255, 150, 90), M.SmoothPlastic)
			ball(c, "MoonB", 1.2, 2.72, 0.35, 0.34, rgb(120, 255, 200), M.SmoothPlastic)
		end
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 3.0
	end

	A.StarHat = function(c)
		cosmicBody(c)
		-- a pointed wizard hat with a bent tip and a big star
		local hat = rgb(70, 52, 170)
		upright(c.Model, "Brim", c.At(0, 2.74, 0), 0.08 * c.S, 2.04 * c.S, darker(hat, 0.3))
		upright(c.Model, "Hat1", c.At(0, 2.99, 0), 0.46 * c.S, 1.22 * c.S, hat)
		upright(c.Model, "Hat2", c.At(0.05, 3.42, 0.02), 0.42 * c.S, 0.86 * c.S, hat)
		upright(c.Model, "Hat3", c.At(0.12, 3.8, 0.04), 0.38 * c.S, 0.54 * c.S, hat)
		part(c.Model, "HatTip", c.At(0.36, 4.06, 0.06) * CFrame.Angles(0, 0, -0.95), c.V(0.26, 0.46, 0.26), hat)
		if c.Room() >= 1 then
			part(c.Model, "HatStar", c.At(0, 3.02, -0.63) * CFrame.Angles(0, 0, PI / 4), c.V(0.36, 0.36, 0.06), GOLD, NEON)
		end
		if c.Room() >= 1 then
			diamond(c, "HatSpeck", 0.24, 3.44, -0.44, 0.14, lighter(c.Glow, 0.3))
		end
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 4.25
	end

	-- a ring of star points floating over the head (`count` parts)
	local function starCrown(c: Ctx, count: number, y: number, r: number, color: Color3)
		for i = 1, count do
			if c.Room() >= 1 then
				local a = PI / 2 + (i - (count + 1) / 2) * (PI / (count + 1)) * 1.6
				part(
					c.Model,
					"StarPoint" .. i,
					c.At(math.cos(a) * r, y + (if i == (count + 1) / 2 then 0.12 else 0), -math.sin(a) * r * 0.6)
						* CFrame.Angles(0, 0, PI / 4),
					c.V(0.24, 0.24, 0.08),
					color,
					NEON
				)
			end
		end
	end

	A.StarCrown = function(c)
		cosmicBody(c)
		planetRing(c, 2.45, 3.0, c.Glow, 0.6, 0.3)
		starCrown(c, 5, 3.08, 0.62, GOLD)
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 3.3
	end

	A.NebulaCrown = function(c)
		cosmicBody(c)
		-- a nebula glowing behind the head, a planet ring, two planets, a crown of stars
		local pink = ball(c, "NebulaA", -0.5, 2.7, 0.75, 2.0, rgb(200, 50, 170), NEON)
		pink.Transparency = 0.88
		local violet = ball(c, "NebulaB", 0.55, 2.95, 0.8, 1.7, rgb(90, 60, 220), NEON)
		violet.Transparency = 0.88
		planetRing(c, 2.45, 3.1, rgb(80, 200, 240), 0.6, 0.3)
		if c.Room() >= 2 then
			ball(c, "PlanetA", -1.36, 2.3, -0.4, 0.5, rgb(255, 170, 80), M.SmoothPlastic)
			ball(c, "PlanetB", 1.32, 2.68, 0.4, 0.38, rgb(110, 255, 210), M.SmoothPlastic)
		end
		starCrown(c, 3, 3.08, 0.5, GOLD)
		specks(c, { { -0.3, 1.24, 0.12 }, { 0.32, 0.78, 0.09 } })
		return 3.8
	end

	---------------------------------------------------------------- C: Mecha Neon

	-- every robot: square shoulder pads in the trim
	local function mechaBody(c: Ctx)
		for _, side in { -1, 1 } do
			redress(
				c,
				if side < 0 then "Boulder" else "Crystal",
				c.At(side * 0.74, 1.52, 0.02) * CFrame.Angles(0, 0, -side * 0.18),
				c.V(0.6, 0.34, 0.7),
				c.Look.Trim,
				M.Metal
			)
		end
	end

	-- a dark visor band across the face (the eyes glow on it)
	local function visor(c: Ctx)
		part(c.Model, "VisorBand", c.At(0, 2.04, -0.69), c.V(1.4, 0.46, 0.06), DARK_GLASS, M.SmoothPlastic)
	end

	-- a V-fin crest with a gem in the middle (3 parts)
	local function vFin(c: Ctx, color: Color3, size: number)
		for i, side in { -1, 1 } do
			part(
				c.Model,
				"Fin" .. i,
				c.At(side * 0.26 * size, 2.62 + 0.26 * size, -0.68) * CFrame.Angles(0, 0, -side * 0.85),
				c.V(0.14, 0.78 * size, 0.08),
				color,
				M.Metal
			)
		end
		if c.Room() >= 1 then
			part(c.Model, "Gem", c.At(0, 2.6, -0.72) * CFrame.Angles(0, 0, PI / 4), c.V(0.24, 0.24, 0.07), c.Glow, NEON)
		end
	end

	-- glowing flames under the feet (jet boots), in the hover gap
	local function bootFlames(c: Ctx, color: Color3)
		for i, x in { -0.3, 0.3 } do
			if c.Room() >= 1 then
				local flame =
					part(c.Model, "BootFlame" .. i, c.At(x, -0.1, 0.02) * CFrame.Angles(0, PI / 4, 0), c.V(0.3, 0.18, 0.3), color, NEON)
				flame.Transparency = 0.15
			end
		end
	end

	-- twin boosters on the back with short wings
	local function boosters(c: Ctx, wings: boolean)
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				upright(c.Model, "Booster" .. i, c.At(side * 0.34, 1.05, 0.62), 0.86 * c.S, 0.42 * c.S, c.Look.Trim, M.Metal)
			end
		end
		if wings then
			for i, side in { -1, 1 } do
				if c.Room() >= 1 then
					wedge(
						c.Model,
						"JetWing" .. i,
						c.At(side * 0.95, 1.2, 0.62) * CFrame.Angles(0, 0, side * 0.35) * CFrame.Angles(0, side * PI / 2, 0),
						c.V(0.08, 0.5, 1.0),
						lighter(c.Look.Body, 0.1),
						M.Metal
					)
				end
			end
		end
	end

	A.NeonVisor = function(c)
		mechaBody(c)
		visor(c)
		sideways(c, "EarLight1", -0.78, 2.05, 0, 0.1, 0.44, c.Glow, NEON)
		sideways(c, "EarLight2", 0.78, 2.05, 0, 0.1, 0.44, c.Glow, NEON)
		if c.Room() >= 2 then
			part(c.Model, "Antenna", c.At(0.42, 2.98, 0), c.V(0.07, 0.56, 0.07), CHROME, M.Metal)
			ball(c, "AntennaTip", 0.42, 3.3, 0, 0.22, c.Glow, NEON)
		end
		if c.Room() >= 1 then
			part(c.Model, "ChestLight", c.At(0, 1.28, -0.44), c.V(0.7, 0.07, 0.05), c.Glow, NEON)
		end
		return 3.41
	end

	A.Headset = function(c)
		mechaBody(c)
		-- big headphones: a band over the head, ear cups with neon rings
		local band = c.Look.Trim
		part(c.Model, "Headband", c.At(0, 2.84, 0), c.V(1.74, 0.16, 0.26), band, M.Metal)
		for i, side in { -1, 1 } do
			sideways(c, "EarCup" .. i, side * 0.86, 2.12, 0, 0.24, 0.74, band, M.Metal)
			if c.Room() >= 1 then
				sideways(c, "EarRing" .. i, side * 0.99, 2.12, 0, 0.04, 0.52, c.Glow, NEON)
			end
		end
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				part(c.Model, "BandSide" .. i, c.At(side * 0.84, 2.62, 0), c.V(0.14, 0.46, 0.22), band, M.Metal)
			end
		end
		if c.Room() >= 1 then
			part(c.Model, "ChestLight", c.At(0, 1.28, -0.44), c.V(0.7, 0.07, 0.05), c.Glow, NEON)
		end
		return 2.92
	end

	A.MechaCrest = function(c)
		mechaBody(c)
		visor(c)
		vFin(c, GOLD, 1)
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				part(
					c.Model,
					"EarFin" .. i,
					c.At(side * 0.8, 2.42, 0.12) * CFrame.Angles(0.45, 0, 0),
					c.V(0.1, 0.56, 0.26),
					c.Look.Trim,
					M.Metal
				)
			end
		end
		if c.Room() >= 1 then
			part(c.Model, "ChestLight", c.At(0, 1.28, -0.44), c.V(0.7, 0.07, 0.05), c.Glow, NEON)
		end
		return 2.62 + 0.26 + 0.39
	end

	A.Rockets = function(c)
		-- rocket pods on the shoulders (the shoulder parts), glowing rocket noses
		for _, side in { -1, 1 } do
			redress(
				c,
				if side < 0 then "Boulder" else "Crystal",
				c.At(side * 0.78, 1.72, 0.06),
				c.V(0.56, 0.56, 0.86),
				c.Look.Trim,
				M.Metal
			)
		end
		for i, k in { { -0.88, 1.82 }, { -0.68, 1.62 }, { 0.68, 1.62 }, { 0.88, 1.82 } } do
			if c.Room() >= 1 then
				facing(c.Model, "Rocket" .. i, c.At(k[1], k[2], -0.4), 0.08 * c.S, 0.18 * c.S, c.Glow, NEON)
			end
		end
		-- a row of three glowing dino spikes over the head
		for i, k in { { -0.42, 0.34 }, { 0, 0.46 }, { 0.42, 0.34 } } do
			if c.Room() >= 1 then
				part(c.Model, "Spike" .. i, c.At(k[1], 2.7, 0.05) * CFrame.Angles(0, 0, PI / 4), c.V(k[2], k[2], 0.12), c.Glow, NEON)
			end
		end
		return 2.7 + 0.46 * 0.71
	end

	A.JetPack = function(c)
		mechaBody(c)
		visor(c)
		vFin(c, CHROME, 0.8)
		bootFlames(c, rgb(255, 150, 40))
		boosters(c, true)
		return 2.62 + 0.26 * 0.8 + 0.32
	end

	A.OmegaFrame = function(c)
		mechaBody(c)
		visor(c)
		vFin(c, GOLD, 1.25)
		boosters(c, true)
		bootFlames(c, c.Glow)
		if c.Room() >= 1 then
			part(c.Model, "ChestLight", c.At(0, 1.28, -0.44), c.V(0.7, 0.07, 0.05), c.Glow, NEON)
		end
		return 2.62 + 0.26 * 1.25 + 0.5
	end

	---------------------------------------------------------------- D: Frost Titans

	-- every ice golem: a snowy brow, snow on one shoulder, an ice shard on the other
	local function frostBody(c: Ctx)
		local brow = c.Model:FindFirstChild("Brow")
		if brow and brow:IsA("BasePart") then
			brow.Color = SNOW
			brow.Material = M.Snow
		end
		redress(c, "Boulder", c.At(-0.6, 1.5, 0.12) * CFrame.Angles(0.1, 0.4, 0.2), c.V(0.6, 0.36, 0.56), SNOW, M.Snow)
		redress(
			c,
			"Crystal",
			c.At(0.58, 1.74, 0.18) * CFrame.Angles(0.2, 0.785, -0.42) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.3, 0.86, 0.3),
			ICE,
			M.Glass
		)
	end

	-- an icicle standing on the head (a diamond-section spike)
	local function icicle(c: Ctx, name: string, x: number, y: number, z: number, height: number, lean: number, color: Color3?)
		part(
			c.Model,
			name,
			c.At(x, y + height / 2, z) * CFrame.Angles(0, 0, lean) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.2, height, 0.2),
			color or ICE,
			M.Glass
		)
	end

	A.IcicleHair = function(c)
		frostBody(c)
		for i, k in { { -0.48, 0.5, 0.45 }, { -0.24, 0.7, 0.2 }, { 0, 0.86, 0 }, { 0.24, 0.66, -0.2 }, { 0.48, 0.48, -0.45 } } do
			if c.Room() >= 1 then
				icicle(c, "Icicle" .. i, k[1], 2.62, 0, k[2], k[3])
			end
		end
		return 2.62 + 0.86
	end

	A.Beanie = function(c)
		frostBody(c)
		-- a knitted beanie with a pom-pom, and a scarf
		part(c.Model, "Beanie", c.At(0, 2.78, 0.02), c.V(1.58, 0.52, 1.4), WOOL_RED)
		part(c.Model, "BeanieFold", c.At(0, 2.56, 0.02), c.V(1.66, 0.22, 1.48), SNOW, M.Fabric)
		ball(c, "PomPom", 0, 3.18, 0.02, 0.5, SNOW, M.Fabric)
		if c.Room() >= 2 then
			part(c.Model, "Scarf", c.At(0, 1.5, 0), c.V(1.32, 0.24, 0.98), WOOL_RED, M.Fabric)
			part(c.Model, "ScarfEnd", c.At(0.34, 1.16, -0.5) * CFrame.Angles(0, 0, 0.12), c.V(0.28, 0.56, 0.08), WOOL_RED, M.Fabric)
		end
		return 3.43
	end

	A.FrostHelm = function(c)
		frostBody(c)
		-- a closed helm of ice; the eyes glow through its slit; an icicle sword
		part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), lighter(c.Look.Body, 0.35), M.Ice)
		part(c.Model, "Slit", c.At(0, 2.06, -0.71), c.V(1.12, 0.24, 0.04), rgb(16, 30, 60))
		for i, k in { { -0.4, 0.5, 0.3 }, { 0, 0.72, 0 }, { 0.4, 0.5, -0.3 } } do
			if c.Room() >= 1 then
				icicle(c, "HelmSpike" .. i, k[1], 2.7, 0.05, k[2], k[3])
			end
		end
		if c.Room() >= 2 then
			part(c.Model, "SwordGuard", c.At(0.86, 0.94, -0.12), c.V(0.5, 0.1, 0.16), c.Look.Trim, M.Metal)
			part(c.Model, "Sword", c.At(0.86, 1.62, -0.12) * CFrame.Angles(0, PI / 4, 0), c.V(0.16, 1.26, 0.16), ICE, M.Glass)
		end
		return 2.7 + 0.72
	end

	A.SnowCloud = function(c)
		frostBody(c)
		-- a hood with a glowing snowflake, and its own little snow cloud
		part(c.Model, "Hood", c.At(0, 2.42, 0.12), c.V(1.68, 0.9, 1.3), c.Look.Trim)
		part(c.Model, "HoodPeak", c.At(0, 2.92, 0.2), c.V(1.2, 0.2, 1.0), darker(c.Look.Trim, 0.15))
		for i = 1, 3 do
			if c.Room() >= 1 then
				part(
					c.Model,
					"Flake" .. i,
					c.At(0, 2.66, -0.55) * CFrame.Angles(0, 0, (i - 1) * PI / 3),
					c.V(0.06, 0.36, 0.04),
					c.Glow,
					NEON
				)
			end
		end
		for i, k in { { -0.3, 3.62, 0.56 }, { 0.12, 3.74, 0.64 }, { 0.46, 3.6, 0.5 } } do
			if c.Room() >= 1 then
				ball(c, "Cloud" .. i, k[1], k[2], 0.1, k[3], SNOW, M.SmoothPlastic)
			end
		end
		return 4.06
	end

	-- a crown of icicles round a band of ice (1 + `count` parts)
	local function iceCrown(c: Ctx, count: number, tallest: number)
		upright(c.Model, "CrownBand", c.At(0, 2.84, 0), 0.24 * c.S, 1.2 * c.S, ICE, M.Glass)
		for i = 1, count do
			if c.Room() >= 1 then
				local t = (i - 1) / (count - 1) * 2 - 1 -- -1 .. 1 across the front
				local a = PI / 2 + t * 1.15
				local height = tallest * (1 - 0.42 * math.abs(t))
				icicle(c, "CrownSpike" .. i, math.cos(a) * 0.5, 2.9, -math.sin(a) * 0.5 + 0.05, height, -t * 0.32, lighter(ICE, 0.2))
			end
		end
	end

	A.IcicleCrown = function(c)
		frostBody(c)
		iceCrown(c, 5, 0.95)
		-- ice shards growing from the back
		for i, k in { { -0.34, 1.7, 0.5, 0.9, -0.4 }, { 0.3, 1.8, 0.55, 1.1, 0.35 } } do
			if c.Room() >= 1 then
				part(
					c.Model,
					"BackShard" .. i,
					c.At(k[1], k[2], k[3]) * CFrame.Angles(0.4, 0, k[5]) * CFrame.Angles(0, PI / 4, 0),
					c.V(0.3, k[4], 0.3),
					ICE,
					M.Glass
				)
			end
		end
		return 2.9 + 0.95
	end

	A.AuroraCrown = function(c)
		frostBody(c)
		iceCrown(c, 3, 0.9)
		-- the northern lights: glowing ribbons fanned round the head like a halo
		local green, cyan, violet = rgb(40, 220, 130), rgb(30, 170, 220), rgb(140, 80, 240)
		local colors = { cyan, green, violet, violet, green }
		for i, lean in { 0, -0.6, 0.6, -1.2, 1.2 } do
			if c.Room() >= 1 then
				local ribbon = part(
					c.Model,
					"Aurora" .. i,
					c.At(-math.sin(lean) * 1.25, 2.1 + math.cos(lean) * 1.25, 0.78) * CFrame.Angles(0, 0, lean),
					c.V(0.5, 1.6, 0.04),
					colors[i],
					NEON
				)
				ribbon.Transparency = 0.4
			end
		end
		return 2.1 + 1.25 + 0.8
	end

	return A
end

return GolemGearLimited
