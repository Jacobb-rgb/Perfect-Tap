--[[
	The Dragon King's royal cape (owner 2026-10-30): Builders/RoyalCape and
	the client's RoyalCapeController.

	  build        within RoyalCape.MaxParts at every size and under every
	               backpack; every part unanchored, massless, never
	               colliding, touching or queried; everything welded below
	               Root (Welds, no Motor6D); the hinges, the sparkles (off)
	  wearing      fits and attaches on R15 (UpperTorso) and R6 (Torso)
	               block characters, scaled with a big avatar, the hem clear
	               of the ground, the body untouched; under a backpack the
	               cape hangs from below the bag and the crest shows under it
	  flow         still at rest, lifted walking, more on a board, billowing
	               falling, swinging out turning; calm (Reduce motion) lifts
	               less and never waves; a walking R15's legs stay in front
	               of the flowing panels
	  controller   on when the Dragon King is equipped, off when unequipped,
	               one cape on re-equip, rebuilt for a respawn or another
	               backpack, off out of range, when the torso streams out and
	               when the player leaves; in the client's ORDER list
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance, Vector3 = roblox.Instance, roblox.Vector3
	local CFrame = Loader.CFrame
	local RoyalCape = Loader.requirePath("ReplicatedStorage.Shared.Builders.RoyalCape")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
	local Preview = require("../tools/lune/lib/cape_preview")

	local function parts(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- the lowest point of a part (world Y)
	local function bottom(part: any): number
		local low = math.huge
		local s = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					low = math.min(low, (part.CFrame * Vector3.new(x * s.X, y * s.Y, z * s.Z)).Y)
				end
			end
		end
		return low
	end

	-- a cape worn the controller's way, posed at rest
	local function wear(character: any, packId: string?): (any, any)
		local fit = RoyalCape.fit(character, packId)
		local cape = RoyalCape.build({ Scale = fit.Scale, Length = fit.Length, Pin = fit.Pin, Crest = fit.Crest })
		RoyalCape.attach(cape, fit.Torso)
		Preview.solve(cape)
		return cape, fit
	end

	local function checkBuilt(cape: any, label: string)
		local list = parts(cape)
		T.le(#list, RoyalCape.MaxParts, label .. ": within the part budget")
		T.eq(cape:GetAttribute("Parts"), #list, label .. ": its Parts attribute")
		T.eq(cape:GetAttribute(RoyalCape.SkipTag), true, label .. ": the studded style leaves it smooth")
		local root = cape.PrimaryPart
		T.truthy(root and root.Name == "Root" and root.Transparency == 1, label .. ": an invisible Root")
		for _, p in list do
			T.falsy(p.Anchored, label .. ": " .. p.Name .. " unanchored (welded)")
			T.truthy(p.Massless, label .. ": " .. p.Name .. " massless")
			T.falsy(p.CanCollide, label .. ": " .. p.Name .. " never collides")
			T.falsy(p.CanTouch, label .. ": " .. p.Name .. " never touches")
			T.falsy(p.CanQuery, label .. ": " .. p.Name .. " never queried")
			if p ~= root then
				local held = false
				for _, child in p:GetChildren() do
					if child:IsA("Weld") and child.Part1 == p and child.Part0 ~= nil then
						held = true
					end
				end
				T.truthy(held, label .. ": " .. p.Name .. " hangs on a Weld")
			end
		end
		for _, d in cape:GetDescendants() do
			T.falsy(d:IsA("Motor6D"), label .. ": no Motor6D")
		end
		-- every part is reached from Root through the welds (Preview.solve asserts it)
		Preview.solve(cape)
	end

	T.test("RoyalCape: the Dragon King's cape builds within budget, massless, never colliding, welded below Root", function()
		T.eq(RoyalCape.Golem, "DragonKing")
		T.truthy(GolemConfig.ById[RoyalCape.Golem] ~= nil, "the Dragon King is a golem kind")
		local cape = RoyalCape.build()
		checkBuilt(cape, "default")
		for _, name in { "CapeTop", "CapeMid", "CapeHem", "Mantle", "Clasp1", "Clasp2", "Ruby1", "Ruby2", "CrestCrown", "Hem" } do
			T.truthy(cape:FindFirstChild(name), "has " .. name)
		end
		T.eq(cape.CapeTop.Material, roblox.Enum.Material.Fabric, "velvet")
		local mid, hem = RoyalCape.hinges(cape)
		T.truthy(mid and hem, "two hinges")
		for _, hinge in { mid, hem } do
			T.eq(typeof(hinge:GetAttribute("RestC0")), "CFrame", hinge.Parent.Name .. "'s hinge remembers its rest")
		end
		local sparkle = cape:FindFirstChild("CapeSparkle", true)
		T.truthy(sparkle and sparkle:IsA("ParticleEmitter"), "the sparkles")
		T.falsy(sparkle.Enabled, "off until the controller turns them on")
		T.eq(sparkle.Texture, RoyalCape.Sparkle, "a built-in texture (no upload)")
		T.truthy(RoyalCape.Sparkle:find("^rbxasset://") ~= nil)
		-- other sizes, and under every backpack
		for _, o in { { Scale = 0.6 }, { Scale = 1.6, Length = 6 }, { Scale = 1, Length = 2.3, Pin = 2 } } do
			checkBuilt(RoyalCape.build(o), `scale {o.Scale}`)
		end
		for _, pack in BackpackData.List do
			local character = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0))
			checkBuilt(wear(character, pack.Id), pack.Id)
		end
	end)

	T.test("RoyalCape: wears() reads the equipped kinds", function()
		T.truthy(RoyalCape.wears("DragonKing"))
		T.truthy(RoyalCape.wears("PebbleGolem,DragonKing,EmberImp"))
		T.truthy(RoyalCape.wears("PebbleGolem, DragonKing"))
		T.falsy(RoyalCape.wears("DragonKingX"))
		T.falsy(RoyalCape.wears("PebbleGolem,MagmaWyvern"))
		T.falsy(RoyalCape.wears(""))
		T.falsy(RoyalCape.wears(nil))
		T.falsy(RoyalCape.wears(5))
	end)

	T.test("RoyalCape: fits and attaches on R15 (UpperTorso) and R6 (Torso), the body untouched", function()
		for _, rig in { "R15", "R6" } do
			local stage = Instance.new("Folder")
			local character = if rig == "R15" then Preview.r15(stage, CFrame.new(0, 3, 0)) else Preview.r6(stage, CFrame.new(0, 3, 0))
			local torsoName = if rig == "R15" then "UpperTorso" else "Torso"
			local before = {}
			for _, p in parts(character) do
				before[p.Name .. "|" .. tostring(p.CFrame.Position)] = tostring(p.Size)
			end
			local count = #character:GetDescendants()
			local cape, fit = wear(character, nil)
			T.eq(fit.Torso.Name, torsoName, rig .. ": hangs on the " .. torsoName)
			T.near(fit.Scale, 1, 1e-6, rig .. ": a 2-stud torso is scale 1")
			local weld = cape.PrimaryPart:FindFirstChild("CapeAttach")
			T.truthy(weld and weld.ClassName == "Weld", rig .. ": a Weld, not a Motor6D")
			T.truthy(weld.Part0 == fit.Torso and weld.Part1 == cape.PrimaryPart, rig .. ": Root welded to the torso")
			local anchor = fit.Torso.CFrame * RoyalCape.anchor(fit.Torso)
			T.near((cape.PrimaryPart.CFrame.Position - anchor.Position).Magnitude, 0, 1e-4, rig .. ": Root at the torso's top back")
			-- the hem clear of the ground (the feet at y = 0), below the knees
			local hem = bottom(cape.Hem)
			T.truthy(hem >= RoyalCape.HemClearance - 0.05 and hem <= 1.2, `{rig}: the hem {hem} above the ground, below the knees`)
			-- behind the back and inside the torso's width at the top
			local back = fit.Torso.CFrame:PointToObjectSpace(cape.CapeTop.CFrame.Position).Z - cape.CapeTop.Size.Z / 2
			T.truthy(back >= fit.Torso.Size.Z / 2 - 1e-4, rig .. ": the velvet behind the back")
			T.le(cape.CapeTop.Size.X, fit.Torso.Size.X, rig .. ": no wider than the torso at the top")
			-- nothing in the character changed, nothing put in it
			T.eq(#character:GetDescendants(), count, rig .. ": nothing added to the character")
			for _, p in parts(character) do
				T.eq(before[p.Name .. "|" .. tostring(p.CFrame.Position)], tostring(p.Size), rig .. ": " .. p.Name .. " unmoved, same size")
			end
			T.truthy(cape.Parent == nil, rig .. ": attach leaves parenting to the controller")
		end
		-- a big avatar gets a big cape; no torso or root yet: no fit
		local big = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0))
		big.UpperTorso.Size = Vector3.new(2.6, 2, 1.3)
		local fit = RoyalCape.fit(big, nil)
		T.near(fit.Scale, 1.3, 1e-4, "scaled to the torso's width")
		T.truthy(RoyalCape.build({ Scale = fit.Scale, Length = fit.Length, Pin = fit.Pin }).CapeTop.Size.X > 2.4, "a wider cape")
		local headless = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0))
		headless.UpperTorso:Destroy()
		T.eq(RoyalCape.fit(headless, nil), nil, "no torso: nothing to hang on")
		local rootless = Preview.r6(Instance.new("Folder"), CFrame.new(0, 3, 0))
		rootless.HumanoidRootPart:Destroy()
		T.eq(RoyalCape.fit(rootless, nil), nil, "no root yet: wait")
	end)

	T.test("RoyalCape: under a backpack the cape hangs from below the bag, the crest under it", function()
		for _, pack in BackpackData.List do
			local character = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0))
			local cape, fit = wear(character, pack.Id)
			T.truthy(fit.Pin >= pack.Size.Y * fit.Scale, pack.Id .. ": the first hinge below the bag")
			T.truthy(fit.Length - fit.Pin >= RoyalCape.MinFlow - 1e-6, pack.Id .. ": room to flow")
			-- the crest's top below the bag's bottom (BackpackWearController: the bag's top level with the torso's)
			local torso = fit.Torso
			local bagBottom = torso.Size.Y / 2 - pack.Size.Y * fit.Scale
			local crown = torso.CFrame:PointToObjectSpace(cape.CrestPoint2.CFrame.Position).Y + 0.1
			T.truthy(crown < bagBottom, `{pack.Id}: the crest ({crown}) under the bag ({bagBottom})`)
			T.truthy(bottom(cape.Hem) >= RoyalCape.HemClearance - 0.05, pack.Id .. ": the hem clear of the ground")
		end
		local fit = RoyalCape.fit(Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0)), "NoSuchPack")
		T.near(fit.Pin, RoyalCape.Pin, 1e-6, "an unknown pack id: as without a pack")
	end)

	T.test("RoyalCape: the flow (rest, walking, boards, falling, turning, Reduce motion)", function()
		local function settle(forward: number, side: number?, vertical: number?, turn: number?, calm: boolean?): { number }
			local state = RoyalCape.newFlow(0.4)
			local out = {}
			for _ = 1, 120 do
				out = { RoyalCape.step(state, 1 / 30, forward, side or 0, vertical or 0, turn or 0, calm == true) }
			end
			for _, v in out do
				T.truthy(v == v and math.abs(v) < 2, "a finite angle")
			end
			return out
		end
		local f = RoyalCape.Flow
		local still = settle(0)
		T.near(still[1], f.Rest[1], f.Breeze, "standing: hanging (a breeze)")
		T.near(still[3], f.Rest[2], f.Breeze * 1.5, "standing: CapeHem hanging too")
		local walk = settle(18)
		T.truthy(walk[1] > still[1] + 0.2, "walking lifts CapeMid")
		T.truthy(walk[1] + walk[3] > walk[1] + 0.15, "and CapeHem more (it curves)")
		local board = settle(45)
		T.truthy(board[1] > walk[1] + 0.15, "a board's speed lifts it further")
		local back = settle(-18)
		T.truthy(back[1] < walk[1] - 0.15, "walking backwards barely lifts it")
		local falling = settle(0, 0, -40)
		T.truthy(falling[1] > still[1] + 0.15, "falling billows it up")
		local left = settle(10, 0, 0, 2)
		local right = settle(10, 0, 0, -2)
		T.truthy(left[2] < 0 and right[2] > 0, "turning swings it out to the other side")
		-- calm: less lift, no wave (two steps in a row the same once settled)
		local calm = settle(18, 0, 0, 0, true)
		T.truthy(calm[1] < walk[1] - 0.05 and calm[1] > still[1], "calm: a smaller lift")
		T.eq(calm[2], 0, "calm: no swing")
		local state = RoyalCape.newFlow()
		for _ = 1, 200 do
			RoyalCape.step(state, 1 / 30, 18, 0, -40, 3, true)
		end
		local a = { RoyalCape.step(state, 1 / 30, 18, 0, -40, 3, true) }
		local b = { RoyalCape.step(state, 1 / 30, 18, 0, -40, 3, true) }
		T.near(a[1], b[1], 1e-6, "calm: no flutter")
		T.near(a[3], b[3], 1e-6, "calm: no flutter below")
		T.near(a[1], calm[1], 1e-3, "calm: no billow from falling")
		-- bend: the hinge turns from its rest
		local cape = RoyalCape.build()
		local mid = RoyalCape.hinges(cape)
		local rest = mid.C0
		RoyalCape.bend(mid, 0.5, 0)
		T.near(mid.C0.Position.Z, rest.Position.Z, 1e-6, "turns about the hinge")
		T.truthy((mid.C0.LookVector - rest.LookVector).Magnitude > 0.4, "turned")
		RoyalCape.bend(mid, 0, 0)
		T.truthy((mid.C0.LookVector - rest.LookVector).Magnitude < 1e-6, "back at rest")
	end)

	T.test("RoyalCape: a walking R15's legs stay in front of the flowing panels", function()
		for _, packId in { false, "RookiePack" } do
			local pack = if packId then packId else nil
			local character = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0), Preview.walkPose(1))
			local flow = Preview.flowAt(Loader, 18)
			local cape, fit = wear(character, pack)
			local need1, need2 = RoyalCape.clearance(RoyalCape.hingeFrame(cape), RoyalCape.shape(cape), RoyalCape.limbs(character), flow[1])
			local lift1, lift2 = RoyalCape.clear(RoyalCape.newFlow(), 10, flow[1], flow[3], need1, need2)
			local mid, hem = RoyalCape.hinges(cape)
			RoyalCape.bend(mid, lift1, 0)
			RoyalCape.bend(hem, lift2, 0)
			Preview.solve(cape)
			local label = pack or "no pack"
			local legs = {}
			for _, name in { "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" } do
				table.insert(legs, character[name])
			end
			local checked = 0
			for _, panel in { cape.CapeMid, cape.CapeHem } do
				for _, leg in legs do
					local s = leg.Size / 2
					for _, x in { -1, 1 } do
						for _, y in { -1, 1 } do
							for _, z in { -1, 1 } do
								local p = panel.CFrame:PointToObjectSpace(leg.CFrame * Vector3.new(x * s.X, y * s.Y, z * s.Z))
								if math.abs(p.X) < panel.Size.X / 2 and math.abs(p.Y) < panel.Size.Y / 2 then
									checked += 1
									-- (in front of the velvet's middle: nothing pokes out of its back)
									T.truthy(p.Z <= 0, `{label}: {leg.Name} in front of {panel.Name} ({p.Z})`)
								end
							end
						end
					end
				end
			end
			T.truthy(checked > 0, label .. ": the legs are behind the cape's width")
			T.truthy(fit.Pin > 0, label)
		end
		-- the flow alone would let the walking legs through: the push matters
		local character = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0), Preview.walkPose(1))
		local cape = wear(character, nil)
		local flow = Preview.flowAt(Loader, 18)
		local need1, need2 = RoyalCape.clearance(RoyalCape.hingeFrame(cape), RoyalCape.shape(cape), RoyalCape.limbs(character), flow[1])
		T.truthy(need1 > flow[1] + 0.02 or need2 > flow[1] + flow[3] + 0.02, "the heels push the cape past the flow's lift")
		-- standing still nothing pushes
		local idle = Preview.r15(Instance.new("Folder"), CFrame.new(0, 3, 0))
		local idleCape = wear(idle, nil)
		local n1, n2 =
			RoyalCape.clearance(RoyalCape.hingeFrame(idleCape), RoyalCape.shape(idleCape), RoyalCape.limbs(idle), RoyalCape.Flow.Rest[1])
		T.truthy(
			n1 <= RoyalCape.Flow.Rest[1] + 0.05 and n2 <= RoyalCape.Flow.Rest[1] + RoyalCape.Flow.Rest[2] + 0.05,
			"standing: hangs freely"
		)
	end)

	T.test(
		"RoyalCapeController: on with the Dragon King, off without, one cape, rebuilt on respawn / new pack, off out of range or streamed out",
		function()
			local Players = Loader.game:GetService("Players")
			local hadLocal = rawget(Players, "LocalPlayer")
			rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1 })
			local ok, Controller = pcall(Loader.requirePath, "StarterPlayer.StarterPlayerScripts.Client.Controllers.RoyalCapeController")
			rawset(Players, "LocalPlayer", hadLocal)
			T.truthy(ok, "RoyalCapeController loads: " .. tostring(Controller))
			local folder = Instance.new("Folder")
			local before = Controller.Container
			Controller.Container = folder
			local ran, err = pcall(function()
				local stage = Instance.new("Folder")
				local p = Instance.new("Player")
				p.Name = "Wearer"
				p.UserId = 4242
				local character = Preview.r15(stage, CFrame.new(0, 3, 0))
				p.Character = character
				local attr = GolemConfig.EquippedAttribute
				p:SetAttribute(attr, "PebbleGolem")
				T.eq(Controller.refresh(p, true), nil, "no Dragon King: no cape")
				T.eq(#folder:GetChildren(), 0)
				p:SetAttribute(attr, "PebbleGolem,DragonKing")
				local cape = Controller.refresh(p, true)
				T.truthy(cape ~= nil, "equipped: a cape")
				T.eq(#folder:GetChildren(), 1, "one cape")
				T.truthy(cape.PrimaryPart.CapeAttach.Part0 == character.UpperTorso, "on the UpperTorso")
				T.truthy(Controller.refresh(p, true) == cape, "refreshed again: the same cape")
				T.eq(#folder:GetChildren(), 1, "still one cape")
				-- unequip: off at once, the entry gone
				p:SetAttribute(attr, "PebbleGolem")
				T.eq(Controller.refresh(p, true), nil, "unequipped: off")
				T.eq(#folder:GetChildren(), 0, "removed")
				T.eq(Controller.wearers[p], nil, "forgotten")
				-- re-equip (twice): one cape
				p:SetAttribute(attr, "DragonKing")
				Controller.refresh(p, true)
				Controller.refresh(p, true)
				T.eq(#folder:GetChildren(), 1, "re-equipped: one cape, never two")
				-- another backpack: fitted again under it
				local first = Controller.refresh(p, true)
				p:SetAttribute(Controller.PackAttribute, "RookiePack")
				local packed = Controller.refresh(p, true)
				T.truthy(packed ~= first and packed ~= nil, "a new cape for the pack")
				T.eq(#folder:GetChildren(), 1, "the old one gone")
				T.truthy(packed:GetAttribute("Pin") > RoyalCape.Pin + 1, "hanging from below the bag")
				-- respawn: on the new character
				local respawned = Preview.r15(stage, CFrame.new(10, 3, 0))
				p.Character = respawned
				local again = Controller.refresh(p, true)
				T.truthy(again ~= packed and again.PrimaryPart.CapeAttach.Part0 == respawned.UpperTorso, "on the new character")
				T.eq(#folder:GetChildren(), 1, "one cape")
				-- out of range: dropped, the wearer remembered; back in range: built again
				T.eq(Controller.refresh(p, false), nil, "out of range: none")
				T.eq(#folder:GetChildren(), 0)
				T.truthy(Controller.wearers[p] ~= nil, "still a wearer")
				T.truthy(Controller.refresh(p, true) ~= nil, "in range again")
				-- the torso streams out: dropped (never left hanging on nothing); it comes back: built again
				local torso = respawned.UpperTorso
				torso.Parent = nil
				T.eq(Controller.refresh(p, true), nil, "no torso: no cape")
				T.eq(#folder:GetChildren(), 0, "the old cape gone")
				torso.Parent = respawned
				T.truthy(Controller.refresh(p, true) ~= nil, "the torso back: the cape back")
				-- a character still arriving (no parts yet): none
				p.Character = Instance.new("Model")
				T.eq(Controller.refresh(p, true), nil, "no torso yet: none")
				T.eq(#folder:GetChildren(), 0)
				-- the player leaves
				p.Character = respawned
				Controller.refresh(p, true)
				T.eq(#folder:GetChildren(), 1)
				Controller.remove(p)
				T.eq(#folder:GetChildren(), 0, "left: removed")
				T.eq(Controller.wearers[p], nil, "forgotten")
				-- an R6 wearer: on the Torso
				local r6 = Instance.new("Player")
				r6.UserId = 77
				r6.Character = Preview.r6(stage, CFrame.new(20, 3, 0))
				r6:SetAttribute(attr, "DragonKing")
				local r6Cape = Controller.refresh(r6, true)
				T.truthy(r6Cape and r6Cape.PrimaryPart.CapeAttach.Part0.Name == "Torso", "R6: on the Torso")
				Controller.remove(r6)
			end)
			Controller.Container = before
			if not ran then
				error(err, 0)
			end
			local init = fs.readFile("src/client/init.client.luau")
			T.truthy(init:find('"RoyalCapeController"', 1, true) ~= nil, "in the client's ORDER list")
		end
	)
end
