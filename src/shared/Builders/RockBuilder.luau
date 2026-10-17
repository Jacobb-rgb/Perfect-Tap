--[[
	Rocks of the mine floors (MineFloors): every floor has its own boulder
	colors and its own crystals, and the crystals get bigger, clearer and
	brighter the deeper the floor (matte -> glowing tips -> glassy shells with
	a glowing core). The ores inside stay secret: one small glint per ore in
	its glow color, the same size for every rarity.

	  RockBuilder.build(floor, kind, oreIds, base, seed) -> Model "Rock"
	    floor   MineFloors index or id
	    kind    Small (3 ores) | Big (4) | Crystal (3 better ores, mostly crystal)
	            | Golden | Geode | Artifact | Giant (the server-wide crystal)
	    base    CFrame on the ground (bottom center)

	  Rock (Model, PrimaryPart = Rock1)
	    Rock1           the main boulder (cracks are drawn on it)
	    Bulk, Cap, Skirt/Keel, Rock2..RockN (side and top lumps)
	    CrystalGroup    one floor crystal (Crystal body, CrystalTip x2, CrystalCore)
	    Glint           one per ore
	    floor extras    Strata, Lava, Moss, Mushroom, Trim, Column, Debris, Rune, Relic ...
	Attributes: Floor, Kind, Zone, OreCount, Stage = 0 (no OreIds: content is secret).
	RockBuilder.applyStage(model, stage, seed) cracks it open one ore at a time.
]]

local Geo = require(script.Parent.Geo)
local ItemBuilder = require(script.Parent.ItemBuilder)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local MineFloors = require(script.Parent.Parent.Config.MineFloors)

local RockBuilder = {}

-- Part budgets per kind (rocks stream in per floor; ~26 rocks per floor).
RockBuilder.Budget = {
	Small = 28,
	Big = 32,
	Crystal = 34,
	Golden = 32,
	Geode = 30,
	Artifact = 30,
	Giant = 80,
} :: { [string]: number }

-- Colors every floor shares for the special rocks, so players learn them once.
RockBuilder.Special = {
	Gold = Color3.fromRGB(255, 196, 52),
	GoldDeep = Color3.fromRGB(196, 132, 30),
	Geode = Color3.fromRGB(176, 104, 255),
	GeodeShell = Color3.fromRGB(74, 62, 84),
	Rune = Color3.fromRGB(90, 255, 214),
}

type Look = "Matte" | "Tipped" | "Shell" | "Glow"

type Ctx = {
	model: Model,
	rng: Rng.Rng,
	floor: MineFloors.Floor,
	pal: MineFloors.Palette,
	base: CFrame,
	kind: string,
	big: boolean,
	mainCf: CFrame,
	mainSize: Vector3,
	start: number,
}

local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local SMALL = { CanTouch = false, CanQuery = true, CanCollide = false, CastShadow = false }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local WHITE = Color3.new(1, 1, 1)
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FOIL = Enum.Material.Foil
local VERTEX_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, math.pi / 4, 0)

-- Crystal look of normal rocks per floor (matte -> glowing tips -> glassy shells);
-- Crystal rocks and specials use the next one up.
local function lookFor(floor: MineFloors.Floor, upgrade: boolean): Look
	local index = floor.Index + (if upgrade then 1 else 0)
	if index <= 1 then
		return "Matte"
	elseif index == 2 then
		return "Tipped"
	end
	return "Shell"
end

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

-- Leans a crystal standing at `foot` outward toward yaw `a` by `lean` radians.
local function lean(foot: CFrame, a: number, amount: number): CFrame
	return foot * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -amount) * CFrame.Angles(0, a, 0)
end

--[[
	One crystal: a diamond-section prism with a ridge tip (the lobby crystal
	build) in a "CrystalGroup" model. `base` = bottom center, up = growth
	direction. Returns the body.
	Matte 3 parts, Tipped 3, Glow 3, Shell 4 (see-through body + glowing core).
]]
local function crystal(parent: Model, base: CFrame, height: number, width: number, color: Color3, look: Look): BasePart
	-- each crystal is its own group so a crack stage can break a whole crystal off
	local model = Instance.new("Model")
	model.Name = "CrystalGroup"
	model.Parent = parent
	local body = base * CFrame.Angles(0, math.pi / 4, 0)
	local bodyH = height * 0.76
	local tipH = height - bodyH
	local bodyColor, bodyMat, transparency = color, SMOOTH, 0
	local tipA, tipB, tipMat = color:Lerp(WHITE, 0.35), color:Lerp(WHITE, 0.15), SMOOTH
	if look == "Tipped" then
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.2)), glow(color), NEON
	elseif look == "Glow" then
		bodyColor, bodyMat = glow(color), NEON
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.3)), glow(color), NEON
	elseif look == "Shell" then
		bodyColor, transparency = color:Lerp(WHITE, 0.25), 0.32
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.3)), glow(color), NEON
	end
	local props = { CanTouch = false, CanQuery = true, CanCollide = false, CastShadow = look ~= "Glow", Transparency = transparency }
	local main = Geo.block(model, body * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), bodyColor, bodyMat, props)
	main.Name = "Crystal"
	if look == "Shell" then
		local core = Geo.block(model, body * CFrame.new(0, bodyH * 0.48, 0), Vector3.new(width * 0.42, bodyH * 0.86, width * 0.42), glow(color), NEON, GLOW)
		core.Name = "CrystalCore"
	end
	local tipAt = body * CFrame.new(0, bodyH + tipH / 2, 0)
	local a = Geo.wedge(model, tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tipA, tipMat, GLOW)
	a.Name = "CrystalTip"
	local b = Geo.wedge(model, tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(width, tipH, width / 2), tipB, tipMat, GLOW)
	b.Name = "CrystalTip"
	return main
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

