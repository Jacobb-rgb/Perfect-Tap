--[[
	The light "Bubble" HUD (owner's pick A, 2026-10-18). Pure builder; a
	controller fills it in.

	  top-left      coins pill (3D coin, amount, + button) and the income chip
	  top-centre    the teleport bar: BASE / LOBBY / VAULT tabs with 3D icons
	  left          the main menu tiles: BACKPACK, GOLEMS, BUILD, SHOP + MORE
	                (2 columns on PC, 3 columns on phones so the tiles stay above
	                the thumbstick)
	  bottom-centre the hotbar: the blaster in slot 1, carried items after it
	  under the bar toasts (white pills with an icon)

	Compact (phones, uiScale <= CompactScale): bigger touch targets in design
	units (>= 44 pt at uiScale 0.62) and the income chip beside the coins.
	Designed for 720 design units of screen height.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local HudBubble = {}

HudBubble.CompactScale = 0.75

export type MenuEntry = { Id: string, Label: string, Icon: string, Role: string }

-- The main tiles (owner: only the main 4-5 on the left, the rest behind MORE).
HudBubble.Menu = {
	{ Id = "Backpack", Label = "BACKPACK", Icon = "backpack", Role = "Backpack" },
	{ Id = "Golems", Label = "GOLEMS", Icon = "golem_GildedPorter", Role = "Golems" },
	{ Id = "Build", Label = "BUILD", Icon = "build", Role = "Build" },
	{ Id = "Shop", Label = "SHOP", Icon = "shop", Role = "Shop" },
	{ Id = "More", Label = "MORE", Icon = "more", Role = "More" },
} :: { MenuEntry }

HudBubble.Spots = {
	{ Id = "Base", Label = "BASE", Icon = "base", Role = "Base" },
	{ Id = "Lobby", Label = "LOBBY", Icon = "lobby", Role = "Lobby" },
	{ Id = "Vault", Label = "VAULT", Icon = "vault", Role = "Vault" },
} :: { MenuEntry }

export type Layout = {
	Compact: boolean,
	Tile: number,
	TileGap: number,
	Columns: number,
	TabWidth: number,
	TabHeight: number,
	Slot: number,
	SlotGap: number,
	Slots: number,
}

function HudBubble.layout(uiScale: number): Layout
	if uiScale <= HudBubble.CompactScale then
		return {
			Compact = true,
			Tile = 78,
			TileGap = 16,
			Columns = 3,
			TabWidth = 118,
			TabHeight = 72,
			Slot = 76,
			SlotGap = 10,
			Slots = 5,
		}
	end
	return {
		Compact = false,
		Tile = 88,
		TileGap = 16,
		Columns = 2,
		TabWidth = 140,
		TabHeight = 52,
		Slot = 70,
		SlotGap = 10,
		Slots = 6,
	}
end

export type Refs = {
	Gui: ScreenGui,
	Coins: TextLabel,
	CoinsPlus: TextButton,
	Income: TextLabel,
	Menu: { [string]: TextButton },
	Tabs: { [string]: TextButton },
	Slots: { Frame },
	CarryLabel: TextLabel,
	Toasts: Frame,
}

local function coinsPill(gui: ScreenGui, layout: Layout): (TextLabel, TextButton, TextLabel)
	local h = if layout.Compact then 58 else 52
	local holder, face = Bubble.body(gui, Bubble.role("Plain"), Vector2.new(250, h), { Name = "Coins", Corner = h // 2 })
	holder.Position = UDim2.fromOffset(34, 16)
	Bubble.icon(face, "coin", h + 18, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
	})
	local amount = Bubble.ink(face, "$0", if layout.Compact then 32 else 30, {
		Name = "Amount",
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -44 - h, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local plusHolder, plusFace = Bubble.body(face, Bubble.role("Go"), Vector2.new(h - 14, h - 14), {
		Name = "Plus",
		Corner = 12,
		Clickable = true,
	})
	plusHolder.AnchorPoint = Vector2.new(1, 0.5)
	plusHolder.Position = UDim2.new(1, -6, 0.5, -2)
	plusHolder.ZIndex = 4
	Bubble.text(plusFace, "+", 30, { Size = UDim2.fromScale(1, 1), ZIndex = 5 })

	local chipHolder, chipFace = Bubble.body(gui, Bubble.role("Go"), Vector2.new(124, 30), { Name = "Income", Corner = 15 })
	chipHolder.Position = if layout.Compact then UDim2.fromOffset(300, 30) else UDim2.fromOffset(76, 16 + h + Theme.Lip + 6)
	local income = Bubble.text(chipFace, "+$0/s", 19, { Name = "Amount", Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	return amount, plusFace :: TextButton, income
end

local function teleportBar(gui: ScreenGui, layout: Layout): { [string]: TextButton }
	local count = #HudBubble.Spots
	local width = count * layout.TabWidth + (count - 1) * 14
	local bar = UIKit.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(width, layout.TabHeight + Theme.Lip),
	}, gui)
	UIKit.list(bar, Enum.FillDirection.Horizontal, 14)
	local tabs = {}
	for i, spot in HudBubble.Spots do
		local holder, face = Bubble.body(bar, Bubble.role(spot.Role), Vector2.new(layout.TabWidth, layout.TabHeight), {
			Name = spot.Id,
			Corner = 16,
			Clickable = true,
		})
		holder.LayoutOrder = i
		if layout.Compact then
			Bubble.icon(face, spot.Icon, 52, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -12) })
			Bubble.text(face, spot.Label, 20, {
				Name = "Label",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, 0, 0, 24),
				ZIndex = 4,
			})
		else
			Bubble.icon(face, spot.Icon, 58, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -10, 0.5, -4) })
			Bubble.text(face, spot.Label, 23, {
				Name = "Label",
				Position = UDim2.fromOffset(50, 0),
				Size = UDim2.new(1, -56, 1, 0),
				ZIndex = 4,
			})
		end
		tabs[spot.Id] = face :: TextButton
	end
	return tabs
end

export type MenuMetrics = {
	Origin: UDim2, -- the menu's top-left
	Width: number,
	Height: number,
	CellHeight: number,
	RowGap: number,
}

-- Where the left menu sits (pure layout math, also used by the MORE flyout).
function HudBubble.menuMetrics(layout: Layout, count: number?): MenuMetrics
	local rows = math.ceil((count or #HudBubble.Menu) / layout.Columns)
	local cellH = layout.Tile + Theme.Lip
	local rowGap = layout.TileGap + 8 -- room for the icons popping out of the row below
	local width = layout.Columns * layout.Tile + (layout.Columns - 1) * layout.TileGap
	local height = rows * cellH + (rows - 1) * rowGap
	local origin = if layout.Compact then UDim2.fromOffset(18, 112) else UDim2.new(0, 18, 0.5, 24 - height // 2)
	return { Origin = origin, Width = width, Height = height, CellHeight = cellH, RowGap = rowGap }
end

-- Top-left of menu tile `index` (1-based).
function HudBubble.tilePosition(layout: Layout, index: number): UDim2
	local m = HudBubble.menuMetrics(layout)
	local col = (index - 1) % layout.Columns
	local row = (index - 1) // layout.Columns
	return UDim2.new(
		m.Origin.X.Scale,
		m.Origin.X.Offset + col * (layout.Tile + layout.TileGap),
		m.Origin.Y.Scale,
		m.Origin.Y.Offset + row * (m.CellHeight + m.RowGap)
	)
end

local function menuTiles(gui: ScreenGui, layout: Layout): { [string]: TextButton }
	local m = HudBubble.menuMetrics(layout)
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Position = m.Origin,
		Size = UDim2.fromOffset(m.Width, m.Height),
	}, gui)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight),
		CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, menu)
	local tiles = {}
	for i, entry in HudBubble.Menu do
		local face = Bubble.tile(menu, {
			Name = entry.Id,
			Label = entry.Label,
			Icon = entry.Icon,
			Role = entry.Role,
			Size = layout.Tile,
			LayoutOrder = i,
		})
		tiles[entry.Id] = face
	end
	return tiles
