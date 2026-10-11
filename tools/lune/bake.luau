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

local basePath = root .. "/build/TerraForge.base.rbxl"
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

fs.writeFile(root .. "/build/TerraForge.rbxl", roblox.serializePlace(place))
fs.removeFile(basePath)
print(string.format("Baked map v%d with %d parts -> build/TerraForge.rbxl", WorldBuilder.Version, parts))
