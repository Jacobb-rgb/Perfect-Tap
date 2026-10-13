--[[
	Machine models (pure builders, used by the server and for build-mode ghosts).

	Local space: origin = footprint center on the plot surface, front = -Z
	(LookVector). Every model has a PrimaryPart "Base" with Attachments:
	  Intake   center of the hopper's intake box (attribute IntakeSize: Vector3)
	  Output   where results are pushed out, at Grid.outputLocal (a cell
	           centre column, 0.5 studs in front of the footprint)
	  Prompt   where ProximityPrompts go
	  Status   above the model (machine billboards)
	  OrePoint / CamPoint   (Cleaning Station close-up; its Output is the tray)
	  AnvilPoint / CamPoint / IngotSlot1..4   (Anvil)
	Conveyors are 6 parts: Base, Belt (tag ConveyorBelt), RailL, RailR, 2x Arrow.
	Moving parts are named so the client can animate them (Roller, Drum, Glow).
]]

local Geo = require(script.Parent.Geo)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Grid = require(script.Parent.Parent.Machines.Grid)

local MachineBuilder = {}

local rgb = Color3.fromRGB
local C = {
	Stone = rgb(120, 112, 108),
	StoneDark = rgb(78, 72, 72),
	Wood = rgb(150, 100, 58),
	WoodLight = rgb(196, 144, 92),
	WoodDark = rgb(100, 64, 38),
	Metal = rgb(80, 82, 92),
	MetalLight = rgb(150, 154, 164),
	Clay = rgb(196, 112, 70),
	ClayDark = rgb(150, 80, 50),
	Brick = rgb(150, 70, 50),
	Glow = rgb(255, 130, 40),
	Gold = rgb(255, 196, 72),
	Teal = rgb(70, 160, 160),
	Belt = rgb(46, 42, 44),
	Arrow = rgb(255, 196, 80),
	Cloth = rgb(240, 222, 190),
}

