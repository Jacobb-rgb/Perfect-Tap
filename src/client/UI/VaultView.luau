--[[
	The Blaster Vault shop window (VaultController opens it at the vault
	counter). Pure builders (only Instance creation), so the Lune preview
	draws it with the same code.

	One card per blaster level 2..10 (+ "STAR BLASTERS": the Star Forge's
	weapons above them, REBIRTH tells where): the weapon
	case drawn in its ore colours, LV, the blaster's name, its damage, the
	price and one button: BUY on your next level (greyed with the price in
	red while you can't afford it), OWNED below it, LOCKED above it. You can
	only buy your next level (VaultService.refusal), so the next card wears
	the gold outline and a NEXT ribbon.

	PC: the cards in a 5 x 2 grid. Phones, tablets and TVs (compact): one row
	of bigger cards that scrolls sideways, every button at least 44 pt.

	The look is the light "Bubble" style the UI chat is building (owner's
	pick, branch ui/light: Config/BubbleTheme + UI/Bubble). Until that lands
	on main the same values live in VaultView.Style; switching later means
	pointing Style at BubbleTheme (the names match).

	With UIConfig.lightUI() on (the light UI, ships off) the window matches the
	other light windows (Bubble.window): the orange header is a full-width band
	with the 3D vault icon popping out, the red X sits on the panel's corner and
	the coins pill shows the 3D coin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local CaseBuilder = require(Shared.Builders.CaseBuilder)
local Format = require(Shared.Util.Format)
local UIConfig = require(Shared.Config.UIConfig)
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)
local Pop = require(script.Parent.Pop)
local TechShopView = require(script.Parent.TechShopView)

local VaultView = {}

local rgb = Color3.fromRGB

export type Role = { Top: Color3, Base: Color3, Lip: Color3 }

-- = Config/BubbleTheme: the game's look (the store-card style, owner 2026-10-20)
local Kit = require(Shared.Config.BubbleTheme)
VaultView.Style = {
	Font = Kit.Font,
	TitleFont = Kit.TitleFont,
	Outline = Kit.Outline,
	Shadow = Kit.Shadow,
	ShadowTransparency = Kit.ShadowTransparency,
	Panel = Kit.Panel,
	PanelTint = Kit.PanelTint,
	Ink = Kit.Ink,
	InkSoft = Kit.InkSoft,
	White = Kit.White,
	Gold = Kit.Gold,
	Good = Kit.Good,
	Bad = Kit.Bad,
	Corner = Kit.Corner,
	Stroke = Kit.Stroke,
	TextStroke = Kit.TextStroke,
	Lip = Kit.Lip,
	GlossTransparency = Kit.GlossTransparency,
	Roles = {
		Vault = Kit.Roles.Vault,
		Go = Kit.Roles.Go,
		Danger = Kit.Roles.Danger,
		Plain = Kit.Roles.Plain,
	} :: { [string]: Role },
}
local S = VaultView.Style

VaultView.PhoneScale = 0.62 -- HudController's floor (phones)
VaultView.MinTouch = 44 -- points
VaultView.CloseRange = 24 -- studs from the counter: the window closes (VaultService.Range is 30)
VaultView.FirstLevel = 2
VaultView.Separator = "   ·   "

-- what a refusal (VaultResult.Reason, VaultService.Reasons) says
VaultView.ReasonText = {
	Owned = "You have this blaster already",
	Locked = "Buy the level before it first",
	Max = "You have the best blaster!",
	StarForge = "Star blasters wait in the Star Forge after a rebirth",
	NoCoins = "Not enough coins",
	TooFar = "Walk back to the counter",
	BadLevel = "That case isn't for sale",
	NoData = "Your save is still loading",
	Waiting = "Wait a moment...",
	NoAnswer = "No answer from the server: try again",
} :: { [string]: string }

function VaultView.reasonText(reason: any): string
	return if type(reason) == "string" and VaultView.ReasonText[reason]
		then VaultView.ReasonText[reason]
		else "You can't buy that right now"
end

---------------------------------------------------------------- the cards (pure)

export type CardState = "Owned" | "Next" | "Locked" | "Soon"

export type Card = {
	Level: number,
	Ore: string,
	Name: string,
	Damage: number,
	Price: number?,
	State: CardState,
	CanBuy: boolean,
	Reason: string?, -- why BUY can't buy (VaultService.Reasons)
}

--[[
	The cards for a player at blaster `level` with `coins` (the same rules as
	VaultService.refusal: only the next level, coins only; `runIncome` = the
	State's Rebirth.RunIncome: the rebirth run's price floor).
]]
function VaultView.cards(level: number, coins: number, runIncome: number?): { Card }
	local current = BlasterData.get(level).Level
	local list: { Card } = {}
	for lv = VaultView.FirstLevel, BlasterData.MaxLevel do
		local ore = BlasterData.vaultOre(lv)
		local price = BlasterData.vaultPrice(lv, runIncome)
		local state: CardState = if lv <= current then "Owned" elseif lv == current + 1 then "Next" else "Locked"
		local reason: string? = nil
		if state == "Owned" then
			reason = "Owned"
		elseif state == "Locked" then
			reason = "Locked"
		elseif not price or coins < price then
			reason = "NoCoins"
		end
		table.insert(list, {
			Level = lv,
			Ore = ore,
			Name = BlasterData.displayName(lv, ore),
			Damage = BlasterData.damage(lv, ore),
			Price = price,
			State = state,
			CanBuy = reason == nil,
			Reason = reason,
		})
	end
	local soon = BlasterData.ByLevel[BlasterData.MaxLevel + 1]
	if soon and soon.ComingSoon then
		table.insert(list, {
			Level = soon.Level,
			Ore = "",
			Name = "Star blasters",
			Damage = 0,
			Price = nil,
			State = "Soon",
			CanBuy = false,
			Reason = "StarForge",
		})
	end
	return list
end

-- The button text of a card.
function VaultView.buttonText(card: Card): string
	if card.State == "Owned" then
		return "OWNED"
	elseif card.State == "Locked" then
		return "LOCKED"
	elseif card.State == "Soon" then
		return "REBIRTH"
	end
	return "BUY"
end

---------------------------------------------------------------- layout math (pure)

export type Rect = { X: number, Y: number, W: number, H: number }

-- Where everything sits on a card (design units, from the card face's top left).
export type Slots = {
	Pill: Rect,
	Icon: Rect,
	Name: Rect,
	Damage: Rect,
	Price: Rect,
	Button: Rect, -- the button's face (its lip shows S.Lip below)
	NameSize: number,
	DamageSize: number,
	PriceSize: number,
	ButtonSize: number,
}

export type Grid = {
	Compact: boolean, -- phones, tablets, TVs: wide cards in one row that scrolls
	Cols: number,
	Rows: number,
	TileW: number,
	TileH: number, -- the card face (the holder is S.Lip taller)
	Gap: number,
	Pad: number,
	HeaderH: number,
	InfoH: number,
	HintH: number,
	PanelW: number,
	PanelH: number, -- the panel face
	ViewW: number, -- the visible width of the cards area
	CanvasW: number, -- the whole row
	Slots: Slots,
}

-- Phones, tablets and TVs: bigger cards in one row (the same rule as the Tech shop).
function VaultView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { X = x, Y = y, W = w, H = h }
end

-- PC: a tall card (pill, case, name, damage, price, BUY under each other).
local function tallSlots(w: number): Slots
	local iconW = math.floor(w * 0.72)
	local iconH = math.floor(iconW * 0.62)
	local iconY = 34
	local nameY = iconY + iconH + 6
	local nameH = math.ceil(16 * 2.25)
	local damageY = nameY + nameH
	local priceY = damageY + 20
	local buttonY = priceY + 28
	return {
		Pill = rect(8, 8, 56, 26),
		Icon = rect(math.floor((w - iconW) / 2), iconY, iconW, iconH),
		Name = rect(8, nameY, w - 16, nameH),
		Damage = rect(8, damageY, w - 16, 18),
		Price = rect(12, priceY, w - 24, 24),
		Button = rect(8, buttonY, w - 16, 42),
		NameSize = 16,
		DamageSize = 14,
		PriceSize = 19,
		ButtonSize = 22,
	}
end

-- Compact: a wide card (the case left, the texts right, price + a big BUY at the bottom).
local function wideSlots(w: number): Slots
	local iconW = 124
	local iconH = math.floor(iconW * 0.62)
	local textX = iconW + 22
	local bottomY = 44 + iconH + 10
	local buttonW = math.floor((w - 20) * 0.55)
	return {
		Pill = rect(10, 10, 66, 30),
		Icon = rect(12, 44, iconW, iconH),
		Name = rect(textX, 44, w - textX - 10, math.ceil(20 * 2.25)),
		Damage = rect(textX, 44 + math.ceil(20 * 2.25) + 2, w - textX - 10, 22),
		Price = rect(14, bottomY + 21, w - buttonW - 36, 30),
		Button = rect(w - buttonW - 10, bottomY, buttonW, 72), -- 72 units = 44.6 pt at the phones' 0.62
		NameSize = 20,
		DamageSize = 17,
		PriceSize = 24,
		ButtonSize = 30,
	}
end

--[[
	The panel and card sizes for `count` cards in maxWidth x maxHeight design
	units (the screen divided by the UI scale, the top bar left out).
]]
function VaultView.grid(count: number, compact: boolean, maxWidth: number, maxHeight: number): Grid
	local g: Grid
	if compact then
		local w = 316
		local slots = wideSlots(w)
		local panelW = math.min(math.floor(maxWidth - 24), 1180)
		local pad = 16
		g = {
			Compact = true,
			Cols = 1,
			Rows = 1,
			TileW = w,
			TileH = slots.Button.Y + slots.Button.H + S.Lip + 10,
			Gap = 14,
			Pad = pad,
			HeaderH = 74,
			InfoH = 36,
			HintH = 0,
			PanelW = panelW,
			PanelH = 0,
			ViewW = panelW - pad * 2,
			CanvasW = count * (w + 14) - 14,
			Slots = slots,
		}
		g.Cols = math.max(1, math.floor((g.ViewW + g.Gap) / (w + g.Gap)))
	else
		local w = 150
		local slots = tallSlots(w)
		local cols = 5
		local pad = 18
		local viewW = cols * w + (cols - 1) * 12
		g = {
			Compact = false,
			Cols = cols,
			Rows = math.max(1, math.ceil(count / cols)),
			TileW = w,
			TileH = slots.Button.Y + slots.Button.H + S.Lip + 8,
			Gap = 12,
			Pad = pad,
			HeaderH = 68,
			InfoH = 30,
			HintH = 28,
			PanelW = viewW + pad * 2,
			PanelH = 0,
			ViewW = viewW,
			CanvasW = viewW,
			Slots = slots,
		}
	end
	g.PanelH = g.HeaderH + g.InfoH + VaultView.rowsHeight(g) + g.HintH + 10
	return g
end

-- The height of the cards area (the rows, their lips, room for the shadow / scroll bar).
function VaultView.rowsHeight(g: Grid): number
	return g.Rows * (g.TileH + S.Lip) + (g.Rows - 1) * g.Gap + 12
end

-- Where card `i` (1-based) sits inside the cards area.
function VaultView.tilePosition(g: Grid, i: number): Vector2
	if g.Compact then
		return Vector2.new((i - 1) * (g.TileW + g.Gap), 0)
	end
	local col = (i - 1) % g.Cols
	local row = math.floor((i - 1) / g.Cols)
	return Vector2.new(col * (g.TileW + g.Gap), row * (g.TileH + S.Lip + g.Gap))
end

---------------------------------------------------------------- the bubble kit

local function corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or S.Corner) }, parent)
end