end

local function hotbar(gui: ScreenGui, layout: Layout): ({ Frame }, TextLabel)
	local width = layout.Slots * layout.Slot + (layout.Slots - 1) * layout.SlotGap
	local bar = UIKit.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(width, layout.Slot + Theme.Lip),
	}, gui)
	UIKit.list(bar, Enum.FillDirection.Horizontal, layout.SlotGap)
	local slots = {}
	for i = 1, layout.Slots do
		local holder, face = Bubble.body(bar, Bubble.role("Plain"), Vector2.new(layout.Slot, layout.Slot), {
			Name = "Slot" .. i,
			Corner = 16,
			Clickable = true,
		})
		holder.LayoutOrder = i
		if not layout.Compact then
			Bubble.ink(face, tostring(i), 16, {
				Name = "Key",
				Position = UDim2.fromOffset(7, 3),
				Size = UDim2.fromOffset(16, 18),
				TextColor3 = Theme.InkSoft,
				ZIndex = 4,
			})
		end
		table.insert(slots, holder)
	end
	local label = Bubble.text(gui, "CARRYING 0/1", 18, {
		Name = "CarryLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16 - layout.Slot - Theme.Lip - 8),
		Size = UDim2.fromOffset(240, 22),
	})
	return slots, label
end

-- Behind MORE (owner: only the main buttons on the left, the rest here).
HudBubble.More = {
	{ Id = "Wheel", Label = "WHEEL", Icon = "wheel", Role = "Danger" },
	{ Id = "Codex", Label = "CODEX", Icon = "book", Role = "Base" },
	{ Id = "Artifacts", Label = "ARTIFACTS", Icon = "artifact", Role = "Build" },
	{ Id = "Boards", Label = "BOARDS", Icon = "trophy", Role = "Vault" },
	{ Id = "Gear", Label = "GEAR", Icon = "helmet", Role = "Lobby" },
	{ Id = "Settings", Label = "SETTINGS", Icon = "cog", Role = "More" },
} :: { MenuEntry }

