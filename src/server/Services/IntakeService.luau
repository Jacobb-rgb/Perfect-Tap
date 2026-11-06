--[[
	IntakeService: the only scanner that moves loose items into machines.

	- Hoppers: the box around a machine's Intake attachment (IntakeSize +
	  IntakeMargin). Only machines whose behaviour takes items have one.
	- Belt ends: a belt whose front cell is a machine face that takes items
	  (ConveyorLogic.feeders) hands over anything pressed against that face.
	  The box reaches FeedReachBelt back onto the belt and FeedReachInto into
	  the machine's cell, so it works wherever the item comes to rest.
	- Town zones (Tobin's SellBin, the Ore Pens) are added with addZone().
	- Items on a belt that no box takes go to the belt handler (ConveyorService).
	  The belt is the one at the item's height (MachineService.atHeight):
	  up at deck level the deck's belt, under a deck the ground one.
	- Items lying on someone else's plot go back to their owner's Storage
	  after ForeignItemReturn seconds.
	- Put In prompts (addLoadPrompt): load what you carry into a machine.
	- An item dropped into a hopper that is full (or busy) waits there; if
	  the player dropped or threw it (HandDropped), its owner gets an Fx
	  'Full' ("FULL" / "BUSY" pops over the hopper with the deny sound,
	  MachineFxController) once per drop, at most once per FULL_POP_GAP
	  per machine.

	Zones are pure maths in a per-plot cell index, rebuilt on every layout
	change, so the 5 Hz scan costs a few box tests per item and no spatial
	queries. Items a client may have moved implausibly (ItemService.isTrusted)
	are skipped until the server has them back.

	Town zones (perf pass 1, SERVER_PERF_AUDIT #5): their boxes (CFrame, half
	size) are cached in an index, rebuilt when a zone is added or a zone
	part moves, resizes or leaves; an item on a plot (plotAt first) is
	tested only against the zones over that plot, any other item only
	against the zones in its TOWN_CELL square. The first zone in the order
	they were added still wins, as before.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local PromptConfig = require(Shared.Config.PromptConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Grid = require(Shared.Machines.Grid)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local Net = require(Shared.Net)
local CarryService = require(script.Parent.CarryService)
local ItemService = require(script.Parent.ItemService)
local MachineService = require(script.Parent.MachineService)
local PlotService = require(script.Parent.PlotService)

local IntakeService = {}

type PlacedMachine = MachineService.PlacedMachine
type ItemRecord = ItemService.ItemRecord
type Reason = MachineService.Reason
type Via = MachineService.Via
type Desc = MachineService.Desc

type Zone = {
	Kind: "Hopper" | "Feeder",
	Machine: PlacedMachine, -- the machine the item goes into
	Belt: PlacedMachine?, -- the feeding belt (feeders only)
	CFrame: CFrame, -- box centre, world space
	Half: Vector3, -- half the box size
}
type StaticZone = {
	Name: string,
	Part: BasePart,
	Handler: (ItemRecord) -> ...any,
	CFrame: CFrame, -- cached box (rebuildStatic)
	Half: Vector3,
}
export type BeltHandler = (belt: PlacedMachine, record: ItemRecord, localPos: Vector3, now: number) -> ...any

local CELL = GameConfig.CellSize
local CELLS = GameConfig.PlotCells
local HALF = CELLS * CELL / 2
-- zone boxes that exactly touch a cell edge don't count that neighbour cell
local EDGE = 0.01
-- Put In prompt: at most this many items per press (a machine's queue holds far fewer)
local MAX_LOAD = 64
local WARN_COOLDOWN = 10
-- Full / Busy feedback: a refusal after this many seconds without one is a
-- new drop (an item picked up and thrown in again; one lying in the hopper
-- is refused every scan)...
local FULL_SEEN_GAP = 1
-- ...and one machine pops at most this often (a whole stack dropped at once: one pop)
local FULL_POP_GAP = 1.5

-- plotId -> cell key -> zones on that cell (hoppers before feeders)
local plotZones: { [number]: { [number]: { Zone } } } = {}
local staticZones: { StaticZone } = {}
-- the town zone index: zones over each plot's square, the rest by town square
local TOWN_CELL = 32
local staticDirty = true
local plotStatic: { [number]: { StaticZone } } = {}
local townStatic: { [number]: { StaticZone } } = {}
local beltHandler: BeltHandler? = nil
local lastReject: { [ItemRecord]: number } = setmetatable({}, { __mode = "k" }) :: any
-- the last Full / Busy refusal of each dropped item, the last pop of each machine
local fullSeen: { [ItemRecord]: number } = setmetatable({}, { __mode = "k" }) :: any
local fullPopAt: { [PlacedMachine]: number } = setmetatable({}, { __mode = "k" }) :: any
local foreignSince: { [ItemRecord]: number } = setmetatable({}, { __mode = "k" }) :: any
local hintTimes: { [Player]: { [string]: number } } = {}
local lastWarn: { [string]: number } = {}

local function warnThrottled(key: string, message: string)
	local now = os.clock()
	if now - (lastWarn[key] or -math.huge) >= WARN_COOLDOWN then
		lastWarn[key] = now
		warn(message)
	end
end

local function inBox(cf: CFrame, half: Vector3, position: Vector3): boolean
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

---------------------------------------------------------------- zone index

-- Registers a zone on every plot cell its box covers.
local function addZoneToCells(cells: { [number]: { Zone } }, plotCF: CFrame, zone: Zone)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = zone.CFrame:PointToWorldSpace(Vector3.new(sx * zone.Half.X, 0, sz * zone.Half.Z))
			local p = plotCF:PointToObjectSpace(corner)
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
	end
	local x0 = math.max(0, math.floor((minX + EDGE + HALF) / CELL))
	local x1 = math.min(CELLS - 1, math.floor((maxX - EDGE + HALF) / CELL))
	local z0 = math.max(0, math.floor((minZ + EDGE + HALF) / CELL))
	local z1 = math.min(CELLS - 1, math.floor((maxZ - EDGE + HALF) / CELL))
	for cz = z0, z1 do
		for cx = x0, x1 do
			local key = Grid.key(cx, cz)
			local list = cells[key]
			if not list then
				list = {}
				cells[key] = list
			end
			table.insert(list, zone)
		end
	end
end

local function hopperZone(machine: PlacedMachine): Zone?
	local base = machine.Model.PrimaryPart
	local intake = base and base:FindFirstChild("Intake")
	if not intake or not intake:IsA("Attachment") then
		return nil
	end
	local size = intake:GetAttribute("IntakeSize")
	if typeof(size) ~= "Vector3" then
		return nil
	end
	local margin = GameConfig.IntakeMargin
	return {
		Kind = "Hopper",
		Machine = machine,
		CFrame = (base :: BasePart).CFrame * intake.CFrame,
		Half = (size :: Vector3) / 2 + Vector3.new(margin, margin, margin),
	}
end

-- Belt-local box at the belt's front end (-front, front = half its length:
-- 2 on a 1x1 belt, 6 on a Belt Lift / Slide): x +/-2, y 0..4 over where
-- the items arrive (a Belt Lift's front end is up at the deck), z from
-- -front - FeedReachInto (into the machine's cell) to -front +
-- FeedReachBelt (back onto the belt).
local function feederZone(belt: PlacedMachine, target: PlacedMachine): Zone
	local front = belt.Info.Size[2] * CELL / 2
	local zMin = -front - GameConfig.FeedReachInto
	local zMax = -front + GameConfig.FeedReachBelt
	local up = if belt.Info.Slope == "Up" then MachineData.DeckHeight else 0
	return {
		Kind = "Feeder",
		Machine = target,
		Belt = belt,
		CFrame = belt.Model:GetPivot() * CFrame.new(0, up + 2, (zMin + zMax) / 2),
		Half = Vector3.new(CELL / 2, 2, (zMax - zMin) / 2),
	}
end

local function rebuild(plotId: number)
	local machines = MachineService.ofPlot(plotId)
	local cells: { [number]: { Zone } } = {}
	local plotCF = PlotService.plotCFrame(plotId)
	local entries: { MachineService.Entry } = {}
	local byEntry: { [MachineService.Entry]: PlacedMachine } = {}
	-- hoppers first, so they win over feeders on the same cell
	for _, machine in machines do
		if not machine.Removed then
			table.insert(entries, machine.Entry)
			byEntry[machine.Entry] = machine
			if MachineService.hasIntake(machine) then
				local zone = hopperZone(machine)
				if zone then
					addZoneToCells(cells, plotCF, zone)
				end
			end
		end
	end
	for _, feeder in ConveyorLogic.feeders(entries) do
		local belt = byEntry[feeder.Conveyor]
		local target = byEntry[feeder.Target]
		if belt and target and MachineService.hasIntake(target) then
			addZoneToCells(cells, plotCF, feederZone(belt, target))
		end
	end
	if next(cells) then
		plotZones[plotId] = cells
	else
		plotZones[plotId] = nil
	end
end

---------------------------------------------------------------- town zone index

local function townKey(cx: number, cz: number): number
	return cx * 65536 + cz
end

-- World-space box around a zone: (min, max).
local function bounds(cf: CFrame, half: Vector3): (Vector3, Vector3)
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local extent = Vector3.new(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	)
	return cf.Position - extent, cf.Position + extent
end

-- Caches every zone's box and files it under the plots it lies over and
-- the town squares it touches (in the order the zones were added).
local function rebuildStatic()
	staticDirty = false
	table.clear(plotStatic)
	table.clear(townStatic)
	local reach = PlotService.PlotReach
	for _, zone in staticZones do
		local part = zone.Part
		if not part.Parent then
			continue -- gone (it comes back with a rebuild when it is parented again)
		end
		zone.CFrame = part.CFrame
		zone.Half = part.Size / 2
		local min, max = bounds(zone.CFrame, zone.Half)
		for _, plot in WorldLayout.Plots do
			local c = plot.Center
			if max.X >= c.X - reach and min.X <= c.X + reach and max.Z >= c.Z - reach and min.Z <= c.Z + reach then
				local list = plotStatic[plot.Id]
				if not list then
					list = {}
					plotStatic[plot.Id] = list
				end
				table.insert(list, zone)
			end
		end
		for cx = math.floor(min.X / TOWN_CELL), math.floor(max.X / TOWN_CELL) do
			for cz = math.floor(min.Z / TOWN_CELL), math.floor(max.Z / TOWN_CELL) do
				local key = townKey(cx, cz)
				local list = townStatic[key]
				if not list then
					list = {}
					townStatic[key] = list
				end
				table.insert(list, zone)
			end
		end
	end
end

local function markStatic()
	staticDirty = true
end

-- The town zones an item at `position` can be in (`plotId`: plotAt's answer).
local function staticNear(position: Vector3, plotId: number?): { StaticZone }?
	if staticDirty then
		rebuildStatic()
	end
	if plotId then
		return plotStatic[plotId]
	end
	return townStatic[townKey(math.floor(position.X / TOWN_CELL), math.floor(position.Z / TOWN_CELL))]
end

---------------------------------------------------------------- public API

-- A fixed box in the world (not on a plot) that takes trusted loose items,
-- e.g. Tobin's SellBin. The handler owns the item from then on. The Ore
-- Magnet never pulls items into or past the zone (ItemService.magnetAvoid).
function IntakeService.addZone(name: string, part: BasePart, handler: (ItemRecord) -> ...any)
	table.insert(staticZones, { Name = name, Part = part, Handler = handler, CFrame = part.CFrame, Half = part.Size / 2 })
	staticDirty = true
	-- the cached box follows the part
	part:GetPropertyChangedSignal("CFrame"):Connect(markStatic)
	part:GetPropertyChangedSignal("Size"):Connect(markStatic)
	part.AncestryChanged:Connect(markStatic)
	ItemService.magnetAvoid(part)
end

-- Called for every trusted loose item on a belt cell that no hopper or belt
-- end took. localPos is the item's position in the belt model's space
-- (front = -Z, the way items move). One handler (ConveyorService).
function IntakeService.setBeltHandler(handler: BeltHandler)
	if beltHandler then
		warn("[IntakeService] belt handler replaced")
	end
	beltHandler = handler
end

-- Throttled toast: at most once per WrongHintCooldown per player per machine type.
function IntakeService.hint(player: Player, machineId: string, text: string)
	local times = hintTimes[player]
	if not times then
		times = {}
		hintTimes[player] = times
	end
	local now = os.clock()
	if now - (times[machineId] or -math.huge) < GameConfig.WrongHintCooldown then
		return
	end
	times[machineId] = now
	Net.fire("Notify", player, { Text = text, Kind = "Info" })
end

-- The belt an item is riding, for pushing it off the side.
local function beltUnder(record: ItemRecord): PlacedMachine?
	local plotId, localPos = PlotService.plotAt(record.Body.Position)
	if not plotId or not localPos then
		return nil
	end
	local cx, cz = Grid.cellFromLocal(localPos)
	local machine = if cx and cz then MachineService.atHeight(plotId, cx, cz, localPos.Y) else nil
	if machine and machine.Info.IsConveyor then
		return machine
	end
	return nil
end

-- World position of a machine's hopper (its Intake attachment), else its pivot.
local function hopperPosition(machine: PlacedMachine): Vector3
	local base = machine.Model.PrimaryPart
	local intake = base and base:FindFirstChild("Intake")
	if base and intake and intake:IsA("Attachment") then
		return (base.CFrame * intake.CFrame).Position
	end
	return machine.Model:GetPivot().Position
end

-- A dropped item a full or busy hopper refused: the owner's Fx 'Full' (see the header).
-- Only items the player dropped or threw (HandDropped): machine pops, belt
-- spills and deck drops backing up are automation and stay quiet.
local function announceFull(machine: PlacedMachine, record: ItemRecord, reason: Reason, now: number)
	if not record.HandDropped then
		return
	end
	local last = fullSeen[record]
	fullSeen[record] = now
	if last and now - last <= FULL_SEEN_GAP then
		return -- still lying there since the last scan
	end
	if now - (fullPopAt[machine] or -math.huge) < FULL_POP_GAP then
		return
	end
	local owner = Players:GetPlayerByUserId(record.Owner)
	if owner then
		fullPopAt[machine] = now
		Net.fire("Fx", owner, "Full", hopperPosition(machine), reason)
	end
end

--[[
	What happens to an item a machine refused. 'Full' and 'Busy': the item
	waits; a dropped one tells its owner the hopper is full (announceFull;
	`now` defaults to os.clock(), the scan passes its own). 'Wrong', 'Mixed'
	and 'Foreign' (at most once per RejectCooldown per item): a dropped item
	bounces out of the hopper's front, a belt item is pushed off the belt's
	side, the owner sees a Reject effect and (not for 'Foreign') the
	machine's WrongHint.
]]
function IntakeService.react(machine: PlacedMachine, record: ItemRecord, reason: Reason, via: Via, belt: PlacedMachine?, now: number?)
	if record.State == "Consumed" then
		return
	end
	if reason == "Full" or reason == "Busy" then
		if via == "Drop" and record.State == "Loose" then
			announceFull(machine, record, reason, now or os.clock())
		end
		return
	end
	local clock = os.clock()
	local last = lastReject[record]
	if last and clock - last < GameConfig.RejectCooldown then
		return
	end
	lastReject[record] = clock
	if record.State == "Loose" then
		if via == "Drop" then
			local look = machine.Model:GetPivot().LookVector
			ItemService.eject(record, look * GameConfig.RejectPop.Out + Vector3.new(0, GameConfig.RejectPop.Up, 0))
		elseif via == "Belt" then
			local from = belt or beltUnder(record)
			local right = (if from then from.Model else machine.Model):GetPivot().RightVector
			ItemService.eject(record, right * GameConfig.BeltRejectPop.Side + Vector3.new(0, GameConfig.BeltRejectPop.Up, 0))
		end
	end
	local owner = Players:GetPlayerByUserId(record.Owner)
	if owner then
		Net.fire("Fx", owner, "Reject", record.Body.Position)
		local hint = machine.Info.WrongHint
		if reason ~= "Foreign" and hint then
			IntakeService.hint(owner, machine.Id, hint)
		end
	end
end

-- Loads carried items that the machine takes, top of the stack first.
local function loadFromHands(player: Player, machine: PlacedMachine)
	if machine.Removed then
		return
	end
	if machine.Owner ~= player then
		Net.fire("Notify", player, { Text = "That's not your machine.", Kind = "Deny" })
		return
	end
	local function fits(desc: Desc): boolean
		return (MachineService.canAccept(machine, desc, player.UserId, "Hand"))
	end
	-- from the backpack, one at a time while the machine takes them (its queue may fill)
	local loaded = 0
	for _ = 1, MAX_LOAD do
		local desc = CarryService.take(player, fits, 1)[1]
		if not desc then
			break
		end
		-- no yield between taking it out of the backpack and putting it in
		if MachineService.insertDesc(machine, desc, player.UserId, "Hand") then
			loaded += 1
		else
			CarryService.add(player, desc, 1, true)
			break
		end
	end
	if loaded > 0 then
		return
	end
	-- nothing went in: say why
	local stacks = CarryService.stacks(player)
	local reason: Reason? = nil
	for _, stack in stacks do
		local ok, why = MachineService.canAccept(machine, stack.Desc, player.UserId, "Hand")
		if not ok and (why == "Full" or why == "Busy") then
			reason = why :: Reason?
			break
		end
		reason = reason or why :: Reason?
	end
	local name = machine.Info.Name
	local text = if #stacks == 0
		then `Your backpack is empty: bring items here to put them in the {name}.`
		elseif reason == "Full" then `Your {name} is full.`
		elseif reason == "Busy" then `Your {name} is busy right now.`
		else machine.Info.WrongHint or `That doesn't go in the {name}.`
	Net.fire("Notify", player, { Text = text, Kind = "Deny" })
end

--[[
	The 'Put In' prompt (E / gamepad Y, PromptConfig "Main") on the machine's
	Prompt attachment, in slot `order`. The server never changes its Enabled
	after this: the client shows it only while you carry something
	(PromptController).
]]
function IntakeService.addLoadPrompt(machine: PlacedMachine, actionText: string, order: number): ProximityPrompt
	local base = machine.Model.PrimaryPart :: BasePart
	local attachment = base:FindFirstChild("Prompt") or base
	local prompt = PromptConfig.make({
		Name = "LoadPrompt",
		ActionText = actionText,
		ObjectText = machine.Info.Name,
		Distance = 10,
		Slot = order,
		Parent = attachment,
	})
	prompt.Triggered:Connect(function(player)
		loadFromHands(player, machine)
	end)
	return prompt
end

---------------------------------------------------------------- scan

local function scanOne(record: ItemRecord, now: number)
	local position = record.Body.Position
	-- 1. which plot (if any), then the town zones there: the first box holding the item wins
	local plotId, localPos = PlotService.plotAt(position)
	local nearby = staticNear(position, plotId)
	if nearby then
		for _, zone in nearby do
			if zone.Part.Parent and inBox(zone.CFrame, zone.Half, position) then
				if ItemService.isTrusted(record, now) then
					zone.Handler(record)
				end
				return
			end
		end
	end
	-- 2. on a plot: which cell
	if not plotId or not localPos then
		foreignSince[record] = nil
		return
	end
	if not ItemService.isTrusted(record, now) then
		return
	end
	local cx, cz = Grid.cellFromLocal(localPos)
	-- 3. hoppers, then belt ends: the first box holding the item wins
	local cells = plotZones[plotId]
	local list = if cells and cx and cz then cells[Grid.key(cx, cz)] else nil
	if list then
		for _, zone in list do
			if not zone.Machine.Removed and inBox(zone.CFrame, zone.Half, position) then
				local via: Via = if zone.Kind == "Hopper" then "Drop" else "Belt"
				local ok, reason = MachineService.insertRecord(zone.Machine, record, via)
				if not ok and reason then
					IntakeService.react(zone.Machine, record, reason :: Reason, via, zone.Belt, now)
				end
				return
			end
		end
	end
	-- 4. riding a belt (the one at the item's height: deck or ground)
	local cellMachine = if cx and cz then MachineService.atHeight(plotId, cx, cz, localPos.Y) else nil
	local handler = beltHandler
	if handler and cellMachine and cellMachine.Info.IsConveyor and not cellMachine.Removed then
		local ok, err = pcall(handler, cellMachine, record, cellMachine.Model:GetPivot():PointToObjectSpace(position), now)
		if not ok then
			warnThrottled("belt", "[IntakeService] belt handler failed: " .. tostring(err))
		end
		if record.State ~= "Loose" then
			return
		end
	end
	-- 5. lying on someone else's forge: it goes home after a while
	local plotOwner = PlotService.ownerOf(plotId)
	if plotOwner and plotOwner.UserId ~= record.Owner then
		local since = foreignSince[record]
		if not since then
			foreignSince[record] = now
		elseif now - since >= GameConfig.ForeignItemReturn then
			foreignSince[record] = nil
			ItemService.stash(record, "Your item landed on another forge")
		end
	else
		foreignSince[record] = nil
	end
end

local function scan()
	local now = os.clock()
	for _, record in ItemService.looseList() do
		if record.State == "Loose" then
			local ok, err = pcall(scanOne :: any, record, now)
			if not ok then
				warnThrottled("scan", "[IntakeService] scan failed: " .. tostring(err))
			end
		end
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/IntakeService.spec.luau).
IntakeService._test = {
	rebuild = rebuild,
	scanOne = scanOne,
	load = loadFromHands,
	reset = function()
		table.clear(plotZones)
		table.clear(staticZones)
		table.clear(hintTimes)
		table.clear(fullSeen)
		table.clear(fullPopAt)
		beltHandler = nil
		staticDirty = true
	end,
	-- what a zone part's CFrame / Size / AncestryChanged signal does
	invalidate = markStatic,
	-- the names of the town zones an item at `position` is tested against
	candidates = function(position: Vector3): { string }
		local plotId = PlotService.plotAt(position)
		local names = {}
		local list = staticNear(position, plotId)
		if list then
			for _, zone in list do
				if zone.Part.Parent then
					table.insert(names, zone.Name)
				end
			end
		end
		return names
	end,
	zonesAt = function(plotId: number, gx: number, gz: number): { Zone }
		local cells = plotZones[plotId]
		return cells and cells[Grid.key(gx, gz)] or {}
	end,
}

function IntakeService.init()
	MachineService.onLayoutChanged(function(_, plotId)
		rebuild(plotId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		hintTimes[player] = nil
	end)
end

function IntakeService.start()
	while true do
		task.wait(GameConfig.IntakeTick)
		scan()
	end
end

return IntakeService
