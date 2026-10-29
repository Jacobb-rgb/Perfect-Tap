--[[
	The luck boosts view (pure builder + pure helpers; BoostController fills
	it in) and the boost chips under the HUD coins.

	Panel (one ScreenGui, in the Pop look: a green Pop window, Pop.tabs, the
	boost card painted in its colour with its live 3D picture on light rays,
	the offers as dark strips with a gold coin / green Robux price button,
	the odds in a dark studded well with rarity-coloured rows; the shared
	pieces: "the Pop look" below):
	  header   LUCK BOOSTS, a line about boosts (or the last message), your
	           coins, the X button
	  tabs     TRIPLE LUCKY · HEXA LUCKY (LB / RB on a gamepad); opened
	           without a boost asked for, the view shows the last tab while
	           it can be bought, else the first one that can (openTab: not
	           coming soon, an effect for this player); a gamepad starts on
	           the tab, never on an offer
	  left     the boost: icon, name, ACTIVE + time left (or Not active),
	           what it does (a short card on small phones: no name, the
	           tab shows it; status and a two-line Card.Short next to the
	           icon), the luck it gives, the offers (coins: "+5 MIN ·
	           $12K", Robux: "+15 MIN · 39 R$", "COMING SOON" while the
	           product id is 0, or while the package that uses the boost
	           isn't in the game: soonSet; Robux packs are hidden where
	           paid random items are restricted) and a note about the
	           coin top-up rule
	  right    THE ODDS in numbers, before you buy (Roblox rule):
	             Hexa Lucky   every ore of a zone you can mine (your current
	                          zone, < > to see the others) without and with
	                          the boost, "Rare or better" on top
	             Triple Lucky every golem of a capsule (< > for the other
	                          capsules) without and with the boost, the
	                          lucky golems' total on top
	           Rows go rarest first, so the numbers the boost raises are
	           in view even on a small phone (the summary row stays while
	           two rows fit under it; the note goes first); the list shows
	           whole rows only (no half-cut row; the rest scrolls).
	  footer   the control hint; gamepads get the platform's own glyphs
	           (setHint; on phones and TVs only the gamepad row, bigger)
	The odds table (buildTable / setTable) is shared with EnchantView (the
	odds-boosting enchants show their new odds the same way).

	Chips (buildChips / setChips / placeChips, their own small ScreenGui,
	scaled with the HUD): one pill per running boost (its picture ringed
	in its colour, the tag and the time left: [clover] TRIPLE 4:59, [gem]
	HEXA 1h 05m: shape, word and colour each tell them apart), or a BOOSTS
	launcher when none runs; a tap opens the view. They sit in the
	left column under the TRAIN chip (chipsTop), which sits under the
	coins and their "+$X" popups; the 72-unit touch area grows down from
	the pill only, so it never reaches over the train chip.

	Designed for 720 design units of height (HudController.uiScale). The
	compact layout (phones, TVs) makes every button at least 72 units
	(44 pt at the phone scale 0.62) and the texts bigger.
	Everything shown comes from the State snapshot (Boosts, Bonuses,
	BlasterLevel, Perks) and the shared configs, so the cards show exactly
	what the server will quote (BoostConfig.coinQuote / coinPrice).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local LimitedGolems = require(Shared.Config.LimitedGolems)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local WorldLayout = require(Shared.Config.WorldLayout)
local PictureModels = require(Shared.Builders.PictureModels)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)
local HudBubble = require(script.Parent.HudBubble)
local TechShopView = require(script.Parent.TechShopView)
local TrainView = require(script.Parent.TrainView)

local BoostView = {}

-- One buy button on a boost card.
export type Offer = {
	Id: string, -- BoostConfig offer id
	Kind: string, -- BoostConfig kind id
	Robux: boolean,
	Product: string?, -- MonetizationConfig key (Robux offers)
	Seconds: number,
	Price: number?, -- coins (coin offers)
	Label: string, -- "+5 MIN"
	PriceText: string, -- "$12.5K", "39 R$", "COMING SOON"
	Text: string, -- the button text ("+5 MIN · $12.5K"; the compact layout puts the price on a second line)
	CanBuy: boolean,
	Reason: string?, -- why not: a BoostConfig.Reasons code or "ComingSoon"
}

export type Card = {
	Kind: string,
	Name: string,
	Description: string,
	Short: string, -- the description in two short lines (a short card: small phones)
	Color: Color3,
	Remaining: number, -- seconds left (0 = off)
	Active: boolean,
	Status: string, -- "ACTIVE: 4:59 left" / "Not active"
	StatusColor: Color3,
	KeyLine: string, -- what it gives the player now
	Offers: { Offer },
	Note: string,
}

-- One line of an odds table (texts already formatted).
export type OddsRow = {
	Name: string,
	Color: Color3,
	Before: string,
	After: string,
	Change: number, -- > 0 the chance grows, < 0 it drops, 0 the same
}

export type OddsTable = {
	Title: string, -- the zone / capsule shown
	Header: string, -- the first column's header ("ORE", "GOLEM", "PER ORE")
	BeforeHeader: string,
	AfterHeader: string,
	Summary: OddsRow?, -- a highlighted first row ("Rare or better")
	Rows: { OddsRow },
	Note: string,
}

export type Chip = { Kind: string, Mult: string, Tag: string, Text: string, Color: Color3 }

export type RowRefs = { Frame: Frame, Name: TextLabel, Before: TextLabel, After: TextLabel }

export type TableRefs = {
	Frame: Frame,
	Prev: TextButton,
	Next: TextButton,
	Title: TextLabel,
	Head: { TextLabel }, -- name, before, after
	Summary: RowRefs,
	List: ScrollingFrame,
	Rows: { RowRefs },
	Note: TextLabel,
	Compact: boolean,
	Width: number,
	HasSelector: boolean,
	ShowSummary: boolean, -- false on a very short table (layoutTable)
	ShowNote: boolean, -- false on a very short table, or when the note is shown elsewhere
	Data: OddsTable?, -- the last data (layoutTable fills the summary again)
	CanSwitch: boolean, -- the arrows show (else the title row is a short one)
	Height: number, -- the last layout's box (setTable lays out again when CanSwitch changes)
	WithNote: boolean,
}

export type CardRefs = {
	Frame: Frame,
	Icon: Frame,
	Name: TextLabel,
	Status: TextLabel,
	Description: TextLabel,
	KeyLine: TextLabel,
	Offers: { TextButton },
	Note: TextLabel,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Receipt: TextLabel,
	Balance: Frame,
	BalanceAmount: TextLabel,
	Close: TextButton,
	TabBar: Frame,
	Tabs: { [string]: TextButton }, -- by boost kind
	TabGlyphs: { ImageLabel }, -- LB, RB
	Card: CardRefs,
	Odds: TableRefs,
	Hint: TextLabel,
	PadHint: Frame,
	PadGlyphs: { ImageLabel },
	PadMode: boolean,
	Tab: string,
	Compact: boolean,
	MaxWidth: number, -- the last layout's room (setHint lays out again when the gamepad row comes or goes)
	MaxHeight: number,
}

export type ChipRefs = {
	Gui: ScreenGui,
	Row: Frame,
	Chips: { [string]: TextButton }, -- by boost kind
	Launcher: TextButton,
	Glyph: ImageLabel, -- the gamepad key that opens the view (shown with a gamepad)
}

BoostView.Tabs = BoostConfig.KindIds
BoostView.TabTitles = { TripleLucky = "TRIPLE LUCKY", HexaLucky = "HEXA LUCKY" } :: { [string]: string }
BoostView.MinHeight = 380
BoostView.CoinsBottom = 96 -- HudView's coins panel (16..90) and a gap
BoostView.FloatersBottom = 96 + 60 -- HudView's "+$X" popups (Floaters at 16, 96, 60 tall)
-- TrainView's chip (at TrainView.ChipTop) is this tall (its CHIP metrics); the boost chips go under it
BoostView.TrainChipHeight = { Normal = 66, Compact = 84 } :: { [string]: number }
BoostView.ChipGap = 8 -- between the train chip and the boost chips
BoostView.ChipLeft = 16 -- lines up with the coins and the train chip
BoostView.ChipHeight = 40 -- the visible pill
BoostView.ChipHit = 72 -- the touch area: the pill and below it (44 pt at the phone scale)
BoostView.Separator = TechShopView.Separator
-- the paid-random policy attribute Policy sets (nil = not known yet = restricted)
BoostView.RestrictedAttribute = "PaidRandomRestricted"
-- ReplicatedStorage attribute BoostService sets: the boost kinds / enchant ids
-- that are coming soon (the package that uses them isn't in the game yet)
BoostView.SoonAttribute = "TerraForgeComingSoon"
BoostView.SoonText = {
	TripleLucky = "Coming soon, with the golem capsules",
} :: { [string]: string }
-- a short card's description (small phones: it sits next to the icon, two lines)
BoostView.ShortText = {
	TripleLucky = "Golem capsules: the rarest golems are 3x as likely.",
	HexaLucky = "Mining: ore luck x2.5. Rarer ores in every rock.",
} :: { [string]: string }
-- the HUD chips' tag before the timer (with the boost's picture: not told apart by colour alone)
BoostView.ChipTags = { TripleLucky = "TRIPLE", HexaLucky = "HEXA" } :: { [string]: string }
-- the gamepad hint row on phones and TVs: bigger, with a footer of its own
BoostView.PadHintScale = 1.25
BoostView.PadFooter = 34

local SEP = TechShopView.Separator
local PAD = 16
local GAP = 8
local SCROLLBAR = 8
local rgb = Color3.fromRGB

---------------------------------------------------------------- pure helpers

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function num(v: any, default: number): number
	return if finite(v) then v else default
end

local function trim(text: string): string
	if text:find("%.") then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text
end

-- A chance (0..1) as a percent with three significant digits:
-- "61.2%", "3.7%", "0.59%", "0.015%"; "0%"; "100%".
function BoostView.pct(chance: number): string
	local p = math.clamp(num(chance, 0), 0, 1) * 100
	if p <= 0 then
		return "0%"
	elseif p >= 99.95 and p < 100 then
		return "99.9%"
	elseif p >= 100 then
		return "100%"
	elseif p < 0.0001 then
		return "<0.0001%"
	end
	local digits = math.max(1, 2 - math.floor(math.log10(p)))
	if p >= 10 then
		digits = 1
	end
	return trim(string.format(`%.{digits}f`, p)) .. "%"
end

-- A luck multiplier: "x1", "x1.3", "x2.5", "x6.25"
function BoostView.mult(value: number): string
	return "x" .. trim(string.format("%.2f", num(value, 1)))
end

-- "5 MIN", "15 MIN", "1 HOUR", "2 HOURS"
function BoostView.duration(seconds: number): string
	local s = math.max(0, math.floor(num(seconds, 0)))
	if s >= 3600 and s % 3600 == 0 then
		local h = s // 3600
		return if h == 1 then "1 HOUR" else `{h} HOURS`
	end
	return `{math.max(1, math.floor(s / 60 + 0.5))} MIN`
end

-- "4:59", "1h 05m"
function BoostView.timer(seconds: number): string
	return Format.seconds(math.max(0, math.ceil(num(seconds, 0))))
end

-- Is the player restricted from paid random items? (the attribute Policy
-- sets; nil = not known yet = restricted, the strict answer)
function BoostView.restricted(attribute: any): boolean
	return attribute ~= false
end

-- The coming-soon ids from the ReplicatedStorage attribute ("A,B"; anything else: none).
function BoostView.soonSet(attribute: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(attribute) == "string" then
		for id in string.gmatch(attribute, "[^,%s]+") do
			set[id] = true
		end
	end
	return set
end

-- A `soon` key that is no boost or enchant id: every Robux button waits for
-- step 8's receipts gate (src/server/Receipts.luau; the ReplicatedStorage
-- attribute MonetizationConfig.ReceiptsAttribute isn't true yet). The server
-- answers "ComingSoon" then too.
BoostView.RobuxSoon = "Robux"

-- What the controllers pass as `soon`: soonSet of the coming-soon attribute,
-- plus RobuxSoon while the receipts attribute isn't true.
function BoostView.soonNow(soonAttribute: any, receiptsAttribute: any): { [string]: boolean }
	local set = BoostView.soonSet(soonAttribute)
	if receiptsAttribute ~= true then
		set[BoostView.RobuxSoon] = true
	end
	return set
end

local function safeState(state: any): { [string]: any }
	return if type(state) == "table" then state else {}
end

local function bonusesOf(state: { [string]: any }): { [string]: any }
	local bonuses = state.Bonuses
	return if type(bonuses) == "table" then bonuses else {}
end

local function levelOf(state: { [string]: any }): number
	local level = state.BlasterLevel
	return if finite(level) then level else 1
end

-- The level coin prices follow (State.PriceLevel: BlasterData.priceLevel, never lowered by a rebirth).
local function priceLevelOf(state: { [string]: any }): number
	local level = state.PriceLevel
	return if finite(level) then level else levelOf(state)
end

local function vipOf(state: { [string]: any }): boolean
	local perks = state.Perks
	return type(perks) == "table" and perks.ForgeVip == true
end

-- What a luck card compares, from a State snapshot (State.Bonuses: the
-- capped totals the server applies). Hexa Lucky's part counts only while
-- it still runs at `now` (a snapshot can be a moment older than its end).
-- Server Luck's ore luck now (x2 while ReplicatedStorage ServerLuckUntil is
-- ahead of the server clock: ServerBoostService; 1 = off).
BoostView.ServerLuckMult = 2
function BoostView.serverLuck(): number
	local ok, on = pcall(function(): boolean
		local untilTime = game:GetService("ReplicatedStorage"):GetAttribute("ServerLuckUntil")
		return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
	end)
	return if ok and on then BoostView.ServerLuckMult else 1
end

function BoostView.context(rawState: any, now: number?): BoostConfig.LuckContext
	local state = safeState(rawState)
	local bonuses = bonusesOf(state)
	local mult = math.max(1, num(bonuses.OreLuckMult, 1))
	if now and mult > 1 and not BoostConfig.active(state.Boosts, "HexaLucky", now) then
		-- the multiplier without Hexa Lucky: Server Luck's while it runs (the State can lag)
		mult = math.min(mult, BoostView.serverLuck())
	end
	return {
		BlasterLevel = levelOf(state),
		Vip = vipOf(state),
		OreLuckPct = math.max(0, num(bonuses.OreLuckPct, 0)),
		OreLuckMult = mult,
		ArtifactPct = math.max(0, num(bonuses.ArtifactPct, 0)),
	}
end

-- The zones the player can mine (BoostConfig.minableZones).
function BoostView.zones(rawState: any): { WorldLayout.Zone }
	local state = safeState(rawState)
	return BoostConfig.minableZones(levelOf(state), vipOf(state))
end

--[[
	The zone an odds table starts on: the zone the player stands in when
	they can mine it, else the hardest zone they can mine (the highest
	MinBlaster; a public zone before a VIP one), preferring zones where
	luck has an effect. nil when they can mine nowhere.
]]
function BoostView.defaultZone(rawState: any, currentZone: string?): string?
	local zones = BoostView.zones(rawState)
	for _, zone in zones do
		if zone.Id == currentZone then
			return zone.Id
		end
	end
	local best: WorldLayout.Zone? = nil
	local function score(zone: WorldLayout.Zone): number
		local lucky = false
		for oreId in BoostConfig.zoneWeights(zone) do
			lucky = lucky or BoostConfig.isLuckyOre(oreId)
		end
		for oreId in (BoostConfig.crystalWeights(zone) or {}) :: { [string]: number } do
			lucky = lucky or BoostConfig.isLuckyOre(oreId)
		end
		return (if lucky then 1000 else 0) + zone.MinBlaster * 10 + (if zone.VipOnly then 0 else 1)
	end
	for _, zone in zones do
		if not best or score(zone) > score(best) then
			best = zone
		end
	end
	return if best then best.Id else nil
end

-- The id `step` places after / before `current` in `ids` (wrapping).
function BoostView.cycle(ids: { string }, current: string?, step: number): string?
	if #ids == 0 then
		return nil
	end
	local index = table.find(ids, current or "") or 1
	return ids[(index - 1 + step) % #ids + 1]
end

-- The capsules whose odds the Triple Lucky card shows (the ones the player
-- may open; a limited edition's only while it is on sale at `now`, unix
-- seconds, default the clock: LimitedGolems.onSale).
function BoostView.capsules(restricted: boolean, now: number?): { string }
	local list = {}
	local t = if type(now) == "number" then now else os.time()
	for _, capsule in CapsuleConfig.List do
		if not (restricted and CapsuleConfig.isPaidRandom(capsule.Id)) and LimitedGolems.onSale(capsule.Id, t) then
			table.insert(list, capsule.Id)
		end
	end
	return list
end

--[[
	The tab the view opens on when no boost is asked for: `current` (the
	last one) while it can be bought, else the first tab that can (not
	coming soon, `soon`: soonSet, and with an effect for this player:
	BoostConfig.hasEffect), else `current`. So the BOOSTS launcher, L and
	D-pad right never open on a page with nothing to buy.
]]
function BoostView.openTab(current: string, rawState: any, soon: { [string]: boolean }?): string
	local state = safeState(rawState)
	local soonSet: { [string]: boolean } = soon or {}
	local function usable(kindId: string): boolean
		return BoostConfig.Kinds[kindId] ~= nil and soonSet[kindId] ~= true and BoostConfig.hasEffect(kindId, levelOf(state), vipOf(state))
	end
	if usable(current) then
		return current
	end
	for _, kindId in BoostView.Tabs do
		if usable(kindId) then
			return kindId
		end
	end
	return current
end

-- The status text for an offer that can't be bought.
function BoostView.reasonText(reason: string?): string
	if reason == "ComingSoon" then
		return MonetizationConfig.StatusText.ComingSoon
	end
	local text = if reason then BoostConfig.Reasons[reason] else nil
	return text or "You can't buy that right now"
end

local function offerOf(
	offer: BoostConfig.Offer,
	state: { [string]: any },
	coins: number,
	now: number,
	effect: boolean,
	soon: boolean,
	robuxSoon: boolean
): Offer
	local boosts = state.Boosts
	local robux = offer.Product ~= nil
	local reason: string? = nil
	local price: number? = nil
	local priceText: string
	if soon then
		-- nothing in the game uses this boost yet
		priceText = "COMING SOON"
		reason = "ComingSoon"
	elseif robux then
		local product = MonetizationConfig.get(offer.Product)
		-- a real id AND step 8's receipts gate on (RobuxSoon not in `soon`)
		local live = MonetizationConfig.keyLive(offer.Product) and not robuxSoon
		priceText = if live and product then `{product.Robux} R$` else "COMING SOON"
		if not effect then
			reason = "NoEffect"
		elseif not BoostConfig.canExtend(boosts, offer.Boost, offer.Seconds, now) then
			reason = "Full"
		elseif not live then
			reason = "ComingSoon"
		end
	else
		price = BoostConfig.coinPrice(offer.Id, priceLevelOf(state))
		priceText = Format.money(price or 0)
		local _, quoteReason = BoostConfig.coinQuote(boosts, offer.Id, levelOf(state), vipOf(state), now, priceLevelOf(state))
		reason = quoteReason
		if reason == nil and price ~= nil and coins < price then
			reason = "NoCoins"
		end
	end
	return {
		Id = offer.Id,
		Kind = offer.Boost,
		Robux = robux,
		Product = offer.Product,
		Seconds = offer.Seconds,
		Price = price,
		Label = `+{BoostView.duration(offer.Seconds)}`,
		PriceText = priceText,
		Text = `+{BoostView.duration(offer.Seconds)}{SEP}{priceText}`,
		CanBuy = reason == nil,
		Reason = reason,
	}
end

--[[
	The two boost cards (BoostConfig.KindIds order) from a State snapshot,
	the coins on screen, the server time `now` and the player's paid-random
	policy. Offers that are paid random items are left out where they are
	restricted (BoostConfig.isPaidRandom). A kind in `soon` (soonSet) is
	shown with every offer "COMING SOON" (the server refuses it too).
]]
function BoostView.cards(rawState: any, coins: number, now: number, restricted: boolean, soon: { [string]: boolean }?): { Card }
	local state = safeState(rawState)
	local soonSet: { [string]: boolean } = soon or {}
	local cash = num(coins, 0)
	local ctx = BoostView.context(state, now)
	local list: { Card } = {}
	for _, kindId in BoostConfig.KindIds do
		local kind = BoostConfig.Kinds[kindId]
		local remaining = BoostConfig.remaining(state.Boosts, kindId, now)
		local effect = BoostConfig.hasEffect(kindId, ctx.BlasterLevel, ctx.Vip)
		local offers: { Offer } = {}
		for _, group in { BoostConfig.CoinOffers, BoostConfig.RobuxOffers } do
			for _, offer in group do
				if offer.Boost == kindId and not (restricted and BoostConfig.isPaidRandom(offer.Id)) then
					local robuxSoon = soonSet[BoostView.RobuxSoon] == true
					table.insert(offers, offerOf(offer, state, cash, now, effect, soonSet[kindId] == true, robuxSoon))
				end
			end
		end
		local keyLine: string
		if kind.Target == "Mining" then
			local without, with = BoostConfig.hexaLuck(ctx.OreLuckPct, BoostView.serverLuck())
			keyLine = `Your ore luck: {BoostView.mult(without)} → {BoostView.mult(with)}`
			if not effect then
				keyLine = BoostConfig.Reasons.NoEffect
			end
		else
			keyLine = `Lucky golems in every capsule: {BoostView.mult(kind.Mult)} as likely`
		end
		if soonSet[kindId] then
			keyLine = BoostView.SoonText[kindId] or MonetizationConfig.StatusText.ComingSoon
		end
		local minutes = math.floor(BoostConfig.CoinBuyBelow / 60)
		local hours = math.floor(BoostConfig.MaxStackSeconds / 3600)
		table.insert(list, {
			Kind = kindId,
			Name = kind.Name,
			Description = kind.Description,
			Short = BoostView.ShortText[kindId] or kind.Description,
			Color = kind.Color,
			Remaining = remaining,
			Active = remaining > 0,
			Status = if remaining > 0 then `ACTIVE: {BoostView.timer(remaining)} left` else "Not active",
			StatusColor = if remaining > 0 then Theme.Good else Theme.TextDim,
			KeyLine = keyLine,
			Offers = offers,
			Note = `Coins top a boost up below {minutes} min left. At most {hours} h at once.`,
		})
	end
	return list
end

local function change(before: number, after: number): number
	local d = after - before
	if math.abs(d) <= 1e-9 * math.max(1, math.abs(before)) then
		return 0
	end
	return if d > 0 then 1 else -1
end

-- One odds row from two chances.
function BoostView.row(name: string, color: Color3, before: number, after: number): OddsRow
	return { Name = name, Color = color, Before = BoostView.pct(before), After = BoostView.pct(after), Change = change(before, after) }
end

-- The rows rarest first (`orders[i]`: row i's Rarity order; the same
-- rarity keeps its order), so a short table shows what luck raises.
function BoostView.rarestFirst(rows: { OddsRow }, orders: { number }): { OddsRow }
	local index: { number } = {}
	for i in rows do
		table.insert(index, i)
	end
	table.sort(index, function(a: number, b: number): boolean
		local oa, ob = orders[a] or 0, orders[b] or 0
		if oa ~= ob then
			return oa > ob
		end
		return a < b
	end)
	local out: { OddsRow } = {}
	for _, i in index do
		table.insert(out, rows[i])
	end
	return out
end

--[[
	Hexa Lucky's table for a zone: the chance of every ore of the zone in
	one ore roll without and with the boost (BoostConfig.oreOdds at the
	player's luck from BoostConfig.hexaLuck), rarest first, "Rare or
	better" on top. An unknown zone gives an empty table.
]]
function BoostView.hexaOdds(rawState: any, zoneId: string?): OddsTable
	local ctx = BoostView.context(rawState, nil)
	local without, with = BoostConfig.hexaLuck(ctx.OreLuckPct, BoostView.serverLuck())
	local zone = if zoneId then WorldLayout.ZoneById[zoneId] else nil
	local rows: { OddsRow } = {}
	local summary: OddsRow? = nil
	local note = `Ore luck {BoostView.mult(without)} without, {BoostView.mult(with)} with Hexa Lucky. Chance per ore in a rock you break.`
	if zone then
		-- one block of rows per table the server rolls from (BoostConfig.zoneWeights; a mine
		-- floor's crystal rocks roll their own richer table, labelled as such)
		local function block(weights: { [string]: number }, suffix: string): { OddsRow }
			local after: { [string]: number } = {}
			for _, line in BoostConfig.oreOdds(weights, with) do
				after[line.Ore] = line.Chance
			end
			local list: { OddsRow } = {}
			local orders: { number } = {}
			for _, line in BoostConfig.oreOdds(weights, without) do
				local ore = OreData.ById[line.Ore]
				local info = Rarity.get(ore.Rarity)
				table.insert(list, BoostView.row(ore.Name .. suffix, info.Color, line.Chance, after[line.Ore] or 0))
				table.insert(orders, info.Order)
			end
			return BoostView.rarestFirst(list, orders)
		end
		local weights = BoostConfig.zoneWeights(zone)
		local crystal = BoostConfig.crystalWeights(zone)
		rows = block(weights, "")
		if crystal then
			for _, row in block(crystal, " (crystal rock)") do
				table.insert(rows, row)
			end
		end
		local before = BoostConfig.rareShare(weights, without)
		local crystalBefore = if crystal then BoostConfig.rareShare(crystal, without) else 0
		if before > 0 then
			summary = BoostView.row("Rare or better", Rarity.get("Rare").Color, before, BoostConfig.rareShare(weights, with))
		elseif crystalBefore <= 0 then
			note = "No Rare ores in this zone: Hexa Lucky changes nothing here."
		end
	end
	return {
		Title = if zone then zone.Name else "No zone",
		Header = "ORE",
		BeforeHeader = "WITHOUT",
		AfterHeader = "WITH HEXA",
		Summary = summary,
		Rows = rows,
		Note = note,
	}
end

--[[
	Triple Lucky's table for a capsule: the chance of every golem without
	and with the boost (CapsuleConfig.odds), rarest first, the lucky
	golems' total on top.
]]
function BoostView.tripleOdds(capsuleId: string?): OddsTable
	local capsule = if capsuleId then CapsuleConfig.ById[capsuleId] else nil
	local rows: { OddsRow } = {}
	local summary: OddsRow? = nil
	if capsule then
		local after: { [string]: number } = {}
		for _, line in CapsuleConfig.odds(capsule.Id, true) do
			after[line.Golem] = line.Chance
		end
		local from = Rarity.get(capsule.LuckyFrom)
		local luckyBefore, luckyAfter = 0, 0
		local orders: { number } = {}
		for _, line in CapsuleConfig.odds(capsule.Id, false) do
			local golem = GolemConfig.ById[line.Golem]
			local info = Rarity.get(golem.Rarity)
			local a = after[line.Golem] or 0
			table.insert(rows, BoostView.row(golem.Name, info.Color, line.Chance, a))
			table.insert(orders, info.Order)
			if info.Order >= from.Order then
				luckyBefore += line.Chance
				luckyAfter += a
			end
		end
		rows = BoostView.rarestFirst(rows, orders)
		summary = BoostView.row(`{from.Name} or better`, from.Color, luckyBefore, luckyAfter)
	end
	local price = if capsule and capsule.Currency == "Robux" then "Robux" else "coins"
	return {
		Title = if capsule then capsule.Name else "No capsule",
		Header = "GOLEM",
		BeforeHeader = "WITHOUT",
		AfterHeader = "WITH TRIPLE",
		Summary = summary,
		Rows = rows,
		Note = if capsule
			then `{capsule.Name} ({price}): chance per golem. {capsule.LuckyFrom}+ golems are 3x as likely with Triple Lucky.`
			else "",
	}
end

-- The HUD chips for the running boosts (KindIds order), from a State snapshot at server time `now`.
function BoostView.chips(rawState: any, now: number): { Chip }
	local state = safeState(rawState)
	local list: { Chip } = {}
	for _, kindId in BoostConfig.KindIds do
		local remaining = BoostConfig.remaining(state.Boosts, kindId, now)
		if remaining > 0 then
			local kind = BoostConfig.Kinds[kindId]
			table.insert(list, {
				Kind = kindId,
				Mult = BoostView.mult(kind.Mult),
				Tag = BoostView.ChipTags[kindId] or string.upper(kind.Name),
				Text = BoostView.timer(remaining),
				Color = kind.Color,
			})
		end
	end
	return list
end

---------------------------------------------------------------- the Pop look (shared)

--[[
	The owner (2026-10-21): "all of these look like terribly old UI: make
	them new, modern, colourful, clean items, more Roblox style". The luck
	boosts, the Enchant shop and the Gear shop wear the Robux Shop's Pop
	look (Pop.luau) instead of LightSkin's recolouring. The pieces they
	share (EnchantView and GearShopView use them too):
	  popWindow / placeWindow  a UIKit.panel becomes a Pop window: a black
	           frame, a bright header band in the window's colour (shine,
	           diagonal stripes, studs) behind the title, a dark studded body
	  popText  a label in white (or a bright ink: ink) with a black edge
	  popButton a UIKit.button becomes a painted Pop button. Its holder is
	           the face (paint, black border, light rim, studs); the
	           TextButton covers it and keeps its Text (the controllers set
	           "...", "BOUGHT!"), shown by a row in white with an optional
	           mark beside it (setMark: a drawn coin, the Robux mark, a
	           crystal): syncButton
	  style    the controllers' UITheme colours as Pop paints (paintFor)
	  backing  a painted pill right behind a label (chips: "LV 2/5", "NEW")
	  burst    light rays and a soft glow behind a picture
]]

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end
BoostView.holderOf = holderOf

local WHITE = Color3.new(1, 1, 1)

local function colorKey(c: Color3): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

BoostView.ShardButton = rgb(70, 170, 220) -- EnchantView's SHARDS buttons
-- a dark face (the chips on bright cards, the money pills)
BoostView.DarkPaint = { Top = rgb(58, 60, 74), Bottom = rgb(24, 25, 32), Edge = PopTheme.Outline } :: Pop.Paint

-- the UITheme colours the controllers style buttons with -> Pop paints
local PAINTS: { [string]: string } = {
	[colorKey(Theme.Accent)] = "Yellow",
	[colorKey(Theme.Coin)] = "Yellow",
	[colorKey(Theme.Good)] = "Green",
	[colorKey(Theme.Bad)] = "Red",
	[colorKey(Theme.Info)] = "Blue",
	[colorKey(BoostView.ShardButton)] = "Blue",
	[colorKey(Theme.PanelLight)] = "Slate",
	[colorKey(Theme.Panel)] = "Slate",
}

function BoostView.paintFor(color: Color3): Pop.Paint
	return Pop.paint(PAINTS[colorKey(color)] or "Slate")
end

-- the UITheme text colours -> bright inks for the dark Pop body
local INKS: { [string]: Color3 } = {
	[colorKey(Theme.Text)] = WHITE,
	[colorKey(Theme.TextDim)] = rgb(208, 214, 228),
	[colorKey(Theme.Good)] = rgb(140, 255, 90),
	[colorKey(Theme.Bad)] = rgb(255, 112, 104),
	[colorKey(Theme.Info)] = rgb(120, 212, 255),
	[colorKey(Theme.Accent)] = rgb(255, 214, 72),
	[colorKey(Theme.Coin)] = rgb(255, 222, 72),
}

function BoostView.ink(color: Color3): Color3
	return INKS[colorKey(color)] or color
end

-- A paint for a rarity / ore / golem colour (a pale or grey one: slate).
function BoostView.paintOf(color: Color3): Pop.Paint
	local _, saturation = color:ToHSV()
	if saturation < 0.25 then
		return Pop.paint("Slate")
	end
	return { Top = color:Lerp(WHITE, 0.15), Bottom = color:Lerp(Color3.new(0, 0, 0), 0.35), Edge = PopTheme.Outline }
end

local function contextualStroke(label: Instance): UIStroke?
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return nil
end

-- A label (or a text button) in the Pop look: the chunky font, a bright ink, a black edge.
function BoostView.popText(label: GuiObject, heavy: boolean?, color: Color3?)
	local text: any = label
	text.FontFace = if heavy then PopTheme.Heavy else PopTheme.Font
	text.TextColor3 = color or BoostView.ink(text.TextColor3)
	text.TextStrokeTransparency = 1
	local edge = contextualStroke(label) or Pop.edge(label)
	edge.Color = PopTheme.Outline
	edge.Thickness = Pop.edgeFor(text.TextSize)
	edge.Transparency = 0
	edge.LineJoinMode = Enum.LineJoinMode.Round
end

-- Removes a frame's old look (UIKit strokes and gradients) before it is painted.
local function strip(frame: Instance)
	for _, child in frame:GetChildren() do
		if (child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end
BoostView.strip = strip

--[[
	A UIKit.panel as a Pop window (`paint`: the window's colour): the black
	frame, the header band behind `title` (its height: placeWindow) and the
	dark studded body under it. The title turns white with a 3D shadow.
]]
function BoostView.popWindow(panel: Frame, title: TextLabel, paint: string)
	panel.BackgroundColor3 = PopTheme.Outline
	panel.BackgroundTransparency = 0
	for _, child in panel:GetChildren() do
		if child:IsA("UIGradient") then
			child:Destroy()
		elseif child:IsA("UIStroke") then
			child.Color = PopTheme.Outline
			child.Thickness = 4
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
		end
	end
	local band = UIKit.new("Frame", {
		Name = "PopBand",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 70),
		ZIndex = 0,
	}, panel)
	Pop.face(band, paint, 4, false)
	local border = band:FindFirstChild("Border") :: UIStroke
	border.Thickness = 3
	local rim = band:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	Pop.studs(band, 4, 0.35, 40, 1)
	-- (the round look: no shine over the top half, the window's icon left of the title: placeWindow)
	local look = Pop.windowLook(Pop.windowKey(panel))
	if look then
		Pop.bandIcon(panel, look.Icon, 56, { ZIndex = 3 })
	else
		UIKit.new("Frame", {
			Name = "Shine",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 0.42),
			ZIndex = 2,
		}, band)
	end
	for i, s in { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.6, 0),
			ZIndex = 2,
		}, band)
	end
	local body = UIKit.new("Frame", {
		Name = "PopBody",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 74),
		Size = UDim2.new(1, -8, 1, -78),
		ZIndex = 0,
	}, panel)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	Pop.studs(body, 4, 0.5, 36, 1)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 2,
	}, body)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	BoostView.popText(title, false, WHITE)
	title.Text = Pop.caption(title.Text) -- (the round look: Title Case, the reel)
	title.ZIndex = 3
	Pop.shadow(title).ZIndex = 2
