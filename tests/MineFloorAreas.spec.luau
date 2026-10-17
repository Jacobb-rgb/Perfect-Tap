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
		local lift = MineKit.oreLift(folder, V3.new(40, 0, 0), "Test")
		T.truthy(lift:HasTag("MineLift"), "ore lift is a Mine Lift")
		local cluster = MineKit.crystals(folder, CF.new(0, 0, 20), 7, 6, "Shell", { roblox.Color3.new(0.2, 0.8, 0.9) }, 1)
		T.truthy(#cluster:GetChildren() >= 7, "cluster crystals")
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
