-- Golem followers that RUN (client Effects/GolemGait + WorldMotionController): legs and arms in opposition, the stride
-- and cadence by speed and size, the lean and bounce of walk / run / sprint, Reduce motion, the flying pose of Premium
-- golems, the level of detail and the part cap, the limb groups found on real GolemBuilder followers (Pebble Golem,
-- the crowned Diamond Duke and Celestial Sovereign, the Dragonscale Knight's shield, the Dragon King's wings), gear
-- moving with what it is welded to (review anim/ship #8: the Knight's sword in its fist, the capes on the torso, the
-- Dragon King's sceptre), the mirror of GolemController's own hop, the controller swapping welds for running limbs
-- and back on a rig, and its frame loop letting go when the last running follower is gone.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Instance = roblox.Instance
	local Gait = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GolemGait")
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.WorldMotionLogic")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")

	local FOLLOWER = 0.85 -- GolemController.FollowerSize

	-- a gait that has been running at `speed` for a while (smoothed values settled)
	local function settled(speed: number, scale: number, yawRate: number?): any
		local g = Gait.newGait(0, 0)
		local t, yaw = 0, 0
		for _ = 1, 120 do
			t += 1 / 60
			yaw += (yawRate or 0) / 60
			Gait.step(g, t, speed, yaw, scale)
		end
		return g, t
	end

	local function poseAt(speed: number, phase: number, floats: boolean?, reduce: boolean?, yawRate: number?): any
		local g, t = settled(speed, 0.85, yawRate)
		g.Phase = phase
		local pose = Gait.newPose()
		Gait.pose(pose, g, t, 0.85, floats == true, 1, nil, Logic.Golem.JumpTime, reduce == true)
		return pose
	end

	T.test("GolemGait: legs swing opposite each other and the arms pump opposite to the legs", function()
		for _, speed in { 3, 9, 16, 26 } do
			local hold = poseAt(speed, 0).ArmL -- the arms' forward hold (no swing at phase 0)
			for i = 0, 24 do
				local pose = poseAt(speed, i / 24 * math.pi * 2)
				T.near(pose.LegL, -pose.LegR, 1e-9, "legs opposite at " .. speed)
				T.truthy((pose.ArmL - hold) * pose.LegL <= 1e-9, "left arm against the left leg")
				T.truthy((pose.ArmR - hold) * pose.LegR <= 1e-9, "right arm against the right leg")
				if math.abs(pose.LegL) > 0.05 then
					T.truthy(math.abs(pose.ArmL - hold) > math.abs(pose.LegL), "arms pump a little more than the legs swing")
				end
			end
		end
		-- the leg swinging forward lifts (the knee), the one going back doesn't
		local pose = poseAt(16, 0.2)
		T.truthy(pose.LiftL > 0 and pose.LiftR == 0, "left leg coming forward lifts")
	end)

	T.test("GolemGait: the stride grows with speed, steps get quicker, and small golems take quick little steps", function()
		local last = 0
		for _, speed in { 1, 3, 6, 10, 16, 22, 30 } do
			local stride = Gait.stride(speed, 0.85)
			T.truthy(stride > last, "stride grows at " .. speed .. ": " .. stride)
			last = stride
		end
		T.truthy(Gait.cadence(16, 0.85) > Gait.cadence(6, 0.85), "quicker steps when running")
		T.le(Gait.cadence(80, 0.85), Gait.Cadence / math.sqrt(0.85) + 1e-9, "the cadence levels off")
		T.truthy(Gait.cadence(16, 0.6) > Gait.cadence(16, 1.3), "a small golem steps quicker")
		T.truthy(Gait.stride(16, 0.6) < Gait.stride(16, 1.3), "with shorter strides")
		T.eq(Gait.cadence(0, 1), 0, "standing: no steps")
		-- the phase follows the cadence
		local g = Gait.newGait(0, 0)
		local t = 0
		for _ = 1, 60 do
			t += 1 / 60
			Gait.step(g, t, 16, 0, 0.85)
		end
		T.truthy(g.Phase > math.pi * 2 * 1.5, "running a second: more than a stride and a half")
	end)

	T.test("GolemGait: walk, run and sprint: bigger swing, more lean and bounce; Reduce motion is calmer", function()
		local function peak(speed: number, reduce: boolean?): (number, number, number)
			local swing, lift = 0, 0
			local pitch = 0
			for i = 0, 32 do
				local pose = poseAt(speed, i / 32 * math.pi * 2, false, reduce)
				swing = math.max(swing, math.abs(pose.LegL))
				lift = math.max(lift, pose.Lift)
				pitch = pose.Pitch
			end
			return swing, lift, pitch
		end
		local walkSwing, walkLift, walkPitch = peak(3)
		local runSwing, runLift, runPitch = peak(15)
		local sprintSwing, _, sprintPitch = peak(28)
		T.truthy(walkSwing < runSwing and runSwing < sprintSwing, "the legs swing more with speed")
		T.truthy(walkLift < runLift, "a running golem bounces more")
		T.truthy(walkPitch > runPitch and runPitch > sprintPitch, "and leans further forward (sprint most)")
		T.truthy(runPitch < -0.15, "a real forward lean when running")
		local calmSwing, _, calmPitch = peak(28, true)
		T.truthy(calmSwing < sprintSwing * 0.6, "Reduce motion: a smaller swing")
		T.truthy(calmPitch > sprintPitch / 2 - 1e-6, "Reduce motion: no sprint lean")
		-- bank into a turn (a left turn raises the yaw: roll left), none with Reduce motion
		local left = poseAt(15, 1, false, false, 3)
		T.truthy(left.Roll > 0.05, "leans into a left turn")
		T.truthy(left.HeadYaw > 0.1, "and looks where it is going")
		T.near(poseAt(15, 0, false, true, 3).Roll, 0, 1e-9, "Reduce motion: no bank")
		-- standing: no swing, but breathing and looking around
		local idle = poseAt(0, 0)
		T.near(idle.LegL, 0, 1e-6, "standing legs")
		-- a braking golem leans back
		local g, t = settled(16, 0.85)
		for _ = 1, 6 do
			t += 1 / 60
			Gait.step(g, t, 0, 0, 0.85)
		end
		local pose = Gait.newPose()
		Gait.pose(pose, g, t, 0.85, false, 1, nil, Logic.Golem.JumpTime, false)
		local steady = poseAt(g.Speed, g.Phase)
		T.truthy(pose.Pitch > steady.Pitch, "braking: leans back against the stop")
		-- the equip jump: arms up
		local jump = Gait.newPose()
		local g2, t2 = settled(0, 0.85)
		Gait.pose(jump, g2, t2, 0.85, false, 1, Logic.Golem.JumpTime / 2, Logic.Golem.JumpTime, false)
		T.truthy(jump.ArmL > 2 and jump.ArmR > 2, "arms up in the equip jump")
	end)

	T.test("GolemGait: Premium golems fly: arms swept back, legs trailing, a tilt into the motion and the turns", function()
		local fly = poseAt(16, 0.7, true)
		T.truthy(fly.ArmL < -0.9 and fly.ArmR < -0.9, "arms swept back")
		T.truthy(fly.LegL < -0.3 and fly.LegR < -0.3, "legs trailing")
		T.le(math.abs(fly.LegL - fly.LegR), 0.25, "no running steps")
		T.truthy(fly.LiftL == 0 and fly.LiftR == 0, "no lifted knee")
		T.truthy(fly.Pitch < -0.2, "tilted into the flight")
		local turning = poseAt(16, 0.7, true, false, 3)
		T.truthy(turning.Roll > 0.15, "banks into the turn")
		-- every phase gives the same flying legs (the gait clock doesn't drive them)
		local other = poseAt(16, 2.9, true)
		T.near(other.LegL, fly.LegL, 1e-6, "legs don't follow the step phase")
		local hover = poseAt(0, 0, true)
		T.truthy(math.abs(hover.Pitch) < 1e-6 and hover.ArmL > -0.3, "hovering in place: upright, arms relaxed")
		local calm = poseAt(16, 0.7, true, true)
		T.truthy(calm.ArmL > fly.ArmL and calm.Pitch > fly.Pitch, "Reduce motion: a softer flying pose")
	end)

	T.test("GolemGait: full limbs only near the camera and on screen, within the part cap (phones less)", function()
		T.truthy(Gait.lod(10, true))
		T.truthy(Gait.lod(Gait.LimbRange, true))
		T.falsy(Gait.lod(Gait.LimbRange + 1, true), "far: the cheap hop")
		T.falsy(Gait.lod(5, false), "off screen: the cheap hop")
		T.truthy(Gait.fits(140, 20, false))
		T.falsy(Gait.fits(150, 20, false), "PC cap")
		T.truthy(Gait.fits(40, 20, true))
		T.falsy(Gait.fits(50, 20, true), "phone cap")
		T.truthy(Gait.Cap.Phone < Gait.Cap.PC)
	end)

	T.test("GolemGait: limb groups on real followers (Pebble, crowned Duke and Sovereign, Knight's shield, Dragon King)", function()
		local function groups(kind: string): (any, { [string]: string }, any)
			local model = GolemBuilder.build(kind, CFrame.new(5, 0, 3) * CFrame.Angles(0, 0.7, 0), { Welded = true, Size = FOLLOWER })
			local rig = Gait.classify(model)
			T.truthy(rig, kind .. " rig")
			local where: { [string]: string } = {}
			local seen: { [any]: boolean } = {}
			for _, key in { "LegL", "LegR", "ArmL", "ArmR", "Head" } do
				local group = rig[key]
				for i, part in group.Parts do
					T.falsy(seen[part], part.Name .. " in one group only")
					seen[part] = true
					where[part.Name] = key
					-- the rest frame puts it back exactly where the builder put it
					local back = rig.Body.CFrame * group.Rest[i]
					T.near((back.Position - part.CFrame.Position).Magnitude, 0, 1e-4, part.Name .. " rest")
					T.truthy(group.Welds[part] ~= nil, part.Name .. " has its weld")
				end
			end
			return rig, where, model
		end
		local rig, where = groups("PebbleGolem")
		T.near(rig.Scale, FOLLOWER, 1e-4, "studs per golem unit")
		T.eq(where.Leg1, "LegL", "Leg1 is the left leg")
		T.eq(where.Leg2, "LegR")
		T.eq(where.Arm1, "ArmL")
		T.eq(where.Fist1, "ArmL", "the fist swings with its arm")
		T.eq(where.Arm2, "ArmR")
		T.eq(where.Fist2, "ArmR")
		for _, name in { "Head", "Brow", "Eye1", "Eye2", "Chip" } do
			T.eq(where[name], "Head", name .. " on the head")
		end
		for _, name in { "Body", "Core", "Boulder", "Crystal", "Vein" } do
			T.eq(where[name], nil, name .. " stays on the body")
		end
		T.eq(rig.Count, 11, "11 limb parts on the Pebble Golem (legs, arms + fists, head, brow, eyes, the chip on its head)")
		-- the hips sit at the top of the legs, the shoulders at the top of the arms
		local hip = rig.LegL.Pivot.Position
		T.near(hip.Y, (Gait.Hip.Y - 0.975) * FOLLOWER, 1e-4, "hip height")
		T.truthy(hip.X < 0, "left hip on the left")

		for _, kind in { "DiamondDuke", "CelestialSovereign" } do
			local _, crowned = groups(kind)
			local crown = 0
			for name, key in crowned do
				if string.sub(name, 1, 5) == "Crown" then
					T.eq(key, "Head", kind .. " " .. name .. " on the head")
					crown += 1
				end
			end
			T.truthy(crown >= 1, kind .. " has its crown")
		end
		local _, sovereign = groups("CelestialSovereign")
		T.eq(sovereign.Aura, nil, "the aura stays on the body")

		local _, knight = groups("ScaleKnight")
		T.eq(knight.Shield, "ArmL", "the shield goes with the left arm (by where it is)")

		local king, kingWhere, kingModel = groups("DragonKing")
		local wings = 0
		for _, d in kingModel:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Wing" then
				wings += 1
				T.eq(kingWhere[d.Name], nil, "the Dragon King's " .. d.Name .. " stays on the body")
			end
		end
		T.truthy(wings >= 2, "the Dragon King has wings")
		T.truthy(king.Count < GolemBuilder.partCount(kingModel), "the wings and the body are not limbs")
		local flames = 0
		for name, key in kingWhere do
			if key == "Head" and name ~= "Head" then
				flames += 1
			end
		end
		T.truthy(flames >= 3, "the crown of flames rides on the head")
		-- geometry rules for gear the builder doesn't name yet
		T.eq(Gait.groupOf("Boot", Vector3.new(-0.3, 0.1, 0)), "LegL")
		T.eq(Gait.groupOf("Gauntlet", Vector3.new(0.9, 0.8, 0)), "ArmR")
		T.eq(Gait.groupOf("Antenna", Vector3.new(0, 3, 0)), "Head")
		T.eq(Gait.groupOf("Backpack", Vector3.new(0, 1.0, 0.5)), "Body")
		T.eq(Gait.groupOf("WingTip", Vector3.new(1.5, 3.5, 0.6)), "Body", "wings stay on the body whatever their height")
	end)

	T.test("GolemGait: gear moves with what it is welded to: the Knight's sword in its fist, capes on the torso", function()
		local function groups(kind: string, extra: ((any) -> ())?): ({ [string]: string }, any, any)
			local model = GolemBuilder.build(kind, CFrame.new(-4, 0, 2) * CFrame.Angles(0, -0.4, 0), { Welded = true, Size = FOLLOWER })
			if extra then
				extra(model)
			end
			local rig = Gait.classify(model)
			local where: { [string]: string } = {}
			for _, key in { "LegL", "LegR", "ArmL", "ArmR", "Head" } do
				for _, part in rig[key].Parts do
					where[part.Name] = key
				end
			end
			return where, rig, model
		end
		-- the Dragonscale Knight (Epic, live): a flaming sword held up past its head, a kite shield, a cape
		local knight, rig, model = groups("ScaleKnight")
		for _, name in { "Blade", "BladeFire", "Guard", "Pommel" } do
			T.eq(knight[name], "ArmR", "the sword's " .. name .. " is held in the right fist")
		end
		for _, name in { "Shield", "ShieldPoint", "ShieldEye", "Bracer1" } do
			T.eq(knight[name], "ArmL", name .. " on the left arm")
		end
		local capes = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Cape" then
				T.eq(knight[d.Name], nil, "the cape's " .. d.Name .. " follows the torso")
				capes += 1
			end
		end
		T.truthy(capes >= 8, "the cape, its flaps, hem, mantle, straps and clasps: " .. capes)
		T.eq(knight.Pauldron1, "ArmL", "a pauldron turns with its arm, not with the head")
		T.eq(knight.Pauldron2, "ArmR")
		for _, name in { "Helm", "HelmFill", "HelmEdge1", "Jaw", "HelmFang1", "Horn1_1", "Horn2_2", "Crest2", "Plume" } do
			T.eq(knight[name], "Head", "the helm's " .. name .. " turns with the head")
		end
		for _, name in { "Breastplate", "Belt", "Tabard" } do
			T.eq(knight[name], nil, name .. " stays on the body")
		end
		-- no tearing: through a running stride, the idle wave and the equip jump the blade stays on its guard
		local function frameOf(name: string, pose: any): any
			for _, key in { "LegL", "LegR", "ArmL", "ArmR", "Head" } do
				local group = rig[key]
				for i, part in group.Parts do
					if part.Name == name then
						local pitch, roll = 0, 0
						if key == "ArmL" then
							pitch, roll = pose.ArmL, -pose.RollL
						elseif key == "ArmR" then
							pitch, roll = pose.ArmR, pose.RollR
						end
						local yaw = if key == "Head" then pose.HeadYaw else 0
						if key == "Head" then
							pitch = pose.HeadPitch
						end
						return Gait.jointFrame(rig.Body.CFrame, group, pitch, yaw, roll, 0) * group.Rest[i]
					end
				end
			end
			return rig.Body.CFrame * rig.Body.CFrame:ToObjectSpace(model:FindFirstChild(name).CFrame)
		end
		local rest = model:FindFirstChild("Guard").CFrame:ToObjectSpace(model:FindFirstChild("Blade").CFrame)
		local drift = 0
		for _, case in { { 12, 0.7, nil }, { 20, 2.1, nil }, { 0, 0, Logic.Golem.JumpTime / 2 } } do
			local g, t = settled(case[1], FOLLOWER)
			g.Phase = case[2]
			local pose = Gait.newPose()
			Gait.pose(pose, g, t, FOLLOWER, false, 1, case[3], Logic.Golem.JumpTime, false)
			local now = frameOf("Guard", pose):ToObjectSpace(frameOf("Blade", pose))
			drift = math.max(drift, (now.Position - rest.Position).Magnitude)
		end
		T.near(drift, 0, 1e-4, "the blade never leaves its guard")

		-- the Dragon King (Mythic, live): the sceptre with its fire orb in the right hand, the crown on the head
		local king, _, kingModel = groups("DragonKing")
		for _, name in { "Staff", "StaffHead", "Orb" } do
			T.eq(king[name], "ArmR", "the sceptre's " .. name .. " in the right hand")
		end
		for _, name in { "CrownBand", "CrownPoint1", "CrownGem1", "CrownFlame" } do
			T.eq(king[name], "Head", "the crown's " .. name .. " on the head")
		end
		for _, d in kingModel:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Cape" then
				T.eq(king[d.Name], nil, "the royal cape's " .. d.Name .. " follows the torso")
			end
		end
		-- the Magma Wyvern's cape collar and spiked pauldrons
		local wyvern = groups("MagmaWyvern")
		T.eq(wyvern.CapeCollar1, nil, "the cape's collar on the torso")
		T.eq(wyvern.PauldronSpike1, "ArmL", "a pauldron's spike with its pauldron")
		T.eq(wyvern.PauldronSpike2, "ArmR")

		-- a builder's own weld decides: a lantern welded to the right fist, hanging over the head, goes with the fist
		local lit = groups("PebbleGolem", function(m: any)
			local body = m.PrimaryPart
			local s = body.Size.X / GolemBuilder.BodySize.X
			local lantern = Instance.new("Part")
			lantern.Name = "Lantern"
			lantern.Size = Vector3.new(0.2, 0.2, 0.2) * s
			lantern.CFrame = body.CFrame * CFrame.new(1.5 * s, 2.2 * s, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = m:FindFirstChild("Fist2")
			weld.Part1 = lantern
			weld.Parent = lantern
			lantern.Parent = m
		end)
		T.eq(lit.Lantern, "ArmR", "welded to the fist: with the fist (where it hangs would say the head)")
		T.eq(Gait.groupOf("Lantern", Vector3.new(1.5, 3.2, 0)), "Head", "(by where it is alone)")

		-- the touch test is exact for turned boxes (a box turned 45 degrees no longer reaches a corner)
		local half = Vector3.new(0.5, 0.5, 0.5)
		T.truthy(Gait.boxesTouch(CFrame.new(0.95, 0, 0), half, half), "side by side, overlapping")
		T.falsy(Gait.boxesTouch(CFrame.new(1.05, 0, 0), half, half), "a gap")
		T.falsy(Gait.boxesTouch(CFrame.new(1.2, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 4), half, half), "a turned box off the corner")
		T.truthy(Gait.boxesTouch(CFrame.new(1.2, 0, 0) * CFrame.Angles(0, 0, math.pi / 4), half, half), "its tip reaches the side")
	end)

	T.test("GolemGait: the hop it takes out is GolemController's own", function()
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/GolemController.luau")
		for _, expr in
			{
				"math.abs(math.sin(pet.Phase)) * 0.55 * k",
				"pitch = -0.12 * k",
				"roll = math.sin(pet.Phase) * 0.08 * k",
				"pitch = -0.08 * k",
				"local k = math.clamp(speed / 10, 0, 1)",
			}
		do
			T.truthy(string.find(source, expr, 1, true) ~= nil, "GolemController still does: " .. expr)
		end
		local lift, pitch, roll = Gait.controllerHop(math.pi / 2, 20, true, true, false)
		T.near(lift, 0.55, 1e-9)
		T.near(pitch, -0.12, 1e-9)
		T.near(roll, 0.08, 1e-9)
		local fl, fp = Gait.controllerHop(1, 20, true, true, true)
		T.eq(fl, 0, "hovering golems don't hop")
		T.near(fp, -0.08, 1e-9)
		T.eq(select(1, Gait.controllerHop(1, 20, false, true, false)), 0, "standing: no hop")
	end)

	T.test("GolemGait: the controller runs the limbs of near golems and puts the welds back when they go far", function()
		local Players = Loader.game:GetService("Players")
		local hadLocal = rawget(Players, "LocalPlayer")
		local hadGolems = AnimConfig.GolemMotion
		AnimConfig.GolemMotion = true
		rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1 })
		local ok, err = pcall(function()
			local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldMotionController")
			local folder = Instance.new("Folder")
			local rig = {
				Folder = folder,
				Eye = Vector3.new(0, 6, 15),
				Right = Vector3.new(1, 0, 0),
				Up = Vector3.new(0, 1, 0),
				Ground = 0,
				Clock = 900,
				Phone = false,
				Reduce = false,
				Firing = false,
				Root = Vector3.new(0, 3, 0),
				Gravity = 196.2,
			}
			Controller.useRig(rig)
			local followers = Instance.new("Folder")
			local function follower(kind: string, x: number): any
				local model = GolemBuilder.build(kind, CFrame.new(x, 0, 0), { Welded = true, Size = FOLLOWER })
				model.Parent = followers
				return {
					Kind = kind,
					Phase = 0,
					Seed = x,
					Floats = (model:GetAttribute("Hover") or 0) > 0,
					Yaw = 0,
					Model = model,
					Root = model.PrimaryPart,
				}
			end
			local pebble = follower("PebbleGolem", 0)
			local king = follower("DragonKing", 4)
			local now = 2000
			local function frame(speed: number)
				now += 1 / 60
				for _, pet in { pebble, king } do
					local root = pet.Root
					pet.Phase += speed / 60 / 1.7 * math.pi
					local offset = Controller.golemOffset(pet, nil, now, speed > 0.8, true, speed)
					local x = root.CFrame.Position.X
					root.CFrame = CFrame.new(x, 1, -((now - 2000) * speed) % 20) * offset
				end
				Controller.step(1 / 60)
			end
			for _ = 1, 20 do
				frame(16) -- (the pick runs every LimbSelect seconds)
			end
			local known, running = Controller.golemStats()
			T.eq(known >= 2 and running, 2, "both golems near and on screen: their limbs run")
			local leg = pebble.Model:FindFirstChild("Leg1")
			local weld = leg:FindFirstChildOfClass("WeldConstraint")
			T.truthy(leg.Anchored and weld.Enabled == false, "a running leg is off its weld")
			local spread = 0
			for _ = 1, 40 do
				frame(16)
				local rest = pebble.Root.CFrame * CFrame.new(-0.3 * FOLLOWER, (0.25 - 0.975) * FOLLOWER, 0.02 * FOLLOWER)
				spread = math.max(spread, (leg.CFrame.Position - rest.Position).Magnitude)
			end
			T.truthy(spread > 0.08, "the leg swings: " .. spread)
			local wing = king.Model:FindFirstChild("Wing1") or king.Model:FindFirstChild("Wing")
			if wing then
				T.falsy(wing.Anchored, "the Dragon King's wings stay welded to its body")
			end
			-- far away: welds back, limbs at rest on the body
			rig.Eye = Vector3.new(0, 6, 400)
			now += 1
			frame(16)
			local _, after = Controller.golemStats()
			T.eq(after, 0, "far: no running limbs")
			T.truthy(weld.Enabled and not leg.Anchored, "the leg is back on its weld")
			-- the phone cap: a crowd of golems never moves more limb parts than it allows
			rig.Eye = Vector3.new(0, 6, 15)
			rig.Phone = true
			Controller.useRig(rig)
			local crowd = {}
			for i = 1, 12 do
				table.insert(crowd, follower("PebbleGolem", i * 0.5))
			end
			now += 1
			for _, pet in crowd do
				Controller.golemOffset(pet, nil, now, true, true, 10)
			end
			local _, _, parts = Controller.golemStats()
			T.le(parts, Gait.Cap.Phone, "phone cap on limb parts")
			-- (GolemController destroys them; Lune can't read a destroyed instance, Roblox reads Parent = nil)
			for _, pet in crowd do
				pet.Model.Parent = nil
			end
			pebble.Model.Parent = nil
			king.Model.Parent = nil
			now += 1
			Controller.golemOffset(follower("PebbleGolem", 0), nil, now, false, true, 0)
			Controller.useRig(nil)
		end)
		rawset(Players, "LocalPlayer", hadLocal)
		AnimConfig.GolemMotion = hadGolems
		if not ok then
			error(err, 0)
		end
	end)

	-- (review anim/ship #10) the real frame loop, no rig: it lets go when the last running follower is destroyed
	T.test("GolemGait: the limb loop disconnects when the last running follower is gone (unequipped, its owner far)", function()
		local Players = Loader.game:GetService("Players")
		local RunService = Loader.game:GetService("RunService")
		local Workspace = Loader.game:GetService("Workspace")
		local UserInputService = Loader.game:GetService("UserInputService")
		local patched = {
			{ Players, "LocalPlayer", { Name = "Me", UserId = 1 } },
			{ RunService, "RenderStepped", nil },
			{ Workspace, "CurrentCamera", nil },
			{ Workspace, "BulkMoveTo", nil },
			{ UserInputService, "TouchEnabled", false },
			{ UserInputService, "MouseEnabled", true },
		}
		local saved = {}
		local connects, live = 0, 0
		local handler: ((number) -> ())? = nil
		patched[2][3] = {
			Connect = function(_, fn)
				connects += 1
				live += 1
				handler = fn
				local c: any = { Connected = true }
				function c.Disconnect(self)
					if self.Connected then
						self.Connected = false
						live -= 1
					end
				end
				return c
			end,
		}
		-- (far from the followers the tests before left behind: only this one is near the camera)
		patched[3][3] = {
			CFrame = CFrame.new(500, 6, 15),
			WorldToViewportPoint = function(_, p)
				return p, true
			end,
		}
		patched[4][3] = function(_, parts, frames)
			for i, part in parts do
				part.CFrame = frames[i]
			end
		end
		for i, p in patched do
			saved[i] = rawget(p[1], p[2])
			rawset(p[1], p[2], p[3])
		end
		local hadGolems = AnimConfig.GolemMotion
		AnimConfig.GolemMotion = true
		local ok, err = pcall(function()
			local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldMotionController")
			Controller.useRig(nil)
			local followers = Instance.new("Folder")
			local model = GolemBuilder.build("PebbleGolem", CFrame.new(500, 0, 0), { Welded = true, Size = FOLLOWER })
			model.Parent = followers
			local pet = {
				Kind = "PebbleGolem",
				Phase = 0,
				Seed = 3,
				Floats = false,
				Yaw = 0,
				Model = model,
				Root = model.PrimaryPart,
			}
			local now = 7000
			for _ = 1, 3 do
				now += 1 / 60
				Controller.golemOffset(pet, nil, now, true, true, 16)
				local step = handler
				if step then
					step(1 / 60)
				end
			end
			local _, running = Controller.golemStats()
			T.eq(running, 1, "near and on screen: its limbs run")
			local _, _, _, _, _, looping = Controller.costs()
			T.truthy(looping and live == 1, "the frame loop is connected")
			-- GolemController destroys it (Lune reads Parent = nil); nothing calls golemOffset for it again
			model.Parent = nil
			local step = handler :: (number) -> ()
			step(1 / 60)
			local _, after, parts = Controller.golemStats()
			T.eq(after, 0, "the destroyed follower left the running list")
			T.eq(parts, 0, "no limb parts counted")
			local _, _, _, _, _, still = Controller.costs()
			T.falsy(still, "the loop let go")
			T.eq(live, 0, "RenderStepped disconnected")
			T.eq(connects, 1, "one connection only")
			Controller.useRig(nil)
		end)
		for i, p in patched do
			rawset(p[1], p[2], saved[i])
		end
		AnimConfig.GolemMotion = hadGolems
		if not ok then
			error(err, 0)
		end
	end)
end
