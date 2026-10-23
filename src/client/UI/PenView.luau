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
	The look is the Robux Shop's Pop kit (owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"; Pop.luau, PopTheme): a black
	frame, the blue header band (the pen's colour, LightSkin.BandRoles
	"Backpack") with the title, the glossy capacity bar (Pop.bar), the
	switch and the red X; bright SEND ALL DIRTY / SEND UNKEPT / STOP buttons;
	one row per item painted in its ore's rarity colour with the item's live
	3D picture (ItemBuilder.display in a ViewportFrame; Dirty Ore: a dirty
	chunk under a "?") on a light burst, the grade chip, the income in green
	money text and green TAKE, blue SEND, orange PODIUM buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Rng = require(Shared.Util.Rng)
local UIConfig = require(Shared.Config.UIConfig)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

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
PenView.HudLeftLight = 300 -- the light HUD's coins pill (34 + 250) and its menu column
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

-- The podium income multiplier: the State's IncomeMult (PodiumService: every
-- bonus, the player level and the 2x Money pass too), else from its Bonuses
-- (1 + IncomePct, the same bonus the podium tags count); junk counts as none.
function PenView.incomeMult(bonuses: any, incomeMult: any?): number
	if type(incomeMult) == "number" and incomeMult == incomeMult and incomeMult >= 0 and incomeMult < math.huge then
		return incomeMult
	end
	local pct = if type(bonuses) == "table" then bonuses.IncomePct else nil
	if type(pct) ~= "number" or pct ~= pct or pct < 0 or pct == math.huge then
		return 1
	end
	return 1 + pct
end

--[[
	Rows for a State Storage summary ("K|O|G|R" -> count): unknown keys
	are skipped, cleaned ore first by income (best first), then the other
	kinds by value, dirty ore last as ONE row (PenView.DirtyKey; its Keys
	map holds the real keys), so the list never shows which chunks are
	the same ore. Pick mode keeps only podium ore. `incomeMult` (default 1)
	scales "+$X/s" like the podium tags and the HUD do (PenView.incomeMult).
]]
function PenView.entries(summary: any, mode: Mode?, incomeMult: number?): { Entry }
	local mult = if type(incomeMult) == "number"
			and incomeMult == incomeMult
			and incomeMult >= 0
			and incomeMult < math.huge
		then incomeMult
		else 1
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
				table.insert(
					list,
					{
						Key = key,
						Kind = desc.K,
						Name = ItemData.displayName(desc.K, desc.O, desc.G, desc.R),
						Grade = if dirty then nil else desc.G,
						Count = math.floor(count),
						Income = if podiumOre then ItemData.income(desc) * mult else 0,
						Value = if dirty then 0 else ItemData.value(desc.K, desc.O, desc.G, desc.R),
						Color = if dirty or not ore then PenView.DirtyColor else ore.Color,
						Mystery = dirty,
						Keys = nil,
					} :: Entry
				)
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

--[[
	The send toolbar's status line for the State's PenSend (pure): the pen's
	own sends ("Sending 3…", or why they wait: PenWait), else the train's
	Direct Unload ("Train unloading 4…"; why that waits shows in the train
	panel, TrainWait), or a short how-to. Also returns whether the pen's
	sends wait, how many items are still to go (both lanes) and how many of
	them the pen sends (STOP).
]]
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
	local wait = if type(send.PenWait) == "string" and send.PenWait ~= "" then send.PenWait else nil
	if pen > 0 and wait then
		return `{Format.big(pen)} waiting: {wait}`, true, total, pen
	elseif pen > 0 then
		return `Sending {Format.big(pen)}…`, false, total, pen
	elseif train > 0 then
		return `Train unloading {Format.big(train)}…`, false, total, 0
	end
	return PenView.SendIdleText, false, 0, 0
end

-- The row SEND button's text: "SEND", or "ALL xN?" while a second press
-- would send the whole stack (`all` = N, its size, the one just sent
-- included: that is what the second press sends; nil = not armed).
function PenView.sendButtonText(all: number?): string
	if all and all > 1 then
		return `ALL x{Format.big(all)}?`
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

---------------------------------------------------------------- the Pop look (the kit pieces this window needs)

