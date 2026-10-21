--[[
	The player LEVEL on screen (pure builders + poses; LevelController plays
	them, the Lune previews pose them frame by frame). The "make level ups
	juicy" reel the owner sent (2026-10-21), in five steps:
	  1 FILL THE BAR   XP orbs fly from the character into the bar, the
	                   fill follows smoothly (setBar with a shown fraction)
	  2 BUILD UP       past GlowFrom the bar glows and pulses (poseGlow)
	  3 BURST          the world burst at the character (Effects/LevelBurst)
	                   and a white flash
	  4 BIG TEXT       LEVEL UP! pops in over light rays (poseMoment)
	  5 THE REWARD     the reward rows slide in and count up (+$ coins,
	                   +1 % income; every 10th level a MILESTONE x5 row)

	  build()  -> View: Gui (ScreenGui "TerraForgeLevel": the bar at the
	              bottom centre over the carry slots, the moment over the
	              middle) and Orbs (ScreenGui "TerraForgeLevelOrbs", no
	              UIScale: orbs fly in screen pixels)
	Pop look (PopTheme): chunky white text with a black edge, painted faces.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local LevelView = {}

LevelView.BarWidth = 380
LevelView.BarHeight = 30
LevelView.Badge = 58
LevelView.BarBottom = 128 -- design units from the bottom edge (over the carry slots and their label)
LevelView.GlowFrom = 0.75 -- the bar starts to glow from this full
LevelView.MomentSeconds = 3.6
LevelView.MomentTop = 40 -- the moment's top (design units): over the character, not on it
LevelView.RowTop = 196
LevelView.RowGap = 56
LevelView.OrbCount = 14
LevelView.OrbSize = 16 -- screen pixels at UI scale 1
LevelView.FillColor = { Color3.fromRGB(255, 226, 90), Color3.fromRGB(255, 128, 24) }
LevelView.GlowColor = Color3.fromRGB(255, 150, 40)

export type Row = { Holder: Frame, Label: TextLabel, Amount: TextLabel, Scale: UIScale }
export type View = {
	Gui: ScreenGui,
	Orbs: ScreenGui,
	OrbList: { Frame },
	Bar: Frame,
	BarScale: UIScale,
	Track: Frame,
	Fill: Frame,
	Glow: Frame,
	XpText: TextLabel,
	Badge: Frame,
	BadgeScale: UIScale,
	BadgeLevel: TextLabel,
	Moment: Frame,
	Flash: Frame,
	Rays: Frame,
	Title: TextLabel,
	TitleScale: UIScale,
	Subtitle: TextLabel,
	SubtitleScale: UIScale,
	Rows: { Row },
	Fit: number, -- the moment's size share (fit(): short phone screens)
}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- 0..1 over [a, b]
local function span(t: number, a: number, b: number): number
	return clamp01((t - a) / (b - a))
end
LevelView.span = span

local function easeOutBack(x: number): number
	local c1, c3 = 1.9, 2.9
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function easeInBack(x: number): number
	return 2.7 * x * x * x - 1.7 * x * x
end

local function row(parent: Instance, name: string, paint: string, order: number): Row
	local holder = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, LevelView.RowTop + (order - 1) * LevelView.RowGap),
		Size = UDim2.fromOffset(310, 48),
		ZIndex = 6,
	}, parent)
	Pop.face(holder, paint, 10)
	local scale = UIKit.new("UIScale", { Scale = 0 }, holder)
	local label = Pop.text(holder, "", 22, {
		Name = "Label",
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0.55, -16, 0.7, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true, -- "+1% INCOME" fits its half
		ZIndex = 7,
	})
	label.Position = UDim2.new(0, 16, 0.5, 0)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, label)
	local amount = Pop.text(holder, "", 30, {
		Name = "Amount",
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 2),
		Size = UDim2.new(0.45, -16, 0.75, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = true, -- "MAX 50%" and "+$1.35M" fit
		ZIndex = 7,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14 }, amount)
	return { Holder = holder, Label = label, Amount = amount, Scale = scale }
end

