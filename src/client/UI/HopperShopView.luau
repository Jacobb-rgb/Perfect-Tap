--[[
	The HOPPERS shop window (concept, owner 2026-10-20): the Store card look
	(UI/Card.luau). One row of tall cards that scrolls sideways, one per
	hopper (Config/HopperConfig), cheapest first. A card shows the hopper,
	its income, the ores it pours, how soon it pays itself back, the BUY
	button with the coin price and what it sells back for.

	  build()                    the window (hidden); Refs.Cards[id]
	  layout(refs, w, h)         fits the window into w x h design units
	  setCard(refs, id, state)   { Owned, CanAfford, Locked } -> button and chips
	  setStatus(refs, text?)     the line under the cards

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CardTheme = require(Shared.Config.CardTheme)
local HopperConfig = require(Shared.Config.HopperConfig)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Card = require(script.Parent.Card)
local Bubble = require(script.Parent.Bubble)

local HopperShopView = {}

export type CardRefs = {
	Hopper: HopperConfig.Hopper,
	Button: TextButton,
	Buy: TextButton,
	BuyAmount: TextLabel,
	Owned: TextLabel,
	Lock: TextLabel,
}

export type Refs = {
	Gui: ScreenGui,
	Window: Card.Window,
	Scroller: ScrollingFrame,
	Cards: { [string]: CardRefs },
	Order: { string },
	Info: TextLabel,
	Status: TextLabel,
}

export type CardState = { Owned: number, CanAfford: boolean, Locked: boolean? }

HopperShopView.Title = "Hoppers"
HopperShopView.Header = 64
HopperShopView.CardSize = Vector2.new(286, 452)
HopperShopView.Gap = 14
HopperShopView.MaxWidth = 1220

local rgb = Color3.fromRGB
HopperShopView.BuyColor = rgb(70, 200, 60)
HopperShopView.BuyDark = rgb(24, 96, 20)
HopperShopView.GreyColor = rgb(96, 102, 118)
HopperShopView.GreyDark = rgb(46, 50, 62)
HopperShopView.Income = rgb(126, 240, 74)

-- the Heart Hopper's pink (CardTheme has no pink glow)
local PINK = Card.glowFrom(rgb(255, 96, 170))

local function glowOf(hopper: HopperConfig.Hopper): string | CardTheme.Glow
	return if hopper.Glow == "Pink" then PINK else hopper.Glow
end

-- "~55 min", "~1 h 15 min"
function HopperShopView.payback(seconds: number): string
	local minutes = math.max(1, math.floor(seconds / 60 / 5 + 0.5) * 5)
	if minutes < 60 then
		return `~{minutes} min`
	end
	local h, m = minutes // 60, minutes % 60
	return if m == 0 then `~{h} h` else `~{h} h {m} min`
end

local function buildCard(parent: Instance, hopper: HopperConfig.Hopper, x: number): CardRefs
	local size = HopperShopView.CardSize
	local glow = glowOf(hopper)
	local card = Card.card(parent, glow, {
		Name = hopper.Id,
		Position = UDim2.fromOffset(x, 12),
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = hopper.Order,
	})
	local edge = if type(glow) == "table" then glow.Edge else CardTheme.Glows[glow].Edge
	Card.sparkles(card, edge:Lerp(Color3.new(1, 1, 1), 0.4), 3 + hopper.Order, 500 + hopper.Order * 29)
	-- the name
	Card.title(card, string.upper(hopper.Name), 26, glow, {
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 32),
	})
	-- the hopper itself (a 3D icon)
	local picture = 186
	local pos = UDim2.new(0.5, 0, 0, 52 + picture / 2)
	Card.picture(card, "hopper_" .. hopper.Id, picture, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		ZIndex = 3,
	})
	Card.halo(card, pos, picture)
	-- what it earns
	Card.text(card, Format.perSecond(hopper.Income), 30, {
		Name = "Income",
		Position = UDim2.fromOffset(0, 246),
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = CardTheme.NumberFont,
		TextColor3 = HopperShopView.Income,
	})
	-- the ores it pours: their little pictures and a word
	local row = UIKit.new("Frame", {
		Name = "Ores",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 284),
		Size = UDim2.new(1, -20, 0, 34),
		ZIndex = 4,
	}, card)
	UIKit.list(row, Enum.FillDirection.Horizontal, 2, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	for i, oreId in hopper.Ores do
		Bubble.icon(row, "item_Clean_" .. oreId, 34, { LayoutOrder = i, ZIndex = 5 })
	end
	Card.text(card, hopper.Tagline, 16, {
		Name = "Pours",
		Position = UDim2.fromOffset(8, 320),
		Size = UDim2.new(1, -16, 0, 20),
		TextColor3 = CardTheme.InkSoft,
	})
	Card.text(card, "Pays back in " .. HopperShopView.payback(HopperConfig.payback(hopper)), 16, {
		Name = "Payback",
		Position = UDim2.fromOffset(8, 340),
		Size = UDim2.new(1, -16, 0, 20),
		TextColor3 = CardTheme.InkSoft,
	})
	-- BUY with the coin price
	local buy = UIKit.new("TextButton", {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 0),
		AutoButtonColor = true,
		BackgroundColor3 = HopperShopView.BuyColor,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 368),
		Size = UDim2.new(1, -28, 0, 50),
		Text = "",
		ZIndex = 4,
	}, card)
	UIKit.corner(buy, 8)
	UIKit.new(
		"UIStroke",
		{ Name = "Rim", Color = HopperShopView.BuyDark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		buy
	)
	local inside = UIKit.new("Frame", { Name = "Inside", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, buy)
	UIKit.list(inside, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Bubble.icon(inside, "coin", 30, { LayoutOrder = 1, ZIndex = 6 })
	local priceText = Format.money(hopper.Price)
	local amount = Card.text(inside, priceText, 28, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Card.digitsWidth(priceText, 28), 34),
		FontFace = CardTheme.NumberFont,
		TextColor3 = Color3.new(1, 1, 1),
		TextWrapped = false,
		ZIndex = 6,
	})
	-- what it sells back for
	Card.text(card, "Sell back: " .. Format.money(hopper.Resale), 15, {
		Name = "Resale",
		Position = UDim2.fromOffset(8, 424),
		Size = UDim2.new(1, -16, 0, 20),
		TextColor3 = CardTheme.InkSoft,
	})
	-- OWNED x2 (top right) and the lock (a hopper you can't buy yet)
	local owned = UIKit.new("TextLabel", {
		Name = "Owned",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = rgb(52, 150, 50),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -8, 0, 46),
		Size = UDim2.fromOffset(92, 26),
		FontFace = CardTheme.NumberFont,
		Text = "OWNED",
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 6,
	}, card)
	UIKit.corner(owned, 13)
	UIKit.new("UIStroke", { Color = rgb(20, 70, 20), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, owned)
	Card.edge(owned, 1.5)
	local lock = Card.text(card, "🔒", 64, {
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(90, 90),
		Visible = false,
		ZIndex = 7,
	})
	return { Hopper = hopper, Button = card, Buy = buy, BuyAmount = amount, Owned = owned, Lock = lock }
end

function HopperShopView.build(): Refs
	local gui = UIKit.screen("TerraForgeHoppers", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local window = Card.window(holder, HopperShopView.Title, Vector2.new(1180, 640), HopperShopView.Header)
	window.Root.SelectionGroup = true
	local info = Card.text(window.Body, "", 17, {
		Name = "Info",
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = CardTheme.InkSoft,
	})
	local size, gap = HopperShopView.CardSize, HopperShopView.Gap
	local scroller = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.fromOffset(gap + #HopperConfig.List * (size.X + gap), size.Y + 24),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = rgb(200, 204, 214),
		ZIndex = 2,
	}, window.Body)
	local cards: { [string]: CardRefs } = {}
	local order: { string } = {}
	for i, hopper in HopperConfig.List do
		cards[hopper.Id] = buildCard(scroller, hopper, gap + (i - 1) * (size.X + gap))
		table.insert(order, hopper.Id)
	end
	local status = Card.text(window.Body, "", 17, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -24, 0, 22),
		TextColor3 = CardTheme.InkSoft,
		ZIndex = 3,
	})
	local refs: Refs = {
		Gui = gui,
		Window = window,
		Scroller = scroller,
		Cards = cards,
		Order = order,
		Info = info,
		Status = status,
	}
	HopperShopView.layout(refs, 1280, 720)
	return refs
