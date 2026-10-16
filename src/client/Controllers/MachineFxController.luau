--[[
	MachineFxController: all machine juice, played from the attributes the
	server sets on machine models (Working, Queue, Cycles...). No remotes
	per tick; the server never waits on any of this.

	- Machines are found by the 'Machine' tag, so streaming in and out just
	  works. Every 0.5 s the machines within 80 studs become active; only
	  those get per-frame work and one-off effects. A machine that leaves
	  the range is put back to its idle look.
	- Working: furnaces pulse their glow, light, embers and chimney smoke;
	  Crusher rollers and the Auto Cleaner drum spin (easing in and out) and
	  the cleaner's vent smokes more. One hum loop plays on the nearest 4
	  working machines within 60 studs (4 pooled sounds).
	- Queue goes up: gulp + dust at the hopper. Cycles goes up: a done click
	  and a glint in the ore's colour at the output (and a tiny shake for
	  your own machine up close); a crate gulps, a Sell Chute flashes coins.
	- Anvil: ingot stubs on IngotSlot1..n (Ingots, IngotOre), glowing while
	  Forging.
	- Progress billboards over YOUR busy machines (MachineBillboard, at most 12).
	- Fx 'Reject': red dust + a reject sound where a machine refused an item.
	- Water (Cleaning Station, Auto Cleaner: Base attachments WaterOut and
	  WaterIn from MachineBuilder): the nearest WATER_MAX wet machines within
	  WATER_RANGE borrow a pooled rig (an invisible anchor with two Beams for
	  the stream - a see-through light blue ribbon and a faint highlight -
	  soft round droplet / mist / ripple / spray emitters with built-in
	  textures). It always runs gently and gets stronger while the machine
	  works (Working, or Busy for a station someone is cleaning at); the
	  basin's WaterPool shimmers. Emitter rates follow the graphics quality
	  (half on low quality and on phones left on automatic). Leaving the range
	  gives the rig back.
	- Auto Cleaner: the bed rollers turn with the drum, the stacked light
	  lights one lamp: green (working), amber (idle) or red (blocked), and the
	  built look (MachineBuilder.Stack.Lit) out of range. Crusher: the side
	  cogs turn with the rollers. Furnaces: the Molten parts (glass sections,
	  mould) pulse with the Glow.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local SoundConfig = require(Shared.Config.SoundConfig)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local MachineBillboard = require(script.Parent.Parent.UI.MachineBillboard)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local FxController = require(script.Parent.FxController)

local MachineFxController = {}

-- Rest pose of a spinning part, both relative to the machine's Base.
type Spinner = { Part: BasePart, Rest: CFrame, Axis: CFrame, Dir: number }
type Emitter = { Emitter: ParticleEmitter, Idle: number, Busy: number }

-- Pooled client water: Beams between Out and In, emitters at the landing
-- point (Splash) and the outlet (Nozzle). All attachments sit on Anchor,
-- which is moved onto the machine's Base.
type WaterRig = {
	Anchor: Part,
	Out: Attachment,
	In: Attachment,
	Splash: Attachment,
	Nozzle: Attachment,
	Stream: Beam,
	Core: Beam,
	Drops: ParticleEmitter,
	Mist: ParticleEmitter,
	Ripple: ParticleEmitter,
	Spray: ParticleEmitter,
	Placed: CFrame?,
	Width1: number, -- stream end width before the wobble
}

type Fx = {
	Model: Model,
	Id: string,
	Base: BasePart?,
	-- replicated attributes, each updated by its own change signal (so in
	-- the Cycles handler WorkOre is still the ore of the job that finished)
	Attr: { [string]: any },
	Active: boolean,
	Distance: number,
	Heat: number, -- 0 idle .. 1 working, eased
	Applied: number, -- heat last written to lights and emitters
	Phase: number,
	Angle: number,
	SpinRate: number,
	Spinners: { Spinner },
	Emitters: { Emitter },
	Glow: BasePart?,
	GlowColor: Color3,
	Light: PointLight?,
	LightIdle: number,
	LightBusy: number,
	Coins: BasePart?,
	CoinsColor: Color3,
	CoinsLight: PointLight?,
	CoinsIdle: number,
	Flash: number,
	Stubs: { BasePart },
	StubsDirty: boolean,
	ForgeLight: PointLight?,
	Billboard: MachineBillboard.Refs?,
	Connections: { RBXScriptConnection },
	-- molten parts that pulse with the Glow (furnaces)
	Hot: { BasePart },
	HotColors: { Color3 },
	-- water (see WaterRig)
	HasWater: boolean,
	Spray: boolean,
	Water: WaterRig?,
	Flow: number, -- 0 gentle .. 1 working, eased
	FlowApplied: number,
	Pool: BasePart?,
	PoolColor: Color3,
	PoolTransparency: number,
	-- stacked status light (Auto Cleaner)
	Signals: { [string]: BasePart }?,
	SignalState: string?,
}

type Hum = { Part: Part, Sound: Sound, Target: Fx? }

local ACTIVE_RANGE = 80
local SELECT_INTERVAL = 0.5
local HUM_RANGE = 60
local HUM_COUNT = 4
local SHAKE_RANGE = 25
local SHAKE = 0.06
local BILLBOARD_RANGE = 50 -- MachineBillboard hides itself beyond 45
local MAX_BILLBOARDS = 12
local HEAT_RATE = 1.6 -- per second: how fast glow and spin ease in and out
local FLASH_DECAY = 2.5
local SPIN_RATE: { [string]: number } = { Crusher = 6, AutoCleaner = 3 } -- rad/s
-- working looks: emitter rates and light brightness at full heat
local EMBERS_BUSY = 14
local SMOKE_BUSY: { [string]: number } = { ClayFurnace = 6, BlastFurnace = 12 }
local VENT_FACTOR = 3
local LIGHT_BUSY = 2.8
local STUB_SIZE = Vector3.new(1.5, 0.45, 0.75)
local STUB_DROP = -0.22 -- from the slot attachment down onto the anvil face
local REJECT_COLOR = Color3.fromRGB(235, 72, 60)
local HOT = Color3.fromRGB(255, 140, 50)
local BED_ROLLER_DIR = -1 -- roller tops move toward the front (-Z)
-- water
local WATER_RANGE = 48 -- a stream is a few pixels wide beyond this
local WATER_MAX = 4 -- rigs in use at once (nearest wet machines)
local FLOW_RATE = 1.2 -- per second
local SOFT = "rbxasset://textures/particles/smoke_main.dds"
local WATER = MachineBuilder.Water
local STACK = MachineBuilder.Stack
local SIGNALS = { "StackRed", "StackAmber", "StackGreen" }

local player = Players.LocalPlayer
local machines: { [Model]: Fx } = {}
local active: { Fx } = {}
local hums: { Hum } = {}
local rigPool: { WaterRig } = {}
local fxFolder: Folder? = nil
local clock = 0
local quality = 1 -- emitter rate scale from the graphics quality

---------------------------------------------------------------- helpers

local function number(fx: Fx, name: string): number
	local value = fx.Attr[name]
	return if type(value) == "number" and value == value then value else 0
end

local function isOwn(fx: Fx): boolean
	return fx.Attr.Owner == player.UserId
end

local function oreOf(oreId: any): OreData.Ore?
	return if type(oreId) == "string" then OreData.ById[oreId] else nil
end

local function folder(): Folder
	local current = fxFolder
	if current and current.Parent then
		return current
	end
	local f = Instance.new("Folder")
	f.Name = "ClientMachineFx"
	f.Parent = Workspace
	fxFolder = f
	return f
end

-- World position of a Base attachment (falls back to the model's pivot).
local function pointOf(fx: Fx, name: string): Vector3
	local base = fx.Base
	local attachment = base and base:FindFirstChild(name)
	if base and attachment and attachment:IsA("Attachment") then
		return (base.CFrame * attachment.CFrame).Position
	end
	return fx.Model:GetPivot().Position
end

local function focusPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- Emitter rate scale for the player's graphics quality: half on low
-- quality (and on touch-only devices left on automatic), 3/4 on medium.
local function qualityScale(): number
	local ok, level = pcall(function(): number
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if not ok or type(level) ~= "number" then
		return 1
	end
	if level <= 0 then -- automatic
		return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 0.5 else 1
	end
	return if level <= 3 then 0.5 elseif level <= 6 then 0.75 else 1
end

---------------------------------------------------------------- looks

local function emitterOn(fx: Fx, part: Instance?, name: string, busy: number?)
	local emitter = part and part:FindFirstChild(name)
	if emitter and emitter:IsA("ParticleEmitter") then
		table.insert(fx.Emitters, { Emitter = emitter, Idle = emitter.Rate, Busy = busy or emitter.Rate })
	end
end

local function addSpinners(fx: Fx, base: BasePart, axisName: string, partNames: { string }, dir: number)
	local axisPart = fx.Model:FindFirstChild(axisName)
	if not axisPart or not axisPart:IsA("BasePart") then
		return
	end
	local axis = base.CFrame:ToObjectSpace(axisPart.CFrame)
	for _, child in fx.Model:GetChildren() do
		if child:IsA("BasePart") and table.find(partNames, child.Name) then
			table.insert(fx.Spinners, { Part = child, Rest = base.CFrame:ToObjectSpace(child.CFrame), Axis = axis, Dir = dir })
		end
	end
end

-- Parts that each turn around their own axis (cylinders run along X).
local function addSelfSpinners(fx: Fx, base: BasePart, partName: string, dir: number)
	for _, child in fx.Model:GetChildren() do
		if child:IsA("BasePart") and child.Name == partName then
			local rest = base.CFrame:ToObjectSpace(child.CFrame)
			table.insert(fx.Spinners, { Part = child, Rest = rest, Axis = rest, Dir = dir })
		end
	end
end

-- The machine's water hooks (Base attachments WaterOut / WaterIn, a basin
-- part WaterPool).
local function captureWater(fx: Fx)
	local base = fx.Base
	local out = base and base:FindFirstChild("WaterOut")
	local into = base and base:FindFirstChild("WaterIn")
	if not (out and out:IsA("Attachment") and into and into:IsA("Attachment")) then
		return
	end
	fx.HasWater = true
	fx.Spray = out:GetAttribute("Spray") == true
	local pool = fx.Model:FindFirstChild("WaterPool")
	if pool and pool:IsA("BasePart") then
		fx.Pool = pool
		fx.PoolColor = pool.Color
		fx.PoolTransparency = pool.Transparency
	end
end

-- Finds the parts each machine type animates (names from MachineBuilder).
local function capture(fx: Fx)
	local model, base = fx.Model, fx.Base
	local id = fx.Id
	if id == "ClayFurnace" or id == "BlastFurnace" then
		local glow = model:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then
			fx.Glow = glow
			fx.GlowColor = glow.Color
			local light = glow:FindFirstChildOfClass("PointLight")
			if light then
				fx.Light = light
				fx.LightIdle = light.Brightness
				fx.LightBusy = math.max(light.Brightness, LIGHT_BUSY)
			end
		end
		emitterOn(fx, glow, "Embers", EMBERS_BUSY)
		emitterOn(fx, model:FindFirstChild("ChimneyTop"), "Smoke", SMOKE_BUSY[id])
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Molten" then
				table.insert(fx.Hot, child)
				table.insert(fx.HotColors, child.Color)
			end
		end
	elseif id == "AutoCleaner" then
		local vent = model:FindFirstChild("Vent")
		local smoke = vent and vent:FindFirstChild("Smoke")
		if smoke and smoke:IsA("ParticleEmitter") then
			emitterOn(fx, vent, "Smoke", smoke.Rate * VENT_FACTOR)
		end
		if base then
			addSpinners(fx, base, "Drum", { "Drum", "DrumRib" }, 1)
			addSelfSpinners(fx, base, "BedRoller", BED_ROLLER_DIR)
		end
		local lamps: { [string]: BasePart } = {}
		local found = false
		for _, name in SIGNALS do
			local lamp = model:FindFirstChild(name)
			if lamp and lamp:IsA("BasePart") then
				lamps[name] = lamp
				found = true
			end
		end
		if found then
			fx.Signals = lamps
		end
	elseif id == "Crusher" then
		if base then
			-- the two rollers turn toward each other
			addSpinners(fx, base, "Roller1", { "Roller1", "Roller1Tooth" }, 1)
			addSpinners(fx, base, "Roller2", { "Roller2", "Roller2Tooth" }, -1)
			-- side cogs: each name sits on one axis line on both sides
			addSpinners(fx, base, "Cog1", { "Cog1" }, 1)
			addSpinners(fx, base, "Cog2", { "Cog2" }, -MachineBuilder.CogRatio)
		end
	elseif id == "SellChute" then
		local coins = model:FindFirstChild("Coins")
		if coins and coins:IsA("BasePart") then
			fx.Coins = coins
			fx.CoinsColor = coins.Color
			local light = coins:FindFirstChildOfClass("PointLight")
			if light then
				fx.CoinsLight = light
				fx.CoinsIdle = light.Brightness
			end
		end
	end
	fx.SpinRate = SPIN_RATE[id] or 0
	captureWater(fx)
end

-- Lights and emitter rates for the current heat (no pulse).
local function applyHeat(fx: Fx)
	local heat = fx.Heat
	fx.Applied = heat
	for _, e in fx.Emitters do
		e.Emitter.Rate = e.Idle + (e.Busy - e.Idle) * heat
	end
	local light = fx.Light
	if light then
		light.Brightness = fx.LightIdle + (fx.LightBusy - fx.LightIdle) * heat
	end
	local glow = fx.Glow
	if glow and heat <= 0 then
		glow.Color = fx.GlowColor
	end
	if heat <= 0 then
		for i, part in fx.Hot do
			part.Color = fx.HotColors[i]
		end
	end
end

---------------------------------------------------------------- status light

-- Auto Cleaner stack light, one lamp lit: green while working, red when
-- blocked, amber when idle; the built look (Stack.Lit) while out of range.
local function applySignal(fx: Fx)
	local lamps = fx.Signals
	if not lamps then
		return
	end
	local status = fx.Attr.Status
	local state = if not fx.Active
		then STACK.Lit
		elseif fx.Attr.Working == true then "StackGreen"
		elseif type(status) == "string" and status ~= "" then "StackRed"
		else "StackAmber"
	if state == fx.SignalState then
		return
	end
	fx.SignalState = state
	for name, lamp in lamps do
		local lit = name == state
		local color = STACK.Lamps[name] or lamp.Color
		lamp.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lamp.Color = if lit then color else color:Lerp(Color3.new(0, 0, 0), STACK.Dim)
	end
end

---------------------------------------------------------------- water

local function waterAttachment(anchor: Part, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = anchor
	return a
end

local function waterBeam(anchor: Part, name: string, out: Attachment, into: Attachment, color: ColorSequence, emission: number): Beam
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0 = out
	b.Attachment1 = into
	b.FaceCamera = true
	b.Segments = 12
	b.Color = color
	b.LightEmission = emission
	b.LightInfluence = 0.6
	b.Enabled = false
	b.Parent = anchor
	return b
end

local function waterEmitter(parent: Attachment, name: string, texture: string, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightInfluence = 0.6
	e.Rate = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

-- One rig (built once, then pooled): stream + core Beams, droplets, mist,
-- ripples on the pool and a shower spray. Soft round particles only (no
-- star glints): water, not magic.
local function newRig(): WaterRig
	local anchor = Instance.new("Part")
	anchor.Name = "WaterRig"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local out = waterAttachment(anchor, "Out")
	local into = waterAttachment(anchor, "In")
	local splash = waterAttachment(anchor, "Splash")
	local nozzle = waterAttachment(anchor, "Nozzle")

	-- the stream: see-through light blue, deeper blue where it lands, a long
	-- soft texture scrolling down it
	local stream = waterBeam(anchor, "Stream", out, into, ColorSequence.new(WATER.Stream, WATER.Deep), 0.1)
	stream.Texture = SOFT
	stream.TextureMode = Enum.TextureMode.Wrap
	stream.TextureLength = 3.5
	stream.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.38),
		NumberSequenceKeypoint.new(0.75, 0.42),
		NumberSequenceKeypoint.new(1, 0.62),
	})
	-- a faint highlight down the middle (stays see-through, tinted blue)
	local core = waterBeam(anchor, "Core", out, into, ColorSequence.new(WATER.Core, WATER.Stream), 0.15)
	core.Transparency = NumberSequence.new(0.6, 0.8)

	-- droplets jumping out where the water lands
	local drops = waterEmitter(splash, "Drops", SOFT, WATER.Splash)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Size = NumberSequence.new(0.16, 0.08)
	drops.Transparency = NumberSequence.new(0.2, 1)
	drops.Lifetime = NumberRange.new(0.35, 0.6)
	drops.Speed = NumberRange.new(3, 6)
	drops.SpreadAngle = Vector2.new(40, 40)
	drops.Acceleration = Vector3.new(0, -32, 0)
	drops.Drag = 1
	drops.LightEmission = 0
	-- a soft puff of mist
	local mist = waterEmitter(splash, "Mist", SOFT, WATER.Splash)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Size = NumberSequence.new(0.5, 1.4)
	mist.Transparency = NumberSequence.new(0.72, 1)
	mist.Lifetime = NumberRange.new(0.5, 0.9)
	mist.Speed = NumberRange.new(0.6, 1.4)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.LightInfluence = 0.8
	-- ripples lying flat on the pool, growing and fading
	local ripple = waterEmitter(splash, "Ripple", SOFT, WATER.Splash)
	ripple.EmissionDirection = Enum.NormalId.Top
	ripple.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ripple.Size = NumberSequence.new(0.3, 1.5)
	ripple.Transparency = NumberSequence.new(0.5, 1)
	ripple.Lifetime = NumberRange.new(0.8, 1)
	ripple.Speed = NumberRange.new(0.02, 0.02)
	ripple.LightEmission = 0.1
	-- shower spray out of a nozzle (Spray outlets)
	local spray = waterEmitter(nozzle, "Spray", SOFT, WATER.Splash:Lerp(WATER.Stream, 0.4))
	spray.EmissionDirection = Enum.NormalId.Bottom
	spray.Size = NumberSequence.new(0.12, 0.08)
	spray.Transparency = NumberSequence.new(0.25, 1)
	spray.Lifetime = NumberRange.new(0.3, 0.45)
	spray.Speed = NumberRange.new(4, 7)
	spray.SpreadAngle = Vector2.new(16, 16)
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.LightEmission = 0

	return {
		Anchor = anchor,
		Out = out,
		In = into,
		Splash = splash,
		Nozzle = nozzle,
		Stream = stream,
		Core = core,
		Drops = drops,
		Mist = mist,
		Ripple = ripple,
		Spray = spray,
		Placed = nil,
		Width1 = WATER.WidthEnd,
	}
end

local function rigEnabled(rig: WaterRig, on: boolean, spray: boolean)
	rig.Stream.Enabled = on
	rig.Core.Enabled = on
	rig.Drops.Enabled = on
	rig.Mist.Enabled = on
	rig.Ripple.Enabled = on
	rig.Spray.Enabled = on and spray
end

-- Moves the rig onto the machine (copies WaterOut / WaterIn and the curve).
local function placeRig(fx: Fx)
	local rig, base = fx.Water, fx.Base
	if not rig or not base then
		return
	end
	local out = base:FindFirstChild("WaterOut")
	local into = base:FindFirstChild("WaterIn")
	if not (out and out:IsA("Attachment") and into and into:IsA("Attachment")) then
		return
	end
	rig.Anchor.CFrame = base.CFrame
	rig.Placed = base.CFrame
	rig.Out.CFrame = out.CFrame
	rig.In.CFrame = into.CFrame
	rig.Splash.CFrame = CFrame.new(into.CFrame.Position)
	rig.Nozzle.CFrame = CFrame.new(out.CFrame.Position)
	local c0, c1 = out:GetAttribute("Curve"), into:GetAttribute("Curve")
	for _, beam in { rig.Stream, rig.Core } do
		beam.CurveSize0 = if type(c0) == "number" then c0 else 0
		beam.CurveSize1 = if type(c1) == "number" then c1 else 0
	end
end

-- Widths and rates for the current flow (gentle 0 .. working 1), rates
-- scaled by the graphics quality.
local function applyFlow(fx: Fx)
	local rig = fx.Water
	if not rig then
		return
	end
	local f = fx.Flow
	fx.FlowApplied = f
	local k = 0.55 + 0.45 * f
	local q = quality
	if fx.Spray then
		rig.Stream.Width0 = WATER.SprayWidth * k
		rig.Width1 = WATER.SprayWidthEnd * k
		rig.Core.Width0 = 0.12 * k
		rig.Core.Width1 = 0.5 * k
		rig.Spray.Rate = (10 + 26 * f) * q
	else
		rig.Stream.Width0 = WATER.Width * k
		rig.Width1 = WATER.WidthEnd * k
		rig.Core.Width0 = WATER.Width * 0.3 * k
		rig.Core.Width1 = WATER.WidthEnd * 0.3 * k
		rig.Spray.Rate = 0
	end
	rig.Stream.Width1 = rig.Width1
	rig.Stream.TextureSpeed = 1.2 + 1.8 * f
	rig.Drops.Rate = (8 + 18 * f) * q
	rig.Mist.Rate = (1.5 + 3 * f) * q
	rig.Ripple.Rate = if fx.Pool then (1.5 + 2.5 * f) * q else 0
end

local function restorePool(fx: Fx)
	local pool = fx.Pool
	if pool then
		pool.Color = fx.PoolColor
		pool.Transparency = fx.PoolTransparency
	end
end

local function releaseRig(fx: Fx)
	local rig = fx.Water
	if not rig then
		return
	end
	fx.Water = nil
	rigEnabled(rig, false, false)
	restorePool(fx)
	table.insert(rigPool, rig)
end

-- False when the rig can't be parented any more (its folder was destroyed).
local function parentRig(rig: WaterRig): boolean
	return pcall(function()
		rig.Anchor.Parent = folder()
	end)
end

local function acquireRig(fx: Fx)
	if fx.Water or not fx.HasWater then
		return
	end
	local pooled = table.remove(rigPool)
	local ready: WaterRig
	if pooled and parentRig(pooled) then
		ready = pooled
	else
		ready = newRig()
		ready.Anchor.Parent = folder()
	end
	fx.Water = ready
	fx.Flow = if fx.Attr.Working == true or fx.Attr.Busy == true then 1 else 0
	placeRig(fx)
	applyFlow(fx)
	rigEnabled(ready, true, fx.Spray)
end

-- Per frame for a machine with a rig: ease the flow, follow the machine,
-- wobble the stream, shimmer the pool.
local function stepWater(fx: Fx, dt: number)
	local rig = fx.Water
	local base = fx.Base
	if not rig or not base then
		return
	end
	if rig.Placed ~= base.CFrame then
		placeRig(fx)
	end
	local target = if fx.Attr.Working == true or fx.Attr.Busy == true then 1 else 0
	if fx.Flow ~= target then
		local delta = FLOW_RATE * dt
		fx.Flow = if fx.Flow < target then math.min(target, fx.Flow + delta) else math.max(target, fx.Flow - delta)
	end
	if math.abs(fx.Flow - fx.FlowApplied) > 0.03 or (fx.Flow == target and fx.FlowApplied ~= target) then
		applyFlow(fx)
	end
	rig.Stream.Width1 = rig.Width1 * (1 + 0.08 * math.sin(clock * 9 + fx.Phase))
	local pool = fx.Pool
	if pool then
		local wave = math.sin(clock * 2.2 + fx.Phase)
		pool.Color = fx.PoolColor:Lerp(WATER.Stream, 0.18 + 0.12 * wave * (0.5 + 0.5 * fx.Flow))
		pool.Transparency = fx.PoolTransparency + 0.06 * math.sin(clock * 3.3 + fx.Phase)
	end
end

---------------------------------------------------------------- anvil stubs

local function clearStubs(fx: Fx)
	for _, stub in fx.Stubs do
		stub:Destroy()
	end
	table.clear(fx.Stubs)
	local light = fx.ForgeLight
	if light then
		light:Destroy()
		fx.ForgeLight = nil
	end
end

-- Ingot stubs on the anvil's slots (local parts) and a glow while forging.
local function refreshStubs(fx: Fx)
	fx.StubsDirty = false
	local base = fx.Base
	if not fx.Active or not base then
		clearStubs(fx)
		return
	end
	local wanted = math.clamp(math.floor(number(fx, "Ingots")), 0, 4)
	while #fx.Stubs > wanted do
		local stub = table.remove(fx.Stubs) :: BasePart
		stub:Destroy()
	end
	local forging = fx.Attr.Forging == true
	local ore = oreOf(fx.Attr.IngotOre)
	local color = if ore then ore.Color else Color3.fromRGB(150, 150, 160)
	for i = 1, wanted do
		local slot = base:FindFirstChild("IngotSlot" .. i)
		local cf = if slot and slot:IsA("Attachment")
			then base.CFrame * slot.CFrame * CFrame.new(0, STUB_DROP, 0)
			else base.CFrame * CFrame.new(0, 5, 0)
		local stub = fx.Stubs[i]
		if not stub then
			local part = Instance.new("Part")
			part.Name = "IngotStub"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Size = STUB_SIZE
			part.Parent = folder()
			fx.Stubs[i] = part
			stub = part
		end
		stub.CFrame = cf
		stub.Color = if forging then color:Lerp(HOT, 0.55) else color
		stub.Material = if forging then Enum.Material.Neon else Enum.Material.Metal
	end
	local light = fx.ForgeLight
	if forging and not light then
		local glow = Instance.new("PointLight")
		glow.Name = "AnvilGlow"
		glow.Color = HOT
		glow.Range = 10
		glow.Brightness = 2
		glow.Shadows = false
		glow.Parent = base:FindFirstChild("AnvilPoint") or base
		fx.ForgeLight = glow
	elseif light and not forging then
		light:Destroy()
		fx.ForgeLight = nil
	end
end

---------------------------------------------------------------- one-off effects

local function onQueueUp(fx: Fx)
	local position = pointOf(fx, "Intake")
	Sfx.play("Gulp", position)
	Vfx.burst("Dust", position, 4)
end

local function onCyclesUp(fx: Fx)
	local id = fx.Id
	if id == "StorageCrate" then
		Sfx.play("Gulp", pointOf(fx, "Intake"))
		return
	end
	if id == "SellChute" then
		fx.Flash = 1
		local coins = fx.Coins
		Vfx.burst("Glint", if coins then coins.Position else pointOf(fx, "Intake"), 6, Color3.fromRGB(255, 214, 90))
		return
	end
	-- Attr.WorkOre still holds the finished job's ore here: a new job's
	-- WorkOre change signal comes after this Cycles one
	local ore = oreOf(fx.Attr.WorkOre or fx.Attr.IngotOre)
	local position = pointOf(fx, "Output")
	Sfx.play("MachineDone", position)
	Vfx.burst("Glint", position, 8, if ore then ore.Glow else nil)
	if isOwn(fx) and fx.Distance <= SHAKE_RANGE then
		CameraShake.add(SHAKE)
	end
end

local function onWorkStart(fx: Fx)
	local id = fx.Id
	if id == "ClayFurnace" or id == "BlastFurnace" then
		local glow = fx.Glow
		Sfx.play("Furnace", if glow then glow.Position else pointOf(fx, "Prompt"))
	elseif id == "Crusher" then
		Sfx.play("Crusher", pointOf(fx, "Intake"))
	end
end

local function onAttribute(fx: Fx, name: string)
	local value = fx.Model:GetAttribute(name)
	local before = fx.Attr[name]
	fx.Attr[name] = value
	if name == "Queue" then
		if fx.Active and type(value) == "number" and type(before) == "number" and value > before then
			onQueueUp(fx)
		end
	elseif name == "Cycles" then
		if fx.Active and type(value) == "number" and type(before) == "number" and value > before then
			onCyclesUp(fx)
		end
	elseif name == "Working" then
		if fx.Active and value == true and before ~= true then
			onWorkStart(fx)
		end
		applySignal(fx)
	elseif name == "Status" then
		applySignal(fx)
	elseif name == "GridX" or name == "GridZ" or name == "Rotation" then
		-- moved: the server put every part back in its rest pose
		fx.Angle = 0
		fx.StubsDirty = true
	elseif name == "Ingots" or name == "IngotOre" or name == "Forging" then
		fx.StubsDirty = true
	end
end

---------------------------------------------------------------- registry

local function setActive(fx: Fx, on: boolean)
	if fx.Active == on then
		return
	end
	fx.Active = on
	if on then
		-- walking up to a working machine: it is already going
		fx.Heat = if fx.Attr.Working == true then 1 else 0
		applyHeat(fx)
		fx.StubsDirty = true
		applySignal(fx)
		return
	end
	-- back to the idle look
	fx.Heat = 0
	applyHeat(fx)
	releaseRig(fx)
	applySignal(fx)
	fx.Flash = 0
	local coins = fx.Coins
	if coins then
		coins.Color = fx.CoinsColor
	end
	local coinsLight = fx.CoinsLight
	if coinsLight then
		coinsLight.Brightness = fx.CoinsIdle
	end
	clearStubs(fx)
	local refs = fx.Billboard
	if refs then
		MachineBillboard.detach(refs)
		fx.Billboard = nil
	end
	local index = table.find(active, fx)
	if index then
		table.remove(active, index)
	end
end

local function register(instance: Instance)
	if not instance:IsA("Model") or machines[instance] then
		return
	end
	local model = instance :: Model
	local id = model:GetAttribute("MachineId")
	if type(id) ~= "string" or id == "Conveyor" then
		return
	end
	local base = model.PrimaryPart or model:FindFirstChild("Base")
	local fx: Fx = {
		Model = model,
		Id = id,
		Base = if base and base:IsA("BasePart") then base else nil,
		Attr = model:GetAttributes(),
		Active = false,
		Distance = math.huge,
		Heat = 0,
		Applied = 0,
		Phase = math.random() * 6,
		Angle = 0,
		SpinRate = 0,
		Spinners = {},
		Emitters = {},
		Glow = nil,
		GlowColor = Color3.new(1, 1, 1),
		Light = nil,
		LightIdle = 0,
		LightBusy = 0,
		Coins = nil,
		CoinsColor = Color3.new(1, 1, 1),
		CoinsLight = nil,
		CoinsIdle = 0,
		Flash = 0,
		Stubs = {},
		StubsDirty = false,
		ForgeLight = nil,
		Billboard = nil,
		Connections = {},
		Hot = {},
		HotColors = {},
		HasWater = false,
		Spray = false,
		Water = nil,
		Flow = 0,
		FlowApplied = 0,
		Pool = nil,
		PoolColor = Color3.new(1, 1, 1),
		PoolTransparency = 0,
		Signals = nil,
		SignalState = nil,
	}
	capture(fx)
	table.insert(
		fx.Connections,
		model.AttributeChanged:Connect(function(name)
			onAttribute(fx, name)
		end)
	)
	machines[model] = fx
end

local function unregister(instance: Instance)
	local fx = machines[instance :: Model]
	if not fx then
		return
	end
	machines[instance :: Model] = nil
	setActive(fx, false)
	for _, connection in fx.Connections do
		connection:Disconnect()
	end
	for _, hum in hums do
		if hum.Target == fx then
			hum.Target = nil
			hum.Sound:Stop()
		end
	end
end

---------------------------------------------------------------- hum pool

local function ensureHums()
	if #hums > 0 then
		return
	end
	local def = SoundConfig.MachineHum
	for i = 1, HUM_COUNT do
		local part = Instance.new("Part")
		part.Name = "MachineHum" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = folder()
		local sound = Instance.new("Sound")
		sound.Name = "Hum"
		if def then
			sound.SoundId = def.Id
			sound.Volume = def.Volume
			sound.PlaybackSpeed = def.Pitch[1] + (def.Pitch[2] - def.Pitch[1]) * math.random()
		end
		sound.Looped = true
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = HUM_RANGE
		sound.Parent = part
		table.insert(hums, { Part = part, Sound = sound, Target = nil })
	end
end

local function assignHums(candidates: { Fx })
	if #candidates == 0 and #hums == 0 then
		return
	end
	ensureHums()
	for i, hum in hums do
		local target = candidates[i]
		hum.Target = target
		if target then
			hum.Part.CFrame = CFrame.new(pointOf(target, "Intake"))
			if not hum.Sound.IsPlaying then
				hum.Sound:Play()
			end
		elseif hum.Sound.IsPlaying then
			hum.Sound:Stop()
		end
	end
end

---------------------------------------------------------------- selection (every 0.5 s)

local function wantsBillboard(fx: Fx): boolean
	if not isOwn(fx) or fx.Distance > BILLBOARD_RANGE then
		return false
	end
	local status = fx.Attr.Status
	return number(fx, "Queue") > 0 or fx.Attr.Working == true or (type(status) == "string" and status ~= "")
end

local function byDistance(a: Fx, b: Fx): boolean
	return a.Distance < b.Distance
end

local function pickActive()
	local focus = focusPosition()
	table.clear(active)
	for model, fx in machines do
		local inRange = false
		if focus and model.Parent then
			fx.Distance = (model:GetPivot().Position - focus).Magnitude
			inRange = fx.Distance <= ACTIVE_RANGE
		else
			fx.Distance = math.huge
		end
		setActive(fx, inRange)
		if inRange then
			table.insert(active, fx)
		end
	end
	table.sort(active, byDistance)

	-- graphics quality changed: re-apply the water rates
	local q = qualityScale()
	if q ~= quality then
		quality = q
		for _, fx in active do
			if fx.Water then
				applyFlow(fx)
			end
		end
	end

	-- water rigs: the nearest WATER_MAX wet machines within WATER_RANGE
	-- (give rigs back first)
	local wanted: { Fx } = {}
	for _, fx in active do
		if fx.HasWater then
			if fx.Distance <= WATER_RANGE and #wanted < WATER_MAX then
				table.insert(wanted, fx)
			else
				releaseRig(fx)
			end
		end
	end
	for _, fx in wanted do
		acquireRig(fx)
	end

	local humming: { Fx } = {}
	local signs = 0
	for _, fx in active do
		if fx.Attr.Working == true and fx.Distance <= HUM_RANGE and #humming < HUM_COUNT then
			table.insert(humming, fx)
		end
		if wantsBillboard(fx) and signs < MAX_BILLBOARDS then
			signs += 1
			if not fx.Billboard then
				fx.Billboard = MachineBillboard.attach(fx.Model)
			end
		elseif fx.Billboard then
			MachineBillboard.detach(fx.Billboard :: MachineBillboard.Refs)
			fx.Billboard = nil
		end
	end
	assignHums(humming)
end

---------------------------------------------------------------- per frame (active machines only)

-- spinning parts moved in one BulkMoveTo per frame (reused lists)
local spinParts: { BasePart } = {}
local spinFrames: { CFrame } = {}

local function step(dt: number)
	clock += dt
	table.clear(spinParts)
	table.clear(spinFrames)
	local serverNow = Workspace:GetServerTimeNow()
	for _, fx in active do
		if not fx.Model.Parent then
			continue -- gone; unregister follows
		end
		local base = fx.Base
		-- ease toward working / idle
		local target = if fx.Attr.Working == true then 1 else 0
		if fx.Heat ~= target then
			local delta = HEAT_RATE * dt
			fx.Heat = if fx.Heat < target then math.min(target, fx.Heat + delta) else math.max(target, fx.Heat - delta)
		end
		if math.abs(fx.Heat - fx.Applied) > 0.02 or (fx.Heat == 0 and fx.Applied ~= 0) then
			applyHeat(fx)
		end
		if fx.Heat > 0 then
			local pulse = math.sin(clock * 5 + fx.Phase) * 0.5 + 0.5
			local light = fx.Light
			if light then
				local bright = fx.LightIdle + (fx.LightBusy - fx.LightIdle) * fx.Heat
				light.Brightness = bright * (1 + 0.2 * pulse * fx.Heat)
			end
			local glow = fx.Glow
			if glow then
				glow.Color = fx.GlowColor:Lerp(Color3.new(1, 0.92, 0.7), 0.35 * pulse * fx.Heat)
			end
			for i, part in fx.Hot do
				part.Color = fx.HotColors[i]:Lerp(Color3.new(1, 0.92, 0.7), 0.3 * pulse * fx.Heat)
			end
			if base and #fx.Spinners > 0 then
				fx.Angle = (fx.Angle + fx.SpinRate * fx.Heat * dt) % (math.pi * 2)
				local origin = base.CFrame
				for _, spinner in fx.Spinners do
					local turn = spinner.Axis * CFrame.Angles(fx.Angle * spinner.Dir, 0, 0) * spinner.Axis:Inverse()
					table.insert(spinParts, spinner.Part)
					table.insert(spinFrames, origin * turn * spinner.Rest)
				end
			end
		end
		-- Sell Chute coin flash
		if fx.Flash > 0 then
			fx.Flash = math.max(0, fx.Flash - FLASH_DECAY * dt)
			local coins = fx.Coins
			if coins then
				coins.Color = fx.CoinsColor:Lerp(Color3.new(1, 1, 1), 0.6 * fx.Flash)
			end
			local light = fx.CoinsLight
			if light then
				light.Brightness = fx.CoinsIdle + 3 * fx.Flash
			end
		end
		-- water stream, splash and pool
		if fx.Water then
			stepWater(fx, dt)
		end
		-- anvil
		if fx.StubsDirty then
			refreshStubs(fx)
		end
		local forgeLight = fx.ForgeLight
		if forgeLight then
			forgeLight.Brightness = 1.6 + math.sin(clock * 7) * 0.6
		end
		-- your own machine's progress sign
		local refs = fx.Billboard
		if refs then
			local queue = number(fx, "Queue")
			local status = fx.Attr.Status
			local statusText = if type(status) == "string" then status else ""
			local progress = 0
			local workTime = number(fx, "WorkTime")
			if fx.Attr.Working == true and workTime > 0 then
				progress = (serverNow - number(fx, "WorkStart")) / workTime
			elseif statusText ~= "" and queue > 0 then
				-- finished, waiting for room to come out
				progress = 1
			end
			local ore = oreOf(fx.Attr.WorkOre)
			MachineBillboard.update(
				refs,
				progress,
				queue,
				number(fx, "QueueMax"),
				number(fx, "OutCount"),
				statusText,
				if ore then ore.Color else nil
			)
		end
	end
	if #spinParts > 0 then
		Workspace:BulkMoveTo(spinParts, spinFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------- lifecycle

function MachineFxController.init()
	FxController.register("Reject", function(position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		Vfx.burst("Dust", position, 6, REJECT_COLOR)
		Vfx.burst("Sparks", position, 4, REJECT_COLOR)
		Sfx.play("Reject", position)
	end)
end

function MachineFxController.start()
	CollectionService:GetInstanceAddedSignal("Machine"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("Machine"):Connect(unregister)
	for _, model in CollectionService:GetTagged("Machine") do
		register(model)
	end
	RunService.RenderStepped:Connect(step)
	while true do
		local ok, err = pcall(function()
			pickActive()
		end)
		if not ok then
			warn("[MachineFxController] " .. tostring(err))
		end
		task.wait(SELECT_INTERVAL)
	end
end

return MachineFxController
