--[[
	BlasterFx: how firing your blaster feels (client only, tuned in
	Config/BlasterFeel). MiningController calls:

	  BlasterFx.start(tool)     the trigger goes down: a muzzle flash burst,
	                            the zap sound, the hum and beam loops, a
	                            camera and gun kick; the muzzle flash (and on
	                            Lv7+ the sparkle swirl) runs while firing
	  BlasterFx.beamStyle()     the beam's thickness, light, the Lv7+ energy
	                            stream and the hit swell, for Vfx.setBeam
	  BlasterFx.hit(point, glow, back, gated, rockColor)
	                            where the beam touches something: sparks in
	                            the beam's glow; on a rock you can mine also
	                            the hit pulses (crackle, chips in the rock's
	                            crust colour, a thud, recoil, Lv10 shock
	                            rings); a rock you can't mine yet only gets
	                            dull grey sparks
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

local BlasterFx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local DULL = Color3.fromRGB(200, 200, 220)
local RING_POOL = 3

type ToolFx = { Flash: ParticleEmitter, Swirl: ParticleEmitter }

local toolFx: { [Tool]: ToolFx } = setmetatable({}, { __mode = "k" }) :: any
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
local style: { Width: number, Core: number, Light: number, Energy: boolean, Pulse: number } =
	{ Width = 0.5, Core = 0.16, Light = 1.6, Energy = false, Pulse = 0 }

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

-- The muzzle flash and the Lv7+ swirl on a tool's Muzzle (made once, local only).
local function emittersFor(tool: Tool): ToolFx?
	local existing = toolFx[tool]
	if existing and existing.Flash.Parent then
		return existing
	end
	local muzzle = muzzleOf(tool)
	if not muzzle then
		return nil
	end
	local flash = Instance.new("ParticleEmitter")
	flash.Name = "BlasterFlash"
	flash.Texture = GLOW
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.LockedToPart = true
	flash.Lifetime = NumberRange.new(0.05, 0.09)
	flash.Speed = NumberRange.new(0)
	flash.Rotation = NumberRange.new(0, 360)
	flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	flash.ZOffset = 0.5
	flash.Enabled = false
	flash.Parent = muzzle
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
	local made: ToolFx = { Flash = flash, Swirl = swirl }
	toolFx[tool] = made
	return made
end

local function setEmitters(tool: Tool, on: boolean)
	local fx = emittersFor(tool)
	if not fx then
		return
	end
	local flashColor = glow:Lerp(Color3.new(1, 1, 1), 0.45)
	local size = feel.Tier.Flash
	fx.Flash.Color = ColorSequence.new(flashColor)
	fx.Flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	fx.Flash.Rate = feel.FlashRate
	fx.Flash.Enabled = on
	fx.Swirl.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(glow, 0.5))
	fx.Swirl.Rate = feel.Swirl
	fx.Swirl.Enabled = on and feel.Swirl > 0
	if on then
		-- the opening flash
		fx.Flash:Emit(math.max(2, math.floor(4 * (if BlasterFx.isPhone() then BlasterFeel.Phone.Particles else 1))))
	end
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
	-- the beam swells for a moment on each pulse
	style.Pulse = BlasterFeel.settle((now - lastPulse) * 0.8)
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
	local tier = feel.Tier
	style.Width, style.Core, style.Light, style.Energy = tier.BeamWidth, tier.CoreWidth, tier.Light, tier.Energy
	pulses = 0
	lastPulse = -math.huge
	setEmitters(tool, true)
	Sfx.play("BlasterStart")
	Sfx.play("BlasterZap")
	Sfx.loop("BlasterHum", true)
	Sfx.loop("BlasterBeam", true)
	restoreGrip()
	local weld = findGrip(tool)
	if weld then
		grip, gripBase = weld, weld.C1
	end
	kick(2)
	CameraShake.kick(BlasterFeel.Recoil.StartKick * feel.CameraKick)
end

function BlasterFx.stop()
	local tool = current
	if not tool then
		return
	end
	current = nil
	local fx = toolFx[tool]
	if fx then
		fx.Flash.Enabled = false
		fx.Swirl.Enabled = false
	end
	Sfx.loop("BlasterHum", false)
	Sfx.loop("BlasterBeam", false)
	Sfx.play("BlasterStop")
	style.Pulse = 0
	-- the gun settles back on its own (step), then the grip is restored
	bindStep()
end

-- The beam's look for Vfx.setBeam (one table, updated in place).
function BlasterFx.beamStyle(): Vfx.BeamStyle
	return style
end

-- A beam style for another player's blaster level (their beams get the tier look too).
function BlasterFx.styleFor(level: any): Vfx.BeamStyle
	local tier = BlasterFeel.tier(level)
	return { Width = tier.BeamWidth, Core = tier.CoreWidth, Light = tier.Light, Energy = tier.Energy, Pulse = 0 }
end

--[[
	The beam touches something at `point` (`back` points to the shooter).
	gated = a rock you can't mine yet: dull sparks only. rockColor = the
	rock's crust colour (nil = not a rock: sparks only, no hit pulses).
]]
function BlasterFx.hit(point: Vector3, beamGlow: Color3, back: Vector3?, gated: boolean, rockColor: Color3?)
	if gated then
		Vfx.burst("Sparks", point, 2, DULL, back)
		return
	end
	Vfx.impact(point, beamGlow, back, feel.Sparks)
	if not current or not rockColor then
		return
	end
	local now = os.clock()
	if now - lastPulse < BlasterFeel.Pulse then
		return
	end
	lastPulse = now
	pulses += 1
	kick(1)
	CameraShake.kick(BlasterFeel.Recoil.PulseKick * feel.CameraKick)
	if pulses % BlasterFeel.TickEvery == 0 then
		Sfx.play("BlastHit", point)
	end
	if pulses % BlasterFeel.ChipEvery == 0 then
		local out = if back and back.Magnitude > 0.01 then back.Unit * 0.6 else Vector3.zero
		Vfx.chips(point + out, feel.Chips, rockColor, 0.8)
		Vfx.burst("Glint", point + out, math.max(1, feel.Sparks // 2), beamGlow:Lerp(Color3.new(1, 1, 1), 0.5))
		Sfx.play("BlastThud", point)
		if feel.Rings > 0 then
			ringAt(point + out * 0.5, beamGlow)
		end
	end
end

-- Is the local player firing (the trigger is down)?
function BlasterFx.isFiring(): boolean
	return current ~= nil
end

return BlasterFx
