--[[
	The light "Bubble" HUD (owner's pick A, 2026-10-18). Pure builder; a
	controller fills it in.

	  bottom-left   the money: a big green amount (K / M / B...) with the cash
	                icon and the income per second over it (owner 2026-10-20,
	                his phone photo); the game HUD (buildGame) only
	  bottom-left   over the money: the green "Shop" pill with the cart (opens
	                the Robux STORE); on phones and tablets at the right end
	                of the TRAIN chip's row (the top-right holds the tutorial
	                bubble and the FREE SPIN chip)
	  top-centre    the teleport bar: BASE / LOBBY / VAULT tabs with 3D icons
	  left          the main menu tiles: BACKPACK, GOLEMS, BUILD, SHOP + MORE
	                (2 columns on PC, 3 columns on phones so the tiles stay above
	                the thumbstick)
	  bottom-centre the hotbar: the blaster in slot 1 (the preview's build());
	                the game HUD (buildGame) has the backpack button right of
	                Roblox's own blaster slot instead (backpackButton)
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
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local CashBuilder = require(Shared.Builders.CashBuilder)
local Pop = require(script.Parent.Pop)

local HudBubble = {}

HudBubble.CompactScale = 0.75

export type MenuEntry = { Id: string, Label: string, Icon: string, Role: string }

-- The main tiles (owner: only the main 4-5 on the left, the rest behind MORE).
HudBubble.Menu = {
	{ Id = "Backpack", Label = "BACKPACK", Icon = "backpack", Role = "Backpack" },
	{ Id = "Golems", Label = "GOLEMS", Icon = "golem_GildedPorter", Role = "Golems" },
	{ Id = "Build", Label = "BUILD", Icon = "build", Role = "Build" },
	-- (the luck boosts: BoostController; "Shop" is the green pill, the Robux STORE)
	{ Id = "Shop", Label = "BOOSTS", Icon = "clover", Role = "Boosts" },
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
	Narrow: boolean, -- the smallest phones: icon-only teleport tabs
}

HudBubble.NarrowWidth = 600 -- points; like TeleportView.NarrowWidth

function HudBubble.layout(uiScale: number, screenWidth: number?): Layout
	if uiScale <= HudBubble.CompactScale then
		local narrow = screenWidth ~= nil and screenWidth < HudBubble.NarrowWidth
		return {
			Compact = true,
			Narrow = narrow,
			Tile = 78,
			TileGap = 12,
			Columns = 3,
			TabWidth = if narrow then 74 else 118,
			TabHeight = 72,
			Slot = 76,
			SlotGap = 10,
			Slots = 5,
		}
	end
	return {
		Compact = false,
		Narrow = false,
		Tile = 82,
		TileGap = 12,
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

--[[
	The money at the bottom-left (owner 2026-10-20, his egg-game photo: "the
	banknotes, then the amount", green, K / M / B...): a 3D cash pile (a live
	ViewportFrame, CashBuilder.pile: no upload needed), the big green amount
	in the heavy font with a thick black edge, and the income per second over
	it. Returns (panel, amount, income); the panel pops on big gains
	(HudController).
]]
local function money(gui: ScreenGui, layout: Layout): (Frame, TextLabel, TextLabel)
	local size = if layout.Compact then 42 else 48
	local pic = size + 36
	local panel = UIKit.new("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 18, 1, if layout.Compact then -22 else -16),
		Size = UDim2.fromOffset(HudBubble.CoinsWidth + 40, size + 36),
	}, gui)
	Pop.model(panel, "cash_pile", pic, CashBuilder.pile(), {
		Name = "Cash",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -10, 1, 14),
		ZIndex = 3,
	})
	local amount = Pop.text(panel, "$0", size, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 1),
		FontFace = PopTheme.Heavy,
		Position = UDim2.new(0, pic - 12, 1, 4),
		Size = UDim2.new(1, -(pic - 12), 0, size + 8),
		TextColor3 = PopTheme.MoneyNumber,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local amountEdge = amount:FindFirstChildOfClass("UIStroke") :: UIStroke
	amountEdge.Thickness = 4
	local small = math.floor(size * 0.5)
	local income = Pop.text(panel, "+$0/s", small, {
		Name = "Income",
		AnchorPoint = Vector2.new(0, 1),
		FontFace = PopTheme.Heavy,
		Position = UDim2.new(0, pic - 8, 1, -(size + 2)),
		Size = UDim2.new(1, -(pic - 8), 0, small + 6),
		TextColor3 = Color3.fromRGB(214, 255, 190),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return panel, amount, income
end

-- The green "Shop" pill with the cart (owner's phone photo): opens the Robux STORE.
HudBubble.ShopPill = Vector2.new(176, 56)
-- phones and tablets (on the chips' row): 72 units tall, 44.6 pt at the 0.62 scale
HudBubble.ShopPillPhone = Vector2.new(188, 72)

-- One BASE / LOBBY / VAULT tab (icon left on PC, on top on phones).
function HudBubble.tab(parent: Instance, spot: MenuEntry, layout: Layout, order: number): TextButton
	local holder, face = Bubble.body(parent, Bubble.role(spot.Role), Vector2.new(layout.TabWidth, layout.TabHeight), {
		Name = spot.Id,
		Corner = 16,
		Clickable = true,
	})
	holder.LayoutOrder = order
	if layout.Narrow then
		Bubble.icon(face, spot.Icon, 66, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -4) })
	elseif layout.Compact then
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
	return face :: TextButton
end

-- The look of a teleport spot (TeleportConfig id -> icon + colour role).
function HudBubble.spot(id: string, label: string): MenuEntry
	for _, spot in HudBubble.Spots do
		if spot.Id == id then
			return spot
		end
	end
	return { Id = id, Label = label, Icon = "base", Role = "Plain" }
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
		tabs[spot.Id] = HudBubble.tab(bar, spot, layout, i)
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
	local cellH = layout.Tile -- (Pop tiles: the icon inside, no lip)
	local rowGap = layout.TileGap
	local width = layout.Columns * layout.Tile + (layout.Columns - 1) * layout.TileGap
	local height = rows * cellH + (rows - 1) * rowGap
	-- phones: under the coins and the income chip (it sits under the pill so
	-- it never meets the teleport bar on narrow phones)
	-- the top-left, right under Roblox's top bar; the TRAIN chip (and the boost
	-- chips beside it) go under the tiles (ChipTop), the Shop pill and the money
	-- at the bottom-left
	local origin = UDim2.fromOffset(18, HudBubble.MenuTop)
	return { Origin = origin, Width = width, Height = height, CellHeight = cellH, RowGap = rowGap }
end

-- A menu tile's colour (owner's tile photo: every tile its own bright colour).
HudBubble.RolePaints = {
	Backpack = "Orange",
	Golems = "Purple",
	Build = "Yellow",
	Boosts = "Green",
	More = "Pink",
	Base = "Blue",
	Lobby = "Teal",
	Vault = "Purple",
	Codex = "Blue",
	Artifacts = "Yellow",
	Boards = "Orange",
	Settings = "Slate",
	Shop = "Green",
	Wheel = "Pink",
	Gear = "Red",
	Rebirth = "Purple",
	Quests = "Pink",
	Plain = "Slate",
} :: { [string]: string }

-- A left menu tile in the Pop look (Pop.tile): returns (face, holder).
function HudBubble.tile(
	parent: Instance,
	o: { Name: string, Label: string, Icon: string, Role: string, Size: number, LayoutOrder: number? }
): (TextButton, Frame)
	return Pop.tile(parent, {
		Name = o.Name,
		Label = o.Label,
		Icon = o.Icon,
		Paint = HudBubble.RolePaints[o.Role] or "Slate",
		Size = o.Size,
		LayoutOrder = o.LayoutOrder,
	})
end

HudBubble.MenuTop = 8 -- the tiles' top under Roblox's top bar (CoreUISafeInsets)
HudBubble.ChipGap = 12

-- The TRAIN chip's top: under the game menu's tiles (design units, CoreUISafeInsets).
function HudBubble.chipTop(layout: Layout): number
	local m = HudBubble.menuMetrics(layout, #HudBubble.GameMenu)
	-- (phones: the Shop pill rides on this row's right end, under the touch
	-- tutorial bubble; the flat Pop tiles are shorter, so keep the old row)
	local extra = if layout.Compact then 28 else 0
	return HudBubble.MenuTop + m.Height + HudBubble.ChipGap + extra
end

--[[
	The farthest right the boost chips' row may reach on this HUD (design
	units; `width` is the HUD gui's width in design units): on phones and
	tablets the Shop pill rides on the right end of the chips' row
	(ChipTop), so the chips stop ChipGap short of its left edge
	(BoostView.HudChipsRight, set by HudController). nil when the pill sits
	elsewhere (PC: over the money, bottom-left) or there is no width yet.
]]
function HudBubble.chipsRight(gui: Instance, width: number): number?
	local pill = gui:FindFirstChild("ShopPill")
	if not (pill and pill:IsA("GuiObject")) or type(gui:GetAttribute("ChipTop")) ~= "number" then
		return nil
	end
	if width ~= width or width <= 0 or pill.Position.Y.Scale ~= 0 then
		return nil
	end
	local left = width * pill.Position.X.Scale + pill.Position.X.Offset - pill.AnchorPoint.X * pill.Size.X.Offset
	return left - HudBubble.ChipGap
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
		local face = HudBubble.tile(menu, {
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
	{ Id = "Wheel", Label = "WHEEL", Icon = "wheel", Role = "Wheel" },
	{ Id = "Codex", Label = "CODEX", Icon = "book", Role = "Codex" },
	{ Id = "Artifacts", Label = "ARTIFACTS", Icon = "artifact", Role = "Artifacts" },
	{ Id = "Boards", Label = "BOARDS", Icon = "trophy", Role = "Boards" },
	{ Id = "Gear", Label = "GEAR", Icon = "helmet", Role = "Gear" },
	{ Id = "Settings", Label = "SETTINGS", Icon = "cog", Role = "Settings" },
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
	local top = if layout.Compact then UDim.new(0, 96) else UDim.new(more.Y.Scale, more.Y.Offset + m.CellHeight - height)
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
	local close, closeHolder =
		Bubble.button(face, { Name = "Close", Text = "X", Role = "Danger", Size = Vector2.new(44, 44), TextSize = 26, Corner = 14 })
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
		tiles[entry.Id] = HudBubble.tile(grid, {
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

---------------------------------------------------------------- the game HUD (UIConfig.LightUI)
--[[
	buildGame / slot / floater / toast / buildOffline have the same shape as
	HudView's, so HudController, TeleportView, BuildView and the other
	controllers use the light HUD unchanged (HudView forwards to these while
	UIConfig.lightUI() is on). Differences:
	  TopBar  is empty with the attribute Bubble: TeleportView.build fills it
	          with bubble tabs
	  Menu    is the left tile grid with the attribute Bubble; every tile
	          starts hidden and shows when a controller claims it
	          (claimTile: BuildView claims BUILD, TeleportView claims LIFT),
	          so there are never dead buttons
	  Carry   the backpack button right of the blaster's hotbar slot (owner
	          2026-10-24: everything goes into the backpack): the pack's
	          picture and "n / cap" (backpackButton / setBackpack)
]]

-- The tiles the game menu can show (claimed by controllers).
HudBubble.GameMenu = {
	HudBubble.Menu[1],
	HudBubble.Menu[2],
	HudBubble.Menu[3],
	HudBubble.Menu[4],
	{ Id = "Elevator", Label = "ELEVATOR", Icon = "lift", Role = "Base" }, -- the side menu's Elevator entry claims it
	HudBubble.Menu[5],
} :: { MenuEntry }

HudBubble.CoinsWidth = 250

-- HudController's UI scale for a screen size (the same formula).
function HudBubble.scaleFor(viewport: Vector2): number
	return math.clamp(math.min(viewport.Y / Theme.BaseHeight, viewport.X / 1100), 0.62, 1.25)
end

-- The scale for this screen right now (1 when there is no camera yet).
function HudBubble.screenScale(): number
	local ok, size = pcall(function()
		local camera = game:GetService("Workspace").CurrentCamera
		return if camera then camera.ViewportSize else nil
	end)
	if ok and typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
		return HudBubble.scaleFor(size)
	end
	return 1
end

export type GameRefs = {
	Gui: ScreenGui,
	Coins: TextLabel,
	CoinsPanel: Frame,
	Income: TextLabel,
	Floaters: Frame,
	Zone: TextLabel,
	Toasts: Frame,
	CarryPanel: Frame, -- the backpack button's holder (build mode hides it)
	Backpack: TextButton, -- the backpack button: opens the inventory (BackpackController)
	CarryLabel: TextLabel, -- the button's "n / cap"
	Menu: Frame,
	TopBar: Frame,
}

-- The screen's width in points right now (nil without a camera).
function HudBubble.screenWidth(): number?
	local ok, width = pcall(function()
		local camera = game:GetService("Workspace").CurrentCamera
		return if camera then camera.ViewportSize.X else nil
	end)
	return if ok and type(width) == "number" and width > 0 then width else nil
end

-- The teleport bar (owner 2026-10-20: BASE / MINE / SPAWN in his photo, text
-- only, at the very top): button sizes per layout, design units.
HudBubble.TopBarPad = 5
HudBubble.TopBarGap = 8
HudBubble.PreviewInset = 36 -- the preview renderer's top bar inset (px)

function HudBubble.topBarButton(layout: Layout): Vector2
	if layout.Narrow then
		return Vector2.new(88, 72) -- (the smallest phones: as wide as the old icon tabs)
	elseif layout.Compact then
		return Vector2.new(128, 72)
	end
	return Vector2.new(150, 46)
end

function HudBubble.topBarSize(layout: Layout): Vector2
	local b = HudBubble.topBarButton(layout)
	local count = #HudBubble.Spots
	return Vector2.new(count * b.X + (count - 1) * HudBubble.TopBarGap + 2 * HudBubble.TopBarPad, b.Y + 2 * HudBubble.TopBarPad)
end

HudBubble.TopBarUnderRow = 6 -- the bar's Y under Roblox's row when the row has no room

--[[
	The bar's X offset (design units from the centre) and whether it fits in
	Roblox's top row: `free` is the row's free span in screen pixels
	(GuiService.TopbarInset min / max x; nil = unknown: centred in the row),
	the HUD gui spans guiLeft..guiLeft + guiWidth px, the bar is `width` design
	units at `scale`. Pure (specs).
]]
function HudBubble.topBarX(free: Vector2?, guiLeft: number, guiWidth: number, width: number, scale: number): (number, boolean)
	if not free then
		return 0, true
	end
	local w = width * scale
	local margin = 6
	local lo, hi = free.X + w / 2 + margin, free.Y - w / 2 - margin
	if lo > hi then
		return 0, false -- the row is too full: under it, centred
	end
	local centre = guiLeft + guiWidth / 2
	local placed = math.clamp(centre, lo, hi)
	return math.floor((placed - centre) / scale), true
end

-- The bar's Y in the HUD gui (CoreUISafeInsets starts under Roblox's top bar):
-- lifted by the top inset (px) at `scale` so it sits 4 px from the screen top.
function HudBubble.topBarY(insetTop: number, scale: number): number
	return -math.floor(insetTop / math.max(scale, 0.01)) + 6
end

function HudBubble.buildGame(uiScale: number?, screenWidth: number?): GameRefs
	local layout = HudBubble.layout(uiScale or HudBubble.screenScale(), screenWidth or HudBubble.screenWidth())
	local gui = UIKit.screen("TerraForgeHud", 5)
	gui:SetAttribute("Bubble", true)
	-- TVs and notched phones: keep clear of the unsafe edges and of Roblox's top
	-- bar (CoreUISafeInsets: the same frame as the TRAIN and boost chips' guis)
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)

	-- the money, bottom-left (the income line lives inside, so hiding the money hides both)
	local coinsPanel, coins, income = money(gui, layout)
	local floaters = UIKit.new("Frame", {
		Name = "Floaters",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 20 + 60, 1, -(coinsPanel.Size.Y.Offset + 30)),
		Size = UDim2.fromOffset(HudBubble.CoinsWidth, 60),
	}, gui)

	-- the teleport bar at the very top, in Roblox's top bar row (owner: "put it
	-- right at the top"; TeleportView fills it, HudController.placeTopBar lifts
	-- it by the real top inset); zone name and toasts under the safe area's top
	local barSize = HudBubble.topBarSize(layout)
	local topBar = UIKit.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, HudBubble.topBarY(HudBubble.PreviewInset, 1)),
		Size = UDim2.fromOffset(barSize.X, barSize.Y),
	}, gui)
	UIKit.corner(topBar, 12)
	Pop.border(topBar, 3)
	UIKit.padding(topBar, HudBubble.TopBarPad)
	topBar:SetAttribute("Pop", true)
	topBar:SetAttribute("Bubble", true)
	topBar:SetAttribute("Compact", layout.Compact)
	topBar:SetAttribute("Narrow", layout.Narrow)
	UIKit.list(topBar, Enum.FillDirection.Horizontal, HudBubble.TopBarGap, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local below = 28
	local zone = Bubble.text(gui, "Emberfall", 30, {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Theme.TitleFont,
		Position = UDim2.new(0.5, 0, 0, below),
		Size = UDim2.fromOffset(460, 36),
		TextTransparency = 1,
	})
	local zoneStroke = zone:FindFirstChildOfClass("UIStroke")
	if zoneStroke then
		zoneStroke.Transparency = 1
	end
	local toasts = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, below + 42),
		Size = UDim2.fromOffset(460, 220),
	}, gui)
	UIKit.list(toasts, Enum.FillDirection.Vertical, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- the left menu: every tile hidden until a controller claims it
	local m = HudBubble.menuMetrics(layout, #HudBubble.GameMenu)
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Position = m.Origin,
		Size = UDim2.fromOffset(m.Width, m.Height),
	}, gui)
	-- where the TRAIN chip goes (TrainView.HudChipTop, set by HudController)
	gui:SetAttribute("ChipTop", HudBubble.chipTop(layout))
	-- the green Shop pill: on big screens over the money (the owner's phone photo: Shop
	-- above the money, bottom-left); on phones and tablets the left column is full
	-- (tiles, the TRAIN chip, the money) and the top-right holds the tutorial bubble
	-- and the FREE SPIN chip, so it sits at the right end of the TRAIN chip's row
	local pill = if layout.Compact then HudBubble.ShopPillPhone else HudBubble.ShopPill
	local moneyTop = -coinsPanel.Position.Y.Offset + coinsPanel.Size.Y.Offset
	local shop = Pop.pill(gui, "Shop", "cart", "Green", pill, {
		Name = "ShopPill",
		AnchorPoint = if layout.Compact then Vector2.new(1, 0) else Vector2.new(0, 1),
		Position = if layout.Compact then UDim2.new(1, -18, 0, HudBubble.chipTop(layout)) else UDim2.new(0, 20, 1, -(moneyTop + 12)),
	})
	shop:SetAttribute("Opens", "StoreController")
	gui:SetAttribute("ShortLuck", layout.Compact) -- (phones: the Server Luck line without "thanks name")
	-- Server Luck running (StoreController fills it from ServerLuckUntil): next to the pill
	Pop.text(gui, "", 22, {
		Name = "ServerLuck",
		AnchorPoint = if layout.Compact then Vector2.new(1, 0) else Vector2.new(0, 1),
		Position = if layout.Compact
			then UDim2.new(1, -18, 0, HudBubble.chipTop(layout) + pill.Y + 8)
			else UDim2.new(0, 22, 1, -(moneyTop + 12 + pill.Y + 8)),
		-- (phones: no wider than the pill's corner, clear of the tabs; the text shrinks to fit)
		Size = if layout.Compact then UDim2.fromOffset(HudBubble.ShopPill.X + 90, 26) else UDim2.fromOffset(420, 28),
		TextScaled = layout.Compact,
		TextColor3 = Color3.fromRGB(140, 255, 120),
		TextXAlignment = if layout.Compact then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		TextWrapped = false,
		Visible = false,
	})
	menu:SetAttribute("Bubble", true)
	menu:SetAttribute("Columns", layout.Columns)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight),
		CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, menu)
	for i, entry in HudBubble.GameMenu do
		local _, holder = HudBubble.tile(menu, {
			Name = entry.Id,
			Label = entry.Label,
			Icon = entry.Icon,
			Role = entry.Role,
			Size = layout.Tile,
			LayoutOrder = i,
		})
		holder.Visible = false
	end

	-- the backpack button right of the blaster's hotbar slot (HudController fills it,
	-- BackpackController opens the inventory)
	local carryPanel, backpack, carryLabel = HudBubble.backpackButton(gui, layout, uiScale or HudBubble.screenScale())

	return {
		Gui = gui,
		Coins = coins,
		CoinsPanel = coinsPanel,
		Income = income,
		Floaters = floaters,
		Zone = zone,
		Toasts = toasts,
		CarryPanel = carryPanel,
		Backpack = backpack,
		CarryLabel = carryLabel,
		Menu = menu,
		TopBar = topBar,
	}
