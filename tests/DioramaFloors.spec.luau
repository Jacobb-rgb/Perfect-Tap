-- The mine floors from the owner's dioramas (Mine/Diorama, Meshy 2026-11-13): with the upload every floor
-- is its diorama and keeps MineKit's floor contract (spawns, markers, budgets), players stand on its
-- ground boxes, and the lifts move to the diorama's spots. Stand-in templates play the upload.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local Diorama = Loader.requirePath("ServerScriptService.Server.World.Mine.Diorama")
	local DioramaData = Loader.requirePath("ServerScriptService.Server.World.Mine.DioramaData")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local MeshCatalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local MineAmbience = Loader.requirePath("ReplicatedStorage.Shared.Config.MineAmbience")
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

	T.test("diorama floors: no upload, no diorama (the part floors)", function()
		Fakes.unmount(Loader)
		for index = 1, 6 do
			T.falsy(MineFloors.usesDiorama(index), "floor " .. index)
			T.falsy(Diorama.has(index), "floor " .. index)
			T.eq(MineFloors.liftSpot(index), MineFloors.LiftSpots[index], "floor " .. index .. " lift spot")
		end
	end)

	T.test("diorama floors: every floor has data and tiles in the catalog", function()
		for _, floor in MineFloors.List do
			local data = DioramaData[floor.Id]
			T.truthy(data, floor.Id .. " data")
			T.truthy(MeshCatalog.Floors[floor.Id] and #MeshCatalog.Floors[floor.Id] >= 8, floor.Id .. " tiles")
			T.eq(#data.Boxes % 5, 0, floor.Id .. " boxes come in fives")
		end
	end)

	T.test("diorama floors: contract, spawns on the ground, markers and budgets", function()
		Fakes(Loader, true)
		for index, name in MODULES do
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
			T.truthy(Diorama.has(index), name .. " is its diorama")
			local folder = roblox.Instance.new("Folder")
			local origin = MineFloors.Placement[index]
			local model = Floor.build(folder, origin, { Cutaway = false })
			local label = name .. " (diorama)"
			T.eq(model.Name, "MineFloor" .. index, label .. " model name")
			T.eq(model:GetAttribute("Diorama"), true, label .. " built from the diorama")
			local tiles = model:FindFirstChild("Diorama")
			T.eq(#tiles:GetChildren(), #MeshCatalog.Floors[MineFloors.ByIndex[index].Id], label .. " every tile")
			for _, tile in tiles:GetChildren() do
				T.truthy(tile:IsA("MeshPart") and not tile.CanCollide and not tile.CanQuery, label .. " tiles are looks")
			end
			-- spawns: enough, some deep, each over a ground box near its height
			local ground = model:FindFirstChild("Ground"):GetChildren()
			local function groundUnder(p): number?
				local best: number? = nil
				for _, box in ground do
					local local_ = box.CFrame:PointToObjectSpace(p)
					local h = box.Size / 2
					if math.abs(local_.X) <= h.X + 0.01 and math.abs(local_.Z) <= h.Z + 0.01 then
						local top = box.CFrame.Position.Y + h.Y
						if top <= p.Y + 1.5 and (best == nil or top > best) then
							best = top
						end
					end
				end
				return best
			end
			local spawns = model:FindFirstChild("RockSpawns"):GetChildren()
			local deep = 0
			for _, s in spawns do
				if s:GetAttribute("Deep") == true then
					deep += 1
				end
				local p = s.CFrame.Position
				local top = groundUnder(p)
				T.truthy(top ~= nil and p.Y - top < 1.5, label .. " spawn on the ground at " .. tostring(p))
			end
			T.le(18, #spawns, label .. " >= 18 rock spawns")
			T.le(6, deep, label .. " >= 6 deep spawns")
			for _, marker in { "GiantSpawn", "Entrance" } do
				local m = model:FindFirstChild(marker)
				T.truthy(m, label .. " " .. marker)
				local top = groundUnder(m.CFrame.Position)
				T.truthy(top ~= nil and m.CFrame.Position.Y - top < 1.5, label .. " " .. marker .. " on the ground")
			end
			local elevator = model:FindFirstChild("Elevator")
			T.truthy(elevator and elevator:HasTag("MineElevator"), label .. " elevator stop")
			T.eq(elevator:GetAttribute("Floor"), index, label .. " elevator floor")
			T.truthy(model:FindFirstChild("BlasterGate", true), label .. " blaster gate")
			T.eq(model:FindFirstChild("BlasterGate", true):GetAttribute("MinBlaster"), MineFloors.ByIndex[index].MinBlaster, label .. " gate level")
			-- the lift where the diorama put it (floor 1 has none)
			local spot = MineFloors.liftSpot(index)
			local liftSpot = model:FindFirstChild("OreLiftSpot")
			if index == 1 then
				T.falsy(spot, label .. " no lift")
			else
				T.eq(spot, MineFloors.Dioramas[index].Lift, label .. " the diorama's lift spot")
				T.truthy(liftSpot, label .. " lift spot marked")
				T.near((liftSpot.PrimaryPart.CFrame.Position - origin:PointToWorldSpace(spot)).Magnitude, 0.5, 0.01, label .. " lift spot at liftSpot")
			end
			-- budgets
			local budget = if index <= 3 then MineKit.NearPartBudget else MineKit.PartBudget
			T.le(count(model, "BasePart"), budget, label .. " parts")
			T.le(count(model, "PointLight"), MineKit.LightBudget, label .. " lights")
			local ambience = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					error(label .. " unanchored part " .. d:GetFullName())
				end
				if d:IsA("Attachment") and d:HasTag(MineAmbience.Tag) then
					ambience += 1
				end
			end
			T.le(4, ambience, label .. " ambience spots")
			T.le(ambience, 8, label .. " ambience spots")
			if index == 6 then
				T.truthy(model:FindFirstChild("VoidCatcher"), label .. " void catcher")
			end
		end
		Fakes.unmount(Loader)
	end)
end
