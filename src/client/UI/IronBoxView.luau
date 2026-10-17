--[[
	Iron Box keep list (pure builder + pure helpers; IronBoxController fills
	it in and wires it up).

	  header   IRON BOX: KEEP LIST, X button, one line on what keeping means
	  modes    KEEP RARE+ | MY LIST | KEEP ALL   (data.KeepMode: RarePlus,
	           List, All); a line under them says what the chosen one does
	  chips    every DISCOVERED ore as a toggle chip, best income first:
	           kept = filled in the ore's colour with a lit (white) light,
	           KEEP and its podium income; sent on = dark with the ore's
	           colour as the light and SEND ON; the outline is the ore's
	           rarity colour. Tapping a chip flips that one ore (in KEEP
	           RARE+ / KEEP ALL it becomes your list first, so only that
	           chip changes: IronBoxService)
	  presets  ALL KEEP / ALL SEND (every chip at once; they make it your list)
	  footer   control hint (gamepads: the platform's button glyphs)
	Designed for 720 design units of height (HudController.uiScale). The
	compact layout (phones) has bigger chips and buttons, so touch targets
	stay >= 44 pt at the smallest UI scale, drops the info line (the line
	under the modes still says what they do) and sits on the right, clear
	of the HUD coins; layout() fits the chip rows to the screen.
	Pure helpers (tested): entries (the State snapshot as chips), modeOf,
	modeText, predict (what an IronBoxAction does to KeepMode / KeepList:
	the same rules as IronBoxService.apply, so a tap shows at once).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)

local IronBoxView = {}

type KeepMode = MachineData.KeepMode

export type Entry = {
	Ore: string,
	Name: string,
	Color: Color3, -- the ore's colour
	RarityColor: Color3,
	Income: number, -- coins per second on a podium (Rough grade)
	Keep: boolean, -- MachineData.keepsOre with the player's settings
}

export type Chip = {
	Ore: string,
	Button: TextButton,
	Swatch: Frame,
	Name: TextLabel,
	State: TextLabel,
	Stroke: UIStroke,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Info: TextLabel,
	Close: TextButton,
	Modes: { [string]: TextButton }, -- by KeepMode
	ModeText: TextLabel,
	List: ScrollingFrame,
	Grid: UIGridLayout,
	Empty: TextLabel,
	Presets: Frame,
	AllKeep: TextButton,
	AllSend: TextButton,
	Hint: TextLabel,
	PadHint: Frame,
	PadA: ImageLabel,
	PadAText: TextLabel,
	PadB: ImageLabel,
	Chips: { [string]: Chip },
	Compact: boolean,
	Mode: KeepMode,
	Rows: number, -- chip rows shown without scrolling
}

IronBoxView.Info = "Clean ore you KEEP goes to your Ore Pen. The rest rolls out of the box onto your belts."
IronBoxView.ModeLabels = { RarePlus = "KEEP RARE+", List = "MY LIST", All = "KEEP ALL" } :: { [string]: string }
IronBoxView.Empty = "No ores discovered yet. Clean dirty ore and every ore you find shows up here."

local PAD = 16
local GAP = 8
local SCROLLBAR = 12
local COLUMNS = 4

-- Sizes per layout (design units; the HUD's UIScale shrinks them on phones).
local LAYOUTS = {
	Normal = { ChipW = 150, ChipH = 58, ModeH = 50, PresetH = 46, Close = 50, Title = 28, Name = 18, MaxRows = 4 },
	Compact = { ChipW = 172, ChipH = 74, ModeH = 72, PresetH = 72, Close = 72, Title = 30, Name = 21, MaxRows = 3 },
}
local TITLE_H = 40
local INFO_H = 40
local MODE_TEXT_H = 24
local HINT_H = 26

local function layoutOf(compact: boolean): typeof(LAYOUTS.Normal)
	return if compact then LAYOUTS.Compact else LAYOUTS.Normal
end

---------------------------------------------------------------- pure helpers

-- The player's keep mode from a State snapshot (a broken value = the default).
function IronBoxView.modeOf(state: any): KeepMode
	local mode = if type(state) == "table" then state.KeepMode else nil
	return if MachineData.isKeepMode(mode) then mode else MachineData.Keep.Default
end

-- What the chosen mode does, for the line under the mode buttons.
function IronBoxView.modeText(mode: KeepMode): string
	if mode == "List" then
		return "Your own list. Ores you haven't set yet follow the Rare+ rule."
	elseif mode == "All" then
		return "Keeps every clean ore. Tap an ore to make your own list."
	end
	return `Keeps {MachineData.Keep.RareFrom} ore and better. Tap an ore to make your own list.`
end

--[[
	The chips for a State snapshot: every discovered ore (known ids only),
	best income first (then by name), Keep = MachineData.keepsOre with the
	snapshot's KeepMode and KeepList.
]]
function IronBoxView.entries(state: any): { Entry }
	local list: { Entry } = {}
	if type(state) ~= "table" or type(state.Discovered) ~= "table" then
		return list
	end
	local mode = IronBoxView.modeOf(state)
	for _, ore in OreData.List do
		if state.Discovered[ore.Id] == true then
			local rarity = Rarity.ById[ore.Rarity]
			table.insert(list, {
				Ore = ore.Id,
				Name = ore.Name,
				Color = ore.Color,
				RarityColor = if rarity then rarity.Color else Theme.TextDim,
				Income = ore.Income,
				Keep = MachineData.keepsOre(mode, state.KeepList, ore.Id),
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Income ~= b.Income then
			return a.Income > b.Income
		end
		return a.Name < b.Name
	end)
	return list
end

local function isDiscovered(state: { [string]: any }, oreId: any): boolean
	return type(oreId) == "string" and OreData.ById[oreId] ~= nil and type(state.Discovered) == "table" and state.Discovered[oreId] == true
end

--[[
	A copy of `state` with KeepMode / KeepList as the server will have them
	after this IronBoxAction (IronBoxService.apply's rules: only discovered
	ores; choosing an ore outside "List" mode first turns what was shown
	into the list). Anything invalid changes nothing.
]]
function IronBoxView.predict(state: { [string]: any }, action: string, arg: any): { [string]: any }
	local copy = table.clone(state)
	local oldList = if type(state.KeepList) == "table" then state.KeepList else {}
	copy.KeepList = table.clone(oldList)
	if action == "ClearList" then
		copy.KeepList = {}
		return copy
	end
	if type(arg) ~= "table" then
		return copy
	end
	if action == "SetMode" then
		if MachineData.isKeepMode(arg.Mode) then
			copy.KeepMode = arg.Mode
		end
		return copy
	end
	if type(arg.Keep) ~= "boolean" then
		return copy
	end
	local ores: { string } = {}
	if action == "SetKeep" then
		if isDiscovered(state, arg.Ore) then
			table.insert(ores, arg.Ore)
		end
	elseif action == "SetKeepMany" and type(arg.Ores) == "table" then
		for _, oreId in arg.Ores do
			if isDiscovered(state, oreId) then
				table.insert(ores, oreId)
			end
		end
	end
	if #ores == 0 then
		return copy
	end
	if copy.KeepMode ~= "List" then
		local list: { [string]: boolean } = {}
		for _, ore in OreData.List do
			if isDiscovered(state, ore.Id) then
				list[ore.Id] = MachineData.keepsOre(state.KeepMode, oldList, ore.Id)
			end
		end
		copy.KeepList = list
		copy.KeepMode = "List"
	end
	for _, oreId in ores do
		copy.KeepList[oreId] = arg.Keep
	end
	return copy
end

---------------------------------------------------------------- building

local function modeButton(parent: Instance, mode: string, order: number): TextButton
	local button = UIKit.button(parent, IronBoxView.ModeLabels[mode], Theme.PanelLight, Theme.PanelDark, {
		Name = "Mode" .. mode,
		LayoutOrder = order,
		TextSize = 19,
	})
	button:SetAttribute("Mode", mode)
	return button
end

function IronBoxView.build(): Refs
	local gui = UIKit.screen("TerraForgeIronBox", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, 500),
	})
	local title = UIKit.label(panel, "IRON BOX: KEEP LIST", 28, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.new(1, -(PAD * 2 + 80), 0, TITLE_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local info = UIKit.label(panel, IronBoxView.Info, 16, {
		Name = "Info",
		Position = UDim2.fromOffset(PAD, 8 + TITLE_H),
		Size = UDim2.new(1, -(PAD * 2 + 70), 0, INFO_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 14),
		Size = UDim2.fromOffset(LAYOUTS.Normal.Close, LAYOUTS.Normal.Close),
		TextSize = 26,
	})

	-- mode buttons in one row
	local modesRow = UIKit.new("Frame", {
		Name = "Modes",
		BackgroundTransparency = 1,
	}, panel)
	UIKit.list(modesRow, Enum.FillDirection.Horizontal, GAP, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local modes: { [string]: TextButton } = {}
	for i, mode in MachineData.Keep.Modes do
		modes[mode] = modeButton(modesRow, mode, i)
	end
	local modeText = UIKit.label(panel, "", 15, {
		Name = "ModeText",
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
	})

	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, panel)
	local grid = UIKit.new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP),
		CellSize = UDim2.fromOffset(LAYOUTS.Normal.ChipW, LAYOUTS.Normal.ChipH),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = COLUMNS,
	}, list)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2) }, list)
	local empty = UIKit.label(panel, IronBoxView.Empty, 19, {
		Name = "Empty",
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	local presets = UIKit.new("Frame", { Name = "Presets", BackgroundTransparency = 1 }, panel)
	UIKit.list(presets, Enum.FillDirection.Horizontal, GAP * 2, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local allKeep = UIKit.button(presets, "ALL KEEP", Theme.Good, Theme.GoodDark, { Name = "AllKeep", LayoutOrder = 1, TextSize = 19 })
	local allSend = UIKit.button(presets, "ALL SEND", Theme.Accent, Theme.AccentDark, { Name = "AllSend", LayoutOrder = 2, TextSize = 19 })

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -6),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		TextColor3 = Theme.TextDim,
	})
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
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
			Size = UDim2.fromOffset(90, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
		})
	end
	local padA = glyph(1)
	local padAText = word(2, "keep / send")
	local padB = glyph(3)
	word(4, "close")

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Info = info,
		Close = close,
		Modes = modes,
		ModeText = modeText,
		List = list,
		Grid = grid,
		Empty = empty,
		Presets = presets,
		AllKeep = allKeep,
		AllSend = allSend,
		Hint = hint,
		PadHint = padHint,
		PadA = padA,
		PadAText = padAText,
		PadB = padB,
		Chips = {},
		Compact = false,
		Mode = MachineData.Keep.Default,
		Rows = LAYOUTS.Normal.MaxRows,
	}
	IronBoxView.layout(refs, false, 1600, 720)
	IronBoxView.setMode(refs, MachineData.Keep.Default)
	return refs
