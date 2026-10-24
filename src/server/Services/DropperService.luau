--[[
	DropperService: the droppers and the Money Laser on the plots (owner
	2026-10-24: real ore on the belts, DropperConfig).

	Droppers (MachineData Behaviour "Dropper", no intake)
	- Every DropperConfig.DropEvery seconds a dropper pushes one Drop
	  ({ K = "Drop", O = its id }) out of its front with MachineService.emit:
	  straight into the machine standing there (a Money Laser, a Splitter, a
	  Sell Box) when it takes it, else as a light loose item onto the belt in
	  front. A blocked front ('OutputBlocked', 'TooManyItems': the owner's
	  loose-item cap) skips that Drop and tries again after
	  GameConfig.OutputRetry: nothing piles up, nothing is owed.
	- It also waits (Status "TooManyItems") while its owner has
	  DropperConfig.MaxLiveDrops Drops in the world (loose, or waiting in a
	  laser / splitter), or the server MaxLiveDropsServer: canDrop.
	- Its value is never on the item: SellService.boxPriceOf / ItemData.value
	  read it from the dropper's id (and the laser's mark) on the server;
	  Tobin never buys one (SellService.priceOf is 0 for a Drop).

	Money Laser (Behaviour "Laser", 1 x 1, fed by belts from every side but
	its front)
	- Takes its owner's Drops only (MachineLogic.accepts: 'Foreign', 'Wrong'
	  for anything else), at most LaserQueue waiting ('Full'). Every Drop
	  that goes in gets the laser's mark (R = DropperConfig.LaserMark: worth
	  Laser.Mult times as much, once; a marked one passes as it is) and goes
	  into its Out queue: MachineService's tick pushes it out of the front,
	  onto the belt or into the machine there (a Sell Box).
	- Attributes: Cycles (+1 per doubled Drop) for effects.

	Live Drops (a pass every SweepEvery seconds, a walk over the records of
	the owners that have droppers or Drops, never over every item)
	- Counts each owner's Drops in the world (loose, or waiting in a laser /
	  splitter queue; anything not Consumed) for canDrop, and removes the
	  LOOSE ones older than DropperConfig.DropLife (one fell off a belt, a
	  belt ends nowhere, or a ride longer than DropLife: ~79 cells of belt).
	- A Drop never stays: storeDesc refuses it ("Lost": leaving, rescues, a
	  return from someone else's plot just remove it; a Drop on another
	  player's plot pays nobody, their Sell Box refuses it as 'Foreign'),
	  CarryService never picks it up, the magnet never pulls it, the Ore Pen
	  destroys one that rolls in, and the saves never keep one: stripped
	  from the machine queues and the pen before a leaving player's last
	  save here, and from any save on load (Data/Migrations).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperConfig = require(Shared.Config.DropperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local MachineLogic = require(Shared.Machines.MachineLogic)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local MachineService = require(script.Parent.MachineService)

local DropperService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineLogic.Desc
type Reason = MachineService.Reason
type Via = MachineService.Via

DropperService.LaserQueue = 3 -- Drops waiting in one laser's Out queue at most
DropperService.SweepEvery = 1 -- seconds between two live-Drop passes

-- owner UserId -> their live Drops (the last pass + what spawned since)
local live: { [number]: number } = {}
local liveTotal = 0
-- owners to look at in the pass: they have droppers placed, or Drops out
local watched: { [number]: boolean } = {}

-- May a dropper of an owner with `mine` live Drops push one more while the
-- server has `total`? (pure: tests/DropperDrops.spec.luau)
function DropperService.canDrop(mine: number, total: number): boolean
	return mine < DropperConfig.MaxLiveDrops and total < DropperConfig.MaxLiveDropsServer
end

-- A Drop after a Money Laser: marked once (a marked Drop passes as it is).
function DropperService.lasered(desc: Desc): Desc
	return { K = desc.K, O = desc.O, R = DropperConfig.LaserMark }
end

function DropperService.liveOf(userId: number): number
	return live[userId] or 0
end

---------------------------------------------------------------- droppers

local function dropperSpawned(machine: PlacedMachine)
	watched[machine.Owner.UserId] = true
	-- (spread the plot's droppers a little so their Drops don't land together)
	machine.State.NextDrop = os.clock() + DropperConfig.DropEvery * (0.5 + (machine.X + machine.Z) % 5 / 10)
	MachineService.setAttrs(machine, { Status = "", Cycles = 0 })
end

local function dropperTick(machine: PlacedMachine, now: number)
	local state = machine.State
	if now < (state.NextDrop or 0) then
		return
	end
	local owner = machine.Owner.UserId
	if not DropperService.canDrop(live[owner] or 0, liveTotal) then
		MachineService.showBlocked(machine, "TooManyItems")
		state.NextDrop = now + GameConfig.OutputRetry
		return
	end
	local result = MachineService.emit(machine, { K = DropperConfig.DropKind, O = machine.Id })
	if result == "Blocked" then
		state.NextDrop = now + GameConfig.OutputRetry
		return
	end
	live[owner] = (live[owner] or 0) + 1
	liveTotal += 1
	state.NextDrop = now + DropperConfig.DropEvery
	state.Cycles = (state.Cycles or 0) + 1
	MachineService.setAttr(machine, "Cycles", state.Cycles)
	MachineService.outputFlowed(machine, true)
end

-- A dropper always has its next Drop to make.
local function dropperBusy(_machine: PlacedMachine, _now: number): boolean
	return true
end

---------------------------------------------------------------- the Money Laser

local function laserSpawned(machine: PlacedMachine)
	watched[machine.Owner.UserId] = true
	MachineService.setAttrs(machine, { Status = "", Cycles = 0 })
end

local function laserCanAccept(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: Via): (boolean, Reason?)
	local ok, reason = MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
	if not ok then
		return false, reason :: Reason?
	end
	local out = machine.Entry.Out
	if out and #out >= DropperService.LaserQueue then
		return false, "Full"
	end
	return true, nil
end

local function laserInsert(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: Via)
	local doubled = desc.R ~= DropperConfig.LaserMark
	MachineService.pushOut(machine, DropperService.lasered(desc))
	if doubled then
		local state = machine.State
		state.Cycles = (state.Cycles or 0) + 1
		MachineService.setAttr(machine, "Cycles", state.Cycles)
	end
end

---------------------------------------------------------------- live Drops

-- One pass (see the header): counts the watched owners' Drops, removes the
-- loose ones older than DropLife, forgets owners with neither.
function DropperService.sweep(now: number)
	local total = 0
	for userId in watched do
		local count = 0
		for _, record in ItemService.ownedBy(userId) do
			if record.Kind == DropperConfig.DropKind and record.State ~= "Consumed" then
				if record.State == "Loose" and now - record.CreatedAt > DropperConfig.DropLife then
					ItemService.destroy(record)
				else
					count += 1
				end
			end
		end
		live[userId] = count
		total += count
		if count == 0 then
			local any = false
			for _, machine in MachineService.all() do
				if machine.Owner.UserId == userId and (machine.Info.Behaviour == "Dropper" or machine.Info.Behaviour == "Laser") then
					any = true
					break
				end
			end
			if not any then
				watched[userId] = nil
				live[userId] = nil
			end
		end
	end
	liveTotal = total
end

-- Takes every Drop out of a save (machine queues, the pen); returns how many.
function DropperService.stripSave(data: { [string]: any }): number
	local removed = DropperConfig.stripDrops(data.Storage)
	local placed = data.PlacedMachines
	if type(placed) == "table" then
		for _, entry in placed do
			if type(entry) == "table" then
				for _, field in { "In", "Out" } do
					local queue = entry[field]
					if type(queue) == "table" then
						removed += DropperConfig.stripDrops(queue)
						if #queue == 0 then
							entry[field] = nil
						end
					end
				end
			end
		end
	end
	return removed
end

-- Internals for the Lune tests only (tests/DropperService.spec.luau).
DropperService._test = {
	-- forget the live counts and the watched owners
	reset = function()
		table.clear(live)
		table.clear(watched)
		liveTotal = 0
	end,
}

---------------------------------------------------------------- lifecycle

function DropperService.init()
	for _, info in MachineData.List do
		if info.Behaviour == "Dropper" then
			MachineService.register(info.Id, { spawned = dropperSpawned, tick = dropperTick, busy = dropperBusy })
		elseif info.Behaviour == "Laser" then
			MachineService.register(info.Id, { spawned = laserSpawned, canAccept = laserCanAccept, insert = laserInsert })
		end
	end
	-- a leaving player's last save keeps no Drop (their loose ones go with ItemService's stash)
	DataService.beforeRelease(function(player, data)
		DropperService.stripSave(data)
		watched[player.UserId] = nil
		live[player.UserId] = nil
	end)
end

function DropperService.start()
	while true do
		task.wait(DropperService.SweepEvery)
		local ok, err = pcall(function()
			DropperService.sweep(os.clock())
		end)
		if not ok then
			warn("[DropperService] sweep failed: " .. tostring(err))
		end
	end
end

return DropperService
