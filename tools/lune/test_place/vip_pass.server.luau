-- TEST FILE ONLY (tools/lune/make_test_place.luau ... vip), Studio only: every player has the Forgemaster's
-- Pass perk ForgeVip, so their own plot's VIP cave opens (World/PlotCave, AccessController) and its 5
-- Glimmer Grotto rocks grow (AccessService). The pass itself is not live yet (MonetizationConfig Id 0).
-- Delete this script for the real game.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")

local function give(player)
	if player:GetAttribute("Perk_ForgeVip") ~= true then
		player:SetAttribute("Perk_ForgeVip", true)
		print("[TEST] Forgemaster's Pass: the VIP cave on your plot is open for " .. player.Name)
	end
end

local function watch(player)
	give(player)
	player:GetAttributeChangedSignal("Perk_ForgeVip"):Connect(function()
		give(player)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
