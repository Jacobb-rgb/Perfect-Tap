--[[
	Pooled particle bursts (client only). A few invisible anchored parts carry
	pre-made emitters; a burst moves one holder and calls :Emit(), so no new
	instances are created per hit (mobile friendly).
	Also small local rock chips (real parts, max ChipLimit alive).
]]

local Workspace = game:GetService("Workspace")

local Vfx = {}

local POOL_SIZE = 10
local CHIP_LIMIT = 40

local folder: Folder? = nil
local holders: { BasePart } = {}
local nextHolder = 1
local chipsAlive = 0

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function makeEmitter(holder: BasePart, name: string, setup: (ParticleEmitter) -> ())
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.LightInfluence = 0
	setup(e)
	e.Parent = holder
end

local function createHolder(index: number): BasePart
	local part = Instance.new("Part")
	part.Name = "FxHolder" .. index
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	makeEmitter(part, "Sparks", function(e)
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(Color3.fromRGB(255, 210, 130))
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.25, 0.5)
		e.Speed = NumberRange.new(16, 30)
		e.SpreadAngle = Vector2.new(75, 75)
		e.Acceleration = Vector3.new(0, -60, 0)
		e.Drag = 3
	end)
	makeEmitter(part, "Dust", function(e)
		e.Texture = SMOKE
		e.Color = ColorSequence.new(Color3.fromRGB(190, 168, 146))
		e.LightInfluence = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(3, 8)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 4
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-60, 60)
	end)
	makeEmitter(part, "Glint", function(e)
		e.Texture = SPARKLE
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.7), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.Speed = NumberRange.new(2, 7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 2
	end)
	makeEmitter(part, "Burst", function(e)
		e.Texture = SPARKLE
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.5, 1.1)
		e.Speed = NumberRange.new(10, 24)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 2.5
	end)
	part.Parent = folder
	return part
end

local function ensure()
	if folder and folder.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "ClientFx"
	f.Parent = Workspace
	folder = f
	table.clear(holders)
	for i = 1, POOL_SIZE do
		table.insert(holders, createHolder(i))
	end
end

-- kind: "Sparks" | "Dust" | "Glint" | "Burst"
function Vfx.burst(kind: string, position: Vector3, count: number, color: Color3?, direction: Vector3?)
	ensure()
	local holder = holders[nextHolder]
	nextHolder = nextHolder % #holders + 1
	if direction and direction.Magnitude > 0.01 then
		-- emitters shoot along the holder's up axis
		holder.CFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	else
		holder.CFrame = CFrame.new(position)
	end
	local emitter = holder:FindFirstChild(kind) :: ParticleEmitter?
	if not emitter then
		return
	end
	if color then
		emitter.Color = ColorSequence.new(color)
	elseif kind == "Sparks" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 210, 130))
	elseif kind == "Dust" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(190, 168, 146))
	end
	emitter:Emit(count)
end

-- Little rock chips that bounce away and vanish (real physics, client only).
function Vfx.chips(position: Vector3, count: number, color: Color3, power: number?)
	ensure()
	local strength = power or 1
	for _ = 1, count do
		if chipsAlive >= CHIP_LIMIT then
			return
		end
		chipsAlive += 1
		local s = 0.25 + math.random() * 0.45
		local chip = Instance.new("Part")
		chip.Size = Vector3.new(s, s * 0.8, s)
		chip.Color = color
		chip.Material = Enum.Material.SmoothPlastic
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		chip.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		chip.Parent = folder
		local angle = math.random() * math.pi * 2
		chip.AssemblyLinearVelocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (6 + math.random() * 8) * strength + Vector3.new(0, 12 + math.random() * 10, 0) * strength
		chip.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(1.1 + math.random() * 0.4, function()
			chip:Destroy()
			chipsAlive -= 1
		end)
	end
end

return Vfx
