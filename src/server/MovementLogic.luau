--[[
	MovementLogic: the pure rules of the movement check and the beam line of
	sight (docs/plans/MOVEMENT_CHECK_PLAN.md). No Roblox services: the Lune
	tests drive it directly, MovementService and MiningService feed it what
	they read from the characters and the world. Numbers: MovementConfig.

	Movement (one State per player, one Sample every SampleInterval):
	- maxSpeed = (Humanoid.WalkSpeed + hoverboard speed) * SpeedFactor; an
	  unreadable walk speed counts as MaxWalkSpeed, an unknown board as
	  MaxHoverboardSpeed. Between two samples the higher maxSpeed and jump of
	  the two count (a slowdown never counts against the move before it).
	- A move is over the limit when its horizontal distance is more than
	  maxSpeed * dt + Slack (+ beltSpeed * dt while standing on a belt: only
	  asked for a move over the limit) or it rises more than jumpHeight +
	  UpSlack + maxSpeed * dt * ClimbPerStud (stairs and ramps). Falling is free.
	- Start over (the sample just resets, the trusted anchor too): the first
	  sample, a new character, ServerMoveGrace after serverMoved, the first
	  JoinGrace seconds.
	- Skip (no check, the trusted anchor keeps its rule): seated, and the
	  FallingDown / Ragdoll / Physics states for at most StateGraceBudget
	  seconds per StateGraceWindow (the client reports its Humanoid state, so a
	  cheat can't stay exempt by faking one).
	- ViolationsToFlag violations within ViolationWindow = flagged for
	  FlagSeconds; FlagsToLog flags within FlagLogWindow = one log line.
	  Nothing here ever kicks or moves anyone.
	- The trusted anchor ("the last good sample") only moves to a sample that
	  could be reached from it in the time since, so a teleport leaves it
	  behind until the walk there would have taken that long.

	Beam line of sight: aim lines from the eye to the rock's box (its closest
	point, then its top center), each stopping BeamStopShort studs before the
	rock so a wall right behind the rock never counts; the line is clear when
	a cast finds nothing, or only parts the caller ignores.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))

local MovementLogic = {}

export type Config = typeof(MovementConfig)

export type State = {
	JoinedAt: number,
	GraceUntil: number,
	Character: any, -- the character the samples belong to (a new one starts over)
	Last: Vector3?, -- the previous sample
	LastAt: number,
	LastSpeed: number,
	LastJump: number,
	Trusted: Vector3?, -- the last good sample (nil = use the live position)
	TrustedAt: number,
	TrustedSpeed: number, -- the highest maxSpeed since Trusted was set
	TrustedJump: number,
	ExemptSpent: number,
	ExemptWindowStart: number,
	Violations: { number }, -- times, within ViolationWindow
	FlaggedUntil: number,
	Flags: { number }, -- times, within FlagLogWindow
	Worst: number, -- the largest excess (studs) since the last log line
	LoggedWorst: number, -- Worst at the last log line
	Logs: number,
}

export type Sample = {
	Position: Vector3,
	Character: any,
	Seated: boolean,
	Exempt: boolean, -- FallingDown / Ragdoll / Physics
	WalkSpeed: number,
	BoardSpeed: number,
	JumpHeight: number,
	BeltSpeed: number,
	OnBelt: (() -> boolean)?, -- asked only for a move over the limit
}

export type Outcome = "Start" | "Grace" | "Skip" | "Ok" | "Violation"

export type Hit = { Instance: Instance, Position: Vector3 }
export type Cast = (origin: Vector3, direction: Vector3) -> Hit?
export type Line = { Origin: Vector3, Direction: Vector3 }

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

---------------------------------------------------------------- limits

-- The highest legitimate horizontal speed: (walk + board) * SpeedFactor.
function MovementLogic.maxSpeed(walkSpeed: number, boardSpeed: number, cfg: Config): number
	local walk = if type(walkSpeed) == "number" and finite(walkSpeed) then math.max(0, walkSpeed) else cfg.MaxWalkSpeed
	local board = if type(boardSpeed) == "number" and finite(boardSpeed) then math.max(0, boardSpeed) else cfg.MaxHoverboardSpeed
	return (walk + board) * cfg.SpeedFactor
end

