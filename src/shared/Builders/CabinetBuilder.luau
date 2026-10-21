--[[
	The glowing block cabinet (the owner's first concept picture,
	docs/art/hoppers_concept.webp): base with a neon top, corner pillars with
	neon strips, a shard chamber behind a window, a light stream onto a slide
	into the priced tray, a roof with corner blocks and the name plate.
	Used by the Money Laser (LaserBuilder); the droppers have their own shape
	(DropperBuilder).

	buildCabinet(cf, color, name, price?, crest?) -> Model (anchored; origin =
	the middle of the base's bottom; front = +Z).
]]

local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)

local CabinetBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

-- Sizes (studs).
CabinetBuilder.Plate = 5.8 -- the base's width (x)
CabinetBuilder.Depth = 5.0 -- the base's depth (z), the tray sticks out in front
CabinetBuilder.PillarH = 7.6 -- the corner pillars (base top -> roof)
CabinetBuilder.Height = 9.4 -- base bottom -> roof top

local function decor(): { [string]: any }
	return { CanTouch = false, CanQuery = false, CastShadow = false, CanCollide = false }
end

local DARK = rgb(22, 20, 35)
local DARK_RIM = rgb(12, 10, 20)

-- a glowing shard: a turned block with a smaller tip (the picture's crystals)
local function shard(parent: Instance, cf: CFrame, size: number, color: Color3)
	Geo.block(parent, cf, Vector3.new(0.55, 1.2, 0.55) * size, color, GLASS, decor())
	Geo.block(
		parent,
		cf * CFrame.new(0, 0.72 * size, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(0.36, 0.36, 0.36) * size,
		color,
		NEON,
		decor()
	)
end

-- a heap of small shards (window pile, tray pile)
local function heap(parent: Instance, cf: CFrame, w: number, d: number, n: number, color: Color3, seed: number)
	for i = 1, n do
		local a = (i * 2.399 + seed) % (math.pi * 2)
		local r = (i * 0.618 + seed * 0.1) % 1
		local x = math.cos(a) * r * w / 2
		local z = math.sin(a) * r * d / 2
		local tint = if i % 3 == 0 then color:Lerp(Color3.new(1, 1, 1), 0.5) else color
		shard(
			parent,
			cf * CFrame.new(x, 0.15 + (1 - r) * 0.35, z) * CFrame.Angles(0.4 * math.sin(i), i * 0.9, 0.5 * math.cos(i)),
			0.5 + (i % 3) * 0.12,
			tint
		)
	end
end

local HEART = {
	".##.##.",
	"#######",
	"#######",
	".#####.",
	"..###..",
	"...#...",
}
local STAR = {
	"...#...",
	"..###..",
	"#######",
	".#####.",
	"..###..",
	".##.##.",
	"##...##",
}

local function crest(model: Instance, cf: CFrame, kind: string, color: Color3)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.45)
	-- every crest stands in a ring of small shards
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		shard(
			model,
			cf
				* CFrame.new(math.cos(a) * 1.9, 0.5 + (i % 2) * 0.4, math.sin(a) * 1.5)
				* CFrame.Angles(math.cos(a) * 0.5, a, math.sin(a) * 0.5),
			0.75,
			if i % 2 == 0 then light else color
		)
	end
	if kind == "cluster" then
		for i, p in { Vector3.new(0, 1.6, 0), Vector3.new(-0.9, 1.1, 0.3), Vector3.new(0.9, 1.2, -0.2), Vector3.new(0.3, 0.9, 0.8) } do
			shard(
				model,
				cf * CFrame.new(p) * CFrame.Angles(0.2 * (i - 2), i, -0.25 * (i - 2)),
				1.5 - i * 0.15,
				if i == 1 then light else color
			)
		end
	elseif kind == "gem" then
		Geo.block(
			model,
			cf * CFrame.new(0, 2.0, 0) * CFrame.Angles(0, math.pi / 4, math.pi / 4),
			Vector3.new(1.6, 1.6, 1.6),
			color,
			NEON,
			decor()
		)
		for i, p in { Vector3.new(-1.0, 1.0, 0.2), Vector3.new(1.0, 1.1, -0.2), Vector3.new(0.4, 0.8, 0.9) } do
			shard(model, cf * CFrame.new(p) * CFrame.Angles(0.2, i, 0.3 * (i - 2)), 1.0, light)
		end
	elseif kind == "heartgem" then
		BlockKit.pixelArt(model, cf * CFrame.new(0, 2.2, 0), HEART, 0.42, { ["#"] = color }, 0.9, NEON)
		BlockKit.pixelArt(model, cf * CFrame.new(-0.42, 2.6, 0.48), { "##", "#." }, 0.42, { ["#"] = light }, 0.1, NEON)
	elseif kind == "heart" then
		BlockKit.pixelArt(model, cf * CFrame.new(0, 2.3, 0), HEART, 0.5, { ["#"] = color }, 0.6, NEON)
	elseif kind == "star" then
		BlockKit.pixelArt(model, cf * CFrame.new(0, 2.5, 0), STAR, 0.48, { ["#"] = color }, 0.6, NEON)
	elseif kind == "vortex" then
		local core = cf * CFrame.new(0, 2.2, 0)
		Geo.block(model, core, Vector3.new(1.1, 1.1, 0.5), rgb(30, 10, 60), PLASTIC, decor())
		for ring, r in { 1.1, 1.8 } do
			local n = if ring == 1 then 8 else 12
			for i = 1, n do
				local a = i / n * math.pi * 2 + ring * 0.3
				local even = (i + ring) % 2 == 0
				Geo.block(
					model,
					core * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a),
					Vector3.new(0.45, 0.7, 0.4),
					if even then color else light,
					if even then NEON else PLASTIC,
					decor()
				)
			end
		end
	elseif kind == "cube" then
		local core = cf * CFrame.new(0, 2.2, 0) * CFrame.Angles(0.5, 0.6, 0.3)
		Geo.block(
			model,
			core,
			Vector3.new(1.7, 1.7, 1.7),
			rgb(255, 196, 60),
			GLASS,
			{ Transparency = 0.25, CanTouch = false, CanQuery = false, CastShadow = false, CanCollide = false }
		)
		Geo.block(model, core, Vector3.new(0.9, 0.9, 0.9), rgb(255, 150, 30), NEON, decor())
		local ring = cf * CFrame.new(0, 2.2, 0) * CFrame.Angles(0.35, 0, 0.25)
		for i = 1, 14 do
			local a = i / 14 * math.pi * 2
			Geo.block(
				model,
				ring * CFrame.new(math.cos(a) * 1.7, 0, math.sin(a) * 1.7) * CFrame.Angles(0, -a, 0),
				Vector3.new(0.18, 0.18, 0.8),
				color,
				NEON,
				decor()
			)
		end
	end
