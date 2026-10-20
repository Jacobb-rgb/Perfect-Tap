--[[
	"Forge Works": a Satisfactory x Hydroneer look for the machines (owner,
	2026-10-20: "the Soft look stays saved, but try more of a Satisfactory x
	Hydroneer style"). A CONCEPT: the game still builds KitMachines (the Soft
	look, saved at the git tag machines-soft-2026-10-20); this module only
	feeds the preview scene `works_gallery` until the owner picks.

	The mix (feel only, nothing copied):
	  - Satisfactory: chunky gunmetal steel housings with chamfered tops,
	    orange side panels with rivets, hazard stripes, big square belt
	    ports with a light strip, glowing inspection windows, round smoke
	    stacks with bands, a lattice of ladders and rails, stack lamps;
	  - Hydroneer: hand-built wood (plank hoppers, timber frames around the
	    steel deck, crates, a wooden windmill tower), copper pipes with brass
	    flanges and pressure gauges, big exposed brass cogs, a water tank and
	    a hose.
	Flat details (planks, rivets, stripes, gauge faces) are SurfaceGui
	frames, so they cost no parts. Every part carries the attribute Kit =
	its colour role, like KitMachines (the crystal upgrade looks repaint by
	role if this look is chosen).

	Local space: origin = footprint centre on the plot surface, front = -Z.
]]

local Geo = require(script.Parent.Geo)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local WorksMachines = {}

type Props = { [string]: any }
type Paint = { x: number, y: number, w: number, h: number, color: Color3, round: boolean?, stripes: number? }

local rgb = Color3.fromRGB
local UP = Vector3.yAxis
local XA = Vector3.xAxis
local ZA = Vector3.zAxis
local FLOOR = 0.3 -- top of the steel deck

WorksMachines.Palette = {
	Steel = rgb(150, 156, 166), -- light steel housings
	SteelDark = rgb(62, 66, 76), -- frames, roofs, recesses
	Deck = rgb(118, 120, 122), -- the concrete-grey deck
	Panel = rgb(222, 216, 204), -- off-white panels
	Orange = rgb(242, 138, 44), -- the works orange: side panels, frames, bands
	Hazard = rgb(250, 190, 40),
	Wood = rgb(176, 130, 86),
	WoodDark = rgb(110, 76, 50),
	Copper = rgb(206, 118, 66),
	Brass = rgb(224, 178, 82),
	Rubber = rgb(30, 32, 38),
	Glass = rgb(206, 232, 246),
	Glow = rgb(255, 132, 30),
	Hot = rgb(255, 220, 120),
	Molten = rgb(255, 120, 24),
	Water = rgb(70, 196, 255),
	Lamp = rgb(90, 230, 120),
	Screen = rgb(22, 28, 40),
	Bolt = rgb(200, 196, 186),
	Line = rgb(84, 56, 34), -- plank seams
}
local P = WorksMachines.Palette

local MATERIAL: { [string]: Enum.Material } = {
	Steel = Enum.Material.Metal,
	SteelDark = Enum.Material.Metal,
	Deck = Enum.Material.Concrete,
	Copper = Enum.Material.Metal,
	Brass = Enum.Material.Metal,
	Wood = Enum.Material.WoodPlanks,
	WoodDark = Enum.Material.Wood,
	Glass = Enum.Material.Glass,
	Glow = Enum.Material.Neon,
	Hot = Enum.Material.Neon,
	Molten = Enum.Material.Neon,
	Water = Enum.Material.Neon,
	Lamp = Enum.Material.Neon,
}

---------------------------------------------------------------- parts

