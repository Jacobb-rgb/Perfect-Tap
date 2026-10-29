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

	Budgets as the tests count them: the clean ore is an invisible Body plus
	the recipe (at most 7 specs); the display recipe makes at most 11 specs
	(ItemBuilder adds 3 motes). The podium camera looks at the +Z side.
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

function SecretOreShapes.register(shapes: { [string]: (any) -> () }, kit: any)
	local K: Kit = kit
	local P, A, V = K.P, K.A, K.V
	local block, wedge, ball, cyl, point, beam = K.block, K.wedge, K.ball, K.cyl, K.point, K.beam

	-- Ember Caves: an ice crystal and a fire crystal crossed, white-hot where they meet.
	shapes.FrostflameCrystal = function(c: Ctx)
		local ice, iceDark = Color3.fromRGB(156, 230, 255), Color3.fromRGB(78, 156, 232)
		local fire, fireDark = Color3.fromRGB(255, 132, 44), Color3.fromRGB(214, 64, 22)
		local left = P(-0.24, 0.92, 0) * A(0, 0.2, 0.34)
		local right = P(0.24, 0.92, 0.02) * A(0, -0.2, -0.34)
		if c.Full then
			K.hexPrism(c, left, 0.36, 1.36, { ice, iceDark, ice })
			K.hexPrism(c, right, 0.36, 1.36, { fire, fireDark, fire })
		else
			shiny(block(c, left, V(0.52, 1.36, 0.52), ice), 0.2)
			shiny(block(c, right, V(0.52, 1.36, 0.52), fire), 0.12)
		end
		lit(point(c, left * P(0, 0.72, 0), 0.46, ice), ice)
		lit(point(c, right * P(0, 0.72, 0), 0.46, fire), fire)
		ball(c, Vector3.new(0, 0.92, 0.08), 0.46, "Neon")
		if c.Full then
			lit(point(c, P(-0.92, 1.72, 0.12) * A(0.3, 0.5, 0.2), 0.22, iceDark), ice)
			lit(point(c, P(0.94, 1.5, -0.08) * A(-0.2, 0.3, 0.4), 0.2, fireDark), fire)
		end
	end

	-- Deep Hollow: a pearly eye with a violet iris and a slit pupil, held by golden claws.
	shapes.HollowEye = function(c: Ctx)
		local f = A(0, FACE, 0)
		local center = f * P(0, 1.0, 0)
		local d = 1.36
		shiny(ball(c, center.Position, d, "Main"), 0.18)
		cyl(c, center * P(0, 0, 0.62) * A(PI / 2, 0, 0), 0.08, 0.74, "Neon")
		block(c, center * P(0, 0, 0.67), V(0.12, 0.46, 0.04), Color3.fromRGB(16, 10, 26))
		shiny(cyl(c, P(0, 0.11, 0), 0.22, 0.84, GOLD_DARK), 0.2)
		if c.Full then
			ball(c, (center * P(0.17, 0.19, 0.66)).Position, 0.11, Color3.new(1, 1, 1))
			-- three claws from the base's rim up to the eyeball's sides
			for k = 0, 2 do
				local a = k * PI * 2 / 3 + 0.5
				local foot = Vector3.new(math.cos(a) * 0.36, 0.2, math.sin(a) * 0.36)
				local tip = center.Position + Vector3.new(math.cos(a) * 0.62, -0.18, math.sin(a) * 0.62)
				shiny(beam(c, foot, tip, 0.12, GOLD), 0.25)
			end
			-- a dark ring around the iris: it reads as an eye from across the room
			cyl(c, center * P(0, 0, 0.6) * A(PI / 2, 0, 0), 0.06, 0.9, Color3.fromRGB(58, 26, 96))
		else
			shiny(beam(c, Vector3.new(-0.36, 0.2, 0), center.Position + Vector3.new(-0.6, -0.2, 0), 0.12, GOLD), 0.25)
			shiny(beam(c, Vector3.new(0.36, 0.2, 0), center.Position + Vector3.new(0.6, -0.2, 0), 0.12, GOLD), 0.25)
		end
	end

	-- Sunken Palace: a black pearl with a glowing teal sea inside, wearing a little golden crown.
	shapes.TidecrownPearl = function(c: Ctx)
		local center = P(0, 0.86, 0)
		shiny(ball(c, center.Position, 1.3, "Main"), 0.42)
		cyl(c, center * A(0.18, 0, 0.1), 0.07, 1.34, "Neon")
		local crown = P(0, 1.56, 0) * A(0.18, 0, 0.1)
		shiny(cyl(c, crown, 0.2, 0.62, GOLD), 0.3)
		local tips = if c.Full then 4 else 2
		for k = 0, tips - 1 do
			local a = k * PI * 2 / tips + 0.3
			shiny(point(c, crown * P(math.cos(a) * 0.25, 0.17, math.sin(a) * 0.25), 0.17, GOLD), 0.3)
		end
		shiny(cyl(c, P(0, 0.09, 0), 0.18, 0.92, GOLD_DARK), 0.2)
		if c.Full then
			lit(ball(c, (crown * P(0, 0.02, 0.31)).Position, 0.12, Color3.fromRGB(60, 240, 220)), Color3.fromRGB(60, 240, 220))
			local bubble = Color3.fromRGB(190, 250, 255)
			ball(c, Vector3.new(-0.86, 1.36, 0.2), 0.16, bubble).Transparency = 0.35
			ball(c, Vector3.new(0.8, 1.72, -0.1), 0.12, bubble).Transparency = 0.35
		end
	end

	-- Stormglass Rift: a glass cube on its corner with a bolt of lightning trapped inside.
	shapes.CagedLightning = function(c: Ctx)
		local cube = P(0, 1.0, 0) * A(0, 0.4, 0)
		local glass = point(c, cube, 1.15, "Glass")
		glass.Transparency = 0.55
		local bolt = {
			Vector3.new(0.12, 1.62, 0),
			Vector3.new(-0.16, 1.12, 0.04),
			Vector3.new(0.16, 0.96, -0.04),
			Vector3.new(-0.08, 0.42, 0),
		}
		for k = 1, 3 do
			beam(c, bolt[k], bolt[k + 1], 0.13, "Neon")
		end
		shiny(ball(c, Vector3.new(0, 1.96, 0), 0.24, GOLD), 0.3)
		shiny(ball(c, Vector3.new(0, 0.06, 0), 0.26, GOLD_DARK), 0.3)
		if c.Full then
			ball(c, Vector3.new(0, 1.0, 0), 0.36, "NeonDark").Transparency = 0.4
			lit(point(c, P(-0.92, 1.4, 0.2) * A(0.4, 0.2, 0.3), 0.16, GOLD), Color3.fromRGB(255, 236, 90))
			lit(point(c, P(0.86, 0.7, -0.16) * A(-0.3, 0.5, 0.2), 0.14, GOLD), Color3.fromRGB(255, 236, 90))
		end
	end

	-- Heartstone Core: Terra's whole heart, its crack mended with gold, with two small wings.
	shapes.HeartOfTerra = function(c: Ctx)
		local f = A(0, FACE, 0)
		local t = 0.56
		-- a heart = a square turned 45 degrees + two round lobes on its upper sides
		local yc = 0.82
		block(c, f * P(0, yc, 0) * A(0, 0, PI / 4), V(1.0, 1.0, t), "Main")
		cyl(c, f * P(-0.354, yc + 0.354, 0) * A(PI / 2, 0, 0), t, 1.0, "Light")
		cyl(c, f * P(0.354, yc + 0.354, 0) * A(PI / 2, 0, 0), t, 1.0, "Main")
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
			beam(c, seam[k], seam[k + 1], 0.08, "Neon")
		end
		if c.Full then
			local wing = Color3.fromRGB(255, 246, 224)
			for _, side in { -1, 1 } do
				local root = f * P(side * 0.86, yc + 0.5, -0.08) * A(0, 0, side * -0.5)
				shiny(wedge(c, root * P(0, 0.16, 0) * A(0, side * PI / 2, 0), V(0.62, 0.42, 0.08), wing), 0.15)
				lit(wedge(c, root * P(side * 0.14, -0.16, 0) * A(0, side * PI / 2, PI), V(0.42, 0.3, 0.06), GOLD), GOLD)
			end
		end
	end

	-- Any floor, one in a million: a black star core with six rainbow spikes (four small ones on the display).
	shapes.RainbowNova = function(c: Ctx)
		local center = P(0, 1.06, 0) * A(0.45, 0.35, 0.2)
		shiny(ball(c, center.Position, 0.78, Color3.fromRGB(22, 16, 34)), 0.5)
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
			local tip = center.Position + center:VectorToWorldSpace(dir) * 1.02
			local spike = beam(c, center.Position, tip, 0.3, color)
			spike.CF = spike.CF * A(0, 0, PI / 4)
			lit(spike, color)
		end
		if c.Full then
			local diagonals = {
				Vector3.new(1, 1, 1),
				Vector3.new(-1, 1, -1),
				Vector3.new(1, -1, -1),
				Vector3.new(-1, -1, 1),
			}
			for k, dir in diagonals do
				local color = SecretOreShapes.Rainbow[k]:Lerp(Color3.new(1, 1, 1), 0.45)
				local tip = center.Position + center:VectorToWorldSpace(dir.Unit) * 0.7
				local spike = beam(c, center.Position, tip, 0.16, color)
				spike.CF = spike.CF * A(0, 0, PI / 4)
				lit(spike, color)
			end
		end
	end
end

return SecretOreShapes
