--[[
	Hoverboards on screen (pure builder + pure helpers; HoverboardController
	fills it in and animates it). Look: the bright "Pop" window kit (Pop.luau,
	like the Robux Shop; owner 2026-10-21: "new, modern, colourful, clean
	items, more Roblox style"), the same chrome as the elevator window
	(ElevatorView.popWindow).

	  panel    a Pop window: a blue header band (the side menu's Hover colour,
	           BubbleTheme Lobby) with shine stripes and studs, a small board
	           icon, "HOVERBOARDS" in white with a 3D shadow, the red square X;
	           a dark studded body; under the band the pitch ("Ride anywhere,
	           faster." or the last server message); a dark footer pill with
	           the control hint (not on phones)
	  cards    one per board (HoverboardData order: 4 coin boards, then the
	           Robux board with a gold "ROBUX" ribbon): a bright painted Pop
	           card (CardPaints) with light rays and a glow behind the board's
	           live 3D model (PictureModels "board_<Id>": HoverboardBuilder in a
	           ViewportFrame; drawn from Frames only if the model can't be
	           built), the name, the speed as chips ("SPEED 23" and "+44%"),
	           one perk line, the coin price (a Robux board: its trail, the
	           price is only on its button) or an OWNED chip, and the button:
	           BUY (green) / BUY with a lock (grey:
	           not enough coins) / EQUIP (blue) / EQUIPPED (gold, a check; the
	           card gets a gold outline and halo) / the green Pop.price "49"
	           (Robux) / COMING SOON (grey: the product id is still 0)
	  (the panel opens from main's left side menu: its HOVER entry, SideMenuView)
	  ride     the RIDE toggle for the HUD's right menu (rideButton): RIDE /
	           STOP with a key chip ("H") or the gamepad glyph

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). Five tall cards in a row when they fit, else 3 + 2 wide
	cards (the picture on the left); the compact layout (phones, uiScale 0.62)
	has 72-unit buttons (about 44 pt). A gamepad selection stays inside the
	panel (SelectionGroup); only the card buttons and the X are selectable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonetizationConfig"))
local HoverboardData = require(Shared.Config.HoverboardData)
local PopTheme = require(Shared.Config.PopTheme)
local PictureModels = require(Shared.Builders.PictureModels)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local ElevatorView = require(script.Parent.ElevatorView)

local HoverboardView = {}

export type CardState = "Buy" | "BuyLocked" | "Equip" | "Equipped" | "Robux" | "Soon"
export type HintKind = "Mouse" | "Gamepad" | "Touch"

-- a Pop button (ElevatorView.popButton: Pop.price's face with the drawn icons and the robux mark)
export type ButtonRefs = ElevatorView.ButtonRefs

export type Card = {
	Board: HoverboardData.Board,
	Frame: Frame, -- the holder (the layout places it; the drop-in scales it)
	Scale: UIScale,
	Face: TextButton, -- the painted Pop card (not selectable: its button is)
	Stroke: UIStroke, -- the card's black edge (gold when equipped)
	Glow: Frame, -- the equipped board's gold halo
	ArtBack: Frame, -- where the picture sits
	Picture: ImageLabel?, -- the live 3D board (nil: drawn on the Canvas instead)
	Canvas: Frame, -- the board drawn from Frames (only without a model)
	CanvasScale: UIScale,
	Ribbon: Frame?,
	Name: TextLabel,
	SpeedChip: Frame,
	Speed: TextLabel,
	BonusChip: Frame,
	Bonus: TextLabel,
	Perk: TextLabel,
	PriceRow: Frame, -- a coin board's price (a Robux board's price is its green button)
	Coin: Frame,
	Price: TextLabel,
	Extra: TextLabel, -- a Robux board's extra perk where a coin board shows its price
	Owned: Frame, -- the OWNED chip where the price was
	Button: TextButton,
	Look: ButtonRefs,
	State: CardState,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame,
	Pop: UIScale,
	Panel: Frame, -- the Pop window
	Header: Frame, -- the blue band
	Body: Frame, -- the dark studded body
	Chrome: ElevatorView.Chrome,
	Icon: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	Subtitle: TextLabel,
	Message: TextLabel,
	Close: TextButton,
	CloseLook: ButtonRefs,
	CardPage: ScrollingFrame, -- the cards (they scroll on very short screens)
	Scrolls: boolean, -- the last layout's cards scroll
	Cards: { Card },
	Footer: Frame,
	Hint: TextLabel,
	HintGlyph: ImageLabel,
	Compact: boolean,
	Columns: number,
	MaxWidth: number,
	MaxHeight: number,
	PoseTime: number,
}

export type RideButton = {
	Holder: Frame,
	Button: TextButton,
	Scale: UIScale,
	Gradient: UIGradient,
	Ring: UIStroke,
	Label: TextLabel,
	Key: TextLabel,
	Glyph: ImageLabel,
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
local GOLD = rgb(255, 204, 64)
local PERK_GOLD = rgb(255, 228, 120)
local INK = rgb(10, 12, 26)

HoverboardView.Title = "HOVERBOARDS"
HoverboardView.Pitch = "Ride anywhere, faster. Bought once, yours forever."
HoverboardView.Paint = "Blue" -- the header band (the side menu's Hover colour)
HoverboardView.OpenTime = 0.42
HoverboardView.CloseTime = 0.2
-- asset ids for the owner's uploaded art ("" = draw it from Frames; only used without a 3D model)
HoverboardView.BoardImages = {} :: { [string]: string }
-- each board's card paint (PopTheme.Paints; the Robux boards as in the shop's passes)
HoverboardView.CardPaints = {
	TimberDrifter = "Orange",
	CartCruiser = "Blue",
	EmberglassGlider = "Red",
	RoyalPhoenix = "Purple",
	TerraForgeCustom = "Pink",
} :: { [string]: string }

type Metrics = {
	Width: number,
	Height: number,
	Pad: number,
	Band: number, -- the coloured header band
	Header: number, -- the band + the pitch line: where the cards start
	Title: number,
	Icon: number,
	Text: number,
	Gap: number,
	Button: number,
	ButtonText: number,
	Name: number,
	Small: number,
	Price: number,
	Close: number,
	Footer: number,
	MinCard: number,
	MinHeight: number, -- a card is at least this tall, else the cards scroll
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1080,
		Height = 470,
		Pad = 20,
		Band = 76,
		Header = 110,
		Title = 46,
		Icon = 52,
		Text = 20,
		Gap = 14,
		Button = 56,
		ButtonText = 24,
		Name = 22,
		Small = 17,
		Price = 26,
		Close = 62,
		Footer = 36,
		MinCard = 176,
		MinHeight = 200,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1320,
		Height = 560,
		Pad = 18,
		Band = 76,
		Header = 104,
		Title = 46,
		Icon = 50,
		Text = 22,
		Gap = 12,
		Button = 72,
		ButtonText = 27,
		Name = 25,
		Small = 20,
		Price = 28,
		Close = 64,
		Footer = 0,
		MinCard = 230,
		MinHeight = 196,
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

-- Cards per row for a panel `width` design units wide.
function HoverboardView.columns(width: number, compact: boolean): number
	local m = metrics(compact)
	local count = #HoverboardData.List
	local need = count * m.MinCard + (count - 1) * m.Gap + m.Pad * 2
	return if width >= need then count else math.ceil(count / 2)
end

-- A board's card paint.
function HoverboardView.cardPaint(board: HoverboardData.Board): Pop.Paint
	return Pop.paint(HoverboardView.CardPaints[board.Id] or "Slate")
end

---------------------------------------------------------------- drawing kit

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

-- a tiny board (headers, the RIDE button)
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

---------------------------------------------------------------- buttons

type ButtonStyle = {
	Paint: Pop.Paint,
	Mid: Color3, -- the face's colour at its glossy step (Pop.face)
	Icon: string?, -- a drawn icon before the word
	Mark: boolean, -- the robux mark before the price (Pop.price)
}

local function buttonStyle(paint: Pop.Paint, icon: string?, mark: boolean?): ButtonStyle
	return { Paint = paint, Mid = paint.Top:Lerp(paint.Bottom, 0.42), Icon = icon, Mark = mark == true }
end

local STYLES: { [string]: ButtonStyle } = {
	Buy = buttonStyle(PopTheme.Price),
	BuyLocked = buttonStyle(PopTheme.Gray, "Lock"),
	Equip = buttonStyle(Pop.paint("Blue")),
	Equipped = buttonStyle(Pop.paint("Yellow"), "Check"),
	Robux = buttonStyle(PopTheme.Price, nil, true), -- the green Pop.price: the robux mark and "49"
	Soon = buttonStyle(PopTheme.Gray, "Clock"),
	Close = buttonStyle(PopTheme.Close),
}
HoverboardView.ButtonStyles = STYLES

local ICON_MAKERS: { [string]: (Instance, Color3) -> Frame } = {
	Check = Icons.check,
	Lock = Icons.lock,
	Clock = Icons.clock,
}

local function styleButton(look: ButtonRefs, styleName: string, text: string, textSize: number)
	local style = STYLES[styleName]
	look.Style = styleName
	ElevatorView.paintButton(look, style.Paint, text, textSize, style.Icon, false)
	local mark = look.Row:FindFirstChild("Mark") :: ImageLabel?
	if mark then
		mark.Visible = style.Mark
		mark.Size = UDim2.fromOffset(textSize + 4, textSize + 4)
	end
end

---------------------------------------------------------------- building

-- the size a card is built at (the layout resizes it; Pop.card sizes its rays and glow from it)
local CARD_BUILD = Vector2.new(200, 320)
-- Pop.card's light burst (rays and glow): it follows the picture
local CARD_FX = { "Rays", "Glow", "Glow1", "Glow2" }
-- the room round the cards inside their scroll (the equipped board's gold halo is not clipped)
local CARD_MARGIN = 6

local function newCard(page: GuiObject, board: HoverboardData.Board): Card
	local robux = board.Kind == "Robux"
	local frame: Frame = UIKit.new("Frame", {
		Name = board.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		LayoutOrder = board.Order,
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
	}, page)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
	-- the equipped board's soft gold halo (outside the card's own gold edge)
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
	-- the painted card: light rays and a glow behind the board, studs, sparkles, the light rim
	local face = Pop.card(frame, HoverboardView.cardPaint(board), {
		Name = "Face",
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
		Selectable = false,
		ZIndex = 2,
	}, UDim2.fromScale(0.5, 0.36))
	face.Size = UDim2.fromScale(1, 1)
	local stroke = face:FindFirstChild("Border") :: UIStroke
	-- the board: its live 3D model (like the shop's board passes), else drawn from Frames
	local artBack: Frame = UIKit.new("Frame", {
		Name = "ArtBack",
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, face)
	local model, from = PictureModels.build("board_" .. board.Id)
	local picture: ImageLabel? = nil
	if model then
		-- (a bit bigger than its spot: the camera frames the board's bounding sphere, a flat board
		-- leaves room round it)
		picture = Pop.model(artBack, "board_" .. board.Id, 160, model, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.3, 1.3),
			ZIndex = 4,
		}, from)
	end
	local canvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 110),
		ZIndex = 4,
	}, face)
	local canvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, canvas)
	if not picture then
		HoverboardView.drawBoard(canvas, board)
	end
	-- the gold ROBUX ribbon on the picture's corner
	local ribbon: Frame? = nil
	if robux then
		ribbon = Pop.ribbon(face, "ROBUX", 86)
	end
	local name = Pop.text(face, board.Name, 22, {
		Name = "BoardName",
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
	})
	-- the speed as chips: "SPEED 23" and the bonus "+44%"
	local speedChip = Pop.chip(face, HoverboardView.speedText(board), "Slate", Vector2.new(100, 26), { ZIndex = 6 })
	speedChip.Name = "SpeedChip"
	local speed = speedChip:FindFirstChild("Label") :: TextLabel
	local bonusChip = Pop.chip(face, HoverboardView.bonusText(board), "Green", Vector2.new(70, 26), { ZIndex = 6 })
	bonusChip.Name = "BonusChip"
	local bonus = bonusChip:FindFirstChild("Label") :: TextLabel
	local perk = Pop.text(face, board.Perks[2] or board.Perks[1] or "", 16, {
		Name = "Perk",
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = if robux then PERK_GOLD else TEXT,
		ZIndex = 6,
	})
	-- the coin price (a gold coin and the amount) or, once owned, the OWNED chip; a Robux
	-- board's price is only on its green button, its line shows one more perk (its trail)
	local priceRow: Frame = UIKit.new("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
		Visible = not robux,
		ZIndex = 6,
	}, face)
	UIKit.list(priceRow, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local coin = Pop.coin(priceRow, 26, { LayoutOrder = 1 })
	local price = Pop.text(priceRow, HoverboardView.priceText(board), 26, {
		Name = "Price",
		LayoutOrder = 2,
		FontFace = PopTheme.Heavy,
		TextColor3 = Theme.Coin,
		ZIndex = 7,
	})
	local extra = Pop.text(face, "", 18, {
		Name = "Extra",
		TextColor3 = PERK_GOLD,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = robux,
		ZIndex = 6,
	})
	local owned = Pop.chip(face, "OWNED", "Green", Vector2.new(110, 28), { Visible = false, ZIndex = 6 })
	owned.Name = "Owned"
	-- the button (over the card, not clipped by it): BUY / EQUIP / EQUIPPED / the Robux price / COMING SOON
	local look = ElevatorView.popButton(frame, "Action", { "Check", "Lock", "Clock" }, ICON_MAKERS)
	look.Holder.ZIndex = 3
	return {
		Board = board,
		Frame = frame,
		Scale = scale,
		Face = face,
		Stroke = stroke,
		Glow = glow,
		ArtBack = artBack,
		Picture = picture,
		Canvas = canvas,
		CanvasScale = canvasScale,
		Ribbon = ribbon,
		Name = name,
		SpeedChip = speedChip,
		Speed = speed,
		BonusChip = bonusChip,
		Bonus = bonus,
		Perk = perk,
		PriceRow = priceRow,
		Coin = coin,
		Price = price,
		Extra = extra,
		Owned = owned,
		Button = look.Button,
		Look = look,
		State = "Buy",
	}
end

local function newFooter(root: Frame): (Frame, TextLabel, ImageLabel)
	local footer, row = ElevatorView.popFooter(root)
	footer.Size = UDim2.fromOffset(460, 36)
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
	return footer, hint, glyph
end

function HoverboardView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeHoverboards", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local root: Frame = UIKit.new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.Width, METRICS.Normal.Height),
		BackgroundTransparency = 1,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local pop: UIScale = UIKit.new("UIScale", { Name = "OpenPop", Scale = 1 }, root)
	-- the Pop window: the blue band (icon, title, X) over the dark studded body
	local chrome = ElevatorView.popWindow(root, HoverboardView.Title, HoverboardView.Paint, METRICS.Normal.Band)
	local panel = chrome.Panel
	-- the band's icon: a violet tile with a white board
	local icon: Frame = UIKit.new("Frame", {
		Name = "HeaderIcon",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, chrome.Header)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, icon)
	gradient3(icon, rgb(170, 100, 255), rgb(118, 56, 220), rgb(72, 30, 160))
	ring(icon, 3, INK)
	local board = Icons.board(icon, TEXT, rgb(120, 230, 255))
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.5)
	board.Size = UDim2.fromScale(0.8, 0.8)
	-- the pitch under the band (or the last server message)
	local subtitle = Pop.text(panel, HoverboardView.Pitch, 20, {
		Name = "Subtitle",
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local message = Pop.text(panel, "", 20, {
		Name = "Message",
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.Bad,
		Visible = false,
		ZIndex = 3,
	})
	-- the cards (a scroll that only scrolls when they don't fit: very short screens)
	local page: ScrollingFrame = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = rgb(196, 200, 212),
		ScrollingEnabled = false,
		Selectable = false,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ZIndex = 3,
	}, panel)
	local cards: { Card } = {}
	for _, b in HoverboardData.List do
		table.insert(cards, newCard(page, b))
	end
	-- the footer pill on the root (over the frame's bottom edge)
	local footer, hint, glyph = newFooter(root)
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
		Message = message,
		Close = chrome.CloseLook.Button,
		CloseLook = chrome.CloseLook,
		CardPage = page,
		Scrolls = false,
		Cards = cards,
		Footer = footer,
		Hint = hint,
		HintGlyph = glyph,
		Compact = false,
		Columns = #cards,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
		PoseTime = HoverboardView.OpenTime,
	}
	HoverboardView.setCards(refs, {}, "", 0)
	HoverboardView.setHint(refs, "Mouse", "Click a card · H: ride · Backspace: close")
	HoverboardView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- filling in

-- Fills every card from the save: owned boards, the equipped one, your coins.
function HoverboardView.setCards(refs: Refs, owned: { [string]: boolean }, equipped: string, coins: any)
	local m = metrics(refs.Compact)
	for _, card in refs.Cards do
		local state: CardState = HoverboardView.cardState(card.Board, owned, equipped, coins) :: any
		card.State = state
		styleButton(
			card.Look,
			state,
			HoverboardView.buttonText(state, card.Board),
			if state == "Soon" then m.ButtonText - 6 else m.ButtonText
		)
		-- the equipped board: a gold edge and the soft gold halo
		local on = state == "Equipped"
		card.Glow.Visible = on
		card.Stroke.Color = if on then GOLD else PopTheme.Outline
		card.Stroke.Thickness = if on then 4 else PopTheme.Edge
		card.Button.Selectable = not on
		local owns = state == "Equip" or on
		local robux = card.Board.Kind == "Robux"
		card.PriceRow.Visible = not owns and not robux
		card.Extra.Visible = not owns and robux
		card.Owned.Visible = owns
	end
end

function HoverboardView.setHint(refs: Refs, kind: HintKind, text: string)
	refs.Hint.Text = text
	refs.Hint.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(text, refs.Hint.TextSize)) + 6, 26)
	refs.HintGlyph.Visible = kind == "Gamepad" and refs.HintGlyph.Image ~= ""
	local width = refs.Hint.Size.X.Offset + (if refs.HintGlyph.Visible then 34 else 0) + 40
	refs.Footer.Size = UDim2.fromOffset(width, refs.Footer.Size.Y.Offset)
