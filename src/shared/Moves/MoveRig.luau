--[[
	MoveRig: puts MoveMath poses onto a rig's Motor6D.Transform, on top of
	whatever the Animator plays (the default Animate walk / idle, a tool
	hold). Works for any R15 rig: a player's character (MoveController) or a
	quest NPC later (find(model), or fromMotors with its own joint map).

	Call step() every frame AFTER the Animator has written the Transforms
	(RunService.Stepped / PreSimulation). For every joint a layer touches:
	  Transform = layer(...layer(base, pose1, w1)..., poseN, wN)
	where base is the Animator's Transform of this frame. A joint the
	Animator did not write again since our last step (it still holds what
	we wrote) keeps the base we saw before, so poses never pile up frame
	after frame. A joint no layer touches any more gets its base back.
	release() does that for every joint (out of range, the move ended, the
	character is busy). No tables are made per frame; the CFrames are new
	values (Roblox CFrames are immutable).

	Rig = { Names, Motors, Base, Written, Count }: one entry per joint found
	(MoveConfig.Joints order). Layer = { Pose, Weight, Override }.
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)
local MoveMath = require(script.Parent.MoveMath)

export type Rig = {
	Names: { string },
	Motors: { Motor6D },
	Base: { [number]: CFrame },
	Written: { [number]: CFrame },
	Count: number,
}
export type Layer = {
	Pose: { [string]: CFrame },
	Weight: number,
	Override: { [string]: boolean },
}

local MoveRig = {}

-- the joints a character must have to count as an R15 rig
MoveRig.Required = { "Root", "Waist", "LeftShoulder", "RightShoulder" }

-- A rig from any joint name -> Motor6D map (names as in MoveConfig.Joints).
function MoveRig.fromMotors(motors: { [string]: Motor6D }): Rig
	local rig: Rig = { Names = {}, Motors = {}, Base = {}, Written = {}, Count = 0 }
	for _, name in MoveConfig.Joints do
		local motor = motors[name]
		if motor then
			table.insert(rig.Names, name)
			table.insert(rig.Motors, motor)
		end
	end
	rig.Count = #rig.Motors
	return rig
end

-- The R15 motors of a character / NPC model (nil: not R15, or not loaded yet).
function MoveRig.find(model: Instance): Rig?
	local motors: { [string]: Motor6D } = {}
	for _, name in MoveConfig.Joints do
		local part = model:FindFirstChild(MoveConfig.JointPart[name])
		local motor = part and part:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			motors[name] = motor
		end
	end
	for _, name in MoveRig.Required do
		if not motors[name] then
			return nil
		end
	end
	return MoveRig.fromMotors(motors)
end

-- Is every motor still in the model (a respawn or a streamed-out limb drops them)?
function MoveRig.alive(rig: Rig): boolean
	for i = 1, rig.Count do
		if not rig.Motors[i].Parent then
			return false
		end
	end
	return rig.Count > 0
end

function MoveRig.step(rig: Rig, layers: { Layer }, count: number)
	local names, motors, bases, written = rig.Names, rig.Motors, rig.Base, rig.Written
	for i = 1, rig.Count do
		local name = names[i]
		local touched = false
		for l = 1, count do
			local layer = layers[l]
			if layer.Weight > 0 and layer.Pose[name] then
				touched = true
				break
			end
		end
		local mine = written[i]
		if touched or mine then
			local motor = motors[i]
			local current = motor.Transform
			-- still what we wrote: the Animator left this joint alone, keep its old base
			local base = if mine and current == mine then bases[i] or current else current
			if touched then
				local result = base
				for l = 1, count do
					local layer = layers[l]
					local pose = layer.Pose[name]
					if pose and layer.Weight > 0 then
						result = MoveMath.layer(result, pose, layer.Weight, layer.Override[name] == true)
					end
				end
				bases[i] = base
				motor.Transform = result
				written[i] = result
			else
				-- nothing on this joint any more: give the base back if ours is still there
				if mine and current == mine then
					motor.Transform = base
				end
				bases[i] = nil
				written[i] = nil
			end
		end
	end
end

-- Every joint back to the Animator's pose (where ours is still in place).
local NO_LAYERS: { Layer } = {}
function MoveRig.release(rig: Rig)
	MoveRig.step(rig, NO_LAYERS, 0)
end

-- Does the rig hold any pose of ours right now?
function MoveRig.holding(rig: Rig): boolean
	return next(rig.Written) ~= nil
end

return MoveRig
