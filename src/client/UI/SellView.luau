--[[
	Tobin's Sell view (pure builder + pure helpers; SellController fills it in).

	  header    TOBIN'S ORE STALL, a short line about prices (or the last
	            sale: HUD toasts are hidden behind the panel), X button
	  list      "IN YOUR PEN" and "IN YOUR HANDS": one row per storage key
	            (all Dirty Ore of a section merged into one row, grey "?"
	            icon, price "?"): ore-colour icon, name, grade chip, count,
	            Tobin's price each, "Sell 1" and "Sell all"
	  footer    "Sell all Dirty Ore", "Sell all but best 4", control hint
	  confirm   a dim layer with "Sell N items for $X?" and Sell / Cancel

	Designed for 720 design units of height (HudController.uiScale); the
	compact layout (phones) has bigger rows and buttons so touch targets stay
	about 44 pt at the smallest scale. The panel fits the space it gets
	(SellView.layout). Helpers: entries (a State summary as rows), plan
	(what a Sell-all button would sell, the same rules as SellService),
	needsConfirm and the confirm texts.

	The look is the Robux Shop's Pop kit (owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"; Pop.luau, PopTheme): a black
	frame, the green header band (the stall's colour, LightSkin.BandRoles
	"Shop") with shine stripes and studs, white chunky titles with a drop
	shadow, a dark studded body, one row per item painted in its rarity
	colour with the item's live 3D picture (ItemBuilder.display in a
	ViewportFrame; Dirty Ore: a dirty chunk under a "?") on a light burst,
	prices in big green money text, big green SELL buttons and the red X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

local SellView = {}

export type Section = "Pen" | "Hands"

export type Entry = {
	Id: string, -- "Pen/<key>" or "Pen/Dirty"
	Section: Section,
	Keys: { [string]: number }, -- storage keys in this row -> count
	Name: string,
	Count: number,
	Price: number?, -- coins per item with the sell bonus, as Tobin pays it (nil = unknown: Dirty Ore)
	Base: number?, -- coins per item before the sell bonus
	Mult: number, -- the sell bonus (State.Bonuses.SellMult) the prices use
	Color: Color3, -- icon colour
	Edge: Color3, -- icon outline (rarity colour, grey for Dirty Ore)
	ChipText: string?,
	ChipColor: Color3?,
	RarityOrder: number, -- 0 for Dirty Ore (hidden)
	Dirty: boolean,
}

export type Row = {
	Id: string,
	Frame: Frame,
	Icon: Frame,
	IconText: TextLabel,
	Name: TextLabel,
	Chip: TextLabel,
	Count: TextLabel,
	Price: TextLabel,
	Each: TextLabel,
	SellOne: TextButton,
	SellAll: TextButton,
	Entry: Entry,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Receipt: TextLabel, -- the last sale / message (toasts hide behind the panel)
	Close: TextButton,
	List: ScrollingFrame,
	Headers: { [Section]: TextLabel },
	Empty: { [Section]: TextLabel },
	Rows: { [string]: Row },
	Footer: Frame,
	SellDirty: TextButton,
	SellRest: TextButton,
	Hint: TextLabel,
	Confirm: TextButton, -- the dim layer (clicking it cancels)
	ConfirmBox: Frame,
	ConfirmText: TextLabel,
	ConfirmYes: TextButton,
	ConfirmNo: TextButton,
	Compact: boolean,
}

export type Plan = {
	Count: number, -- items one request would sell (at most MaxPerRequest)
	Eligible: number, -- items the filter matches in total
	Total: number, -- coins for the known items in Count
	Dirty: number, -- Dirty Ore among Count (price unknown)
	BestOrder: number, -- rarest known item sold (Rarity order, 0 = none)
	Kept: number, -- clean ores kept by "AllButBest"
}

-- one item in a plan
type Unit = { Section: Section, Desc: ItemData.Desc, Income: number, Price: number }

-- A sell bonus from State.Bonuses.SellMult (anything broken = 1).
local function cleanMult(mult: any): number
	return if type(mult) == "number" and mult == mult and mult >= 1 and mult < math.huge then mult else 1
end

-- Coins Tobin pays for items whose base price adds up to `base` with the sell
-- bonus `mult`: rounded once, like Bonuses.sellAmount on the server.
function SellView.withBonus(base: number, mult: number): number
	return math.floor(base * cleanMult(mult) + 0.5)
end

SellView.MaxRows = 120 -- per section
SellView.ConfirmCount = 10 -- selling more than this asks first
SellView.ConfirmRarity = 4 -- ...and so does anything Epic or rarer
SellView.KeepBest = 4 -- must match SellService.KeepBest
SellView.DirtyColor = Color3.fromRGB(120, 112, 106)

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Footer: number,
	Row: number,
	Button: number,
	SellOne: number,
	SellAll: number,
	PriceWidth: number,
	Title: number,
	Text: number,
	Band: number, -- the header band's height (the title and the X sit in it)
	Close: number,
}