end

-- The header band `band` units tall (from 4 under the top edge), the body under it; the title's shadow follows it.
function BoostView.placeWindow(panel: Frame, band: number)
	local bandFrame = panel:FindFirstChild("PopBand") :: Frame?
	local body = panel:FindFirstChild("PopBody") :: Frame?
	if not bandFrame or not body then
		return
	end
	bandFrame.Size = UDim2.new(1, -8, 0, band)
	body.Position = UDim2.fromOffset(4, 4 + band)
	body.Size = UDim2.new(1, -8, 1, -(band + 8))
	-- the round look: the window's icon at the band's left; the title, the line under it and
	-- the receipt (just placed by the layout) move right of it
	local icon = panel:FindFirstChild("BandIcon") :: ImageLabel?
	if icon then
		local size = math.min(band - 14, 56)
		icon.Size = UDim2.fromOffset(size, size)
		icon.Position = UDim2.fromOffset(14, 4 + math.floor(band / 2))
		local room = Pop.iconRoom(icon) - 4
		for _, name in { "Title", "Subtitle", "Receipt" } do
			local label = panel:FindFirstChild(name)
			if room > 0 and label and label:IsA("GuiObject") then
				label.Position += UDim2.fromOffset(room, 0)
				label.Size -= UDim2.fromOffset(room, 0)
			end
		end
	end
	local title = panel:FindFirstChild("Title") :: TextLabel?
	local shadow = panel:FindFirstChild("TitleShadow") :: TextLabel?
	if title and shadow then
		shadow.AnchorPoint = title.AnchorPoint
		shadow.Position = title.Position + UDim2.fromOffset(0, 4)
		shadow.Size = title.Size
		shadow.Text = title.Text
		shadow.TextSize = title.TextSize
		shadow.Visible = title.Visible
		local edge = title:FindFirstChild("Edge") or contextualStroke(title)
		local shadowEdge = shadow:FindFirstChildOfClass("UIStroke")
		if edge and edge:IsA("UIStroke") and shadowEdge then
			edge.Thickness = Pop.edgeFor(title.TextSize)
			shadowEdge.Thickness = edge.Thickness
		end
	end
