--[[
	Robux Shop window in the light "Bubble" look (pure builder, preview first).
	Content follows MonetizationConfig (step 6-8 branch): game passes, luck
	boosts, Royal capsules, the two rare enchants; coin packs stay hidden
	while MonetizationConfig.CoinPacksEnabled is false.

	  header   green (Shop colour), shop bag icon, red X
	  tabs     PASSES / BOOSTS / CAPSULES / ENCHANTS
	  left     the hero offer (Forgemaster's Pass): big icon, perks, BUY
	  right    the other offers as rows: icon, name, description, price or OWNED

	Prices show Roblox's own Robux icon (IconAssets.BuiltIn.robux). Random
	things (boosts, capsules) say "odds shown before buying" in their text.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local ShopBubble = {}

export type Offer = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Price: string, -- Robux amount
	Owned: boolean?,
	Perks: { string }?, -- the hero offer's list
	Tag: string?, -- ribbon on the hero ("BEST VALUE")
}

export type Data = { Tab: string, Hero: Offer, Offers: { Offer } }

export type Layout = {
	Compact: boolean,
	Size: Vector2,
	Header: number,
	Tab: Vector2,
	Hero: number,
	Button: number,
	NameSize: number,
	TextSize: number,
}

function ShopBubble.layout(uiScale: number): Layout
	if uiScale <= 0.75 then
		return {
			Compact = true,
			Size = Vector2.new(1300, 520),
			Header = 60,
			Tab = Vector2.new(208, 72),
			Hero = 470,
			Button = 72,
			NameSize = 26,
			TextSize = 19,
		}
	end
	return {
		Compact = false,
		Size = Vector2.new(1000, 592),
		Header = 68,
		Tab = Vector2.new(172, 54),
		Hero = 400,
		Button = 56,
		NameSize = 24,
		TextSize = 16,
	}
end

ShopBubble.Tabs = {
	{ Id = "Passes", Label = "PASSES", Icon = "medal", Role = "Shop" },
	{ Id = "Boosts", Label = "BOOSTS", Icon = "clover", Role = "Shop" },
	{ Id = "Capsules", Label = "CAPSULES", Icon = "capsule_Royal", Role = "Shop" },
	{ Id = "Enchants", Label = "ENCHANTS", Icon = "enchant", Role = "Shop" },
}

export type Refs = {
	Window: Bubble.Window,
	Tabs: { [string]: TextButton },
	Buy: { [string]: TextButton },
}

local function priceButton(parent: Instance, offer: Offer, size: Vector2, textSize: number): (TextButton, Frame)
	if offer.Owned then
		local face, holder = Bubble.button(parent, {
			Name = "Owned",
			Text = "OWNED",
			Role = "Plain",
			Size = size,
			Icon = "check",
			TextSize = textSize,
		})
		local label = face:FindFirstChild("Label") :: TextLabel
		label.TextColor3 = Theme.InkSoft
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
			stroke.Transparency = 1
		end
		return face, holder
	end
	return Bubble.button(parent, {
		Name = "Buy",
		Text = offer.Price,
		Role = "Go",
		Size = size,
		Icon = "robux",
		TextSize = textSize + 4,
	})
end

local function hero(parent: Frame, offer: Offer, layout: Layout): TextButton
	local holder, face = Bubble.body(parent, Bubble.role("Build"), Vector2.new(layout.Hero, 0), { Name = "Hero", Corner = 22 })
	holder.Size = UDim2.new(0, layout.Hero, 1, 0)
	for _, part in { "Shadow", "Lip" } do
		local piece = holder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 1, -Theme.Lip)
	end
	face.Size = UDim2.new(1, 0, 1, -Theme.Lip)
	if offer.Tag then
		local tag = Bubble.chip(face, offer.Tag, Vector2.new(150, 34), 18, "Danger", {
			Name = "Tag",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -66, 0, 26),
			Rotation = 8,
			ZIndex = 6,
		})
		tag.ZIndex = 6
	end
	local pad = 16
	local perkTop
	if layout.Compact then
		Bubble.icon(face, offer.Icon, 120, { Position = UDim2.fromOffset(pad - 6, -10) })
		Bubble.text(face, string.upper(offer.Name), 30, {
			Name = "Title",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(130, 18),
			Size = UDim2.new(1, -150, 0, 80),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		perkTop = 118
	else
		Bubble.icon(face, offer.Icon, 140, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -24) })
		Bubble.text(face, string.upper(offer.Name), 30, {
			Name = "Title",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(pad, 116),
			Size = UDim2.new(1, -pad * 2, 0, 36),
			ZIndex = 4,
		})
		perkTop = 160
	end
	local perks = UIKit.new("Frame", {
		Name = "Perks",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad + 8, perkTop),
		Size = UDim2.new(1, -pad * 2 - 8, 0, 160),
		ZIndex = 4,
	}, face)
	local columns = if layout.Compact then 2 else 1
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.new(1 / columns, -6, 0, 30),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, perks)
	local perkList: { string } = offer.Perks or {}
	for i, perk in perkList do
		local row = UIKit.new("Frame", { Name = "Perk" .. i, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 4 }, perks)
		Bubble.icon(row, "check", 30, { Position = UDim2.fromOffset(0, 0), ZIndex = 5 })
		Bubble.text(row, perk, layout.TextSize + 4, {
			Name = "Text",
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(1, -34, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = layout.Compact,
			ZIndex = 5,
		})
	end
	local buy, buyHolder = priceButton(face, offer, Vector2.new(layout.Hero - pad * 2, layout.Button), 26)
	buyHolder.AnchorPoint = Vector2.new(0.5, 1)
	buyHolder.Position = UDim2.new(0.5, 0, 1, -pad + 2)
	return buy
end

local function row(parent: Instance, offer: Offer, layout: Layout, height: number, order: number): TextButton
	local holder, face = Bubble.body(parent, Bubble.role("Plain"), Vector2.new(0, height - Theme.Lip), { Name = offer.Id, Corner = 18 })
	holder.LayoutOrder = order
	holder.Size = UDim2.new(1, 0, 0, height)
	for _, part in { "Shadow", "Lip" } do
		local piece = holder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 0, height - Theme.Lip)
	end
	face.Size = UDim2.new(1, 0, 0, height - Theme.Lip)
	local iconSize = math.floor(height * 0.92)
	Bubble.icon(face, offer.Icon, iconSize, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, -4) })
	local buttonWidth = if layout.Compact then 170 else 140
	Bubble.ink(face, offer.Name, layout.NameSize, {
		Name = "Name",
		Position = UDim2.fromOffset(iconSize + 10, 10),
		Size = UDim2.new(1, -iconSize - buttonWidth - 30, 0, layout.NameSize + 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = 4,
	})
	Bubble.ink(face, offer.Description, layout.TextSize, {
		Name = "Description",
		Position = UDim2.fromOffset(iconSize + 10, layout.NameSize + 16),
		Size = UDim2.new(1, -iconSize - buttonWidth - 30, 1, -layout.NameSize - 22),
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	local buy, buyHolder = priceButton(face, offer, Vector2.new(buttonWidth, layout.Button), 22)
	buyHolder.AnchorPoint = Vector2.new(1, 0.5)
	buyHolder.Position = UDim2.new(1, -12, 0.5, -2)
	return buy
end

function ShopBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local layout = ShopBubble.layout(uiScale)
	local window = Bubble.window(parent, {
		Name = "Shop",
		Title = "SHOP",
		Icon = "shop",
		Role = "Shop",
		Size = layout.Size,
		HeaderHeight = layout.Header,
	})
	local body = window.Body
	local tabs = Bubble.tabs(body, ShopBubble.Tabs, data.Tab, layout.Tab, if layout.Compact then 24 else 20)
	local top = layout.Tab.Y + Theme.Lip + 14
	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
	}, body)
	local buy = {}
	buy[data.Hero.Id] = hero(content, data.Hero, layout)
	local list = UIKit.new("Frame", {
		Name = "Offers",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.Hero + 18, 0),
		Size = UDim2.new(1, -layout.Hero - 18, 1, 0),
	}, content)
	UIKit.list(list, Enum.FillDirection.Vertical, 12)
	local available = layout.Size.Y - layout.Header - 3 - 32 - top
	local count = math.max(1, #data.Offers)
	local height = math.floor((available - (count - 1) * 12) / count)
	for i, offer in data.Offers do
		buy[offer.Id] = row(list, offer, layout, height, i)
	end
	return { Window = window, Tabs = tabs, Buy = buy }
end

return ShopBubble
