--[[
	The Gear shop view at the SHOP stall (pure builder + pure helpers;
	GearShopController fills it in). One ScreenGui:

	  header   GEAR SHOP, a line about the shop (or the last message: HUD
	           toasts hide behind the panel), your coins, the X button
	  cards    the four GearConfig lines side by side (Boots, Helmet Lamp,
	           Gloves, Magnet: the backpacks have their own BACKPACKS shop
	           since 2026-10-24), each a painted Pop card in its own
	           colour (GearShopView.Paints; the window is a Pop window,
	           BoostView.popWindow):
	             a showcase: the item's picture (IconAssets boots, helmet...;
	             drawn from frames until the sheet is uploaded) on light
	             rays, and the level chip ("LV 2/5", "MAX"); the name; five
	             glossy level pips; what it does; the effect well: what you
	             have now -> what the next level gives (big white), its unit,
	             a second stat (lamp brightness); the price
	             (Format.money, gold, white when you can't afford it); the
	             gold coin BUY button (grey when you can't afford it; MAX and
	             BOUGHT! green)
	  footer   the control hint (GearShopView.hintText; "All gear at the
	           top level" once every line is MAX); with a gamepad the
	           platform's own button glyphs (GearShopView.setHint). The
	           compact layout shows it only for a gamepad (TVs, a pad on
	           a phone): A buy, B close

	A card shows the server's answer for a moment in its effect box
	(GearShopView.setStatus). Designed for 720 design units of height
	(HudController.uiScale). The compact layout (phones, TVs) makes every
	button at least 44 pt at the phone scale (GearShopView.touchTargets);
	on a short screen a card drops, in this order, its description, its
	level pips and its second stat line, so the showcase keeps its size;
	on a tall one the description gets the lines its text needs (top
	aligned, right under the pips) and the showcase the rest (rows).
	Texts fit their boxes (TechShopView.fitText shrinks a long one). Cards
	that don't fit side by side scroll sideways.
	Prices and levels come from GearConfig (nextPrice / quote rules) and the
	State snapshot (Gear: the save's levels), so a card always offers what
	the server will quote. The effect numbers are the server's preview
	(GearService.preview: walk speed, magnet radius... with every bonus
	counted, e.g. the Magnetism enchant), or the gear table until it came.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local GearConfig = require(Shared.Config.GearConfig)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)
local TechShopView = require(script.Parent.TechShopView)
-- (the shared Pop pieces: popWindow, popButton, style, backing, burst)
local BoostView = require(script.Parent.BoostView)

local GearShopView = {}

-- The BUY button of a card.
export type Buy = {
	Text: string, -- "BUY", "MAX"
	Level: number?, -- GearAction Level: the level being bought
	Price: number?, -- nil at the top level
	Reason: string?, -- why it can't be bought now (a GearConfig.Reasons code)
	CanBuy: boolean, -- for sale and affordable
}

-- What one card shows (GearShopView.cards).
export type Card = {
	Line: string, -- GearConfig line id (the GearAction Line)
	Order: number,
	Title: string,
	Description: string,
	Level: number, -- the level you have (0..MaxLevel)
	Max: number,
	Chip: string, -- "LV 2/5" / "MAX"
	ChipColor: Color3,
	Effect: string, -- "18 → 20" (top level: "26")
	Unit: string, -- "walk speed"
	Extra: string, -- the second stat (the Helmet Lamp's brightness), "" when none
	EffectColor: Color3,
	PriceText: string, -- "$3K"; "TOP LEVEL" when done
	PriceColor: Color3,
	Done: boolean,
	Buy: Buy,
	Icon: string, -- GearConfig line Icon (GearShopView.icon kind)
}

-- The room a card's texts get (design units; TechShopView.fitText).
type Boxes = {
	Width: number, -- the card's inner width
	Title: number,
	Description: number,
	DescriptionHeight: number,
	Effect: number,
	Unit: number,
	Extra: number,
	Status: number,
	StatusHeight: number,
	Price: number,
	Button: number, -- the BUY text size
}

export type Slot = {
	Line: string,
	Frame: Frame,
	Showcase: Frame,
	Art: Frame,
	Chip: TextLabel,
	Title: TextLabel,
	PipBar: Frame,
	Pips: { Frame },
	Description: TextLabel,
	EffectBox: Frame,
	Effect: TextLabel,
	Unit: TextLabel,
	Extra: TextLabel,
	Status: TextLabel, -- the server's answer for a moment (covers the effect texts)
	Price: TextLabel,
	Button: TextButton,
	Boxes: Boxes,
	Card: Card?,
	Picture: ImageLabel, -- the uploaded picture (IconAssets: boots, helmet...); Art draws it until then
	Burst: Frame, -- the light rays behind the picture
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Receipt: TextLabel,
	Balance: Frame,
	BalanceAmount: TextLabel,
	Close: TextButton,
	List: ScrollingFrame,
	Slots: { [string]: Slot }, -- by line id
	SlotList: { Slot }, -- in shop order
	Hint: TextLabel,
	PadHint: Frame, -- gamepad hint: [A] buy  [B] close, the platform's glyphs
	PadGlyphs: { ImageLabel }, -- A, B
	PadMode: boolean, -- the hint is the glyph row (PadHint)
	Gamepad: boolean, -- a gamepad plays (the compact layout shows the footer then)
	HintDone: boolean, -- every line is at the top level (no "buy" in the hint)
	Compact: boolean,
	-- the bounds of the last layout (setHint lays out again when the footer comes or goes)
	LayoutWidth: number,
	LayoutHeight: number,
	-- which optional rows the cards show (layout)
	ShowDescription: boolean,
	ShowPips: boolean,
	ShowExtra: boolean,
	PriceOnButton: boolean, -- short screens: "BUY $18K" on the button, no price row
}

GearShopView.PhoneScale = 0.62 -- HudController's floor (phones)
GearShopView.MinTouch = 44 -- points
GearShopView.CoinsBottom = 96 -- HudView's coins panel and a gap: a panel below this leaves it clear
GearShopView.MinHeight = 360
-- studs from the counter's surface at which the open shop closes: under the
-- server's GearConfig.Range (30), so lag never gets an open shop's BUY refused
GearShopView.CloseRange = 24
GearShopView.Separator = TechShopView.Separator
GearShopView.Subtitle = "Gear works right away and stays after you respawn."
GearShopView.DoneHint = "All gear at the top level"

-- Status lines the controller shows on a card (here so the tests can check they fit).
GearShopView.StatusText = {
	NoAnswer = "No answer, try again", -- safe: a repeat is refused as Stale
	Waiting = "Wait for your last buy",
	LateBought = "Bought!",
}

local rgb = Color3.fromRGB

--[[
	The Pop look (owner 2026-10-21: "new, modern, colourful, clean items,
	Roblox style"): each card painted in its own bright colour (picked so its
	picture stands out: red boots on teal, the yellow helmet on purple...),
	light rays behind the big picture, the level on a chip, glossy pips, the
	stat in big white on a dark well and a gold coin BUY button.
]]
GearShopView.WindowPaint = "Blue" -- the Gear colour (BubbleTheme.Roles.Gear)
GearShopView.Paints = {
	Boots = "Teal",
	HelmetLamp = "Purple",
	Gloves = "Pink",
	Magnet = "Green",
} :: { [string]: string }
-- the level pips: lit (gold), every one at the top level (green), not yet (dark)
GearShopView.PipColors = {
	On = rgb(255, 214, 50),
	Done = rgb(120, 240, 70),
	Off = rgb(28, 30, 38),
}
-- the price's gold (affordable) and plain white (not yet: the BUY button is grey)
local PRICE_GOLD = ColorSequence.new(rgb(255, 246, 120), rgb(255, 176, 20))
local WHITE = Color3.new(1, 1, 1)

-- The SHOP stall's item colors (Lobby/Districts/Stalls) and the showcase's blue neon.
local C = {
	Helmet = rgb(255, 196, 18),
	HelmetDark = rgb(196, 138, 8),
	Lamp = rgb(255, 250, 214),
	LampRim = rgb(120, 126, 140),
	Beam = rgb(255, 240, 170),
	Boots = rgb(222, 38, 38),
	BootsDark = rgb(150, 22, 22),
	Sole = rgb(52, 40, 36),
	Lace = rgb(255, 236, 214),
	Strap = rgb(110, 70, 40),
	Glove = rgb(214, 120, 50),
	GloveDark = rgb(150, 76, 28),
	Cuff = rgb(96, 58, 40),
	Magnet = rgb(226, 30, 40),
	MagnetDark = rgb(150, 18, 24),
	Tip = rgb(240, 240, 248),
	Spark = rgb(120, 200, 255),
	Case = rgb(24, 40, 96),
	CaseDark = rgb(12, 18, 48),
	Neon = rgb(40, 120, 255),
}

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Footer: number,
	Gap: number, -- between cards
	Pad: number, -- inside a card
	Button: number,
	MinCard: number, -- narrower: the cards scroll sideways
	MaxCard: number,
	IconMax: number,
	IconMin: number, -- the showcase never gets smaller while an optional row can go
	IconTall: number, -- a tall card's showcase grows up to this (no empty band under the pips)
	Title: number,
	Description: number,
	DescriptionMin: number,
	Effect: number,
	Unit: number,
	Extra: number,
	Price: number,
	Chip: number,
	Close: number,
}

local PAD = 16
-- the compact layout's footer while a gamepad plays (the glyph row fits in it)
local PAD_FOOTER = 34

-- (Width: four cards at MaxCard side by side, the gaps and the padding)
local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 910,
		Height = 560,
		Header = 82,
		Footer = 30,
		Gap = 12,
		Pad = 10,
		Button = 54,
		MinCard = 150,
		MaxCard = 210,
		IconMax = 124,
		IconMin = 92,
		IconTall = 160,
		Title = 21,
		Description = 15,
		DescriptionMin = 12,
		Effect = 26,
		Unit = 15,
		Extra = 14,
		Price = 24,
		Chip = 14,
		Close = 54,
	},
	-- phones and TVs: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 960,
		Height = 600,
		-- the X (72 high, from 6) reaches below the title row: the cards start under it
		Header = 80,
		Footer = 6,
		Gap = 10,
		Pad = 8,
		Button = 72,
		MinCard = 156,
		MaxCard = 220,
		IconMax = 118,
		IconMin = 78,
		IconTall = 180,
		Title = 22,
		Description = 16,
		DescriptionMin = 13,
		Effect = 28,
		Unit = 16,
		Extra = 15,
		Price = 26,
		Chip = 16,
		Close = 72,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

-- The compact layout's screens (as TechShopView: touch, TVs, small or low screens).
function GearShopView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return TechShopView.compactFor(touch, tenFoot, scale, viewportHeight)
end

---------------------------------------------------------------- pure helpers

local function num(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end

local function safeState(state: any): { [string]: any }
	return if type(state) == "table" then state else {}
end

-- A gear value as the cards say it: whole numbers plain, others with up to two decimals.
function GearShopView.number(value: number): string
	if value == math.floor(value) then
		return string.format("%d", value)
	end
	local text = string.format("%.2f", value)
	text = text:gsub("0+$", "")
	return text
end

local function fromTo(now: string, nextValue: string?): string
	if nextValue == nil then
		return now
	end
	return `{now} → {nextValue}`
end

-- the second stat of a line (the card's Extra row; nothing is thrown since the backpack, so
-- the Gloves' throw power isn't shown)
local EXTRA_STAT: { [string]: string } = { HelmetLamp = "LampBrightness" }

-- A line's preview when it is for `level` and its numbers are sane (else nil:
-- the card falls back to the gear table).
local function livePreview(values: any, level: number): GearConfig.LinePreview?
	if type(values) ~= "table" or values.Level ~= level then
		return nil
	end
	local now = values.Now
	if type(now) ~= "number" or now ~= now or now < 0 or now == math.huge then
		return nil
	end
	return values :: GearConfig.LinePreview
end

--[[
	What a line gives at `level` and (below the top level) at the next one,
	as the card's effect box says it: the big text, its unit and a second
	stat ("" when the line has none). Level 0 of the lamp and the magnet
	reads "Off". `values` (GearService.preview for this line, from the
	server) makes every number the real total with every bonus counted (the
	Magnetism enchant, golems, Swift); without it, or when it is for
	another level, the numbers are the gear table's.
]]
function GearShopView.effect(lineId: string, level: number, values: any?): (string, string, string)
	local line = GearConfig.ById[lineId]
	if not line then
		return "", "", ""
	end
	local current = GearConfig.clampLevel(level)
	local nextLevel: number? = if current < GearConfig.MaxLevel then current + 1 else nil
	local live = livePreview(values, current)
	local function value(at: number, extra: boolean): number
		if live then
			local v: number? = if at == current
				then (if extra then live.ExtraNow else live.Now)
				else (if extra then live.ExtraNext else live.Next)
			if type(v) == "number" and v == v and v >= 0 and v < math.huge then
				return v
			end
		end
		if extra then
			return GearConfig.value(lineId, at, EXTRA_STAT[lineId])
		end
		return GearConfig.value(lineId, at)
	end
	local function show(at: number, extra: boolean): string
		local v = value(at, extra)
		if v <= 0 and (lineId == "HelmetLamp" or lineId == "Magnet") then
			return "Off"
		end
		return GearShopView.number(math.floor(v * 100 + 0.5) / 100)
	end
	local function pair(extra: boolean): string
		local now = show(current, extra)
		local after = if nextLevel then show(nextLevel, extra) else nil
		return fromTo(now, after)
	end
	if lineId == "HelmetLamp" then
		local extra = if current == 0 and nextLevel then `Brightness {show(nextLevel, true)}` else `Brightness {pair(true)}`
		return pair(false), line.Unit, extra
	end
	return pair(false), line.Unit, ""
end

-- The chip of a level: "LV 2/5", or "MAX" at the top.
function GearShopView.chipText(level: number): string
	local current = GearConfig.clampLevel(level)
	if current >= GearConfig.MaxLevel then
		return "MAX"
	end
	return `LV {current}/{GearConfig.MaxLevel}`
end

--[[
	Every card of the shop from a State snapshot (Gear, Perks), your coins
	and the server's preview (GearService.preview: the real totals, nil =
	the gear table), in GearConfig.Lines order. The BUY offers exactly what
	the server quotes (GearConfig.quote): the next level, at nextPrice.
]]
function GearShopView.cards(rawState: any, coins: number, preview: any?): { Card }
	local state = safeState(rawState)
	local cash = num(coins)
	local values: { [string]: any } = if type(preview) == "table" then preview else {}
	local list: { Card } = {}
	for order, line in GearConfig.Lines do
		local level = GearConfig.level(state.Gear, line.Id)
		local price = GearConfig.nextPrice(line.Id, level)
		local done = price == nil
		local effect, unit, extra = GearShopView.effect(line.Id, level, values[line.Id])
		local buy: Buy
		if price == nil then
			buy = { Text = "MAX", Level = nil, Price = nil, Reason = "Max", CanBuy = false }
		else
			local afford = cash >= price
			buy = {
				Text = "BUY",
				Level = level + 1,
				Price = price,
				Reason = if afford then nil else "NoCoins",
				CanBuy = afford,
			}
		end
		table.insert(list, {
			Line = line.Id,
			Order = order,
			Title = line.Name,
			Description = line.Description,
			Level = level,
			Max = GearConfig.MaxLevel,
			Chip = GearShopView.chipText(level),
			ChipColor = if done then Theme.GoodDark else Theme.PanelDark,
			Effect = effect,
			Unit = unit,
			Extra = extra,
			EffectColor = if done then Theme.Good else Theme.Accent,
			PriceText = if price then Format.money(price) else "TOP LEVEL",
			PriceColor = if done then Theme.Good elseif cash >= (price :: number) then Theme.Coin else Theme.Bad,
			Done = done,
			Buy = buy,
			Icon = line.Icon,
		})
	end
	return list
end

---------------------------------------------------------------- icons

-- A rectangle in scale units of the art box (x0, y0 top left .. x1, y1 bottom right).
local function bit(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, color: Color3, round: number?): Frame
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
	UIKit.stroke(frame, 2)
	return frame
end

-- A soft shine on a shape (no outline).
local function shine(parent: Instance, x0: number, y0: number, x1: number, y1: number, transparency: number?)
	local frame = UIKit.new("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = transparency or 0.55,
		BorderSizePixel = 0,
	}, parent)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