local PAD = 16
local SCROLLBAR = 10

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 720,
		Height = 580,
		Header = 96, -- the band, then the line under it (the subtitle or the last sale)
		Footer = 100,
		Row = 70,
		Button = 54,
		SellOne = 96,
		SellAll = 108,
		PriceWidth = 104,
		Title = 34,
		Text = 20,
		Band = 64,
		Close = 50,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 900,
		Height = 560,
		Header = 84, -- the band (the last sale sits next to the title)
		Footer = 106,
		Row = 86,
		Button = 72,
		SellOne = 110,
		SellAll = 124,
		PriceWidth = 112,
		Title = 30,
		Text = 22,
		Band = 78,
		Close = 64,
	},
}

local SECTION_ORDER: { [Section]: number } = { Pen = 0, Hands = 2000 }
local SECTION_TITLE: { [Section]: string } = { Pen = "IN YOUR ORE PEN", Hands = "IN YOUR HANDS" }
local SECTION_EMPTY: { [Section]: string } = {
	Pen = "Your Ore Pen is empty.",
	Hands = "You're not carrying anything. Carry ore here or throw it into the SELL bin.",
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

function SellView.priceText(price: number?): string
	if price == nil then
		return "?"
	end
	return Format.money(price)
end

local function rarityOf(oreId: string): (number, Color3)
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	if info then
		return info.Order, info.Color
	end
	return 0, Theme.TextDim
end

--[[
	A State summary (storage key -> count) as rows: junk keys and zero counts
	are skipped, all Dirty Ore is one row (first), the rest by price, then name.
	`sellMult` (State.Bonuses.SellMult, nil = 1): the prices are what Tobin
	really pays with the player's sell bonus.
]]
function SellView.entries(summary: any, section: Section, sellMult: number?): { Entry }
	local list: { Entry } = {}
	local mult = cleanMult(sellMult)
	if type(summary) ~= "table" then
		return list
	end
	local dirty: Entry? = nil
	for key, rawCount in summary do
		local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
		local count = if type(rawCount) == "number" and rawCount == rawCount then math.floor(rawCount) else 0
		if desc and count >= 1 then
			if desc.K == "Raw" then
				local row = dirty
				if not row then
					row = {
						Id = section .. "/Dirty",
						Section = section,
						Keys = {},
						Name = ItemData.DirtyName,
						Count = 0,
						Price = nil,
						Mult = mult,
						Color = SellView.DirtyColor,
						Edge = Theme.TextDim,
						ChipText = "Unknown",
						ChipColor = SellView.DirtyColor,
						RarityOrder = 0,
						Dirty = true,
					}
					dirty = row
				end
				local merged = row :: Entry
				merged.Keys[key] = count
				merged.Count += count
			else
				local order, edge = rarityOf(desc.O)
				local ore = OreData.ById[desc.O]
				local grade = desc.G and ItemData.GradeById[desc.G]
				local base = ItemData.value(desc.K, desc.O, desc.G, desc.R)
				table.insert(list, {
					Id = section .. "/" .. key,
					Section = section,
					Keys = { [key] = count },
					Name = ItemData.displayName(desc.K, desc.O, desc.G, desc.R),
					Count = count,
					Price = SellView.withBonus(base, mult),
					Base = base,
					Mult = mult,
					Color = if ore then ore.Color else Theme.TextDim,
					Edge = edge,
					ChipText = if grade then grade.Name else nil,
					ChipColor = if grade then grade.Color else nil,
					RarityOrder = order,
					Dirty = false,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.Price or 0, b.Price or 0
		if pa ~= pb then
			return pa > pb
		elseif a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.Id < b.Id
	end)
	if dirty then
		table.insert(list, 1, dirty)
	end
	return list
end

-- The key a "Sell 1" on this row sells: any of its keys, picked by `roll`
-- in 0..1 weighted by count (Dirty Ore: a random one of the dirty chunks).
function SellView.pickKey(entry: Entry, roll: number): string?
	local keys = {}
	for key in entry.Keys do
		table.insert(keys, key)
	end
	table.sort(keys)
	local total = 0
	for _, key in keys do
		total += entry.Keys[key]
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	for _, key in keys do
		target -= entry.Keys[key]
		if target < 0 then
			return key
		end
	end
	return keys[#keys]
end

--[[
	What SellAll { Filter, From? } would sell from these summaries, with the
	server's rules: "Dirty" = all Dirty Ore; "AllButBest" = everything else
	except the KeepBest cleaned ores with the highest income. Hands first,
	at most EconomyConfig.Sell.MaxPerRequest items. Total includes the sell
	bonus `sellMult` (nil = 1), rounded once like SellService.
]]
function SellView.plan(pen: any, hands: any, filter: string, from: Section?, sellMult: number?): Plan
	local units: { Unit } = {}
	local function add(summary: any, section: Section)
		if type(summary) ~= "table" then
			return
		end
		local keys = {}
		for key in summary do
			if type(key) == "string" then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		for _, key in keys do
			local desc = ItemData.parseKey(key)
			local raw = summary[key]
			local count = if type(raw) == "number" and raw == raw then math.floor(math.min(raw, 1000)) else 0
			if desc then
				for _ = 1, count do
					table.insert(units, {
						Section = section,
						Desc = desc,
						Income = ItemData.income(desc),
						Price = ItemData.value(desc.K, desc.O, desc.G, desc.R),
					})
				end
			end
		end
	end
	add(hands, "Hands")
	add(pen, "Pen")

	local kept: { [Unit]: boolean } = {}
	local keptCount = 0
	if filter == "AllButBest" then
		local clean: { Unit } = {}
		for _, unit in units do
			if unit.Income > 0 then
				table.insert(clean, unit)
			end
		end
		table.sort(clean, function(a, b)
			if a.Income ~= b.Income then
				return a.Income > b.Income
			end
			return a.Section == "Pen" and b.Section ~= "Pen"
		end)
		for i = 1, math.min(SellView.KeepBest, #clean) do
			kept[clean[i]] = true
			keptCount += 1
		end
	end

	local plan: Plan = { Count = 0, Eligible = 0, Total = 0, Dirty = 0, BestOrder = 0, Kept = keptCount }
	for _, unit in units do
		local dirty = unit.Desc.K == "Raw"
		local wanted = (from == nil or unit.Section == from)
			and (if filter == "Dirty" then dirty elseif filter == "AllButBest" then not dirty and not kept[unit] else false)
		if wanted then
			plan.Eligible += 1
			if plan.Count < EconomyConfig.Sell.MaxPerRequest then
				plan.Count += 1
				if dirty then
					plan.Dirty += 1
				else
					plan.Total += unit.Price
					plan.BestOrder = math.max(plan.BestOrder, (rarityOf(unit.Desc.O)))
				end
			end
		end
	end
	plan.Total = SellView.withBonus(plan.Total, cleanMult(sellMult))
	return plan
end

-- Selling this many items (rarest known one: `rarityOrder`) asks first.
function SellView.needsConfirm(count: number, rarityOrder: number): boolean
	return count > SellView.ConfirmCount or rarityOrder >= SellView.ConfirmRarity
end

local function itemsText(count: number): string
	return if count == 1 then "1 item" else `{Format.commas(count)} items`
end

-- "Sell 12 Clean Gold for $4.5K?" / "Sell 14 Dirty Ore?" (one row).
function SellView.confirmRowText(entry: Entry, count: number): string
	if entry.Dirty then
		return `Sell {Format.commas(count)} {ItemData.DirtyName}? Tobin pays the raw price, and then you'll see what it was.`
	end
	local price = SellView.withBonus((entry.Base or entry.Price or 0) * count, entry.Mult)
	local rarity = ""
	if entry.RarityOrder >= SellView.ConfirmRarity then
		local info = Rarity.List[entry.RarityOrder]
		rarity = if info then ` ({info.Name})` else ""
	end
	return `Sell {Format.commas(count)} {entry.Name}{rarity} for {Format.money(price)}?`
end

-- Text for a Sell-all button's confirm step.
function SellView.confirmPlanText(plan: Plan, filter: string): string
	local capped = if plan.Eligible > plan.Count
		then ` Tobin buys {EconomyConfig.Sell.MaxPerRequest} at a time ({Format.commas(plan.Eligible)} in total).`
		else ""
	if filter == "Dirty" then
		return `Sell {Format.commas(plan.Count)} {ItemData.DirtyName}? Tobin pays the raw price, and then you'll see what it was.{capped}`
	end
	local price = if capped == "" then ` for {Format.money(plan.Total)}` else ""
	return `Sell {itemsText(plan.Count)}{price}? You keep your {SellView.KeepBest} best clean ores and your {ItemData.DirtyName}.{capped}`
end

---------------------------------------------------------------- the Pop look (the kit pieces this window needs)

SellView.Paint = "Green" -- the header band: the stall's colour (LightSkin.BandRoles TerraForgeSell = "Shop")
-- the Dirty Ore row: a dirt brown (it never says which ore it is)
SellView.DirtyPaint = {
	Top = Color3.fromRGB(190, 162, 132),
	Bottom = Color3.fromRGB(104, 82, 64),
	Edge = PopTheme.Outline,
} :: Pop.Paint

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(214, 220, 232) -- quieter white text (hints, "each")
local ROW_CORNER = 10
local HOLDER_KEYS = { Size = true, Position = true, AnchorPoint = true, LayoutOrder = true, Visible = true }

-- A chip's colour from a grade colour: a shade deeper, so its white word reads.
local function chipColor(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.14)
end

-- A text's black edge (its Contextual UIStroke, made when missing).
local function edgeOf(label: GuiObject): UIStroke
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return Pop.edge(label)
end

-- White chunky text with a black edge (a UIKit label or button), or `color`.
local function ink(label: GuiObject, color: Color3?, font: Font?)
	local text: any = label
	text.FontFace = font or PopTheme.Font
	text.TextColor3 = color or PopTheme.Ink
	local edge = edgeOf(label)
	edge.Color = PopTheme.Outline
	edge.Thickness = Pop.edgeFor(text.TextSize)
	edge.Transparency = 0
	edge.LineJoinMode = Enum.LineJoinMode.Round
end

-- Drops a frame's border strokes (a UIKit stroke), so Pop.face draws its own.
local function dropBorders(frame: GuiObject)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child:Destroy()
		end
	end
end

--[[
	A Pop button that keeps UIKit.button's shape: the returned TextButton
	(clear, its own word: controllers and views set its Text, TextSize and
	TextTransparency) fills its holder, and the holder is the painted face
	(Pop.face: the glossy paint, the black border, the light rim, studs).
	(A UIGradient on the button itself would tint its word too.) Size /
	Position / AnchorPoint / LayoutOrder / Visible go on the holder (layouts
	move it), the rest on the button. paintButton recolours the face.
]]
local HOVER = Color3.fromRGB(236, 236, 236)
local PRESS = Color3.fromRGB(200, 200, 200)

local function popButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local name = if props and type(props.Name) == "string" then props.Name else text
	local face = UIKit.new("Frame", {
		Name = name .. "Holder",
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 4,
	}, parent)
	Pop.face(face, paint)
	Pop.studs(face, PopTheme.Corner, 0.45, 28, 4)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		FontFace = PopTheme.Font,
		TextColor3 = PopTheme.Ink,
		TextSize = 22,
		Selectable = true,
		ZIndex = 5,
	}, face)
	Pop.edge(button, 2.5)
	if props then
		for key, value in props do
			local target: any = if HOLDER_KEYS[key] then face else button
			if key ~= "Name" then
				target[key] = value
			end
		end
	end
	-- hover / press darken the face (AutoButtonColor would only darken the clear button)
	pcall(function()
		local b: any = button
		b:GetPropertyChangedSignal("GuiState"):Connect(function()
			local state = b.GuiState
			face.BackgroundColor3 = if state == Enum.GuiState.Press then PRESS elseif state == Enum.GuiState.Hover then HOVER else WHITE
		end)
	end)
	return button
end

-- Recolours a popButton's face.
local function paintButton(button: TextButton, paint: string | Pop.Paint)
	local face = button.Parent
	if face and face:IsA("GuiObject") then
		Pop.repaint(face, paint)
	end
end

-- A small round chip (a UIKit.chip): one bright colour (a gradient would tint its word), a black border, white text.
local function popChip(chip: TextLabel, color: Color3)
	dropBorders(chip)
	chip.BackgroundColor3 = color
	chip.BackgroundTransparency = 0
	Pop.border(chip, 2)
	ink(chip)
end

--[[
	The window's chrome on an old panel: the black frame, a dark studded
	body and the bright header band (shine stripes, studs); both sit under
	everything else (ZIndex 0). setBand sizes them for a band `band` tall.
]]
local function chrome(panel: Frame, paint: string | Pop.Paint)
	panel.BackgroundColor3 = PopTheme.Outline
	local old = panel:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = PopTheme.Outline
		stroke.Thickness = 4
	end
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, panel)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	Pop.studs(body, 4, 0.5, 36, 0)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 0,
	}, body)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	local head = UIKit.new("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		ClipsDescendants = true,
		ZIndex = 0,
	}, panel)
	Pop.face(head, paint, 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = 3
	Pop.studs(head, 4, 0.35, 40, 0)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 0,
	}, head)
	for i, s in { { 0.62, 46 }, { 0.7, 22 }, { 0.8, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = 0,
		}, head)
	end
