--[[
	Style exploration (owner 2026-10-17: "better, a cute and at the same time
	cool look, like the new games have"): the Clay Furnace in three styles so
	the owner can pick the direction before every machine is redone.
	  A "Soft"  rounded, chunky toy shapes: a soft box body (every top and
	            upright edge rounded), pill-cornered plinth and lid, an arched
	            glowing door, a fat chimney, a round bowl hopper, a capsule tank
	            with a glowing porthole; cream white with slate and orange.
	  B "Bot"   A with a face: two round eye screens over the glowing door
	            (the mouth), pink cheeks, an antenna with a glowing ball.
	  C "Cool"  the same rounded shapes in dark graphite with cyan glow.
	Same contract as MachineBuilder (Base, Output, Prompt, Intake, Status,
	Glow, ChimneyTop) and the Kit colour roles of KitMachines, so the chosen
	style can replace KitMachines' look.
]]

local Geo = require(script.Parent.Geo)
local Grid = require(script.Parent.Parent.Machines.Grid)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local CuteMachines = {}

type Props = { [string]: any }
type Palette = { [string]: Color3 }
type Style = { name: string, palette: Palette, face: boolean, cool: boolean }

local rgb = Color3.fromRGB
local UP = Vector3.yAxis
local XA = Vector3.xAxis
local ZA = Vector3.zAxis
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local FLOOR = 0.3

local SOFT: Palette = {
	Body = rgb(232, 226, 214),
	Frame = rgb(72, 84, 122),
	Pipe = rgb(88, 100, 138),
	Dark = rgb(36, 40, 60),
	Trim = rgb(255, 146, 52),
	Neon = rgb(255, 150, 50),
	Glow = rgb(255, 132, 30),
	Hot = rgb(255, 218, 110),
	Eye = rgb(80, 232, 232),
	Cheek = rgb(255, 150, 170),
	Screen = rgb(24, 30, 48),
	Floor = rgb(60, 66, 92),
}
local COOL: Palette = {
	Body = rgb(64, 70, 102),
	Frame = rgb(36, 40, 62),
	Pipe = rgb(48, 54, 82),
	Dark = rgb(18, 20, 32),
	Trim = rgb(255, 146, 52),
	Neon = rgb(60, 226, 255),
	Glow = rgb(255, 132, 30),
	Hot = rgb(255, 218, 110),
	Eye = rgb(60, 226, 255),
	Cheek = rgb(255, 150, 170),
	Screen = rgb(14, 18, 30),
	Floor = rgb(30, 34, 52),
}

CuteMachines.Styles = {
	A = { name = "Soft", palette = SOFT, face = false, cool = false },
	B = { name = "Bot", palette = SOFT, face = true, cool = false },
	C = { name = "Cool", palette = COOL, face = false, cool = true },
} :: { [string]: Style }

local MATERIAL: { [string]: Enum.Material } = { Neon = NEON, Glow = NEON, Hot = NEON, Eye = NEON }
local SOLID: Props = { CanTouch = false }
local PROP: Props = { CanTouch = false, CanQuery = false, CanCollide = false }
local TINY: Props = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }

type Ctx = { model: Model, base: BasePart, pal: Palette, style: Style }

local function style(ctx: Ctx, part: BasePart, role: string, flags: Props?, name: string?): BasePart
	part:SetAttribute("Kit", role)
	local color = ctx.pal[role]
	if color then
		part.Color = color
	end
	part.Material = MATERIAL[role] or SMOOTH
	-- a little shine on the big painted shapes (toy look)
	if role == "Body" or role == "Frame" or role == "Trim" then
		part.Reflectance = 0.04
	end
	for key, value in flags or SOLID do
		(part :: any)[key] = value
	end
	if name then
		part.Name = name
	end
	return part
end

local function block(ctx: Ctx, cf: CFrame, size: Vector3, role: string, flags: Props?, name: string?): BasePart
	return style(ctx, Geo.make("Part", { CFrame = cf, Size = size }, ctx.model), role, flags, name)
