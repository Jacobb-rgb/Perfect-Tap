--[[
	FeederService: the Ore Feeder (owner 2026-11-07: "podavač", automation).

	- It takes ore you put in (Put In from your backpack, up to LoadMax a
	  press, or ore you drop into its funnel): dirty, clean or crushed, never
	  a dirty SECRET ore (that one is cleaned by hand: its moment). Never from
	  a belt or another machine: it feeds only what you gave it.
	- It holds up to MachineData.feederCapacity(level) ores (the Capacity
	  upgrade at the machine: 200, 500, 700, 1000) in its saved queue
	  (Entry.In, so leaving and shutdowns keep it like any machine's queue).
	- Every MachineData.FeederSeconds it moves the next ore to its output
	  (Entry.Out); MachineService's tick pushes it out of the front, onto the
	  belt or into the machine standing there, and waits while that refuses
	  or the owner has too many loose items (the Status says so).
	- Attributes for the clients: Stored (held + waiting at the outlet),
	  Capacity. A Capacity level bought updates every feeder of the owner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MachineData = require(Shared.Config.MachineData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local MachineLogic = require(Shared.Machines.MachineLogic)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local IntakeService = require(script.Parent.IntakeService)
local MachineService = require(script.Parent.MachineService)
local ShopService = require(script.Parent.ShopService)

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineService.Desc
type Via = MachineService.Via
type Reason = MachineService.Reason

local FeederService = {}

FeederService.Id = "OreFeeder"

-- Ores this player's feeders hold (their Capacity level; 0 without a save).
function FeederService.capacityOf(player: Player): number
	local data = DataService.get(player)
	return MachineData.feederCapacity(if data then EconomyConfig.upgradeLevel(data, FeederService.Id, "Capacity") else 0)
end

local function held(machine: PlacedMachine): number
	local entry = machine.Entry
	return (if entry.In then #entry.In else 0) + (if entry.Out then #entry.Out else 0)
end

-- (the counter shows the ore waiting inside: the one at the outlet is on its way out)
local function show(machine: PlacedMachine)
	local queue = machine.Entry.In
	MachineService.setAttrs(machine, { Stored = if queue then #queue else 0, Capacity = FeederService.capacityOf(machine.Owner) })
end

-- What it takes (see the header). Pure but for the owner's capacity.
function FeederService.accepts(machine: PlacedMachine, desc: Desc, ownerUserId: number, via: Via): (boolean, Reason?)
	if via ~= "Hand" and via ~= "Drop" then
		return false, "Wrong"
	end
	if ownerUserId ~= machine.Owner.UserId then
		return false, "Foreign"
	end
	local accepts = machine.Info.Accepts
	if not MachineLogic.isValidDesc(desc) or not accepts or not accepts[desc.K] then
		return false, "Wrong"
	end
	if desc.K == "Raw" and SecretOreConfig.isSecret(desc.O) then
		return false, "Wrong"
	end
	if held(machine) >= FeederService.capacityOf(machine.Owner) then
		return false, "Full"
	end
	return true, nil
end

local function insert(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: Via)
	local queue = machine.Entry.In or {}
	machine.Entry.In = queue
	table.insert(queue, desc)
	show(machine)
	DataService.changed(machine.Owner)
end

--[[
	Put In with a whole backpack in one pass (review 11-09: 1000 one-by-one
	inserts were one long server frame): the room left, every fitting stack
	taken at once, appended to the queue, one save mark. Returns how many.
]]
function FeederService.loadAll(player: Player, machine: PlacedMachine): number
	if machine.Removed or machine.Owner ~= player then
		return 0
	end
	local room = FeederService.capacityOf(player) - held(machine)
	if room <= 0 then
		return 0
	end
	local taken = CarryService.take(player, function(desc: Desc): boolean
		return (FeederService.accepts(machine, desc, player.UserId, "Hand"))
	end, room)
	if #taken == 0 then
		return 0
	end
	local queue = machine.Entry.In or {}
	machine.Entry.In = queue
	for _, desc in taken do
		table.insert(queue, desc)
	end
	show(machine)
	MachineService.wake(machine)
	DataService.changed(player)
	return #taken
end

-- One ore to the outlet every FeederSeconds while the outlet is empty.
local function tick(machine: PlacedMachine, now: number)
	local queue = machine.Entry.In
	local out = machine.Entry.Out
	if not queue or #queue == 0 or (out and #out > 0) then
		return
	end
	local state = machine.State
	local nextAt = state.NextFeed
	if type(nextAt) == "number" and now < nextAt then
		return
	end
	state.NextFeed = now + MachineData.FeederSeconds
	local desc = table.remove(queue, 1)
	if desc then
		MachineService.pushOut(machine, desc)
		show(machine)
	end
end

local function busy(machine: PlacedMachine, _now: number): boolean
	local queue = machine.Entry.In
	return queue ~= nil and #queue > 0
end

local behaviour: MachineService.Behaviour = {
	spawned = function(machine: PlacedMachine)
		show(machine)
		IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Put In", 0)
	end,
	canAccept = FeederService.accepts,
	insert = insert,
	tick = tick,
	busy = busy,
}

function FeederService.init()
	MachineService.register(FeederService.Id, behaviour)
	IntakeService.setBulkLoader(FeederService.Id, FeederService.loadAll)
	-- a Capacity level: every feeder of the owner shows (and takes) the new size at once
	ShopService.onBought(function(player, bought)
		if bought.Kind == "Upgrade" and bought.Machine == FeederService.Id then
			for _, machine in MachineService.ofPlayer(player) do
				if machine.Id == FeederService.Id and not machine.Removed then
					show(machine)
				end
			end
		end
	end)
end

-- Every live feeder of the player shows its count again (after Night Shift's machines took ore).
function FeederService.refresh(player: Player)
	for _, machine in MachineService.ofPlayer(player) do
		if machine.Id == FeederService.Id and not machine.Removed then
			show(machine)
		end
	end
end

function FeederService.start() end

-- (tests)
FeederService._test = {
	behaviour = behaviour,
	tick = tick,
	held = held,
}

return FeederService
