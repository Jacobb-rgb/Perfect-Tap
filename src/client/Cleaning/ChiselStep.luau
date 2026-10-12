--[[
	Step 1: CHISEL. Trace each glowing guide line (from either end).
	The shared CutTracker scores the trace exactly like the server will.
	Completing a line cracks the crust: flash, shake, a tiny hit-stop, then
	the crust pieces break away with real (client) physics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Theme = require(Shared.Config.UITheme)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local Geometry2D = require(Shared.Cleaning.Geometry2D)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Geo = require(Shared.Builders.Geo)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local ChiselStep = {}
ChiselStep.__index = ChiselStep

local DOT_COLOR = Color3.fromRGB(255, 232, 150)
local DONE_DOT = Color3.fromRGB(120, 100, 70)
local OFF_COLOR = Color3.fromRGB(255, 90, 70)
local MIN_SAMPLE_DISTANCE = 0.015
local MIN_SAMPLE_TIME = 1 / 50

function ChiselStep.new(ctx: any)
	local self = setmetatable({
		ctx = ctx,
		cutIndex = 0,
		tracker = nil :: any,
		samples = {} :: { number },
		dots = {} :: { BasePart },
		ends = {} :: { BasePart },
		groove = {} :: { BasePart },
		cracking = false,
		done = false,
		lastSample = nil :: Vector2?,
		lastSampleT = -1,
		lastScratch = 0,
		lastWarning = 0,
		scores = {} :: { number },
		chips = 0,
		pulse = 0,
	}, ChiselStep)
	self:beginCut(1)
	return self
end

function ChiselStep.clearGuides(self: any)
	for _, part in self.dots do
		part:Destroy()
	end
	for _, part in self.ends do
		part:Destroy()
	end
	for _, part in self.groove do
		part:Destroy()
	end
	table.clear(self.dots)
	table.clear(self.ends)
	table.clear(self.groove)
end

function ChiselStep.beginCut(self: any, index: number)
	local ctx = self.ctx
	local cut = ctx.pattern.Cuts[index]
	self:clearGuides()
	if not cut then
		self.done = true
		return
	end
	self.cutIndex = index
	self.tracker = CleaningScoring.CutTracker.new(cut, ctx.tolerance, ctx.pattern.MaxCutSpeed)
	self.samples = {}
	self.lastSample = nil
	self.lastSampleT = -1
	self.dots = OreShellBuilder.guideDots(ctx.shell, cut, DOT_COLOR, ctx.folder)
	-- both ends glow bigger: you may start from either
	for _, p in { cut.Line[1], cut.Line[#cut.Line] } do
		local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.DotZ + 0.02)
		local marker = Geo.ball(ctx.folder, world, 0.2, DOT_COLOR, Enum.Material.Neon, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		table.insert(self.ends, marker)
	end
	local total = #ctx.pattern.Cuts
	local corner = if cut.Kind == "Gable" then " It has a corner!" else ""
	ctx.setInstruction(`Cut {index} of {total}: trace the glowing line.{corner}`)
	ctx.setProgress(`Cut {index} / {total}`)
	-- gamepad: start the cursor next to the first end
	local screen = ctx.screenAt(cut.Line[1].X, cut.Line[1].Y, OreShellBuilder.DotZ)
	if screen then
		ctx.pointer:warp(screen)
	end
end

function ChiselStep.liveScore(self: any): number
	local total, weight = 0, 0
	for i, cut in self.ctx.pattern.Cuts do
		local score = self.scores[i]
		if not score and i == self.cutIndex and self.tracker then
			score = self.tracker:score()
		end
		if score then
			total += score * cut.Length
			weight += cut.Length
		end
	end
	return if weight > 0 then total / weight else 1
end

local function chipEffect(ctx: any, p: Vector2)
	local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.CoreFront + 0.04)
	local ore = ctx.ore
	-- a small permanent notch on the core
	Geo.block(ctx.folder, ctx.shell.WorkCF.Rotation + world, Vector3.new(0.22, 0.18, 0.05), Color3.fromRGB(40, 32, 30), nil, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Name = "ChipMark",
	})
	-- the chip flying off
	local chip = Geo.wedge(ctx.folder, CFrame.new(world) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), Vector3.new(0.18, 0.14, 0.16), ore.Color, nil, {
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local toward = ctx.shell.WorkCF.LookVector * -1
	chip.AssemblyLinearVelocity = toward * 6 + Vector3.new(math.random() - 0.5, 1, math.random() - 0.5) * 6
	chip.AssemblyAngularVelocity = Vector3.new(10, 8, 6)
	task.delay(1, function()
		chip:Destroy()
	end)
	Vfx.burst("Sparks", world, 6, Color3.fromRGB(255, 120, 90))
	Sfx.play("Chip")
	CameraShake.add(0.12)
	ctx.feedback("CHIP!", Theme.Bad)
	ctx.flash(Color3.fromRGB(255, 80, 60), 0.85)
end

function ChiselStep.crack(self: any)
	local ctx = self.ctx
	local cutIndex = self.cutIndex
	local cut = ctx.pattern.Cuts[cutIndex]
	self.cracking = true
	ctx.submission.Cuts[cutIndex] = { Samples = self.samples }
	local score = self.tracker:score()
	self.scores[cutIndex] = score
	local isLast = cutIndex == #ctx.pattern.Cuts

	task.spawn(function()
		-- 1) the groove and seam light up
		for _, part in self.groove do
			part.Color = ctx.ore.Glow
			part.Size = Vector3.new(0.16, part.Size.Y, part.Size.Z)
		end
		for _, seam in ctx.shell.Seams[cutIndex] or {} do
			seam.Color = ctx.ore.Glow
			seam.Material = Enum.Material.Neon
		end
		-- 2) crack! sound, shake, flash
		Sfx.play("ChiselCrack", nil, 1 + cutIndex * 0.04)
		CameraShake.add(if isLast then 0.6 else 0.38)
		ctx.flash(Color3.new(1, 1, 1), if isLast then 0.55 else 0.75)
		-- 3) hit-stop: freeze for ~3 frames before anything moves
		task.wait(0.06)
		-- 4) the crust pieces break away
		local center = ctx.worldAt(0, 0, 0)
		for _, capModel in ctx.shell.Caps[cutIndex] or {} do
			local primary = capModel.PrimaryPart
			if primary then
				local centroid = Geometry2D.centroid(cut.Caps[1])
				local pieceCenter = primary.Position
				local outward = (pieceCenter - center)
				outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.new(0, 1, 0)
				for _, d in capModel:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = false
					end
				end
				local toward = ctx.shell.WorkCF.LookVector * -1
				primary.AssemblyLinearVelocity = outward * math.random(7, 11) + toward * 4 + Vector3.new(0, 6, 0)
				primary.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
				Vfx.burst("Dust", pieceCenter, 10, ctx.ore.Crust)
				Vfx.chips(pieceCenter, 4, ctx.ore.Crust, 0.7)
				local _ = centroid
				task.delay(1.2, function()
					for _, d in capModel:GetDescendants() do
						if d:IsA("BasePart") then
							TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
						end
					end
					task.wait(0.4)
					capModel:Destroy()
				end)
			end
		end
		for _, seam in ctx.shell.Seams[cutIndex] or {} do
			seam:Destroy()
		end
		-- glints where the core shows through
		Vfx.burst("Glint", center, 6 + cutIndex, ctx.ore.Glow)
		if score >= 0.92 then
			ctx.feedback("PERFECT CUT!", Color3.fromRGB(255, 225, 110))
		elseif score >= 0.78 then
			ctx.feedback("Great cut!", Color3.fromRGB(160, 255, 170))
		elseif score >= 0.55 then
			ctx.feedback("Good", Color3.fromRGB(120, 220, 255))
		else
			ctx.feedback("Rough cut", Color3.fromRGB(200, 170, 140))
		end
		self:clearGuides()
		if isLast then
			for _, rim in ctx.shell.CoreRim do
				TweenService:Create(rim, TweenInfo.new(0.5), { Transparency = 0 }):Play()
			end
			task.wait(0.5)
			ctx.feedback("The core is free!", ctx.ore.Glow)
		end
		task.wait(0.45)
		self.cracking = false
		self:beginCut(cutIndex + 1)
	end)
