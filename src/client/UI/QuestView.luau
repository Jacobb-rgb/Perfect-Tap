--[[
	The QUESTS window and the daily-streak popup (Pop kit, docs/plans/DAILY_QUESTS_PLAN.md).
	Pure builder + layout, no services: the Lune previews build it too.

	  build()                 the QUESTS window (hidden): a purple header, a dark
	                          body that scrolls: LOGIN STREAK (7 day cells, today
	                          glowing, ODDS), DAILY QUESTS (3 cards + the reset
	                          countdown), WEEKLY QUEST (1 gold card + its countdown)
	  buildPopup()            the streak popup shown on join (7 big cells, CLAIM)
	  layout(refs, w, h, compact?) fits a window into w x h design units
	                          (compact: phones / TVs, every button >= 44 pt)
	  setView(refs, view, now) draws snapshot.Quests (QuestLogic.view) at os.time() `now`
	  setStreak(cells, view)  the 7 cells of either window
	  showOdds(refs, lines?)  the day-7 capsule's odds panel (nil hides it)
	  oddsLines(lucky)        those lines (CapsuleConfig.odds: exact chances)
	  setStatus(refs, text?)  a line at the bottom

	Pictures come from the icon sheets (IconAssets; nothing until uploaded,
	the words always show). No emoji anywhere (owner).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)
local QuestConfig = require(Shared.Config.QuestConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local IconAssets = require(Shared.Config.IconAssets)
local QuestLogic = require(Shared.Quests.QuestLogic)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local QuestView = {}

export type DayRefs = {
	Button: TextButton,
	Title: TextLabel,
	Icon: ImageLabel,
	Label: TextLabel,
	Shade: Frame,
	Done: Frame,
	ClaimTag: Frame,
	Glow: UIStroke,
	Locked: Frame?, -- the round look's red LOCKED chip on a day still to come
}

export type QuestRefs = {
	Card: Frame,
	Badge: TextButton,
	Title: TextLabel,
	Fill: Frame,
	BarText: TextLabel,
	Reward: TextLabel,
	Claim: TextButton,
	Done: Frame,
	Shade: Frame,
}

export type Refs = {
	Gui: ScreenGui,
	Group: Frame,
	Window: Pop.Window,
	Scroller: ScrollingFrame,
	Days: { DayRefs },
	Quests: { QuestRefs }, -- 1..DailyCount = the dailies, then the weekly
	Lower: Frame, -- everything under the streak heading (QuestView.place)
	DailyHeading: TextLabel,
	WeeklyHeading: TextLabel,
	DailyTimer: TextLabel,
	WeeklyTimer: TextLabel,
	OddsButton: TextButton,
	Odds: Frame,
	OddsLines: TextLabel,
	OddsBack: TextButton,
	Status: TextLabel,
	Fit: number,
	Compact: boolean,
}

export type PopupRefs = {
	Gui: ScreenGui,
	Group: Frame,
	Window: Pop.Window,
	Days: { DayRefs },
	Subtitle: TextLabel,
	Claim: TextButton,
	OddsButton: TextButton,
	Note: TextLabel,
	Odds: Frame,
	OddsLines: TextLabel,
	OddsBack: TextButton,
	Fit: number,
	Compact: boolean,
}

QuestView.Title = "QUESTS"
QuestView.PopupTitle = "DAILY REWARD"
QuestView.Header = 76
QuestView.Width = 960
QuestView.Content = 912 -- the scrolled list's width
QuestView.MaxHeight = 680
QuestView.MinTouch = 44 -- points (all-platforms rule)
QuestView.PhoneScale = 0.62 -- HudController's UI scale on phones
QuestView.Gap = 8
QuestView.HeadingH = 40
QuestView.CellH = 104
QuestView.CardH = 72
QuestView.WeeklyH = 80
QuestView.ClaimW = 160
QuestView.ClaimH = 54
QuestView.RewardW = 230
QuestView.BadgeSize = 60
QuestView.PopupCellH = 150
QuestView.PopupHeight = 430
-- the round look's Daily Rewards (the reel): days 1-6 in two rows of three, day 7 big on the right
QuestView.RoundPopupWidth = 780
QuestView.RoundPopupHeight = 572
QuestView.RoundGridH = 300
QuestView.RoundGridMin = 180 -- the grid's least height when a phone's window is short (layoutPopup)
QuestView.RoundPopupLeast = 480 -- under this height the round popup shrinks whole (fit < 1)
QuestView.WeeklyPaint = "Yellow"

-- Design units a tap target needs to be 44 pt on a phone through the fit shrink.
function QuestView.minTouch(fit: number): number
	return math.ceil(QuestView.MinTouch / (QuestView.PhoneScale * math.max(fit, 0.3)))
end

-- The window's size and fit scale for a w x h design-unit screen.
function QuestView.windowSize(w: number, h: number, maxHeight: number?, width: number?, least: number?): (Vector2, number)
	local wide = width or QuestView.Width
	-- (`least`: the height under which the whole window shrinks (fit < 1) rather than get shorter)
	local fit = math.min(1, (w - 24) / wide, (h - 16) / (least or 400))
	local height = math.min(maxHeight or QuestView.MaxHeight, (h - 24) / fit)
	return Vector2.new(wide, math.floor(height)), fit
end

-- The popup's size: the round look's narrower Daily Rewards window, else the wide one.
function QuestView.popupSize(): Vector2
	if PopTheme.round() then
		return Vector2.new(QuestView.RoundPopupWidth, QuestView.RoundPopupHeight)
	end
	return Vector2.new(QuestView.Width, QuestView.PopupHeight)
end

---------------------------------------------------------------- pieces

local function screen(name: string, order: number): (ScreenGui, Frame, Frame)
	local gui = UIKit.screen(name, order)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local group = UIKit.new("Frame", {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(QuestView.Width, 600),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, holder)
	return gui, holder, group
end

local function picture(parent: Instance, icon: string, size: number, props: { [string]: any }): ImageLabel
	local image = UIKit.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 5,
	}, parent)
	IconAssets.apply(image, icon)
	image:SetAttribute("Icon", icon)
	for key, value in props do
		(image :: any)[key] = value
	end
	return image
end

-- A dark cover over a finished card / cell.
local function shade(parent: GuiObject, z: number): Frame
	local frame = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
	}, parent)
	UIKit.corner(frame, PopTheme.Corner)
	return frame