local function stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or S.Stroke,
		Color = color or S.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

-- White text with the dark outline (on coloured faces).
local function text(parent: Instance, value: string, size: number, props: UIKit.Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = S.White,
		FontFace = S.Font,
		TextWrapped = false,
	}, parent)
	if props then
		for key, v in props do
			(label :: any)[key] = v
		end
	end
	UIKit.new("UIStroke", {
		Thickness = if size >= 26 then 3 else S.TextStroke,
		Color = S.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, label)
	return label
end

-- Dark text with no outline (on white).
local function ink(parent: Instance, value: string, size: number, props: UIKit.Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextSize = size,
		TextColor3 = S.Ink,
		FontFace = S.Font,
		TextWrapped = false,
	}, parent)
	if props then
		for key, v in props do
			(label :: any)[key] = v
		end
	end
	return label
end

export type Body = { Holder: Frame, Face: GuiObject, Lip: Frame, Gradient: UIGradient, Stroke: UIStroke }

--[[
	A chunky "bubble": a soft shadow, a darker lip (the 3D edge), the face
	(a gradient, the navy outline) and a gloss strip. The holder is S.Lip
	taller than the face.
]]
local function body(parent: Instance, r: Role, name: string, clickable: boolean, radius: number?): Body
	local holder = UIKit.new("Frame", { Name = name, BackgroundTransparency = 1 }, parent)
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = S.Shadow,
		BackgroundTransparency = S.ShadowTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S.Lip + 4),
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 1,
	}, holder)
	corner(shadow, radius)
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = r.Lip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, S.Lip),
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 1,
	}, holder)
	corner(lip, radius)
	stroke(lip)
	local face: GuiObject = UIKit.new(if clickable then "TextButton" else "Frame", {
		Name = "Face",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -S.Lip),
		ZIndex = 2,
	}, holder)
	if clickable then
		local button = face :: TextButton
		button.AutoButtonColor = false
		button.Text = ""
	end
	corner(face, radius)
	local outline = stroke(face)
	local grad = gradient(face, r.Top, r.Base)
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = S.GlossTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, 0.4, 0),
		ZIndex = 2,
	}, face)
	corner(gloss, math.max(4, (radius or S.Corner) - 5))
	return { Holder = holder, Face = face, Lip = lip, Gradient = grad, Stroke = outline }
end

local function paint(b: Body, r: Role)
	b.Lip.BackgroundColor3 = r.Lip
	b.Gradient.Color = ColorSequence.new(r.Top, r.Base)
end

