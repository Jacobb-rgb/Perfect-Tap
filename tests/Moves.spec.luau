--[[
	The player's procedural moves (owner 2026-10-21): MoveConfig's data
	(every move, joint, key and ease valid, sane durations), MoveMath
	(keyframes, easing, loops, blend weights, the 360 spin that never
	unwinds, layering), MoveRig on fake motors (no pile-up when the Animator
	skips a joint, the base given back), the poses on an R15 block rig (no
	hand or forearm through the body, the feet never deep in the floor),
	MoveRules (the attribute format, the whitelist, loops, blocks,
	celebrations), MoveService (whitelist, Guard, MinGap, the attribute,
	the Net rate limit, the celebration hooks), and the integrator's rules
	for MoveController (one Stepped loop, no new input bindings, the one-line
	Throw hook).
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance, Vector3 = roblox.Instance, roblox.Vector3
	local CFrame = Loader.CFrame
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local MoveMath = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveMath")
	local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
	local MoveRules = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRules")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local R15 = require("../tools/lune/lib/dummy_r15")

	local DEG = math.pi / 180
	local JOINTS: { [string]: boolean } = {}
	for _, name in MoveConfig.Joints do
		JOINTS[name] = true
	end

	-- the rotation angle (radians) between two CFrames
	local function angleBetween(a: any, b: any): number
		local _, angle = (a:Inverse() * b):ToAxisAngle()
		return math.abs(angle)
	end
	local function near(a: any, b: any, degrees: number, studs: number?): boolean
		return angleBetween(a, b) <= degrees * DEG and (a.Position - b.Position).Magnitude <= (studs or 1e-3)
	end

	---------------------------------------------------------------- MoveConfig

	T.test("moves: every move is listed, named, valid and sanely timed", function()
		local listed: { [string]: boolean } = {}
		for _, name in MoveConfig.List do
			listed[name] = true
			T.truthy(MoveConfig.Moves[name], name .. " exists")
		end
		for _, name in { "Carry", "Throw", "Recoil", "Spray", "Celebrate", "BigCelebrate", "CashToss" } do
			T.truthy(listed[name], name .. " is one of the moves (owner's list)")
		end
		T.eq(MoveConfig.Moves.Hammer, nil, "the Foundry's Hammer went with the Foundry (owner 2026-10-24)")
		for name, move in MoveConfig.Moves do
			T.truthy(listed[name], name .. " is in MoveConfig.List")
			T.eq(move.Name, name, name .. " name")
			T.truthy(move.Slot == "Loop" or move.Slot == "Action" or move.Slot == "Kick", name .. " slot")
			T.eq(move.Loop, move.Slot == "Loop", name .. ": loops (and only loops) use the Loop slot")
			T.truthy(move.Duration >= 0.1 and move.Duration <= 2, name .. " lasts 0.1..2 s")
			T.truthy(move.BlendIn >= 0 and move.BlendOut >= 0, name .. " blend times")
			if not move.Loop then
				T.le(move.BlendIn + move.BlendOut, move.Duration, name .. ": the blends fit in the move")
			end
			T.truthy(move.MinGap >= 0 and move.MinGap <= 2, name .. " MinGap")
			T.truthy(type(move.Priority) == "number" and move.Priority >= 0, name .. " Priority")
			for _, joint in move.Override do
				T.truthy(JOINTS[joint], `{name}: Override joint {joint} is an R15 joint`)
			end
			T.truthy(#move.Keys >= 2, name .. " has keys")
			T.eq(move.Keys[1].T, 0, name .. ": the first key is at 0")
			local last = -1
			for i, key in move.Keys do
				T.truthy(key.T > last, `{name} key {i}: times rise`)
				last = key.T
				T.truthy(key.Ease == nil or MoveMath.Eases[key.Ease] ~= nil, `{name} key {i}: ease {tostring(key.Ease)}`)
				for joint, euler in key.Pose or {} do
					T.truthy(JOINTS[joint], `{name} key {i}: {joint} is an R15 joint`)
					T.eq(#euler, 3, `{name} key {i} {joint}: x, y, z`)
					for _, v in euler do
						T.truthy(type(v) == "number" and v == v and math.abs(v) <= 400, `{name} key {i} {joint}: a sane angle`)
					end
				end
				if key.Offset then
					T.eq(#key.Offset, 3, `{name} key {i}: offset x, y, z`)
					T.truthy(math.abs(key.Offset[2]) <= 1.6, `{name} key {i}: a hop of at most 1.6 studs`)
				end
			end
			if move.Loop then
				T.lt(last, move.Duration, name .. ": a loop's last key comes before it wraps")
			else
				T.eq(last, move.Duration, name .. ": a one-shot's last key is its end")
			end
		end
		-- the owner's timings
		T.near(MoveConfig.Moves.Throw.Duration, 0.45, 0.05, "Throw about 0.45 s")
		T.near(MoveConfig.Moves.Recoil.Duration, 0.12, 0.02, "Recoil about 0.12 s")
		T.near(MoveConfig.Moves.Celebrate.Duration, 1.2, 0.1, "Celebrate about 1.2 s")
		T.near(MoveConfig.Moves.BigCelebrate.Duration, 1.6, 0.1, "BigCelebrate about 1.6 s")
		T.near(MoveConfig.Moves.CashToss.Duration, 0.9, 0.1, "CashToss about 0.9 s")
		T.eq(MoveConfig.Moves.Recoil.Slot, "Kick", "Recoil adds on top")
		T.eq(#MoveConfig.Moves.Recoil.Override, 0, "Recoil overrides nothing (additive)")
		for _, joint in MoveConfig.Moves.Carry.Override do
			T.falsy(joint:find("Hip") or joint:find("Knee") or joint:find("Ankle"), "Carry leaves the legs walking: " .. joint)
		end
		T.truthy(MoveConfig.Range <= 70, "moves only within ~70 studs (phones)")
	end)

	T.test("moves: one-shots start and end at rest, loops wrap seamlessly", function()
		for name, move in MoveConfig.Moves do
			if move.Loop then
				local a = MoveMath.evaluate(move, 0, 1, {})
				local b = MoveMath.evaluate(move, move.Duration - 1e-4, 1, {})
				for joint, cf in a do
					T.truthy(near(cf, b[joint], 0.5, 0.01), `{name} {joint} wraps without a jump`)
				end
			else
				for _, t in { 0, move.Duration } do
					local pose = MoveMath.evaluate(move, t, 1, {})
					for joint, cf in pose do
						T.truthy(near(cf, CFrame.identity, 0.01, 1e-4), `{name} {joint} at rest at t={t}`)
					end
				end
			end
		end
	end)

	---------------------------------------------------------------- MoveMath

	T.test("moves: easing curves", function()
		for name, fn in MoveMath.Eases do
			T.near(fn(0), 0, 1e-9, name .. "(0)")
			T.near(fn(1), 1, 1e-9, name .. "(1)")
		end
		for _, name in { "Linear", "In", "Out", "InOut", "Sine" } do
			local fn = MoveMath.Eases[name]
			local last = -1
			for i = 0, 20 do
				local v = fn(i / 20)
				T.truthy(v >= last - 1e-9, name .. " never goes back")
				last = v
			end
		end
		T.near(MoveMath.Eases.InOut(0.5), 0.5, 1e-9, "InOut half way")
		T.near(MoveMath.Eases.Sine(0.5), 0.5, 1e-9, "Sine half way")
		T.lt(MoveMath.Eases.In(0.5), 0.5, "In starts slow")
		T.lt(0.5, MoveMath.Eases.Out(0.5), "Out starts fast")
		local peak = 0
		for i = 0, 50 do
			peak = math.max(peak, MoveMath.Eases.Back(i / 50))
		end
		T.truthy(peak > 1.05, "Back pops past the key")
		T.eq(MoveMath.ease("Nope", 0.5), MoveMath.Eases.InOut(0.5), "an unknown ease is InOut")
		T.eq(MoveMath.ease("Linear", 2), 1, "clamped")
	end)

	-- a small move of our own: MoveMath works for any move table (quest NPCs later)
	local probe = {
		Name = "Probe",
		Duration = 1,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.1,
		BlendOut = 0.2,
		Override = { "RightShoulder" },
		MinGap = 0,
		Keys = {
			{ T = 0, Pose = {} },
			{ T = 0.5, Ease = "Linear", Pose = { RightShoulder = { 90, 0, 0 }, Root = { 0, 180, 0 } }, Offset = { 0, 1, 0 } },
			{ T = 1, Ease = "Linear", Pose = { Root = { 0, 360, 0 } } },
		},
	}

	T.test("moves: keyframes interpolate per angle with the key's ease", function()
		local pose, offset = MoveMath.evaluate(probe, 0.5, 1, {})
		T.truthy(near(pose.RightShoulder, CFrame.Angles(90 * DEG, 0, 0), 0.01), "at the key: the key's pose")
		T.near(offset.Y, 1, 1e-6, "the Root offset at the key")
		T.near(pose.Root.Position.Y, 1, 1e-6, "the offset is in the Root's CFrame")
		local quarter = MoveMath.evaluate(probe, 0.25, 1, {})
		T.truthy(near(quarter.RightShoulder, CFrame.Angles(45 * DEG, 0, 0), 0.01), "linear half way: 45 degrees")
		T.near(quarter.Root.Position.Y, 0.5, 1e-6, "the offset half way")
		-- 180 -> 360 on the Root is a real turn, not the short way back
		local spin = MoveMath.evaluate(probe, 0.75, 1, {})
		local _, yaw = spin.Root:ToEulerAnglesYXZ()
		T.near(math.abs(yaw), 90 * DEG, 0.01, "270 degrees of spin (= -90)")
		-- the segment helper
		local a, b, alpha = MoveMath.segment(probe, 0.75)
		T.eq(a, 2, "segment from key 2")
		T.eq(b, 3, "to key 3")
		T.near(alpha, 0.5, 1e-9, "half way")
		local first = MoveMath.segment(probe, -1)
		T.eq(first, 1, "before the start: key 1")
		local _, lastKey = MoveMath.segment(probe, 5)
		T.eq(lastKey, 3, "after the end: the last key")
		-- weight scales the whole pose
		local half = MoveMath.evaluate(probe, 0.5, 0.5, {})
		T.truthy(near(half.RightShoulder, CFrame.Angles(45 * DEG, 0, 0), 0.01), "weight 0.5: half the angle")
		T.near(half.Root.Position.Y, 0.5, 1e-6, "weight 0.5: half the hop")
		-- the out table is reused
		local out = {}
		local got = MoveMath.evaluate(probe, 0.3, 1, out)
		T.eq(got, out, "evaluate fills the given table")
	end)

	T.test("moves: blend weights fade in and out (one-shots and loops)", function()
		T.eq(MoveMath.weight(probe, -0.1), 0, "before it starts")
		T.eq(MoveMath.weight(probe, 0), 0, "fades in from 0")
		T.near(MoveMath.weight(probe, 0.1), 1, 1e-9, "full after BlendIn")
		T.near(MoveMath.weight(probe, 0.5), 1, 1e-9, "full in the middle")
		T.truthy(MoveMath.weight(probe, 0.9) < 1, "fading out in the last BlendOut")
		T.eq(MoveMath.weight(probe, 1), 0, "gone at the end")
		T.falsy(MoveMath.done(probe, 0.99), "not done before the end")
		T.truthy(MoveMath.done(probe, 1), "done at the end")
		local carry = MoveConfig.Moves.Carry
		T.near(MoveMath.weight(carry, 100), 1, 1e-9, "a loop stays on")
		T.falsy(MoveMath.done(carry, 100), "a running loop is never done")
		T.near(MoveMath.weight(carry, 5, 5), 1, 1e-9, "stopped now: still full")
		local mid = MoveMath.weight(carry, 5 + carry.BlendOut / 2, 5)
		T.truthy(mid > 0 and mid < 1, "fading out after the stop")
		T.eq(MoveMath.weight(carry, 5 + carry.BlendOut, 5), 0, "gone BlendOut after the stop")
		T.truthy(MoveMath.done(carry, 5 + carry.BlendOut, 5), "a stopped loop is done after BlendOut")
		local last = 1
		for i = 0, 10 do
			local w = MoveMath.weight(carry, 5 + carry.BlendOut * i / 10, 5)
			T.truthy(w <= last + 1e-9, "the fade only goes down")
			last = w
		end
	end)

	T.test("moves: the BigCelebrate spin is a full turn and never unwinds while it fades", function()
		local move = MoveConfig.Moves.BigCelebrate
		local yaws = {}
		for i = 0, 32 do
			local pose = MoveMath.evaluate(move, move.Duration * i / 32, 1, {})
			local look = pose.Root.LookVector
			table.insert(yaws, math.atan2(-look.X, -look.Z))
		end
		-- the body faces every way once: the yaw passes behind (|yaw| near 180)
		local behind = false
		for _, yaw in yaws do
			if math.abs(yaw) > 150 * DEG then
				behind = true
			end
		end
		T.truthy(behind, "the spin turns the back to the camera on the way round")
		-- while it fades out, the turn left is small (the short way, not 360 back)
		for i = 0, 10 do
			local t = move.Duration - move.BlendOut + move.BlendOut * i / 10
			local w = MoveMath.weight(move, t)
			local pose = MoveMath.evaluate(move, t, w, {})
			local look = pose.Root.LookVector
			T.truthy(math.abs(math.atan2(-look.X, -look.Z)) < 20 * DEG, "facing forward while fading, t=" .. t)
		end
		T.truthy(math.abs(MoveMath.wrap(2 * math.pi)) < 1e-9, "360 wraps to 0")
		T.near(MoveMath.wrap(1.5 * math.pi), -0.5 * math.pi, 1e-9, "270 wraps to -90")
	end)

	T.test("moves: layer adds on top or overrides by weight", function()
		local base = CFrame.Angles(0.3, 0, 0)
		local pose = CFrame.Angles(0, 0, 0.5)
		T.truthy(near(MoveMath.layer(base, pose, 1, false), base * pose, 1e-4), "add: base * pose")
		T.truthy(near(MoveMath.layer(base, pose, 1, true), pose, 1e-4), "override at full weight: only the pose")
		T.truthy(near(MoveMath.layer(base, CFrame.identity, 0, true), base, 1e-4), "override at 0: the base")
		local mid = MoveMath.layer(base, CFrame.identity, 0.5, true)
		T.near(angleBetween(mid, CFrame.identity), 0.15, 1e-3, "override half way: half the base")
		local overrides = MoveMath.overrides(MoveConfig.Moves.Carry)
		T.truthy(overrides.RightShoulder and overrides.LeftElbow, "Carry overrides the arms")
		T.falsy(overrides.Waist, "Carry adds the lean on top")
	end)

	---------------------------------------------------------------- MoveRig

	local function fakeMotors(): { [string]: any }
		local motors = {}
		for _, name in MoveConfig.Joints do
			motors[name] = { Transform = CFrame.identity, Parent = true, Name = name }
		end
		return motors
	end

	T.test("moves: MoveRig layers on the Animator's pose and never piles up", function()
		local motors = fakeMotors()
		local rig = MoveRig.fromMotors(motors)
		T.eq(rig.Count, #MoveConfig.Joints, "every joint")
		local kickPose = { RightShoulder = CFrame.Angles(0.2, 0, 0) }
		local layers = { { Pose = kickPose, Weight = 1, Override = {} } }
		local walk = CFrame.Angles(-0.4, 0, 0)
		motors.RightShoulder.Transform = walk -- the Animator's frame
		MoveRig.step(rig, layers, 1)
		T.truthy(near(motors.RightShoulder.Transform, walk * kickPose.RightShoulder, 1e-3), "added on the walk")
		T.truthy(MoveRig.holding(rig), "holding a pose")
		-- the Animator skipped this joint: the next step keeps the old base (no 2x kick)
		MoveRig.step(rig, layers, 1)
		T.truthy(near(motors.RightShoulder.Transform, walk * kickPose.RightShoulder, 1e-3), "no pile-up")
		-- the Animator wrote a new frame
		local walk2 = CFrame.Angles(0.4, 0, 0)
		motors.RightShoulder.Transform = walk2
		MoveRig.step(rig, layers, 1)
		T.truthy(near(motors.RightShoulder.Transform, walk2 * kickPose.RightShoulder, 1e-3), "on the new frame")
		-- the layer is gone: the base comes back where ours is still in place
		layers[1].Weight = 0
		MoveRig.step(rig, layers, 1)
		T.truthy(near(motors.RightShoulder.Transform, walk2, 1e-3), "the base given back")
		T.falsy(MoveRig.holding(rig), "nothing held")
		-- release never overwrites a frame the Animator wrote since
		layers[1].Weight = 1
		MoveRig.step(rig, layers, 1)
		local walk3 = CFrame.Angles(0.1, 0.1, 0)
		motors.RightShoulder.Transform = walk3
		MoveRig.release(rig)
		T.truthy(near(motors.RightShoulder.Transform, walk3, 1e-3), "the Animator's newer frame stays")
		-- an untouched joint is never written
		T.eq(motors.LeftKnee.Transform, CFrame.identity, "the legs are left alone")
	end)

	T.test("moves: MoveRig overrides and stacks layers in slot order", function()
		local motors = fakeMotors()
		local rig = MoveRig.fromMotors(motors)
		local carry = { Pose = { LeftShoulder = CFrame.Angles(1.2, 0, 0) }, Weight = 1, Override = { LeftShoulder = true } }
		local throw = { Pose = { LeftShoulder = CFrame.Angles(2.5, 0, 0) }, Weight = 1, Override = { LeftShoulder = true } }
		local swing = CFrame.Angles(-0.5, 0, 0)
		motors.LeftShoulder.Transform = swing
		MoveRig.step(rig, { carry, throw }, 2)
		T.truthy(near(motors.LeftShoulder.Transform, CFrame.Angles(2.5, 0, 0), 1e-3), "the action over the loop, the walk swing gone")
		motors.LeftShoulder.Transform = swing
		throw.Weight = 0
		MoveRig.step(rig, { carry, throw }, 2)
		T.truthy(near(motors.LeftShoulder.Transform, CFrame.Angles(1.2, 0, 0), 1e-3), "the loop alone")
	end)

	T.test("moves: MoveRig finds R15 motors and skips R6", function()
		local model = Instance.new("Model")
		for _, name in MoveConfig.Joints do
			local part = model:FindFirstChild(MoveConfig.JointPart[name])
			if not part then
				part = Instance.new("Part")
				part.Name = MoveConfig.JointPart[name]
				part.Parent = model
			end
			local motor = Instance.new("Motor6D")
			motor.Name = name
			motor.Parent = part
		end
		local rig = MoveRig.find(model)
		T.truthy(rig, "an R15 rig")
		T.eq(rig.Count, #MoveConfig.Joints, "all 15 joints")
		T.eq(rig.Names[1], "Root", "parents first")
		local r6 = Instance.new("Model")
		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Parent = r6
		local shoulder = Instance.new("Motor6D")
		shoulder.Name = "Right Shoulder"
		shoulder.Parent = torso
		T.eq(MoveRig.find(r6), nil, "R6: no rig")
		-- a partly loaded R15 (no Waist yet) waits
		model:FindFirstChild("UpperTorso"):FindFirstChild("Waist"):Destroy()
		T.eq(MoveRig.find(model), nil, "no Waist: not yet")
	end)

	---------------------------------------------------------------- the poses on an R15 rig

	-- every move sampled at 30 fps on the R15 block rig (tool hold under Recoil)
	T.test("moves: no hand or forearm through the body, feet never deep in the floor", function()
		local rootCF = CFrame.new(0, R15.RootHeight, 0)
		for name, move in MoveConfig.Moves do
			local length = if move.Loop then move.Duration * 2 else move.Duration
			local worst, worstAt = 0, ""
			local lowestFoot = math.huge
			for f = 0, math.floor(length * 30) do
				local t = f / 30
				local w = MoveMath.weight(move, t)
				local pose = MoveMath.evaluate(move, t, w, {})
				local overrides = MoveMath.overrides(move)
				local transforms = {}
				for _, joint in MoveConfig.Joints do
					local base = if name == "Recoil" and joint == "RightShoulder" then CFrame.Angles(90 * DEG, 0, 0) else CFrame.identity
					local cf = pose[joint]
					transforms[joint] = if cf then MoveMath.layer(base, cf, w, overrides[joint] == true) else base
				end
				local parts = R15.solve(rootCF, transforms)
				for _, limb in { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" } do
					local half = R15.Parts[limb].Size * 0.42
					for _, body in { "UpperTorso", "Head", "LowerTorso" } do
						local size = R15.Parts[body].Size
						for cx = -1, 1, 2 do
							for cy = -1, 1, 2 do
								for cz = -1, 1, 2 do
									local p =
										parts[body]:PointToObjectSpace(parts[limb] * Vector3.new(cx * half.X, cy * half.Y, cz * half.Z))
									local depth =
										math.min(size.X / 2 - math.abs(p.X), size.Y / 2 - math.abs(p.Y), size.Z / 2 - math.abs(p.Z))
									if depth > worst then
										worst, worstAt = depth, `t={t} {limb} in {body}`
									end
								end
							end
						end
					end
				end
				for _, foot in { "LeftFoot", "RightFoot" } do
					local size = R15.Parts[foot].Size
					for cx = -1, 1, 2 do
						for cz = -1, 1, 2 do
							local p = parts[foot] * Vector3.new(cx * size.X / 2, -size.Y / 2, cz * size.Z / 2)
							lowestFoot = math.min(lowestFoot, p.Y)
						end
					end
				end
			end
			T.le(worst, 0.1, `{name}: limbs stay out of the body ({worstAt})`)
			T.truthy(lowestFoot > -0.35, `{name}: the feet stay on the floor (lowest {lowestFoot})`)
		end
	end)

	---------------------------------------------------------------- MoveRules

	T.test("moves: the Move attribute format", function()
		T.eq(MoveRules.encode("Throw", 7), "Throw:7", "encode")
		local name, seq = MoveRules.decode("BigCelebrate:42")
		T.eq(name, "BigCelebrate", "decode name")
		T.eq(seq, 42, "decode seq")
		for _, bad in { "Throw", "Throw:", ":1", "Throw:-1", "Throw:1:2", "throw:1", "Nope:1", "Throw:1 ", "", 12, true } do
			T.eq(MoveRules.decode(bad), nil, "rejects " .. tostring(bad))
		end
		T.eq(MoveRules.decode(string.rep("A", 60) .. ":1"), nil, "rejects long strings")
		T.eq(MoveRules.nextSeq(0), 1, "first seq")
		T.eq(MoveRules.nextSeq(MoveRules.MaxSeq), 1, "wraps")
		for name in MoveConfig.Moves do
			local back = MoveRules.decode(MoveRules.encode(name, 3))
			T.eq(back, name, name .. " round trip")
		end
	end)

	T.test("moves: the client whitelist, gaps, loops, blocks, range, Reduce Motion", function()
		for _, name in { "Throw", "Wave", "Shrug" } do
			T.truthy(MoveRules.clientAllowed(name), name .. " a client may ask for")
		end
		for _, name in { "Celebrate", "BigCelebrate", "CashToss", "Recoil", "Carry", "Spray", "Hammer", "throw", "", 1, nil } do
			T.falsy(MoveRules.clientAllowed(name), tostring(name) .. " only the server plays")
		end
		for name in MoveConfig.ClientMoves do
			local move = MoveConfig.Moves[name]
			T.truthy(move and not move.Loop, name .. ": client moves are one-shots")
			T.falsy(name:find("Celebrate") or name == "CashToss", name .. ": celebrations stay server-set")
		end
		local moves = MoveConfig.Moves
		T.truthy(MoveRules.replaces(nil, false, moves.Shrug), "a free slot")
		T.falsy(MoveRules.replaces(moves.BigCelebrate, false, moves.Shrug), "a shrug never cuts a celebration")
		T.falsy(MoveRules.replaces(moves.Throw, false, moves.Wave), "nor a throw")
		T.truthy(MoveRules.replaces(moves.BigCelebrate, true, moves.Shrug), "a finished move frees the slot")
		T.truthy(MoveRules.replaces(moves.Celebrate, false, moves.Throw), "the throw input wins")
		T.truthy(MoveRules.replaces(moves.Throw, false, moves.BigCelebrate), "a celebration is never lost to a throw")
		T.truthy(MoveRules.canPlay(nil, 0, 1), "the first time")
		T.falsy(MoveRules.canPlay(10, 10.5, 1), "within MinGap")
		T.truthy(MoveRules.canPlay(10, 11, 1), "after MinGap")
		T.eq(MoveRules.loopFor(2, nil), "Carry", "carrying")
		T.eq(MoveRules.loopFor(0, nil), nil, "empty hands")
		T.eq(MoveRules.loopFor(2, "Spray"), "Spray", "the server's loop first")
		T.eq(MoveRules.loopFor(0, "Hammer"), nil, "no Hammer loop (no Foundry)")
		T.eq(MoveRules.loopFor(1, "Throw"), "Carry", "a one-shot name is no loop")
		T.eq(MoveRules.loopFor(0 / 0, "Nope"), nil, "NaN carry, unknown loop")
		T.eq(MoveRules.loopFor("3", nil), nil, "a string count is no count")
		for _, state in { "Seated", "Swimming", "Climbing", "Ragdoll", "FallingDown", "Physics", "Dead", "PlatformStanding" } do
			T.truthy(MoveRules.blocked(state, false, false, false, 100), state .. " blocks")
		end
		for _, state in { "Running", "RunningNoPhysics", "Jumping", "Freefall", "Landed", nil } do
			T.falsy(MoveRules.blocked(state, false, false, false, 100), tostring(state) .. " lets moves play")
		end
		T.truthy(MoveRules.blocked("Running", true, false, false, 100), "sitting")
		T.truthy(MoveRules.blocked("Running", false, true, false, 100), "on a hoverboard")
		T.truthy(MoveRules.blocked("Running", false, false, true, 100), "in a close-up")
		T.truthy(MoveRules.blocked("Running", false, false, false, 0), "dead")
		T.truthy(MoveRules.visible(20, true), "near and on screen")
		T.falsy(MoveRules.visible(20, false), "off screen")
		T.falsy(MoveRules.visible(MoveConfig.Range + 1, true), "too far")
		T.falsy(MoveRules.visible(0 / 0, true), "NaN distance")
		T.eq(MoveRules.substitute("BigCelebrate", true), "CelebrateCalm", "Reduce Motion: no spin jump")
		T.eq(MoveRules.substitute("BigCelebrate", false), "BigCelebrate", "the full move otherwise")
		T.eq(MoveRules.substitute("Throw", true), "Throw", "the rest stays")
	end)

	local function oreOf(rarity: string): string
		for id, ore in OreData.ById do
			if ore.Rarity == rarity then
				return id
			end
		end
		error("no " .. rarity .. " ore")
	end
	local function golemOf(rarity: string): string
		for id, golem in GolemConfig.ById do
			if golem.Rarity == rarity then
				return id
			end
		end
		error("no " .. rarity .. " golem")
	end

	T.test("moves: which result earns which celebration", function()
		T.eq(MoveRules.forClean("Legendary", "Clean", false), "BigCelebrate", "Legendary ore")
		T.eq(MoveRules.forClean("Mythic", "Rough", false), "BigCelebrate", "Mythic ore")
		T.eq(MoveRules.forClean("Common", "Clean", true), "Celebrate", "a new ore")
		T.eq(MoveRules.forClean("Rare", "Flawless", false), "Celebrate", "Flawless")
		T.eq(MoveRules.forClean("Epic", "Pristine", false), nil, "an old ore, not Flawless")
		T.eq(MoveRules.forClean(nil, "Clean", false), nil, "unknown ore")
		T.eq(MoveRules.forCapsule({ "Common", "Rare" }), nil, "no big golem")
		T.eq(MoveRules.forCapsule({ "Common", "Mythic" }), "BigCelebrate", "a Mythic among them")
		T.eq(MoveRules.forCapsule({ "Legendary" }), "BigCelebrate", "Legendary")
		T.eq(MoveRules.forProgress(nil, { Blaster = 5, Rebirths = 0 }), nil, "just loaded")
		T.eq(MoveRules.forProgress({ Blaster = 4, Rebirths = 0 }, { Blaster = 5, Rebirths = 0 }), "BigCelebrate", "a new blaster level")
		T.eq(MoveRules.forProgress({ Blaster = 10, Rebirths = 1 }, { Blaster = 1, Rebirths = 2 }), "BigCelebrate", "a rebirth")
		T.eq(MoveRules.forProgress({ Blaster = 5, Rebirths = 0 }, { Blaster = 5, Rebirths = 0 }), nil, "nothing new")
		T.eq(MoveRules.forProgress({ Blaster = 5, Rebirths = 0 }, { Blaster = 4, Rebirths = 0 }), nil, "lower")
		T.truthy(MoveRules.bigSell(MoveConfig.BigSell.Items), "a big sale")
		T.falsy(MoveRules.bigSell(MoveConfig.BigSell.Items - 1), "a small sale")
		-- the data the rules read
		T.truthy(OreData.ById[oreOf("Legendary")] and GolemConfig.ById[golemOf("Mythic")], "rarities exist")
	end)

	---------------------------------------------------------------- MoveService

	local MoveService = Loader.requirePath("ServerScriptService.Server.Services.MoveService")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Players = Loader.game:GetService("Players")

	local function fakeCharacter(alive: boolean): any
		local attributes = {}
		local humanoid = { Health = if alive then 100 else 0 }
		local root = { Position = Vector3.new(0, 3, 0) }
		local character: any = { Parent = true, Attributes = attributes }
		function character.GetAttribute(_, key: string)
			return attributes[key]
		end
		function character.SetAttribute(_, key: string, value: any)
			attributes[key] = value
		end
		function character.FindFirstChildOfClass(_, class: string)
			return if class == "Humanoid" then humanoid else nil
		end
		function character.FindFirstChild(_, name: string)
			return if name == "HumanoidRootPart" then root else nil
		end
		return character
	end
	local function fakePlayer(name: string, alive: boolean?): any
		local attributes = {}
		local player: any = { Name = name, UserId = #name, Parent = Players, Character = fakeCharacter(alive ~= false) }
		function player.GetAttribute(_, key: string)
			return attributes[key]
		end
		function player.SetAttribute(_, key: string, value: any)
			attributes[key] = value
		end
		return player
	end
	local function moveOf(player: any): string?
		return player.Character:GetAttribute(MoveConfig.Attribute)
	end

	local function withService(name: string, fn: (now: { value: number }) -> ())
		T.test(name, function()
			local now = { value = 100 }
			MoveService._test.reset()
			MoveService._test.setClock(function()
				return now.value
			end)
			-- (the moves as they work when the owner switches them on: AnimConfig.PlayerMoves)
			local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")
			local was = AnimConfig.PlayerMoves
			AnimConfig.PlayerMoves = true
			local ok, err = pcall(fn, now)
			AnimConfig.PlayerMoves = was
			MoveService._test.reset()
			if not ok then
				error(err, 0)
			end
		end)
	end

	withService("moves: MoveService plays only whitelisted client moves, with Guard and MinGap", function(now)
		local test = MoveService._test
		local p = fakePlayer("Mover")
		for _, bad in
			{
				"Celebrate",
				"BigCelebrate",
				"CashToss",
				"Recoil",
				"Carry",
				"Spray",
				"Hammer",
				"Nope",
				12,
				{},
				true,
				nil,
				string.rep("W", 200),
			}
		do
			test.onMove(p, bad)
			T.eq(moveOf(p), nil, "refused: " .. tostring(bad))
		end
		test.onMove(p, "Throw")
		T.eq(moveOf(p), nil, "Throw needs something in your hands")
		p:SetAttribute(MoveConfig.CarryAttribute, 2)
		test.onMove(p, "Throw")
		T.eq(moveOf(p), "Throw:1", "Throw while carrying")
		test.onMove(p, "Wave")
		T.eq(moveOf(p), "Wave:2", "Wave, the next seq")
		now.value += 0.1
		test.onMove(p, "Wave")
		T.eq(moveOf(p), "Wave:2", "the same move within its MinGap: refused")
		now.value += MoveConfig.Moves.Wave.MinGap
		test.onMove(p, "Wave")
		T.eq(moveOf(p), "Wave:3", "after the gap")
		local name, seq = MoveRules.decode(moveOf(p))
		T.eq(name, "Wave", "the attribute decodes")
		T.eq(seq, 3, "with its seq")
		local dead = fakePlayer("Ghost", false)
		test.onMove(dead, "Shrug")
		T.eq(moveOf(dead), nil, "no move without a living character")
		local gone = fakePlayer("Gone")
		gone.Character = nil
		T.falsy(MoveService.play(gone, "Celebrate"), "no character, no move")
		T.falsy(MoveService.play(p, "Carry"), "loops never go through play()")
		T.falsy(MoveService.play(p, "Nope"), "unknown")
		MoveService.setLoop(p, "Spray")
		T.eq(p.Character:GetAttribute(MoveConfig.LoopAttribute), "Spray", "the loop attribute")
		MoveService.setLoop(p, "Throw")
		T.eq(p.Character:GetAttribute(MoveConfig.LoopAttribute), nil, "a one-shot is no loop")
		MoveService.setLoop(p, nil)
		T.eq(p.Character:GetAttribute(MoveConfig.LoopAttribute), nil, "cleared")
	end)

	withService("moves: MoveService celebrations from the existing hooks", function(now)
		local test = MoveService._test
		local p = fakePlayer("Lucky")
		test.onCleaned(p, oreOf("Common"), "Clean", 0.5)
		T.eq(moveOf(p), nil, "an old Common ore: nothing")
		test.onDiscovered(p, oreOf("Common"))
		test.onCleaned(p, oreOf("Common"), "Clean", 0.5)
		T.eq(moveOf(p), "Celebrate:1", "a new ore")
		now.value += 5
		test.onCleaned(p, oreOf("Rare"), "Flawless", 1)
		T.eq(moveOf(p), "Celebrate:2", "Flawless")
		now.value += 5
		test.onCleaned(p, oreOf("Legendary"), "Rough", 0.2)
		T.eq(moveOf(p), "BigCelebrate:3", "Legendary ore")
		now.value += 5
		test.onDiscovered(p, oreOf("Epic"))
		now.value += MoveService.FreshSeconds + 1
		test.onCleaned(p, oreOf("Epic"), "Clean", 0.5)
		T.eq(moveOf(p), "BigCelebrate:3", "a discovery long ago (an Auto Cleaner) is not this clean")
		test.onOpened(p, { Capsule = "Test", Count = 1, Kinds = { golemOf("Common") }, Lucky = false, Source = "Coins" })
		T.eq(moveOf(p), "BigCelebrate:3", "a Common golem: nothing")
		test.onOpened(p, { Capsule = "Test", Count = 3, Kinds = { golemOf("Common"), golemOf("Mythic") }, Lucky = false, Source = "Coins" })
		T.eq(moveOf(p), "BigCelebrate:4", "a Mythic golem")
		-- the save: a new blaster level, then a rebirth
		local data = { BlasterLevel = 3, Rebirths = 0 }
		local original = rawget(DataService, "get")
		rawset(DataService, "get", function()
			return data
		end)
		local ok, err = pcall(function()
			test.onLoaded(p, data)
			test.onChanged(p)
			T.eq(moveOf(p), "BigCelebrate:4", "a save change with nothing new")
			now.value += 5
			data.BlasterLevel = 4
			test.onChanged(p)
			T.eq(moveOf(p), "BigCelebrate:5", "forged / bought the next blaster")
			now.value += 5
			data.BlasterLevel = 1
			data.Rebirths = 1
			test.onChanged(p)
			T.eq(moveOf(p), "BigCelebrate:6", "a rebirth")
		end)
		rawset(DataService, "get", original)
		if not ok then
			error(err, 0)
		end
		-- a big sale at Tobin's
		local atStall = true
		test.setCounterCheck(function()
			return atStall
		end)
		for _ = 1, MoveConfig.BigSell.Items - 1 do
			test.onSold(p, {}, 10)
		end
		test.flushSell(p)
		T.eq(moveOf(p), "BigCelebrate:6", "a small sale: nothing")
		for _ = 1, MoveConfig.BigSell.Items do
			test.onSold(p, {}, 10)
		end
		test.flushSell(p)
		T.eq(moveOf(p), "CashToss:7", "money rain")
		now.value += 5
		atStall = false
		for _ = 1, MoveConfig.BigSell.Items * 2 do
			test.onSold(p, {}, 10)
		end
		test.flushSell(p)
		T.eq(moveOf(p), "CashToss:7", "a Sell Box far away: nothing")
	end)

	T.test("moves: Net Move is rate limited", function()
		local limit = Net.Events.Move
		T.truthy(type(limit) == "table", "Move is a client -> server event")
		T.truthy(limit.Rate <= 5 and limit.Burst <= 8, "a tight limit")
		-- the Net.spec trick: fake remotes, then a burst of events
		local remotes: { [string]: any } = {}
		local original = rawget(Net, "event")
		rawset(Net, "event", function(remoteName: string)
			local remote = remotes[remoteName]
			if not remote then
				remote = { Listeners = {} }
				remote.OnServerEvent = {
					Connect = function(_, fn)
						table.insert(remote.Listeners, fn)
						return { Connected = true, Disconnect = function() end }
					end,
				}
				remotes[remoteName] = remote
			end
			return remote
		end)
		Net._test.reset()
		local ok, err = pcall(function()
			local calls = 0
			Net.on("Move", function()
				calls += 1
			end)
			local player = { Name = "Spammer", UserId = 9, Parent = Players }
			for _ = 1, 40 do
				for _, listener in remotes.Move.Listeners do
					listener(player, "Wave")
				end
			end
			T.eq(calls, limit.Burst, "a burst gets through, the rest is dropped")
		end)
		Net._test.reset()
		rawset(Net, "event", original)
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- review fixes (anim/all #4, #6)

	-- #6: the game's Reduce motion (and Roblox's) calms the celebrations and skips the extras
	T.test("moves: Reduce Motion calms celebrations, skips the extras, keeps the feedback moves", function()
		T.eq(MoveRules.substitute("BigCelebrate", true), "CelebrateCalm", "BigCelebrate becomes the plain, calm celebration")
		T.eq(MoveRules.substitute("Celebrate", true), "CelebrateCalm", "Celebrate gets calmer")
		T.eq(MoveRules.substitute("CashToss", true), "CashTossCalm", "the money toss gets calmer")
		for name in MoveConfig.Extras do
			T.eq(MoveRules.substitute(name, true), nil, name .. ": an optional extra is skipped")
			T.eq(MoveRules.substitute(name, false), name, name .. ": played without Reduce Motion")
		end
		T.truthy(MoveConfig.Extras.Wave and MoveConfig.Extras.Shrug, "Wave and Shrug are the extras")
		for _, name in { "Carry", "Throw", "Recoil", "Spray" } do
			T.eq(MoveRules.substitute(name, true), name, name .. " stays (gameplay feedback)")
			T.falsy(MoveConfig.Extras[name], name .. " is no extra")
		end
		for from, to in MoveConfig.ReducedMotion do
			T.truthy(MoveConfig.Moves[from] and MoveConfig.Moves[to], `{from} -> {to}: both exist`)
			T.eq(MoveConfig.ReducedMotion[to], nil, to .. ": no chains")
			T.falsy(MoveConfig.Extras[to], to .. " is no extra")
			T.eq(MoveConfig.Moves[to].Slot, MoveConfig.Moves[from].Slot, to .. ": the same slot")
		end
		-- the calm moves: a smaller hop, no crouch dip, no spin
		local function rootRange(name: string): (number, number, number)
			local move = MoveConfig.Moves[name]
			local high, low, turn = -math.huge, math.huge, 0
			for f = 0, 60 do
				local pose, offset = MoveMath.evaluate(move, move.Duration * f / 60, 1, {})
				high = math.max(high, offset.Y)
				low = math.min(low, offset.Y)
				local root = pose.Root
				if root then
					local look = root.LookVector
					turn = math.max(turn, math.abs(math.atan2(-look.X, -look.Z)))
				end
			end
			return high, low, turn
		end
		local bigHigh = rootRange("BigCelebrate")
		local celebrateHigh, celebrateLow = rootRange("Celebrate")
		for _, name in { "CelebrateCalm", "CashTossCalm" } do
			local high, low, turn = rootRange(name)
			T.truthy(high <= 0.3, name .. ": a small hop at most")
			T.truthy(high < celebrateHigh and high < bigHigh, name .. ": smaller than the full celebrations")
			T.truthy(low >= -0.01, name .. ": no crouch dip")
			T.truthy(turn < 1 * DEG, name .. ": no spin")
		end
		T.truthy(celebrateLow < -0.1, "(the full Celebrate does dip: the check above means something)")
		-- the controller reads the game's toggle as well as Roblox's
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/MoveController.luau")
		T.truthy(controller:find("SettingsController.onChanged", 1, true), "subscribes to the SETTINGS panel")
		T.truthy(controller:find("current.ReduceMotion", 1, true), "reads SettingsConfig.ReduceMotion")
		T.truthy(controller:find("ReducedMotionEnabled", 1, true), "and Roblox's own setting")
		T.truthy(controller:find("MoveRules.substitute(name, reducedMotion())", 1, true), "start() swaps by both")
		local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
		T.eq(SettingsConfig.Defaults.ReduceMotion, false, "the SETTINGS toggle exists (off by default)")
	end)

	-- #4: an extra never takes the arm holding the blaster; firing masks every move's arms
	T.test("moves: the blaster arm stays on target (extras skipped, arms masked while firing)", function()
		for name in MoveConfig.Extras do
			T.truthy(MoveRules.usesArms(name), name .. " overrides an arm")
			T.truthy(MoveRules.skipArmed(name, true, false), name .. ": skipped with a tool in hand")
			T.truthy(MoveRules.skipArmed(name, false, true), name .. ": skipped while the blaster fires")
			T.falsy(MoveRules.skipArmed(name, false, false), name .. ": plays with empty hands")
		end
		for _, name in { "Throw", "Celebrate", "BigCelebrate", "CashToss", "Carry", "Recoil" } do
			T.falsy(MoveRules.skipArmed(name, true, true), name .. ": never skipped (feedback / celebration)")
		end
		T.falsy(MoveRules.usesArms("Recoil"), "Recoil only adds to the arms")
		T.truthy(MoveRules.maskArms("Action", true), "firing: an action leaves the arms alone")
		T.truthy(MoveRules.maskArms("Loop", true), "firing: a loop leaves the arms alone")
		T.falsy(MoveRules.maskArms("Kick", true), "the recoil kick still moves the gun arm")
		T.falsy(MoveRules.maskArms("Action", false), "not firing: the arms move")
		for joint in MoveRules.ArmJoints do
			T.truthy(JOINTS[joint] and (joint:find("Shoulder") or joint:find("Elbow") or joint:find("Wrist")), joint .. " is an arm joint")
		end
		-- MoveRig: a masked layer leaves the tool-hold pose of the arm alone, the body still moves
		local motors = fakeMotors()
		local rig = MoveRig.fromMotors(motors)
		local hold = CFrame.Angles(90 * DEG, 0, 0)
		local shrug = MoveMath.evaluate(MoveConfig.Moves.Shrug, 0.4, 1, {})
		local layer = {
			Pose = shrug,
			Weight = 1,
			Override = MoveMath.overrides(MoveConfig.Moves.Shrug),
			Mask = MoveRules.ArmJoints,
		}
		local kick = { Pose = { RightShoulder = CFrame.Angles(5 * DEG, 0, 0) }, Weight = 1, Override = {}, Mask = nil }
		motors.RightShoulder.Transform = hold
		MoveRig.step(rig, { layer, kick }, 2)
		T.truthy(near(motors.RightShoulder.Transform, hold * kick.Pose.RightShoulder, 1e-3), "the gun arm: the hold plus the kick only")
		T.eq(motors.LeftElbow.Transform, CFrame.identity, "the other arm is left alone too")
		T.truthy(near(motors.Neck.Transform, shrug.Neck, 1e-3), "the head tilt still plays")
		-- the controller checks both places: what you send, and what you show of the others
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/MoveController.luau")
		local _, checks = controller:gsub("MoveRules%.skipArmed%(", "")
		T.eq(checks, 2, "playLocal and onMoveAttribute skip extras on the gun arm")
		T.truthy(controller:find("MoveRules.maskArms(", 1, true), "every frame: the arms masked while firing")
	end)

	---------------------------------------------------------------- the integrator's rules (static)

	T.test("moves: one Stepped loop, no new input bindings, the one-line Throw hook", function()
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/MoveController.luau")
		local _, stepped = controller:gsub("RunService%.Stepped:Connect", "")
		T.eq(stepped, 1, "one RunService loop for every character")
		for _, banned in { "RenderStepped", "Heartbeat", "BindAction", "InputBegan", "UserInputService", "ContextActionService" } do
			T.falsy(controller:find(banned, 1, true), "MoveController uses no " .. banned)
		end
		local interact = fs.readFile(Loader.root .. "/src/client/Controllers/InteractController.luau")
		local _, hooks = interact:gsub("MoveController", "")
		T.eq(hooks, 2, "InteractController: one hook line (the call and its comment)")
		T.truthy(
			interact:find('pcall%(require%(script%.Parent%.MoveController%)%.playLocal, "Throw"%)[^\n]*\n%s*Net%.send%("CarryThrow"'),
			"the hook plays Throw (pcall: never blocks it) right before the throw is sent"
		)
		local mathSource = fs.readFile(Loader.root .. "/src/shared/Moves/MoveMath.luau")
		for _, banned in { "GetService", "Players", "LocalPlayer", "Instance.new" } do
			T.falsy(mathSource:find(banned, 1, true), "MoveMath stays pure: no " .. banned)
		end
	end)
end
