--[[
	BlasterFx: how firing your blaster feels (client only, tuned in
	Config/BlasterFeel; the shots themselves are Effects/BlasterShots).
	MiningController calls:

	  BlasterFx.start(tool)     the trigger goes down: the zap sound, the hum
	                            loop, a camera and gun kick; on Lv7+ the
	                            sparkle swirl runs while firing
	  BlasterFx.fired(spin)     a shot leaves (spin 0..1): its sound, the hum
	                            climbing with the spin, recoil
	  BlasterFx.hit(point, glow, back, gated, rockColor)
	                            a shot lands: a small impact in its glow; on a
	                            rock you can mine also the hit pulses (crackle,
	                            chips in the rock's crust colour, a thud, Lv10
	                            shock rings); a rock you can't mine yet only
	                            gets dull grey sparks
	  BlasterFx.stop()          the trigger comes up: everything off, the gun
	                            settles back

	The gun kick moves the RightGrip weld (local only: other players see the
	gun still). Phones get half the particles, no camera kick and a smaller
	gun kick (BlasterFeel.Phone). Emitters are made once per tool (on its
	Muzzle attachment) and a small pool of ring holders is reused: nothing is
	created per hit except Vfx's capped rock chips. No extra lights.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterFeel = require(Shared.Config.BlasterFeel)
local Vfx = require(script.Parent.Vfx)
local Sfx = require(script.Parent.Sfx)
local CameraShake = require(script.Parent.CameraShake)
local BarrelSpin = require(script.Parent.BarrelSpin)

local BlasterFx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local DULL = Color3.fromRGB(200, 200, 220)
local RING_POOL = 3

local toolFx: { [Tool]: ParticleEmitter } = setmetatable({}, { __mode = "k" }) :: any
local current: Tool? = nil
local feel: BlasterFeel.Feel = BlasterFeel.resolve(1, false)
local glow = Color3.fromRGB(255, 150, 70)
local pulses = 0
local lastPulse = -math.huge
local kickAt = -math.huge -- when the gun was last kicked
local kickSize = 0 -- how big that kick was (1 = a pulse kick)
local grip: Weld? = nil -- the RightGrip weld we move
local gripBase: CFrame? = nil -- its C1 before we touched it
local stepBound = false
local ringHolders: { BasePart } = {}
local nextRing = 1
local shotSoundAt = -math.huge

-- Phones and tablets (touch, no mouse): the light version.
function BlasterFx.isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function glowOf(tool: Tool): Color3
	local value = tool:GetAttribute("Glow")
	return if typeof(value) == "Color3" then value else glow
end

-- The level a blaster's effects look like: its Level, a STAR blaster's the top tier (10).
function BlasterFx.levelOf(tool: Instance?): number
	if tool and tool:GetAttribute("Star") ~= nil then
		return 10
	end
	local value = tool and tool:GetAttribute("Level")
	return if type(value) == "number" then value else 1
end
local levelOf = BlasterFx.levelOf

local function muzzleOf(tool: Tool): Attachment?
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

---------------------------------------------------------------- emitters

-- The Lv7+ swirl on a tool's Muzzle (made once, local only; the shots bring their own flash).
local function swirlFor(tool: Tool): ParticleEmitter?
	local existing = toolFx[tool]
	if existing and existing.Parent then
		return existing
	end
	local muzzle = muzzleOf(tool)
	if not muzzle then
		return nil
	end
	local swirl = Instance.new("ParticleEmitter")
	swirl.Name = "BlasterSwirl"
	swirl.Texture = SPARKLE
	swirl.LightEmission = 1
	swirl.LightInfluence = 0
	swirl.Lifetime = NumberRange.new(0.3, 0.5)
	swirl.Speed = NumberRange.new(1, 2.5)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.RotSpeed = NumberRange.new(-200, 200)
	swirl.Acceleration = Vector3.new(0, 2, 0)
	swirl.Drag = 2
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	swirl.Enabled = false
	swirl.Parent = muzzle
	toolFx[tool] = swirl
	return swirl
end

local function setSwirl(tool: Tool, on: boolean)
	if on and feel.Swirl <= 0 then
		return
	end
	local swirl = if on then swirlFor(tool) else toolFx[tool]
	if not swirl then
		return
	end
	swirl.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(glow, 0.5))
	swirl.Rate = feel.Swirl
	swirl.Enabled = on
end

-- A small pool of anchored holders for the Lv10 shock rings at the hit.
local function ringAt(position: Vector3, color: Color3)
	if #ringHolders < RING_POOL then
		local folder = Workspace:FindFirstChild("ClientFx")
		if not folder then
			return -- Vfx makes the folder with its first burst
		end
		local part = Instance.new("Part")
		part.Name = "BlasterRing"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Ring"
		e.Texture = RING
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Lifetime = NumberRange.new(0.22, 0.28)
		e.Speed = NumberRange.new(0)
		e.Rotation = NumberRange.new(0, 360)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 3.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Enabled = false
		e.Parent = part
		part.Parent = folder
		table.insert(ringHolders, part)
	end
	local holder = ringHolders[nextRing]
	if not holder then
		return
	end
	nextRing = nextRing % #ringHolders + 1
	if not holder.Parent then
		table.clear(ringHolders)
		nextRing = 1
		return
	end
	holder.CFrame = CFrame.new(position)
	local e = holder:FindFirstChild("Ring") :: ParticleEmitter?
	if e then
		e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3))
		e:Emit(1)
	end