local function sparkle(part: BasePart, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = rate
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = part
end

-- A point on the side of the main boulder toward yaw `a` (local to mainCf), at height y.
local function sidePoint(c: Ctx, a: number, y: number, inset: number?): CFrame
	local half = c.mainSize / 2
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local t = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Z / math.max(math.abs(dir.Z), 1e-3))
	t -= inset or 0
	return c.mainCf * CFrame.new(dir.X * t, y, dir.Z * t)
end

-- A point on top of the main boulder (local offsets as fractions of its size).
local function topPoint(c: Ctx, fx: number, fz: number, sink: number?): CFrame
	local s = c.mainSize
	return c.mainCf * CFrame.new(fx * s.X, s.Y / 2 + 0.55 - (sink or 0.2), fz * s.Z)
end

---------------------------------------------------------------- the boulder

type BoulderOpts = { Float: number?, Carved: boolean?, Lumps: number?, Scale: number?, Flat: number? }

local function boulder(c: Ctx, opts: BoulderOpts): BasePart
	local rng, pal, base = c.rng, c.pal, c.base
	local scale = opts.Scale or (if c.big then 1.3 else 1)
	local float = opts.Float or 0
	local tilt = if opts.Carved then 0.02 else 0.1
	local size = Vector3.new(rng:range(4.4, 4.9), rng:range(3.3, 3.7) * (opts.Flat or 1), rng:range(4.0, 4.5)) * scale
	c.mainSize = size
	c.mainCf = base * CFrame.new(0, size.Y * 0.42 + float, 0) * CFrame.Angles(rng:range(-tilt, tilt), 0, rng:range(-tilt, tilt))
	local rock1 = Geo.block(c.model, c.mainCf, size, Geo.vary(pal.Mid, rng, 0.03), SMOOTH, SOLID)
	rock1.Name = "Rock1"
	-- the boulder again, turned 45 degrees: facets (carved floors keep a cut block instead)
	local bulkSize = Vector3.new(size.X * 0.86, size.Y * 0.92, size.Z * 0.9)
	local bulkYaw = if opts.Carved then math.pi / 4 else math.pi / 4 + rng:range(-0.15, 0.15)
	local bulk = Geo.block(
		c.model,
		base * CFrame.new(0, size.Y * 0.4 + float, 0) * CFrame.Angles(rng:range(-tilt, tilt), bulkYaw, rng:range(-tilt, tilt)),
		if opts.Carved then Vector3.new(size.X * 0.8, size.Y * 0.84, size.Z * 0.8) else bulkSize,
		Geo.vary(pal.Mid:Lerp(pal.Dark, 0.3), rng, 0.03),
		SMOOTH,
		SOLID
	)
	bulk.Name = "Bulk"
	local cap = Geo.block(
		c.model,
		c.mainCf * CFrame.new(rng:range(-0.2, 0.2), size.Y / 2 + 0.1, rng:range(-0.2, 0.2)) * CFrame.Angles(0, (if opts.Carved then 0 else math.pi / 4) + rng:range(-0.25, 0.25), 0),
		Vector3.new(size.X * 0.66, 0.6, size.Z * 0.62),
		Geo.vary(pal.Light, rng, 0.03),
		SMOOTH,
		SOLID
	)
	cap.Name = "Cap"
	if float > 0 then
		-- a floating rock: a pointed keel underneath instead of a foot
		local k = math.min(size.X, size.Z) * 0.62
		local keel = Geo.block(c.model, base * CFrame.new(0, float + 0.3, 0) * CFrame.Angles(0, c.start, 0) * VERTEX_UP, Vector3.new(k, k, k), Geo.vary(pal.Dark, rng, 0.03), SMOOTH, SOLID)
		keel.Name = "Keel"
	else
		local skirt = Geo.block(c.model, base * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.pi / 8 + rng:range(-0.2, 0.2), 0), Vector3.new(size.X * 1.06, 0.8, size.Z * 1.04), Geo.vary(pal.Dark, rng, 0.03), SMOOTH, SOLID)
		skirt.Name = "Skirt"
	end
	local lumps = opts.Lumps or (if c.big then 3 else 2)
	for i = 1, lumps do
		local s: Vector3
		local cf: CFrame
		if i <= 2 then
			local a = c.start + (i - 1) * 2.4 + rng:range(-0.3, 0.3)
			local dist = size.X * rng:range(0.42, 0.5)
			s = size * rng:range(0.42, 0.52)
			cf = base * CFrame.new(math.cos(a) * dist, s.Y * 0.42 + float * 0.6, math.sin(a) * dist) * Geo.randomTilt(rng, if opts.Carved then 0.08 else 0.3)
		else
			local a = c.start + 1.2 + i
			s = size * rng:range(0.36, 0.44)
			cf = c.mainCf * CFrame.new(math.cos(a) * size.X * 0.18, size.Y * 0.5 + s.Y * 0.3, math.sin(a) * size.Z * 0.18) * Geo.randomTilt(rng, 0.35)
		end
		local lump = Geo.block(c.model, cf, s, Geo.vary(if i % 2 == 0 then pal.Light else pal.Mid, rng, 0.05), SMOOTH, SOLID)
		lump.Name = "Rock" .. (i + 1)
	end
	return rock1
