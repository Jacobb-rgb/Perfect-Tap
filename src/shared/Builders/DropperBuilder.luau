--[[
	The droppers (Config/DropperConfig) like the owner's picture
	docs/art/droppers_concept.webp (2026-10-21), in the glowing block style of
	the first concept: a stepped block pedestal with a glowing step, a leaning
	two-block column with a ladder of glowing slot blocks on its side, a long
	block arm on top with a glowing top edge, and the spout under the arm's end
	that drops the dropper's ores in a beam of light onto a glowing pad.
	Crystals grow around the pedestal; each dropper is made of its own stuff:

	  BasicDropper       dirt blocks with grass caps, vines, flowers, green glow
	  BlueDropper        black stone, blue glow, blue crystals
	  RedDropper         black stone with lava cracks and a lava drip, red glow
	  PurpleDropper      purple stone, violet glow, purple crystals
	  GoldDropper        gold blocks, gold glow, sparkles
	  RainbowDropper     black stone, every slot another colour, rainbow crystals,
	                     a block rainbow behind it
	  DarkMatterDropper  starry black blocks with violet cracks, a spiral on the
	                     column, a swirl ring and black orbs around it

	build(id, cf) -> Model (anchored; origin = the middle of its stage's bottom;
	front = +Z; the arm reaches toward -X and drops onto the pad there).
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local ItemBuilder = require(script.Parent.ItemBuilder)
local DropperConfig = require(Shared.Config.DropperConfig)
local Format = require(Shared.Util.Format)

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
	BasicDropper = style(rgb(150, 104, 62), rgb(102, 68, 38), { rgb(90, 255, 110) }, { rgb(60, 220, 80) }, "grass"),
	BlueDropper = style(rgb(74, 78, 96), rgb(36, 38, 52), { rgb(40, 150, 255) }, { rgb(70, 170, 255) }, "stone"),
	RedDropper = style(rgb(78, 60, 58), rgb(38, 26, 26), { rgb(255, 70, 30) }, { rgb(255, 60, 50) }, "lava"),
	PurpleDropper = style(rgb(104, 64, 160), rgb(62, 36, 104), { rgb(205, 90, 255) }, { rgb(190, 110, 255) }, "stone"),
	GoldDropper = style(rgb(246, 194, 62), rgb(186, 126, 28), { rgb(255, 214, 80) }, { rgb(255, 205, 60) }, "gold"),
	RainbowDropper = style(rgb(62, 62, 76), rgb(30, 30, 40), RAINBOW, RAINBOW, "rainbow"),
	DarkMatterDropper = style(rgb(46, 32, 78), rgb(18, 12, 34), { rgb(175, 80, 255) }, { rgb(140, 60, 255) }, "dark"),
} :: { [string]: Style }

-- Sizes (studs).
DropperBuilder.Width = 9.4 -- the stage along x (before Scale)
DropperBuilder.Depth = 7 -- the stage along z
DropperBuilder.Height = 10.6 -- stage bottom -> arm top (before Scale)

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false, CastShadow = false }
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