end

-- Sizes the header band (`band` units tall, the frame included) and the body under it.
local function setBand(panel: Frame, band: number)
	local head = panel:FindFirstChild("Header") :: Frame?
	local body = panel:FindFirstChild("Body") :: Frame?
	if head and body then
		head.Size = UDim2.new(1, -8, 0, band - 8)
		body.Position = UDim2.fromOffset(4, band)
		body.Size = UDim2.new(1, -8, 1, -(band + 4))
	end
end

-- The title's 3D drop shadow (Pop.shadow), kept on the title as layouts move it.
local function syncShadow(title: TextLabel)
	local parent = title.Parent
	local found = if parent then parent:FindFirstChild(title.Name .. "Shadow") else nil
	local shade: TextLabel = if found and found:IsA("TextLabel") then found else Pop.shadow(title)
	shade.Position = title.Position + UDim2.fromOffset(0, 4)
	shade.Size = title.Size
	shade.AnchorPoint = title.AnchorPoint
	shade.Text = title.Text
	shade.TextSize = title.TextSize
	shade.TextXAlignment = title.TextXAlignment
	shade.Visible = title.Visible
	shade.ZIndex = math.max(1, title.ZIndex - 1)
end

-- The paint of a row: its rarity's (Pop.rarityPaint); Dirty Ore a dirt brown.
function SellView.rowPaint(entry: Entry): Pop.Paint
	if entry.Dirty then
		return SellView.DirtyPaint
	end
	local info = Rarity.List[entry.RarityOrder]
	return Pop.rarityPaint(if info then info.Id else nil)
