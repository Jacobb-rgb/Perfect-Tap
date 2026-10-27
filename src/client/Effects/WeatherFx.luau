--[[
	WeatherFx: the weather's instances (client only), built once on first
	use and reused for every kind of weather (Config/WeatherConfig, the math
	in Weather/WeatherLogic). WeatherController drives it.

	  sky       8 invisible strips above the camera, leaning with the wind,
	            round a square hole on the camera's fall line (clear view,
	            WeatherLogic.hole / strips): rain streaks (VelocityParallel +
	            Squash), hail and snow fall out of their bottoms; the inner
	            ring's particles are smaller and fainter; LockedToPart, so
	            the falling field moves with the camera and walking never
	            carries the lens into it
	  air box   an invisible part from the ground up, turned downwind:
	            leaves (green and amber), heat wobble
	  pads      a few invisible pads the controller puts down by raycasts
	            near the camera: ripple rings + droplets (rain), bouncing
	            hail + a clack sound, settling snow flakes
	  rainbow   one anchor part with an Attachment trio and two Beams per
	            colour band (WeatherLogic.rainbowArc: a half circle)
	  tint      the weather's own ColorCorrectionEffect "WeatherTint" under
	            the camera (never in Lighting: LightingController tweens the
	            first ColorCorrectionEffect it finds there)
	  sounds    a SoundGroup (WeatherConfig.Group, nested in the SETTINGS
	            sound group), the rain and wind loops, thunder and the crack

	Everything is pooled: nothing is created after build(). Rates and
	volumes are only written when they change. Parts never collide, are
	never hit by raycasts or touches and cast no shadows.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeatherConfig = require(Shared.Config.WeatherConfig)
local WeatherLogic = require(Shared.Weather.WeatherLogic)

local WeatherFx = {}

WeatherFx.FolderName = "TerraForgeWeather"
WeatherFx.TintName = "WeatherTint"

export type Pad = {
	Part: Part,
	Emitters: { [string]: ParticleEmitter },
	Clack: Sound,
	Placed: boolean,
}

export type BandBeams = {
	A: Beam, -- left foot -> top
	B: Beam, -- top -> right foot
}

export type SkyStrip = {
	Part: Part,
	Emitters: { [string]: ParticleEmitter }, -- Rain, Hail, Snow
	Offset: CFrame, -- in the sky field's frame
	Share: number, -- of the sky rates
	Near: boolean,
}

export type Fx = {
	Folder: Folder,
	Sky: { SkyStrip },
	Hole: number, -- the sky field's hole now (half width, studs)
	Air: Part,
	Emitters: { [string]: ParticleEmitter }, -- the air box's, by WeatherConfig.Particles key ("Leaves2" = the amber leaves)
	Rates: { [string]: number }, -- what is written now
	Pads: { Pad },
	Rainbow: Part,
	Bands: { BandBeams },
	RainbowAlpha: number,
	Tint: ColorCorrectionEffect,
	Group: SoundGroup,
	Loops: { [string]: Sound },
	Shots: { [string]: { Sound } }, -- one-shot pools (Thunder, Crack)
	NextShot: { [string]: number },
	Rng: Random,
}

local SKY_KEYS = { "Rain", "Hail", "Snow" }
local PAD_KEYS = { "Ripple", "Drop", "Bounce", "Settle" }

local function invisiblePart(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Locked = true
	part.Parent = parent
	return part
end

local function orientation(name: string?): Enum.ParticleOrientation
	if name == "VelocityParallel" then
		return Enum.ParticleOrientation.VelocityParallel
	elseif name == "VelocityPerpendicular" then
		return Enum.ParticleOrientation.VelocityPerpendicular
	end
	return Enum.ParticleOrientation.FacingCamera
end

-- The inner ring's version of a look: smaller and fainter (Box.NearSize, Box.NearAlpha).
local function nearLook(p: WeatherConfig.Particle): WeatherConfig.Particle
	local box = WeatherConfig.Box
	local near = table.clone(p)
	near.Size = { p.Size[1] * box.NearSize, p.Size[2] * box.NearSize }
	near.Transparency = 1 - (1 - p.Transparency) * box.NearAlpha
	return near
end

-- A ParticleEmitter from a WeatherConfig.Particles look; off (Rate 0) until the controller sets a rate.
local function emitter(
	parent: Instance,
	name: string,
	p: WeatherConfig.Particle,
	direction: Enum.NormalId,
	color: Color3?,
	locked: boolean?
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = p.Texture
	e.Color = ColorSequence.new(color or p.Color)
	local mid = (p.Size[1] + p.Size[2]) / 2
	local spread = (p.Size[2] - p.Size[1]) / 2
	local grow = p.Grow or 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, mid, spread),
		NumberSequenceKeypoint.new(1, mid * grow, spread * grow),
	})
	local t = p.Transparency
	if p.Grow then
		-- a ripple: clear as it spreads
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t), NumberSequenceKeypoint.new(1, 1) })
	else
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.1, t),
			NumberSequenceKeypoint.new(0.8, t),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	e.Lifetime = NumberRange.new(p.Lifetime[1], p.Lifetime[2])
	e.Speed = NumberRange.new(p.Speed[1], p.Speed[2])
	local s = p.Spread or 0
	e.SpreadAngle = Vector2.new(s, s)
	e.Acceleration = Vector3.new(0, -(p.Gravity or 0), 0)
	e.Drag = p.Drag or 0
	local spin = p.RotSpeed or 0
	if spin > 0 then
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-spin, spin)
	end
	if p.Squash then
		e.Squash = NumberSequence.new(p.Squash)
	end
	e.Orientation = orientation(p.Orientation)
	e.LightEmission = p.LightEmission
	e.LightInfluence = 0.4
	e.EmissionDirection = direction
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = locked == true
	e.Rate = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

