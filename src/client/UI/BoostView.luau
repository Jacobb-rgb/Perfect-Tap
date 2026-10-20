--[[
	The luck boosts view (pure builder + pure helpers; BoostController fills
	it in) and the boost chips under the HUD coins.

	Panel (one ScreenGui):
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
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local HudView = require(script.Parent.HudView)
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
function BoostView.context(rawState: any, now: number?): BoostConfig.LuckContext
	local state = safeState(rawState)
	local bonuses = bonusesOf(state)
	local mult = math.max(1, num(bonuses.OreLuckMult, 1))
	if now and mult > 1 and not BoostConfig.active(state.Boosts, "HexaLucky", now) then
		mult = 1
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
		for oreId in zone.Ores do
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

-- The capsules whose odds the Triple Lucky card shows (the ones the player may open).
function BoostView.capsules(restricted: boolean): { string }
	local list = {}
	for _, capsule in CapsuleConfig.List do
		if not (restricted and CapsuleConfig.isPaidRandom(capsule.Id)) then
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
			local without, with = BoostConfig.hexaLuck(ctx.OreLuckPct)
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
	local without, with = BoostConfig.hexaLuck(ctx.OreLuckPct)
	local zone = if zoneId then WorldLayout.ZoneById[zoneId] else nil
	local rows: { OddsRow } = {}
	local summary: OddsRow? = nil
	local note = `Ore luck {BoostView.mult(without)} without, {BoostView.mult(with)} with Hexa Lucky. Chance per ore in a rock you break.`
	if zone then
		local after: { [string]: number } = {}
		for _, line in BoostConfig.oreOdds(zone.Ores, with) do
			after[line.Ore] = line.Chance
		end
		local orders: { number } = {}
		for _, line in BoostConfig.oreOdds(zone.Ores, without) do
			local ore = OreData.ById[line.Ore]
			local info = Rarity.get(ore.Rarity)
			table.insert(rows, BoostView.row(ore.Name, info.Color, line.Chance, after[line.Ore] or 0))
			table.insert(orders, info.Order)
		end
		rows = BoostView.rarestFirst(rows, orders)
		local before = BoostConfig.rareShare(zone.Ores, without)
		if before > 0 then
			summary = BoostView.row("Rare or better", Rarity.get("Rare").Color, before, BoostConfig.rareShare(zone.Ores, with))
		else
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
function BoostView.icon(parent: Instance, size: number, kindId: string): Frame
	local tile = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(tile, 12)
	UIKit.stroke(tile, 2.5)
	BoostView.setIcon(tile, kindId)
	return tile
end

function BoostView.setIcon(tile: Frame, kindId: string)
	if tile:GetAttribute("Kind") == kindId then
		return
	end
	tile:SetAttribute("Kind", kindId)
	local old = tile:FindFirstChild("Art")
	if old then
		old:Destroy()
	end
	BoostView.art(tile, kindId, true)
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
	Normal = { Select = 44, Head = 22, Row = 28, Text = 17, Col = 96, Note = 40 },
	Compact = { Select = 72, Head = 26, Row = 32, Text = 20, Col = 116, Note = 48 },
}

local function tableMetrics(compact: boolean): TableMetrics
	return if compact then TABLE_METRICS.Compact else TABLE_METRICS.Normal
end
BoostView.tableMetrics = tableMetrics

local function newRow(parent: Instance, name: string, order: number): RowRefs
	local frame = UIKit.new("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = if order % 2 == 0 then 1 else 0.55,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 6)
	local label = UIKit.label(frame, "", 17, {
		Name = "Name",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local before = UIKit.label(frame, "", 17, {
		Name = "Before",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local after = UIKit.label(frame, "", 17, {
		Name = "After",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	return { Frame = frame, Name = label, Before = before, After = after }
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
	row.Name.TextColor3 = data.Color
	local fitWidth = tonumber(row.Name:GetAttribute("FitWidth"))
	if fitWidth then
		local size = tonumber(row.Name:GetAttribute("FullSize")) or row.Name.TextSize
		TechShopView.fitText(row.Name, fitWidth, row.Frame.Size.Y.Offset, size, 12)
	end
	row.Before.Text = data.Before
	row.After.Text = data.After
	row.After.TextColor3 = if data.Change > 0 then Theme.Good elseif data.Change < 0 then Theme.TextDim else Theme.Text
end

--[[
	An odds table in `parent`: a selector row ([<] title [>]; the arrows are
	hidden when there's nothing to switch, `selector` false: no arrows at
	all), column headers, a highlighted summary row, a scrolling list of
	rows and a note at the bottom.
]]
function BoostView.buildTable(parent: Instance, selector: boolean): TableRefs
	local frame = UIKit.new("Frame", {
		Name = "Odds",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)
	local prev = UIKit.button(frame, "<", Theme.PanelLight, Theme.Panel, { Name = "Prev", TextSize = 26 })
	local nextButton = UIKit.button(frame, ">", Theme.PanelLight, Theme.Panel, { Name = "Next", TextSize = 26 })
	local title = UIKit.label(frame, "", 22, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local head: { TextLabel } = {}
	for i, name in { "HeadName", "HeadBefore", "HeadAfter" } do
		table.insert(
			head,
			UIKit.label(frame, "", 14, {
				Name = name,
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
				TextColor3 = Theme.TextDim,
				TextWrapped = false,
			})
		)
	end
	local summary = newRow(frame, "Summary", 1)
	summary.Frame.BackgroundColor3 = Theme.Panel
	summary.Frame.BackgroundTransparency = 0
	UIKit.stroke(summary.Frame, 2)
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, frame)
	UIKit.list(list, Enum.FillDirection.Vertical, 2)
	local note = UIKit.label(frame, "", 15, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
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

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end
BoostView.holderOf = holderOf

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
		t.Prev.TextSize = if compact then 30 else 26
		t.Next.TextSize = t.Prev.TextSize
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

-- A coins chip like the HUD's (icon + amount) for a panel header.
function BoostView.balance(parent: Instance): (Frame, TextLabel)
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(balance, 10)
	UIKit.stroke(balance, 2)
	local coin = HudView.coinIcon(balance, 26)
	coin.Position = UDim2.fromOffset(8, 7)
	local amount = UIKit.label(balance, "$0", 24, {
		Name = "Amount",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return balance, amount
end

function BoostView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeBoosts", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
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
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, { Name = "Close", AnchorPoint = Vector2.new(1, 0), TextSize = 26 })
	local balance, balanceAmount = BoostView.balance(panel)

	local tabBar = UIKit.new("Frame", { Name = "TabBar", BackgroundTransparency = 1 }, panel)
	local tabs: { [string]: TextButton } = {}
	for _, kindId in BoostView.Tabs do
		tabs[kindId] =
			UIKit.button(tabBar, BoostView.TabTitles[kindId], Theme.Accent, Theme.AccentDark, { Name = "Tab" .. kindId, TextSize = 22 })
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
			}, tabBar)
		)
	end

	-- the boost card (left)
	local cardFrame = UIKit.new("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(cardFrame, 12)
	UIKit.stroke(cardFrame, 2.5)
	local icon = BoostView.icon(cardFrame, 84, "TripleLucky")
	local name = UIKit.label(cardFrame, "", 28, {
		Name = "BoostName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local status = UIKit.label(cardFrame, "", 18, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	})
	local description = UIKit.label(cardFrame, "", 16, {
		Name = "Description",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
		ClipsDescendants = true,
	})
	local keyLine = UIKit.label(cardFrame, "", 18, {
		Name = "KeyLine",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local offers: { TextButton } = {}
	for i = 1, 3 do
		table.insert(offers, UIKit.button(cardFrame, "", Theme.Accent, Theme.AccentDark, { Name = "Offer" .. i, TextSize = 20 }))
	end
	local note = UIKit.label(cardFrame, "", 15, {
		Name = "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})

	local odds = BoostView.buildTable(panel, true)
	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
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

	-- tabs: equal buttons, room for the LB / RB glyphs at the ends
	refs.TabBar.Position = UDim2.fromOffset(PAD, m.Header)
	refs.TabBar.Size = UDim2.new(1, -(PAD * 2 + m.TabGap), 0, m.TabBar)
	local count = #BoostView.Tabs
	local inset = 26
	local share = 1 / count
	local fixed = (2 * inset + GAP * (count - 1)) / count
	for i, kindId in BoostView.Tabs do
		local holder = holderOf(refs.Tabs[kindId])
		holder.Position = UDim2.new(share * (i - 1), inset + (i - 1) * (GAP - fixed), 0, 6)
		holder.Size = UDim2.new(share, -fixed, 0, m.TabHeight)
		refs.Tabs[kindId].TextSize = if compact then 24 else 22
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
			if holder.Visible then
				i += 1
			end
		end
		y += m.Offer + GAP + 4
	else
		for _, button in card.Offers do
			local holder = holderOf(button)
			holder.Position = UDim2.fromOffset(12, y)
			holder.Size = UDim2.new(1, -24, 0, m.Offer)
			button.TextSize = 20
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

local function style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holderOf(button).BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end
BoostView.style = style

-- Shows one boost's tab (and marks its tab button).
function BoostView.setTab(refs: Refs, kindId: string)
	refs.Tab = kindId
	for _, id in BoostView.Tabs do
		local on = id == kindId
		local button = refs.Tabs[id]
		button.BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight
		holderOf(button).BackgroundColor3 = if on then Theme.AccentDark else Theme.PanelDark
		button.TextColor3 = if on then Theme.Text else Theme.TextDim
	end
end

-- The tab after (dir = 1) or before (dir = -1) `kindId`, wrapping.
function BoostView.nextTab(kindId: string, dir: number): string
	return BoostView.cycle(BoostView.Tabs, kindId, if dir < 0 then -1 else 1) or BoostView.Tabs[1]
end

-- Fills the card from BoostView.cards. Buttons that show an answer (Busy) keep their text.
function BoostView.setCard(refs: Refs, card: Card)
	local c = refs.Card
	BoostView.setIcon(c.Icon, card.Kind)
	c.Name.Text = string.upper(card.Name)
	c.Status.Text = card.Status
	c.Status.TextColor3 = card.StatusColor
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
		if offer and button:GetAttribute("Busy") ~= true then
			button.Text = if refs.Compact then `{offer.Label}\n{offer.PriceText}` else offer.Text
			if offer.Robux then
				style(button, offer.CanBuy, Theme.Good, Theme.GoodDark)
			else
				style(button, offer.CanBuy, Theme.Accent, Theme.AccentDark)
			end
		end
	end
	BoostView.placeOffers(refs, math.min(#card.Offers, #c.Offers))
	for _, button in c.Offers do
		BoostView.fitButton(button, refs.Compact)
	end
	c.Note.Text = card.Note
	local noteHeight = tonumber(c.Frame:GetAttribute("NoteHeight")) or 40
	TechShopView.fitText(c.Note, width - 24, noteHeight, m.Note, m.Note - 3)
end

-- The card's note line shows a status (an answer) for a moment; nil puts the note back.
function BoostView.setStatus(refs: Refs, text: string?, color: Color3?, note: string)
	local c = refs.Card
	c.Note.Text = text or note
	c.Note.TextColor3 = if text then color or Theme.Text else Theme.TextDim
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

function BoostView.showReceipt(refs: Refs, text: string, color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = color
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
		table.insert(list, holderOf(refs.Tabs[kindId]))
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
function BoostView.setChipText(button: TextButton, tag: string, text: string)
	local pill = button:FindFirstChild("Pill") :: Frame?
	if not pill then
		return
	end
	local label = pill:FindFirstChild("Text") :: TextLabel
	local x = 4 + CHIP_DOT + 8
	label.Text = if tag == "" then text else `{tag} {text}`
	local width = math.ceil(TechShopView.textWidth(label.Text, CHIP_TEXT)) + 2
	label.Position = UDim2.fromOffset(x, 0)
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
	local function pill(text: string): number
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

-- Moves the chips' row to `top` (BoostView.chipsTop).
function BoostView.placeChips(refs: ChipRefs, top: number)
	refs.Row.Position = UDim2.fromOffset(BoostView.ChipLeft, top)
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

-- Shows the running boosts' chips (BoostView.chips); the launcher when
-- none runs and `launcher` is on.
function BoostView.setChips(refs: ChipRefs, chips: { Chip }, launcher: boolean)
	local shown: { [string]: boolean } = {}
	for _, chip in chips do
		local button = refs.Chips[chip.Kind]
		if button then
			shown[chip.Kind] = true
			BoostView.setChipText(button, chip.Tag, chip.Text)
			button.Visible = true
		end
	end
	for kindId, button in refs.Chips do
		if not shown[kindId] then
			button.Visible = false
		end
	end
	refs.Launcher.Visible = launcher and #chips == 0
end

return BoostView
