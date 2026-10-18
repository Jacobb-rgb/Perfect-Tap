--[[
	Hoverboards on screen (pure builder + pure helpers; HoverboardController
	fills it in and animates it). Same look as the elevator panel
	(ElevatorView: dark navy panel in a glowing neon frame, chunky buttons).

	  panel    header: a small board icon, a big "HOVERBOARDS" and a subtitle
	           ("Ride anywhere, faster." or the last server message); a red X;
	           a footer pill with the control hint (not on phones)
	  cards    one per board (HoverboardData order: 3 coin boards, then the 2
	           Robux boards with a gold "ROBUX" ribbon): the board drawn from
	           Frames (side view, nose left, its hover glow), the name, the speed
	           with "+28%", one perk line, the price ($ coin or R$) and the
	           button: BUY (green) / BUY with a lock (grey: not enough coins) /
	           EQUIP (blue) / EQUIPPED (navy, a check) / R$ 49 (green, Robux) /
	           COMING SOON (grey: the product id is still 0)
	  side     the "Boards" button for the left side menu (sideButton: the
	           elevator's size and shape, violet, a little board on it)
	  ride     the RIDE toggle for the HUD's right menu (rideButton): RIDE /
	           STOP with a key chip ("H") or the gamepad glyph

	Every bit of art is drawn from Frames (images need uploads under the
	owner's account; set BoardImages[boardId] / SideIconImage to asset ids
	and ImageLabels are used instead).

	Designed for 720 design units of height (HudController scales every
	TerraForge gui). Five cards in a row when they fit, else 3 + 2; the
	compact layout (phones, uiScale 0.62) has 72-unit buttons (about 44 pt).
	A gamepad selection stays inside the panel (SelectionGroup).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoverboardData = require(Shared.Config.HoverboardData)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local HudView = require(script.Parent.HudView)
local ElevatorView = require(script.Parent.ElevatorView)

local HoverboardView = {}

export type CardState = "Buy" | "BuyLocked" | "Equip" | "Equipped" | "Robux" | "Soon"
export type HintKind = "Mouse" | "Gamepad" | "Touch"

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

export type Card = {
	Board: HoverboardData.Board,
	Frame: Frame,
	Scale: UIScale,
	Stroke: UIStroke,
	Glow: Frame,
	ArtBack: Frame,
	Canvas: Frame,
	CanvasScale: UIScale,
	Ribbon: Frame?,
	Name: TextLabel,
	Speed: TextLabel,
	Bonus: TextLabel,
	Perk: TextLabel,
	PriceRow: Frame,
	Coin: Frame,
	Robux: Frame,
	Price: TextLabel,
	Button: TextButton,
	Look: ButtonRefs,
	State: CardState,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame,
	Pop: UIScale,
	Panel: Frame,
	Icon: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	Subtitle: TextLabel,
	Message: TextLabel,
	Close: TextButton,
	CloseLook: ButtonRefs,
	CardPage: Frame,
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

export type SideButton = {
	Holder: Frame,
	Button: TextButton,
	Scale: UIScale,
	Label: TextLabel,
	Glyph: ImageLabel,
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
local NAVY_TOP = rgb(26, 34, 72)
local NAVY_BOTTOM = rgb(12, 16, 38)
local NAVY_CARD = rgb(20, 26, 54)
local NAVY_DEEP = rgb(10, 14, 32)
local NEON = rgb(70, 170, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local NEON_DEEP = rgb(36, 84, 190)
local TEXT = rgb(245, 248, 255)
local TEXT_SOFT = rgb(196, 208, 236)
local GOLD = rgb(255, 204, 64)
local ROBUX_GREEN = rgb(120, 236, 120)
local INK = rgb(10, 12, 26)

HoverboardView.Title = "HOVERBOARDS"
HoverboardView.Pitch = "Ride anywhere, faster. Bought once, yours forever."
HoverboardView.OpenTime = 0.42
HoverboardView.CloseTime = 0.2
HoverboardView.SideButtonSize = ElevatorView.SideButtonSize
-- asset ids for the owner's uploaded art ("" = draw it from Frames)
HoverboardView.BoardImages = {} :: { [string]: string }
HoverboardView.SideIconImage = ""

type Metrics = {
	Width: number,
	Height: number,
	Pad: number,
	Header: number,
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
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1080,
		Height = 470,
		Pad = 20,
		Header = 104,
		Title = 60,
		Icon = 62,
		Text = 20,
		Gap = 14,
		Button = 56,
		ButtonText = 24,
		Name = 22,
		Small = 17,
		Price = 26,
		Close = 60,
		Footer = 36,
		MinCard = 176,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1320,
		Height = 560,
		Pad = 18,
		Header = 92,
		Title = 48,
		Icon = 58,
		Text = 22,
		Gap = 12,
		Button = 72,
		ButtonText = 27,
		Name = 25,
		Small = 20,
		Price = 28,
		Close = 68,
		Footer = 0,
		MinCard = 230,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- What a board's card offers: owned / equipped, else buy (coins) or Robux.
function HoverboardView.cardState(board: HoverboardData.Board, owned: { [string]: boolean }, equipped: string, coins: any): CardState
	local state: CardState = "BuyLocked"
	if owned[board.Id] then
		state = if equipped == board.Id then "Equipped" else "Equip"
	elseif board.Kind == "Robux" then
		state = if HoverboardData.canPrompt(board) then "Robux" else "Soon"
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
	NeonComet = function(c: Frame, col: HoverboardData.Colors)
		hoverGlow(c, col.Glow, 104, 110)
		local trail = block(c, "Trail", 160, 50, 40, 10, WHITE, 0, 5)
		UIKit.new("UIGradient", {
			Color = ColorSequence.new(col.Glow, col.Glow2),
			Transparency = NumberSequence.new(0.1, 1),
			Rotation = 0,
		}, trail)
		block(c, "Fin", 134, 26, 20, 26, col.Glow2:Lerp(BLACK, 0.15), 28, 3)
		local body = block(c, "Body", 58, 44, 104, 16, WHITE, 0, 4)
		gradient3(body, col.Main:Lerp(WHITE, 0.25), col.Main, col.Main:Lerp(BLACK, 0.35))
		ring(body, 2, INK, 0.2)
		local nose = centred(c, "Nose", 58, 52, 16, 16, col.Main, 45)
		ring(nose, 2, INK, 0.2)
		block(c, "Stripe", 62, 52, 96, 3, col.Glow)
		block(c, "Thruster", 160, 46, 8, 12, col.Main:Lerp(BLACK, 0.4), 0, 2)
		local halo = centred(c, "Ring", 36, 52, 40, 9, col.Glow2, -12, true)
		halo.BackgroundTransparency = 0.25
		local orb = centred(c, "Orb", 36, 52, 26, 26, col.Glow, 0, true)
		ring(orb, 2, col.Trim, 0.3)
		centred(c, "OrbCore", 34, 49, 11, 11, col.Trim, 0, true)
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

local function tint(icon: Instance, color: Color3)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.Name == "Ink" then
			d.BackgroundColor3 = color
		end
	end
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

-- the Robux hexagon (two rotated squares with a hole)
function Icons.robux(parent: Instance, color: Color3): Frame
	local box = iconBox(parent, "Robux")
	ink(box, 0.5, 0.5, 0.78, 0.78, color, 0, 0.18)
	ink(box, 0.5, 0.5, 0.72, 0.72, color, 45, 0.12)
	local hole = ink(box, 0.5, 0.5, 0.32, 0.32, INK, 45, 0.1)
	hole.Name = "Hole"
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

---------------------------------------------------------------- chunky buttons

type ButtonStyle = {
	Top: Color3,
	Mid: Color3,
	Bottom: Color3,
	Lip: Color3,
	Edge: Color3,
	Text: Color3,
	TextStroke: Color3,
	Icon: string?,
	IconColor: Color3,
}

local STYLES: { [string]: ButtonStyle } = {
	Buy = {
		Top = rgb(170, 250, 130),
		Mid = rgb(76, 214, 72),
		Bottom = rgb(46, 172, 54),
		Lip = rgb(22, 106, 34),
		Edge = INK,
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
		Text = rgb(172, 178, 200),
		TextStroke = rgb(18, 20, 30),
		Icon = "Lock",
		IconColor = rgb(166, 172, 194),
	},
	Equip = {
		Top = rgb(130, 210, 255),
		Mid = rgb(56, 150, 246),
		Bottom = rgb(34, 104, 214),
		Lip = rgb(18, 58, 140),
		Edge = INK,
		Text = TEXT,
		TextStroke = rgb(12, 40, 110),
		Icon = nil,
		IconColor = TEXT,
	},
	Equipped = {
		Top = rgb(30, 46, 98),
		Mid = rgb(18, 28, 66),
		Bottom = rgb(12, 18, 46),
		Lip = rgb(8, 12, 30),
		Edge = NEON,
		Text = rgb(140, 210, 255),
		TextStroke = rgb(6, 16, 50),
		Icon = "Check",
		IconColor = rgb(110, 214, 92),
	},
	Robux = {
		Top = rgb(170, 250, 130),
		Mid = rgb(76, 214, 72),
		Bottom = rgb(46, 172, 54),
		Lip = rgb(22, 106, 34),
		Edge = INK,
		Text = TEXT,
		TextStroke = rgb(18, 84, 28),
		Icon = "Robux",
		IconColor = TEXT,
	},
	Soon = {
		Top = rgb(70, 76, 98),
		Mid = rgb(54, 60, 80),
		Bottom = rgb(42, 47, 64),
		Lip = rgb(24, 27, 38),
		Edge = INK,
		Text = rgb(172, 178, 200),
		TextStroke = rgb(18, 20, 30),
		Icon = "Clock",
		IconColor = rgb(166, 172, 194),
	},
	Close = {
		Top = rgb(255, 128, 112),
		Mid = rgb(236, 62, 62),
		Bottom = rgb(196, 38, 44),
		Lip = rgb(120, 22, 28),
		Edge = INK,
		Text = TEXT,
		TextStroke = rgb(90, 14, 20),
		Icon = nil,
		IconColor = TEXT,
	},
}
HoverboardView.ButtonStyles = STYLES

local ICON_MAKERS: { [string]: (Instance, Color3) -> Frame } = {
	Check = Icons.check,
	Lock = Icons.lock,
	Robux = Icons.robux,
	Clock = Icons.clock,
}

local function chunkyButton(parent: Instance, name: string): ButtonRefs
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
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local made: { [string]: Frame } = {}
	for kind, maker in ICON_MAKERS do
		local icon = maker(row, TEXT)
		icon.LayoutOrder = 1
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

local function styleButton(look: ButtonRefs, styleName: string, text: string, textSize: number, title: boolean?)
	local style = STYLES[styleName]
	look.Style = styleName
	setGradient3(look.Gradient, style.Top, style.Mid, style.Bottom)
	look.Holder.BackgroundColor3 = style.Lip
	look.Edge.Color = style.Edge
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
end

---------------------------------------------------------------- building

local function newCard(page: Frame, board: HoverboardData.Board): Card
	local robux = board.Kind == "Robux"
	local frame: Frame = UIKit.new("Frame", {
		Name = board.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = NAVY_CARD,
		BorderSizePixel = 0,
		LayoutOrder = board.Order,
	}, page)
	UIKit.corner(frame, 16)
	local stroke = ring(frame, 3, if robux then GOLD else board.Colors.Glow)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
	-- the equipped card's glow ring
	local glow: Frame = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, frame)
	UIKit.corner(glow, 16)
	ring(glow, 9, NEON, 0.55)
	-- the art box: a dark gradient in the board's glow colour, the board on it
	local artBack: Frame = UIKit.new("Frame", {
		Name = "ArtBack",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(artBack, 12)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(NAVY_DEEP, board.Colors.Glow:Lerp(NAVY_DEEP, 0.6)),
		Rotation = 90,
	}, artBack)
	local canvas: Frame = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 110),
	}, frame)
	local canvasScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, canvas)
	HoverboardView.drawBoard(canvas, board)
	local ribbon: Frame? = nil
	if robux then
		local r: Frame = UIKit.new("Frame", {
			Name = "Ribbon",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(78, 24),
			ZIndex = 3,
		}, frame)
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		gradient3(r, rgb(255, 232, 140), GOLD, rgb(214, 150, 30))
		ring(r, 2, INK)
		UIKit.label(r, "ROBUX", 15, {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			FontFace = Theme.TitleFont,
			TextColor3 = TEXT,
			TextWrapped = false,
			ZIndex = 3,
		})
		ribbon = r
	end
	local name = UIKit.label(frame, board.Name, 22, {
		Name = "BoardName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextColor3 = TEXT,
	})
	local speed = UIKit.label(frame, HoverboardView.speedText(board), 18, {
		Name = "Speed",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextColor3 = TEXT_SOFT,
	})
	local bonus = UIKit.label(frame, HoverboardView.bonusText(board), 16, {
		Name = "Bonus",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		TextWrapped = false,
		TextColor3 = TEXT,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bonus)
	gradient3(bonus, rgb(130, 236, 110), rgb(64, 186, 60), rgb(40, 140, 44))
	local perk = UIKit.label(frame, board.Perks[2] or board.Perks[1] or "", 16, {
		Name = "Perk",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextColor3 = if robux then GOLD else TEXT_SOFT,
	})
	local priceRow: Frame = UIKit.new("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
	}, frame)
	UIKit.list(priceRow, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local coin = HudView.coinIcon(priceRow, 24)
	coin.LayoutOrder = 1
	coin.Visible = not robux
	local robuxIcon = Icons.robux(priceRow, ROBUX_GREEN)
	robuxIcon.LayoutOrder = 1
	robuxIcon.Visible = robux
	local price = UIKit.label(priceRow, HoverboardView.priceText(board), 24, {
		Name = "Price",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		FontFace = Theme.TitleFont,
		TextColor3 = if robux then ROBUX_GREEN else Theme.Coin,
	})
	local look = chunkyButton(frame, "Action")
	return {
		Board = board,
		Frame = frame,
		Scale = scale,
		Stroke = stroke,
		Glow = glow,
		ArtBack = artBack,
		Canvas = canvas,
		CanvasScale = canvasScale,
		Ribbon = ribbon,
		Name = name,
		Speed = speed,
		Bonus = bonus,
		Perk = perk,
		PriceRow = priceRow,
		Coin = coin,
		Robux = robuxIcon,
		Price = price,
		Button = look.Button,
		Look = look,
		State = "Buy",
	}
end

local function newFooter(root: Frame): (Frame, TextLabel, ImageLabel)
	local footer: Frame = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(460, 36),
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
	local icon: Frame = UIKit.new("Frame", {
		Name = "HeaderIcon",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, panel)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, icon)
	gradient3(icon, rgb(170, 100, 255), rgb(118, 56, 220), rgb(72, 30, 160))
	ring(icon, 3, INK)
	local board = Icons.board(icon, TEXT, rgb(120, 230, 255))
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.5)
	board.Size = UDim2.fromScale(0.8, 0.8)
	local titleShadow = UIKit.label(panel, HoverboardView.Title, 56, {
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
	local title = UIKit.label(panel, HoverboardView.Title, 56, {
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
	local subtitle = UIKit.label(panel, HoverboardView.Pitch, 20, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextColor3 = TEXT_SOFT,
	})
	local message = UIKit.label(panel, "", 20, {
		Name = "Message",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextColor3 = Theme.Bad,
		Visible = false,
	})
	-- cards
	local page: Frame = UIKit.new("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
	}, panel)
	local cards: { Card } = {}
	for _, b in HoverboardData.List do
		table.insert(cards, newCard(page, b))
	end
	-- on the root (over the frame): the X and the footer pill
	local closeLook = chunkyButton(root, "Close")
	closeLook.Holder.AnchorPoint = Vector2.new(1, 0)
	styleButton(closeLook, "Close", "X", 36, true)
	local footer, hint, glyph = newFooter(root)
	local refs: Refs = {
		Gui = gui,
		Root = root,
		Pop = pop,
		Panel = panel,
		Icon = icon,
		Title = title,
		TitleShadow = titleShadow,
		Subtitle = subtitle,
		Message = message,
		Close = closeLook.Button,
		CloseLook = closeLook,
		CardPage = page,
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
		card.Glow.Visible = state == "Equipped"
		card.Button.Selectable = state ~= "Equipped"
		local owns = state == "Equip" or state == "Equipped"
		card.PriceRow.Visible = not owns
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

-- Inside a card: the art on top, the name, speed + bonus, the perk line and the
-- price, the button at the bottom. Short cards (phones, two rows) drop the perk
-- line and put the price at the end of the speed line.
local function layoutCard(card: Card, m: Metrics, w: number, h: number)
	local pad = 12
	local buttonHeight = m.Button
	local textRows = (m.Name + 6) + (m.Small + 8)
	local full = pad + 70 + 8 + textRows + (m.Small + 8) + (m.Price + 4) + 8 + buttonHeight + pad
	local tight = h < full
	local below = if tight then textRows + 8 else textRows + (m.Small + 8) + (m.Price + 4) + 8
	local artHeight = math.max(40, h - pad - 8 - below - buttonHeight - pad)
	card.ArtBack.Position = UDim2.fromOffset(pad, pad)
	card.ArtBack.Size = UDim2.new(1, -pad * 2, 0, artHeight)
	card.CanvasScale.Scale = math.min(artHeight * 1.12 / 110, (w - pad * 2) / 200)
	card.Canvas.Position = UDim2.new(0.5, 0, 0, pad + artHeight / 2)
	local y = pad + artHeight + 8
	card.Name.Position = UDim2.fromOffset(pad + 2, y)
	card.Name.Size = UDim2.new(1, -pad * 2, 0, m.Name + 4)
	card.Name.TextSize = m.Name
	y += m.Name + 6
	card.Speed.TextSize = m.Small
	local speedWidth = math.ceil(ElevatorView.measure(card.Speed.Text, m.Small)) + 4
	card.Speed.Position = UDim2.fromOffset(pad + 2, y)
	card.Speed.Size = UDim2.fromOffset(speedWidth, m.Small + 6)
	card.Bonus.TextSize = m.Small - 2
	local bonusWidth = math.ceil(ElevatorView.measure(card.Bonus.Text, m.Small - 2)) + 16
	card.Bonus.Position = UDim2.fromOffset(pad + 2 + speedWidth + 6, y + 1)
	card.Bonus.Size = UDim2.fromOffset(bonusWidth, m.Small + 4)
	local priceSize = if tight then m.Small + 2 else m.Price
	card.Price.TextSize = priceSize
	local priceWidth = math.ceil(ElevatorView.measure(card.Price.Text, priceSize, true)) + 6
	card.Price.Size = UDim2.fromOffset(priceWidth, priceSize + 4)
	card.Coin.Size = UDim2.fromOffset(priceSize - 2, priceSize - 2)
	card.Robux.Size = UDim2.fromOffset(priceSize - 2, priceSize - 2)
	card.Perk.Visible = not tight
	if tight then
		local rowWidth = priceSize + 6 + priceWidth
		card.PriceRow.Position = UDim2.fromOffset(w - pad - rowWidth, y)
		card.PriceRow.Size = UDim2.fromOffset(rowWidth, m.Small + 6)
	else
		y += m.Small + 8
		card.Perk.TextSize = m.Small - 1
		card.Perk.Position = UDim2.fromOffset(pad + 2, y)
		card.Perk.Size = UDim2.new(1, -pad * 2, 0, m.Small + 4)
		y += m.Small + 8
		card.PriceRow.Position = UDim2.fromOffset(pad + 2, y)
		card.PriceRow.Size = UDim2.new(1, -pad * 2, 0, m.Price + 4)
	end
	local holder = card.Look.Holder
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.new(0, pad, 1, -pad)
	holder.Size = UDim2.new(1, -pad * 2, 0, buttonHeight)
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
	-- header
	refs.Icon.Position = UDim2.fromOffset(m.Pad + 4, 16)
	refs.Icon.Size = UDim2.fromOffset(m.Icon, m.Icon)
	local textLeft = m.Pad + 4 + m.Icon + 14
	local titleWidth = width - textLeft - (m.Close + m.Pad + 12)
	refs.Title.Position = UDim2.fromOffset(textLeft, 8)
	refs.Title.Size = UDim2.fromOffset(titleWidth, m.Title + 4)
	refs.Title.TextSize = m.Title
	refs.TitleShadow.Position = UDim2.fromOffset(textLeft + 2, 12)
	refs.TitleShadow.Size = refs.Title.Size
	refs.TitleShadow.TextSize = m.Title
	refs.Subtitle.Position = UDim2.fromOffset(textLeft, 8 + m.Title + 4)
	refs.Subtitle.Size = UDim2.fromOffset(titleWidth, m.Text + 8)
	refs.Subtitle.TextSize = m.Text
	refs.Message.Position = refs.Subtitle.Position
	refs.Message.Size = refs.Subtitle.Size
	refs.Message.TextSize = m.Text
	local close = refs.CloseLook.Holder
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -12, 0, 16)
	refs.CloseLook.Label.TextSize = if compact then 40 else 36
	refs.Footer.Visible = not compact
	refs.Footer.Size = UDim2.fromOffset(refs.Footer.Size.X.Offset, math.max(m.Footer, 30))
	-- the cards: one row of five, or 3 + 2 (the second row centred)
	local top = m.Header
	local bottom = if compact then m.Pad else m.Pad + 14
	refs.CardPage.Position = UDim2.fromOffset(m.Pad, top)
	refs.CardPage.Size = UDim2.new(1, -m.Pad * 2, 1, -(top + bottom))
	local inner = width - m.Pad * 2
	local cardWidth = math.floor((inner - m.Gap * (columns - 1)) / columns)
	local cardHeight = math.floor((height - top - bottom - m.Gap * (rows - 1)) / rows)
	for i, card in refs.Cards do
		local row = math.floor((i - 1) / columns)
		local column = (i - 1) % columns
		local inRow = math.min(columns, #refs.Cards - row * columns)
		local rowWidth = inRow * cardWidth + (inRow - 1) * m.Gap
		local x = (inner - rowWidth) / 2 + column * (cardWidth + m.Gap) + cardWidth / 2
		local y = row * (cardHeight + m.Gap) + cardHeight / 2
		card.Frame.Position = UDim2.fromOffset(x, y)
		card.Frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		card.Frame:SetAttribute("BaseY", y)
		layoutCard(card, m, cardWidth, cardHeight)
	end
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

---------------------------------------------------------------- the side menu button

--[[
	The "Boards" button of the left side menu (the elevator button's size and
	shape): a violet rounded square with a glowing board on it, speed lines,
	"Boards" under it, a gamepad glyph slot top-right.
]]
function HoverboardView.sideButton(parent: Instance, size: number): SideButton
	local holder: Frame = UIKit.new("Frame", {
		Name = "BoardsButton",
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
	gradient3(button, rgb(156, 92, 255), rgb(96, 44, 206), rgb(54, 20, 138))
	ring(button, 4, rgb(214, 176, 255))
	local scale: UIScale = UIKit.new("UIScale", { Name = "Bounce", Scale = 1 }, button)
	local glow: Frame = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, button)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, glow)
	ring(glow, 9, rgb(170, 100, 255), 0.65)
	if HoverboardView.SideIconImage ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = HoverboardView.SideIconImage,
			ScaleType = Enum.ScaleType.Fit,
		}, button)
	else
		local canvas: Frame = UIKit.new("Frame", {
			Name = "Art",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(200, 110),
			BackgroundTransparency = 1,
		}, button)
		UIKit.new("UIScale", { Scale = size * 0.92 / 200 }, canvas)
		HoverboardView.drawBoard(canvas, HoverboardData.ById.NeonComet)
		for i = 1, 3 do
			local line = UIKit.new("Frame", {
				Name = "Speed",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.08, 0.2 + 0.09 * i),
				Size = UDim2.fromScale(0.26 - 0.05 * i, 0.04),
				BackgroundColor3 = rgb(230, 210, 255),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
			}, button)
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, line)
		end
	end
	local label = UIKit.label(holder, "Boards", 18, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 16, 0, 22),
		TextColor3 = TEXT,
		TextWrapped = false,
	})
	local labelStroke = label:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Color = rgb(40, 14, 90)
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
	return { Holder = holder, Button = button, Scale = scale, Label = label, Glyph = glyph }
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
