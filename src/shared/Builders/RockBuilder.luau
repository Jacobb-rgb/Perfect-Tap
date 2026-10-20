--[[
	Rocks of the mine floors (MineFloors), v2 after the owner's ore-shelf
	reference and The Forge's basalt rocks (2026-10-17): tall faceted stone
	shards with slanted or ridged tops, a glowing core peeking through the gaps
	between them (lava, ice, gold, heart glow per floor) and
	dense clusters of slim, two-tone faceted crystals with glowing tips and
	twinkles. The crystals get clearer and brighter the deeper the floor
	(matte -> glowing tips -> glassy shells with a glowing core -> pure glow;
	the Stormglass Rift's smoky indigo glass with lightning trapped inside).
	The ores inside stay secret: one small glint per ore in its glow color.
	Each floor's look is keyed by its MineFloors Id (LOOKS below), never by its
	Index, so a new floor can go in between and the others renumber safely.

	  RockBuilder.build(floor, kind, oreIds, base, seed) -> Model "Rock"
	    floor   MineFloors index or id (the look is chosen by the floor's Id)
	    kind    Small (3 ores) | Big (4) | Crystal (3 better ores, mostly crystal)
	            | Golden | Geode | Artifact | Giant (the server-wide crystal)
	    base    CFrame on the ground (bottom center)

	  Rock (Model, PrimaryPart = Rock1)
	    Rock1           the central shard (Facet, Cap = its top)
	    Rock2..RockN    ring shards, each a Model (Body, Facet, Top); one breaks off per crack stage
	    Core            glowing heart between the shards (most floors)
	    Pebble, Skirt/Keel  rubble and the foot
	    CrystalGroup    one crystal (Crystal body, CrystalFacet, CrystalCore, CrystalTip...)
	    Glint           one per ore
	    Twinkle         little light stars at crystal tips
	    floor extras    Moss, Mushroom, Trim, Column, Debris, Rune, Relic, Nugget ...
	Attributes: Floor, Kind, Zone, OreCount, Stage = 0 (no OreIds: content is secret).
	RockBuilder.applyStage(model, stage, seed) cracks it open one ore at a time.
]]

local Geo = require(script.Parent.Geo)
local ItemBuilder = require(script.Parent.ItemBuilder)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local MineFloors = require(script.Parent.Parent.Config.MineFloors)

local RockBuilder = {}

-- Part budgets per kind (a floor streams in on its own; ~26 rocks per floor).
RockBuilder.Budget = {
	Small = 76,
	Big = 90,
	Crystal = 92,
	Golden = 68,
	Geode = 60,
	Artifact = 64,
	Giant = 170, -- one per floor
} :: { [string]: number }

-- Colors every floor shares for the special rocks, so players learn them once.
RockBuilder.Special = {
	Gold = Color3.fromRGB(255, 196, 52),
	GoldDeep = Color3.fromRGB(196, 132, 30),
	Geode = Color3.fromRGB(176, 104, 255),
	GeodeShell = Color3.fromRGB(74, 62, 84),
	Rune = Color3.fromRGB(90, 255, 214),
}

type Look = "Matte" | "Tipped" | "Shell" | "Glow" | "Storm"

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
	foot: CFrame, -- the rock's foot (lifted for floating rocks)
	ring: number, -- radius of the ring of shards
	top: number, -- half width of the central shard's top
	gaps: { number }, -- yaw of the gaps between ring shards
	look: FloorLook,
}

--[[
	How a floor's rocks look (LOOKS, keyed by the floor's MineFloors Id):
	  Build        the floor's Small / Big rock
	  Tier         how deep it is for sizes and glow (the floor's index when its
	               rocks were made; the deeper, the taller the crystals and the
	               brighter their lights; fractions are fine)
	  CrystalLook  crystal look of its Crystal rocks (one step up from Build's)
	  GiantLook    crystal look of its Giant Crystal
	  Core         the palette color glowing between the shards of its Crystal
	               rocks and Giant Crystal (nil: the floor's crystal color)
	  Float        floating rocks (the void)
	  Carved       upright pillar shards with flat gold-trimmed tops (the palace)
]]
type FloorLook = {
	Build: (Ctx, { string }) -> (),
	Tier: number,
	CrystalLook: Look,
	GiantLook: Look,
	Core: ("Accent" | "Crystal")?,
	Float: boolean?,
	Carved: boolean?,
}

local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local SMALL = { CanTouch = false, CanQuery = true, CanCollide = false, CastShadow = false }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FOIL = Enum.Material.Foil
local VERTEX_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, math.pi / 4, 0)
-- the smoky indigo glass of the Stormglass Rift's crystals (look "Storm")
local STORM_GLASS = Color3.fromRGB(84, 98, 184)

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

-- Leans a frame standing at `foot` outward toward yaw `a` by `amount` radians.
local function tilt(foot: CFrame, a: number, amount: number): CFrame
	return foot * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -amount) * CFrame.Angles(0, a, 0)
end

local function randomTilt(rng: Rng.Rng, amount: number): CFrame
	return CFrame.Angles(rng:range(-amount, amount), rng:range(0, math.pi * 2), rng:range(-amount, amount))
end

---------------------------------------------------------------- crystals

