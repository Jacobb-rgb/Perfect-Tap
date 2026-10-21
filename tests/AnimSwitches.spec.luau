-- The AnimConfig switches of the world animations (Controllers/WorldMotionController): what ships (golems ON, world
-- effects OFF), "off" costs nothing (no remote listened to, no rock scan or cache, no pool, no frame loop asked for,
-- no chunk ever hidden), GolemMotion off = GolemController's own motion (identity, nothing tracked, running limbs back
-- on their welds), and with it on the hook composes cleanly with GolemController's own placement (its hop is taken
-- out exactly: the golem's frame doesn't depend on it), Reduce motion with the switches.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local CFrame = roblox.CFrame
	local Instance = roblox.Instance
	local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Gait = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GolemGait")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")

	local FOLLOWER = 0.85

	-- Runs `body(Controller, rig)` with the switches set, the local player stubbed and every patch put back.
	local function with(worldFx: boolean, golems: boolean, body: (any, any) -> ())
		local Players = Loader.game:GetService("Players")
		local hadLocal = rawget(Players, "LocalPlayer")
		local hadFx, hadGolems = AnimConfig.WorldFx, AnimConfig.GolemMotion
		rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1 })
		AnimConfig.WorldFx, AnimConfig.GolemMotion = worldFx, golems
		local ok, err = pcall(function()
			local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldMotionController")
			local rig = {
				Folder = Instance.new("Folder"),
				Eye = Vector3.new(0, 6, 15),
				Right = Vector3.new(1, 0, 0),
				Up = Vector3.new(0, 1, 0),
				Ground = 0,
				Clock = 3000,
				Phone = false,
				Reduce = false,
				Firing = true,
				Root = Vector3.new(0, 3, 6),
				Gravity = 196.2,
			}
			Controller.useRig(rig)
			body(Controller, rig)
			Controller.useRig(nil)
		end)
		rawset(Players, "LocalPlayer", hadLocal)
		AnimConfig.WorldFx, AnimConfig.GolemMotion = hadFx, hadGolems
		if not ok then
			error(err, 0)
		end
	end

	local function follower(kind: string, x: number, parent: any): any
		local model = GolemBuilder.build(kind, CFrame.new(x, 0, 0), { Welded = true, Size = FOLLOWER })
		model.Parent = parent
		return {
			Kind = kind,
			Phase = 0,
			Seed = x + 1,
			Floats = (model:GetAttribute("Hover") or 0) > 0,
			Yaw = 0,
			Model = model,
			Root = model.PrimaryPart,
		}
	end

	T.test("AnimSwitches: what ships: the golems run, the world effects are built but off", function()
		T.eq(AnimConfig.GolemMotion, true, "GolemMotion on (the owner said yes)")
		T.eq(AnimConfig.WorldFx, false, "WorldFx off until the owner says yes")
	end)

	T.test("AnimSwitches: WorldFx off costs nothing: no remote, no rock scan, no pool, no loop, no chunk hidden", function()
		with(false, false, function(Controller, rig)
			local pools0, rocks0, fxAsks0, golemAsks0, listens0 = Controller.costs()
			-- init / start connect nothing (both switches off): Net, the Rock tag and Players are never touched
			local CollectionService = Loader.game:GetService("CollectionService")
			local Players = Loader.game:GetService("Players")
			local touched = {}
			local saved = {
				{ Net, "listen", rawget(Net, "listen") },
				{ CollectionService, "GetTagged", rawget(CollectionService, "GetTagged") },
				{ CollectionService, "GetInstanceAddedSignal", rawget(CollectionService, "GetInstanceAddedSignal") },
				{ Players, "GetPlayers", rawget(Players, "GetPlayers") },
				{ Players, "PlayerAdded", rawget(Players, "PlayerAdded") },
			}
			for _, entry in saved do
				local name = entry[2]
				rawset(entry[1], name, function()
					table.insert(touched, name)
					error("touched " .. name)
				end)
			end
			local ok, err = pcall(function()
				Controller.init()
				Controller.start()
			end)
			for _, entry in saved do
				rawset(entry[1], entry[2], entry[3])
			end
			T.truthy(ok, "init / start with everything off: " .. tostring(err))
			T.eq(#touched, 0, "nothing connected: " .. table.concat(touched, ", "))
			T.eq(Controller.connected.WorldFx, false)
			T.eq(Controller.connected.GolemMotion, false)
			-- every world hook returns at once
			local items = Instance.new("Folder")
			local chunk = ItemBuilder.build({ Kind = "Raw", OreId = "Copper" }, CFrame.new(0, 4, 1), 3)
			chunk:SetAttribute("Kind", "Raw")
			chunk:SetAttribute("State", "Loose")
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
			chunk.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 16, 6)
			chunk.Parent = items
			Controller.onFx("NodeCrack", Vector3.new(0, 2.5, 1.5), Color3.fromRGB(150, 130, 110), 2, nil, 4)
			Controller.onItemAdded(chunk)
			Controller.onFx("NodeShatter", Vector3.new(0, 2, 0), Color3.new(0.5, 0.5, 0.5), Color3.new(1, 0.5, 0), 1, "Big", 2)
			Controller.onFx("BlastHit", Vector3.new(0, 2, 0), Color3.new(1, 0.5, 0), 1, { Name = "Other" })
			local rock = Instance.new("Model")
			local stone = Instance.new("Part")
			stone.CFrame = CFrame.new(0, 2, 0)
			stone.Parent = rock
			rock.PrimaryPart = stone
			Controller.onHealthDrop(rock)
			Controller.onEarned({ Source = "Sell", Position = Vector3.new(2, 0, 0), Count = 9, Amount = 300 })
			for _ = 1, 30 do
				rig.Clock += 1 / 30
				Controller.step(1 / 30)
			end
			for _, d in chunk:GetDescendants() do
				if d:IsA("BasePart") then
					T.eq(d.LocalTransparencyModifier, 0, "the real chunk is never hidden")
				end
			end
			local bits, pops, flashes = Controller.stats()
			T.eq(bits + pops + flashes, 0, "nothing shown")
			local pools1, rocks1, fxAsks1, golemAsks1, listens1, looping = Controller.costs()
			T.eq(pools1, pools0, "no pool made")
			T.eq(rocks1, rocks0, "no rock cached")
			T.eq(fxAsks1, fxAsks0, "the frame loop never asked for")
			T.eq(golemAsks1, golemAsks0)
			T.eq(listens1, listens0, "no remote listened to")
			T.falsy(looping, "no frame loop connected")
			T.eq(#rig.Folder:GetChildren(), 0, "no part made")
		end)
	end)

	T.test("AnimSwitches: GolemMotion off = GolemController's own motion: identity, nothing tracked, limbs back on welds", function()
		local followers = Instance.new("Folder")
		local pet
		with(true, true, function(Controller, rig)
			-- running limbs first (switch on) ...
			pet = follower("PebbleGolem", 0, followers)
			local now = 4000
			for _ = 1, 20 do
				now += 1 / 60
				pet.Root.CFrame = CFrame.new(0, 1, 0) * Controller.golemOffset(pet, nil, now, true, true, 16)
				Controller.step(1 / 60)
			end
			local leg = pet.Model:FindFirstChild("Leg1")
			T.truthy(leg.Anchored, "running with the switch on")
			-- ... then the switch goes off: identity, and the limbs go back on their welds at rest
			AnimConfig.GolemMotion = false
			local known0, _, _ = Controller.golemStats()
			local _, _, _, asks0 = Controller.costs()
			local offset = Controller.golemOffset(pet, nil, now + 1, true, true, 16)
			T.eq(offset, CFrame.identity, "off: GolemController's own motion only")
			T.falsy(leg.Anchored, "the leg is back on its weld")
			T.truthy(leg:FindFirstChildOfClass("WeldConstraint").Enabled, "weld on")
			local fresh = follower("DiamondDuke", 3, followers)
			for i = 1, 30 do
				T.eq(Controller.golemOffset(fresh, nil, now + 2 + i / 60, true, true, 20), CFrame.identity, "every frame")
			end
			local known1, running1, parts1 = Controller.golemStats()
			T.eq(known1, known0, "no new follower tracked")
			T.eq(running1 + parts1, 0, "nothing running")
			local _, _, _, asks1 = Controller.costs()
			T.eq(asks1, asks0, "the golems never asked for the frame loop")
			T.falsy(fresh.Model:FindFirstChild("Leg1").Anchored, "a new golem keeps its welds")
			-- (gone: GolemController would destroy them; Lune reads Parent = nil)
			pet.Model.Parent = nil
			fresh.Model.Parent = nil
			local _ = rig
		end)
	end)

	T.test("AnimSwitches: with running limbs the hook takes GolemController's hop out exactly (they don't fight)", function()
		with(false, true, function(Controller, rig)
			local followers = Instance.new("Folder")
			local pet = follower("PebbleGolem", 0, followers)
			local now = 5000
			-- GolemController's own placement (stepPets) with its hop, times the hook
			local function place(phase: number, speed: number, walking: boolean): any
				pet.Phase = phase
				local k = math.clamp(speed / 10, 0, 1)
				local y = if walking then math.abs(math.sin(phase)) * 0.55 * k else 0
				local pitch = if walking then -0.12 * k else 0
				local roll = if walking then math.sin(phase) * 0.08 * k else 0
				local offset = Controller.golemOffset(pet, nil, now, walking, true, speed)
				return CFrame.new(2, y + 1, -3) * CFrame.Angles(0, 0.4, 0) * CFrame.Angles(pitch, 0, roll) * offset
			end
			for _ = 1, 40 do
				now += 1 / 60
				pet.Root.CFrame = place(now * 3, 16, true)
				Controller.step(1 / 60)
			end
			T.truthy(pet.Model:FindFirstChild("Leg1").Anchored, "its limbs run")
			-- the same frame (same clock) with very different hop phases: the same golem frame
			local a = place(0, 16, true)
			local b = place(math.pi / 2, 16, true) -- GolemController's hop at its highest
			local c = place(2.2, 16, true)
			T.near((a.Position - b.Position).Magnitude, 0, 1e-4, "its hop never shows through")
			T.near((a.Position - c.Position).Magnitude, 0, 1e-4)
			T.near(a.LookVector:Dot(b.LookVector), 1, 1e-6, "nor its tilt")
			-- and GolemController still decides where it is and where it faces: only lift, lean and bank are added
			T.near(Vector3.new(a.Position.X - 2, 0, a.Position.Z + 3).Magnitude, 0, 0.05, "on its spot")
			local flat = Vector3.new(a.LookVector.X, 0, a.LookVector.Z).Unit
			local want = CFrame.Angles(0, 0.4, 0).LookVector
			T.truthy(flat:Dot(want) > 0.99, "facing where GolemController turned it")
			local _ = rig
		end)
	end)

	T.test("AnimSwitches: Reduce motion works with the switches on (golems calmer) and the gait makes no tables per frame", function()
		with(false, true, function(Controller, rig)
			local followers = Instance.new("Folder")
			local pet = follower("PebbleGolem", 0, followers)
			local now = 6000
			local function swing(): number
				local most = 0
				for _ = 1, 60 do
					now += 1 / 60
					pet.Phase += 0.3
					pet.Root.CFrame = CFrame.new(0, 1, 0) * Controller.golemOffset(pet, nil, now, true, true, 16)
					Controller.step(1 / 60)
					local leg = pet.Model:FindFirstChild("Leg1")
					local rest = pet.Root.CFrame * CFrame.new(-0.3 * FOLLOWER, (0.25 - 0.975) * FOLLOWER, 0.02 * FOLLOWER)
					most = math.max(most, (leg.CFrame.Position - rest.Position).Magnitude)
				end
				return most
			end
			local full = swing()
			rig.Reduce = true
			Controller.useRig(rig)
			local calm = swing()
			T.truthy(calm < full * 0.75, "Reduce motion: a smaller swing (" .. calm .. " vs " .. full .. ")")
			rig.Reduce = false
			Controller.useRig(rig)
		end)
		-- the per-frame gait maths fills its tables in place
		local g = Gait.newGait(0, 0)
		local pose = Gait.newPose()
		local before = pose
		for i = 1, 30 do
			Gait.step(g, i / 60, 16, 0, 0.85)
			Gait.pose(pose, g, i / 60, 0.85, false, 1, nil, 0.95, false)
		end
		T.eq(pose, before, "the same pose table every frame")
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Effects/GolemGait.luau")
		local stepBody = string.match(source, "function GolemGait%.step%(.-\nend\n") or ""
		local poseBody = string.match(source, "function GolemGait%.pose%(.-\nend\n") or ""
		T.truthy(#stepBody > 0 and #poseBody > 0, "found the per-frame functions")
		T.falsy(string.find(stepBody, "{", 1, true), "GolemGait.step makes no table")
		T.falsy(string.find(poseBody, "{", 1, true), "GolemGait.pose makes no table")
	end)
end
