--[[
	Tweens Lighting and post effects to the preset of the zone the player is
	in (town, quarry, caves...). Other code can push a temporary preset on top
	(the cleaning close-up uses "Workbench") and pop it again.

	The golden-hour sky (docs/ART_DIRECTION.md section 7) is set up here once:
	- a Sky object (LightingConfig.Sky) if the place has none
	- Workspace.Terrain.Clouds (LightingConfig.Clouds) if missing
	- alignSun(): the sun goes where the lobby art expects it
	  (LobbyLayout.SunDirection, low over the west sea)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local LobbyLayout = require(Shared.Config.LobbyLayout)
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

-- The Sky object (default skybox, big low sun, no stars) if the place has none.
function LightingController.ensureSky(): Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		return sky
	end
	local created = Instance.new("Sky")
	created.Name = "Sky"
	created.SunAngularSize = LightingConfig.Sky.SunAngularSize
	created.MoonAngularSize = LightingConfig.Sky.MoonAngularSize
	created.StarCount = LightingConfig.Sky.StarCount
	created.CelestialBodiesShown = LightingConfig.Sky.CelestialBodiesShown
	created.Parent = Lighting
	return created
end

-- Soft pink sunset clouds (Workspace.Terrain.Clouds) if the place has none.
function LightingController.ensureClouds(): Clouds?
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return nil
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		return clouds
	end
	local created = Instance.new("Clouds")
	created.Cover = LightingConfig.Clouds.Cover
	created.Density = LightingConfig.Clouds.Density
	created.Color = LightingConfig.Clouds.Color
	created.Parent = terrain
	return created
end

--[[
	Put the sun where the lobby art expects it. Roblox's sun path (ClockTime +
	GeographicLatitude) cannot be computed offline, so this searches once for
	the pair whose Lighting:GetSunDirection() is closest to
	LobbyLayout.SunDirection: a coarse grid over the whole day and latitudes
	-66..66, then a shrinking pattern search. Client-only (the server never
	changes ClockTime, so nothing overwrites it). Keeps the configured values
	if the engine does not update the direction immediately or no pair is
	close enough. Returns the error of the applied sun direction.
]]
function LightingController.alignSun(): number
	local config = LightingConfig.Sun
	local target = LobbyLayout.SunDirection
	local startClock, startLatitude = Lighting.ClockTime, Lighting.GeographicLatitude
	local function errorAt(clock: number, latitude: number): number
		Lighting.ClockTime = clock % 24
		Lighting.GeographicLatitude = math.clamp(latitude, -89, 89)
		return (Lighting:GetSunDirection() - target).Magnitude
	end
	local startError = errorAt(startClock, startLatitude)
	if not config.AutoAlign then
		return startError
	end
	-- the engine must report a new direction right after a property change
	local probeA = errorAt(startClock + 3, startLatitude)
	local probeB = errorAt(startClock + 9, startLatitude)
	if math.abs(probeA - startError) < 1e-4 and math.abs(probeB - startError) < 1e-4 then
		errorAt(startClock, startLatitude)
		return startError
	end
	local bestClock, bestLatitude, bestError = startClock, startLatitude, startError
	for clock = 0, 23.75, 0.25 do
		for latitude = -66, 66, 6 do
			local e = errorAt(clock, latitude)
			if e < bestError then
				bestClock, bestLatitude, bestError = clock, latitude, e
			end
		end
	end
	local stepClock, stepLatitude = 0.25, 6
	for _ = 1, 40 do
		local improved = false
		for _, delta in { { stepClock, 0 }, { -stepClock, 0 }, { 0, stepLatitude }, { 0, -stepLatitude } } do
			local clock, latitude = bestClock + delta[1], math.clamp(bestLatitude + delta[2], -89, 89)
			local e = errorAt(clock, latitude)
			if e < bestError then
				bestClock, bestLatitude, bestError = clock % 24, latitude, e
				improved = true
			end
		end
		if not improved then
			stepClock, stepLatitude = stepClock / 2, stepLatitude / 2
			if stepClock < 0.002 then
				break
			end
		end
	end
	if bestError > config.MaxError then
		return errorAt(startClock, startLatitude)
	end
	local applied = errorAt(bestClock, bestLatitude)
	if RunService:IsStudio() then
		print(
			string.format(
				"[TerraForge] sun aligned: ClockTime %.3f, GeographicLatitude %.2f (error %.3f; was %.3f). Put them in LightingConfig.Sun and default.project.json.",
				bestClock,
				bestLatitude,
				applied,
				startError
			)
		)
	end
	return applied
end

function LightingController.init()
	LightingController.ensureSky()
	LightingController.ensureClouds()
	local ok, err = pcall(LightingController.alignSun)
	if not ok then
		warn("[TerraForge] sun alignment failed: " .. tostring(err))
	end
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