local function solid(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
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

local function attach(base: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = base
	return a
end

-- Output attachment at the shared grid position; returns it so lips and
-- chutes can line up with it.
local function output(base: BasePart, id: string): Vector3
	local position = Grid.outputLocal(id) :: Vector3
	attach(base, "Output", CFrame.new(position))
	return position
end

local function light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function emitter(parent: Instance, kind: string, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = kind
	if kind == "Smoke" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(3, 5)
		e.SpreadAngle = Vector2.new(10, 10)
		e.LightInfluence = 1
	else -- Embers
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.LightEmission = 1
		e.LightInfluence = 0
	end
	e.Rate = rate
	e.Parent = parent
	return e
end

local function newModel(id: string): (Model, Part)
	local machine = MachineData.ById[id]
	local w, d = machine.Size[1] * GameConfig.CellSize, machine.Size[2] * GameConfig.CellSize
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("MachineId", id)
	local base = Geo.block(model, CFrame.new(0, 0.15, 0), Vector3.new(w - 0.3, 0.3, d - 0.3), C.StoneDark, nil, solid({ Name = "Base" }))
	base.Name = "Base"
	model.PrimaryPart = base
	return model, base
end

local function sign(parent: Instance, cf: CFrame, text: string, width: number)
	local board = Geo.block(parent, cf, Vector3.new(width, 0.7, 0.15), C.WoodDark, nil, decor())
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = C.Gold
	label.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
	label.Parent = gui
	return board
end

local function funnel(parent: Instance, center: Vector3, topSize: number, height: number, color: Color3)
	-- four wedges forming an open hopper (the opening is in the middle)
	for i = 0, 3 do
		local rot = CFrame.new(center) * CFrame.Angles(0, i * math.pi / 2, 0)
		Geo.wedge(parent, rot * CFrame.new(0, 0, topSize / 2 - 0.4) * CFrame.Angles(0, math.pi, 0), Vector3.new(topSize, height, 0.8), color, nil, solid())
	end
end

---------------------------------------------------------------- machines

local function cleaningStation(): Model
	local model, base = newModel("CleaningStation")
	base.Color = C.Stone
	local top = 3.4
	-- bench
	Geo.block(model, CFrame.new(0, top, 0.4), Vector3.new(10.4, 0.6, 5.2), C.WoodLight, nil, solid({ Name = "Bench" }))
	Geo.block(model, CFrame.new(0, top - 0.45, 0.4), Vector3.new(10.6, 0.3, 5.4), C.WoodDark, nil, solid())
	for _, x in { -4.7, 4.7 } do
		for _, z in { -1.7, 2.5 } do
			Geo.block(model, CFrame.new(x, top / 2, z), Vector3.new(0.7, top, 0.7), C.WoodDark, nil, solid())
		end
	end
	Geo.block(model, CFrame.new(0, 1, 2.5), Vector3.new(9.4, 0.3, 0.4), C.WoodDark, nil, solid())
	-- stone work slab + vise
	Geo.block(model, CFrame.new(0, top + 0.5, 0.3), Vector3.new(4.4, 0.4, 3.6), C.StoneDark, nil, solid({ Name = "WorkSlab" }))
	for _, x in { -1.75, 1.75 } do
		Geo.block(model, CFrame.new(x, top + 0.95, 0.3), Vector3.new(0.45, 0.5, 2), C.Metal, Enum.Material.Metal, solid({ Name = "Jaw" }))
	end
	Geo.cylinder(model, Vector3.new(-2.5, top + 0.95, 0.3), 0.4, 0.4, C.MetalLight, Enum.Material.Metal, decor())
	Geo.block(model, CFrame.new(-2.8, top + 0.95, 0.3) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.16, 1.4, 0.16), C.MetalLight, Enum.Material.Metal, decor())
	-- tool rack at the back left: chisel, hammer, brush, cloth
	Geo.block(model, CFrame.new(-3.6, top + 1.8, 2.75), Vector3.new(3.4, 2.6, 0.25), C.WoodDark, nil, solid())
	Geo.block(model, CFrame.new(-4.6, top + 1.9, 2.55), Vector3.new(0.2, 1.4, 0.2), C.MetalLight, Enum.Material.Metal, decor())
	Geo.wedge(model, CFrame.new(-4.6, top + 1.05, 2.55) * CFrame.Angles(math.pi, 0, 0), Vector3.new(0.2, 0.3, 0.2), C.MetalLight, Enum.Material.Metal, decor())
	Geo.block(model, CFrame.new(-3.7, top + 1.9, 2.55), Vector3.new(0.25, 1.6, 0.25), C.Wood, nil, decor())
	Geo.block(model, CFrame.new(-3.7, top + 2.7, 2.55), Vector3.new(0.9, 0.45, 0.45), C.Metal, Enum.Material.Metal, decor())
	Geo.block(model, CFrame.new(-2.8, top + 2.2, 2.55), Vector3.new(0.6, 0.9, 0.3), C.Wood, nil, decor())
	Geo.block(model, CFrame.new(-2.8, top + 1.6, 2.55), Vector3.new(0.7, 0.4, 0.35), rgb(70, 50, 40), nil, decor())
	-- lamp (upper right, out of the close-up camera's view)
	Geo.block(model, CFrame.new(3.9, top + 2.5, 2.4), Vector3.new(0.35, 5, 0.35), C.Metal, Enum.Material.Metal, solid())
	Geo.block(model, CFrame.new(3.3, top + 4.9, 1.9) * CFrame.Angles(0, math.rad(40), 0), Vector3.new(1.6, 0.25, 0.25), C.Metal, Enum.Material.Metal, decor())
	local shade = Geo.block(model, CFrame.new(2.7, top + 4.5, 1.4), Vector3.new(1.3, 0.6, 1.3), rgb(60, 110, 90), nil, decor())
	shade.Name = "LampShade"
	local bulb = Geo.ball(model, Vector3.new(2.7, top + 4.1, 1.4), 0.55, rgb(255, 222, 150), Enum.Material.Neon, decor())
	bulb.Name = "LampBulb"
	light(bulb, rgb(255, 214, 160), 14, 1.6)
	-- output tray on the right
	Geo.block(model, CFrame.new(3.6, top + 0.45, -0.4), Vector3.new(2.6, 0.3, 2.6), C.WoodDark, nil, solid({ Name = "Tray" }))
	for _, off in { Vector3.new(0, 0, 1.25), Vector3.new(0, 0, -1.25) } do
		Geo.block(model, CFrame.new(Vector3.new(3.6, top + 0.8, -0.4) + off), Vector3.new(2.6, 0.5, 0.15), C.Wood, nil, solid())
	end
	for _, off in { Vector3.new(1.25, 0, 0), Vector3.new(-1.25, 0, 0) } do
		Geo.block(model, CFrame.new(Vector3.new(3.6, top + 0.8, -0.4) + off), Vector3.new(0.15, 0.5, 2.6), C.Wood, nil, solid())
	end
	sign(model, CFrame.new(0, top - 0.75, -2.32), "CLEANING STATION", 4.6)

	local orePoint = CFrame.new(0, top + 1.95, 0.3)
	attach(base, "OrePoint", orePoint)
	-- close-up camera: in front and above, looking down at about 35 degrees
	attach(base, "CamPoint", CFrame.lookAt(Vector3.new(0, top + 5.4, -4.6), orePoint.Position + Vector3.new(0, 0.1, 0)))
	attach(base, "Output", CFrame.new(3.6, top + 1.4, -0.4))
	attach(base, "Prompt", CFrame.new(0, top + 0.6, -2.4))
	local intake = attach(base, "Intake", orePoint)
	intake:SetAttribute("IntakeSize", Vector3.new(3.4, 2.6, 3.4))
	return model
end

local function storageCrate(): Model
	local model, base = newModel("StorageCrate")
	base.Color = C.WoodDark
	local body = Geo.block(model, CFrame.new(0, 2.3, 0.2), Vector3.new(6.2, 4, 6.2), C.Wood, nil, solid({ Name = "Body" }))
	for _, y in { 0.9, 3.7 } do
		Geo.block(model, CFrame.new(0, y, 0.2), Vector3.new(6.4, 0.45, 6.4), C.WoodDark, nil, solid())
	end
	for _, x in { -3, 3 } do
		for _, z in { -2.8, 3.2 } do
			Geo.block(model, CFrame.new(x, 2.3, z), Vector3.new(0.5, 4.2, 0.5), C.Metal, Enum.Material.Metal, decor())
		end
	end
	-- open lid leaning back
	Geo.block(model, CFrame.new(0, 5.2, 3.6) * CFrame.Angles(math.rad(-65), 0, 0), Vector3.new(6.2, 0.4, 3), C.WoodLight, nil, solid())
	-- dark inside
	Geo.block(model, CFrame.new(0, 4.32, 0.2), Vector3.new(5.6, 0.05, 5.6), rgb(50, 34, 24), nil, decor())
	local label = sign(model, CFrame.new(0, 2.6, -2.98), "0/60", 3)
	label.Name = "CountSign"
	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	output(base, "StorageCrate")
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.2))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 2.4, 6))
	local _ = body
	return model
