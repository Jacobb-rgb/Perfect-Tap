-- Mine floor areas (src/server/World/Mine): the shared MineKit pieces and every floor
-- builder that exists keep the contract in MineKit's header (spawns, markers, budgets).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local MODULES = { "Floor1Quarry", "Floor2Ember", "Floor3Lagoon", "Floor4Palace", "Floor5Core" }

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
end
