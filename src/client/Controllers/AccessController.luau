--[[
	AccessController: VIP players can walk through the Glimmer Grotto door
	(only on their own screen; the server double-checks positions).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local AccessController = {}

local player = Players.LocalPlayer

local function refresh()
	local vip = player:GetAttribute("Perk_ForgeVip") == true
	for _, door in CollectionService:GetTagged("VipDoor") do
		if door:IsA("BasePart") then
			door.CanCollide = not vip
			door.Transparency = if vip then 0.75 else 0.55
		end
	end
end

function AccessController.start()
	refresh()
	player:GetAttributeChangedSignal("Perk_ForgeVip"):Connect(refresh)
	CollectionService:GetInstanceAddedSignal("VipDoor"):Connect(refresh)
end

return AccessController
