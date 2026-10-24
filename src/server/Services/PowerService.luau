--[[
	PowerService: power poles, generators and the machine speeds they give
	(docs/plans/MACHINES_GAME_PLAN.md "WP-Power"; the maths is the pure
	Machines/PowerLogic, the numbers MachineData.PowerRules).

	Owner's rules: power goes through cables and poles; too little power
	slows machines down, it never stops them.

	- A player's networks are worked out again (PowerLogic.compute over the
	  player's placed machines and their types' Speed levels) after every
	  layout change (MachineService.onLayoutChanged: place, move, pickup,
	  spawn, unload), after a Tech shop upgrade of a generator type
	  (ShopService.onBought) and when a power model is rebuilt (the spawned
	  hook, e.g. MachineService.refreshType after a Speed buy: the new model
	  gets the last results at once, a fresh compute follows next frame).
	  Nothing runs per frame.
	- MachineService.addSpeedModifier: a machine with Power > 0 works at its
	  network's speed (PowerService.speedOf; job times are divided by it).
	  A machine the last compute doesn't know yet (placed this frame) makes
	  it compute right away, so a job never starts on a stale speed.
	- Model attributes (only changed ones are written, MachineService.setAttrs):
	    machines (Power > 0)  PowerSpeed  number 0..1, 2 decimals (1 = full speed)
	                          Powered     bool: on a network whose generators make power
	                          Network     string: network id ("" = no pole in reach)
	    generators            PowerOut    number: power it makes at its Speed level
	                          Network     string ("" = no pole in reach: its power goes nowhere)
	    poles                 Network     string: network id (the cell "x,z" of its first pole)
	                          PowerSupply / PowerDemand  numbers: the whole network's
	                          Links       cells of the poles it has a cable to, "x,z;x,z"
	                          Feeds       cells (GridX,GridZ = entry X,Z) of the generators
	                                      and machines it feeds, "x,z;x,z"
	  Links and Feeds use PowerLogic.encodeCells; a link is listed on both
	  of its poles (PowerController draws it once).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local PowerLogic = require(Shared.Machines.PowerLogic)
local DataService = require(script.Parent.DataService)
local MachineService = require(script.Parent.MachineService)
local ShopService = require(script.Parent.ShopService)

local PowerService = {}

type PlacedMachine = MachineService.PlacedMachine
type MachineResult = PowerLogic.MachineResult

-- The last compute of one player: results by saved entry (the same table
-- across moves and model rebuilds) and the attributes each model got.
type State = {
	Results: { [any]: MachineResult },
	Attrs: { [any]: { [string]: any } },
}

local states: { [Player]: State } = {}
local pending: { [Player]: boolean } = {}

-- Does this machine type take part in power (poles, generators, machines with Power,
-- at any of its tiers: the Furnace from Brick up)?
local function isPowerType(info: MachineData.Machine): boolean
	if PowerLogic.kindOf(info) ~= "Other" then
		return true
	end
	local tiers = info.Tiers
	if tiers then
		for tier = 1, #tiers do
			if PowerLogic.kindOf(MachineData.info(info.Id, tier)) ~= "Other" then
				return true
			end
		end
	end
	return false
end

local function cellsOf(indexes: { number }, list: { PlacedMachine }): string
	local cells: { PowerLogic.Cell } = {}
	for _, index in indexes do
		local machine = list[index]
		table.insert(cells, { X = machine.X, Z = machine.Z })
	end
	return PowerLogic.encodeCells(cells)
end

-- Works out the player's networks again and writes the attributes.
local function recompute(player: Player)
	pending[player] = nil
	local list: { PlacedMachine } = {}
	for _, machine in MachineService.ofPlayer(player) do
		if not machine.Removed then
			table.insert(list, machine)
		end
	end
	if #list == 0 then
		states[player] = nil
		return
	end
	local entries: { PowerLogic.Entry } = table.create(#list)
	for i, machine in list do
		entries[i] = { Id = machine.Id, X = machine.X, Z = machine.Z, R = machine.R }
	end
	local data = DataService.get(player)
	local upgrades = data and data.MachineUpgrades
	local result = PowerLogic.compute(entries, PowerLogic.speedLevels(upgrades), upgrades)
	local state: State = { Results = {}, Attrs = {} }
	for i, machine in list do
		local res = result.Machines[i]
		if not res or res.Kind == "Other" then
			continue
		end
		state.Results[machine.Entry] = res
		local attrs: { [string]: any }
		if res.Kind == "Machine" then
			attrs = { PowerSpeed = PowerLogic.round2(res.Speed), Powered = res.Powered, Network = res.Network or "" }
		elseif res.Kind == "Generator" then
			attrs = { PowerOut = PowerLogic.round2(res.PowerOut), Network = res.Network or "" }
		else
			local pole = result.Poles[i]
			local network = pole and result.ByNetwork[pole.Network]
			attrs = {
				Network = if pole then pole.Network else "",
				PowerSupply = PowerLogic.round2(if network then network.Supply else 0),
				PowerDemand = PowerLogic.round2(if network then network.Demand else 0),
				Links = if pole then cellsOf(pole.Links, list) else "",
				Feeds = if pole then cellsOf(pole.Feeds, list) else "",
			}
		end
		state.Attrs[machine.Entry] = attrs
		MachineService.setAttrs(machine, attrs)
	end
	states[player] = state
end

-- Computes again next frame (once, however often it is asked for this frame).
local function schedule(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		if pending[player] then
			recompute(player)
		end
	end)
end

-- The power result of a placed machine (nil = no power part or not computed).
function PowerService.resultOf(machine: PlacedMachine): MachineResult?
	local state = states[machine.Owner]
	return if state then state.Results[machine.Entry] else nil
end

-- How fast a machine works on its power (1 = full speed or needs no power).
function PowerService.speedOf(machine: PlacedMachine): number
	local power = machine.Info.Power
	if not (type(power) == "number" and power > 0) then
		return 1
	end
	local res = PowerService.resultOf(machine)
	if not res and not machine.Removed then
		-- placed this frame: the layout listener hasn't run yet
		recompute(machine.Owner)
		res = PowerService.resultOf(machine)
	end
	return if res then res.Speed else MachineData.PowerRules.UnpoweredSpeed
end

-- A power model was (re)built: give it the last attributes now, compute next frame.
local function onSpawned(machine: PlacedMachine)
	local state = states[machine.Owner]
	local attrs = state and state.Attrs[machine.Entry]
	if attrs then
		MachineService.setAttrs(machine, attrs)
	end
	schedule(machine.Owner)
end

local function onBought(player: Player, bought: ShopService.Bought)
	local id = bought.Machine
	local info = if id then MachineData.ById[id] else nil
	if bought.Kind == "Upgrade" and info and (PowerLogic.kindOf(info) == "Generator" or bought.Upgrade == "Tier") then
		-- a generator makes more, a new tier uses more (the Furnace)
		schedule(player)
	end
end

local function forget(player: Player)
	states[player] = nil
	pending[player] = nil
end

-- Internals for the Lune tests only (tests/Power.spec.luau).
PowerService._test = {
	recompute = recompute,
	schedule = schedule,
	spawned = onSpawned,
	bought = onBought,
	forget = forget,
	state = function(player: Player): State?
		return states[player]
	end,
	reset = function()
		table.clear(states)
		table.clear(pending)
	end,
}

function PowerService.init()
	for _, info in MachineData.List do
		if not info.Retired and isPowerType(info) then
			MachineService.register(info.Id, { spawned = onSpawned })
		end
	end
	MachineService.addSpeedModifier(PowerService.speedOf)
	MachineService.onLayoutChanged(function(player: Player)
		recompute(player)
	end)
	ShopService.onBought(onBought)
end

function PowerService.start()
	Players.PlayerRemoving:Connect(forget)
end

return PowerService
