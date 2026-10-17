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
	  odds    one row per segment: its color, label, the exact chance and
	          what it pays THIS player (coins at their income, the ore
	          prize's own odds, the capsule's rarity odds with their Triple
	          Lucky), from rows() (pure, tested)
	  result  the prize card over the panel ("YOU WON!") with an OK button
	          and confetti pieces the controller lets fall
	  chip    its own ScreenGui: "FREE SPIN!" in the HUD's top row, right of
	          the quick-teleport bar (TeleportView's width), only while the
	          free spin is ready

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

export type Row = { Id: string, Label: string, Detail: string, Chance: string, Color: Color3 }

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
	Rows: { [string]: Frame },
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

export type ChipRefs = { Gui: ScreenGui, Button: TextButton }

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
	RowLabel: number,
	RowDetail: number,
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
		Row = 66,
		RowLabel = 20,
		RowDetail = 15,
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
		Row = 82,
		RowLabel = 24,
		RowDetail = 18,
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
		return `+{WheelView.duration(segment.Seconds or 0)} of {name}: {what} (up to {WheelView.duration(BoostConfig.MaxStackSeconds)})`
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
		})
	end
	return list
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
		if seconds <= 0 then
			return name, `Already full: boosts stack up to {WheelView.duration(BoostConfig.MaxStackSeconds)}`
		end
		local what = if boost and boost.Target == "Capsules" then "Rarer golems from capsules" else "Rarer ores from rocks"
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
		return `{Format.money(coins or 0)} coins`, `Your golem inventory is full: coins instead of a {capsuleName}`
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

-- The odds rows (one per segment; the list scrolls).
function WheelView.setRows(refs: Refs, rows: { Row })
	local m = metrics(refs.Compact)
	for _, child in refs.Odds:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(refs.Rows)
	for i, row in rows do
		local frame = UIKit.new("Frame", {
			Name = row.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, -12, 0, m.Row),
			BackgroundColor3 = Theme.PanelDark,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, refs.Odds)
		UIKit.corner(frame, 10)
		local swatch = UIKit.new("Frame", {
			Name = "Swatch",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(0, 14, 1, -20),
			BackgroundColor3 = row.Color:Lerp(Color3.new(1, 1, 1), 0.12),
			BorderSizePixel = 0,
		}, frame)
		UIKit.corner(swatch, 7)
		UIKit.label(frame, row.Label, m.RowLabel, {
			Name = "Label",
			Position = UDim2.fromOffset(34, 6),
			Size = UDim2.new(1, -120, 0, m.RowLabel + 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
		})
		UIKit.label(frame, row.Chance, m.RowLabel + 2, {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 5),
			Size = UDim2.fromOffset(84, m.RowLabel + 6),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = GOLD,
			FontFace = Theme.TitleFont,
		})
		UIKit.label(frame, row.Detail, m.RowDetail, {
			Name = "Detail",
			Position = UDim2.fromOffset(34, m.RowLabel + 10),
			Size = UDim2.new(1, -46, 0, m.Row - m.RowLabel - 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.TextDim,
			TextWrapped = true,
		})
		refs.Rows[row.Id] = frame
	end
	refs.Odds.CanvasSize = UDim2.fromOffset(0, #rows * (m.Row + 8))
end

-- Lights a row (the segment the wheel stopped on), nil = none.
function WheelView.highlight(refs: Refs, id: string?)
	for rowId, frame in refs.Rows do
		local on = rowId == id
		frame.BackgroundColor3 = if on then Theme.PanelLight else Theme.PanelDark
		local stroke = frame:FindFirstChild("Lit")
		if on and not stroke then
			local s = UIKit.stroke(frame, 3, GOLD)
			s.Name = "Lit"
		elseif not on and stroke then
			stroke:Destroy()
		end
	end
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
		Selectable = true,
	}, panel)
	UIKit.list(odds, Enum.FillDirection.Vertical, 8)
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
	refs.OddsTitle.Position = UDim2.fromOffset(oddsX, m.Header - 6)
	refs.OddsTitle.Size = UDim2.fromOffset(oddsW, 30)
	refs.Odds.Position = UDim2.fromOffset(oddsX, m.Header + 28)
	refs.Odds.Size = UDim2.fromOffset(oddsW, height - m.Header - 28 - hintH - 6)
	refs.Hint.Position = UDim2.new(1, -pad, 1, -6)
	refs.Hint.Size = UDim2.fromOffset(oddsW, m.Hint + 4)
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
-- (TeleportView's width at this uiScale), design units from the top centre.
function WheelView.chipOffset(uiScale: number): Vector2
	local layout = TeleportView.layout(uiScale)
	local barWidth = TeleportView.barWidth(layout, 3) + 44 + layout.Gap
	return Vector2.new(math.floor(barWidth / 2) + 14, 10)
end

function WheelView.buildChip(uiScale: number): ChipRefs
	local gui = UIKit.screen("TerraForgeFreeSpin", 4)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local compact = uiScale <= TeleportView.CompactScale
	local size = if compact then WheelView.ChipSize.Compact else WheelView.ChipSize.Normal
	local offset = WheelView.chipOffset(uiScale)
	local button = UIKit.button(gui, "", Color3.fromRGB(255, 120, 60), Color3.fromRGB(170, 60, 24), {
		Name = "FreeSpin",
		Position = UDim2.new(0.5, offset.X, 0, offset.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	UIKit.label(button, "🎡", 30, {
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
	return { Gui = gui, Button = button }
end

-- Moves the chip for a new uiScale (phone <-> big screen).
function WheelView.placeChip(chip: ChipRefs, uiScale: number)
	local compact = uiScale <= TeleportView.CompactScale
	local size = if compact then WheelView.ChipSize.Compact else WheelView.ChipSize.Normal
	local offset = WheelView.chipOffset(uiScale)
	local holder = chip.Button.Parent
	if holder and holder:IsA("Frame") then
		holder.Position = UDim2.new(0.5, offset.X, 0, offset.Y)
		holder.Size = UDim2.fromOffset(size.X, size.Y)
	end
end

return WheelView
