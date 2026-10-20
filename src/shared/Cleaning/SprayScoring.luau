--[[
	Scores spray-washing. The client feeds its recorded samples to a
	SprayTracker for live feedback; the server replays the same samples with
	the same tracker (CleaningService) to decide the real grade. Same code on
	both sides = same result.

	Submission (client -> server), flat arrays for a small payload:
	  Strokes = { { u, v, t, u, v, t, ... }, ... }  one list per press of the spray
	  Input   = "Mouse" | "Touch" | "Gamepad"
	t is seconds since the session started on the client. The client records
	a sample at most every SampleStep while the spray is on (also when the
	nozzle stands still), so every stretch of spraying is in the recording.

	The spray: between two samples of a stroke the nozzle moves in a straight
	line and sprays for the time between them (at most MaxStep: a frame hitch
	never sprays longer). Every cell within Radius loses dirt at
	(1 - (distance / Radius)^2) seconds per second. Spray time with no dirty
	cell in reach is wasted water. A crystal heats up while the nozzle points
	right at it (CrystalRadius) and cools off elsewhere; at CrystalHeat it
	cracks.

	Score = 1 - slow - waste - cracks:
	  slow   up to Weights.Slow: washing time over Par (the time a good player
	         needs), on a log scale (twice par costs less than half of it,
	         SlowFull times par all of it)
	  waste  up to Weights.Waste: wasted share of the spray over WasteFree
	  cracks Weights.Crack per cracked crystal (at most Weights.MaxCrack)
	Lune (tools/lune/spray_calibrate.luau): a steady sweep at par speed is
	Flawless on every rarity, a slow careful one Pristine, scribbling with
	the spray always on Clean.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local CleaningPatterns = require(script.Parent.CleaningPatterns)

local SprayScoring = {}

SprayScoring.Radius = 0.24 -- face units the spray reaches around the nozzle point
-- Spray radius multiplier per input: a finger hides what it sprays and a stick is slower to aim.
SprayScoring.InputLeniency = { Mouse = 1.0, Touch = 1.25, Gamepad = 1.15 }
SprayScoring.SampleStep = 0.05 -- the client records a sample at most this often while spraying
-- Two samples of one stroke closer than this can't come from the client (frame slack below SampleStep).
-- With the timeline check this ties the replay's work to real session time (server load, review 10-20).
SprayScoring.MinGap = SprayScoring.SampleStep - 0.01
SprayScoring.AimReach = 1.8 -- face units from the clump's middle: the pointer farther out is off the clump
SprayScoring.MaxStep = 0.1 -- a longer gap between two samples sprays only this long
SprayScoring.MaxSubsteps = 24 -- a long jump of the nozzle is split into this many sprays at most
SprayScoring.MaxReach = 3 -- face units: samples farther out are broken input
SprayScoring.MaxSamples = 4000 -- 200 s of spraying at 20 samples per second
SprayScoring.MaxStrokes = 1500 -- quick dabs (one-sample taps are dropped by the client)
-- Replay work budget: sprays per sample so far (+ slack). An honest run needs about 1-2 per
-- sample (one more per ~2.4 face units per second of nozzle speed: frantic scribbling at 9 needs
-- about 4.5, so 6 leaves room up to ~13); a forged zig-zag across the clump needs ~20.
SprayScoring.SubstepsPerSample = 6
SprayScoring.SubstepSlack = 200
SprayScoring.CrystalRadius = 0.1 -- face units: the nozzle point this close heats a crystal
SprayScoring.CrystalHeat = 0.35 -- seconds point-blank before a crystal cracks (a slow pass over it is fine)
SprayScoring.CrystalCool = 1.5 -- heat lost per second away from it
-- Par = (Base + PerAmount * the clump's dirt) / the input's leniency (a wider spray is quicker,
-- so it helps the aim, not the score). Lune: a steady sweep at 1.9 face units per second
-- (slower on thicker dirt) takes about 1.2 x par.
SprayScoring.Par = { Base = 1.5, PerAmount = 0.3 }
SprayScoring.SlowFull = 5 -- times par: the whole slow penalty
SprayScoring.WasteFree = 0.25 -- this much wasted spray costs nothing (edges, getting into place)
SprayScoring.WasteFull = 0.75 -- the full waste penalty from here
SprayScoring.Weights = { Slow = 0.4, Waste = 0.2, Crack = 0.12, MaxCrack = 0.36 }
-- Samples later than this can't come from a live session (the server ends sessions at CleaningTimeout).
SprayScoring.MaxSampleTime = GameConfig.CleaningTimeout + 10

--[[
	Fixed pauses of the real client (seconds). The client waits exactly these
	(task.wait / task.delay never return early), and the server's timeline
	check requires the same gaps. Change them here only: a client-only change
	would get every honest run rejected.
]]
SprayScoring.ClientPauses = {
	Intro = 0.75, -- the camera flies in before the spray works
	Finish = 0.5, -- the last specks wash off before the recording is sent
}
local PAUSE_SLACK = 0.05 -- frame timing; the real client is always slower than these gaps
SprayScoring.MinGaps = {
	FirstSpray = SprayScoring.ClientPauses.Intro - PAUSE_SLACK, -- session start -> first sample
	ToSubmit = SprayScoring.ClientPauses.Finish - PAUSE_SLACK, -- last sample -> CleanSubmit
}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

---------------------------------------------------------------- tracker

local SprayTracker = {}
SprayTracker.__index = SprayTracker
SprayScoring.SprayTracker = SprayTracker

export type Tracker = typeof(setmetatable(
	{} :: {
		pattern: CleaningPatterns.Pattern,
		leniency: number,
		radius: number,
		dirt: { number },
		cleaned: { [number]: boolean },
		cleanedCount: number,
		heat: { number },
		heatT: { number },
		cracked: { [number]: boolean },
		cracks: number,
		substeps: number,
		sprayTime: number,
		wasteTime: number,
		firstT: number?, -- the first spray that hit dirt
		doneT: number?, -- the spray that finished the job
		lastT: number?, -- the latest sample
		lastU: number?,
		lastV: number?, -- nil while the spray is off
	},
	SprayTracker
))

function SprayTracker.new(pattern: CleaningPatterns.Pattern, input: any): Tracker
	local dirt = {}
	for i, cell in pattern.Cells do
		dirt[i] = cell.Amount
	end
	local heat, heatT = {}, {}
	for i in pattern.Crystals do
		heat[i] = 0
		heatT[i] = 0
	end
	return setmetatable({
		pattern = pattern,
		leniency = SprayScoring.InputLeniency[input] or 1,
		radius = SprayScoring.Radius * (SprayScoring.InputLeniency[input] or 1),
		dirt = dirt,
		cleaned = {},
		cleanedCount = 0,
		heat = heat,
		heatT = heatT,
		cracked = {},
		cracks = 0,
		substeps = 0,
		sprayTime = 0,
		wasteTime = 0,
		firstT = nil,
		doneT = nil,
		lastT = nil,
		lastU = nil,
		lastV = nil,
	}, SprayTracker)
end

function SprayTracker.complete(self: Tracker): boolean
	return self.cleanedCount >= self.pattern.Required
end

-- 0..1: how far the job is (1 = done).
function SprayTracker.progress(self: Tracker): number
	return math.min(1, self.cleanedCount / math.max(1, self.pattern.Required))
end

-- How much of a cell's dirt is left (0 = clean, 1 = untouched).
function SprayTracker.left(self: Tracker, index: number): number
	local cell = self.pattern.Cells[index]
	return if cell then math.max(0, self.dirt[index]) / cell.Amount else 0
end

-- One spray of `dt` seconds at (u, v), starting at time t.
local function spray(self: Tracker, u: number, v: number, dt: number, t: number, cleanedNow: { number }, crackedNow: { number })
	local pattern = self.pattern
	local r = self.radius
	local grid, size, origin = pattern.Grid, pattern.CellSize, pattern.Origin
	local fromX = math.max(0, math.floor((u - r - origin.X) / size))
	local toX = math.min(grid - 1, math.floor((u + r - origin.X) / size))
	local fromY = math.max(0, math.floor((v - r - origin.Y) / size))
	local toY = math.min(grid - 1, math.floor((v + r - origin.Y) / size))
	local useful = false
	for gx = fromX, toX do
		for gy = fromY, toY do
			local index = pattern.CellAt[gx * grid + gy]
			if index and not self.cleaned[index] then
				local center = pattern.Cells[index].Center
				local du, dv = center.X - u, center.Y - v
				local d2 = du * du + dv * dv
				if d2 < r * r then
					useful = true
					self.dirt[index] -= dt * (1 - d2 / (r * r))
					if self.dirt[index] <= 0 then
						self.cleaned[index] = true
						self.cleanedCount += 1
						table.insert(cleanedNow, index)
					end
				end
			end
		end
	end
	self.sprayTime += dt
	if useful then
		self.firstT = self.firstT or t
	else
		self.wasteTime += dt
	end
	local reach = SprayScoring.CrystalRadius
	for i, crystal in pattern.Crystals do
		if not self.cracked[i] then
			local du, dv = crystal.Center.X - u, crystal.Center.Y - v
			if du * du + dv * dv < reach * reach then
				local cooled = math.max(0, self.heat[i] - math.max(0, t - self.heatT[i]) * SprayScoring.CrystalCool)
				self.heat[i] = cooled + dt
				self.heatT[i] = t + dt
				if self.heat[i] >= SprayScoring.CrystalHeat then
					self.cracked[i] = true
					self.cracks += 1
					table.insert(crackedNow, i)
				end
			end
		end
	end
	if not self.doneT and self:complete() then
		self.doneT = t + dt
	end
end

--[[
	A recorded sample at (u, v), time t, with the spray on. The nozzle sprays
	along the straight line from the stroke's last sample (nothing for the
	first sample of a stroke). Returns the cells that just came clean and the
	crystals that just cracked. Nothing changes once the job is done.
]]
function SprayTracker.add(self: Tracker, u: number, v: number, t: number): ({ number }, { number })
	local cleanedNow: { number } = {}
	local crackedNow: { number } = {}
	local fromU, fromV, fromT = self.lastU, self.lastV, self.lastT
	self.lastU, self.lastV, self.lastT = u, v, t
	if self.doneT or not fromU or not fromV or not fromT then
		return cleanedNow, crackedNow
	end
	local dt = math.min(t - fromT, SprayScoring.MaxStep)
	if dt <= 0 then
		return cleanedNow, crackedNow
	end
	local du, dv = u - fromU, v - fromV
	local distance = math.sqrt(du * du + dv * dv)
	local steps = math.clamp(math.ceil(distance / (self.radius * 0.5)), 1, SprayScoring.MaxSubsteps)
	local each = dt / steps
	self.substeps += steps
	for k = 1, steps do
		local f = (k - 0.5) / steps
		spray(self, fromU + du * f, fromV + dv * f, each, fromT + (k - 1) * each, cleanedNow, crackedNow)
		if self.doneT then
			break
		end
	end
	return cleanedNow, crackedNow
end

-- The spray goes off (the next sample starts a new stroke).
function SprayTracker.lift(self: Tracker)
	self.lastU, self.lastV = nil, nil
end

function SprayScoring.par(pattern: CleaningPatterns.Pattern, input: any): number
	local leniency = SprayScoring.InputLeniency[input] or 1
	return (SprayScoring.Par.Base + SprayScoring.Par.PerAmount * pattern.TotalAmount) / leniency
end

-- 0..1 of the slow penalty for a washing time of `ratio` times par.
function SprayScoring.slowness(ratio: number): number
	if ratio <= 1 then
		return 0
	end
	return math.clamp(math.log(ratio) / math.log(SprayScoring.SlowFull), 0, 1)
end

export type Parts = { Score: number, Speed: number, Aim: number, Cracks: number, Time: number }

-- The score of what the tracker saw, as if the job ended at `now` (default: when it was done).
function SprayTracker.parts(self: Tracker, now: number?): Parts
	local w = SprayScoring.Weights
	local finish = self.doneT or now or self.lastT or 0
	local time = if self.firstT then math.max(0, finish - self.firstT) else 0
	local par = (SprayScoring.Par.Base + SprayScoring.Par.PerAmount * self.pattern.TotalAmount) / self.leniency
	local over = SprayScoring.slowness(time / par)
	local wasted = if self.sprayTime > 0 then self.wasteTime / self.sprayTime else 0
	local waste = math.clamp((wasted - SprayScoring.WasteFree) / (SprayScoring.WasteFull - SprayScoring.WasteFree), 0, 1)
	local crack = math.min(w.MaxCrack, self.cracks * w.Crack)
	return {
		Score = math.clamp(1 - over * w.Slow - waste * w.Waste - crack, 0, 1),
		Speed = 1 - over,
		Aim = 1 - wasted,
		Cracks = self.cracks,
		Time = time,
	}
end

---------------------------------------------------------------- scoring

export type Result = {
	Valid: boolean,
	Reason: string?,
	Score: number,
	Grade: string,
	Speed: number,
	Aim: number,
	Cracks: number,
	Time: number,
}

local function invalid(reason: string): Result
	return { Valid = false, Reason = reason, Score = 0, Grade = "Rough", Speed = 0, Aim = 0, Cracks = 0, Time = 0 }
end

--[[
	Full score. `submission` comes from the client (untrusted: every field is
	checked). Valid = false means the input was impossible or the dirt is
	still on: no grade.
]]
function SprayScoring.score(pattern: CleaningPatterns.Pattern, submission: any): Result
	if type(submission) ~= "table" or type(submission.Strokes) ~= "table" then
		return invalid("bad submission")
	end
	local strokes = submission.Strokes
	if #strokes > SprayScoring.MaxStrokes then
		return invalid("too many strokes")
	end
	local tracker = SprayTracker.new(pattern, submission.Input)
	local count = 0
	local replayed = 0
	local lastT = -1
	local reach = SprayScoring.MaxReach
	for s = 1, #strokes do
		local stroke = strokes[s]
		if type(stroke) ~= "table" or #stroke % 3 ~= 0 then
			return invalid("bad stroke")
		end
		count += #stroke // 3
		if count > SprayScoring.MaxSamples then
			return invalid("too many samples")
		end
		for i = 1, #stroke, 3 do
			local u, v, t = stroke[i], stroke[i + 1], stroke[i + 2]
			if not (finite(u) and finite(v) and finite(t)) then
				return invalid("non-finite sample")
			end
			if math.abs(u) > reach or math.abs(v) > reach or t < lastT - 1e-6 or t < 0 or t > SprayScoring.MaxSampleTime then
				return invalid("sample out of range")
			end
			-- inside a stroke the client records at most every SampleStep
			if i > 1 and t - lastT < SprayScoring.MinGap then
				return invalid("samples too close")
			end
			lastT = t
			tracker:add(u, v, t)
			replayed += 1
			if tracker.substeps > replayed * SprayScoring.SubstepsPerSample + SprayScoring.SubstepSlack then
				return invalid("too much spray")
			end
		end
		tracker:lift()
	end
	if not tracker:complete() then
		return invalid("dirt left")
	end
	local parts = tracker:parts()
	return {
		Valid = true,
		Reason = nil,
		Score = parts.Score,
		Grade = ItemData.gradeFromScore(parts.Score),
		Speed = parts.Speed,
		Aim = parts.Aim,
		Cracks = parts.Cracks,
		Time = parts.Time,
	}
end

--[[
	The server's cheap check, run BEFORE the replay (score). Shape-safe and
	O(samples): only the timestamps are read. elapsed = seconds since the
	server started the session. The client's clock starts later (when
	CleanBegin arrives), sprays only after the intro and sends the recording
	only after the finish pause, so an honest run always has
	first >= MinGaps.FirstSpray and elapsed >= latest + MinGaps.ToSubmit.
	A bot therefore needs at least as long as a perfect player going through
	the real client, and with MinGap a heavy recording needs as much real
	session time (the replay's work follows the time a player really spent).
]]
function SprayScoring.fitsSession(submission: any, elapsed: number): (boolean, string?)
	if type(submission) ~= "table" or type(submission.Strokes) ~= "table" then
		return false, "bad submission"
	end
	local strokes = submission.Strokes
	if #strokes > SprayScoring.MaxStrokes then
		return false, "too many strokes"
	end
	local first, latest = math.huge, -math.huge
	local count = 0
	for s = 1, #strokes do
		local stroke = strokes[s]
		if type(stroke) ~= "table" or #stroke % 3 ~= 0 then
			return false, "bad stroke"
		end
		count += #stroke // 3
		if count > SprayScoring.MaxSamples then
			return false, "too many samples"
		end
		for i = 3, #stroke, 3 do
			local t = stroke[i]
			if not finite(t) then
				return false, "non-finite sample"
			end
			first = math.min(first, t)
			latest = math.max(latest, t)
		end
	end
	if first == math.huge then
		return false, "no spray"
	end
	if first < SprayScoring.MinGaps.FirstSpray - 1e-6 then
		return false, "sprayed before the intro"
	end
	if latest + SprayScoring.MinGaps.ToSubmit > elapsed then
		return false, `timing mismatch ({math.floor(latest * 10) / 10}s claimed in {math.floor(elapsed * 10) / 10}s)`
	end
	return true, nil
end

return SprayScoring