end

-- Fits the window into a w x h design-unit screen.
function HopperShopView.layout(refs: Refs, w: number, h: number)
	local width = math.min(HopperShopView.MaxWidth, w - 40)
	local height = HopperShopView.Header + 28 + HopperShopView.CardSize.Y + 24 + 28 + 12
	local fit = math.min(1, (h - 150) / height) -- (the HUD's top bar and coins stay in sight)
	refs.Window.Root.Size = UDim2.fromOffset(width / fit, height)
	local holder = refs.Window.Root.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
end

function HopperShopView.setCard(refs: Refs, id: string, state: CardState)
	local card = refs.Cards[id]
	if not card then
		return
	end
	card.Owned.Visible = state.Owned > 0
	card.Owned.Text = if state.Owned > 1 then `OWNED x{state.Owned}` else "OWNED"
	card.Lock.Visible = state.Locked == true
	local can = state.CanAfford and not state.Locked
	card.Buy.BackgroundColor3 = if can then HopperShopView.BuyColor else HopperShopView.GreyColor
	local rim = card.Buy:FindFirstChild("Rim") :: UIStroke?
	if rim then
		rim.Color = if can then HopperShopView.BuyDark else HopperShopView.GreyDark
	end
	card.BuyAmount.TextColor3 = if can then Color3.new(1, 1, 1) else CardTheme.InkSoft
end

function HopperShopView.setInfo(refs: Refs, text: string)
	refs.Info.Text = text
end

function HopperShopView.setStatus(refs: Refs, text: string?)
	refs.Status.Text = text or ""
end

return HopperShopView
