--[[
	Poses a move on the R15 block rig (lib/dummy_r15) at a time, the way the
	game layers it (MoveMath.evaluate + MoveMath.layer on an Animator base),
	and measures it: the lowest point of the body (the floor) and how deep a
	hand, forearm, foot or shin goes into the torso or the head. Used by the
	emote preview (export_emotes.luau) and tests/Emotes.spec.luau.
]]

local roblox = require("@lune/roblox") :: any
local R15 = require("./dummy_r15")

local Vector3 = roblox.Vector3

local MovePose = {}

MovePose.Limbs = { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg" }
MovePose.Bodies = { "UpperTorso", "Head", "LowerTorso" }

-- part CFrames of `move` at time t (stopAt: the loop was stopped then); base(joint) = the Animator's Transform
function MovePose.solve(
	Loader: any,
	move: any,
	t: number,
	stopAt: number?,
	base: ((string) -> any)?
): ({ [string]: any }, { [string]: any })
	local MoveMath = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveMath")
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local CFrame = Loader.CFrame
	local w = MoveMath.weight(move, t, stopAt)
	local pose = MoveMath.evaluate(move, t, w, {}, stopAt)
	local overrides = MoveMath.overrides(move)
	local transforms = {}
	for _, joint in MoveConfig.Joints do
		local b = if base then base(joint) else CFrame.identity
		local cf = pose[joint]
		transforms[joint] = if cf and w > 0 then MoveMath.layer(b, cf, w, overrides[joint] == true) else b
	end
	return R15.solve(CFrame.new(0, R15.RootHeight, 0), transforms), pose
end

-- the lowest corner of any visible part: (y, part)
function MovePose.lowest(parts: { [string]: any }): (number, string)
	local low, which = math.huge, ""
	for name, info in R15.Parts do
		if not info.Hidden and parts[name] then
			local half = info.Size / 2
			for cx = -1, 1, 2 do
				for cy = -1, 1, 2 do
					for cz = -1, 1, 2 do
						local y = (parts[name] * Vector3.new(cx * half.X, cy * half.Y, cz * half.Z)).Y
						if y < low then
							low, which = y, name
						end
					end
				end
			end
		end
	end
	return low, which
end

-- how deep (studs) the inner 84 % of a limb goes into a body part: (depth, "limb in body")
function MovePose.clip(parts: { [string]: any }, limbs: { string }?, bodies: { string }?): (number, string)
	local worst, at = 0, ""
	for _, limb in limbs or MovePose.Limbs do
		local half = R15.Parts[limb].Size * 0.42
		for _, body in bodies or MovePose.Bodies do
			local size = R15.Parts[body].Size
			for cx = -1, 1, 2 do
				for cy = -1, 1, 2 do
					for cz = -1, 1, 2 do
						local p = parts[body]:PointToObjectSpace(parts[limb] * Vector3.new(cx * half.X, cy * half.Y, cz * half.Z))
						local depth = math.min(size.X / 2 - math.abs(p.X), size.Y / 2 - math.abs(p.Y), size.Z / 2 - math.abs(p.Z))
						if depth > worst then
							worst, at = depth, `{limb} in {body}`
						end
					end
				end
			end
		end
	end
	return worst, at
end

-- The times to check a loop: the intro, `loops` passes of the loop, then the outro from a stop
-- (stopped at `stopFraction` of a pass, so the outro starts from a pose in the middle of the loop).
function MovePose.timeline(move: any, loops: number, stopFraction: number?, fps: number?): { { t: number, stop: number? } }
	local step = 1 / (fps or 30)
	local from = move.LoopFrom or 0
	local stopAt = from + (move.Duration - from) * (loops + (stopFraction or 0.37))
	local outro = 0
	for _, k in move.Outro or {} do
		outro = math.max(outro, k.T)
	end
	local list = {}
	local t = 0
	while t <= stopAt + outro + 1e-9 do
		table.insert(list, { t = t, stop = if t >= stopAt then stopAt else nil })
		t += step
	end
	return list
end

return MovePose