end

local function furnace(id: string, scale: number): Model
	local model, base = newModel(id)
	base.Color = C.StoneDark
	local s = scale
	local clay = if id == "BlastFurnace" then C.Brick else C.Clay
	local clayDark = if id == "BlastFurnace" then rgb(110, 50, 36) else C.ClayDark
	Geo.block(model, CFrame.new(0, 0.7 * s, 0.3), Vector3.new(6.6, 1.1, 6.6) * Vector3.new(s, 1, s), C.Stone, nil, solid())
	Geo.block(model, CFrame.new(0, 2.6 * s, 0.4), Vector3.new(6, 3 * s, 6) * Vector3.new(s, 1, s), clay, nil, solid({ Name = "Body" }))
	Geo.block(model, CFrame.new(0, 4.7 * s, 0.6), Vector3.new(4.8, 1.6 * s, 4.8) * Vector3.new(s, 1, s), clayDark, nil, solid())
	Geo.block(model, CFrame.new(0, 5.9 * s, 0.8), Vector3.new(3.2, 1.2 * s, 3.2) * Vector3.new(s, 1, s), clay, nil, solid())
	-- chimney
	local chimney = Geo.block(model, CFrame.new(1.3 * s, 7.6 * s, 1.8 * s), Vector3.new(1.4, 3 * s, 1.4) * Vector3.new(s, 1, s), C.StoneDark, nil, solid())
	local top = Geo.block(model, CFrame.new(1.3 * s, 9.15 * s, 1.8 * s), Vector3.new(1.5 * s, 0.15, 1.5 * s), C.Glow, Enum.Material.Neon, decor({ Name = "ChimneyTop" }))
	emitter(top, "Smoke", rgb(110, 100, 96), if id == "BlastFurnace" then 5 else 2)
	-- glowing mouth, moved toward the output column but kept on the body
	local out = output(base, id)
	local mouthX = math.clamp(out.X, -1.4 * s, 1.4 * s)
	Geo.block(model, CFrame.new(mouthX, 2.3 * s, -2.65 * s), Vector3.new(3.2 * s, 2.6 * s, 0.4), C.StoneDark, nil, solid())
	local glow = Geo.block(model, CFrame.new(mouthX, 2.2 * s, -2.75 * s), Vector3.new(2.4 * s, 1.8 * s, 0.25), C.Glow, Enum.Material.Neon, decor({ Name = "Glow" }))
	light(glow, C.Glow, 12 * s, 1.2)
	emitter(glow, "Embers", C.Glow, 2)
	-- output lip leading to the Output point
	Geo.block(model, CFrame.new(out.X, 1.15, out.Z + 1.4), Vector3.new(2.4 * s, 0.3, 1.8), C.Metal, Enum.Material.Metal, solid())
	-- hopper on top
	funnel(model, Vector3.new(0, 7.2 * s, 0.8), 3 * s, 1.2, C.Metal)
	sign(model, CFrame.new(0, 4.1 * s, -2.62 * s), if id == "BlastFurnace" then "BLAST FURNACE" else "FURNACE", 3.6 * s)
	attach(base, "Prompt", CFrame.new(0, 2.5, -3.6 * s))
	local intake = attach(base, "Intake", CFrame.new(0, 4.5 * s, 1.2))
	intake:SetAttribute("IntakeSize", Vector3.new(7 * s, 9 * s, 6 * s))
	local _ = chimney
	return model
