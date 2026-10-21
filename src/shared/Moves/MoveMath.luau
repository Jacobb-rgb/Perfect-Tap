--[[
	MoveMath: the pure math of the procedural moves (Config/MoveConfig has
	the data and the angle conventions). No instances, no services: Lune
	tests, the preview renderer, players (MoveController) and any other rig
	(quest NPCs, through Moves/MoveRig) use the same functions.

	  evaluate(move, t, weight?, out?, stopAt?) -> (pose, rootOffset)
	      pose[joint] = the joint's CFrame at time t (seconds since the move
	      started; a loop wraps, after its intro when it has LoopFrom),
	      angles and the Root offset scaled by weight (0..1, default 1). out
	      is reused when given (no new table per frame). stopAt (a stopped
	      loop): a move with an Outro plays it from the pose at stopAt
	  weight(move, t, stopAt?) -> 0..1   the blend weight: fades in over
	      BlendIn, a one-shot fades out over its last BlendOut, a loop fades
	      out over BlendOut from stopAt (nil = still running), or at the end
	      of its Outro
	  done(move, t, stopAt?) -> boolean  nothing left to show
	  layer(base, pose, weight, override) -> CFrame   puts one move's joint
	      onto the animated Transform: added (base * pose) or, for an
	      Override joint, replacing it (base faded out by weight, then pose)
	  ease(name, x)                      the key curves
	  compile(move)                      the cached, radian form evaluate reads

	Keys are interpolated per angle (not slerp), so a key at 360 degrees on
	the Root is a real spin. Before scaling by a weight under 1 each angle
	is wrapped into -180..180 (the same rotation), so a fading pose always
	takes the short way back (a finished 360 spin never unwinds). The Root
	turns in YXZ order about its RootPivot (MoveConfig).
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)

export type Move = MoveConfig.Move
export type Pose = { [string]: CFrame }
export type Compiled = {
	Duration: number,
	Loop: boolean,
	BlendIn: number,
	BlendOut: number,
	Joints: { string }, -- the joints the move uses, in MoveConfig.Joints (then ToolJoints) order
	Override: { [string]: boolean },
	Times: { number },
	Eases: { (number) -> number },
	Angles: { { number } }, -- [key][3 * jointIndex - 2 .. 3 * jointIndex] radians
	Offsets: { { number } }?, -- [key] = { x, y, z } studs (nil: the move never moves the Root)
	LoopStart: number, -- the key a loop goes back to (1, or the key at LoopFrom)
	Pivot: { number }?, -- the Root's turning point (studs from the joint)
	OutroTimes: { number }?,
	OutroEases: { (number) -> number },
	OutroAngles: { { number } },
	OutroOffsets: { { number } },
	OutroEnd: number, -- seconds the outro lasts (0: none)
	Scratch: { number }, -- the pose at the stop (reused)
	ScratchOffset: { number },
}

local MoveMath = {}

local PI = math.pi
local TWO_PI = 2 * math.pi
local DEG = math.pi / 180

---------------------------------------------------------------- easing

local function linear(x: number): number
	return x
end
local function easeIn(x: number): number
	return x * x * x
end
local function easeOut(x: number): number
	local u = 1 - x
	return 1 - u * u * u
end
local function easeInOut(x: number): number
	if x < 0.5 then
		return 4 * x * x * x
	end
	local u = -2 * x + 2
	return 1 - u * u * u / 2
end
local function sine(x: number): number
	return 0.5 - math.cos(x * PI) / 2
end
local BACK = 1.70158
local function back(x: number): number
	local u = x - 1
	return 1 + (BACK + 1) * u * u * u + BACK * u * u
end

MoveMath.Eases = {
	Linear = linear,
	In = easeIn,
	Out = easeOut,
	InOut = easeInOut,
	Sine = sine,
	Back = back,
} :: { [string]: (number) -> number }

function MoveMath.ease(name: string?, x: number): number
	local fn = if name then MoveMath.Eases[name] else nil
	return (fn or easeInOut)(math.clamp(x, 0, 1))
