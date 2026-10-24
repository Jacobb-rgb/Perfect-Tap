-- TEST FILE ONLY (Roblox Studio): the studded style is switched on in this place
-- (Workspace attributes StudStyle and StudStyleLook: "Classic" = proposal A,
-- "Custom" = proposal B). Proposal B needs the three stud pictures uploaded
-- (NAHRAJ_DO_ROBLOXU/vystupky): paste their ids (or rbxassetid:// links) into
-- this script's attributes ColorMap, NormalMap and RoughnessMap, then press Play.
-- Switch live while playing (command bar, Server view):
--   workspace:SetAttribute("StudStyleLook", "Custom")   -- or "Classic"
--   workspace:SetAttribute("StudStyle", false)           -- the map as it is today
-- Delete this script for the real game.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudStyleConfig = require(Shared.Config.StudStyleConfig)
local StudStyle = require(Shared.StudStyle)

local found = 0
for _, key in { "ColorMap", "NormalMap", "RoughnessMap" } do
	local id = tonumber(string.match(tostring(script:GetAttribute(key) or ""), "%d+"))
	if id and id > 0 then
		StudStyleConfig.Assets[key] = id
		found += 1
	end
end
if StudStyleConfig.Assets.NormalMap > 0 then
	if workspace:GetAttribute("StudStyle") == true then
		StudStyle.ensureVariants(game:GetService("MaterialService"))
	end
	print(`[TEST] stud pictures: {found} of 3 ids, look {workspace:GetAttribute("StudStyleLook")}`)
else
	warn("[TEST] proposal B: paste the uploaded stud picture ids into TEST_Vystupky's attributes (ColorMap, NormalMap, RoughnessMap)")
end