-- How high the Humanoid jumps: JumpPower^2 / (2 * gravity) with UseJumpPower, else JumpHeight.
function MovementLogic.jumpHeight(useJumpPower: boolean, jumpPower: number, jumpHeight: number, gravity: number, cfg: Config): number
	local height: number
	if useJumpPower then
		if type(jumpPower) == "number" and finite(jumpPower) and type(gravity) == "number" and finite(gravity) and gravity > 0 then
			height = jumpPower * jumpPower / (2 * gravity)
		else
			height = cfg.DefaultJumpHeight
		end
	else
		height = if type(jumpHeight) == "number" and finite(jumpHeight) then jumpHeight else cfg.DefaultJumpHeight
	end
	return math.clamp(height, 0, cfg.MaxJumpHeight)
end

-- Studs a character may cover horizontally in `dt` seconds.
function MovementLogic.allowedHorizontal(speed: number, dt: number, beltSpeed: number, cfg: Config): number
	return (speed + beltSpeed) * math.max(0, dt) + cfg.Slack
end

-- Studs a character may rise in `dt` seconds (a jump, plus stairs and ramps while walking).
function MovementLogic.allowedUp(jump: number, speed: number, dt: number, cfg: Config): number
	return jump + cfg.UpSlack + speed * math.max(0, dt) * cfg.ClimbPerStud
end

-- How far a move is over the limit (<= 0: fine). Falling is free.
function MovementLogic.excess(from: Vector3, to: Vector3, dt: number, speed: number, jump: number, beltSpeed: number, cfg: Config): number
	local delta = to - from
	local flat = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
	local over = flat - MovementLogic.allowedHorizontal(speed, dt, beltSpeed, cfg)
	if delta.Y > 0 then
		over = math.max(over, delta.Y - MovementLogic.allowedUp(jump, speed, dt, cfg))
	end
	return over
end

---------------------------------------------------------------- state

function MovementLogic.newState(now: number): State
	return {
		JoinedAt = now,
		GraceUntil = -math.huge,
		Character = nil,
		Last = nil,
		LastAt = now,
		LastSpeed = 0,
		LastJump = 0,
		Trusted = nil,
		TrustedAt = now,
		TrustedSpeed = 0,
		TrustedJump = 0,
		ExemptSpent = 0,
		ExemptWindowStart = now,
		Violations = {},
		FlaggedUntil = -math.huge,
		Flags = {},
		Worst = 0,
		LoggedWorst = 0,
		Logs = 0,
	}
end

function MovementLogic.isFlagged(state: State, now: number): boolean
	return now < state.FlaggedUntil
end

-- The last good sample while flagged (nil when not flagged or unknown: use the live position).
function MovementLogic.trusted(state: State, now: number): Vector3?
	if MovementLogic.isFlagged(state, now) then
		return state.Trusted
	end
	return nil
end

-- The server moved the character: the samples start over for ServerMoveGrace seconds.
function MovementLogic.serverMoved(state: State, now: number, cfg: Config)
	state.GraceUntil = math.max(state.GraceUntil, now + cfg.ServerMoveGrace)
	state.Trusted = nil -- the live position until the next sample sets the anchor there
end

-- Drops the times before `cutoff` (the list is in time order).
local function prune(times: { number }, cutoff: number)
	while #times > 0 and times[1] < cutoff do
		table.remove(times, 1)
	end
end

-- Counts a violation. Returns (flagged now, write a log line now).
function MovementLogic.recordViolation(state: State, now: number, excess: number, cfg: Config): (boolean, boolean)
	state.Worst = math.max(state.Worst, excess)
	prune(state.Violations, now - cfg.ViolationWindow)
	table.insert(state.Violations, now)
	if #state.Violations < cfg.ViolationsToFlag then
		return false, false
	end
	table.clear(state.Violations)
	state.FlaggedUntil = now + cfg.FlagSeconds
	prune(state.Flags, now - cfg.FlagLogWindow)
	table.insert(state.Flags, now)
	if #state.Flags < cfg.FlagsToLog then
		return true, false
	end
	table.clear(state.Flags)
	state.LoggedWorst = state.Worst
	state.Worst = 0
	state.Logs += 1
	return true, true
end