end

-- The side menu's IconNames (SideMenuView.Entries) -> 3D icon + colour role.
HudBubble.EntryLooks = {
	Golems = { Icon = "golem_GildedPorter", Role = "Golems" },
	Shop = { Icon = "clover", Role = "Boosts" }, -- the luck boosts (the Robux STORE is the green Shop pill)
	Codex = { Icon = "book", Role = "Codex" },
	Artifacts = { Icon = "artifact", Role = "Artifacts" },
	Boards = { Icon = "trophy", Role = "Boards" },
	Settings = { Icon = "cog", Role = "Settings" },
	Store = { Icon = "coins", Role = "Shop" },
	Elevator = { Icon = "lift", Role = "Base" },
	Hoverboards = { Icon = "hoverboard", Role = "Lobby" }, -- (no sheet cell yet: empty until uploaded, the label shows)
	Wheel = { Icon = "wheel", Role = "Wheel" },
	Gear = { Icon = "helmet", Role = "Gear" },
	Rebirth = { Icon = "rebirth", Role = "Rebirth" }, -- STAR FORGE
	Quests = { Icon = "medal", Role = "Quests" }, -- daily / weekly quests + the login streak
	Emotes = { Icon = "emotes", Role = "Lobby" }, -- the EMOTES menu (EmoteController; no sheet cell: the word shows)
} :: { [string]: { Icon: string, Role: string } }

