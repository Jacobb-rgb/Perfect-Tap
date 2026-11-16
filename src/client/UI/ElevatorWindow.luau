--[[
	ElevatorWindow: the ELEVATOR window (owner 2026-11-15: his two reference
	pictures and "ROBLOX MINING GAME - ELEVATOR UI (FINAL COINS VERSION)"),
	in the Robux Shop's look (UI/ShopFx: thick dark outlines, bright faces
	with a lip, chunky Fredoka One words with a dark edge, 3D buttons with a
	sweeping shine) on a dark navy window.

	  header   the elevator icon (doors, up and down arrows), ELEVATOR,
	           "Choose your destination and travel deeper into the mine.",
	           the red X
	  status   YOUR BLASTER Lv. N, its way to the top level (N of
	           BlasterData.MaxLevel, a bar and the percent) with "Upgrade your
	           blaster to unlock deeper floors.", the player's coins with the
	           gold coin and a green + (the Robux Shop's coins)
	  cards    one per floor (MineFloors.List): its picture edge to edge (the
	           owner's upload IconAssets.ElevatorArt, else a painted backdrop
	           in the floor's colours), the number on a shield, the name, the
	           rarities of its ores and one button:
	             Here    gold frame and halo, CURRENT LOCATION, YOU ARE HERE
	             Travel  TRAVEL and an arrow, in the floor's colour
	             Buy     a basket, PURCHASE, the price and the gold coin
	                     (gold/orange); without the coins darker, NOT ENOUGH
	                     COINS over it (the price stays)
	             Locked  dark, a big lock, BLASTER LV. N REQUIRED, LOCKED
	  banner   COMING SOON (MineFloors.ComingSoon): a big "?", "Something
	           exciting is on the way...", NEXT UPDATE with a clock
	Coins are the only price ever shown (the coin, never a gem or Robux).

	Layout: PC and TV 3 x 2 cards and the banner, all in view; compact
	(phones) 2 columns that scroll under the header and the status line,
	72-unit buttons (about 44 pt). Gamepads: the cards' buttons, the + and
	the X are selectable; the selection stays in the window (SelectionGroup).

	Motion (TweenService; ShopFx.quiet = none): it opens (the dim fades in,
	the window grows from 0.94, the header drops in, the cards pop in one
	after another), a hovered card rises (its edge and button brighten, its
	picture pans a little), a purchase flashes gold (the coin pops, coins fly
	out, the coins count down, the card turns to TRAVEL), a locked card
	shakes (its lock flashes, the requirement lights up), TRAVEL lights its
	card and dims the others, and it closes (shrinks back, a veil, the dim
	fades). Loops (ShopFx marks, the controller plays them): the buttons'
	shine, the gold halo, the title's glint, the "?" float, the clock's wiggle.

	Pure builder + helpers (Instances only): the Lune previews and specs build it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local IconAssets = require(Shared.Config.IconAssets)
local MineFloors = require(Shared.Config.MineFloors)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local ShopFx = require(script.Parent.ShopFx)
local ElevatorView = require(script.Parent.ElevatorView)

local ElevatorWindow = {}

type Props = { [string]: any }

local hex = Color3.fromHex
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function apply(instance: Instance, props: Props?)
	if props then
		local target: any = instance
		for key, value in props do
			target[key] = value
		end
	end
end

---------------------------------------------------------------- data

export type State = "Here" | "Travel" | "Buy" | "Locked"

export type Entry = {
	Index: number,
	Id: string,
	Name: string,
	MinBlaster: number,
	Price: number, -- coins (0: no purchase: a floor you can walk to)
	Bought: boolean,
	State: State,
	Afford: boolean, -- Buy: the player has the coins
	Rarities: { string },
}

--[[
	The cards' states for a player: `level` = the blaster level, `here` = the
	floor of the stop the window was opened at (nil = none), `bought` = the
	floors bought (snapshot ElevatorFloors: Id -> true), `coins` = the coins.
	A floor is Here (that stop), else Locked (blaster too weak), else Buy (a
	price not paid yet), else Travel.
]]
function ElevatorWindow.entries(level: any, here: number?, bought: any, coins: any): { Entry }
	local blaster = if type(level) == "number" and level == level then level else 1
	local money = if type(coins) == "number" and coins == coins then coins else 0
	local owned: { [string]: any } = if type(bought) == "table" then bought else {}
	local list: { Entry } = {}
	for _, floor in MineFloors.List do
		local price = MineFloors.priceOf(floor.Index)
		local paid = owned[floor.Id] == true
		local state: State = if floor.Index == here
			then "Here"
			elseif blaster < floor.MinBlaster then "Locked"
			elseif price > 0 and not paid then "Buy"
			else "Travel"
		table.insert(list, {
			Index = floor.Index,
			Id = floor.Id,
			Name = floor.Name,
			MinBlaster = floor.MinBlaster,
			Price = price,
			Bought = paid,
			State = state,
			Afford = money >= price,
			Rarities = ElevatorView.floorRarities(floor.Index),
		})
	end
	return list
end

-- "BLASTER LV. 9 REQUIRED"
function ElevatorWindow.requirementText(minBlaster: number): string
	return `BLASTER LV. {minBlaster} REQUIRED`
end

-- A price on a button: "750", "5,000", "3.3M" (Format.short).
function ElevatorWindow.priceText(price: number): string
	return Format.short(math.max(0, math.floor(price)))
end

-- The blaster's way to the top level: 0..1 (level 1 of 10 = 0.1).
function ElevatorWindow.progress(level: any): number
	local blaster = if type(level) == "number" and level == level then level else 1
	return math.clamp(blaster / BlasterData.MaxLevel, 0, 1)
end

-- The status line's words under the bar.
function ElevatorWindow.progressHint(level: any): string
	if ElevatorWindow.progress(level) >= 1 then
		return "Top blaster level: every floor can be yours."
	end
	return "Upgrade your blaster to unlock deeper floors."
end

-- "01"
function ElevatorWindow.numberText(index: number): string
	return string.format("%02d", index)
end

-- "GREYSTONE\nQUARRY": the name in capitals, its words on two lines.
function ElevatorWindow.nameText(name: string): string
	local words = string.split(string.upper(name), " ")
	if #words <= 1 then
		return words[1] or ""
	end
	local half = math.ceil(#words / 2)
	return table.concat(words, " ", 1, half) .. "\n" .. table.concat(words, " ", half + 1)
end

---------------------------------------------------------------- colours and sizes

ElevatorWindow.Ink = hex("#0b1030") -- every outline and text edge (navy)
ElevatorWindow.Gold = hex("#ffcf2a")
ElevatorWindow.Body = { hex("#2b367a"), hex("#1d2558"), hex("#121838") }
ElevatorWindow.Head = { hex("#4660d6"), hex("#2a3aa6"), hex("#1a2370") }
ElevatorWindow.Panel = { hex("#1a2250"), hex("#0f1432") }
ElevatorWindow.DimTo = 0.45 -- the dim over the world
ElevatorWindow.Corner = 30
ElevatorWindow.CardCorner = 18

-- the rarity chips: { top, bottom }
ElevatorWindow.RarityColors = {
	Common = { hex("#e0e4ee"), hex("#8f97b0") },
	Uncommon = { hex("#a6ff6a"), hex("#2fb82a") },
	Rare = { hex("#8ae0ff"), hex("#2a7cf0") },
	Epic = { hex("#e0a6ff"), hex("#9a3cf0") },
	Legendary = { hex("#ffe27a"), hex("#f09a0a") },
	Mythic = { hex("#ff9ad8"), hex("#e0208a") },
} :: { [string]: { Color3 } }

export type Style = { Top: Color3, Mid: Color3, Low: Color3, Ink: Color3, Text: Color3 }

ElevatorWindow.Styles = {
	Buy = { Top = hex("#fff27a"), Mid = hex("#ffb41a"), Low = hex("#f2760a"), Ink = hex("#5a2600"), Text = WHITE },
	Poor = { Top = hex("#8c8164"), Mid = hex("#695d42"), Low = hex("#4a412c"), Ink = hex("#1c170c"), Text = hex("#efe2c0") },
	Here = { Top = hex("#5c4818"), Mid = hex("#3e300e"), Low = hex("#2a2008"), Ink = hex("#120d02"), Text = hex("#ffd84a") },
	Locked = { Top = hex("#8a90a8"), Mid = hex("#666c84"), Low = hex("#4c5166"), Ink = hex("#181a24"), Text = hex("#e2e6f0") },
} :: { [string]: Style }

-- A floor's TRAVEL button: its own colour.
function ElevatorWindow.floorStyle(index: number): Style
	local c = ElevatorView.floorColor(index)
	return { Top = c:Lerp(WHITE, 0.42), Mid = c, Low = c:Lerp(BLACK, 0.3), Ink = c:Lerp(BLACK, 0.78), Text = WHITE }
end

-- The button style of an entry.
function ElevatorWindow.styleOf(entry: Entry): Style
	if entry.State == "Travel" then
		return ElevatorWindow.floorStyle(entry.Index)
	elseif entry.State == "Buy" then
		return if entry.Afford then ElevatorWindow.Styles.Buy else ElevatorWindow.Styles.Poor
	end
	return ElevatorWindow.Styles[entry.State] or ElevatorWindow.Styles.Locked
end

-- The words on an entry's button.
function ElevatorWindow.buttonText(entry: Entry): string
	if entry.State == "Here" then
		return "YOU ARE HERE"
	elseif entry.State == "Travel" then
		return "TRAVEL"
	elseif entry.State == "Buy" then
		return "PURCHASE"
	end
	return "LOCKED"
end

-- The line over the button ("" = none).
function ElevatorWindow.noteText(entry: Entry): string
	if entry.State == "Locked" then
		return ElevatorWindow.requirementText(entry.MinBlaster)
	elseif entry.State == "Buy" and not entry.Afford then
		return "NOT ENOUGH COINS"
	end
	return ""
end

export type Metrics = {
	Compact: boolean,
	Columns: number,
	Pad: number, -- the body's edge to its content
	Gap: number, -- between cards
	Header: number,
	Title: number,
	Sub: number,
	Icon: number,
	Close: number,
	Status: number,
	Small: number, -- the status line's small words
	Level: number,
	Coins: number,
	CardH: number, -- compact: a card's height (PC: from the window's height)
	Badge: Vector2,
	Number: number,
	Name: number,
	Chip: number,
	ChipText: number,
	Button: number,
	ButtonText: number,
	Note: number,
	Lock: number,
	Banner: number,
	BannerTitle: number,
	BannerSub: number,
	Hint: number,
}

local PC: Metrics = {
	Compact = false,
	Columns = 3,
	Pad = 18,
	Gap = 14,
	Header = 82,
	Title = 52,
	Sub = 17,
	Icon = 62,
	Close = 54,
	Status = 56,
	Small = 13,
	Level = 28,
	Coins = 26,
	CardH = 0,
	Badge = Vector2.new(50, 58),
	Number = 26,
	Name = 24,
	Chip = 22,
	ChipText = 12,
	Button = 48,
	ButtonText = 21,
	Note = 14,
	Lock = 48,
	Banner = 72,
	BannerTitle = 32,
	BannerSub = 15,
	Hint = 14,
}

local COMPACT: Metrics = {
	Compact = true,
	Columns = 2,
	Pad = 14,
	Gap = 12,
	Header = 80,
	Title = 46,
	Sub = 16,
	Icon = 58,
	Close = 72,
	Status = 58,
	Small = 15,
	Level = 28,
	Coins = 28,
	CardH = 236,
	Badge = Vector2.new(54, 62),
	Number = 28,
	Name = 28,
	Chip = 26,
	ChipText = 15,
	Button = 72,
	ButtonText = 28,
	Note = 17,
	Lock = 54,
	Banner = 100,
	BannerTitle = 36,
	BannerSub = 18,
	Hint = 16,
}

function ElevatorWindow.metricsFor(compact: boolean?): Metrics
	return if compact then COMPACT else PC
end

-- The window's size for the room (design units) the screen leaves.
function ElevatorWindow.windowSize(m: Metrics, maxW: number, maxH: number): Vector2
	if m.Compact then
		return Vector2.new(math.max(560, math.floor(maxW - 12)), math.max(300, math.floor(maxH - 8)))
	end
	return Vector2.new(math.clamp(math.floor(maxW - 40), 880, 1200), math.clamp(math.floor(maxH - 20), 560, 700))
end

---------------------------------------------------------------- refs

export type Card = {
	Index: number,
	Holder: Frame, -- placed by the layout, held by its middle (its UIScale "Scale": pop-in, hover)
	Edge: Frame, -- the dark outline
	Face: TextButton, -- the clipped card (a tap anywhere is the button's)
	Border: UIStroke, -- the floor's colour round the face
	Light: UIStroke, -- the light edge inside (hover brightens it)
	Art: ImageLabel, -- the uploaded picture (hidden without it)
	Backdrop: Frame, -- the drawn backdrop (under the art)
	Dark: Frame, -- the locked shade
	Fade: Frame, -- dims the card while another one is picked
	Flash: Frame, -- the purchase's gold flash
	Halo: Frame, -- the gold halo (here)
	Tag: Frame, -- CURRENT LOCATION
	Badge: Frame,
	Number: TextLabel,
	Name: TextLabel,
	Chips: Frame,
	Lock: GuiObject, -- the big lock (locked)
	Note: Frame, -- the line over the button
	NoteText: TextLabel,
	NoteLock: GuiObject,
	ButtonHolder: Frame,
	Button: TextButton,
	ButtonBright: Frame, -- brightens the button on hover
	Words: TextLabel,
	Price: TextLabel,
	Pin: GuiObject,
	Basket: GuiObject,
	Coin: GuiObject,
	Arrow: GuiObject,
	Shine: Frame,
	Entry: Entry?,
}

export type Refs = {
	Gui: ScreenGui,
	Metrics: Metrics,
	Dim: Frame,
	Group: Frame,
	Root: Frame,
	Body: Frame,
	Veil: Frame,
	Header: Frame,
	Icon: Frame,
	Title: TextLabel,
	Sub: TextLabel,
	CloseHolder: Frame,
	Close: TextButton,
	Status: Frame,
	BlasterIcon: GuiObject,
	BlasterWord: TextLabel,
	Level: TextLabel,
	Track: Frame,
	Fill: Frame,
	Percent: TextLabel,
	ProgressHint: TextLabel,
	CoinIcon: GuiObject,
	CoinAmount: TextLabel,
	PlusHolder: Frame,
	Plus: TextButton,
	Grid: ScrollingFrame,
	Cards: { Card },
	Banner: Frame,
	BannerFace: TextButton,
	Question: TextLabel,
	Next: Frame,
	Message: Frame,
	MessageText: TextLabel,
	Hint: Frame,
	HintText: TextLabel,
	Layer: Frame, -- over everything (flying coins)
	Size: Vector2, -- the window's size now
	Entries: { Entry },
	Picked: number?, -- TRAVEL pressed: this card is lit, the others dimmed
	Coins: number, -- the coins the status line shows
}

---------------------------------------------------------------- small drawings

local function frame(parent: Instance, props: Props): Frame
	local made = UIKit.new("Frame", {
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, parent)
	apply(made, props)
	return made
end

-- A solid triangle pointing up or down: a square turned 45 degrees, half of it showing.
local function triangle(parent: Instance, center: Vector2, w: number, up: boolean, color: Color3, z: number): Frame
	local h = math.floor(w / 2)
	local clip = frame(parent, {
		Name = if up then "Up" else "Down",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
	})
	local side = math.floor(w / math.sqrt(2) + 0.5)
	frame(clip, {
		Name = "Shape",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		Position = if up then UDim2.new(0.5, 0, 1, 0) else UDim2.new(0.5, 0, 0, 0),
		Rotation = 45,
		Size = UDim2.fromOffset(side, side),
		ZIndex = z,
	})
	return clip
end

-- The elevator icon: a blue tile with two doors, an up and a down arrow beside it.
local function elevatorIcon(parent: Instance, size: number, z: number): Frame
	local holder = frame(parent, {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.floor(size * 1.42), size),
		ZIndex = z,
	})
	ShopFx.drop(
		frame(holder, { Name = "TileHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = z }),
		16,
		5,
		z
	)
	local tile = frame(holder, { Name = "Tile", Size = UDim2.fromOffset(size, size), ZIndex = z + 1 })
	ShopFx.face(tile, { hex("#8ae8ff"), hex("#2ab4ff"), hex("#1a62e0") }, math.floor(size * 0.24), 4, 90)
	ShopFx.gloss(tile, math.floor(size * 0.24), z + 2, 0.36)
	-- the doors: two light panels and a dark seam, a lintel over them
	local inset = math.floor(size * 0.2)
	local doorW = math.floor((size - 2 * inset - 4) / 2)
	local doorH = size - 2 * inset - 2
	for i = 0, 1 do
		local door = frame(tile, {
			Name = "Door" .. (i + 1),
			BackgroundColor3 = hex("#e6f8ff"),
			Position = UDim2.fromOffset(inset + i * (doorW + 4), inset + 4),
			Size = UDim2.fromOffset(doorW, doorH - 4),
			ZIndex = z + 3,
		})
		UIKit.corner(door, 3)
		UIKit.new("UIStroke", { Color = ElevatorWindow.Ink, Thickness = 2 }, door)
		UIKit.new("UIGradient", {
			Color = ColorSequence.new(hex("#ffffff"), hex("#9fdcff")),
			Rotation = 90,
		}, door)
	end
	local lintel = frame(tile, {
		Name = "Lintel",
		BackgroundColor3 = ElevatorWindow.Ink,
		Position = UDim2.fromOffset(inset - 2, inset - 2),
		Size = UDim2.fromOffset(size - 2 * inset + 4, 5),
		ZIndex = z + 3,
	})
	UIKit.corner(lintel, 2)
	-- up and down
	local ax = math.floor(size * 1.2)
	local aw = math.floor(size * 0.3)
	triangle(holder, Vector2.new(ax, math.floor(size * 0.3)), aw, true, hex("#7ae6ff"), z + 1)
	triangle(holder, Vector2.new(ax, math.floor(size * 0.7)), aw, false, hex("#7ae6ff"), z + 1)
	return holder
end

-- A location pin: a round head and a point, a dark dot inside.
local function pin(parent: Instance, size: number, color: Color3, z: number): Frame
	local holder = frame(parent, {
		Name = "Pin",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	local head = math.floor(size * 0.72)
	local point = math.floor(size * 0.46)
	frame(holder, {
		Name = "Point",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.62)),
		Rotation = 45,
		Size = UDim2.fromOffset(point, point),
		ZIndex = z,
	})
	local ball = frame(holder, {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = color,
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(head, head),
		ZIndex = z + 1,
	})
	UIKit.corner(ball, 999)
	local dot = frame(ball, {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = ElevatorWindow.Ink,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		ZIndex = z + 2,
	})
	UIKit.corner(dot, 999)
	return holder
end

-- An arrow pointing right: a bar and a head (two bars), white with a dark edge.
local function arrow(parent: Instance, size: number, ink: Color3, z: number): Frame
	local holder = frame(parent, {
		Name = "Arrow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	local t = math.max(4, math.floor(size * 0.2))
	local function bar(name: string, at: UDim2, w: number, rotation: number)
		local b = frame(holder, {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			Rotation = rotation,
			Size = UDim2.fromOffset(w, t),
			ZIndex = z,
		})
		UIKit.corner(b, 999)
		UIKit.new("UIStroke", { Color = ink, Thickness = 2 }, b)
	end
	bar("Shaft", UDim2.fromScale(0.42, 0.5), math.floor(size * 0.72), 0)
	local head = math.floor(size * 0.5)
	bar("HeadUp", UDim2.new(0.62, 0, 0.5, -math.floor(head * 0.32)), head, 45)
	bar("HeadDown", UDim2.new(0.62, 0, 0.5, math.floor(head * 0.32)), head, -45)
	return holder
end

-- A plus: two white bars with a dark edge.
local function plusMark(parent: Instance, size: number, z: number)
	local t = math.max(5, math.floor(size * 0.22))
	for i, rotation in { 0, 90 } do
		local b = frame(parent, {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rotation,
			Size = UDim2.fromOffset(size, t),
			ZIndex = z,
		})
		UIKit.corner(b, 3)
		UIKit.new("UIStroke", { Color = hex("#0b3a05"), Thickness = 2 }, b)
	end
end

-- A drawn gold coin (the icon sheet's stands in once it shows): a gold disc, a darker ring, a "$".
local function drawnCoin(parent: Instance, size: number, z: number, props: Props?): Frame
	local coin = frame(parent, {
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	UIKit.corner(coin, 999)
	UIKit.new("UIGradient", { Color = ColorSequence.new(hex("#fff27a"), hex("#f29a0a")), Rotation = 90 }, coin)
	UIKit.new("UIStroke", { Color = ElevatorWindow.Ink, Thickness = math.max(2, math.floor(size / 14)) }, coin)
	local ring = frame(coin, {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = z + 1,
	})
	UIKit.corner(ring, 999)
	UIKit.new("UIStroke", { Color = hex("#d27a0a"), Thickness = math.max(1.5, size / 18) }, ring)
	ShopFx.text(coin, "$", math.floor(size * 0.56), {
		Name = "Mark",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = hex("#d27a0a"),
		ZIndex = z + 2,
	}, hex("#fff3a0"), 0)
	apply(coin, props)
	return coin
end

-- A drawn lock (the icon sheet's stands in once it shows).
local function drawnLock(parent: Instance, size: number, z: number, props: Props?): Frame
	local holder = frame(parent, {
		Name = "Lock",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	local shackle = frame(holder, {
		Name = "Shackle",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.56, 0.56),
		ZIndex = z,
	})
	UIKit.corner(shackle, 999)
	UIKit.new("UIStroke", { Color = hex("#c8cedc"), Thickness = math.max(3, math.floor(size * 0.12)) }, shackle)
	local body = frame(holder, {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.86, 0.6),
		ZIndex = z + 1,
	})
	ShopFx.face(body, { hex("#fff27a"), hex("#ffc21a"), hex("#e8880a") }, math.floor(size * 0.12), 3, 90)
	local hole = frame(body, {
		Name = "Hole",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = ElevatorWindow.Ink,
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.2, 0.36),
		ZIndex = z + 2,
	})
	UIKit.corner(hole, 999)
	apply(holder, props)
	return holder
end

-- A picture from the shop's icon sheet, else a drawn stand-in (nil: none).
local function iconOr(parent: Instance, name: string, size: number, z: number, props: Props?): GuiObject?
	local image = ShopFx.icon(parent, name, size, props)
	if image then
		image.ZIndex = z
		return image
	end
	if name == "coin" then
		return drawnCoin(parent, size, z, props)
	elseif name == "lock" then
		return drawnLock(parent, size, z, props)
	end
	return nil
end

-- An invisible stand-in so a slot always holds a GuiObject (a picture that never shows).
local function blank(parent: Instance, size: number, name: string): Frame
	return frame(parent, { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Visible = false })
end

---------------------------------------------------------------- the 3D buttons

-- Paints a button face in `style` (a dark outline, the colour with a darker lip at the bottom).
local function paintFace(face: GuiObject, style: Style, height: number)
	local paint = face:FindFirstChild("Paint")
	local colors = { style.Top, style.Mid, style.Low }
	if paint and paint:IsA("UIGradient") then
		paint.Color = ShopFx.faceSequence(colors, height, math.max(4, math.floor(height * 0.11)))
	end
end

---------------------------------------------------------------- the cards

-- A floor's painted backdrop (until its picture is uploaded): its colours, a glow and crystals.
local function backdrop(face: GuiObject, index: number, z: number): Frame
	local floor = MineFloors.ByIndex[index]
	local palette = floor and floor.Palette
	local color = ElevatorView.floorColor(index)
	local holder = frame(face, {
		Name = "Backdrop",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	})
	UIKit.corner(holder, ElevatorWindow.CardCorner - 2)
	local top = if palette then palette.Mid:Lerp(color, 0.45) else color
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top:Lerp(WHITE, 0.12)),
			ColorSequenceKeypoint.new(0.55, top:Lerp(BLACK, 0.35)),
			ColorSequenceKeypoint.new(1, top:Lerp(BLACK, 0.72)),
		}),
		Rotation = 90,
	}, holder)
	-- a soft glow on the right where the crystals stand
	local glow = frame(holder, {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if palette then palette.Accent else color,
		BackgroundTransparency = 0.55,
		Position = UDim2.fromScale(0.74, 0.62),
		Size = UDim2.fromScale(0.5, 0.9),
		ZIndex = z,
	})
	UIKit.corner(glow, 999)
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, glow)
	-- crystals: tall turned squares in the floor's two crystal colours
	local crystalA = if palette then palette.Crystal else color
	local crystalB = if palette then palette.Crystal2 else WHITE
	type Spot = { X: number, Y: number, W: number, H: number, R: number, C: Color3 }
	local spots: { Spot } = {
		{ X = 0.7, Y = 0.66, W = 0.1, H = 0.5, R = -8, C = crystalA },
		{ X = 0.8, Y = 0.7, W = 0.08, H = 0.38, R = 14, C = crystalB },
		{ X = 0.62, Y = 0.74, W = 0.07, H = 0.3, R = -22, C = crystalB },
		{ X = 0.88, Y = 0.76, W = 0.06, H = 0.26, R = 26, C = crystalA },
		{ X = 0.3, Y = 0.82, W = 0.05, H = 0.2, R = 18, C = crystalA },
	}
	for i, spot in spots do
		local c = spot.C
		local crystal = frame(holder, {
			Name = "Crystal" .. i,
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = WHITE,
			Position = UDim2.fromScale(spot.X, spot.Y),
			Rotation = spot.R,
			Size = UDim2.fromScale(spot.W, spot.H),
			ZIndex = z + 1,
		})
		UIKit.corner(crystal, 6)
		UIKit.new("UIStroke", { Color = ElevatorWindow.Ink, Thickness = 2.5 }, crystal)
		UIKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.55)),
				ColorSequenceKeypoint.new(0.5, c),
				ColorSequenceKeypoint.new(1, c:Lerp(BLACK, 0.35)),
			}),
			Rotation = 0,
		}, crystal)
	end
	-- the ground
	local ground = frame(holder, {
		Name = "Ground",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = if palette then palette.Dark else color:Lerp(BLACK, 0.5),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.2),
		ZIndex = z + 2,
	})
	UIKit.corner(ground, ElevatorWindow.CardCorner - 2)
	return holder
