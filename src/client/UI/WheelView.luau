--[[
	The Spin & Win screen and the HUD's FREE SPIN! chip in the bright "Pop"
	look (Pop + Config/PopTheme; the owner's reference wheel, 2026-10-20):
	pure builders, layout math and texts (WheelController fills them in,
	spins the disc and handles input; the Lune preview builds the same views).
	No window frame around the wheel, no emoji anywhere (text only).

	  wheel    centre: a BIG wheel, 8 segments painted bright purple / yellow /
	           pink (FaceColors, clockwise from the top: segment i centred at
	           (i - 1) x 45 degrees), each with its prize name along the
	           radius and its exact chance at the rim. Drawn from rotated bars
	           (Roblox UI has no wedges): every segment is a fan of bars
	           through the centre plus one bar on each edge whose outer side
	           lies ON the edge ray, so no colour spills over a segment edge;
	           black dividers, a thick dark-green leafy rim with yellow studs,
	           a red pointer at the top (a circle and a diamond tip), a dark
	           hub. The whole Disc frame turns (children turn with it);
	           restAngle / spinTarget give the angle that puts a segment under
	           the pointer. The red X sits at the wheel's top right.
	  below    "FREE SPIN IN 13:42:10" / "FREE SPIN READY!" and the big
	           SPIN (n) banner: n = the free spin (1 when ready) + the bought
	           spins held (spinCount); grey while n is 0
	  left     BUY SPINS: a lilac card, three rows (the wheel mark, x1 / x5 /
	           x10, a green Robux price button: WheelConfig.Packs and
	           MonetizationConfig), a blue Details button and the Fast Spin
	           box (a 1.2 s spin instead of 5 s). Where paid random items are
	           restricted the rows hide and a note says so (setBuy).
	  right    the jackpot (WheelConfig.JackpotId, the Crystal Capsule): every
	           golem it can wake as a small tile (its picture, golem_<Kind>,
	           and its exact chance; Triple Lucky as the player has it) and a
	           footer with its chance on the wheel. A click opens its details.
	  details  ALL ODDS (Details / the jackpot): a Pop window over the screen
	           with one row per segment, all 8 in view: its face colour,
	           label and exact chance; on a PC also one line of what it pays
	           THIS player (coins at their income, the ore prize's own odds,
	           the capsule's rarity odds with their Triple Lucky), from rows()
	           (pure, tested). With a full golem inventory the capsule rows,
	           and with a full Ore Pen the ore row, start with what they pay
	           instead ("Golem inventory full: pays $X coins instead",
	           fullNote: the real fallback amounts), on the BUY step too. Phones and TVs (compact) show the rows as a
	           2 x 4 grid of 72-unit tiles. Every row is a button: its details
	           card covers the window's body (the whole text and, for a
	           capsule, the exact chance of EVERY golem in it); X / B / the row
	           again close it. A "more below" note shows whenever the list is
	           longer than its box.
	  result   the prize card over the lower half of the wheel ("YOU WON!": the
	           won segment stays in view under the pointer) with an OK button
	           and confetti pieces the controller lets fall
	  chip     its own ScreenGui: "FREE SPIN!" (a painted orange button, the
	           drawn wheel mark, no emoji) in the HUD's top row, right of the
	           quick-teleport bar (TeleportView's width for this uiScale and
	           screen width: icon-only under TeleportView.NarrowWidth), only
	           while the free spin is ready and the touch tutorial bubble
	           isn't in that same spot (chipVisible)

	Designed for 720 design units of height (HudController scales every
	TerraForge gui); `compact` (phones, TVs) has 72-unit buttons (44 pt at
	uiScale 0.62) and bigger texts, and layout() fits everything on screens
	down to a 568 x 320 pt phone (smaller wheel, smaller jackpot tiles; on a
	screen too narrow for both side cards the jackpot hides: Details lists
	it). The LightSkin wrap is off for this screen (it would recolour the Pop
	faces); TouchControls.follow hides Roblox's touch controls while it is open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local IconAssets = require(Shared.Config.IconAssets)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local OreData = require(Shared.Config.OreData)
local PopTheme = require(Shared.Config.PopTheme)
local Rarity = require(Shared.Config.Rarity)
local WheelConfig = require(Shared.Config.WheelConfig)
local Format = require(Shared.Util.Format)
local TeleportView = require(script.Parent.TeleportView)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

local WheelView = {}

type Segment = WheelConfig.Segment

-- One item of a row's own odds list (a capsule's golems).
export type Line = { Name: string, Chance: string, Color: Color3, Golem: string? }
export type Row = { Id: string, Label: string, Detail: string, Chance: string, Color: Color3, Lines: { Line }? }

-- What rows() needs to know about the player (WheelController reads the State).
export type Info = {
	NoCapsules: boolean,
	Income: number, -- podium income per second (State.Income)
	Ore: WheelConfig.OreContext,
	TripleLucky: boolean,
	-- what a prize pays when there is no room (the rows say so before any spin
	-- or buy; nil: not known, no note)
	GolemRoom: number?, -- free golem inventory places (GolemConfig.room)
	PenFull: boolean?, -- the Ore Pen can't take one more item (PenService.refusal)
	PriceLevel: number?, -- BlasterData.priceLevel: the capsule fallback coins
	SellMult: number?, -- the player's sell bonus (Bonuses SellMult): the ore fallback coins
}

-- A BUY SPINS row: its frame, the count label and the Robux price button.
export type BuyRow = { Count: number, Product: string, Frame: Frame, Label: TextLabel, Button: TextButton }

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Title: TextLabel,
	Close: TextButton,
	Rays: Frame,
	WheelBox: Frame,
	Disc: Frame,
	Labels: { TextLabel },
	Chances: { TextLabel },
	Studs: { Frame },
	Pointer: Frame,
	Spin: TextButton,
	SpinCount: number, -- the n on SPIN (n)
	Status: TextLabel,
	-- BUY SPINS (left)
	Buy: Frame,
	BuyTitle: TextLabel,
	BuyRows: { BuyRow },
	BuyButtons: { [number]: TextButton }, -- spin count -> its price button
	BuyNote: TextLabel,
	Details: TextButton,
	FastSpin: TextButton,
	FastCheck: TextButton,
	Fast: boolean,
	-- the jackpot (right)
	Jackpot: TextButton,
	JackpotTitle: TextLabel,
	JackpotTiles: Frame,
	JackpotFooter: TextLabel,
	JackpotShown: boolean,
	-- ALL ODDS (Details)
	OddsCard: Frame,
	OddsDim: Frame,
	OddsClose: TextButton,
	OddsTitle: TextLabel,
	OddsBuy: TextButton, -- the buy step's price button (the odds above it)
	BuyPack: number?, -- the spin count of the buy step shown (nil: plain Details)
	Odds: ScrollingFrame,
	Rows: { [string]: TextButton },
	RowData: { [string]: Row },
	More: TextLabel,
	Info: Frame,
	InfoSwatch: Frame,
	InfoTitle: TextLabel,
	InfoChance: TextLabel,
	InfoText: TextLabel,
	InfoLines: Frame,
	InfoClose: TextButton,
	InfoId: string?,
	Hint: TextLabel,
	-- the prize
	Result: Frame,
	ResultTitle: TextLabel,
	ResultPrize: TextLabel,
	ResultDetail: TextLabel,
	ResultOk: TextButton,
	Confetti: Frame,
	SegmentIds: { string },
	Compact: boolean,
}

export type ChipRefs = { Gui: ScreenGui, Button: TextButton, Icon: Frame }

type Metrics = {
	Margin: number, -- screen margin around everything
	TopClear: number, -- room kept free at the top for the HUD's BASE / LOBBY / VAULT bar
	Wheel: number, -- the wheel's biggest diameter
	MinWheel: number,
	Side: number, -- the side cards' width
	MinSide: number,
	Gap: number, -- between the columns
	Lift: number, -- room above the wheel for the X's overhang
	TitleH: number, -- the SPIN & WIN row above the wheel (0: none)
	Title: number,
	Status: number, -- the FREE SPIN IN line
	StatusText: number,
	Button: number, -- the SPIN banner
	ButtonWidth: number,
	Lip: number,
	Close: number, -- the X's touch box
	CloseFace: number, -- the painted X inside it (it may sit on the rim, never on the faces)
	Pad: number, -- inside the side cards
	BuyHead: number, -- the BUY SPINS title row
	BuyTitle: number,
	BuyRow: number,
	BuyGap: number,
	BuyText: number,
	Price: number, -- the price buttons' width
	Small: number, -- the Details / Fast Spin buttons' height
	Tile: number, -- the jackpot's golem tiles
	TileGap: number,
	TileColumns: number,
	JackHead: number,
	JackTitle: number,
	Footer: number,
	Row: number, -- ALL ODDS rows
	RowGap: number,
	RowLabel: number,
	RowDetail: number,
	Columns: number,
	Line: number,
	Band: number, -- ALL ODDS header band (its X is 0.82 of it)
	Hint: number,
	Card: Vector2, -- the prize card
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Margin = 8,
		TopClear = 66,
		Wheel = 500,
		MinWheel = 220,
		Side = 280,
		MinSide = 220,
		Gap = 24,
		Lift = 0,
		TitleH = 56,
		Title = 46,
		Status = 34,
		StatusText = 26,
		Button = 64,
		ButtonWidth = 330,
		Lip = 5,
		Close = 54,
		CloseFace = 54,
		Pad = 12,
		BuyHead = 46,
		BuyTitle = 34,
		BuyRow = 60,
		BuyGap = 8,
		BuyText = 30,
		Price = 124,
		Small = 52,
		Tile = 80,
		TileGap = 8,
		TileColumns = 3,
		JackHead = 62,
		JackTitle = 26,
		Footer = 30,
		Row = 54,
		RowGap = 4,
		RowLabel = 19,
		RowDetail = 14,
		Columns = 1,
		Line = 15,
		Band = 64,
		Hint = 16,
		Card = Vector2.new(460, 250),
	},
	-- phones and TVs: 72-unit buttons are 44 pt at uiScale 0.62
	Compact = {
		Margin = 8,
		TopClear = 0,
		Wheel = 440,
		MinWheel = 220,
		Side = 262,
		MinSide = 220,
		Gap = 26,
		Lift = 4,
		TitleH = 0,
		Title = 36,
		Status = 28,
		StatusText = 24,
		Button = 72,
		ButtonWidth = 300,
		Lip = 4,
		Close = 72,
		CloseFace = 58,
		Pad = 8,
		BuyHead = 36,
		BuyTitle = 28,
		BuyRow = 72,
		BuyGap = 6,
		BuyText = 30,
		Price = 124,
		Small = 72,
		Tile = 56,
		TileGap = 6,
		TileColumns = 4,
		JackHead = 36,
		JackTitle = 22,
		Footer = 26,
		Row = 72,
		RowGap = 6,
		RowLabel = 20,
		RowDetail = 15,
		Columns = 2,
		Line = 17,
		Band = 88,
		Hint = 18,
		Card = Vector2.new(440, 236),
	},
}

