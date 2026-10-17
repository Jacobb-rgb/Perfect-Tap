--[[
	The Enchant shop view at the rune table (pure builder + pure helpers;
	EnchantController fills it in). One ScreenGui:

	  header   ENCHANTS, a line about enchants (or the last message), your
	           coins and crystal shards, the X button
	  left     YOUR BLASTER: the enchant slots (the blaster level opens 1, 2,
	           3, 4 slots: EnchantConfig.SlotLevels; a locked slot says which
	           level opens it; a filled one its main effect in short: "+20%
	           damage"), then the catalog grouped by rarity (Common ..
	           Mythic): rune, name, tier ("NEW", "II / III", "MAX"), what it
	           does ("+10% blaster damage": the owned tier, else tier I) and
	           a line (in which slot, owned, or the price)
	  right    the picked enchant: rune, name, rarity and tier chips, what it
	           does, now -> next tier, then
	             odds boosters (Lucky, Prospector, Starbreaker): THE NEW ODDS
	             in numbers before any buy (Roblox rule): per zone (< > to
	             switch, your current zone first) the chance of each lucky
	             rarity now and after the buy and the artifact chance per
	             rock (BoostConfig.preview with EnchantConfig.nextDelta)
	             the others: every tier's effect
	           and at the bottom a status line and the buttons: BUY $X
	           (coins), N SHARDS (Epic and Legendary), 20 R$ (the two
	           Mythics; "20 R$ • SOON", greyed, while the pass id is 0;
	           hidden where paid random items are restricted for an odds
	           booster), EQUIP / UNEQUIP (owned enchants); one COMING SOON
	           button for an enchant whose effect only a package that isn't
	           in the game yet reads (BoostView.soonSet)
	           The odds are the lasting ones: a running Hexa Lucky is left
	           out, and the AFTER column says "IN A SLOT" when the buy
	           doesn't put the enchant in a slot (owned but not equipped;
	           or every open slot full: then AFTER is with it in place of
	           the slotted enchant that gives the least luck, named in the
	           note). While artifacts aren't in the game (Prospector is
	           coming soon) the artifact rows are left out (Prospector's
	           own table stays, as information) and the note says so.
	  gamepad  the selection starts on the picked catalog row, never on a
	           buy button (A is also jump: no buy by a reflex press)
	  footer   the control hint; gamepads get the platform's own glyphs
	           (on phones and TVs only the gamepad row, bigger)
	The right pane's middle scrolls when a small screen can't show it all
	(the buttons always stay in view). Designed for 720 design units of
	height (HudController.uiScale); the compact layout (phones, TVs) makes
	every button, slot and list row at least 72 units (44 pt at the phone
	scale 0.62). Everything comes from the State snapshot (Enchants,
	BlasterLevel, Coins, Shards, Bonuses, Perks) and EnchantConfig, so the
	cards show exactly what the server will quote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local StatConfig = require(Shared.Config.StatConfig)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local BoostView = require(script.Parent.BoostView)
local TechShopView = require(script.Parent.TechShopView)

local EnchantView = {}

export type Buy = {
	Currency: string, -- "Coins" | "Shards" | "Robux" | "Max" (the top tier: a greyed button)
	Text: string, -- the button text
	Price: number?, -- coins or shards
	Product: string?, -- Robux: the MonetizationConfig key
	Tier: number, -- the EnchantAction Tier (the tier being bought)
	CanBuy: boolean,
	Reason: string?, -- why not: an EnchantConfig.Reasons code or "ComingSoon"
}

export type Card = {
	Id: string,
	Name: string,
	Rarity: string,
	RarityName: string,
	RarityColor: Color3,
	Color: Color3, -- the rune color
	Description: string,
	Order: number,
	Tier: number, -- owned tier (0 = not owned)
	MaxTier: number,
	Owned: boolean,
	Done: boolean, -- top tier
	Slot: number?, -- the open slot it sits in
	TierText: string, -- "NEW", "II / III", "MAX", "OWNED"
	Effect: string, -- the list row's second line: what the owned tier does (tier I when not owned)
	ListLine: string, -- the list row's third line: in which slot, owned, or the price
	ListLineColor: Color3,
	Now: string,
	Next: string,
	Tiers: string, -- every tier's effect, one line each
	Buys: { Buy },
	Odds: boolean, -- an odds booster: the detail shows the new odds
}

export type SlotCard = {
	Index: number,
	Open: boolean,
	Need: number, -- the blaster level that opens it
	Id: string?, -- the enchant in it
	Name: string,
	Sub: string,
	Color: Color3,
}

export type SlotRefs = { Button: TextButton, Rune: Frame, Name: TextLabel, Sub: TextLabel }
export type RowRefs = {
	Id: string,
	Button: TextButton,
	Rune: Frame,
	Name: TextLabel,
	Tier: TextLabel,
	Effect: TextLabel,
	Line: TextLabel,
}

export type DetailRefs = {
	Frame: Frame,
	Rune: Frame,
	Name: TextLabel,
	RarityChip: TextLabel,
	TierChip: TextLabel,
	Body: ScrollingFrame,
	Description: TextLabel,
	Now: TextLabel,
	Next: TextLabel,
	OddsNote: TextLabel, -- the odds table's note (the luck now -> after), under Next
	Odds: BoostView.TableRefs,
	TiersBox: Frame, -- ALL TIERS (the enchants that change no odds)
	TiersTitle: TextLabel,
	Tiers: TextLabel,
	Status: TextLabel,
	Buttons: { TextButton }, -- the buy buttons (in Card.Buys order)
	Equip: TextButton,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Receipt: TextLabel,
	Balance: Frame,
	BalanceAmount: TextLabel,
	ShardBalance: Frame,
	ShardAmount: TextLabel,
	Close: TextButton,
	SlotLabel: TextLabel,
	Slots: { SlotRefs },
	List: ScrollingFrame,
	Groups: { [string]: TextLabel }, -- by rarity
	Rows: { [string]: RowRefs },
	RowList: { RowRefs },
	Detail: DetailRefs,
	Hint: TextLabel,
	PadHint: Frame,
	PadGlyphs: { ImageLabel },
	PadMode: boolean,
	Selected: string,
	Compact: boolean,
	BodyWidth: number, -- the width of the texts in the detail's middle
	Wide: boolean, -- the detail has two columns: info left, odds / tiers right
	RightWidth: number, -- the right column's box (wide)
	RightHeight: number,
	MaxWidth: number, -- the last layout's room (setHint lays out again when the gamepad row comes or goes)
	MaxHeight: number,
}

EnchantView.MinHeight = 380
EnchantView.CoinsBottom = 96
-- studs from the table's surface at which the open view closes: under the
-- server's EnchantConfig.Range (30), so lag never gets a BUY refused as TooFar
EnchantView.CloseRange = 24
EnchantView.ShardColor = Color3.fromRGB(110, 230, 255)
-- the detail pane gets two columns (info | odds or tiers) from this width (design units)
EnchantView.WideDetail = 640
EnchantView.Separator = TechShopView.Separator

-- What a coming-soon enchant waits for (BoostView.soonSet; the server refuses it until then).
EnchantView.SoonText = {
	Prospector = "Coming soon, with artifacts",
	GolemBond = "Coming soon, with golems",
	Magnetism = "Coming soon, with the Ore Magnet",
} :: { [string]: string }
-- While this enchant is coming soon, artifacts aren't in the game (BoostService.Consumers:
-- Prospector -> ArtifactService): the odds tables leave the artifact rows out.
EnchantView.ArtifactsWith = "Prospector"