end

-- The shield with the floor's number: a dark outline shape, the colour over it, "01".
local function badge(parent: Instance, index: number, size: Vector2, z: number): (Frame, TextLabel)
	local color = ElevatorView.floorColor(index)
	local holder = frame(parent, {
		Name = "Badge",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z,
	})
	local w, h = size.X, size.Y
	local top = math.floor(h * 0.68)
	local function shape(inset: number, c: Color3, zz: number, name: string)
		local rect = frame(holder, {
			Name = name .. "Top",
			BackgroundColor3 = c,
			Position = UDim2.fromOffset(inset, inset),
			Size = UDim2.fromOffset(w - 2 * inset, top - inset),
			ZIndex = zz,
		})
		UIKit.corner(rect, math.max(4, 12 - inset))
		-- the point: a turned square reaching the bottom
		local half = (h - inset) - math.floor(h * 0.6)
		local side = math.floor(half * math.sqrt(2) + 0.5)
		local point = frame(holder, {
			Name = name .. "Point",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = c,
			Position = UDim2.fromOffset(math.floor(w / 2), math.floor(h * 0.6)),
			Rotation = 45,
			Size = UDim2.fromOffset(side, side),
			ZIndex = zz,
		})
		UIKit.corner(point, math.max(3, 7 - inset))
	end
	shape(0, ElevatorWindow.Ink, z, "Outline")
	shape(4, color, z + 1, "Face")
	-- a light band over its top half
	local light = frame(holder, {
		Name = "Light",
		BackgroundColor3 = color:Lerp(WHITE, 0.45),
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(w - 8, math.floor((top - 4) * 0.45)),
		ZIndex = z + 2,
	})
	UIKit.corner(light, 8)
	local number = ShopFx.text(holder, ElevatorWindow.numberText(index), math.floor(h * 0.46), {
		Name = "Number",
		Position = UDim2.fromOffset(0, math.floor(h * 0.06)),
		Size = UDim2.new(1, 0, 0, math.floor(h * 0.56)),
		ZIndex = z + 4,
	}, ElevatorWindow.Ink, 2)
	return holder, number
