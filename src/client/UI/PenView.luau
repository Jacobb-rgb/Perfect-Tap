--[[
	Ore Pen panel (pure builder; PenController fills it in and wires it up).
	  header   ORE PEN title, fill "37 / 40" with a coloured bar, X button
	  list     one row per kind of item (storage key): an icon square in the
	           ore's colour (Dirty Ore: dull grey with "?"), the name, a grade
	           chip, "+$X/s" for cleaned ore, the count, TAKE and PODIUM
	  footer   control hint
	Pick mode (from a podium's "Place Ore" prompt) lists only cleaned ore
	with one PLACE button per row.
	Compact layout for phones (uiScale <= 0.75): taller rows and buttons, so
	touch targets stay >= 44 pt at the smallest UI scale.
	PenView.entries() turns the State snapshot into sorted rows (pure, tested).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Rng = require(Shared.Util.Rng)
local UIKit = require(script.Parent.UIKit)

local PenView = {}

export type Mode = "Pen" | "Pick"

export type Entry = {
	Key: string,
	Kind: string,
	Name: string,
	Grade: string?, -- grade id for the chip (cleaned ore and later stages)
	Count: number,
	Income: number, -- coins per second on a podium (0 = can't go on one)
	Value: number, -- for sorting things that can't go on a podium
	Color: Color3, -- icon colour
	Mystery: boolean, -- dirty ore: "?" icon
}

export type Row = {
	Key: string,
	Frame: Frame,
	Icon: Frame,
	Mystery: TextLabel,
	Name: TextLabel,
	Grade: TextLabel,
	Income: TextLabel,
	Count: TextLabel,
	Take: TextButton,
	Podium: TextButton,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Header: TextLabel,
	Bar: Frame,
	BarFill: Frame,
	Close: TextButton,
	List: ScrollingFrame,
	Empty: TextLabel,
	Hint: TextLabel,
	PadHint: Frame, -- gamepad hint: [A] choose  [B] close, with the platform's glyphs
	PadA: ImageLabel,
	PadAText: TextLabel,
	PadB: ImageLabel,
	Rows: { [string]: Row },
	Compact: boolean,
	Mode: Mode,
	Slot: number?,
}

PenView.MaxRows = 80
PenView.DirtyColor = Color3.fromRGB(120, 114, 108)

local PAD = 16
local HEADER = 84
local FOOTER = 34
local GAP = 8
local SCROLLBAR = 12

-- Sizes per layout (design units; the HUD's UIScale shrinks them on phones).
local LAYOUTS = {
	Normal = { Width = 660, RowH = 64, ButtonH = 50, TakeW = 92, PodiumW = 112, Rows = 5, Name = 20, Close = 52 },
	Compact = { Width = 760, RowH = 86, ButtonH = 72, TakeW = 116, PodiumW = 132, Rows = 4, Name = 22, Close = 72 },
}

local function layoutOf(refs: Refs): typeof(LAYOUTS.Normal)
	return if refs.Compact then LAYOUTS.Compact else LAYOUTS.Normal
end

---------------------------------------------------------------- entries (pure)

local KIND_ORDER = { Clean = 1, Ingot = 2, Gear = 3, Crushed = 4, Raw = 5 }

--[[
	Rows for a State Storage summary ("K|O|G|R" -> count): unknown keys
	are skipped, cleaned ore first by income (best first), then the other
	kinds by value, dirty ore last. Pick mode keeps only podium ore.
]]
function PenView.entries(summary: any, mode: Mode?): { Entry }
	local list: { Entry } = {}
	if type(summary) ~= "table" then
		return list
	end
	for key, count in summary do
		local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
		if desc and type(count) == "number" and count >= 1 and count == count then
			local podiumOre = EconomyConfig.Podiums.Kinds[desc.K] == true
			if mode ~= "Pick" or podiumOre then
				local dirty = desc.K == "Raw"
				local ore = OreData.ById[desc.O]
				table.insert(list, {
					Key = key,
					Kind = desc.K,
					Name = ItemData.displayName(desc.K, desc.O, desc.G, desc.R),
					Grade = if dirty then nil else desc.G,
					Count = math.floor(count),
					Income = if podiumOre then ItemData.income(desc) else 0,
					Value = if dirty then 0 else ItemData.value(desc.K, desc.O, desc.G, desc.R),
					Color = if dirty or not ore then PenView.DirtyColor else ore.Color,
					Mystery = dirty,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		local ka, kb = KIND_ORDER[a.Kind] or 9, KIND_ORDER[b.Kind] or 9
		if ka ~= kb then
			return ka < kb
		elseif a.Income ~= b.Income then
			return a.Income > b.Income
		elseif a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.Key < b.Key
	end)
	return list
end

-- The first podium slot that is unlocked and empty (nil when none).
function PenView.freeSlot(podiums: any, slots: any): number?
	if type(podiums) ~= "table" then
		return nil
	end
	local unlocked = if type(slots) == "number"
		then math.clamp(math.floor(slots), 0, EconomyConfig.Podiums.Max)
		else EconomyConfig.Podiums.Free
	for slot = 1, unlocked do
		if podiums[slot] == "" or podiums[slot] == nil then
			return slot
		end
	end
	return nil
end

-- How many display copies of each key the pen pile shows (at most `max`):
-- round-robin over the sorted rows, so a full pen still shows variety.
function PenView.pileCounts(summary: any, max: number): { [string]: number }
	local entries = PenView.entries(summary, "Pen")
	local counts: { [string]: number } = {}
	local total = 0
	local round = 1
	while total < max do
		local added = false
		for _, entry in entries do
			if total >= max then
				break
			end
			if entry.Count >= round then
				counts[entry.Key] = (counts[entry.Key] or 0) + 1
				total += 1
				added = true
			end
		end
		if not added then
			break
		end
		round += 1
	end
	return counts
end

-- Where the pile's display copies lie: BaseLayout.Pen.ShowMax spots spread
-- over the pen floor with a little jitter (world CFrames, bottom centers).
function PenView.pileSpots(plotCF: CFrame, plotId: number): { CFrame }
	local area = BaseLayout.Pen.Area
	local max = BaseLayout.Pen.ShowMax
	local cols = math.max(1, math.ceil(math.sqrt(max * area.Size.X / area.Size.Z)))
	local rows = math.max(1, math.ceil(max / cols))
	local w, d = area.Size.X - 4, area.Size.Z - 4
	local rng = Rng.new(`PenPile/{plotId}`)
	local list = {}
	for i = 0, max - 1 do
		local cx, cz = i % cols, math.floor(i / cols)
		local x = area.Center.X - w / 2 + (cx + 0.5) * w / cols + rng:range(-0.6, 0.6)
		local z = area.Center.Z - d / 2 + (cz + 0.5) * d / rows + rng:range(-0.6, 0.6)
		table.insert(list, plotCF * CFrame.new(x, 0.2, z) * CFrame.Angles(0, rng:range(0, 6.28), 0))
	end
	return list
end

---------------------------------------------------------------- building

local function fillColor(fraction: number): Color3
	if fraction >= 1 then
		return Theme.Bad
	elseif fraction >= 0.8 then
		return Theme.Accent
	end
	return Theme.Good
end

function PenView.build(): Refs
	local gui = UIKit.screen("TerraForgePen", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(LAYOUTS.Normal.Width, 400),
	})
	local title = UIKit.label(panel, "ORE PEN", 30, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.new(1, -(PAD * 2 + 90), 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		TextScaled = false,
	})
	local header = UIKit.label(panel, "0 / 0", 20, {
		Name = "Header",
		Position = UDim2.fromOffset(PAD, 46),
		Size = UDim2.fromOffset(110, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(PAD + 110, 52),
		Size = UDim2.new(1, -(PAD * 2 + 110 + 90), 0, 14),
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
		Size = UDim2.fromOffset(LAYOUTS.Normal.Close, LAYOUTS.Normal.Close),
		TextSize = 26,
	})

	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
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
	UIKit.list(list, Enum.FillDirection.Vertical, GAP)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, list)

	local empty = UIKit.label(panel, "", 20, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, (HEADER - FOOTER) / 2),
		Size = UDim2.new(1, -PAD * 4, 0, 70),
		TextColor3 = Theme.TextDim,
		Visible = false,
	})
	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -8),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		TextColor3 = Theme.TextDim,
	})
	-- gamepads: the platform's own button glyphs (Xbox or PlayStation), set by the controller
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	UIKit.list(padHint, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local function glyph(order: number): ImageLabel
		return UIKit.new("ImageLabel", {
			Name = "Glyph" .. order,
			LayoutOrder = order,
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
		}, padHint)
	end
	local function word(order: number, text: string): TextLabel
		return UIKit.label(padHint, text, 16, {
			Name = "Word" .. order,
			LayoutOrder = order,
			Size = UDim2.fromOffset(84, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
		})
	end
	local padA = glyph(1)
	local padAText = word(2, "choose")
	local padB = glyph(3)
	word(4, "close")

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Header = header,
		Bar = bar,
		BarFill = barFill,
		Close = close,
		List = list,
		Empty = empty,
		Hint = hint,
		PadHint = padHint,
		PadA = padA,
		PadAText = padAText,
		PadB = padB,
		Rows = {},
		Compact = false,
		Mode = "Pen",
		Slot = nil,
	}
	PenView.setCompact(refs, false)
	PenView.setMode(refs, "Pen", nil)
	return refs
end

-- Places the row's parts for the current layout.
local function layoutRow(refs: Refs, row: Row)
	local l = layoutOf(refs)
	local rowW = l.Width - PAD - SCROLLBAR - PAD
	row.Frame.Size = UDim2.fromOffset(rowW, l.RowH)
	local icon = l.RowH - 16
	row.Icon.Size = UDim2.fromOffset(icon, icon)
	row.Icon.Position = UDim2.fromOffset(8, 8)
	row.Mystery.TextSize = math.floor(icon * 0.6)
	local textX = icon + 18
	local buttons = l.TakeW + l.PodiumW + 24
	local countW = 64
	local textW = rowW - textX - buttons - countW
	row.Name.Position = UDim2.fromOffset(textX, 6)
	row.Name.Size = UDim2.fromOffset(textW, math.floor(l.RowH * 0.45))
	row.Name.TextSize = l.Name
	local lineY = math.floor(l.RowH * 0.5) + 2
	row.Grade.Position = UDim2.fromOffset(textX, lineY)
	row.Income.Position = UDim2.fromOffset(textX + 96, lineY - 2)
	row.Income.Size = UDim2.fromOffset(math.max(40, textW - 96), 26)
	row.Count.Position = UDim2.fromOffset(rowW - buttons - countW, 0)
	row.Count.Size = UDim2.fromOffset(countW - 6, l.RowH)
	local buttonY = math.floor((l.RowH - l.ButtonH) / 2) + 3
	local take = row.Take.Parent :: Frame
	take.Position = UDim2.fromOffset(rowW - l.PodiumW - l.TakeW - 16, buttonY)
	take.Size = UDim2.fromOffset(l.TakeW, l.ButtonH)
	local podium = row.Podium.Parent :: Frame
	podium.Position = UDim2.fromOffset(rowW - l.PodiumW - 8, buttonY)
	podium.Size = UDim2.fromOffset(l.PodiumW, l.ButtonH)
end

local function newRow(refs: Refs, key: string): Row
	local frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, refs.List)
	frame:SetAttribute("Key", key)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(icon, 10)
	UIKit.stroke(icon, 2.5)
	UIKit.gradient(icon, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	local mystery = UIKit.label(icon, "?", 28, {
		Name = "Mystery",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		Visible = false,
	})
	local name = UIKit.label(frame, "", 20, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local grade = UIKit.chip(frame, "", Theme.PanelDark, { Name = "Grade", Size = UDim2.fromOffset(88, 22) })
	local income = UIKit.label(frame, "", 17, {
		Name = "Income",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Good,
		TextWrapped = false,
	})
	local count = UIKit.label(frame, "x0", 24, {
		Name = "Count",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local take = UIKit.button(frame, "TAKE", Theme.Good, Theme.GoodDark, { Name = "Take", TextSize = 20 })
	local podium = UIKit.button(frame, "PODIUM", Theme.Accent, Theme.AccentDark, { Name = "Podium", TextSize = 20 })
	local row: Row = {
		Key = key,
		Frame = frame,
		Icon = icon,
		Mystery = mystery,
		Name = name,
		Grade = grade,
		Income = income,
		Count = count,
		Take = take,
		Podium = podium,
	}
	refs.Rows[key] = row
	layoutRow(refs, row)
	return row
end

--[[
	Shows these entries in this order (at most MaxRows). Rows are reused by
	key; rows for keys that are gone are removed. `canPodium` = a podium
	slot is free and unlocked (normal mode). Returns the rows just created,
	so the controller can hook up their buttons.
]]
function PenView.setEntries(refs: Refs, list: { Entry }, canPodium: boolean): { Row }
	local created: { Row } = {}
	local keep: { [string]: boolean } = {}
	local pick = refs.Mode == "Pick"
	for index, entry in list do
		if index > PenView.MaxRows then
			break
		end
		keep[entry.Key] = true
		local existing: Row? = refs.Rows[entry.Key]
		local row: Row
		if existing then
			row = existing
		else
			row = newRow(refs, entry.Key)
			table.insert(created, row)
		end
		row.Frame.LayoutOrder = index
		row.Icon.BackgroundColor3 = entry.Color
		row.Mystery.Visible = entry.Mystery
		row.Name.Text = entry.Name
		local grade = entry.Grade and ItemData.GradeById[entry.Grade]
		row.Grade.Visible = grade ~= nil
		if grade then
			row.Grade.Text = grade.Name
			row.Grade.BackgroundColor3 = grade.Color
		end
		row.Income.Position = UDim2.fromOffset(row.Grade.Position.X.Offset + (if grade then 96 else 0), row.Income.Position.Y.Offset)
		row.Income.Text = if entry.Income > 0
			then Format.perSecond(entry.Income)
			elseif entry.Mystery then "Clean it to see what it is"
			else ""
		row.Income.TextColor3 = if entry.Income > 0 then Theme.Good else Theme.TextDim
		row.Count.Text = "x" .. Format.big(entry.Count)
		local takeHolder = row.Take.Parent :: Frame
		local podiumHolder = row.Podium.Parent :: Frame
		takeHolder.Visible = not pick
		local podiumOre = entry.Income > 0
		podiumHolder.Visible = podiumOre and (pick or canPodium)
		row.Podium.Text = if pick then "PLACE" else "PODIUM"
	end
	local rows = refs.Rows :: { [string]: any }
	for key, row in refs.Rows do
		if not keep[key] then
			row.Frame:Destroy()
			rows[key] = nil
		end
	end
	refs.Empty.Visible = next(keep) == nil
	return created
end

-- "37 / 40" and the fill bar (green, amber from 80%, red when full).
function PenView.setHeader(refs: Refs, count: number, capacity: number)
	refs.Header.Text = `{Format.commas(count)} / {Format.commas(capacity)}`
	local fraction = if capacity > 0 then count / capacity else 1
	refs.BarFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	local color = fillColor(fraction)
	refs.BarFill.BackgroundColor3 = color
	refs.Header.TextColor3 = if fraction >= 0.8 then color else Theme.Text
end

-- The footer: a text hint, or (gamepad) button glyphs with "choose" / "close".
function PenView.setHint(refs: Refs, text: string, glyphA: string?, glyphB: string?)
	local pad = glyphA ~= nil and glyphB ~= nil
	refs.Hint.Text = text
	refs.Hint.Visible = not pad
	refs.PadHint.Visible = pad
	if pad then
		refs.PadA.Image = glyphA :: string
		refs.PadB.Image = glyphB :: string
		refs.PadAText.Text = if refs.Mode == "Pick" then "place" else "choose"
	end
end

-- Normal pen view, or pick mode for one podium slot.
function PenView.setMode(refs: Refs, mode: Mode, slot: number?)
	refs.Mode = mode
	refs.Slot = if mode == "Pick" then slot else nil
	if mode == "Pick" then
		refs.Title.Text = `PODIUM {slot or "?"}: PICK AN ORE`
		refs.Empty.Text = "No cleaned ore in your pen yet. Clean dirty ore at the Cleaning Station, then come back."
	else
		refs.Title.Text = "ORE PEN"
		refs.Empty.Text = "Your Ore Pen is empty. Throw or drop ore into the pen to keep it here."
	end
end

-- Phone layout (taller rows and buttons) or the normal one.
function PenView.setCompact(refs: Refs, compact: boolean)
	refs.Compact = compact
	local l = layoutOf(refs)
	local height = HEADER + l.Rows * l.RowH + (l.Rows - 1) * GAP + 12 + FOOTER
	refs.Panel.Size = UDim2.fromOffset(l.Width, height)
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	refs.Title.TextSize = if compact then 34 else 30
	for _, row in refs.Rows do
		layoutRow(refs, row)
	end
end

return PenView
