--[[
	Hoverboards on screen (pure builder + pure helpers; HoverboardController
	fills it in and animates it). The look copies the golem inventory
	(GolemView: the pixel reels, itself like Pet Simulator 99's inventory;
	owner 2026-10-28: the old window "looks old / different", "make it like
	Pet Simulator 99"). One ScreenGui "TerraForgeHoverboards":

	  header   a band in the window's colour (Paint: blue, the side menu's
	           Hover colour) with the lattice and a gleam, "HOVERBOARDS" in
	           white with its 3D shadow, a count chip (boards owned "3 / 5"),
	           the red X
	  grid     one square reel card per board on a dark well (HoverboardData
	           order: 3 on top, the 4th coin board and the Robux board wider
	           under them): the board's paint (CardPaints; the Robux board
	           the rainbow) with the lattice, a turning sunburst behind its
	           big live 3D model (PictureModels "board_<Id>", seen diagonally;
	           drawn from Frames only if the model can't be built), the name
	           in pixel letters on top, "SPEED 31" at the bottom, tilted tags:
	           "E" (equipped) on the left, on the right OWNED, else the price
	           (a coin; grey with a lock when you can't afford it) or ROBUX.
	           The picked card: a thick gold outline and a white ring
	  detail   the picked board as a big reel card: the name, its live 3D
	           model (the controller swings it slowly: turnDetail), a pill
	           COIN BOARD / ROBUX BOARD, chips "SPEED 31" and "+72%", the
	           description and the perks (when there is room), and ONE
	           action button from cardState: BUY with the coin price (yellow,
	           the coin button; grey with a lock when you can't afford it),
	           EQUIP (blue), EQUIPPED (gold, a check, not a gamepad stop),
	           the green Robux price (the robux mark and "49"), COMING SOON
	           (grey, a clock: the pass id is still 0)
	  footer   the control hint (PC, gamepad: its glyph) or the pitch
	           (phones), the last server message in its place for a while
	  ride     the RIDE toggle for the HUD's right menu (rideButton): RIDE /
	           STOP with a key chip ("H") or the gamepad glyph; in the round
	           look the Ride tile of the HUD's grid instead (rideTile, owner
	           2026-10-28: grey like the other tiles), Ride / Stop

	Clicking a card picks it (the detail follows); the detail's button does
	the action (HoverboardController). Faces, fonts and colours come from
	Pop / PopTheme / GolemView only, so a new PopTheme look follows here.
	Designed for 720 design units of height (HudController scales every
	TerraForge gui); the compact layout (phones, uiScale 0.62) has 72-unit
	buttons (about 44 pt) and fits 568 x 320 pt. A gamepad selection stays
	inside the window (SelectionGroup): the cards, the action button, the X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonetizationConfig"))
local HoverboardData = require(Shared.Config.HoverboardData)
local PopTheme = require(Shared.Config.PopTheme)
local PictureModels = require(Shared.Builders.PictureModels)
local IconAssets = require(Shared.Config.IconAssets)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local HudBubble = require(script.Parent.HudBubble)
local GolemView = require(script.Parent.GolemView)
local TechShopView = require(script.Parent.TechShopView)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

local HoverboardView = {}

export type CardState = "Buy" | "BuyLocked" | "Equip" | "Equipped" | "Robux" | "Soon"
export type HintKind = "Mouse" | "Gamepad" | "Touch"

export type Card = {
	Board: HoverboardData.Board,
	Frame: Frame, -- the holder (the layout places it; the drop-in scales it)
	Scale: UIScale,
	Button: TextButton, -- the reel card itself: a click / tap / A picks the board
	Stroke: UIStroke, -- its black edge (gold when picked)
	Pick: Frame, -- the white ring inside the gold outline (picked)
	ArtBack: Frame, -- where the picture sits
	Picture: ImageLabel?, -- the live 3D board (nil: drawn on the Canvas instead)
	Canvas: Frame, -- the board drawn from Frames (only without a model)
	CanvasScale: UIScale,
	Name: TextLabel,
	Line: TextLabel, -- the bottom line: "SPEED 31"
	Equipped: TextLabel, -- the "E" tag
	Tag: TextLabel, -- the right tag: OWNED / the price / ROBUX
	TagCoin: Frame,
	TagLock: Frame,
	TagHeight: number, -- the tags' height on this card (the layout: smaller cards, smaller tags)
	State: CardState,
	Owned: boolean,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame, -- the window (the chrome's black frame; a SelectionGroup)
	Panel: Frame, -- = Root (older callers)
	Pop: UIScale, -- the opening pop (OpenPop)
	Title: TextLabel,
	Count: TextLabel, -- "3 / 5"
	Close: TextButton,
	GridWell: Frame,
	Grid: Frame,
	Cards: { Card },
	Detail: Frame,
	DetailName: TextLabel,
	DetailPicture: ImageLabel, -- the 3D board (Icon attribute: the preview's picture)
	DetailView: ViewportFrame,
	DetailCamera: Camera,
	DetailCanvas: Frame, -- the board drawn from Frames (only without a model)
	DetailCanvasScale: UIScale,
	DetailKind: TextLabel, -- COIN BOARD / ROBUX BOARD
	DetailSpeed: TextLabel, -- SPEED 31
	DetailBonus: TextLabel, -- +72%
	DetailText: TextLabel, -- the description
	DetailPerks: { TextLabel },
	Action: TextButton, -- the one action button (holder "ActionHolder")
	ActionRow: Frame,
	ActionWord: TextLabel,
	ActionAmount: TextLabel,
	ActionIcons: { [string]: GuiObject }, -- Lock, Check, Clock, Coin, Mark
	ActionStyle: string,
	Footer: Frame,
	Hint: TextLabel,
	HintGlyph: ImageLabel,
	HintText: string, -- the last setHint text (phones show the pitch instead)
	HintKind: HintKind, -- the last setHint input kind
	Message: TextLabel,
	Selected: string, -- the board picked by a click ("" = none: the default, equipped else the first)
	Shown: string, -- the board the detail shows (the pick, else the default)
	DetailBoard: string?, -- the board the detail's model shows
	DetailCenter: Vector3,
	DetailDistance: number,
	DetailFrom: Vector3,
	Compact: boolean,
	MaxWidth: number,
	MaxHeight: number,
	PoseTime: number,
}

export type RideButton = {
	Holder: Frame,
	Button: TextButton,
	Scale: UIScale?, -- (the round button's bounce; a tile presses by itself: Pop's "Press")
	Gradient: UIGradient?, -- (the round button's paint)
	Ring: UIStroke?,
	Label: TextLabel,
	Key: TextLabel?, -- (the round button's key chip; a tile wears HudBubble's keycap)
	Glyph: ImageLabel?,
	Tile: boolean, -- the round look's grey tile in the HUD's grid (always shown)
	Riding: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NAVY_DEEP = rgb(10, 14, 32)
local NEON_BRIGHT = rgb(120, 210, 255)
local TEXT = rgb(255, 255, 255)
local INK = rgb(10, 12, 26)

HoverboardView.Title = "HOVERBOARDS"
HoverboardView.Pitch = "Ride anywhere, faster. Bought once, yours forever."
HoverboardView.Paint = "Blue" -- the header band (the side menu's Hover colour)
HoverboardView.OpenTime = 0.42
HoverboardView.CloseTime = 0.2
-- asset ids for the owner's uploaded art ("" = draw it from Frames; only used without a 3D model)
HoverboardView.BoardImages = {} :: { [string]: string }
-- each board's card paint (PopTheme.Paints)
HoverboardView.CardPaints = {
	TimberDrifter = "Orange",
	CartCruiser = "Blue",
	EmberglassGlider = "Red",
	RoyalPhoenix = "Purple",
	TerraForgeCustom = "Pink",
} :: { [string]: string }
-- boards whose cards wear the rainbow (PopTheme.Rainbow) over their paint
HoverboardView.Rainbow = { TerraForgeCustom = true } :: { [string]: boolean }
-- the detail model's slow swing (turnDetail): radians each way, radians a second
HoverboardView.TurnSwing = 0.5
HoverboardView.TurnSpeed = 0.7
-- a picture is this much of its square tall where the board is (boards are flat: the
-- camera frames the board's bounding sphere, the board fills about half of it)
HoverboardView.BoardHeight = 0.5

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Footer: number,
	Button: number,
	Close: number,
	Detail: number, -- the detail column's width
	Title: number,
	Text: number,
	Small: number,
	Tag: number, -- a card tag's height
	Pill: number, -- the detail's pill and chips
	NameFloor: number, -- a card name below this goes on two lines
	MinPicture: number, -- the detail's picture row never shrinks under this (it drops the texts first)
	MaxPicture: number,
}

local PAD = 16
local GAP = 10
local CELL_GAP = 8
local INSET = 6 -- the cards inside their well (the picked card's gold outline shows)
local CARD_TITLE = 26 -- a card's name row (one line)
local CARD_LINE = 22 -- a card's bottom line

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 940,
		Height = 560,
		Header = 70,
		Footer = 30,
		Button = 52,
		Close = 54,
		Detail = 320,
		Title = 32,
		Text = 18,
		Small = 15,
		Tag = 24,
		Pill = 28,
		NameFloor = 13,
		MinPicture = 96,
		MaxPicture = 176,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1180,
		Height = 600,
		Header = 84,
		Footer = 30,
		Button = 72,
		Close = 72,
		Detail = 340,
		Title = 34,
		Text = 20,
		Small = 17,
		Tag = 28,
		Pill = 32,
		NameFloor = 15,
		MinPicture = 104,
		MaxPicture = 176,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- Are Robux purchases switched on? (the receipts gate, src/server/Receipts.luau, publishes
-- MonetizationConfig.ReceiptsAttribute; until then every Robux card says COMING SOON).
-- Swappable for the Lune tests.
function HoverboardView.receiptsReady(): boolean
	return ReplicatedStorage:GetAttribute(MonetizationConfig.ReceiptsAttribute) == true
end

-- What a board's card offers: owned / equipped, else buy (coins) or Robux.
function HoverboardView.cardState(board: HoverboardData.Board, owned: { [string]: boolean }, equipped: string, coins: any): CardState
	local state: CardState = "BuyLocked"
	if owned[board.Id] then
		state = if equipped == board.Id then "Equipped" else "Equip"
	elseif board.Kind == "Robux" then
		state = if HoverboardData.canPrompt(board) and HoverboardView.receiptsReady() then "Robux" else "Soon"
	else
		local have = if type(coins) == "number" and coins == coins then coins else 0
		if have >= (board.Price or math.huge) then
			state = "Buy"
		end
	end
	return state
end

function HoverboardView.priceText(board: HoverboardData.Board): string
	if board.Kind == "Robux" then
		return `{board.Robux or HoverboardData.RobuxPrice} R$`
	end
	return Format.money(board.Price or 0)
end

function HoverboardView.speedText(board: HoverboardData.Board): string
	return `SPEED {board.Speed}`
end

function HoverboardView.bonusText(board: HoverboardData.Board): string
	return `+{HoverboardData.speedBonus(board)}%`
end

-- The action button's word (BUY's price is a second word: amountText).
function HoverboardView.buttonText(state: CardState, board: HoverboardData.Board): string
	if state == "Buy" or state == "BuyLocked" then
		return "BUY"
	elseif state == "Equip" then
		return "EQUIP"
	elseif state == "Equipped" then
		return "EQUIPPED"
	elseif state == "Robux" then
		return tostring(board.Robux or HoverboardData.RobuxPrice)
	end
	return "COMING SOON"
end

-- The action button's second word: a coin board's price on BUY ("" otherwise).
function HoverboardView.amountText(state: CardState, board: HoverboardData.Board): string
	if state == "Buy" or state == "BuyLocked" then
		return Format.money(board.Price or 0)
	end
	return ""
end

-- The detail's pill: what kind of board it is.
function HoverboardView.kindText(board: HoverboardData.Board): string
	return if board.Kind == "Robux" then "ROBUX BOARD" else "COIN BOARD"
end

-- A card's right tag: OWNED, else what it costs (a coin board's price, ROBUX).
function HoverboardView.tagText(board: HoverboardData.Board, owned: boolean): string
	if owned then
		return "OWNED"
	elseif board.Kind == "Robux" then
		return "ROBUX"
	end
	return Format.money(board.Price or 0)
end

-- The owned list of a State snapshot ({ Owned = { id... } }) as a set.
function HoverboardView.ownedSet(list: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(list) == "table" then
		for _, id in list do
			if type(id) == "string" and HoverboardData.get(id) then
				set[id] = true
			end
		end
	end
	return set
end

-- "3 / 5": the boards you own of all of them.
function HoverboardView.countText(owned: { [string]: boolean }): string
	local n = 0
	for _, board in HoverboardData.List do
		if owned[board.Id] then
			n += 1
		end
	end
	return `{n} / {#HoverboardData.List}`
end

-- The board the detail shows first: the equipped one, else the first board.
function HoverboardView.defaultBoard(equipped: string): string
	local board = HoverboardData.get(equipped)
	return if board then board.Id else HoverboardData.List[1].Id
end

-- A board's card paint.
function HoverboardView.cardPaint(board: HoverboardData.Board): Pop.Paint
	return Pop.paint(HoverboardView.CardPaints[board.Id] or "Slate")
end

--[[
	Where the cards go in a well `w` x `h` design units (inside it, INSET from
	its edge): three on top, the rest (two) under them, widened to fill the
	row. Returns { x, y, w, h } per card in board order.
]]
function HoverboardView.cells(w: number, h: number, count: number?): { { number } }
	local n = count or #HoverboardData.List
	local top = math.min(3, n)
	local rows = if n > top then 2 else 1
	local innerW = w - INSET * 2
	local innerH = h - INSET * 2
	local rowH = math.floor((innerH - CELL_GAP * (rows - 1)) / rows)
	local out: { { number } } = {}
	for row = 1, rows do
		local first = if row == 1 then 1 else top + 1
		local last = if row == 1 then top else n
		local inRow = last - first + 1
		local cellW = math.floor((innerW - CELL_GAP * (inRow - 1)) / inRow)
		for i = first, last do
			local column = i - first
			table.insert(out, { INSET + column * (cellW + CELL_GAP), INSET + (row - 1) * (rowH + CELL_GAP), cellW, rowH })
		end
	end
	return out
end

---------------------------------------------------------------- drawing kit (the stand-in without a 3D model)

-- A frame at offset (x, y) (top-left) in a canvas, w x h, rotated `rot`, `corner` in offset.
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

-- A frame centred at (cx, cy) (offset) in a canvas.
local function centred(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	w: number,
	h: number,
	color: Color3,
	rot: number?,
	round: boolean?
): Frame
	local frame = block(parent, name, cx - w / 2, cy - h / 2, w, h, color, rot)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	end
	return frame
end

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

-- The soft hover glow under a board (a wide pale ellipse and a bright core).
local function hoverGlow(c: Frame, color: Color3, x: number, w: number)
	local soft = centred(c, "Glow", x, 88, w + 30, 18, color, 0, true)
	soft.BackgroundTransparency = 0.72
	local core = centred(c, "GlowCore", x, 84, w * 0.8, 6, color:Lerp(WHITE, 0.25), 0, true)
	core.BackgroundTransparency = 0.15
end

-- A deck seen from the side with its lit top face: a bar plus a lighter strip.
local function deck(c: Frame, x: number, y: number, w: number, h: number, color: Color3, round: number?)
	local body = block(c, "Deck", x, y, w, h, WHITE, 0, round)
	gradient3(body, color:Lerp(WHITE, 0.18), color, color:Lerp(BLACK, 0.3))
	ring(body, 2, INK, 0.2)
	local top = block(c, "DeckTop", x + 3, y - 4, w - 6, 5, color:Lerp(WHITE, 0.35), 0, round and math.min(round, 3) or nil)
	return body, top
end

local function crystal(c: Frame, cx: number, bottom: number, w: number, h: number, rot: number, color: Color3)
	local holder: Frame = UIKit.new("Frame", {
		Name = "Crystal",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(cx, bottom),
		Size = UDim2.fromOffset(w, h + w / 2),
		BackgroundTransparency = 1,
		Rotation = rot,
	}, c)
	local side = w / math.sqrt(2)
	block(holder, "Tip", (w - side) / 2, w / 2 - side / 2, side, side, color:Lerp(WHITE, 0.4), 45)
	local body = block(holder, "Body", 0, w / 2, w, h, WHITE)
	UIKit.new("UIGradient", { Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.2)), Rotation = 0 }, body)
end

-- Side views of the boards on a 200 x 110 canvas (nose to the left).
local ART: { [string]: (Frame, HoverboardData.Colors) -> () } = {
	TimberDrifter = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 100, 120)
		for _, x in { 66, 134 } do
			centred(c, "Pad", x, 72, 34, 10, col.Accent, 0, true)
			centred(c, "PadGlow", x, 78, 24, 4, col.Glow, 0, true)
		end
		centred(c, "Can", 150, 66, 30, 9, col.Trim, 0, true)
		local wood = col.Main
		deck(c, 50, 52, 100, 12, wood, 2)
		block(c, "KickNose", 24, 46, 32, 12, wood:Lerp(BLACK, 0.06), -24, 2)
		block(c, "KickTail", 144, 46, 32, 12, wood:Lerp(BLACK, 0.06), 24, 2)
		block(c, "Grain", 62, 57, 74, 2, wood:Lerp(BLACK, 0.35))
		for _, x in { 54, 140 } do
			block(c, "Strap", x, 48, 8, 18, col.Accent, 0, 2)
			centred(c, "Bolt", x + 4, 52, 6, 6, col.Trim, 0, true)
		end
	end,
	CartCruiser = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 100, 110)
		block(c, "Base", 62, 60, 76, 8, col.Main:Lerp(BLACK, 0.3), 0, 3)
		local tub = block(c, "Tub", 50, 36, 100, 26, WHITE, 0, 3)
		gradient3(tub, col.Main:Lerp(WHITE, 0.25), col.Main, col.Main:Lerp(BLACK, 0.25))
		ring(tub, 2, INK, 0.2)
		block(c, "WallNose", 40, 34, 14, 24, col.Main:Lerp(WHITE, 0.1), -16, 2)
		block(c, "WallTail", 146, 34, 14, 24, col.Main:Lerp(WHITE, 0.1), 16, 2)
		block(c, "Lip", 38, 28, 124, 7, col.Trim, 0, 3)
		for _, x in { 68, 100, 132 } do
			centred(c, "Rivet", x, 44, 5, 5, rgb(226, 178, 78), 0, true)
		end
		block(c, "Vent", 84, 50, 32, 4, col.Glow, 0, 2)
		for _, x in { 70, 130 } do
			local wheel = centred(c, "Wheel", x, 68, 24, 24, col.Accent, 0, true)
			ring(wheel, 2, INK, 0.2)
			centred(c, "Hub", x, 68, 9, 9, col.Glow, 0, true)
		end
		centred(c, "Lamp", 44, 48, 9, 9, col.Glow2, 0, true)
	end,
	EmberglassGlider = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 100, 120)
		block(c, "Basalt", 46, 60, 108, 9, col.Trim, 0, 4)
		block(c, "LavaSeam", 40, 57, 120, 4, col.Glow, 0, 2)
		deck(c, 38, 46, 124, 11, col.Main, 6)
		block(c, "Crack", 70, 50, 60, 2, col.Glow)
		for i, spec in { { 46, 18, -34 }, { 54, 24, -20 }, { 62, 16, -6 } } do
			crystal(c, spec[1], 48, 9, spec[2], spec[3], col.Accent:Lerp(BLACK, 0.06 * i))
		end
		for i, spec in { { 138, 16, 6 }, { 146, 26, 22 }, { 154, 18, 36 } } do
			crystal(c, spec[1], 48, 9, spec[2], spec[3], col.Accent:Lerp(BLACK, 0.06 * i))
		end
	end,
	TerraForgeCustom = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 100, 120)
		block(c, "Rim", 34, 58, 132, 6, col.Glow2, 0, 3)
		local body, top = deck(c, 30, 44, 140, 14, col.Main, 7)
		ring(body, 3, col.Trim, 0)
		top.BackgroundColor3 = col.Main
		-- doodle stickers in bright marker colours along the deck
		local doodles: { Color3 } =
			{ rgb(96, 214, 80), rgb(255, 150, 40), rgb(70, 160, 255), rgb(196, 90, 255), col.Accent, rgb(255, 80, 90) }
		for i, color in doodles do
			local dot = centred(c, "Doodle", 26 + i * 22, 50 + (i % 2) * 2, 15, 11, color, (i * 23) % 40 - 20, true)
			ring(dot, 2, col.Trim, 0)
		end
	end,
	RoyalPhoenix = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 104, 120)
		local gold = col.Trim
		-- wings: feather blades sweeping back and up, flame tips
		for i, spec in { { 84, -36, 64 }, { 94, -28, 56 }, { 104, -20, 48 } } do
			local blade = block(c, "Wing", spec[1], 36 - i * 2, spec[3], 8, if i == 2 then col.Main:Lerp(WHITE, 0.25) else gold, spec[2], 3)
			blade.AnchorPoint = Vector2.new(0, 0.5)
			local tip = block(
				c,
				"WingTip",
				spec[1] + spec[3] * math.cos(math.rad(spec[2])) - 4,
				36 - i * 2 + spec[3] * math.sin(math.rad(spec[2])) - 4,
				10,
				8,
				col.Accent,
				spec[2],
				3
			)
			tip.AnchorPoint = Vector2.new(0, 0.5)
		end
		for i, rot in { -14, -4, 8 } do
			local tail = block(c, "Tail", 150, 50 + i, 42, 7, if i == 2 then col.Main:Lerp(WHITE, 0.2) else gold, rot, 3)
			tail.AnchorPoint = Vector2.new(0, 0.5)
		end
		block(c, "Rim", 42, 60, 118, 4, gold, 0, 2)
		deck(c, 44, 48, 114, 12, col.Main, 6)
		block(c, "Gem", 96, 44, 8, 8, col.Glow, 45)
		-- neck curving up from the nose, a sleek head with a long beak, crest feathers
		block(c, "Neck", 48, 30, 7, 22, gold, -10, 3)
		block(c, "Neck2", 44, 16, 6, 18, gold, 8, 3)
		block(c, "Head", 36, 10, 16, 10, gold, 0, 3)
		block(c, "Beak", 12, 13, 26, 4, gold:Lerp(col.Accent, 0.5), -4, 2)
		centred(c, "Eye", 41, 14, 4, 4, col.Glow, 0, true)
		for i, rot in { -40, -22, -6 } do
			local crest = block(c, "Crest", 50, 13 - i, 22, 4, if i == 2 then col.Accent else gold, rot, 2)
			crest.AnchorPoint = Vector2.new(0, 0.5)
		end
	end,
}

-- Draws a board's side view into a 200 x 110 canvas (or the owner's image).
function HoverboardView.drawBoard(canvas: Frame, board: HoverboardData.Board)
	local image = HoverboardView.BoardImages[board.Id]
	if image and image ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		}, canvas)
		return
	end
	local draw = ART[board.Id]
	if draw then
		draw(canvas, board.Colors)
	end