end

-- One glint per ore on the boulder's sides (tiny crystals in the ore's glow color).
local function glints(c: Ctx, oreIds: { string })
	local count = #oreIds
	for i, oreId in oreIds do
		local ore = OreData.ById[oreId]
		local color = glow(if ore then ore.Glow else c.pal.Accent)
		local a = c.start + 0.6 + (i - 1) * (math.pi * 2 / math.max(count, 1)) + c.rng:range(-0.2, 0.2)
		local y = c.rng:range(-0.15, 0.25) * c.mainSize.Y
		local g = Geo.block(c.model, sidePoint(c, a, y) * CFrame.Angles(c.rng:range(-0.4, 0.4), a, c.rng:range(-0.4, 0.4)) * VERTEX_UP, Vector3.new(0.55, 0.55, 0.55), color, NEON, GLOW)
		g.Name = "Glint"
	end
end

-- `count` floor crystals growing out of the top edge of the boulder, leaning outward.
local function topCrystals(c: Ctx, count: number, minH: number, maxH: number, look: Look, around: number?, colors: { Color3 }?): BasePart?
	local rng = c.rng
	local biggest: BasePart? = nil
	local spread = around or (math.pi * 2)
	local center = c.start + 2.2
	for i = 1, count do
		local a = center + (if count > 1 then (i - 1) / (count - 1) - 0.5 else 0) * spread + rng:range(-0.2, 0.2)
		local r = rng:range(0.18, 0.3)
		local foot = topPoint(c, math.cos(a) * r, math.sin(a) * r, 0.45)
		local h = rng:range(minH, maxH) * (if c.big then 1.2 else 1)
		local color = if colors then colors[(i - 1) % #colors + 1] elseif i % 2 == 1 then c.pal.Crystal else c.pal.Crystal2
		local body = crystal(c.model, lean(foot, a, rng:range(0.25, 0.55)), h, h * 0.3, color, look)
		if not biggest or h > (biggest :: BasePart).Size.Y then
			biggest = body
		end
	end
	return biggest
end

---------------------------------------------------------------- floor looks

-- Floor 1, Greystone Quarry: sandy boulder with a darker stratum, small matte crystals.
local function quarry(c: Ctx)
	local band = Geo.block(c.model, c.mainCf * CFrame.new(0, -c.mainSize.Y * 0.14, 0), Vector3.new(c.mainSize.X + 0.06, 0.42, c.mainSize.Z + 0.06), c.pal.Dark:Lerp(c.pal.Mid, 0.45), SMOOTH, GLOW)
	band.Name = "Strata"
	topCrystals(c, if c.big then 3 else 2, 1.3, 1.9, "Matte", 1.4)
end

-- Floor 2, Ember Caves: red basalt with glowing lava cracks and fire-tipped crystals.
local function ember(c: Ctx)
	for i = 1, 2 do
		local a = c.start + 0.9 + i * 2.6
		local cf = sidePoint(c, a, c.rng:range(-0.2, 0.15) * c.mainSize.Y, -0.02) * CFrame.Angles(0, -a + math.pi / 2, c.rng:range(-0.9, 0.9))
		local lava = Geo.block(c.model, cf, Vector3.new(c.rng:range(1.8, 2.6), 0.24, 0.14), glow(c.pal.Accent), NEON, GLOW)
		lava.Name = "Lava"
	end
	topCrystals(c, if c.big then 4 else 3, 1.6, 2.5, "Tipped", 2.2)
end

-- Floor 3, Deep Hollow (crystal lagoon): wet blue stone, moss, a glowing mushroom, glassy crystals.
local function lagoon(c: Ctx)
	local moss = Geo.block(c.model, topPoint(c, 0.04, -0.04, 0.12) * CFrame.Angles(0, c.start, 0), Vector3.new(c.mainSize.X * 0.5, 0.36, c.mainSize.Z * 0.46), c.pal.Accent, SMOOTH, SMALL)
	moss.Name = "Moss"
	local drip = Geo.block(c.model, sidePoint(c, c.start + 2.2, c.mainSize.Y * 0.32, -0.08) * CFrame.Angles(0, -(c.start + 2.2), 0), Vector3.new(0.3, 1.1, 1.3), c.pal.Accent:Lerp(c.pal.Dark, 0.2), SMOOTH, GLOW)
	drip.Name = "Moss"
	topCrystals(c, if c.big then 4 else 3, 1.9, 2.9, "Shell", 1.8)
	-- glowing mushroom at the foot
	local a = c.start + 4.4
	local foot = c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.62, 0, math.sin(a) * c.mainSize.Z * 0.62)
	local stem = Geo.block(c.model, foot * CFrame.new(0, 0.45, 0), Vector3.new(0.28, 0.9, 0.28), Color3.fromRGB(214, 236, 230), SMOOTH, GLOW)
	stem.Name = "Mushroom"
	local cap = Geo.block(c.model, foot * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.32, 1.1, 1.1), glow(Color3.fromRGB(110, 255, 210)), NEON, { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Shape = Enum.PartType.Cylinder })
	cap.Name = "Mushroom"