-- The slot cards' short stat names (their sub line is narrow): "+20% damage".
EnchantView.ShortLabels = {
	DamagePct = "damage",
	OverchargePct = "surge",
	ReachStuds = "range",
	MagnetBonus = "magnet",
	TwinDropChance = "twin chunk",
	ArtifactPct = "artifacts",
	SellPct = "sell value",
	GolemBondPct = "golem bonus",
	WalkSpeed = "speed",
} :: { [string]: string }
-- the stat a slot card shows when an enchant has two (Heartfire: damage, Starbreaker: ore luck)
EnchantView.ShortOrder = {
	"DamagePct",
	"OreLuckPct",
	"OverchargePct",
	"ReachStuds",
	"WalkSpeed",
	"MagnetBonus",
	"TwinDropChance",
	"SellPct",
	"ArtifactPct",
	"GolemBondPct",
}

-- Status lines the controller shows (here so the tests can check they fit).
EnchantView.StatusText = {
	NoAnswer = "No answer, try again",
	Waiting = "Wait for your last buy",
	PickSlot = "Pick a slot on the left for it",
	Equipped = "Equipped!",
	Unequipped = "Taken out of its slot",
	LateBought = "Bought!",
}

local SEP = TechShopView.Separator
local PAD = 16
local GAP = 8
local SCROLLBAR = 8

---------------------------------------------------------------- pure helpers

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function num(v: any, default: number): number
	return if finite(v) then v else default
end

local function safeState(state: any): { [string]: any }
	return if type(state) == "table" then state else {}
end

local function levelOf(state: { [string]: any }): number
	return num(state.BlasterLevel, 1)
end

-- "I", "II", ... (a number past the names)
function EnchantView.tierName(tier: number): string
	return EnchantConfig.TierNames[tier] or tostring(tier)
end

-- The crystal shards in a State snapshot.
function EnchantView.shards(rawState: any): number
	local n = num(safeState(rawState).Shards, 0)
	return if n > 0 then math.floor(n) else 0
end

-- The open slot an enchant sits in (nil when none).
function EnchantView.slotOf(enchants: any, blasterLevel: any, id: string): number?
	local slots = if type(enchants) == "table" then enchants.Slots else nil
	if type(slots) ~= "table" then
		return nil
	end
	for i = 1, EnchantConfig.unlockedSlots(blasterLevel) do
		if slots[i] == id then
			return i
		end
	end
	return nil
end

local function joined(id: string, tier: number): string
	return table.concat(EnchantConfig.describe(id, tier), ", ")
end

