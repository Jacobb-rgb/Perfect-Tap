--[[
	MY GOLEMS window in the light "Bubble" look (pure builder, preview first;
	step 7's GolemView moves onto it). Same content as step 7:

	  header   purple (Golems colour), golem icon, title, count, red X
	  top      the 3 equipped slots (golem, name, bonus), EQUIP BEST, CAPSULES
	  left     every owned golem as a rarity card: bonus chip, "E" when
	           equipped, a lock when locked; the total equipped bonus on top
	  right    the selected golem: picture, rarity, bonus, lore,
	           UNEQUIP / LOCK / DELETE
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local GolemsBubble = {}

export type Golem = {
	Id: string, -- the owned entry (unique)
	Kind: string, -- GolemConfig id (the icon: golem_<Kind>)
	Name: string,
	Rarity: string,
	Color: Color3, -- rarity colour
	Bonus: string, -- "+16% Mining speed"
	Short: string, -- "+16% MINING"
	Lore: string,
	Equipped: boolean?,
	Locked: boolean?,
}

export type Data = { Golems: { Golem }, Selected: string?, Total: string, Count: number, Cap: number }

export type Layout = {
	Compact: boolean,
	Size: Vector2,
	Header: number,
	Slot: Vector2,
	Action: Vector2,
	Card: Vector2,
	NameSize: number,
	ChipSize: number,
	Detail: number,
	Button: number,
}

function GolemsBubble.layout(uiScale: number): Layout
	if uiScale <= 0.75 then
		return {
			Compact = true,
			Size = Vector2.new(1300, 520),
			Header = 60,
			Slot = Vector2.new(250, 72),
			Action = Vector2.new(200, 72),
			Card = Vector2.new(124, 124),
			NameSize = 19,
			ChipSize = 16,
			Detail = 360,
			Button = 72,
		}
	end
	return {
		Compact = false,
		Size = Vector2.new(1000, 592),
		Header = 68,
		Slot = Vector2.new(200, 80),
		Action = Vector2.new(158, 56),
		Card = Vector2.new(104, 112),
		NameSize = 15,
		ChipSize = 14,
		Detail = 300,
		Button = 52,
	}
end

export type Refs = {
	Window: Bubble.Window,
	Slots: { TextButton },
	Cards: { [string]: TextButton },
	EquipBest: TextButton,
	Capsules: TextButton,
	Unequip: TextButton,
	Lock: TextButton,
	Delete: TextButton,
}

local function equippedSlot(parent: Instance, golem: Golem?, layout: Layout, order: number): TextButton
	local role = if golem then Bubble.roleFrom(golem.Color) else Bubble.role("Plain")
	local holder, face = Bubble.body(parent, role, layout.Slot, { Name = "Slot" .. order, Corner = 18, Clickable = true })
	holder.LayoutOrder = order
	if golem then
		local iconSize = layout.Slot.Y + 14
		Bubble.icon(face, "golem_" .. golem.Kind, iconSize, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -4, 0.5, -6) })
		Bubble.text(face, golem.Name, if layout.Compact then 22 else 19, {
			Name = "Name",
			Position = UDim2.fromOffset(iconSize - 6, 6),
			Size = UDim2.new(1, -iconSize, 0.5, -4),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.text(face, golem.Bonus, if layout.Compact then 18 else 15, {
			Name = "Bonus",
			Position = UDim2.new(0, iconSize - 6, 0.5, 0),
			Size = UDim2.new(1, -iconSize, 0.5, -8),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
	else
		Bubble.ink(face, "EMPTY SLOT", 18, { Name = "Empty", Size = UDim2.fromScale(1, 1), TextColor3 = Theme.InkSoft, ZIndex = 4 })
	end
	return face :: TextButton
end

local function detail(parent: Frame, golem: Golem, layout: Layout): (TextButton, TextButton, TextButton)
	local pad = 12
	local glowSize = if layout.Compact then 100 else 104
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = if layout.Compact then Vector2.new(0, 0) else Vector2.new(0.5, 0),
		BackgroundColor3 = golem.Color,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = if layout.Compact then UDim2.fromOffset(pad, pad) else UDim2.new(0.5, 0, 0, pad),
		Size = UDim2.fromOffset(glowSize, glowSize),
		ZIndex = 3,
	}, parent)
	Bubble.corner(glow, glowSize)
	Bubble.icon(glow, "golem_" .. golem.Kind, glowSize + 20, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -6) })
	local textX = if layout.Compact then pad + glowSize + 12 else pad
	local textW = if layout.Compact then -pad * 2 - glowSize - 12 else -pad * 2
	local y = if layout.Compact then pad else pad + glowSize + 8
	local align = if layout.Compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	Bubble.ink(parent, string.upper(golem.Name), 26, {
		Name = "GolemName",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(textX, y),
		Size = UDim2.new(1, textW, 0, 30),
		TextScaled = true,
		TextXAlignment = align,
		ZIndex = 4,
	})
	local chipRow = UIKit.new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, y + 34),
		Size = UDim2.new(1, textW, 0, 28),
		ZIndex = 4,
	}, parent)
	UIKit.list(chipRow, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = if layout.Compact then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,
	})
	Bubble.chip(chipRow, string.upper(golem.Rarity), Vector2.new(110, 28), 16, Bubble.roleFrom(golem.Color), { LayoutOrder = 1 })
	if golem.Equipped then
		Bubble.chip(chipRow, "EQUIPPED", Vector2.new(110, 28), 16, "Go", { LayoutOrder = 2 })
	end
	Bubble.text(parent, golem.Bonus, if layout.Compact then 22 else 20, {
		Name = "Bonus",
		Position = UDim2.fromOffset(textX, y + 66),
		Size = UDim2.new(1, textW, 0, 26),
		TextColor3 = Theme.Good,
		TextXAlignment = align,
		ZIndex = 4,
	})
	local loreY = if layout.Compact then pad + glowSize + 10 else y + 96
	Bubble.ink(parent, golem.Lore, if layout.Compact then 18 else 15, {
		Name = "Lore",
		Position = UDim2.fromOffset(pad, loreY),
		Size = UDim2.new(1, -pad * 2, 0, if layout.Compact then 46 else 40),
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextXAlignment = align,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	local row = UIKit.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, pad, 1, -pad + 2),
		Size = UDim2.new(1, -pad * 2, 0, layout.Button + Theme.Lip),
		ZIndex = 4,
	}, parent)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8)
	local w = (layout.Detail - pad * 2 - 16) // 3
	local text = if layout.Compact then 19 else 16
	local unequip = Bubble.button(row, {
		Name = "Unequip",
		Text = if golem.Equipped then "UNEQUIP" else "EQUIP",
		Role = "Build",
		Size = Vector2.new(w, layout.Button),
		TextSize = text,
		LayoutOrder = 1,
	})
	local lock = Bubble.button(row, {
		Name = "Lock",
		Text = if golem.Locked then "UNLOCK" else "LOCK",
		Role = "Lobby",
		Size = Vector2.new(w, layout.Button),
		TextSize = text,
		LayoutOrder = 2,
	})
	local delete = Bubble.button(row, {
		Name = "Delete",
		Text = "DELETE",
		Role = "Danger",
		Size = Vector2.new(w, layout.Button),
		TextSize = text,
		LayoutOrder = 3,
	})
	return unequip, lock, delete
