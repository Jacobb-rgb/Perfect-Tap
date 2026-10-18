--[[
	Backpack window in the light "Bubble" look (pure builder, preview first):
	what the player owns, one tab each.

	  header   blue (Backpack colour), backpack icon, shards + coins, red X
	  tabs     ORES (the Ore Pen) / GOLEMS / BLASTERS / ARTIFACTS
	  left     a scrolling grid of cards: the item's 3D look on its rarity
	           colour, name, value chip (raw ore: "?" until it is cleaned)
	  right    the selected item: big picture, rarity + grade chips, value,
	           SELL / PODIUM / KEEP

	In the game the item pictures are live 3D ViewportFrames of the item model
	(no uploads for ~120 ore x kind looks); the preview uses rendered icons.
	The builder takes plain data so the controller fills it from the save.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local BackpackBubble = {}

export type Item = {
	Id: string,
	Name: string, -- "Pristine Ruby", "Raw Copper"
	Icon: string,
	Color: Color3, -- rarity colour
	Rarity: string,
	Grade: string?, -- nil for raw ore
	Value: string, -- "$4.8K" or "?"
}

export type Data = {
	Tab: string,
	Items: { Item },
	Selected: string?,
	Coins: string,
	Shards: string,
	Used: number,
	Capacity: number,
}

export type Layout = {
	Compact: boolean,
	Size: Vector2,
	Header: number,
	Tab: Vector2,
	Card: Vector2,
	NameSize: number,
	ChipSize: number,
	Detail: number,
	Button: number,
}

function BackpackBubble.layout(uiScale: number): Layout
	if uiScale <= 0.75 then
		return {
			Compact = true,
			Size = Vector2.new(1300, 520),
			Header = 60,
			Tab = Vector2.new(208, 72),
			Card = Vector2.new(110, 124),
			NameSize = 19,
			ChipSize = 21,
			Detail = 360,
			Button = 72,
		}
	end
	return {
		Compact = false,
		Size = Vector2.new(1000, 592),
		Header = 68,
		Tab = Vector2.new(172, 54),
		Card = Vector2.new(94, 104),
		NameSize = 15,
		ChipSize = 16,
		Detail = 300,
		Button = 52,
	}
end

BackpackBubble.Tabs = {
	{ Id = "Ores", Label = "ORES", Icon = "item_Clean_Ruby", Role = "Backpack" },
	{ Id = "Golems", Label = "GOLEMS", Icon = "golem_GildedPorter", Role = "Golems" },
	{ Id = "Blasters", Label = "BLASTERS", Icon = "blaster", Role = "Vault" },
	{ Id = "Artifacts", Label = "ARTIFACTS", Icon = "artifact", Role = "Build" },
}

export type Refs = {
	Window: Bubble.Window,
	Tabs: { [string]: TextButton },
	Cards: { [string]: TextButton },
	Sell: TextButton,
	Podium: TextButton,
	Keep: TextButton,
}

local function headerChip(window: Bubble.Window, icon: string, text: string, rightOffset: number, width: number): Frame
	local chip = Bubble.chip(window.Header, "", Vector2.new(width, 44), 24, nil, {
		Name = icon,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightOffset, 0.5, 0),
		ZIndex = 5,
	})
	local label = chip:FindFirstChild("Text") :: TextLabel
	label.Text = text
	label.Position = UDim2.fromOffset(30, 0)
	label.Size = UDim2.new(1, -36, 1, 0)
	Bubble.icon(chip, icon, 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 6 })
	return chip
end

