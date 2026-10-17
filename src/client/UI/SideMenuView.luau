--[[
	The side menu on the LEFT edge of the screen (pure builder + layout math;
	SideMenuController fills it in and handles input), like the button
	columns of popular simulators:

	  SHOP · GOLEMS · CODEX · ARTIFACTS · BOARDS · SETTINGS · STORE

	Chunky buttons in their own colours, an emoji icon over a short label.
	A red badge shows a count (CODEX: ores discovered since you last looked);
	a "SOON" chip marks a button whose feature isn't in the game yet.
	The column starts below the HUD coins and their "+$X" popups and is
	centred in the room under them; when one column doesn't fit (phones) the
	buttons make two columns (SideMenuView.Fits). On phones every button is
	at least 44 pt (SideMenuView.layout, SideMenuView.touchTargets for the
	tests). With a
	gamepad the D-pad Left glyph shows over the column (D-pad Left jumps
	into the menu).
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
	{ Id = "Golems", Label = "GOLEMS", Icon = "🗿", Color = rgb(110, 214, 92), Dark = rgb(52, 136, 50) },
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
SideMenuView.Normal = { Width = 84, Height = 64, Gap = 8 }
SideMenuView.Compact = { Width = 84, Height = 72, Gap = 6 }
SideMenuView.CompactScale = 0.75 -- at this uiScale and below: the phone buttons

export type Layout = {
	Columns: number,
	Rows: number,
	Width: number, -- one button
	Height: number,
	Gap: number,
	Top: number, -- the column's top (design units)
	Size: Vector2, -- the whole column
}

export type Refs = {
	Gui: ScreenGui,
	Column: Frame,
	Buttons: { [string]: TextButton },
	Badges: { [string]: TextLabel },
	Soon: { [string]: TextLabel },
	PadGlyph: ImageLabel,
	Order: { string },
}

-- The tries, in order: { columns, the lowest top }. One column under the
-- coins' popups, then two; on the smallest phones (568 x 320 pt) two
-- columns start right under the coins panel; three only past that.
SideMenuView.Fits = { { 1, SideMenuView.TopMin }, { 2, SideMenuView.TopMin }, { 2, SideMenuView.TopTight }, { 3, SideMenuView.TopTight } }

-- Where the buttons go for a uiScale and the screen's height in design
-- units (below the top bar).
function SideMenuView.layout(uiScale: number, designHeight: number, count: number?): Layout
	local n = count or #SideMenuView.Entries
	local m = if uiScale <= SideMenuView.CompactScale then SideMenuView.Compact else SideMenuView.Normal
	-- never under 44 pt on a touch screen
	local minSide = SideMenuView.MinTouch / math.max(uiScale, 0.1)
	local w = math.max(m.Width, math.ceil(minSide))
	local h = math.max(m.Height, if uiScale <= SideMenuView.CompactScale then math.ceil(minSide) else 0)
	local columns, rows, height, topMin = 1, n, 0, SideMenuView.TopMin
	for _, try in SideMenuView.Fits do
		columns, topMin = try[1], try[2]
		rows = math.ceil(n / columns)
		height = rows * h + (rows - 1) * m.Gap
		if height <= designHeight - topMin - SideMenuView.BottomMargin then
			break
		end
	end
	local top = math.max(topMin, math.floor((designHeight - height) / 2))
	local width = columns * w + (columns - 1) * m.Gap
	return { Columns = columns, Rows = rows, Width = w, Height = h, Gap = m.Gap, Top = top, Size = Vector2.new(width, height) }
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
	local gui = UIKit.screen("TerraForgeSideMenu", 6)
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

-- Places the buttons for a layout (row by row: left, right, next row...).
function SideMenuView.apply(refs: Refs, layout: Layout)
	refs.Column.Position = UDim2.fromOffset(SideMenuView.Left, layout.Top)
	refs.Column.Size = UDim2.fromOffset(layout.Size.X, layout.Size.Y)
	for i, id in refs.Order do
		local holder = refs.Buttons[id].Parent :: Frame
		local col = (i - 1) % layout.Columns
		local row = (i - 1) // layout.Columns
		holder.Position = UDim2.fromOffset(col * (layout.Width + layout.Gap), row * (layout.Height + layout.Gap) + 5)
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

-- Every tappable thing (for the touch-size tests).
function SideMenuView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = {}
	for _, id in refs.Order do
		table.insert(list, refs.Buttons[id].Parent :: Frame)
	end
	return list
end

return SideMenuView
