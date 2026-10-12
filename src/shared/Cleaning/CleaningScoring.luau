--[[
	Scores the cleaning minigame. The client uses CutTracker for live
	feedback; the server runs CleaningScoring.score() on the recorded input
	to decide the real grade. Same code on both sides = same result.

	Submission (client -> server), all arrays flat for a small payload:
	  Cuts   = { { Samples = { u, v, t, u, v, t, ... } }, ... }  t = seconds since cut start
	  Scrape = { Removed = { index, t, ... }, Fragile = { index, t, ... } }
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
CleaningScoring.InputLeniency = { Mouse = 1.0, Touch = 1.35, Gamepad = 1.25 }
CleaningScoring.PolishBand = { Min = 1.5, Max = 8.5 } -- radians per second that count as good polishing

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
		if math.abs(u) > 3 or math.abs(v) > 3 or t < lastT - 1e-6 or t > 180 then
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

local function scoreScrape(pattern: CleaningPatterns.Pattern, scrape: any): (boolean, string?, number, number, number)
	if type(scrape) ~= "table" or type(scrape.Removed) ~= "table" then
		return false, "bad scrape", 0, 0, 0
	end
	local removed, fragile = scrape.Removed, scrape.Fragile or {}
	if type(fragile) ~= "table" or #removed % 2 ~= 0 or #fragile % 2 ~= 0 or #removed > 400 or #fragile > 40 then
		return false, "bad scrape lists", 0, 0, 0
	end
	local seen = {}
	local count = 0
	local lastT, firstT = -1, nil
	for i = 1, #removed, 2 do
		local index, t = removed[i], removed[i + 1]
		if not finite(index) or not finite(t) or index ~= math.floor(index) then
			return false, "bad scrape entry", 0, 0, 0
		end
		local patch = pattern.Dirt[index]
		if not patch or patch.Fragile or seen[index] or t < lastT - 1e-6 or t > 180 then
			return false, "bad scrape entry", 0, 0, 0
		end
		seen[index] = true
		count += 1
		lastT = t
		firstT = firstT or t
	end
	if count < pattern.DirtCount then
		return false, "dirt left", 0, 0, 0
	end
	local duration = lastT - (firstT or 0)
	if duration < pattern.DirtCount / 40 then
		return false, "scraped impossibly fast", 0, 0, 0
	end
	local hits = 0
	local seenFragile = {}
	for i = 1, #fragile, 2 do
		local index = fragile[i]
		local patch = finite(index) and pattern.Dirt[index] or nil
		if patch and patch.Fragile and not seenFragile[index] then
			seenFragile[index] = true
			hits += 1
		end
	end
	local par = 1.5 + pattern.DirtCount * 0.07
	local slow = math.clamp((duration - par * 2) / (par * 2), 0, 1) * 0.2
	local score = math.clamp(1 - 0.15 * hits - slow, 0, 1)
	return true, nil, score, hits, duration
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
		if not finite(t) or not finite(a) or t < lastT - 1e-6 or t > 180 or math.abs(a) > math.pi + 1e-3 then
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
	-- faster than ~4 turns per second is a bot, not a fast hand (fast hands lose points instead)
	if duration < total / 25 then
		return false, "polished impossibly fast", 0, 0
	end
	local consistency = math.abs(net) / math.max(total, 1e-6)
	local score = 0.7 * (inBand / total) + 0.3 * consistency
	if polish.Mode == "Rub" then
		score = math.min(score, 0.75)
	end
	return true, nil, math.clamp(score, 0, 1), duration
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

return CleaningScoring