end

local DRAW: { [string]: (Frame) -> () } = {
	-- two red boots (the back one darker), dark soles, white laces
	Boots = function(a: Frame)
		bit(a, "BackShaft", 0.16, 0.16, 0.42, 0.62, C.BootsDark, 0.18)
		bit(a, "BackFoot", 0.16, 0.5, 0.6, 0.72, C.BootsDark, 0.4)
		bit(a, "BackSole", 0.14, 0.68, 0.62, 0.78, C.Sole, 0.3)
		bit(a, "Shaft", 0.38, 0.22, 0.64, 0.7, C.Boots, 0.18)
		bit(a, "Foot", 0.38, 0.56, 0.88, 0.8, C.Boots, 0.45)
		bit(a, "Sole", 0.36, 0.76, 0.9, 0.88, C.Sole, 0.3)
		bit(a, "Cuff", 0.35, 0.16, 0.67, 0.27, C.Lace, 0.4)
		bit(a, "LaceA", 0.42, 0.36, 0.6, 0.4, C.Lace, 0.5)
		bit(a, "LaceB", 0.42, 0.47, 0.6, 0.51, C.Lace, 0.5)
		shine(a, 0.44, 0.3, 0.5, 0.62)
	end,
	-- a yellow miner's helmet (side view, a half dome on a brim) with a
	-- glowing lamp at the front and three light rays
	Helmet = function(a: Frame)
		for i, angle in { -16, 0, 16 } do
			local ray = UIKit.new("Frame", {
				Name = "Ray" .. i,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.8, 0.42),
				Size = UDim2.fromScale(0.22, 0.05),
				Rotation = angle,
				BackgroundColor3 = C.Beam,
				BorderSizePixel = 0,
			}, a)
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ray)
		end
		-- the dome: the top half of an ellipse (a clipping frame)
		local clip = UIKit.new("Frame", {
			Name = "DomeClip",
			Position = UDim2.fromScale(0.1, 0.2),
			Size = UDim2.fromScale(0.68, 0.44),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, a)
		local dome = UIKit.new("Frame", {
			Name = "Dome",
			Size = UDim2.fromScale(1, 2),
			BackgroundColor3 = C.Helmet,
			BorderSizePixel = 0,
		}, clip)
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dome)
		UIKit.stroke(dome, 2)
		bit(a, "Ridge", 0.4, 0.2, 0.48, 0.62, C.HelmetDark, 0.5)
		bit(a, "Brim", 0.04, 0.6, 0.86, 0.72, C.HelmetDark, 0.5)
		bit(a, "Band", 0.12, 0.72, 0.76, 0.8, C.Strap, 0.3)
		bit(a, "Mount", 0.62, 0.32, 0.8, 0.52, C.LampRim, 0.3)
		bit(a, "Lamp", 0.68, 0.34, 0.84, 0.5, C.Lamp, 0.5)
		shine(a, 0.2, 0.3, 0.34, 0.36)
	end,
	-- a copper work glove: palm, four fingers, thumb, a leather cuff
	Gloves = function(a: Frame)
		for i, x in { 0.26, 0.38, 0.5, 0.62 } do
			local top = if i == 2 or i == 3 then 0.1 else 0.16
			bit(a, "Finger", x, top, x + 0.11, 0.48, C.Glove, 0.5)
		end
		local thumb = bit(a, "Thumb", 0.64, 0.4, 0.86, 0.52, C.Glove, 0.5)
		thumb.Rotation = -35
		bit(a, "Palm", 0.24, 0.36, 0.76, 0.74, C.Glove, 0.25)
		bit(a, "Seam", 0.3, 0.52, 0.7, 0.56, C.GloveDark, 0.5)
		bit(a, "Cuff", 0.22, 0.7, 0.78, 0.9, C.Cuff, 0.2)
		shine(a, 0.3, 0.4, 0.36, 0.66)
	end,
	-- a red U magnet with white tips and blue sparks
	Magnet = function(a: Frame)
		bit(a, "Base", 0.16, 0.42, 0.84, 0.86, C.Magnet, 0.5)
		bit(a, "Hole", 0.36, 0.36, 0.64, 0.68, C.Case, 0.5)
		bit(a, "LegL", 0.16, 0.2, 0.36, 0.66, C.Magnet, 0.1)
		bit(a, "LegR", 0.64, 0.2, 0.84, 0.66, C.Magnet, 0.1)
		bit(a, "TipL", 0.16, 0.08, 0.36, 0.22, C.Tip, 0.15)
		bit(a, "TipR", 0.64, 0.08, 0.84, 0.22, C.Tip, 0.15)
		for _, s in { { 0.42, 0.06 }, { 0.5, 0.16 }, { 0.46, 0.26 } } do
			local spark = bit(a, "Spark", s[1], s[2], s[1] + 0.07, s[2] + 0.07, C.Spark, 0.2)
			spark.Rotation = 45
		end
		shine(a, 0.2, 0.3, 0.26, 0.6)
	end,
}