function LevelView.build(): View
	local gui = UIKit.screen("TerraForgeLevel", 7)
	gui:SetAttribute("TerraForge", true)

	-- the bar: a round level badge on the left, the XP track
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, LevelView.Badge / 2, 1, -LevelView.BarBottom),
		Size = UDim2.fromOffset(LevelView.BarWidth, LevelView.BarHeight),
	}, gui)
	local barScale = UIKit.new("UIScale", { Scale = 1 }, bar)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 22, 1, 22),
		BackgroundColor3 = LevelView.GlowColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, bar)
	UIKit.corner(glow, 22)
	local track = UIKit.new("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	}, bar)
	UIKit.corner(track, 10)
	Pop.border(track, PopTheme.Edge)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, track)
	UIKit.corner(fill, 10)
	UIKit.new("UIGradient", { Color = ColorSequence.new(LevelView.FillColor[1], LevelView.FillColor[2]), Rotation = 90 }, fill)
	-- a glossy streak over the top half of the fill
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(1, -8, 0.3, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, fill)
	UIKit.corner(shine, 4)
	local xpText = Pop.text(track, "0 / 80 XP", 17, {
		Name = "XpText",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	})

	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(LevelView.Badge, LevelView.Badge),
		ZIndex = 7,
	}, bar)
	Pop.face(badge, "Purple", LevelView.Badge)
	local badgeScale = UIKit.new("UIScale", { Scale = 1 }, badge)
	Pop.text(badge, "LV", 13, {
		Name = "Lv",
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 8,
	})
	local badgeLevel = Pop.text(badge, "1", 26, {
		Name = "Level",
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 8,
	})

	-- the moment: flash, rays, LEVEL UP!, the level, the reward rows
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, gui)
	local moment = UIKit.new("Frame", {
		Name = "Moment",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, LevelView.MomentTop),
		Size = UDim2.fromOffset(600, 420),
		Visible = false,
	}, gui)
	local rays = Pop.rays(moment, UDim2.fromOffset(300, 92), 9, 250, 0.6, 2)
	for _, ray in rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
		end
	end
	local title = Pop.title(moment, "LEVEL UP!", 84, "Gold", {
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(300, 92),
		Size = UDim2.fromOffset(600, 100),
		ZIndex = 5,
	})
	local edge = title:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = 6
	end
	local titleScale = UIKit.new("UIScale", { Scale = 0 }, title)
	local subtitle = Pop.text(moment, "LEVEL 2", 34, {
		Name = "Subtitle",
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(300, 162),
		Size = UDim2.fromOffset(400, 44),
		ZIndex = 5,
	})
	local subtitleScale = UIKit.new("UIScale", { Scale = 0 }, subtitle)
	local rows = {
		row(moment, "Coins", "Green", 1),
		row(moment, "Income", "Blue", 2),
		row(moment, "Milestone", "Pink", 3),
	}
	rows[1].Label.Text = "COINS"
	rows[2].Label.Text = "INCOME"
	rows[3].Label.Text = "MILESTONE"

	-- the orbs: their own gui without a UIScale (screen pixels)
	local orbs = UIKit.new("ScreenGui", {
		Name = "TerraForgeLevelOrbs",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 8,
	})
	local orbList = {}
	for i = 1, LevelView.OrbCount do
		local orb = UIKit.new("Frame", {
			Name = "Orb" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(LevelView.OrbSize, LevelView.OrbSize),
			BackgroundColor3 = Color3.fromRGB(255, 214, 70),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		}, orbs)
		UIKit.corner(orb, LevelView.OrbSize)
		UIKit.new("UIStroke", { Name = "Border", Color = Color3.fromRGB(255, 120, 20), Thickness = 2 }, orb)
		local core = UIKit.new("Frame", {
			Name = "Core",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.42, 0.4),
			Size = UDim2.fromScale(0.45, 0.45),
			BackgroundColor3 = Color3.fromRGB(255, 255, 230),
			BorderSizePixel = 0,
			ZIndex = 3,
		}, orb)
		UIKit.corner(core, LevelView.OrbSize)
		table.insert(orbList, orb)
	end

	return {
		Gui = gui,
		Orbs = orbs,
		OrbList = orbList,
		Bar = bar,
		BarScale = barScale,
		Track = track,
		Fill = fill,
		Glow = glow,
		XpText = xpText,
		Badge = badge,
		BadgeScale = badgeScale,
		BadgeLevel = badgeLevel,
		Moment = moment,
		Flash = flash,
		Rays = rays,
		Fit = 1,
		Title = title,
		TitleScale = titleScale,
		Subtitle = subtitle,
		SubtitleScale = subtitleScale,
		Rows = rows,
	}
end