end

-- Floor 4, Sunken Palace: carved stone with a gold trim, a fallen column piece, gold and lavender crystals.
local function palace(c: Ctx)
	local trim = Geo.block(c.model, c.mainCf * CFrame.new(0, -c.mainSize.Y * 0.18, 0), Vector3.new(c.mainSize.X + 0.1, 0.3, c.mainSize.Z + 0.1), c.pal.Accent, FOIL, GLOW)
	trim.Name = "Trim"
	local a = c.start + 3.8
	local foot = c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.66, 0.62, math.sin(a) * c.mainSize.Z * 0.66)
	local column = Geo.block(c.model, foot * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(0, 0, 0.18), Vector3.new(2.6, 1.24, 1.24), c.pal.Light:Lerp(WHITE, 0.15), SMOOTH, { CanTouch = false, CanQuery = true, CanCollide = true, Shape = Enum.PartType.Cylinder })
	column.Name = "Column"
	local ring = Geo.block(c.model, column.CFrame * CFrame.new(0.9, 0, 0), Vector3.new(0.26, 1.42, 1.42), c.pal.Accent, FOIL, { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Shape = Enum.PartType.Cylinder })
	ring.Name = "Trim"
	topCrystals(c, if c.big then 4 else 3, 2.1, 3.2, "Shell", 2.0)
end

-- Floor 5, Heartstone Core: a dark floating rock with orbiting debris and glowing pink/aqua crystals.
local function core(c: Ctx)
	local rng = c.rng
	for i = 1, 2 do
		local a = c.start + i * 2.9
		local s = rng:range(0.7, 1.0)
		local bit = Geo.block(c.model, c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.78, c.mainSize.Y * rng:range(0.5, 0.9) + 1, math.sin(a) * c.mainSize.Z * 0.78) * Geo.randomTilt(rng, 0.6), Vector3.new(s, s * 0.8, s), Geo.vary(c.pal.Light, rng, 0.05), SMOOTH, SMALL)
		bit.Name = "Debris"
	end
	local mote = Geo.block(c.model, c.base * CFrame.new(math.cos(c.start) * c.mainSize.X * 0.7, c.mainSize.Y * 1.25 + 1, math.sin(c.start) * c.mainSize.Z * 0.7) * VERTEX_UP, Vector3.new(0.4, 0.4, 0.4), glow(c.pal.Accent), NEON, GLOW)
	mote.Name = "Debris"
	local vein = Geo.block(c.model, sidePoint(c, c.start + 1.5, 0, -0.02) * CFrame.Angles(0, -(c.start + 1.5) + math.pi / 2, 0.7), Vector3.new(2.4, 0.24, 0.14), glow(c.pal.Crystal), NEON, GLOW)
	vein.Name = "Lava"
	local biggest = topCrystals(c, 2, 2.6, 3.4, "Shell", 1.5)
	topCrystals(c, if c.big then 3 else 2, 1.4, 1.9, "Glow", 3.6)
	if biggest then
		light(biggest, glow(c.pal.Crystal), 12, 1.1)
	end