--[[
	One crystal in its own "CrystalGroup" (a crack stage can break it off):
	a diamond-section body with a darker octagon facet block through it
	(alternating light and dark faces, like a cut gem), a ridge tip, and for
	`hero` crystals a true 4-sided pointed tip (exact triangles). Shell looks
	are see-through with a glowing core; Storm looks are smoky indigo glass
	(`color` only tints it) with a bright core in `color` and neon tips.
	`base` = bottom center, up = growth. Parts: small 3, big 4-5, hero 11-12.
]]
local function crystal(parent: Model, base: CFrame, height: number, width: number, color: Color3, look: Look, hero: boolean?): BasePart
	local group = Instance.new("Model")
	group.Name = "CrystalGroup"
	group.Parent = parent
	local bodyH = height * (if hero then 0.7 else 0.74)
	local tipH = height - bodyH
	local light, dark = color:Lerp(WHITE, 0.16), color:Lerp(BLACK, 0.3)
	local bodyColor, facetColor, bodyMat, transparency = light, dark, SMOOTH, 0
	local tipA, tipB, tipMat = color:Lerp(WHITE, 0.45), color:Lerp(WHITE, 0.2), SMOOTH
	if look == "Tipped" then
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.25)), glow(color), NEON
	elseif look == "Shell" then
		bodyColor, facetColor, transparency = color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.12), 0.3
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.35)), glow(color), NEON
	elseif look == "Glow" then
		bodyColor, facetColor, bodyMat = glow(color:Lerp(WHITE, 0.1)), glow(color:Lerp(BLACK, 0.25)), NEON
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.4)), glow(color:Lerp(WHITE, 0.15)), NEON
	elseif look == "Storm" then
		bodyColor, facetColor, transparency = STORM_GLASS:Lerp(color, 0.14), STORM_GLASS:Lerp(BLACK, 0.3), 0.38
		tipA, tipB, tipMat = glow(color:Lerp(WHITE, 0.15)), glow(color:Lerp(BLACK, 0.08)), NEON
	end
	local shadow = look ~= "Glow"
	local bodyCf = base * CFrame.Angles(0, math.pi / 4, 0)
	local main = Geo.block(group, bodyCf * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), bodyColor, bodyMat, {
		CanTouch = false,
		CanQuery = true,
		CanCollide = false,
		CastShadow = shadow,
		Transparency = transparency,
	})
	main.Name = "Crystal"
	if width >= 0.55 or hero then
		local facet = Geo.block(group, base * CFrame.new(0, bodyH * 0.49, 0), Vector3.new(width * 0.84, bodyH * 0.98, width * 0.84), facetColor, bodyMat, {
			CanTouch = false,
			CanQuery = false,
			CanCollide = false,
			CastShadow = false,
			Transparency = transparency * 0.6,
		})
		facet.Name = "CrystalFacet"
	end
	-- (stormglass: only the thicker crystals, so the rocks keep their part budgets)
	if (look == "Shell" and (hero or width >= 0.7)) or (look == "Storm" and (hero or width >= 1.15)) then
		local k = if look == "Storm" then 0.5 else 0.4
		local core = Geo.block(group, bodyCf * CFrame.new(0, bodyH * 0.5, 0), Vector3.new(width * k, bodyH * 0.9, width * k), glow(color), NEON, GLOW)
		core.Name = "CrystalCore"
	end
	if hero then
		-- a real point: four triangles from the body's top corners to the apex
		local corners = {
			bodyCf * CFrame.new(width / 2, bodyH, width / 2),
			bodyCf * CFrame.new(width / 2, bodyH, -width / 2),
			bodyCf * CFrame.new(-width / 2, bodyH, -width / 2),
			bodyCf * CFrame.new(-width / 2, bodyH, width / 2),
		}
		local apex = (bodyCf * CFrame.new(0, bodyH + tipH, 0)).Position
		local center = (bodyCf * CFrame.new(0, bodyH, 0)).Position
		for i = 1, 4 do
			local a = corners[i].Position
			local b = corners[i % 4 + 1].Position
			local faces = Geo.triangle(group, a, b, apex, math.min(0.3, width * 0.25), if i % 2 == 0 then tipA else tipB, tipMat, (a + b) / 2 - center, GLOW)
			for _, f in faces do
				f.Name = "CrystalTip"
			end
		end
	else
		local tipAt = bodyCf * CFrame.new(0, bodyH + tipH / 2, 0)
		local a = Geo.wedge(group, tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tipA, tipMat, GLOW)
		a.Name = "CrystalTip"
		local b = Geo.wedge(group, tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(width, tipH, width / 2), tipB, tipMat, GLOW)
		b.Name = "CrystalTip"
	end
	return main
end

-- A little light star (two crossed neon bars), as at the crystal tips in the reference.
local function twinkle(c: Ctx, position: Vector3, size: number, color: Color3)
	local cf = CFrame.new(position) * CFrame.Angles(c.rng:range(-0.3, 0.3), c.rng:range(0, math.pi), 0)
	local a = Geo.block(c.model, cf, Vector3.new(size, size * 0.12, size * 0.12), color, NEON, GLOW)
	a.Name = "Twinkle"
	local b = Geo.block(c.model, cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(size * 0.8, size * 0.12, size * 0.12), color, NEON, GLOW)
	b.Name = "Twinkle"
end

local function tipOf(part: BasePart): Vector3
	return (part.CFrame * CFrame.new(0, part.Size.Y * 0.62, 0)).Position
end

