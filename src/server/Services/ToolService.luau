--[[
	ToolService: gives every character the pickaxe from their save data
	and swaps it when they buy a better one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PickaxeBuilder = require(Shared.Builders.PickaxeBuilder)
local DataService = require(script.Parent.DataService)

local ToolService = {}

local function removePickaxes(player: Player)
	local containers: { Instance? } = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == "Pickaxe" then
					child:Destroy()
				end
			end
		end
	end
end

-- Gives (or replaces) the pickaxe. Re-equips it if the old one was in hand.
function ToolService.refresh(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not character or not backpack then
		return
	end
	local wasEquipped = character:FindFirstChild("Pickaxe") ~= nil
	removePickaxes(player)
	local tool = PickaxeBuilder.build(data.Pickaxe)
	tool.Parent = backpack
	if wasEquipped then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(tool)
		end
	end
end

function ToolService.init()
	local function setup(player: Player)
		player.CharacterAdded:Connect(function()
			if DataService.waitFor(player, 30) then
				player:WaitForChild("Backpack", 10)
				ToolService.refresh(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	DataService.onLoaded(function(player)
		if player.Character then
			ToolService.refresh(player)
		end
	end)
end

return ToolService
