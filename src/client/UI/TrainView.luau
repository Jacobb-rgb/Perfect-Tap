--[[
	Your ore train on screen (pure builder + pure helpers; TrainController
	fills it in). Two ScreenGuis:

	  chip    a small HUD panel under the coins (top-left, below the "+$X"
	          popups; on compact / touch layouts right of the side menu's
	          MENU button, chipLeft): a locomotive icon in your banner color, "TRAIN 6/8",
	          the state ("On its way 0:12", "Pen full – make room",
	          "Returning", "Full – Send!"...), a cargo / trip bar and a SEND
	          button. While the train is away the count is the ore on board
	          ("TRAIN 8/8 · On its way 0:12"). The left part is a button that
	          opens the panel; a key hint shows T (keyboard) or the L3 glyph
	          (gamepad).
	  panel   the Mine Station panel: your coins in the header; on the left
	          your cargo, the trip time and a big SEND button; on the right
	          the Capacity and Speed upgrades (level, what the next level
	          gives, price, BUY) and the Express perk line ("coming soon");
	          X / B / Backspace closes it. A gamepad selection stays inside
	          it (SelectionGroup). The chip hides while it is open.

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). The compact layout (phones, uiScale 0.62) makes every
	button at least 44 pt (TrainView.touchTargets lists them for the tests);
	narrow panels move the price onto the detail line, short ones shrink the
	upgrade rows (never under the 76-unit buttons). On phones the panel sits
	at the bottom of the screen (over the backpack button) and under the HUD coins
	when there is room; when it has to cover them, CoversCoins tells the
	controller to hide them while it is open.
	Helpers: read (a State snapshot's Train with safe defaults), status (the
	chip and panel state), upgrade (an upgrade row), seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local TrainConfig = require(Shared.Config.TrainConfig)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local PictureModels = require(Shared.Builders.PictureModels)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)

local TrainView = {}

TrainView.PhoneScale = 0.62 -- HudController's floor (phones)
TrainView.MinTouch = 44 -- points
TrainView.ChipLeft = 16 -- lines up with the coins panel
TrainView.ChipTop = 136 -- under the coins panel (16..90) and its "+$X" popups (96..130)
-- the light HUD (HudBubble): the chip goes under its menu tiles (HudController sets it from the HUD)
TrainView.HudChipTop = nil :: number?
TrainView.HudChipLeft = nil :: number? -- the round look: under the tiles' left edge, or beside their last row (HudBubble.chipLeft)
-- the round look under its tiles: the chip is as wide as them (HudBubble.chipWidth), stacked on a mouse
-- or a TV (the block is two tiles wide: SEND goes under the name and the line; CHIP.Stack)
TrainView.HudChipWidth = nil :: number?
TrainView.HudChipStack = false
TrainView.HudChipTenFoot = false -- a TV: the stacked chip's bigger words (CHIP.StackTv)
-- The chip's ScreenGui order: over the HUD (5), or under it in the round look (the chip by its
-- tiles: the HUD's toasts, "+$X" floaters and Server Luck line stay readable over it there).
TrainView.ChipOrder = 6
TrainView.UnderHudOrder = 4
-- compact (touch) layouts: the side menu's MENU button sits first in the chip's
-- row (SideMenuView), so the chip starts this far right of ChipLeft (chipLeft)
TrainView.MenuSlot = 88 -- MENU (84 wide at x 12) and a gap
TrainView.ExpressPrice = 199 -- R$, the placeholder on the Express line
TrainView.UnloadGrace = 2 -- seconds after the arrival before a train with ore still on board counts as waiting
TrainView.CoinsBottom = 96 -- HudView's coins panel (16..90) and a gap: a phone panel below this leaves it clear
TrainView.MinPanelHeight = 400 -- the compact cargo card needs this much (its SEND under the state line)
-- Why the train waits at your stop (the server's WaitReason): the state line meanwhile
TrainView.PenFullLine = "Pen full – make room"
TrainView.PenOverLine = "Pen over its limit – take or sell ore"
-- Direct Unload waits (the server's UnloadWait, PenService's Train lane): the state line meanwhile
TrainView.UnloadWaitText = {
	Jammed = "Belt full – waiting",
	TooMany = "Too many loose items",
} :: { [string]: string }

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
	TripCut: number, -- the share the rebirth's Express Rails cut off every trip (0..0.5)
	AutoDepartIn: number?,
	Waiting: boolean, -- at your stop with ore it can't unload (the Ore Pen is full)
	WaitReason: string?, -- why: "PenOver" (the pen holds more than it fits) | "PenFull"
	Unloading: boolean?, -- at your stop pouring dirty ore onto your TRAIN chute's belt (Direct Unload)
	UnloadWait: string?, -- why that pouring waits right now (a key of TrainView.UnloadWaitText)
}

export type Phase = "Empty" | "Loading" | "Full" | "Moving" | "Unloading" | "Waiting" | "Returning"