--[[
	A gear icon (`kind` = a GearConfig line Icon) drawn from frames into
	`art` (any size; everything is in scale units). setIcon redraws one.
]]
function GearShopView.setIcon(art: Frame, kind: string)
	if art:GetAttribute("Kind") == kind then
		return
	end
	art:ClearAllChildren()
	art:SetAttribute("Kind", kind)
	local draw = DRAW[kind]
	if draw then
		draw(art)
	else
		bit(art, "Plain", 0.2, 0.2, 0.8, 0.8, C.Helmet, 0.2)
	end
end

-- The kinds setIcon draws (tests).
function GearShopView.iconKinds(): { string }
	local list = {}
	for kind in DRAW do
		table.insert(list, kind)
	end
	table.sort(list)
	return list
end

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- Paints a button (the controllers pass UITheme colours: Accent a gold coin
-- button, Good green; disabled grey): BoostView.style, the Pop look.
local style = BoostView.style
GearShopView.style = style
-- Shows a button's Text on its face again (the game does it on every Text change; the previews call it).
GearShopView.syncButton = BoostView.syncButton

-- The IconAssets picture of a gear line's Icon ("Boots" -> boots).
function GearShopView.pictureName(kind: string): string
	return string.lower(kind)
end

-- Shows a card's uploaded picture (and in the previews), else the drawing (Art).
local function setPicture(slot: Slot, kind: string)
	local name = GearShopView.pictureName(kind)
	if slot.Picture:GetAttribute("Icon") ~= name then
		IconAssets.apply(slot.Picture, name)
		slot.Picture:SetAttribute("Icon", name)
	end
	local shows = IconAssets.shows(name)
	slot.Picture.Visible = shows
	slot.Art.Visible = not shows