end

-- An offer strip's texts (popOffer): the duration, and the price (or, while Busy, the button's Text) on its price button.
function BoostView.syncOffer(button: TextButton)
	local label = button:FindFirstChild("Label") :: TextLabel?
	local price = button:FindFirstChild("Price") :: Frame?
	local row = if price then price:FindFirstChild("Row") else nil
	local priceLabel = if row then row:FindFirstChild("Label") :: TextLabel? else nil
	if not label or not price or not row or not priceLabel then
		return
	end
	local busy = button:GetAttribute("Busy") == true
	label.Text = tostring(button:GetAttribute("Label") or "")
	local text = if busy then button.Text else tostring(button:GetAttribute("PriceText") or "")
	priceLabel.Text = text
	local size = tonumber(button:GetAttribute("PriceSize")) or 20
	local kind = button:GetAttribute("Mark")
	local mark = row:FindFirstChild("Mark") :: GuiObject?
	local showMark = mark ~= nil and type(kind) == "string" and kind ~= "" and not busy
	local markSize = math.floor(size * 1.1 + 4)
	local room = price.Size.X.Offset - 14 - (if showMark then markSize + 5 else 0)
	local fit = size
	while fit > 10 and TechShopView.textWidth(text, fit) * 0.92 > room do
		fit -= 1
	end
	priceLabel.TextSize = fit
	local edge = priceLabel:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(fit)
	end
	priceLabel.Size = UDim2.fromOffset(math.max(10, math.min(math.ceil(TechShopView.textWidth(text, fit) * 0.92) + 4, room)), fit + 8)
	if mark then
		mark.Visible = showMark
		mark.Size = UDim2.fromOffset(markSize, markSize)
		local sign = mark:FindFirstChild("Mark") :: TextLabel?
		if sign then
			sign.TextSize = math.floor(markSize * 0.62)
		end
	end
end

-- Shows a button's Text in its row (the words, the mark beside them; no mark while it is Busy).
function BoostView.syncButton(button: TextButton)
	if holderOf(button):GetAttribute("PopOffer") then
		BoostView.syncOffer(button)
		return
	end
	local row = button:FindFirstChild("Row")
	local label = if row then row:FindFirstChild("Label") :: TextLabel? else nil
	if not row or not label then
		return
	end
	local text = button.Text
	local size = button.TextSize
	label.Text = text
	label.TextSize = size
	label.TextTransparency = 0
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(size)
	end
	local width, lines = 0, 0
	for _, line in string.split(text, "\n") do
		width = math.max(width, TechShopView.textWidth(line, size) * 0.92)
		lines += 1
	end
	local kind = button:GetAttribute("Mark")
	local mark = row:FindFirstChild("Mark") :: GuiObject?
	local showMark = mark ~= nil and type(kind) == "string" and kind ~= "" and button:GetAttribute("Busy") ~= true
	local markSize = math.floor(size * 1.1 + 4)
	if mark then
		mark.Visible = showMark
		mark.Size = UDim2.fromOffset(markSize, markSize)
		local sign = mark:FindFirstChild("Mark") :: TextLabel?
		if sign then
			sign.TextSize = math.floor(markSize * 0.62)
		end
	end
	local holder = holderOf(button)
	local room = if holder.Size.X.Scale == 0 and holder.Size.X.Offset > 0 then holder.Size.X.Offset - 8 else math.huge
	if showMark then
		room -= markSize + 5
	end
	label.Size = UDim2.fromOffset(math.max(10, math.min(math.ceil(width) + 4, room)), math.ceil(lines * size * 1.12) + 4)
end

-- A drawn crystal (the shards' mark).
function BoostView.crystal(parent: Instance, size: number, props: { [string]: any }?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Crystal",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	local gem = UIKit.new("Frame", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = 45,
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 6,
	}, holder)
	UIKit.corner(gem, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(200, 252, 255), rgb(40, 180, 240)), Rotation = 90 }, gem)
	Pop.border(gem, 2)
	if props then
		for key, value in props do
			(holder :: any)[key] = value
		end
	end
	return holder
end

-- The mark beside a button's words: "coin", "robux", "shard" or "" (none).
function BoostView.setMark(button: TextButton, kind: string?)
	local price = button:FindFirstChild("Price")
	local row = button:FindFirstChild("Row") or (if price then price:FindFirstChild("Row") else nil)
	if not row then
		return
	end
	local want = kind or ""
	local old = row:FindFirstChild("Mark")
	if old and old:GetAttribute("Kind") ~= want then
		old:Destroy()
		old = nil
	end
	if not old and want ~= "" then
		local textSize = if price then tonumber(button:GetAttribute("PriceSize")) or 20 else button.TextSize
		local size = math.floor(textSize * 1.1 + 4)
		local mark: GuiObject
		if want == "coin" then
			mark = Pop.coin(row, size, { Name = "Mark", LayoutOrder = 1, ZIndex = 3 })
		elseif want == "robux" then
			local image = UIKit.new("ImageLabel", {
				Name = "Mark",
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(size, size),
				ZIndex = 3,
			}, row)
			IconAssets.apply(image, "robux")
			image:SetAttribute("Icon", "robux")
			mark = image
		else
			mark = BoostView.crystal(row, size, { Name = "Mark", LayoutOrder = 1, ZIndex = 3 })
		end
		mark:SetAttribute("Kind", want)
	end
	button:SetAttribute("Mark", want)
	BoostView.syncButton(button)
end

--[[
	A UIKit.button (a holder "lip" with the TextButton face on it) as a
	painted Pop button: the holder is the face, the TextButton covers it
	(transparent) and a row shows its Text. Returns the holder.
]]
function BoostView.popButton(button: TextButton, paint: string | Pop.Paint, corner: number?, heavy: boolean?): Frame
	local holder = holderOf(button)
	local radius = corner or 8
	strip(holder)
	local holderCorner = holder:FindFirstChildOfClass("UICorner")
	if holderCorner then
		holderCorner.CornerRadius = UDim.new(0, radius)
	end
	Pop.face(holder, paint, radius)
	local rim = holder:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 1
	end
	Pop.studs(holder, radius, 0.5, 28, 1)
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	button.ZIndex = 2
	local row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 5, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Pop.text(row, button.Text, button.TextSize, {
		Name = "Label",
		LayoutOrder = 2,
		FontFace = if heavy then PopTheme.Heavy else PopTheme.Font,
		ZIndex = 3,
	})
	holder:SetAttribute("PopButton", true)
	pcall(function()
		local function sync()
			BoostView.syncButton(button)
		end
		button:GetPropertyChangedSignal("Text"):Connect(sync)
		button:GetPropertyChangedSignal("TextSize"):Connect(sync)
		button:GetAttributeChangedSignal("Busy"):Connect(sync)
	end)
	BoostView.syncButton(button)
	return holder
end

--[[
	An offer strip (the boost card's offers, popOffer): the holder a dark
	face, the TextButton over it (its Text stays: the tests fit it, the
	controller sets "..." and "BOUGHT!"), the duration on the left
	(attribute Label) and a price button (attribute PriceText, its mark:
	setMark) painted gold / green / grey (style, paintOffer); while Busy the
	price button shows the Text.
]]
function BoostView.popOffer(button: TextButton): Frame
	local holder = holderOf(button)
	strip(holder)
	local holderCorner = holder:FindFirstChildOfClass("UICorner")
	if holderCorner then
		holderCorner.CornerRadius = UDim.new(0, 10)
	end
	Pop.face(holder, BoostView.DarkPaint, 10)
	local rim = holder:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 1
	end
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	button.ZIndex = 2
	Pop.text(button, "", 22, {
		Name = "Label",
		FontFace = PopTheme.Heavy,
		ZIndex = 3,
	})
	local price = UIKit.new("Frame", { Name = "Price", BorderSizePixel = 0, ZIndex = 3 }, button)
	Pop.face(price, "Yellow", 8)
	Pop.studs(price, 8, 0.5, 28, 1)
	local priceRim = price:FindFirstChild("Rim") :: Frame?
	if priceRim then
		priceRim.ZIndex = 1
	end
	local row = UIKit.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, price)
	UIKit.list(row, Enum.FillDirection.Horizontal, 5, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Pop.text(row, "", 20, { Name = "Label", LayoutOrder = 2, ZIndex = 3 })
	holder:SetAttribute("PopButton", true)
	holder:SetAttribute("PopOffer", true)
	pcall(function()
		local function sync()
			BoostView.syncOffer(button)
		end
		button:GetPropertyChangedSignal("Text"):Connect(sync)
		button:GetAttributeChangedSignal("Busy"):Connect(sync)
	end)
	return holder
end

--[[
	Paints a button (the controllers pass UITheme colours: Accent = a gold
	coin button, Good = green, Info = blue, Bad = red); a disabled one
	turns grey. Old-look buttons (not popButton'd) keep their colours.
]]
local function style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	local holder = holderOf(button)
	local price = button:FindFirstChild("Price") :: Frame?
	if holder:GetAttribute("PopOffer") and price then
		Pop.repaint(price, if enabled then BoostView.paintFor(color) else PopTheme.Gray)
		BoostView.syncOffer(button)
		return
	end
	if holder:GetAttribute("PopButton") then
		Pop.repaint(holder, if enabled then BoostView.paintFor(color) else PopTheme.Gray)
		holder:SetAttribute("Enabled", enabled)
		BoostView.syncButton(button)
		return
	end
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holder.BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end
BoostView.style = style

-- Paints a Pop button directly (a Pop paint name or paint).
function BoostView.paintButton(button: TextButton, paint: string | Pop.Paint)
	Pop.repaint(holderOf(button), paint)
	BoostView.syncButton(button)
end

--[[
	A painted pill right behind `label` (a sibling named <label>Back, one
	ZIndex under it; no rim, like Pop.chip). placeBacking puts it on the
	label: its whole box, or `width` wide on the side the text sits.
]]
function BoostView.backing(label: GuiObject, paint: string | Pop.Paint): Frame
	local back = UIKit.new("Frame", {
		Name = label.Name .. "Back",
		BorderSizePixel = 0,
		ZIndex = math.max(1, label.ZIndex - 1),
	}, label.Parent)
	UIKit.corner(back, 999)
	Pop.face(back, paint, 999, true, false)
	local border = back:FindFirstChild("Border") :: UIStroke
	border.Thickness = 2.5
	label.ZIndex = back.ZIndex + 1
	return back
end

function BoostView.placeBacking(label: GuiObject, width: number?, paint: (string | Pop.Paint)?)
	local parent = label.Parent
	local back = if parent then parent:FindFirstChild(label.Name .. "Back") :: Frame? else nil
	if not back then
		return
	end
	back.Visible = label.Visible
	back.AnchorPoint = label.AnchorPoint
	back.Rotation = label.Rotation
	if width then
		local text: any = label
		local align = text.TextXAlignment
		local h = label.Size.Y.Offset
		local x = label.Position
		-- a left / right aligned label's text starts at its anchor side
		if align == Enum.TextXAlignment.Left and label.AnchorPoint.X == 0 then
			back.Position = x + UDim2.fromOffset(-8, 0)
		elseif align == Enum.TextXAlignment.Right and label.AnchorPoint.X == 1 then
			back.Position = x + UDim2.fromOffset(8, 0)
		else
			back.Position = x
		end
		back.Size = UDim2.fromOffset(width, h)
	else
		back.Position = label.Position
		back.Size = label.Size
	end
	if paint then
		Pop.repaint(back, paint)
	end
end

--[[
	Light rays and a soft glow behind a picture (as Pop.card's): `parent`
	should clip. Returns the holder (placeBurst moves and sizes it).
]]
function BoostView.burst(parent: Instance, count: number, z: number): Frame
	local holder = UIKit.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 200),
		ZIndex = z,
	}, parent)
	local rays = Pop.fx(holder, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2.2, 2.2),
		ZIndex = z,
	})
	if not rays then
		-- (bars twice the burst's size, like Pop.card's: they reach the corners)
		local made = Pop.rays(holder, UDim2.fromScale(0.5, 0.5), count, 100, 0.6, z)
		made.Size = UDim2.fromScale(2, 2)
		for _, ray in made:GetChildren() do
			if ray:IsA("Frame") then
				ray.Size = UDim2.new(1, 0, 0.08, 0)
			end
		end
	end
	local glow = Pop.fx(holder, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = rgb(255, 255, 240),
		ImageTransparency = 0.3,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		ZIndex = z,
	})
	if not glow then
		for i, k in { 0.32, 0.22 } do
			local disc = UIKit.new("Frame", {
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = if i == 1 then 0.8 else 0.7,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(k, k),
				ZIndex = z,
			}, holder)
			UIKit.corner(disc, 999)
		end
	end
	return holder
