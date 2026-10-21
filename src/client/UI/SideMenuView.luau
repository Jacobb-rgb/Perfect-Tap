--[[
	The side menu on the LEFT edge of the screen (pure builder + layout math;
	SideMenuController fills it in and handles input), like the button
	columns of popular simulators:

	  GOLEMS · ELEVATOR · SHOP · CODEX · ARTIFACTS · BOARDS · SETTINGS · STORE · HOVER

	The entries are data (SideMenuView.Entries) for the coming light-UI
	restyle: each has a Group ("Main": the tiles that stay on screen;
	"More": the ones behind a MORE flyout), a stable Order inside its group
	(Main follows the light HUD's tiles BACKPACK 1, GOLEMS 2, SHOP 4; order 3,
	which the light UI had reserved for BUILD, is ELEVATOR since the mine
	floors (2026-10-18), so BUILD needs another slot; BACKPACK has no side
	menu controller yet; HOVER, the hoverboards, is "More" order 6: "BOARDS"
	is the leaderboards) and an IconName (the light HUD's 3D icon:
	HudBubble.EntryLooks). There is no MORE flyout yet, so every entry
	shows, sorted by Group then Order (SideMenuView.sorted).

	Chunky buttons in their own colours with a short label in the middle:
	words only, no emoji (the owner's "text only"; NoEmoji.spec).
	A red badge shows a count (CODEX: ores discovered since you last looked);
	a "SOON" chip inside a button's top-right corner marks a feature that
	isn't in the game yet (STORE). A button can be hidden (setHidden:
	GOLEMS / ARTIFACTS while their packages aren't in the game); the others
	close up.

	Where it goes (SideMenuView.layout). The left column under the coins has
	ONE order, so nothing in it covers anything else: the coins (16..90),
	their "+$X" popups, the TRAIN chip (TrainView, at ChipTop), the running
	boost chips (BoostView.chipsTop, a ChipHit-tall touch area), then this
	menu (SideMenu.spec intersects the rects on PC, 667 x 375 and 568 x 320):
	  mouse   one column below the boost chips' touch area (TopMin), centred
	          in the room under them; two columns (or more) when one
	          doesn't fit (SideMenuView.Fits)
	  touch   (MenuPanels.isTouch, or uiScale <= CompactScale) one MENU
	          button (a 44 pt square: the screen stays the game's) first in
	          the train chip's row, which starts right of it on these layouts
	          (TrainView.chipLeft: MenuSlot); a tap opens the grid of buttons
	          next to and under it (setExpanded; the badges add up on MENU
	          while it is shut). The open grid takes the place of the train
	          and boost chips: they hide while it is open (MenuPanels.
	          gridOpen; TrainView.chipVisible, BoostView.chipsVisible), so it
	          never covers them half-way, and come back when it shuts; the
	          grid still draws above the HUD (DisplayOrder OpenOrder).
	          The bottom-left corner belongs to Roblox's movement thumbstick
	          (the DynamicThumbstick takes touches in the left 40 % of the
	          screen, below its top third): the open grid ends above
	          TouchBottom (60 %) of the height, so the 40 % x 40 % corner
	          where the thumb rests stays free (SideMenuView.TouchFits;
	          SideMenu.spec checks phones and tablets). Every button is at
	          least 44 pt.
	  TV      (ten-foot) the column keeps SafeShare (5 %) of the width from the
	          left edge and of the height from the bottom: the title-safe area;
	          the labels and SOON chips get bigger there (TenFootText)
	With a gamepad the D-pad Left glyph shows over the column (D-pad Left
	jumps into the menu). SideMenuView.touchTargets lists the shown buttons
	for the tests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local BoostView = require(script.Parent.BoostView)
local TrainView = require(script.Parent.TrainView)

local SideMenuView = {}

local rgb = Color3.fromRGB

-- the touch layout's MENU button (opens and shuts the grid)
SideMenuView.ToggleId = "Menu"
SideMenuView.ToggleColor = Theme.PanelLight
SideMenuView.ToggleDark = Theme.PanelDark

export type Group = "Main" | "More"

export type Entry = {
	Id: string, -- stable: the button's name, SideMenuController.Actions key
	Label: string,
	Group: Group, -- "Main" stays on screen, "More" goes behind the MORE flyout
	Order: number, -- stable place inside the group (gaps are kept for new entries)
	IconName: string, -- a key of HudBubble.EntryLooks (the light HUD's 3D icon)
	Color: Color3,
	Dark: Color3,
}

-- The groups in the order they show.
SideMenuView.Groups = { "Main", "More" } :: { Group }

SideMenuView.Entries = {
	{ Id = "Golems", Label = "GOLEMS", Group = "Main", Order = 2, IconName = "Golems", Color = rgb(110, 214, 92), Dark = rgb(52, 136, 50) },
	-- the mine elevator: a teleport to the stop of your floor (ElevatorController.open), in
	-- the elevator's neon blue; hidden while the world has no stop (ElevatorController.available)
	{
		Id = "Elevator",
		Label = "ELEVATOR",
		Group = "Main",
		Order = 3,
		IconName = "Elevator",
		Color = rgb(70, 160, 255),
		Dark = rgb(28, 78, 190),
	},
	{ Id = "Shop", Label = "SHOP", Group = "Main", Order = 4, IconName = "Shop", Color = rgb(255, 120, 168), Dark = rgb(178, 58, 108) },
	{ Id = "Codex", Label = "CODEX", Group = "More", Order = 1, IconName = "Codex", Color = rgb(96, 186, 255), Dark = rgb(38, 110, 186) },
	{
		Id = "Collection",
		Label = "ARTIFACTS",
		Group = "More",
		Order = 2,
		IconName = "Artifacts",
		Color = rgb(255, 196, 72),
		Dark = rgb(186, 124, 26),
	},
	{
		Id = "Boards",
		Label = "BOARDS",
		Group = "More",
		Order = 3,
		IconName = "Boards",
		Color = rgb(182, 118, 255),
		Dark = rgb(104, 56, 178),
	},
	{
		Id = "Settings",
		Label = "SETTINGS",
		Group = "More",
		Order = 4,
		IconName = "Settings",
		Color = rgb(150, 140, 132),
		Dark = rgb(88, 80, 74),
	},
	{ Id = "Store", Label = "STORE", Group = "More", Order = 5, IconName = "Store", Color = rgb(72, 200, 150), Dark = rgb(28, 120, 86) },
	-- the hoverboards panel (HoverboardController); "BOARDS" is the leaderboards
	{
		Id = "Hoverboards",
		Label = "HOVER",
		Group = "More",
		Order = 6,
		IconName = "Hoverboards",
		Color = rgb(150, 96, 255),
		Dark = rgb(78, 40, 176),
	},
	-- rebirth STAR FORGE (RebirthController), in the indigo of the rebirth window
	{
		Id = "Rebirth",
		Label = "REBIRTH",
		Group = "More",
		Order = 7,
		IconName = "Rebirth",
		Color = rgb(124, 132, 250),
		Dark = rgb(60, 64, 172),
	},
} :: { Entry }

-- The entries in the order they show: by Group (SideMenuView.Groups), then Order, then Id.
function SideMenuView.sorted(): { Entry }
	local rank: { [string]: number } = {}
	for i, group in SideMenuView.Groups do
		rank[group] = i
	end
	local list = table.clone(SideMenuView.Entries)
	table.sort(list, function(a: Entry, b: Entry): boolean
		local ga, gb = rank[a.Group] or #SideMenuView.Groups + 1, rank[b.Group] or #SideMenuView.Groups + 1
		if ga ~= gb then
			return ga < gb
		end
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Id < b.Id
	end)
	return list
end

SideMenuView.MinTouch = 44 -- points
SideMenuView.Left = 12 -- design units from the left edge
SideMenuView.ChipsGap = 8 -- between the boost chips' touch area and the mouse column
-- mouse: below the train chip and the boost chips' touch area under it
SideMenuView.TopMin = BoostView.chipsTop(nil, false) + BoostView.ChipHit + SideMenuView.ChipsGap
SideMenuView.TopTight = 98 -- nothing of the menu ever goes above this (the coins panel ends at 90)
SideMenuView.BottomMargin = 12
-- the HUD's right-side menu (RIDE, BUILD: 84 wide, 14 from the edge) and a gap:
-- the open touch grid never reaches it
SideMenuView.RightReserve = 14 + 84 + 8
-- the ScreenGui's DisplayOrder: under the HUD (5) while shut, its "+$X"
-- popups and toasts on top; the open touch grid draws over the train and
-- boost chips (6) until it shuts
SideMenuView.Order = 4
SideMenuView.OpenOrder = 7
-- TVs: the labels and SOON chips at least this big (18 px at the 1.25 HUD scale),
-- on buttons this much wider (ARTIFACTS still fits)
SideMenuView.TenFootText = { Label = 15, Soon = 15 }
SideMenuView.TenFootWidth = 96
SideMenuView.LabelText = 14
SideMenuView.SoonText = 10
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
	Touch: boolean?, -- a touch screen (MenuPanels.isTouch)
	TenFoot: boolean?, -- a TV (GuiService:IsTenFootInterface)
	DesignWidth: number?, -- the screen's width in design units (the TV margin)
}

-- A box on the screen in design units (the tests' rects).
export type Rect = { X: number, Y: number, W: number, H: number }

export type Layout = {
	Columns: number,
	Rows: number,
	Width: number, -- one button
	Height: number,
	Gap: number,
	Left: number, -- the column's left edge (design units)
	Top: number, -- the column's top (design units)
	Size: Vector2, -- the whole column (touch: the open grid with MENU)
	Touch: boolean, -- the touch layout (kept clear of the thumbstick)
	Toggle: boolean, -- the MENU button takes the first cell (the touch layout)
	TenFoot: boolean, -- a TV: bigger label and SOON text
}

export type Refs = {
	Gui: ScreenGui,
	Column: Frame,
	Buttons: { [string]: TextButton },
	Badges: { [string]: TextLabel },
	Soon: { [string]: TextLabel },
	Hidden: { [string]: boolean },
	Counts: { [string]: number },
	PadGlyph: ImageLabel,
	Order: { string },
	-- the touch layout's MENU button: three bars shut, an X open
	Toggle: TextButton,
	ToggleBadge: TextLabel,
	ToggleBars: Frame,
	ToggleX: TextLabel,
	ToggleLabel: TextLabel,
	Expanded: boolean,
	Layout: Layout?, -- the last layout applied
	TenFoot: boolean, -- the TV text sizes are on (apply: Layout.TenFoot)
}

-- The tries, in order: { columns, the lowest top }; the first that fits wins.
-- Mouse: one column under the boost chips, then two, three, four (never
-- higher: the train and boost chips own the column above TopMin).
SideMenuView.Fits = { { 1, SideMenuView.TopMin }, { 2, SideMenuView.TopMin }, { 3, SideMenuView.TopMin }, { 4, SideMenuView.TopMin } }
-- Touch (the open grid, MENU in its first cell, in the train chip's row):
-- must end above TouchBottom; narrower before wider; one row of every cell
-- as the last resort (the top comes from touchTop), its buttons narrowed to
-- reach no further than the right-side menu allows (never under 44 pt: the
-- smallest phones with nine buttons).
SideMenuView.TouchFits = { { 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 16 } }

-- The touch layout's top: MENU (`h` tall) centred on the compact train
-- chip's row (TrainView.ChipTop), the badges' Drop above it.
function SideMenuView.touchTop(h: number): number
	local row = TrainView.chipSize(true).Y
	return math.max(SideMenuView.TopTight, math.floor(TrainView.ChipTop + (row - h) / 2) - SideMenuView.Drop)
end

-- The train chip's box on a layout (compact = touch) and the boost chips'
-- row under it at its widest (design units): the column stays clear of both.
function SideMenuView.trainRect(compact: boolean): Rect
	local size = TrainView.chipSize(compact)
	return { X = TrainView.chipLeft(compact), Y = TrainView.ChipTop, W = size.X, H = size.Y }
end

function SideMenuView.chipsRect(compact: boolean): Rect
	return { X = BoostView.ChipLeft, Y = BoostView.chipsTop(nil, compact), W = BoostView.chipsWidth(), H = BoostView.ChipHit }
end

-- Where the buttons go for a uiScale and the screen's height in design
-- units (below the top bar). Touch layouts count the MENU button as a cell.
function SideMenuView.layout(uiScale: number, designHeight: number, options: Options?): Layout
	local o: Options = options or {}
	local compact = uiScale <= SideMenuView.CompactScale
	local touch = o.Touch == true or compact
	local n = math.max(1, o.Count or #SideMenuView.Entries) + (if touch then 1 else 0)
	local tv = o.TenFoot == true
	local m = if compact then SideMenuView.Compact else SideMenuView.Normal
	-- never under 44 pt on a touch screen
	local minSide = SideMenuView.MinTouch / math.max(uiScale, 0.1)
	local w = math.max(m.Width, math.ceil(minSide), if tv then SideMenuView.TenFootWidth else 0)
	local h = math.max(m.Height, if touch then math.ceil(minSide) else 0)
	local bottomMargin = if tv
		then math.max(SideMenuView.BottomMargin, designHeight * SideMenuView.SafeShare)
		else SideMenuView.BottomMargin
	-- the lowest the column may end
	local floor = if touch then designHeight * SideMenuView.TouchBottom else designHeight - bottomMargin
	local left = SideMenuView.Left
	if tv and o.DesignWidth then
		left = math.max(left, math.ceil(o.DesignWidth * SideMenuView.SafeShare))
	end
	-- the rightmost the open touch grid may reach: never the HUD's right-side menu
	local right = if o.DesignWidth then o.DesignWidth - SideMenuView.RightReserve else math.huge
	local columns, rows, height, topMin = 1, n, 0, SideMenuView.TopMin
	local fits: { { number } } = if touch then SideMenuView.TouchFits else SideMenuView.Fits
	for _, try in fits do
		columns, topMin = math.min(try[1], n), try[2] or SideMenuView.touchTop(h)
		rows = math.ceil(n / columns)
		height = rows * h + (rows - 1) * m.Gap
		local wide = left + columns * w + (columns - 1) * m.Gap
		if topMin + SideMenuView.Drop + height <= floor and (not touch or wide <= right) then
			break
		end
	end
	-- touch, one row as the last resort: narrower buttons when it reaches the right-side menu
	if touch and left + columns * w + (columns - 1) * m.Gap > right then
		w = math.max(math.ceil(minSide), math.floor((right - left - (columns - 1) * m.Gap) / columns))
	end
	-- mouse: centred in the room under the boost chips; touch: in the train chip's row
	local top = if touch then topMin else math.max(topMin, math.floor((designHeight - height) / 2))
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
		Toggle = touch,
		TenFoot = tv,
	}
end

local function newButton(column: Frame, entry: Entry, order: number): (TextButton, TextLabel, TextLabel)
	local button = UIKit.button(column, "", entry.Color, entry.Dark, {
		Name = entry.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SideMenuView.Normal.Width, SideMenuView.Normal.Height),
	})
	button:SetAttribute("Menu", entry.Id)
	button:SetAttribute("MenuGroup", entry.Group)
	-- the name in the middle (no icon: words only)
	UIKit.label(button, entry.Label, SideMenuView.LabelText, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
	-- inside the button's top-right corner (it belongs to this button, not
	-- the gap between two)
	local soon = UIKit.chip(button, "SOON", Theme.PanelDark, {
		Name = "Soon",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(38, 15),
		TextSize = SideMenuView.SoonText,
		TextColor3 = Theme.TextDim,
		ZIndex = 4,
		Visible = false,
	})
	return button, badge, soon
end

-- The touch layout's MENU button: three gold bars over "MENU" while the
-- grid is shut, an X over "CLOSE" while it is open; its badge adds up the
-- buttons' counts while shut.
local function newToggle(column: Frame): (TextButton, TextLabel, Frame, TextLabel, TextLabel)
	local button = UIKit.button(column, "", SideMenuView.ToggleColor, SideMenuView.ToggleDark, {
		Name = SideMenuView.ToggleId,
		LayoutOrder = 0,
		Size = UDim2.fromOffset(SideMenuView.Normal.Width, SideMenuView.Normal.Height),
	})
	button:SetAttribute("Menu", SideMenuView.ToggleId)
	local bars = UIKit.new("Frame", {
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(32, 26),
		BackgroundTransparency = 1,
	}, button)
	for i = 0, 2 do
		local bar = UIKit.new("Frame", {
			Name = "Bar" .. (i + 1),
			Position = UDim2.fromOffset(0, i * 10),
			Size = UDim2.fromOffset(32, 6),
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
		}, bars)
		UIKit.corner(bar, 3)
	end
	local x = UIKit.label(button, "X", 30, {
		Name = "X",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		Visible = false,
	})
	local label = UIKit.label(button, "MENU", SideMenuView.LabelText, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -4, 0, 18),
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local badge = UIKit.chip(button.Parent :: Frame, "1", Theme.Bad, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.fromOffset(26, 26),
		TextSize = 16,
		ZIndex = 4,
		Visible = false,
	})
	UIKit.corner(badge, 13)
	return button, badge, bars, x, label
end

function SideMenuView.build(): Refs
	-- under the HUD (5 would be above): its "+$X" popups and toasts show on
	-- top where they meet the touch layout's wide grid
	local gui = UIKit.screen("TerraForgeSideMenu", SideMenuView.Order)
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
	local toggle, toggleBadge, bars, x, toggleLabel = newToggle(column)
	local refs: Refs = {
		Gui = gui,
		Column = column,
		Buttons = {},
		Badges = {},
		Soon = {},
		Hidden = {},
		Counts = {},
		PadGlyph = glyph,
		Order = {},
		Toggle = toggle,
		ToggleBadge = toggleBadge,
		ToggleBars = bars,
		ToggleX = x,
		ToggleLabel = toggleLabel,
		Expanded = false,
		Layout = nil,
		TenFoot = false,
	}
	for i, entry in SideMenuView.sorted() do
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
	local layout = refs.Layout
	local holder = button.Parent :: Frame
	holder.Visible = not hidden and (layout == nil or not layout.Toggle or refs.Expanded)
end

local function badgeText(count: number): string
	return if count >= 10 then "9+" else tostring(math.max(0, math.floor(count)))
end

-- MENU's badge: the shown buttons' counts added up, while the grid is shut.
local function updateToggleBadge(refs: Refs)
	local total = 0
	for _, id in SideMenuView.shown(refs) do
		total += refs.Counts[id] or 0
	end
	local layout = refs.Layout
	local shut = layout ~= nil and layout.Toggle and not refs.Expanded
	refs.ToggleBadge.Visible = shut and total > 0
	refs.ToggleBadge.Text = badgeText(total)
end

-- Places the shown buttons for a layout (row by row: left to right, then
-- the next row). Touch layouts: MENU in the first cell, the buttons after
-- it only while the grid is open (refs.Expanded).
-- The label / SOON text sizes: bigger on TVs (TenFootText: at least 18 px
-- at the HUD's 1.25 scale, the all-platforms TV minimum).
local function applyText(refs: Refs, tenFoot: boolean)
	refs.TenFoot = tenFoot
	local label = if tenFoot then SideMenuView.TenFootText.Label else SideMenuView.LabelText
	local soonSize = if tenFoot then SideMenuView.TenFootText.Soon else SideMenuView.SoonText
	refs.ToggleLabel.TextSize = label
	for id, button in refs.Buttons do
		local text = button:FindFirstChild("Label")
		if text and text:IsA("TextLabel") then
			text.TextSize = label
			text.Size = UDim2.new(1, -4, 0, label + 4)
		end
		local soon = refs.Soon[id]
		if soon then
			soon.TextSize = soonSize
			soon.Size = UDim2.fromOffset(if tenFoot then 46 else 38, soonSize + 5)
		end
	end
end

function SideMenuView.apply(refs: Refs, layout: Layout)
	refs.Layout = layout
	if refs.TenFoot ~= layout.TenFoot then
		applyText(refs, layout.TenFoot)
	end
	local toggleHolder = refs.Toggle.Parent :: Frame
	toggleHolder.Visible = layout.Toggle
	local open = not layout.Toggle or refs.Expanded
	-- the open touch grid draws over the train and boost chips
	refs.Gui.DisplayOrder = if layout.Toggle and refs.Expanded then SideMenuView.OpenOrder else SideMenuView.Order
	local function place(holder: Frame, cell: number)
		local col = cell % layout.Columns
		local row = cell // layout.Columns
		holder.Position = UDim2.fromOffset(col * (layout.Width + layout.Gap), row * (layout.Height + layout.Gap) + SideMenuView.Drop)
		holder.Size = UDim2.fromOffset(layout.Width, layout.Height)
	end
	local first = if layout.Toggle then 1 else 0
	if layout.Toggle then
		place(toggleHolder, 0)
	end
	for i, id in SideMenuView.shown(refs) do
		local holder = refs.Buttons[id].Parent :: Frame
		place(holder, first + i - 1)
		holder.Visible = open
	end
	-- the column's box: the open grid, or MENU alone
	local size = if open then layout.Size else Vector2.new(layout.Width, layout.Height)
	refs.Column.Position = UDim2.fromOffset(layout.Left, layout.Top)
	refs.Column.Size = UDim2.fromOffset(size.X, size.Y + SideMenuView.Drop)
	refs.PadGlyph.Position = UDim2.new(0, layout.Width / 2, 0, -2)
	-- MENU's face: bars + "MENU" shut, X + "CLOSE" open
	refs.ToggleBars.Visible = not refs.Expanded
	refs.ToggleX.Visible = refs.Expanded
	refs.ToggleLabel.Text = if refs.Expanded then "CLOSE" else "MENU"
	updateToggleBadge(refs)
end

-- Opens or shuts the touch layout's grid (the last layout again).
function SideMenuView.setExpanded(refs: Refs, on: boolean)
	refs.Expanded = on
	local layout = refs.Layout
	if layout then
		SideMenuView.apply(refs, layout)
	end
end

-- A count on a button's badge (0 hides it; 10 and more show "9+"); MENU
-- shows them added up while the grid is shut.
function SideMenuView.setBadge(refs: Refs, id: string, count: number)
	local badge = refs.Badges[id]
	if not badge then
		return
	end
	refs.Counts[id] = math.max(0, math.floor(count))
	badge.Visible = count > 0
	badge.Text = badgeText(count)
	local soon = refs.Soon[id]
	if soon and badge.Visible then
		soon.Visible = false
	end
	updateToggleBadge(refs)
end

-- The "SOON" chip on a button whose feature isn't in the game yet.
function SideMenuView.setSoon(refs: Refs, id: string, on: boolean)
	local soon = refs.Soon[id]
	if soon then
		soon.Visible = on and not refs.Badges[id].Visible
	end
end

-- Every tappable button that shows (for the touch-size tests): MENU on
-- touch layouts, the buttons unless the grid is shut.
function SideMenuView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = {}
	local layout = refs.Layout
	local toggle = layout ~= nil and layout.Toggle
	if toggle then
		table.insert(list, refs.Toggle.Parent :: Frame)
	end
	if not toggle or refs.Expanded then
		for _, id in SideMenuView.shown(refs) do
			table.insert(list, refs.Buttons[id].Parent :: Frame)
		end
	end
	return list
end

-- The cell of a button in the last layout (0 = the first; MENU is 0 on
-- touch layouts), or nil when it isn't shown.
function SideMenuView.cellOf(refs: Refs, button: Instance): number?
	local layout = refs.Layout
	if not layout then
		return nil
	end
	if layout.Toggle and (button == refs.Toggle or button == refs.Toggle.Parent) then
		return 0
	end
	local first = if layout.Toggle then 1 else 0
	for i, id in SideMenuView.shown(refs) do
		local own = refs.Buttons[id]
		if button == own or button == own.Parent then
			return first + i - 1
		end
	end
	return nil
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- With the light UI on (ships off) the entries live in the light HUD's tiles
-- and MORE flyout (SideMenuController mirrors them); this column stays hidden.
local darkBuild = SideMenuView.build
SideMenuView.build = function(): Refs
	local refs = darkBuild()
	if UIConfig.lightUI() then
		refs.Gui.Enabled = false
		refs.Gui:SetAttribute("HiddenByLight", true)
	end
	return refs
end

return SideMenuView