end

--[[
	The item a row shows: its picture name (the preview's icon) and the
	description ItemBuilder.display draws, from the row's first storage
	key. Dirty Ore: a dirty chunk that never tells which ore it is.
]]
function SellView.pictureOf(entry: Entry): (string, ItemData.Desc)
	local dirty: ItemData.Desc = { K = "Raw", O = "Copper" }
	if entry.Dirty then
		return "ore_raw", dirty
	end
	local key = next(entry.Keys)
	local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
	if not desc then
		return "ore_raw", dirty
	end
	return `item_{desc.K}_{desc.O}`, desc
end

-- A row's live 3D picture (built once: a row's item never changes).
local function fillPicture(icon: Frame, entry: Entry)
	if icon:FindFirstChild("Picture") then
		return
	end
	local name, desc = SellView.pictureOf(entry)
	local ok, model = pcall(ItemBuilder.display, desc, CFrame.new(), name)
	Pop.model(icon, name, 10, if ok then model else nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(1.12, 1.12),
		ZIndex = 3,
	}, Vector3.new(-0.5, 0.55, -1))
end

---------------------------------------------------------------- building

local function sectionHeader(list: ScrollingFrame, section: Section): TextLabel
	local header = UIKit.label(list, SECTION_TITLE[section], 22, {
		Name = section .. "Header",
		LayoutOrder = SECTION_ORDER[section],
		Size = UDim2.new(1, -SCROLLBAR, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = false,
	})
	ink(header, WHITE, PopTheme.Heavy)
	local gold = PopTheme.Titles.Gold
	UIKit.new("UIGradient", { Color = ColorSequence.new(gold[1], gold[#gold]), Rotation = 90 }, header)
	return header
end

local function emptyLabel(list: ScrollingFrame, section: Section): TextLabel
	local label = UIKit.label(list, SECTION_EMPTY[section], 17, {
		Name = section .. "Empty",
		LayoutOrder = SECTION_ORDER[section] + 1000,
		Size = UDim2.new(1, -SCROLLBAR, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	ink(label, SOFT)
	return label
end

function SellView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeSell", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("Pop", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.Width, METRICS.Normal.Height),
		Active = true,
	})
	chrome(panel, SellView.Paint)

	local title = UIKit.label(panel, "TOBIN'S ORE STALL", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 3,
	})
	ink(title)
	local subtitle = UIKit.label(panel, "Tobin buys any ore. Dirty Ore sells at the raw price; you see what it was after.", 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	ink(subtitle, SOFT)
	local receipt = UIKit.label(panel, "", 17, {
		Name = "Receipt",
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 3,
		-- a dark pill behind it: any message colour reads on the band or the body
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.2,
	})
	UIKit.corner(receipt, 8)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, receipt)
	ink(receipt, Theme.Good)
	local close = popButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 30,
		FontFace = PopTheme.Heavy,
	})

	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 2,
	}, panel)
	UIKit.list(list, Enum.FillDirection.Vertical, 8)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10) }, list)

	local footer = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, panel)
	local sellDirty = popButton(footer, "Sell all Dirty Ore", "Orange", {
		Name = "SellDirty",
		TextSize = 20,
	})
	local sellRest = popButton(footer, `Sell all but best {SellView.KeepBest}`, "Green", {
		Name = "SellRest",
		TextSize = 20,
	})
	local hint = UIKit.label(footer, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3,
	})
	ink(hint, SOFT)

	-- confirm step: a dim layer over the panel (click outside the box = cancel)
	local confirm = UIKit.new("TextButton", {
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = false,
		Text = "",
		Visible = false,
		ZIndex = 5,
	}, panel)
	UIKit.corner(confirm, PopTheme.WindowCorner)
	local box = UIKit.new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 230),
		Active = true,
		ZIndex = 6,
	}, confirm)
	UIKit.corner(box, PopTheme.WindowCorner)
	Pop.border(box, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, box)
	Pop.rim(box, Color3.fromRGB(110, 116, 134), PopTheme.WindowCorner, 4, 6)
	Pop.studs(box, PopTheme.WindowCorner, 0.5, 36, 6)
	local confirmText = UIKit.label(box, "", 22, {
		Name = "Text",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -PAD * 2, 1, -(PAD * 3 + 72)),
		ZIndex = 7,
	})
	ink(confirmText)
	local yes = popButton(box, "SELL", "Green", {
		Name = "Yes",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -PAD),
		Size = UDim2.new(0.5, -PAD * 1.5, 0, 66),
		TextSize = 26,
	})
	local no = popButton(box, "CANCEL", PopTheme.Close, {
		Name = "No",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -PAD, 1, -PAD),
		Size = UDim2.new(0.5, -PAD * 1.5, 0, 66),
		TextSize = 26,
	})
	for _, button in { yes, no } do
		local holder = button.Parent :: Frame
		holder.ZIndex = 7
		button.ZIndex = 8
	end
	-- gamepads move between the two (SellController keeps them inside the box)
	yes.NextSelectionRight = no
	no.NextSelectionLeft = yes

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		Close = close,
		List = list,
		Headers = { Pen = sectionHeader(list, "Pen"), Hands = sectionHeader(list, "Hands") },
		Empty = { Pen = emptyLabel(list, "Pen"), Hands = emptyLabel(list, "Hands") },
		Rows = {},
		Footer = footer,
		SellDirty = sellDirty,
		SellRest = sellRest,
		Hint = hint,
		Confirm = confirm,
		ConfirmBox = box,
		ConfirmText = confirmText,
		ConfirmYes = yes,
		ConfirmNo = no,
		Compact = false,
	}
	SellView.layout(refs, compact == true, math.huge, math.huge)
	-- (the light UI: an open window hides the touch thumbstick)
	if UIConfig.lightUI() then
		TouchControls.follow(gui)
	end
	return refs