end

local FLOOR_LOOK: { (Ctx) -> () } = { quarry, ember, lagoon, palace, core }

---------------------------------------------------------------- kinds

local function normalRock(c: Ctx, oreIds: { string })
	local index = c.floor.Index
	boulder(c, {
		Float = if index == 5 then 1.1 else 0,
		Carved = index == 4,
		Lumps = if index == 4 then (if c.big then 2 else 1) elseif index == 5 then 1 else nil,
	})
	FLOOR_LOOK[index](c)
	glints(c, oreIds)
end

-- Crystal rock: a small boulder carrying a big crystal cluster in the floor's colors.
local function crystalRock(c: Ctx)
	local index = c.floor.Index
	local look: Look = lookFor(c.floor, true)
	boulder(c, { Scale = 0.85, Flat = 0.7, Lumps = 1, Float = if index == 5 then 0.8 else 0, Carved = index == 4 })
	local rng = c.rng
	local mainH = 4.6 + index * 0.45
	local foot = topPoint(c, 0, 0, 0.5)
	local main = crystal(c.model, foot * CFrame.Angles(rng:range(-0.1, 0.1), 0, rng:range(-0.1, 0.1)), mainH, mainH * 0.25, c.pal.Crystal, look)
	local sides = if index >= 3 then 5 else 4
	for i = 1, sides do
		local a = c.start + (i / sides) * math.pi * 2 + rng:range(-0.25, 0.25)
		local h = mainH * rng:range(0.42, 0.7)
		local f = topPoint(c, math.cos(a) * 0.2, math.sin(a) * 0.2, 0.5)
		crystal(c.model, lean(f, a, rng:range(0.35, 0.62)), h, h * 0.28, if i % 2 == 0 then c.pal.Crystal else c.pal.Crystal2, look)
	end
	light(main, glow(c.pal.Crystal), 14 + index, 1 + index * 0.12)
	sparkle(main, glow(c.pal.Crystal:Lerp(WHITE, 0.3)), 2 + index * 0.5, 0.6)
end

-- Golden rock: the floor boulder laced with gold veins and nuggets, gold crystals on top.
local function goldenRock(c: Ctx)
	local S = RockBuilder.Special
	boulder(c, { Float = if c.floor.Index == 5 then 1.1 else 0, Carved = c.floor.Index == 4 })
	local rng = c.rng
	-- the same warm gold body on every floor, so it reads as "golden" from far away
	for _, part in c.model:GetChildren() do
		if part:IsA("BasePart") then
			local tone = if part.Name == "Cap" then S.Gold:Lerp(WHITE, 0.2)
				elseif part.Name == "Skirt" or part.Name == "Keel" then S.GoldDeep:Lerp(Color3.new(0, 0, 0), 0.25)
				elseif part.Name == "Bulk" then S.GoldDeep
				else S.Gold:Lerp(S.GoldDeep, 0.45)
			part.Color = Geo.vary(tone, rng, 0.04)
		end
	end
	for i = 1, 3 do
		local a = c.start + i * 2.1
		local cf = sidePoint(c, a, rng:range(-0.25, 0.2) * c.mainSize.Y, -0.02) * CFrame.Angles(0, -a + math.pi / 2, rng:range(-0.9, 0.9))
		local vein = Geo.block(c.model, cf, Vector3.new(rng:range(2.2, 3.0), 0.26, 0.14), glow(S.Gold), NEON, GLOW)
		vein.Name = "GoldVein"
	end
	for i = 1, 3 do
		local a = c.start + 1 + i * 2.1
		local s = rng:range(0.7, 0.95)
		local n = Geo.block(c.model, sidePoint(c, a, rng:range(-0.1, 0.3) * c.mainSize.Y) * Geo.randomTilt(rng, 0.5), Vector3.new(s, s * 0.8, s), S.Gold, FOIL, SMALL)
		n.Name = "Nugget"
	end
	local biggest = topCrystals(c, 3, 1.8, 2.7, "Tipped", 1.8, { S.Gold, S.Gold:Lerp(WHITE, 0.35), S.GoldDeep })
	if biggest then
		light(biggest, glow(S.Gold), 13, 1.1)
		sparkle(biggest, glow(S.Gold:Lerp(WHITE, 0.3)), 4, 0.55)
	end
end