export type Status = {
	Phase: Phase,
	Cargo: number, -- the count shown: the station cargo, or the ore on board while the train is away
	Capacity: number,
	Title: string, -- "TRAIN 6/8"
	Unit: string, -- under the panel's big count: "ore on board" / "ore on the way"...
	Line: string, -- "On its way 0:12"
	Color: Color3, -- the line's color
	CanSend: boolean,
	Fill: number, -- Cargo / capacity, 0..1
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
	Balance: Frame, -- your coins in the header
	BalanceIcon: Frame,
	BalanceAmount: TextLabel,
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
	CoversCoins: boolean, -- the panel lies over the HUD coins (layout)
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
	Balance: number, -- the header's coins pill: width (height = Close - 14)
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
	-- under the round look's two tiles (a mouse or a TV, HudChipStack): the locomotive, the name
	-- and the bar on top, the line under them, SEND as wide as the chip at the bottom (its Width
	-- is the tiles', HudChipWidth; HudBubble.StackChipHeight mirrors the Height)
	Stack = { Width = 150, Height = 104, Icon = 34, Title = 18, Line = 13, SendWidth = 0, SendHeight = 30, SendText = 18, Key = 18 },
	-- a TV: the words at least 18 px at 1080p (15 units): the name across the chip on two rows
	-- ("TRAIN" / "120/180"), the line on two rows (HudBubble.StackChipHeightTv)
	StackTv = { Width = 161, Height = 158, Icon = 38, Title = 20, Line = 15, SendWidth = 0, SendHeight = 34, SendText = 20, Key = 20 },
}

-- The stacked chip's rows (design units from its top): the locomotive's square with the name
-- and the bar beside it, the line under them, then SEND as wide as the chip. A TV: the name
-- across the chip on two rows (no square: the words stay 15 units), the bar under it, the line
-- on two rows, SEND.
type StackRows = {
	Pad: number,
	Square: number,
	TitleRows: number,
	TitleMin: number,
	BarTop: number,
	LineTop: number,
	LineRows: number,
	SendTop: number,
	Bottom: number,
}
local STACK: StackRows =
	{ Pad = 6, Square = 34, TitleRows = 1, TitleMin = 0, BarTop = 0, LineTop = 42, LineRows = 1, SendTop = 59, Bottom = 5 }
-- (a TV's rows follow the name's two rows: pixelStackLayout puts the bar, the line and SEND under
-- them; BarTop / LineTop / SendTop here fit the widest pixel font, 24 units a row)
local STACK_TV: StackRows =
	{ Pad = 6, Square = 0, TitleRows = 2, TitleMin = 15, BarTop = 60, LineTop = 71, LineRows = 2, SendTop = 109, Bottom = 5 }

local function stackRows(): StackRows
	return if TrainView.HudChipTenFoot then STACK_TV else STACK
end

-- The chip's metrics on a layout: the stacked chip under the round look's tiles, else the normal or
-- compact one (as wide as the tiles when it goes under them on touch; SEND a little narrower there).
local function chipMetrics(compact: boolean): ChipMetrics
	if TrainView.HudChipStack and TrainView.HudChipTop then
		local m = table.clone(if TrainView.HudChipTenFoot then CHIP.StackTv else CHIP.Stack)
		m.Width = TrainView.HudChipWidth or m.Width
		return m
	end
	local m = if compact then CHIP.Compact else CHIP.Normal
	local width = TrainView.HudChipWidth
	if width and TrainView.HudChipTop then
		m = table.clone(m)
		if width < m.Width then
			m.SendWidth = math.max(m.SendHeight, math.min(m.SendWidth, math.floor(width * 0.27)))
		end
		m.Width = width
	end
	return m
end

-- Where the chip's left edge goes (design units): ChipLeft, or right of the
-- side menu's MENU button on compact (touch) layouts.
function TrainView.chipLeft(compact: boolean): number
	if TrainView.HudChipTop then
		return TrainView.HudChipLeft or TrainView.ChipLeft -- the light HUD has no MENU button there
	end
	return TrainView.ChipLeft + (if compact then TrainView.MenuSlot else 0)
end

-- Where the chip's top goes (design units): under the light HUD's tiles, or ChipTop.
function TrainView.chipTop(): number
	return TrainView.HudChipTop or TrainView.ChipTop
end

-- The chip's size on a layout (design units).
function TrainView.chipSize(compact: boolean): Vector2
	local m = chipMetrics(compact)
	return Vector2.new(m.Width, m.Height)
end

-- Takes the chip's place from the light HUD's gui attributes (HudBubble.buildGame: ChipTop,
-- ChipLeft, ChipWidth, ChipStack; HudController at start, the specs); nil = the default place.
function TrainView.useHud(gui: Instance?)
	local function number(name: string): number?
		local value = if gui then gui:GetAttribute(name) else nil
		return if type(value) == "number" then value else nil
	end
	TrainView.HudChipTop = number("ChipTop")
	TrainView.HudChipLeft = number("ChipLeft")
	TrainView.HudChipWidth = number("ChipWidth")
	TrainView.HudChipStack = gui ~= nil and gui:GetAttribute("ChipStack") == true
	TrainView.HudChipTenFoot = gui ~= nil and gui:GetAttribute("ChipTenFoot") == true
end

-- Is the chip the stacked one (under the round look's tiles on a mouse or a TV)?
function TrainView.chipStacked(): boolean
	return TrainView.HudChipStack == true and TrainView.HudChipTop ~= nil
end

local PANEL: { [string]: PanelMetrics } = {
	Normal = {
		Width = 860,
		Height = 460,
		Header = 72,
		Balance = 172,
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
		Balance = 196,
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
		TripSeconds = num(t.TripSeconds, TrainConfig.tripSeconds(speedLevel, express, optional(t.TripCut))),
		TripCut = math.clamp(num(t.TripCut, 0), 0, 0.5),
		AutoDepartIn = optional(t.AutoDepartIn),
		Waiting = t.Waiting == true,
		WaitReason = if t.WaitReason == "PenOver" or t.WaitReason == "PenFull" then t.WaitReason else nil,
		Unloading = t.Unloading == true,
		UnloadWait = if type(t.UnloadWait) == "string" and TrainView.UnloadWaitText[t.UnloadWait] then t.UnloadWait else nil,
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
	Is your train standing at your stop because the Ore Pen is full? The
	server says so (Waiting), or it still has ore on board (Moving > 0)
	UnloadGrace seconds after its ArriveAt (the arrival itself unloads, the
	grace covers the snapshot that is still on its way), unless the server
	says it is pouring its dirty ore onto your TRAIN chute's belt
	(Unloading, Direct Unload). `now` is server time.
]]
function TrainView.waiting(train: Snapshot, now: number): boolean
	if train.Waiting then
		return true
	elseif train.Unloading then
		-- Direct Unload: it stands there on purpose, pouring onto your belt
		return false
	end
	local arrive = train.ArriveAt
	return train.Moving > 0 and arrive ~= nil and now >= arrive + TrainView.UnloadGrace
end

--[[
	What the chip and the panel say. `now` is server time
	(workspace:GetServerTimeNow(), like DepartAt / ArriveAt); `autoLeft` the
	seconds until the train leaves by itself (counted down by the controller,
	nil = use the snapshot's AutoDepartIn). While the train is away the count
	is the ore on board (Moving): on its way, unloading at your stop (with
	Direct Unload "Unloading onto your belt", or why that waits:
	UnloadWaitText), the phase "Waiting" there because the Ore Pen is full
	("Pen full – make room", TrainView.waiting) or holds more than it fits
	(WaitReason "PenOver": PenOverLine), then rolling back empty.
	Nothing can be sent while it is away.
]]
function TrainView.status(train: Snapshot, now: number, autoLeft: number?): Status
	local capacity = train.Capacity
	local function make(phase: Phase, count: number, unit: string, line: string, color: Color3, canSend: boolean, progress: number?): Status
		return {
			Phase = phase,
			Cargo = count,
			Capacity = capacity,
			Title = `TRAIN {count}/{capacity}`,
			Unit = unit,
			Line = line,
			Color = color,
			CanSend = canSend,
			Fill = if capacity > 0 then math.clamp(count / capacity, 0, 1) else 0,
			Progress = progress,
		}
	end
	local moving = train.Moving
	local arrive = train.ArriveAt
	if TrainView.waiting(train, now) then
		local line = if train.WaitReason == "PenOver" then TrainView.PenOverLine else TrainView.PenFullLine
		return make("Waiting", moving, "ore waiting at your pen", line, Theme.Bad, false)
	elseif (arrive and now < arrive) or (moving > 0 and not arrive) then
		local depart = train.DepartAt
		local progress = if depart and arrive and arrive > depart then math.clamp((now - depart) / (arrive - depart), 0, 1) else nil
		local line = if arrive then "On its way " .. Format.seconds(math.max(0, math.ceil(arrive - now))) else "On its way"
		return make("Moving", moving, "ore on the way", line, Theme.Info, false, progress)
	elseif moving > 0 then
		-- just arrived (UnloadGrace), or Direct Unload: the server is unloading it
		-- (onto your belt, or waiting for room there: UnloadWait says why)
		local wait = if train.Unloading and train.UnloadWait then TrainView.UnloadWaitText[train.UnloadWait] else nil
		if wait then
			return make("Unloading", moving, "ore on the way", wait, Theme.Accent, false, 1)
		end
		local line = if train.Unloading then "Unloading onto your belt" else "Unloading…"
		return make("Unloading", moving, "ore on the way", line, Theme.Info, false, 1)
	elseif arrive and now < arrive + TrainConfig.ReturnSeconds then
		return make("Returning", 0, "ore on board", "Returning", Theme.TextDim, false)
	end
	local cargo = train.Cargo
	if capacity > 0 and cargo >= capacity then
		return make("Full", cargo, "ore on board", "Full – Send!", Theme.Accent, true)
	elseif cargo > 0 then
		local auto = autoLeft or train.AutoDepartIn
		return make(
			"Loading",
			cargo,
			"ore on board",
			if auto then "Leaves in " .. Format.seconds(math.max(0, math.ceil(auto))) else "Ready – Send!",
			Theme.Good,
			true
		)
	end
	return make("Empty", 0, "ore on board", "Load ore at the Mine", Theme.TextDim, false)
end

-- The HUD chip shows with the HUD, but not while the panel is open (it says the same; on PC its
-- edge would cover the chip's SEND), nor while the touch side menu's grid is open in its place
-- (MenuPanels.gridOpen: the grid would cover it half-way).
function TrainView.chipVisible(hudShown: boolean, panelOpen: boolean, gridOpen: boolean?): boolean
	return hudShown and not panelOpen and gridOpen ~= true
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
		local now = TrainView.seconds(TrainConfig.tripSeconds(level, train.Express, train.TripCut))
		detail = if maxed
			then `Trip {now} (max)`
			else `Trip {now} → {TrainView.seconds(TrainConfig.tripSeconds(level + 1, train.Express, train.TripCut))}`
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

---------------------------------------------------------------- the Pop pieces
--[[
	The panel's Pop look (popSkin, at the end of the file) dresses the same
	instances the dark build makes: a lip button's holder becomes the painted
	Pop face (attribute Pop, PopKind "Text" | "Coin" | "Robux") and the
	button on it a see-through TextButton with white chunky words. A "Coin"
	button shows the drawn gold coin and the row's price while it says BUY;
	the "Robux" one (Express) the robux mark and the price while it says
	SOON (syncFace). Everything else it says ("MAX", "BOUGHT!", "…", "ON")
	shows as its own words.
]]

local TRAIN_FROM = Vector3.new(-1, 0.35, -0.55) -- (PictureModels' "train" camera: the side, a little from the front)

-- The Pop paint for one of the old button colours.
local function popPaintOf(color: Color3): string
	if color == Theme.Good then
		return "Green"
	elseif color == Theme.Accent then
		return "Orange"
	elseif color == Theme.Bad then
		return "Red"
	elseif color == Theme.Info then
		return "Blue"
	end
	return "Slate"
end

-- The black edge of a text (its Contextual UIStroke, made when missing).
local function popEdge(label: GuiObject)
	local text: any = label
	local edge: UIStroke? = nil
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			edge = child
		end
	end
	local stroke = edge or Pop.edge(label)
	stroke.Color = PopTheme.Outline
	stroke.Transparency = 0
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = Pop.edgeFor(if text.TextScaled then 24 else text.TextSize)
end

-- White chunky words with a black edge on an old label or button.
local function popText(label: GuiObject, font: Font?)
	local text: any = label
	text.FontFace = font or PopTheme.Font
	text.TextColor3 = PopTheme.Ink
	popEdge(label)
end

-- The dark copy under a title (Pop.shadow) follows the title's place and words.
local function syncShadow(label: TextLabel)
	local parent = label.Parent
	local shade = if parent then parent:FindFirstChild(label.Name .. "Shadow") else nil
	if shade and shade:IsA("TextLabel") then
		shade.AnchorPoint = label.AnchorPoint
		shade.Position = label.Position + UDim2.fromOffset(0, 4)
		shade.Size = label.Size
		shade.Text = label.Text
		shade.TextSize = label.TextSize
		shade.Visible = label.Visible
	end
end

-- A lip button (UIKit.button) as a Pop button: the holder painted, the button see-through on it.
local function popButton(button: TextButton, paint: string | Pop.Paint, kind: string?)
	local holder = holderOf(button)
	for _, child in holder:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local corner = holder:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 10)
	end
	Pop.face(holder, paint, 10)
	local rim = holder:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 1
	end
	Pop.studs(holder, 10, 0.45, 28, 1)
	holder:SetAttribute("Pop", true)
	holder:SetAttribute("PopKind", kind or "Text")
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	button.BackgroundTransparency = 1
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 3
	popText(button)
end

-- A Pop button's face: its own words, or the coin / robux mark with the price (see above).
local function syncFace(button: TextButton)
	local holder = holderOf(button)
	local kind = holder:GetAttribute("PopKind")
	if kind ~= "Coin" and kind ~= "Robux" then
		return
	end
	local amount = ""
	if kind == "Coin" and button.Text == "BUY" then
		local row = holder.Parent
		local price = if row then row:FindFirstChild("Price") else nil
		amount = if price and price:IsA("TextLabel") then price.Text else ""
	elseif kind == "Robux" and button.Text == "SOON" then
		amount = tostring(TrainView.ExpressPrice)
	end
	local shows = amount ~= ""
	button.TextTransparency = if shows then 1 else 0
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") then
			child.Transparency = if shows then 1 else 0
		end
	end
	local face = button:FindFirstChild("PopFace") :: Frame?
	if not shows then
		if face then
			face.Visible = false
		end
		return
	end
	local w, h = holder.Size.X.Offset, holder.Size.Y.Offset
	local key = `{amount}|{w}|{h}`
	if face and face:GetAttribute("Key") == key then
		face.Visible = true
		return
	end
	if face then
		face:Destroy()
	end
	local mark = math.floor(h * 0.5)
	local chars = math.max(1, utf8.len(amount) or #amount)
	local size = math.clamp(math.floor(math.min(h * 0.5, (w - 20 - mark - 6) / (chars * 0.6))), 12, 40)
	mark = math.min(mark, size + 4)
	local row = UIKit.new("Frame", {
		Name = "PopFace",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, button)
	row:SetAttribute("Key", key)
	UIKit.list(row, Enum.FillDirection.Horizontal, 5, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	if kind == "Coin" then
		Pop.coin(row, mark, { LayoutOrder = 1 })
	else
		local robux = UIKit.new("ImageLabel", {
			Name = "Mark",
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(mark, mark),
			ZIndex = 6,
		}, row)
		IconAssets.apply(robux, "robux")
		robux:SetAttribute("Icon", "robux")
	end
	Pop.text(row, amount, size, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Pop.textWidth(amount, size), size + 6),
		ZIndex = 6,
	})
end

-- Colors a button: enabled in its own colors, or greyed out. (The button's
-- BackgroundColor3 says which in both looks; on a Pop button it is unseen.)
local function style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	local holder = holderOf(button)
	if holder:GetAttribute("Pop") then
		local kind = holder:GetAttribute("PopKind")
		local paint: string | Pop.Paint = if kind == "Robux"
			then PopTheme.Price
			elseif not enabled then PopTheme.Gray
			elseif kind == "Coin" then "Yellow"
			else popPaintOf(color)
		Pop.repaint(holder, paint)
		syncFace(button)
		return
	end
	holder.BackgroundColor3 = if enabled then dark else Theme.PanelDark
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
		Position = UDim2.fromOffset(TrainView.ChipLeft, TrainView.chipTop()),
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
		TextTruncate = Enum.TextTruncate.AtEnd,
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
		TextTruncate = Enum.TextTruncate.AtEnd,
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
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local title = UIKit.label(panel, "YOUR ORE TRAIN", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle =
		UIKit.label(panel, "Load the ore in your backpack at the Mine Station. Your train takes it home to your Ore Pen.", 16, {
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
	-- your coins, next to the close button (the HUD's may be covered on phones)
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(balance, 10)
	UIKit.stroke(balance, 2)
	local balanceIcon = HudView.coinIcon(balance, 26)
	local balanceAmount = UIKit.label(balance, "$0", 24, {
		Name = "Amount",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
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
		Balance = balance,
		BalanceIcon = balanceIcon,
		BalanceAmount = balanceAmount,
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
		CoversCoins = false,
	}
	TrainView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

local PRICE_WIDTH = 112
local NARROW_PRICE_WIDTH = 86

local function chipWidthOf(m: PanelMetrics): number
	return if m.Text > 20 then 92 else 78
end

--[[
	Is a row of `rowsWidth` units too narrow for the name and its level chip
	next to the price? Then the price moves onto the detail line ("CAPACITY"
	in the title font is about 5.2 x its text size wide).
]]
function TrainView.isNarrow(m: PanelMetrics, rowsWidth: number): boolean
	local nameRoom = rowsWidth - (14 + 12 + m.Buy + 12 + PRICE_WIDTH + 8 + chipWidthOf(m) + 6)
	return nameRoom < (m.Text + 2) * 5.2
end

local function placeRow(row: Row, m: PanelMetrics, rowHeight: number, narrow: boolean)
	row.Frame.Size = UDim2.new(1, 0, 0, rowHeight)
	local buy = holderOf(row.Buy)
	buy.AnchorPoint = Vector2.new(1, 0)
	buy.Size = UDim2.fromOffset(m.Buy, m.Button)
	buy.Position = UDim2.new(1, -12, 0, (rowHeight - m.Button) / 2 + 3) -- the face sits 5 above its lip
	row.Buy.TextSize = m.Text + 2
	local text = if narrow then m.Text - 3 else m.Text
	local right = 12 + m.Buy + 12
	local chipWidth = chipWidthOf(m)
	local nameTop = rowHeight / 2 - text - 12
	local detailTop = rowHeight / 2 + 4
	-- the text column: name with the level chip at its right end, the detail under it;
	-- the price beside both (wide rows) or at the detail line's end (narrow rows)
	local textRight: number
	local detailRight: number
	if narrow then
		textRight = right
		detailRight = right + NARROW_PRICE_WIDTH + 8
		row.Price.AnchorPoint = Vector2.new(1, 0)
		row.Price.Position = UDim2.new(1, -right, 0, detailTop)
		row.Price.Size = UDim2.fromOffset(NARROW_PRICE_WIDTH, text + 6)
	else
		textRight = right + PRICE_WIDTH + 8
		detailRight = textRight
		row.Price.AnchorPoint = Vector2.new(1, 0.5)
		row.Price.Position = UDim2.new(1, -right, 0.5, 0)
		row.Price.Size = UDim2.fromOffset(PRICE_WIDTH, 30)
	end
	row.Price.TextSize = text + 2
	row.Level.AnchorPoint = Vector2.new(1, 0)
	row.Level.Position = UDim2.new(1, -textRight, 0, nameTop + 3)
	row.Level.Size = UDim2.fromOffset(chipWidth, text + 2)
	row.Level.TextSize = m.Small - 1
	row.Name.Position = UDim2.fromOffset(14, nameTop)
	row.Name.Size = UDim2.new(1, -(14 + textRight + (if row.Level.Visible then chipWidth + 6 else 0)), 0, text + 8)
	row.Name.TextSize = text + 2
	row.Detail.Position = UDim2.fromOffset(14, detailTop)
	row.Detail.Size = UDim2.new(1, -(14 + detailRight), 0, text + 6)
	row.Detail.TextSize = text
end

local function placeStack(refs: Refs, m: ChipMetrics)
	local k = stackRows()
	local w, h, pad = m.Width, m.Height, k.Pad
	refs.ChipFrame.Size = UDim2.fromOffset(w, h)
	local iconHeight = m.Icon / ICON_ASPECT
	refs.ChipIcon.Size = UDim2.fromOffset(m.Icon, iconHeight)
	refs.ChipIcon.Position = UDim2.fromOffset(pad, pad + (k.Square - iconHeight) / 2)
	local textLeft = pad + k.Square + 8
	refs.ChipTitle.Position = UDim2.fromOffset(textLeft, pad)
	refs.ChipTitle.Size = UDim2.fromOffset(w - textLeft - pad - (m.Key + 4), m.Title + 4)
	refs.ChipTitle.TextSize = m.Title
	refs.ChipBar.Position = UDim2.fromOffset(textLeft, pad + m.Title + 8)
	refs.ChipBar.Size = UDim2.fromOffset(w - textLeft - pad, 7)
	refs.ChipLine.Position = UDim2.fromOffset(pad + 2, k.LineTop)
	refs.ChipLine.Size = UDim2.fromOffset(w - 2 * (pad + 2), k.LineRows * (m.Line + 3))
	refs.ChipLine.TextSize = m.Line
	refs.ChipKey.Visible = m.Key > 0
	refs.ChipKey.Size = UDim2.fromOffset(m.Key, m.Key)
	refs.ChipKey.Position = UDim2.fromOffset(w - pad - m.Key, pad + 1)
	refs.ChipGlyph.Size = UDim2.fromOffset(m.Title + 6, m.Title + 6)
	refs.ChipGlyph.Position = UDim2.fromOffset(w - pad - (m.Title + 6), pad - 2)
	-- the top rows open the panel, SEND sends
	refs.ChipOpen.Size = UDim2.fromOffset(w, k.SendTop - 2)
	local send = holderOf(refs.ChipSend)
	send.AnchorPoint = Vector2.new(0, 0)
	send.Size = UDim2.fromOffset(w - 2 * pad, math.max(m.SendHeight, h - k.SendTop - k.Bottom - 4))
	send.Position = UDim2.fromOffset(pad, k.SendTop)
	refs.ChipSend.TextSize = m.SendText
end

local function placeChip(refs: Refs, m: ChipMetrics)
	if TrainView.chipStacked() then
		placeStack(refs, m)
		return
	end
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
	refs.Chip.DisplayOrder = if TrainView.HudChipLeft and TrainView.HudChipTop then TrainView.UnderHudOrder else TrainView.ChipOrder
	placeChip(refs, chipMetrics(compact))
	refs.ChipFrame.Position = UDim2.fromOffset(TrainView.chipLeft(compact), TrainView.chipTop())

	local m = if compact then PANEL.Compact else PANEL.Normal
	local width = math.max(620, math.min(m.Width, maxWidth - 24))
	local minHeight = TrainView.MinPanelHeight
	local height = math.max(minHeight, math.min(m.Height, maxHeight - 16))
	local top: number
	if compact then
		-- phones: at the bottom of the screen, over the backpack button; under the HUD coins when it fits
		local below = maxHeight - TrainView.CoinsBottom - 8
		if below >= minHeight then
			height = math.min(m.Height, below)
		end
		refs.Panel.AnchorPoint = Vector2.new(0.5, 1)
		refs.Panel.Position = UDim2.new(0.5, 0, 1, -8)
		top = maxHeight - 8 - height
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
		top = (maxHeight - height) / 2
	end
	refs.Panel.Size = UDim2.fromOffset(width, height)
	-- does it lie over HudView's coins panel (16, 16, CoinsWidth x 74)?
	local left = (maxWidth - width) / 2
	refs.CoversCoins = left < 16 + HudView.CoinsWidth and top < 16 + 74

	-- header: title, your coins, close; the subtitle under them (not on phones)
	local closeSize = m.Close
	-- (PC: a slim pill above the subtitle line; phones: as tall as the close button's face)
	local pillHeight = if compact then closeSize - 14 else 34
	local balance = refs.Balance
	balance.Size = UDim2.fromOffset(m.Balance, pillHeight)
	balance.Position = UDim2.new(1, -(PAD + closeSize + 10), 0, if compact then 16 else 10)
	local iconSize = pillHeight - 12
	refs.BalanceIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	refs.BalanceIcon.Position = UDim2.fromOffset(8, 6)
	refs.BalanceAmount.Position = UDim2.fromOffset(8 + iconSize + 8, 0)
	refs.BalanceAmount.Size = UDim2.new(1, -(8 + iconSize + 8 + 8), 1, 0)
	refs.BalanceAmount.TextSize = if compact then m.Text + 4 else m.Text + 2
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 20 else 8)
	refs.Title.Size = UDim2.new(1, -(PAD * 2 + closeSize + 10 + m.Balance + 10), 0, m.Title + 6)
	refs.Title.TextSize = m.Title
	refs.Subtitle.Visible = not compact
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 46)
	refs.Subtitle.Size = UDim2.new(1, -(PAD * 2 + closeSize + 10), 0, 20)
	refs.Subtitle.TextSize = m.Small
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
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
	local tripHeight = math.max(0, cardHeight - 14 - m.Button - 8 - tripTop)
	refs.Trip.Size = UDim2.new(1, -28, 0, tripHeight)
	refs.Trip.TextSize = m.Small
	-- PC: three lines of explanation; phones: one short line (setUpgrades), or none when short
	refs.Trip.Visible = tripHeight >= (m.Small + 4) * (if compact then 1 else 3)

	-- right: the upgrade rows (+ the hint under them on PC); short panels get
	-- lower rows, never lower than the buttons
	local rowsLeft = PAD + m.Card + PAD
	local rowsWidth = width - rowsLeft - PAD
	local room = height - m.Header - PAD - (if compact then 0 else 28)
	local rowHeight = math.max(m.Button + 12, math.min(m.Row, (room - GAP * 2) / 3))
	local narrow = TrainView.isNarrow(m, rowsWidth)
	local rows = refs.Rows.Capacity.Frame.Parent :: Frame
	rows.Position = UDim2.fromOffset(rowsLeft, m.Header)
	rows.Size = UDim2.new(1, -(rowsLeft + PAD), 0, rowHeight * 3 + GAP * 2)
	for _, row in { refs.Rows.Capacity, refs.Rows.Speed, refs.Express } do
		placeRow(row, m, rowHeight, narrow)
	end
	refs.Hint.Visible = not compact
	refs.Hint.Position = UDim2.fromOffset(rowsLeft, m.Header + rowHeight * 3 + GAP * 2 + 6)
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
	refs.ChipFill.BackgroundColor3 = if status.Phase == "Waiting"
		then Theme.Bad
		elseif progress then Theme.Info
		elseif status.Phase == "Full" then Theme.Good
		else Theme.Accent
	style(refs.ChipSend, status.CanSend, Theme.Good, Theme.GoodDark)

	refs.Cargo.Text = `{status.Cargo} / {status.Capacity}`
	refs.CargoUnit.Text = status.Unit
	refs.CargoFill.Size = UDim2.fromScale(status.Fill, 1)
	local fill = if status.Phase == "Waiting" then Theme.Bad elseif status.Phase == "Full" then Theme.Good else Theme.Accent
	if refs.Gui:GetAttribute("PopSkin") then
		-- the Pop look: a glossy painted fill (its white background takes the paint)
		Pop.repaint(refs.CargoFill, popPaintOf(fill), true)
		refs.CargoFill.Visible = status.Fill > 0.001
		syncShadow(refs.Cargo)
	else
		refs.CargoFill.BackgroundColor3 = fill
	end
	refs.State.Text = status.Line
	refs.State.TextColor3 = status.Color
	style(refs.Send, status.CanSend, Theme.Good, Theme.GoodDark)
end

-- The trip line and the two upgrade rows.
function TrainView.setUpgrades(refs: Refs, train: Snapshot, coins: number)
	local auto = TrainConfig.AutoDepartSeconds
	local trip = `Trip {TrainView.seconds(train.TripSeconds)} to your base.`
	refs.Trip.Text = if refs.Compact then trip else `{trip} It leaves when full, when you send it, or {auto} s after the last load.`
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
	if refs.Gui:GetAttribute("PopSkin") then
		-- the Pop look: the Express card's chip says what its green Robux button can't
		express.Level.Text = if train.Express then "OWNED" else "SOON"
		express.Level.BackgroundColor3 = if train.Express then Color3.fromRGB(60, 190, 40) else Color3.fromRGB(246, 166, 20)
	end
end

-- Your coins in the panel's header.
function TrainView.setCoins(refs: Refs, coins: number)
	local text = Format.money(math.max(0, coins))
	if refs.BalanceAmount.Text ~= text then
		refs.BalanceAmount.Text = text
	end
end

function TrainView.setColor(refs: Refs, color: Color3)
	TrainView.setIconColor(refs.ChipIcon, color)
	TrainView.setIconColor(refs.CardIcon, color)
	-- the Pop look: the card's live locomotive in your banner colour (only when it changes)
	local picture = refs.Card:FindFirstChild("Picture")
	local view = if picture then picture:FindFirstChild("View") else nil
	if view and view:IsA("ViewportFrame") and view:GetAttribute("Color") ~= color then
		local ok, model = pcall(TrainBuilder.locomotive, color)
		if ok then
			Pop.show(view, model :: Model, TRAIN_FROM)
			view:SetAttribute("Color", color)
		end
	end
end

---------------------------------------------------------------- the Pop look (UIConfig.LightUI)
--[[
	While the light UI is on (it ships on), the panel wears the bright Pop
	look of the Robux Shop (UI/Pop; owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"): a blue header band (the window's
	colour) with shine stripes and studs over a dark studded body, the
	bright cargo card with the live locomotive (PictureModels "train") in a
	light burst, the bar / state / trip lines in a dark well, a big green
	SEND TRAIN, painted CAPACITY and SPEED cards with gold coin BUY buttons
	and the Express card with the green Robux button (Pop.price's look). The
	same instances, names and refs as the dark build: the controller and
	the specs drive both (the HUD chip: pixelChip, below).
]]

TrainView.PopPaints = {
	Header = "Blue", -- (LightSkin.BandRoles: TerraForgeTrainPanel = Lobby)
	Cargo = "Yellow",
	Capacity = "Purple",
	Speed = "Teal",
	Express = "Pink",
} :: { [string]: string }

-- A sparkle-and-rays card face on an old frame: the paint, a light burst
-- (a "Burst" frame to place: popLayout), the studs, the light rim. The
-- frame's own children move above the decoration.
local function popCard(frame: Frame, paint: string, corner: number, rays: boolean): Frame
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		elseif child:IsA("GuiObject") then
			child.ZIndex = math.max(child.ZIndex, 5)
		end
	end
	local round = frame:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, corner)
	end
	Pop.face(frame, paint, corner, false)
	frame.ClipsDescendants = true
	local p = Pop.paint(paint)
	local burst = UIKit.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 1,
	}, frame)
	if rays then
		local made = Pop.fx(burst, "fx_rays", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			ImageTransparency = 0.35,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(560, 560),
			ZIndex = 1,
		})
		if not made then
			Pop.rays(burst, UDim2.fromScale(0.5, 0.5), 10, 280, 0.6, 1)
		end
	end
	local glow = Pop.fx(burst, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = if rays then 0.3 else 0.55,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(170, 170),
		ZIndex = 1,
	})
	if not glow then
		local disc = UIKit.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(110, 110),
			ZIndex = 1,
		}, burst)
		UIKit.corner(disc, 999)
	end
	Pop.studs(frame, corner, 0.5, 44, 2)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	-- three sparkles (fixed spots: the same every build)
	for i, spot in { { 0.12, 0.2, 22 }, { 0.86, 0.16, 18 }, { 0.7, 0.78, 14 } } do
		Pop.sparkle(frame, UDim2.fromScale(spot[1], spot[2]), spot[3], 3, 0.15 + i * 0.1)
	end
	return burst
end

-- A level chip (UIKit.chip) as a Pop chip: a dark well, a black edge, white words.
local function popChip(chip: TextLabel)
	chip.BackgroundColor3 = PopTheme.Well
	chip.BackgroundTransparency = 0
	for _, child in chip:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Color = PopTheme.Outline
			child.Thickness = 2.5
		end
	end
	popText(chip)
end

-- The header band of the window's colour (Pop.window's look) behind the title.
local function popBand(panel: Frame, paint: string): Frame
	local band = UIKit.new("Frame", {
		Name = "PopHeader",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 62),
		ClipsDescendants = true,
		ZIndex = 2,
	}, panel)
	Pop.face(band, paint, 6, false)
	local border = band:FindFirstChild("Border") :: UIStroke?
	if border then
		border.Thickness = 3
	end
	Pop.studs(band, 6, 0.35, 40, 2)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 2,
	}, band)
	for i, s in { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = 2,
		}, band)
	end
	return band
