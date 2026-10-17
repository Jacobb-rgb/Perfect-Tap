--[[
	The mine elevator on screen (pure builder + pure helpers; ElevatorController
	fills it in and animates it). Look: the owner's mock
	docs/art/ui/elevator_ui_reference.webp (dark navy panel in a glowing blue
	neon frame) and icon docs/art/ui/elevator_icon.webp.

	  panel    header: a small elevator icon, a big white "ELEVATOR" and a
	           subtitle ("Your blaster: Lv 7. ..." with "Lv 7" in yellow);
	           a red X top-right; a footer pill with the control hint
	           ("Click GO to ride · Backspace: close") hanging on the bottom edge
	  Floors   (owned) a card per floor, 3 x 2: a coloured frame per floor,
	           a big number badge, the name, a "Blaster 7+" pill (green when
	           your blaster is enough, red when not, grey for Coming soon), a
	           mode line (walker "Walk or ride", crown "Elevator only", clock
	           "Next update"), themed art on the right half and the card's
	           button: "→ GO" / pin "YOU ARE HERE" / lock "LOCKED" / clock
	           "COMING SOON" (the sixth card is MineFloors.ComingSoon)
	  Buy      (not owned) the pitch, the floor chips 1-5 + "?", the price and
	           a BUY button greyed out (with a lock) while you can't afford it
	  doors    two steel door halves with a glowing seam over the panel: the
	           opening animation slides them apart (ElevatorView.pose)

	Every icon and every bit of art is drawn from Frames (rotated squares for
	crystals, UIGradient, UIStroke, UICorner): images need uploads under the
	owner's account. When the owner uploads the icons, set IconImage (the
	side button) and HeaderIconImage (the panel header) to the asset ids and
	ImageLabels are used instead.

	Also here: the left "SideMenu" (buildSideMenu, its own ScreenGui; later
	buttons can join its stack) with the elevator icon button, and the ride
	fade (buildFade).

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). The compact layout (phones, uiScale 0.62) has 72-unit
	buttons (about 44 pt) and fits the panel into what the screen leaves.
	A gamepad selection stays inside the panel (SelectionGroup); only the
	buttons that do something are selectable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local HudView = require(script.Parent.HudView)

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
	Color: Color3, -- the floor's UI colour (frame, badge)
}

-- a chunky button: a dark lip (Holder) under the face (Button)
export type ButtonRefs = {
	Holder: Frame,
	Edge: UIStroke,
	Button: TextButton,
	Gradient: UIGradient,
	Row: Frame,
	Icons: { [string]: Frame },
	Label: TextLabel,
	LabelStroke: UIStroke,
	Style: string,
}

export type DropItem = { Frame: Frame, Scale: UIScale, Base: UDim2 }