--[[
	A crystal cluster fanning out of `root` (up = outward): one tall crystal
	in the middle, the others around it, leaning out and shorter the more
	they lean. Returns the tallest body.
]]
local function cluster(c: Ctx, root: CFrame, count: number, height: number, look: Look, colors: { Color3 }, hero: boolean?): BasePart
	local rng = c.rng
	local tallest = crystal(c.model, root * CFrame.Angles(rng:range(-0.08, 0.08), 0, rng:range(-0.08, 0.08)), height, height * 0.22, colors[1], look, hero)
	local others = count - 1
	for i = 1, others do
		local a = (i / others) * math.pi * 2 + rng:range(-0.3, 0.3)
		local amount = rng:range(0.25, 0.7)
		local h = height * rng:range(0.85, 1.0) * (1 - amount * 0.6)
		local foot = root * CFrame.new(math.cos(a) * height * 0.08, -height * 0.04, math.sin(a) * height * 0.08)
		crystal(c.model, tilt(foot, a, amount), h, h * rng:range(0.2, 0.27), colors[i % #colors + 1], look)
	end
	return tallest
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

---------------------------------------------------------------- the rock body

type BodyOpts = {
	Scale: number?,
	Float: number?,
	Carved: boolean?, -- upright pillar shards with flat gold-trimmed tops (Sunken Palace)
	Core: Color3?, -- glowing heart color between the shards (nil = solid rock)
	Chunks: number?, -- shards in the ring
	Flat: number?, -- height multiplier
	Colors: { Color3 }?, -- override Mid, Light, Dark
	Strata: { Color3 }?, -- colored rock layers across the shards (Greystone Quarry)
}

-- A point on the rock surface toward yaw `a` (fraction `up` of the half height), pushed out by `out`.
local function surface(c: Ctx, a: number, up: number, out: number?): CFrame
	local s = c.mainSize
	return c.mainCf * CFrame.new(math.cos(a) * (s.X * 0.5 + (out or 0)), up * s.Y * 0.5, math.sin(a) * (s.Z * 0.5 + (out or 0)))
end

-- A crystal root on top of the central shard toward yaw `a`, at fraction `r` of its half width, leaning out by `lean`.
local function topRoot(c: Ctx, a: number, r: number, lean: number): CFrame
	local foot = c.mainCf * CFrame.new(math.cos(a) * r * c.top, c.mainSize.Y * 0.5 - 0.2, math.sin(a) * r * c.top)
	return tilt(CFrame.new(foot.Position), a, lean)
end

-- A crystal root in the gap between two ring shards (gap `i`), at fraction `up` of the rock height.
local function gapRoot(c: Ctx, i: number, up: number, lean: number): CFrame
	local a = c.gaps[(i - 1) % #c.gaps + 1]
	local p = c.foot * CFrame.new(math.cos(a) * c.ring * 0.62, up * c.mainSize.Y, math.sin(a) * c.ring * 0.62)
	return tilt(CFrame.new(p.Position), a, lean)
end

--[[
	One stone shard: a tall prism with a turned block through it (more,
	alternating light/dark facets, like a basalt column) and a slanted or
	ridged top that catches the light; carved shards get a flat top with a
	gold trim. Returns the body.
]]
local function shard(parent: Instance, foot: CFrame, w: number, d: number, h: number, colors: { Color3 }, rng: Rng.Rng, carved: boolean, accent: Color3?, name: string, strata: { Color3 }?): BasePart
	local mid, lite, dark = colors[1], colors[2], colors[3]
	local body = Geo.block(parent, foot * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), Geo.vary(mid, rng, 0.04), SMOOTH, SOLID)
	body.Name = name
	if strata then
		-- colored rock layers, like the striped quarry cliffs
		local layers = if h > 2.4 then 2 else 1
		for i = 1, layers do
			local y = h * (if layers == 1 then rng:range(0.35, 0.6) else (0.22 + (i - 1) * 0.36 + rng:range(-0.04, 0.04)))
			local band = Geo.block(parent, foot * CFrame.new(0, y, 0), Vector3.new(w + 0.08, rng:range(0.3, 0.46), d + 0.08), Geo.vary(strata[(i + rng:int(0, 1)) % #strata + 1], rng, 0.03), SMOOTH, GLOW)
			band.Name = "Strata"
		end
	end
	local m = math.min(w, d)
	local facet = Geo.block(parent, foot * CFrame.new(0, h * 0.47, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(m * 0.86, h * 0.94, m * 0.86), Geo.vary(mid:Lerp(dark, 0.45), rng, 0.04), SMOOTH, SOLID)
	facet.Name = "Facet"
	local topColor = Geo.vary(lite, rng, 0.04)
	if carved then
		local cap = Geo.block(parent, foot * CFrame.new(0, h + 0.12, 0), Vector3.new(w + 0.16, 0.24, d + 0.16), topColor, SMOOTH, SOLID)
		cap.Name = "Top"
		if accent then
			local trim = Geo.block(parent, foot * CFrame.new(0, h - 0.25, 0), Vector3.new(w + 0.08, 0.2, d + 0.08), accent, FOIL, GLOW)
			trim.Name = "Trim"
		end
	elseif rng:chance(0.55) then
		-- slanted top: one wedge over the whole footprint, sloping toward a random side
		local t = m * rng:range(0.5, 0.85)
		local quarter = rng:int(0, 3)
		local size = if quarter % 2 == 0 then Vector3.new(w, t, d) else Vector3.new(d, t, w)
		local cap = Geo.wedge(parent, foot * CFrame.new(0, h + t / 2, 0) * CFrame.Angles(0, quarter * math.pi / 2, 0), size, topColor, SMOOTH, SOLID)
		cap.Name = "Top"
	else
		-- ridged top: two wedges meeting along the long side, a sharp shard tip
		local t = m * rng:range(0.6, 1.0)
		local long, short = math.max(w, d), math.min(w, d)
		local spin = if w >= d then CFrame.new() else CFrame.Angles(0, math.pi / 2, 0)
		local at = foot * CFrame.new(0, h + t / 2, 0) * spin
		local a = Geo.wedge(parent, at * CFrame.new(0, 0, -short / 4), Vector3.new(long, t, short / 2), topColor, SMOOTH, SOLID)
		a.Name = "Top"
		local b = Geo.wedge(parent, at * CFrame.new(0, 0, short / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(long, t, short / 2), Geo.vary(lite:Lerp(mid, 0.35), rng, 0.04), SMOOTH, SOLID)
		b.Name = "Top"
	end
	return body
end

--[[
	A shard rock (after The Forge's basalt rocks, in our colors): one tall
	central shard (Rock1), a ring of shorter shards leaning outward (Rock2..,
	each a group so a crack stage breaks a whole shard off), a glowing core
	showing through the narrow gaps, two small rubble shards and a foot.
]]
local function body(c: Ctx, opts: BodyOpts): BasePart
	local rng, pal, base = c.rng, c.pal, c.base
	local colors = opts.Colors or { pal.Mid, pal.Light, pal.Dark }
	local scale = opts.Scale or (if c.big then 1.3 else 1)
	local float = opts.Float or 0
	local tall = opts.Flat or 1
	local carved = opts.Carved == true
	local accent = if carved then pal.Accent else nil
	local foot = base * CFrame.new(0, float, 0)
	c.foot = foot
	local h1 = rng:range(3.2, 3.8) * scale * tall
	local w1, d1 = 2.1 * scale, 1.85 * scale
	c.top = math.min(w1, d1) * 0.5
	c.ring = rng:range(1.5, 1.65) * scale
	c.mainSize = Vector3.new(5.2 * scale, h1, 5.0 * scale)
	c.mainCf = foot * CFrame.new(0, h1 / 2, 0)
	if opts.Core then
		local core = Geo.block(c.model, foot * CFrame.new(0, h1 * 0.36, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(2.9 * scale, h1 * 0.6, 2.9 * scale), glow(opts.Core), NEON, GLOW)
		core.Name = "Core"
	end
	local rock1 = shard(c.model, foot * CFrame.Angles(rng:range(-0.05, 0.05), c.start, rng:range(-0.05, 0.05)), w1, d1, h1, colors, rng, carved, accent, "Rock1", opts.Strata)
	local n = opts.Chunks or (if c.big then 6 else 5)
	c.gaps = {}
	for i = 1, n do
		local a = c.start + (i / n) * math.pi * 2 + rng:range(-0.12, 0.12)
		table.insert(c.gaps, a + math.pi / n)
		local at = foot * CFrame.new(math.cos(a) * c.ring, -0.15, math.sin(a) * c.ring)
		local lean = if carved then rng:range(0, 0.06) else rng:range(0.1, 0.28)
		local h = h1 * rng:range(0.45, 0.82)
		local group = Instance.new("Model")
		group.Name = "Rock" .. (i + 1)
		group.Parent = c.model
		local tone = if i % 3 == 0 then { colors[1]:Lerp(colors[2], 0.3), colors[2], colors[3] } else colors
		shard(group, tilt(CFrame.new(at.Position), a, lean) * CFrame.Angles(0, a + rng:range(-0.3, 0.3), 0), rng:range(1.4, 1.9) * scale, rng:range(1.2, 1.6) * scale, h, tone, rng, carved, accent, "Body", opts.Strata)
	end
	for i = 1, 2 do
		local a = c.start + 0.7 + i * 2.6
		local at = foot * CFrame.new(math.cos(a) * c.ring * 1.75, -0.1, math.sin(a) * c.ring * 1.75)
		local s = rng:range(0.6, 0.85) * scale
		local rubble = Geo.block(c.model, tilt(CFrame.new(at.Position), a, rng:range(0.2, 0.5)) * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(s, s * rng:range(1.1, 1.7), s * 0.85), Geo.vary(colors[3]:Lerp(colors[1], 0.4), rng, 0.05), SMOOTH, SMALL)
		rubble.Name = "Pebble"
	end
	if float > 0 then
		local k = 2.4 * scale
		local keel = Geo.block(c.model, foot * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, c.start, 0) * VERTEX_UP, Vector3.new(k, k, k), Geo.vary(colors[3], rng, 0.03), SMOOTH, SOLID)
		keel.Name = "Keel"
	else
		local skirt = Geo.block(c.model, foot * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, c.start + 0.4, 0), Vector3.new(4.6 * scale, 0.45, 4.4 * scale), Geo.vary(colors[3], rng, 0.03), SMOOTH, SOLID)
		skirt.Name = "Skirt"
	end
	-- the central shard's top is the "Cap" (moss sits on it on the lagoon floor)
	for _, child in c.model:GetChildren() do
		if child.Name == "Top" and child:IsA("BasePart") then
			child.Name = "Cap"
			break
		end
	end
	return rock1
end

-- One glint per ore on the rock's sides (tiny gems in the ore's glow color).
local function glints(c: Ctx, oreIds: { string })
	local count = #oreIds
	for i, oreId in oreIds do
		local ore = OreData.ById[oreId]
		local color = glow(if ore then ore.Glow else c.pal.Accent)
		local a = c.start + 0.5 + (i - 1) * (math.pi * 2 / math.max(count, 1)) + c.rng:range(-0.15, 0.15)
		local g = Geo.block(c.model, surface(c, a, c.rng:range(-0.5, -0.1), -0.25) * CFrame.Angles(0, -a, 0) * VERTEX_UP, Vector3.new(0.55, 0.55, 0.55), color, NEON, GLOW)
		g.Name = "Glint"
	end
end

-- The two floor crystal clusters on a normal rock: one crowning the central shard, one out of a gap.
local function rockClusters(c: Ctx, look: Look, height: number, colorsA: { Color3 }, colorsB: { Color3 }): BasePart
	local mainCount = if c.big then 6 else 5
	local tallest = cluster(c, topRoot(c, c.start + 2.2, 0.3, 0.15), mainCount, height * (if c.big then 1.15 else 1), look, colorsA)
	local root = gapRoot(c, 3, 0.4, 0.55)
	cluster(c, root, 3, height * 0.62, look, colorsB)
	return tallest
end

---------------------------------------------------------------- floor looks

-- Floor 1, Greystone Quarry: blue-grey slate shards (they stand out on the sandy quarry
-- floor) with pale layers, shiny copper veins and nuggets catching the sun, grass at the
-- foot, and a crown of copper and quartz crystals with glowing tips (the first floor has to
-- grab players at first sight).
local QUARRY_STRATA = { Color3.fromRGB(150, 158, 178), Color3.fromRGB(96, 100, 120) }
local COPPER = Color3.fromRGB(232, 132, 66)
local GRASS = { Color3.fromRGB(104, 178, 70), Color3.fromRGB(132, 200, 84) }

local function quarry(c: Ctx, oreIds: { string })
	local rng = c.rng
	body(c, { Strata = QUARRY_STRATA })
	-- copper veins: shiny metal strips across the outer shards, and a few nuggets
	for i = 1, 2 do
		local a = c.start + 0.9 + i * 2.7
		local at = surface(c, a, rng:range(-0.35, 0.15), -0.32)
		local vein = Geo.block(c.model, at * CFrame.Angles(0, -a + math.pi / 2, rng:range(-0.9, 0.9)), Vector3.new(rng:range(1.6, 2.3), 0.24, 0.16), COPPER, FOIL, GLOW)
		vein.Name = "Vein"
	end
	for i = 1, 3 do
		local a = c.start + 2.0 + i * 1.9
		local s = rng:range(0.45, 0.65)
		local nugget = Geo.block(c.model, surface(c, a, rng:range(-0.6, 0.1), -0.25) * randomTilt(rng, 0.6), Vector3.new(s, s * 0.8, s), COPPER:Lerp(Color3.fromRGB(255, 200, 120), rng:range(0, 0.4)), FOIL, SMALL)
		nugget.Name = "Nugget"
	end
	-- grass tufts at the foot (the quarry is open to the sky)
	for i = 1, 2 do
		local a = c.start + 1.6 + i * 3.1
		local root = c.foot * CFrame.new(math.cos(a) * c.ring * 1.55, 0, math.sin(a) * c.ring * 1.55)
		for j = 1, 3 do
			local b = a + (j - 2) * 0.7
			local h = rng:range(0.6, 0.95)
			local blade = Geo.block(c.model, tilt(root, b, 0.35) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, b, 0), Vector3.new(0.2, h, 0.12), GRASS[j % 2 + 1], SMOOTH, GLOW)
			blade.Name = "Grass"
		end
	end
	local tallest = rockClusters(c, "Tipped", 3.1, { c.pal.Crystal, c.pal.Crystal:Lerp(WHITE, 0.25) }, { c.pal.Crystal2, c.pal.Crystal })
	twinkle(c, tipOf(tallest), 0.8, glow(Color3.fromRGB(255, 230, 190)))
	glints(c, oreIds)
end

-- Floor 2, Ember Caves: dark basalt chunks around a lava heart, fire-tipped crystals.
local function ember(c: Ctx, oreIds: { string })
	body(c, { Core = c.pal.Accent })
	local tallest = rockClusters(c, "Tipped", 3.3, { c.pal.Crystal, c.pal.Crystal2 }, { c.pal.Crystal2, c.pal.Crystal })
	twinkle(c, tipOf(tallest), 0.8, glow(c.pal.Crystal:Lerp(WHITE, 0.5)))
	glints(c, oreIds)
end

-- Floor 3, Deep Hollow (crystal lagoon): wet blue stone around an icy glow, moss, a mushroom, glassy crystals.
local function lagoon(c: Ctx, oreIds: { string })
	body(c, { Core = c.pal.Crystal })
	-- wet moss patches around the foot
	for i = 1, 3 do
		local a = c.start + 1.1 + i * 2.05
		local at = c.foot * CFrame.new(math.cos(a) * c.ring * 1.25, 0.46, math.sin(a) * c.ring * 1.25) * CFrame.Angles(0, a, 0)
		local moss = Geo.block(c.model, at, Vector3.new(c.rng:range(1.0, 1.5), 0.16, c.rng:range(0.7, 1.1)), c.pal.Accent, SMOOTH, SMALL)
		moss.Name = "Moss"
	end
	local tallest = rockClusters(c, "Shell", 3.45, { c.pal.Crystal, c.pal.Crystal2 }, { c.pal.Crystal2, c.pal.Crystal })
	twinkle(c, tipOf(tallest), 0.9, glow(c.pal.Crystal2))
	local a = c.start + 4.4
	local foot = c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.62, 0, math.sin(a) * c.mainSize.Z * 0.62)
	local stem = Geo.block(c.model, foot * CFrame.new(0, 0.45, 0), Vector3.new(0.28, 0.9, 0.28), Color3.fromRGB(214, 236, 230), SMOOTH, GLOW)
	stem.Name = "Mushroom"
	local capPart = Geo.block(c.model, foot * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.32, 1.1, 1.1), glow(Color3.fromRGB(110, 255, 210)), NEON, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Cylinder,
	})
	capPart.Name = "Mushroom"
	glints(c, oreIds)
end

-- Floor 4, Sunken Palace: carved stone chunks around a gold glow, a gold trim, a fallen column, gold and lavender crystals.
local function palace(c: Ctx, oreIds: { string })
	local rock1 = body(c, { Carved = true, Core = c.pal.Accent })
	local trim = Geo.block(c.model, rock1.CFrame * CFrame.new(0, -rock1.Size.Y * 0.2, 0), Vector3.new(rock1.Size.X + 0.12, 0.32, rock1.Size.Z + 0.12), c.pal.Accent, FOIL, GLOW)
	trim.Name = "Trim"
	local a = c.start + 3.8
	local foot = c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.7, 0.62, math.sin(a) * c.mainSize.Z * 0.7)
	local column = Geo.block(c.model, foot * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(0, 0, 0.18), Vector3.new(2.6, 1.24, 1.24), c.pal.Light:Lerp(WHITE, 0.15), SMOOTH, {
		CanTouch = false,
		CanQuery = true,
		CanCollide = true,
		Shape = Enum.PartType.Cylinder,
	})
	column.Name = "Column"
	local ring = Geo.block(c.model, column.CFrame * CFrame.new(0.9, 0, 0), Vector3.new(0.26, 1.42, 1.42), c.pal.Accent, FOIL, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Cylinder,
	})
	ring.Name = "Trim"
	local tallest = rockClusters(c, "Shell", 3.6, { c.pal.Crystal, c.pal.Crystal2 }, { c.pal.Crystal2, c.pal.Crystal })
	twinkle(c, tipOf(tallest), 1.0, glow(c.pal.Crystal:Lerp(WHITE, 0.4)))
	glints(c, oreIds)
