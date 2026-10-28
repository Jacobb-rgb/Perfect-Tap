--[[
	The golem capsule screens (pure builders + pure helpers;
	CapsuleController fills them in).

	Both wear the bright Pop look of the Robux Shop (owner 2026-10-21: "new,
	modern, colourful, clean items, Roblox style"; GolemView's Pop pieces):
	the purple Golems band over a dark studded body, never the LightSkin.

	Shop panel (ScreenGui "TerraForgeCapsules"):
	  header   GOLEM EGGS, a line about odds, your coins, MY GOLEMS, X
	  tabs     one bright tab per capsule the player may open (LB / RB on a gamepad):
	           STONE · CRYSTAL · ROYAL (CapsuleConfig.Stall: a limited
	           edition's capsule is sold only in the Robux shop's banner,
	           but its opening plays here). Hidden where it isn't allowed: the
	           Royal capsule (Robux) where paid random items are restricted
	           or the policy isn't known yet, coin capsules too while coins
	           can be bought with Robux (CapsuleConfig.isPaidRandom).
	  left     a big painted card with the capsule's live 3D model (PictureModels
	           "capsule_<Id>"), its name and description, the Triple Lucky
	           banner while it runs, OPEN x1 / x3 / x10 with the price of each
	           (gold coin buttons at the player's blaster level; Royal: green
	           Robux buttons, a greyed "Coming soon" button while that
	           product's id is a placeholder or step 8's receipts aren't
	           ready, and "Coming soon!" instead of the buttons when none of
	           them is live), a status line and the golem room ("Golems 12 / 60")
	  right    the EXACT odds of every golem in the capsule on a dark studded
	           well: rarity bar, name, a rarity chip, bonus, the chance in big
	           numbers (CapsuleConfig.odds; with Triple Lucky on, the boosted
	           odds, the lucky golems marked "x3"). Always fully shown: a paid
	           random item.
	  footer   the control hint (not on phones)
	cards(state, coins, restricted, now, stateAt?, receipts?) says what each tab shows,
	from the State snapshot, so the cards always match what the server
	quotes (luckyNow: the Triple Lucky odds the client shows and sends with
	every open). layout() sets every size, position AND text size from the
	normal or compact metrics, so a panel built for one layout and laid out
	for the other looks exactly like one built for it.

	Opening overlay (ScreenGui "TerraForgeCapsuleOpen", above everything):
	  a dim backdrop, rotating rarity rays over a soft glow, the
	  ViewportFrame "Hero" (the controller animates the capsule and the
	  golems in it), a full-screen flash, the name plate (a chunky name with
	  a 3D shadow, rarity and NEW! chips, the bonus chip), a counter (2 / 3),
	  the result grid of bright rarity cards with rays behind each golem's
	  live 3D picture (x3: 3 cards, x10: 5 x 2, more: a card per kind with
	  its count, summary) and SKIP / OK / OPEN AGAIN
	  (in the "Controls" frame, a SelectionGroup that stops at its edges: a
	  gamepad never leaves the overlay for the shop behind it).

	fillBoard(gui, capsuleId, lucky): the CapsuleStall's OddsBoard
	SurfaceGui (a 1.9 x 3.9 stud board): the capsule's name and, big, each
	rarity's total chance on the six rows the stall's rarity chips mark;
	each golem's own chance is in the capsule menu (the board says so).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local PictureModels = require(Shared.Builders.PictureModels)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
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
		Header = 80, -- (the band holds the 72-unit X and MY GOLEMS)
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
function CapsuleView.cards(state: any, coins: number, restricted: boolean, now: number, stateAt: number?, receipts: boolean?): { Card }
	-- coin prices follow State.PriceLevel (BlasterData.priceLevel: a rebirth never lowers them)
	local level = if type(state) == "table" then (if state.PriceLevel ~= nil then state.PriceLevel else state.BlasterLevel) else nil
	local room = GolemConfig.room(golemsOf(state))
	local owned = GolemConfig.count(golemsOf(state))
	local luckySeconds = CapsuleView.luckySeconds(state, now)
	local lucky = CapsuleView.luckyNow(state, now, stateAt)
	local cash = num(coins)
	local cards: { Card } = {}
	for _, capsule in CapsuleConfig.Stall do
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
	local top = if capsule and capsule.Shell then capsule.Shell else color:Lerp(Color3.new(1, 1, 1), 0.55)
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

-- the capsules' tab and picture-card paints (Pop.Paints names)
CapsuleView.Paints = {
	Stone = "Orange",
	Crystal = "Purple",
	Royal = "Blue",
	Sky = "Teal",
} :: { [string]: string }

function CapsuleView.paintOf(capsuleId: string): string
	return CapsuleView.Paints[capsuleId] or "Pink"
end

-- A button's look: its Pop paint when enabled, else grey (GolemView.style).
function CapsuleView.style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	GolemView.style(button, enabled, color, dark)
end

--[[
	An OPEN button: a painted Pop button whose own Text ("OPEN 3\n$7.5K",
	what the controller and the tests read) stays hidden while the button
	shows it as "OPEN 3" over a gold coin (or the robux mark) and the price.
	A one-line Text (the controller's "..." while it waits) shows as it is.
]]
local function openButton(parent: Instance, count: number, index: number): TextButton
	local button = GolemView.popButton(parent, `OPEN {count}`, "Yellow", {
		Name = "Open" .. count,
		LayoutOrder = index,
		TextSize = 18,
	})
	button.TextWrapped = true
	button.LineHeight = 1.05
	GolemView.text(button, `OPEN {count}`, 18, { Name = "Label", ZIndex = 5 })
	local row = UIKit.new("Frame", { Name = "Row", BackgroundTransparency = 1, ZIndex = 5 }, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Pop.coin(row, 22, { LayoutOrder = 1 })
	local mark = UIKit.new("ImageLabel", {
		Name = "Robux",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 6,
	}, row)
	IconAssets.apply(mark, "robux")
	mark:SetAttribute("Icon", "robux")
	GolemView.text(row, "", 22, { Name = "Amount", LayoutOrder = 2, ZIndex = 6 })
	-- the controller writes "..." into the button while it waits
	pcall(function()
		button:GetPropertyChangedSignal("Text"):Connect(function()
			CapsuleView.syncOpen(button)
		end)
	end)
	return button
end

-- Shows an OPEN button's Text as its Pop face (see openButton).
function CapsuleView.syncOpen(button: TextButton)
	local label = button:FindFirstChild("Label") :: TextLabel?
	local row = button:FindFirstChild("Row") :: Frame?
	if not label or not row then
		return
	end
	local top, bottom = string.match(button.Text, "^(.-)\n(.*)$")
	local split = top ~= nil and bottom ~= nil
	button.TextTransparency = if split then 1 else 0
	local edge = button:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Transparency = if split then 1 else 0
	end
	label.Visible = split
	row.Visible = split
	if not top or not bottom then
		return
	end
	local holder = holderOf(button)
	local w = holder.Size.X.Offset
	label.Text = top
	TechShopView.fitText(label, w - 10, label.Size.Y.Offset, (label:GetAttribute("Max") :: number?) or 20, 10)
	GolemView.fitEdge(label)
	local currency = button:GetAttribute("Currency")
	local robux = currency == "Robux" and string.sub(bottom, 1, 3) == "R$ "
	local coin = row:FindFirstChild("Coin") :: Frame?
	local mark = row:FindFirstChild("Robux") :: ImageLabel?
	if coin then
		coin.Visible = currency == "Coins"
	end
	if mark then
		mark.Visible = robux
	end
	local amount = row:FindFirstChild("Amount") :: TextLabel?
	if amount then
		amount.Text = if robux then string.sub(bottom, 4) else bottom
		local icon = if (coin and coin.Visible) or robux then (if coin then coin.Size.X.Offset else 22) + 4 else 0
		local rowH = row.Size.Y.Offset
		TechShopView.fitText(amount, w - 14 - icon, rowH, (amount:GetAttribute("Max") :: number?) or 22, 10)
		amount.Size = UDim2.fromOffset(math.ceil(TechShopView.textWidth(amount.Text, amount.TextSize)) + 4, rowH)
		GolemView.fitEdge(amount)
	end
end

local function newRow(refs: Refs, index: number, m: Metrics): Row
	local frame = UIKit.new("Frame", {
		Name = "Row" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, -10, 0, m.Row),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if index % 2 == 0 then 0.92 else 0.965,
		BorderSizePixel = 0,
	}, refs.List)
	UIKit.corner(frame, 6)
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.new(0, 4, 0.5, -(m.Row - 8) / 2),
		Size = UDim2.fromOffset(8, m.Row - 8),
		BorderSizePixel = 0,
	}, frame)
	UIKit.corner(bar, 4)
	local function cell(name: string, size: number, align: Enum.TextXAlignment): TextLabel
		return GolemView.text(frame, "", size, {
			Name = name,
			TextXAlignment = align,
			-- never runs into the next cell (fitText shrinks it first)
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local row: Row = {
		Frame = frame,
		Bar = bar,
		Name = cell("GolemName", m.Text - 1, Enum.TextXAlignment.Left),
		-- the rarity as a chip in its colour
		Rarity = GolemView.solidChip(frame, "", GolemView.ChipDark, Vector2.new(90, m.Row - 6), {
			Name = "Rarity",
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 5,
		}),
		Bonus = cell("Bonus", m.Small, Enum.TextXAlignment.Left),
		-- the chance: big chunky numbers
		Chance = cell("Chance", m.Text + 2, Enum.TextXAlignment.Right),
		Lucky = GolemView.solidChip(frame, "x3", LUCKY_DARK, Vector2.new(34, m.Row - 8), {
			Name = "Lucky",
			AnchorPoint = Vector2.new(1, 0.5),
			Visible = false,
			ZIndex = 5,
		}),
	}
	row.Chance.FontFace = PopTheme.Heavy
	row.Bonus.TextColor3 = rgb(206, 212, 226)
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

local function chanceWidth(m: Metrics): number
	return if m.Row > 28 then 120 else 96
end

-- Places a row's cells for a list `width` wide (every size from the layout).
local function placeRow(row: Row, m: Metrics, width: number)
	local h = m.Row
	local chanceW = chanceWidth(m)
	local luckyW = 34
	local rest = width - 20 - chanceW - luckyW - 12
	local nameW, rarityW, bonusW = CapsuleView.oddsColumns(rest)
	row.Rarity.Visible = rarityW > 0
	row.Frame.Size = UDim2.new(1, -10, 0, h)
	row.Bar.Position = UDim2.new(0, 5, 0.5, -(h - 8) / 2)
	row.Bar.Size = UDim2.fromOffset(7, h - 8)
	row.Name.Position = UDim2.fromOffset(18, 0)
	row.Name.Size = UDim2.fromOffset(nameW - 6, h)
	-- (the chip fills its column; the bonus starts a little after it)
	row.Rarity.Position = UDim2.fromOffset(18 + nameW, 3)
	GolemView.sizeChip(row.Rarity, rarityW, h - 6)
	row.Bonus.Position = UDim2.fromOffset(18 + nameW + rarityW + 6, 0)
	row.Bonus.Size = UDim2.fromOffset(math.max(0, bonusW - 6), h)
	row.Lucky.Position = UDim2.new(1, -(chanceW + 8), 0.5, 0)
	GolemView.sizeChip(row.Lucky, luckyW, h - 8)
	row.Lucky.TextSize = m.Small - 1
	row.Chance.AnchorPoint = Vector2.new(1, 0)
	row.Chance.Position = UDim2.new(1, -6, 0, 0)
	row.Chance.Size = UDim2.fromOffset(chanceW - 6, h)
end

-- Fits a row's words (after its texts or its layout changed).
local function fitRow(row: Row, m: Metrics)
	TechShopView.fitText(row.Name, row.Name.Size.X.Offset, m.Row, m.Text - 1, 11)
	TechShopView.fitText(row.Rarity, row.Rarity.Size.X.Offset - 10, m.Row - 6, m.Small - 1, 9)
	TechShopView.fitText(row.Bonus, row.Bonus.Size.X.Offset, m.Row, m.Small, 10)
	TechShopView.fitText(row.Chance, row.Chance.Size.X.Offset, m.Row, m.Text + 2, 11)
	for _, label in { row.Name, row.Rarity, row.Bonus, row.Chance } do
		GolemView.fitEdge(label)
	end
end

-- The odds well's head: the note at the right as wide as its words, the
-- title in the room left of it (shrunk to fit; the note keeps its size).
local function placeOddsHead(refs: Refs, m: Metrics)
	local rightW = refs.Right.Size.X.Offset
	local note = refs.OddsNote
	note.TextSize = m.Small - 1
	local noteW = math.min(math.ceil(TechShopView.textWidth(note.Text, note.TextSize)) + 8, math.floor(rightW * 0.5))
	note.AnchorPoint = Vector2.new(1, 0)
	note.Position = UDim2.new(1, -12, 0, 8)
	note.Size = UDim2.fromOffset(noteW, 26)
	local titleW = rightW - noteW - 36
	refs.OddsTitle.Position = UDim2.fromOffset(12, 6)
	refs.OddsTitle.Size = UDim2.fromOffset(titleW, 30)
	TechShopView.fitText(refs.OddsTitle, titleW, 30, m.Text + 3, 10)
	GolemView.fitEdge(refs.OddsTitle)
end

function CapsuleView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local gui = UIKit.screen("TerraForgeCapsules", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look: no LightSkin (it would recolour the faces)

	local panel = UIKit.new("Frame", {
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
	}, gui)
	local title = GolemView.chrome(panel, "GOLEM EGGS", GolemView.WindowPaint)
	local subtitle = GolemView.text(panel, "Each egg hatches a sleeping golem: the odds of every golem are listed.", m.Small + 1, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(246, 236, 255),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
	})
	local close = GolemView.popButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		FontFace = PopTheme.Heavy,
		TextSize = 34,
		ZIndex = 6,
	})
	local golems = GolemView.popButton(panel, "MY GOLEMS", "Blue", { Name = "MyGolems", TextSize = 19, ZIndex = 6 })
	-- the coins: a dark pill with a gold coin
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		BackgroundColor3 = GolemView.ChipDark,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, panel)
	UIKit.corner(balance, 20)
	Pop.border(balance, 3)
	Pop.coin(balance, 28, { Position = UDim2.fromOffset(7, 6) })
	local balanceAmount = GolemView.text(balance, "$0", 24, {
		Name = "Amount",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -46, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(255, 226, 92),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})

	-- tabs: one bright tab per capsule (Pop.selectTab paints the shown one)
	local tabBar = UIKit.new("Frame", { Name = "TabBar", BackgroundTransparency = 1, ZIndex = 4 }, panel)
	UIKit.list(tabBar, Enum.FillDirection.Horizontal, GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local tabs: { [string]: TextButton } = {}
	for i, capsule in CapsuleConfig.Stall do
		local holder = UIKit.new("Frame", {
			Name = "Tab" .. capsule.Id .. "Holder",
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.fromOffset(m.TabWidth, m.TabHeight),
		}, tabBar)
		local paint = CapsuleView.paintOf(capsule.Id)
		local tab = Pop.button(holder, string.upper(capsule.Id), paint, Vector2.new(m.TabWidth, m.TabHeight), {
			Name = "Button",
			Size = UDim2.fromScale(1, 1),
		})
		tab:SetAttribute("TabPaint", paint)
		tabs[capsule.Id] = tab
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
				ZIndex = 6,
			}, panel)
		)
	end

	-- left: the capsule's painted card (its live 3D capsule), the OPEN buttons
	local left = UIKit.new("Frame", { Name = "Left", BackgroundTransparency = 1, ZIndex = 4 }, panel)
	local artHolder = UIKit.new("Frame", { Name = "ArtHolder", BackgroundTransparency = 1, ZIndex = 2 }, left)
	local capsuleName = GolemView.text(left, "", m.Text + 9, {
		Name = "CapsuleName",
		FontFace = PopTheme.Heavy,
		TextWrapped = true,
		ZIndex = 5,
	})
	local description = GolemView.text(left, "", m.Small, {
		Name = "Description",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
	})
	local luckyBanner = UIKit.new("Frame", {
		Name = "LuckyBanner",
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
	}, left)
	Pop.face(luckyBanner, "Yellow", 8)
	local luckyText = GolemView.text(luckyBanner, "", m.Small, {
		Name = "Text",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		TextColor3 = rgb(52, 34, 6),
		ZIndex = 7,
	})
	local luckyEdge = luckyText:FindFirstChild("Edge") :: UIStroke
	luckyEdge.Color = Color3.new(1, 1, 1)
	luckyEdge.Thickness = 1.5
	local buttons: { TextButton } = {}
	for i, count in CapsuleConfig.Counts do
		table.insert(buttons, openButton(left, count, i))
	end
	local note = Pop.title(left, "", m.Text + 6, "Gold", {
		Name = "Note",
		FontFace = PopTheme.Heavy,
		TextWrapped = true,
		Visible = false,
		ZIndex = 5,
	})
	local status = GolemView.text(left, "", m.Small, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Info,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local room = GolemView.text(left, "", m.Small, {
		Name = "Room",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(206, 212, 226),
	})

	-- right: the exact odds on a dark studded well (paid random items: always shown)
	local right = Pop.well(panel, { Name = "Right", ZIndex = 3 })
	local oddsTitle = Pop.title(right, "ODDS FOR EACH EGG", m.Text + 3, "Gold", {
		Name = "OddsTitle",
		FontFace = PopTheme.Heavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local oddsNote = GolemView.text(right, "", m.Small - 1, {
		Name = "OddsNote",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = rgb(206, 212, 226),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local heads = UIKit.new("Frame", { Name = "Heads", BackgroundTransparency = 1, ZIndex = 4 }, right)
	for _, k in { { "HeadGolem", "GOLEM" }, { "HeadRarity", "RARITY" }, { "HeadBonus", "BONUS" }, { "HeadChance", "CHANCE" } } do
		GolemView.text(heads, k[2], m.Small - 2, {
			Name = k[1],
			TextColor3 = rgb(178, 184, 200),
			TextXAlignment = if k[1] == "HeadChance" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		})
	end
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = rgb(220, 224, 236),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		-- a gamepad can scroll the odds (it has nothing to press)
		Selectable = true,
		ZIndex = 4,
	}, right)
	UIKit.list(list, Enum.FillDirection.Vertical, 1)

	local hint = GolemView.text(panel, "", m.Small, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = rgb(200, 205, 218),
	})
	local empty = GolemView.text(panel, "Eggs aren't available where you play.", m.Text + 2, {
		Name = "Empty",
		TextWrapped = true,
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
		Tab = CapsuleConfig.Stall[1].Id,
		ArtFor = nil,
		Compact = isCompact,
	}
	CapsuleView.layout(refs, isCompact, math.huge, math.huge)
	-- like every window: Roblox's touch controls hide while it is open
	TouchControls.follow(gui)
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
	compact metrics, shrunk to the space the screen has. Every size,
	position and text size comes from here, so a panel built for one layout
	and laid out for the other looks exactly like one built for it.
]]
function CapsuleView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	local m = metrics(compact)
	local width = math.max(math.min(m.Width, maxWidth - 16), m.Left + 420)
	local height = math.max(math.min(m.Height, maxHeight - 12), 400)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	refs.Compact = compact

	-- every text size from the metrics (the build's sizes are only a start)
	for _, tab in refs.Tabs do
		local label = tab:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextSize = if compact then 30 else 24
			GolemView.fitEdge(label)
		end
	end
	for _, button in refs.Buttons do
		button.TextSize = if compact then 21 else 18
	end
	refs.Golems.TextSize = if compact then 21 else 19
	refs.Close.TextSize = math.floor(m.Close * 0.62)
	refs.Note.TextSize = m.Text + 6
	refs.Status.TextSize = m.Small
	refs.Room.TextSize = m.Small
	refs.LuckyText.TextSize = m.Small
	refs.OddsTitle.TextSize = m.Text + 3
	refs.OddsNote.TextSize = m.Small - 1
	for _, child in refs.Heads:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextSize = m.Small - (if compact then 1 else 2)
		end
	end
	refs.Hint.TextSize = m.Small
	refs.Empty.TextSize = m.Text + 2
	for _, label in { refs.Note, refs.Status, refs.Room, refs.OddsTitle, refs.OddsNote, refs.Hint, refs.Empty } do
		GolemView.fitEdge(label)
	end

	-- header: title + subtitle on the band, coins / MY GOLEMS / X right
	local h = m.Header
	GolemView.layoutChrome(refs.Panel, h)
	local closeHolder = holderOf(refs.Close)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -(PAD - 4), 0, math.floor((h - m.Close) / 2))
	closeHolder.Size = UDim2.fromOffset(m.Close, m.Close)
	local golemsW = if compact then 200 else 150
	local golemsH = if compact then m.Close else 48
	local golemsHolder = holderOf(refs.Golems)
	golemsHolder.AnchorPoint = Vector2.new(1, 0)
	golemsHolder.Position = UDim2.new(1, -(PAD - 4 + m.Close + GAP), 0, math.floor((h - golemsH) / 2))
	golemsHolder.Size = UDim2.fromOffset(golemsW, golemsH)
	local balanceW = if compact then 190 else 160
	refs.Balance.AnchorPoint = Vector2.new(1, 0)
	refs.Balance.Position = UDim2.new(1, -(PAD - 4 + m.Close + 2 * GAP + golemsW), 0, math.floor((h - 40) / 2))
	refs.Balance.Size = UDim2.fromOffset(balanceW, 40)
	-- (the round look: the window's icon left of the title)
	local iconRoom = GolemView.placeIcon(refs.Panel, PAD, h)
	local textW = width - (2 * PAD + m.Close + 3 * GAP + golemsW + balanceW) - iconRoom
	GolemView.placeTitle(refs.Title, PAD + 4 + iconRoom, 6, textW, m.Title + 6, m.Title + 2)
	TechShopView.fitText(refs.Title, textW, m.Title + 6, m.Title + 2, 20)
	GolemView.placeTitle(refs.Title, PAD + 4 + iconRoom, 6, textW, m.Title + 6, refs.Title.TextSize)
	place(refs.Subtitle, PAD + 6 + iconRoom, m.Title + 12, textW, 20)
	refs.Subtitle.Visible = textW > 260
	TechShopView.fitText(refs.Subtitle, textW, 20, m.Small + 1, 11)
	GolemView.fitEdge(refs.Subtitle)

	-- tabs
	local tabY = h + 2
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
	-- the OPEN buttons side by side at the bottom, the status and room lines under them
	local statusH = 22
	local buttonsY = bodyH - (m.Button + 10 + 2 * statusH)
	local buttonW = math.floor((leftW - 2 * GAP) / 3)
	for i, button in refs.Buttons do
		placeButton(button, (i - 1) * (buttonW + GAP), buttonsY, buttonW, m.Button)
		local labelH = math.floor(m.Button * 0.4)
		local label = button:FindFirstChild("Label") :: TextLabel
		place(label, 5, 5, buttonW - 10, labelH)
		label:SetAttribute("Max", if compact then 21 else 18)
		local row = button:FindFirstChild("Row") :: Frame
		local rowH = m.Button - labelH - 9
		place(row, 0, 5 + labelH, buttonW, rowH)
		local icon = math.min(rowH - 4, if compact then 28 else 24)
		local coin = row:FindFirstChild("Coin") :: Frame
		coin.Size = UDim2.fromOffset(icon, icon)
		local coinMark = coin:FindFirstChild("Mark") :: TextLabel?
		if coinMark then
			coinMark.TextSize = math.floor(icon * 0.62)
		end
		local mark = row:FindFirstChild("Robux") :: ImageLabel
		mark.Size = UDim2.fromOffset(icon, icon)
		local amount = row:FindFirstChild("Amount") :: TextLabel
		amount:SetAttribute("Max", if compact then 26 else 22)
		CapsuleView.syncOpen(button)
	end
	place(refs.Note, 0, buttonsY, leftW, m.Button)
	place(refs.Status, 0, buttonsY + m.Button + 10, leftW, statusH)
	place(refs.Room, 0, buttonsY + m.Button + 10 + statusH, leftW, statusH)
	-- the capsule's card above them, down to the buttons
	local bannerH = if compact then 40 else 36
	local artY = 4
	local artH = buttonsY - 10 - artY
	local old = refs.ArtHolder.Size
	place(refs.ArtHolder, 0, artY, leftW, artH)
	if refs.ArtFor ~= nil and (old.X.Offset ~= leftW or old.Y.Offset ~= artH) then
		-- the card is drawn at its size: draw it again
		refs.ArtHolder:ClearAllChildren()
		refs.ArtFor = nil
	end
	-- tall card: the name on top, the capsule in the middle, the words under it;
	-- short card: the capsule on the left, the name and words right of it.
	-- The Triple Lucky banner takes the words' place while it runs.
	local tall = artH >= leftW * 0.55
	local pic, picX, picY
	local nameSize = m.Text + 9
	if tall then
		local nameH = nameSize + 10
		local descH = math.max(bannerH, math.floor(m.Small * 2 * 1.15) + 6)
		place(refs.CapsuleName, 12, artY + 8, leftW - 24, nameH)
		place(refs.Description, 14, artY + artH - descH - 10, leftW - 28, descH)
		place(refs.LuckyBanner, 12, artY + artH - descH - 10 + math.floor((descH - bannerH) / 2), leftW - 24, bannerH)
		refs.CapsuleName.TextXAlignment = Enum.TextXAlignment.Center
		refs.Description.TextXAlignment = Enum.TextXAlignment.Center
		pic = math.min(artH - nameH - descH - 26, math.floor(leftW * 0.62))
		picX = leftW / 2
		picY = 8 + nameH + (artH - nameH - descH - 18) / 2
	else
		pic = math.min(artH - 14, math.floor(leftW * 0.36))
		picX = 8 + pic / 2
		picY = artH / 2
		local wordsX = pic + 18
		local wordsW = leftW - wordsX - 10
		local nameH = math.min(math.floor(nameSize * 2 * 1.12) + 4, math.floor(artH * 0.5))
		local descH = math.max(0, artH - nameH - 18)
		place(refs.CapsuleName, wordsX, artY + 8, wordsW, nameH)
		place(refs.Description, wordsX, artY + 10 + nameH, wordsW, descH)
		place(refs.LuckyBanner, wordsX, artY + artH - bannerH - 8, wordsW, bannerH)
		refs.CapsuleName.TextXAlignment = Enum.TextXAlignment.Left
		refs.Description.TextXAlignment = Enum.TextXAlignment.Left
	end
	refs.ArtHolder:SetAttribute("Picture", math.max(24, pic))
	refs.ArtHolder:SetAttribute("PictureX", picX)
	refs.ArtHolder:SetAttribute("PictureY", picY)
	refs.CapsuleName:SetAttribute("Max", nameSize)

	-- right: the odds list on its well
	local rightX = PAD + leftW + PAD
	local rightW = width - rightX - PAD
	place(refs.Right, rightX, bodyY, rightW, bodyH)
	placeOddsHead(refs, m)
	place(refs.Heads, 8, 38, rightW - 16, 18)
	local listW = rightW - 16
	local chanceW = chanceWidth(m)
	local rest = listW - 10 - 20 - chanceW - 34 - 12
	local nameW, rarityW, bonusW = CapsuleView.oddsColumns(rest)
	local headCells = {
		HeadGolem = { 18, nameW },
		HeadRarity = { 18 + nameW, rarityW },
		HeadBonus = { 18 + nameW + rarityW + 6, bonusW - 6 },
	}
	local headRarity = refs.Heads:FindFirstChild("HeadRarity")
	if headRarity and headRarity:IsA("TextLabel") then
		headRarity.Visible = rarityW > 0
	end
	for _, child in refs.Heads:GetChildren() do
		if child:IsA("TextLabel") then
			local cell = headCells[child.Name]
			if cell then
				place(child, cell[1], 0, math.max(0, cell[2]), 18)
			else
				child.AnchorPoint = Vector2.new(1, 0)
				child.Position = UDim2.new(1, -16, 0, 0)
				child.Size = UDim2.fromOffset(chanceW, 18)
			end
		end
	end
	place(refs.List, 8, 58, listW, bodyH - 64)
	for _, row in refs.Rows do
		placeRow(row, m, listW - 10)
		row.Name.TextSize = m.Text - 1
		row.Chance.TextSize = m.Text + 2
		row.Rarity.TextSize = m.Small - 1
		row.Bonus.TextSize = m.Small
		fitRow(row, m)
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
		local size = refs.ArtHolder.Size
		local w, h = size.X.Offset, size.Y.Offset
		local pic = (refs.ArtHolder:GetAttribute("Picture") :: number?) or 100
		local at = UDim2.fromOffset(
			(refs.ArtHolder:GetAttribute("PictureX") :: number?) or w / 2,
			(refs.ArtHolder:GetAttribute("PictureY") :: number?) or h / 2
		)
		GolemView.glowCard(refs.ArtHolder, CapsuleView.paintOf(card.Id), Vector2.new(w, h), { Name = "Card" }, at)
		local model, from = PictureModels.build("capsule_" .. card.Id)
		if model then
			Pop.model(refs.ArtHolder, "capsule_" .. card.Id, pic, model, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = at,
				ZIndex = 4,
			}, from)
		else
			local drawn = CapsuleView.art(refs.ArtHolder, card.Id, math.floor(pic * 0.7), pic)
			drawn.AnchorPoint = Vector2.new(0.5, 0.5)
			drawn.Position = at
			drawn.ZIndex = 4
		end
		refs.ArtFor = card.Id
	end
	refs.CapsuleName.Text = string.upper(card.Name)
	local nameMax = (refs.CapsuleName:GetAttribute("Max") :: number?) or (m.Text + 9)
	TechShopView.fitText(refs.CapsuleName, refs.CapsuleName.Size.X.Offset, refs.CapsuleName.Size.Y.Offset, nameMax, 14)
	GolemView.fitEdge(refs.CapsuleName)
	refs.Description.Text = card.Description
	TechShopView.fitText(refs.Description, refs.Description.Size.X.Offset, refs.Description.Size.Y.Offset, m.Small + 1, 11)
	GolemView.fitEdge(refs.Description)
	refs.LuckyBanner.Visible = card.Lucky
	refs.Description.Visible = not card.Lucky -- (the banner takes its place)
	refs.LuckyText.Text = CapsuleView.luckyText(card)
	TechShopView.fitText(refs.LuckyText, refs.LuckyBanner.Size.X.Offset - 16, refs.LuckyBanner.Size.Y.Offset, m.Small + 1, 10)
	local showButtons = card.Note == nil
	for i, button in refs.Buttons do
		local buy = card.Buys[i]
		holderOf(button).Visible = showButtons and buy ~= nil
		if buy and button:GetAttribute("Busy") ~= true then
			button:SetAttribute("Currency", if card.Robux then (if buy.Reason == "ComingSoon" then "None" else "Robux") else "Coins")
			button.Text = `{buy.Text}\n{buy.PriceText}`
			-- coins gold, Robux green, grey when it can't be opened now
			GolemView.setPaint(button, if card.Robux then PopTheme.Price else "Yellow", buy.CanBuy)
			CapsuleView.syncOpen(button)
		end
	end
	refs.Note.Visible = not showButtons
	refs.Note.Text = card.Note or ""
	refs.Room.Text = `Golems: {card.Owned} / {GolemConfig.InventoryCap}`
	refs.Room.TextColor3 = if card.Room < 1 then Theme.Bad else rgb(206, 212, 226)
	refs.OddsNote.Text = if card.Lucky then "Triple Lucky odds (x3 = boosted)" else "the chance of each golem"
	refs.OddsNote.TextColor3 = if card.Lucky then LUCKY else rgb(206, 212, 226)
	placeOddsHead(refs, m)
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
		row.Name.TextColor3 = line.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		row.Rarity.Text = string.upper(line.Rarity)
		row.Rarity.BackgroundColor3 = GolemView.rarityChip(line.Rarity)
		row.Bonus.Text = line.Bonus
		row.Chance.Text = line.Text
		row.Chance.TextColor3 = if line.Lucky then LUCKY else PopTheme.Ink
		row.Lucky.Visible = line.Lucky
		fitRow(row, m)
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
	Pop.selectTab(refs.Tabs, card.Id)
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
	gui:SetAttribute("PopSkin", true)
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
	-- the light burst behind the golem: a soft glow and wide rays (the
	-- controller turns them and paints them the golem's rarity colour)
	local rays = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(760, 760),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, gui)
	for i, k in { 0.62, 0.4 } do
		local disc = UIKit.new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if i == 1 then 0.8 else 0.66,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			ZIndex = 2,
		}, rays)
		UIKit.corner(disc, 999)
	end
	for i = 1, RAYS do
		local ray = UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.085, 0, 1, 0),
			Rotation = (i - 1) * 180 / RAYS,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, rays)
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.2),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.7, 0.2),
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
		-- (a solid golem in its own colours: a softer ambient, a white key light; owner
		-- 2026-10-28: "the golems mustn't be see-through")
		Ambient = rgb(150, 148, 152),
		LightColor = rgb(255, 255, 255),
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
	-- the name plate: a chunky name with a 3D shadow, the rarity and NEW! chips, the bonus
	local plate = UIKit.new("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	local plateName = GolemView.text(plate, "", if isCompact then 50 else 46, {
		Name = "GolemName",
		FontFace = PopTheme.Heavy,
		ZIndex = 6,
	})
	Pop.shadow(plateName, 5)
	local chips = UIKit.new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, plate)
	UIKit.list(chips, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local plateRarity = GolemView.solidChip(chips, "", GolemView.ChipDark, Vector2.new(150, 32), {
		Name = "Rarity",
		LayoutOrder = 1,
	})
	local plateNew = GolemView.solidChip(chips, "NEW!", Pop.paint("Yellow").Bottom, Vector2.new(84, 32), {
		Name = "New",
		LayoutOrder = 2,
	})
	local plateBonus = GolemView.solidChip(plate, "", GolemView.ChipDark, Vector2.new(320, 34), {
		Name = "Bonus",
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = GolemView.BonusColor,
	})
	local counter = Pop.title(gui, "", if isCompact then 30 else 26, "Gold", {
		Name = "Counter",
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = PopTheme.Heavy,
		ZIndex = 6,
	})
	local note = GolemView.text(gui, "", if isCompact then 20 else 18, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = LUCKY,
		ZIndex = 6,
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
	local skip = GolemView.popButton(controls, "SKIP", PopTheme.Gray, {
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(200, button),
		TextSize = 24,
	})
	local ok = GolemView.popButton(controls, "OK", "Green", {
		Name = "Ok",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(200, button),
		TextSize = 26,
		Visible = false,
	})
	local again = GolemView.popButton(controls, "OPEN AGAIN", "Yellow", {
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
	local hint = GolemView.text(gui, "", if isCompact then 20 else 17, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = rgb(214, 218, 230),
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
	refs.PlateBonus.TextSize = if compact then 24 else 22
	refs.Counter.TextSize = if compact then 30 else 26
	refs.Note.TextSize = if compact then 20 else 18
	refs.Hint.TextSize = if compact then 20 else 17
	for _, label in { refs.PlateBonus, refs.Counter, refs.Note, refs.Hint } do
		GolemView.fitEdge(label)
	end
	local bottom = height - 18
	-- the hero sits in the upper part, the plate under it, the buttons at the bottom
	local hero = math.clamp(math.floor(height * 0.5), 220, 460)
	local heroY = math.max(hero / 2 + 40, height * 0.36)
	refs.Hero.Size = UDim2.fromOffset(hero, hero)
	refs.Hero.Position = UDim2.fromOffset(width / 2, heroY)
	refs.Rays.Size = UDim2.fromOffset(hero * 1.7, hero * 1.7)
	refs.Rays.Position = UDim2.fromOffset(width / 2, heroY)
	local plateY = math.min(heroY + hero * 0.38, bottom - button - 132)
	local plateW = math.min(width - 40, 700)
	refs.Plate.Position = UDim2.fromOffset(width / 2, plateY)
	refs.Plate.Size = UDim2.fromOffset(plateW, 128)
	local nameSize = if compact then 50 else 46
	GolemView.placeTitle(refs.PlateName, 0, 0, plateW, 54, nameSize)
	local shadow = refs.Plate:FindFirstChild("GolemNameShadow")
	if shadow and shadow:IsA("TextLabel") then
		shadow.Position = UDim2.fromOffset(0, 5)
	end
	local chips = refs.PlateRarity.Parent :: Frame
	place(chips, 0, 58, plateW, 32)
	GolemView.sizeChip(refs.PlateRarity, 150, 32)
	GolemView.sizeChip(refs.PlateNew, 84, 32)
	refs.PlateRarity.TextSize = 20
	refs.PlateNew.TextSize = 20
	refs.PlateBonus.Position = UDim2.new(0.5, 0, 0, 94)
	GolemView.sizeChip(refs.PlateBonus, math.min(plateW, 340), 34)
	refs.Counter.Position = UDim2.fromOffset(width / 2, 10)
	refs.Counter.Size = UDim2.fromOffset(500, 38)
	refs.Note.Position = UDim2.fromOffset(width / 2, 48)
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
	refs.PlateName.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)
	local size = refs.PlateName.Size
	TechShopView.fitText(refs.PlateName, size.X.Offset, size.Y.Offset, if refs.Compact then 50 else 46, 24)
	GolemView.placeTitle(refs.PlateName, 0, 0, size.X.Offset, size.Y.Offset, refs.PlateName.TextSize)
	local shadow = refs.Plate:FindFirstChild("GolemNameShadow")
	if shadow and shadow:IsA("TextLabel") then
		shadow.Position = UDim2.fromOffset(0, 5)
	end
	refs.PlateRarity.Text = string.upper(golem.Rarity)
	refs.PlateRarity.BackgroundColor3 = GolemView.rarityChip(golem.Rarity)
	refs.PlateNew.Visible = isNew
	refs.PlateBonus.Text = GolemConfig.describe(golem.Id)
	TechShopView.fitText(refs.PlateBonus, refs.PlateBonus.Size.X.Offset - 20, 34, if refs.Compact then 24 else 22, 12)
	GolemView.fitEdge(refs.PlateBonus)
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

-- More golems than this (a limited capsule's x50) show one card per kind with its count.
CapsuleView.GridMax = 10

--[[
	A big opening as one card per kind (summary of `kinds` / `new`): the
	kinds rarest first (GolemConfig.score), how many of each woke and
	whether any of them is NEW.
]]
function CapsuleView.summary(kinds: { string }, new: { [number]: boolean }): ({ string }, { [number]: boolean }, { [number]: number })
	local order: { string } = {}
	local counts: { [string]: number } = {}
	local fresh: { [string]: boolean } = {}
	for i, kind in kinds do
		if counts[kind] == nil then
			table.insert(order, kind)
			counts[kind] = 0
		end
		counts[kind] += 1
		if new[i] then
			fresh[kind] = true
		end
	end
	table.sort(order, function(a: string, b: string): boolean
		local sa, sb = GolemConfig.score(a), GolemConfig.score(b)
		if sa ~= sb then
			return sa > sb
		end
		return a < b
	end)
	local outNew: { [number]: boolean } = {}
	local outCounts: { [number]: number } = {}
	for i, kind in order do
		outNew[i] = fresh[kind] == true
		outCounts[i] = counts[kind]
	end
	return order, outNew, outCounts
end

--[[
	The result grid: one bright rarity card per woken golem (opening order:
	light rays behind its live 3D picture, the name, the bonus chip), hidden
	until the controller pops them; `new` marks kinds the player didn't own
	before (NEW!), `best` gets a gold outline. 1-3 golems: one row of big
	cards; more: 5 per row. `counts` (CapsuleView.summary): each card is a
	kind, "x12" on it.
]]
function CapsuleView.setGrid(refs: OpenRefs, kinds: { string }, new: { [number]: boolean }, best: number?, counts: { [number]: number }?)
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
	local nameSize = math.max(11, math.floor((if many then 16 else 21) * math.max(k, 0.75)))
	local bonusSize = math.max(10, math.floor((if many then 13 else 16) * math.max(k, 0.75)))
	local nameH = nameSize + 7
	local bonusH = bonusSize + 9
	for i, kind in kinds do
		local golem = GolemConfig.ById[kind]
		local portraitSize = math.max(24, math.min(cellSize.X - 24, cellSize.Y - nameH - bonusH - 20))
		local frame = GolemView.glowCard(refs.Grid, GolemView.rarityPaint(if golem then golem.Rarity else nil), cellSize, {
			Name = "Cell" .. i,
			LayoutOrder = i,
			Visible = false,
			ZIndex = 4,
		}, UDim2.new(0.5, 0, 0, 8 + portraitSize / 2))
		local border = frame:FindFirstChild("Border") :: UIStroke
		if best == i then
			border.Color = GolemView.SelectColor
			border.Thickness = 5
		end
		GolemView.picture(frame, kind, portraitSize, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			ZIndex = 4,
		})
		local name = GolemView.text(frame, if golem then golem.Name else "???", nameSize, {
			Name = "GolemName",
			Position = UDim2.new(0, 5, 1, -(nameH + bonusH + 8)),
			Size = UDim2.new(1, -10, 0, nameH),
			ZIndex = 6,
		})
		TechShopView.fitText(name, cellSize.X - 10, nameH, nameSize, 9)
		GolemView.fitEdge(name)
		local bonus = GolemView.solidChip(frame, GolemConfig.describe(kind), GolemView.ChipDark, Vector2.new(cellSize.X - 12, bonusH), {
			Name = "Bonus",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			TextColor3 = GolemView.BonusColor,
		})
		TechShopView.fitText(bonus, cellSize.X - 24, bonusH, bonusSize, 8)
		GolemView.fitEdge(bonus)
		if new[i] then
			GolemView.solidChip(frame, "NEW!", Pop.paint("Yellow").Bottom, Vector2.new(58, 24), {
				Name = "New",
				Position = UDim2.fromOffset(6, 6),
				TextSize = 15,
				ZIndex = 7,
			})
		end
		local count = if counts then counts[i] else nil
		if count and count > 1 then
			GolemView.solidChip(frame, `x{count}`, GolemView.ChipDark, Vector2.new(50, 24), {
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				TextSize = 16,
				ZIndex = 7,
			})
		end
		local scale = UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, frame)
		table.insert(refs.Cells, { Frame = frame, Scale = scale, Kind = kind })
	end
end

-- The rays and flash color (the glow discs too).
function CapsuleView.setRayColor(refs: OpenRefs, color: Color3)
	for _, ray in refs.Rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
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

return CapsuleView