end

local function popSkin(refs: Refs)
	refs.Gui:SetAttribute("PopSkin", true)
	local panel = refs.Panel
	-- the window: a black frame round a dark studded body, the bright header band
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	local body = panel:FindFirstChildOfClass("UIGradient")
	if body then
		body.Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom)
	end
	local outline = panel:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = PopTheme.Outline
		outline.Thickness = 4
	end
	local round = panel:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	end
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = 4
		end
	end
	Pop.studs(panel, PopTheme.WindowCorner, 0.5, 36, 1)
	popBand(panel, TrainView.PopPaints.Header)
	popText(refs.Title)
	Pop.shadow(refs.Title).ZIndex = 3
	popText(refs.Subtitle)
	popText(refs.Hint)
	-- your coins: a dark pill
	refs.Balance.BackgroundColor3 = PopTheme.Well
	for _, child in refs.Balance:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = PopTheme.Outline
			child.Thickness = 3
		end
	end
	popText(refs.BalanceAmount)
	refs.BalanceAmount.TextColor3 = PopTheme.MoneyNumber
	popButton(refs.Close, PopTheme.Close)
	refs.Close.FontFace = PopTheme.Heavy

	-- the cargo card: bright, the live locomotive in a light burst
	popCard(refs.Card, TrainView.PopPaints.Cargo, 12, true)
	local model, from = PictureModels.build("train")
	local picture = Pop.model(refs.Card, "train", 120, model, { Name = "Picture", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }, from)
	local view = picture:FindFirstChild("View")
	if view then
		view:SetAttribute("Color", Color3.fromRGB(226, 72, 60)) -- (PictureModels' red; setColor repaints it)
	end
	refs.CardIcon.Visible = false
	popText(refs.CardLabel)
	popText(refs.Cargo, PopTheme.Heavy)
	Pop.shadow(refs.Cargo).ZIndex = 4
	popText(refs.CargoUnit)
	popText(refs.Trip)
	popEdge(refs.State)
	-- the bar, the state and the trip lines sit in a dark well (the state keeps its colour)
	local well = UIKit.new("Frame", {
		Name = "PopWell",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, refs.Card)
	UIKit.corner(well, 10)
	Pop.border(well, 3)
	Pop.studs(well, 10, 0.6, 36, 4)
	-- the glossy cargo bar (Pop.bar's look)
	local track = refs.CargoBar
	track.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	for _, child in track:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = PopTheme.Outline
			child.Thickness = 3
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(1, 0)
		end
	end
	local fillCorner = refs.CargoFill:FindFirstChildOfClass("UICorner")
	if fillCorner then
		fillCorner.CornerRadius = UDim.new(1, 0)
	end
	Pop.face(refs.CargoFill, "Orange", 8, true, false)
	local fillBorder = refs.CargoFill:FindFirstChild("Border")
	if fillBorder then
		fillBorder:Destroy()
	end
	popButton(refs.Send, "Green")
	refs.Send.FontFace = PopTheme.Heavy

	-- the upgrade cards: painted, a gold coin BUY; Express: the green Robux button
	local rows: { [string]: Row } = { Capacity = refs.Rows.Capacity, Speed = refs.Rows.Speed, Express = refs.Express }
	for kind, row in rows do
		local burst = popCard(row.Frame, TrainView.PopPaints[kind], 12, false)
		burst.Position = UDim2.fromScale(0.2, 0.5)
		popText(row.Name)
		popChip(row.Level)
		popText(row.Detail)
		row.Price.Visible = false -- (the price is on the button)
		popButton(row.Buy, if kind == "Express" then PopTheme.Price else "Yellow", if kind == "Express" then "Robux" else "Coin")
		pcall(function()
			-- (the controller writes "…" / "BOUGHT!" on the button: its face follows)
			row.Buy:GetPropertyChangedSignal("Text"):Connect(function()
				syncFace(row.Buy)
			end)
		end)
	end
	-- the Express card's chip says SOON / OWNED (setUpgrades)
	refs.Express.Level.Visible = true
	refs.Express.Level.Text = "SOON"
	refs.Express.Level.BackgroundColor3 = Color3.fromRGB(246, 166, 20)
	style(refs.Express.Buy, false, Theme.Good, Theme.GoodDark)
end

-- Places the Pop pieces the dark layout doesn't know (after TrainView.layout).
local function popLayout(refs: Refs)
	local m = if refs.Compact then PANEL.Compact else PANEL.Normal
	local band = refs.Panel:FindFirstChild("PopHeader") :: Frame?
	if band then
		band.Size = UDim2.new(1, -8, 0, m.Header - 10)
	end
	popEdge(refs.Title)
	syncShadow(refs.Title)
	refs.Close.TextSize = math.floor(m.Close * 0.6)
	popEdge(refs.Close)
	popEdge(refs.BalanceAmount)
	local pill = refs.Balance:FindFirstChildOfClass("UICorner")
	if pill then
		pill.CornerRadius = UDim.new(0, math.floor(refs.Balance.Size.Y.Offset / 2))
	end
	-- the cargo card: the picture where the old icon was, bigger, in its light burst
	local icon = refs.CardIcon
	local iw, ih = icon.Size.X.Offset, icon.Size.Y.Offset
	local size = math.floor(iw * 1.16)
	local centre = UDim2.fromOffset(icon.Position.X.Offset + iw / 2 - 2, icon.Position.Y.Offset + ih / 2 + 4)
	local picture = refs.Card:FindFirstChild("Picture") :: ImageLabel?
	if picture then
		picture.Position = centre
		picture.Size = UDim2.fromOffset(size, size)
	end
	local burst = refs.Card:FindFirstChild("Burst") :: Frame?
	if burst then
		burst.Position = centre
	end
	local labels: { GuiObject } = { refs.CardLabel, refs.Cargo, refs.CargoUnit, refs.State, refs.Trip, refs.Send }
	for _, label in labels do
		popEdge(label)
	end
	syncShadow(refs.Cargo)
	local well = refs.Card:FindFirstChild("PopWell") :: Frame?
	if well then
		local top = refs.CargoBar.Position.Y.Offset - 7
		local sendTop = refs.Card.Size.Y.Offset - 14 - m.Button
		well.Position = UDim2.fromOffset(8, top)
		well.Size = UDim2.new(1, -16, 0, math.max(0, sendTop - 8 - top))
	end
	-- the cards: the price is on the button, so the level chip moves up to it and
	-- the name and the detail get the room (a long name gets a little smaller)
	local right = 12 + m.Buy + 12
	local chipWidth = chipWidthOf(m)
	for _, row in { refs.Rows.Capacity, refs.Rows.Speed, refs.Express } do
		row.Level.Position = UDim2.new(1, -(right + 4), 0, row.Level.Position.Y.Offset)
		-- (the rows frame is the panel's width less its Offset: design units)
		local rowsWidth = (row.Frame.Parent :: Frame).Size.X.Offset + refs.Panel.Size.X.Offset
		local nameRoom = rowsWidth - (14 + right + 4 + chipWidth + 8)
		row.Name.Size = UDim2.new(1, -(14 + right + 4 + chipWidth + 8), 0, row.Name.Size.Y.Offset)
		local chars = math.max(1, utf8.len(row.Name.Text) or #row.Name.Text)
		row.Name.TextSize = math.max(14, math.min(row.Name.TextSize, math.floor(nameRoom / (chars * 0.62))))
		row.Detail.Size = UDim2.new(1, -(14 + right), 0, row.Detail.Size.Y.Offset)
		local texts: { GuiObject } = { row.Name, row.Level, row.Detail, row.Buy }
		for _, label in texts do
			popEdge(label)
		end
		syncFace(row.Buy)
	end
end

--[[
	The HUD chip in the pixel reels' look (owner 2026-10-22): a small reel
	button (a slate painted face with the thick black outline, the lip and
	the lattice), the locomotive in a blue painted square at its left end,
	TRAIN 5/8 in white pixel letters with a black edge, the line under it,
	the trip / cargo bar in a dark well with a glossy fill, the green SEND as
	a painted reel button (TrainView.style repaints it: grey when it can't
	go). The same instances and names as the dark build: the controller and
	the specs drive both.
]]
TrainView.ChipPaints = { Face = "Slate", Icon = "Blue", Send = "Green" } :: { [string]: string }

local function stripLook(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

local function pixelChip(refs: Refs)
	refs.Chip:SetAttribute("PopSkin", true)
	local frame = refs.ChipFrame
	stripLook(frame)
	-- (the bigger phone size first: the lattice reaches every corner of both sizes)
	frame.Size = UDim2.fromOffset(CHIP.Compact.Width, CHIP.Compact.Height)
	Pop.face(frame, TrainView.ChipPaints.Face, 12)
	Pop.studs(frame, 12, 0.45, 28, 1)
	local square = UIKit.new("Frame", { Name = "IconSquare", ZIndex = 1 }, frame)
	square.Size = UDim2.fromOffset(60, 60)
	Pop.face(square, TrainView.ChipPaints.Icon, 10, true, false)
	local squareBorder = square:FindFirstChild("Border") :: UIStroke?
	if squareBorder then
		squareBorder.Thickness = 2.5
	end
	Pop.studs(square, 10, 0.45, 20, 1)
	refs.ChipIcon.ZIndex = 2
	for _, d in refs.ChipIcon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 2)
		end
	end
	popText(refs.ChipTitle, PopTheme.Pixel)
	popEdge(refs.ChipLine)
	-- the bar: a dark well and a glossy fill (setStatus colours it)
	refs.ChipBar.BackgroundColor3 = PopTheme.Well
	for _, child in refs.ChipBar:GetChildren() do
		if child:IsA("UIStroke") then
			child.Color = PopTheme.Outline
			child.Thickness = 2
		end
	end
	UIKit.new("UIGradient", {
		Name = "Gloss",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 235, 235)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)),
		}),
	}, refs.ChipFill)
	-- SEND: a painted reel button (style() repaints it from the state)
	popButton(refs.ChipSend, TrainView.ChipPaints.Send)
	refs.ChipSend.FontFace = PopTheme.Pixel
	Pop.fxTag(holderOf(refs.ChipSend), "Press")
	-- the "T" key cap: a dark well with a pixel letter
	local key = refs.ChipKey
	key.BackgroundColor3 = PopTheme.Well
	key.FontFace = PopTheme.Pixel
	key.TextColor3 = PopTheme.Ink
	for _, child in key:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Color = PopTheme.Outline
		end
	end
	popEdge(key)
