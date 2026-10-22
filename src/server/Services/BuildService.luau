--[[
	BuildService: the server side of build mode.

	Handles BuildPlace (seq, machineId, x, z, r, level?) / BuildMove (seq,
	model, x, z, r, level?) / BuildPickup (seq, model) and always answers
	with BuildResult { Seq, Op, Ok, Reason?, Id?, X?, Z?, R?, L? } (Reason
	is a Placement.Reasons code). `level` is nil or 0 for the ground, 1 for
	a platform's deck (docs/plans/PLATFORMS_PLAN.md). Checks, in this order:
	  1. argument types and ranges ('BadInput'; a level other than nil / 0 / 1 too)
	  2. data loaded and a plot assigned ('NoPlot')
	  3. standing within BuildRange of your plot ('TooFar')
	  4. moves and pickups: the model is one of your machines ('NotYours')
	MachineService then checks the layout, slots, inventory and Busy, and
	owns the save (Placement ledger), so this service writes no data itself.

	- A machine placed or moved onto players lifts them onto its roof, and
	  loose items there are lifted too, so nothing ends up inside a machine.
	  On a deck only what is up at deck level is lifted (not the belt under
	  it); a new platform lifts players onto its deck, never the items on
	  the belts under it.
	- Other players nearby see dust (Fx 'Placed' / 'PackedUp'); the builder
	  plays their own effects locally.
	- Stored items live in the Ore Pen on the base yard (design v2), so no
	  machine is needed to reach them.
	- StateService gets Placed {{Id,X,Z,R,L?}} and Build {MachineSlots,
	  ConveyorSlots, MachinesUsed, ConveyorsUsed} for the HUD and the
	  build-mode ghost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local Grid = require(Shared.Machines.Grid)
local Placement = require(Shared.Machines.Placement)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)
local MachineService = require(script.Parent.MachineService)
local MovementService = require(script.Parent.MovementService)
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

local placedCallbacks: { (Player, string) -> ...any } = {}

-- Runs after every successful placement (tutorials, quests...).
function BuildService.onPlaced(callback: (Player, string) -> ...any)
	table.insert(placedCallbacks, callback)
end

local function reply(
	player: Player,
	seq: number,
	op: Op,
	ok: boolean,
	reason: string?,
	id: string?,
	x: number?,
	z: number?,
	r: number?,
	level: number?
)
	Net.fire("BuildResult", player, {
		Seq = seq,
		Op = op,
		Ok = ok,
		Reason = reason,
		Id = id,
		X = x,
		Z = z,
		R = r,
		L = if level == 1 then 1 else nil,
	})
end

-- The optional level argument: nil / 0 = the ground (0), 1 = a deck (1),
-- anything else nil (BadInput).
local function levelArg(value: any): number?
	if value == nil then
		return 0
	end
	return Guard.integer(value, 0, MachineData.MaxLevel)
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

-- Highest point of a model's solid parts in world Y (rotated parts included;
-- glow, beams and other non-colliding decor don't count: a Money Laser's beam
-- must not lift a player up to its top). A model with no solid part: all parts.
local function modelTop(model: Model): number
	local top = -math.huge
	local solid = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			solid = true
			break
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.CanCollide or not solid) then
			local cf, size = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local halfHeight = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
			top = math.max(top, cf.Position.Y + halfHeight)
		end
	end
	return if top > -math.huge then top else model:GetPivot().Position.Y
end

-- Is a world position over one of the given cells of the plot, at least
-- `minY` studs over the pad (plot-local)?
local function overCells(plotId: number, cells: { [number]: boolean }, position: Vector3, minY: number): boolean
	local at, localPos = PlotService.plotAt(position)
	if at ~= plotId or not localPos or localPos.Y < minY then
		return false
	end
	local gx, gz = Grid.cellFromLocal(localPos)
	return gx ~= nil and gz ~= nil and cells[Grid.key(gx, gz)] == true
end