PenView.Paint = "Blue" -- the header band: the pen's colour (LightSkin.BandRoles TerraForgePen = "Backpack")
-- the merged Dirty Ore row: a dirt brown (it never says which ores they are)
PenView.DirtyPaint = {
	Top = Color3.fromRGB(190, 162, 132),
	Bottom = Color3.fromRGB(104, 82, 64),
	Edge = PopTheme.Outline,
} :: Pop.Paint

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(214, 220, 232) -- quieter white text (status, hints)
local ROW_CORNER = 10
local BAR_H = 20 -- the capacity bar's height
local HOLDER_KEYS = { Size = true, Position = true, AnchorPoint = true, LayoutOrder = true, Visible = true }
local HOVER = Color3.fromRGB(236, 236, 236)
local PRESS = Color3.fromRGB(200, 200, 200)

-- A text's black edge (its Contextual UIStroke, made when missing).
local function edgeOf(label: GuiObject): UIStroke
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return Pop.edge(label)
end

-- White chunky text with a black edge (a UIKit label or button), or `color`.
local function ink(label: GuiObject, color: Color3?, font: Font?)
	local text: any = label
	text.FontFace = font or PopTheme.Font
	text.TextColor3 = color or PopTheme.Ink
	local edge = edgeOf(label)
	edge.Color = PopTheme.Outline
	edge.Thickness = Pop.edgeFor(text.TextSize)
	edge.Transparency = 0
	edge.LineJoinMode = Enum.LineJoinMode.Round
end

--[[
	The pixel reels (owner 2026-10-22, docs/art/ui_pixel_refs: "the
	inventory exactly like this"): short words (the title, the count, the
	item names, chips, every button) in the pixel font, shrunk to fit their
	box (Pop.fit) with a margin; sentences (the status, the hint, the empty
	text) stay round. Rows are chunky painted bars with a darker lip, the
	lattice and a turning sunburst behind the item's picture.
]]

-- The biggest Pop.text size (at most `size`) at which `text` leaves a margin inside `width`.
local function wordSize(text: string, size: number, width: number): number
	local s = size
	while s > 10 and Pop.textWidth(text, s) > width - 14 do
		s -= 1
	end
	return s
end

-- A short word in the pixel font, shrunk to fit (at most `size`, a margin inside `width`).
local function pixel(label: GuiObject, size: number, width: number?)
	local l: any = label
	l.FontFace = PopTheme.Pixel
	l.TextWrapped = false
	l:SetAttribute("Round", nil) -- (a word again: see roundText)
	Pop.fit(l, if width then wordSize(l.Text, size, width) else size)
	local edge = edgeOf(label)
	edge.LineJoinMode = Enum.LineJoinMode.Miter
end

-- A sentence in the round font at `size` (no shrink-to-fit), round for good (Pop.round)
-- until pixel() makes it a word again; still cut with "..." rather than spilled.
local function roundText(label: TextLabel, size: number)
	local cut = label.TextTruncate
	Pop.round(label, size)
	label.TextTruncate = cut
	edgeOf(label).LineJoinMode = Enum.LineJoinMode.Round
end

--[[
	The grade chip's pixel letters (design units): the chip is as wide as
	its word needs (review 2026-10-22: "PRISTINE" shrank to 6 pt on a
	568x320 phone), so 13 units are 8 pt at the phones' 0.62 UI scale.
]]
PenView.GradeSize = { Normal = 11, Compact = 13 }