local function restart(state: State, sample: Sample, now: number, speed: number, jump: number)
	state.Character = sample.Character
	state.Last = sample.Position
	state.LastAt = now
	state.LastSpeed = speed
	state.LastJump = jump
	state.Trusted = sample.Position
	state.TrustedAt = now
	state.TrustedSpeed = speed
	state.TrustedJump = jump
end

--[[
	One sample. Returns (outcome, flagged now, log now, excess in studs).
	Never yields; OnBelt is called at most once.
]]
function MovementLogic.step(state: State, sample: Sample, now: number, cfg: Config): (Outcome, boolean, boolean, number)
	local position = sample.Position
	local speed = MovementLogic.maxSpeed(sample.WalkSpeed, sample.BoardSpeed, cfg)
	local jump = if type(sample.JumpHeight) == "number" and finite(sample.JumpHeight)
		then math.clamp(sample.JumpHeight, 0, cfg.MaxJumpHeight)
		else cfg.DefaultJumpHeight
	local last = state.Last
	if not last then
		restart(state, sample, now, speed, jump)
		return "Start", false, false, 0
	end
	if sample.Character ~= state.Character or now < state.GraceUntil or now < state.JoinedAt + cfg.JoinGrace then
		restart(state, sample, now, speed, jump)
		return "Grace", false, false, 0
	end
	local dt = math.max(0, now - state.LastAt)
	-- standing on a belt, asked once and only when a move is over the limit
	local beltAsked, onBelt = false, false
	local function beltSpeed(): number
		if not beltAsked then
			beltAsked = true
			local ask = sample.OnBelt
			onBelt = ask ~= nil and sample.BeltSpeed > 0 and ask()
		end
		return if onBelt then sample.BeltSpeed else 0
	end

	-- the trusted anchor follows only moves possible from it in the time since
	state.TrustedSpeed = math.max(state.TrustedSpeed, speed)
	state.TrustedJump = math.max(state.TrustedJump, jump)
	local trusted = state.Trusted
	if not trusted then
		state.Trusted = position
		state.TrustedAt = now
		state.TrustedSpeed, state.TrustedJump = speed, jump
	else
		local since = now - state.TrustedAt
		local over = MovementLogic.excess(trusted, position, since, state.TrustedSpeed, state.TrustedJump, 0, cfg)
		if over > 0 then
			over = MovementLogic.excess(trusted, position, since, state.TrustedSpeed, state.TrustedJump, beltSpeed(), cfg)
		end
		if over <= 0 then
			state.Trusted = position
			state.TrustedAt = now
			state.TrustedSpeed, state.TrustedJump = speed, jump
		end
	end

	-- seated, or a Humanoid state within its budget: no check
	local exempt = sample.Seated == true
	if not exempt and sample.Exempt then
		if now - state.ExemptWindowStart > cfg.StateGraceWindow then
			state.ExemptWindowStart = now
			state.ExemptSpent = 0
		end
		state.ExemptSpent += math.min(dt, 1) -- a long gap before this sample isn't time spent in the state
		exempt = state.ExemptSpent <= cfg.StateGraceBudget
	end

	local outcome: Outcome = "Ok"
	local flaggedNow, logNow, excess = false, false, 0
	if exempt then
		outcome = "Skip"
	else
		local pairSpeed = math.max(speed, state.LastSpeed)
		local pairJump = math.max(jump, state.LastJump)
		excess = MovementLogic.excess(last, position, dt, pairSpeed, pairJump, 0, cfg)
		if excess > 0 then
			excess = MovementLogic.excess(last, position, dt, pairSpeed, pairJump, beltSpeed(), cfg)
		end
		if excess > 0 then
			outcome = "Violation"
			flaggedNow, logNow = MovementLogic.recordViolation(state, now, excess, cfg)
		else
			excess = 0
		end
	end
	state.Last = position
	state.LastAt = now
	state.LastSpeed = speed
	state.LastJump = jump
	return outcome, flaggedNow, logNow, excess
end

-- The fastest belt (studs per second): conveyorSpeed * the highest SpeedMult of a belt machine.
function MovementLogic.fastestBelt(machines: { any }, conveyorSpeed: number): number
	local best = 0
	for _, info in machines do
		if type(info) == "table" and info.IsConveyor == true then
			local mult = info.SpeedMult
			if type(mult) ~= "number" or not finite(mult) or mult <= 0 then
				mult = 1
			end
			best = math.max(best, conveyorSpeed * mult)
		end
	end
	return best