-- Puts characters and loose items standing in a machine's footprint on
-- top of it (they would otherwise be stuck inside its parts). On a deck
-- only what is up there; a platform lifts players, not the items riding
-- the belts under it.
local function liftOccupants(machine: PlacedMachine)
	local cells: { [number]: boolean } = {}
	for _, k in Placement.cells(machine.Id, machine.X, machine.Z, machine.R) do
		cells[k] = true
	end
	local minY = if machine.L == 1 then MachineService.DeckItemY else -math.huge
	local liftItems = machine.Info.Behaviour ~= "Platform"
	local top = modelTop(machine.Model)
	for _, other in Players:GetPlayers() do
		local root = Guard.rootPart(other)
		local character = other.Character
		if root and character and overCells(machine.PlotId, cells, root.Position, minY) then
			local position = root.Position
			local turn = root.CFrame - position
			character:PivotTo(CFrame.new(position.X, top + CHARACTER_LIFT, position.Z) * turn)
			MovementService.serverMoved(other)
		end
	end
	if not liftItems then
		return
	end
	for _, record in ItemService.looseList() do
		if record.State == "Loose" then
			local position = record.Body.CFrame.Position
			if overCells(machine.PlotId, cells, position, minY) then
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

local function onPlace(player: Player, seqArg: any, idArg: any, xArg: any, zArg: any, rArg: any, levelValue: any)
	local seq = Guard.integer(seqArg, 0, MAX_SEQ) or -1
	local id = Guard.string(idArg, MAX_ID_LENGTH)
	local x, z, r = Guard.integer(xArg, 0, LAST_CELL), Guard.integer(zArg, 0, LAST_CELL), Guard.integer(rArg, 0, 3)
	local level = levelArg(levelValue)
	if seq < 0 or not id or not x or not z or not r or not level then
		reply(player, seq, "Place", false, "BadInput")
		return
	end
	local plotId, code = plotFor(player)
	if not plotId then
		reply(player, seq, "Place", false, code, id, x, z, r, level)
		return
	end
	local machine, reason = MachineService.place(player, id, x, z, r, level)
	if not machine then
		reply(player, seq, "Place", false, reason or "Invalid", id, x, z, r, level)
		return
	end
	if not machine.Info.IsConveyor then
		liftOccupants(machine)
	end
	reply(player, seq, "Place", true, nil, machine.Id, machine.X, machine.Z, machine.R, machine.L)
	puff(player, "Placed", machine.Model:GetPivot().Position, machine.Id)
	for _, callback in placedCallbacks do
		local ok, err = pcall(callback, player, machine.Id)
		if not ok then
			warn("[BuildService] onPlaced listener failed: " .. tostring(err))
		end
	end
end

local function onMove(player: Player, seqArg: any, modelArg: any, xArg: any, zArg: any, rArg: any, levelValue: any)
	local seq = Guard.integer(seqArg, 0, MAX_SEQ) or -1
	local x, z, r = Guard.integer(xArg, 0, LAST_CELL), Guard.integer(zArg, 0, LAST_CELL), Guard.integer(rArg, 0, 3)
	local level = levelArg(levelValue)
	if seq < 0 or not x or not z or not r or not level then
		reply(player, seq, "Move", false, "BadInput")
		return
	end
	local plotId, code = plotFor(player)
	if not plotId then
		reply(player, seq, "Move", false, code, nil, x, z, r, level)
		return
	end
	local machine = ownMachine(player, plotId, modelArg)
	if not machine then
		reply(player, seq, "Move", false, "NotYours", nil, x, z, r, level)
		return
	end
	local ok, reason = MachineService.move(machine, x, z, r, level)
	if not ok then
		reply(player, seq, "Move", false, reason or "Invalid", machine.Id, x, z, r, level)
		return
	end
	if not machine.Info.IsConveyor then
		liftOccupants(machine)
	end
	reply(player, seq, "Move", true, nil, machine.Id, machine.X, machine.Z, machine.R, machine.L)
	puff(player, "Placed", machine.Model:GetPivot().Position, machine.Id)
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
	local id, x, z, r, level = machine.Id, machine.X, machine.Z, machine.R, machine.L
	local position = machine.Model:GetPivot().Position
	local ok, reason = MachineService.pickup(machine)
	if not ok then
		reply(player, seq, "Pickup", false, reason or "Invalid", id, x, z, r, level)
		return
	end
	reply(player, seq, "Pickup", true, nil, id, x, z, r, level)
	puff(player, "PackedUp", position, id)
end

---------------------------------------------------------------- state for the client

-- Placed = {Id,X,Z,R,L?} of every saved machine (the ghost checks against
-- it; L only for deck entries); Build = slot limits and usage for the
-- build-mode chip.
local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	local placed = {}
	if type(data.PlacedMachines) == "table" then
		for _, entry in data.PlacedMachines do
			if type(entry) == "table" then
				table.insert(placed, { Id = entry.Id, X = entry.X, Z = entry.Z, R = entry.R, L = if entry.L == 1 then 1 else nil })
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
