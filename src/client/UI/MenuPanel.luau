--[[
	MenuPanel: the shared frame of the side menu's panels (ORE CODEX,
	SETTINGS, HALL OF FAME): pure builder + layout math, so the Lune preview
	tools draw the same thing. One ScreenGui per panel:

	  header  the title (and a subtitle line on big screens), the red X
	          button top right (with the gamepad's B glyph on a gamepad)
	  body    an empty Frame the panel fills in
	  footer  the control hint: a text (big screens only), or with a
	          gamepad the platform's own button glyphs and a word for each
	          (always: TVs and phones with a gamepad need them most)

	Designed for 720 design units of height (HudController.uiScale scales
	every TerraForge gui). The compact layout (phones, TVs) makes the X
	button 72 units (44 pt at the phone scale 0.62) and drops the subtitle
	and the text footer. layout() fits the panel into the room it gets and
	keeps it clear of the HUD's teleport bar (top centre; the panel loses
	up to 15 % of its height for that, else it covers the bar whole) and of
	the coins (top left) when there is space. Call setHint before layout:
	the gamepad footer's room is reserved when it shows.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local LightSkin = require(script.Parent.LightSkin)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)
local TeleportView = require(script.Parent.TeleportView)

local MenuPanel = {}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Close: TextButton,
	CloseGlyph: ImageLabel,
	Body: Frame,
	Hint: TextLabel,
	PadHint: Frame,
	Compact: boolean,
	PadMode: boolean,
}

export type Glyph = { Image: string, Word: string }

MenuPanel.Pad = 16
MenuPanel.PhoneScale = 0.62 -- HudController's floor (phones)
MenuPanel.MinTouch = 44 -- points
MenuPanel.CoinsBottom = 96 -- HudView's coins panel (16..90) and a gap
-- under HudView's teleport bar (its frame is TopBarHeight tall; the phone
-- buttons are taller and stick out evenly) and a gap
MenuPanel.TopBarBottom = HudView.TopBarY
	+ (HudView.TopBarHeight + math.max(HudView.TopBarHeight, TeleportView.layout(TeleportView.CompactScale).Height)) / 2
	+ 6
MenuPanel.BarShrink = 0.85 -- a panel may lose up to 15 % of its height to stay under the teleport bar
MenuPanel.PadFooter = 30 -- the gamepad footer's room (compact layouts too)
MenuPanel.Metrics = {
	Normal = { Header = 70, Footer = 30, Close = 54, Title = 34 },
	Compact = { Header = 84, Footer = 8, Close = 72, Title = 32 },
}

-- The compact layout: touch screens, TVs, small scales and short windows.
function MenuPanel.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end
MenuPanel.holderOf = holderOf

function MenuPanel.build(name: string, title: string, subtitle: string, displayOrder: number?): Refs
	local gui = UIKit.screen(name, displayOrder or 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 480),
		Active = true,
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local titleLabel = UIKit.label(panel, title, 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitleLabel = UIKit.label(panel, subtitle, 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
	})
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 1, -2),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 3,
		Visible = false,
	}, holderOf(close))
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
	}, panel)
	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	UIKit.list(padHint, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = titleLabel,
		Subtitle = subtitleLabel,
		Close = close,
		CloseGlyph = glyph,
		Body = body,
		Hint = hint,
		PadHint = padHint,
		Compact = false,
		PadMode = false,
	}
	MenuPanel.layout(refs, false, 600, 480, math.huge, math.huge)
	return refs
end