local function props(role: string, size: Vector3, extra: Props?): Props
	local p: Props = {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		-- small parts cast no shadow (mobile)
		CastShadow = size.Magnitude > 3,
		Transparency = if role == "Glass" then 0.72 else 0,
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function tag(part: BasePart, role: string, name: string?): BasePart
	part:SetAttribute("Kit", role)
	if name then
		part.Name = name
	end
	return part
end

local function box(m: Instance, cf: CFrame, size: Vector3, role: string, name: string?, extra: Props?): BasePart
	local part = Geo.block(m, cf, size, (P :: any)[role], MATERIAL[role] or Enum.Material.SmoothPlastic, props(role, size, extra))
	return tag(part, role, name)
end

local function wedge(m: Instance, cf: CFrame, size: Vector3, role: string): BasePart
	local part = Geo.wedge(m, cf, size, (P :: any)[role], MATERIAL[role] or Enum.Material.SmoothPlastic, props(role, size))
	return tag(part, role)
end

-- A cylinder from a to b.
local function rod(m: Instance, a: Vector3, b: Vector3, d: number, role: string, name: string?): BasePart
	local length = (b - a).Magnitude
	local size = Vector3.new(length, d, d)
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	local part = Geo.block(m, cf, size, (P :: any)[role], MATERIAL[role] or Enum.Material.SmoothPlastic, props(role, size))
	part.Shape = Enum.PartType.Cylinder
	return tag(part, role, name)
end

-- An upright cylinder standing on `bottom`.
local function post(m: Instance, bottom: Vector3, d: number, h: number, role: string, name: string?): BasePart
	return rod(m, bottom, bottom + UP * h, d, role, name)
end

local function ball(m: Instance, center: Vector3, d: number, role: string, name: string?): BasePart
	local size = Vector3.new(d, d, d)
	local part = Geo.ball(m, center, d, (P :: any)[role], MATERIAL[role] or Enum.Material.SmoothPlastic, props(role, size))
	return tag(part, role, name)
end

---------------------------------------------------------------- flat details

local function paint(part: BasePart, face: Enum.NormalId, items: { Paint }): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Paint"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 140
	gui.Parent = part
	for _, it in items do
		local stripes = it.stripes
		if stripes then
			-- hazard stripes: hard yellow / dark steps, 2 keypoints each, at most
			-- 10 stripes per gradient (Roblox: 20 keypoints, from 0 to exactly 1)
			local n = math.max(1, math.floor(stripes))
			local chunks = math.ceil(n / 10)
			local from = 0
			for c = 1, chunks do
				local to = math.floor(n * c / chunks + 0.5)
				local k = to - from
				local keys = {}
				for j = 0, k - 1 do
					local color = if (from + j) % 2 == 0 then P.Hazard else P.SteelDark
					table.insert(keys, ColorSequenceKeypoint.new(j / k, color))
					table.insert(keys, ColorSequenceKeypoint.new(if j == k - 1 then 1 else (j + 1) / k - 0.001, color))
				end
				local chunk = Instance.new("Frame")
				chunk.Name = "Stripes"
				chunk.BorderSizePixel = 0
				chunk.BackgroundColor3 = Color3.new(1, 1, 1)
				chunk.Position = UDim2.fromScale(it.x + it.w * from / n, it.y)
				chunk.Size = UDim2.fromScale(it.w * k / n, it.h)
				local gradient = Instance.new("UIGradient")
				gradient.Color = ColorSequence.new(keys)
				gradient.Parent = chunk
				chunk.Parent = gui
				from = to
			end
		else
			local frame = Instance.new("Frame")
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = it.color
			frame.Position = UDim2.fromScale(it.x, it.y)
			frame.Size = UDim2.fromScale(it.w, it.h)
			if it.round then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = frame
			end
			frame.Parent = gui
		end
	end
	return gui
end

-- Plank seams across a face (`count` boards), running along the face's width.
local function planks(part: BasePart, face: Enum.NormalId, count: number, across: boolean?)
	local items: { Paint } = {}
	for i = 1, count - 1 do
		local t = i / count
		if across then
			table.insert(items, { x = t - 0.006, y = 0, w = 0.012, h = 1, color = P.Line })
		else
			table.insert(items, { x = 0, y = t - 0.01, w = 1, h = 0.02, color = P.Line })
		end
	end
	paint(part, face, items)
end

-- Four round rivets in the corners of a face.
local function rivets(part: BasePart, face: Enum.NormalId)
	paint(part, face, {
		{ x = 0.05, y = 0.07, w = 0.05, h = 0.07, color = P.Bolt, round = true },
		{ x = 0.9, y = 0.07, w = 0.05, h = 0.07, color = P.Bolt, round = true },
		{ x = 0.05, y = 0.86, w = 0.05, h = 0.07, color = P.Bolt, round = true },
		{ x = 0.9, y = 0.86, w = 0.05, h = 0.07, color = P.Bolt, round = true },
	})
end

-- A control panel painted on a housing face (Satisfactory): a dark screen with a green bar,
-- two round buttons and panel seams. x, y = the panel's top-left corner (face scale).
local function controlPanel(part: BasePart, face: Enum.NormalId, x: number, y: number)
	paint(part, face, {
		{ x = 0, y = 0.5, w = 1, h = 0.012, color = P.SteelDark },
		{ x = x, y = y, w = 0.2, h = 0.18, color = P.Screen },
		{ x = x + 0.02, y = y + 0.06, w = 0.16, h = 0.04, color = P.Lamp },
		{ x = x + 0.02, y = y + 0.11, w = 0.09, h = 0.03, color = P.Orange },
		{ x = x + 0.03, y = y + 0.22, w = 0.05, h = 0.06, color = P.Molten, round = true },
		{ x = x + 0.11, y = y + 0.22, w = 0.05, h = 0.06, color = P.Lamp, round = true },
	})
end

local function hazard(part: BasePart, face: Enum.NormalId, stripes: number, y: number?, h: number?)
	paint(part, face, { { x = 0, y = y or 0, w = 1, h = h or 1, color = P.Hazard, stripes = stripes } })
end

---------------------------------------------------------------- kit pieces

local function newModel(id: string): (Model, BasePart, number, number)
	local info = MachineData.ById[id]
	local cell = GameConfig.CellSize
	local w, d = info.Size[1] * cell, info.Size[2] * cell
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("Look", "Works")
	-- the steel deck in a timber frame (Hydroneer) with a hazard edge at the front (Satisfactory)
	local base = box(model, CFrame.new(0, FLOOR / 2, 0), Vector3.new(w - 0.5, FLOOR, d - 0.5), "Deck", "Base")
	hazard(base, Enum.NormalId.Top, math.floor(w * 1.5), 0.93, 0.07)
	for _, side in { -1, 1 } do
		local beam = box(model, CFrame.new(0, 0.22, side * (d / 2 - 0.2)), Vector3.new(w - 0.1, 0.44, 0.4), "WoodDark")
		planks(beam, Enum.NormalId.Top, 2)
		box(model, CFrame.new(side * (w / 2 - 0.2), 0.22, 0), Vector3.new(0.4, 0.44, d - 0.9), "WoodDark")
	end
	model.PrimaryPart = base
	return model, base, w, d
end

--[[
	A steel housing with chamfered top edges (Satisfactory): the body, a
	narrower roof slab and a wedge along each top edge. Returns the body and
	the roof's top height.
]]
local function housing(m: Instance, bottom: Vector3, w: number, h: number, d: number, c: number, role: string?): (BasePart, number)
	local r = role or "Steel"
	local body = box(m, CFrame.new(bottom + UP * ((h - c) / 2)), Vector3.new(w, h - c, d), r)
	local top = bottom.Y + h - c
	local roof = box(m, CFrame.new(bottom.X, top + c / 2, bottom.Z), Vector3.new(w - 2 * c, c, d - 2 * c), "SteelDark")
	local cy = top + c / 2
	wedge(m, CFrame.new(bottom.X, cy, bottom.Z - d / 2 + c / 2), Vector3.new(w, c, c), r)
	wedge(m, CFrame.new(bottom.X, cy, bottom.Z + d / 2 - c / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, c, c), r)
	wedge(m, CFrame.new(bottom.X - w / 2 + c / 2, cy, bottom.Z) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(d - 2 * c, c, c), r)
	wedge(m, CFrame.new(bottom.X + w / 2 - c / 2, cy, bottom.Z) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(d - 2 * c, c, c), r)
	local _ = roof
	return body, top + c
end

-- Orange side panels with rivets on the left and right of a housing.
local function sidePanels(m: Instance, center: Vector3, w: number, h: number, d: number)
	for _, side in { -1, 1 } do
		local panel = box(m, CFrame.new(center + XA * side * (w / 2 + 0.06)), Vector3.new(0.12, h, d), "Orange")
		rivets(panel, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right)
	end
end

-- A belt port (Satisfactory): an orange frame round a dark mouth with a light strip over it.
local function port(m: Instance, cf: CFrame, w: number, h: number)
	box(m, cf, Vector3.new(w + 0.4, h + 0.4, 0.3), "Orange")
	box(m, cf * CFrame.new(0, 0, -0.08), Vector3.new(w, h, 0.2), "Rubber")
	box(m, cf * CFrame.new(0, h / 2 + 0.32, -0.05), Vector3.new(w * 0.8, 0.12, 0.12), "Lamp")
end

-- A round smoke stack: steel, an orange band, a dark rim and the ChimneyTop the smoke comes out of.
local function stack(m: Instance, bottom: Vector3, d: number, h: number)
	post(m, bottom, d, h, "Steel")
	post(m, bottom + UP * (h * 0.55), d + 0.14, 0.4, "Orange")
	post(m, bottom + UP * (h - 0.05), d + 0.24, 0.3, "SteelDark")
	post(m, bottom + UP * (h + 0.2), d * 0.7, 0.08, "Rubber", "ChimneyTop")
end

-- A wooden plank hopper (Hydroneer): a box of four boards, upright outside and sloping
-- down to a `bottom`-wide mouth inside, on a timber rim with iron corners.
local function hopper(m: Instance, center: Vector3, top: number, bottom: number, h: number)
	local slope = (top - bottom) / 2
	for k = 0, 3 do
		local turn = CFrame.Angles(0, k * math.pi / 2, 0)
		local board = wedge(
			m,
			CFrame.new(center + UP * (h / 2)) * turn * CFrame.new(0, 0, -(bottom / 2 + slope / 2)) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(top, h, slope),
			"Wood"
		)
		local _ = board
	end
	local rimY = center.Y + h + 0.15
	for k = 0, 3 do
		local turn = CFrame.Angles(0, k * math.pi / 2, 0)
		local rail =
			box(m, CFrame.new(center.X, rimY, center.Z) * turn * CFrame.new(0, 0, -top / 2), Vector3.new(top + 0.3, 0.3, 0.3), "WoodDark")
		if k == 0 then
			planks(rail, Enum.NormalId.Front, 2, true)
		end
		box(m, CFrame.new(center.X, rimY, center.Z) * turn * CFrame.new(top / 2, 0, -top / 2), Vector3.new(0.4, 0.4, 0.4), "SteelDark")
	end
end

-- A brass-ringed pressure gauge looking along `facing`.
local function gauge(m: Instance, at: Vector3, facing: Vector3, d: number)
	local ring = rod(m, at, at + facing * 0.16, d, "Brass")
	local face = rod(m, at + facing * 0.14, at + facing * 0.2, d * 0.78, "Panel")
	local _ = ring
	local needle =
		box(m, CFrame.lookAt(at + facing * 0.22, at + facing) * CFrame.Angles(0, 0, 0.6), Vector3.new(0.05, d * 0.32, 0.03), "Molten")
	local _ = face
	local _ = needle
end

-- A copper pipe from a to b with brass flanges at both ends.
local function pipe(m: Instance, a: Vector3, b: Vector3, d: number)
	rod(m, a, b, d, "Copper")
	local dir = (b - a).Unit
	rod(m, a, a + dir * 0.18, d + 0.16, "Brass")
	rod(m, b - dir * 0.18, b, d + 0.16, "Brass")
end

-- A cog (Hydroneer): a disc with four bars through it (eight teeth) and an axle cap.
local function cog(m: Instance, center: Vector3, axis: Vector3, d: number, thick: number, role: string, name: string?)
	rod(m, center - axis * (thick / 2), center + axis * (thick / 2), d, role, name)
	local up = if math.abs(axis.Y) > 0.9 then XA else UP
	local side = axis:Cross(up).Unit
	up = side:Cross(axis).Unit
	for k = 0, 3 do
		local a = k * math.pi / 4
		local dir = up * math.cos(a) + side * math.sin(a)
		local cf = CFrame.fromMatrix(center, axis, dir)
		box(m, cf, Vector3.new(thick * 0.9, d + 0.36, 0.26), role)
	end
	rod(m, center + axis * (thick / 2), center + axis * (thick / 2 + 0.16), d * 0.3, "SteelDark")
end

-- A stack lamp on a short post (green: working).
local function lamp(m: Instance, at: Vector3)
	post(m, at, 0.16, 0.9, "SteelDark")
	post(m, at + UP * 0.9, 0.34, 0.36, "Lamp", "StackGreen")
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

---------------------------------------------------------------- machines

--[[
	Clay Furnace (2x2), a works smelter: a chamfered steel housing with
	orange side panels, a glowing grated window at the front over the output
	port, a wooden coal hopper on the roof, a banded smoke stack at the back,
	a copper pipe with a gauge, a belt port at the back, a stack lamp.
]]
local function clayFurnace(): Model
	local m, _, w, d = newModel("ClayFurnace")
	local bw, bh, bd = 5.4, 4.2, 5.0
	local bottom = Vector3.new(0, FLOOR, 0.2)
	local body, roof = housing(m, bottom, bw, bh, bd, 0.7)
	sidePanels(m, bottom + UP * ((bh - 0.7) / 2), bw, bh - 1.6, bd - 1.4)
	local front = bottom.Z - bd / 2
	-- the firebox: an orange frame, the fire behind a grate, its hot core
	local winY = bottom.Y + 2.1
	box(m, CFrame.new(-0.5, winY, front - 0.12), Vector3.new(2.6, 2.0, 0.3), "Orange")
	local fire = box(m, CFrame.new(-0.5, winY, front - 0.22), Vector3.new(2.1, 1.5, 0.12), "Glow", "Glow")
	light(fire, P.Glow, 12, 1.4)
	paint(fire, Enum.NormalId.Front, {
		{ x = 0.3, y = 0.3, w = 0.4, h = 0.45, color = P.Hot, round = true },
		{ x = 0.2, y = 0, w = 0.05, h = 1, color = P.SteelDark },
		{ x = 0.47, y = 0, w = 0.05, h = 1, color = P.SteelDark },
		{ x = 0.74, y = 0, w = 0.05, h = 1, color = P.SteelDark },
	})
	controlPanel(body, Enum.NormalId.Front, 0.74, 0.18)
	port(m, CFrame.new(0, bottom.Y + 0.6, front - 0.2), 1.6, 0.8)
	hopper(m, Vector3.new(0.9, roof, 0.6), 2.4, 1.2, 1.1)
	stack(m, Vector3.new(-1.4, roof, 1.5), 1.1, 3.0)
	-- a copper pipe down the right side to a gauge
	local px = bw / 2 + 0.45
	pipe(m, Vector3.new(px, roof - 0.4, 1.6), Vector3.new(px, bottom.Y + 1.0, 1.6), 0.36)
	gauge(m, Vector3.new(px + 0.1, bottom.Y + 2.4, 0.4), XA, 0.8)
	port(m, CFrame.new(0, bottom.Y + 1.6, bottom.Z + bd / 2 + 0.2) * CFrame.Angles(0, math.pi, 0), 1.6, 1.0)
	lamp(m, Vector3.new(-w / 2 + 0.7, FLOOR, -d / 2 + 0.7))
	local _ = body
	return m
end

--[[
	Crusher (2x2): a steel housing under a big wooden plank hopper with iron
	corners, two exposed brass cogs on the left (Cog1 / Cog2), a motor box
	with a copper coil on the right, a hazard plate and the output port at
	the front, a stack lamp.
]]
local function crusher(): Model
	local m, _, w, d = newModel("Crusher")
	local bw, bh, bd = 5.0, 3.0, 4.6
	local bottom = Vector3.new(0.2, FLOOR, 0.3)
	local body, roof = housing(m, bottom, bw, bh, bd, 0.5)
	local front = bottom.Z - bd / 2
	hopper(m, Vector3.new(bottom.X, roof - 0.2, bottom.Z), 4.6, 2.0, 1.8)
	-- the cogs turn on the +X side (MachineFxController names)
	local left = bottom.X + bw / 2 + 0.2
	cog(m, Vector3.new(left, bottom.Y + 1.9, bottom.Z + 0.6), XA, 2.3, 0.3, "Brass", "Cog1")
	cog(m, Vector3.new(left, bottom.Y + 1.0, bottom.Z - 1.2), XA, 1.3, 0.3, "SteelDark", "Cog2")
	-- the motor on the -X side: a steel box, an orange cap, a copper coil
	local right = bottom.X - bw / 2 - 1.2
	box(m, CFrame.new(right + 0.6, bottom.Y + 0.8, bottom.Z + 0.5), Vector3.new(1.2, 1.6, 1.8), "SteelDark")
	box(m, CFrame.new(right + 0.6, bottom.Y + 1.7, bottom.Z + 0.5), Vector3.new(1.3, 0.2, 1.9), "Orange")
	rod(
		m,
		Vector3.new(right + 0.6, bottom.Y + 0.8, bottom.Z - 0.6),
		Vector3.new(right + 0.6, bottom.Y + 0.8, bottom.Z - 0.3),
		1.1,
		"Copper"
	)
	controlPanel(body, Enum.NormalId.Front, 0.06, 0.08)
	local plate = box(m, CFrame.new(bottom.X, bottom.Y + 2.3, front - 0.06), Vector3.new(bw - 0.6, 0.5, 0.1), "Hazard")
	hazard(plate, Enum.NormalId.Front, 9)
	port(m, CFrame.new(bottom.X, bottom.Y + 0.8, front - 0.2), 1.8, 1.0)
	lamp(m, Vector3.new(w / 2 - 0.7, FLOOR, -d / 2 + 0.7))
	local _ = body
	return m
end

--[[
	Cleaning Station (3x2), a wash bench: a planked workbench on steel legs
	with a steel vise (OrePoint) and a wooden wash tub, a copper water tank
	with brass bands and a gauge, a black hose to the spray wand on its
	hook, a lamp arm over the vise and a tool board at the back.
]]
local function cleaningStation(): Model
	local m, base, w, d = newModel("CleaningStation")
	local benchY = 2.6
	local bx, bz, bw, bd = 0.6, 0.6, 6.4, 3.6
	local top = box(m, CFrame.new(bx, benchY, bz), Vector3.new(bw, 0.35, bd), "Wood")
	planks(top, Enum.NormalId.Top, 4, true)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				m,
				CFrame.new(bx + sx * (bw / 2 - 0.3), (FLOOR + benchY) / 2, bz + sz * (bd / 2 - 0.3)),
				Vector3.new(0.35, benchY - FLOOR, 0.35),
				"Steel"
			)
		end
	end
	local shelf = box(m, CFrame.new(bx, 0.9, bz), Vector3.new(bw - 0.4, 0.2, bd - 0.4), "WoodDark")
	planks(shelf, Enum.NormalId.Top, 3, true)
	-- the vise in the middle (the ore sits in its jaws)
	local vy = benchY + 0.18
	box(m, CFrame.new(bx, vy + 0.25, bz), Vector3.new(1.6, 0.5, 1.0), "SteelDark")
	for _, sx in { -1, 1 } do
		box(m, CFrame.new(bx + sx * 0.75, vy + 0.85, bz), Vector3.new(0.3, 0.9, 1.0), "Steel")
	end
	rod(m, Vector3.new(bx + 0.9, vy + 0.6, bz), Vector3.new(bx + 2.0, vy + 0.6, bz), 0.16, "Brass")
	rod(m, Vector3.new(bx + 2.0, vy + 0.6, bz - 0.5), Vector3.new(bx + 2.0, vy + 0.6, bz + 0.5), 0.12, "Steel")
	-- the wash tub at the right end of the bench
	local tub = box(m, CFrame.new(bx + 2.3, benchY + 0.45, bz), Vector3.new(1.5, 0.6, 2.4), "Wood")
	planks(tub, Enum.NormalId.Front, 2)
	box(m, CFrame.new(bx + 2.3, benchY + 0.72, bz), Vector3.new(1.2, 0.08, 2.1), "Water", "WaterPool", { Transparency = 0.25 })
	-- the water tank on the left, a gauge on it
	local tx, tz = -w / 2 + 1.5, 0.4
	post(m, Vector3.new(tx, FLOOR, tz), 2.2, 3.4, "Copper")
	for _, y in { 0.6, 2.8 } do
		post(m, Vector3.new(tx, FLOOR + y, tz), 2.36, 0.22, "Brass")
	end
	ball(m, Vector3.new(tx, FLOOR + 3.4, tz), 2.1, "Copper")
	gauge(m, Vector3.new(tx, FLOOR + 1.9, tz - 1.1), -ZA, 0.7)
	-- the hose from the tank's foot along the floor up to the wand's hook
	local hookX, hookZ = bx + bw / 2 + 0.5, bz - 0.4
	local h0 = Vector3.new(tx + 1.1, FLOOR + 0.4, tz - 0.6)
	local h1 = Vector3.new(bx - 1.0, FLOOR + 0.2, -d / 2 + 0.9)
	local h2 = Vector3.new(hookX - 0.2, FLOOR + 0.2, -d / 2 + 0.9)
	local h3 = Vector3.new(hookX, benchY + 0.4, hookZ)
	rod(m, h0, h1, 0.22, "Rubber")
	rod(m, h1, h2, 0.22, "Rubber")
	rod(m, h2, h3, 0.22, "Rubber")
	-- the spray wand on its hook: a yellow lance, a brass nozzle, a black grip
	post(m, Vector3.new(hookX + 0.3, FLOOR, hookZ + 0.6), 0.2, 3.6, "SteelDark")
	local grip = h3 + UP * 0.2
	rod(m, grip, grip + Vector3.new(0, 1.6, -0.25), 0.16, "Hazard")
	rod(m, grip + Vector3.new(0, 1.6, -0.25), grip + Vector3.new(0, 1.85, -0.29), 0.24, "Brass")
	box(m, CFrame.new(grip + Vector3.new(0.05, -0.15, 0.1)), Vector3.new(0.22, 0.5, 0.3), "Rubber")
	-- a lamp arm over the vise (Satisfactory work light)
	local ax, az = bx - 1.6, bz + bd / 2 - 0.3
	post(m, Vector3.new(ax, benchY + 0.18, az), 0.18, 2.4, "SteelDark")
	rod(m, Vector3.new(ax, benchY + 2.5, az), Vector3.new(bx - 0.3, benchY + 2.5, bz), 0.14, "SteelDark")
	local head = box(m, CFrame.new(bx - 0.3, benchY + 2.35, bz), Vector3.new(0.8, 0.3, 0.6), "Orange")
	local bulb = box(m, CFrame.new(bx - 0.3, benchY + 2.17, bz), Vector3.new(0.6, 0.06, 0.4), "Hot")
	light(bulb, P.Hot, 8, 0.9)
	local _ = head
	-- the tool board at the back
	local board = box(m, CFrame.new(bx, benchY + 1.4, bz + bd / 2 + 0.1), Vector3.new(4.2, 2.2, 0.15), "Wood")
	planks(board, Enum.NormalId.Front, 3)
	paint(board, Enum.NormalId.Front, {
		{ x = 0.12, y = 0.25, w = 0.05, h = 0.5, color = P.SteelDark },
		{ x = 0.3, y = 0.2, w = 0.12, h = 0.14, color = P.Orange },
		{ x = 0.34, y = 0.34, w = 0.04, h = 0.45, color = P.WoodDark },
		{ x = 0.6, y = 0.3, w = 0.2, h = 0.08, color = P.Steel },
		{ x = 0.84, y = 0.22, w = 0.08, h = 0.5, color = P.Copper },
	})
	lamp(m, Vector3.new(w / 2 - 0.6, FLOOR, d / 2 - 0.6))
	local _ = base
	return m
