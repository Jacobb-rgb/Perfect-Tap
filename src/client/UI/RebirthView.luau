--[[
	RebirthView: the STAR FORGE window (rebirth B, RebirthConfig), a side
	menu panel in the MenuPanel frame. Pure builder + layout math, so the
	Lune previews draw the same thing.

	  tabs      REBIRTH | STAR SHOP (with your unspent stars)
	  REBIRTH   three columns, each a coloured chip over short rows:
	            YOU LOSE (red), YOU KEEP (blue), YOU GET (green): the
	            exact lists of RebirthConfig.reset (Head Start's level and
	            Podium Keeper change the rows); under them what a rebirth
	            needs and the big REBIRTH! button (grey until your blaster
	            reaches MinBlaster; the first press turns it red "SURE?")
	  STAR SHOP a card per perk: icon, name, what a level does, the level
	            (2/10), and its BUY button with the star price (MAX at the top,
	            grey without the stars)

	setInfo(refs, info) fills both pages from the State's Rebirth field and
	the blaster level. layout(refs, compact, maxWidth, maxHeight) sizes the
	panel (phones and TVs: the compact metrics, every button at least
	MenuPanel.MinTouch points at the phone scale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local Rng = require(Shared.Util.Rng)
local UIKit = require(script.Parent.UIKit)
local MenuPanel = require(script.Parent.MenuPanel)
local TechShopView = require(script.Parent.TechShopView)

local RebirthView = {}

local rgb = Color3.fromRGB

export type Info = {
	Count: number, -- rebirths so far
	Stars: number, -- unspent
	Perks: { [string]: any },
	Level: number, -- the blaster level now
	Ready: boolean,
	StarsNow: number, -- what a rebirth now pays
	Reached: number?, -- the level this run counts (RebirthConfig.reachedOf)
	Glow: string?, -- the Plot Glow colour shown ("" = off)
}

export type Column = { Frame: Frame, Chip: TextLabel, Rows: { TextLabel } }
export type Card = {
	Id: string,
	Frame: Frame,
	Icon: TextLabel,
	Name: TextLabel,
	Text: TextLabel,
	Level: TextLabel,
	Buy: TextButton,
	Pick: TextButton?, -- Plot Glow: the colour shown (a tap picks the next unlocked one)
}

export type Refs = {
	Gui: ScreenGui,
	Frame: MenuPanel.Refs,
	Tabs: { [string]: TextButton },
	Pages: { [string]: Frame },
	Columns: { [string]: Column },
	Need: TextLabel,
	Rebirth: TextButton,
	Message: TextLabel,
	Stars: TextLabel,
	Cards: { Card },
	Tab: string,
	Confirm: boolean,
	Ready: boolean,
	Compact: boolean,
	Laid: boolean, -- layout ran (texts refit when they change)
}

RebirthView.Colors = {
	Rebirth = rgb(160, 168, 255), -- the indigo of the proposal's Rebirth role
	RebirthDark = rgb(60, 64, 172),
	Lose = rgb(236, 84, 70),
	Keep = rgb(96, 186, 255),
	Get = rgb(110, 214, 92),
	Star = rgb(255, 206, 72),
	Off = rgb(120, 108, 100),
	OffDark = rgb(70, 62, 58),
}

RebirthView.Metrics = {
	-- design units: the wanted panel, a column row, the tab row, the REBIRTH! bar
	Normal = { Width = 980, Height = 650, Row = 34, Text = 18, Chip = 34, Tab = 46, Bar = 86, Card = 134, Button = 46 },
	Compact = { Width = 1180, Height = 600, Row = 38, Text = 21, Chip = 40, Tab = 76, Bar = 96, Card = 176, Button = 76 },
}

RebirthView.TabIds = { "Rebirth", "Shop" }
-- compact layouts: the tabs start this far into the body (right of the "STAR FORGE" title)
RebirthView.TitleRoom = 250

-- The rows of the three columns for a save (Head Start's level, Podium Keeper).
function RebirthView.lists(perks: any): { [string]: { string } }
	local start = RebirthConfig.startLevel(perks)
	local open = EnchantConfig.unlockedSlots(start)
	local enchantRow = if open < EnchantConfig.MaxSlots
		then `✨  Enchant slots {open + 1}-{EnchantConfig.MaxSlots} for now`
		else "✨  Enchant slots stay open"
	local keepsPodiums = RebirthConfig.levelOf(perks, "PodiumKeeper") > 0
	return {
		Lose = {
			"💰  Earned coins",
			`🔫  Blaster back to LV {start}`,
			"⛏️  Floors and elevator",
			"⚙️  Machine speed",
			"🚂  Train and backpack levels",
			enchantRow,
			if keepsPodiums then "🪨  Ore (podiums stay)" else "🪨  All your ore",
		},
		Keep = {
			"🏭  Your whole factory",
			"🤖  Golems and enchants",
			"🏺  Artifacts and codex",
			"🛹  Boards and gear",
			"💎  Shards, Robux items",
			"💰  Coins bought with Robux",
			"🏆  Stats and records",
		},
		Get = {
			"⭐  Forge Stars",
			"🔁  A new rebirth",
			"🛒  Star Shop perks",
		},
	}
end

-- What the bottom line says (the requirement, or what a rebirth pays now).
function RebirthView.needText(info: Info): string
	local reached = info.Reached or info.Level
	if info.Ready then
		return `Blaster LV {reached}: a rebirth now pays ⭐ {info.StarsNow}`
	end
	if info.Level >= RebirthConfig.MinBlaster then
		-- a level from the Vault: after the first rebirth the stars want a forged one
		return `Forge blaster LV {RebirthConfig.MinBlaster} at the Foundry to rebirth (Vault cases don't count)`
	end
	return `Reach blaster LV {RebirthConfig.MinBlaster} to rebirth (you have LV {info.Level})`
end

-- A perk card's level text and BUY button text (and whether it can be bought).
function RebirthView.cardText(perks: any, stars: number, id: string): (string, string, boolean)
	local perk = RebirthConfig.ById[id]
	local level = RebirthConfig.levelOf(perks, id)
	local top = if perk then #perk.Costs else 0
	local cost = RebirthConfig.nextCost(perks, id)
	if not cost then
		return `{level}/{top}`, "MAX", false
	end
	return `{level}/{top}`, `⭐ {cost}  BUY`, stars >= cost
end

---------------------------------------------------------------- build

local function chunky(parent: Instance, text: string, color: Color3, dark: Color3, name: string): TextButton
	local button = UIKit.button(parent, text, color, dark, { Name = name, TextSize = 22 })
	return button
end

local function newColumn(parent: Instance, id: string, title: string, color: Color3): Column
	local frame = UIKit.new("Frame", {
		Name = id,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2, color)
	local chip = UIKit.chip(frame, title, color, { Name = "Chip" })
	return { Frame = frame, Chip = chip, Rows = {} }
end

local function newCard(parent: Instance, perk: RebirthConfig.Perk, order: number): Card
	local frame = UIKit.new("Frame", {
		Name = "Perk" .. perk.Id,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2, RebirthView.Colors.RebirthDark)
	local icon = UIKit.label(frame, perk.Icon, 34, { Name = "Icon", TextWrapped = false })
	local name = UIKit.label(frame, perk.Name, 20, {
		Name = "PerkName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local text = UIKit.label(frame, perk.Text, 15, {
		Name = "Text",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local level = UIKit.label(frame, "0/0", 16, { Name = "Level", TextColor3 = RebirthView.Colors.Star, TextWrapped = false })
	local buy = chunky(frame, "BUY", Theme.Good, Theme.GoodDark, "Buy")
	local pick = if perk.Id == "PlotGlow" then chunky(frame, "OFF", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "Pick") else nil
	return { Id = perk.Id, Frame = frame, Icon = icon, Name = name, Text = text, Level = level, Buy = buy, Pick = pick }
end

function RebirthView.build(): Refs
	local frame = MenuPanel.build("TerraForgeRebirth", "STAR FORGE", "Rebirth: start over with your factory and earn Forge Stars")
	local body = frame.Body
	local tabs: { [string]: TextButton } = {}
	tabs.Rebirth = chunky(body, "REBIRTH", RebirthView.Colors.Rebirth, RebirthView.Colors.RebirthDark, "TabRebirth")
	tabs.Shop = chunky(body, "STAR SHOP", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "TabShop")
	local stars = UIKit.label(body, "⭐ 0", 24, {
		Name = "Stars",
		TextColor3 = RebirthView.Colors.Star,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})

	local rebirthPage = UIKit.new("Frame", { Name = "RebirthPage", BackgroundTransparency = 1 }, body)
	local columns: { [string]: Column } = {
		Lose = newColumn(rebirthPage, "Lose", "YOU LOSE", RebirthView.Colors.Lose),
		Keep = newColumn(rebirthPage, "Keep", "YOU KEEP", RebirthView.Colors.Keep),
		Get = newColumn(rebirthPage, "Get", "YOU GET", RebirthView.Colors.Get),
	}
	local lists = RebirthView.lists(nil)
	for id: string, column: Column in columns do
		for i = 1, #lists[id] do
			table.insert(
				column.Rows,
				UIKit.label(column.Frame, "", 18, {
					Name = "Row" .. i,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
				})
			)
		end
	end
	local need = UIKit.label(rebirthPage, "", 18, {
		Name = "Need",
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
	})
	local rebirth = chunky(rebirthPage, "REBIRTH!", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "RebirthButton")
	local message = UIKit.label(rebirthPage, "", 16, { Name = "Message", TextColor3 = Theme.Bad, TextWrapped = true, Visible = false })

	local shopPage = UIKit.new("ScrollingFrame", {
		Name = "ShopPage",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, body)
	UIKit.new("UIGridLayout", {
		Name = "Grid",
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		CellSize = UDim2.fromOffset(300, 116),
	}, shopPage)
	local cards = {}
	for i, perk in RebirthConfig.Perks do
		table.insert(cards, newCard(shopPage, perk, i))
	end

	return {
		Gui = frame.Gui,
		Frame = frame,
		Tabs = tabs,
		Pages = { Rebirth = rebirthPage, Shop = shopPage },
		Columns = columns,
		Need = need,
		Rebirth = rebirth,
		Message = message,
		Stars = stars,
		Cards = cards,
		Tab = "Rebirth",
		Confirm = false,
		Ready = false,
		Compact = false,
		Laid = false,
	}
end

---------------------------------------------------------------- layout

local function rect(object: GuiObject, x: number, y: number, w: number, h: number)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function place(button: TextButton, x: number, y: number, w: number, h: number)
	rect(MenuPanel.holderOf(button), x, y, w, h)
end

-- The metrics of a layout.
function RebirthView.metrics(compact: boolean): typeof(RebirthView.Metrics.Normal)
	return if compact then RebirthView.Metrics.Compact else RebirthView.Metrics.Normal
end

-- Sizes and places everything in the room the panel gets (design units).
-- Normal: the tabs and the star count on top of the body. Compact (phones,
-- TVs): they sit in the header's free room right of the title, so the
-- columns get the whole body. The requirement line and REBIRTH! sit in the
-- YOU GET column (it has the fewest rows).
function RebirthView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	local m = RebirthView.metrics(compact)
	refs.Compact = compact
	refs.Laid = true
	local body = MenuPanel.layout(refs.Frame, compact, m.Width, m.Height, maxWidth, maxHeight)
	local w, h = body.X, body.Y
	-- tabs and the star count
	local tabW = math.min(if compact then 220 else 200, (w - 20) / 3)
	local top: number
	if compact then
		local header = MenuPanel.Metrics.Compact.Header
		local tabY = -header + (header - m.Tab) / 2
		local tabX = RebirthView.TitleRoom
		place(refs.Tabs.Rebirth, tabX, tabY, tabW, m.Tab)
		place(refs.Tabs.Shop, tabX + tabW + 10, tabY, tabW, m.Tab)
		local starsX = tabX + tabW * 2 + 20
		-- up to the X button (it hangs MenuPanel.Pad - 4 from the panel's right edge)
		local starsRight = w + MenuPanel.Pad - (MenuPanel.Pad - 4) - MenuPanel.Metrics.Compact.Close - 8
		rect(refs.Stars, starsX, tabY, math.max(0, starsRight - starsX), m.Tab)
		top = 0
	else
		-- (8 down: the buttons' lip rises 5 toward the subtitle)
		place(refs.Tabs.Rebirth, 0, 8, tabW, m.Tab)
		place(refs.Tabs.Shop, tabW + 10, 8, tabW, m.Tab)
		rect(refs.Stars, tabW * 2 + 20, 8, w - (tabW * 2 + 20), m.Tab)
		top = m.Tab + 18
	end
	refs.Tabs.Rebirth.TextSize = m.Text + 4
	refs.Tabs.Shop.TextSize = m.Text + 4
	refs.Stars.TextSize = m.Text + 8
	local pageH = h - top
	rect(refs.Pages.Rebirth, 0, top, w, pageH)
	rect(refs.Pages.Shop, 0, top, w, pageH)
	-- the three columns
	local gap = 10
	local colW = (w - gap * 2) / 3
	local x = 0
	local getX = 0
	local rowsEnd = 0
	for _, id in { "Lose", "Keep", "Get" } do
		local column = refs.Columns[id]
		rect(column.Frame, x, 0, colW, pageH)
		rect(column.Chip, 10, 8, colW - 20, m.Chip)
		column.Chip.TextSize = m.Text + 2
		for i, row in column.Rows do
			rect(row, 12, 8 + m.Chip + 8 + (i - 1) * m.Row, colW - 24, m.Row)
			TechShopView.fitText(row, colW - 24, m.Row, m.Text, m.Text - 6)
			if id == "Get" then
				rowsEnd = 8 + m.Chip + 8 + i * m.Row
			end
		end
		if id == "Get" then
			getX = x
		end
		x += colW + gap
	end
	-- the requirement line and the button at the bottom of YOU GET
	local buttonY = pageH - m.Button - 12
	local lineY = rowsEnd + 6
	local lineH = math.max(0, buttonY - 8 - lineY)
	rect(refs.Need, getX + 12, lineY, colW - 24, lineH)
	refs.Need.TextSize = m.Text - 1
	rect(refs.Message, getX + 12, lineY, colW - 24, lineH)
	refs.Message.TextSize = m.Text - 1
	place(refs.Rebirth, getX + 12, buttonY, colW - 24, m.Button)
	refs.Rebirth.TextSize = m.Text + 10
	-- the shop's cards: two or three columns
	local columns = if w >= 3 * 300 + 2 * 10 + 8 then 3 else 2
	local cardW = math.floor((w - 8 - (columns - 1) * 10) / columns)
	local grid = refs.Pages.Shop:FindFirstChild("Grid") :: UIGridLayout
	grid.CellSize = UDim2.fromOffset(cardW, m.Card)
	for _, card in refs.Cards do
		rect(card.Icon, 8, 8, 48, 48)
		rect(card.Name, 62, 8, cardW - 62 - 70, 28)
		TechShopView.fitText(card.Name, cardW - 62 - 70, 28, m.Text + 2, m.Text - 4)
		rect(card.Level, cardW - 70, 8, 62, 28)
		card.Level.TextSize = m.Text
		rect(card.Text, 62, 38, cardW - 70, m.Card - 38 - m.Button - 14)
		TechShopView.fitText(card.Text, cardW - 70, m.Card - 38 - m.Button - 14, m.Text - 2, m.Text - 6)
		place(card.Buy, cardW - 190, m.Card - m.Button - 8, 182, m.Button)
		card.Buy.TextSize = m.Text + 2
		local pick = card.Pick
		if pick then
			place(pick, 8, m.Card - m.Button - 8, cardW - 190 - 16, m.Button)
			pick.TextSize = m.Text
		end
	end
end

---------------------------------------------------------------- state

-- Shows one page (and lights its tab).
function RebirthView.setTab(refs: Refs, tab: string)
	refs.Tab = if tab == "Shop" then "Shop" else "Rebirth"
	for _, id in RebirthView.TabIds do
		local on = id == refs.Tab
		refs.Pages[id].Visible = on
		local color = if on then RebirthView.Colors.Rebirth else RebirthView.Colors.Off
		local dark = if on then RebirthView.Colors.RebirthDark else RebirthView.Colors.OffDark
		MenuPanel.style(refs.Tabs[id], color, dark)
	end
end

-- The REBIRTH! button: grey (not ready), indigo, or red "SURE?" (waiting for the second press).
function RebirthView.setConfirm(refs: Refs, on: boolean)
	refs.Confirm = on and refs.Ready
	local button = refs.Rebirth
	if not refs.Ready then
		button.Text = "REBIRTH!"
		MenuPanel.style(button, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
	elseif refs.Confirm then
		button.Text = "SURE?"
		MenuPanel.style(button, Theme.Bad, Theme.BadDark)
	else
		button.Text = "REBIRTH!"
		MenuPanel.style(button, RebirthView.Colors.Rebirth, RebirthView.Colors.RebirthDark)
	end
end

-- A short line in place of the requirement (a refusal), or nil to hide it.
function RebirthView.setMessage(refs: Refs, text: string?)
	refs.Message.Visible = text ~= nil and text ~= ""
	refs.Message.Text = text or ""
	refs.Need.Visible = not refs.Message.Visible
end

-- Fills both pages.
function RebirthView.setInfo(refs: Refs, info: Info)
	local lists = RebirthView.lists(info.Perks)
	lists.Get[1] = if info.Ready then `⭐  {info.StarsNow} Forge Stars` else `⭐  Stars from LV {RebirthConfig.MinBlaster}`
	lists.Get[2] = `🔁  Rebirth #{info.Count + 1}`
	for id, column in refs.Columns do
		for i, row in column.Rows do
			row.Text = lists[id][i] or ""
			if refs.Laid then
				local m = RebirthView.metrics(refs.Compact)
				TechShopView.fitText(row, row.Size.X.Offset, row.Size.Y.Offset, m.Text, m.Text - 6)
			end
		end
	end
	refs.Need.Text = RebirthView.needText(info)
	refs.Need.TextColor3 = if info.Ready then RebirthView.Colors.Get else Theme.TextDim
	refs.Ready = info.Ready
	RebirthView.setConfirm(refs, refs.Confirm)
	refs.Stars.Text = `⭐ {info.Stars}`
	refs.Tabs.Shop.Text = "STAR SHOP"
	for _, card in refs.Cards do
		local level, buy, affordable = RebirthView.cardText(info.Perks, info.Stars, card.Id)
		card.Level.Text = level
		card.Buy.Text = buy
		local pick = card.Pick
		if pick then
			local shown = info.Glow or ""
			local color: RebirthConfig.GlowColor? = nil
			for _, c in RebirthConfig.GlowColors do
				if c.Id == shown then
					color = c
				end
			end
			local picked = color
			if picked then
				pick.Text = string.upper(picked.Name)
				MenuPanel.style(pick, picked.Color:Lerp(Color3.new(0, 0, 0), 0.15), picked.Color:Lerp(Color3.new(0, 0, 0), 0.5))
			else
				pick.Text = "OFF"
				MenuPanel.style(pick, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
			end
			MenuPanel.holderOf(pick).Visible = RebirthConfig.levelOf(info.Perks, card.Id) > 0
		end
		if buy == "MAX" then
			MenuPanel.style(card.Buy, RebirthView.Colors.Star, Theme.AccentDark)
		elseif affordable then
			MenuPanel.style(card.Buy, Theme.Good, Theme.GoodDark)
		else
			MenuPanel.style(card.Buy, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
		end
	end
end

---------------------------------------------------------------- the moment

export type Moment = { Gui: ScreenGui, Flash: Frame, Banner: TextLabel, Paid: TextLabel, Stars: { TextLabel } }

-- The rebirth moment's overlay: a white flash, the banner "REBIRTH n!", the
-- stars it paid and a handful of falling stars (RebirthController animates
-- it; `seed` places the stars).
function RebirthView.buildMoment(count: number, stars: number, seed: number?): Moment
	local gui = UIKit.screen("TerraForgeRebirthMoment", 40)
	gui.IgnoreGuiInset = true
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	}, gui)
	local banner = UIKit.label(gui, `REBIRTH {count}!`, 72, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(900, 110),
		FontFace = Theme.TitleFont,
		TextColor3 = RebirthView.Colors.Star,
		TextWrapped = false,
	})
	UIKit.textStroke(banner, 4)
	local paid = UIKit.label(gui, `+{stars} Forge Stars`, 40, {
		Name = "Paid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(700, 60),
		TextColor3 = Theme.Text,
		TextWrapped = false,
	})
	UIKit.textStroke(paid, 3)
	local rng = Rng.new(seed or 7)
	local list = {}
	for i = 1, 18 do
		local star = UIKit.label(gui, "⭐", rng:int(26, 44), {
			Name = "Star" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:range(0.1, 0.9), rng:range(0.05, 0.95)),
			Size = UDim2.fromOffset(50, 50),
			Rotation = rng:range(-60, 60),
			TextWrapped = false,
		})
		table.insert(list, star)
	end
	return { Gui = gui, Flash = flash, Banner = banner, Paid = paid, Stars = list }
end

-- Every button (touch-size tests: MenuPanel.MinTouch at MenuPanel.PhoneScale).
function RebirthView.buttons(refs: Refs): { TextButton }
	local list = { refs.Tabs.Rebirth, refs.Tabs.Shop, refs.Rebirth }
	for _, card in refs.Cards do
		table.insert(list, card.Buy)
		if card.Pick then
			table.insert(list, card.Pick)
		end
	end
	return list
end

return RebirthView
