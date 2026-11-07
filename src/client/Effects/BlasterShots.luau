--[[
	BlasterShots: the blaster fires separate energy shots, not a beam (owner
	2026-11-06: "individual energy shots flying rapidly toward the target",
	"increasing fire rate as the blaster spins faster"). Only what you see: the
	server's damage ticks and the aim (MiningController) know nothing of it.

	  aim(key, muzzle, from, to, solid, color, level, hold, hooks)
	      the gun `key` ("local" or a Player) fires at `to` (solid: it lands
	      there). Call it every frame for your own gun (hold = nil, until
	      stop); another player's keeps firing for `hold` seconds (their
	      BlastHits come a few times a second)
	  stop(key)      the trigger comes up (shots in the air fly on)
	  release(key)   a player left: their gun's light goes

	A gun's fire rate follows its spin (BlasterFeel.shotStep): the same ramp as
	its barrels, so the shots get faster as they spin up. Each shot leaves from
	the next barrel, so a stream winds slightly round the barrels' axis, and
	throws a muzzle flash; when it lands: a small impact. The gun's one light at
	the hit holds steady while shots land and fades after the last (no strobe:
	BlasterFeel.glareStep).

	Hooks (your own gun): Shot(spin) as a shot leaves, Hit(point, back) when it
	lands. Without hooks: only the small flash at the hit.

	A shot = one anchored Neon ball (the head) and two Beams (the glow trail and
	its white core), made once and reused: Shots.Pool at most in the air, other
	players' guns leave Shots.Reserve for yours (a gun skips a shot when none is
	free; your sound and recoil still play). One Heartbeat connection while
	anything flies or a gun runs, all moved with one BulkMoveTo.
	Reduce motion: a slower top rate (Shots.ReducedRate), straight streams, no
	muzzle or impact flashes (soft sparks), a dim steady light.

	Env: what a Lune spec replaces (it has no real signals, emitters or BulkMoveTo).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterFeel = require(Shared.Config.BlasterFeel)
local Motion = require(script.Parent.Parent.UI.Motion)
local Vfx = require(script.Parent.Vfx)

local BlasterShots = {}

BlasterShots.Env = {
	connect = function(fn: (number) -> ()): RBXScriptConnection
		return RunService.Heartbeat:Connect(fn)
	end,
	move = function(parts: { BasePart }, frames: { CFrame })
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end,
	emit = function(flash: ParticleEmitter)
		flash:Emit(1)
	end,
	inWorld = function(instance: Instance): boolean
		return instance:IsDescendantOf(Workspace)
	end,
	worldOf = function(attachment: Attachment): Vector3
		return attachment.WorldPosition
	end,
	clock = os.clock,
	isPhone = function(): boolean
		return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	end,
}

local SHOTS = BlasterFeel.Shots
local GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"
local WHITE = Color3.new(1, 1, 1)
local FLASH_NAME = "ShotFlash"

export type Hooks = {
	Shot: ((spin: number) -> ())?,
	Hit: ((point: Vector3, back: Vector3) -> ())?,
}

type Gun = {
	Muzzle: Attachment?,
	From: Vector3,
	To: Vector3,
	Solid: boolean,
	Color: Color3,
	Tier: BlasterFeel.Tier,
	FlashEvery: number,
	Hooks: Hooks?,
	Top: number,
	On: boolean,
	Until: number,
	Spin: number,
	Due: number,
	Barrel: number,
	Count: number,
	Flash: ParticleEmitter?,
	FlashColor: Color3?,
	Lamp: BasePart,
	Light: PointLight,
	Glare: number, -- the hit light now (0..1)
	LandedAt: number, -- when its last shot landed
}

type Shot = {
	Part: BasePart,
	Glow: Beam,
	Core: Beam,
	Color: Color3?,
	Width: number,
	Gun: Gun?,
	Frame: CFrame,
	Dir: Vector3,
	To: Vector3,
	Solid: boolean,
	At: number,
	Length: number,
}

local guns: { [any]: Gun } = {}
local gunCount = 0
local free: { Shot } = {}
local flying: { Shot } = {}
local made = 0
local connection: RBXScriptConnection? = nil
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

---------------------------------------------------------------- the pool

local function trailBeam(name: string, a: Attachment, b: Attachment, part: BasePart): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a
	beam.Attachment1 = b
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0.05, 1) -- bright at the head, gone at the tail
	beam.Enabled = false
	beam.Parent = part
	return beam
end

local function newShot(): Shot
	local part = Instance.new("Part")
	part.Name = "BlasterShot"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	local head = Instance.new("Attachment")
	head.Parent = part
	-- (a part looks along its -Z: the trail runs back along +Z)
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, SHOTS.Trail)
	tail.Parent = part
	local mid = Instance.new("Attachment")
	mid.Position = Vector3.new(0, 0, SHOTS.Trail * 0.6)
	mid.Parent = part
	local glow = trailBeam("Glow", head, tail, part)
	local core = trailBeam("Core", head, mid, part)
	core.Color = ColorSequence.new(WHITE)
	part.Parent = Vfx.folder()
	made += 1
	return {
		Part = part,
		Glow = glow,
		Core = core,
		Color = nil,
		Width = 0,
		Gun = nil,
		Frame = CFrame.identity,
		Dir = Vector3.zero,
		To = Vector3.zero,
		Solid = false,
		At = 0,
		Length = 0,
	}
