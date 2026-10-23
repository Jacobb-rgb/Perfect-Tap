--[[
	Owner test place: copies a baked place and adds a Studio-only script that
	unlocks everything for every player (blaster 10, the elevator, all
	hoverboards, lots of coins). Used for HRA_K_TESTOVANI/*_TEST_vse_odemceno_*.rbxl.

	lune run tools/lune/make_test_place.luau build/TerraForge.rbxl <out.rbxl>
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local src, dst = process.args[1], process.args[2]
assert(src and dst, "usage: lune run tools/lune/make_test_place.luau <in.rbxl> <out.rbxl>")
local game = roblox.deserializePlace(fs.readFile(src))
local sss = game:GetService("ServerScriptService")
local script = roblox.Instance.new("Script")
script.Name = "TEST_VseOdemceno"
script.Source = [[
-- TEST FILE ONLY: in Roblox Studio every player starts with everything unlocked
-- (blaster 10, the elevator, all hoverboards, lots of coins). Delete this script for the real game.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local Services = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local BOARDS = { "TimberDrifter", "CartCruiser", "EmberglassGlider", "NeonComet", "RoyalPhoenix" }
local function unlock(player)
	for _ = 1, 150 do
		local data = DataService.get(player)
		if data then
			data.Coins = math.max(tonumber(data.Coins) or 0, 1e15)
			data.BlasterLevel = 10
			data.Upgrades = data.Upgrades or {}
			data.Upgrades.Elevator = true
			data.Hoverboards = data.Hoverboards or { Owned = {}, Equipped = "", Passes = {} }
			data.Hoverboards.Owned = data.Hoverboards.Owned or {}
			for _, id in BOARDS do
				data.Hoverboards.Owned[id] = true
			end
			data.Hoverboards.Equipped = "RoyalPhoenix"
			DataService.changed(player)
			print("[TEST] everything unlocked for " .. player.Name)
			return
		end
		task.wait(0.2)
	end
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(unlock, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(unlock, player)
end
]]
script.Parent = sss
fs.writeFile(dst, roblox.serializePlace(game))
print("wrote " .. dst)
