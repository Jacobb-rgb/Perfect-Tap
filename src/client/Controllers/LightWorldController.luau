--[[
	LightWorldController: the in-world labels in the light "Bubble" look.
	Does nothing unless UIConfig.lightUI() is on (it ships on since
	2026-10-20).

	- Labels: every BillboardGui in the world and in the PlayerGui (podium
	  income tags, machine signs, sell pop-ups, item hints, the foundry's pen
	  tag, the podium Remove button...) gets LightSkin.world: navy outlines and
	  text edges, dark panels white. Labels other sessions own are left alone
	  (LightWorldController.Skip: the mine floors' rock name + HP labels),
	  and so is Roblox's own prompt UI (the "Prompt" BillboardGuis its core
	  script puts in PlayerGui.ProximityPrompts): no navy edges on it.
	- Prompts: the stock Roblox prompt (owner 2026-10-20; PromptConfig makes
	  every prompt in the Default style). Only with UIConfig.CustomPrompts on
	  does every ProximityPrompt switch to the Custom style on this screen
	  and show LightPrompt (the key in a gold circle, the action and object
	  on a white pill, a green hold bar; touch: tap the pill). That pill
	  ignores UIOffset and never updates its text, so it stays off.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local LightSkin = require(script.Parent.Parent.UI.LightSkin)
local LightPrompt = require(script.Parent.Parent.UI.LightPrompt)

local LightWorldController = {}

local player = Players.LocalPlayer

-- BillboardGui names the light skin leaves alone (their owners style them).
LightWorldController.Skip = {
	RockLabel = true, -- art/mine-floors: the rock name + HP labels
	TerraForgePrompt = true, -- our own prompt pills (UIConfig.CustomPrompts)
} :: { [string]: boolean }

-- The ScreenGui Roblox's prompt core script keeps its prompt UI in (PlayerGui).
LightWorldController.StockPromptFolder = "ProximityPrompts"

-- The light skin for one world label (BillboardGui), once. Roblox's own
-- prompt UI is left alone: its core script parents a BillboardGui "Prompt"
-- into the PlayerGui's ScreenGui "ProximityPrompts" (a generic name, so the
-- folder is the check, not Skip).
function LightWorldController.skinLabel(gui: Instance)
	if not gui:IsA("BillboardGui") or LightWorldController.Skip[gui.Name] then
		return
	end
	if gui:FindFirstAncestor(LightWorldController.StockPromptFolder) then
		return
	end
	if gui:GetAttribute("LightSkin") then
		return
	end
	LightSkin.world(gui)
end
local skinLabel = LightWorldController.skinLabel

---------------------------------------------------------------- prompts

local shown: { [ProximityPrompt]: LightPrompt.Refs } = {}

local function keyFor(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): (string, string?)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP", nil
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, prompt.GamepadKeyCode)
		return "", if ok then image else nil
	end
	local ok, text = pcall(UserInputService.GetStringForKeyCode, UserInputService, prompt.KeyboardKeyCode)
	return if ok and text ~= "" then text else prompt.KeyboardKeyCode.Name, nil
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if shown[prompt] then
		return
	end
	local refs = LightPrompt.build(prompt.ActionText, prompt.ObjectText, "")
	local text, image = keyFor(prompt, inputType)
	LightPrompt.setKey(refs, text, image)
	refs.Gui.Adornee = prompt.Parent :: Instance
	refs.Gui.StudsOffset = Vector3.new(0, 0, 0)
	refs.Gui.MaxDistance = prompt.MaxActivationDistance + 10
	refs.Gui.Parent = player:WaitForChild("PlayerGui")
	shown[prompt] = refs
	-- pop in
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = refs.Gui:FindFirstChild("Pill") :: Instance
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- touch / click on the pill holds the prompt
	refs.Button.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	refs.Button.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)
end

local function hide(prompt: ProximityPrompt)
	local refs = shown[prompt]
	if refs then
		shown[prompt] = nil
		refs.Gui:Destroy()
	end
end

local holdTweens: { [ProximityPrompt]: Tween } = {}

local function useCustom(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt.Style == Enum.ProximityPromptStyle.Default then
		prompt.Style = Enum.ProximityPromptStyle.Custom -- on this screen only
	end
end

local function startPrompts()
	for _, d in Workspace:GetDescendants() do
		useCustom(d)
	end
	Workspace.DescendantAdded:Connect(useCustom)
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local refs = shown[prompt]
		if refs then
			LightPrompt.setHold(refs, 0)
			local tween = TweenService:Create(refs.Fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
				Size = UDim2.fromScale(1, 1),
			})
			holdTweens[prompt] = tween
			tween:Play()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local tween = holdTweens[prompt]
		if tween then
			tween:Cancel()
			holdTweens[prompt] = nil
		end
		local refs = shown[prompt]
		if refs then
			LightPrompt.setHold(refs, 0)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local refs = shown[prompt]
		if refs then
			local pill = refs.Gui:FindFirstChild("Pill") :: Frame?
			local scale = pill and pill:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1.15
				TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
			end
		end
	end)
end

---------------------------------------------------------------- lifecycle

function LightWorldController.init() end

function LightWorldController.start()
	if not UIConfig.lightUI() then
		return
	end
	for _, d in Workspace:GetDescendants() do
		skinLabel(d)
	end
	-- (filtered before deferring: a streamed-in region adds thousands of parts at once)
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("BillboardGui") then
			task.defer(skinLabel, d)
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	for _, d in playerGui:GetDescendants() do
		skinLabel(d)
	end
	playerGui.DescendantAdded:Connect(function(d)
		if d:IsA("BillboardGui") then
			task.defer(skinLabel, d)
		end
	end)
	if UIConfig.CustomPrompts then
		startPrompts()
	end
end

return LightWorldController
