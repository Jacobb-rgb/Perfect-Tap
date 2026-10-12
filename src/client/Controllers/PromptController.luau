--[[
	PromptController: hides machine prompts on other players' machines (on
	this screen only; the server still checks ownership) and keeps prompt
	keys consistent (F / gamepad Y; E is Grab).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local PromptController = {}

local player = Players.LocalPlayer

local function machineOwner(prompt: ProximityPrompt): number?
	local node: Instance? = prompt
	while node do
		if node:IsA("Model") and node:GetAttribute("MachineId") then
			return node:GetAttribute("Owner") :: number?
		end
		node = node.Parent
	end
	return nil
end

function PromptController.start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local owner = machineOwner(prompt)
		if owner and owner ~= player.UserId then
			prompt.Enabled = false
		end
	end)
end

return PromptController
