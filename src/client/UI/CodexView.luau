--[[
	The ORE CODEX (pure builder + pure helpers; CodexController fills it in).
	Opens from the "Ore Codex" prompt at the ROCK SCANNER terminal (tag
	OreCodex) or the side menu's CODEX button. One MenuPanel:

	  header  ORE CODEX, the count chip "17 / 30 FOUND" with a progress fill
	  grid    all 30 ores (OreData.List order: Common -> Mythic), one card
	          each: a gem in the ore's colour with its glow, the name and a
	          rarity strip; an ore you haven't discovered is a dark gem with
	          "?" and "???". A "NEW" badge marks ores discovered since you
	          last looked (the controller decides which).
	  detail  the selected card: big gem, name, rarity chip, podium income
	          (Rough and Flawless), sell value, the blaster level it needs,
	          where it is found (the WorldLayout zones whose rocks hold it)
	          and its lore. Undiscovered: "???" and how to find it.

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
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
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
	Gem: Frame,
	Mark: TextLabel,
	Name: TextLabel,
	Strip: Frame,
	New: TextLabel,
	Stroke: UIStroke,
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
		CardH = 98,
		Gap = 8,
		DetailW = 300,
		CardText = 14,
		Text = 16,
		Lore = 16,
		Gem = 84,
	},
	-- phones: at uiScale 0.62 a 72-unit card is about 44 pt
	Compact = {
		Width = 1120,
		Height = 640,
		CardW = 80,
		CardH = 88,
		Gap = 8,
		DetailW = 300,
		CardText = 15,
		Text = 18,
		Lore = 17,
		Gem = 72,
	},
} :: { [string]: Metrics }

CodexView.GridInset = 12 -- the grid's left padding, its scroll bar and a little room
CodexView.HiddenColor = Color3.fromRGB(58, 48, 44)
CodexView.HiddenEdge = Color3.fromRGB(96, 84, 76)
CodexView.HiddenName = "???"
CodexView.FindHint = "Not discovered yet. Blast rocks, then clean the dirty ore to find out what it is."

---------------------------------------------------------------- pure helpers

-- Names of the zones whose rocks hold an ore, in world order (deeper later).
function CodexView.zonesOf(oreId: string): { string }
	local names = {}
	for _, zone in WorldLayout.Zones do
		local weight = zone.Ores[oreId]
		if type(weight) == "number" and weight > 0 then
			table.insert(names, zone.Name)
		end
	end
	return names
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

-- "17 / 30 FOUND"
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
	local where = if #entry.Zones > 0 then table.concat(entry.Zones, ", ") else "Deep in the mines"
	return {
		Name = ore.Name,
		Rarity = ore.Rarity,
		Income = `Podium: {Format.perSecond(ore.Income)}  (Flawless {Format.perSecond(flawless)})`,
		Value = `Sells for {Format.money(ore.Value)}`,
		Tier = `Blaster level {ore.Tier}+`,
		Where = `Found in: {where}`,
		Lore = ore.Lore,
	}
end

---------------------------------------------------------------- builders

local function metrics(compact: boolean): Metrics
	return if compact then CodexView.Metrics.Compact else CodexView.Metrics.Normal
end

