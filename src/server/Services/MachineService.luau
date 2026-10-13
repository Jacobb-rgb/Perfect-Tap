--[[
	MachineService: machines placed on plots.

	- Saved in data.PlacedMachines as { Id, X, Z, R } (grid cell + rotation).
	- New players get MachineData.StarterKit once.
	- Machines spawn on the plot when it is assigned and vanish when the
	  player leaves (their placement is saved, nothing is lost).
	- Behaviour per machine type is registered by other services with
	  MachineService.register(machineId, { spawned = fn, removed = fn }).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local MachineService = {}

export type PlacedMachine = {
	Model: Model,
	Id: string,
	Owner: Player,
	PlotId: number,
	X: number,
	Z: number,
	R: number,
	State: { [string]: any }, -- per-type runtime state (queues, timers...)
}

export type Behaviour = {
	spawned: ((PlacedMachine) -> ...any)?,
	removed: ((PlacedMachine) -> ...any)?,
}

local placed: { [Model]: PlacedMachine } = {}
local behaviours: { [string]: { Behaviour } } = {}

function MachineService.register(machineId: string, behaviour: Behaviour)
	behaviours[machineId] = behaviours[machineId] or {}
	table.insert(behaviours[machineId], behaviour)
	-- machines that spawned before this behaviour was registered catch up
	if behaviour.spawned then
		for _, machine in placed do
			if machine.Id == machineId then
				local ok, err = pcall(behaviour.spawned, machine)
				if not ok then
					warn(`[MachineService] {machineId} spawned hook failed: {err}`)
				end
			end
		end
	end
end

function MachineService.get(model: Instance?): PlacedMachine?
	local node = model
	while node do
		if node:IsA("Model") and placed[node :: Model] then
			return placed[node :: Model]
		end
		node = node.Parent
	end
	return nil
end

function MachineService.ofPlayer(player: Player): { PlacedMachine }
	local list = {}
	for _, machine in placed do
		if machine.Owner == player then
			table.insert(list, machine)
		end
	end
	return list
end

function MachineService.all(): { [Model]: PlacedMachine }
	return placed
end

-- World CFrame of a named attachment on the machine's Base.
function MachineService.point(machine: PlacedMachine, name: string): CFrame?
	local base = machine.Model.PrimaryPart
	local attachment = base and base:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame
	end
	return nil
end

function MachineService.spawn(player: Player, plotId: number, entry: { [string]: any }): PlacedMachine?
	local machineInfo = MachineData.ById[entry.Id]
	if not machineInfo then
		warn("[MachineService] unknown machine in save: " .. tostring(entry.Id))
		return nil
	end
	local plotModel = PlotService.model(plotId)
	local folder = plotModel and plotModel:FindFirstChild("Machines")
	if not folder then
		return nil
	end
	local model = MachineBuilder.build(entry.Id)
	model:PivotTo(PlotService.footprintCFrame(plotId, entry.Id, entry.X, entry.Z, entry.R))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("GridX", entry.X)
	model:SetAttribute("GridZ", entry.Z)
	model:SetAttribute("Rotation", entry.R)
	model:AddTag("Machine")
	model.Parent = folder
	local machine: PlacedMachine = {
		Model = model,
		Id = entry.Id,
		Owner = player,
		PlotId = plotId,
		X = entry.X,
		Z = entry.Z,
		R = entry.R,
		State = {},
	}
	placed[model] = machine
	local hooks: { Behaviour } = behaviours[entry.Id] or {}
	for _, behaviour in hooks do
		if behaviour.spawned then
			local ok, err = pcall(behaviour.spawned, machine)
			if not ok then
				warn(`[MachineService] {entry.Id} spawned hook failed: {err}`)
			end
		end
	end
	return machine
end

function MachineService.remove(machine: PlacedMachine)
	local hooks: { Behaviour } = behaviours[machine.Id] or {}
	for _, behaviour in hooks do
		if behaviour.removed then
			local ok, err = pcall(behaviour.removed, machine)
			if not ok then
				warn(`[MachineService] {machine.Id} removed hook failed: {err}`)
			end
		end
	end
	placed[machine.Model] = nil
	machine.Model:Destroy()
end

local function spawnAll(player: Player, plotId: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	if not data.StarterKitGiven then
		data.StarterKitGiven = true
		for _, entry in MachineData.StarterKit do
			table.insert(data.PlacedMachines, { Id = entry.Id, X = entry.X, Z = entry.Z, R = entry.R })
		end
	end
	for _, entry in data.PlacedMachines do
		MachineService.spawn(player, plotId, entry)
	end
	DataService.changed(player)
end

function MachineService.init()
	PlotService.onAssigned(spawnAll)
	PlotService.onReleased(function(player)
		for _, machine in MachineService.ofPlayer(player) do
			MachineService.remove(machine)
		end
	end)
end

return MachineService