end

---------------------------------------------------------------- icons

local function iconBox(parent: Instance, name: string): Frame
	return UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
	}, parent)
end

local function ink(parent: Instance, cx: number, cy: number, w: number, h: number, color: Color3, rot: number?, round: number?): Frame
	local frame: Frame = UIKit.new("Frame", {
		Name = "Ink",
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

local Icons = {}

-- a check mark (EQUIPPED)
function Icons.check(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Check")
	ink(box, 0.34, 0.62, 0.42, 0.18, color, 45, 0.5)
	ink(box, 0.62, 0.48, 0.66, 0.18, color, -50, 0.5)
	return box
end

-- a padlock (not enough coins)
function Icons.lock(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Lock")
	local shackle = ink(box, 0.5, 0.34, 0.5, 0.52, color, 0, 0.5)
	shackle.BackgroundTransparency = 1
	shackle.Name = "Shackle"
	UIKit.stroke(shackle, 2.5, color)
	ink(box, 0.5, 0.68, 0.76, 0.5, color, 0, 0.16)
	return box
end

-- a clock (COMING SOON)
function Icons.clock(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Clock")
	local face = ink(box, 0.5, 0.5, 0.84, 0.84, color, 0, 0.5)
	face.BackgroundTransparency = 1
	face.Name = "Face"
	UIKit.stroke(face, 2.5, color)
	ink(box, 0.5, 0.36, 0.11, 0.32, color, 0, 0.5)
	ink(box, 0.62, 0.52, 0.3, 0.11, color, 20, 0.5)
	return box
end

-- a tiny board (the RIDE button)
function Icons.board(parent: Instance, color: Color3, glowColor: Color3): Frame
	local box = iconBox(parent, "BoardIcon")
	local glowBar = ink(box, 0.5, 0.82, 0.86, 0.14, glowColor, 0, 0.5)
	glowBar.Name = "Glow"
	glowBar.BackgroundTransparency = 0.25
	ink(box, 0.5, 0.56, 0.78, 0.22, color, 0, 0.5)
	ink(box, 0.14, 0.46, 0.22, 0.18, color, -28, 0.5)
	ink(box, 0.86, 0.46, 0.22, 0.18, color, 28, 0.5)
	for i = 1, 3 do
		local line = ink(box, 0.08 + 0.02 * i, 0.12 + 0.12 * i, 0.3, 0.07, color, 0, 0.5)
		line.Name = "Speed"
		line.BackgroundTransparency = 0.35
	end
	return box
end

---------------------------------------------------------------- the reel pieces (GolemView's look)
--[[
	The golem inventory's pixel reels, rebuilt here from the shared kit
	(GolemView's own reel helpers are local to it): short words in the pixel
	font shrink to fit their box, sentences stay round; a reel card is a
	paint with its lip, the light edge, the lattice and a turning sunburst
	with a soft glow behind its picture.
]]

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- A short word in the pixel font, shrunk to fit its box (Pop.fit).
local function pixel(label: TextLabel | TextButton, size: number)
	local l: any = label
	l.FontFace = PopTheme.Pixel
	l.TextWrapped = false
	Pop.fit(l, size)
end

-- A pixel word sized to leave a margin inside `width` (and at most `size`).
local function fitWord(label: TextLabel | TextButton, size: number, width: number)
	local l: any = label
	local s = size
	while s > 10 and Pop.textWidth(l.Text, s) > width - 12 do
		s -= 1
	end
	Pop.fit(l, s)
end

-- A sentence in the round font at `size` (round for good: Pop.round), still cut, never spilled.
local function round(label: TextLabel, size: number)
	local cut = label.TextTruncate
	Pop.round(label, size)
	label.TextTruncate = cut
end

-- A pixel name at `size` on `lines` lines (TextScaled under a cap: never bigger than `size`).
local function setName(label: TextLabel, size: number, lines: number)
	label.FontFace = PopTheme.Pixel
	label.TextWrapped = lines > 1
	label.TextScaled = true
	label.TextSize = size
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label:SetAttribute("NameLines", lines)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	l.MinTextSize = 1
	l.MaxTextSize = size
	l.MinTextSize = math.min(size, PopTheme.PixelMin)
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.LineJoinMode = Enum.LineJoinMode.Miter
	end
end

-- Keeps a pixel word off a face's lip and its sides.
local function padWord(object: GuiObject, left: number, right: number, lip: number)
	local pad = object:FindFirstChildOfClass("UIPadding") or UIKit.new("UIPadding", {}, object)
	local p = pad :: UIPadding
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingTop = UDim.new(0, 2)
	p.PaddingBottom = UDim.new(0, lip)
end

-- A Pop button (GolemView.popButton) with a pixel word, a gleam and the press bounce.
local function reelButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local button = GolemView.popButton(parent, text, paint, props)
	button:SetAttribute("WordSize", button.TextSize)
	pixel(button, button.TextSize)
	padWord(button, 6, 6, 6)
	local holder = holderOf(button)
	Pop.gleam(holder, 2)
	Pop.fxTag(holder, "Press")
	return button
end

-- A small tag with a pixel word (E, OWNED, the price, the count).
local function reelTag(parent: Instance, text: string, color: Color3, size: Vector2, props: { [string]: any }?): TextLabel
	local chip = GolemView.solidChip(parent, text, color, size, props)
	pixel(chip, math.floor(size.Y * 0.8))
	padWord(chip, 5, 5, 2)
	return chip
end

--[[
	Paints `frame` as a reel card: the paint with its lip and light edge, the
	lattice, and the sunburst (Pop.rays, turning) with a soft glow behind
	`centre` (inside the lattice's clip). The frame's Size must be set first.
]]
local function reelFace(frame: GuiObject, paint: string | Pop.Paint, corner: number, centre: UDim2, reach: number)
	Pop.face(frame, paint, corner)
	local clip = Pop.studs(frame, corner, 0.45, 30, 2) :: Frame
	Pop.rays(clip, centre, 8, reach, GolemView.RayFade, 2)
	local short = math.min(frame.Size.X.Offset, frame.Size.Y.Offset, 220)
	for i, k in { 0.7, 0.46 } do
		local disc = UIKit.new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = if i == 1 then 0.82 else 0.72,
			BorderSizePixel = 0,
			Position = centre,
			Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
			ZIndex = 2,
		}, clip)
		UIKit.corner(disc, 999)
	end
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
end

-- Moves a reel card's sunburst and glow to `centre` (its picture moved).
local function aimReel(frame: Instance, centre: UDim2)
	local clip = frame:FindFirstChild("Lattice")
	if not clip then
		return
	end
	-- (the clip sits 3 units inside the card)
	local at = centre - UDim2.fromOffset(3, 3)
	for _, name in { "Rays", "Glow1", "Glow2" } do
		local piece = clip:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Position = at
		end
	end
end

-- The window's header band in the reels' look: the lattice and a gleam (no shine stripes).
local function reelBand(panel: Frame)
	local band = panel:FindFirstChild("Band")
	if not band or not band:IsA("Frame") then
		return
	end
	for _, child in band:GetChildren() do
		if child.Name == "Shine" or string.sub(child.Name, 1, 6) == "Stripe" then
			child:Destroy()
		end
	end
	Pop.gleam(band, 3)
end

--[[
	A board's reel paint on a face `h` units tall: its paint with the lip, or
	the rainbow (HoverboardView.Rainbow; no lip: it runs left to right).
]]
local function paintBoard(frame: GuiObject, board: HoverboardData.Board, h: number)
	if h > 0 then
		frame:SetAttribute("Lip", Pop.lipUnits(h) / h)
	end
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		gradient.Rotation = 90
	end
	Pop.repaint(frame, HoverboardView.cardPaint(board))
	if HoverboardView.Rainbow[board.Id] then
		Pop.rainbow(frame)
	end
end

-- The bounds (centre, radius) of every part in a model (Pop.show frames the same sphere).
local function boundsOf(model: Instance): (Vector3, number)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local half = part.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local at = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
						hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
					end
				end
			end
		end
	end
	if lo.X > hi.X then
		return Vector3.zero, 1
	end
	return (lo + hi) * 0.5, math.max(0.5, (hi - lo).Magnitude * 0.5)
end

---------------------------------------------------------------- the action button

type ActionStyle = {
	Paint: Pop.Paint,
	Icon: string?, -- Lock / Check / Clock / Coin / Mark (the robux mark)
	Coin: boolean, -- the coin before the price
}

local function actionStyle(paint: Pop.Paint, icon: string?, coin: boolean?): ActionStyle
	return { Paint = paint, Icon = icon, Coin = coin == true }
end

local STYLES: { [string]: ActionStyle } = {
	Buy = actionStyle(Pop.paint("Yellow"), nil, true), -- the coin button (Pop.coinButton's yellow)
	BuyLocked = actionStyle(PopTheme.Gray, "Lock", true),
	Equip = actionStyle(Pop.paint("Blue")),
	Equipped = actionStyle(Pop.paint("Yellow"), "Check"),
	Robux = actionStyle(PopTheme.Price, "Mark"), -- the green Pop.price: the robux mark and "49"
	Soon = actionStyle(PopTheme.Gray, "Clock"),
}
HoverboardView.ButtonStyles = STYLES

local function newAction(parent: Instance): (TextButton, Frame, TextLabel, TextLabel, { [string]: GuiObject })
	local button = reelButton(parent, "", "Yellow", { Name = "Action", TextSize = 22, ZIndex = 6 })
	button.Text = ""
	-- (the row below sits above the lip itself: no word padding)
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad:Destroy()
	end
	local row: Frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local icons: { [string]: GuiObject } = {}
	icons.Lock = Icons.lock(row, WHITE)
	icons.Check = Icons.check(row, WHITE)
	icons.Clock = Icons.clock(row, WHITE)
	local mark: ImageLabel = UIKit.new("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 6,
	}, row)
	IconAssets.apply(mark, "robux")
	mark:SetAttribute("Icon", "robux")
	icons.Mark = mark
	for i, name in { "Lock", "Check", "Clock", "Mark" } do
		local icon = icons[name]
		icon.LayoutOrder = i
		icon.Visible = false
		icon.ZIndex = 6
	end
	local word = GolemView.text(row, "BUY", 22, { Name = "Word", LayoutOrder = 10, ZIndex = 6 })
	local coin = Pop.coin(row, 24, { LayoutOrder = 11, Visible = false })
	icons.Coin = coin
	local amount = GolemView.text(row, "", 22, { Name = "Amount", LayoutOrder = 12, ZIndex = 6 })
	return button, row, word, amount, icons
end

-- Sizes the action button's row (the icon, the word, the price) for its holder.
local function fitAction(refs: Refs)
	local holder = holderOf(refs.Action)
	local w, h = holder.Size.X.Offset, holder.Size.Y.Offset
	local lip = Pop.lipUnits(h)
	refs.ActionRow.Size = UDim2.new(1, 0, 1, -lip)
	local style = STYLES[refs.ActionStyle] or STYLES.Equip
	local hasAmount = refs.ActionAmount.Text ~= ""
	local function width(size: number): number
		local letter = math.floor(size * PopTheme.PixelScale + 0.5)
		local sum = Pop.textWidth(refs.ActionWord.Text, size)
		local items = 1
		if style.Icon then
			sum += math.floor(letter * 1.25) + 4
			items += 1
		end
		if style.Coin and hasAmount then
			sum += math.floor(letter * 1.25) + 4 + Pop.textWidth(refs.ActionAmount.Text, size)
			items += 2
		end
		return sum + 6 * (items - 1)
	end
	local size = math.floor((h - lip) * 0.58)
	while size > 12 and width(size) > w - 24 do
		size -= 1
	end
	local letter = math.floor(size * PopTheme.PixelScale + 0.5)
	for name, icon in refs.ActionIcons do
		-- (the coin and the robux mark are round: a bit bigger than a letter)
		local side = if name == "Coin" or name == "Mark" then math.floor(letter * 1.25) + 4 else letter + 4
		icon.Size = UDim2.fromOffset(side, side)
		icon.Visible = name == style.Icon or (name == "Coin" and style.Coin and hasAmount)
	end
	for _, label in { refs.ActionWord, refs.ActionAmount } do
		label.Visible = label.Text ~= ""
		label.Size = UDim2.fromOffset(Pop.textWidth(label.Text, size), h - lip)
		Pop.fit(label, size)
	end
end

---------------------------------------------------------------- building

-- the size a card is built at (the layout resizes it; the sunburst's reach covers the widest card)
local CARD_BUILD = Vector2.new(184, 212)
local CARD_REACH = 300

local function newCard(grid: Frame, board: HoverboardData.Board): Card
	local frame: Frame = UIKit.new("Frame", {
		Name = board.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		LayoutOrder = board.Order,
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
		ZIndex = 4,
	}, grid)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
	local button: TextButton = UIKit.new("TextButton", {
		Name = "Card",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Selectable = true,
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
		Text = "",
		ZIndex = 2,
	}, frame)
	reelFace(button, HoverboardView.cardPaint(board), GolemView.CardCorner, UDim2.fromScale(0.5, 0.5), CARD_REACH)
	button.Size = UDim2.fromScale(1, 1)
	paintBoard(button, board, CARD_BUILD.Y)
	Pop.fxTag(button, "Press")
	local stroke = button:FindFirstChild("Border") :: UIStroke
	-- the board: its live 3D model (bigger than its spot: the board is flat), else drawn from Frames
	local artBack: Frame = UIKit.new("Frame", {
		Name = "ArtBack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, button)
	local model, from = PictureModels.build("board_" .. board.Id)
	local picture: ImageLabel? = nil
	if model then
		picture = Pop.model(artBack, "board_" .. board.Id, 160, model, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, from)
		Pop.fxTag(picture :: ImageLabel, "Lean")
	end
	local canvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 110),
		ZIndex = 4,
	}, button)
	local canvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, canvas)
	if not picture then
		HoverboardView.drawBoard(canvas, board)
	end
	local name = GolemView.text(button, string.upper(board.Name), 20, {
		Name = "BoardName",
		Position = UDim2.fromOffset(5, 5),
		ZIndex = 6,
	})
	local line = GolemView.text(button, HoverboardView.speedText(board), 17, {
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = GolemView.BonusColor,
		ZIndex = 6,
	})
	-- tilted tags beside the picture (the reels' price tags): E on the left, OWNED / the price / ROBUX on the right
	local equipped = reelTag(button, "E", Pop.paint("Green").Bottom, Vector2.new(30, 26), {
		Name = "EquippedBadge",
		Rotation = -10,
		Visible = false,
		ZIndex = 7,
	})
	local tag = reelTag(button, "", GolemView.ChipDark, Vector2.new(80, 24), {
		Name = "Tag",
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 10,
		ZIndex = 7,
	})
	local tagCoin = Pop.coin(tag, 18, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Visible = false,
		ZIndex = 8,
	})
	local tagLock = Icons.lock(tag, WHITE)
	tagLock.AnchorPoint = Vector2.new(0, 0.5)
	tagLock.Position = UDim2.new(0, 5, 0.5, 0)
	tagLock.Visible = false
	tagLock.ZIndex = 8
	for _, piece in tagLock:GetChildren() do
		if piece:IsA("GuiObject") then
			piece.ZIndex = 8
		end
	end
	-- the picked card: a white ring inside the gold outline
	local pick: Frame = UIKit.new("Frame", {
		Name = "Pick",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Visible = false,
		ZIndex = 7,
	}, button)
	UIKit.corner(pick, GolemView.CardCorner - 4)
	UIKit.new("UIStroke", {
		Name = "Ring",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = GolemView.PickColor,
		Thickness = 3,
	}, pick)
	return {
		Board = board,
		Frame = frame,
		Scale = scale,
		Button = button,
		Stroke = stroke,
		Pick = pick,
		ArtBack = artBack,
		Picture = picture,
		Canvas = canvas,
		CanvasScale = canvasScale,
		Name = name,
		Line = line,
		Equipped = equipped,
		Tag = tag,
		TagCoin = tagCoin,
		TagLock = tagLock,
		TagHeight = 24,
		State = "BuyLocked",
		Owned = false,
	}
end

function HoverboardView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local gui = UIKit.screen("TerraForgeHoverboards", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look: never the LightSkin (it would recolour the faces)
	local root: Frame = UIKit.new("Frame", {
		Name = "Root",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local pop: UIScale = UIKit.new("UIScale", { Name = "OpenPop", Scale = 1 }, root)
	-- the chrome: the band in the window's colour (lattice, gleam), the title with its shadow
	local title = GolemView.chrome(root, HoverboardView.Title, HoverboardView.Paint)
	reelBand(root)
	local count = reelTag(root, "0 / 5", GolemView.ChipDark, Vector2.new(96, 30), {
		Name = "Count",
		ZIndex = 6,
	})
	local close = reelButton(root, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		FontFace = PopTheme.Heavy,
		TextSize = 34,
		ZIndex = 6,
	})

	-- the grid: a reel card per board on a dark studded well
	local gridWell = Pop.well(root, { Name = "GridWell", ZIndex = 3 })
	local grid: Frame = UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, root)
	local cards: { Card } = {}
	for _, board in HoverboardData.List do
		table.insert(cards, newCard(grid, board))
	end

	-- the detail: a big reel card of the picked board
	local detail: Frame = UIKit.new("Frame", {
		Name = "Detail",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(m.Detail, 420),
		ZIndex = 3,
	}, root)
	reelFace(detail, HoverboardView.cardPaint(HoverboardData.List[1]), GolemView.CardCorner, UDim2.new(0.5, 0, 0, 120), 420)
	local detailName = GolemView.text(detail, "", m.Text + 10, {
		Name = "BoardName",
		ZIndex = 6,
	})
	local detailPicture = Pop.model(detail, "board_" .. HoverboardData.List[1].Id, 200, nil, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 4,
	})
	Pop.fxTag(detailPicture, "Lean")
	local detailView = detailPicture:FindFirstChild("View") :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = detailView
	pcall(function()
		detailView.CurrentCamera = camera
	end)
	local detailCanvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 110),
		Visible = false,
		ZIndex = 4,
	}, detail)
	local detailCanvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, detailCanvas)
	local detailKind = reelTag(detail, "COIN BOARD", GolemView.ChipDark, Vector2.new(170, m.Pill), {
		Name = "Kind",
		AnchorPoint = Vector2.new(0.5, 0),
	})
	local detailSpeed = reelTag(detail, "SPEED 0", GolemView.ChipDark, Vector2.new(130, m.Pill), {
		Name = "Speed",
	})
	local detailBonus = reelTag(detail, "+0%", GolemView.ChipDark, Vector2.new(80, m.Pill), {
		Name = "Bonus",
		TextColor3 = GolemView.BonusColor,
	})
	local detailText = GolemView.text(detail, "", m.Small - 1, {
		Name = "Description",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.5,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	round(detailText, m.Small - 1)
	UIKit.corner(detailText, 8)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, detailText)
	local perks: { TextLabel } = {}
	for i = 1, 3 do
		table.insert(
			perks,
			GolemView.text(detail, "", m.Small + 1, {
				Name = "Perk" .. i,
				TextColor3 = GolemView.BonusColor,
				Visible = false,
				ZIndex = 6,
			})
		)
	end
	local action, actionRow, actionWord, actionAmount, actionIcons = newAction(detail)

	-- the footer: the control hint (with the gamepad's glyph) or the pitch; the server's message
	local footer: Frame = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, root)
	UIKit.list(footer, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local glyph: ImageLabel = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		ZIndex = 5,
	}, footer)
	local hint = GolemView.text(footer, "", m.Small, {
		Name = "Hint",
		LayoutOrder = 2,
		TextColor3 = PopTheme.Ink:Lerp(PopTheme.Body, 0.22),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	round(hint, m.Small)
	local message = GolemView.text(root, "", m.Small, {
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 1),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		ZIndex = 5,
	})
	round(message, m.Small)

	local refs: Refs = {
		Gui = gui,
		Root = root,
		Panel = root,
		Pop = pop,
		Title = title,
		Count = count,
		Close = close,
		GridWell = gridWell,
		Grid = grid,
		Cards = cards,
		Detail = detail,
		DetailName = detailName,
		DetailPicture = detailPicture,
		DetailView = detailView,
		DetailCamera = camera,
		DetailCanvas = detailCanvas,
		DetailCanvasScale = detailCanvasScale,
		DetailKind = detailKind,
		DetailSpeed = detailSpeed,
		DetailBonus = detailBonus,
		DetailText = detailText,
		DetailPerks = perks,
		Action = action,
		ActionRow = actionRow,
		ActionWord = actionWord,
		ActionAmount = actionAmount,
		ActionIcons = actionIcons,
		ActionStyle = "",
		Footer = footer,
		Hint = hint,
		HintGlyph = glyph,
		HintText = "",
		HintKind = "Mouse",
		Message = message,
		Selected = "",
		Shown = "",
		DetailBoard = nil,
		DetailCenter = Vector3.zero,
		DetailDistance = 10,
		DetailFrom = Vector3.new(-1, 0.75, -0.7).Unit,
		Compact = isCompact,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
		PoseTime = HoverboardView.OpenTime,
	}
	HoverboardView.layout(refs, isCompact, math.huge, math.huge)
	HoverboardView.setCards(refs, {}, "", 0)
	HoverboardView.setHint(refs, "Mouse", "Click a board to see it · H: ride · Backspace: close")
	-- like every window: Roblox's touch controls hide while it is open
	TouchControls.follow(gui)
	return refs
end

---------------------------------------------------------------- the detail's 3D board

-- Points the detail's camera at its board, turned `yaw` radians round it.
local function aimCamera(refs: Refs, yaw: number)
	local turned = CFrame.Angles(0, yaw, 0) * refs.DetailFrom
	local at = refs.DetailCenter + turned * refs.DetailDistance
	refs.DetailCamera.CFrame = CFrame.lookAt(at, refs.DetailCenter)
end

-- Shows `board` in the detail's picture (its live model; drawn from Frames without one).
local function showDetailBoard(refs: Refs, board: HoverboardData.Board)
	if refs.DetailBoard == board.Id then
		return
	end
	refs.DetailBoard = board.Id
	for _, child in refs.DetailView:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	refs.DetailCanvas:ClearAllChildren()
	refs.DetailCanvasScale = UIKit.new("UIScale", { Scale = 1 }, refs.DetailCanvas)
	refs.DetailPicture:SetAttribute("Icon", "board_" .. board.Id)
	local model, from = PictureModels.build("board_" .. board.Id)
	if model then
		model.Parent = refs.DetailView
		local centre, radius = boundsOf(model)
		refs.DetailCenter = centre
		refs.DetailDistance = radius / math.sin(math.rad(15)) * 0.95
		refs.DetailFrom = from.Unit
		aimCamera(refs, 0)
	else
		HoverboardView.drawBoard(refs.DetailCanvas, board)
	end
	refs.DetailPicture.Visible = model ~= nil
	refs.DetailCanvas.Visible = model == nil
end

--[[
	The detail's board swinging slowly (`t` seconds since the window opened;
	HoverboardController calls it every frame while the window is open and
	Reduce Motion is off): one camera move, nothing rebuilt.
]]
function HoverboardView.turnDetail(refs: Refs, t: number)
	if refs.DetailBoard == nil or not refs.DetailPicture.Visible then
		return
	end
	aimCamera(refs, math.sin(t * HoverboardView.TurnSpeed) * HoverboardView.TurnSwing)
end

---------------------------------------------------------------- filling in

local function cardOf(refs: Refs, id: string): Card?
	for _, card in refs.Cards do
		if card.Board.Id == id then
			return card
		end
	end
	return nil
end

-- The card of the board the detail shows (the pick, else the default).
function HoverboardView.selectedCard(refs: Refs): Card
	return cardOf(refs, refs.Shown) or refs.Cards[1]
end

--[[
	Sizes a card's tags for its TagHeight: the right tag fits its word (and
	the coin or the lock before it; a UIPadding moves a chip's children too,
	so the icon sits left of the padded word), the E tag a little bigger.
]]
local function sizeTag(card: Card)
	local h = card.TagHeight
	local tag = card.Tag
	local icon = card.TagCoin.Visible or card.TagLock.Visible
	local iconW = if icon then h - 6 else 0
	local left = 5 + iconW
	padWord(tag, left, 5, 2)
	card.TagCoin.Size = UDim2.fromOffset(h - 8, h - 8)
	card.TagCoin.Position = UDim2.new(0, 4 - left, 0.5, 0)
	card.TagLock.Size = UDim2.fromOffset(h - 10, h - 10)
	card.TagLock.Position = UDim2.new(0, 6 - left, 0.5, 0)
	local word = math.floor(h * 0.8)
	GolemView.sizeChip(tag, math.ceil(Pop.textWidth(tag.Text, word)) + 6 + iconW, h)
	Pop.fit(tag, word)
	local e = h + 2
	GolemView.sizeChip(card.Equipped, e + 4, e)
	Pop.fit(card.Equipped, math.floor(e * 0.8))
