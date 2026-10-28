--[[
	The mine elevator on screen (pure builder + pure helpers; ElevatorController
	fills it in and animates it). Look: the bright "Pop" window kit (Pop.luau,
	like the Robux Shop; owner 2026-10-21: "new, modern, colourful, clean
	items, more Roblox style").

	  panel    a Pop window: a teal header band (the side menu's Elevator
	           colour, BubbleTheme Base) with shine stripes and studs, a small
	           elevator icon, "ELEVATOR" in white with a 3D shadow, the red
	           square X; a dark studded body; under the band a subtitle line
	           ("Your blaster: Lv 7. ..." with "Lv 7" in gold); a dark footer
	           pill with the control hint hanging on the bottom edge
	  Floors   (owned) a card per floor and Coming soon: 4 + 3 when the panel
	           is wide enough (PC), else 3 columns that scroll (phones: two
	           rows show, the last row is a swipe away). Each card is a bright
	           painted Pop card in its floor's colour with light rays and a
	           glow behind its themed art, a big number badge, the name, the
	           floor's ore rarity chips (Common .. Mythic, Pop.rarityPaint), a
	           mode line (walker "Walk or ride", crown "Elevator only", clock
	           "Next update") when there is room and the card's button: a big
	           green Pop "→ GO" / pin "YOU ARE HERE" (blue) / lock "LOCKED" /
	           clock "COMING SOON" (grey; the last card is MineFloors.ComingSoon).
	           A floor your blaster can't reach gets a dark LOCKED shade and its
	           requirement ("Blaster 9+", red) on the button's corner; the
	           current floor gets a gold outline and a soft gold halo.
	  Buy      (not owned) the pitch, the floor tiles 1-6 + "?" painted in
	           their colours, a dark studded well with the gold coin price and a
	           green Pop BUY (grey with a lock while you can't afford it)
	  doors    two steel door halves with a glowing seam over the panel: the
	           opening animation slides them apart (ElevatorView.pose)

	The floor art and the small icons are drawn from Frames (rotated squares
	for crystals, UIGradient, UIStroke, UICorner): images need uploads under
	the owner's account. When the owner uploads the header icon, set
	HeaderIconImage to its asset id and an ImageLabel is used instead. (The
	side menu's ELEVATOR button is main's SideMenuView entry "Elevator": its
	icon is the light HUD's "lift" sprite (HudBubble.EntryLooks); the owner's
	elevator_icon.webp belongs there.)

	Also here: the void rescue's fade (buildFade), and the Pop pieces the
	hoverboards window shares (ElevatorView.paintFrom / popWindow / fitWindow
	/ popFooter: the same chrome).

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). The compact layout (phones, uiScale 0.62) has 72-unit
	buttons (about 44 pt) and fits the panel into what the screen leaves.
	A gamepad selection stays inside the panel (SelectionGroup); only the
	buttons that do something are selectable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local OreData = require(Shared.Config.OreData)
local PopTheme = require(Shared.Config.PopTheme)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local ElevatorView = {}

export type Mode = "Buy" | "Floors"
export type FloorState = "Open" | "Locked" | "Here" | "Soon"
export type HintKind = "Mouse" | "Gamepad" | "Touch"

export type FloorEntry = {
	Index: number,
	Name: string,
	MinBlaster: number,
	Requirement: string, -- "Blaster 7+"
	Met: boolean, -- the blaster is enough
	State: FloorState,
	ElevatorOnly: boolean,
	Color: Color3, -- the floor's UI colour (card, badge)
	Rarities: { string }, -- the rarities of the floor's ores, Common first (none for Coming soon)
}

-- a Pop button (Pop.price's face: the drawn icons, the robux mark and the word in a row) in a holder
export type ButtonRefs = {
	Holder: Frame,
	Edge: UIStroke,
	Button: TextButton,
	Gradient: UIGradient,
	Row: GuiObject,
	Icons: { [string]: Frame },
	Label: TextLabel,
	LabelStroke: UIStroke,
	Style: string,
}

export type DropItem = { Frame: Frame, Scale: UIScale, Base: UDim2 }

export type Card = {
	Index: number,
	Frame: Frame, -- the holder (the layout places it; the drop-in scales it)
	Scale: UIScale,
	Face: TextButton, -- the painted Pop card (not selectable: its button is)
	Stroke: UIStroke, -- the card's black edge (gold on the current floor)
	Glow: Frame, -- the current floor's gold halo
	Canvas: Frame,
	CanvasScale: UIScale,
	Badge: Frame,
	BadgeGradient: UIGradient,
	Number: TextLabel,
	Name: TextLabel,
	Rarities: Frame, -- the ore rarity chips' row
	RarityChips: { Frame },
	Shade: Frame, -- the LOCKED shade
	Pill: Frame, -- the requirement ("Blaster 9+") on a locked card's button
	Chip: TextLabel, -- the pill's text
	ChipGradient: UIGradient,
	ChipStroke: UIStroke,
	ModeRow: Frame,
	ModeIcons: { [string]: Frame },
	ModeText: TextLabel,
	Button: TextButton,
	Look: ButtonRefs,
	Entry: FloorEntry,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame, -- holds the panel, the X and the footer (pops in)
	Pop: UIScale,
	Panel: Frame, -- the Pop window (black frame; clips the doors)
	Header: Frame, -- the teal band
	Body: Frame, -- the dark studded body
	Chrome: Chrome, -- the window's pieces (ElevatorView.fitWindow)
	Icon: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	Subtitle: Frame, -- a row of coloured parts
	SubtitleParts: { TextLabel },
	Message: TextLabel, -- the last server message (instead of the subtitle)
	Close: TextButton,
	CloseLook: ButtonRefs,
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
	BuyLook: ButtonRefs,
	Note: TextLabel,
	-- the Floors page (the cards ride a ScrollingFrame: it scrolls when they don't all fit)
	FloorPage: Frame,
	FloorScroll: ScrollingFrame,
	Columns: number, -- the cards per row of the last layout
	Cards: { Card },
	-- footer pill
	Footer: Frame,
	Hint: TextLabel,
	HintIcons: { [string]: GuiObject },
	HintGlyph: ImageLabel,
	-- opening doors
	Doors: Frame,
	DoorLeft: Frame,
	DoorRight: Frame,
	Seam: Frame,
	DropIns: { [string]: { DropItem } },
	Mode: Mode,
	Compact: boolean,
	CanAfford: boolean,
	MaxWidth: number, -- the room the last layout got (design units)
	MaxHeight: number,
	Level: number, -- the blaster level the cards were filled for
	PoseTime: number, -- where the opening animation stands (OpenTime = open)
	HintKind: HintKind,
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
	Pad: number,
	Band: number, -- the coloured header band
	Header: number, -- the band + the subtitle line: where the pages start
	Title: number,
	Icon: number,
	Text: number,
	Gap: number,
	Button: number,
	Badge: number,
	CardName: number,
	Chip: number,
	ChipText: number,
	ModeText: number,
	ModeIcon: number,
	Close: number,
	Pitch: number,
	Tile: number,
	Price: number,
	Footer: number,
	ButtonText: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NAVY_DEEP = rgb(10, 14, 32)
local NEON = rgb(70, 170, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local TEXT = rgb(255, 255, 255)
local TEXT_SOFT = rgb(222, 228, 244)
local GOLD = rgb(255, 204, 64)
local GOLD_TEXT = rgb(255, 214, 90)
local INK = rgb(10, 12, 26) -- outlines
local OUTLINE = PopTheme.Outline
local MET = rgb(56, 190, 70) -- the requirement pill: your blaster is enough
local UNMET = rgb(226, 58, 72) -- not yet

local METRICS: { [string]: Metrics } = {
	Normal = {
		BuyWidth = 720,
		FloorWidth = 1250, -- four cards a row on a 1280-wide screen
		FloorHeight = 540,
		Pad = 20,
		Band = 76,
		Header = 110,
		Title = 46,
		Icon = 52,
		Text = 20,
		Gap = 14,
		Button = 58,
		Badge = 60,
		CardName = 22,
		Chip = 26,
		ChipText = 15,
		ModeText = 17,
		ModeIcon = 20,
		Close = 62,
		Pitch = 22,
		Tile = 64,
		Price = 44,
		Footer = 36,
		ButtonText = 26,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		BuyWidth = 880,
		FloorWidth = 1060,
		FloorHeight = 520,
		Pad = 18,
		Band = 76,
		Header = 98,
		Title = 44,
		Icon = 50,
		Text = 21,
		Gap = 12,
		Button = 72,
		Badge = 58,
		CardName = 24,
		Chip = 28,
		ChipText = 16,
		ModeText = 18,
		ModeIcon = 22,
		Close = 64,
		Pitch = 24,
		Tile = 66,
		Price = 48,
		Footer = 0,
		ButtonText = 28,
	},
}

ElevatorView.Title = "ELEVATOR"
ElevatorView.Paint = "Teal" -- the header band (the side menu's Elevator colour)
ElevatorView.Pitch = "Ride to every floor you have unlocked. Buy once, keep forever."
-- asset ids for the owner's uploaded icons ("" = draw them from Frames)
ElevatorView.HeaderIconImage = "" -- the small icon left of the title
-- each floor's frame and badge colour (the mock): orange, red-orange, cyan, gold, electric
-- indigo (the Stormglass Rift), purple; grey = coming soon
ElevatorView.FloorColors = {
	rgb(255, 150, 40),
	rgb(255, 92, 46),
	rgb(40, 196, 255),
	rgb(255, 190, 40),
	rgb(98, 112, 255),
	rgb(176, 72, 236),
} :: { Color3 }
-- a card is at least this wide in a row of four (else three a row, scrolling)
ElevatorView.MinCardWidth = 260
-- the floor name shrinks to fit its card, never under this
ElevatorView.MinNameSize = 18
-- how much of the next row shows under the cards when they scroll (design units)
ElevatorView.ScrollPeek = 34
ElevatorView.SoonColor = rgb(118, 124, 146)
ElevatorView.LockedColor = rgb(52, 58, 78)
-- the opening animation (ElevatorView.pose): doors part, the panel pops, the cards drop in
ElevatorView.OpenTime = 0.56
ElevatorView.CloseTime = 0.24

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- measuring text

-- Glyph widths of FredokaOne and LuckiestGuy (1/100 em, ASCII 32..126), measured
-- from the fonts. In the game ElevatorController sets ElevatorView.Measure to
-- TextService, so these only matter for the tests and the preview.
local FREDOKA = {
	25,
	27,
	43,
	75,
	48,
	84,
	75,
	21,
	38,
	38,
	50,
	53,
	24,
	43,
	24,
	53,
	61,
	41,
	61,
	61,
	59,
	53,
	56,
	56,
	58,
	56,
	24,
	24,
	63,
	48,
	63,
	51,
	91,
	77,
	65,
	68,
	70,
	64,
	64,
	71,
	70,
	26,
	55,
	64,
	59,
	87,
	72,
	78,
	63,
	83,
	63,
	58,
	73,
	73,
	78,
	100,
	74,
	69,
	64,
	35,
	53,
	35,
	53,
	83,
	48,
	60,
	59,
	52,
	60,
	57,
	45,
	59,
	61,
	26,
	25,
	54,
	33,
	85,
	61,
	60,
	58,
	58,
	46,
	49,
	45,
	61,
	64,
	79,
	57,
	60,
	59,
	38,
	22,
	38,
	65,
}
local LUCKIEST = {
	20,
	28,
	48,
	61,
	44,
	72,
	63,
	23,
	39,
	38,
	54,
	46,
	22,
	38,
	22,
	50,
	63,
	39,
	51,
	53,
	54,
	53,
	57,
	51,
	57,
	56,
	25,
	25,
	46,
	39,
	46,
	55,
	66,
	63,
	59,
	51,
	58,
	48,
	49,
	63,
	63,
	30,
	51,
	61,
	45,
	79,
	70,
	64,
	60,
	69,
	61,
	53,
	54,
	62,
	61,
	91,
	59,
	61,
	49,
	37,
	51,
	37,
	49,
	30,
	28,
	63,
	59,
	51,
	58,
	58,
	49,
	63,
	63,
	29,
	51,
	60,
	45,
	90,
	65,
	64,
	60,
	69,
	61,
	53,
	54,
	61,
	61,
	91,
	59,
	61,
	50,
	41,
	29,
	40,
	58,
}

-- In the game: TextService (set by ElevatorController); nil = the tables above.
ElevatorView.Measure = nil :: ((text: string, size: number, title: boolean) -> number)?

-- Width of one line of `text` at `size` (FredokaOne, or LuckiestGuy when `title`).
function ElevatorView.measure(text: string, size: number, title: boolean?): number
	local custom = ElevatorView.Measure
	if custom then
		local ok, width = pcall(custom, text, size, title == true)
		if ok and type(width) == "number" and width == width then
			return width
		end
	end
	local widths = if title then LUCKIEST else FREDOKA
	local em = 0
	for _, code in utf8.codes(text) do
		em += if code >= 32 and code <= 126 then widths[code - 31] else 60
	end
	return em / 100 * size
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

function ElevatorView.floorColor(index: number): Color3
	return ElevatorView.FloorColors[index] or ElevatorView.SoonColor
end

-- the rarities in their order (OreData), for the cards' chips
ElevatorView.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- The rarities of a floor's ores (its rocks and its crystal rocks), Common first; {} for no such floor.
function ElevatorView.floorRarities(index: number): { string }
	local floor = MineFloors.ByIndex[index]
	local found: { [string]: boolean } = {}
	if floor then
		for _, weights in { floor.Ores, floor.CrystalOres } do
			for id in weights do
				if OreData.exists(id) then
					found[OreData.get(id).Rarity] = true
				end
			end
		end
	end
	local list: { string } = {}
	for _, rarity in ElevatorView.RarityOrder do
		if found[rarity] then
			table.insert(list, rarity)
		end
	end
	return list
end

--[[
	The cards: MineFloors.List in order, then the "Coming soon" floor.
	`level` = the player's blaster level, `here` = the floor of the stop the
	panel was opened at (nil = none of them).
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
			Color = ElevatorView.floorColor(floor.Index),
			Rarities = ElevatorView.floorRarities(floor.Index),
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
		Rarities = {},
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

-- The line under the title as coloured parts ("Lv 7" in yellow).
function ElevatorView.subtitleParts(mode: Mode, level: number): { { Text: string, Color: Color3 } }
	if mode == "Buy" then
		return { { Text = "Every mine floor, one ride away.", Color = TEXT } }
	end
	return {
		{ Text = "Your blaster: ", Color = TEXT },
		{ Text = `Lv {level}.`, Color = GOLD },
		{ Text = " Buy better blasters in the Vault to unlock deeper floors.", Color = TEXT },
	}
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

---------------------------------------------------------------- drawing kit

-- A frame centred at (cx, cy), w x h, all in scale of the parent; rotated `rot` degrees.
local function shape(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	w: number,
	h: number,
	color: Color3,
	rot: number?,
	round: number?
): Frame
	local frame: Frame = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx, cy),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rot or 0,
	}, parent)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, frame)
	end
	return frame
end

-- A frame at offset (x, y) (top-left), w x h, rotated `rot`; `corner` in offset.
local function block(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	rot: number?,
	corner: number?
): Frame
	local frame: Frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rot or 0,
	}, parent)
	if corner then
		UIKit.corner(frame, corner)
	end
	return frame
end

-- A top-to-bottom gradient with three colours (the frame's own colour should be white).
local function gradient3(parent: Instance, top: Color3, mid: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.5, mid),
			ColorSequenceKeypoint.new(1, bottom),
		}),
		Rotation = rotation or 90,
	}, parent)
end

local function ring(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	return UIKit.stroke(parent, thickness, color, transparency or 0)
end

-- An empty, square icon box (its parts are named "Ink").
local function iconBox(parent: Instance, name: string): Frame
	return UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
	}, parent)
