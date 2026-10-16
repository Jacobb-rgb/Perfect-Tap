--[[
	Step 1: CHISEL. Trace each glowing guide line (from either end).
	The shared CutRecorder applies the recording rules and the shared
	CutTracker scores the trace exactly like the server will (the server
	replays the recorded samples).
	Lifting the pointer keeps the groove: the end it started from goes dark
	and a "continue here" ball pulses at the groove tip. After an early lift,
	pressing anywhere but the tip starts the line over, so a touch at the
	wrong end is forgotten. Scratch sound, dust and sparks only play while
	the groove really moves (or you are at its tip).
	Completing a line cracks the crust: flash, shake, a tiny hit-stop, then
	the crust pieces break away with real (client) physics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local CutRecorder = require(Shared.Cleaning.CutRecorder)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Geo = require(Shared.Builders.Geo)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local ChiselStep = {}
ChiselStep.__index = ChiselStep

local DOT_COLOR = Color3.fromRGB(255, 232, 150)
local DONE_DOT = Color3.fromRGB(120, 100, 70)
local OFF_COLOR = Color3.fromRGB(255, 90, 70)
local TIP_COLOR = Color3.fromRGB(255, 255, 255)
local GROOVE_COLOR = Color3.fromRGB(255, 170, 70)
local END_SIZE = 0.2
local TIP_SIZE = 0.15
local WARNING_COOLDOWN = 0.8 -- seconds between two warnings
local START_HINT_DELAY = 0.35 -- pressing this long without starting the cut shows "Start at a glowing end!"

local MARKER_PROPS = {
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}

function ChiselStep.new(ctx: any)
	local self = setmetatable({
		ctx = ctx,
		cutIndex = 0,
		recorder = nil :: any,
		dots = {} :: { BasePart },
		ends = {} :: { BasePart }, -- [1] at Line[1], [2] at the other end
		tipMarker = nil :: BasePart?,
		atTip = false, -- the last sample was cutting at the groove tip
		groove = {} :: { BasePart },
		cracking = false,
		done = false,
		lastScratch = 0,
		lastWarning = -math.huge,
		scores = {} :: { number },
		attemptChips = 0, -- chips of the current attempt (dropped if the attempt restarts)
		chipMarks = {} :: { BasePart },
		wasDown = false,
		downSince = 0,
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
	if self.tipMarker then
		self.tipMarker:Destroy()
		self.tipMarker = nil
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
	self.recorder = CutRecorder.new(cut, ctx.tolerance, ctx.pattern.MaxCutSpeed)
	self:clearAttempt()
	self.dots = OreShellBuilder.guideDots(ctx.shell, cut, DOT_COLOR, ctx.folder)
	-- both ends glow bigger: you may start from either
	for _, p in { cut.Line[1], cut.Line[#cut.Line] } do
		local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.DotZ + 0.02)
		table.insert(self.ends, Geo.ball(ctx.folder, world, END_SIZE, DOT_COLOR, Enum.Material.Neon, MARKER_PROPS))
	end
	-- "continue here": pulses at the groove tip once the cut started
	local tip = Geo.ball(ctx.folder, ctx.worldAt(0, 0, OreShellBuilder.DotZ + 0.03), TIP_SIZE, TIP_COLOR, Enum.Material.Neon, MARKER_PROPS)
	tip.Name = "GrooveTip"
	tip.Transparency = 1
	self.tipMarker = tip
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

-- Visuals of a dropped attempt: groove, faded dots, its chips and their notches.
function ChiselStep.clearAttempt(self: any)
	local ctx = self.ctx
	for _, part in self.groove do
		part:Destroy()
	end
	table.clear(self.groove)
	for _, dot in self.dots do
		dot.Color = DOT_COLOR
		dot.Transparency = 0
	end
	-- chips of an abandoned attempt don't count (the server never sees them)
	if self.attemptChips > 0 then
		ctx.removeChips(self.attemptChips)
		self.attemptChips = 0
	end
	for _, mark in self.chipMarks do
		mark:Destroy()
	end
	table.clear(self.chipMarks)
	self.atTip = false
end

function ChiselStep.liveScore(self: any): number
	local total, weight = 0, 0
	for i, cut in self.ctx.pattern.Cuts do
		local score = self.scores[i]
		if not score and i == self.cutIndex and self.recorder then
			score = self.recorder.tracker:score()
		end
		if score then
			total += score * cut.Length
			weight += cut.Length
		end
	end
	return if weight > 0 then total / weight else 1
end

-- End markers pulse until the cut starts; then the start end goes dark and the tip pulses.
function ChiselStep.updateMarkers(self: any)
	local ctx = self.ctx
	local glow = 0.5 + 0.5 * math.sin(self.pulse * 6)
	local recorder = self.recorder
	local startEnd = recorder and recorder:startEnd()
	for i, marker in self.ends do
		if startEnd == nil then
			marker.Transparency = 0
			marker.Size = Vector3.one * END_SIZE * (1 + glow * 0.35)
		elseif i == startEnd then
			marker.Transparency = 1
		else
			-- the far end stays as the goal, without inviting a restart
			marker.Transparency = 0
			marker.Size = Vector3.one * END_SIZE
		end
	end
	local tipMarker = self.tipMarker
	if tipMarker then
		-- while cutting right at the tip the tool is there: the glow would only hide the dots ahead
		local tip = recorder and not (ctx.pointer.Down and self.atTip) and recorder:tip()
		if tip then
			tipMarker.Transparency = 0
			tipMarker.Position = ctx.worldAt(tip.X, tip.Y, OreShellBuilder.DotZ + 0.03)
			tipMarker.Size = Vector3.one * TIP_SIZE * (1 + glow * 0.6)
		else
			tipMarker.Transparency = 1
		end
	end
end

local function chipEffect(ctx: any, p: Vector2): BasePart
	local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.CoreFront + 0.04)
	local ore = ctx.ore
	-- a small permanent notch on the core
	local mark = Geo.block(ctx.folder, ctx.shell.WorkCF.Rotation + world, Vector3.new(0.22, 0.18, 0.05), Color3.fromRGB(40, 32, 30), nil, {
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
	return mark
end

function ChiselStep.crack(self: any)
	local ctx = self.ctx
	local cutIndex = self.cutIndex
	local pauses = CleaningScoring.ClientPauses
	self.cracking = true
	if self.tipMarker then
		self.tipMarker.Transparency = 1
	end
	-- this attempt's chips (and their notches) are final now
	self.attemptChips = 0
	table.clear(self.chipMarks)
	ctx.submission.Cuts[cutIndex] = { Samples = self.recorder.samples }
	local score = self.recorder.tracker:score()
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
		-- (every pause here is a ClientPauses value: the server's timeline check expects them)
		task.wait(pauses.HitStop)
		-- 4) the crust pieces break away
		local center = ctx.worldAt(0, 0, 0)
		for _, capModel in ctx.shell.Caps[cutIndex] or {} do
			local primary = capModel.PrimaryPart
			if primary then
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
				Vfx.burst("FineDust", pieceCenter, 4, ItemBuilder.DirtyCrust)
				Vfx.chips(pieceCenter, 4, ItemBuilder.DirtyCrust, 0.7)
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
				TweenService:Create(rim, TweenInfo.new(pauses.LastCrack), { Transparency = 0 }):Play()
			end
			task.wait(pauses.LastCrack)
			ctx.feedback("The core is free!", ctx.ore.Glow)
		end
		task.wait(pauses.Crack)
		self.cracking = false
		self:beginCut(cutIndex + 1)
	end)
end

function ChiselStep.notify(self: any, t: number, text: string, color: Color3)
	if t - self.lastWarning > WARNING_COOLDOWN then
		self.lastWarning = t
		self.ctx.feedback(text, color)
	end
end

function ChiselStep.update(self: any, dt: number): boolean
	local ctx = self.ctx
	if self.done then
		return true
	end
	self.pulse += dt
	ctx.updateTool("Chisel", ctx.pointer.Down)
	if self.cracking or not self.recorder then
		return false
	end
	self:updateMarkers()
	local pointer = ctx.pointer
	local recorder = self.recorder
	if not pointer.Down then
		if self.wasDown then
			-- the groove stays; an early lift lets the next press decide (see CutRecorder)
			recorder:release()
		end
		self.wasDown = false
		self.atTip = false
		return false
	end
	local t = ctx.now()
	if not self.wasDown then
		self.wasDown = true
		self.downSince = t
	end
	local p = ctx.faceAt(pointer.Position, OreShellBuilder.DotZ)
	if not p then
		return false
	end
	local feed = recorder:feed(p, t)
	if feed.Restarted or feed.Overflow then
		self:clearAttempt()
	end
	if feed.Overflow then
		-- very long wobbly attempt: start the line over rather than get stuck
		ctx.feedback("Try that line again!", Color3.fromRGB(255, 200, 90))
		return false
	end
	local state = feed.State
	if not state then
		return false
	end
	if not state.Started then
		if t - self.downSince > START_HINT_DELAY then
			self:notify(t, "Start at a glowing end!", Color3.fromRGB(255, 200, 90))
		end
		return false
	end
	local tracker = recorder.tracker
	local cutLength = tracker.cut.Length
	OreShellBuilder.updateGroove(ctx.shell, tracker.cut, state.Progress, tracker.direction, self.groove, ctx.folder, GROOVE_COLOR)
	-- dots already cut fade out
	local reached = state.Progress * cutLength
	for _, dot in self.dots do
		local s = dot:GetAttribute("S") :: number
		local along = if tracker.direction == 1 then s else cutLength - s
		if along <= reached then
			dot.Color = DONE_DOT
			dot.Transparency = 0.6
		else
			dot.Color = if state.OnLine then DOT_COLOR else OFF_COLOR
		end
	end
	-- only a groove that really moves (or the tip under the pointer) sounds like cutting
	local cutting = state.OnLine and (feed.Gained or recorder:nearTip(p))
	self.atTip = cutting
	if cutting and t - self.lastScratch > 0.07 then
		self.lastScratch = t
		Sfx.play("ChiselScratch")
		local world = ctx.worldAt(p.X, p.Y, OreShellBuilder.DotZ)
		if t - ctx.lastFineDust > 0.2 then
			ctx.lastFineDust = t
			Vfx.burst("FineDust", world, 1, ItemBuilder.DirtyCrust)
		end
		if state.Quality > 0.9 then
			Vfx.burst("Sparks", world, 1)
		end
	end
	if not state.OnLine then
		self:notify(t, "Back to the line!", Theme.Bad)
	elseif not cutting then
		self:notify(t, "Continue from the glowing tip!", Color3.fromRGB(255, 200, 90))
	elseif state.TooFast then
		self:notify(t, "Slow down!", Color3.fromRGB(255, 200, 90))
	end
	if state.Chipped and state.ChipPoint then
		self.attemptChips += 1
		table.insert(self.chipMarks, chipEffect(ctx, state.ChipPoint))
		ctx.addChip()
	end
	ctx.setMeter(ctx.combinedScore())
	if state.Complete then
		self:crack()
	end
	return false
end

function ChiselStep.destroy(self: any)
	self:clearGuides()
end

return ChiselStep