end

-- Fills every card from the save: owned boards, the equipped one, your coins (and the detail).
function HoverboardView.setCards(refs: Refs, owned: { [string]: boolean }, equipped: string, coins: any)
	refs.Count.Text = HoverboardView.countText(owned)
	for _, card in refs.Cards do
		local board = card.Board
		local state: CardState = HoverboardView.cardState(board, owned, equipped, coins)
		card.State = state
		card.Owned = owned[board.Id] == true
		card.Equipped.Visible = state == "Equipped"
		-- the right tag: OWNED (blue), ROBUX (gold), else the price (a coin; grey with a lock: too expensive)
		local tag = card.Tag
		tag.Text = HoverboardView.tagText(board, card.Owned)
		local locked = state == "BuyLocked"
		local priced = not card.Owned and board.Kind ~= "Robux"
		tag.BackgroundColor3 = if card.Owned
			then Pop.paint("Blue").Bottom
			elseif board.Kind == "Robux" then Pop.paint("Yellow").Bottom
			elseif locked then PopTheme.Gray.Bottom
			else GolemView.ChipDark
		tag.TextColor3 = if priced and not locked then Pop.paint("Yellow").Top else PopTheme.Ink
		card.TagCoin.Visible = priced and not locked
		card.TagLock.Visible = priced and locked
		sizeTag(card)
	end
	HoverboardView.select(refs, refs.Selected)