-- Geode: a round rock split in two, its glowing violet inside full of crystals
-- (readable from every side: the split runs across the whole top).
local function geodeRock(c: Ctx)
	local S = RockBuilder.Special
	local rng = c.rng
	local float = if c.floor.Index == 5 then 1.1 else 0
	local shell = S.GeodeShell:Lerp(c.pal.Mid, 0.35)
	local s = rng:range(3.8, 4.2)
	local gap = 0.9
	c.mainSize = Vector3.new(s, s * 0.82, s)
	c.mainCf = c.base * CFrame.new(0, s * 0.36 + float, 0)
	-- two halves leaning apart, each a block plus a turned block for a rounder outline
	for side = -1, 1, 2 do
		local half = c.mainCf * CFrame.new(side * (s / 4 + gap / 2), 0, 0) * CFrame.Angles(0, 0, -side * 0.16)
		local body = Geo.block(c.model, half, Vector3.new(s / 2, s * 0.82, s * 0.92), Geo.vary(shell, rng, 0.03), SMOOTH, SOLID)
		body.Name = if side < 0 then "Rock1" else "Rock2"
		local round = Geo.block(c.model, half * CFrame.new(side * 0.12, -0.05, 0) * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(s * 0.44, s * 0.74, s * 0.74), Geo.vary(shell:Lerp(c.pal.Dark, 0.25), rng, 0.03), SMOOTH, SOLID)
		round.Name = "Bulk"
		local rim = Geo.block(c.model, half * CFrame.new(-side * (s / 4 - 0.08), 0.1, 0), Vector3.new(0.18, s * 0.6, s * 0.7), S.Geode:Lerp(WHITE, 0.15), SMOOTH, GLOW)
		rim.Name = "Hollow"
	end
	if float == 0 then
		local skirt = Geo.block(c.model, c.base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0.3, 0), Vector3.new(s * 1.15, 0.6, s * 1.05), Geo.vary(c.pal.Dark, rng, 0.03), SMOOTH, SOLID)
		skirt.Name = "Skirt"
	end
	-- the glowing inside and crystals growing up and out of the split
	local core = Geo.block(c.model, c.mainCf * CFrame.new(0, -0.1, 0), Vector3.new(gap + 0.5, s * 0.66, s * 0.76), glow(S.Geode), NEON, GLOW)
	core.Name = "Hollow"
	local lit: BasePart? = nil
	for i = 1, 6 do
		local z = (i - 3.5) / 3 * s * 0.32
		local side = if i % 2 == 0 then 1 else -1
		local foot = c.mainCf * CFrame.new(side * 0.18, s * 0.2, z)
		local h = rng:range(1.3, 2.1)
		local body = crystal(c.model, foot * CFrame.Angles(rng:range(-0.25, 0.25), 0, -side * rng:range(0.15, 0.4)), h, h * 0.3, if i % 3 == 0 then S.Geode:Lerp(WHITE, 0.45) else S.Geode, "Glow")
		lit = lit or body
	end
	if lit then
		light(lit, glow(S.Geode), 12, 1.3)
		sparkle(lit, glow(S.Geode:Lerp(WHITE, 0.3)), 3, 0.5)
	end
end

-- Artifact rock: the floor boulder with a glowing rune stone and a royal relic sticking out.
local function artifactRock(c: Ctx, oreIds: { string })
	local S = RockBuilder.Special
	boulder(c, { Float = if c.floor.Index == 5 then 1.1 else 0, Carved = c.floor.Index == 4, Lumps = 1 })
	local a = c.start + 2.4
	local face = sidePoint(c, a, c.mainSize.Y * 0.02, -0.08) * CFrame.Angles(0, -a, 0)
	local plate = Geo.block(c.model, face * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(0.3, 1.9, 1.9), c.pal.Light:Lerp(WHITE, 0.2), SMOOTH, GLOW)
	plate.Name = "Rune"
	local ring = Geo.block(c.model, face * CFrame.new(0.12, 0, 0), Vector3.new(0.12, 1.5, 1.5), glow(S.Rune), NEON, { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Shape = Enum.PartType.Cylinder })
	ring.Name = "Rune"
	local dot = Geo.block(c.model, face * CFrame.new(0.2, 0, 0), Vector3.new(0.12, 0.8, 0.8), plate.Color, SMOOTH, { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Shape = Enum.PartType.Cylinder })
	dot.Name = "Rune"
	local glyph = Geo.block(c.model, face * CFrame.new(0.26, 0, 0) * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(0.1, 0.42, 0.42), glow(S.Rune), NEON, GLOW)
	glyph.Name = "Rune"
	-- a crown half buried in the top
	local crownAt = topPoint(c, -0.12, 0.1, 0.35) * CFrame.Angles(0.35, c.start, 0.2)
	local band = Geo.block(c.model, crownAt * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.5, 1.3, 1.3), S.Gold, FOIL, { CanTouch = false, CanQuery = true, CanCollide = false, Shape = Enum.PartType.Cylinder })
	band.Name = "Relic"
	for i = 1, 3 do
		local ang = i * (math.pi * 2 / 3)
		local spike = Geo.block(c.model, crownAt * CFrame.new(math.cos(ang) * 0.5, 0.42, math.sin(ang) * 0.5) * CFrame.Angles(0, ang, 0) * VERTEX_UP, Vector3.new(0.36, 0.36, 0.36), S.Gold:Lerp(WHITE, 0.15), FOIL, GLOW)
		spike.Name = "Relic"
	end
	light(ring, glow(S.Rune), 10, 1)
	glints(c, oreIds)