-- A gem: a rounded square turned 45 degrees in the ore's colour, its glow
-- as the edge, a light glint. Returns the gem frame (inside a holder that
-- stays square to the screen, so the "?" on top isn't turned).
local function gem(parent: Instance, size: number, name: string): (Frame, TextLabel)
	local holder = UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
	}, parent)
	local body = UIKit.new("Frame", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		Rotation = 45,
		BackgroundColor3 = CodexView.HiddenColor,
		BorderSizePixel = 0,
	}, holder)
	UIKit.corner(body, math.max(4, math.floor(size * 0.1)))
	UIKit.new("UIStroke", {
		Name = "Glow",
		Thickness = math.max(2, math.floor(size * 0.05)),
		Color = CodexView.HiddenEdge,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, body)
	UIKit.gradient(body, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	local glint = UIKit.new("Frame", {
		Name = "Glint",
		Position = UDim2.fromScale(0.16, 0.16),
		Size = UDim2.fromScale(0.3, 0.14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, body)
	UIKit.corner(glint, 4)
	local mark = UIKit.label(holder, "?", math.floor(size * 0.42), {
		Name = "Mark",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		ZIndex = 3,
	})
	return body, mark
end

-- Colours a gem for an ore (found) or the dark silhouette.
function CodexView.paintGem(body: Frame, mark: TextLabel, ore: OreData.Ore?)
	local glow = body:FindFirstChild("Glow") :: UIStroke?
	local glint = body:FindFirstChild("Glint") :: Frame?
	if ore then
		body.BackgroundColor3 = ore.Color
		if glow then
			glow.Color = ore.Glow
		end
		if glint then
			glint.Visible = true
		end
		mark.Visible = false
	else
		body.BackgroundColor3 = CodexView.HiddenColor
		if glow then
			glow.Color = CodexView.HiddenEdge
		end
		if glint then
			glint.Visible = false
		end
		mark.Visible = true
	end
end

local function newCard(refs: Refs, ore: OreData.Ore, order: number, m: Metrics)
	local button = UIKit.new("TextButton", {
		Name = "Card" .. ore.Id,
		LayoutOrder = order,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, refs.Grid)
	button:SetAttribute("Ore", ore.Id)
	UIKit.corner(button, 10)
	local stroke = UIKit.stroke(button, 2)
	local body, mark = gem(button, m.CardW * 0.62, "GemHolder")
	local holder = body.Parent :: Frame
	holder.Position = UDim2.new(0.5, 0, 0, 6 + m.CardW * 0.31)
	local name = UIKit.label(button, CodexView.HiddenName, m.CardText, {
		Name = "OreName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -6, 0, 20),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local strip = UIKit.new("Frame", {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -16, 0, 4),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, button)
	UIKit.corner(strip, 2)
	local new = UIKit.chip(button, "NEW", Theme.Good, {
		Name = "NewBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(40, 18),
		TextSize = 12,
		Visible = false,
		ZIndex = 4,
	})
	local card: Card = {
		OreId = ore.Id,
		Button = button,
		Gem = body,
		Mark = mark,
		Name = name,
		Strip = strip,
		New = new,
		Stroke = stroke,
	}
	refs.Cards[ore.Id] = card
	table.insert(refs.CardList, card)
end

function CodexView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local frame = MenuPanel.build("TerraForgeCodex", "ORE CODEX", "Every ore of Terra. Discover them by cleaning dirty ore.", 16)
	local panel = frame.Panel
	local body = frame.Body

	-- the count chip with a progress fill, left of the X button
	local chip = UIKit.new("Frame", {
		Name = "CountChip",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, panel)
	UIKit.corner(chip, 10)
	UIKit.stroke(chip, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.AccentDark,
		BorderSizePixel = 0,
	}, chip)
	UIKit.corner(fill, 10)
	local count = UIKit.label(chip, "0 / 30 FOUND", 20, {
		Name = "Count",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Text,
		TextWrapped = false,
		ZIndex = 2,
	})

	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, body)
	local gridLayout = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(m.CardW, m.CardH),
		CellPadding = UDim2.fromOffset(m.Gap, m.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, grid)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 6),
	}, grid)

	-- the detail pane
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, body)
	UIKit.corner(detail, 12)
	UIKit.stroke(detail, 2)
	local detailGem, detailMark = gem(detail, m.Gem, "BigGem")
	local detailName = UIKit.label(detail, CodexView.HiddenName, 28, {
		Name = "OreName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local detailRarity = UIKit.chip(detail, "Common", Theme.PanelLight, {
		Name = "Rarity",
		Size = UDim2.fromOffset(110, 26),
		TextSize = 16,
	})
	local function line(name: string, color: Color3): TextLabel
		return UIKit.label(detail, "", m.Text, {
			Name = name,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = color,
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
		DetailIncome = line("Income", Theme.Coin),
		DetailValue = line("Value", Theme.Text),
		DetailTier = line("Tier", Theme.Info),
		DetailWhere = line("Where", Theme.Text),
		DetailLore = line("Lore", Theme.TextDim),
		Selected = nil,
		Compact = isCompact,
	}
	for i, ore in OreData.List do
		newCard(refs, ore, i, m)
	end
	CodexView.layout(refs, isCompact, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

-- Fits the codex into the room it gets (design units).
function CodexView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local frame = refs.Frame
	local bodySize = MenuPanel.layout(frame, compact, m.Width, m.Height, maxWidth, maxHeight)
	local mm = if compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal

	-- the count chip left of the X button
	refs.CountChip.Size = UDim2.fromOffset(if compact then 200 else 190, if compact then 48 else 40)
	refs.CountChip.Position = UDim2.new(1, -(MenuPanel.Pad + mm.Close + 12), 0, if compact then 20 else 14)
	refs.Count.TextSize = if compact then 22 else 20
	frame.Title.Size = UDim2.new(1, -(MenuPanel.Pad * 2 + mm.Close + 220), 0, 40)
	frame.Subtitle.Size = UDim2.new(1, -(MenuPanel.Pad * 2 + mm.Close + 220), 0, 20)

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
	for _, card in refs.CardList do
		card.Name.TextSize = m.CardText
	end

	-- the detail pane: gem + name + rarity on top, then the lines
	refs.Detail.Position = UDim2.new(1, 0, 0, 0)
	refs.Detail.Size = UDim2.new(0, detailW, 1, -4)
	local holder = refs.DetailGem.Parent :: Frame
	holder.Size = UDim2.fromOffset(m.Gem, m.Gem)
	holder.Position = UDim2.fromOffset(10 + m.Gem / 2, 8 + m.Gem / 2)
	refs.DetailMark.TextSize = math.floor(m.Gem * 0.42)
	local textX = 18 + m.Gem
	refs.DetailName.Position = UDim2.fromOffset(textX, 14)
	refs.DetailName.Size = UDim2.new(1, -(textX + 10), 0, 34)
	refs.DetailName.TextSize = if compact then 26 else 28
	refs.DetailRarity.Position = UDim2.fromOffset(textX, 52)
	local inner = detailW - 28
	local y = 16 + m.Gem
	local function place(label: TextLabel, lines: number, size: number)
		label.TextSize = size
		label.Position = UDim2.fromOffset(14, y)
		label.Size = UDim2.fromOffset(inner, lines * (size + 4))
		y += lines * (size + 4) + 4
	end
	place(refs.DetailIncome, 2, m.Text)
	place(refs.DetailValue, 1, m.Text)
	place(refs.DetailTier, 1, m.Text)
	place(refs.DetailWhere, 2, m.Text)
	y += 2
	refs.DetailLore.TextSize = m.Lore
	refs.DetailLore.Position = UDim2.fromOffset(14, y)
	refs.DetailLore.Size = UDim2.new(0, inner, 1, -(y + 8))
end

---------------------------------------------------------------- filling in

-- Shows the entries on the cards and the count.
function CodexView.setEntries(refs: Refs, entries: { Entry })
	for _, entry in entries do
		local card = refs.Cards[entry.Ore.Id]
		if card then
			local info = Rarity.ById[entry.Ore.Rarity]
			CodexView.paintGem(card.Gem, card.Mark, if entry.Found then entry.Ore else nil)
			card.Name.Text = if entry.Found then entry.Ore.Name else CodexView.HiddenName
			card.Name.TextColor3 = if entry.Found then Theme.Text else Theme.TextDim
			card.Strip.BackgroundColor3 = if entry.Found and info then info.Color else Theme.PanelLight
			card.New.Visible = entry.New
			card.Button:SetAttribute("Found", entry.Found)
		end
	end
	local found, total = CodexView.count(entries)
	refs.Count.Text = CodexView.countText(found, total)
	refs.CountFill.Size = UDim2.fromScale(if total > 0 then found / total else 0, 1)
end

-- Shows one entry in the detail pane and marks its card.
function CodexView.select(refs: Refs, entry: Entry)
	refs.Selected = entry.Ore.Id
	for _, card in refs.CardList do
		local on = card.OreId == entry.Ore.Id
		card.Stroke.Color = if on then Theme.Accent else Theme.Outline
		card.Stroke.Thickness = if on then 3 else 2
	end
	local text = CodexView.detailText(entry)
	CodexView.paintGem(refs.DetailGem, refs.DetailMark, if entry.Found then entry.Ore else nil)
	refs.DetailName.Text = text.Name
	refs.DetailName.TextColor3 = if entry.Found then Theme.Text else Theme.TextDim
	local info = if text.Rarity then Rarity.ById[text.Rarity] else nil
	refs.DetailRarity.Visible = info ~= nil
	if info then
		refs.DetailRarity.Text = info.Name
		refs.DetailRarity.BackgroundColor3 = info.DarkColor
	end
	refs.DetailIncome.Text = text.Income
	refs.DetailIncome.TextColor3 = if entry.Found then Theme.Coin else Theme.TextDim
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
