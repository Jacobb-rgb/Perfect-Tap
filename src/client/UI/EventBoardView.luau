--[[
	EventBoardView: what the clients draw on the iron billboard's screen part
	(one SurfaceGui, three lines; EventBoardController fills it once a second).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventBoardLogic = require(Shared.Events.EventBoardLogic)
local Theme = require(Shared.Config.UITheme)

local EventBoardView = {}

EventBoardView.MaxDistance = 900 -- studs: it stands in the mountains, read from the whole town
-- (a 120 x 54-stud screen: 600 x 270 px; review 11-10: TextScaled stops at 100 px, so
-- at 5 px a stud the big line's letters can be 20 studs tall, read from the spawn)
EventBoardView.PixelsPerStud = 5
EventBoardView.TextCap = 100 -- px: Roblox's TextScaled limit
-- each line's top and height (shares of the screen)
EventBoardView.Lines = { Title = { 0.04, 0.14 }, Big = { 0.2, 0.37 }, Small = { 0.6, 0.34 } }

export type Refs = { Gui: SurfaceGui, Title: TextLabel, Big: TextLabel, Small: TextLabel }

-- `y`, `height`: shares of the screen.
local function line(gui: SurfaceGui, name: string, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = Theme.TitleFont
	label.Position = UDim2.fromScale(0.05, y)
	label.Size = UDim2.fromScale(0.9, height)
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = gui
	return label
end

function EventBoardView.build(screen: BasePart): Refs
	local gui = Instance.new("SurfaceGui")
	gui.Name = "EventBoard"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.MaxDistance = EventBoardView.MaxDistance
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = EventBoardView.PixelsPerStud
	gui.Parent = screen
	return {
		Gui = gui,
		-- (review 11-07: the second line big too, readable from the spawn on a phone)
		Title = line(gui, "Title", EventBoardView.Lines.Title[1], EventBoardView.Lines.Title[2]),
		Big = line(gui, "Big", EventBoardView.Lines.Big[1], EventBoardView.Lines.Big[2]),
		Small = line(gui, "Small", EventBoardView.Lines.Small[1], EventBoardView.Lines.Small[2]),
	}
end

function EventBoardView.fill(refs: Refs, page: EventBoardLogic.Page)
	refs.Title.Text = page.Title
	refs.Title.TextColor3 = page.Color
	refs.Big.Text = page.Big
	refs.Big.TextColor3 = page.BigColor or Color3.new(1, 1, 1)
	refs.Small.Text = page.Small
	refs.Small.TextColor3 = page.SmallColor or Color3.new(1, 1, 1)
end

return EventBoardView