end

local function along(pos: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) < 0.95 then UP else ZA
	local z = x:Cross(ref).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(pos, x, y, z)
end

-- Cylinder along `dir`; `d2` makes it an oval (height across, d = width across).
local function cyl(
	ctx: Ctx,
	center: Vector3,
	dir: Vector3,
	length: number,
	d: number,
	role: string,
	flags: Props?,
	name: string?,
	d2: number?
): BasePart
	local part = Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = along(center, dir),
		Size = Vector3.new(length, d2 or d, d),
	}, ctx.model)
	return style(ctx, part, role, flags, name)
end

local function ball(ctx: Ctx, center: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	local part = Geo.make("Part", { Shape = Enum.PartType.Ball, CFrame = CFrame.new(center), Size = Vector3.new(d, d, d) }, ctx.model)
	return style(ctx, part, role, flags or PROP, name)
end

local function rod(ctx: Ctx, a: Vector3, b: Vector3, d: number, role: string, flags: Props?, name: string?): BasePart
	return cyl(ctx, (a + b) / 2, b - a, (b - a).Magnitude, d, role, flags, name)
end

--[[
	Soft box standing on `bottom` (front = -Z): all four upright edges and all
	top edges rounded with radius `r`, corners are balls. 15 parts.
]]
local function softBox(ctx: Ctx, bottom: Vector3, w: number, h: number, d: number, r: number, role: string, name: string?): BasePart
	local lower = h - r
	local main = block(ctx, CFrame.new(bottom + Vector3.new(0, lower / 2, 0)), Vector3.new(w, lower, d - 2 * r), role, SOLID, name)
	block(ctx, CFrame.new(bottom + Vector3.new(0, lower / 2, 0)), Vector3.new(w - 2 * r, lower, d), role, SOLID)
	block(ctx, CFrame.new(bottom + Vector3.new(0, h - r / 2, 0)), Vector3.new(w - 2 * r, r, d - 2 * r), role, SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = bottom + Vector3.new(sx * (w / 2 - r), 0, sz * (d / 2 - r))
			cyl(ctx, corner + Vector3.new(0, lower / 2, 0), UP, lower, 2 * r, role, SOLID)
			ball(ctx, corner + Vector3.new(0, lower, 0), 2 * r, role, SOLID)
		end
		cyl(ctx, bottom + Vector3.new(sx * (w / 2 - r), lower, 0), ZA, d - 2 * r, 2 * r, role, SOLID)
	end
	for _, sz in { -1, 1 } do
		cyl(ctx, bottom + Vector3.new(0, lower, sz * (d / 2 - r)), XA, w - 2 * r, 2 * r, role, SOLID)
	end
	return main
end

-- Slab with rounded upright corners (a pill-cornered plate). 6 parts.
local function pillSlab(ctx: Ctx, bottom: Vector3, w: number, h: number, d: number, r: number, role: string, name: string?): BasePart
	local c = bottom + Vector3.new(0, h / 2, 0)
	local main = block(ctx, CFrame.new(c), Vector3.new(w, h, d - 2 * r), role, SOLID, name)
	block(ctx, CFrame.new(c), Vector3.new(w - 2 * r, h, d), role, SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(ctx, c + Vector3.new(sx * (w / 2 - r), 0, sz * (d / 2 - r)), UP, h, 2 * r, role, SOLID)
		end
	end
	return main
end

-- An arch (a block with a half circle on top) standing on `bottom`, `z` thick along Z. 2 parts.
local function arch(ctx: Ctx, bottom: Vector3, w: number, straight: number, z: number, role: string, flags: Props?, name: string?): BasePart
	local part = block(ctx, CFrame.new(bottom + Vector3.new(0, straight / 2, 0)), Vector3.new(w, straight, z), role, flags, name)
	cyl(ctx, bottom + Vector3.new(0, straight, 0), ZA, z, w, role, flags, name)
	return part
end

local function attach(base: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = base
	return a
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function smoke(parent: Instance)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(rgb(236, 236, 240))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 4.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(2.5, 4)
	e.Rate = 2
	e.Parent = parent
end

--[[
	Arched glowing door on the front face at `z` (bottom centre `x`, `y0`):
	an orange frame, a dark ring, the glow and a hot core, grate bars.
]]
local function door(ctx: Ctx, x: number, y0: number, z: number, w: number, straight: number)
	arch(ctx, Vector3.new(x, y0, z - 0.2), w + 0.7, straight, 0.4, "Trim", SOLID)
	arch(ctx, Vector3.new(x, y0, z - 0.42), w + 0.2, straight, 0.06, "Dark", TINY)
	local glow = arch(ctx, Vector3.new(x, y0, z - 0.46), w, straight, 0.06, "Glow", TINY, "Glow")
	arch(ctx, Vector3.new(x, y0 + 0.25, z - 0.5), w * 0.55, straight * 0.7, 0.04, "Hot", TINY, "GlowCore")
	for i = -1, 1 do
		block(ctx, CFrame.new(x + i * w * 0.28, y0 + 0.3, z - 0.56), Vector3.new(0.2, 0.6, 0.1), "Dark", TINY)
	end
	block(ctx, CFrame.new(x, y0 + 0.55, z - 0.56), Vector3.new(w * 0.95, 0.14, 0.1), "Dark", TINY)
	light(glow, ctx.pal.Glow, 8, 0.7)
end

-- Round eye screen facing -Z at `center`: frame ring, dark screen, glowing oval pupil, white glint.
local function eye(ctx: Ctx, center: Vector3, d: number)
	cyl(ctx, center + Vector3.new(0, 0, 0.05), ZA, 0.24, d * 1.22, "Frame", TINY)
	cyl(ctx, center + Vector3.new(0, 0, -0.1), ZA, 0.06, d, "Screen", TINY)
	cyl(ctx, center + Vector3.new(0, d * 0.04, -0.14), ZA, 0.04, d * 0.5, "Eye", TINY, "Pupil", d * 0.66)
	local glint = cyl(ctx, center + Vector3.new(-d * 0.12, d * 0.2, -0.17), ZA, 0.03, d * 0.16, "Eye", TINY, "Glint")
	glint.Color = Color3.new(1, 1, 1)
end

local function newModel(id: string, s: Style): Ctx
	local machine = MachineData.ById[id]
	local w, d = machine.Size[1] * GameConfig.CellSize, machine.Size[2] * GameConfig.CellSize
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("MachineId", id)
	model:SetAttribute("Style", s.name)
	local ctx: Ctx = { model = model, base = nil :: any, pal = s.palette, style = s }
	ctx.base = block(ctx, CFrame.new(0, FLOOR / 2, 0), Vector3.new(w - 0.3, FLOOR, d - 0.3), "Floor", SOLID, "Base")
	model.PrimaryPart = ctx.base :: any
	return ctx
end

--[[
	The Clay Furnace in style `key` (A / B / C): a soft box body on a pill
	plinth with a glowing strip, a pill lid, the arched glowing door, a fat
	chimney, a bowl hopper, a capsule tank with a porthole whose pipe bends
	into the body, a chute to the output; B adds the face and the antenna,
	C adds glowing corner bars.
]]
function CuteMachines.furnace(key: string): Model
	local s = CuteMachines.Styles[key] or CuteMachines.Styles.A
	local ctx = newModel("ClayFurnace", s)
	local hx, hz, w, h, d = 0.25, -0.1, 5.8, 4.4, 5.4
	local plinthH = 0.7
	pillSlab(ctx, Vector3.new(hx, FLOOR, hz), w + 0.6, plinthH, d + 0.6, 0.7, "Frame")
	local front = hz - d / 2
	for _, side in { -1, 1 } do
		block(ctx, CFrame.new(hx, FLOOR + plinthH / 2, hz + side * (d / 2 + 0.32)), Vector3.new(w - 1.2, 0.16, 0.06), "Neon", TINY)
		block(ctx, CFrame.new(hx + side * (w / 2 + 0.32), FLOOR + plinthH / 2, hz), Vector3.new(0.06, 0.16, d - 1.2), "Neon", TINY)
	end
	local bodyY = FLOOR + plinthH
	softBox(ctx, Vector3.new(hx, bodyY, hz), w, h, d, 1.0, "Body", "Body")
	local top = bodyY + h
	pillSlab(ctx, Vector3.new(hx, top - 0.15, hz), w - 1.6, 0.45, d - 1.6, 0.6, "Frame")
	local lidTop = top + 0.3
	-- the arched door (the mouth when there is a face)
	local doorX = if s.face then hx else 0.75
	door(ctx, doorX, bodyY + 0.15, front, 2.2, 1.3)
	if s.face then
		for _, side in { -1, 1 } do
			eye(ctx, Vector3.new(doorX + side * 1.35, bodyY + 3.25, front - 0.05), 1.05)
			local cheek =
				cyl(ctx, Vector3.new(doorX + side * 2.05, bodyY + 2.55, front - 0.03), ZA, 0.04, 0.55, "Cheek", TINY, "Cheek", 0.34)
			cheek.Transparency = 0.25
		end
		local antennaFoot = Vector3.new(hx + 1.3, lidTop, hz + 0.6)
		cyl(ctx, antennaFoot + Vector3.new(0, 0.1, 0), UP, 0.2, 0.6, "Frame", TINY)
		rod(ctx, antennaFoot, antennaFoot + Vector3.new(0, 1.5, 0), 0.14, "Frame", TINY)
		ball(ctx, antennaFoot + Vector3.new(0, 1.65, 0), 0.5, "Eye", TINY, "AntennaBall")
	end
	if s.cool then
		for _, side in { -1, 1 } do
			block(
				ctx,
				CFrame.new(hx + side * (w / 2 - 0.15), bodyY + h / 2 - 0.3, front - 0.02),
				Vector3.new(0.14, h - 2.0, 0.06),
				"Neon",
				TINY
			)
		end
		block(ctx, CFrame.new(hx, top - 0.05, front + 0.85), Vector3.new(w - 2.2, 0.1, 0.06), "Neon", TINY)
	end
	-- fat chimney at the back left with a round cap and a dark mouth
	local cx, cz = hx - 1.25, hz + 1.1
	cyl(ctx, Vector3.new(cx, lidTop + 0.25, cz), UP, 0.5, 2.1, "Frame", SOLID)
	local stackH = 2.3
	cyl(ctx, Vector3.new(cx, lidTop + 0.5 + stackH / 2, cz), UP, stackH, 1.5, "Pipe", SOLID)
	cyl(ctx, Vector3.new(cx, lidTop + 0.5 + stackH * 0.4, cz), UP, 0.3, 1.62, "Trim", TINY)
	local capY = lidTop + 0.5 + stackH
	cyl(ctx, Vector3.new(cx, capY + 0.22, cz), UP, 0.45, 2.05, "Frame", SOLID)
	cyl(ctx, Vector3.new(cx, capY + 0.22, cz), UP, 0.14, 2.12, "Neon", TINY)
	local mouth = cyl(ctx, Vector3.new(cx, capY + 0.46, cz), UP, 0.04, 1.3, "Dark", TINY, "ChimneyTop")
	smoke(mouth)
	-- bowl hopper on the lid, front right (back right when there is a face)
	local bx, bz = hx + 1.25, if s.face then hz + 1.0 else hz - 0.5
	cyl(ctx, Vector3.new(bx, lidTop + 0.25, bz), UP, 0.5, 1.3, "Frame", SOLID)
	cyl(ctx, Vector3.new(bx, lidTop + 0.85, bz), UP, 0.8, 2.3, "Body", SOLID)
	cyl(ctx, Vector3.new(bx, lidTop + 1.27, bz), UP, 0.26, 2.5, "Trim", SOLID)
	cyl(ctx, Vector3.new(bx, lidTop + 1.41, bz), UP, 0.04, 1.85, "Dark", TINY)
	-- capsule tank on the left with a glowing porthole; its pipe bends into the body
	local tx, tz = hx - w / 2 - 0.55, hz + 0.9
	local tankD, tankH = 1.5, 2.2
	cyl(ctx, Vector3.new(tx, FLOOR + 0.15, tz), UP, 0.3, tankD + 0.2, "Frame", PROP)
	cyl(ctx, Vector3.new(tx, FLOOR + 0.3 + tankH / 2, tz), UP, tankH, tankD, "Pipe", SOLID, "Tank")
	ball(ctx, Vector3.new(tx, FLOOR + 0.3 + tankH, tz), tankD, "Pipe", SOLID)
	cyl(ctx, Vector3.new(tx, FLOOR + 0.3 + tankH * 0.2, tz), UP, 0.24, tankD + 0.08, "Trim", TINY)
	cyl(ctx, Vector3.new(tx, FLOOR + 0.3 + tankH, tz), UP, 0.2, tankD + 0.06, "Trim", TINY)
	local port = Vector3.new(tx, FLOOR + 0.3 + tankH * 0.55, tz - tankD / 2)
	cyl(ctx, port, ZA, 0.16, 0.85, "Frame", TINY)
	cyl(ctx, port - ZA * 0.06, ZA, 0.06, 0.6, "Neon", TINY, "TankGlow")
	local p0 = Vector3.new(tx, FLOOR + 0.3 + tankH + tankD / 2, tz)
	local r = 0.5
	rod(ctx, p0 - UP * 0.1, p0 + UP * 0.3, 0.55, "Pipe", PROP)
	local center = p0 + UP * 0.3 + XA * r
	local prev = p0 + UP * 0.3
	for i = 1, 3 do
		local th = i * math.pi / 6
		local nextP = center - XA * (r * math.cos(th)) + UP * (r * math.sin(th))
		rod(ctx, prev, nextP, 0.55, "Pipe", PROP)
		if i < 3 then
			ball(ctx, nextP, 0.55, "Pipe", PROP)
		end
		prev = nextP
	end
	rod(ctx, prev, Vector3.new(hx - w / 2 + 0.3, prev.Y, tz), 0.55, "Pipe", PROP)
	cyl(ctx, Vector3.new(hx - w / 2 - 0.05, prev.Y, tz), XA, 0.24, 0.8, "Trim", TINY)
	cyl(ctx, prev + XA * 0.1, XA, 0.22, 0.72, "Trim", TINY)
	-- chute from the door to the output
	local outPos = Grid.outputLocal("ClayFurnace") :: Vector3
	local a, b = Vector3.new(doorX, bodyY + 0.2, front - 0.55), Vector3.new(outPos.X, outPos.Y - 0.3, outPos.Z + 0.3)
	local cf = CFrame.lookAt((a + b) / 2, b)
	block(ctx, cf, Vector3.new(1.3, 0.2, (b - a).Magnitude), "Dark", PROP, "Chute")
	for _, side in { -1, 1 } do
		block(ctx, cf * CFrame.new(side * 0.72, 0.15, 0), Vector3.new(0.16, 0.45, (b - a).Magnitude), "Trim", TINY, "ChuteLip")
	end

	attach(ctx.base, "Output", CFrame.new(outPos))
	attach(ctx.base, "Prompt", CFrame.new(0, 2.5, -3.6))
	local intake = attach(ctx.base, "Intake", CFrame.new(0, 4.5, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7, 9, 6))
	local topY = 0
	for _, part in ctx.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			local pcf, size = part.CFrame, part.Size
			local _, _, _, _, _, _, r10, r11, r12 = pcf:GetComponents()
			topY = math.max(topY, pcf.Position.Y + math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2)
		end
	end
	attach(ctx.base, "Status", CFrame.new(0, topY - FLOOR / 2 + 1.5, 0))
	return ctx.model
end

return CuteMachines