end

local function ink(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, rot: number?, round: number?): Frame
	return shape(parent, "Ink", cx, cy, w, h, color, rot, round)
end

local Icons = {}

-- → (GO)
function Icons.arrow(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Arrow")
	ink(box, 0.42, 0.5, 0.64, 0.2, color, 0, 0.5)
	ink(box, 0.66, 0.34, 0.44, 0.2, color, 45, 0.5)
	ink(box, 0.66, 0.66, 0.44, 0.2, color, -45, 0.5)
	return box
end

-- a map pin (YOU ARE HERE)
function Icons.pin(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Pin")
	ink(box, 0.5, 0.6, 0.44, 0.44, color, 45, 0.12)
	ink(box, 0.5, 0.4, 0.66, 0.66, color, 0, 0.5)
	shape(box, "Hole", 0.5, 0.4, 0.26, 0.26, NAVY_DEEP, 0, 0.5)
	return box
end

-- a padlock (LOCKED)
function Icons.lock(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Lock")
	local shackle = shape(box, "Shackle", 0.5, 0.34, 0.5, 0.52, color, 0, 0.5)
	shackle.BackgroundTransparency = 1
	local s = ring(shackle, 2.5, color)
	s.Name = "InkRing"
	ink(box, 0.5, 0.68, 0.76, 0.5, color, 0, 0.16)
	shape(box, "Keyhole", 0.5, 0.66, 0.14, 0.18, INK, 0, 0.5)
	return box
end

-- a clock (COMING SOON, "Next update")
function Icons.clock(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Clock")
	local face = shape(box, "Face", 0.5, 0.5, 0.84, 0.84, color, 0, 0.5)
	face.BackgroundTransparency = 1
	local s = ring(face, 2.5, color)
	s.Name = "InkRing"
	ink(box, 0.5, 0.36, 0.11, 0.32, color, 0, 0.5)
	ink(box, 0.62, 0.52, 0.3, 0.11, color, 20, 0.5)
	return box
end

-- a walking figure ("Walk or ride")
function Icons.walker(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Walker")
	ink(box, 0.58, 0.14, 0.24, 0.24, color, 0, 0.5)
	ink(box, 0.52, 0.44, 0.17, 0.38, color, 14, 0.5)
	ink(box, 0.4, 0.78, 0.14, 0.4, color, 24, 0.5)
	ink(box, 0.64, 0.78, 0.14, 0.4, color, -26, 0.5)
	ink(box, 0.34, 0.44, 0.12, 0.32, color, 48, 0.5)
	ink(box, 0.7, 0.46, 0.12, 0.3, color, -36, 0.5)
	return box
end

-- a crown ("Elevator only")
function Icons.crown(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Crown")
	ink(box, 0.2, 0.42, 0.26, 0.26, color, 45, 0.1)
	ink(box, 0.5, 0.3, 0.28, 0.28, color, 45, 0.1)
	ink(box, 0.8, 0.42, 0.26, 0.26, color, 45, 0.1)
	ink(box, 0.5, 0.62, 0.8, 0.34, color, 0, 0.1)
	ink(box, 0.5, 0.86, 0.86, 0.14, color, 0, 0.3)
	shape(box, "Jewel", 0.5, 0.62, 0.16, 0.16, rgb(255, 90, 90), 45)
	return box
end

-- a computer mouse (footer hint)
function Icons.mouse(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Mouse")
	local body = ink(box, 0.5, 0.52, 0.62, 0.92, color, 0, 0.45)
	ring(body, 1.5, INK)
	shape(box, "Wheel", 0.5, 0.3, 0.1, 0.24, NAVY_DEEP, 0, 0.5)
	shape(box, "Split", 0.5, 0.42, 0.62, 0.05, rgb(150, 160, 190))
	return box
end

-- a tap (footer hint on touch screens)
function Icons.tap(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Tap")
	local outer = shape(box, "Wave", 0.5, 0.5, 0.92, 0.92, color, 0, 0.5)
	outer.BackgroundTransparency = 1
	local s = ring(outer, 2, color)
	s.Name = "InkRing"
	ink(box, 0.5, 0.5, 0.44, 0.44, color, 0, 0.5)
	return box
end

-- "^" made of two bars (the side button's chevrons)
local function chevron(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3): Frame
	local box: Frame = UIKit.new("Frame", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx, cy),
		Size = UDim2.fromScale(w, h),
		BackgroundTransparency = 1,
	}, parent)
	-- two bars meeting at the top centre (the box is about 10 : 7)
	-- no outlines: the two bars read as one clean arrow
	shape(box, "Ink", 0.34, 0.58, 0.66, 0.4, color, -42, 0.12)
	shape(box, "Ink", 0.66, 0.58, 0.66, 0.4, color, 42, 0.12)
	return box
end

-- The small elevator icon of the header (doors with ↑↓ on top), or the owner's image.
local function headerIcon(parent: Instance): Frame
	local box = iconBox(parent, "ElevatorIcon")
	if ElevatorView.HeaderIconImage ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = ElevatorView.HeaderIconImage,
			ScaleType = Enum.ScaleType.Fit,
		}, box)
		return box
	end
	local body = shape(box, "Body", 0.5, 0.56, 0.78, 0.84, WHITE, 0, 0.14)
	gradient3(body, rgb(250, 252, 255), rgb(206, 226, 255), rgb(150, 186, 246))
	ring(body, 3, INK)
	local doorL = shape(body, "DoorL", 0.29, 0.6, 0.36, 0.66, WHITE, 0, 0.1)
	gradient3(doorL, rgb(120, 180, 255), rgb(70, 130, 240), rgb(44, 92, 210))
	local doorR = shape(body, "DoorR", 0.71, 0.6, 0.36, 0.66, WHITE, 0, 0.1)
	gradient3(doorR, rgb(120, 180, 255), rgb(70, 130, 240), rgb(44, 92, 210))
	shape(body, "Seam", 0.5, 0.6, 0.05, 0.66, INK)
	-- ↑ ↓ above the doors
	local up = chevron(body, 0.36, 0.14, 0.24, 0.16, NAVY_DEEP)
	up.Name = "Up"
	local down = chevron(body, 0.64, 0.14, 0.24, 0.16, NAVY_DEEP)
	down.Name = "Down"
	down.Rotation = 180
	return box
end

-- A tall crystal (body + pointed tip) standing on (x, y) in a canvas, leaning `rot` degrees.
local function crystal(parent: Instance, x: number, y: number, w: number, h: number, rot: number, color: Color3, light: Color3): Frame
	local tip = w / 2
	local holder: Frame = UIKit.new("Frame", {
		Name = "Crystal",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h + tip),
		BackgroundTransparency = 1,
		Rotation = rot,
	}, parent)
	local side = w / math.sqrt(2)
	local point = block(holder, "Tip", (w - side) / 2, tip - side / 2, side, side, color, 45)
	UIKit.new("UIGradient", { Color = ColorSequence.new(light, color), Rotation = 0 }, point)
	local body = block(holder, "Body", 0, tip, w, h, WHITE)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, light),
			ColorSequenceKeypoint.new(0.45, light:Lerp(color, 0.5)),
			ColorSequenceKeypoint.new(0.5, color),
			ColorSequenceKeypoint.new(1, color:Lerp(BLACK, 0.25)),
		}),
		Rotation = 0,
	}, body)
	return holder