-- A gold coin (left of prices).
local function coin(parent: Instance, size: number, props: UIKit.Props?): Frame
	local frame = UIKit.new("Frame", {
		Name = "Coin",
		BackgroundColor3 = S.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, parent)
	if props then
		for key, v in props do
			(frame :: any)[key] = v
		end
	end
	corner(frame, size)
	stroke(frame, 2.5)
	gradient(frame, rgb(255, 228, 120), rgb(245, 172, 20))
	local inner = UIKit.new("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = rgb(255, 214, 80),
		BorderSizePixel = 0,
		ZIndex = 4,
	}, frame)
	corner(inner, size)
	UIKit.new("UIStroke", { Thickness = 1.5, Color = rgb(214, 140, 10) }, inner)
	return frame
end

---------------------------------------------------------------- the case icon

--[[
	A weapon case drawn with frames in its ore look (CaseBuilder.look): the
	body, the lid with its raised panel, the glowing band, straps, the latch
	and the glowing diamond; lava cracks on hot ores, stars on the others.
	`w` = width in design units (height ~0.62 w).
]]
function VaultView.caseIcon(parent: Instance, level: number, oreId: string, w: number): Frame
	local bodyColor, panelColor, glowColor, hot = CaseBuilder.look(oreId)
	local h = math.floor(w * 0.62)
	local root = UIKit.new("Frame", {
		Name = "CaseIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 3,
	}, parent)
	local function box(name: string, x: number, y: number, bw: number, bh: number, color: Color3, z: number, radius: number?): Frame
		local f = UIKit.new("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(math.floor(x * w), math.floor(y * h)),
			Size = UDim2.fromOffset(math.max(1, math.floor(bw * w)), math.max(1, math.floor(bh * h))),
			ZIndex = z,
		}, root)
		if radius then
			corner(f, radius)
		end
		return f
	end
	-- a soft glow under the case
	local glow = box("Glow", 0.06, 0.78, 0.88, 0.2, glowColor, 3, 40)
	glow.BackgroundTransparency = 0.55
	-- feet, body and lid
	box("FootL", 0.12, 0.86, 0.12, 0.1, S.Outline, 3, 3)
	box("FootR", 0.76, 0.86, 0.12, 0.1, S.Outline, 3, 3)
	local base = box("Base", 0.04, 0.42, 0.92, 0.48, bodyColor, 4, 8)
	stroke(base, 3)
	gradient(base, bodyColor:Lerp(Color3.new(1, 1, 1), 0.18), bodyColor)
	local lid = box("Lid", 0.02, 0.14, 0.96, 0.34, bodyColor:Lerp(panelColor, 0.6), 5, 10)
	stroke(lid, 3)
	gradient(lid, panelColor:Lerp(Color3.new(1, 1, 1), 0.25), bodyColor:Lerp(panelColor, 0.4))
	local inset = box("LidPanel", 0.2, 0.2, 0.6, 0.2, panelColor, 6, 5)
	inset.BackgroundTransparency = 0.1
	-- the glowing band where the lid meets the base, the straps, the latch
	local band = box("Band", 0.05, 0.47, 0.9, 0.07, glowColor, 6, 3)
	gradient(band, Color3.new(1, 1, 1):Lerp(glowColor, 0.45), glowColor)
	box("StrapL", 0.2, 0.14, 0.07, 0.76, S.Outline:Lerp(bodyColor, 0.4), 7, 2)
	box("StrapR", 0.73, 0.14, 0.07, 0.76, S.Outline:Lerp(bodyColor, 0.4), 7, 2)
	local latch = box("Latch", 0.44, 0.42, 0.12, 0.16, S.Gold, 8, 3)
	stroke(latch, 2)
	-- the emblem: a glowing diamond on the lid
	local d = math.floor(h * 0.2)
	local gem = UIKit.new("Frame", {
		Name = "Emblem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.3)),
		Size = UDim2.fromOffset(d, d),
		Rotation = 45,
		BackgroundColor3 = glowColor,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, root)
	corner(gem, 3)
	stroke(gem, 2.5)
	gradient(gem, Color3.new(1, 1, 1):Lerp(glowColor, 0.35), glowColor)
	-- lava cracks (hot ores) or stars (cool ores) on the base
	if hot then
		for i, c in { { 0.1, 0.66, 0.14, -18 }, { 0.3, 0.72, 0.1, 24 }, { 0.6, 0.64, 0.12, -30 }, { 0.8, 0.74, 0.08, 12 } } do
			local crack = box("Crack" .. i, c[1], c[2], c[3], 0.035, glowColor, 6)
			crack.Rotation = c[4]
		end
	else
		for i, c in { { 0.1, 0.62 }, { 0.32, 0.76 }, { 0.62, 0.66 }, { 0.84, 0.78 }, { 0.5, 0.82 } } do
			local star = box("Star" .. i, c[1], c[2], 0.025, 0.04, Color3.new(1, 1, 1):Lerp(glowColor, 0.4), 6, 2)
			star.BackgroundTransparency = 0.15
		end
	end
	-- crystal shards from level 4 (more at 7 and 10), like the 3D case
	local shards = if level >= 10 then 3 elseif level >= 7 then 2 elseif level >= 4 then 1 else 0
	for i = 1, shards do
		local x = ({ 0.86, 0.1, 0.5 })[i]
		local tall = ({ 0.34, 0.26, 0.22 })[i]
		local shard = UIKit.new("Frame", {
			Name = "Shard" .. i,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(math.floor(x * w), math.floor(h * (if i == 3 then 0.12 else 0.16))),
			Size = UDim2.fromOffset(math.floor(w * 0.07), math.floor(h * tall)),
			Rotation = ({ 14, -12, 0 })[i],
			BackgroundColor3 = glowColor,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, root)
		corner(shard, 3)
		stroke(shard, 2)
		gradient(shard, Color3.new(1, 1, 1):Lerp(glowColor, 0.4), glowColor)
	end
	return root
end

---------------------------------------------------------------- building

export type Tile = {
	Level: number,
	Holder: Frame,
	Body: Body,
	Face: GuiObject,
	Icon: Frame?,
	Lv: TextLabel,
	LvPill: Frame,
	Name: TextLabel,
	Damage: TextLabel,
	PriceRow: Frame,
	Price: TextLabel,
	Button: TextButton,
	ButtonBody: Body,
	ButtonText: TextLabel,
	Ribbon: Frame,
	Check: Frame,
	Dim: Frame,
	Card: Card?,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame,
	Panel: Frame,
	PanelBody: Body,
	Header: Frame,
	Title: TextLabel,
	CoinsPill: Frame,
	Coins: TextLabel,
	Close: TextButton,
	Info: TextLabel,
	Cards: ScrollingFrame,
	Tiles: { Tile },
	Hint: TextLabel,
	Message: TextLabel,
	Grid: Grid?,
	Level: number, -- the level the cards were built for
}

local function buildTile(parent: Instance, index: number): Tile
	local plain = S.Roles.Plain
	local b = body(parent, plain, "Card" .. index, false, S.Corner)
	local face = b.Face
	b.Gradient.Color = ColorSequence.new(S.Panel, S.PanelTint)
	-- dims a locked card
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = rgb(200, 208, 224),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 12,
		Visible = false,
	}, face)
	corner(dim)
	-- LV pill (top left)
	local pill = UIKit.new("Frame", {
		Name = "LvPill",
		BackgroundColor3 = S.Roles.Vault.Base,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(56, 26),
		ZIndex = 10,
	}, face)
	corner(pill, 13)
	stroke(pill, 2.5)
	gradient(pill, S.Roles.Vault.Top, S.Roles.Vault.Base)
	local lv = text(pill, "LV 2", 17, { Name = "Lv", Size = UDim2.fromScale(1, 1), ZIndex = 11 })
	-- NEXT ribbon (top right) and the owned check
	local ribbon = UIKit.new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = S.Gold,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(58, 26),
		ZIndex = 10,
		Visible = false,
	}, face)
	corner(ribbon, 13)
	stroke(ribbon, 2.5)
	gradient(ribbon, rgb(255, 236, 140), S.Gold)
	text(ribbon, "NEXT", 17, { Name = "Text", Size = UDim2.fromScale(1, 1), ZIndex = 11 })
	local check = UIKit.new("Frame", {
		Name = "Check",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = S.Good,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 10,
		Visible = false,
	}, face)
	corner(check, 14)
	stroke(check, 2.5)
	-- the tick, drawn from two white bars (no glyph: the owner's "text only", NoEmoji.spec):
	-- { centre x, centre y, length, rotation } in the 28 x 28 badge
	for i, arm in { { 10.5, 16.5, 8, 45 }, { 16.5, 14, 14, -50 } } do
		local bar = UIKit.new("Frame", {
			Name = "Tick" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = S.White,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(arm[1], arm[2]),
			Size = UDim2.fromOffset(arm[3], 4),
			Rotation = arm[4],
			ZIndex = 11,
		}, check)
		corner(bar, 2)
	end
	-- the texts
	local name = ink(face, "", 17, {
		Name = "BlasterName",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 10,
	})
	local damage = ink(face, "", 15, { Name = "Damage", TextColor3 = S.InkSoft, ZIndex = 10 })
	local priceRow = UIKit.new("Frame", { Name = "PriceRow", BackgroundTransparency = 1, ZIndex = 10 }, face)
	coin(priceRow, 22, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
	local price = ink(priceRow, "", 20, {
		Name = "Price",
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -28, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	})
	-- the button
	local bb = body(face, S.Roles.Go, "BuyButton", true, 14)
	bb.Holder.ZIndex = 10
	for _, d in bb.Holder:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 10
		end
	end
	local button = bb.Face :: TextButton
	button.Name = "Buy"
	local buttonText = text(button, "BUY", 22, { Name = "Label", Size = UDim2.fromScale(1, 1), ZIndex = 14 })
	return {
		Level = 0,
		Holder = b.Holder,
		Body = b,
		Face = face,
		Icon = nil,
		Lv = lv,
		LvPill = pill,
		Name = name,
		Damage = damage,
		PriceRow = priceRow,
		Price = price,
		Button = button,
		ButtonBody = bb,
		ButtonText = buttonText,
		Ribbon = ribbon,
		Check = check,
		Dim = dim,
		Card = nil,
	}
end

function VaultView.build(): Refs
	local gui = UIKit.screen("TerraForgeVault", 16)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local root = UIKit.new("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	local panelBody = body(root, S.Roles.Plain, "Panel", false, 24)
	local panel = panelBody.Holder
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panelBody.Gradient.Color = ColorSequence.new(S.Panel, S.Panel)
	local panelGloss = panelBody.Face:FindFirstChild("Gloss")
	if panelGloss then
		panelGloss:Destroy()
	end
	panel.SelectionGroup = true
	local face = panelBody.Face
	-- the orange header with the title and your coins
	local header = body(face, S.Roles.Vault, "Header", false, 20)
	header.Holder.Position = UDim2.fromOffset(10, 10)
	local title = text(header.Face, Pop.caption("BLASTER VAULT"), 34, {
		Name = "Title",
		FontFace = S.TitleFont,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local pill = UIKit.new("Frame", {
		Name = "CoinsPill",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = S.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -72, 0.5, 0),
		Size = UDim2.fromOffset(190, 40),
		ZIndex = 4,
	}, header.Face)
	corner(pill, 20)
	stroke(pill, 3)
	coin(pill, 32, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), ZIndex = 5 })
	local coins = ink(pill, "$0", 22, {
		Name = "Coins",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	-- the close button (red X) on the panel's corner
	local closeBody = body(face, S.Roles.Danger, "CloseButton", true, 14)
	closeBody.Holder.AnchorPoint = Vector2.new(0.5, 0.5)
	closeBody.Holder.ZIndex = 20
	for _, d in closeBody.Holder:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 20
		end
	end
	local close = closeBody.Face :: TextButton
	close.Name = "Close"
	text(close, "X", 28, { Name = "Label", FontFace = S.TitleFont, Size = UDim2.fromScale(1, 1), ZIndex = 24 })
	-- your blaster now
	local info = ink(face, "", 18, {
		Name = "Info",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	-- the cards
	local cards = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = S.InkSoft,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ClipsDescendants = true,
		ZIndex = 3,
	}, face)
	-- the footer: the hint, or a message for a few seconds
	local hint = ink(face, "", 16, { Name = "Hint", TextColor3 = S.InkSoft, ZIndex = 3 })
	local message = ink(face, "", 18, { Name = "Message", Visible = false, ZIndex = 3 })
	if UIConfig.lightUI() then
		-- the header band: no own outline / lip / shadow, square bottom, a navy
		-- line under it, the 3D vault icon on the left; the 3D coin in the pill
		header.Stroke.Enabled = false
		header.Lip.Visible = false
		local headerShadow = header.Holder:FindFirstChild("Shadow") :: Frame?
		if headerShadow then
			headerShadow.Visible = false
		end
		local vault = S.Roles.Vault
		header.Gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, vault.Top),
			ColorSequenceKeypoint.new(0.5, vault.Base),
			ColorSequenceKeypoint.new(1, vault.Base),
		})
		local headerCorner = header.Face:FindFirstChildOfClass("UICorner")
		if headerCorner then
			headerCorner.CornerRadius = UDim.new(0, 24)
		end
		UIKit.new("Frame", {
			Name = "Fill", -- squares the band's bottom corners
			BackgroundColor3 = vault.Base,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.5),
			ZIndex = 2,
		}, header.Face)
		UIKit.new("Frame", {
			Name = "Line",
			BackgroundColor3 = S.Outline,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			ZIndex = 3,
		}, header.Face)
		Bubble.icon(header.Face, "vault", 90, {
			Name = "HeaderIcon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, -10),
			ZIndex = 6,
		})
		local flatCoin = pill:FindFirstChild("Coin") :: Frame?
		if flatCoin then
			flatCoin.Visible = false
		end
		Bubble.icon(pill, "coin", 50, {
			Name = "CoinIcon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			ZIndex = 6,
		})
	end
	local refs: Refs = {
		Gui = gui,
		Root = root,
		Panel = panel,
		PanelBody = panelBody,
		Header = header.Holder,
		Title = title,
		CoinsPill = pill,
		Coins = coins,
		Close = close,
		Info = info,
		Cards = cards,
		Tiles = {},
		Hint = hint,
		Message = message,
		Grid = nil,
		Level = 0,
	}
	for i = 1, BlasterData.MaxLevel - VaultView.FirstLevel + 2 do
		table.insert(refs.Tiles, buildTile(cards, i))
	end
	return refs
