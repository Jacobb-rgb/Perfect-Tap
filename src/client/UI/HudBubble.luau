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
	                the game HUD (buildGame) has its own BLASTER slot and the
	                backpack button, one group in the middle, instead of
	                Roblox's hotbar (carryGroup)
	  under the bar toasts (white pills with an icon)

	Compact (phones, uiScale <= CompactScale): bigger touch targets in design
	units (>= 44 pt at uiScale 0.62) and the income chip beside the coins.
	Designed for 720 design units of screen height.

	The round look (owner 2026-10-27, the UI pack reel's HUD; PopTheme.Look =
	"Round"): the game menu is the reel's grid of dark tiles (RoundMenu:
	Store, Rebirth, Golems, Inventory, Spin, Ride, Daily, Build, More), two a
	row in a tall block with the TRAIN chip under it as wide as it (owner
	2026-10-28: "the block tall, not wide"; fitRound sizes it for the
	screen; touch screens keep it wide at the top, out of the thumbstick's
	zone), Title Case words, a tilted sticker ("FREE!" on Spin while
	WheelController's badge counts a ready spin, setTileBadge); the top centre is a row of separate buttons
	(Shop red: the Robux STORE, then LOBBY / BASE / VAULT from TeleportView);
	the money bottom-left without the cash, the income line under it; three
	offers mid-right (Offers: the product's picture, a green "R$99" tag, its
	name; StoreController opens the Store at it and hides what is owned).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local CashBuilder = require(Shared.Builders.CashBuilder)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local StoreConfig = require(Shared.Config.StoreConfig)
local PictureModels = require(Shared.Builders.PictureModels)
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

-- The round look's game menu (the reel's tiles, in its order, and Ride): every tile hidden
-- until a controller claims it (StoreController Store, SideMenuController Rebirth / Golems /
-- Quests, BackpackController Inventory, WheelController Spin (ui/boost-corner), HoverboardView
-- Ride (owner 2026-10-28: a grey tile like the others, not the round violet button), BuildView Build).
HudBubble.RoundMenu = {
	{ Id = "Store", Label = "Store", Icon = "cart", Role = "Store" },
	{ Id = "Rebirth", Label = "Rebirth", Icon = "rebirth", Role = "Rebirth" },
	{ Id = "Golems", Label = "Golems", Icon = "golem_GildedPorter", Role = "Golems" },
	{ Id = "Backpack", Label = "Inventory", Icon = "backpack", Role = "Backpack" },
	{ Id = "Wheel", Label = "Spin", Icon = "wheel", Role = "Wheel" },
	{ Id = "Ride", Label = "Ride", Icon = "hoverboard", Role = "Ride" },
	{ Id = "Quests", Label = "Daily", Icon = "medal", Role = "Quests" },
	{ Id = "Build", Label = "Build", Icon = "build", Role = "Build" },
	{ Id = "More", Label = "More", Icon = "more", Role = "More" },
} :: { MenuEntry }

-- The round look's tile accents (the reel: every dark tile its own colour on the edge and the lip).
HudBubble.RoundPaints = {
	Store = "Crimson",
	Rebirth = "Magenta",
	Golems = "Orange",
	Backpack = "Ember",
	Wheel = "Violet",
	Ride = "Teal",
	Quests = "Pink",
	Build = "Lime",
	More = "Steel",
} :: { [string]: string }

-- The side menu entries that are tiles on the left in the round look (the rest go behind More).
HudBubble.RoundMain = { Store = true, Rebirth = true, Golems = true, Quests = true } :: { [string]: boolean }

--[[
	The round look's offers mid-right (the reel's three potions with "R$49"):
	a Store card each (StoreConfig), its picture, the tag and the name.
]]
HudBubble.Offers = {
	{ Card = "StarterPack", Name = "Starter Pack", Icon = "golem_GildedPorter" },
	{ Card = "DoubleMoney", Name = "2x Money", Icon = "cash_safe" },
	{ Card = "TripleLucky15", Name = "Triple Lucky", Icon = "clover" },
}
HudBubble.OfferSize = 74 -- design units: the picture square (phones: OfferSizePhone); the reel: ~110 px of 1080
HudBubble.OfferGap = 35 -- between two offers (the reel: one every 200 px)
HudBubble.OfferSizePhone = 74 -- 46 pt at the phones' 0.62 scale

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
	Width: number, -- the screen's width in design units (1280 when unknown)
	Touch: boolean, -- a touch-first screen (phones, tablets): no offers, the tiles at the top
	TenFoot: boolean, -- a TV: the round look keeps out of the outer 5 % (Inset)
	Inset: number, -- design units kept free at the left and right edges (TVs: 5 % of the width)
	-- the round look's grid for this screen (fitRound; nil in the other looks)
	Top: number?, -- the tiles' top (design units under Roblox's top bar)
	Chip: ("Under" | "Beside")?, -- the TRAIN chip under the tiles (as wide as them) or beside the last row
	ChipStack: boolean?, -- under them on a mouse or a TV: TrainView's stacked chip (the block's width)
	ChipCap: number?, -- beside them on touch: the chip ends here (left of the boost column beside the tutorial bubble)
	ChipY: number?, -- beside them on touch: the chip's top (lifted over the touch buttons under it)
	ChipGap: number?, -- under them squeezed (the smallest phones): the gap over the chip
}

HudBubble.NarrowWidth = 600 -- points; like TeleportView.NarrowWidth
HudBubble.TenFootSafe = 0.05 -- a TV's title-safe band (TutorialView.TenFootSafe)

-- Is this a touch-first device (a phone or a tablet; with a keyboard too, but no mouse)? The test
-- MenuPanels.isTouch, TrainController and BoostController use. false in Lune.
function HudBubble.isTouch(): boolean
	local ok, touch = pcall(function()
		local input = game:GetService("UserInputService")
		return input.TouchEnabled and not input.MouseEnabled
	end)
	return ok and touch == true
end