export type Card = {
	Index: number,
	Frame: Frame,
	Scale: UIScale,
	Stroke: UIStroke,
	Glow: Frame,
	ArtBack: Frame,
	ArtGradient: UIGradient,
	Canvas: Frame,
	CanvasScale: UIScale,
	Badge: Frame,
	BadgeGradient: UIGradient,
	Number: TextLabel,
	Name: TextLabel,
	Pill: Frame,
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
	Root: Frame, -- holds the glow, the panel, the X and the footer (pops in)
	Pop: UIScale,
	Panel: Frame,
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
	-- the Floors page
	FloorPage: Frame,
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

export type IconButton = {
	Holder: Frame,
	Button: TextButton,
	Scale: UIScale,
	Chevrons: { Frame }, -- bottom to top, left column then right column
	ChevronBase: { UDim2 },
	ChevronRow: { number }, -- 1 = bottom
	Label: TextLabel,
	Glyph: ImageLabel,
}

export type SideMenu = {
	Gui: ScreenGui,
	Menu: Frame,
	Elevator: IconButton,
}

type Metrics = {
	BuyWidth: number,
	FloorWidth: number,
	FloorHeight: number,
	Pad: number,
	Header: number,
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
local NAVY_TOP = rgb(26, 34, 72)
local NAVY_BOTTOM = rgb(12, 16, 38)
local NAVY_CARD = rgb(20, 26, 54)
local NAVY_DEEP = rgb(10, 14, 32)
local NEON = rgb(70, 170, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local NEON_DEEP = rgb(36, 84, 190)
local TEXT = rgb(245, 248, 255)
local TEXT_SOFT = rgb(196, 208, 236)
local TEXT_DIM = rgb(150, 158, 184)
local GOLD = rgb(255, 204, 64)
local GOLD_TEXT = rgb(255, 210, 90)
local INK = rgb(10, 12, 26) -- outlines

local METRICS: { [string]: Metrics } = {
	Normal = {
		BuyWidth = 720,
		FloorWidth = 960,
		FloorHeight = 540,
		Pad = 20,
		Header = 106,
		Title = 62,
		Icon = 66,
		Text = 20,
		Gap = 14,
		Button = 58,
		Badge = 64,
		CardName = 22,
		Chip = 26,
		ChipText = 16,
		ModeText = 17,
		ModeIcon = 20,
		Close = 60,
		Pitch = 22,
		Tile = 64,
		Price = 48,
		Footer = 36,
		ButtonText = 26,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		BuyWidth = 880,
		FloorWidth = 1040,
		FloorHeight = 520,
		Pad = 18,
		Header = 92,
		Title = 48,
		Icon = 60,
		Text = 21,
		Gap = 12,
		Button = 72,
		Badge = 62,
		CardName = 24,
		Chip = 28,
		ChipText = 17,
		ModeText = 18,
		ModeIcon = 22,
		Close = 68,
		Pitch = 24,
		Tile = 66,
		Price = 52,
		Footer = 0,
		ButtonText = 28,
	},
}

ElevatorView.Title = "ELEVATOR"
ElevatorView.Pitch = "Ride to every floor you have unlocked. Buy once, keep forever."
-- asset ids for the owner's uploaded icons ("" = draw them from Frames)
ElevatorView.IconImage = "" -- the side menu button (docs/art/ui/elevator_icon.webp)
ElevatorView.HeaderIconImage = "" -- the small icon left of the title
-- each floor's frame and badge colour (the mock): orange, red-orange, cyan, gold, purple; grey = coming soon
ElevatorView.FloorColors = {
	rgb(255, 150, 40),
	rgb(255, 92, 46),
	rgb(40, 196, 255),
	rgb(255, 190, 40),
	rgb(176, 72, 236),
} :: { Color3 }
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

--[[
	The six cards: MineFloors.List in order, then the "Coming soon" floor.
	`level` = the player's blaster level, `here` = the floor the player is on
	(nil = none of them).
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

-- The line under the title as coloured parts ("Lv 7" in yellow).
function ElevatorView.subtitleParts(mode: Mode, level: number): { { Text: string, Color: Color3 } }
	if mode == "Buy" then
		return { { Text = "Every mine floor, one ride away.", Color = TEXT } }
	end
	return {
		{ Text = "Your blaster: ", Color = TEXT },
		{ Text = `Lv {level}.`, Color = GOLD },
		{ Text = " Forge better blasters to unlock deeper floors.", Color = TEXT },
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

-- Half-sizes (x, z) of the floor areas around MineFloors.Placement (docs/plans/MINE_STEP_PLAN.md).
local FLOOR_HALF = { Vector2.new(70, 60), Vector2.new(68, 60), Vector2.new(68, 58), Vector2.new(66, 56), Vector2.new(80, 70) }

-- The floor whose area holds `position` (nil = town or elsewhere); only for "YOU ARE HERE".
function ElevatorView.floorAt(position: Vector3): number?
	for index, origin in MineFloors.Placement do
		local half = FLOOR_HALF[index] or Vector2.new(70, 60)
		local p = origin.Position
		local dy = position.Y - p.Y
		if math.abs(position.X - p.X) <= half.X and math.abs(position.Z - p.Z) <= half.Y and dy >= -30 and dy <= 60 then
			return index
		end
	end
	return nil
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

local function setGradient3(g: UIGradient, top: Color3, mid: Color3, bottom: Color3)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.5, mid),
		ColorSequenceKeypoint.new(1, bottom),
	})
end

local function ring(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	return UIKit.stroke(parent, thickness, color, transparency or 0)
end

-- An empty, square icon box; parts named "Ink" take the icon's colour (tint).
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

-- Colours every "Ink" part (and "InkRing" stroke) of an icon.
local function tint(icon: Instance, color: Color3)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.Name == "Ink" then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") and d.Name == "InkRing" then
			d.Color = color
		end
	end
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
	-- 5 Heartstone Core: the pink heart crystal on its pedestal
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
	-- 6 Coming soon: dim pillars and a big "?"
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

-- each card's art colour (the right end of its background)
local ART_TINT = {
	rgb(104, 104, 118),
	rgb(156, 56, 34),
	rgb(20, 112, 156),
	rgb(44, 74, 168),
	rgb(116, 40, 156),
	rgb(66, 70, 94),
}

---------------------------------------------------------------- chunky buttons

type ButtonStyle = {
	Top: Color3,
	Mid: Color3,
	Bottom: Color3,
	Lip: Color3,
	Edge: Color3,
	EdgeThickness: number,
	Text: Color3,
	TextStroke: Color3,
	Icon: string?,
	IconColor: Color3,
}

local BUTTON_STYLES: { [string]: ButtonStyle } = {
	Go = {
		Top = rgb(170, 250, 130),
		Mid = rgb(76, 214, 72),
		Bottom = rgb(46, 172, 54),
		Lip = rgb(22, 106, 34),
		Edge = INK,
		EdgeThickness = 3,
		Text = TEXT,
		TextStroke = rgb(18, 84, 28),
		Icon = "Arrow",
		IconColor = TEXT,
	},
	Here = {
		Top = rgb(30, 46, 98),
		Mid = rgb(18, 28, 66),
		Bottom = rgb(12, 18, 46),
		Lip = rgb(8, 12, 30),
		Edge = NEON,
		EdgeThickness = 3,
		Text = rgb(140, 210, 255),
		TextStroke = rgb(6, 16, 50),
		Icon = "Pin",
		IconColor = rgb(80, 180, 255),
	},
	Locked = {
		Top = rgb(70, 76, 98),
		Mid = rgb(54, 60, 80),
		Bottom = rgb(42, 47, 64),
		Lip = rgb(24, 27, 38),
		Edge = INK,
		EdgeThickness = 3,
		Text = rgb(172, 178, 200),
		TextStroke = rgb(18, 20, 30),
		Icon = "Lock",
		IconColor = rgb(166, 172, 194),
	},
	Soon = {
		Top = rgb(70, 76, 98),
		Mid = rgb(54, 60, 80),
		Bottom = rgb(42, 47, 64),
		Lip = rgb(24, 27, 38),
		Edge = INK,
		EdgeThickness = 3,
		Text = rgb(172, 178, 200),
		TextStroke = rgb(18, 20, 30),
		Icon = "Clock",
		IconColor = rgb(166, 172, 194),
	},
	Buy = {
		Top = rgb(170, 250, 130),
		Mid = rgb(76, 214, 72),
		Bottom = rgb(46, 172, 54),
		Lip = rgb(22, 106, 34),
		Edge = INK,
		EdgeThickness = 3,
		Text = TEXT,
		TextStroke = rgb(18, 84, 28),
		Icon = nil,
		IconColor = TEXT,
	},
	BuyLocked = {
		Top = rgb(70, 76, 98),
		Mid = rgb(54, 60, 80),
		Bottom = rgb(42, 47, 64),
		Lip = rgb(24, 27, 38),
		Edge = INK,
		EdgeThickness = 3,
		Text = rgb(172, 178, 200),
		TextStroke = rgb(18, 20, 30),
		Icon = "Lock",
		IconColor = rgb(166, 172, 194),
	},
	Close = {
		Top = rgb(255, 128, 112),
		Mid = rgb(236, 62, 62),
		Bottom = rgb(196, 38, 44),
		Lip = rgb(120, 22, 28),
		Edge = INK,
		EdgeThickness = 3,
		Text = TEXT,
		TextStroke = rgb(90, 14, 20),
		Icon = nil,
		IconColor = TEXT,
	},
}
ElevatorView.ButtonStyles = BUTTON_STYLES

local ICON_MAKERS: { [string]: (Instance, Color3) -> Frame } = {
	Arrow = Icons.arrow,
	Pin = Icons.pin,
	Lock = Icons.lock,
	Clock = Icons.clock,
}

local function chunkyButton(parent: Instance, name: string, icons: { string }): ButtonRefs
	local holder: Frame = UIKit.new("Frame", {
		Name = name .. "Holder",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 56),
	}, parent)
	UIKit.corner(holder, 14)
	local edge = ring(holder, 3, INK)
	local button: TextButton = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -5),
		Size = UDim2.fromScale(1, 1),
		Text = "",
	}, holder)
	UIKit.corner(button, 14)
	local g = gradient3(button, WHITE, WHITE, WHITE)
	local row: Frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 10, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local made: { [string]: Frame } = {}
	for i, kind in icons do
		local icon = ICON_MAKERS[kind](row, TEXT)
		icon.LayoutOrder = i
		icon.Visible = false
		made[kind] = icon
	end
	local label = UIKit.label(row, "", 24, {
		Name = "Label",
		LayoutOrder = 10,
		TextWrapped = false,
		Size = UDim2.fromOffset(60, 30),
	})
	local labelStroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	labelStroke.Thickness = 2.5
	return {
		Holder = holder,
		Edge = edge,
		Button = button,
		Gradient = g,
		Row = row,
		Icons = made,
		Label = label,
		LabelStroke = labelStroke,
		Style = "",
	}