end

--[[
	Blast Furnace (3x3), a works foundry: a tall chamfered housing with
	orange panels and steel ribs, a long glowing slit window, a tapping spout
	with a molten stream, two banded stacks, a copper tank and pipes on the
	right, a ladder and a roof rail on the left, two wooden coke crates, belt
	ports at the front and back, a stack lamp.
]]
local function blastFurnace(): Model
	local m, _, w, d = newModel("BlastFurnace")
	local bw, bh, bd = 6.6, 6.4, 6.2
	local bottom = Vector3.new(-0.4, FLOOR, 0.6)
	local body, roof = housing(m, bottom, bw, bh, bd, 0.8)
	sidePanels(m, bottom + UP * (bh * 0.42), bw, bh * 0.55, bd - 1.6)
	local front = bottom.Z - bd / 2
	for _, sx in { -1, 1 } do
		box(
			m,
			CFrame.new(bottom.X + sx * (bw / 2 - 0.25), bottom.Y + (bh - 0.8) / 2, front - 0.12),
			Vector3.new(0.5, bh - 0.8, 0.26),
			"SteelDark"
		)
	end
	controlPanel(body, Enum.NormalId.Front, 0.7, 0.62)
	-- the slit window and the tapping spout under it
	local winY = bottom.Y + 3.8
	box(m, CFrame.new(bottom.X, winY, front - 0.1), Vector3.new(4.2, 1.1, 0.24), "SteelDark")
	local fire = box(m, CFrame.new(bottom.X, winY, front - 0.18), Vector3.new(3.8, 0.7, 0.1), "Glow", "Glow")
	light(fire, P.Glow, 14, 1.6)
	local bars = box(m, CFrame.new(bottom.X, winY, front - 0.25), Vector3.new(3.8, 0.7, 0.05), "Glass")
	paint(bars, Enum.NormalId.Front, {
		{ x = 0.2, y = 0, w = 0.03, h = 1, color = P.SteelDark },
		{ x = 0.4, y = 0, w = 0.03, h = 1, color = P.SteelDark },
		{ x = 0.6, y = 0, w = 0.03, h = 1, color = P.SteelDark },
		{ x = 0.8, y = 0, w = 0.03, h = 1, color = P.SteelDark },
	})
	wedge(m, CFrame.new(bottom.X, bottom.Y + 2.2, front - 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.2, 0.5, 1.0), "Orange")
	rod(m, Vector3.new(bottom.X, bottom.Y + 2.0, front - 1.0), Vector3.new(bottom.X, bottom.Y + 0.9, front - 1.1), 0.3, "Molten", "Molten")
	port(m, CFrame.new(bottom.X, bottom.Y + 0.6, front - 0.25), 1.8, 0.8)
	port(m, CFrame.new(bottom.X, bottom.Y + 1.6, bottom.Z + bd / 2 + 0.2) * CFrame.Angles(0, math.pi, 0), 1.8, 1.0)
	-- two stacks on the roof
	stack(m, Vector3.new(bottom.X - 1.4, roof, bottom.Z + 1.3), 1.2, 3.6)
	stack(m, Vector3.new(bottom.X + 1.5, roof, bottom.Z + 1.3), 1.0, 2.8)
	-- the copper tank and its pipes on the right
	local tx, tz = bottom.X + bw / 2 + 1.25, bottom.Z - 1.2
	post(m, Vector3.new(tx, FLOOR, tz), 1.9, 3.2, "Copper")
	post(m, Vector3.new(tx, FLOOR + 2.4, tz), 2.04, 0.2, "Brass")
	ball(m, Vector3.new(tx, FLOOR + 3.2, tz), 1.8, "Copper")
	pipe(m, Vector3.new(tx, FLOOR + 3.9, tz), Vector3.new(tx, roof - 1.0, tz), 0.4)
	pipe(m, Vector3.new(tx, roof - 0.9, tz), Vector3.new(bottom.X + bw / 2 + 0.05, roof - 0.9, tz), 0.4)
	gauge(m, Vector3.new(tx, FLOOR + 1.6, tz - 0.95), -ZA, 0.7)
	-- a ladder up the left side and a rail along the roof's front
	local lx = bottom.X - bw / 2 - 0.35
	for _, sz in { -0.45, 0.45 } do
		post(m, Vector3.new(lx, FLOOR, bottom.Z + sz), 0.14, bh + 1.0, "Orange")
	end
	for k = 1, 5 do
		rod(m, Vector3.new(lx, FLOOR + k * 1.15, bottom.Z - 0.45), Vector3.new(lx, FLOOR + k * 1.15, bottom.Z + 0.45), 0.1, "Steel")
	end
	for _, sx in { -1, 1 } do
		post(m, Vector3.new(bottom.X + sx * (bw / 2 - 1.0), roof, front + 1.0), 0.12, 1.0, "Orange")
	end
	rod(
		m,
		Vector3.new(bottom.X - bw / 2 + 1.0, roof + 1.0, front + 1.0),
		Vector3.new(bottom.X + bw / 2 - 1.0, roof + 1.0, front + 1.0),
		0.12,
		"Orange"
	)
	-- wooden coke crates at the front left
	for i, at in { Vector3.new(-w / 2 + 1.1, 0, -d / 2 + 1.1), Vector3.new(-w / 2 + 1.0, 1.3, -d / 2 + 1.2) } do
		local crate = box(m, CFrame.new(at + UP * (FLOOR + 0.6)) * CFrame.Angles(0, i * 0.3, 0), Vector3.new(1.2, 1.2, 1.2), "Wood")
		planks(crate, Enum.NormalId.Front, 3)
		planks(crate, Enum.NormalId.Top, 3, true)
	end
	lamp(m, Vector3.new(w / 2 - 0.7, FLOOR, -d / 2 + 0.7))
	local _ = body
	return m