end

-- Paints the action button for `state` (`board`: its words).
local function styleAction(refs: Refs, state: CardState, board: HoverboardData.Board)
	local style = STYLES[state]
	refs.ActionStyle = state
	GolemView.setPaint(refs.Action, style.Paint, true)
	refs.ActionWord.Text = HoverboardView.buttonText(state, board)
	refs.ActionAmount.Text = HoverboardView.amountText(state, board)
	local dim = state == "BuyLocked" or state == "Soon"
	refs.ActionWord.TextColor3 = if dim then PopTheme.Ink:Lerp(PopTheme.Gray.Bottom, 0.25) else PopTheme.Ink
	refs.ActionAmount.TextColor3 = refs.ActionWord.TextColor3
	-- EQUIPPED has nothing to do: not a gamepad stop
	refs.Action.Selectable = state ~= "Equipped"
	refs.Action:SetAttribute("State", state)
	fitAction(refs)
end

--[[
	Lays out the detail card for its board (the texts it shows depend on its
	description and perks): the name, the picture row (as big as the room
	allows, at least MinPicture: the perks go first, then the description),
	the pill, the chips, the description, the perks, the button at the bottom.
]]
local function layoutDetail(refs: Refs)
	local m = metrics(refs.Compact)
	local card = HoverboardView.selectedCard(refs)
	local board = card.Board
	local w = refs.Detail.Size.X.Offset
	local h = refs.Detail.Size.Y.Offset
	local inner = w - 24
	local buttonH = m.Button
	local nameH = if refs.Compact then 34 else 30
	local fixed = 10 + nameH + 4 + 6 + m.Pill + 6 + m.Pill + 8 + buttonH + 12
	local spare = h - fixed
	-- the description (round, at most three lines) and the perk lines (pixel)
	local textSize = m.Small - 1
	local lines = math.min(3, TechShopView.textLines(board.Description, inner - 16, textSize))
	local descH = math.ceil(lines * textSize * TechShopView.LineHeight) + 12
	local perkH = m.Small + 5
	local perksH = #board.Perks * perkH
	local showDesc, showPerks = true, true
	local picture = spare - (descH + 6) - (perksH + 6)
	if picture < m.MinPicture then
		showPerks = false
		picture = spare - (descH + 6)
	end
	if picture < m.MinPicture then
		showDesc = false
		picture = spare
	end
	picture = math.max(40, math.min(m.MaxPicture, picture))
	-- the name on top
	refs.DetailName.Position = UDim2.fromOffset(12, 10)
	refs.DetailName.Size = UDim2.fromOffset(inner, nameH)
	refs.DetailName.Text = string.upper(board.Name)
	fitWord(refs.DetailName, if refs.Compact then 34 else 32, inner)
	-- the picture row: the board big and turned (its square overflows the row: the board is flat)
	local picTop = 10 + nameH + 4
	local centreY = picTop + picture / 2
	local square = math.floor(math.min(inner, picture / HoverboardView.BoardHeight))
	refs.DetailPicture.Position = UDim2.fromOffset(w / 2, centreY)
	refs.DetailPicture.Size = UDim2.fromOffset(square, square)
	refs.DetailCanvas.Position = UDim2.fromOffset(w / 2, centreY)
	refs.DetailCanvasScale.Scale = math.max(0.2, math.min(picture * 1.1 / 110, inner / 200))
	aimReel(refs.Detail, UDim2.fromOffset(w / 2, centreY))
	-- the pill and the chips
	local y = picTop + picture + 6
	local pillSize = math.floor(m.Pill * 0.8)
	refs.DetailKind.Text = HoverboardView.kindText(board)
	refs.DetailKind.BackgroundColor3 = (if board.Kind == "Robux" then PopTheme.Price else HoverboardView.cardPaint(board)).Bottom:Lerp(
		PopTheme.Outline,
		0.3
	)
	refs.DetailKind.Position = UDim2.new(0.5, 0, 0, y)
	GolemView.sizeChip(refs.DetailKind, math.min(inner, math.ceil(Pop.textWidth(refs.DetailKind.Text, pillSize)) + 22), m.Pill)
	Pop.fit(refs.DetailKind, pillSize)
	y += m.Pill + 6
	refs.DetailSpeed.Text = HoverboardView.speedText(board)
	refs.DetailBonus.Text = HoverboardView.bonusText(board)
	local speedW = math.ceil(Pop.textWidth(refs.DetailSpeed.Text, pillSize)) + 22
	local bonusW = math.ceil(Pop.textWidth(refs.DetailBonus.Text, pillSize)) + 22
	local chipsW = speedW + 8 + bonusW
	local x = math.floor((w - chipsW) / 2)
	refs.DetailSpeed.Position = UDim2.fromOffset(x, y)
	GolemView.sizeChip(refs.DetailSpeed, speedW, m.Pill)
	Pop.fit(refs.DetailSpeed, pillSize)
	refs.DetailBonus.Position = UDim2.fromOffset(x + speedW + 8, y)
	GolemView.sizeChip(refs.DetailBonus, bonusW, m.Pill)
	Pop.fit(refs.DetailBonus, pillSize)
	y += m.Pill + 6
	-- the description and the perks (when there is room)
	refs.DetailText.Visible = showDesc
	refs.DetailText.Text = board.Description
	refs.DetailText.Position = UDim2.fromOffset(12, y)
	refs.DetailText.Size = UDim2.fromOffset(inner, descH)
	TechShopView.fitText(refs.DetailText, inner - 16, descH - 10, textSize, 11)
	GolemView.fitEdge(refs.DetailText)
	if showDesc then
		y += descH + 6
	end
	for i, label in refs.DetailPerks do
		local perk = board.Perks[i]
		label.Visible = showPerks and perk ~= nil
		label.Text = if perk then "+ " .. string.upper(perk) else ""
		label.Position = UDim2.fromOffset(12, y + (i - 1) * perkH)
		label.Size = UDim2.fromOffset(inner, perkH - 2)
		Pop.fitOrRound(label, m.Small + 1, m.Small + 1, if refs.Compact then 13 else 10, inner, perkH - 4)
	end
	-- the action button at the bottom
	local holder = holderOf(refs.Action)
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.Position = UDim2.fromOffset(12, h - buttonH - 12)
	holder.Size = UDim2.fromOffset(inner, buttonH)
	fitAction(refs)
