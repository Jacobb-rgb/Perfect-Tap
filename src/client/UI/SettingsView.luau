--[[
	The SETTINGS panel (pure builder + pure helpers; SettingsController fills
	it in). One MenuPanel in the Pop look (owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style") with a clean row per setting
	(SettingsConfig) in a dark studded well:

	  Music           [-] [=====o-----] [+]  60%   volume slider
	  Sounds          [-] [=======o---] [+]  80%   volume slider
	  Camera shake                       [ ON ]    toggle (green / grey)
	  Gamepad rumble                     [ OFF ]   toggle
	  Reduce motion                      [ OFF ]   toggle (UI/Motion; while AnimConfig.UIMotion
	                                               is off it calms only the golem followers, and
	                                               its note says so)

	Each row: a big white word, a small note under it; the sliders are a
	dark well with a glossy green fill and a white knob; - / + and ON / OFF
	are painted Pop buttons. A slider follows a click or a drag on its bar
	(mouse and touch); the - / + buttons move it one SettingsConfig.Step
	(and are what a gamepad selects; it starts on the Sounds row). A row can
	be hidden (setShown: Music until a track plays through the music group,
	Gamepad rumble without a gamepad); the panel closes up around it.
	Designed for 720 design units of height; the compact layout (phones,
	TVs) makes every button at least 44 pt (SettingsView.touchTargets for
	the tests).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimConfig = require(Shared.Config.AnimConfig)
local SettingsConfig = require(Shared.Config.SettingsConfig)
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local MenuPanel = require(script.Parent.MenuPanel)

local SettingsView = {}

export type RowSpec = { Id: string, Kind: "Volume" | "Toggle", Icon: string, Title: string, Note: string }

export type VolumeRow = {
	Id: string,
	Frame: Frame,
	Title: TextLabel,
	Note: TextLabel,
	Icon: TextLabel,
	Minus: TextButton,
	Plus: TextButton,
	Track: TextButton,
	Fill: Frame,
	Knob: Frame,
	Value: TextLabel,
}

export type ToggleRow = {
	Id: string,
	Frame: Frame,
	Title: TextLabel,
	Note: TextLabel,
	Icon: TextLabel,
	Button: TextButton, -- its Text is the state ("ON" / "OFF"); the painted word shows it
}

export type Refs = {
	Frame: MenuPanel.Refs,
	Gui: ScreenGui,
	List: Frame,
	Volumes: { [string]: VolumeRow },
	Toggles: { [string]: ToggleRow },
	Order: { string },
	Hidden: { [string]: boolean },
	Compact: boolean,
}

SettingsView.Rows = {
	-- (no music plays yet: the volume is saved for the soundtrack)
	{ Id = "Music", Kind = "Volume", Icon = "", Title = "Music", Note = "The soundtrack" },
	{ Id = "Sfx", Kind = "Volume", Icon = "", Title = "Sounds", Note = "Every game sound" },
	{ Id = "Shake", Kind = "Toggle", Icon = "", Title = "Camera shake", Note = "When rocks crack" },
	{ Id = "Rumble", Kind = "Toggle", Icon = "", Title = "Gamepad rumble", Note = "Vibration while you blast" },
	-- (the UI motion switched off: the menus never pop, so it calms what it reaches now, the golems
	-- running after you: smaller steps, no lean, no hops; the emotes stay as picked)
	{
		Id = "ReduceMotion",
		Kind = "Toggle",
		Icon = "",
		Title = "Reduce motion",
		Note = if AnimConfig.UIMotion then "Calm menus: no pops or bounces" else "Calmer golems: no hops or lean",
	},
} :: { RowSpec }

type Metrics = { Width: number, Row: number, Button: number, Toggle: number, Title: number, Note: number, Value: number }

SettingsView.Metrics = {
	Normal = { Width = 660, Row = 74, Button = 50, Toggle = 132, Title = 26, Note = 15, Value = 24 },
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = { Width = 760, Row = 90, Button = 72, Toggle = 150, Title = 28, Note = 16, Value = 26 },
} :: { [string]: Metrics }

SettingsView.Gap = 8 -- between the rows
SettingsView.WellPad = 8 -- the well's inside margin

SettingsView.OnPaint = "Green"
SettingsView.OffPaint = PopTheme.Gray
SettingsView.StepPaint = "Blue" -- the - / + buttons
SettingsView.FillPaint = "Green" -- a slider's fill
-- a row's face: a slate a little lighter than the well
SettingsView.RowPaint = {
	Top = Color3.fromRGB(84, 90, 108),
	Bottom = Color3.fromRGB(56, 60, 74),
	Edge = PopTheme.Outline,
} :: Pop.Paint
SettingsView.NoteColor = Color3.fromRGB(196, 206, 226)
SettingsView.ValueColor = Color3.fromRGB(255, 232, 110)

local function metrics(compact: boolean): Metrics
	return if compact then SettingsView.Metrics.Compact else SettingsView.Metrics.Normal
end

-- The panel height a layout needs (header, `rows` rows (default: all),
-- the well's margins, footer; padMode = the gamepad footer shows).
function SettingsView.height(compact: boolean, padMode: boolean?, rows: number?): number
	local m = metrics(compact)
	local mm = if compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal
	local footer = if padMode then math.max(mm.Footer, MenuPanel.PadFooter) else mm.Footer
	local count = rows or #SettingsView.Rows
	return mm.Header + 6 + SettingsView.WellPad * 2 + count * m.Row + (count - 1) * SettingsView.Gap + footer + 8
end

-- The ids of the rows that show, in order.
function SettingsView.shown(refs: Refs): { string }
	local list = {}
	for _, id in refs.Order do
		if not refs.Hidden[id] then
			table.insert(list, id)
		end
	end
	return list
end

-- Shows or hides a row (call layout afterwards: the panel closes up).
-- Returns whether it changed.
function SettingsView.setShown(refs: Refs, id: string, shown: boolean): boolean
	local row = refs.Volumes[id] or refs.Toggles[id]
	if not row or (refs.Hidden[id] ~= true) == shown then
		return false
	end
	if shown then
		refs.Hidden[id] = nil
	else
		refs.Hidden[id] = true
	end
	row.Frame.Visible = shown
	return true
end

-- A slider value (0..1) from a point's x on a bar that starts at `left` and is `width` wide.
function SettingsView.fraction(x: number, left: number, width: number): number
	if width <= 0 or x ~= x then
		return 0
	end
	return math.clamp((x - left) / width, 0, 1)
end

-- A painted Pop button in a holder frame (MenuPanel.holderOf: the layout
-- sizes the holder, the touch tests read it).
local function button(parent: Instance, name: string, text: string, paint: string | Pop.Paint): TextButton
	local holder = UIKit.new("Frame", {
		Name = name .. "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(60, 50),
		ZIndex = 4,
	}, parent)
	local made = Pop.button(holder, text, paint, Vector2.new(60, 50), {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	})
	return made
end

-- A button's painted word (Pop.button's "Label").
local function wordOf(b: TextButton): TextLabel
	return b:FindFirstChild("Label") :: TextLabel
end

local function rowFrame(parent: Instance, spec: RowSpec, order: number): (Frame, TextLabel, TextLabel, TextLabel)
	local frame = UIKit.new("Frame", {
		Name = "Row" .. spec.Id,
		LayoutOrder = order,
		ZIndex = 3,
	}, parent)
	Pop.face(frame, SettingsView.RowPaint, 10, false)
	Pop.studs(frame, 10, 0.6, 36, 3)
	local icon = UIKit.new("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Text = spec.Icon,
		Visible = false, -- (no emoji: the word says it)
	}, frame)
	local title = Pop.text(frame, spec.Title, 26, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	local note = Pop.text(frame, spec.Note, 15, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SettingsView.NoteColor,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	return frame, icon, title, note
end

local function newVolume(refs: Refs, spec: RowSpec, order: number)
	local frame, icon, title, note = rowFrame(refs.List, spec, order)
	local minus = button(frame, "Minus", "-", SettingsView.StepPaint)
	local plus = button(frame, "Plus", "+", SettingsView.StepPaint)
	-- the - and + drawn as white bars with a black edge (a font's "-" sits
	-- small and high): the black bars under the white ones, so a + has no
	-- edge across its middle
	local function layer(b: TextButton, name: string, rotation: number, color: Color3, grow: number, z: number)
		local made = UIKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rotation,
			Size = UDim2.new(0.46, grow, 0.13, grow),
			ZIndex = z,
		}, b)
		UIKit.corner(made, 4)
	end
	local function stroke(b: TextButton, name: string, rotation: number)
		layer(b, name .. "Edge", rotation, PopTheme.Outline, 5, 5)
		layer(b, name, rotation, Color3.new(1, 1, 1), 0, 6)
	end
	for _, b in { minus, plus } do
		wordOf(b).Visible = false
		stroke(b, "Dash", 0)
	end
	stroke(plus, "Stem", 90)
	local track = UIKit.new("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Selectable = false,
		ZIndex = 4,
	}, frame)
	-- the slider: a dark well, a glossy painted fill, a white knob
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 4,
	}, track)
	UIKit.corner(bar, 10)
	Pop.border(bar, 3)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = 4,
	}, bar)
	Pop.face(fill, SettingsView.FillPaint, 10, true, false)
	local fillBorder = fill:FindFirstChild("Border")
	if fillBorder then
		fillBorder:Destroy()
	end
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 6,
	}, bar)
	Pop.face(knob, { Top = Color3.new(1, 1, 1), Bottom = Color3.fromRGB(196, 204, 222), Edge = PopTheme.Outline }, 16, true, false)
	local value = Pop.text(frame, "50%", 24, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		FontFace = PopTheme.Heavy,
		TextColor3 = SettingsView.ValueColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	})
	refs.Volumes[spec.Id] = {
		Id = spec.Id,
		Frame = frame,
		Title = title,
		Note = note,
		Icon = icon,
		Minus = minus,
		Plus = plus,
		Track = track,
		Fill = fill,
		Knob = knob,
		Value = value,
	}
