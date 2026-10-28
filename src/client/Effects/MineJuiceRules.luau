--[[
	MineJuiceRules: the pure rules of the mining reel's extras (Config/JuiceConfig;
	MineJuiceController and Effects/RockCracks ask them, the specs check them).
	`reduced` is UI/Motion.reduced() (the SETTINGS toggle or Roblox's own
	Reduce motion, ReduceMotionController): with it nothing new moves or
	flashes; the cracks still grow (a still change on a hit) with steady glints.

	  flare(now, last, reduced)          may a rock's glints flare again now? At
	                                     most JuiceConfig.GlintFlaresPerSecond a
	                                     second per rock, never with Reduce motion
	  chips(reduced, distance, phone, hasFace)
	                                     chips one hit knocks off (0: Reduce
	                                     motion, farther than ChipRange, or no
	                                     crack face to fly from: a rock waiting
	                                     for a crack slot throws none, never
	                                     from inside the rock)
	  tryFace(now, lastTry, old)         try a new crack face? Only when your view
	                                     of the old one is below FaceDot, at most
	                                     once per KeepHit
	  betterFace(old, new)               take it? Only when it beats the old face
	                                     by FaceMargin (no jumping between
	                                     grazing shards)
	  sparkle(reduced, distance)         the gold sparkle at a crack stage?
	  pickup(reduced, hasIcon, onScreen) what an ore entering your carry shows:
	                                     "Fly" (the icon floats up and flies in,
	                                     then the bump), "Bump" (no free icon or
	                                     the spot is off screen: the bump only),
	                                     "Quiet" (Reduce motion: no flight, no
	                                     bump, only the sound)
	  evict(slots, now, incomingKept)    which cracked rock gives its parts back
	                                     for a new one (nil = none: skip the new
	                                     rock). Never your own or focused rock
	                                     (Kept), never one hit within KeepHit
	                                     seconds unless the new rock is yours
	                                     (one swap, then it stays: no thrash)
	  land(now, showing, lastFlash)      an ore lands: merge into the bump still
	                                     showing on that target (only its +N counts
	                                     up and pops again) or start a new bump; a
	                                     new bump flashes white at most once per
	                                     flareGap() (flash safety)
	  once(now, last, gap)               a sound or burst at most once per `gap`
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JuiceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("JuiceConfig"))

local MineJuiceRules = {}

export type Pickup = "Fly" | "Bump" | "Quiet"

MineJuiceRules.FaceDot = 0.3 -- your view of the crack's face below this (dot): look for a better face
MineJuiceRules.FaceMargin = 0.25 -- a new face must face you this much better (dot) to take the crack
-- A cracked rock as evict() sees it: when it was last hit, and whether it must keep its crack.
export type Slot = { HitAt: number, Kept: boolean }

-- The shortest time between two glint flares of one rock (seconds).
function MineJuiceRules.flareGap(): number
	return 1 / math.max(JuiceConfig.GlintFlaresPerSecond, 0.1)
end

-- May a rock whose glints last flared at `last` (nil = never) flare again at `now`?
function MineJuiceRules.flare(now: number, last: number?, reduced: boolean): boolean
	if reduced then
		return false
	end
	return last == nil or now - last >= MineJuiceRules.flareGap() - 1e-9
end

-- How many chips one hit `distance` studs from the camera knocks off (`hasFace`: a crack face to fly from).
function MineJuiceRules.chips(reduced: boolean, distance: number, phone: boolean, hasFace: boolean): number
	if reduced or not hasFace or not (distance <= JuiceConfig.ChipRange) then
		return 0
	end
	return if phone then 2 else 3
end

--[[
	Should a crack whose face you see at `old` (dot, 1 = straight on) try a new
	face now? Only below FaceDot and at most once per KeepHit seconds since the
	last try (`lastTry`, nil = never).
]]
function MineJuiceRules.tryFace(now: number, lastTry: number?, old: number): boolean
	return old < MineJuiceRules.FaceDot and (lastTry == nil or now - lastTry >= JuiceConfig.KeepHit - 1e-9)
end

-- Does a face seen at `new` beat the crack's face seen at `old` by FaceMargin?
function MineJuiceRules.betterFace(old: number, new: number): boolean
	return new >= old + MineJuiceRules.FaceMargin
end

-- The warm gold sparkle at a crack stage `distance` studs from the camera?
function MineJuiceRules.sparkle(reduced: boolean, distance: number): boolean
	return not reduced and distance <= JuiceConfig.CrackRange
end

--[[
	Which of `slots` gives its crack back for a new rock (the key, or nil: the
	new rock gets none this hit). `incomingKept`: the new rock is your own or
	focused one.
]]
function MineJuiceRules.evict<K>(slots: { [K]: Slot }, now: number, incomingKept: boolean): K?
	local best: K? = nil
	local bestAt = math.huge
	for key, slot in slots do
		local fresh = now - slot.HitAt < JuiceConfig.KeepHit
		if not slot.Kept and (incomingKept or not fresh) and slot.HitAt < bestAt then
			best, bestAt = key, slot.HitAt
		end
	end
	return best
end

--[[
	An ore lands on a target whose bump is `showing` (its +N still on screen):
	merge (the +N counts up and pops again: no new flash, ring or pop sound,
	however many ores come); else a new bump, which flashes white only when the
	target's last flash (`lastFlash`) is a flareGap() back. Returns (merge, flash).
]]
function MineJuiceRules.land(now: number, showing: boolean, lastFlash: number?): (boolean, boolean)
	if showing then
		return true, false
	end
	return false, MineJuiceRules.flare(now, lastFlash, false)
end

-- Something that should happen at most once per `gap` seconds (last = nil: never yet).
function MineJuiceRules.once(now: number, last: number?, gap: number): boolean
	return last == nil or now - last >= gap - 1e-9
end

-- What a pickup shows (see the header).
function MineJuiceRules.pickup(reduced: boolean, hasIcon: boolean, onScreen: boolean): Pickup
	if reduced then
		return "Quiet"
	end
	return if hasIcon and onScreen then "Fly" else "Bump"
end

return MineJuiceRules