end

--[[
	Picks a board (`id`; "" or unknown: no pick, the default: the equipped
	one, else the first; a refresh keeps a pick, setCards re-reads the default):
	its card gets the gold outline and the white ring, the detail shows it
	and its action. The gamepad's links follow (the right column's cards go
	right to the action button while it is a stop, else to the X; the button
	goes back left to the picked card).
]]
function HoverboardView.select(refs: Refs, id: string)
	local card = cardOf(refs, id)
	if not card then
		local equipped = ""
		for _, c in refs.Cards do
			if c.State == "Equipped" then
				equipped = c.Board.Id
			end
		end
		card = cardOf(refs, HoverboardView.defaultBoard(equipped))
	end
	local picked = card or refs.Cards[1]
	refs.Selected = if cardOf(refs, id) then id else ""
	refs.Shown = picked.Board.Id
	for _, c in refs.Cards do
		local chosen = c == picked
		c.Stroke.Thickness = if chosen then 6 else PopTheme.Edge
		c.Stroke.Color = if chosen then GolemView.SelectColor else PopTheme.Outline
		c.Pick.Visible = chosen
	end
	local board = picked.Board
	paintBoard(refs.Detail, board, refs.Detail.Size.Y.Offset)
	showDetailBoard(refs, board)
	styleAction(refs, picked.State, board)
	layoutDetail(refs)
	-- the gamepad's links
	local stop = refs.Action.Selectable
	for i, c in refs.Cards do
		local rightmost = i == 3 or i == #refs.Cards
		if rightmost then
			c.Button.NextSelectionRight = if stop then refs.Action else refs.Close
		end
	end
	refs.Action.NextSelectionLeft = picked.Button