WheelView.Segments = 8
WheelView.BarsPerSegment = 8 -- the fan inside a segment (plus its two edge bars)
WheelView.DiscShare = 0.86 -- the faces' diameter as a share of the wheel box
WheelView.RingShare = 0.94 -- the green rim's outer diameter (the leaves stick out past it)
WheelView.HubShare = 0.24 -- the hub's diameter as a share of the disc
WheelView.LabelRadius = 0.52 -- the prize names' distance from the centre (share of the radius)
WheelView.ChanceRadius = 0.86 -- the chances' distance from the centre (share of the radius)
WheelView.Turns = 5 -- full turns before the disc stops
WheelView.FastTurns = 2 -- the same with Fast Spin on
WheelView.ChipSize = { Normal = Vector2.new(190, 54), Compact = Vector2.new(176, 72) }
WheelView.StudCount = 16
WheelView.LeafCount = 30
WheelView.ConfettiCount = 36
WheelView.ConfettiColors = {
	Color3.fromRGB(255, 206, 72),
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(110, 214, 92),
	Color3.fromRGB(120, 196, 255),
	Color3.fromRGB(196, 130, 255),
	Color3.fromRGB(255, 240, 220),
}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = PopTheme.Outline
-- the faces (owner's reference: bright alternating purple / yellow / pink)
WheelView.FaceColors = {
	Purple = rgb(170, 92, 248),
	Yellow = rgb(255, 204, 44),
	Pink = rgb(255, 104, 180),
} :: { [string]: Color3 }
WheelView.FaceOrder = { "Purple", "Yellow", "Pink", "Yellow" }
local GREEN_DARK = rgb(28, 104, 40) -- the rim
local GREEN = rgb(64, 160, 58) -- the leaves
local GREEN_LIGHT = rgb(92, 196, 72)
local STUD = rgb(255, 222, 74)
local POINTER = rgb(238, 40, 48)
local HUB = rgb(40, 42, 52)
local GOLD = rgb(255, 214, 80) -- chances in the lists
local DIM_TEXT = rgb(204, 208, 224)
-- the side cards: light lilac with a thick black border
local LILAC: Pop.Paint = { Top = rgb(236, 222, 255), Bottom = rgb(198, 174, 250), Edge = INK }
local LILAC_DEEP: Pop.Paint = { Top = rgb(200, 176, 250), Bottom = rgb(158, 128, 236), Edge = INK }

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- "30%", "33.3%", "0.5%", "0.12%" (exact odds as players read them).
function WheelView.percent(share: number): string
	if type(share) ~= "number" or share ~= share then
		return "0%"
	end
	local v = share * 100
	local text
	if math.abs(v - math.floor(v + 0.5)) < 1e-6 then
		text = string.format("%d", math.floor(v + 0.5))
	elseif v >= 1 then
		text = string.format("%.1f", v)
	else
		text = string.format("%.2f", v)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. "%"
end

-- "13:42:10" (hours may pass 24: the timer is never longer than a day).
function WheelView.countdown(seconds: number): string
	local s = math.max(0, math.ceil(if seconds == seconds then seconds else 0))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	return string.format("%02d:%02d:%02d", h, m, s % 60)
end

-- "10 min", "2 h", "90 s"
function WheelView.duration(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return `{seconds // 3600} h`
	elseif seconds >= 60 then
		return `{math.floor(seconds / 60 + 0.5)} min`
	end
	return `{math.max(0, math.floor(seconds))} s`
end

-- The face colour of segment `index` (1..8): purple, yellow, pink, yellow, ...
function WheelView.faceColor(index: number): Color3
	local order = WheelView.FaceOrder
	return WheelView.FaceColors[order[(index - 1) % #order + 1]]
end

-- How long the screen disc (and the lobby wheel) turns, and how many full
-- turns: Fast Spin makes it WheelConfig.FastSpinSeconds.
function WheelView.spinSeconds(fast: boolean?): number
	return if fast then WheelConfig.FastSpinSeconds else WheelConfig.SpinSeconds
end

function WheelView.spinTurns(fast: boolean?): number
	return if fast then WheelView.FastTurns else WheelView.Turns
end

-- The n on SPIN (n): the free spin when it is ready plus the bought spins
-- this player can use (`held`: 0 where paid random items are restricted).
function WheelView.spinCount(ready: boolean, held: number?): number
	local bought = if type(held) == "number" and held == held and held > 0 then math.floor(held) else 0
	return (if ready then 1 else 0) + bought
end

-- The line under the wheel.
function WheelView.statusText(ready: boolean, secondsLeft: number, busy: boolean?): string
	if busy then
		return "GOOD LUCK!"
	elseif ready then
		return "FREE SPIN READY!"
	end
	return "FREE SPIN IN " .. WheelView.countdown(secondsLeft)
end

-- The SPIN banner's word.
function WheelView.spinText(count: number, busy: boolean?): string
	if busy then
		return "SPINNING..."
	end
	return `SPIN ({count})`
end

-- The disc rotation (degrees, Roblox: clockwise) that puts segment `index`
-- (1..count, clockwise from the top) under the pointer at the top.
function WheelView.restAngle(index: number, count: number): number
	local step = 360 / count
	return (360 - (index - 1) * step) % 360
end

-- The rotation to spin to from `current`: at least `turns` full turns
-- forward (clockwise), landing on `index` shifted by `jitter` (-0.5..0.5 of
-- a segment, kept inside the segment).
function WheelView.spinTarget(current: number, index: number, count: number, turns: number, jitter: number?): number
	local step = 360 / count
	local rest = WheelView.restAngle(index, count) + math.clamp(jitter or 0, -0.4, 0.4) * step
	local base = current + turns * 360
	local target = base - (base % 360) + (rest % 360)
	if target < base then
		target += 360
	end
	return target
end

-- The segment under the pointer at a disc rotation (degrees).
function WheelView.segmentAt(rotation: number, count: number): number
	local step = 360 / count
	local angle = -rotation % 360 -- the disc angle now at the top
	return math.floor((angle + step / 2) / step) % count + 1
end

-- Ease-out for the spin (fast start, a long slow stop), t in 0..1.
function WheelView.ease(t: number): number
	local x = math.clamp(t, 0, 1)
	return 1 - (1 - x) ^ 4
end

local function rarityLine(odds: { [string]: number }): string
	local parts = {}
	for _, info in Rarity.List do
		local chance = odds[info.Id]
		if chance and chance > 0 then
			table.insert(parts, `{info.Name} {WheelView.percent(chance)}`)
		end
	end
	return table.concat(parts, " · ")
end

-- Is the Ore Pen full in a State snapshot (StorageCount / PenCapacity /
-- PenOver, as PenService.refusal decides one more item)? nil: not known.
function WheelView.penFull(state: { [string]: any }): boolean?
	local count = tonumber(state.StorageCount)
	local capacity = tonumber(state.PenCapacity)
	if not count or not capacity then
		return nil
	end
	return state.PenOver == true or count + 1 > capacity
end

-- What rows() needs from a State snapshot (WheelController passes the
-- latest one and whether paid random items are restricted).
function WheelView.info(state: { [string]: any }?, restricted: boolean): Info
	local s: { [string]: any } = state or {}
	local bonuses = if type(s.Bonuses) == "table" then s.Bonuses else {}
	local income = tonumber(s.Income) or 0
	local sell = tonumber(bonuses.SellMult)
	return {
		NoCapsules = restricted,
		Income = if income == income then income else 0,
		Ore = {
			BlasterLevel = tonumber(s.BlasterLevel) or 1,
			BestIncome = WheelConfig.bestIncome(s.Discovered),
		},
		TripleLucky = bonuses.TripleLucky == true,
		GolemRoom = if type(s.Golems) == "table" then GolemConfig.room(s.Golems) else nil,
		PenFull = WheelView.penFull(s),
		PriceLevel = BlasterData.priceLevel(s),
		SellMult = if sell and sell == sell and sell > 0 then sell else 1,
	}
end

-- The coins a capsule prize pays with a full golem inventory, and the ore
-- prize with a full Ore Pen (the server's WheelService amounts).
function WheelView.capsuleFallback(info: Info, capsuleId: string): number
	return WheelConfig.capsuleFallbackCoins(capsuleId, info.PriceLevel or 1)
end

function WheelView.oreFallback(info: Info): number
	local base = WheelConfig.oreFallbackCoins(info.Ore)
	if base <= 0 then
		return 0
	end
	return math.floor(base * (info.SellMult or 1) + 0.5)
end

-- "Golem inventory full: pays $X coins instead · " before a capsule row,
-- "Ore Pen full: pays $X coins instead · " before the ore row ("" when
-- there is room or it isn't known).
function WheelView.fullNote(segment: Segment, info: Info): string
	if segment.Kind == "Capsule" and info.GolemRoom ~= nil and info.GolemRoom < 1 then
		local coins = WheelView.capsuleFallback(info, segment.Capsule or "")
		return `Golem inventory full: pays {Format.money(coins)} coins instead · `
	elseif segment.Kind == "Ore" and info.PenFull == true then
		return `Ore Pen full: pays {Format.money(WheelView.oreFallback(info))} coins instead · `
	end
	return ""
end

-- What a segment pays this player (the odds list's second line).
function WheelView.detail(segment: Segment, info: Info): string
	if segment.Kind == "Coins" then
		local coins = WheelConfig.coins(segment, info.Income)
		return `{WheelView.duration(segment.Seconds or 0)} of your podium income, at least {Format.money(segment.Min or 0)}: {Format.money(
			coins
		)} now`
	elseif segment.Kind == "Boost" then
		local kind = BoostConfig.Kinds[segment.Boost or ""]
		local name = if kind then kind.Name else "a boost"
		local what = if kind and kind.Target == "Capsules" then "rarer golems from capsules" else "rarer ores from rocks"
		local cap = WheelView.duration(BoostConfig.MaxStackSeconds)
		return `+{WheelView.duration(segment.Seconds or 0)} of {name}: {what} (stacks up to {cap}; what doesn't fit is paid in coins)`
	elseif segment.Kind == "Capsule" then
		local capsule = CapsuleConfig.ById[segment.Capsule or ""]
		local name = if capsule then capsule.Name else "capsule"
		local line = rarityLine(CapsuleConfig.rarityOdds(segment.Capsule or "", info.TripleLucky))
		local lucky = if info.TripleLucky then " (Triple Lucky on)" else ""
		-- (the note leads the line: a cut row never hides it)
		return WheelView.fullNote(segment, info) .. `A free {name}{lucky}: {line}`
	elseif segment.Kind == "Ore" then
		local parts = {}
		for _, line in WheelConfig.oreOdds(info.Ore) do
			local ore = OreData.ById[line.Ore]
			table.insert(parts, `{if ore then ore.Name else line.Ore} {WheelView.percent(line.Chance)}`)
		end
		if #parts == 0 then
			return "Coins instead: no Rare ore in your mines yet"
		end
		return WheelView.fullNote(segment, info) .. "A dirty Rare+ ore for your Ore Pen: " .. table.concat(parts, " · ")
	elseif segment.Kind == "Shards" then
		return `{segment.Amount or 0} crystal shards for the Enchant shop`
	end
	return ""
end

-- The exact chance of every golem in a capsule (Triple Lucky as the player has it).
function WheelView.capsuleLines(capsuleId: string, tripleLucky: boolean): { Line }
	local lines: { Line } = {}
	for _, line in CapsuleConfig.odds(capsuleId, tripleLucky) do
		local golem = GolemConfig.ById[line.Golem]
		table.insert(lines, {
			Name = if golem then golem.Name else line.Golem,
			Chance = WheelView.percent(line.Chance),
			Color = if golem then Rarity.get(golem.Rarity).Color else PopTheme.Ink,
			Golem = line.Golem,
		})
	end
	return lines
end

-- The odds list for this player: one row per segment of their wheel.
function WheelView.rows(info: Info): { Row }
	local list: { Row } = {}
	for _, segment in WheelConfig.segments(info.NoCapsules) do
		table.insert(list, {
			Id = segment.Id,
			Label = segment.Label,
			Detail = WheelView.detail(segment, info),
			Chance = WheelView.percent(segment.Odds),
			Color = WheelView.faceColor(segment.Index),
			Lines = if segment.Kind == "Capsule" then WheelView.capsuleLines(segment.Capsule or "", info.TripleLucky) else nil,
		})
	end
	return list
end

-- The jackpot segment (the right-hand card) and what it can give.
function WheelView.jackpot(tripleLucky: boolean): (Segment, { Line })
	local segment = WheelConfig.ById[WheelConfig.JackpotId]
	return segment, WheelView.capsuleLines(segment.Capsule or "", tripleLucky)
end

-- The picture of a golem kind: its icon, or the icon under its old name (the
-- 36-ore roster renamed three golems; GolemConfig.Renamed).
function WheelView.golemIcon(kind: string): string
	local name = "golem_" .. kind
	if IconAssets.has(name) then
		return name
	end
	for old, new in GolemConfig.Renamed do
		if new == kind and IconAssets.has("golem_" .. old) then
			return "golem_" .. old
		end
	end
	return name
end

-- `text` cut to fit one line of `width` design units at `size` (with "...").
function WheelView.truncate(text: string, size: number, width: number): string
	local fits = math.max(4, math.floor(width / (size * 0.56)))
	if #text <= fits then
		return text
	end
	local head = text:sub(1, fits - 3)
	local cut = head:gsub("%s+%S*$", "")
	if cut == "" then
		cut = head
	end
	return cut .. "..."
end

-- The prize card's two lines for a WheelResult payload.
function WheelView.prizeText(result: { [string]: any }): (string, string)
	local kind = result.Kind
	local coins = tonumber(result.Coins)
	if kind == "Coins" then
		return `{Format.money(tonumber(result.Amount) or 0)} coins`, "Straight into your wallet"
	elseif kind == "Boost" then
		local boost = BoostConfig.Kinds[tostring(result.Boost)]
		local name = if boost then boost.Name else "Boost"
		local seconds = tonumber(result.Seconds) or 0
		local cap = WheelView.duration(BoostConfig.MaxStackSeconds)
		if seconds <= 0 then
			return `{Format.money(coins or 0)} coins`, `{name} is already full (up to {cap}): coins instead`
		end
		local what = if boost and boost.Target == "Capsules" then "Rarer golems from capsules" else "Rarer ores from rocks"
		if coins and coins > 0 then
			return `{name} +{WheelView.duration(seconds)}`, `Full at {cap}: +{Format.money(coins)} coins for the rest`
		end
		return `{name} +{WheelView.duration(seconds)}`, what
	elseif kind == "Capsule" then
		local capsule = CapsuleConfig.ById[tostring(result.Capsule)]
		local capsuleName = if capsule then capsule.Name else "capsule"
		local golem = result.Golem
		local golemInfo = if type(golem) == "table" then GolemConfig.ById[tostring(golem.Kind)] else nil
		if golemInfo then
			local rarity = Rarity.get(golemInfo.Rarity)
			local article = if string.find(rarity.Name, "^[AEIOU]") then "An" else "A"
			return `{golemInfo.Name}!`, `{article} {rarity.Name} golem from a free {capsuleName}`
		end
		if result.Full == true then
			return `{Format.money(coins or 0)} coins`, `Your golem inventory is full: coins instead of a {capsuleName}`
		end
		return `{Format.money(coins or 0)} coins`, `Coins instead of a {capsuleName}`
	elseif kind == "Ore" then
		if result.DirtyOre then
			return "A dirty Rare+ ore!", "It's in your Ore Pen: clean it to see which one"
		end
		return `{Format.money(coins or 0)} coins`, "Coins instead of the ore prize"
	elseif kind == "Shards" then
		return `{tonumber(result.Amount) or 0} Shards`, "Crystal shards for the Enchant shop"
	end
	return "Prize!", ""
end

-- Lines a text needs at `size` in `width` design units (a generous estimate).
function WheelView.lines(text: string, size: number, width: number): number
	local perLine = math.max(1, math.floor(width / (size * 0.56)))
	local count, line = 1, 0
	for word in text:gmatch("%S+") do
		local need = if line == 0 then #word else line + 1 + #word
		if need > perLine and line > 0 then
			count += 1
			line = #word
		else
			line = need
		end
	end
	return count
end

--[[
	How far the X moves up and right off the wheel box's top-right corner so
	its inner corner stays off the painted faces (`wheel` the box's size,
	`close` the X's): 0 when the corner is clear already.
]]
function WheelView.closeShift(wheel: number, close: number): number
	local r = wheel / 2
	local face = r * WheelView.DiscShare + 2
	return math.max(0, math.ceil(face / math.sqrt(2) - r + close))
end

---------------------------------------------------------------- building

local function circle(parent: Instance, props: { [string]: any }): Frame
	local merged: { [string]: any } = { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5) }
	for key, value in props do
		merged[key] = value
	end
	local frame: Frame = UIKit.new("Frame", merged, parent)
	UIKit.corner(frame, 9999)
	return frame
end

-- A bar on the disc (scale units of the disc: 1 = the disc's diameter).
local function bar(
	parent: Instance,
	cx: number,
	cy: number,
	width: number,
	length: number,
	degrees: number,
	color: Color3,
	z: number
): Frame
	return UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + cx, 0.5 + cy),
		Size = UDim2.fromScale(width, length),
		Rotation = degrees,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

-- Unit direction of a clockwise-from-top angle in screen space (y down).
local function dir(degrees: number): (number, number)
	local r = math.rad(degrees)
	return math.sin(r), -math.cos(r)
end

-- Light rays from the middle of a square frame (scale sizes: they follow it).
local function rays(parent: Instance, count: number, z: number): Frame
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, parent)
	for i = 1, count do
		local ray = UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * (180 / count),
			Size = UDim2.fromScale(1, 0.08),
			ZIndex = z,
		}, holder)
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.16, 0.72),
				NumberSequenceKeypoint.new(0.34, 1),
				NumberSequenceKeypoint.new(0.66, 1),
				NumberSequenceKeypoint.new(0.84, 0.72),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	return holder
end

--[[
	The wheel mark (BUY SPINS rows, the HUD chip): a little wheel drawn from
	four bars through the middle in the face colours, a black ring and a hub.
	`size` in design units. Returns the frame ("Mark").
]]
function WheelView.mark(parent: Instance, size: number, props: { [string]: any }?): Frame
	local mark = circle(parent, {
		Name = "Mark",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WheelView.FaceColors.Yellow,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 5,
	})
	Pop.border(mark, if size >= 40 then 3 else 2)
	for i, color in { WheelView.FaceColors.Purple, WheelView.FaceColors.Yellow, WheelView.FaceColors.Pink, WheelView.FaceColors.Yellow } do
		UIKit.new("Frame", {
			Name = "Spoke" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * 45,
			Size = UDim2.fromScale(0.36, 0.98),
			ZIndex = 5,
		}, mark)
	end
	local hub = circle(mark, {
		Name = "Hub",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundColor3 = HUB,
		ZIndex = 6,
	})
	Pop.border(hub, 1.5)
	if props then
		for key, value in props do
			local target: any = mark
			target[key] = value
		end
	end
	return mark
end

-- Draws the segments, dividers and labels of `segments` on the disc
-- (clears what was there). Disc scale: the radius is 0.5.
function WheelView.setSegments(refs: Refs, segments: { Segment })
	local disc = refs.Disc
	for _, child in disc:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(refs.Labels)
	table.clear(refs.Chances)
	table.clear(refs.SegmentIds)
	local count = #segments
	local step = 360 / count
	local R = 0.5
	local fan = WheelView.BarsPerSegment
	-- bar width: the rim chord between two fan bars, with a little overlap
	local width = 2 * R * math.sin(math.rad(step / (fan + 1) / 2)) * 1.25
	local edges: { () -> () } = {}
	for i, segment in segments do
		table.insert(refs.SegmentIds, segment.Id)
		local color = WheelView.faceColor(i)
		local a0 = (i - 1) * step - step / 2
		-- the fan through the centre
		for k = 1, fan do
			local a = a0 + step * k / (fan + 1)
			local dx, dy = dir(a)
			bar(disc, dx * R / 2, dy * R / 2, width, R, a, color, 2)
		end
		-- the two edge bars, their outer side on the edge rays (drawn after every fan)
		table.insert(edges, function()
			for _, edge in { { a0, 1 }, { a0 + step, -1 } } do
				local a, side = edge[1], edge[2]
				local dx, dy = dir(a)
				local px, py = dir(a + 90) -- toward growing angles
				local off = side * width / 2
				bar(disc, dx * R / 2 + px * off, dy * R / 2 + py * off, width, R, a, color, 3)
			end
		end)
	end
	for _, draw in edges do
		draw()
	end
	-- a soft light in the middle: the faces look rounded
	circle(disc, {
		Name = "Gloss",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		ZIndex = 4,
	})
	for i, segment in segments do
		local a0 = (i - 1) * step - step / 2
		local dx, dy = dir(a0)
		bar(disc, dx * R / 2, dy * R / 2, 0.016, R, a0, INK, 5)
		local mid = (i - 1) * step
		local lx, ly = dir(mid)
		-- radial, read from the centre out (the left half from the rim in, never upside down)
		local rotation = if mid > 180 then mid + 90 else mid - 90
		local nameR = R * WheelView.LabelRadius
		local label = Pop.text(disc, segment.Label, 15, {
			Name = "Label" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + lx * nameR, 0.5 + ly * nameR),
			Size = UDim2.fromScale(R * 0.5, R * 0.42),
			Rotation = rotation,
			TextWrapped = true,
			ZIndex = 6,
		})
		table.insert(refs.Labels, label)
		local chanceR = R * WheelView.ChanceRadius
		local chance = Pop.text(disc, WheelView.percent(segment.Odds), 16, {
			Name = "Chance" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + lx * chanceR, 0.5 + ly * chanceR),
			Size = UDim2.fromScale(R * 0.25, R * 0.22),
			Rotation = rotation,
			FontFace = PopTheme.Heavy,
			ZIndex = 6,
		})
		table.insert(refs.Chances, chance)
	end
	-- the hub sits on the disc (it turns with it)
	local hub = circle(disc, {
		Name = "Hub",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.HubShare, WheelView.HubShare),
		BackgroundColor3 = HUB,
		ZIndex = 7,
	})
	Pop.border(hub, 4)
	local inner = circle(hub, {
		Name = "Inner",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
		BackgroundColor3 = rgb(70, 74, 92),
		ZIndex = 8,
	})
	Pop.border(inner, 2)
	circle(inner, {
		Name = "Shine",
		Position = UDim2.fromScale(0.38, 0.34),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 9,
	})
