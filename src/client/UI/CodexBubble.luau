--[[
	ORE CODEX in the light "Bubble" look (pure builder, preview first; steps
	6-7's CodexView moves onto it): every ore of Terra, found or "???".

	  header   teal (Codex colour), book icon, "14 / 30 FOUND", red X
	  left     a card per ore in its rarity colour (NEW! on fresh finds),
	           unknown ores as plain "?" cards
	  right    the selected ore: picture, rarity, podium income, sell price,
	           blaster level, where it is found, its lore
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local Bubble = require(script.Parent.Bubble)

local CodexBubble = {}

export type Ore = { Id: string, Name: string, Rarity: string, Color: Color3, Found: boolean, New: boolean? }
export type Detail = { Podium: string, Sells: string, Blaster: string, FoundIn: string, Lore: string }
export type Data = { Ores: { Ore }, Selected: string, Detail: Detail, Found: number, Total: number }
export type Refs = { Window: Bubble.Window, Cards: { [string]: TextButton } }

local function unknown(parent: Instance, id: string, size: Vector2, order: number, textSize: number): TextButton
	local holder, face = Bubble.body(parent, Bubble.role("Plain"), Vector2.new(size.X, size.Y - Theme.Lip), { Name = id, Corner = 16, Clickable = true })
	holder.LayoutOrder = order
	Bubble.ink(face, "?", math.floor(size.Y * 0.5), {
		Name = "Mystery",
		FontFace = Theme.TitleFont,
		Size = UDim2.new(1, 0, 1, -textSize),
		TextColor3 = Theme.InkSoft,
		ZIndex = 4,
	})
	Bubble.chip(face, "???", Vector2.new(math.floor(size.X * 0.66), textSize + 8), textSize, nil, {
		Name = "Chance",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
	})
	return face :: TextButton
end

local function line(parent: Instance, label: string, text: string, y: number, size: number, color: Color3?): number
	Bubble.ink(parent, label, size - 2, {
		Name = label,
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, size),
		TextColor3 = color or Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	Bubble.ink(parent, text, size, {
		Name = label .. "Value",
		Position = UDim2.fromOffset(14, y + size),
		Size = UDim2.new(1, -28, 0, size * 2),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	return y + size * 3 + 10
end

function CodexBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Codex",
		Title = "ORE CODEX",
		Icon = "book",
		Role = "Codex",
		Size = size,
		HeaderHeight = header,
	})
	Bubble.chip(window.Header, `{data.Found} / {data.Total} FOUND`, Vector2.new(210, 42), 22, nil, {
		Name = "Found",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		ZIndex = 5,
	})
	local body = window.Body
	local detailW = if compact then 380 else 300
	local card = if compact then Vector2.new(112, 120) else Vector2.new(94, 104)
	local nameSize = if compact then 20 else 15
	local chipSize = if compact then 16 else 12
	local left = Bubble.inset(body, "Ores", UDim2.fromOffset(0, 0), UDim2.new(1, -detailW - 18, 1, 0))
	Bubble.ink(left, "EVERY ORE OF TERRA: FIND THEM BY CLEANING DIRTY ORE", if compact then 19 else 15, {
		Name = "Heading",
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 26),
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = 4,
	})
	local grid = Bubble.grid(left, card, Vector2.new(10, 20), {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 1, -40),
	})
	local cards = {}
	local selected: Ore? = nil
	for i, ore in data.Ores do
		if ore.Found then
			if ore.Id == data.Selected then
				selected = ore
			end
			cards[ore.Id] = Bubble.card(grid, {
				Name = ore.Id,
				Label = ore.Name,
				Icon = "item_Clean_" .. ore.Id,
				Color = ore.Color,
				Chip = string.upper(ore.Rarity),
				ChipWidth = card.X - 8,
				Size = card,
				NameSize = nameSize,
				ChipSize = chipSize,
				Badge = if ore.New then "NEW" else nil,
				BadgeColor = Theme.Roles.Vault.Base,
				Selected = ore.Id == data.Selected,
				LayoutOrder = i,
			})
		else
			cards[ore.Id] = unknown(grid, ore.Id, card, i, chipSize)
		end
	end

	local right = Bubble.inset(body, "Detail", UDim2.new(1, -detailW, 0, 0), UDim2.new(0, detailW, 1, 0))
	local ore = selected or data.Ores[1]
	local d = data.Detail
	local textSize = if compact then 18 else 15
	if compact then
		Bubble.glowIcon(right, "item_Clean_" .. ore.Id, ore.Color, 96, { Position = UDim2.fromOffset(12, 12) })
		Bubble.ink(right, string.upper(ore.Name), 30, {
			Name = "OreName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(122, 22),
			Size = UDim2.new(1, -134, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.chip(right, string.upper(ore.Rarity), Vector2.new(120, 30), 18, Bubble.roleFrom(ore.Color), { Position = UDim2.fromOffset(122, 62) })
		local y = 120
		y = line(right, "PODIUM", d.Podium, y, textSize, Theme.Good)
		y = line(right, "SELLS FOR", d.Sells, y, textSize)
		line(right, "FOUND IN", d.FoundIn, y, textSize)
	else
		Bubble.glowIcon(right, "item_Clean_" .. ore.Id, ore.Color, 104, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
		})
		Bubble.ink(right, string.upper(ore.Name), 30, {
			Name = "OreName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(12, 124),
			Size = UDim2.new(1, -24, 0, 34),
			ZIndex = 4,
		})
		Bubble.chip(right, string.upper(ore.Rarity), Vector2.new(110, 28), 16, Bubble.roleFrom(ore.Color), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 160),
		})
		local y = 196
		y = line(right, "PODIUM", d.Podium, y, textSize, Theme.Good)
		y = line(right, "SELLS FOR", d.Sells, y, textSize)
		y = line(right, "FOUND IN", d.FoundIn, y, textSize)
		Bubble.ink(right, d.Lore, 14, {
			Name = "Lore",
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -28, 1, -y - 10),
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 4,
		})
	end
	return { Window = window, Cards = cards }
end

return CodexBubble
