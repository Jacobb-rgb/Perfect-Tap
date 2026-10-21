--[[
	The DROPPER WORKS shop window (concept, owner 2026-10-21: like Sandbox
	Tycoon's build menu, in Terra Forge's fonts): a white panel with blue tab
	buttons on top (DROPPERS / LASERS) and the red X, a pink title strip, a grid
	of square tiles (name on top, the item's picture, the green price at the
	bottom; a locked tile is dark with its yellow lock text), the detail pane on
	the right for the picked tile with the big BUY button, and the "max counts"
	box at the bottom.

	  build()                    the window (hidden); Refs.Tiles[id]
	  layout(refs, w, h)         fits the window into w x h design units
	  setTab(refs, tab)          "Droppers" | "Lasers"
	  setTile(refs, id, state)   { Owned, CanAfford, Locked: string? }
	  showDetail(refs, id, state) the right pane for one item
	  setCounts(refs, text)      the max counts box
	  setStatus(refs, text?)     the line under the grid

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperConfig = require(Shared.Config.DropperConfig)
local IconAssets = require(Shared.Config.IconAssets)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local DropperShopView = {}

local rgb = Color3.fromRGB

-- the look (Sandbox Tycoon's light build menu)
DropperShopView.Colors = {
	Panel = rgb(246, 248, 252),
	PanelEdge = rgb(190, 202, 222),
	Tab = rgb(150, 196, 255),
	TabOn = rgb(56, 140, 255),
	TabEdge = rgb(36, 92, 190),
	Strip = rgb(240, 70, 110), -- the pink title strip
	StripEdge = rgb(170, 30, 66),
	Tile = rgb(226, 232, 242),
	TileEdge = rgb(172, 184, 206),
	TilePicked = rgb(56, 140, 255),
	Locked = rgb(54, 58, 70),
	LockText = rgb(255, 214, 50),
	Ink = rgb(40, 44, 60),
	InkSoft = rgb(104, 112, 132),
	Price = rgb(64, 200, 60),
	PriceEdge = rgb(20, 80, 20),
	Buy = rgb(70, 200, 60),
	BuyEdge = rgb(30, 110, 26),
	Grey = rgb(150, 156, 170),
	GreyEdge = rgb(96, 102, 118),
	Close = rgb(236, 64, 76),
	CloseEdge = rgb(140, 24, 36),
	Income = rgb(64, 200, 60),
}
DropperShopView.Font = Font.fromEnum(Enum.Font.FredokaOne)
DropperShopView.Size = Vector2.new(1080, 620)
DropperShopView.Tile = Vector2.new(150, 172)
DropperShopView.Gap = 12
DropperShopView.Columns = 4

export type TileRefs = {
	Id: string,
	Frame: TextButton,
	Price: TextLabel,
	Owned: TextLabel,
	Lock: Frame,
	LockText: TextLabel,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame,
	Tabs: { [string]: TextButton },
	Title: TextLabel,
	Grids: { [string]: Frame },
	Tiles: { [string]: TileRefs },
	Order: { string },
	Detail: {
		Picture: ImageLabel,
		Name: TextLabel,
		Income: TextLabel,
		Ores: Frame,
		Lines: TextLabel,
		Buy: TextButton,
		BuyText: TextLabel,
	},
	Counts: TextLabel,
	Status: TextLabel,
	Close: TextButton,
}

export type TileState = { Owned: number, CanAfford: boolean, Locked: string? }

local C = DropperShopView.Colors

local function text(parent: Instance, words: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = DropperShopView.Font,
		Text = words,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = true,
		ZIndex = 4,
	}, parent)
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	return label
end

-- white text with a dark edge (prices, buttons)
local function bold(parent: Instance, words: string, size: number, color: Color3, edge: Color3, props: { [string]: any }?): TextLabel
	local label = text(parent, words, size, color, props)
	UIKit.new("UIStroke", { Color = edge, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	return label
end

local function button(parent: Instance, color: Color3, edge: Color3, props: { [string]: any }): TextButton
	local b = UIKit.new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 4,
	}, parent)
	for k, v in props do
		(b :: any)[k] = v
	end
	UIKit.corner(b, 8)
	UIKit.new("UIStroke", { Name = "Edge", Color = edge, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end

local function items(tab: string): { { Id: string, Name: string, Price: number, Icon: string } }
	local list = {}
	if tab == "Droppers" then
		for _, dropper in DropperConfig.List do
			table.insert(list, { Id = dropper.Id, Name = dropper.Name, Price = dropper.Price, Icon = "dropper_" .. dropper.Id })
		end
	else
		local laser = DropperConfig.Laser
		table.insert(list, { Id = laser.Id, Name = laser.Name, Price = laser.Price, Icon = "dropper_" .. laser.Id })
	end
	return list
end

local function buildTile(grid: Instance, item: { Id: string, Name: string, Price: number, Icon: string }, index: number): TileRefs
	local size, gap, cols = DropperShopView.Tile, DropperShopView.Gap, DropperShopView.Columns
	local col, row = (index - 1) % cols, (index - 1) // cols
	local tile = button(grid, C.Tile, C.TileEdge, {
		Name = item.Id,
		Position = UDim2.fromOffset(col * (size.X + gap), row * (size.Y + gap)),
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = index,
	})
	local nameLabel = text(
		tile,
		item.Name,
		17,
		C.Ink,
		{ Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 22), TextWrapped = false, TextScaled = true }
	)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 17 }, nameLabel)
	Bubble.icon(tile, item.Icon, 104, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 82), ZIndex = 4 })
	local price = bold(tile, Format.money(item.Price), 24, C.Price, C.PriceEdge, {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -8, 0, 28),
	})
	local owned = UIKit.new("TextLabel", {
		Name = "Owned",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.Buy,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -4, 0, 28),
		Size = UDim2.fromOffset(52, 22),
		FontFace = DropperShopView.Font,
		Text = "x1",
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 6,
	}, tile)
	UIKit.corner(owned, 11)
	-- the dark lock cover with its yellow words (Sandbox's "Tier 2")
	local lock = UIKit.new("Frame", {
		Name = "Lock",
		BackgroundColor3 = C.Locked,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
	}, tile)
	UIKit.corner(lock, 8)
	local lockName = text(
		lock,
		item.Name,
		17,
		rgb(220, 224, 236),
		{ Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 22), TextWrapped = false, TextScaled = true, ZIndex = 8 }
	)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 17 }, lockName)
	text(
		lock,
		"LOCKED",
		22,
		Color3.new(1, 1, 1),
		{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(60, 50), ZIndex = 8 }
	)
	local lockText = bold(lock, "", 22, C.LockText, rgb(40, 30, 0), {
		Name = "LockText",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -8, 0, 26),
		ZIndex = 8,
	})
	return { Id = item.Id, Frame = tile, Price = price, Owned = owned, Lock = lock, LockText = lockText }