end

---------------------------------------------------------------- layout

local function setRect(gui: GuiObject, r: Rect, lipped: boolean?)
	gui.Position = UDim2.fromOffset(r.X, r.Y)
	gui.Size = UDim2.fromOffset(r.W, r.H + (if lipped then S.Lip else 0))
end

local function placeTile(tile: Tile, g: Grid, i: number)
	local slots = g.Slots
	local p = VaultView.tilePosition(g, i)
	tile.Holder.Position = UDim2.fromOffset(p.X, p.Y)
	tile.Holder.Size = UDim2.fromOffset(g.TileW, g.TileH + S.Lip)
	setRect(tile.LvPill, slots.Pill)
	tile.Lv.TextSize = if g.Compact then 20 else 17
	local icon = tile.Icon
	if icon then
		icon.Position = UDim2.fromOffset(slots.Icon.X, slots.Icon.Y)
	end
	setRect(tile.Name, slots.Name)
	TechShopView.fitText(tile.Name, slots.Name.W, slots.Name.H, slots.NameSize, math.floor(slots.NameSize * 0.7))
	tile.Name.TextXAlignment = if g.Compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	setRect(tile.Damage, slots.Damage)
	tile.Damage.TextSize = slots.DamageSize
	tile.Damage.TextXAlignment = tile.Name.TextXAlignment
	setRect(tile.PriceRow, slots.Price)
	tile.Price.TextSize = slots.PriceSize
	local coinIcon = tile.PriceRow:FindFirstChild("Coin") :: Frame?
	local coinSize = if g.Compact then 26 else 22
	if coinIcon then
		coinIcon.Size = UDim2.fromOffset(coinSize, coinSize)
	end
	tile.Price.Position = UDim2.fromOffset(coinSize + 6, 0)
	tile.Price.Size = UDim2.new(1, -(coinSize + 6), 1, 0)
	setRect(tile.ButtonBody.Holder, slots.Button, true)
	tile.ButtonText.TextSize = slots.ButtonSize