local function newSound(name: string, def: WeatherConfig.SoundDef, parent: Instance, group: SoundGroup): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = 0
	s.Looped = def.Looped == true
	s.PlaybackSpeed = def.Pitch[1]
	s.SoundGroup = group
	s.Parent = parent
	return s
end

-- The weather SoundGroup, nested in the SETTINGS sound group once that exists.
local function soundGroup(): SoundGroup
	local found = SoundService:FindFirstChild(WeatherConfig.Group, true)
	local group: SoundGroup
	if found and found:IsA("SoundGroup") then
		group = found
	else
		group = Instance.new("SoundGroup")
		group.Name = WeatherConfig.Group
		group.Parent = SoundService
	end
	local function nest()
		local sfx = SoundService:FindFirstChild(WeatherConfig.ParentGroup)
		if sfx and sfx:IsA("SoundGroup") and group.Parent ~= sfx then
			group.Parent = sfx
		end
	end
	nest()
	SoundService.ChildAdded:Connect(function(child: Instance)
		if child.Name == WeatherConfig.ParentGroup then
			nest()
		end
	end)
	return group
end

-- The tint effect under the current camera (moved along if the camera is replaced).
function WeatherFx.tintParent(fx: Fx)
	local camera = Workspace.CurrentCamera
	if camera and fx.Tint.Parent ~= camera then
		fx.Tint.Parent = camera
	end
end