export type TileSpec = { Label: string?, IconName: string?, Order: number? }

local function tileSize(menu: Instance): number
	local grid = menu:FindFirstChildOfClass("UIGridLayout")
	return if grid then grid.CellSize.X.Offset else 86
end

-- Shows a menu tile for a controller and returns its button (its Parent is
-- the tile holder, like UIKit.button's). Unknown ids get a new tile from
-- `spec` (label, IconName -> EntryLooks, order after the known tiles).
function HudBubble.claimTile(menu: Instance, id: string, spec: TileSpec?): TextButton
	local holder = menu:FindFirstChild(id)
	if not holder then
		local look = if spec and spec.IconName then HudBubble.EntryLooks[spec.IconName] else nil
		local _, created = HudBubble.tile(menu, {
			Name = id,
			Label = if spec and spec.Label then spec.Label else string.upper(id),
			Icon = if look then look.Icon else "more",
			Role = if look then look.Role else "Plain",
			Size = tileSize(menu),
			LayoutOrder = 10 + (if spec and spec.Order then spec.Order else 40),
		})
		holder = created
	end
	local frame = holder :: Frame
	frame.Visible = true
	HudBubble.linkMenu(menu)
	return frame:FindFirstChild("Face") :: TextButton
end

--[[
	Gamepad D-pad order of the menu tiles: the visible tiles in grid order
	(LayoutOrder), left / right along a row, up / down a column. Run again
	whenever a tile shows or hides. Returns the faces in order (tests).
]]
function HudBubble.linkMenu(menu: Instance): { GuiObject }
	local columns = (menu:GetAttribute("Columns") :: number?) or 2
	local holders: { Frame } = {}
	for _, child in menu:GetChildren() do
		if child:IsA("Frame") and child.Visible and child:FindFirstChild("Face") then
			table.insert(holders, child)
		end
	end
	table.sort(holders, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local faces: { GuiObject } = {}
	for _, holder in holders do
		table.insert(faces, holder:FindFirstChild("Face") :: GuiObject)
	end
	for i, face in faces do
		local col = (i - 1) % columns
		local links: any = face -- NextSelection* take a GuiObject or nil
		local function link(name: string, target: GuiObject?)
			pcall(function() -- (Lune's instances can't hold a nil Ref)
				links[name] = target
			end)
		end
		link("NextSelectionLeft", if col > 0 then faces[i - 1] else nil)
		link("NextSelectionRight", if col < columns - 1 then faces[i + 1] else nil)
		link("NextSelectionUp", faces[i - columns])
		link("NextSelectionDown", faces[i + columns])
	end
	return faces
end

-- Hides / shows a claimed tile (a controller that went away, a hidden entry).
function HudBubble.setTileVisible(menu: Instance, id: string, visible: boolean)
	local holder = menu:FindFirstChild(id)
	if holder and holder:IsA("Frame") and holder.Visible ~= visible then
		holder.Visible = visible
		HudBubble.linkMenu(menu)
	end
end

-- A count badge on a tile's face (0 hides it).
function HudBubble.setTileBadge(face: GuiObject, count: number)
	local badge = face:FindFirstChild("Badge")
	if count <= 0 then
		if badge then
			badge:Destroy()
		end
		return
	end
	local text = if count > 99 then "99+" else tostring(count)
	if badge then
		local label = badge:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = text
		end
	else
		Bubble.badge(face, text)
	end
end

--[[
	The MORE flyout of the game HUD: a white bubble right of the left menu
	with a tile per "More" entry (addMore). The MORE tile opens and shuts it
	(toggleMore); it starts shut. Returns the entry's button.
]]
function HudBubble.addMore(menu: Instance, id: string, spec: TileSpec): TextButton
	local gui = menu.Parent :: Instance
	local flyout = gui:FindFirstChild("MoreFlyout") :: Frame?
	if not flyout then
		local columns = 3
		local size = tileSize(menu)
		local created = UIKit.new("Frame", {
			Name = "MoreFlyout",
			BackgroundColor3 = PopTheme.Well,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.new(
				(menu :: any).Position.X.Scale,
				(menu :: any).Position.X.Offset + (menu :: any).Size.X.Offset + 20,
				(menu :: any).Position.Y.Scale,
				(menu :: any).Position.Y.Offset
			),
			Size = UDim2.fromOffset(columns * size + (columns - 1) * 12 + 32, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			ZIndex = 5,
		}, gui)
		created:SetAttribute("Columns", columns)
		UIKit.corner(created, 12)
		Pop.border(created, 3)
		local pad = UIKit.padding(created, 16)
		pad.PaddingTop = UDim.new(0, 16)
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, created)
		flyout = created
		local more = HudBubble.claimTile(menu, "More")
		more.Activated:Connect(function()
			HudBubble.toggleMore(menu)
		end)
	end
	local look = if spec.IconName then HudBubble.EntryLooks[spec.IconName] else nil
	local face = HudBubble.tile(flyout :: Frame, {
		Name = id,
		Label = spec.Label or string.upper(id),
		Icon = if look then look.Icon else "more",
		Role = if look then look.Role else "Plain",
		Size = tileSize(menu),
		LayoutOrder = spec.Order or 50,
	})
	HudBubble.linkMenu(flyout :: Frame)
	return face
end

-- Called with the MORE flyout's new state (SideMenuController sets it).
HudBubble.onMoreToggled = nil :: ((boolean) -> ())?

-- Opens / shuts the MORE flyout (nil = the other way round). Returns whether it is open.
function HudBubble.toggleMore(menu: Instance, open: boolean?): boolean
	local gui = menu.Parent :: Instance
	local flyout = gui:FindFirstChild("MoreFlyout") :: Frame?
	if not flyout then
		return false
	end
	local on = if open == nil then not flyout.Visible else open
	flyout.Visible = on
	local hook = HudBubble.onMoreToggled
	if hook then
		hook(on) -- (SideMenuController: MenuPanels.setGridOpen, the chips hide while it is open)
	end
	local more = menu:FindFirstChild("More")
	local face = more and more:FindFirstChild("Face") :: GuiObject?
	if face then
		Bubble.select(face, on)
	end
	return on
end

-- The light look's gamepad selection: a thick gold rounded outline
-- (PlayerGui.SelectionImageObject, set by HudController).
function HudBubble.selectionImage(): Frame
	local frame = UIKit.new("Frame", {
		Name = "BubbleSelection",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
	})
	Bubble.corner(frame, Theme.Corner + 4)
	UIKit.new("UIStroke", {
		Thickness = 5,
		Color = Theme.Gold,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, frame)
	return frame
end

--[[
	The backpack button (owner 2026-10-24: "everything into the backpack", a
	backpack icon next to the Blaster slot opens the ore inventory;
	docs/plans/OWNER_PLAYTEST_1024.md "4 + 5"). It took the place of the
	hotbar's carried-ore squares: right of the blaster's slot in Roblox's own
	hotbar (bottom centre, drawn in real pixels: backpackX keeps the gap at
	every UI scale), in the hotbar wells' pixel look (a dark rounded well, a
	black outline, a light rim lit from below, a faint lattice) holding the
	pack's picture (IconAssets "backpack"; drawn from frames until the sheet
	is uploaded) and "n / cap" in pixel letters. A full backpack paints the
	count red and shows a red FULL tag on the top edge (setBackpack). The
	key hint on the top-right corner names the open key (setBackpackKey: Q,
	the gamepad's R1 glyph, nothing on touch). Clicking, tapping or a
	gamepad's A on it opens the inventory (BackpackController). The dark HUD
	(HudView) uses the same button.
]]
HudBubble.SlotTop = Color3.fromRGB(20, 21, 27) -- the well's shadowed top inside
HudBubble.SlotBottom = Color3.fromRGB(54, 58, 72)
HudBubble.SlotRim = Color3.fromRGB(150, 160, 188)
HudBubble.BackpackSize = Vector2.new(176, 64) -- design units (PC)
HudBubble.BackpackSizePhone = Vector2.new(196, 76) -- 47 pt tall at the phones' 0.62 scale
HudBubble.BackpackBottom = 12 -- design units above the safe area's bottom edge
HudBubble.BlasterSlot = 60 -- Roblox's hotbar slot in px (100 on a TV: GuiService:IsTenFootInterface)
HudBubble.BlasterGap = 16 -- px between the slot's middle half and the button (its 5 px border included)
HudBubble.FullColor = Color3.fromRGB(255, 92, 84)
-- the drawn pack (no uploaded picture yet): the Rookie Pack's colours (BackpackData)
local PACK = {
	Body = Color3.fromRGB(240, 140, 58),
	Flap = Color3.fromRGB(214, 120, 48),
	Strap = Color3.fromRGB(122, 76, 44),
	Buckle = Color3.fromRGB(250, 206, 90),
}

-- The button's X offset from the screen's middle (design units) at `uiScale`:
-- right of the blaster's slot, which Roblox draws in real pixels. Pure (specs).
function HudBubble.backpackX(uiScale: number, tenFoot: boolean?): number
	local slot = if tenFoot then 100 else HudBubble.BlasterSlot
	return math.ceil((slot / 2 + HudBubble.BlasterGap) / math.max(uiScale, 0.01))
end

-- "12 / 30": what the button says. Pure (specs).
function HudBubble.backpackText(count: number, capacity: number): string
	local n = if type(count) == "number" and count == count and count > 0 then math.floor(count) else 0
	local cap = if type(capacity) == "number" and capacity == capacity and capacity > 0 then math.floor(capacity) else 0
	return `{n} / {cap}`
end

-- A rounded piece of the drawn pack (scale units of `parent`).
local function packBit(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, color: Color3, round: number): Frame
	local bit = UIKit.new("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		ZIndex = 5,
	}, parent)
	UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, bit)
	return bit