end

---------------------------------------------------------------- beam line of sight

-- The world-axis box (min, max) around a part's rotated box.
function MovementLogic.partBounds(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local extent = Vector3.new(
		math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz,
		math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz,
		math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	)
	local center = cf.Position
	return center - extent, center + extent
end

-- The point of the box (min, max) closest to `point` (the point itself inside).
function MovementLogic.closestPoint(point: Vector3, min: Vector3, max: Vector3): Vector3
	return Vector3.new(math.clamp(point.X, min.X, max.X), math.clamp(point.Y, min.Y, max.Y), math.clamp(point.Z, min.Z, max.Z))
end

-- Where the segment from -> to first enters the box (from itself when inside, nil when it misses).
function MovementLogic.entryPoint(from: Vector3, to: Vector3, min: Vector3, max: Vector3): Vector3?
	local d = to - from
	local tmin, tmax = 0, 1
	local starts = { from.X, from.Y, from.Z }
	local dirs = { d.X, d.Y, d.Z }
	local mins = { min.X, min.Y, min.Z }
	local maxs = { max.X, max.Y, max.Z }
	for axis = 1, 3 do
		local s, v = starts[axis], dirs[axis]
		if math.abs(v) < 1e-9 then
			if s < mins[axis] or s > maxs[axis] then
				return nil
			end
		else
			local t1 = (mins[axis] - s) / v
			local t2 = (maxs[axis] - s) / v
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return from + d * tmin
end

-- A line from `eye` that stops `stopShort` before `point` (nil when the eye is that close).
local function lineTo(eye: Vector3, point: Vector3, stopShort: number): Line?
	local toward = point - eye
	local length = toward.Magnitude
	if length <= stopShort then
		return nil
	end
	return { Origin = eye, Direction = toward.Unit * (length - stopShort) }
end

--[[
	The aim lines from the eye to a rock's box: its closest point first, then
	where the line to its top center enters the box (a rock on a ledge above
	you). Each stops `stopShort` before the rock. nil = the eye is within
	stopShort of the rock (or inside its box): nothing can stand between.
]]
function MovementLogic.beamLines(eye: Vector3, min: Vector3, max: Vector3, stopShort: number): { Line }?
	local closest = MovementLogic.closestPoint(eye, min, max)
	local first = lineTo(eye, closest, stopShort)
	if not first then
		return nil
	end
	local lines = { first }
	local top = Vector3.new((min.X + max.X) / 2, max.Y, (min.Z + max.Z) / 2)
	local entry = MovementLogic.entryPoint(eye, top, min, max)
	if entry and (entry - closest).Magnitude > 0.5 then
		local second = lineTo(eye, entry, stopShort)
		if second then
			table.insert(lines, second)
		end
	end
	return lines
end

-- Is one line clear? Hits where `ignored(instance)` is true are cast through (at most maxPasses casts).
function MovementLogic.lineClear(line: Line, cast: Cast, ignored: (Instance) -> boolean, maxPasses: number): boolean
	local from = line.Origin
	local direction = line.Direction
	for _ = 1, math.max(1, maxPasses) do
		local hit = cast(from, direction)
		if not hit then
			return true
		end
		if not ignored(hit.Instance) then
			return false
		end
		local length = direction.Magnitude
		local travelled = (hit.Position - from).Magnitude + 0.05
		if travelled >= length then
			return true
		end
		local unit = direction.Unit
		from = from + unit * travelled
		direction = unit * (length - travelled)
	end
	return true -- only ignored parts were in the way
end

-- Can the beam reach the rock's box from the eye? (any aim line clear)
function MovementLogic.beamClear(eye: Vector3, min: Vector3, max: Vector3, cast: Cast, ignored: (Instance) -> boolean, cfg: Config): boolean
	local lines = MovementLogic.beamLines(eye, min, max, cfg.BeamStopShort)
	if not lines then
		return true
	end
	for _, line in lines do
		if MovementLogic.lineClear(line, cast, ignored, cfg.BeamMaxPasses) then
			return true
		end
	end
	return false
end

return MovementLogic
