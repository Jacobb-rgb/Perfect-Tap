--[[
	The quick-teleport buttons (pure builder + layout math; TeleportController
	fills them in and handles input).

	  bar      HudView's TopBar at the top centre: BASE / LOBBY / VAULT, chunky
	           buttons in the spot colours (TeleportConfig.Spots, Bar = true),
	           the icon left of the name; on phones (compact) the icon sits on
	           top so the button is tall enough to tap (>= 44 pt at uiScale 0.62)
	  side     the ELEVATOR icon in HudView's right-side Menu (under BUILD),
	           hidden until the world has an elevator
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
local Bubble = require(script.Parent.Bubble)
local HudBubble = require(script.Parent.HudBubble)

local TeleportView = {}

type Spot = TeleportConfig.Spot

export type Layout = { Width: number, Height: number, Gap: number, IconTop: boolean, IconOnly: boolean }

export type Refs = {
	Buttons: { [string]: TextButton },
	Covers: { [string]: TextLabel },
	Hint: ImageLabel,
	Side: TextButton?,
}

TeleportView.CompactScale = 0.75 -- at this uiScale and below the bar uses the tall phone buttons
TeleportView.NarrowWidth = 600 -- screens narrower than this (pt) show icons only (the coins panel needs the room)
TeleportView.SideSize = Vector2.new(84, 64) -- like the BUILD button

-- Button sizes for a uiScale and the screen width in pt (design units).
function TeleportView.layout(uiScale: number, screenWidth: number?): Layout
	if screenWidth and screenWidth < TeleportView.NarrowWidth then
		-- small phones: square icon buttons, still >= 44 pt at uiScale 0.62
		return { Width = 74, Height = 72, Gap = 8, IconTop = false, IconOnly = true }
	elseif uiScale <= TeleportView.CompactScale then
		return { Width = 112, Height = 72, Gap = 8, IconTop = true, IconOnly = false }
	end
	return { Width = 132, Height = 54, Gap = 10, IconTop = false, IconOnly = false }
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
	label.Visible = not layout.IconOnly
	if layout.IconOnly then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromOffset(40, 40)
	elseif layout.IconTop then
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

-- The light HUD (UIConfig.LightUI): bubble tabs in the top bar, the LIFT as a
-- menu tile (hidden until the world has an elevator), a dark cover with the
-- seconds left over each.
local function buildBubble(topBar: Frame, menu: Frame?, uiScale: number): Refs
	local layout = HudBubble.layout(uiScale)
	if topBar:GetAttribute("Compact") ~= nil then
		layout = HudBubble.layout(if topBar:GetAttribute("Compact") then 0.62 else 1)
	end
	local buttons: { [string]: TextButton } = {}
	local covers: { [string]: TextLabel } = {}
	local hint = UIKit.new("ImageLabel", {
		Name = "GamepadHint",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
	}, topBar)
	local side: TextButton? = nil
	local function cover(face: GuiObject): TextLabel
		local label = Bubble.text(face, "", 30, {
			Name = "Cooldown",
			BackgroundColor3 = Color3.fromRGB(15, 18, 40),
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 8,
		})
		UIKit.new("UICorner", { CornerRadius = UDim.new(0, 16) }, label)
		return label
	end
	for order, spot in TeleportConfig.Spots do
		if spot.Bar then
			local face = HudBubble.tab(topBar, HudBubble.spot(spot.Id, spot.Label), layout, order)
			face:SetAttribute("Teleport", spot.Id)
			buttons[spot.Id], covers[spot.Id] = face, cover(face)
		elseif menu then
			local face = HudBubble.claimTile(menu, spot.Id)
			face:SetAttribute("Teleport", spot.Id)
			local holder = face.Parent :: Frame
			holder.Visible = false
			buttons[spot.Id], covers[spot.Id] = face, cover(face)
			side = face
		end
	end
	return { Buttons = buttons, Covers = covers, Hint = hint, Side = side }
end

-- Fills HudView's TopBar (and puts the side icon into its Menu).
function TeleportView.build(topBar: Frame, menu: Frame?, uiScale: number, screenWidth: number?): Refs
	if topBar:GetAttribute("Bubble") then
		return buildBubble(topBar, menu, uiScale)
	end
	local layout = TeleportView.layout(uiScale, screenWidth)
	local buttons: { [string]: TextButton } = {}
	local covers: { [string]: TextLabel } = {}
	local hint = UIKit.new("ImageLabel", {
		Name = "GamepadHint",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
	}, topBar)
	local side: TextButton? = nil
	for order, spot in TeleportConfig.Spots do
		if spot.Bar then
			local button, cover = spotButton(topBar, spot, order, Vector2.new(layout.Width, layout.Height))
			place(button, layout)
			buttons[spot.Id], covers[spot.Id] = button, cover
		elseif menu then
			local button, cover = spotButton(menu, spot, 20 + order, TeleportView.SideSize)
			place(button, { Width = TeleportView.SideSize.X, Height = TeleportView.SideSize.Y, Gap = 0, IconTop = true, IconOnly = false })
			local holder = button.Parent :: Frame
			holder.Visible = false
			buttons[spot.Id], covers[spot.Id] = button, cover
			side = button
		end
	end
	local list = topBar:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, layout.Gap)
	end
	return { Buttons = buttons, Covers = covers, Hint = hint, Side = side }
end

-- Re-lays the bar's buttons for a new uiScale / screen width (phone <-> big screen).
function TeleportView.relayout(refs: Refs, topBar: Frame, uiScale: number, screenWidth: number?)
	if topBar:GetAttribute("Bubble") then
		return -- the light tabs keep the layout they were built with
	end
	local layout = TeleportView.layout(uiScale, screenWidth)
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

-- The elevator icon on the side shows only while the world has an elevator.
function TeleportView.setSideVisible(refs: Refs, visible: boolean)
	local side = refs.Side
	if side and side.Parent then
		(side.Parent :: Frame).Visible = visible
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