end

--[[
	Sizes everything for the screen: maxWidth x maxHeight design units (the
	screen divided by the UI scale, the top bar left out).
]]
function VaultView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	if UIConfig.lightUI() then
		-- the light X sits on the panel's corner: keep room for it on screen
		local half = (if compact then 72 else 54) // 2 + 12
		maxWidth -= half * 2
		maxHeight -= half
	end
	local g = VaultView.grid(#refs.Tiles, compact, maxWidth, maxHeight)
	local old = refs.Grid
	refs.Grid = g
	refs.Panel.Size = UDim2.fromOffset(g.PanelW, g.PanelH + S.Lip)
	-- the header leaves room for the X on the panel's corner
	local closeSize = if compact then 72 else 54
	local light = UIConfig.lightUI()
	if light then
		-- a full-width band; the X sits on the panel's corner (Bubble.window)
		refs.Header.Position = UDim2.fromOffset(0, 0)
		refs.Header.Size = UDim2.fromOffset(g.PanelW, g.HeaderH - 14 + S.Lip)
		refs.Title.Position = UDim2.fromOffset(104, 0)
		refs.Title.Size = UDim2.new(0.6, -90, 1, 0)
	else
		refs.Header.Position = UDim2.fromOffset(10, 10)
		refs.Header.Size = UDim2.fromOffset(g.PanelW - 20 - closeSize - 6, g.HeaderH - 16 + S.Lip)
	end
	refs.Title.TextSize = if compact then 36 else 34
	refs.CoinsPill.Position = if light then UDim2.new(1, -(closeSize // 2 + 26), 0.5, -1) else UDim2.new(1, -14, 0.5, -1)
	refs.CoinsPill.Size = UDim2.fromOffset(if compact then 220 else 190, if compact then 44 else 38)
	refs.Coins.TextSize = if compact then 26 else 22
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(closeSize, closeSize + S.Lip)
	closeHolder.Position = if light then UDim2.new(1, -12, 0, 10) else UDim2.new(1, -closeSize / 2 - 10, 0, closeSize / 2 + 8)
	refs.Info.TextSize = if compact then 22 else 18
	refs.Info.Position = UDim2.fromOffset(g.Pad + 2, g.HeaderH)
	refs.Info.Size = UDim2.fromOffset(g.PanelW - g.Pad * 2, g.InfoH)
	refs.Cards.Position = UDim2.fromOffset(g.Pad, g.HeaderH + g.InfoH + 4)
	refs.Cards.Size = UDim2.fromOffset(g.ViewW, VaultView.rowsHeight(g))
	refs.Cards.CanvasSize = UDim2.fromOffset(g.CanvasW, 0)
	refs.Cards.ScrollingEnabled = g.CanvasW > g.ViewW
	refs.Cards.ScrollBarThickness = if g.CanvasW > g.ViewW then 8 else 0
	for i, tile in refs.Tiles do
		local card = tile.Card
		if card and old and old.Slots.Icon.W ~= g.Slots.Icon.W then
			-- the case icon is drawn at its size: draw it again
			tile.Card = nil
			placeTile(tile, g, i)
			VaultView.fillTile(tile, card, g)
		else
			placeTile(tile, g, i)
		end
	end
	local footY = g.PanelH - (if g.HintH > 0 then g.HintH + 4 else 0)
	refs.Hint.Visible = g.HintH > 0 and not refs.Message.Visible
	refs.Hint.Position = UDim2.fromOffset(g.Pad, footY)
	refs.Hint.Size = UDim2.fromOffset(g.PanelW - g.Pad * 2, g.HintH)
	-- a message: in the footer on PC, over the "Your blaster" line on compact screens
	refs.Message.Position = if g.HintH > 0 then UDim2.fromOffset(g.Pad, footY) else refs.Info.Position
	refs.Message.Size = if g.HintH > 0 then UDim2.fromOffset(g.PanelW - g.Pad * 2, g.HintH) else refs.Info.Size
	refs.Message.TextSize = if compact then 22 else 18
end

---------------------------------------------------------------- filling in

function VaultView.fillTile(tile: Tile, card: Card, g: Grid?)
	local fresh = tile.Card == nil or tile.Card.Level ~= card.Level or tile.Card.Ore ~= card.Ore
	tile.Card = card
	tile.Level = card.Level
	tile.Holder.Visible = true
	if fresh then
		local old = tile.Icon
		if old then
			old:Destroy()
			tile.Icon = nil
		end
		if card.State ~= "Soon" then
			local slot = if g then g.Slots.Icon else rect(17, 34, 108, 66)
			local icon = VaultView.caseIcon(tile.Face, card.Level, card.Ore, slot.W)
			for _, d in icon:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex += 2
				end
			end
			icon.ZIndex += 2
			icon.Position = UDim2.fromOffset(slot.X, slot.Y)
			tile.Icon = icon
		end
	end
	tile.Lv.Text = "LV " .. card.Level
	tile.Name.Text = if card.State == "Soon" then "STAR BLASTERS" else card.Name
	-- long names ("Heartstone Shard Heartlance") get smaller to stay on 2 lines
	local nameMax = if g then g.Slots.NameSize else 16
	TechShopView.fitText(tile.Name, tile.Name.Size.X.Offset, tile.Name.Size.Y.Offset, nameMax, math.floor(nameMax * 0.7))
	tile.Damage.Text = if card.State == "Soon" then "In the Star Forge" else Format.big(card.Damage) .. " DMG/s"
	local priced = card.Price ~= nil and card.State ~= "Owned"
	tile.PriceRow.Visible = priced
	tile.Price.Text = if card.Price then Format.money(card.Price) else ""
	tile.Price.TextColor3 = if card.Reason == "NoCoins" then S.Bad else S.Ink
	tile.ButtonText.Text = VaultView.buttonText(card)
	paint(tile.ButtonBody, if card.CanBuy then S.Roles.Go else S.Roles.Plain)
	-- BUY: white with the outline; the others: soft grey ink, no outline
	tile.ButtonText.TextColor3 = if card.CanBuy then S.White else S.InkSoft
	local outline = tile.ButtonText:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Enabled = card.CanBuy
		outline.Transparency = if card.CanBuy then 0 else 1
	end
	tile.Ribbon.Visible = card.State == "Next"
	tile.Check.Visible = card.State == "Owned"
	tile.Dim.Visible = card.State == "Locked" or card.State == "Soon"
	-- the next card: a gold outline
	tile.Body.Stroke.Color = if card.State == "Next" then S.Gold else S.Outline
	tile.Body.Stroke.Thickness = if card.State == "Next" then 5 else S.Stroke
	tile.Button.Selectable = true
end

-- Fills the cards (VaultView.cards) in; extra tiles hide.
function VaultView.setCards(refs: Refs, cards: { Card })
	for i, tile in refs.Tiles do
		local card = cards[i]
		if card then
			VaultView.fillTile(tile, card, refs.Grid)
		else
			tile.Holder.Visible = false
		end
	end
end

function VaultView.setCoins(refs: Refs, coins: number)
	refs.Coins.Text = Format.money(coins)
end

-- "Your blaster: LV 3 Cobalt Spark Blaster · 16 DMG/s"
function VaultView.setCurrent(refs: Refs, level: number, oreId: string)
	refs.Level = level
	refs.Info.Text = string.format(
		"Your blaster: LV %d %s%s%s DMG/s",
		level,
		BlasterData.displayName(level, oreId),
		VaultView.Separator,
		Format.big(BlasterData.damage(level, oreId))
	)
end

function VaultView.setHint(refs: Refs, value: string)
	refs.Hint.Text = value
end

-- A message in the footer (nil = back to the hint).
function VaultView.setMessage(refs: Refs, value: string?, color: Color3?)
	local g = refs.Grid
	refs.Message.Visible = value ~= nil
	refs.Message.Text = value or ""
	refs.Message.TextColor3 = color or S.Ink
	refs.Hint.Visible = value == nil and (g == nil or g.HintH > 0)
	refs.Info.Visible = value == nil or (g ~= nil and g.HintH > 0)
end

-- The tile showing `level`.
function VaultView.tileFor(refs: Refs, level: number): Tile?
	for _, tile in refs.Tiles do
		if tile.Level == level and tile.Holder.Visible then
			return tile
		end
	end
	return nil
end

-- The button a gamepad selects on open: your next card's, else the first.
function VaultView.firstButton(refs: Refs): TextButton
	for _, tile in refs.Tiles do
		local card = tile.Card
		if card and card.State == "Next" and tile.Holder.Visible then
			return tile.Button
		end
	end
	return refs.Tiles[1].Button
end

-- Scrolls the row so `tile` is in view (compact layout; gamepad selection).
function VaultView.scrollTo(refs: Refs, tile: Tile)
	local g = refs.Grid
	if not g or not g.Compact then
		return
	end
	local x = tile.Holder.Position.X.Offset
	local left = refs.Cards.CanvasPosition.X
	if x < left then
		refs.Cards.CanvasPosition = Vector2.new(x, 0)
	elseif x + g.TileW > left + g.ViewW then
		refs.Cards.CanvasPosition = Vector2.new(x + g.TileW - g.ViewW, 0)
	end
end

-- Every button (touch-size tests: VaultView.MinTouch at VaultView.PhoneScale).
function VaultView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { refs.Close.Parent :: GuiObject }
	for _, tile in refs.Tiles do
		table.insert(list, tile.ButtonBody.Holder)
	end
	return list
end

---------------------------------------------------------------- the Pop look (UIConfig.LightUI)
--[[
	While the light UI is on (it ships on) the window wears the bright Pop
	look of the Robux Shop (UI/Pop; owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"): an orange header band (the
	window's colour) with shine stripes and studs, the 3D vault icon popping
	out of it, the white title with its shadow and the red X in the band,
	over a dark studded body. Each case is a bright painted card in its
	ore's colour (PopPaints; the STAR BLASTERS card a rainbow) with a light
	burst behind the case picture, a dark LV chip, the gold NEXT chip, the
	green owned tick, and one button: the gold coin button with the price
	on your next case (grey while you can't afford it), grey OWNED / LOCKED
	(locked cards are shaded), FOUNDRY orange, REBIRTH purple. The next
	case keeps the gold outline. The same instances, names and refs as
	before (the controller and the specs drive both looks).
]]

VaultView.PopPaints = {
	Copper = "Orange",
	Cobalt = "Blue",
	Emberite = "Red",
	Gold = "Yellow",
	Sapphire = "Teal",
	Amethyst = "Purple",
	Obsidian = "Night",
	RoyalAurum = "Yellow",
	Heartstone = "Pink",
} :: { [string]: string }

-- A case card's paint: its ore's (PopPaints), else the nearest by the case's glow colour.
function VaultView.popPaint(oreId: string): string
	local named = VaultView.PopPaints[oreId]
	if named then
		return named
	end
	if oreId == "" then
		return "Night"
	end
	local _, _, glow = CaseBuilder.look(oreId)
	local h, s = glow:ToHSV()
	local deg = h * 360
	if s < 0.25 then
		return "Slate"
	elseif deg < 18 or deg >= 340 then
		return "Red"
	elseif deg < 40 then
		return "Orange"
	elseif deg < 70 then
		return "Yellow"
	elseif deg < 160 then
		return "Green"
	elseif deg < 195 then
		return "Teal"
	elseif deg < 250 then
		return "Blue"
	elseif deg < 300 then
		return "Purple"
	end
	return "Pink"
end

local GOLD_OUTLINE = rgb(255, 200, 40)
local SOFT_RED = rgb(255, 150, 140)

-- The black edge of a text (its Contextual UIStroke, made when missing).
local function popEdge(label: GuiObject)
	local t: any = label
	local edge: UIStroke? = nil
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			edge = child
		end
	end
	local made = edge or Pop.edge(label)
	made.Color = PopTheme.Outline
	made.Transparency = 0
	made.Enabled = true
	made.LineJoinMode = Enum.LineJoinMode.Round
	made.Thickness = Pop.edgeFor(if t.TextScaled then 24 else t.TextSize)
end

-- White chunky words with a black edge.
local function popText(label: GuiObject, font: Font?)
	local t: any = label
	t.FontFace = font or PopTheme.Font
	t.TextColor3 = PopTheme.Ink
	popEdge(label)
end

-- A bubble body as a Pop face: no lip, shadow or gloss strip; the paint, the black border, the light rim.
local function popBody(b: Body, paint: string | Pop.Paint, corner: number, glossy: boolean)
	b.Lip.Visible = false
	local shadow = b.Holder:FindFirstChild("Shadow") :: GuiObject?
	if shadow then
		shadow.Visible = false
	end
	local gloss = b.Face:FindFirstChild("Gloss") :: GuiObject?
	if gloss then
		gloss.Visible = false
	end
	b.Gradient.Name = "Paint"
	b.Stroke.Name = "Border"
	b.Stroke.Enabled = true
	b.Stroke.Color = PopTheme.Outline
	b.Stroke.Thickness = PopTheme.Edge
	local round = b.Face:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, corner)
	end
	Pop.face(b.Face, paint, corner, glossy)
	b.Face:SetAttribute("Pop", true)
end

-- The gold coin and the price on a BUY button (nil: the button's own word shows).
local function popPriceFace(tile: Tile, amount: string?, affordable: boolean)
	local button = tile.Button
	local face = button:FindFirstChild("PopFace") :: Frame?
	local shows = amount ~= nil and tile.ButtonText.Text == "BUY"
	tile.ButtonText.TextTransparency = if shows then 1 else 0
	local edge = tile.ButtonText:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Transparency = if shows then 1 else 0
	end
	if not shows then
		if face then
			face.Visible = false
		end
		return
	end
	local text = amount :: string
	local h = tile.ButtonBody.Holder.Size.Y.Offset - S.Lip
	local w = tile.ButtonBody.Holder.Size.X.Offset
	local key = `{text}|{w}|{h}`
	if not face or face:GetAttribute("Key") ~= key then
		if face then
			face:Destroy()
		end
		local mark = math.floor(h * 0.52)
		local chars = math.max(1, utf8.len(text) or #text)
		local size = math.clamp(math.floor(math.min(h * 0.52, (w - 16 - mark - 5) / (chars * 0.6))), 12, 40)
		mark = math.min(mark, size + 4)
		local row = UIKit.new("Frame", {
			Name = "PopFace",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 16,
		}, button)
		row:SetAttribute("Key", key)
		UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
		Pop.coin(row, mark, { LayoutOrder = 1, ZIndex = 17 })
		Pop.text(row, text, size, {
			Name = "Amount",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(Pop.textWidth(text, size), size + 6),
			ZIndex = 18,
		})
		face = row
	end
	local made = face :: Frame
	made.Visible = true
	local label = made:FindFirstChild("Amount") :: TextLabel?
	if label then
		label.TextColor3 = if affordable then PopTheme.Ink else SOFT_RED
	end
end

-- The light burst behind a card's case picture (at the icon slot's centre).
local function placeBurst(tile: Tile, g: Grid?)
	local burst = tile.Face:FindFirstChild("Burst") :: Frame?
	if burst then
		local slot = if g then g.Slots.Icon else rect(17, 34, 108, 66)
		burst.Position = UDim2.fromOffset(slot.X + slot.W / 2, slot.Y + slot.H / 2)
	end
end

local function popTile(tile: Tile)
	local face = tile.Face
	popBody(tile.Body, "Slate", 12, false)
	face.ClipsDescendants = true
	local rim = face:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 4
	end
	-- the light burst behind the case, the studs, three sparkles
	local burst = UIKit.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 2,
	}, face)
	local rays = Pop.fx(burst, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 380),
		ZIndex = 2,
	})
	if not rays then
		Pop.rays(burst, UDim2.fromScale(0.5, 0.5), 10, 190, 0.6, 2)
	end
	local glow = Pop.fx(burst, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0.35,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		ZIndex = 2,
	})
	if not glow then
		local disc = UIKit.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(96, 96),
			ZIndex = 2,
		}, burst)
		corner(disc, 999)
	end
	Pop.studs(face, 12, 0.5, 44, 3)
	for i, spot in { { 0.12, 0.3, 16 }, { 0.88, 0.36, 14 }, { 0.5, 0.12, 12 } } do
		Pop.sparkle(face, UDim2.fromScale(spot[1], spot[2]), spot[3], 4, 0.15 + i * 0.1)
	end
	-- a locked case is shaded; the chips and the texts in the Pop words
	tile.Dim.BackgroundColor3 = PopTheme.Outline
	tile.Dim.BackgroundTransparency = 0.5
	local dimCorner = tile.Dim:FindFirstChildOfClass("UICorner")
	if dimCorner then
		dimCorner.CornerRadius = UDim.new(0, 12)
	end
	local pillPaint = tile.LvPill:FindFirstChildOfClass("UIGradient")
	if pillPaint then
		pillPaint:Destroy()
	end
	tile.LvPill.BackgroundColor3 = PopTheme.Well
	for _, badge in { tile.LvPill, tile.Ribbon, tile.Check } do
		local edge = badge:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = PopTheme.Outline
		end
	end
	popText(tile.Lv)
	local ribbonText = tile.Ribbon:FindFirstChild("Text")
	if ribbonText then
		popText(ribbonText :: GuiObject)
	end
	popText(tile.Name)
	popText(tile.Damage)
	popText(tile.Price)
	local coinIcon = tile.PriceRow:FindFirstChild("Coin")
	local coinEdge = if coinIcon then coinIcon:FindFirstChildOfClass("UIStroke") else nil
	if coinEdge then
		coinEdge.Color = PopTheme.Outline
	end
	-- the button: a Pop face (fillTile paints it)
	popBody(tile.ButtonBody, "Yellow", 10, true)
	Pop.studs(tile.ButtonBody.Face, 10, 0.45, 28, 12)
	local buttonRim = tile.ButtonBody.Face:FindFirstChild("Rim") :: Frame?
	if buttonRim then
		buttonRim.ZIndex = 12
	end
	popText(tile.ButtonText, PopTheme.Heavy)
	pcall(function()
		-- (the controller writes "..." on the button while a buy is on its way: the word shows)
		tile.ButtonText:GetPropertyChangedSignal("Text"):Connect(function()
			if tile.ButtonText.Text ~= "BUY" then
				popPriceFace(tile, nil, true)
			end
		end)
	end)