end

-- Paints a chunky button in a style with a text (sizes from `textSize`).
local function styleButton(look: ButtonRefs, styleName: string, text: string, textSize: number, title: boolean?)
	local style = BUTTON_STYLES[styleName]
	look.Style = styleName
	setGradient3(look.Gradient, style.Top, style.Mid, style.Bottom)
	look.Holder.BackgroundColor3 = style.Lip
	look.Edge.Color = style.Edge
	look.Edge.Thickness = style.EdgeThickness
	look.Label.Text = text
	look.Label.TextSize = textSize
	look.Label.FontFace = if title then Theme.TitleFont else Theme.Font
	look.Label.TextColor3 = style.Text
	look.LabelStroke.Color = style.TextStroke
	look.Label.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(text, textSize, title)) + 4, textSize + 8)
	local iconSize = math.floor(textSize * 0.95)
	for kind, icon in look.Icons do
		local shown = kind == style.Icon
		icon.Visible = shown
		if shown then
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			tint(icon, style.IconColor)
		end
	end
	look.Button.AutoButtonColor = false
end

---------------------------------------------------------------- building

-- A rounded pill (a Frame with its rim) with a label inside (one stroke per object).
local function newPill(parent: Instance): (Frame, TextLabel, UIGradient, UIStroke)
	local pill: Frame = UIKit.new("Frame", {
		Name = "Requirement",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, parent)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	local g = gradient3(pill, WHITE, WHITE, WHITE)
	local rim = ring(pill, 2, INK)
	local label = UIKit.label(pill, "", 16, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
	})
	return pill, label, g, rim