end

--[[
	Sizes and places everything for a layout (compact = phones) inside
	`maxWidth` x `maxHeight` design units (the screen divided by the UI
	scale): as many chip rows as fit (1..MaxRows), the rest scrolls.
]]
function IronBoxView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local l = layoutOf(compact)
	local listW = COLUMNS * l.ChipW + (COLUMNS - 1) * GAP + SCROLLBAR + 4
	local width = math.min(listW + PAD * 2, math.max(320, maxWidth - 16))
	local info = if compact then 0 else INFO_H
	refs.Info.Visible = not compact
	local top = 8 + TITLE_H + info
	-- the mode buttons sit under the close button, or (no info line) beside it
	local modesY = top + 4
	local besideClose = modesY < 14 + l.Close + 4
	local modesW = width - PAD * 2 - (if besideClose then l.Close + GAP else 0)
	local modeTextY = modesY + l.ModeH + 6
	local listY = modeTextY + MODE_TEXT_H + 8
	local below = 10 + l.PresetH + 8 + HINT_H
	local rowH = l.ChipH + GAP
	local fit = math.floor((maxHeight - 24 - listY - below + GAP) / rowH)
	local rows = math.clamp(fit, 1, l.MaxRows)
	refs.Rows = rows
	local listH = rows * rowH + 8
	local height = listY + listH + below
	refs.Panel.Size = UDim2.fromOffset(width, height)
	-- phones: on the right (thumb side), clear of the HUD coins top left
	refs.Panel.AnchorPoint = if compact then Vector2.new(1, 0.5) else Vector2.new(0.5, 0.5)
	refs.Panel.Position = if compact then UDim2.new(1, -12, 0.5, 0) else UDim2.fromScale(0.5, 0.5)
	refs.Title.TextSize = l.Title
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	refs.Info.Size = UDim2.new(1, -(PAD * 2 + l.Close + 8), 0, INFO_H)
	local modesRow = (refs.Modes.RarePlus.Parent :: Frame).Parent :: Frame
	modesRow.Position = UDim2.fromOffset(PAD, modesY)
	modesRow.Size = UDim2.fromOffset(modesW, l.ModeH)
	local modeW = math.floor((modesW - GAP * 2) / 3)
	for _, button in refs.Modes do
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(modeW, l.ModeH - 6)
		button.TextSize = if compact then 21 else 19
	end
	refs.ModeText.Position = UDim2.fromOffset(PAD, modeTextY)
	refs.ModeText.Size = UDim2.new(1, -PAD * 2, 0, MODE_TEXT_H)
	refs.List.Position = UDim2.fromOffset(PAD, listY)
	refs.List.Size = UDim2.new(1, -PAD, 0, listH)
	refs.Grid.CellSize = UDim2.fromOffset(l.ChipW, l.ChipH)
	refs.Empty.Position = UDim2.fromOffset(PAD * 2, listY)
	refs.Empty.Size = UDim2.new(1, -PAD * 4, 0, listH)
	refs.Presets.Position = UDim2.fromOffset(PAD, listY + listH + 10)
	refs.Presets.Size = UDim2.new(1, -PAD * 2, 0, l.PresetH)
	for _, button in { refs.AllKeep, refs.AllSend } do
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(if compact then 210 else 170, l.PresetH - 6)
		button.TextSize = if compact then 22 else 19
	end
	for _, chip in refs.Chips do
		chip.Name.TextSize = l.Name
		chip.State.TextSize = if compact then 16 else 13
	end
