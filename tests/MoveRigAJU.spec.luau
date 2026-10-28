--[[
	MoveRig and Roblox's Avatar Joint Upgrade (StarterPlayer.AvatarJointUpgrade
	"Default": live since 2026-05, forced at the end of 2026): R15 player
	characters get AnimationConstraints instead of Motor6Ds. MoveRig.find must
	take them (else nothing is posed: no emotes, no hoverboard pose, the owner's
	playtest 2026-10-28), whether they are named like the joint in its part or
	sit elsewhere and are only known by their Attachment1 ("<Joint>RigAttachment").
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
	local R15 = require("../tools/lune/lib/dummy_r15")

	local function character(named: boolean, motors: boolean?): any
		local model = Instance.new("Model")
		local parts: { [string]: any } = {}
		for name in R15.Parts do
			local part = Instance.new("Part")
			part.Name = name
			part.Parent = model
			parts[name] = part
		end
		for _, j in R15.Joints do
			if motors then
				local m = Instance.new("Motor6D")
				m.Name = j.Name
				m.Part0 = parts[j.Part0]
				m.Part1 = parts[j.Part1]
				m.C0 = j.C0
				m.C1 = j.C1
				m.Parent = parts[j.Part1]
				continue
			end
			local a0 = Instance.new("Attachment")
			a0.Name = j.Name .. "RigAttachment"
			a0.CFrame = j.C0
			a0.Parent = parts[j.Part0]
			local a1 = Instance.new("Attachment")
			a1.Name = j.Name .. "RigAttachment"
			a1.CFrame = j.C1
			a1.Parent = parts[j.Part1]
			local c = Instance.new("AnimationConstraint")
			c.Name = if named then j.Name else "AnimationConstraint"
			c.Attachment0 = a0
			c.Attachment1 = a1
			c.Parent = if named then parts[j.Part1] else parts.HumanoidRootPart
		end
		return model
	end

	T.test("MoveRig: Avatar Joint Upgrade characters (AnimationConstraints) are rigs and get posed", function()
		for _, named in { true, false } do
			local rig = MoveRig.find(character(named))
			T.truthy(rig ~= nil, `an AJU character is a rig (constraints named like the joints: {named})`)
			T.eq(rig.Count, #MoveConfig.Joints, "every joint found")
			for i = 1, rig.Count do
				T.truthy(rig.Motors[i]:IsA("AnimationConstraint"), rig.Names[i] .. " is the AnimationConstraint")
				T.eq(rig.Motors[i].Attachment1.Name, rig.Names[i] .. "RigAttachment", rig.Names[i] .. " matched to its joint")
			end
			local turn = CFrame.Angles(0, 0.5, 0)
			local layers = { { Pose = { Waist = turn }, Weight = 1, Override = { Waist = true } } }
			MoveRig.step(rig, layers, 1)
			local waist = rig.Motors[table.find(rig.Names, "Waist") :: number]
			T.near(waist.Transform.LookVector:Dot(turn.LookVector), 1, 1e-6, "the pose lands on the constraint's Transform")
			MoveRig.release(rig)
			T.falsy(MoveRig.holding(rig), "given back")
		end
		-- classic Motor6D characters still work, partial rigs still wait
		local classic = MoveRig.find(character(true, true))
		T.truthy(classic ~= nil and classic.Motors[1]:IsA("Motor6D"), "Motor6D characters still work")
		local partial = character(true)
		partial.UpperTorso.Waist:Destroy()
		T.eq(MoveRig.find(partial), nil, "no Waist: not a rig yet")
		T.eq(MoveRig.jointName(Instance.new("AnimationConstraint")), nil, "an unrelated constraint is no joint")
	end)
end
