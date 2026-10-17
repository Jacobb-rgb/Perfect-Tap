--[[
	Preview gallery of the Kenney kit models rebuilt from boxes
	(src/server/World/Lobby/Backdrop/Horizon/Kenney/*):
	  lune run tools/lune/export_scene.luau horizon_kenney
	Every model stands on a grey pad in a row, 40 studs apart, longest side
	30 studs, facing the camera (+Z).
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local Gallery = {}

function Gallery.build(Loader: any, workspace: any)
	local Blocks = Loader.requirePath("ServerScriptService.Server.World.Lobby.Backdrop.Horizon.Blocks")
	local names = {}
	for _, file in fs.readDir("src/server/World/Lobby/Backdrop/Horizon/Kenney") do
		local name = string.match(file, "^(.-)%.luau$")
		if name and name ~= "init" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local ground = roblox.Instance.new("Part")
	ground.Anchored = true
	ground.Size = roblox.Vector3.new(60 + #names * 40, 1, 120)
	ground.CFrame = roblox.CFrame.new((#names - 1) * 20, -0.5, 0)
	ground.Color = roblox.Color3.fromRGB(70, 74, 90)
	ground.Parent = workspace
	for i, name in names do
		local data = Loader.requirePath("ServerScriptService.Server.World.Lobby.Backdrop.Horizon.Kenney." .. name)
		local at = roblox.Vector3.new((i - 1) * 40, 0, 0)
		Blocks.build(workspace, data, roblox.CFrame.lookAt(at, at + roblox.Vector3.new(0, 0, 1)), 30, { Name = name })
		print(string.format("%-16s %4d parts", name, #data.Boxes // 7))
	end
end

return Gallery
