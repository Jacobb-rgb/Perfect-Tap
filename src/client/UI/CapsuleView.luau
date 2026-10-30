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

	Opening (owner 2026-10-29, the clicker-sim video: "open them exactly
	like there, this clean, glowing by rarity"; HatchFx has the flow, the
	timings and the maths; CapsuleController plays it):
	  "TerraForgeCapsuleOpen" (the whole screen, nothing dims the world: the
	  controller blurs it softly) holds the taps that skip (on touch off the
	  thumbstick's zone), soft blobs of the best colour, ONE flash, the white
	  sunburst, the full-screen ViewportFrame "Stage" (the eggs, then the
	  golems, HUGE and SOLID: nothing see-through over them), the white rings
	  and puffs, the shell pieces and a little confetti, and under each
	  golem its NAME (FredokaOne, white, a thick dark edge) and "1 in N" in
	  its rarity's colour (BrightTheme.oneInText), nothing else.
	  "TerraForgeCapsuleAuto" (the safe frame): the Auto button bottom left
	  (touch: above the thumbstick's zone; a TV: inside its safe margin),
	  green while on, its key on a badge (G / the gamepad's glyph), and a
	  note when Auto stops under an opening.
	  The top centre stays free (no egg or golem there: room for a quest card).

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
local BrightTheme = require(Shared.Config.BrightTheme)
local IconAssets = require(Shared.Config.IconAssets)
local PictureModels = require(Shared.Builders.PictureModels)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local Confetti = require(script.Parent.Confetti)
local HatchFx = require(script.Parent.HatchFx)
local RevealKit = require(script.Parent.Parent.Effects.RevealKit)
local TrashIcon = require(script.Parent.TrashIcon)
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

-- A rectangle in the opening's design units (its top-left and bottom-right).
export type KeepBox = { Min: Vector2, Max: Vector2 }
-- (a waiting note's form: its text, its lines, its widest line's width)
type NoteOption = { Text: string, Lines: number, Width: number }

-- A golem's name under it in the opening: the NAME and "1 in N" in its rarity's colour (an
-- auto-deleted golem: a trash mark and "DELETED" under them; a won golem past the inventory's
-- hard cap, a Robux pack's: "Waiting: inventory full" under them, it wakes when there is room).
export type Tag = {
	Frame: Frame,
	Name: TextLabel,
	Chance: TextLabel,
	Deleted: Frame,
	DeletedCan: Frame, -- (its trash mark)
	DeletedWord: TextLabel, -- (its "DELETED")
	Waiting: Frame,
	WaitingText: TextLabel,
}

export type OpenRefs = {
	Gui: ScreenGui, -- "TerraForgeCapsuleOpen": the whole screen (IgnoreGuiInset), the world shows through
	Controls: ScreenGui, -- "TerraForgeCapsuleAuto": the Auto button and its note, in the safe frame
	Tap: TextButton, -- a click / tap skips (touch: right of the thumbstick's zone)
	TapTop: TextButton, -- (touch: the thumbstick column's top third)
	Blobs: { Frame }, -- soft blobs of the best colour drifting behind the eggs
	Flash: Frame, -- ONE flash in the best colour, under the stage
	Sunburst: Frame, -- the soft white sunburst behind the golems
	Stage: ViewportFrame, -- the eggs, then the golems (the whole screen; HatchFx's camera maths)
	Camera: Camera,
	Rings: { { Frame } }, -- per egg slot: its white shockwave rings
	Puffs: { Frame }, -- per egg slot: its white puff
	Bits: Frame, -- the screen-sized layer the shell pieces and the confetti fly in
	Shards: { Frame },
	Confetti: { Frame },
	Tags: { Tag }, -- per golem slot: its name and chance
	AutoHolder: Frame,
	Auto: TextButton, -- the Auto toggle
	AutoArrow: Frame,
	AutoLabel: TextLabel,
	AutoKey: Frame,
	AutoKeyText: TextLabel,
	AutoGlyph: ImageLabel,
	Note: TextLabel, -- why Auto stopped (the HUD's toasts hide while an opening plays)
	Chain: TextLabel, -- "2 / 5": a big pack's openings, one after another (setChain)
	AutoKeep: { KeepBox }, -- the Auto button's disc with its key, and its label (the stage's design units): names step aside while it shows
	SafeBottom: number, -- design units under the safe frame (a phone's home indicator): no tag goes there
	Size: Vector2, -- the screen in design units (layoutOpening)
	Touch: boolean,
	Compact: boolean,
}

CapsuleView.StageTags = 10 -- the most results an opening shows (CapsuleConfig.Counts' largest)
CapsuleView.WaitingText = "Waiting: inventory full" -- under a won golem past the inventory's hard cap
CapsuleView.WaitingShort = "Waiting: full" -- (where the whole note doesn't fit on one line: a phone's Open 10)
CapsuleView.WaitingLines = "Waiting:\nfull" -- (the short one on two lines: the narrowest, beside the Auto button)
CapsuleView.DeletedWide = 130 -- the DELETED pill: its trash mark and the word
CapsuleView.DeletedNarrow = 38 -- the trash mark alone (where the pill would run under the Auto button)

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
	-- the kinds the player auto-deletes (the egg panel's trash): a coin egg holding one of them
	-- may still open with too little room (the server counts only the golems it keeps)
	local golems = golemsOf(state)
	local deleting = if type(golems) == "table" and type(golems.AutoDelete) == "table" then golems.AutoDelete else {}
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
				local full = room < count and not CapsuleView.deletesAny(capsule.Id, deleting)
				local reason: string? = if full then "InventoryFull" elseif cash < price then "NoCoins" else nil
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

-- Does this egg hold a golem the player auto-deletes (`deleting`: State Golems.AutoDelete)?
function CapsuleView.deletesAny(capsuleId: string, deleting: { [any]: any }): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	if not capsule or capsule.Currency ~= "Coins" then
		return false
	end
	for kind in capsule.Odds do
		if deleting[kind] == true then
			return true
		end
	end
	return false
end

-- Refusals CapsuleConfig.Reasons doesn't list yet (CapsuleService's own).
CapsuleView.ExtraReasons = {
	OddsChanged = "The odds just changed: check them and open again",
	TooMany = "That's the most golems you can auto-delete",
	BadGolem = "That golem can't be auto-deleted",
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

-- A control that never buys, for a gamepad's selection after an opening (A mashed to skip it must
-- not open another egg): the shown tab, else the odds list, else X.
function CapsuleView.restButton(refs: Refs): GuiObject
	local tab = refs.Tabs[refs.Tab]
	if tab and holderOf(tab).Visible then
		return tab
	end
	if refs.Right.Visible then
		return refs.List
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

local function circle(parent: Instance, name: string, color: Color3, transparency: number, z: number): Frame
	local disc = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent) :: Frame
	UIKit.corner(disc, 9999)
	return disc
end

-- A text in the bright look: FredokaOne, white, a thick dark edge.
local function brightText(parent: Instance, name: string, size: number, z: number): TextLabel
	local label = UIKit.new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		FontFace = BrightTheme.Font,
		Size = UDim2.new(1, 0, 0, size + 6),
		Text = "",
		TextColor3 = BrightTheme.TextOnColour,
		TextSize = size,
		TextWrapped = false,
		ZIndex = z,
	}, parent) :: TextLabel
	UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = BrightTheme.Outline,
		LineJoinMode = Enum.LineJoinMode.Round,
		Thickness = CapsuleView.TextEdge(size),
	}, label)
	return label
end

-- The dark edge of a name or chance `size` design units big (thick, like the video's).
function CapsuleView.TextEdge(size: number): number
	return math.clamp(size * 0.1, 2, 4.5)
end

CapsuleView.Blobs = 4 -- soft blobs of the best colour behind the eggs
CapsuleView.SunRays = 16
CapsuleView.ShardCount = 30 -- shell pieces at the burst (shared by the eggs)
CapsuleView.ConfettiCount = 18 -- "a little confetti" at the reveal
CapsuleView.AutoDisc = { Normal = 88, Compact = 72 } -- the Auto button (compact: 72 units = 44.6 pt at the phone floor)

--[[
	Builds the opening (see the header): two ScreenGuis, the whole screen's
	"TerraForgeCapsuleOpen" (the world shows through: nothing dims it) and
	"TerraForgeCapsuleAuto" in the safe frame (the Auto button, its note).
	Every piece is made here once and pooled; layoutOpening sizes them.
]]
function CapsuleView.buildOpening(compact: boolean?): OpenRefs
	local isCompact = compact == true
	local gui = UIKit.screen("TerraForgeCapsuleOpen", 40)
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- (its own bright look: the light UI's re-skin leaves it alone)
	-- a click / tap skips; on touch these two leave the thumbstick's zone free (layoutOpening)
	local function tapper(name: string): TextButton
		return UIKit.new("TextButton", {
			Name = name,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = false,
			Text = "",
			ZIndex = 1,
		}, gui) :: TextButton
	end
	local tap = tapper("Tap")
	local tapTop = tapper("TapTop")
	-- soft blobs of the best colour drifting behind the eggs (three discs each: a soft edge)
	local blobs: { Frame } = {}
	for i = 1, CapsuleView.Blobs do
		local blob = UIKit.new("Frame", {
			Name = "Blob" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(300, 300),
			Visible = false,
			ZIndex = 2,
		}, gui) :: Frame
		for j, k in { 1, 0.72, 0.46 } do
			local disc = circle(blob, "Soft" .. j, Color3.new(1, 1, 1), 0.86, 2)
			disc.Size = UDim2.fromScale(k, k)
		end
		table.insert(blobs, blob)
	end
	-- ONE flash in the best colour (RevealKit's; under the stage: the golems that pop in are never behind it)
	local flash = RevealKit.flash(gui, 3)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	-- the soft white sunburst behind the golems: rays through the middle and a glow
	local sunburst = UIKit.new("Frame", {
		Name = "Sunburst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, gui) :: Frame
	local glow = circle(sunburst, "Glow", Color3.new(1, 1, 1), 0.55, 4)
	glow.Size = UDim2.fromScale(0.5, 0.5)
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
	}, glow)
	local core = circle(sunburst, "Core", Color3.new(1, 1, 1), 0.35, 4)
	core.Size = UDim2.fromScale(0.26, 0.26)
	for i = 1, CapsuleView.SunRays do
		local ray = UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * 180 / CapsuleView.SunRays,
			Size = UDim2.new(if i % 2 == 0 then 0.035 else 0.06, 0, 1, 0),
			ZIndex = 4,
		}, sunburst) :: Frame
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.32, 0.45),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(0.68, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	-- the stage: the eggs, then the golems, in front of the camera over the world (the whole screen)
	local stage = UIKit.new("ViewportFrame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		-- (solid, bright, clean: a soft ambient and a white key light from the front)
		Ambient = rgb(168, 166, 172),
		LightColor = rgb(255, 255, 255),
		LightDirection = Vector3.new(-0.35, -0.75, -0.55),
		ZIndex = 5,
	}, gui) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.Name = "StageCamera"
	camera.FieldOfView = 40
	camera.CFrame = CFrame.new()
	camera.Parent = stage
	stage.CurrentCamera = camera
	-- the shockwave rings and the puff of each egg (over the eggs: there's no golem yet)
	local rings: { { Frame } } = {}
	local puffs: { Frame } = {}
	for i = 1, CapsuleView.StageTags do
		-- (RevealKit's shockwave rings: HatchStage poses them thin and white round the egg)
		local list = RevealKit.rings(gui, HatchFx.RingCount, 6)
		for j, ring in list do
			ring.Name = `Ring{i}_{j}`
		end
		table.insert(rings, list)
		local puff = UIKit.new("Frame", {
			Name = "Puff" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(100, 100),
			Visible = false,
			ZIndex = 6,
		}, gui) :: Frame
		for j, k in { 1, 0.66 } do
			local disc = circle(puff, "Soft" .. j, Color3.new(1, 1, 1), 0.5, 6)
			disc.Size = UDim2.fromScale(k, k)
		end
		table.insert(puffs, puff)
	end
	-- the shell pieces and the confetti fly in a layer the size of the screen (Confetti's shares)
	local bits = UIKit.new("Frame", { Name = "Bits", BackgroundTransparency = 1, ZIndex = 7 }, gui) :: Frame
	local shards = Confetti.build(bits, CapsuleView.ShardCount, 7)
	local confetti = Confetti.build(bits, CapsuleView.ConfettiCount, 8)
	-- the names under the golems: the NAME and "1 in N" in the rarity's colour
	local tags: { Tag } = {}
	for i = 1, CapsuleView.StageTags do
		local holder = UIKit.new("Frame", {
			Name = "Tag" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(320, 90),
			Visible = false,
			ZIndex = 9,
		}, gui) :: Frame
		local name = brightText(holder, "GolemName", 34, 9)
		name.Position = UDim2.fromScale(0.5, 0)
		local chance = brightText(holder, "OneIn", 26, 9)
		chance.Position = UDim2.new(0.5, 0, 0, 40)
		-- an auto-deleted golem: a red trash mark and DELETED under its chance
		local deleted = UIKit.new("Frame", {
			Name = "Deleted",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = BrightTheme.Bad,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(CapsuleView.DeletedWide, 30),
			Visible = false,
			ZIndex = 9,
		}, holder) :: Frame
		UIKit.corner(deleted, BrightTheme.PillCorner)
		UIKit.new(
			"UIStroke",
			{ Name = "Rim", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = BrightTheme.Outline, Thickness = 2 },
			deleted
		)
		local can = TrashIcon.build(deleted, 22, Color3.new(1, 1, 1), 10)
		can.AnchorPoint = Vector2.new(0, 0.5)
		can.Position = UDim2.new(0, 8, 0.5, 0)
		local word = brightText(deleted, "Word", 18, 10)
		word.Text = "DELETED"
		word.AnchorPoint = Vector2.new(0, 0.5)
		word.Position = UDim2.new(0, 34, 0.5, 0)
		word.Size = UDim2.new(1, -38, 0, 24)
		word.TextXAlignment = Enum.TextXAlignment.Left
		-- a won golem that waits (a Robux pack past the inventory's hard cap): a gold note under its chance
		local waiting = UIKit.new("Frame", {
			Name = "Waiting",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = BrightTheme.Paints.Gold.Bottom,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(220, 28),
			Visible = false,
			ZIndex = 9,
		}, holder) :: Frame
		UIKit.corner(waiting, BrightTheme.PillCorner)
		UIKit.new(
			"UIStroke",
			{ Name = "Rim", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = BrightTheme.Outline, Thickness = 2 },
			waiting
		)
		local wait = brightText(waiting, "Word", 16, 10)
		wait.Text = CapsuleView.WaitingText
		wait.AnchorPoint = Vector2.new(0.5, 0.5)
		wait.LineHeight = 0.95
		wait.Position = UDim2.fromScale(0.5, 0.5)
		wait.Size = UDim2.new(1, -10, 1, -4)
		wait.TextWrapped = true -- (two lines where its golem's room is narrow: a phone's Open 10)
		table.insert(tags, {
			Frame = holder,
			Name = name,
			Chance = chance,
			Deleted = deleted,
			DeletedCan = can,
			DeletedWord = word,
			Waiting = waiting,
			WaitingText = wait,
		})
	end

	-- the Auto button (bottom left; touch: above the thumbstick's zone) and its note, in the safe frame
	local controls = UIKit.screen("TerraForgeCapsuleAuto", 41)
	controls.Enabled = false
	controls:SetAttribute("TerraForge", true)
	controls:SetAttribute("PopSkin", true)
	local disc = if isCompact then CapsuleView.AutoDisc.Compact else CapsuleView.AutoDisc.Normal
	local holder = UIKit.new("Frame", {
		Name = "AutoHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(disc, disc),
		ZIndex = 2,
	}, controls) :: Frame
	local auto = UIKit.new("TextButton", {
		Name = "Auto",
		AutoButtonColor = true,
		BackgroundColor3 = rgb(46, 50, 64),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.fromOffset(disc, disc),
		Text = "",
		ZIndex = 2,
	}, holder) :: TextButton
	UIKit.corner(auto, 9999)
	UIKit.new("UIStroke", {
		Name = "Rim",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.new(1, 1, 1),
		Thickness = 3,
		Transparency = 0.2,
	}, auto)
	-- a round arrow (our own drawing): a ring, a gap at its top right, the arrow's head there
	local arrow = UIKit.new("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
	}, auto) :: Frame
	local ring = circle(arrow, "Ring", Color3.new(1, 1, 1), 1, 3)
	UIKit.new("UIStroke", { Name = "Line", Color = Color3.new(1, 1, 1), Thickness = 6 }, ring)
	UIKit.new("Frame", {
		Name = "Gap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rgb(46, 50, 64),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.86, 0.14),
		Rotation = 45,
		Size = UDim2.fromScale(0.34, 0.2),
		ZIndex = 4,
	}, arrow)
	local head = UIKit.new("Frame", {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.97, 0.3),
		Rotation = 45,
		Size = UDim2.fromScale(0.32, 0.32),
		ZIndex = 5,
	}, arrow) :: Frame
	UIKit.new("UIGradient", {
		Rotation = -45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, head)
	local label = brightText(holder, "AutoLabel", 22, 3)
	label.Text = "AUTO"
	-- the key: a white badge with the letter (G) or the gamepad's glyph
	local key = UIKit.new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		Visible = false,
		ZIndex = 6,
	}, holder) :: Frame
	UIKit.corner(key, 8)
	UIKit.new("UIStroke", { Name = "Rim", Color = BrightTheme.Outline, Thickness = 2 }, key)
	local keyText = UIKit.new("TextLabel", {
		Name = "KeyText",
		BackgroundTransparency = 1,
		FontFace = BrightTheme.Font,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = BrightTheme.Text,
		TextSize = 20,
		ZIndex = 7,
	}, key) :: TextLabel
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
	}, key) :: ImageLabel
	-- why Auto stopped (the odds changed under it): the HUD's toasts hide while an opening plays
	local note = UIKit.new("TextLabel", {
		Name = "Note",
		BackgroundTransparency = 1,
		FontFace = BrightTheme.SmallFont,
		Size = UDim2.fromOffset(420, 24),
		Text = "",
		TextColor3 = BrightTheme.TextOnColour,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 3,
	}, controls) :: TextLabel
	UIKit.new("UIStroke", { Name = "Edge", Color = BrightTheme.Outline, Thickness = 2 }, note)
	-- a big pack's openings one after another: "2 / 5" at the top (setChain; under the top bar)
	local chain = brightText(controls, "Chain", 30, 3)
	chain.Size = UDim2.fromOffset(200, 36)
	chain.Visible = false
	local refs: OpenRefs = {
		Gui = gui,
		Controls = controls,
		Tap = tap,
		TapTop = tapTop,
		Blobs = blobs,
		Flash = flash,
		Sunburst = sunburst,
		Stage = stage,
		Camera = camera,
		Rings = rings,
		Puffs = puffs,
		Bits = bits,
		Shards = shards,
		Confetti = confetti,
		Tags = tags,
		AutoHolder = holder,
		Auto = auto,
		AutoArrow = arrow,
		AutoLabel = label,
		AutoKey = key,
		AutoKeyText = keyText,
		AutoGlyph = glyph,
		Note = note,
		Chain = chain,
		AutoKeep = {},
		SafeBottom = 0,
		Size = Vector2.new(1280, 720),
		Touch = false,
		Compact = isCompact,
	}
	CapsuleView.layoutOpening(refs, isCompact, 1280, 720)
	return refs
end

-- "2 / 5": opening `batch` of `batches` (a big pack shown 10 golems at a time); hidden for one opening.
function CapsuleView.setChain(refs: OpenRefs, batch: number?, batches: number?)
	local of = batches or 1
	refs.Chain.Visible = of > 1
	refs.Chain.Text = if of > 1 then `{batch or 1} / {of}` else ""
end

export type OpeningOpts = {
	Touch: boolean?, -- a touch screen: the thumbstick's zone stays free (left 40 %, lower 2/3)
	Inset: number?, -- Roblox's top bar row (design units): the safe frame starts under it
	SafeBottom: number?, -- design units under the safe frame at the bottom (a phone's home indicator)
	TenFoot: boolean?, -- a TV: the Auto button inside the TV-safe margin
}

-- The thumbstick's zone on a touch screen (shares of the screen): the left 40 %, the lower 2/3.
CapsuleView.ThumbZone = { Width = 0.4, Top = 1 / 3 }

--[[
	Places the opening for a `width` x `height` design-unit screen (the
	whole screen: the stage gui ignores the top bar's inset). The Auto button
	sits bottom left (a TV: inside its safe margin); on touch above the
	thumbstick's zone (the left 40 %, the lower 2/3), its label beside it,
	and the taps that skip leave that zone free (the player can still walk).
]]
function CapsuleView.layoutOpening(refs: OpenRefs, compact: boolean, width: number, height: number, opts: OpeningOpts?)
	local o: OpeningOpts = opts or {}
	local touch = o.Touch == true
	local inset = o.Inset or 0
	refs.Compact = compact
	refs.Touch = touch
	refs.Size = Vector2.new(width, height)
	refs.SafeBottom = math.max(0, o.SafeBottom or 0)
	local zone = CapsuleView.ThumbZone
	if touch then
		refs.Tap.Position = UDim2.fromOffset(width * zone.Width, 0)
		refs.Tap.Size = UDim2.fromOffset(width * (1 - zone.Width), height)
		refs.TapTop.Position = UDim2.fromOffset(0, 0)
		refs.TapTop.Size = UDim2.fromOffset(width * zone.Width, height * zone.Top)
		refs.TapTop.Visible = true
	else
		refs.Tap.Position = UDim2.fromOffset(0, 0)
		refs.Tap.Size = UDim2.fromOffset(width, height)
		refs.TapTop.Visible = false
	end
	refs.Flash.Position = UDim2.fromOffset(0, 0)
	refs.Flash.Size = UDim2.fromOffset(width, height)
	refs.Stage.Position = UDim2.fromOffset(0, 0)
	refs.Stage.Size = UDim2.fromOffset(width, height)
	refs.Bits.Position = UDim2.fromOffset(0, 0)
	refs.Bits.Size = UDim2.fromOffset(width, height)
	refs.Sunburst.Position = UDim2.fromOffset(width / 2, height * 0.48)
	refs.Sunburst.Size = UDim2.fromOffset(height * 1.45, height * 1.45)
	for _, blob in refs.Blobs do
		blob.Size = UDim2.fromOffset(height * 0.62, height * 0.62)
	end
	-- the Auto button and its note (the Controls gui: under the top bar, the safe frame)
	local disc = if compact or touch then CapsuleView.AutoDisc.Compact else CapsuleView.AutoDisc.Normal
	local room = height - inset -- (the Controls gui's height)
	local margin = if o.TenFoot then math.max(24, math.floor(width * 0.05)) else 22
	refs.Auto.Size = UDim2.fromOffset(disc, disc)
	refs.AutoHolder.Size = UDim2.fromOffset(disc, disc)
	local labelSize = if compact or touch then 22 else 24
	refs.AutoLabel.TextSize = labelSize
	refs.AutoLabel.Size = UDim2.fromOffset(if touch then 120 else disc + 60, labelSize + 6)
	local edge = refs.AutoLabel:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Thickness = CapsuleView.TextEdge(labelSize) * 0.8
	end
	-- (the key badge sits on the disc's top-right corner, 9 units out; KEEP more round each part)
	local KEEP = 4
	if touch then
		-- above the thumbstick's zone, the label to the right of the disc
		local zoneTop = height * zone.Top - inset
		local y = math.max(2, zoneTop - disc - 4)
		refs.AutoHolder.AnchorPoint = Vector2.new(0, 0)
		refs.AutoHolder.Position = UDim2.fromOffset(margin, y)
		refs.AutoLabel.AnchorPoint = Vector2.new(0, 0.5)
		refs.AutoLabel.Position = UDim2.new(1, 10, 0.5, 0)
		refs.AutoLabel.TextXAlignment = Enum.TextXAlignment.Left
		refs.Note.Position = UDim2.fromOffset(margin + disc + 10, y + disc / 2 + labelSize * 0.6)
		refs.AutoKeep = {
			{ -- the disc and its key
				Min = Vector2.new(margin - KEEP, inset + y - 9 - KEEP),
				Max = Vector2.new(margin + disc + 9 + KEEP, inset + y + disc + KEEP),
			},
			{ -- its label, beside it
				Min = Vector2.new(margin + disc + 10 - KEEP, inset + y + disc / 2 - (labelSize + 6) / 2 - KEEP),
				Max = Vector2.new(margin + disc + 10 + 120 + KEEP, inset + y + disc / 2 + (labelSize + 6) / 2 + KEEP),
			},
		}
	else
		local top = room - margin - labelSize - 6 - disc -- (the disc's top in the Controls gui)
		refs.AutoHolder.AnchorPoint = Vector2.new(0, 1)
		refs.AutoHolder.Position = UDim2.fromOffset(margin + 10, room - margin - labelSize - 6)
		refs.AutoLabel.AnchorPoint = Vector2.new(0.5, 0)
		refs.AutoLabel.Position = UDim2.new(0.5, 0, 1, 2)
		refs.AutoLabel.TextXAlignment = Enum.TextXAlignment.Center
		refs.Note.Position = UDim2.fromOffset(margin, room - margin - labelSize - 6 - disc - 34)
		local left = margin + 10
		refs.AutoKeep = {
			{ -- the disc and its key
				Min = Vector2.new(left - KEEP, inset + top - 9 - KEEP),
				Max = Vector2.new(left + disc + 9 + KEEP, inset + top + disc + KEEP),
			},
			{ -- "AUTO" under it
				Min = Vector2.new(left + disc / 2 - (disc + 60) / 2 - KEEP, inset + top + disc + 2 - KEEP),
				Max = Vector2.new(left + disc / 2 + (disc + 60) / 2 + KEEP, inset + top + disc + 2 + labelSize + 6 + KEEP),
			},
		}
	end
	refs.Note.Size = UDim2.fromOffset(math.min(width - 2 * margin, 460), 24)
	refs.Note.TextSize = if compact or touch then 20 else 18
	-- the chain's "2 / 5": top middle, just under the top bar (on touch above the thumbstick's zone)
	local chainSize = if compact or touch then 26 else 30
	refs.Chain.TextSize = chainSize
	refs.Chain.Size = UDim2.fromOffset(130, chainSize + 6) -- (room for "10 / 10")
	-- (a TV: inside its 5 % title-safe band, as Auto and its note; touch: top right, over no golem's
	-- head and out of the thumbstick's zone, Auto's corner is the top left there)
	if touch then
		-- (against the Controls gui's own right edge: the notch-safe frame, never the viewport's)
		refs.Chain.AnchorPoint = Vector2.new(1, 0)
		refs.Chain.Position = UDim2.new(1, -margin, 0, 8)
	else
		refs.Chain.AnchorPoint = Vector2.new(0.5, 0)
		refs.Chain.Position = UDim2.fromOffset(width / 2, if o.TenFoot then math.max(8, math.ceil(height * 0.05) - inset) else 8)
	end
	local chainEdge = refs.Chain:FindFirstChild("Edge")
	if chainEdge and chainEdge:IsA("UIStroke") then
		chainEdge.Thickness = CapsuleView.TextEdge(chainSize)
	end
end

-- A golem's name and "1 in N" under its feet (`at`: the tag's top middle, design units; `size`: the
-- name's text size, smaller when the name is wider than `room`: it never runs into its neighbour's).
CapsuleView.TagMin = 16 -- design units (20 px at 1080p; 10 pt on a phone)
function CapsuleView.setTag(
	refs: OpenRefs,
	slot: number,
	name: string,
	chance: string,
	color: Color3,
	at: Vector2,
	size: number,
	room: number?,
	deleted: boolean?,
	waiting: boolean?,
	pitch: number?,
	splitBelow: number?
)
	local tag = refs.Tags[slot]
	if not tag then
		return
	end
	at = Vector2.new(at.X, math.floor(at.Y)) -- (whole units, as the tag stands: what clears the button is measured there)
	local fit = size
	local width = room or math.huge
	local function smallOf(f: number): number
		return math.max(CapsuleView.TagMin, math.floor(f * HatchFx.ChanceShare + 0.5))
	end
	-- (a two-word or longer name can go on two lines, split at the space nearest its middle)
	local first, second = name, nil :: string?
	do
		local best = math.huge
		for i = 1, #name do
			if string.sub(name, i, i) == " " and math.abs(i - #name / 2) < best then
				best = math.abs(i - #name / 2)
				first, second = string.sub(name, 1, i - 1), string.sub(name, i + 1)
			end
		end
	end
	local function nameWidth(f: number, lines: number): number
		local line2 = second
		if lines == 2 and line2 then
			return math.max(TechShopView.textWidth(first, f), TechShopView.textWidth(line2, f)) * 1.04 + 8
		end
		return TechShopView.textWidth(name, f) * 1.04 + 8
	end
	-- the name and its "1 in N" as rows { width, top, height } at a name size, on `lines` lines
	local function textRows(f: number, lines: number): { { number } }
		local s = smallOf(f)
		local nameH = lines * (f + 2) + 4
		return {
			{ math.ceil(nameWidth(f, lines)), 0, nameH },
			{ math.ceil(TechShopView.textWidth(chance, s) + 8), nameH - 4, s + 6 },
		}
	end
	-- (`splitBelow`: a name that would get smaller than that to fit its room on one line goes on two
	-- lines: of one row, the big middle one's at its own size (it keeps to its own column), the others'
	-- at the text floor)
	local splitAt = math.clamp(splitBelow or 0, CapsuleView.TagMin, math.max(CapsuleView.TagMin, size))
	local lines = if splitBelow and second and nameWidth(splitAt, 1) > width then 2 else 1
	while fit > CapsuleView.TagMin and nameWidth(fit, lines) > width do
		fit -= 1
	end
	if lines == 2 then
		-- (two lines only as big as the safe bottom allows: the name, its "1 in N" and its mark above it)
		local floor = refs.Size.Y - refs.SafeBottom - 6
		local markH = if deleted then 36 elseif waiting then CapsuleView.TagMin + 2 + 14 else 0
		while fit > CapsuleView.TagMin and at.Y + 2 * (fit + 2) + smallOf(fit) + 10 + markH > floor do
			fit -= 1
		end
	end
	-- (the Auto button shows: the name steps right of it within its column; where that isn't enough
	-- it gets smaller, never under the floor; still not: on two lines; so no letter hides under it)
	local roomFit = fit
	while fit > CapsuleView.TagMin and not CapsuleView.clears(refs, at, textRows(fit, lines), pitch) do
		fit -= 1
	end
	if lines == 1 and second and not CapsuleView.clears(refs, at, textRows(fit, 1), pitch) then
		lines, fit = 2, roomFit
		while fit > CapsuleView.TagMin and not CapsuleView.clears(refs, at, textRows(fit, 2), pitch) do
			fit -= 1
		end
	end
	local small = smallOf(fit)
	local nameH = lines * (fit + 2) + 4
	tag.Name.Text = if lines == 2 and second then first .. "\n" .. second else name
	tag.Name.TextSize = fit
	tag.Name.Size = UDim2.new(1, 0, 0, nameH)
	tag.Chance.Text = chance
	tag.Chance.TextSize = small
	tag.Chance.TextColor3 = color
	tag.Chance.Position = UDim2.new(0.5, 0, 0, nameH - 4)
	tag.Chance.Size = UDim2.new(1, 0, 0, small + 6)
	for _, label in { tag.Name, tag.Chance } do
		local edge = label:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Thickness = CapsuleView.TextEdge(label.TextSize)
		end
	end
	-- (auto-deleted: the trash mark and DELETED under the chance; won but waiting: its gold note)
	local wait = waiting == true and deleted ~= true
	tag.Deleted.Visible = deleted == true
	tag.Waiting.Visible = wait
	local frameW = math.max(160, math.min(width, fit * 12))
	local markTop = nameH - 4 + small + 6
	-- (does every part clear the Auto button beside it? None of the forms left: the tag says so, its
	-- UnderAuto attribute; the specs hold it never does)
	local clear = CapsuleView.clears(refs, at, textRows(fit, lines), pitch)
	local markW, markH, gap = 0, 0, 0 -- (the mark's box under the "1 in N"; the room kept under it)
	if deleted then
		-- the pill (the trash mark and DELETED) where it clears the Auto button beside it, else the
		-- trash mark alone (a 4:3 screen's Open 10: its second row's first golem beside AUTO ON)
		local wide = CapsuleView.clears(refs, at, { { CapsuleView.DeletedWide, markTop, 30 } }, pitch)
		markW, markH, gap = if wide then CapsuleView.DeletedWide else CapsuleView.DeletedNarrow, 30, 6
		clear = clear and (wide or CapsuleView.clears(refs, at, { { markW, markTop, markH } }, pitch))
		tag.Deleted.Size = UDim2.fromOffset(markW, markH)
		tag.DeletedWord.Visible = wide
		tag.DeletedCan.AnchorPoint = if wide then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5)
		tag.DeletedCan.Position = if wide then UDim2.new(0, 8, 0.5, 0) else UDim2.fromScale(0.5, 0.5)
	elseif wait then
		-- the note at the text floor (TagMin: 10 pt on a phone), its room the golems' pitch (the big
		-- middle one's too): the whole note on one line where it fits, else the short one, else that
		-- on two lines (the narrowest); the first that also clears the Auto button (beside it) wins
		local noteRoom = math.min(width, pitch or width)
		local noteSize = CapsuleView.TagMin
		local options: { NoteOption } = {}
		for _, text in { CapsuleView.WaitingText, CapsuleView.WaitingShort } do
			local w = TechShopView.textWidth(text, noteSize)
			if w + 22 <= noteRoom then
				table.insert(options, { Text = text, Lines = 1, Width = w })
			end
		end
		local widest, count = 0, 0
		for line in string.gmatch(CapsuleView.WaitingLines, "[^\n]+") do
			widest = math.max(widest, TechShopView.textWidth(line, noteSize))
			count += 1
		end
		table.insert(options, { Text = CapsuleView.WaitingLines, Lines = count, Width = widest })
		local function boxOf(option: NoteOption): (number, number)
			return math.min(math.ceil(option.Width) + 22, math.max(60, noteRoom)), option.Lines * (noteSize + 2) + 10
		end
		local pick: NoteOption? = nil
		for _, option in options do
			local w, h = boxOf(option)
			if CapsuleView.clears(refs, at, { { w, markTop, h } }, pitch) then
				pick = option
				break
			end
		end
		clear = clear and pick ~= nil
		local chosen = pick or options[#options] -- (none clears: the narrowest)
		tag.WaitingText.Text = chosen.Text
		tag.WaitingText.TextSize = noteSize
		local noteEdge = tag.WaitingText:FindFirstChild("Edge")
		if noteEdge and noteEdge:IsA("UIStroke") then
			noteEdge.Thickness = CapsuleView.TextEdge(noteSize)
		end
		markW, markH = boxOf(chosen) -- (never wider than its room: neighbours never touch)
		gap = 4
		tag.Waiting.Size = UDim2.fromOffset(markW, markH)
	end
	tag.Frame:SetAttribute("UnderAuto", if clear then nil else true)
	local frameH = markTop + 4 + markH + gap
	-- the name and its "1 in N" step aside together; the mark (narrower) on its own, as far as it needs
	local x = CapsuleView.stepAside(refs, at, textRows(fit, lines), pitch)
	local markX = CapsuleView.stepAside(refs, at, { { markW, markTop, markH } }, pitch) -- DELETED / the note
	for _, mark in { tag.Deleted, tag.Waiting } do
		mark.Position = UDim2.new(0.5, math.ceil(markX - math.floor(x)), 0, markTop)
	end
	tag.Frame.Position = UDim2.fromOffset(x, at.Y)
	tag.Frame.Size = UDim2.fromOffset(frameW, frameH)
end

--[[
	A name tag's x (its middle) under its golem at `at`: while the Auto
	button shows, a tag whose parts (`rows`: { width, top, height } each,
	centred) would lie under its disc, key or label steps right, just
	enough, but never out of its own column (`pitch`: the golems' pitch, a
	tag of a neighbour keeps its room); hidden Auto: it stays put.
]]
function CapsuleView.stepAside(refs: OpenRefs, at: Vector2, rows: { { number } }, pitch: number?): number
	if not refs.AutoHolder.Visible or not pitch then
		return at.X
	end
	local need, half = 0, 0
	for _, row in rows do
		local w, top, h = row[1], row[2], row[3]
		if w > 0 and h > 0 then
			half = math.max(half, w / 2)
			for _, keep in refs.AutoKeep do
				local y0, y1 = at.Y + top, at.Y + top + h
				local x0, x1 = at.X - w / 2, at.X + w / 2
				if y0 < keep.Max.Y and y1 > keep.Min.Y and x0 < keep.Max.X and x1 > keep.Min.X then
					need = math.max(need, keep.Max.X - x0)
				end
			end
		end
	end
	if need <= 0 then
		return at.X
	end
	-- (whole units, rounded up: offsets are whole numbers, the part clears the button)
	return math.ceil(at.X + math.min(need, math.max(0, pitch / 2 - half)))
end

-- Do `rows` (stepped aside as stepAside puts them) clear the Auto button? (Hidden Auto: always.)
function CapsuleView.clears(refs: OpenRefs, at: Vector2, rows: { { number } }, pitch: number?): boolean
	if not refs.AutoHolder.Visible or not pitch then
		return true
	end
	local x = CapsuleView.stepAside(refs, at, rows, pitch)
	for _, row in rows do
		local w, top, h = row[1], row[2], row[3]
		if w > 0 and h > 0 then
			for _, keep in refs.AutoKeep do
				local y0, y1 = at.Y + top, at.Y + top + h
				local x0, x1 = x - w / 2, x + w / 2
				if y0 < keep.Max.Y and y1 > keep.Min.Y and x0 < keep.Max.X and x1 > keep.Min.X then
					return false
				end
			end
		end
	end
	return true
end

--[[
	A tag's DELETED pill and its waiting note fade with the name (`alpha`
	0 shown .. 1 gone: HatchStage poses it with the name's), so Reduce
	motion's calm opening fades them with the stage too.
]]
function CapsuleView.fadeMarks(tag: Tag, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, mark in { tag.Deleted, tag.Waiting } do
		if not mark.Visible then
			continue
		end
		mark.BackgroundTransparency = a
		for _, d in mark:GetDescendants() do
			if d:IsA("UIStroke") then
				d.Transparency = a
			elseif d:IsA("TextLabel") then
				d.TextTransparency = a
			elseif d:IsA("Frame") then
				-- (the trash mark's can: solid; its slits see-through, 0.55; its holder stays clear)
				local name = d.Name
				if name == "Handle" or name == "Lid" or name == "Body" then
					d.BackgroundTransparency = a
				elseif string.sub(name, 1, 4) == "Slit" then
					d.BackgroundTransparency = 0.55 + 0.45 * a
				end
			end
		end
		local rim = mark:FindFirstChild("Rim")
		if rim and rim:IsA("UIStroke") then
			rim.Transparency = a
		end
	end
end

--[[
	The Auto button: shown where Auto can run (`visible`), green and its
	arrow turning while on; its key on a white badge (`text` "G", or a
	gamepad's `glyph`; nothing on touch).
]]
function CapsuleView.setAuto(refs: OpenRefs, visible: boolean, on: boolean, text: string, glyph: string?)
	refs.AutoHolder.Visible = visible
	refs.Auto.BackgroundColor3 = if on then BrightTheme.Paints.Green.Bottom else rgb(46, 50, 64)
	local gap = refs.AutoArrow:FindFirstChild("Gap")
	if gap and gap:IsA("Frame") then
		gap.BackgroundColor3 = refs.Auto.BackgroundColor3
	end
	local rim = refs.Auto:FindFirstChild("Rim")
	if rim and rim:IsA("UIStroke") then
		rim.Color = if on then BrightTheme.Paints.Green.Edge else Color3.new(1, 1, 1)
	end
	refs.AutoLabel.Text = if on then "AUTO ON" else "AUTO"
	local hasGlyph = glyph ~= nil and glyph ~= ""
	refs.AutoKey.Visible = hasGlyph or text ~= ""
	refs.AutoKeyText.Text = text
	refs.AutoKeyText.Visible = not hasGlyph
	refs.AutoGlyph.Image = glyph or ""
	refs.AutoGlyph.Visible = hasGlyph
end

-- Every button of the opening (tests: 44 pt at the phone scale; on touch clear of the thumbstick's zone).
function CapsuleView.openTargets(refs: OpenRefs): { GuiObject }
	return { refs.Auto }
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

---------------------------------------------------------------- the stall's odds board

--[[
	Fills the CapsuleStall's OddsBoard SurfaceGui (`gui`, its old labels are
	removed) with one capsule's odds, big enough to read on the 1.9 x 3.9
	stud board: the title, a line saying whose odds these are and where each
	golem's own chance is (the capsule menu), then per rarity (the six rows
	the stall's rarity chips mark, CapsuleConfig.rarities order) the rarity's total
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
	local rarities = CapsuleConfig.rarities() -- (the golems' six: a "Secret" Rarity is for ores)
	local rows = #rarities
	local rowH = 0.8 / rows
	for i, info in rarities do
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