function DropperBuilder.build(id: string, cf: CFrame): Model
	local dropper = DropperConfig.ById[id]
	local st = DropperBuilder.Styles[id]
	assert(dropper and st, "Unknown dropper " .. tostring(id))
	local model = Instance.new("Model")
	model.Name = id
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function cube(c: CFrame, size: Vector3, face: Color3?, rim: Color3?, mode: string?): Part
		return BlockKit.cube(model, c, size, face or st.Face, rim or st.Rim, mode)
	end
	local K = DropperBuilder.Scale
	type Drop = { Id: string, At: CFrame, Seed: number }
	local ores: { Drop } = {}
	local function dropOre(oreId: string, x: number, y: number, z: number, turn: CFrame, seed: number)
		table.insert(ores, { Id = oreId, At = cf * CFrame.new(x * K, y * K, z * K) * turn, Seed = seed })
	end
	local glow = glowOf(st, 1)
	local W, D = DropperBuilder.Width, DropperBuilder.Depth
	local DARK, DARK_RIM = rgb(26, 24, 38), rgb(14, 12, 22)
	local bx, sx = 1.0, -2.7 -- the pedestal's middle, the spout's x
	local stageH = 0.5

	---------------------------------------------------------------- the stage, its glowing front edge and the price
	cube(at(0, stageH / 2, 0), Vector3.new(W, stageH, D), DARK, DARK_RIM)
	Geo.block(model, at(0, stageH + 0.01, D / 2 - 0.2), Vector3.new(W - 0.2, 0.04, 0.16), glow, NEON, decor())
	BlockKit.text(
		model,
		at(0, stageH / 2, D / 2 + 0.05),
		Vector3.new(4.2, 0.46, 0.06),
		Format.money(dropper.Price),
		rgb(255, 230, 120),
		DARK,
		nil,
		Enum.Font.LuckiestGuy
	)

	---------------------------------------------------------------- the stepped pedestal and its glowing step
	local p1y = stageH + 0.8
	cube(at(bx, p1y, -0.2), Vector3.new(5.0, 1.6, 4.6))
	local p2y = stageH + 1.6 + 0.6
	cube(at(bx + 0.3, p2y, -0.4), Vector3.new(3.8, 1.2, 3.6))
	cube(at(bx - 0.4, stageH + 0.4, 2.55), Vector3.new(2.6, 0.8, 0.9))
	Geo.block(model, at(bx - 0.4, stageH + 0.42, 3.02), Vector3.new(2.2, 0.22, 0.05), glowOf(st, 2), NEON, decor())
	Geo.block(model, at(bx, stageH + 1.6, 2.12), Vector3.new(4.6, 0.12, 0.06), glowOf(st, 3), NEON, decor())

	---------------------------------------------------------------- the leaning column and the ladder of slot blocks
	local lowerY = p2y + 0.6 + 1.5
	cube(at(bx + 0.1, lowerY, -0.4) * CFrame.Angles(0, 0, 0.06), Vector3.new(2.3, 3.0, 2.5))
	local upperY = lowerY + 2.9
	cube(at(bx - 0.15, upperY, -0.4) * CFrame.Angles(0, 0, 0.13), Vector3.new(2.1, 2.9, 2.3))
	for i = 1, 4 do
		local ly = p2y + 0.2 + i * 1.25
		local lx = bx + 1.55 - (i - 1) * 0.12
		cube(at(lx, ly, -0.3 + (i % 2) * 0.12), Vector3.new(1.0, 1.15, 1.9), nil, nil, "side")
		Geo.block(model, at(lx, ly, 0.68 + (i % 2) * 0.12), Vector3.new(0.62, 0.28, 0.05), glowOf(st, i + 1), NEON, decor())
	end

	---------------------------------------------------------------- the arm, its top step, the glowing top edge
	local armY = upperY + 1.45 + 0.9
	local armRight, armLeft = bx + 1.6, sx - 1.0
	local armLen = armRight - armLeft
	cube(at((armRight + armLeft) / 2, armY, -0.4), Vector3.new(armLen, 1.8, 2.6))
	Geo.block(
		model,
		at((armRight + armLeft) / 2 - 0.4, armY - 0.92, 0.82),
		Vector3.new(armLen - 1.2, 0.1, 0.1),
		glowOf(st, 3),
		NEON,
		decor()
	)
	cube(at(bx + 0.4, armY + 1.25, -0.4), Vector3.new(2.6, 0.7, 2.3))
	Geo.block(model, at((armRight + armLeft) / 2, armY + 0.92, 0.82), Vector3.new(armLen - 0.2, 0.12, 0.1), glow, NEON, decor())
	Geo.block(
		model,
		at((armRight + armLeft) / 2, armY + 0.92, -0.4),
		Vector3.new(armLen - 0.4, 0.06, 2.3),
		glowOf(st, 2),
		NEON,
		decor({ Transparency = 0.5 })
	)
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
	cube(at(sx, spoutY, -0.4), Vector3.new(1.7, 0.9, 1.7))
	Geo.block(model, at(sx, spoutY - 0.47, -0.4), Vector3.new(1.2, 0.06, 1.2), glow, NEON, decor())
	local lamp = Geo.block(model, at(sx, spoutY - 0.8, -0.4), Vector3.new(0.2, 0.2, 0.2), glow, NEON, decor({ Transparency = 1 }))
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Brightness = 2.2
	light.Range = 14
	light.Parent = lamp
	local padY = stageH + 0.35
	local beamTop = spoutY - 0.5
	Geo.block(model, at(sx, beamTop - 0.5, -0.4), Vector3.new(1.1, 1.0, 1.1), glow, NEON, decor({ Transparency = 0.75 }))
	for i = 1, 2 do
		local oreId = dropper.Ores[(i - 1) % #dropper.Ores + 1]
		dropOre(oreId, sx + (i - 1.5) * 0.2, beamTop - 0.6 - i * 1.9, -0.4 + (i % 2) * 0.15, CFrame.Angles(i, i * 2, 0.4), 30 + i)
	end
	cube(at(sx - 0.1, padY, 0.2), Vector3.new(2.8, 0.7, 3.4), DARK, DARK_RIM)
	for _, side in { -1, 1 } do
		Geo.block(model, at(sx - 0.1 + side * 1.36, padY, 0.2), Vector3.new(0.1, 0.72, 3.42), glow, NEON, decor())
		Geo.block(model, at(sx - 0.1, padY, 0.2 + side * 1.66), Vector3.new(2.82, 0.72, 0.1), glow, NEON, decor())
	end
	for i, p in { Vector3.new(-0.6, 0, 0.1), Vector3.new(0.4, 0, 1.0), Vector3.new(0, 0.25, 0.4) } do
		local oreId = dropper.Ores[(i + 1) % #dropper.Ores + 1]
		dropOre(oreId, sx + p.X, padY + 0.6 + p.Y, -0.4 + p.Z, CFrame.Angles(0.3, i * 1.7, 0.2), 40 + i)
	end

	---------------------------------------------------------------- crystals around the pedestal and the pad
	cluster(model, at(bx + 2.6, stageH, 2.0), st, 1, 4)
	cluster(model, at(bx - 2.3, stageH, 1.9), st, 3, 3)
	cluster(model, at(bx + 2.4, stageH, -2.4), st, 5, 3)
	cluster(model, at(sx - 1.4, stageH, 2.2), st, 2, 3)

	---------------------------------------------------------------- what each one is made of
	local kind = st.Kind
	if kind == "grass" then
		local GRASS, GRASS_RIM = rgb(96, 186, 66), rgb(62, 132, 44)
		cube(at(bx, stageH + 1.6 + 0.12, -0.2), Vector3.new(5.02, 0.3, 4.62), GRASS, GRASS_RIM, "side")
		cube(at(bx + 0.3, p2y + 0.62, -0.4), Vector3.new(3.82, 0.3, 3.62), GRASS, GRASS_RIM, "side")
		cube(at((armRight + armLeft) / 2, armY + 0.98, -0.4), Vector3.new(armLen + 0.02, 0.3, 2.62), GRASS, GRASS_RIM, "side")
		-- vines down the column and the arm, flowers at the foot
		for i, v in
			{
				Vector3.new(bx - 1.0, lowerY + 0.5, 0.9),
				Vector3.new(bx + 0.5, upperY, 0.82),
				Vector3.new(armLeft + 1.4, armY - 0.6, 0.92),
				Vector3.new(armRight - 0.9, armY - 0.8, 0.92),
			}
		do
			Geo.block(model, at(v.X, v.Y, v.Z), Vector3.new(0.22, 1.4 + (i % 2) * 0.6, 0.06), GRASS, PLASTIC, decor())
		end
		for i = 1, 6 do
			local fx = bx - 2.4 + i * 0.9
			Geo.block(
				model,
				at(fx, stageH + 0.15, 2.9 + (i % 2) * 0.3),
				Vector3.new(0.3, 0.3, 0.3),
				if i % 3 == 0 then rgb(255, 230, 80) else rgb(255, 255, 245),
				PLASTIC,
				decor()
			)
		end
	elseif kind == "lava" then
		local LAVA = rgb(255, 90, 20)
		crack(model, at(bx - 0.6, p1y, 2.11), 1.4, LAVA, 1)
		crack(model, at(bx + 1.2, p1y, 2.11), 1.4, LAVA, 2)
		crack(model, at(bx - 0.2, lowerY, 0.86), 2.6, LAVA, 3)
		crack(model, at(bx + 0.1, upperY, 0.76), 2.4, LAVA, 4)
		-- a lava drip down the pedestal into a little pool
		Geo.block(model, at(bx - 1.9, stageH + 1.1, 2.12), Vector3.new(0.35, 1.2, 0.06), LAVA, NEON, decor())
		Geo.block(model, at(bx - 1.9, stageH + 0.03, 2.9), Vector3.new(1.4, 0.05, 1.0), LAVA, NEON, decor())
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
		for band = 1, 6, 2 do
			local r = 4.6 - band * 0.3
			for k = 0, 6 do
				local a = k / 6 * math.pi
				Geo.block(
					model,
					at(math.cos(a) * r, stageH + 1 + math.sin(a) * r, -3.6),
					Vector3.new(0.62, 0.62, 0.3),
					RAINBOW[band],
					PLASTIC,
					decor()
				)
			end
		end
	elseif kind == "dark" then
		-- stars on the blocks, violet cracks, the spiral, the swirl ring and the orbs
		for i = 1, 6 do
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
			if k % 2 == 0 then
				Geo.block(
					model,
					at(bx + math.cos(a) * 3.6, stageH + 1.2 + math.sin(a * 2) * 0.25, -0.2 + math.sin(a) * 3.0) * CFrame.Angles(0, -a, 0),
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
				Vector3.new(sx - 1.2, 7.0, -1.8),
			}
		do
			Geo.ball(model, (at(p.X, p.Y, p.Z)).Position, 0.6 + (i % 3) * 0.25, rgb(18, 10, 30), PLASTIC, decor())
		end
	end
	BlockKit.scale(model, cf, K)
	for _, o in ores do
		ore(model, o.Id, dropper.Grade, o.At, o.Seed)
	end
	return model
end

return DropperBuilder
