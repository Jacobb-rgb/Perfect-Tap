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
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local SoundConfig = require(Shared.Config.SoundConfig)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local MachineBillboard = require(script.Parent.Parent.UI.MachineBillboard)
local FxController = require(script.Parent.FxController)

local MachineFxController = {}

-- Rest pose of a spinning part, both relative to the machine's Base.
type Spinner = { Part: BasePart, Rest: CFrame, Axis: CFrame, Dir: number }
type Emitter = { Emitter: ParticleEmitter, Idle: number, Busy: number }

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

local player = Players.LocalPlayer
local machines: { [Model]: Fx } = {}
local active: { Fx } = {}
local hums: { Hum } = {}
local fxFolder: Folder? = nil
local clock = 0

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
	elseif id == "AutoCleaner" then
		local vent = model:FindFirstChild("Vent")
		local smoke = vent and vent:FindFirstChild("Smoke")
		if smoke and smoke:IsA("ParticleEmitter") then
			emitterOn(fx, vent, "Smoke", smoke.Rate * VENT_FACTOR)
		end
		if base then
			addSpinners(fx, base, "Drum", { "Drum", "DrumRib" }, 1)
		end
	elseif id == "Crusher" then
		if base then
			-- the two rollers turn toward each other
			addSpinners(fx, base, "Roller1", { "Roller1", "Roller1Tooth" }, 1)
			addSpinners(fx, base, "Roller2", { "Roller2", "Roller2Tooth" }, -1)
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
		return
	end
	-- back to the idle look
	fx.Heat = 0
	applyHeat(fx)
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