end

function HoverboardView.setHint(refs: Refs, kind: HintKind, text: string)
	refs.HintText = text
	refs.HintKind = kind
	refs.HintGlyph.Visible = kind == "Gamepad" and refs.HintGlyph.Image ~= ""
	-- (phones: no hint; the pitch says what the boards are)
	refs.Hint.Text = if refs.Compact and kind ~= "Gamepad" then HoverboardView.Pitch else text
	local m = metrics(refs.Compact)
	local width = refs.Footer.Size.X.Offset - (if refs.HintGlyph.Visible then 34 else 0)
	refs.Hint.Size = UDim2.fromOffset(math.max(40, width), math.max(20, m.Footer - 6))
	TechShopView.fitText(refs.Hint, math.max(40, width), math.max(20, m.Footer - 6), m.Small, 11)
	GolemView.fitEdge(refs.Hint)
end

function HoverboardView.showMessage(refs: Refs, text: string, color: Color3)
	refs.Message.Text = text
	refs.Message.TextColor3 = color
	refs.Message.Visible = true
	refs.Footer.Visible = false
	local size = refs.Message.Size
	TechShopView.fitText(refs.Message, size.X.Offset, size.Y.Offset, metrics(refs.Compact).Small + 1, 11)
	GolemView.fitEdge(refs.Message)
