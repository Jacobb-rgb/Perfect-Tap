--[[
	GolemEmotes: the shopkeeper golems' moves (owner 2026-10-24: "big golems
	serve our shops, each a different cool golem, with emotes, e.g. waving").
	Pure math: a pose is how far the golem hops, turns, leans and raises its
	arms at a moment; Builders/GolemKeeper turns a pose into part CFrames.

	  pose(emote?, t, clock, calm?) -> Pose   `emote` playing for `t` seconds
	                                   (nil: only the idle), `clock` = any
	                                   running time (the idle's breathing and
	                                   sway); `calm` (Reduce Motion): no jump
	  Duration[emote]                  how long each one plays
	  OnTheirOwn                       the ones a golem does now and then by itself
	  own(reduced)                     those, or under Reduce Motion only Calm:
	                                   Bow and Wave, never Spin, Hop or Dance
	  Big[emote]                       the whole-body moves (Hop, Spin, Dance): a
	                                   hello or thanks waits until one is over
	  mix(a, b, w)                     a blend from pose a to pose b (w 0..1)

	Pose: Lift (a share of the golem's height), Yaw / Pitch / Roll (radians,
	the whole golem from its feet; Pitch < 0 leans forward), Right / Left
	(radians: how far each arm swings out and up from hanging down; about
	2.4 = over the head).
]]

local GolemEmotes = {}

export type Emote = "Wave" | "Hop" | "Spin" | "Dance" | "Bow" | "Cheer"

export type Pose = {
	Lift: number,
	Yaw: number,
	Pitch: number,
	Roll: number,
	Right: number,
	Left: number,
}

GolemEmotes.Duration = {
	Wave = 2.2,
	Hop = 1.0,
	Spin = 1.2,
	Dance = 2.6,
	Bow = 1.6,
	Cheer = 1.6,
} :: { [string]: number }

-- the moves a golem does now and then by itself (Wave greets, Cheer thanks)
GolemEmotes.OnTheirOwn = { "Hop", "Spin", "Dance", "Bow", "Wave" } :: { Emote }
-- under Reduce Motion: no spin, hop or dance
GolemEmotes.Calm = { "Bow", "Wave" } :: { Emote }
-- the whole-body moves: cutting one short would snap the golem round
GolemEmotes.Big = { Hop = true, Spin = true, Dance = true } :: { [string]: boolean }

-- The moves a golem may do by itself (`reduced`: Reduce Motion is on).
function GolemEmotes.own(reduced: boolean): { Emote }
	return if reduced then GolemEmotes.Calm else GolemEmotes.OnTheirOwn
end

local function smooth(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

-- 0 -> 1 over `fade` seconds, back to 0 over the last `fade` of `d`
local function inOut(t: number, d: number, fade: number): number
	return smooth(t / fade) * smooth((d - t) / fade)
end

-- 0 -> 1 -> 0 over p in 0..1 (a jump's arc)
local function bump(p: number): number
	local c = math.clamp(p, 0, 1)
	return 4 * c * (1 - c)
end

function GolemEmotes.neutral(): Pose
	return { Lift = 0, Yaw = 0, Pitch = 0, Roll = 0, Right = 0, Left = 0 }
end

-- The idle every golem keeps up: a slow breath, a sway, arms barely moving.
function GolemEmotes.idle(clock: number): Pose
	local breath = math.sin(clock * 2.2)
	return {
		Lift = 0.006 * breath,
		Yaw = 0,
		Pitch = 0,
		Roll = 0.015 * math.sin(clock * 1.3),
		Right = 0.05 * (1 + breath),
		Left = 0.05 * (1 + breath),
	}
end

-- What `emote` adds at `t` seconds (nothing once it is over).
function GolemEmotes.move(emote: string, t: number): Pose
	local p = GolemEmotes.neutral()
	local d = GolemEmotes.Duration[emote]
	if not d or t < 0 or t > d then
		return p
	end
	if emote == "Wave" then
		local w = inOut(t, d, 0.3)
		p.Right = w * (2.4 + 0.35 * math.sin(t * 10))
		p.Roll = -0.05 * w
	elseif emote == "Hop" then
		local arc = bump(t / 0.7)
		p.Lift = 0.12 * arc
		p.Right = 0.6 * arc
		p.Left = 0.6 * arc
	elseif emote == "Spin" then
		p.Yaw = 2 * math.pi * smooth(t / d)
		p.Lift = 0.06 * bump(t / d)
	elseif emote == "Dance" then
		local w = inOut(t, d, 0.3)
		local beat = math.sin(t * 7)
		p.Roll = 0.1 * beat * w
		p.Yaw = 0.25 * math.sin(t * 3.5) * w
		p.Right = w * (1.2 + beat)
		p.Left = w * (1.2 - beat)
		p.Lift = 0.03 * math.abs(beat) * w
	elseif emote == "Bow" then
		local b = bump(t / d)
		p.Pitch = -0.4 * b
		p.Right = 0.3 * b
		p.Left = 0.3 * b
	elseif emote == "Cheer" then
		local w = inOut(t, d, 0.2)
		p.Right = 2.7 * w
		p.Left = 2.7 * w
		p.Lift = 0.1 * bump((t % 0.8) / 0.8) * w
	end
	return p
end

-- The whole pose: the idle plus `emote` (if any) at `t`; `calm` (Reduce
-- Motion): the emote leaves the golem on the floor (a cheer without its jump).
function GolemEmotes.pose(emote: string?, t: number, clock: number, calm: boolean?): Pose
	local idle = GolemEmotes.idle(clock)
	if not emote then
		return idle
	end
	local m = GolemEmotes.move(emote, t)
	return {
		Lift = idle.Lift + (if calm then 0 else m.Lift),
		Yaw = idle.Yaw + m.Yaw,
		Pitch = idle.Pitch + m.Pitch,
		Roll = idle.Roll + m.Roll,
		Right = idle.Right + m.Right,
		Left = idle.Left + m.Left,
	}
end

-- From pose `a` to pose `b`: `w` = 0 is a, 1 is b (an emote that cuts in
-- blends over a moment instead of snapping).
function GolemEmotes.mix(a: Pose, b: Pose, w: number): Pose
	local k = math.clamp(w, 0, 1)
	return {
		Lift = a.Lift + (b.Lift - a.Lift) * k,
		Yaw = a.Yaw + (b.Yaw - a.Yaw) * k,
		Pitch = a.Pitch + (b.Pitch - a.Pitch) * k,
		Roll = a.Roll + (b.Roll - a.Roll) * k,
		Right = a.Right + (b.Right - a.Right) * k,
		Left = a.Left + (b.Left - a.Left) * k,
	}
end

return GolemEmotes