-- Is this a TV (Roblox's ten-foot interface)? false in Lune.
function HudBubble.isTenFoot(): boolean
	local ok, ten = pcall(function()
		return game:GetService("GuiService"):IsTenFootInterface()
	end)
	return ok and ten == true
end

--[[
	The layout for a screen: `uiScale` (HudController's), the screen's width in
	points, touch / TV, and `guiHeight`: the HUD gui's height in points (the
	screen under Roblox's top bar; nil = this screen's, else a 16:9 one at
	`uiScale`). The round look's grid is fitted to it (fitRound).
]]
function HudBubble.layout(uiScale: number, screenWidth: number?, touch: boolean?, tenFoot: boolean?, guiHeight: number?): Layout
	local width = if screenWidth and screenWidth > 0 and uiScale > 0 then screenWidth / uiScale else 1280
	local isTouch, isTen = touch == true, tenFoot == true
	local inset = if isTen then math.ceil(width * HudBubble.TenFootSafe) else 0
	local layout: Layout
	if uiScale <= HudBubble.CompactScale then
		local narrow = screenWidth ~= nil and screenWidth < HudBubble.NarrowWidth
		-- (the round look: 72 units = 44.6 pt; fitRound picks the columns)
		local round = PopTheme.round()
		layout = {
			Compact = true,
			Narrow = narrow,
			Tile = if round then 72 else 78,
			TileGap = if round then 6 else 12,
			Columns = if round then 4 else 3,
			TabWidth = if narrow then 74 else 118,
			TabHeight = 72,
			Slot = 76,
			SlotGap = 10,
			Slots = 5,
			Width = width,
			Touch = isTouch,
			TenFoot = isTen,
			Inset = inset,
		}
	else
		-- (the round look on a touch tablet: smaller tiles a row at the top, like a phone's, so the
		-- grid stays above the thumbstick's start zone and left of the top row's buttons)
		local tablet = PopTheme.round() and isTouch
		layout = {
			Compact = false,
			Narrow = false,
			Tile = if tablet then 58 elseif PopTheme.round() then 77 else 82, -- (the reel's tiles: 116 px of 1080 with 8..12 px gaps)
			TileGap = if tablet then 6 elseif PopTheme.round() then 7 else 12,
			Columns = if tablet then 4 else 2,
			TabWidth = 140,
			TabHeight = 52,
			Slot = 70,
			SlotGap = 10,
			Slots = 6,
			Width = width,
			Touch = isTouch,
			TenFoot = isTen,
			Inset = inset,
		}
	end
	if PopTheme.round() then
		local height = guiHeight or HudBubble.guiHeight() or 720 * uiScale - HudBubble.PreviewInset
		HudBubble.fitRound(layout, height / math.max(uiScale, 0.01), uiScale)
	end
	return layout
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
	if PopTheme.round() then
		-- the reel: the amount big in green with a thick dark edge, no cash, and a white line
		-- under it (the reel's "Friend Boost +0%": our income per second)
		-- (measured: "$0" 53 px and the line's capitals 35 px tall at 1080p, 8 px from the left edge)
		local big, line, tall = HudBubble.moneySize(layout)
		local panel = UIKit.new("Frame", {
			Name = "Coins",
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(
				0,
				(if layout.Compact then 18 else 6) + layout.Inset,
				if layout.TenFoot then 0.95 else 1,
				if layout.Compact then -22 else -12
			),
			Size = UDim2.fromOffset(HudBubble.CoinsWidth + 40, tall),
		}, gui)
		local amount = Pop.text(panel, "$0", big, {
			Name = "Amount",
			AnchorPoint = Vector2.new(0, 0),
			FontFace = PopTheme.Heavy,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, big + 6),
			TextColor3 = PopTheme.MoneyNumber,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local amountEdge = amount:FindFirstChildOfClass("UIStroke") :: UIStroke
		amountEdge.Thickness = 4.5
		local income = Pop.text(panel, "+$0/s", line, {
			Name = "Income",
			AnchorPoint = Vector2.new(0, 1),
			FontFace = PopTheme.Heavy,
			Position = UDim2.new(0, 2, 1, 0),
			Size = UDim2.new(1, -2, 0, line + 6),
			TextColor3 = PopTheme.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		return panel, amount, income
	end
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
	local origin = UDim2.fromOffset((if PopTheme.round() then HudBubble.RoundMenuLeft else 18) + layout.Inset, HudBubble.menuTop(layout))
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
	local round = PopTheme.round()
	return Pop.tile(parent, {
		Name = o.Name,
		Label = Pop.caption(o.Label), -- (the round look: Title Case, the reel)
		Icon = o.Icon,
		Paint = (if round then HudBubble.RoundPaints[o.Role] else nil) or HudBubble.RolePaints[o.Role] or "Slate",
		Size = o.Size,
		LayoutOrder = o.LayoutOrder,
	})
end

-- The tiles the game menu can show in this look (the round look: RoundMenu).
function HudBubble.gameMenu(): { MenuEntry }
	return if PopTheme.round() then HudBubble.RoundMenu else HudBubble.GameMenu
end

--[[
	A tilted sticker word on a tile's top-left corner (the reel's "OP!"):
	"FREE!" on Spin while a spin is ready. nil / "" takes it off.
]]
function HudBubble.setSticker(face: GuiObject, text: string?)
	local old = face:FindFirstChild("Sticker")
	if text == nil or text == "" then
		if old then
			old:Destroy()
		end
		return
	end
	if old and old:IsA("TextLabel") then
		old.Text = text
		return
	end
	-- (the tile's size from its holder, the grid's cell: 24 % of it)
	local holder = face.Parent
	local grid = if holder and holder.Parent then holder.Parent:FindFirstChildOfClass("UIGridLayout") else nil
	local tile = if grid then grid.CellSize.Y.Offset else 76
	local size = math.max(16, math.floor(tile * 0.22))
	local sticker = Pop.title(face, text, size, "Gold", {
		Name = "Sticker",
		AnchorPoint = Vector2.new(0, 0.5),
		FontFace = PopTheme.Heavy,
		Position = UDim2.new(0, -8, 0, math.floor(size * 0.85)),
		Rotation = -12,
		Size = UDim2.new(0.8, 0, 0, size + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	})
	local edge = sticker:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = 3
	end
end

HudBubble.MenuTop = 8 -- the tiles' top under Roblox's top bar (CoreUISafeInsets)
HudBubble.ChipGap = 12
HudBubble.TabletChipGap = 6 -- a touch tablet's tiles and its TRAIN chip
HudBubble.TouchChipHeight = 84 -- TrainView's compact chip (touch screens: TrainController)
-- the round look on big screens: the reel's tiles sit lower, their middle a little above the
-- screen's (rows 285..772 px of 1080), 10 units from the left edge
HudBubble.RoundMenuTop = 140
HudBubble.RoundMenuLeft = 10

HudBubble.StackChipHeight = 104 -- TrainView's stacked chip (under the round look's tiles on a mouse or a TV)
HudBubble.StackChipHeightTv = 158 -- the stacked chip on a TV (the name and the line on two rows each)
HudBubble.TouchChipWidth = 384 -- TrainView's compact chip at its own width
HudBubble.StackGap = 8 -- the tiles and the stacked chip under them
HudBubble.RoundMinTile = 56 -- design units: the smallest tile on a mouse or a TV (touch: 44 pt)
HudBubble.RoundTouchColumns = { 5, 4 } -- touch: the tries, the first that fits wins
HudBubble.TouchChipMinWidth = 300 -- the touch chip under the tiles needs this much (its name, line and SEND)
HudBubble.TutorialBarGap = 10 -- TutorialView.BarGap: the touch bubble starts this far right of the top row
-- BoostView's corner column beside the touch tutorial bubble: CornerGap + CornerWidth + CornerGap
HudBubble.BoostColumnRoom = 14 + 72 + 14

--[[
	The touch buttons in the phone's bottom right, in px from the gui's bottom-right corner
	(left, top, right, bottom edges; small = the shorter screen side 500 px or less): Roblox's
	jump, the game's Grab and FIRE (BoostView.TouchButtons is this table; the LightUI spec
	reads InteractController / MiningController to keep it in step. Grab: Roblox draws CAS
	buttons 45 px, 35 on a 320 px screen; 70 / 90 here is on the safe side.)
]]
HudBubble.TouchButtons = {
	Small = {
		{ Name = "Jump", Left = 95, Top = 90, Right = 25, Bottom = 20 }, -- Roblox's jump button
		{ Name = "Grab", Left = 170, Top = 150, Right = 100, Bottom = 80 }, -- InteractController: SetPosition(1, -170, 1, -150)
		-- MiningController: an 88 px holder centred at (1, -240, 1, -100), its face lifted 5 px (top 149)
		{ Name = "Fire", Left = 284, Top = 149, Right = 196, Bottom = 56 },
	},
	Large = {
		{ Name = "Jump", Left = 170, Top = 210, Right = 50, Bottom = 90 },
		{ Name = "Grab", Left = 170, Top = 150, Right = 80, Bottom = 60 },
		{ Name = "Fire", Left = 368, Top = 203, Right = 252, Bottom = 82 }, -- 116 px centred at (1, -310, 1, -140), lifted 5
	},
} :: { [string]: { { Name: string, Left: number, Top: number, Right: number, Bottom: number } } }

-- The touch buttons as boxes in a gui `width` x `height` design units at `uiScale` (small: the
-- shorter screen side, `height` plus Roblox's top bar, 500 pt or less).
function HudBubble.touchButtonBoxes(width: number, height: number, uiScale: number): { { number } }
	local s = math.max(uiScale, 0.01)
	local small = math.min(width * s, height * s + HudBubble.PreviewInset) <= 500
	local boxes = {}
	for _, b in HudBubble.TouchButtons[if small then "Small" else "Large"] do
		table.insert(boxes, { width - b.Left / s, height - b.Top / s, width - b.Right / s, height - b.Bottom / s })
	end
	return boxes
end
HudBubble.RoundColumns = { 2, 3, 4, 5 } -- a mouse or a TV: the tries (two: the owner's tall block)

-- The stacked TRAIN chip's height on this layout (TrainView mirrors it: CHIP.Stack / CHIP.StackTv).
function HudBubble.stackChipHeight(layout: Layout): number
	return if layout.TenFoot then HudBubble.StackChipHeightTv else HudBubble.StackChipHeight
end

-- The money bottom-left in the round look: (the amount's text size, the income line's, the panel's height).
function HudBubble.moneySize(layout: Layout): (number, number, number)
	local big = if layout.Compact then 44 else 40
	local line = if layout.Compact then math.floor(big * 0.52) else 27
	return big, line, big + line + 14
end

-- The lowest the round look's left column (the tiles and the TRAIN chip) may reach in a gui
-- `height` design units tall: above the "+$X" floaters over the money (and its Server Luck line).
function HudBubble.roundFloor(layout: Layout, height: number): number
	local _, _, money = HudBubble.moneySize(layout)
	local bottom = if layout.TenFoot then height * (1 - HudBubble.TenFootSafe) else height
	return bottom - (money + 30 + 60) - 6 -- (the floaters: 60 tall, 30 over the money; a margin)
end

--[[
	The round look's grid for a gui `height` design units tall at `uiScale` (owner
	2026-10-28: "the block tall, not wide", the TRAIN chip under it, "ending like
	it"): sets layout.Columns, Tile, Top, Chip and ChipStack.
	  mouse / TV   two a row (the reel's column), the tiles smaller on a short
	               screen (never under RoundMinTile); three, four, five a row
	               when two can't fit; the stacked chip (StackChipHeight) under
	               them as wide as them, all above the floaters (roundFloor). As
	               low as the reel's tiles (RoundMenuTop) where there is room.
	  touch        at the top, wide: the thumbstick's start zone (the left 40 %
	               under the top third) stays free on tablets; five a row where
	               they stay left of the top row, else four; the touch chip
	               (TouchChipHeight) under them as wide as them
	  no fit       (the smallest screens) the tiles at the top, as many a row as
	               stay left of the top row at their size (touch: never under
	               44 pt), the chip beside their last row. Touch: squeezed
	               under them (44 pt tiles, a small gap) when they are wide
	               enough for the chip and it ends above the money; else
	               beside, lifted over the touch buttons under it (FIRE,
	               Grab, Jump: TouchButtons) and ending left of the boost
	               column that stands beside the tutorial bubble (ChipCap,
	               ChipY; TutorialView.layout, BoostView.cornerSpot)
]]
function HudBubble.fitRound(layout: Layout, height: number, uiScale: number)
	local count = #HudBubble.RoundMenu
	local left = HudBubble.RoundMenuLeft + layout.Inset
	local tabsLeft = layout.Width / 2 - HudBubble.topBarSize(layout).X / 2 - 8
	local floor = HudBubble.roundFloor(layout, height)
	local gap = layout.TileGap
	local stackH = HudBubble.stackChipHeight(layout)
	layout.ChipCap, layout.ChipY, layout.ChipGap = nil, nil, nil
	local function wide(columns: number, tile: number): number
		return columns * tile + (columns - 1) * gap
	end
	if layout.Touch then
		-- (a tablet: above the thumbstick's zone too; a phone's tiles are never smaller than 44 pt)
		local limit = if layout.Compact then floor else math.min(floor, height / 3)
		local minTile = math.ceil(44 / math.max(uiScale, 0.01))
		local chipGap = if layout.Compact then HudBubble.ChipGap else HudBubble.TabletChipGap
		for _, columns in HudBubble.RoundTouchColumns do
			local rows = math.ceil(count / columns)
			local tile = layout.Tile
			-- (narrower tiles to stay left of the top row, and shorter ones to stay above the zone)
			tile = math.min(tile, math.floor((tabsLeft - left - (columns - 1) * gap) / columns))
			tile = math.min(tile, math.floor((limit - HudBubble.MenuTop - chipGap - HudBubble.TouchChipHeight - (rows - 1) * gap) / rows))
			if tile >= minTile then
				layout.Columns, layout.Tile, layout.Top = columns, tile, HudBubble.MenuTop
				layout.Chip, layout.ChipStack = "Under", false
				return
			end
		end
	else
		for _, columns in HudBubble.RoundColumns do
			local rows = math.ceil(count / columns)
			local room = floor - HudBubble.MenuTop - HudBubble.StackGap - stackH - (rows - 1) * gap
			local tile = math.min(layout.Tile, math.floor(room / rows))
			if tile >= HudBubble.RoundMinTile and left + wide(columns, tile) <= tabsLeft then
				local need = rows * tile + (rows - 1) * gap + HudBubble.StackGap + stackH
				layout.Columns, layout.Tile = columns, tile
				layout.Top = math.clamp(floor - need, HudBubble.MenuTop, HudBubble.RoundMenuTop)
				layout.Chip, layout.ChipStack = "Under", true
				return
			end
		end
	end
	-- nothing fits: at the top, as many a row as stay left of the top row (touch: at 44 pt;
	-- fewer a row, more rows), the chip beside their last row
	local tile = layout.Tile
	if layout.Touch then
		tile = math.max(tile, math.ceil(44 / math.max(uiScale, 0.01)))
	end
	local columns = 2
	for _, try in { 5, 4, 3 } do
		if left + wide(try, tile) <= tabsLeft then
			columns = try
			break
		end
	end
	layout.Columns, layout.Tile, layout.Top = columns, tile, HudBubble.MenuTop
	layout.Chip, layout.ChipStack = "Beside", false
	if not layout.Touch then
		return
	end
	local rows = math.ceil(count / columns)
	-- squeezed under the tiles: 44 pt tiles from 4 units down, the chip 4 under them, above the money
	local _, _, money = HudBubble.moneySize(layout)
	local moneyTop = height - money - (if layout.Compact then 22 else 12)
	local squeezeTop, squeezeGap = 4, 4
	local roomTile = math.floor((moneyTop - 1 - HudBubble.TouchChipHeight - squeezeGap - squeezeTop - (rows - 1) * gap) / rows)
	local squeezed = math.min(tile, roomTile)
	local minTile = math.ceil(44 / math.max(uiScale, 0.01))
	if squeezed >= minTile and wide(columns, squeezed) >= HudBubble.TouchChipMinWidth then
		layout.Tile, layout.Top = squeezed, squeezeTop
		layout.Chip, layout.ChipGap = "Under", squeezeGap
		return
	end
	-- beside: it ends left of the boost column beside the tutorial bubble (which starts right of
	-- the top row) and rises over the touch buttons under it, never into the top row
	local barRight = layout.Width / 2 + HudBubble.topBarSize(layout).X / 2
	local cap = barRight + HudBubble.TutorialBarGap - HudBubble.BoostColumnRoom
	layout.ChipCap = cap
	local chipLeft = left + wide(columns, tile) + HudBubble.ChipGap
	local chipRight = math.min(chipLeft + HudBubble.TouchChipWidth, cap)
	local chipH = HudBubble.TouchChipHeight
	local chipTop = HudBubble.MenuTop + rows * tile + (rows - 1) * gap - math.max(tile, chipH)
	for _, b in HudBubble.touchButtonBoxes(layout.Width, height, uiScale) do
		if chipLeft < b[3] and b[1] < chipRight and chipTop + chipH > b[2] - 6 then
			chipTop = b[2] - 6 - chipH
		end
	end
	local barBottom = HudBubble.TopBarUnderRow + HudBubble.topBarSize(layout).Y + 4
	layout.ChipY = math.max(chipTop, barBottom)
end

-- The tiles' top (design units under Roblox's top bar, CoreUISafeInsets): the round look's
-- fitted top (fitRound), else right under the bar.
function HudBubble.menuTop(layout: Layout): number
	return layout.Top or HudBubble.MenuTop
end

-- Does the TRAIN chip go beside the tiles' last row (the round look when it can't go under them)?
function HudBubble.chipBeside(layout: Layout): boolean
	return layout.Chip == "Beside"
end

-- The TRAIN chip's left edge in the round look (design units): the tiles' left edge (under
-- them) or right of them (beside); nil in the other looks (TrainView.ChipLeft).
function HudBubble.chipLeft(layout: Layout): number?
	if layout.Chip == nil then
		return nil
	end
	local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
	if layout.Chip == "Under" then
		return m.Origin.X.Offset
	end
	return m.Origin.X.Offset + m.Width + HudBubble.ChipGap
end

-- The TRAIN chip's width when it goes under the round look's tiles (theirs), beside them on touch
-- up to ChipCap at most, else nil (TrainView's own).
function HudBubble.chipWidth(layout: Layout): number?
	local cap = layout.ChipCap
	if layout.Chip == "Beside" and cap then
		local left = HudBubble.chipLeft(layout) :: number
		return math.min(HudBubble.TouchChipWidth, math.floor(cap - left))
	end
	if layout.Chip ~= "Under" then
		return nil
	end
	return HudBubble.menuMetrics(layout, #HudBubble.gameMenu()).Width
end

-- The TRAIN chip's top: under the game menu's tiles (design units, CoreUISafeInsets).
function HudBubble.chipTop(layout: Layout): number
	local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
	local top = HudBubble.menuTop(layout)
	if layout.Chip == "Beside" then
		if layout.ChipY then
			return layout.ChipY -- (touch: lifted over the touch buttons, fitRound)
		end
		-- (beside the last row of tiles, its top with theirs; the taller compact chip ends with them)
		local chip = if layout.Compact or layout.Touch then HudBubble.TouchChipHeight else 0
		return top + m.Height - math.max(m.CellHeight, chip)
	elseif layout.Chip == "Under" then
		local gap = if layout.ChipGap
			then layout.ChipGap
			elseif layout.ChipStack then HudBubble.StackGap
			elseif layout.Touch and not layout.Compact then HudBubble.TabletChipGap
			else HudBubble.ChipGap
		return top + m.Height + gap
	end
	-- (phones: the Shop pill rides on this row's right end, under the touch
	-- tutorial bubble; the flat Pop tiles are shorter, so keep the old row)
	local extra = if layout.Compact then 28 else 0
	-- (a touch tablet: the compact chip, TouchChipHeight tall, ends above the thumbstick's zone)
	local gap = if layout.Touch and not layout.Compact then HudBubble.TabletChipGap else HudBubble.ChipGap
	return top + m.Height + gap + extra
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
	-- (the round look on phones: no pill on the chips' row; they stop short of the screen's edge)
	if PopTheme.round() and gui:GetAttribute("CompactHud") == true and width == width and width > 0 then
		return width - 16 - HudBubble.ChipGap
	end
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
	  Carry   the bottom group, centred (owner 2026-10-28): the BLASTER slot
	          (blasterSlot: Roblox's own hotbar is off, Util/Hotbar) and the
	          backpack button (owner 2026-10-24: everything goes into the
	          backpack): the pack's picture and "n / cap" (carryGroup /
	          setBackpack)
]]

-- The tiles the game menu can show (claimed by controllers).
-- (HudBubble.Menu[1], the BACKPACK tile, went next to the hotbar: backpackButton.
-- The menu keeps two rows on phones: 6 tiles in 3 columns; EMOTES is behind MORE.)
HudBubble.GameMenu = {
	HudBubble.Menu[2],
	HudBubble.Menu[3],
	HudBubble.Menu[4],
	{ Id = "Elevator", Label = "ELEVATOR", Icon = "lift", Role = "Base" }, -- the side menu's Elevator entry claims it
	HudBubble.Menu[5],
	-- Spin & Win (owner 2026-10-28: the wheel's picture as a tile next to MORE, under
	-- BOOSTS, instead of the FREE SPIN! chip; WheelController claims it, badge = spins ready)
	{ Id = "Wheel", Label = "SPIN", Icon = "wheel", Role = "Wheel" },
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
	CarryPanel: Frame, -- the bottom group's holder: the BLASTER slot + the backpack button (build mode hides it)
	Backpack: TextButton, -- the backpack button: opens the inventory (BackpackController)
	CarryLabel: TextLabel, -- the button's "n / cap"
	BlasterSlot: TextButton?, -- the BLASTER slot left of it (BlasterSlotController); nil on the dark HUD
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

-- This screen's HUD gui height in points (the viewport under Roblox's top bar), nil without a camera.
function HudBubble.guiHeight(): number?
	local ok, height = pcall(function()
		local camera = game:GetService("Workspace").CurrentCamera
		if not camera then
			return nil
		end
		return camera.ViewportSize.Y - game:GetService("GuiService"):GetGuiInset().Y
	end)
	return if ok and type(height) == "number" and height > 0 then height else nil
end

-- The teleport bar (owner 2026-10-20: BASE / MINE / SPAWN in his photo, text
-- only, at the very top): button sizes per layout, design units.
HudBubble.TopBarPad = 5
HudBubble.TopBarGap = 8
HudBubble.PreviewInset = 36 -- the preview renderer's top bar inset (px)

function HudBubble.topBarButton(layout: Layout): Vector2
	-- (the round look: four buttons in the row, the Shop first; a little narrower on phones so
	-- the row stays clear of the left tiles)
	local round = PopTheme.round()
	if layout.Narrow then
		return Vector2.new(if round then 80 else 88, 72) -- (the smallest phones: as wide as the old icon tabs)
	elseif layout.Compact then
		return Vector2.new(if round then 94 else 128, 72)
	end
	if round then
		-- (the reel's tabs: 165 x 65 units, 13 % of the screen's width each; narrower on a tablet so
		-- the four stay clear of its tutorial bubble, 289 units from the right edge)
		return Vector2.new(math.clamp(math.floor((layout.Width - 612) / 4), HudBubble.TabMin, HudBubble.TabMax), 64)
	end
	return Vector2.new(150, 46)
end
HudBubble.TabMin = 110 -- the round look's PC tab widths (design units)
HudBubble.TabMax = 165

-- Does the round look's red Shop button lead the top row on this layout?
function HudBubble.shopInRow(layout: Layout): boolean
	return PopTheme.round() and not layout.Narrow
end

function HudBubble.topBarSize(layout: Layout): Vector2
	local b = HudBubble.topBarButton(layout)
	-- (the round look: the red Shop button leads the row; not on the smallest phones, where
	-- the row must stay short: the Store tile is the left grid's first)
	local count = #HudBubble.Spots + (if HudBubble.shopInRow(layout) then 1 else 0)
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

--[[
	The round look's red Shop button in the top row (named "ShopPill": StoreController
	opens the Store with it): the cart over its left end, "Shop" beside it.
]]
function HudBubble.shopButton(topBar: Instance, size: Vector2, layout: Layout): TextButton
	local button = Pop.button(topBar, "Shop", "Crimson", size, { Name = "ShopPill", LayoutOrder = 0 })
	local label = button:FindFirstChild("Label") :: TextLabel?
	if not layout.Compact and IconAssets.shows("cart") then
		Pop.tabMark(button, "cart", size.Y) -- (the reel's faded picture over the left end)
	end
	if label then
		local lip = Pop.lipUnits(size.Y)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, -math.floor(lip / 2))
		label.Size = UDim2.new(1, -16, 0, math.floor(size.Y * 0.62))
		Pop.fit(label, if layout.Compact then 30 else 34)
		Pop.shadow(label, 3)
	end
	return button
end

--[[
	The round look's offers mid-right (HudBubble.Offers, the reel's column of
	potions): a picture button per offer named like its Store card over a
	white sunburst, "R$99" in lime letters tilted over its top-right corner
	and its name under it. StoreController opens the Store at the card and
	hides an offer the player owns or can't buy. Returns the column.
]]
function HudBubble.offers(gui: Instance, layout: Layout): Frame
	local size = if layout.Compact then HudBubble.OfferSizePhone else HudBubble.OfferSize
	local nameH = if layout.Compact then 22 else 24
	local gap = HudBubble.OfferGap
	local cell = size + nameH + gap
	local width = size + 60
	local column = UIKit.new("Frame", {
		Name = "Offers",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -(6 + layout.Inset), 0.5, 0), -- (a TV: out of the safe band)
		Size = UDim2.fromOffset(width, #HudBubble.Offers * cell - gap),
	}, gui)
	UIKit.list(column, Enum.FillDirection.Vertical, gap, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	for i, offer in HudBubble.Offers do
		local spec = StoreConfig.ById[offer.Card]
		local product = if spec then MonetizationConfig.Products[spec.Keys[1]] else nil
		local holder = UIKit.new("Frame", {
			Name = offer.Card,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.fromOffset(width, size + nameH),
		}, column)
		-- (the reel: a soft white sunburst behind each picture)
		Pop.fx(holder, "fx_rays", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			ImageTransparency = 0.55,
			Position = UDim2.new(0.5, 0, 0, math.floor(size / 2)),
			Size = UDim2.fromOffset(math.floor(size * 1.5), math.floor(size * 1.5)),
			ZIndex = 2,
		})
		local button = UIKit.new("ImageButton", {
			Name = "Offer",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Image = "",
			Position = UDim2.fromScale(0.5, 0),
			ScaleType = Enum.ScaleType.Fit,
			Selectable = true,
			Size = UDim2.fromOffset(size, size),
			ZIndex = 3,
		}, holder)
		IconAssets.apply(button, offer.Icon)
		button:SetAttribute("Icon", offer.Icon)
		button:SetAttribute("Card", offer.Card)
		Pop.fxTag(button, "Lean")
		if product and product.Robux then
			-- (the reel: lime letters with a dark edge, no box, tilted up over the corner)
			local price = Pop.text(button, `R${product.Robux}`, 22, {
				Name = "Price",
				AnchorPoint = Vector2.new(0.5, 0.5),
				FontFace = PopTheme.Heavy,
				Position = UDim2.new(1, -2, 0, 4),
				Rotation = -8,
				Size = UDim2.fromOffset(math.floor(size * 0.9), 28),
				TextColor3 = PopTheme.Paints.Lime.Top,
				ZIndex = 6,
			})
			local edge = price:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Thickness = 2.5
			end
		end
		Pop.text(holder, offer.Name, nameH - 2, {
			Name = "OfferName",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, nameH),
			ZIndex = 4,
		})
	end
	return column
end

function HudBubble.buildGame(uiScale: number?, screenWidth: number?, touch: boolean?, tenFoot: boolean?, guiHeight: number?): GameRefs
	local layout = HudBubble.layout(
		uiScale or HudBubble.screenScale(),
		screenWidth or HudBubble.screenWidth(),
		if touch == nil then HudBubble.isTouch() else touch,
		if tenFoot == nil then HudBubble.isTenFoot() else tenFoot,
		guiHeight
	)
	-- (a TV: the bottom-left pieces stand 5 % in from the edges, the safe band)
	local bottom = if layout.TenFoot then 1 - HudBubble.TenFootSafe else 1
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
		Position = UDim2.new(0, 20 + 60 + layout.Inset, bottom, -(coinsPanel.Size.Y.Offset + 30)),
		Size = UDim2.fromOffset(HudBubble.CoinsWidth, 60),
	}, gui)

	-- the teleport bar at the very top, in Roblox's top bar row (owner: "put it
	-- right at the top"; TeleportView fills it, HudController.placeTopBar lifts
	-- it by the real top inset); zone name and toasts under the safe area's top
	local barSize = HudBubble.topBarSize(layout)
	local round = PopTheme.round()
	local topBar = UIKit.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = PopTheme.Well,
		-- (the round look: the reel's separate buttons, no dark strip behind them)
		BackgroundTransparency = if round then 1 else 0.1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, HudBubble.topBarY(HudBubble.PreviewInset, uiScale or 1)),
		Size = UDim2.fromOffset(barSize.X, barSize.Y),
	}, gui)
	UIKit.corner(topBar, 12)
	local barBorder = Pop.border(topBar, 3)
	barBorder.Enabled = not round
	UIKit.padding(topBar, HudBubble.TopBarPad)
	topBar:SetAttribute("Pop", true)
	topBar:SetAttribute("Bubble", true)
	topBar:SetAttribute("Compact", layout.Compact)
	topBar:SetAttribute("Narrow", layout.Narrow)
	topBar:SetAttribute("Button", HudBubble.topBarButton(layout)) -- (TeleportView sizes its buttons alike)
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

	if round and layout.Compact then
		-- (the round look's four tiles a row on phones reach under the toasts' and the zone's
		-- first words: those draw over the tiles, they only show for a moment)
		toasts.ZIndex = 8
		zone.ZIndex = 8
	elseif layout.Touch and not layout.Compact then
		-- (a touch tablet: the TRAIN chip's gui draws over this one; the toasts start under it)
		toasts.Position = UDim2.new(0.5, 0, 0, HudBubble.chipTop(layout) + HudBubble.TouchChipHeight + 8)
	end

	-- the left menu: every tile hidden until a controller claims it
	local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Position = m.Origin,
		Size = UDim2.fromOffset(m.Width, m.Height),
	}, gui)
	-- where the TRAIN chip goes (TrainView.useHud, HudController): placeMenu below
	-- the green Shop pill: on big screens over the money (the owner's phone photo: Shop
	-- above the money, bottom-left); on phones and tablets the left column is full
	-- (tiles, the TRAIN chip, the money) and the top-right holds the tutorial bubble
	-- and the FREE SPIN chip, so it sits at the right end of the TRAIN chip's row
	local pill = if layout.Compact then HudBubble.ShopPillPhone else HudBubble.ShopPill
	local moneyTop = -coinsPanel.Position.Y.Offset + coinsPanel.Size.Y.Offset
	local shop: GuiButton? = nil
	if HudBubble.shopInRow(layout) then
		-- the round look: the red Shop button leads the top row (the reel's Shop / Spawn / Plot)
		shop = HudBubble.shopButton(topBar, HudBubble.topBarButton(layout), layout)
	elseif not round then
		shop = Pop.pill(gui, "Shop", "cart", "Green", pill, {
			Name = "ShopPill",
			AnchorPoint = if layout.Compact then Vector2.new(1, 0) else Vector2.new(0, 1),
			Position = if layout.Compact then UDim2.new(1, -18, 0, HudBubble.chipTop(layout)) else UDim2.new(0, 20, 1, -(moneyTop + 12)),
		})
	end
	if shop then
		shop:SetAttribute("Opens", "StoreController")
	end
	gui:SetAttribute("CompactHud", layout.Compact)
	gui:SetAttribute("ShortLuck", layout.Compact) -- (phones: the Server Luck line without "thanks name")
	-- Server Luck running (StoreController fills it from ServerLuckUntil): next to the pill
	Pop.text(gui, "", 22, {
		Name = "ServerLuck",
		AnchorPoint = if layout.Compact and not round then Vector2.new(1, 0) else Vector2.new(0, 1),
		-- (the round look: over the money, where the pill was)
		Position = if round
			then UDim2.new(0, 22 + layout.Inset, bottom, -(moneyTop + 8))
			elseif layout.Compact then UDim2.new(1, -18, 0, HudBubble.chipTop(layout) + pill.Y + 8)
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
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight),
		CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, menu)
	for i, entry in HudBubble.gameMenu() do
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
	HudBubble.placeMenu(gui, menu, layout)

	-- the BLASTER slot and the backpack button, centred at the bottom (Roblox's own hotbar
	-- is off: Util/Hotbar; HudController fills the button, BackpackController opens the
	-- inventory, BlasterSlotController equips the Blaster from the slot)
	local carryPanel, backpack, carryLabel, blaster = HudBubble.carryGroup(gui, layout)
	-- (phones and touch tablets: no offers: the right edge holds the tutorial bubble's SKIP and
	-- Roblox's jump button; the Store tile and the Shop button are a tap away)
	if round and not layout.Compact and not layout.Touch then
		HudBubble.offers(gui, layout)
	end

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
		BlasterSlot = blaster,
		Menu = menu,
		TopBar = topBar,
	}
end

--[[
	Puts the game menu's tiles where `layout` says and tells the TRAIN chip its
	place (gui attributes ChipTop, ChipLeft, ChipWidth, ChipStack, ChipTenFoot:
	TrainView.useHud). buildGame does it once; HudController again when the
	screen changes size (the round look's grid is fitted to it: fitRound).
]]
function HudBubble.placeMenu(gui: Instance, menu: Frame, layout: Layout)
	local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
	menu.Position = m.Origin
	menu.Size = UDim2.fromOffset(m.Width, m.Height)
	menu:SetAttribute("Columns", layout.Columns)
	local grid = menu:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(layout.Tile, m.CellHeight)
		grid.CellPadding = UDim2.fromOffset(layout.TileGap, m.RowGap)
	end
	-- (the MORE flyout opens right of the tiles)
	local flyout = gui:FindFirstChild("MoreFlyout")
	if flyout and flyout:IsA("GuiObject") then
		flyout.Position = UDim2.new(m.Origin.X.Scale, m.Origin.X.Offset + m.Width + 20, flyout.Position.Y.Scale, flyout.Position.Y.Offset)
	end
	gui:SetAttribute("ChipTop", HudBubble.chipTop(layout))
	gui:SetAttribute("ChipLeft", HudBubble.chipLeft(layout)) -- (nil: TrainView.ChipLeft)
	-- (the round look: under the tiles the chip is as wide as them, stacked on a mouse or a TV)
	gui:SetAttribute("ChipWidth", HudBubble.chipWidth(layout))
	gui:SetAttribute("ChipStack", layout.ChipStack == true)
	gui:SetAttribute("ChipTenFoot", layout.TenFoot)
	HudBubble.linkMenu(menu)
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

-- A tile's key hint: a white keycap on its top left corner ("B" on Build, "H" on Ride), made once,
-- hidden until setKeyCap.
function HudBubble.keyCap(face: GuiObject): Frame
	local existing = face:FindFirstChild("KeyCap")
	if existing and existing:IsA("Frame") then
		return existing
	end
	-- (inside the tile's corner: the left neighbour's count badge pokes over its edge)
	local cap = UIKit.new("Frame", {
		Name = "KeyCap",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 5,
		Visible = false,
	}, face)
	Bubble.corner(cap, 8)
	Bubble.stroke(cap, 2.5)
	Bubble.ink(cap, "", 17, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.DarkInk,
		ZIndex = 6,
	})
	UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Visible = false,
	}, cap)
	return cap
