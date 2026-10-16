--[[
	Storage Crate panel (pure builder; StorageController fills it in).
	  header   STORAGE title, fill count '12 / 60' with a coloured bar, X button
	  grid     one card per kind of item: colour swatch, count, name, value,
	           TAKE (1, into your hands) and TAKE 5 buttons
	  footer   control hint
	6 columns on PC, 3 on phones. Buttons are at least 56 px tall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)

local StorageView = {}

export type Entry = { Key: string, Name: string, Count: number, Value: number, Color: Color3 }

export type Cell = {
	Key: string,
	Frame: Frame,
	Swatch: Frame,
	Count: TextLabel,
	Name: TextLabel,
	Value: TextLabel,
	Take: TextButton,
	TakeFive: TextButton,
	TakeFiveHolder: Frame, -- the TAKE 5 button with its lip (hidden for a single item)
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Header: TextLabel,
	Bar: Frame,
	BarFill: Frame,
	Close: TextButton,
	Grid: ScrollingFrame,
	Layout: UIGridLayout,
	Empty: TextLabel,
	Hint: TextLabel,
	Cells: { [string]: Cell },
	Columns: number,
}

StorageView.MaxEntries = 120
StorageView.CellWidth = 150
StorageView.CellHeight = 188
StorageView.ButtonHeight = 56
StorageView.Gap = 10

local PAD = 16
local HEADER = 76
local FOOTER = 34
local SCROLLBAR = 12
local VISIBLE_ROWS = 2

-- Panel width for a number of columns (design units).
function StorageView.panelWidth(columns: number): number
	return columns * StorageView.CellWidth + (columns - 1) * StorageView.Gap + PAD * 2 + SCROLLBAR
end

local function fillColor(fraction: number): Color3
	if fraction >= 1 then
		return Theme.Bad
	elseif fraction >= 0.8 then
		return Theme.Accent
	end
	return Theme.Good
end

function StorageView.build(columns: number?): Refs
	local gui = UIKit.screen("TerraForgeStorage", 15)
	gui.Enabled = false

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(StorageView.panelWidth(6), 0),
	})

	local title = UIKit.label(panel, "STORAGE", 30, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.new(0.5, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	local header = UIKit.label(panel, "0 / 0", 22, {
		Name = "Header",
		Position = UDim2.fromOffset(PAD, 42),
		Size = UDim2.fromOffset(150, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(PAD + 150, 48),
		Size = UDim2.new(1, -(PAD * 2 + 150 + 72), 0, 14),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(bar, 7)
	UIKit.stroke(bar, 2)
	local barFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Good,
		BorderSizePixel = 0,
	}, bar)
	UIKit.corner(barFill, 7)

	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 14),
		Size = UDim2.fromOffset(StorageView.ButtonHeight, StorageView.ButtonHeight),
		TextSize = 26,
	})

	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(1, -PAD, 1, -(HEADER + FOOTER)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, panel)
	local layout = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(StorageView.CellWidth, StorageView.CellHeight),
		CellPadding = UDim2.fromOffset(StorageView.Gap, StorageView.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 6,
	}, grid)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, grid)

	local empty = UIKit.label(panel, "Your crates are empty. Drop or throw items into a crate to store them.", 20, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, (HEADER - FOOTER) / 2),
		Size = UDim2.new(1, -PAD * 4, 0, 60),
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	local hint = UIKit.label(panel, "TAKE puts items in your hands", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -8),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		TextColor3 = Theme.TextDim,
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Header = header,
		Bar = bar,
		BarFill = barFill,
		Close = close,
		Grid = grid,
		Layout = layout,
		Empty = empty,
		Hint = hint,
		Cells = {},
		Columns = 6,
	}
	StorageView.setColumns(refs, columns or 6)
	return refs
end

-- 6 columns on PC, 3 on phones (the panel resizes to fit).
function StorageView.setColumns(refs: Refs, columns: number)
	local count = math.clamp(math.floor(columns), 1, 6)
	refs.Columns = count
	refs.Layout.FillDirectionMaxCells = count
	local height = HEADER + VISIBLE_ROWS * StorageView.CellHeight + (VISIBLE_ROWS - 1) * StorageView.Gap + 12 + FOOTER
	refs.Panel.Size = UDim2.fromOffset(StorageView.panelWidth(count), height)
