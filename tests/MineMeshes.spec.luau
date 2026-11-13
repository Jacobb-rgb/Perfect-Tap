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
		T.eq(lights(stop), 1, "one light")
		Fakes.unmount(Loader)
	end)
end
