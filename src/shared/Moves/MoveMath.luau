--[[
	MoveMath: the pure math of the procedural moves (Config/MoveConfig has
	the data and the angle conventions). No instances, no services: Lune
	tests, the preview renderer, players (MoveController) and any other rig
	(quest NPCs, through Moves/MoveRig) use the same functions.

	  evaluate(move, t, weight?, out?) -> (pose, rootOffset)
	      pose[joint] = the joint's CFrame at time t (seconds since the move
	      started; a loop wraps), angles and the Root offset scaled by weight
	      (0..1, default 1). out is reused when given (no new table per frame).
	  weight(move, t, stopAt?) -> 0..1   the blend weight: fades in over
	      BlendIn, a one-shot fades out over its last BlendOut, a loop fades
	      out over BlendOut from stopAt (nil = still running)
	  done(move, t, stopAt?) -> boolean  nothing left to show
	  layer(base, pose, weight, override) -> CFrame   puts one move's joint
	      onto the animated Transform: added (base * pose) or, for an
	      Override joint, replacing it (base faded out by weight, then pose)
	  ease(name, x)                      the key curves
	  compile(move)                      the cached, radian form evaluate reads

	Keys are interpolated per angle (not slerp), so a key at 360 degrees on
	the Root is a real spin. Before scaling by a weight under 1 each angle
	is wrapped into -180..180 (the same rotation), so a fading pose always
	takes the short way back (a finished 360 spin never unwinds).
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)

export type Move = MoveConfig.Move
export type Pose = { [string]: CFrame }
export type Compiled = {
	Duration: number,
	Loop: boolean,
	BlendIn: number,
	BlendOut: number,
	Joints: { string }, -- the joints the move uses, in MoveConfig.Joints order
	Override: { [string]: boolean },
	Times: { number },
	Eases: { (number) -> number },
	Angles: { { number } }, -- [key][3 * jointIndex - 2 .. 3 * jointIndex] radians
	Offsets: { { number } }?, -- [key] = { x, y, z } studs (nil: the move never moves the Root)
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

local JOINT_INDEX: { [string]: number } = {}
for i, name in MoveConfig.Joints do
	JOINT_INDEX[name] = i
end
MoveMath.JointIndex = JOINT_INDEX

function MoveMath.compile(move: Move): Compiled
	local cached = cache[move]
	if cached then
		return cached
	end
	local used: { [string]: boolean } = {}
	local anyOffset = false
	for _, key in move.Keys do
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
	if anyOffset then
		used.Root = true
	end
	local joints: { string } = {}
	for _, name in MoveConfig.Joints do
		if used[name] then
			table.insert(joints, name)
		end
	end
	local times: { number } = {}
	local eases: { (number) -> number } = {}
	local angles: { { number } } = {}
	local offsets: { { number } } = {}
	for _, key in move.Keys do
		table.insert(times, key.T)
		local fn = if key.Ease then MoveMath.Eases[key.Ease] else nil
		table.insert(eases, fn or easeInOut)
		local row: { number } = {}
		for _, joint in joints do
			local e = if key.Pose then key.Pose[joint] else nil
			table.insert(row, if e then (e[1] or 0) * DEG else 0)
			table.insert(row, if e then (e[2] or 0) * DEG else 0)
			table.insert(row, if e then (e[3] or 0) * DEG else 0)
		end
		table.insert(angles, row)
		local o = key.Offset
		table.insert(offsets, { if o then o[1] or 0 else 0, if o then o[2] or 0 else 0, if o then o[3] or 0 else 0 })
	end
	local override: { [string]: boolean } = {}
	for _, joint in move.Override do
		override[joint] = true
	end
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
	}
	cache[move] = compiled
	return compiled
end

-- The Override set of a move (joint -> true), for MoveRig layers.
function MoveMath.overrides(move: Move): { [string]: boolean }
	return MoveMath.compile(move).Override
end

---------------------------------------------------------------- evaluate

-- The two keys around t and how far between them (0..1, eased).
function MoveMath.segment(move: Move, t: number): (number, number, number)
	local c = MoveMath.compile(move)
	local times = c.Times
	local n = #times
	if n <= 1 then
		return 1, 1, 0
	end
	local time = t
	if c.Loop then
		time = t % c.Duration
		if time >= times[n] then
			local span = c.Duration - times[n] + times[1]
			if span <= 0 then
				return n, n, 0
			end
			return n, 1, c.Eases[1]((time - times[n]) / span)
		end
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

function MoveMath.evaluate(move: Move, t: number, weight: number?, out: Pose?): (Pose, Vector3)
	local c = MoveMath.compile(move)
	local w = math.clamp(weight or 1, 0, 1)
	local pose: Pose = out or {}
	local a, b, alpha = MoveMath.segment(move, t)
	local rowA, rowB = c.Angles[a], c.Angles[b]
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
		local offsets = c.Offsets
		if joint == "Root" and offsets then
			local oa, ob = offsets[a], offsets[b]
			local ox = (oa[1] + (ob[1] - oa[1]) * alpha) * w
			local oy = (oa[2] + (ob[2] - oa[2]) * alpha) * w
			local oz = (oa[3] + (ob[3] - oa[3]) * alpha) * w
			offset = Vector3.new(ox, oy, oz)
			pose[joint] = CFrame.new(ox, oy, oz) * CFrame.Angles(rx, ry, rz)
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
			if c.BlendOut <= 0 then
				return if t >= stopAt then 0 else w
			end
			w = math.min(w, 1 - smooth((t - stopAt) / c.BlendOut))
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
		return stopAt ~= nil and t >= stopAt + c.BlendOut
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