end

local function newSlot(refs: Refs, line: GearConfig.GearLine, order: number, m: Metrics): Slot
	-- the card: painted in the line's own colour, light rays behind the picture (it clips them)
	local frame = UIKit.new("Frame", {
		Name = line.Id,
		LayoutOrder = order,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, refs.List)
	Pop.face(frame, GearShopView.Paints[line.Id] or "Blue", 12, false)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	local burst = BoostView.burst(frame, 10, 1)
	Pop.studs(frame, 12, 0.5, 44, 2)
	-- the showcase: the picture's box (see-through: the picture sits on the rays)
	local showcase = UIKit.new("Frame", {
		Name = "Showcase",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, frame)
	for i, spot in { { 0.14, 0.24, 18 }, { 0.84, 0.72, 16 }, { 0.2, 0.82, 12 } } do
		Pop.sparkle(showcase, UDim2.fromScale(spot[1], spot[2]), spot[3], 1, 0.15 + i * 0.1)
	end
	local art = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, showcase)
	GearShopView.setIcon(art, line.Icon)
	local picture = UIKit.new("ImageLabel", {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 2,
	}, showcase)
	-- the level chip ("LV 2/5", "MAX") on its pill
	local chip = UIKit.chip(showcase, "", Theme.PanelDark, {
		Name = "Chip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 5),
		ZIndex = 4,
	})
	BoostView.strip(chip)
	chip.BackgroundTransparency = 1
	BoostView.popText(chip, false, WHITE)
	BoostView.backing(chip, BoostView.DarkPaint)
	local title = UIKit.label(frame, "", m.Title, {
		Name = "ItemName",
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 5,
	})
	BoostView.popText(title, true, WHITE)
	local pipBar = UIKit.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, frame)
	UIKit.list(pipBar, Enum.FillDirection.Horizontal, 5, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local pips: { Frame } = {}
	for i = 1, GearConfig.MaxLevel do
		local pip = UIKit.new("Frame", {
			Name = "Pip" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(20, 10),
			BackgroundColor3 = GearShopView.PipColors.Off,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, pipBar)
		UIKit.corner(pip, 5)
		UIKit.stroke(pip, 2, PopTheme.Outline)
		-- (a glossy top: the colour stays BackgroundColor3)
		UIKit.new("UIGradient", { Color = ColorSequence.new(WHITE, rgb(200, 200, 200)), Rotation = 90 }, pip)
		table.insert(pips, pip)
	end
	local description = UIKit.label(frame, "", m.Description, {
		Name = "Description",
		TextYAlignment = Enum.TextYAlignment.Top,
		ClipsDescendants = true,
		ZIndex = 5,
	})
	BoostView.popText(description, false, WHITE)
	-- the effect: a dark well with the stat in big white
	local effectBox = UIKit.new("Frame", {
		Name = "EffectBox",
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, frame)
	UIKit.corner(effectBox, 10)
	Pop.border(effectBox, 2.5)
	local effect = UIKit.label(effectBox, "", m.Effect, {
		Name = "Effect",
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	BoostView.popText(effect, true, WHITE)
	local unit = UIKit.label(effectBox, "", m.Unit, {
		Name = "Unit",
		TextWrapped = false,
	})
	BoostView.popText(unit, false, WHITE)
	local extra = UIKit.label(effectBox, "", m.Extra, {
		Name = "Extra",
		TextWrapped = false,
	})
	BoostView.popText(extra, false, rgb(255, 236, 150))
	local status = UIKit.label(effectBox, "", m.Unit, {
		Name = "Status",
		TextWrapped = true,
		Visible = false,
	})
	BoostView.popText(status)
	-- the price: big gold words (white while you can't afford it: the button is grey then)
	local price = UIKit.label(frame, "", m.Price, {
		Name = "Price",
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 5,
	})
	BoostView.popText(price, true, WHITE)
	UIKit.new("UIGradient", { Name = "Gold", Color = PRICE_GOLD, Rotation = 90 }, price)
	-- the gold coin BUY button (grey when you can't afford it; green MAX / BOUGHT!)
	local button = UIKit.button(frame, "BUY", Theme.Accent, Theme.AccentDark, { Name = "Buy" })
	holderOf(button).ZIndex = 5
	BoostView.popButton(button, "Yellow", 10)
	BoostView.setMark(button, "coin")
	local slot: Slot = {
		Line = line.Id,
		Frame = frame,
		Showcase = showcase,
		Art = art,
		Chip = chip,
		Title = title,
		PipBar = pipBar,
		Pips = pips,
		Description = description,
		EffectBox = effectBox,
		Effect = effect,
		Unit = unit,
		Extra = extra,
		Status = status,
		Price = price,
		Button = button,
		-- set by placeSlot
		Boxes = {
			Width = 0,
			Title = m.Title,
			Description = m.Description,
			DescriptionHeight = 0,
			Effect = m.Effect,
			Unit = m.Unit,
			Extra = m.Extra,
			Status = m.Unit,
			StatusHeight = 0,
			Price = m.Price,
			Button = 22,
		},
		Card = nil,
		Picture = picture,
		Burst = burst,
	}
	setPicture(slot, line.Icon)
	refs.Slots[line.Id] = slot
	table.insert(refs.SlotList, slot)
	return slot
end

function GearShopView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeGearShop", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look, never LightSkin's recolouring

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.Width, METRICS.Normal.Height),
		Active = true,
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local title = UIKit.label(panel, "GEAR SHOP", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, GearShopView.Subtitle, 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local receipt = UIKit.label(panel, "", 17, {
		Name = "Receipt",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Good,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 34,
	})
	-- your coins, next to the close button (the HUD's may be covered on phones)
	local balance, balanceAmount = BoostView.balance(panel)
	-- the Pop window: the blue header band (the Gear colour), the dark body
	BoostView.popWindow(panel, title, GearShopView.WindowPaint)
	BoostView.popText(subtitle, false, WHITE)
	BoostView.popText(receipt, false, WHITE)
	BoostView.popButton(close, PopTheme.Close, 6, true)

	-- the cards: side by side, scrolling sideways when they don't fit
	local list = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = rgb(196, 200, 212),
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, panel)

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	BoostView.popText(hint)
	-- gamepads: the platform's own button glyphs (Xbox or PlayStation), set by the controller
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	UIKit.list(padHint, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local padGlyphs: { ImageLabel } = {}
	local order = 0
	local function padGlyph(name: string)
		order += 1
		table.insert(
			padGlyphs,
			UIKit.new("ImageLabel", {
				Name = "Glyph" .. name,
				LayoutOrder = order,
				Size = UDim2.fromOffset(24, 24),
				BackgroundTransparency = 1,
			}, padHint)
		)
	end
	local function padWord(name: string, text: string, width: number, visible: boolean?)
		order += 1
		local word = UIKit.label(padHint, text, 15, {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
			Visible = visible ~= false,
		})
		BoostView.popText(word)
	end
	-- (every line at the top level: "All gear at the top level  [B] close")
	padWord("WordDone", GearShopView.DoneHint, 196, false)
	padGlyph("A")
	padWord("WordBuy", "buy", 44)
	padGlyph("B")
	padWord("WordClose", "close", 52)

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		Balance = balance,
		BalanceAmount = balanceAmount,
		Close = close,
		List = list,
		Slots = {},
		SlotList = {},
		Hint = hint,
		PadHint = padHint,
		PadGlyphs = padGlyphs,
		PadMode = false,
		Gamepad = false,
		HintDone = false,
		Compact = compact == true,
		LayoutWidth = math.huge,
		LayoutHeight = math.huge,
		ShowDescription = true,
		ShowPips = true,
		ShowExtra = true,
		PriceOnButton = false,
	}
	local m = metrics(refs.Compact)
	for order2, line in GearConfig.Lines do
		newSlot(refs, line, order2, m)
	end
	GearShopView.layout(refs, refs.Compact, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

-- Fits a card's texts into their boxes (a long text gets a little smaller).
local function fitSlot(slot: Slot)
	local b = slot.Boxes
	if b.Width <= 0 then
		return -- not placed yet
	end
	TechShopView.fitText(slot.Title, b.Width, b.Title * 1.3, b.Title, math.max(12, b.Title - 7))
	if slot.Description.Visible then
		TechShopView.fitText(slot.Description, b.Width, b.DescriptionHeight, b.Description, math.max(11, b.Description - 3))
	end
	local inner = b.Width - 8
	TechShopView.fitText(slot.Effect, inner, b.Effect * 1.2, b.Effect, math.max(14, b.Effect - 10))
	TechShopView.fitText(slot.Unit, inner, b.Unit * 1.25, b.Unit, math.max(11, b.Unit - 4))
	TechShopView.fitText(slot.Extra, inner, b.Extra * 1.25, b.Extra, math.max(10, b.Extra - 4))
	TechShopView.fitText(slot.Status, inner, b.StatusHeight, b.Status, math.max(11, b.Status - 4))
	TechShopView.fitText(slot.Price, b.Width, b.Price * 1.25, b.Price, math.max(14, b.Price - 8))
	-- (a TextButton measures like a TextLabel; the coin beside the words takes its room)
	local button: any = slot.Button
	local mark = button:GetAttribute("Mark")
	local markRoom = if type(mark) == "string" and mark ~= "" then math.floor(b.Button * 1.1 + 4) + 5 else 0
	TechShopView.fitText(button, b.Width - 16 - markRoom, b.Button * 1.3, b.Button, math.max(14, b.Button - 8))
	BoostView.syncButton(button)
end
GearShopView.fitSlot = fitSlot

-- The height of a card's parts below the showcase (without the description).
local function stackHeight(m: Metrics, pips: boolean, extra: boolean, priceRow: boolean): number
	local effectBox = m.Effect * 1.2 + m.Unit * 1.25 + (if extra then m.Extra * 1.25 else 0) + 10
	return m.Pad -- top
		+ 6 -- showcase -> title
		+ m.Title * 1.3
		+ (if pips then 2 + 12 else 0)
		+ 6
		+ effectBox
		+ 4
		+ (if priceRow then m.Price * 1.25 + 4 else 0)
		+ 5 -- the button's lip
		+ m.Button
		+ m.Pad -- bottom
end

export type Rows = {
	Description: boolean,
	Pips: boolean,
	Extra: boolean,
	PriceOnButton: boolean,
	Icon: number, -- the showcase's height
	DescriptionHeight: number,
}

--[[
	Which optional rows fit a card `height` units tall, and how tall the
	showcase and the description get. On a short card, in this order: the
	description goes, the price moves onto the BUY button ("BUY $18K"),
	the level pips go (the chip still says the level), then the second stat
	line, so the showcase stays at least IconMin (unless nothing else is
	left to drop).
]]
function GearShopView.rows(compact: boolean, height: number): Rows
	local m = metrics(compact)
	local descriptionMin = 2 * m.Description * TechShopView.LineHeight + 4
	local descriptionWant = 3 * m.Description * TechShopView.LineHeight + 4
	local pips, extra, priceRow = true, true, true
	local avail = height - stackHeight(m, pips, extra, priceRow) - 6
	if avail >= m.IconMin + descriptionMin then
		-- the showcase first (up to IconMax), then the description its lines
		-- (two, three when there is room), then the showcase grows on (up
		-- to IconTall): no empty band between the pips and the text
		local text = math.clamp(avail - m.IconMax, descriptionMin, descriptionWant)
		local icon = math.min(m.IconTall, avail - text)
		return {
			Description = true,
			Pips = true,
			Extra = true,
			PriceOnButton = false,
			Icon = icon,
			DescriptionHeight = avail - icon,
		}
	end
	avail = height - stackHeight(m, pips, extra, priceRow)
	if avail < m.IconMin then
		priceRow = false
		avail = height - stackHeight(m, pips, extra, priceRow)
	end
	if avail < m.IconMin then
		pips = false
		avail = height - stackHeight(m, pips, extra, priceRow)
	end
	if avail < m.IconMin then
		extra = false
		avail = height - stackHeight(m, pips, extra, priceRow)
	end
	return {
		Description = false,
		Pips = pips,
		Extra = extra,
		PriceOnButton = not priceRow,
		Icon = math.clamp(avail, 40, m.IconMax),
		DescriptionHeight = 0,
	}
end

-- The BUY button's text for a card ("BUY $18K" when the price rides on it).
function GearShopView.buttonText(refs: Refs, card: Card): string
	if refs.PriceOnButton and card.Buy.Price ~= nil then
		return `{card.Buy.Text} {card.PriceText}`
	end
	return card.Buy.Text
end

-- One card (`width` x `height` design units) at x = `left` in the list.
local function placeSlot(
	refs: Refs,
	slot: Slot,
	m: Metrics,
	left: number,
	width: number,
	height: number,
	iconSize: number,
	descriptionHeight: number
)
	local compact = refs.Compact
	slot.Frame.Position = UDim2.fromOffset(left, 0)
	slot.Frame.Size = UDim2.fromOffset(width, height)
	local inner = width - 2 * m.Pad
	local y = m.Pad
	slot.Showcase.Position = UDim2.fromOffset(m.Pad, y)
	slot.Showcase.Size = UDim2.fromOffset(inner, iconSize)
	-- the item never hides under the level chip (top right): a tall
	-- showcase puts it centred below the chip, a short wide one beside it
	local chipWidth = if compact then 76 else 66
	local chipHeight = if compact then 26 else 22
	slot.Chip.Size = UDim2.fromOffset(chipWidth, chipHeight)
	slot.Chip.TextSize = m.Chip
	local below = chipHeight + 7 -- the chip sits 5 from the top, and a gap
	local under = math.min(inner * 0.86, iconSize - below - 4, iconSize * 0.9)
	local beside = math.min(iconSize * 0.9, inner - chipWidth - 12)
	slot.Art.AnchorPoint = Vector2.new(0.5, 0.5)
	if under >= beside then
		local art = math.max(24, under)
		slot.Art.Position = UDim2.new(0.5, 0, 0, math.max(iconSize / 2, below + art / 2))
		slot.Art.Size = UDim2.fromOffset(art, art)
	else
		local art = math.max(24, beside)
		slot.Art.Position = UDim2.fromOffset(6 + art / 2, iconSize / 2)
		slot.Art.Size = UDim2.fromOffset(art, art)
	end
	-- the picture over the drawing's box (a little bigger: the pictures have a margin),
	-- the light burst behind it, the chip's pill
	slot.Picture.Position = slot.Art.Position
	slot.Picture.Size = UDim2.fromOffset(slot.Art.Size.X.Offset * 1.15, slot.Art.Size.Y.Offset * 1.15)
	local artCentre = slot.Art.Position
	BoostView.placeBurst(
		slot.Burst,
		UDim2.fromOffset(m.Pad + artCentre.X.Scale * inner + artCentre.X.Offset, m.Pad + artCentre.Y.Offset),
		math.max(width, iconSize) * 1.15
	)
	BoostView.placeBacking(slot.Chip)
	y += iconSize + 6
	slot.Title.Position = UDim2.fromOffset(m.Pad, y)
	slot.Title.Size = UDim2.fromOffset(inner, m.Title * 1.3)
	y += m.Title * 1.3
	slot.PipBar.Visible = refs.ShowPips
	if refs.ShowPips then
		slot.PipBar.Position = UDim2.fromOffset(m.Pad, y + 2)
		slot.PipBar.Size = UDim2.fromOffset(inner, 12)
		local pipWidth = math.min(22, (inner - 4 * 5) / GearConfig.MaxLevel)
		for _, pip in slot.Pips do
			pip.Size = UDim2.fromOffset(pipWidth, 10)
		end
		y += 14
	end
	y += 6
	slot.Description.Visible = refs.ShowDescription
	if refs.ShowDescription then
		slot.Description.Position = UDim2.fromOffset(m.Pad, y)
		slot.Description.Size = UDim2.fromOffset(inner, descriptionHeight)
		y += descriptionHeight + 6
	end
	-- from the bottom: the button, the price, the effect box
	local buttonTop = height - m.Pad - m.Button
	local holder = holderOf(slot.Button)
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.Position = UDim2.fromOffset(m.Pad, buttonTop)
	holder.Size = UDim2.fromOffset(inner, m.Button)
	slot.Button.TextSize = if compact then 24 else 22
	local priceHeight = if refs.PriceOnButton then 0 else m.Price * 1.25
	local priceTop = buttonTop - 5 - (if refs.PriceOnButton then 0 else 4 + priceHeight)
	slot.Price.Visible = not refs.PriceOnButton
	slot.Price.Position = UDim2.fromOffset(m.Pad, priceTop)
	slot.Price.Size = UDim2.fromOffset(inner, priceHeight)
	local effectHeight = m.Effect * 1.2 + m.Unit * 1.25 + (if refs.ShowExtra then m.Extra * 1.25 else 0) + 10
	local effectTop = priceTop - 4 - effectHeight
	slot.EffectBox.Position = UDim2.fromOffset(m.Pad, effectTop)
	slot.EffectBox.Size = UDim2.fromOffset(inner, effectHeight)
	local ey = 5
	slot.Effect.Position = UDim2.fromOffset(4, ey)
	slot.Effect.Size = UDim2.fromOffset(inner - 8, m.Effect * 1.2)
	ey += m.Effect * 1.2
	slot.Unit.Position = UDim2.fromOffset(4, ey)
	slot.Unit.Size = UDim2.fromOffset(inner - 8, m.Unit * 1.25)
	ey += m.Unit * 1.25
	slot.Extra.Visible = refs.ShowExtra and slot.Status.Visible == false
	slot.Extra.Position = UDim2.fromOffset(4, ey)
	slot.Extra.Size = UDim2.fromOffset(inner - 8, m.Extra * 1.25)
	slot.Status.Position = UDim2.fromOffset(4, 4)
	slot.Status.Size = UDim2.fromOffset(inner - 8, effectHeight - 8)
	slot.Boxes = {
		Width = inner,
		Title = m.Title,
		Description = m.Description,
		DescriptionHeight = descriptionHeight,
		Effect = m.Effect,
		Unit = m.Unit,
		Extra = m.Extra,
		Status = m.Unit,
		StatusHeight = effectHeight - 8,
		Price = m.Price,
		Button = slot.Button.TextSize,
	}
	fitSlot(slot)
end

-- Does the footer (the control hint) show? Always on PC; in the compact
-- layout only while a gamepad plays (TVs: A buy, B close), never under a thumb.
local function footerShown(refs: Refs): boolean
	return not refs.Compact or refs.Gamepad
end

-- The hint's rows: the text or the glyph row, and in the glyph row "buy"
-- or "All gear at the top level".
local function showFooter(refs: Refs)
	local shown = footerShown(refs)
	refs.Hint.Visible = shown and not refs.PadMode
	refs.PadHint.Visible = shown and refs.PadMode
	local done = refs.HintDone
	local word = refs.PadHint:FindFirstChild("WordDone") :: GuiObject?
	local buy = refs.PadHint:FindFirstChild("WordBuy") :: GuiObject?
	if word then
		word.Visible = done
	end
	if buy then
		buy.Visible = not done
	end
	refs.PadGlyphs[1].Visible = not done
end

--[[
	Sizes everything for the normal or compact (phone / TV) layout and fits
	the panel into `maxWidth` x `maxHeight` design units (the screen divided
	by the UI scale; math.huge = no limit).
]]
function GearShopView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local width = math.max(560, math.min(m.Width, maxWidth - 24))
	local height = math.max(GearShopView.MinHeight, math.min(m.Height, maxHeight - 16))
	-- below the HUD coins when there is room (as TechShopView); a phone panel covers them
	local left = (maxWidth - width) / 2
	local top = (maxHeight - height) / 2
	if maxWidth < 1e6 and maxHeight < 1e6 then
		if left < 16 + HudView.CoinsWidth and top < GearShopView.CoinsBottom then
			local below = maxHeight - GearShopView.CoinsBottom - 8
			if below >= (if compact then height else GearShopView.MinHeight) then
				height = math.min(height, below)
				top = GearShopView.CoinsBottom + (below - height) / 2
			end
		end
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0)
		refs.Panel.Position = UDim2.new(0.5, 0, 0, top)
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	refs.Panel.Size = UDim2.fromOffset(width, height)

	-- header
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, if compact then 6 else 14)
	local balanceWidth = if compact then 190 else 176
	refs.Balance.Size = UDim2.fromOffset(balanceWidth, 40)
	refs.Balance.Position = UDim2.new(1, -(PAD + m.Close + 12), 0, if compact then 14 else 16)
	local headRight = PAD + m.Close + 12 + balanceWidth + 12
	refs.Title.TextSize = if compact then 30 else 34
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 10 else 8)
	refs.Title.Size = UDim2.new(1, -(PAD + headRight), 0, 40)
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 50)
	refs.Subtitle.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 22)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	if compact then
		local titleWidth = 250
		refs.Title.Size = UDim2.fromOffset(titleWidth, 40)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth, 4)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + headRight), 0, 56)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
	else
		refs.Receipt.Position = UDim2.fromOffset(PAD, 50)
		refs.Receipt.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 24)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
	end
	refs.Close.TextSize = if compact then 46 else 36
	BoostView.syncButton(refs.Close)
	BoostView.placeWindow(refs.Panel, m.Header - 8)

	-- the cards
	refs.LayoutWidth = maxWidth
	refs.LayoutHeight = maxHeight
	local footer = if compact and refs.Gamepad then PAD_FOOTER else m.Footer
	local listTop = m.Header
	local listHeight = height - listTop - footer - 6
	local listWidth = width - 2 * PAD
	refs.List.Position = UDim2.fromOffset(PAD, listTop)
	refs.List.Size = UDim2.fromOffset(listWidth, listHeight)
	local count = #refs.SlotList
	local cardWidth = (listWidth - (count - 1) * m.Gap) / count
	local scrolls = cardWidth < m.MinCard
	cardWidth = math.clamp(cardWidth, m.MinCard, m.MaxCard)
	local total = count * cardWidth + (count - 1) * m.Gap
	-- a scroll bar under the cards takes room from them
	local cardHeight = listHeight - (if scrolls then 12 else 0)
	refs.List.CanvasSize = UDim2.fromOffset(if scrolls then total else 0, 0)
	refs.List.ScrollingEnabled = scrolls
	local rows = GearShopView.rows(compact, cardHeight)
	refs.ShowDescription = rows.Description
	refs.ShowPips = rows.Pips
	refs.ShowExtra = rows.Extra
	refs.PriceOnButton = rows.PriceOnButton
	-- centred when they don't fill the row
	local x = if scrolls then 0 else math.max(0, (listWidth - total) / 2)
	for _, slot in refs.SlotList do
		placeSlot(refs, slot, m, x, cardWidth, cardHeight, rows.Icon, rows.DescriptionHeight)
		x += cardWidth + m.Gap
		-- a laid-out card keeps its content (the button text may change with PriceOnButton)
		local card = slot.Card
		if card and slot.Button:GetAttribute("Busy") ~= true then
			slot.Button.Text = GearShopView.buttonText(refs, card)
		end
	end

	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, if compact then 24 else 20)
	refs.Hint.TextSize = if compact then 18 else 15
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, if compact then -5 else -4)
	showFooter(refs)
