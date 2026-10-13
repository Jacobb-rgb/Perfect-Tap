--[[
	Step 2: SCRAPE. Drag the brush over the core: dirt patches pop off with
	dust. Avoid the glinting fragile crystals (scraping one snaps it).
	The shared ScrapeTracker decides what the brush hits; only brush
	positions that changed something are recorded, and the server replays
	them to get the same result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local ScrapeStep = {}
ScrapeStep.__index = ScrapeStep

local MAX_REACH = 2.5 -- face units; the pointer is nowhere near the ore beyond this

function ScrapeStep.new(ctx: any)
	local self = setmetatable({
		ctx = ctx,
		tracker = CleaningScoring.ScrapeTracker.new(ctx.pattern),
		samples = {} :: { number },
		total = ctx.pattern.DirtCount,
		lastPop = 0,
		done = false,
		finishing = false,
	}, ScrapeStep)
	ctx.submission.Scrape = { Samples = self.samples }
	ctx.setInstruction("Brush away the dirt. Careful: don't scrape the glinting crystals!")
	ctx.setProgress(`Dirt: 0 / {self.total}`)
	-- the crystals sparkle so players can spot them
	for _, shard in ctx.shell.Fragile do
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1))
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.4, 0.7)
		sparkle.Speed = NumberRange.new(0.1, 0.3)
		sparkle.Rate = 4
		sparkle.LightEmission = 1
		sparkle.LightInfluence = 0
		sparkle.Parent = shard
	end
	return self
end

-- Same formula as the server; while scraping, "now" stands in for the last removal.
function ScrapeStep.liveScore(self: any): number
	local tracker = self.tracker
	local duration = 0
	if tracker.firstT then
		local last = if self.finishing then tracker.lastT else self.ctx.now()
		duration = last - tracker.firstT
	end
	return CleaningScoring.scrapeScore(self.total, tracker.hits, duration)
end

local function popPatch(ctx: any, patch: BasePart)
	local position = patch.Position
	local tween = TweenService:Create(patch, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = Vector3.new(0.02, 0.02, 0.02),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		patch:Destroy()
	end)
	if ctx.now() - ctx.lastFineDust > 0.08 then
		ctx.lastFineDust = ctx.now()
		Vfx.burst("FineDust", position, 3, patch.Color)
	end
end

function ScrapeStep.finish(self: any)
	if self.finishing then
		return
	end
	self.finishing = true
	local ctx = self.ctx
	Sfx.loop("Scrape", false)
	-- the dirt around the crystals goes too
	for _, d in ctx.shell.Model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "FragileDirt" then
			popPatch(ctx, d)
		end
	end
	Vfx.burst("Glint", ctx.worldAt(0, 0, OreShellBuilder.CoreFront + 0.1), 14, ctx.ore.Glow)
	if self.tracker.hits == 0 then
		ctx.feedback("Spotless!", Color3.fromRGB(160, 255, 170))
	else
		ctx.feedback("Clean... mostly", Color3.fromRGB(200, 200, 160))
	end
	task.delay(0.7, function()
		self.done = true
	end)
end

function ScrapeStep.update(self: any, _dt: number): boolean
	local ctx = self.ctx
	if self.done then
		return true
	end
	local pointer = ctx.pointer
	ctx.updateTool("Brush", pointer.Down)
	if self.finishing then
		return false
	end
	local scraping = false
	if pointer.Down then
		local p = ctx.faceAt(pointer.Position, OreShellBuilder.DirtFront)
		if p and math.abs(p.X) <= MAX_REACH and math.abs(p.Y) <= MAX_REACH then
			local t = ctx.now()
			local removedNow, snappedNow = self.tracker:add(p, t)
			if #removedNow > 0 or #snappedNow > 0 then
				-- only brush positions that changed something are sent
				table.insert(self.samples, p.X)
				table.insert(self.samples, p.Y)
				table.insert(self.samples, t)
			end
			for _, index in snappedNow do
				local shard = ctx.shell.Fragile[index]
				if shard then
					Vfx.burst("Glint", shard.Position, 10, ctx.ore.Glow)
					Vfx.chips(shard.Position, 3, ctx.ore.Glow, 0.5)
					shard:Destroy()
				end
				Sfx.play("Chip")
				CameraShake.add(0.15)
				ctx.feedback("Crystal snapped!", Theme.Bad)
				ctx.flash(Color3.fromRGB(255, 80, 60), 0.85)
			end
			for _, index in removedNow do
				scraping = true
				local patch = ctx.shell.Dirt[index]
				if patch then
					popPatch(ctx, patch)
				end
			end
			if scraping and t - self.lastPop > 0.06 then
				self.lastPop = t
				Sfx.play("DirtPop")
			end
			ctx.setProgress(`Dirt: {self.tracker.removed} / {self.total}`)
		end
	end
	ctx.setMeter(ctx.combinedScore())
	Sfx.loop("Scrape", pointer.Down and (pointer.Moved or scraping))
	if self.tracker:complete() then
		self:finish()
	end
	return false
end

function ScrapeStep.destroy(_self: any)
	Sfx.loop("Scrape", false)
end

return ScrapeStep