end

--[[
	The pack's picture `size` units square ("Pack"): the uploaded "backpack"
	icon, or until the sheet is uploaded a drawn pack (straps, body, flap,
	pocket, buckle; black outlines). Returns the frame.
]]
function HudBubble.packArt(parent: Instance, size: number, props: { [string]: any }?): Frame
	local art = UIKit.new("Frame", {
		Name = "Pack",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, parent)
	local icon = UIKit.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, art)
	IconAssets.apply(icon, "backpack")
	icon:SetAttribute("Icon", "backpack")
	-- (only an uploaded sheet: the previews draw the pack like the game does until then)
	local shows = IconAssets.find("backpack") ~= ""
	icon.Visible = shows
	if not shows then
		local drawn = UIKit.new("Frame", {
			Name = "Drawn",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		}, art)
		packBit(drawn, "StrapL", 0.24, 0.12, 0.34, 0.42, PACK.Strap, 0.4)
		packBit(drawn, "StrapR", 0.66, 0.12, 0.76, 0.42, PACK.Strap, 0.4)
		local handle = packBit(drawn, "Handle", 0.38, 0.06, 0.62, 0.18, PACK.Strap, 0.5)
		Pop.border(handle, 2)
		local body = packBit(drawn, "Body", 0.18, 0.16, 0.82, 0.9, PACK.Body, 0.24)
		Pop.border(body, 2.5)
		local flap = packBit(drawn, "Flap", 0.18, 0.16, 0.82, 0.44, PACK.Flap, 0.3)
		Pop.border(flap, 2)
		local pocket = packBit(drawn, "Pocket", 0.3, 0.56, 0.7, 0.82, PACK.Flap, 0.2)
		Pop.border(pocket, 2)
		local buckle = packBit(drawn, "Buckle", 0.44, 0.36, 0.56, 0.5, PACK.Buckle, 0.2)
		Pop.border(buckle, 1.5)
		local shine = packBit(drawn, "Shine", 0.24, 0.5, 0.28, 0.8, Color3.new(1, 1, 1), 0.5)
		shine.BackgroundTransparency = 0.55
	end
	if props then
		local target: any = art
		for key, value in props do
			target[key] = value
		end
	end
	return art