end

-- Giant Crystal: the floor's server-wide event crystal on a rock base.
local function giantRock(c: Ctx)
	local rng, pal = c.rng, c.pal
	local index = c.floor.Index
	local look: Look = if index <= 1 then "Tipped" else "Shell"
	local size = Vector3.new(11, 3.4, 10)
	c.mainSize = size
	c.mainCf = c.base * CFrame.new(0, size.Y * 0.4, 0) * CFrame.Angles(0, c.start, 0)
	local rock1 = Geo.block(c.model, c.mainCf, size, Geo.vary(pal.Mid, rng, 0.03), SMOOTH, SOLID)
	rock1.Name = "Rock1"
	local bulk = Geo.block(c.model, c.mainCf * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(size.X * 0.92, size.Y * 0.9, size.Z * 0.92), Geo.vary(pal.Dark, rng, 0.03), SMOOTH, SOLID)
	bulk.Name = "Bulk"
	local cap = Geo.block(c.model, c.mainCf * CFrame.new(0, size.Y / 2 + 0.2, 0) * CFrame.Angles(0, 0.4, 0), Vector3.new(size.X * 0.6, 0.8, size.Z * 0.6), Geo.vary(pal.Light, rng, 0.03), SMOOTH, SOLID)
	cap.Name = "Cap"
	local top = c.mainCf * CFrame.new(0, size.Y / 2 + 0.4, 0)
	local mainH = 15 + index
	local main = crystal(c.model, top, mainH, mainH * 0.21, pal.Crystal, look)
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + rng:range(-0.2, 0.2)
		local h = mainH * rng:range(0.45, 0.68)
		local foot = top * CFrame.new(math.cos(a) * 1.8, 0, math.sin(a) * 1.8)
		crystal(c.model, lean(foot, a, rng:range(0.28, 0.45)), h, h * 0.24, if i % 2 == 0 then pal.Crystal else pal.Crystal2, look)
	end
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + 0.5 + rng:range(-0.2, 0.2)
		local h = rng:range(2.4, 3.8)
		local foot = c.mainCf * CFrame.new(math.cos(a) * size.X * 0.42, size.Y / 2 - 0.2, math.sin(a) * size.Z * 0.42)
		crystal(c.model, lean(foot, a, rng:range(0.6, 0.85)), h, h * 0.3, if i % 2 == 0 then pal.Crystal2 else pal.Crystal, "Glow")
	end
	light(main, glow(pal.Crystal), 40, 2)
	sparkle(main, glow(pal.Crystal:Lerp(WHITE, 0.3)), 8, 1.2)
end

---------------------------------------------------------------- build

