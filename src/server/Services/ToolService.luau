--[[
	ToolService: every character gets exactly one Blaster tool, built for the
	save's BlasterLevel + BlasterOre (BlasterBuilder). It is rebuilt when those
	change (Foundry, step 3) and given again after every respawn. If the old
	blaster was in the player's hand, the new one is equipped right away.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local DataService = require(script.Parent.DataService)

local ToolService = {}

-- "level|ore" of the blaster each player was given (nil = none yet)
local given: { [Player]: string } = {}

-- Tool names that are ours (old saves had a pickaxe in the backpack).
local OUR_TOOLS = { [BlasterBuilder.ToolName] = true, Pickaxe = true }

local function oreOf(data: { [string]: any }): string
	local ore = data.BlasterOre
	return if type(ore) == "string" and #ore <= 40 then ore else ""
end

local function signature(data: { [string]: any }): string
	return tostring(BlasterData.get(data.BlasterLevel).Level) .. "|" .. oreOf(data)
end

local function removeTools(player: Player)
	local containers: { Instance? } = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and OUR_TOOLS[child.Name] then
					child:Destroy()
				end
			end
		end
	end
end

-- The Blaster in the player's hand (nil when it sits in the backpack).
function ToolService.equipped(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(BlasterBuilder.ToolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- Gives (or replaces) the blaster. Re-equips it if the old one was in hand.
function ToolService.refresh(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not character or not backpack then
		return
	end
	local wasEquipped = ToolService.equipped(player) ~= nil
	removeTools(player)
	local tool = BlasterBuilder.build(data.BlasterLevel, oreOf(data))
	tool.Parent = backpack
	given[player] = signature(data)
	if wasEquipped then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:EquipTool(tool)
		end
	end
end

function ToolService.init()
	local function setup(player: Player)
		player.CharacterAdded:Connect(function()
			given[player] = nil
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
	Players.PlayerRemoving:Connect(function(player)
		given[player] = nil
	end)
	DataService.onLoaded(function(player)
		if player.Character then
			ToolService.refresh(player)
		end
	end)
	-- a new blaster level or ore (Foundry) swaps the tool; other changes are ignored
	DataService.onChanged(function(player)
		local data = DataService.get(player)
		local current = given[player]
		if data and current and current ~= signature(data) then
			ToolService.refresh(player)
		end
	end)
end

return ToolService
