--[[
	The keep list (pure builder + pure helpers; IronBoxController fills it
	in and wires it up). Opened at an Iron Box or at the pen's sorting
	board: both use the same list.

	  header   KEEP LIST, X button, one line on what keeping means
	  modes    RARE+ | MY LIST | EVERYTHING   (data.KeepMode: RarePlus,
	           List, All); a line under them says what the chosen one does
	           (in RARE+ / EVERYTHING with a custom list saved: that a tap
	           replaces MY LIST)
	  chips    every DISCOVERED ore as a toggle chip, best income first:
	           kept = filled in the ore's colour with a lit (white) light,
	           KEEP and its podium income; sent on = dark with the ore's
	           colour as the light and SEND ON; the outline is the ore's
	           rarity colour. Tapping a chip flips that one ore (in RARE+ /
	           EVERYTHING what you see becomes your list first, replacing an
	           older one, so only that chip changes: IronBoxService). Exactly
	           Rows rows show; with more, a scroll track (the bar's groove)
	           sits at the list's right edge
	  presets  SET ALL: KEEP / SET ALL: SEND (every chip at once; they make
	           it your list), and in MY LIST mode RESET (ClearList: every ore
	           follows the Rare+ rule again)
	  footer   control hint (gamepads: the platform's button glyphs)
	Designed for 720 design units of height (HudController.uiScale). The
	compact layout (phones) has bigger chips and buttons, so touch targets
	stay >= 44 pt at the smallest UI scale (0.62), drops the info line (the
	line under the modes still says what they do) and sits on the right,
	clear of the HUD coins; layout() fits the chip rows to the screen's
	height and the chip columns (4, or 3 / 2 on narrow screens) to its
	width.
	Pure helpers (tested): entries (the State snapshot as chips), modeOf,
	hasList, modeText, predict (what an IronBoxAction does to KeepMode / KeepList:
	the same rules as IronBoxService.apply, so a tap shows at once).

	The look is the Robux Shop's Pop kit (owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"; Pop.luau, PopTheme): a black
	frame, the steel blue header band (LightSkin.BandRoles "Settings") with
	the title and the red X, bright mode tabs (the picked one painted, the
	others slate, like Pop.tabs), every ore a card painted in its rarity
	colour with the ore's live 3D picture (ItemBuilder.display) on a light
	burst: KEEP bright with its income in money green, SEND ON shaded; the
	presets are big Pop buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)

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
	Track: Frame, -- the scroll bar's groove (more chips than rows)
	Grid: UIGridLayout,
	Empty: TextLabel,
	Presets: Frame,
	AllKeep: TextButton,
	AllSend: TextButton,
	Reset: TextButton, -- MY LIST only: IronBoxAction "ClearList"
	Hint: TextLabel,
	PadHint: Frame,
	PadA: ImageLabel,
	PadAText: TextLabel,
	PadB: ImageLabel,
	Chips: { [string]: Chip },
	Compact: boolean,
	Mode: KeepMode,
	Rows: number, -- chip rows shown without scrolling
	Columns: number, -- chip columns
	Count: number, -- chips shown
}

IronBoxView.Title = "KEEP LIST"
IronBoxView.Info = "Iron Boxes put the clean ore you KEEP into your Ore Pen and send the rest on along your belts."
IronBoxView.ModeLabels = { RarePlus = "RARE+", List = "MY LIST", All = "EVERYTHING" } :: { [string]: string }
IronBoxView.PresetLabels = { Keep = "SET ALL: KEEP", Send = "SET ALL: SEND", Reset = "RESET" }
IronBoxView.Empty = "No ores discovered yet. Clean dirty ore and every ore you find shows up here."

local PAD = 16
local GAP = 8
local SCROLLBAR = 12 -- room at the list's right for its scroll bar
local BAR = 8 -- the scroll bar's thickness (inside SCROLLBAR)
local LIST_PAD = 4 -- the list's padding over and under the chips
local COLUMNS = 4 -- chip columns when the screen is wide enough...
local MIN_COLUMNS = 2 -- ...down to this many on narrow ones
local EDGE = 12 -- compact: the panel's gap to the screen's right edge
-- compact: the HUD's coin panel on the left (its left gap, width and a gap)
local HUD_CLEAR = 16 + HudView.CoinsWidth + 8

-- Sizes per layout (design units; the HUD's UIScale shrinks them on phones:
-- compact holders are 72 tall, 44.6 pt at the 0.62 floor).
local LAYOUTS = {
	Normal = {
		ChipW = 176,
		ChipH = 58,
		ModeH = 50,
		PresetH = 46,
		PresetW = 170,
		ResetW = 120,
		Close = 50,
		Title = 28,
		Name = 18,
		State = 15, -- the chip's KEEP · income / SEND ON line
		ModeText = 19,
		PresetText = 19,
		MaxRows = 4,
		-- gaps over the modes, over the presets and under them
		ModesGap = 4,
		PresetGap = 10,
		HintGap = 8,
	},
	Compact = {
		ChipW = 180,
		ChipH = 72,
		ModeH = 78,
		PresetH = 78,
		PresetW = 196,
		ResetW = 120,
		Close = 72,
		Title = 30,
		Name = 21,
		State = 16,
		ModeText = 21,
		PresetText = 21,
		MaxRows = 3,
		-- tighter, so a 568 x 320 pt phone still shows two chip rows
		ModesGap = 2,
		PresetGap = 6,
		HintGap = 4,
	},
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

-- Does the snapshot hold a custom list (any choice on KeepList)?
function IronBoxView.hasList(state: any): boolean
	local list = if type(state) == "table" then state.KeepList else nil
	return type(list) == "table" and next(list) ~= nil
end

--[[
	What the chosen mode does, for the line under the mode buttons. In
	RARE+ / EVERYTHING a tap turns what you see into your list; with a
	custom list saved (`hasList`) that replaces it, so the line says so.
]]
function IronBoxView.modeText(mode: KeepMode, hasList: boolean?): string
	if mode == "List" then
		return "Your own list. Unset ores follow the Rare+ rule; RESET clears it."
	end
	local rule = if mode == "All" then "Keeps every clean ore." else `Keeps {MachineData.Keep.RareFrom} ore and better.`
	return rule .. (if hasList then " Tapping an ore replaces MY LIST." else " Tap an ore to make your own list.")
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

---------------------------------------------------------------- the Pop look (the kit pieces this window needs)

-- the header band: the keep list's steel blue (LightSkin.BandRoles TerraForgeIronBox = "Settings")
IronBoxView.Paint = {
	Top = Color3.fromRGB(150, 176, 226),
	Bottom = Color3.fromRGB(62, 84, 134),
	Edge = Color3.fromRGB(14, 14, 18),
} :: Pop.Paint
-- each mode's tab paint (the picked tab is painted, the others slate: Pop.selectTab)
IronBoxView.ModePaints = { RarePlus = "Purple", List = "Yellow", All = "Green" } :: { [string]: string }

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(214, 220, 232) -- quieter white text (info, hints, SEND ON)
local CHIP_CORNER = 10
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
	body and the bright header band (shine stripes, studs); both sit under
	everything else (ZIndex 0). setBand sizes them for a band `band` tall.
]]
local function chrome(panel: Frame, paint: string | Pop.Paint)
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
		ClipsDescendants = true,
		ZIndex = 0,
	}, panel)
	Pop.face(head, paint, 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = 3
	Pop.studs(head, 4, 0.35, 40, 0)
	if not PopTheme.round() then -- (the round look's band has no shine over its top half)
		UIKit.new("Frame", {
			Name = "Shine",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0.42, 0),
			ZIndex = 0,
		}, head)
	end
	for i, s in { { 0.62, 46 }, { 0.7, 22 }, { 0.8, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = 0,
		}, head)
	end
end

-- Sizes the header band (`band` units tall, the frame included) and the body under it.
local function setBand(panel: Frame, band: number)
	local head = panel:FindFirstChild("Header") :: Frame?
	local body = panel:FindFirstChild("Body") :: Frame?
	if head and body then
		head.Size = UDim2.new(1, -8, 0, band - 8)
		body.Position = UDim2.fromOffset(4, band)
		body.Size = UDim2.new(1, -8, 1, -(band + 4))
	end
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
	shade.TextXAlignment = title.TextXAlignment
	shade.Visible = title.Visible
	shade.ZIndex = math.max(1, title.ZIndex - 1)
end

-- A chip's paint: its ore's rarity (Pop.rarityPaint).
function IronBoxView.chipPaint(oreId: string): Pop.Paint
	local ore = OreData.ById[oreId]
	return Pop.rarityPaint(if ore then ore.Rarity else nil)
end

---------------------------------------------------------------- building

local function modeButton(parent: Instance, mode: string, order: number): TextButton
	local button = popButton(parent, IronBoxView.ModeLabels[mode], "Slate", {
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
	gui:SetAttribute("Pop", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, 500),
	})
	chrome(panel, IronBoxView.Paint)
	local title = UIKit.label(panel, IronBoxView.Title, 28, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, 8),
		Size = UDim2.new(1, -(PAD * 2 + 80), 0, TITLE_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 3,
	})
	ink(title)
	local info = UIKit.label(panel, IronBoxView.Info, 16, {
		Name = "Info",
		Position = UDim2.fromOffset(PAD, 8 + TITLE_H + 11),
		Size = UDim2.new(1, -PAD * 2, 0, INFO_H - 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
	})
	ink(info, SOFT)
	local close = popButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 14),
		Size = UDim2.fromOffset(LAYOUTS.Normal.Close, LAYOUTS.Normal.Close),
		TextSize = 32,
		FontFace = PopTheme.Heavy,
	})

	-- mode tabs in one row
	local modesRow = UIKit.new("Frame", {
		Name = "Modes",
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, panel)
	UIKit.list(modesRow, Enum.FillDirection.Horizontal, GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})
	local modes: { [string]: TextButton } = {}
	for i, mode in MachineData.Keep.Modes do
		modes[mode] = modeButton(modesRow, mode, i)
	end
	local modeText = UIKit.label(panel, "", 15, {
		Name = "ModeText",
		TextWrapped = true,
		ZIndex = 3,
	})
	ink(modeText, SOFT)

	-- the scroll bar's groove (shown when there are more chips than rows),
	-- behind the list so the bar itself runs in it
	local track = UIKit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
	}, panel)
	UIKit.corner(track, BAR // 2)
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		ScrollBarThickness = BAR,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
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
	UIKit.new(
		"UIPadding",
		{ PaddingTop = UDim.new(0, LIST_PAD), PaddingBottom = UDim.new(0, LIST_PAD), PaddingLeft = UDim.new(0, 2) },
		list
	)
	local empty = UIKit.label(panel, IronBoxView.Empty, 19, {
		Name = "Empty",
		Visible = false,
		ZIndex = 3,
	})
	ink(empty, SOFT)

	local presets = UIKit.new("Frame", { Name = "Presets", BackgroundTransparency = 1, ZIndex = 2 }, panel)
	UIKit.list(presets, Enum.FillDirection.Horizontal, GAP * 2, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local labels = IronBoxView.PresetLabels
	local allKeep = popButton(presets, labels.Keep, "Green", { Name = "AllKeep", LayoutOrder = 1, TextSize = 19 })
	local allSend = popButton(presets, labels.Send, "Orange", { Name = "AllSend", LayoutOrder = 2, TextSize = 19 })
	local reset = popButton(presets, labels.Reset, "Red", {
		Name = "Reset",
		LayoutOrder = 3,
		TextSize = 19,
		Visible = false,
	})

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -6),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		ZIndex = 3,
	})
	ink(hint, SOFT)
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
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
			Size = UDim2.fromOffset(90, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			ZIndex = 3,
		})
		ink(label, SOFT)
		return label
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
		Track = track,
		Grid = grid,
		Empty = empty,
		Presets = presets,
		AllKeep = allKeep,
		AllSend = allSend,
		Reset = reset,
		Hint = hint,
		PadHint = padHint,
		PadA = padA,
		PadAText = padAText,
		PadB = padB,
		Chips = {},
		Compact = false,
		Mode = MachineData.Keep.Default,
		Rows = LAYOUTS.Normal.MaxRows,
		Columns = COLUMNS,
		Count = 0,
	}
	IronBoxView.layout(refs, false, 1600, 720)
	IronBoxView.setMode(refs, MachineData.Keep.Default)
	-- (the light UI: an open window hides the touch thumbstick)
	if UIConfig.lightUI() then
		TouchControls.follow(gui)
	end
	return refs
