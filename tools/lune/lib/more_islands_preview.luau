--[[
	More floating islands and SKY HAVEN (owner 2026-10-21): scene "more_islands" for
	tools/lune/export_scene.luau, the world (Sky.build makes them, Sky/MoreIslands and
	Sky/SkyHaven) with their part counts printed. Shots: the scratchpad's more_islands_shots.json.
]]

local Preview = {}

function Preview.build(Loader: any, workspace: any)
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local map = WorldBuilder.build(workspace)
	for _, name in { "MoreIslands", "SkyHaven" } do
		local m = map:FindFirstChild(name, true)
		local parts = 0
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
		end
		print(string.format("[more_islands] %s %d parts", name, parts))
	end
	return map
end

return Preview
