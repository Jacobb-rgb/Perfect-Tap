--[[
	The hoverboard riding pose (owner 2026-10-24: "no cool animation, it looks
	like I'm bugged onto a flying thing"): Moves/BoardPose on the R15 block rig.
	Every joint posed in every state, the feet stay on the deck while riding
	(any speed, turn, landing, the end of the hop on), lift clear of it in a
	jump (the board kickflips under them), the hands never go through the
	body; the hop-on phases, the board's fly-in and the kickflip end where
	they should.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BoardPose = Loader.requirePath("ReplicatedStorage.Shared.Moves.BoardPose")
	local R15 = require("../tools/lune/lib/dummy_r15")

	local rootCF = CFrame.new(0, R15.RootHeight, 0)

	local function solve(state: any): any
		local pose = BoardPose.evaluate(state, {})
		return R15.solve(rootCF, pose), pose
	end

	-- the lowest corner of each foot above the deck (the dummy's floor; `turn` tilts it like the board
	-- does in a turn: about the board's Root, DeckHeight under the deck)
	local function feet(parts: any, turn: number?): (number, number)
		local d = BoardPose.DeckHeight
		local deck = CFrame.new(0, -d, 0) * CFrame.Angles(0, 0, BoardPose.MaxRoll * (turn or 0)) * CFrame.new(0, d, 0)
		local lows = {}
		for _, foot in { "LeftFoot", "RightFoot" } do
			local size = R15.Parts[foot].Size
			local low = math.huge
			for cx = -1, 1, 2 do
				for cz = -1, 1, 2 do
					local p = deck:PointToObjectSpace(parts[foot] * Vector3.new(cx * size.X / 2, -size.Y / 2, cz * size.Z / 2))
					low = math.min(low, p.Y)
				end
			end
			table.insert(lows, low)
		end
		return lows[1], lows[2]
	end

	local function handsInBody(parts: any): number
		local worst = 0
		for _, limb in { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" } do
			local half = R15.Parts[limb].Size * 0.42
			for _, body in { "UpperTorso", "Head", "LowerTorso" } do
				local size = R15.Parts[body].Size
				for cx = -1, 1, 2 do
					for cy = -1, 1, 2 do
						for cz = -1, 1, 2 do
							local p = parts[body]:PointToObjectSpace(parts[limb] * Vector3.new(cx * half.X, cy * half.Y, cz * half.Z))
							local depth = math.min(size.X / 2 - math.abs(p.X), size.Y / 2 - math.abs(p.Y), size.Z / 2 - math.abs(p.Z))
							worst = math.max(worst, depth)
						end
					end
				end
			end
		end
		return worst
	end

	T.test("board pose: every joint, feet on the deck while riding, hands out of the body", function()
		local lowest, highest, worstHands = math.huge, -math.huge, 0
		for _, speed in { 0, 0.5, 1 } do
			for _, turn in { -1, 0, 1 } do
				for _, land in { 0, 0.5, 1 } do
					for f = 0, 20 do
						local state = { T = f * 0.15, Speed = speed, Turn = turn, Mount = 1, Air = 0, Land = land }
						local parts, pose = solve(state)
						for _, joint in BoardPose.Joints do
							T.truthy(pose[joint] ~= nil, joint .. " posed")
						end
						local l, r = feet(parts, turn)
						lowest = math.min(lowest, l, r)
						highest = math.max(highest, l, r)
						worstHands = math.max(worstHands, handsInBody(parts))
					end
				end
			end
		end
		T.truthy(lowest > -0.35, `feet never deep in the deck (lowest {lowest})`)
		T.truthy(highest < 0.4, `feet never float off the deck while riding (highest {highest})`)
		T.le(worstHands, 0.1, "hands and forearms stay out of the body")
	end)

	T.test("board pose: a jump lifts the feet clear for the kickflip", function()
		local parts = solve({ T = 0, Speed = 0.6, Turn = 0, Mount = 1, Air = 1, Land = 0 })
		local l, r = feet(parts)
		T.truthy(math.min(l, r) > 0.4, `both feet off the deck in the air ({l}, {r})`)
	end)

	T.test("board pose: the hop on starts facing forward and ends in the stance on the deck", function()
		local prep, jump, turn, land = BoardPose.mountPhases(0)
		T.eq(jump, 0, "no jump at the start")
		T.eq(turn, 0, "still facing forward")
		prep, jump, turn, land = BoardPose.mountPhases(1)
		T.eq(prep, 0, "prep done")
		T.eq(jump, 0, "jump done")
		T.eq(turn, 1, "turned into the stance")
		T.near(land, 0, 1e-6, "squash done")
		local _, top = BoardPose.mountPhases(0.5)
		T.near(top, 1, 1e-6, "the top of the hop half way")
		T.eq(BoardPose.weight(0), 0, "fades in from the plain pose")
		T.eq(BoardPose.weight(1), 1, "full pose once on")
		for f = 0, 30 do
			local parts = solve({ T = 0, Speed = 0, Turn = 0, Mount = f / 30, Air = 0, Land = 0 })
			local l, r = feet(parts)
			T.truthy(math.min(l, r) > -0.35, `the hop never sinks into the deck (u {f / 30}: {math.min(l, r)})`)
		end
		local rise, spin = BoardPose.boardMount(0)
		T.near(rise, -2.4, 1e-6, "the board starts below")
		T.near(spin, math.pi * 2, 1e-6, "one full spin in")
		rise, spin = BoardPose.boardMount(1)
		T.near(rise, 0, 1e-6, "the board ends under the feet")
		T.near(spin, 0, 1e-6, "and straight")
		T.eq(BoardPose.flip(0), 0, "the kickflip starts flat")
		T.near(BoardPose.flip(BoardPose.FlipTime), math.pi * 2, 1e-6, "and ends flat after one roll")
	end)

	T.test("board pose: the kickflip starts only on a jump and never snaps", function()
		local MAX_STEP = math.rad(30)
		local function wrapped(a: number): number
			return (a + math.pi) % (2 * math.pi) - math.pi
		end
		-- a jump at 60 fps that lands after 0.1 s (a short hop); a second launch mid-flip is ignored
		local flipAt: number? = nil
		local last = 0
		local started = false
		for f = 0, 60 do
			local now = f / 60
			local roll
			flipAt, roll = BoardPose.stepFlip(flipAt, now, f == 0 or f == 10)
			if f == 0 then
				started = flipAt ~= nil
			end
			T.le(math.abs(wrapped(roll - last)), MAX_STEP, `roll step at frame {f}`)
			last = roll
		end
		T.truthy(started, "a jump starts the flip")
		T.eq(flipAt, nil, "the flip has ended")
		T.near(wrapped(last), 0, 1e-6, "flat again")
		-- a fall off a ledge (no launch): no flip at all
		local at: number? = nil
		for f = 0, 30 do
			local roll
			at, roll = BoardPose.stepFlip(at, f / 60, false)
			T.eq(roll, 0, "no flip on a fall")
		end
	end)

	T.test("board pose: leg scale from the joints, tall legs still stand on the deck", function()
		local joints: { [string]: any } = {}
		for _, j in R15.Joints do
			joints[j.Name] = j
		end
		T.near(BoardPose.legScale(joints.LeftHip, joints.LeftKnee, joints.LeftAnkle), 1, 0.01, "block rig = 1")
		T.eq(BoardPose.legScale({}, {}, {}), 1, "broken joints = 1")
		-- the block rig with legs 1.3 x as long (Rthro-like), solved by hand
		local k = 1.3
		local LEG = { LeftHip = "C1", LeftKnee = "both", LeftAnkle = "C0", RightHip = "C1", RightKnee = "both", RightAnkle = "C0" }
		local scaled = {}
		for _, j in R15.Joints do
			local copy = { Name = j.Name, Part0 = j.Part0, Part1 = j.Part1, C0 = j.C0, C1 = j.C1 }
			local which = LEG[j.Name]
			if which == "C0" or which == "both" then
				copy.C0 = CFrame.new(j.C0.Position * k)
			end
			if which == "C1" or which == "both" then
				copy.C1 = CFrame.new(j.C1.Position * k)
			end
			table.insert(scaled, copy)
			joints[j.Name] = copy
		end
		local leg = BoardPose.legScale(joints.LeftHip, joints.LeftKnee, joints.LeftAnkle)
		T.near(leg, k, 0.01, "tall legs measured")
		local rootY = R15.RootHeight + (k - 1) * BoardPose.BlockLeg
		local lowest, highest = math.huge, -math.huge
		for _, speed in { 0, 1 } do
			for _, land in { 0, 1 } do
				local pose = BoardPose.evaluate({ T = 0.4, Speed = speed, Turn = 0, Mount = 1, Air = 0, Land = land, Leg = leg }, {})
				local parts: { [string]: any } = { HumanoidRootPart = CFrame.new(0, rootY, 0) }
				for _, j in scaled do
					parts[j.Part1] = parts[j.Part0] * j.C0 * (pose[j.Name] or CFrame.identity) * j.C1:Inverse()
				end
				local l, r = feet(parts)
				lowest = math.min(lowest, l, r)
				highest = math.max(highest, l, r)
			end
		end
		T.truthy(lowest > -0.35 and highest < 0.45, `tall legs crouch onto the deck ({lowest} .. {highest})`)
	end)

	T.test("board pose: sideways like a surfer (Pet Simulator 99), head ahead, blaster pointing ahead", function()
		local free = solve({ T = 0.3, Speed = 0.5, Turn = 0, Mount = 1, Air = 0, Land = 0 })
		local function yawOf(v: any): number
			return math.deg(math.atan2(-v.X, -v.Z))
		end
		local hips = yawOf(free.LowerTorso.LookVector)
		T.truthy(math.abs(hips - BoardPose.Stance) < 6, `the body is turned sideways ({hips} degrees)`)
		local head = yawOf(free.Head.LookVector)
		-- almost ahead: the Helmet Lamp on the head (a 70 degree cone) lights the way
		T.truthy(head > 0 and head < 20, `the head looks almost where you go ({head} degrees)`)
		local l, r = free.LeftFoot.Position, free.RightFoot.Position
		T.truthy(math.abs(l.Z - r.Z) > 1.0, `feet apart along the board ({math.abs(l.Z - r.Z)})`)
		T.truthy(r.Z < l.Z, "the right foot leads")
		T.truthy(math.abs(l.X - r.X) < 0.6, "both feet on the board's middle line")
		-- with the blaster: the right hand far ahead of the shoulder, at shoulder height
		local tool = solve({ T = 0.3, Speed = 0.5, Turn = 0, Mount = 1, Air = 0, Land = 0, Tool = true })
		local hand, shoulder = tool.RightHand.Position, tool.RightUpperArm.Position
		T.truthy(hand.Z < shoulder.Z - 1.2, `the blaster hand points ahead ({hand.Z - shoulder.Z})`)
		T.truthy(math.abs(hand.Y - shoulder.Y) < 0.6, "at shoulder height")
		-- the hop on starts facing forward and turns sideways
		local start = solve({ T = 0, Speed = 0, Turn = 0, Mount = 0.13, Air = 0, Land = 0 })
		T.truthy(math.abs(yawOf(start.LowerTorso.LookVector)) < 20, "the hop on starts facing ahead")
	end)

	T.test("board pose: MoveRig override on every joint, the Animator's pose back on release", function()
		local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
		local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
		local base = CFrame.Angles(0.2, 0, 0)
		local motors: { [string]: any } = {}
		for _, name in MoveConfig.Joints do
			motors[name] = { Transform = base, Parent = true, Name = name }
		end
		local rig = MoveRig.fromMotors(motors)
		local all = {}
		for _, name in BoardPose.Joints do
			all[name] = true
		end
		local layers = { { Pose = {}, Weight = 1, Override = all } }
		BoardPose.evaluate({ T = 0, Speed = 0.5, Turn = 0, Mount = 1, Air = 0, Land = 0 }, layers[1].Pose)
		for _ = 1, 3 do
			for _, motor in motors do
				motor.Transform = base -- the Animator writes its pose every frame
			end
			MoveRig.step(rig, layers, 1)
		end
		for name, motor in motors do
			T.near((motor.Transform.Position - layers[1].Pose[name].Position).Magnitude, 0, 1e-6, name .. " is the board pose")
			T.near(motor.Transform.LookVector:Dot(layers[1].Pose[name].LookVector), 1, 1e-6, name .. " turned as posed")
		end
		MoveRig.release(rig)
		for name, motor in motors do
			T.near(motor.Transform.LookVector:Dot(base.LookVector), 1, 1e-6, name .. " back to the Animator's pose")
		end
		T.falsy(MoveRig.holding(rig), "nothing of ours left")
		-- an arm masked (a tool in hand): the Animator keeps it
		layers[1].Mask = { RightShoulder = true }
		motors.RightShoulder.Transform = base
		MoveRig.step(rig, layers, 1)
		T.near(motors.RightShoulder.Transform.LookVector:Dot(base.LookVector), 1, 1e-6, "a masked arm keeps the hold")
	end)

	T.test("board pose: at the pose range edge the whole body fades (no 90 degree snap)", function()
		local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
		local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
		local base = CFrame.Angles(0.2, 0, 0) -- the Animator's pose (another rider's replicated idle)
		local motors: { [string]: any } = {}
		for _, name in MoveConfig.Joints do
			motors[name] = { Transform = base, Parent = true, Name = name }
		end
		T.truthy(motors.Root ~= nil, "the Root is a joint")
		local rig = MoveRig.fromMotors(motors)
		local all = {}
		for _, name in BoardPose.Joints do
			all[name] = true
		end
		local layers = { { Pose = {}, Weight = 1, Override = all } }
		-- one frame as HoverboardController's poseStep does it
		local function at(fade: number)
			local state = { T = 0, Speed = 0.5, Turn = 0, Mount = 1, Air = 0, Land = 0, Fade = fade }
			BoardPose.evaluate(state, layers[1].Pose)
			layers[1].Weight = math.max(1e-3, BoardPose.blend(state))
			for _, motor in motors do
				motor.Transform = base -- the Animator writes its pose every frame
			end
			MoveRig.step(rig, layers, 1)
		end
		local function yaw(): number
			local v = motors.Root.Transform.LookVector
			return math.deg(math.atan2(-v.X, -v.Z))
		end
		at(0.02)
		for name, motor in motors do
			T.near(motor.Transform.LookVector:Dot(base.LookVector), 1, 1e-3, name .. ": a sliver of fade is still the Animator's pose")
			T.near(motor.Transform.Position.Magnitude, 0, 0.01, name .. " not moved yet")
		end
		at(0.5)
		T.truthy(yaw() > 25 and yaw() < 65, `half way turned half way ({yaw()} degrees)`)
		at(1)
		T.near(yaw(), BoardPose.Stance, 6, "faded in: sideways")
		MoveRig.release(rig)
		-- the fade: PoseFadeTime in and out; at once for your own rider and a hop on
		local step = (1 / 60) / 0.3
		local f = 0
		for _ = 1, 9 do
			f = BoardPose.stepFade(f, true, false, step)
		end
		T.near(f, 0.5, 1e-6, "half way after half the time")
		T.eq(BoardPose.stepFade(0, true, true, step), 1, "yours / a hop on: at once")
		T.eq(BoardPose.stepFade(0.01, false, true, step), 0, "out of range: fades to nothing")
		T.near(BoardPose.blend({ T = 0, Speed = 0, Turn = 0, Mount = 1, Air = 0, Land = 0 }), 1, 1e-9, "no Fade: all of it")
	end)

	T.test("board pose: MoveRig finds Avatar Joint Upgrade joints (AnimationConstraints) and poses them", function()
		local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
		local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
		local Instance = roblox.Instance
		-- an R15 character as Roblox spawns it with StarterPlayer.AvatarJointUpgrade on: no Motor6Ds,
		-- an AnimationConstraint per joint between two RigAttachments
		local function character(named: boolean): any
			local model = Instance.new("Model")
			local parts: { [string]: any } = {}
			for _, name in
				{
					"HumanoidRootPart",
					"LowerTorso",
					"UpperTorso",
					"Head",
					"LeftUpperArm",
					"LeftLowerArm",
					"LeftHand",
					"RightUpperArm",
					"RightLowerArm",
					"RightHand",
					"LeftUpperLeg",
					"LeftLowerLeg",
					"LeftFoot",
					"RightUpperLeg",
					"RightLowerLeg",
					"RightFoot",
				}
			do
				local part = Instance.new("Part")
				part.Name = name
				part.Parent = model
				parts[name] = part
			end
			for _, j in R15.Joints do
				local a0 = Instance.new("Attachment")
				a0.Name = j.Name .. "RigAttachment"
				a0.CFrame = j.C0
				a0.Parent = parts[j.Part0]
				local a1 = Instance.new("Attachment")
				a1.Name = j.Name .. "RigAttachment"
				a1.CFrame = j.C1
				a1.Parent = parts[j.Part1]
				local c = Instance.new("AnimationConstraint")
				-- named like the joint in its part, or (the fallback) anonymous somewhere else
				c.Name = if named then j.Name else "AnimationConstraint"
				c.Attachment0 = a0
				c.Attachment1 = a1
				c.Parent = if named then parts[j.Part1] else parts.HumanoidRootPart
			end
			return model
		end
		for _, named in { true, false } do
			local model = character(named)
			local rig = MoveRig.find(model)
			T.truthy(rig ~= nil, `an AJU character is a rig (named {named})`)
			T.eq(rig.Count, #MoveConfig.Joints, "every joint found")
			for i = 1, rig.Count do
				T.truthy(rig.Motors[i]:IsA("AnimationConstraint"), rig.Names[i] .. " is the AnimationConstraint")
				T.eq(rig.Motors[i].Attachment1.Name, rig.Names[i] .. "RigAttachment", rig.Names[i] .. " matched to its joint")
			end
			-- the riding pose lands on the constraints' Transform
			local layers = { { Pose = {}, Weight = 1, Override = {} :: { [string]: boolean } } }
			for _, name in BoardPose.Joints do
				layers[1].Override[name] = true
			end
			BoardPose.evaluate({ T = 0, Speed = 0.5, Turn = 0, Mount = 1, Air = 0, Land = 0 }, layers[1].Pose)
			MoveRig.step(rig, layers, 1)
			local root = rig.Motors[table.find(rig.Names, "Root") :: number]
			T.near((root.Transform.Position - layers[1].Pose.Root.Position).Magnitude, 0, 1e-4, "the Root moved")
			T.near(root.Transform.LookVector:Dot(layers[1].Pose.Root.LookVector), 1, 1e-4, "and turned sideways")
			MoveRig.release(rig)
			T.falsy(MoveRig.holding(rig), "given back")
		end
	end)

	T.test("board pose: the controller drives it in one Stepped pass over MoveRig", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/Controllers/HoverboardController.luau")
		T.truthy(string.find(source, "RunService.Stepped:Connect", 1, true) ~= nil, "Stepped (after the Animator)")
		T.truthy(string.find(source, "MoveRig.step(rig, rider.Layers, 1)", 1, true) ~= nil, "MoveRig layering")
		T.truthy(string.find(source, "MoveRig.release(rig)", 1, true) ~= nil, "the pose is given back")
		T.truthy(
			string.find(source, "layer.Weight = math.max(1e-3, BoardPose.blend(rider.State))", 1, true) ~= nil,
			"the weight is the pose's own blend"
		)
		T.truthy(string.find(source, "rider.State.Fade = rider.PoseFade", 1, true) ~= nil, "the range edge fades the pose itself")
	end)
end
