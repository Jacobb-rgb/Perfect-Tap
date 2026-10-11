--[[
	Tweens Lighting and post effects to the preset of the zone the player is
	in (town, quarry, caves...). Other code can push a temporary preset on top
	(the cleaning close-up uses "Workbench") and pop it again.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local WorldLayout = require(Shared.Config.WorldLayout)

local LightingController = {}

local player = Players.LocalPlayer
local currentZonePreset = "Surface"
local overrides: { string } = {}
local activeTweens: { Tween } = {}

local EFFECT_CLASSES = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local function effect(group: string): Instance?
	if group == "Lighting" then
		return Lighting
	end
	local className = EFFECT_CLASSES[group]
	return className and Lighting:FindFirstChildOfClass(className)
end

local function tweenTo(presetName: string, duration: number)
	local preset = LightingConfig.Presets[presetName]
	if not preset then
		return
	end
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local groups: { [string]: { [string]: any } } = {
		Lighting = preset.Lighting,
		Atmosphere = preset.Atmosphere,
		ColorCorrection = preset.ColorCorrection,
		Bloom = preset.Bloom,
		SunRays = preset.SunRays,
	}
	for group, values in groups do
		local target = effect(group)
		if target and next(values) then
			local goals = {}
			for key, value in values do
				goals[key] = value
			end
			local tween = TweenService:Create(target, info, goals)
			table.insert(activeTweens, tween)
			tween:Play()
		end
	end
end

local function desiredPreset(): string
	if #overrides > 0 then
		return overrides[#overrides]
	end
	return currentZonePreset
end

local lastApplied = ""
local function refresh(duration: number?)
	local want = desiredPreset()
	if want ~= lastApplied then
		lastApplied = want
		tweenTo(want, duration or LightingConfig.TweenTime)
	end
end

-- Temporarily use another preset (e.g. "Workbench"). Returns a pop function.
function LightingController.push(presetName: string, duration: number?): () -> ()
	table.insert(overrides, presetName)
	refresh(duration)
	local popped = false
	return function()
		if popped then
			return
		end
		popped = true
		local index = table.find(overrides, presetName)
		if index then
			table.remove(overrides, index)
		end
		refresh(duration)
	end
end

function LightingController.currentZone(): string
	return currentZonePreset
end

function LightingController.start()
	while true do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local zone = WorldLayout.zoneAt(root.Position)
			local preset = if zone then zone.Lighting else "Surface"
			if preset ~= currentZonePreset then
				currentZonePreset = preset
				refresh()
			end
		end
		task.wait(0.4)
	end
end

return LightingController