-- The bar: level, the shown fill (0..1) and the XP text (only what changed is written).
function LevelView.setBar(view: View, level: number, shown: number, xp: number, need: number)
	local text = tostring(level)
	if view.BadgeLevel.Text ~= text then
		view.BadgeLevel.Text = text
		view.BadgeLevel.TextSize = if level >= 100 then 21 else 26
	end
	local fill = UDim2.fromScale(clamp01(shown), 1)
	if view.Fill.Size ~= fill then
		view.Fill.Size = fill
		view.Fill.Visible = shown > 0.004
	end
	local xpText = `{Format.commas(math.floor(xp))} / {Format.commas(need)} XP`
	if view.XpText.Text ~= xpText then
		view.XpText.Text = xpText
	end
end

-- Step 2: the build-up glow past GlowFrom, pulsing (`clock` in seconds);
-- `reduced` (Reduce motion): a steady glow, the bar never grows.
function LevelView.poseGlow(view: View, shown: number, clock: number, reduced: boolean?)
	local k = clamp01((shown - LevelView.GlowFrom) / (1 - LevelView.GlowFrom))
	local pulse = if reduced then 0.5 else 0.5 + 0.5 * math.sin(clock * (6 + 8 * k))
	view.Glow.BackgroundTransparency = 1 - k * (0.35 + 0.35 * pulse)
	local grow = if reduced then 10 * k else 14 * k * pulse
	view.Glow.Size = UDim2.new(1, 14 + grow, 1, 14 + grow)
	view.BarScale.Scale = if reduced then 1 else 1 + 0.035 * k * pulse
end

-- An orb `u` (0..1) of the way from `from` to `to` (screen pixels) on an arc.
function LevelView.poseOrb(orb: Frame, from: Vector2, to: Vector2, u: number, scale: number, seed: number)
	if u <= 0 or u >= 1 then
		orb.Visible = false
		return
	end
	local e = u * u * (3 - 2 * u)
	local mid = (from + to) / 2 + Vector2.new(math.sin(seed * 12.9) * 160, -120 - 60 * math.abs(math.cos(seed * 7.3))) * scale
	local a = from:Lerp(mid, e)
	local b = mid:Lerp(to, e)
	local p = a:Lerp(b, e)
	local s = LevelView.OrbSize * scale * (if u < 0.15 then 0.4 + 4 * u else 1 - 0.35 * span(u, 0.7, 1))
	orb.Visible = true
	orb.Position = UDim2.fromOffset(p.X, p.Y)
	orb.Size = UDim2.fromOffset(s, s)
end

-- Increase: the income share this level added (0 past LevelConfig.BonusCap)
export type Moment = { Level: number, Coins: number, Bonus: number, Increase: number?, Milestone: boolean }

local function fadeText(label: TextLabel, alpha: number)
	label.TextTransparency = 1 - alpha
	local edge = label:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Transparency = 1 - alpha
	end
end

-- The INCOME row's words: "+1% INCOME" and the total, or MAX at the cap.
function LevelView.incomeText(m: Moment): (string, string)
	local total = math.floor(m.Bonus * 100 + 0.5)
	local increase = m.Increase
	if increase ~= nil and increase <= 0 then
		return "INCOME", string.format("MAX %d%%", total)
	end
	local step = math.floor((increase or 0.01) * 100 + 0.5)
	return string.format("+%d%% INCOME", step), string.format("%d%%", total)
end

