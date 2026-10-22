--[[
	ChampionService: the #1 player of each lobby leaderboard stands on the
	giant HALL OF FAME (owner 2026-10-20: "the best player's skin always hops
	on top"). The hall has five pedestals, BaseParts Champion1..Champion5
	(tag LeaderChampion, attribute Board = the board's place in
	LeaderboardConfig.Boards; World/Lobby/Districts/Hall.luau).

	- After every leaderboard refresh (LeaderboardService.onRefreshed) the
	  top row of each board is compared with the avatar standing on its
	  pedestal; only a new #1 rebuilds it (Players:CreateHumanoidModelFromUserId,
	  pcall'd, in its own thread: it yields). A failed build keeps the old
	  avatar and is tried again on the next refresh. Studio test players
	  (UserId <= 0) have no avatar: the pedestal stays empty.
	- The avatar: every part anchored, no collision, touch, queries or
	  shadows; the Humanoid's name is hidden (a small "#1 Name" sign hangs
	  over the head instead); it faces the plaza (the board's front) with
	  its feet on the pedestal. It streams in as one piece (Atomic).
	- The hop is client-side: the model is tagged "Spin" with SpinSpeed 0,
	  Hop = true, BobHeight / BobSpeed (DecorController), so the server never
	  moves it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)

local ChampionService = {}

ChampionService.Tag = "LeaderChampion"
ChampionService.ModelName = "ChampionAvatar"
ChampionService.HopHeight = 1.1 -- studs
ChampionService.HopSpeed = 3.4

-- board index -> the UserId standing there now (0 = none) and the name on its sign
local standing: { [number]: number } = {}
local standingName: { [number]: string } = {}
local building: { [number]: boolean } = {}

-- (tests swap the avatar maker)
local makeAvatar: (userId: number) -> Model? = function(userId: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	return if ok then model else nil
end

-- (tests swap the pedestal list)
local pedestals: () -> { Instance } = function()
	return CollectionService:GetTagged(ChampionService.Tag)
end

-- The pedestal of board `index` (nil while the hall isn't built / streamed).
function ChampionService.pedestal(index: number): BasePart?
	for _, part in pedestals() do
		if part:IsA("BasePart") and part:GetAttribute("Board") == index then
			return part
		end
	end
	return nil
end

-- Where an avatar of `height` stands on `pedestal`, facing out of the hall's
-- front (the board's Front face: its board shares the hall's facing).
function ChampionService.standCFrame(pedestal: BasePart, height: number, facing: Vector3): CFrame
	local at = pedestal.CFrame.Position
	local top = at.Y + math.min(pedestal.Size.X, pedestal.Size.Y, pedestal.Size.Z) / 2
	local position = Vector3.new(at.X, top + height / 2, at.Z)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(position, position + look)
end

-- The sign over a champion's head.
function ChampionService.signText(name: string): string
	return if name ~= "" then `#1  {name}` else "#1"
end

-- Board `index`'s avatar (nil when nobody stands there).
local function avatarOf(index: number): Instance?
	local pedestal = ChampionService.pedestal(index)
	return if pedestal and pedestal.Parent then pedestal.Parent:FindFirstChild(ChampionService.ModelName .. index) else nil
end

-- Makes `model` a still, harmless statue that the client makes hop.
function ChampionService.dress(model: Model, name: string, userId: number)
	model.Name = ChampionService.ModelName
	model:SetAttribute("UserId", userId)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function()
			humanoid.EvaluateStateMachine = false -- a statue: no physics states
		end)
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	-- "#1 Name" over the head
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local sign = Instance.new("BillboardGui")
		sign.Name = "ChampionName"
		sign.Size = UDim2.fromOffset(220, 44)
		sign.StudsOffset = Vector3.new(0, 2.4, 0)
		sign.MaxDistance = 160
		sign.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Name = "Name"
		label.Text = ChampionService.signText(name)
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 214, 80)
		label.TextStrokeTransparency = 0
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.Parent = sign
		sign.Parent = head
	end
	model:SetAttribute("SpinSpeed", 0)
	model:SetAttribute("Hop", true)
	model:SetAttribute("BobHeight", ChampionService.HopHeight)
	model:SetAttribute("BobSpeed", ChampionService.HopSpeed)
	model:AddTag("Spin")
end

-- An avatar's height (its bounding box; about 5 studs when it can't be read).
function ChampionService.height(model: Model): number
	local ok, size = pcall(function(): Vector3
		local _, box = model:GetBoundingBox()
		return box
	end)
	return if ok and size.Y > 0 then size.Y else 5
end

-- Puts `model` on board `index`'s pedestal (replacing the avatar there).
function ChampionService.place(index: number, model: Model): boolean
	local pedestal = ChampionService.pedestal(index)
	if not pedestal then
		return false
	end
	local old = pedestal.Parent and pedestal.Parent:FindFirstChild(ChampionService.ModelName .. index)
	if old then
		old:Destroy()
	end
	local board = pedestal.Parent and pedestal.Parent:FindFirstChild("Board" .. index)
	local facing = if board and board:IsA("BasePart") then board.CFrame.LookVector else Vector3.new(0, 0, -1)
	model:PivotTo(ChampionService.standCFrame(pedestal, ChampionService.height(model), facing))
	model.Name = ChampionService.ModelName .. index
	model.Parent = pedestal.Parent
	return true
end

-- Clears board `index`'s avatar.
function ChampionService.clear(index: number)
	local pedestal = ChampionService.pedestal(index)
	local old = if pedestal and pedestal.Parent then pedestal.Parent:FindFirstChild(ChampionService.ModelName .. index) else nil
	if old then
		old:Destroy()
	end
	standing[index] = 0
	standingName[index] = nil
end

-- The leaderboards refreshed: a new #1 on a board gets its avatar built (one
-- avatar download per player per refresh: a player leading several boards is
-- cloned), a #1 whose name came late gets it on the sign.
function ChampionService.update(tops: { [string]: any })
	local wanted: { [number]: { { Index: number, Name: string } } } = {}
	for index, board in LeaderboardConfig.Boards do
		local top = tops[board.Id]
		local first = if type(top) == "table" and type(top.Rows) == "table" then top.Rows[1] else nil
		local userId = if type(first) == "table" and type(first.UserId) == "number" then first.UserId else 0
		local name = if type(first) == "table" and type(first.Name) == "string" then first.Name else ""
		if userId <= 0 then
			if (standing[index] or 0) ~= 0 then
				ChampionService.clear(index)
			end
		elseif standing[index] == userId then
			if standingName[index] ~= name then
				-- the name was resolved after the avatar went up
				local avatar = avatarOf(index)
				local label = if avatar then avatar:FindFirstChild("Name", true) else nil
				if label and label:IsA("TextLabel") then
					label.Text = ChampionService.signText(name)
				end
				standingName[index] = name
			end
		elseif not building[index] then
			building[index] = true
			local list = wanted[userId]
			if not list then
				list = {}
				wanted[userId] = list
			end
			table.insert(list, { Index = index, Name = name })
		end
	end
	for userId, boards in wanted do
		task.spawn(function()
			local model = makeAvatar(userId)
			for i, spot in boards do
				building[spot.Index] = nil
				if model then
					local copy = if i < #boards then model:Clone() else model
					ChampionService.dress(copy, spot.Name, userId)
					if ChampionService.place(spot.Index, copy) then
						standing[spot.Index] = userId
						standingName[spot.Index] = spot.Name
					else
						copy:Destroy()
					end
				end
			end
		end)
	end
end

function ChampionService.init()
	local LeaderboardService = require(script.Parent.LeaderboardService) :: any
	if type(LeaderboardService.onRefreshed) == "function" then
		LeaderboardService.onRefreshed(ChampionService.update)
	end
end

function ChampionService.start() end

-- Test hooks.
ChampionService._test = {
	setMaker = function(fn: (number) -> Model?)
		makeAvatar = fn
	end,
	setPedestals = function(fn: () -> { Instance })
		pedestals = fn
	end,
	reset = function()
		table.clear(standing)
		table.clear(standingName)
		table.clear(building)
	end,
	standing = function(index: number): number
		return standing[index] or 0
	end,
}

return ChampionService