end

-- Floor 6, Heartstone Core: a dark floating rock around a pink heart glow, orbiting debris, glowing crystals.
local function core(c: Ctx, oreIds: { string })
	local rng = c.rng
	body(c, { Float = 1.1, Core = c.pal.Crystal, Chunks = 5 })
	for i = 1, 2 do
		local a = c.start + i * 2.9
		local s = rng:range(0.7, 1.0)
		local bit = Geo.block(
			c.model,
			c.base * CFrame.new(math.cos(a) * c.mainSize.X * 0.8, c.mainSize.Y * rng:range(0.5, 0.9) + 1, math.sin(a) * c.mainSize.Z * 0.8) * randomTilt(rng, 0.6),
			Vector3.new(s, s * 0.8, s),
			Geo.vary(c.pal.Light, rng, 0.05),
			SMOOTH,
			SMALL
		)
		bit.Name = "Debris"
	end
	local tallest = rockClusters(c, "Glow", 3.8, { c.pal.Crystal, c.pal.Crystal2 }, { c.pal.Crystal2, c.pal.Accent })
	twinkle(c, tipOf(tallest), 1.1, glow(c.pal.Crystal2:Lerp(WHITE, 0.3)))
	light(tallest, glow(c.pal.Crystal), 12, 1.1)
	glints(c, oreIds)