end

-- One streak day cell: "DAY n", the prize's picture and words.
local function dayCell(parent: Instance, spec: QuestConfig.StreakDay, size: Vector2, order: number): DayRefs
	local button = Pop.card(parent, spec.Paint, {
		Name = "Day" .. spec.Day,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size.X, size.Y),
		Selectable = false,
	}, UDim2.fromScale(0.5, 0.48))
	local titleSize = math.floor(math.min(24, size.Y * 0.17))
	local title = Pop.title(button, "DAY " .. spec.Day, titleSize, if spec.Day == 7 then "Gold" else "White", {
		Name = "DayTitle",
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, titleSize + 6),
		ZIndex = 5,
	})
	local pic = math.floor(size.Y * 0.4)
	local icon = picture(button, spec.Icon, pic, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
	})
	local labelSize = math.floor(math.min(18, size.Y * 0.13))
	local label = Pop.text(button, spec.Label, labelSize, {
		Name = "Prize",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -8, 0, labelSize * 2 + 6),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 5,
	})
	local cover = shade(button, 7)
	local done: Frame
	local claimTag: Frame
	local locked: Frame? = nil
	if PopTheme.round() then
		-- (the reel's Daily Rewards: a chip at the bottom of every day: Claimed grey, Claim lime,
		-- LOCKED red; the prize's words above it)
		local chipH = math.floor(math.min(30, math.max(20, size.Y * 0.16)))
		local chipW = math.floor(size.X * 0.8)
		local function chip(name: string, text: string, paint: string | Pop.Paint): Frame
			return Pop.tag(button, text, paint, Vector2.new(chipW, chipH), {
				Name = name,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Visible = false,
				ZIndex = 8,
			})
		end
		done = chip("Done", "Claimed", PopTheme.Gray)
		claimTag = chip("ClaimTag", "Claim", "Lime")
		locked = chip("Locked", "LOCKED", "Red")
		label.Position = UDim2.new(0.5, 0, 1, -(chipH + 10))
		icon.Position = UDim2.new(0.5, 0, 0.42, 0)
	else
		done = Pop.tag(button, "DONE", "Green", Vector2.new(math.floor(size.X * 0.7), 30), {
			Name = "Done",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = -8,
			Visible = false,
			ZIndex = 8,
		})
		-- (in the DAY title's place: setStreak hides the title meanwhile)
		claimTag = Pop.tag(button, "TODAY!", "Red", Vector2.new(math.floor(size.X * 0.78), titleSize + 6), {
			Name = "ClaimTag",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(math.floor(size.X / 2), 4),
			Visible = false,
			ZIndex = 9,
		})
	end
	-- the glowing edge of today's cell
	local glow = UIKit.new("UIStroke", {
		Name = "Glow",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(255, 236, 90),
		Thickness = 0,
		Transparency = 0,
	}, button)
	return {
		Button = button,
		Title = title,
		Icon = icon,
		Label = label,
		Shade = cover,
		Done = done,
		ClaimTag = claimTag,
		Glow = glow,
		Locked = locked,
	}
end

--[[
	The round look's Daily Rewards grid (the reel): days 1-6 in two rows of
	three on the left, day 7 big and rainbow on the right, `width` x
	`height` units.
]]
local function dayGrid(parent: Instance, width: number, height: number): { DayRefs }
	local gap = 10
	local count = #QuestConfig.Streak
	local leftW = math.floor(width * 0.74)
	local cellW = math.floor((leftW - 2 * gap) / 3)
	local cellH = math.floor((height - gap) / 2)
	local cells: { DayRefs } = {}
	for i, spec in QuestConfig.Streak do
		local last = i == count
		local size = if last then Vector2.new(width - leftW - gap, height) else Vector2.new(cellW, cellH)
		local cell = dayCell(parent, spec, size, i)
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		cell.Button.Position = if last then UDim2.fromOffset(leftW + gap, 0) else UDim2.fromOffset(col * (cellW + gap), row * (cellH + gap))
		if last then
			Pop.rainbow(cell.Button)
		end
		table.insert(cells, cell)
	end
	return cells
end

-- A row of the 7 day cells, `width` wide.
local function dayRow(parent: Instance, width: number, height: number, y: number): { DayRefs }
	local row = UIKit.new("Frame", {
		Name = "Days",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 2,
	}, parent)
	local count = #QuestConfig.Streak
	local gap = 10
	local cellW = math.floor((width - gap * (count - 1)) / count)
	UIKit.list(row, Enum.FillDirection.Horizontal, gap, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local cells = {}
	for i, spec in QuestConfig.Streak do
		table.insert(cells, dayCell(row, spec, Vector2.new(cellW, height), i))
	end
	return cells
end

-- The odds panel over a window's body: a title, the lines, BACK.
local function oddsPanel(parent: Instance): (Frame, TextLabel, TextButton)
	local panel = UIKit.new("Frame", {
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 380),
		Visible = false,
		Active = true,
		ZIndex = 20,
	}, parent)
	UIKit.corner(panel, PopTheme.WindowCorner)
	Pop.border(panel, 4)
	Pop.title(panel, "DAY 7: CRYSTAL CAPSULE ODDS", 26, "Cyan", {
		Name = "OddsTitle",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 32),
		ZIndex = 21,
	})
	-- the header line, then the golems in two columns (showOdds splits the text)
	local lines = Pop.text(panel, "", 18, {
		Name = "Lines",
		Position = UDim2.fromOffset(24, 46),
		Size = UDim2.new(1, -48, 0, 24),
		TextWrapped = true,
		ZIndex = 21,
	})
	for i, column in { "Left", "Right" } do
		Pop.text(lines, "", 18, {
			Name = column,
			Position = UDim2.new((i - 1) * 0.5, 0, 0, 30),
			Size = UDim2.new(0.5, -6, 0, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 21,
		})
	end
	local back = Pop.button(panel, "BACK", "Blue", Vector2.new(180, 56), {
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		ZIndex = 22,
	})
	return panel, lines, back
end

-- A text-only line under / beside a heading.
local function note(parent: Instance, text: string, size: number, props: { [string]: any }): TextLabel
	local label = Pop.text(parent, text, size, { Name = "Note", ZIndex = 4 })
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

local function heading(parent: Instance, text: string, colors: string, y: number): TextLabel
	-- (the round look: "- DAILY QUESTS -", the reel's section headings)
	return Pop.title(parent, Pop.section(text), 32, colors, {
		Name = "Heading",
		FontFace = PopTheme.Heavy,
		Position = UDim2.fromOffset(8, y),
		Size = UDim2.new(0, 520, 0, QuestView.HeadingH),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
end

-- One quest card: the badge, the words, the progress bar, the reward, CLAIM.
local function questCard(parent: Instance, name: string, y: number, height: number, weekly: boolean): QuestRefs
	local w = QuestView.Content
	local card = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(w, height),
		ZIndex = 2,
	}, parent)
	Pop.face(card, if weekly then "Orange" else "Slate", PopTheme.Corner, false)
	local badgeSize = QuestView.BadgeSize
	local badge = Pop.tile(card, {
		Name = "Badge",
		Label = "QUEST",
		Icon = "more",
		Paint = "Blue",
		Size = badgeSize,
	})
	local holder = badge.Parent :: Frame
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 8, 0.5, 0)
	holder.ZIndex = 3
	badge.Selectable = false
	badge.Active = false
	badge.AutoButtonColor = false
	local left = badgeSize + 20
	local right = QuestView.ClaimW + QuestView.RewardW + 30
	local title = Pop.text(card, "", 26, {
		Name = "QuestTitle",
		Position = UDim2.fromOffset(left, 6),
		Size = UDim2.new(1, -(left + QuestView.ClaimW + 24), 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	local barW = w - left - right
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		Position = UDim2.new(0, left, 1, -34),
		Size = UDim2.fromOffset(barW, 26),
		ClipsDescendants = true,
		ZIndex = 4,
	}, card)
	UIKit.corner(bar, 13)
	Pop.border(bar, 2.5)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
	}, bar)
	Pop.face(fill, "Green", 13, true)
	local fillBorder = fill:FindFirstChild("Border") :: UIStroke?
	if fillBorder then
		fillBorder.Thickness = 0
	end
	local barText = Pop.text(bar, "0 / 0", 18, {
		Name = "BarText",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	})
	local reward = Pop.text(card, "", 20, {
		Name = "Reward",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(QuestView.ClaimW + 22), 0.5, 0),
		Size = UDim2.fromOffset(QuestView.RewardW, height - 12),
		TextColor3 = PopTheme.MoneyNumber,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	local claim = Pop.button(card, "CLAIM", "Green", Vector2.new(QuestView.ClaimW, QuestView.ClaimH), {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		ZIndex = 6,
	})
	local cover = shade(card, 8)
	local done = Pop.tag(card, "DONE", "Green", Vector2.new(QuestView.ClaimW, 40), {
		Name = "Done",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Visible = false,
		ZIndex = 9,
	})
	return {
		Card = card,
		Badge = badge,
		Title = title,
		Fill = fill,
		BarText = barText,
		Reward = reward,
		Claim = claim,
		Done = done,
		Shade = cover,
	}
end

---------------------------------------------------------------- the QUESTS window

QuestView.OddsH = 40

--[[
	Stacks the list: the streak heading row (`oddsH` tall: ODDS grows on
	phones), the day cells, DAILY QUESTS with its cards (`cardH`), WEEKLY
	QUEST (`weeklyH`). Sets the scroller's canvas.
]]
function QuestView.place(refs: Refs, oddsH: number, cardH: number, weeklyH: number)
	local w = QuestView.Content
	local top = math.max(QuestView.HeadingH, oddsH + 2) + 4
	refs.Lower.Position = UDim2.fromOffset(0, top)
	local y = QuestView.CellH + QuestView.Gap + 4
	refs.DailyHeading.Position = UDim2.fromOffset(8, y)
	refs.DailyTimer.Position = UDim2.fromOffset(w - 4, y + 8)
	y += QuestView.HeadingH + 2
	for i, q in refs.Quests do
		local weekly = i > QuestConfig.DailyCount
		if weekly then
			y += 4
			refs.WeeklyHeading.Position = UDim2.fromOffset(8, y)
			refs.WeeklyTimer.Position = UDim2.fromOffset(w - 4, y + 8)
			y += QuestView.HeadingH + 2
		end
		local h = if weekly then weeklyH else cardH
		q.Card.Position = UDim2.fromOffset(0, y)
		q.Card.Size = UDim2.fromOffset(w, h)
		q.Reward.Size = UDim2.fromOffset(QuestView.RewardW, h - 12)
		y += h + QuestView.Gap
	end
	y += 4
	refs.Lower.Size = UDim2.fromOffset(w, y)
	refs.Scroller.CanvasSize = UDim2.fromOffset(0, top + y)
end

function QuestView.build(): Refs
	local gui, _, group = screen("TerraForgeQuests", 16)
	local size = QuestView.windowSize(1280, 720)
	group.Size = UDim2.fromOffset(size.X, size.Y)
	local window = Pop.window(group, QuestView.Title, size, QuestView.Header, "Purple")
	window.Root.AnchorPoint = Vector2.new(0, 0)
	window.Root.Position = UDim2.fromOffset(0, 0)

	local scroller = UIKit.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -14, 1, -10),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 2,
	}, window.Body)

	local w = QuestView.Content
	local y = 0
	heading(scroller, "LOGIN STREAK", "Gold", y)
	local oddsButton = Pop.button(scroller, "ODDS", "Blue", Vector2.new(120, 40), {
		Name = "OddsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(w - 4, y + 2),
	})
	note(scroller, "A prize every day. Miss a day: back to day 1.", 18, {
		Name = "StreakNote",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(w - 136, y + 10),
		Size = UDim2.fromOffset(440, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- everything under the streak heading: QuestView.place moves it down when
	-- the phone layout makes ODDS taller, and makes the cards taller with CLAIM
	local lower = UIKit.new("Frame", {
		Name = "Lower",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, QuestView.HeadingH + 4),
		Size = UDim2.fromOffset(w, 600),
		ZIndex = 2,
	}, scroller)
	local days = dayRow(lower, w, QuestView.CellH, 0)
	local dailyHeading = heading(lower, "DAILY QUESTS", "Cyan", 0)
	local dailyTimer = note(lower, "", 20, {
		Name = "DailyTimer",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(380, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local quests: { QuestRefs } = {}
	for i = 1, QuestConfig.DailyCount do
		table.insert(quests, questCard(lower, "Daily" .. i, 0, QuestView.CardH, false))
	end
	local weeklyHeading = heading(lower, "WEEKLY QUEST", "Gold", 0)
	local weeklyTimer = note(lower, "", 20, {
		Name = "WeeklyTimer",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(380, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	table.insert(quests, questCard(lower, "Weekly", 0, QuestView.WeeklyH, true))

	local status = Pop.text(window.Root, "", 20, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(700, 30),
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 15,
	})
	UIKit.corner(status, 8)
	local odds, lines, back = oddsPanel(window.Root)

	local built: Refs = {
		Gui = gui,
		Group = group,
		Window = window,
		Scroller = scroller,
		Days = days,
		Quests = quests,
		Lower = lower,
		DailyHeading = dailyHeading,
		WeeklyHeading = weeklyHeading,
		DailyTimer = dailyTimer,
		WeeklyTimer = weeklyTimer,
		OddsButton = oddsButton,
		Odds = odds,
		OddsLines = lines,
		OddsBack = back,
		Status = status,
		Fit = 1,
		Compact = false,
	}
	QuestView.place(built, QuestView.OddsH, QuestView.CardH, QuestView.WeeklyH)
	return built
end

---------------------------------------------------------------- the streak popup

function QuestView.buildPopup(): PopupRefs
	local gui, _, group = screen("TerraForgeStreak", 17)
	local size = QuestView.popupSize()
	local round = PopTheme.round()
	group.Size = UDim2.fromOffset(size.X, size.Y)
	local window = Pop.window(group, QuestView.PopupTitle, size, QuestView.Header, "Orange")
	window.Root.AnchorPoint = Vector2.new(0, 0)
	window.Root.Position = UDim2.fromOffset(0, 0)
	local body = window.Body
	local subtitle = Pop.title(body, "", 28, "Gold", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 3,
	})
	local rowH = if round then QuestView.RoundGridH else QuestView.PopupCellH
	local inner = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 52),
		Size = UDim2.new(1, -40, 0, rowH),
		ZIndex = 2,
	}, body)
	local days = if round then dayGrid(inner, size.X - 48, rowH) else dayRow(inner, QuestView.Width - 48, QuestView.PopupCellH, 0)
	local claim = Pop.button(body, "CLAIM", "Green", Vector2.new(300, 66), {
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52 + rowH + 18),
	})
	local oddsButton = Pop.button(body, "ODDS", "Blue", Vector2.new(130, 52), {
		Name = "OddsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 52 + rowH + 25),
	})
	local footnote = note(body, "Miss a day and the streak starts again at day 1.", 18, {
		Name = "Footnote",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -40, 0, 24),
	})
	local odds, lines, back = oddsPanel(window.Root)
	return {
		Gui = gui,
		Group = group,
		Window = window,
		Days = days,
		Subtitle = subtitle,
		Claim = claim,
		OddsButton = oddsButton,
		Note = footnote,
		Odds = odds,
		OddsLines = lines,
		OddsBack = back,
		Fit = 1,
		Compact = false,
	}
end

---------------------------------------------------------------- layout

-- Fits a window into a w x h design-unit screen (compact: phones / TVs).
local function fitWindow(
	refs: any,
	w: number,
	h: number,
	compact: boolean?,
	maxHeight: number?,
	width: number?,
	least: number?
): (number, number)
	local size, fit = QuestView.windowSize(w, h, maxHeight, width, least)
	refs.Window.Root.Size = UDim2.fromOffset(size.X, size.Y)
	refs.Group.Size = UDim2.fromOffset(size.X, size.Y)
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	local k = if compact then 1 / math.max(fit, 0.5) else 1
	local close = math.floor(math.max(62, if compact then QuestView.minTouch(fit) else 0) * math.min(k, 1.25))
	refs.Window.Close.Size = UDim2.fromOffset(close, close)
	local closeLabel = refs.Window.Close:FindFirstChild("Label") :: TextLabel?
	if closeLabel then
		closeLabel.TextSize = math.floor(close * 0.66)
	end
	refs.Fit = fit
	refs.Compact = compact == true
	local touch = if compact then QuestView.minTouch(fit) else 0
	refs.OddsBack.Size = UDim2.fromOffset(180, math.max(56, touch))
	refs.Odds.Size = UDim2.fromOffset(560, math.min(380, size.Y - QuestView.Header - 20))
	return fit, touch
end

function QuestView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local _, touch = fitWindow(refs, w, h, compact)
	local claimH = math.max(QuestView.ClaimH, touch)
	for _, q in refs.Quests do
		q.Claim.Size = UDim2.fromOffset(QuestView.ClaimW, claimH)
	end
	local oddsH = math.max(QuestView.OddsH, touch)
	refs.OddsButton.Size = UDim2.fromOffset(120, oddsH)
	-- (a taller CLAIM makes its card taller: 8 units of card around it)
	QuestView.place(refs, oddsH, math.max(QuestView.CardH, claimH + 12), math.max(QuestView.WeeklyH, claimH + 12))
end

function QuestView.layoutPopup(refs: PopupRefs, w: number, h: number, compact: boolean?)
	local popup = QuestView.popupSize()
	-- (the round look's taller popup: on a short phone the whole window shrinks, not the grid alone)
	local least = if PopTheme.round() then QuestView.RoundPopupLeast else nil
	local _, touch = fitWindow(refs, w, h, compact, popup.Y, popup.X, least)
	local claimH, oddsH = math.max(66, touch), math.max(52, touch)
	refs.Claim.Size = UDim2.fromOffset(300, claimH)
	refs.OddsButton.Size = UDim2.fromOffset(130, oddsH)
	if not PopTheme.round() then
		return
	end
	-- the round look's day grid: shrunk (a UIScale) when the window is shorter than it wants
	-- (phones: CLAIM and ODDS stay inside, over the footnote)
	local row = refs.Window.Body:FindFirstChild("Row") :: Frame?
	if not row then
		return
	end
	local bodyH = refs.Window.Root.Size.Y.Offset - QuestView.Header - 3
	local below = math.max(18 + claimH, 25 + oddsH) + 6 + 32 -- (the buttons, a gap, the footnote)
	local gridH = math.clamp(bodyH - 52 - below, QuestView.RoundGridMin, QuestView.RoundGridH)
	local found = row:FindFirstChild("Fit")
	local fit: UIScale = if found and found:IsA("UIScale") then found else UIKit.new("UIScale", { Name = "Fit" }, row) :: UIScale
	fit.Scale = gridH / QuestView.RoundGridH
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 52)
	refs.Claim.Position = UDim2.new(0.5, 0, 0, 52 + gridH + 18)
	refs.OddsButton.Position = UDim2.new(1, -24, 0, 52 + gridH + 25)
end

---------------------------------------------------------------- filling in

-- "+$12.5K  +10 Shards  +Triple Lucky 15m": a reward's words.
function QuestView.rewardText(q: { [string]: any }): string
	local parts = {}
	if type(q.Coins) == "number" and q.Coins > 0 then
		table.insert(parts, "+" .. Format.money(q.Coins))
	end
	if type(q.Shards) == "number" and q.Shards > 0 then
		table.insert(parts, `+{q.Shards} Shards`)
	end
	if type(q.Boost) == "string" then
		local name = if q.Boost == "HexaLucky" then "Hexa Lucky" else "Triple Lucky"
		local minutes = math.floor((q.BoostSeconds or 0) / 60)
		table.insert(parts, `+{name} {minutes}m`)
	end
	if type(q.Capsule) == "string" then
		local capsule = CapsuleConfig.ById[q.Capsule]
		table.insert(parts, "+" .. (if capsule then capsule.Name else q.Capsule))
	end
	return table.concat(parts, "  ")
end

-- The words under a day cell: its coins priced now, else its label.
function QuestView.dayText(day: { [string]: any }): string
	if type(day.Coins) == "number" and day.Coins > 0 then
		if type(day.Shards) == "number" and day.Shards > 0 then
			return `{Format.money(day.Coins)} + {day.Shards} Shards`
		end
		return Format.money(day.Coins)
	end
	if type(day.Capsule) == "string" and type(day.Shards) == "number" and day.Shards > 0 then
		return `{day.Label} + {day.Shards} Shards`
	end
	return tostring(day.Label or "")
end

-- The 7 cells of either window from view.Streak.
function QuestView.setStreak(cells: { DayRefs }, streak: { [string]: any }?)
	local s: { [string]: any } = streak or {}
	local today = if type(s.Today) == "number" then s.Today else 1
	local done = if type(s.Done) == "number" then s.Done else 0
	local canClaim = s.CanClaim == true
	local days = if type(s.Days) == "table" then s.Days else {}
	for i, cell in cells do
		local day = days[i]
		if type(day) == "table" then
			cell.Label.Text = QuestView.dayText(day)
		end
		local isDone = i <= done
		local isToday = i == today and canClaim
		local locked = cell.Locked
		if locked then
			-- (the round look: the chips say it, the card stays bright)
			cell.Shade.Visible = false
			cell.Done.Visible = isDone
			cell.ClaimTag.Visible = isToday
			locked.Visible = not isDone and not isToday
			cell.Title.Visible = true
		else
			cell.Shade.Visible = isDone
			cell.Done.Visible = isDone
			cell.ClaimTag.Visible = isToday
			cell.Title.Visible = not isToday
		end
		cell.Glow.Thickness = if isToday then 5 elseif i == today then 3 else 0
		cell.Button.Selectable = isToday
		cell.Button.Active = isToday
	end
end

-- Draws snapshot.Quests (QuestLogic.view) at os.time() `now`.
function QuestView.setView(refs: Refs, view: { [string]: any }?, now: number)
	local v: { [string]: any } = view or {}
	QuestView.setStreak(refs.Days, v.Streak)
	local lists = { if type(v.Daily) == "table" then v.Daily else {}, if type(v.Weekly) == "table" then v.Weekly else {} }
	for i, q in refs.Quests do
		local weekly = i > QuestConfig.DailyCount
		local list = if weekly then lists[2] else lists[1]
		local data = list[if weekly then 1 else i]
		q.Card.Visible = type(data) == "table"
		if type(data) == "table" then
			local goal = math.max(1, tonumber(data.Goal) or 1)
			local progress = math.clamp(tonumber(data.Progress) or 0, 0, goal)
			local finished = progress >= goal
			local claimed = data.Claimed == true
			q.Title.Text = tostring(data.Text or "")
			q.Fill.Size = UDim2.fromScale(progress / goal, 1)
			q.Fill.Visible = progress > 0
			q.BarText.Text = if data.Money
				then `{Format.money(progress)} / {Format.money(goal)}`
				else `{Format.commas(progress)} / {Format.commas(goal)}`
			q.Reward.Text = QuestView.rewardText(data)
			local face = q.Badge
			local icon = face:FindFirstChild("Icon") :: ImageLabel?
			local iconName = tostring(data.Icon or "more")
			if icon and icon:GetAttribute("Icon") ~= iconName then
				IconAssets.apply(icon, iconName)
				icon:SetAttribute("Icon", iconName)
				icon.Visible = IconAssets.shows(iconName)
			end
			local label = face:FindFirstChild("Label") :: TextLabel?
			if label then
				label.Text = tostring(data.Short or "QUEST")
			end
			Pop.repaint(face, tostring(data.Paint or "Blue"))
			q.Claim.Visible = not claimed
			q.Claim.Selectable = finished and not claimed
			q.Claim.Active = finished and not claimed
			Pop.repaint(q.Claim, if finished then "Green" else "Slate")
			local claimLabel = q.Claim:FindFirstChild("Label") :: TextLabel?
			if claimLabel then
				claimLabel.Text = if finished then "CLAIM" else `{math.floor(progress / goal * 100)}%`
			end
			q.Done.Visible = claimed
			q.Shade.Visible = claimed
		end
	end
	local dailyEnds = tonumber(v.DailyEnds)
	local weeklyEnds = tonumber(v.WeeklyEnds)
	refs.DailyTimer.Text = if dailyEnds then "New quests in " .. QuestLogic.countdown(dailyEnds - now) else ""
	refs.WeeklyTimer.Text = if weeklyEnds then "New quest in " .. QuestLogic.countdown(weeklyEnds - now) else ""
end

-- The popup's words for a view.
function QuestView.setPopup(refs: PopupRefs, view: { [string]: any }?)
	local streak: { [string]: any } = if view and type(view.Streak) == "table" then view.Streak else {}
	QuestView.setStreak(refs.Days, streak)
	local today = if type(streak.Today) == "number" then streak.Today else 1
	local canClaim = streak.CanClaim == true
	refs.Subtitle.Text = if canClaim then `Day {today} of 7: claim your prize!` else "Come back tomorrow for the next day!"
	local label = refs.Claim:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = if canClaim then "CLAIM" else "CLAIMED"
	end
	Pop.repaint(refs.Claim, if canClaim then "Green" else "Slate")
	refs.Claim.Active = canClaim
end

-- The Crystal Capsule's exact odds (the day-7 prize), one line per golem.
function QuestView.oddsLines(lucky: boolean): string
	local capsuleId = QuestConfig.Streak[#QuestConfig.Streak].Capsule or "Crystal"
	local lines = {}
	for _, line in CapsuleConfig.odds(capsuleId, lucky) do
		local golem = GolemConfig.ById[line.Golem]
		local percent = string.format("%.2f", line.Chance * 100):gsub("0+$", ""):gsub("%.$", "")
		table.insert(lines, `{if golem then golem.Name else line.Golem}  {percent}%`)
	end
	local header = if lucky then "Triple Lucky is on: the better golems are 3x as likely." else "One golem, each one of:"
	return header .. "\n" .. table.concat(lines, "\n")
end

function QuestView.showOdds(refs: any, text: string?)
	refs.Odds.Visible = text ~= nil
	if text then
		-- the first line on top, the others in two columns
		local rows = string.split(text, "\n")
		refs.OddsLines.Text = table.remove(rows, 1) or ""
		local half = math.ceil(#rows / 2)
		local left = refs.OddsLines:FindFirstChild("Left") :: TextLabel?
		local right = refs.OddsLines:FindFirstChild("Right") :: TextLabel?
		if left and right then
			left.Text = table.concat(rows, "\n", 1, half)
			right.Text = if #rows > half then table.concat(rows, "\n", half + 1, #rows) else ""
			left.Size = UDim2.new(0.5, -6, 0, half * 22 + 4)
			right.Size = left.Size
		end
	end
end

function QuestView.setStatus(refs: Refs, text: string?)
	refs.Status.Visible = text ~= nil and text ~= ""
	refs.Status.Text = text or ""
end

return QuestView
