--[[
	PlotService: gives every player their own workshop plot when their data
	loads, frees it when they leave, and converts grid cells to world space.
	The grid maths itself lives in Shared/Machines/Grid (the build-mode
	ghost uses the same code).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Grid = require(Shared.Machines.Grid)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local PlotService = {}

local plotOfPlayer: { [Player]: number } = {}
local ownerOfPlot: { [number]: Player } = {}
local assignedCallbacks: { (Player, number) -> ...any } = {}
local releasedCallbacks: { (Player, number) -> ...any } = {}

function PlotService.onAssigned(callback: (Player, number) -> ...any)
	table.insert(assignedCallbacks, callback)
	for player, plotId in plotOfPlayer do
		task.spawn(callback, player, plotId)
	end
end

-- Runs before the plot is freed (machines are removed here).
function PlotService.onReleased(callback: (Player, number) -> ...any)
	table.insert(releasedCallbacks, callback)
end

function PlotService.plotOf(player: Player): number?
	return plotOfPlayer[player]
end

function PlotService.ownerOf(plotId: number): Player?
	return ownerOfPlot[plotId]
end

-- Plots never move, so their CFrames are worked out once.
local plotFrames: { [number]: CFrame } = {}

function PlotService.plotCFrame(plotId: number): CFrame
	local cf = plotFrames[plotId]
	if not cf then
		cf = WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
		plotFrames[plotId] = cf
	end
	return cf
end

function PlotService.model(plotId: number): Model?
	return WorldService.getPlotModel(plotId)
end

-- World CFrame of a machine footprint's centre (gx, gz = min corner cell),
-- turned so the machine's front faces Grid.dir(rotation).
function PlotService.footprintCFrame(plotId: number, machineId: string, gx: number, gz: number, rotation: number): CFrame
	return PlotService.plotCFrame(plotId) * Grid.localCFrame(machineId, gx, gz, rotation)
end

-- Grid cell under a world position on a plot (or nil when off the plot).
function PlotService.cellAt(plotId: number, position: Vector3): (number?, number?)
	return Grid.cellFromLocal(PlotService.plotCFrame(plotId):PointToObjectSpace(position))
end

-- Half the plot pad plus a little: anything further from a plot centre is off it.
local QUICK_REJECT = GameConfig.PlotCells * GameConfig.CellSize / 2 + 2
-- (plotAt only ever returns a plot whose centre is this close on X and Z)
PlotService.PlotReach = QUICK_REJECT
local MIN_LOCAL_Y, MAX_LOCAL_Y = -3, 24

-- Which plot a world position is over (any plot, owned or not), and the
-- position in that plot's local space. Cheap: a box reject per plot first.
function PlotService.plotAt(position: Vector3): (number?, Vector3?)
	for _, plot in WorldLayout.Plots do
		local center = plot.Center
		if math.abs(position.X - center.X) <= QUICK_REJECT and math.abs(position.Z - center.Z) <= QUICK_REJECT then
			local localPos = PlotService.plotCFrame(plot.Id):PointToObjectSpace(position)
			if localPos.Y >= MIN_LOCAL_Y and localPos.Y <= MAX_LOCAL_Y then
				return plot.Id, localPos
			end
		end
	end
	return nil, nil
end

-- Is the player's character within `range` studs (horizontally) of the plot centre?
function PlotService.isNear(player: Player, plotId: number, range: number): boolean
	local plot = WorldLayout.Plots[plotId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not plot or not root then
		return false
	end
	local offset = root.Position - plot.Center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= range
end

function PlotService.setSignText(plotId: number, text: string)
	local model = PlotService.model(plotId)
	local sign = model and model:FindFirstChild("PlotSign")
	local label = sign and sign:FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function assign(player: Player)
	if plotOfPlayer[player] then
		return
	end
	for _, plot in WorldLayout.Plots do
		if not ownerOfPlot[plot.Id] then
			ownerOfPlot[plot.Id] = player
			plotOfPlayer[player] = plot.Id
			player:SetAttribute("PlotId", plot.Id)
			local model = PlotService.model(plot.Id)
			if model then
				model:SetAttribute("OwnerUserId", player.UserId)
			end
			PlotService.setSignText(plot.Id, player.DisplayName .. "'s Forge")
			for _, callback in assignedCallbacks do
				task.spawn(callback, player, plot.Id)
			end
			return
		end
	end
	warn("[PlotService] no free plot for " .. player.Name)
end

local function release(player: Player)
	local plotId = plotOfPlayer[player]
	if not plotId then
		return
	end
	for _, callback in releasedCallbacks do
		local ok, err = pcall(callback, player, plotId)
		if not ok then
			warn("[PlotService] release callback failed: " .. tostring(err))
		end
	end
	plotOfPlayer[player] = nil
	ownerOfPlot[plotId] = nil
	local model = PlotService.model(plotId)
	if model then
		model:SetAttribute("OwnerUserId", nil)
	end
	PlotService.setSignText(plotId, "Free Plot")
end

-- Where a character stands at the front of a plot, facing it (joining, the BASE teleport).
function PlotService.homeCFrame(plotId: number): CFrame
	local cf = PlotService.plotCFrame(plotId) * CFrame.new(0, 3, -GameConfig.PlotCells * GameConfig.CellSize / 2 - 6)
	return CFrame.lookAt(cf.Position, PlotService.plotCFrame(plotId).Position + Vector3.new(0, 3, 0))
end

-- Teleports a character to the front of their plot (used after joining).
function PlotService.sendHome(player: Player)
	local plotId = plotOfPlayer[player]
	local character = player.Character
	if plotId and character then
		character:PivotTo(PlotService.homeCFrame(plotId))
	end
end

function PlotService.init()
	DataService.onLoaded(function(player)
		assign(player)
		-- first spawn after loading: start at your own workshop
		if player.Character then
			task.delay(0.3, PlotService.sendHome, player)
		end
	end)
	local function setup(player: Player)
		player.CharacterAdded:Connect(function()
			if plotOfPlayer[player] then
				task.delay(0.3, PlotService.sendHome, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	DataService.beforeRelease(function(player)
		release(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

return PlotService