end

-- Centres a burst at `at` (its parent's units), `size` across (the rays reach the corners).
function BoostView.placeBurst(burst: GuiObject, at: UDim2, size: number)
	burst.Position = at
	burst.Size = UDim2.fromOffset(size, size)
end

-- A dark studded well (Pop.well's look) on an existing frame.
function BoostView.popWell(frame: Frame, transparency: number?)
	strip(frame)
	frame.BackgroundColor3 = PopTheme.Well
	frame.BackgroundTransparency = transparency or 0
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	else
		UIKit.corner(frame, PopTheme.WindowCorner)
	end
	Pop.border(frame, 3)
	Pop.studs(frame, PopTheme.WindowCorner, 0.6, 36, 0)
end

---------------------------------------------------------------- icons

local function bit(parent: Instance, x0: number, y0: number, x1: number, y1: number, color: Color3, round: number?, stroke: number?): Frame
	local frame = UIKit.new("Frame", {
		Name = "Bit",
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, frame)
	end
	if stroke then
		UIKit.stroke(frame, stroke)
	end
	return frame
end

--[[
	A boost icon on a dark tile (`size` design units): Triple Lucky a
	four-leaf clover, Hexa Lucky a cut gold gem; a badge with the
	multiplier in the corner. Unknown kinds: a plain tile.
]]
-- The boost cards' live 3D pictures (the Shop's luck cards): PictureModels name, preview icon.
BoostView.Pictures = {
	TripleLucky = { Model = "clover", Icon = "clover" },
	HexaLucky = { Model = "item_Diamond", Icon = "rainbow" },
} :: { [string]: { Model: string, Icon: string } }
-- the boost's paint (its card, its tab), the window's (the Boosts colour: BubbleTheme.Roles.Boosts)
BoostView.Paints = { TripleLucky = "Yellow", HexaLucky = "Blue" } :: { [string]: string }
BoostView.WindowPaint = "Green"

function BoostView.icon(parent: Instance, size: number, kindId: string): Frame
	local tile = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
	BoostView.setIcon(tile, kindId)
	return tile
end

--[[
	The boost's picture in a tile: the live 3D model (PictureModels, like
	the Shop's luck cards; a bit bigger than the tile, a sticker), else the
	drawn art; the multiplier on a chip in the corner.
]]
function BoostView.setIcon(tile: Frame, kindId: string)
	if tile:GetAttribute("Kind") == kindId then
		return
	end
	tile:SetAttribute("Kind", kindId)
	for _, name in { "Art", "Picture", "MultChip" } do
		local old = tile:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local art = BoostView.art(tile, kindId, false)
	art.ZIndex = 2
	local spec = BoostView.Pictures[kindId]
	local model, from = nil, Vector3.new(0, 0.1, -1)
	if spec then
		model, from = PictureModels.build(spec.Model)
	end
	if spec and model then
		Pop.model(tile, spec.Icon, 10, model, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.22, 1.22),
			ZIndex = 3,
		}, from)
		art.Visible = false
	end
	local kind = BoostConfig.Kinds[kindId]
	if kind then
		Pop.chip(tile, string.upper(BoostView.mult(kind.Mult)), "Pink", Vector2.new(58, 28), {
			Name = "MultChip",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 4, 1, 6),
			ZIndex = 5,
		})
	end
end

--[[
	A boost's picture (Triple Lucky a clover, Hexa Lucky a gold gem) in a
	frame "Art" filling 82 % of `parent`; `badge`: the multiplier badge in
	the corner (the HUD chips leave it out: too small to read there).
]]
function BoostView.art(parent: Instance, kindId: string, badge: boolean): Frame
	local art = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundTransparency = 1,
	}, parent)
	local kind = BoostConfig.Kinds[kindId]
	if kindId == "TripleLucky" then
		local leaf = rgb(90, 220, 120)
		local dark = rgb(40, 140, 70)
		bit(art, 0.47, 0.5, 0.55, 0.96, dark, 0.5, 1.5).Rotation = 18
		bit(art, 0.08, 0.08, 0.5, 0.5, leaf, 0.5, 2)
		bit(art, 0.5, 0.08, 0.92, 0.5, leaf, 0.5, 2)
		bit(art, 0.08, 0.42, 0.5, 0.84, leaf, 0.5, 2)
		bit(art, 0.5, 0.42, 0.92, 0.84, leaf, 0.5, 2)
		bit(art, 0.4, 0.36, 0.6, 0.56, rgb(200, 255, 200), 0.5)
	elseif kindId == "HexaLucky" then
		local gold = rgb(255, 196, 60)
		local outer = bit(art, 0.16, 0.16, 0.84, 0.84, gold, 0.12, 2.5)
		outer.Rotation = 45
		bit(art, 0.3, 0.3, 0.7, 0.7, rgb(255, 236, 150), 0.1).Rotation = 45
		bit(art, 0.42, 0.2, 0.5, 0.28, rgb(255, 252, 230), 0.5)
	else
		bit(art, 0.2, 0.2, 0.8, 0.8, Theme.PanelLight, 0.2)
	end
	if kind and badge then
		local tag = UIKit.new("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1.08, 1.08),
			Size = UDim2.fromScale(0.62, 0.36),
			BackgroundColor3 = kind.Color,
			BorderSizePixel = 0,
		}, art)
		UIKit.corner(tag, 8)
		UIKit.stroke(tag, 2)
		UIKit.label(tag, BoostView.mult(kind.Mult), 18, {
			Name = "Mult",
			Size = UDim2.fromScale(1, 1),
			TextScaled = true,
			TextWrapped = false,
			FontFace = Theme.TitleFont,
		})
	end
	return art
end

---------------------------------------------------------------- odds table (shared)

type TableMetrics = { Select: number, Head: number, Row: number, Text: number, Col: number, Note: number }

local TABLE_METRICS: { [string]: TableMetrics } = {
	Normal = { Select = 44, Head = 22, Row = 28, Text = 19, Col = 96, Note = 40 },
	Compact = { Select = 72, Head = 26, Row = 32, Text = 22, Col = 116, Note = 48 },
}

local function tableMetrics(compact: boolean): TableMetrics
	return if compact then TABLE_METRICS.Compact else TABLE_METRICS.Normal
end
BoostView.tableMetrics = tableMetrics

