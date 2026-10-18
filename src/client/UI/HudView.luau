--[[
	HUD layout (pure builder). Returns references the HudController fills in.
	  top-left     coins ("$1.23K") with the podium income under it ("+$12/s"),
	               floating "+$X" popups (Earned) below
	  top-center   the quick-teleport bar (TeleportView: BASE / LOBBY / VAULT),
	               the zone name + toast notifications under it
	  bottom       carry slots + hints
	  center       throw power bar
	  right side   menu buttons (added by later steps)
	The "While you were away" popup is its own ScreenGui (buildOffline).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)

local HudView = {}

HudView.CoinsWidth = 236
HudView.DirtyColor = Color3.fromRGB(120, 114, 108) -- dirty ore: no rarity color until cleaned
HudView.TopBarY = 10 -- the teleport bar at the top centre (design units)
HudView.TopBarWidth = 440
HudView.TopBarHeight = 58
-- carry squares drawn at most: a bigger backpack (24 with Strong Back) shows
-- "+N" on the last one, so the panel never covers the touch controls
HudView.MaxCarrySlots = 8
HudView.CarryPanelHeight = 74

export type Refs = {
	Gui: ScreenGui,
	Coins: TextLabel,
	CoinsPanel: Frame,
	Income: TextLabel,
	Floaters: Frame,
	Zone: TextLabel,
	Toasts: Frame,
	CarryPanel: Frame,
	CarrySlots: Frame,
	CarryLabel: TextLabel,
	ThrowBar: Frame,
	ThrowFill: Frame,
	Menu: Frame,
	TopBar: Frame,
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

	-- coins and the podium income under them
	local coinsPanel = UIKit.panel(gui, {
		Name = "Coins",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(HudView.CoinsWidth, 74),
	})
	local icon = coinIcon(coinsPanel, 40)
	icon.Position = UDim2.fromOffset(10, 9)
	local coins = UIKit.label(coinsPanel, "$0", 30, {
		Name = "Amount",
		Position = UDim2.fromOffset(60, 4),
		Size = UDim2.new(1, -68, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextScaled = false,
		TextWrapped = false,
	})
	local income = UIKit.label(coinsPanel, "+$0/s", 18, {
		Name = "Income",
		Position = UDim2.fromOffset(60, 42),
		Size = UDim2.new(1, -68, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextScaled = false,
		TextWrapped = false,
	})
	-- "+$X" popups rise from here (under the coins panel)
	local floaters = UIKit.new("Frame", {
		Name = "Floaters",
		Position = UDim2.fromOffset(16, 96),
		Size = UDim2.fromOffset(HudView.CoinsWidth, 60),
		BackgroundTransparency = 1,
	}, gui)

	-- the quick-teleport bar (TeleportController fills it)
	local topBar = UIKit.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HudView.TopBarY),
		Size = UDim2.fromOffset(HudView.TopBarWidth, HudView.TopBarHeight),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(topBar, Enum.FillDirection.Horizontal, 10, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})

	-- zone name + toasts (under the teleport bar)
	local zone = UIKit.label(gui, "Emberfall", 26, {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HudView.TopBarY + HudView.TopBarHeight + 8),
		Size = UDim2.fromOffset(420, 34),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextTransparency = 1,
	})
	local toasts = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HudView.TopBarY + HudView.TopBarHeight + 50),
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
	UIKit.list(
		menu,
		Enum.FillDirection.Vertical,
		10,
		{ VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right }
	)

	return {
		Gui = gui,
		Coins = coins,
		CoinsPanel = coinsPanel,
		Income = income,
		Floaters = floaters,
		Zone = zone,
		Toasts = toasts,
		CarryPanel = carryPanel,
		CarrySlots = slots,
		CarryLabel = carryLabel,
		ThrowBar = throwBar,
		ThrowFill = throwFill,
		Menu = menu,
		TopBar = topBar,
	}
end

--[[
	How the carry panel shows `count` carried items of `capacity`: the
	squares drawn (at most MaxCarrySlots), how many of them show an item,
	the "+N" on the last square (0 = none: everything fits) and the panel's
	width (design units). The text says the whole count ("CARRYING 12/24").
]]
function HudView.carryLayout(capacity: number, count: number): (number, number, number, number)
	local cap = if type(capacity) == "number" and capacity == capacity then math.max(1, math.floor(capacity)) else 1
	local carried = if type(count) == "number" and count == count then math.max(0, math.floor(count)) else 0
	local squares = math.min(cap, HudView.MaxCarrySlots)
	local shown = math.min(carried, squares)
	local more = 0
	if carried > squares then
		shown = squares - 1
		more = carried - shown
	end
	return squares, shown, more, math.max(200, squares * 40 + 24)
end

-- The last carry square when more items are carried than squares are drawn: "+N".
function HudView.moreSlot(parent: Instance, more: number, order: number): Frame
	local slot = HudView.slot(parent, Theme.PanelLight, order)
	UIKit.label(slot, `+{more}`, if more >= 100 then 14 else 18, { Name = "More", Size = UDim2.fromScale(1, 1) })
	return slot
end

-- One carry slot square; color = rarity color or empty. `mystery` (dirty
-- ore) shows a "?" instead of hinting at the rarity.
function HudView.slot(parent: Instance, filled: Color3?, order: number, mystery: boolean?): Frame
	local slot = UIKit.new("Frame", {
		Name = "Slot" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = if mystery then HudView.DirtyColor else filled or Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(slot, 8)
	UIKit.stroke(slot, 2.5)
	if filled or mystery then
		UIKit.gradient(slot, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	end
	if mystery then
		UIKit.label(slot, "?", 22, { Name = "Mystery", Size = UDim2.fromScale(1, 1) })
	end
	return slot
end

-- A floating "+$1.2K" (the controller moves and fades it).
function HudView.floater(parent: Instance, text: string): TextLabel
	return UIKit.label(parent, text, 28, {
		Name = "Floater",
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.fromOffset(HudView.CoinsWidth - 60, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
end

export type OfflineRefs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Amount: TextLabel,
	Detail: TextLabel,
	Collect: TextButton,
}

-- "Welcome back! While you were away: +$12.4K" with a COLLECT button.
function HudView.buildOffline(): OfflineRefs
	local gui = UIKit.screen("TerraForgeOffline", 30)
	gui.Enabled = false
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, gui)
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 300),
	})
	UIKit.label(panel, "WELCOME BACK!", 34, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	UIKit.label(panel, "While you were away you earned", 20, {
		Name = "Lead",
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 26),
		TextColor3 = Theme.TextDim,
	})
	local icon = coinIcon(panel, 44)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, -120, 0, 100)
	local amount = UIKit.label(panel, "+$0", 44, {
		Name = "Amount",
		Position = UDim2.new(0.5, -88, 0, 96),
		Size = UDim2.fromOffset(300, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	local detail = UIKit.label(panel, "", 17, {
		Name = "Detail",
		Position = UDim2.fromOffset(24, 156),
		Size = UDim2.new(1, -48, 0, 48),
		TextColor3 = Theme.TextDim,
	})
	local collect = UIKit.button(panel, "COLLECT", Theme.Good, Theme.GoodDark, {
		Name = "Collect",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, 60),
		TextSize = 26,
	})
	return { Gui = gui, Dim = dim, Panel = panel, Amount = amount, Detail = detail, Collect = collect }
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