end

local function newToggle(refs: Refs, spec: RowSpec, order: number)
	local frame, icon, title, note = rowFrame(refs.List, spec, order)
	local toggle = button(frame, "Toggle", "ON", SettingsView.OnPaint)
	-- (the state word as the button's own Text, unseen: the painted word shows it)
	toggle.Text = "ON"
	toggle.TextTransparency = 1
	refs.Toggles[spec.Id] = { Id = spec.Id, Frame = frame, Title = title, Note = note, Icon = icon, Button = toggle }
end

function SettingsView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local frame = MenuPanel.build("TerraForgeSettings", "SETTINGS", "Saved to your profile: they follow you to every device.", 17, true)
	-- the rows in a dark studded well
	local well = Pop.well(frame.Body, {
		Name = "Well",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 1, -6),
	})
	local pad = SettingsView.WellPad
	local list = UIKit.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.new(1, -2 * pad, 1, -2 * pad),
		ZIndex = 3,
	}, well)
	UIKit.list(list, Enum.FillDirection.Vertical, SettingsView.Gap)
	local refs: Refs = {
		Frame = frame,
		Gui = frame.Gui,
		List = list,
		Volumes = {},
		Toggles = {},
		Order = {},
		Hidden = {},
		Compact = isCompact,
	}
	for i, spec in SettingsView.Rows do
		table.insert(refs.Order, spec.Id)
		if spec.Kind == "Volume" then
			newVolume(refs, spec, i)
		else
			newToggle(refs, spec, i)
		end
	end
	SettingsView.layout(refs, isCompact, math.huge, math.huge)
	SettingsView.set(refs, SettingsConfig.sanitize(nil))
	return refs