end

function GolemsBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local layout = GolemsBubble.layout(uiScale)
	local window = Bubble.window(parent, {
		Name = "MyGolems",
		Title = "MY GOLEMS",
		Icon = "golem_GildedPorter",
		Role = "Golems",
		Size = layout.Size,
		HeaderHeight = layout.Header,
	})
	Bubble.chip(window.Header, `{data.Count} / {data.Cap}`, Vector2.new(120, 40), 22, nil, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		ZIndex = 5,
	})
	local body = window.Body

	-- equipped slots + EQUIP BEST / CAPSULES
	local slotsRow = UIKit.new("Frame", {
		Name = "Equipped",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, layout.Slot.Y + Theme.Lip),
	}, body)
	UIKit.list(slotsRow, Enum.FillDirection.Horizontal, 12)
	local equipped = {}
	for _, golem in data.Golems do
		if golem.Equipped then
			table.insert(equipped, golem)
		end
	end
	local slots = {}
	for i = 1, 3 do
		table.insert(slots, equippedSlot(slotsRow, equipped[i], layout, i))
	end
	local capsules, capsHolder = Bubble.button(body, {
		Name = "Capsules",
		Text = "CAPSULES",
		Role = "Golems",
		Size = layout.Action,
		Icon = "capsule_Crystal",
		TextSize = if layout.Compact then 22 else 19,
	})
	capsHolder.AnchorPoint = Vector2.new(1, 0)
	capsHolder.Position = UDim2.new(1, 0, 0, (layout.Slot.Y - layout.Action.Y) // 2)
	local best, bestHolder = Bubble.button(body, {
		Name = "EquipBest",
		Text = "EQUIP BEST",
		Role = "Go",
		Size = layout.Action,
		TextSize = if layout.Compact then 22 else 19,
	})
	bestHolder.AnchorPoint = Vector2.new(1, 0)
	bestHolder.Position = UDim2.new(1, -layout.Action.X - 12, 0, (layout.Slot.Y - layout.Action.Y) // 2)

	-- the grid
	local top = layout.Slot.Y + Theme.Lip + 14
	local left = Bubble.inset(body, "Owned", UDim2.fromOffset(0, top), UDim2.new(1, -layout.Detail - 18, 1, -top))
	Bubble.text(left, "TOTAL: " .. data.Total, if layout.Compact then 21 else 17, {
		Name = "Total",
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 28),
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = 4,
	})
	local grid = Bubble.grid(left, layout.Card, Vector2.new(10, if layout.Compact then 22 else 20), {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 1, -40),
	})
	local cards = {}
	local selected: Golem? = nil
	for i, golem in data.Golems do
		local isSelected = golem.Id == data.Selected
		if isSelected then
			selected = golem
		end
		cards[golem.Id] = Bubble.card(grid, {
			Name = golem.Id,
			Label = golem.Name,
			Icon = "golem_" .. golem.Kind,
			Color = golem.Color,
			Chip = golem.Short,
			ChipWidth = layout.Card.X - 10,
			Size = layout.Card,
			NameSize = layout.NameSize,
			ChipSize = layout.ChipSize,
			Badge = if golem.Equipped then "E" else nil,
			BadgeColor = Theme.Good,
			CornerIcon = if golem.Locked then "lock" else nil,
			Selected = isSelected,
			LayoutOrder = i,
		})
	end

	local right = Bubble.inset(body, "Detail", UDim2.new(1, -layout.Detail, 0, top), UDim2.new(0, layout.Detail, 1, -top))
	local unequip, lock, delete = detail(right, selected or data.Golems[1], layout)
	return {
		Window = window,
		Slots = slots,
		Cards = cards,
		EquipBest = best,
		Capsules = capsules,
		Unequip = unequip,
		Lock = lock,
		Delete = delete,
	}
end

return GolemsBubble
