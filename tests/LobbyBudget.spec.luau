--[[
	Map part budget with everything a server shows (lobby fix round 2): the
	built Map (the lobby packages, the land, the 8 plots with their yards)
	plus one ore node on every node spawn, built like the preview export
	(tools/lune/export_scene.luau world), plus the artifact museum
	ArtifactService builds into every plot's yard at server start (steps
	6-7, MuseumBuilder, empty: the found relics come with the players). It
	stays at least 200 parts under LobbyLayout.Budget.MapParts, so the ores
	on the podiums and in the pens (the yard preview adds ~220) still fit;
	the museums are inside the lobby area, so they count toward LobbyParts
	too. The per-package budgets stay in tests/Lobby.spec.luau.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MuseumBuilder = Loader.requirePath("ServerScriptService.Server.World.MuseumBuilder")

	T.test("budget: the full map with plots, yards, museums and ore nodes keeps 200 parts under MapParts", function()
		local game = roblox.Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local map = WorldBuilder.build(workspace)
		local mapParts, lobbyParts = 0, 0
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				mapParts += 1
				if LobbyLayout.inArea(d.CFrame.Position) then
					lobbyParts += 1
				end
			end
		end
		-- one empty museum per plot yard, as ArtifactService builds them
		local museumParts, museumLobbyParts = 0, 0
		for _, plot in WorldLayout.Plots do
			local museum = MuseumBuilder.build(WorldLayout.plotCFrame(plot))
			for _, d in museum:GetDescendants() do
				if d:IsA("BasePart") then
					museumParts += 1
					if LobbyLayout.inArea(d.CFrame.Position) then
						museumLobbyParts += 1
					end
				end
			end
		end
		T.le(
			lobbyParts + museumLobbyParts,
			LobbyLayout.Budget.LobbyParts,
			`lobby parts with the museums ({lobbyParts} + {museumLobbyParts})`
		)
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
		local total = mapParts + nodeParts + museumParts
		local budget = LobbyLayout.Budget.MapParts
		T.le(mapParts, budget, `built map parts ({mapParts})`)
		T.le(total, budget - 200, `map + ore nodes + museums ({total}) keep 200 parts for the podium and pen ores`)
	end)
end
