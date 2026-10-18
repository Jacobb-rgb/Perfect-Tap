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
			TileGap = 16,
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
	local cellH = layout.Tile + Theme.Lip
	local rowGap = layout.TileGap + 8 -- room for the icons popping out of the row below
	local width = layout.Columns * layout.Tile + (layout.Columns - 1) * layout.TileGap
	local height = rows * cellH + (rows - 1) * rowGap
	-- phones: under the coins and the income chip (it sits under the pill so
	-- it never meets the teleport bar on narrow phones)
	local origin = if layout.Compact then UDim2.fromOffset(18, 136) else UDim2.new(0, 18, 0.5, 24 - height // 2)
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
	  Carry   the hotbar row; the slots show the carried ore's rarity colour
]]

-- The tiles the game menu can show (claimed by controllers).
HudBubble.GameMenu = {
	HudBubble.Menu[1],
	HudBubble.Menu[2],
	HudBubble.Menu[3],
	HudBubble.Menu[4],
	{ Id = "Elevator", Label = "LIFT", Icon = "lift", Role = "Base" },
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
	CarryPanel: Frame,
	CarrySlots: Frame,
	CarryLabel: TextLabel,
	ThrowBar: Frame,
	ThrowFill: Frame,
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

function HudBubble.buildGame(uiScale: number?, screenWidth: number?): GameRefs
	local layout = HudBubble.layout(uiScale or HudBubble.screenScale(), screenWidth or HudBubble.screenWidth())
	local gui = UIKit.screen("TerraForgeHud", 5)
	gui:SetAttribute("Bubble", true)
	-- TVs and notched phones: keep clear of the unsafe edges
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)

	-- coins (the income chip lives inside, so hiding the coins hides both)
	local coins, plus, income = coinsPill(gui, layout)
	local coinsFace = coins.Parent :: Frame
	local coinsPanel = coinsFace.Parent :: Frame
	local plusHolder = plus.Parent :: Frame
	plusHolder.Visible = false -- no coin shop yet: no dead button
	coins.Size = UDim2.new(1, -52, 1, 0)
	local chipHolder = (income.Parent :: Frame).Parent :: Frame
	chipHolder.Parent = coinsPanel
	chipHolder.Position = UDim2.new(0, 42, 1, 6) -- under the pill (beside it would meet the tabs on small phones)
	chipHolder.ZIndex = 2
	local floaters = UIKit.new("Frame", {
		Name = "Floaters",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(if layout.Compact then 190 else 34, if layout.Compact then 92 else 130),
		Size = UDim2.fromOffset(HudBubble.CoinsWidth, 60),
	}, gui)

	-- top bar (TeleportView fills it), zone name and toasts under it
	local topBar = UIKit.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(3 * layout.TabWidth + 3 * 14 + 40, layout.TabHeight + Theme.Lip),
	}, gui)
	topBar:SetAttribute("Bubble", true)
	topBar:SetAttribute("Compact", layout.Compact)
	topBar:SetAttribute("Narrow", layout.Narrow)
	UIKit.list(topBar, Enum.FillDirection.Horizontal, 14, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local below = 12 + layout.TabHeight + Theme.Lip + 10
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
		Position = if layout.Compact then m.Origin else UDim2.new(0, 18, 0.5, 24 - m.Height // 2),
		Size = UDim2.fromOffset(m.Width, m.Height),
	}, gui)
	menu:SetAttribute("Bubble", true)
	menu:SetAttribute("Columns", layout.Columns)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight),
		CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, menu)
	for i, entry in HudBubble.GameMenu do
		local _, holder = Bubble.tile(menu, {
			Name = entry.Id,
			Label = entry.Label,
			Icon = entry.Icon,
			Role = entry.Role,
			Size = layout.Tile,
			LayoutOrder = i,
		})
		holder.Visible = false
	end

	-- the hotbar: carried items (HudController fills the slots)
	local carryPanel = UIKit.new("Frame", {
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(260, layout.Slot + Theme.Lip),
	}, gui)
	local carryLabel = Bubble.text(carryPanel, "CARRYING 0/1", 18, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(260, 22),
	})
	local slots = UIKit.new("Frame", {
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, layout.Slot + Theme.Lip),
	}, carryPanel)
	slots:SetAttribute("SlotSize", layout.Slot)
	UIKit.list(slots, Enum.FillDirection.Horizontal, layout.SlotGap, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- throw power bar
	local throwBar = UIKit.new("Frame", {
		Name = "ThrowBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(220, 22),
		Visible = false,
	}, gui)
	Bubble.corner(throwBar, 11)
	Bubble.stroke(throwBar, 3.5)
	local throwFill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, throwBar)
	Bubble.corner(throwFill, 11)

	return {
		Gui = gui,
		Coins = coins,
		CoinsPanel = coinsPanel,
		Income = income,
		Floaters = floaters,
		Zone = zone,
		Toasts = toasts,
		CarryPanel = carryPanel,
		CarrySlots = slots,
		CarryLabel = carryLabel,
		ThrowBar = throwBar,
		ThrowFill = throwFill,
		Menu = menu,
		TopBar = topBar,
	}