function RockBuilder.build(floorKey: number | string, kind: MineFloors.RockKind, oreIds: { string }, base: CFrame, seed: number | string): Model
	local floor = MineFloors.get(floorKey)
	local rng = Rng.new(seed)
	local model = Instance.new("Model")
	model.Name = "Rock"
	local c: Ctx = {
		model = model,
		rng = rng,
		floor = floor,
		pal = floor.Palette,
		base = base * CFrame.Angles(0, rng:range(0, math.pi * 2), 0),
		kind = kind,
		big = kind == "Big" or kind == "Golden",
		mainCf = base,
		mainSize = Vector3.new(1, 1, 1),
		start = rng:range(0, math.pi * 2),
	}
	if kind == "Crystal" then
		crystalRock(c)
	elseif kind == "Golden" then
		goldenRock(c)
	elseif kind == "Geode" then
		geodeRock(c)
	elseif kind == "Artifact" then
		artifactRock(c, oreIds)
	elseif kind == "Giant" then
		giantRock(c)
	else
		normalRock(c, oreIds)
	end
	local rock1 = model:FindFirstChild("Rock1")
	if rock1 and rock1:IsA("BasePart") then
		model.PrimaryPart = rock1
	end
	model:SetAttribute("Floor", floor.Index)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Zone", floor.ZoneId or floor.Id)
	model:SetAttribute("OreCount", #oreIds)
	model:SetAttribute("Stage", 0)
	if kind == "Artifact" then
		model:SetAttribute("Artifact", true)
	end
	return model
end

---------------------------------------------------------------- crack stages

local CRACK = Color3.fromRGB(26, 18, 18)

-- side faces cracked per stage (1 = +X, 2 = -X, 3 = +Z, 4 = -Z, 5 = top)
local STAGE_FACES = { { 1, 3 }, { 2, 4, 5 }, { 1, 2, 3, 4 } }

local function crackAt(model: Model, cf: CFrame, length: number, color: Color3, rng: Rng.Rng)
	local dark = Geo.block(model, cf, Vector3.new(0.16, length, 0.36), CRACK, SMOOTH, GLOW)
	dark.Name = "Crack"
	local line = Geo.block(model, cf * CFrame.new(0.04, 0, 0), Vector3.new(0.18, length * 0.82, 0.14), color, NEON, GLOW)
	line.Name = "Crack"
	-- a branch from the upper end: cracks look like lightning, not like tape
	local turn = rng:range(0.6, 1.0) * (if rng:chance(0.5) then 1 else -1)
	local branchLen = length * rng:range(0.4, 0.55)
	local branch = Geo.block(model, cf * CFrame.new(0.04, length * 0.38, 0) * CFrame.Angles(turn, 0, 0) * CFrame.new(0, branchLen / 2, 0), Vector3.new(0.18, branchLen, 0.12), color, NEON, GLOW)
	branch.Name = "Crack"
end

--[[
	Cracks a rock open one ore at a time: stage s (1 .. OreCount - 1) adds
	glowing cracks in the color of the s-th ore and breaks one lump and one
	crystal off (returned so the caller can fling and remove them); the last
	ore comes out when the rock shatters (client VFX). Works on every
	RockBuilder rock; deeper stages crack more faces.
]]
function RockBuilder.applyStage(model: Model, stage: number, seed: number | string): { BasePart }
	local broken: { BasePart } = {}
	local rock1 = model:FindFirstChild("Rock1")
	if not rock1 or not rock1:IsA("BasePart") then
		return broken
	end
	local rng = Rng.new(tostring(seed) .. ":" .. stage)
	local glintColors: { Color3 } = {}
	for _, child in model:GetChildren() do
		if child.Name == "Glint" and child:IsA("BasePart") then
			table.insert(glintColors, child.Color)
		end
	end
	local floorIndex = model:GetAttribute("Floor")
	local fallback = glow(MineFloors.get(if type(floorIndex) == "number" then floorIndex else 1).Palette.Accent)
	local color = glintColors[stage] or glintColors[1] or fallback
	local size = rock1.Size
	for _, face in STAGE_FACES[math.clamp(stage, 1, #STAGE_FACES)] do
		local length = rng:range(0.55, 0.8) * math.min(size.Y, if face <= 2 then size.Z else size.X) * 1.2
		local cf: CFrame
		if face == 5 then
			cf = rock1.CFrame * CFrame.new(rng:range(-0.2, 0.2) * size.X, size.Y / 2, rng:range(-0.2, 0.2) * size.Z) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(rng:range(0, math.pi), 0, 0)
		else
			local xAxis = face <= 2
			local sign = if face % 2 == 1 then 1 else -1
			local across = rng:range(-0.22, 0.22)
			local offset = if xAxis
				then Vector3.new(sign * size.X / 2, rng:range(-0.15, 0.15) * size.Y, across * size.Z)
				else Vector3.new(across * size.X, rng:range(-0.15, 0.15) * size.Y, sign * size.Z / 2)
			-- local X of the crack = the face normal (pointing out)
			local facing = if xAxis
				then (if sign > 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0))
				else CFrame.Angles(0, if sign > 0 then -math.pi / 2 else math.pi / 2, 0)
			cf = rock1.CFrame * CFrame.new(offset) * facing * CFrame.Angles(rng:range(-0.7, 0.7), 0, 0)
		end
		crackAt(model, cf, length, color, rng)
	end
	-- one lump and one crystal break off
	local lump = model:FindFirstChild("Rock" .. (stage + 1))
	if lump and lump:IsA("BasePart") then
		table.insert(broken, lump)
	end
	local groups: { Instance } = {}
	for _, child in model:GetChildren() do
		if child.Name == "CrystalGroup" then
			table.insert(groups, child)
		end
	end
	if #groups > 1 then
		-- the smallest crystal goes first; the biggest stays until the shatter
		table.sort(groups, function(a, b)
			local ba, bb = a:FindFirstChild("Crystal"), b:FindFirstChild("Crystal")
			local ha = if ba and ba:IsA("BasePart") then ba.Size.Y else 0
			local hb = if bb and bb:IsA("BasePart") then bb.Size.Y else 0
			return ha < hb
		end)
		-- hand the parts back loose (the caller flings and removes them) and drop the empty group
		for _, d in groups[1]:GetChildren() do
			if d:IsA("BasePart") then
				d.Parent = model
				table.insert(broken, d)
			end
		end
		groups[1]:Destroy()
	end
	model:SetAttribute("Stage", stage)
	return broken
end

return RockBuilder
