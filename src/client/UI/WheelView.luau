--[[
	The daily wheel screen (SPIN & WIN) and the HUD's FREE SPIN! chip: pure
	builders, layout math and texts (WheelController fills them in, spins
	the disc and handles input; the Lune preview builds the same views).

	  panel   the title, an X (B / Backspace close it too), the wheel, the
	          SPIN! button with the countdown under it ("Next free spin in
	          13:42:10"), the ODDS list and a hint line
	  wheel   8 pie segments in WheelConfig's colors, clockwise from the top
	          (segment i centered at (i - 1) x 45 degrees), drawn from rotated
	          bars (Roblox UI has no wedges): every segment is a fan of bars
	          through the centre plus one bar on each edge whose outer side
	          lies ON the edge ray, so no color spills over a segment edge;
	          gold dividers, radial labels, a ring of light studs, a pointer
	          at the top and a hub. The whole Disc frame turns (children turn
	          with it); restAngle / spinTarget give the angle that puts a
	          segment under the pointer.
	  odds    one row per segment, all 8 in view: its color, label and the
	          exact chance; on a PC also one line of what it pays THIS player
	          (coins at their income, the ore prize's own odds, the capsule's
	          rarity odds with their Triple Lucky), from rows() (pure,
	          tested). Phones and TVs (compact) show the rows as a 2 x 4 grid
	          of 72-unit tiles (label + chance). Every row is a button: a
	          click / tap / A shows its details card over the odds column
	          (the whole text and, for a capsule, the exact chance of EVERY
	          golem in it); X / B / the row again close it. A "more below"
	          note shows whenever the list is longer than its box.
	  result  the prize card over the panel ("YOU WON!") with an OK button
	          and confetti pieces the controller lets fall
	  chip    its own ScreenGui: "FREE SPIN!" in the HUD's top row, right of
	          the quick-teleport bar (TeleportView's width for this uiScale
	          and screen width: icon-only under TeleportView.NarrowWidth),
	          only while the free spin is ready and the touch tutorial bubble
	          isn't in that same spot (chipVisible)

	Designed for 720 design units of height (HudController scales every
	TerraForge gui); `compact` (phones, TVs) has 72-unit buttons (44 pt at
	uiScale 0.62) and bigger texts, and layout() shrinks the panel to fit
	small screens down to a 568 x 320 pt phone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WheelConfig = require(Shared.Config.WheelConfig)
local Format = require(Shared.Util.Format)
local TeleportView = require(script.Parent.TeleportView)
local UIKit = require(script.Parent.UIKit)

local WheelView = {}

type Segment = WheelConfig.Segment

-- One item of a row's own odds list (a capsule's golems).
export type Line = { Name: string, Chance: string, Color: Color3 }
export type Row = { Id: string, Label: string, Detail: string, Chance: string, Color: Color3, Lines: { Line }? }

-- What rows() needs to know about the player (WheelController reads the State).
export type Info = {
	NoCapsules: boolean,
	Income: number, -- podium income per second (State.Income)
	Ore: WheelConfig.OreContext,
	TripleLucky: boolean,
}

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Title: TextLabel,
	Close: TextButton,
	WheelBox: Frame,
	Disc: Frame,
	Labels: { TextLabel },
	Studs: { Frame },
	Spin: TextButton,
	Status: TextLabel,
	OddsTitle: TextLabel,
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
	Result: Frame,
	ResultTitle: TextLabel,
	ResultPrize: TextLabel,
	ResultDetail: TextLabel,
	ResultOk: TextButton,
	Confetti: Frame,
	SegmentIds: { string },
	Compact: boolean,
}

export type ChipRefs = { Gui: ScreenGui, Button: TextButton, Icon: TextLabel }

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Pad: number,
	Wheel: number,
	Button: number,
	ButtonWidth: number,
	Status: number,
	Close: number,
	Row: number,
	RowGap: number,
	RowLabel: number,
	RowDetail: number,
	Columns: number,
	Line: number,
	Title: number,
	Hint: number,
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 980,
		Height = 600,
		Header = 70,
		Pad = 18,
		Wheel = 390,
		Button = 58,
		ButtonWidth = 250,
		Status = 26,
		Close = 54,
		Row = 54,
		RowGap = 4,
		RowLabel = 19,
		RowDetail = 14,
		Columns = 1,
		Line = 15,
		Title = 40,
		Hint = 16,
	},
	-- phones and TVs: 72-unit buttons are 44 pt at uiScale 0.62
	Compact = {
		Width = 1060,
		Height = 600,
		Header = 64,
		Pad = 14,
		Wheel = 380,
		Button = 72,
		ButtonWidth = 250,
		Status = 26,
		Close = 72,
		Row = 72,
		RowGap = 6,
		RowLabel = 20,
		RowDetail = 18,
		Columns = 2,
		Line = 17,
		Title = 36,
		Hint = 18,
	},
}