end

-- The tile's key: `cap` on the keycap ("B"), or the gamepad's own glyph `image`; neither hides it
-- (touch: the tile is the way).
function HudBubble.setKeyCap(face: GuiObject, cap: string?, image: string?)
	local frame = HudBubble.keyCap(face)
	local text = frame:FindFirstChild("Text") :: TextLabel
	local glyph = frame:FindFirstChild("Glyph") :: ImageLabel
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local hasImage = image ~= nil and image ~= ""
	glyph.Image = image or ""
	glyph.Visible = hasImage
	text.Text = if hasImage then "" else cap or ""
	text.Visible = not hasImage
	frame.BackgroundTransparency = if hasImage then 1 else 0
	if stroke then
		stroke.Enabled = not hasImage
	end
	frame.Visible = hasImage or (cap ~= nil and cap ~= "")
end

-- A count badge on a tile's face (0 hides it). The round look's Spin tile wears the reel's
-- tilted "FREE!" sticker while the free spin is ready (`free`: WheelController; nil: any count),
-- else the count of the bought spins held as a badge.
function HudBubble.setTileBadge(face: GuiObject, count: number, free: boolean?)
	local holder = face.Parent
	if PopTheme.round() and holder and holder.Name == "Wheel" then
		local sticker = if free == nil then count > 0 else free
		HudBubble.setSticker(face, if sticker then "FREE!" else nil)
		if sticker then
			count = 0 -- (the sticker says it: no count badge with it)
		end
	end
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
	if on then
		-- (under the top row's buttons, which may reach below the tiles' top on a tablet; over the
		-- toasts, the HUD's other pieces)
		local bar = gui:FindFirstChild("TopBar")
		local top = if menu:IsA("GuiObject") then menu.Position.Y.Offset else flyout.Position.Y.Offset
		if bar and bar:IsA("GuiObject") then
			top = math.max(top, bar.Position.Y.Offset + math.floor(bar.Size.Y.Offset * (1 - bar.AnchorPoint.Y)) + 8)
		end
		flyout.Position = UDim2.new(flyout.Position.X.Scale, flyout.Position.X.Offset, flyout.Position.Y.Scale, top)
		flyout.ZIndex = 9
	end
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
	hotbar's carried-ore squares, in the hotbar wells' pixel look (a dark
	rounded well, a black outline, a light rim lit from below, a faint
	lattice) holding the pack's picture (IconAssets "backpack"; drawn from
	frames until the sheet is uploaded) and "n / cap" in pixel letters. A
	full backpack paints the count red and shows a red FULL tag on the top
	edge (setBackpack). The key hint on the top-right corner names the open
	key (setBackpackKey: Q, the gamepad's R1 glyph, nothing on touch).
	Clicking, tapping or a gamepad's A on it opens the inventory
	(BackpackController).
	  light HUD  (carryGroup, owner 2026-10-28: "a custom slot for the
	             blaster left of the backpack, the pair in the middle")
	             Roblox's own hotbar is off (Util/Hotbar); the game's BLASTER
	             slot (blasterSlot: the same well, the blaster's picture, the
	             "1" key on the top-left corner, a gold ring while the Blaster
	             is in hand) sits left of the button, and the pair is one
	             group centred at the bottom (design units, carrySpan)
	  dark HUD   (HudView, backpackButton) the button alone, right of the
	             blaster's slot in Roblox's own hotbar (bottom centre, drawn
	             in real pixels: backpackX keeps the gap at every UI scale)
]]
HudBubble.SlotTop = Color3.fromRGB(20, 21, 27) -- the well's shadowed top inside
HudBubble.SlotBottom = Color3.fromRGB(54, 58, 72)
HudBubble.SlotRim = Color3.fromRGB(150, 160, 188)
HudBubble.BackpackSize = Vector2.new(176, 64) -- design units (PC)
HudBubble.BackpackSizePhone = Vector2.new(196, 76) -- 47 pt tall at the phones' 0.62 scale
HudBubble.BackpackBottom = 12 -- design units above the safe area's bottom edge
HudBubble.BlasterSlot = 60 -- the dark HUD: Roblox's hotbar slot in px (100 on a TV: GuiService:IsTenFootInterface)
HudBubble.BlasterGap = 16 -- the dark HUD: px between the slot's middle half and the button (its 5 px border included)
HudBubble.GroupGap = 10 -- the light HUD: design units between the BLASTER slot and the backpack button
HudBubble.WellCorner = 4 -- the round look's wells: the reel's nearly square tiles
-- the round look's wells' colours (their lip and edge): the blaster's laser blue, the pack's orange
HudBubble.WellPaints = { Blaster = "Blue", Backpack = "Ember" } :: { [string]: string }
HudBubble.EquippedColor = Color3.fromRGB(255, 203, 46) -- the slot's ring while the Blaster is in hand
HudBubble.DiscColor = Color3.fromRGB(130, 214, 255) -- the light behind the slot's blaster (a laser's cyan)
HudBubble.FullColor = Color3.fromRGB(255, 92, 84)
-- the drawn pack (no uploaded picture yet): the Rookie Pack's colours (BackpackData)
local PACK = {
	Body = Color3.fromRGB(240, 140, 58),
	Flap = Color3.fromRGB(214, 120, 48),
	Strap = Color3.fromRGB(122, 76, 44),
	Buckle = Color3.fromRGB(250, 206, 90),
}