end

-- Stormglass Rift: dark indigo shards around trapped lightning (a yellow glow in the gaps),
-- glowing zig-zag cracks down the outer shards, a crown of stormglass crystals (smoky indigo
-- glass, a bright core, yellow-white neon tips) and a spark at the top.
local function storm(c: Ctx, oreIds: { string })
	local rng = c.rng
	body(c, { Core = c.pal.Crystal, Chunks = 5 })
	-- lightning cracks: two neon strips meeting at a sharp bend, flat on the rock's face
	local crackColor = glow(c.pal.Crystal:Lerp(WHITE, 0.35))
	for i = 1, 2 do
		local a = c.start + 1.2 + i * 2.5
		local face = surface(c, a, rng:range(-0.2, 0.3), -0.3) * CFrame.Angles(0, -a + math.pi / 2, 0)
		local roll = rng:range(0.9, 1.25) * (if i == 1 then 1 else -1)
		local len1, len2 = rng:range(0.9, 1.2), rng:range(0.8, 1.1)
		local first = face * CFrame.Angles(0, 0, roll) * CFrame.new(-len1 / 2, 0, 0)
		local a1 = Geo.block(c.model, first, Vector3.new(len1, 0.2, 0.14), crackColor, NEON, GLOW)
		a1.Name = "Vein"
		local second = face * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, 0, -roll * 1.7) * CFrame.new(len2 / 2 - 0.05, 0, 0)
		local a2 = Geo.block(c.model, second, Vector3.new(len2, 0.18, 0.14), crackColor, NEON, GLOW)
		a2.Name = "Vein"
	end
	local tallest = rockClusters(c, "Storm", 3.7, { c.pal.Crystal, c.pal.Crystal2 }, { c.pal.Crystal2, c.pal.Crystal })
	twinkle(c, tipOf(tallest), 1.0, glow(c.pal.Crystal2))
	glints(c, oreIds)