end

-- A free shot (nil: none for this gun). A shot whose part is gone (the effects folder was reset) is dropped.
local function take(own: boolean): Shot?
	local pool = if BlasterShots.Env.isPhone() then SHOTS.PhonePool else SHOTS.Pool
	if #flying >= (if own then pool else pool - SHOTS.Reserve) then
		return nil
	end
	while #free > 0 do
		local shot = table.remove(free) :: Shot
		if shot.Part.Parent then
			return shot
		end
		made -= 1
	end
	return newShot()
end

local function put(shot: Shot)
	shot.Part.Transparency = 1
	shot.Glow.Enabled = false
	shot.Core.Enabled = false
	shot.Gun = nil
	table.insert(free, shot)
end

---------------------------------------------------------------- one shot

-- The flash on this muzzle (one per gun, made once, like BlasterFx's swirl on the same attachment).
local function flashOf(gun: Gun, muzzle: Attachment): ParticleEmitter
	local flash = gun.Flash
	if not flash or flash.Parent ~= muzzle then
		local found = muzzle:FindFirstChild(FLASH_NAME)
		if found and found:IsA("ParticleEmitter") then
			flash = found
		else
			local e = Instance.new("ParticleEmitter")
			e.Name = FLASH_NAME
			e.Texture = GLOW
			e.LightEmission = 1
			e.LightInfluence = 0
			e.LockedToPart = true
			e.Lifetime = NumberRange.new(0.04, 0.07)
			e.Speed = NumberRange.new(0)
			e.Rotation = NumberRange.new(0, 360)
			e.Transparency = NumberSequence.new(0.1, 1)
			e.ZOffset = 0.5
			e.Enabled = false
			e.Parent = muzzle
			flash = e
		end
		gun.Flash = flash
		gun.FlashColor = nil
	end
	return flash :: ParticleEmitter
end

local function muzzleFlash(gun: Gun, muzzle: Attachment)
	gun.Count += 1
	if gun.Count % gun.FlashEvery ~= 0 then
		return
	end
	local flash = flashOf(gun, muzzle)
	if gun.FlashColor ~= gun.Color then
		gun.FlashColor = gun.Color
		local size = gun.Tier.Flash
		flash.Color = ColorSequence.new(gun.Color:Lerp(WHITE, 0.45))
		flash.Size = NumberSequence.new(size, size * 0.4)
	end
	BlasterShots.Env.emit(flash)
end

-- A shot leaves the gun, `late` seconds ago (a frame's shots leave evenly apart).
local function fire(gun: Gun, late: number)
	local hooks = gun.Hooks
	if hooks and hooks.Shot then
		hooks.Shot(gun.Spin) -- (your sound and recoil, even when no shot is free)
	end
	local muzzle = gun.Muzzle
	local alive = muzzle ~= nil and BlasterShots.Env.inWorld(muzzle)
	local origin = if alive and muzzle then BlasterShots.Env.worldOf(muzzle) else gun.From
	local line = gun.To - origin
	if line.Magnitude < 0.5 then
		return
	end
	local shot = take(hooks ~= nil)
	if not shot then
		return
	end
	-- the next barrel: a little off the axis (it still lands on the point)
	gun.Barrel = gun.Barrel % SHOTS.Barrels + 1
	local start = origin
	local calm = Motion.reduced()
	if not calm then
		local angle = gun.Barrel / SHOTS.Barrels * math.pi * 2
		local axis = CFrame.lookAt(origin, gun.To)
		start = origin + axis.RightVector * (math.cos(angle) * SHOTS.Spiral) + axis.UpVector * (math.sin(angle) * SHOTS.Spiral)
	end
	local path = gun.To - start
	local length = path.Magnitude
	shot.Gun = gun
	shot.Frame = CFrame.lookAt(start, gun.To)
	shot.Dir = path / length
	shot.To = gun.To
	shot.Solid = gun.Solid
	shot.At = SHOTS.Speed * late
	shot.Length = length
	local width = gun.Tier.ShotWidth
	if shot.Color ~= gun.Color or shot.Width ~= width then
		shot.Color = gun.Color
		shot.Width = width
		local hot = gun.Color:Lerp(WHITE, 0.35)
		shot.Part.Color = hot
		shot.Part.Size = Vector3.new(width, width, width) * 0.85
		shot.Glow.Color = ColorSequence.new(hot, gun.Color)
		shot.Glow.Width0 = width
		shot.Glow.Width1 = width * 0.15
		shot.Core.Width0 = gun.Tier.ShotCore
		shot.Core.Width1 = gun.Tier.ShotCore * 0.2
	end
	shot.Part.Transparency = 0
	shot.Glow.Enabled = true
	shot.Core.Enabled = true
	table.insert(flying, shot)
	if alive and muzzle and not calm then
		muzzleFlash(gun, muzzle)
	end
end

local function land(shot: Shot)
	local gun = shot.Gun
	if not gun or not shot.Solid then
		return
	end
	local back = -shot.Dir
	local hooks = gun.Hooks
	if hooks and hooks.Hit then
		hooks.Hit(shot.To, back)
	else
		Vfx.impact(shot.To, gun.Color, nil, 0)
	end
	gun.LandedAt = BlasterShots.Env.clock()
	if gun.Lamp.Parent then
		gun.Lamp.CFrame = CFrame.new(shot.To + back * 0.8)
	end
end

---------------------------------------------------------------- the frame

local function step(dt: number)
	local now = BlasterShots.Env.clock()
	local running = false
	for _, gun in guns do
		local on = gun.On or now < gun.Until
		local count
		gun.Spin, gun.Due, count = BlasterFeel.shotStep(gun.Spin, gun.Due, dt, on, gun.Top)
		for i = 1, count do
			fire(gun, dt * (count - i) / count)
		end
		local lit = now - gun.LandedAt < SHOTS.LightHold
		if lit or gun.Glare > 0 then
			gun.Glare = BlasterFeel.glareStep(gun.Glare, dt, lit, if Motion.reduced() then SHOTS.ReducedLight else SHOTS.LightLevel)
			gun.Light.Enabled = gun.Glare > 0
			gun.Light.Brightness = gun.Tier.Light * gun.Glare
		end
		running = running or on or gun.Spin > 0 or lit or gun.Glare > 0
	end
	table.clear(moveParts)
	table.clear(moveFrames)
	-- (backward: a shot that lands swaps with the last one, already moved)
	for i = #flying, 1, -1 do
		local shot = flying[i]
		shot.At += SHOTS.Speed * dt
		if shot.At >= shot.Length or not shot.Part.Parent then
			flying[i] = flying[#flying]
			flying[#flying] = nil
			land(shot)
			put(shot)
		else
			table.insert(moveParts, shot.Part)
			table.insert(moveFrames, shot.Frame + shot.Dir * shot.At)
		end
	end
	if #moveParts > 0 then
		BlasterShots.Env.move(moveParts, moveFrames)
	end
	local current = connection
	if not running and #flying == 0 and current then
		connection = nil
		current:Disconnect()
	end
end

---------------------------------------------------------------- the API

local function gunOf(key: any): Gun?
	local gun = guns[key]
	if gun and gun.Lamp.Parent then
		return gun
	end
	if gun then
		guns[key] = nil -- the effects folder was reset
		gunCount -= 1
	end
	if gunCount >= SHOTS.Guns then
		return nil
	end
	local lamp = Instance.new("Part")
	lamp.Name = "ShotLamp"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(0.2, 0.2, 0.2)
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Enabled = false
	light.Parent = lamp
	lamp.Parent = Vfx.folder()
	local fresh: Gun = {
		Muzzle = nil,
		From = Vector3.zero,
		To = Vector3.zero,
		Solid = false,
		Color = WHITE,
		Tier = BlasterFeel.tier(1),
		FlashEvery = 1,
		Hooks = nil,
		Top = SHOTS.FastRate,
		On = false,
		Until = 0,
		Spin = 0,
		Due = 1,
		Barrel = 0,
		Count = 0,
		Flash = nil,
		FlashColor = nil,
		Lamp = lamp,
		Light = light,
		Glare = 0,
		LandedAt = -math.huge,
	}
	guns[key] = fresh
	gunCount += 1
	return fresh
end

function BlasterShots.aim(
	key: any,
	muzzle: Attachment?,
	from: Vector3,
	to: Vector3,
	solid: boolean,
	color: Color3,
	level: any,
	hold: number?,
	hooks: Hooks?
)
	local gun = gunOf(key)
	if not gun then
		return
	end
	gun.Muzzle = muzzle
	gun.From = from
	gun.To = to
	gun.Solid = solid
	gun.Hooks = hooks
	local tier = BlasterFeel.tier(level)
	if gun.Color ~= color or gun.Tier ~= tier then
		gun.Color = color
		gun.Tier = tier
		gun.Light.Color = color
		gun.FlashColor = nil
		gun.FlashEvery = BlasterFeel.resolve(level, BlasterShots.Env.isPhone()).FlashEvery
	end
	local top = if hooks then SHOTS.FastRate else SHOTS.OtherRate
	gun.Top = if Motion.reduced() then math.min(top, SHOTS.ReducedRate) else top
	if hold then
		gun.Until = BlasterShots.Env.clock() + hold
	else
		gun.On = true
	end
	if not connection then
		connection = BlasterShots.Env.connect(step)
	end
end

function BlasterShots.stop(key: any)
	local gun = guns[key]
	if gun then
		gun.On = false
		gun.Until = 0
	end
end

function BlasterShots.release(key: any)
	local gun = guns[key]
	if not gun then
		return
	end
	guns[key] = nil
	gunCount -= 1
	gun.Lamp:Destroy()
	for _, shot in flying do
		if shot.Gun == gun then
			shot.Solid = false -- its gun is gone: it just flies out
		end
	end
end

return BlasterShots