end

local function glowDot(parent: Instance, x: number, y: number, size: number, color: Color3, transparency: number): Frame
	local dot = block(parent, "Glow", x - size / 2, y - size / 2, size, size, color)
	dot.BackgroundTransparency = transparency
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	return dot
end

local function column(parent: Instance, x: number, top: number, h: number, light: Color3, dark: Color3)
	local shaft = block(parent, "Shaft", x, top, 16, h, WHITE)
	UIKit.new("UIGradient", { Color = ColorSequence.new(light, dark), Rotation = 0 }, shaft)
	block(parent, "Groove", x + 7, top + 2, 2, h - 4, dark)
	block(parent, "Capital", x - 4, top - 7, 24, 8, light, 0, 2)
	block(parent, "Base", x - 4, top + h - 1, 24, 8, light, 0, 2)
end

-- A soft rounded silhouette behind the art (cave mouth, arch, rock band).
local function backdrop(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transparency: number?)
	local back = block(parent, "Back", x, y, w, h, color)
	back.BackgroundTransparency = transparency or 0
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.45, 0) }, back)
end

-- Art on a card's right half (a 170 x 120 canvas; x grows right, y down).
local ART: { (Frame) -> () } = {
	-- 1 Greystone Quarry: stone blocks under a timber frame with a lantern
	function(c: Frame)
		backdrop(c, 56, 4, 118, 50, rgb(150, 150, 166), 0.55)
		backdrop(c, 70, 30, 104, 40, rgb(126, 128, 144), 0.4)
		local beam = rgb(120, 82, 52)
		block(c, "PostL", 84, 18, 8, 82, beam)
		block(c, "PostR", 150, 18, 8, 82, beam)
		block(c, "Beam", 78, 12, 86, 9, beam:Lerp(WHITE, 0.1), 0, 2)
		glowDot(c, 122, 48, 44, rgb(255, 170, 60), 0.78)
		block(c, "Cord", 121, 21, 2, 12, rgb(40, 32, 26))
		block(c, "Lantern", 113, 32, 18, 24, rgb(58, 44, 34), 0, 4)
		block(c, "Flame", 117, 37, 10, 14, rgb(255, 196, 80), 0, 3)
		local stones = { { 60, 84, 46, 30 }, { 100, 74, 40, 40 }, { 136, 88, 34, 26 }, { 76, 64, 30, 22 } }
		for _, s in stones do
			local stone = block(c, "Stone", s[1], s[2], s[3], s[4], WHITE, 0, 5)
			gradient3(stone, rgb(176, 182, 196), rgb(128, 134, 150), rgb(86, 90, 106))
			ring(stone, 1.5, INK, 0.3)
		end
	end,
	-- 2 Ember Caves: lava and orange crystals
	function(c: Frame)
		backdrop(c, 64, 10, 110, 96, rgb(60, 18, 18), 0.15)
		backdrop(c, 84, 26, 80, 74, rgb(200, 70, 30), 0.55)
		block(c, "Drip", 92, 8, 9, 9, rgb(60, 18, 18), 45)
		block(c, "Drip", 140, 10, 7, 7, rgb(60, 18, 18), 45)
		local lava = block(c, "Lava", 40, 100, 130, 18, WHITE, 0, 6)
		UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(255, 196, 70), rgb(255, 84, 30)), Rotation = 0 }, lava)
		glowDot(c, 130, 70, 80, rgb(255, 110, 40), 0.8)
		block(c, "Rock", 52, 70, 34, 34, rgb(70, 32, 30), 0, 8)
		block(c, "Rock", 150, 60, 22, 44, rgb(62, 28, 28), 0, 6)
		local orange, light = rgb(255, 120, 30), rgb(255, 214, 120)
		crystal(c, 98, 104, 14, 22, -22, orange, light)
		crystal(c, 118, 104, 18, 40, -8, orange, light)
		crystal(c, 138, 104, 22, 52, 6, orange, light)
		crystal(c, 156, 104, 14, 28, 22, orange, light)
	end,
	-- 3 Deep Hollow: cyan crystals over glowing water
	function(c: Frame)
		backdrop(c, 64, 8, 110, 98, rgb(10, 40, 70), 0.1)
		backdrop(c, 86, 24, 80, 76, rgb(40, 170, 230), 0.6)
		local water = block(c, "Water", 40, 102, 130, 16, WHITE, 0, 6)
		UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(40, 140, 200), rgb(90, 230, 255)), Rotation = 0 }, water)
		glowDot(c, 128, 66, 86, rgb(60, 200, 255), 0.78)
		local cyan, light = rgb(40, 190, 255), rgb(200, 248, 255)
		crystal(c, 96, 104, 14, 26, -24, cyan, light)
		crystal(c, 116, 104, 18, 44, -10, cyan, light)
		crystal(c, 138, 104, 24, 58, 4, cyan, light)
		crystal(c, 158, 104, 14, 30, 20, cyan, light)
	end,
	-- 4 Sunken Palace: marble columns over flooded tiles
	function(c: Frame)
		backdrop(c, 72, 4, 46, 100, rgb(24, 36, 92), 0.2)
		backdrop(c, 120, 0, 50, 104, rgb(24, 36, 92), 0.2)
		local floor = block(c, "Tiles", 50, 104, 120, 14, WHITE, 0, 4)
		UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(50, 70, 140), rgb(80, 200, 255)), Rotation = 0 }, floor)
		glowDot(c, 128, 60, 80, rgb(90, 140, 255), 0.82)
		local light, dark = rgb(196, 204, 236), rgb(110, 120, 170)
		column(c, 86, 30, 72, light, dark)
		column(c, 122, 44, 58, light, dark)
		column(c, 154, 22, 80, light, dark)
	end,
	-- 5 Stormglass Rift: a thundercloud with a glowing belly, a bolt striking yellow storm crystals
	function(c: Frame)
		backdrop(c, 62, 6, 112, 102, rgb(18, 22, 64), 0.1)
		glowDot(c, 124, 80, 84, rgb(255, 214, 80), 0.8)
		-- frozen rain behind the cloud
		for i, x in { 80, 96, 150, 162 } do
			local streak = block(c, "Rain", x, 40 + (i % 2) * 6, 2, 26, rgb(176, 200, 255), 8)
			streak.BackgroundTransparency = 0.45
		end
		-- the cloud: stepped puffs, darker below, a glowing underside
		block(c, "Cloud", 74, 16, 92, 22, rgb(70, 78, 130), 0, 10)
		block(c, "Cloud", 84, 4, 44, 26, rgb(98, 106, 160), 0, 12)
		block(c, "Cloud", 118, 8, 40, 22, rgb(88, 96, 150), 0, 11)
		block(c, "Belly", 80, 34, 80, 5, rgb(255, 214, 110), 0, 2)
		-- the bolt: three zig-zag strokes from the cloud down to the crystals
		local bolt, core = rgb(255, 236, 120), rgb(255, 252, 226)
		block(c, "Bolt", 116, 36, 6, 24, bolt, 24, 1)
		block(c, "Bolt", 106, 56, 18, 6, bolt, -24, 1)
		block(c, "Bolt", 112, 60, 6, 24, bolt, 24, 1)
		block(c, "BoltCore", 117, 39, 2, 18, core, 24)
		glowDot(c, 112, 84, 14, core, 0.2)
		-- rock and the yellow storm crystals
		block(c, "Rock", 84, 94, 70, 16, rgb(52, 60, 100), 0, 6)
		local yellow, light = rgb(255, 214, 60), rgb(255, 250, 210)
		crystal(c, 96, 104, 12, 22, -22, rgb(84, 98, 184), rgb(150, 162, 236))
		crystal(c, 114, 104, 16, 30, -6, yellow, light)
		crystal(c, 134, 104, 20, 40, 6, yellow, light)
		crystal(c, 154, 104, 12, 24, 22, rgb(84, 98, 184), rgb(150, 162, 236))
	end,
	-- 6 Heartstone Core: the pink heart crystal on its pedestal
	function(c: Frame)
		backdrop(c, 66, 6, 108, 100, rgb(40, 14, 64), 0.1)
		block(c, "Float", 74, 22, 18, 12, rgb(70, 40, 100), 12, 3)
		block(c, "Float", 154, 14, 14, 10, rgb(70, 40, 100), -15, 3)
		glowDot(c, 128, 54, 90, rgb(255, 80, 200), 0.72)
		block(c, "Pedestal", 104, 92, 48, 12, rgb(70, 44, 96), 0, 3)
		block(c, "Foot", 112, 102, 32, 14, rgb(54, 34, 76), 0, 3)
		local pink, light = rgb(240, 60, 200), rgb(255, 196, 246)
		-- the lower point first (under the body)
		local side = 30 / math.sqrt(2)
		block(c, "Low", 128 - side / 2, 74 - side / 2, side, side, pink:Lerp(BLACK, 0.2), 45)
		local heart = crystal(c, 128, 74, 30, 34, 0, pink, light)
		heart.Name = "Heart"
		crystal(c, 96, 104, 10, 18, -18, rgb(170, 80, 240), rgb(230, 190, 255))
		crystal(c, 160, 104, 10, 22, 16, rgb(170, 80, 240), rgb(230, 190, 255))
	end,
	-- 7 Coming soon: dim pillars and a big "?"
	function(c: Frame)
		local grey = rgb(84, 90, 110)
		column(c, 82, 34, 68, grey:Lerp(WHITE, 0.15), grey:Lerp(BLACK, 0.2))
		column(c, 150, 26, 76, grey:Lerp(WHITE, 0.15), grey:Lerp(BLACK, 0.2))
		local mark = UIKit.label(c, "?", 64, {
			Name = "Mark",
			Position = UDim2.fromOffset(100, 20),
			Size = UDim2.fromOffset(46, 80),
			FontFace = Theme.TitleFont,
			TextColor3 = rgb(150, 158, 184),
			TextTransparency = 0.25,
		})
		local stroke = mark:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = INK
			stroke.Transparency = 0.4
		end
	end,
}

