--[[
	The tutorial bubble (pure builder + layout math; TutorialController
	fills it in and handles input). Its own ScreenGui "TerraForgeTutorial"
	(DisplayOrder 4: under the HUD's toasts, over the blaster's crosshair).

	  +--------------------------------------+
	  | (3 / 8)  LOAD THE TRAIN               |
	  | Throw the ore into the big hopper at  |
	  | the station.                          |
	  | Hold Q, then let go      [GOT IT][SKIP]|
	  +--------------------------------------+

	Where it goes (TutorialView.layout):
	  mouse     the bottom-right corner (the right-side menu is centred above
	            it, the HUD's bottom group in the middle; a narrow screen
	            lifts the bubble over it)
	  gamepad   the same corner, kept TenFootSafe of the screen from the
	            edges (the TV's title-safe area)
	  touch     the top-right corner: the bottom right is the jump and throw
	            buttons, the bottom left the thumbstick. As wide as the room
	            right of the teleport bar allows (MinWidth .. MaxWidth); the
	            buttons are RowTouch tall (>= 44 pt at uiScale 0.62). The
	            FREE SPIN! chip's spot: the chip waits while the bubble shows
	            (WheelView.chipVisible)
	SKIP asks once more ("SURE?") before it counts. GOT IT shows only on an
	info step (TutorialConfig Optional), the hint line on the others.
	A step-done pop and the finish card are tweens in the controller.
	With UIConfig.lightUI() on (the light UI, ships off) the bubble and the
	card wear the light look (LightSkin) and the touch bubble keeps clear of
	the light HUD's tabs.

	Designed for 720 design units of height (HudController scales every
	TerraForge gui).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local UIConfig = require(Shared.Config.UIConfig)
local UIKit = require(script.Parent.UIKit)
local TeleportView = require(script.Parent.TeleportView)
local HudBubble = require(script.Parent.HudBubble)
local LightSkin = require(script.Parent.LightSkin)

local TutorialView = {}

export type Layout = {
	AnchorPoint: Vector2,
	Position: Vector2, -- design units from the top-left of the screen
	Width: number,
	Height: number,
	BodyHeight: number,
	RowHeight: number, -- the GOT IT / SKIP buttons' height
	Touch: boolean,
}

export type Refs = {
	Gui: ScreenGui,
	Bubble: Frame,
	Counter: TextLabel,
	Title: TextLabel,
	Body: TextLabel,
	Hint: TextLabel,
	Skip: TextButton,
	Ack: TextButton,
	PadGlyph: ImageLabel,
	Done: Frame,
	DoneText: TextLabel,
	Pointer: Frame, -- the on-screen arrow at a side-menu button (a step's UiTarget)
}

TutorialView.Margin = 14 -- design units from the screen's right edge
TutorialView.Bottom = 16 -- design units from the bottom (mouse / gamepad)
TutorialView.Top = 10 -- design units from the top (touch, below Roblox's top bar)
TutorialView.TenFootSafe = 0.05 -- share of the screen kept free at each edge on a TV
TutorialView.Width = 380 -- mouse / gamepad
TutorialView.MaxWidth = 340 -- touch: at most ...
TutorialView.MinWidth = 236 -- ... and at least this wide
TutorialView.BarGap = 10 -- touch: room kept between the teleport bar and the bubble
TutorialView.RowMouse = 38
TutorialView.RowTouch = 72 -- 72 x 0.62 = 44.6 pt
TutorialView.Head = 40 -- the counter + title row; the text starts under it
TutorialView.Gap = 4 -- between the text and the button row
TutorialView.Foot = 9 -- under the button row (the buttons' lip hangs 5 into it)
TutorialView.Body = 48 -- the text's height (two lines; touch: up to BodyTouch)
TutorialView.BodyTouch = 64 -- three lines on the narrow phone bubble
TutorialView.BodyMin = 40 -- the text shrinks to this before the bubble reaches the right-side menu
TutorialView.MenuGap = 8 -- touch: room kept above the right-side menu's top button
TutorialView.SkipWidth = 84
TutorialView.AckWidth = 112

-- The panels the steps send the player to (the Ore Pen for Clean, Tobin's
-- counter and the Tech shop for Grow, the Blaster Vault for Blaster): the bubble
-- stays up beside them. Any other open panel (MenuPanels.Names: the side
-- menu's CODEX, GOLEMS, ARTIFACTS, BOOSTS, SETTINGS, HALL OF FAME, the
-- wheel, the shops...) has the screen: the bubble and the guide hide and
-- R3 is free (TutorialController).
TutorialView.StepPanels = { "PenController", "SellController", "TechShopController", "VaultController" }

-- Does one of these open panels hide the bubble?
function TutorialView.panelHides(open: { string }): boolean
	for _, name in open do
		if not table.find(TutorialView.StepPanels, name) then
			return true
		end
	end
	return false
end

-- The bubble's height for a text height and a button row height.
function TutorialView.height(body: number, row: number): number
	return TutorialView.Head + body + TutorialView.Gap + row + TutorialView.Foot
end

-- The bubble's place and size for a uiScale, the screen size in pt and the
-- input. `menuTop` (design units) is the top of the right-side menu's
-- buttons: the touch bubble keeps above it.
function TutorialView.layout(uiScale: number, screen: Vector2, touch: boolean, tenFoot: boolean?, menuTop: number?): Layout
	local scale = if uiScale > 0 then uiScale else 1
	local w, h = screen.X / scale, screen.Y / scale
	if touch then
		local barRight
		if UIConfig.lightUI() then
			-- the light HUD's top bar (HudBubble.buildGame: its size for this screen, the round
			-- look's four wider buttons too)
			local light = HudBubble.layout(scale, screen.X)
			barRight = w / 2 + HudBubble.topBarSize(light).X / 2
		else
			local bar = TeleportView.layout(scale, screen.X)
			barRight = w / 2 + (TeleportView.barWidth(bar, 3) + 44 + bar.Gap) / 2
		end
		local room = w - TutorialView.Margin - barRight - TutorialView.BarGap
		local width = math.clamp(room, TutorialView.MinWidth, TutorialView.MaxWidth)
		local row = TutorialView.RowTouch
		local body = if width < 300 then TutorialView.BodyTouch else TutorialView.Body
		if menuTop then
			local above = menuTop - TutorialView.MenuGap - TutorialView.Top - TutorialView.height(0, row)
			body = math.clamp(math.floor(above), TutorialView.BodyMin, body)
		end
		return {
			AnchorPoint = Vector2.new(1, 0),
			Position = Vector2.new(w - TutorialView.Margin, TutorialView.Top),
			Width = width,
			Height = TutorialView.height(body, row),
			BodyHeight = body,
			RowHeight = row,
			Touch = true,
		}
	end
	local right, bottom = TutorialView.Margin, TutorialView.Bottom
	if tenFoot then
		right = math.max(right, w * TutorialView.TenFootSafe)
		bottom = math.max(bottom, h * TutorialView.TenFootSafe)
	end
	-- a narrow screen (4:3): over the HUD's bottom group (the light HUD's BLASTER slot and
	-- backpack button, centred; the dark HUD's backpack button) when the bubble would reach it
	local _, groupRight = HudBubble.carrySpan(scale, tenFoot, UIConfig.lightUI(), w)
	local group = HudBubble.carryGroupSize(scale <= HudBubble.CompactScale)
	local packRight = w / 2 + groupRight
	if w - right - TutorialView.Width < packRight + TutorialView.BarGap then
		bottom = math.max(bottom, HudBubble.BackpackBottom + group.Y + TutorialView.BarGap)
	end
	local body, row = TutorialView.Body, TutorialView.RowMouse
	return {
		AnchorPoint = Vector2.new(1, 1),
		Position = Vector2.new(w - right, h - bottom),
		Width = TutorialView.Width,
		Height = TutorialView.height(body, row),
		BodyHeight = body,
		RowHeight = row,
		Touch = false,
	}
end

local function sizeLimit(label: TextLabel, max: number, min: number)
	label.TextScaled = true
	UIKit.new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min }, label)
end

-- Builds the ScreenGui (not parented) with the bubble and the finish card.
function TutorialView.build(): Refs
	local gui = UIKit.screen("TerraForgeTutorial", 4)
	gui:SetAttribute("TerraForge", true)
	local bubble = UIKit.panel(gui, {
		Name = "Bubble",
		Visible = false,
		Active = false,
	})
	local counter = UIKit.chip(bubble, "1 / " .. TutorialConfig.Total, Theme.Accent, {
		Name = "Counter",
		Position = UDim2.fromOffset(12, 11),
		Size = UDim2.fromOffset(58, 26),
		TextSize = 16,
	})
	local title = UIKit.label(bubble, "", 24, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	sizeLimit(title, 24, 14)
	local body = UIKit.label(bubble, "", 18, {
		Name = "Body",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	sizeLimit(body, 18, 12)
	local hint = UIKit.label(bubble, "", 16, {
		Name = "Hint",
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	sizeLimit(hint, 16, 11)
	local skip = UIKit.button(bubble, "SKIP", Theme.PanelLight, Theme.PanelDark, { Name = "Skip", TextSize = 18 })
	local ack = UIKit.button(bubble, "GOT IT", Theme.Good, Theme.GoodDark, { Name = "Ack", TextSize = 18 })
	local glyph = UIKit.new("ImageLabel", {
		Name = "PadGlyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, bubble)

	-- the finish card: a short "Tutorial complete!" with the reward
	local done = UIKit.panel(gui, {
		Name = "Done",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 128),
		Visible = false,
	})
	UIKit.label(done, "TUTORIAL COMPLETE!", 30, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, 40),
	})
	local doneText = UIKit.label(done, "", 20, {
		Name = "Text",
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 0, 52),
	})
	-- the on-screen arrow: a chevron pointing left, at a side-menu button
	local pointer = UIKit.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(TutorialView.PointerSize, TutorialView.PointerSize),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
	}, gui)
	for _, side in { -1, 1 } do
		local arm = UIKit.new("Frame", {
			Name = if side < 0 then "ArmTop" else "ArmBottom",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, side * 11),
			Size = UDim2.fromOffset(40, 14),
			Rotation = side * 40,
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, pointer)
		UIKit.corner(arm, 7)
		UIKit.stroke(arm, 3)
	end
	local refs: Refs = {
		Gui = gui,
		Pointer = pointer,
		Bubble = bubble,
		Counter = counter,
		Title = title,
		Body = body,
		Hint = hint,
		Skip = skip,
		Ack = ack,
		PadGlyph = glyph,
		Done = done,
		DoneText = doneText,
	}
	TutorialView.apply(refs, TutorialView.layout(1, Vector2.new(1280, 720), false))
	if UIConfig.lightUI() then
		LightSkin.apply(gui)
	end
	return refs
end

-- Places the bubble and everything in it for a layout.
function TutorialView.apply(refs: Refs, layout: Layout)
	local w = layout.Width
	local bubble = refs.Bubble
	bubble.AnchorPoint = layout.AnchorPoint
	bubble.Position = UDim2.fromOffset(layout.Position.X, layout.Position.Y)
	bubble.Size = UDim2.fromOffset(w, layout.Height)
	refs.Title.Position = UDim2.fromOffset(80, 8)
	refs.Title.Size = UDim2.fromOffset(w - 92, 28)
	refs.Body.Position = UDim2.fromOffset(14, TutorialView.Head)
	refs.Body.Size = UDim2.fromOffset(w - 28, layout.BodyHeight)
	local rowY = TutorialView.Head + layout.BodyHeight + TutorialView.Gap
	local row = layout.RowHeight
	-- the buttons' holders carry the size (UIKit.button); their lip hangs 5 below
	local skipHolder = refs.Skip.Parent :: Frame
	local ackHolder = refs.Ack.Parent :: Frame
	skipHolder.Position = UDim2.fromOffset(w - 12 - TutorialView.SkipWidth, rowY + 5)
	skipHolder.Size = UDim2.fromOffset(TutorialView.SkipWidth, row)
	ackHolder.Position = UDim2.fromOffset(w - 12 - TutorialView.SkipWidth - 8 - TutorialView.AckWidth, rowY + 5)
	ackHolder.Size = UDim2.fromOffset(TutorialView.AckWidth, row)
	refs.Hint.Position = UDim2.fromOffset(14, rowY)
	refs.Hint.Size = UDim2.fromOffset(w - 28 - TutorialView.SkipWidth - 8, row)
	refs.PadGlyph.Position = UDim2.fromOffset(w - 12 - TutorialView.SkipWidth, rowY)
end

-- The gamepad glyph (its image, "" = hidden) on the corner of SKIP, or of GOT IT on an info step.
function TutorialView.setGlyph(refs: Refs, image: string, onAck: boolean)
	local glyph = refs.PadGlyph
	glyph.Image = image
	glyph.Visible = image ~= ""
	local holder = (if onAck then refs.Ack.Parent else refs.Skip.Parent) :: Frame
	glyph.Position = UDim2.fromOffset(holder.Position.X.Offset, holder.Position.Y.Offset - 5)
end

-- Fills the bubble with a step (index 1 .. Total).
function TutorialView.setStep(refs: Refs, index: number, step: TutorialConfig.Step, hint: string?)
	refs.Counter.Text = TutorialConfig.counter(index)
	refs.Title.Text = string.upper(step.Title)
	refs.Body.Text = step.Text
	local optional = step.Optional == true
	refs.Hint.Text = hint or ""
	refs.Hint.Visible = not optional and hint ~= nil
	local ackHolder = refs.Ack.Parent :: Frame
	ackHolder.Visible = optional
	TutorialView.setSkipAsk(refs, false)
end

-- SKIP's two looks: "SKIP", then "SURE?" (red) until the second press or a timeout.
function TutorialView.setSkipAsk(refs: Refs, asking: boolean)
	refs.Skip.Text = if asking then "SURE?" else "SKIP"
	refs.Skip.BackgroundColor3 = if asking then Theme.Bad else Theme.PanelLight
	local holder = refs.Skip.Parent :: Frame
	holder.BackgroundColor3 = if asking then Theme.BadDark else Theme.PanelDark
end

TutorialView.PointerSize = 56
TutorialView.PointerGap = 8 -- design units between the button's right edge and the arrow

-- Where the arrow goes for a button: right of the menu (`rightEdge`, the
-- column's right side: a grid's other buttons stay clear), level with the
-- button (design units in the tutorial's gui, from absolute pixels and the
-- gui's scale).
function TutorialView.pointerSpot(buttonPos: Vector2, buttonSize: Vector2, guiPos: Vector2, scale: number, rightEdge: number?): Vector2
	local s = if scale > 0 then scale else 1
	local right = math.max(buttonPos.X + buttonSize.X, rightEdge or 0)
	local x = (right - guiPos.X) / s + TutorialView.PointerGap
	local y = (buttonPos.Y + buttonSize.Y / 2 - guiPos.Y) / s
	return Vector2.new(x, y)
end

-- The finish card's line ("+250 coins" when there was a reward).
function TutorialView.doneText(reward: number?): string
	if reward and reward > 0 then
		return `Nice work, forger! +{reward} coins`
	end
	return "Nice work, forger!"
end

-- The bubble's buttons with their on-screen size in pt (for the touch-size tests).
function TutorialView.touchTargets(refs: Refs, uiScale: number): { { Name: string, Width: number, Height: number } }
	local out = {}
	for _, button in { refs.Skip, refs.Ack } do
		local holder = button.Parent :: Frame
		table.insert(out, {
			Name = holder.Name,
			Width = holder.Size.X.Offset * uiScale,
			Height = holder.Size.Y.Offset * uiScale,
		})
	end
	return out
end

return TutorialView