end

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

local function placeRow(row: Row, m: Metrics)
	local frame = row.Frame
	frame.Size = UDim2.new(1, -SCROLLBAR, 0, m.Row)
	local iconSize = m.Row - 12
	row.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
	row.Icon.Position = UDim2.fromOffset(8, 6)
	row.IconText.TextSize = math.floor(iconSize * 0.62)
	local buttonTop = (m.Row - m.Button) / 2
	local sellAll = holderOf(row.SellAll)
	sellAll.AnchorPoint = Vector2.new(1, 0)
	sellAll.Position = UDim2.new(1, -8, 0, buttonTop)
	sellAll.Size = UDim2.fromOffset(m.SellAll, m.Button)
	local sellOne = holderOf(row.SellOne)
	sellOne.AnchorPoint = Vector2.new(1, 0)
	sellOne.Position = UDim2.new(1, -(16 + m.SellAll), 0, buttonTop)
	sellOne.Size = UDim2.fromOffset(m.SellOne, m.Button)
	local right = 24 + m.SellAll + m.SellOne
	row.Price.AnchorPoint = Vector2.new(1, 0)
	row.Price.Position = UDim2.new(1, -(right + 6), 0, m.Row / 2 - 26)
	row.Price.Size = UDim2.fromOffset(m.PriceWidth, 30)
	row.Price.TextSize = m.Text + 4
	row.Each.AnchorPoint = Vector2.new(1, 0)
	row.Each.Position = UDim2.new(1, -(right + 6), 0, m.Row / 2 + 4)
	row.Each.Size = UDim2.fromOffset(m.PriceWidth, 18)
	local left = iconSize + 20
	local middle = right + m.PriceWidth + 12
	row.Name.Position = UDim2.fromOffset(left, m.Row / 2 - 27)
	row.Name.Size = UDim2.new(1, -(left + middle), 0, 28)
	row.Name.TextSize = m.Text + 2
	local chipH = if m.Row > 70 then 26 else 22
	row.Chip.Position = UDim2.fromOffset(left, m.Row / 2 + 4)
	row.Chip.Size = UDim2.fromOffset(if m.Row > 70 then 100 else 88, chipH)
	row.Chip.TextSize = if m.Row > 70 then 16 else 14
	row.Count.Position = UDim2.fromOffset(left + (if row.Chip.Visible then row.Chip.Size.X.Offset + 8 else 0), m.Row / 2 + 2)
	row.Count.Size = UDim2.fromOffset(90, chipH + 4)
	row.Count.TextSize = m.Text + 2
	row.SellOne.TextSize = if m.Row > 70 then 22 else 20
	row.SellAll.TextSize = if m.Row > 70 then 22 else 20