end

---------------------------------------------------------------- recoil

local function findGrip(tool: Tool): Weld?
	local character = Players.LocalPlayer.Character
	local handle = tool:FindFirstChild("Handle")
	if not character or not handle then
		return nil
	end
	for _, name in { "RightHand", "Right Arm" } do
		local arm = character:FindFirstChild(name)
		local weld = arm and arm:FindFirstChild("RightGrip")
		if weld and weld:IsA("Weld") and weld.Part1 == handle then
			return weld
		end
	end
	return nil
end

local function restoreGrip()
	local weld, base = grip, gripBase
	if weld and base and weld.Parent then
		weld.C1 = base
	end
	grip, gripBase = nil, nil
end

--[[
	The kick for this frame, in the grip attachment's frame: the gun jumps
	back along its barrel and the muzzle climbs, both settling with
	BlasterFeel.settle. Worked out from the gun's real barrel and the world's
	up, so it is right whatever the avatar's rig does.
]]
local function gripKick(weld: Weld, base: CFrame, amount: number): CFrame
	local hand = weld.Part0
	if amount < 1e-3 or not hand then
		return base
	end
	-- the hand's grip frame (Handle = Hold * C1^-1), and the unkicked barrel (-Z of the gun) in it
	local hold = hand.CFrame * weld.C0
	local barrel = base:VectorToObjectSpace(Vector3.new(0, 0, -1))
	local up = hold:VectorToObjectSpace(Vector3.yAxis)
	local axis = barrel:Cross(up)
	local recoil = BlasterFeel.Recoil
	local kick = CFrame.new(-barrel * recoil.GunBack * amount)
	if axis.Magnitude > 1e-3 then
		kick *= CFrame.fromAxisAngle(axis.Unit, recoil.GunLift * amount)
	end
	-- kicking the hold by K: Handle' = Hold * K * C1^-1, so C1' = C1 * K^-1
	return base * kick:Inverse()
end

local function step()
	local now = os.clock()
	local weld, base = grip, gripBase
	if weld and base then
		if not weld.Parent then
			grip, gripBase = nil, nil
		else
			weld.C1 = gripKick(weld, base, kickSize * BlasterFeel.settle(now - kickAt))
		end
	end
	if not current and (not weld or now - kickAt > 0.6) then
		restoreGrip()
		if stepBound then
			stepBound = false
			RunService:UnbindFromRenderStep("TerraForgeBlasterFx")
		end
	end
