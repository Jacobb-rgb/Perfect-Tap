--[[
	ConveyorService: belts and the chute cells (step d "WP-Conveyor",
	step 3 "WP-Belts", docs/plans/STEP3_PLAN.md).

	Belts (MachineService.register for every MachineData entry with
	IsConveyor: the Conveyor, the Express Conveyor, the Belt Lift and the
	Slide)
	- A belt's Belt part is an anchored conveyor surface: its
	  AssemblyLinearVelocity = LookVector * beltSpeed(belt), set when it
	  spawns and after every move. beltSpeed = GameConfig.ConveyorSpeed *
	  the belt's SpeedMult (MachineData; the Express Conveyor runs at 2x).
	  The Belt Lift's and the Slide's Belt part is tilted (KitMachines.slope),
	  so the same LookVector carries items up the lift and down the slide.
	  Anchored-part velocity replicates, so there is no client code and
	  nothing runs per frame per part.
	- Every part of a belt is in the "Conveyors" collision group, which does
	  not collide with "Characters": players walk through belts, items ride.
	- Rails: on every layout change ConveyorLogic.openSides opens the side
	  rail where another belt feeds in from the side (no collision,
	  invisible, its painted face off), so corners and T-joins work.
	- Jams (IntakeService.setBeltHandler, 5 Hz, only for items riding a belt
	  that no hopper or belt end took): a server-simulated item slower than
	  ConveyorStuckSpeed for ConveyorStuckSeconds gets a nudge along the belt
	  (its Belt part's LookVector * beltSpeed + 1 up: up a Belt Lift's
	  slope, down a Slide's), which also wakes items that fell asleep;
	  ConveyorMaxNudges nudges within ConveyorNudgeWindow push it off the
	  belt's side (BeltRejectPop). An item that waits behind another item of
	  the same line (a queue in front of a full machine) is not
	  stuck: it just waits. Belts that face each other are not a line: those
	  items get nudged and pushed off, which clears the jam. The items ahead
	  come from a cell index of the loose items, built once per IntakeService
	  pass and only when an item is slow: a check looks at the 3 x 3 cells
	  around the belt (the machine under an item ahead is the one at its
	  height: MachineService.atHeight), never at every item on the server.

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
	- In the world every chute gets a colored floor plate on its cell and a
	  small plaque high on the plot's back wall, facing the grid (per plot,
	  built once in start(); PlotBuilder builds the wall). Every plaque's
	  bottom is at PlaqueBottom, on the wall's cap: over the rails of the
	  belt on the chute and the items riding it. Its top stays under the
	  ORE PEN sign and the gate posts' caps. PEN stands on the cap's ledge
	  behind its cell (a stud clear of the yard gate's post), TRAIN hangs on
	  the gate post beside its cell (that cell sits in the gate opening);
	  an arrow points from an off-cell plaque to its cell. A Source's
	  plaque says "TURN BELT" while the belt on it faces SinkRotation.
	  Build mode draws its own plates (PlacementController / GridOverlay).
	- A belt that runs off the grid's back edge (SinkRotation) just stops
	  its items at the plot's back wall (the FOUNDRY sink that took them
	  went with the Foundry, owner 2026-10-24). A save from before still
	  has its belt into the old FOUNDRY cell (OldFoundryCell): its items
	  would pile up loose at the wall until the loose-item cap stops the
	  factory, so the owner hears it once a session when the plot's layout
	  loads (OldFoundryText).

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
local PlotBuilder = require(script.Parent.Parent.World.PlotBuilder)

local ConveyorService = {}

type PlacedMachine = MachineService.PlacedMachine
type ItemRecord = ItemService.ItemRecord
type Desc = ItemService.Desc

-- Why a Source chute can't take an item right now.
export type SourceWait = "NoPlot" | "NoBelt" | "Yard" | "Jammed" | "TooMany"
-- Why spawnAtSource gave no item: a SourceWait (try again later) or "Bad"
-- (this desc can never become an item: keep it and move on).
export type SpawnFail = SourceWait | "Bad"

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
} :: { [string]: string }
ConveyorService.YardText = "Turn the belt away from the yard" -- toasts, the pen panel
ConveyorService.YardSign = "TURN BELT" -- the plaque's line meanwhile
-- A Source stops this many loose items below the machines' limit (the header):
-- two machines' worth of finished items (MachineData.MaxOutBuffer each).
ConveyorService.SourceReserve = 2 * MachineData.MaxOutBuffer

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

-- Studs per second a belt of this type moves items: GameConfig.ConveyorSpeed
-- times its MachineData SpeedMult (the Express Conveyor: 2). A broken
-- multiplier counts as 1.
function ConveyorService.speedOf(info: MachineData.Machine): number
	local mult = info.SpeedMult
	if type(mult) ~= "number" or mult ~= mult or mult <= 0 or mult == math.huge then
		mult = 1
	end
	return GameConfig.ConveyorSpeed * (mult :: number)
end

-- How fast this belt moves items (speedOf its type).
function ConveyorService.beltSpeed(machine: PlacedMachine): number
	return ConveyorService.speedOf(machine.Info)
end

-- The belt surface moves items toward the front, and players walk through every part.
local function applyBelt(machine: PlacedMachine)
	local belt = beltPart(machine)
	if belt then
		belt.AssemblyLinearVelocity = belt.CFrame.LookVector * ConveyorService.beltSpeed(machine)
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
	if ItemService.looseCount(ownerUserId, "Base") >= ConveyorService.sourceCeiling() then
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
	local record = spawnSafely(desc, ownerUserId, spot, pivot.LookVector * ConveyorService.beltSpeed(belt))
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

---------------------------------------------------------------- jams

-- Is an item on cell (cx, cz) of the belt's plot (just ahead, `y` world
-- studs high) part of the same line: on a belt that doesn't run against
-- this one, or at a machine? (The machine at the item's height: a deck
-- belt's line goes on over the deck, a lift's onto it.)
local function sameLine(belt: PlacedMachine, cx: number, cz: number, y: number, dir: Vector3): boolean
	local localY = y - PlotService.plotCFrame(belt.PlotId).Position.Y
	local machine = MachineService.atHeight(belt.PlotId, cx, cz, localY)
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
	-- the cells around the item (a Belt Lift is 3 cells long), else around the belt
	local ix, iz = Grid.cellFromLocal(PlotService.plotCFrame(belt.PlotId):PointToObjectSpace(position))
	local mx, mz = ix or belt.X, iz or belt.Z
	for cz = math.max(0, mz - 1), math.min(CELLS - 1, mz + 1) do
		for cx = math.max(0, mx - 1), math.min(CELLS - 1, mx + 1) do
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
						if sameLine(belt, cx, cz, looseY[i], dir) then
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
	-- along the belt surface: up a Belt Lift's slope, down a Slide's
	local surface = beltPart(belt)
	local along = if surface then surface.CFrame.LookVector else dir
	record.Body.AssemblyLinearVelocity = along * ConveyorService.beltSpeed(belt) + Vector3.new(0, 1, 0)