end

-- A narrow chip's line shrinks to fit its box (never under `floor`, default 9) rather than running out of it.
local function shrinkLine(label: TextLabel, size: number, floor: number?)
	label.TextScaled = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = label:FindFirstChild("Fit") :: UITextSizeConstraint?
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	l.MaxTextSize = size
	l.MinTextSize = math.min(size, floor or 9)
end

-- The stacked pixel chip (under the round look's tiles): the locomotive in its square with
-- the name and the bar beside it, the line under them, SEND across the bottom above the lip.
local function pixelStackLayout(refs: Refs, m: ChipMetrics, area: number)
	local k = stackRows()
	local pad, s = k.Pad, k.Square
	local square = refs.ChipFrame:FindFirstChild("IconSquare") :: Frame?
	if square then
		square.Visible = s > 0
		square.Position = UDim2.fromOffset(pad, pad)
		square.Size = UDim2.fromOffset(s, s)
	end
	refs.ChipIcon.Visible = s > 0
	local iw = math.max(s - 6, 0)
	local ih = iw / ICON_ASPECT
	refs.ChipIcon.Size = UDim2.fromOffset(iw, ih)
	refs.ChipIcon.Position = UDim2.fromOffset(pad + 3, pad + math.floor((s - ih) / 2))
	local textLeft = if s > 0 then pad + s + 6 else pad + 2
	local titleH = math.floor(m.Title * PopTheme.PixelScale + 0.5) + 4
	local keyRoom = m.Key + 4 -- (the T key or the gamepad's glyph right of the name)
	refs.ChipTitle.Position = UDim2.fromOffset(textLeft, pad + 2)
	refs.ChipTitle.Size = UDim2.fromOffset(m.Width - textLeft - pad - keyRoom, k.TitleRows * titleH)
	if k.TitleRows > 1 then
		-- (a TV: "TRAIN" / "120/180" on two rows, never under TitleMin)
		refs.ChipTitle.TextWrapped = true
		shrinkLine(refs.ChipTitle, m.Title, k.TitleMin)
	else
		refs.ChipTitle.TextWrapped = false
		Pop.fit(refs.ChipTitle, m.Title)
	end
	refs.ChipTitle.TextXAlignment = Enum.TextXAlignment.Left
	local lineTop, sendTop = k.LineTop, k.SendTop
	if k.BarTop > 0 then
		-- (a TV: the bar under the name's two rows, the line and SEND under it)
		local barTop = math.min(k.BarTop, pad + 2 + k.TitleRows * titleH + 4)
		refs.ChipBar.Position = UDim2.fromOffset(pad + 2, barTop)
		refs.ChipBar.Size = UDim2.fromOffset(m.Width - 2 * (pad + 2), 7)
		lineTop = barTop + 7 + 4
		sendTop = lineTop + k.LineRows * (m.Line + 2) + 4
	else
		refs.ChipBar.Position = UDim2.fromOffset(textLeft, pad + 2 + titleH + 4)
		refs.ChipBar.Size = UDim2.fromOffset(m.Width - textLeft - pad, 7)
	end
	refs.ChipLine.Position = UDim2.fromOffset(pad + 2, lineTop)
	refs.ChipLine.Size = UDim2.fromOffset(m.Width - 2 * (pad + 2), k.LineRows * (m.Line + 2))
	refs.ChipLine.TextXAlignment = Enum.TextXAlignment.Left
	refs.ChipLine.TextWrapped = k.LineRows > 1 -- (a TV: a long line goes on two rows, not smaller)
	shrinkLine(refs.ChipLine, m.Line, if k.LineRows > 1 then m.Line else nil)
	-- SEND across the bottom, above the lip
	local send = holderOf(refs.ChipSend)
	send.AnchorPoint = Vector2.new(0, 0)
	send.Position = UDim2.fromOffset(pad, sendTop)
	send.Size = UDim2.fromOffset(m.Width - 2 * pad, math.max(20, area - sendTop - k.Bottom))
	Pop.face(send, TrainView.ChipPaints.Send, if PopTheme.round() then PopTheme.Corner else 10)
	TrainView.style(refs.ChipSend, refs.ChipSend.BackgroundColor3 ~= Theme.PanelLight, Theme.Good, Theme.GoodDark)
	Pop.fit(refs.ChipSend :: any, m.SendText)
end

-- Places the pixel chip's parts for its size (after placeChip): everything
-- centred on the face above the lip, the locomotive in its square.
local function pixelChipLayout(refs: Refs)
	local m = chipMetrics(refs.Compact)
	local frame = refs.ChipFrame
	if PopTheme.round() then
		-- the round look: a dark tile like the reel's left tiles, the train's blue in its lip and edge
		Pop.darkTile(frame, "Blue", PopTheme.Corner + 1)
		local corner = frame:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, PopTheme.Corner + 1)
		end
	else
		Pop.face(frame, TrainView.ChipPaints.Face, 12)
	end
	local lip = Pop.lipUnits(m.Height)
	local area = m.Height - lip
	if TrainView.chipStacked() then
		pixelStackLayout(refs, m, area)
		return
	end
	-- the square and the locomotive in it
	local s = area - 12
	local square = frame:FindFirstChild("IconSquare") :: Frame?
	if square then
		square.Position = UDim2.fromOffset(7, math.floor((area - s) / 2))
		square.Size = UDim2.fromOffset(s, s)
	end
	local iw = s - 8
	local ih = iw / ICON_ASPECT
	refs.ChipIcon.Size = UDim2.fromOffset(iw, ih)
	refs.ChipIcon.Position = UDim2.fromOffset(11, math.floor((area - ih) / 2))
	-- title, line and bar as one block in the middle
	local titleH = math.floor(m.Title * PopTheme.PixelScale + 0.5) + 4
	local lineH = m.Line + 2
	local barH = if refs.Compact then 9 else 7
	local y0 = math.floor((area - (titleH + lineH + 3 + barH)) / 2)
	local textLeft = refs.ChipTitle.Position.X.Offset
	refs.ChipTitle.Position = UDim2.fromOffset(textLeft, y0)
	refs.ChipTitle.Size = UDim2.fromOffset(refs.ChipTitle.Size.X.Offset, titleH)
	Pop.fit(refs.ChipTitle, m.Title)
	refs.ChipTitle.TextXAlignment = Enum.TextXAlignment.Left
	refs.ChipLine.Position = UDim2.fromOffset(textLeft, y0 + titleH)
	refs.ChipLine.Size = UDim2.fromOffset(refs.ChipLine.Size.X.Offset, lineH)
	if TrainView.HudChipWidth and TrainView.HudChipTop then
		shrinkLine(refs.ChipLine, m.Line) -- (as wide as the tiles: narrower than its own width)
	end
	refs.ChipBar.Position = UDim2.fromOffset(textLeft, y0 + titleH + lineH + 3)
	refs.ChipBar.Size = UDim2.fromOffset(refs.ChipBar.Size.X.Offset, barH)
	refs.ChipKey.Position = UDim2.fromOffset(refs.ChipKey.Position.X.Offset, y0)
	refs.ChipGlyph.Position = UDim2.fromOffset(refs.ChipGlyph.Position.X.Offset, y0 - 1)
	-- SEND centred on the face above the lip
	local send = holderOf(refs.ChipSend)
	send.Position = UDim2.new(1, -10, 0, math.max(0, math.floor((area - m.SendHeight) / 2)))
	Pop.face(send, TrainView.ChipPaints.Send, if PopTheme.round() then PopTheme.Corner else 10)
	TrainView.style(refs.ChipSend, refs.ChipSend.BackgroundColor3 ~= Theme.PanelLight, Theme.Good, Theme.GoodDark)
	Pop.fit(refs.ChipSend :: any, m.SendText)
end

local plainLayout = TrainView.layout
TrainView.layout = function(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	plainLayout(refs, compact, maxWidth, maxHeight)
	if refs.Gui:GetAttribute("PopSkin") then
		popLayout(refs)
	end
	if refs.Chip:GetAttribute("PopSkin") then
		pixelChipLayout(refs)
	end
end

local darkBuild = TrainView.build
TrainView.build = function(compact: boolean?): Refs
	local refs = darkBuild(compact)
	if UIConfig.lightUI() then
		-- the HUD chip wears the pixel reels' look, the panel the Pop look
		pixelChip(refs)
		TouchControls.follow(refs.Gui)
		popSkin(refs)
		TrainView.layout(refs, compact == true, math.huge, math.huge)
	end
	return refs
end

return TrainView