-- An odds row: a rounded pill painted in its rarity's colour (fillRow), the
-- name left and the two numbers right, white with black edges.
local function newRow(parent: Instance, name: string, order: number): RowRefs
	local frame = UIKit.new("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	UIKit.corner(frame, 8)
	UIKit.new("UIGradient", { Name = "Paint", Rotation = 90 }, frame)
	local label = Pop.text(frame, "", 17, {
		Name = "Name",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local before = Pop.text(frame, "", 17, {
		Name = "Before",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = rgb(232, 236, 246),
		ZIndex = 3,
	})
	local after = Pop.text(frame, "", 17, {
		Name = "After",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	})
	return { Frame = frame, Name = label, Before = before, After = after }
end

-- Paints an odds row: its rarity's colour (the summary row gold).
local function paintRow(row: RowRefs, color: Color3)
	local paint = if row.Frame.Name == "Summary" then Pop.paint("Yellow") else BoostView.paintOf(color)
	local gradient = row.Frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(paint.Top, paint.Bottom)
	end
end

-- The value columns' width in a table `width` wide: narrower in a narrow
-- table (the name keeps about half), and the size their texts fit at
-- ("0.0606%" is the longest: about 4.4 em).
local function columnOf(width: number, m: TableMetrics): (number, number)
	local col = math.min(m.Col, math.floor((width - 36) * 0.26))
	return col, math.min(m.Text, math.floor((col - 6) / 4.4))
end

local function placeRow(row: RowRefs, width: number, m: TableMetrics)
	row.Frame.Size = UDim2.new(1, 0, 0, m.Row)
	local col, valueText = columnOf(width, m)
	row.Name.Position = UDim2.fromOffset(8, 0)
	row.Name.Size = UDim2.new(1, -(16 + col * 2), 1, 0)
	row.Before.AnchorPoint = Vector2.new(1, 0)
	row.Before.Position = UDim2.new(1, -(8 + col), 0, 0)
	row.Before.Size = UDim2.new(0, col - 6, 1, 0)
	row.After.AnchorPoint = Vector2.new(1, 0)
	row.After.Position = UDim2.new(1, -8, 0, 0)
	row.After.Size = UDim2.new(0, col - 6, 1, 0)
	row.Name.TextSize = m.Text
	row.Name:SetAttribute("FullSize", m.Text)
	row.Before.TextSize = valueText
	row.After.TextSize = valueText
	-- a long name gets smaller instead of being cut
	row.Name:SetAttribute("FitWidth", width - (16 + col * 2))
	TechShopView.fitText(row.Name, width - (16 + col * 2), m.Row, m.Text, 12)
end

local function fillRow(row: RowRefs, data: OddsRow?)
	row.Frame.Visible = data ~= nil
	if not data then
		return
	end
	row.Name.Text = data.Name
	paintRow(row, data.Color)
	local fitWidth = tonumber(row.Name:GetAttribute("FitWidth"))
	if fitWidth then
		local size = tonumber(row.Name:GetAttribute("FullSize")) or row.Name.TextSize
		TechShopView.fitText(row.Name, fitWidth, row.Frame.Size.Y.Offset, size, 12)
	end
	row.Before.Text = data.Before
	row.After.Text = data.After
	-- (a boosted number in full white, the same or a lower one a little dimmer)
	row.After.TextColor3 = if data.Change > 0 then WHITE else rgb(214, 220, 232)
end

--[[
	An odds table in `parent`: a selector row ([<] title [>]; the arrows are
	hidden when there's nothing to switch, `selector` false: no arrows at
	all), column headers, a highlighted summary row, a scrolling list of
	rows and a note at the bottom.
]]
function BoostView.buildTable(parent: Instance, selector: boolean): TableRefs
	-- a dark studded well (Pop.well) with rarity-coloured rows: the odds in
	-- big white numbers, always in full view (paid random items: Roblox rule)
	local frame = UIKit.new("Frame", {
		Name = "Odds",
		BorderSizePixel = 0,
	}, parent)
	BoostView.popWell(frame)
	local prev = UIKit.button(frame, "<", Theme.PanelLight, Theme.Panel, { Name = "Prev", TextSize = 26 })
	local nextButton = UIKit.button(frame, ">", Theme.PanelLight, Theme.Panel, { Name = "Next", TextSize = 26 })
	BoostView.popButton(prev, "Blue", 8, true)
	BoostView.popButton(nextButton, "Blue", 8, true)
	local title = Pop.title(frame, "", 22, "Gold", {
		Name = "Title",
		FontFace = PopTheme.Heavy,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local head: { TextLabel } = {}
	for i, name in { "HeadName", "HeadBefore", "HeadAfter" } do
		table.insert(
			head,
			Pop.text(frame, "", 14, {
				Name = name,
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
				TextColor3 = rgb(214, 220, 232),
				ZIndex = 3,
			})
		)
	end
	local summary = newRow(frame, "Summary", 1)
	Pop.border(summary.Frame, 2.5)
	summary.Name.FontFace = PopTheme.Heavy
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = rgb(196, 200, 212),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 2,
	}, frame)
	UIKit.list(list, Enum.FillDirection.Vertical, 2)
	local note = Pop.text(frame, "", 15, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextColor3 = rgb(214, 220, 232),
		ZIndex = 3,
	})
	return {
		Frame = frame,
		Prev = prev,
		Next = nextButton,
		Title = title,
		Head = head,
		Summary = summary,
		List = list,
		Rows = {},
		Note = note,
		Compact = false,
		Width = 0,
		HasSelector = selector,
		ShowSummary = true,
		ShowNote = true,
		Data = nil,
		CanSwitch = selector,
		Height = 0,
		WithNote = true,
	}
end

-- The height a table needs to show `rows` rows without scrolling (layoutTable's sums);
-- `selector`: the arrows show; `withNote` false: no note under the rows.
function BoostView.tableHeight(rows: number, compact: boolean, selector: boolean, withNote: boolean?, summary: boolean?): number
	local m = tableMetrics(compact)
	local top = 8 + (if selector then m.Select + 8 else 34)
	local note = if withNote == false then 0 else m.Note
	local summaryRow = if summary == false then 0 else m.Row + 6
	return top + m.Head + summaryRow + math.max(1, rows) * (m.Row + 2) + note + 12
end

-- Sizes a table for a `width` x `height` box (design units). `withNote` false:
-- the note is never shown (the caller shows it elsewhere).
function BoostView.layoutTable(t: TableRefs, width: number, height: number, compact: boolean, withNote: boolean?)
	local m = tableMetrics(compact)
	t.Compact = compact
	t.Width = width
	t.Height = height
	t.WithNote = withNote ~= false
	t.Frame.Size = UDim2.fromOffset(width, height)
	local inner = width - 20
	local y = 8
	if t.HasSelector and t.CanSwitch then
		local prev, nextHolder = holderOf(t.Prev), holderOf(t.Next)
		prev.Size = UDim2.fromOffset(m.Select, m.Select)
		prev.Position = UDim2.fromOffset(10, y + 4)
		nextHolder.AnchorPoint = Vector2.new(1, 0)
		nextHolder.Size = UDim2.fromOffset(m.Select, m.Select)
		nextHolder.Position = UDim2.new(1, -10, 0, y + 4)
		t.Prev.TextSize = if compact then 32 else 28
		t.Next.TextSize = t.Prev.TextSize
		BoostView.syncButton(t.Prev)
		BoostView.syncButton(t.Next)
		t.Title.Position = UDim2.fromOffset(18 + m.Select, y)
		t.Title.Size = UDim2.new(1, -(36 + m.Select * 2), 0, m.Select)
		t.Title.TextSize = if compact then 26 else 22
		y += m.Select + 8
	else
		holderOf(t.Prev).Visible = false
		holderOf(t.Next).Visible = false
		t.Title.Position = UDim2.fromOffset(12, y)
		t.Title.Size = UDim2.new(1, -24, 0, 30)
		t.Title.TextSize = if compact then 24 else 20
		y += 34
	end
	t.Title.TextXAlignment = if t.HasSelector and t.CanSwitch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	-- column headers over the list (the list's rows sit 10 in from the frame)
	local col = columnOf(inner - SCROLLBAR, m)
	t.Head[1].Position = UDim2.fromOffset(18, y)
	t.Head[1].Size = UDim2.new(1, -(36 + col * 2), 0, m.Head)
	-- each header right-aligned over its column, a gap between them
	t.Head[2].AnchorPoint = Vector2.new(1, 0)
	t.Head[2].Position = UDim2.new(1, -(18 + SCROLLBAR + col), 0, y)
	t.Head[2].Size = UDim2.fromOffset(col - 8, m.Head)
	t.Head[3].AnchorPoint = Vector2.new(1, 0)
	t.Head[3].Position = UDim2.new(1, -(18 + SCROLLBAR), 0, y)
	t.Head[3].Size = UDim2.fromOffset(col - 8, m.Head)
	for _, label in t.Head do
		label.TextSize = if compact then 16 else 14
	end
	t.Frame:SetAttribute("Col", col)
	BoostView.fitHeads(t)
	y += m.Head
	-- a short table keeps rows in view: the note goes first (it needs room
	-- for the summary and three rows), the summary row stays while two rows
	-- fit under it (rows go rarest first: the ones luck raises are in view)
	local rows = 3 * (m.Row + 2)
	local note = m.Note
	t.ShowNote = withNote ~= false and height - y - m.Row - 6 - note - 12 >= rows
	t.Note.Visible = t.ShowNote
	if not t.ShowNote then
		note = 0
	end
	local data = t.Data
	-- (a table whose data has no summary row gives its room to the rows)
	t.ShowSummary = height - y - m.Row - 6 - note - 12 >= 2 * (m.Row + 2) and (data == nil or data.Summary ~= nil)
	t.Summary.Frame.Position = UDim2.fromOffset(10, y)
	placeRow(t.Summary, inner - SCROLLBAR, m)
	t.Summary.Frame.Size = UDim2.new(1, -(20 + SCROLLBAR), 0, m.Row)
	fillRow(t.Summary, if t.ShowSummary and data then data.Summary else nil)
	if t.ShowSummary then
		y += m.Row + 6
	end
	t.Note.TextSize = if compact then 17 else 15
	t.Note.Position = UDim2.fromOffset(12, height - m.Note - 6)
	t.Note.Size = UDim2.new(1, -24, 0, m.Note)
	t.List.Position = UDim2.fromOffset(10, y)
	-- whole rows only: no half-cut row at the bottom (the rest scrolls; the scroll bar shows it)
	local room = math.max(m.Row, height - y - note - 12)
	local whole = math.max(1, math.floor((room + 0.01) / (m.Row + 2))) * (m.Row + 2)
	t.List.Size = UDim2.new(1, -20, 0, math.min(room, whole))
	for _, row in t.Rows do
		placeRow(row, inner - SCROLLBAR, m)
	end
end

-- Fits the column headers to their columns (a narrow table: smaller headers).
function BoostView.fitHeads(t: TableRefs)
	local col = tonumber(t.Frame:GetAttribute("Col")) or 96
	local full = if t.Compact then 16 else 14
	TechShopView.fitText(t.Head[1], math.max(20, t.Width - 36 - col * 2), 24, full, 10)
	TechShopView.fitText(t.Head[2], col - 8, 24, full, 10)
	TechShopView.fitText(t.Head[3], col - 8, 24, full, 10)
end

-- Fills a table (rows are made as needed and hidden when not used).
function BoostView.setTable(t: TableRefs, data: OddsTable, canSwitch: boolean)
	local before = t.Data
	t.Data = data
	-- a summary row that comes or goes changes the layout
	if t.Width > 0 and (before == nil or (before.Summary == nil) ~= (data.Summary == nil)) then
		BoostView.layoutTable(t, t.Width, t.Height, t.Compact, t.WithNote)
	end
	t.Title.Text = data.Title
	t.Head[1].Text = data.Header
	t.Head[2].Text = data.BeforeHeader
	t.Head[3].Text = data.AfterHeader
	BoostView.fitHeads(t)
	if t.HasSelector then
		holderOf(t.Prev).Visible = canSwitch
		holderOf(t.Next).Visible = canSwitch
		if canSwitch ~= t.CanSwitch then
			-- the title row changes height: lay the table out again
			t.CanSwitch = canSwitch
			if t.Width > 0 then
				BoostView.layoutTable(t, t.Width, t.Height, t.Compact, t.WithNote)
			end
		end
	end
	fillRow(t.Summary, if t.ShowSummary then data.Summary else nil)
	local m = tableMetrics(t.Compact)
	for i, rowData in data.Rows do
		local existing: RowRefs? = t.Rows[i]
		local row: RowRefs
		if existing then
			row = existing
		else
			row = newRow(t.List, "Row" .. i, i)
			t.Rows[i] = row
			placeRow(row, t.Width - 20 - SCROLLBAR, m)
		end
		fillRow(row, rowData)
	end
	for i = #data.Rows + 1, #t.Rows do
		t.Rows[i].Frame.Visible = false
	end
	t.Note.Text = data.Note
	TechShopView.fitText(t.Note, math.max(1, t.Width - 24), m.Note, if t.Compact then 17 else 15, if t.Compact then 14 else 12)
end

---------------------------------------------------------------- the panel

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	TabBar: number,
	TabHeight: number,
	Footer: number,
	Left: number, -- the card column's width
	Icon: number,
	Offer: number, -- offer button height
	Name: number,
	Description: number,
	DescriptionLines: number,
	Key: number,
	Note: number,
	Close: number,
	TabGap: number,
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1000,
		Height = 600,
		Header = 82,
		TabBar = 62,
		TabHeight = 48,
		Footer = 30,
		Left = 404,
		Icon = 72,
		Offer = 54,
		Name = 28,
		Description = 16,
		DescriptionLines = 3,
		Key = 18,
		Note = 15,
		Close = 54,
		TabGap = 0,
	},
	-- phones and TVs: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1240,
		Height = 580,
		Header = 64,
		TabBar = 84,
		TabHeight = 72,
		Footer = 6,
		Left = 520,
		Icon = 72,
		Offer = 72,
		Name = 28,
		Description = 19,
		DescriptionLines = 3,
		Key = 20,
		Note = 17,
		Close = 72,
		TabGap = 72 + 20,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

-- The compact layout on touch screens, TVs and small screens (as TechShopView).
function BoostView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return TechShopView.compactFor(touch, tenFoot, scale, viewportHeight)
end

--[[
	A gamepad hint row: [glyph] word [glyph] word ... (the controller sets
	the glyph images). Returns the frame and its glyph images in order.
]]
function BoostView.padHint(parent: Instance, parts: { { Glyphs: number, Word: string, Width: number } }): (Frame, { ImageLabel })
	local frame = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(520, 24),
		BackgroundTransparency = 1,
		Visible = false,
	}, parent)
	frame:SetAttribute("BaseWidth", 520)
	UIKit.list(frame, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local glyphs: { ImageLabel } = {}
	local order = 0
	for _, part in parts do
		for _ = 1, part.Glyphs do
			order += 1
			table.insert(
				glyphs,
				UIKit.new("ImageLabel", {
					Name = "Glyph",
					LayoutOrder = order,
					Size = UDim2.fromOffset(24, 24),
					BackgroundTransparency = 1,
				}, frame)
			)
		end
		order += 1
		local word = UIKit.label(frame, part.Word, 15, {
			Name = "Word",
			LayoutOrder = order,
			Size = UDim2.fromOffset(part.Width, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
		})
		BoostView.popText(word)
		word:SetAttribute("BaseWidth", part.Width)
	end
	return frame, glyphs
end

-- Sizes a padHint row at `scale` (1 = 24-unit glyphs, 15-unit words; phones and TVs: PadHintScale).
function BoostView.scalePadHint(frame: Frame, scale: number)
	local base = tonumber(frame:GetAttribute("BaseWidth")) or 520
	frame.Size = UDim2.fromOffset(base * scale, 24 * scale)
	for _, child in frame:GetChildren() do
		if child:IsA("ImageLabel") then
			child.Size = UDim2.fromOffset(24 * scale, 24 * scale)
		elseif child:IsA("TextLabel") then
			local width = tonumber(child:GetAttribute("BaseWidth")) or 60
			child.Size = UDim2.fromOffset(width * scale, 24 * scale)
			child.TextSize = math.floor(15 * scale + 0.5)
		end
	end
end

-- The footer's height: the layout's own, or room for the bigger gamepad row (phones and TVs with a gamepad).
function BoostView.footerHeight(compact: boolean, padMode: boolean, footer: number): number
	return if compact and padMode then BoostView.PadFooter else footer
end

-- Shows the footer hint for the mode: the text (mouse / keyboard, not on phones and TVs) or the gamepad row.
function BoostView.showHint(hint: TextLabel, padHint: Frame, compact: boolean, padMode: boolean)
	hint.Visible = not compact and not padMode
	padHint.Visible = padMode
	BoostView.scalePadHint(padHint, if compact then BoostView.PadHintScale else 1)
end

-- The coins on a dark pill in a window's header band (a drawn gold coin + the green money, like the HUD's).
function BoostView.balance(parent: Instance): (Frame, TextLabel)
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	UIKit.corner(balance, 999)
	Pop.face(balance, BoostView.DarkPaint, 999, true, false)
	Pop.coin(balance, 30, {
		Name = "Coin",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		ZIndex = 3,
	})
	local amount = Pop.text(balance, "$0", 24, {
		Name = "Amount",
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextColor3 = PopTheme.MoneyNumber,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	return balance, amount
end

function BoostView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeBoosts", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look, never LightSkin's recolouring
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.Width, METRICS.Normal.Height),
		Active = true,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local title = UIKit.label(panel, "LUCK BOOSTS", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, "Better odds for a while. See exactly how the odds change (on the right) before you buy.", 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local receipt = UIKit.label(panel, "", 17, {
		Name = "Receipt",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Good,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, { Name = "Close", AnchorPoint = Vector2.new(1, 0), TextSize = 34 })
	local balance, balanceAmount = BoostView.balance(panel)
	-- the Pop window: the green header band (the Boosts colour), the dark body
	BoostView.popWindow(panel, title, BoostView.WindowPaint)
	BoostView.popText(subtitle, false, WHITE)
	BoostView.popText(receipt, false, WHITE)
	BoostView.popButton(close, PopTheme.Close, 6, true)

	-- the tabs: bright Pop tabs, the picked one in its boost's colour
	local tabBar = UIKit.new("Frame", { Name = "TabBar", BackgroundTransparency = 1, ZIndex = 2 }, panel)
	local specs: { Pop.TabSpec } = {}
	for _, kindId in BoostView.Tabs do
		table.insert(specs, { Id = kindId, Label = BoostView.TabTitles[kindId], Paint = BoostView.Paints[kindId] or "Blue" })
	end
	local tabs = Pop.tabs(tabBar, specs, BoostView.Tabs[1], Vector2.new(300, 48), { Name = "Tabs", ZIndex = 2 })
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
			}, tabBar)
		)
	end

	-- the boost card (left): painted in the boost's colour, rays behind its 3D picture
	local cardFrame = UIKit.new("Frame", {
		Name = "Card",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	}, panel)
	Pop.face(cardFrame, BoostView.Paints[BoostView.Tabs[1]] or "Yellow", 10, false)
	local cardRim = cardFrame:FindFirstChild("Rim") :: Frame?
	if cardRim then
		cardRim.ZIndex = 3
	end
	BoostView.burst(cardFrame, 10, 1)
	Pop.studs(cardFrame, 10, 0.5, 44, 2)
	for i, spot in { { 0.06, 0.06, 18 }, { 0.3, 0.05, 14 }, { 0.92, 0.1, 20 } } do
		Pop.sparkle(cardFrame, UDim2.fromScale(spot[1], spot[2]), spot[3], 2, 0.2 + i * 0.08)
	end
	local icon = BoostView.icon(cardFrame, 84, "TripleLucky")
	icon.ZIndex = 4
	local name = UIKit.label(cardFrame, "", 28, {
		Name = "BoostName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 5,
	})
	BoostView.popText(name, true, WHITE)
	local status = UIKit.label(cardFrame, "", 18, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 5,
	})
	BoostView.popText(status)
	BoostView.backing(status, BoostView.DarkPaint)
	local description = UIKit.label(cardFrame, "", 16, {
		Name = "Description",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ClipsDescendants = true,
		ZIndex = 5,
	})
	BoostView.popText(description, false, WHITE)
	local keyLine = UIKit.label(cardFrame, "", 18, {
		Name = "KeyLine",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	BoostView.popText(keyLine, false, WHITE)
	-- the offers: dark strips with the duration and a coin / Robux price button
	local offers: { TextButton } = {}
	for i = 1, 3 do
		local button = UIKit.button(cardFrame, "", Theme.Accent, Theme.AccentDark, { Name = "Offer" .. i, TextSize = 20 })
		holderOf(button).ZIndex = 5
		BoostView.popOffer(button)
		table.insert(offers, button)
	end
	local note = UIKit.label(cardFrame, "", 15, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
	})
	BoostView.popText(note, false, WHITE)

	local odds = BoostView.buildTable(panel, true)
	odds.Frame.ZIndex = 2
	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	BoostView.popText(hint)
	local padHint, padGlyphs = BoostView.padHint(panel, {
		{ Glyphs = 2, Word = "switch boost", Width = 110 },
		{ Glyphs = 1, Word = "buy / pick", Width = 90 },
		{ Glyphs = 1, Word = "close", Width = 52 },
		{ Glyphs = 1, Word = "scroll odds", Width = 96 },
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		Balance = balance,
		BalanceAmount = balanceAmount,
		Close = close,
		TabBar = tabBar,
		Tabs = tabs,
		TabGlyphs = glyphs,
		Card = {
			Frame = cardFrame,
			Icon = icon,
			Name = name,
			Status = status,
			Description = description,
			KeyLine = keyLine,
			Offers = offers,
			Note = note,
		},
		Odds = odds,
		Hint = hint,
		PadHint = padHint,
		PadGlyphs = padGlyphs,
		PadMode = false,
		Tab = BoostView.Tabs[1],
		Compact = compact == true,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
	}
	BoostView.setTab(refs, refs.Tab)
	BoostView.layout(refs, refs.Compact, math.huge, math.huge)
	return refs
end

--[[
	Sizes everything for the normal or compact layout and fits the panel
	into `maxWidth` x `maxHeight` design units (math.huge = no limit); like
	the Tech shop it moves below the HUD coins when there is room.
]]
function BoostView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local footer = BoostView.footerHeight(compact, refs.PadMode, m.Footer)
	local width = math.max(640, math.min(m.Width, maxWidth - 24))
	local height = math.max(BoostView.MinHeight, math.min(m.Height, maxHeight - 16))
	if maxWidth < 1e6 and maxHeight < 1e6 then
		local left = (maxWidth - width) / 2
		local top = (maxHeight - height) / 2
		if left < 16 + HudView.CoinsWidth and top < BoostView.CoinsBottom then
			local below = maxHeight - BoostView.CoinsBottom - 8
			if below >= (if compact then height else BoostView.MinHeight) then
				height = math.min(height, below)
				top = BoostView.CoinsBottom + (below - height) / 2
			end
		end
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0)
		refs.Panel.Position = UDim2.new(0.5, 0, 0, math.max(0, top))
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	refs.Panel.Size = UDim2.fromOffset(width, height)

	-- header
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, if compact then 6 else 14)
	local balanceWidth = if compact then 190 else 176
	refs.Balance.Size = UDim2.fromOffset(balanceWidth, 40)
	refs.Balance.Position = UDim2.new(1, -(PAD + m.Close + 12), 0, if compact then 14 else 16)
	local headRight = PAD + m.Close + 12 + balanceWidth + 12
	refs.Title.TextSize = if compact then 30 else 34
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 10 else 8)
	refs.Title.Size = UDim2.new(1, -(PAD + headRight), 0, 40)
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 50)
	refs.Subtitle.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 22)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	if compact then
		local titleWidth = 270
		refs.Title.Size = UDim2.fromOffset(titleWidth, 40)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth, 4)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + headRight), 0, 56)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
	else
		refs.Receipt.Position = UDim2.fromOffset(PAD, 50)
		refs.Receipt.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 24)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
	end
	refs.Close.TextSize = if compact then 46 else 36
	BoostView.syncButton(refs.Close)
	BoostView.placeWindow(refs.Panel, m.Header - 8)

	-- tabs: equal Pop tabs, room for the LB / RB glyphs at the ends
	refs.TabBar.Position = UDim2.fromOffset(PAD, m.Header)
	refs.TabBar.Size = UDim2.new(1, -(PAD * 2 + m.TabGap), 0, m.TabBar)
	local count = #BoostView.Tabs
	local inset = 26
	local barWidth = width - (PAD * 2 + m.TabGap)
	local each = math.floor((barWidth - 2 * inset - GAP * (count - 1)) / count)
	local row = refs.TabBar:FindFirstChild("Tabs") :: Frame?
	if row then
		row.Position = UDim2.fromOffset(inset, 6)
		row.Size = UDim2.new(1, -2 * inset, 0, m.TabHeight)
	end
	for _, kindId in BoostView.Tabs do
		local tab = refs.Tabs[kindId]
		tab.Size = UDim2.fromOffset(each, m.TabHeight)
		local label = tab:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Size = UDim2.new(1, -12, 1, 0)
			label.Position = UDim2.fromOffset(6, 0)
			TechShopView.fitText(label, each - 16, m.TabHeight - 8, if compact then 28 else 26, 14)
			local edge = label:FindFirstChild("Edge") :: UIStroke?
			if edge then
				edge.Thickness = Pop.edgeFor(label.TextSize)
			end
		end
	end
	refs.TabGlyphs[1].Position = UDim2.new(0, 12, 0, 6 + m.TabHeight / 2 - 3)
	refs.TabGlyphs[2].Position = UDim2.new(1, -12, 0, 6 + m.TabHeight / 2 - 3)

	-- body: the card (left) and the odds (right)
	local top = m.Header + m.TabBar
	local bodyHeight = height - top - footer - 8
	local left = math.min(m.Left, math.floor((width - PAD * 2 - 12) * 0.45))
	local card = refs.Card
	card.Frame.Position = UDim2.fromOffset(PAD, top)
	card.Frame.Size = UDim2.fromOffset(left, bodyHeight)
	card.Icon.Size = UDim2.fromOffset(m.Icon, m.Icon)
	card.Icon.Position = UDim2.fromOffset(12, 10)
	local textLeft = 12 + m.Icon + 14
	card.Name.TextSize = m.Name
	card.Name.Position = UDim2.fromOffset(textLeft, 10)
	card.Name.Size = UDim2.new(1, -(textLeft + 10), 0, 34)
	card.Status.TextSize = if compact then 20 else 18
	card.Status.Position = UDim2.fromOffset(textLeft, 46)
	card.Status.Size = UDim2.new(1, -(textLeft + 10), 0, 26)
	local y = 10 + m.Icon + 8
	local descHeight = math.ceil(m.Description * TechShopView.LineHeight * m.DescriptionLines) + 4
	local offersHeight = if compact then m.Offer + GAP + 4 else 3 * (m.Offer + GAP)
	local need = y + descHeight + 4 + m.Key + 8 + 12 + offersHeight + 24
	-- a short card (a small phone): the tab above already shows the name, so
	-- the status and the two-line short description (Card.Short) sit next to
	-- the icon, and the key line and the offers keep their room
	local short = need > bodyHeight
	card.Frame:SetAttribute("Short", short)
	card.Name.Visible = not short
	card.Description.Visible = true
	card.Description.TextSize = m.Description
	if short then
		card.Status.Position = UDim2.fromOffset(textLeft, 6)
		descHeight = 10 + m.Icon - 34
		card.Description.Position = UDim2.fromOffset(textLeft, 34)
		card.Description.Size = UDim2.new(1, -(textLeft + 10), 0, descHeight)
		card.Frame:SetAttribute("DescriptionWidth", left - textLeft - 10)
	else
		card.Description.Position = UDim2.fromOffset(12, y)
		card.Description.Size = UDim2.new(1, -24, 0, descHeight)
		card.Frame:SetAttribute("DescriptionWidth", left - 24)
		y += descHeight + 4
	end
	card.KeyLine.TextSize = m.Key
	card.KeyLine.Position = UDim2.fromOffset(12, y)
	card.KeyLine.Size = UDim2.new(1, -24, 0, m.Key + 8)
	y += m.Key + 8 + 12
	-- the light burst behind the picture, the status on its dark pill
	local burst = card.Frame:FindFirstChild("Burst") :: Frame?
	if burst then
		BoostView.placeBurst(burst, UDim2.fromOffset(12 + m.Icon / 2, 10 + m.Icon / 2), math.max(left, 260))
	end
	BoostView.placeStatus(refs)
	card.Frame:SetAttribute("OffersTop", y)
	card.Frame:SetAttribute("Width", left)
	card.Frame:SetAttribute("DescriptionHeight", descHeight)
	card.Frame:SetAttribute("BodyHeight", bodyHeight)
	local shown = 0
	for _, button in card.Offers do
		if holderOf(button).Visible then
			shown += 1
		end
	end
	BoostView.placeOffers(refs, shown)

	local oddsWidth = width - PAD * 2 - left - 12
	refs.Odds.Frame.Position = UDim2.fromOffset(PAD + left + 12, top)
	BoostView.layoutTable(refs.Odds, oddsWidth, bodyHeight, compact)

	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, -4)
	BoostView.showHint(refs.Hint, refs.PadHint, compact, refs.PadMode)