end

--[[
	The cabinet in `color`: base, pillars, chamber with the window and its
	shards, the light stream, the slide, the tray with the price, the roof and
	the name. `crestKind` nil: no crest (the laser adds its own beam).
]]
function CabinetBuilder.buildCabinet(cf: CFrame, color: Color3, name: string, price: string?, crestKind: string?): Model
	local model = Instance.new("Model")
	local dim = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local rim = color:Lerp(Color3.new(0, 0, 0), 0.6)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.45)
	local W, D = CabinetBuilder.Plate, CabinetBuilder.Depth
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- base with a neon top
	BlockKit.cube(model, at(0, 0.35, 0), Vector3.new(W, 0.7, D), dim, rim, "side")
	Geo.block(model, at(0, 0.73, 0), Vector3.new(W - 0.3, 0.08, D - 0.3), color, NEON, decor())

	-- the tray in front, with its price plate and the poured shards
	local trayZ = D / 2 + 0.7
	BlockKit.cube(model, at(0, 0.6, trayZ), Vector3.new(W - 0.4, 1.2, 1.8), DARK, DARK_RIM, "side")
	for _, side in { -1, 1 } do
		Geo.block(model, at(side * (W / 2 - 0.25), 0.6, trayZ), Vector3.new(0.12, 1.22, 1.82), color, NEON, decor())
	end
	heap(model, at(0, 1.2, trayZ - 0.1), W - 1.4, 1.2, 4, color, 3)
	if price then
		BlockKit.text(
			model,
			at(0, 0.6, trayZ + 0.93),
			Vector3.new(W - 1.4, 0.9, 0.08),
			price,
			Color3.new(1, 1, 1),
			DARK,
			color,
			Enum.Font.LuckiestGuy
		)
	end

	-- four corner pillars with a neon strip and two pixel marks each
	local px, pz = W / 2 - 0.4, D / 2 - 0.4
	local pillarH = CabinetBuilder.PillarH
	for _, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		local pc = at(c.X * px, 0.7 + pillarH / 2, c.Y * pz)
		BlockKit.cube(model, pc, Vector3.new(0.8, pillarH, 0.8), dim, rim, "side")
		if c.Y > 0 then
			Geo.block(model, pc * CFrame.new(0, 0, 0.42), Vector3.new(0.16, pillarH - 1.4, 0.06), color, NEON, decor())
			for _, y in { -pillarH / 2 + 0.4, pillarH / 2 - 0.4 } do
				Geo.block(model, pc * CFrame.new(0, y, 0.42), Vector3.new(0.4, 0.4, 0.06), light, NEON, decor())
			end
		end
	end

	-- the chamber: dark back and sides, a dark floor shelf, the tinted window
	local chamberH = pillarH - 2.8
	local chamberY = 0.7 + 1.2 + chamberH / 2
	BlockKit.cube(model, at(0, chamberY, -D / 2 + 0.5), Vector3.new(W - 1.4, chamberH, 0.4), DARK, DARK_RIM, "side")
	for _, side in { -1, 1 } do
		BlockKit.cube(model, at(side * (W / 2 - 0.5), chamberY, 0), Vector3.new(0.3, chamberH, D - 1.6), DARK, DARK_RIM, "side")
	end
	BlockKit.cube(model, at(0, 0.7 + 1.05, -0.3), Vector3.new(W - 1.4, 0.3, D - 1.8), DARK, DARK_RIM, "side")
	heap(model, at(0, 0.7 + 1.2, -0.6), W - 2.2, D - 2.6, 4, color, 7)
	Geo.block(model, at(0, chamberY + 0.2, D / 2 - 0.45), Vector3.new(W - 1.5, chamberH - 0.4, 0.1), color, GLASS, {
		Transparency = 0.88,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		CanCollide = false,
	})

	-- the funnel under the roof, its light stream and the slide into the tray
	BlockKit.cube(model, at(0, chamberY + chamberH / 2 - 0.3, 0), Vector3.new(2.4, 0.6, 2.4), dim, rim, "side")
	BlockKit.cube(model, at(0, chamberY + chamberH / 2 - 0.8, 0), Vector3.new(1.2, 0.5, 1.2), DARK, DARK_RIM, "side")
	Geo.block(model, at(0, chamberY, 0.3), Vector3.new(0.4, chamberH - 1.6, 0.4), color, NEON, {
		Transparency = 0.45,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		CanCollide = false,
	})
	local slide = at(0, 1.35, D / 2 - 0.2) * CFrame.Angles(-0.55, 0, 0)
	Geo.block(model, slide, Vector3.new(1.6, 0.15, 2.4), DARK, PLASTIC, decor())
	for _, side in { -1, 1 } do
		Geo.block(model, slide * CFrame.new(side * 0.85, 0.15, 0), Vector3.new(0.14, 0.3, 2.4), color, NEON, decor())
	end
	for i = 1, 3 do
		shard(
			model,
			slide * CFrame.new((i - 2) * 0.35, 0.35, (i - 2) * 0.7) * CFrame.Angles(0.3, i, 0.2),
			0.55,
			if i == 2 then light else color
		)
	end

	-- the roof: a slab in the colour, a neon top edge, corner blocks
	local roofY = 0.7 + pillarH + 0.35
	BlockKit.cube(model, at(0, roofY, 0), Vector3.new(W + 0.2, 0.7, D + 0.2), dim, rim, "side")
	Geo.block(model, at(0, roofY + 0.38, 0), Vector3.new(W, 0.08, D), color, NEON, decor())
	for _, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		BlockKit.cube(model, at(c.X * (W / 2 - 0.3), roofY + 0.75, c.Y * (D / 2 - 0.3)), Vector3.new(0.7, 0.7, 0.7), dim, rim, "flat")
		Geo.block(model, at(c.X * (W / 2 - 0.3), roofY + 1.12, c.Y * (D / 2 - 0.3)), Vector3.new(0.4, 0.05, 0.4), light, NEON, decor())
	end
	-- the name plate under the roof's front edge
	BlockKit.text(
		model,
		at(0, roofY - 0.95, D / 2 + 0.05),
		Vector3.new(W - 1.0, 1.1, 0.1),
		name,
		Color3.new(1, 1, 1),
		DARK,
		color,
		Enum.Font.LuckiestGuy
	)

	-- one light so the cabinet glows on the ground around it
	local lamp = Geo.block(model, at(0, chamberY, 0), Vector3.new(0.2, 0.2, 0.2), color, NEON, decor())
	lamp.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = 1.6
	glow.Range = 12
	glow.Parent = lamp

	if crestKind then
		local top = at(0, roofY + 0.4, 0)
		local crestModel = Instance.new("Model")
		crest(crestModel, top, crestKind, color)
		BlockKit.scale(crestModel, top, 1.35)
		for _, part in crestModel:GetChildren() do
			part.Parent = model
		end
	end
	return model
end

return CabinetBuilder