-- Steps 3-5 at `t` seconds into the moment (0..MomentSeconds). `reduced`
-- (Reduce motion): no flash, no rays, no pop or wobble: the words fade in
-- and out at full size, the rows simply show, the numbers don't count.
function LevelView.poseMoment(view: View, t: number, m: Moment, reduced: boolean?)
	local total = LevelView.MomentSeconds
	view.Moment.Visible = t >= 0 and t < total
	view.Subtitle.Text = "LEVEL " .. Format.commas(m.Level)
	local rows = { { At = 0.85, Kind = "Coins" }, { At = 1.2, Kind = "Income" } }
	if m.Milestone then
		table.insert(rows, { At = 1.55, Kind = "Milestone" })
	end
	local incomeLabel, incomeAmount = LevelView.incomeText(m)
	if reduced then
		view.Flash.BackgroundTransparency = 1
		view.Rays.Visible = false
		local alpha = span(t, 0, 0.3) * (1 - span(t, total - 0.4, total))
		view.TitleScale.Scale = 1
		view.Title.Rotation = 0
		fadeText(view.Title, alpha)
		view.SubtitleScale.Scale = 1
		fadeText(view.Subtitle, alpha)
		for i, r in view.Rows do
			local spec = rows[i]
			r.Holder.Visible = spec ~= nil and t >= spec.At and t < total - 0.4
			r.Scale.Scale = 1
			r.Holder.Position = UDim2.new(0.5, 0, 0, (LevelView.RowTop + (i - 1) * LevelView.RowGap) * view.Fit)
			if spec and spec.Kind == "Coins" then
				r.Amount.Text = "+" .. Format.money(math.floor(m.Coins))
			elseif spec and spec.Kind == "Income" then
				r.Label.Text = incomeLabel
				r.Amount.Text = incomeAmount
			elseif spec then
				r.Amount.Text = "x5 COINS"
			end
		end
		view.BadgeScale.Scale = 1
		return
	end
	view.Rays.Visible = true
	fadeText(view.Title, 1)
	fadeText(view.Subtitle, 1)
	-- the white flash
	view.Flash.BackgroundTransparency = if t < 0 then 1 else 0.35 + 0.65 * span(t, 0, 0.3)
	-- out: everything shrinks away at the end
	local out = easeInBack(span(t, total - 0.45, total))
	-- LEVEL UP!: pops in with an overshoot and a wobble, breathes while it stays
	local pop = easeOutBack(span(t, 0.05, 0.5))
	local breathe = 1 + 0.04 * math.sin(t * 5) * span(t, 0.5, 0.8)
	view.TitleScale.Scale = math.max(pop * breathe * (1 - out), 0)
	view.Title.Rotation = -10 * (1 - easeOutCubic(span(t, 0.05, 0.6))) + 2 * math.sin(t * 3) * span(t, 0.6, 1)
	-- the rays: fade in, turn slowly
	view.Rays.Rotation = t * 22
	local raysSize = 500 * view.Fit * pop * (1 - out)
	view.Rays.Size = UDim2.fromOffset(raysSize, raysSize)
	-- the level under it
	view.SubtitleScale.Scale = math.max(easeOutBack(span(t, 0.45, 0.8)) * (1 - out), 0)
	-- the reward rows: slide in one after another, the numbers count up
	for i, r in view.Rows do
		local spec = rows[i]
		if not spec then
			r.Holder.Visible = false
			continue
		end
		r.Holder.Visible = true
		local inK = easeOutBack(span(t, spec.At, spec.At + 0.35))
		r.Scale.Scale = math.max(inK * (1 - out), 0)
		r.Holder.Position = UDim2.new(
			0.5,
			80 * (1 - easeOutCubic(span(t, spec.At, spec.At + 0.35))),
			0,
			(LevelView.RowTop + (i - 1) * LevelView.RowGap) * view.Fit
		)
		local count = easeOutCubic(span(t, spec.At + 0.15, spec.At + 0.95))
		if spec.Kind == "Coins" then
			r.Amount.Text = "+" .. Format.money(math.floor(m.Coins * count))
			r.Amount.TextColor3 = PopTheme.Ink
		elseif spec.Kind == "Income" then
			r.Label.Text = incomeLabel
			r.Amount.Text = incomeAmount
		else
			r.Amount.Text = "x5 COINS"
		end
	end
	-- the badge pumps as the new number lands
	view.BadgeScale.Scale = 1 + 0.45 * math.sin(math.pi * span(t, 0, 0.45))
end

-- The moment's size share for a gui `designHeight` units tall (under the inset):
-- the rewards end above the bar; 1 on a PC screen, ~0.7 on a 568 x 320 phone.
function LevelView.fitFor(designHeight: number): number
	local content = LevelView.RowTop + 2 * LevelView.RowGap + 48 -- three rows (a milestone)
	local room = designHeight - LevelView.BarBottom - LevelView.BarHeight - 12 - LevelView.MomentTop
	return math.clamp(room / content, 0.5, 1)
end

-- Lays the moment out at size share `k` (only when it changed).
function LevelView.fit(view: View, k: number)
	if math.abs(view.Fit - k) < 0.005 then
		return
	end
	view.Fit = k
	view.Title.Position = UDim2.fromOffset(300, 92 * k)
	view.Title.Size = UDim2.fromOffset(600, 100 * k)
	view.Title.TextSize = math.floor(84 * k)
	view.Subtitle.Position = UDim2.fromOffset(300, 162 * k)
	view.Subtitle.Size = UDim2.fromOffset(400, 44 * k)
	view.Subtitle.TextSize = math.floor(34 * k)
	view.Rays.Position = UDim2.fromOffset(300, 92 * k)
	for _, r in view.Rows do
		r.Holder.Size = UDim2.fromOffset(310 * k, 48 * k)
	end
end

-- Hides the moment (and the flash) between level ups.
function LevelView.hideMoment(view: View)
	view.Moment.Visible = false
	view.Flash.BackgroundTransparency = 1
	view.BadgeScale.Scale = 1
end

return LevelView
