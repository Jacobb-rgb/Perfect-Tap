--[[
	HUD layout (pure builder). Returns references the HudController fills in.
	  top-left     coins
	  top-center   zone name + toast notifications
	  bottom       carry slots + hints
	  center       throw power bar
	  right side   menu buttons (added by later steps)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)

local HudView = {}

export type Refs = {
	Gui: ScreenGui,
	Coins: TextLabel,
	CoinsPanel: Frame,
	Zone: TextLabel,
	Toasts: Frame,
	CarryPanel: Frame,
	CarrySlots: Frame,
	CarryLabel: TextLabel,
	ThrowBar: Frame,
	ThrowFill: Frame,
	Menu: Frame,
}

local function coinIcon(parent: Instance, size: number): Frame
	local coin = UIKit.new("Frame", {
		Name = "CoinIcon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Coin,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(coin, size)
	UIKit.stroke(coin, 2.5)
	local inner = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = Color3.fromRGB(255, 232, 140),
		BorderSizePixel = 0,
	}, coin)
	UIKit.corner(inner, size)
	UIKit.stroke(inner, 1.5, Theme.AccentDark)
	return coin
end
HudView.coinIcon = coinIcon

function HudView.build(): Refs
	local gui = UIKit.screen("TerraForgeHud", 5)

	-- coins
	local coinsPanel = UIKit.panel(gui, {
		Name = "Coins",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(210, 56),
	})
	local icon = coinIcon(coinsPanel, 38)
	icon.Position = UDim2.fromOffset(9, 9)
	local coins = UIKit.label(coinsPanel, "0", 30, {
		Name = "Amount",
		Position = UDim2.fromOffset(56, 4),
		Size = UDim2.new(1, -64, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextScaled = false,
	})

	-- zone name + toasts
	local zone = UIKit.label(gui, "Emberfall", 26, {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(420, 34),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextTransparency = 1,
	})
	local toasts = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(520, 260),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(toasts, Enum.FillDirection.Vertical, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- carry slots
	local carryPanel = UIKit.panel(gui, {
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(260, 74),
	})
	local carryLabel = UIKit.label(carryPanel, "HANDS 0/1", 16, {
		Name = "Label",
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.TextDim,
	})
	local slots = UIKit.new("Frame", {
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.new(1, -16, 0, 38),
		BackgroundTransparency = 1,
	}, carryPanel)
	UIKit.list(slots, Enum.FillDirection.Horizontal, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- throw power bar
	local throwBar = UIKit.new("Frame", {
		Name = "ThrowBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(180, 16),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	UIKit.corner(throwBar, 8)
	UIKit.stroke(throwBar, 2.5)
	local throwFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, throwBar)
	UIKit.corner(throwFill, 8)

	-- right-side menu buttons (filled by later steps)
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(84, 360),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(menu, Enum.FillDirection.Vertical, 10, { VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right })

	return {
		Gui = gui,
		Coins = coins,
		CoinsPanel = coinsPanel,
		Zone = zone,
		Toasts = toasts,
		CarryPanel = carryPanel,
		CarrySlots = slots,
		CarryLabel = carryLabel,
		ThrowBar = throwBar,
		ThrowFill = throwFill,
		Menu = menu,
	}
end

-- One carry slot square; color = rarity color or empty.
function HudView.slot(parent: Instance, filled: Color3?, order: number): Frame
	local slot = UIKit.new("Frame", {
		Name = "Slot" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = filled or Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(slot, 8)
	UIKit.stroke(slot, 2.5)
	if filled then
		UIKit.gradient(slot, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	end
	return slot
end

-- A toast message (Kind = Info | Deny | Discovery | Reward). Returns the frame.
function HudView.toast(parent: Instance, text: string, color: Color3): Frame
	local frame = UIKit.panel(parent, {
		Name = "Toast",
		Size = UDim2.fromOffset(460, 44),
		BackgroundColor3 = Theme.Panel,
	})
	local bar = UIKit.new("Frame", {
		Size = UDim2.new(0, 8, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(bar, 4)
	UIKit.label(frame, text, 20, {
		Name = "Text",
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -32, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return frame
end

return HudView