end

--[[
	An offer strip's insides for a `w` x `h` strip: the duration left and the
	price button right (a column of wide strips), or the duration on top and
	the price button under it (compact: three strips side by side).
]]
function BoostView.placeOffer(button: TextButton, w: number, h: number, compact: boolean)
	local label = button:FindFirstChild("Label") :: TextLabel?
	local price = button:FindFirstChild("Price") :: Frame?
	if not label or not price then
		return
	end
	if compact then
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 4)
		label.Size = UDim2.new(1, -8, 0, 26)
		label.TextXAlignment = Enum.TextXAlignment.Center
		TechShopView.fitText(label, w - 12, 26, 22, 14)
		price.AnchorPoint = Vector2.new(0.5, 1)
		price.Position = UDim2.new(0.5, 0, 1, -6)
		price.Size = UDim2.fromOffset(math.floor(w - 12), h - 38)
		button:SetAttribute("PriceSize", 20)
	else
		local priceWidth = math.floor(math.min(230, w * 0.56))
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 14, 0.5, 0)
		label.Size = UDim2.new(0, w - priceWidth - 30, 1, -6)
		label.TextXAlignment = Enum.TextXAlignment.Left
		TechShopView.fitText(label, w - priceWidth - 30, h - 8, 26, 14)
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -7, 0.5, 0)
		price.Size = UDim2.fromOffset(priceWidth, h - 12)
		button:SetAttribute("PriceSize", 22)
	end
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(label.TextSize)
	end
	local mark = button:GetAttribute("Mark")
	BoostView.setMark(button, "")
	BoostView.setMark(button, if type(mark) == "string" then mark else "")
end

--[[
	Places the `n` shown offer buttons of the card and the note under them:
	a column of wide buttons (normal), or one row with the price on a
	second line (compact: three 72-unit buttons side by side, so a phone
	keeps room for the description and the note).
]]
function BoostView.placeOffers(refs: Refs, n: number)
	local card = refs.Card
	local m = metrics(refs.Compact)
	local width = tonumber(card.Frame:GetAttribute("Width")) or m.Left
	local bodyHeight = tonumber(card.Frame:GetAttribute("BodyHeight")) or 400
	local y = tonumber(card.Frame:GetAttribute("OffersTop")) or 200
	local count = math.max(1, n)
	if refs.Compact then
		local each = (width - 24 - GAP * (count - 1)) / count
		local i = 0
		for _, button in card.Offers do
			local holder = holderOf(button)
			holder.Size = UDim2.fromOffset(each, m.Offer)
			holder.Position = UDim2.fromOffset(12 + i * (each + GAP), y)
			button.TextSize = 20
			BoostView.placeOffer(button, each, m.Offer, true)
			if holder.Visible then
				i += 1
			end
		end
		y += m.Offer + GAP + 4
	else
		for _, button in card.Offers do
			local holder = holderOf(button)
			holder.Position = UDim2.fromOffset(12, y)
			holder.Size = UDim2.fromOffset(width - 24, m.Offer)
			button.TextSize = 20
			BoostView.placeOffer(button, width - 24, m.Offer, false)
			if holder.Visible then
				y += m.Offer + GAP
			end
		end
	end
	local noteHeight = math.max(20, bodyHeight - y - 6)
	card.Note.TextSize = m.Note
	card.Note.Position = UDim2.fromOffset(12, y)
	card.Note.Size = UDim2.new(1, -24, 0, noteHeight)
	card.Frame:SetAttribute("NoteHeight", noteHeight)
end

--[[
	Scrolls a ScrollingFrame by `delta` design units (the controllers move
	lists with the gamepad's right stick: rows aren't selectable, so the
	selection alone would never reach the last ones). Clamped to its canvas.
]]
function BoostView.scrollBy(frame: ScrollingFrame, delta: number)
	-- CanvasPosition is in design units; the Absolute sizes are on-screen pixels (x the UI scale)
	local scale = 1
	local gui = frame:FindFirstAncestorOfClass("ScreenGui")
	local uiScale = if gui then gui:FindFirstChild("Scale") else nil
	if uiScale and uiScale:IsA("UIScale") and uiScale.Scale > 0 then
		scale = uiScale.Scale
	end
	local maxY = math.max(0, (frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y) / scale)
	local y = math.clamp(frame.CanvasPosition.Y + delta, 0, maxY)
	frame.CanvasPosition = Vector2.new(frame.CanvasPosition.X, y)
end

-- Shrinks a button's text a little when it would not fit its face (two lines on compact offers).
function BoostView.fitButton(button: TextButton, compact: boolean)
	local holder = holderOf(button)
	local size = holder.Size
	if size.X.Scale ~= 0 or size.X.Offset <= 0 then
		return -- a width from the parent: measured where it is placed
	end
	button.TextWrapped = string.find(button.Text, "\n", 1, true) ~= nil
	TechShopView.fitText(button :: any, size.X.Offset - 10, size.Y.Offset - 6, if compact then 22 else 20, 12)
end

---------------------------------------------------------------- filling in

-- Shows one boost's tab (Pop.selectTab: its tab painted in the boost's colour, the other grey).
function BoostView.setTab(refs: Refs, kindId: string)
	refs.Tab = kindId
	Pop.selectTab(refs.Tabs, kindId)
end

-- The tab after (dir = 1) or before (dir = -1) `kindId`, wrapping.
function BoostView.nextTab(kindId: string, dir: number): string
	return BoostView.cycle(BoostView.Tabs, kindId, if dir < 0 then -1 else 1) or BoostView.Tabs[1]
end

-- The status ("ACTIVE: 4:59 left") on its dark pill, as wide as its words.
function BoostView.placeStatus(refs: Refs)
	local status = refs.Card.Status
	local card = refs.Card.Frame
	local room = (tonumber(card:GetAttribute("Width")) or card.Size.X.Offset) - status.Position.X.Offset - 4
	local width = math.ceil(TechShopView.textWidth(status.Text, status.TextSize) * 0.92) + 24
	BoostView.placeBacking(status, math.min(width, room))
	local back = status.Parent and status.Parent:FindFirstChild(status.Name .. "Back") :: Frame?
	if back then
		back.Visible = status.Text ~= ""
		back.Size = UDim2.fromOffset(back.Size.X.Offset, status.TextSize + 12)
		back.Position = status.Position + UDim2.fromOffset(-10, math.floor((status.Size.Y.Offset - status.TextSize - 12) / 2))
	end
end

-- An offer's price as its button shows it: the coins, the Robux number (the mark beside it), or COMING SOON.
function BoostView.priceWords(offer: Offer): (string, string)
	if offer.Robux then
		local number = string.match(offer.PriceText, "^(%d+) R%$$")
		if number then
			return number, "robux"
		end
		return offer.PriceText, ""
	end
	if offer.Reason == "ComingSoon" then
		return offer.PriceText, ""
	end
	return offer.PriceText, "coin"
end

