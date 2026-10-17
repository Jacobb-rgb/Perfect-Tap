--[[
	The side menu on the LEFT edge of the screen (pure builder + layout math;
	SideMenuController fills it in and handles input), like the button
	columns of popular simulators:

	  SHOP · GOLEMS · CODEX · ARTIFACTS · BOARDS · SETTINGS · STORE

	Chunky buttons in their own colours, an emoji icon over a short label.
	A red badge shows a count (CODEX: ores discovered since you last looked);
	a "SOON" chip marks a button whose feature isn't in the game yet (STORE).
	A button can be hidden (setHidden: GOLEMS / ARTIFACTS while their
	packages aren't in the game); the others close up.

	Where it goes (SideMenuView.layout):
	  mouse   one column below the HUD coins and their "+$X" popups, centred
	          in the room under them; two columns (or three) when one
	          doesn't fit (SideMenuView.Fits)
	  touch   (TouchEnabled, or uiScale <= CompactScale) the bottom-left
	          corner belongs to Roblox's movement thumbstick (the
	          DynamicThumbstick takes touches in the left 40 % of the screen,
	          below its top third): the buttons sit right under the coins
	          in up to four columns and end above TouchBottom (60 %) of the
	          height, so the 40 % x 40 % corner where the thumb rests stays
	          free (SideMenuView.TouchFits; SideMenu.spec checks phones and
	          tablets). Every button is at least 44 pt.
	  TV      (ten-foot) the column keeps SafeShare (5 %) of the width from the
	          left edge and of the height from the bottom: the title-safe area
	With a gamepad the D-pad Left glyph shows over the column (D-pad Left
	jumps into the menu). SideMenuView.touchTargets lists the shown buttons
	for the tests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)

local SideMenuView = {}

local rgb = Color3.fromRGB

export type Entry = { Id: string, Label: string, Icon: string, Color: Color3, Dark: Color3 }

SideMenuView.Entries = {
	{ Id = "Shop", Label = "SHOP", Icon = "🛒", Color = rgb(255, 120, 168), Dark = rgb(178, 58, 108) },
	{ Id = "Golems", Label = "GOLEMS", Icon = "🤖", Color = rgb(110, 214, 92), Dark = rgb(52, 136, 50) },
	{ Id = "Codex", Label = "CODEX", Icon = "📖", Color = rgb(96, 186, 255), Dark = rgb(38, 110, 186) },
	{ Id = "Collection", Label = "ARTIFACTS", Icon = "🏺", Color = rgb(255, 196, 72), Dark = rgb(186, 124, 26) },
	{ Id = "Boards", Label = "BOARDS", Icon = "🏆", Color = rgb(182, 118, 255), Dark = rgb(104, 56, 178) },
	{ Id = "Settings", Label = "SETTINGS", Icon = "⚙️", Color = rgb(150, 140, 132), Dark = rgb(88, 80, 74) },
	{ Id = "Store", Label = "STORE", Icon = "💰", Color = rgb(72, 200, 150), Dark = rgb(28, 120, 86) },
} :: { Entry }

SideMenuView.MinTouch = 44 -- points
SideMenuView.Left = 12 -- design units from the left edge
SideMenuView.TopMin = 150 -- below the coins panel (16..90) and the "+$X" popups under it
SideMenuView.TopTight = 98 -- right under the coins panel (the smallest phones)
SideMenuView.BottomMargin = 12
SideMenuView.Drop = 5 -- the buttons sit this far below the column's top (room for the badges)
SideMenuView.Normal = { Width = 84, Height = 64, Gap = 8 }
SideMenuView.Compact = { Width = 84, Height = 72, Gap = 6 }
SideMenuView.CompactScale = 0.75 -- at this uiScale and below: the phone buttons (and the touch layout)
-- touch layouts end above this share of the height: the thumbstick's corner below stays free
SideMenuView.TouchBottom = 0.6
-- TVs: the share of the screen kept clear at the edges (title safe)
SideMenuView.SafeShare = 0.05

export type Options = {
	Count: number?, -- the buttons shown (default: every entry)
	Touch: boolean?, -- a touch screen (UserInputService.TouchEnabled)
	TenFoot: boolean?, -- a TV (GuiService:IsTenFootInterface)
	DesignWidth: number?, -- the screen's width in design units (the TV margin)
}

export type Layout = {
	Columns: number,
	Rows: number,
	Width: number, -- one button
	Height: number,
	Gap: number,
	Left: number, -- the column's left edge (design units)
	Top: number, -- the column's top (design units)
	Size: Vector2, -- the whole column
	Touch: boolean, -- the touch layout (kept clear of the thumbstick)
}

export type Refs = {
	Gui: ScreenGui,
	Column: Frame,
	Buttons: { [string]: TextButton },
	Badges: { [string]: TextLabel },
	Soon: { [string]: TextLabel },
	Hidden: { [string]: boolean },
	PadGlyph: ImageLabel,
	Order: { string },
}

-- The tries, in order: { columns, the lowest top }; the first that fits wins.
-- Mouse: one column under the coins' popups, then two; on short windows
-- two columns start right under the coins panel; three only past that.
SideMenuView.Fits = { { 1, SideMenuView.TopMin }, { 2, SideMenuView.TopMin }, { 2, SideMenuView.TopTight }, { 3, SideMenuView.TopTight } }
-- Touch: must end above TouchBottom; wider before lower (under the popups
-- while that fits, then right under the coins); one row as the last resort.
SideMenuView.TouchFits = {
	{ 1, SideMenuView.TopMin },
	{ 2, SideMenuView.TopMin },
	{ 3, SideMenuView.TopMin },
	{ 4, SideMenuView.TopMin },
	{ 3, SideMenuView.TopTight },
	{ 4, SideMenuView.TopTight },
	{ 7, SideMenuView.TopTight },
}

-- Where the buttons go for a uiScale and the screen's height in design
-- units (below the top bar).
function SideMenuView.layout(uiScale: number, designHeight: number, options: Options?): Layout
	local o: Options = options or {}
	local n = math.max(1, o.Count or #SideMenuView.Entries)
	local compact = uiScale <= SideMenuView.CompactScale
	local touch = o.Touch == true or compact
	local tv = o.TenFoot == true
	local m = if compact then SideMenuView.Compact else SideMenuView.Normal
	-- never under 44 pt on a touch screen
	local minSide = SideMenuView.MinTouch / math.max(uiScale, 0.1)
	local w = math.max(m.Width, math.ceil(minSide))
	local h = math.max(m.Height, if touch then math.ceil(minSide) else 0)
	local bottomMargin = if tv then math.max(SideMenuView.BottomMargin, designHeight * SideMenuView.SafeShare) else SideMenuView.BottomMargin
	-- the lowest the column may end
	local floor = if touch then designHeight * SideMenuView.TouchBottom else designHeight - bottomMargin
	local columns, rows, height, topMin = 1, n, 0, SideMenuView.TopMin
	local fits: { { number } } = if touch then SideMenuView.TouchFits else SideMenuView.Fits
	for _, try in fits do
		columns, topMin = math.min(try[1], n), try[2]
		rows = math.ceil(n / columns)
		height = rows * h + (rows - 1) * m.Gap
		if topMin + SideMenuView.Drop + height <= floor then
			break
		end
	end
	-- mouse: centred in the room under the coins; touch: right under them
	local top = if touch then topMin else math.max(topMin, math.floor((designHeight - height) / 2))
	local left = SideMenuView.Left
	if tv and o.DesignWidth then
		left = math.max(left, math.ceil(o.DesignWidth * SideMenuView.SafeShare))
	end
	local width = columns * w + (columns - 1) * m.Gap
	return {
		Columns = columns,
		Rows = rows,
		Width = w,
		Height = h,
		Gap = m.Gap,
		Left = left,
		Top = top,
		Size = Vector2.new(width, height),
		Touch = touch,
	}
end

local function newButton(column: Frame, entry: Entry, order: number): (TextButton, TextLabel, TextLabel)
	local button = UIKit.button(column, "", entry.Color, entry.Dark, {
		Name = entry.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SideMenuView.Normal.Width, SideMenuView.Normal.Height),
	})
	button:SetAttribute("Menu", entry.Id)
	UIKit.label(button, entry.Icon, 28, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = false,
	})
	UIKit.label(button, entry.Label, 14, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -4, 0, 18),
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local holder = button.Parent :: Frame
	local badge = UIKit.chip(holder, "1", Theme.Bad, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.fromOffset(26, 26),
		TextSize = 16,
		ZIndex = 4,
		Visible = false,
	})
	UIKit.corner(badge, 13)
	local soon = UIKit.chip(holder, "SOON", Theme.PanelDark, {
		Name = "Soon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(46, 18),
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		ZIndex = 4,
		Visible = false,
	})
	return button, badge, soon