end

local function crusher(): Model
	local model, base = newModel("Crusher")
	base.Color = C.StoneDark
	Geo.block(model, CFrame.new(0, 2, 0.4), Vector3.new(6, 3.4, 5.6), C.Metal, Enum.Material.Metal, solid({ Name = "Body" }))
	for _, x in { -3.05, 3.05 } do
		Geo.block(model, CFrame.new(x, 2, 0.4), Vector3.new(0.3, 3.8, 6), rgb(210, 160, 50), nil, solid())
	end
	-- rollers (client spins them while working)
	for i, z in { -0.4, 1.2 } do
		local roller = Geo.cylinder(model, Vector3.new(0, 4.1, z + 0.4), 5.2, 1.6, C.MetalLight, Enum.Material.Metal, decor({ Name = "Roller" .. i }))
		roller.CFrame = CFrame.new(0, 4.1, z + 0.4)
		-- teeth
		for k = 0, 3 do
			Geo.block(model, CFrame.new(0, 4.1, z + 0.4) * CFrame.Angles(k * math.pi / 4, 0, 0), Vector3.new(5.1, 1.9, 0.25), C.Metal, Enum.Material.Metal, decor({ Name = "Roller" .. i .. "Tooth" }))
		end
	end
	funnel(model, Vector3.new(0, 5.6, 0.8), 5.4, 2, rgb(210, 160, 50))
	-- warning stripes
	for i = -2, 2 do
		Geo.block(model, CFrame.new(i * 1.1, 0.6, -2.42) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.4, 1, 0.05), if i % 2 == 0 then C.Belt else rgb(240, 190, 40), nil, decor())
	end
	-- output chute
	local out = output(base, "Crusher")
	Geo.wedge(model, CFrame.new(out.X, 1.2, out.Z + 1.3) * CFrame.Angles(0, math.pi, 0), Vector3.new(2.2, 0.8, 1.6), C.MetalLight, Enum.Material.Metal, solid())
	sign(model, CFrame.new(0, 2.8, -2.42), "CRUSHER", 3)
	attach(base, "Prompt", CFrame.new(0, 2.5, -3.2))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6.6, 6, 6.2))
	return model
end