end

function HoverboardView.hideMessage(refs: Refs)
	refs.Message.Visible = false
	refs.Footer.Visible = true
end

-- The first thing a gamepad selects: the picked board's card (a click before a switch to the
-- gamepad: focus, gold pick and detail stay together), else the equipped one's, the shown one's,
-- the first.
function HoverboardView.firstButton(refs: Refs): TextButton?
	if refs.Selected ~= "" then
		local picked = cardOf(refs, refs.Shown)
		if picked then
			return picked.Button
		end
	end
	for _, card in refs.Cards do
		if card.State == "Equipped" then
			return card.Button
		end
	end
	local picked = cardOf(refs, refs.Shown)
	if picked then
		return picked.Button
	end
	return if refs.Cards[1] then refs.Cards[1].Button else refs.Close
end

-- Every button a finger or a gamepad uses (tests: 44 pt at the phone scale).
function HoverboardView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close), holderOf(refs.Action) }
	for _, card in refs.Cards do
		table.insert(list, card.Button)
	end
	return list
end

---------------------------------------------------------------- layout

local function place(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

--[[
	Inside a card `w` x `h`: the pixel name on top (two lines when one would
	be small), the bottom line, the picture between them (a square that
	overflows the row: the board is flat), the tags beside the picture.
]]
local function layoutCard(card: Card, m: Metrics, w: number, h: number)
	local lip = Pop.lipUnits(h)
	paintBoard(card.Button, card.Board, h)
	local nameText = string.upper(card.Board.Name)
	card.Name.Text = nameText
	local nameMax = math.floor((m.Small + 7) * PopTheme.PixelScale + 0.5)
	local nameSize, nameLines = GolemView.nameFit(nameText, nameMax, w - 12, m.NameFloor)
	local nameH = if nameLines > 1 then GolemView.nameHeight(nameSize, nameLines) else CARD_TITLE - 4
	card.Name.Position = UDim2.fromOffset(5, 5)
	card.Name.Size = UDim2.new(1, -10, 0, nameH)
	setName(card.Name, nameSize, nameLines)
	local picTop = math.max(CARD_TITLE, 5 + nameH + 1)
	-- the bottom line
	card.Line.Position = UDim2.new(0.5, 0, 1, -(lip + 2))
	card.Line.Size = UDim2.new(1, -10, 0, CARD_LINE - 4)
	Pop.fitOrRound(card.Line, m.Small + 2, m.Small + 2, if m == METRICS.Compact then 13 else 10, w - 10, CARD_LINE - 4)
	-- the picture
	local bottom = h - lip - CARD_LINE - 2
	local ph = math.max(20, bottom - picTop)
	local pw = w - 12
	local square = math.floor(math.min(pw * 1.1, ph / HoverboardView.BoardHeight))
	local cx, cy = w / 2, picTop + ph / 2
	card.ArtBack.Position = UDim2.fromOffset(cx, cy)
	card.ArtBack.Size = UDim2.fromOffset(square, square)
	card.Canvas.Position = UDim2.fromOffset(cx, cy)
	card.CanvasScale.Scale = math.max(0.2, math.min(ph * 1.12 / 110, pw / 200))
	aimReel(card.Button, UDim2.fromOffset(cx, cy))
	-- the tags: E on the left, the right tag tilted on the right (smaller on small cards)
	card.TagHeight = math.clamp(math.floor(h * 0.13), 20, m.Tag)
	card.Equipped.Position = UDim2.fromOffset(6, picTop + 4)
	card.Tag.Position = UDim2.new(1, -5, 0, picTop + 10)
	sizeTag(card)
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	window into `maxWidth` x `maxHeight` design units (math.huge = no limit).
]]
function HoverboardView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local width = math.min(m.Width, maxWidth - 16)
	local height = math.min(m.Height, maxHeight - 12)
	width = math.max(width, 3 * 132 + 2 * CELL_GAP + INSET * 2 + m.Detail + 2 * PAD + GAP)
	height = math.max(height, 380)
	refs.Root.Size = UDim2.fromOffset(width, height)

	-- the header: the band, the title and its count, the X
	local h = m.Header
	GolemView.layoutChrome(refs.Root, h)
	local titleSize = m.Title + 4
	local titleW = math.ceil(Pop.textWidth(refs.Title.Text, titleSize)) + 8
	GolemView.placeTitle(refs.Title, PAD + 4, 4, titleW, h - 12, titleSize)
	local countH = if compact then 34 else 30
	refs.Count.Position = UDim2.fromOffset(PAD + 4 + titleW + 8, math.floor((h - countH) / 2))
	GolemView.sizeChip(refs.Count, if compact then 108 else 96, countH)
	Pop.fit(refs.Count, if compact then 25 else 22)
	local closeHolder = holderOf(refs.Close)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -(PAD - 4), 0, math.floor((h - m.Close) / 2))
	closeHolder.Size = UDim2.fromOffset(m.Close, m.Close)
	Pop.fit(refs.Close :: any, math.floor(m.Close * 0.62))

	-- the body: the grid on its well on the left, the detail card on the right
	local bodyY = h + 8
	local footer = m.Footer
	local bodyH = height - bodyY - footer - 8
	local detailX = width - PAD - m.Detail
	local gridW = detailX - PAD - GAP
	place(refs.GridWell, PAD - 4, bodyY - 4, gridW + 8, bodyH + 8)
	place(refs.Grid, PAD - 4, bodyY - 4, gridW + 8, bodyH + 8)
	for i, cell in HoverboardView.cells(gridW + 8, bodyH + 8, #refs.Cards) do
		local card = refs.Cards[i]
		local x, y, w, ch = cell[1], cell[2], cell[3], cell[4]
		card.Frame.Size = UDim2.fromOffset(w, ch)
		card.Frame.Position = UDim2.fromOffset(x + w / 2, y + ch / 2)
		card.Frame:SetAttribute("BaseY", y + ch / 2)
		layoutCard(card, m, w, ch)
	end
	place(refs.Detail, detailX, bodyY - 4, m.Detail, bodyH + 8)

	-- the footer line (and the message in its place)
	refs.Footer.Position = UDim2.new(0.5, 0, 1, -4)
	refs.Footer.Size = UDim2.fromOffset(width - 40, footer - 4)
	refs.Message.Position = UDim2.new(0.5, 0, 1, -4)
	refs.Message.Size = UDim2.fromOffset(width - 40, footer - 4)
	HoverboardView.setHint(refs, refs.HintKind, refs.HintText)

	-- the detail (its texts follow the picked board)
	HoverboardView.select(refs, refs.Selected)
	HoverboardView.pose(refs, refs.PoseTime)
end

---------------------------------------------------------------- the opening animation

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

-- The window `seconds` into its opening (0 = closed, OpenTime = open): the
-- window pops in, the cards drop in one after another. Closing plays it backwards.
function HoverboardView.pose(refs: Refs, seconds: number)
	local t = math.clamp(seconds, 0, HoverboardView.OpenTime)
	refs.PoseTime = t
	refs.Pop.Scale = 0.88 + 0.12 * backOut(clamp01(t / 0.26))
	for i, card in refs.Cards do
		local q = clamp01((t - 0.12 - 0.035 * (i - 1)) / 0.16)
		card.Frame.Visible = q > 0
		card.Scale.Scale = 0.86 + 0.14 * backOut(q)
		local baseY = card.Frame:GetAttribute("BaseY")
		local y = if type(baseY) == "number" then baseY else 0
		card.Frame.Position = UDim2.fromOffset(card.Frame.Position.X.Offset, y - 16 * (1 - q))
	end
end

---------------------------------------------------------------- the RIDE button

HoverboardView.RideSize = 84

-- The RIDE toggle for the HUD's right menu (its LayoutOrder puts it above BUILD).
function HoverboardView.rideButton(parent: Instance): RideButton
	local size = HoverboardView.RideSize
	local holder: Frame = UIKit.new("Frame", {
		Name = "RideHolder",
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(size, size + 6),
	}, parent)
	local button: TextButton = UIKit.new("TextButton", {
		Name = "Ride",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}, holder)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)
	local g = gradient3(button, WHITE, WHITE, WHITE)
	local ringStroke = ring(button, 4, INK)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Bounce", Scale = 1 }, button)
	local icon = Icons.board(button, TEXT, rgb(120, 230, 255))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.36)
	icon.Size = UDim2.fromScale(0.56, 0.4)
	local label = UIKit.label(button, "RIDE", 22, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.9, 0.3),
		FontFace = Theme.TitleFont,
		TextColor3 = TEXT,
		TextWrapped = false,
	})
	local key = UIKit.label(holder, "H", 16, {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = NAVY_DEEP,
		BackgroundTransparency = 0,
		TextColor3 = TEXT,
		TextWrapped = false,
		ZIndex = 3,
	})
	UIKit.corner(key, 8)
	ring(key, 2, NEON_BRIGHT)
	local glyph: ImageLabel = UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, holder)
	local ride: RideButton = {
		Holder = holder,
		Button = button,
		Scale = scale,
		Gradient = g,
		Ring = ringStroke,
		Label = label,
		Key = key,
		Glyph = glyph,
		Tile = false,
		Riding = false,
	}
	HoverboardView.setRiding(ride, false)
	return ride