end

local function newCard(page: Frame, entry: FloorEntry): Card
	local frame: Frame = UIKit.new("Frame", {
		Name = "Floor" .. entry.Index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = NAVY_CARD,
		BorderSizePixel = 0,
	}, page)
	UIKit.corner(frame, 16)
	local stroke = ring(frame, 3, entry.Color)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
	-- the glow ring of the current floor
	local glow: Frame = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, frame)
	UIKit.corner(glow, 16)
	ring(glow, 9, NEON, 0.55)
	-- art on the right half: a background that fades in from the card colour, then the canvas
	local artBack: Frame = UIKit.new("Frame", {
		Name = "ArtBack",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(artBack, 12)
	local artGradient: UIGradient = UIKit.new("UIGradient", {
		Color = ColorSequence.new(NAVY_CARD, ART_TINT[entry.Index] or ART_TINT[6]),
		Rotation = 0,
	}, artBack)
	local canvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(170, 120),
	}, frame)
	local canvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, canvas)
	local draw = ART[entry.Index] or ART[6]
	draw(canvas)
	-- badge, name, pill, mode line
	local badge: Frame = UIKit.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12),
	}, frame)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.24, 0) }, badge)
	ring(badge, 3, INK)
	local badgeGradient = gradient3(badge, WHITE, WHITE, WHITE)
	local number = UIKit.label(badge, "", 40, {
		Name = "Number",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextColor3 = TEXT,
	})
	local numberStroke = number:FindFirstChildOfClass("UIStroke")
	if numberStroke then
		numberStroke.Thickness = 3
		numberStroke.Color = INK
	end
	local name = UIKit.label(frame, "", 22, {
		Name = "FloorName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextColor3 = TEXT,
	})
	local pill, chip, chipGradient, chipStroke = newPill(frame)
	local modeRow: Frame = UIKit.new("Frame", {
		Name = "Mode",
		BackgroundTransparency = 1,
	}, frame)
	UIKit.list(modeRow, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local modeIcons: { [string]: Frame } = {
		Walk = Icons.walker(modeRow, TEXT_SOFT),
		Crown = Icons.crown(modeRow, GOLD),
		Clock = Icons.clock(modeRow, TEXT_DIM),
	}
	for _, icon in modeIcons do
		icon.LayoutOrder = 1
	end
	local modeText = UIKit.label(modeRow, "", 17, {
		Name = "Text",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	local look = chunkyButton(frame, "Go", { "Arrow", "Pin", "Lock", "Clock" })
	return {
		Index = entry.Index,
		Frame = frame,
		Scale = scale,
		Stroke = stroke,
		Glow = glow,
		ArtBack = artBack,
		ArtGradient = artGradient,
		Canvas = canvas,
		CanvasScale = canvasScale,
		Badge = badge,
		BadgeGradient = badgeGradient,
		Number = number,
		Name = name,
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

local function paintBadge(g: UIGradient, color: Color3)
	setGradient3(g, color:Lerp(WHITE, 0.38), color, color:Lerp(BLACK, 0.22))
end

-- A floor chip of the Buy page (a small badge), in a slot so it can pop.
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
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, slot)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.24, 0) }, tile)
	ring(tile, 3, INK)
	paintBadge(gradient3(tile, WHITE, WHITE, WHITE), color)
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, tile)
	local number = UIKit.label(tile, text, 34, {
		Name = "Number",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextScaled = true,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 40 }, number)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0.16, 0),
		PaddingBottom = UDim.new(0.12, 0),
	}, number)
	local stroke = number:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 2.5
		stroke.Color = INK
	end
	if crown then
		local icon = Icons.crown(tile, GOLD)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.92, 0.06)
		icon.Size = UDim2.fromScale(0.42, 0.42)
		icon.Rotation = 18
	end
	return slot
end