end

--[[
	Every floor's rock look by its MineFloors Id (FloorLook above). Tier, Core,
	Float and Carved of the first five floors are what their Index gave before the
	Rift went in, so their rocks stay exactly as they were; a floor without an
	entry gets the quarry's.
]]
local LOOKS: { [string]: FloorLook } = {
	Quarry = { Build = quarry, Tier = 1, CrystalLook = "Tipped", GiantLook = "Tipped" },
	EmberCaves = { Build = ember, Tier = 2, CrystalLook = "Shell", GiantLook = "Shell", Core = "Accent" },
	DeepHollow = { Build = lagoon, Tier = 3, CrystalLook = "Shell", GiantLook = "Shell", Core = "Crystal" },
	SunkenPalace = { Build = palace, Tier = 4, CrystalLook = "Glow", GiantLook = "Shell", Core = "Accent", Carved = true },
	-- floor 5, between the palace and the core (blaster 8+): stormglass everywhere, richer on its Crystal rocks
	StormglassRift = { Build = storm, Tier = 4.5, CrystalLook = "Storm", GiantLook = "Storm", Core = "Crystal" },
	HeartstoneCore = { Build = core, Tier = 5, CrystalLook = "Glow", GiantLook = "Glow", Core = "Crystal", Float = true },
}

local function lookOf(floor: MineFloors.Floor): FloorLook
	return LOOKS[floor.Id] or LOOKS.Quarry
end

-- The glowing core color of a floor's rocks (nil = solid rock).
local function coreColor(c: Ctx): Color3?
	if c.look.Core == "Accent" then
		return c.pal.Accent
	elseif c.look.Core == "Crystal" then
		return c.pal.Crystal
	end
	return nil
end

---------------------------------------------------------------- special kinds

-- Crystal rock: a low rock with a dense crystal cluster in the floor's colors and a pointed hero crystal.
local function crystalRock(c: Ctx)
	local tier = c.look.Tier
	local look: Look = c.look.CrystalLook
	body(c, { Scale = 0.8, Flat = 0.45, Chunks = 4, Float = if c.look.Float then 0.8 else 0, Carved = c.look.Carved == true, Core = coreColor(c) or c.pal.Crystal })
	local mainH = 5 + tier * 0.5
	local main = cluster(c, topRoot(c, c.start, 0.05, 0), 9, mainH, look, { c.pal.Crystal, c.pal.Crystal2, c.pal.Crystal:Lerp(WHITE, 0.2) }, true)
	cluster(c, gapRoot(c, 2, 0.35, 0.6), 4, mainH * 0.45, look, { c.pal.Crystal2, c.pal.Crystal })
	light(main, glow(c.pal.Crystal), 14 + tier, 1 + tier * 0.12)
	sparkle(main, glow(c.pal.Crystal:Lerp(WHITE, 0.3)), 2 + tier * 0.5, 0.6)
	twinkle(c, tipOf(main), 1.2, glow(c.pal.Crystal2:Lerp(WHITE, 0.4)))
	twinkle(c, (main.CFrame * CFrame.new(main.Size.X * 0.9, -main.Size.Y * 0.1, 0)).Position, 0.8, glow(c.pal.Crystal:Lerp(WHITE, 0.5)))
end

-- Golden rock: gold chunks around a gold heart, a gold crystal cluster and nuggets (the same on every floor).
local function goldenRock(c: Ctx)
	local S = RockBuilder.Special
	local rng = c.rng
	body(c, {
		Float = if c.look.Float then 1.1 else 0,
		Core = S.Gold,
		Colors = { S.Gold:Lerp(S.GoldDeep, 0.45), S.Gold:Lerp(WHITE, 0.2), S.GoldDeep:Lerp(BLACK, 0.25) },
	})
	for i = 1, 3 do
		local a = c.start + 1 + i * 2.1
		local s = rng:range(0.7, 0.95)
		local n = Geo.block(c.model, surface(c, a, rng:range(-0.2, 0.3), 0.1) * randomTilt(rng, 0.5), Vector3.new(s, s * 0.8, s), S.Gold, FOIL, SMALL)
		n.Name = "Nugget"
	end
	local main = cluster(c, topRoot(c, c.start + 2.2, 0.25, 0.2), 6, 2.9, "Tipped", { S.Gold, S.Gold:Lerp(WHITE, 0.35), S.GoldDeep })
	light(main, glow(S.Gold), 13, 1.1)
	sparkle(main, glow(S.Gold:Lerp(WHITE, 0.3)), 4, 0.55)
	twinkle(c, tipOf(main), 1.0, glow(S.Gold:Lerp(WHITE, 0.5)))
end

-- Geode: a round rock split in two, its glowing violet inside full of crystals.
local function geodeRock(c: Ctx)
	local S = RockBuilder.Special
	local rng = c.rng
	local float = if c.look.Float then 1.1 else 0
	local shell = S.GeodeShell:Lerp(c.pal.Mid, 0.35)
	local s = rng:range(3.8, 4.2)
	local gap = 0.9
	c.mainSize = Vector3.new(s, s * 0.82, s)
	c.mainCf = c.base * CFrame.new(0, s * 0.36 + float, 0)
	local core = Geo.block(c.model, c.mainCf * CFrame.new(0, -0.1, 0), Vector3.new(gap + 0.5, s * 0.66, s * 0.76), glow(S.Geode), NEON, GLOW)
	core.Name = "Core"
	for side = -1, 1, 2 do
		local half = c.mainCf * CFrame.new(side * (s / 4 + gap / 2), 0, 0) * CFrame.Angles(0, 0, -side * 0.16)
		local part = Geo.block(c.model, half, Vector3.new(s / 2, s * 0.82, s * 0.92), Geo.vary(shell, rng, 0.03), SMOOTH, SOLID)
		part.Name = if side < 0 then "Rock1" else "Rock2"
		local round = Geo.block(c.model, half * CFrame.new(side * 0.12, -0.05, 0) * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(s * 0.44, s * 0.74, s * 0.74), Geo.vary(shell:Lerp(c.pal.Dark, 0.25), rng, 0.03), SMOOTH, SOLID)
		round.Name = if side < 0 then "Rock3" else "Rock4"
		local chip = Geo.block(c.model, half * CFrame.new(side * s * 0.12, s * 0.36, rng:range(-0.4, 0.4)) * randomTilt(rng, 0.4), Vector3.new(s * 0.3, s * 0.2, s * 0.34), Geo.vary(shell:Lerp(WHITE, 0.12), rng, 0.03), SMOOTH, SOLID)
		chip.Name = "Cap"
		local rim = Geo.block(c.model, half * CFrame.new(-side * (s / 4 - 0.08), 0.1, 0), Vector3.new(0.18, s * 0.6, s * 0.7), S.Geode:Lerp(WHITE, 0.15), SMOOTH, GLOW)
		rim.Name = "Hollow"
	end
	if float == 0 then
		local skirt = Geo.block(c.model, c.base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0.3, 0), Vector3.new(s * 1.15, 0.6, s * 1.05), Geo.vary(c.pal.Dark, rng, 0.03), SMOOTH, SOLID)
		skirt.Name = "Skirt"
	end
	local lit: BasePart? = nil
	for i = 1, 8 do
		local z = (i - 4.5) / 4 * s * 0.34
		local side = if i % 2 == 0 then 1 else -1
		local foot = c.mainCf * CFrame.new(side * 0.16, s * 0.18, z)
		local h = rng:range(1.3, 2.2) * (1 - math.abs(z) / s * 0.8)
		local part = crystal(c.model, foot * CFrame.Angles(rng:range(-0.3, 0.3), 0, -side * rng:range(0.15, 0.45)), h, h * 0.26, if i % 3 == 0 then S.Geode:Lerp(WHITE, 0.45) else S.Geode, "Glow")
		if not lit or part.Size.Y > (lit :: BasePart).Size.Y then
			lit = part
		end
	end
	if lit then
		light(lit, glow(S.Geode), 12, 1.3)
		sparkle(lit, glow(S.Geode:Lerp(WHITE, 0.3)), 3, 0.5)
		twinkle(c, tipOf(lit), 0.9, glow(S.Geode:Lerp(WHITE, 0.5)))
	end