end

---------------------------------------------------------------- filling in

local function fillSlot(refs: Refs, slot: Slot, card: Card)
	slot.Card = card
	slot.Title.Text = string.upper(card.Title)
	slot.Chip.Text = card.Chip
	-- the level chip: a dark pill, green at the top level
	BoostView.placeBacking(slot.Chip, nil, if card.Done then Pop.paint("Green") else BoostView.DarkPaint)
	local pips = GearShopView.PipColors
	for i, pip in slot.Pips do
		pip.BackgroundColor3 = if i <= card.Level then (if card.Done then pips.Done else pips.On) else pips.Off
	end
	slot.Description.Text = card.Description
	slot.Effect.Text = card.Effect
	slot.Effect.TextColor3 = if card.Done then rgb(170, 255, 120) else WHITE
	slot.Unit.Text = card.Unit
	slot.Extra.Text = card.Extra
	slot.Price.Text = card.PriceText
	-- the price: gold while you can buy it, green at the top level, white while you can't afford it
	local gold = slot.Price:FindFirstChild("Gold") :: UIGradient?
	if gold then
		gold.Enabled = not card.Done and card.Buy.CanBuy
	end
	slot.Price.TextColor3 = if card.Done then rgb(150, 255, 100) else WHITE
	GearShopView.setIcon(slot.Art, card.Icon)
	setPicture(slot, card.Icon)
	local button = slot.Button
	-- a button showing an answer ("BOUGHT!", "...") keeps its text and
	-- colors until the controller frees it (and refreshes the card)
	if button:GetAttribute("Busy") ~= true then
		button.Text = GearShopView.buttonText(refs, card)
		if card.Done then
			-- MAX: a green tag (no coin)
			BoostView.paintButton(button, "Green")
			BoostView.setMark(button, "")
		else
			style(button, card.Buy.CanBuy, Theme.Accent, Theme.AccentDark)
			BoostView.setMark(button, "coin")
		end
	end
	fitSlot(slot)