end

-- the blend curve (smoothstep)
local function smooth(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

---------------------------------------------------------------- compile

local cache: { [any]: Compiled } = setmetatable({}, { __mode = "k" }) :: any

local ALL_JOINTS: { string } = table.clone(MoveConfig.Joints)
for _, name in MoveConfig.ToolJoints do
	table.insert(ALL_JOINTS, name)
end
local JOINT_INDEX: { [string]: number } = {}
for i, name in ALL_JOINTS do
	JOINT_INDEX[name] = i
end
MoveMath.JointIndex = JOINT_INDEX
MoveMath.AllJoints = ALL_JOINTS

local function easeOf(name: string?): (number) -> number
	local fn = if name then MoveMath.Eases[name] else nil
	return fn or easeInOut
end

local function rowOf(key: MoveConfig.Key, joints: { string }): { number }
	local row: { number } = {}
	for _, joint in joints do
		local e = if key.Pose then key.Pose[joint] else nil
		table.insert(row, if e then (e[1] or 0) * DEG else 0)
		table.insert(row, if e then (e[2] or 0) * DEG else 0)
		table.insert(row, if e then (e[3] or 0) * DEG else 0)
	end
	return row
end

local function offsetOf(key: MoveConfig.Key): { number }
	local o = key.Offset
	return { if o then o[1] or 0 else 0, if o then o[2] or 0 else 0, if o then o[3] or 0 else 0 }
end

function MoveMath.compile(move: Move): Compiled
	local cached = cache[move]
	if cached then
		return cached
	end
	local used: { [string]: boolean } = {}
	local anyOffset = false
	local function scan(keys: { MoveConfig.Key })
		for _, key in keys do
			if key.Pose then
				for joint in key.Pose do
					assert(JOINT_INDEX[joint], `[MoveMath] {move.Name}: unknown joint {joint}`)
					used[joint] = true
				end
			end
			if key.Offset then
				anyOffset = true
			end
		end
	end
	scan(move.Keys)
	local outro = move.Outro
	if outro then
		scan(outro)
	end
	if anyOffset or move.RootPivot then
		used.Root = true
	end
	local joints: { string } = {}
	for _, name in ALL_JOINTS do
		if used[name] then
			table.insert(joints, name)
		end
	end
	local times: { number } = {}
	local eases: { (number) -> number } = {}
	local angles: { { number } } = {}
	local offsets: { { number } } = {}
	local loopStart = 1
	for i, key in move.Keys do
		table.insert(times, key.T)
		table.insert(eases, easeOf(key.Ease))
		table.insert(angles, rowOf(key, joints))
		table.insert(offsets, offsetOf(key))
		if move.LoopFrom and math.abs(key.T - move.LoopFrom) < 1e-6 then
			loopStart = i
		end
	end
	assert(not move.LoopFrom or times[loopStart] == move.LoopFrom, `[MoveMath] {move.Name}: no key at LoopFrom`)
	local outroTimes: { number }? = nil
	local outroEases: { (number) -> number } = {}
	local outroAngles: { { number } } = {}
	local outroOffsets: { { number } } = {}
	local outroEnd = 0
	if outro and #outro > 0 then
		local list: { number } = {}
		for _, key in outro do
			table.insert(list, key.T)
			table.insert(outroEases, easeOf(key.Ease))
			table.insert(outroAngles, rowOf(key, joints))
			table.insert(outroOffsets, offsetOf(key))
			outroEnd = math.max(outroEnd, key.T)
		end
		outroTimes = list
	end
	local override: { [string]: boolean } = {}
	for _, joint in move.Override do
		override[joint] = true
	end
	local pivot = move.RootPivot
	local compiled: Compiled = {
		Duration = move.Duration,
		Loop = move.Loop,
		BlendIn = move.BlendIn,
		BlendOut = move.BlendOut,
		Joints = joints,
		Override = override,
		Times = times,
		Eases = eases,
		Angles = angles,
		Offsets = if anyOffset then offsets else nil,
		LoopStart = loopStart,
		Pivot = if pivot then { pivot[1] or 0, pivot[2] or 0, pivot[3] or 0 } else nil,
		OutroTimes = outroTimes,
		OutroEases = outroEases,
		OutroAngles = outroAngles,
		OutroOffsets = outroOffsets,
		OutroEnd = outroEnd,
		Scratch = table.create(3 * #joints, 0),
		ScratchOffset = { 0, 0, 0 },
	}
	cache[move] = compiled
	return compiled
end

-- The Override set of a move (joint -> true), for MoveRig layers.
function MoveMath.overrides(move: Move): { [string]: boolean }
	return MoveMath.compile(move).Override
end

---------------------------------------------------------------- evaluate

-- The time inside the key list (a loop wraps back to its LoopStart key after Duration).
local function keyTime(c: Compiled, t: number): number
	if c.Loop and t >= c.Duration then
		local from = c.Times[c.LoopStart]
		local span = c.Duration - from
		if span > 0 then
			return from + (t - from) % span
		end
	end
	return t
end

-- The two keys around t and how far between them (0..1, eased).
function MoveMath.segment(move: Move, t: number): (number, number, number)
	local c = MoveMath.compile(move)
	local times = c.Times
	local n = #times
	if n <= 1 then
		return 1, 1, 0
	end
	local time = keyTime(c, t)
	if c.Loop and time >= times[n] and times[n] < c.Duration then
		-- after the last key: ease back to the loop's first key at Duration
		local span = c.Duration - times[n]
		return n, c.LoopStart, c.Eases[c.LoopStart]((time - times[n]) / span)
	end
	if time <= times[1] then
		return 1, 1, 0
	end
	if time >= times[n] then
		return n, n, 0
	end
	for i = 1, n - 1 do
		local t0, t1 = times[i], times[i + 1]
		if time < t1 then
			local span = t1 - t0
			local x = if span > 0 then (time - t0) / span else 1
			return i, i + 1, c.Eases[i + 1](math.clamp(x, 0, 1))
		end
	end
	return n, n, 0
end

-- an angle in -pi..pi (the same rotation)
local function wrap(a: number): number
	local w = (a + PI) % TWO_PI - PI
	return w
end
MoveMath.wrap = wrap

-- The raw (unweighted, unwrapped) angles and offset at key time t into c.Scratch / c.ScratchOffset.
local function sample(move: Move, c: Compiled, t: number)
	local a, b, alpha = MoveMath.segment(move, t)
	local rowA, rowB = c.Angles[a], c.Angles[b]
	local out = c.Scratch
	for k = 1, #out do
		out[k] = rowA[k] + (rowB[k] - rowA[k]) * alpha
	end
	local offsets = c.Offsets
	local o = c.ScratchOffset
	if offsets then
		local oa, ob = offsets[a], offsets[b]
		for k = 1, 3 do
			o[k] = oa[k] + (ob[k] - oa[k]) * alpha
		end
	else
		o[1], o[2], o[3] = 0, 0, 0
	end
end

function MoveMath.evaluate(move: Move, t: number, weight: number?, out: Pose?, stopAt: number?): (Pose, Vector3)
	local c = MoveMath.compile(move)
	local w = math.clamp(weight or 1, 0, 1)
	local pose: Pose = out or {}
	local rowA: { number }, rowB: { number }, alpha: number
	local offA: { number }?, offB: { number }?
	local outroTimes = c.OutroTimes
	if stopAt and outroTimes and t >= stopAt then
		-- the outro: from the pose at the stop (each angle the short way) through the Outro keys
		sample(move, c, stopAt)
		local scratch = c.Scratch
		for k = 1, #scratch do
			scratch[k] = wrap(scratch[k])
		end
		local u = t - stopAt
		local n = #outroTimes
		if u >= outroTimes[n] then
			rowA, rowB, alpha = c.OutroAngles[n], c.OutroAngles[n], 0
			offA, offB = c.OutroOffsets[n], c.OutroOffsets[n]
		else
			local k = 1
			while k < n and u >= outroTimes[k] do
				k += 1
			end
			local t0 = if k == 1 then 0 else outroTimes[k - 1]
			local span = outroTimes[k] - t0
			alpha = c.OutroEases[k](if span > 0 then math.clamp((u - t0) / span, 0, 1) else 1)
			rowA = if k == 1 then scratch else c.OutroAngles[k - 1]
			rowB = c.OutroAngles[k]
			offA = if k == 1 then c.ScratchOffset else c.OutroOffsets[k - 1]
			offB = c.OutroOffsets[k]
		end
	else
		local a, b
		a, b, alpha = MoveMath.segment(move, t)
		rowA, rowB = c.Angles[a], c.Angles[b]
		local offsets = c.Offsets
		if offsets then
			offA, offB = offsets[a], offsets[b]
		end
	end
	local partial = w < 1
	local offset = Vector3.zero
	for i, joint in c.Joints do
		local k = 3 * i
		local ax, ay, az = rowA[k - 2], rowA[k - 1], rowA[k]
		local rx = ax + (rowB[k - 2] - ax) * alpha
		local ry = ay + (rowB[k - 1] - ay) * alpha
		local rz = az + (rowB[k] - az) * alpha
		if partial then
			rx, ry, rz = wrap(rx) * w, wrap(ry) * w, wrap(rz) * w
		end
		if joint == "Root" then
			local ox, oy, oz = 0, 0, 0
			if offA and offB then
				ox = (offA[1] + (offB[1] - offA[1]) * alpha) * w
				oy = (offA[2] + (offB[2] - offA[2]) * alpha) * w
				oz = (offA[3] + (offB[3] - offA[3]) * alpha) * w
				offset = Vector3.new(ox, oy, oz)
			end
			local rotation = CFrame.fromEulerAnglesYXZ(rx, ry, rz)
			local pivot = c.Pivot
			if pivot then
				local px, py, pz = pivot[1], pivot[2], pivot[3]
				pose[joint] = CFrame.new(ox + px, oy + py, oz + pz) * rotation * CFrame.new(-px, -py, -pz)
			else
				pose[joint] = CFrame.new(ox, oy, oz) * rotation
			end
		else
			pose[joint] = CFrame.Angles(rx, ry, rz)
		end
	end
	return pose, offset
end

---------------------------------------------------------------- weights

function MoveMath.weight(move: Move, t: number, stopAt: number?): number
	local c = MoveMath.compile(move)
	if t < 0 then
		return 0
	end
	local w = if c.BlendIn > 0 then smooth(t / c.BlendIn) else 1
	if c.Loop then
		if stopAt then
			if c.OutroTimes then
				-- the outro plays at full weight and ends at rest; a short fade at its very end
				local finish = stopAt + c.OutroEnd
				if t >= finish then
					return 0
				end
				if c.BlendOut > 0 then
					w = math.min(w, smooth((finish - t) / c.BlendOut))
				end
			elseif c.BlendOut <= 0 then
				return if t >= stopAt then 0 else w
			else
				w = math.min(w, 1 - smooth((t - stopAt) / c.BlendOut))
			end
		end
	else
		if t >= c.Duration then
			return 0
		end
		if c.BlendOut > 0 then
			w = math.min(w, smooth((c.Duration - t) / c.BlendOut))
		end
	end
	return math.clamp(w, 0, 1)
end

function MoveMath.done(move: Move, t: number, stopAt: number?): boolean
	local c = MoveMath.compile(move)
	if c.Loop then
		if not stopAt then
			return false
		end
		if c.OutroTimes then
			return t >= stopAt + c.OutroEnd
		end
		return t >= stopAt + c.BlendOut
	end
	return t >= c.Duration
end

---------------------------------------------------------------- layering

function MoveMath.layer(base: CFrame, pose: CFrame, weight: number, override: boolean): CFrame
	if override then
		if weight >= 1 then
			return pose
		end
		return base:Lerp(CFrame.identity, math.clamp(weight, 0, 1)) * pose
	end
	return base * pose
end

return MoveMath
