--[[
	Ore Pen panel (pure builder; PenController fills it in and wires it up).
	  header   ORE PEN title, fill "37 / 40" with a coloured bar, the
	           AUTO-SORT ON / OFF switch (with the sorting billboard,
	           Upgrades.PenAutomation >= 1) and the X button
	  toolbar  (step 3, WP-Belts) SEND ALL DIRTY, SEND UNKEPT (with the
	           sorting billboard), STOP (while the pen sends something) and
	           a status line ("Sending 3…", or why a chute waits)
	  list     one row per kind of item (storage key): an icon square in the
	           ore's colour (Dirty Ore: dull grey with "?"), the name, a grade
	           chip, "+$X/s" for cleaned ore, the count, TAKE, SEND (one item
	           onto your belts at the PEN chute; for a few seconds after, it
	           reads "ALL xN?" and a second press sends the rest of the
	           stack: setSendArmed) and PODIUM
	  footer   control hint
	Pick mode (from a podium's "Place Ore" prompt) lists only cleaned ore
	with one PLACE button per row (no toolbar, no TAKE / SEND).
	Compact layout for phones (uiScale <= 0.75): taller rows and buttons, so
	touch targets stay >= 44 pt at the smallest UI scale (Normal's 50-unit
	buttons stay >= 44 pt down to a 0.88 scale). Given the screen's size in
	design units (setCompact's `room`), the panel keeps clear of the HUD: it
	shows as many rows as fit between the coins (top left) and the HANDS
	box (bottom centre), and on phones it sits at the top, right of the
	coins.
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
	Keys: { [string]: number }?, -- the merged Dirty Ore row: real key -> count
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
	Send: TextButton,
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
	AutoSort: TextButton, -- the sorting billboard's switch (header)
	Toolbar: Frame,
	SendDirty: TextButton,
	SendUnkept: TextButton,
	StopSend: TextButton,
	Status: TextLabel,
	List: ScrollingFrame,
	Empty: TextLabel,
	Hint: TextLabel,
	PadHint: Frame, -- gamepad hint: [A] choose  [B] close, with the platform's glyphs
	PadA: ImageLabel,
	PadAText: TextLabel,
	PadB: ImageLabel,
	Rows: { [string]: Row },
	Compact: boolean,
	Room: Vector2?, -- the screen in design units (gui size / UI scale), when known
	Mode: Mode,
	Slot: number?,
}

PenView.MaxRows = 80
PenView.DirtyColor = Color3.fromRGB(120, 114, 108)
PenView.SendColor = Theme.Info
PenView.SendDark = Color3.fromRGB(46, 104, 164)
PenView.OffColor = Color3.fromRGB(128, 118, 110)
PenView.OffDark = Color3.fromRGB(74, 66, 60)
PenView.MinRows = 2
-- The HUD the panel keeps clear of (HudView, design units): the coins box
-- top left (16 + 74 tall, 16 + CoinsWidth 236 wide) and the HANDS box at
-- the bottom centre (74 tall, 16 above the edge).
PenView.HudTop = 90
PenView.HudLeft = 252
PenView.HudBottom = 90
local HUD_GAP = 8

local PAD = 16
local HEADER = 84
local FOOTER = 34
local GAP = 8
local SCROLLBAR = 12

-- Sizes per layout (design units; the HUD's UIScale shrinks them on phones).
-- Rows = the most rows shown (fewer when the screen is short, see `room`).
-- Tool* = the send toolbar under the header (ToolH tall, buttons ToolButtonH).
-- Toggle* = the AUTO-SORT switch left of the X (as tall as the X).
local LAYOUTS = {
	Normal = {
		Width = 740,
		RowH = 64,
		ButtonH = 50,
		TakeW = 92,
		SendW = 92,
		PodiumW = 112,
		Rows = 5,
		Name = 20,
		Close = 52,
		ToolH = 58,
		ToolButtonH = 50,
		DirtyW = 190,
		UnkeptW = 170,
		StopW = 100,
		ToolText = 18,
		StatusText = 16,
		ToggleW = 172,
		ToggleText = 17,
	},
	Compact = {
		Width = 800,
		RowH = 86,
		ButtonH = 72,
		TakeW = 108,
		SendW = 108,
		PodiumW = 124,
		Rows = 3,
		Name = 22,
		Close = 72,
		ToolH = 84,
		ToolButtonH = 72,
		DirtyW = 214,
		UnkeptW = 196,
		StopW = 112,
		ToolText = 20,
		StatusText = 19,
		ToggleW = 196,
		ToggleText = 19,
	},
}

local function layoutOf(refs: Refs): typeof(LAYOUTS.Normal)
	return if refs.Compact then LAYOUTS.Compact else LAYOUTS.Normal
end

---------------------------------------------------------------- entries (pure)

local KIND_ORDER = { Clean = 1, Ingot = 2, Gear = 3, Crushed = 4, Raw = 5 }

-- Key of the one merged Dirty Ore row (not a storage key).
PenView.DirtyKey = "Dirty"

--[[
	Rows for a State Storage summary ("K|O|G|R" -> count): unknown keys
	are skipped, cleaned ore first by income (best first), then the other
	kinds by value, dirty ore last as ONE row (PenView.DirtyKey; its Keys
	map holds the real keys), so the list never shows which chunks are
	the same ore. Pick mode keeps only podium ore.
]]
function PenView.entries(summary: any, mode: Mode?): { Entry }
	local list: { Entry } = {}
	if type(summary) ~= "table" then
		return list
	end
	local dirtyRow: Entry? = nil
	for key, count in summary do
		local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
		if desc and type(count) == "number" and count >= 1 and count == count then
			local podiumOre = EconomyConfig.Podiums.Kinds[desc.K] == true
			if desc.K == "Raw" and mode ~= "Pick" then
				local current = dirtyRow
				if not current then
					local newRow: Entry = {
						Key = PenView.DirtyKey,
						Kind = "Raw",
						Name = ItemData.DirtyName,
						Grade = nil,
						Count = 0,
						Income = 0,
						Value = 0,
						Color = PenView.DirtyColor,
						Mystery = true,
						Keys = {},
					}
					table.insert(list, newRow)
					current = newRow
					dirtyRow = newRow
				end
				local entry: Entry = current :: Entry
				entry.Count += math.floor(count)
				local keys = entry.Keys
				if keys then
					keys[key] = math.floor(count)
				end
			elseif mode ~= "Pick" or podiumOre then
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
					Keys = nil,
				} :: Entry)
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

-- A real storage key for one item of an entry: the merged Dirty Ore row
-- picks one of its keys, weighted by count (`roll` in [0, 1)).
function PenView.keyFor(entry: Entry, roll: number): string?
	local keys = entry.Keys
	if not keys then
		return entry.Key
	end
	local sorted = {}
	local total = 0
	for key, count in keys do
		table.insert(sorted, key)
		total += count
	end
	table.sort(sorted)
	local target = math.clamp(roll, 0, 0.999999) * total
	for _, key in sorted do
		target -= keys[key]
		if target < 0 then
			return key
		end
	end
	return sorted[#sorted]
end

-- The send toolbar's status line for the State's PenSend (pure): why a
-- chute waits, "Sending 3…" while items leave (the pen's and the train's
-- Direct Unload), or a short how-to. Also returns whether it waits, how
-- many items are still to go and how many of them the pen sends (STOP).
PenView.SendIdleText = "SEND puts ore on your belts at the PEN chute"
function PenView.sendText(send: any): (string, boolean, number, number)
	if type(send) ~= "table" then
		return PenView.SendIdleText, false, 0, 0
	end
	local function count(v: any): number
		return if type(v) == "number" and v == v and v < math.huge then math.max(0, math.floor(v)) else 0
	end
	local pen, train = count(send.Pen), count(send.Train)
	local total = pen + train
	local wait = if type(send.Wait) == "string" and send.Wait ~= "" then send.Wait else nil
	if total > 0 and wait then
		return `{Format.big(total)} waiting: {wait}`, true, total, pen
	elseif total > 0 then
		return `Sending {Format.big(total)}…`, false, total, pen
	end
	return PenView.SendIdleText, false, 0, 0
end

-- The row SEND button's text: "SEND", or "ALL xN?" while a second press
-- would send the rest of the stack (`rest` = N, nil = not armed).
function PenView.sendButtonText(rest: number?): string
	if rest and rest > 0 then
		return `ALL x{Format.big(rest)}?`
	end
	return "SEND"
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
	-- the pile needs real keys: open the merged Dirty Ore row up again
	local entries: { { Key: string, Count: number } } = {}
	for _, entry in PenView.entries(summary, "Pen") do
		local keys = entry.Keys
		if keys then
			local sorted = {}
			for key in keys do
				table.insert(sorted, key)
			end
			table.sort(sorted)
			for _, key in sorted do
				table.insert(entries, { Key = key, Count = keys[key] })
			end
		else
			table.insert(entries, { Key = entry.Key, Count = entry.Count })
		end
	end
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
	-- the sorting billboard's switch, left of the X (setAutoSort shows it)
	local autoSort = UIKit.button(panel, "AUTO-SORT ON", Theme.Good, Theme.GoodDark, {
		Name = "AutoSort",
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		TextSize = LAYOUTS.Normal.ToggleText,
	})

	-- the send toolbar (WP-Belts): three buttons and a status line in a row
	local toolbar = UIKit.new("Frame", {
		Name = "Toolbar",
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(1, -PAD * 2, 0, LAYOUTS.Normal.ToolH),
		BackgroundTransparency = 1,
	}, panel)
	UIKit.list(toolbar, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local sendDirty = UIKit.button(toolbar, "SEND ALL DIRTY", PenView.SendColor, PenView.SendDark, {
		Name = "SendDirty",
		LayoutOrder = 1,
		TextSize = 18,
	})
	local sendUnkept = UIKit.button(toolbar, "SEND UNKEPT", PenView.SendColor, PenView.SendDark, {
		Name = "SendUnkept",
		LayoutOrder = 2,
		TextSize = 18,
	})
	local stopSend = UIKit.button(toolbar, "STOP", Theme.Bad, Theme.BadDark, {
		Name = "StopSend",
		LayoutOrder = 3,
		TextSize = 18,
	})
	local status = UIKit.label(toolbar, "", 16, {
		Name = "Status",
		LayoutOrder = 4,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
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
		AutoSort = autoSort,
		Toolbar = toolbar,
		SendDirty = sendDirty,
		SendUnkept = sendUnkept,
		StopSend = stopSend,
		Status = status,
		List = list,
		Empty = empty,
		Hint = hint,
		PadHint = padHint,
		PadA = padA,
		PadAText = padAText,
		PadB = padB,
		Rows = {},
		Compact = false,
		Room = nil,
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
	local buttons = l.TakeW + l.SendW + l.PodiumW + 32
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
	take.Position = UDim2.fromOffset(rowW - l.PodiumW - l.SendW - l.TakeW - 24, buttonY)
	take.Size = UDim2.fromOffset(l.TakeW, l.ButtonH)
	local sendHolder = row.Send.Parent :: Frame
	sendHolder.Position = UDim2.fromOffset(rowW - l.PodiumW - l.SendW - 16, buttonY)
	sendHolder.Size = UDim2.fromOffset(l.SendW, l.ButtonH)
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
	local send = UIKit.button(frame, "SEND", PenView.SendColor, PenView.SendDark, { Name = "Send", TextSize = 20 })
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
		Send = send,
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
		local sendHolder = row.Send.Parent :: Frame
		local podiumHolder = row.Podium.Parent :: Frame
		takeHolder.Visible = not pick
		sendHolder.Visible = not pick
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

--[[
	The send toolbar (normal mode only): what is being sent and why it waits
	(PenView.sendText of the State's PenSend), STOP while something is
	queued, SEND UNKEPT only with the sorting billboard (`canUnkept`), SEND
	ALL DIRTY dimmed while the pen holds no dirty ore (`dirty` = how many).
]]
function PenView.setSending(refs: Refs, send: any, canUnkept: boolean, dirty: number)
	local text, waiting, _, pen = PenView.sendText(send)
	refs.Status.Text = text
	refs.Status.TextColor3 = if waiting then Theme.Accent else Theme.TextDim
	-- STOP stops the pen's sends (the train's Direct Unload goes on)
	local stop = refs.StopSend.Parent :: Frame
	stop.Visible = pen > 0
	local unkept = refs.SendUnkept.Parent :: Frame
	unkept.Visible = canUnkept
	refs.SendDirty.BackgroundColor3 = if dirty > 0 then PenView.SendColor else Theme.PanelLight
	refs.SendDirty.TextTransparency = if dirty > 0 then 0 else 0.4
end

--[[
	The AUTO-SORT switch (pen mode, with the sorting billboard: `visible`):
	green "AUTO-SORT ON" or grey "AUTO-SORT OFF" (State AutoSort).
]]
function PenView.setAutoSort(refs: Refs, visible: boolean, on: boolean)
	local holder = refs.AutoSort.Parent :: Frame
	local show = visible and refs.Mode == "Pen"
	local changed = holder.Visible ~= show
	holder.Visible = show
	refs.AutoSort.Text = if on then "AUTO-SORT ON" else "AUTO-SORT OFF"
	refs.AutoSort.BackgroundColor3 = if on then Theme.Good else PenView.OffColor
	holder.BackgroundColor3 = if on then Theme.GoodDark else PenView.OffDark
	if changed then
		-- the fill bar makes room for it
		local l = layoutOf(refs)
		local right = PAD + l.Close + (if show then 8 + l.ToggleW + 12 else 90 - l.Close)
		refs.Bar.Size = UDim2.new(1, -(PAD + 110 + right), 0, 14)
	end
end

-- How many rows fit (the HUD stays clear: PenView.HudTop / HudBottom), at
-- most the layout's Rows, at least MinRows.
local function rowsFor(refs: Refs, fixed: number): number
	local l = layoutOf(refs)
	local room = refs.Room
	if not room then
		return l.Rows
	end
	local free = if refs.Compact
		then room.Y - HUD_GAP - PenView.HudBottom - HUD_GAP
		else room.Y - 2 * (math.max(PenView.HudTop, PenView.HudBottom) + HUD_GAP)
	local rows = math.floor((free - fixed + GAP) / (l.RowH + GAP))
	return math.clamp(rows, PenView.MinRows, l.Rows)
end

-- Where the panel sits: centred; on phones (with `room`) at the top, right of the coins.
local function placePanel(refs: Refs, width: number)
	local room = refs.Room
	if refs.Compact and room then
		-- centre it in the room right of the coins, never off the right edge
		local want = PenView.HudLeft + HUD_GAP + width / 2 - room.X / 2
		local most = room.X / 2 - width / 2 - HUD_GAP
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0)
		refs.Panel.Position = UDim2.new(0.5, math.max(0, math.min(want, most)), 0, HUD_GAP)
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
end

-- Panel size, place, header, toolbar and list for the current layout and mode.
local function layoutPanel(refs: Refs)
	local l = layoutOf(refs)
	local tool = if refs.Mode == "Pen" then l.ToolH else 0
	local fixed = HEADER + tool + 12 + FOOTER
	local rows = rowsFor(refs, fixed)
	local height = fixed + rows * l.RowH + (rows - 1) * GAP
	refs.Panel.Size = UDim2.fromOffset(l.Width, height)
	placePanel(refs, l.Width)
	local toggle = refs.AutoSort.Parent :: Frame
	toggle.Position = UDim2.new(1, -(PAD + l.Close + 8), 0, 14)
	toggle.Size = UDim2.fromOffset(l.ToggleW, l.Close)
	refs.AutoSort.TextSize = l.ToggleText
	if refs.Mode ~= "Pen" then
		toggle.Visible = false
	end
	local right = PAD + l.Close + (if toggle.Visible then 8 + l.ToggleW + 12 else 90 - l.Close)
	refs.Bar.Size = UDim2.new(1, -(PAD + 110 + right), 0, 14)
	refs.Toolbar.Visible = tool > 0
	refs.Toolbar.Size = UDim2.new(1, -PAD * 2, 0, l.ToolH)
	refs.List.Position = UDim2.fromOffset(PAD, HEADER + tool)
	refs.List.Size = UDim2.new(1, -PAD, 1, -(HEADER + tool + FOOTER))
	local used = 0
	local function sizeButton(button: TextButton, width: number)
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(width, l.ToolButtonH)
		button.TextSize = l.ToolText
		used += width + 8
	end
	sizeButton(refs.SendDirty, l.DirtyW)
	sizeButton(refs.SendUnkept, l.UnkeptW)
	sizeButton(refs.StopSend, l.StopW)
	refs.Status.Size = UDim2.fromOffset(math.max(80, l.Width - PAD * 2 - used), l.ToolButtonH)
	refs.Status.TextSize = l.StatusText
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
	layoutPanel(refs)
end

--[[
	Phone layout (taller rows and buttons) or the normal one. `room`: the
	screen in design units (the ScreenGui's size divided by its UIScale),
	so the panel can keep clear of the HUD (nil: the full layout, centred).
]]
function PenView.setCompact(refs: Refs, compact: boolean, room: Vector2?)
	refs.Compact = compact
	refs.Room = room
	local l = layoutOf(refs)
	layoutPanel(refs)
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	refs.Title.TextSize = if compact then 34 else 30
	for _, row in refs.Rows do
		layoutRow(refs, row)
	end
end

return PenView
