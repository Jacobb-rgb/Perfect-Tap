--[[
	Looks of the SECRET ores (owner 2026-10-29: "secret ore ... jenom na malou
	šanci", SecretOreConfig): one recipe per ore, keyed by the ore Id
	(OreData Shape = Id), registered into ItemBuilder like OreShapesHigh and
	built with the same kit (see its header: c.Full, c.Pal, block / wedge /
	ball / cyl / point / beam / hexPrism, tones or a Color3).
	A secret ore looks like nothing else in the mine: its own colours (not
	the ore palette alone), glowing parts on every copy and, on the display
	copy, a little extra floating around it (ItemBuilder adds the motes and
	the light for Secret like for Mythic).

	v2 (owner 2026-10-29: "mnohem mnohem víc cool"): every display copy has
	parts that move (move(): a Move kind for SecretOreFx: crystals orbiting,
	the eye looking round and blinking, the clam breathing, the lightning
	flickering, the heart beating with its wings flapping and a ring of
	little worlds, the star turning in a whirling rainbow disc), and
	SecretOreFx.dress adds the aura (halo, glowing bubble, sparkles, floor).

	Budgets as the tests count them: the clean ore is an invisible Body plus
	the recipe (at most 7 specs); the display recipe makes at most 20 specs
	(ItemBuilder adds 3 motes and SecretOreFx 8 aura parts: <=
	ItemBuilder.Budget.SecretDisplay). The FIRST spec of a display stands
	upright (a ball or a block turned about Y only): it becomes the
	PrimaryPart and the podium turns the model about its Y axis.
	The podium camera looks at the +Z side.
]]

local SecretOreShapes = {}

SecretOreShapes.Ores = {
	"FrostflameCrystal",
	"HollowEye",
	"TidecrownPearl",
	"CagedLightning",
	"HeartOfTerra",
	"RainbowNova",
}

-- the spec ItemBuilder makes for every part (see ItemBuilder.put)
type Spec = {
	Shape: string,
	CF: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	Neon: boolean,
	Name: string?,
	Move: string?,
	Pivot: Vector3?,
	Axis: Vector3?,
	Speed: number?,
	Phase: number?,
	Amount: number?,
}
type Tone = string | Color3
type Ctx = any
type Kit = {
	P: (number, number, number) -> CFrame,
	A: (number, number, number) -> CFrame,
	V: (number, number, number) -> Vector3,
	block: (Ctx, CFrame, Vector3, Tone) -> Spec,
	wedge: (Ctx, CFrame, Vector3, Tone) -> Spec,
	ball: (Ctx, Vector3, number, Tone) -> Spec,
	cyl: (Ctx, CFrame, number, number, Tone) -> Spec,
	point: (Ctx, CFrame, number, Tone) -> Spec,
	beam: (Ctx, Vector3, Vector3, number, Tone) -> Spec,
	hexPrism: (Ctx, CFrame, number, number, { Tone }) -> (),
	onBall: (Vector3, number, Vector3, number?) -> Vector3,
	VertexUp: CFrame,
	UpCyl: CFrame,
}

local PI = math.pi
local BLACK = Color3.new(0, 0, 0)
local FACE = -0.3 -- flat looks turn this far (the podium shows ores turned +0.45)

local GOLD = Color3.fromRGB(255, 200, 84)
local GOLD_DARK = Color3.fromRGB(196, 136, 40)

-- The rainbow of Rainbow Nova, red to violet (also SecretOreConfig.Rainbow for the client's colour drift).
SecretOreShapes.Rainbow = {
	Color3.fromRGB(255, 70, 96),
	Color3.fromRGB(255, 156, 48),
	Color3.fromRGB(255, 228, 64),
	Color3.fromRGB(80, 236, 120),
	Color3.fromRGB(64, 156, 255),
	Color3.fromRGB(176, 92, 255),
}

-- Neon colour that keeps its hue under bloom (the same rule as ItemBuilder.glowColor).
local function glowOf(color: Color3): Color3
	local h, s, v = color:ToHSV()
	local safe = Color3.fromHSV(h, math.max(s, 0.62), math.min(v, 0.84))
	local luminance = 0.2126 * safe.R + 0.7152 * safe.G + 0.0722 * safe.B
	if luminance > 0.7 then
		safe = safe:Lerp(BLACK, 1 - 0.7 / luminance)
	end
	return safe
end

-- A part that glows in its own colour, not the ore's glow.
local function lit(spec: Spec, color: Color3): Spec
	spec.Color = glowOf(color)
	spec.Material = Enum.Material.Neon
	spec.Reflectance = 0
	spec.Transparency = 0
	spec.Neon = true
	return spec
end

local function shiny(spec: Spec, reflectance: number): Spec
	spec.Reflectance = reflectance
	return spec
end

-- A part that moves on the display (SecretOreFx kinds; pivot and axis in unit space).
local function move(spec: Spec, kind: string, pivot: Vector3?, axis: Vector3?, speed: number?, phase: number?, amount: number?): Spec
	spec.Move = kind
	spec.Pivot = pivot
	spec.Axis = axis
	spec.Speed = speed
	spec.Phase = phase
	spec.Amount = amount
	return spec
end

function SecretOreShapes.register(shapes: { [string]: (any) -> () }, kit: any)
	local K: Kit = kit
	local P, A, V = K.P, K.A, K.V
	local block, wedge, ball, cyl, point, beam = K.block, K.wedge, K.ball, K.cyl, K.point, K.beam
	local UP = Vector3.yAxis

	-- Ember Caves: an ice crystal and a fire crystal crossed on a frosted, glowing rock,
	-- white-hot where they meet; ice shards and embers circle it in opposite ways.
	shapes.FrostflameCrystal = function(c: Ctx)
		local ice, iceDark = Color3.fromRGB(156, 230, 255), Color3.fromRGB(78, 156, 232)
		local fire, fireDark = Color3.fromRGB(255, 132, 44), Color3.fromRGB(214, 64, 22)
		local rock = Color3.fromRGB(46, 38, 52)
		local left = P(-0.26, 0.98, 0) * A(0, 0.2, 0.34)
		local right = P(0.26, 0.98, 0.02) * A(0, -0.2, -0.34)
		local heart = Vector3.new(0, 0.98, 0.1)
		if c.Full then
			shiny(block(c, P(0, 0.2, 0) * A(0, 0.35, 0), V(1.5, 0.4, 1.15), rock), 0.05)
			shiny(block(c, P(-0.4, 0.42, 0.06) * A(0, 0.35, 0.1), V(0.74, 0.08, 0.9), Color3.fromRGB(214, 246, 255)), 0.2)
			lit(beam(c, V(0.12, 0.41, 0.5), V(0.66, 0.41, -0.06), 0.08, fire), fire)
			K.hexPrism(c, left, 0.36, 1.36, { ice, iceDark, ice })
			K.hexPrism(c, right, 0.36, 1.36, { fire, fireDark, fire })
		else
			block(c, P(0, 0.15, 0) * A(0, 0.35, 0), V(1.1, 0.3, 0.9), rock)
			shiny(block(c, left, V(0.52, 1.36, 0.52), ice), 0.2)
			shiny(block(c, right, V(0.52, 1.36, 0.52), fire), 0.12)
		end
		lit(point(c, left * P(0, 0.72, 0), 0.46, ice), ice)
		lit(point(c, right * P(0, 0.72, 0), 0.46, fire), fire)
		move(lit(ball(c, heart, 0.5, fire), Color3.fromRGB(255, 190, 120)), "Pulse", nil, nil, 3.2, 0, 0.14)
		if c.Full then
			shiny(point(c, P(-0.66, 0.5, 0.36) * A(0.3, 0, 0.4), 0.3, ice), 0.2)
			shiny(point(c, P(0.64, 0.48, -0.32) * A(-0.2, 0, -0.4), 0.28, fire), 0.12)
			-- two ice shards one way round, two embers the other
			local hub = Vector3.new(0, 1.05, 0)
			move(lit(point(c, P(1.02, 1.55, 0.2) * A(0.3, 0.5, 0.2), 0.22, iceDark), ice), "Spin", hub, UP, 1.1)
			move(lit(point(c, P(-1.02, 1.3, -0.2) * A(-0.2, 0.3, 0.4), 0.18, iceDark), ice), "Spin", hub, UP, 1.1)
			move(lit(ball(c, Vector3.new(0.3, 0.75, 1.0), 0.15, fire), fire), "Spin", hub, UP, -1.4)
			move(lit(ball(c, Vector3.new(-0.3, 1.7, -1.0), 0.13, fire), fire), "Spin", hub, UP, -1.4)
		end
	end

	-- Deep Hollow: a pearly eye that looks round and blinks, held by curled golden claws
	-- on a base with a violet gem; two little eyes circle it.
	shapes.HollowEye = function(c: Ctx)
		local f = A(0, FACE, 0)
		local center = f * P(0, 1.05, 0)
		local eye = center.Position
		local d = 1.36
		local violet = Color3.fromRGB(190, 110, 255)
		shiny(ball(c, eye, d, "Main"), 0.18)
		local look = Vector3.new(0.25, 1, 0)
		move(cyl(c, center * P(0, 0, 0.62) * A(PI / 2, 0, 0), 0.08, 0.74, "Neon"), "Look", eye, look, 0.8, 0, 0.4)
		move(block(c, center * P(0, 0, 0.67), V(0.12, 0.46, 0.04), Color3.fromRGB(16, 10, 26)), "Look", eye, look, 0.8, 0, 0.4)
		shiny(cyl(c, P(0, 0.11, 0), 0.22, 0.9, GOLD_DARK), 0.2)
		if c.Full then
			move(cyl(c, center * P(0, 0, 0.6) * A(PI / 2, 0, 0), 0.06, 0.9, Color3.fromRGB(58, 26, 96)), "Look", eye, look, 0.8, 0, 0.4)
			move(ball(c, (center * P(0.17, 0.19, 0.66)).Position, 0.11, Color3.new(1, 1, 1)), "Look", eye, look, 0.8, 0, 0.4)
			-- the lid and its lashes: only there while it blinks
			local lid = shiny(cyl(c, center * P(0, 0, 0.64) * A(PI / 2, 0, 0), 0.1, 0.98, "Main"), 0.18)
			lid.Transparency = 1
			move(lid, "Lid", eye, look)
			local lash = block(c, center * P(0, -0.02, 0.71), V(0.86, 0.06, 0.04), Color3.fromRGB(40, 20, 60))
			lash.Transparency = 1
			move(lash, "Lid", eye, look)
			lit(point(c, f * P(0, 0.16, 0.44), 0.2, violet), violet)
			-- three claws, each a bar up and a tip curled over the eye
			for k = 0, 2 do
				local a = k * PI * 2 / 3 + 0.5
				local foot = (f * P(math.cos(a) * 0.38, 0.2, math.sin(a) * 0.38)).Position
				local knee = eye + f:VectorToWorldSpace(Vector3.new(math.cos(a) * 0.68, -0.3, math.sin(a) * 0.68))
				local tip = eye + f:VectorToWorldSpace(Vector3.new(math.cos(a) * 0.56, 0.26, math.sin(a) * 0.56))
				shiny(beam(c, foot, knee, 0.13, GOLD), 0.25)
				shiny(beam(c, knee, tip, 0.1, GOLD), 0.25)
			end
			-- two little eyes circling it (the violet dot always looks out)
			local orbit = Vector3.new(0.2, 1, 0.1)
			for _, side in { 1, -1 } do
				local at = eye + Vector3.new(side * 1.05, side * 0.2, side * 0.1)
				move(shiny(ball(c, at, 0.26, Color3.fromRGB(244, 240, 255)), 0.15), "Spin", eye, orbit, 0.7)
				move(lit(ball(c, at + Vector3.new(side * 0.12, 0, 0.04), 0.11, violet), violet), "Spin", eye, orbit, 0.7)
			end
		else
			shiny(beam(c, Vector3.new(-0.36, 0.2, 0), eye + Vector3.new(-0.6, -0.2, 0), 0.12, GOLD), 0.25)
			shiny(beam(c, Vector3.new(0.36, 0.2, 0), eye + Vector3.new(0.6, -0.2, 0), 0.12, GOLD), 0.25)
		end
	end

	-- Sunken Palace: a black pearl in an open clam, wearing a little golden crown; the clam
	-- breathes, a glimmer runs round the pearl's teal band and bubbles rise.
	shapes.TidecrownPearl = function(c: Ctx)
		local center = P(0, 1.0, 0)
		local shell = Color3.fromRGB(255, 150, 184)
		local teal = Color3.fromRGB(60, 240, 220)
		shiny(ball(c, center.Position, 1.2, "Main"), 0.42)
		local band = center * A(0.18, 0, 0.1)
		cyl(c, band, 0.07, 1.24, "Neon")
		shiny(cyl(c, P(0, 0.2, 0), 0.22, 1.9, shell), 0.25)
		local crown = P(0, 1.68, 0) * A(0.18, 0, 0.1)
		shiny(cyl(c, crown, 0.2, 0.62, GOLD), 0.3)
		local tips = if c.Full then 4 else 2
		for k = 0, tips - 1 do
			local a = k * PI * 2 / tips + 0.3
			shiny(point(c, crown * P(math.cos(a) * 0.25, 0.17, math.sin(a) * 0.25), 0.17, GOLD), 0.3)
		end
		if c.Full then
			move(
				lit(ball(c, (band * P(0.63, 0, 0)).Position, 0.13, Color3.fromRGB(200, 255, 245)), teal),
				"Spin",
				center.Position,
				band.UpVector,
				2.4
			)
			shiny(cyl(c, P(0, 0.31, 0), 0.05, 1.98, GOLD), 0.3)
			-- the upper shell, open behind the pearl, and its glowing inside: breathing on the hinge
			local hinge = Vector3.new(0, 0.32, -0.9)
			local lid = CFrame.new(hinge) * A(-0.95, 0, 0) * P(0, 0.08, 0.9)
			move(shiny(cyl(c, lid, 0.16, 1.9, shell), 0.25), "Swing", hinge, Vector3.xAxis, 1.3, 0, 0.1)
			move(lit(cyl(c, lid * P(0, -0.1, 0), 0.03, 1.55, teal), teal), "Swing", hinge, Vector3.xAxis, 1.3, 0, 0.1)
			lit(ball(c, (crown * P(0, 0.02, 0.31)).Position, 0.12, teal), teal)
			local bubble = Color3.fromRGB(190, 250, 255)
			for k, at in { Vector3.new(-0.85, 0.5, 0.35), Vector3.new(0.82, 0.7, 0.12), Vector3.new(0.22, 0.45, 0.88) } do
				local b = ball(c, at, 0.17 - k * 0.02, bubble)
				b.Transparency = 0.35
				move(b, "Rise", nil, UP, 0.45, k / 3, 1.5)
			end
		end
	end

	-- Stormglass Rift: a storm in a golden lantern: a glass jar between a gold base and lid,
	-- four gold bars and a handle; inside a flickering bolt round a breathing core,
	-- an arc jumps between two bars and two sparks circle it.
	shapes.CagedLightning = function(c: Ctx)
		local y0, y1 = 0.2, 1.62
		local yaw = A(0, 0.4, 0)
		shiny(block(c, P(0, 0.1, 0) * yaw, V(1.15, 0.2, 1.15), GOLD_DARK), 0.25)
		local glass = cyl(c, P(0, (y0 + y1) / 2, 0), y1 - y0, 1.0, "Glass")
		glass.Transparency = 0.55
		shiny(block(c, P(0, y1 + 0.08, 0) * yaw, V(1.15, 0.18, 1.15), GOLD), 0.3)
		local hub = Vector3.new(0, 0.95, 0)
		local bolt = {
			Vector3.new(0.14, 1.5, 0.05),
			Vector3.new(-0.16, 1.08, 0.08),
			Vector3.new(0.17, 0.9, -0.02),
			Vector3.new(-0.08, 0.36, 0.02),
		}
		local bolts = if c.Full then 3 else 2
		for k = 1, bolts do
			move(beam(c, bolt[k], bolt[k + 1], 0.13, "Neon"), "Flicker", hub, UP, 1, 0)
		end
		local core = ball(c, hub, 0.42, "NeonDark")
		core.Transparency = 0.4
		move(core, "Pulse", nil, nil, 5, 0, 0.15)
		if c.Full then
			local bars = {}
			for k = 0, 3 do
				local a = 0.4 + PI / 4 + k * PI / 2
				local x, z = math.cos(a) * 0.6, -math.sin(a) * 0.6
				bars[k + 1] = Vector3.new(x, 0, z)
				shiny(beam(c, Vector3.new(x, y0, z), Vector3.new(x, y1 + 0.02, z), 0.09, GOLD), 0.3)
			end
			shiny(beam(c, Vector3.new(-0.3, y1 + 0.17, 0), Vector3.new(0, y1 + 0.5, 0), 0.08, GOLD), 0.3)
			shiny(beam(c, Vector3.new(0, y1 + 0.5, 0), Vector3.new(0.3, y1 + 0.17, 0), 0.08, GOLD), 0.3)
			local zap = Color3.fromRGB(220, 250, 255)
			move(
				lit(beam(c, bars[1] + Vector3.new(0, 1.35, 0), bars[2] + Vector3.new(0, 1.22, 0), 0.05, zap), zap),
				"Flicker",
				hub,
				UP,
				1,
				0.5
			)
			local spark = Color3.fromRGB(255, 236, 90)
			move(lit(point(c, P(-0.98, 1.25, 0.25) * A(0.4, 0.2, 0.3), 0.16, GOLD), spark), "Spin", hub, UP, 2.2)
			move(lit(point(c, P(0.92, 0.62, -0.2) * A(-0.3, 0.5, 0.2), 0.14, GOLD), spark), "Spin", hub, UP, -1.8)
		end
	end

	-- Heartstone Core: Terra's whole heart, its crack mended with gold, beating on a gold
	-- stand; its wings flap and a ring of little worlds (grass, earth, sea, sand) circles it.
	shapes.HeartOfTerra = function(c: Ctx)
		local f = A(0, FACE, 0)
		local t = 0.56
		local yc = 0.92
		local hc = (f * P(0, yc + 0.12, 0)).Position
		if c.Full then
			shiny(block(c, f * P(0, 0.1, 0), V(0.62, 0.2, 0.44), GOLD_DARK), 0.25)
		end
		-- a heart = a square turned 45 degrees + two round lobes on its upper sides; it beats
		local beatSpeed, beatAmount = 0.9, 0.08
		move(block(c, f * P(0, yc, 0) * A(0, 0, PI / 4), V(1.0, 1.0, t), "Main"), "Beat", hc, UP, beatSpeed, 0, beatAmount)
		move(cyl(c, f * P(-0.354, yc + 0.354, 0) * A(PI / 2, 0, 0), t, 1.0, "Light"), "Beat", hc, UP, beatSpeed, 0, beatAmount)
		move(cyl(c, f * P(0.354, yc + 0.354, 0) * A(PI / 2, 0, 0), t, 1.0, "Main"), "Beat", hc, UP, beatSpeed, 0, beatAmount)
		-- the golden seam down its front
		local z = t / 2 + 0.03
		local seam = {
			(f * P(0.02, yc + 0.6, z)).Position,
			(f * P(0.14, yc + 0.22, z)).Position,
			(f * P(-0.1, yc - 0.16, z)).Position,
			(f * P(0.03, yc - 0.6, z)).Position,
		}
		local seams = if c.Full then 3 else 2
		for k = 1, seams do
			move(beam(c, seam[k], seam[k + 1], 0.08, "Neon"), "Beat", hc, UP, beatSpeed, 0, beatAmount)
		end
		if c.Full then
			local wing = Color3.fromRGB(255, 246, 224)
			local up = f:VectorToWorldSpace(UP)
			for _, side in { -1, 1 } do
				local root = f * P(side * 0.86, yc + 0.5, -0.08) * A(0, 0, side * -0.5)
				local hinge = (f * P(side * 0.6, yc + 0.45, -0.08)).Position
				move(
					shiny(wedge(c, root * P(0, 0.16, 0) * A(0, side * PI / 2, 0), V(0.62, 0.42, 0.08), wing), 0.15),
					"Swing",
					hinge,
					up,
					3,
					0,
					side * 0.32
				)
				move(
					lit(wedge(c, root * P(side * 0.14, -0.16, 0) * A(0, side * PI / 2, PI), V(0.42, 0.3, 0.06), GOLD), GOLD),
					"Swing",
					hinge,
					up,
					3,
					0,
					side * 0.32
				)
			end
			-- a ring of little worlds
			local ring = Vector3.new(0.25, 1, -0.15)
			local worlds = {
				Color3.fromRGB(96, 176, 84),
				Color3.fromRGB(134, 96, 64),
				Color3.fromRGB(64, 140, 214),
				Color3.fromRGB(226, 196, 130),
			}
			for k, color in worlds do
				local a = k * PI / 2 + 0.4
				local at = hc + Vector3.new(math.cos(a) * 1.12, math.sin(a * 2) * 0.12, math.sin(a) * 1.12)
				move(block(c, CFrame.new(at) * A(k * 0.7, k * 1.3, k * 0.4), V(0.26, 0.24, 0.26), color), "Spin", hc, ring, 0.55)
			end
		end
	end

	-- Any floor, one in a million: a newborn star: a black core with six rainbow spikes,
	-- each with a glowing tip, turning slowly; a rainbow disc whirls round it and a little
	-- gold star circles the other way.
	shapes.RainbowNova = function(c: Ctx)
		local center = P(0, 1.1, 0) * A(0.45, 0.35, 0.2)
		local cp = center.Position
		local starAxis = Vector3.new(0.3, 1, 0.2)
		shiny(ball(c, cp, 0.9, Color3.fromRGB(22, 16, 34)), 0.5)
		local dirs = {
			Vector3.new(0, 1, 0),
			Vector3.new(1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, -1, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, -1),
		}
		for k, dir in dirs do
			local color = SecretOreShapes.Rainbow[k]
			local out = center:VectorToWorldSpace(dir)
			if c.Full then
				-- a coloured spike (it keeps its colour under the bloom) and a glowing point on its end
				local spike = shiny(beam(c, cp, cp + out * 1.0, 0.2, color), 0.2)
				spike.CF = spike.CF * A(0, 0, PI / 4)
				move(spike, "Spin", cp, starAxis, 0.45)
				local tip = CFrame.lookAt(cp + out * 1.12, cp + out * 2) * A(-PI / 2, 0, 0)
				move(lit(point(c, tip, 0.3, color), color), "Spin", cp, starAxis, 0.45)
			else
				local spike = beam(c, cp, cp + out * 1.02, 0.3, color)
				spike.CF = spike.CF * A(0, 0, PI / 4)
				lit(spike, color)
			end
		end
		if c.Full then
			-- the whirling rainbow disc
			local disc = CFrame.new(cp) * A(0.95, 0, -0.3)
			for i, color in SecretOreShapes.Rainbow do
				local a = i * PI / 3
				local at = disc:PointToWorldSpace(Vector3.new(math.cos(a) * 0.74, 0, math.sin(a) * 0.74))
				local tangent = disc:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
				move(
					lit(block(c, CFrame.lookAt(at, at + tangent, disc.UpVector), V(0.08, 0.08, 0.42), color), color),
					"Spin",
					cp,
					disc.UpVector,
					2.2
				)
			end
			move(lit(point(c, P(1.15, 1.6, 0.3) * A(0.3, 0.2, 0.5), 0.22, GOLD), GOLD), "Spin", cp, UP, -1.1)
		end
	end
end

return SecretOreShapes
