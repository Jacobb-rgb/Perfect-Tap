--[[
	Cleaning minigame UI (pure builder), the default look's frame (a look
	module may hide parts of it and draw its own).
	  top      banner (SPRAY + instruction)
	  left     Leave button
	  right    live QUALITY meter (grade zones)
	  center   feedback pop text ("Crystal cracked!", "Sparkling!")
	  bottom   "% CLEAN" bar, device hint
	  card     grade reveal (grade, ore, value, stars, details, Collect)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local Theme = require(Shared.Config.UITheme)
local ItemData = require(Shared.Config.ItemData)
local UIKit = require(script.Parent.UIKit)
local LightSkin = require(script.Parent.LightSkin)

local CleaningView = {}

export type Refs = {
	Gui: ScreenGui,
	Banner: Frame,
	StepLabel: TextLabel,
	Title: TextLabel,
	Instruction: TextLabel,
	Leave: TextButton,
	Meter: Frame,
	MeterFill: Frame,
	MeterMarker: Frame,
	MeterGrade: TextLabel,
	Feedback: TextLabel,
	Hint: TextLabel,
	Progress: TextLabel, -- "62% CLEAN" on the bar
	CleanBar: Frame,
	CleanFill: Frame,
	Cursor: Frame,
	Card: Frame,
	CardGrade: TextLabel,
	CardOre: TextLabel,
	CardValue: TextLabel,
	CardStars: TextLabel,
	CardDetail: TextLabel,
	CardInto: TextLabel, -- where the clean ore went (CleanResult.Into: intoText)
	CardStreak: TextLabel,
	Collect: TextButton,
	Flash: Frame,
}

local METER_HEIGHT = 300

-- Design-unit layout numbers the controller needs to keep the ore in view.
CleaningView.BannerBottom = 128 -- the banner, from the top
CleaningView.BottomReserved = 110 -- the "% CLEAN" bar and the hint, from the bottom
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
	local stepLabel = UIKit.label(banner, "CLEANING", 16, {
		Name = "Step",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.TextDim,
	})
	local title = UIKit.label(banner, "SPRAY", 40, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	local instruction = UIKit.label(banner, "Wash the dirt off", 18, {
		Name = "Instruction",
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.new(1, -24, 0, 30),
	})
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
		Size = UDim2.fromOffset(92, METER_HEIGHT + 70),
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
	-- feedback pop
	local feedback = UIKit.label(gui, "", 44, {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(600, 60),
		FontFace = Theme.TitleFont,
		TextTransparency = 1,
	})
	UIKit.new("UIScale", { Name = "Pop", Scale = 1 }, feedback)
	local hint = UIKit.label(gui, "", if touch then 19 else 17, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(640, 24),
		TextColor3 = Theme.TextDim,
	})

	-- "% CLEAN" bar
	local cleanBar = UIKit.new("Frame", {
		Name = "CleanBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.fromOffset(if touch then 380 else 340, if touch then 40 else 34),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, gui)
	UIKit.corner(cleanBar, 12)
	UIKit.stroke(cleanBar, 2.5)
	local cleanFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(110, 205, 255),
		BorderSizePixel = 0,
	}, cleanBar)
	UIKit.corner(cleanFill, 12)
	local progress = UIKit.label(cleanBar, "0% CLEAN", if touch then 22 else 19, {
		Name = "Progress",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		ZIndex = 3,
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
		Size = UDim2.fromOffset(420, 262),
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
	-- where the clean ore went: the backpack, else the pen, else the tray (CleaningService)
	local cardInto = UIKit.label(card, "", if touch then 18 else 16, {
		Name = "Into",
		Position = UDim2.fromOffset(0, 172),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Theme.Good,
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
		card.Size = UDim2.fromOffset(440, 284)
	end

	return {
		Gui = gui,
		Banner = banner,
		StepLabel = stepLabel,
		Title = title,
		Instruction = instruction,
		Leave = leave,
		Meter = meter,
		MeterFill = fill,
		MeterMarker = marker,
		MeterGrade = meterGrade,
		Feedback = feedback,
		Hint = hint,
		Progress = progress,
		CleanBar = cleanBar,
		CleanFill = cleanFill,
		Cursor = cursor,
		Card = card,
		CardGrade = cardGrade,
		CardOre = cardOre,
		CardValue = cardValue,
		CardStars = cardStars,
		CardDetail = cardDetail,
		CardInto = cardInto,
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

-- The "% CLEAN" bar: 0..1 of the job done.
function CleaningView.setClean(refs: Refs, fraction: number)
	local f = math.clamp(fraction, 0, 1)
	refs.CleanFill.Size = UDim2.fromScale(f, 1)
	refs.Progress.Text = `{math.floor(f * 100 + 1e-6)}% CLEAN`
end

--[[
	Compact layout for small screens: the step banner moves to the top-left
	corner under Leave, so the middle of the screen (where the ore is) stays
	clear. On big screens the banner sits top-center.
]]
function CleaningView.setCompact(refs: Refs, compact: boolean, leaveHeight: number?)
	local banner = refs.Banner
	if compact then
		local top = 16 + (leaveHeight or 48) + 12
		banner.AnchorPoint = Vector2.new(0, 0)
		banner.Position = UDim2.fromOffset(16, top)
		banner.Size = UDim2.fromOffset(CleaningView.CompactWidth, 140)
		refs.Instruction.Size = UDim2.new(1, -24, 0, 62)
	else
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Position = UDim2.new(0.5, 0, 0, 12)
		banner.Size = UDim2.fromOffset(470, 108)
		refs.Instruction.Size = UDim2.new(1, -24, 0, 30)
	end
end

-- Where the clean ore went (CleanResult.Into, CleaningService: owner 2026-10-24, cleaned
-- ore goes straight into the backpack), as the result card says it ("" for anything else).
CleaningView.IntoText = {
	Backpack = "In your backpack",
	Pen = "Backpack full: moved to your Ore Pen",
	Sold = "Backpack and Ore Pen full: sold to Tobin",
	Tray = "Backpack full: waiting on the station's tray",
} :: { [string]: string }

function CleaningView.intoText(into: any): string
	return if type(into) == "string" then CleaningView.IntoText[into] or "" else ""
end

-- The card's "where it went" line; a full backpack is the warning colour.
function CleaningView.setInto(refs: Refs, into: any)
	refs.CardInto.Text = CleaningView.intoText(into)
	refs.CardInto.TextColor3 = if into == "Backpack" then Theme.Good else Theme.Accent
end

-- Header while the ore rises out of the clump (all the dirt is off).
function CleaningView.setReveal(refs: Refs, instruction: string)
	refs.StepLabel.Text = "ALL CLEAN"
	refs.Title.Text = "REVEAL"
	refs.Instruction.Text = instruction
	CleaningView.setClean(refs, 1)
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
	return if streak >= 2 then `STREAK x{streak}` else ""
end

function CleaningView.setStreak(view: Refs, streak: number)
	local text = CleaningView.streakText(streak)
	view.CardStreak.Text = text
	view.CardStreak.Visible = text ~= ""
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- While the light UI is on (ships off), the same window wears the light
-- look (LightSkin: white panels, navy outlines, dark text, light buttons).
local darkBuild = CleaningView.build
CleaningView.build = function(options: Options?): Refs
	local refs = darkBuild(options)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
	end
	return refs
end

return CleaningView
