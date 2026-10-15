--[[
	BuildService: the server side of build mode.

	Handles BuildPlace / BuildMove / BuildPickup and always answers with
	BuildResult { Seq, Op, Ok, Reason?, Id?, X?, Z?, R? } (Reason is a
	Placement.Reasons code). Checks, in this order:
	  1. argument types and ranges ('BadInput')
	  2. data loaded and a plot assigned ('NoPlot')
	  3. standing within BuildRange of your plot ('TooFar')
	  4. moves and pickups: the model is one of your machines ('NotYours')
	MachineService then checks the layout, slots, inventory and Busy, and
	owns the save (Placement ledger), so this service writes no data itself.

	- A machine placed or moved onto players lifts them onto its roof, and
	  loose items there are lifted too, so nothing ends up inside a machine.
	- Other players nearby see dust (Fx 'Placed' / 'PackedUp'); the builder
	  plays their own effects locally.
	- Packing up your last crate never touches Storage; one toast says so.
	- StateService gets Placed {{Id,X,Z,R}} and Build {MachineSlots,
	  ConveyorSlots, MachinesUsed, ConveyorsUsed} for the HUD and the
	  build-mode ghost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Grid = require(Shared.Machines.Grid)
local Placement = require(Shared.Machines.Placement)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)
local MachineService = require(script.Parent.MachineService)
local StateService = require(script.Parent.StateService)

local BuildService = {}

type PlacedMachine = MachineService.PlacedMachine
export type Op = "Place" | "Move" | "Pickup"

local MAX_SEQ = 2 ^ 31 - 1
local LAST_CELL = GameConfig.PlotCells - 1
local MAX_ID_LENGTH = 32
local FX_RANGE = 100 -- other players this close see the build dust
local CHARACTER_LIFT = 3 -- studs above the machine's top for a lifted character's root
local ITEM_LIFT = 2 -- studs above the machine's top for lifted loose items
local SAFE_TEXT = "Your stored items are safe. Place a crate to reach them."

local placedCallbacks: { (Player, string) -> ...any } = {}

-- Runs after every successful placement (tutorials, quests...).
function BuildService.onPlaced(callback: (Player, string) -> ...any)
	table.insert(placedCallbacks, callback)
end

local function reply(player: Player, seq: number, op: Op, ok: boolean, reason: string?, id: string?, x: number?, z: number?, r: number?)
	Net.fire("BuildResult", player, {
		Seq = seq,
		Op = op,
		Ok = ok,
		Reason = reason,
		Id = id,
		X = x,
		Z = z,
		R = r,
	})
end

-- Checks 2 and 3: the player's plot, if they may build on it right now.
local function plotFor(player: Player): (number?, string?)
	local plotId = PlotService.plotOf(player)
	if not plotId or not DataService.get(player) then
		return nil, "NoPlot"
	end
	if not PlotService.isNear(player, plotId, GameConfig.BuildRange) then
		return nil, "TooFar"
	end
	return plotId, nil
end

-- Check 4: the model must be one of the player's own placed machines.
local function ownMachine(player: Player, plotId: number, value: any): PlacedMachine?
	local plotModel = PlotService.model(plotId)
	local folder = plotModel and plotModel:FindFirstChild("Machines")
	local model = folder and Guard.instance(value, "Model", folder)
	local machine = model and MachineService.get(model)
	if not machine or machine.Model ~= model or machine.Removed or machine.Owner ~= player then
		return nil
	end
	return machine
end

---------------------------------------------------------------- lifting

-- Highest point of a model in world Y (rotated parts included).
local function modelTop(model: Model): number
	local top = -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local halfHeight = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
			top = math.max(top, cf.Position.Y + halfHeight)
		end
	end
	return if top > -math.huge then top else model:GetPivot().Position.Y
end

-- Is a world position over one of the given cells of the plot?
local function overCells(plotId: number, cells: { [number]: boolean }, position: Vector3): boolean
	local at, localPos = PlotService.plotAt(position)
	if at ~= plotId or not localPos then
		return false
	end
	local gx, gz = Grid.cellFromLocal(localPos)
	return gx ~= nil and gz ~= nil and cells[Grid.key(gx, gz)] == true
end

-- Puts characters and loose items standing in a machine's footprint on
-- top of it (they would otherwise be stuck inside its parts).
local function liftOccupants(machine: PlacedMachine)
	local cells: { [number]: boolean } = {}
	for _, k in Placement.cells(machine.Id, machine.X, machine.Z, machine.R) do
		cells[k] = true
	end
	local top = modelTop(machine.Model)
	for _, other in Players:GetPlayers() do
		local root = Guard.rootPart(other)
		local character = other.Character
		if root and character and overCells(machine.PlotId, cells, root.Position) then
			local position = root.Position
			local turn = root.CFrame - position
			character:PivotTo(CFrame.new(position.X, top + CHARACTER_LIFT, position.Z) * turn)
		end
	end
	for _, record in ItemService.looseList() do
		if record.State == "Loose" then
			local position = record.Body.CFrame.Position
			if overCells(machine.PlotId, cells, position) then
				-- release() moves it, wakes its physics and resets its trust point
				ItemService.release(record, CFrame.new(position.X, top + ITEM_LIFT, position.Z), Vector3.new(0, -1, 0))
			end
		end
	end
end

local function puff(player: Player, kind: string, position: Vector3, machineId: string)
	Net.fireNear("Fx", position, FX_RANGE, player, kind, position, machineId)
end

---------------------------------------------------------------- handlers

local function onPlace(player: Player, seqArg: any, idArg: any, xArg: any, zArg: any, rArg: any)
	local seq = Guard.integer(seqArg, 0, MAX_SEQ) or -1
	local id = Guard.string(idArg, MAX_ID_LENGTH)
	local x, z, r = Guard.integer(xArg, 0, LAST_CELL), Guard.integer(zArg, 0, LAST_CELL), Guard.integer(rArg, 0, 3)
	if seq < 0 or not id or not x or not z or not r then
		reply(player, seq, "Place", false, "BadInput")
		return
	end
	local plotId, code = plotFor(player)
	if not plotId then
		reply(player, seq, "Place", false, code, id, x, z, r)
		return
	end
	local machine, reason = MachineService.place(player, id, x, z, r)
	if not machine then
		reply(player, seq, "Place", false, reason or "Invalid", id, x, z, r)
		return
	end
	if not machine.Info.IsConveyor then
		liftOccupants(machine)
	end
	reply(player, seq, "Place", true, nil, machine.Id, machine.X, machine.Z, machine.R)
	puff(player, "Placed", machine.Model:GetPivot().Position, machine.Id)
	for _, callback in placedCallbacks do
		local ok, err = pcall(callback, player, machine.Id)
		if not ok then
			warn("[BuildService] onPlaced listener failed: " .. tostring(err))
		end
	end
end

local function onMove(player: Player, seqArg: any, modelArg: any, xArg: any, zArg: any, rArg: any)
	local seq = Guard.integer(seqArg, 0, MAX_SEQ) or -1
	local x, z, r = Guard.integer(xArg, 0, LAST_CELL), Guard.integer(zArg, 0, LAST_CELL), Guard.integer(rArg, 0, 3)
	if seq < 0 or not x or not z or not r then
		reply(player, seq, "Move", false, "BadInput")
		return
	end
	local plotId, code = plotFor(player)
	if not plotId then
		reply(player, seq, "Move", false, code, nil, x, z, r)
		return
	end
	local machine = ownMachine(player, plotId, modelArg)
	if not machine then
		reply(player, seq, "Move", false, "NotYours", nil, x, z, r)
		return
	end
	local ok, reason = MachineService.move(machine, x, z, r)
	if not ok then
		reply(player, seq, "Move", false, reason or "Invalid", machine.Id, x, z, r)
		return
	end
	if not machine.Info.IsConveyor then
		liftOccupants(machine)
	end
	reply(player, seq, "Move", true, nil, machine.Id, machine.X, machine.Z, machine.R)
	puff(player, "Placed", machine.Model:GetPivot().Position, machine.Id)
end

-- No crate left on the plot while Storage still holds items?
local function lostCrateAccess(player: Player): boolean
	local data = DataService.get(player)
	if not data or type(data.Storage) ~= "table" or #data.Storage == 0 then
		return false
	end
	for _, entry in data.PlacedMachines do
		if type(entry) == "table" and entry.Id == "StorageCrate" then
			return false
		end
	end
	return true
end

local function onPickup(player: Player, seqArg: any, modelArg: any)
	local seq = Guard.integer(seqArg, 0, MAX_SEQ) or -1
	if seq < 0 then
		reply(player, seq, "Pickup", false, "BadInput")
		return
	end
	local plotId, code = plotFor(player)
	if not plotId then
		reply(player, seq, "Pickup", false, code)
		return
	end
	local machine = ownMachine(player, plotId, modelArg)
	if not machine then
		reply(player, seq, "Pickup", false, "NotYours")
		return
	end
	local id, x, z, r = machine.Id, machine.X, machine.Z, machine.R
	local position = machine.Model:GetPivot().Position
	local ok, reason = MachineService.pickup(machine)
	if not ok then
		reply(player, seq, "Pickup", false, reason or "Invalid", id, x, z, r)
		return
	end
	reply(player, seq, "Pickup", true, nil, id, x, z, r)
	puff(player, "PackedUp", position, id)
	if id == "StorageCrate" and lostCrateAccess(player) then
		Net.fire("Notify", player, { Text = SAFE_TEXT, Kind = "Info" })
	end
end

---------------------------------------------------------------- state for the client

-- Placed = {Id,X,Z,R} of every saved machine (the ghost checks against it);
-- Build = slot limits and usage for the build-mode chip.
local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	local placed = {}
	if type(data.PlacedMachines) == "table" then
		for _, entry in data.PlacedMachines do
			if type(entry) == "table" then
				table.insert(placed, { Id = entry.Id, X = entry.X, Z = entry.Z, R = entry.R })
			end
		end
	end
	snapshot.Placed = placed
	local limits = MachineService.limits(player)
	local machines, conveyors = MachineService.usage(player)
	snapshot.Build = {
		MachineSlots = limits.Machines,
		ConveyorSlots = limits.Conveyors,
		MachinesUsed = machines,
		ConveyorsUsed = conveyors,
	}
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/BuildService.spec.luau).
BuildService._test = {
	place = onPlace,
	move = onMove,
	pickup = onPickup,
	provide = provide,
	modelTop = modelTop,
	reset = function()
		table.clear(placedCallbacks)
	end,
}

function BuildService.init()
	Net.on("BuildPlace", onPlace)
	Net.on("BuildMove", onMove)
	Net.on("BuildPickup", onPickup)
	StateService.addProvider(provide)
end

return BuildService