end

-- The scroll groove shows while the chips need more rows than fit.
local function syncTrack(refs: Refs)
	refs.Track.Visible = refs.Count > refs.Rows * refs.Columns
end

-- The panel's width for this many chip columns.
local function panelWidth(l: typeof(LAYOUTS.Normal), columns: number): number
	return columns * l.ChipW + (columns - 1) * GAP + SCROLLBAR + 4 + PAD * 2
end

-- The most chip columns (COLUMNS..MIN_COLUMNS) whose panel fits `room`.
local function columnsFor(l: typeof(LAYOUTS.Normal), room: number): number?
	for columns = COLUMNS, MIN_COLUMNS, -1 do
		if panelWidth(l, columns) <= room then
			return columns
		end
	end
	return nil
end

--[[
	Chip columns and panel width for a screen `maxWidth` design units wide.
	Phones: as many columns as fit beside the HUD coins (the panel sits on
	the right); when not even MIN_COLUMNS do (portrait), the whole width.
	The panel is always exactly as wide as its chip grid, so no column is
	ever cut off (the list only scrolls vertically).
]]
function IronBoxView.fitColumns(compact: boolean, maxWidth: number): (number, number)
	local l = layoutOf(compact)
	local beside = if compact then columnsFor(l, maxWidth - EDGE - HUD_CLEAR) else nil
	local columns: number = beside or columnsFor(l, maxWidth - (if compact then EDGE * 2 else 16)) or MIN_COLUMNS
	return columns, panelWidth(l, columns)
