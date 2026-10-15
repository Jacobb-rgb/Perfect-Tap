--[[
	CutRecorder: how the client records one chisel cut (pure logic, shared so
	the Lune tests run exactly the client's rules).

	- Pointer positions go to the shared CutTracker. Only samples from the
	  moment the cut starts are kept: earlier ones don't change the tracker,
	  so the server replays exactly the kept samples and gets the same score.
	- Lifting the pointer keeps the groove. After an early lift (less than
	  FalseStart of the line done) the next press decides: on the line near
	  the groove tip (ResumeReach tolerances, at most half of what is left of
	  the line) the cut goes on; anywhere else the attempt starts over.
	  So a touch at the wrong end is forgotten, but a thumb lifted to look at
	  the line can carry on where the groove ends. Both cases replay the same
	  on the server: a dropped attempt is never sent.
	- A very long wobbly attempt that runs out of sample room starts over.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CleaningPatterns = require(script.Parent.CleaningPatterns)
local CleaningScoring = require(script.Parent.CleaningScoring)
local Geometry2D = require(script.Parent.Geometry2D)

local CutRecorder = {}
CutRecorder.__index = CutRecorder

CutRecorder.MinSampleDistance = 0.015 -- face units between kept samples
CutRecorder.MinSampleTime = 1 / 50 -- seconds between kept samples
CutRecorder.MaxReach = 2.5 -- face units; farther out the pointer is nowhere near the ore (server limit is 3)
CutRecorder.FalseStart = 0.3 -- an early lift (less than this much of the line) may start the cut over
CutRecorder.ResumeReach = 4 -- tolerances from the groove tip that still carry on the cut

export type Feed = {
	State: CleaningScoring.CutState?, -- nil when the position was skipped (too close, too soon, out of reach)
	Recorded: boolean, -- kept for the server (the cut has started)
	Restarted: boolean, -- the previous attempt was dropped before this position was used
	Overflow: boolean, -- out of sample room: the attempt was dropped (start the line again)
	Gained: boolean, -- the groove moved forward
}

function CutRecorder.new(cut: CleaningPatterns.Cut, tolerance: number, maxSpeed: number)
	local self = setmetatable({
		cut = cut,
		tol = tolerance,
		maxSpeed = maxSpeed,
		tracker = nil :: any,
		samples = {} :: { number },
		lastSample = nil :: Vector2?,
		lastSampleT = -1,
		pendingRestart = false,
	}, CutRecorder)
	self:reset()
	return self
end

-- Starts the cut over: new tracker, no samples.
function CutRecorder.reset(self: any)
	self.tracker = CleaningScoring.CutTracker.new(self.cut, self.tol, self.maxSpeed)
	self.samples = {}
	self.lastSample = nil
	self.lastSampleT = -1
	self.pendingRestart = false
end

-- The pointer was released.
function CutRecorder.release(self: any)
	local tracker = self.tracker
	if tracker.started and not tracker.complete and tracker.progress < self.cut.Length * CutRecorder.FalseStart then
		self.pendingRestart = true
	end
end

-- One pointer position (face units) while pressed, at session time t.
function CutRecorder.feed(self: any, p: Vector2, t: number): Feed
	local result: Feed = { State = nil, Recorded = false, Restarted = false, Overflow = false, Gained = false }
	if math.abs(p.X) > CutRecorder.MaxReach or math.abs(p.Y) > CutRecorder.MaxReach then
		return result
	end
	local spacing = if #self.samples > GameConfig.MaxTracePoints * 2 then CutRecorder.MinSampleDistance * 3 else CutRecorder.MinSampleDistance
	local last = self.lastSample
	if (last and (p - last).Magnitude < spacing) or t - self.lastSampleT < CutRecorder.MinSampleTime then
		return result
	end
	if self.pendingRestart then
		self.pendingRestart = false
		-- carry on only close to the tip, never from the far end (that is a fresh start there):
		-- the window is at most half of what is left of the line
		local tracker = self.tracker
		local reach = math.min(self.tol * CutRecorder.ResumeReach, (self.cut.Length - tracker.progress) * 0.5)
		if not tracker:nearTip(p, reach) then
			self:reset()
			result.Restarted = true
		end
	end
	self.lastSample = p
	self.lastSampleT = t
	local before = self.tracker.progress
	local state = self.tracker:add(p, t)
	if not state.Started then
		result.State = state
		return result
	end
	if #self.samples >= (GameConfig.MaxTracePoints - 1) * 3 then
		self:reset()
		result.Overflow = true
		return result
	end
	table.insert(self.samples, p.X)
	table.insert(self.samples, p.Y)
	table.insert(self.samples, t)
	result.State = state
	result.Recorded = true
	result.Gained = self.tracker.progress > before
	return result
end

-- Is p on the line within ResumeReach tolerances of the groove tip (where cutting goes on)?
function CutRecorder.nearTip(self: any, p: Vector2): boolean
	return self.tracker.started and self.tracker:nearTip(p, self.tol * CutRecorder.ResumeReach)
end

-- Where the groove ends (face units), or nil before the cut started.
function CutRecorder.tip(self: any): Vector2?
	local tracker = self.tracker
	if not tracker.started then
		return nil
	end
	local point = Geometry2D.pointAt(self.cut.Line, tracker:tipS())
	return point
end

-- 1 if the cut started at Line[1], 2 if at the other end, nil before it started.
function CutRecorder.startEnd(self: any): number?
	local tracker = self.tracker
	if not tracker.started then
		return nil
	end
	return if tracker.direction == 1 then 1 else 2
end

return CutRecorder
