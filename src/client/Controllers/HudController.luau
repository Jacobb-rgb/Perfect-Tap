--[[
	HudController: coins counter (with a pop when it changes), zone banner,
	toast notifications, carry slots and UI scaling for small screens.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local HudView = require(script.Parent.Parent.UI.HudView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local StateController = require(script.Parent.StateController)

local HudController = {}

local player = Players.LocalPlayer
local refs: HudView.Refs
local shownCoins = 0
local targetCoins = 0
local MAX_TOASTS = 4

local TOAST_COLORS = {
	Info = Theme.Info,
	Deny = Theme.Bad,
	Discovery = Theme.Accent,
	Reward = Theme.Good,
}

function HudController.refs(): HudView.Refs
	return refs
end

function HudController.toast(text: string, kind: string?, color: Color3?)
	local frames = {}
	for _, child in refs.Toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames >= MAX_TOASTS then
		frames[1]:Destroy()
	end
	local frame = HudView.toast(refs.Toasts, text, color or TOAST_COLORS[kind or "Info"] or Theme.Info)
	frame.LayoutOrder = math.floor(os.clock() * 100) % 1e6
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if kind == "Deny" then
		Sfx.play("UIDeny")
	elseif kind == "Discovery" then
		Sfx.play("Discovery")
	end
	task.delay(3.2, function()
		if frame.Parent then
			TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
			task.wait(0.22)
			frame:Destroy()
		end
	end)
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local scale = math.clamp(math.min(size.Y / Theme.BaseHeight, size.X / 1100), 0.62, 1.25)
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		local uiScale = gui:IsA("ScreenGui") and gui:FindFirstChild("Scale")
		if uiScale and uiScale:IsA("UIScale") and gui:GetAttribute("TerraForge") then
			uiScale.Scale = scale
		end
	end
end

local function rarityColorOfItem(model: Instance): Color3
	local ore = OreData.ById[model:GetAttribute("OreId") :: string]
	return if ore then Rarity.get(ore.Rarity).Color else Theme.PanelLight
end

local function refreshCarry()
	local capacity = (player:GetAttribute("CarryCapacity") :: number?) or 1
	local carried = {}
	for _, item in CollectionService:GetTagged("Item") do
		if item:GetAttribute("CarriedBy") == player.UserId then
			table.insert(carried, item)
		end
	end
	for _, child in refs.CarrySlots:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i = 1, capacity do
		local item = carried[i]
		HudView.slot(refs.CarrySlots, if item then rarityColorOfItem(item) else nil, i)
	end
	refs.CarryLabel.Text = `CARRYING {#carried}/{capacity}`
	refs.CarryPanel.Size = UDim2.fromOffset(math.max(200, capacity * 40 + 24), 74)
end

local currentZone = ""
local function zoneLoop()
	while true do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local zone = WorldLayout.zoneAt(root.Position)
			local name = if zone then zone.Name else "Terra"
			if name ~= currentZone then
				currentZone = name
				refs.Zone.Text = name
				refs.Zone.TextTransparency = 0
				local stroke = refs.Zone:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = 0
				end
				task.delay(2.5, function()
					if currentZone == name then
						TweenService:Create(refs.Zone, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
						if stroke then
							TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
						end
					end
				end)
			end
		end
		task.wait(0.5)
	end
end

function HudController.init()
	refs = HudView.build()
	refs.Gui:SetAttribute("TerraForge", true)
	refs.Gui.Parent = player:WaitForChild("PlayerGui")

	Net.listen("Notify", function(message)
		if type(message) ~= "table" or type(message.Text) ~= "string" then
			return
		end
		local color = nil
		if type(message.Rarity) == "string" and Rarity.ById[message.Rarity] then
			color = Rarity.ById[message.Rarity].Color
		end
		HudController.toast(message.Text, message.Kind, color)
	end)

	StateController.onChanged(function(state)
		targetCoins = state.Coins or 0
	end)
end

function HudController.start()
	local camera = Workspace.CurrentCamera
	updateScale()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	player:WaitForChild("PlayerGui").ChildAdded:Connect(function()
		task.defer(updateScale)
	end)

	player:GetAttributeChangedSignal("CarryCount"):Connect(refreshCarry)
	player:GetAttributeChangedSignal("CarryCapacity"):Connect(refreshCarry)
	CollectionService:GetInstanceAddedSignal("Item"):Connect(function()
		task.defer(refreshCarry)
	end)
	refreshCarry()

	task.spawn(zoneLoop)

	-- smooth coin counter
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = refs.CoinsPanel
	while true do
		if shownCoins ~= targetCoins then
			local diff = targetCoins - shownCoins
			local step = if math.abs(diff) < 2 then diff else diff * 0.25
			shownCoins += step
			if math.abs(targetCoins - shownCoins) < 0.5 then
				shownCoins = targetCoins
			end
			refs.Coins.Text = Format.commas(math.floor(shownCoins + 0.5))
			if diff > 0 then
				coinScale.Scale = 1.12
				TweenService:Create(coinScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
			end
		end
		task.wait(0.05)
	end
end

return HudController
