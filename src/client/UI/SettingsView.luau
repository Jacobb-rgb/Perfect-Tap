--[[
	The SETTINGS panel (pure builder + pure helpers; SettingsController fills
	it in). One MenuPanel with a row per setting (SettingsConfig):

	  Music           - [=====o-----] +  60%   volume slider
	  Sounds          - [=======o---] +  80%   volume slider
	  Camera shake    [ ON ]                   toggle
	  Gamepad rumble  [ ON ]                   toggle

	A slider follows a click or a drag on its bar (mouse and touch); the
	- / + buttons move it one SettingsConfig.Step (and are what a gamepad
	selects). Designed for 720 design units of height; the compact layout
	(phones, TVs) makes every button at least 44 pt (SettingsView.touchTargets
	for the tests).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
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
	Button: TextButton,
}

export type Refs = {
	Frame: MenuPanel.Refs,
	Gui: ScreenGui,
	List: Frame,
	Volumes: { [string]: VolumeRow },
	Toggles: { [string]: ToggleRow },
	Order: { string },
	Compact: boolean,
}

SettingsView.Rows = {
	-- (no music plays yet: the volume is saved for the soundtrack)
	{ Id = "Music", Kind = "Volume", Icon = "🎵", Title = "Music", Note = "Soundtrack coming soon" },
	{ Id = "Sfx", Kind = "Volume", Icon = "🔊", Title = "Sounds", Note = "Every game sound" },
	{ Id = "Shake", Kind = "Toggle", Icon = "📷", Title = "Camera shake", Note = "When rocks crack" },
	{ Id = "Rumble", Kind = "Toggle", Icon = "🎮", Title = "Gamepad rumble", Note = "Vibration while you blast" },
} :: { RowSpec }

type Metrics = { Width: number, Row: number, Button: number, Toggle: number, Title: number, Note: number, Value: number }

SettingsView.Metrics = {
	Normal = { Width = 660, Row = 74, Button = 50, Toggle = 132, Title = 22, Note = 14, Value = 22 },
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = { Width = 760, Row = 90, Button = 72, Toggle = 150, Title = 24, Note = 15, Value = 24 },
} :: { [string]: Metrics }

SettingsView.OnColor = Theme.Good
SettingsView.OnDark = Theme.GoodDark
SettingsView.OffColor = Color3.fromRGB(120, 108, 100)
SettingsView.OffDark = Color3.fromRGB(70, 62, 58)

local function metrics(compact: boolean): Metrics
	return if compact then SettingsView.Metrics.Compact else SettingsView.Metrics.Normal
end

-- The panel height a layout needs (header, rows, footer; padMode = the
-- gamepad footer shows).
function SettingsView.height(compact: boolean, padMode: boolean?): number
	local m = metrics(compact)
	local mm = if compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal
	local footer = if padMode then math.max(mm.Footer, MenuPanel.PadFooter) else mm.Footer
	return mm.Header + #SettingsView.Rows * (m.Row + 10) + footer + 6
end

-- A slider value (0..1) from a point's x on a bar that starts at `left` and is `width` wide.
function SettingsView.fraction(x: number, left: number, width: number): number
	if width <= 0 or x ~= x then
		return 0
	end
	return math.clamp((x - left) / width, 0, 1)
end

local function rowFrame(parent: Instance, spec: RowSpec, order: number): (Frame, TextLabel, TextLabel, TextLabel)
	local frame = UIKit.new("Frame", {
		Name = "Row" .. spec.Id,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2)
	local icon = UIKit.label(frame, spec.Icon, 30, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		TextWrapped = false,
	})
	local title = UIKit.label(frame, spec.Title, 22, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local note = UIKit.label(frame, spec.Note, 14, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return frame, icon, title, note
end

local function newVolume(refs: Refs, spec: RowSpec, order: number)
	local frame, icon, title, note = rowFrame(refs.List, spec, order)
	local minus = UIKit.button(frame, "-", Theme.Accent, Theme.AccentDark, { Name = "Minus", TextSize = 30 })
	local plus = UIKit.button(frame, "+", Theme.Accent, Theme.AccentDark, { Name = "Plus", TextSize = 30 })
	local track = UIKit.new("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Selectable = false,
	}, frame)
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, track)
	UIKit.corner(bar, 7)
	UIKit.stroke(bar, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, bar)
	UIKit.corner(fill, 7)
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, bar)
	UIKit.corner(knob, 14)
	UIKit.stroke(knob, 3)
	local value = UIKit.label(frame, "50%", 22, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
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
	local button = UIKit.button(frame, "ON", SettingsView.OnColor, SettingsView.OnDark, { Name = "Toggle", TextSize = 24 })
	refs.Toggles[spec.Id] = { Id = spec.Id, Frame = frame, Title = title, Note = note, Icon = icon, Button = button }
end

function SettingsView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local frame = MenuPanel.build("TerraForgeSettings", "SETTINGS", "Saved to your profile: they follow you to every device.", 17)
	local list = UIKit.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, frame.Body)
	UIKit.list(list, Enum.FillDirection.Vertical, 10)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4) }, list)
	local refs: Refs = {
		Frame = frame,
		Gui = frame.Gui,
		List = list,
		Volumes = {},
		Toggles = {},
		Order = {},
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
	local body = MenuPanel.layout(refs.Frame, compact, m.Width, SettingsView.height(compact, refs.Frame.PadMode), maxWidth, maxHeight)
	local rowW = body.X
	local controlsW = math.min(math.floor(rowW * 0.56), 420)
	local textX = 62
	local textW = rowW - controlsW - textX - 16
	-- a short phone screen: rows share the height they get
	local rows = #SettingsView.Rows
	local rowH = math.max(m.Button + 8, math.min(m.Row, math.floor((body.Y - 4 - (rows - 1) * 10) / rows)))
	local function placeText(title: TextLabel, note: TextLabel)
		title.TextSize = m.Title
		note.TextSize = m.Note
		title.Position = UDim2.new(0, textX, 0.5, -(m.Title + 2))
		title.Size = UDim2.fromOffset(textW, m.Title + 4)
		note.Position = UDim2.new(0, textX, 0.5, 2)
		note.Size = UDim2.fromOffset(textW, m.Note + 4)
	end
	for _, row in refs.Volumes do
		row.Frame.Size = UDim2.new(1, 0, 0, rowH)
		placeText(row.Title, row.Note)
		local valueW = if compact then 72 else 64
		local left = rowW - controlsW
		local minus = MenuPanel.holderOf(row.Minus)
		minus.AnchorPoint = Vector2.new(0, 0.5)
		minus.Size = UDim2.fromOffset(m.Button, m.Button)
		minus.Position = UDim2.new(0, left, 0.5, 3)
		local plus = MenuPanel.holderOf(row.Plus)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Size = UDim2.fromOffset(m.Button, m.Button)
		plus.Position = UDim2.new(1, -(valueW + 12 + m.Button), 0.5, 3)
		local trackLeft = left + m.Button + 16
		local trackW = (rowW - (valueW + 12 + m.Button) - 16) - trackLeft
		row.Track.AnchorPoint = Vector2.new(0, 0.5)
		row.Track.Position = UDim2.new(0, trackLeft, 0.5, 0)
		row.Track.Size = UDim2.fromOffset(math.max(40, trackW), m.Button)
		row.Value.TextSize = m.Value
		row.Value.Position = UDim2.new(1, -10, 0.5, 0)
		row.Value.Size = UDim2.fromOffset(valueW, 30)
	end
	for _, row in refs.Toggles do
		row.Frame.Size = UDim2.new(1, 0, 0, rowH)
		placeText(row.Title, row.Note)
		local holder = MenuPanel.holderOf(row.Button)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Size = UDim2.fromOffset(m.Toggle, m.Button)
		holder.Position = UDim2.new(1, -12, 0.5, 3)
		row.Button.TextSize = if compact then 26 else 24
	end
end

-- Shows a settings record.
function SettingsView.set(refs: Refs, settings: SettingsConfig.Settings)
	local values = settings :: { [string]: any }
	for id, row in refs.Volumes do
		local v = math.clamp(tonumber(values[id]) or 0, 0, 1)
		row.Fill.Size = UDim2.fromScale(v, 1)
		row.Knob.Position = UDim2.fromScale(v, 0.5)
		row.Value.Text = SettingsConfig.percent(v)
		row.Value.TextColor3 = if v > 0 then Theme.Coin else Theme.TextDim
	end
	for id, row in refs.Toggles do
		local on = values[id] == true
		row.Button.Text = if on then "ON" else "OFF"
		MenuPanel.style(row.Button, if on then SettingsView.OnColor else SettingsView.OffColor, if on then SettingsView.OnDark else SettingsView.OffDark)
	end
end

-- The first button a gamepad selects.
function SettingsView.firstButton(refs: Refs): TextButton
	return refs.Volumes.Music.Minus
end

-- Every tappable thing (for the touch-size tests).
function SettingsView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { MenuPanel.holderOf(refs.Frame.Close) }
	for _, id in refs.Order do
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