-- The dark HUD's button: its X offset from the screen's middle (design units) at
-- `uiScale`, right of the blaster's slot, which Roblox draws in real pixels. Pure (specs).
function HudBubble.backpackX(uiScale: number, tenFoot: boolean?): number
	local slot = if tenFoot then 100 else HudBubble.BlasterSlot
	return math.ceil((slot / 2 + HudBubble.BlasterGap) / math.max(uiScale, 0.01))
end

-- The light HUD's BLASTER slot: a square as tall as the backpack button (design units).
function HudBubble.blasterSlotSize(compact: boolean): number
	return (if compact then HudBubble.BackpackSizePhone else HudBubble.BackpackSize).Y
end

-- The light HUD's bottom group: the BLASTER slot, the gap, the backpack button (design units).
function HudBubble.carryGroupSize(compact: boolean): Vector2
	local pack = if compact then HudBubble.BackpackSizePhone else HudBubble.BackpackSize
	return Vector2.new(HudBubble.blasterSlotSize(compact) + HudBubble.GroupGap + pack.X, pack.Y)
end

--[[
	What the HUD draws at the bottom centre at `uiScale`: its left and right
	edges in design units from the screen's middle. The light HUD's group
	(the BLASTER slot + the backpack button) is centred (on phones and
	tablets kept out of the thumbstick's zone: carryLeft, with the gui's
	`width` in design units); the dark HUD's backpack button sits right of
	Roblox's slot (backpackX). Both stand BackpackBottom over the bottom
	edge, carryGroupSize(...).Y tall. Pure (specs, TutorialView).
]]
function HudBubble.carrySpan(uiScale: number, tenFoot: boolean?, light: boolean, width: number?): (number, number)
	local compact = uiScale <= HudBubble.CompactScale
	if light then
		local group = HudBubble.carryGroupSize(compact).X
		local left = HudBubble.carryLeft(width, group, compact)
		return left, left + group
	end
	local pack = if compact then HudBubble.BackpackSizePhone else HudBubble.BackpackSize
	local left = HudBubble.backpackX(uiScale, tenFoot)
	return left, left + pack.X
