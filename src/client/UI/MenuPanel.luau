--[[
	MenuPanel: the shared frame of the side menu's panels (ORE CODEX,
	SETTINGS, HALL OF FAME, STAR FORGE): pure builder + layout math, so the
	Lune preview tools draw the same thing. One ScreenGui per panel, in the
	Pop look (owner 2026-10-21: "new, modern, colourful, Roblox style", like
	the Robux Shop, Pop.window):

	  header  a bright band in the window's own colour (MenuPanel.paintFor:
	          Codex teal, Settings steel blue, Hall of Fame orange, Star Forge
	          periwinkle) with studs, a light rim and diagonal shine stripes;
	          the title in white chunky text with a black edge and a 3D drop
	          shadow (and a subtitle line on big screens), the red square X
	          (Pop.close; the gamepad's B glyph on it with a gamepad)
	  body    an empty Frame the panel fills in, over the dark studded floor
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

	build(..., pop = true): the window is rebuilt in the Pop kit inside too,
	so it never wears the LightSkin recolouring (attribute PopSkin). Other
	windows (old-kit contents) keep LightSkin while the light UI is on; the
	chrome is made so the skin leaves it alone (the X's word sits beside the
	button, not on its white face).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local PopTheme = require(Shared.Config.PopTheme)
local BubbleTheme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
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
	Compact = { Header = 84, Footer = 8, Close = 72, Title = 38 },
}
MenuPanel.Rim = 4 -- the black frame around the band and the body
MenuPanel.SoftInk = Color3.fromRGB(206, 214, 232) -- the footer's words

local rgb = Color3.fromRGB

-- The header colours (a window's own colour, LightSkin.BandRoles); a name
-- not listed gets its BandRoles role's colours, else orange.
MenuPanel.Paints = {
	TerraForgeCodex = PopTheme.Paints.Teal,
	TerraForgeSettings = { Top = rgb(100, 150, 255), Bottom = rgb(36, 72, 206), Edge = PopTheme.Outline },
	TerraForgeHallOfFame = PopTheme.Paints.Orange,
	TerraForgeRebirth = { Top = rgb(150, 150, 255), Bottom = rgb(80, 72, 230), Edge = PopTheme.Outline },
} :: { [string]: Pop.Paint }

function MenuPanel.paintFor(name: string): Pop.Paint
	local paint = MenuPanel.Paints[name]
	if paint then
		return paint
	end
	local role = BubbleTheme.Roles[LightSkin.BandRoles[name] or ""]
	if role then
		return { Top = role.Top, Bottom = role.Lip:Lerp(role.Base, 0.35), Edge = PopTheme.Outline }
	end
	return PopTheme.Paints.Orange
end

-- The compact layout: touch screens, TVs, small scales and short windows.
function MenuPanel.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end
MenuPanel.holderOf = holderOf

-- The title's drop shadow follows the title (a sibling under it: a child would draw on top).
function MenuPanel.syncTitle(refs: Refs)
	local title = refs.Title
	local shadow = refs.Panel:FindFirstChild("TitleShadow") :: TextLabel?
	if not shadow then
		return
	end
	shadow.Position = title.Position + UDim2.fromOffset(0, 4)
	shadow.Size = title.Size
	shadow.Text = title.Text
	shadow.TextSize = title.TextSize
	shadow.Visible = title.Visible
	shadow.TextXAlignment = title.TextXAlignment
	shadow.AnchorPoint = title.AnchorPoint
	local edge = title:FindFirstChild("Edge") :: UIStroke?
	local shadowEdge = shadow:FindFirstChildOfClass("UIStroke")
	if edge and shadowEdge then
		shadowEdge.Thickness = edge.Thickness
	end
end

-- The header band: the window's colour, studs, the light rim, a shine strip and diagonal stripes.
local function band(panel: Frame, paint: Pop.Paint): Frame
	local head = UIKit.new("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(MenuPanel.Rim, MenuPanel.Rim),
		ZIndex = 0, -- (under everything the window shows)
	}, panel)
	Pop.face(head, paint, 6, false)
	local border = head:FindFirstChild("Border") :: UIStroke
	border.Thickness = 3
	Pop.studs(head, 6, 0.35, 40, 0)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 0,
	}, head)
	for i, s in { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.6, 0),
			ZIndex = 0,
		}, head)
	end
	return head
end

-- The dark studded floor under the body (a gradient down, a shade under the header).
local function floor(panel: Frame): Frame
	local back = UIKit.new("Frame", {
		Name = "Back",
		BackgroundColor3 = PopTheme.Body,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, panel)
	UIKit.corner(back, 6)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(196, 198, 206)), Rotation = 90 }, back)
	Pop.studs(back, 6, 0.55, 36, 0)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 0,
	}, back)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	return back
end