end

--[[
	Conveyor (1x1): a black belt with orange chevrons between steel rails
	with an orange top edge, on wooden legs (Base / Belt / RailL / RailR like
	the game's belts).
]]
local function conveyor(): Model
	local m = Instance.new("Model")
	m.Name = "Conveyor"
	m:SetAttribute("Look", "Works")
	local cell = GameConfig.CellSize
	local base = box(m, CFrame.new(0, 0.1, 0), Vector3.new(cell * 0.7, 0.2, cell), "SteelDark", "Base", { Transparency = 1 })
	m.PrimaryPart = base
	local beltY = 1.3
	local belt = box(m, CFrame.new(0, beltY, 0), Vector3.new(cell * 0.62, 0.2, cell), "Rubber", "Belt")
	paint(belt, Enum.NormalId.Top, {
		{ x = 0.42, y = 0.2, w = 0.16, h = 0.08, color = P.Orange },
		{ x = 0.42, y = 0.7, w = 0.16, h = 0.08, color = P.Orange },
	})
	for _, side in { -1, 1 } do
		local rail = box(
			m,
			CFrame.new(side * cell * 0.36, beltY + 0.1, 0),
			Vector3.new(0.3, 0.6, cell),
			"Steel",
			if side < 0 then "RailL" else "RailR"
		)
		paint(rail, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Orange } })
		box(m, CFrame.new(side * cell * 0.36, beltY / 2, 0), Vector3.new(0.35, beltY - 0.2, 0.35), "Wood")
	end
	return m
