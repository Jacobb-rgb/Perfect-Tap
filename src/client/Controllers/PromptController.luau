--[[
	PromptController: machine prompts that fit what you're doing (on this
	screen only; the server still checks everything) and consistent prompt
	keys.

	- Prompts on other players' machines are hidden.
	- 'LoadPrompt' (Put In) on your own machines shows only while you carry
	  something. The server never changes its Enabled, so this local choice sticks.
	- Pell's 'SellPrompt' shows what your carried items are worth.
	- setSuppressed(reason, on) hides every prompt during close-ups (build
	  mode, the anvil); prompts come back when no reason is left.
	Keys: F / gamepad Y for machine prompts; the Cleaning Station's "Take Ore
	Back" uses G / gamepad B and is always shown (its own keys, so it never
	fires together with another prompt). Taken elsewhere: E / X Grab, Q / RB
	Throw; B is also Leave inside the cleaning minigame, while the station
	prompts are disabled.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local PromptController = {}

local player = Players.LocalPlayer
local suppressed: { [string]: boolean } = {}
-- weak keys: prompts of machines that are gone drop out by themselves
local loadPrompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local sellPrompts: { [ProximityPrompt]: string } = setmetatable({}, { __mode = "k" }) :: any -- prompt -> its own ObjectText
local machineConnections: { [Instance]: RBXScriptConnection } = {}

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

local function carryCount(): number
	return (player:GetAttribute("CarryCount") :: number?) or 0
end

local function applyLoad(prompt: ProximityPrompt)
	prompt.Enabled = machineOwner(prompt) == player.UserId and carryCount() > 0
end

-- Coins your carried items would sell for (each item has a Value attribute).
local function carriedValue(): number
	local total = 0
	for _, item in CollectionService:GetTagged("Item") do
		if item:GetAttribute("CarriedBy") == player.UserId then
			total += (item:GetAttribute("Value") :: number?) or 0
		end
	end
	return total
end

local function applySell(prompt: ProximityPrompt)
	local original = sellPrompts[prompt]
	if original == nil then
		original = prompt.ObjectText
		sellPrompts[prompt] = original
	end
	local worth = carriedValue()
	prompt.ObjectText = if worth > 0 then `Worth {Format.commas(worth)} coins` else original
end

local function refreshAll()
	for prompt in loadPrompts do
		if prompt.Parent then
			applyLoad(prompt)
		end
	end
	for prompt in sellPrompts do
		if prompt.Parent then
			applySell(prompt)
		end
	end
end

local function track(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Name == "LoadPrompt" then
		loadPrompts[instance] = true
		applyLoad(instance)
	end
end

-- Load prompts are created right after the machine appears, so watch each
-- machine for them (machines stream in and out).
local function watchMachine(model: Instance)
	if machineConnections[model] then
		return
	end
	for _, d in model:GetDescendants() do
		track(d)
	end
	machineConnections[model] = model.DescendantAdded:Connect(track)
end

local function unwatchMachine(model: Instance)
	local connection = machineConnections[model]
	if connection then
		connection:Disconnect()
		machineConnections[model] = nil
	end
end

-- Hides or shows every proximity prompt for a reason ('Build', 'Anvil'...).
function PromptController.setSuppressed(reason: string, on: boolean)
	if on then
		suppressed[reason] = true
	else
		suppressed[reason] = nil
	end
	ProximityPromptService.Enabled = next(suppressed) == nil
end

function PromptController.start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name == "LoadPrompt" then
			loadPrompts[prompt] = true
			applyLoad(prompt)
			return
		end
		if prompt.Name == "SellPrompt" then
			applySell(prompt)
		end
		local owner = machineOwner(prompt)
		if owner and owner ~= player.UserId then
			prompt.Enabled = false
		end
	end)

	CollectionService:GetInstanceAddedSignal("Machine"):Connect(watchMachine)
	CollectionService:GetInstanceRemovedSignal("Machine"):Connect(unwatchMachine)
	for _, model in CollectionService:GetTagged("Machine") do
		watchMachine(model)
	end

	-- an item's CarriedBy attribute may arrive a moment after CarryCount, so refresh twice
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		refreshAll()
		task.delay(0.25, refreshAll)
	end)
end

return PromptController