end

-- Places a chip's parts: the words on the left, the big picture on the
-- right (cut a little by the card's edge, the words may run over it).
local function placeChip(chip: Chip, l: typeof(LAYOUTS.Normal))
	local h = l.ChipH
	local pic = h + 2
	chip.Swatch.Position = UDim2.new(1, 6, 0.5, 0)
	chip.Swatch.Size = UDim2.fromOffset(pic, pic)
	local x = 10
	local right = 16 + math.floor(pic * 0.3)
	chip.Name.Position = UDim2.new(0, x, 0, 5)
	chip.Name.Size = UDim2.new(1, -(x + right), 0.52, -3)
	chip.Name.TextSize = l.Name
	chip.State.Position = UDim2.new(0, x, 0.52, 0)
	chip.State.Size = UDim2.new(1, -(x + right), 0.44, -4)
	chip.State.TextSize = l.State
end

--[[
	Sizes and places everything for a layout (compact = phones) inside
	`maxWidth` x `maxHeight` design units (the screen divided by the UI
	scale): chip columns that fit the width (fitColumns), as many chip rows
	as fit (1..MaxRows), the rest scrolls. The header band holds the title
	and the X (phones: the mode tabs too, beside the X); the info line, the
	tabs and the chips sit on the body.
]]
function IronBoxView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local l = layoutOf(compact)
	local columns, width = IronBoxView.fitColumns(compact, maxWidth)
	refs.Columns = columns
	refs.Grid.FillDirectionMaxCells = columns
	local info = if compact then 0 else INFO_H
	refs.Info.Visible = not compact
	local top = 8 + TITLE_H + info
	-- the mode buttons sit under the close button, or (no info line) beside it
	local modesY = top + l.ModesGap
	local besideClose = modesY < 14 + l.Close + 4
	local modesW = width - PAD * 2 - (if besideClose then l.Close + GAP else 0)
	local modeTextY = modesY + l.ModeH + 6
	local listY = modeTextY + MODE_TEXT_H + 8
	local below = l.PresetGap + l.PresetH + l.HintGap + HINT_H
	local rowH = l.ChipH + GAP
	local fit = math.floor((maxHeight - 24 - listY - below + GAP) / rowH)
	local rows = math.clamp(fit, 1, l.MaxRows)
	refs.Rows = rows
	-- exactly `rows` rows (no sliver of the next one) plus the padding
	local listH = rows * rowH - GAP + LIST_PAD * 2
	local height = listY + listH + below
	refs.Panel.Size = UDim2.fromOffset(width, height)
	-- phones: on the right (thumb side), clear of the HUD coins top left
	refs.Panel.AnchorPoint = if compact then Vector2.new(1, 0.5) else Vector2.new(0.5, 0.5)
	refs.Panel.Position = if compact then UDim2.new(1, -EDGE, 0.5, 0) else UDim2.fromScale(0.5, 0.5)
	-- the band: the title and the X (beside the X, the tabs too)
	local band = if besideClose then modesY + l.ModeH + 6 else 8 + TITLE_H + 10
	setBand(refs.Panel, band)
	refs.Title.TextSize = l.Title + 4
	syncShadow(refs.Title)
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	closeHolder.Position = UDim2.new(1, -PAD, 0, if besideClose then 14 else math.floor((band - l.Close) / 2))
	refs.Close.TextSize = math.floor(l.Close * 0.62)
	refs.Info.Size = UDim2.new(1, -PAD * 2, 0, INFO_H - 8)
	local modesRow = (refs.Modes.RarePlus.Parent :: Frame).Parent :: Frame
	modesRow.Position = UDim2.fromOffset(PAD, modesY)
	modesRow.Size = UDim2.fromOffset(modesW, l.ModeH)
	local modeW = math.floor((modesW - GAP * 2) / 3)
	for _, button in refs.Modes do
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(modeW, l.ModeH - 6)
		-- "EVERYTHING" still fits a narrow button
		button.TextSize = math.min(l.ModeText + 2, math.floor(modeW / 6.2))
	end
	refs.ModeText.Position = UDim2.fromOffset(PAD, modeTextY)
	refs.ModeText.Size = UDim2.new(1, -PAD * 2, 0, MODE_TEXT_H)
	-- PAD on both sides: the scroll bar runs inside the panel, by the chips
	refs.List.Position = UDim2.fromOffset(PAD, listY)
	refs.List.Size = UDim2.new(1, -PAD * 2, 0, listH)
	refs.Track.Position = UDim2.new(1, -PAD - BAR, 0, listY + 2)
	refs.Track.Size = UDim2.fromOffset(BAR, listH - 4)
	refs.Grid.CellSize = UDim2.fromOffset(l.ChipW, l.ChipH)
	refs.Empty.Position = UDim2.fromOffset(PAD * 2, listY)
	refs.Empty.Size = UDim2.new(1, -PAD * 4, 0, listH)
	refs.Presets.Position = UDim2.fromOffset(PAD, listY + listH + l.PresetGap)
	refs.Presets.Size = UDim2.new(1, -PAD * 2, 0, l.PresetH)
	-- the two presets and RESET in one row (narrower on a narrow panel)
	local rowW = width - PAD * 2
	local squeeze = math.min(1, (rowW - GAP * 4) / (l.PresetW * 2 + l.ResetW))
	for _, button in { refs.AllKeep, refs.AllSend, refs.Reset } do
		local holder = button.Parent :: Frame
		local w = if button == refs.Reset then l.ResetW else l.PresetW
		holder.Size = UDim2.fromOffset(math.floor(w * squeeze), l.PresetH - 6)
		button.TextSize = math.floor(l.PresetText * math.max(0.7, squeeze))
	end
	for _, chip in refs.Chips do
		placeChip(chip, l)
	end
	syncTrack(refs)
end

-- A chip's live 3D ore picture (built once per chip: its ore never changes).
local function fillPicture(swatch: Frame, oreId: string)
	if swatch:FindFirstChild("Picture") then
		return
	end
	local name = "item_Clean_" .. oreId
	local ok, model = pcall(ItemBuilder.display, { K = "Clean", O = oreId, G = "Pristine" }, CFrame.new(), name)
	Pop.model(swatch, name, 10, if ok then model else nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.1, 1.1),
		ZIndex = 3,
	}, Vector3.new(-0.5, 0.55, -1))
