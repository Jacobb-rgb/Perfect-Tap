--[[
	Scores the cleaning minigame. The client uses CutTracker for live
	feedback; the server runs CleaningScoring.score() on the recorded input
	to decide the real grade. Same code on both sides = same result.

	Submission (client -> server), all arrays flat for a small payload.
	Every t is seconds since the session started on the client (one clock for
	all three steps), so the server can compare the whole timeline with the
	real session time, and with the real client's fixed pauses (ClientPauses)
	between the steps.
	  Cuts   = { { Samples = { u, v, t, u, v, t, ... } }, ... }  only samples from the moment the cut started
	                                           (CutRecorder; one kept attempt may span several strokes)
	  Scrape = { Samples = { u, v, t, ... } }  brush positions that removed dirt or snapped a crystal;
	                                           the server replays them (ScrapeTracker) to find what was hit
	  Polish = { Samples = { t, angle, t, angle, ... }, Mode = "Circle" | "Rub" }
	  Input  = "Mouse" | "Touch" | "Gamepad"
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local Geometry2D = require(script.Parent.Geometry2D)
local CleaningPatterns = require(script.Parent.CleaningPatterns)

local CleaningScoring = {}

CleaningScoring.Weights = { Chisel = 0.5, Scrape = 0.25, Polish = 0.25 }
CleaningScoring.ChipPenalty = 0.05
CleaningScoring.MaxChipPenalty = 0.3
-- Line tolerance multiplier per input. A phone shows one face unit at only ~105 pt (a 1080p
-- PC: ~315 px) and a finger is far less precise than a mouse, so touch gets twice the line
-- (Lune test: Mythic on a phone with an 8 pt wobble still reaches Clean or better).
CleaningScoring.InputLeniency = { Mouse = 1.0, Touch = 2.0, Gamepad = 1.4 }
-- Radians per second that count as good polishing. Demo = the speed of the ring's moving dot:
-- the middle of the band on a log scale (sqrt(Min * Max)), where shaky hands lose the least.
-- Max 10.5 (was 8.5): in the reviewer simulation jittery hands keep >= 0.98 polish from 0.5 to
-- 0.8 turns/s (8.5 only allowed 0.5 to 0.64).
CleaningScoring.PolishBand = { Min = 1.5, Max = 10.5, Demo = 4 }
CleaningScoring.BrushRadius = 0.17 -- face units; a dirt patch goes when the brush is within this + half its size
CleaningScoring.FragileRadius = 0.12 -- face units; closer than this to a crystal snaps it
-- Samples later than this can't come from a live session (the server ends sessions at CleaningTimeout).
CleaningScoring.MaxSampleTime = GameConfig.CleaningTimeout + 10
-- Only a bot is this fast (humans just lose points for going fast):
CleaningScoring.MaxPolishSpeed = 60 -- average rad/s over the whole polish (about 10 turns per second)

--[[
	Fixed pauses of the real client (seconds). The client waits exactly these
	(task.wait / task.delay never return early), and the server's timeline
	check requires the same gaps between the recorded steps. Change them here
	only: a client-only change would get every honest run rejected.
]]
CleaningScoring.ClientPauses = {
	Intro = 0.75, -- camera flies in before the first cut
	HitStop = 0.06, -- a finished cut freezes for a moment before the crust breaks away
	Crack = 0.45, -- the crust breaks away before the next cut (or the next step)
	LastCrack = 0.5, -- extra pause after the last cut (the core rim lights up)
	StepGap = 0.25, -- between two steps, and before the recording is sent
	ScrapeFinish = 0.7, -- "Spotless!" before polishing
	PolishFinish = 0.4, -- "Gleaming!" before the recording is sent
}
local PAUSE_SLACK = 0.05 -- frame timing; the real client is always slower than these gaps
local pauses = CleaningScoring.ClientPauses
-- The smallest gaps the real client can produce (on its session clock).
CleaningScoring.MinGaps = {
	FirstCut = pauses.Intro - PAUSE_SLACK, -- session start -> first cut sample
	BetweenCuts = pauses.HitStop + pauses.Crack - PAUSE_SLACK, -- last sample of a cut -> first of the next
	ToScrape = pauses.HitStop + pauses.LastCrack + pauses.Crack + pauses.StepGap - PAUSE_SLACK,
	ToPolish = pauses.ScrapeFinish + pauses.StepGap - PAUSE_SLACK,
	ToSubmit = pauses.PolishFinish + pauses.StepGap - PAUSE_SLACK, -- last polish sample -> CleanSubmit
}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

---------------------------------------------------------------- cut tracker

export type CutState = {
	Started: boolean,
	Progress: number, -- 0..1
	Deviation: number, -- distance to the line / tolerance
	Quality: number, -- 0..1 for this sample
	OnLine: boolean,
	Chipped: boolean, -- a chip happened on this sample
	ChipPoint: Vector2?,
	TooFast: boolean,
	Complete: boolean,
}

local CutTracker = {}
CutTracker.__index = CutTracker
CleaningScoring.CutTracker = CutTracker

function CutTracker.new(cut: CleaningPatterns.Cut, tolerance: number, maxSpeed: number)
	return setmetatable({
		cut = cut,
		tol = tolerance,
		maxSpeed = maxSpeed,
		started = false,
		direction = 1,
		progress = 0, -- arc length
		weighted = 0,
		weight = 0,
		chips = 0,
		lastChipAt = -math.huge,
		lastT = 0,
		firstT = 0,
		complete = false,
		fastSamples = 0,
	}, CutTracker)
end

function CutTracker.add(self: any, p: Vector2, t: number): CutState
	local cut = self.cut
	local tol = self.tol
	local length = cut.Length
	local d, s = Geometry2D.closest(cut.Line, p)
	local state: CutState = {
		Started = self.started,
		Progress = self.progress / length,
		Deviation = d / tol,
		Quality = 0,
		OnLine = false,
		Chipped = false,
		ChipPoint = nil,
		TooFast = false,
		Complete = self.complete,
	}
	if self.complete then
		return state
	end
	if not self.started then
		-- start near either end of the line
		local fromStart = s
		local fromEnd = length - s
		if d > tol * 2.5 or math.min(fromStart, fromEnd) > math.max(tol * 3, length * 0.15) then
			return state
		end
		self.started = true
		self.direction = if fromStart <= fromEnd then 1 else -1
		self.firstT = t
		self.lastT = t
		state.Started = true
	end
	local along = if self.direction == 1 then s else length - s
	local onLine = d <= tol * 3
	local quality = math.clamp(1 - (d - tol * 0.5) / (tol * 1.5), 0, 1)
	state.OnLine = onLine
	state.Quality = quality
	if onLine then
		local gain = along - self.progress
		if gain > 0 and gain < tol * 4 then
			local dt = math.max(t - self.lastT, 1 / 240)
			if gain / dt > self.maxSpeed then
				quality *= 0.6
				state.TooFast = true
				self.fastSamples += 1
			end
			self.weighted += quality * gain
			self.weight += gain
			self.progress = along
		end
		-- wobbling in place still counts a little, so shaky hands matter
		self.weighted += quality * 0.002
		self.weight += 0.002
	end
	-- chipping: cutting into the core side of the line
	local depth = math.huge
	for i, n in cut.Normals do
		depth = math.min(depth, cut.Offsets[i] - n:Dot(p))
	end
	if depth > tol * 1.6 and d < tol * 6 and self.progress - self.lastChipAt >= 0.18 then
		self.chips += 1
		self.lastChipAt = self.progress
		state.Chipped = true
		state.ChipPoint = p
	end
	self.lastT = t
	state.Progress = self.progress / length
	if self.progress >= length * 0.96 then
		self.complete = true
	end
	state.Complete = self.complete
	return state
end

function CutTracker.score(self: any): number
	if self.weight <= 0 then
		return 0
	end
	return math.clamp(self.weighted / self.weight, 0, 1)
end

-- Arc length (from Line[1]) where the groove ends; only meaningful once started.
function CutTracker.tipS(self: any): number
	return if self.direction == 1 then self.progress else self.cut.Length - self.progress
end

-- Is p on the line and within `distance` (face units, along the line) of the groove tip?
function CutTracker.nearTip(self: any, p: Vector2, distance: number): boolean
	local d, s = Geometry2D.closest(self.cut.Line, p)
	local along = if self.direction == 1 then s else self.cut.Length - s
	return d <= self.tol * 3 and math.abs(along - self.progress) < distance
end

---------------------------------------------------------------- scoring

export type Result = {
	Valid: boolean,
	Reason: string?,
	Score: number,
	Grade: string,
	Chisel: number,
	Scrape: number,
	Polish: number,
	Chips: number,
	FragileHits: number,
}

local function invalid(reason: string): Result
	return {
		Valid = false,
		Reason = reason,
		Score = 0,
		Grade = "Rough",
		Chisel = 0,
		Scrape = 0,
		Polish = 0,
		Chips = 0,
		FragileHits = 0,
	}
end

local function scoreCut(cut: CleaningPatterns.Cut, samples: any, tol: number, maxSpeed: number): (boolean, string?, number, number, number)
	if type(samples) ~= "table" or #samples % 3 ~= 0 or #samples > GameConfig.MaxTracePoints * 3 or #samples < 6 then
		return false, "bad cut samples", 0, 0, 0
	end
	local tracker = CutTracker.new(cut, tol, maxSpeed)
	local lastT = -1
	for i = 1, #samples, 3 do
		local u, v, t = samples[i], samples[i + 1], samples[i + 2]
		if not (finite(u) and finite(v) and finite(t)) then
			return false, "non-finite sample", 0, 0, 0
		end
		if math.abs(u) > 3 or math.abs(v) > 3 or t < lastT - 1e-6 or t < 0 or t > CleaningScoring.MaxSampleTime then
			return false, "sample out of range", 0, 0, 0
		end
		lastT = t
		tracker:add(Vector2.new(u, v), t)
	end
	if not tracker.complete then
		return false, "cut not finished", 0, 0, 0
	end
	local duration = tracker.lastT - tracker.firstT
	-- only physically impossible speeds (a bot), not a fast human flick
	if duration < math.max(0.05, cut.Length / (maxSpeed * 4)) then
		return false, "cut impossibly fast", 0, 0, 0
	end
	return true, nil, tracker:score(), tracker.chips, duration
end

---------------------------------------------------------------- scrape tracker

--[[
	Replays brush positions over the dirt. The client feeds every brush
	position but records only the ones that removed dirt or snapped a crystal
	(the others change nothing), so the server gets the same result from the
	short recorded list.
]]
local ScrapeTracker = {}
ScrapeTracker.__index = ScrapeTracker
CleaningScoring.ScrapeTracker = ScrapeTracker

function ScrapeTracker.new(pattern: CleaningPatterns.Pattern)
	return setmetatable({
		pattern = pattern,
		cleared = {} :: { [number]: boolean },
		snapped = {} :: { [number]: boolean },
		removed = 0,
		hits = 0,
		firstT = nil :: number?, -- first removal
		lastT = nil :: number?, -- last removal
	}, ScrapeTracker)
end

-- Returns the indices of dirt patches removed and crystals snapped by a brush at p.
function ScrapeTracker.add(self: any, p: Vector2, t: number): ({ number }, { number })
	local removedNow: { number } = {}
	local snappedNow: { number } = {}
	for _, d in self.pattern.Dirt do
		local distance = (d.Center - p).Magnitude
		if d.Fragile then
			if not self.snapped[d.Index] and distance <= CleaningScoring.FragileRadius then
				self.snapped[d.Index] = true
				self.hits += 1
				table.insert(snappedNow, d.Index)
			end
		elseif not self.cleared[d.Index] and distance <= CleaningScoring.BrushRadius + d.Size * 0.5 then
			self.cleared[d.Index] = true
			self.removed += 1
			table.insert(removedNow, d.Index)
		end
	end
	if #removedNow > 0 then
		self.firstT = self.firstT or t
		self.lastT = t
	end
	return removedNow, snappedNow
end

function ScrapeTracker.complete(self: any): boolean
	return self.removed >= self.pattern.DirtCount
end

-- Scrape score: each snapped crystal costs 0.15; dawdling costs up to 0.2.
-- duration = first to last removal (the client passes "now" while still scraping).
function CleaningScoring.scrapeScore(dirtCount: number, hits: number, duration: number): number
	local par = 1.5 + dirtCount * 0.07
	local slow = math.clamp((duration - par * 2) / (par * 2), 0, 1) * 0.2
	return math.clamp(1 - 0.15 * hits - slow, 0, 1)
end

local function scoreScrape(pattern: CleaningPatterns.Pattern, scrape: any): (boolean, string?, number, number, number)
	if type(scrape) ~= "table" or type(scrape.Samples) ~= "table" then
		return false, "bad scrape", 0, 0, 0
	end
	local samples = scrape.Samples
	-- every recorded sample removes or snaps at least one patch
	if #samples % 3 ~= 0 or #samples > (#pattern.Dirt + 4) * 3 then
		return false, "bad scrape samples", 0, 0, 0
	end
	local tracker = ScrapeTracker.new(pattern)
	local lastT = -1
	for i = 1, #samples, 3 do
		local u, v, t = samples[i], samples[i + 1], samples[i + 2]
		if not (finite(u) and finite(v) and finite(t)) then
			return false, "non-finite scrape sample", 0, 0, 0
		end
		if math.abs(u) > 3 or math.abs(v) > 3 or t < lastT - 1e-6 or t < 0 or t > CleaningScoring.MaxSampleTime then
			return false, "scrape sample out of range", 0, 0, 0
		end
		lastT = t
		tracker:add(Vector2.new(u, v), t)
	end
	if not tracker:complete() then
		return false, "dirt left", 0, 0, 0
	end
	local duration = (tracker.lastT or 0) - (tracker.firstT or 0)
	-- a bot clearing everything at once; any human scrub takes longer
	if duration < pattern.DirtCount / 200 then
		return false, "scraped impossibly fast", 0, 0, 0
	end
	return true, nil, CleaningScoring.scrapeScore(pattern.DirtCount, tracker.hits, duration), tracker.hits, duration
end

local function wrapAngle(a: number): number
	while a > math.pi do
		a -= math.pi * 2
	end
	while a < -math.pi do
		a += math.pi * 2
	end
	return a
end

-- Polishing: total angle travelled around the core, how much of it at a good speed,
-- and how consistently in one direction.
function CleaningScoring.polishProgress(samples: { number }): (number, number, number)
	local total, inBand, net = 0, 0, 0
	for i = 3, #samples - 1, 2 do
		local t0, a0 = samples[i - 2], samples[i - 1]
		local t1, a1 = samples[i], samples[i + 1]
		local delta = wrapAngle(a1 - a0)
		if math.abs(delta) <= math.pi * 0.75 then
			local dt = math.max(t1 - t0, 1 / 240)
			local speed = math.abs(delta) / dt
			total += math.abs(delta)
			net += delta
			if speed >= CleaningScoring.PolishBand.Min and speed <= CleaningScoring.PolishBand.Max then
				inBand += math.abs(delta)
			end
		end
	end
	return total, inBand, net
end

-- Polish score: 70% time in the speed band, 30% circling one way. "Rub" mode
-- (accessibility: no circling needed) is capped.
CleaningScoring.RubCap = 0.75
function CleaningScoring.polishScore(total: number, inBand: number, net: number, mode: any): number
	if total <= 0 then
		return 0
	end
	local score = 0.7 * (inBand / total) + 0.3 * (math.abs(net) / total)
	if mode == "Rub" then
		score = math.min(score, CleaningScoring.RubCap)
	end
	return math.clamp(score, 0, 1)
end

local function scorePolish(pattern: CleaningPatterns.Pattern, polish: any): (boolean, string?, number, number)
	if type(polish) ~= "table" or type(polish.Samples) ~= "table" then
		return false, "bad polish", 0, 0
	end
	local samples = polish.Samples
	if #samples % 2 ~= 0 or #samples > GameConfig.MaxPolishSamples * 2 or #samples < 8 then
		return false, "bad polish samples", 0, 0
	end
	local lastT = -1
	for i = 1, #samples, 2 do
		local t, a = samples[i], samples[i + 1]
		if not finite(t) or not finite(a) or t < lastT - 1e-6 or t < 0 or t > CleaningScoring.MaxSampleTime or math.abs(a) > math.pi + 1e-3 then
			return false, "bad polish sample", 0, 0
		end
		lastT = t
	end
	local total, inBand, net = CleaningScoring.polishProgress(samples)
	local needed = pattern.PolishTurns * math.pi * 2
	if total < needed * 0.95 then
		return false, "not polished", 0, 0
	end
	local duration = samples[#samples - 1] - samples[1]
	-- only a bot is this fast; fast hands just lose points (outside the speed band)
	if duration < total / CleaningScoring.MaxPolishSpeed then
		return false, "polished impossibly fast", 0, 0
	end
	return true, nil, CleaningScoring.polishScore(total, inBand, net, polish.Mode), duration
end

--[[
	Full score. `submission` comes from the client (untrusted: every field is
	checked). Returns a Result; Valid = false means the input was impossible
	or incomplete and must not award a grade.
]]
function CleaningScoring.score(pattern: CleaningPatterns.Pattern, submission: any): Result
	if type(submission) ~= "table" or type(submission.Cuts) ~= "table" then
		return invalid("bad submission")
	end
	if #submission.Cuts ~= #pattern.Cuts then
		return invalid("wrong cut count")
	end
	local leniency = CleaningScoring.InputLeniency[submission.Input] or 1
	local tol = pattern.Tolerance * leniency

	local chiselWeighted, chiselLength, chips = 0, 0, 0
	for i, cut in pattern.Cuts do
		local entry = submission.Cuts[i]
		local ok, reason, score, cutChips = scoreCut(cut, type(entry) == "table" and entry.Samples or nil, tol, pattern.MaxCutSpeed)
		if not ok then
			return invalid(`cut {i}: {reason}`)
		end
		chiselWeighted += score * cut.Length
		chiselLength += cut.Length
		chips += cutChips
	end
	local chisel = if chiselLength > 0 then chiselWeighted / chiselLength else 0

	local scrapeOk, scrapeReason, scrape, fragileHits = scoreScrape(pattern, submission.Scrape)
	if not scrapeOk then
		return invalid("scrape: " .. tostring(scrapeReason))
	end
	local polishOk, polishReason, polish = scorePolish(pattern, submission.Polish)
	if not polishOk then
		return invalid("polish: " .. tostring(polishReason))
	end

	local weights = CleaningScoring.Weights
	local penalty = math.min(CleaningScoring.MaxChipPenalty, chips * CleaningScoring.ChipPenalty)
	local total = math.clamp(weights.Chisel * chisel + weights.Scrape * scrape + weights.Polish * polish - penalty, 0, 1)
	return {
		Valid = true,
		Reason = nil,
		Score = total,
		Grade = ItemData.gradeFromScore(total),
		Chisel = chisel,
		Scrape = scrape,
		Polish = polish,
		Chips = chips,
		FragileHits = fragileHits,
	}
end

--[[
	Checks a submission that score() accepted: the steps happen in order, with
	at least the real client's pauses between them (MinGaps: the camera intro,
	the crack after each cut, the step finishes). Returns the latest timestamp;
	the server compares that with how long the session really lasted.
]]
function CleaningScoring.timeline(submission: any): (boolean, number)
	local gaps = CleaningScoring.MinGaps
	local previous, gap = 0, gaps.FirstCut
	for _, cut in submission.Cuts do
		local samples = cut.Samples
		if samples[3] < previous + gap - 1e-6 then
			return false, 0
		end
		previous, gap = samples[#samples], gaps.BetweenCuts
	end
	local scrape = submission.Scrape.Samples
	-- a finished scrape always has samples (score() checks the dirt is gone)
	if #scrape == 0 or scrape[3] < previous + gaps.ToScrape - 1e-6 then
		return false, 0
	end
	previous = scrape[#scrape]
	local polish = submission.Polish.Samples
	if polish[1] < previous + gaps.ToPolish - 1e-6 then
		return false, 0
	end
	return true, polish[#polish - 1]
end

--[[
	The server's timing check for a submission that score() accepted.
	elapsed = seconds since the server started the session. The client's clock
	starts later (when CleanBegin arrives) and it sends the recording only
	after the polish finish pause, so an honest run always has
	elapsed >= latest + MinGaps.ToSubmit. A bot therefore needs at least as
	long as a perfect player going through the real client.
]]
function CleaningScoring.fitsSession(submission: any, elapsed: number): (boolean, string?)
	local ordered, latest = CleaningScoring.timeline(submission)
	if not ordered then
		return false, "steps out of order"
	end
	if latest + CleaningScoring.MinGaps.ToSubmit > elapsed then
		return false, `timing mismatch ({math.floor(latest * 10) / 10}s claimed in {math.floor(elapsed * 10) / 10}s)`
	end
	return true, nil
end

---------------------------------------------------------------- polish gauge

-- Where the green zone sits on the SPEED gauge (0..1 along the track).
CleaningScoring.GaugeGreen = { From = 0.3, To = 0.75 }

-- Needle position (0..1) for a speed in rad/s: green exactly inside PolishBand, on a log
-- scale (shaky hands vary their speed by a factor, not by a fixed amount).
function CleaningScoring.needleFor(speed: number): number
	local band = CleaningScoring.PolishBand
	local green = CleaningScoring.GaugeGreen
	if speed < band.Min then
		return green.From * math.max(speed, 0) / band.Min
	elseif speed <= band.Max then
		return green.From + (green.To - green.From) * math.log(speed / band.Min) / math.log(band.Max / band.Min)
	end
	return green.To + (1 - green.To) * math.min(1, math.log(speed / band.Max) / math.log(2))
end

--[[
	The speed the gauge shows: the angle covered by the recorded polish
	samples over the last Window seconds (the same samples the server scores),
	so the needle reads the real speed and not a lagging average. When no
	sample comes for MaxGap seconds the window slides on and the needle drops.
]]
local PolishGauge = {}
PolishGauge.__index = PolishGauge
CleaningScoring.PolishGauge = PolishGauge
PolishGauge.Window = 0.3
PolishGauge.MaxGap = 0.12

function PolishGauge.new()
	return setmetatable({
		spans = {} :: { number }, -- fromT, toT, travel, fromT, toT, travel, ...
		lastT = -math.huge,
	}, PolishGauge)
end

-- A recorded sample at t that covered `travel` radians since the previous one at fromT.
function PolishGauge.add(self: any, fromT: number, t: number, travel: number)
	local spans = self.spans
	table.insert(spans, fromT)
	table.insert(spans, t)
	table.insert(spans, travel)
	self.lastT = t
	-- forget spans that ended long before the window
	while #spans > 0 and spans[2] < t - PolishGauge.Window - PolishGauge.MaxGap - 1 do
		table.remove(spans, 1)
		table.remove(spans, 1)
		table.remove(spans, 1)
	end
end

-- Average speed (rad/s) over the window ending now (or at the last sample, if it was recent).
function PolishGauge.speed(self: any, now: number): number
	local finish = math.max(self.lastT, now - PolishGauge.MaxGap)
	local start = finish - PolishGauge.Window
	local spans = self.spans
	local covered = 0
	for i = 1, #spans, 3 do
		local from, to, travel = spans[i], spans[i + 1], spans[i + 2]
		if to - from <= 1e-6 then
			if to > start and to <= finish then
				covered += travel
			end
		else
			local overlap = math.min(to, finish) - math.max(from, start)
			if overlap > 0 then
				covered += travel * overlap / (to - from)
			end
		end
	end
	return covered / PolishGauge.Window
end

return CleaningScoring