function WeatherFx.build(): Fx
	local old = Workspace:FindFirstChild(WeatherFx.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = WeatherFx.FolderName
	folder.Parent = Workspace

	local box = WeatherConfig.Box
	local particles = WeatherConfig.Particles
	-- the sky field: WeatherLogic.strips' order (the inner ring's four, then the outer ring's)
	local sky: { SkyStrip } = {}
	for i, strip in WeatherLogic.strips(WeatherLogic.hole(nil)) do
		local part = invisiblePart("WeatherSky" .. i, Vector3.new(1, 2, 1), folder)
		local own: { [string]: ParticleEmitter } = {}
		for _, key in SKY_KEYS do
			local look = if strip.Near then nearLook(particles[key]) else particles[key]
			own[key] = emitter(part, "Weather" .. key, look, Enum.NormalId.Bottom, nil, true)
		end
		table.insert(sky, { Part = part, Emitters = own, Offset = CFrame.identity, Share = 0, Near = strip.Near })
	end
	local air = invisiblePart("WeatherAir", box.Air, folder)
	local emitters: { [string]: ParticleEmitter } = {}
	local leaves = particles.Leaves
	emitters.Leaves = emitter(air, "WeatherLeaves", leaves, Enum.NormalId.Right)
	emitters.Leaves2 = emitter(air, "WeatherLeaves2", leaves, Enum.NormalId.Right, leaves.Color2)
	emitters.Heat = emitter(air, "WeatherHeat", particles.Heat, Enum.NormalId.Top)

	local group = soundGroup()
	local sounds = WeatherConfig.Sounds
	local pads: { Pad } = {}
	local ground = WeatherConfig.Ground
	for i = 1, ground.Points do
		local part = invisiblePart("WeatherPad" .. i, Vector3.new(ground.Pad, 0.2, ground.Pad), folder)
		local own: { [string]: ParticleEmitter } = {}
		for _, key in PAD_KEYS do
			own[key] = emitter(part, "Weather" .. key, particles[key], Enum.NormalId.Top)
		end
		local clack = newSound("WeatherClack", sounds.Clack, part, group)
		clack.RollOffMode = Enum.RollOffMode.InverseTapered
		clack.RollOffMinDistance = 6
		clack.RollOffMaxDistance = 60
		table.insert(pads, { Part = part, Emitters = own, Clack = clack, Placed = false })
	end

	-- the rainbow: per band a left foot, a top and a right foot, two Beams
	local anchor = invisiblePart("WeatherRainbow", Vector3.new(1, 1, 1), folder)
	local r = WeatherConfig.Rainbow
	local bands: { BandBeams } = {}
	for i, band in WeatherLogic.rainbowBands() do
		local arc = WeatherLogic.rainbowArc(band.Radius)
		local points: { Attachment } = {}
		for k = 1, 3 do
			local a = Instance.new("Attachment")
			a.Name = `Band{i}_{k}`
			a.CFrame = CFrame.fromMatrix(arc.Points[k], arc.Axes[k], Vector3.new(0, 0, 1))
			a.Parent = anchor
			points[k] = a
		end
		local function beam(from: Attachment, to: Attachment, name: string): Beam
			local b = Instance.new("Beam")
			b.Name = name
			b.Attachment0 = from
			b.Attachment1 = to
			b.CurveSize0 = arc.Curve
			b.CurveSize1 = arc.Curve
			b.Width0 = band.Width
			b.Width1 = band.Width
			b.Color = ColorSequence.new(band.Color)
			b.Texture = ""
			b.FaceCamera = true
			b.Segments = 24
			b.LightEmission = r.LightEmission
			b.LightInfluence = 0
			b.Transparency = NumberSequence.new(1)
			b.Enabled = false
			b.Parent = anchor
			return b
		end
		table.insert(bands, {
			A = beam(points[1], points[2], `Band{i}A`),
			B = beam(points[2], points[3], `Band{i}B`),
		})
	end

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = WeatherFx.TintName
	tint.Enabled = false

	local loops: { [string]: Sound } = {}
	for _, name in { "Rain", "Wind" } do
		loops[name] = newSound("Weather" .. name, sounds[name], SoundService, group)
	end
	local shots: { [string]: { Sound } } = {}
	for _, name in { "Thunder", "Crack" } do
		shots[name] = {
			newSound("Weather" .. name .. "1", sounds[name], SoundService, group),
			newSound("Weather" .. name .. "2", sounds[name], SoundService, group),
		}
	end

	local fx: Fx = {
		Folder = folder,
		Sky = sky,
		Hole = -1,
		Air = air,
		Emitters = emitters,
		Rates = {},
		Pads = pads,
		Rainbow = anchor,
		Bands = bands,
		RainbowAlpha = 0,
		Tint = tint,
		Group = group,
		Loops = loops,
		Shots = shots,
		NextShot = { Thunder = 1, Crack = 1 },
		Rng = Random.new(),
	}
	WeatherFx.tintParent(fx)
	WeatherFx.setHole(fx, WeatherLogic.hole(nil))
	return fx
end

---------------------------------------------------------------- rates

local function setRate(e: ParticleEmitter, rate: number)
	local on = rate > 0.05
	if e.Enabled ~= on then
		e.Enabled = on
	end
	local want = if on then rate else 0
	if math.abs(e.Rate - want) > math.max(0.05, want * 0.02) or (want == 0 and e.Rate ~= 0) then
		e.Rate = want
	end
end

-- Sets the rates (particles per second) by WeatherConfig.Particles key ("Leaves2" = the amber
-- leaves); missing keys go to 0. A sky key's rate is shared by the sky strips (by area), pad
-- keys apply to every placed pad (a pad that is not placed stays off).
function WeatherFx.setRates(fx: Fx, rates: { [string]: number })
	for key, e in fx.Emitters do
		local rate = rates[key] or 0
		if fx.Rates[key] ~= rate then
			fx.Rates[key] = rate
			setRate(e, rate)
		end
	end
	for _, key in SKY_KEYS do
		local rate = rates[key] or 0
		fx.Rates[key] = rate
		for _, strip in fx.Sky do
			setRate(strip.Emitters[key], rate * strip.Share)
		end
	end
	for _, key in PAD_KEYS do
		local rate = rates[key] or 0
		fx.Rates[key] = rate
		for _, pad in fx.Pads do
			setRate(pad.Emitters[key], if pad.Placed then rate else 0)
		end
	end
end

-- Puts pad `index` at a ground point (nil = takes it away).
function WeatherFx.placePad(fx: Fx, index: number, position: Vector3?)
	local pad = fx.Pads[index]
	if not pad then
		return
	end
	if position then
		pad.Part.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0))
	end
	local placed = position ~= nil
	if pad.Placed ~= placed then
		pad.Placed = placed
		for _, key in PAD_KEYS do
			setRate(pad.Emitters[key], if placed then fx.Rates[key] or 0 else 0)
		end
	end