end

local function newRow(refs: Refs, entry: Entry): Row
	local frame = UIKit.new("Frame", {
		Name = "Row",
		BorderSizePixel = 0,
		ClipsDescendants = true, -- (the light burst behind the picture)
	}, refs.List)
	Pop.face(frame, SellView.rowPaint(entry), ROW_CORNER, false)
	Pop.studs(frame, ROW_CORNER, 0.5, 40, 1)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	-- the picture: a light burst and a soft glow behind the item's live 3D look
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, frame)
	Pop.rays(icon, UDim2.fromScale(0.5, 0.5), 8, 84, 0.45, 1)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 2,
	}, icon)
	UIKit.corner(glow, 999)
	Pop.sparkle(icon, UDim2.fromScale(0.9, 0.14), 16, 4, 0.15)
	Pop.sparkle(icon, UDim2.fromScale(0.08, 0.82), 12, 4, 0.35)
	fillPicture(icon, entry)
	local iconText = UIKit.label(icon, "", 30, {
		Name = "Mark",
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
		ZIndex = 5,
	})
	ink(iconText, WHITE, PopTheme.Heavy)
	local name = UIKit.label(frame, "", 22, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(name)
	local chip = UIKit.chip(frame, "", Theme.PanelDark, {
		Name = "Chip",
		Size = UDim2.fromOffset(88, 22),
		TextSize = 14,
		ZIndex = 4,
	})
	popChip(chip, chipColor(SellView.DirtyColor))
	local count = UIKit.label(frame, "x0", 22, {
		Name = "Count",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	ink(count)
	local price = UIKit.label(frame, "", 24, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(price, PopTheme.Money, PopTheme.Heavy)
	local each = UIKit.label(frame, "each", 14, {
		Name = "Each",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	ink(each, SOFT)
	local sellOne = popButton(frame, "SELL 1", "Green", { Name = "SellOne" })
	local sellAll = popButton(frame, "SELL ALL", "Green", { Name = "SellAll" })
	local row: Row = {
		Id = entry.Id,
		Frame = frame,
		Icon = icon,
		IconText = iconText,
		Name = name,
		Chip = chip,
		Count = count,
		Price = price,
		Each = each,
		SellOne = sellOne,
		SellAll = sellAll,
		Entry = entry,
	}
	refs.Rows[entry.Id] = row
	return row
end

local function fillRow(row: Row, entry: Entry, index: number, m: Metrics)
	row.Entry = entry
	row.Frame.LayoutOrder = SECTION_ORDER[entry.Section] + index
	Pop.repaint(row.Frame, SellView.rowPaint(entry), false)
	row.IconText.Text = if entry.Dirty then "?" else ""
	row.Name.Text = entry.Name
	row.Chip.Visible = entry.ChipText ~= nil
	row.Chip.Text = entry.ChipText or ""
	row.Chip.BackgroundColor3 = chipColor(entry.ChipColor or SellView.DirtyColor)
	row.Count.Text = "x" .. Format.commas(entry.Count)
	row.Price.Text = SellView.priceText(entry.Price)
	holderOf(row.SellAll).Visible = entry.Count > 1
	placeRow(row, m)
end

--[[
	Shows a section's entries in order (at most MaxRows). Rows are reused by
	id; rows of that section that are gone are removed. Returns the rows
	that were just created, so the controller can hook up their buttons.
]]
function SellView.setEntries(refs: Refs, section: Section, list: { Entry }): { Row }
	local m = metrics(refs.Compact)
	local created: { Row } = {}
	local keep: { [string]: boolean } = {}
	for index, entry in list do
		if index > SellView.MaxRows then
			break
		end
		keep[entry.Id] = true
		local row: Row? = refs.Rows[entry.Id]
		if not row then
			local made = newRow(refs, entry)
			table.insert(created, made)
			row = made
		end
		fillRow(row :: Row, entry, index, m)
	end
	for id, row in refs.Rows do
		if row.Entry.Section == section and not keep[id] then
			row.Frame:Destroy()
			refs.Rows[id] = nil
		end
	end
	refs.Empty[section].Visible = next(keep) == nil
	local total = 0
	for _, entry in list do
		total += entry.Count
	end
	refs.Headers[section].Text = if total > 0 then `{SECTION_TITLE[section]}  ({Format.commas(total)})` else SECTION_TITLE[section]
	return created
end

-- The footer buttons: their labels, greyed out when they'd sell nothing.
function SellView.setFooter(refs: Refs, dirty: Plan, rest: Plan)
	local function style(button: TextButton, enabled: boolean, paint: string)
		paintButton(button, if enabled then paint else PopTheme.Gray)
		button.TextTransparency = if enabled then 0 else 0.3
	end
	refs.SellDirty.Text = if dirty.Eligible > 0 then `Sell all Dirty Ore ({Format.commas(dirty.Eligible)})` else "Sell all Dirty Ore"
	style(refs.SellDirty, dirty.Eligible > 0, "Orange")
	refs.SellRest.Text = `Sell all but best {SellView.KeepBest}`
	style(refs.SellRest, rest.Eligible > 0, "Green")
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (the screen divided by
	the UI scale; math.huge = no limit). The title and the X sit in the
	header band, the line under it (the subtitle or the last sale) on the
	body; phones: the last sale next to the title, in the band.
]]
function SellView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local width = math.max(560, math.min(m.Width, maxWidth - 24))
	local height = math.max(400, math.min(m.Height, maxHeight - 16))
	refs.Panel.Size = UDim2.fromOffset(width, height)
	setBand(refs.Panel, m.Band)
	refs.Title.TextSize = m.Title
	refs.Title.Position = UDim2.fromOffset(PAD, 0)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	local closeRoom = m.Close + 24
	if compact then
		-- next to the title, two short lines
		local titleWidth = 330
		refs.Title.Size = UDim2.fromOffset(titleWidth, m.Band)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth + 8, 12)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + 8 + closeRoom), 0, m.Band - 24)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
	else
		refs.Title.Size = UDim2.new(1, -(PAD + closeRoom), 0, m.Band)
		refs.Receipt.Position = UDim2.fromOffset(PAD, m.Band + 3)
		refs.Receipt.Size = UDim2.new(1, -PAD * 2, 0, 26)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
	end
	refs.Subtitle.Position = UDim2.fromOffset(PAD, m.Band + 5)
	refs.Subtitle.Size = UDim2.new(1, -PAD * 2, 0, 22)
	syncShadow(refs.Title)
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -12, 0, math.floor((m.Band - m.Close) / 2))
	refs.Close.TextSize = math.floor(m.Close * 0.62)
	refs.List.Position = UDim2.fromOffset(PAD, m.Header)
	refs.List.Size = UDim2.new(1, -PAD, 1, -(m.Header + m.Footer))
	refs.Footer.Position = UDim2.new(0, PAD, 1, -8)
	refs.Footer.Size = UDim2.new(1, -PAD * 2, 0, m.Footer - 10)
	local buttonTop = 10
	for i, button in { refs.SellDirty, refs.SellRest } do
		local holder = holderOf(button)
		holder.Size = UDim2.new(0.5, -6, 0, m.Button)
		holder.Position = UDim2.new(if i == 1 then 0 else 0.5, if i == 1 then 0 else 6, 0, buttonTop)
		button.TextSize = if compact then 24 else 22
	end
	refs.Hint.Visible = not compact
	refs.ConfirmText.TextSize = if compact then 24 else 22
	refs.ConfirmBox.Size = UDim2.fromOffset(math.min(width - 40, if compact then 620 else 520), if compact then 260 else 230)
	for _, button in { refs.ConfirmYes, refs.ConfirmNo } do
		holderOf(button).Size = UDim2.new(0.5, -PAD * 1.5, 0, m.Button + 8)
	end
	for _, row in refs.Rows do
		placeRow(row, m)
	end
end

-- Shows a message (instead of the subtitle).
function SellView.showReceipt(refs: Refs, text: string, color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = color
	refs.Receipt.Visible = true
	refs.Subtitle.Visible = false
end

function SellView.hideReceipt(refs: Refs)
	refs.Receipt.Visible = false
	refs.Subtitle.Visible = not refs.Compact
end

function SellView.showConfirm(refs: Refs, text: string)
	refs.ConfirmText.Text = text
	refs.Confirm.Visible = true
end

function SellView.hideConfirm(refs: Refs)
	refs.Confirm.Visible = false
end

-- The first row of a section (lowest LayoutOrder), for gamepad selection.
function SellView.firstRow(refs: Refs): Row?
	local first: Row? = nil
	for _, row in refs.Rows do
		if not first or row.Frame.LayoutOrder < first.Frame.LayoutOrder then
			first = row
		end
	end
	return first
end

return SellView