local function newFooter(root: Frame): (Frame, TextLabel, { [string]: GuiObject }, ImageLabel)
	local footer: Frame = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(380, 36),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, root)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, footer)
	gradient3(footer, rgb(24, 32, 66), rgb(14, 20, 46), rgb(10, 14, 34))
	ring(footer, 2, NEON, 0.15)
	local row: Frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, footer)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
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
	local hint = UIKit.label(row, "", 17, {
		Name = "Hint",
		LayoutOrder = 2,
		TextWrapped = false,
		TextColor3 = TEXT,
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
		UIKit.corner(door, 22)
		UIKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(108, 122, 156)),
				ColorSequenceKeypoint.new(0.5, rgb(72, 82, 110)),
				ColorSequenceKeypoint.new(1, rgb(46, 52, 74)),
			}),
			Rotation = 90,
		}, door)
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
	-- the neon frame's soft outer glow (two rings outside the panel's own stroke)
	for i, spec in { { 16, 0.86 }, { 8, 0.62 } } do
		local glow: Frame = UIKit.new("Frame", {
			Name = "Glow" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, root)
		UIKit.corner(glow, 26)
		ring(glow, spec[1], NEON, spec[2])
	end
	local panel: Frame = UIKit.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
	}, root)
	UIKit.corner(panel, 24)
	gradient3(panel, NAVY_TOP, rgb(18, 24, 54), NAVY_BOTTOM)
	ring(panel, 4, NEON_BRIGHT)
	local bevel: Frame = UIKit.new("Frame", {
		Name = "Bevel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -14, 1, -14),
		BackgroundTransparency = 1,
	}, panel)
	UIKit.corner(bevel, 18)
	ring(bevel, 2, NEON_DEEP, 0.35)

	-- header
	local icon = headerIcon(panel)
	local titleShadow = UIKit.label(panel, ElevatorView.Title, 56, {
		Name = "TitleShadow",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = NEON_DEEP,
		TextWrapped = false,
	})
	local shadowStroke = titleShadow:FindFirstChildOfClass("UIStroke")
	if shadowStroke then
		shadowStroke.Color = rgb(8, 18, 60)
		shadowStroke.Thickness = 3
	end
	local title = UIKit.label(panel, ElevatorView.Title, 56, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = TEXT,
		TextWrapped = false,
	})
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = rgb(20, 50, 150)
		titleStroke.Thickness = 3
	end
	local subtitle: Frame = UIKit.new("Frame", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
	}, panel)
	UIKit.list(subtitle, Enum.FillDirection.Horizontal, 0, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local parts: { TextLabel } = {}
	for i = 1, 3 do
		table.insert(
			parts,
			UIKit.label(subtitle, "", 20, {
				Name = "Part" .. i,
				LayoutOrder = i,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		)
	end
	local message = UIKit.label(panel, "", 20, {
		Name = "Message",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Bad,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Visible = false,
	})

	-- the Buy page
	local buyPage: Frame = UIKit.new("Frame", {
		Name = "BuyPage",
		BackgroundTransparency = 1,
	}, panel)
	local pitch = UIKit.label(buyPage, ElevatorView.Pitch, 22, {
		Name = "Pitch",
		TextColor3 = TEXT,
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
	local caption = UIKit.label(buyPage, ElevatorView.captionText(), 18, {
		Name = "Caption",
		TextColor3 = GOLD_TEXT,
	})
	local priceBox: Frame = UIKit.new("Frame", {
		Name = "PriceBox",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, buyPage)
	UIKit.corner(priceBox, 16)
	gradient3(priceBox, rgb(16, 22, 50), NAVY_DEEP, rgb(8, 10, 26))
	ring(priceBox, 2, NEON, 0.2)
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, priceBox)
	local coin = HudView.coinIcon(priceBox, 40)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	local price = UIKit.label(priceBox, "", 48, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	local buyLook = chunkyButton(buyPage, "Buy", { "Lock" })
	UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, buyLook.Holder)
	local note = UIKit.label(buyPage, "", 18, {
		Name = "Note",
		TextColor3 = TEXT_SOFT,
	})

	-- the Floors page
	local floorPage: Frame = UIKit.new("Frame", {
		Name = "FloorPage",
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	local cards: { Card } = {}
	for _, entry in ElevatorView.entries(1, nil) do
		table.insert(cards, newCard(floorPage, entry))
	end

	local doors, doorLeft, doorRight, seam = newDoors(panel)

	-- on the root (over the frame): the X and the footer pill
	local closeLook = chunkyButton(root, "Close", {})
	closeLook.Holder.AnchorPoint = Vector2.new(1, 0)
	styleButton(closeLook, "Close", "X", 36, true)
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
		Icon = icon,
		Title = title,
		TitleShadow = titleShadow,
		Subtitle = subtitle,
		SubtitleParts = parts,
		Message = message,
		Close = closeLook.Button,
		CloseLook = closeLook,
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
	card.Number.Text = if soon then "?" else tostring(entry.Index)
	paintBadge(card.BadgeGradient, entry.Color)
	card.Name.Text = entry.Name
	card.Name.TextColor3 = if soon then TEXT_SOFT else TEXT
	card.Chip.Text = entry.Requirement
	local pill = if soon then ElevatorView.SoonColor elseif entry.Met then rgb(56, 190, 70) else rgb(226, 58, 72)
	setGradient3(card.ChipGradient, pill:Lerp(WHITE, 0.25), pill, pill:Lerp(BLACK, 0.15))
	card.ChipStroke.Color = pill:Lerp(BLACK, 0.55)
	card.Chip.TextColor3 = TEXT
	local modeKind = if soon then "Clock" elseif entry.ElevatorOnly then "Crown" else "Walk"
	for kind, icon in card.ModeIcons do
		icon.Visible = kind == modeKind
	end
	card.ModeText.Text = if soon then "Next update" elseif entry.ElevatorOnly then "Elevator only" else "Walk or ride"
	card.ModeText.TextColor3 = if soon then TEXT_DIM elseif entry.ElevatorOnly then GOLD_TEXT elseif here then NEON_BRIGHT else TEXT_SOFT
	tint(card.ModeIcons.Walk, if here then NEON_BRIGHT else TEXT_SOFT)
	-- the frame: the floor's colour; the current floor glows
	card.Stroke.Color = if here then NEON_BRIGHT else entry.Color
	card.Stroke.Thickness = if here then 4 else 3
	card.Glow.Visible = here
	card.Frame.BackgroundColor3 = if here then rgb(20, 34, 74) else NAVY_CARD
	card.ArtGradient.Color = ColorSequence.new(card.Frame.BackgroundColor3, ART_TINT[card.Index] or ART_TINT[6])
	local style = if entry.State == "Open" then "Go" elseif here then "Here" elseif soon then "Soon" else "Locked"
	local long = here or soon
	styleButton(card.Look, style, ElevatorView.buttonText(entry.State), if long then m.ButtonText - 4 else m.ButtonText + 4)
	-- only GO moves you; a tap on LOCKED says why (the controller), the others do nothing
	card.Button.Selectable = entry.State == "Open"
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

local function layoutCard(card: Card, m: Metrics, cardWidth: number, cardHeight: number)
	-- inside a card: badge row, the mode line (when there is room), the button
	local buttonHeight = math.min(m.Button, math.floor(cardHeight * 0.45))
	local badge = math.min(m.Badge, cardHeight - buttonHeight - 36)
	local showMode = cardHeight >= 12 + badge + 6 + m.ModeIcon + 8 + buttonHeight + 12
	card.Badge.Size = UDim2.fromOffset(badge, badge)
	card.Number.TextSize = math.floor(badge * 0.66)
	local left = 12 + badge + 12
	local nameHeight = math.floor(badge * 0.5)
	card.Name.Position = UDim2.fromOffset(left, 12)
	card.Name.Size = UDim2.new(1, -(left + 10), 0, nameHeight)
	card.Name.TextSize = m.CardName
	local chipText = m.ChipText
	card.Chip.TextSize = chipText
	card.Pill.Position = UDim2.fromOffset(left, 12 + nameHeight + 2)
	card.Pill.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(card.Chip.Text, chipText)) + 28, m.Chip)
	card.ModeRow.Visible = showMode
	card.ModeRow.Position = UDim2.fromOffset(14, 12 + badge + 8)
	card.ModeRow.Size = UDim2.new(1, -28, 0, m.ModeIcon + 2)
	for _, icon in card.ModeIcons do
		icon.Size = UDim2.fromOffset(m.ModeIcon, m.ModeIcon)
	end
	card.ModeText.TextSize = m.ModeText
	card.ModeText.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(card.ModeText.Text, m.ModeText)) + 4, m.ModeIcon + 2)
	local holder = card.Look.Holder
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.new(0, 12, 1, -12)
	holder.Size = UDim2.new(1, -24, 0, buttonHeight)
	-- art: the right part of the card above the button
	local artHeight = cardHeight - 12 - buttonHeight - 12
	card.ArtBack.Position = UDim2.new(0.4, 0, 0, 4)
	card.ArtBack.Size = UDim2.new(0.6, -4, 0, artHeight)
	local artScale = math.min(artHeight / 120, (cardWidth * 0.6 - 4) / 170)
	card.CanvasScale.Scale = artScale
	-- the canvas scales about its centre: place the centre so its top-right corner sits at (-4, 4)
	card.Canvas.Position = UDim2.new(1, -4 - 85 * artScale, 0, 4 + 60 * artScale)
end

local function layoutFloors(refs: Refs, m: Metrics, width: number, height: number)
	local top = m.Header
	local bottom = if refs.Compact then m.Pad else m.Pad + 14
	refs.FloorPage.Position = UDim2.fromOffset(m.Pad, top)
	refs.FloorPage.Size = UDim2.new(1, -m.Pad * 2, 1, -(top + bottom))
	local columns = 3
	local rows = math.ceil(#refs.Cards / columns)
	local cardWidth = math.floor((width - m.Pad * 2 - m.Gap * (columns - 1)) / columns)
	local cardHeight = math.floor((height - top - bottom - m.Gap * (rows - 1)) / rows)
	for i, card in refs.Cards do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		-- centred anchors: the drop-in UIScale grows from the middle
		local base = UDim2.fromOffset(column * (cardWidth + m.Gap) + cardWidth / 2, row * (cardHeight + m.Gap) + cardHeight / 2)
		refs.DropIns.Floors[i].Base = base
		card.Frame.Position = base
		card.Frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		layoutCard(card, m, cardWidth, cardHeight)
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
	local bottom = if compact then m.Pad else m.Pad + 26
	local buyContent = layoutBuy(refs, m, width)
	local wantHeight = if refs.Mode == "Buy" then m.Header + buyContent + bottom else m.FloorHeight
	local height = math.max(380, math.min(wantHeight, maxHeight - 16))
	refs.Root.Size = UDim2.fromOffset(width, height)
	-- phones: at the bottom of the screen, clear of the HUD coins when there is room
	refs.Root.AnchorPoint = if compact then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	refs.Root.Position = if compact then UDim2.new(0.5, 0, 1, -10) else UDim2.fromScale(0.5, 0.5)
	-- header: icon, title (with its shadow), subtitle
	local iconSize = m.Icon
	refs.Icon.Position = UDim2.fromOffset(m.Pad + 4, 14)
	refs.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local textLeft = m.Pad + 4 + iconSize + 14
	local titleWidth = width - textLeft - (m.Close + m.Pad + 12)
	refs.Title.Position = UDim2.fromOffset(textLeft, 8)
	refs.Title.Size = UDim2.fromOffset(titleWidth, m.Title + 4)
	refs.Title.TextSize = m.Title
	refs.TitleShadow.Position = UDim2.fromOffset(textLeft + 2, 12)
	refs.TitleShadow.Size = refs.Title.Size
	refs.TitleShadow.TextSize = m.Title
	refs.Subtitle.Position = UDim2.fromOffset(textLeft, 8 + m.Title + 4)
	refs.Subtitle.Size = UDim2.fromOffset(titleWidth, m.Text + 8)
	refs.Message.Position = refs.Subtitle.Position
	refs.Message.Size = refs.Subtitle.Size
	refs.Message.TextSize = m.Text
	setSubtitle(refs)
	-- the X (on the frame's corner) and the footer pill (on the bottom edge; not on phones)
	local close = refs.CloseLook.Holder
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -12, 0, 16)
	refs.CloseLook.Label.TextSize = if compact then 40 else 36
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

---------------------------------------------------------------- the side menu

--[[
	The elevator icon button (after docs/art/ui/elevator_icon.webp): a glowing
	blue rounded square, a steel shaft with a glass cabin and a blocky figure
	inside, glowing up-chevrons on both sides, "Elevator" under it. `size` =
	the square's side in design units (84 = 52 pt at the phone scale).
]]
function ElevatorView.iconButton(parent: Instance, size: number): IconButton
	local holder: Frame = UIKit.new("Frame", {
		Name = "ElevatorButton",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size + 8, size + 30),
	}, parent)
	local button: TextButton = UIKit.new("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 4 + size / 2),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, button)
	gradient3(button, rgb(34, 60, 132), rgb(18, 32, 82), rgb(10, 18, 50))
	ring(button, 4, NEON_BRIGHT)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Bounce", Scale = 1 }, button)
	-- soft outer glow
	local glow: Frame = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, button)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, glow)
	ring(glow, 9, NEON, 0.65)
	local chevrons: { Frame } = {}
	local bases: { UDim2 } = {}
	local rows: { number } = {}
	if ElevatorView.IconImage ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = ElevatorView.IconImage,
			ScaleType = Enum.ScaleType.Fit,
		}, button)
	else
		-- little sparkles in the corners
		for _, spot in { { 0.2, 0.2, 25 }, { 0.8, 0.17, -20 }, { 0.17, 0.84, -25 }, { 0.83, 0.85, 20 } } do
			local sparkle = shape(button, "Sparkle", spot[1], spot[2], 0.07, 0.035, NEON_BRIGHT, spot[3], 0.3)
			sparkle.BackgroundTransparency = 0.25
		end
		-- the shaft (behind the cabin) with its glowing stripes and the rail
		local shaft = shape(button, "Shaft", 0.5, 0.5, 0.38, 0.9, WHITE, 0, 0.06)
		UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(108, 118, 146), rgb(56, 62, 86)), Rotation = 0 }, shaft)
		shape(button, "StripeL", 0.4, 0.5, 0.04, 0.9, NEON_BRIGHT)
		shape(button, "StripeR", 0.6, 0.5, 0.04, 0.9, NEON_BRIGHT)
		shape(button, "Rail", 0.5, 0.5, 0.05, 0.9, rgb(28, 32, 46))
		-- the cabin: frame, glowing top bar, glass, ceiling light, the figure, floor bar
		local cabin = shape(button, "Cabin", 0.5, 0.56, 0.56, 0.5, WHITE, 0, 0.08)
		gradient3(cabin, rgb(140, 148, 172), rgb(104, 112, 136), rgb(70, 76, 98))
		ring(cabin, 2, INK)
		local glass = shape(button, "Glass", 0.5, 0.57, 0.42, 0.38, WHITE, 0, 0.04)
		gradient3(glass, rgb(170, 226, 255), rgb(90, 170, 255), rgb(50, 120, 236))
		glass.BackgroundTransparency = 0.05
		shape(button, "Light", 0.5, 0.41, 0.18, 0.025, WHITE, 0, 0.5)
		local body = rgb(206, 238, 255)
		shape(button, "Head", 0.5, 0.49, 0.08, 0.08, body, 0, 0.18)
		shape(button, "Torso", 0.5, 0.6, 0.12, 0.13, body, 0, 0.1)
		shape(button, "ArmL", 0.415, 0.6, 0.045, 0.12, body, 8, 0.3)
		shape(button, "ArmR", 0.585, 0.6, 0.045, 0.12, body, -8, 0.3)
		shape(button, "LegL", 0.475, 0.71, 0.05, 0.09, body, 0, 0.2)
		shape(button, "LegR", 0.525, 0.71, 0.05, 0.09, body, 0, 0.2)
		local top = shape(button, "TopBar", 0.5, 0.32, 0.64, 0.1, WHITE, 0, 0.2)
		gradient3(top, rgb(150, 158, 184), rgb(112, 120, 146), rgb(78, 84, 108))
		ring(top, 2, INK)
		shape(top, "Strip", 0.5, 0.5, 0.62, 0.32, NEON_BRIGHT, 0, 0.5)
		local floorBar = shape(button, "FloorBar", 0.5, 0.82, 0.64, 0.08, WHITE, 0, 0.2)
		gradient3(floorBar, rgb(150, 158, 184), rgb(112, 120, 146), rgb(78, 84, 108))
		ring(floorBar, 2, INK)
		-- up-chevrons on both sides, bottom to top
		for _, x in { 0.135, 0.865 } do
			for row, y in { 0.7, 0.555, 0.41 } do
				local c = chevron(button, x, y, 0.22, 0.15, rgb(200, 245, 255))
				table.insert(chevrons, c)
				table.insert(bases, c.Position)
				table.insert(rows, row)
			end
		end
	end
	local label = UIKit.label(holder, "Elevator", 18, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 16, 0, 22),
		TextColor3 = TEXT,
		TextWrapped = false,
	})
	local labelStroke = label:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Color = rgb(10, 24, 70)
		labelStroke.Thickness = 2.5
	end
	local glyph: ImageLabel = UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, holder)
	return {
		Holder = holder,
		Button = button,
		Scale = scale,
		Chevrons = chevrons,
		ChevronBase = bases,
		ChevronRow = rows,
		Label = label,
		Glyph = glyph,
	}
