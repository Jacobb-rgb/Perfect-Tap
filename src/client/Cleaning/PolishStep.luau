--[[
	Step 3: POLISH. Rub in circles around the core (or rotate the left
	stick). The core goes from dull to gleaming; a speed gauge shows the
	sweet spot. "Hold to rub" mode (accessibility) works without circling,
	but can't reach the top polish score.
]]

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

local function wrap(a: number): number
	while a > math.pi do
		a -= math.pi * 2
	end
	while a < -math.pi do
		a += math.pi * 2
	end
	return a
end

-- Speed (rad/s) -> needle position matching the gauge's green zone (0.3..0.75).
local function needleFor(speed: number): number
	local band = CleaningScoring.PolishBand
	if speed < band.Min then
		return 0.3 * speed / band.Min
	elseif speed <= band.Max then
		return 0.3 + 0.45 * (speed - band.Min) / (band.Max - band.Min)
	end
	return 0.75 + 0.25 * math.min(1, (speed - band.Max) / 6)
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
		speed = 0,
		quarter = 0,
		rubMode = false,
		rubAngle = 0,
		done = false,
		finishing = false,
		ring = {} :: { BasePart },
		dull = nil :: Color3?,
		sparkle = nil :: ParticleEmitter?,
		pulse = 0,
		connection = nil :: RBXScriptConnection?,
	}, PolishStep)
	local needed = ctx.pattern.PolishTurns * math.pi * 2
	self.needed = needed
	ctx.submission.Polish = { Samples = self.samples, Mode = "Circle" }
	ctx.setInstruction("Rub in circles around the ore to polish it!")
	ctx.setProgress("Shine: 0%")
	ctx.view.Gauge.Visible = true
	ctx.view.Shine.Visible = true
	ctx.view.RubToggle.Parent.Visible = true
	self.connection = ctx.view.RubToggle.Activated:Connect(function()
		self.rubMode = not self.rubMode
		ctx.view.RubToggle.Text = if self.rubMode then "Hold to rub: ON" else "Hold to rub: OFF"
		Sfx.play("UIClick")
	end)
	-- a dotted ring around the core shows where to rub
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
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
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
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

function PolishStep.liveScore(self: any): number
	if self.total <= 0 then
		return 1
	end
	local score = 0.7 * (self.inBand / self.total) + 0.3 * (math.abs(self.net) / self.total)
	if self.rubMode then
		score = math.min(score, 0.75)
	end
	return score
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

function PolishStep.addSample(self: any, angle: number, t: number)
	local ctx = self.ctx
	if #self.samples >= (GameConfig.MaxPolishSamples - 2) * 2 then
		return
	end
	if self.lastAngle then
		local delta = wrap(angle - self.lastAngle)
		if math.abs(delta) < 0.04 and t - self.lastT < 0.06 then
			return
		end
		if math.abs(delta) <= math.pi * 0.75 then
			local dt = math.max(t - self.lastT, 1 / 240)
			local speed = math.abs(delta) / dt
			self.speed = self.speed * 0.7 + speed * 0.3
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
	ctx.submission.Polish.Mode = if self.rubMode then "Rub" else ctx.submission.Polish.Mode
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

function PolishStep.update(self: any, dt: number): boolean
	local ctx = self.ctx
	if self.done then
		return true
	end
	self.pulse += dt
	-- a bright dot runs around the ring to show the motion
	local lead = math.floor((self.pulse * 6) % #self.ring) + 1
	for i, dot in self.ring do
		dot.Transparency = if i == lead then 0 else 0.55
	end
	local pointer = ctx.pointer
	ctx.updateTool("Cloth", pointer.Down)
	ctx.view.GaugeNeedle.Position = UDim2.fromScale(needleFor(self.speed), 0.5)
	self.speed *= 0.92
	if self.finishing then
		return false
	end
	local t = ctx.now()
	if self.rubMode then
		if pointer.Down or pointer.Stick.Magnitude > 0.5 then
			self.rubAngle = wrap(self.rubAngle + 3.2 * dt)
			ctx.submission.Polish.Mode = "Rub"
			self:addSample(self.rubAngle, t)
		end
	elseif pointer.Kind == "Gamepad" and pointer.Stick.Magnitude > 0.5 then
		self:addSample(math.atan2(pointer.Stick.Y, pointer.Stick.X), t)
	elseif pointer.Down then
		local center = ctx.screenAt(0, 0, OreShellBuilder.CoreFront)
		if center then
			local offset = pointer.Position - center
			if offset.Magnitude > 12 then
				-- screen y grows downwards: flip so counter-clockwise is positive
				self:addSample(math.atan2(-offset.Y, offset.X), t)
			end
		end
	end
	if self.total >= self.needed * 1.03 then
		self.finishing = true
		self:applyShine(1)
		ctx.feedback("Gleaming!", Color3.fromRGB(255, 240, 170))
		task.delay(0.4, function()
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
	ctx.view.Gauge.Visible = false
	ctx.view.Shine.Visible = false
	ctx.view.RubToggle.Parent.Visible = false
end

local _ = CleaningScoring
return PolishStep