-- How wide the grade chip is for `word` (at least a 4-letter word's room).
function PenView.gradeWidth(word: string, compact: boolean): number
	local size = if compact then PenView.GradeSize.Compact else PenView.GradeSize.Normal
	return math.max(4, utf8.len(word) or #word) * size + 10
end

-- The row's second line: the grade chip (its word's width) and the income right of it.
local function placeLine(refs: Refs, row: Row)
	local l = layoutOf(refs)
	local textX = row.Name.Position.X.Offset
	local textW = row.Name.Size.X.Offset
	local lineY = math.floor(l.RowH * 0.5) + 2
	local chipH = if refs.Compact then 26 else 22
	local word = row.Grade.Text
	local gradeW = PenView.gradeWidth(word, refs.Compact)
	row.Grade.Position = UDim2.fromOffset(textX, lineY)
	row.Grade.Size = UDim2.fromOffset(gradeW, chipH)
	local size = if refs.Compact then PenView.GradeSize.Compact else PenView.GradeSize.Normal
	pixel(row.Grade, size / PopTheme.PixelScale)
	local incomeX = textX + (if row.Grade.Visible and word ~= "" then gradeW + 8 else 0)
	row.Income.Position = UDim2.fromOffset(incomeX, lineY - 2)
	row.Income.Size = UDim2.fromOffset(math.max(40, textX + textW - incomeX), chipH + 4)
end

--[[
	A Pop button that keeps UIKit.button's shape: the returned TextButton
	(clear, its own word: controllers and views set its Text, TextSize and
	TextTransparency) fills its holder, and the holder is the painted face
	(Pop.face: the glossy paint, the black border, the light rim, studs).
	(A UIGradient on the button itself would tint its word too.) Size /
	Position / AnchorPoint / LayoutOrder / Visible go on the holder (layouts
	move it), the rest on the button. paintButton recolours the face.
]]
local function popButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local name = if props and type(props.Name) == "string" then props.Name else text
	local face = UIKit.new("Frame", {
		Name = name .. "Holder",
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 4,
	}, parent)
	Pop.face(face, paint)
	Pop.studs(face, PopTheme.Corner, 0.45, 28, 4)
	Pop.gleam(face, 4)
	Pop.fxTag(face, "Press")
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		FontFace = PopTheme.Font,
		TextColor3 = PopTheme.Ink,
		TextSize = 22,
		Selectable = true,
		ZIndex = 5,
	}, face)
	Pop.edge(button, 2.5)
	if props then
		for key, value in props do
			local target: any = if HOLDER_KEYS[key] then face else button
			if key ~= "Name" then
				target[key] = value
			end
		end
	end
	-- (the word: pixel, off the lip)
	UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 5),
	}, button)
	pixel(button, button.TextSize)
	-- hover / press darken the face (AutoButtonColor would only darken the clear button)
	pcall(function()
		local b: any = button
		b:GetPropertyChangedSignal("GuiState"):Connect(function()
			local state = b.GuiState
			face.BackgroundColor3 = if state == Enum.GuiState.Press then PRESS elseif state == Enum.GuiState.Hover then HOVER else WHITE
		end)
	end)
	return button
end

-- Recolours a popButton's face.
local function paintButton(button: TextButton, paint: string | Pop.Paint)
	local face = button.Parent
	if face and face:IsA("GuiObject") then
		Pop.repaint(face, paint)
	end
end