WheelView.Segments = 8
WheelView.BarsPerSegment = 8 -- the fan inside a segment (plus its two edge bars)
WheelView.DiscShare = 0.9 -- the disc's diameter as a share of the wheel box
WheelView.HubShare = 0.22 -- the hub's radius as a share of the disc radius
WheelView.LabelRadius = 0.6 -- the labels' distance from the centre (share of the radius)
WheelView.Turns = 5 -- full turns before the disc stops
WheelView.ChipSize = { Normal = Vector2.new(190, 54), Compact = Vector2.new(176, 72) }
WheelView.StudCount = 16
WheelView.ConfettiCount = 36
WheelView.ConfettiColors = {
	Color3.fromRGB(255, 206, 72),
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(110, 214, 92),
	Color3.fromRGB(120, 196, 255),
	Color3.fromRGB(196, 130, 255),
	Color3.fromRGB(255, 240, 220),
}

local GOLD = Color3.fromRGB(255, 196, 64)
local GOLD_DARK = Color3.fromRGB(150, 96, 20)
local SPIN_GREEN = Theme.Good
local SPIN_GREEN_DARK = Theme.GoodDark
local WAIT_GREY = Color3.fromRGB(110, 98, 92)
local WAIT_GREY_DARK = Color3.fromRGB(64, 56, 52)

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
		return `A free {name}{lucky}: {line}`
	elseif segment.Kind == "Ore" then
		local parts = {}
		for _, line in WheelConfig.oreOdds(info.Ore) do
			local ore = OreData.ById[line.Ore]
			table.insert(parts, `{if ore then ore.Name else line.Ore} {WheelView.percent(line.Chance)}`)
		end
		if #parts == 0 then
			return "Coins instead: no Rare ore in your mines yet"
		end
		return "A dirty Rare+ ore for your Ore Pen: " .. table.concat(parts, " · ")
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
			Color = if golem then Rarity.get(golem.Rarity).Color else Theme.Text,
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
			Color = segment.Color,
			Lines = if segment.Kind == "Capsule" then WheelView.capsuleLines(segment.Capsule or "", info.TripleLucky) else nil,
		})
	end
	return list
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
			return `{golemInfo.Name}!`, `A {rarity.Name} golem from a free {capsuleName}`
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
		local color = segment.Color:Lerp(Color3.new(1, 1, 1), 0.12)
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
	for i, segment in segments do
		local a0 = (i - 1) * step - step / 2
		local dx, dy = dir(a0)
		bar(disc, dx * R / 2, dy * R / 2, 0.012, R, a0, GOLD, 4)
		local mid = (i - 1) * step
		local lx, ly = dir(mid)
		local label = UIKit.label(disc, segment.Label, 15, {
			Name = "Label" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + lx * R * WheelView.LabelRadius, 0.5 + ly * R * WheelView.LabelRadius),
			Size = UDim2.fromScale(R * 0.62, R * 0.24),
			-- radial, read from the centre out (the left half from the rim in, never upside down)
			Rotation = if mid > 180 then mid + 90 else mid - 90,
			TextWrapped = true,
			ZIndex = 6,
		})
		table.insert(refs.Labels, label)
	end
	-- the hub sits on the disc (it turns with it)
	local hub = circle(disc, {
		Name = "Hub",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.HubShare, WheelView.HubShare),
		BackgroundColor3 = Theme.PanelDark,
		ZIndex = 7,
	})
	UIKit.stroke(hub, 4, GOLD)
	UIKit.label(hub, "★", 30, {
		Name = "Star",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = GOLD,
		ZIndex = 8,
	})
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
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Theme.PanelDark,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Selectable = true,
		}, refs.Odds)
		UIKit.corner(button, 10)
		local swatch = UIKit.new("Frame", {
			Name = "Swatch",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(0, 14, 1, -20),
			BackgroundColor3 = row.Color:Lerp(Color3.new(1, 1, 1), 0.12),
			BorderSizePixel = 0,
		}, button)
		UIKit.corner(swatch, 7)
		local chanceW = if refs.Compact then 78 else 72
		if refs.Compact then
			-- a tile: the label (up to two lines) and the chance beside it
			UIKit.label(button, row.Label, m.RowLabel, {
				Name = "Label",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 32, 0.5, 0),
				Size = UDim2.new(1, -(32 + chanceW + 8), 1, -8),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			})
			UIKit.label(button, row.Chance, m.RowLabel + 4, {
				Name = "Chance",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(chanceW, m.RowLabel + 8),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = GOLD,
				FontFace = Theme.TitleFont,
				TextWrapped = false,
			})
		else
			-- a row: the label and the chance, one line of what it pays, a "more" chevron
			UIKit.label(button, row.Label, m.RowLabel, {
				Name = "Label",
				Position = UDim2.fromOffset(34, 5),
				Size = UDim2.new(1, -(34 + chanceW + 30), 0, m.RowLabel + 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = false,
			})
			UIKit.label(button, row.Chance, m.RowLabel + 2, {
				Name = "Chance",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -30, 0, 4),
				Size = UDim2.fromOffset(chanceW, m.RowLabel + 6),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = GOLD,
				FontFace = Theme.TitleFont,
				TextWrapped = false,
			})
			UIKit.label(button, row.Detail, m.RowDetail, {
				Name = "Detail",
				Position = UDim2.fromOffset(34, m.RowLabel + 10),
				Size = UDim2.fromOffset(200, m.RowDetail + 6),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.TextDim,
				TextWrapped = false,
			})
		end
		UIKit.label(button, "›", 30, {
			Name = "More",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(18, 34),
			TextColor3 = Theme.TextDim,
			TextWrapped = false,
			Visible = not refs.Compact,
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
		width = math.floor(m.Width * 0.45)
	end
	local detailW = width - 12 - 34 - 34
	for id, button in refs.Rows do
		local detail = button:FindFirstChild("Detail")
		local row = refs.RowData[id]
		if detail and detail:IsA("TextLabel") and row then
			detail.Size = UDim2.fromOffset(detailW, m.RowDetail + 6)
			detail.Text = WheelView.truncate(row.Detail, m.RowDetail, detailW)
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
		local on = rowId == id
		local open = rowId == refs.InfoId
		button.BackgroundColor3 = if on or open then Theme.PanelLight else Theme.PanelDark
		local stroke = button:FindFirstChild("Lit")
		if on and not stroke then
			local made = UIKit.stroke(button, 3, GOLD)
			made.Name = "Lit"
		elseif not on and stroke then
			stroke:Destroy()
		end
	end
end

-- The details card of a row over the odds column: its whole text and, for
-- a capsule, the exact chance of every golem (two columns).
function WheelView.showInfo(refs: Refs, id: string)
	local row = refs.RowData[id]
	if not row then
		return
	end
	local m = metrics(refs.Compact)
	refs.InfoId = id
	refs.InfoSwatch.BackgroundColor3 = row.Color:Lerp(Color3.new(1, 1, 1), 0.12)
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
		UIKit.label(refs.InfoLines, text, math.max(11, size), {
			Name = "Line" .. i,
			LayoutOrder = i,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = line.Color:Lerp(Color3.new(1, 1, 1), 0.3),
			TextWrapped = false,
		})
	end
	refs.Info.Visible = true
end

function WheelView.hideInfo(refs: Refs)
	refs.InfoId = nil
	refs.Info.Visible = false
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

local function styleButton(button: TextButton, color: Color3, dark: Color3)
	button.BackgroundColor3 = color
	local holder = button.Parent
	if holder and holder:IsA("Frame") then
		holder.BackgroundColor3 = dark
	end
end

-- The SPIN! button and the countdown line: ready, waiting (seconds left)
-- or busy (a spin in flight / the wheel turning).
function WheelView.setReady(refs: Refs, ready: boolean, secondsLeft: number, busy: boolean?)
	if busy then
		refs.Spin.Text = "SPINNING..."
		styleButton(refs.Spin, WAIT_GREY, WAIT_GREY_DARK)
		refs.Status.Text = "Good luck!"
	elseif ready then
		refs.Spin.Text = "SPIN!"
		styleButton(refs.Spin, SPIN_GREEN, SPIN_GREEN_DARK)
		refs.Status.Text = "Your free spin is ready!"
	else
		refs.Spin.Text = "COME BACK LATER"
		styleButton(refs.Spin, WAIT_GREY, WAIT_GREY_DARK)
		refs.Status.Text = "Next free spin in " .. WheelView.countdown(secondsLeft)
	end
	refs.Spin:SetAttribute("Ready", ready and not busy)
end

-- Shows the prize card (the controller adds the confetti fall).
function WheelView.showResult(refs: Refs, prize: string, detail: string, color: Color3)
	refs.ResultPrize.Text = prize
	refs.ResultPrize.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.55)
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

-- Confetti pieces scattered over the top of the panel (deterministic for
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
			ZIndex = 30,
		}, refs.Confetti)
		table.insert(pieces, piece)
	end
	return pieces