local function popBuild(name: string, title: string, subtitle: string, displayOrder: number?): Refs
	local gui = UIKit.screen(name, displayOrder or 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 480),
		Active = true,
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	UIKit.corner(panel, PopTheme.WindowCorner + 2)
	Pop.border(panel, 4)
	floor(panel)
	band(panel, MenuPanel.paintFor(name))

	local titleLabel = Pop.text(panel, title, MenuPanel.Metrics.Normal.Title, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	Pop.shadow(titleLabel)
	local subtitleLabel = Pop.text(panel, subtitle, 15, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(255, 252, 236),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	-- the red X (its word beside the button: LightSkin'd windows ink words on white faces)
	local holder = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(54, 54),
		ZIndex = 4,
	}, panel)
	local close = Pop.close(holder, 54, { Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	local word = close:FindFirstChild("Label") :: TextLabel
	word.Parent = holder
	word.Name = "X"
	word.ZIndex = 5
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 1, -2),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 6,
		Visible = false,
	}, holder)
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, panel)
	local hint = Pop.text(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = MenuPanel.SoftInk,
		ZIndex = 2,
	})
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
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
	-- (in the game: the shadow follows a title a window changes after layout)
	pcall(function()
		for _, prop in { "Text", "Position", "Size", "TextSize", "Visible" } do
			titleLabel:GetPropertyChangedSignal(prop):Connect(function()
				MenuPanel.syncTitle(refs)
			end)
		end
	end)
	MenuPanel.layout(refs, false, 600, 480, math.huge, math.huge)
	return refs
end

-- Sizes the panel (wanted width x height, shrunk to the room it gets) and
-- places the header, body and footer. Returns the body's size.
function MenuPanel.layout(refs: Refs, compact: boolean, width: number, height: number, maxWidth: number, maxHeight: number): Vector2
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

	-- the band over the header's room, the dark floor under the rest
	local rim = MenuPanel.Rim
	local bandH = m.Header - 2 * rim
	local head = refs.Panel:FindFirstChild("Band") :: Frame?
	if head then
		head.Size = UDim2.new(1, -2 * rim, 0, bandH)
	end
	local back = refs.Panel:FindFirstChild("Back") :: Frame?
	if back then
		back.Position = UDim2.fromOffset(rim, rim + bandH)
		back.Size = UDim2.new(1, -2 * rim, 1, -(2 * rim + bandH))
	end

	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -pad + 4, 0, rim + math.floor((bandH - m.Close) / 2))
	local word = close:FindFirstChild("X") :: TextLabel?
	if word then
		word.TextSize = math.floor(m.Close * 0.66)
	end
	refs.Close.TextSize = if compact then 30 else 26
	refs.Title.TextSize = m.Title
	-- big screens: the title and the subtitle under it; compact: the title in the band's middle
	refs.Title.Position = UDim2.fromOffset(pad, if compact then rim + math.floor((bandH - 44) / 2) else 4)
	refs.Title.Size = UDim2.new(1, -(pad * 2 + m.Close + 8), 0, if compact then 44 else 40)
	refs.Subtitle.Position = UDim2.fromOffset(pad + 2, 42)
	refs.Subtitle.Size = UDim2.new(1, -(pad * 2 + m.Close + 10), 0, 20)
	refs.Subtitle.Visible = not compact
	refs.Body.Position = UDim2.fromOffset(pad, m.Header)
	refs.Body.Size = UDim2.new(1, -pad * 2, 1, -(m.Header + footer))
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -pad * 2, 0, 20)
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, -4)
	refs.PadHint.Size = UDim2.new(1, -pad * 2, 0, 24)
	refs.Hint.Visible = not compact and not refs.PadMode
	refs.PadHint.Visible = refs.PadMode
	MenuPanel.syncTitle(refs)
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
				ZIndex = 3,
			}, refs.PadHint)
			Pop.text(refs.PadHint, g.Word, 15, {
				Name = "Word" .. i,
				LayoutOrder = i * 2,
				Size = UDim2.fromOffset(#g.Word * 9 + 6, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = MenuPanel.SoftInk,
				ZIndex = 3,
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

-- Chunky selectable button styling for an on / off state (UIKit.button pairs).
function MenuPanel.style(button: TextButton, color: Color3, dark: Color3)
	button.BackgroundColor3 = color
	local holder = button.Parent
	if holder and holder:IsA("Frame") then
		holder.BackgroundColor3 = dark
	end
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- While the light UI is on, a window whose insides are still the old kit
-- wears the light look inside the Pop frame (LightSkin); a window rebuilt
-- in the Pop kit (`pop`) never does (attribute PopSkin). Windows also hide
-- Roblox's touch controls while open.
MenuPanel.build = function(name: string, title: string, subtitle: string, displayOrder: number?, pop: boolean?): Refs
	local refs = popBuild(name, title, subtitle, displayOrder)
	if pop then
		refs.Gui:SetAttribute("PopSkin", true)
	end
	if UIConfig.lightUI() then
		if not pop then
			LightSkin.apply(refs.Gui)
		end
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return MenuPanel