end

--[[
	The backpack button in `gui` (see above): returns (holder "Carry", the
	button "Backpack", its count label "Count"). `layout` picks the PC or
	the phone size; `uiScale` places it right of the blaster's slot.
]]
function HudBubble.backpackButton(gui: Instance, layout: Layout, uiScale: number): (Frame, TextButton, TextLabel)
	local size = if layout.Compact then HudBubble.BackpackSizePhone else HudBubble.BackpackSize
	local holder = UIKit.new("Frame", {
		Name = "Carry",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, HudBubble.backpackX(uiScale), 1, -HudBubble.BackpackBottom),
		Size = UDim2.fromOffset(size.X, size.Y),
	}, gui)
	local button = UIKit.new("TextButton", {
		Name = "Backpack",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Selectable = true,
		ZIndex = 2,
	}, holder)
	UIKit.corner(button, 14)
	Pop.border(button)
	UIKit.new("UIGradient", {
		Name = "Paint",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HudBubble.SlotTop),
			ColorSequenceKeypoint.new(0.3, HudBubble.SlotTop:Lerp(HudBubble.SlotBottom, 0.55)),
			ColorSequenceKeypoint.new(1, HudBubble.SlotBottom),
		}),
	}, button)
	-- the light rim inside the outline, lit from below (an inset, like the old hotbar wells)
	local rim = UIKit.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 3,
	}, button)
	UIKit.corner(rim, 11)
	local light = UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = HudBubble.SlotRim,
		Thickness = 2,
	}, rim)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, light)
	Pop.studs(button, 14, 0.6, nil, 3)
	Pop.fxTag(button, "Press")
	local pic = size.Y - 8
	HudBubble.packArt(button, pic, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
	})
	local count = Pop.text(button, HudBubble.backpackText(0, 5), math.floor(size.Y * 0.44), {
		Name = "Count",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, pic + 6, 0.5, 0),
		Size = UDim2.new(1, -(pic + 12), 0, math.floor(size.Y * 0.56)),
		ZIndex = 6,
	})
	-- a full backpack: the red FULL tag on the top edge, over the count
	Pop.tag(button, "FULL", "Red", Vector2.new(if layout.Compact then 84 else 72, if layout.Compact then 30 else 26), {
		Name = "Full",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, pic + 6 + math.floor((size.X - pic - 12) / 2), 0, 0),
		Visible = false,
		ZIndex = 8,
	})
	-- the open key on the top-right corner: a key cap (keyboards, like the TRAIN chip's T) or the gamepad's glyph
	local keySize = if layout.Compact then 30 else 28
	local key = Pop.text(button, "", 20, {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0,
		Position = UDim2.new(1, -8, 0, 2),
		Size = UDim2.fromOffset(keySize, keySize),
		Visible = false,
		ZIndex = 8,
	})
	UIKit.corner(key, 6)
	Pop.border(key, 2.5)
	UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -8, 0, 2),
		Size = UDim2.fromOffset(keySize, keySize),
		Visible = false,
		ZIndex = 8,
	}, button)
	return holder, button, count
