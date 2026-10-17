--[[
	The mine elevator on screen (pure builder + pure helpers; ElevatorController
	fills it in). One panel with two pages:

	  Buy      (not owned) "ELEVATOR", "Ride to every floor you have unlocked.
	           Buy once, keep forever.", a strip of the floors (4 and 5 marked
	           "elevator only"), the price (Format.money) and a BUY button that
	           is greyed out while you can't afford it, with "You have $X. You
	           need $Y more." under it
	  Floors   (owned) a card per floor, 3 x 2: the floor number in the
	           floor's crystal colour, its name, a "Blaster 7+" chip (green
	           when your blaster is enough, red when not), "Elevator only" on
	           floors 4-5, and the card's button: GO / LOCKED / YOU ARE HERE /
	           COMING SOON (the sixth card is MineFloors.ComingSoon)
	  X (and B / Backspace in the controller) closes it; messages from the
	  server show in the header (HUD toasts hide behind the panel).

	A second ScreenGui (buildFade) darkens the screen during a ride and shows
	"FLOOR 4" + the floor's name.

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). The compact layout (phones, uiScale 0.62) has 72-unit
	buttons (about 44 pt) and fits the panel into what the screen leaves
	(ElevatorView.layout). A gamepad selection stays inside the panel
	(SelectionGroup); only the buttons that do something are selectable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)

local ElevatorView = {}

export type Mode = "Buy" | "Floors"
export type FloorState = "Open" | "Locked" | "Here" | "Soon"

export type FloorEntry = {
	Index: number,
	Name: string,
	MinBlaster: number,
	Requirement: string, -- "Blaster 7+"
	Met: boolean, -- the blaster is enough
	State: FloorState,
	ElevatorOnly: boolean,
	Color: Color3, -- the floor's crystal colour (number badge)
}

export type Card = {
	Index: number,
	Frame: Frame,
	Stroke: UIStroke,
	Badge: Frame,
	Number: TextLabel,
	Name: TextLabel,
	Chip: TextLabel,
	Tag: TextLabel,
	Button: TextButton,
	Entry: FloorEntry,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Message: TextLabel, -- the last server message (instead of the subtitle)
	Close: TextButton,
	-- the Buy page
	BuyPage: Frame,
	Pitch: TextLabel,
	Strip: Frame,
	Tiles: { Frame },
	Caption: TextLabel,
	PriceBox: Frame,
	Coin: Frame,
	Price: TextLabel,
	BuyButton: TextButton,
	Note: TextLabel,
	-- the Floors page
	FloorPage: Frame,
	Cards: { Card },
	Hint: TextLabel,
	Mode: Mode,
	Compact: boolean,
	CanAfford: boolean,
	MaxWidth: number, -- the room the last layout got (design units)
	MaxHeight: number,
	Level: number, -- the blaster level the cards were filled for
}

export type Fade = {
	Gui: ScreenGui,
	Black: Frame,
	Title: TextLabel,
	Name: TextLabel,
}

type Metrics = {
	BuyWidth: number,
	FloorWidth: number,
	FloorHeight: number,
	Header: number,
	Title: number,
	Text: number,
	Pitch: number,
	Tile: number,
	Button: number,
	CardName: number,
	Badge: number,
	Close: number,
	Price: number,
	Gap: number,
}

local PAD = 16
local COLUMNS = 3

local METRICS: { [string]: Metrics } = {
	Normal = {
		BuyWidth = 620,
		FloorWidth = 880,
		FloorHeight = 520,
		Header = 92,
		Title = 40,
		Text = 18,
		Pitch = 22,
		Tile = 62,
		Button = 56,
		CardName = 21,
		Badge = 58,
		Close = 54,
		Price = 46,
		Gap = 12,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		BuyWidth = 820,
		FloorWidth = 1000,
		FloorHeight = 490,
		Header = 84,
		Title = 36,
		Text = 20,
		Pitch = 24,
		Tile = 66,
		Button = 72,
		CardName = 24,
		Badge = 62,
		Close = 64,
		Price = 50,
		Gap = 12,
	},
}

ElevatorView.Title = "ELEVATOR"
ElevatorView.Pitch = "Ride to every floor you have unlocked. Buy once, keep forever."
ElevatorView.LockedColor = Color3.fromRGB(96, 84, 78)
ElevatorView.SoonColor = Color3.fromRGB(70, 60, 74)

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