end

--[[
	Wind Turbine (2x2), a Hydroneer windmill: a tapered timber lattice tower
	with cross braces on a gearbox, a steel nacelle with an orange cap, a
	brass hub and three off-white blades with orange tips (Rotor), a tail
	vane.
]]
local function windTurbine(): Model
	local m, _, w, d = newModel("WindTurbine")
	local towerH = 8.5
	local baseHalf, topHalf = 2.4, 0.8
	local gearbox = box(m, CFrame.new(0, FLOOR + 0.6, 0), Vector3.new(2.2, 1.2, 2.2), "Steel")
	box(m, CFrame.new(0, FLOOR + 1.27, 0), Vector3.new(2.3, 0.14, 2.3), "Orange")
	controlPanel(gearbox, Enum.NormalId.Front, 0.1, 0.12)
	local corners = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local a = Vector3.new(sx * baseHalf, FLOOR, sz * baseHalf)
			local b = Vector3.new(sx * topHalf, FLOOR + towerH, sz * topHalf)
			local mid = (a + b) / 2
			box(m, CFrame.lookAt(mid, b) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(0.35, (b - a).Magnitude, 0.35), "Wood")
			table.insert(corners, { a = a, b = b })
		end
	end
	-- cross braces on the front and back faces
	for _, sz in { -1, 1 } do
		local y0, y1 = FLOOR + 1.0, FLOOR + towerH * 0.6
		local h0 = baseHalf - (baseHalf - topHalf) * (y0 - FLOOR) / towerH
		local h1 = baseHalf - (baseHalf - topHalf) * (y1 - FLOOR) / towerH
		local a, b = Vector3.new(-h0, y0, sz * h0), Vector3.new(h1, y1, sz * h1)
		box(m, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(0.2, (b - a).Magnitude, 0.2), "WoodDark")
		local c, e = Vector3.new(h0, y0, sz * h0), Vector3.new(-h1, y1, sz * h1)
		box(m, CFrame.lookAt((c + e) / 2, e) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(0.2, (e - c).Magnitude, 0.2), "WoodDark")
	end
	local topY = FLOOR + towerH
	local deck = box(m, CFrame.new(0, topY + 0.1, 0), Vector3.new(2.2, 0.25, 2.2), "Wood")
	planks(deck, Enum.NormalId.Top, 3, true)
	-- the nacelle, the hub and the blades (they face the front)
	box(m, CFrame.new(0, topY + 0.8, 0.2), Vector3.new(1.3, 1.1, 2.4), "Steel")
	box(m, CFrame.new(0, topY + 1.4, 0.2), Vector3.new(1.4, 0.15, 2.5), "Orange")
	local hubZ = -1.2
	rod(m, Vector3.new(0, topY + 0.8, hubZ + 0.3), Vector3.new(0, topY + 0.8, hubZ - 0.2), 0.9, "Brass", "Rotor")
	ball(m, Vector3.new(0, topY + 0.8, hubZ - 0.25), 0.6, "Orange")
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local dir = Vector3.new(math.sin(a), math.cos(a), 0)
		local across = Vector3.new(dir.Y, -dir.X, 0)
		local hub = Vector3.new(0, topY + 0.8, hubZ - 0.05)
		-- the blade lies in the rotor plane, turned a little like a sail
		local frame = CFrame.fromMatrix(hub, across, dir) * CFrame.Angles(0, 0.3, 0)
		box(m, frame * CFrame.new(0, 1.9, 0), Vector3.new(0.75, 3.0, 0.12), "Panel", "Blade")
		box(m, frame * CFrame.new(0, 3.65, 0), Vector3.new(0.78, 0.5, 0.14), "Orange")
	end
	-- the tail vane
	rod(m, Vector3.new(0, topY + 0.9, 1.4), Vector3.new(0, topY + 0.9, 3.0), 0.14, "SteelDark")
	box(m, CFrame.new(0, topY + 1.1, 3.1), Vector3.new(0.08, 1.2, 1.2), "Wood")
	local _ = corners
	local _ = w
	local _ = d
	return m
