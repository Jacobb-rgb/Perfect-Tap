--[[
	Your ore train on screen (pure builder + pure helpers; TrainController
	fills it in). Two ScreenGuis:

	  chip    a small HUD panel under the coins (top-left, below the "+$X"
	          popups): a locomotive icon in your banner color, "TRAIN 6/8",
	          the state ("On its way 0:12", "Returning", "Full – Send!"...),
	          a cargo bar and a SEND button. The left part is a button that
	          opens the panel; a key hint shows T (keyboard) or the L3 glyph
	          (gamepad).
	  panel   the Mine Station panel: on the left your cargo, the trip time and
	          a big SEND button; on the right the Capacity and Speed upgrades
	          (level, what the next level gives, price, BUY) and the Express
	          perk line ("coming soon"); X / B / Backspace closes it.

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). The compact layout (phones, uiScale 0.62) makes every
	button at least 44 pt (TrainView.touchTargets lists them for the tests).
	Helpers: read (a State snapshot's Train with safe defaults), status (the
	chip and panel state), upgrade (an upgrade row), seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrainConfig = require(Shared.Config.TrainConfig)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local UIKit = require(script.Parent.UIKit)

local TrainView = {}

TrainView.PhoneScale = 0.62 -- HudController's floor (phones)
TrainView.MinTouch = 44 -- points
TrainView.ChipLeft = 16 -- lines up with the coins panel
TrainView.ChipTop = 136 -- under the coins panel (16..90) and its "+$X" popups (96..130)
TrainView.ExpressPrice = 199 -- R$, the placeholder on the Express line

export type Snapshot = {
	Cargo: number,
	Capacity: number,
	Moving: number,
	DepartAt: number?,
	ArriveAt: number?,
	CapacityLevel: number,
	SpeedLevel: number,
	NextCapacityPrice: number?,
	NextSpeedPrice: number?,
	Express: boolean,
	TripSeconds: number,
	AutoDepartIn: number?,
}

export type Phase = "Empty" | "Loading" | "Full" | "Moving" | "Returning"

export type Status = {
	Phase: Phase,
	Cargo: number,
	Capacity: number,
	Title: string, -- "TRAIN 6/8"
	Line: string, -- "On its way 0:12"
	Color: Color3, -- the line's color
	CanSend: boolean,
	Fill: number, -- cargo / capacity, 0..1
	Progress: number?, -- share of the trip done while the train is on its way (the chip's bar shows it)
}

export type Kind = "Capacity" | "Speed"

export type Upgrade = {
	Kind: Kind,
	Name: string,
	LevelText: string, -- "LV 2/6"
	Detail: string, -- "Cargo 12 → 18"
	Price: number?, -- nil when maxed
	PriceText: string,
	Maxed: boolean,
	CanBuy: boolean, -- not maxed and affordable
}

export type Row = {
	Frame: Frame,
	Name: TextLabel,
	Level: TextLabel,
	Detail: TextLabel,
	Price: TextLabel,
	Buy: TextButton,
}

export type Refs = {
	-- the HUD chip
	Chip: ScreenGui,
	ChipFrame: Frame,
	ChipOpen: TextButton,
	ChipIcon: Frame,
	ChipTitle: TextLabel,
	ChipLine: TextLabel,
	ChipBar: Frame,
	ChipFill: Frame,
	ChipSend: TextButton,
	ChipKey: TextLabel,
	ChipGlyph: ImageLabel,
	-- the station panel
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Close: TextButton,
	Card: Frame,
	CardLabel: TextLabel,
	CardIcon: Frame,
	Cargo: TextLabel,
	CargoUnit: TextLabel,
	CargoBar: Frame,
	CargoFill: Frame,
	State: TextLabel,
	Trip: TextLabel,
	Send: TextButton,
	Rows: { Capacity: Row, Speed: Row },
	Express: Row,
	Hint: TextLabel,
	Compact: boolean,
}

type ChipMetrics = {
	Width: number,
	Height: number,
	Icon: number, -- icon width (height = width / ICON_ASPECT)
	Title: number,
	Line: number,
	SendWidth: number,
	SendHeight: number,
	SendText: number,
	Key: number,
}

type PanelMetrics = {
	Width: number,
	Height: number,
	Header: number,
	Card: number, -- left column width
	Row: number,
	Button: number,
	Buy: number,
	Close: number,
	Title: number,
	Text: number,
	Small: number,
	Big: number,
	CardIcon: number,
}

local PAD = 16
local GAP = 10
local ICON_ASPECT = 1.36 -- the locomotive icon keeps this width / height (round wheels)

local CHIP: { [string]: ChipMetrics } = {
	Normal = { Width = 330, Height = 66, Icon = 46, Title = 22, Line = 16, SendWidth = 88, SendHeight = 46, SendText = 20, Key = 22 },
	-- phones: at uiScale 0.62 the 72-unit SEND is 44.6 pt, the 84-unit chip 52 pt
	Compact = { Width = 384, Height = 84, Icon = 56, Title = 26, Line = 18, SendWidth = 112, SendHeight = 72, SendText = 24, Key = 0 },
}

local PANEL: { [string]: PanelMetrics } = {
	Normal = {
		Width = 860,
		Height = 460,
		Header = 72,
		Card = 300,
		Row = 100,
		Button = 56,
		Buy = 128,
		Close = 54,
		Title = 34,
		Text = 20,
		Small = 16,
		Big = 46,
		CardIcon = 96,
	},
	-- phones: every button 76 units (47 pt at uiScale 0.62)
	Compact = {
		Width = 1000,
		Height = 490,
		Header = 90,
		Card = 360,
		Row = 112,
		Button = 76,
		Buy = 156,
		Close = 76,
		Title = 32,
		Text = 24,
		Small = 19,
		Big = 54,
		CardIcon = 104,
	},
}

---------------------------------------------------------------- pure helpers

local function num(value: any, default: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return default
end

local function optional(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- A State snapshot's Train field with safe defaults (junk fields are ignored).
function TrainView.read(raw: any): Snapshot
	local t = if type(raw) == "table" then raw else {}
	local express = t.Express == true
	local capacityLevel = math.max(0, math.floor(num(t.CapacityLevel, 0)))
	local speedLevel = math.max(0, math.floor(num(t.SpeedLevel, 0)))
	return {
		Cargo = math.max(0, math.floor(num(t.Cargo, 0))),
		Capacity = math.max(0, math.floor(num(t.Capacity, TrainConfig.capacity(capacityLevel, express)))),
		Moving = math.max(0, math.floor(num(t.Moving, 0))),
		DepartAt = optional(t.DepartAt),
		ArriveAt = optional(t.ArriveAt),
		CapacityLevel = capacityLevel,
		SpeedLevel = speedLevel,
		NextCapacityPrice = optional(t.NextCapacityPrice),
		NextSpeedPrice = optional(t.NextSpeedPrice),
		Express = express,
		TripSeconds = num(t.TripSeconds, TrainConfig.tripSeconds(speedLevel, express)),
		AutoDepartIn = optional(t.AutoDepartIn),
	}
end

-- "30 s" / "12.5 s"
function TrainView.seconds(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d s", rounded)
	end
	return string.format("%.1f s", rounded)
end

--[[
	What the chip and the panel say. `now` is server time
	(workspace:GetServerTimeNow(), like DepartAt / ArriveAt); `autoLeft` the
	seconds until the train leaves by itself (counted down by the controller,
	nil = use the snapshot's AutoDepartIn).
]]
function TrainView.status(train: Snapshot, now: number, autoLeft: number?): Status
	local capacity = train.Capacity
	local cargo = train.Cargo
	local fill = if capacity > 0 then math.clamp(cargo / capacity, 0, 1) else 0
	local function make(phase: Phase, line: string, color: Color3, canSend: boolean, progress: number?): Status
		return {
			Phase = phase,
			Cargo = cargo,
			Capacity = capacity,
			Title = `TRAIN {cargo}/{capacity}`,
			Line = line,
			Color = color,
			CanSend = canSend,
			Fill = fill,
			Progress = progress,
		}
	end
	local arrive = train.ArriveAt
	if arrive and now < arrive then
		local depart = train.DepartAt
		local progress = if depart and arrive > depart then math.clamp((now - depart) / (arrive - depart), 0, 1) else nil
		return make("Moving", "On its way " .. Format.seconds(math.max(0, math.ceil(arrive - now))), Theme.Info, false, progress)
	elseif arrive and now < arrive + TrainConfig.ReturnSeconds then
		return make("Returning", "Returning", Theme.TextDim, false)
	elseif capacity > 0 and cargo >= capacity then
		return make("Full", "Full – Send!", Theme.Accent, true)
	elseif cargo > 0 then
		local auto = autoLeft or train.AutoDepartIn
		return make(
			"Loading",
			if auto then "Leaves in " .. Format.seconds(math.max(0, math.ceil(auto))) else "Ready – Send!",
			Theme.Good,
			true
		)
	end
	return make("Empty", "Load ore at the Mine", Theme.TextDim, false)
end

-- One upgrade row from a snapshot (prices from the snapshot, else TrainConfig).
function TrainView.upgrade(train: Snapshot, kind: Kind, coins: number): Upgrade
	local list = if kind == "Capacity" then TrainConfig.Capacity else TrainConfig.Speed
	local level = if kind == "Capacity" then train.CapacityLevel else train.SpeedLevel
	local maxLevel = TrainConfig.maxLevel(list)
	level = math.clamp(level, 0, maxLevel)
	local snapshotPrice = if kind == "Capacity" then train.NextCapacityPrice else train.NextSpeedPrice
	local price: number? = if level >= maxLevel then nil else snapshotPrice or TrainConfig.nextPrice(list, level)
	local maxed = price == nil
	local detail: string
	if kind == "Capacity" then
		local now = TrainConfig.capacity(level, train.Express)
		detail = if maxed then `Cargo {now} (max)` else `Cargo {now} → {TrainConfig.capacity(level + 1, train.Express)}`
	else
		local now = TrainView.seconds(TrainConfig.tripSeconds(level, train.Express))
		detail = if maxed
			then `Trip {now} (max)`
			else `Trip {now} → {TrainView.seconds(TrainConfig.tripSeconds(level + 1, train.Express))}`
	end
	return {
		Kind = kind,
		Name = if kind == "Capacity" then "CAPACITY" else "SPEED",
		LevelText = `LV {level + 1}/{maxLevel + 1}`,
		Detail = detail,
		Price = price,
		PriceText = if price then Format.money(price) else "MAX",
		Maxed = maxed,
		CanBuy = price ~= nil and coins >= price,
	}
end

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- Colors a button: enabled in its own colors, or greyed out.
local function style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holderOf(button).BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end
TrainView.style = style

local function box(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, color: Color3, round: number?): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, frame)
	end
	UIKit.stroke(frame, 1.5)
	return frame
end

--[[
	A little side-view locomotive (Kenney Train Kit colors) drawn with frames
	in scale units, so it works at any size with width / height = 1.36.
	"Body" frames take the banner color (TrainView.setIconColor).
]]
function TrainView.icon(parent: Instance, width: number): Frame
	local c = TrainBuilder.Colors
	local icon = UIKit.new("Frame", {
		Name = "TrainIcon",
		Size = UDim2.fromOffset(width, width / ICON_ASPECT),
		BackgroundTransparency = 1,
	}, parent)
	box(icon, "Chimney", 0.17, 0.06, 0.31, 0.4, c.Soot)
	box(icon, "Body", 0.1, 0.34, 0.6, 0.72, Theme.Accent, 0.25)
	box(icon, "Smokebox", 0.03, 0.36, 0.16, 0.72, c.Smokebox, 0.3)
	box(icon, "Body", 0.55, 0.14, 0.93, 0.72, Theme.Accent)
	box(icon, "Window", 0.63, 0.25, 0.84, 0.45, c.Glass)
	box(icon, "Roof", 0.5, 0.04, 0.98, 0.17, c.Roof)
	box(icon, "Deck", 0.02, 0.69, 0.97, 0.79, c.Deck)
	local d = 0.24 -- wheel width share; height share = d * aspect, so the wheels stay round
	for i, x in { 0.2, 0.47, 0.76 } do
		box(icon, "Wheel" .. i, x - d / 2, 0.98 - d * ICON_ASPECT, x + d / 2, 0.98, c.Red, 0.5)
	end
	return icon
end

function TrainView.setIconColor(icon: Frame, color: Color3)
	for _, child in icon:GetChildren() do
		if child.Name == "Body" and child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end
end

local function bar(parent: Instance, name: string): (Frame, Frame)
	local track = UIKit.new("Frame", {
		Name = name,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(track, 6)
	UIKit.stroke(track, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, track)
	UIKit.corner(fill, 6)
	return track, fill
end

local function buildChip(): (ScreenGui, { [string]: any })
	local gui = UIKit.screen("TerraForgeTrain", 6)
	gui:SetAttribute("TerraForge", true)
	local frame = UIKit.panel(gui, {
		Name = "TrainChip",
		Position = UDim2.fromOffset(TrainView.ChipLeft, TrainView.ChipTop),
	})
	-- the left part opens the panel (mouse, touch, gamepad selection)
	local open = UIKit.new("TextButton", {
		Name = "Open",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
	}, frame)
	local icon = TrainView.icon(frame, CHIP.Normal.Icon)
	local title = UIKit.label(frame, "TRAIN 0/8", 22, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local line = UIKit.label(frame, "", 16, {
		Name = "Line",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local track, fill = bar(frame, "Bar")
	local send = UIKit.button(frame, "SEND", Theme.Good, Theme.GoodDark, { Name = "Send" })
	-- keyboard key cap "T" (PC) or the L3 glyph (gamepad), at the title's end
	local key = UIKit.label(frame, "T", 15, {
		Name = "Key",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.PanelDark,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	UIKit.corner(key, 6)
	UIKit.stroke(key, 2)
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Visible = false,
	}, frame)
	return gui,
		{
			Frame = frame,
			Open = open,
			Icon = icon,
			Title = title,
			Line = line,
			Bar = track,
			Fill = fill,
			Send = send,
			Key = key,
			Glyph = glyph,
		}
end

local function upgradeRow(parent: Instance, name: string, order: number): Row
	local frame = UIKit.new("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)
	local title = UIKit.label(frame, name, 22, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local level = UIKit.chip(frame, "LV 1/6", Theme.PanelDark, { Name = "Level" })
	local detail = UIKit.label(frame, "", 20, {
		Name = "Detail",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local price = UIKit.label(frame, "", 22, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	local buy = UIKit.button(frame, "BUY", Theme.Accent, Theme.AccentDark, { Name = "Buy" })
	return { Frame = frame, Name = title, Level = level, Detail = detail, Price = price, Buy = buy }
end

function TrainView.build(compact: boolean?): Refs
	local chip, c = buildChip()

	local gui = UIKit.screen("TerraForgeTrainPanel", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Active = true,
	})
	local title = UIKit.label(panel, "YOUR ORE TRAIN", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, "Throw ore into the Mine Station hopper. Your train takes it home to your Ore Pen.", 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
	})

	-- left: your cargo
	local card = UIKit.new("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(card, 12)
	UIKit.stroke(card, 2.5)
	local cardLabel = UIKit.label(card, "CARGO", 22, {
		Name = "Label",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local cardIcon = TrainView.icon(card, PANEL.Normal.CardIcon)
	local cargo = UIKit.label(card, "0 / 8", 46, {
		Name = "Cargo",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local unit = UIKit.label(card, "ore on board", 16, {
		Name = "Unit",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local cargoBar, cargoFill = bar(card, "Bar")
	local state = UIKit.label(card, "", 20, {
		Name = "State",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local trip = UIKit.label(card, "", 16, {
		Name = "Trip",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local send = UIKit.button(card, "SEND TRAIN", Theme.Good, Theme.GoodDark, { Name = "Send", TextSize = 24 })

	-- right: upgrades and the Express perk
	local rows = UIKit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
	}, panel)
	UIKit.list(rows, Enum.FillDirection.Vertical, GAP)
	local capacityRow = upgradeRow(rows, "CAPACITY", 1)
	local speedRow = upgradeRow(rows, "SPEED", 2)
	local express = upgradeRow(rows, "EXPRESS TRAIN", 3)
	express.Name.TextColor3 = Theme.Info
	express.Level.Visible = false
	express.Detail.Text = "2x speed, +50% cargo"
	express.Price.Text = `{TrainView.ExpressPrice} R$`
	express.Price.TextColor3 = Theme.Good
	express.Buy.Text = "SOON"
	style(express.Buy, false, Theme.Good, Theme.GoodDark)

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})

	local refs: Refs = {
		Chip = chip,
		ChipFrame = c.Frame,
		ChipOpen = c.Open,
		ChipIcon = c.Icon,
		ChipTitle = c.Title,
		ChipLine = c.Line,
		ChipBar = c.Bar,
		ChipFill = c.Fill,
		ChipSend = c.Send,
		ChipKey = c.Key,
		ChipGlyph = c.Glyph,
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Close = close,
		Card = card,
		CardLabel = cardLabel,
		CardIcon = cardIcon,
		Cargo = cargo,
		CargoUnit = unit,
		CargoBar = cargoBar,
		CargoFill = cargoFill,
		State = state,
		Trip = trip,
		Send = send,
		Rows = { Capacity = capacityRow, Speed = speedRow },
		Express = express,
		Hint = hint,
		Compact = false,
	}
	TrainView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

local function placeRow(row: Row, m: PanelMetrics)
	row.Frame.Size = UDim2.new(1, 0, 0, m.Row)
	local buy = holderOf(row.Buy)
	buy.AnchorPoint = Vector2.new(1, 0)
	buy.Size = UDim2.fromOffset(m.Buy, m.Button)
	buy.Position = UDim2.new(1, -12, 0, (m.Row - m.Button) / 2 + 3) -- the face sits 5 above its lip
	row.Buy.TextSize = m.Text + 2
	local right = 12 + m.Buy + 12
	local priceWidth = 112
	row.Price.AnchorPoint = Vector2.new(1, 0.5)
	row.Price.Position = UDim2.new(1, -right, 0.5, 0)
	row.Price.Size = UDim2.fromOffset(priceWidth, 30)
	row.Price.TextSize = m.Text + 2
	-- the text column: name with the level chip at its right end, the detail under it
	local textRight = right + priceWidth + 8
	local chipWidth = if m.Text > 20 then 92 else 78
	local nameTop = m.Row / 2 - m.Text - 12
	row.Level.AnchorPoint = Vector2.new(1, 0)
	row.Level.Position = UDim2.new(1, -textRight, 0, nameTop + 3)
	row.Level.Size = UDim2.fromOffset(chipWidth, m.Text + 2)
	row.Level.TextSize = m.Small - 1
	row.Name.Position = UDim2.fromOffset(14, nameTop)
	row.Name.Size = UDim2.new(1, -(14 + textRight + (if row.Level.Visible then chipWidth + 6 else 0)), 0, m.Text + 8)
	row.Name.TextSize = m.Text + 2
	row.Detail.Position = UDim2.fromOffset(14, m.Row / 2 + 4)
	row.Detail.Size = UDim2.new(1, -(14 + textRight), 0, m.Text + 6)
	row.Detail.TextSize = m.Text
end

local function placeChip(refs: Refs, m: ChipMetrics)
	refs.ChipFrame.Size = UDim2.fromOffset(m.Width, m.Height)
	local iconHeight = m.Icon / ICON_ASPECT
	refs.ChipIcon.Size = UDim2.fromOffset(m.Icon, iconHeight)
	refs.ChipIcon.Position = UDim2.fromOffset(10, (m.Height - iconHeight) / 2)
	local textLeft = 10 + m.Icon + 10
	local sendLeft = m.Width - 10 - m.SendWidth
	local textWidth = sendLeft - 8 - textLeft
	local keyWidth = if m.Key > 0 then m.Key + 6 else 0
	local top = math.floor((m.Height - (m.Title + m.Line + 16)) / 2)
	refs.ChipTitle.Position = UDim2.fromOffset(textLeft, top)
	refs.ChipTitle.Size = UDim2.fromOffset(textWidth - keyWidth, m.Title + 4)
	refs.ChipTitle.TextSize = m.Title
	refs.ChipLine.Position = UDim2.fromOffset(textLeft, top + m.Title + 4)
	refs.ChipLine.Size = UDim2.fromOffset(textWidth, m.Line + 4)
	refs.ChipLine.TextSize = m.Line
	refs.ChipBar.Position = UDim2.fromOffset(textLeft, m.Height - 14)
	refs.ChipBar.Size = UDim2.fromOffset(textWidth, 7)
	refs.ChipKey.Visible = m.Key > 0
	refs.ChipKey.Size = UDim2.fromOffset(m.Key, m.Key)
	refs.ChipKey.Position = UDim2.fromOffset(sendLeft - 8 - m.Key, top + 2)
	refs.ChipGlyph.Size = UDim2.fromOffset(m.Title + 6, m.Title + 6)
	refs.ChipGlyph.Position = UDim2.fromOffset(sendLeft - 8 - (m.Title + 6), top - 1)
	refs.ChipOpen.Size = UDim2.fromOffset(sendLeft - 4, m.Height)
	local send = holderOf(refs.ChipSend)
	send.AnchorPoint = Vector2.new(1, 0)
	send.Size = UDim2.fromOffset(m.SendWidth, m.SendHeight)
	send.Position = UDim2.new(1, -10, 0, (m.Height - m.SendHeight) / 2 + 3)
	refs.ChipSend.TextSize = m.SendText
end

--[[
	Sizes the chip and the panel for the normal or compact (phone) layout and
	fits the panel into `maxWidth` x `maxHeight` design units (the screen
	divided by the UI scale; math.huge = no limit).
]]
function TrainView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	placeChip(refs, if compact then CHIP.Compact else CHIP.Normal)

	local m = if compact then PANEL.Compact else PANEL.Normal
	local width = math.max(620, math.min(m.Width, maxWidth - 24))
	local height = math.max(400, math.min(m.Height, maxHeight - 16))
	refs.Panel.Size = UDim2.fromOffset(width, height)

	-- header: title, subtitle (not on phones), close
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 20 else 8)
	refs.Title.Size = UDim2.new(1, -(PAD * 2 + m.Close + 10), 0, m.Title + 6)
	refs.Title.TextSize = m.Title
	refs.Subtitle.Visible = not compact
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 46)
	refs.Subtitle.Size = UDim2.new(1, -(PAD * 2 + m.Close + 10), 0, 20)
	refs.Subtitle.TextSize = m.Small
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, 12)

	-- left: the cargo card
	local cardHeight = height - m.Header - PAD
	refs.Card.Position = UDim2.fromOffset(PAD, m.Header)
	refs.Card.Size = UDim2.fromOffset(m.Card, cardHeight)
	refs.CardLabel.Position = UDim2.fromOffset(14, 10)
	refs.CardLabel.Size = UDim2.new(1, -28, 0, m.Text + 8)
	refs.CardLabel.TextSize = m.Text + 2
	local iconHeight = m.CardIcon / ICON_ASPECT
	local iconTop = 14 + m.Text + 10
	refs.CardIcon.Size = UDim2.fromOffset(m.CardIcon, iconHeight)
	refs.CardIcon.Position = UDim2.fromOffset(14, iconTop)
	local numberLeft = 14 + m.CardIcon + 14
	refs.Cargo.Position = UDim2.fromOffset(numberLeft, iconTop + iconHeight / 2 - m.Big * 0.62)
	refs.Cargo.Size = UDim2.new(1, -(numberLeft + 10), 0, m.Big)
	refs.Cargo.TextSize = m.Big
	refs.CargoUnit.Position = UDim2.fromOffset(numberLeft, iconTop + iconHeight / 2 + m.Big * 0.42)
	refs.CargoUnit.Size = UDim2.new(1, -(numberLeft + 10), 0, m.Small + 4)
	refs.CargoUnit.TextSize = m.Small
	local barTop = iconTop + iconHeight + 14
	refs.CargoBar.Position = UDim2.fromOffset(14, barTop)
	refs.CargoBar.Size = UDim2.new(1, -28, 0, if compact then 18 else 16)
	local stateTop = barTop + (if compact then 18 else 16) + 10
	refs.State.Position = UDim2.fromOffset(14, stateTop)
	refs.State.Size = UDim2.new(1, -28, 0, m.Text + 6)
	refs.State.TextSize = m.Text
	local send = holderOf(refs.Send)
	send.AnchorPoint = Vector2.new(0, 1)
	send.Size = UDim2.new(1, -28, 0, m.Button)
	send.Position = UDim2.new(0, 14, 1, -14)
	refs.Send.TextSize = if compact then 28 else 24
	local tripTop = stateTop + m.Text + 10
	refs.Trip.Position = UDim2.fromOffset(14, tripTop)
	refs.Trip.Size = UDim2.new(1, -28, 0, math.max(0, cardHeight - 14 - m.Button - 8 - tripTop))
	refs.Trip.TextSize = m.Small

	-- right: the upgrade rows (+ the hint under them on PC)
	local rowsLeft = PAD + m.Card + PAD
	local rows = refs.Rows.Capacity.Frame.Parent :: Frame
	rows.Position = UDim2.fromOffset(rowsLeft, m.Header)
	rows.Size = UDim2.new(1, -(rowsLeft + PAD), 0, m.Row * 3 + GAP * 2)
	for _, row in { refs.Rows.Capacity, refs.Rows.Speed, refs.Express } do
		placeRow(row, m)
	end
	refs.Hint.Visible = not compact
	refs.Hint.Position = UDim2.fromOffset(rowsLeft, m.Header + m.Row * 3 + GAP * 2 + 6)
	refs.Hint.Size = UDim2.new(1, -(rowsLeft + PAD), 0, 22)
	refs.Hint.TextSize = 15
end

function TrainView.row(refs: Refs, kind: Kind): Row
	return if kind == "Capacity" then refs.Rows.Capacity else refs.Rows.Speed
end

-- Every button a finger has to hit (holders of the lip buttons), for the tests.
function TrainView.touchTargets(refs: Refs): { GuiObject }
	return {
		refs.ChipOpen,
		holderOf(refs.ChipSend),
		holderOf(refs.Send),
		holderOf(refs.Close),
		holderOf(refs.Rows.Capacity.Buy),
		holderOf(refs.Rows.Speed.Buy),
		holderOf(refs.Express.Buy),
	}
end

---------------------------------------------------------------- filling in

-- The chip and the card's state (cargo, line, bar, SEND).
function TrainView.setStatus(refs: Refs, status: Status)
	refs.ChipTitle.Text = status.Title
	refs.ChipLine.Text = status.Line
	refs.ChipLine.TextColor3 = status.Color
	-- the chip's bar: the trip while it runs, else the cargo
	local progress = status.Progress
	refs.ChipFill.Size = UDim2.fromScale(progress or status.Fill, 1)
	refs.ChipFill.BackgroundColor3 = if progress then Theme.Info elseif status.Phase == "Full" then Theme.Good else Theme.Accent
	style(refs.ChipSend, status.CanSend, Theme.Good, Theme.GoodDark)

	refs.Cargo.Text = `{status.Cargo} / {status.Capacity}`
	refs.CargoFill.Size = UDim2.fromScale(status.Fill, 1)
	refs.CargoFill.BackgroundColor3 = if status.Phase == "Full" then Theme.Good else Theme.Accent
	refs.State.Text = status.Line
	refs.State.TextColor3 = status.Color
	style(refs.Send, status.CanSend, Theme.Good, Theme.GoodDark)
end

-- The trip line and the two upgrade rows.
function TrainView.setUpgrades(refs: Refs, train: Snapshot, coins: number)
	local auto = TrainConfig.AutoDepartSeconds
	refs.Trip.Text =
		`Trip {TrainView.seconds(train.TripSeconds)} to your base. It leaves when full, when you send it, or {auto} s after the last load.`
	for _, row in { refs.Rows.Capacity, refs.Rows.Speed } do
		local info = TrainView.upgrade(train, if row == refs.Rows.Capacity then "Capacity" else "Speed", coins)
		row.Name.Text = info.Name
		row.Level.Text = info.LevelText
		row.Detail.Text = info.Detail
		row.Price.Text = info.PriceText
		row.Price.TextColor3 = if info.Maxed then Theme.TextDim elseif info.CanBuy then Theme.Coin else Theme.Bad
		row.Buy.Text = if info.Maxed then "MAX" else "BUY"
		style(row.Buy, info.CanBuy, Theme.Accent, Theme.AccentDark)
	end
	local express = refs.Express
	if train.Express then
		express.Detail.Text = "2x speed, +50% cargo"
		express.Price.Text = "OWNED"
		express.Buy.Text = "ON"
		style(express.Buy, true, Theme.Good, Theme.GoodDark)
	else
		express.Detail.Text = "2x speed, +50% cargo"
		express.Price.Text = `{TrainView.ExpressPrice} R$`
		express.Buy.Text = "SOON"
		style(express.Buy, false, Theme.Good, Theme.GoodDark)
	end
end

function TrainView.setColor(refs: Refs, color: Color3)
	TrainView.setIconColor(refs.ChipIcon, color)
	TrainView.setIconColor(refs.CardIcon, color)
end

return TrainView