end

-- The side menu's IconNames (SideMenuView.Icons keys) -> 3D icon + colour role.
HudBubble.EntryLooks = {
	Golems = { Icon = "golem_GildedPorter", Role = "Golems" },
	Shop = { Icon = "shop", Role = "Shop" },
	Codex = { Icon = "book", Role = "Codex" },
	Artifacts = { Icon = "artifact", Role = "Artifacts" },
	Boards = { Icon = "trophy", Role = "Boards" },
	Settings = { Icon = "cog", Role = "Settings" },
	Store = { Icon = "coins", Role = "Shop" },
	Elevator = { Icon = "lift", Role = "Base" },
	Hoverboards = { Icon = "rainbow", Role = "Lobby" },
	Wheel = { Icon = "wheel", Role = "Wheel" },
	Gear = { Icon = "helmet", Role = "Gear" },
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
		local _, created = Bubble.tile(menu, {
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
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(
				(menu :: any).Position.X.Scale,
				(menu :: any).Position.X.Offset + (menu :: any).Size.X.Offset + 20,
				(menu :: any).Position.Y.Scale,
				(menu :: any).Position.Y.Offset
			),
			Size = UDim2.fromOffset(columns * size + (columns - 1) * 16 + 32, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			ZIndex = 5,
		}, gui)
		created:SetAttribute("Columns", columns)
		Bubble.corner(created, 24)
		Bubble.stroke(created)
		local pad = UIKit.padding(created, 16)
		pad.PaddingTop = UDim.new(0, 24)
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(size, size + Theme.Lip),
			CellPadding = UDim2.fromOffset(16, 24),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, created)
		flyout = created
		local more = HudBubble.claimTile(menu, "More")
		more.Activated:Connect(function()
			HudBubble.toggleMore(menu)
		end)
	end
	local look = if spec.IconName then HudBubble.EntryLooks[spec.IconName] else nil
	local face = Bubble.tile(flyout :: Frame, {
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

-- Opens / shuts the MORE flyout (nil = the other way round). Returns whether it is open.
function HudBubble.toggleMore(menu: Instance, open: boolean?): boolean
	local gui = menu.Parent :: Instance
	local flyout = gui:FindFirstChild("MoreFlyout") :: Frame?
	if not flyout then
		return false
	end
	local on = if open == nil then not flyout.Visible else open
	flyout.Visible = on
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

-- One hotbar slot: a carried ore in its rarity colour, "?" for dirty ore,
-- empty when nothing is carried.
function HudBubble.slot(parent: Instance, filled: Color3?, order: number, mystery: boolean?): Frame
	local size = (parent:GetAttribute("SlotSize") :: number?) or 70
	local holder, face = Bubble.body(parent, Bubble.role("Plain"), Vector2.new(size, size), { Name = "Slot" .. order, Corner = 16 })
	holder.LayoutOrder = order
	if mystery then
		Bubble.ink(face, "?", math.floor(size * 0.6), {
			Name = "Mystery",
			FontFace = Theme.TitleFont,
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Theme.InkSoft,
			ZIndex = 4,
		})
	elseif filled then
		local gem = UIKit.new("Frame", {
			Name = "Ore",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = filled,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			Size = UDim2.fromScale(0.5, 0.5),
			ZIndex = 4,
		}, face)
		Bubble.corner(gem, 8)
		Bubble.stroke(gem, 3)
		Bubble.gradient(gem, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	end
	return holder
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
	local collect, collectHolder = Bubble.button(body, { Name = "Collect", Text = "COLLECT", Role = "Go", Size = Vector2.new(240, 62), TextSize = 30 })
	collectHolder.AnchorPoint = Vector2.new(0.5, 1)
	collectHolder.Position = UDim2.fromScale(0.5, 1)
	return { Gui = gui, Dim = dim, Panel = window.Holder, Amount = amount, Detail = detail, Collect = collect }
end

return HudBubble