end

-- A row's painted face: dark slate, lit purple (the prize), open blue.
local function paintRow(button: GuiObject, lit: boolean, open: boolean)
	Pop.repaint(button, if lit then "Purple" elseif open then "Blue" else "Slate")
	local border = button:FindFirstChild("Border") :: UIStroke?
	if border then
		border.Color = if lit then GOLD else INK
		border.Thickness = if lit then 4 else 3
	end
end

-- The odds rows (one per segment): buttons in a list (PC) or a 2-column
-- grid of tiles (compact). The canvas follows; updateMore shows the "more
-- below" note when they don't all fit.
function WheelView.setRows(refs: Refs, rows: { Row })
	local m = metrics(refs.Compact)
	for _, child in refs.Odds:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(refs.Rows)
	table.clear(refs.RowData)
	for i, row in rows do
		local button = UIKit.new("TextButton", {
			Name = row.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, -12, 0, m.Row),
			AutoButtonColor = true,
			Text = "",
			Selectable = true,
			ZIndex = 2,
		}, refs.Odds)
		Pop.face(button, "Slate", 8)
		local swatch = UIKit.new("Frame", {
			Name = "Swatch",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(0, 16, 1, -20),
			BackgroundColor3 = row.Color,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, button)
		UIKit.corner(swatch, 6)
		Pop.border(swatch, 2)
		-- the label and the chance, one line of what it pays this player (phones too:
		-- the buy step shows it before any Robux), a "more" mark on a PC
		local chanceW = if refs.Compact then 80 else 74
		local markW = if refs.Compact then 8 else 30
		Pop.text(button, row.Label, m.RowLabel, {
			Name = "Label",
			Position = UDim2.fromOffset(36, if refs.Compact then 6 else 4),
			Size = UDim2.new(1, -(36 + chanceW + markW), 0, m.RowLabel + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Pop.text(button, row.Chance, m.RowLabel + (if refs.Compact then 5 else 3), {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -markW, 0, if refs.Compact then 4 else 3),
			Size = UDim2.fromOffset(chanceW, m.RowLabel + 8),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = GOLD,
			FontFace = PopTheme.Heavy,
			ZIndex = 4,
		})
		-- (phones: two lines, so what it pays fits the tile)
		Pop.text(button, row.Detail, m.RowDetail, {
			Name = "Detail",
			Position = UDim2.fromOffset(36, m.RowLabel + (if refs.Compact then 11 else 10)),
			Size = UDim2.fromOffset(200, m.RowDetail + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = DIM_TEXT,
			TextWrapped = refs.Compact,
			ZIndex = 4,
		})
		Pop.text(button, ">", 24, {
			Name = "More",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(18, 30),
			FontFace = PopTheme.Heavy,
			Visible = not refs.Compact,
			ZIndex = 4,
		})
		refs.Rows[row.Id] = button
		refs.RowData[row.Id] = row
	end
	local lines = math.ceil(#rows / m.Columns)
	refs.Odds.CanvasSize = UDim2.fromOffset(0, lines * m.Row + math.max(0, lines - 1) * m.RowGap)
	WheelView.fitRows(refs)
end

-- The rows' one-line details follow the list's width (cut with "...": the
-- details card has the whole text), and the "more below" note.
function WheelView.fitRows(refs: Refs)
	local m = metrics(refs.Compact)
	local width = refs.Odds.Size.X.Offset
	if width <= 0 then
		width = 600
	end
	local grid = refs.Odds:FindFirstChildOfClass("UIGridLayout")
	-- a row's width: the list's (PC) or a grid tile's (compact)
	local rowW = if grid then grid.CellSize.X.Offset else width - 12
	local detailW = rowW - 36 - (if grid then 10 else 34)
	for id, button in refs.Rows do
		local detail = button:FindFirstChild("Detail")
		local row = refs.RowData[id]
		if detail and detail:IsA("TextLabel") and row then
			local lineCount = if grid then 2 else 1
			detail.Size = UDim2.fromOffset(detailW, lineCount * (m.RowDetail + 2) + 4)
			detail.Text = WheelView.truncate(row.Detail, m.RowDetail, math.floor(detailW * (if grid then 1.85 else 1)))
		end
	end
	WheelView.updateMore(refs)
end

-- Shows the "more below" note while rows are hidden under the list's bottom.
function WheelView.updateMore(refs: Refs)
	local canvas = refs.Odds.CanvasSize.Y.Offset
	local view = refs.Odds.Size.Y.Offset
	local scrolled = refs.Odds.CanvasPosition.Y
	refs.More.Visible = canvas - (scrolled + view) > 8
end

-- Lights a row (the segment the wheel stopped on), nil = none.
function WheelView.highlight(refs: Refs, id: string?)
	for rowId, button in refs.Rows do
		paintRow(button, rowId == id, rowId == refs.InfoId)
	end
end

-- The details card of a row over the window's body: its whole text and, for
-- a capsule, the exact chance of every golem (two columns).
function WheelView.showInfo(refs: Refs, id: string)
	local row = refs.RowData[id]
	if not row then
		return
	end
	local m = metrics(refs.Compact)
	refs.InfoId = id
	refs.InfoSwatch.BackgroundColor3 = row.Color
	refs.InfoTitle.Text = row.Label
	refs.InfoChance.Text = row.Chance
	refs.InfoText.Text = row.Detail
	local width = refs.Info.Size.X.Offset - 32
	local textSize = m.RowDetail + 2
	local textY = refs.InfoText.Position.Y.Offset
	local textH = math.ceil(WheelView.lines(row.Detail, textSize, width) * textSize * 1.25 + 4)
	refs.InfoText.TextSize = textSize
	refs.InfoText.Size = UDim2.fromOffset(width, textH)
	for _, child in refs.InfoLines:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local lines: { Line } = row.Lines or {}
	refs.InfoLines.Visible = #lines > 0
	refs.InfoLines.Position = UDim2.fromOffset(16, textY + textH + 6)
	refs.InfoLines.Size = UDim2.fromOffset(width, refs.Info.Size.Y.Offset - (textY + textH + 6) - 10)
	local cellW = math.floor((width - 8) / 2)
	local grid = refs.InfoLines:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(cellW, m.Line + 7)
	end
	for i, line in lines do
		local text = `{line.Name}  {line.Chance}`
		local size = math.min(m.Line, math.floor(cellW / (#text * 0.56)))
		Pop.text(refs.InfoLines, text, math.max(11, size), {
			Name = "Line" .. i,
			LayoutOrder = i,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = line.Color:Lerp(WHITE, 0.3),
			ZIndex = 14,
		})
	end
	refs.Info.Visible = true
end

function WheelView.hideInfo(refs: Refs)
	refs.InfoId = nil
	refs.Info.Visible = false
end

-- The hint text in the odds window's header (shown when it fits).
function WheelView.setHint(refs: Refs, text: string)
	refs.Hint.Text = text
	WheelView.placeHint(refs)
end

-- ALL ODDS (Details): open / closed / is it open?
function WheelView.showOdds(refs: Refs)
	refs.BuyPack = nil
	refs.OddsTitle.Text = "ALL ODDS"
	refs.OddsBuy.Visible = false
	refs.OddsCard.Visible = true
	refs.OddsDim.Visible = true
	WheelView.placeHint(refs)
	WheelView.updateMore(refs)
end

-- The buy step of a BUY SPINS row (`count` 1, 5, 10): the same window with
-- every segment's exact odds and what it pays this player, the pack in its
-- title and its green Robux price button: nothing is bought before the
-- player has seen the odds (the controller sends "Buy" from that button).
function WheelView.showBuy(refs: Refs, count: number)
	local pack = WheelConfig.packFor(count)
	if not pack then
		return
	end
	local product = MonetizationConfig.get(pack.Product)
	WheelView.hideInfo(refs)
	refs.BuyPack = count
	refs.OddsTitle.Text = `BUY {count} SPIN{if count == 1 then "" else "S"}`
	Pop.setPrice(refs.OddsBuy, if product then product.Robux else nil, "--")
	refs.OddsBuy:SetAttribute("Product", pack.Product)
	refs.OddsBuy:SetAttribute("Count", count)
	refs.OddsBuy.Visible = true
	refs.OddsCard.Visible = true
	refs.OddsDim.Visible = true
	WheelView.placeHint(refs)
	WheelView.updateMore(refs)
end

function WheelView.hideOdds(refs: Refs)
	WheelView.hideInfo(refs)
	refs.BuyPack = nil
	refs.OddsBuy.Visible = false
	refs.OddsCard.Visible = false
	refs.OddsDim.Visible = false
end

function WheelView.oddsOpen(refs: Refs): boolean
	return refs.OddsCard.Visible
end

-- The SPIN (n) banner and the line under the wheel: ready (the free spin),
-- `held` bought spins the player can use (0 where restricted), waiting
-- (seconds left) or busy (a spin in flight / the wheel turning).
function WheelView.setReady(refs: Refs, ready: boolean, secondsLeft: number, busy: boolean?, held: number?)
	local count = WheelView.spinCount(ready, held)
	refs.SpinCount = count
	local label = refs.Spin:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = WheelView.spinText(count, busy)
	end
	local live = count > 0 and not busy
	Pop.repaint(refs.Spin, if live then Pop.paint("Green") else PopTheme.Gray)
	local holder = refs.Spin.Parent
	local lip = if holder then holder:FindFirstChild("Lip") else nil
	if lip and lip:IsA("Frame") then
		lip.BackgroundColor3 = if live then rgb(20, 70, 18) else rgb(58, 60, 70)
	end
	refs.Status.Text = WheelView.statusText(ready, secondsLeft, busy)
	refs.Status.TextColor3 = if ready and not busy then rgb(170, 255, 110) else PopTheme.Ink
	refs.Spin:SetAttribute("Ready", live)
end

-- The BUY SPINS card: prices from MonetizationConfig; where paid random
-- items are restricted the rows hide and the note says why.
function WheelView.setBuy(refs: Refs, restricted: boolean)
	for _, row in refs.BuyRows do
		row.Frame.Visible = not restricted
		local product = MonetizationConfig.get(row.Product)
		Pop.setPrice(row.Button, if product then product.Robux else nil, "--")
	end
	refs.BuyNote.Visible = restricted
end

-- The Fast Spin box.
function WheelView.setFast(refs: Refs, on: boolean)
	refs.Fast = on
	Pop.setCheck(refs.FastCheck, on)
	refs.FastSpin:SetAttribute("On", on)
end

-- The jackpot card's tiles: what the jackpot capsule can give (with % each).
function WheelView.setJackpot(refs: Refs, lines: { Line })
	local m = metrics(refs.Compact)
	for _, child in refs.JackpotTiles:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local grid = refs.JackpotTiles:FindFirstChildOfClass("UIGridLayout")
	local tile = if grid then grid.CellSize.X.Offset else m.Tile
	for i, line in lines do
		local color = line.Color
		local face = UIKit.new("Frame", {
			Name = "Tile" .. i,
			LayoutOrder = i,
			ZIndex = 4,
		}, refs.JackpotTiles)
		Pop.face(face, { Top = color:Lerp(WHITE, 0.45), Bottom = color:Lerp(INK, 0.15), Edge = INK }, 8)
		local icon = WheelView.golemIcon(line.Golem or "")
		local picture = UIKit.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, 1),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(0.86, 0, 0.72, 0),
			ZIndex = 5,
		}, face)
		IconAssets.apply(picture, icon)
		picture:SetAttribute("Icon", icon)
		local shows = IconAssets.shows(icon)
		picture.Visible = shows
		if not shows then
			-- no uploaded picture yet: the golem's name (never an emoji)
			Pop.text(face, line.Name, math.max(10, math.floor(tile * 0.15)), {
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 3),
				Size = UDim2.new(1, -6, 0.66, 0),
				TextWrapped = true,
				ZIndex = 6,
			})
		end
		Pop.text(face, line.Chance, math.max(13, math.floor(tile * 0.24)), {
			Name = "Chance",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -2, 0.34, 0),
			FontFace = PopTheme.Heavy,
			ZIndex = 7,
		})
	end
	local segment = WheelConfig.ById[WheelConfig.JackpotId]
	refs.JackpotFooter.Text = `{WheelView.percent(segment.Odds)} ON THE WHEEL`
end

-- Shows the prize card (the controller adds the confetti fall).
function WheelView.showResult(refs: Refs, prize: string, detail: string, color: Color3)
	refs.ResultPrize.Text = prize
	refs.ResultPrize.TextColor3 = color:Lerp(WHITE, 0.45)
	refs.ResultDetail.Text = detail
	refs.Result.Visible = true
	refs.Confetti.Visible = true
end

function WheelView.hideResult(refs: Refs)
	refs.Result.Visible = false
	refs.Confetti.Visible = false
	for _, child in refs.Confetti:GetChildren() do
		child:Destroy()
	end
end

-- Confetti pieces scattered over the top of the screen (deterministic for
-- a seed); the controller tweens them down. Returns the pieces.
function WheelView.confetti(refs: Refs, seed: number): { Frame }
	local pieces: { Frame } = {}
	local state = seed
	local function rand(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	for i = 1, WheelView.ConfettiCount do
		local colors = WheelView.ConfettiColors
		local piece = UIKit.new("Frame", {
			Name = "Piece" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.05 + rand() * 0.9, 0.02 + rand() * 0.55),
			Size = UDim2.fromOffset(8 + math.floor(rand() * 8), 12 + math.floor(rand() * 10)),
			Rotation = rand() * 360,
			BackgroundColor3 = colors[1 + math.floor(rand() * #colors) % #colors],
			BorderSizePixel = 0,
			ZIndex = 40,
		}, refs.Confetti)
		Pop.border(piece, 1.5)
		table.insert(pieces, piece)
	end
	return pieces
end

-- The red pointer at the top: a circle and a diamond tip pointing down
-- (the diamond's lower sides touch the circle), drawn black a little bigger
-- behind for the outline. Scale units of its square frame.
local function pointer(box: Frame): Frame
	local frame = UIKit.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, -0.025),
		Size = UDim2.fromScale(0.15, 0.15),
		ZIndex = 10,
	}, box)
	local cx, cy = 0.5, 0.34
	local layers: { { Name: string, R: number, Color: Color3, Z: number } } = {
		{ Name = "Outline", R = 0.34, Color = INK, Z = 10 },
		{ Name = "Fill", R = 0.27, Color = POINTER, Z = 11 },
	}
	for _, layer in layers do
		local name, r, color, z = layer.Name, layer.R, layer.Color, layer.Z
		-- the diamond: side r, its bottom corner r * sqrt(2) under the circle's centre
		UIKit.new("Frame", {
			Name = name .. "Tip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(cx, cy + r * math.sqrt(0.5)),
			Rotation = 45,
			Size = UDim2.fromScale(r, r),
			ZIndex = z,
		}, frame)
		circle(frame, {
			Name = name .. "Head",
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(r * 2, r * 2),
			BackgroundColor3 = color,
			ZIndex = z,
		})
	end
	circle(frame, {
		Name = "Shine",
		Position = UDim2.fromScale(cx - 0.09, cy - 0.1),
		Size = UDim2.fromScale(0.13, 0.13),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		ZIndex = 12,
	})
	local pin = circle(frame, {
		Name = "PointerPin",
		Position = UDim2.fromScale(cx, cy),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundColor3 = rgb(130, 14, 22),
		ZIndex = 12,
	})
	Pop.border(pin, 1.5)
	return frame
end

-- A side card: painted lilac, thick black border, its title on top.
local function sideCard(parent: Instance, name: string, button: boolean): any
	local card = UIKit.new(if button then "TextButton" else "Frame", {
		Name = name,
		Active = true,
		ZIndex = 2,
	}, parent)
	if button then
		card.Text = ""
		card.AutoButtonColor = false
		card.Selectable = true
	end
	Pop.face(card, LILAC, 14, false)
	local border = card:FindFirstChild("Border") :: UIStroke
	border.Thickness = 4
	-- a light top strip (the photos' shine)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 5),
		Size = UDim2.new(1, -12, 0, 10),
		ZIndex = 2,
	}, card)
	return card
end

-- Builds the Spin & Win screen (hidden). `compact`: phones and TVs.
function WheelView.build(compact: boolean): Refs
	local m = metrics(compact)
	local gui = UIKit.screen("TerraForgeWheel", 20)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look: no LightSkin (it would recolour the faces)
	gui.Enabled = false
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 140),
		Position = UDim2.fromOffset(0, -140),
		BackgroundColor3 = rgb(16, 10, 34),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	-- everything sits in one invisible box (no window frame around the wheel)
	local panel = UIKit.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1000, 600),
		Active = true,
		ZIndex = 1,
	}, gui)
	local rayHolder = rays(panel, 10, 1)
	local title = Pop.title(panel, "SPIN & WIN", m.Title, "Gold", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = PopTheme.Heavy,
		Size = UDim2.fromOffset(500, m.TitleH),
		Visible = m.TitleH > 0,
		ZIndex = 4,
	})

	---------------------------------------------------------------- the wheel
	local box = UIKit.new("Frame", {
		Name = "WheelBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(m.Wheel, m.Wheel),
		ZIndex = 3,
	}, panel)
	-- the leafy rim: green bumps round the edge under the ring
	local leafR = WheelView.RingShare / 2 - 0.012
	for i = 1, WheelView.LeafCount do
		local a = (i - 1) * 360 / WheelView.LeafCount
		local dx, dy = dir(a)
		local leaf = circle(box, {
			Name = "Leaf" .. i,
			Position = UDim2.fromScale(0.5 + dx * leafR, 0.5 + dy * leafR),
			Size = UDim2.fromScale(0.072, 0.072),
			BackgroundColor3 = if i % 2 == 0 then GREEN else GREEN_LIGHT,
			ZIndex = 1,
		})
		Pop.border(leaf, 3)
	end
	local ring = circle(box, {
		Name = "Ring",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.RingShare, WheelView.RingShare),
		BackgroundColor3 = GREEN_DARK,
		ZIndex = 2,
	})
	Pop.border(ring, 4)
	circle(box, {
		Name = "RimLight",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.RingShare - 0.02, WheelView.RingShare - 0.02),
		BackgroundColor3 = rgb(46, 138, 52),
		ZIndex = 2,
	})
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.DiscShare, WheelView.DiscShare),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, box)
	-- the black line round the faces (still: a circle looks the same turned)
	local edge = circle(box, {
		Name = "Edge",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.DiscShare, WheelView.DiscShare),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	Pop.border(edge, 4)
	local studs: { Frame } = {}
	for i = 1, WheelView.StudCount do
		local a = (i - 1) * 360 / WheelView.StudCount + 360 / WheelView.StudCount / 2
		local dx, dy = dir(a)
		local r = (WheelView.RingShare + WheelView.DiscShare) / 4
		local stud = circle(box, {
			Name = "Stud" .. i,
			Position = UDim2.fromScale(0.5 + dx * r, 0.5 + dy * r),
			Size = UDim2.fromScale(0.03, 0.03),
			BackgroundColor3 = STUD,
			ZIndex = 9,
		})
		Pop.border(stud, 2)
		table.insert(studs, stud)
	end
	local pointerFrame = pointer(box)
	-- the X: a touch box (72 units on phones) round the painted red square
	local close = UIKit.new("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(m.Close, m.Close),
		Selectable = true,
		ZIndex = 20,
	}, panel)
	-- (a Frame, not a button: every click on the X reaches `close`)
	local closeFace = UIKit.new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.CloseFace, m.CloseFace),
		ZIndex = 20,
	}, close)
	Pop.face(closeFace, PopTheme.Close, 4)
	Pop.text(closeFace, "X", math.floor(m.CloseFace * 0.66), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = PopTheme.Heavy,
		ZIndex = 21,
	})

	---------------------------------------------------------------- under the wheel
	local status = Pop.text(panel, "", m.StatusText, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = PopTheme.Heavy,
		Size = UDim2.fromOffset(m.ButtonWidth + 160, m.Status),
		ZIndex = 4,
	})
	local spinHolder = UIKit.new("Frame", {
		Name = "SpinHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(m.ButtonWidth, m.Button + m.Lip),
		ZIndex = 4,
	}, panel)
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = rgb(20, 60, 18),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, m.Lip),
		Size = UDim2.new(1, 0, 0, m.Button),
		ZIndex = 4,
	}, spinHolder)
	UIKit.corner(lip, 14)
	Pop.border(lip, 4)
	local spin = UIKit.new("TextButton", {
		Name = "Spin",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.new(1, 0, 0, m.Button),
		Selectable = true,
		ZIndex = 5,
	}, spinHolder)
	Pop.face(spin, "Green", 14)
	local spinBorder = spin:FindFirstChild("Border") :: UIStroke
	spinBorder.Thickness = 4
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0.3, 0),
		ZIndex = 5,
	}, spin)
	Pop.text(spin, "SPIN (1)", math.floor(m.Button * 0.56), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = PopTheme.Heavy,
		ZIndex = 6,
	})

	---------------------------------------------------------------- BUY SPINS (left)
	local buy = sideCard(panel, "Buy", false) :: Frame
	local buyTitle = Pop.text(buy, "BUY SPINS", m.BuyTitle, {
		Name = "Title",
		Position = UDim2.fromOffset(0, m.Pad),
		Size = UDim2.new(1, 0, 0, m.BuyHead - 6),
		FontFace = PopTheme.Heavy,
		ZIndex = 4,
	})
	local buyRows: { BuyRow } = {}
	local buyButtons: { [number]: TextButton } = {}
	for i, pack in WheelConfig.Packs do
		local frame = UIKit.new("Frame", {
			Name = "Row" .. pack.Count,
			LayoutOrder = i,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -2 * m.Pad, 0, m.BuyRow),
			ZIndex = 3,
		}, buy)
		UIKit.corner(frame, 10)
		Pop.border(frame, 3)
		WheelView.mark(frame, math.floor(math.min(m.BuyRow - 14, 46)), {
			Position = UDim2.new(0, 8, 0.5, 0),
		})
		local label = Pop.text(frame, "x" .. pack.Count, m.BuyText, {
			Name = "Count",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, math.floor(math.min(m.BuyRow - 14, 46)) + 14, 0.5, 0),
			Size = UDim2.fromOffset(70, m.BuyText + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = PopTheme.Heavy,
			ZIndex = 5,
		})
		local product = MonetizationConfig.get(pack.Product)
		local price =
			Pop.price(frame, if product then product.Robux else nil, Vector2.new(m.Price, m.BuyRow - (if compact then 0 else 10)), {
				Name = "Buy" .. pack.Count,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(if compact then 0 else 5), 0.5, 0),
				ZIndex = 5,
			}, "--")
		price:SetAttribute("Product", pack.Product)
		price:SetAttribute("Count", pack.Count)
		-- (a 72-unit button on phones: its price not bigger than on a PC)
		local priceRow = price:FindFirstChild("Row")
		local amount = if priceRow then priceRow:FindFirstChild("Amount") :: TextLabel? else nil
		local robuxMark = if priceRow then priceRow:FindFirstChild("Mark") :: ImageLabel? else nil
		local priceSize = math.min(34, math.floor((m.BuyRow - 10) * 0.62))
		if amount then
			amount.TextSize = priceSize
			amount.Size = UDim2.fromOffset(Pop.textWidth(amount.Text, priceSize), priceSize + 6)
		end
		if robuxMark then
			robuxMark.Size = UDim2.fromOffset(priceSize + 2, priceSize + 2)
		end
		table.insert(buyRows, { Count = pack.Count, Product = pack.Product, Frame = frame, Label = label, Button = price })
		buyButtons[pack.Count] = price
	end
	local buyNote = Pop.text(buy, "Spins can't be bought where you play. Your free spin comes every day!", if compact then 22 else 24, {
		Name = "Note",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = false,
		ZIndex = 4,
	})
	local details = Pop.button(buy, "Details", "Blue", Vector2.new(200, m.Small), {
		Name = "Details",
		ZIndex = 4,
	})
	local fastSpin = UIKit.new("TextButton", {
		Name = "FastSpin",
		AutoButtonColor = true,
		Text = "",
		Selectable = true,
		ZIndex = 4,
	}, buy)
	Pop.face(fastSpin, LILAC_DEEP, 10)
	Pop.text(fastSpin, if compact then "FAST\nSPIN" else "Fast Spin", if compact then 20 else 24, {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(1, -66, 1, -6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 5,
	})
	local checkSize = if compact then 46 else 38
	local fastCheck = Pop.check(fastSpin, false, checkSize, {
		Name = "Check",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Selectable = false, -- (the whole row is the button)
		ZIndex = 5,
	})

	---------------------------------------------------------------- the jackpot (right)
	local jackpotSegment = WheelConfig.ById[WheelConfig.JackpotId]
	local jackpotCapsule = CapsuleConfig.ById[jackpotSegment.Capsule or ""]
	local jackpot = sideCard(panel, "Jackpot", true) :: TextButton
	local jackpotTitle =
		Pop.text(jackpot, string.upper(if jackpotCapsule then jackpotCapsule.Name else jackpotSegment.Label), m.JackTitle, {
			Name = "Title",
			Position = UDim2.fromOffset(0, m.Pad),
			Size = UDim2.new(1, 0, 0, m.JackTitle + 8),
			FontFace = PopTheme.Heavy,
			ZIndex = 4,
		})
	Pop.text(jackpot, "can give:", 18, {
		Name = "Sub",
		Position = UDim2.fromOffset(0, m.Pad + m.JackTitle + 6),
		Size = UDim2.new(1, 0, 0, 22),
		Visible = not compact,
		ZIndex = 4,
	})
	local tiles = UIKit.new("Frame", {
		Name = "Tiles",
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, jackpot)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(m.Tile, m.Tile),
		CellPadding = UDim2.fromOffset(m.TileGap, m.TileGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = m.TileColumns,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, tiles)
	local footer = Pop.text(jackpot, "", m.Footer - 6, {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 1),
		FontFace = PopTheme.Heavy,
		TextColor3 = rgb(255, 236, 120),
		Size = UDim2.new(1, -2 * m.Pad, 0, m.Footer),
		ZIndex = 4,
	})

	---------------------------------------------------------------- ALL ODDS (Details)
	local oddsDim = UIKit.new("Frame", {
		Name = "OddsDim",
		Size = UDim2.new(1, 0, 1, 140),
		Position = UDim2.fromOffset(0, -140),
		BackgroundColor3 = rgb(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 24,
	}, gui)
	local window = Pop.window(gui, "ALL ODDS", Vector2.new(800, 560), m.Band, "Green")
	local card = window.Root
	card.Name = "OddsCard"
	card.ZIndex = 25
	card.Visible = false
	local body = window.Body
	local odds = UIKit.new("ScrollingFrame", {
		Name = "Odds",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = GOLD,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 2,
	}, body)
	if m.Columns > 1 then
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(200, m.Row),
			CellPadding = UDim2.fromOffset(m.RowGap, m.RowGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirectionMaxCells = m.Columns,
		}, odds)
	else
		UIKit.list(odds, Enum.FillDirection.Vertical, m.RowGap)
	end
	-- "more below" over the bottom of the list while rows hide under it
	local more = Pop.text(body, "more odds below", m.Hint, {
		Name = "More",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = PopTheme.Well,
		TextColor3 = GOLD,
		Visible = false,
		ZIndex = 8,
	})
	UIKit.corner(more, 8)
	local hint = Pop.text(window.Header, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	})
	-- the buy step: every segment's odds in the body, this price button in the header
	local oddsBuy = Pop.price(window.Header, nil, Vector2.new(m.Price + 30, m.Band - 16), {
		Name = "Confirm",
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		ZIndex = 6,
	}, "--")
	-- a row's details card over the whole window (its X where the window's X is)
	local info = UIKit.new("Frame", {
		Name = "Info",
		Visible = false,
		Active = true,
		ZIndex = 12,
	}, card)
	Pop.face(info, "Slate", 6, false)
	local infoBand = UIKit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, m.Band - 8),
		ZIndex = 12,
	}, info)
	Pop.face(infoBand, "Purple", 4, false)
	local bandX = math.floor(m.Band * 0.82)
	local infoSwatch = UIKit.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0, math.floor((m.Band - 8) / 2)),
		Size = UDim2.fromOffset(18, math.floor(m.Band * 0.5)),
		BorderSizePixel = 0,
		ZIndex = 13,
	}, info)
	UIKit.corner(infoSwatch, 6)
	Pop.border(infoSwatch, 2)
	local infoTitle = Pop.text(info, "", math.floor(m.Band * 0.42), {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0, math.floor((m.Band - 8) / 2)),
		Size = UDim2.new(1, -(44 + bandX + 140), 0, math.floor(m.Band * 0.5)),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = PopTheme.Heavy,
		ZIndex = 13,
	})
	local infoChance = Pop.text(info, "", math.floor(m.Band * 0.44), {
		Name = "Chance",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(bandX + 24), 0, math.floor((m.Band - 8) / 2)),
		Size = UDim2.fromOffset(130, math.floor(m.Band * 0.5)),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = GOLD,
		FontFace = PopTheme.Heavy,
		ZIndex = 13,
	})
	local infoClose = Pop.close(info, bandX, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0, math.floor(m.Band / 2) - 4),
		ZIndex = 14,
	})
	local infoText = Pop.text(info, "", m.RowDetail + 2, {
		Name = "Text",
		Position = UDim2.fromOffset(16, m.Band + 4),
		Size = UDim2.new(1, -32, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = DIM_TEXT,
		TextWrapped = true,
		ZIndex = 13,
	})
	local infoLines = UIKit.new("Frame", {
		Name = "Lines",
		BackgroundTransparency = 1,
		ZIndex = 13,
	}, info)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(200, m.Line + 7),
		CellPadding = UDim2.fromOffset(8, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 2,
	}, infoLines)

	---------------------------------------------------------------- the prize card and the confetti
	local confetti = UIKit.new("Frame", {
		Name = "Confetti",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 40,
	}, panel)
	local result = UIKit.new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(m.Card.X, m.Card.Y),
		ClipsDescendants = true,
		Active = true,
		Visible = false,
		ZIndex = 30,
	}, panel)
	Pop.face(result, "Night", 14, false)
	result:SetAttribute("Motion", "PopIn") -- (UIMotionController: it bounces in each time it shows)
	local resultBorder = result:FindFirstChild("Border") :: UIStroke
	resultBorder.Thickness = 4
	local resultRays = rays(result, 8, 30)
	resultRays.Position = UDim2.fromScale(0.5, 0.18)
	resultRays.Size = UDim2.fromOffset(m.Card.X * 1.4, m.Card.X * 1.4)
	local resultTitle = Pop.title(result, "YOU WON!", 44, "Gold", {
		Name = "Title",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 50),
		FontFace = PopTheme.Heavy,
		ZIndex = 31,
	})
	local resultPrize = Pop.text(result, "", 30, {
		Name = "Prize",
		Position = UDim2.fromOffset(14, 62),
		Size = UDim2.new(1, -28, 0, 40),
		TextWrapped = true,
		ZIndex = 31,
	})
	local resultDetail = Pop.text(result, "", if compact then 20 else 18, {
		Name = "Detail",
		Position = UDim2.fromOffset(18, 104),
		Size = UDim2.new(1, -36, 0, 46),
		TextColor3 = DIM_TEXT,
		TextWrapped = true,
		ZIndex = 31,
	})
	local ok = Pop.button(result, "OK", "Green", Vector2.new(180, if compact then 72 else 56), {
		Name = "Ok",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		ZIndex = 32,
	})
	local okLabel = ok:FindFirstChild("Label") :: TextLabel
	okLabel.FontFace = PopTheme.Heavy
	okLabel.ZIndex = 33

	local refs: Refs = {
		Gui = gui,
		Dim = dim,
		Panel = panel,
		Title = title,
		Close = close,
		Rays = rayHolder,
		WheelBox = box,
		Disc = disc,
		Labels = {},
		Chances = {},
		Studs = studs,
		Pointer = pointerFrame,
		Spin = spin,
		SpinCount = 1,
		Status = status,
		Buy = buy,
		BuyTitle = buyTitle,
		BuyRows = buyRows,
		BuyButtons = buyButtons,
		BuyNote = buyNote,
		Details = details,
		FastSpin = fastSpin,
		FastCheck = fastCheck,
		Fast = false,
		Jackpot = jackpot,
		JackpotTitle = jackpotTitle,
		JackpotTiles = tiles,
		JackpotFooter = footer,
		JackpotShown = true,
		OddsCard = card,
		OddsDim = oddsDim,
		OddsClose = window.Close,
		OddsTitle = window.Title,
		OddsBuy = oddsBuy,
		BuyPack = nil,
		Odds = odds,
		Rows = {},
		RowData = {},
		More = more,
		Info = info,
		InfoSwatch = infoSwatch,
		InfoTitle = infoTitle,
		InfoChance = infoChance,
		InfoText = infoText,
		InfoLines = infoLines,
		InfoClose = infoClose,
		InfoId = nil,
		Hint = hint,
		Result = result,
		ResultTitle = resultTitle,
		ResultPrize = resultPrize,
		ResultDetail = resultDetail,
		ResultOk = ok,
		Confetti = confetti,
		SegmentIds = {},
		Compact = compact,
	}
	WheelView.setSegments(refs, WheelConfig.segments(false))
	WheelView.setBuy(refs, false)
	local _, lines = WheelView.jackpot(false)
	WheelView.setJackpot(refs, lines)
	WheelView.setReady(refs, true, 0, false, 0)
	-- like every window: Roblox's touch controls hide while it is open
	TouchControls.follow(gui)
	return refs