end

-- IntakeService calls this for every trusted loose item riding a belt that no
-- hopper or belt end took (localPos in the belt's space, front = -Z).
local function onBelt(belt: PlacedMachine, record: ItemRecord, localPos: Vector3, now: number)
	if record.State ~= "Loose" or belt.Removed then
		return
	end
	unjam(belt, record, now)
end

---------------------------------------------------------------- chutes in the world

local SIGN_BOARD = Color3.fromRGB(46, 40, 44)
local SIGN_TEXT = Color3.fromRGB(255, 244, 228)
local SIGN_WARN = Color3.fromRGB(255, 120, 90)
local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }

-- The plot's back wall (PlotBuilder padWalls; plot-local): its centre line,
-- the cap slab on the brick band (1.4 studs deep, its top at 2.25) with the
-- bullnose (radius 0.5) along the centre line, the yard gate's posts
-- (1.8-stud shafts up to 3.7, 2.1-stud caps at the opening's edges), the
-- pillars between a gate post and the corner (PlotBuilder.backPillars, one
-- half way at 12 cells) and at the corners (2.05-stud caps from 3.0). The
-- pillar line is the same |x| and z (a square grid).
local WALL_Z = PlotBuilder.WallLine
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
	Where a chute's plaque goes (plot-local): its centre x, the z of the face
	it stands or hangs on (the plaque is in front of it) and the x of its
	cell.
	  gate opening   (no wall there) on the nearer gate post's front, its
	                 inner edge at the opening
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
	local plate =
		Geo.block(model, plotCF * CFrame.new(cell.X, 0.06, cell.Z), Vector3.new(CELL - 0.5, 0.05, CELL - 0.5), chute.Color, nil, DECOR)
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

-- The old FOUNDRY chute's cell (an ordinary cell since the Foundry went) and what its
-- belt's owner hears once a session (the header).
ConveyorService.OldFoundryCell = { X = 9 + (CELLS - 12) / 2, Z = CELLS - 1 }
ConveyorService.OldFoundryText =
	"Your belt at the back wall ran into the Foundry, which is gone: its items now stop at the wall. Turn that belt or pick it up."
ConveyorService.NoticeDelay = 4 -- seconds after the layout loads (the HUD may still be starting)
local foundryNoticed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A belt into the old FOUNDRY cell on this plot: its owner hears it once a session.
local function noticeOldFoundryBelt(player: Player, plotId: number)
	if foundryNoticed[player] then
		return
	end
	local cell = ConveyorService.OldFoundryCell
	local machine = MachineService.atCell(plotId, cell.X, cell.Z)
	if not machine or not machine.Info.IsConveyor or machine.R ~= BaseLayout.SinkRotation or machine.L ~= 0 then
		return
	end
	foundryNoticed[player] = true
	task.delay(ConveyorService.NoticeDelay, function()
		if player.Parent then
			Net.fire("Notify", player, { Text = ConveyorService.OldFoundryText, Kind = "Info" })
		end
	end)
end

local function onLayout(player: Player, plotId: number)
	updateRails(MachineService.ofPlot(plotId))
	updateMarkers(plotId)
	noticeOldFoundryBelt(player, plotId)
end

-- Internals for the Lune tests only (tests/ConveyorService.spec.luau).
ConveyorService._test = {
	onBelt = onBelt,
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
		table.clear(foundryNoticed)
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

-- Every belt type (MachineData IsConveyor: Conveyor, ExpressConveyor, BeltLift, Slide), in List order.
function ConveyorService.beltIds(): { string }
	local list = {}
	for _, info in MachineData.List do
		if info.IsConveyor then
			table.insert(list, info.Id)
		end
	end
	return list
end

function ConveyorService.init()
	setupCollisionGroup()
	for _, id in ConveyorService.beltIds() do
		MachineService.register(id, {
			spawned = applyBelt,
			moved = applyBelt,
		})
	end
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
end

return ConveyorService
