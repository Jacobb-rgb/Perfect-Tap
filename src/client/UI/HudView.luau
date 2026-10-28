--[[
	HUD layout (pure builder). Returns references the HudController fills in.
	  top-left     coins ("$1.23K") with the podium income under it ("+$12/s"),
	               floating "+$X" popups (Earned) below
	  top-center   the quick-teleport bar (TeleportView: BASE / LOBBY / VAULT),
	               the zone name + toast notifications under it
	  bottom       the backpack button right of the blaster's slot in Roblox's
	               own hotbar (HudBubble.backpackButton): the pack's picture
	               and "n / cap"; it opens the inventory (BackpackController).
	               The light HUD has its own BLASTER slot left of the button
	               instead of Roblox's hotbar, the pair centred
	               (HudBubble.carryGroup, BlasterSlotController)
	  right side   menu buttons (added by later steps)
	The "While you were away" popup is its own ScreenGui (buildOffline).
	While UIConfig.lightUI() is on, every builder here forwards to the light
	"Bubble" HUD (HudBubble: the same refs), so the controllers need no change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local UIConfig = require(Shared.Config.UIConfig)
local UIKit = require(script.Parent.UIKit)
local HudBubble = require(script.Parent.HudBubble)

local HudView = {}

HudView.CoinsWidth = 236
HudView.TopBarY = 10 -- the teleport bar at the top centre (design units)
HudView.TopBarWidth = 440
HudView.TopBarHeight = 58

export type Refs = {
	Gui: ScreenGui,
	Coins: TextLabel,
	CoinsPanel: Frame,
	Income: TextLabel,
	Floaters: Frame,
	Zone: TextLabel,
	Toasts: Frame,
	CarryPanel: Frame, -- the backpack button's holder (build mode hides it); the light HUD's: the whole bottom group
	Backpack: TextButton, -- the backpack button: opens the inventory (BackpackController)
	CarryLabel: TextLabel, -- the button's "n / cap"
	BlasterSlot: TextButton?, -- the light HUD's BLASTER slot (BlasterSlotController); nil here: Roblox's hotbar
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
	if UIConfig.lightUI() then
		return HudBubble.buildGame()
	end
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

	-- the backpack button right of the blaster's hotbar slot (the light HUD's button; phone sized on phones)
	local scale = HudBubble.screenScale()
	local carryPanel, backpack, carryLabel = HudBubble.backpackButton(gui, HudBubble.layout(scale), scale)

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
		Backpack = backpack,
		CarryLabel = carryLabel,
		BlasterSlot = nil,
		Menu = menu,
		TopBar = topBar,
	}
end

---------------------------------------------------------------- the backpack button
-- (one button for both looks: HudBubble's packButton; the light HUD adds the BLASTER slot)

HudView.backpackText = HudBubble.backpackText
HudView.backpackX = HudBubble.backpackX

-- "count / capacity" on the backpack button; a full backpack gets the red count and the FULL tag.
function HudView.setBackpack(refs: Refs, count: number, capacity: number)
	HudBubble.setBackpack(refs.Backpack, count, capacity)
end

-- The open key on the backpack button: a keyboard key, a gamepad glyph, or neither (touch).
function HudView.setBackpackKey(refs: Refs, text: string?, glyph: string?)
	HudBubble.setBackpackKey(refs.Backpack, text, glyph)
end

-- Places the bottom group for `uiScale`: the light HUD's stays centred, the dark HUD's
-- button keeps right of the blaster's hotbar slot (Roblox draws it in real pixels).
function HudView.placeBackpack(refs: Refs, uiScale: number, tenFoot: boolean?)
	HudBubble.placeBackpack(refs.CarryPanel, uiScale, tenFoot)
end

-- The BLASTER slot's key hint ("1" on a keyboard, nothing on touch or a gamepad); no-op on the dark HUD.
function HudView.setBlasterKey(refs: Refs, text: string?)
	local slot = refs.BlasterSlot
	if slot then
		HudBubble.setBackpackKey(slot, text, nil)
	end
end

-- The BLASTER slot's gold ring while the Blaster is in hand; no-op on the dark HUD.
function HudView.setBlasterEquipped(refs: Refs, on: boolean)
	local slot = refs.BlasterSlot
	if slot then
		HudBubble.setBlasterEquipped(slot, on)
	end
end

-- A floating "+$1.2K" (the controller moves and fades it).
function HudView.floater(parent: Instance, text: string): TextLabel
	if UIConfig.lightUI() then
		return HudBubble.floater(parent, text)
	end
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
	if UIConfig.lightUI() then
		return HudBubble.buildOffline()
	end
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
	if UIConfig.lightUI() then
		return HudBubble.toastColor(parent, text, color)
	end
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
