--[[
	The Robux STORE window (owner 2026-10-20, from his store photos): the
	"Store" header band, one long row of dark cards with glowing borders that
	scrolls sideways (Config/StoreConfig places them), the green Robux price
	at each card's bottom right. Built with the Card kit (UI/Card.luau).

	  build(compact?)   the window (hidden); Refs.Cards[id] per StoreConfig card
	  layout(refs, w, h) fits the window into w x h design units (phones: the
	                    cards stay big, the row scrolls)
	  setCard(refs, id, key, state) which product a card shows now and its
	                    state ("Buy" | "Owned" | "Pending" | "Hidden")
	  setCoins(refs, income) the coin cards' amounts at this podium income
	  showDetail(refs, detail?) the odds panel shown before a paid random
	                    buy (nil hides it)
	  setStatus(refs, text?) the line under the cards

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CardTheme = require(Shared.Config.CardTheme)
local StoreConfig = require(Shared.Config.StoreConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Card = require(script.Parent.Card)

local StoreView = {}

export type CardRefs = {
	Spec: StoreConfig.CardSpec,
	Button: TextButton,
	Title: TextLabel?,
	Amount: TextLabel?, -- Coins: the coins it gives
	Description: TextLabel?,
	Price: Frame,
	PriceAmount: TextLabel,
	Owned: TextLabel,
	Key: string, -- the product it shows now
}

export type Detail = {
	Title: string,
	Lines: { string },
	Robux: number,
	Glow: string,
}

export type Refs = {
	Gui: ScreenGui,
	Window: Card.Window,
	Scroller: ScrollingFrame,
	Cards: { [string]: CardRefs },
	Order: { string }, -- card ids left to right (gamepad order)
	Status: TextLabel,
	Detail: Frame,
	DetailTitle: TextLabel,
	DetailLines: TextLabel,
	DetailBuy: TextButton,
	DetailBack: TextButton,
}

StoreView.Header = 64
StoreView.Margin = 10
StoreView.MaxWidth = 1180

-- A card's spot on the scrolling row (design units).
function StoreView.cardRect(spec: StoreConfig.CardSpec): (Vector2, Vector2)
	local unit, gap, row = StoreConfig.Unit, StoreConfig.Gap, StoreConfig.RowHeight
	local pos = Vector2.new(gap + spec.Col * unit, gap + spec.Row * (row + gap))
	local size = Vector2.new(spec.Cols * unit - gap, spec.Rows * row + (spec.Rows - 1) * gap)
	return pos, size
end

-- The scrolling row's full size (design units).
function StoreView.canvasSize(): Vector2
	local gap = StoreConfig.Gap
	return Vector2.new(StoreConfig.columns() * StoreConfig.Unit + gap, StoreConfig.Rows * (StoreConfig.RowHeight + gap) + gap)
end

-- The window's size and fit scale for a w x h design-unit screen: the
-- cards keep their size (the row scrolls sideways); a screen too short for
-- both rows shrinks the whole window (fit < 1) instead of cutting them.
function StoreView.windowSize(w: number, h: number): (Vector2, number)
	local canvas = StoreView.canvasSize()
	local tall = canvas.Y + StoreView.Header + 2 * StoreView.Margin + 26
	local fit = math.min(1, (h - 16) / tall)
	return Vector2.new(math.min(StoreView.MaxWidth, (w - 24) / fit), tall), fit
end

local function productOf(spec: StoreConfig.CardSpec): MonetizationConfig.Product
	return MonetizationConfig.Products[spec.Keys[1]]
end

-- the dark "OWNED" chip that replaces a pass's price once it is bought
local function ownedChip(parent: Instance, size: number): TextLabel
	local chip = Card.text(parent, "OWNED", size, {
		Name = "Owned",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -8),
		Size = UDim2.fromOffset(size * 5, size + 10),
		BackgroundColor3 = Color3.fromRGB(26, 70, 30),
		BackgroundTransparency = 0,
		TextColor3 = CardTheme.Price,
		Visible = false,
		ZIndex = 6,
	})
	UIKit.corner(chip, 6)
	return chip
end

local function buildCard(parent: Instance, spec: StoreConfig.CardSpec, seed: number): CardRefs
	local product = productOf(spec)
	local pos, size = StoreView.cardRect(spec)
	local glow = if spec.GlowColor then Card.glowFrom(spec.GlowColor) else (CardTheme.Glows[spec.Glow] or CardTheme.Glows.Orange)
	local button = Card.card(parent, glow, {
		Name = spec.Id,
		Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	Card.sparkles(button, if glow.Rainbow then CardTheme.Glows.Gold.Top else glow.Top, if spec.Rows > 1 then 7 else 4, seed)
	local priceSize = if spec.Rows > 1 then 28 else 22
	local price = Card.price(button, product.Robux, priceSize)
	local refs: CardRefs = {
		Spec = spec,
		Button = button,
		Title = nil,
		Amount = nil,
		Description = nil,
		Price = price,
		PriceAmount = price:FindFirstChild("Amount") :: TextLabel,
		Owned = ownedChip(button, priceSize - 4),
		Key = spec.Keys[1],
	}
	local title = spec.Title or product.Name
	if spec.Look == "Bundle" then
		refs.Title = Card.title(button, title, 34, glow, {
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.new(1, 0, 0, 42),
		})
		Card.text(button, "Includes:", 19, {
			Name = "Includes",
			Position = UDim2.fromOffset(22, 64),
			Size = UDim2.new(1, -44, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local lines: { string } = spec.Lines or {}
		for i, line in lines do
			Card.text(button, "•  " .. line, 18, {
				Name = "Line" .. i,
				Position = UDim2.fromOffset(28, 66 + i * 26),
				Size = UDim2.new(1, -56, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if i == 1 then CardTheme.Glows.Orange.Top else CardTheme.Ink,
			})
		end
		local pic = math.floor(size.Y * 0.44)
		Card.halo(button, UDim2.fromScale(0.5, 0.7), pic)
		Card.picture(button, spec.Icon, pic, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.7),
		})
	elseif spec.Look == "Coins" then
		refs.Amount = Card.title(button, "", 28, "Gold", {
			Name = "Amount",
			FontFace = CardTheme.NumberFont,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 34),
		})
		local pic = math.floor(math.min(size.X * 0.66, size.Y * 0.52))
		Card.halo(button, UDim2.fromScale(0.5, 0.56), pic)
		Card.picture(button, spec.Icon, pic, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
		})
	elseif spec.Look == "Boost" then
		refs.Title = Card.title(button, title, 32, glow, {
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 40),
		})
		local pic = math.floor(math.min(size.X * 0.7, size.Y * 0.42))
		Card.halo(button, UDim2.fromScale(0.5, 0.4), pic)
		Card.picture(button, spec.Icon, pic, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
		})
		Card.text(button, spec.Big or "", 42, {
			Name = "Big",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.64),
			Size = UDim2.new(1, -16, 0, 48),
			FontFace = CardTheme.NumberFont,
		})
		Card.text(button, spec.Note or "", 22, {
			Name = "Note",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.75),
			Size = UDim2.new(1, -16, 0, 28),
			TextColor3 = glow.Top,
		})
	elseif spec.Look == "Item" then
		refs.Title = Card.title(button, title, 28, glow, {
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 36),
		})
		local pic = math.floor(math.min(size.X * 0.4, size.Y * 0.56))
		Card.halo(button, UDim2.new(0, 16 + pic / 2, 0.56, 0), pic)
		Card.picture(button, spec.Icon, pic, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.56, 0),
		})
		refs.Description = Card.text(button, spec.Short or product.Description, 15, {
			Name = "Description",
			Position = UDim2.fromOffset(pic + 26, 50),
			Size = UDim2.new(1, -(pic + 36), 1, -96),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = CardTheme.Ink,
		})
	elseif spec.Look == "Capsule" then
		refs.Title = Card.title(button, "Royal Capsule", 22, glow, {
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 28),
		})
		local pic = math.floor(math.min(size.X * 0.56, size.Y * 0.5))
		Card.halo(button, UDim2.fromScale(0.5, 0.55), pic)
		Card.picture(button, spec.Icon, pic, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
		})
		Card.title(button, spec.Note or "", 34, "Gold", {
			Name = "Count",
			FontFace = CardTheme.NumberFont,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -6),
			Size = UDim2.fromOffset(80, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	elseif spec.Look == "Star" then
		refs.Title = Card.title(button, title, 22, glow, {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 28),
		})
		-- the live gun (RebirthView.fillPicture fills the ViewportFrame in the
		-- game; the picture's Icon is the preview's rendered gun)
		local pic = math.floor(math.min(size.X * 0.55, size.Y * 0.5))
		Card.halo(button, UDim2.new(0, 14 + pic / 2, 0.52, 0), pic)
		local picture = UIKit.new("ImageLabel", {
			Name = "Picture",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Image = "",
			Position = UDim2.new(0, 14, 0.52, 0),
			Size = UDim2.fromOffset(pic, pic),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}, button)
		picture:SetAttribute("Icon", spec.Icon)
		UIKit.new("ViewportFrame", {
			Name = "View",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Ambient = Color3.fromRGB(150, 150, 170),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -1, -0.4),
			ZIndex = 3,
		}, picture)
		Card.text(button, spec.Big or "", 24, {
			Name = "Big",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, pic + 22, 0, 46),
			Size = UDim2.new(1, -(pic + 30), 0, 30),
			FontFace = CardTheme.NumberFont,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		refs.Description = Card.text(button, spec.Note or "", 15, {
			Name = "Note",
			Position = UDim2.new(0, pic + 22, 0, 80),
			Size = UDim2.new(1, -(pic + 30), 0, 40),
			TextColor3 = glow.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
	return refs
end

function StoreView.build(): Refs
	local gui = UIKit.screen("TerraForgeStore", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	-- a dim backdrop over the world
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	-- the window sits in a full-screen holder whose UIScale fits it to short screens
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local size = StoreView.windowSize(1280, 720)
	local window = Card.window(holder, StoreConfig.Title, size, StoreView.Header)
	-- a gamepad selection never wanders out to the HUD
	window.Root.SelectionGroup = true
	window.Root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	window.Root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	window.Root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	window.Root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local canvas = StoreView.canvasSize()
	local scroller = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -22),
		CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(200, 204, 214),
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 2,
	}, window.Body)
	local cards: { [string]: CardRefs } = {}
	local order: { string } = {}
	for i, spec in StoreConfig.Cards do
		cards[spec.Id] = buildCard(scroller, spec, 1000 + i * 37)
		table.insert(order, spec.Id)
	end
	table.sort(order, function(a, b)
		local sa, sb = StoreConfig.ById[a], StoreConfig.ById[b]
		if sa.Col ~= sb.Col then
			return sa.Col < sb.Col
		end
		return sa.Row < sb.Row
	end)
	local status = Card.text(window.Body, "", 17, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -24, 0, 22),
		TextColor3 = CardTheme.InkSoft,
		ZIndex = 3,
	})

	-- the odds panel (paid random items show their odds before the buy); a
	-- dim blocker under it keeps taps and the D-pad off the cards behind
	local blocker = UIKit.new("TextButton", {
		Name = "Blocker",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Selectable = false,
		Visible = false,
		ZIndex = 19,
	}, window.Body)
	UIKit.corner(blocker, CardTheme.CardCorner)
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CardTheme.Card,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 420),
		Visible = false,
		ZIndex = 20,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, window.Body)
	UIKit.corner(detail, CardTheme.CardCorner)
	local detailEdge = UIKit.new("UIStroke", { Color = CardTheme.Glows.Purple.Edge, Thickness = CardTheme.EdgeThickness }, detail)
	detailEdge.Name = "Glow"
	local detailTitle = Card.title(detail, "", 30, "Purple", {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 21,
	})
	-- the odds can run long (Triple Lucky: every capsule): they scroll
	local linesScroll = UIKit.new("ScrollingFrame", {
		Name = "LinesScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 58),
		Size = UDim2.new(1, -40, 1, -140),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = CardTheme.InkSoft,
		ZIndex = 21,
	}, detail)
	local detailLines = Card.text(linesScroll, "", 17, {
		Name = "Lines",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -12, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 21,
	})
	local function detailButton(name: string, text: string, color: Color3, dark: Color3, x: number): TextButton
		local b = UIKit.new("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 1),
			AutoButtonColor = true,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.new(x, 0, 1, -16),
			Size = UDim2.fromOffset(190, 54),
			FontFace = CardTheme.NumberFont,
			Text = text,
			TextSize = 26,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 22,
		}, detail)
		UIKit.corner(b, 8)
		UIKit.new("UIStroke", { Color = dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		Card.edge(b, 2)
		return b
	end
	local back = detailButton("Back", "BACK", Color3.fromRGB(110, 118, 136), Color3.fromRGB(50, 56, 70), 0.28)
	local buy = detailButton("Buy", "BUY", Color3.fromRGB(70, 200, 60), Color3.fromRGB(24, 96, 20), 0.72)

	local refs: Refs = {
		Gui = gui,
		Window = window,
		Scroller = scroller,
		Cards = cards,
		Order = order,
		Status = status,
		Detail = detail,
		DetailTitle = detailTitle,
		DetailLines = detailLines,
		DetailBuy = buy,
		DetailBack = back,
	}
	StoreView.layout(refs, 1280, 720)
	return refs
end

-- Sizes for the big screens and for phones / TVs (compact: TechShopView.compactFor):
-- on a phone the HUD scale is small, so the X, the odds and their buttons grow.
StoreView.Metrics = {
	Normal = { Close = 50, Lines = 17, Note = 15, Button = Vector2.new(190, 54), Detail = Vector2.new(560, 420) },
	Compact = { Close = 72, Lines = 24, Note = 19, Button = Vector2.new(240, 72), Detail = Vector2.new(760, 470) },
}

-- Fits the window into a w x h design-unit screen (compact: the phone sizes).
function StoreView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local size, fit = StoreView.windowSize(w, h)
	refs.Window.Root.Size = UDim2.fromOffset(size.X, size.Y)
	local holder = refs.Window.Root.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	local m = if compact then StoreView.Metrics.Compact else StoreView.Metrics.Normal
	refs.Window.Close.Size = UDim2.fromOffset(m.Close, m.Close)
	refs.Window.Close.TextSize = math.floor(m.Close * 0.62)
	refs.Detail.Size = UDim2.fromOffset(m.Detail.X, m.Detail.Y)
	refs.DetailLines.TextSize = m.Lines
	for _, button in { refs.DetailBuy, refs.DetailBack } do
		button.Size = UDim2.fromOffset(m.Button.X, m.Button.Y)
		button.TextSize = math.floor(m.Button.Y * 0.48)
	end
	for _, card in refs.Cards do
		local description = card.Description
		if description and (card.Spec.Look == "Item" or card.Spec.Look == "Star") then
			description.TextSize = m.Note
		end
	end
end

-- Which product a card shows and how: "Buy" (price), "Owned" (a pass the
-- player has: the OWNED chip), "Pending" (a purchase on its way: greyed),
-- "Locked" (not yet: a STAR blaster before its rebirth; greyed, no price),
-- "Hidden" (nothing to sell: the blaster at the top level).
function StoreView.setCard(refs: Refs, id: string, key: string, state: string)
	local card = refs.Cards[id]
	local product = MonetizationConfig.Products[key]
	if not card or not product then
		return
	end
	card.Key = key
	card.PriceAmount.Text = tostring(product.Robux)
	card.PriceAmount.Size = UDim2.fromOffset(Card.digitsWidth(card.PriceAmount.Text, card.PriceAmount.TextSize), card.PriceAmount.Size.Y.Offset)
	if card.Description and card.Spec.Look ~= "Star" then
		card.Description.Text = card.Spec.Short or product.Description
	end
	card.Button.Visible = state ~= "Hidden"
	card.Price.Visible = state == "Buy" or state == "Pending"
	card.Owned.Visible = state == "Owned"
	card.Button.Active = state == "Buy"
	-- greyed while a buy is on its way or until it opens (a STAR blaster's rebirths)
	card.Button.BackgroundTransparency = if state == "Pending" or state == "Locked" then 0.35 else 0
end

-- A Star card's note ("Opens at rebirth 3", "Owned: opens at rebirth 5").
function StoreView.setNote(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	if not card then
		return
	end
	if card.Description then
		card.Description.Text = text
		return
	end
	local note = card.Button:FindFirstChild("Note") -- a Boost card's gold line (the blaster)
	if note and note:IsA("TextLabel") then
		note.Text = text
	end
end

-- A Boost card's big line ("LV 5" on the blaster card).
function StoreView.setBig(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	local big = if card then card.Button:FindFirstChild("Big") else nil
	if big and big:IsA("TextLabel") then
		big.Text = text
	end
end

-- The coin cards' amounts at a podium income of `income` coins per second.
function StoreView.setCoins(refs: Refs, income: number)
	for _, card in refs.Cards do
		local amount = card.Amount
		if amount then
			local coins = MonetizationConfig.coinPackAmount(card.Key, income) or 0
			amount.Text = "$" .. Format.big(coins)
		end
	end
end

-- The odds panel before a paid random buy (nil hides it).
function StoreView.showDetail(refs: Refs, detail: Detail?)
	refs.Detail.Visible = detail ~= nil
	local blocker = refs.Window.Body:FindFirstChild("Blocker")
	if blocker and blocker:IsA("GuiObject") then
		blocker.Visible = detail ~= nil
	end
	if not detail then
		return
	end
	local glow = CardTheme.Glows[detail.Glow] or CardTheme.Glows.Purple
	refs.DetailTitle.Text = detail.Title
	local gradient = refs.DetailTitle:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(glow.Top, glow.Bottom)
	end
	local edge = refs.Detail:FindFirstChild("Glow") :: UIStroke?
	if edge then
		edge.Color = glow.Edge
	end
	refs.DetailLines.Text = table.concat(detail.Lines, "\n")
	-- (AutomaticSize grows it in the game; the height also from the lines for the previews)
	refs.DetailLines.Size = UDim2.new(1, -12, 0, #detail.Lines * math.ceil(refs.DetailLines.TextSize * 1.3) + 8)
	refs.DetailBuy.Text = `BUY  {detail.Robux} R$`
end

-- The line under the cards (nil / "" clears it).
function StoreView.setStatus(refs: Refs, text: string?)
	refs.Status.Text = text or ""
end

return StoreView
