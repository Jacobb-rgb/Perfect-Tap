--[[
	ConveyorService: belts and the chute cells (step d "WP-Conveyor",
	step 3 "WP-Belts", docs/plans/STEP3_PLAN.md).

	Belts (MachineService.register "Conveyor")
	- A belt's Belt part is an anchored conveyor surface: its
	  AssemblyLinearVelocity = LookVector * GameConfig.ConveyorSpeed, set when
	  it spawns and after every move. Anchored-part velocity replicates, so
	  there is no client code and nothing runs per frame per part.
	- Every part of a belt is in the "Conveyors" collision group, which does
	  not collide with "Characters": players walk through belts, items ride.
	- Rails: on every layout change ConveyorLogic.openSides opens the side
	  rail where another belt feeds in from the side (no collision,
	  invisible, its painted face off), so corners and T-joins work.
	- Jams (IntakeService.setBeltHandler, 5 Hz, only for items riding a belt
	  that no hopper or belt end took): a server-simulated item slower than
	  ConveyorStuckSpeed for ConveyorStuckSeconds gets a nudge along the belt
	  (dir * ConveyorSpeed + 1 up), which also wakes items that fell asleep;
	  ConveyorMaxNudges nudges within ConveyorNudgeWindow push it off the
	  belt's side (BeltRejectPop). An item that waits behind another item of
	  the same line (a queue in front of a full machine or a sink) is not
	  stuck: it just waits. Belts that face each other are not a line: those
	  items get nudged and pushed off, which clears the jam. The items ahead
	  come from a cell index of the loose items, built once per IntakeService
	  pass and only when an item is slow: a check looks at the 3 x 3 cells
	  around the belt, never at every item on the server.

	Chutes (BaseLayout.Chutes, three fixed cells on the back grid row)
	- Sources (PEN, TRAIN): sourceReady / spawnAtSource put an item onto the
	  belt standing on the chute cell, and only when that belt doesn't run
	  off the grid edge (BaseLayout.sourceFeeds), has room (none of the
	  owner's loose items on its cell, none spawned there in the last
	  SourceGap seconds) and the owner has fewer than sourceCeiling() loose
	  items. That ceiling sits SourceReserve items below the one machines
	  stop at (MaxLooseItemsPerPlayer - LooseHeadroom, MachineService.emit),
	  so a full line never takes the room its machines need for their
	  finished items: they keep emitting, the line keeps draining, and the
	  Sources wait ("TooMany") instead of locking it. A Source never drops
	  an item loose. PenService's send queue (both lanes: the pen's Send
	  and the train's Direct Unload) uses them. spawnable(desc) says whether
	  a saved desc can become an item at all (known kind, ore, grade,
	  recipe); spawnAtSource refuses any other with "Bad" (the caller keeps
	  it and moves on), and an error half way through never leaves a
	  half-made item behind.
	- Sinks (FOUNDRY): setSink(name, handler), see below. Another player's
	  item at a sink is refused like at a machine ("Foreign": pushed off the
	  belt, IntakeService sends it home after ForeignItemReturn).
	- In the world every chute gets a colored floor plate on its cell and a
	  small plaque high on the plot's back wall, facing the grid (per plot,
	  built once in start(); PlotBuilder stays untouched). Every plaque's
	  bottom is at PlaqueBottom, on the wall's cap: over the rails of the
	  belt on the chute and the items riding it. Its top stays under the
	  ORE PEN sign and the gate posts' caps. PEN stands on the cap's ledge
	  behind its cell (a stud clear of the yard gate's post), TRAIN hangs on
	  the gate post beside its cell (that cell sits in the gate opening),
	  FOUNDRY stands on the cap's ledge past the wall pillar beside its cell
	  (the Foundry's receiver hood, BaseLayout.FoundryIntake, covers the
	  wall behind the cell), in the gap between two podiums, so their price
	  tags stay in view; an arrow points from an off-cell plaque to its
	  cell. A Source's plaque says "TURN BELT" while the belt on it faces
	  SinkRotation. Build mode draws its own plates (PlacementController /
	  GridOverlay).

	THE SINK HOOK (for the package that owns a sink, e.g. FoundryService):
	  ConveyorService.setSink("Foundry", function(player, record): boolean ... end)
	- Called for a trusted loose item of the plot's OWNER only (player = the
	  owner, record.Owner == player.UserId) that reached the sink:
	    * the item is in the last FeedReachBelt studs of a belt on the chute
	      cell whose front faces BaseLayout.SinkRotation (off the grid edge,
	      into the back wall), or
	    * no belt stands on the chute cell and the item lies or rolls on that
	      cell, at most SinkScanUp studs over the pad (a look at the owner's
	      items every GameConfig.IntakeTick; ore flying over it is not in).
	  A belt on the cell that faces any other way just carries items across.
	- The handler must not yield. It returns true when it took the item: it
	  took it out of the world itself (ItemService.absorb) and stored it in
	  the same step. It returns false to leave the item where it is: it
	  waits there and is offered again every IntakeTick (the handler shows
	  its own throttled hint, e.g. "Ore Pen full"). An error counts as false.
	  A true is trusted: an item the handler says it took but left in the
	  world is destroyed right there (with a warning), so it can never be
	  offered, and stored, a second time.
	- What doesn't go into the sink's own store goes into the Ore Pen with
	  PenService.store, which refuses at the pen's capacity: then the handler
	  stores nothing and returns false (the item waits at the sink, with the
	  "Ore Pen full" hint). Never ItemService.storeDesc (it fills the pen
	  past its capacity and then sells) and NEVER PenService.arrived:
	  arrived() is for things a player brings to the pen (thrown in, Put In,
	  a train delivery) and lets the sorting billboard send them on again,
	  so an item stored that way would ride the PEN chute back to the sink
	  and loop forever. Machines (the Iron Box) store the same way.
	- setSink(name, nil) removes the handler. Without a handler items wait
	  at the end of the belt (the plot's back wall stops them) and items on
	  a belt-less cell stay where they are.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local WorldLayout = require(Shared.Config.WorldLayout)
local Geo = require(Shared.Builders.Geo)
local Grid = require(Shared.Machines.Grid)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local Net = require(Shared.Net)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)

local ConveyorService = {}

type PlacedMachine = MachineService.PlacedMachine
type ItemRecord = ItemService.ItemRecord
type Desc = ItemService.Desc

-- Why a Source chute can't take an item right now.
export type SourceWait = "NoPlot" | "NoBelt" | "Yard" | "Jammed" | "TooMany"
-- Why spawnAtSource gave no item: a SourceWait (try again later) or "Bad"
-- (this desc can never become an item: keep it and move on).
export type SpawnFail = SourceWait | "Bad"
-- What a Sink does with an owner's item (see the header): true = taken.
export type SinkHandler = (player: Player, record: ItemRecord) -> boolean

type Jam = { SlowSince: number?, Nudges: { number } }
-- Before / After: the arrow toward the chute cell around the line (off-cell plaques)
type Marker = { Line: TextLabel, Plate: Part, Edge: Part, Before: string, After: string }

ConveyorService.CollisionGroup = "Conveyors"
ConveyorService.SourceGap = 0.45 -- seconds between two items spawned on one Source belt
ConveyorService.SpawnUp = 1.7 -- studs above the pad where a Source item appears
ConveyorService.SpawnBack = 0.6 -- studs toward the belt's back end (it rides the whole belt)
-- the in-world plaques: the chute's Label big, one short word line under it
-- (the Hint is far too long for a plaque; build mode and toasts carry it)
ConveyorService.SignLines = {
	Pen = "ORE OUT",
	Train = "ORE OUT",
	Foundry = "BELT IN",
} :: { [string]: string }
ConveyorService.YardText = "Turn the belt away from the yard" -- toasts, the pen panel
ConveyorService.YardSign = "TURN BELT" -- the plaque's line meanwhile
-- A Source stops this many loose items below the machines' limit (the header):
-- two machines' worth of finished items (MachineData.MaxOutBuffer each).
ConveyorService.SourceReserve = 2 * MachineData.MaxOutBuffer
-- A belt-less Sink cell takes items at most this high over the pad.
ConveyorService.SinkScanUp = 3

local CELL = GameConfig.CellSize
local CELLS = GameConfig.PlotCells
-- a jam: items closer than this ahead (along the belt) are the line in front
local AHEAD_MIN, AHEAD_REACH = 0.2, 2.6
local AHEAD_WIDTH, AHEAD_HEIGHT = 1.8, 2.5
-- the Source room check: the belt's cell plus a little
local ROOM_HALF = Vector3.new(CELL / 2, 3, CELL / 2 + 0.4)
local ROOM_UP = 2 -- the box centre above the pad
local WARN_COOLDOWN = 10

local jams: { [ItemRecord]: Jam } = setmetatable({}, { __mode = "k" }) :: any
local sinks: { [string]: SinkHandler } = {}
local lastSpawn: { [string]: number } = {}
local markers: { [number]: { [string]: Marker } } = {}
-- the loose items of one IntakeService pass: where they were (flat arrays, so
-- a jam check walks numbers instead of making a Vector3 per item) and the
-- plot cell each one lies on (plotId -> Grid.key -> indices into looseCache)
local looseCache: { ItemRecord } = {}
local looseX: { number } = {}
local looseY: { number } = {}
local looseZ: { number } = {}
local looseCells: { [number]: { [number]: { number } } } = {}
local looseCacheAt = -math.huge
local lastWarn: { [string]: number } = {}

local function warnThrottled(key: string, message: string)
	local now = os.clock()
	if now - (lastWarn[key] or -math.huge) >= WARN_COOLDOWN then
		lastWarn[key] = now
		warn(message)
	end
end

local function chuteOf(name: string): BaseLayout.Chute?
	return BaseLayout.Chutes[name]
end

--[[
	The loose items of this scan, their positions and the plot cell each one
	lies on: built once per IntakeService pass (`now` is the pass's time),
	and only when an item on a belt is slow. Every later look in the same
	pass reads the few cells it needs.
]]
local function indexLoose(now: number)
	if now == looseCacheAt then
		return
	end
	looseCacheAt = now
	looseCache = ItemService.looseList()
	table.clear(looseX)
	table.clear(looseY)
	table.clear(looseZ)
	table.clear(looseCells)
	for i, record in looseCache do
		local p = record.Body.CFrame.Position
		looseX[i], looseY[i], looseZ[i] = p.X, p.Y, p.Z
		local plotId, localPos = PlotService.plotAt(p)
		local cx: number?, cz: number? = nil, nil
		if localPos then
			cx, cz = Grid.cellFromLocal(localPos)
		end
		if plotId and cx and cz then
			local cells = looseCells[plotId]
			if not cells then
				cells = {}
				looseCells[plotId] = cells
			end
			local key = Grid.key(cx, cz)
			local list = cells[key]
			if not list then
				list = {}
				cells[key] = list
			end
			table.insert(list, i)
		end
	end
end

---------------------------------------------------------------- belts

local function beltPart(machine: PlacedMachine): BasePart?
	local belt = machine.Model:FindFirstChild("Belt")
	return if belt and belt:IsA("BasePart") then belt else nil
end

-- The belt surface moves items toward the front, and players walk through every part.
local function applyBelt(machine: PlacedMachine)
	local belt = beltPart(machine)
	if belt then
		belt.AssemblyLinearVelocity = belt.CFrame.LookVector * GameConfig.ConveyorSpeed
	end
	for _, part in machine.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = ConveyorService.CollisionGroup
		end
	end
end

-- An open rail lets items in from the side: no collision, invisible, its painted face off.
local function setRail(model: Model, name: string, open: boolean)
	local rail = model:FindFirstChild(name)
	if not rail or not rail:IsA("BasePart") then
		return
	end
	if rail.CanCollide ~= not open then
		rail.CanCollide = not open
	end
	local transparency = if open then 1 else 0
	if rail.Transparency ~= transparency then
		rail.Transparency = transparency
	end
	for _, child in rail:GetChildren() do
		if child:IsA("SurfaceGui") and child.Enabled == open then
			child.Enabled = not open
		end
	end
end

-- Rails of every belt on a plot (corners and T-joins open their side).
local function updateRails(machines: { PlacedMachine })
	local entries = {}
	for _, machine in machines do
		if not machine.Removed then
			table.insert(entries, machine.Entry)
		end
	end
	local sides = ConveyorLogic.openSides(entries)
	for _, machine in machines do
		if machine.Info.IsConveyor and not machine.Removed then
			local open = sides[machine.Entry]
			setRail(machine.Model, "RailL", open ~= nil and open.Left)
			setRail(machine.Model, "RailR", open ~= nil and open.Right)
		end
	end
end

---------------------------------------------------------------- chutes: lookups

-- The belt standing on a chute cell of a plot (any direction), or nil.
function ConveyorService.beltOn(plotId: number, chute: string): PlacedMachine?
	local info = chuteOf(chute)
	if not info then
		return nil
	end
	local machine = MachineService.atCell(plotId, info.X, info.Z)
	if machine and machine.Info.IsConveyor and not machine.Removed then
		return machine
	end
	return nil
end

--[[
	The belt a Source chute feeds (standing on its cell and not running off
	the grid edge), or nil and why: "NoBelt" (nothing there) | "Yard" (it
	faces SinkRotation). Room isn't checked here (sourceReady does).
]]
local function sourceBelt(plotId: number, chute: string): (PlacedMachine?, SourceWait?)
	local belt = ConveyorService.beltOn(plotId, chute)
	if not belt then
		return nil, "NoBelt"
	end
	if not BaseLayout.sourceFeeds(belt.R) then
		return nil, "Yard"
	end
	return belt, nil
end
ConveyorService.sourceBelt = sourceBelt

local function inBox(cf: CFrame, half: Vector3, position: Vector3): boolean
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

--[[
	Is one of the owner's loose items lying on (or just over) this belt's
	cell? Only the owner's items (at most MaxLooseItemsPerPlayer, never a
	walk over every item on the server): everything a Source spawns is
	theirs, and another player's item on the plot goes home by itself
	(IntakeService, ForeignItemReturn).
]]
local function beltBusy(belt: PlacedMachine, ownerUserId: number): boolean
	local box = belt.Model:GetPivot() * CFrame.new(0, ROOM_UP, 0)
	for _, record in ItemService.ownedBy(ownerUserId) do
		if record.State == "Loose" and inBox(box, ROOM_HALF, record.Body.CFrame.Position) then
			return true
		end
	end
	return false
end

-- How many loose items the owner may have before a Source waits ("TooMany"):
-- SourceReserve below the machines' limit (MachineService.emit), see the header.
function ConveyorService.sourceCeiling(): number
	return GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom - ConveyorService.SourceReserve
end

--[[
	Can the Source chute `chute` of plot `plotId` take an item for
	`ownerUserId` right now? (true) or (false, why): "NoBelt" | "Yard" |
	"Jammed" (an item still lies on its cell, or one was just spawned) |
	"TooMany" (the owner has sourceCeiling() loose items: the room above
	that is for their machines' finished items).
]]
local function sourceReady(plotId: number, chute: string, ownerUserId: number): (boolean, SourceWait?)
	local info = chuteOf(chute)
	if not info or info.Kind ~= "Source" then
		return false, "NoBelt"
	end
	local belt: PlacedMachine?, why: SourceWait? = sourceBelt(plotId, chute)
	if not belt then
		return false, why
	end
	local last = lastSpawn[`{plotId}/{chute}`]
	if last and os.clock() - last < ConveyorService.SourceGap then
		return false, "Jammed"
	end
	if ItemService.looseCount(ownerUserId) >= ConveyorService.sourceCeiling() then
		return false, "TooMany"
	end
	if beltBusy(belt, ownerUserId) then
		return false, "Jammed"
	end
	return true, nil
end
ConveyorService.sourceReady = sourceReady

--[[
	Can this saved desc become an item at all? A table with a known kind and
	ore, and a grade / recipe that is nil or a known one (exactly what
	ItemService.spawnDesc needs, so it never refuses or errors half way on
	our data). Saves can hold others (an ore that was renamed, a broken
	entry): those stay where they are and are never sent.
]]
function ConveyorService.spawnable(desc: any): boolean
	if type(desc) ~= "table" then
		return false
	end
	local kind, ore, grade, recipe = desc.K, desc.O, desc.G, desc.R
	if type(kind) ~= "string" or type(ore) ~= "string" or not ItemData.Kinds[kind] or not OreData.exists(ore) then
		return false
	end
	if grade ~= nil and (type(grade) ~= "string" or not ItemData.GradeById[grade]) then
		return false
	end
	if recipe ~= nil and (type(recipe) ~= "string" or not ItemData.RecipeById[recipe]) then
		return false
	end
	return true
end

--[[
	ItemService.spawnDesc in a protected call. If it errors half way, the
	item it may already have made (indexed, maybe not in the world yet) is
	unmade again, so the caller can trust the answer: a record = the item
	exists once, nil = nothing exists (and the caller keeps its desc).
]]
local function spawnSafely(desc: Desc, ownerUserId: number, spot: CFrame, velocity: Vector3): ItemRecord?
	local before = os.clock()
	local ok, result = pcall(ItemService.spawnDesc, desc, ownerUserId, spot, velocity, true)
	if ok then
		return result
	end
	warnThrottled("spawn", `[ConveyorService] spawning {desc.K} {desc.O} failed: {result}`)
	for _, record in ItemService.ownedBy(ownerUserId) do
		if record.CreatedAt >= before and record.State == "Loose" and record.Kind == desc.K and record.OreId == desc.O then
			ItemService.destroy(record)
		end
	end
	return nil
end

--[[
	Spawns `desc` (owned by ownerUserId) onto the belt of a Source chute,
	riding toward the belt's front with server physics. (nil, why) when it
	can't, and then nothing happened: a SourceWait (sourceReady said no: try
	again later) or "Bad" (spawnable says no, or spawning failed: this desc
	won't spawn, move on). The caller takes the item out of its place
	first and puts it back on nil, all without a yield. `checked`: the
	caller got true from sourceReady for this chute and owner in the same
	step, with no yield and no spawn since (its room isn't looked at again).
]]
function ConveyorService.spawnAtSource(
	plotId: number,
	chute: string,
	desc: Desc,
	ownerUserId: number,
	checked: boolean?
): (ItemRecord?, SpawnFail?)
	if not ConveyorService.spawnable(desc) then
		return nil, "Bad"
	end
	local info = chuteOf(chute)
	if not info or info.Kind ~= "Source" then
		return nil, "NoBelt"
	end
	if not checked then
		local ok: boolean, why: SourceWait? = sourceReady(plotId, chute, ownerUserId)
		if not ok then
			return nil, why
		end
	end
	local belt: PlacedMachine?, why: SourceWait? = sourceBelt(plotId, chute)
	if not belt then
		return nil, why
	end
	local pivot = belt.Model:GetPivot()
	local spot = pivot * CFrame.new(0, ConveyorService.SpawnUp, ConveyorService.SpawnBack)
	local record = spawnSafely(desc, ownerUserId, spot, pivot.LookVector * GameConfig.ConveyorSpeed)
	if not record then
		return nil, "Bad"
	end
	lastSpawn[`{plotId}/{chute}`] = os.clock()
	return record, nil
end

-- One line for the player: why a Source chute waits.
function ConveyorService.waitText(chute: string, why: SourceWait?): string?
	local info = chuteOf(chute)
	local label = if info then info.Label else string.upper(chute)
	if why == "NoBelt" then
		return `Put a conveyor on your {label} chute`
	elseif why == "Yard" then
		return `{label} chute: {string.lower(ConveyorService.YardText)}`
	elseif why == "Jammed" then
		return `The belt at your {label} chute is full`
	elseif why == "TooMany" then
		return "Too many loose items: pick some up"
	elseif why == "NoPlot" then
		return "You don't have a plot yet"
	end
	return nil
end

---------------------------------------------------------------- chutes: sinks

-- The package that owns a Sink chute registers what it does with items (header).
function ConveyorService.setSink(name: string, handler: SinkHandler?)
	local info = chuteOf(name)
	assert(info and info.Kind == "Sink", "Not a sink chute: " .. tostring(name))
	if handler and sinks[name] then
		warn("[ConveyorService] sink handler replaced: " .. name)
	end
	if handler then
		sinks[name] = handler
	else
		sinks[name] = nil
	end
end

-- Offers an item to a sink. Returns true when the sink took it.
local function offer(name: string, plotId: number, record: ItemRecord, belt: PlacedMachine?): boolean
	local owner = PlotService.ownerOf(plotId)
	if not owner or owner.UserId ~= record.Owner then
		if belt then
			-- another player's item: pushed off like at a machine, it goes home
			IntakeService.react(belt, record, "Foreign", "Belt", belt)
		end
		return false
	end
	local handler = sinks[name]
	if not handler then
		return false
	end
	local ok, taken = pcall(handler, owner, record)
	if not ok then
		warnThrottled("sink" .. name, `[ConveyorService] {name} sink failed: {taken}`)
		return false
	end
	if taken ~= true then
		return false
	end
	if record.State == "Loose" then
		-- the handler says it took (and stored) the item but left it in the
		-- world: trust the answer and take it out, or it would be offered,
		-- and stored, again every IntakeTick
		warnThrottled("sinkLoose" .. name, `[ConveyorService] {name} sink took an item but left it in the world (absorb it)`)
		ItemService.destroy(record)
	end
	return true
end

-- The Sink chute a belt delivers into (on the sink cell, facing SinkRotation), if any.
local function sinkOfBelt(belt: PlacedMachine): string?
	local name = BaseLayout.chuteAt(belt.X, belt.Z)
	local info = name and chuteOf(name)
	if name and info and info.Kind == "Sink" and belt.R == BaseLayout.SinkRotation then
		return name
	end
	return nil
end

--[[
	Items lying on a sink cell that has no belt (every IntakeTick). Only the
	owner's items can go in, so only theirs are looked at (at most
	MaxLooseItemsPerPlayer per owned plot, never every item on the server),
	and only on the pad: at most SinkScanUp studs over it (an item flying
	over the cell isn't on it).
]]
local function scanSinks(now: number)
	if next(sinks) == nil then
		return
	end
	for _, plot in WorldLayout.Plots do
		local owner = PlotService.ownerOf(plot.Id)
		if not owner then
			continue
		end
		local open: { string }? = nil
		for name in sinks do
			local info = chuteOf(name)
			if info and not MachineService.atCell(plot.Id, info.X, info.Z) then
				local list = open or {}
				open = list
				table.insert(list, name)
			end
		end
		if not open then
			continue
		end
		local plotCF = PlotService.plotCFrame(plot.Id)
		for _, record in ItemService.ownedBy(owner.UserId) do
			if record.State ~= "Loose" then
				continue
			end
			local localPos = plotCF:PointToObjectSpace(record.Body.CFrame.Position)
			if localPos.Y < -1 or localPos.Y > ConveyorService.SinkScanUp then
				continue
			end
			local cx, cz = Grid.cellFromLocal(localPos)
			if not cx or not cz or not ItemService.isTrusted(record, now) then
				continue
			end
			for _, name in open do
				local info = chuteOf(name)
				if info and cx == info.X and cz == info.Z then
					offer(name, plot.Id, record, nil)
					break
				end
			end
		end
	end
end

---------------------------------------------------------------- jams

-- Is an item on cell (cx, cz) of the belt's plot (just ahead) part of the
-- same line: on a belt that doesn't run against this one, or at a machine?
local function sameLine(belt: PlacedMachine, cx: number, cz: number, dir: Vector3): boolean
	local machine = MachineService.atCell(belt.PlotId, cx, cz)
	if not machine or machine.Removed then
		return false
	end
	if not machine.Info.IsConveyor then
		return true
	end
	return machine.Model:GetPivot().LookVector:Dot(dir) > -0.5
end

--[[
	Does another item of the same line wait right in front of this one? Only
	the loose items on the 3 x 3 cells around the belt can be that close
	(AHEAD_REACH and AHEAD_WIDTH are under a cell), from this pass's index.
]]
local function queued(belt: PlacedMachine, record: ItemRecord, dir: Vector3, now: number): boolean
	indexLoose(now)
	local cells = looseCells[belt.PlotId]
	if not cells then
		return false
	end
	local position = record.Body.CFrame.Position
	local x, y, z = position.X, position.Y, position.Z
	local dx, dz = dir.X, dir.Z
	for cz = math.max(0, belt.Z - 1), math.min(CELLS - 1, belt.Z + 1) do
		for cx = math.max(0, belt.X - 1), math.min(CELLS - 1, belt.X + 1) do
			local list = cells[Grid.key(cx, cz)]
			if not list then
				continue
			end
			for _, i in list do
				local ox, oz = looseX[i] - x, looseZ[i] - z
				local along = ox * dx + oz * dz
				if along > AHEAD_MIN and along <= AHEAD_REACH and math.abs(looseY[i] - y) <= AHEAD_HEIGHT then
					local sx, sz = ox - dx * along, oz - dz * along
					local other = looseCache[i]
					if sx * sx + sz * sz <= AHEAD_WIDTH * AHEAD_WIDTH and other ~= record and other.State == "Loose" then
						if sameLine(belt, cx, cz, dir) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function unjam(belt: PlacedMachine, record: ItemRecord, now: number)
	local jam = jams[record]
	if record.ClientOwnedUntil ~= nil then
		-- the owner's client moves it right now: not ours to judge
		if jam then
			jam.SlowSince = nil
		end
		return
	end
	local speed = record.Body.AssemblyLinearVelocity.Magnitude
	if speed >= GameConfig.ConveyorStuckSpeed then
		if jam then
			jam.SlowSince = nil
		end
		return
	end
	local pivot = belt.Model:GetPivot()
	local dir = pivot.LookVector
	if queued(belt, record, dir, now) then
		if jam then
			jam.SlowSince = nil
		end
		return
	end
	if not jam then
		jam = { SlowSince = now, Nudges = {} }
		jams[record] = jam
		return
	end
	local since = jam.SlowSince
	if not since then
		jam.SlowSince = now
		return
	end
	if now - since < GameConfig.ConveyorStuckSeconds then
		return
	end
	jam.SlowSince = now
	local nudges = jam.Nudges
	for i = #nudges, 1, -1 do
		if now - nudges[i] > GameConfig.ConveyorNudgeWindow then
			table.remove(nudges, i)
		end
	end
	table.insert(nudges, now)
	if #nudges >= GameConfig.ConveyorMaxNudges then
		-- still stuck after all the nudges: off the side of the belt
		jams[record] = nil
		local pop = GameConfig.BeltRejectPop
		ItemService.eject(record, pivot.RightVector * pop.Side + Vector3.new(0, pop.Up, 0))
		local owner = Players:GetPlayerByUserId(record.Owner)
		if owner then
			Net.fire("Fx", owner, "Reject", record.Body.CFrame.Position)
		end
		return
	end
	record.Body.AssemblyLinearVelocity = dir * GameConfig.ConveyorSpeed + Vector3.new(0, 1, 0)
end

-- IntakeService calls this for every trusted loose item riding a belt that no
-- hopper or belt end took (localPos in the belt's space, front = -Z).
local function onBelt(belt: PlacedMachine, record: ItemRecord, localPos: Vector3, now: number)
	if record.State ~= "Loose" or belt.Removed then
		return
	end
	local sink = sinkOfBelt(belt)
	if sink and localPos.Z <= -CELL / 2 + GameConfig.FeedReachBelt then
		-- at the end of a sink belt: it goes in, or waits there (never nudged off)
		jams[record] = nil
		offer(sink, belt.PlotId, record, belt)
		return
	end
	unjam(belt, record, now)
end

---------------------------------------------------------------- chutes in the world

local SIGN_BOARD = Color3.fromRGB(46, 40, 44)
local SIGN_TEXT = Color3.fromRGB(255, 244, 228)
local SIGN_WARN = Color3.fromRGB(255, 120, 90)
local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }

-- The plot's back wall (PlotBuilder padWalls, which this package must not
-- change; plot-local): its centre line, the cap slab on the brick band
-- (1.4 studs deep, its top at 2.25) with the bullnose (radius 0.5) along the
-- centre line, the yard gate's posts (1.8-stud shafts up to 3.7, 2.1-stud
-- caps at the opening's edges), the pillars half way from a gate post to the
-- corner and at the corners (2.05-stud caps from 3.0).
local WALL_Z = GameConfig.PlotCells * CELL / 2 + 1 -- PlotBuilder.WallLine
local PILLAR_LINE = WALL_Z + 0.1
local CAP_TOP, CAP_FRONT = 2.25, WALL_Z - 0.7
local POST_CAP, POST_W = 2.1, 1.8
local PILLAR_CAP = 2.05
local POST_CLEAR = 1 -- a gate post stands out in front of the wall: keep this far from it
local EDGE = 0.08 -- the colored frame around the board (and its depth)
local BOARD_DEPTH = 0.06
local STRIP_DEPTH = 0.02 -- the text strips on the board (one label each)
local PLAQUE_DEPTH = EDGE + BOARD_DEPTH + STRIP_DEPTH
-- a plaque's back on the cap's ledge (in front of the bullnose, its front
-- flush with the cap) and on a gate post's front face
local CAP_FACE = CAP_FRONT + PLAQUE_DEPTH
local POST_FACE = PILLAR_LINE - POST_W / 2
-- a plaque: its frame stands on the cap (over the rails of a belt on the
-- chute, 1.1, and the items riding it), its top under the gate posts' caps
-- (3.7) and the ORE PEN sign (3.75)
ConveyorService.PlaqueSize = Vector2.new(2.6, 1.25)
ConveyorService.PlaqueBottom = CAP_TOP + EDGE -- the board's bottom

--[[
	The middle of the gap between two neighbouring podiums (BaseLayout.Podiums,
	plot-local x) nearest to `from` on its `side` (or at it), nil when there is
	none: a plaque there leaves their price tags in view from the grid.
]]
local function podiumGap(from: number, side: number): number?
	local spans: { { number } } = {}
	for _, rect in BaseLayout.Podiums do
		table.insert(spans, { rect.Center.X - rect.Size.X / 2, rect.Center.X + rect.Size.X / 2 })
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local best: number? = nil
	for i = 1, #spans - 1 do
		local mid = (spans[i][2] + spans[i + 1][1]) / 2
		if (mid - from) * side >= 0 and (best == nil or math.abs(mid - from) < math.abs((best :: number) - from)) then
			best = mid
		end
	end
	return best
end

--[[
	Where a chute's plaque goes (plot-local): its centre x, the z of the face
	it stands or hangs on (the plaque is in front of it) and the x of its
	cell.
	  gate opening   (no wall there) on the nearer gate post's front, its
	                 inner edge at the opening
	  receiver hood  (BaseLayout.FoundryIntake.Zone covers the wall behind
	                 the cell) on the cap's ledge past the hood and the wall
	                 pillar beside it, in the nearest gap between two podiums
	  otherwise      on the cap's ledge right behind the cell, POST_CLEAR
	                 from the yard gate's post
	A ledge spot never reaches the corner pillar.
]]
function ConveyorService.plaqueSpot(name: string): (number, number, number)
	local cell = BaseLayout.chuteLocal(name)
	local half = ConveyorService.PlaqueSize.X / 2 + EDGE -- with its frame
	local gate = BaseLayout.YardGate
	local side = if cell.X >= gate.CenterX then 1 else -1
	local offset = math.abs(cell.X - gate.CenterX)
	if offset < gate.Width / 2 then
		return gate.CenterX + side * (gate.Width / 2 + 0.1 + half), POST_FACE, cell.X
	end
	-- the ledge ends at the corner pillar's cap
	local farthest = PILLAR_LINE - PILLAR_CAP / 2 - 0.1 - half
	local zone = BaseLayout.FoundryIntake.Zone
	local zoneMin, zoneMax = zone.Center.X - zone.Size.X / 2, zone.Center.X + zone.Size.X / 2
	if cell.X + half > zoneMin and cell.X - half < zoneMax then
		local postX = math.abs(gate.CenterX + side * (gate.Width / 2 + POST_CAP / 2))
		local pillarX = side * (postX + PILLAR_LINE) / 2
		local from = if side > 0
			then math.max(zoneMax, pillarX + PILLAR_CAP / 2) + 0.1 + half
			else math.min(zoneMin, pillarX - PILLAR_CAP / 2) - 0.1 - half
		local gap = podiumGap(from, side)
		local x = if gap and math.abs(gap) <= farthest then gap else from
		return x, CAP_FACE, cell.X
	end
	local clear = gate.Width / 2 + POST_CAP + POST_CLEAR + half
	local x = gate.CenterX + side * math.max(offset, clear)
	return side * math.min(math.abs(x), farthest), CAP_FACE, cell.X
end

-- One text strip on the plaque's board: a thin part with one SurfaceGui
-- and one label (big, short words, readable from the grid).
local function strip(model: Model, cf: CFrame, size: Vector3, name: string, text: string, color: Color3, font: Enum.Font): TextLabel
	local part = Geo.block(model, cf, size, SIGN_BOARD, nil, DECOR)
	part.Name = name
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.3
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(font)
	l.Parent = gui
	return l
end

--[[
	One chute's floor plate and plaque on a plot (plot-local layout):
	  plate   the cell in the chute's Color, a thin slab on the pad (a belt
	          on the cell hides it; it shows where the chute is while empty)
	  plaque  a dark board in a frame of the chute's Color, upright on the
	          back wall facing the grid (plaqueSpot), its frame on the
	          cap's height: the Label big, a one-word line under it
	          (SignLines, with an arrow toward the cell when the plaque is
	          beside it)
]]
local function buildMarker(folder: Instance, plotCF: CFrame, name: string, chute: BaseLayout.Chute): Marker
	local model = Instance.new("Model")
	model.Name = name
	local cell = BaseLayout.chuteLocal(name)
	-- top at 0.085: over the lawn stripes (<= 0.048), under build mode's plates (GridOverlay, >= 0.1)
	local plate = Geo.block(model, plotCF * CFrame.new(cell.X, 0.06, cell.Z), Vector3.new(CELL - 0.5, 0.05, CELL - 0.5), chute.Color, nil, DECOR)
	plate.Name = "Plate"
	plate.Transparency = 0.15
	-- the plaque: front (-Z model space) toward the grid
	local x, face, cellX = ConveyorService.plaqueSpot(name)
	local size = ConveyorService.PlaqueSize
	local y = ConveyorService.PlaqueBottom + size.Y / 2
	local edge = Geo.block(
		model,
		plotCF * CFrame.new(x, y, face - EDGE / 2),
		Vector3.new(size.X + EDGE * 2, size.Y + EDGE * 2, EDGE),
		chute.Color,
		nil,
		DECOR
	)
	edge.Name = "Edge"
	local boardZ = face - EDGE - BOARD_DEPTH / 2
	local board = Geo.block(model, plotCF * CFrame.new(x, y, boardZ), Vector3.new(size.X, size.Y, BOARD_DEPTH), SIGN_BOARD, nil, DECOR)
	board.Name = "Board"
	local stripZ = face - EDGE - BOARD_DEPTH - STRIP_DEPTH / 2
	local w = size.X * 0.9
	strip(
		model,
		plotCF * CFrame.new(x, y + size.Y * 0.17, stripZ),
		Vector3.new(w, size.Y * 0.56, STRIP_DEPTH),
		"Title",
		chute.Label,
		chute.Color,
		Enum.Font.LuckiestGuy
	)
	-- from the grid the plot's +X is on the left: an arrow from the plaque toward its cell
	local before = if cellX > x + 0.5 then "< " else ""
	local after = if cellX < x - 0.5 then " >" else ""
	local line = strip(
		model,
		plotCF * CFrame.new(x, y - size.Y * 0.3, stripZ),
		Vector3.new(w, size.Y * 0.3, STRIP_DEPTH),
		"Line",
		before .. (ConveyorService.SignLines[name] or chute.Label) .. after,
		SIGN_TEXT,
		Enum.Font.FredokaOne
	)
	model.Parent = folder
	return { Line = line, Plate = plate, Edge = edge, Before = before, After = after }
end

local function buildMarkers(plotId: number)
	local plot = PlotService.model(plotId)
	if not plot or markers[plotId] then
		return
	end
	local old = plot:FindFirstChild("Chutes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = "Chutes"
	local plotCF = PlotService.plotCFrame(plotId)
	local list: { [string]: Marker } = {}
	for _, name in BaseLayout.ChuteNames do
		list[name] = buildMarker(folder, plotCF, name, BaseLayout.Chutes[name])
	end
	folder.Parent = plot
	markers[plotId] = list
end

-- A Source's plaque warns while the belt on it runs off the grid edge.
local function updateMarkers(plotId: number)
	local list = markers[plotId]
	if not list then
		return
	end
	for name, marker in list do
		local info = BaseLayout.Chutes[name]
		local _, why: SourceWait? = sourceBelt(plotId, name)
		local warnYard = info.Kind == "Source" and why == "Yard"
		local word = if warnYard then ConveyorService.YardSign else ConveyorService.SignLines[name] or info.Label
		local text = marker.Before .. word .. marker.After
		if marker.Line.Text ~= text then
			marker.Line.Text = text
			marker.Line.TextColor3 = if warnYard then SIGN_WARN else SIGN_TEXT
		end
	end
end

---------------------------------------------------------------- lifecycle

local function setupCollisionGroup()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ConveyorService.CollisionGroup)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ItemService.CharacterGroup)
	end)
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(ConveyorService.CollisionGroup, ItemService.CharacterGroup, false)
	end)
	if not ok then
		warn("[ConveyorService] collision group: " .. tostring(err))
	end