end

-- Fits the panel into the room it gets (design units).
function SettingsView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local rows = math.max(1, #SettingsView.shown(refs))
	local body = MenuPanel.layout(refs.Frame, compact, m.Width, SettingsView.height(compact, refs.Frame.PadMode, rows), maxWidth, maxHeight)
	local rowW = body.X - 2 * SettingsView.WellPad
	local controlsW = math.min(math.floor(rowW * 0.56), 420)
	local textX = 18
	local textW = rowW - controlsW - textX - 16
	-- a short phone screen: rows share the height they get
	local room = body.Y - 6 - 2 * SettingsView.WellPad
	local rowH = math.max(m.Button + 8, math.min(m.Row, math.floor((room - (rows - 1) * SettingsView.Gap) / rows)))
	local function placeText(title: TextLabel, note: TextLabel)
		title.TextSize = m.Title
		note.TextSize = m.Note
		title.Position = UDim2.new(0, textX, 0.5, -(m.Title + 3))
		title.Size = UDim2.fromOffset(textW, m.Title + 4)
		note.Position = UDim2.new(0, textX + 1, 0.5, 3)
		note.Size = UDim2.fromOffset(textW, m.Note + 4)
	end
	local stepWord = if compact then 44 else 34
	for _, row in refs.Volumes do
		row.Frame.Size = UDim2.new(1, 0, 0, rowH)
		placeText(row.Title, row.Note)
		local valueW = if compact then 76 else 68
		local left = rowW - controlsW
		local minus = MenuPanel.holderOf(row.Minus)
		minus.AnchorPoint = Vector2.new(0, 0.5)
		minus.Size = UDim2.fromOffset(m.Button, m.Button)
		minus.Position = UDim2.new(0, left, 0.5, 0)
		local plus = MenuPanel.holderOf(row.Plus)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Size = UDim2.fromOffset(m.Button, m.Button)
		plus.Position = UDim2.new(1, -(valueW + 12 + m.Button), 0.5, 0)
		wordOf(row.Minus).TextSize = stepWord
		wordOf(row.Plus).TextSize = stepWord
		local trackLeft = left + m.Button + 16
		local trackW = (rowW - (valueW + 12 + m.Button) - 16) - trackLeft
		row.Track.AnchorPoint = Vector2.new(0, 0.5)
		row.Track.Position = UDim2.new(0, trackLeft, 0.5, 0)
		row.Track.Size = UDim2.fromOffset(math.max(40, trackW), m.Button)
		local bar = row.Fill.Parent :: Frame
		bar.Size = UDim2.new(1, 0, 0, if compact then 24 else 20)
		local knob = if compact then 38 else 32
		row.Knob.Size = UDim2.fromOffset(knob, knob)
		row.Value.TextSize = m.Value
		row.Value.Position = UDim2.new(1, -12, 0.5, 0)
		row.Value.Size = UDim2.fromOffset(valueW, 30)
	end
	for _, row in refs.Toggles do
		row.Frame.Size = UDim2.new(1, 0, 0, rowH)
		placeText(row.Title, row.Note)
		local holder = MenuPanel.holderOf(row.Button)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Size = UDim2.fromOffset(m.Toggle, m.Button)
		holder.Position = UDim2.new(1, -12, 0.5, 0)
		row.Button.TextSize = if compact then 26 else 24
		wordOf(row.Button).TextSize = if compact then 32 else 28
	end
end

-- Shows a settings record.
function SettingsView.set(refs: Refs, settings: SettingsConfig.Settings)
	local values = settings :: { [string]: any }
	for id, row in refs.Volumes do
		local v = math.clamp(tonumber(values[id]) or 0, 0, 1)
		row.Fill.Size = UDim2.fromScale(v, 1)
		row.Fill.Visible = v > 0.001
		row.Knob.Position = UDim2.fromScale(v, 0.5)
		row.Value.Text = SettingsConfig.percent(v)
		row.Value.TextColor3 = if v > 0 then SettingsView.ValueColor else SettingsView.NoteColor
	end
	for id, row in refs.Toggles do
		local on = values[id] == true
		local word = if on then "ON" else "OFF"
		row.Button.Text = word
		wordOf(row.Button).Text = word
		Pop.repaint(row.Button, if on then SettingsView.OnPaint else SettingsView.OffPaint)
	end
end

-- The first button a gamepad selects: the Sounds row (the one most
-- players come for; the first shown row when it is hidden).
function SettingsView.firstButton(refs: Refs): TextButton
	if not refs.Hidden.Sfx then
		return refs.Volumes.Sfx.Minus
	end
	for _, id in SettingsView.shown(refs) do
		local volume = refs.Volumes[id]
		if volume then
			return volume.Minus
		end
		local toggle = refs.Toggles[id]
		if toggle then
			return toggle.Button
		end
	end
	return refs.Frame.Close
end

-- Every tappable thing that shows (for the touch-size tests).
function SettingsView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { MenuPanel.holderOf(refs.Frame.Close) }
	for _, id in SettingsView.shown(refs) do
		local volume = refs.Volumes[id]
		if volume then
			table.insert(list, MenuPanel.holderOf(volume.Minus))
			table.insert(list, MenuPanel.holderOf(volume.Plus))
			table.insert(list, volume.Track)
		end
		local toggle = refs.Toggles[id]
		if toggle then
			table.insert(list, MenuPanel.holderOf(toggle.Button))
		end
	end
	return list
end

return SettingsView