end

-- The BUY SPINS card's height for a layout (the rows, Details, Fast Spin).
local function buyHeight(m: Metrics, compact: boolean): number
	local rows = #WheelConfig.Packs * m.BuyRow + (#WheelConfig.Packs - 1) * m.BuyGap
	local tools = if compact then m.Small else 2 * m.Small + m.BuyGap
	return m.Pad + m.BuyHead + rows + m.BuyGap + 6 + tools + m.Pad
end

-- Lays the BUY SPINS card out inside `width`.
local function placeBuy(refs: Refs, m: Metrics, width: number)
	local inner = width - 2 * m.Pad
	local y = m.Pad + m.BuyHead
	for _, row in refs.BuyRows do
		row.Frame.Position = UDim2.fromOffset(m.Pad, y)
		row.Frame.Size = UDim2.fromOffset(inner, m.BuyRow)
		y += m.BuyRow + m.BuyGap
	end
	-- (restricted: the note in the rows' place)
	local rowsTop = m.Pad + m.BuyHead
	refs.BuyNote.Position = UDim2.fromOffset(m.Pad, rowsTop)
	refs.BuyNote.Size = UDim2.fromOffset(inner, y - rowsTop - m.BuyGap)
	y += 6
	if refs.Compact then
		-- Details and Fast Spin share one row (72 units each: 44 pt on a phone)
		local half = math.floor((inner - m.BuyGap) / 2)
		refs.Details.Position = UDim2.fromOffset(m.Pad, y)
		refs.Details.Size = UDim2.fromOffset(half, m.Small)
		refs.FastSpin.Position = UDim2.fromOffset(m.Pad + half + m.BuyGap, y)
		refs.FastSpin.Size = UDim2.fromOffset(inner - half - m.BuyGap, m.Small)
	else
		refs.Details.Position = UDim2.fromOffset(m.Pad, y)
		refs.Details.Size = UDim2.fromOffset(inner, m.Small)
		y += m.Small + m.BuyGap
		refs.FastSpin.Position = UDim2.fromOffset(m.Pad, y)
		refs.FastSpin.Size = UDim2.fromOffset(inner, m.Small)
	end
	local detailsLabel = refs.Details:FindFirstChild("Label") :: TextLabel?
	if detailsLabel then
		detailsLabel.TextSize = math.floor(math.min(m.Small * 0.5, 30))
	end
end

-- The jackpot card's tile size and height inside `width` x at most `maxHeight`.
local function jackpotSize(m: Metrics, width: number, maxHeight: number, count: number): (number, number)
	local inner = width - 2 * m.Pad
	local columns = m.TileColumns
	local rowsN = math.max(1, math.ceil(count / columns))
	local tile = math.min(m.Tile, math.floor((inner - (columns - 1) * m.TileGap) / columns))
	local fixed = m.Pad + m.JackHead + 6 + m.Footer + m.Pad
	local room = maxHeight - fixed - (rowsN - 1) * m.TileGap
	tile = math.max(30, math.min(tile, math.floor(room / rowsN)))
	return tile, fixed + rowsN * tile + (rowsN - 1) * m.TileGap
end

-- Fits the screen into `maxWidth` x `maxHeight` design units (the screen
-- below the top bar): the wheel as big as it goes, the side cards beside it
-- (the jackpot hides on a screen too narrow for both), the X, the SPIN
-- banner, the prize card and ALL ODDS.
function WheelView.layout(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local W = math.floor(maxWidth - 2 * m.Margin)
	local H = math.floor(maxHeight - 2 * m.Margin - m.TopClear)
	local below = 6 + m.Status + 4 + m.Button + m.Lip
	local function wheelFor(sides: number, side: number, titleH: number): number
		local byHeight = H - below - m.Lift - titleH
		local byWidth = W - sides * (side + m.Gap)
		return math.floor(math.min(m.Wheel, byHeight, byWidth))
	end
	-- the title row only when the wheel keeps its full size with it
	local titleH = if m.TitleH > 0 and H - below - m.Lift - m.TitleH >= m.Wheel then m.TitleH else 0
	local side = m.Side
	local sides = 2
	local wheel = wheelFor(sides, side, titleH)
	if wheel < m.MinWheel then
		-- narrower side cards first, then no jackpot card
		side = math.max(m.MinSide, math.floor((W - m.MinWheel) / 2 - m.Gap))
		wheel = wheelFor(sides, side, titleH)
		if wheel < m.MinWheel then
			sides = 1
			side = m.Side
			wheel = wheelFor(sides, side, titleH)
		end
	end
	wheel = math.max(wheel, 120)
	refs.JackpotShown = sides == 2
	refs.Jackpot.Visible = refs.JackpotShown

	local buyH = buyHeight(m, refs.Compact)
	local columnH = titleH + m.Lift + wheel + below
	local contentH = math.min(H, math.max(columnH, buyH))
	local wheelX = side + m.Gap
	local width = wheelX + wheel + (if sides == 2 then m.Gap + side else 0)
	refs.Panel.Size = UDim2.fromOffset(width, contentH)
	refs.Panel.Position = UDim2.new(0.5, 0, 0.5, math.floor(m.TopClear / 2))
	local top = math.max(0, math.floor((contentH - columnH) / 2))
	local wheelY = top + titleH + m.Lift
	refs.WheelBox.Size = UDim2.fromOffset(wheel, wheel)
	refs.WheelBox.Position = UDim2.fromOffset(wheelX, wheelY)
	local cx = wheelX + math.floor(wheel / 2)
	refs.Title.Visible = titleH > 0
	refs.Title.Position = UDim2.fromOffset(cx, top)
	refs.Title.Size = UDim2.fromOffset(wheel, titleH)
	refs.Rays.Position = UDim2.fromOffset(cx, wheelY + math.floor(wheel / 2))
	refs.Rays.Size = UDim2.fromOffset(math.floor(wheel * 1.36), math.floor(wheel * 1.36))
	-- the X at the wheel's top right, off the faces
	-- (its touch box reaches a little further: it may lie on the wheel, nothing there is a button)
	local shift = math.min(WheelView.closeShift(wheel, m.CloseFace), m.Lift + titleH, m.Gap)
	local extra = math.floor((m.Close - m.CloseFace) / 2)
	refs.Close.AnchorPoint = Vector2.new(1, 0)
	refs.Close.Position = UDim2.fromOffset(wheelX + wheel + shift + extra, wheelY - shift - extra)
	-- under the wheel
	local statusY = wheelY + wheel + 6
	refs.Status.Position = UDim2.fromOffset(cx, statusY)
	local spinHolder = refs.Spin.Parent :: Frame
	spinHolder.Size = UDim2.fromOffset(math.min(m.ButtonWidth, wheel + 2 * m.Gap), m.Button + m.Lip)
	spinHolder.Position = UDim2.fromOffset(cx, statusY + m.Status + 4)

	-- the side cards, centred on the wheel (kept on screen)
	local wheelMid = wheelY + wheel / 2
	local buyY = math.clamp(math.floor(wheelMid - buyH / 2), 0, math.max(0, contentH - buyH))
	refs.Buy.Position = UDim2.fromOffset(0, buyY)
	refs.Buy.Size = UDim2.fromOffset(side, buyH)
	placeBuy(refs, m, side)
	local _, lines = WheelView.jackpot(false)
	local tile, jackH = jackpotSize(m, side, contentH, #lines)
	local jackY = math.clamp(math.floor(wheelMid - jackH / 2), 0, math.max(0, contentH - jackH))
	refs.Jackpot.Position = UDim2.fromOffset(wheelX + wheel + m.Gap, jackY)
	refs.Jackpot.Size = UDim2.fromOffset(side, jackH)
	local grid = refs.JackpotTiles:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(tile, tile)
	end
	local tilesTop = m.Pad + m.JackHead + 3
	refs.JackpotTiles.Position = UDim2.fromOffset(m.Pad, tilesTop)
	refs.JackpotTiles.Size = UDim2.fromOffset(side - 2 * m.Pad, jackH - tilesTop - m.Footer - m.Pad)
	for _, child in refs.JackpotTiles:GetChildren() do
		if child:IsA("Frame") then
			for _, label in child:GetChildren() do
				if label:IsA("TextLabel") and label.Name == "Chance" then
					label.TextSize = math.max(13, math.floor(tile * 0.24))
				end
			end
		end
	end
	refs.JackpotFooter.Position = UDim2.new(0.5, 0, 1, -m.Pad + 2)

	-- the prize card over the lower half of the wheel (the prize stays under the pointer)
	local cardW = math.min(m.Card.X, width - 16)
	local cardTop = wheelY + math.floor(wheel * 0.5) + 4
	local cardH = math.min(m.Card.Y, contentH - cardTop - 4)
	if cardH < m.Card.Y then
		cardTop = math.max(0, contentH - m.Card.Y - 4)
		cardH = math.min(m.Card.Y, contentH - cardTop - 4)
	end
	refs.Result.Size = UDim2.fromOffset(cardW, cardH)
	refs.Result.Position = UDim2.fromOffset(cx, cardTop)

	-- the faces' text follows the wheel's size
	local faceR = wheel * WheelView.DiscShare / 2
	local nameSize = math.max(12, math.floor(faceR * (if refs.Compact then 0.105 else 0.094)))
	local chanceSize = math.max(13, math.floor(faceR * 0.118))
	for _, label in refs.Labels do
		label.TextSize = nameSize
		local edge = label:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Thickness = Pop.edgeFor(nameSize)
		end
	end
	for _, label in refs.Chances do
		label.TextSize = chanceSize
		local edge = label:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Thickness = Pop.edgeFor(chanceSize)
		end
	end

	WheelView.layoutOdds(refs, maxWidth, maxHeight)
end

-- ALL ODDS: the window over the screen, its rows, the details card.
function WheelView.layoutOdds(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local width = math.floor(math.min(if refs.Compact then 1040 else 820, maxWidth - 2 * m.Margin))
	local height = math.floor(math.min(560, maxHeight - m.Margin))
	refs.OddsCard.Size = UDim2.fromOffset(width, height)
	local bodyW = width - 8
	local bodyH = height - m.Band - 4
	local pad = 6
	refs.Odds.Position = UDim2.fromOffset(pad, pad)
	refs.Odds.Size = UDim2.fromOffset(bodyW - 2 * pad, bodyH - 2 * pad)
	local grid = refs.Odds:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(math.floor((bodyW - 2 * pad - 12 - m.RowGap) / 2), m.Row)
	end
	refs.More.Position = UDim2.new(0.5, 0, 1, -4)
	refs.More.Size = UDim2.fromOffset(math.min(bodyW - 24, 260), m.Hint + 10)
	-- the details card covers the whole window (header too: one X)
	refs.Info.Position = UDim2.fromOffset(4, 4)
	refs.Info.Size = UDim2.fromOffset(width - 8, height - 8)
	-- the buy step: the green price button in the header, left of the X
	local closeW = math.floor(m.Band * 0.82) + 20
	local confirmW = m.Price + 30
	refs.OddsBuy.Size = UDim2.fromOffset(confirmW, m.Band - 16)
	refs.OddsBuy.Position = UDim2.new(1, -closeW, 0.5, 0)
	WheelView.placeHint(refs)
	WheelView.fitRows(refs)
end

-- The hint between the window's title and the X (and the price button in the buy step).
function WheelView.placeHint(refs: Refs)
	local m = metrics(refs.Compact)
	local width = refs.OddsCard.Size.X.Offset
	local titleW = Pop.measure(refs.OddsTitle) + 30
	local closeW = math.floor(m.Band * 0.82) + 20
	local right = closeW + (if refs.OddsBuy.Visible then refs.OddsBuy.Size.X.Offset + 12 else 4)
	local room = width - 8 - titleW - right
	refs.Hint.Position = UDim2.new(1, -right, 0.5, 0)
	refs.Hint.Size = UDim2.fromOffset(math.max(0, room), m.Hint + 6)
	refs.Hint.Visible = room >= Pop.measure(refs.Hint) * 0.85
end

---------------------------------------------------------------- the HUD chip

-- Where the chip sits: right of the quick-teleport bar in the HUD's top row
-- (TeleportView's bar at this uiScale and screen width in pt: the icon-only
-- bar under TeleportView.NarrowWidth), design units from the top centre.
function WheelView.chipOffset(uiScale: number, screenWidth: number?): Vector2
	local layout = TeleportView.layout(uiScale, screenWidth)
	local barWidth = TeleportView.barWidth(layout, 3) + 44 + layout.Gap
	return Vector2.new(math.floor(barWidth / 2) + 14, 10)
end

-- The chip's size at a uiScale (design units).
function WheelView.chipSize(uiScale: number): Vector2
	return if uiScale <= TeleportView.CompactScale then WheelView.ChipSize.Compact else WheelView.ChipSize.Normal
end

-- The chip's box on a screen (pt): its top-left corner and size in design
-- units from the screen's top-left.
function WheelView.chipRect(uiScale: number, screen: Vector2): (Vector2, Vector2)
	local offset = WheelView.chipOffset(uiScale, screen.X)
	return Vector2.new(screen.X / uiScale / 2 + offset.X, offset.Y), WheelView.chipSize(uiScale)
end

-- The chip for a uiScale and the screen width in pt (nil: the bar's
-- uiScale layout, as on a screen wider than TeleportView.NarrowWidth): an
-- orange painted button, the drawn wheel mark and FREE SPIN! (no emoji).
-- Its Parent is the holder frame placeChip moves.
function WheelView.buildChip(uiScale: number, screenWidth: number?): ChipRefs
	local gui = UIKit.screen("TerraForgeFreeSpin", 4)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true)
	gui.Enabled = false
	local compact = uiScale <= TeleportView.CompactScale
	local size = WheelView.chipSize(uiScale)
	local offset = WheelView.chipOffset(uiScale, screenWidth)
	local holder = UIKit.new("Frame", {
		Name = "FreeSpin",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, offset.X, 0, offset.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
	}, gui)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Selectable = true,
		ZIndex = 2,
	}, holder)
	-- (the pixel reels' small button: the painted face with its lip and lattice,
	-- a gleam now and then, the round wheel in a painted square at the left end,
	-- FREE SPIN! in pixel letters on two lines so they stay big)
	Pop.face(button, "Orange", 12)
	Pop.studs(button, 12, 0.45, 28, 2)
	Pop.gleam(button, 2)
	Pop.fxTag(button, "Press")
	local lip = Pop.lipUnits(size.Y)
	local square = size.Y - lip - 10
	local well = UIKit.new("Frame", {
		Name = "IconSquare",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, -math.floor(lip / 2)),
		Size = UDim2.fromOffset(square, square),
		ZIndex = 3,
	}, button)
	Pop.face(well, "Purple", math.floor(square * 0.22), true, false)
	local wellBorder = well:FindFirstChild("Border") :: UIStroke?
	if wellBorder then
		wellBorder.Thickness = 2.5
	end
	Pop.studs(well, 8, 0.45, 20, 3)
	local markSize = square - 6
	local icon = WheelView.mark(button, markSize, {
		Name = "Icon",
		Position = UDim2.new(0, 9, 0.5, -math.floor(lip / 2)),
	})
	local left = 6 + square + 6
	local label = Pop.text(button, "FREE SPIN!", if compact then 25 else 22, {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, -math.floor(lip / 2)),
		Size = UDim2.new(1, -(left + 6), 1, -(lip + 8)),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = PopTheme.Heavy,
		ZIndex = 5,
	})
	-- (two lines: wrapped and scaled, at most this big)
	label.TextWrapped = true
	label.TextScaled = true
	local fit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if fit then
		-- (the round look's letters are narrower: bigger, still two lines when they don't fit one)
		fit.MaxTextSize = if PopTheme.round() then (if compact then 26 else 22) elseif compact then 22 else 17
	end
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = 2
	end
	return { Gui = gui, Button = button, Icon = icon }
end

-- Should the FREE SPIN! chip show: the spin is ready, the wheel screen is
-- closed, no spin is in flight, nothing else has the screen (the cleaning
-- minigame, build mode, the crate opening: the HUD is hidden) and the
-- tutorial bubble isn't in the chip's spot (`tutorialInTopRow`: on touch
-- screens the bubble sits right of the teleport bar too; it comes first)?
function WheelView.chipVisible(ready: boolean, isOpen: boolean, spinning: boolean, busyScreen: boolean, tutorialInTopRow: boolean?): boolean
	return ready and not isOpen and not spinning and not busyScreen and not tutorialInTopRow
end

-- Moves the chip for a new uiScale and screen width in pt (phone <-> big screen).
function WheelView.placeChip(chip: ChipRefs, uiScale: number, screenWidth: number?)
	local size = WheelView.chipSize(uiScale)
	local offset = WheelView.chipOffset(uiScale, screenWidth)
	local holder = chip.Button.Parent
	if holder and holder:IsA("Frame") then
		holder.Position = UDim2.new(0.5, offset.X, 0, offset.Y)
		holder.Size = UDim2.fromOffset(size.X, size.Y)
	end
end

return WheelView