end

-- Artifact rock: the floor rock with a glowing rune stone and a royal crown sticking out.
local function artifactRock(c: Ctx, oreIds: { string })
	local S = RockBuilder.Special
	body(c, { Float = if c.look.Float then 1.1 else 0, Carved = c.look.Carved == true, Chunks = 4 })
	local a = c.start + 2.4
	local face = CFrame.new((c.mainCf * CFrame.new(math.cos(a) * c.mainSize.X * 0.5, c.mainSize.Y * 0.05, math.sin(a) * c.mainSize.Z * 0.5)).Position) * CFrame.Angles(0, -a, 0)
	local plate = Geo.block(c.model, face * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(0.4, 2.1, 2.1), c.pal.Light:Lerp(WHITE, 0.25), SMOOTH, GLOW)
	plate.Name = "Rune"
	local disc = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Shape = Enum.PartType.Cylinder }
	local ring = Geo.block(c.model, face * CFrame.new(0.16, 0, 0), Vector3.new(0.12, 1.6, 1.6), glow(S.Rune), NEON, disc)
	ring.Name = "Rune"
	local dot = Geo.block(c.model, face * CFrame.new(0.24, 0, 0), Vector3.new(0.12, 0.9, 0.9), plate.Color, SMOOTH, disc)
	dot.Name = "Rune"
	local glyph = Geo.block(c.model, face * CFrame.new(0.3, 0, 0) * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(0.1, 0.46, 0.46), glow(S.Rune), NEON, GLOW)
	glyph.Name = "Rune"
	local crownAt = c.mainCf * CFrame.new(-0.3, c.mainSize.Y * 0.5 + 0.1, 0.3) * CFrame.Angles(0.35, c.start, 0.2)
	local band = Geo.block(c.model, crownAt * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.55, 1.4, 1.4), S.Gold, FOIL, {
		CanTouch = false,
		CanQuery = true,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	band.Name = "Relic"
	for i = 1, 4 do
		local ang = i * (math.pi / 2)
		local spike = Geo.block(c.model, crownAt * CFrame.new(math.cos(ang) * 0.55, 0.45, math.sin(ang) * 0.55) * CFrame.Angles(0, ang, 0) * VERTEX_UP, Vector3.new(0.38, 0.38, 0.38), S.Gold:Lerp(WHITE, 0.15), FOIL, GLOW)
		spike.Name = "Relic"
	end
	local jewel = Geo.block(c.model, crownAt * CFrame.new(0, 0.1, 0.72) * VERTEX_UP, Vector3.new(0.3, 0.3, 0.3), glow(Color3.fromRGB(255, 60, 90)), NEON, GLOW)
	jewel.Name = "Relic"
	light(ring, glow(S.Rune), 10, 1)
	twinkle(c, (crownAt * CFrame.new(0.3, 0.9, 0)).Position, 0.8, glow(S.Gold:Lerp(WHITE, 0.5)))
	glints(c, oreIds)
end

-- Giant Crystal: the floor's server-wide event crystal on a broken rock base.
local function giantRock(c: Ctx)
	local rng, pal = c.rng, c.pal
	local look: Look = c.look.GiantLook
	body(c, { Scale = 2.3, Flat = 0.4, Chunks = 6, Carved = c.look.Carved == true, Core = coreColor(c) or pal.Crystal })
	local mainH = 15 + c.look.Tier
	local main = cluster(c, topRoot(c, c.start, 0.0, 0), 11, mainH, look, { pal.Crystal, pal.Crystal2, pal.Crystal:Lerp(WHITE, 0.2) }, true)
	for i = 1, #c.gaps do
		cluster(c, gapRoot(c, i, 0.45, 0.7), 3, rng:range(3, 4.4), "Glow", { if i % 2 == 0 then pal.Crystal2 else pal.Crystal, pal.Crystal })
	end
	light(main, glow(pal.Crystal), 40, 2)
	sparkle(main, glow(pal.Crystal:Lerp(WHITE, 0.3)), 8, 1.2)
	twinkle(c, tipOf(main), 2.2, glow(pal.Crystal2:Lerp(WHITE, 0.4)))
	twinkle(c, (main.CFrame * CFrame.new(2.4, -2, 0)).Position, 1.4, glow(pal.Crystal:Lerp(WHITE, 0.5)))
end

---------------------------------------------------------------- decoration

-- A crystal cluster on its own, for cave decorations that match the rocks (MineKit.crystals).
-- look: "Matte" | "Tipped" | "Shell" | "Glow" | "Storm"; tall clusters (height >= 4) get a pointed hero crystal.
function RockBuilder.decorCluster(parent: Instance, root: CFrame, count: number, height: number, look: string, colors: { Color3 }, seed: number | string): Model
	local model = Instance.new("Model")
	model.Name = "CrystalCluster"
	model.Parent = parent
	local floor = MineFloors.List[1]
	local c: Ctx = {
		model = model,
		rng = Rng.new(seed),
		floor = floor,
		pal = floor.Palette,
		base = root,
		kind = "Decor",
		big = false,
		mainCf = root,
		mainSize = Vector3.new(1, 1, 1),
		start = 0,
		foot = root,
		ring = 1,
		top = 1,
		gaps = {},
		look = lookOf(floor),
	}
	local l: Look = if look == "Matte" then "Matte" elseif look == "Tipped" then "Tipped" elseif look == "Glow" then "Glow" elseif look == "Storm" then "Storm" else "Shell"
	local tallest = cluster(c, root, math.max(1, count), height, l, colors, height >= 4)
	if l ~= "Matte" then
		twinkle(c, tipOf(tallest), math.clamp(height * 0.28, 0.6, 2.4), glow(colors[1]:Lerp(WHITE, 0.4)))
	end
	return model
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
		foot = base,
		ring = 1,
		top = 1,
		gaps = {},
		look = lookOf(floor),
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
		c.look.Build(c, oreIds)
	end
	local rock1 = model:FindFirstChild("Rock1")
	if rock1 and rock1:IsA("BasePart") then
		model.PrimaryPart = rock1
	end
	model:SetAttribute("Floor", floor.Index)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Zone", floor.ZoneId)
	model:SetAttribute("OreCount", #oreIds)
	model:SetAttribute("Stage", 0)
	if kind == "Artifact" then
		model:SetAttribute("Artifact", true)
	end
	return model
end

---------------------------------------------------------------- crack stages

local CRACK = Color3.fromRGB(26, 18, 18)

-- A glowing crack on the outer face of `part` (the face pointing most along `outward`).
local function crackOn(model: Model, part: BasePart, outward: Vector3, color: Color3, rng: Rng.Rng)
	local cf = part.CFrame
	local size = part.Size
	-- candidate faces: normal, depth along it, and the face's two spans
	local faces = {
		{ n = cf.RightVector, d = size.X, a = size.Y, b = size.Z },
		{ n = -cf.RightVector, d = size.X, a = size.Y, b = size.Z },
		{ n = -cf.LookVector, d = size.Z, a = size.Y, b = size.X },
		{ n = cf.LookVector, d = size.Z, a = size.Y, b = size.X },
		{ n = cf.UpVector, d = size.Y, a = size.X, b = size.Z },
	}
	local best = faces[1]
	for _, face in faces do
		if face.n:Dot(outward) > best.n:Dot(outward) then
			best = face
		end
	end
	local length = math.min(best.a, best.b) * rng:range(0.7, 0.95)
	local center = cf.Position + best.n * (best.d / 2)
	-- a frame whose X axis is the face normal; the crack runs along Y, spun inside the face
	local up = if math.abs(best.n.Y) > 0.9 then cf.RightVector else Vector3.new(0, 1, 0)
	local frame = CFrame.lookAt(center, center + best.n, up) * CFrame.Angles(0, -math.pi / 2, 0)
	frame = frame * CFrame.new(0, rng:range(-0.15, 0.15) * best.a, 0) * CFrame.Angles(rng:range(-0.8, 0.8), 0, 0)
	local dark = Geo.block(model, frame, Vector3.new(0.16, length, 0.38), CRACK, SMOOTH, GLOW)
	dark.Name = "Crack"
	local line = Geo.block(model, frame * CFrame.new(0.04, 0, 0), Vector3.new(0.18, length * 0.82, 0.15), color, NEON, GLOW)
	line.Name = "Crack"
	local turn = rng:range(0.6, 1.0) * (if rng:chance(0.5) then 1 else -1)
	local branchLen = length * rng:range(0.4, 0.55)
	local branch = Geo.block(model, frame * CFrame.new(0.04, length * 0.38, 0) * CFrame.Angles(turn, 0, 0) * CFrame.new(0, branchLen / 2, 0), Vector3.new(0.18, branchLen, 0.12), color, NEON, GLOW)
	branch.Name = "Crack"
end

--[[
	Cracks a rock open one ore at a time: stage s (1 .. OreCount - 1) puts
	glowing cracks in the color of the s-th ore on the outer chunks, and breaks
	one chunk and one crystal off (returned so the caller can fling and remove
	them); the last ore comes out when the rock shatters (client VFX).
]]
function RockBuilder.applyStage(model: Model, stage: number, seed: number | string): { BasePart }
	local broken: { BasePart } = {}
	local rock1 = model:FindFirstChild("Rock1")
	if not rock1 or not rock1:IsA("BasePart") then
		return broken
	end
	local rng = Rng.new(tostring(seed) .. ":" .. stage)
	local glintColors: { Color3 } = {}
	local chunks: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Glint" then
				table.insert(glintColors, child.Color)
			elseif string.match(child.Name, "^Rock%d+$") then
				table.insert(chunks, child)
			end
		elseif child:IsA("Model") and string.match(child.Name, "^Rock%d+$") then
			local shardBody = child:FindFirstChild("Body")
			if shardBody and shardBody:IsA("BasePart") then
				table.insert(chunks, shardBody)
			end
		end
	end
	local floorIndex = model:GetAttribute("Floor")
	local fallback = glow(MineFloors.get(if type(floorIndex) == "number" then floorIndex else 1).Palette.Accent)
	local color = glintColors[stage] or glintColors[1] or fallback
	local center = rock1.CFrame.Position
	-- 2 cracks at stage 1, 3 at stage 2, 4 at stage 3, on different chunks
	local cracks = math.clamp(stage + 1, 2, 4)
	for i = 1, cracks do
		local part = chunks[(stage * 3 + i * 2) % #chunks + 1]
		local outward = part.CFrame.Position - center
		if outward.Magnitude < 0.2 then
			outward = Vector3.new(math.cos(i * 2.1), 0.4, math.sin(i * 2.1))
		end
		crackOn(model, part, outward.Unit, color, rng)
	end
	-- one shard (or chunk) and one crystal break off
	local lump = model:FindFirstChild("Rock" .. (stage + 1))
	if lump and lump:IsA("BasePart") then
		table.insert(broken, lump)
	elseif lump and lump:IsA("Model") then
		for _, d in lump:GetChildren() do
			if d:IsA("BasePart") then
				d.Parent = model
				table.insert(broken, d)
			end
		end
		lump:Destroy()
	end
	local groups: { Instance } = {}
	for _, child in model:GetChildren() do
		if child.Name == "CrystalGroup" and child:FindFirstChild("Crystal") then
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
