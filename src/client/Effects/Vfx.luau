--[[
	Pooled particle bursts (client only). A few invisible anchored parts carry
	pre-made emitters; a burst moves one holder and calls :Emit(), so no new
	instances are created per hit (mobile friendly).
	Also small local rock chips (real parts, max ChipLimit alive) and pooled
	laser beams (one per key, e.g. "local" or a Player, max BEAM_LIMIT).
]]

local Workspace = game:GetService("Workspace")

local Vfx = {}

local POOL_SIZE = 10
local CHIP_LIMIT = 40
local BEAM_LIMIT = 10

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
	-- small dust for the cleaning close-up (the camera is only ~6 studs away)
	makeEmitter(part, "FineDust", function(e)
		e.Texture = SMOKE
		e.Color = ColorSequence.new(Color3.fromRGB(190, 168, 146))
		e.LightInfluence = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.32) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.3, 0.55)
		e.Speed = NumberRange.new(0.8, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -2, 0)
		e.Drag = 3
		e.Rotation = NumberRange.new(0, 360)
	end)
	makeEmitter(part, "Glint", function(e)
		e.Texture = SPARKLE
		e.LightEmission = 1
		e.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.7), NumberSequenceKeypoint.new(1, 0) })
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
	-- laser impact: a short hot flash where the beam touches the rock
	makeEmitter(part, "Impact", function(e)
		e.Texture = SPARKLE
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.08, 0.16)
		e.Speed = NumberRange.new(0, 1)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rotation = NumberRange.new(0, 360)
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

-- kind: "Sparks" | "Dust" | "FineDust" | "Glint" | "Burst" | "Impact"
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
	elseif kind == "Dust" or kind == "FineDust" then
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
		chip.AssemblyLinearVelocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (6 + math.random() * 8) * strength
			+ Vector3.new(0, 12 + math.random() * 10, 0) * strength
		chip.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(1.1 + math.random() * 0.4, function()
			chip:Destroy()
			chipsAlive -= 1
		end)
	end
end

---------------------------------------------------------------- laser beams

type BeamHandle = {
	Anchor: BasePart, -- invisible part at the beam's end (holds the light)
	Start: Attachment, -- used when there is no muzzle to start from
	End: Attachment,
	Outer: Beam,
	Inner: Beam,
	Light: PointLight,
	HideAt: number?,
}

local beams: { [any]: BeamHandle } = {}
local beamCount = 0

local function newBeam(): BeamHandle
	ensure()
	local anchor = Instance.new("Part")
	anchor.Name = "BeamEnd"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = "Start"
	startAttachment.Parent = anchor
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = "End"
	endAttachment.Parent = anchor
	local function beam(name: string, width: number, transparency: number): Beam
		local b = Instance.new("Beam")
		b.Name = name
		b.Attachment0 = startAttachment
		b.Attachment1 = endAttachment
		b.FaceCamera = true
		b.Segments = 1
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Width0 = width
		b.Width1 = width * 0.75
		b.Transparency = NumberSequence.new(transparency)
		b.Enabled = false
		b.Parent = anchor
		return b
	end
	local outer = beam("Glow", 0.5, 0.3)
	local inner = beam("Core", 0.16, 0)
	inner.Color = ColorSequence.new(Color3.new(1, 1, 1))
	local light = Instance.new("PointLight")
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = false
	light.Enabled = false
	light.Parent = anchor
	anchor.Parent = folder
	return {
		Anchor = anchor,
		Start = startAttachment,
		End = endAttachment,
		Outer = outer,
		Inner = inner,
		Light = light,
		HideAt = nil,
	}
end

local function showBeam(handle: BeamHandle, on: boolean)
	handle.Outer.Enabled = on
	handle.Inner.Enabled = on
	handle.Light.Enabled = on
end

--[[
	Shows (or moves) the beam `key` from the muzzle attachment (or `from` when
	there is none) to `to`. With `holdSeconds` it hides itself unless it is
	set again in time (beams of other players come from the server a few
	times a second). Call it every frame for your own beam: the width flickers.
]]
function Vfx.setBeam(key: any, muzzle: Attachment?, from: Vector3, to: Vector3, color: Color3, holdSeconds: number?)
	local handle = beams[key]
	if not handle then
		if beamCount >= BEAM_LIMIT then
			return
		end
		handle = newBeam()
		beams[key] = handle
		beamCount += 1
	end
	local h = handle :: BeamHandle
	if not h.Anchor.Parent then
		-- the effects folder was removed (e.g. the place reset it): start over
		beams[key] = nil
		beamCount -= 1
		return
	end
	h.Anchor.CFrame = CFrame.new(to)
	local start = h.Start
	if muzzle and muzzle:IsDescendantOf(Workspace) then
		h.Outer.Attachment0 = muzzle
		h.Inner.Attachment0 = muzzle
	else
		start.WorldPosition = from
		h.Outer.Attachment0 = start
		h.Inner.Attachment0 = start
	end
	local flicker = 0.85 + math.random() * 0.3
	h.Outer.Width0 = 0.5 * flicker
	h.Outer.Width1 = 0.36 * flicker
	h.Inner.Width0 = 0.16 * flicker
	h.Inner.Width1 = 0.12 * flicker
	h.Outer.Color = ColorSequence.new(color)
	h.Light.Color = color
	showBeam(h, true)
	if holdSeconds then
		local hideAt = os.clock() + holdSeconds
		h.HideAt = hideAt
		task.delay(holdSeconds + 0.02, function()
			if h.HideAt == hideAt then
				showBeam(h, false)
				h.HideAt = nil
			end
		end)
	else
		h.HideAt = nil
	end
end

function Vfx.hideBeam(key: any)
	local handle = beams[key]
	if handle then
		handle.HideAt = nil
		showBeam(handle, false)
	end
end

-- Frees a beam for good (a player left).
function Vfx.releaseBeam(key: any)
	local handle = beams[key]
	if handle then
		beams[key] = nil
		beamCount -= 1
		handle.Anchor:Destroy()
	end
end

-- Where a beam hits: a hot flash and sparks bouncing back toward the shooter.
function Vfx.impact(position: Vector3, color: Color3, back: Vector3?, sparks: number?)
	Vfx.burst("Impact", position, 1, color:Lerp(Color3.new(1, 1, 1), 0.35))
	Vfx.burst("Sparks", position, sparks or 3, color:Lerp(Color3.new(1, 1, 1), 0.5), back)
end

return Vfx
