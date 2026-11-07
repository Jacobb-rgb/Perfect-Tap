--[[
	EventBoardView: what the clients draw on the iron billboard's screen part
	(one SurfaceGui, three lines; EventBoardController fills it once a second).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventBoardLogic = require(Shared.Events.EventBoardLogic)
local Theme = require(Shared.Config.UITheme)

local EventBoardView = {}

EventBoardView.MaxDistance = 320 -- studs: past this the screen doesn't draw
EventBoardView.PixelsPerStud = 28
-- each line's top and height (shares of the screen)
EventBoardView.Lines = { Title = { 0.05, 0.15 }, Big = { 0.24, 0.36 }, Small = { 0.64, 0.28 } }

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
end

return EventBoardView