end

local function onLayout(_: Player, plotId: number)
	updateRails(MachineService.ofPlot(plotId))
	updateMarkers(plotId)
end

-- Internals for the Lune tests only (tests/ConveyorService.spec.luau).
ConveyorService._test = {
	onBelt = onBelt,
	scanSinks = scanSinks,
	onLayout = onLayout,
	buildMarkers = buildMarkers,
	markers = function(plotId: number): { [string]: Marker }?
		return markers[plotId]
	end,
	jam = function(record: ItemRecord): Jam?
		return jams[record]
	end,
	behaviour = {
		spawned = applyBelt,
		moved = applyBelt,
	},
	reset = function()
		table.clear(sinks)
		table.clear(lastSpawn)
		table.clear(markers)
		table.clear(jams)
		table.clear(looseCache)
		table.clear(looseX)
		table.clear(looseY)
		table.clear(looseZ)
		table.clear(looseCells)
		looseCacheAt = -math.huge
	end,
}

function ConveyorService.init()
	setupCollisionGroup()
	MachineService.register("Conveyor", {
		spawned = applyBelt,
		moved = applyBelt,
	})
	MachineService.onLayoutChanged(onLayout)
	IntakeService.setBeltHandler(onBelt)
end

function ConveyorService.start()
	for _, plot in WorldLayout.Plots do
		local ok, err = pcall(function()
			buildMarkers(plot.Id)
		end)
		if not ok then
			warn(`[ConveyorService] chute signs on plot {plot.Id}: {err}`)
		end
		updateMarkers(plot.Id)
	end
	while true do
		task.wait(GameConfig.IntakeTick)
		local ok, err = pcall(function()
			scanSinks(os.clock())
		end)
		if not ok then
			warnThrottled("scan", "[ConveyorService] sink scan failed: " .. tostring(err))
		end
	end
end

return ConveyorService