end

--[[
	The left "SideMenu": its own ScreenGui with a vertical stack at the left
	edge, a little above the middle (clear of the HUD coins at the top and the
	thumbstick at the bottom on phones). Other buttons can join the stack
	(ElevatorController.sideMenu()); LayoutOrder sorts them.
]]
ElevatorView.SideButtonSize = 84
-- the chevrons' idle pulse runs between these colours (opaque: no overlap seams)
ElevatorView.ChevronDim = rgb(70, 140, 230)
ElevatorView.ChevronBright = rgb(200, 245, 255)

function ElevatorView.buildSideMenu(): SideMenu
	local gui = UIKit.screen("TerraForgeSideMenu", 5)
	gui:SetAttribute("TerraForge", true)
	pcall(function()
		-- keep clear of notches and rounded corners on phones
		local insets: any = gui
		insets.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	local menu: Frame = UIKit.new("Frame", {
		Name = "SideMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.46, 0),
		Size = UDim2.fromOffset(ElevatorView.SideButtonSize + 24, 420),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(menu, Enum.FillDirection.Vertical, 14, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local elevator = ElevatorView.iconButton(menu, ElevatorView.SideButtonSize)
	elevator.Holder.LayoutOrder = 10
	return { Gui = gui, Menu = menu, Elevator = elevator }
end

-- The idle "chevrons pulse upward" pose at `phase` (0..1, loops): for previews;
-- the controller runs the same motion with looping tweens.
function ElevatorView.iconPose(icon: IconButton, phase: number)
	for i, c in icon.Chevrons do
		local row = icon.ChevronRow[i]
		-- each row lights up during half the loop, one third later than the row below
		local p = ((phase - (row - 1) / 3) % 1) * 2
		local lift = if p < 1 then math.sin(p * math.pi) else 0
		local base = icon.ChevronBase[i]
		c.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale - 0.03 * lift, base.Y.Offset)
		for _, bar in c:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundColor3 = ElevatorView.ChevronDim:Lerp(ElevatorView.ChevronBright, lift)
			end
		end
	end
end

return ElevatorView