function ElevatorView.requirementText(minBlaster: number): string
	return `Blaster {minBlaster}+`
end

-- The line under the Buy button.
function ElevatorView.noteText(coins: number, price: number): string
	local have = if type(coins) == "number" and coins == coins then math.max(coins, 0) else 0
	if have >= price then
		return `You have {Format.money(have)}.`
	end
	return `You have {Format.money(have)}. You need {Format.money(price - have)} more.`
end

function ElevatorView.canAfford(coins: any, price: number): boolean
	return type(coins) == "number" and coins == coins and coins >= price
end

--[[
	The six cards: MineFloors.List in order, then the "Coming soon" floor.
	`level` = the player's blaster level, `here` = the floor of the stop the
	player stands at (nil = none of them).
]]
function ElevatorView.entries(level: any, here: number?): { FloorEntry }
	local blaster = if type(level) == "number" and level == level then level else 1
	local list: { FloorEntry } = {}
	for _, floor in MineFloors.List do
		local met = blaster >= floor.MinBlaster
		local state: FloorState = if floor.Index == here then "Here" elseif met then "Open" else "Locked"
		table.insert(list, {
			Index = floor.Index,
			Name = floor.Name,
			MinBlaster = floor.MinBlaster,
			Requirement = ElevatorView.requirementText(floor.MinBlaster),
			Met = met,
			State = state,
			ElevatorOnly = floor.ViaElevator,
			Color = floor.Palette.Crystal,
		})
	end
	local soon = MineFloors.ComingSoon
	table.insert(list, {
		Index = soon.Index,
		Name = "Coming soon",
		MinBlaster = soon.MinBlaster,
		Requirement = ElevatorView.requirementText(soon.MinBlaster),
		Met = false,
		State = "Soon",
		ElevatorOnly = true,
		Color = ElevatorView.SoonColor,
	})
	return list
end

-- "Floors 4 and 5 can only be reached by elevator." (from MineFloors ViaElevator)
function ElevatorView.captionText(): string
	local only: { string } = {}
	for _, floor in MineFloors.List do
		if floor.ViaElevator then
			table.insert(only, tostring(floor.Index))
		end
	end
	if #only == 0 then
		return "Skip the walk to any floor you have unlocked."
	elseif #only == 1 then
		return `Floor {only[1]} can only be reached by elevator.`
	end
	local last = table.remove(only)
	return `Floors {table.concat(only, ", ")} and {last} can only be reached by elevator.`
end

-- The line under the title.
function ElevatorView.subtitleText(mode: Mode, level: number): string
	if mode == "Buy" then
		return "Every mine floor, one ride away."
	end
	return `Your blaster: Lv {level}. Forge better blasters to unlock deeper floors.`
end

-- The text on a card's button.
function ElevatorView.buttonText(state: FloorState): string
	if state == "Open" then
		return "GO"
	elseif state == "Here" then
		return "YOU ARE HERE"
	elseif state == "Soon" then
		return "COMING SOON"
	end
	return "LOCKED"
end

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

local function styleButton(button: TextButton, color: Color3, dark: Color3, textColor: Color3)
	button.BackgroundColor3 = color
	holderOf(button).BackgroundColor3 = dark
	button.TextColor3 = textColor
end

local function newTile(strip: Frame, index: number, color: Color3, text: string): Frame
	local tile = UIKit.new("Frame", {
		Name = "Tile" .. index,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, strip)
	UIKit.corner(tile, 12)
	UIKit.stroke(tile, 3)
	UIKit.gradient(tile, Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165))
	UIKit.label(tile, text, 30, {
		Name = "Number",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
	})
	return tile
end

