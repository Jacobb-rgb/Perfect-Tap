--[[
	The golem capsule screens (pure builders + pure helpers;
	CapsuleController fills them in).

	Shop panel (ScreenGui "TerraForgeCapsules"):
	  header   GOLEM CAPSULES, a line about odds, your coins, MY GOLEMS, X
	  tabs     one per capsule the player may open (LB / RB on a gamepad):
	           STONE · CRYSTAL · ROYAL. Hidden where it isn't allowed: the
	           Royal capsule (Robux) where paid random items are restricted
	           or the policy isn't known yet, coin capsules too while coins
	           can be bought with Robux (CapsuleConfig.isPaidRandom).
	  left     the capsule (drawn from frames), its name and description, the
	           Triple Lucky banner while it runs, OPEN x1 / x3 / x10 with the
	           price of each (coins at the player's blaster level; Royal:
	           Robux per button, a greyed "Coming soon" button while that
	           product's id is a placeholder or step 8's receipts aren't
	           ready, and "Coming soon!" instead of the buttons when none of
	           them is live), a status line and the golem room ("Golems 12 / 60")
	  right    the EXACT odds of every golem in the capsule: rarity color,
	           name, rarity, bonus, chance (CapsuleConfig.odds; with Triple
	           Lucky on, the boosted odds, the lucky golems marked "x3")
	  footer   the control hint (not on phones)
	cards(state, coins, restricted, now, stateAt?, receipts?) says what each tab shows,
	from the State snapshot, so the cards always match what the server
	quotes (luckyNow: the Triple Lucky odds the client shows and sends with
	every open). layout() sets every size, position AND text size from the
	normal or compact metrics, so a panel built for one layout and laid out
	for the other looks exactly like one built for it.

	Opening overlay (ScreenGui "TerraForgeCapsuleOpen", above everything):
	  a dim backdrop, rotating rarity rays, the ViewportFrame "Hero" (the
	  controller animates the capsule and the golems in it), a full-screen
	  flash, the name plate (name, rarity, NEW!, bonus), a counter (2 / 3),
	  the result grid (x3: 3 cards, x10: 5 x 2) and SKIP / OK / OPEN AGAIN
	  (in the "Controls" frame, a SelectionGroup that stops at its edges: a
	  gamepad never leaves the overlay for the shop behind it).

	fillBoard(gui, capsuleId, lucky): the CapsuleStall's OddsBoard
	SurfaceGui (a 1.9 x 3.9 stud board): the capsule's name and, big, each
	rarity's total chance on the six rows the stall's rarity chips mark;
	each golem's own chance is in the capsule menu (the board says so).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local LightSkin = require(script.Parent.LightSkin)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)
local GolemView = require(script.Parent.GolemView)
local TechShopView = require(script.Parent.TechShopView)

local CapsuleView = {}

CapsuleView.PhoneScale = TechShopView.PhoneScale
-- the odds list's columns: shares of the room left of the chance for the name and the rarity (the bonus gets the rest)
CapsuleView.Columns = { 0.41, 0.25 }
-- a RARITY column narrower than this can't show "Legendary" readably: the list
-- drops it (the coloured bar and the name's colour show the rarity) and the
-- name and bonus share the room (oddsColumns; small phones)
CapsuleView.RarityMinWidth = 80
CapsuleView.MinTouch = TechShopView.MinTouch
CapsuleView.Separator = "  •  "
CapsuleView.BoardAttribute = "CapsuleBoard" -- on every instance fillBoard adds (old labels don't have it)
-- fillBoard's columns (x, width as shares of the board) on the stall's own
-- grid (Districts/Capsules.luau): the stall's neon RarityChip parts stand in
-- front of the Marker column, so the names and totals start right of them
CapsuleView.BoardColumns = {
	Marker = { 0.08, 0.13 },
	Row = { 0.27, 0.31 },
	Total = { 0.6, 0.35 },
} :: { [string]: { number } }
-- ReplicatedStorage attribute: step 8's receipts are handled (the one receipts
-- gate, src/server/Receipts.luau; = CapsuleService.ReceiptsAttribute)
CapsuleView.ReceiptsAttribute = MonetizationConfig.ReceiptsAttribute

export type OddsLine = {
	Golem: string,
	Name: string,
	Rarity: string,
	Color: Color3,
	Chance: number,
	Text: string, -- "0.07%"
	Lucky: boolean, -- tripled by Triple Lucky (only while it runs)
	Bonus: string,
}

export type Buy = {
	Count: number,
	Text: string, -- "OPEN 3"
	Price: number?, -- coins (nil for Robux)
	PriceText: string, -- "$7.5K" / "R$ 139"
	CanBuy: boolean,
	Reason: string?, -- CapsuleConfig.Reasons code or "ComingSoon"
}

export type Card = {
	Id: string,
	Name: string,
	Description: string,
	Color: Color3,
	Glow: Color3,
	Visible: boolean,
	Robux: boolean,
	Live: boolean, -- at least one Robux button can be bought (real id, receipts ready; coin capsules: true)
	Lucky: boolean, -- Triple Lucky runs: the odds include it
	LuckySeconds: number,
	LuckyFrom: string,
	Buys: { Buy },
	Note: string?, -- shown instead of the buttons ("Coming soon!" when no Robux button is live)
	Room: number, -- free golem places
	Owned: number,
	Odds: { OddsLine },
}

export type Row = {
	Frame: Frame,
	Bar: Frame,
	Name: TextLabel,
	Rarity: TextLabel,
	Bonus: TextLabel,
	Chance: TextLabel,
	Lucky: TextLabel,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Balance: Frame,
	BalanceAmount: TextLabel,
	Golems: TextButton,
	Close: TextButton,
	TabBar: Frame,
	Tabs: { [string]: TextButton },
	TabGlyphs: { ImageLabel },
	Left: Frame,
	ArtHolder: Frame,
	CapsuleName: TextLabel,
	Description: TextLabel,
	LuckyBanner: Frame,
	LuckyText: TextLabel,
	Buttons: { TextButton },
	Note: TextLabel,
	Status: TextLabel,
	Room: TextLabel,
	Right: Frame,
	OddsTitle: TextLabel,
	OddsNote: TextLabel,
	Heads: Frame,
	List: ScrollingFrame,
	Rows: { Row },
	Hint: TextLabel,
	Empty: TextLabel,
	Tab: string,
	ArtFor: string?,
	Compact: boolean,
}

export type Cell = { Frame: Frame, Scale: UIScale, Kind: string }

export type OpenRefs = {
	Gui: ScreenGui,
	Dim: TextButton,
	Rays: Frame,
	Hero: ViewportFrame,
	Camera: Camera,
	Flash: Frame,
	Plate: Frame,
	PlateName: TextLabel,
	PlateRarity: TextLabel,
	PlateNew: TextLabel,
	PlateBonus: TextLabel,
	Counter: TextLabel,
	Note: TextLabel,
	Grid: Frame,
	GridLayout: UIGridLayout,
	GridRoom: Vector2, -- the room the grid may take (layoutOpening)
	Cells: { Cell },
	Controls: Frame, -- SKIP / OK / OPEN AGAIN (a SelectionGroup)
	Skip: TextButton,
	Ok: TextButton,
	Again: TextButton,
	Hint: TextLabel,
	Compact: boolean,
}

local rgb = Color3.fromRGB
local DARK = rgb(26, 22, 26)
local LUCKY = rgb(255, 206, 72)
local LUCKY_DARK = rgb(170, 120, 20)

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	TabBar: number,
	TabHeight: number,
	TabWidth: number,
	Footer: number,
	Left: number,
	Art: Vector2,
	Button: number,
	Close: number,
	Row: number,
	Title: number,
	Text: number,
	Small: number,
}

local PAD = 16
local GAP = 10

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 900,
		Height = 580,
		Header = 74,
		TabBar = 60,
		TabHeight = 48,
		TabWidth = 170,
		Footer = 30,
		Left = 330,
		Art = Vector2.new(104, 150),
		Button = 64,
		Close = 54,
		Row = 23,
		Title = 32,
		Text = 17,
		Small = 14,
	},
	-- phones and TVs: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1180,
		Height = 600,
		Header = 76,
		TabBar = 84,
		TabHeight = 72,
		TabWidth = 210,
		Footer = 6,
		Left = 400,
		Art = Vector2.new(84, 120),
		Button = 76,
		Close = 72,
		Row = 32,
		Title = 34,
		Text = 20,
		Small = 17,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

local function num(v: any): number
	return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0
end

-- "25%", "23.19%", "0.07%", "0.0465%": the exact chance, three significant
-- digits (at least two decimals), trailing zeros cut.
function CapsuleView.percent(chance: number): string
	local p = num(chance) * 100
	if p <= 0 then
		return "0%"
	end
	local decimals = math.max(2, 2 - math.floor(math.log10(p)))
	local text = string.format(`%.{math.min(decimals, 8)}f`, p)
	if text:find("%.") then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text .. "%"
end

-- The exact odds of a capsule, one line per golem (CapsuleConfig.odds order).
function CapsuleView.oddsLines(capsuleId: string, lucky: boolean): { OddsLine }
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule then
		return {}
	end
	local from = Rarity.ById[capsule.LuckyFrom].Order
	local lines: { OddsLine } = {}
	for _, line in CapsuleConfig.odds(capsuleId, lucky) do
		local golem = GolemConfig.ById[line.Golem]
		if golem then
			table.insert(lines, {
				Golem = line.Golem,
				Name = golem.Name,
				Rarity = golem.Rarity,
				Color = Rarity.ById[golem.Rarity].Color,
				Chance = line.Chance,
				Text = CapsuleView.percent(line.Chance),
				Lucky = lucky and GolemConfig.order(line.Golem) >= from,
				Bonus = GolemConfig.describe(line.Golem),
			})
		end
	end
	return lines
end

-- Seconds left of the Triple Lucky boost in the snapshot at `now` (server time).
function CapsuleView.luckySeconds(state: any, now: number): number
	local boosts = if type(state) == "table" then state.Boosts else nil
	return BoostConfig.remaining(boosts, "TripleLucky", now)
end

--[[
	Does the player get the Triple Lucky odds at `now` (server time)? The
	boost in the snapshot (Boosts.TripleLuckyUntil) or any other source the
	server counts (State.Bonuses.TripleLucky, CapsuleService.oddsFor).
	`stateAt`: when the snapshot came (server time). The Bonuses flag was
	right then, so it is trusted only if the boost didn't run then (else it
	may be the boost's own flag, stale once the boost ran out). nil: trusted.
]]
function CapsuleView.luckyNow(state: any, now: number, stateAt: number?): boolean
	local boosts = if type(state) == "table" then state.Boosts else nil
	local untilTime = BoostConfig.untilOf(boosts, "TripleLucky")
	if untilTime > now then
		return true
	end
	local bonuses = if type(state) == "table" then state.Bonuses else nil
	if type(bonuses) ~= "table" or bonuses.TripleLucky ~= true then
		return false
	end
	return stateAt == nil or untilTime <= stateAt
end

local function golemsOf(state: any): any
	return if type(state) == "table" then state.Golems else nil
end

-- May the player see / open this capsule (see the header)?
function CapsuleView.visible(capsuleId: string, restricted: boolean): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule then
		return false
	end
	return not (restricted and CapsuleConfig.isPaidRandom(capsuleId))
end

-- What every capsule tab shows (see the header). `restricted`: paid random
-- items are restricted for this player, or the policy isn't known yet.
-- `stateAt`: when the snapshot came (luckyNow). `receipts`: step 8 takes
-- Royal receipts (ReceiptsAttribute; nil = not yet): a Robux button is
-- live only with a real product id AND receipts.
function CapsuleView.cards(
	state: any,
	coins: number,
	restricted: boolean,
	now: number,
	stateAt: number?,
	receipts: boolean?
): { Card }
	-- coin prices follow State.PriceLevel (BlasterData.priceLevel: a rebirth never lowers them)
	local level = if type(state) == "table" then (if state.PriceLevel ~= nil then state.PriceLevel else state.BlasterLevel) else nil
	local room = GolemConfig.room(golemsOf(state))
	local owned = GolemConfig.count(golemsOf(state))
	local luckySeconds = CapsuleView.luckySeconds(state, now)
	local lucky = CapsuleView.luckyNow(state, now, stateAt)
	local cash = num(coins)
	local cards: { Card } = {}
	for _, capsule in CapsuleConfig.List do
		local robux = capsule.Currency == "Robux"
		local buys: { Buy } = {}
		local live = not robux -- Robux: decided per button below
		for _, count in CapsuleConfig.Counts do
			if robux then
				local key = CapsuleConfig.product(capsule.Id, count)
				local product = if key then MonetizationConfig.get(key) else nil
				local isLive = key ~= nil and MonetizationConfig.keyLive(key) and receipts == true
				live = live or isLive
				local reason: string? = if not isLive then "ComingSoon" elseif room < count then "InventoryFull" else nil
				table.insert(buys, {
					Count = count,
					Text = `OPEN {count}`,
					Price = nil,
					PriceText = if not isLive then "Coming soon" elseif product then `R$ {product.Robux}` else "",
					CanBuy = reason == nil,
					Reason = reason,
				})
			else
				local price = CapsuleConfig.price(capsule.Id, count, level) or math.huge
				local reason: string? = if room < count then "InventoryFull" elseif cash < price then "NoCoins" else nil
				table.insert(buys, {
					Count = count,
					Text = `OPEN {count}`,
					Price = price,
					PriceText = Format.money(price),
					CanBuy = reason == nil,
					Reason = reason,
				})
			end
		end
		table.insert(cards, {
			Id = capsule.Id,
			Name = capsule.Name,
			Description = capsule.Description,
			Color = capsule.Color,
			Glow = capsule.Glow,
			Visible = CapsuleView.visible(capsule.Id, restricted),
			Robux = robux,
			Live = live,
			Lucky = lucky,
			LuckySeconds = luckySeconds,
			LuckyFrom = capsule.LuckyFrom,
			Buys = buys,
			Note = if robux and not live then MonetizationConfig.StatusText.ComingSoon else nil,
			Room = room,
			Owned = owned,
			Odds = CapsuleView.oddsLines(capsule.Id, lucky),
		})
	end
	return cards
end

-- Refusals CapsuleConfig.Reasons doesn't list yet (CapsuleService's own).
CapsuleView.ExtraReasons = {
	OddsChanged = "The odds just changed: check them and open again",
} :: { [string]: string }