end

-- The round look's Ride tile in the HUD's grid (HudBubble.RoundMenu "Ride"): a dark tile like
-- Spin or Build, its word Ride / Stop, the H keycap; nil when the grid has no Ride tile.
function HoverboardView.rideTile(menu: Instance): RideButton?
	if not (menu:GetAttribute("Bubble") and menu:FindFirstChild("Ride")) then
		return nil
	end
	local face = HudBubble.claimTile(menu, "Ride")
	local label = face:FindFirstChild("Label") :: TextLabel
	local ride: RideButton = {
		Holder = face.Parent :: Frame,
		Button = face,
		Label = label,
		Tile = true,
		Riding = false,
	}
	HoverboardView.setRiding(ride, false)
	return ride
end

-- RIDE (violet) while walking, STOP (red) while riding; `hint` = the key chip
-- text ("H"), "" hides it (touch); `glyph` = a gamepad image shown instead.
function HoverboardView.setRiding(ride: RideButton, riding: boolean, hint: string?, glyph: string?)
	ride.Riding = riding
	local gradient, ringStroke, key, glyphLabel = ride.Gradient, ride.Ring, ride.Key, ride.Glyph
	if ride.Tile or not (gradient and ringStroke and key and glyphLabel) then
		-- the tile: only its word and its keycap change
		ride.Label.Text = Pop.caption(if riding then "Stop" else "Ride")
		HudBubble.setKeyCap(ride.Button, if glyph and glyph ~= "" then nil else hint or "H", glyph)
		return
	end
	if riding then
		setGradient3(gradient, rgb(255, 140, 120), rgb(236, 70, 66), rgb(176, 34, 44))
		ringStroke.Color = rgb(90, 14, 20)
		ride.Label.Text = "STOP"
	else
		setGradient3(gradient, rgb(176, 116, 255), rgb(118, 56, 230), rgb(70, 28, 160))
		ringStroke.Color = INK
		ride.Label.Text = "RIDE"
	end
	local image = glyph or ""
	glyphLabel.Image = image
	glyphLabel.Visible = image ~= ""
	local text = hint or "H"
	key.Text = text
	key.Visible = image == "" and text ~= ""
end

return HoverboardView