-- Fills an offer strip: the duration, the price button (gold coins, green Robux, grey when it can't be bought).
function BoostView.paintOffer(button: TextButton, offer: Offer)
	local words, mark = BoostView.priceWords(offer)
	button:SetAttribute("Label", offer.Label)
	button:SetAttribute("PriceText", words)
	local price = button:FindFirstChild("Price") :: Frame?
	if price then
		local paint = if not offer.CanBuy then PopTheme.Gray elseif offer.Robux then PopTheme.Price else Pop.paint("Yellow")
		Pop.repaint(price, paint)
	end
	BoostView.setMark(button, mark)
end

-- Fills the card from BoostView.cards. Buttons that show an answer (Busy) keep their text.
function BoostView.setCard(refs: Refs, card: Card)
	local c = refs.Card
	BoostView.setIcon(c.Icon, card.Kind)
	Pop.repaint(c.Frame, BoostView.Paints[card.Kind] or "Yellow", false)
	c.Name.Text = string.upper(card.Name)
	c.Status.Text = card.Status
	c.Status.TextColor3 = BoostView.ink(card.StatusColor)
	BoostView.placeStatus(refs)
	local short = c.Frame:GetAttribute("Short") == true
	c.Description.Text = if short then card.Short else card.Description
	c.KeyLine.Text = card.KeyLine
	local width = tonumber(c.Frame:GetAttribute("Width")) or 400
	local descHeight = tonumber(c.Frame:GetAttribute("DescriptionHeight")) or 60
	local descWidth = tonumber(c.Frame:GetAttribute("DescriptionWidth")) or (width - 24)
	local m = metrics(refs.Compact)
	TechShopView.fitText(c.Description, descWidth, descHeight, m.Description, m.Description - (if short then 4 else 3))
	TechShopView.fitText(c.KeyLine, width - 24, m.Key + 8, m.Key, m.Key - 4)
	for i, button in c.Offers do
		local offer = card.Offers[i]
		holderOf(button).Visible = offer ~= nil
		if offer then
			button:SetAttribute("Label", offer.Label)
			if button:GetAttribute("Busy") ~= true then
				button.Text = if refs.Compact then `{offer.Label}\n{offer.PriceText}` else offer.Text
				BoostView.paintOffer(button, offer)
			end
		end
	end
	BoostView.placeOffers(refs, math.min(#card.Offers, #c.Offers))
	for _, button in c.Offers do
		BoostView.fitButton(button, refs.Compact)
		BoostView.syncOffer(button)
	end
	c.Note.Text = card.Note
	local noteHeight = tonumber(c.Frame:GetAttribute("NoteHeight")) or 40
	TechShopView.fitText(c.Note, width - 24, noteHeight, m.Note, m.Note - 3)
end

-- The card's note line shows a status (an answer) for a moment, on a dark pill; nil puts the note back.
function BoostView.setStatus(refs: Refs, text: string?, color: Color3?, note: string)
	local c = refs.Card
	c.Note.Text = text or note
	c.Note.TextColor3 = if text then BoostView.ink(color or Theme.Text) else WHITE
	c.Note.BackgroundColor3 = PopTheme.Outline
	c.Note.BackgroundTransparency = if text then 0.35 else 1
	if not c.Note:FindFirstChildOfClass("UICorner") then
		UIKit.corner(c.Note, 8)
	end
end

function BoostView.setCoins(refs: Refs, coins: number)
	refs.BalanceAmount.Text = Format.money(math.max(0, num(coins, 0)))
end

-- The footer hint: `text`, or with `glyphs` (LB, RB, A, B, right stick images)
-- the gamepad row (also on phones and TVs: it gets a footer of its own there,
-- so the panel is laid out again when the row comes or goes).
function BoostView.setHint(refs: Refs, text: string, glyphs: { string }?)
	local was = refs.PadMode
	refs.Hint.Text = text
	refs.PadMode = glyphs ~= nil
	if glyphs then
		for i, image in refs.PadGlyphs do
			image.Image = glyphs[i] or ""
		end
	end
	if refs.Compact and was ~= refs.PadMode then
		BoostView.layout(refs, true, refs.MaxWidth, refs.MaxHeight)
	end
	BoostView.showHint(refs.Hint, refs.PadHint, refs.Compact, refs.PadMode)
end

-- The last message in the header band (white: readable on every window's colour).
function BoostView.showReceipt(refs: Refs, text: string, _color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = WHITE
	refs.Receipt.Visible = true
	refs.Subtitle.Visible = false
end

function BoostView.hideReceipt(refs: Refs)
	refs.Receipt.Visible = false
	refs.Subtitle.Visible = not refs.Compact
end

-- The button a gamepad starts on: the open tab, never an offer (A is also
-- jump: a reflex press right after opening must not spend anything).
function BoostView.firstButton(refs: Refs): GuiObject
	return refs.Tabs[refs.Tab]
end

-- Every button a finger must hit (for the touch-size tests).
function BoostView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close), holderOf(refs.Odds.Prev), holderOf(refs.Odds.Next) }
	for _, kindId in BoostView.Tabs do
		table.insert(list, refs.Tabs[kindId]) -- (a Pop tab is its own button)
	end
	for _, button in refs.Card.Offers do
		table.insert(list, holderOf(button))
	end
	return list
end

---------------------------------------------------------------- HUD chips

-- the chip's parts (design units): the icon square and the text ("TRIPLE 3:42")
local CHIP_DOT = 32
local CHIP_TEXT = 20
local CHIP_PIXEL = 17 -- the pixel chips' words (Pop.text size: 12.6-unit letters, like the tiles' words)
local CHIP_PIXEL_SMALL = 14 -- (a phone row that still doesn't fit without the tags: 10.4-unit letters)

--[[
	Builds a chip's pill (once) at the top of its touch area (which grows
	down only): a square with the boost's picture (`kindId`, ringed in the
	boost's colour; the launcher: a "+" on `color`) and one text, the tag
	and the timer ("TRIPLE 3:42"). Shape, word and colour each tell the
	boosts apart.
]]
local function chipPill(button: TextButton, color: Color3, kindId: string?)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromOffset(120, BoostView.ChipHeight),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, button)
	UIKit.corner(pill, BoostView.ChipHeight // 2)
	UIKit.stroke(pill, 2.5)
	local dot = UIKit.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(CHIP_DOT, CHIP_DOT),
		BackgroundColor3 = if kindId then Theme.PanelDark else color,
		BorderSizePixel = 0,
	}, pill)
	UIKit.corner(dot, 12)
	UIKit.stroke(dot, 2, if kindId then color else nil)
	if kindId then
		BoostView.art(dot, kindId, false)
	else
		UIKit.label(dot, "+", 18, {
			Name = "Mult",
			Size = UDim2.fromScale(1, 1),
			FontFace = Theme.TitleFont,
			TextWrapped = false,
		})
	end
	UIKit.label(pill, "", CHIP_TEXT, {
		Name = "Text",
		Position = UDim2.fromOffset(4 + CHIP_DOT + 8, 0),
		Size = UDim2.fromOffset(0, BoostView.ChipHeight),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
end

-- Fills a chip: "TRIPLE 3:42" (`tag` "" = the timer / word alone); the
-- pill is as wide as its text (TechShopView.textWidth, a generous guess).
-- `small` (the pixel chips only): smaller letters (CHIP_PIXEL_SMALL).
function BoostView.setChipText(button: TextButton, tag: string, text: string, small: boolean?)
	local pill = button:FindFirstChild("Pill") :: Frame?
	if not pill then
		return
	end
	local label = pill:FindFirstChild("Text") :: TextLabel
	if button:GetAttribute("Corner") == true then
		label.Text = text -- (the corner tile: the picture says which boost, the time alone under it)
		return
	end
	local x = 4 + CHIP_DOT + 8
	label.Text = if tag == "" then text else `{tag} {text}`
	local pixel = pill:GetAttribute("Pixel") == true
	local letters = if small then CHIP_PIXEL_SMALL else CHIP_PIXEL
	if pixel and label:GetAttribute("WordSize") ~= letters then
		Pop.fit(label, letters)
	end
	local width = if pixel
		then math.ceil(Pop.textWidth(label.Text, letters))
		else math.ceil(TechShopView.textWidth(label.Text, CHIP_TEXT)) + 2
	-- (the pixel pill: the word centred on the face above its lip)
	label.Position = UDim2.fromOffset(x, if pixel then -2 else 0)
	label.Size = UDim2.fromOffset(width, BoostView.ChipHeight)
	pill.Size = UDim2.fromOffset(x + width + 10, BoostView.ChipHeight)
	button.Size = UDim2.fromOffset(x + width + 10, BoostView.ChipHit)
end

--[[
	The top of the chips' row (design units): under the train chip
	(`trainChip`: its frame, else where TrainView puts it on this layout),
	and never above the coins' "+$X" popups.
]]
function BoostView.chipsTop(trainChip: GuiObject?, compact: boolean): number
	if TrainView.HudChipTop and trainChip then
		return trainChip.Position.Y.Offset -- the light HUD: the chips beside the train chip
	end
	local bottom: number
	if trainChip then
		bottom = trainChip.Position.Y.Offset + trainChip.Size.Y.Offset * (1 - trainChip.AnchorPoint.Y)
	else
		bottom = TrainView.ChipTop + (if compact then BoostView.TrainChipHeight.Compact else BoostView.TrainChipHeight.Normal)
	end
	return math.max(bottom, BoostView.FloatersBottom) + BoostView.ChipGap
end

-- The widest the chips' row gets (design units): every boost chip with the
-- longest timer text, the gaps and the gamepad glyph (SideMenuView keeps
-- its column clear of it; SideMenu.spec checks the rects).
function BoostView.chipsWidth(): number
	local pixel = UIConfig.lightUI()
	local function pill(text: string): number
		if pixel then
			return 4 + CHIP_DOT + 8 + math.ceil(Pop.textWidth(text, CHIP_PIXEL)) + 10
		end
		return 4 + CHIP_DOT + 8 + math.ceil(TechShopView.textWidth(text, CHIP_TEXT)) + 2 + 10
	end
	local width = 0
	for _, kindId in BoostConfig.KindIds do
		width += pill(`{BoostView.ChipTags[kindId] or ""} 23h 59m`) + 8
	end
	return math.max(width, pill("BOOSTS") + 8) + 30
end

-- Whether the chips' row shows: with the HUD, not while a panel is open (a
-- wide panel would cut them off; the Boosts panel shows the same timers), nor
-- while the touch side menu's grid is open over the left column
-- (MenuPanels.gridOpen: it would cover them half-way).
function BoostView.chipsVisible(hudShown: boolean, panelOpen: boolean, gridOpen: boolean?): boolean
	return hudShown and not panelOpen and gridOpen ~= true
end

-- Where the chips' row starts (design units): ChipLeft, or right of the train
-- chip on the light HUD (the left column holds the menu tiles there).
function BoostView.chipsLeft(trainChip: GuiObject?): number
	if TrainView.HudChipTop and trainChip then
		return trainChip.Position.X.Offset + trainChip.Size.X.Offset + BoostView.ChipGap
	end
	return BoostView.ChipLeft
end

-- Moves the chips' row to `top` (BoostView.chipsTop), at `left` (BoostView.chipsLeft).
-- (the light build's corner row stays in its corner: BoostView.placeCorner)
function BoostView.placeChips(refs: ChipRefs, top: number, left: number?)
	if refs.Row:GetAttribute("Corner") == true then
		return
	end
	refs.Row.Position = UDim2.fromOffset(left or BoostView.ChipLeft, top)
end

--[[
	The chips' own ScreenGui (attribute TerraForge: HudController scales
	it with the HUD): a row in the left column under the train chip
	(placeChips). Each chip is a TextButton 72 units tall (the touch area)
	with the 40-unit pill at its top: the touch area grows down only.
]]
function BoostView.buildChips(): ChipRefs
	local gui = UIKit.screen("TerraForgeBoostChips", 6)
	gui:SetAttribute("TerraForge", true)
	local row = UIKit.new("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(BoostView.ChipLeft, BoostView.chipsTop(nil, false)),
		Size = UDim2.fromOffset(HudView.CoinsWidth + 200, BoostView.ChipHit),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Top })
	local function chipButton(name: string, order: number): TextButton
		return UIKit.new("TextButton", {
			Name = name,
			LayoutOrder = order,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(120, BoostView.ChipHit),
		}, row)
	end
	local chips: { [string]: TextButton } = {}
	for i, kindId in BoostConfig.KindIds do
		local button = chipButton("Chip" .. kindId, i)
		chipPill(button, BoostConfig.Kinds[kindId].Color, kindId)
		BoostView.setChipText(button, BoostView.ChipTags[kindId] or "", "0:00")
		button.Visible = false
		chips[kindId] = button
	end
	local launcher = chipButton("Launcher", 0)
	chipPill(launcher, rgb(90, 220, 120), nil)
	BoostView.setChipText(launcher, "", "BOOSTS")
	-- the gamepad key's glyph, centred on the pills
	local glyphHolder = UIKit.new("Frame", {
		Name = "GlyphHolder",
		LayoutOrder = 99,
		Size = UDim2.fromOffset(30, BoostView.ChipHeight),
		BackgroundTransparency = 1,
	}, row)
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Visible = false,
	}, glyphHolder)
	return { Gui = gui, Row = row, Chips = chips, Launcher = launcher, Glyph = glyph }
end

--[[
	The farthest right the chips' row may reach (design units in the chips'
	gui), nil = no limit. HudController sets it from the light HUD
	(HudBubble.chipsRight): on phones the green Shop pill rides on the right
	end of this row, and a chip over it would open Boosts instead of the Shop.
]]
BoostView.HudChipsRight = nil :: number?

