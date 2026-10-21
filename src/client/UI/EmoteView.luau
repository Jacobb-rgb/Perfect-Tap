--[[
	The EMOTES menu (owner 2026-10-21: "add the emotes"): a Pop window with
	a purple "EMOTES" header and the red X over a grid of the 12 emotes
	(EmoteConfig.List), each a bright painted card with the emote's name in
	words and a short line under it. Text only: no pictures, never an emoji.
	The card playing now wears a PLAYING tag; the Blaster Spin card goes
	grey with "Hold your blaster" while the blaster isn't in hand. A hint
	line at the bottom says how to stop (move) and the key (EmoteController).

	  build()                  the window (hidden); Refs.Cards[name] per emote
	  layout(refs, w, h, compact?) fits the window into w x h design units;
	                           compact (phones, TVs): every card stays at
	                           least MinTouch points high at PhoneScale
	  setCard(refs, name, state, note?)  "Ready" | "Playing" | "Locked"
	  setHint(refs, text)
	  cardSize(refs)           a card's design size now (tests)

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EmoteConfig = require(Shared.Config.EmoteConfig)
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local EmoteView = {}

EmoteView.Columns = 4
EmoteView.Header = 70
EmoteView.Gap = 12
EmoteView.Pad = 16
EmoteView.HintHeight = 34
EmoteView.MaxWidth = 960
EmoteView.MaxHeight = 560
EmoteView.MinTouch = 44 -- points
EmoteView.PhoneScale = 0.62 -- HudController's floor (phones)

-- The menu's words for each emote: the name and a short line (English, like the rest of the UI).
EmoteView.Labels = {
	Breakdance = { "BREAKDANCE", "windmill + freeze" },
	Headspin = { "HEADSPIN", "spin on your head" },
	Robot = { "ROBOT", "beep boop moves" },
	DiscoPoint = { "DISCO", "point up, point down" },
	BackGlide = { "BACK GLIDE", "slide backwards" },
	Worm = { "THE WORM", "wave on the floor" },
	Victory = { "VICTORY", "jumps and a spin" },
	AirGuitar = { "AIR GUITAR", "strum and headbang" },
	ForgeHammer = { "FORGE HAMMER", "stomp and strike" },
	GolemStomp = { "GOLEM STOMP", "heavy steps, roar" },
	GemJuggle = { "GEM JUGGLE", "three shiny gems" },
	BlasterSpin = { "BLASTER SPIN", "cowboy twirl" },
} :: { [string]: { string } }

-- a bright paint per card, round the colours
EmoteView.Paints = { "Purple", "Blue", "Teal", "Pink", "Orange", "Green", "Yellow", "Red" }

export type CardRefs = {
	Name: string,
	Button: TextButton,
	Title: TextLabel,
	Note: TextLabel,
	Tag: Frame,
	Paint: string,
	State: string,
}

export type Refs = {
	Gui: ScreenGui,
	Group: Frame,
	Window: Pop.Window,
	Grid: Frame,
	Cards: { [string]: CardRefs },
	Order: { string },
	Hint: TextLabel,
	Compact: boolean,
}

-- The compact layout: touch screens, TVs, small scales and short windows (as the other panels).
function EmoteView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

-- A card's design height that is MinTouch points on a phone after the fit shrink.
function EmoteView.minTouch(fit: number): number
	return math.ceil(EmoteView.MinTouch / (EmoteView.PhoneScale * math.max(fit, 0.3)))
end

local function buildCard(grid: Frame, name: string, index: number): CardRefs
	local labels = EmoteView.Labels[name] or { string.upper(name), "" }
	local paint = EmoteView.Paints[(index - 1) % #EmoteView.Paints + 1]
	local button = UIKit.new("TextButton", {
		Name = name,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = index,
		Selectable = true,
		ZIndex = 3,
	}, grid)
	Pop.face(button, paint, PopTheme.Corner, true)
	local title = Pop.text(button, labels[1], 30, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.14, 0),
		Size = UDim2.new(1, -12, 0.42, 0),
		TextScaled = true,
		ZIndex = 4,
	})
	local note = Pop.text(button, labels[2], 18, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.new(1, -14, 0.26, 0),
		TextScaled = true,
		ZIndex = 4,
	})
	local tag = Pop.tag(button, "PLAYING", "Green", Vector2.new(96, 24), {
		Name = "Playing",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Visible = false,
	})
	return { Name = name, Button = button, Title = title, Note = note, Tag = tag, Paint = paint, State = "Ready" }
end

