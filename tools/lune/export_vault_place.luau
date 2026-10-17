--[[
	Writes a small Roblox Studio TEST place with only the Forge Vault blaster
	shop proposal (tools/lune/lib/blaster_shop.luau, Shop.buildStudio): the
	vault, its jungle trees, a grass ground, a spawn in front of it, the
	game's evening lighting, a script that turns the hologram, and a real
	[E] ProximityPrompt at the counter. The game's own place is not touched.

	  lune run tools/lune/export_vault_place.luau [out.rbxl]
	  default: ../BlasterVault_TEST.rbxl (next to the projekt folder)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

local out = process.args[1] or (root .. "/../BlasterVault_TEST.rbxl")
local Shop = require("./lib/blaster_shop")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

-- the game's evening lighting (LightingConfig.Surface, like WorldService does)
pcall(function()
	lighting.Technology = roblox.Enum.Technology.Future
end)
lighting.ClockTime = 17.6
lighting.GeographicLatitude = 23.5
local preset = LightingConfig.Presets.Surface
for key, value in preset.Lighting do
	lighting[key] = value
end
for group, className in
	{ Atmosphere = "Atmosphere", ColorCorrection = "ColorCorrectionEffect", Bloom = "BloomEffect", SunRays = "SunRaysEffect" }
do
	local effect = roblox.Instance.new(className)
	effect.Name = group
	for key, value in preset[group] do
		effect[key] = value
	end
	effect.Parent = lighting
end

-- the game's sky and shadows (default.project.json)
local sky = roblox.Instance.new("Sky")
sky.SunAngularSize = 16
sky.MoonAngularSize = 11
sky.StarCount = 0
sky.Parent = lighting
lighting.GlobalShadows = true
lighting.ShadowSoftness = 0.3

local vault = Shop.buildStudio(Loader, workspace)
local parts = 0
for _, d in vault:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

-- a spawn on the path, looking at the vault
local spawn = roblox.Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Size = roblox.Vector3.new(6, 1, 6)
spawn.CFrame = Loader.CFrame.new(0, 0.5, 78)
spawn.Color = roblox.Color3.fromRGB(150, 138, 128)
spawn.Parent = workspace

-- the hologram floats and turns, its gems circle the other way; the prompt says hi
local script = roblox.Instance.new("Script")
script.Name = "VaultTestEffects"
script.Source = [[
local RunService = game:GetService("RunService")
local vault = workspace:WaitForChild("BlasterVault")
local holo = vault:FindFirstChild("VaultHologram", true)
local gems = vault:FindFirstChild("VaultGems", true)
local holoBase = holo and holo:GetPivot()
local gemsBase = gems and gems:GetPivot()
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	if holo then
		holo:PivotTo(holoBase * CFrame.new(0, math.sin(t * 1.4) * 0.8, 0) * CFrame.Angles(0, t * 0.7, 0))
	end
	if gems then
		gems:PivotTo(gemsBase * CFrame.Angles(0, -t * 0.4, 0))
	end
end)
local prompt = vault:FindFirstChild("ShopPrompt", true)
if prompt then
	prompt:FindFirstChildWhichIsA("ProximityPrompt").Triggered:Connect(function(player)
		print(player.Name .. " opened the Blaster Vault (the crate shop menu comes later)")
	end)
end
]]
script.Parent = game:GetService("ServerScriptService")

-- inside the vault the light goes down (dark and moody, the glows stand out); back up outside
local zonePart = vault:FindFirstChild("VaultInterior", true)
if zonePart then
	zonePart.CanQuery = false
	zonePart.CanTouch = false
end
local starterPlayer = game:GetService("StarterPlayer")
local playerScripts = starterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
if not playerScripts then
	playerScripts = roblox.Instance.new("StarterPlayerScripts")
	playerScripts.Parent = starterPlayer
end
local mood = roblox.Instance.new("LocalScript")
mood.Name = "VaultInteriorLight"
mood.Source = [[
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local zone = workspace:WaitForChild("BlasterVault"):FindFirstChild("VaultInterior", true)
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local outside = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	ExposureCompensation = Lighting.ExposureCompensation,
	EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
}
local inside = {
	Ambient = Color3.new(0.05, 0.04, 0.07),
	OutdoorAmbient = Color3.new(0.2, 0.18, 0.26),
	ExposureCompensation = -0.45,
	EnvironmentDiffuseScale = 0.15,
}
local ccOut = cc and { Contrast = cc.Contrast, Saturation = cc.Saturation, Brightness = cc.Brightness }
local ccIn = { Contrast = 0.32, Saturation = 0.34, Brightness = -0.02 }
local bloomOut = bloom and { Intensity = bloom.Intensity, Threshold = bloom.Threshold }
local bloomIn = { Intensity = 1.1, Threshold = 0.85 }
local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local wasInside = false
while true do
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local now = false
	if root and zone then
		local p = zone.CFrame:PointToObjectSpace(root.Position)
		local h = zone.Size / 2
		now = math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
	end
	if now ~= wasInside then
		wasInside = now
		TweenService:Create(Lighting, info, if now then inside else outside):Play()
		if cc then
			TweenService:Create(cc, info, if now then ccIn else ccOut):Play()
		end
		if bloom then
			TweenService:Create(bloom, info, if now then bloomIn else bloomOut):Play()
		end
	end
	task.wait(0.2)
end
]]
mood.Parent = playerScripts

fs.writeFile(out, roblox.serializePlace(game))
print(string.format("Wrote %s (%d parts in the vault model)", out, parts))
