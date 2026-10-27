--[[
	MineJuiceRules: the pure rules of the mining reel's extras (Config/JuiceConfig;
	MineJuiceController and Effects/RockCracks ask them, the specs check them).
	`reduced` is UI/Motion.reduced() (the SETTINGS toggle or Roblox's own
	Reduce motion, ReduceMotionController): with it nothing new moves or
	flashes; the cracks still grow (a still change on a hit) with steady glints.

	  flare(now, last, reduced)          may a rock's glints flare again now? At
	                                     most JuiceConfig.GlintFlaresPerSecond a
	                                     second per rock, never with Reduce motion
	  chips(reduced, distance, phone)    chips one hit knocks off (0: Reduce
	                                     motion, or farther than ChipRange)
	  sparkle(reduced, distance)         the gold sparkle at a crack stage?
	  pickup(reduced, hasIcon, onScreen) what an ore entering your carry shows:
	                                     "Fly" (the icon floats up and flies in,
	                                     then the bump), "Bump" (no free icon or
	                                     the spot is off screen: the bump only),
	                                     "Quiet" (Reduce motion: no flight, no
	                                     bump, only the sound)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JuiceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("JuiceConfig"))

local MineJuiceRules = {}

export type Pickup = "Fly" | "Bump" | "Quiet"

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

-- How many chips one hit `distance` studs from the camera knocks off.
function MineJuiceRules.chips(reduced: boolean, distance: number, phone: boolean): number
	if reduced or not (distance <= JuiceConfig.ChipRange) then
		return 0
	end
	return if phone then 2 else 3
end

-- The warm gold sparkle at a crack stage `distance` studs from the camera?
function MineJuiceRules.sparkle(reduced: boolean, distance: number): boolean
	return not reduced and distance <= JuiceConfig.CrackRange
end

-- What a pickup shows (see the header).
function MineJuiceRules.pickup(reduced: boolean, hasIcon: boolean, onScreen: boolean): Pickup
	if reduced then
		return "Quiet"
	end
	return if hasIcon and onScreen then "Fly" else "Bump"
end

return MineJuiceRules