end

-- Fills every card from GearShopView.cards (cards with no data keep their last content).
function GearShopView.setCards(refs: Refs, cards: { Card })
	for _, card in cards do
		local slot = refs.Slots[card.Line]
		if slot then
			fillSlot(refs, slot, card)
		end
	end
end

function GearShopView.setCoins(refs: Refs, coins: number)
	refs.BalanceAmount.Text = Format.money(math.max(0, num(coins)))
end

-- A card's status (the server's answer) in its effect box: text in `color` (a bright ink), or nil to show the effect again.
function GearShopView.setStatus(refs: Refs, lineId: string, text: string?, color: Color3?)
	local slot = refs.Slots[lineId]
	if not slot then
		return
	end
	local on = text ~= nil
	slot.Status.Visible = on
	slot.Effect.Visible = not on
	slot.Unit.Visible = not on
	slot.Extra.Visible = not on and refs.ShowExtra
	slot.Status.Text = text or ""
	slot.Status.TextColor3 = BoostView.ink(color or Theme.Text)
	local b = slot.Boxes
	if b.Width > 0 then
		TechShopView.fitText(slot.Status, b.Width - 8, b.StatusHeight, b.Status, math.max(11, b.Status - 4))
	end
end

--[[
	The footer's text (GearShopController.updateHint) for an input ("Mouse",
	"Touch", "Pad": a gamepad whose buttons have no glyph image, named
	`buyName` / `closeName`); `done` = every line is at the top level, so
	there is nothing to buy.
]]
function GearShopView.hintText(input: string, done: boolean, buyName: string?, closeName: string?): string
	local sep = GearShopView.Separator
	if input == "Pad" then
		local close = `{closeName or "B"}: close`
		return if done then `{GearShopView.DoneHint}{sep}{close}` else `{buyName or "A"}: buy{sep}{close}`
	elseif input == "Touch" then
		return if done then GearShopView.DoneHint else "Tap BUY to upgrade"
	end
	return if done then `{GearShopView.DoneHint}{sep}Backspace: close` else `Click BUY to upgrade{sep}Backspace: close`