end

function HoverboardView.showMessage(refs: Refs, text: string, color: Color3)
	refs.Message.Text = text
	refs.Message.TextColor3 = color
	refs.Message.Visible = true
	refs.Subtitle.Visible = false
end

function HoverboardView.hideMessage(refs: Refs)
	refs.Message.Visible = false
	refs.Subtitle.Visible = true
end

-- The first card button a gamepad should land on (the equipped card's neighbour, else the first actionable).
function HoverboardView.firstButton(refs: Refs): TextButton?
	for _, card in refs.Cards do
		if card.State == "Buy" or card.State == "Robux" or card.State == "Equip" then
			return card.Button
		end
	end
	for _, card in refs.Cards do
		if card.Button.Selectable then
			return card.Button
		end
	end
	return refs.Close
end

---------------------------------------------------------------- layout

-- A label's text size for `room` design units (never under `least`), its black edge to match.
local function fitText(label: TextLabel, size: number, room: number, least: number)
	local wide = ElevatorView.measure(label.Text, size)
	label.TextSize = if wide > room then math.max(least, math.floor(size * room / wide)) else size
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(label.TextSize)
	end
end

-- Sizes a row of chips for `textSize` (smaller when they don't fit `room`); returns the row's width.
local function sizeChips(chips: { Frame }, textSize: number, height: number, room: number, gap: number): number
	local function total(size: number): number
		local sum = gap * (#chips - 1)
		for _, chip in chips do
			local label = chip:FindFirstChildOfClass("TextLabel")
			if label then
				sum += math.ceil(ElevatorView.measure(label.Text, size)) + 18
			end
		end
		return sum
	end
	local size = textSize
	local width = total(size)
	if width > room then
		size = math.max(11, math.floor(textSize * room / width))
		width = total(size)
	end
	for _, chip in chips do
		local label = chip:FindFirstChildOfClass("TextLabel")
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

--[[
	Inside a card: the button at the bottom. A tall card (PC, five a row): the
	name, the picture, the speed chips, the perk line and the price (or OWNED;
	a Robux board: its trail) above it. A wide card (phones, 3 + 2): the
	picture on the left, the name, the chips and the price (a Robux board: its
	"Rainbow lightning") on the right (no perk line).
]]
local function layoutCard(card: Card, m: Metrics, w: number, h: number)
	local pad = 10
	local holder = card.Look.Holder
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.new(0, pad, 1, -pad)
	holder.Size = UDim2.new(1, -pad * 2, 0, m.Button)
	local bottom = h - pad - m.Button - 6 -- the words and the picture end here
	local chipHeight = m.Small + 8
	local priceHeight = m.Price + 6
	local chips = { card.SpeedChip, card.BonusChip }
	local px, py, pw, ph
	if w <= h then
		card.Name.TextXAlignment = Enum.TextXAlignment.Center
		card.Name.Position = UDim2.fromOffset(pad, pad)
		card.Name.Size = UDim2.fromOffset(w - pad * 2, m.Name + 6)
		fitText(card.Name, m.Name, w - pad * 2 - 4, 13)
		local priceTop = bottom - priceHeight
		local perkTop = priceTop - 2 - (m.Small + 4)
		local chipsTop = perkTop - 4 - chipHeight
		card.Perk.Visible = true
		card.Perk.TextXAlignment = Enum.TextXAlignment.Center
		card.Perk.Position = UDim2.fromOffset(pad, perkTop)
		card.Perk.Size = UDim2.fromOffset(w - pad * 2, m.Small + 4)
		fitText(card.Perk, m.Small - 1, w - pad * 2 - 4, 12)
		local chipsWidth = sizeChips(chips, m.Small - 2, chipHeight, w - pad * 2, 6)
		local x = math.floor((w - chipsWidth) / 2)
		card.SpeedChip.Position = UDim2.fromOffset(x, chipsTop)
		card.BonusChip.Position = UDim2.fromOffset(x + card.SpeedChip.Size.X.Offset + 6, chipsTop)
		card.PriceRow.Position = UDim2.fromOffset(pad, priceTop)
		card.PriceRow.Size = UDim2.fromOffset(w - pad * 2, priceHeight)
		card.Owned.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Owned.Position = UDim2.fromOffset(math.floor(w / 2), priceTop + math.floor(priceHeight / 2))
		local perks = card.Board.Perks
		card.Extra.Text = perks[3] or perks[1] or ""
		card.Extra.TextXAlignment = Enum.TextXAlignment.Center
		card.Extra.Position = UDim2.fromOffset(pad, priceTop)
		card.Extra.Size = UDim2.fromOffset(w - pad * 2, priceHeight)
		fitText(card.Extra, m.Small + 1, w - pad * 2 - 4, 12)
		px, py = pad, pad + m.Name + 8
		pw, ph = w - pad * 2, chipsTop - 4 - (pad + m.Name + 8)
	else
		pw, ph = math.floor(w * 0.44), bottom - pad
		px, py = pad, pad
		local x = pad + pw + 8
		local room = w - x - pad
		card.Name.TextXAlignment = Enum.TextXAlignment.Left
		card.Name.Position = UDim2.fromOffset(x, pad)
		card.Name.Size = UDim2.fromOffset(room, m.Name + 6)
		fitText(card.Name, m.Name, room - 2, 13)
		local chipsTop = pad + m.Name + 10
		sizeChips(chips, m.Small - 2, chipHeight, room, 6)
		card.SpeedChip.Position = UDim2.fromOffset(x, chipsTop)
		card.BonusChip.Position = UDim2.fromOffset(x + card.SpeedChip.Size.X.Offset + 6, chipsTop)
		card.Perk.Visible = false
		local priceTop = chipsTop + chipHeight + 6
		card.PriceRow.Position = UDim2.fromOffset(x, priceTop)
		card.PriceRow.Size = UDim2.fromOffset(room, priceHeight)
		card.Owned.AnchorPoint = Vector2.new(0, 0.5)
		card.Owned.Position = UDim2.fromOffset(x, priceTop + math.floor(priceHeight / 2))
		local perks = card.Board.Perks
		card.Extra.Text = perks[2] or perks[1] or ""
		card.Extra.TextXAlignment = Enum.TextXAlignment.Left
		card.Extra.Position = UDim2.fromOffset(x, priceTop)
		card.Extra.Size = UDim2.fromOffset(room, priceHeight)
		fitText(card.Extra, m.Small + 1, room - 2, 12)
	end
	local list = card.PriceRow:FindFirstChildOfClass("UIListLayout")
	if list then
		list.HorizontalAlignment = if w <= h then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	end
	-- the price: the coin and the amount
	card.Price.TextSize = m.Price
	card.Price.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(card.Price.Text, m.Price, true)) + 6, priceHeight)
	card.Coin.Size = UDim2.fromOffset(m.Price, m.Price)
	local coinMark = card.Coin:FindFirstChild("Mark") :: TextLabel?
	if coinMark then
		coinMark.TextSize = math.floor(m.Price * 0.62)
	end
	sizeChips({ card.Owned }, m.Small - 1, chipHeight + 2, w, 0)
	-- the picture and the light burst behind it
	card.ArtBack.Position = UDim2.fromOffset(px, py)
	card.ArtBack.Size = UDim2.fromOffset(pw, math.max(20, ph))
	local cx, cy = px + pw / 2, py + ph / 2
	card.Canvas.Position = UDim2.fromOffset(cx, cy)
	card.CanvasScale.Scale = math.max(0.2, math.min(ph * 1.12 / 110, pw / 200))
	for _, fxName in CARD_FX do
		local fx = card.Face:FindFirstChild(fxName)
		if fx and fx:IsA("GuiObject") then
			fx.Position = UDim2.fromOffset(cx, cy)
		end
	end
	-- the ROBUX ribbon on the picture's top-right corner
	local ribbon = card.Ribbon
	if ribbon then
		ribbon.AnchorPoint = Vector2.new(1, 0)
		ribbon.Position = UDim2.fromOffset(px + pw, py)
	end
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (math.huge = no limit).
]]
function HoverboardView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local width = math.max(560, math.min(m.Width, maxWidth - 24))
	local columns = HoverboardView.columns(width, compact)
	refs.Columns = columns
	local rows = math.ceil(#refs.Cards / columns)
	local wantHeight = if rows > 1 then m.Height + 300 else m.Height
	local height = math.max(380, math.min(wantHeight, maxHeight - 16))
	refs.Root.Size = UDim2.fromOffset(width, height)
	refs.Root.AnchorPoint = if compact then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	refs.Root.Position = if compact then UDim2.new(0.5, 0, 1, -10) else UDim2.fromScale(0.5, 0.5)
	-- the band: the icon, the title (with its shadow) and the X
	ElevatorView.fitWindow(refs.Chrome, refs.Icon, m.Band, m.Title, m.Icon, m.Close)
	-- the pitch line under the band
	refs.Subtitle.Position = UDim2.fromOffset(m.Pad, m.Band + 2)
	refs.Subtitle.Size = UDim2.new(1, -m.Pad * 2, 0, m.Header - m.Band - 4)
	refs.Subtitle.TextSize = m.Text
	refs.Message.Position = refs.Subtitle.Position
	refs.Message.Size = refs.Subtitle.Size
	refs.Message.TextSize = m.Text
	refs.Footer.Visible = not compact
	refs.Footer.Size = UDim2.fromOffset(refs.Footer.Size.X.Offset, math.max(m.Footer, 30))
	-- the cards: one row of five, or 3 + 2 (the second row centred); on a very short screen
	-- (a 568 x 320 phone) the cards keep MinHeight and the page scrolls (the next row peeks in)
	local top = m.Header
	local bottom = if compact then m.Pad else m.Pad + 14
	local page = refs.CardPage
	page.Position = UDim2.fromOffset(m.Pad - CARD_MARGIN, top - CARD_MARGIN)
	page.Size = UDim2.new(1, -(m.Pad - CARD_MARGIN) * 2, 1, -(top + bottom) + CARD_MARGIN * 2)
	local pageHeight = height - top - bottom
	local fitHeight = math.floor((pageHeight - m.Gap * (rows - 1)) / rows)
	local scrolls = rows > 1 and fitHeight < m.MinHeight
	refs.Scrolls = scrolls
	local barRoom = if scrolls then page.ScrollBarThickness + 4 else 0
	local inner = width - m.Pad * 2 - barRoom
	local cardWidth = math.floor((inner - m.Gap * (columns - 1)) / columns)
	local cardHeight = if scrolls then m.MinHeight else fitHeight
	for i, card in refs.Cards do
		local row = math.floor((i - 1) / columns)
		local column = (i - 1) % columns
		local inRow = math.min(columns, #refs.Cards - row * columns)
		local rowWidth = inRow * cardWidth + (inRow - 1) * m.Gap
		local x = CARD_MARGIN + (inner - rowWidth) / 2 + column * (cardWidth + m.Gap) + cardWidth / 2
		local y = CARD_MARGIN + row * (cardHeight + m.Gap) + cardHeight / 2
		card.Frame.Position = UDim2.fromOffset(x, y)
		card.Frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		card.Frame:SetAttribute("BaseY", y)
		layoutCard(card, m, cardWidth, cardHeight)
	end
	page.CanvasSize = UDim2.fromOffset(0, CARD_MARGIN * 2 + rows * cardHeight + (rows - 1) * m.Gap)
	page.ScrollingEnabled = scrolls
	page.ScrollBarImageTransparency = if scrolls then 0.2 else 1
	-- a new layout re-sized the buttons' text
	for _, card in refs.Cards do
		styleButton(card.Look, card.State, card.Look.Label.Text, if card.State == "Soon" then m.ButtonText - 6 else m.ButtonText)
	end
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

-- The panel `seconds` into its opening (0 = closed, OpenTime = open): the panel
-- pops in, the cards drop in one after another. Closing plays it backwards.
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
		Riding = false,
	}
	HoverboardView.setRiding(ride, false)
	return ride
end

-- RIDE (violet) while walking, STOP (red) while riding; `hint` = the key chip
-- text ("H"), "" hides it (touch); `glyph` = a gamepad image shown instead.
function HoverboardView.setRiding(ride: RideButton, riding: boolean, hint: string?, glyph: string?)
	ride.Riding = riding
	if riding then
		setGradient3(ride.Gradient, rgb(255, 140, 120), rgb(236, 70, 66), rgb(176, 34, 44))
		ride.Ring.Color = rgb(90, 14, 20)
		ride.Label.Text = "STOP"
	else
		setGradient3(ride.Gradient, rgb(176, 116, 255), rgb(118, 56, 230), rgb(70, 28, 160))
		ride.Ring.Color = INK
		ride.Label.Text = "RIDE"
	end
	local image = glyph or ""
	ride.Glyph.Image = image
	ride.Glyph.Visible = image ~= ""
	local text = hint or "H"
	ride.Key.Text = text
	ride.Key.Visible = image == "" and text ~= ""
end

return HoverboardView