end

-- The sky field's hole (half width, studs: WeatherLogic.hole for the kind now): the strips are
-- resized round it and share the sky rates by area. Only when it changes (a new kind).
function WeatherFx.setHole(fx: Fx, hole: number)
	if math.abs(fx.Hole - hole) < 1e-3 then
		return
	end
	fx.Hole = hole
	for i, strip in WeatherLogic.strips(hole) do
		local own = fx.Sky[i]
		if own then
			own.Share = strip.Share
			own.Offset = CFrame.new(strip.X, 0, strip.Z)
			own.Part.Size = Vector3.new(math.max(strip.SizeX, 0.05), 2, math.max(strip.SizeZ, 0.05))
		end
	end
	local rates = table.clone(fx.Rates)
	table.clear(fx.Rates)
	WeatherFx.setRates(fx, rates)
end

---------------------------------------------------------------- placing (every frame)

-- What follows the camera. The sky field is centred on the camera's fall line (Height studs up
-- and upwind by Height x tan(slant), so the slanted rain misses the lens by the hole) and leans
-- `slant` radians downwind; the air box stands from `groundY` up, ahead and upwind.
function WeatherFx.place(fx: Fx, camera: CFrame, windYaw: number, slant: number, groundY: number)
	local box = WeatherConfig.Box
	local wind = WeatherLogic.windDirection(windYaw)
	local upwind = -wind * (box.Height * math.tan(slant))
	-- yaw so the field's +X is downwind, then roll so its bottom faces point down and downwind
	local turn = CFrame.fromMatrix(Vector3.zero, wind, Vector3.new(0, 1, 0))
	local field = CFrame.new(camera.Position + upwind + Vector3.new(0, box.Height, 0)) * turn * CFrame.Angles(0, 0, slant)
	for _, strip in fx.Sky do
		strip.Part.CFrame = field * strip.Offset
	end
	local look = camera.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local at = camera.Position + (if flat.Magnitude > 1e-3 then flat.Unit * box.Ahead else Vector3.zero)
	local airY = groundY + box.Air.Y / 2 - 0.5
	fx.Air.CFrame = CFrame.new(Vector3.new(at.X, airY, at.Z) - wind * box.Upwind) * turn
end

---------------------------------------------------------------- tint

function WeatherFx.setTint(fx: Fx, tint: WeatherLogic.Tint, flash: number)
	local e = fx.Tint
	local on = flash > 0.001 or not WeatherLogic.isNeutral(tint)
	if e.Enabled ~= on then
		e.Enabled = on
	end
	if not on then
		return
	end
	e.TintColor = tint.Color
	e.Brightness = tint.Brightness + flash
	e.Contrast = tint.Contrast
	e.Saturation = tint.Saturation
end

---------------------------------------------------------------- rainbow

