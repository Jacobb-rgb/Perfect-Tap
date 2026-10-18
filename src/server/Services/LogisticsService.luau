--[[
	LogisticsService: the roster machines that move or sell items instead of
	making them (docs/plans/MACHINES_GAME_PLAN.md, WP-Logi). Behaviour per
	machine type goes through MachineService.register; every timer runs on
	the 10 Hz MachineService tick (table work only, never a loop over parts).

	Splitter / Sorter (MachineData SideOutputs, Grid.sideOutputCell)
	- Intake like a processor: hopper, belt (any side but the front) and the
	  Put In prompt; the saved queue Entry.In holds at most
	  GameConfig.MachineIntakeQueue items (more waits: 'Full'). Owner's items
	  only (MachineLogic.accepts: 'Foreign', 'Wrong' for kinds it can't take).
	- One item leaves every interval (SplitInterval / SortInterval, see
	  interval()) through MachineService.emitSide: straight into a machine
	  standing in the side cell when that face takes it, else as a loose item
	  at OutputL / OutputR moving sideways onto the belt there. A blocked
	  side ('OutputBlocked' / 'TooManyItems') keeps the item in the queue and
	  tries again after GameConfig.OutputRetry.
	- Splitter: left first, then right, in turn; a blocked side gives its
	  turn to the other side (the next item then tries the blocked one first).
	- Sorter: items whose ore rarity Order >= its threshold go right, the rest
	  left, never the other way (a blocked side waits). The threshold is the
	  entry's own setting C (a Rarity Order 1..6, default DefaultThreshold =
	  Rare). MachineAction "SorterCycle" (arg -1 = one step back, anything
	  else one step on, wrapping around) saves the next one in C.
	- Attributes: Queue, QueueMax, Working, Cycles, LastSide (-1 / 1, the
	  side the last item left), Status; the Sorter also Threshold (its Rarity
	  Order) and Detail ("Rare+ ▶ right", the billboard line). A blocked
	  side shows its reason at once; it clears when the queue empties or the
	  next item leaves too (MachineService.outputFlowed), never in between.
	  When the first side is blocked and the other takes the item, nothing
	  shows at all (emitSide quiet).
	- busy: while items wait in the queue (an insert wakes it).

	Robot Arm (MachineData NoIntake)
	- Every interval (ArmInterval) it takes the first finished item (Entry.Out)
	  of the machine whose footprint covers the cell right BEHIND it (against
	  Grid.dir) and hands it to the machine covering the cell right IN FRONT
	  of it, when that machine takes it from the arm's side
	  (ConveyorLogic.faceAllowed + MachineService.canAccept via "Machine").
	  The check comes first, then the pop and the insert with no yield in
	  between, so an item is never in two places or in none.
	- A back machine whose output front faces the arm would only pop its
	  items out loose onto the arm: while the arm has a machine in front that
	  takes items from it, the arm holds that output in (it moves the back
	  machine's MachineService State.NextEmit ArmHold seconds ahead on every
	  tick), so the items wait in the back machine's Out for the arm.
	- Attributes: Working + Holding (the ore id of the item it just moved, ""
	  when idle) for ArmShow seconds after each move, Cycles, Status
	  ("OutputBlocked" while the front machine refuses the item), each
	  written only when it changes.
	- The machines behind and in front are looked up once per layout change
	  (MachineService.layoutVersion), not on every tick. The arm follows the
	  back machine (MachineService.follow) and is busy while that machine
	  is on the tick (it may finish an item any moment), has items in Out,
	  or the arm shows a move or a status; a layout change wakes every arm
	  of the plot.

	Sell Box
	- Intake (hopper, belts from every side, Put In) that takes the owner's
	  items only and sells each one at once at Tobin's price with the
	  owner's sell bonus (Bonuses.sellAmount of SellService.priceOf, the
	  same as the counter and the SellBin): EconomyService.award (source
	  SellSource; onSold listeners get the base price),
	  Stats.ItemsSold + 1, DataService.changed. It never holds an item. An
	  item it can't sell (worth nothing, the owner's save not loaded) is
	  refused, never taken.
	- Feedback like Tobin's SellBin: the sales of one box within SellPopup
	  seconds become one Net "Earned" coin popup (Source "Sell", at the box),
	  the sales within SellToast seconds one toast ("Sell Box: Tobin paid
	  $1.2K for 3 items." with the Dirty Ore reveal).
	- Attribute Cycles (+1 per sale) for effects.
	- The payment is the very LAST step of a sale: the Cycles attribute,
	  the popup / toast batches and the stats come first, then
	  EconomyService.award, DataService.changed and SellService.notifySold
	  (listeners run in their own threads). So an error before it leaves
	  the item with MachineService (it comes back out), never paid AND
	  returned.
	- busy: while a popup or toast waits to be sent (a sale wakes it).

	Speed (interval): base seconds * MachineData.speedMult(the machine type's
	Speed level) / MachineService.speedFactor(machine) (power), never below
	MinInterval.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Grid = require(Shared.Machines.Grid)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local IntakeService = require(script.Parent.IntakeService)
local MachineService = require(script.Parent.MachineService)
local SellService = require(script.Parent.SellService)

local LogisticsService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineLogic.Desc
type Reason = MachineService.Reason
type Via = MachineService.Via

-- What one look of the Robot Arm did.
export type ArmResult = "Moved" | "Idle" | "Refused"

-- Sales of one Sell Box waiting for their popup or toast.
type Batch = { Total: number, Count: number, Descs: { Desc }, FlushAt: number, Position: Vector3 }

-- (side -1 = left, 1 = right) an item leaves by
type Pick = (machine: PlacedMachine, desc: Desc) -> number

LogisticsService.SplitInterval = 0.6 -- seconds per item before Speed upgrades
LogisticsService.SortInterval = 0.6
LogisticsService.ArmInterval = 1.5
LogisticsService.MinInterval = GameConfig.MachineTick
LogisticsService.ArmHold = 0.5 -- seconds the arm holds the back machine's output in after each look
LogisticsService.ArmShow = 1 -- longest a hand-over shows (Working / Holding)
LogisticsService.SellPopup = 2 -- seconds of a Sell Box's sales that make one coin popup
LogisticsService.SellToast = 6 -- ... and one toast
LogisticsService.SellSource = "SellBox" -- EconomyService.award source
LogisticsService.DefaultThreshold = Rarity.get("Rare").Order
LogisticsService.SortPromptName = "SortPrompt"

-- Machine ids by MachineData Behaviour.
local SPLITTER = "Splitter"
local SORTER = "Sorter"
local ROBOT_ARM = "RobotArm"
local SELL_BOX = "SellBox"
-- most dirty-ore names one toast remembers for its reveal
local MAX_TOAST_DESCS = 64

local function count(list: { Desc }?): number
	return if list then #list else 0
end

local function bump(machine: PlacedMachine): number
	local cycles = machine.Model:GetAttribute("Cycles")
	return (if type(cycles) == "number" and cycles == cycles then cycles else 0) + 1
end

---------------------------------------------------------------- speed

-- The owner's Speed level of this machine type (0 without a save).
local function speedLevel(machine: PlacedMachine): number
	local data = DataService.get(machine.Owner)
	return if data then EconomyConfig.upgradeLevel(data, machine.Id, "Speed") else 0
end

-- Seconds between two items: `base` with the Speed level and the
-- machine's current speed (power), never below MinInterval.
function LogisticsService.interval(machine: PlacedMachine, base: number): number
	local seconds = base * MachineData.speedMult(speedLevel(machine)) / MachineService.speedFactor(machine)
	if seconds ~= seconds or seconds == math.huge then
		seconds = base
	end
	return math.max(LogisticsService.MinInterval, seconds)
end

---------------------------------------------------------------- rarity

-- Rarity Order of an ore (0 = unknown).
local function oreOrder(oreId: string): number
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	return if info then info.Order else 0
end

local function rarityAt(order: number): Rarity.RarityInfo?
	for _, info in Rarity.List do
		if info.Order == order then
			return info
		end
	end
	return nil
end

-- A Sorter's threshold: its saved C when that is a Rarity Order, else DefaultThreshold.
function LogisticsService.threshold(machine: PlacedMachine): number
	local saved = machine.Entry.C
	if type(saved) == "number" and saved == saved and rarityAt(math.floor(saved)) then
		return math.floor(saved)
	end
	return LogisticsService.DefaultThreshold
end

-- The billboard line of a threshold: "Rare+ ▶ right".
function LogisticsService.sorterText(order: number): string
	local info = rarityAt(order) or Rarity.get("Rare")
	return `{info.Name}+ ▶ right`
end

-- The threshold after one SorterCycle step (wraps around the rarities).
function LogisticsService.nextThreshold(order: number, step: number): number
	local n = #Rarity.List
	return (order - 1 + step) % n + 1
end

local function showThreshold(machine: PlacedMachine)
	local order = LogisticsService.threshold(machine)
	local text = LogisticsService.sorterText(order)
	MachineService.setAttrs(machine, { Threshold = order, Detail = text })
	local prompt = machine.Model:FindFirstChild(LogisticsService.SortPromptName, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = text
	end
end

---------------------------------------------------------------- Splitter and Sorter

local function routerSpawned(machine: PlacedMachine)
	MachineService.setAttrs(machine, {
		Queue = count(machine.Entry.In),
		QueueMax = GameConfig.MachineIntakeQueue,
		Working = false,
		Cycles = 0,
		LastSide = 0,
		Status = "",
	})
	IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Put In", 0)
end

local function routerCanAccept(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: Via): (boolean, Reason?)
	local ok, reason = MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
	if not ok then
		return false, reason :: Reason?
	end
	if count(machine.Entry.In) >= GameConfig.MachineIntakeQueue then
		return false, "Full"
	end
	return true, nil
end

local function routerInsert(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: Via)
	MachineLogic.push(machine.Entry, desc)
	MachineService.setAttrs(machine, { Queue = count(machine.Entry.In), Working = true })
	DataService.changed(machine.Owner)
end

-- Takes In[1] off the queue (it left, or it was junk).
local function dropFirst(machine: PlacedMachine)
	local entry = machine.Entry
	local queue = entry.In
	if queue then
		table.remove(queue, 1)
		if #queue == 0 then
			entry.In = nil
		end
	end
end

--[[
	One router step: when its interval is up, In[1] leaves by the side
	`pick` chooses (with `fallback`, by the other side when that one is
	blocked). The item leaves the queue only once emitSide handed it on or
	spawned it.
]]
local function route(machine: PlacedMachine, now: number, base: number, pick: Pick, fallback: boolean)
	local state = machine.State
	if now < (state.NextSend or 0) then
		return
	end
	local queue = machine.Entry.In
	local desc = queue and queue[1]
	if desc == nil then
		MachineService.setAttr(machine, "Working", false)
		return
	end
	if not MachineLogic.isValidDesc(desc) then
		-- junk from a damaged save: drop it so the machine doesn't jam
		dropFirst(machine)
		warn(`[LogisticsService] dropped a bad item from {machine.Owner.Name}'s {machine.Id}`)
		MachineService.setAttr(machine, "Queue", count(machine.Entry.In))
		DataService.changed(machine.Owner)
		return
	end
	-- quiet: a side that refuses only shows once the item can't leave at all
	local side = if pick(machine, desc) < 0 then -1 else 1
	local result, _, reason = MachineService.emitSide(machine, desc, side, true)
	if result == "Blocked" and fallback then
		side = -side
		result, _, reason = MachineService.emitSide(machine, desc, side, true)
	end
	if result == "Blocked" then
		-- the item stays first in line
		if reason then
			MachineService.showBlocked(machine, reason)
		end
		state.NextSend = now + GameConfig.OutputRetry
		MachineService.setAttr(machine, "Working", false)
		return
	end
	dropFirst(machine)
	state.LastSide = side
	state.NextSend = now + LogisticsService.interval(machine, base)
	MachineService.setAttrs(machine, {
		Queue = count(machine.Entry.In),
		Working = machine.Entry.In ~= nil,
		LastSide = side,
		Cycles = bump(machine),
	})
	MachineService.outputFlowed(machine, machine.Entry.In == nil)
	DataService.changed(machine.Owner)
end

-- A Splitter / Sorter needs the tick while items wait in its queue.
local function routerBusy(machine: PlacedMachine, _now: number): boolean
	return machine.Entry.In ~= nil
end

-- Splitter: left first, then the side the last item didn't take.
local function splitterPick(machine: PlacedMachine, _desc: Desc): number
	return if machine.State.LastSide == -1 then 1 else -1
end

-- Sorter: its threshold rarity and better to the right, the rest to the left.
local function sorterPick(machine: PlacedMachine, desc: Desc): number
	return if oreOrder(desc.O) >= LogisticsService.threshold(machine) then 1 else -1
end

-- MachineAction "SorterCycle" (the dispatcher checked owner and range; `arg` is raw).
local function onSorterCycle(player: Player, machine: PlacedMachine, arg: any)
	if machine.Info.Behaviour ~= SORTER or machine.Removed then
		return
	end
	local step = if arg == -1 then -1 else 1
	local order = LogisticsService.nextThreshold(LogisticsService.threshold(machine), step)
	machine.Entry.C = order
	showThreshold(machine)
	DataService.changed(player)
end

-- The Sorter's own button (PC G, gamepad ButtonB, touch tap): steps the
-- threshold like SorterCycle. Owner only; the prompt's range is the check.
local function addSortPrompt(machine: PlacedMachine)
	local base = machine.Model.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = LogisticsService.SortPromptName
	prompt.ActionText = "Change Sort"
	prompt.ObjectText = LogisticsService.sorterText(LogisticsService.threshold(machine))
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 72)
	prompt.Parent = base:FindFirstChild("Prompt") or base
	prompt.Triggered:Connect(function(player: Player)
		if player == machine.Owner then
			onSorterCycle(player, machine, 1)
		end
	end)
end

local splitterBehaviour: MachineService.Behaviour = {
	spawned = routerSpawned,
	canAccept = routerCanAccept,
	insert = routerInsert,
	tick = function(machine: PlacedMachine, now: number)
		route(machine, now, LogisticsService.SplitInterval, splitterPick, true)
	end,
	busy = routerBusy,
}

local sorterBehaviour: MachineService.Behaviour = {
	spawned = function(machine: PlacedMachine)
		routerSpawned(machine)
		showThreshold(machine)
		addSortPrompt(machine)
	end,
	canAccept = routerCanAccept,
	insert = routerInsert,
	tick = function(machine: PlacedMachine, now: number)
		route(machine, now, LogisticsService.SortInterval, sorterPick, false)
	end,
	busy = routerBusy,
}

---------------------------------------------------------------- Robot Arm

-- The other machine covering the cell (dx, dz) away from the arm, if any.
local function besideArm(arm: PlacedMachine, dx: number, dz: number): PlacedMachine?
	local machine = MachineService.atCell(arm.PlotId, arm.X + dx, arm.Z + dz)
	if machine and machine ~= arm and not machine.Removed and machine.Owner == arm.Owner then
		return machine
	end
	return nil
end

-- The machines behind and in front of the arm.
local function armNeighbours(arm: PlacedMachine): (PlacedMachine?, PlacedMachine?)
	local dx, dz = Grid.dir(arm.R)
	return besideArm(arm, -dx, -dz), besideArm(arm, dx, dz)
end

-- Does `front` take items, from the arm's side?
local function frontTakes(arm: PlacedMachine, front: PlacedMachine): boolean
	return MachineService.hasIntake(front) and ConveyorLogic.faceAllowed(front.Entry, arm.X, arm.Z)
end

-- What the arm knows about its neighbours since the last layout change.
type ArmCache = {
	Version: number, -- MachineService.layoutVersion of the arm's plot when looked up
	Back: PlacedMachine?,
	Front: PlacedMachine?,
	Takes: boolean, -- the front takes items from the arm's side (frontTakes)
	Holds: boolean, -- the back machine's output front faces the arm: hold it in
}

-- The arm's neighbours, looked up again only after a layout change.
local function armCache(arm: PlacedMachine): ArmCache
	local state = arm.State
	local version = MachineService.layoutVersion(arm.PlotId)
	local cached = state.Neighbours :: ArmCache?
	if cached and cached.Version == version then
		return cached
	end
	local back, front = armNeighbours(arm)
	local takes = back ~= nil and front ~= nil and frontTakes(arm, front)
	local holds = false
	if back and takes then
		local ox, oz = Grid.outputCell(back.Id, back.X, back.Z, back.R)
		holds = ox == arm.X and oz == arm.Z
	end
	-- wake whenever the back machine wakes: it may finish an item any moment
	local before = cached and cached.Back
	if before ~= back then
		if before then
			MachineService.unfollow(arm, before)
		end
		if back then
			MachineService.follow(arm, back)
		end
	end
	local fresh: ArmCache = { Version = version, Back = back, Front = front, Takes = takes, Holds = holds }
	state.Neighbours = fresh
	return fresh
end

--[[
	Moves at most one item from back's Out into front. The check comes
	first, then the pop and the insert with no yield in between. `takes`:
	frontTakes already worked out (the arm's cache), nil = check now.
]]
local function armMove(arm: PlacedMachine, back: PlacedMachine?, front: PlacedMachine?, takes: boolean?): (ArmResult, Desc?)
	if not back or not front or back == front then
		return "Idle", nil
	end
	local out = back.Entry.Out
	local desc = out and out[1]
	if desc == nil or not MachineLogic.isValidDesc(desc) then
		-- nothing finished (junk is the MachineService tick's to drop)
		return "Idle", nil
	end
	local owner = arm.Owner.UserId
	local ok = if takes == nil then frontTakes(arm, front) else takes
	if not ok or not MachineService.canAccept(front, desc, owner, "Machine") then
		return "Refused", nil
	end
	local item = MachineLogic.popOut(back.Entry) :: Desc
	if not MachineService.insertDesc(front, item, owner, "Machine") then
		-- can't happen (nothing changed since the check), but never lose it
		local list = back.Entry.Out or {}
		back.Entry.Out = list
		table.insert(list, 1, item)
		return "Refused", nil
	end
	local left = back.Entry.Out
	MachineService.setAttr(back, "OutCount", if left then #left else 0)
	MachineService.outputFlowed(back, left == nil)
	DataService.changed(arm.Owner)
	return "Moved", item
end

-- One look of the arm from outside (the tests): the machines around it right now.
function LogisticsService.armMove(arm: PlacedMachine): (ArmResult, Desc?)
	local back, front = armNeighbours(arm)
	return armMove(arm, back, front)
end

-- The arm's Status, written only when it changes.
local function armStatus(arm: PlacedMachine, status: string)
	if arm.State.Status ~= status then
		arm.State.Status = status
		MachineService.setAttr(arm, "Status", status)
	end
end

local function armTick(arm: PlacedMachine, now: number)
	local state = arm.State
	local showUntil = state.ShowUntil
	if showUntil and now >= showUntil then
		state.ShowUntil = nil
		MachineService.setAttr(arm, "Working", false)
		MachineService.setAttr(arm, "Holding", "")
	end
	local cache = armCache(arm)
	local back, front = cache.Back, cache.Front
	if back and cache.Holds then
		-- the back machine's output front faces the arm: keep its items in for the arm
		local held = tonumber(back.State.NextEmit) or 0
		back.State.NextEmit = math.max(held, now + LogisticsService.ArmHold)
	end
	if now < (state.NextMove or 0) then
		return
	end
	local result, item = armMove(arm, back, front, cache.Takes)
	if result == "Moved" and item then
		local seconds = LogisticsService.interval(arm, LogisticsService.ArmInterval)
		state.NextMove = now + seconds
		state.ShowUntil = now + math.min(seconds * 0.8, LogisticsService.ArmShow)
		MachineService.setAttrs(arm, { Working = true, Holding = item.O, Cycles = bump(arm) })
		armStatus(arm, "")
	else
		armStatus(arm, if result == "Refused" then "OutputBlocked" else "")
	end
end

--[[
	Does the arm need the tick? While it shows a move or a status, after a
	layout change (it looks again), and while it has a back and a front
	machine and the back one has items in Out or is on the tick itself (it
	may finish one any moment; the arm holds its output in meanwhile).
]]
local function armBusy(arm: PlacedMachine, _now: number): boolean
	local state = arm.State
	if state.ShowUntil ~= nil or (state.Status ~= nil and state.Status ~= "") then
		return true
	end
	local cache = state.Neighbours :: ArmCache?
	if not cache or cache.Version ~= MachineService.layoutVersion(arm.PlotId) then
		return true
	end
	local back = cache.Back
	if not back or not cache.Front or back.Removed then
		return false
	end
	local out = back.Entry.Out
	return (out ~= nil and #out > 0) or MachineService.isActive(back)
end

local armBehaviour: MachineService.Behaviour = {
	spawned = function(arm: PlacedMachine)
		arm.State.Status = ""
		MachineService.setAttrs(arm, { Working = false, Holding = "", Cycles = 0, Status = "" })
	end,
	tick = armTick,
	busy = armBusy,
}

-- After a layout change the plot's arms look at their neighbours again.
local function wakeArms(_player: Player, plotId: number)
	for _, machine in MachineService.ofPlot(plotId) do
		if machine.Info.Behaviour == ROBOT_ARM then
			MachineService.wake(machine)
		end
	end
end

---------------------------------------------------------------- Sell Box

local function sellPosition(machine: PlacedMachine): Vector3
	local cf = MachineService.point(machine, "Intake")
	return if cf then cf.Position else machine.Model:GetPivot().Position + Vector3.new(0, 4, 0)
end

local function addSale(machine: PlacedMachine, key: string, window: number, desc: Desc, price: number, now: number)
	local batch = machine.State[key] :: Batch?
	if not batch then
		local fresh: Batch = { Total = 0, Count = 0, Descs = {}, FlushAt = now + window, Position = sellPosition(machine) }
		machine.State[key] = fresh
		batch = fresh
	end
	local b = batch :: Batch
	b.Total += price
	b.Count += 1
	if #b.Descs < MAX_TOAST_DESCS then
		table.insert(b.Descs, desc)
	end
end

-- "Sell Box: Tobin paid $1.2K for 3 items." plus the Dirty Ore reveal
-- (coloured by the rarest revealed ore from Rare up), like Tobin's toast.
local function saleToast(machine: PlacedMachine, batch: Batch): { [string]: any }
	local reveal, rarityId = SellService.revealText(batch.Descs)
	local message: { [string]: any } = {
		Text = `{machine.Info.Name}: {SellService.paidText(batch.Total, batch.Count)}{reveal}`,
		Kind = "Reward",
	}
	local info = rarityId and Rarity.ById[rarityId]
	if info and info.Order >= 3 then
		message.Rarity = rarityId
	end
	return message
end

-- Sends the popup and toast whose time is up (all of them with `all`).
local function flushSales(machine: PlacedMachine, now: number, all: boolean)
	local state = machine.State
	local player = machine.Owner
	local popup = state.SalePopup :: Batch?
	if popup and (all or now >= popup.FlushAt) then
		state.SalePopup = nil
		if player.Parent then
			Net.fire("Earned", player, { Amount = popup.Total, Source = "Sell", Position = popup.Position, Count = popup.Count })
		end
	end
	local toast = state.SaleToast :: Batch?
	if toast and (all or now >= toast.FlushAt) then
		state.SaleToast = nil
		if player.Parent then
			Net.fire("Notify", player, saleToast(machine, toast))
		end
	end
end

local function sellCanAccept(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: Via): (boolean, Reason?)
	local ok, reason = MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
	if not ok then
		return false, reason :: Reason?
	end
	if SellService.priceOf(desc) <= 0 then
		return false, "Wrong"
	end
	if not DataService.get(machine.Owner) then
		return false, "Busy"
	end
	return true, nil
end

local function sellInsert(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: Via)
	local player = machine.Owner
	local data = DataService.get(player)
	local base = SellService.priceOf(desc)
	if not data or base <= 0 then
		-- canAccept said yes a moment ago; MachineService puts the item back out
		error("the Sell Box can't sell this right now")
	end
	-- the same bonus as Tobin's counter and the SellBin (Midas, SellValue
	-- golems, collection rewards); onSold listeners still get the base price
	local price = Bonuses.sellAmount(Bonuses.stats(player), base)
	local sold: Desc = { K = desc.K, O = desc.O, G = desc.G, R = desc.R }
	-- everything that could fail comes first: an error here sends the item
	-- back out (MachineService.deliver) with nothing paid
	MachineService.setAttr(machine, "Cycles", bump(machine))
	local now = os.clock()
	addSale(machine, "SalePopup", LogisticsService.SellPopup, sold, price, now)
	addSale(machine, "SaleToast", LogisticsService.SellToast, sold, price, now)
	local stats = (data :: { [string]: any }).Stats
	if type(stats) == "table" then
		local before = tonumber(stats.ItemsSold) or 0
		stats.ItemsSold = (if before == before then before else 0) + 1
	end
	-- the payment is the very last step (listeners run in their own threads)
	EconomyService.award(player, price, LogisticsService.SellSource, true)
	DataService.changed(player)
	SellService.notifySold(player, sold, base)
end

-- A Sell Box needs the tick while a popup or toast waits to be sent.
local function sellBusy(machine: PlacedMachine, _now: number): boolean
	return machine.State.SalePopup ~= nil or machine.State.SaleToast ~= nil
end

local sellBehaviour: MachineService.Behaviour = {
	spawned = function(machine: PlacedMachine)
		MachineService.setAttrs(machine, { Working = false, Cycles = 0, Status = "" })
		IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Put In", 0)
	end,
	removed = function(machine: PlacedMachine, _reason: MachineService.RemoveReason)
		-- the coins are paid already: say so before the box goes
		flushSales(machine, os.clock(), true)
	end,
	canAccept = sellCanAccept,
	insert = sellInsert,
	tick = function(machine: PlacedMachine, now: number)
		flushSales(machine, now, false)
	end,
	busy = sellBusy,
}

---------------------------------------------------------------- lifecycle

-- Behaviour per MachineData Behaviour.
local BEHAVIOURS: { [string]: MachineService.Behaviour } = {
	[SPLITTER] = splitterBehaviour,
	[SORTER] = sorterBehaviour,
	[ROBOT_ARM] = armBehaviour,
	[SELL_BOX] = sellBehaviour,
}

-- Internals for the Lune tests only (tests/Logistics.spec.luau).
LogisticsService._test = {
	splitter = splitterBehaviour,
	sorter = sorterBehaviour,
	arm = armBehaviour,
	sellBox = sellBehaviour,
	sorterCycle = onSorterCycle,
	flushSales = flushSales,
	wakeArms = wakeArms,
}

function LogisticsService.init()
	for _, info in MachineData.List do
		local behaviour = info.Behaviour and BEHAVIOURS[info.Behaviour]
		if behaviour and not info.Retired then
			MachineService.register(info.Id, behaviour)
		end
	end
	MachineService.onAction("SorterCycle", onSorterCycle)
	MachineService.onLayoutChanged(wakeArms)
end

function LogisticsService.start() end

return LogisticsService
