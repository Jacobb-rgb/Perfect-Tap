--[[
	A Roblox Studio TEST place with the IN-GAME Vault lobby package
	(src/server/World/Lobby/Vault) exactly as the game will build it: the vault,
	the statues and the jungle trees at their lobby spot, the preview's grass
	ground and path around them, a spawn on the path, the game's evening
	lighting and sky, and small stand-ins for the game's client code: the
	hologram spins (DecorController's Spin tag), the inside gets darker
	(LightingController's LightingZone + the VaultInterior preset), and an E
	prompt sits on the counter (the shop hook VaultCounter).

	  lune run tools/lune/export_vault_game_place.luau [out.rbxl]
	  default: build/BlasterVault_GAME_TEST.rbxl
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

local out = process.args[1] or (root .. "/build/BlasterVault_GAME_TEST.rbxl")
local Vault = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local Shop = require("./lib/blaster_shop")
local CF = Loader.CFrame

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

pcall(function()
	lighting.Technology = roblox.Enum.Technology.Future
end)
lighting.ClockTime = 17.6
lighting.GeographicLatitude = 23.5
lighting.GlobalShadows = true
lighting.ShadowSoftness = 0.3
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
local sky = roblox.Instance.new("Sky")
sky.SunAngularSize = 16
sky.MoonAngularSize = 11
sky.StarCount = 0
sky.Parent = lighting

-- the package, as the game builds it
local vault = roblox.Instance.new("Model")
vault.Name = "Vault"
vault.Parent = workspace
Vault.build(vault, Rng.new("Lobby/Vault"))

-- the ground around it (built in the vault's design frame, moved to its place)
local origin = Vault.origin()
local ground = roblox.Instance.new("Model")
ground.Name = "Ground"
Shop.studioGround(Loader, ground, Vault.Scale)
for _, d in ground:GetDescendants() do
	if d:IsA("BasePart") then
		d.CFrame = origin * d.CFrame
		d.Anchored = true
		if d.Size.Y <= 3.1 and d.Size.X >= 1.2 and d.Size.Z >= 1.2 then
			d.CanCollide = true
		end
	end
end
ground.Parent = workspace

local spawn = roblox.Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Size = roblox.Vector3.new(6, 1, 6)
spawn.CFrame = origin * CF.new(0, 0.5, 78)
spawn.Color = roblox.Color3.fromRGB(150, 138, 128)
spawn.Parent = workspace

-- stand-ins for the game's client code
local effects = roblox.Instance.new("Script")
effects.Name = "VaultTestEffects"
effects.Source = [[
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
-- DecorController: models tagged Spin turn around their pivot and bob
local spinners = {}
for _, m in CollectionService:GetTagged("Spin") do
	if m:IsA("Model") then
		table.insert(spinners, { model = m, base = m:GetPivot(), speed = m:GetAttribute("SpinSpeed") or 0.8,
			bob = m:GetAttribute("BobHeight") or 0.4, bobSpeed = m:GetAttribute("BobSpeed") or 1.4 })
	end
end
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	for _, s in spinners do
		s.model:PivotTo(s.base * CFrame.new(0, math.sin(t * s.bobSpeed) * s.bob, 0) * CFrame.Angles(0, t * s.speed, 0))
	end
end)
-- the shop hook: an E prompt on the counter
for _, counter in CollectionService:GetTagged("VaultCounter") do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Blaster Vault"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		print(player.Name .. " opened the Blaster Vault (the crate shop menu comes later)")
	end)
end
]]
effects.Parent = game:GetService("ServerScriptService")

local starterPlayer = game:GetService("StarterPlayer")
local playerScripts = roblox.Instance.new("StarterPlayerScripts")
playerScripts.Parent = starterPlayer
local inside = LightingConfig.Presets.VaultInterior
local function color(c): string
	return string.format("Color3.new(%.3f, %.3f, %.3f)", c.R, c.G, c.B)
end
local mood = roblox.Instance.new("LocalScript")
mood.Name = "VaultInteriorLight"
mood.Source = string.format(
	[[
-- LightingController stand-in: inside a part tagged LightingZone, tween to the VaultInterior preset
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local outside = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	ExposureCompensation = Lighting.ExposureCompensation, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale }
local inside = { Ambient = %s, OutdoorAmbient = %s, ExposureCompensation = %s, EnvironmentDiffuseScale = %s }
local ccOut = { Contrast = cc.Contrast, Saturation = cc.Saturation, Brightness = cc.Brightness, TintColor = cc.TintColor }
local ccIn = { Contrast = %s, Saturation = %s, Brightness = %s, TintColor = %s }
local bloomOut = { Intensity = bloom.Intensity, Threshold = bloom.Threshold }
local bloomIn = { Intensity = %s, Threshold = %s }
local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local was = false
while true do
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local now = false
	if rootPart then
		for _, zone in CollectionService:GetTagged("LightingZone") do
			local p = zone.CFrame:PointToObjectSpace(rootPart.Position)
			local h = zone.Size / 2
			if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then
				now = true
			end
		end
	end
	if now ~= was then
		was = now
		TweenService:Create(Lighting, info, if now then inside else outside):Play()
		TweenService:Create(cc, info, if now then ccIn else ccOut):Play()
		TweenService:Create(bloom, info, if now then bloomIn else bloomOut):Play()
	end
	task.wait(0.4)
end
]],
	color(inside.Lighting.Ambient),
	color(inside.Lighting.OutdoorAmbient),
	tostring(inside.Lighting.ExposureCompensation),
	tostring(inside.Lighting.EnvironmentDiffuseScale),
	tostring(inside.ColorCorrection.Contrast),
	tostring(inside.ColorCorrection.Saturation),
	tostring(inside.ColorCorrection.Brightness),
	color(inside.ColorCorrection.TintColor),
	tostring(inside.Bloom.Intensity),
	tostring(inside.Bloom.Threshold)
)
mood.Parent = playerScripts

fs.writeFile(out, roblox.serializePlace(game))
local n = 0
for _, d in vault:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
print(string.format("Wrote %s (the Vault package: %d parts)", out, n))
