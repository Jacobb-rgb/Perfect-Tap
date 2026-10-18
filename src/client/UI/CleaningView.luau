--[[
	Cleaning minigame UI (pure builder).
	  top      step banner (STEP 1/3 · CHISEL + instruction) and step pips
	  left     Leave button
	  right    live QUALITY meter (grade zones) + chips counter
	  center   feedback pop text ("Perfect!", "Slow down!", "CHIP!")
	  bottom   device hint, polish speed gauge (green = CleaningScoring band), "Easy polish" toggle
	  card     grade reveal (grade, ore, value, stars, details, Collect)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local ItemData = require(Shared.Config.ItemData)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local UIKit = require(script.Parent.UIKit)

local CleaningView = {}

export type Refs = {
	Gui: ScreenGui,
	Banner: Frame,
	PipRow: Frame,
	StepLabel: TextLabel,
	Title: TextLabel,
	Instruction: TextLabel,
	Pips: { Frame },
	Leave: TextButton,
	Meter: Frame,
	MeterFill: Frame,
	MeterMarker: Frame,
	MeterGrade: TextLabel,
	Chips: TextLabel,
	Feedback: TextLabel,
	Hint: TextLabel,
	Progress: TextLabel,
	Gauge: Frame,
	GaugeNeedle: Frame,
	Shine: Frame,
	ShineFill: Frame,
	RubToggle: TextButton,
	Cursor: Frame,
	Card: Frame,
	CardGrade: TextLabel,
	CardOre: TextLabel,
	CardValue: TextLabel,
	CardStars: TextLabel,
	CardDetail: TextLabel,
	CardStreak: TextLabel,
	Collect: TextButton,
	Flash: Frame,
}

local METER_HEIGHT = 300

-- Design-unit layout numbers the controller needs to keep the ore in view.
CleaningView.BannerBottom = 152 -- banner + step pips, from the top
CleaningView.BottomReserved = 150 -- progress / speed gauge / shine bar, from the bottom
CleaningView.CompactWidth = 300 -- banner width in compact mode (top-left, under Leave)

export type Options = {
	Touch: boolean?, -- bigger buttons and text for fingers
}

function CleaningView.build(options: Options?): Refs
	local touch = options ~= nil and options.Touch == true
	local gui = UIKit.screen("TerraForgeCleaning", 20)

	-- full-screen flash (white/rarity colored on cracks and the reveal)
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	-- step banner
	local banner = UIKit.panel(gui, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(470, 108),
	})
	local stepLabel = UIKit.label(banner, "STEP 1 / 3", 16, {
		Name = "Step",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.TextDim,
	})
	local title = UIKit.label(banner, "CHISEL", 40, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	local instruction = UIKit.label(banner, "Trace the glowing line", 18, {
		Name = "Instruction",
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.new(1, -24, 0, 30),
	})
	local pipRow = UIKit.new("Frame", {
		Name = "Pips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(120, 18),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(pipRow, Enum.FillDirection.Horizontal, 12, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local pips = {}
	for i = 1, 3 do
		local pip = UIKit.new("Frame", {
			Name = "Pip" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Theme.PanelDark,
			BorderSizePixel = 0,
		}, pipRow)
		UIKit.corner(pip, 9)
		UIKit.stroke(pip, 2.5)
		table.insert(pips, pip)
	end

	-- leave
	local leave = UIKit.button(gui, "Leave", Theme.Bad, Theme.BadDark, {
		Name = "Leave",
		Position = UDim2.fromOffset(16, 16),
		Size = if touch then UDim2.fromOffset(150, 70) else UDim2.fromOffset(118, 48),
		TextSize = if touch then 26 else 20,
	})

	-- quality meter
	local meter = UIKit.panel(gui, {
		Name = "Quality",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(92, METER_HEIGHT + 96),
	})
	UIKit.label(meter, "QUALITY", 16, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.TextDim,
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 32),
		Size = UDim2.fromOffset(34, METER_HEIGHT),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, meter)
	UIKit.corner(track, 10)
	UIKit.stroke(track, 2.5)
	-- grade zones (bottom = Rough, top = Flawless)
	for i, grade in ItemData.Grades do
		local nextGrade = ItemData.Grades[i + 1]
		local from = grade.MinScore
		local to = if nextGrade then nextGrade.MinScore else 1
		UIKit.new("Frame", {
			Name = "Zone" .. grade.Id,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1 - from),
			Size = UDim2.fromScale(0.28, to - from),
			BackgroundColor3 = grade.Color,
			BorderSizePixel = 0,
		}, track)
	end
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.34, 0, 1, 0),
		Size = UDim2.new(0.66, 0, 0, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, track)
	UIKit.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	local marker = UIKit.new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 8, 0, 4),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
	}, track)
	local meterGrade = UIKit.label(meter, "Rough", 16, {
		Name = "Grade",
		Position = UDim2.fromOffset(0, METER_HEIGHT + 38),
		Size = UDim2.new(1, 0, 0, 20),
	})
	local chips = UIKit.label(meter, "Chips: 0", if touch then 18 else 15, {
		Name = "Chips",
		Position = UDim2.fromOffset(0, METER_HEIGHT + 62),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.TextDim,
	})

	-- feedback pop + progress
	local feedback = UIKit.label(gui, "", 44, {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(600, 60),
		FontFace = Theme.TitleFont,
		TextTransparency = 1,
	})
	UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, feedback)
	local progress = UIKit.label(gui, "", 20, {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(500, 26),
		TextColor3 = Theme.Accent,
	})
	local hint = UIKit.label(gui, "", if touch then 19 else 17, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(640, 24),
		TextColor3 = Theme.TextDim,
	})

	-- polish: speed gauge + shine
	local gauge = UIKit.panel(gui, {
		Name = "Gauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -46),
		Size = UDim2.fromOffset(340, 42),
		Visible = false,
	})
	UIKit.label(
		gauge,
		"SPEED",
		if touch then 17 else 13,
		{ Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(60, 42), TextColor3 = Theme.TextDim }
	)
	local gaugeTrack = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(72, 13),
		Size = UDim2.fromOffset(254, 16),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
	}, gauge)
	UIKit.corner(gaugeTrack, 8)
	local green = CleaningScoring.GaugeGreen
	UIKit.new("Frame", {
		Name = "Sweet",
		Position = UDim2.fromScale(green.From, 0),
		Size = UDim2.fromScale(green.To - green.From, 1),
		BackgroundColor3 = Theme.Good,
		BorderSizePixel = 0,
	}, gaugeTrack)
	local needle = UIKit.new("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(6, 28),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
	}, gaugeTrack)
	UIKit.corner(needle, 3)
	UIKit.stroke(needle, 2)
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -134),
		Size = UDim2.fromOffset(300, 14),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	UIKit.corner(shine, 7)
	UIKit.stroke(shine, 2.5)
	local shineFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 240, 170),
		BorderSizePixel = 0,
	}, shine)
	UIKit.corner(shineFill, 7)

	local rub = UIKit.button(gui, "Easy polish: OFF", Theme.PanelLight, Theme.PanelDark, {
		Name = "Rub",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = if touch then UDim2.fromOffset(240, 72) else UDim2.fromOffset(210, 44),
		TextSize = if touch then 22 else 16,
		Visible = false,
	})

	-- gamepad cursor
	local cursor = UIKit.new("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
	}, gui)
	UIKit.corner(cursor, 17)
	UIKit.stroke(cursor, 3, Theme.Accent)

	-- grade card
	local card = UIKit.panel(gui, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromOffset(420, 236),
		Visible = false,
		ZIndex = 30,
	})
	UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, card)
	local cardGrade = UIKit.label(card, "FLAWLESS", 50, {
		Name = "Grade",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 56),
		FontFace = Theme.TitleFont,
	})
	local cardStars = UIKit.label(card, "★★★★", 30, {
		Name = "Stars",
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 32),
		TextColor3 = Theme.Coin,
	})
	local cardOre = UIKit.label(card, "Gold", 22, {
		Name = "Ore",
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 26),
	})
	local cardValue = UIKit.label(card, "Worth 78 coins", 18, {
		Name = "Value",
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Theme.Coin,
	})
	local cardDetail = UIKit.label(card, "", if touch then 17 else 14, {
		Name = "Detail",
		Position = UDim2.fromOffset(0, 148),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.TextDim,
	})
	-- a little streak chip in the card's top corner (cleans in a row, cosmetic only)
	local cardStreak = UIKit.chip(card, "", Theme.Accent, {
		Name = "Streak",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(if touch then 132 else 112, if touch then 34 else 28),
		TextSize = if touch then 20 else 17,
		Visible = false,
		ZIndex = 31,
	})
	local collect = UIKit.button(card, "Collect", Theme.Good, Theme.GoodDark, {
		Name = "Collect",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = if touch then UDim2.fromOffset(220, 64) else UDim2.fromOffset(180, 50),
	})

	if touch then
		card.Size = UDim2.fromOffset(440, 254)
	end

	return {
		Gui = gui,
		Banner = banner,
		PipRow = pipRow,
		StepLabel = stepLabel,
		Title = title,
		Instruction = instruction,
		Pips = pips,
		Leave = leave,
		Meter = meter,
		MeterFill = fill,
		MeterMarker = marker,
		MeterGrade = meterGrade,
		Chips = chips,
		Feedback = feedback,
		Hint = hint,
		Progress = progress,
		Gauge = gauge,
		GaugeNeedle = needle,
		Shine = shine,
		ShineFill = shineFill,
		RubToggle = rub,
		Cursor = cursor,
		Card = card,
		CardGrade = cardGrade,
		CardOre = cardOre,
		CardValue = cardValue,
		CardStars = cardStars,
		CardDetail = cardDetail,
		CardStreak = cardStreak,
		Collect = collect,
		Flash = flash,
	}