---------------------------------------------------------------- Pop pieces (the hoverboards window uses them too)

-- A Pop paint from one colour: a lighter top, a deeper bottom (a floor's card, a board's card).
function ElevatorView.paintFrom(color: Color3, light: number?, deep: number?): Pop.Paint
	return {
		Top = color:Lerp(WHITE, light or 0.1),
		Bottom = color:Lerp(BLACK, deep or 0.35),
		Edge = OUTLINE,
	}
end

-- A small round label's gradient with `color` at its glossy step (the requirement pill).
local function paintChip(g: UIGradient, color: Color3)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.3)),
		ColorSequenceKeypoint.new(0.48, color),
		ColorSequenceKeypoint.new(0.52, color:Lerp(BLACK, 0.12)),
		ColorSequenceKeypoint.new(1, color:Lerp(BLACK, 0.28)),
	})
end

export type Chrome = {
	Panel: Frame,
	Header: Frame,
	Body: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	CloseLook: ButtonRefs,
}

--[[
	A Pop window filling `root` (Pop.window: a black frame, the band in
	`paint` with shine stripes and studs, the white title with its 3D shadow,
	a dark studded body). The window clips (the elevator's doors stay inside);
	its red X (Pop.close) sits in a holder on `root` (a controller hangs the
	gamepad's B glyph on the holder). fitWindow sizes it for a band height.
]]
function ElevatorView.popWindow(root: Frame, title: string, paint: string, band: number): Chrome
	local window = Pop.window(root, title, Vector2.new(800, 500), band, paint)
	if window.Icon then
		window.Icon:Destroy() -- (the round look's band icon: this window brings its own, fitWindow)
	end
	local panel = window.Root
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.ClipsDescendants = true
	local holder: Frame = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, root)
	local close = window.Close
	close.AnchorPoint = Vector2.zero
	close.Position = UDim2.new()
	close.Size = UDim2.fromScale(1, 1)
	close.ZIndex = 2 -- (under a controller's glyph on the holder)
	close.Parent = holder
	local label = close:FindFirstChild("Label") :: TextLabel
	local look: ButtonRefs = {
		Holder = holder,
		Edge = close:FindFirstChild("Border") :: UIStroke,
		Button = close,
		Gradient = close:FindFirstChild("Paint") :: UIGradient,
		Row = close,
		Icons = {},
		Label = label,
		LabelStroke = label:FindFirstChild("Edge") :: UIStroke,
		Style = "Close",
	}
	return {
		Panel = panel,
		Header = window.Header,
		Body = window.Body,
		Title = window.Title,
		TitleShadow = window.Header:FindFirstChild("TitleShadow") :: TextLabel,
		CloseLook = look,
	}
end

-- Sizes a popWindow for a `band` tall header: the icon and the title in the band, the X on its right.
function ElevatorView.fitWindow(chrome: Chrome, icon: GuiObject, band: number, titleSize: number, iconSize: number, closeSize: number)
	chrome.Header.Size = UDim2.new(1, -8, 0, band - 8)
	chrome.Body.Position = UDim2.fromOffset(4, band)
	chrome.Body.Size = UDim2.new(1, -8, 1, -(band + 4))
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local left = 12 + iconSize + 12
	local title, shadow = chrome.Title, chrome.TitleShadow
	title.TextSize = titleSize
	title.Position = UDim2.new(0, left, 0.5, 0)
	title.Size = UDim2.new(1, -(left + closeSize + 24), 1, -4)
	local edge = title:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(titleSize)
	end
	shadow.TextSize = titleSize
	shadow.Position = title.Position + UDim2.fromOffset(0, 4)
	shadow.Size = title.Size
	local close = chrome.CloseLook
	close.Holder.Size = UDim2.fromOffset(closeSize, closeSize)
	close.Holder.Position = UDim2.new(1, -10, 0, math.floor(band / 2))
	close.Label.TextSize = math.floor(closeSize * 0.66)
	close.LabelStroke.Thickness = Pop.edgeFor(close.Label.TextSize)
end

-- The dark footer pill hanging on the panel's bottom edge; returns it and its row (icons + the hint).
function ElevatorView.popFooter(root: Frame): (Frame, Frame)
	local footer: Frame = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(380, 36),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, footer)
	Pop.border(footer, 3)
	local row: Frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, footer)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	return footer, row
end

--[[
	A Pop button in a holder: Pop.price's face (green, studs, the light rim;
	its Row holds the robux "Mark" and the word "Amount") with the drawn icons
	`iconNames` (from `makers`, in white) in front of the word. paintButton
	repaints it per state.
]]
function ElevatorView.popButton(
	parent: Instance,
	name: string,
	iconNames: { string },
	makers: { [string]: (Instance, Color3) -> Frame }
): ButtonRefs
	local holder: Frame = UIKit.new("Frame", {
		Name = name .. "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(160, 56),
	}, parent)
	local button = Pop.price(holder, nil, Vector2.new(160, 56), {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, "")
	local row = button:FindFirstChild("Row") :: Frame
	local list = row:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, 8)
	end
	local made: { [string]: Frame } = {}
	for _, kind in iconNames do
		local icon = makers[kind](row, WHITE)
		icon.LayoutOrder = 0
		icon.Visible = false
		made[kind] = icon
	end
	local label = row:FindFirstChild("Amount") :: TextLabel
	return {
		Holder = holder,
		Edge = button:FindFirstChild("Border") :: UIStroke,
		Button = button,
		Gradient = button:FindFirstChild("Paint") :: UIGradient,
		Row = row,
		Icons = made,
		Label = label,
		LabelStroke = label:FindFirstChild("Edge") :: UIStroke,
		Style = "",
	}