end

local function newChip(refs: Refs, oreId: string): Chip
	local button = UIKit.new("TextButton", {
		Name = "Chip",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Text = "",
	}, refs.List)
	button:SetAttribute("Ore", oreId)
	UIKit.corner(button, 12)
	local stroke = UIKit.stroke(button, 3)
	UIKit.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196))
	local swatch = UIKit.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(0, 14, 0.62, 0),
		BorderSizePixel = 0,
	}, button)
	UIKit.corner(swatch, 7)
	UIKit.stroke(swatch, 2)
	local l = layoutOf(refs.Compact)
	local name = UIKit.label(button, "", l.Name, {
		Name = "OreName",
		Position = UDim2.new(0, 28, 0, 4),
		Size = UDim2.new(1, -34, 0.56, -2),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local state = UIKit.label(button, "", if refs.Compact then 16 else 13, {
		Name = "State",
		Position = UDim2.new(0, 28, 0.56, 0),
		Size = UDim2.new(1, -34, 0.4, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	local chip: Chip = { Ore = oreId, Button = button, Swatch = swatch, Name = name, State = state, Stroke = stroke }
	refs.Chips[oreId] = chip
	return chip
end

-- One chip's look: kept = filled in the ore's colour with a lit light,
-- sent on = dark with the ore's colour as the light.
local function paintChip(chip: Chip, entry: Entry, index: number)
	chip.Button.LayoutOrder = index
	chip.Name.Text = entry.Name
	chip.Stroke.Color = entry.RarityColor
	chip.Swatch.BackgroundColor3 = if entry.Keep then Theme.Text else entry.Color
	if entry.Keep then
		chip.Button.BackgroundColor3 = entry.Color
		chip.State.Text = "KEEP · " .. Format.perSecond(entry.Income)
		chip.State.TextColor3 = Theme.Text
		chip.Name.TextColor3 = Theme.Text
	else
		chip.Button.BackgroundColor3 = Theme.PanelDark
		chip.State.Text = "SEND ON"
		chip.State.TextColor3 = Theme.TextDim
		chip.Name.TextColor3 = Theme.TextDim
	end
	chip.Button:SetAttribute("Keep", entry.Keep)
end

--[[
	Shows these chips in this order. Chips are reused by ore; chips of ores
	that are gone are removed. Returns the chips just created, so the
	controller can hook up their buttons.
]]
function IronBoxView.setEntries(refs: Refs, list: { Entry }): { Chip }
	local created: { Chip } = {}
	local keep: { [string]: boolean } = {}
	for index, entry in list do
		keep[entry.Ore] = true
		local existing: Chip? = refs.Chips[entry.Ore]
		local chip: Chip
		if existing then
			chip = existing
		else
			chip = newChip(refs, entry.Ore)
			table.insert(created, chip)
		end
		paintChip(chip, entry, index)
	end
	local chips = refs.Chips :: { [string]: any }
	for oreId, chip in refs.Chips do
		if not keep[oreId] then
			chip.Button:Destroy()
			chips[oreId] = nil
		end
	end
	refs.Empty.Visible = #list == 0
	return created
end

-- The chosen mode: its button lit and the line under the buttons.
function IronBoxView.setMode(refs: Refs, mode: KeepMode)
	refs.Mode = mode
	for id, button in refs.Modes do
		local on = id == mode
		local holder = button.Parent :: Frame
		button.BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight
		holder.BackgroundColor3 = if on then Theme.AccentDark else Theme.PanelDark
		button.TextColor3 = if on then Theme.Text else Theme.TextDim
		button:SetAttribute("Selected", on)
	end
	refs.ModeText.Text = IronBoxView.modeText(mode)
end

-- The footer: a text hint, or (gamepad) button glyphs with "keep / send" / "close".
function IronBoxView.setHint(refs: Refs, text: string, glyphA: string?, glyphB: string?)
	local pad = glyphA ~= nil and glyphB ~= nil
	refs.Hint.Text = text
	refs.Hint.Visible = not pad
	refs.PadHint.Visible = pad
	if pad then
		refs.PadA.Image = glyphA :: string
		refs.PadB.Image = glyphB :: string
	end
end

return IronBoxView
