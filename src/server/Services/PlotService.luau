--[[
	PlotService: gives every player their own workshop plot when their data
	loads, frees it when they leave, and converts grid cells to world space.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local WorldLayout = require(Shared.Config.WorldLayout)
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

function PlotService.plotCFrame(plotId: number): CFrame
	return WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
end

function PlotService.model(plotId: number): Model?
	return WorldService.getPlotModel(plotId)
end

-- Center of a machine footprint in plot space (gx, gz = min corner cell).
function PlotService.footprintCFrame(plotId: number, machineId: string, gx: number, gz: number, rotation: number): CFrame
	local machine = MachineData.ById[machineId]
	local w, d = MachineData.footprint(machine, rotation)
	local cell = GameConfig.CellSize
	local half = GameConfig.PlotCells * cell / 2
	local x = -half + (gx + w / 2) * cell
	local z = -half + (gz + d / 2) * cell
	return PlotService.plotCFrame(plotId) * CFrame.new(x, 0, z) * CFrame.Angles(0, -rotation * math.pi / 2, 0)
end

-- Grid cell under a world position on a plot (or nil when off the plot).
function PlotService.cellAt(plotId: number, position: Vector3): (number?, number?)
	local localPos = PlotService.plotCFrame(plotId):PointToObjectSpace(position)
	local cell = GameConfig.CellSize
	local half = GameConfig.PlotCells * cell / 2
	local gx = math.floor((localPos.X + half) / cell)
	local gz = math.floor((localPos.Z + half) / cell)
	if gx < 0 or gz < 0 or gx >= GameConfig.PlotCells or gz >= GameConfig.PlotCells then
		return nil, nil
	end
	return gx, gz
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

-- Teleports a character to the front of their plot (used after joining).
function PlotService.sendHome(player: Player)
	local plotId = plotOfPlayer[player]
	local character = player.Character
	if plotId and character then
		local cf = PlotService.plotCFrame(plotId) * CFrame.new(0, 3, -GameConfig.PlotCells * GameConfig.CellSize / 2 - 6)
		character:PivotTo(CFrame.lookAt(cf.Position, PlotService.plotCFrame(plotId).Position + Vector3.new(0, 3, 0)))
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
