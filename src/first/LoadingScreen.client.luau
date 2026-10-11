--[[
	Terra Forge loading screen (runs before everything else).
	Shows the logo on a warm gradient until the game and character are loaded.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(40, 22, 18)
background.BorderSizePixel = 0
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 32, 22)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(36, 20, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 12, 12)),
})
gradient.Rotation = 90
gradient.Parent = background

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.fromScale(0.8, 0.16)
title.BackgroundTransparency = 1
title.Text = "TERRA FORGE"
title.TextScaled = true
title.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
title.TextColor3 = Color3.fromRGB(255, 196, 90)
title.Parent = background
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(90, 30, 10)
stroke.Parent = title
local titleGradient = Instance.new("UIGradient")
titleGradient.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 120, 40))
titleGradient.Rotation = 90
titleGradient.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.54)
subtitle.Size = UDim2.fromScale(0.6, 0.05)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Rekindling the Great Forge..."
subtitle.TextScaled = true
subtitle.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
subtitle.TextColor3 = Color3.fromRGB(240, 210, 180)
subtitle.Parent = background

local ember = Instance.new("Frame")
ember.AnchorPoint = Vector2.new(0.5, 0.5)
ember.Position = UDim2.fromScale(0.5, 0.66)
ember.Size = UDim2.fromOffset(18, 18)
ember.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
ember.BorderSizePixel = 0
ember.Parent = background
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = ember

local spin = TweenService:Create(ember, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Size = UDim2.fromOffset(30, 30),
	BackgroundColor3 = Color3.fromRGB(255, 210, 120),
})
spin:Play()

-- wait for the game and the character, but never longer than ~15 seconds
local started = os.clock()
while (not game:IsLoaded() or not player.Character) and os.clock() - started < 15 do
	task.wait(0.1)
end
task.wait(0.6)

local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
for _, label in { title, subtitle } do
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
end
TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
TweenService:Create(ember, fade, { BackgroundTransparency = 1 }):Play()
task.wait(0.7)
spin:Cancel()
gui:Destroy()
