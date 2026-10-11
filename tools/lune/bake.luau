--[[
	Bakes the generated map into the Rojo-built place file.

	  rojo build -o build/TerraForge.base.rbxl
	  lune run tools/lune/bake.luau
	  -> build/TerraForge.rbxl (open this in Roblox Studio)

	Usually you just run tools/build.sh, which does both.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

-- args: [basePlace] [outputPlace] (unique temp names let several builds run at once)
local basePath = process.args[1] or (root .. "/build/TerraForge.base.rbxl")
local outputPath = process.args[2] or (root .. "/build/TerraForge.rbxl")
if not fs.isFile(basePath) then
	error("Missing " .. basePath .. " - run: rojo build -o build/TerraForge.base.rbxl")
end

local place = roblox.deserializePlace(fs.readFile(basePath))
local workspace = place:GetService("Workspace")

local existing = workspace:FindFirstChild("Map")
if existing then
	existing:Destroy()
end

local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local map = WorldBuilder.build(workspace)

local parts = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

local tempOut = outputPath .. ".tmp"
fs.writeFile(tempOut, roblox.serializePlace(place))
fs.move(tempOut, outputPath, true)
fs.removeFile(basePath)
print(string.format("Baked map v%d with %d parts -> build/TerraForge.rbxl", WorldBuilder.Version, parts))