local function anvil(): Model
	local model, base = newModel("Anvil")
	base.Color = C.Stone
	Geo.cylinder(model, Vector3.new(0, 1.3, 0.3), 2.4, 3.6, C.WoodDark, nil, solid({ Name = "Stump" }))
	Geo.cylinder(model, Vector3.new(0, 2.55, 0.3), 0.15, 3.7, C.Wood, nil, decor())
	Geo.block(model, CFrame.new(0, 3, 0.3), Vector3.new(2.6, 0.7, 2), C.Metal, Enum.Material.Metal, solid())
	Geo.block(model, CFrame.new(0, 3.65, 0.3), Vector3.new(1.4, 0.7, 1.3), C.Metal, Enum.Material.Metal, solid())
	local face = Geo.block(model, CFrame.new(0, 4.35, 0.3), Vector3.new(3.6, 0.8, 1.8), C.Metal, Enum.Material.Metal, solid({ Name = "AnvilFace" }))
	Geo.wedge(model, CFrame.new(-2.3, 4.35, 0.3) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), Vector3.new(1.4, 0.8, 1.2), C.Metal, Enum.Material.Metal, decor())
	-- hammer leaning on the stump
	Geo.block(model, CFrame.new(1.9, 2.2, -1.1) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.25, 2.6, 0.25), C.Wood, nil, decor())
	Geo.block(model, CFrame.new(2.3, 3.4, -1.1) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(1.1, 0.5, 0.5), C.MetalLight, Enum.Material.Metal, decor())
	-- quench bucket
	Geo.cylinder(model, Vector3.new(-2.4, 0.9, 2), 1.5, 1.6, C.Wood, nil, solid())
	Geo.cylinder(model, Vector3.new(-2.4, 1.6, 2), 0.1, 1.4, rgb(70, 140, 180), nil, decor())
	sign(model, CFrame.new(0, 1.6, -1.55), "ANVIL", 1.8)
	local anvilPoint = Vector3.new(0, 4.95, 0.3)
	attach(base, "AnvilPoint", CFrame.new(anvilPoint))
	-- forging close-up: in front and above, looking down at the face
	attach(base, "CamPoint", CFrame.lookAt(Vector3.new(0, 8.5, -5.5), anvilPoint + Vector3.new(0, 0.2, 0)))
	-- where the client shows waiting ingots: side by side across the face,
	-- turned so their long side runs front to back
	for i = 1, 4 do
		attach(base, "IngotSlot" .. i, CFrame.new((i - 2.5) * 0.9, 5.05, 0.3) * CFrame.Angles(0, math.pi / 2, 0))
	end
	attach(base, "Prompt", CFrame.new(0, 3.5, -1.8))
	output(base, "Anvil")
	local intake = attach(base, "Intake", CFrame.new(0, 5, 0.3))
	intake:SetAttribute("IntakeSize", Vector3.new(4.4, 2.6, 3.4))
	local _ = face
	return model
end

local function autoCleaner(): Model
	local model, base = newModel("AutoCleaner")
	base.Color = C.StoneDark
	for _, x in { -2.4, 2.4 } do
		Geo.block(model, CFrame.new(x, 1.8, 0.4), Vector3.new(0.6, 3.6, 4.6), C.Metal, Enum.Material.Metal, solid())
	end
	local drum = Geo.cylinder(model, Vector3.new(0, 3.2, 0.4), 4.2, 4, C.Teal, nil, solid({ Name = "Drum" }))
	drum.CFrame = CFrame.new(0, 3.2, 0.4)
	for k = 0, 3 do
		Geo.block(model, CFrame.new(0, 3.2, 0.4) * CFrame.Angles(k * math.pi / 4, 0, 0), Vector3.new(4.25, 4.1, 0.3), rgb(50, 120, 120), nil, decor({ Name = "DrumRib" }))
	end
	funnel(model, Vector3.new(0, 5.9, 0.6), 3.2, 1.4, C.MetalLight)
	-- dust vent
	local vent = Geo.block(model, CFrame.new(2.2, 5.4, 2.2), Vector3.new(0.9, 1.4, 0.9), C.Metal, Enum.Material.Metal, decor({ Name = "Vent" }))
	emitter(vent, "Smoke", rgb(190, 170, 150), 1)
	local out = output(base, "AutoCleaner")
	Geo.wedge(model, CFrame.new(out.X, 1.2, out.Z + 1.3) * CFrame.Angles(0, math.pi, 0), Vector3.new(2.2, 0.8, 1.6), C.MetalLight, Enum.Material.Metal, solid())
	sign(model, CFrame.new(0, 0.9, -1.85), "AUTO CLEANER", 3)
	attach(base, "Prompt", CFrame.new(0, 2.5, -3))
	local intake = attach(base, "Intake", CFrame.new(0, 4.6, 0.6))
	intake:SetAttribute("IntakeSize", Vector3.new(6, 6.6, 6))
	return model