end

local function newCell(refs: Refs, key: string): Cell
	local frame = UIKit.new("Frame", {
		Name = "Item",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, refs.Grid)
	frame:SetAttribute("Key", key)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)

	local swatch = UIKit.new("Frame", {
		Name = "Swatch",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(swatch, 10)
	UIKit.stroke(swatch, 2.5)
	UIKit.gradient(swatch, Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160))

	local count = UIKit.label(frame, "x0", 26, {
		Name = "Count",
		Position = UDim2.fromOffset(56, 10),
		Size = UDim2.new(1, -66, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local name = UIKit.label(frame, "", 16, {
		Name = "ItemName",
		Position = UDim2.fromOffset(8, 54),
		Size = UDim2.new(1, -16, 0, 40),
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local value = UIKit.label(frame, "", 15, {
		Name = "Value",
		Position = UDim2.fromOffset(8, 94),
		Size = UDim2.new(1, -16, 0, 20),
		TextColor3 = Theme.Coin,
	})

	-- UIKit buttons sit 5 px above their lip, so the lip ends 8 px from the bottom
	local buttonWidth = (StorageView.CellWidth - 8 * 3) / 2
	local top = StorageView.CellHeight - StorageView.ButtonHeight - 8
	local take = UIKit.button(frame, "TAKE", Theme.Good, Theme.GoodDark, {
		Name = "Take",
		Position = UDim2.fromOffset(8, top),
		Size = UDim2.fromOffset(buttonWidth, StorageView.ButtonHeight),
		TextSize = 18,
	})
	local takeFive = UIKit.button(frame, "TAKE 5", Theme.Accent, Theme.AccentDark, {
		Name = "TakeFive",
		Position = UDim2.fromOffset(16 + buttonWidth, top),
		Size = UDim2.fromOffset(buttonWidth, StorageView.ButtonHeight),
		TextSize = 18,
	})

	local cell: Cell = {
		Key = key,
		Frame = frame,
		Swatch = swatch,
		Count = count,
		Name = name,
		Value = value,
		Take = take,
		TakeFive = takeFive,
		TakeFiveHolder = takeFive.Parent :: Frame,
	}
	refs.Cells[key] = cell
	return cell
end

--[[
	Shows these entries in this order (at most MaxEntries). Cards are reused
	by key; cards for keys that are gone are removed. Returns the cards that
	were just created, so the controller can hook up their buttons.
]]
function StorageView.setEntries(refs: Refs, list: { Entry }): { Cell }
	local created: { Cell } = {}
	local keep: { [string]: boolean } = {}
	for index, entry in list do
		if index > StorageView.MaxEntries then
			break
		end
		keep[entry.Key] = true
		local cell = refs.Cells[entry.Key]
		if not cell then
			cell = newCell(refs, entry.Key)
			table.insert(created, cell)
		end
		cell.Frame.LayoutOrder = index
		cell.Swatch.BackgroundColor3 = entry.Color
		cell.Count.Text = "x" .. Format.commas(entry.Count)
		cell.Name.Text = entry.Name
		cell.Name.TextColor3 = entry.Color
		cell.Value.Text = `{Format.commas(entry.Value)} coins each`
		cell.TakeFive.Text = if entry.Count >= 5 then "TAKE 5" else `TAKE {entry.Count}`
		cell.TakeFiveHolder.Visible = entry.Count > 1
	end
	for key, cell in refs.Cells do
		if not keep[key] then
			cell.Frame:Destroy()
			refs.Cells[key] = nil
		end
	end
	refs.Empty.Visible = next(keep) == nil
	return created
end

-- '12 / 60' and the fill bar (green, amber from 80%, red when full).
function StorageView.setHeader(refs: Refs, count: number, capacity: number)
	refs.Header.Text = `{Format.commas(count)} / {Format.commas(capacity)}`
	local fraction = if capacity > 0 then count / capacity else 1
	refs.BarFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	local color = fillColor(fraction)
	refs.BarFill.BackgroundColor3 = color
	refs.Header.TextColor3 = if fraction >= 0.8 then color else Theme.Text
end

return StorageView
