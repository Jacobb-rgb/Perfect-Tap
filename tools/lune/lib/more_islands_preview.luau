--[[
	Proposal: more floating islands round the map (owner 2026-10-21). Scene
	"more_islands" for tools/lune/export_scene.luau: the world plus
	Sky/MoreIslands (not in the map yet). Shots: the scratchpad's
	more_islands_shots.json (overview, spawn, hero and one per island).
]]

local Preview = {}

function Preview.build(Loader: any, workspace: any)
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local MoreIslands = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.MoreIslands")
	local SkyHaven = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.SkyHaven")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local map = WorldBuilder.build(workspace)
	local sky = map.Emberfall.Lobby:FindFirstChild("Sky") or map
	local m = MoreIslands.build(sky, Rng.new("Sky/MoreIslands"))
	local haven = SkyHaven.build(sky, Rng.new("Sky/SkyHaven"))
	local havenParts = 0
	for _, d in haven:GetDescendants() do
		if d:IsA("BasePart") then
			havenParts += 1
		end
	end
	print(string.format("[more_islands] sky haven %d parts", havenParts))
	local parts = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[more_islands] %d parts", parts))
	return map
end

return Preview