end

-- Sets the meter to a 0..1 score.
function CleaningView.setMeter(refs: Refs, score: number)
	local s = math.clamp(score, 0, 1)
	refs.MeterFill.Size = UDim2.new(0.66, 0, s, 0)
	refs.MeterMarker.Position = UDim2.fromScale(0.5, 1 - s)
	local gradeId = ItemData.gradeFromScore(s)
	local grade = ItemData.GradeById[gradeId]
	refs.MeterFill.BackgroundColor3 = grade.Color
	refs.MeterGrade.Text = grade.Name
	refs.MeterGrade.TextColor3 = grade.Color
end

function CleaningView.setStep(refs: Refs, index: number, title: string, instruction: string)
	refs.StepLabel.Text = `STEP {index} / 3`
	refs.Title.Text = title
	refs.Instruction.Text = instruction
	for i, pip in refs.Pips do
		pip.BackgroundColor3 = if i < index then Theme.Good elseif i == index then Theme.Accent else Theme.PanelDark
	end
end

--[[
	Compact layout for small screens: the step banner moves to the top-left
	corner under Leave, so the middle of the screen (where the ore is) stays
	clear. On big screens the banner sits top-center.
]]
function CleaningView.setCompact(refs: Refs, compact: boolean, leaveHeight: number?)
	local banner, pips = refs.Banner, refs.PipRow
	if compact then
		local top = 16 + (leaveHeight or 48) + 12
		banner.AnchorPoint = Vector2.new(0, 0)
		banner.Position = UDim2.fromOffset(16, top)
		banner.Size = UDim2.fromOffset(CleaningView.CompactWidth, 140)
		refs.Instruction.Size = UDim2.new(1, -24, 0, 62)
		pips.AnchorPoint = Vector2.new(0.5, 0)
		pips.Position = UDim2.fromOffset(16 + CleaningView.CompactWidth / 2, top + 146)
	else
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Position = UDim2.new(0.5, 0, 0, 12)
		banner.Size = UDim2.fromOffset(470, 108)
		refs.Instruction.Size = UDim2.new(1, -24, 0, 30)
		pips.AnchorPoint = Vector2.new(0.5, 0)
		pips.Position = UDim2.new(0.5, 0, 0, 126)
	end
end

-- Header while the ore rises out of the rock (all three steps done).
function CleaningView.setReveal(refs: Refs, instruction: string)
	refs.StepLabel.Text = "ALL STEPS DONE"
	refs.Title.Text = "REVEAL"
	refs.Instruction.Text = instruction
	for _, pip in refs.Pips do
		pip.BackgroundColor3 = Theme.Good
	end
end

-- Cleans in a row (each within StreakWindow seconds of the last one): purely
-- cosmetic, nothing is saved or rewarded.
CleaningView.StreakWindow = 120

-- The streak after a clean that finished at `now` (the last one at `last`, nil = none).
function CleaningView.nextStreak(streak: number, last: number?, now: number): number
	if last and now - last <= CleaningView.StreakWindow then
		return streak + 1
	end
	return 1
end

-- The chip's text for a streak ("" below 2: no chip).
function CleaningView.streakText(streak: number): string
	return if streak >= 2 then `🔥 Streak x{streak}` else ""
end

function CleaningView.setStreak(view: Refs, streak: number)
	local text = CleaningView.streakText(streak)
	view.CardStreak.Text = text
	view.CardStreak.Visible = text ~= ""
end

return CleaningView