local function newCard(page: Frame, entry: FloorEntry): Card
	local frame = UIKit.new("Frame", {
		Name = "Floor" .. entry.Index,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, page)
	UIKit.corner(frame, 14)
	local stroke = UIKit.stroke(frame, 3)
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
	}, frame)
	UIKit.corner(badge, 12)
	UIKit.stroke(badge, 3)
	UIKit.gradient(badge, Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160))
	local number = UIKit.label(badge, "", 34, {
		Name = "Number",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
	})
	local name = UIKit.label(frame, "", 21, {
		Name = "FloorName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	local chip = UIKit.chip(frame, "", Theme.GoodDark, {
		Name = "Requirement",
		TextSize = 15,
	})
	local tag = UIKit.label(frame, "", 15, {
		Name = "Tag",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local button = UIKit.button(frame, "GO", Theme.Good, Theme.GoodDark, {
		Name = "Go",
		TextSize = 24,
	})
	return {
		Index = entry.Index,
		Frame = frame,
		Stroke = stroke,
		Badge = badge,
		Number = number,
		Name = name,
		Chip = chip,
		Tag = tag,
		Button = button,
		Entry = entry,
	}
end

function ElevatorView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeElevator", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.BuyWidth, 420),
		Active = true,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})

	local title = UIKit.label(panel, ElevatorView.Title, 40, {
		Name = "Title",
		Position = UDim2.fromOffset(PAD + 2, 10),
		Size = UDim2.new(1, -(PAD * 2 + 80), 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	local subtitle = UIKit.label(panel, "", 18, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(PAD + 2, 54),
		Size = UDim2.new(1, -(PAD * 2 + 80), 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	local message = UIKit.label(panel, "", 18, {
		Name = "Message",
		Position = UDim2.fromOffset(PAD + 2, 54),
		Size = UDim2.new(1, -(PAD * 2 + 80), 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Bad,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Visible = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 14),
		Size = UDim2.fromOffset(54, 54),
		TextSize = 26,
	})

	-- the Buy page
	local buyPage = UIKit.new("Frame", {
		Name = "BuyPage",
		BackgroundTransparency = 1,
	}, panel)
	local pitch = UIKit.label(buyPage, ElevatorView.Pitch, 22, {
		Name = "Pitch",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local strip = UIKit.new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
	}, buyPage)
	UIKit.list(strip, Enum.FillDirection.Horizontal, 10, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local tiles: { Frame } = {}
	for _, floor in MineFloors.List do
		local tile = newTile(strip, floor.Index, floor.Palette.Crystal, tostring(floor.Index))
		if floor.ViaElevator then
			-- elevator-only floors get a gold rim (the caption says why)
			local rim = tile:FindFirstChildOfClass("UIStroke")
			if rim then
				rim.Color = Theme.Accent
				rim.Thickness = 4
			end
		end
		table.insert(tiles, tile)
	end
	table.insert(tiles, newTile(strip, MineFloors.ComingSoon.Index, ElevatorView.SoonColor, "?"))
	local caption = UIKit.label(buyPage, ElevatorView.captionText(), 18, {
		Name = "Caption",
		TextColor3 = Theme.TextDim,
	})
	local priceBox = UIKit.new("Frame", {
		Name = "PriceBox",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, buyPage)
	UIKit.corner(priceBox, 14)
	UIKit.stroke(priceBox, 3)
	local coin = UIKit.new("Frame", {
		Name = "Coin",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Coin,
		BorderSizePixel = 0,
	}, priceBox)
	UIKit.corner(coin, 100)
	UIKit.stroke(coin, 3)
	-- the inner ring of the coin (like the HUD's coin)
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1,
	}, coin)
	UIKit.corner(ring, 100)
	UIKit.stroke(ring, 3, Theme.AccentDark)
	local price = UIKit.label(priceBox, "", 46, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	local buyButton = UIKit.button(buyPage, "BUY", Theme.Good, Theme.GoodDark, {
		Name = "Buy",
		TextSize = 30,
		FontFace = Theme.TitleFont,
	})
	local note = UIKit.label(buyPage, "", 18, {
		Name = "Note",
		TextColor3 = Theme.TextDim,
	})

	-- the Floors page
	local floorPage = UIKit.new("Frame", {
		Name = "FloorPage",
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	local cards: { Card } = {}
	for _, entry in ElevatorView.entries(1, nil) do
		table.insert(cards, newCard(floorPage, entry))
	end

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		TextColor3 = Theme.TextDim,
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Message = message,
		Close = close,
		BuyPage = buyPage,
		Pitch = pitch,
		Strip = strip,
		Tiles = tiles,
		Caption = caption,
		PriceBox = priceBox,
		Coin = coin,
		Price = price,
		BuyButton = buyButton,
		Note = note,
		FloorPage = floorPage,
		Cards = cards,
		Hint = hint,
		Mode = "Buy",
		Compact = false,
		CanAfford = false,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
		Level = 1,
	}
	ElevatorView.setPurchase(refs, 0, MineFloors.Elevator.Price)
	ElevatorView.setFloors(refs, ElevatorView.entries(1, nil), 1)
	ElevatorView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- filling in

-- The Buy page: the price, the BUY button (greyed out when you can't afford it) and the note.
function ElevatorView.setPurchase(refs: Refs, coins: any, price: number)
	local afford = ElevatorView.canAfford(coins, price)
	refs.CanAfford = afford
	refs.Price.Text = Format.money(price)
	local have = if type(coins) == "number" then coins else 0
	refs.Note.Text = ElevatorView.noteText(have, price)
	refs.Note.TextColor3 = if afford then Theme.Good else Theme.TextDim
	if afford then
		styleButton(refs.BuyButton, Theme.Good, Theme.GoodDark, Theme.Text)
	else
		styleButton(refs.BuyButton, ElevatorView.LockedColor, Theme.PanelDark, Theme.TextDim)
	end
	refs.BuyButton.AutoButtonColor = false
	refs.BuyButton.Selectable = afford
end

local function fillCard(card: Card, entry: FloorEntry)
	card.Entry = entry
	local locked = entry.State == "Locked" or entry.State == "Soon"
	card.Number.Text = if entry.State == "Soon" then "?" else tostring(entry.Index)
	card.Badge.BackgroundColor3 = if locked then entry.Color:Lerp(ElevatorView.LockedColor, 0.6) else entry.Color
	card.Name.Text = entry.Name
	card.Name.TextColor3 = if locked then Theme.TextDim else Theme.Text
	card.Chip.Text = entry.Requirement
	card.Chip.BackgroundColor3 = if entry.State == "Soon" then Theme.PanelDark elseif entry.Met then Theme.GoodDark else Theme.BadDark
	card.Tag.Text = if entry.State == "Soon" then "Next update" elseif entry.ElevatorOnly then "Elevator only" else "Walk or ride"
	card.Tag.TextColor3 = if entry.ElevatorOnly and entry.State ~= "Soon" then Theme.Accent else Theme.TextDim
	card.Stroke.Color = if entry.State == "Here" then Theme.Accent else Theme.Outline
	card.Frame.BackgroundColor3 = if locked then Theme.Panel else Theme.PanelLight
	local button = card.Button
	button.Text = ElevatorView.buttonText(entry.State)
	if entry.State == "Open" then
		styleButton(button, Theme.Good, Theme.GoodDark, Theme.Text)
	elseif entry.State == "Here" then
		styleButton(button, Theme.PanelDark, Theme.Outline, Theme.Accent)
	else
		styleButton(button, ElevatorView.LockedColor, Theme.PanelDark, Theme.TextDim)
	end
	-- only GO moves you; a tap on LOCKED says why (the controller), the others do nothing
	button.Selectable = entry.State == "Open"
	button.AutoButtonColor = false
end

-- The Floors page: the cards and the blaster line in the header.
function ElevatorView.setFloors(refs: Refs, entries: { FloorEntry }, level: number)
	for i, card in refs.Cards do
		local entry = entries[i]
		if entry then
			fillCard(card, entry)
		end
	end
	refs.Level = level
	refs.Subtitle.Text = ElevatorView.subtitleText(refs.Mode, level)
end

-- Shows the Buy page or the Floors page.
function ElevatorView.setMode(refs: Refs, mode: Mode)
	refs.Mode = mode
	refs.BuyPage.Visible = mode == "Buy"
	refs.FloorPage.Visible = mode == "Floors"
	refs.Subtitle.Text = ElevatorView.subtitleText(mode, refs.Level)
	ElevatorView.layout(refs, refs.Compact, refs.MaxWidth, refs.MaxHeight)
end

-- The first GO button (for a gamepad selection), or nil when every floor is locked.
function ElevatorView.firstGo(refs: Refs): TextButton?
	for _, card in refs.Cards do
		if card.Entry.State == "Open" then
			return card.Button
		end
	end
	return nil
end

-- A message in the header (instead of the subtitle).
function ElevatorView.showMessage(refs: Refs, text: string, color: Color3)
	refs.Message.Text = text
	refs.Message.TextColor3 = color
	refs.Message.Visible = true
	refs.Subtitle.Visible = false
end

function ElevatorView.hideMessage(refs: Refs)
	refs.Message.Visible = false
	refs.Subtitle.Visible = true
end

---------------------------------------------------------------- layout

-- Places the Buy page; returns the height its content needs (from the page top).
local function layoutBuy(refs: Refs, m: Metrics, width: number): number
	local inner = width - PAD * 2
	local top = m.Header
	refs.BuyPage.Position = UDim2.fromOffset(PAD, top)
	refs.BuyPage.Size = UDim2.new(1, -PAD * 2, 1, -top)
	-- room for two lines (one line on wide panels sits in the middle of it)
	local pitchHeight = math.floor(m.Pitch * 2.5)
	refs.Pitch.Position = UDim2.fromOffset(4, 0)
	refs.Pitch.Size = UDim2.new(1, -8, 0, pitchHeight)
	refs.Pitch.TextSize = m.Pitch
	refs.Pitch.TextYAlignment = Enum.TextYAlignment.Center
	local y = pitchHeight + 6
	local tile = m.Tile
	refs.Strip.Position = UDim2.fromOffset(0, y)
	refs.Strip.Size = UDim2.new(1, 0, 0, tile + 12)
	for _, t in refs.Tiles do
		t.Size = UDim2.fromOffset(tile, tile)
	end
	y += tile + 18
	refs.Caption.Position = UDim2.fromOffset(0, y)
	refs.Caption.Size = UDim2.new(1, 0, 0, m.Text + 6)
	refs.Caption.TextSize = m.Text
	y += m.Text + 18
	-- price on the left, BUY on the right, the note under both
	local half = math.floor((inner - m.Gap) / 2)
	local boxHeight = m.Button + 18
	refs.PriceBox.Position = UDim2.fromOffset(0, y)
	refs.PriceBox.Size = UDim2.fromOffset(half, boxHeight)
	local coinSize = math.floor(boxHeight * 0.6)
	refs.Coin.Position = UDim2.new(0, 14, 0.5, 0)
	refs.Coin.Size = UDim2.fromOffset(coinSize, coinSize)
	refs.Price.Position = UDim2.fromOffset(coinSize + 26, 0)
	refs.Price.Size = UDim2.new(1, -(coinSize + 34), 1, 0)
	refs.Price.TextSize = m.Price
	local buy = holderOf(refs.BuyButton)
	buy.Position = UDim2.fromOffset(half + m.Gap, y + 9)
	buy.Size = UDim2.fromOffset(inner - half - m.Gap, m.Button + 4)
	refs.BuyButton.TextSize = if refs.Compact then 34 else 30
	y += boxHeight + 10
	refs.Note.Position = UDim2.fromOffset(0, y)
	refs.Note.Size = UDim2.new(1, 0, 0, m.Text + 8)
	refs.Note.TextSize = m.Text
	return y + m.Text + 8
end

local function layoutFloors(refs: Refs, m: Metrics, width: number, height: number)
	local top = m.Header
	local bottom = if refs.Compact then PAD else PAD + 26
	refs.FloorPage.Position = UDim2.fromOffset(PAD, top)
	refs.FloorPage.Size = UDim2.new(1, -PAD * 2, 1, -(top + bottom))
	local rows = math.ceil(#refs.Cards / COLUMNS)
	local cardWidth = math.floor((width - PAD * 2 - m.Gap * (COLUMNS - 1)) / COLUMNS)
	local cardHeight = math.floor((height - top - bottom - m.Gap * (rows - 1)) / rows)
	-- inside a card: badge row, the tag line (when there is room), the button
	local buttonHeight = math.min(m.Button, math.floor(cardHeight * 0.42))
	local badge = math.min(m.Badge, cardHeight - buttonHeight - 30)
	local showTag = cardHeight >= 10 + badge + 26 + buttonHeight + 16
	for i, card in refs.Cards do
		local column = (i - 1) % COLUMNS
		local row = math.floor((i - 1) / COLUMNS)
		card.Frame.Position = UDim2.fromOffset(column * (cardWidth + m.Gap), row * (cardHeight + m.Gap))
		card.Frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		card.Badge.Size = UDim2.fromOffset(badge, badge)
		card.Number.TextSize = math.floor(badge * 0.6)
		local left = 10 + badge + 10
		local nameHeight = math.floor(badge * 0.5)
		card.Name.Position = UDim2.fromOffset(left, 10)
		card.Name.Size = UDim2.new(1, -(left + 8), 0, nameHeight)
		card.Name.TextSize = m.CardName
		card.Chip.Position = UDim2.fromOffset(left, 10 + nameHeight + 2)
		card.Chip.Size = UDim2.fromOffset(if refs.Compact then 120 else 104, math.max(22, badge - nameHeight - 6))
		card.Chip.TextSize = if refs.Compact then 17 else 15
		card.Tag.Visible = showTag
		card.Tag.Position = UDim2.fromOffset(12, 10 + badge + 4)
		card.Tag.Size = UDim2.new(1, -24, 0, 22)
		card.Tag.TextSize = if refs.Compact then 18 else 16
		local holder = holderOf(card.Button)
		holder.AnchorPoint = Vector2.new(0, 1)
		holder.Position = UDim2.new(0, 10, 1, -10)
		holder.Size = UDim2.new(1, -20, 0, buttonHeight)
		local long = card.Entry.State == "Here" or card.Entry.State == "Soon"
		card.Button.TextSize = if long then (if refs.Compact then 22 else 19) else (if refs.Compact then 28 else 24)
	end
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (the screen divided by
	the UI scale; math.huge = no limit).
]]
function ElevatorView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local wantWidth = if refs.Mode == "Buy" then m.BuyWidth else m.FloorWidth
	local width = math.max(520, math.min(wantWidth, maxWidth - 24))
	-- the Buy page is as tall as its content, the cards fill what they get
	local bottom = if compact then PAD else PAD + 26
	local buyContent = layoutBuy(refs, m, width)
	local wantHeight = if refs.Mode == "Buy" then m.Header + buyContent + bottom else m.FloorHeight
	local height = math.max(380, math.min(wantHeight, maxHeight - 16))
	refs.Panel.Size = UDim2.fromOffset(width, height)
	-- phones: at the bottom of the screen, clear of the HUD coins when there is room
	refs.Panel.AnchorPoint = if compact then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	refs.Panel.Position = if compact then UDim2.new(0.5, 0, 1, -8) else UDim2.fromScale(0.5, 0.5)
	refs.Title.TextSize = m.Title
	refs.Title.Size = UDim2.new(1, -(PAD * 2 + m.Close + 12), 0, m.Title + 4)
	for _, label in { refs.Subtitle, refs.Message } do
		label.Position = UDim2.fromOffset(PAD + 2, 10 + m.Title + 6)
		label.Size = UDim2.new(1, -(PAD * 2 + m.Close + 12), 0, m.Text + 6)
		label.TextSize = m.Text
	end
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, if compact then 8 else 14)
	refs.Close.TextSize = if compact then 30 else 26
	refs.Hint.Visible = not compact
	refs.Hint.Position = UDim2.new(0, PAD, 1, -8)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	layoutFloors(refs, m, width, height)
end

---------------------------------------------------------------- the ride fade

-- The black screen of a ride (no UIScale: the black layer always covers the whole screen).
function ElevatorView.buildFade(): Fade
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeElevatorFade",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 60,
		Enabled = false,
	})
	local black = UIKit.new("Frame", {
		Name = "Black",
		BackgroundColor3 = Color3.fromRGB(10, 7, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = true,
	}, gui)
	local title = UIKit.label(black, "", 48, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.12, 0),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextScaled = true,
		TextTransparency = 1,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 72, MinTextSize = 24 }, title)
	local name = UIKit.label(black, "", 28, {
		Name = "FloorName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(0.9, 0, 0.07, 0),
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextTransparency = 1,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 16 }, name)
	return { Gui = gui, Black = black, Title = title, Name = name }
end

function ElevatorView.setFadeText(fade: Fade, floorIndex: number, name: string)
	fade.Title.Text = `FLOOR {floorIndex}`
	fade.Name.Text = name
end

return ElevatorView
