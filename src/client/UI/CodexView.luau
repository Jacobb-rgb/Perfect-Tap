--[[
	The ORE CODEX (pure builder + pure helpers; CodexController fills it in).
	Opens from the side menu's CODEX button (the ROCK SCANNER terminal with
	its "Ore Codex" prompt went 2026-10-24, owner; a model tagged OreCodex
	still gets the prompt). One MenuPanel in the Pop look
	(owner 2026-10-21: "new, modern, colourful, clean items, Roblox style",
	like the Robux Shop):

	  header  ORE CODEX on the teal band, the count bar "17 / 36 FOUND" (a
	          glossy gold fill, Pop.bar)
	  grid    every ore (#OreData.List, 36; Common -> Mythic), one bright
	          card each painted in its rarity's colour (Pop.rarityPaint) with
	          light rays and a glow behind the ore's live 3D picture (a
	          ViewportFrame of the cleaned ore, ItemBuilder; built once the ore
	          is discovered; the preview draws item_Clean_<Ore>), a soft halo
	          in the ore's own glow colour, the name and the rarity chip. An
	          ore you haven't discovered is a dark slate card with a big "?"
	          and "???". A NEW chip marks ores discovered since you last looked
	          (the controller decides which); the selected card gets a gold
	          outline.
	  detail  the selected ore on a bright card in its rarity's colour: the
	          big 3D picture, name, rarity chip, and in a dark well under them
	          the podium income (Rough and Flawless), sell value (cleaned
	          Rough and Flawless, and dirty, before sell bonuses), the blaster
	          level it needs (the lowest gate of the zones that hold it:
	          levelOf), where it is found (the WorldLayout zones whose rocks
	          hold it) and its lore. Undiscovered: a dark card, "???" and how
	          to find it.

	Click / tap a card (or move the gamepad selection onto it) to read it.
	Designed for 720 design units of height; the compact layout (phones)
	makes every card at least 44 pt (CodexView.touchTargets for the tests).
	Discovery comes from the State snapshot (snapshot.Discovered, the save's
	{ [oreId] = true }): CodexView.entries.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local PopTheme = require(Shared.Config.PopTheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local MenuPanel = require(script.Parent.MenuPanel)

local CodexView = {}

export type Entry = {
	Ore: OreData.Ore,
	Found: boolean,
	New: boolean,
	Zones: { string }, -- names of the zones whose rocks hold it
}

export type Card = {
	OreId: string,
	Button: TextButton,
	Gem: Frame, -- the halo behind the picture (the ore's colour when found)
	Mark: TextLabel, -- the big "?" of an undiscovered ore
	Name: TextLabel,
	Strip: Frame, -- the rarity chip
	New: Frame, -- the NEW chip
	Stroke: UIStroke, -- the card's outline (gold when selected)
}

export type Refs = {
	Frame: MenuPanel.Refs,
	Gui: ScreenGui,
	Count: TextLabel,
	CountFill: Frame,
	CountChip: Frame,
	Grid: ScrollingFrame,
	GridLayout: UIGridLayout,
	Cards: { [string]: Card },
	CardList: { Card },
	Detail: Frame,
	DetailGem: Frame,
	DetailMark: TextLabel,
	DetailName: TextLabel,
	DetailRarity: TextLabel,
	DetailIncome: TextLabel,
	DetailValue: TextLabel,
	DetailTier: TextLabel,
	DetailWhere: TextLabel,
	DetailLore: TextLabel,
	Selected: string?,
	Compact: boolean,
	Filters: { [string]: TextButton }, -- the round look's rarity tabs right of the window (the reel's Index)
	Filter: string?, -- the rarity they show now (nil: every card)
}

type Metrics = {
	Width: number,
	Height: number,
	CardW: number,
	CardH: number,
	Gap: number,
	DetailW: number,
	CardText: number,
	Text: number,
	Lore: number,
	Gem: number,
}

CodexView.Metrics = {
	Normal = {
		Width = 960,
		Height = 640,
		CardW = 88,
		CardH = 124,
		Gap = 8,
		DetailW = 300,
		CardText = 15,
		Text = 16,
		Lore = 16,
		Gem = 124,
	},
	-- phones: at uiScale 0.62 a 72-unit card is about 44 pt
	Compact = {
		Width = 1120,
		Height = 640,
		CardW = 80,
		CardH = 100,
		Gap = 8,
		DetailW = 300,
		CardText = 16,
		Text = 18,
		Lore = 17,
		Gem = 84,
	},
} :: { [string]: Metrics }

CodexView.GridInset = 12 -- the grid's left padding, its scroll bar and a little room
-- the round look's rarity filter tabs right of the window (the reel's Index: Common grey,
-- Uncommon green, Rare blue, Epic purple, Legendary yellow, our Mythic pink)
CodexView.FilterW = 170
CodexView.FilterH = 52
CodexView.FilterGap = 10
CodexView.FilterPaints = {
	Common = "Gray",
	Uncommon = "Lime",
	Rare = "Royal",
	Epic = "Violet",
	Legendary = "Yellow",
	Mythic = "Pink",
} :: { [string]: string }
CodexView.ChipCard = 110 -- cards at least this tall show the rarity chip (phones: the detail shows it)
CodexView.HiddenColor = Color3.fromRGB(58, 62, 74)
CodexView.HiddenEdge = Color3.fromRGB(96, 102, 120)
-- an undiscovered ore's card: darker than the Common slate
CodexView.HiddenPaint = {
	Top = Color3.fromRGB(70, 74, 88),
	Bottom = Color3.fromRGB(34, 36, 46),
	Edge = PopTheme.Outline,
} :: Pop.Paint
CodexView.SelectColor = Color3.fromRGB(255, 222, 64) -- the selected card's gold outline
CodexView.HiddenName = "???"
CodexView.FindHint = "Not discovered yet. Blast rocks, then clean the dirty ore to find out what it is."

---------------------------------------------------------------- pure helpers

-- the zones never change while the game runs: worked out once per ore
local zoneCache: { [string]: { string } } = {}

-- Names of the zones whose rocks hold an ore, in world order (deeper later).
-- (A shared list: don't change it.)
function CodexView.zonesOf(oreId: string): { string }
	local cached = zoneCache[oreId]
	if cached then
		return cached
	end
	local names = {}
	for _, zone in WorldLayout.Zones do
		local weight = zone.Ores[oreId]
		if type(weight) == "number" and weight > 0 then
			table.insert(names, zone.Name)
		end
	end
	zoneCache[oreId] = names
	return names
end

local levelCache: { [string]: number } = {}

-- The blaster level an ore needs: the lowest MinBlaster of the zones whose
-- rocks hold it (the VIP-only zones count only when no other zone holds
-- it), else the ore's own Tier (no zone holds it). So the line agrees with
-- "Found in" under it (Bronze: the Quarry, level 1).
function CodexView.levelOf(ore: OreData.Ore): number
	local cached = levelCache[ore.Id]
	if cached then
		return cached
	end
	local open, vip = math.huge, math.huge
	for _, zone in WorldLayout.Zones do
		local weight = zone.Ores[ore.Id]
		if type(weight) == "number" and weight > 0 then
			if zone.VipOnly then
				vip = math.min(vip, zone.MinBlaster)
			else
				open = math.min(open, zone.MinBlaster)
			end
		end
	end
	local level = if open < math.huge then open elseif vip < math.huge then vip else ore.Tier
	levelCache[ore.Id] = level
	return level
end

-- What the cards show, as one string (discovered ores and NEW badges):
-- the codex redraws only when it changes, not on every State push.
function CodexView.fingerprint(discovered: any, fresh: { [string]: boolean }?): string
	local found = if type(discovered) == "table" then discovered else {}
	local parts = table.create(#OreData.List)
	for _, ore in OreData.List do
		if found[ore.Id] == true then
			table.insert(parts, if fresh and fresh[ore.Id] then ore.Id .. "!" else ore.Id)
		end
	end
	return table.concat(parts, ",")
end

-- Every ore with whether it is discovered (the save's { [oreId] = true }).
-- `fresh` = ores to mark NEW (discovered since the codex was last looked at).
function CodexView.entries(discovered: any, fresh: { [string]: boolean }?): { Entry }
	local found = if type(discovered) == "table" then discovered else {}
	local list = table.create(#OreData.List)
	for _, ore in OreData.List do
		local isFound = found[ore.Id] == true
		table.insert(list, {
			Ore = ore,
			Found = isFound,
			New = isFound and fresh ~= nil and fresh[ore.Id] == true,
			Zones = CodexView.zonesOf(ore.Id),
		})
	end
	return list
end

-- How many entries are discovered, and the total.
function CodexView.count(entries: { Entry }): (number, number)
	local n = 0
	for _, entry in entries do
		if entry.Found then
			n += 1
		end
	end
	return n, #entries
end

-- "17 / 36 FOUND"
function CodexView.countText(found: number, total: number): string
	return `{found} / {total} FOUND`
end

-- The detail texts of an entry (undiscovered ones keep their secrets).
export type DetailText = {
	Name: string,
	Rarity: string?,
	Income: string,
	Value: string,
	Tier: string,
	Where: string,
	Lore: string,
}
function CodexView.detailText(entry: Entry): DetailText
	if not entry.Found then
		return {
			Name = CodexView.HiddenName,
			Rarity = nil,
			Income = CodexView.FindHint,
			Value = "",
			Tier = "",
			Where = "",
			Lore = "",
		}
	end
	local ore = entry.Ore
	local flawless = ore.Income * ItemData.gradeMult("Flawless")
	-- what the ore sells for (before sell bonuses): cleaned (Rough, like
	-- the podium line) and Flawless, and as the Dirty Ore it is when mined
	local clean = ItemData.value("Clean", ore.Id, "Rough")
	local best = ItemData.value("Clean", ore.Id, "Flawless")
	local dirty = ItemData.value("Raw", ore.Id)
	local where = if #entry.Zones > 0 then table.concat(entry.Zones, ", ") else "Deep in the mines"
	return {
		Name = ore.Name,
		Rarity = ore.Rarity,
		Income = `Podium: {Format.perSecond(ore.Income)}  (Flawless {Format.perSecond(flawless)})`,
		Value = `Sells: {Format.money(clean)} (Flawless {Format.money(best)}), dirty {Format.money(dirty)}`,
		Tier = `Blaster level {CodexView.levelOf(ore)}+`,
		Where = `Found in: {where}`,
		Lore = ore.Lore,
	}
end

-- The part that carries the ROCK SCANNER terminal's "Ore Codex" prompt:
-- the tagged part itself, or a tagged model's cabinet (its PrimaryPart, or
-- the part named Cabinet). nil while the cabinet hasn't streamed in: never
-- some other small part (CodexController waits for the cabinet).
function CodexView.promptPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		local primary = target.PrimaryPart
		if primary then
			return primary
		end
		local cabinet = target:FindFirstChild("Cabinet", true)
		if cabinet and cabinet:IsA("BasePart") then
			return cabinet
		end
	end
	return nil
end

---------------------------------------------------------------- builders

local function metrics(compact: boolean): Metrics
	return if compact then CodexView.Metrics.Compact else CodexView.Metrics.Normal
end

-- the camera's direction for an ore's picture (the shop's item_ pictures)
local FROM = Vector3.new(-0.5, 0.5, -1)

-- A deep version of a paint (chips on a card in that paint).
local function deep(paint: Pop.Paint): Pop.Paint
	local black = Color3.new(0, 0, 0)
	return { Top = paint.Bottom:Lerp(black, 0.1), Bottom = paint.Bottom:Lerp(black, 0.5), Edge = PopTheme.Outline }
end

-- A card's paint: its rarity's (found) or the dark slate (undiscovered).
local function paintOf(ore: OreData.Ore?): Pop.Paint
	return if ore then Pop.rarityPaint(ore.Rarity) else CodexView.HiddenPaint
end

-- A cleaned ore for a picture (nil when the builder fails).
local function oreModel(oreId: string): Model?
	local ok, made = pcall(ItemBuilder.build, { Kind = "Clean", OreId = oreId, Grade = "Clean" }, CFrame.new(), "codex_" .. oreId)
	return if ok then made else nil
end

-- Puts the ore's model in a picture's ViewportFrame (once per ore; `force` swaps it).
local function fillPicture(picture: ImageLabel, oreId: string, force: boolean?)
	local view = picture:FindFirstChild("View") :: ViewportFrame?
	if not view or (not force and view:GetAttribute("Ore") == oreId) then
		return
	end
	local model = oreModel(oreId)
	if model then
		-- (a ViewportFrame draws no particles or lights: leave them out)
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") then
				d:Destroy()
			end
		end
		Pop.show(view, model, FROM)
		view:SetAttribute("Ore", oreId)
	end
end

-- The light burst of a card (rays, glows, sparkles): hidden on an undiscovered ore.
local function fxOf(card: GuiObject): { GuiObject }
	local list: { GuiObject } = {}
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("Fx") then
			table.insert(list, child)
		end
	end
	return list
end

local function markFx(card: GuiObject)
	for _, child in card:GetChildren() do
		local name = child.Name
		if child:IsA("GuiObject") and (name == "Rays" or string.sub(name, 1, 4) == "Glow" or string.sub(name, 1, 7) == "Sparkle") then
			child:SetAttribute("Fx", true)
		end
	end
end

local function setFx(card: GuiObject, on: boolean)
	local none = card:GetAttribute("NoFx") == true -- (the round look's cells: no sunburst)
	for _, child in fxOf(card) do
		child.Visible = on and not none
	end
end

--[[
	Paints a Frame like Pop.card (the detail pane is no button): the paint,
	light rays and a soft glow around `centre`, the studs, the light rim and
	a few sparkles. It clips its rays.
]]
local function paintFrame(frame: Frame, paint: Pop.Paint, centre: UDim2, long: number, short: number)
	Pop.face(frame, paint, PopTheme.Corner + 2, false)
	if PopTheme.round() then
		Pop.twoTone(frame, paint)
	end
	frame.ClipsDescendants = true
	local rays = Pop.fx(frame, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = centre,
		Size = UDim2.fromOffset(long * 2.2, long * 2.2),
		ZIndex = 2,
	})
	if not rays then
		Pop.rays(frame, centre, 10, long, 0.6, 2)
	end
	local glow = Pop.fx(frame, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = paint.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = 0.3,
		Position = centre,
		Size = UDim2.fromOffset(math.floor(short * 1.1), math.floor(short * 1.1)),
		ZIndex = 2,
	})
	if not glow then
		for i, k in { 0.62, 0.42 } do
			local disc = UIKit.new("Frame", {
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = if i == 1 then 0.8 else 0.7,
				BorderSizePixel = 0,
				Position = centre,
				Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
				ZIndex = 2,
			}, frame)
			UIKit.corner(disc, 999)
		end
	end
	Pop.studs(frame, PopTheme.Corner + 2, 0.5, 44, 3)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	for i, spot in { { 0.18, 0.1, 22 }, { 0.84, 0.16, 18 }, { 0.78, 0.32, 14 } } do
		Pop.sparkle(frame, UDim2.fromScale(spot[1], spot[2]), spot[3], 3, 0.15 + i * 0.08)
	end
	markFx(frame)
end

-- A label's drop shadow (Pop.shadow) follows its text, place and size.
local function syncShadow(label: TextLabel)
	local parent = label.Parent
	local shadow = if parent then parent:FindFirstChild(label.Name .. "Shadow") :: TextLabel? else nil
	if shadow then
		shadow.Text = label.Text
		shadow.TextSize = label.TextSize
		shadow.Position = label.Position + UDim2.fromOffset(0, 3)
		shadow.Size = label.Size
		shadow.Visible = label.Visible
		shadow.TextXAlignment = label.TextXAlignment
		shadow.AnchorPoint = label.AnchorPoint
	end
end

-- The halo behind a picture: a soft disc in the ore's colour with its glow
-- as the edge (dark for an undiscovered ore, a big "?" on it).
local function halo(parent: Instance, name: string, z: number): Frame
	local disc = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CodexView.HiddenColor,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	UIKit.corner(disc, 999)
	UIKit.new("UIStroke", {
		Name = "Glow",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = CodexView.HiddenEdge,
		Thickness = 3,
		Transparency = 0.2,
	}, disc)
	return disc
end

-- Colours a halo for an ore (found) or the dark undiscovered one, and shows its "?".
function CodexView.paintGem(body: Frame, mark: TextLabel, ore: OreData.Ore?)
	local glow = body:FindFirstChild("Glow") :: UIStroke?
	if ore then
		body.BackgroundColor3 = ore.Color
		body.BackgroundTransparency = 0.55
		if glow then
			glow.Color = ore.Glow
			glow.Transparency = 0.25
		end
		mark.Visible = false
	else
		body.BackgroundColor3 = CodexView.HiddenColor
		body.BackgroundTransparency = 0.2
		if glow then
			glow.Color = CodexView.HiddenEdge
			glow.Transparency = 0.1
		end
		mark.Visible = true
	end
end

local function newCard(refs: Refs, ore: OreData.Ore, order: number, m: Metrics)
	local button = Pop.card(refs.Grid, CodexView.HiddenPaint, {
		Name = "Card" .. ore.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(m.CardW, m.CardH),
	}, UDim2.fromScale(0.5, 0.5))
	button:SetAttribute("Ore", ore.Id)
	markFx(button)
	if PopTheme.round() then
		-- (the reel's Index: a dark cell, the rarity on its inner edge, no sunburst)
		Pop.cellFace(button, nil, 6)
		button:SetAttribute("NoFx", true)
	end
	local stroke = button:FindFirstChild("Border") :: UIStroke
	local gem = halo(button, "Gem", 4)
	Pop.model(button, "item_Clean_" .. ore.Id, 60, nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
	})
	local mark = Pop.text(button, "?", 44, {
		Name = "Mark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = PopTheme.Heavy,
		TextColor3 = Color3.fromRGB(214, 220, 236),
		ZIndex = 6,
	})
	local name = Pop.text(button, CodexView.HiddenName, m.CardText, {
		Name = "OreName",
		AnchorPoint = Vector2.new(0.5, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	local strip = Pop.chip(button, string.upper(ore.Rarity), deep(Pop.rarityPaint(ore.Rarity)), Vector2.new(72, 18), {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 7,
	})
	if PopTheme.round() then
		-- (the reel's Index: the rarity as a word in its colour on top of the cell, no chip)
		strip.BackgroundTransparency = 1
		local stripBorder = strip:FindFirstChild("Border") :: UIStroke?
		if stripBorder then
			stripBorder.Enabled = false
		end
		local label = strip:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = ore.Rarity
			label.TextColor3 = Pop.rarityPaint(ore.Rarity).Top:Lerp(Color3.new(1, 1, 1), 0.25)
		end
	end
	local new = Pop.chip(button, "NEW", "Green", Vector2.new(42, 20), {
		Name = "NewBadge",
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 8,
		Visible = false,
		ZIndex = 8,
	})
	local card: Card = {
		OreId = ore.Id,
		Button = button,
		Gem = gem,
		Mark = mark,
		Name = name,
		Strip = strip,
		New = new,
		Stroke = stroke,
	}
	setFx(button, false)
	refs.Cards[ore.Id] = card
	table.insert(refs.CardList, card)
end

function CodexView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local frame = MenuPanel.build("TerraForgeCodex", "ORE CODEX", "Every ore of Terra. Discover them by cleaning dirty ore.", 16, true)
	local panel = frame.Panel
	local body = frame.Body

	-- the count bar (a glossy gold fill), left of the X button
	local chip = Pop.bar(panel, 0, "Yellow", Vector2.new(190, 40), `0 / {#OreData.List} FOUND`, {
		Name = "CountChip",
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 4,
	})
	local fill = chip:FindFirstChild("Fill") :: Frame
	local count = chip:FindFirstChild("Label") :: TextLabel

	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(200, 208, 226),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 2,
	}, body)
	local gridLayout = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(m.CardW, m.CardH),
		CellPadding = UDim2.fromOffset(m.Gap, m.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, grid)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
	}, grid)

	-- the detail pane: a bright card in the selected ore's rarity colour
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, body)
	paintFrame(detail, CodexView.HiddenPaint, UDim2.new(0.5, 0, 0, 72), 300, 160)
	local detailGem = halo(detail, "Halo", 4)
	Pop.model(detail, "item_Clean_" .. OreData.List[1].Id, m.Gem, nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
	})
	local detailMark = Pop.text(detail, "?", 60, {
		Name = "Mark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = PopTheme.Heavy,
		TextColor3 = Color3.fromRGB(214, 220, 236),
		ZIndex = 6,
	})
	local detailName = Pop.text(detail, CodexView.HiddenName, 28, {
		Name = "OreName",
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	Pop.shadow(detailName, 3)
	local rarityChip = Pop.chip(detail, "COMMON", deep(Pop.rarityPaint("Common")), Vector2.new(130, 28), {
		Name = "Rarity",
		ZIndex = 7,
	})
	local detailRarity = rarityChip:FindFirstChild("Label") :: TextLabel
	-- the facts in a dark well (readable on any paint)
	local info = Pop.well(detail, { Name = "Info", ZIndex = 4 })
	local function line(name: string, color: Color3): TextLabel
		return Pop.text(info, "", m.Text, {
			Name = name,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 6,
		})
	end
	local refs: Refs = {
		Frame = frame,
		Gui = frame.Gui,
		Count = count,
		CountFill = fill,
		CountChip = chip,
		Grid = grid,
		GridLayout = gridLayout,
		Cards = {},
		CardList = {},
		Detail = detail,
		DetailGem = detailGem,
		DetailMark = detailMark,
		DetailName = detailName,
		DetailRarity = detailRarity,
		DetailIncome = line("Income", PopTheme.Money),
		DetailValue = line("Value", Color3.fromRGB(255, 232, 120)),
		DetailTier = line("Tier", Color3.fromRGB(140, 214, 255)),
		DetailWhere = line("Where", PopTheme.Ink),
		DetailLore = line("Lore", Color3.fromRGB(206, 214, 232)),
		Selected = nil,
		Compact = isCompact,
		Filters = {},
		Filter = nil,
	}
	for i, ore in OreData.List do
		newCard(refs, ore, i, m)
	end
	if PopTheme.round() then
		-- the reel's rarity tabs outside the window, on its right (a tap shows only the found
		-- ores of that rarity, again shows all)
		for i, rarity in Rarity.List do
			local tab = Pop.button(
				frame.Panel,
				rarity.Name,
				CodexView.FilterPaints[rarity.Id] or "Slate",
				Vector2.new(CodexView.FilterW, CodexView.FilterH),
				{
					Name = "Filter" .. rarity.Id,
					LayoutOrder = i,
					ZIndex = 4,
				}
			)
			refs.Filters[rarity.Id] = tab
			pcall(function()
				tab.Activated:Connect(function()
					CodexView.setFilter(refs, if refs.Filter == rarity.Id then nil else rarity.Id)
				end)
			end)
		end
	end
	CodexView.layout(refs, isCompact, math.huge, math.huge)
	return refs
end

--[[
	The round look's rarity filter: only the found ores of `rarity` show
	(an undiscovered ore never tells its rarity); nil shows every card. The
	picked tab gets a white edge.
]]
function CodexView.setFilter(refs: Refs, rarity: string?)
	refs.Filter = rarity
	for _, card in refs.CardList do
		local ore = OreData.ById[card.OreId]
		local found = card.Button:GetAttribute("Found") == true
		card.Button.Visible = rarity == nil or (found and ore ~= nil and ore.Rarity == rarity)
	end
	for id, tab in refs.Filters do
		local border = tab:FindFirstChild("Border") :: UIStroke?
		if border then
			border.Color = if id == rarity then Color3.new(1, 1, 1) else PopTheme.Outline
		end
	end
end

---------------------------------------------------------------- layout

-- Places one card's inside for its cell (w x h design units); `chip` = room for the rarity chip.
-- A card name's text size: the full size, smaller (down to 11) when the name is wider than the card.
local function fitName(card: Card)
	local grid = card.Button.Parent
	local width = if grid then grid:GetAttribute("CardW") else nil
	local max = if grid then grid:GetAttribute("CardText") else nil
	if type(width) ~= "number" or type(max) ~= "number" then
		return
	end
	local size = max
	while size > 11 and Pop.textWidth(card.Name.Text, size) > width - 8 do
		size -= 1
	end
	card.Name.TextSize = size
end

local function layoutCard(card: Card, w: number, h: number, textSize: number, chip: boolean)
	local button = card.Button
	if PopTheme.round() then
		-- (the reel's Index cell: the rarity word on top in its colour, the picture, the name at the bottom)
		local word = math.max(12, textSize - 2)
		card.Strip.AnchorPoint = Vector2.new(0.5, 0)
		card.Strip.Position = UDim2.new(0.5, 0, 0, 5)
		card.Strip.Size = UDim2.fromOffset(w - 10, word + 4)
		card.Strip:SetAttribute("Room", true)
		card.Name.TextSize = textSize
		card.Name.AnchorPoint = Vector2.new(0.5, 1)
		card.Name.Position = UDim2.new(0.5, 0, 1, -5)
		card.Name.Size = UDim2.new(1, -8, 0, textSize + 4)
		local top = 5 + word + 6
		local bottom = h - (textSize + 10)
		local size = math.max(24, math.floor(math.min(w - 16, bottom - top)))
		local centre = UDim2.fromOffset(math.floor(w / 2), math.floor((top + bottom) / 2))
		local picture = button:FindFirstChild("Picture") :: ImageLabel
		picture.Position = centre
		picture.Size = UDim2.fromOffset(size, size)
		card.Gem.Position = centre
		card.Gem.Size = UDim2.fromOffset(math.floor(size * 0.78), math.floor(size * 0.78))
		card.Mark.Position = centre
		card.Mark.Size = UDim2.fromOffset(size, size)
		card.Mark.TextSize = math.floor(size * 0.62)
		card.New.Position = UDim2.new(1, -3, 0, top)
		return
	end
	card.Name.TextSize = textSize
	card.Name.Position = UDim2.new(0.5, 0, 0, 4)
	card.Name.Size = UDim2.new(1, -8, 0, textSize + 4)
	local top = 4 + textSize + 4
	local chipH = 18
	local bottom = if chip then h - (chipH + 10) else h - 6
	card.Strip.Position = UDim2.new(0.5, 0, 1, -6)
	card.Strip.Size = UDim2.fromOffset(math.max(40, w - 14), chipH)
	card.Strip:SetAttribute("Room", chip)
	local size = math.max(24, math.floor(math.min(w - 14, bottom - top)))
	local centre = UDim2.fromOffset(math.floor(w / 2), math.floor((top + bottom) / 2))
	local picture = button:FindFirstChild("Picture") :: ImageLabel
	picture.Position = centre
	picture.Size = UDim2.fromOffset(size, size)
	card.Gem.Position = centre
	card.Gem.Size = UDim2.fromOffset(math.floor(size * 0.78), math.floor(size * 0.78))
	card.Mark.Position = centre
	card.Mark.Size = UDim2.fromOffset(size, size)
	card.Mark.TextSize = math.floor(size * 0.62)
	card.New.Position = UDim2.new(1, -3, 0, top + 2)
end

-- Fits the codex into the room it gets (design units).
function CodexView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local frame = refs.Frame
	-- (the round look's filter tabs right of the window on big screens: the window leaves them room)
	local filters = next(refs.Filters) ~= nil and not compact
	local room = if filters then CodexView.FilterW + CodexView.FilterGap + 8 else 0
	local bodySize = MenuPanel.layout(frame, compact, m.Width, m.Height, maxWidth - 2 * room, maxHeight)
	if room > 0 and maxWidth < 1e6 and frame.Panel.AnchorPoint == Vector2.zero then
		-- (laid out in a room narrower on both sides: back to the screen's middle, the tabs on its right)
		frame.Panel.Position += UDim2.fromOffset(room, 0)
	end
	local mm = if compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal
	for id, tab in refs.Filters do
		local info = Rarity.ById[id]
		local i = if info then table.find(Rarity.List, info) or 1 else 1
		local holder = tab :: GuiObject
		holder.Visible = filters
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.new(1, CodexView.FilterGap, 0, mm.Header + (i - 1) * (CodexView.FilterH + CodexView.FilterGap))
	end

	-- the count bar left of the X button, in the band's middle
	local barH = if compact then 48 else 40
	refs.CountChip.Size = UDim2.fromOffset(if compact then 220 else 200, barH)
	refs.CountChip.Position = UDim2.new(1, -(MenuPanel.Pad + mm.Close + 12), 0, math.floor((mm.Header - barH) / 2))
	refs.Count.TextSize = if compact then 24 else 21
	frame.Title.Size = UDim2.new(1, -(MenuPanel.Pad * 2 + mm.Close + 240), 0, frame.Title.Size.Y.Offset)
	frame.Subtitle.Size = UDim2.new(1, -(MenuPanel.Pad * 2 + mm.Close + 240), 0, 20)
	MenuPanel.syncTitle(frame)

	-- the grid fills the body left of the detail pane
	local detailW = math.min(m.DetailW, math.max(220, bodySize.X * 0.36))
	local gridW = bodySize.X - detailW - 12
	refs.Grid.Position = UDim2.fromOffset(0, 0)
	refs.Grid.Size = UDim2.new(0, gridW, 1, 0)
	-- as many columns of at least CardW as fit (beside the scroll bar and
	-- the padding), the cards stretched to fill the row
	local usable = gridW - CodexView.GridInset
	local columns = math.max(1, math.floor((usable + m.Gap) / (m.CardW + m.Gap)))
	local cardW = math.floor((usable - (columns - 1) * m.Gap) / columns)
	refs.GridLayout.CellSize = UDim2.fromOffset(cardW, m.CardH)
	refs.GridLayout.CellPadding = UDim2.fromOffset(m.Gap, m.Gap)
	local chip = m.CardH >= CodexView.ChipCard or PopTheme.round() -- (the round look: the rarity word always)
	refs.Grid:SetAttribute("Chips", chip)
	refs.Grid:SetAttribute("CardW", cardW)
	refs.Grid:SetAttribute("CardText", m.CardText)
	for _, card in refs.CardList do
		layoutCard(card, cardW, m.CardH, m.CardText, chip)
		fitName(card)
		card.Strip.Visible = chip and card.Button:GetAttribute("Found") == true
	end

	-- the detail card: big picture, name and rarity (tall on big screens,
	-- side by side on phones), the facts in the well under them
	refs.Detail.Position = UDim2.new(1, 0, 0, 0)
	refs.Detail.Size = UDim2.new(0, detailW, 1, -4)
	local detail = refs.Detail
	local picture = detail:FindFirstChild("Picture") :: ImageLabel
	local rarityChip = refs.DetailRarity.Parent :: Frame
	local g = m.Gem
	local centre: UDim2
	local y: number
	if compact then
		centre = UDim2.fromOffset(12 + g / 2, 10 + g / 2)
		local textX = 20 + g
		refs.DetailName.AnchorPoint = Vector2.new(0, 0)
		refs.DetailName.Position = UDim2.fromOffset(textX, 14)
		refs.DetailName.Size = UDim2.new(1, -(textX + 10), 0, 34)
		refs.DetailName.TextXAlignment = Enum.TextXAlignment.Left
		refs.DetailName.TextSize = 26
		rarityChip.AnchorPoint = Vector2.new(0, 0)
		rarityChip.Position = UDim2.fromOffset(textX, 54)
		y = 18 + g
	else
		centre = UDim2.new(0.5, 0, 0, 10 + g / 2)
		refs.DetailName.AnchorPoint = Vector2.new(0.5, 0)
		refs.DetailName.Position = UDim2.new(0.5, 0, 0, 14 + g)
		refs.DetailName.Size = UDim2.new(1, -20, 0, 34)
		refs.DetailName.TextXAlignment = Enum.TextXAlignment.Center
		refs.DetailName.TextSize = 30
		rarityChip.AnchorPoint = Vector2.new(0.5, 0)
		rarityChip.Position = UDim2.new(0.5, 0, 0, 52 + g)
		y = 90 + g
	end
	rarityChip.Size = UDim2.fromOffset(140, 28)
	refs.DetailRarity.TextSize = 18
	syncShadow(refs.DetailName)
	picture.Position = centre
	picture.Size = UDim2.fromOffset(g, g)
	refs.DetailGem.Position = centre
	refs.DetailGem.Size = UDim2.fromOffset(math.floor(g * 0.78), math.floor(g * 0.78))
	refs.DetailMark.Position = centre
	refs.DetailMark.Size = UDim2.fromOffset(g, g)
	refs.DetailMark.TextSize = math.floor(g * 0.6)
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("Fx") and not string.find(child.Name, "Sparkle", 1, true) then
			child.Position = centre
		end
	end
	-- the facts: a well from y to the bottom
	local info = detail:FindFirstChild("Info") :: Frame
	info.Position = UDim2.fromOffset(8, y)
	info.Size = UDim2.new(1, -16, 1, -(y + 8))
	local inner = detailW - 16 - 24
	local ly = 10
	local function place(label: TextLabel, lines: number, size: number)
		label.TextSize = size
		label.Position = UDim2.fromOffset(12, ly)
		label.Size = UDim2.fromOffset(inner, lines * (size + 4))
		ly += lines * (size + 4) + 4
	end
	place(refs.DetailIncome, 2, m.Text)
	place(refs.DetailValue, 2, m.Text)
	place(refs.DetailTier, 1, m.Text)
	place(refs.DetailWhere, 2, m.Text)
	ly += 2
	refs.DetailLore.TextSize = m.Lore
	refs.DetailLore.Position = UDim2.fromOffset(12, ly)
	refs.DetailLore.Size = UDim2.new(0, inner, 1, -(ly + 8))
end

---------------------------------------------------------------- filling in

-- Shows the entries on the cards and the count.
function CodexView.setEntries(refs: Refs, entries: { Entry })
	local chips = refs.Grid:GetAttribute("Chips") ~= false
	for _, entry in entries do
		local card = refs.Cards[entry.Ore.Id]
		if card then
			local found = entry.Found
			local ore = if found then entry.Ore else nil
			local button = card.Button
			Pop.repaint(button, paintOf(ore), false)
			setFx(button, found)
			CodexView.paintGem(card.Gem, card.Mark, ore)
			local picture = button:FindFirstChild("Picture") :: ImageLabel
			picture.Visible = found
			if found then
				fillPicture(picture, entry.Ore.Id)
			end
			card.Name.Text = if found then entry.Ore.Name else CodexView.HiddenName
			fitName(card)
			card.Name.TextColor3 = if found then PopTheme.Ink else Color3.fromRGB(176, 184, 204)
			card.Strip.Visible = found and chips
			card.New.Visible = entry.New
			button:SetAttribute("Found", found)
		end
	end
	local found, total = CodexView.count(entries)
	Pop.setBar(refs.CountChip, if total > 0 then found / total else 0, CodexView.countText(found, total))
	if refs.Filter then
		CodexView.setFilter(refs, refs.Filter)
	end
end

-- Shows one entry in the detail pane and marks its card.
function CodexView.select(refs: Refs, entry: Entry)
	refs.Selected = entry.Ore.Id
	for _, card in refs.CardList do
		local on = card.OreId == entry.Ore.Id
		card.Stroke.Color = if on then CodexView.SelectColor else PopTheme.Outline
		card.Stroke.Thickness = if on then 5 else PopTheme.Edge
	end
	local text = CodexView.detailText(entry)
	local ore = if entry.Found then entry.Ore else nil
	local detail = refs.Detail
	Pop.repaint(detail, paintOf(ore), false)
	setFx(detail, entry.Found)
	CodexView.paintGem(refs.DetailGem, refs.DetailMark, ore)
	local picture = detail:FindFirstChild("Picture") :: ImageLabel
	picture.Visible = entry.Found
	picture:SetAttribute("Icon", "item_Clean_" .. entry.Ore.Id)
	if entry.Found then
		fillPicture(picture, entry.Ore.Id, true)
	end
	refs.DetailName.Text = text.Name
	refs.DetailName.TextColor3 = if entry.Found then PopTheme.Ink else Color3.fromRGB(176, 184, 204)
	syncShadow(refs.DetailName)
	local info = if text.Rarity then Rarity.ById[text.Rarity] else nil
	local rarityChip = refs.DetailRarity.Parent :: Frame
	refs.DetailRarity.Visible = info ~= nil
	rarityChip.Visible = info ~= nil
	if info then
		refs.DetailRarity.Text = info.Name
		Pop.repaint(rarityChip, deep(Pop.rarityPaint(info.Id)))
	end
	refs.DetailIncome.Text = text.Income
	refs.DetailIncome.TextColor3 = if entry.Found then PopTheme.Money else Color3.fromRGB(206, 214, 232)
	refs.DetailValue.Text = text.Value
	refs.DetailTier.Text = text.Tier
	refs.DetailWhere.Text = text.Where
	refs.DetailLore.Text = text.Lore
end

-- Every tappable thing (for the touch-size tests).
function CodexView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { MenuPanel.holderOf(refs.Frame.Close) }
	for _, card in refs.CardList do
		table.insert(list, card.Button)
	end
	return list
end

return CodexView