end

-- Paints a popButton: `paint`, the word (`heavy`: the LuckiestGuy font) and the drawn icon `icon` (nil: none).
function ElevatorView.paintButton(look: ButtonRefs, paint: Pop.Paint, text: string, textSize: number, icon: string?, heavy: boolean?)
	Pop.repaint(look.Button, paint)
	look.Label.Text = text
	look.Label.TextSize = textSize
	look.Label.FontFace = if heavy then PopTheme.Heavy else PopTheme.Font
	look.Label.TextColor3 = TEXT
	look.LabelStroke.Thickness = Pop.edgeFor(textSize)
	look.Label.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(text, textSize, heavy)) + 6, textSize + 8)
	local iconSize = math.floor(textSize * 0.95)
	for kind, frame in look.Icons do
		local shown = kind == icon
		frame.Visible = shown
		if shown then
			frame.Size = UDim2.fromOffset(iconSize, iconSize)
		end
	end
end

---------------------------------------------------------------- buttons

type ButtonStyle = {
	Paint: Pop.Paint,
	Mid: Color3, -- the face gradient's second key (Pop.face: the deep end before the lip)
	Icon: string?,
}

local function buttonStyle(paint: Pop.Paint, icon: string?): ButtonStyle
	-- (Mid: the face gradient's second key; the pixel kit's face runs Top -> Bottom, then the lip)
	return { Paint = paint, Mid = paint.Bottom, Icon = icon }
end

local BUTTON_STYLES: { [string]: ButtonStyle } = {
	Go = buttonStyle(PopTheme.Price, "Arrow"), -- the big green Pop button
	Here = buttonStyle(Pop.paint("Blue"), "Pin"),
	Locked = buttonStyle(PopTheme.Gray, "Lock"),
	Soon = buttonStyle(PopTheme.Gray, "Clock"),
	Buy = buttonStyle(PopTheme.Price, nil),
	BuyLocked = buttonStyle(PopTheme.Gray, "Lock"),
	Close = buttonStyle(PopTheme.Close, nil),
}
ElevatorView.ButtonStyles = BUTTON_STYLES

local ICON_MAKERS: { [string]: (Instance, Color3) -> Frame } = {
	Arrow = Icons.arrow,
	Pin = Icons.pin,
	Lock = Icons.lock,
	Clock = Icons.clock,
}

-- Paints a button in a style with a text.
local function styleButton(look: ButtonRefs, styleName: string, text: string, textSize: number, heavy: boolean?)
	local style = BUTTON_STYLES[styleName]
	look.Style = styleName
	ElevatorView.paintButton(look, style.Paint, text, textSize, style.Icon, heavy)
end

---------------------------------------------------------------- building

-- the size a card is built at (the layout resizes it; Pop.card sizes its rays and glow from it)
local CARD_BUILD = Vector2.new(290, 186)
-- Pop.card's light burst (rays and glow): it follows the card's art
local CARD_FX = { "Rays", "Glow", "Glow1", "Glow2" }

-- The number badge's paint: a deeper tile of the floor's colour.
local function badgePaint(color: Color3): Pop.Paint
	return ElevatorView.paintFrom(color, 0.12, 0.5)
end

-- The requirement pill (a round label with a black edge); it hangs on a locked card's button.
local function newPill(parent: Instance): (Frame, TextLabel, UIGradient, UIStroke)
	local pill: Frame = UIKit.new("Frame", {
		Name = "Requirement",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
	}, parent)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	local g = UIKit.new("UIGradient", { Name = "Paint", Rotation = 90 }, pill)
	local edge = Pop.border(pill, 3)
	local label = Pop.text(pill, "", 16, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	return pill, label, g, edge
end

local function newCard(page: GuiObject, entry: FloorEntry): Card
	local frame: Frame = UIKit.new("Frame", {
		Name = "Floor" .. entry.Index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
	}, page)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
	-- the current floor's soft gold halo (outside the card's own gold edge)
	local glow: Frame = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		Visible = false,
		ZIndex = 1,
	}, frame)
	UIKit.corner(glow, PopTheme.Corner + 4)
	ring(glow, 6, GOLD, 0.45)
	-- the painted card: the floor's colour, light rays and a glow behind its art, studs, the light rim
	local face = Pop.card(frame, ElevatorView.paintFrom(entry.Color), {
		Name = "Face",
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
		Selectable = false,
		ZIndex = 2,
	}, UDim2.fromScale(0.72, 0.42))
	face.Size = UDim2.fromScale(1, 1)
	local stroke = face:FindFirstChild("Border") :: UIStroke
	-- the floor's themed art
	local canvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(170, 120),
		ZIndex = 4,
	}, face)
	local canvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, canvas)
	local draw = ART[entry.Index] or ART[#ART]
	draw(canvas)
	-- the LOCKED shade: over the paint and the art, under the words
	local shade: Frame = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = OUTLINE,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
	}, face)
	UIKit.corner(shade, PopTheme.Corner)
	-- the round look's big gold padlock over a floor you can't ride to yet (the reel's Teleport)
	if PopTheme.round() then
		local padlock = Icons.lock(face, GOLD)
		padlock.Name = "Padlock"
		padlock.AnchorPoint = Vector2.new(0.5, 0.5)
		padlock.Position = UDim2.fromScale(0.5, 0.42)
		padlock.Size = UDim2.fromOffset(64, 64)
		padlock.Visible = false
		padlock.ZIndex = 6
		for _, d in padlock:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 6
			end
		end
	end
	-- the number badge, the name
	local badge: Frame = UIKit.new("Frame", {
		Name = "Badge",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(60, 60),
		ZIndex = 6,
	}, face)
	local badgeGradient = Pop.face(badge, badgePaint(entry.Color), 10)
	local number = Pop.text(badge, "", 40, {
		Name = "Number",
		FontFace = PopTheme.Heavy,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	})
	local name = Pop.text(face, "", 22, {
		Name = "FloorName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
	})
	-- the ore rarity chips (what you find down there)
	local rarities: Frame = UIKit.new("Frame", {
		Name = "Rarities",
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, face)
	UIKit.list(rarities, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local chips: { Frame } = {}
	for i = 1, #ElevatorView.RarityOrder do
		local chip = Pop.chip(rarities, "", "Slate", Vector2.new(80, 26), { LayoutOrder = i, Visible = false })
		chip.Name = "Rarity" .. i
		table.insert(chips, chip)
	end
	-- the mode line
	local modeRow: Frame = UIKit.new("Frame", {
		Name = "Mode",
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, face)
	UIKit.list(modeRow, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local modeIcons: { [string]: Frame } = {
		Walk = Icons.walker(modeRow, WHITE),
		Crown = Icons.crown(modeRow, GOLD),
		Clock = Icons.clock(modeRow, TEXT_SOFT),
	}
	for _, icon in modeIcons do
		icon.LayoutOrder = 1
	end
	local modeText = Pop.text(modeRow, "", 17, {
		Name = "Text",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- the button (over the card, not clipped by it) and the requirement pill on its corner
	local look = ElevatorView.popButton(frame, "Go", { "Arrow", "Pin", "Lock", "Clock" }, ICON_MAKERS)
	look.Holder.ZIndex = 3
	local pill, chip, chipGradient, chipStroke = newPill(frame)
	return {
		Index = entry.Index,
		Frame = frame,
		Scale = scale,
		Face = face,
		Stroke = stroke,
		Glow = glow,
		Canvas = canvas,
		CanvasScale = canvasScale,
		Badge = badge,
		BadgeGradient = badgeGradient,
		Number = number,
		Name = name,
		Rarities = rarities,
		RarityChips = chips,
		Shade = shade,
		Pill = pill,
		Chip = chip,
		ChipGradient = chipGradient,
		ChipStroke = chipStroke,
		ModeRow = modeRow,
		ModeIcons = modeIcons,
		ModeText = modeText,
		Button = look.Button,
		Look = look,
		Entry = entry,
	}
end

-- A floor tile of the Buy page (a painted square with the number), in a slot so it can pop.
local function newTile(strip: Frame, index: number, color: Color3, text: string, crown: boolean): Frame
	local slot: Frame = UIKit.new("Frame", {
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		LayoutOrder = index,
	}, strip)
	local tile: Frame = UIKit.new("Frame", {
		Name = "Tile",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, slot)
	Pop.face(tile, ElevatorView.paintFrom(color), 10)
	Pop.studs(tile, 10, 0.5, 30, 2)
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, tile)
	local number = Pop.text(tile, text, 34, {
		Name = "Number",
		FontFace = PopTheme.Heavy,
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		ZIndex = 3,
	})
	Pop.limit(number, 40)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0.16, 0),
		PaddingBottom = UDim.new(0.12, 0),
	}, number)
	if crown then
		local icon = Icons.crown(tile, GOLD)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.92, 0.06)
		icon.Size = UDim2.fromScale(0.42, 0.42)
		icon.Rotation = 18
		icon.ZIndex = 4
	end
	return slot
end

local function newFooter(root: Frame): (Frame, TextLabel, { [string]: GuiObject }, ImageLabel)
	local footer, row = ElevatorView.popFooter(root)
	local mouse = Icons.mouse(row, TEXT)
	mouse.Size = UDim2.fromOffset(16, 22)
	mouse.LayoutOrder = 1
	local tap = Icons.tap(row, TEXT)
	tap.Size = UDim2.fromOffset(18, 18)
	tap.LayoutOrder = 1
	tap.Visible = false
	local glyph: ImageLabel = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(26, 26),
		LayoutOrder = 1,
		Visible = false,
	}, row)
	local hint = Pop.text(row, "", 17, {
		Name = "Hint",
		LayoutOrder = 2,
	})
	return footer, hint, { Mouse = mouse, Touch = tap }, glyph
end

local function newDoors(panel: Frame): (Frame, Frame, Frame, Frame)
	local doors: Frame = UIKit.new("Frame", {
		Name = "Doors",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Visible = false,
	}, panel)
	local function half(name: string, anchorX: number): Frame
		local door: Frame = UIKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(anchorX, 0),
			Size = UDim2.new(0.5, 14, 1, 0),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, doors)
		UIKit.corner(door, PopTheme.WindowCorner)
		UIKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(108, 122, 156)),
				ColorSequenceKeypoint.new(0.5, rgb(72, 82, 110)),
				ColorSequenceKeypoint.new(1, rgb(46, 52, 74)),
			}),
			Rotation = 90,
		}, door)
		Pop.studs(door, PopTheme.WindowCorner, 0.55, 36, 1)
		for i = 1, 4 do
			shape(door, "Groove", 0.5, i * 0.2, 0.74, 0.012, rgb(28, 32, 48))
		end
		-- the glowing inner edge
		local inner = if anchorX == 0 then 1 else 0
		local edge = shape(door, "Edge", inner, 0.5, 0, 1, NEON_BRIGHT)
		edge.AnchorPoint = Vector2.new(inner, 0.5)
		edge.Size = UDim2.new(0, 6, 1, 0)
		local soft = shape(door, "EdgeGlow", inner, 0.5, 0, 1, NEON)
		soft.AnchorPoint = Vector2.new(inner, 0.5)
		soft.Size = UDim2.new(0, 18, 1, 0)
		soft.BackgroundTransparency = 0.6
		return door
	end
	local left = half("DoorLeft", 0)
	local right = half("DoorRight", 1)
	-- the seam glow where the doors meet (fades as they part)
	local seam = shape(doors, "Seam", 0.5, 0.5, 0, 1, NEON_BRIGHT)
	seam.Size = UDim2.new(0, 10, 1, 0)
	seam.ZIndex = 2
	return doors, left, right, seam