end

-- Builds the wheel screen (hidden). `compact`: phones and TVs.
function WheelView.build(compact: boolean): Refs
	local m = metrics(compact)
	local gui = UIKit.screen("TerraForgeWheel", 20)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 140),
		Position = UDim2.fromOffset(0, -140),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		Active = true,
	})
	local title = UIKit.label(panel, "SPIN & WIN", m.Title, {
		Name = "Title",
		Position = UDim2.fromOffset(m.Pad + 4, 8),
		Size = UDim2.new(0.6, 0, 0, m.Header - 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
		TextWrapped = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(m.Close, m.Close),
		TextSize = 26,
	})
	-- the wheel
	local box = UIKit.new("Frame", {
		Name = "WheelBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(m.Wheel, m.Wheel),
	}, panel)
	local ring = circle(box, {
		Name = "Ring",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		ZIndex = 1,
	})
	UIKit.stroke(ring, 5, GOLD_DARK)
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(WheelView.DiscShare, WheelView.DiscShare),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, box)
	local studs: { Frame } = {}
	for i = 1, WheelView.StudCount do
		local a = (i - 1) * 360 / WheelView.StudCount + 360 / WheelView.StudCount / 2
		local dx, dy = dir(a)
		local r = (1 + WheelView.DiscShare) / 4
		local stud = circle(box, {
			Name = "Stud" .. i,
			Position = UDim2.fromScale(0.5 + dx * r, 0.5 + dy * r),
			Size = UDim2.fromScale(0.03, 0.03),
			BackgroundColor3 = if i % 2 == 0 then GOLD else Theme.Text,
			ZIndex = 9,
		})
		table.insert(studs, stud)
	end
	-- the pointer at the top: a gold diamond biting into the rim
	local pointer = UIKit.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.045),
		Size = UDim2.fromScale(0.085, 0.085),
		Rotation = 45,
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, box)
	UIKit.corner(pointer, 4)
	UIKit.stroke(pointer, 3, Theme.Outline)
	circle(box, {
		Name = "PointerPin",
		Position = UDim2.fromScale(0.5, 0.045),
		Size = UDim2.fromScale(0.03, 0.03),
		BackgroundColor3 = Theme.Outline,
		ZIndex = 11,
	})
	local spin = UIKit.button(panel, "SPIN!", SPIN_GREEN, SPIN_GREEN_DARK, {
		Name = "Spin",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(m.ButtonWidth, m.Button),
		TextSize = if compact then 30 else 28,
		FontFace = Theme.TitleFont,
	})
	local status = UIKit.label(panel, "", 18, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(m.ButtonWidth + 120, m.Status),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	-- the odds
	local oddsTitle = UIKit.label(panel, "ODDS", 24, {
		Name = "OddsTitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local odds = UIKit.new("ScrollingFrame", {
		Name = "Odds",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, panel)
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
	local more = UIKit.label(panel, "▼ more odds below", m.Hint, {
		Name = "More",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.PanelDark,
		TextColor3 = GOLD,
		TextWrapped = false,
		Visible = false,
		ZIndex = 8,
	})
	UIKit.corner(more, 8)
	-- a row's details card over the odds column
	local info = UIKit.panel(panel, {
		Name = "Info",
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		Active = true,
		ZIndex = 12,
	})
	local infoSwatch = UIKit.new("Frame", {
		Name = "Swatch",
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(14, 32),
		BorderSizePixel = 0,
		ZIndex = 13,
	}, info)
	UIKit.corner(infoSwatch, 7)
	local infoTitle = UIKit.label(info, "", m.RowLabel + 4, {
		Name = "Title",
		Position = UDim2.fromOffset(40, 12),
		Size = UDim2.new(1, -(40 + m.Close + 110), 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 13,
	})
	local infoChance = UIKit.label(info, "", m.RowLabel + 6, {
		Name = "Chance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(m.Close + 22), 0, 12),
		Size = UDim2.fromOffset(100, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = GOLD,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 13,
	})
	local infoClose = UIKit.button(info, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(m.Close, m.Close),
		TextSize = 24,
		ZIndex = 14,
	})
	local infoText = UIKit.label(info, "", m.RowDetail + 2, {
		Name = "Text",
		Position = UDim2.fromOffset(16, m.Close + 16),
		Size = UDim2.new(1, -32, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
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
	local hint = UIKit.label(panel, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	-- the prize card and the confetti over the panel
	local confetti = UIKit.new("Frame", {
		Name = "Confetti",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 30,
	}, panel)
	local result = UIKit.panel(panel, {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if compact then 560 else 500, if compact then 290 else 260),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
	})
	local resultTitle = UIKit.label(result, "YOU WON!", 40, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 46),
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
		ZIndex = 21,
	})
	local resultPrize = UIKit.label(result, "", 32, {
		Name = "Prize",
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 0, 42),
		ZIndex = 21,
	})
	local resultDetail = UIKit.label(result, "", if compact then 20 else 18, {
		Name = "Detail",
		Position = UDim2.fromOffset(20, 112),
		Size = UDim2.new(1, -40, 0, 50),
		TextColor3 = Theme.TextDim,
		ZIndex = 21,
	})
	local ok = UIKit.button(result, "OK", Theme.Accent, Theme.AccentDark, {
		Name = "Ok",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(180, if compact then 72 else 56),
		TextSize = 26,
		ZIndex = 22,
	})
	local refs: Refs = {
		Gui = gui,
		Dim = dim,
		Panel = panel,
		Title = title,
		Close = close,
		WheelBox = box,
		Disc = disc,
		Labels = {},
		Studs = studs,
		Spin = spin,
		Status = status,
		OddsTitle = oddsTitle,
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
	return refs
end

-- Fits the panel into `maxWidth` x `maxHeight` design units (the screen
-- below the top bar) and places the wheel, the button and the odds.
function WheelView.layout(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local width = math.min(m.Width, maxWidth - 16)
	local height = math.min(m.Height, maxHeight - 12)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	local pad = m.Pad
	local below = m.Button + m.Status + pad + 10
	local wheel = math.floor(math.min(m.Wheel, height - m.Header - below - pad, width * 0.46))
	refs.WheelBox.Size = UDim2.fromOffset(wheel, wheel)
	local leftWidth = math.max(wheel, m.ButtonWidth) + 2 * pad
	refs.WheelBox.Position = UDim2.fromOffset(math.floor((leftWidth - wheel) / 2), m.Header)
	local buttonY = m.Header + wheel + 10
	local spinHolder = refs.Spin.Parent :: Frame
	spinHolder.Position = UDim2.fromOffset(math.floor(leftWidth / 2), buttonY)
	refs.Status.Position = UDim2.fromOffset(math.floor(leftWidth / 2), buttonY + m.Button + 6)
	local hintH = m.Hint + 10
	local oddsX = leftWidth + 4
	local oddsW = width - oddsX - pad
	-- compact: "ODDS" and the hint share the header row (left of the X) and
	-- the tiles start under the X, down to the panel's bottom: all 8 fit
	local titleY = if refs.Compact then math.floor((m.Header - 30) / 2) + 4 else m.Header - 6
	local listTop = if refs.Compact then 10 + m.Close + 6 else m.Header + 28
	refs.OddsTitle.Position = UDim2.fromOffset(oddsX, titleY)
	refs.OddsTitle.Size = UDim2.fromOffset(if refs.Compact then 80 else oddsW, 30)
	local oddsH = if refs.Compact then height - listTop - 10 else height - listTop - hintH - 6
	refs.Odds.Position = UDim2.fromOffset(oddsX, listTop)
	refs.Odds.Size = UDim2.fromOffset(oddsW, oddsH)
	local grid = refs.Odds:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(math.floor((oddsW - 12 - m.RowGap) / 2), m.Row)
	end
	refs.More.Position = UDim2.fromOffset(oddsX + math.floor((oddsW - 12) / 2), listTop + oddsH)
	refs.More.Size = UDim2.fromOffset(math.min(oddsW - 12, 260), m.Hint + 10)
	-- the details card covers the odds column (title included)
	-- (compact: over the whole panel, its X where the panel's X is)
	if refs.Compact then
		refs.Info.Position = UDim2.fromOffset(0, 0)
		refs.Info.Size = UDim2.fromOffset(width, height)
	else
		refs.Info.Position = UDim2.fromOffset(oddsX - 4, m.Header - 8)
		refs.Info.Size = UDim2.fromOffset(oddsW + 4, height - (m.Header - 8) - hintH - 2)
	end
	WheelView.fitRows(refs)
	if refs.Compact then
		refs.Hint.AnchorPoint = Vector2.new(0, 0)
		refs.Hint.TextXAlignment = Enum.TextXAlignment.Left
		refs.Hint.Position = UDim2.fromOffset(oddsX + 86, titleY + 4)
		refs.Hint.Size = UDim2.fromOffset(math.max(60, width - (oddsX + 86) - m.Close - 24), m.Hint + 4)
	else
		refs.Hint.AnchorPoint = Vector2.new(1, 1)
		refs.Hint.TextXAlignment = Enum.TextXAlignment.Right
		refs.Hint.Position = UDim2.new(1, -pad, 1, -6)
		refs.Hint.Size = UDim2.fromOffset(oddsW, m.Hint + 4)
	end
	-- the prize card covers the odds column: the wheel stays in view, the
	-- won segment under the pointer
	local cardW = math.min(if refs.Compact then 560 else 500, oddsW)
	local cardH = math.min(if refs.Compact then 290 else 260, height - m.Header - 12)
	refs.Result.Size = UDim2.fromOffset(cardW, cardH)
	refs.Result.Position = UDim2.fromOffset(oddsX + math.floor(oddsW / 2), m.Header + math.floor((height - m.Header) / 2) - 6)
	-- label text follows the wheel's size
	local textSize = math.max(12, math.floor(wheel * (if refs.Compact then 0.046 else 0.04)))
	for _, label in refs.Labels do
		label.TextSize = textSize
	end
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
-- uiScale layout, as on a screen wider than TeleportView.NarrowWidth).
function WheelView.buildChip(uiScale: number, screenWidth: number?): ChipRefs
	local gui = UIKit.screen("TerraForgeFreeSpin", 4)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local compact = uiScale <= TeleportView.CompactScale
	local size = WheelView.chipSize(uiScale)
	local offset = WheelView.chipOffset(uiScale, screenWidth)
	local button = UIKit.button(gui, "", Color3.fromRGB(255, 120, 60), Color3.fromRGB(170, 60, 24), {
		Name = "FreeSpin",
		Position = UDim2.new(0.5, offset.X, 0, offset.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	local icon = UIKit.label(button, "🎡", 30, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		TextWrapped = false,
	})
	UIKit.label(button, "FREE SPIN!", if compact then 24 else 22, {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 48, 0.5, 0),
		Size = UDim2.new(1, -54, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	return { Gui = gui, Button = button, Icon = icon }
end

-- Should the FREE SPIN! chip show: the spin is ready, the wheel screen is
-- closed, no spin is in flight, nothing else has the screen (the cleaning
-- minigame, build mode, the Foundry moment: the HUD is hidden) and the
-- tutorial bubble isn't in the chip's spot (`tutorialInTopRow`: on touch
-- screens the bubble sits right of the teleport bar too; it comes first)?
function WheelView.chipVisible(
	ready: boolean,
	isOpen: boolean,
	spinning: boolean,
	busyScreen: boolean,
	tutorialInTopRow: boolean?
): boolean
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