end

-- Is every card at the top level?
function GearShopView.allDone(cards: { Card }): boolean
	for _, card in cards do
		if not card.Done then
			return false
		end
	end
	return #cards > 0
end

--[[
	The footer hint: `text` (mouse, touch, or a gamepad without glyph
	images), or with `glyphs` (the images of the platform's A and B
	buttons, from GetImageForKeyCode) the glyph row "[A] buy  [B] close"
	("All gear at the top level  [B] close" when `done`). `gamepad`: a
	gamepad plays (implied by glyphs). The compact layout shows the footer
	only for a gamepad, and lays the cards out again when it comes or goes.
]]
function GearShopView.setHint(refs: Refs, text: string, glyphs: { string }?, gamepad: boolean?, done: boolean?)
	refs.Hint.Text = text
	refs.PadMode = glyphs ~= nil
	refs.HintDone = done == true
	if glyphs then
		for i, image in refs.PadGlyphs do
			image.Image = glyphs[i] or ""
		end
	end
	local pad = gamepad == true or glyphs ~= nil
	if pad ~= refs.Gamepad then
		refs.Gamepad = pad
		if refs.Compact then
			-- the footer comes or goes: the cards get its room
			GearShopView.layout(refs, true, refs.LayoutWidth, refs.LayoutHeight)
			return
		end
	end
	showFooter(refs)
end

-- Shows a message in the header (instead of the subtitle).
-- (white: readable on the blue band)
function GearShopView.showReceipt(refs: Refs, text: string, _color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = WHITE
	refs.Receipt.Visible = true
	refs.Subtitle.Visible = false
end

function GearShopView.hideReceipt(refs: Refs)
	refs.Receipt.Visible = false
	refs.Subtitle.Visible = not refs.Compact
end

-- The button a gamepad starts on: the first card that can buy, else the first card's.
function GearShopView.firstButton(refs: Refs): TextButton
	for _, slot in refs.SlotList do
		local card = slot.Card
		if card and card.Buy.CanBuy then
			return slot.Button
		end
	end
	return refs.SlotList[1].Button
end

-- Every button a finger must hit (for the touch-size tests).
function GearShopView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close) }
	for _, slot in refs.SlotList do
		table.insert(list, holderOf(slot.Button))
	end
	return list
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- The window wears the Pop look switch on or off (never LightSkin's
-- recolouring); with the light UI on it also hides Roblox's touch controls
-- while open.
local popBuild = GearShopView.build
GearShopView.build = function(compact: boolean?): Refs
	local refs = popBuild(compact)
	if UIConfig.lightUI() then
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return GearShopView