end

local function bindStep()
	if not stepBound then
		stepBound = true
		RunService:BindToRenderStep("TerraForgeBlasterFx", Enum.RenderPriority.Character.Value + 1, step)
	end
end

local function kick(size: number)
	kickAt = os.clock()
	kickSize = size * feel.GunKick
	bindStep()
end

---------------------------------------------------------------- the API

function BlasterFx.start(tool: Tool)
	if current and current ~= tool then
		BlasterFx.stop()
	end
	current = tool
	glow = glowOf(tool)
	feel = BlasterFeel.resolve(levelOf(tool), BlasterFx.isPhone())
	pulses = 0
	lastPulse = -math.huge
	setSwirl(tool, true)
	Sfx.play("BlasterStart")
	Sfx.play("BlasterZap")
	Sfx.loop("BlasterHum", true)
	restoreGrip()
	local weld = findGrip(tool)
	if weld then
		grip, gripBase = weld, weld.C1
	end
	kick(2)
	CameraShake.kick(BlasterFeel.Recoil.StartKick * feel.CameraKick)
	BarrelSpin.set(tool, true) -- the minigun's barrels spin up
end

function BlasterFx.stop()
	local tool = current
	if not tool then
		return
	end
	current = nil
	BarrelSpin.set(tool, false) -- ... and run down
	setSwirl(tool, false)
	Sfx.loop("BlasterHum", false)
	Sfx.play("BlasterStop")
	-- the gun settles back on its own (step), then the grip is restored
	bindStep()
end

-- A shot leaves your gun: its sound (higher with the spin), the hum climbing, recoil at most every Pulse.
function BlasterFx.fired(spin: number)
	local now = os.clock()
	local shots = BlasterFeel.Shots
	if now - shotSoundAt >= shots.SoundGap then
		shotSoundAt = now
		Sfx.play("BlasterShot", nil, 1 + 0.2 * spin)
	end
	Sfx.loopPitch("BlasterHum", 0.8 + 0.4 * spin)
	if now - kickAt >= BlasterFeel.Pulse then
		kick(1)
		CameraShake.kick(BlasterFeel.Recoil.PulseKick * feel.CameraKick)
	end
end

--[[
	A shot lands at `point` (`back` points to the shooter). gated = a rock you
	can't mine yet: dull sparks only. rockColor = the rock's crust colour (nil =
	not a rock: the impact only, no hit pulses).
]]
function BlasterFx.hit(point: Vector3, shotGlow: Color3, back: Vector3?, gated: boolean, rockColor: Color3?)
	if gated then
		Vfx.burst("Sparks", point, 1, DULL, back)
		return
	end
	Vfx.impact(point, shotGlow, back, feel.Sparks)
	if not current or not rockColor then
		return
	end
	local now = os.clock()
	if now - lastPulse < BlasterFeel.Pulse then
		return
	end
	lastPulse = now
	pulses += 1
	if pulses % BlasterFeel.TickEvery == 0 then
		Sfx.play("BlastHit", point)
	end
	if pulses % BlasterFeel.ChipEvery == 0 then
		local out = if back and back.Magnitude > 0.01 then back.Unit * 0.6 else Vector3.zero
		Vfx.chips(point + out, feel.Chips, rockColor, 0.8)
		Vfx.burst("Glint", point + out, math.max(1, feel.Sparks), shotGlow:Lerp(Color3.new(1, 1, 1), 0.5))
		Sfx.play("BlastThud", point)
		if feel.Rings > 0 then
			ringAt(point + out * 0.5, shotGlow)
		end
	end
end

-- Is the local player firing (the trigger is down)?
function BlasterFx.isFiring(): boolean
	return current ~= nil
end

return BlasterFx
