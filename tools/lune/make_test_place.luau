--[[
	Owner test place: copies a baked place and adds a Studio-only script that
	unlocks everything for every player (blaster 10, all hoverboards, lots of
	coins; the elevator floors 4-6 are left to buy in its window). Used for
	HRA_K_TESTOVANI/*_TEST_vse_odemceno_*.rbxl.

	lune run tools/lune/make_test_place.luau build/TerraForge.rbxl <out.rbxl> [trace] [eggtest]

	"trace" also adds tools/lune/test_place/egg_trace.client.luau: a Studio-only panel that says what blocks the next egg.
	"eggtest" also adds tools/lune/test_place/egg_selftest.client.luau: in Studio the egg opening plays itself
	(1 / 3 / 10 eggs, a Legendary, a Mythic, a pack, Auto) and says [EGG TEST] PASS / FAIL for each in Output.
	"vip" also adds tools/lune/test_place/vip_pass.server.luau: in Studio every player has the Forgemaster's
	Pass perk ForgeVip, so their plot's VIP cave opens and its rocks grow (owner 2026-11-17).
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
-- (blaster 10, all hoverboards, lots of coins: buy the elevator floors in its window). Delete this script for the real game.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local Services = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local BOARDS = { "TimberDrifter", "CartCruiser", "EmberglassGlider", "RoyalPhoenix", "TerraForgeCustom" }
local function unlock(player)
	for _ = 1, 150 do
		local data = DataService.get(player)
		if data then
			data.Coins = math.max(tonumber(data.Coins) or 0, 1e15)
			data.BlasterLevel = 10
			-- (floors 4-6 stay to buy in the ELEVATOR window: the coins above are plenty)
			data.Hoverboards = data.Hoverboards or { Owned = {}, Equipped = "", Passes = {} }
			data.Hoverboards.Owned = data.Hoverboards.Owned or {}
			for _, id in BOARDS do
				data.Hoverboards.Owned[id] = true
			end
			data.Hoverboards.Equipped = "TerraForgeCustom"
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
local extras = { [process.args[3] or ""] = true, [process.args[4] or ""] = true, [process.args[5] or ""] = true }
if extras.trace then
	local trace = roblox.Instance.new("LocalScript")
	trace.Name = "TEST_VejceStopa"
	trace.Source = fs.readFile("tools/lune/test_place/egg_trace.client.luau")
	trace.Parent = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
end
if extras.eggtest then
	local test = roblox.Instance.new("LocalScript")
	test.Name = "TEST_VejceAutoTest"
	test.Source = fs.readFile("tools/lune/test_place/egg_selftest.client.luau")
	test.Parent = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
end
if extras.vip then
	local vip = roblox.Instance.new("Script")
	vip.Name = "TEST_VipPas"
	vip.Source = fs.readFile("tools/lune/test_place/vip_pass.server.luau")
	vip.Parent = sss
end
fs.writeFile(dst, roblox.serializePlace(game))
-- Lune drops the texture packs it can't read: put them back (tools/meshy/texture_packs.mjs)
local packs = process.spawn("node", { "tools/meshy/texture_packs.mjs", "inject", dst })
print((string.gsub(packs.stdout .. packs.stderr, "%s+$", "")))
assert(packs.ok, "texture_packs.mjs inject failed")
print("wrote " .. dst)