-- The text for a refusal (CapsuleConfig.Reasons, MonetizationConfig.StatusText).
function CapsuleView.reasonText(reason: any): string
	if type(reason) == "string" then
		local text = CapsuleConfig.Reasons[reason] or CapsuleView.ExtraReasons[reason] or MonetizationConfig.StatusText[reason]
		if text and text ~= "" then
			return text
		end
	end
	return "You can't open that right now"
end

-- The Triple Lucky banner: "TRIPLE LUCKY 12:34  •  EPIC+ x3" (time left,
-- when it comes from the boost; the golems it triples).
function CapsuleView.luckyText(card: Card): string
	local from = string.upper(card.LuckyFrom)
	local left = if card.LuckySeconds > 0 then ` {Format.seconds(card.LuckySeconds)}` else ""
	return `TRIPLE LUCKY{left}{CapsuleView.Separator}{from}+ x3`
end

---------------------------------------------------------------- the capsule drawn from frames

-- A capsule (pill) drawn from frames in a w x h box (the shop's art).
function CapsuleView.art(parent: Instance, capsuleId: string, w: number, h: number): Frame
	local capsule = CapsuleConfig.ById[capsuleId]
	local color = if capsule then capsule.Color else rgb(150, 140, 130)
	local glow = if capsule then capsule.Glow else rgb(255, 170, 80)
	local top = color:Lerp(Color3.new(1, 1, 1), 0.55)
	local box = UIKit.new("Frame", {
		Name = "Art",
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
	}, parent)
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.9, 0.08),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, box)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shadow)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.86, 0.92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, box)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	UIKit.stroke(pill, 3)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.49, top),
			ColorSequenceKeypoint.new(0.51, color),
			ColorSequenceKeypoint.new(1, color:Lerp(DARK, 0.2)),
		}),
	}, pill)
	local band = UIKit.new("Frame", {
		Name = "Band",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 6, 0.07, 0),
		BackgroundColor3 = glow,
		BorderSizePixel = 0,
	}, pill)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, band)
	UIKit.stroke(band, 2)
	local window = UIKit.new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.34, 0.16),
		BackgroundColor3 = glow:Lerp(Color3.new(1, 1, 1), 0.3),
		BorderSizePixel = 0,
	}, pill)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, window)
	UIKit.stroke(window, 2, color:Lerp(DARK, 0.4))
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Position = UDim2.fromScale(0.17, 0.1),
		Size = UDim2.fromScale(0.1, 0.26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, pill)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	return box