end

--[[
	Power Pole (1x1): a wooden pole on a concrete-grey foot with an iron
	brace, a timber cross arm with two white insulators and brass caps
	(CableL / CableR: where the cables hang, like the game's poles).
]]
local function powerPole(): Model
	local m = Instance.new("Model")
	m.Name = "PowerPole"
	m:SetAttribute("Look", "Works")
	local base = box(m, CFrame.new(0, 0.2, 0), Vector3.new(1.4, 0.4, 1.4), "SteelDark", "Base")
	m.PrimaryPart = base
	local h = 6.2
	post(m, Vector3.new(0, FLOOR, 0), 0.55, h, "Wood")
	post(m, Vector3.new(0, FLOOR, 0), 0.9, 0.7, "SteelDark")
	box(m, CFrame.new(0, FLOOR + h - 0.6, 0), Vector3.new(2.8, 0.3, 0.35), "WoodDark")
	for _, sx in { -1, 1 } do
		local at = Vector3.new(sx * 1.1, FLOOR + h - 0.45, 0)
		post(m, at, 0.28, 0.45, "Panel")
		post(m, at + UP * 0.45, 0.2, 0.12, "Brass", if sx < 0 then "CableL" else "CableR")
		rod(m, Vector3.new(sx * 0.9, FLOOR + h - 0.75, 0), Vector3.new(0, FLOOR + h - 1.5, 0), 0.08, "Steel")
	end
	return m
end

local BUILDERS: { [string]: () -> Model } = {
	ClayFurnace = clayFurnace,
	Crusher = crusher,
	CleaningStation = cleaningStation,
	BlastFurnace = blastFurnace,
	Conveyor = conveyor,
	WindTurbine = windTurbine,
	PowerPole = powerPole,
}

-- The machines the concept has so far (in gallery order).
WorksMachines.Concept = { "CleaningStation", "ClayFurnace", "Crusher", "BlastFurnace", "Conveyor", "WindTurbine", "PowerPole" }

function WorksMachines.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

function WorksMachines.build(id: string): Model
	local builder = BUILDERS[id]
	assert(builder, "WorksMachines has no " .. id)
	return builder()
end

return WorksMachines