-- Shows the rainbow at `alpha` (0 = hidden) in `frame` (WeatherLogic.rainbowFrame).
function WeatherFx.setRainbow(fx: Fx, alpha: number, frame: CFrame?)
	local show = alpha > 0.005 and frame ~= nil
	if frame and show then
		fx.Rainbow.CFrame = frame
	end
	if not show then
		if fx.RainbowAlpha > 0 then
			fx.RainbowAlpha = 0
			for _, band in fx.Bands do
				band.A.Enabled = false
				band.B.Enabled = false
			end
		end
		return
	end
	if math.abs(alpha - fx.RainbowAlpha) < 0.015 and fx.RainbowAlpha > 0 then
		return
	end
	fx.RainbowAlpha = alpha
	local foot = WeatherLogic.rainbowTransparency(alpha, 0)
	local mid = WeatherLogic.rainbowTransparency(alpha, 0.5)
	local top = WeatherLogic.rainbowTransparency(alpha, 1)
	local up = NumberSequence.new({
		NumberSequenceKeypoint.new(0, foot),
		NumberSequenceKeypoint.new(0.5, mid),
		NumberSequenceKeypoint.new(1, top),
	})
	local down = NumberSequence.new({
		NumberSequenceKeypoint.new(0, top),
		NumberSequenceKeypoint.new(0.5, mid),
		NumberSequenceKeypoint.new(1, foot),
	})
	for _, band in fx.Bands do
		band.A.Transparency = up
		band.B.Transparency = down
		band.A.Enabled = true
		band.B.Enabled = true
	end
end

---------------------------------------------------------------- sounds

local function pitch(fx: Fx, def: WeatherConfig.SoundDef): number
	return def.Pitch[1] + (def.Pitch[2] - def.Pitch[1]) * fx.Rng:NextNumber()
end

-- A loop (Rain, Wind) at `level` (0..1 of its configured volume; 0 stops it).
function WeatherFx.setLoop(fx: Fx, name: string, level: number)
	local s = fx.Loops[name]
	local def = WeatherConfig.Sounds[name]
	if not (s and def) then
		return
	end
	local volume = def.Volume * math.clamp(level, 0, 1)
	if volume < 0.003 then
		if s.IsPlaying then
			s:Stop()
		end
		return
	end
	if math.abs(s.Volume - volume) > 0.002 then
		s.Volume = volume
	end
	if not s.IsPlaying then
		s.PlaybackSpeed = pitch(fx, def)
		s:Play()
	end
end

-- A one-shot (Thunder, Crack) at `level` of its volume.
function WeatherFx.play(fx: Fx, name: string, level: number)
	local pool = fx.Shots[name]
	local def = WeatherConfig.Sounds[name]
	if not (pool and def) then
		return
	end
	local index = fx.NextShot[name] or 1
	fx.NextShot[name] = index % #pool + 1
	local s = pool[index]
	s.Volume = def.Volume * math.clamp(level, 0, 1)
	s.PlaybackSpeed = pitch(fx, def)
	s.TimePosition = 0
	s:Play()
end

-- A hail clack at a placed pad.
function WeatherFx.clack(fx: Fx, index: number, level: number)
	local pad = fx.Pads[index]
	local def = WeatherConfig.Sounds.Clack
	if not (pad and pad.Placed and def) then
		return
	end
	local s = pad.Clack
	s.Volume = def.Volume * math.clamp(level, 0, 1)
	s.PlaybackSpeed = pitch(fx, def)
	s.TimePosition = 0
	s:Play()
end

-- Removes the particles that are still flying (going down a mine, into the vault, cleaning).
function WeatherFx.clear(fx: Fx)
	for _, e in fx.Emitters do
		e:Clear()
	end
	for _, strip in fx.Sky do
		for _, e in strip.Emitters do
			e:Clear()
		end
	end
	for _, pad in fx.Pads do
		for _, e in pad.Emitters do
			e:Clear()
		end
	end
end

-- Everything off: no particles, no beams, no tint, no sound (the instances stay for later).
function WeatherFx.hide(fx: Fx)
	WeatherFx.setRates(fx, {})
	for i in fx.Pads do
		WeatherFx.placePad(fx, i, nil)
	end
	WeatherFx.setRainbow(fx, 0, nil)
	WeatherFx.setTint(fx, WeatherLogic.Neutral, 0)
	for name in fx.Loops do
		WeatherFx.setLoop(fx, name, 0)
	end
end

return WeatherFx