end

-- Fills a card in the Pop look (after the bubble fillTile).
local function popFill(tile: Tile, card: Card, g: Grid?)
	local face = tile.Face
	local soon = card.State == "Soon"
	local paintKey = if soon then "Rainbow" else card.Ore
	local paint = face:FindFirstChild("Paint") :: UIGradient?
	if face:GetAttribute("PopOre") ~= paintKey then
		face:SetAttribute("PopOre", paintKey)
		Pop.repaint(face, if soon then "Night" else VaultView.popPaint(card.Ore), false)
		if paint then
			paint.Rotation = 90
		end
		if soon then
			Pop.rainbow(face)
		end
	end
	placeBurst(tile, g)
	-- the case icon over the burst (fillTile draws it at ZIndex 5+)
	tile.Body.Stroke.Color = if card.State == "Next" then GOLD_OUTLINE else PopTheme.Outline
	tile.Body.Stroke.Thickness = if card.State == "Next" then 5 else PopTheme.Edge
	tile.Price.TextColor3 = if card.Reason == "NoCoins" then SOFT_RED else PopTheme.Ink
	-- the button: gold coin BUY with the price, grey OWNED / LOCKED, FOUNDRY, REBIRTH
	local word = VaultView.buttonText(card)
	local buttonPaint: string | Pop.Paint = if word == "BUY"
		then (if card.CanBuy then "Yellow" else PopTheme.Gray)
		elseif word == "FOUNDRY" then "Orange"
		elseif word == "REBIRTH" then "Purple"
		else PopTheme.Gray
	tile.ButtonBody.Face.BackgroundColor3 = Color3.new(1, 1, 1)
	Pop.repaint(tile.ButtonBody.Face, buttonPaint)
	tile.ButtonText.TextColor3 = PopTheme.Ink
	popEdge(tile.ButtonText)
	local onButton = word == "BUY" and card.Price ~= nil
	popPriceFace(tile, if onButton then Format.money(card.Price :: number) else nil, card.CanBuy)
	-- the price sits on the BUY button; the locked cards keep the price line
	if onButton then
		tile.PriceRow.Visible = false
	end