export type MoreRefs = { Panel: Frame, Tiles: { [string]: TextButton }, Close: TextButton }

--[[
	The MORE flyout: a white bubble right of the menu with a pointer at the
	MORE tile and a tile per entry (3 columns). On PC its bottom lines up with
	MORE; on phones it sits under the coins, clear of the thumbstick.
]]
function HudBubble.moreMenu(refs: Refs, uiScale: number): MoreRefs
	local layout = HudBubble.layout(uiScale)
	local m = HudBubble.menuMetrics(layout)
	local more = HudBubble.tilePosition(layout, #HudBubble.Menu)
	local cols = 3
	local pad = 16
	local head = 50
	local rows = math.ceil(#HudBubble.More / cols)
	local width = cols * layout.Tile + (cols - 1) * layout.TileGap + pad * 2
	local height = head + rows * m.CellHeight + (rows - 1) * m.RowGap + pad
	local left = m.Origin.X.Offset + m.Width + 26
	local top = if layout.Compact
		then UDim.new(0, 96)
		else UDim.new(more.Y.Scale, more.Y.Offset + m.CellHeight - height)
	local pointer = UIKit.new("Frame", {
		Name = "MorePointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, left, more.Y.Scale, more.Y.Offset + layout.Tile // 2),
		Rotation = 45,
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 1,
	}, refs.Gui)
	Bubble.corner(pointer, 6)
	Bubble.stroke(pointer)
	local holder, face = Bubble.body(refs.Gui, Bubble.role("Plain"), Vector2.new(width, height), {
		Name = "MorePanel",
		Corner = 24,
		Gloss = false,
	})
	holder.Position = UDim2.new(0, left, top.Scale, top.Offset)
	Bubble.ink(face, "MORE", 28, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(pad + 2, 8),
		Size = UDim2.new(1, -pad * 2 - 50, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local close, closeHolder = Bubble.button(face, { Name = "Close", Text = "X", Role = "Danger", Size = Vector2.new(44, 44), TextSize = 26, Corner = 14 })
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -10, 0, 8)
	local grid = UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, head),
		Size = UDim2.new(1, -pad * 2, 1, -head - pad),
		ZIndex = 3,
	}, face)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight),
		CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local tiles = {}
	for i, entry in HudBubble.More do
		tiles[entry.Id] = Bubble.tile(grid, {
			Name = entry.Id,
			Label = entry.Label,
			Icon = entry.Icon,
			Role = entry.Role,
			Size = layout.Tile,
			LayoutOrder = i,
		})
	end
	local moreTile = refs.Menu.More
	if moreTile then
		Bubble.select(moreTile, true)
	end
	return { Panel = holder, Tiles = tiles, Close = close }
end

-- Puts an item icon in a hotbar slot (nil clears it); `selected` = the held slot.
function HudBubble.setSlot(slot: Frame, icon: string?, selected: boolean?)
	local face = slot:FindFirstChild("Face") :: GuiObject?
	if not face then
		return
	end
	local old = face:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	if icon then
		Bubble.icon(face, icon, math.floor(slot.Size.X.Offset * 0.84), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
	end
	local stroke = face:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.Gold else Theme.Outline
		stroke.Thickness = if selected then 5 else Theme.Stroke
	end
end

-- A toast under the teleport bar: white pill with a 3D icon.
function HudBubble.toast(toasts: Frame, text: string, icon: string?, order: number?): Frame
	local holder, face = Bubble.body(toasts, Bubble.role("Plain"), Vector2.new(360, 44), { Name = "Toast", Corner = 22 })
	holder.LayoutOrder = order or 0
	if icon then
		Bubble.icon(face, icon, 52, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -8, 0.5, -2) })
	end
	Bubble.ink(face, text, 21, {
		Name = "Text",
		Position = UDim2.fromOffset(if icon then 48 else 16, 0),
		Size = UDim2.new(1, if icon then -60 else -32, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	return holder
end

function HudBubble.build(uiScale: number): Refs
	local layout = HudBubble.layout(uiScale)
	local gui = UIKit.screen("TerraForgeHud", 5)
	gui:SetAttribute("TerraForge", true)
	local scale = gui:FindFirstChild("Scale") :: UIScale
	scale.Scale = uiScale

	local coins, plus, income = coinsPill(gui, layout)
	local tabs = teleportBar(gui, layout)
	local menu = menuTiles(gui, layout)
	local slots, carryLabel = hotbar(gui, layout)

	local toasts = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 12 + layout.TabHeight + Theme.Lip + 18),
		Size = UDim2.fromOffset(360, 160),
	}, gui)
	UIKit.list(toasts, Enum.FillDirection.Vertical, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	return {
		Gui = gui,
		Coins = coins,
		CoinsPlus = plus,
		Income = income,
		Menu = menu,
		Tabs = tabs,
		Slots = slots,
		CarryLabel = carryLabel,
		Toasts = toasts,
	}
end

return HudBubble
