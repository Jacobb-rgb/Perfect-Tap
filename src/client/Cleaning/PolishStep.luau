--[[
	Step 3: POLISH. Rub in circles around the core (or rotate the left
	stick). The core goes from dull to gleaming. The SPEED gauge shows the
	real circling speed (CleaningScoring.PolishGauge) and is green exactly
	where the server counts it as good polishing; "Slower!" / "Faster!" pop up
	when you stay outside it. A bright dot runs round the ring at a good speed.
	"Easy polish" (accessibility toggle, R / gamepad Y) works without
	circling, but caps the polish score at RubCap (75%) once it was used;
	the first time it counts, a message says so.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Geo = require(Shared.Builders.Geo)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)

local PolishStep = {}
PolishStep.__index = PolishStep

local RUB_ACTION = "TerraForgeRubToggle"
local STILL_ANGLE = 0.04 -- radians; smaller moves are "holding still"
local STILL_SAMPLE_TIME = 0.5 -- while holding still, record at most this often
local RING_DOTS = 24
local SLOW_DOWN_AFTER = 0.3 -- seconds above the band before "Slower!"
local SPEED_UP_AFTER = 0.5 -- seconds below the band (while rubbing) before "Faster!"
local SPEED_HINT_COOLDOWN = 1.2
local HINT_COLOR = Color3.fromRGB(255, 200, 90)

local function wrap(a: number): number
	while a > math.pi do
		a -= math.pi * 2
	end
	while a < -math.pi do
		a += math.pi * 2
	end
	return a
end

function PolishStep.new(ctx: any)
	local self = setmetatable({
		ctx = ctx,
		samples = {} :: { number },
		lastAngle = nil :: number?,
		lastT = -1,
		total = 0,
		inBand = 0,
		net = 0,
		gauge = CleaningScoring.PolishGauge.new(),
		fastSince = nil :: number?,
		slowSince = nil :: number?,
		lastSpeedHint = -math.huge,
		quarter = 0,
		rubMode = false,
		rubAngle = 0,
		rubNoticed = false,
		done = false,
		finishing = false,
		ring = {} :: { BasePart },
		dull = nil :: Color3?,
		sparkle = nil :: ParticleEmitter?,
		demoAngle = 0,
		connection = nil :: RBXScriptConnection?,
		label = nil :: any, -- refreshes the Easy polish button text
		labelKind = ctx.pointer.Kind :: string,
	}, PolishStep)
	local needed = ctx.pattern.PolishTurns * math.pi * 2
	self.needed = needed
	ctx.submission.Polish = { Samples = self.samples, Mode = "Circle" }
	ctx.setInstruction("Rub in circles around the ore. Keep the SPEED needle in the green!")
	ctx.setProgress("Shine: 0%")
	ctx.view.Gauge.Visible = true
	ctx.view.Shine.Visible = true
	ctx.view.RubToggle.Parent.Visible = true
	local function label()
		local key = if ctx.pointer.Kind == "Gamepad" then "Y" elseif ctx.pointer.Kind == "Touch" then nil else "R"
		local state = if self.rubMode then "ON" else "OFF"
		ctx.view.RubToggle.Text = if key then `Easy polish ({key}): {state}` else `Easy polish: {state}`
	end
	self.label = label
	local function toggle()
		self.rubMode = not self.rubMode
		label()
		Sfx.play("UIClick")
	end
	label()
	self.connection = ctx.view.RubToggle.Activated:Connect(toggle)
	ContextActionService:BindAction(RUB_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	-- a dotted ring around the core shows where to rub
	for i = 1, RING_DOTS do
		local a = i / RING_DOTS * math.pi * 2
		local world = ctx.worldAt(math.cos(a) * 0.62, math.sin(a) * 0.62, OreShellBuilder.CoreFront + 0.06)
		local dot = Geo.ball(ctx.folder, world, 0.07, Color3.fromRGB(255, 240, 200), Enum.Material.Neon, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 0.4,
		})
		table.insert(self.ring, dot)
	end
	self.dull = ctx.shell.Core[1] and ctx.shell.Core[1].Color
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(ctx.ore.Glow:Lerp(Color3.new(1, 1, 1), 0.5))
	sparkle.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(0.4, 0.8)
	sparkle.Speed = NumberRange.new(0.2, 0.8)
	sparkle.SpreadAngle = Vector2.new(60, 60)
	sparkle.Rate = 0
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	if ctx.shell.Core[1] then
		sparkle.Parent = ctx.shell.Core[1]
	end
	self.sparkle = sparkle
	return self
end

-- Same formula as the server (easy polish caps the whole polish once it was used).
function PolishStep.liveScore(self: any): number
	if self.total <= 0 then
		return 1
	end
	return CleaningScoring.polishScore(self.total, self.inBand, self.net, self.ctx.submission.Polish.Mode)
end

function PolishStep.applyShine(self: any, progress: number)
	local ctx = self.ctx
	local shine = math.clamp(progress, 0, 1)
	local bright = ctx.ore.Color:Lerp(Color3.new(1, 1, 1), 0.08)
	for _, part in ctx.shell.Core do
		part.Color = (self.dull or part.Color):Lerp(bright, shine)
		part.Reflectance = 0.35 * shine
	end
	if self.sparkle then
		self.sparkle.Rate = shine * 10
	end
	ctx.view.ShineFill.Size = UDim2.fromScale(shine, 1)
	ctx.setProgress(string.format("Shine: %d%%", math.floor(shine * 100)))
end

-- Easy polish counts from the first sample recorded with it on (the server caps the score).
function PolishStep.markRub(self: any)
	local ctx = self.ctx
	ctx.submission.Polish.Mode = "Rub"
	if not self.rubNoticed then
		self.rubNoticed = true
		ctx.feedback(`Easy polish: max {math.floor(CleaningScoring.RubCap * 100)}% shine`, HINT_COLOR)
	end
end

function PolishStep.addSample(self: any, angle: number, t: number)
	local ctx = self.ctx
	if #self.samples >= (GameConfig.MaxPolishSamples - 2) * 2 then
		-- out of room (only possible after a very long, messy polish): start the shine over
		table.clear(self.samples)
		self.lastAngle = nil
		self.total, self.inBand, self.net, self.quarter = 0, 0, 0, 0
		ctx.feedback("Keep polishing!", HINT_COLOR)
		return
	end
	if self.lastAngle then
		local delta = wrap(angle - self.lastAngle)
		if math.abs(delta) < STILL_ANGLE and t - self.lastT < STILL_SAMPLE_TIME then
			return
		end
		if math.abs(delta) <= math.pi * 0.75 then
			local dt = math.max(t - self.lastT, 1 / 240)
			local speed = math.abs(delta) / dt
			self.gauge:add(self.lastT, t, math.abs(delta))
			self.total += math.abs(delta)
			self.net += delta
			local band = CleaningScoring.PolishBand
			if speed >= band.Min and speed <= band.Max then
				self.inBand += math.abs(delta)
			end
		end
	end
	self.lastAngle = angle
	self.lastT = t
	table.insert(self.samples, t)
	table.insert(self.samples, angle)
	if self.rubMode then
		self:markRub()
	end
	-- feedback
	local progress = self.total / self.needed
	local quarter = math.floor(progress * 4 * self.ctx.pattern.PolishTurns)
	if quarter > self.quarter then
		self.quarter = quarter
		Sfx.play("Polish", nil, 1 + math.min(progress, 1) * 0.6)
		local a = angle
		Vfx.burst("Glint", ctx.worldAt(math.cos(a) * 0.5, math.sin(a) * 0.5, OreShellBuilder.CoreFront + 0.1), 3, ctx.ore.Glow)
	end
	self:applyShine(progress)
	ctx.setMeter(ctx.combinedScore())
end

-- "Slower!" / "Faster!" when the real speed stays outside the band (circling only).
function PolishStep.speedHints(self: any, speed: number, t: number, rubbing: boolean)
	local band = CleaningScoring.PolishBand
	if not rubbing or self.rubMode then
		self.fastSince, self.slowSince = nil, nil
		return
	end
	if speed > band.Max then
		self.fastSince = self.fastSince or t
		self.slowSince = nil
	elseif speed < band.Min then
		self.slowSince = self.slowSince or t
		self.fastSince = nil
	else
		self.fastSince, self.slowSince = nil, nil
	end
	if t - self.lastSpeedHint < SPEED_HINT_COOLDOWN then
		return
	end
	if self.fastSince and t - self.fastSince >= SLOW_DOWN_AFTER then
		self.lastSpeedHint = t
		self.ctx.feedback("Slower!", HINT_COLOR)
	elseif self.slowSince and t - self.slowSince >= SPEED_UP_AFTER then
		self.lastSpeedHint = t
		self.ctx.feedback("Faster!", HINT_COLOR)
	end
end

function PolishStep.update(self: any, dt: number): boolean
	local ctx = self.ctx
	if self.done then
		return true
	end
	-- a bright dot runs round the ring at a good polishing speed
	self.demoAngle = (self.demoAngle + CleaningScoring.PolishBand.Demo * dt) % (math.pi * 2)
	local lead = math.floor(self.demoAngle / (math.pi * 2) * RING_DOTS) % RING_DOTS + 1
	for i, dot in self.ring do
		dot.Transparency = if i == lead then 0 else 0.55
	end
	local pointer = ctx.pointer
	if pointer.Kind ~= self.labelKind then
		-- the key hint on the Easy polish button follows the device in use
		self.labelKind = pointer.Kind
		self.label()
	end
	ctx.updateTool("Cloth", pointer.Down)
	local t = ctx.now()
	local speed = self.gauge:speed(t)
	ctx.view.GaugeNeedle.Position = UDim2.fromScale(CleaningScoring.needleFor(speed), 0.5)
	if self.finishing then
		return false
	end
	local rubbing = false
	if self.rubMode then
		if pointer.Down or pointer.Stick.Magnitude > 0.5 then
			self.rubAngle = wrap(self.rubAngle + 3.2 * dt)
			self:markRub()
			self:addSample(self.rubAngle, t)
		end
	elseif pointer.Kind == "Gamepad" and pointer.Stick.Magnitude > 0.5 then
		rubbing = true
		self:addSample(math.atan2(pointer.Stick.Y, pointer.Stick.X), t)
	elseif pointer.Down then
		local center = ctx.screenAt(0, 0, OreShellBuilder.CoreFront)
		if center then
			local offset = pointer.Position - center
			if offset.Magnitude > 12 then
				rubbing = true
				-- screen y grows downwards: flip so counter-clockwise is positive
				self:addSample(math.atan2(-offset.Y, offset.X), t)
			end
		end
	end
	self:speedHints(speed, t, rubbing)
	if self.total >= self.needed * 1.03 then
		self.finishing = true
		self:applyShine(1)
		ctx.feedback("Gleaming!", Color3.fromRGB(255, 240, 170))
		-- a ClientPauses value: the server's timeline check expects this pause
		task.delay(CleaningScoring.ClientPauses.PolishFinish, function()
			self.done = true
		end)
	end
	return false
end

function PolishStep.destroy(self: any)
	local ctx = self.ctx
	for _, dot in self.ring do
		dot:Destroy()
	end
	if self.connection then
		self.connection:Disconnect()
	end
	ContextActionService:UnbindAction(RUB_ACTION)
	ctx.view.Gauge.Visible = false
	ctx.view.Shine.Visible = false
	ctx.view.RubToggle.Parent.Visible = false
end

return PolishStep
