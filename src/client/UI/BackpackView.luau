--[[
	The backpack inventory window (owner 2026-10-24: everything you pick up
	goes into the backpack; a backpack icon next to the Blaster slot opens
	it; docs/plans/OWNER_PLAYTEST_1024.md "4 + 5"). BackpackController
	opens it from the HUD's backpack button and fills it from
	Util/BackpackState. Plain Pop window (the style chat restyles it later:
	every frame has a clear name):

	  Window      Pop.window: the blue band with the Title ("BACKPACK") and
	              the red Close X over the dark Body
	  Info        PackName (the worn pack, in its rarity colour), the fill
	              Bar (Count / Capacity; red, with FULL on it, when full)
	              and CountLabel ("12 / 30")
	  List        one Row per stack (Rows[id]): Icon (the item's live 3D
	              Picture on a light burst; dirty ore under a "?"),
	              ItemName ("Pristine Ruby"; every dirty ore merged into one
	              "Dirty Ore" row that keeps its secret, like the Sell view),
	              Grade (the chip: the grade, UNKNOWN, RELIC) and Count ("x4")
	  Empty       "Your backpack is empty..." while it holds nothing
	  Footer      ShopLine (bigger backpacks at the BACKPACKS shop in the
	              lobby) and Hint (the controls)

	  build()                       the window (hidden), laid out for 1280 x 720
	  layout(refs, w, h, compact?)  fits the window into w x h design units;
	                                compact (phones, TVs): taller rows, a
	                                thumb-sized X (>= MinTouch pt at PhoneScale)
	  entries(stacks)               pure: BackpackState stacks -> rows' data
	  setBackpack(refs, backpack)   fills everything (rows reused by id); returns
	                                the rows it made
	  setHint(refs, text)
	  firstRow(refs)                the top row (the gamepad's first selection)

	Rows are Selectable frames: a gamepad walks the list with the D-pad and
	the list scrolls along. Pure builder + layout, no services: the Lune
	previews and specs build it too.

	The round look (owner 2026-10-27, the UI pack reel's Inventory; PopTheme.
	Look = "Round"): the window is "Inventory", the Info row starts with a
	"Search..." box (it filters the stacks by name) and ends in the count
	chip, and the List is a grid of square dark cells (five a row on a PC):
	every Row keeps its frames: Grade becomes the rarity word on top in its
	colour, the Icon's picture sits in the middle, ItemName under it and
	Count ("x4") at the picture's bottom-right. Dirty ore (DirtyByOre, the
	owner's pick 2026-10-27): one stack per ore, "Dirty Ruby", its crust
	chunk with a piece of the real ore poking out (only here: the Sell view
	and the world keep the dirty secret); DirtyByOre = false brings back
	the one shared "Dirty Ore" stack. The storage keys already name the
	ore ("Raw|Ruby||"): nothing new reaches the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local BackpackData = require(Shared.Config.BackpackData)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local PopTheme = require(Shared.Config.PopTheme)
local Rarity = require(Shared.Config.Rarity)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local BackpackView = {}

type Desc = ItemData.Desc
type Stack = { Key: string, Desc: Desc, Count: number }
-- what setBackpack reads (Util/BackpackState.Backpack has these fields)
export type Backpack = {
	Equipped: string,
	Name: string,
	Count: number,
	Capacity: number,
	Full: boolean,
	Stacks: { Stack },
}

export type Entry = {
	Id: string, -- "Dirty" (every dirty ore; DirtyByOre: one per ore) or the stack's storage key
	Name: string,
	Chip: string, -- "PRISTINE", "UNKNOWN", "RELIC", "" (no chip)
	ChipColor: Color3,
	Count: number,
	Rarity: string?, -- the row's paint (nil: hidden or none)
	Dirty: boolean,
	Picture: string, -- the preview's icon name
	Desc: Desc, -- what the live picture draws
	Piece: string?, -- DirtyByOre: the ore whose piece pokes out of the dirty crust
}

export type Row = {
	Id: string,
	Frame: Frame,
	Icon: Frame,
	Mystery: TextLabel,
	ItemName: TextLabel,
	Grade: TextLabel,
	Count: TextLabel,
	Entry: Entry,
}

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Group: Frame,
	Window: Pop.Window,
	Title: TextLabel,
	Close: TextButton,
	Info: Frame,
	PackName: TextLabel,
	Bar: Frame,
	CountLabel: TextLabel,
	List: ScrollingFrame,
	Empty: TextLabel,
	Footer: Frame,
	ShopLine: TextLabel,
	Hint: TextLabel,
	Rows: { [string]: Row },
	Compact: boolean,
	Search: TextBox?, -- the round look's "Search..." box (filters the cells by name)
	Filter: string, -- what the search box holds (lower case; "" shows every stack)
}

BackpackView.Title = "BACKPACK"
BackpackView.RoundTitle = "Inventory" -- (the round look: the reel's window title)
-- the owner's pick (2026-10-27): dirty ore stacks per ore and shows a piece of its real ore;
-- false: every dirty ore in one shared "Dirty Ore" stack that keeps the secret
BackpackView.DirtyByOre = true
BackpackView.Columns = 5 -- the round look's cells a row
BackpackView.CellGap = 8
BackpackView.SearchText = "Search..."
BackpackView.Paint = "Blue" -- the band: the backpack's colour (BubbleTheme Roles.Backpack, the Ore Pen's band)
BackpackView.ShopText = "Bigger backpacks are sold at the BACKPACKS shop in the lobby."
BackpackView.EmptyText = "Your backpack is empty. Walk over ore to pick it up."
BackpackView.MaxRows = 120
BackpackView.MaxWidth = 660
BackpackView.MaxHeight = 560
BackpackView.MinTouch = 44 -- points
BackpackView.PhoneScale = 0.62 -- HudController's floor (phones)
BackpackView.DirtyColor = Color3.fromRGB(120, 112, 106)
BackpackView.RelicColor = Color3.fromRGB(146, 128, 108)
BackpackView.FullColor = Color3.fromRGB(255, 92, 84)
-- the merged Dirty Ore row's picture: a dirty chunk that never says which ore (as the Sell view's)
local DIRTY_PICTURE = "Copper"
-- the merged Dirty Ore row and the relics: a dirt brown (they never say what they hide)
BackpackView.DirtyPaint = {
	Top = Color3.fromRGB(190, 162, 132),
	Bottom = Color3.fromRGB(104, 82, 64),
	Edge = PopTheme.Outline,
} :: Pop.Paint

type Metrics = {
	Header: number,
	Pad: number,
	Info: number,
	Bar: number,
	CountWidth: number,
	Row: number,
	RowGap: number,
	Footer: number,
	Name: number,
	Chip: number,
	Count: number,
	Text: number,
	Close: number,
}

-- Sizes per layout (design units); the compact rows are at least MinTouch points tall on a phone.
local METRICS: { [string]: Metrics } = {
	Normal = {
		Header = 70,
		Pad = 14,
		Info = 44,
		Bar = 26,
		CountWidth = 132,
		Row = 72,
		RowGap = 8,
		Footer = 58,
		Name = 22,
		Chip = 14,
		Count = 28,
		Text = 17,
		Close = 56,
	},
	Compact = {
		Header = 78,
		Pad = 14,
		Info = 52,
		Bar = 30,
		CountWidth = 150,
		Row = 84,
		RowGap = 10,
		Footer = 64,
		Name = 26,
		Chip = 16,
		Count = 32,
		Text = 20,
		Close = 72,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

-- The round look's cell grid (else the pixel look's rows).
local function grid(): boolean
	return PopTheme.round()
end

-- The compact layout: touch screens, TVs, small scales and short windows (as the other panels).
function BackpackView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

---------------------------------------------------------------- pure helpers

-- "12 / 30".
function BackpackView.countText(count: number, capacity: number): string
	return `{math.max(0, math.floor(count))} / {math.max(0, math.floor(capacity))}`
end

-- The bar's fill (0..1) for count / capacity.
function BackpackView.fill(count: number, capacity: number): number
	if capacity <= 0 then
		return if count > 0 then 1 else 0
	end
	return math.clamp(count / capacity, 0, 1)
end

-- The rarity id of an ore (nil for an unknown one).
local function rarityOf(oreId: string): string?
	local ore = OreData.ById[oreId]
	return if ore and Rarity.ById[ore.Rarity] then ore.Rarity else nil
end

--[[
	Backpack stacks (BackpackState: sorted) as rows: every dirty ore in one
	"Dirty Ore" row first (its count is them all; no name, no rarity, a
	plain dirty chunk for its picture), a row per dusty relic (a dusty
	picture, no rarity: the cleaning reveals it), then one row per item in
	the stacks' order, named like the Sell view ("Pristine Ruby") with its
	grade chip. Pure.
]]
function BackpackView.entries(stacks: { Stack }): { Entry }
	local list: { Entry } = {}
	local dirty: Entry? = nil
	local dirtyStacks = 0 -- (DirtyByOre: the dirty stacks lead the list, in the stacks' order)
	for _, stack in stacks do
		local desc = stack.Desc
		if stack.Count > 0 then
			if desc.K == "Raw" and BackpackView.DirtyByOre then
				-- (the owner's pick: a stack per ore, its crust with a piece of the real ore)
				local ore = OreData.ById[desc.O]
				dirtyStacks += 1
				table.insert(list, dirtyStacks, {
					Id = stack.Key,
					Name = if ore then "Dirty " .. ore.Name else ItemData.DirtyName,
					Chip = "DIRTY",
					ChipColor = BackpackView.DirtyColor,
					Count = stack.Count,
					Rarity = rarityOf(desc.O),
					Dirty = true,
					Picture = "ore_raw",
					Desc = { K = "Raw", O = DIRTY_PICTURE },
					Piece = if ore then desc.O else nil,
				})
			elseif desc.K == "Raw" then
				local merged: Entry
				if dirty then
					merged = dirty
				else
					merged = {
						Id = "Dirty",
						Name = ItemData.DirtyName,
						Chip = "UNKNOWN",
						ChipColor = BackpackView.DirtyColor,
						Count = 0,
						Rarity = nil,
						Dirty = true,
						Picture = "ore_raw",
						Desc = { K = "Raw", O = DIRTY_PICTURE },
					}
					dirty = merged
					table.insert(list, 1, merged)
				end
				merged.Count += stack.Count
			elseif desc.K == "Relic" then
				table.insert(list, {
					Id = stack.Key,
					Name = ItemData.RelicName,
					Chip = "RELIC",
					ChipColor = BackpackView.RelicColor,
					Count = stack.Count,
					Rarity = nil,
					Dirty = false,
					Picture = if ArtifactConfig.ById[desc.O] then `artifact_{desc.O}` else "artifact",
					Desc = desc,
				})
			else
				local grade = if desc.G then ItemData.GradeById[desc.G] else nil
				table.insert(list, {
					Id = stack.Key,
					Name = ItemData.displayName(desc.K, desc.O, desc.G, desc.R),
					Chip = if grade then string.upper(grade.Name) else "",
					ChipColor = if grade then grade.Color else BackpackView.DirtyColor,
					Count = stack.Count,
					Rarity = rarityOf(desc.O),
					Dirty = false,
					Picture = `item_{desc.K}_{desc.O}`,
					Desc = desc,
				})
			end
		end
	end
	return list
end

-- The worn pack's name as the window shows it, and its rarity colour.
function BackpackView.packName(backpack: Backpack): (string, Color3)
	local pack = BackpackData.ById[backpack.Equipped]
	local rarity = if pack then Rarity.ById[pack.Rarity] else nil
	return string.upper(backpack.Name), if rarity then rarity.Color else PopTheme.Ink
end

---------------------------------------------------------------- building

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(214, 220, 232) -- quieter white text (hints)
local ROW_CORNER = 10
local SCROLLBAR = 10

-- A plain label in the Pop look: white text with a black edge (a sentence: the round font).
local function sentence(parent: Instance, text: string, size: number, props: { [string]: any }): TextLabel
	local label = Pop.text(parent, text, size, props)
	Pop.round(label, size)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

local function newRow(refs: Refs, id: string): Row
	local frame = UIKit.new("Frame", {
		Name = "Row",
		BorderSizePixel = 0,
		ClipsDescendants = true, -- (the light burst behind the picture)
		Selectable = true, -- (a gamepad walks the list: the list scrolls with the selection)
		Size = UDim2.new(1, -SCROLLBAR, 0, 72),
		ZIndex = 3,
	}, refs.List)
	frame:SetAttribute("Id", id)
	Pop.face(frame, BackpackView.DirtyPaint, ROW_CORNER)
	Pop.studs(frame, ROW_CORNER, 0.45, 40, 3)
	if grid() then
		-- (the round look: the reel's dark cell, the rarity on its inner edge)
		Pop.cellFace(frame, nil, 6)
	end
	-- the picture: a light burst and a soft glow behind the item's live 3D look
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, frame)
	if not grid() then
		Pop.rays(icon, UDim2.fromScale(0.5, 0.5), 8, 80, 0.5, 4)
	end
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = if grid() then 0.88 else 0.7,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 4,
	}, icon)
	UIKit.corner(glow, 999)
	local mystery = Pop.text(icon, "?", 40, {
		Name = "Mystery",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
	})
	local name = Pop.text(frame, "", 22, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local grade = Pop.text(frame, "", 14, {
		Name = "Grade",
		BackgroundTransparency = 0,
		BackgroundColor3 = BackpackView.DirtyColor,
		ZIndex = 5,
	})
	UIKit.corner(grade, 6)
	Pop.border(grade, 2)
	local count = Pop.text(frame, "x0", 28, {
		Name = "Count",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	})
	local row: Row = {
		Id = id,
		Frame = frame,
		Icon = icon,
		Mystery = mystery,
		ItemName = name,
		Grade = grade,
		Count = count,
		Entry = {
			Id = id,
			Name = "",
			Chip = "",
			ChipColor = BackpackView.DirtyColor,
			Count = 0,
			Rarity = nil,
			Dirty = false,
			Picture = "ore_raw",
			Desc = { K = "Raw", O = DIRTY_PICTURE },
		},
	}
	refs.Rows[id] = row
	return row
end

-- A row's sizes for the current layout.
local function placeRow(refs: Refs, row: Row)
	local m = metrics(refs.Compact)
	if grid() then
		-- a cell (its size: the list's grid): the rarity word on top, the picture, the name
		-- under it (two lines at most), the count on the picture's bottom-right corner
		local layout = refs.List:FindFirstChild("Grid") :: UIGridLayout?
		local w = if layout then layout.CellSize.X.Offset else 110
		local h = if layout then layout.CellSize.Y.Offset else 124
		row.Frame.Size = UDim2.fromOffset(w, h) -- (the grid places it; the size says what it is)
		local word = if refs.Compact then 15 else 13
		local nameSize = if refs.Compact then 15 else 13
		local nameH = nameSize * 2 + 4
		row.Grade.AnchorPoint = Vector2.new(0.5, 0)
		row.Grade.Position = UDim2.new(0.5, 0, 0, 4)
		row.Grade.Size = UDim2.new(1, -8, 0, word + 4)
		row.Grade.BackgroundTransparency = 1
		Pop.fit(row.Grade, word)
		local top = word + 8
		local pic = math.max(24, math.min(w - 14, h - top - nameH - 8))
		row.Icon.AnchorPoint = Vector2.new(0.5, 0)
		row.Icon.Position = UDim2.new(0.5, 0, 0, top)
		row.Icon.Size = UDim2.fromOffset(pic, pic)
		row.ItemName.AnchorPoint = Vector2.new(0.5, 1)
		row.ItemName.Position = UDim2.new(0.5, 0, 1, -4)
		row.ItemName.Size = UDim2.new(1, -6, 0, nameH)
		row.ItemName.TextXAlignment = Enum.TextXAlignment.Center
		row.ItemName.TextWrapped = true
		row.ItemName.TextScaled = true
		Pop.limit(row.ItemName, nameSize + 1, nameSize)
		local countH = if refs.Compact then 26 else 22
		row.Count.AnchorPoint = Vector2.new(1, 1)
		row.Count.Position = UDim2.fromOffset(w - 5, top + pic + 2)
		row.Count.Size = UDim2.fromOffset(math.floor(w * 0.6), countH)
		Pop.fit(row.Count, countH)
		return
	end
	local h = m.Row
	row.Frame.Size = UDim2.new(1, -SCROLLBAR, 0, h)
	local pic = h - 8
	row.Icon.Position = UDim2.fromOffset(4, 4)
	row.Icon.Size = UDim2.fromOffset(pic, pic)
	local textX = pic + 14
	local countW = math.floor(m.Count * 3.4)
	row.ItemName.Position = UDim2.fromOffset(textX, 6)
	row.ItemName.Size = UDim2.new(1, -(textX + countW + 12), 0, math.floor(h * 0.46))
	Pop.fit(row.ItemName, m.Name)
	local chipH = m.Chip + 10
	local chipW = math.max(4, utf8.len(row.Grade.Text) or #row.Grade.Text) * math.ceil(m.Chip * PopTheme.PixelScale) + 16
	row.Grade.Position = UDim2.fromOffset(textX, math.floor(h * 0.56))
	row.Grade.Size = UDim2.fromOffset(chipW, chipH)
	Pop.fit(row.Grade, m.Chip)
	row.Count.AnchorPoint = Vector2.new(1, 0.5)
	row.Count.Position = UDim2.new(1, -12, 0.5, 0)
	row.Count.Size = UDim2.fromOffset(countW, math.floor(h * 0.5))
	Pop.fit(row.Count, m.Count)
end

-- A row's live 3D picture (built once: a row's item never changes).
local function fillPicture(row: Row, entry: Entry)
	if row.Icon:FindFirstChild("Picture") then
		return
	end
	local ok, model = pcall(ItemBuilder.display, entry.Desc, CFrame.new(), entry.Picture)
	local piece = entry.Piece
	Pop.model(row.Icon, entry.Picture, 10, if ok then model else nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if piece then UDim2.fromScale(0.44, 0.58) else UDim2.fromScale(0.5, 0.52),
		Size = if piece then UDim2.fromScale(0.96, 0.96) else UDim2.fromScale(1.12, 1.12),
		ZIndex = 5,
	}, Vector3.new(-0.5, 0.55, -1))
	if piece then
		-- DirtyByOre: a piece of the real ore poking out of the crust's top-right
		local cleanOk, clean = pcall(ItemBuilder.display, { K = "Clean", O = piece, G = "Clean" }, CFrame.new(), "piece_" .. piece)
		local made = Pop.model(row.Icon, `item_Clean_{piece}`, 10, if cleanOk then clean else nil, {
			Name = "Piece",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.72, 0.3),
			Size = UDim2.fromScale(0.62, 0.62),
			ZIndex = 6,
		}, Vector3.new(-0.5, 0.55, -1))
		made.Rotation = 14
	end
end

local function fillRow(refs: Refs, row: Row, entry: Entry, order: number)
	row.Entry = entry
	row.Frame.LayoutOrder = order
	Pop.repaint(row.Frame, if entry.Rarity then Pop.rarityPaint(entry.Rarity) else BackpackView.DirtyPaint)
	fillPicture(row, entry)
	row.Mystery.Visible = entry.Dirty and not entry.Piece and not grid()
	row.ItemName.Text = entry.Name
	if grid() then
		-- (the reel's cell: the rarity word on top in its colour; a dirty or dusty one says so)
		local info = if entry.Rarity then Rarity.ById[entry.Rarity] else nil
		row.Grade.Text = if info then info.Name elseif entry.Dirty then "Dirty" elseif entry.Chip == "RELIC" then "Relic" else ""
		row.Grade.TextColor3 = if info then info.Color:Lerp(Color3.new(1, 1, 1), 0.2) else BackpackView.DirtyPaint.Top
		row.Grade.Visible = row.Grade.Text ~= ""
	else
		row.Grade.Text = entry.Chip
		row.Grade.BackgroundColor3 = entry.ChipColor
		row.Grade.Visible = entry.Chip ~= ""
	end
	row.Count.Text = `x{entry.Count}`
	row.Frame.Visible = refs.Filter == "" or string.find(string.lower(entry.Name), refs.Filter, 1, true) ~= nil
	placeRow(refs, row)
end

-- The round look's search: only the stacks whose name holds `text` show ("" shows them all).
function BackpackView.setSearch(refs: Refs, text: string)
	refs.Filter = string.lower(text)
	for _, row in refs.Rows do
		row.Frame.Visible = refs.Filter == "" or string.find(string.lower(row.Entry.Name), refs.Filter, 1, true) ~= nil
	end
end

function BackpackView.build(): Refs
	local gui = UIKit.screen("TerraForgeBackpack", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	-- the window sits in a full-screen holder whose UIScale fits it to small screens
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local group = UIKit.new("Frame", {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BackpackView.MaxWidth, BackpackView.MaxHeight),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, holder)
	local m = metrics(false)
	local window = Pop.window(
		group,
		if grid() then BackpackView.RoundTitle else BackpackView.Title,
		Vector2.new(BackpackView.MaxWidth, BackpackView.MaxHeight),
		m.Header,
		BackpackView.Paint
	)
	window.Root.AnchorPoint = Vector2.new(0, 0)
	window.Root.Position = UDim2.fromOffset(0, 0)
	local body = window.Body

	-- the worn pack and how full it is
	local info = UIKit.new("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, body)
	local packName = Pop.text(info, "", 22, {
		Name = "PackName",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local bar = Pop.bar(info, 0, "Green", Vector2.new(200, m.Bar), "", {
		AnchorPoint = Vector2.new(0, 0.5),
	})
	local countLabel = Pop.text(info, BackpackView.countText(0, 0), 26, {
		Name = "CountLabel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	-- the round look: the reel's "Search..." box at the row's left (it filters the cells by
	-- name), the count in a chip at its right
	local search: TextBox? = nil
	if grid() then
		local box = UIKit.new("TextBox", {
			Name = "Search",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(14, 16, 22),
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			FontFace = PopTheme.Pixel,
			PlaceholderColor3 = Color3.fromRGB(226, 230, 238),
			PlaceholderText = BackpackView.SearchText,
			Position = UDim2.fromScale(0, 0.5),
			Text = "",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, info)
		UIKit.corner(box, 6)
		Pop.border(box, 2)
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, box)
		search = box
		countLabel.BackgroundColor3 = Color3.fromRGB(150, 74, 24)
		countLabel.BackgroundTransparency = 0
		UIKit.corner(countLabel, 6)
		Pop.border(countLabel, 2)
		countLabel.TextXAlignment = Enum.TextXAlignment.Center
	end

	-- the stacks
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		ZIndex = 2,
	}, body)
	if grid() then
		-- (the round look: the reel's grid of square cells; layout sizes them)
		UIKit.new("UIGridLayout", {
			Name = "Grid",
			CellPadding = UDim2.fromOffset(BackpackView.CellGap, BackpackView.CellGap),
			CellSize = UDim2.fromOffset(110, 124),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, list)
	else
		UIKit.new("UIListLayout", {
			Name = "Layout",
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, m.RowGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, list)
	end
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }, list)
	local empty = sentence(body, BackpackView.EmptyText, 20, {
		Name = "Empty",
		TextWrapped = true,
		Visible = false,
		ZIndex = 3,
	})
	empty.TextColor3 = SOFT

	-- where bigger packs are, and the controls
	local footer = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, body)
	local shopLine = sentence(footer, BackpackView.ShopText, 18, {
		Name = "ShopLine",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0.55, 0),
		TextColor3 = PopTheme.Titles.Gold[1],
		ZIndex = 3,
	})
	local hint = sentence(footer, "", 16, {
		Name = "Hint",
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.new(1, 0, 0.45, 0),
		ZIndex = 3,
	})
	hint.TextColor3 = SOFT

	local refs: Refs = {
		Gui = gui,
		Dim = dim,
		Group = group,
		Window = window,
		Title = window.Title,
		Close = window.Close,
		Info = info,
		PackName = packName,
		Bar = bar,
		CountLabel = countLabel,
		List = list,
		Empty = empty,
		Footer = footer,
		ShopLine = shopLine,
		Hint = hint,
		Rows = {},
		Compact = false,
		Search = search,
		Filter = "",
	}
	if search then
		pcall(function() -- (the game only: the Lune previews have no signals)
			search:GetPropertyChangedSignal("Text"):Connect(function()
				BackpackView.setSearch(refs, search.Text)
			end)
		end)
	end
	BackpackView.layout(refs, 1280, 720, false)
	return refs
end

---------------------------------------------------------------- layout

-- The window's design size and the fit scale for a w x h design-unit screen.
function BackpackView.windowSize(w: number, h: number, compact: boolean): (Vector2, number)
	local m = metrics(compact)
	local maxWidth = if compact then BackpackView.MaxWidth + 80 else BackpackView.MaxWidth
	-- the least height: the band, the info row, two rows and the footer
	local minHeight = m.Header + 4 + m.Pad * 3 + m.Info + 2 * m.Row + m.RowGap + m.Footer
	local width = math.max(420, math.min(maxWidth, w - 40))
	local height = math.max(minHeight, math.min(BackpackView.MaxHeight, h - 40))
	local fit = math.min(1, (w - 16) / width, (h - 16) / height)
	return Vector2.new(math.floor(width), math.floor(height)), fit
end

function BackpackView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local isCompact = compact == true
	refs.Compact = isCompact
	local m = metrics(isCompact)
	local size, fit = BackpackView.windowSize(w, h, isCompact)
	local window = refs.Window
	window.Root.Size = UDim2.fromOffset(size.X, size.Y)
	refs.Group.Size = UDim2.fromOffset(size.X, size.Y)
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	-- the band and the X (compact: the X keeps a thumb-sized target through the fit shrink)
	window.Body.Position = UDim2.fromOffset(4, m.Header)
	window.Body.Size = UDim2.new(1, -8, 1, -(m.Header + 4))
	window.Header.Size = UDim2.new(1, -8, 0, m.Header - 8)
	local k = if isCompact then 1 / math.max(fit, 0.5) else 1
	local close = math.floor(m.Close * k)
	window.Close.Size = UDim2.fromOffset(close, close)
	window.Close.Position = UDim2.new(1, -10, 0, math.floor(m.Header / 2))
	local closeLabel = window.Close:FindFirstChild("Label") :: TextLabel?
	if closeLabel then
		closeLabel.TextSize = math.floor(close * 0.66)
	end
	window.Title.Size = UDim2.new(1, -(close + 40), 1, -4)
	-- the body: info, list, footer
	local bodyW = size.X - 8
	local bodyH = size.Y - m.Header - 4
	local innerW = bodyW - 2 * m.Pad
	refs.Info.Position = UDim2.fromOffset(m.Pad, m.Pad)
	refs.Info.Size = UDim2.fromOffset(innerW, m.Info)
	local search = refs.Search
	-- (the round look: the search box first, then the pack's name, its bar and the count chip)
	local searchW = if search then math.floor(innerW * 0.34) else 0
	if search then
		search.Size = UDim2.fromOffset(searchW, m.Info - 8)
		search.TextSize = m.Text + 2
	end
	local nameX = if search then searchW + 10 else 0
	local nameW = if search then math.floor(innerW * 0.2) else math.floor(innerW * 0.36)
	refs.PackName.Position = UDim2.new(0, nameX, 0.5, 0)
	refs.PackName.Size = UDim2.fromOffset(nameW, m.Info)
	Pop.fit(refs.PackName, if search then m.Name - 4 else m.Name)
	refs.CountLabel.Size = UDim2.fromOffset(m.CountWidth, if search then m.Info - 8 else m.Info)
	Pop.fit(refs.CountLabel, if search then m.Count - 6 else m.Count)
	local barX = nameX + nameW + 10
	local barW = math.max(60, innerW - barX - m.CountWidth - 10)
	refs.Bar.Position = UDim2.new(0, barX, 0.5, 0)
	refs.Bar.Size = UDim2.fromOffset(barW, m.Bar)
	local barLabel = refs.Bar:FindFirstChild("Label") :: TextLabel?
	if barLabel then
		Pop.fit(barLabel, math.floor(m.Bar * 0.9))
	end
	local listTop = m.Pad * 2 + m.Info
	local listH = bodyH - listTop - m.Footer - m.Pad
	refs.List.Position = UDim2.fromOffset(m.Pad, listTop)
	refs.List.Size = UDim2.fromOffset(innerW, math.max(m.Row, listH))
	local layout = refs.List:FindFirstChild("Layout") :: UIListLayout?
	if layout then
		layout.Padding = UDim.new(0, m.RowGap)
	end
	local cells = refs.List:FindFirstChild("Grid") :: UIGridLayout?
	if cells then
		-- the round look's cells: Columns a row, square-ish, at least a thumb on a phone
		-- (MinTouch points through the fit shrink)
		local gap = BackpackView.CellGap
		local columns = BackpackView.Columns
		local cellW = math.floor((innerW - SCROLLBAR - (columns - 1) * gap) / columns)
		local least = if isCompact then math.ceil(BackpackView.MinTouch / (BackpackView.PhoneScale * math.max(fit, 0.3))) else 0
		cellW = math.max(cellW, least)
		cells.CellSize = UDim2.fromOffset(cellW, math.max(least, math.floor(cellW * 1.1)))
		cells.CellPadding = UDim2.fromOffset(gap, gap)
	end
	refs.Empty.Position = UDim2.fromOffset(m.Pad + 10, listTop + 10)
	refs.Empty.Size = UDim2.fromOffset(innerW - 20, math.min(listH, 80))
	refs.Empty.TextSize = m.Text + 2
	refs.Footer.Position = UDim2.new(0, m.Pad, 1, -math.floor(m.Pad / 2))
	refs.Footer.Size = UDim2.fromOffset(innerW, m.Footer)
	refs.ShopLine.TextSize = m.Text
	refs.Hint.TextSize = m.Text - 2
	for _, row in refs.Rows do
		placeRow(refs, row)
	end
end

-- The fit scale the layout chose (the FitScale UIScale).
function BackpackView.fitScale(refs: Refs): number
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	return if scale and scale:IsA("UIScale") then scale.Scale else 1
end

---------------------------------------------------------------- filling in

--[[
	Shows a backpack: the worn pack's name, the bar and the count (red, the
	bar red with FULL on it, when full), one row per entry (at most MaxRows;
	rows are reused by id, gone ones removed) and the empty line. Returns
	the rows it just made.
]]
function BackpackView.setBackpack(refs: Refs, backpack: Backpack): { Row }
	local name, color = BackpackView.packName(backpack)
	refs.PackName.Text = name
	refs.PackName.TextColor3 = color
	local full = backpack.Full
	Pop.setBar(refs.Bar, BackpackView.fill(backpack.Count, backpack.Capacity), if full then "FULL" else "")
	local fill = refs.Bar:FindFirstChild("Fill") :: Frame?
	if fill then
		Pop.repaint(fill, if full then "Red" else "Green", true)
	end
	refs.CountLabel.Text = BackpackView.countText(backpack.Count, backpack.Capacity)
	refs.CountLabel.TextColor3 = if full then BackpackView.FullColor else PopTheme.Ink
	refs.Gui:SetAttribute("Full", full)

	local created: { Row } = {}
	local keep: { [string]: boolean } = {}
	for index, entry in BackpackView.entries(backpack.Stacks) do
		if index > BackpackView.MaxRows then
			break
		end
		keep[entry.Id] = true
		local existing = refs.Rows[entry.Id]
		local row: Row
		if existing then
			row = existing
		else
			row = newRow(refs, entry.Id)
			table.insert(created, row)
		end
		fillRow(refs, row, entry, index)
	end
	for id, row in refs.Rows do
		if not keep[id] then
			row.Frame:Destroy()
			refs.Rows[id] = nil
		end
	end
	refs.Empty.Visible = next(refs.Rows) == nil
	return created
end

function BackpackView.setHint(refs: Refs, text: string)
	refs.Hint.Text = text
end

-- The top row (the gamepad's first selection), nil while empty.
function BackpackView.firstRow(refs: Refs): Row?
	local best: Row? = nil
	for _, row in refs.Rows do
		if not best or row.Frame.LayoutOrder < best.Frame.LayoutOrder then
			best = row
		end
	end
	return best
end

-- The rows in list order (tests, the controller's selection).
function BackpackView.rows(refs: Refs): { Row }
	local list: { Row } = {}
	for _, row in refs.Rows do
		table.insert(list, row)
	end
	table.sort(list, function(a: Row, b: Row): boolean
		return a.Frame.LayoutOrder < b.Frame.LayoutOrder
	end)
	return list
end

return BackpackView
