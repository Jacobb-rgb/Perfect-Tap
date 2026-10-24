--[[
	The droppers (Config/DropperConfig) like the owner's picture
	docs/art/droppers_concept.webp (2026-10-21), rounded and clean (owner
	2026-10-24: "more rounded, cleaner, more detail"): a rounded stage with a
	glowing front edge and the price, a round pedestal drum with a flange, a
	glowing ring and a bolted cap, a round column with glowing rings and a
	collar, a ball elbow, a round arm with a glowing top line and the name,
	and a round nozzle at its end that drops the dropper's ores in a beam of
	light onto a round glowing dish; a little console with glowing buttons.
	Crystals grow round the pedestal; each dropper is made of its own stuff:

	  BasicDropper       dirt with a grass cap, vines, flowers, green glow
	  BlueDropper        dark stone, blue glow, blue crystals
	  RedDropper         dark stone with glowing lava cracks and a lava pool, red glow
	  PurpleDropper      purple stone, violet glow, purple crystals
	  GoldDropper        gold, gold glow, sparkles
	  RainbowDropper     dark stone, every ring another colour, rainbow crystals,
	                     a rainbow of round lamps behind it
	  DarkMatterDropper  deep violet with black orbs and a swirl of glowing bars

	build(id, cf, lite?) -> Model (anchored; origin = the middle of its stage's bottom;
	front = +Z; the arm reaches toward -X and drops onto the pad there).
	`lite` (the DROPPERS shop's showroom, phones): fewer rings, no flange,
	bolts, collar, console or light, two crystal clusters, one ore on the
	dish, and every ore a glowing gem block in its colour in place of the
	ore model.
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

function DropperBuilder.build(id: string, cf: CFrame, lite: boolean?): Model
	local dropper = DropperConfig.ById[id]
	local st = DropperBuilder.Styles[id]
	assert(dropper and st, "Unknown dropper " .. tostring(id))
	local model = Instance.new("Model")
	model.Name = id
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function block(c: CFrame, size: Vector3, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
		return Geo.block(model, c, size, color, material or PLASTIC, decor(extra))
	end
	-- an upright cylinder centred at (x, y, z)
	local function drum(x: number, y: number, z: number, h: number, d: number, color: Color3, material: Enum.Material?): Part
		return Geo.cylinder(model, at(x, y, z).Position, h, d, color, material or PLASTIC, decor())
	end
	-- a cylinder along local X centred at (x, y, z)
	local function bar(x: number, y: number, z: number, len: number, d: number, color: Color3, material: Enum.Material?): Part
		local p = block(at(x, y, z), Vector3.new(len, d, d), color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function ball(x: number, y: number, z: number, d: number, color: Color3, material: Enum.Material?): Part
		return Geo.ball(model, at(x, y, z).Position, d, color, material or PLASTIC, decor())
	end
	local K = DropperBuilder.Scale
	type Drop = { Id: string, At: CFrame, Seed: number }
	local ores: { Drop } = {}
	local function dropOre(oreId: string, x: number, y: number, z: number, turn: CFrame, seed: number)
		table.insert(ores, { Id = oreId, At = cf * CFrame.new(x * K, y * K, z * K) * turn, Seed = seed })
	end
	local glow = glowOf(st, 1)
	local W, D = DropperBuilder.Width, DropperBuilder.Depth
	local DARK = rgb(26, 24, 38)
	local bx, sx, zc = 1.0, -2.7, -0.4 -- the pedestal's middle, the spout's x, the machine's z
	local stageH = 0.5

	---------------------------------------------------------------- the stage: a rounded slab, its glowing front edge, the price
	local r = 1.0
	block(at(0, stageH / 2, 0), Vector3.new(W - 2 * r, stageH, D), DARK)
	block(at(0, stageH / 2, 0), Vector3.new(W, stageH, D - 2 * r), DARK)
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			drum(cx * (W / 2 - r), stageH / 2, cz * (D / 2 - r), stageH, 2 * r, DARK)
		end
	end
	block(at(0, stageH + 0.01, D / 2 - 0.25), Vector3.new(W - 2 * r - 0.2, 0.04, 0.16), glow, NEON)
	BlockKit.text(
		model,
		at(0, stageH / 2, D / 2 + 0.03),
		Vector3.new(4.2, 0.42, 0.06),
		Format.money(dropper.Price),
		rgb(255, 230, 120),
		DARK,
		nil,
		Enum.Font.LuckiestGuy
	)

	---------------------------------------------------------------- the pedestal: a round drum, a flange, a glowing ring, a cap with bolts
	local pedH = 1.4
	local pedTop = stageH + pedH
	drum(bx, stageH + pedH / 2, zc, pedH, 4.4, st.Face)
	drum(bx, stageH + 0.9, zc, 0.14, 4.52, glowOf(st, 2), NEON)
	drum(bx, pedTop + 0.17, zc, 0.34, 3.7, st.Rim)
	if not lite then
		drum(bx, stageH + 0.13, zc, 0.26, 4.8, st.Rim)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			ball(bx + math.cos(a) * 1.55, pedTop + 0.36, zc + math.sin(a) * 1.55, 0.36, st.Rim)
		end
	end

	---------------------------------------------------------------- the column: a round pillar with glowing rings and a collar
	local colBottom, colTop = pedTop + 0.34, 8.6
	local colH = colTop - colBottom
	drum(bx, (colBottom + colTop) / 2, zc, colH, 2.2, st.Face)
	local rings = if lite then 2 else 3
	for k = 1, rings do
		drum(bx, colBottom + colH * k / (rings + 1), zc, 0.3, 2.36, glowOf(st, k + 1), NEON)
	end
	if not lite then
		drum(bx, colTop - 0.25, zc, 0.5, 2.6, st.Rim)
	end

	---------------------------------------------------------------- the elbow, the round arm, its glowing top line and the name
	local armY = colTop + 0.35
	ball(bx, armY, zc, 2.8, st.Face)
	local armEnd = sx - 0.2
	local armLen = bx - armEnd
	local armMid = (bx + armEnd) / 2
	bar(armMid, armY, zc, armLen, 1.9, st.Face)
	ball(armEnd, armY, zc, 1.95, st.Face)
	block(at(armMid - 0.2, armY + 0.93, zc), Vector3.new(armLen - 0.8, 0.1, 0.32), glow, NEON)
	BlockKit.text(
		model,
		at(armMid - 0.05, armY, zc + 1.48),
		Vector3.new(armLen - 0.9, 0.78, 0.06),
		string.upper(dropper.Name),
		Color3.new(1, 1, 1),
		DARK,
		glow,
		Enum.Font.LuckiestGuy
	)

	---------------------------------------------------------------- the spout: a round nozzle, a glowing ring and tip, its light and beam
	local spoutY = armY - 1.05
	drum(sx, spoutY, zc, 0.8, 1.4, st.Rim)
	drum(sx, spoutY - 0.36, zc, 0.12, 1.52, glow, NEON)
	drum(sx, spoutY - 0.45, zc, 0.08, 0.95, glow, NEON)
	if not lite then
		local lamp = block(at(sx, spoutY - 0.9, zc), Vector3.new(0.2, 0.2, 0.2), glow, NEON, { Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Brightness = 2.2
		light.Range = 14
		light.Parent = lamp
	end
	local padY = stageH + 0.3
	local beamTop, beamBottom = spoutY - 0.5, padY + 0.3
	local beam = drum(sx, (beamTop + beamBottom) / 2, zc, beamTop - beamBottom, 0.9, glow, NEON)
	beam.Transparency = 0.75
	for i = 1, 2 do
		local oreId = dropper.Ores[(i - 1) % #dropper.Ores + 1]
		dropOre(oreId, sx + (i - 1.5) * 0.2, beamTop - 0.6 - i * 1.9, zc + (i % 2) * 0.15, CFrame.Angles(i, i * 2, 0.4), 30 + i)
	end

	---------------------------------------------------------------- the pad: a round dish with a glowing ring, ores on it
	drum(sx, padY, zc + 0.2, 0.6, 3.2, DARK)
	drum(sx, padY + 0.2, zc + 0.2, 0.12, 3.4, glow, NEON)
	for i, p in { Vector3.new(-0.5, 0, 0.1), Vector3.new(0.4, 0, 0.8), Vector3.new(0, 0.25, 0.3) } do
		if lite and i > 1 then
			break
		end
		local oreId = dropper.Ores[(i + 1) % #dropper.Ores + 1]
		dropOre(oreId, sx + p.X, padY + 0.6 + p.Y, zc + p.Z, CFrame.Angles(0.3, i * 1.7, 0.2), 40 + i)
	end

	---------------------------------------------------------------- a little console with glowing buttons (front right)
	if not lite then
		local console = at(bx + 3.0, stageH + 0.45, 2.1) * CFrame.Angles(math.rad(-20), 0, 0)
		block(console, Vector3.new(1.3, 0.8, 0.9), st.Rim)
		for k, bxk in { -0.3, 0.3 } do
			block(console * CFrame.new(bxk, 0.42, 0), Vector3.new(0.3, 0.08, 0.3), glowOf(st, k), NEON)
		end
	end

	---------------------------------------------------------------- crystals round the pedestal and the pad
	cluster(model, at(bx + 2.7, stageH, 1.9), st, 1, if lite then 3 else 4)
	cluster(model, at(sx - 1.6, stageH, 2.3), st, 2, if lite then 2 else 3)
	if not lite then
		cluster(model, at(bx + 2.6, stageH, -2.5), st, 5, 2)
	end

	---------------------------------------------------------------- what each one is made of
	local kind = st.Kind
	if kind == "grass" then
		local GRASS = rgb(96, 186, 66)
		drum(bx, pedTop + 0.4, zc, 0.16, 3.9, GRASS)
		local flowers = if lite then 2 else 5
		for i = 1, flowers do
			local fx = bx - 2.3 + i * 0.85
			ball(fx, stageH + 0.18, 2.95 + (i % 2) * 0.25, 0.34, if i % 3 == 0 then rgb(255, 230, 80) else rgb(255, 255, 245))
		end
		if not lite then
			for _, v in
				{ Vector3.new(bx - 0.75, colBottom + colH * 0.55, zc + 1.05), Vector3.new(bx + 0.6, colBottom + colH * 0.35, zc + 1.05) }
			do
				block(at(v.X, v.Y, v.Z), Vector3.new(0.2, 1.8, 0.08), GRASS)
			end
		end
	elseif kind == "lava" then
		local LAVA = rgb(255, 90, 20)
		for _, a in { -0.5, 0.45 } do
			block(
				at(bx + math.sin(a) * 2.21, stageH + 0.75, zc + math.cos(a) * 2.21) * CFrame.Angles(0, a, 0.25),
				Vector3.new(0.14, 1.0, 0.06),
				LAVA,
				NEON
			)
		end
		drum(bx - 2.0, stageH + 0.03, 2.6, 0.06, 1.3, LAVA, NEON)
	elseif kind == "gold" then
		local sparkles = if lite then 3 else 6
		for i = 1, sparkles do
			local a = i * 1.7
			block(
				at(bx + math.cos(a) * 3.0, stageH + 2 + (i % 4) * 1.5, zc + math.sin(a) * 2.2) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(0.22, 0.22, 0.05),
				rgb(255, 250, 210),
				NEON
			)
		end
	elseif kind == "rainbow" and not lite then
		-- a rainbow of round lamps behind it
		for k = 0, 5 do
			local a = k / 5 * math.pi
			ball(math.cos(a) * 3.9, stageH + 1.2 + math.sin(a) * 3.9, -3.3, 0.7, RAINBOW[k + 1], NEON)
		end
	elseif kind == "dark" then
		-- black orbs round it and a swirl of glowing bars
		for i, p in
			{
				Vector3.new(bx + 2.9, 5.0, 1.0),
				Vector3.new(bx - 2.4, 6.2, 0.8),
				Vector3.new(sx - 1.2, 7.0, -1.8),
			}
		do
			ball(p.X, p.Y, p.Z, 0.6 + (i % 3) * 0.25, rgb(18, 10, 30))
		end
		if not lite then
			for k = 1, 6 do
				local a = k / 6 * math.pi * 2
				block(
					at(bx + math.cos(a) * 3.4, stageH + 1.4 + math.sin(a * 2) * 0.25, zc + math.sin(a) * 2.9) * CFrame.Angles(0, -a, 0),
					Vector3.new(0.12, 0.08, 1.1),
					glow,
					NEON
				)
			end
		end
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