function EmoteView.build(): Refs
	local gui = UIKit.screen("TerraForgeEmotes", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	-- the window sits in a full-screen holder whose UIScale fits it to small screens
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
		Size = UDim2.fromOffset(EmoteView.MaxWidth, EmoteView.MaxHeight),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, holder)
	local window = Pop.window(group, "EMOTES", Vector2.new(EmoteView.MaxWidth, EmoteView.MaxHeight), EmoteView.Header, "Purple")
	window.Root.AnchorPoint = Vector2.new(0, 0)
	window.Root.Position = UDim2.fromOffset(0, 0)

	local grid = UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EmoteView.Pad, EmoteView.Pad),
		Size = UDim2.new(1, -2 * EmoteView.Pad, 1, -(2 * EmoteView.Pad + EmoteView.HintHeight)),
		ZIndex = 2,
	}, window.Body)
	UIKit.new("UIGridLayout", {
		Name = "Layout",
		CellSize = UDim2.fromOffset(200, 120),
		CellPadding = UDim2.fromOffset(EmoteView.Gap, EmoteView.Gap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local cards: { [string]: CardRefs } = {}
	local order: { string } = {}
	for i, name in EmoteConfig.List do
		cards[name] = buildCard(grid, name, i)
		table.insert(order, name)
	end
	local hint = Pop.text(window.Body, "Pick a move. Walk to stop it.", 20, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, EmoteView.HintHeight - 8),
		TextScaled = true,
		ZIndex = 3,
	})
	local refs: Refs = {
		Gui = gui,
		Group = group,
		Window = window,
		Grid = grid,
		Cards = cards,
		Order = order,
		Hint = hint,
		Compact = false,
	}
	EmoteView.layout(refs, 1280, 720, false)
	return refs
end

-- The window's design size and the fit scale for a w x h design-unit screen.
function EmoteView.windowSize(w: number, h: number, compact: boolean): (Vector2, number)
	local rows = math.ceil(#EmoteConfig.List / EmoteView.Columns)
	-- the least height the grid may have: compact cards stay MinTouch points high
	local minCard = if compact then EmoteView.minTouch(1) else 90
	local minHeight = EmoteView.Header + 2 * EmoteView.Pad + EmoteView.HintHeight + rows * minCard + (rows - 1) * EmoteView.Gap + 8
	local width = math.min(EmoteView.MaxWidth, w - 40)
	local height = math.max(minHeight, math.min(EmoteView.MaxHeight, h - 40))
	local fit = math.min(1, (w - 16) / width, (h - 16) / height)
	return Vector2.new(math.floor(width), math.floor(height)), fit
end

function EmoteView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local isCompact = compact == true
	refs.Compact = isCompact
	local size, fit = EmoteView.windowSize(w, h, isCompact)
	refs.Window.Root.Size = UDim2.fromOffset(size.X, size.Y)
	refs.Group.Size = UDim2.fromOffset(size.X, size.Y)
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	local rows = math.ceil(#EmoteConfig.List / EmoteView.Columns)
	local gridW = size.X - 8 - 2 * EmoteView.Pad
	local gridH = size.Y - EmoteView.Header - 4 - 2 * EmoteView.Pad - EmoteView.HintHeight
	local cellW = math.floor((gridW - (EmoteView.Columns - 1) * EmoteView.Gap) / EmoteView.Columns)
	local cellH = math.floor((gridH - (rows - 1) * EmoteView.Gap) / rows)
	local layout = refs.Grid:FindFirstChild("Layout") :: UIGridLayout?
	if layout then
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
	end
	-- (compact: the X keeps a thumb-sized target through the fit shrink)
	local k = if isCompact then 1 / math.max(fit, 0.5) else 1
	local close = math.floor((if isCompact then 72 else 56) * k)
	refs.Window.Close.Size = UDim2.fromOffset(close, close)
	local closeLabel = refs.Window.Close:FindFirstChild("Label") :: TextLabel?
	if closeLabel then
		closeLabel.TextSize = math.floor(close * 0.66)
	end
	for _, card in refs.Cards do
		card.Tag.Size = UDim2.fromOffset(math.min(96, cellW - 12), math.max(20, math.floor(cellH * 0.2)))
	end
end

-- A card's design size now.
function EmoteView.cardSize(refs: Refs): Vector2
	local layout = refs.Grid:FindFirstChild("Layout") :: UIGridLayout?
	if not layout then
		return Vector2.zero
	end
	return Vector2.new(layout.CellSize.X.Offset, layout.CellSize.Y.Offset)
end

-- The fit scale the layout chose (the FitScale UIScale).
function EmoteView.fit(refs: Refs): number
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	return if scale and scale:IsA("UIScale") then scale.Scale else 1
end

-- "Ready" | "Playing" (the PLAYING tag) | "Locked" (grey, the note says why).
function EmoteView.setCard(refs: Refs, name: string, state: string, note: string?)
	local card = refs.Cards[name]
	if not card then
		return
	end
	card.State = state
	card.Tag.Visible = state == "Playing"
	Pop.repaint(card.Button, if state == "Locked" then "Slate" else card.Paint, true)
	local labels = EmoteView.Labels[name]
	card.Note.Text = note or (if labels then labels[2] else "")
	card.Button.AutoButtonColor = state ~= "Locked"
	card.Title.TextTransparency = if state == "Locked" then 0.35 else 0
end

function EmoteView.setHint(refs: Refs, text: string)
	refs.Hint.Text = text
end

return EmoteView