end

-- Shows "count / capacity" on the button; a full backpack gets the red count and the FULL tag.
function HudBubble.setBackpack(button: GuiObject, count: number, capacity: number)
	local full = capacity > 0 and count >= capacity
	local label = button:FindFirstChild("Count") :: TextLabel?
	if label then
		local text = HudBubble.backpackText(count, capacity)
		if label.Text ~= text then
			label.Text = text
		end
		label.TextColor3 = if full then HudBubble.FullColor else PopTheme.Ink
	end
	local tag = button:FindFirstChild("Full") :: GuiObject?
	if tag then
		tag.Visible = full
	end
	button:SetAttribute("Full", full)
end

-- The open key on the button: `text` (a keyboard key), `glyph` (a gamepad image), or neither (touch).
function HudBubble.setBackpackKey(button: GuiObject, text: string?, glyph: string?)
	local key = button:FindFirstChild("Key") :: TextLabel?
	local image = button:FindFirstChild("Glyph") :: ImageLabel?
	local showGlyph = glyph ~= nil and glyph ~= ""
	if image then
		image.Image = if showGlyph then glyph :: string else ""
		image.Visible = showGlyph
	end
	if key then
		key.Text = if showGlyph then "" else (text or "")
		key.Visible = not showGlyph and text ~= nil and text ~= ""
	end