end

-- Places the Pop pieces after the layout: the X in the band, the pill left of it, the title's shadow.
local function popLayout(refs: Refs)
	local g = refs.Grid
	if not g then
		return
	end
	local compact = g.Compact
	local closeSize = if compact then 72 else 54
	local band = g.HeaderH - 14 -- the header face's height
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	closeHolder.Position = UDim2.new(1, -(10 + closeSize / 2), 0, band / 2 + S.Lip / 2)
	refs.CoinsPill.AnchorPoint = Vector2.new(1, 0.5)
	refs.CoinsPill.Position = UDim2.new(1, -(closeSize + 24), 0.5, 0)
	local pillCorner = refs.CoinsPill:FindFirstChildOfClass("UICorner")
	if pillCorner then
		pillCorner.CornerRadius = UDim.new(0, math.floor(refs.CoinsPill.Size.Y.Offset / 2))
	end
	popEdge(refs.Title)
	local shade = refs.Title.Parent and refs.Title.Parent:FindFirstChild("TitleShadow")
	if shade and shade:IsA("TextLabel") then
		shade.Position = refs.Title.Position + UDim2.fromOffset(0, 4)
		shade.Size = refs.Title.Size
		shade.TextSize = refs.Title.TextSize
	end
	for _, label in { refs.Coins, refs.Info, refs.Hint, refs.Message } do
		popEdge(label)
	end
	for _, tile in refs.Tiles do
		placeBurst(tile, g)
		for _, label in { tile.Lv, tile.Name, tile.Damage, tile.Price, tile.ButtonText } do
			popEdge(label)
		end
		local card = tile.Card
		if card then
			popFill(tile, card, g)
		end
	end