end

-- Roblox's DynamicThumbstick starts on touches in the left 40 % of the screen (its lower two-thirds)
HudBubble.ThumbZone = 0.4

--[[
	The light HUD's bottom group's left edge from the screen's middle (design
	units): centred, but on phones and tablets (`compact`) never inside the
	thumbstick's zone (a touch on the BLASTER slot there would not walk the
	character; review 2026-10-28): the group moves right until its left edge
	is ThumbZone of the gui's `width` (design units; nil: unknown, centred).
	Its right end stays left of the touch jump button (BlasterSlot spec).
	Pure.
]]
function HudBubble.carryLeft(width: number?, groupWidth: number, compact: boolean): number
	local left = -math.floor(groupWidth / 2)
	if compact and width and width > 0 then
		left = math.max(left, math.ceil(-(0.5 - HudBubble.ThumbZone) * width))
	end
	return left
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
	A hotbar well button `name` in `parent` (the backpack button's and the
	BLASTER slot's look): a dark rounded well, a black outline, a light rim
	lit from below, a faint lattice, the press motion. `size` nil fills the
	parent.
]]
local function well(parent: Instance, name: string, size: Vector2?, paint: string?): TextButton
	local button = UIKit.new("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Size = if size then UDim2.fromOffset(size.X, size.Y) else UDim2.fromScale(1, 1),
		Selectable = true,
		ZIndex = 2,
	}, parent)
	if PopTheme.round() then
		-- the round look: the reel's dark tile, its colour in the lip and the edge (like the left tiles)
		local look = Pop.paint(paint or "Slate")
		Pop.darkTile(button, look, HudBubble.WellCorner)
		button:SetAttribute("RimColor", look.Top)
		Pop.studs(button, HudBubble.WellCorner, 0.6, nil, 3)
		Pop.fxTag(button, "Press")
		return button
	end
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
		-- (the round look: the Inventory tile's orange on the dark tile's edge)
		Color = if PopTheme.round() then Pop.paint("Ember").Top else HudBubble.SlotRim,
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
	return button