end

-- Moves the button's holder right of the blaster's slot for a new UI scale.
function HudBubble.placeBackpack(holder: GuiObject, uiScale: number, tenFoot: boolean?)
	holder.Position = UDim2.new(0.5, HudBubble.backpackX(uiScale, tenFoot), 1, -HudBubble.BackpackBottom)
end

-- A floating "+$1.2K" under the coins (HudController moves and fades it).
function HudBubble.floater(parent: Instance, text: string): TextLabel
	return Bubble.text(parent, text, 30, {
		Name = "Floater",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.fromOffset(HudBubble.CoinsWidth - 44, 36),
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- A toast: a white pill with a dot in the message's colour.
function HudBubble.toastColor(parent: Instance, text: string, color: Color3): Frame
	local holder, face = Bubble.body(parent, Bubble.role("Plain"), Vector2.new(440, 44), { Name = "Toast", Corner = 22 })
	local dot = UIKit.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = 4,
	}, face)
	Bubble.corner(dot, 11)
	Bubble.stroke(dot, 2.5)
	Bubble.ink(face, text, 21, {
		Name = "Text",
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -56, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	return holder
end

export type OfflineRefs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Amount: TextLabel,
	Detail: TextLabel,
	Collect: TextButton,
}

-- "WELCOME BACK!": what the podiums earned while away, and COLLECT.
function HudBubble.buildOffline(): OfflineRefs
	local gui = UIKit.screen("TerraForgeOffline", 30)
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Theme.Shadow,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	local window = Bubble.window(gui, {
		Name = "Offline",
		Title = "WELCOME BACK!",
		Icon = "coins",
		Role = "Shop",
		Size = Vector2.new(560, 340),
	})
	local close = window.Close.Parent :: Frame
	close.Visible = false -- COLLECT (and B / Backspace) close it
	local body = window.Body
	Bubble.ink(body, "While you were away you earned", 22, {
		Name = "Lead",
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = Theme.InkSoft,
	})
	local row = Bubble.iconText(body, "coin", "+$0", 46, {
		Name = "AmountRow",
		Position = UDim2.fromOffset(0, 34),
	}, true)
	local amount = row:FindFirstChild("Text") :: TextLabel
	amount.FontFace = Theme.TitleFont
	amount.Size = UDim2.fromOffset(300, 52)
	local detail = Bubble.ink(body, "", 18, {
		Name = "Detail",
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 52),
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
	})
	local collect, collectHolder =
		Bubble.button(body, { Name = "Collect", Text = "COLLECT", Role = "Go", Size = Vector2.new(240, 62), TextSize = 30 })
	collectHolder.AnchorPoint = Vector2.new(0.5, 1)
	collectHolder.Position = UDim2.fromScale(0.5, 1)
	return { Gui = gui, Dim = dim, Panel = window.Holder, Amount = amount, Detail = detail, Collect = collect }
end

return HudBubble