--[[
	The window's chrome on an old panel: the black frame, a dark studded
	body and the bright header band (shine stripes, studs) `band` units
	tall; both sit under everything else (ZIndex 0).
]]
local function chrome(panel: Frame, paint: string | Pop.Paint, band: number)
	panel.BackgroundColor3 = PopTheme.Outline
	local old = panel:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = PopTheme.Outline
		stroke.Thickness = 4
	end
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, band),
		Size = UDim2.new(1, -8, 1, -(band + 4)),
		ZIndex = 0,
	}, panel)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	Pop.studs(body, 4, 0.5, 36, 0)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 0,
	}, body)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	local head = UIKit.new("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, band - 8),
		ClipsDescendants = true,
		ZIndex = 0,
	}, panel)
	Pop.face(head, paint, 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = 3
	-- (the pixel reels: the lattice over the band and a gleam now and then, no shine stripes)
	Pop.studs(head, 4, 0.35, 40, 0)
	Pop.gleam(head, 0)
end

-- The title's 3D drop shadow (Pop.shadow), kept on the title as layouts move it.
local function syncShadow(title: TextLabel)
	local parent = title.Parent
	local found = if parent then parent:FindFirstChild(title.Name .. "Shadow") else nil
	local shade: TextLabel = if found and found:IsA("TextLabel") then found else Pop.shadow(title)
	shade.Position = title.Position + UDim2.fromOffset(0, 4)
	shade.Size = title.Size
	shade.AnchorPoint = title.AnchorPoint
	shade.Text = title.Text
	shade.TextSize = title.TextSize
	shade.TextScaled = title.TextScaled
	local fit = title:FindFirstChildOfClass("UITextSizeConstraint")
	local shadeFit = shade:FindFirstChildOfClass("UITextSizeConstraint")
	if fit and shadeFit then
		shadeFit.MaxTextSize = fit.MaxTextSize
		shadeFit.MinTextSize = fit.MinTextSize
	elseif fit then
		fit:Clone().Parent = shade
	end
	shade.TextXAlignment = title.TextXAlignment
	shade.Visible = title.Visible
	shade.ZIndex = math.max(1, title.ZIndex - 1)
end

-- The ore description behind an entry (nil: the merged Dirty Ore row).
local function descOf(entry: Entry): ItemData.Desc?
	if entry.Keys ~= nil or entry.Key == PenView.DirtyKey then
		return nil
	end
	return ItemData.parseKey(entry.Key)
end

-- The paint of a row: its ore's rarity (Pop.rarityPaint); Dirty Ore a dirt brown.
function PenView.rowPaint(entry: Entry): Pop.Paint
	local desc = descOf(entry)
	if entry.Mystery or not desc then
		return PenView.DirtyPaint
	end
	local ore = OreData.ById[desc.O]
	return Pop.rarityPaint(if ore then ore.Rarity else nil)
end

--[[
	The item a row shows: its picture name (the preview's icon) and the
	description ItemBuilder.display draws. Dirty Ore: a dirty chunk that
	never tells which ore it is.
]]
function PenView.pictureOf(entry: Entry): (string, ItemData.Desc)
	local desc = descOf(entry)
	if entry.Mystery or not desc then
		return "ore_raw", { K = "Raw", O = "Copper" }
	end
	return `item_{desc.K}_{desc.O}`, desc
end

-- A row's live 3D picture (built once: a row's key never changes).
local function fillPicture(icon: Frame, entry: Entry)
	if icon:FindFirstChild("Picture") then
		return
	end
	local name, desc = PenView.pictureOf(entry)
	local ok, model = pcall(ItemBuilder.display, desc, CFrame.new(), name)
	Pop.model(icon, name, 10, if ok then model else nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(1.12, 1.12),
		ZIndex = 3,
	}, Vector3.new(-0.5, 0.55, -1))
end

---------------------------------------------------------------- building

-- The capacity bar's paint: green, orange from 80%, red when full.
local function fillPaint(fraction: number): string
	if fraction >= 1 then
		return "Red"
	elseif fraction >= 0.8 then
		return "Orange"
	end
	return "Green"
end