end

local function newChip(refs: Refs, oreId: string): Chip
	-- a painted Pop card in the ore's rarity colour
	local button = UIKit.new("TextButton", {
		Name = "Chip",
		AutoButtonColor = true,
		BorderSizePixel = 0,
		ClipsDescendants = true, -- (the light burst behind the picture)
		Text = "",
		ZIndex = 2,
	}, refs.List)
	button:SetAttribute("Ore", oreId)
	Pop.face(button, IronBoxView.chipPaint(oreId), CHIP_CORNER, false)
	local stroke = button:FindFirstChild("Border") :: UIStroke
	Pop.studs(button, CHIP_CORNER, 0.5, 40, 1)
	local rim = button:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 4
	end
	-- the picture: a light burst and a soft glow behind the ore's live 3D look
	local swatch = UIKit.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, button)
	Pop.rays(swatch, UDim2.fromScale(0.5, 0.5), 8, 72, 0.45, 1)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 2,
	}, swatch)
	UIKit.corner(glow, 999)
	fillPicture(swatch, oreId)
	-- SEND ON: a shade over the paint and the picture (the words stay bright)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 3,
	}, button)
	UIKit.corner(shade, CHIP_CORNER)
	local l = layoutOf(refs.Compact)
	local name = UIKit.label(button, "", l.Name, {
		Name = "OreName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	ink(name)
	local state = UIKit.label(button, "", l.State, {
		Name = "State",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	ink(state)
	local chip: Chip = { Ore = oreId, Button = button, Swatch = swatch, Name = name, State = state, Stroke = stroke }
	placeChip(chip, l)
	refs.Chips[oreId] = chip
	return chip
end

-- One chip's look: kept = bright in its rarity paint, "KEEP" and its podium
-- income in money green; sent on = shaded, "SEND ON" in soft white.
local function paintChip(chip: Chip, entry: Entry, index: number)
	chip.Button.LayoutOrder = index
	chip.Name.Text = entry.Name
	local shade = chip.Button:FindFirstChild("Shade") :: Frame?
	if shade then
		shade.Visible = not entry.Keep
	end
	if entry.Keep then
		chip.State.Text = "KEEP · " .. Format.perSecond(entry.Income)
		chip.State.TextColor3 = PopTheme.Money
		chip.Name.TextColor3 = PopTheme.Ink
	else
		chip.State.Text = "SEND ON"
		chip.State.TextColor3 = SOFT
		chip.Name.TextColor3 = SOFT
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
	refs.Count = #list
	syncTrack(refs)
	return created
end

-- The chosen mode: its tab painted (the others slate, like Pop.selectTab)
-- and the line under the tabs (`hasList`: a custom list is saved, see modeText).
function IronBoxView.setMode(refs: Refs, mode: KeepMode, hasList: boolean?)
	refs.Mode = mode
	for id, button in refs.Modes do
		local on = id == mode
		paintButton(button, if on then IronBoxView.ModePaints[id] or "Blue" else "Slate")
		button.TextTransparency = if on then 0 else 0.25
		button:SetAttribute("Selected", on)
	end
	refs.ModeText.Text = IronBoxView.modeText(mode, hasList)
	-- RESET (back to the Rare+ rule) only means something for your own list
	local resetHolder = refs.Reset.Parent :: Frame
	resetHolder.Visible = mode == "List"
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
