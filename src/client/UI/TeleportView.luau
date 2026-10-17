--[[
	The quick-teleport buttons (pure builder + layout math; TeleportController
	fills them in and handles input).

	  bar      HudView's TopBar at the top centre: BASE / LOBBY / VAULT, chunky
	           buttons in the spot colours (TeleportConfig.Spots, Bar = true),
	           the icon left of the name; on phones (compact) the icon sits on
	           top so the button is tall enough to tap (>= 44 pt at uiScale 0.62)
	  (the elevator's button is not here: ElevatorController draws it in the
	  left side menu and sends the "Elevator" teleport; owner 2026-10-18)
	  hint     the gamepad glyph left of the bar (D-pad down jumps into the bar)
	  cooldown a dark cover with the seconds left over each button after a teleport
	  fade     its own ScreenGui: the screen goes dark during the jump

	Designed for 720 design units of height (HudController scales every
	TerraForge gui).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local TeleportConfig = require(Shared.Config.TeleportConfig)
local UIKit = require(script.Parent.UIKit)

local TeleportView = {}

type Spot = TeleportConfig.Spot

export type Layout = { Width: number, Height: number, Gap: number, IconTop: boolean }

export type Refs = {
	Buttons: { [string]: TextButton },
	Covers: { [string]: TextLabel },
	Hint: ImageLabel,
}

TeleportView.CompactScale = 0.75 -- at this uiScale and below the bar uses the tall phone buttons

-- Button sizes for a uiScale (design units).
function TeleportView.layout(uiScale: number): Layout
	if uiScale <= TeleportView.CompactScale then
		return { Width = 112, Height = 72, Gap = 8, IconTop = true }
	end
	return { Width = 132, Height = 54, Gap = 10, IconTop = false }
end

-- Width of the bar's buttons in a layout (design units).
function TeleportView.barWidth(layout: Layout, count: number): number
	return count * layout.Width + math.max(0, count - 1) * layout.Gap
end

local function place(button: TextButton, layout: Layout)
	local icon = button:FindFirstChild("Icon") :: TextLabel?
	local label = button:FindFirstChild("Label") :: TextLabel?
	if not icon or not label then
		return
	end
	if layout.IconTop then
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.Size = UDim2.new(1, 0, 0, 34)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.Size = UDim2.new(1, -8, 0, 24)
		label.TextXAlignment = Enum.TextXAlignment.Center
	else
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.Size = UDim2.fromOffset(34, 34)
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 46, 0.5, 0)
		label.Size = UDim2.new(1, -52, 0, 30)
		label.TextXAlignment = Enum.TextXAlignment.Left
	end
end

local function spotButton(parent: Instance, spot: Spot, order: number, size: Vector2): (TextButton, TextLabel)
	local button = UIKit.button(parent, "", spot.Color, spot.Dark, {
		Name = spot.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	button:SetAttribute("Teleport", spot.Id)
	UIKit.label(button, spot.Icon, 30, {
		Name = "Icon",
		TextScaled = false,
		TextWrapped = false,
	})
	UIKit.label(button, spot.Label, 22, {
		Name = "Label",
		FontFace = Theme.TitleFont,
		TextScaled = false,
		TextWrapped = false,
	})
	local cover = UIKit.label(button, "", 24, {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Theme.PanelDark,
		ZIndex = 3,
		Visible = false,
	})
	UIKit.corner(cover, 12)
	return button, cover
end

-- Fills HudView's TopBar with the bar spots (Bar = true).
function TeleportView.build(topBar: Frame, uiScale: number): Refs
	local layout = TeleportView.layout(uiScale)
	local buttons: { [string]: TextButton } = {}
	local covers: { [string]: TextLabel } = {}
	local hint = UIKit.new("ImageLabel", {
		Name = "GamepadHint",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
	}, topBar)
	for order, spot in TeleportConfig.Spots do
		if spot.Bar then
			local button, cover = spotButton(topBar, spot, order, Vector2.new(layout.Width, layout.Height))
			place(button, layout)
			buttons[spot.Id], covers[spot.Id] = button, cover
		end
	end
	local list = topBar:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, layout.Gap)
	end
	return { Buttons = buttons, Covers = covers, Hint = hint }
end

-- Re-lays the bar's buttons for a new uiScale (phone <-> big screen).
function TeleportView.relayout(refs: Refs, topBar: Frame, uiScale: number)
	local layout = TeleportView.layout(uiScale)
	for id, button in refs.Buttons do
		local spot = TeleportConfig.ById[id]
		if spot and spot.Bar then
			local holder = button.Parent :: Frame
			holder.Size = UDim2.fromOffset(layout.Width, layout.Height)
			place(button, layout)
		end
	end
	local list = topBar:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, layout.Gap)
	end
	topBar.Size = UDim2.fromOffset(TeleportView.barWidth(layout, 3) + 44 + layout.Gap, layout.Height + 4)
end

-- The seconds left on every button (0 = ready).
function TeleportView.setCooldown(refs: Refs, seconds: number)
	local text = if seconds > 0 then tostring(math.ceil(seconds)) else ""
	for _, cover in refs.Covers do
		cover.Visible = seconds > 0
		cover.Text = text
	end
end

-- The dark screen during a jump (its own ScreenGui over everything).
function TeleportView.buildFade(): (ScreenGui, Frame)
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeTeleportFade",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local cover = UIKit.new("Frame", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 8, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
	}, gui)
	return gui, cover
end

return TeleportView