end

---------------------------------------------------------------- shop panel

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- A button's look: enabled in its colors, or greyed out.
function CapsuleView.style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holderOf(button).BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end

local function newRow(refs: Refs, index: number, m: Metrics): Row
	local frame = UIKit.new("Frame", {
		Name = "Row" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, -10, 0, m.Row),
		BackgroundColor3 = if index % 2 == 0 then Theme.PanelLight else Theme.PanelDark,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, refs.List)
	UIKit.corner(frame, 6)
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.new(0, 4, 0.5, -(m.Row - 10) / 2),
		Size = UDim2.fromOffset(8, m.Row - 10),
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(bar, 3)
	local function cell(name: string, size: number, align: Enum.TextXAlignment): TextLabel
		return UIKit.label(frame, "", size, {
			Name = name,
			TextXAlignment = align,
			TextWrapped = false,
			-- never runs into the next cell (fitText shrinks it first)
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local row: Row = {
		Frame = frame,
		Bar = bar,
		Name = cell("GolemName", m.Text - 1, Enum.TextXAlignment.Left),
		Rarity = cell("Rarity", m.Small, Enum.TextXAlignment.Left),
		Bonus = cell("Bonus", m.Small, Enum.TextXAlignment.Left),
		Chance = cell("Chance", m.Text - 1, Enum.TextXAlignment.Right),
		Lucky = UIKit.chip(frame, "x3", LUCKY, {
			Name = "Lucky",
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = m.Small - 1,
			Visible = false,
		}),
	}
	row.Bonus.TextColor3 = Theme.TextDim
	refs.Rows[index] = row
	return row
end

-- The odds list's GOLEM / RARITY / BONUS widths for `rest` units (RARITY 0
-- = dropped: too narrow to read, see RarityMinWidth).
function CapsuleView.oddsColumns(rest: number): (number, number, number)
	local nameW = math.floor(rest * CapsuleView.Columns[1])
	local rarityW = math.floor(rest * CapsuleView.Columns[2])
	if rarityW < CapsuleView.RarityMinWidth then
		nameW = math.floor(rest * 0.5)
		rarityW = 0
	end
	return nameW, rarityW, rest - nameW - rarityW
end

-- Places a row's cells for a list `width` wide.
local function placeRow(row: Row, m: Metrics, width: number)
	local h = m.Row
	local chanceW = if m.Row > 28 then 120 else 96
	local luckyW = 34
	local rest = width - 20 - chanceW - luckyW - 12
	local nameW, rarityW, bonusW = CapsuleView.oddsColumns(rest)
	row.Rarity.Visible = rarityW > 0
	row.Frame.Size = UDim2.new(1, -10, 0, h)
	row.Bar.Position = UDim2.new(0, 4, 0.5, -(h - 10) / 2)
	row.Bar.Size = UDim2.fromOffset(8, h - 10)
	row.Lucky.TextSize = m.Small - 1
	row.Name.Position = UDim2.fromOffset(18, 0)
	row.Name.Size = UDim2.fromOffset(nameW, h)
	row.Rarity.Position = UDim2.fromOffset(18 + nameW, 0)
	row.Rarity.Size = UDim2.fromOffset(rarityW, h)
	row.Bonus.Position = UDim2.fromOffset(18 + nameW + rarityW, 0)
	row.Bonus.Size = UDim2.fromOffset(bonusW, h)
	row.Lucky.Position = UDim2.new(1, -(chanceW + 8), 0.5, 0)
	row.Lucky.Size = UDim2.fromOffset(luckyW, h - 8)
	row.Chance.AnchorPoint = Vector2.new(1, 0)
	row.Chance.Position = UDim2.new(1, -6, 0, 0)
	row.Chance.Size = UDim2.fromOffset(chanceW - 6, h)
end

function CapsuleView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local gui = UIKit.screen("TerraForgeCapsules", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		Active = true,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local title = UIKit.label(panel, "GOLEM CAPSULES", m.Title, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, "Each capsule wakes a sleeping golem: the odds of every golem are listed.", m.Small + 1, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, { Name = "Close", TextSize = 26 })
	local golems = UIKit.button(panel, "MY GOLEMS", Theme.Info, rgb(50, 110, 170), { Name = "MyGolems", TextSize = 19 })
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(balance, 10)
	UIKit.stroke(balance, 2)
	local coin = HudView.coinIcon(balance, 26)
	coin.Position = UDim2.fromOffset(8, 7)
	local balanceAmount = UIKit.label(balance, "$0", 22, {
		Name = "Amount",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -46, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- tabs: one per capsule
	local tabBar = UIKit.new("Frame", { Name = "TabBar", BackgroundTransparency = 1 }, panel)
	UIKit.list(tabBar, Enum.FillDirection.Horizontal, GAP, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local tabs: { [string]: TextButton } = {}
	for i, capsule in CapsuleConfig.List do
		tabs[capsule.Id] = UIKit.button(tabBar, string.upper(capsule.Id), capsule.Color, capsule.Color:Lerp(DARK, 0.45), {
			Name = "Tab" .. capsule.Id,
			LayoutOrder = i,
			TextSize = if isCompact then 24 else 21,
		})
	end
	local glyphs: { ImageLabel } = {}
	for _, name in { "GlyphL", "GlyphR" } do
		table.insert(
			glyphs,
			UIKit.new("ImageLabel", {
				Name = name,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(34, 34),
				Visible = false,
				ZIndex = 4,
			}, panel)
		)
	end

	-- left: the capsule and its buttons
	local left = UIKit.new("Frame", { Name = "Left", BackgroundTransparency = 1 }, panel)
	local artHolder = UIKit.new("Frame", { Name = "ArtHolder", BackgroundTransparency = 1 }, left)
	local capsuleName = UIKit.label(left, "", m.Text + 7, {
		Name = "CapsuleName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local description = UIKit.label(left, "", m.Small, {
		Name = "Description",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local luckyBanner = UIKit.new("Frame", {
		Name = "LuckyBanner",
		BackgroundColor3 = LUCKY,
		BorderSizePixel = 0,
		Visible = false,
	}, left)
	UIKit.corner(luckyBanner, 10)
	UIKit.stroke(luckyBanner, 2, LUCKY_DARK)
	local luckyText = UIKit.label(luckyBanner, "", m.Small, {
		Name = "Text",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		TextWrapped = false,
	})
	local buttons: { TextButton } = {}
	for i, count in CapsuleConfig.Counts do
		local button = UIKit.button(left, `OPEN {count}`, Theme.Good, Theme.GoodDark, {
			Name = "Open" .. count,
			LayoutOrder = i,
			TextSize = if isCompact then 21 else 18,
		})
		button.TextWrapped = true
		button.LineHeight = 1.05
		table.insert(buttons, button)
	end
	local note = UIKit.label(left, "", m.Text + 4, {
		Name = "Note",
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		Visible = false,
	})
	local status = UIKit.label(left, "", m.Small, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Info,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local room = UIKit.label(left, "", m.Small, {
		Name = "Room",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})

	-- right: the odds
	local right = UIKit.new("Frame", {
		Name = "Right",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(right, 12)
	UIKit.stroke(right, 2)
	local oddsTitle = UIKit.label(right, "ODDS FOR EACH CAPSULE", m.Text, {
		Name = "OddsTitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local oddsNote = UIKit.label(right, "", m.Small - 1, {
		Name = "OddsNote",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local heads = UIKit.new("Frame", { Name = "Heads", BackgroundTransparency = 1 }, right)
	for _, k in { { "HeadGolem", "GOLEM" }, { "HeadRarity", "RARITY" }, { "HeadBonus", "BONUS" }, { "HeadChance", "CHANCE" } } do
		UIKit.label(heads, k[2], m.Small - 2, {
			Name = k[1],
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
			TextXAlignment = if k[1] == "HeadChance" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		})
	end
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		-- a gamepad can scroll the odds (it has nothing to press)
		Selectable = true,
	}, right)
	UIKit.list(list, Enum.FillDirection.Vertical, 1)

	local hint = UIKit.label(panel, "", m.Small, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local empty = UIKit.label(panel, "Capsules aren't available where you play.", m.Text + 2, {
		Name = "Empty",
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Balance = balance,
		BalanceAmount = balanceAmount,
		Golems = golems,
		Close = close,
		TabBar = tabBar,
		Tabs = tabs,
		TabGlyphs = glyphs,
		Left = left,
		ArtHolder = artHolder,
		CapsuleName = capsuleName,
		Description = description,
		LuckyBanner = luckyBanner,
		LuckyText = luckyText,
		Buttons = buttons,
		Note = note,
		Status = status,
		Room = room,
		Right = right,
		OddsTitle = oddsTitle,
		OddsNote = oddsNote,
		Heads = heads,
		List = list,
		Rows = {},
		Hint = hint,
		Empty = empty,
		Tab = CapsuleConfig.List[1].Id,
		ArtFor = nil,
		Compact = isCompact,
	}
	CapsuleView.layout(refs, isCompact, math.huge, math.huge)
	return refs
end

local function place(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function placeButton(button: TextButton, x: number, y: number, w: number, h: number)
	local holder = holderOf(button)
	holder.AnchorPoint = Vector2.new(0, 0)
	place(holder, x, y, w, h)
end

--[[
	Fits the panel into `maxWidth` x `maxHeight` design units: the normal or
	compact metrics, shrunk to the space the screen has.
]]
function CapsuleView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	local m = metrics(compact)
	local width = math.max(math.min(m.Width, maxWidth - 16), m.Left + 420)
	local height = math.max(math.min(m.Height, maxHeight - 12), 400)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	if refs.Compact ~= compact then
		-- the capsule art is drawn at the layout's size: draw it again
		refs.ArtHolder:ClearAllChildren()
		refs.ArtFor = nil
	end
	refs.Compact = compact

	-- every text size from the metrics (the build's sizes are only a start)
	for _, tab in refs.Tabs do
		tab.TextSize = if compact then 24 else 21
	end
	for _, button in refs.Buttons do
		button.TextSize = if compact then 21 else 18
	end
	refs.Golems.TextSize = if compact then 21 else 19
	refs.Note.TextSize = m.Text + 4
	refs.Status.TextSize = m.Small
	refs.Room.TextSize = m.Small
	refs.LuckyText.TextSize = m.Small
	refs.OddsTitle.TextSize = m.Text
	refs.OddsNote.TextSize = m.Small - 1
	for _, child in refs.Heads:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextSize = m.Small - (if compact then 1 else 2)
		end
	end
	refs.Hint.TextSize = m.Small
	refs.Empty.TextSize = m.Text + 2

	-- header: title + subtitle left, coins / MY GOLEMS / X right
	local h = m.Header
	local closeHolder = holderOf(refs.Close)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -PAD, 0, (h - m.Close) / 2 + 3)
	closeHolder.Size = UDim2.fromOffset(m.Close, m.Close)
	local golemsW = if compact then 200 else 150
	local golemsH = if compact then m.Close else 48
	local golemsHolder = holderOf(refs.Golems)
	golemsHolder.AnchorPoint = Vector2.new(1, 0)
	golemsHolder.Position = UDim2.new(1, -(PAD + m.Close + GAP), 0, (h - golemsH) / 2 + 3)
	golemsHolder.Size = UDim2.fromOffset(golemsW, golemsH)
	local balanceW = if compact then 190 else 160
	refs.Balance.AnchorPoint = Vector2.new(1, 0)
	refs.Balance.Position = UDim2.new(1, -(PAD + m.Close + 2 * GAP + golemsW), 0, (h - 40) / 2)
	refs.Balance.Size = UDim2.fromOffset(balanceW, 40)
	local textW = width - (2 * PAD + m.Close + 3 * GAP + golemsW + balanceW)
	place(refs.Title, PAD + 4, 8, textW, m.Title + 4)
	place(refs.Subtitle, PAD + 4, 8 + m.Title + 4, textW, 20)
	refs.Subtitle.Visible = textW > 260
	TechShopView.fitText(refs.Title, textW, m.Title + 4, m.Title, 20)
	TechShopView.fitText(refs.Subtitle, textW, 20, m.Small + 1, 11)

	-- tabs
	local tabY = h
	place(refs.TabBar, PAD + 40, tabY, width - 2 * PAD - 80, m.TabBar)
	for _, tab in refs.Tabs do
		local holder = holderOf(tab)
		holder.Size = UDim2.fromOffset(m.TabWidth, m.TabHeight)
	end
	refs.TabGlyphs[1].Position = UDim2.fromOffset(PAD + 18, tabY + m.TabBar / 2)
	refs.TabGlyphs[2].Position = UDim2.new(1, -(PAD + 18), 0, tabY + m.TabBar / 2)

	-- body
	local bodyY = tabY + m.TabBar + 4
	local bodyH = height - bodyY - m.Footer - 6
	local leftW = m.Left
	place(refs.Left, PAD, bodyY, leftW, bodyH)
	local art = m.Art
	place(refs.ArtHolder, 0, 4, art.X, art.Y)
	local textX = art.X + 12
	local nameH = m.Text + 12
	place(refs.CapsuleName, textX, 4, leftW - textX, nameH)
	place(refs.Description, textX, 4 + nameH, leftW - textX, art.Y - nameH)
	TechShopView.fitText(refs.Description, leftW - textX, art.Y - nameH, m.Small, 11)
	local y = art.Y + 12
	local bannerH = if compact then 40 else 36
	place(refs.LuckyBanner, 0, y, leftW, bannerH)
	-- the three OPEN buttons side by side; the room and status lines under them
	local statusH = 22
	local buttonsY = math.min(y + bannerH + 10, bodyH - m.Button - 2 * statusH - 10)
	local buttonW = math.floor((leftW - 2 * GAP) / 3)
	for i, button in refs.Buttons do
		placeButton(button, (i - 1) * (buttonW + GAP), buttonsY + 5, buttonW, m.Button)
	end
	place(refs.Note, 0, buttonsY, leftW, m.Button)
	place(refs.Status, 0, buttonsY + m.Button + 10, leftW, statusH)
	place(refs.Room, 0, buttonsY + m.Button + 10 + statusH, leftW, statusH)

	-- right: the odds list
	local rightX = PAD + leftW + PAD
	local rightW = width - rightX - PAD
	place(refs.Right, rightX, bodyY, rightW, bodyH)
	place(refs.OddsTitle, 12, 6, rightW * 0.5, 28)
	place(refs.OddsNote, rightW * 0.5, 6, rightW * 0.5 - 12, 28)
	place(refs.Heads, 8, 34, rightW - 16, 18)
	local listW = rightW - 16
	local chanceW = if m.Row > 28 then 120 else 96
	local rest = listW - 10 - 20 - chanceW - 34 - 12
	local nameW, rarityW, bonusW = CapsuleView.oddsColumns(rest)
	local headCells = {
		HeadGolem = { 18, nameW },
		HeadRarity = { 18 + nameW, rarityW },
		HeadBonus = { 18 + nameW + rarityW, bonusW },
	}
	local headRarity = refs.Heads:FindFirstChild("HeadRarity")
	if headRarity and headRarity:IsA("TextLabel") then
		headRarity.Visible = rarityW > 0
	end
	for _, child in refs.Heads:GetChildren() do
		if child:IsA("TextLabel") then
			local cell = headCells[child.Name]
			if cell then
				place(child, cell[1], 0, cell[2], 18)
			else
				child.AnchorPoint = Vector2.new(1, 0)
				child.Position = UDim2.new(1, -16, 0, 0)
				child.Size = UDim2.fromOffset(chanceW, 18)
			end
		end
	end
	place(refs.List, 8, 56, listW, bodyH - 62)
	for _, row in refs.Rows do
		placeRow(row, m, listW - 10)
		row.Name.TextSize = m.Text - 1
		row.Chance.TextSize = m.Text - 1
		row.Rarity.TextSize = m.Small
		row.Bonus.TextSize = m.Small
		TechShopView.fitText(row.Name, row.Name.Size.X.Offset, m.Row, m.Text - 1, 11)
		TechShopView.fitText(row.Rarity, row.Rarity.Size.X.Offset - 4, m.Row, m.Small, 10)
		TechShopView.fitText(row.Bonus, row.Bonus.Size.X.Offset, m.Row, m.Small, 10)
	end

	refs.Hint.Position = UDim2.new(0.5, 0, 1, -4)
	refs.Hint.Size = UDim2.new(1, -40, 0, math.max(m.Footer - 4, 20))
	refs.Hint.Visible = not compact
	place(refs.Empty, PAD, bodyY, width - 2 * PAD, bodyH)
end

-- Shows one capsule's card (the tab's left side and its odds).
local function showCard(refs: Refs, card: Card)
	local m = metrics(refs.Compact)
	if refs.ArtFor ~= card.Id then
		refs.ArtHolder:ClearAllChildren()
		CapsuleView.art(refs.ArtHolder, card.Id, m.Art.X, m.Art.Y)
		refs.ArtFor = card.Id
	end
	refs.CapsuleName.Text = string.upper(card.Name)
	refs.CapsuleName.TextColor3 = card.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	TechShopView.fitText(refs.CapsuleName, refs.CapsuleName.Size.X.Offset, refs.CapsuleName.Size.Y.Offset, m.Text + 7, 14)
	refs.Description.Text = card.Description
	refs.LuckyBanner.Visible = card.Lucky
	refs.LuckyText.Text = CapsuleView.luckyText(card)
	TechShopView.fitText(refs.LuckyText, refs.LuckyBanner.Size.X.Offset - 16, refs.LuckyBanner.Size.Y.Offset, m.Small, 10)
	local showButtons = card.Note == nil
	for i, button in refs.Buttons do
		local buy = card.Buys[i]
		holderOf(button).Visible = showButtons and buy ~= nil
		if buy and button:GetAttribute("Busy") ~= true then
			button.Text = `{buy.Text}\n{buy.PriceText}`
			CapsuleView.style(button, buy.CanBuy, Theme.Good, Theme.GoodDark)
		end
	end
	refs.Note.Visible = not showButtons
	refs.Note.Text = card.Note or ""
	refs.Room.Text = `Golems: {card.Owned} / {GolemConfig.InventoryCap}`
	refs.Room.TextColor3 = if card.Room < 1 then Theme.Bad else Theme.TextDim
	refs.OddsNote.Text = if card.Lucky then "Triple Lucky odds (x3 = boosted)" else "the chance of each golem"
	refs.OddsNote.TextColor3 = if card.Lucky then LUCKY else Theme.TextDim
	-- odds rows (pooled)
	for i, line in card.Odds do
		local existing: Row? = refs.Rows[i]
		local row: Row
		if existing then
			row = existing
		else
			row = newRow(refs, i, m)
			placeRow(row, m, refs.List.Size.X.Offset - 10)
		end
		row.Frame.Visible = true
		row.Bar.BackgroundColor3 = line.Color
		row.Name.Text = line.Name
		row.Name.TextColor3 = line.Color:Lerp(Color3.new(1, 1, 1), 0.25)
		row.Rarity.Text = line.Rarity
		row.Rarity.TextColor3 = line.Color
		row.Bonus.Text = line.Bonus
		row.Chance.Text = line.Text
		row.Chance.TextColor3 = if line.Lucky then LUCKY else Theme.Text
		row.Lucky.Visible = line.Lucky
		TechShopView.fitText(row.Name, row.Name.Size.X.Offset, m.Row, m.Text - 1, 11)
		TechShopView.fitText(row.Rarity, row.Rarity.Size.X.Offset - 4, m.Row, m.Small, 10)
		TechShopView.fitText(row.Bonus, row.Bonus.Size.X.Offset, m.Row, m.Small, 10)
	end
	for i = #card.Odds + 1, #refs.Rows do
		refs.Rows[i].Frame.Visible = false
	end
end

--[[
	Shows the cards: tabs only for visible capsules (the shown tab moves to
	the first visible one when its capsule is hidden), then the shown tab's
	card. Returns the shown tab ("" when no capsule may be opened).
]]
function CapsuleView.setCards(refs: Refs, cards: { Card }): string
	local shown: Card? = nil
	local first: Card? = nil
	for _, card in cards do
		local tab = refs.Tabs[card.Id]
		if tab then
			holderOf(tab).Visible = card.Visible
		end
		if card.Visible then
			first = first or card
			if card.Id == refs.Tab then
				shown = card
			end
		end
	end
	local card = shown or first
	refs.Empty.Visible = card == nil
	refs.Left.Visible = card ~= nil
	refs.Right.Visible = card ~= nil
	if not card then
		refs.Tab = ""
		return ""
	end
	refs.Tab = card.Id
	for id, tab in refs.Tabs do
		local selected = id == card.Id
		local capsule = CapsuleConfig.ById[id]
		tab.BackgroundColor3 = if selected then capsule.Color:Lerp(Color3.new(1, 1, 1), 0.2) else capsule.Color:Lerp(DARK, 0.25)
		tab.TextColor3 = if selected then Theme.Text else Theme.TextDim
		local stroke = tab:FindFirstChild("Selected") :: UIStroke?
		if selected and not stroke then
			local made = UIKit.stroke(tab, 3, Color3.new(1, 1, 1))
			made.Name = "Selected"
		elseif not selected and stroke then
			stroke:Destroy()
		end
	end
	showCard(refs, card)
	return card.Id
end

-- The visible tabs in order (gamepad LB / RB).
function CapsuleView.visibleTabs(cards: { Card }): { string }
	local out = {}
	for _, card in cards do
		if card.Visible then
			table.insert(out, card.Id)
		end
	end
	return out
end

function CapsuleView.setCoins(refs: Refs, coins: number)
	refs.BalanceAmount.Text = Format.money(math.max(0, num(coins)))
end

function CapsuleView.setStatus(refs: Refs, text: string?, color: Color3?)
	refs.Status.Text = text or ""
	refs.Status.TextColor3 = color or Theme.Info
end

function CapsuleView.setHint(refs: Refs, text: string)
	refs.Hint.Text = text
end

-- The first OPEN button that can be pressed (gamepad selection on open).
-- No buttons (Royal "Coming soon!"): the odds list (a gamepad scrolls it),
-- never X, so A right after LB / RB doesn't close the shop.
function CapsuleView.firstButton(refs: Refs): GuiObject
	for _, button in refs.Buttons do
		if holderOf(button).Visible then
			return button
		end
	end
	if refs.Right.Visible then
		return refs.List
	end
	local tab = refs.Tabs[refs.Tab]
	if tab and holderOf(tab).Visible then
		return tab
	end
	return refs.Close
end

-- Every button a finger or a gamepad uses (tests: 44 pt at the phone scale).
function CapsuleView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close), holderOf(refs.Golems) }
	for _, tab in refs.Tabs do
		table.insert(list, holderOf(tab))
	end
	for _, button in refs.Buttons do
		table.insert(list, holderOf(button))
	end
	return list
end

---------------------------------------------------------------- opening overlay

local RAYS = 12

function CapsuleView.buildOpening(compact: boolean?): OpenRefs
	local isCompact = compact == true
	local gui = UIKit.screen("TerraForgeCapsuleOpen", 40)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local dim = UIKit.new("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -40),
		BackgroundColor3 = rgb(12, 8, 16),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, gui)
	local rays = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(760, 760),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, gui)
	for i = 1, RAYS do
		local ray = UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 46, 1, 0),
			Rotation = (i - 1) * 180 / RAYS,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, rays)
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	local hero = UIKit.new("ViewportFrame", {
		Name = "Hero",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(460, 460),
		BackgroundTransparency = 1,
		Ambient = rgb(160, 150, 150),
		LightColor = rgb(255, 244, 228),
		LightDirection = Vector3.new(-0.5, -1, 0.7),
		ZIndex = 3,
	}, gui)
	local camera = Instance.new("Camera")
	camera.Name = "HeroCamera"
	camera.FieldOfView = 30
	camera.Parent = hero
	hero.CurrentCamera = camera
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, gui)
	local plate = UIKit.new("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	local plateName = UIKit.label(plate, "", if isCompact then 48 else 44, {
		Name = "GolemName",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 52),
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 5,
	})
	local nameStroke = plateName:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Thickness = 3
	end
	local chips = UIKit.new("Frame", {
		Name = "Chips",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, plate)
	UIKit.list(chips, Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local plateRarity = UIKit.chip(chips, "", Theme.PanelLight, {
		Name = "Rarity",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(130, 28),
		TextSize = 18,
		ZIndex = 5,
	})
	local plateNew = UIKit.chip(chips, "NEW!", Theme.Accent, {
		Name = "New",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(70, 28),
		TextSize = 18,
		ZIndex = 5,
	})
	local plateBonus = UIKit.label(plate, "", if isCompact then 26 else 24, {
		Name = "Bonus",
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Theme.Good,
		TextWrapped = false,
		ZIndex = 5,
	})
	local counter = UIKit.label(gui, "", if isCompact then 28 else 24, {
		Name = "Counter",
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Text,
		TextWrapped = false,
		ZIndex = 5,
	})
	local note = UIKit.label(gui, "", if isCompact then 20 else 18, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = LUCKY,
		TextWrapped = false,
		ZIndex = 5,
	})
	local grid = UIKit.new("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, gui)
	local gridLayout = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 190),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, grid)
	local button = if isCompact then 76 else 60
	-- the buttons' own selection group: a gamepad stays on the overlay
	local controls = UIKit.new("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1280, 720),
		ZIndex = 6,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local skip = UIKit.button(controls, "SKIP", Theme.PanelLight, Theme.PanelDark, {
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(200, button),
		TextSize = 24,
	})
	local ok = UIKit.button(controls, "OK", Theme.Good, Theme.GoodDark, {
		Name = "Ok",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(200, button),
		TextSize = 26,
		Visible = false,
	})
	local again = UIKit.button(controls, "OPEN AGAIN", Theme.Accent, Theme.AccentDark, {
		Name = "Again",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(if isCompact then 340 else 300, button),
		TextSize = 22,
		Visible = false,
	})
	for _, b in { skip, ok, again } do
		holderOf(b).ZIndex = 6
		b.ZIndex = 6
	end
	local hint = UIKit.label(gui, "", if isCompact then 20 else 17, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		ZIndex = 6,
	})
	local refs: OpenRefs = {
		Gui = gui,
		Dim = dim,
		Rays = rays,
		Hero = hero,
		Camera = camera,
		Flash = flash,
		Plate = plate,
		PlateName = plateName,
		PlateRarity = plateRarity,
		PlateNew = plateNew,
		PlateBonus = plateBonus,
		Counter = counter,
		Note = note,
		Grid = grid,
		GridLayout = gridLayout,
		GridRoom = Vector2.new(800, 400),
		Cells = {},
		Controls = controls,
		Skip = skip,
		Ok = ok,
		Again = again,
		Hint = hint,
		Compact = isCompact,
	}
	CapsuleView.layoutOpening(refs, isCompact, 1280, 720)
	return refs
end

-- Places the overlay for a `width` x `height` design-unit screen.
function CapsuleView.layoutOpening(refs: OpenRefs, compact: boolean, width: number, height: number)
	refs.Compact = compact
	local button = if compact then 76 else 60
	-- every text size from the layout (the build's sizes are only a start)
	refs.PlateName.TextSize = if compact then 48 else 44
	refs.PlateBonus.TextSize = if compact then 26 else 24
	refs.Counter.TextSize = if compact then 28 else 24
	refs.Note.TextSize = if compact then 20 else 18
	refs.Hint.TextSize = if compact then 20 else 17
	local bottom = height - 18
	-- the hero sits in the upper part, the plate under it, the buttons at the bottom
	local hero = math.clamp(math.floor(height * 0.5), 220, 460)
	local heroY = math.max(hero / 2 + 40, height * 0.36)
	refs.Hero.Size = UDim2.fromOffset(hero, hero)
	refs.Hero.Position = UDim2.fromOffset(width / 2, heroY)
	refs.Rays.Size = UDim2.fromOffset(hero * 1.7, hero * 1.7)
	refs.Rays.Position = UDim2.fromOffset(width / 2, heroY)
	local plateY = math.min(heroY + hero * 0.38, bottom - button - 132)
	refs.Plate.Position = UDim2.fromOffset(width / 2, plateY)
	refs.Plate.Size = UDim2.fromOffset(math.min(width - 40, 700), 124)
	refs.Counter.Position = UDim2.fromOffset(width / 2, 12)
	refs.Counter.Size = UDim2.fromOffset(400, 34)
	refs.Note.Position = UDim2.fromOffset(width / 2, 46)
	refs.Note.Size = UDim2.fromOffset(math.min(width - 40, 700), 24)
	-- the grid between the note and the buttons
	local top = 76
	local gridH = bottom - button - 16 - top
	refs.Grid.Position = UDim2.fromOffset(width / 2, top + gridH / 2)
	refs.Grid.Size = UDim2.fromOffset(width - 40, gridH)
	refs.GridRoom = Vector2.new(width - 40, gridH)
	refs.Controls.Position = UDim2.fromOffset(0, 0)
	refs.Controls.Size = UDim2.fromOffset(width, height)
	local skipHolder = holderOf(refs.Skip)
	skipHolder.Position = UDim2.fromOffset(width / 2, bottom)
	skipHolder.Size = UDim2.fromOffset(if compact then 240 else 200, button)
	local okHolder = holderOf(refs.Ok)
	okHolder.Position = UDim2.fromOffset(width / 2 - 8, bottom)
	okHolder.Size = UDim2.fromOffset(if compact then 240 else 200, button)
	local againHolder = holderOf(refs.Again)
	againHolder.Position = UDim2.fromOffset(width / 2 + 8, bottom)
	againHolder.Size = UDim2.fromOffset(if compact then 340 else 300, button)
	refs.Hint.Position = UDim2.fromOffset(width / 2, bottom - button - 10)
	refs.Hint.Size = UDim2.fromOffset(math.min(width - 40, 700), 24)
end

-- The name plate for a woken golem (nil hides it).
function CapsuleView.setPlate(refs: OpenRefs, kind: string?, isNew: boolean)
	local golem = if kind then GolemConfig.ById[kind] else nil
	refs.Plate.Visible = golem ~= nil
	if not golem then
		return
	end
	local color = Rarity.ById[golem.Rarity].Color
	refs.PlateName.Text = string.upper(golem.Name)
	refs.PlateName.TextColor3 = color
	TechShopView.fitText(refs.PlateName, refs.Plate.Size.X.Offset, 52, if refs.Compact then 48 else 44, 24)
	refs.PlateRarity.Text = string.upper(golem.Rarity)
	refs.PlateRarity.BackgroundColor3 = color
	refs.PlateNew.Visible = isNew
	refs.PlateBonus.Text = GolemConfig.describe(golem.Id)
end

-- The rarity color of a kind (the rays, the flash, the cell frames).
function CapsuleView.rarityColor(kind: string): Color3
	local golem = GolemConfig.ById[kind]
	return if golem then Rarity.ById[golem.Rarity].Color else Theme.PanelLight
end

-- The best kind of a batch (highest GolemConfig.score; first on a tie).
function CapsuleView.best(kinds: { string }): string?
	local best: string? = nil
	for _, kind in kinds do
		if best == nil or GolemConfig.score(kind) > GolemConfig.score(best) then
			best = kind
		end
	end
	return best
end

--[[
	The result grid: one card per woken golem (opening order), hidden until
	the controller pops them; `new` marks kinds the player didn't own
	before. 1-3 golems: one row of big cards; more: 5 per row.
]]
function CapsuleView.setGrid(refs: OpenRefs, kinds: { string }, new: { [number]: boolean }, best: number?)
	for _, cell in refs.Cells do
		cell.Frame:Destroy()
	end
	table.clear(refs.Cells)
	local many = #kinds > 3
	local base = if many then Vector2.new(150, 190) else Vector2.new(200, 250)
	if refs.Compact then
		base = if many then Vector2.new(160, 196) else Vector2.new(220, 260)
	end
	-- shrink the cards to the grid's room (short phone screens), keeping their shape
	local cols = if many then 5 else math.max(1, #kinds)
	local rows = if many then math.ceil(#kinds / 5) else 1
	local gap = 12
	local roomW = (refs.GridRoom.X - (cols - 1) * gap) / cols
	local roomH = (refs.GridRoom.Y - (rows - 1) * gap) / rows
	local k = math.clamp(math.min(roomW / base.X, roomH / base.Y, 1), 0.4, 1)
	local cellSize = Vector2.new(math.floor(base.X * k), math.floor(base.Y * k))
	refs.GridLayout.CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y)
	-- exactly `cols` cards per row (x10: 5 x 2)
	refs.Grid.Size = UDim2.fromOffset(cols * cellSize.X + (cols - 1) * gap, rows * cellSize.Y + (rows - 1) * gap)
	local nameSize = math.max(11, math.floor((if many then 15 else 19) * math.max(k, 0.75)))
	local bonusSize = math.max(10, math.floor((if many then 13 else 16) * math.max(k, 0.75)))
	local nameH = nameSize + 7
	local bonusH = bonusSize + 7
	for i, kind in kinds do
		local golem = GolemConfig.ById[kind]
		local color = CapsuleView.rarityColor(kind)
		local frame = UIKit.new("Frame", {
			Name = "Cell" .. i,
			LayoutOrder = i,
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
		}, refs.Grid)
		UIKit.corner(frame, 14)
		UIKit.stroke(frame, if best == i then 5 else 3, if best == i then Color3.new(1, 1, 1) else color)
		UIKit.gradient(frame, color:Lerp(Theme.Panel, 0.55), Theme.PanelDark)
		local portraitSize = math.max(24, math.min(cellSize.X - 34, cellSize.Y - nameH - bonusH - 20))
		local portrait = GolemView.portrait(frame, kind, portraitSize)
		portrait.AnchorPoint = Vector2.new(0.5, 0)
		portrait.Position = UDim2.new(0.5, 0, 0, 10)
		local name = UIKit.label(frame, if golem then golem.Name else "???", nameSize, {
			Name = "GolemName",
			Position = UDim2.new(0, 6, 1, -(nameH + bonusH + 6)),
			Size = UDim2.new(1, -12, 0, nameH),
			TextColor3 = color,
			TextWrapped = false,
			ZIndex = 5,
		})
		TechShopView.fitText(name, cellSize.X - 12, nameH, nameSize, 9)
		local bonus = UIKit.label(frame, GolemConfig.describe(kind), bonusSize, {
			Name = "Bonus",
			Position = UDim2.new(0, 6, 1, -(bonusH + 4)),
			Size = UDim2.new(1, -12, 0, bonusH),
			TextColor3 = Theme.Good,
			TextWrapped = false,
			ZIndex = 5,
		})
		TechShopView.fitText(bonus, cellSize.X - 12, bonusH, bonusSize, 8)
		if new[i] then
			UIKit.chip(frame, "NEW!", Theme.Accent, {
				Name = "New",
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(52, 22),
				TextSize = 14,
				ZIndex = 6,
			})
		end
		local scale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, frame)
		table.insert(refs.Cells, { Frame = frame, Scale = scale, Kind = kind })
	end
end

-- The rays and flash color.
function CapsuleView.setRayColor(refs: OpenRefs, color: Color3)
	for _, ray in refs.Rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = color
		end
	end
end

-- Every button of the overlay (tests: 44 pt at the phone scale).
function CapsuleView.openTargets(refs: OpenRefs): { GuiObject }
	return { holderOf(refs.Skip), holderOf(refs.Ok), holderOf(refs.Again) }
end

---------------------------------------------------------------- the stall's odds board

--[[
	Fills the CapsuleStall's OddsBoard SurfaceGui (`gui`, its old labels are
	removed) with one capsule's odds, big enough to read on the 1.9 x 3.9
	stud board: the title, a line saying whose odds these are and where each
	golem's own chance is (the capsule menu), then per rarity (the six rows
	the stall's rarity chips mark, Rarity.List order) the rarity's total
	chance. Rarities the capsule doesn't hold show a dash. `lucky`: the
	viewer's Triple Lucky is on (the boosted odds).
]]
function CapsuleView.fillBoard(gui: Instance, capsuleId: string, lucky: boolean)
	gui:ClearAllChildren()
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule then
		return
	end
	local function label(
		name: string,
		text: string,
		x: number,
		y: number,
		w: number,
		h: number,
		color: Color3,
		align: Enum.TextXAlignment?
	): TextLabel
		local l = Instance.new("TextLabel")
		-- one line, as big as its box allows
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(x, y)
		l.Size = UDim2.fromScale(w, h)
		l.Text = text
		l.TextScaled = true
		l.TextWrapped = false
		l.TextColor3 = color
		l.TextStrokeColor3 = DARK
		l.TextStrokeTransparency = 0.2
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.FontFace = Theme.Font
		l:SetAttribute(CapsuleView.BoardAttribute, true)
		l.Parent = gui
		return l
	end
	label("Title", string.upper(capsule.Name), 0.05, 0.012, 0.9, 0.075, capsule.Color:Lerp(Color3.new(1, 1, 1), 0.45))
	label(
		"Subtitle",
		if lucky then "TRIPLE LUCKY ODDS" else "ODDS PER RARITY",
		0.05,
		0.09,
		0.9,
		0.04,
		if lucky then LUCKY else rgb(220, 210, 200)
	)
	label("Note", "Each golem's odds: capsule menu", 0.05, 0.13, 0.9, 0.032, rgb(190, 180, 172))
	local odds = CapsuleConfig.rarityOdds(capsuleId, lucky)
	local rows = #Rarity.List
	local rowH = 0.8 / rows
	for i, info in Rarity.List do
		local y = 0.17 + (i - 1) * rowH
		local total = odds[info.Id]
		local marker = Instance.new("Frame")
		marker.Name = "Marker" .. i
		marker.BorderSizePixel = 0
		marker.BackgroundColor3 = info.Color
		local columns = CapsuleView.BoardColumns
		marker.Position = UDim2.fromScale(columns.Marker[1], y + rowH * 0.22)
		marker.Size = UDim2.fromScale(columns.Marker[2], rowH * 0.56)
		marker:SetAttribute(CapsuleView.BoardAttribute, true)
		marker.Parent = gui
		local held = total ~= nil and total > 0
		local nameColor = if held then Color3.new(1, 1, 1) else rgb(150, 140, 136)
		label("Row" .. i, info.Name, columns.Row[1], y + rowH * 0.22, columns.Row[2], rowH * 0.56, nameColor)
		label(
			"Total" .. i,
			if held then CapsuleView.percent(total :: number) else "-",
			columns.Total[1],
			y + rowH * 0.1,
			columns.Total[2],
			rowH * 0.8,
			info.Color,
			Enum.TextXAlignment.Right
		)
	end
end


---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- While the light UI is on (ships off), the same window wears the light
-- look (LightSkin); windows also hide Roblox's touch controls while open.
local darkBuild = CapsuleView.build
CapsuleView.build = function(compact: boolean?): Refs
	local refs = darkBuild(compact)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
		TouchControls.follow(refs.Gui)
	end
	return refs
end

local darkBuildOpening = CapsuleView.buildOpening
CapsuleView.buildOpening = function(compact: boolean?): OpenRefs
	local refs = darkBuildOpening(compact)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
	end
	return refs
end

return CapsuleView