end

function SideMenuView.build(): Refs
	-- under the HUD (5 would be above): its "+$X" popups and toasts show on
	-- top where they meet the touch layout's wide grid
	local gui = UIKit.screen("TerraForgeSideMenu", 4)
	gui:SetAttribute("TerraForge", true)
	local column = UIKit.new("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SideMenuView.Left, SideMenuView.TopMin),
		-- a gamepad selection that jumped in stays in the menu
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local glyph = UIKit.new("ImageLabel", {
		Name = "PadGlyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0, SideMenuView.Normal.Width / 2, 0, -6),
		Size = UDim2.fromOffset(32, 32),
		Visible = false,
	}, column)
	local refs: Refs = {
		Gui = gui,
		Column = column,
		Buttons = {},
		Badges = {},
		Soon = {},
		Hidden = {},
		PadGlyph = glyph,
		Order = {},
	}
	for i, entry in SideMenuView.Entries do
		local button, badge, soon = newButton(column, entry, i)
		refs.Buttons[entry.Id] = button
		refs.Badges[entry.Id] = badge
		refs.Soon[entry.Id] = soon
		table.insert(refs.Order, entry.Id)
	end
	SideMenuView.apply(refs, SideMenuView.layout(1, 684))
	return refs
end

-- The ids of the buttons that show, in order.
function SideMenuView.shown(refs: Refs): { string }
	local list = {}
	for _, id in refs.Order do
		if not refs.Hidden[id] then
			table.insert(list, id)
		end
	end
	return list
end

-- Hides a button (a feature that isn't in the game); call apply with a
-- layout for the new count afterwards.
function SideMenuView.setHidden(refs: Refs, id: string, hidden: boolean)
	local button = refs.Buttons[id]
	if not button then
		return
	end
	if hidden then
		refs.Hidden[id] = true
	else
		refs.Hidden[id] = nil
	end
	local holder = button.Parent :: Frame
	holder.Visible = not hidden
end

-- Places the shown buttons for a layout (row by row: left to right, then
-- the next row).
function SideMenuView.apply(refs: Refs, layout: Layout)
	refs.Column.Position = UDim2.fromOffset(layout.Left, layout.Top)
	refs.Column.Size = UDim2.fromOffset(layout.Size.X, layout.Size.Y + SideMenuView.Drop)
	for i, id in SideMenuView.shown(refs) do
		local holder = refs.Buttons[id].Parent :: Frame
		local col = (i - 1) % layout.Columns
		local row = (i - 1) // layout.Columns
		holder.Position = UDim2.fromOffset(col * (layout.Width + layout.Gap), row * (layout.Height + layout.Gap) + SideMenuView.Drop)
		holder.Size = UDim2.fromOffset(layout.Width, layout.Height)
	end
	refs.PadGlyph.Position = UDim2.new(0, layout.Width / 2, 0, -2)
end

-- A count on a button's badge (0 hides it; 10 and more show "9+").
function SideMenuView.setBadge(refs: Refs, id: string, count: number)
	local badge = refs.Badges[id]
	if not badge then
		return
	end
	badge.Visible = count > 0
	badge.Text = if count >= 10 then "9+" else tostring(math.max(0, math.floor(count)))
	local soon = refs.Soon[id]
	if soon and badge.Visible then
		soon.Visible = false
	end
end

-- The "SOON" chip on a button whose feature isn't in the game yet.
function SideMenuView.setSoon(refs: Refs, id: string, on: boolean)
	local soon = refs.Soon[id]
	if soon then
		soon.Visible = on and not refs.Badges[id].Visible
	end
end

-- Every tappable button that shows (for the touch-size tests).
function SideMenuView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = {}
	for _, id in SideMenuView.shown(refs) do
		table.insert(list, refs.Buttons[id].Parent :: Frame)
	end
	return list
end

return SideMenuView