end

local function popSkin(refs: Refs)
	refs.Gui:SetAttribute("PopSkin", true)
	-- the window: a black frame round a dark studded body
	local body = refs.PanelBody
	popBody(body, { Top = PopTheme.Body, Bottom = PopTheme.BodyBottom, Edge = PopTheme.Outline }, 12, false)
	body.Stroke.Thickness = 4
	local face = body.Face
	local rim = face:FindFirstChild("Rim")
	if rim then
		rim:Destroy()
	end
	Pop.studs(face, 12, 0.5, 36, 1)
	-- the header: the orange band, its shine stripes and studs (clipped in their own
	-- frame: the 3D vault icon pops out of the band)
	local header = refs.Header
	header.ZIndex = 2
	local headerFace = header:FindFirstChild("Face") :: Frame
	for _, name in { "Fill", "Line", "Gloss" } do
		local part = headerFace:FindFirstChild(name)
		if part then
			part:Destroy()
		end
	end
	local headerLip = header:FindFirstChild("Lip") :: GuiObject?
	if headerLip then
		headerLip.Visible = false
	end
	local headerShadow = header:FindFirstChild("Shadow") :: GuiObject?
	if headerShadow then
		headerShadow.Visible = false
	end
	local headerPaint = headerFace:FindFirstChildOfClass("UIGradient")
	if headerPaint then
		headerPaint.Name = "Paint"
	end
	local headerBorder = headerFace:FindFirstChildOfClass("UIStroke")
	if headerBorder then
		headerBorder.Name = "Border"
		headerBorder.Enabled = true
		headerBorder.Color = PopTheme.Outline
		headerBorder.Thickness = 3
	end
	local headerCorner = headerFace:FindFirstChildOfClass("UICorner")
	if headerCorner then
		headerCorner.CornerRadius = UDim.new(0, 10)
	end
	Pop.face(headerFace, "Orange", 10, false)
	local headerRim = headerFace:FindFirstChild("Rim") :: Frame?
	if headerRim then
		headerRim.ZIndex = 3
	end
	local shine = UIKit.new("Frame", {
		Name = "PopBand",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, headerFace)
	corner(shine, 10)
	Pop.studs(shine, 10, 0.35, 40, 2)
	if not PopTheme.round() then -- (the round look's band has no shine over its top half)
		UIKit.new("Frame", {
			Name = "Shine",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0.42, 0),
			ZIndex = 2,
		}, shine)
	end
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
		}, shine)
	end
	popText(refs.Title)
	Pop.shadow(refs.Title).ZIndex = 3
	refs.Title.ZIndex = 5
	-- your coins: a dark pill
	refs.CoinsPill.BackgroundColor3 = PopTheme.Well
	local pillEdge = refs.CoinsPill:FindFirstChildOfClass("UIStroke")
	if pillEdge then
		pillEdge.Color = PopTheme.Outline
	end
	popText(refs.Coins)
	refs.Coins.TextColor3 = PopTheme.MoneyNumber
	-- the red X (Pop.close's look), inside the band
	local closeHolder = refs.Close.Parent :: Frame
	local lip: any = closeHolder:FindFirstChild("Lip")
	local closePaint: any = refs.Close:FindFirstChildOfClass("UIGradient")
	local closeEdge: any = refs.Close:FindFirstChildOfClass("UIStroke")
	popBody({ Holder = closeHolder, Face = refs.Close, Lip = lip, Gradient = closePaint, Stroke = closeEdge }, PopTheme.Close, 6, true)
	local closeLabel = refs.Close:FindFirstChild("Label")
	if closeLabel then
		popText(closeLabel :: GuiObject, PopTheme.Heavy)
	end
	-- the line and the footer
	popText(refs.Info)
	popText(refs.Hint)
	popText(refs.Message)
	refs.Cards.ScrollBarImageColor3 = rgb(220, 224, 236)
	for _, tile in refs.Tiles do
		popTile(tile)
	end
end

local plainFillTile = VaultView.fillTile
VaultView.fillTile = function(tile: Tile, card: Card, g: Grid?)
	plainFillTile(tile, card, g)
	if tile.Face:GetAttribute("Pop") then
		popFill(tile, card, g)
	end
end

local plainLayout = VaultView.layout
VaultView.layout = function(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	plainLayout(refs, compact, maxWidth, maxHeight)
	if refs.Gui:GetAttribute("PopSkin") then
		popLayout(refs)
	end
end

local bubbleBuild = VaultView.build
VaultView.build = function(): Refs
	local refs = bubbleBuild()
	if UIConfig.lightUI() then
		popSkin(refs)
	end
	return refs
end

return VaultView