end

--[[
	A well's key hint (setBackpackKey fills it): a key cap "Key" (keyboards,
	like the TRAIN chip's T) and a gamepad glyph "Glyph", both hidden, on the
	top-right corner (`left`: the top-left).
]]
local function keyHint(button: TextButton, compact: boolean, left: boolean?)
	local keySize = if compact then 30 else 28
	local at = if left then UDim2.new(0, 8, 0, 2) else UDim2.new(1, -8, 0, 2)
	local key = Pop.text(button, "", 20, {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0,
		Position = at,
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
		Position = at,
		Size = UDim2.fromOffset(keySize, keySize),
		Visible = false,
		ZIndex = 8,
	}, button)
end

-- The backpack button itself in `holder`: the well, the pack's picture, "n / cap", FULL, the key hint.
local function packButton(holder: Instance, layout: Layout, size: Vector2, own: Vector2?): (TextButton, TextLabel)
	local button = well(holder, "Backpack", own, HudBubble.WellPaints.Backpack)
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
	keyHint(button, layout.Compact)
	return button, count
end

--[[
	The dark HUD's backpack button in `gui` (see above): returns (holder
	"Carry", the button "Backpack", its count label "Count"). `layout` picks
	the PC or the phone size; `uiScale` places it right of the blaster's slot
	in Roblox's own hotbar.
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
	local button, count = packButton(holder, layout, size, nil)
	return holder, button, count
end

--[[
	The light HUD's BLASTER slot in `parent` (owner 2026-10-28), at its
	top-left: a square well as tall as the backpack button with the
	blaster's picture (the uploaded IconAssets "blaster", else a live model:
	PictureModels "blaster" in a Pop.model view; the previews draw the
	"blaster" picture there), the "1" key cap on the top-left corner
	(setBackpackKey fills it, nothing on touch or a gamepad) and a gold ring
	with a gold rim while the Blaster is in hand (setBlasterEquipped).
	BlasterSlotController equips / puts away the Blaster from it.
]]
function HudBubble.blasterSlot(parent: Instance, layout: Layout): TextButton
	local side = HudBubble.blasterSlotSize(layout.Compact)
	local button = well(parent, "Blaster", Vector2.new(side, side), HudBubble.WellPaints.Blaster)
	-- a soft light disc behind the picture, lit from above (the blaster is dark iron:
	-- it reads on the dark well); gold while in hand (setBlasterEquipped)
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = HudBubble.DiscColor,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(side - 12, side - 12),
		ZIndex = 4,
	}, button)
	UIKit.corner(disc, side)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
	}, disc)
	-- (a bit under the middle: the 1 key cap sits on the top-left corner)
	local pic = side - 6
	local at = UDim2.new(0.5, 2, 0.5, 4)
	if IconAssets.find("blaster") ~= "" then
		local icon = UIKit.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = at,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(pic, pic),
			ZIndex = 5,
		}, button)
		IconAssets.apply(icon, "blaster")
		icon:SetAttribute("Icon", "blaster")
	else
		local model, from = PictureModels.build("blaster")
		Pop.model(button, "blaster", pic, model, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			ZIndex = 5,
		}, from)
	end
	-- in hand: a gold ring round the black outline (outside the well, so it covers nothing)
	local ring = UIKit.new("Frame", {
		Name = "Equipped",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * PopTheme.Edge, 1, 2 * PopTheme.Edge),
		Visible = false,
		ZIndex = 7,
	}, button)
	UIKit.corner(ring, (if PopTheme.round() then HudBubble.WellCorner else 14) + PopTheme.Edge)
	UIKit.new("UIStroke", {
		Name = "Gold",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = HudBubble.EquippedColor,
		Thickness = 4,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, ring)
	keyHint(button, layout.Compact, true)
	button:SetAttribute("Equipped", false)
	return button
end

-- The slot's equipped look: the gold ring and a gold rim while the Blaster is in hand.
function HudBubble.setBlasterEquipped(button: GuiObject, on: boolean)
	local ring = button:FindFirstChild("Equipped") :: GuiObject?
	if ring then
		ring.Visible = on
	end
	local disc = button:FindFirstChild("Disc") :: GuiObject?
	if disc then
		disc.BackgroundColor3 = if on then HudBubble.EquippedColor else HudBubble.DiscColor
	end
	local rim = button:FindFirstChild("Rim")
	local light = rim and rim:FindFirstChild("Light") :: UIStroke?
	if light then
		local rimColor = button:GetAttribute("RimColor") -- (the round look: the well's own colour)
		light.Color = if on then HudBubble.EquippedColor elseif typeof(rimColor) == "Color3" then rimColor else HudBubble.SlotRim
		light.Thickness = if on then 3 else 2
	end
	button:SetAttribute("Equipped", on)
end

--[[
	The light HUD's bottom group in `gui`: the BLASTER slot, a GroupGap,
	the backpack button, centred at the bottom (carrySpan). Returns (holder
	"Carry": the whole group, so whatever hides it hides both; the button
	"Backpack", its count label "Count", the slot "Blaster").
]]
function HudBubble.carryGroup(gui: Instance, layout: Layout): (Frame, TextButton, TextLabel, TextButton)
	local size = if layout.Compact then HudBubble.BackpackSizePhone else HudBubble.BackpackSize
	local group = HudBubble.carryGroupSize(layout.Compact)
	local holder = UIKit.new("Frame", {
		Name = "Carry",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, HudBubble.carryLeft(layout.Width, group.X, layout.Compact or layout.Touch), 1, -HudBubble.BackpackBottom),
		Size = UDim2.fromOffset(group.X, group.Y),
	}, gui)
	holder:SetAttribute("Group", true)
	holder:SetAttribute("ScreenWidth", layout.Width) -- (placeBackpack: until the gui has a size)
	holder:SetAttribute("Thumb", layout.Compact or layout.Touch) -- (a touch screen: the thumbstick's zone)
	local slot = HudBubble.blasterSlot(holder, layout)
	local button, count = packButton(holder, layout, size, size)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.fromScale(1, 0)
	return holder, button, count, slot
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

-- Places the "Carry" holder for a new UI scale: the light HUD's group stays centred
-- (design units); the dark HUD's button moves right of Roblox's slot (real pixels).
function HudBubble.placeBackpack(holder: GuiObject, uiScale: number, tenFoot: boolean?)
	if holder:GetAttribute("Group") then
		-- (centred; phones and tablets: out of the thumbstick's zone, carryLeft)
		local seen = 0
		local parent = holder.Parent
		if parent and parent:IsA("GuiBase2d") then
			local gui: GuiBase2d = parent
			local ok, size = pcall(function() -- (Lune's instances have no AbsoluteSize)
				return gui.AbsoluteSize
			end)
			seen = if ok and typeof(size) == "Vector2" then size.X else 0
		end
		local given = holder:GetAttribute("ScreenWidth")
		local width = if seen > 0 then seen / math.max(uiScale, 0.01) elseif type(given) == "number" then given else nil
		local thumb = uiScale <= HudBubble.CompactScale or holder:GetAttribute("Thumb") == true
		local left = HudBubble.carryLeft(width, holder.Size.X.Offset, thumb)
		holder.Position = UDim2.new(0.5, left, 1, -HudBubble.BackpackBottom)
		return
	end
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
