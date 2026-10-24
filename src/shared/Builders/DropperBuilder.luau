--[[
	The droppers (Config/DropperConfig) like the owner's picture
	docs/art/droppers_concept.webp (2026-10-21), in the glowing block style of
	the first concept: a stepped block pedestal with a glowing step, a leaning
	two-block column with a ladder of glowing slot blocks on its side, a long
	block arm on top with a glowing top edge, and the spout under the arm's end
	that drops the dropper's ores in a beam of light onto a glowing pad.
	Crystals grow around the pedestal; each dropper is made of its own stuff:

	  BasicDropper       TOXIC: dark steel with glowing green slime caps, slime
	                     drips, bubbles, a toxic barrel and hazard stripes
	  BlueDropper        FROST: ice-blue blocks with snow caps, icicles, snow heaps
	                     and floating snowflakes, cyan glow
	  RedDropper         LAVA: black stone with lava cracks, lava flowing down the
	                     column into a pool, orange glowing spots, red glow
	  PurpleDropper      CRYSTAL: purple stone, crystals sticking out everywhere
	  GoldDropper        HEAVEN: white marble with gold rims, a golden halo, white
	                     wings on the column, clouds at the foot, sparkles
	  RainbowDropper     black stone, every slot another colour, rainbow crystals,
	                     a block rainbow behind it
	  DarkMatterDropper  starry black blocks with violet cracks, a spiral on the
	                     column, a swirl ring and black orbs around it
	(owner 2026-10-24: back to the blocks, themes "like a Heaven Dropper")

	build(id, cf, lite?, onBelt?) -> Model (anchored; origin = the middle of its
	stage's bottom; front = +Z; the arm reaches toward -X and drops onto the pad
	there; onBelt: the plot's machine, the arm over the belt cell beside it).
	`lite` (the DROPPERS shop's showroom, phones): plain blocks in place of
	the framed pedestal, column and arm blocks, two crystal clusters in
	place of four, one ore on the pad, and every ore a glowing gem block in
	its colour in place of the ore model.
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local ItemBuilder = require(script.Parent.ItemBuilder)
local DropperConfig = require(Shared.Config.DropperConfig)
local Format = require(Shared.Util.Format)
local OreData = require(Shared.Config.OreData)

local DropperBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

export type Style = {
	Face: Color3,
	Rim: Color3,
	Glow: { Color3 }, -- glows (more than one: they take turns, the rainbow)
	Crystal: { Color3 },
	Kind: string,
	Trim: { Color3 }, -- (the shop / previews)
}

local RAINBOW = { rgb(255, 70, 70), rgb(255, 160, 40), rgb(255, 230, 60), rgb(70, 230, 90), rgb(50, 170, 255), rgb(150, 90, 255) }

local function style(face: Color3, rim: Color3, glow: { Color3 }, crystal: { Color3 }, kind: string): Style
	return { Face = face, Rim = rim, Glow = glow, Crystal = crystal, Kind = kind, Trim = { glow[1] } }
end

DropperBuilder.Styles = {
	BasicDropper = style(rgb(78, 88, 80), rgb(40, 46, 42), { rgb(120, 255, 60) }, { rgb(110, 240, 60), rgb(200, 255, 80) }, "toxic"),
	BlueDropper = style(rgb(150, 205, 245), rgb(70, 120, 190), { rgb(120, 230, 255) }, { rgb(170, 235, 255), rgb(225, 248, 255) }, "ice"),
	RedDropper = style(rgb(78, 60, 58), rgb(38, 26, 26), { rgb(255, 70, 30) }, { rgb(255, 60, 50) }, "lava"),
	PurpleDropper = style(
		rgb(104, 64, 160),
		rgb(62, 36, 104),
		{ rgb(205, 90, 255), rgb(255, 110, 220) },
		{ rgb(140, 50, 255), rgb(225, 50, 180), rgb(60, 110, 255) }, -- (deep: the neon keeps the hue)
		"crystal"
	),
	GoldDropper = style(
		rgb(246, 244, 236),
		rgb(224, 176, 58),
		{ rgb(255, 222, 120), rgb(255, 248, 215) },
		{ rgb(255, 236, 150), rgb(255, 255, 255) },
		"heaven"
	),
	RainbowDropper = style(rgb(62, 62, 76), rgb(30, 30, 40), RAINBOW, RAINBOW, "rainbow"),
	DarkMatterDropper = style(rgb(46, 32, 78), rgb(18, 12, 34), { rgb(175, 80, 255) }, { rgb(140, 60, 255) }, "dark"),
} :: { [string]: Style }

-- Sizes (studs).
DropperBuilder.Width = 9.4 -- the stage along x (before Scale)
DropperBuilder.Depth = 7 -- the stage along z
DropperBuilder.Height = 10.6 -- stage bottom -> arm top (before Scale)

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false, CastShadow = false, CanCollide = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function glowOf(st: Style, i: number): Color3
	return st.Glow[(i - 1) % #st.Glow + 1]
end

local function crystalOf(st: Style, i: number): Color3
	return st.Crystal[(i - 1) % #st.Crystal + 1]
end

-- a crystal: a glassy body in the colour with a glowing tip
local function crystal(parent: Instance, cf: CFrame, size: number, color: Color3, tip: boolean)
	Geo.block(parent, cf, Vector3.new(0.5, 1.3, 0.5) * size, color, if tip then NEON else GLASS, decor())
end

local function cluster(parent: Instance, cf: CFrame, st: Style, seed: number, n: number)
	for i = 1, n do
		local a = i * 2.4 + seed
		local lean = CFrame.Angles(math.sin(a) * 0.45, a, math.cos(a) * 0.45)
		crystal(
			parent,
			cf * CFrame.new(math.cos(a) * 0.6, 0.5, math.sin(a) * 0.5) * lean,
			0.8 + ((i + seed) % 3) * 0.3,
			crystalOf(st, i + seed),
			i == 1
		)
	end
end

-- On a plot (build's `onBelt`, owner 2026-10-24: "the spout points over the
-- belt and the ore falls right onto it"): the body stands to one side of the
-- stage (BeltShift along z) and the arm reaches out over the belt cell in
-- front, its nozzle at BeltSpoutX right over that cell's middle, with a thin
-- light beam down to BeltTop; no pad. MachineBuilder turns it so the arm
-- points to the machine's front (Grid.outputLocal: the nozzle, DropperConfig.SpoutHeight).
DropperBuilder.BeltShift = -1.95
DropperBuilder.BeltSpoutX = -7.06
DropperBuilder.BeltTop = 1.0 -- studs: a belt's top (the beam's foot)

-- the geometry is built at 1 and then scaled up by Scale (the ores keep their real size)
DropperBuilder.Scale = 0.85 -- a 2 x 2 cell machine like the others (9.4 x 7 -> 8 x 6 studs, ~9 tall)
DropperBuilder.Cells = { 2, 2 }

local function ore(parent: Instance, id: string, grade: string, cf: CFrame, seed: number)
	local model = ItemBuilder.buildLight({ Kind = "Clean", OreId = id, Grade = grade }, cf, seed)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.Parent = parent
end

-- a zigzag crack of thin glowing bars on a face (+Z of `cf`)
local function crack(parent: Instance, cf: CFrame, length: number, color: Color3, seed: number)
	local y = length / 2
	local x = 0
	local steps = 3
	for i = 1, steps do
		local dx = (if (i + seed) % 2 == 0 then 1 else -1) * 0.35
		local seg = length / steps
		local mid = Vector3.new(x + dx / 2, y - seg / 2, 0)
		local angle = math.atan2(dx, seg)
		Geo.block(parent, cf * CFrame.new(mid) * CFrame.Angles(0, 0, angle), Vector3.new(0.15, seg + 0.05, 0.04), color, NEON, decor())
		x += dx
		y -= seg
	end
end

local SPIRAL = {
	".####.",
	"#....#",
	"#.##.#",
	"#.#..#",
	"#.####",
	".#....",
}

function DropperBuilder.build(id: string, cf: CFrame, lite: boolean?, onBelt: boolean?): Model
	local dropper = DropperConfig.ById[id]
	local st = DropperBuilder.Styles[id]
	assert(dropper and st, "Unknown dropper " .. tostring(id))
	local model = Instance.new("Model")
	model.Name = id
	-- (onBelt: the machine on a plot, see the header: the body moves to one
	-- side of the stage, the arm reaches out over the belt cell in front)
	local DZ = if onBelt then DropperBuilder.BeltShift else 0
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z + DZ)
	end
	local function at0(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function cube(c: CFrame, size: Vector3, face: Color3?, rim: Color3?, mode: string?): Part
		return BlockKit.cube(model, c, size, face or st.Face, rim or st.Rim, mode)
	end
	local K = DropperBuilder.Scale
	local SIDE = if lite then "flat" else "side" -- (lite: one block per framed cube)
	type Drop = { Id: string, At: CFrame, Seed: number }
	local ores: { Drop } = {}
	local function dropOre(oreId: string, x: number, y: number, z: number, turn: CFrame, seed: number)
		table.insert(ores, { Id = oreId, At = cf * CFrame.new(x * K, y * K, (z + DZ) * K) * turn, Seed = seed })
	end
	local glow = glowOf(st, 1)
	local W = DropperBuilder.Width
	local D = if onBelt then DropperBuilder.Width else DropperBuilder.Depth
	local DARK, DARK_RIM = rgb(26, 24, 38), rgb(14, 12, 22)
	-- the pedestal's middle, the spout's x (onBelt: over the belt cell in front),
	-- px: where the pad and the decor by it stand
	local px = -2.7
	local bx, sx = 1.0, if onBelt then DropperBuilder.BeltSpoutX else px
	local stageH = 0.5

	---------------------------------------------------------------- the stage, its glowing front edge and the price
	cube(at0(0, stageH / 2, 0), Vector3.new(W, stageH, D), DARK, DARK_RIM, "flat")
	Geo.block(model, at0(0, stageH + 0.01, D / 2 - 0.2), Vector3.new(W - 0.2, 0.04, 0.16), glow, NEON, decor())
	BlockKit.text(
		model,
		at0(0, stageH / 2, D / 2 + 0.05),
		Vector3.new(4.2, 0.46, 0.06),
		Format.money(dropper.Price),
		rgb(255, 230, 120),
		DARK,
		nil,
		Enum.Font.LuckiestGuy
	)

	---------------------------------------------------------------- the stepped pedestal and its glowing step
	local p1y = stageH + 0.8
	cube(at(bx, p1y, -0.2), Vector3.new(5.0, 1.6, 4.6), nil, nil, SIDE)
	local p2y = stageH + 1.6 + 0.6
	cube(at(bx + 0.3, p2y, -0.4), Vector3.new(3.8, 1.2, 3.6), nil, nil, SIDE)
	cube(at(bx - 0.4, stageH + 0.4, 2.55), Vector3.new(2.6, 0.8, 0.9), nil, nil, "flat")
	Geo.block(model, at(bx - 0.4, stageH + 0.42, 3.02), Vector3.new(2.2, 0.22, 0.05), glowOf(st, 2), NEON, decor())
	Geo.block(model, at(bx, stageH + 1.6, 2.12), Vector3.new(4.6, 0.12, 0.06), glowOf(st, 3), NEON, decor())

	---------------------------------------------------------------- the leaning column and the ladder of slot blocks
	local lowerY = p2y + 0.6 + 1.5
	cube(at(bx + 0.1, lowerY, -0.4) * CFrame.Angles(0, 0, 0.06), Vector3.new(2.3, 3.0, 2.5), nil, nil, SIDE)
	local upperY = lowerY + 2.9
	cube(at(bx - 0.15, upperY, -0.4) * CFrame.Angles(0, 0, 0.13), Vector3.new(2.1, 2.9, 2.3), nil, nil, SIDE)
	for i = 1, 4 do
		local ly = p2y + 0.2 + i * 1.25
		local lx = bx + 1.55 - (i - 1) * 0.12
		cube(at(lx, ly, -0.3 + (i % 2) * 0.12), Vector3.new(1.0, 1.15, 1.9), nil, nil, "flat")
		Geo.block(model, at(lx, ly, 0.68 + (i % 2) * 0.12), Vector3.new(0.62, 0.28, 0.05), glowOf(st, i + 1), NEON, decor())
	end

	---------------------------------------------------------------- the arm and its glowing edges (its top: the rounded top below)
	local armY = upperY + 1.45 + 0.9
	local armRight, armLeft = bx + 1.6, sx - 1.0
	local armLen = armRight - armLeft
	cube(at((armRight + armLeft) / 2, armY, -0.4), Vector3.new(armLen, 1.8, 2.6), nil, nil, SIDE)
	Geo.block(
		model,
		at((armRight + armLeft) / 2 - 0.4, armY - 0.92, 0.82),
		Vector3.new(armLen - 1.2, 0.1, 0.1),
		glowOf(st, 3),
		NEON,
		decor()
	)
	Geo.block(model, at((armRight + armLeft) / 2, armY + 0.92, 0.82), Vector3.new(armLen - 0.2, 0.12, 0.1), glow, NEON, decor())
	-- the name on the arm's front
	BlockKit.text(
		model,
		at(armLeft + armLen / 2 - 0.3, armY, 0.92),
		Vector3.new(armLen - 1.6, 1.0, 0.06),
		string.upper(dropper.Name),
		Color3.new(1, 1, 1),
		DARK,
		glow,
		Enum.Font.LuckiestGuy
	)

	---------------------------------------------------------------- the spout, its light beam, the falling ores and the pad
	local spoutY = armY - 0.9 - 0.45
	cube(at(sx, spoutY, -0.4), Vector3.new(1.7, 0.9, 1.7), nil, nil, "flat")
	Geo.block(model, at(sx, spoutY - 0.47, -0.4), Vector3.new(1.2, 0.06, 1.2), glow, NEON, decor())
	local lamp = Geo.block(model, at(sx, spoutY - 0.8, -0.4), Vector3.new(0.2, 0.2, 0.2), glow, NEON, decor({ Transparency = 1 }))
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Brightness = 2.2
	light.Range = 14
	light.Parent = lamp
	local padY = stageH + 0.35
	local beamTop = spoutY - 0.5
	if onBelt then
		-- a thin light beam from the nozzle down to the belt
		local bottom = DropperBuilder.BeltTop / K
		local beam = Geo.block(
			model,
			at(sx, (beamTop + bottom) / 2, -0.4),
			Vector3.new(0.7, beamTop - bottom, 0.7),
			glow,
			NEON,
			decor({ Transparency = 0.82 })
		)
		beam.Name = "Beam"
	else
		Geo.block(model, at(sx, beamTop - 0.5, -0.4), Vector3.new(1.1, 1.0, 1.1), glow, NEON, decor({ Transparency = 0.75 }))
		for i = 1, 2 do
			local oreId = dropper.Ores[(i - 1) % #dropper.Ores + 1]
			dropOre(oreId, sx + (i - 1.5) * 0.2, beamTop - 0.6 - i * 1.9, -0.4 + (i % 2) * 0.15, CFrame.Angles(i, i * 2, 0.4), 30 + i)
		end
		cube(at(sx - 0.1, padY, 0.2), Vector3.new(2.8, 0.7, 3.4), DARK, DARK_RIM, "flat")
		for _, side in { -1, 1 } do
			Geo.block(model, at(sx - 0.1 + side * 1.36, padY, 0.2), Vector3.new(0.1, 0.72, 3.42), glow, NEON, decor())
			Geo.block(model, at(sx - 0.1, padY, 0.2 + side * 1.66), Vector3.new(2.82, 0.72, 0.1), glow, NEON, decor())
		end
		for i, p in { Vector3.new(-0.6, 0, 0.1), Vector3.new(0.4, 0, 1.0), Vector3.new(0, 0.25, 0.4) } do
			if lite and i > 1 then
				break
			end
			local oreId = dropper.Ores[(i + 1) % #dropper.Ores + 1]
			dropOre(oreId, sx + p.X, padY + 0.6 + p.Y, -0.4 + p.Z, CFrame.Angles(0.3, i * 1.7, 0.2), 40 + i)
		end
	end

	---------------------------------------------------------------- crystals around the pedestal and the pad
	cluster(model, at(bx + 2.6, stageH, 2.0), st, 1, 4)
	cluster(model, at(if onBelt then px - 0.7 else sx - 1.4, stageH, 2.2), st, 2, 3)
	if not lite then
		cluster(model, at(bx - 2.3, stageH, 1.9), st, 3, 3)
		cluster(model, at(bx + 2.4, stageH, if onBelt then -1.5 else -2.4), st, 5, 2)
	end

	---------------------------------------------------------------- what each one is made of
	local kind = st.Kind
	local armTop = armY + 0.9 -- (a slime or snow cap raises it: the rounded top sits on it)
	-- (glowing bits round the blocks: a helper for the spots, flakes and crystals below)
	local function spot(x: number, y: number, z: number, size: Vector3, color: Color3, turn: CFrame?)
		Geo.block(model, at(x, y, z) * (turn or CFrame.new()), size, color, NEON, decor())
	end
	if kind == "toxic" then
		-- toxic slime on the steps and the arm, slime drips, bubbles, a toxic barrel, hazard stripes
		local SLIME, SLIME_RIM = rgb(130, 255, 70), rgb(70, 170, 40)
		cube(at(bx, stageH + 1.6 + 0.12, -0.2), Vector3.new(5.02, 0.3, 4.62), SLIME, SLIME_RIM, "side")
		cube(at((armRight + armLeft) / 2, armY + 0.98, -0.4), Vector3.new(armLen + 0.02, 0.3, 2.62), SLIME, SLIME_RIM, "side")
		armTop = armY + 1.13
		local drips = if lite then 2 else 4
		for i = 1, drips do
			local v = ({
				Vector3.new(bx - 1.0, lowerY + 0.3, 0.86),
				Vector3.new(armLeft + 1.6, armY - 0.75, 0.92),
				Vector3.new(bx + 0.5, upperY - 0.2, 0.8),
				Vector3.new(armRight - 1.0, armY - 0.9, 0.92),
			})[i]
			spot(v.X, v.Y, v.Z, Vector3.new(0.3, 1.2 + (i % 2) * 0.7, 0.06), SLIME)
		end
		if not lite then
			-- the barrel: a drum with a glowing band and a glowing lid
			local barrel = at(bx + 3.1, stageH + 0.9, 2.0)
			Geo.cylinder(model, barrel.Position, 1.8, 1.3, rgb(220, 190, 40), PLASTIC, decor())
			Geo.cylinder(model, (barrel * CFrame.new(0, 0.2, 0)).Position, 0.3, 1.36, rgb(30, 30, 30), PLASTIC, decor())
			Geo.cylinder(model, (barrel * CFrame.new(0, 0.92, 0)).Position, 0.06, 1.1, SLIME, NEON, decor())
			for k = 1, 3 do
				Geo.ball(
					model,
					at(px - 0.8 + k * 0.5, stageH + 0.6 + k * 0.35, 1.4 - k * 0.3).Position,
					0.25 + k * 0.08,
					SLIME,
					NEON,
					decor()
				)
			end
			-- hazard stripes on the stage's front
			for k = 0, 3 do
				Geo.block(
					model,
					at(bx - 1.6 + k * 0.7, stageH + 0.02, 3.2) * CFrame.Angles(0, math.rad(35), 0),
					Vector3.new(0.25, 0.03, 0.9),
					rgb(255, 210, 40),
					PLASTIC,
					decor()
				)
			end
		end
	elseif kind == "lava" then
		local LAVA = rgb(255, 90, 20)
		local SPOT = rgb(255, 150, 30)
		crack(model, at(bx - 0.6, p1y, 2.11), 1.4, LAVA, 1)
		crack(model, at(bx + 0.1, upperY, 0.76), 2.4, LAVA, 4)
		if not lite then
			crack(model, at(bx + 1.2, p1y, 2.11), 1.4, LAVA, 2)
			crack(model, at(bx - 0.2, lowerY, 0.86), 2.6, LAVA, 3)
		end
		-- lava flowing from the arm down the column and the steps into a pool
		local flow = {
			{ X = bx - 0.85, Y = upperY, Z = 0.85, H = 2.6 },
			{ X = bx - 0.95, Y = lowerY - 0.2, Z = 0.95, H = 2.8 },
			{ X = bx - 1.9, Y = stageH + 1.1, Z = 2.12, H = 1.2 },
		}
		for k, f in flow do
			if not lite or k ~= 2 then
				spot(f.X, f.Y, f.Z, Vector3.new(0.38, f.H, 0.07), LAVA)
			end
		end
		spot(bx - 1.9, stageH + 0.03, 2.9, Vector3.new(1.8, 0.05, 1.2), LAVA)
		-- orange glowing spots on the blocks
		local spots = if lite then 3 else 8
		for i = 1, spots do
			local face = ({
				Vector3.new(bx + 0.7, p1y + 0.3, 2.12),
				Vector3.new(bx + 1.6, p2y, 1.43),
				Vector3.new(bx + 0.6, lowerY + 0.9, 0.87),
				Vector3.new(bx - 0.4, upperY + 0.8, 0.77),
				Vector3.new(armLeft + 0.9, armY + 0.2, 0.92),
				Vector3.new(armRight - 0.6, armY - 0.3, 0.92),
				Vector3.new(bx - 1.4, p1y - 0.3, 2.12),
				Vector3.new(bx + 0.9, upperY - 0.9, 0.77),
			})[i]
			local sz = 0.22 + (i % 3) * 0.1
			spot(face.X, face.Y, face.Z, Vector3.new(sz, sz, 0.05), SPOT)
		end
	elseif kind == "ice" then
		-- snow caps on the steps and the arm, icicles under the arm, snow heaps, snowflakes
		local SNOW, SNOW_RIM = rgb(250, 252, 255), rgb(190, 220, 245)
		cube(at(bx, stageH + 1.6 + 0.12, -0.2), Vector3.new(5.02, 0.3, 4.62), SNOW, SNOW_RIM, "side")
		cube(at((armRight + armLeft) / 2, armY + 0.98, -0.4), Vector3.new(armLen + 0.02, 0.3, 2.62), SNOW, SNOW_RIM, "side")
		armTop = armY + 1.13
		if not lite then
			cube(at(bx + 0.3, p2y + 0.62, -0.4), Vector3.new(3.82, 0.3, 3.62), SNOW, SNOW_RIM, "side")
			-- snow heaps on the stage
			for _, h in { Vector3.new(bx + 2.6, 0, 2.3), Vector3.new(px - 1.0, 0, 2.5), Vector3.new(bx + 2.6, 0, -1.6) } do
				Geo.block(model, at(h.X, stageH + 0.25, h.Z), Vector3.new(1.5, 0.5, 1.1), SNOW, PLASTIC, decor())
				Geo.block(model, at(h.X + 0.2, stageH + 0.6, h.Z), Vector3.new(0.9, 0.4, 0.7), SNOW, PLASTIC, decor())
			end
		end
		local icicles = if lite then 2 else 4
		for i = 1, icicles do
			local ix = armLeft + 1.6 + (i - 1) * (armLen - 2.6) / math.max(1, icicles - 1)
			local len = 0.7 + (i % 2) * 0.5
			Geo.block(
				model,
				at(ix, armY - 0.9 - len / 2, 0.75),
				Vector3.new(0.26, len, 0.26),
				rgb(200, 240, 255),
				NEON,
				decor({ Transparency = 0.2 })
			)
		end
		-- snowflakes floating round it: three crossed glowing bars each
		local flakes = if lite then 1 else 5
		for i = 1, flakes do
			local a = i * 1.9
			local c = Vector3.new(bx - 0.5 + math.cos(a) * 3.4, stageH + 3 + (i % 3) * 1.8, math.sin(a) * 2.6)
			for k = 0, 2 do
				spot(c.X, c.Y, c.Z, Vector3.new(0.9, 0.12, 0.06), rgb(235, 250, 255), CFrame.Angles(0, a, k * math.pi / 3))
			end
		end
	elseif kind == "crystal" then
		-- big pointed crystals sticking out everywhere (a glowing prism with a
		-- pointed tip, growing along its frame's up from `base`, leaning out)
		local function spike(base: CFrame, len: number, w: number, color: Color3)
			local bodyH = len * 0.75
			Geo.block(model, base * CFrame.new(0, bodyH / 2, 0), Vector3.new(w, bodyH, w), color, NEON, decor())
			local tipH = len - bodyH
			local tip = base * CFrame.new(0, bodyH + tipH / 2, 0)
			local light = color:Lerp(Color3.new(1, 1, 1), 0.2)
			Geo.wedge(model, tip * CFrame.new(0, 0, -w / 4), Vector3.new(w, tipH, w / 2), light, NEON, decor())
			Geo.wedge(
				model,
				tip * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, math.pi, 0),
				Vector3.new(w, tipH, w / 2),
				color,
				NEON,
				decor()
			)
		end
		-- (x, y, z: where it grows from; out: the lean (radians) about z / x; len, w)
		local spikes = {
			{ bx + 0.6, armY + 0.9, -0.4, -0.35, 0.2, 2.6, 0.75 },
			{ armLeft + 1.2, armY + 0.9, -0.5, 0.45, -0.1, 2.0, 0.6 },
			{ bx + 1.4, armY + 0.6, -1.2, -0.9, -0.5, 1.6, 0.5 },
			{ bx + 1.3, lowerY + 0.5, -0.4, -1.25, 0.1, 1.9, 0.6 },
			{ bx - 1.1, upperY + 0.4, -0.6, 1.2, -0.2, 1.7, 0.55 },
			{ bx + 0.3, lowerY - 0.3, 0.9, 0.2, 1.25, 1.6, 0.5 },
			{ bx - 0.4, upperY + 0.9, 0.7, -0.3, 1.1, 1.4, 0.45 },
			{ bx + 1.8, p1y + 0.8, -1.0, -0.5, -0.3, 2.0, 0.6 },
			{ bx - 2.3, p1y + 0.8, 1.2, 0.7, 0.4, 1.8, 0.55 },
			{ px + 1.4, stageH, -1.6, 0.3, -0.3, 1.8, 0.55 },
			{ bx + 2.3, stageH, 2.0, -0.3, 0.3, 1.6, 0.5 },
			{ armLeft + 0.2, armY + 0.2, 0.7, 0.8, 0.9, 1.4, 0.45 },
		}
		local count = if lite then 5 else #spikes
		for k = 1, count do
			local c = spikes[k]
			spike(at(c[1], c[2], c[3]) * CFrame.Angles(c[5], 0, c[4]), c[6] * 1.3, c[7] * 1.15, crystalOf(st, k))
		end
	elseif kind == "heaven" then
		-- a golden halo over the arm, white wings on the column, clouds at the foot, sparkles
		local GOLD = rgb(255, 214, 90)
		local hy = armY + 2.8 -- (over the arm's rounded top)
		local hx = (armRight + armLeft) / 2 + 0.6
		local bars = if lite then 4 else 8
		for k = 0, bars - 1 do
			local a = k / bars * math.pi * 2
			local radius = 1.5
			local len = 2 * radius * math.tan(math.pi / bars) + 0.05
			Geo.block(
				model,
				at(hx + math.cos(a) * radius, hy, -0.4 + math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0),
				Vector3.new(len, 0.22, 0.22),
				GOLD,
				NEON,
				decor()
			)
		end
		local feathers = if lite then 1 else 3
		for _, side in { -1, 1 } do
			for f = 1, feathers do
				Geo.block(
					model,
					at(bx + 0.1 + side * (1.3 + f * 0.45), upperY + 0.6 - f * 0.45, -0.6) * CFrame.Angles(0, 0, side * math.rad(25)),
					Vector3.new(0.9 + f * 0.25, 0.42, 0.3),
					Color3.new(1, 1, 1),
					PLASTIC,
					decor()
				)
			end
		end
		if not lite then
			for _, c in { Vector3.new(bx - 2.6, 0, 2.4), Vector3.new(bx + 2.5, 0, 1.0), Vector3.new(px - 1.0, 0, -2.0) } do
				Geo.block(model, at(c.X, stageH + 0.35, c.Z), Vector3.new(1.4, 0.7, 1.0), rgb(250, 250, 255), PLASTIC, decor())
				Geo.block(model, at(c.X + 0.5, stageH + 0.75, c.Z - 0.1), Vector3.new(0.9, 0.6, 0.8), rgb(235, 240, 255), PLASTIC, decor())
			end
		end
		local sparkles = if lite then 3 else 6
		for i = 1, sparkles do
			local a = i * 1.7
			Geo.block(
				model,
				at(bx + math.cos(a) * 3.2, stageH + 2 + (i % 4) * 1.6, math.sin(a) * 2.2) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(0.22, 0.22, 0.05),
				rgb(255, 250, 210),
				NEON,
				decor()
			)
		end
	elseif kind == "gold" then
		for i = 1, 8 do
			local a = i * 1.7
			Geo.block(
				model,
				at(bx + math.cos(a) * 3.2, stageH + 2 + (i % 4) * 1.6, math.sin(a) * 2.2) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(0.22, 0.22, 0.05),
				rgb(255, 250, 210),
				NEON,
				decor()
			)
		end
	elseif kind == "rainbow" then
		-- a block rainbow behind it
		for band = 1, 5, 4 do
			local r = 4.6 - band * 0.3
			for k = 0, 5 do
				local a = k / 5 * math.pi
				Geo.block(
					model,
					at(math.cos(a) * r, stageH + 1 + math.sin(a) * r, if onBelt then -2.4 else -3.6),
					Vector3.new(0.62, 0.62, 0.3),
					RAINBOW[band],
					PLASTIC,
					decor()
				)
			end
		end
	elseif kind == "dark" then
		-- stars on the blocks, violet cracks, the spiral, the swirl ring and the orbs
		for i = 1, 4 do
			local a = i * 2.1
			Geo.block(
				model,
				at(bx + math.cos(a) * 2.2, stageH + 0.6 + (i % 6) * 1.25, 2.13),
				Vector3.new(0.12, 0.12, 0.04),
				rgb(240, 230, 255),
				NEON,
				decor()
			)
		end
		crack(model, at(bx - 0.9, p1y, 2.11), 1.4, glow, 1)
		crack(model, at(bx + 0.5, lowerY, 0.86), 2.6, glow, 2)
		BlockKit.pixelArt(model, at(bx - 0.15, upperY, 0.82) * CFrame.Angles(0, 0, 0.13), SPIRAL, 0.26, { ["#"] = glow }, 0.05, NEON)
		for k = 1, 18 do
			local a = k / 18 * math.pi * 2
			if k % 3 == 0 then
				Geo.block(
					model,
					at(bx + math.cos(a) * 3.6, stageH + 1.2 + math.sin(a * 2) * 0.25, -0.2 + math.sin(a) * (if onBelt then 2.2 else 3.0))
						* CFrame.Angles(0, -a, 0),
					Vector3.new(0.12, 0.08, 1.1),
					glow,
					NEON,
					decor()
				)
			end
		end
		for i, p in
			{
				Vector3.new(bx + 2.9, 5.0, 1.0),
				Vector3.new(bx - 2.4, 6.2, 0.8),
				Vector3.new(px - 1.2, 7.0, -1.8),
			}
		do
			Geo.ball(model, (at(p.X, p.Y, p.Z)).Position, 0.6 + (i % 3) * 0.25, rgb(18, 10, 30), PLASTIC, decor())
		end
	end
	---------------------------------------------------------------- the rounded top of the arm
	-- (owner 2026-10-24: the long see-through glow on the arm's top looked
	-- speckled over the studs; "round the top, with its end, right to the
	-- edges", "the dark block stays at the end") a solid glowing half-round
	-- roof as wide as the arm, from the dark top block over the column to a
	-- half-dome over the drop (a cylinder and a ball whose middles lie on the
	-- arm's top); the top block as tall as the roof, closing its end
	do
		local z0, d = -0.4, 2.6
		local endX = armLeft + d / 2
		local blockW = 2.6
		local backX = bx + 0.4 - blockW / 2
		cube(at(bx + 0.4, armTop + 0.7, z0), Vector3.new(blockW, 1.4, d + 0.02), nil, nil, "flat")
		local color = glowOf(st, 2)
		local function round(shape: Enum.PartType, at0cf: CFrame, size: Vector3)
			Geo.make("Part", {
				Shape = shape,
				CFrame = at0cf,
				Size = size,
				Color = color,
				Material = NEON,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				CastShadow = false,
			}, model)
		end
		round(Enum.PartType.Cylinder, at((endX + backX) / 2, armTop, z0), Vector3.new(backX - endX + 0.02, d, d))
		round(Enum.PartType.Ball, at(endX, armTop, z0), Vector3.new(d, d, d))
	end

	BlockKit.scale(model, cf, K)
	for _, o in ores do
		if lite then
			local color = if OreData.exists(o.Id) then OreData.get(o.Id).Glow else glow
			Geo.block(model, o.At, Vector3.new(0.75, 0.75, 0.75), color, NEON, decor())
		else
			ore(model, o.Id, dropper.Grade, o.At, o.Seed)
		end
	end
	return model
end

return DropperBuilder