end

function ElevatorView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeElevator", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local root: Frame = UIKit.new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.FloorWidth, METRICS.Normal.FloorHeight),
		BackgroundTransparency = 1,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local pop: UIScale = UIKit.new("UIScale", { Name = "OpenPop", Scale = 1 }, root)
	-- the Pop window: the teal band (icon, title, X) over the dark studded body
	local chrome = ElevatorView.popWindow(root, ElevatorView.Title, ElevatorView.Paint, METRICS.Normal.Band)
	local panel = chrome.Panel
	local icon = headerIcon(chrome.Header)
	icon.ZIndex = 5

	-- the subtitle line under the band (or the last server message)
	local subtitle: Frame = UIKit.new("Frame", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, panel)
	UIKit.list(subtitle, Enum.FillDirection.Horizontal, 0, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local parts: { TextLabel } = {}
	for i = 1, 3 do
		table.insert(
			parts,
			Pop.text(subtitle, "", 20, {
				Name = "Part" .. i,
				LayoutOrder = i,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		)
	end
	local message = Pop.text(panel, "", 20, {
		Name = "Message",
		TextColor3 = Theme.Bad,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		ZIndex = 3,
	})

	-- the Buy page
	local buyPage: Frame = UIKit.new("Frame", {
		Name = "BuyPage",
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, panel)
	local pitch = Pop.text(buyPage, ElevatorView.Pitch, 22, {
		Name = "Pitch",
		TextWrapped = true,
	})
	local strip: Frame = UIKit.new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
	}, buyPage)
	UIKit.list(strip, Enum.FillDirection.Horizontal, 12, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local tiles: { Frame } = {}
	for _, floor in MineFloors.List do
		table.insert(tiles, newTile(strip, floor.Index, ElevatorView.floorColor(floor.Index), tostring(floor.Index), floor.ViaElevator))
	end
	table.insert(tiles, newTile(strip, MineFloors.ComingSoon.Index, ElevatorView.SoonColor, "?", false))
	local caption = Pop.text(buyPage, ElevatorView.captionText(), 18, {
		Name = "Caption",
		TextColor3 = GOLD_TEXT,
		TextWrapped = true,
	})
	-- the price in a dark studded well: a gold coin and the amount in gold
	local priceBox = Pop.well(buyPage, { Name = "PriceBox" })
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, priceBox)
	local coin = Pop.coin(priceBox, 40, { AnchorPoint = Vector2.new(0, 0.5), ZIndex = 4 })
	local price = Pop.title(priceBox, "", 44, "Gold", {
		Name = "Price",
		FontFace = PopTheme.Heavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local buyLook = ElevatorView.popButton(buyPage, "Buy", { "Lock" }, ICON_MAKERS)
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, buyLook.Holder)
	local note = Pop.text(buyPage, "", 18, {
		Name = "Note",
		TextColor3 = TEXT_SOFT,
		TextWrapped = true,
	})

	-- the Floors page
	local floorPage: Frame = UIKit.new("Frame", {
		Name = "FloorPage",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, panel)
	-- the cards scroll when they don't all fit (phones); a gamepad selection scrolls it too
	local floorScroll: ScrollingFrame = UIKit.new("ScrollingFrame", {
		Name = "FloorScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = rgb(196, 200, 212),
		ScrollBarImageTransparency = 0.2,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, floorPage)
	local cards: { Card } = {}
	for _, entry in ElevatorView.entries(1, nil) do
		table.insert(cards, newCard(floorScroll, entry))
	end

	local doors, doorLeft, doorRight, seam = newDoors(panel)

	-- the footer pill on the root (over the frame's bottom edge)
	local footer, hint, hintIcons, glyph = newFooter(root)

	local drops: { [string]: { DropItem } } = { Floors = {}, Buy = {} }
	for _, card in cards do
		table.insert(drops.Floors, { Frame = card.Frame, Scale = card.Scale, Base = UDim2.new() })
	end
	for _, slot in tiles do
		local tile = slot:FindFirstChild("Tile") :: Frame
		table.insert(drops.Buy, { Frame = tile, Scale = tile:FindFirstChild("Drop") :: UIScale, Base = UDim2.fromScale(0.5, 0.5) })
	end
	table.insert(drops.Buy, { Frame = priceBox, Scale = priceBox:FindFirstChild("Drop") :: UIScale, Base = UDim2.new() })
	table.insert(drops.Buy, { Frame = buyLook.Holder, Scale = buyLook.Holder:FindFirstChild("Drop") :: UIScale, Base = UDim2.new() })

	local refs: Refs = {
		Gui = gui,
		Root = root,
		Pop = pop,
		Panel = panel,
		Header = chrome.Header,
		Body = chrome.Body,
		Chrome = chrome,
		Icon = icon,
		Title = chrome.Title,
		TitleShadow = chrome.TitleShadow,
		Subtitle = subtitle,
		SubtitleParts = parts,
		Message = message,
		Close = chrome.CloseLook.Button,
		CloseLook = chrome.CloseLook,
		BuyPage = buyPage,
		Pitch = pitch,
		Strip = strip,
		Tiles = tiles,
		Caption = caption,
		PriceBox = priceBox,
		Coin = coin,
		Price = price,
		BuyButton = buyLook.Button,
		BuyLook = buyLook,
		Note = note,
		FloorPage = floorPage,
		FloorScroll = floorScroll,
		Columns = 4,
		Cards = cards,
		Footer = footer,
		Hint = hint,
		HintIcons = hintIcons,
		HintGlyph = glyph,
		Doors = doors,
		DoorLeft = doorLeft,
		DoorRight = doorRight,
		Seam = seam,
		DropIns = drops,
		Mode = "Buy",
		Compact = false,
		CanAfford = false,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
		Level = 1,
		PoseTime = ElevatorView.OpenTime,
		HintKind = "Mouse",
	}
	ElevatorView.setPurchase(refs, 0, MineFloors.Elevator.Price)
	ElevatorView.setFloors(refs, ElevatorView.entries(1, nil), 1)
	ElevatorView.setHint(refs, "Mouse", "Click GO to ride · Backspace: close")
	ElevatorView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- filling in

local function setSubtitle(refs: Refs)
	local m = metrics(refs.Compact)
	local list = ElevatorView.subtitleParts(refs.Mode, refs.Level)
	for i, label in refs.SubtitleParts do
		local part = list[i]
		label.Visible = part ~= nil
		if part then
			label.Text = part.Text
			label.TextColor3 = part.Color
			label.TextSize = m.Text
			label.Size = UDim2.new(0, math.ceil(ElevatorView.measure(part.Text, m.Text)) + 1, 1, 0)
		end
	end
end

-- The Buy page: the price, the BUY button (greyed out with a lock when you can't afford it) and the note.
function ElevatorView.setPurchase(refs: Refs, coins: any, price: number)
	local afford = ElevatorView.canAfford(coins, price)
	refs.CanAfford = afford
	refs.Price.Text = Format.money(price)
	local have = if type(coins) == "number" then coins else 0
	refs.Note.Text = ElevatorView.noteText(have, price)
	refs.Note.TextColor3 = if afford then Theme.Good else TEXT_SOFT
	local m = metrics(refs.Compact)
	styleButton(refs.BuyLook, if afford then "Buy" else "BuyLocked", "BUY", m.ButtonText + 6, true)
	refs.BuyButton.Selectable = afford
end

local function fillCard(card: Card, entry: FloorEntry, m: Metrics)
	card.Entry = entry
	local here = entry.State == "Here"
	local soon = entry.State == "Soon"
	local closed = soon or entry.State == "Locked"
	card.Number.Text = if soon then "?" else tostring(entry.Index)
	-- the card and its badge in the floor's colour (the round look: deeper, like the reel's
	-- area pictures)
	local round = PopTheme.round()
	Pop.repaint(card.Face, ElevatorView.paintFrom(ElevatorView.cardColor(entry.Color)), false)
	Pop.repaint(card.Badge, badgePaint(entry.Color))
	card.Name.Text = entry.Name
	card.Name.TextColor3 = if soon then TEXT_SOFT else TEXT
	-- the ore rarity chips
	for i, chip in card.RarityChips do
		local rarity = entry.Rarities[i]
		chip.Visible = rarity ~= nil
		local label = chip:FindFirstChild("Label") :: TextLabel?
		if rarity and label then
			label.Text = rarity
			Pop.repaint(chip, Pop.rarityPaint(rarity))
		end
	end
	-- a floor you can't ride to: the dark shade, the requirement on the button's corner
	card.Shade.Visible = closed
	local padlock = card.Face:FindFirstChild("Padlock")
	if padlock and padlock:IsA("GuiObject") then
		padlock.Visible = round and entry.State == "Locked"
	end
	card.Chip.Text = entry.Requirement
	local pill = if soon then ElevatorView.SoonColor elseif entry.Met then MET else UNMET
	paintChip(card.ChipGradient, pill)
	card.ChipStroke.Color = OUTLINE
	card.Pill.Visible = closed
	card.Rarities.Visible = not (closed and card.Rarities:GetAttribute("UnderPill") == true)
	local modeKind = if soon then "Clock" elseif entry.ElevatorOnly then "Crown" else "Walk"
	for kind, icon in card.ModeIcons do
		icon.Visible = kind == modeKind
	end
	card.ModeText.Text = if soon then "Next update" elseif entry.ElevatorOnly then "Elevator only" else "Walk or ride"
	card.ModeText.TextColor3 = if soon then TEXT_SOFT elseif entry.ElevatorOnly then GOLD_TEXT else TEXT
	-- the edge: Pop black; the current floor: gold, thicker, with the soft gold halo
	card.Stroke.Color = if here then GOLD else OUTLINE
	card.Stroke.Thickness = if here then 4 else PopTheme.Edge
	card.Glow.Visible = here
	local style = if entry.State == "Open" then "Go" elseif here then "Here" elseif soon then "Soon" else "Locked"
	local long = here or soon
	styleButton(card.Look, style, ElevatorView.buttonText(entry.State), if long then m.ButtonText - 4 else m.ButtonText + 4)
	-- only GO moves you; a tap on LOCKED says why (the controller), the others do nothing
	card.Button.Selectable = entry.State == "Open"
end

-- A floor card's colour: the floor's (the round look: deeper, like the reel's area pictures).
function ElevatorView.cardColor(color: Color3): Color3
	return if PopTheme.round() then color:Lerp(Color3.new(0, 0, 0), 0.28) else color
end

-- The Floors page: the cards and the blaster line in the header.
function ElevatorView.setFloors(refs: Refs, entries: { FloorEntry }, level: number)
	local m = metrics(refs.Compact)
	for i, card in refs.Cards do
		local entry = entries[i]
		if entry then
			fillCard(card, entry, m)
		end
	end
	refs.Level = level
	setSubtitle(refs)
end

-- The footer pill: the hint text and its icon (mouse, a tap, or the gamepad glyph the controller sets).
function ElevatorView.setHint(refs: Refs, kind: HintKind, text: string)
	refs.HintKind = kind
	refs.HintIcons.Mouse.Visible = kind == "Mouse"
	refs.HintIcons.Touch.Visible = kind == "Touch"
	refs.HintGlyph.Visible = kind == "Gamepad"
	refs.Hint.Text = text
	refs.Hint.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(text, refs.Hint.TextSize)) + 2, 26)
	local width = ElevatorView.measure(text, refs.Hint.TextSize) + 26 + 8 + 44
	refs.Footer.Size = UDim2.fromOffset(math.ceil(width), refs.Footer.Size.Y.Offset)
end

-- Shows the Buy page or the Floors page.
function ElevatorView.setMode(refs: Refs, mode: Mode)
	refs.Mode = mode
	refs.BuyPage.Visible = mode == "Buy"
	refs.FloorPage.Visible = mode == "Floors"
	setSubtitle(refs)
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

-- A message under the band (instead of the subtitle).
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
	local inner = width - m.Pad * 2
	local top = m.Header
	refs.BuyPage.Position = UDim2.fromOffset(m.Pad, top)
	refs.BuyPage.Size = UDim2.new(1, -m.Pad * 2, 1, -top)
	-- room for two lines (one line on wide panels sits in the middle of it)
	local pitchHeight = math.floor(m.Pitch * 2.5)
	refs.Pitch.Position = UDim2.fromOffset(4, 0)
	refs.Pitch.Size = UDim2.new(1, -8, 0, pitchHeight)
	refs.Pitch.TextSize = m.Pitch
	local y = pitchHeight + 8
	local tile = m.Tile
	refs.Strip.Position = UDim2.fromOffset(0, y)
	refs.Strip.Size = UDim2.new(1, 0, 0, tile + 14)
	for _, slot in refs.Tiles do
		slot.Size = UDim2.fromOffset(tile, tile)
	end
	y += tile + 22
	refs.Caption.Position = UDim2.fromOffset(0, y)
	refs.Caption.Size = UDim2.new(1, 0, 0, m.Text + 6)
	refs.Caption.TextSize = m.Text - 1
	y += m.Text + 20
	-- price on the left, BUY on the right, the note under both
	local half = math.floor((inner - m.Gap) / 2)
	local boxHeight = m.Button + 18
	local drops = refs.DropIns.Buy
	local priceBase = UDim2.fromOffset(half / 2, y + boxHeight / 2)
	drops[#drops - 1].Base = priceBase
	refs.PriceBox.AnchorPoint = Vector2.new(0.5, 0.5)
	refs.PriceBox.Position = priceBase
	refs.PriceBox.Size = UDim2.fromOffset(half, boxHeight)
	local coinSize = math.floor(boxHeight * 0.58)
	refs.Coin.Position = UDim2.new(0, 16, 0.5, 0)
	refs.Coin.Size = UDim2.fromOffset(coinSize, coinSize)
	local mark = refs.Coin:FindFirstChild("Mark") :: TextLabel?
	if mark then
		mark.TextSize = math.floor(coinSize * 0.62)
	end
	refs.Price.Position = UDim2.fromOffset(coinSize + 30, 0)
	refs.Price.Size = UDim2.new(1, -(coinSize + 38), 1, 0)
	refs.Price.TextSize = m.Price
	local buy = refs.BuyLook.Holder
	local buyWidth = inner - half - m.Gap
	local buyBase = UDim2.fromOffset(half + m.Gap + buyWidth / 2, y + 9 + (m.Button + 4) / 2)
	drops[#drops].Base = buyBase
	buy.AnchorPoint = Vector2.new(0.5, 0.5)
	buy.Position = buyBase
	buy.Size = UDim2.fromOffset(buyWidth, m.Button + 4)
	y += boxHeight + 12
	refs.Note.Position = UDim2.fromOffset(0, y)
	refs.Note.Size = UDim2.new(1, 0, 0, m.Text + 8)
	refs.Note.TextSize = m.Text - 1
	return y + m.Text + 8
end

-- Sizes a card's rarity chips for `textSize` (smaller when they don't fit `room`); returns the row's width.
local function sizeChips(card: Card, textSize: number, height: number, room: number): number
	local function total(size: number): number
		local sum = 0
		for _, chip in card.RarityChips do
			local label = chip:FindFirstChild("Label") :: TextLabel?
			if chip.Visible and label then
				sum += math.ceil(ElevatorView.measure(label.Text, size)) + 18 + 6
			end
		end
		return math.max(0, sum - 6)
	end
	local size = textSize
	local width = total(size)
	if width > room and width > 0 then
		size = math.max(11, math.floor(textSize * room / width))
		width = total(size)
	end
	for _, chip in card.RarityChips do
		local label = chip:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextSize = size
			local edge = label:FindFirstChild("Edge") :: UIStroke?
			if edge then
				edge.Thickness = Pop.edgeFor(size)
			end
			chip.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(label.Text, size)) + 18, height)
		end
	end
	return width
end

local function layoutCard(card: Card, m: Metrics, cardWidth: number, cardHeight: number)
	-- inside a card: the badge with the name and the rarity chips beside it, the mode line (when
	-- there is room), the button at the bottom, the art on the right above the button
	local buttonHeight = math.min(m.Button, math.floor(cardHeight * 0.45))
	local badge = math.min(m.Badge, cardHeight - buttonHeight - 36)
	local showMode = cardHeight >= 12 + badge + 6 + m.ModeIcon + 8 + buttonHeight + 12
	card.Badge.Size = UDim2.fromOffset(badge, badge)
	card.Number.TextSize = math.floor(badge * 0.66)
	local numberEdge = card.Number:FindFirstChild("Edge") :: UIStroke?
	if numberEdge then
		numberEdge.Thickness = Pop.edgeFor(card.Number.TextSize)
	end
	local left = 12 + badge + 12
	local nameHeight = math.floor(badge * 0.5)
	card.Name.Position = UDim2.fromOffset(left, 12)
	card.Name.Size = UDim2.new(1, -(left + 10), 0, nameHeight)
	-- the name shrinks to fit a narrow card (never under MinNameSize)
	local room = cardWidth - left - 10
	local wide = ElevatorView.measure(card.Name.Text, m.CardName)
	card.Name.TextSize = if wide > room then math.max(ElevatorView.MinNameSize, math.floor(m.CardName * room / wide)) else m.CardName
	local nameEdge = card.Name:FindFirstChild("Edge") :: UIStroke?
	if nameEdge then
		nameEdge.Thickness = Pop.edgeFor(card.Name.TextSize)
	end
	-- the rarity chips under the name
	local chipsTop = 12 + nameHeight + 2
	local chipsWidth = sizeChips(card, m.ChipText, m.Chip, room)
	card.Rarities.Position = UDim2.fromOffset(left, chipsTop)
	card.Rarities.Size = UDim2.new(1, -(left + 10), 0, m.Chip)
	-- the mode line under the badge
	card.ModeRow.Visible = showMode
	card.ModeRow.Position = UDim2.fromOffset(14, 12 + badge + 8)
	card.ModeRow.Size = UDim2.new(1, -28, 0, m.ModeIcon + 2)
	for _, icon in card.ModeIcons do
		icon.Size = UDim2.fromOffset(m.ModeIcon, m.ModeIcon)
	end
	card.ModeText.TextSize = m.ModeText
	card.ModeText.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(card.ModeText.Text, m.ModeText)) + 4, m.ModeIcon + 2)
	-- the button (the round look: the reel's TELEPORT, bottom-right, half the card)
	local holder = card.Look.Holder
	if PopTheme.round() then
		holder.AnchorPoint = Vector2.new(1, 1)
		holder.Position = UDim2.new(1, -12, 1, -12)
		holder.Size = UDim2.new(0.56, -12, 0, buttonHeight)
	else
		holder.AnchorPoint = Vector2.new(0, 1)
		holder.Position = UDim2.new(0, 12, 1, -12)
		holder.Size = UDim2.new(1, -24, 0, buttonHeight)
	end
	-- the requirement pill on the button's top-right corner (a locked floor)
	local buttonTop = cardHeight - 12 - buttonHeight
	local pillText = m.ChipText + 1
	card.Chip.TextSize = pillText
	local pillWidth = math.ceil(ElevatorView.measure(card.Chip.Text, pillText)) + 26
	card.Pill.AnchorPoint = Vector2.new(1, 0.5)
	card.Pill.Position = UDim2.fromOffset(cardWidth - 22, buttonTop)
	card.Pill.Size = UDim2.fromOffset(pillWidth, m.Chip)
	-- (a short card: the pill would sit on the chips; a locked one hides its chips)
	local under = chipsTop + m.Chip > buttonTop - m.Chip / 2 - 2 and left + chipsWidth > cardWidth - 22 - pillWidth - 4
	card.Rarities:SetAttribute("UnderPill", under)
	card.Rarities.Visible = not (card.Pill.Visible and under)
	-- the art: the right part of the card above the button; the light burst follows it
	local artHeight = cardHeight - 12 - buttonHeight - 12
	local artScale = math.min(artHeight / 120, (cardWidth * 0.6 - 4) / 170)
	card.CanvasScale.Scale = artScale
	-- the canvas scales about its centre: its top-right corner sits at (-4, 4)
	local cx, cy = cardWidth - 4 - 85 * artScale, 4 + 60 * artScale
	card.Canvas.Position = UDim2.fromOffset(cx, cy)
	for _, fxName in CARD_FX do
		local fx = card.Face:FindFirstChild(fxName)
		if fx and fx:IsA("GuiObject") then
			fx.Position = UDim2.fromOffset(cx, cy)
		end
	end
end

-- the room round the cards inside the scroll (the current floor's gold halo is not clipped)
local CARD_MARGIN = 6

--[[
	The cards: four a row when each is at least MinCardWidth wide (PC: 4 + 3, the
	short last row centred, nothing scrolls), else three a row; two rows always
	show, the top of the next one peeks in under them (ScrollPeek) and it
	scrolls into view (phones: the Coming soon card is a swipe away).
]]
local function layoutFloors(refs: Refs, m: Metrics, width: number, height: number)
	local top = m.Header
	local bottom = if refs.Compact then m.Pad else m.Pad + 14
	refs.FloorPage.Position = UDim2.fromOffset(m.Pad, top)
	refs.FloorPage.Size = UDim2.new(1, -m.Pad * 2, 1, -(top + bottom))
	local inner = width - m.Pad * 2 - CARD_MARGIN * 2
	local count = #refs.Cards
	local columns = if (inner - m.Gap * 3) / 4 >= ElevatorView.MinCardWidth then 4 else 3
	refs.Columns = columns
	local rows = math.ceil(count / columns)
	local shown = math.min(rows, 2)
	local pageHeight = height - top - bottom
	local scrolls = rows > shown
	-- room for the scroll bar on the right when the cards scroll
	local barRoom = if scrolls then refs.FloorScroll.ScrollBarThickness + 4 else 0
	local cardWidth = math.floor((inner - barRoom - m.Gap * (columns - 1)) / columns)
	-- when the cards scroll, the next row peeks in under the last full one (there is more)
	local peek = if scrolls then ElevatorView.ScrollPeek else 0
	local cardHeight = math.floor((pageHeight - CARD_MARGIN * 2 - m.Gap * (shown - 1) - peek) / shown)
	for i, card in refs.Cards do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		-- a short last row sits in the middle
		local inRow = math.min(columns, count - row * columns)
		local shift = (columns - inRow) * (cardWidth + m.Gap) / 2
		-- centred anchors: the drop-in UIScale grows from the middle
		local base = UDim2.fromOffset(
			CARD_MARGIN + shift + column * (cardWidth + m.Gap) + cardWidth / 2,
			CARD_MARGIN + row * (cardHeight + m.Gap) + cardHeight / 2
		)
		refs.DropIns.Floors[i].Base = base
		card.Frame.Position = base
		card.Frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		layoutCard(card, m, cardWidth, cardHeight)
	end
	refs.FloorScroll.CanvasSize = UDim2.fromOffset(0, CARD_MARGIN * 2 + rows * cardHeight + (rows - 1) * m.Gap)
	refs.FloorScroll.ScrollingEnabled = scrolls
	refs.FloorScroll.ScrollBarImageTransparency = if scrolls then 0.2 else 1
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
	local bottom = if compact then m.Pad else m.Pad + 26
	local buyContent = layoutBuy(refs, m, width)
	local wantHeight = if refs.Mode == "Buy" then m.Header + buyContent + bottom else m.FloorHeight
	local height = math.max(380, math.min(wantHeight, maxHeight - 16))
	refs.Root.Size = UDim2.fromOffset(width, height)
	-- phones: at the bottom of the screen, clear of the HUD coins when there is room
	refs.Root.AnchorPoint = if compact then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	refs.Root.Position = if compact then UDim2.new(0.5, 0, 1, -10) else UDim2.fromScale(0.5, 0.5)
	-- the band: the icon, the title (with its shadow) and the X
	ElevatorView.fitWindow(refs.Chrome, refs.Icon, m.Band, m.Title, m.Icon, m.Close)
	-- the subtitle line under the band
	refs.Subtitle.Position = UDim2.fromOffset(m.Pad, m.Band + 2)
	refs.Subtitle.Size = UDim2.new(1, -m.Pad * 2, 0, m.Header - m.Band - 4)
	refs.Message.Position = refs.Subtitle.Position
	refs.Message.Size = refs.Subtitle.Size
	refs.Message.TextSize = m.Text
	setSubtitle(refs)
	-- the footer pill (on the bottom edge; not on phones)
	refs.Footer.Visible = not compact
	refs.Footer.Size = UDim2.fromOffset(refs.Footer.Size.X.Offset, math.max(m.Footer, 30))
	layoutFloors(refs, m, width, height)
	ElevatorView.pose(refs, refs.PoseTime)
end

---------------------------------------------------------------- the opening animation

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function outQuad(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function inOutQuad(x: number): number
	if x < 0.5 then
		return 2 * x * x
	end
	local y = -2 * x + 2
	return 1 - y * y / 2
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

--[[
	The panel `seconds` into its opening (0 = doors shut, OpenTime = open):
	the panel pops in with a slight overshoot (0-0.3 s), the doors with the
	glowing seam slide apart (0.06-0.36 s) and the cards (or the Buy page's
	chips, price and BUY) drop in one after another (from 0.2 s). Closing
	plays it backwards. The controller drives it with a tween.
]]
function ElevatorView.pose(refs: Refs, seconds: number)
	local t = math.clamp(seconds, 0, ElevatorView.OpenTime)
	refs.PoseTime = t
	refs.Pop.Scale = 0.88 + 0.12 * backOut(clamp01(t / 0.3))
	local d = inOutQuad(clamp01((t - 0.06) / 0.3))
	refs.Doors.Visible = d < 1
	refs.DoorLeft.Position = UDim2.fromScale(-0.56 * d, 0)
	refs.DoorRight.Position = UDim2.fromScale(1 + 0.56 * d, 0)
	refs.Seam.BackgroundTransparency = clamp01(d * 4)
	local list = refs.DropIns[refs.Mode]
	local step = if #list > 6 then 0.025 else 0.035
	for i, item in list do
		local q = clamp01((t - 0.2 - step * (i - 1)) / 0.18)
		item.Frame.Visible = q > 0
		local base = item.Base
		item.Frame.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - 18 * (1 - outQuad(q)))
		item.Scale.Scale = 0.86 + 0.14 * backOut(q)
	end
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
		BackgroundColor3 = Color3.fromRGB(8, 10, 24),
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
		TextColor3 = TEXT,
		TextScaled = true,
		TextTransparency = 1,
	})
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = rgb(20, 50, 150)
	end
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 72, MinTextSize = 24 }, title)
	local name = UIKit.label(black, "", 28, {
		Name = "FloorName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(0.9, 0, 0.07, 0),
		TextColor3 = NEON_BRIGHT,
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
