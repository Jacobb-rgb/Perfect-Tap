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

	-- the lowest corner of each foot (the dummy's floor = the deck)
	local function feet(parts: any): (number, number)
		local lows = {}
		for _, foot in { "LeftFoot", "RightFoot" } do
			local size = R15.Parts[foot].Size
			local low = math.huge
			for cx = -1, 1, 2 do
				for cz = -1, 1, 2 do
					local p = parts[foot] * Vector3.new(cx * size.X / 2, -size.Y / 2, cz * size.Z / 2)
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
						local l, r = feet(parts)
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

	T.test("board pose: the controller drives it in one Stepped pass over MoveRig", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/Controllers/HoverboardController.luau")
		T.truthy(string.find(source, "RunService.Stepped:Connect", 1, true) ~= nil, "Stepped (after the Animator)")
		T.truthy(string.find(source, "MoveRig.step(rig, rider.Layers, 1)", 1, true) ~= nil, "MoveRig layering")
		T.truthy(string.find(source, "MoveRig.release(rig)", 1, true) ~= nil, "the pose is given back")
	end)
end