-- Sizes the panel (wanted width x height, shrunk to the room it gets) and
-- places the header, body and footer. Returns the body's size.
function MenuPanel.layout(
	refs: Refs,
	compact: boolean,
	width: number,
	height: number,
	maxWidth: number,
	maxHeight: number
): Vector2
	refs.Compact = compact
	local m = if compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal
	local footer = if refs.PadMode then math.max(m.Footer, MenuPanel.PadFooter) else m.Footer
	local pad = MenuPanel.Pad
	local w = math.min(width, maxWidth - 16)
	local h = math.min(height, maxHeight - 8)
	if maxWidth < 1e6 and maxHeight < 1e6 then
		local left = (maxWidth - w) / 2
		local top = (maxHeight - h) / 2
		-- the teleport bar (top centre, under every panel's middle) would
		-- peek out above the panel: go under it when the panel can stay
		-- nearly whole, else cover it from the top
		if top < MenuPanel.TopBarBottom then
			local room = maxHeight - MenuPanel.TopBarBottom - 8
			if room >= h * MenuPanel.BarShrink then
				h = math.min(h, room)
				top = MenuPanel.TopBarBottom + (room - h) / 2
			else
				top = 4
			end
		end
		-- the HUD coins (top left) would peek out from under the panel: move
		-- the panel below them, else to their right when there is room
		-- (phones: the panel covers them, nearly whole)
		local coinsRight = 16 + HudView.CoinsWidth + 8
		if left < coinsRight and top < MenuPanel.CoinsBottom then
			local below = maxHeight - MenuPanel.CoinsBottom - 8
			if below >= h then
				top = MenuPanel.CoinsBottom + (below - h) / 2
			elseif maxWidth - w - 8 >= coinsRight then
				left = coinsRight + (maxWidth - w - 8 - coinsRight) / 2
			end
		end
		refs.Panel.AnchorPoint = Vector2.new(0, 0)
		refs.Panel.Position = UDim2.fromOffset(math.max(4, left), math.max(4, top))
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	refs.Panel.Size = UDim2.fromOffset(w, h)

	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -pad + 4, 0, if compact then 8 else 12)
	refs.Close.TextSize = if compact then 30 else 26
	refs.Title.TextSize = m.Title
	refs.Title.Position = UDim2.fromOffset(pad, if compact then 18 else 8)
	refs.Title.Size = UDim2.new(1, -(pad * 2 + m.Close + 8), 0, 40)
	refs.Subtitle.Position = UDim2.fromOffset(pad, 46)
	refs.Subtitle.Size = UDim2.new(1, -(pad * 2 + m.Close + 8), 0, 20)
	refs.Subtitle.Visible = not compact
	refs.Body.Position = UDim2.fromOffset(pad, m.Header)
	refs.Body.Size = UDim2.new(1, -pad * 2, 1, -(m.Header + footer))
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -pad * 2, 0, 20)
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, -4)
	refs.PadHint.Size = UDim2.new(1, -pad * 2, 0, 24)
	refs.Hint.Visible = not compact and not refs.PadMode
	refs.PadHint.Visible = refs.PadMode
	return Vector2.new(w - pad * 2, h - m.Header - footer)
end

-- The footer: a text, or (gamepad) glyph images with a word after each.
-- Switching between the two can change the body's room (compact layouts):
-- lay the panel out again after it (the controllers do: glyphs, then fit).
function MenuPanel.setHint(refs: Refs, text: string, glyphs: { Glyph }?)
	refs.Hint.Text = text
	refs.PadMode = glyphs ~= nil
	for _, child in refs.PadHint:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if glyphs then
		for i, g in glyphs do
			UIKit.new("ImageLabel", {
				Name = "Glyph" .. i,
				LayoutOrder = i * 2 - 1,
				Size = UDim2.fromOffset(24, 24),
				BackgroundTransparency = 1,
				Image = g.Image,
			}, refs.PadHint)
			UIKit.label(refs.PadHint, g.Word, 15, {
				Name = "Word" .. i,
				LayoutOrder = i * 2,
				Size = UDim2.fromOffset(#g.Word * 9 + 6, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.TextDim,
				TextWrapped = false,
			})
		end
	end
	refs.Hint.Visible = not refs.Compact and not refs.PadMode
	refs.PadHint.Visible = refs.PadMode
end

-- The B glyph on the close button (gamepads only).
function MenuPanel.setCloseGlyph(refs: Refs, image: string?)
	refs.CloseGlyph.Visible = image ~= nil and image ~= ""
	refs.CloseGlyph.Image = image or ""
end

-- Chunky selectable button styling for an on / off state.
function MenuPanel.style(button: TextButton, color: Color3, dark: Color3)
	button.BackgroundColor3 = color
	local holder = button.Parent
	if holder and holder:IsA("Frame") then
		holder.BackgroundColor3 = dark
	end
end


---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- While the light UI is on (ships off), the same window wears the light
-- look (LightSkin); windows also hide Roblox's touch controls while open.
local darkBuild = MenuPanel.build
MenuPanel.build = function(name: string, title: string, subtitle: string, displayOrder: number?): Refs
	local refs = darkBuild(name, title, subtitle, displayOrder)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return MenuPanel
