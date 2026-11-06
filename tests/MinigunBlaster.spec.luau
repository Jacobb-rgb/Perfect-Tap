--[[
	The round blasters (Builders/MinigunBlaster, the owner's pictures of 2026-10-31
	and 2026-11-06): every level in every ore and every STAR blaster stays inside
	its budget, every piece is round (only the crystals and the hexagonal muzzle
	are cut), the crystals grow with the level, each level has his colours in its
	case's ore and an older save's other ore keeps its own, the spinning parts hang
	on the spin hub's Motor6D about the gun's axis, the two-handed hip hold fits,
	and the client's spin speed ramps up and runs down (Effects/BarrelSpin).
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Enum, Vector3 = roblox.Enum, roblox.Vector3
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local MinigunBlaster = Loader.requirePath("ReplicatedStorage.Shared.Builders.MinigunBlaster")
	local BarrelSpin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BarrelSpin")

	local function named(tool: any): { [string]: number }
		local count = {}
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") then
				count[d.Name] = (count[d.Name] or 0) + 1
			end
		end
		return count
	end

	T.test("MinigunBlaster: the game's blasters are round miniguns", function()
		T.eq(BlasterBuilder.Shape, "Minigun", "the owner's pick")
	end)

	T.test("MinigunBlaster: every level in every ore and every STAR blaster within the budget", function()
		local ores = { "", "NotAnOre" }
		for _, ore in OreData.List do
			table.insert(ores, ore.Id)
		end
		local function check(tool: any, label: string)
			local parts = 0
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			-- (the Handle and the spin hub come on top; below the cap: piece() stops silently at it)
			T.lt(parts - 2, MinigunBlaster.MaxParts, label .. " nothing cut off at the cap")
			T.le(parts, BlasterBuilder.MaxParts, label .. " within the blaster budget")
		end
		for level = 1, BlasterData.MaxLevel do
			for _, ore in ores do
				check(BlasterBuilder.build(level, ore), `level {level} {ore}`)
			end
		end
		for _, star in StarBlasterData.List do
			check(BlasterBuilder.buildStar(star, 10, "Heartstone"), star.Id)
		end
	end)

	T.test("MinigunBlaster: all round but the crystals and the hexagonal muzzle", function()
		local cut = { Crystal = true, CrystalTip = true, MuzzleGlow = true }
		for _, tool in
			{
				BlasterBuilder.build(1, ""),
				BlasterBuilder.build(10, BlasterData.vaultOre(10)),
				BlasterBuilder.buildStar(StarBlasterData.ById.Pulsar, 10, "Heartstone"),
			}
		do
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 and not cut[d.Name] then
					T.truthy(d:IsA("Part") and (d.Shape == Enum.PartType.Cylinder or d.Shape == Enum.PartType.Ball), d.Name .. " is round")
				end
			end
		end
	end)

	T.test("MinigunBlaster: crystals grow with the level, his colours in the case's ore", function()
		local last = 0
		local neonOf = function(tool: any, name: string): any
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") and d.Name == name then
					return d.Color
				end
			end
			return nil
		end
		for level = 1, BlasterData.MaxLevel do
			local tool = BlasterBuilder.build(level, BlasterData.vaultOre(level))
			local n = named(tool)
			local crystals = n.Crystal or 0
			T.eq(crystals, MinigunBlaster.crystals(level), `level {level} crystals`)
			T.truthy(crystals >= last, `level {level}: never fewer crystals`)
			last = crystals
			T.eq(n.Barrel, 6, `level {level}: six barrels`)
			T.eq(n.MuzzleGlow, 3, `level {level}: the hexagonal muzzle`)
			T.truthy((n.Rim or 0) >= 5, `level {level}: the glowing bands and hoops`)
			T.eq(
				neonOf(tool, "Rim"),
				MinigunBlaster.palette(level, BlasterData.vaultOre(level), {} :: any).Color,
				`level {level}: his colour`
			)
		end
		T.eq(MinigunBlaster.crystals(1), 2, "two at level 1")
		T.eq(MinigunBlaster.crystals(10), 12, "twelve at level 10")
		-- no two neighbours in his list look the same but the two first, which differ a little
		for level = 2, #MinigunBlaster.Palettes do
			local a, b = MinigunBlaster.Palettes[level - 1].Crystal, MinigunBlaster.Palettes[level].Crystal
			T.truthy(a ~= b, `model {level}: its own crystal colour`)
		end
		T.eq(#MinigunBlaster.Palettes, BlasterData.MaxLevel + #StarBlasterData.List, "a palette for every gun")
		-- an older save's gun in another ore keeps that ore's colours
		local own = neonOf(BlasterBuilder.build(5, BlasterData.vaultOre(5)), "Rim")
		T.truthy(neonOf(BlasterBuilder.build(5, "Heartstone"), "Rim") ~= own, "another ore, another colour")
		-- the STAR blasters: all the crystals; the Singularity Rail has its ring muzzle
		for _, star in StarBlasterData.List do
			local tool = BlasterBuilder.buildStar(star, 3, "Copper")
			T.eq(named(tool).Crystal, 12, star.Id .. ": all twelve crystals")
			T.eq(tool:GetAttribute("Star"), star.Id, star.Id .. ": its star id")
		end
		T.eq(named(BlasterBuilder.buildStar(StarBlasterData.ById.Singularity, 3, "Copper")).Bore, 1, "the ring muzzle's dark bore")
	end)

	T.test("MinigunBlaster: the barrels, dots and lights hang on the spin motor about the gun's axis", function()
		for _, tool in { BlasterBuilder.build(3, BlasterData.vaultOre(3)), BlasterBuilder.buildStar(StarBlasterData.ById.Nebula, 10, "") } do
			local handle = tool:FindFirstChild("Handle")
			local hub = tool:FindFirstChild(BlasterBuilder.SpinHub)
			local motor = handle:FindFirstChild(BlasterBuilder.SpinMotor)
			T.truthy(hub and motor and motor:IsA("Motor6D"), "the hub and its motor")
			T.truthy(motor.Part0 == handle and motor.Part1 == hub, "Handle -> hub")
			T.truthy((motor.C0.Position - hub.CFrame.Position).Magnitude < 1e-4, "the motor sits at the hub")
			local muzzle = handle:FindFirstChild("Muzzle")
			-- the axis runs through the muzzle (the beam leaves from the cluster's middle)
			T.near(motor.C0.Position.X, muzzle.Position.X, 1e-4, "on the muzzle's line (x)")
			T.near(motor.C0.Position.Y, muzzle.Position.Y, 1e-4, "on the muzzle's line (y)")
			local spinning = 0
			for _, d in tool:GetDescendants() do
				local weld = if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
				if weld and weld.Part0 == hub then
					spinning += 1
					T.truthy(d.Name == "Barrel" or d.Name == "Dot" or d.Name == "Light", d.Name .. " turns with the barrels")
				end
			end
			T.eq(spinning, 16, "six barrels, six rim dots and four lights turn")
			T.eq(BarrelSpin.motorOf(tool), motor, "the client finds the motor")
		end
		T.eq(BarrelSpin.motorOf(BlasterBuilder.silhouette(5)), nil, "no motor, no spin")
	end)

	-- the hold on the R15 rig, the Animator's tool hold under it (owner: "dole u pasu ... oběma rukama")
	T.test("BlasterHold: low at the hip, the barrel ahead, both hands on the gun, less reach than the arm's", function()
		local Moves = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
		local R15 = require("../tools/lune/lib/dummy_r15")
		local MovePose = require("../tools/lune/lib/move_pose")
		local CFrame = Loader.CFrame
		local RAISED = CFrame.Angles(math.rad(90), 0, 0)
		local GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		local parts, pose = MovePose.solve(Loader, Moves.Moves[Moves.Hold], 0.8, nil, function(joint: string)
			return if joint == "RightShoulder" then RAISED else CFrame.identity
		end)
		local arm = R15.solve(CFrame.new(0, R15.RootHeight, 0), { RightShoulder = RAISED })
		T.truthy(pose.RightGrip, "the hold turns the gun on the grip")
		local handle = parts.RightHand * GRIP * pose.RightGrip
		local shoulderY = (parts.UpperTorso * CFrame.new(1, 0.56, 0)).Position.Y
		T.lt(handle.Position.Y, shoulderY - 0.5, "the hand well under the shoulder")
		T.lt(handle.Position.Y, parts.LowerTorso.Position.Y + 0.8, "the hand at the belt")
		T.truthy(handle.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.97, "the barrel straight ahead (within about 14 degrees)")
		-- the left hand on the gun: over the hand's point, near its middle line
		local left = handle:PointToObjectSpace((parts.LeftHand * CFrame.new(0, -0.15, 0)).Position)
		T.truthy(math.abs(left.X) < 0.3 and left.Y > 0 and left.Y < 1 and left.Z < 0.3 and left.Z > -1, "the left hand on the gun")
		for _, level in { 1, 5, 10 } do
			local muzzle =
				BlasterBuilder.build(level, BlasterData.vaultOre(level)):FindFirstChild("Handle"):FindFirstChild("Muzzle").Position
			local tip, armTip = handle * muzzle, (arm.RightHand * GRIP) * muzzle
			T.lt(tip.Y, armTip.Y - 0.5, `level {level}: the barrel lower than on the raised arm`)
			-- (no further ahead than the arm's hold: a wall in front is no worse than before)
			T.truthy(tip.Z > armTip.Z, `level {level}: the barrel reaches less far ahead`)
		end
	end)

	T.test("BarrelSpin: spins up in SpinUp, runs down in SpinDown, never past full", function()
		local speed, t = 0, 0
		while speed < BarrelSpin.Full and t < 2 do
			speed = BarrelSpin.speed(speed, true, 1 / 60, BarrelSpin.Full)
			t += 1 / 60
		end
		T.near(t, BarrelSpin.SpinUp, 0.03, "full spin after SpinUp")
		T.eq(BarrelSpin.speed(speed, true, 1, BarrelSpin.Full), BarrelSpin.Full, "never past full")
		t = 0
		while speed > 0 and t < 3 do
			speed = BarrelSpin.speed(speed, false, 1 / 60, BarrelSpin.Full)
			t += 1 / 60
		end
		T.near(t, BarrelSpin.SpinDown, 0.03, "stopped after SpinDown")
		T.eq(speed, 0, "stopped")
		T.truthy(BarrelSpin.ReducedFull < BarrelSpin.Full, "Reduce motion: slower")
	end)
end
