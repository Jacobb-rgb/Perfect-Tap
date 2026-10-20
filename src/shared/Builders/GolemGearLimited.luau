--[[
	The LIMITED EDITION golems' gear (GolemConfig Edition, Config/
	LimitedGolems): the themed accessories of each set, registered into
	GolemBuilder's ACCESSORIES (GolemBuilder calls GolemGearLimited.
	accessories with its own part helpers). Pure: only creates Instances.

	Every accessory follows GolemBuilder's contract: it adds its parts to
	c.Model (positions in unscaled golem units from the feet: c.At / c.V)
	and returns the top of what it added. They also re-dress the body's own
	parts (Boulder, Crystal, Core, Fists: shoulder spikes, a lava core, lava
	hands) so the theme reads at no part cost. Parts beyond the first few
	are added in priority order only while c.Room() says the golem's part
	budget allows (a limited golem: GolemBuilder.LimitedMaxParts = 25; a
	capsule golem wearing this gear: GolemBuilder.MaxParts), so every
	accessory builds on every golem.

	  Dragonforge (October / November 2026):
	    DragonHorns   Cinder Whelp: curved ivory horns, little bat wings, a
	                  snout, a tail with a glowing tip
	    DragonEgg     Ember Hatchling: the top of its dragon egg as a cap
	                  (a broken zigzag rim, spots), stubby wings, a tail
	    DragonHelm    Dragonscale Knight: a closed helm shaped like a dragon's
	                  head (the upper jaw over the eye slit, horns, a glowing
	                  crest) and a dragon shield
	    DragonWings   Flamewing (Epic): big fiery two-pointed wings, horns, a
	                  snout; Magma Wyvern (Legendary): bigger wings, a tail,
	                  lava hands
	    DragonCrown   Dragon King: a crown of flames on a gold band and huge
	                  gold-boned two-pointed wings

	A new edition adds its own section (and its names to GolemConfig.
	Accessories / Faces); an old one stays: its golems live on in the saves.
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
-- the eyes sit a little forward (they glow through a slit).
GolemGearLimited.Faces = {
	DragonHelm = "Closed",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local GOLD = rgb(255, 196, 56)
local IVORY = rgb(244, 230, 200)
local SHELL = rgb(252, 240, 214)
local SPOT = rgb(240, 120, 40)
local FLAME_HOT = rgb(255, 214, 70)
local FLAME = rgb(255, 120, 24)

function GolemGearLimited.accessories(kit: Kit): { [string]: (Ctx) -> number }
	local part, upright, wedge = kit.part, kit.upright, kit.wedge
	local darker, lighter = kit.darker, kit.lighter
	local A: { [string]: (Ctx) -> number } = {}

	-- one of the body's own parts, re-dressed (nothing when it isn't there)
	local function redress(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material)
		local p = c.Model:FindFirstChild(name)
		if p and p:IsA("Part") then
			p.CFrame = cf
			p.Size = size
			p.Color = color
			p.Material = material
		end
	end

	local function recolor(c: Ctx, name: string, color: Color3, material: Enum.Material)
		local p = c.Model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = color
			p.Material = material
		end
	end

	---------------------------------------------------------------- Dragonforge

	-- every dragon: shoulder spikes (the boulder in the trim, the crystal
	-- glowing like lava) and a bigger glowing lava core on the chest
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
		redress(c, "Core", c.At(0, 0.98, -0.445) * CFrame.Angles(0, 0, PI / 4), c.V(0.34, 0.34, 0.06), c.Glow, NEON)
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

	-- a pair of curved horns (4 parts)
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

	-- a dragon snout on the lower face (1 part; `nostrils` adds two glowing ones)
	local function snout(c: Ctx, nostrils: boolean)
		part(c.Model, "Snout", c.At(0, 1.74, -0.74), c.V(0.8, 0.38, 0.26), lighter(c.Look.Body, 0.08), M.Slate)
		if nostrils and c.Room() >= 2 then
			for i, x in { -0.16, 0.16 } do
				part(c.Model, "Nostril" .. i, c.At(x, 1.8, -0.88), c.V(0.1, 0.08, 0.04), c.Glow, NEON)
			end
		end
	end

	-- A dragon tail curling out from behind the hip to the golem's left and
	-- forward, ending in a spade (2 parts), so it shows from the front.
	local function tail(c: Ctx, size: number, color: Color3, tipColor: Color3, tipMaterial: Enum.Material)
		local s = c.S
		local endX, endZ = 0.32 + 0.95 * size, 0.42 - 0.6 * size
		local from = c.At(0.32, 0.46, 0.42).Position
		local to = c.At(endX, 0.22, endZ).Position
		local length = (to - from).Magnitude
		part(c.Model, "Tail", CFrame.lookAt((from + to) / 2, to), Vector3.new(0.24 * s, 0.22 * s, length + 0.1 * s), color, M.Slate)
		-- the spade faces the front, a diamond standing on the tail's end
		part(
			c.Model,
			"TailTip",
			c.At(endX + 0.1 * size, 0.24 + 0.17 * size, endZ - 0.04) * CFrame.Angles(0, 0, PI / 4),
			c.V(0.3 * size, 0.3 * size, 0.08),
			tipColor,
			tipMaterial
		)
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
	-- between them (its right angle the wrist). 2 parts, or 1 without a
	-- bone. Returns the wrist's height (unscaled).
	local function wing(
		c: Ctx,
		i: number,
		side: number,
		arm: number,
		finger: number,
		angle: number,
		membrane: Color3,
		bone: Color3?,
		boneMaterial: Enum.Material?
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
		if bone then
			part(
				c.Model,
				"WingBone" .. i,
				root * CFrame.new(up * (arm * s / 2)) * CFrame.Angles(0, 0, side * angle),
				c.V(arm + 0.1, 0.12, 0.12),
				bone,
				boneMaterial
			)
		end
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

	-- a pair of wings (bones: 4 parts, without: 2), then their lobes while the budget allows
	local function wings(
		c: Ctx,
		arm: number,
		finger: number,
		angle: number,
		membrane: Color3,
		bone: Color3?,
		boneMaterial: Enum.Material?
	): number
		local top = 0
		for i, side in { -1, 1 } do
			top = wing(c, i, side, arm, finger, angle, membrane, bone, boneMaterial)
		end
		return top
	end

	local function lobes(c: Ctx, arm: number, finger: number, angle: number, membrane: Color3)
		if c.Room() >= 2 then
			for i, side in { -1, 1 } do
				wingLobe(c, i, side, arm, finger, angle, membrane)
			end
		end
	end

	A.DragonHorns = function(c)
		-- Cinder Whelp: a baby dragon
		dragonBody(c)
		local top = horns(c, 0.66, 2.5, 0.1, 1, IVORY, IVORY, M.Slate)
		local membrane = c.Look.Trim:Lerp(c.Look.Glow, 0.4)
		if c.Room() >= 4 then
			top = math.max(top, wings(c, 1.05, 0.92, 0.9, membrane, c.Glow, NEON))
		end
		if c.Room() >= 1 then
			snout(c, false)
		end
		if c.Room() >= 2 then
			tail(c, 1, c.Look.Trim, c.Glow, NEON)
		end
		return top
	end

	A.DragonEgg = function(c)
		-- Ember Hatchling: the top of its egg still on its head
		dragonBody(c)
		part(c.Model, "Shell", c.At(0, 2.66, 0.02), c.V(1.5, 1.5, 1.5), SHELL, M.SmoothPlastic, BALL)
		for i, x in { -0.42, 0, 0.42 } do
			if c.Room() >= 1 then
				part(
					c.Model,
					"ShellPoint" .. i,
					c.At(x, 2.56, -0.69) * CFrame.Angles(0, 0, PI / 4),
					c.V(0.32, 0.32, 0.06),
					SHELL,
					M.SmoothPlastic
				)
			end
		end
		-- stubby wings (no bones) and a little tail
		if c.Room() >= 2 then
			wings(c, 0.85, 0.75, 0.85, c.Look.Glow:Lerp(c.Look.Trim, 0.35))
		end
		if c.Room() >= 2 then
			tail(c, 0.8, c.Look.Trim, c.Glow, NEON)
		end
		-- orange spots on the shell
		for i, k in { { -0.32, 3.0, -0.52, 0.32 }, { 0.36, 3.2, -0.32, 0.26 } } do
			if c.Room() >= 1 then
				part(c.Model, "Spot" .. i, c.At(k[1], k[2], k[3]), c.V(k[4], k[4], k[4]), SPOT, M.SmoothPlastic, BALL)
			end
		end
		return 2.66 + 0.76
	end

	A.DragonHelm = function(c)
		-- Dragonscale Knight: a helm shaped like a dragon's head, a dragon shield
		dragonBody(c)
		local trim = c.Look.Trim
		part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), trim, M.Metal)
		part(c.Model, "Slit", c.At(0, 2.02, -0.71), c.V(1.12, 0.22, 0.04), rgb(20, 14, 18))
		-- the dragon's upper jaw jutting out over the eyes
		part(c.Model, "Jaw", c.At(0, 2.32, -0.88) * CFrame.Angles(-0.12, 0, 0), c.V(1.08, 0.3, 0.46), darker(trim, 0.2), M.Metal)
		local top = horns(c, 0.72, 2.4, 0.1, 1.3, GOLD, IVORY, M.Slate)
		-- the shield on the left arm, turned half to the front: a heater shield with a dragon's eye
		if c.Room() >= 3 then
			local shield = c.At(-1.02, 0.98, -0.28) * CFrame.Angles(0, PI / 4, 0)
			part(c.Model, "Shield", shield, c.V(0.82, 0.62, 0.12), darker(trim, 0.1), M.Metal)
			part(
				c.Model,
				"ShieldPoint",
				shield * CFrame.new(0, -0.3 * c.S, 0) * CFrame.Angles(0, 0, PI / 4),
				c.V(0.58, 0.58, 0.11),
				darker(trim, 0.1),
				M.Metal
			)
			part(
				c.Model,
				"ShieldEye",
				shield * CFrame.new(0, -0.08 * c.S, -0.07 * c.S) * CFrame.Angles(0, 0, PI / 4),
				c.V(0.26, 0.26, 0.04),
				c.Glow,
				NEON
			)
		end
		-- a glowing crest of scales over the top
		for i, z in { -0.25, 0.25 } do
			if c.Room() >= 1 then
				part(c.Model, "Crest" .. i, c.At(0, 2.86, z) * CFrame.Angles(PI / 4, 0, 0), c.V(0.1, 0.36, 0.36), c.Glow, NEON)
			end
		end
		return top
	end

	A.DragonWings = function(c)
		dragonBody(c)
		local premium = c.Look.Rarity == "Legendary" or c.Look.Rarity == "Mythic"
		local arm, finger, angle = if premium then 1.5 else 1.3, if premium then 1.35 else 1.12, 0.9
		local membrane = c.Look.Trim:Lerp(c.Look.Glow, if premium then 0.34 else 0.5)
		local top = wings(c, arm, finger, angle, membrane, c.Glow, NEON)
		if premium then
			-- Magma Wyvern: lava hands, a tail, little horns
			for _, name in { "Fist1", "Fist2" } do
				recolor(c, name, c.Look.Trim:Lerp(c.Look.Glow, 0.7), NEON)
			end
			lobes(c, arm, finger, angle, membrane)
			if c.Room() >= 2 then
				tail(c, 1.15, darker(c.Look.Body, 0.1), c.Glow, NEON)
			end
			for i, side in { -1, 1 } do
				if c.Room() >= 1 then
					part(
						c.Model,
						"Horn" .. i,
						c.At(side * 0.62, 2.82, 0.12) * CFrame.Angles(0.45, 0, side * -0.55),
						c.V(0.22, 0.6, 0.22),
						IVORY,
						M.Slate
					)
				end
			end
			return math.max(top, 3.3)
		end
		-- Flamewing: two-pointed fiery wings, horns, a snout
		lobes(c, arm, finger, angle, membrane)
		if c.Room() >= 4 then
			top = math.max(top, horns(c, 0.66, 2.5, 0.1, 0.85, IVORY, IVORY, M.Slate))
		end
		if c.Room() >= 1 then
			snout(c, true)
		end
		return top
	end

	A.DragonCrown = function(c)
		-- the Dragon King: a crown of flames, huge gold-boned wings
		dragonBody(c)
		upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.3 * c.S, 1.24 * c.S, GOLD, M.Foil)
		local arm, finger, angle = 1.7, 1.5, 0.88
		local membrane = rgb(160, 28, 36)
		local top = wings(c, arm, finger, angle, membrane, GOLD, M.Foil)
		-- the flames: the middle one tallest, hot yellow; the sides orange
		local colors = { FLAME, FLAME_HOT, FLAME }
		for i, k in { { -0.4, -0.22, 0.48, 0.3 }, { 0, -0.48, 0.66, 0 }, { 0.4, -0.22, 0.48, -0.3 } } do
			if c.Room() >= 1 then
				local height = k[3]
				part(
					c.Model,
					"Flame" .. i,
					c.At(k[1], 3.0, k[2]) * CFrame.Angles(0, 0, k[4]) * CFrame.Angles(0, 0, PI / 4),
					c.V(height, height, 0.1),
					colors[i],
					NEON
				)
				top = math.max(top, 3.0 + height * 0.71)
			end
		end
		lobes(c, arm, finger, angle, membrane)
		return math.max(top, 3.4)
	end

	return A
end

return GolemGearLimited