end

-- One rarity chip.
local function rarityChip(parent: Instance, rarity: string, m: Metrics, order: number): Frame
	local text = string.upper(rarity)
	local w = ShopFx.textWidth(text, m.ChipText) + 20
	local chip = ShopFx.chip(parent, text, w, m.Chip, m.ChipText, {
		Name = "Chip" .. order,
		LayoutOrder = order,
		ZIndex = 9,
	}, ElevatorWindow.RarityColors[rarity] or ElevatorWindow.RarityColors.Common)
	return chip
end

local function newCard(grid: Instance, index: number, m: Metrics): Card
	local z = 4
	local holder = frame(grid, {
		Name = "Floor" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 200),
		ZIndex = z,
	})
	UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, holder)
	-- the gold halo (here): it breathes
	local halo = frame(holder, {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = ElevatorWindow.Gold,
		BackgroundTransparency = 0.5,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 18, 1, 18),
		Visible = false,
		ZIndex = z,
	})
	UIKit.corner(halo, ElevatorWindow.CardCorner + 11)
	halo:SetAttribute("ShopFx", "Glow")
	halo:SetAttribute("Fade", 0.4)
	ShopFx.drop(holder, ElevatorWindow.CardCorner, 6, z)
	local edge = frame(holder, {
		Name = "Edge",
		BackgroundColor3 = ElevatorWindow.Ink,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	})
	UIKit.corner(edge, ElevatorWindow.CardCorner + 4)
	local face = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		BackgroundColor3 = ElevatorWindow.Ink,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(4, 4),
		Selectable = false,
		Size = UDim2.new(1, -8, 1, -8),
		Text = "",
		ZIndex = z + 2,
	}, edge) :: TextButton
	UIKit.corner(face, ElevatorWindow.CardCorner)
	local border = UIKit.new("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = ElevatorView.floorColor(index),
		Thickness = 3,
	}, face) :: UIStroke
	local zz = z + 3
	local back = backdrop(face, index, zz)
	local floor = MineFloors.ByIndex[index]
	local art = UIKit.new("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = zz + 3,
	}, face) :: ImageLabel
	UIKit.corner(art, ElevatorWindow.CardCorner - 2)
	art:SetAttribute("Cover", true) -- (the previews fill the card with it, like Crop)
	if floor and IconAssets.elevatorArtShows(floor.Id) then
		-- (the painted backdrop stays under it: seen while Roblox checks the upload or if it never loads)
		IconAssets.applyElevatorArt(art, floor.Id)
		art.Visible = true
	end
	-- dark shades: over the words at the top left and under the button
	local shadeTop = frame(face, {
		Name = "ShadeTop",
		BackgroundColor3 = ElevatorWindow.Ink,
		Size = UDim2.fromScale(1, 0.62),
		ZIndex = zz + 4,
	})
	UIKit.new("UIGradient", {
		Rotation = 70,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(0.55, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shadeTop)
	local shadeLow = frame(face, {
		Name = "ShadeLow",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = ElevatorWindow.Ink,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.46),
		ZIndex = zz + 4,
	})
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
	}, shadeLow)
	local dark = frame(face, {
		Name = "Dark",
		BackgroundColor3 = hex("#0a0d22"),
		BackgroundTransparency = 0.38,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = zz + 5,
	})
	UIKit.corner(dark, ElevatorWindow.CardCorner - 2)
	-- the light edge inside (hover brightens it)
	local rim = frame(face, {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = zz + 6,
	})
	UIKit.corner(rim, ElevatorWindow.CardCorner - 2)
	local light = UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = WHITE,
		Thickness = 2,
		Transparency = 0.7,
	}, rim) :: UIStroke
	local zw = zz + 7
	local shield, number = badge(face, index, m.Badge, zw)
	shield.Position = UDim2.fromOffset(12, 12)
	local name = ShopFx.text(face, ElevatorWindow.nameText(floor and floor.Name or ""), m.Name, {
		Name = "Name",
		LineHeight = 0.92,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = zw + 1,
	}, ElevatorWindow.Ink, 3)
	local chips = frame(face, {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, m.Chip),
		ZIndex = zw,
	})
	UIKit.list(chips, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	for i, rarity in ElevatorView.floorRarities(index) do
		if i <= 3 then
			rarityChip(chips, rarity, m, i)
		end
	end
	-- the big lock (locked)
	local lock = iconOr(face, "lock", m.Lock, zw + 2, {
		Name = "LockBig",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
	}) or blank(face, m.Lock, "LockBig")
	UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, lock)
	-- the line over the button: a small lock and the words
	local note = frame(face, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, m.Note + 8),
		Visible = false,
		ZIndex = zw,
	})
	UIKit.list(note, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local noteLock = iconOr(note, "lock", m.Note + 6, zw + 1, { Name = "Lock", LayoutOrder = 1 }) or blank(note, m.Note + 6, "Lock")
	local noteText = ShopFx.text(note, "", m.Note, {
		Name = "Words",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(10, m.Note + 6),
		ZIndex = zw + 1,
	}, ElevatorWindow.Ink, 0)
	-- the button
	local buttonHolder = frame(face, {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, m.Button),
		ZIndex = zw,
	})
	ShopFx.drop(buttonHolder, ShopFx.ButtonCorner, ShopFx.ButtonDrop, zw)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.5),
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = zw + 1,
	}, buttonHolder) :: TextButton
	local style = ElevatorWindow.floorStyle(index)
	ShopFx.face(button, { style.Top, style.Mid, style.Low }, ShopFx.ButtonCorner, 4)
	paintFace(button, style, m.Button)
	local shine = frame(button, {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zw + 2,
	})
	UIKit.corner(shine, ShopFx.ButtonCorner)
	local sweep = UIKit.new("UIGradient", {
		Name = "Sweep",
		Rotation = 18,
		Offset = Vector2.new(ShopFx.ShineFrom, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shine)
	sweep:SetAttribute("ShopFx", "Shine")
	local bright = frame(button, {
		Name = "Bright",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zw + 2,
	})
	UIKit.corner(bright, ShopFx.ButtonCorner)
	local lip = math.max(4, math.floor(m.Button * 0.11))
	local row = frame(button, {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -lip),
		ZIndex = zw + 3,
	})
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local iconSize = math.floor(m.ButtonText * 1.25)
	local pinIcon = pin(row, iconSize, ElevatorWindow.Gold, zw + 4)
	pinIcon.LayoutOrder = 1
	local basket = iconOr(row, "basket", iconSize + 4, zw + 4, { Name = "Basket", LayoutOrder = 1 }) or blank(row, iconSize, "Basket")
	local words = ShopFx.text(row, "TRAVEL", m.ButtonText, {
		Name = "Words",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(ShopFx.textWidth("TRAVEL", m.ButtonText), m.ButtonText + 4),
		ZIndex = zw + 4,
	}, style.Ink, 0)
	local price = ShopFx.text(row, "", m.ButtonText, {
		Name = "Price",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(10, m.ButtonText + 4),
		Visible = false,
		ZIndex = zw + 4,
	}, style.Ink, 0)
	local coin = iconOr(row, "coin", iconSize, zw + 4, { Name = "Coin", LayoutOrder = 4 }) or blank(row, iconSize, "Coin")
	local arrowIcon = arrow(row, iconSize, style.Ink, zw + 4)
	arrowIcon.LayoutOrder = 5
	-- the purchase's gold flash (over the whole card) and the picked-card dimmer
	local flash = frame(face, {
		Name = "Flash",
		BackgroundColor3 = hex("#ffe27a"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zw + 8,
	})
	UIKit.corner(flash, ElevatorWindow.CardCorner - 2)
	local fade = frame(holder, {
		Name = "Fade",
		BackgroundColor3 = hex("#05081c"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 12,
	})
	UIKit.corner(fade, ElevatorWindow.CardCorner + 4)
	-- CURRENT LOCATION, on the top edge
	local tagText = "CURRENT LOCATION"
	local tagSize = math.floor(m.ChipText * 1.08)
	local tagW = ShopFx.textWidth(tagText, tagSize) + tagSize * 2 + 22
	local tag = frame(holder, {
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.58, 0, 0, 2),
		Size = UDim2.fromOffset(tagW, math.floor(tagSize * 2)),
		Visible = false,
		ZIndex = z + 10,
	})
	ShopFx.drop(tag, 12, 4, z + 10)
	local tagFace = frame(tag, { Name = "Face", Size = UDim2.fromScale(1, 1), ZIndex = z + 11 })
	ShopFx.face(tagFace, { hex("#fff27a"), hex("#ffc21a"), hex("#f0900a") }, 12, 3, 90)
	local tagRow = frame(tagFace, {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 12,
	})
	UIKit.list(tagRow, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	pin(tagRow, math.floor(tagSize * 1.25), ElevatorWindow.Ink, z + 13).LayoutOrder = 1
	local tagLabel = ShopFx.text(tagRow, tagText, tagSize, {
		Name = "Words",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(ShopFx.textWidth(tagText, tagSize), tagSize + 4),
		TextColor3 = ElevatorWindow.Ink,
		ZIndex = z + 13,
	}, hex("#fff6c0"), 0)
	local tagEdge = tagLabel:FindFirstChild("Edge")
	if tagEdge and tagEdge:IsA("UIStroke") then
		tagEdge.Thickness = 1
	end
	return {
		Index = index,
		Holder = holder,
		Edge = edge,
		Face = face,
		Border = border,
		Light = light,
		Art = art,
		Backdrop = back,
		Dark = dark,
		Fade = fade,
		Flash = flash,
		Halo = halo,
		Tag = tag,
		Badge = shield,
		Number = number,
		Name = name,
		Chips = chips,
		Lock = lock,
		Note = note,
		NoteText = noteText,
		NoteLock = noteLock,
		ButtonHolder = buttonHolder,
		Button = button,
		ButtonBright = bright,
		Words = words,
		Price = price,
		Pin = pinIcon,
		Basket = basket,
		Coin = coin,
		Arrow = arrowIcon,
		Shine = shine,
		Entry = nil,
	}
end

-- Sets a TextLabel's words and its width (in a row).
local function setRowText(label: TextLabel, text: string)
	label.Text = text
	label.Size = UDim2.fromOffset(math.max(1, ShopFx.textWidth(text, label.TextSize)), label.Size.Y.Offset)
end

-- Recolours the outline of every word and drawing in a button row.
local function inkRow(row: Instance, ink: Color3)
	for _, d in row:GetDescendants() do
		if d:IsA("UIStroke") and (d.Name == "Edge" or d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Arrow") then
			d.Color = ink
		end
	end
end

--[[
	Shows `entry` on its card: the frame, halo and tag (here), the locked
	shade and lock, the line over the button and the button itself.
]]
function ElevatorWindow.setCard(card: Card, entry: Entry, m: Metrics)
	card.Entry = entry
	local state = entry.State
	local color = ElevatorView.floorColor(entry.Index)
	local here = state == "Here"
	local locked = state == "Locked"
	card.Border.Color = if here then ElevatorWindow.Gold elseif locked then color:Lerp(ElevatorWindow.Ink, 0.45) else color
	card.Border.Thickness = if here then 4 else 3
	card.Halo.Visible = here
	card.Tag.Visible = here
	card.Dark.Visible = locked
	card.Lock.Visible = locked
	-- the line over the button
	local note = ElevatorWindow.noteText(entry)
	card.Note.Visible = note ~= ""
	card.NoteLock.Visible = locked
	setRowText(card.NoteText, note)
	card.NoteText.TextColor3 = if locked then hex("#e8ecff") else hex("#ff7a8a")
	-- the button
	local style = ElevatorWindow.styleOf(entry)
	paintFace(card.Button, style, m.Button)
	card.Button:SetAttribute("State", state)
	card.Shine.Visible = state == "Travel" or (state == "Buy" and entry.Afford)
	card.Words.TextColor3 = style.Text
	setRowText(card.Words, ElevatorWindow.buttonText(entry))
	local buy = state == "Buy"
	card.Price.Visible = buy
	card.Price.TextColor3 = style.Text
	if buy then
		setRowText(card.Price, ElevatorWindow.priceText(entry.Price))
	end
	card.Pin.Visible = here
	card.Basket.Visible = buy
	card.Coin.Visible = buy
	card.Arrow.Visible = state == "Travel"
	inkRow(card.Button, style.Ink)
end

---------------------------------------------------------------- the window

-- The red X (the shop's): a dark slab, a red face with a lip, a white X.
local function closeButton(parent: Instance, size: number, z: number): (Frame, TextButton)
	local holder = frame(parent, {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Rotation = 4,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	ShopFx.drop(holder, 15, 5, z)
	local close = UIKit.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.5),
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = z + 1,
	}, holder) :: TextButton
	ShopFx.face(close, { hex("#ff7a7a"), hex("#e0262f"), hex("#b4141e") }, 15, 4, 90)
	ShopFx.gloss(close, 15, z + 2, 0.4)
	ShopFx.bindPress(close, holder)
	ShopFx.text(close, "X", math.floor(size * 0.66), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 3,
	})
	return holder, close
end

local function divider(parent: Instance, z: number): Frame
	return frame(parent, {
		Name = "Divider",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		Size = UDim2.fromOffset(2, 10),
		ZIndex = z,
	})
end

function ElevatorWindow.build(compact: boolean?): Refs
	local m = ElevatorWindow.metricsFor(compact)
	local gui = UIKit.screen("TerraForgeElevator", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("MotionSkip", true) -- (it opens itself; the motion watcher leaves it)
	gui:SetAttribute("Compact", m.Compact)
	local dim = frame(gui, {
		Name = "Dim",
		BackgroundColor3 = hex("#05081c"),
		BackgroundTransparency = ElevatorWindow.DimTo,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
	local group = frame(gui, {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1200, 700),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	UIKit.new("UIScale", { Name = "OpenPop", Scale = 1 }, group)
	ShopFx.drop(group, ElevatorWindow.Corner, 10, 1, { Name = "WindowDrop" })
	local rim = 6
	local root = frame(group, {
		Name = "Window",
		Active = true,
		BackgroundColor3 = ElevatorWindow.Ink,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	UIKit.corner(root, ElevatorWindow.Corner)
	UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = hex("#7a9cff"),
		Thickness = 2.5,
		Transparency = 0.55,
	}, root)
	local body = frame(root, {
		Name = "Body",
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -2 * rim),
		ZIndex = 2,
	})
	ShopFx.face(body, ElevatorWindow.Body, ElevatorWindow.Corner - rim, 0, 90)
	-- the header band (rounded top, square bottom)
	local header = frame(root, {
		Name = "Header",
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header),
		ZIndex = 3,
	})
	ShopFx.face(header, ElevatorWindow.Head, ElevatorWindow.Corner - rim, 0, 90)
	local headerFill = frame(root, {
		Name = "HeaderFill",
		Position = UDim2.fromOffset(rim, rim + math.floor(m.Header / 2)),
		Size = UDim2.new(1, -2 * rim, 0, math.ceil(m.Header / 2)),
		ZIndex = 3,
	})
	ShopFx.face(headerFill, { ElevatorWindow.Head[2], ElevatorWindow.Head[3] }, 0, 0, 90)
	local band = frame(root, {
		Name = "Band",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header),
		ZIndex = 4,
	})
	ShopFx.studs(band, 1400, m.Header, 26, 0.5, 4)
	frame(root, {
		Name = "HeaderLine",
		BackgroundColor3 = ElevatorWindow.Ink,
		Position = UDim2.fromOffset(rim, rim + m.Header - 3),
		Size = UDim2.new(1, -2 * rim, 0, 5),
		ZIndex = 5,
	})
	local icon = elevatorIcon(root, m.Icon, 6)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	local title = ShopFx.title(root, "ELEVATOR", m.Title, { WHITE, WHITE, hex("#9fd8ff") }, {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(ShopFx.textWidth("ELEVATOR", m.Title) + 20, m.Title + 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 5)
	local titleEdge = title:FindFirstChild("Edge")
	if titleEdge and titleEdge:IsA("UIStroke") then
		titleEdge.Thickness = 5
	end
	ShopFx.glint(title)
	local sub = ShopFx.text(root, "Choose your destination and travel deeper into the mine.", m.Sub, {
		Name = "Sub",
		AnchorPoint = Vector2.new(0, 0),
		Size = UDim2.fromOffset(640, m.Sub + 4),
		TextColor3 = hex("#d8e6ff"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 0)
	local closeHolder, close = closeButton(root, m.Close, 8)
	-- the status line
	local status = frame(body, {
		Name = "Status",
		Size = UDim2.fromOffset(600, m.Status),
		ZIndex = 5,
	})
	ShopFx.face(status, ElevatorWindow.Panel, 16, 3, 90)
	ShopFx.rim(status, 16, 6, 0.85)
	local blasterIcon = iconOr(status, "blaster", m.Status - 10, 7, {
		Name = "Blaster",
		AnchorPoint = Vector2.new(0, 0.5),
		Rotation = -8,
	}) or blank(status, m.Status - 10, "Blaster")
	local blasterWord = ShopFx.text(status, "YOUR BLASTER", m.Small, {
		Name = "BlasterWord",
		Size = UDim2.fromOffset(160, m.Small + 4),
		TextColor3 = hex("#9cc4ff"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 0)
	local level = ShopFx.title(status, "Lv. 1", m.Level, { hex("#fff6a0"), hex("#ffd23a"), hex("#ff9a1a") }, {
		Name = "Level",
		Size = UDim2.fromOffset(160, m.Level + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 2)
	local div1 = divider(status, 6)
	div1.Name = "Divider1"
	local track = frame(status, {
		Name = "Track",
		BackgroundColor3 = hex("#080b20"),
		Size = UDim2.fromOffset(300, 18),
		ZIndex = 6,
	})
	UIKit.corner(track, 9)
	UIKit.new("UIStroke", { Color = ElevatorWindow.Ink, Thickness = 2 }, track)
	local fill = frame(track, {
		Name = "Fill",
		Size = UDim2.fromScale(0.1, 1),
		ZIndex = 7,
	})
	UIKit.corner(fill, 9)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(hex("#3ad0ff"), hex("#2a7cff")),
		Rotation = 0,
	}, fill)
	local fillLight = frame(fill, {
		Name = "Light",
		BackgroundTransparency = 0.55,
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 0.32, 0),
		ZIndex = 8,
	})
	UIKit.corner(fillLight, 4)
	local percent = ShopFx.text(status, "10%", math.floor(m.Level * 0.78), {
		Name = "Percent",
		Size = UDim2.fromOffset(70, m.Level),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 2)
	local progressHint = ShopFx.text(status, ElevatorWindow.progressHint(1), m.Small, {
		Name = "ProgressHint",
		Size = UDim2.fromOffset(400, m.Small + 4),
		TextColor3 = hex("#c4d2ff"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 0)
	local div2 = divider(status, 6)
	div2.Name = "Divider2"
	local coinIcon = iconOr(status, "coin", math.floor(m.Status * 0.66), 7, {
		Name = "CoinIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
	}) or drawnCoin(status, math.floor(m.Status * 0.66), 7, { Name = "CoinIcon", AnchorPoint = Vector2.new(0.5, 0.5) })
	UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, coinIcon)
	local coinAmount = ShopFx.text(status, "0", m.Coins, {
		Name = "CoinAmount",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(150, m.Coins + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, ElevatorWindow.Ink, 2)
	local plusSize = math.floor(m.Status * 0.66)
	local plusHolder = frame(status, {
		Name = "PlusHolder",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(plusSize, plusSize),
		ZIndex = 7,
	})
	ShopFx.drop(plusHolder, 10, 4, 7)
	local plus = UIKit.new("TextButton", {
		Name = "Plus",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.5),
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 8,
	}, plusHolder) :: TextButton
	ShopFx.face(plus, { hex("#a4ff5a"), hex("#4fd62a"), hex("#2aa61a") }, 10, 3, 90)
	ShopFx.gloss(plus, 10, 9, 0.4)
	plusMark(plus, math.floor(plusSize * 0.56), 10)
	ShopFx.bindPress(plus, plusHolder)
	-- the cards and the banner (phones: they scroll)
	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ScrollBarImageColor3 = hex("#c8d6ff"),
		ScrollBarThickness = if m.Compact then 10 else 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = m.Compact,
		Selectable = false,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ZIndex = 4,
	}, body) :: ScrollingFrame
	local cards: { Card } = {}
	for _, floor in MineFloors.List do
		local card = newCard(grid, floor.Index, m)
		table.insert(cards, card)
	end
	-- COMING SOON
	local banner = frame(grid, {
		Name = "ComingSoon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1100, m.Banner),
		ZIndex = 4,
	})
	UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, banner)
	ShopFx.drop(banner, ElevatorWindow.CardCorner, 6, 4)
	local bannerEdge = frame(banner, {
		Name = "Edge",
		BackgroundColor3 = ElevatorWindow.Ink,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	UIKit.corner(bannerEdge, ElevatorWindow.CardCorner + 4)
	local bannerFace = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(4, 4),
		Selectable = false,
		Size = UDim2.new(1, -8, 1, -8),
		Text = "",
		ZIndex = 6,
	}, bannerEdge) :: TextButton
	ShopFx.face(bannerFace, { hex("#3a2a8a"), hex("#22185c"), hex("#120c36") }, ElevatorWindow.CardCorner, 0, 90)
	UIKit.new("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = hex("#7a5cff"),
		Thickness = 3,
	}, bannerFace)
	local bannerArt = UIKit.new("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
	}, bannerFace) :: ImageLabel
	UIKit.corner(bannerArt, ElevatorWindow.CardCorner - 2)
	bannerArt:SetAttribute("Cover", true)
	if IconAssets.elevatorArtShows("ComingSoon") then
		IconAssets.applyElevatorArt(bannerArt, "ComingSoon")
		bannerArt.Visible = true
	else
		-- a mystery mine: dark peaks and two faint crystals
		for i, p in { { 0.1, 0.9, 120, -14 }, { 0.3, 1.0, 160, 10 }, { 0.72, 0.95, 140, -8 }, { 0.9, 1.0, 180, 12 } } do
			local peak = frame(bannerFace, {
				Name = "Peak" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = hex("#160f40"),
				Position = UDim2.fromScale(p[1], p[2]),
				Rotation = 45 + p[4],
				Size = UDim2.fromOffset(p[3], p[3]),
				ZIndex = 7,
			})
			UIKit.corner(peak, 10)
		end
		for i, p in { { 0.16, 0.6, -12 }, { 0.84, 0.55, 16 } } do
			local crystal = frame(bannerFace, {
				Name = "Crystal" .. i,
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = hex("#a68aff"),
				BackgroundTransparency = 0.25,
				Position = UDim2.fromScale(p[1], p[2] + 0.4),
				Rotation = p[3],
				Size = UDim2.fromOffset(16, 40),
				ZIndex = 8,
			})
			UIKit.corner(crystal, 5)
		end
	end
	-- the big "?" (it floats: its holder carries the mark, so its dark copy floats with it)
	local questionHolder = frame(bannerFace, {
		Name = "QuestionHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.16, 0, 0.5, 0),
		Rotation = -8,
		Size = UDim2.fromOffset(math.floor(m.Banner * 0.8), m.Banner),
		ZIndex = 10,
	})
	questionHolder:SetAttribute("ShopFx", "Float")
	questionHolder:SetAttribute("Rise", 5)
	local question = ShopFx.title(questionHolder, "?", math.floor(m.Banner * 0.82), { WHITE, hex("#d8c8ff"), hex("#a68aff") }, {
		Name = "Question",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
	}, hex("#1a0f4a"), 4)
	local soonTitle = ShopFx.title(bannerFace, "COMING SOON", m.BannerTitle, { WHITE, WHITE, hex("#c8b8ff") }, {
		Name = "SoonTitle",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(ShopFx.textWidth("COMING SOON", m.BannerTitle) + 12, m.BannerTitle + 6),
		ZIndex = 10,
	}, hex("#140a3a"), 3)
	local soonSub = ShopFx.text(bannerFace, "Something exciting is on the way...", m.BannerSub, {
		Name = "SoonSub",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(ShopFx.textWidth("Something exciting is on the way...", m.BannerSub) + 12, m.BannerSub + 6),
		TextColor3 = hex("#d8ccff"),
		ZIndex = 10,
	}, hex("#140a3a"), 0)
	local nextH = math.floor(m.Banner * 0.58)
	local nextW = ShopFx.textWidth("NEXT UPDATE", math.floor(nextH * 0.4)) + nextH + 34
	local nextTag = frame(bannerFace, {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(nextW, nextH),
		ZIndex = 10,
	})
	ShopFx.drop(nextTag, 14, 4, 10)
	local nextFace = frame(nextTag, { Name = "Face", Size = UDim2.fromScale(1, 1), ZIndex = 11 })
	ShopFx.face(nextFace, { hex("#e0a0ff"), hex("#a64dff"), hex("#6a1ad0") }, 14, 3, 90)
	ShopFx.gloss(nextFace, 14, 12, 0.4)
	local nextRow = frame(nextFace, {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 12,
	})
	UIKit.list(nextRow, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local clock = iconOr(nextRow, "clock", math.floor(nextH * 0.66), 13, { Name = "Clock", LayoutOrder = 1 })
	if clock then
		clock:SetAttribute("ShopFx", "Wiggle")
		clock:SetAttribute("Swing", 8)
	end
	ShopFx.text(nextRow, "NEXT UPDATE", math.floor(nextH * 0.4), {
		Name = "Words",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(ShopFx.textWidth("NEXT UPDATE", math.floor(nextH * 0.4)), math.floor(nextH * 0.4) + 4),
		ZIndex = 13,
	}, hex("#2a0a5a"), 0)
	-- the message (a refusal, a thank you): a pill over the cards
	local message = frame(body, {
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = hex("#0a0d24"),
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(560, 44),
		Visible = false,
		ZIndex = 40,
	})
	UIKit.corner(message, 22)
	UIKit.new("UIStroke", { Color = hex("#7a9cff"), Thickness = 2, Transparency = 0.3 }, message)
	local messageText = ShopFx.text(message, "", 18, {
		Name = "Words",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextWrapped = true,
		ZIndex = 41,
	}, ElevatorWindow.Ink, 0)
	-- the control hint on the bottom edge
	local hint = frame(root, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = hex("#0a0d24"),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(360, 30),
		Visible = false,
		ZIndex = 9,
	})
	UIKit.corner(hint, 15)
	UIKit.new("UIStroke", { Color = hex("#7a9cff"), Thickness = 2, Transparency = 0.4 }, hint)
	local hintText = ShopFx.text(hint, "", m.Hint, {
		Name = "Words",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = hex("#d8e6ff"),
		ZIndex = 10,
	}, ElevatorWindow.Ink, 0)
	-- the veil (closing) and the layer over everything (flying coins)
	local veil = frame(root, {
		Name = "Veil",
		BackgroundColor3 = hex("#05081c"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
	})
	UIKit.corner(veil, ElevatorWindow.Corner)
	local layer = frame(group, {
		Name = "Layer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	})
	local refs: Refs = {
		Gui = gui,
		Metrics = m,
		Dim = dim,
		Group = group,
		Root = root,
		Body = body,
		Veil = veil,
		Header = header,
		Icon = icon,
		Title = title,
		Sub = sub,
		CloseHolder = closeHolder,
		Close = close,
		Status = status,
		BlasterIcon = blasterIcon,
		BlasterWord = blasterWord,
		Level = level,
		Track = track,
		Fill = fill,
		Percent = percent,
		ProgressHint = progressHint,
		CoinIcon = coinIcon,
		CoinAmount = coinAmount,
		PlusHolder = plusHolder,
		Plus = plus,
		Grid = grid,
		Cards = cards,
		Banner = banner,
		BannerFace = bannerFace,
		Question = question,
		Next = nextTag,
		Message = message,
		MessageText = messageText,
		Hint = hint,
		HintText = hintText,
		Layer = layer,
		Size = Vector2.new(1200, 700),
		Entries = {},
		Picked = nil,
		Coins = 0,
	}
	ElevatorWindow.layout(refs, 1280, 720)
	ElevatorWindow.setStatus(refs, 1, 0)
	-- (the soon words sit round the banner's middle)
	ShopFx.place(soonTitle, UDim2.new(0.5, 0, 0.5, 2))
	ShopFx.place(soonSub, UDim2.new(0.5, 0, 0.5, 4))
	return refs
end

-- Is this window built for the other kind of screen?
function ElevatorWindow.needsRebuild(refs: Refs, compact: boolean): boolean
	return refs.Metrics.Compact ~= compact
end

-- Lays the inside of one card out for its size.
local function layoutCard(card: Card, w: number, h: number, m: Metrics)
	card.Holder.Size = UDim2.fromOffset(w, h)
	local inner = w - 8
	local innerH = h - 8
	local edge = 10
	card.Badge.Position = UDim2.fromOffset(edge, edge)
	local nameX = edge + m.Badge.X + 10
	local nameW = inner - nameX - edge
	local nameH = math.floor(m.Name * 2 * 0.92) + 4
	ShopFx.place(card.Name, UDim2.fromOffset(nameX, edge + 1), UDim2.fromOffset(nameW, nameH))
	ShopFx.limit(card.Name, m.Name, math.max(16, m.Name - 8))
	local chipsY = edge + math.max(m.Badge.Y - m.Chip, nameH + 3)
	card.Chips.Position = UDim2.fromOffset(nameX, chipsY)
	card.Chips.Size = UDim2.fromOffset(nameW, m.Chip)
	-- the button at the bottom, the line over it, the big lock on the right over the picture
	local bw = math.min(inner - 28, if m.Compact then 330 else 250)
	card.ButtonHolder.Size = UDim2.fromOffset(bw, m.Button)
	card.ButtonHolder.Position = UDim2.new(0.5, 0, 0, innerH - edge)
	local noteY = innerH - edge - m.Button - 5
	card.Note.Position = UDim2.new(0.5, 0, 0, noteY)
	card.Note.Size = UDim2.fromOffset(inner - 20, m.Note + 6)
	local lockY = math.floor((chipsY + m.Chip + noteY - m.Note - 6) / 2)
	card.Lock.Position = UDim2.new(1, -math.floor(m.Lock * 0.8), 0, math.max(lockY, chipsY + math.floor(m.Lock / 2)))
	-- (on the right of the top edge: clear of the name)
	card.Tag.Position = UDim2.new(1, -(math.floor(card.Tag.Size.X.Offset / 2) + 18), 0, 1)
end

--[[
	Fits the window to the room the screen leaves (`maxW` x `maxH` design
	units): the header, the status line and the cards (PC: 3 x 2 and the
	banner; compact: 2 columns that scroll, the banner at their end).
]]
function ElevatorWindow.layout(refs: Refs, maxW: number, maxH: number)
	local m = refs.Metrics
	local size = ElevatorWindow.windowSize(m, maxW, maxH)
	refs.Size = size
	refs.Group.Size = UDim2.fromOffset(size.X, size.Y)
	local rim = 6
	local bodyW = size.X - 2 * rim
	-- the header: the icon, the title and its line, the X
	local titleW = refs.Title.Size.X.Offset
	refs.Icon.Position = UDim2.fromOffset(rim + 20, rim + math.floor(m.Header / 2))
	local titleX = rim + 20 + math.floor(m.Icon * 1.42) + 14
	local subShown = not m.Compact or size.X >= 900
	local titleY = rim + math.floor(m.Header / 2) - (if subShown then math.floor(m.Sub * 0.62) else 0)
	ShopFx.place(refs.Title, UDim2.fromOffset(titleX, titleY))
	ShopFx.setVisible(refs.Sub, subShown)
	refs.Sub.Size = UDim2.fromOffset(math.max(100, bodyW - (titleX - rim) - m.Close - 40), m.Sub + 4)
	ShopFx.place(refs.Sub, UDim2.fromOffset(titleX + 4, titleY + math.floor(m.Title * 0.48)))
	if not subShown then
		refs.Sub.Size = UDim2.fromOffset(titleW, m.Sub + 4)
	end
	refs.CloseHolder.Position = UDim2.new(1, -(rim + 14 + math.floor(m.Close / 2)), 0, rim + math.floor(m.Header / 2))
	-- the status line
	local pad = m.Pad
	local statusY = m.Header + 8
	local statusW = bodyW - 2 * pad
	refs.Status.Position = UDim2.fromOffset(pad, statusY)
	refs.Status.Size = UDim2.fromOffset(statusW, m.Status)
	local sh = m.Status
	refs.BlasterIcon.Position = UDim2.fromOffset(10, math.floor(sh / 2))
	local wordsX = 10 + (sh - 10) + 10
	ShopFx.place(refs.BlasterWord, UDim2.fromOffset(wordsX, math.floor(sh / 2) - m.Small - 6))
	ShopFx.place(refs.Level, UDim2.fromOffset(wordsX, math.floor(sh / 2) - 6))
	local leftW = wordsX + 120
	local coinsW = math.floor(m.Status * 0.66) + 150 + math.floor(m.Status * 0.66) + 30
	local div1 = refs.Status:FindFirstChild("Divider1") :: Frame
	local div2 = refs.Status:FindFirstChild("Divider2") :: Frame
	div1.Position = UDim2.fromOffset(leftW, 10)
	div1.Size = UDim2.fromOffset(2, sh - 20)
	div2.Position = UDim2.fromOffset(statusW - coinsW, 10)
	div2.Size = UDim2.fromOffset(2, sh - 20)
	local barX = leftW + 22
	local barW = math.max(120, statusW - coinsW - barX - 22 - 76)
	local hintShown = not m.Compact
	refs.Track.Position = UDim2.fromOffset(barX, if hintShown then math.floor(sh * 0.22) else math.floor(sh / 2) - 9)
	refs.Track.Size = UDim2.fromOffset(barW, 18)
	ShopFx.place(refs.Percent, UDim2.fromOffset(barX + barW + 12, refs.Track.Position.Y.Offset - math.floor(m.Level / 2) + 9))
	ShopFx.setVisible(refs.ProgressHint, hintShown)
	refs.ProgressHint.Size = UDim2.fromOffset(barW + 80, m.Small + 4)
	ShopFx.place(refs.ProgressHint, UDim2.fromOffset(barX, math.floor(sh * 0.22) + 24))
	local coinX = statusW - coinsW + 22 + math.floor(m.Status * 0.33)
	refs.CoinIcon.Position = UDim2.fromOffset(coinX, math.floor(sh / 2))
	ShopFx.place(refs.CoinAmount, UDim2.fromOffset(coinX + math.floor(m.Status * 0.33) + 10, math.floor(sh / 2)))
	refs.PlusHolder.Position = UDim2.fromOffset(statusW - 12, math.floor(sh / 2))
	-- the cards and the banner
	local gridY = statusY + m.Status + 12
	local gridH = size.Y - 2 * rim - gridY
	local grid = refs.Grid
	grid.Position = UDim2.fromOffset(0, gridY)
	grid.Size = UDim2.fromOffset(bodyW, gridH)
	local columns = m.Columns
	local rows = math.ceil(#refs.Cards / columns)
	local scrollbar = if m.Compact then 12 else 0
	local cardW = math.floor((bodyW - 2 * pad - scrollbar - (columns - 1) * m.Gap) / columns)
	local cardH = m.CardH
	if not m.Compact then
		local bannerTop = gridH - pad - m.Banner
		cardH = math.floor((bannerTop - m.Gap - 8 - (rows - 1) * m.Gap) / rows)
	end
	for i, card in refs.Cards do
		local col = (i - 1) % columns
		local row = (i - 1) // columns
		local x = pad + col * (cardW + m.Gap) + math.floor(cardW / 2)
		local y = 8 + row * (cardH + m.Gap) + math.floor(cardH / 2)
		card.Holder.Position = UDim2.fromOffset(x, y)
		layoutCard(card, cardW, cardH, m)
	end
	local bannerW = bodyW - 2 * pad - scrollbar
	local bannerY = 8 + rows * (cardH + m.Gap) + 4
	refs.Banner.Size = UDim2.fromOffset(bannerW, m.Banner)
	refs.Banner.Position = UDim2.fromOffset(pad + math.floor(bannerW / 2), bannerY + math.floor(m.Banner / 2))
	refs.Next.Position = UDim2.new(1, -18, 0.5, 0)
	local contentH = bannerY + m.Banner + pad
	grid.CanvasSize = UDim2.fromOffset(0, if m.Compact then contentH else 0)
	-- (a new layout moves the pieces the opening animates: their rest is read again)
	for _, gui in { refs.Icon, refs.Title, refs.Sub, refs.Status, refs.Banner } :: { GuiObject } do
		gui:SetAttribute("BasePosition", nil)
	end
	local shadow = ShopFx.shadowOf(refs.Title)
	if shadow then
		shadow:SetAttribute("BasePosition", nil)
	end
	for _, card in refs.Cards do
		card.Holder:SetAttribute("BasePosition", nil)
	end
	-- the message near the bottom, over COMING SOON (the cards' names stay readable)
	refs.Message.Position = UDim2.fromOffset(math.floor(bodyW / 2), size.Y - 2 * rim - pad - math.floor(m.Banner / 2) - 4)
	refs.Message.Size = UDim2.fromOffset(math.min(bodyW - 60, 640), if m.Compact then 52 else 44)
	refs.MessageText.TextSize = if m.Compact then 20 else 18
end

---------------------------------------------------------------- filling in

--[[
	The status line: the blaster level and its bar, the coins. (A purchase
	counts the coins down instead: ElevatorWindow.countCoins.)
]]
function ElevatorWindow.setStatus(refs: Refs, level: any, coins: any)
	local blaster = if type(level) == "number" and level == level then math.floor(level) else 1
	local p = ElevatorWindow.progress(blaster)
	ShopFx.setText(refs.Level, `Lv. {blaster}`)
	refs.Fill.Size = UDim2.fromScale(math.max(p, 0.04), 1)
	ShopFx.setText(refs.Percent, `{math.floor(p * 100 + 0.5)}%`)
	ShopFx.setText(refs.ProgressHint, ElevatorWindow.progressHint(blaster))
	local money = if type(coins) == "number" and coins == coins then coins else 0
	refs.Coins = money
	ShopFx.setText(refs.CoinAmount, Format.short(math.floor(money)))
end

-- Fills every card in (ElevatorWindow.entries).
function ElevatorWindow.setFloors(refs: Refs, entries: { Entry })
	refs.Entries = entries
	for _, entry in entries do
		local card = refs.Cards[entry.Index]
		if card then
			ElevatorWindow.setCard(card, entry, refs.Metrics)
		end
	end
end

-- The control hint on the bottom edge ("" hides it).
function ElevatorWindow.setHint(refs: Refs, text: string)
	refs.Hint.Visible = text ~= ""
	refs.HintText.Text = text
	refs.Hint.Size = UDim2.fromOffset(ShopFx.textWidth(text, refs.HintText.TextSize) + 40, refs.HintText.TextSize + 16)
end

function ElevatorWindow.showMessage(refs: Refs, text: string, color: Color3)
	refs.MessageText.Text = text
	refs.MessageText.TextColor3 = color
	refs.Message.Visible = true
end

function ElevatorWindow.hideMessage(refs: Refs)
	refs.Message.Visible = false
end

-- The card of the button a gamepad starts on: a floor to travel to or buy, else this floor, else none.
function ElevatorWindow.firstButton(refs: Refs): TextButton?
	local here: TextButton? = nil
	for _, card in refs.Cards do
		local entry = card.Entry
		if entry then
			if entry.State == "Travel" or (entry.State == "Buy" and entry.Afford) then
				return card.Button
			elseif entry.State == "Here" then
				here = card.Button
			end
		end
	end
	return here
end

-- The card a button (or a card face) belongs to.
function ElevatorWindow.cardOf(refs: Refs, gui: Instance): Card?
	for _, card in refs.Cards do
		if gui == card.Button or gui == card.Face or gui:IsDescendantOf(card.Holder) then
			return card
		end
	end
	return nil
end

---------------------------------------------------------------- motion

-- (tests and previews) every tween goes to `maker` instead of TweenService (nil: TweenService).
local fakeTweens: ShopFx.TweenMaker? = nil
function ElevatorWindow.useTweens(maker: ShopFx.TweenMaker?)
	fakeTweens = maker
end

-- (previews) the few one-off timers go to `delayer` instead of task.delay (the video's own clock).
local fakeDelays: ((seconds: number, fn: () -> ()) -> ())? = nil
function ElevatorWindow.useDelays(delayer: ((seconds: number, fn: () -> ()) -> ())?)
	fakeDelays = delayer
end

local function later(seconds: number, fn: () -> ())
	local fake = fakeDelays
	if fake then
		fake(seconds, fn)
	else
		task.delay(seconds, fn)
	end
end

local function tween(instance: Instance, time: number, style: string, direction: string, goal: Props, delay: number?): any
	local fake = fakeTweens
	if fake then
		local made = fake(instance, time, style, direction, goal, 0, false, delay or 0)
		if made and made.Play then
			made:Play()
		end
		return made
	end
	local ok, made = pcall(function()
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(time, (Enum.EasingStyle :: any)[style], (Enum.EasingDirection :: any)[direction], 0, false, delay or 0)
		local t = TweenService:Create(instance, info, goal)
		t:Play()
		return t
	end)
	return if ok then made else nil
end

local function scaleOn(gui: Instance, name: string): UIScale
	local found = gui:FindFirstChild(name)
	if found and found:IsA("UIScale") then
		return found
	end
	return UIKit.new("UIScale", { Name = name, Scale = 1 }, gui)
end

-- Every card's and the banner's holder, in order (the pop-in).
local function holders(refs: Refs): { GuiObject }
	local list: { GuiObject } = {}
	for _, card in refs.Cards do
		table.insert(list, card.Holder)
	end
	table.insert(list, refs.Banner)
	return list
end

--[[
	Opens: the dim fades in, the window grows from 0.94, the header drops in
	(the icon, the title, its line, the status line; the X spins in), the
	cards and the banner pop in one after another. Quiet: all at rest.
]]
function ElevatorWindow.playOpen(refs: Refs)
	local pop = scaleOn(refs.Group, "OpenPop")
	refs.Veil.BackgroundTransparency = 1
	for _, card in refs.Cards do
		card.Fade.BackgroundTransparency = 1
	end
	refs.Picked = nil
	if ShopFx.quiet() then
		pop.Scale = 1
		refs.Dim.BackgroundTransparency = ElevatorWindow.DimTo
		ShopFx.popIn(holders(refs))
		return
	end
	pop.Scale = 0.94
	tween(pop, 0.22, "Quad", "Out", { Scale = 1 })
	refs.Dim.BackgroundTransparency = 1
	tween(refs.Dim, 0.2, "Quad", "Out", { BackgroundTransparency = ElevatorWindow.DimTo })
	local drops: { GuiObject } = { refs.Icon, refs.Title, refs.Sub, refs.Status }
	local shadow = ShopFx.shadowOf(refs.Title)
	if shadow then
		table.insert(drops, shadow)
	end
	ShopFx.cascade({ Drops = drops, Pops = {}, Spin = refs.CloseHolder })
	ShopFx.popIn(holders(refs))
end

-- Closes: a veil darkens it, it shrinks to 0.94, the dim fades; then `done`. Quiet: `done` at once.
function ElevatorWindow.playClose(refs: Refs, done: () -> ())
	local pop = scaleOn(refs.Group, "OpenPop")
	if ShopFx.quiet() then
		pop.Scale = 1
		done()
		return
	end
	tween(refs.Veil, 0.15, "Quad", "In", { BackgroundTransparency = 0.25 })
	tween(pop, 0.16, "Quad", "In", { Scale = 0.94 })
	tween(refs.Dim, 0.16, "Quad", "In", { BackgroundTransparency = 1 })
	later(0.17, done)
end

ElevatorWindow.Lift = 6 -- a hovered card rises this much
ElevatorWindow.Pan = 14 -- its picture pans this many picture pixels

--[[
	A card under the mouse or the gamepad's selection: it rises and grows a
	little, its light edge and its button brighten, its picture pans.
]]
function ElevatorWindow.hover(card: Card, on: boolean)
	ShopFx.hover(card.Holder, on, false, { Lift = ElevatorWindow.Lift, Light = card.Light })
	local quiet = ShopFx.quiet()
	local bright = if on and not quiet then 0.82 else 1
	if quiet then
		card.ButtonBright.BackgroundTransparency = bright
	else
		tween(card.ButtonBright, 0.14, "Quad", "Out", { BackgroundTransparency = bright })
	end
	local art = card.Art
	if art.Visible and art.ImageRectSize.X > 0 then
		local base = art:GetAttribute("BaseRect")
		if typeof(base) ~= "Vector2" then
			base = art.ImageRectOffset
			art:SetAttribute("BaseRect", base)
		end
		local goal = if on and not quiet then (base :: Vector2) + Vector2.new(ElevatorWindow.Pan, 0) else base :: Vector2
		if quiet then
			art.ImageRectOffset = goal
		else
			tween(art, 0.5, "Sine", "Out", { ImageRectOffset = goal })
		end
	end
end

--[[
	A locked card says no: it shakes left and right, its lock flashes big
	and its requirement lights up. Quiet: only the requirement lights up.
]]
function ElevatorWindow.shake(card: Card)
	local note = card.NoteText
	local rest = note.TextColor3
	note.TextColor3 = hex("#ffd84a")
	if ShopFx.quiet() then
		later(0.6, function()
			note.TextColor3 = rest
		end)
		return
	end
	tween(note, 0.6, "Quad", "In", { TextColor3 = rest }, 0.25)
	local base = card.Holder:GetAttribute("BasePosition")
	if typeof(base) ~= "UDim2" then
		base = card.Holder.Position
		card.Holder:SetAttribute("BasePosition", base)
	end
	local at = base :: UDim2
	local steps = { 9, -8, 6, -4, 0 }
	for i, dx in steps do
		tween(card.Holder, 0.06, "Quad", "Out", { Position = at + UDim2.fromOffset(dx, 0) }, (i - 1) * 0.06)
	end
	local pop = scaleOn(card.Lock, "Pop")
	pop.Scale = 1.35
	tween(pop, 0.35, "Back", "Out", { Scale = 1 })
end

-- A button that can't (not enough coins): it shakes, the NOT ENOUGH COINS line lights up.
function ElevatorWindow.refuse(card: Card)
	ElevatorWindow.shake(card)
end

--[[
	A floor was bought: a gold flash over its card, coins fly out of it, the
	status line's coin pops and the card turns to TRAVEL with a pop (the
	caller fills the new entry in first). Quiet: just the new state.
]]
function ElevatorWindow.unlock(refs: Refs, card: Card)
	if ShopFx.quiet() then
		return
	end
	card.Flash.BackgroundTransparency = 0.1
	tween(card.Flash, 0.6, "Quad", "Out", { BackgroundTransparency = 1 })
	local face = card.Face
	-- the card's middle on the layer over the window (design units: the body sits 6 in, the cards in the grid)
	local grid = refs.Grid
	local at = UDim2.fromOffset(
		6 + grid.Position.X.Offset + card.Holder.Position.X.Offset - math.floor(grid.CanvasPosition.X),
		6 + grid.Position.Y.Offset + card.Holder.Position.Y.Offset - math.floor(grid.CanvasPosition.Y)
	)
	ShopFx.celebrate(card.ButtonHolder, ShopFx.ButtonCorner, refs.Layer, at, "coin", card.Index)
	local pop = scaleOn(refs.CoinIcon, "Pop")
	pop.Scale = 1.4
	tween(pop, 0.45, "Back", "Out", { Scale = 1 })
	local wordsPop = scaleOn(face, "Unlock")
	wordsPop.Scale = 1.06
	tween(wordsPop, 0.4, "Back", "Out", { Scale = 1 })
end

--[[
	The coins count from what the status line shows to `coins` (a purchase:
	down), about half a second. Quiet: at once.
]]
function ElevatorWindow.countCoins(refs: Refs, coins: number)
	local from = refs.Coins
	refs.Coins = coins
	if ShopFx.quiet() or from == coins then
		ShopFx.setText(refs.CoinAmount, Format.short(math.floor(coins)))
		return
	end
	-- (on the amount: the previews read it while it counts)
	local old = refs.CoinAmount:FindFirstChild("CoinCount")
	if old then
		old:Destroy()
	end
	local value = Instance.new("NumberValue")
	value.Name = "CoinCount"
	value.Value = from
	value.Parent = refs.CoinAmount
	local ok = pcall(function()
		value.Changed:Connect(function(n: number)
			ShopFx.setText(refs.CoinAmount, Format.short(math.floor(n)))
		end)
	end)
	if not ok or not tween(value, 0.55, "Quad", "Out", { Value = coins }) then
		ShopFx.setText(refs.CoinAmount, Format.short(math.floor(coins)))
	end
	later(0.6, function()
		ShopFx.setText(refs.CoinAmount, Format.short(math.floor(refs.Coins)))
		value:Destroy()
	end)
end

--[[
	TRAVEL pressed: its card lights up and grows a little, every other card
	dims (until the ride starts, or unpick). Quiet: only the dimming.
]]
function ElevatorWindow.pick(refs: Refs, index: number)
	refs.Picked = index
	local quiet = ShopFx.quiet()
	for _, card in refs.Cards do
		local goal = if card.Index == index then 1 else 0.5
		if quiet then
			card.Fade.BackgroundTransparency = goal
		else
			tween(card.Fade, 0.18, "Quad", "Out", { BackgroundTransparency = goal })
		end
		if card.Index == index and not quiet then
			card.Flash.BackgroundTransparency = 0.6
			tween(card.Flash, 0.5, "Quad", "Out", { BackgroundTransparency = 1 })
			local grow = scaleOn(card.Face, "Unlock")
			grow.Scale = 1.04
			tween(grow, 0.3, "Back", "Out", { Scale = 1 })
		end
	end
end

-- Back from a pick (the ride was refused).
function ElevatorWindow.unpick(refs: Refs)
	refs.Picked = nil
	for _, card in refs.Cards do
		if ShopFx.quiet() then
			card.Fade.BackgroundTransparency = 1
		else
			tween(card.Fade, 0.18, "Quad", "Out", { BackgroundTransparency = 1 })
		end
	end
end

-- The window's loops (ShopFx marks under it: the shine, the halo, the glint, the "?", the clock).
function ElevatorWindow.loops(refs: Refs): { ShopFx.Loop }
	return ShopFx.loopsUnder({ refs.Root }, refs.Metrics.Compact)
end

return ElevatorWindow
