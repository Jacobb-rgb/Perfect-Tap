--[[
	Golem Capsules window in the light "Bubble" look (pure builder; preview
	first, then CapsuleView of step 7 moves onto it). Same content as the step 7
	shop: the three capsules, OPEN 1 / 3 / 10 with prices, Triple / Hexa Lucky,
	MY GOLEMS, and the exact chance of every golem (Roblox rule: odds before
	every open).

	  header   purple (Golems colour), capsule icon, title, coins, red X
	  tabs     STONE / CRYSTAL / ROYAL in each capsule's shell colour
	  left     the selected capsule on a glow, OPEN buttons, lucky boosts
	  right    a card per golem: 3D golem icon on its rarity colour, name, chance

	The builder takes plain data (Data) so it does not depend on the capsule
	configs; the controller fills it from CapsuleConfig / GolemConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local CapsuleBubble = {}

export type Golem = { Id: string, Name: string, Color: Color3, Chance: number, Lucky: boolean? }
export type Capsule = {
	Id: string,
	Name: string,
	Color: Color3,
	Glow: Color3,
	Currency: string, -- "Coins" | "Robux"
	Prices: { string }, -- shown on OPEN 1 / 3 / 10
}
export type Data = {
	Capsules: { Capsule },
	Selected: string,
	Golems: { Golem }, -- the selected capsule's odds, best chance first
	Coins: string,
	Owned: number,
	Cap: number,
	Boosts: { { Id: string, Label: string, Price: string, Active: boolean?, TimeLeft: string? } },
}

export type Layout = {
	Compact: boolean,
	Size: Vector2,
	Header: number,
	Tab: Vector2,
	Showcase: number,
	Open: Vector2,
	Boost: Vector2,
	Columns: number,
	Card: Vector2,
	NameSize: number,
	ChanceSize: number,
}

function CapsuleBubble.layout(uiScale: number): Layout
	if uiScale <= 0.75 then
		return {
			Compact = true,
			Size = Vector2.new(1300, 520),
			Header = 60,
			Tab = Vector2.new(140, 72),
			Showcase = 120,
			Open = Vector2.new(98, 72),
			Boost = Vector2.new(148, 72),
			Columns = 7,
			Card = Vector2.new(116, 124),
			NameSize = 22,
			ChanceSize = 22,
		}
	end
	return {
		Compact = false,
		Size = Vector2.new(980, 592),
		Header = 68,
		Tab = Vector2.new(150, 54),
		Showcase = 206,
		Open = Vector2.new(92, 72),
		Boost = Vector2.new(144, 52),
		Columns = 5,
		Card = Vector2.new(112, 104),
		NameSize = 16,
		ChanceSize = 17,
	}
end

-- 0.25 -> "25%", 0.025 -> "2.5%", 0.0007 -> "0.07%"
function CapsuleBubble.percent(chance: number): string
	local v = chance * 100
	local text
	if v >= 10 then
		text = string.format("%.0f", v)
	elseif v >= 1 then
		text = string.format("%.1f", v)
	elseif v >= 0.1 then
		text = string.format("%.2f", v)
	else
		text = string.format("%.3f", v)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. "%"
end

export type Refs = {
	Window: Bubble.Window,
	Tabs: { [string]: TextButton },
	Open: { [number]: TextButton },
	Boosts: { [string]: TextButton },
	MyGolems: TextButton,
	Cards: { [string]: Frame },
}

local function selectedCapsule(data: Data): Capsule
	for _, capsule in data.Capsules do
		if capsule.Id == data.Selected then
			return capsule
		end
	end
	return data.Capsules[1]
end

local function card(parent: Instance, golem: Golem, layout: Layout, order: number): Frame
	local _, holder = Bubble.card(parent, {
		Name = golem.Id,
		Label = golem.Name,
		Icon = "golem_" .. golem.Id,
		Color = golem.Color,
		Chip = CapsuleBubble.percent(golem.Chance),
		ChipRole = if golem.Lucky then "Build" else nil,
		Badge = if golem.Lucky then "x3" else nil,
		Size = layout.Card,
		NameSize = layout.NameSize,
		ChipSize = layout.ChanceSize,
		LayoutOrder = order,
	})
	return holder
end

function CapsuleBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local layout = CapsuleBubble.layout(uiScale)
	local window = Bubble.window(parent, {
		Name = "GolemCapsules",
		Title = "GOLEM CAPSULES",
		Icon = "capsule_Crystal",
		Role = "Golems",
		Size = layout.Size,
		HeaderHeight = layout.Header,
		TitleSize = if layout.Compact then 36 else 38,
	})
	local body = window.Body
	local capsule = selectedCapsule(data)

	-- coins in the header
	local coins = Bubble.chip(window.Header, "", Vector2.new(190, 44), 24, nil, {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -54, 0.5, 0),
		ZIndex = 5,
	})
	local coinsText = coins:FindFirstChild("Text") :: TextLabel
	coinsText.Text = data.Coins
	coinsText.Position = UDim2.fromOffset(34, 0)
	coinsText.Size = UDim2.new(1, -40, 1, 0)
	Bubble.icon(coins, "coin", 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 6 })

	-- capsule tabs
	local tabsRow = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, layout.Tab.Y + Theme.Lip),
	}, body)
	UIKit.list(tabsRow, Enum.FillDirection.Horizontal, 12)
	local tabs = {}
	for i, c in data.Capsules do
		local selected = c.Id == data.Selected
		local face = Bubble.button(tabsRow, {
			Name = c.Id,
			Text = string.upper(c.Id),
			Role = if selected then Bubble.roleFrom(c.Color) else "Plain",
			Size = layout.Tab,
			Icon = "capsule_" .. c.Id,
			TextSize = if layout.Compact then 24 else 22,
			LayoutOrder = i,
		})
		if selected then
			local stroke = face:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.Gold
				stroke.Thickness = 5
			end
		else
			local label = face:FindFirstChild("Label") :: TextLabel
			label.TextColor3 = Theme.InkSoft
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
				stroke.Transparency = 1
			end
		end
		tabs[c.Id] = face
	end

	-- golem count + MY GOLEMS (right of the tabs)
	local myGolems, myHolder = Bubble.button(body, {
		Name = "MyGolems",
		Text = "MY GOLEMS",
		Role = "Golems",
		Size = Vector2.new(if layout.Compact then 220 else 196, layout.Tab.Y),
		Icon = "golem_SilverSquire",
		TextSize = if layout.Compact then 24 else 21,
	})
	myHolder.AnchorPoint = Vector2.new(1, 0)
	myHolder.Position = UDim2.fromScale(1, 0)
	Bubble.chip(body, `GOLEMS {data.Owned}/{data.Cap}`, Vector2.new(if layout.Compact then 190 else 160, 36), if layout.Compact then 22 else 18, nil, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(if layout.Compact then 220 else 196) - 14, 0, layout.Tab.Y // 2),
	})

	-- left: the capsule, OPEN buttons, boosts
	local top = layout.Tab.Y + Theme.Lip + 14
	local leftWidth = 3 * layout.Open.X + 2 * 12
	local showHolder, showFace = Bubble.body(body, Bubble.role("Plain"), Vector2.new(leftWidth, layout.Showcase), {
		Name = "Showcase",
		Corner = 20,
		Gloss = false,
	})
	showHolder.Position = UDim2.fromOffset(0, top)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = capsule.Glow,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if layout.Compact
			then UDim2.fromOffset(layout.Showcase - 30, layout.Showcase - 30)
			else UDim2.fromOffset(layout.Showcase - 70, layout.Showcase - 70),
		ZIndex = 3,
	}, showFace)
	Bubble.corner(glow, layout.Showcase)
	Bubble.icon(showFace, "capsule_" .. capsule.Id, if layout.Compact then layout.Showcase - 20 else layout.Showcase - 56, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(if layout.Compact then 0.3 else 0.5, if layout.Compact then 0.5 else 0.43),
		ZIndex = 4,
	})
	if not layout.Compact then
		glow.Position = UDim2.fromScale(0.5, 0.43)
	end
	if layout.Compact then
		glow.Position = UDim2.fromScale(0.3, 0.5)
		Bubble.ink(showFace, string.upper(capsule.Name), 26, {
			Name = "Name",
			FontFace = Theme.TitleFont,
			Position = UDim2.new(0.5, -10, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			TextWrapped = true,
			ZIndex = 4,
		})
	else
		Bubble.ink(showFace, string.upper(capsule.Name), 24, {
			Name = "Name",
			FontFace = Theme.TitleFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 28),
			ZIndex = 4,
		})
	end

	local openRow = UIKit.new("Frame", {
		Name = "OpenRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top + layout.Showcase + Theme.Lip + 14),
		Size = UDim2.fromOffset(leftWidth, layout.Open.Y + Theme.Lip),
	}, body)
	UIKit.list(openRow, Enum.FillDirection.Horizontal, 12)
	local open = {}
	for i, count in { 1, 3, 10 } do
		open[count] = Bubble.button(openRow, {
			Name = "Open" .. count,
			Text = "OPEN " .. count,
			Role = "Go",
			Size = layout.Open,
			Price = capsule.Prices[i],
			PriceIcon = if capsule.Currency == "Robux" then "robux" else "coin",
			TextSize = if layout.Compact then 22 else 21,
			LayoutOrder = i,
		})
	end

	local boostRow = UIKit.new("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top + layout.Showcase + Theme.Lip + 14 + layout.Open.Y + Theme.Lip + 12),
		Size = UDim2.fromOffset(leftWidth, layout.Boost.Y + Theme.Lip),
	}, body)
	UIKit.list(boostRow, Enum.FillDirection.Horizontal, 12)
	local boosts = {}
	for i, boost in data.Boosts do
		local button = Bubble.button(boostRow, {
			Name = boost.Id,
			Text = boost.Label,
			Role = if boost.Id == "HexaLucky" then "Golems" else "Build",
			Size = Vector2.new((leftWidth - 12) // 2, layout.Boost.Y),
			Price = boost.Price,
			PriceIcon = "robux",
			TextSize = if layout.Compact then 21 else 17,
			LayoutOrder = i,
		})
		if boost.Active then
			-- running boost: the time left instead of the price, gold outline
			local price = button:FindFirstChild("Price")
			if price then
				price:Destroy()
			end
			Bubble.chip(button, boost.TimeLeft or "ACTIVE", Vector2.new(math.floor(layout.Boost.X * 0.7), if layout.Compact then 28 else 22), if layout.Compact then 20 else 16, nil, {
				Name = "TimeLeft",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -5),
			})
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.Gold
				stroke.Thickness = 5
			end
		end
		boosts[boost.Id] = button
	end

	-- right: the chance of every golem
	local oddsX = leftWidth + 18
	local oddsHolder, oddsFace = Bubble.body(body, Bubble.role("Plain"), Vector2.new(0, 0), { Name = "Odds", Corner = 20, Gloss = false })
	oddsHolder.Position = UDim2.fromOffset(oddsX, top)
	oddsHolder.Size = UDim2.new(1, -oddsX, 1, -top)
	for _, part in { "Shadow", "Lip" } do
		local piece = oddsHolder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 1, -Theme.Lip)
	end
	oddsFace.Size = UDim2.new(1, 0, 1, -Theme.Lip)
	local tint = oddsFace:FindFirstChildOfClass("UIGradient")
	if tint then
		tint.Color = ColorSequence.new(Theme.PanelTint, Theme.PanelTint)
	end
	Bubble.ink(oddsFace, "CHANCE OF EACH GOLEM", if layout.Compact then 22 else 19, {
		Name = "Heading",
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.InkSoft,
		ZIndex = 4,
	})
	local grid = UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 1, -58),
		ZIndex = 3,
	}, oddsFace)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Card.X, layout.Card.Y),
		CellPadding = UDim2.fromOffset(10, if layout.Compact then 22 else 20),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local cards = {}
	for i, golem in data.Golems do
		cards[golem.Id] = card(grid, golem, layout, i)
	end

	return { Window = window, Tabs = tabs, Open = open, Boosts = boosts, MyGolems = myGolems, Cards = cards }
end

return CapsuleBubble
