--[[
	EventBoardController: keeps the big iron billboard's screen filled (tag
	EventBoardScreen; it streams in and out with the town). Once a second, only
	while one is streamed in: the page for the server's time (EventBoardLogic),
	with the Find of the Day from FindOfDayService's Workspace attributes.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventBoardLogic = require(Shared.Events.EventBoardLogic)
local FindOfDay = require(Shared.Events.FindOfDay)
local EventBoardView = require(script.Parent.Parent.UI.EventBoardView)

local EventBoardController = {}

local TAG = "EventBoardScreen"
local screens: { [Instance]: EventBoardView.Refs } = {}
local running = false

local function find(): FindOfDay.Entry?
	return FindOfDay.read({
		Day = Workspace:GetAttribute("FindOfDayDay"),
		UserId = Workspace:GetAttribute("FindOfDayUser"),
		Name = Workspace:GetAttribute("FindOfDayName"),
		Ore = Workspace:GetAttribute("FindOfDayOre"),
		Grade = Workspace:GetAttribute("FindOfDayGrade"),
	})
end

local function refresh()
	local now = Workspace:GetServerTimeNow()
	local pages = EventBoardLogic.pages(now, Workspace:GetAttribute("WeatherForce"), find())
	local page = EventBoardLogic.pageAt(now, pages)
	for _, refs in screens do
		EventBoardView.fill(refs, page)
	end
end

-- (one error never freezes the board for the session: the next second tries again)
local function loop()
	running = true
	while next(screens) do
		local ok, err = pcall(function()
			refresh()
		end)
		if not ok then
			warn(`[EventBoardController] {err}`)
		end
		task.wait(1)
	end
	running = false
end

local function added(screen: Instance)
	if screen:IsA("BasePart") and not screens[screen] then
		screens[screen] = EventBoardView.build(screen)
		if not running then
			task.spawn(loop)
		end
	end
end

function EventBoardController.init() end

function EventBoardController.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(added)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(screen)
		screens[screen] = nil
	end)
	for _, screen in CollectionService:GetTagged(TAG) do
		added(screen)
	end
end

return EventBoardController
