--[[
	The hoppers (Config/HopperConfig) built from parts in the Kenney Factory
	Kit style: a square collar on top of a four-sided funnel full of ores, four
	legs on a base plate with a glowing trim, a spout pouring a stream of ores
	into the collection chest under it. Every hopper up the list is bigger and
	gets more shine:

	  EpicHopper       steel, purple trim, bolts
	  LegendaryHopper  brass, golden crown spikes
	  MythicHopper     black iron, red crystal spikes on the corners
	  HeartHopper      rose metal, a floating heart and two little hearts
	  StarHopper       white and gold, a big golden star and a ring of lights
	  RiftHopper       night metal, rainbow trims, a rift ring behind it, shards
	  TerraCoreHopper  all gold, a glowing core held by four arms, a ring around it

	build(id, cf) -> Model (anchored, origin = the middle of the base plate's
	bottom, front = -Z... the sign faces +Z, toward the player).
	Pure: only creates Instances, so the Lune previews run it too.
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local ItemBuilder = require(script.Parent.ItemBuilder)
local HopperConfig = require(Shared.Config.HopperConfig)
local OreData = require(Shared.Config.OreData)
local Format = require(Shared.Util.Format)

local HopperBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local METAL = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

export type Style = {
	Scale: number,
	Frame: Color3, -- legs, plate, chest
	Metal: Color3, -- collar and funnel
	Dark: Color3, -- bands, pads
	Trim: { Color3 }, -- neon trims (more than one: they take turns)
	Deco: string,
}

HopperBuilder.Styles = {
	EpicHopper = {
		Scale = 1,
		Frame = rgb(70, 74, 88),
		Metal = rgb(132, 138, 156),
		Dark = rgb(40, 42, 52),
		Trim = { rgb(180, 92, 255) },
		Deco = "bolts",
	},
	LegendaryHopper = {
		Scale = 1.1,
		Frame = rgb(86, 58, 38),
		Metal = rgb(214, 160, 64),
		Dark = rgb(52, 34, 24),
		Trim = { rgb(255, 176, 32) },
		Deco = "crown",
	},
	MythicHopper = {
		Scale = 1.2,
		Frame = rgb(44, 34, 40),
		Metal = rgb(126, 40, 58),
		Dark = rgb(26, 18, 22),
		Trim = { rgb(255, 59, 122) },
		Deco = "crystals",
	},
	HeartHopper = {
		Scale = 1.3,
		Frame = rgb(118, 52, 80),
		Metal = rgb(236, 150, 180),
		Dark = rgb(70, 28, 46),
		Trim = { rgb(255, 120, 180) },
		Deco = "hearts",
	},
	StarHopper = {
		Scale = 1.45,
		Frame = rgb(226, 222, 210),
		Metal = rgb(240, 188, 70),
		Dark = rgb(150, 110, 40),
		Trim = { rgb(255, 176, 40) },
		Deco = "star",
	},
	RiftHopper = {
		Scale = 1.6,
		Frame = rgb(30, 26, 46),
		Metal = rgb(64, 54, 100),
		Dark = rgb(16, 14, 26),
		Trim = { rgb(255, 96, 96), rgb(255, 196, 64), rgb(120, 230, 90), rgb(70, 190, 255), rgb(190, 110, 255) },
		Deco = "rift",
	},
	TerraCoreHopper = {
		Scale = 1.85,
		Frame = rgb(178, 120, 36),
		Metal = rgb(232, 172, 60),
		Dark = rgb(96, 60, 20),
		Trim = { rgb(255, 150, 30) },
		Deco = "core",
	},
} :: { [string]: Style }

-- Sizes at Scale 1 (studs).
HopperBuilder.Plate = 7.2 -- base plate side
HopperBuilder.LegHeight = 5.0 -- plate top -> funnel bottom
HopperBuilder.FunnelHeight = 2.8
HopperBuilder.TopWidth = 5.4 -- funnel top (inside the collar)
HopperBuilder.SpoutWidth = 1.3
HopperBuilder.Collar = 1.1 -- collar height

-- How tall a hopper is (studs, without its decoration).
function HopperBuilder.height(id: string): number
	local s = HopperBuilder.Styles[id].Scale
	return (0.45 + HopperBuilder.LegHeight + HopperBuilder.FunnelHeight + HopperBuilder.Collar) * s
end

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function trim(style: Style, i: number): Color3
	return style.Trim[(i - 1) % #style.Trim + 1]
end

-- a text plate (SurfaceGui on the face toward +Z)
local function sign(parent: Instance, cf: CFrame, size: Vector3, text: string, ink: Color3, board: Color3, edge: Color3)
	Geo.block(parent, cf * CFrame.new(0, 0, -0.04), size + Vector3.new(0.16, 0.16, -0.04), edge, NEON, decor())
	local plate = Geo.block(parent, cf, size, board, METAL, decor())
	plate.Name = "Sign"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Text = text
	label.TextColor3 = ink
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = gui
	return plate
end

-- one face of the funnel: a trapezoid from two triangles (top edge wider)
local function funnelFace(
	parent: Instance,
	origin: CFrame,
	yaw: number,
	top: number,
	bottom: number,
	yTop: number,
	yBot: number,
	color: Color3
)
	local turn = origin * CFrame.Angles(0, yaw, 0)
	local tl = turn:PointToWorldSpace(Vector3.new(-top / 2, yTop, top / 2))
	local tr = turn:PointToWorldSpace(Vector3.new(top / 2, yTop, top / 2))
	local bl = turn:PointToWorldSpace(Vector3.new(-bottom / 2, yBot, bottom / 2))
	local br = turn:PointToWorldSpace(Vector3.new(bottom / 2, yBot, bottom / 2))
	local outward = turn:VectorToWorldSpace(Vector3.new(0, -(top - bottom) / 2, yTop - yBot)).Unit
	Geo.triangle(parent, tl, tr, br, 0.18, color, METAL, outward, decor({ CastShadow = true }))
	Geo.triangle(parent, tl, br, bl, 0.18, color, METAL, outward, decor({ CastShadow = true }))
end

local function ore(parent: Instance, id: string, grade: string, cf: CFrame, seed: number, full: boolean?)
	local info = { Kind = "Clean", OreId = id, Grade = grade }
	local model = if full then ItemBuilder.build(info, cf, seed) else ItemBuilder.buildLight(info, cf, seed)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.Parent = parent
	return model
end

-- a four-point star (two long thin blocks + a diamond) facing +Z
local function star(parent: Instance, cf: CFrame, size: number, color: Color3)
	Geo.block(parent, cf, Vector3.new(size * 0.16, size, size * 0.14), color, NEON, decor())
	Geo.block(parent, cf, Vector3.new(size, size * 0.16, size * 0.14), color, NEON, decor())
	Geo.block(parent, cf * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(size * 0.38, size * 0.38, size * 0.16), color, NEON, decor())
end

-- a heart (two balls + a turned block) facing +Z
local function heart(parent: Instance, cf: CFrame, size: number, color: Color3)
	local r = size * 0.5
	Geo.ball(parent, cf:PointToWorldSpace(Vector3.new(-r * 0.5, r * 0.25, 0)), r * 1.1, color, NEON, decor())
	Geo.ball(parent, cf:PointToWorldSpace(Vector3.new(r * 0.5, r * 0.25, 0)), r * 1.1, color, NEON, decor())
	Geo.block(
		parent,
		cf * CFrame.new(0, -r * 0.2, 0) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(r * 1.05, r * 1.05, r * 0.9),
		color,
		NEON,
		decor()
	)
end

function HopperBuilder.build(id: string, cf: CFrame): Model
	local hopper = HopperConfig.ById[id]
	local style = HopperBuilder.Styles[id]
	assert(hopper and style, "Unknown hopper " .. tostring(id))
	local s = style.Scale
	local model = Instance.new("Model")
	model.Name = id
	local root = cf * CFrame.new(0, 0, 0)
	local function at(x: number, y: number, z: number): CFrame
		return root * CFrame.new(x * s, y * s, z * s)
	end

	local plate = HopperBuilder.Plate
	local plateH = 0.45
	local legTop = plateH + HopperBuilder.LegHeight
	local funTop = legTop + HopperBuilder.FunnelHeight
	local top, spout = HopperBuilder.TopWidth, HopperBuilder.SpoutWidth
	local collar = HopperBuilder.Collar

	---------------------------------------------------------------- base plate with a glowing trim
	local base = Geo.block(model, at(0, plateH / 2, 0), Vector3.new(plate, plateH, plate) * s, style.Dark, METAL)
	base.Name = "Base"
	for i = 0, 3 do
		local side = root * CFrame.Angles(0, i * math.pi / 2, 0)
		Geo.block(
			model,
			side * CFrame.new(0, (plateH - 0.06) * s, (plate / 2 - 0.12) * s),
			Vector3.new(plate - 0.1, 0.12, 0.12) * s,
			trim(style, i + 1),
			NEON,
			decor()
		)
	end

	---------------------------------------------------------------- legs, pads and side braces
	local legX = top / 2 - 0.25
	for i, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		local x, z = corner.X * legX, corner.Y * legX
		Geo.block(model, at(x, plateH + 0.15, z), Vector3.new(1.0, 0.3, 1.0) * s, style.Dark, METAL, decor({ CastShadow = true }))
		Geo.block(
			model,
			at(x, (plateH + legTop) / 2 + 0.15, z),
			Vector3.new(0.62, HopperBuilder.LegHeight + 0.3, 0.62) * s,
			style.Frame,
			METAL,
			decor({ CastShadow = true })
		)
		if style.Deco == "bolts" or style.Deco == "rift" then
			Geo.ball(model, at(x, legTop - 0.5, z + corner.Y * 0.32).Position, 0.24 * s, trim(style, i), NEON, decor())
		end
	end
	-- braces on the back and the two sides (the front stays open to show the chest)
	for i = 1, 3 do
		local side = root * CFrame.Angles(0, (i - 1) * math.pi / 2 + math.pi / 2, 0)
		Geo.block(
			model,
			side * CFrame.new(0, (legTop - 1.2) * s, legX * s),
			Vector3.new(top - 0.8, 0.32, 0.3) * s,
			style.Frame,
			METAL,
			decor()
		)
	end

	---------------------------------------------------------------- funnel, spout and collar
	for i = 0, 3 do
		funnelFace(model, root, i * math.pi / 2, top * s, spout * s, funTop * s, legTop * s, style.Metal)
	end
	Geo.cylinder(model, at(0, legTop - 0.35, 0).Position, 0.7 * s, spout * 0.92 * s, style.Metal, METAL, decor())
	Geo.cylinder(model, at(0, legTop - 0.72, 0).Position, 0.18 * s, spout * 1.12 * s, trim(style, 1), NEON, decor())
	-- the collar: four thick walls and a glowing band on each
	for i = 0, 3 do
		local side = root * CFrame.Angles(0, i * math.pi / 2, 0)
		Geo.block(
			model,
			side * CFrame.new(0, (funTop + collar / 2) * s, (top / 2 + 0.05) * s),
			Vector3.new(top + 0.5, collar, 0.4) * s,
			style.Metal,
			METAL,
			decor({ CastShadow = true })
		)
		Geo.block(
			model,
			side * CFrame.new(0, (funTop + 0.18) * s, (top / 2 + 0.27) * s),
			Vector3.new(top + 0.52, 0.16, 0.06) * s,
			trim(style, i + 2),
			NEON,
			decor()
		)
		Geo.block(
			model,
			side * CFrame.new(0, (funTop + collar) * s, (top / 2 + 0.05) * s),
			Vector3.new(top + 0.62, 0.16, 0.52) * s,
			style.Dark,
			METAL,
			decor()
		)
	end
	-- the ore heap in the collar: a glowing fill and the ores poking out
	local main = OreData.get(hopper.Ores[#hopper.Ores])
	Geo.block(model, at(0, funTop + collar * 0.55, 0), Vector3.new(top - 0.2, 0.2, top - 0.2) * s, main.Color, METAL, decor())
	Geo.block(
		model,
		at(0, funTop + collar * 0.55 + 0.02, 0),
		Vector3.new(top - 1.4, 0.2, top - 1.4) * s,
		main.Glow,
		NEON,
		decor({ Transparency = 0.35 })
	)
	local heap = {
		Vector3.new(-1.3, 0, -0.9),
		Vector3.new(1.1, 0, -1.2),
		Vector3.new(0.1, 0.15, 0.2),
		Vector3.new(-0.9, 0, 1.2),
		Vector3.new(1.3, 0, 1.1),
	}
	for i, p in heap do
		local oreId = hopper.Ores[(i - 1) % #hopper.Ores + 1]
		ore(model, oreId, hopper.Grade, at(p.X, funTop + collar * 0.75 + p.Y, p.Z) * CFrame.Angles(0.3 * i, i * 1.3, -0.2 * i), i, i == 3)
	end

	---------------------------------------------------------------- the stream and the chest
	local chestTop = plateH + 1.5
	local streamTop, streamBottom = legTop - 0.9, chestTop + 0.4
	local beam = Geo.cylinder(
		model,
		at(0, (streamTop + streamBottom) / 2, 0).Position,
		(streamTop - streamBottom) * s,
		0.9 * s,
		main.Glow,
		NEON,
		decor({ Transparency = 0.82 })
	)
	beam.Name = "Stream"
	local drops = 4
	for i = 1, drops do
		local t = (i - 0.5) / drops
		local oreId = hopper.Ores[(i * 2 - 1) % #hopper.Ores + 1]
		ore(
			model,
			oreId,
			hopper.Grade,
			at(math.sin(i * 2.1) * 0.15, streamTop - t * (streamTop - streamBottom), math.cos(i * 1.7) * 0.15)
				* CFrame.Angles(i * 0.9, i * 2.2, i * 0.4),
			10 + i
		)
	end
	-- the chest: a box, a darker band, glowing corners and the ore pile on top
	local chestW, chestD = 3.4, 2.6
	Geo.block(model, at(0, plateH + 0.7, 0.2), Vector3.new(chestW, 1.4, chestD) * s, style.Frame, METAL, decor({ CastShadow = true }))
	Geo.block(model, at(0, plateH + 0.32, 0.2), Vector3.new(chestW + 0.08, 0.36, chestD + 0.08) * s, style.Dark, METAL, decor())
	for _, x in { -1, 1 } do
		Geo.block(
			model,
			at(x * (chestW / 2 - 0.05), plateH + 0.8, 0.2 + chestD / 2 - 0.05),
			Vector3.new(0.18, 1.3, 0.18) * s,
			trim(style, 1),
			NEON,
			decor()
		)
	end
	Geo.block(model, at(0, chestTop - 0.05, 0.2), Vector3.new(chestW - 0.4, 0.1, chestD - 0.4) * s, main.Color, METAL, decor())
	for i, p in { Vector3.new(-0.8, 0, 0), Vector3.new(0.75, 0, 0.35), Vector3.new(0, 0.2, -0.3) } do
		local oreId = hopper.Ores[(i + 1) % #hopper.Ores + 1]
		ore(model, oreId, hopper.Grade, at(p.X, chestTop + 0.25 + p.Y, 0.2 + p.Z) * CFrame.Angles(0.2, i * 1.9, 0.3), 20 + i, i == 3)
	end
	-- the income plate on the chest front
	sign(
		model,
		at(0, plateH + 0.85, 0.2 + chestD / 2 + 0.06),
		Vector3.new(2.9, 0.62, 0.08) * s,
		Format.perSecond(hopper.Income),
		rgb(140, 255, 110),
		rgb(16, 18, 24),
		trim(style, 1)
	)
	-- the name plate on the collar front
	sign(
		model,
		at(0, funTop + collar / 2, top / 2 + 0.3),
		Vector3.new(top - 0.6, collar - 0.34, 0.08) * s,
		string.upper(hopper.Name),
		rgb(255, 250, 236),
		rgb(16, 18, 24),
		trim(style, 1)
	)

	---------------------------------------------------------------- the decoration of each hopper
	local roof = funTop + collar
	local deco = style.Deco
	local corners = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local cx = top / 2 + 0.05
	if deco == "bolts" then
		for i, c in corners do
			Geo.ball(model, at(c.X * cx, roof + 0.1, c.Y * cx).Position, 0.42 * s, style.Dark, METAL, decor())
			Geo.ball(model, at(c.X * cx, roof + 0.22, c.Y * cx).Position, 0.2 * s, trim(style, i), NEON, decor())
		end
	elseif deco == "crown" then
		for i, c in corners do
			Geo.block(
				model,
				at(c.X * cx, roof + 0.55, c.Y * cx) * CFrame.Angles(0, math.pi / 4, 0),
				Vector3.new(0.7, 1.0, 0.7) * s,
				style.Metal,
				METAL,
				decor()
			)
			Geo.block(
				model,
				at(c.X * cx, roof + 1.25, c.Y * cx) * CFrame.Angles(math.pi / 4, math.pi / 4, 0),
				Vector3.new(0.3, 0.3, 0.3) * s,
				trim(style, i),
				NEON,
				decor()
			)
		end
		-- small spikes in the middle of each side
		for i = 0, 3 do
			local side = root * CFrame.Angles(0, i * math.pi / 2, 0)
			Geo.block(
				model,
				side * CFrame.new(0, (roof + 0.4) * s, cx * s) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(0.5, 0.5, 0.3) * s,
				style.Metal,
				METAL,
				decor()
			)
		end
	elseif deco == "crystals" then
		for i, c in corners do
			local lean = CFrame.Angles(-c.Y * 0.32, 0, c.X * 0.32)
			local crystal = at(c.X * cx, roof + 0.8, c.Y * cx) * lean * CFrame.Angles(0, math.pi / 4, 0)
			Geo.block(model, crystal, Vector3.new(0.5, 1.6, 0.5) * s, rgb(200, 30, 80), GLASS, decor())
			Geo.block(
				model,
				crystal * CFrame.new(0, 0.8 * s, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
				Vector3.new(0.36, 0.36, 0.36) * s,
				trim(style, i),
				NEON,
				decor()
			)
			Geo.block(
				model,
				at(c.X * (cx - 0.5), roof + 0.5, c.Y * (cx + 0.2)) * lean * CFrame.Angles(0.3, 0.7, 0),
				Vector3.new(0.34, 1.1, 0.34) * s,
				rgb(150, 30, 60),
				GLASS,
				decor()
			)
		end
	elseif deco == "hearts" then
		heart(model, at(0, roof + 2.3, 0), 1.8 * s, trim(style, 1))
		heart(model, at(-2.4, roof + 1.2, 0.6) * CFrame.Angles(0, 0, 0.3), 0.7 * s, rgb(255, 170, 205))
		heart(model, at(2.5, roof + 1.7, -0.4) * CFrame.Angles(0, 0, -0.3), 0.55 * s, rgb(255, 170, 205))
		for _, c in corners do
			Geo.ball(model, at(c.X * cx, roof + 0.2, c.Y * cx).Position, 0.5 * s, style.Frame, METAL, decor())
		end
	elseif deco == "star" then
		star(model, at(0, roof + 2.8, 0), 2.6 * s, trim(style, 1))
		Geo.block(model, at(0, roof + 0.8, 0), Vector3.new(0.3, 1.4, 0.3) * s, style.Dark, METAL, decor())
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			Geo.ball(model, at(math.cos(a) * 4.2, roof + 0.4, math.sin(a) * 4.2).Position, 0.3 * s, trim(style, 1), NEON, decor())
		end
		for i, c in corners do
			star(model, at(c.X * cx, roof + 0.5, c.Y * cx) * CFrame.Angles(0, i * 0.8, 0), 0.8 * s, rgb(255, 196, 70))
		end
	elseif deco == "rift" then
		-- the rift ring behind the hopper: glowing blocks in the rainbow colours
		local ringY, ringR = funTop - 0.5, 4.4
		for i = 1, 16 do
			local a = i / 16 * math.pi * 2
			Geo.block(
				model,
				at(math.cos(a) * ringR, ringY + math.sin(a) * ringR, -top / 2 - 2.2) * CFrame.Angles(0, 0, a),
				Vector3.new(0.5, 1.7, 0.4) * s,
				trim(style, i),
				NEON,
				decor()
			)
		end
		Geo.cylinder(
			model,
			at(0, ringY, -top / 2 - 2.35).Position,
			0.1 * s,
			7.6 * s,
			rgb(60, 30, 110),
			NEON,
			decor({ Transparency = 0.45, CFrame = at(0, ringY, -top / 2 - 2.35) * CFrame.Angles(0, math.pi / 2, 0) })
		)
		-- floating shards over the collar
		for i, p in { Vector3.new(-2.6, 1.6, 0.8), Vector3.new(2.4, 2.1, -0.6), Vector3.new(0.4, 2.8, 0.3), Vector3.new(-0.9, 1.2, -2.2) } do
			Geo.block(
				model,
				at(p.X, roof + p.Y, p.Z) * CFrame.Angles(i * 0.7, i * 0.5, 0.6),
				Vector3.new(0.45, 1.2, 0.45) * s,
				trim(style, i + 1),
				NEON,
				decor()
			)
		end
	elseif deco == "core" then
		-- the core: a glowing ball in a glass shell, held by four arms, with a ring of gold lights
		local coreY = roof + 3.2
		for _, c in corners do
			local from = at(c.X * cx, roof, c.Y * cx).Position
			local to = at(c.X * 0.9, coreY - 0.6, c.Y * 0.9).Position
			local mid = (from + to) / 2
			Geo.block(model, CFrame.lookAt(mid, to), Vector3.new(0.4 * s, 0.4 * s, (to - from).Magnitude), style.Dark, METAL, decor())
		end
		Geo.ball(model, at(0, coreY, 0).Position, 1.9 * s, rgb(255, 84, 40), NEON, decor())
		Geo.ball(model, at(0, coreY, 0).Position, 3.0 * s, rgb(255, 170, 80), GLASS, decor({ Transparency = 0.6 }))
		for i = 1, 14 do
			local a = i / 14 * math.pi * 2
			Geo.block(
				model,
				at(math.cos(a) * 2.6, coreY, math.sin(a) * 2.6) * CFrame.Angles(0, -a, 0),
				Vector3.new(0.3, 0.3, 1.0) * s,
				if i % 2 == 0 then trim(style, 1) else style.Metal,
				if i % 2 == 0 then NEON else METAL,
				decor()
			)
		end
		for i, c in corners do
			star(model, at(c.X * (cx + 0.2), roof + 0.6, c.Y * (cx + 0.2)) * CFrame.Angles(0, i * 0.8, 0), 0.9 * s, rgb(255, 140, 40))
		end
	end
	return model
end

return HopperBuilder
