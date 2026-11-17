--[[
	AccessController: the VIP cave behind every yard (World/PlotCave, owner 2026-11-17) opens for
	its plot's owner with the Forgemaster's Pass only. Their own door turns see-through and
	passable on their own screen; every other door stays a solid glowing curtain (the server moves
	anyone else out, AccessService).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local AccessController = {}

local player = Players.LocalPlayer

-- May the local player walk through `door`? (their own plot's, with the pass)
function AccessController.opens(vip: boolean, playerPlot: any, doorPlot: any): boolean
	return vip and type(playerPlot) == "number" and playerPlot == doorPlot
end

local function refresh()
	local vip = player:GetAttribute("Perk_ForgeVip") == true
	local plotId = player:GetAttribute("PlotId")
	for _, door in CollectionService:GetTagged("VipDoor") do
		if door:IsA("BasePart") then
			local open = AccessController.opens(vip, plotId, door:GetAttribute("PlotId"))
			door.CanCollide = not open
			door.Transparency = if open then 0.6 else 0
		end
	end
end

function AccessController.start()
	refresh()
	player:GetAttributeChangedSignal("Perk_ForgeVip"):Connect(refresh)
	player:GetAttributeChangedSignal("PlotId"):Connect(refresh)
	CollectionService:GetInstanceAddedSignal("VipDoor"):Connect(refresh)
end

return AccessController