function PenView.build(): Refs
	local gui = UIKit.screen("TerraForgePen", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("Pop", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(LAYOUTS.Normal.Width, 400),
	})
	chrome(panel, PenView.Paint, HEADER)
	local title = UIKit.label(panel, "ORE PEN", 30, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, 4),
		Size = UDim2.new(1, -(PAD * 2 + 90), 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextScaled = false,
		ZIndex = 3,
	})
	ink(title)
	pixel(title, 34)
	local header = UIKit.label(panel, "0 / 0", 20, {
		Name = "Header",
		Position = UDim2.fromOffset(PAD, 48),
		Size = UDim2.fromOffset(110, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 3,
	})
	ink(header)
	pixel(header, 24, 98)
	-- the capacity bar (Pop.bar): a dark well, a glossy fill
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(PAD + 110, 61 - BAR_H / 2),
		Size = UDim2.new(1, -(PAD * 2 + 110 + 90), 0, BAR_H),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, panel)
	UIKit.corner(bar, BAR_H // 2)
	Pop.border(bar, 3)
	local barFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, bar)
	Pop.face(barFill, "Green", BAR_H // 2, true, false)
	local fillBorder = barFill:FindFirstChild("Border")
	if fillBorder then
		fillBorder:Destroy()
	end

	local close = popButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 16),
		Size = UDim2.fromOffset(LAYOUTS.Normal.Close, LAYOUTS.Normal.Close),
		TextSize = 32,
		FontFace = PopTheme.Heavy,
	})
	-- the sorting billboard's switch, left of the X (setAutoSort shows it)
	local autoSort = popButton(panel, "AUTO-SORT ON", "Green", {
		Name = "AutoSort",
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		TextSize = LAYOUTS.Normal.ToggleText,
	})

	-- the send toolbar (WP-Belts): three bright buttons and a status line in a row
	local toolbar = UIKit.new("Frame", {
		Name = "Toolbar",
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(1, -PAD * 2, 0, LAYOUTS.Normal.ToolH),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, panel)
	UIKit.list(toolbar, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local sendDirty = popButton(toolbar, "SEND ALL DIRTY", "Blue", {
		Name = "SendDirty",
		LayoutOrder = 1,
		TextSize = 18,
	})
	local sendUnkept = popButton(toolbar, "SEND UNKEPT", "Teal", {
		Name = "SendUnkept",
		LayoutOrder = 2,
		TextSize = 18,
	})
	local stopSend = popButton(toolbar, "STOP", "Red", {
		Name = "StopSend",
		LayoutOrder = 3,
		TextSize = 18,
	})
	local status = UIKit.label(toolbar, "", 16, {
		Name = "Status",
		LayoutOrder = 4,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	ink(status, SOFT)

	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(1, -PAD, 1, -(HEADER + FOOTER)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 2,
	}, panel)
	UIKit.list(list, Enum.FillDirection.Vertical, GAP)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, list)

	local empty = UIKit.label(panel, "", 20, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, (HEADER - FOOTER) / 2),
		Size = UDim2.new(1, -PAD * 4, 0, 70),
		Visible = false,
		ZIndex = 3,
	})
	ink(empty, SOFT)
	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -8),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		ZIndex = 3,
	})
	ink(hint, SOFT)
	-- gamepads: the platform's own button glyphs (Xbox or PlayStation), set by the controller
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
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
			ZIndex = 3,
		}, padHint)
	end
	local function word(order: number, text: string): TextLabel
		local label = UIKit.label(padHint, text, 16, {
			Name = "Word" .. order,
			LayoutOrder = order,
			Size = UDim2.fromOffset(84, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			ZIndex = 3,
		})
		ink(label, SOFT)
		return label
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
	-- (the light UI: an open window hides the touch thumbstick)
	if UIConfig.lightUI() then
		TouchControls.follow(gui)
	end
	PenView.setCompact(refs, false)
	PenView.setMode(refs, "Pen", nil)
	return refs
end

-- Places the row's parts for the current layout.
local function layoutRow(refs: Refs, row: Row)
	local l = layoutOf(refs)
	local rowW = l.Width - PAD - SCROLLBAR - PAD
	row.Frame.Size = UDim2.fromOffset(rowW, l.RowH)
	local icon = l.RowH - 12
	row.Icon.Size = UDim2.fromOffset(icon, icon)
	row.Icon.Position = UDim2.fromOffset(8, 6)
	row.Mystery.TextSize = math.floor(icon * 0.62)
	local textX = icon + 18
	local buttons = l.TakeW + l.SendW + l.PodiumW + 32
	local countW = 64
	local textW = rowW - textX - buttons - countW
	row.Name.Position = UDim2.fromOffset(textX, 6)
	row.Name.Size = UDim2.fromOffset(textW, math.floor(l.RowH * 0.42))
	pixel(row.Name, l.Name + 6, textW)
	placeLine(refs, row)
	if Pop.isPixel(row.Income.FontFace) then
		pixel(row.Income, if refs.Compact then 26 else 24)
	else
		row.Income.TextSize = if refs.Compact then 18 else 16
	end
	row.Count.Position = UDim2.fromOffset(rowW - buttons - countW, 0)
	row.Count.Size = UDim2.fromOffset(countW - 6, l.RowH)
	local buttonY = math.floor((l.RowH - l.ButtonH) / 2)
	local take = row.Take.Parent :: Frame
	take.Position = UDim2.fromOffset(rowW - l.PodiumW - l.SendW - l.TakeW - 24, buttonY)
	take.Size = UDim2.fromOffset(l.TakeW, l.ButtonH)
	local sendHolder = row.Send.Parent :: Frame
	sendHolder.Position = UDim2.fromOffset(rowW - l.PodiumW - l.SendW - 16, buttonY)
	sendHolder.Size = UDim2.fromOffset(l.SendW, l.ButtonH)
	local podium = row.Podium.Parent :: Frame
	podium.Position = UDim2.fromOffset(rowW - l.PodiumW - 8, buttonY)
	podium.Size = UDim2.fromOffset(l.PodiumW, l.ButtonH)
	-- (every row button's word at one size: the longest, "PODIUM", sets it)
	local word = wordSize("PODIUM", if refs.Compact then 28 else 26, l.PodiumW)
	for _, button in { row.Take, row.Send, row.Podium } do
		pixel(button, word)
	end
end

local function newRow(refs: Refs, key: string): Row
	local frame = UIKit.new("Frame", {
		Name = "Row",
		BorderSizePixel = 0,
		ClipsDescendants = true, -- (the light burst behind the picture)
	}, refs.List)
	frame:SetAttribute("Key", key)
	Pop.face(frame, PenView.DirtyPaint, ROW_CORNER)
	Pop.studs(frame, ROW_CORNER, 0.45, 40, 1)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	-- the picture: a light burst and a soft glow behind the item's live 3D look
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, frame)
	Pop.rays(icon, UDim2.fromScale(0.5, 0.5), 8, 80, 0.5, 1)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 2,
	}, icon)
	UIKit.corner(glow, 999)
	local mystery = UIKit.label(icon, "?", 28, {
		Name = "Mystery",
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
		Visible = false,
		ZIndex = 5,
	})
	ink(mystery, WHITE, PopTheme.Heavy)
	pixel(mystery, 44)
	local name = UIKit.label(frame, "", 22, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	ink(name)
	-- the grade chip: one bright colour (a gradient would tint its word), a black border
	local grade = UIKit.chip(frame, "", Theme.PanelDark, { Name = "Grade", Size = UDim2.fromOffset(88, 22), ZIndex = 4 })
	for _, child in grade:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child:Destroy()
		end
	end
	Pop.border(grade, 2)
	ink(grade)
	local income = UIKit.label(frame, "", 18, {
		Name = "Income",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(income, PopTheme.Money, PopTheme.Pixel)
	local count = UIKit.label(frame, "x0", 26, {
		Name = "Count",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(count, WHITE, PopTheme.Heavy)
	pixel(count, 34)
	local take = popButton(frame, "TAKE", "Green", { Name = "Take", TextSize = 20 })
	local send = popButton(frame, "SEND", "Blue", { Name = "Send", TextSize = 20 })
	local podium = popButton(frame, "PODIUM", "Orange", { Name = "Podium", TextSize = 20 })
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
		Pop.repaint(row.Frame, PenView.rowPaint(entry))
		fillPicture(row.Icon, entry)
		row.Mystery.Visible = entry.Mystery
		row.Name.Text = string.upper(entry.Name)
		pixel(row.Name, (layoutOf(refs).Name + 6), row.Name.Size.X.Offset)
		local grade = entry.Grade and ItemData.GradeById[entry.Grade]
		row.Grade.Visible = grade ~= nil
		if grade then
			row.Grade.Text = string.upper(grade.Name)
			row.Grade.BackgroundColor3 = grade.Color:Lerp(Color3.new(0, 0, 0), 0.14)
		end
		placeLine(refs, row)
		row.Income.Text = if entry.Income > 0
			then Format.perSecond(entry.Income)
			elseif entry.Mystery then "Clean it to see what it is"
			else ""
		row.Income.TextColor3 = if entry.Income > 0 then PopTheme.Money else SOFT
		-- (an amount is a pixel word; "Clean it to see what it is" a round sentence)
		if entry.Income > 0 then
			pixel(row.Income, if refs.Compact then 26 else 24)
		else
			roundText(row.Income, if refs.Compact then 18 else 16)
		end
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

-- The status line while the pen holds more than its capacity (State PenOver:
-- a rescue move overfilled it; the server refuses new ore with "PenOver").
PenView.OverText = "Over its limit: nothing new goes in until you TAKE, sell or SEND some"

-- Does the pen hold more than its capacity?
function PenView.isOver(count: number, capacity: number): boolean
	return capacity > 0 and count > capacity
end

--[[
	"37 / 40" and the capacity bar (green, orange from 80%, red when full).
	Over its capacity it stays red and, while nothing is being sent
	(setSending runs first and showed the idle line), the status line says
	why new ore can't go in (OverText).
]]
function PenView.setHeader(refs: Refs, count: number, capacity: number)
	refs.Header.Text = `{Format.commas(count)} / {Format.commas(capacity)}`
	pixel(refs.Header, 24, 98)
	local fraction = if capacity > 0 then count / capacity else 1
	refs.BarFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	refs.BarFill.Visible = fraction > 0.001
	local paint = fillPaint(fraction)
	Pop.repaint(refs.BarFill, paint, true)
	refs.Header.TextColor3 = if fraction >= 0.8 then PopTheme.Paints[paint].Top else PopTheme.Ink
	if PenView.isOver(count, capacity) and refs.Status.Text == PenView.SendIdleText then
		refs.Status.Text = PenView.OverText
		refs.Status.TextColor3 = Theme.Bad
	end
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
	ALL DIRTY greyed out while the pen holds no dirty ore (`dirty` = how many).
]]
function PenView.setSending(refs: Refs, send: any, canUnkept: boolean, dirty: number)
	local text, waiting, _, pen = PenView.sendText(send)
	refs.Status.Text = text
	refs.Status.TextColor3 = if waiting then Theme.Accent else SOFT
	-- STOP stops the pen's sends (the train's Direct Unload goes on)
	local stop = refs.StopSend.Parent :: Frame
	stop.Visible = pen > 0
	local unkept = refs.SendUnkept.Parent :: Frame
	unkept.Visible = canUnkept
	paintButton(refs.SendDirty, if dirty > 0 then "Blue" else PopTheme.Gray)
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
	paintButton(refs.AutoSort, if on then "Green" else "Slate")
	if changed then
		-- the fill bar makes room for it
		local l = layoutOf(refs)
		local right = PAD + l.Close + (if show then 8 + l.ToggleW + 12 else 90 - l.Close)
		refs.Bar.Size = UDim2.new(1, -(PAD + 110 + right), 0, BAR_H)
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
		-- (the light HUD's coins pill is wider)
		local left = if UIConfig.lightUI() then PenView.HudLeftLight else PenView.HudLeft
		local want = left + HUD_GAP + width / 2 - room.X / 2
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
	-- the X and the switch, centred in the header band
	local top = math.floor((HEADER - l.Close) / 2)
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Position = UDim2.new(1, -PAD, 0, top)
	local toggle = refs.AutoSort.Parent :: Frame
	toggle.Position = UDim2.new(1, -(PAD + l.Close + 8), 0, top)
	toggle.Size = UDim2.fromOffset(l.ToggleW, l.Close)
	pixel(refs.AutoSort, l.ToggleText + 6, l.ToggleW)
	if refs.Mode ~= "Pen" then
		toggle.Visible = false
	end
	local right = PAD + l.Close + (if toggle.Visible then 8 + l.ToggleW + 12 else 90 - l.Close)
	refs.Bar.Size = UDim2.new(1, -(PAD + 110 + right), 0, BAR_H)
	refs.Toolbar.Visible = tool > 0
	refs.Toolbar.Size = UDim2.new(1, -PAD * 2, 0, l.ToolH)
	refs.List.Position = UDim2.fromOffset(PAD, HEADER + tool)
	refs.List.Size = UDim2.new(1, -PAD, 1, -(HEADER + tool + FOOTER))
	local used = 0
	local function sizeButton(button: TextButton, width: number)
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(width, l.ToolButtonH)
		pixel(button, l.ToolText + 6, width)
		used += width + 8
	end
	sizeButton(refs.SendDirty, l.DirtyW)
	sizeButton(refs.SendUnkept, l.UnkeptW)
	sizeButton(refs.StopSend, l.StopW)
	refs.Status.Size = UDim2.fromOffset(math.max(80, l.Width - PAD * 2 - used), l.ToolButtonH)
	refs.Status.TextSize = l.StatusText
	syncShadow(refs.Title)
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
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	pixel(refs.Close, math.floor(l.Close * 0.62) / PopTheme.PixelScale)
	pixel(refs.Title, if compact then 36 else 34)
	layoutPanel(refs)
	for _, row in refs.Rows do
		layoutRow(refs, row)
	end
end

return PenView
