--[[
	MoveRig: puts MoveMath poses onto a rig's joint Transforms, on top of
	whatever the Animator plays (the default Animate walk / idle, a tool
	hold). Works for any R15 rig: a player's character (MoveController,
	HoverboardController) or a quest NPC later (find(model), or fromMotors
	with its own joint map).

	The joints: classic Motor6Ds, or AnimationConstraints. Roblox's Avatar
	Joint Upgrade (StarterPlayer.AvatarJointUpgrade "Default": live for every
	game since 2026-05, forced for all at the end of 2026) gives R15 player
	characters AnimationConstraints instead of Motor6Ds: same joints, the
	offsets on RigAttachments (Attachment0 / Attachment1) instead of C0 / C1,
	and the same .Transform, which the Animator resets every frame (so we
	write it in PreSimulation / Stepped, after the Animator). find() takes
	either; an AnimationConstraint is matched by its name or, failing that,
	by its Attachment1 ("<Joint>RigAttachment"). (The owner's playtest
	2026-10-28: no hoverboard pose and no emotes, because find() only
	looked for Motor6Ds.)

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
	(MoveConfig.Joints order). Layer = { Pose, Weight, Override, Mask? }:
	joints in Mask are left alone by that layer (the arms while the blaster
	fires: MoveRules.maskArms).
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)
local MoveMath = require(script.Parent.MoveMath)

-- a Motor6D or an AnimationConstraint (both have .Transform and .Parent)
export type Joint = any
export type Rig = {
	Names: { string },
	Motors: { Joint },
	Base: { [number]: CFrame },
	Written: { [number]: CFrame },
	Count: number,
}
export type Layer = {
	Pose: { [string]: CFrame },
	Weight: number,
	Override: { [string]: boolean },
	Mask: { [string]: boolean }?,
}

-- does this layer move this joint now?
local function moves(layer: Layer, name: string): boolean
	if layer.Weight <= 0 or not layer.Pose[name] then
		return false
	end
	local mask = layer.Mask
	return not (mask and mask[name])
end

local MoveRig = {}

-- the joints a character must have to count as an R15 rig
MoveRig.Required = { "Root", "Waist", "LeftShoulder", "RightShoulder" }

-- A rig from any joint name -> joint map (names as in MoveConfig.Joints).
function MoveRig.fromMotors(motors: { [string]: Joint }): Rig
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

local function isJoint(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint"))
end

-- The joint name of an AnimationConstraint: its own name, or its Attachment1's ("LeftHipRigAttachment").
local JOINT_NAMES: { [string]: boolean } = {}
for _, name in MoveConfig.Joints do
	JOINT_NAMES[name] = true
end
function MoveRig.jointName(joint: Instance): string?
	if JOINT_NAMES[joint.Name] then
		return joint.Name
	end
	local a1 = if joint:IsA("AnimationConstraint") then joint.Attachment1 else nil
	if a1 then
		local name = string.match(a1.Name, "^(.+)RigAttachment$")
		if name and JOINT_NAMES[name] then
			return name
		end
	end
	return nil
end

-- The R15 joints of a character / NPC model (nil: not R15, or not loaded yet).
function MoveRig.find(model: Instance): Rig?
	local motors: { [string]: Joint } = {}
	local missing = false
	for _, name in MoveConfig.Joints do
		local part = model:FindFirstChild(MoveConfig.JointPart[name])
		local joint = part and part:FindFirstChild(name)
		if joint and isJoint(joint) then
			motors[name] = joint
		else
			missing = true
		end
	end
	if missing then
		-- Avatar Joint Upgrade: the AnimationConstraints, wherever they sit and whatever their names
		for _, d in model:GetDescendants() do
			if d:IsA("AnimationConstraint") then
				local name = MoveRig.jointName(d)
				if name and not motors[name] then
					motors[name] = d
				end
			end
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
			if moves(layers[l], name) then
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
					if moves(layer, name) then
						result = MoveMath.layer(result, layer.Pose[name], layer.Weight, layer.Override[name] == true)
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
