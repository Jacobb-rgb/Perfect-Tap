--[[
	The backpack shop on screen (pure builder + pure helpers;
	BackpackShopController fills it in and animates it). Owner 2026-10-24:
	ten backpacks worst to best (BackpackData), a BACKPACKS stall in the lobby,
	coins only. Look: the bright "Pop" window kit (Pop.luau), the same chrome
	and cards as the hoverboards (HoverboardView, ElevatorView.popWindow).

	  panel    a Pop window: a teal header band with shine stripes and studs,
	           a small backpack icon, "BACKPACKS" in white with a 3D shadow,
	           the red square X; a dark studded body; under the band your
	           backpack ("Your backpack: Trail Pack · 12 / 15 ore") or the last
	           server message; a dark footer pill with the control hint (not
	           on phones)
	  cards    one per pack (BackpackData order), painted in its rarity's
	           colour (RarityPaints) with light rays and a glow behind the
	           pack's live 3D model (PictureModels "backpack_<Id>":
	           BackpackBuilder in a ViewportFrame), the name, the chips
	           "400 ORE" and the rarity, the price (a coin and the amount;
	           "FREE" for the starter) or an OWNED chip, and the button: BUY
	           (green) / BUY with a lock (grey: not enough coins) / EQUIP
	           (blue) / EQUIPPED (gold, a check; the card gets a gold edge and
	           halo)
	The panel opens at the BACKPACKS stall (OpenUI "Backpacks" { Counter }
	from the server's BackpackService). Designed for 720 design units of
	height (HudController scales every TerraForge gui). Five cards a row when
	they fit (two rows), fewer on narrow screens; the cards scroll when they
	don't fit the height (phones). The compact layout (phones, uiScale 0.62)
	has 64-unit buttons (about 40 pt). A gamepad selection stays inside the
	panel (SelectionGroup); only the card buttons and the X are selectable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BackpackData = require(Shared.Config.BackpackData)
local PopTheme = require(Shared.Config.PopTheme)
local Rarity = require(Shared.Config.Rarity)
local PictureModels = require(Shared.Builders.PictureModels)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local ElevatorView = require(script.Parent.ElevatorView)

local BackpackShopView = {}

export type CardState = "Buy" | "BuyLocked" | "Equip" | "Equipped"
export type HintKind = "Mouse" | "Gamepad" | "Touch"
export type ButtonRefs = ElevatorView.ButtonRefs

export type Card = {
	Pack: BackpackData.Backpack,
	Frame: Frame, -- the holder (the layout places it; the drop-in scales it)
	Scale: UIScale,
	Face: TextButton, -- the painted Pop card (not selectable: its button is)
	Stroke: UIStroke, -- the card's black edge (gold when equipped)
	Glow: Frame, -- the equipped pack's gold halo
	ArtBack: Frame, -- where the picture sits
	Picture: ImageLabel?, -- the live 3D pack (nil: the model couldn't be built)
	Name: TextLabel,
	SizeChip: Frame, -- "400 ORE"
	RarityChip: Frame, -- "EPIC"
	PriceRow: Frame,
	Coin: Frame,
	Price: TextLabel,
	Owned: Frame, -- the OWNED chip where the price was
	Button: TextButton,
	Look: ButtonRefs,
	State: CardState,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame,
	Pop: UIScale,
	Panel: Frame,
	Header: Frame,
	Body: Frame,
	Chrome: ElevatorView.Chrome,
	Icon: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	Subtitle: TextLabel,
	Message: TextLabel,
	Close: TextButton,
	CloseLook: ButtonRefs,
	CardPage: ScrollingFrame,
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

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local GOLD = rgb(255, 204, 64)
local INK = rgb(10, 12, 26)

BackpackShopView.Title = "BACKPACKS"
BackpackShopView.Pitch = "Carry more ore. Bought once, yours forever."
BackpackShopView.Paint = "Teal" -- the header band
BackpackShopView.OpenTime = 0.42
BackpackShopView.CloseTime = 0.2
BackpackShopView.CloseRange = 16 -- studs from the counter: walking farther away closes the shop
-- each rarity's card paint (PopTheme.Paints)
BackpackShopView.RarityPaints = {
	Common = "Slate",
	Uncommon = "Green",
	Rare = "Blue",
	Epic = "Purple",
	Legendary = "Orange",
	Mythic = "Pink",
} :: { [string]: string }
-- BackpackResult reasons (the "Návrhy strojů" BackpackService) -> the line for the player
BackpackShopView.Reasons = {
	TooFar = "Walk up to the BACKPACKS stall to shop.",
	NoCoins = "Not enough coins yet.",
	Owned = "You already own that backpack.",
	NotOwned = "Buy that backpack first.",
	BadId = "That backpack isn't sold here.",
	Locked = "That backpack isn't for sale yet.",
} :: { [string]: string }

type Metrics = {
	Width: number,
	Height: number,
	Pad: number,
	Band: number, -- the coloured header band
	Header: number, -- the band + the status line: where the cards start
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
	MinCard: number, -- the narrowest card
	MinHeight: number, -- a card is at least this tall, else the cards scroll
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1100,
		Height = 680,
		Pad = 20,
		Band = 76,
		Header = 110,
		Title = 46,
		Icon = 52,
		Text = 20,
		Gap = 14,
		Button = 52,
		ButtonText = 22,
		Name = 21,
		Small = 16,
		Price = 24,
		Close = 62,
		Footer = 36,
		MinCard = 186,
		MinHeight = 230, -- two rows fit 1280 x 720 and 1366 x 768 under the top bar
	},
	-- phones: at uiScale 0.62 a 64-unit button is about 40 pt
	Compact = {
		Width = 1320,
		Height = 600,
		Pad = 18,
		Band = 76,
		Header = 104,
		Title = 46,
		Icon = 50,
		Text = 22,
		Gap = 12,
		Button = 64,
		ButtonText = 26,
		Name = 24,
		Small = 19,
		Price = 27,
		Close = 64,
		Footer = 0,
		MinCard = 236,
		MinHeight = 300,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- What a pack's card offers: owned / equipped, else buy (green when you can afford it).
function BackpackShopView.cardState(pack: BackpackData.Backpack, owned: { [string]: boolean }, equipped: string, coins: any): CardState
	local state: CardState = "BuyLocked"
	if owned[pack.Id] then
		state = if equipped == pack.Id then "Equipped" else "Equip"
	else
		local have = if type(coins) == "number" and coins == coins then coins else 0
		if have >= pack.Price then
			state = "Buy"
		end
	end
	return state
end

function BackpackShopView.priceText(pack: BackpackData.Backpack): string
	return if pack.Price <= 0 then "FREE" else Format.money(pack.Price)
end

-- The card's capacity chip: what the pack holds worn, with the player's carry
-- bonuses (State.Backpacks.Bonus: BackpackData.carried, the server's formula).
function BackpackShopView.capacityText(pack: BackpackData.Backpack, bonus: any?): string
	return `{Format.commas(BackpackData.carried(pack.Capacity, bonus))} ORE`
end

function BackpackShopView.buttonText(state: CardState): string
	if state == "Equip" then
		return "EQUIP"
	elseif state == "Equipped" then
		return "EQUIPPED"
	end
	return "BUY"
end

-- The owned packs of a State snapshot as a set (unknown ids dropped): a list
-- ({ Owned = { id... } }) or a set ({ Owned = { [id] = true } }).
function BackpackShopView.ownedSet(list: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(list) == "table" then
		for key, value in list do
			local id = if type(value) == "string" then value elseif value == true then key else nil
			if type(id) == "string" and BackpackData.ById[id] then
				set[id] = true
			end
		end
	end
	return set
end

-- The line under the band: the equipped pack and how full it is.
function BackpackShopView.statusText(equipped: string, count: any, capacity: any): string
	local pack = BackpackData.ById[equipped] or BackpackData.ById[BackpackData.StarterId]
	local held = if type(count) == "number" and count == count then math.max(0, math.floor(count)) else 0
	local room = if type(capacity) == "number" and capacity == capacity and capacity > 0 then math.floor(capacity) else pack.Capacity
	return `Your backpack: {pack.Name} · {Format.commas(held)} / {Format.commas(room)} ore`
end

-- Cards per row for a panel `width` design units wide (2..5).
function BackpackShopView.columns(width: number, compact: boolean): number
	local m = metrics(compact)
	local fit = math.floor((width - m.Pad * 2 + m.Gap) / (m.MinCard + m.Gap))
	return math.clamp(fit, 2, 5)
end

-- A pack's card paint (its rarity's).
function BackpackShopView.cardPaint(pack: BackpackData.Backpack): Pop.Paint
	return Pop.paint(BackpackShopView.RarityPaints[pack.Rarity] or "Slate")
end

---------------------------------------------------------------- icons

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

local function iconBox(parent: Instance, name: string): Frame
	return UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
	}, parent)
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

-- a little backpack (the header): the bag, the flap, the pocket, a buckle
function Icons.backpack(parent: Instance): Frame
	local box = iconBox(parent, "BackpackIcon")
	local body = ink(box, 0.5, 0.56, 0.7, 0.76, rgb(70, 120, 230), 0, 0.22)
	UIKit.stroke(body, 2, INK)
	local flap = ink(box, 0.5, 0.33, 0.74, 0.34, rgb(240, 192, 82), 0, 0.3)
	UIKit.stroke(flap, 2, INK)
	local pocket = ink(box, 0.5, 0.76, 0.46, 0.26, rgb(46, 88, 200), 0, 0.3)
	UIKit.stroke(pocket, 2, INK)
	ink(box, 0.5, 0.44, 0.16, 0.16, rgb(200, 244, 255), 45)
	return box
end

local ICON_MAKERS: { [string]: (Instance, Color3) -> Frame } = {
	Check = Icons.check,
	Lock = Icons.lock,
}

---------------------------------------------------------------- buttons

type ButtonStyle = { Paint: Pop.Paint, Icon: string? }

local STYLES: { [string]: ButtonStyle } = {
	Buy = { Paint = PopTheme.Price, Icon = nil },
	BuyLocked = { Paint = PopTheme.Gray, Icon = "Lock" },
	Equip = { Paint = Pop.paint("Blue"), Icon = nil },
	Equipped = { Paint = Pop.paint("Yellow"), Icon = "Check" },
}
BackpackShopView.ButtonStyles = STYLES

local function styleButton(look: ButtonRefs, styleName: CardState, textSize: number)
	local style = STYLES[styleName]
	look.Style = styleName
	ElevatorView.paintButton(look, style.Paint, BackpackShopView.buttonText(styleName), textSize, style.Icon, false)
	local mark = look.Row:FindFirstChild("Mark") :: ImageLabel?
	if mark then
		mark.Visible = false
	end
end

---------------------------------------------------------------- building

-- the size a card is built at (the layout resizes it; Pop.card sizes its rays and glow from it)
local CARD_BUILD = Vector2.new(200, 320)
-- Pop.card's light burst (rays and glow): it follows the picture
local CARD_FX = { "Rays", "Glow", "Glow1", "Glow2" }
-- the room round the cards inside their scroll (the equipped pack's gold halo is not clipped)
local CARD_MARGIN = 6

local function newCard(page: GuiObject, pack: BackpackData.Backpack): Card
	local frame: Frame = UIKit.new("Frame", {
		Name = pack.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		LayoutOrder = pack.Order,
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
	}, page)
	local scale: UIScale = UIKit.new("UIScale", { Name = "Drop", Scale = 1 }, frame)
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
	UIKit.stroke(glow, 6, GOLD, 0.45)
	local face = Pop.card(frame, BackpackShopView.cardPaint(pack), {
		Name = "Face",
		Size = UDim2.fromOffset(CARD_BUILD.X, CARD_BUILD.Y),
		Selectable = false,
		ZIndex = 2,
	}, UDim2.fromScale(0.5, 0.36))
	face.Size = UDim2.fromScale(1, 1)
	local stroke = face:FindFirstChild("Border") :: UIStroke
	local artBack: Frame = UIKit.new("Frame", {
		Name = "ArtBack",
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, face)
	local model, from = PictureModels.build("backpack_" .. pack.Id)
	local picture: ImageLabel? = nil
	if model then
		picture = Pop.model(artBack, "backpack_" .. pack.Id, 160, model, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.15, 1.15),
			ZIndex = 4,
		}, from)
	end
	local name = Pop.text(face, pack.Name, 21, {
		Name = "PackName",
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
	})
	local sizeChip = Pop.chip(face, BackpackShopView.capacityText(pack), "Night", Vector2.new(100, 26), { ZIndex = 6 })
	sizeChip.Name = "SizeChip"
	local rarityInfo = Rarity.ById[pack.Rarity]
	local rarityChip = Pop.chip(face, string.upper(pack.Rarity), "Night", Vector2.new(80, 26), { ZIndex = 6 })
	rarityChip.Name = "RarityChip"
	local rarityLabel = rarityChip:FindFirstChild("Label") :: TextLabel?
	if rarityLabel and rarityInfo then
		rarityLabel.TextColor3 = rarityInfo.Color
	end
	local priceRow: Frame = UIKit.new("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, face)
	UIKit.list(priceRow, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local coin = Pop.coin(priceRow, 24, { LayoutOrder = 1 })
	local price = Pop.text(priceRow, BackpackShopView.priceText(pack), 24, {
		Name = "Price",
		LayoutOrder = 2,
		FontFace = PopTheme.Heavy,
		TextColor3 = Theme.Coin,
		ZIndex = 7,
	})
	local owned = Pop.chip(face, "OWNED", "Green", Vector2.new(110, 28), { Visible = false, ZIndex = 6 })
	owned.Name = "Owned"
	local look = ElevatorView.popButton(frame, "Action", { "Check", "Lock" }, ICON_MAKERS)
	look.Holder.ZIndex = 3
	return {
		Pack = pack,
		Frame = frame,
		Scale = scale,
		Face = face,
		Stroke = stroke,
		Glow = glow,
		ArtBack = artBack,
		Picture = picture,
		Name = name,
		SizeChip = sizeChip,
		RarityChip = rarityChip,
		PriceRow = priceRow,
		Coin = coin,
		Price = price,
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

function BackpackShopView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeBackpacks", 15)
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
	local chrome = ElevatorView.popWindow(root, BackpackShopView.Title, BackpackShopView.Paint, METRICS.Normal.Band)
	local panel = chrome.Panel
	-- the band's icon: a gold tile with a little blue backpack
	local icon: Frame = UIKit.new("Frame", {
		Name = "HeaderIcon",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, chrome.Header)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.26, 0) }, icon)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 226, 120)),
			ColorSequenceKeypoint.new(0.5, rgb(250, 188, 60)),
			ColorSequenceKeypoint.new(1, rgb(210, 130, 30)),
		}),
		Rotation = 90,
	}, icon)
	UIKit.stroke(icon, 3, INK, 0)
	local bag = Icons.backpack(icon)
	bag.AnchorPoint = Vector2.new(0.5, 0.5)
	bag.Position = UDim2.fromScale(0.5, 0.5)
	bag.Size = UDim2.fromScale(0.78, 0.78)
	local subtitle = Pop.text(panel, BackpackShopView.Pitch, 20, {
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
	for _, pack in BackpackData.List do
		table.insert(cards, newCard(page, pack))
	end
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
		Columns = 5,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
		PoseTime = BackpackShopView.OpenTime,
	}
	BackpackShopView.setCards(refs, {}, BackpackData.StarterId, 0)
	BackpackShopView.setHint(refs, "Mouse", "Click a card · Backspace: close")
	BackpackShopView.layout(refs, compact == true, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- filling in

-- Fills every card from the save: owned packs, the equipped one, your coins.
-- Returns whether a capacity chip changed its text (the caller lays the window out again).
function BackpackShopView.setCards(refs: Refs, owned: { [string]: boolean }, equipped: string, coins: any, bonus: any?): boolean
	local m = metrics(refs.Compact)
	local resized = false
	for _, card in refs.Cards do
		local label = card.SizeChip:FindFirstChildOfClass("TextLabel")
		local text = BackpackShopView.capacityText(card.Pack, bonus)
		if label and label.Text ~= text then
			label.Text = text
			resized = true
		end
		local state: CardState = BackpackShopView.cardState(card.Pack, owned, equipped, coins) :: any
		card.State = state
		styleButton(card.Look, state, m.ButtonText)
		-- the equipped pack: a gold edge and the soft gold halo
		local on = state == "Equipped"
		card.Glow.Visible = on
		card.Stroke.Color = if on then GOLD else PopTheme.Outline
		card.Stroke.Thickness = if on then 4 else PopTheme.Edge
		card.Button.Selectable = not on
		local owns = state == "Equip" or on
		card.PriceRow.Visible = not owns
		card.Owned.Visible = owns
	end
	return resized
end

-- The line under the band: your backpack and how full it is (nil: the pitch).
function BackpackShopView.setStatus(refs: Refs, text: string?)
	refs.Subtitle.Text = text or BackpackShopView.Pitch
end

function BackpackShopView.setHint(refs: Refs, kind: HintKind, text: string)
	refs.Hint.Text = text
	-- its font first (a long hint is a round sentence, as the game's Text signal makes it), then its width
	Pop.sentence(refs.Hint, Pop.wordSize(refs.Hint))
	refs.Hint.Size = UDim2.fromOffset(math.ceil(Pop.measure(refs.Hint)) + 6, 26)
	refs.HintGlyph.Visible = kind == "Gamepad" and refs.HintGlyph.Image ~= ""
	local width = refs.Hint.Size.X.Offset + (if refs.HintGlyph.Visible then 34 else 0) + 40
	refs.Footer.Size = UDim2.fromOffset(width, refs.Footer.Size.Y.Offset)
end

function BackpackShopView.showMessage(refs: Refs, text: string, color: Color3)
	refs.Message.Text = text
	refs.Message.TextColor3 = color
	refs.Message.Visible = true
	refs.Subtitle.Visible = false
end

function BackpackShopView.hideMessage(refs: Refs)
	refs.Message.Visible = false
	refs.Subtitle.Visible = true
end

-- The first card button a gamepad should land on (the first you can buy or equip).
function BackpackShopView.firstButton(refs: Refs): TextButton?
	for _, card in refs.Cards do
		if card.State == "Buy" or card.State == "Equip" then
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

-- Inside a card: the name on top, the picture, the chips, the price (or OWNED), the button at the bottom.
local function layoutCard(card: Card, m: Metrics, w: number, h: number)
	local pad = 10
	local holder = card.Look.Holder
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.new(0, pad, 1, -pad)
	holder.Size = UDim2.new(1, -pad * 2, 0, m.Button)
	local bottom = h - pad - m.Button - 6
	local chipHeight = m.Small + 8
	local priceHeight = m.Price + 6
	card.Name.TextXAlignment = Enum.TextXAlignment.Center
	card.Name.Position = UDim2.fromOffset(pad, pad)
	card.Name.Size = UDim2.fromOffset(w - pad * 2, m.Name + 6)
	fitText(card.Name, m.Name, w - pad * 2 - 4, 13)
	local priceTop = bottom - priceHeight
	local chipsTop = priceTop - 4 - chipHeight
	local chips = { card.SizeChip, card.RarityChip }
	local chipsWidth = sizeChips(chips, m.Small - 2, chipHeight, w - pad * 2, 6)
	local x = math.floor((w - chipsWidth) / 2)
	card.SizeChip.Position = UDim2.fromOffset(x, chipsTop)
	card.RarityChip.Position = UDim2.fromOffset(x + card.SizeChip.Size.X.Offset + 6, chipsTop)
	card.PriceRow.Position = UDim2.fromOffset(pad, priceTop)
	card.PriceRow.Size = UDim2.fromOffset(w - pad * 2, priceHeight)
	card.Owned.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Owned.Position = UDim2.fromOffset(math.floor(w / 2), priceTop + math.floor(priceHeight / 2))
	card.Price.TextSize = m.Price
	card.Price.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(card.Price.Text, m.Price, true)) + 6, priceHeight)
	card.Coin.Size = UDim2.fromOffset(m.Price, m.Price)
	local coinMark = card.Coin:FindFirstChild("Mark") :: TextLabel?
	if coinMark then
		coinMark.TextSize = math.floor(m.Price * 0.62)
	end
	sizeChips({ card.Owned }, m.Small - 1, chipHeight + 2, w, 0)
	-- the picture and the light burst behind it
	local px, py = pad, pad + m.Name + 8
	local pw, ph = w - pad * 2, chipsTop - 4 - (pad + m.Name + 8)
	card.ArtBack.Position = UDim2.fromOffset(px, py)
	card.ArtBack.Size = UDim2.fromOffset(pw, math.max(20, ph))
	local cx, cy = px + pw / 2, py + ph / 2
	for _, fxName in CARD_FX do
		local fx = card.Face:FindFirstChild(fxName)
		if fx and fx:IsA("GuiObject") then
			fx.Position = UDim2.fromOffset(cx, cy)
		end
	end
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (math.huge = no limit).
	On a PC the footer pill hangs half below the panel, so the panel sits a
	little above the middle with room for it underneath.
]]
function BackpackShopView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local width = math.max(560, math.min(m.Width, maxWidth - 24))
	local columns = BackpackShopView.columns(width, compact)
	refs.Columns = columns
	local rows = math.ceil(#refs.Cards / columns)
	local hang = if compact then 0 else math.ceil(math.max(m.Footer, 30) / 2)
	local height = math.max(380, math.min(m.Height, maxHeight - 16 - hang))
	refs.Root.Size = UDim2.fromOffset(width, height)
	refs.Root.AnchorPoint = if compact then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	refs.Root.Position = if compact then UDim2.new(0.5, 0, 1, -10) else UDim2.new(0.5, 0, 0.5, -math.floor(hang / 2))
	ElevatorView.fitWindow(refs.Chrome, refs.Icon, m.Band, m.Title, m.Icon, m.Close)
	refs.Subtitle.Position = UDim2.fromOffset(m.Pad, m.Band + 2)
	refs.Subtitle.Size = UDim2.new(1, -m.Pad * 2, 0, m.Header - m.Band - 4)
	refs.Subtitle.TextSize = m.Text
	refs.Message.Position = refs.Subtitle.Position
	refs.Message.Size = refs.Subtitle.Size
	refs.Message.TextSize = m.Text
	refs.Footer.Visible = not compact
	refs.Footer.Size = UDim2.fromOffset(refs.Footer.Size.X.Offset, math.max(m.Footer, 30))
	-- the cards: rows of `columns` (the last row centred); when they don't fit the height
	-- each keeps MinHeight and the page scrolls (the next row peeks in)
	local top = m.Header
	local bottom = if compact then m.Pad else m.Pad + 14
	local page = refs.CardPage
	page.Position = UDim2.fromOffset(m.Pad - CARD_MARGIN, top - CARD_MARGIN)
	page.Size = UDim2.new(1, -(m.Pad - CARD_MARGIN) * 2, 1, -(top + bottom) + CARD_MARGIN * 2)
	local pageHeight = height - top - bottom
	local fitHeight = math.floor((pageHeight - m.Gap * (rows - 1)) / rows)
	local scrolls = fitHeight < m.MinHeight
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
	for _, card in refs.Cards do
		styleButton(card.Look, card.State, m.ButtonText)
	end
	BackpackShopView.pose(refs, refs.PoseTime)
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
function BackpackShopView.pose(refs: Refs, seconds: number)
	local t = math.clamp(seconds, 0, BackpackShopView.OpenTime)
	refs.PoseTime = t
	refs.Pop.Scale = 0.88 + 0.12 * backOut(clamp01(t / 0.26))
	for i, card in refs.Cards do
		local q = clamp01((t - 0.1 - 0.02 * (i - 1)) / 0.16)
		card.Frame.Visible = q > 0
		card.Scale.Scale = 0.86 + 0.14 * backOut(q)
		local baseY = card.Frame:GetAttribute("BaseY")
		local y = if type(baseY) == "number" then baseY else 0
		card.Frame.Position = UDim2.fromOffset(card.Frame.Position.X.Offset, y - 16 * (1 - q))
	end
end

return BackpackShopView
