--[[
	The quick-teleport buttons (pure builder + layout math; TeleportController
	fills them in and handles input).

	  bar      HudView's TopBar at the top centre: BASE / LOBBY / VAULT, chunky
	           buttons in the spot colours (TeleportConfig.Spots, Bar = true),
	           the name in the middle (words only, no emoji: the owner's "text
	           only"); on phones (compact) the buttons are taller so they are
	           big enough to tap (>= 44 pt at uiScale 0.62)
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
local Bubble = require(script.Parent.Bubble)
local HudBubble = require(script.Parent.HudBubble)
local Pop = require(script.Parent.Pop)
local PopTheme = require(Shared.Config.PopTheme)

local TeleportView = {}

type Spot = TeleportConfig.Spot

-- Tall: the phones' taller buttons; Narrow: the smallest phones' squares (a smaller name)
export type Layout = { Width: number, Height: number, Gap: number, Tall: boolean, Narrow: boolean }

export type Refs = {
	Buttons: { [string]: TextButton },
	Covers: { [string]: TextLabel },
	Hint: ImageLabel,
}

TeleportView.CompactScale = 0.75 -- at this uiScale and below the bar uses the tall phone buttons
TeleportView.NarrowWidth = 600 -- screens narrower than this (pt) get square buttons (the coins panel needs the room)

-- Button sizes for a uiScale and the screen width in pt (design units).
function TeleportView.layout(uiScale: number, screenWidth: number?): Layout
	if screenWidth and screenWidth < TeleportView.NarrowWidth then
		-- small phones: square buttons, still >= 44 pt at uiScale 0.62
		return { Width = 74, Height = 72, Gap = 8, Tall = true, Narrow = true }
	elseif uiScale <= TeleportView.CompactScale then
		return { Width = 112, Height = 72, Gap = 8, Tall = true, Narrow = false }
	end
	return { Width = 132, Height = 54, Gap = 10, Tall = false, Narrow = false }
end

-- Width of the bar's buttons in a layout (design units).
function TeleportView.barWidth(layout: Layout, count: number): number
	return count * layout.Width + math.max(0, count - 1) * layout.Gap
end

TeleportView.LabelText = 22 -- the name on the buttons
TeleportView.NarrowText = 18 -- on the narrow squares ("LOBBY" still fits 74 units)

-- The name in the middle of the button (no icon: words only).
local function place(button: TextButton, layout: Layout)
	local label = button:FindFirstChild("Label") :: TextLabel?
	if not label then
		return
	end
	label.Visible = true
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -8, 0, 30)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextSize = if layout.Narrow then TeleportView.NarrowText else TeleportView.LabelText
end

local function spotButton(parent: Instance, spot: Spot, order: number, size: Vector2): (TextButton, TextLabel)
	local button = UIKit.button(parent, "", spot.Color, spot.Dark, {
		Name = spot.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	button:SetAttribute("Teleport", spot.Id)
	UIKit.label(button, spot.Label, TeleportView.LabelText, {
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

-- The light HUD (UIConfig.LightUI): bubble tabs in the top bar with a dark
-- cover showing the seconds left over each (the elevator's tile comes from the
-- side menu's Elevator entry, SideMenuController).
local function buildBubble(topBar: Frame, uiScale: number): Refs
	local layout = HudBubble.layout(uiScale)
	if topBar:GetAttribute("Compact") ~= nil then
		local narrow = topBar:GetAttribute("Narrow") == true
		layout = HudBubble.layout(if topBar:GetAttribute("Compact") then 0.62 else 1, if narrow then 0 else nil)
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
		end
	end
	-- gamepad: left / right along the tabs
	local order: { TextButton } = {}
	for _, spot in TeleportConfig.Spots do
		local tab = buttons[spot.Id]
		if spot.Bar and tab then
			table.insert(order, tab)
		end
	end
	for i, tab in order do
		local links: any = tab
		pcall(function() -- (Lune's instances can't hold a nil Ref)
			links.NextSelectionLeft = order[i - 1]
		end)
		pcall(function()
			links.NextSelectionRight = order[i + 1]
		end)
	end
	return { Buttons = buttons, Covers = covers, Hint = hint }
end

-- The bar's colours (owner's BASE / MINE / SPAWN photo: blue, teal, purple).
TeleportView.Paints = { Base = "Blue", Lobby = "Teal", Vault = "Purple" } :: { [string]: string }

--[[
	The Pop bar (owner 2026-10-20): a dark rounded strip at the very top with
	a bright button per spot, a light rim inside each, the word in white with
	a black edge; text only. A dark cover shows the seconds left.
]]
local function buildPop(topBar: Frame): Refs
	local compact = topBar:GetAttribute("Compact") == true
	local narrow = topBar:GetAttribute("Narrow") == true
	local layout = HudBubble.layout(if compact then 0.62 else 1, if narrow then 0 else nil)
	local size = HudBubble.topBarButton(layout)
	local buttons: { [string]: TextButton } = {}
	local covers: { [string]: TextLabel } = {}
	local hint = UIKit.new("ImageLabel", {
		Name = "GamepadHint",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, topBar)
	local order: { TextButton } = {}
	for i, spot in TeleportConfig.Spots do
		if spot.Bar then
			local paint = Pop.paint(TeleportView.Paints[spot.Id] or "Slate")
			local button = Pop.button(topBar, spot.Label, paint, size, {
				Name = spot.Id,
				LayoutOrder = i,
			})
			button:SetAttribute("Teleport", spot.Id)
			local label = button:FindFirstChild("Label") :: TextLabel
			label.TextSize = if narrow then 24 elseif compact then 28 else 26
			-- the light rim inside the black border (the photo's glow)
			local rim = UIKit.new("Frame", {
				Name = "Rim",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 1, -6),
				ZIndex = 5,
			}, button)
			UIKit.corner(rim, 4)
			UIKit.new("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = paint.Top:Lerp(Color3.new(1, 1, 1), 0.55),
				Thickness = 2,
				Transparency = 0.15,
			}, rim)
			local cover = Pop.text(button, "", 26, {
				Name = "Cooldown",
				BackgroundColor3 = PopTheme.Outline,
				BackgroundTransparency = 0.35,
				Size = UDim2.fromScale(1, 1),
				Visible = false,
				ZIndex = 8,
			})
			UIKit.corner(cover, PopTheme.Corner)
			buttons[spot.Id], covers[spot.Id] = button, cover
			table.insert(order, button)
		end
	end
	for i, button in order do
		local links: any = button
		pcall(function() -- (Lune's instances can't hold a nil Ref)
			links.NextSelectionLeft = order[i - 1]
		end)
		pcall(function()
			links.NextSelectionRight = order[i + 1]
		end)
	end
	return { Buttons = buttons, Covers = covers, Hint = hint }
end

-- Fills HudView's TopBar with the bar spots (Bar = true; the elevator is in the left side menu).
function TeleportView.build(topBar: Frame, uiScale: number, screenWidth: number?): Refs
	if topBar:GetAttribute("Pop") then
		return buildPop(topBar)
	elseif topBar:GetAttribute("Bubble") then
		return buildBubble(topBar, uiScale)
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
