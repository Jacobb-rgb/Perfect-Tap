-- The owner's mine models (Meshy, 2026-11-13) in the mine floors: the elevator tower. Stand-in
-- templates (tools/lune/lib/mesh_fakes) play the upload here.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")

	local function lights(model)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("Light") then
				n += 1
			end
		end
		return n
	end

	T.test("mine meshes: the elevator stop is the owner's tower on the steel platform", function()
		Fakes(Loader, true)
		local holder = roblox.Instance.new("Model")
		local stop = MineKit.elevator(holder, CF.new(4, 2, 8), 3)
		local tower = stop:FindFirstChild("Tower")
		T.truthy(tower and tower:IsA("MeshPart"), "the tower mesh")
		T.eq(tower:GetAttribute("Asset"), "Prop_MineElevator", "asset")
		T.near(tower.Size.Y, MineKit.ElevatorTowerHeight, 1e-3, "tower height")
		T.near(tower.CFrame.Position.Y - tower.Size.Y / 2, 2.6, 1e-3, "standing on the platform")
		T.falsy(tower.CanCollide or tower.CanQuery, "the tower is a look")
		T.eq(stop.PrimaryPart and stop.PrimaryPart.Name, "Base", "PrimaryPart Base (arrival)")
		local panel = stop:FindFirstChild("CallPanel")
		T.truthy(panel and panel:FindFirstChild("PromptPoint"), "call panel prompt")
		T.truthy(stop:HasTag("MineElevator"), "tag")
		T.eq(stop:GetAttribute("Floor"), 3, "floor")
		T.falsy(stop:FindFirstChild("Pulley"), "no part frame")
		T.le(#stop:GetDescendants(), 90, "parts")
		-- (owner 2026-11-14: "lit": three warm lamps up the tower)
		T.eq(lights(stop), 3, "three lights")
		-- as tall as asked (a floor's ceiling) and as wide (he found it narrow)
		local tall = MineKit.elevator(holder, CF.new(40, 2, 8), 3, { Height = 31.4, Width = 12 })
		local tallTower = tall:FindFirstChild("Tower")
		T.near(tallTower.Size.Y, 31.4, 1e-3, "the asked height")
		T.near(tallTower.Size.X, 12, 1e-3, "the asked width")
		T.near(tallTower.CFrame.Position.Y + tallTower.Size.Y / 2, 2 + 0.6 + 31.4, 1e-3, "from the platform up to the ceiling")
		local base = tall:FindFirstChild("Base")
		T.le(tallTower.Size.X + 2.9, base.Size.X, "the platform round its foot")
		-- riders arrive on the plate in front of the wide tower, never inside it
		local arrivalZ = tall:GetAttribute("ArrivalZ")
		T.truthy(type(arrivalZ) == "number" and arrivalZ <= -(tallTower.Size.Z / 2 + 0.9), "arrival in front of the tower")
		T.truthy(arrivalZ > -base.Size.Z / 2, "arrival on the plate")
		local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
		local arrival = ElevatorService.arrivalCFrame(tall)
		local stopCF = ElevatorService.stopCFrame(tall)
		local lp = stopCF:PointToObjectSpace(arrival.Position)
		T.near(lp.Z, arrivalZ, 1e-3, "the service puts riders there")
		T.lt(lp.Z, -tallTower.Size.Z / 2 - 0.5, "in front of the tower's face")
		-- the call panel on the plate, beside the tower and in front of it
		local panel = tall:FindFirstChild("CallPanel")
		local pp = base.CFrame:PointToObjectSpace(panel.CFrame.Position)
		T.lt(math.abs(pp.X) + panel.Size.X / 2, base.Size.X / 2 + 0.01, "the panel on the plate")
		T.lt(tallTower.Size.X / 2, math.abs(pp.X) - panel.Size.X / 2 + 0.01, "beside the tower")
		T.lt(pp.Z + panel.Size.Z / 2, -tallTower.Size.Z / 2, "in front of the tower")
		Fakes.unmount(Loader)
	end)
end