end

local function sellChute(): Model
	local model, base = newModel("SellChute")
	base.Color = C.WoodDark
	Geo.block(model, CFrame.new(0, 1.4, 0), Vector3.new(1, 2.8, 1), C.WoodDark, nil, solid())
	funnel(model, Vector3.new(0, 3.3, 0), 3.6, 1.4, C.Wood)
	local coins = Geo.block(model, CFrame.new(0, 2.9, 0), Vector3.new(1.6, 0.3, 1.6), C.Gold, Enum.Material.Neon, decor({ Name = "Coins" }))
	light(coins, C.Gold, 8, 0.8)
	sign(model, CFrame.new(0, 1.6, -0.6), "SELL", 1)
	attach(base, "Prompt", CFrame.new(0, 2, -1.2))
	local intake = attach(base, "Intake", CFrame.new(0, 3.8, 0))
	intake:SetAttribute("IntakeSize", Vector3.new(3.6, 2.4, 3.6))
	return model
end

local function conveyor(): Model
	local model, base = newModel("Conveyor")
	base.Transparency = 1
	base.CanCollide = false
	base.CanQuery = true
	base.CastShadow = false
	Geo.block(model, CFrame.new(-1.85, 0.55, 0), Vector3.new(0.3, 1.1, 4), C.Metal, Enum.Material.Metal, solid({ Name = "RailL", CastShadow = false }))
	Geo.block(model, CFrame.new(1.85, 0.55, 0), Vector3.new(0.3, 1.1, 4), C.Metal, Enum.Material.Metal, solid({ Name = "RailR", CastShadow = false }))
	-- zero bounce and high friction so items ride the belt instead of hopping
	local belt = Geo.block(model, CFrame.new(0, 0.6, 0), Vector3.new(3.4, 0.4, 4), C.Belt, nil, solid({
		Name = "Belt",
		CanTouch = true,
		CastShadow = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 1.2, 0, 100, 100),
	}))
	belt:AddTag("ConveyorBelt")
	-- one flat chevron pointing to the front (-Z), the direction items move:
	-- two wedges lying flat, mirrored around x = 0
	local w, h = 1.8, 1.2
	for _, side in { -1, 1 } do
		Geo.wedge(model, CFrame.new(side * w / 4, 0.82, 0) * CFrame.Angles(0, 0, -side * math.pi / 2), Vector3.new(0.04, w / 2, h), C.Arrow, Enum.Material.Neon, decor({ Name = "Arrow" }))
	end
	attach(base, "Prompt", CFrame.new(0, 1.5, 0))
	return model
end

local BUILDERS: { [string]: () -> Model } = {
	CleaningStation = cleaningStation,
	StorageCrate = storageCrate,
	ClayFurnace = function()
		return furnace("ClayFurnace", 1)
	end,
	BlastFurnace = function()
		return furnace("BlastFurnace", 1.45)
	end,
	Crusher = crusher,
	Anvil = anvil,
	AutoCleaner = autoCleaner,
	SellChute = sellChute,
	Conveyor = conveyor,
}

-- Builds a machine model at the local origin (place it with :PivotTo()).
function MachineBuilder.build(id: string): Model
	local builder = BUILDERS[id]
	assert(builder, "No model for machine " .. tostring(id))
	local model = builder()
	local base = model.PrimaryPart :: BasePart
	local top = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- highest point of the (possibly rotated) part
			local cf, size = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local halfHeight = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
			top = math.max(top, cf.Position.Y + halfHeight)
		end
	end
	attach(base, "Status", CFrame.new(0, top - base.CFrame.Position.Y + 1.5, 0))
	return model
end

return MachineBuilder