end

function ChiselStep.update(self: any, dt: number): boolean
	local ctx = self.ctx
	if self.done then
		return true
	end
	self.pulse += dt
	-- pulsing guide
	local glow = 0.5 + 0.5 * math.sin(self.pulse * 6)
	for _, marker in self.ends do
		marker.Size = Vector3.new(0.2, 0.2, 0.2) * (1 + glow * 0.35)
	end
	ctx.updateTool("Chisel", ctx.pointer.Down)
	if self.cracking or not self.tracker then
		return false
	end
	local pointer = ctx.pointer
	if pointer.Down then
		local p = ctx.faceAt(pointer.Position, OreShellBuilder.DotZ)
		local t = ctx.now()
		if p and #self.samples < (GameConfig.MaxTracePoints - 4) * 3 then
			local spacing = if #self.samples > GameConfig.MaxTracePoints * 2 then MIN_SAMPLE_DISTANCE * 3 else MIN_SAMPLE_DISTANCE
			local movedEnough = not self.lastSample or (p - self.lastSample).Magnitude >= spacing
			if movedEnough and t - self.lastSampleT >= MIN_SAMPLE_TIME then
				self.lastSample = p
				self.lastSampleT = t
				table.insert(self.samples, p.X)
				table.insert(self.samples, p.Y)
				table.insert(self.samples, t)
				local state = self.tracker:add(p, t)
				if state.Started then
					OreShellBuilder.updateGroove(ctx.shell, self.tracker.cut, state.Progress, self.tracker.direction, self.groove, ctx.folder, Color3.fromRGB(255, 170, 70))
					-- dots already cut fade out
					local cutLength = self.tracker.cut.Length
					local reached = state.Progress * cutLength
					for _, dot in self.dots do
						local s = dot:GetAttribute("S") :: number
						local along = if self.tracker.direction == 1 then s else cutLength - s
						if along <= reached then
							dot.Color = DONE_DOT
							dot.Transparency = 0.6
						else
							dot.Color = if state.OnLine then DOT_COLOR else OFF_COLOR
						end
					end
					if state.OnLine and t - self.lastScratch > 0.07 then
						self.lastScratch = t
						Sfx.play("ChiselScratch")
						local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.DotZ)
						Vfx.burst("Dust", world, 1, ctx.ore.Crust)
						if state.Quality > 0.9 then
							Vfx.burst("Sparks", world, 1)
						end
					end
					if not state.OnLine and t - self.lastWarning > 0.8 then
						self.lastWarning = t
						ctx.feedback("Back to the line!", Theme.Bad)
					elseif state.TooFast and t - self.lastWarning > 0.8 then
						self.lastWarning = t
						ctx.feedback("Slow down!", Color3.fromRGB(255, 200, 90))
					end
					if state.Chipped and state.ChipPoint then
						self.chips += 1
						ctx.addChip()
						chipEffect(ctx, state.ChipPoint)
					end
					ctx.setMeter(self:liveScore())
					if state.Complete then
						self:crack()
					end
				end
			end
		end
	end
	return false
end

function ChiselStep.destroy(self: any)
	self:clearGuides()
end

local _ = Workspace
return ChiselStep