-- An enchant's main effect at `tier` in short, for the narrow slot cards:
-- "+20% damage", "+15% ore luck", "+4 studs range" (ShortLabels, ShortOrder).
function EnchantView.shortEffect(id: string, tier: number): string
	local enchant = EnchantConfig.ById[id]
	if not enchant then
		return ""
	end
	local stat: string? = nil
	for _, candidate in EnchantView.ShortOrder do
		if enchant.Effects[candidate] then
			stat = candidate
			break
		end
	end
	if stat == nil then
		return EnchantConfig.describe(id, tier)[1] or ""
	end
	local text = StatConfig.describe(stat, EnchantConfig.value(id, stat, tier))
	local info = StatConfig.ById[stat]
	local short = EnchantView.ShortLabels[stat]
	if short and info and #text > #info.Label and string.sub(text, -#info.Label) == info.Label then
		text = string.sub(text, 1, #text - #info.Label) .. short
	end
	return text
end

-- Every tier's effect, one line each; the owned one is marked.
function EnchantView.tiersText(id: string, owned: number): string
	local lines = {}
	for tier = 1, EnchantConfig.tiers(id) do
		local mark = if tier == owned then "  (yours)" else ""
		table.insert(lines, `{EnchantView.tierName(tier)}: {joined(id, tier)}{mark}`)
	end
	return table.concat(lines, "\n")
end

-- The buttons of a card (see Buy). Paid random buys are left out where they
-- are restricted; a coming-soon enchant gets one greyed COMING SOON button.
local function buysOf(
	enchant: EnchantConfig.Enchant,
	tier: number,
	coins: number,
	shards: number,
	restricted: boolean,
	soon: boolean
): { Buy }
	local coinPrice, shardPrice, product = EnchantConfig.nextPrice(enchant.Id, tier)
	local nextTier = tier + 1
	if coinPrice == nil then
		return { { Currency = "Max", Text = "TOP TIER", Tier = tier, CanBuy = false, Reason = "Max" } }
	end
	if soon then
		return { { Currency = "Soon", Text = "COMING SOON", Tier = nextTier, CanBuy = false, Reason = "ComingSoon" } }
	end
	local list: { Buy } = {}
	if not (restricted and EnchantConfig.isPaidRandom(enchant.Id, "Coins")) then
		table.insert(list, {
			Currency = "Coins",
			Text = `BUY {Format.money(coinPrice)}`,
			Price = coinPrice,
			Tier = nextTier,
			CanBuy = coins >= coinPrice,
			Reason = if coins >= coinPrice then nil else "NoCoins",
		})
	end
	if shardPrice and not (restricted and EnchantConfig.isPaidRandom(enchant.Id, "Shards")) then
		table.insert(list, {
			Currency = "Shards",
			Text = `{Format.big(shardPrice)} SHARDS`,
			Price = shardPrice,
			Tier = nextTier,
			CanBuy = shards >= shardPrice,
			Reason = if shards >= shardPrice then nil else "NoShards",
		})
	end
	if product and not (restricted and EnchantConfig.isPaidRandom(enchant.Id, "Robux")) then
		local info = MonetizationConfig.get(product)
		local live = MonetizationConfig.keyLive(product)
		-- the pass id is 0 until it's on sale: its price shows, greyed, with SOON
		local text = if info then `{info.Robux} R$` else "COMING SOON"
		if info and not live then
			text ..= " • SOON"
		end
		table.insert(list, {
			Currency = "Robux",
			Text = text,
			Product = product,
			Tier = nextTier,
			CanBuy = live,
			Reason = if live then nil else "ComingSoon",
		})
	end
	return list
end

--[[
	Every enchant card (EnchantConfig.List order: Common first, Mythic
	last) from a State snapshot, the coins on screen and the player's
	paid-random policy (`restricted`: the Robux option of an odds booster
	is left out; coins and shards too while coins can be bought with Robux).
	An id in `soon` (BoostView.soonSet) can't be bought yet: COMING SOON.
]]
function EnchantView.cards(rawState: any, coins: number, restricted: boolean, soon: { [string]: boolean }?): { Card }
	local state = safeState(rawState)
	local soonSet: { [string]: boolean } = soon or {}
	local cash = num(coins, 0)
	local shards = EnchantView.shards(state)
	local enchants = state.Enchants
	local level = levelOf(state)
	local list: { Card } = {}
	for order, enchant in EnchantConfig.List do
		local id = enchant.Id
		local tier = EnchantConfig.tierOf(enchants, id)
		local max = EnchantConfig.tiers(id)
		local done = tier >= max
		local slot = EnchantView.slotOf(enchants, level, id)
		local info = Rarity.get(enchant.Rarity)
		local isSoon = soonSet[id] == true
		local buys = buysOf(enchant, tier, cash, shards, restricted, isSoon)
		local tierText: string
		if tier == 0 then
			tierText = "NEW"
		elseif max == 1 then
			tierText = "OWNED"
		elseif done then
			tierText = "MAX"
		else
			tierText = `{EnchantView.tierName(tier)} / {EnchantView.tierName(max)}`
		end
		-- the list row's line: where it is, or what it costs
		local coinPrice, shardPrice, product = EnchantConfig.nextPrice(id, tier)
		local priceText = if coinPrice then Format.money(coinPrice) else ""
		if shardPrice then
			priceText ..= ` or {Format.big(shardPrice)} shards`
		end
		local robux = if product then MonetizationConfig.get(product) else nil
		if product and robux and not (restricted and EnchantConfig.isPaidRandom(id, "Robux")) then
			-- the pass id is 0 until it's on sale: the Robux price is only a promise
			priceText ..= if MonetizationConfig.keyLive(product) then ` or {robux.Robux} R$` else ` or {robux.Robux} R$ (soon)`
		end
		local line: string
		local lineColor: Color3
		if isSoon and tier == 0 then
			line, lineColor = EnchantView.SoonText[id] or MonetizationConfig.StatusText.ComingSoon, Theme.Info
		elseif tier == 0 then
			line, lineColor = priceText, Theme.Coin
		else
			line = if slot then `In slot {slot}` else "Owned: not in a slot"
			lineColor = if slot then Theme.Good else Theme.Accent
			if not done and coinPrice then
				line ..= `{SEP}next {Format.money(coinPrice)}`
			end
		end
		table.insert(list, {
			Id = id,
			Name = enchant.Name,
			Rarity = enchant.Rarity,
			RarityName = info.Name,
			RarityColor = info.Color,
			Color = enchant.Color,
			Description = enchant.Description,
			Order = order,
			Tier = tier,
			MaxTier = max,
			Owned = tier > 0,
			Done = done,
			Slot = slot,
			TierText = tierText,
			Effect = joined(id, math.max(1, tier)),
			ListLine = line,
			ListLineColor = lineColor,
			Now = if tier > 0 then `Now: {joined(id, tier)}` else "Not owned yet",
			Next = if done
				then "Top tier: nothing more to buy"
				elseif tier == 0 then `Buy: {joined(id, 1)}`
				else `Next: {joined(id, tier + 1)}`,
			Tiers = EnchantView.tiersText(id, tier),
			Buys = buys,
			Odds = enchant.OddsBoost == true,
		})
	end
	return list
end

-- The blaster's enchant slots from a State snapshot (EnchantConfig.MaxSlots of them).
function EnchantView.slotCards(rawState: any): { SlotCard }
	local state = safeState(rawState)
	local level = levelOf(state)
	local open = EnchantConfig.unlockedSlots(level)
	local enchants = state.Enchants
	local slots = if type(enchants) == "table" and type(enchants.Slots) == "table" then enchants.Slots else {}
	local list: { SlotCard } = {}
	for i = 1, EnchantConfig.MaxSlots do
		local need = EnchantConfig.SlotLevels[i] or 1
		local id = slots[i]
		local enchant = if type(id) == "string" then EnchantConfig.ById[id] else nil
		local tier = if enchant then EnchantConfig.tierOf(enchants, enchant.Id) else 0
		if i > open then
			table.insert(
				list,
				{ Index = i, Open = false, Need = need, Name = "LOCKED", Sub = `Blaster level {need}`, Color = Theme.PanelDark }
			)
		elseif enchant and tier > 0 then
			local tierText = if EnchantConfig.tiers(enchant.Id) > 1 then ` {EnchantView.tierName(tier)}` else ""
			table.insert(list, {
				Index = i,
				Open = true,
				Need = need,
				Id = enchant.Id,
				Name = string.upper(enchant.Name) .. tierText,
				Sub = EnchantView.shortEffect(enchant.Id, tier),
				Color = enchant.Color,
			})
		else
			table.insert(list, { Index = i, Open = true, Need = need, Name = "EMPTY", Sub = `Slot {i}`, Color = Theme.PanelLight })
		end
	end
	return list
end

-- The zones an odds table can show (BoostView.zones) as ids.
function EnchantView.zoneIds(rawState: any): { string }
	local ids = {}
	for _, zone in BoostView.zones(rawState) do
		table.insert(ids, zone.Id)
	end
	return ids
end

--[[
	The slotted enchant a buy of `id` would have to replace: nil when `id`
	sits in an open slot or an open slot is free. Else a slotted enchant
	that changes no odds (the first one), or, when every slot holds an odds
	booster, the one that gives the least luck (ore luck + artifact chance).
]]
function EnchantView.replaceTarget(enchants: any, blasterLevel: any, id: string): string?
	if EnchantView.slotOf(enchants, blasterLevel, id) ~= nil or EnchantConfig.firstFreeSlot(enchants, blasterLevel) ~= nil then
		return nil
	end
	local slots = if type(enchants) == "table" then enchants.Slots else nil
	if type(slots) ~= "table" then
		return nil
	end
	local best: string? = nil
	local bestScore = math.huge
	for i = 1, EnchantConfig.unlockedSlots(blasterLevel) do
		local other = slots[i]
		local enchant = if type(other) == "string" then EnchantConfig.ById[other] else nil
		if enchant and enchant.Id ~= id then
			local score = 0
			if enchant.OddsBoost then
				local tier = EnchantConfig.tierOf(enchants, enchant.Id)
				score = 1 + EnchantConfig.value(enchant.Id, "OreLuckPct", tier) + EnchantConfig.value(enchant.Id, "ArtifactPct", tier)
			end
			if score < bestScore then
				best, bestScore = enchant.Id, score
			end
		end
	end
	return best
end

--[[
	The new odds an odds-boosting enchant's next tier gives
	(BoostConfig.preview with EnchantConfig.nextDelta, every total capped
	like the server's), for zone `zoneId` (a zone the player can mine; the
	first one when it isn't). nil for other enchants and at the top tier.
	  luck: "Rare or better" on top, then each lucky rarity of the zone,
	        and the artifact chance per rock when the buy changes it
	  artifacts only (Prospector): one row per zone (no switching)
	The odds are the lasting ones: a running Hexa Lucky (it runs out) is
	left out of NOW and AFTER, and the note says so. The AFTER column is
	"AFTER BUY" when the enchant is in a slot or the buy puts it in one (a
	new enchant goes into the first free open slot), else "IN A SLOT" with
	a note: the luck only counts once it is equipped. With every open slot
	full, AFTER is with the enchant in place of replaceTarget (its luck
	taken out; the note names it), so the numbers can really be reached.
	`soon` (BoostView.soonSet): while EnchantView.ArtifactsWith is in it
	artifacts aren't in the game: the luck table has no artifact row,
	Prospector's table stays as information, and the notes say so.
	Returns the table and whether the zone can be switched.
]]
function EnchantView.odds(
	rawState: any,
	id: string,
	zoneId: string?,
	now: number?,
	soon: { [string]: boolean }?
): (BoostView.OddsTable?, boolean)
	local enchant = EnchantConfig.ById[id]
	if not enchant or not enchant.OddsBoost then
		return nil, false
	end
	local state = safeState(rawState)
	local level = levelOf(state)
	local delta = EnchantConfig.nextDelta(state.Enchants, level, id)
	if next(delta) == nil then
		return nil, false
	end
	local artifactsSoon = soon ~= nil and soon[EnchantView.ArtifactsWith] == true
	-- the lasting odds: without a running Hexa Lucky
	local ctx = BoostView.context(state, now)
	local hexa = ctx.OreLuckMult > 1
	ctx.OreLuckMult = 1
	-- does the buy's effect count right away (in a slot)?
	local tier = EnchantConfig.tierOf(state.Enchants, id)
	local slotted = EnchantView.slotOf(state.Enchants, level, id) ~= nil
	local inSlot = slotted or (tier == 0 and EnchantConfig.firstFreeSlot(state.Enchants, level) ~= nil)
	local afterHeader = if inSlot then "AFTER BUY" else "IN A SLOT"
	-- every open slot full: AFTER is with it in place of the slotted enchant with the least luck
	local replaced = if inSlot then nil else EnchantView.replaceTarget(state.Enchants, level, id)
	local slotNote = ""
	if replaced then
		local other = EnchantConfig.ById[replaced]
		slotNote = ` Every open slot is full: these odds are with it in place of {other.Name}.`
	elseif not inSlot then
		slotNote = if tier > 0
			then " It isn't in a slot: equip it to get these odds."
			else " Every open slot is full: put it in a slot to get these odds."
	end
	local hexaNote = if hexa then " Hexa Lucky isn't counted (it runs out)." else ""
	local preview = BoostConfig.preview(ctx, delta)
	if replaced then
		local replacedTier = EnchantConfig.tierOf(state.Enchants, replaced)
		local without = table.clone(ctx)
		without.OreLuckPct = math.max(0, ctx.OreLuckPct - EnchantConfig.value(replaced, "OreLuckPct", replacedTier))
		without.ArtifactPct = math.max(0, ctx.ArtifactPct - EnchantConfig.value(replaced, "ArtifactPct", replacedTier))
		local swapped = BoostConfig.preview(without, delta)
		local artifacts: { BoostConfig.ArtifactEffect } = {}
		for i, line in preview.Artifacts do
			local after = swapped.Artifacts[i]
			table.insert(artifacts, { Zone = line.Zone, Before = line.Before, After = if after then after.After else line.After })
		end
		preview = {
			LuckBefore = preview.LuckBefore,
			LuckAfter = swapped.LuckAfter,
			Zones = BoostConfig.zoneEffects(level, ctx.Vip, preview.LuckBefore, swapped.LuckAfter),
			Artifacts = artifacts,
		}
	end
	local luck = (delta.OreLuckPct or 0) > 0 or (delta.OreLuckMult or 1) > 1
	local artifacts = (delta.ArtifactPct or 0) > 0 and not artifactsSoon
	local artifactName = "Artifact"
	local rows: { BoostView.OddsRow } = {}
	if not luck then
		for _, line in preview.Artifacts do
			local zone = WorldLayout.ZoneById[line.Zone]
			table.insert(rows, BoostView.row(if zone then zone.Name else line.Zone, Theme.Text, line.Before, line.After))
		end
		local art = math.floor(ctx.ArtifactPct * 100 + 0.5)
		local note = `Your artifact bonus now: +{art}%. Every zone you can mine.`
		if artifactsSoon then
			note = "Artifacts are coming soon: these will be the odds then. Every zone you can mine."
		end
		return {
			Title = "ARTIFACT CHANCE",
			Header = "PER ROCK YOU BREAK",
			BeforeHeader = "NOW",
			AfterHeader = afterHeader,
			Summary = nil,
			Rows = rows,
			Note = note .. slotNote,
		},
			false
	end
	local effect: BoostConfig.ZoneEffect? = nil
	for _, line in preview.Zones do
		if line.Zone == zoneId then
			effect = line
		end
	end
	effect = effect or preview.Zones[1]
	local summary: BoostView.OddsRow? = nil
	local title = "No zone"
	local zoneKey = ""
	if effect then
		zoneKey = effect.Zone
		local zone = WorldLayout.ZoneById[effect.Zone]
		title = if zone then zone.Name else effect.Zone
		for _, line in effect.Rarities do
			local info = Rarity.get(line.Rarity)
			table.insert(rows, BoostView.row(info.Name, info.Color, line.Before, line.After))
		end
		if not effect.NoEffect then
			summary = BoostView.row("Rare or better", Rarity.get("Rare").Color, effect.Before, effect.After)
		end
	end
	if artifacts then
		for _, line in preview.Artifacts do
			if line.Zone == zoneKey then
				table.insert(rows, BoostView.row(artifactName, Theme.Accent, line.Before, line.After))
			end
		end
	end
	local note =
		`Ore luck {BoostView.mult(preview.LuckBefore)} → {BoostView.mult(preview.LuckAfter)}: chance of each rarity for every ore chunk you mine.`
	if math.abs(preview.LuckAfter - preview.LuckBefore) <= 1e-9 then
		note = if preview.LuckBefore >= StatConfig.MaxOreLuck - 1e-9
			then `Your ore luck is at its cap ({BoostView.mult(StatConfig.MaxOreLuck)}): this buy doesn't change it.`
			else "Your ore luck from enchants and golems is at its cap: this buy doesn't change it."
	elseif effect and effect.NoEffect then
		note = "No Rare ores in this zone: ore luck changes nothing here."
	end
	local soonNote = if artifactsSoon and (delta.ArtifactPct or 0) > 0 then " Artifacts: coming soon." else ""
	return {
		Title = title,
		Header = "CHANCE",
		BeforeHeader = "NOW",
		AfterHeader = afterHeader,
		Summary = summary,
		Rows = rows,
		Note = note .. slotNote .. hexaNote .. soonNote,
	},
		true
end

-- The text for a reason code.
function EnchantView.reasonText(reason: string?): string
	if reason == "ComingSoon" then
		return MonetizationConfig.StatusText.ComingSoon
	end
	local text = if reason then EnchantConfig.Reasons[reason] else nil
	return text or "You can't buy that right now"
end

---------------------------------------------------------------- the rune icon

--[[
	A rune: a diamond in the enchant's color with its first letter (`size`
	design units). Mythic runes get a bright ring.
]]
function EnchantView.rune(parent: Instance, size: number, color: Color3, letter: string, mythic: boolean?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Rune",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, parent)
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		Rotation = 45,
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
	}, holder)
	UIKit.corner(ring, 6)
	local stone = UIKit.new("Frame", {
		Name = "Stone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		Rotation = 45,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, holder)
	UIKit.corner(stone, 5)
	UIKit.gradient(stone, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	local glow = UIKit.new("UIStroke", {
		Name = "Glow",
		Thickness = 2,
		Color = Color3.fromRGB(255, 240, 200),
		Transparency = if mythic then 0 else 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, ring)
	glow.Enabled = mythic == true
	UIKit.label(holder, letter, 20, {
		Name = "Letter",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextScaled = true,
		TextWrapped = false,
	})
	local pad = UIKit.new("UIPadding", {}, holder:FindFirstChild("Letter") :: Instance)
	local inset = UDim.new(0.26, 0)
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = inset, inset, inset, inset
	return holder
end

-- Recolors a rune.
function EnchantView.setRune(rune: Frame, color: Color3, letter: string, mythic: boolean?)
	local stone = rune:FindFirstChild("Stone") :: Frame?
	if stone then
		stone.BackgroundColor3 = color
	end
	local label = rune:FindFirstChild("Letter") :: TextLabel?
	if label then
		label.Text = letter
	end
	local ring = rune:FindFirstChild("Ring") :: Frame?
	local glow = if ring then ring:FindFirstChild("Glow") :: UIStroke? else nil
	if glow then
		glow.Enabled = mythic == true
		glow.Transparency = if mythic then 0 else 1
	end
end

---------------------------------------------------------------- building

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Footer: number,
	Left: number,
	SlotLabel: number,
	SlotHeight: number,
	SlotRune: number,
	SlotName: number,
	SlotSub: number,
	Row: number,
	RowRune: number,
	RowName: number,
	RowEffect: number,
	RowLine: number,
	RowNameY: number, -- the row's three lines: name (+ tier), effect, slot / price
	RowEffectY: number,
	RowLineY: number,
	Group: number,
	DetailRune: number,
	Name: number,
	Chip: number,
	Description: number,
	Line: number,
	Tiers: number,
	Button: number,
	ButtonText: number,
	Status: number,
	Close: number,
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 1200,
		Height = 600,
		Header = 76,
		Footer = 30,
		Left = 380,
		SlotLabel = 26,
		SlotHeight = 56,
		SlotRune = 32,
		SlotName = 17,
		SlotSub = 13,
		Row = 74,
		RowRune = 40,
		RowName = 20,
		RowEffect = 15,
		RowLine = 15,
		RowNameY = 5,
		RowEffectY = 30,
		RowLineY = 50,
		Group = 26,
		DetailRune = 56,
		Name = 28,
		Chip = 24,
		Description = 17,
		Line = 18,
		Tiers = 17,
		Button = 54,
		ButtonText = 20,
		Status = 18,
		Close = 54,
	},
	-- phones and TVs: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1240,
		Height = 580,
		Header = 64,
		Footer = 6,
		Left = 360,
		SlotLabel = 28,
		SlotHeight = 72,
		SlotRune = 38,
		SlotName = 19,
		SlotSub = 15,
		Row = 86,
		RowRune = 46,
		RowName = 22,
		RowEffect = 17,
		RowLine = 17,
		RowNameY = 7,
		RowEffectY = 35,
		RowLineY = 59,
		Group = 30,
		DetailRune = 56,
		Name = 28,
		Chip = 28,
		Description = 19,
		Line = 20,
		Tiers = 19,
		Button = 72,
		ButtonText = 22,
		Status = 20,
		Close = 72,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

local holderOf = BoostView.holderOf

local function newSlot(parent: Instance, index: number): SlotRefs
	local button = UIKit.button(parent, "", Theme.PanelLight, Theme.PanelDark, { Name = "Slot" .. index })
	local rune = EnchantView.rune(button, 32, Theme.PanelLight, "", false)
	rune.AnchorPoint = Vector2.new(0, 0.5)
	local name = UIKit.label(button, "EMPTY", 17, {
		Name = "SlotName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local sub = UIKit.label(button, "", 13, {
		Name = "SlotSub",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return { Button = button, Rune = rune, Name = name, Sub = sub }
end

local function newRow(list: ScrollingFrame, enchant: EnchantConfig.Enchant, order: number): RowRefs
	local button = UIKit.new("TextButton", {
		Name = enchant.Id,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, list)
	UIKit.corner(button, 10)
	UIKit.stroke(button, 2.5)
	local rune = EnchantView.rune(button, 40, enchant.Color, enchant.Name:sub(1, 1), enchant.Rarity == "Mythic")
	rune.AnchorPoint = Vector2.new(0, 0.5)
	local name = UIKit.label(button, string.upper(enchant.Name), 20, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local tier = UIKit.label(button, "", 16, {
		Name = "Tier",
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local effect = UIKit.label(button, "", 15, {
		Name = "Effect",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = UIKit.label(button, "", 15, {
		Name = "Line",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return { Id = enchant.Id, Button = button, Rune = rune, Name = name, Tier = tier, Effect = effect, Line = line }
end

function EnchantView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeEnchants", 15)
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
	local title = UIKit.label(panel, "ENCHANTS", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, "Perks for your blaster. Owned forever; swapping slots is free.", 16, {
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
	-- crystal shards (a cyan crystal + the number)
	local shardBalance = UIKit.new("Frame", {
		Name = "Shards",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(shardBalance, 10)
	UIKit.stroke(shardBalance, 2)
	local crystal = UIKit.new("Frame", {
		Name = "Crystal",
		Position = UDim2.fromOffset(13, 11),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = EnchantView.ShardColor,
		BorderSizePixel = 0,
	}, shardBalance)
	UIKit.corner(crystal, 3)
	UIKit.stroke(crystal, 2)
	local shardAmount = UIKit.label(shardBalance, "0", 22, {
		Name = "Amount",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -46, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = EnchantView.ShardColor,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- the slots
	local slotLabel = UIKit.label(panel, "YOUR BLASTER", 18, {
		Name = "SlotLabel",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local slots: { SlotRefs } = {}
	for i = 1, EnchantConfig.MaxSlots do
		table.insert(slots, newSlot(panel, i))
	end

	-- the catalog
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
	}, panel)
	UIKit.list(list, Enum.FillDirection.Vertical, 6)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 2) }, list)
	local groups: { [string]: TextLabel } = {}
	local rows: { [string]: RowRefs } = {}
	local rowList: { RowRefs } = {}
	local order = 0
	local lastRarity = ""
	for _, enchant in EnchantConfig.List do
		if enchant.Rarity ~= lastRarity then
			lastRarity = enchant.Rarity
			order += 1
			local info = Rarity.get(enchant.Rarity)
			groups[enchant.Rarity] = UIKit.label(list, string.upper(info.Name), 18, {
				Name = "Group" .. info.Id,
				LayoutOrder = order,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				FontFace = Theme.TitleFont,
				TextColor3 = info.Color,
				TextWrapped = false,
			})
		end
		order += 1
		local row = newRow(list, enchant, order)
		rows[enchant.Id] = row
		table.insert(rowList, row)
	end

	-- the detail pane
	local detailFrame = UIKit.new("Frame", {
		Name = "Detail",
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(detailFrame, 12)
	UIKit.stroke(detailFrame, 2.5)
	local first = EnchantConfig.List[1]
	local detailRune = EnchantView.rune(detailFrame, 56, first.Color, first.Name:sub(1, 1), false)
	local detailName = UIKit.label(detailFrame, "", 28, {
		Name = "EnchantName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local rarityChip = UIKit.chip(detailFrame, "", Theme.PanelDark, { Name = "RarityChip" })
	local tierChip = UIKit.chip(detailFrame, "", Theme.PanelDark, { Name = "TierChip" })
	local body = UIKit.new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, detailFrame)
	UIKit.list(body, Enum.FillDirection.Vertical, 6)
	local description = UIKit.label(body, "", 17, {
		Name = "Description",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local nowLine = UIKit.label(body, "", 18, {
		Name = "Now",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local nextLine = UIKit.label(body, "", 18, {
		Name = "Next",
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Accent,
	})
	local oddsNote = UIKit.label(body, "", 17, {
		Name = "OddsNote",
		LayoutOrder = 4,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Info,
	})
	local odds = BoostView.buildTable(body, true)
	odds.Frame.LayoutOrder = 5
	local tiersBox = UIKit.new("Frame", {
		Name = "TiersBox",
		LayoutOrder = 6,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, body)
	UIKit.corner(tiersBox, 12)
	UIKit.stroke(tiersBox, 2.5)
	local tiersTitle = UIKit.label(tiersBox, "ALL TIERS", 20, {
		Name = "TiersTitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local tiers = UIKit.label(tiersBox, "", 17, {
		Name = "Tiers",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local status = UIKit.label(detailFrame, "", 18, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local buttons: { TextButton } = {}
	for i = 1, 3 do
		table.insert(buttons, UIKit.button(detailFrame, "BUY", Theme.Accent, Theme.AccentDark, { Name = "Buy" .. i, TextSize = 20 }))
	end
	local equip = UIKit.button(detailFrame, "EQUIP", Theme.Info, Color3.fromRGB(40, 100, 170), { Name = "Equip", TextSize = 20 })

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local padHint, padGlyphs = BoostView.padHint(panel, {
		{ Glyphs = 1, Word = "pick / buy", Width = 90 },
		{ Glyphs = 1, Word = "close", Width = 52 },
		{ Glyphs = 1, Word = "scroll", Width = 56 },
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		Balance = balance,
		BalanceAmount = balanceAmount,
		ShardBalance = shardBalance,
		ShardAmount = shardAmount,
		Close = close,
		SlotLabel = slotLabel,
		Slots = slots,
		List = list,
		Groups = groups,
		Rows = rows,
		RowList = rowList,
		Detail = {
			Frame = detailFrame,
			Rune = detailRune,
			Name = detailName,
			RarityChip = rarityChip,
			TierChip = tierChip,
			Body = body,
			Description = description,
			Now = nowLine,
			Next = nextLine,
			OddsNote = oddsNote,
			Odds = odds,
			TiersBox = tiersBox,
			TiersTitle = tiersTitle,
			Tiers = tiers,
			Status = status,
			Buttons = buttons,
			Equip = equip,
		},
		Hint = hint,
		PadHint = padHint,
		PadGlyphs = padGlyphs,
		PadMode = false,
		Selected = first.Id,
		Compact = compact == true,
		BodyWidth = 0,
		Wide = false,
		RightWidth = 0,
		RightHeight = 0,
		MaxWidth = math.huge,
		MaxHeight = math.huge,
	}
	EnchantView.layout(refs, refs.Compact, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

--[[
	Sizes everything for the normal or compact (phone / TV) layout and fits
	the panel into `maxWidth` x `maxHeight` design units (math.huge = no
	limit); like the Tech shop it moves below the HUD coins when there is room.
]]
function EnchantView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	refs.MaxWidth = maxWidth
	refs.MaxHeight = maxHeight
	local m = metrics(compact)
	local width = math.max(720, math.min(m.Width, maxWidth - 24))
	local height = math.max(EnchantView.MinHeight, math.min(m.Height, maxHeight - 16))
	if maxWidth < 1e6 and maxHeight < 1e6 then
		local left = (maxWidth - width) / 2
		local top = (maxHeight - height) / 2
		if left < 16 + 236 and top < EnchantView.CoinsBottom then
			local below = maxHeight - EnchantView.CoinsBottom - 8
			if below >= (if compact then height else EnchantView.MinHeight) then
				height = math.min(height, below)
				top = EnchantView.CoinsBottom + (below - height) / 2
			end
		end
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0)
		refs.Panel.Position = UDim2.new(0.5, 0, 0, math.max(0, top))
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	refs.Panel.Size = UDim2.fromOffset(width, height)

	-- header: title (+ subtitle / message), coins, shards, X
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, if compact then 6 else 12)
	local balanceWidth = if compact then 190 else 176
	local shardWidth = if compact then 150 else 132
	refs.Balance.Size = UDim2.fromOffset(balanceWidth, 40)
	refs.Balance.Position = UDim2.new(1, -(PAD + m.Close + 12), 0, if compact then 14 else 16)
	refs.ShardBalance.Size = UDim2.fromOffset(shardWidth, 40)
	refs.ShardBalance.Position = UDim2.new(1, -(PAD + m.Close + 12 + balanceWidth + 10), 0, if compact then 14 else 16)
	local headRight = PAD + m.Close + 12 + balanceWidth + 10 + shardWidth + 12
	refs.Title.TextSize = if compact then 30 else 34
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 10 else 6)
	refs.Title.Size = UDim2.new(1, -(PAD + headRight), 0, 40)
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 46)
	refs.Subtitle.Size = UDim2.new(1, -(PAD + headRight), 0, 22)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	if compact then
		local titleWidth = 230
		refs.Title.Size = UDim2.fromOffset(titleWidth, 40)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth, 4)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + headRight), 0, 56)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
	else
		refs.Receipt.Position = UDim2.fromOffset(PAD, 46)
		refs.Receipt.Size = UDim2.new(1, -(PAD + headRight), 0, 24)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
	end

	-- left column: YOUR BLASTER + the 2 x 2 slots, then the catalog
	local top = m.Header
	local bodyHeight = height - top - BoostView.footerHeight(compact, refs.PadMode, m.Footer) - 8
	local left = math.min(m.Left, math.floor((width - PAD * 2 - 12) * 0.42))
	refs.SlotLabel.TextSize = if compact then 20 else 18
	refs.SlotLabel.Position = UDim2.fromOffset(PAD + 2, top)
	refs.SlotLabel.Size = UDim2.fromOffset(left, m.SlotLabel)
	local slotTop = top + m.SlotLabel + 4
	local slotWidth = (left - GAP) / 2
	for i, slot in refs.Slots do
		local holder = holderOf(slot.Button)
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		-- the face sits 5 units above its lip
		holder.Position = UDim2.fromOffset(PAD + col * (slotWidth + GAP), slotTop + 5 + row * (m.SlotHeight + GAP))
		holder.Size = UDim2.fromOffset(slotWidth, m.SlotHeight)
		slot.Rune.Size = UDim2.fromOffset(m.SlotRune, m.SlotRune)
		slot.Rune.Position = UDim2.new(0, 8, 0.5, 0)
		local textLeft = 8 + m.SlotRune + 8
		-- (a locked slot has no rune: its texts start at the left)
		local x = if slot.Rune.Visible then textLeft else 10
		slot.Name.TextSize = m.SlotName
		slot.Name.Position = UDim2.fromOffset(x, if compact then 10 else 6)
		slot.Name.Size = UDim2.new(1, -(textLeft + 6), 0, m.SlotName + 6)
		slot.Sub.TextSize = m.SlotSub
		slot.Sub.Position = UDim2.fromOffset(x, if compact then 38 else 30)
		slot.Sub.Size = UDim2.new(1, -(textLeft + 6), 0, m.SlotSub + 6)
		EnchantView.fitSlot(refs, slot)
	end
	local listTop = slotTop + 5 + 2 * m.SlotHeight + GAP + 10
	refs.List.Position = UDim2.fromOffset(PAD, listTop)
	refs.List.Size = UDim2.fromOffset(left, math.max(m.Row, top + bodyHeight - listTop))
	for _, label in refs.Groups do
		label.Size = UDim2.new(1, -(SCROLLBAR + 4), 0, m.Group)
		label.TextSize = if compact then 20 else 18
	end
	for _, row in refs.RowList do
		row.Button.Size = UDim2.new(1, -(SCROLLBAR + 6), 0, m.Row)
		row.Rune.Size = UDim2.fromOffset(m.RowRune, m.RowRune)
		row.Rune.Position = UDim2.new(0, 8, 0.5, 0)
		local textLeft = 8 + m.RowRune + 10
		row.Name.TextSize = m.RowName
		row.Name.Position = UDim2.fromOffset(textLeft, m.RowNameY)
		row.Name.Size = UDim2.new(1, -(textLeft + 96), 0, m.RowName + 6)
		row.Tier.TextSize = if compact then 18 else 16
		row.Tier.Position = UDim2.new(1, -10, 0, m.RowNameY)
		row.Tier.Size = UDim2.fromOffset(86, m.RowName + 6)
		row.Effect.Position = UDim2.fromOffset(textLeft, m.RowEffectY)
		row.Effect.Size = UDim2.new(1, -(textLeft + 10), 0, m.RowEffect + 4)
		EnchantView.fitRowEffect(refs, row)
		row.Line.TextSize = m.RowLine
		row.Line.Position = UDim2.fromOffset(textLeft, m.RowLineY)
		row.Line.Size = UDim2.new(1, -(textLeft + 10), 0, m.RowLine + 4)
	end

	-- right: the detail pane
	local d = refs.Detail
	local detailLeft = PAD + left + 12
	local detailWidth = width - detailLeft - PAD
	d.Frame.Position = UDim2.fromOffset(detailLeft, top)
	d.Frame.Size = UDim2.fromOffset(detailWidth, bodyHeight)
	-- wide (PC, TV): info left, the odds / tiers column right at full height;
	-- narrow (phones): one scrolling column with everything
	local wide = detailWidth >= EnchantView.WideDetail
	refs.Wide = wide
	local infoWidth = if wide then math.clamp(math.floor(detailWidth * (if compact then 0.36 else 0.4)), 250, 330) else detailWidth - 24
	d.Rune.Size = UDim2.fromOffset(m.DetailRune, m.DetailRune)
	d.Rune.Position = UDim2.fromOffset(12, 10)
	local textLeft = 12 + m.DetailRune + 12
	d.Name.TextSize = m.Name
	d.Name.Position = UDim2.fromOffset(textLeft, 6)
	d.Name.Size = UDim2.fromOffset(12 + infoWidth - textLeft, 34)
	local chipWidth = math.min(if compact then 130 else 112, (12 + infoWidth - textLeft - 8) / 2)
	d.RarityChip.Position = UDim2.fromOffset(textLeft, 42)
	d.RarityChip.Size = UDim2.fromOffset(chipWidth, m.Chip)
	d.RarityChip.TextSize = if compact then 17 else 15
	d.TierChip.Position = UDim2.fromOffset(textLeft + chipWidth + 8, 42)
	d.TierChip.Size = UDim2.fromOffset(chipWidth, m.Chip)
	d.TierChip.TextSize = d.RarityChip.TextSize
	local headTop = math.max(10 + m.DetailRune, 42 + m.Chip) + 8
	-- the buttons at the bottom (the face sits 5 above its lip), the status line over them
	local buttonsTop = bodyHeight - m.Button - 10
	local statusTop = buttonsTop - m.Status - 14
	d.Status.TextSize = m.Status
	d.Status.Position = UDim2.fromOffset(12, statusTop)
	d.Status.Size = UDim2.new(1, -24, 0, m.Status + 8)
	for _, button in d.Buttons do
		holderOf(button).Position = UDim2.fromOffset(12, buttonsTop)
		holderOf(button).Size = UDim2.fromOffset(120, m.Button)
		button.TextSize = m.ButtonText
	end
	holderOf(d.Equip).Position = UDim2.fromOffset(12, buttonsTop)
	holderOf(d.Equip).Size = UDim2.fromOffset(120, m.Button)
	d.Equip.TextSize = m.ButtonText
	d.Body.Position = UDim2.fromOffset(12, headTop)
	d.Body.Size = UDim2.fromOffset(infoWidth, math.max(40, statusTop - headTop - 4))
	refs.BodyWidth = infoWidth - (if wide then 4 else SCROLLBAR + 4)
	refs.RightWidth = if wide then detailWidth - infoWidth - 36 else refs.BodyWidth
	refs.RightHeight = if wide then statusTop - 4 - 10 else 0
	-- the odds table and the tiers box move between the column and the scroll
	-- (narrow: the new odds come first, before the description)
	for _, frame in { d.Odds.Frame, d.TiersBox } do
		if wide then
			frame.Parent = d.Frame
			frame.Position = UDim2.fromOffset(12 + infoWidth + 12, 10)
		else
			frame.Parent = d.Body
			frame.Position = UDim2.new()
		end
	end
	d.Odds.Frame.LayoutOrder = if wide then 5 else 0
	-- narrow: what the buy gives comes first (one short line), then the new odds
	d.Next.LayoutOrder = if wide then 3 else -1
	d.Description.TextSize = m.Description
	d.Now.TextSize = m.Line
	d.Next.TextSize = m.Line
	d.OddsNote.TextSize = m.Description
	d.Tiers.TextSize = m.Tiers
	d.TiersTitle.TextSize = if compact then 22 else 20
	EnchantView.placeButtons(refs)
	EnchantView.placeBody(refs)
	-- texts fitted to the old sizes are fitted again (setHint lays the panel out again)
	TechShopView.fitText(d.Name, d.Name.Size.X.Offset, 34, m.Name, 18)
	if d.Status.Text ~= "" then
		TechShopView.fitText(d.Status, refs.BodyWidth, m.Status + 8, m.Status, 13)
	else
		d.Status.TextSize = m.Status
	end

	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, -4)
	BoostView.showHint(refs.Hint, refs.PadHint, compact, refs.PadMode)
end

-- Spreads the shown buttons (buys, then EQUIP) over the bottom row.
function EnchantView.placeButtons(refs: Refs)
	local d = refs.Detail
	local shown: { TextButton } = {}
	for _, button in d.Buttons do
		if holderOf(button).Visible then
			table.insert(shown, button)
		end
	end
	if holderOf(d.Equip).Visible then
		table.insert(shown, d.Equip)
	end
	local width = refs.Detail.Frame.Size.X.Offset - 24
	local n = math.max(1, #shown)
	local each = math.min(260, (width - GAP * (n - 1)) / n)
	for i, button in shown do
		local holder = holderOf(button)
		holder.Size = UDim2.fromOffset(each, holder.Size.Y.Offset)
		holder.Position = UDim2.fromOffset(12 + (i - 1) * (each + GAP), holder.Position.Y.Offset)
		TechShopView.fitText(button :: any, each - 12, holder.Size.Y.Offset - 8, metrics(refs.Compact).ButtonText, 14)
	end
end

--[[
	Sizes the detail's middle from its texts (word-wrap guesses:
	TechShopView.textLines): the info column (description, now, next, the
	odds note) and the odds table or the tiers box, in the right column
	(wide, at its full height) or under the info in the scroll (narrow, at
	the height they need: the table never scrolls inside the scroll).
]]
function EnchantView.placeBody(refs: Refs)
	local d = refs.Detail
	local width = math.max(100, refs.BodyWidth)
	local m = metrics(refs.Compact)
	local function size(label: TextLabel, textSize: number, w: number): number
		local lines = if label.Text == "" then 0 else TechShopView.textLines(label.Text, w, textSize)
		local height = math.ceil(lines * textSize * TechShopView.LineHeight) + 2
		label.Size = UDim2.fromOffset(w, height)
		label.Visible = lines > 0
		return height
	end
	size(d.Description, m.Description, width)
	size(d.Now, m.Line, width)
	size(d.Next, m.Line, width)
	size(d.OddsNote, m.Description, width)
	local right = math.max(100, refs.RightWidth)
	if d.Odds.Frame.Visible then
		local rows = 0
		for _, row in d.Odds.Rows do
			if row.Frame.Visible then
				rows += 1
			end
		end
		local data = d.Odds.Data
		local height = if refs.Wide
			then refs.RightHeight
			else BoostView.tableHeight(rows, refs.Compact, d.Odds.CanSwitch, false, data ~= nil and data.Summary ~= nil)
		BoostView.layoutTable(d.Odds, right, height, refs.Compact, false)
	end
	if d.TiersBox.Visible then
		d.TiersTitle.Position = UDim2.fromOffset(12, 8)
		d.TiersTitle.Size = UDim2.fromOffset(right - 24, 28)
		d.Tiers.Position = UDim2.fromOffset(12, 42)
		local textHeight = size(d.Tiers, m.Tiers, right - 24)
		d.Tiers.Visible = true
		d.TiersBox.Size = UDim2.fromOffset(right, if refs.Wide then refs.RightHeight else 42 + textHeight + 10)
	end
end

---------------------------------------------------------------- filling in

local style = BoostView.style
EnchantView.style = style

local function buyColors(currency: string): (Color3, Color3)
	if currency == "Robux" then
		return Theme.Good, Theme.GoodDark
	elseif currency == "Shards" then
		return Color3.fromRGB(70, 170, 220), Color3.fromRGB(30, 100, 150)
	end
	return Theme.Accent, Theme.AccentDark
end

-- Fills the slots from EnchantView.slotCards; `picking` (an enchant id) marks the open slots as targets.
function EnchantView.setSlots(refs: Refs, slots: { SlotCard }, blasterLevel: number, picking: string?)
	local open = EnchantConfig.unlockedSlots(blasterLevel)
	refs.SlotLabel.Text = `YOUR BLASTER{SEP}LEVEL {math.floor(blasterLevel)}{SEP}{open} OF {EnchantConfig.MaxSlots} SLOTS`
	TechShopView.fitText(refs.SlotLabel, refs.SlotLabel.Size.X.Offset, refs.SlotLabel.Size.Y.Offset, refs.SlotLabel.TextSize, 13)
	for i, slotRefs in refs.Slots do
		local card = slots[i]
		if card then
			slotRefs.Name.Text = card.Name
			slotRefs.Sub.Text = card.Sub
			local enchant = if card.Id then EnchantConfig.ById[card.Id] else nil
			EnchantView.setRune(
				slotRefs.Rune,
				card.Color,
				if enchant then enchant.Name:sub(1, 1) else "",
				enchant ~= nil and enchant.Rarity == "Mythic"
			)
			slotRefs.Rune.Visible = card.Open
			local target = picking ~= nil and card.Open
			if target then
				style(slotRefs.Button, true, Theme.Accent, Theme.AccentDark)
			else
				style(slotRefs.Button, card.Open, Theme.PanelLight, Theme.PanelDark)
			end
			slotRefs.Name.TextColor3 = if card.Open then Theme.Text else Theme.TextDim
			local textLeft = 8 + slotRefs.Rune.Size.X.Offset + 8
			local x = if card.Open then textLeft else 10
			slotRefs.Name.Position = UDim2.fromOffset(x, slotRefs.Name.Position.Y.Offset)
			slotRefs.Sub.Position = UDim2.fromOffset(x, slotRefs.Sub.Position.Y.Offset)
			EnchantView.fitSlot(refs, slotRefs)
		end
	end
end

-- A slot's texts get smaller instead of being cut (layout and setSlots).
function EnchantView.fitSlot(refs: Refs, slotRefs: SlotRefs)
	local m = metrics(refs.Compact)
	local room = holderOf(slotRefs.Button).Size.X.Offset - slotRefs.Name.Position.X.Offset - 6
	TechShopView.fitText(slotRefs.Name, room, m.SlotName + 6, m.SlotName, 12)
	TechShopView.fitText(slotRefs.Sub, room, m.SlotSub + 6, m.SlotSub, 10)
end

-- A catalog row's effect line gets a little smaller before it is cut ("…").
function EnchantView.fitRowEffect(refs: Refs, row: RowRefs)
	local m = metrics(refs.Compact)
	-- the row: the list's width less its scroll bar room and padding
	local room = refs.List.Size.X.Offset - (SCROLLBAR + 6) - 2 - row.Effect.Position.X.Offset - 10
	TechShopView.fitText(row.Effect, room, m.RowEffect + 4, m.RowEffect, m.RowEffect - 3)
end

-- Fills the catalog rows; the `selected` row is outlined.
function EnchantView.setRows(refs: Refs, cards: { Card }, selected: string)
	for _, card in cards do
		local row = refs.Rows[card.Id]
		if row then
			row.Tier.Text = card.TierText
			row.Tier.TextColor3 = if card.Done then Theme.Good elseif card.Owned then Theme.Accent else Theme.Info
			row.Effect.Text = card.Effect
			EnchantView.fitRowEffect(refs, row)
			row.Line.Text = card.ListLine
			row.Line.TextColor3 = card.ListLineColor
			local on = card.Id == selected
			row.Button.BackgroundColor3 = if on then Theme.Panel else Theme.PanelLight
			local stroke = row.Button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if on then Theme.Accent else Theme.Outline
				stroke.Thickness = if on then 3.5 else 2.5
			end
		end
	end
end

--[[
	Fills the detail pane for `card` (its odds table `odds` for an odds
	booster, nil otherwise; `canSwitch`: the zone arrows show). Buttons that
	show an answer (Busy) keep their text.
]]
function EnchantView.setDetail(refs: Refs, card: Card, odds: BoostView.OddsTable?, canSwitch: boolean)
	refs.Selected = card.Id
	local d = refs.Detail
	EnchantView.setRune(d.Rune, card.Color, card.Name:sub(1, 1), card.Rarity == "Mythic")
	d.Name.Text = string.upper(card.Name)
	d.RarityChip.Text = string.upper(card.RarityName)
	d.RarityChip.BackgroundColor3 = card.RarityColor
	d.TierChip.Text = card.TierText
	d.TierChip.BackgroundColor3 = if card.Done then Theme.GoodDark elseif card.Owned then Theme.AccentDark else Theme.PanelDark
	d.Description.Text = card.Description
	d.Now.Text = card.Now
	d.Now.TextColor3 = if card.Owned then Theme.Text else Theme.TextDim
	d.Next.Text = card.Next
	d.Next.TextColor3 = if card.Done then Theme.Good else Theme.Accent
	if odds then
		d.Odds.Frame.Visible = true
		d.TiersBox.Visible = false
		BoostView.setTable(d.Odds, odds, canSwitch)
		d.OddsNote.Text = odds.Note
		d.Tiers.Text = ""
	else
		d.Odds.Frame.Visible = false
		d.TiersBox.Visible = true
		d.OddsNote.Text = ""
		d.Tiers.Text = card.Tiers
	end
	for i, button in d.Buttons do
		local buy = card.Buys[i]
		holderOf(button).Visible = buy ~= nil
		if buy and button:GetAttribute("Busy") ~= true then
			button.Text = buy.Text
			local color, dark = buyColors(buy.Currency)
			if buy.Currency == "Max" then
				style(button, false, Theme.Good, Theme.GoodDark)
				button.TextColor3 = Theme.Good
			else
				style(button, buy.CanBuy, color, dark)
			end
		end
	end
	holderOf(d.Equip).Visible = card.Owned
	if card.Owned and d.Equip:GetAttribute("Busy") ~= true then
		if card.Slot then
			d.Equip.Text = "UNEQUIP"
			style(d.Equip, true, Theme.Bad, Theme.BadDark)
		else
			d.Equip.Text = "EQUIP"
			style(d.Equip, true, Theme.Info, Color3.fromRGB(40, 100, 170))
		end
	end
	EnchantView.placeButtons(refs)
	EnchantView.placeBody(refs)
	local m = metrics(refs.Compact)
	TechShopView.fitText(d.Name, d.Name.Size.X.Offset, 34, m.Name, 18)
end

-- The status line over the buttons: `text` in `color` (nil clears it).
function EnchantView.setStatus(refs: Refs, text: string?, color: Color3?)
	local d = refs.Detail
	d.Status.Text = text or ""
	d.Status.TextColor3 = color or Theme.Text
	if text then
		local m = metrics(refs.Compact)
		TechShopView.fitText(d.Status, refs.BodyWidth, m.Status + 8, m.Status, 13)
	end
end

function EnchantView.setBalances(refs: Refs, coins: number, shards: number)
	refs.BalanceAmount.Text = Format.money(math.max(0, num(coins, 0)))
	refs.ShardAmount.Text = Format.big(math.max(0, math.floor(num(shards, 0))))
end

-- The footer hint: `text`, or with `glyphs` (A, B, right stick images) the
-- gamepad row (also on phones and TVs: it gets a footer of its own there, so
-- the panel is laid out again when the row comes or goes).
function EnchantView.setHint(refs: Refs, text: string, glyphs: { string }?)
	local was = refs.PadMode
	refs.Hint.Text = text
	refs.PadMode = glyphs ~= nil
	if glyphs then
		for i, image in refs.PadGlyphs do
			image.Image = glyphs[i] or ""
		end
	end
	if refs.Compact and was ~= refs.PadMode then
		EnchantView.layout(refs, true, refs.MaxWidth, refs.MaxHeight)
	end
	BoostView.showHint(refs.Hint, refs.PadHint, refs.Compact, refs.PadMode)
end

function EnchantView.showReceipt(refs: Refs, text: string, color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = color
	refs.Receipt.Visible = true
	refs.Subtitle.Visible = false
end

function EnchantView.hideReceipt(refs: Refs)
	refs.Receipt.Visible = false
	refs.Subtitle.Visible = not refs.Compact
end

-- The button a gamepad starts on: the picked catalog row, else the close
-- button; never a buy button (A is also jump: a reflex press right after
-- the prompt must not spend anything).
function EnchantView.firstButton(refs: Refs): GuiObject
	local row = refs.Rows[refs.Selected]
	if row then
		return row.Button
	end
	return refs.Close
end

-- Every button a finger must hit (for the touch-size tests).
function EnchantView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close), holderOf(refs.Detail.Equip) }
	for _, slot in refs.Slots do
		table.insert(list, holderOf(slot.Button))
	end
	for _, row in refs.RowList do
		table.insert(list, row.Button)
	end
	for _, button in refs.Detail.Buttons do
		table.insert(list, holderOf(button))
	end
	table.insert(list, holderOf(refs.Detail.Odds.Prev))
	table.insert(list, holderOf(refs.Detail.Odds.Next))
	return list
end

return EnchantView