end

function DropperShopView.build(): Refs
	local gui = UIKit.screen("TerraForgeDroppers", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local size = DropperShopView.Size
	local root = UIKit.new("Frame", {
		Name = "Window",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		SelectionGroup = true,
		ZIndex = 2,
	}, holder)
	UIKit.corner(root, 14)
	UIKit.new("UIStroke", { Color = C.PanelEdge, Thickness = 4 }, root)

	-- the tab buttons (icon + word) and the X
	local tabs: { [string]: TextButton } = {}
	for i, tab in { { "Droppers", "dropper_BasicDropper" }, { "Lasers", "dropper_MoneyLaser2X" } } do
		local b = button(root, C.Tab, C.TabEdge, {
			Name = tab[1],
			Position = UDim2.fromOffset(16 + (i - 1) * 178, 14),
			Size = UDim2.fromOffset(166, 58),
		})
		Bubble.icon(b, tab[2], 48, { Position = UDim2.fromOffset(6, 5), ZIndex = 5 })
		bold(
			b,
			string.upper(tab[1]),
			22,
			Color3.new(1, 1, 1),
			C.TabEdge,
			{ Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -60, 1, 0), ZIndex = 5 }
		)
		tabs[tab[1]] = b
	end
	local close = button(root, C.Close, C.CloseEdge, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(54, 54),
	})
	bold(close, "X", 32, Color3.new(1, 1, 1), C.CloseEdge, { Size = UDim2.fromScale(1, 1), ZIndex = 5 })

	-- the pink title strip
	local strip = UIKit.new("Frame", {
		Name = "Strip",
		BackgroundColor3 = C.Strip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.fromOffset(4 * DropperShopView.Tile.X + 3 * DropperShopView.Gap, 40),
		ZIndex = 3,
	}, root)
	UIKit.corner(strip, 8)
	UIKit.new("UIStroke", { Color = C.StripEdge, Thickness = 3 }, strip)
	local title = bold(strip, "Droppers", 26, Color3.new(1, 1, 1), C.StripEdge, { Size = UDim2.fromScale(1, 1) })

	-- one grid per tab
	local grids: { [string]: Frame } = {}
	local tiles: { [string]: TileRefs } = {}
	local order: { string } = {}
	for _, tab in { "Droppers", "Lasers" } do
		local grid = UIKit.new("Frame", {
			Name = tab .. "Grid",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 136),
			Size = UDim2.fromOffset(4 * DropperShopView.Tile.X + 3 * DropperShopView.Gap, 2 * DropperShopView.Tile.Y + DropperShopView.Gap),
			Visible = tab == "Droppers",
			ZIndex = 3,
		}, root)
		grids[tab] = grid
		for i, item in items(tab) do
			tiles[item.Id] = buildTile(grid, item, i)
			table.insert(order, item.Id)
		end
	end

	-- the detail pane on the right
	local paneX = 16 + 4 * DropperShopView.Tile.X + 3 * DropperShopView.Gap + 16
	local pane = UIKit.new("Frame", {
		Name = "Detail",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(paneX, 84),
		Size = UDim2.new(1, -paneX - 16, 1, -100),
		ZIndex = 3,
	}, root)
	UIKit.corner(pane, 10)
	UIKit.new("UIStroke", { Color = C.TileEdge, Thickness = 3 }, pane)
	local picture = Bubble.icon(
		pane,
		"dropper_BasicDropper",
		170,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), ZIndex = 4 }
	)
	local name = text(pane, "", 26, C.Ink, { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 30) })
	local income = bold(pane, "", 30, C.Income, C.PriceEdge, { Position = UDim2.fromOffset(8, 206), Size = UDim2.new(1, -16, 0, 34) })
	local ores = UIKit.new(
		"Frame",
		{ Name = "Ores", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 242), Size = UDim2.new(1, -16, 0, 36), ZIndex = 4 },
		pane
	)
	UIKit.list(ores, Enum.FillDirection.Horizontal, 2, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local lines = text(
		pane,
		"",
		17,
		C.InkSoft,
		{ Position = UDim2.fromOffset(10, 282), Size = UDim2.new(1, -20, 0, 66), TextYAlignment = Enum.TextYAlignment.Top }
	)
	local buy = button(pane, C.Buy, C.BuyEdge, {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -28, 0, 62),
	})
	local buyText = bold(buy, "BUY", 30, Color3.new(1, 1, 1), C.BuyEdge, { Size = UDim2.fromScale(1, 1), ZIndex = 5 })

	-- the max counts box (bottom left) and the status line
	local countsBox = UIKit.new("Frame", {
		Name = "Counts",
		BackgroundColor3 = C.Tile,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 16, 1, -58),
		Size = UDim2.fromOffset(300, 44),
		ZIndex = 3,
	}, root)
	UIKit.corner(countsBox, 8)
	UIKit.new("UIStroke", { Color = C.TileEdge, Thickness = 2 }, countsBox)
	local counts = text(countsBox, "", 17, C.Ink, { Size = UDim2.fromScale(1, 1) })
	local status = text(root, "", 17, C.InkSoft, {
		Name = "Status",
		Position = UDim2.new(0, 330, 1, -56),
		Size = UDim2.new(0, 4 * DropperShopView.Tile.X + 3 * DropperShopView.Gap - 314, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local refs: Refs = {
		Gui = gui,
		Root = root,
		Tabs = tabs,
		Title = title,
		Grids = grids,
		Tiles = tiles,
		Order = order,
		Detail = { Picture = picture, Name = name, Income = income, Ores = ores, Lines = lines, Buy = buy, BuyText = buyText },
		Counts = counts,
		Status = status,
		Close = close,
	}
	DropperShopView.setTab(refs, "Droppers")
	DropperShopView.layout(refs, 1280, 720)
	return refs
end

-- Fits the window into a w x h design-unit screen (the HUD's top bar and coins stay in sight).
function DropperShopView.layout(refs: Refs, w: number, h: number)
	local size = DropperShopView.Size
	local fit = math.min(1, (w - 40) / size.X, (h - 150) / size.Y)
	local holder = refs.Root.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
end

function DropperShopView.setTab(refs: Refs, tab: string)
	for name, b in refs.Tabs do
		b.BackgroundColor3 = if name == tab then C.TabOn else C.Tab
	end
	for name, grid in refs.Grids do
		grid.Visible = name == tab
	end
	refs.Title.Text = tab
end

function DropperShopView.setTile(refs: Refs, id: string, state: TileState)
	local tile = refs.Tiles[id]
	if not tile then
		return
	end
	tile.Owned.Visible = state.Owned > 0
	tile.Owned.Text = `x{state.Owned}`
	tile.Lock.Visible = state.Locked ~= nil
	tile.LockText.Text = state.Locked or ""
	tile.Price.TextColor3 = if state.CanAfford then C.Price else C.InkSoft
end

-- The right pane for item `id` (a dropper or the laser); `picked` outlines its tile.
function DropperShopView.showDetail(refs: Refs, id: string, state: TileState)
	local d = refs.Detail
	for tileId, tile in refs.Tiles do
		local edge = tile.Frame:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Color = if tileId == id then C.TilePicked else C.TileEdge
			edge.Thickness = if tileId == id then 5 else 3
		end
	end
	for _, child in d.Ores:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local dropper = DropperConfig.ById[id]
	local price: number
	if dropper then
		d.Name.Text = dropper.Name
		d.Income.Text = Format.perSecond(dropper.Income)
		for i, oreId in dropper.Ores do
			Bubble.icon(d.Ores, "item_Clean_" .. oreId, 34, { LayoutOrder = i, ZIndex = 5 })
		end
		local minutes = math.max(5, math.floor(DropperConfig.payback(dropper) / 300 + 0.5) * 5)
		local back = if minutes < 60
			then `~{minutes} min`
			else `~{minutes // 60} h{if minutes % 60 > 0 then " " .. minutes % 60 .. " min" else ""}`
		d.Lines.Text = `{dropper.Tagline}\nPays back in {back}\nSell back: {Format.money(dropper.Resale)}`
		price = dropper.Price
	else
		local laser = DropperConfig.Laser
		d.Name.Text = laser.Name
		d.Income.Text = `x{laser.Mult} MONEY`
		d.Lines.Text = `{laser.Tagline}\nPut it on a dropper's belt\nSell back: {Format.money(laser.Resale)}`
		price = laser.Price
	end
	d.Picture:SetAttribute("Icon", "dropper_" .. id)
	IconAssets.apply(d.Picture, "dropper_" .. id)
	local can = state.CanAfford and state.Locked == nil
	d.Buy.BackgroundColor3 = if can then C.Buy else C.Grey
	local edge = d.Buy:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Color = if can then C.BuyEdge else C.GreyEdge
	end
	d.BuyText.Text = if state.Locked then state.Locked else "BUY  " .. Format.money(price)
end

function DropperShopView.setCounts(refs: Refs, words: string)
	refs.Counts.Text = words
end

function DropperShopView.setStatus(refs: Refs, words: string?)
	refs.Status.Text = words or ""
end

return DropperShopView