-- The right edge of the chips' row's visible chips (design units): the row's
-- left plus every shown chip and the gaps between (the gamepad glyph, shown
-- with a gamepad only, is not a touch target and isn't counted).
function BoostView.rowRight(refs: ChipRefs): number
	local list = refs.Row:FindFirstChildOfClass("UIListLayout")
	local gap = if list then list.Padding.Offset else 8
	local right = refs.Row.Position.X.Offset
	local count = 0
	for _, child in refs.Row:GetChildren() do
		if child:IsA("TextButton") and child.Visible then
			right += child.Size.X.Offset
			count += 1
		end
	end
	return right + math.max(0, count - 1) * gap
end

-- Shows the running boosts' chips (BoostView.chips); the launcher when
-- none runs and `launcher` is on. A row that would pass HudChipsRight (a
-- phone's Shop pill) drops the tags (the picture and the colour still tell
-- the boosts apart), then takes smaller letters; the row's attribute "Fit"
-- says which ("Tags", "Short", "Small").
function BoostView.setChips(refs: ChipRefs, chips: { Chip }, launcher: boolean)
	local shown: { [string]: boolean } = {}
	local function fill(short: boolean, small: boolean)
		for _, chip in chips do
			local button = refs.Chips[chip.Kind]
			if button then
				shown[chip.Kind] = true
				BoostView.setChipText(button, if short then "" else chip.Tag, chip.Text, small)
				button.Visible = true
			end
		end
	end
	fill(false, false)
	for kindId, button in refs.Chips do
		if not shown[kindId] then
			button.Visible = false
		end
	end
	local corner = refs.Row:GetAttribute("Corner") == true
	-- (the corner shows running boosts only: the side menu's BOOSTS tile opens the view)
	refs.Launcher.Visible = launcher and #chips == 0 and not corner
	local fit = "Tags"
	local limit = if corner then nil else BoostView.HudChipsRight
	if limit and #chips > 0 and BoostView.rowRight(refs) > limit then
		fit = "Short"
		fill(true, false)
		if BoostView.rowRight(refs) > limit then
			fit = "Small"
			fill(true, true)
		end
	end
	refs.Row:SetAttribute("Fit", fit)
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- The window wears the Pop look switch on or off (never LightSkin's
-- recolouring); with the light UI on it also hides Roblox's touch controls
-- while open. The HUD chips wear the pixel reels' look (below).
local popBuild = BoostView.build
BoostView.build = function(compact: boolean?): Refs
	local refs = popBuild(compact)
	if UIConfig.lightUI() then
		TouchControls.follow(refs.Gui)
	end
	return refs
end

--[[
	The HUD chips in the pixel reels' look (owner 2026-10-22): each pill a
	small reel button (a painted face with the thick black outline, the lip,
	the lattice), the boost's picture in a painted square at its left end,
	the tag and the timer in white pixel letters with a black edge. The same
	instances and names as the dark build (Pill, Dot, Art, Text, Mult): the
	controller and the specs drive both.
]]
BoostView.ChipPaints = {
	TripleLucky = { Face = "Green", Dot = "Yellow" },
	HexaLucky = { Face = "Purple", Dot = "Blue" },
	Launcher = { Face = "Teal", Dot = "Green" },
} :: { [string]: { Face: string, Dot: string } }

local function pixelPill(button: TextButton, look: { Face: string, Dot: string })
	local pill = button:FindFirstChild("Pill") :: Frame?
	if not pill then
		return
	end
	for _, child in pill:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UICorner") then
			child:Destroy()
		end
	end
	pill:SetAttribute("Pixel", true)
	Pop.face(pill, look.Face, 12)
	Pop.studs(pill, 12, 0.45, 28, pill.ZIndex)
	local lip = Pop.lipUnits(BoostView.ChipHeight)
	local dot = pill:FindFirstChild("Dot") :: Frame?
	if dot then
		for _, child in dot:GetChildren() do
			if child:IsA("UIStroke") or child:IsA("UICorner") then
				child:Destroy()
			end
		end
		dot.Position = UDim2.new(0, 4, 0.5, -math.floor(lip / 2))
		Pop.face(dot, look.Dot, 8, true, false)
		local border = dot:FindFirstChild("Border") :: UIStroke?
		if border then
			border.Thickness = 2.5
		end
		Pop.studs(dot, 8, 0.45, 20, dot.ZIndex)
		dot.ZIndex = 3
		local art = dot:FindFirstChild("Art")
		if art and art:IsA("GuiObject") then
			art.ZIndex = 4
			for _, d in art:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = math.max(d.ZIndex, 4)
				end
			end
		end
		local mult = dot:FindFirstChild("Mult") :: TextLabel?
		if mult then
			mult.FontFace = PopTheme.Pixel
			mult.TextColor3 = PopTheme.Ink
			mult.ZIndex = 5
			Pop.edge(mult, 2)
			Pop.fit(mult, 24)
		end
	end
	local label = pill:FindFirstChild("Text") :: TextLabel?
	if label then
		label.FontFace = PopTheme.Pixel
		label.TextColor3 = PopTheme.Ink
		label.ZIndex = 4
		for _, child in label:GetChildren() do
			if child:IsA("UIStroke") then
				child:Destroy()
			end
		end
		Pop.edge(label, 2)
		Pop.fit(label, CHIP_PIXEL)
		label.TextXAlignment = Enum.TextXAlignment.Left
	end
end

--[[
	The corner look (owner 2026-10-24, his Studio photo: not a pill next to
	the train chip, only the four-leaf picture with the time counting down
	under it, bottom right): with the light UI each running boost is its
	picture alone (BoostView.art: the clover, Hexa's gem) over its time left
	in white pixel letters, in a row at the bottom-right corner that grows
	to the left (placeCorner). The BOOSTS launcher never shows there (the
	side menu's BOOSTS tile opens the view). The same names as the pills
	(Pill, Dot, Art, Text), so setChips drives both; the button (the touch
	area) is the whole tile, at least 44 pt on a phone.
]]
BoostView.CornerIcon = 64 -- the picture (design units)
BoostView.CornerText = 24 -- the time under it
BoostView.CornerWidth = 72 -- one tile's touch area (44 pt at the phone scale 0.62)
BoostView.CornerTextWidth = 72 -- the time stays inside its tile (a long one shrinks: "23h 59m")
BoostView.CornerGap = 14
BoostView.CornerRight = 20 -- from the screen's right edge
BoostView.CornerBottom = 20 -- from the bottom (mouse, gamepad)
BoostView.CornerJumpGap = 8 -- pixels kept free beside / over Roblox's touch jump button

-- One tile's height (design units): the picture, the time under it.
function BoostView.cornerHeight(): number
	return BoostView.CornerIcon + 2 + BoostView.CornerText
end

local function cornerTile(button: TextButton, kindId: string)
	button:SetAttribute("Corner", true)
	local pill = button:FindFirstChild("Pill") :: Frame?
	if not pill then
		return
	end
	for _, child in pill:GetChildren() do
		child:Destroy()
	end
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 0)
	pill.Size = UDim2.fromOffset(BoostView.CornerIcon, BoostView.CornerIcon)
	pill.BackgroundTransparency = 1
	pill.ClipsDescendants = false
	local round = PopTheme.round()
	if round then
		-- the round look (the reel's bottom-right squares): a bright studded face in the boost's colour
		local paints = BoostView.ChipPaints[kindId]
		pill.BackgroundTransparency = 0
		Pop.face(pill, if paints then paints.Face else "Green", PopTheme.Corner)
		Pop.studs(pill, PopTheme.Corner, 0.45, 28, 2)
	end
	local dot = UIKit.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if round then 0.46 else 0.5),
		Size = UDim2.fromScale(if round then 0.8 else 1, if round then 0.8 else 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, pill)
	BoostView.art(dot, kindId, false).Size = UDim2.fromScale(1, 1)
	local label = UIKit.label(pill, "", BoostView.CornerText, {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, if round then 0.5 else 0),
		-- (the round look: over the tile's bottom edge, the reel's "inf")
		Position = if round then UDim2.new(0.5, 0, 1, 0) else UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(BoostView.CornerTextWidth, BoostView.CornerText),
		FontFace = PopTheme.Pixel,
		TextColor3 = PopTheme.Ink,
		TextWrapped = false,
		ZIndex = 5,
	})
	Pop.edge(label, if round then 2.5 else 2)
	Pop.fit(label, BoostView.CornerText)
	button.Size = UDim2.fromOffset(BoostView.CornerWidth, BoostView.cornerHeight())
end

--[[
	Where the corner row goes: design units from the right edge and the bottom
	of the chips' gui. Every rect is in that gui's frame: it starts under
	Roblox's top bar (CoreUISafeInsets), so `Gui` is its AbsoluteSize, never
	the camera's viewport (review 2026-10-28 #1).
	- Mouse / gamepad: the very corner, 5% in on a TV (TutorialView.TenFootSafe),
	  standing on the tutorial card while it shows there (`TutorialTop`).
	- Touch, a tablet (the Shop pill at the bottom left): a column over Roblox's
	  jump button (120 px reaching 210 px up), clear of the game's Grab and FIRE
	  buttons (both lower, further left).
	- Touch, a phone (the Shop pill at the top right): the phone's bottom right
	  is the jump, Grab and FIRE buttons, so the row stands on the Shop pill, at
	  the right edge (review 2026-10-28: on any lower spot a tap meant for FIRE
	  opened Boosts). The touch tutorial bubble has that corner while it shows
	  (its SKIP sits right over the pill's row), so the row goes, in this order
	  (review 2026-10-28 follow-up: the moved row kept the right edge's height
	  and could land on FIRE's top or on the toasts):
	    Beside      left of the bubble, re-checked against the touch buttons
	                under that strip, clear of the toasts' column (ToastColumn)
	    Below       under the bubble at the right edge (and under the pill),
	                when that is clear of the touch buttons and the toasts
	    OverToasts  left of the bubble, clear of the touch buttons, over the
	                toasts' column (toasts take no taps; the bubble's SKIP and
	                FIRE do)
	    OnPill      (no room at all) the pill's spot, under the bubble
	Returns right, bottom, whether the tiles stack in a column, and the spot:
	"Corner" (mouse, gamepad), "Column" (a tablet), "Pill" (a phone) or one of
	the bubble's spots above.
]]
export type PillRect = { Left: number, Top: number?, Bottom: number } -- design units from the gui's top-left

export type CornerInput = {
	Screen: Vector2, -- the whole screen (px): which touch layout Roblox picks
	Gui: Vector2, -- the chips' gui (px, AbsoluteSize)
	Scale: number,
	Touch: boolean,
	TenFoot: boolean?,
	Count: number?, -- the boosts shown
	TutorialTop: number?, -- the mouse tutorial card's top, design units from the gui's bottom
	Bubble: PillRect?, -- the touch tutorial bubble (top right): its left edge and bottom
	Pill: PillRect?, -- the phone's Shop pill (top right): its left edge, top and bottom
	Avoid: PillRect?, -- the round look's offers column (right edge, middle): the row moves left of it
	Chip: ChipRect?, -- the TRAIN chip beside the round look's tiles (touch phones): never under the corner
}

-- A box in design units in the chips' gui (the TRAIN chip's frame).
export type ChipRect = { Left: number, Top: number, Right: number, Bottom: number }

BoostView.TenFootSafe = 0.05 -- (TutorialView.TenFootSafe: the TV's title-safe band)
-- The HUD's toast column (HudBubble.buildGame: centred, from y 70, HudBubble.toastColor's
-- 440 wide pills; HudController shows 3 at most, 56 apart), design units from the gui's top.
BoostView.ToastColumn = { Width = 440, Top = 70, Height = 3 * 56 }

-- The touch buttons in the phone's bottom right, in px from the gui's bottom-right corner
-- (left, top, right, bottom edges; small = the shorter screen side 500 px or less). The
-- LightUI spec reads InteractController / MiningController to keep these in step. (Grab:
-- Roblox draws CAS buttons 45 px, 35 on a 320 px screen; 70 / 90 here is on the safe side.)
-- (the table lives in HudBubble: the round look's tiles and TRAIN chip keep clear of it too)
BoostView.TouchButtons = HudBubble.TouchButtons

-- The highest top (design units from the gui's top) of the touch buttons whose
-- columns reach the strip from `left` to `right` (design units from the gui's left).
local function touchButtonsTop(screen: Vector2, w: number, h: number, s: number, left: number, right: number): number
	local small = math.min(screen.X, screen.Y) <= 500
	local top = h
	for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
		local bLeft, bRight = w - b.Left / s, w - b.Right / s
		if left < bRight and bLeft < right then
			top = math.min(top, h - b.Top / s)
		end
	end
	return top
end

--[[
	Is a corner row `rowW` wide at `right` (design units from the gui's right
	edge) with its top at `top` clear of the touch buttons under it, the
	toasts' column (when `toasts`) and the gui's edges?
]]
local function rowClear(input: CornerInput, w: number, h: number, right: number, top: number, rowW: number, toasts: boolean): boolean
	local s = math.max(input.Scale, 0.01)
	local gap = BoostView.CornerGap
	local tile = BoostView.cornerHeight()
	local left = w - right - rowW
	if left < gap or top < gap or top + tile > h - gap then
		return false
	end
	if top + tile > touchButtonsTop(input.Screen, w, h, s, left, w - right) - gap then
		return false
	end
	if toasts then
		local column = BoostView.ToastColumn
		local columnLeft, columnRight = w / 2 - column.Width / 2, w / 2 + column.Width / 2
		if left < columnRight and columnLeft < w - right and top < column.Top + column.Height and column.Top < top + tile then
			return false
		end
	end
	return true
end

function BoostView.cornerSpot(input: CornerInput): (number, number, boolean, string)
	local s = math.max(input.Scale, 0.01)
	local w, h = input.Gui.X / s, input.Gui.Y / s
	local gap = BoostView.CornerGap
	local tile = BoostView.cornerHeight()
	local right, bottom = BoostView.CornerRight, BoostView.CornerBottom
	if input.TenFoot then
		right = math.max(right, math.ceil(w * BoostView.TenFootSafe))
		bottom = math.max(bottom, math.ceil(h * BoostView.TenFootSafe))
	end
	local stacked = false
	local spot = "Corner"
	local pill, bubble = input.Pill, input.Bubble
	local count = math.max(1, input.Count or #BoostConfig.KindIds)
	if input.Touch and pill == nil then
		-- (a column at the right edge, on the touch buttons under it)
		local function columnBottom(r: number): number
			local buttonsTop = touchButtonsTop(input.Screen, w, h, s, w - r - BoostView.CornerWidth, w - r)
			return math.ceil(h - buttonsTop + BoostView.CornerJumpGap / s)
		end
		bottom = math.max(bottom, columnBottom(right))
		stacked = true
		spot = "Column"
		-- (the round look's phones have no Shop pill on the right: while the touch tutorial bubble
		-- shows at the top right and the column would reach it, the column moves left of it)
		local columnH = count * tile + (count - 1) * gap
		if bubble and w - right > bubble.Left and h - bottom - columnH < bubble.Bottom + gap then
			local beside = math.ceil(w - bubble.Left) + gap
			right, bottom = beside, math.max(bottom, columnBottom(beside))
			local rowW = BoostView.CornerWidth
			if h - bottom - columnH < gap then
				-- (no room for the column over the touch buttons: side by side instead, unless that
				-- runs onto the TRAIN chip beside the tiles: then the column from the top down)
				local sideW = count * BoostView.CornerWidth + (count - 1) * gap
				local sideBottom = bottom
				for _, r in { beside, beside + sideW - BoostView.CornerWidth } do
					sideBottom = math.max(sideBottom, columnBottom(r))
				end
				local chip = input.Chip
				local sideLeft, sideTop = w - beside - sideW, h - sideBottom - tile
				local onChip = chip ~= nil
					and sideLeft < chip.Right
					and chip.Left < w - beside
					and sideTop < chip.Bottom
					and chip.Top < sideTop + tile
				if onChip then
					bottom = math.ceil(h - gap - columnH)
				else
					stacked, columnH, rowW, bottom = false, tile, sideW, sideBottom
				end
			end
			-- (over the toasts' column when it must: toasts take no taps)
			local column = BoostView.ToastColumn
			local left, top = w - right - rowW, h - bottom - columnH
			local overToasts = left < w / 2 + column.Width / 2
				and w / 2 - column.Width / 2 < w - right
				and top < column.Top + column.Height
				and column.Top < top + columnH
			spot = if overToasts then "OverToasts" else "Beside"
		end
	elseif input.Touch and pill then
		-- (a row on the Shop pill, and on any touch button its tiles would reach)
		local rowW = count * BoostView.CornerWidth + (count - 1) * gap
		local pillTop = pill.Top or (pill.Bottom - 72)
		local function onPill(r: number): number
			local limit = math.min(pillTop, touchButtonsTop(input.Screen, w, h, s, w - r - rowW, w - r))
			return math.max(gap, limit - gap - tile)
		end
		local rowTop = onPill(right)
		spot = "Pill"
		-- (the touch tutorial bubble, at the top right, has the corner while it shows: see above)
		if bubble and w - right > bubble.Left and rowTop < bubble.Bottom + gap then
			local beside = math.ceil(w - bubble.Left) + gap
			local besideTop = onPill(beside)
			local belowTop = bubble.Bottom + gap
			if w - right > pill.Left and belowTop + tile + gap > pillTop then
				belowTop = math.max(belowTop, pill.Bottom + gap) -- (under the pill too)
			end
			if rowClear(input, w, h, beside, besideTop, rowW, true) then
				right, rowTop, spot = beside, besideTop, "Beside"
			elseif rowClear(input, w, h, right, belowTop, rowW, true) then
				rowTop, spot = belowTop, "Below"
			elseif rowClear(input, w, h, beside, besideTop, rowW, false) then
				right, rowTop, spot = beside, besideTop, "OverToasts"
			else
				spot = "OnPill"
			end
		end
		bottom = math.ceil(h - rowTop - tile)
	end
	if input.TutorialTop then
		bottom = math.max(bottom, input.TutorialTop + gap)
	end
	-- the round look's offers at the right edge (HudBubble.offers): a row that would reach
	-- them (standing on the tutorial card, a tall column) goes left of the column
	local avoid = input.Avoid
	if avoid then
		local rowH = if stacked then count * tile + (count - 1) * gap else tile
		local top = h - bottom - rowH
		local avoidTop = avoid.Top or (avoid.Bottom - tile)
		if w - right > avoid.Left - gap and top < avoid.Bottom + gap and avoidTop - gap < top + rowH then
			right = math.ceil(w - avoid.Left) + gap
			spot = "BesideOffers"
		end
	end
	return right, bottom, stacked, spot
end

-- Moves the corner row (a light build's chips) to `right`, `bottom` (BoostView.cornerSpot),
-- side by side or `stacked` in a column.
function BoostView.placeCorner(refs: ChipRefs, right: number, bottom: number, stacked: boolean?)
	local row = refs.Row
	row.Position = UDim2.new(1, -right, 1, -bottom)
	local count = #BoostConfig.KindIds
	local list = row:FindFirstChildOfClass("UIListLayout")
	if list then
		list.FillDirection = if stacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	end
	row.Size = if stacked
		then UDim2.fromOffset(BoostView.CornerWidth + 30, count * (BoostView.cornerHeight() + BoostView.CornerGap) + BoostView.ChipHeight)
		else UDim2.fromOffset(count * (BoostView.CornerWidth + BoostView.CornerGap) + 30, BoostView.cornerHeight())
	row:SetAttribute("Stacked", stacked == true)
end

local darkBuildChips = BoostView.buildChips
BoostView.buildChips = function(): ChipRefs
	local refs = darkBuildChips()
	if UIConfig.lightUI() then
		refs.Gui:SetAttribute("PopSkin", true)
		for kindId, button in refs.Chips do
			cornerTile(button, kindId)
		end
		pixelPill(refs.Launcher, BoostView.ChipPaints.Launcher)
		BoostView.setChipText(refs.Launcher, "", "BOOSTS")
		local row = refs.Row
		row:SetAttribute("Corner", true)
		-- (the gamepad glyph at the row's far end: the tiles keep the corner)
		local glyphHolder = row:FindFirstChild("GlyphHolder")
		if glyphHolder and glyphHolder:IsA("GuiObject") then
			glyphHolder.LayoutOrder = -1
		end
		row.AnchorPoint = Vector2.new(1, 1)
		local list = row:FindFirstChildOfClass("UIListLayout")
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Right
			list.VerticalAlignment = Enum.VerticalAlignment.Bottom
			list.Padding = UDim.new(0, BoostView.CornerGap)
		end
		BoostView.placeCorner(refs, BoostView.CornerRight, BoostView.CornerBottom, false)
	end
	return refs
end

return BoostView
