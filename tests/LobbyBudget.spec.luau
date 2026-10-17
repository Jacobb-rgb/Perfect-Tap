--[[
	Map part budget with everything a server shows (lobby fix round 2): the
	built Map (the lobby packages, the land, the 8 plots with their yards)
	plus one ore node on every node spawn, built like the preview export
	(tools/lune/export_scene.luau world). It stays at least 200 parts under
	LobbyLayout.Budget.MapParts, so the ores on the podiums and in the pens
	(the yard preview adds ~220) still fit. The per-package budgets stay in
	tests/Lobby.spec.luau.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

	T.test("budget: the full map with plots, yards and ore nodes keeps 200 parts under MapParts", function()
		local game = roblox.Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local map = WorldBuilder.build(workspace)
		local mapParts = 0
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				mapParts += 1
			end
		end
		-- the plots and their yards are part of the built map
		T.truthy(map:FindFirstChild("Plots") and #map.Plots:GetChildren() == #WorldLayout.Plots, "the plots are built")
		local nodeParts = 0
		local folder = roblox.Instance.new("Folder")
		folder.Parent = workspace
		for index, spawn in WorldBuilder.generateNodeSpawns() do
			local zone = WorldLayout.ZoneById[spawn.Zone]
			local rng = Rng.new(index * 97 + 5)
			local node = OreNodeBuilder.build(rng:weighted(zone.Ores), roblox.CFrame.new(spawn.Position), index)
			node.Parent = folder
			for _, d in node:GetDescendants() do
				if d:IsA("BasePart") then
					nodeParts += 1
				end
			end
		end
		local total = mapParts + nodeParts
		local budget = LobbyLayout.Budget.MapParts
		T.le(mapParts, budget, `built map parts ({mapParts})`)
		T.le(total, budget - 200, `map + ore nodes ({total}) keep 200 parts for the podium and pen ores`)
	end)
end
