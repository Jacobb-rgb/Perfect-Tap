-- Mine floor areas (src/server/World/Mine): the shared MineKit pieces and every floor
-- builder that exists keep the contract in MineKit's header (spawns, markers, budgets), and
-- the floors' boxes in the world keep clear of each other (the elevator-only ones).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local MODULES = { "Floor1Quarry", "Floor2Ember", "Floor3Lagoon", "Floor4Palace", "Floor5Storm", "Floor6Core" }

	local function count(model, className)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	T.test("MineKit: elevator, gate, ore lift, wall and crystals build", function()
		local folder = roblox.Instance.new("Folder")
		local elevator = MineKit.elevator(folder, CF.new(0, 0, 0), 4)
		T.eq(elevator:GetAttribute("Floor"), 4, "elevator floor")
		T.truthy(elevator:FindFirstChild("PromptPoint", true) ~= nil, "elevator prompt point")
		T.le(count(elevator, "BasePart"), 90, "elevator parts")
		T.le(count(elevator, "PointLight"), 1, "elevator lights")
		local gate = MineKit.gate(folder, CF.new(20, 0, 0), 12, 5, { roblox.Color3.new(0.5, 0.5, 0.5), roblox.Color3.new(0.7, 0.7, 0.7), roblox.Color3.new(0.3, 0.3, 0.3) })
		T.eq(gate:GetAttribute("MinBlaster"), 5, "gate level")
		local spot = MineKit.oreLift(folder, V3.new(40, 0, 0), "Test")
		T.eq(spot.Name, "OreLiftSpot", "in the game the floor only marks the lift's spot")
		T.eq(spot:GetAttribute("LiftId"), "Test", "spot lift id")
		MineKit.PreviewLifts = true
		local lift = MineKit.oreLift(folder, V3.new(40, 0, 0), "Test")
		MineKit.PreviewLifts = false
		T.truthy(lift:HasTag("MineLift"), "the preview builds the Mine Lift")
		local cluster = MineKit.crystals(folder, CF.new(0, 0, 20), 7, 6, "Shell", { roblox.Color3.new(0.2, 0.8, 0.9) }, 1)
		T.truthy(#cluster:GetChildren() >= 7, "cluster crystals")
	end)

	T.test("mine floor areas in the game: every floor <= 2500 parts, floors 1-3 <= 1250, no own ore lifts", function()
		-- the integrator's rule: FloorParts <= 2500 BaseParts per mine floor in the game build
		T.eq(MineKit.PartBudget, 2500, "MineKit.PartBudget")
		-- floors 1-3 stream in with the town (the quarry rim on phones): 1250 each
		T.eq(MineKit.NearPartBudget, 1250, "MineKit.NearPartBudget")
		T.le(MineKit.NearPartBudget, MineKit.PartBudget, "the near-town budget is the tighter one")
		for index, name in MODULES do
			local ok, Floor = pcall(Loader.requirePath, "ServerScriptService.Server.World.Mine." .. name)
			if ok and Floor then
				local folder = roblox.Instance.new("Folder")
				local model = Floor.build(folder, CF.new(0, 0, 0), { Cutaway = false })
				local parts = count(model, "BasePart")
				T.le(parts, MineKit.PartBudget, name .. " in-game parts")
				if index <= 3 then
					T.le(parts, MineKit.NearPartBudget, name .. " in-game parts (streams in with the town)")
				end
				local lift = model:FindFirstChild("MineLift", true)
				T.truthy(lift == nil or not lift:HasTag("MineLift"), name .. " builds no Mine Lift of its own in the game")
			end
		end
	end)

	T.test("mine floor areas: contract, spawns, markers and budgets", function()
		for index, name in MODULES do
			local ok, Floor = pcall(Loader.requirePath, "ServerScriptService.Server.World.Mine." .. name)
			if ok and Floor then
				for _, cutaway in { false, true } do
					local folder = roblox.Instance.new("Folder")
					local model = Floor.build(folder, CF.new(0, 0, 0), { Cutaway = cutaway })
					local label = name .. (if cutaway then " (cutaway)" else "")
					T.eq(model.Name, "MineFloor" .. index, label .. " model name")
					T.eq(Floor.Index, index, label .. " index")
					local spawns = model:FindFirstChild("RockSpawns")
					T.truthy(spawns ~= nil, label .. " RockSpawns")
					local total, deep = 0, 0
					for _, p in spawns:GetChildren() do
						total += 1
						if p:GetAttribute("Deep") == true then
							deep += 1
						end
					end
					T.truthy(total >= 18, label .. " has >= 18 rock spawns (" .. total .. ")")
					T.truthy(deep >= 6, label .. " has >= 6 deep spawns (" .. deep .. ")")
					T.truthy(model:FindFirstChild("GiantSpawn") ~= nil, label .. " GiantSpawn")
					T.truthy(model:FindFirstChild("Entrance") ~= nil, label .. " Entrance")
					T.truthy(model:FindFirstChild("Elevator", true) ~= nil, label .. " elevator stop")
					T.truthy(model:FindFirstChild("BlasterGate", true) ~= nil, label .. " blaster gate")
					T.le(count(model, "BasePart"), MineKit.PartBudget, label .. " parts")
					T.le(count(model, "PointLight"), MineKit.LightBudget, label .. " lights")
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and not d.Anchored then
							error(label .. " unanchored part " .. d:GetFullName())
						end
					end
				end
			end
		end
	end)

	-- the world-space box of a whole floor model (min, max)
	local function modelBox(model): (any, any)
		local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
				local h = d.Size / 2
				local e = V3.new(
					math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
					math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
					math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
				)
				lo = lo:Min(d.CFrame.Position - e)
				hi = hi:Max(d.CFrame.Position + e)
			end
		end
		return lo, hi
	end

	T.test("mine floor areas in the world: the elevator-only floors' boxes keep clear of every other floor", function()
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		T.eq(#MODULES, #MineFloors.List, "a builder per floor")
		local boxes = {}
		for index, name in MODULES do
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
			T.eq(Floor.Index, index, name .. " index = its MineFloors index")
			local model = Floor.build(roblox.Instance.new("Folder"), MineFloors.Placement[index], { Cutaway = false })
			local lo, hi = modelBox(model)
			boxes[index] = { Lo = lo, Hi = hi }
		end
		local GAP = 2 -- studs of air at least between two floors
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				-- (floors 1-3 are walked into each other: their tunnels and ramps may touch)
				if MineFloors.List[i].ViaElevator or MineFloors.List[j].ViaElevator then
					local a, b = boxes[i], boxes[j]
					local apart = a.Hi.X + GAP <= b.Lo.X
						or b.Hi.X + GAP <= a.Lo.X
						or a.Hi.Y + GAP <= b.Lo.Y
						or b.Hi.Y + GAP <= a.Lo.Y
						or a.Hi.Z + GAP <= b.Lo.Z
						or b.Hi.Z + GAP <= a.Lo.Z
					T.truthy(apart, `{MineFloors.List[i].Id} and {MineFloors.List[j].Id} keep {GAP} studs apart`)
				end
			end
		end
		-- the Rift sits between the palace above and the core's void enclosure below
		T.truthy(boxes[5].Hi.Y < boxes[4].Lo.Y and boxes[5].Lo.Y > boxes[6].Hi.Y, "the Rift between floors 4 and 6")
	end)

	---------------------------------------------------------------- the Stormglass Rift
	-- Floor 5 (gate 8) between the palace and the core: its own budgets and height band.
	local STORM_PARTS = 2400 -- the phase A target, under MineKit.PartBudget
	local STORM_Y = { -25, 60 } -- local height band: clear of floor 4 above and the core below

	-- the world-space box of a part (min, max)
	local function bounds(part): (any, any)
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
		local h = part.Size / 2
		local e = V3.new(
			math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
			math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
			math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
		)
		return part.CFrame.Position - e, part.CFrame.Position + e
	end

	T.test("stormglass rift: contract, spawns, markers, budgets and its height band", function()
		local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine.Floor5Storm")
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		T.eq(Floor.Id, "StormglassRift", "floor id")
		T.eq(Floor.Index, 5, "floor 5")
		T.eq(Floor.MinBlaster, 8, "blaster gate 8")
		T.eq(MineFloors.get(5).Id, Floor.Id, "MineFloors floor 5")
		T.eq(Floor.Palette, MineFloors.get(Floor.Id).Palette, "its palette lives in MineFloors")
		local origin = MineFloors.Placement[Floor.Index]
		for _, cutaway in { false, true } do
			local label = "StormglassRift" .. (if cutaway then " (cutaway)" else "")
			local model = Floor.build(roblox.Instance.new("Folder"), origin, { Cutaway = cutaway })
			T.eq(model.Name, "MineFloor5", label .. " model name")
			T.eq(model:GetAttribute("FloorId"), "StormglassRift", label .. " FloorId")
			local spawns = model:FindFirstChild("RockSpawns")
			T.truthy(spawns ~= nil, label .. " RockSpawns")
			local total, deep = 0, 0
			for _, p in spawns:GetChildren() do
				total += 1
				if p:GetAttribute("Deep") == true then
					deep += 1
				end
				local q = origin:PointToObjectSpace(p.CFrame.Position)
				T.truthy(math.abs(q.Y) < 0.01, label .. " spawn on the ground")
				T.eq(p:GetAttribute("Deep") == true, q.Z < 2, label .. " deep exactly past the rift")
			end
			T.truthy(total >= 24 and total <= 28, label .. " about 26 rock spawns (" .. total .. ")")
			T.truthy(deep >= 10, label .. " >= 10 deep spawns (" .. deep .. ")")
			T.truthy(model:FindFirstChild("GiantSpawn") ~= nil, label .. " GiantSpawn")
			T.truthy(model:FindFirstChild("Entrance") ~= nil, label .. " Entrance")
			local elevator = model:FindFirstChild("Elevator", true)
			T.truthy(elevator ~= nil and elevator:GetAttribute("Floor") == 5, label .. " elevator stop")
			local gate = model:FindFirstChild("BlasterGate", true)
			T.truthy(gate ~= nil and gate:GetAttribute("MinBlaster") == 8, label .. " BLASTER LV 8+ gate")
			local parts = count(model, "BasePart")
			T.le(parts, STORM_PARTS, label .. " parts")
			T.le(parts, MineKit.PartBudget, label .. " parts (MineKit.PartBudget)")
			T.le(count(model, "PointLight"), MineKit.LightBudget, label .. " lights")
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					if not d.Anchored then
						error(label .. " unanchored part " .. d:GetFullName())
					end
					local lo, hi = bounds(d)
					local a, b = origin:PointToObjectSpace(lo), origin:PointToObjectSpace(hi)
					if a.Y < STORM_Y[1] or b.Y > STORM_Y[2] then
						error(`{label} {d:GetFullName()} leaves the height band ({a.Y} .. {b.Y})`)
					end
					local s = Floor.Size
					if a.X < -s.X / 2 - 0.5 or b.X > s.X / 2 + 0.5 or a.Z < -s.Z / 2 - 0.5 or b.Z > s.Z / 2 + 0.5 then
						error(`{label} {d:GetFullName()} leaves the footprint`)
					end
				end
			end
		end
		-- in the game the floor only marks the lift's spot: Railway builds TrainConfig's "StormglassRift" lift there
		local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
		local liftCfg = nil
		for _, cfg in TrainConfig.Lifts do
			if cfg.Id == Floor.Id then
				liftCfg = cfg
			end
		end
		T.truthy(liftCfg ~= nil, "TrainConfig has the Rift's lift")
		T.eq(Floor.LiftSpot, MineFloors.LiftSpots[Floor.Index], "MineFloors.LiftSpots[5]")
		T.truthy((liftCfg.Position - origin:PointToWorldSpace(Floor.LiftSpot)).Magnitude < 0.01, "the lift stands on the Rift's spot")
		local built = Floor.build(roblox.Instance.new("Folder"), origin, { Cutaway = false })
		local spot = built:FindFirstChild("OreLiftSpot", true)
		T.truthy(spot ~= nil and spot:GetAttribute("LiftId") == "StormglassRift", "ore lift spot")
		local at = origin:PointToObjectSpace(spot.PrimaryPart.CFrame.Position)
		T.truthy((at - (Floor.LiftSpot + V3.new(0, 0.5, 0))).Magnitude < 0.01, "the spot is Floor.LiftSpot")
		local lift = built:FindFirstChild("MineLift", true)
		T.truthy(lift == nil or not lift:HasTag("MineLift"), "no Mine Lift of its own in the game")
	end)

	T.test("stormglass rift: 4-8 ambience spots of its kinds, at most 3 loops anywhere, no extra parts", function()
		local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine.Floor5Storm")
		local MineAmbience = Loader.requirePath("ReplicatedStorage.Shared.Config.MineAmbience")
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		local origin = MineFloors.Placement[Floor.Index]
		local model = Floor.build(roblox.Instance.new("Folder"), origin, { Cutaway = false })
		local kinds = MineAmbience.Floors[Floor.Id]
		T.truthy(kinds ~= nil, "MineAmbience.Floors.StormglassRift")
		local spots = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == "Attachment" and d:HasTag(MineAmbience.Tag) then
				table.insert(spots, d)
			end
		end
		T.truthy(#spots >= MineAmbience.SpotsPerFloor[1] and #spots <= MineAmbience.SpotsPerFloor[2], `4-8 spots ({#spots})`)
		local seen: { [string]: boolean } = {}
		local loops = {}
		local s = Floor.Size
		for _, spot in spots do
			local kind = spot:GetAttribute(MineAmbience.Attribute)
			T.truthy(table.find(kinds, kind), `{spot.Name}: {kind} is a Stormglass Rift kind`)
			T.eq(spot.Name, "Ambience" .. kind, spot.Name .. " name")
			seen[kind] = true
			local host = spot.Parent
			T.truthy(host:IsA("BasePart") and host:IsDescendantOf(model), spot.Name .. " rides on a part of the floor")
			T.truthy(host.Name ~= "RockSpawn" and host.Name ~= "GiantSpawn", spot.Name .. " not on a marker")
			local p = (host.CFrame * spot.CFrame).Position
			local q = origin:PointToObjectSpace(p)
			T.truthy(math.abs(q.X) <= s.X / 2 and math.abs(q.Z) <= s.Z / 2 and q.Y >= -s.Y / 2 and q.Y <= s.Y, spot.Name .. " inside the floor's box")
			for _, layer in MineAmbience.Kinds[kind] do
				if layer.Loop then
					table.insert(loops, { At = p, Reach = layer.MaxDistance })
				end
			end
		end
		for _, kind in kinds do
			T.truthy(seen[kind], "plays " .. kind)
		end
		local worst = 0
		for x = -s.X / 2, s.X / 2, 4 do
			for z = -s.Z / 2, s.Z / 2, 4 do
				for y = -10, 46, 4 do
					local p = origin:PointToWorldSpace(V3.new(x, y, z))
					local heard = 0
					for _, loop in loops do
						if (loop.At - p).Magnitude < loop.Reach then
							heard += 1
						end
					end
					worst = math.max(worst, heard)
				end
			end
		end
		T.le(worst, MineAmbience.MaxLoops, "loops heard at one point")
		local real = MineKit.ambience
		MineKit.ambience = function(_host, _kind, _at)
			return roblox.Instance.new("Attachment")
		end
		local ok, without = pcall(Floor.build, roblox.Instance.new("Folder"), origin, { Cutaway = false })
		MineKit.ambience = real
		T.truthy(ok, "builds without spots: " .. tostring(without))
		T.eq(count(model, "BasePart"), count(without, "BasePart"), "the spots add no parts")
	end)

	T.test("stormglass rift: storm rocks keep the rock budgets", function()
		local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine.Floor5Storm")
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
		local ok, err = pcall(function()
			for _, kind in { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" } do
				for seed = 1, 6 do
					local ores = if kind == "Giant" then {} else { "StormGem", "Moonstone", "Sunstone", "LeafGem" }
					while #ores > MineFloors.OreCount[kind] do
						table.remove(ores)
					end
					local rock = RockBuilder.build(Floor.Id, kind, ores, CF.new(0, 0, 0), seed * 11)
					T.le(count(rock, "BasePart"), RockBuilder.Budget[kind], `storm {kind} rock parts (seed {seed})`)
					T.le(count(rock, "PointLight"), 1, `storm {kind} rock lights`)
					T.eq(rock:GetAttribute("Floor"), Floor.Index, "rock floor")
					if kind ~= "Giant" then
						for stage = 1, MineFloors.OreCount[kind] - 1 do
							RockBuilder.applyStage(rock, stage, seed)
						end
					end
				end
			end
			-- the storm look is its own: stormglass crystals (see-through indigo) and lightning cracks
			local small = RockBuilder.build(Floor.Id, "Small", { "StormGem", "StormGem", "StormGem" }, CF.new(0, 0, 0), 3)
			local glass, veins = 0, 0
			for _, d in small:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Crystal" and d.Transparency > 0.2 then
					glass += 1
				elseif d:IsA("BasePart") and d.Name == "Vein" then
					veins += 1
				end
			end
			T.truthy(glass >= 3, "stormglass crystals on a storm rock")
			T.eq(veins, 4, "two zig-zag lightning cracks")
		end)
		if not ok then
			error(err, 0)
		end
	end)
end
