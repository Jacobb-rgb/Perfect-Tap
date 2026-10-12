--[[
	Step 2: SCRAPE. Drag the brush over the core: dirt patches pop off with
	dust. Avoid the glinting fragile crystals (scraping one snaps it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local ScrapeStep = {}
ScrapeStep.__index = ScrapeStep

local BRUSH_RADIUS = 0.17 -- face units

function ScrapeStep.new(ctx: any)
	local self = setmetatable({
		ctx = ctx,
		removed = 0,
		total = ctx.pattern.DirtCount,
		cleared = {} :: { [number]: boolean },
		hit = {} :: { [number]: boolean },
		hits = 0,
		lastPop = 0,
		done = false,
		finishing = false,
	}, ScrapeStep)
	ctx.submission.Scrape = { Removed = {}, Fragile = {} }
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

function ScrapeStep.liveScore(self: any): number
	return math.clamp(1 - 0.15 * self.hits, 0, 1)
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
	Vfx.burst("Dust", position, 2, patch.Color)
	local _ = ctx
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
	if self.hits == 0 then
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
		if p then
			local t = ctx.now()
			for _, d in ctx.pattern.Dirt do
				local distance = (d.Center - p).Magnitude
				if d.Fragile then
					if not self.hit[d.Index] and distance <= BRUSH_RADIUS * 0.7 then
						self.hit[d.Index] = true
						self.hits += 1
						table.insert(ctx.submission.Scrape.Fragile, d.Index)
						table.insert(ctx.submission.Scrape.Fragile, t)
						local shard = ctx.shell.Fragile[d.Index]
						if shard then
							Vfx.burst("Glint", shard.Position, 10, ctx.ore.Glow)
							Vfx.chips(shard.Position, 3, ctx.ore.Glow, 0.5)
							shard:Destroy()
						end
						Sfx.play("Chip")
						CameraShake.add(0.15)
						ctx.addChip()
						ctx.feedback("Crystal snapped!", Theme.Bad)
						ctx.flash(Color3.fromRGB(255, 80, 60), 0.85)
					end
				elseif not self.cleared[d.Index] and distance <= BRUSH_RADIUS + d.Size * 0.5 then
					self.cleared[d.Index] = true
					self.removed += 1
					scraping = true
					table.insert(ctx.submission.Scrape.Removed, d.Index)
					table.insert(ctx.submission.Scrape.Removed, t)
					local patch = ctx.shell.Dirt[d.Index]
					if patch then
						popPatch(ctx, patch)
					end
					if t - self.lastPop > 0.06 then
						self.lastPop = t
						Sfx.play("DirtPop")
					end
				end
			end
			ctx.setProgress(`Dirt: {self.removed} / {self.total}`)
			ctx.setMeter(ctx.combinedScore())
		end
	end
	Sfx.loop("Scrape", pointer.Down and (pointer.Moved or scraping))
	if self.removed >= self.total then
		self:finish()
	end
	return false
end

function ScrapeStep.destroy(_self: any)
	Sfx.loop("Scrape", false)
end

return ScrapeStep
