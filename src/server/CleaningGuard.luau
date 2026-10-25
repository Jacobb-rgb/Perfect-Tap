--[[
	CleaningGuard: keeps scripted cleaning from turning every dirty ore
	Flawless (security audit #4, owner's YES 2026-10-20). CleaningService runs
	it on every valid spray submission, after SprayScoring.

	- HARD signal (enforced): synthetic timestamps. The real client stamps
	  every sample with os.clock() on its own frames, so two intervals in a
	  row are never equal to the microsecond, let alone RunLength in a row
	  (or EqualShare of them all). A script that computes its timestamps
	  (t += step) does exactly that. Only the intervals inside a stroke
	  count, in order across the strokes: the gaps between strokes never
	  break a run (a script cutting its run into 2-sample strokes that
	  start where the last one ended still shows d, d, d, ...; review
	  2026-10-25). Such a run keeps its grade up to Pristine: FLAWLESS
	  needs real hands. Nothing else changes (no rejection), so even a
	  false positive costs a little.
	- SOFT signal (logged only while SoftEnforce is false): a perfectly even
	  nozzle speed over all the strokes, from a mouse or touch (a gamepad
	  stick can move the cursor evenly, so it never counts). One warn line
	  per player every LogEvery seconds with the counts, so the owner can
	  look at real numbers before enforcing.

	Pure apart from the per-player log counters: check() reads only the
	submission (the shape in SprayScoring's header).
]]

local CleaningGuard = {}

CleaningGuard.Config = {
	RunLength = 25, -- consecutive near-equal sample intervals that only computed timestamps give
	EqualShare = 0.5, -- or this share of all the intervals equal to the one before (many short strokes)
	EqualStep = 1e-6, -- seconds: two intervals closer than this count as equal
	MinSamples = 20, -- a signal needs at least this many samples
	SpeedSpread = 0.02, -- soft: nozzle speed's spread (median absolute deviation / median) below this is inhumanly even
	HardEnforce = true, -- synthetic timestamps: Flawless becomes Pristine
	SoftEnforce = false, -- soft signals: logged only (owner: enforce once real logs show no false positives)
	LogEvery = 60, -- seconds between two log lines per player
	CapGrade = "Pristine", -- what a flagged Flawless becomes
}

export type Verdict = {
	Synthetic: boolean, -- the hard signal
	Soft: { string }, -- names of the soft signals that fired ("Speed")
}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The longest run of consecutive near-equal intervals in a list of intervals,
-- and how many intervals equal the one before.
local function longestEqualRun(intervals: { number }): (number, number)
	local best, run, equal = 0, 0, 0
	for i = 2, #intervals do
		if math.abs(intervals[i] - intervals[i - 1]) < CleaningGuard.Config.EqualStep then
			run += 1
			equal += 1
			best = math.max(best, run)
		else
			run = 0
		end
	end
	return best, equal
end

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	return if n % 2 == 1 then sorted[(n + 1) // 2] else (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

-- How spread out positive values are: median absolute deviation / median
-- (robust: a cut's short last step or a corner doesn't hide an even pace).
-- nil when too few or the median is 0.
local function spread(values: { number }): number?
	if #values < 2 then
		return nil
	end
	local mid = median(values)
	if mid <= 0 then
		return nil
	end
	local deviations = {}
	for _, v in values do
		table.insert(deviations, math.abs(v - mid))
	end
	return median(deviations) / mid
end

-- Every `stride`-th value starting at `offset` of a flat array, if all finite (else nil).
local function column(flat: any, stride: number, offset: number): { number }?
	if type(flat) ~= "table" then
		return nil
	end
	local out = {}
	for i = offset, #flat, stride do
		local v = flat[i]
		if not finite(v) then
			return nil
		end
		table.insert(out, v)
	end
	return out
end

-- The nozzle speeds between consecutive (u, v, t) samples.
local function speeds(flat: any): { number }
	local out = {}
	if type(flat) ~= "table" then
		return out
	end
	for i = 4, #flat - 2, 3 do
		local u0, v0, t0 = flat[i - 3], flat[i - 2], flat[i - 1]
		local u1, v1, t1 = flat[i], flat[i + 1], flat[i + 2]
		if finite(u0) and finite(v0) and finite(t0) and finite(u1) and finite(v1) and finite(t1) and t1 > t0 then
			table.insert(out, math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2) / (t1 - t0))
		end
	end
	return out
end

-- What the submission's timing says (see the header).
function CleaningGuard.check(submission: any): Verdict
	local verdict: Verdict = { Synthetic = false, Soft = {} }
	if type(submission) ~= "table" or type(submission.Strokes) ~= "table" then
		return verdict
	end
	local cfg = CleaningGuard.Config
	-- the sample intervals inside every stroke, in order, as one stream (not the gaps between strokes)
	local intervals: { number } = {}
	local samples = 0
	for _, stroke in submission.Strokes do
		local stamps = column(stroke, 3, 3)
		if stamps then
			samples += #stamps
			for i = 2, #stamps do
				local dt = stamps[i] - stamps[i - 1]
				if dt > 0 then
					table.insert(intervals, dt)
				end
			end
		end
	end
	local run, equal = longestEqualRun(intervals)
	if run >= cfg.RunLength or (samples > cfg.MinSamples and equal >= (#intervals - 1) * cfg.EqualShare) then
		verdict.Synthetic = true
	end
	-- soft signal: never for a gamepad (its stick moves the cursor evenly)
	if submission.Input ~= "Gamepad" then
		local all: { number } = {}
		for _, stroke in submission.Strokes do
			for _, v in speeds(stroke) do
				table.insert(all, v)
			end
		end
		local even = if #all >= cfg.MinSamples then spread(all) else nil
		if even and even < cfg.SpeedSpread then
			table.insert(verdict.Soft, "Speed")
		end
	end
	return verdict
end

-- The grade a run keeps after the check: a flagged Flawless becomes CapGrade.
function CleaningGuard.gradeFor(grade: string, verdict: Verdict): string
	if grade ~= "Flawless" then
		return grade
	end
	local cfg = CleaningGuard.Config
	if (verdict.Synthetic and cfg.HardEnforce) or (#verdict.Soft > 0 and cfg.SoftEnforce) then
		return cfg.CapGrade
	end
	return grade
end

---------------------------------------------------------------- logging

type Counts = { Runs: number, Synthetic: number, Soft: number, Flawless: number, LoggedAt: number }
local counts: { [any]: Counts } = setmetatable({}, { __mode = "k" }) :: any
local clock: () -> number = os.clock
local log: (string) -> () = function(line: string)
	warn(line)
end

-- Counts one checked run of `player` (its grade before the check) and
-- writes the player's line when something fired, at most every LogEvery s.
function CleaningGuard.note(player: any, verdict: Verdict, grade: string)
	local entry = counts[player]
	if not entry then
		entry = { Runs = 0, Synthetic = 0, Soft = 0, Flawless = 0, LoggedAt = -math.huge }
		counts[player] = entry
	end
	entry.Runs += 1
	if grade == "Flawless" then
		entry.Flawless += 1
	end
	if verdict.Synthetic then
		entry.Synthetic += 1
	end
	if #verdict.Soft > 0 then
		entry.Soft += 1
	end
	if not verdict.Synthetic and #verdict.Soft == 0 then
		return
	end
	local now = clock()
	if now - entry.LoggedAt < CleaningGuard.Config.LogEvery then
		return
	end
	entry.LoggedAt = now
	local id = if type(player) == "table" or typeof(player) == "Instance" then (player :: any).UserId else player
	log(
		`[CleaningGuard] user {tostring(id)}: {entry.Runs} runs, {entry.Flawless} Flawless, {entry.Synthetic} synthetic timing, {entry.Soft} soft ({table.concat(
			verdict.Soft,
			","
		)})`
	)
end

-- Internals for the Lune tests only.
CleaningGuard._test = {
	longestEqualRun = longestEqualRun,
	spread = spread,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setLog = function(fn: (string) -> ())
		log = fn
	end,
	counts = function(player: any): Counts?
		return counts[player]
	end,
	reset = function()
		table.clear(counts)
		clock = os.clock
		log = function(line: string)
			warn(line)
		end
	end,
}

return CleaningGuard