local function detail(parent: Frame, item: Item, layout: Layout): (TextButton, TextButton, TextButton)
	local pad = 12
	if layout.Compact then
		-- picture left, name / chips / value right, then the buttons
		local glow = UIKit.new("Frame", {
			Name = "Glow",
			BackgroundColor3 = item.Color,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(pad, pad),
			Size = UDim2.fromOffset(100, 100),
			ZIndex = 3,
		}, parent)
		Bubble.corner(glow, 50)
		Bubble.icon(glow, item.Icon, 112, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		Bubble.ink(parent, string.upper(item.Name), 26, {
			Name = "ItemName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(pad + 112, pad),
			Size = UDim2.new(1, -pad * 2 - 112, 0, 30),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		local chips = UIKit.new("Frame", {
			Name = "Chips",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(pad + 112, pad + 36),
			Size = UDim2.new(1, -pad * 2 - 112, 0, 30),
			ZIndex = 4,
		}, parent)
		UIKit.list(chips, Enum.FillDirection.Horizontal, 8)
		Bubble.chip(chips, string.upper(item.Rarity), Vector2.new(108, 30), 18, Bubble.roleFrom(item.Color), { LayoutOrder = 1 })
		Bubble.chip(chips, string.upper(item.Grade or "Dirty"), Vector2.new(104, 30), 18, nil, { LayoutOrder = 2 })
		Bubble.iconText(parent, "coin", item.Value, 28, {
			Name = "Value",
			Position = UDim2.fromOffset(pad + 112, pad + 72),
			Size = UDim2.new(0, 160, 0, 34),
		}, true)
	else
		local glow = UIKit.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = item.Color,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, pad + 6),
			Size = UDim2.fromOffset(118, 118),
			ZIndex = 3,
		}, parent)
		Bubble.corner(glow, 59)
		Bubble.icon(glow, item.Icon, 136, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		Bubble.ink(parent, string.upper(item.Name), 28, {
			Name = "ItemName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(pad, pad + 132),
			Size = UDim2.new(1, -pad * 2, 0, 32),
			TextScaled = true,
			ZIndex = 4,
		})
		local chips = UIKit.new("Frame", {
			Name = "Chips",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(pad, pad + 170),
			Size = UDim2.new(1, -pad * 2, 0, 28),
			ZIndex = 4,
		}, parent)
		UIKit.list(chips, Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
		Bubble.chip(chips, string.upper(item.Rarity), Vector2.new(104, 28), 16, Bubble.roleFrom(item.Color), { LayoutOrder = 1 })
		Bubble.chip(chips, string.upper(item.Grade or "Dirty"), Vector2.new(104, 28), 16, nil, { LayoutOrder = 2 })
		Bubble.iconText(parent, "coin", item.Value, 30, {
			Name = "Value",
			Position = UDim2.fromOffset(0, pad + 204),
		}, true)
	end
	-- buttons at the bottom: SELL full width, PODIUM and KEEP side by side
	local inner = layout.Detail - pad * 2
	local h = layout.Button
	local sell, sellHolder = Bubble.button(parent, {
		Name = "Sell",
		Text = "SELL " .. item.Value,
		Role = "Go",
		Size = Vector2.new(inner, h),
		Icon = "coins",
		TextSize = if layout.Compact then 28 else 24,
	})
	sellHolder.AnchorPoint = Vector2.new(0, 1)
	sellHolder.Position = UDim2.new(0, pad, 1, -pad - h - Theme.Lip - 10)
	local podium, podiumHolder = Bubble.button(parent, {
		Name = "Podium",
		Text = "PODIUM",
		Role = "Lobby",
		Size = Vector2.new((inner - 10) // 2, h),
		TextSize = if layout.Compact then 24 else 20,
	})
	podiumHolder.AnchorPoint = Vector2.new(0, 1)
	podiumHolder.Position = UDim2.new(0, pad, 1, -pad)
	local keep, keepHolder = Bubble.button(parent, {
		Name = "Keep",
		Text = "KEEP",
		Role = "Build",
		Size = Vector2.new((inner - 10) // 2, h),
		TextSize = if layout.Compact then 24 else 20,
	})
	keepHolder.AnchorPoint = Vector2.new(1, 1)
	keepHolder.Position = UDim2.new(1, -pad, 1, -pad)
	return sell, podium, keep
end

function BackpackBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local layout = BackpackBubble.layout(uiScale)
	local window = Bubble.window(parent, {
		Name = "Backpack",
		Title = "BACKPACK",
		Icon = "backpack",
		Role = "Backpack",
		Size = layout.Size,
		HeaderHeight = layout.Header,
		TitleSize = if layout.Compact then 36 else 38,
	})
	headerChip(window, "coin", data.Coins, 54, 190)
	headerChip(window, "shard", data.Shards, 54 + 190 + 40, 130)

	local body = window.Body
	local tabs = Bubble.tabs(body, BackpackBubble.Tabs, data.Tab, layout.Tab, if layout.Compact then 24 else 20)
	Bubble.chip(body, `PEN {data.Used}/{data.Capacity}`, Vector2.new(if layout.Compact then 170 else 140, 36), if layout.Compact then 22 else 18, nil, {
		Name = "Capacity",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0, layout.Tab.Y // 2),
	})

	local top = layout.Tab.Y + Theme.Lip + 14
	local left = Bubble.inset(body, "Items", UDim2.fromOffset(0, top), UDim2.new(1, -layout.Detail - 18, 1, -top))
	Bubble.ink(left, "YOUR ORES", if layout.Compact then 22 else 19, {
		Name = "Heading",
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.InkSoft,
		ZIndex = 4,
	})
	local grid = Bubble.grid(left, layout.Card, Vector2.new(10, if layout.Compact then 22 else 20), {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 1, -40),
	})
	local cards = {}
	local selected: Item? = nil
	for i, item in data.Items do
		local isSelected = item.Id == data.Selected
		if isSelected then
			selected = item
		end
		cards[item.Id] = Bubble.card(grid, {
			Name = item.Id,
			Label = item.Name,
			Icon = item.Icon,
			Color = item.Color,
			Chip = item.Value,
			Size = layout.Card,
			NameSize = layout.NameSize,
			ChipSize = layout.ChipSize,
			Selected = isSelected,
			LayoutOrder = i,
		})
	end

	local right = Bubble.inset(body, "Detail", UDim2.new(1, -layout.Detail, 0, top), UDim2.new(0, layout.Detail, 1, -top))
	local sell, podium, keep = detail(right, selected or data.Items[1], layout)
	return { Window = window, Tabs = tabs, Cards = cards, Sell = sell, Podium = podium, Keep = keep }
end

return BackpackBubble
