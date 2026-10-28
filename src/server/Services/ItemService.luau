--[[
	ItemService: every physical item (ore chunks, ingots, gear) in the world.

	- Items are Models in Workspace.Items with a single colliding Body part.
	- The server keeps the truth in `records`; attributes on the model are
	  only for clients (they can't change them).
	- Ownership: every item belongs to one player (Owner = UserId). Only the
	  owner can pick it up, and selling always pays the owner, so stealing
	  or griefing other players' items gains nothing.
	- Physics: the owner's client simulates an item for a few seconds after a
	  drop/throw (smooth), then the server takes it back. Only owners within
	  GameConfig.ClientPhysicsRange get it (a far-away client may not have
	  the part streamed in). Items are in the "Items" collision group, which
	  does not collide with characters (no flinging other players with items).
	- Trust: while a client simulates an item it could move it anywhere, so
	  machines only take an item when isTrusted() says its travel since the
	  drop is plausible. Items that end up far from where they were dropped
	  snap back when the server takes physics back.
	- Descriptors: an item outside the world (storage, machine queues) is a
	  Desc { K = kind, O = oreId, G = grade?, R = recipe? }. absorb() turns an
	  item into a Desc, spawnDesc() turns a Desc back into an item.
	- Ids: a short number per server session (record.Id, getById), only used
	  as a key and a look seed: never saved, never sent as an attribute.
	- Attributes (all clients read): Kind, Owner, State, and for anything but
	  dirty ore OreId, Grade?, Recipe?, Value; CarriedBy while carried.
	- Loose items per player, counted apart by where they lie (looseCount
	  "Base" / "Away"): machines, chutes and pen takes stop a little below
	  GameConfig.MaxLooseItemsPerPlayer items on and around bases, and
	  MiningService doesn't let a rock give ore while that many lie away from
	  bases (atLooseCap). A busy factory never stops your mining and ore left
	  in the mine never stalls your factory. One last-resort rescue: while a
	  player is at the mine's cap, ore they left far behind (StaleAway*) or
	  that lies stuck out of reach (StuckSeconds) goes into their pen, oldest
	  first, with a toast, so a wedged chunk can't block mining for ever.
	  Over everything, GameConfig.MaxLooseItemsTotal: hand drops, throws and
	  Pen takes stop at that many loose items (atTotalCap). Resting items
	  sleep in Roblox physics.
	- Items that fall out of the world are put back next to their owner.
	- Leaving players: loose and carried items go into the Ore Pen.
	- A dropper's Drop (DropperConfig) is never stored (storeDesc: "Lost",
	  so leaving, rescues and returns from other plots just remove it) and
	  never pulled by the magnet (CarryService never picks it up either).
	- The Ore Pen (data.Storage) holds penCapacity items. Only RESCUE moves
	  (storeDesc: leaving, an item lost by the engine, Placement repair, an
	  item returned from someone else's plot) may overfill it, up to the
	  DataStore cap GameConfig.MaxStoredItems; Tobin's price is paid beyond
	  that. While a pen is over its capacity it takes nothing new from the
	  player or their automation (PenService.refusal "PenOver").
	- Dirty ore hides its rarity (Security #6): a Raw item has no OreId and
	  no Value attribute and is named just "Raw" (the server keeps the ore in
	  record.OreId; the cleaning, sale and pen code read it there).
	- Light belt items (docs/SERVER_PERF_AUDIT.md #3/#4): items machines and
	  chutes spawn (serverOwned) wear ItemBuilder.buildLight (<= 3 parts);
	  dress() switches an item to the full look (CarryService does on every
	  pickup). absorb() of a light loose item (a machine taking it off a belt)
	  PARKS its model hidden where it is (anchored, invisible, not queryable,
	  no "Item" tag) for Pool.Keep seconds; the next serverOwned spawn of the
	  same owner within Pool.Reach (the machine's output) re-dresses that
	  model instead of building a new one: no new model, part or weld
	  replicates when the look stays, only the decor when it changes.
	- Queued items can sleep (sleep / wake / wakeNear: anchored in place while
	  they wait at a full machine); taking an item wakes the owner's sleepers
	  around it, and none sleeps longer than SleepMax.
	- Consumed records (Security #11) can't be mounted, released or set to
	  another state; when a CARRIED record is consumed (the engine destroyed
	  it), CarryService hears it (onCarriedConsumed) and drops it from the list.
	- Hand-back (Security #8): when the server takes an item's physics back
	  from the owner's client it keeps at most HandBackSpeed / HandBackSpin,
	  and an item further than travelLimit or higher above its release point
	  than riseLimit snaps back (isTrusted checks the rise too).
	- Fast throws (Grip Gloves): CarryService.onThrow raises the item's
	  plausible speed for that one release (allowSpeed), so isTrusted and
	  the MaxItemTravel snap-back scale with it instead of refusing a legal
	  long throw. Any other release goes back to GameConfig.MaxItemSpeed.
	- Items whose position isn't a finite number are put back next to their
	  owner (or into the pen) by the maintenance pass.
	- The Ore Magnet (gear, ItemService.Magnet): every 0.25 s, for each
	  player whose Bonuses.magnetRadius is above 0, their OWN loose items
	  within that radius fly to them (never another player's) and INTO
	  THEIR HANDS: an item that reaches your feet (StopDistance), or lands
	  there (within StartDistance), is picked up (setMagnetHands:
	  CarryService's room and a quiet pickup). Only as many items as your
	  hands still take are pulled at once, so with full hands nothing
	  moves and nothing herds after you.
	  Server physics: the item gets a LinearVelocity in the ground plane
	  (gravity and walls still act, so nothing passes through a wall), and
	  a low ray (RayHeight above the owner's feet, to the item) must be
	  clear before (and every CheckEvery seconds while) it is pulled, so
	  curbs and railings count; a blocked item isn't tried again for
	  CheckEvery seconds and doesn't take a pull slot (at most RayBudget
	  rays per magnet per pass; an item still blocked while neither it nor
	  you moved BlockedMove studs waits BlockedBackoff seconds instead: the
	  wall is still there). Every CheckEvery a pull must have come
	  MinProgress studs closer, and a short ground probe ahead of it (one
	  ray per pulled item per pass) must find a floor within ProbeDrop, so
	  nothing is pushed forever against an obstacle or over a ledge (no new
	  probe while the item moved less than ProbeMove since the last one in
	  about the same direction, nor when the probed spot is at your own feet:
	  you stand on that floor). The ray filter is set once per magnet per pass.
	  The magnet GIVES UP on an item (MagnetDone) that got stuck, ran to a
	  ledge, or arrived when your hands were full; it tries again after
	  RetryAfter seconds, or once you went out of its range and came back
	  (picking it up clears it too).
	  Left alone: items you dropped or threw yourself (HandDropped, until
	  you pick them up again), items for Magnet.Delay seconds after they
	  appear, items a client still simulates whose travel isn't plausible
	  (isTrusted + MaxItemTravel: the magnet never launders a client-moved
	  item), items on or around a base (belts, chutes, the Ore Pen's
	  intake), items whose way to you passes an intake zone
	  (IntakeService.addZone registers every zone with magnetAvoid: the
	  SellBin, train hoppers..., so the magnet never pushes ore into a
	  sale), items far above or below you and items that aren't at a
	  finite position. At most MaxPulls items per magnet at once, the
	  nearest first. Replication stays small: one constraint per item, kept
	  and switched on / off (Enabled), its velocity rewritten only when it
	  changes by more than SteerChange; a pulled item's model carries the
	  CollectionService tag Magnet.Tag (clients draw a beam when its Owner
	  attribute is them).
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local DropperConfig = require(Shared.Config.DropperConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local ItemService = {}

ItemService.ItemGroup = "Items"
ItemService.CharacterGroup = "Characters"

export type Desc = ItemData.Desc
export type StoreResult = "Stored" | "Sold" | "Lost"

export type ItemRecord = {
	Id: number, -- short, per server session (a key and the look's seed)
	Model: Model,
	Body: BasePart,
	Kind: string,
	OreId: string,
	Grade: string?,
	Recipe: string?,
	Owner: number,
	State: string, -- Loose | Carried | Machine | Consumed
	Light: boolean, -- wears the light belt look (ItemBuilder.buildLight)
	Asleep: number?, -- os.clock() when it was anchored in a queue (sleep), nil = awake
	CreatedAt: number, -- also reset when the item is dropped/ejected
	ClientOwnedUntil: number?,
	LastNearOwner: number, -- os.clock() when the item was last near its owner or a machine
	BaseAt: Vector3?, -- where onBase was last asked for this item (looseCount's cache)
	OnBase: boolean?, -- its answer there
	ReleasePos: Vector3, -- where it was last spawned or released (trust and snap-back)
	ReleasedAt: number, -- os.clock() of that release
	-- the flat speed (studs/s) this release may plausibly reach (a strong
	-- throw, allowSpeed); nil = GameConfig.MaxItemSpeed. Reset by every release.
	MaxSpeed: number?,
	-- the Ore Magnet (see the header): dropped / thrown by the owner's hand
	-- (CarryService sets it, picking it up clears it), given up on (stuck, a
	-- ledge, full hands: tried again later, picking it up clears it), the
	-- pull constraint (kept once made, Enabled while pulled) and its last velocity
	HandDropped: boolean?,
	MagnetDone: boolean?,
	MagnetDoneAt: number?, -- os.clock() when the magnet gave up on it
	Pull: LinearVelocity?,
	PullVelocity: Vector2?,
	PullCheckedAt: number?, -- os.clock() of the last clear line-of-sight check
	PullFlat: number?, -- the flat distance to the owner at that check (progress)
	BlockedUntil: number?, -- a wall was in the way: not tried again before this os.clock()
	BlockedEye: Vector3?, -- where the owner's eye and the item were at that check (the backoff)
	BlockedAt: Vector3?,
	ProbeAt: Vector3?, -- the floor probe's cache: where the item was, its way, the answer
	ProbeDir: Vector3?,
	ProbeOk: boolean?,
}

local records: { [Model]: ItemRecord } = {}
local byId: { [number]: ItemRecord } = {}
-- owner UserId -> their records, so per-player counts don't walk every item
local byOwner: { [number]: { [ItemRecord]: boolean } } = {}
local folder: Folder
local nextId = 0
-- CarryService: a carried record was consumed (it drops it from its list)
local carriedConsumed: ((ItemRecord) -> ())? = nil

-- What the server keeps when it takes an item's physics back from a client (Security #8).
ItemService.HandBackSpeed = 20 -- studs/s
ItemService.HandBackSpin = 20 -- rad/s
ItemService.Gravity = 196.2 -- studs/s² when Workspace.Gravity can't be read

-- Queued items (sleep): woken around a taken item, never asleep longer than this.
ItemService.SleepMax = 6 -- seconds
ItemService.WakeRadius = 8 -- studs around a taken item where its owner's sleepers wake

--[[
	The parked-model pool (header): a light item a machine took stays as a
	hidden model for Keep seconds; a serverOwned spawn of the same owner
	within Reach studs wears it again. At most Max parked models per owner.
]]
ItemService.Pool = { Keep = 6, Reach = 14, Max = 8 }
type Parked = {
	Model: Model,
	Body: BasePart,
	At: number, -- os.clock() when it was parked
	Position: Vector3,
	Look: string, -- lookKey of what it still looks like
	Shown: { [BasePart]: number }, -- each part's Transparency before it was hidden
}
local parked: { [number]: { Parked } } = {}
local RAW_NAME = "Raw" -- every dirty ore model is called just this (Security #6)

---------------------------------------------------------------- the Ore Magnet (settings, letting go)

ItemService.Magnet = {
	Delay = 0.75, -- seconds after an item appears or is released before a magnet takes it
	StopDistance = 4.5, -- flat studs from the owner where a pulled item is let go (at your feet)
	StartDistance = 6, -- a pull only starts further away than this (StopDistance + 1.5: no flicker)
	Speed = 18, -- top pull speed (studs/s)
	MinSpeed = 7,
	SpeedPerStud = 1.6, -- pull speed per stud of distance (between MinSpeed and Speed)
	MaxPulls = 8, -- items one magnet pulls at once (the nearest with a clear way)
	RayBudget = 12, -- line-of-sight raycasts per magnet per pass
	MaxRise = 10, -- items further above or below the owner's root are left alone
	CheckEvery = 1, -- seconds between the line-of-sight checks of a pulled (or blocked) item
	MinProgress = 1, -- studs a pull must come closer per CheckEvery (else it is stuck: given up)
	RayHeight = 1.5, -- the line-of-sight ray runs this high above the owner's feet (curbs block it)
	ProbeAhead = 0.25, -- seconds of pull ahead of an item where its floor is probed
	ProbeDrop = 3, -- more floor than this below that point missing = a ledge (given up)
	ProbeUp = 2.5, -- the probe starts this high above it (a ramp up to you still has floor)
	ProbeMove = 1, -- studs an item must move (or turn ProbeTurn) before its floor is probed again
	ProbeTurn = 0.9, -- the cos of the turn that probes again (about 25 degrees)
	FeetReach = 3, -- a probed spot this close (flat) to your feet needs no ray: you stand there
	BlockedMove = 2, -- studs you or a blocked item must move before it is tried again after CheckEvery
	BlockedBackoff = 3, -- seconds a blocked item waits when neither moved
	RetryAfter = 10, -- seconds before an item the magnet gave up on is tried again
	BaseMargin = 4, -- studs around a base (machine grid + yard) where the magnet never pulls
	ZoneMargin = 5, -- studs around an intake zone (magnetAvoid) a pull's way keeps clear of
	ForcePerMass = 400, -- the pull's MaxForce per unit of the item's mass (beats ground friction)
	SteerChange = 0.1, -- the pull velocity is rewritten only when it changes by more than this share
	Tag = "MagnetPulled", -- CollectionService tag of a pulled item's model (client visuals)
	PullName = "MagnetPull", -- the LinearVelocity (and its Attachment) in the item's Body
}

-- items being pulled right now (so a magnet that went away lets go of them)
local pulling: { [ItemRecord]: boolean } = {}
-- intake zones the magnet keeps away from (magnetAvoid)
local avoidParts: { BasePart } = {}

-- Lets go of an item the magnet pulls. The constraint stays in the body,
-- switched off, for the next pull; `destroy` removes it (picked up, gone).
local function stopPull(record: ItemRecord, destroy: boolean?)
	local wasPulling = pulling[record] == true
	pulling[record] = nil
	record.PullCheckedAt = nil
	record.PullFlat = nil
	record.PullVelocity = nil
	local pull = record.Pull
	if pull then
		if destroy then
			record.Pull = nil
			local attachment = pull.Attachment0
			pull:Destroy()
			if attachment then
				attachment:Destroy()
			end
		elseif pull.Enabled then
			pull.Enabled = false
		end
	end
	if wasPulling and record.Model.Parent then
		record.Model:RemoveTag(ItemService.Magnet.Tag)
	end
end

-- Keeps the Ore Magnet's pulls away from an intake zone (a part whose box
-- takes loose items: the SellBin, train hoppers, pens...). IntakeService.addZone
-- calls it for every zone it registers.
function ItemService.magnetAvoid(part: BasePart)
	if not table.find(avoidParts, part) then
		table.insert(avoidParts, part)
	end
end

local function finiteVector(v: Vector3): boolean
	local s = v.X + v.Y + v.Z
	return s == s and s > -math.huge and s < math.huge
end

local function ownerPlayer(record: ItemRecord): Player?
	return Players:GetPlayerByUserId(record.Owner)
end

-- Root part of a user's living character (nil when not in the game).
local function ownerRoot(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function finiteNumber(v: number): boolean
	return v == v and v > -math.huge and v < math.huge
end

-- Workspace.Gravity (ItemService.Gravity when it can't be read).
local function gravity(): number
	local ok, g = pcall(function(): any
		return Workspace.Gravity
	end)
	if ok and type(g) == "number" and g > 1 and g < 10000 then
		return g
	end
	return ItemService.Gravity
end

local function index(record: ItemRecord)
	records[record.Model] = record
	byId[record.Id] = record
	local set = byOwner[record.Owner]
	if not set then
		set = {}
		byOwner[record.Owner] = set
	end
	set[record] = true
end

local function unindex(record: ItemRecord)
	-- (a parked model may already be worn by a newer record: only our own entries go)
	if records[record.Model] == record then
		records[record.Model] = nil
	end
	if byId[record.Id] == record then
		byId[record.Id] = nil
	end
	local set = byOwner[record.Owner]
	if set then
		set[record] = nil
		if next(set) == nil then
			byOwner[record.Owner] = nil
		end
	end
end

-- Where an item is (Body.CFrame.Position is Body.Position; the Lune tests can read it).
local function positionOf(record: ItemRecord): Vector3
	return record.Body.CFrame.Position
end

local function setNetworkOwner(record: ItemRecord, player: Player?)
	local body = record.Body
	pcall(function()
		if not body.Anchored and body:IsDescendantOf(Workspace) and body:CanSetNetworkOwnership() then
			body:SetNetworkOwner(player)
		end
	end)
end

local function setGroup(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = ItemService.ItemGroup
		end
	end
end

-- The look a model wears, as a key (a parked model with the same key is reused as it is).
local function lookKey(kind: string, oreId: string, grade: string?, recipe: string?, light: boolean): string
	return `{kind}|{oreId}|{grade or ""}|{recipe or ""}|{if light then "L" else "F"}`
end

local function infoOf(record: ItemRecord): ItemBuilder.ItemInfo
	return { Kind = record.Kind, OreId = record.OreId, Grade = record.Grade, Recipe = record.Recipe }
end

local function buildLook(info: ItemBuilder.ItemInfo, cf: CFrame, seed: number, light: boolean): Model
	if light then
		return ItemBuilder.buildLight(info, cf, seed)
	end
	return ItemBuilder.build(info, cf, seed)
end

--[[
	Puts the look of `fresh` (a just built, unparented item model) onto
	`model`, keeping model's Body part (its CFrame, physics and every
	reference to it stay valid). Everything in the Body (welds, sparkles, a
	pull constraint, a carry weld) goes: callers stop pulls and weld again
	afterwards.
]]
local function transplant(model: Model, body: BasePart, fresh: Model)
	local newBody = fresh.PrimaryPart :: BasePart
	for _, child in model:GetChildren() do
		if child ~= body then
			child:Destroy()
		end
	end
	for _, child in body:GetChildren() do
		child:Destroy()
	end
	if body:IsA("Part") and newBody:IsA("Part") then
		body.Shape = newBody.Shape
	end
	body.Size = newBody.Size
	body.CFrame = newBody.CFrame
	body.Color = newBody.Color
	body.Material = newBody.Material
	body.Transparency = newBody.Transparency
	body.Reflectance = newBody.Reflectance
	body.CastShadow = newBody.CastShadow
	body.CustomPhysicalProperties = newBody.CustomPhysicalProperties
	for _, child in newBody:GetChildren() do
		if not child:IsA("WeldConstraint") then
			child.Parent = body
		end
	end
	for _, child in fresh:GetChildren() do
		if child ~= newBody then
			child.Parent = model
			if child:IsA("BasePart") then
				child.CollisionGroup = ItemService.ItemGroup
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = child
				weld.Parent = body
			end
		end
	end
	fresh:Destroy()
end

local function syncAttributes(record: ItemRecord)
	local m = record.Model
	-- dirty ore and dusty relics keep their secret until they are cleaned
	local raw = record.Kind == "Raw" or record.Kind == "Relic"
	m:SetAttribute("Kind", record.Kind)
	m:SetAttribute("Owner", record.Owner)
	m:SetAttribute("State", record.State)
	-- dirty ore keeps its secret until it is cleaned: no ore id, no value
	-- (the server keeps record.OreId); a reused model loses the old ones
	m:SetAttribute("OreId", if raw then nil else record.OreId)
	m:SetAttribute("Grade", record.Grade)
	m:SetAttribute("Recipe", record.Recipe)
	m:SetAttribute("Value", if raw then nil else ItemData.value(record.Kind, record.OreId, record.Grade, record.Recipe))
	local name = if record.Kind == "Relic" then "Relic" elseif raw then RAW_NAME else record.Kind .. "_" .. record.OreId
	if m.Name ~= name then
		m.Name = name
	end
end

local function markReleased(record: ItemRecord)
	record.ReleasePos = positionOf(record)
	record.ReleasedAt = os.clock()
	record.MaxSpeed = nil
end

-- Unanchors every part of a loose item (only the Body collides and touches).
local function loosen(record: ItemRecord)
	for _, d in record.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = d ~= record.Body
			d.CanCollide = d == record.Body
			d.Anchored = false
		end
	end
end

function ItemService.get(model: Instance?): ItemRecord?
	if typeof(model) ~= "Instance" then
		return nil
	end
	return records[model :: Model]
end

function ItemService.getById(id: number): ItemRecord?
	return byId[id]
end

-- Finds the item record for any part of an item model.
function ItemService.fromPart(part: Instance?): ItemRecord?
	local node = part
	while node and node ~= folder do
		if node:IsA("Model") and records[node] then
			return records[node]
		end
		node = node.Parent
	end
	return nil
end

-- Sets an item's state (Loose | Carried | Machine). A consumed record is
-- refused (false): it is gone for good (Security #11).
function ItemService.setState(record: ItemRecord, state: string): boolean
	if record.State == "Consumed" then
		return false
	end
	record.State = state
	if state ~= "Loose" then
		-- carried, in a machine...: the magnet lets go (and its constraint
		-- goes), and a hand-dropped or already fetched item counts as new
		-- again once it was picked up
		stopPull(record, true)
		record.HandDropped = nil
		record.MagnetDone = nil
		record.MagnetDoneAt = nil
		record.BlockedUntil = nil
		record.Asleep = nil
	end
	if record.Model.Parent then
		record.Model:SetAttribute("State", state)
	end
	return true
end

--[[
	Switches an item between the light belt look (light = true) and the full
	look, in place (the same Model and Body). CarryService puts on the full
	look at every pickup, before it welds the item to the hand. False when
	nothing changed (already dressed so, or consumed).
]]
function ItemService.dress(record: ItemRecord, light: boolean): boolean
	if record.State == "Consumed" or record.Light == light then
		return false
	end
	stopPull(record, true)
	record.Pull = nil
	transplant(record.Model, record.Body, buildLook(infoOf(record), record.Body.CFrame, record.Id, light))
	record.Light = light
	return true
end

-- The item as a storage descriptor (a fresh table).
function ItemService.descOf(record: ItemRecord): Desc
	return { K = record.Kind, O = record.OreId, G = record.Grade, R = record.Recipe }
end

export type LooseWhere = "Base" | "Away"

-- Is this item on / around a base? Cached per item until it moved 2 studs
-- (looseCount runs every machine tick pass and at every rock stage).
local function recordOnBase(record: ItemRecord): boolean
	local position = record.Body.CFrame.Position
	local last = record.BaseAt
	if last and (last - position).Magnitude < 2 then
		return record.OnBase == true
	end
	local on = ItemService.onBase(position)
	record.BaseAt = position
	record.OnBase = on
	return on
end

-- The player's loose items: all, or only those on / around a base ("Base":
-- belts, chutes, the pen gate) or away from every base ("Away": mine drops).
function ItemService.looseCount(userId: number, where: LooseWhere?): number
	local count = 0
	local set = byOwner[userId]
	if set then
		for record in set do
			if record.State == "Loose" then
				if where == nil then
					count += 1
				else
					if recordOnBase(record) == (where == "Base") then
						count += 1
					end
				end
			end
		end
	end
	return count
end

-- Does this player have as many loose items away from bases as the world
-- lets them have (GameConfig.MaxLooseItemsPerPlayer)? Mining stops giving
-- ore then (MiningService); items on bases don't count (the factory's own cap).
function ItemService.atLooseCap(userId: number): boolean
	return ItemService.looseCount(userId, "Away") >= GameConfig.MaxLooseItemsPerPlayer
end

-- Has this player as many loose items, anywhere, as the hard ceiling
-- (GameConfig.MaxLooseItemsTotal)? Hand drops, throws and Pen takes stop.
function ItemService.atTotalCap(userId: number): boolean
	return ItemService.looseCount(userId) >= GameConfig.MaxLooseItemsTotal
end

-- Room for more loose items under the hard ceiling.
function ItemService.totalRoom(userId: number): number
	return math.max(0, GameConfig.MaxLooseItemsTotal - ItemService.looseCount(userId))
end

-- Every loose item. A copy, so callers may destroy items while walking it.
function ItemService.looseList(): { ItemRecord }
	local list = {}
	for _, record in records do
		if record.State == "Loose" then
			table.insert(list, record)
		end
	end
	return list
end

---------------------------------------------------------------- sleeping queues

local function setAnchored(record: ItemRecord, anchored: boolean)
	for _, d in record.Model:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored ~= anchored then
			d.Anchored = anchored
		end
	end
end

--[[
	Anchors a loose item where it is while it waits in a queue at a full
	machine (the belt code decides that), so it costs no awake physics. Not
	while a client simulates it or the magnet pulls it. True = asleep now.
]]
function ItemService.sleep(record: ItemRecord): boolean
	if record.State ~= "Loose" or record.ClientOwnedUntil ~= nil or pulling[record] then
		return false
	end
	if not record.Asleep then
		record.Asleep = os.clock()
		setAnchored(record, true)
	end
	return true
end

-- Lets a sleeping item move again (true = it was asleep).
function ItemService.wake(record: ItemRecord): boolean
	if not record.Asleep then
		return false
	end
	record.Asleep = nil
	if record.State == "Loose" then
		setAnchored(record, false)
	end
	return true
end

-- Wakes the owner's sleeping items within `radius` studs of `position`
-- (taking an item lets the queue behind it move up). Returns how many.
function ItemService.wakeNear(userId: number, position: Vector3, radius: number?): number
	local set = byOwner[userId]
	if not set then
		return 0
	end
	local reach = radius or ItemService.WakeRadius
	local woken = 0
	for record in set do
		if record.Asleep and (positionOf(record) - position).Magnitude <= reach then
			ItemService.wake(record)
			woken += 1
		end
	end
	return woken
end

---------------------------------------------------------------- taking items out of the world

-- Marks a record consumed and forgets it (the model is the caller's).
local function consume(record: ItemRecord)
	local wasCarried = record.State == "Carried"
	record.State = "Consumed"
	record.Asleep = nil
	stopPull(record, true)
	unindex(record)
	local hook = carriedConsumed
	if wasCarried and hook then
		-- CarryService drops it from the hands' list (never breaks the caller)
		local ok, err = pcall(hook :: any, record)
		if not ok then
			warn(`[ItemService] carried item {record.Id}: {err}`)
		end
	end
end

-- CarryService listens here: a record it carries was consumed.
function ItemService.onCarriedConsumed(callback: ((ItemRecord) -> ())?)
	carriedConsumed = callback
end

local function destroyParked(entry: Parked)
	entry.Model:Destroy()
end

-- Hides a light belt item's model where it lies, for the next spawn near
-- it (the pool, header). False when it can't be parked (then the caller
-- destroys it).
local function park(record: ItemRecord, position: Vector3): boolean
	local model = record.Model
	local items: Folder? = folder
	if items == nil or model.Parent ~= items or not finiteVector(position) then
		return false
	end
	local list = parked[record.Owner]
	if not list then
		list = {}
		parked[record.Owner] = list
	end
	if #list >= ItemService.Pool.Max then
		destroyParked(table.remove(list, 1) :: Parked)
	end
	local shown: { [BasePart]: number } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			shown[d] = d.Transparency
			d.Anchored = true
			d.Transparency = 1
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	-- clients only look at tagged items: a parked model is nothing to them
	model:RemoveTag("Item")
	table.insert(list, {
		Model = model,
		Body = record.Body,
		At = os.clock(),
		Position = position,
		Look = lookKey(record.Kind, record.OreId, record.Grade, record.Recipe, record.Light),
		Shown = shown,
	})
	return true
end

-- The nearest parked model of `owner` within Pool.Reach of `position` (taken out of the pool).
local function unpark(owner: number, position: Vector3): Parked?
	local list = parked[owner]
	if not list then
		return nil
	end
	local best: Parked? = nil
	local bestIndex = 0
	local bestDistance = ItemService.Pool.Reach
	for i, entry in list do
		local distance = (entry.Position - position).Magnitude
		if entry.Model.Parent ~= nil and distance <= bestDistance then
			best, bestIndex, bestDistance = entry, i, distance
		end
	end
	if best then
		table.remove(list, bestIndex)
		if #list == 0 then
			parked[owner] = nil
		end
	end
	return best
end

-- Parked models older than Pool.Keep go for good (the maintenance pass).
local function expireParked(now: number)
	for owner, list in parked do
		for i = #list, 1, -1 do
			local entry = list[i]
			if now - entry.At >= ItemService.Pool.Keep or entry.Model.Parent == nil then
				table.remove(list, i)
				destroyParked(entry)
			end
		end
		if #list == 0 then
			parked[owner] = nil
		end
	end
end

-- Destroys every parked model of a user (leaving).
local function clearParked(userId: number)
	local list = parked[userId]
	parked[userId] = nil
	if list then
		for _, entry in list do
			destroyParked(entry)
		end
	end
end

-- Takes an item out of the world for good. A record consumed before is
-- left alone (its model may already be worn again by a newer item).
function ItemService.destroy(record: ItemRecord)
	if record.State == "Consumed" then
		return
	end
	consume(record)
	record.Model:Destroy()
end

-- Takes an item out of the world (into a machine, a sale...) and returns
-- what it was. Works in any state except Consumed (CarryService.pickup puts
-- what it absorbs into the backpack's counts). A light item
-- taken off the ground (a belt) leaves its model parked for the next spawn
-- near it, and wakes its owner's sleeping items around it.
function ItemService.absorb(record: ItemRecord): Desc
	assert(record.State ~= "Consumed", "absorb: item already consumed")
	local desc = ItemService.descOf(record)
	local weld = record.Body:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	record.Model:SetAttribute("CarriedBy", nil)
	local fromBelt = record.State == "Loose" and record.Light
	local position = positionOf(record)
	consume(record)
	if not (fromBelt and park(record, position)) then
		record.Model:Destroy()
	end
	if fromBelt and finiteVector(position) then
		ItemService.wakeNear(record.Owner, position)
	end
	return desc
end

-- How many items the Ore Pen of this save holds (pen upgrades, DataStore cap).
function ItemService.penCapacity(data: { [string]: any }): number
	local upgrades = data.Upgrades
	local level = if type(upgrades) == "table" then upgrades.PenLevel else 0
	return EconomyConfig.penCapacity(level, GameConfig.MaxStoredItems)
end

--[[
	A RESCUE move into the player's Ore Pen (data.Storage): leaving the
	game, an item the engine destroyed, an item returned from someone
	else's plot (and Placement's layout repair, which writes the save
	itself). Nothing may be lost there, so it may fill the pen past its
	capacity, up to the DataStore cap (GameConfig.MaxStoredItems); only
	beyond that is the item sold at Tobin's price, so a dirty Mythic is never
	sold without the player choosing it. 'Lost' only when the player's data
	isn't loaded or the descriptor is junk. With a reason, the player gets a
	toast. Everything the player or their automation puts in goes through
	PenService, which refuses at the capacity (and while the pen is over it).
]]
-- Who takes a dusty relic that a rescue move would store (ArtifactService:
-- it is cleaned on the way, the artifact goes into the collection).
local relicKeeper: ((Player, string, Vector3?) -> boolean)? = nil

function ItemService.setRelicKeeper(keeper: ((Player, string, Vector3?) -> boolean)?)
	relicKeeper = keeper
end

-- Cleans a dusty relic of `player` through the keeper (the Cleaning Station):
-- true when its artifact went into the collection.
function ItemService.keepRelic(player: Player, artifactId: string, position: Vector3?): boolean
	local keeper = relicKeeper
	return keeper ~= nil and keeper(player, artifactId, position)
end

function ItemService.storeDesc(player: Player, desc: Desc, reason: string?): StoreResult
	local data = DataService.get(player)
	if not data then
		return "Lost"
	end
	if type(desc) ~= "table" or type(desc.K) ~= "string" or type(desc.O) ~= "string" then
		warn("[ItemService] storeDesc got a bad item for " .. player.Name)
		return "Lost"
	end
	-- a dropper's Drop is never kept (DropperConfig): it just goes
	if DropperConfig.isDrop(desc) then
		return "Lost"
	end
	-- a dusty relic never waits in the pen: the keeper cleans it on the way
	-- (nothing is lost); without a keeper it waits there as data
	if desc.K == "Relic" then
		local keeper = relicKeeper
		if keeper and keeper(player, desc.O) then
			return "Stored"
		end
	end
	local result: StoreResult
	local value = 0
	if #data.Storage < GameConfig.MaxStoredItems then
		table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		result = "Stored"
		DataService.changed(player)
	else
		-- DataStore cap reached: pay what Tobin would (base value x the
		-- player's sell bonus, Bonuses.sellAmount) instead of losing the item
		value = Bonuses.sellAmount(Bonuses.stats(player), ItemData.value(desc.K, desc.O, desc.G, desc.R))
		EconomyService.award(player, value, "PenFull")
		result = "Sold"
	end
	if reason and player.Parent then
		Net.fire("Notify", player, {
			Text = if result == "Stored"
				then reason .. " (moved to your Ore Pen)"
				else `{reason} (no room left anywhere: sold it for {Format.money(value)})`,
			Kind = "Info",
		})
	end
	return result
end

-- Rescues an item into the owner's Ore Pen (storeDesc; sold only at the
-- DataStore cap). Returns true when the item was kept (stored).
function ItemService.stash(record: ItemRecord, reason: string?): boolean
	if record.State == "Consumed" then
		-- already taken out of the world (and kept or used): never a second copy
		return false
	end
	local player = ownerPlayer(record)
	local desc = ItemService.descOf(record)
	ItemService.destroy(record)
	if not player then
		return false
	end
	return ItemService.storeDesc(player, desc, reason) == "Stored"
end

-- The owner's client simulates the item for a moment (smooth throws), but
-- only when it is close enough to surely have the item streamed in.
local function giveClientPhysics(record: ItemRecord)
	local player = ownerPlayer(record)
	local root = ownerRoot(record.Owner)
	if player and root and (root.Position - positionOf(record)).Magnitude <= GameConfig.ClientPhysicsRange then
		setNetworkOwner(record, player)
		record.ClientOwnedUntil = os.clock() + GameConfig.ServerOwnershipAfter
	else
		setNetworkOwner(record, nil)
		record.ClientOwnedUntil = nil
	end
end

local function keepServerPhysics(record: ItemRecord)
	setNetworkOwner(record, nil)
	record.ClientOwnedUntil = nil
end

-- A parked model worn again by a new item at `cf` (the pool, header).
local function wearParked(entry: Parked, info: ItemBuilder.ItemInfo, cf: CFrame, seed: number, light: boolean): (Model, BasePart)
	local model, body = entry.Model, entry.Body
	if entry.Look == lookKey(info.Kind, info.OreId, info.Grade, info.Recipe, light) then
		-- the same look: shown again as it was
		for part, transparency in entry.Shown do
			if part.Parent then
				part.Transparency = transparency
			end
		end
	else
		transplant(model, body, buildLook(info, cf, seed, light))
	end
	model:PivotTo(cf)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = true -- so clicking any part of the item targets it
			d.CanTouch = d == body
		end
	end
	model:AddTag("Item")
	return model, body
end

local function create(info: ItemBuilder.ItemInfo, owner: number, cf: CFrame, velocity: Vector3?, serverOwned: boolean): ItemRecord?
	-- a dusty relic carries an artifact id where ore carries its ore, a
	-- dropper's Drop its dropper's id (DropperConfig)
	local known = if info.Kind == "Relic"
		then ArtifactConfig.ById[info.OreId] ~= nil
		elseif info.Kind == DropperConfig.DropKind then DropperConfig.validDrop({
			K = info.Kind,
			O = info.OreId,
			G = info.Grade,
			R = info.Recipe,
		})
		else OreData.exists(info.OreId)
	if not known or not ItemData.Kinds[info.Kind] then
		warn("[ItemService] bad item info", info.Kind, info.OreId)
		return nil
	end
	nextId += 1
	local id = nextId
	-- machines and chutes (serverOwned) make belt items: the light look,
	-- in a parked model of the same owner nearby when there is one
	-- (a dropper's Drop always wears the full ore look: owner 2026-10-24, "it must look like our ores")
	local light = serverOwned and info.Kind ~= DropperConfig.DropKind
	local reuse = if light then unpark(owner, cf.Position) else nil
	local model: Model, body: BasePart
	if reuse then
		model, body = wearParked(reuse, info, cf, id, light)
	else
		model = buildLook(info, cf, id, light)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model:AddTag("Item")
		setGroup(model)
		body = model.PrimaryPart :: BasePart
	end
	local now = os.clock()
	local record: ItemRecord = {
		Id = id,
		Model = model,
		Body = body,
		Kind = info.Kind,
		OreId = info.OreId,
		Grade = info.Grade,
		Recipe = info.Recipe,
		Owner = owner,
		State = "Loose",
		Light = light,
		CreatedAt = now,
		ClientOwnedUntil = nil,
		LastNearOwner = now,
		ReleasePos = cf.Position,
		ReleasedAt = now,
	}
	index(record)
	syncAttributes(record)
	if reuse then
		loosen(record)
	else
		model.Parent = folder
	end
	markReleased(record)
	if velocity then
		body.AssemblyLinearVelocity = velocity
		body.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
	elseif reuse then
		body.AssemblyLinearVelocity = Vector3.zero
		body.AssemblyAngularVelocity = Vector3.zero
	end
	if serverOwned then
		keepServerPhysics(record)
	else
		giveClientPhysics(record)
	end
	return record
end

--[[
	Spawns a physical item (the full look; a mining drop, a cleaned ore...).
	info = { Kind, OreId, Grade?, Recipe? }, owner = UserId.
]]
function ItemService.spawn(info: ItemBuilder.ItemInfo, owner: number, cf: CFrame, velocity: Vector3?): ItemRecord?
	return create(info, owner, cf, velocity, false)
end

--[[
	Spawns an item from a descriptor (machine output, storage). With
	`serverOwned` the server keeps its physics from the start: machine
	outputs riding belts are then never waiting on a client (see isTrusted),
	and it wears the light belt look, re-using a parked model of the same
	owner within Pool.Reach when there is one (MachineService.emit,
	ConveyorService's chutes: nothing to change there).
]]
function ItemService.spawnDesc(desc: Desc, ownerUserId: number, cf: CFrame, velocity: Vector3?, serverOwned: boolean?): ItemRecord?
	if type(desc) ~= "table" or type(desc.K) ~= "string" or type(desc.O) ~= "string" then
		warn("[ItemService] spawnDesc got a bad item")
		return nil
	end
	return create({ Kind = desc.K, OreId = desc.O, Grade = desc.G, Recipe = desc.R }, ownerUserId, cf, velocity, serverOwned == true)
end

-- Re-creates an item from storage data next to a position.
function ItemService.spawnFromStorage(entry: { [string]: any }, owner: number, cf: CFrame): ItemRecord?
	return ItemService.spawnDesc(entry :: any, owner, cf)
end

-- Makes an item loose again at a CFrame (after being carried or ejected by
-- a machine). A consumed record is refused (false).
function ItemService.release(record: ItemRecord, cf: CFrame, velocity: Vector3?): boolean
	if record.State == "Consumed" then
		return false
	end
	local model = record.Model
	model:PivotTo(cf)
	loosen(record)
	ItemService.setState(record, "Loose")
	record.Asleep = nil
	record.CreatedAt = os.clock()
	record.LastNearOwner = os.clock()
	markReleased(record)
	if velocity then
		record.Body.AssemblyLinearVelocity = velocity
	end
	giveClientPhysics(record)
	return true
end

-- Pops an item out of where it is (a refused item bouncing out of a hopper).
function ItemService.eject(record: ItemRecord, velocity: Vector3): boolean
	if record.State == "Consumed" then
		return false
	end
	return ItemService.release(record, record.Model:GetPivot() + Vector3.new(0, 1.5, 0), velocity)
end

-- Anchors an item into a machine slot (state "Machine"). A consumed record is refused (false).
function ItemService.mount(record: ItemRecord, cf: CFrame): boolean
	if record.State == "Consumed" then
		return false
	end
	local model = record.Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(cf)
	record.ClientOwnedUntil = nil
	ItemService.setState(record, "Machine")
	return true
end

-- The flat speed (studs/s) the item's current release can plausibly reach.
local function maxSpeedOf(record: ItemRecord): number
	local speed = record.MaxSpeed
	if speed and speed == speed and speed > GameConfig.MaxItemSpeed then
		return speed
	end
	return GameConfig.MaxItemSpeed
end

--[[
	A strong throw (Grip Gloves): the item just released may plausibly fly at
	`flatSpeed` studs/s, so isTrusted and the MaxItemTravel snap-back allow
	that much for this release (never less than GameConfig.MaxItemSpeed, at
	most ItemService.MaxSpeedScale times it). The next release resets it.
]]
ItemService.MaxSpeedScale = 2
function ItemService.allowSpeed(record: ItemRecord, flatSpeed: number)
	if type(flatSpeed) ~= "number" or flatSpeed ~= flatSpeed then
		return
	end
	local base = GameConfig.MaxItemSpeed
	record.MaxSpeed = math.clamp(flatSpeed, base, base * ItemService.MaxSpeedScale)
end

-- How far (studs) the item may be from its release point when the server
-- takes its physics back: MaxItemTravel, scaled with a strong throw's speed.
function ItemService.travelLimit(record: ItemRecord): number
	return GameConfig.MaxItemTravel * maxSpeedOf(record) / GameConfig.MaxItemSpeed
end

-- How high (studs) above its release point the item can plausibly get:
-- the top of a throw at its release's speed (straight up), plus PlausibleSlack.
function ItemService.riseLimit(record: ItemRecord): number
	local speed = maxSpeedOf(record)
	return speed * speed / (2 * gravity()) + GameConfig.PlausibleSlack
end

-- Could this item have got from its release point to `position` by itself
-- (no further than travelLimit, no higher than riseLimit)?
local function reachable(record: ItemRecord, position: Vector3): boolean
	return (position - record.ReleasePos).Magnitude <= ItemService.travelLimit(record)
		and position.Y - record.ReleasePos.Y <= ItemService.riseLimit(record)
end

--[[
	Can a machine believe where this item is? Always, while the server
	simulates it. While the owner's client does, the owner must be close
	(AntiTeleportRange), the item can't have travelled further since its
	release than its release's speed allows (MaxItemSpeed, or a strong
	throw's allowSpeed, plus PlausibleSlack) nor risen above riseLimit.
	`now` = os.clock().
]]
function ItemService.isTrusted(record: ItemRecord, now: number): boolean
	if record.ClientOwnedUntil == nil then
		return true
	end
	local root = ownerRoot(record.Owner)
	if not root then
		return false
	end
	local position = positionOf(record)
	if (root.Position - position).Magnitude > GameConfig.AntiTeleportRange then
		return false
	end
	if position.Y - record.ReleasePos.Y > ItemService.riseLimit(record) then
		return false
	end
	local flat = Vector3.new(position.X - record.ReleasePos.X, 0, position.Z - record.ReleasePos.Z).Magnitude
	return flat <= math.max(0, now - record.ReleasedAt) * maxSpeedOf(record) + GameConfig.PlausibleSlack
end

-- All items (any state) owned by a user.
function ItemService.ownedBy(userId: number): { ItemRecord }
	local list = {}
	local set = byOwner[userId]
	if set then
		for record in set do
			table.insert(list, record)
		end
	end
	return list
end

local function rescueCFrame(userId: number): CFrame?
	local root = ownerRoot(userId)
	if root then
		return root.CFrame * CFrame.new(0, 2, -4)
	end
	return nil
end

-- Puts a lost item back next to its owner, or into the Ore Pen when they have no character.
local function rescue(record: ItemRecord)
	stopPull(record)
	local cf = rescueCFrame(record.Owner)
	if cf then
		if not finiteVector(positionOf(record)) then
			-- a broken pivot can't be moved from: place the body itself
			record.Body.CFrame = cf
		end
		record.Body.AssemblyLinearVelocity = Vector3.zero
		record.Body.AssemblyAngularVelocity = Vector3.zero
		ItemService.release(record, cf)
	else
		ItemService.stash(record, nil)
	end
end

-- Caps a vector's length (a non-finite one becomes zero).
local function capped(v: Vector3, limit: number): Vector3?
	local length = v.Magnitude
	if not finiteNumber(length) then
		return Vector3.zero
	end
	if length > limit then
		return v.Unit * limit
	end
	return nil
end

-- The server takes an item's physics back: whatever speed the client gave
-- it, at most HandBackSpeed and HandBackSpin are kept (Security #8).
local function capHandBack(record: ItemRecord)
	local body = record.Body
	-- (read safely: a body that never moved may have no velocity yet under Lune)
	local okLinear, v = pcall(function(): Vector3
		return body.AssemblyLinearVelocity
	end)
	local linear = if okLinear then capped(v, ItemService.HandBackSpeed) else nil
	if linear then
		body.AssemblyLinearVelocity = linear
	end
	local okSpin, w = pcall(function(): Vector3
		return body.AssemblyAngularVelocity
	end)
	local spin = if okSpin then capped(w, ItemService.HandBackSpin) else nil
	if spin then
		body.AssemblyAngularVelocity = spin
	end
end

--[[
	One record's part of the maintenance pass. `root` is the owner's
	character root (looked up once per owner per pass, nil = none).
]]
local function maintainOne(record: ItemRecord, now: number, root: BasePart?)
	if not record.Model.Parent or not record.Body.Parent then
		-- destroyed by the engine (fell below FallenPartsDestroyHeight): keep it in the pen
		if record.State ~= "Consumed" then
			local desc = ItemService.descOf(record)
			consume(record)
			local player = ownerPlayer(record)
			if player then
				ItemService.storeDesc(player, desc, nil)
			end
		else
			unindex(record)
		end
		record.Pull = nil
		record.PullVelocity = nil
		return
	end
	if record.State ~= "Loose" then
		return
	end
	local position = positionOf(record)
	-- fell out of the world, or physics broke (NaN / inf): put it back
	if not finiteVector(position) or position.Y < GameConfig.ItemFallKillY then
		rescue(record)
		return
	end
	local asleep = record.Asleep
	if asleep and now - asleep >= ItemService.SleepMax then
		-- nothing sleeps for ever (a belt taken away under a queue)
		ItemService.wake(record)
	end
	if record.ClientOwnedUntil and now > record.ClientOwnedUntil then
		record.ClientOwnedUntil = nil
		setNetworkOwner(record, nil)
		capHandBack(record)
		-- a client moved it implausibly far (or high) while it simulated it: put it back
		if not reachable(record, position) then
			warn(`[ItemService] item {record.Id} of user {record.Owner} travelled too far, returning it`)
			rescue(record)
			return
		end
	end
	-- remember when the owner was last close (machines use this against item teleporting)
	if root and (root.Position - position).Magnitude < 40 then
		record.LastNearOwner = now
	end
end

-- The mine cap's last resort (see the header): ore away from bases that
-- was left behind (not near its owner for StaleAwaySeconds and further than
-- StaleAwayStuds now) or lies stuck (StuckSeconds since it was dropped,
-- still out of grab reach) goes into the pen, oldest first, until the
-- player is back under the cap. Only while at the cap, every StaleCheckEvery.
ItemService.StaleAwaySeconds = 90
ItemService.StaleAwayStuds = 60
ItemService.StuckSeconds = 180
ItemService.StaleCheckEvery = 2
local staleCheckedAt: { [number]: number } = {}

local function rescueStale(owner: number, now: number, root: BasePart?)
	if now - (staleCheckedAt[owner] or -math.huge) < ItemService.StaleCheckEvery then
		return
	end
	staleCheckedAt[owner] = now
	local set = byOwner[owner]
	if not set then
		return
	end
	local away: { ItemRecord } = {}
	for record in set do
		if record.State == "Loose" and not recordOnBase(record) then
			table.insert(away, record)
		end
	end
	local cap = GameConfig.MaxLooseItemsPerPlayer
	if #away < cap then
		return
	end
	local grab = GameConfig.PickupRange + 2
	local stale: { ItemRecord } = {}
	for _, record in away do
		local distance = if root then (root.Position - positionOf(record)).Magnitude else math.huge
		local leftBehind = now - record.LastNearOwner >= ItemService.StaleAwaySeconds and distance > ItemService.StaleAwayStuds
		local stuck = now - record.CreatedAt >= ItemService.StuckSeconds and distance > grab
		if leftBehind or stuck then
			table.insert(stale, record)
		end
	end
	if #stale == 0 then
		return
	end
	table.sort(stale, function(a: ItemRecord, b: ItemRecord): boolean
		return a.CreatedAt < b.CreatedAt
	end)
	local player = ownerPlayer(stale[1])
	local moved = 0
	for i = 1, math.min(#away - cap + 1, #stale) do
		ItemService.stash(stale[i], nil) -- a rescue move: may overfill the pen (header)
		moved += 1
	end
	if player and moved > 0 then
		local what = if moved == 1 then "1 ore" else `{moved} ore`
		Net.fire("Notify", player, {
			Text = `{what} you left lying in the mine went into your Ore Pen, so your rocks give ore again.`,
			Kind = "Info",
		})
	end
end

--[[
	The maintenance pass (every 0.25 s from start; the tests call it): each
	owner's root is looked up once, every record checked in a protected
	call without a closure per record, old parked models dropped, and the
	mine cap's rescue (rescueStale).
]]
function ItemService.maintainAll(now: number)
	for owner, set in byOwner do
		local root = ownerRoot(owner)
		for record in set do
			local ok, err = pcall(maintainOne :: any, record, now, root)
			if not ok then
				warn("[ItemService] maintenance error: " .. tostring(err))
			end
		end
		local rescued, why = pcall(rescueStale :: any, owner, now, root)
		if not rescued then
			warn("[ItemService] rescue error: " .. tostring(why))
		end
	end
	for owner in staleCheckedAt do
		if not byOwner[owner] then
			staleCheckedAt[owner] = nil
		end
	end
	expireParked(now)
end

local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ItemService.ItemGroup)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(ItemService.CharacterGroup)
	end)
	PhysicsService:CollisionGroupSetCollidable(ItemService.ItemGroup, ItemService.CharacterGroup, false)

	local function characterParts(character: Model)
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = ItemService.CharacterGroup
			end
		end
		character.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = ItemService.CharacterGroup
			end
		end)
	end
	local function setupPlayer(player: Player)
		if player.Character then
			characterParts(player.Character)
		end
		player.CharacterAdded:Connect(characterParts)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

---------------------------------------------------------------- the Ore Magnet (pulling)

-- The player's magnet radius (0 = none). Swappable for the Lune tests.
local function defaultMagnetRadius(player: Player): number
	return Bonuses.magnetRadius(Bonuses.stats(player))
end
local magnetRadiusOf: (Player) -> number = defaultMagnetRadius

local rayParams: RaycastParams? = nil
local rayCharacter: Model? = nil -- whose character the filter holds now
local rayFolder: Folder? = nil

-- The magnet's raycast filter: items and the owner's character never count.
-- The filter is only set again when the character changes (the magnet does
-- one player at a time: once per magnet per pass, not per ray).
local function magnetRayParams(character: Model?): RaycastParams
	local params = rayParams
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.RespectCanCollide = true
		rayParams = made
		params = made
		rayCharacter = nil
		rayFolder = nil
	end
	local p = params :: RaycastParams
	if rayCharacter ~= character or rayFolder ~= folder then
		local ignore: { Instance } = { folder }
		if character then
			table.insert(ignore, character)
		end
		p.FilterDescendantsInstances = ignore
		rayCharacter = character
		rayFolder = folder
	end
	return p
end

-- Nothing solid between `from` and `to` (items and the owner's character don't count).
local function defaultClearPath(from: Vector3, to: Vector3, character: Model?): boolean
	return Workspace:Raycast(from, to - from, magnetRayParams(character)) == nil
end
local clearPath: (Vector3, Vector3, Model?) -> boolean = defaultClearPath

-- Is there floor under `point` (an item's bottom at a spot ahead of it),
-- at most Magnet.ProbeDrop below it? No floor = a ledge or a pit. The ray
-- starts ProbeUp above it, so a ramp rising toward you still counts.
local function defaultFloorAhead(point: Vector3, character: Model?): boolean
	local m = ItemService.Magnet
	local origin = point + Vector3.new(0, m.ProbeUp, 0)
	local down = Vector3.new(0, -(m.ProbeUp + m.ProbeDrop), 0)
	return Workspace:Raycast(origin, down, magnetRayParams(character)) ~= nil
end
local floorAhead: (Vector3, Model?) -> boolean = defaultFloorAhead

--[[
	The owner's hands (CarryService.init sets them with setMagnetHands;
	ItemService can't require CarryService): how many more items they take
	right now, and taking an item that arrived at the owner's feet into
	them (true = carried now). Without them (the Lune tests) the magnet
	pulls up to MaxPulls and an arriving item stays at your feet.
]]
local handsRoom: ((Player) -> number)? = nil
local handsCatch: ((Player, ItemRecord) -> boolean)? = nil

function ItemService.setMagnetHands(room: ((Player) -> number)?, catch: ((Player, ItemRecord) -> boolean)?)
	handsRoom = room
	handsCatch = catch
end

-- A base in plot-local studs: the 12 x 12 machine grid and the yard behind it.
local BASE_HALF_X = math.max(GameConfig.PlotCells * GameConfig.CellSize / 2, BaseLayout.Yard.Size.X / 2)
local BASE_MIN_Z = -GameConfig.PlotCells * GameConfig.CellSize / 2
local BASE_MAX_Z = BaseLayout.Yard.Center.Z + BaseLayout.Yard.Size.Z / 2
local BASE_REACH = math.sqrt(BASE_HALF_X * BASE_HALF_X + math.max(-BASE_MIN_Z, BASE_MAX_Z) ^ 2) + 16
local baseFrames: { CFrame } = {}

-- Is a world position on or around any base (grid + yard, plus `margin`, default
-- Magnet.BaseMargin)? The magnet never pulls there: belts, chutes and the Ore Pen's intake
-- work with loose items. (CarryService's auto-pickup asks with margin 0: the margin would
-- cover the alleys between the plots, where the town's starter outcrops stand.)
function ItemService.onBase(position: Vector3, margin: number?): boolean
	if #baseFrames == 0 then
		for _, plot in WorldLayout.Plots do
			table.insert(baseFrames, WorldLayout.plotCFrame(plot))
		end
	end
	local edge = if margin then margin else ItemService.Magnet.BaseMargin
	for _, frame in baseFrames do
		local offset = position - frame.Position
		if offset.X * offset.X + offset.Z * offset.Z <= BASE_REACH * BASE_REACH then
			local p = frame:PointToObjectSpace(position)
			if
				math.abs(p.X) <= BASE_HALF_X + edge
				and p.Z >= BASE_MIN_Z - edge
				and p.Z <= BASE_MAX_Z + edge
				and p.Y >= -10
				and p.Y <= 40
			then
				return true
			end
		end
	end
	return false
end

-- Does the straight way from `a` to `b` pass within `margin` studs of the
-- box of `part` (its CFrame and Size)? A slab test in the part's space.
local function wayNearBox(part: BasePart, a: Vector3, b: Vector3, margin: number): boolean
	local cf = part.CFrame
	local half = part.Size / 2
	local p0 = cf:PointToObjectSpace(a)
	local p1 = cf:PointToObjectSpace(b)
	local d = p1 - p0
	local tMin, tMax = 0, 1
	local starts = { p0.X, p0.Y, p0.Z }
	local deltas = { d.X, d.Y, d.Z }
	local halves = { half.X + margin, half.Y + margin, half.Z + margin }
	for axis = 1, 3 do
		local o, dd, h = starts[axis], deltas[axis], halves[axis]
		if math.abs(dd) < 1e-9 then
			if math.abs(o) > h then
				return false
			end
		else
			local t1, t2 = (-h - o) / dd, (h - o) / dd
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return false
			end
		end
	end
	return true
end

-- The intake zones (magnetAvoid) a magnet at `rootPos` with `radius` could reach.
local function zonesNear(rootPos: Vector3, radius: number): { BasePart }
	local near: { BasePart } = {}
	for i = #avoidParts, 1, -1 do
		local part = avoidParts[i]
		if not part.Parent then
			table.remove(avoidParts, i)
		else
			local reach = radius + part.Size.Magnitude / 2 + ItemService.Magnet.ZoneMargin
			local offset = part.CFrame.Position - rootPos
			if offset.X * offset.X + offset.Z * offset.Z <= reach * reach then
				table.insert(near, part)
			end
		end
	end
	return near
end

-- Would pulling from `from` to the owner at `to` pass an intake zone?
function ItemService.wayNearZone(from: Vector3, to: Vector3, zones: { BasePart }?): boolean
	local margin = ItemService.Magnet.ZoneMargin
	local list: { BasePart } = zones or avoidParts
	for _, part in list do
		if part.Parent and wayNearBox(part, from, to, margin) then
			return true
		end
	end
	return false
end

-- May the server take this item's physics now? Always when it already has
-- them; while a client simulates it, only when its travel is plausible (the
-- same checks as isTrusted and the maintenance snap-back), so the magnet
-- never turns a client-moved item into a trusted one.
local function plausible(record: ItemRecord, now: number, position: Vector3): boolean
	if record.ClientOwnedUntil == nil then
		return true
	end
	return ItemService.isTrusted(record, now) and (position - record.ReleasePos).Magnitude <= ItemService.travelLimit(record)
end

--[[
	Does a magnet of `radius` studs whose owner's root is at `rootPos` want
	to pull this item now (`now` = os.clock())? The line of sight and the
	intake zones are checked separately (magnetStep). Also returns the flat
	distance to the owner (0 when the item was turned down before that)
	and whether it is an item the magnet would take but that already lies
	at the owner's feet (within StartDistance, or StopDistance while it is
	pulled): the hands may take that one (magnetFor).
]]
function ItemService.magnetWants(record: ItemRecord, rootPos: Vector3, radius: number, now: number): (boolean, number, boolean)
	local m = ItemService.Magnet
	if record.State ~= "Loose" or record.HandDropped or record.MagnetDone or not (radius > 0) or not record.Model.Parent then
		return false, 0, false
	end
	-- a dropper's Drop is never carried (DropperConfig)
	if record.Kind == DropperConfig.DropKind then
		return false, 0, false
	end
	if now - record.ReleasedAt < m.Delay then
		return false, 0, false
	end
	local position = positionOf(record)
	if not finiteVector(position) or not finiteVector(rootPos) then
		return false, 0, false
	end
	local dx, dz = rootPos.X - position.X, rootPos.Z - position.Z
	local flat = math.sqrt(dx * dx + dz * dz)
	if not (flat <= radius) or math.abs(rootPos.Y - position.Y) > m.MaxRise then
		return false, flat, false
	end
	if not plausible(record, now, position) or ItemService.onBase(position) then
		return false, flat, false
	end
	-- hysteresis: a pull starts beyond StartDistance and goes on down to StopDistance
	local near = if pulling[record] then m.StopDistance else m.StartDistance
	if flat <= near then
		return false, flat, true
	end
	return true, flat, false
end

-- The pull speed (studs/s) for an item `flat` studs away.
function ItemService.pullSpeed(flat: number): number
	local m = ItemService.Magnet
	return math.clamp(flat * m.SpeedPerStud, m.MinSpeed, m.Speed)
end

local function itemMass(record: ItemRecord): number
	local ok, mass = pcall(function()
		return record.Body.AssemblyMass
	end)
	if ok and type(mass) == "number" and mass > 0 and mass < math.huge then
		return mass
	end
	return 2
end

-- Starts or steers the pull of one item toward `rootPos` (flat: the ground
-- plane). The constraint is made once and switched on / off; its velocity
-- is only rewritten when it changed by more than SteerChange.
local function pullToward(record: ItemRecord, rootPos: Vector3, flat: number)
	local m = ItemService.Magnet
	local position = positionOf(record)
	local dir = Vector3.new(rootPos.X - position.X, 0, rootPos.Z - position.Z)
	local velocity = if dir.Magnitude > 1e-3 then dir.Unit * ItemService.pullSpeed(flat) else Vector3.zero
	local plane = Vector2.new(velocity.X, velocity.Z)
	local pull = record.Pull
	if pull and pull.Parent ~= record.Body then
		-- the old one went away with a rebuilt body: make a new one
		record.Pull = nil
		pull = nil
	end
	if not pulling[record] then
		-- the server simulates it from now on (magnetWants checked it is plausible)
		ItemService.wake(record)
		keepServerPhysics(record)
		if not pull then
			local attachment = Instance.new("Attachment")
			attachment.Name = m.PullName
			attachment.Parent = record.Body
			local made = Instance.new("LinearVelocity")
			made.Name = m.PullName
			made.Attachment0 = attachment
			made.RelativeTo = Enum.ActuatorRelativeTo.World
			made.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
			made.PrimaryTangentAxis = Vector3.new(1, 0, 0)
			made.SecondaryTangentAxis = Vector3.new(0, 0, 1)
			made.MaxForce = itemMass(record) * m.ForcePerMass
			made.PlaneVelocity = plane
			made.Parent = record.Body
			record.Pull = made
		else
			local existing = pull :: LinearVelocity
			existing.PlaneVelocity = plane
			existing.Enabled = true
		end
		record.PullVelocity = plane
		pulling[record] = true
		record.Model:AddTag(m.Tag)
		-- wake a resting item up
		record.Body.AssemblyLinearVelocity = velocity + Vector3.new(0, 2, 0)
		return
	end
	local current = record.Pull
	local last = record.PullVelocity
	if current and (not last or (plane - last).Magnitude > m.SteerChange * math.max(last.Magnitude, 1)) then
		current.PlaneVelocity = plane
		record.PullVelocity = plane
	end
end

-- A living character's root part and humanoid (nil when dead or not spawned).
local function aliveRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?, humanoid
end

-- How high a character's root is above its feet (R15: HipHeight + half
-- the root; R6: half the root + 2 studs of legs); 3 when unknown.
local function rootHeight(humanoid: Humanoid?, root: BasePart): number
	if not humanoid then
		return 3
	end
	local ok, height = pcall(function(): number
		local half = root.Size.Y / 2
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			return half + 2
		end
		return humanoid.HipHeight + half
	end)
	if ok and type(height) == "number" and height == height and height > 0.5 and height < 20 then
		return height
	end
	return 3
end

type Wanted = { Record: ItemRecord, Flat: number, Position: Vector3 }

-- Half an item's height (its bottom is that far below its centre).
local function halfHeight(record: ItemRecord): number
	local y = record.Body.Size.Y
	return if y > 0 and y < 20 then y / 2 else 0.5
end

-- The magnet gives up on an item for now (stuck, a ledge, full hands):
-- tried again after RetryAfter or once the owner left its range (see magnetFor).
local function giveUp(record: ItemRecord, now: number)
	stopPull(record)
	record.MagnetDone = true
	record.MagnetDoneAt = now
end

-- Steers one pull toward the owner, unless the floor ends just ahead of
-- the item (a ledge, a pit): then the magnet gives up on it. True = pulled.
-- No new probe while the item moved less than ProbeMove (and turned less
-- than ProbeTurn) since its last good one, nor when the probed spot is at
-- your feet (FeetReach, about your feet's height `feetY`: you stand there).
local function steer(record: ItemRecord, entry: Wanted, rootPos: Vector3, feetY: number, character: Model?, now: number): boolean
	local m = ItemService.Magnet
	local position = entry.Position
	local dir = Vector3.new(rootPos.X - position.X, 0, rootPos.Z - position.Z)
	if dir.Magnitude > 1e-3 then
		local unit = dir.Unit
		local ahead = math.max(1, ItemService.pullSpeed(entry.Flat) * m.ProbeAhead)
		local point = position + unit * ahead - Vector3.new(0, halfHeight(record), 0)
		local fx, fz = rootPos.X - point.X, rootPos.Z - point.Z
		local atFeet = fx * fx + fz * fz <= m.FeetReach * m.FeetReach and math.abs(point.Y - feetY) <= 1.5
		local lastAt, lastDir = record.ProbeAt, record.ProbeDir
		local fresh = record.ProbeOk == true
			and lastAt ~= nil
			and lastDir ~= nil
			and (position - lastAt).Magnitude < m.ProbeMove
			and unit:Dot(lastDir) >= m.ProbeTurn
		if not atFeet and not fresh then
			local ok = floorAhead(point, character)
			record.ProbeAt = position
			record.ProbeDir = unit
			record.ProbeOk = ok
			if not ok then
				giveUp(record, now)
				return false
			end
		end
	end
	pullToward(record, rootPos, entry.Flat)
	return true
end

-- Is a blocked item still behind its wall? Never before BlockedUntil; after
-- it, only while neither the owner's eye nor the item moved BlockedMove
-- studs, and at most BlockedBackoff seconds since the check (the wall is
-- still there: no new ray needed).
local function stillBlocked(record: ItemRecord, eye: Vector3, position: Vector3, now: number): boolean
	local untilAt = record.BlockedUntil
	if not untilAt then
		return false
	end
	if now < untilAt then
		return true
	end
	local m = ItemService.Magnet
	if now - (untilAt - m.CheckEvery) >= m.BlockedBackoff then
		return false
	end
	local fromEye, fromAt = record.BlockedEye, record.BlockedAt
	if not fromEye or not fromAt then
		return false
	end
	return (eye - fromEye).Magnitude < m.BlockedMove and (position - fromAt).Magnitude < m.BlockedMove
end

-- One player's part of a magnet pass (see magnetStep).
local function magnetFor(player: Player, set: { [ItemRecord]: boolean }, root: BasePart, humanoid: Humanoid?, radius: number, now: number)
	local m = ItemService.Magnet
	local rootPos = root.Position
	if not finiteVector(rootPos) then
		for record in set do
			stopPull(record)
		end
		return
	end
	local character = player.Character
	local catch = handsCatch
	-- what the hands still take (one less after every catch); without hands: MaxPulls
	local room = if handsRoom then handsRoom(player) else m.MaxPulls
	room = if room == room then math.max(0, math.floor(room)) else 0
	local wanted: { Wanted } = {}
	for record in set do
		if record.MagnetDone and record.State == "Loose" then
			-- given up on: tried again after RetryAfter, or once you went out of
			-- range (you come back for it)
			local position = positionOf(record)
			local dx, dz = rootPos.X - position.X, rootPos.Z - position.Z
			local since = record.MagnetDoneAt
			if not since or now - since >= m.RetryAfter or not (dx * dx + dz * dz <= radius * radius) then
				record.MagnetDone = nil
				record.MagnetDoneAt = nil
			end
		end
		local wants, flat, atFeet = ItemService.magnetWants(record, rootPos, radius, now)
		if wants then
			table.insert(wanted, { Record = record, Flat = flat, Position = positionOf(record) })
		else
			local was = pulling[record] == true
			if was then
				stopPull(record)
			end
			if atFeet then
				-- at your feet (pulled here, or it landed here): into your hands
				if catch and room > 0 and catch(player, record) then
					room -= 1
				elseif was then
					-- arrived with full hands: left there, given up on for now
					giveUp(record, now)
				end
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.Flat < b.Flat
	end)
	-- only as many pulls as the hands still take: with full hands nothing
	-- moves, nothing herds after you
	local slots = math.min(m.MaxPulls, room)
	if #wanted == 0 or slots <= 0 then
		-- nothing to pull (or full hands): no zones, no rays
		for _, entry in wanted do
			stopPull(entry.Record)
		end
		return
	end
	local zones = zonesNear(rootPos, radius)
	-- the line of sight runs low (RayHeight above the feet): curbs and railings count
	local feetY = rootPos.Y - rootHeight(humanoid, root)
	local eye = Vector3.new(rootPos.X, feetY + m.RayHeight, rootPos.Z)
	local pulled, rays = 0, 0
	for _, entry in wanted do
		local record = entry.Record
		local was = pulling[record] == true
		local checked = record.PullCheckedAt
		local due = not was or not checked or now - checked >= m.CheckEvery
		local last = record.PullFlat
		if pulled >= slots then
			stopPull(record)
		elseif #zones > 0 and ItemService.wayNearZone(entry.Position, rootPos, zones) then
			-- never push ore into a sale or a hopper
			stopPull(record)
		elseif not was and stillBlocked(record, eye, entry.Position, now) then
			-- a wall was in the way a moment ago (and nothing moved since): not tried again yet
		elseif was and due and last and last - entry.Flat < m.MinProgress then
			-- no closer than a CheckEvery ago: stuck on something low, or you
			-- walk away faster than it slides
			giveUp(record, now)
		elseif due and rays >= m.RayBudget then
			-- no rays left this pass: a pull goes on and is checked next time
			if was and steer(record, entry, rootPos, feetY, character, now) then
				pulled += 1
			end
		elseif due then
			rays += 1
			if clearPath(eye, entry.Position + Vector3.new(0, 0.5, 0), character) then
				record.BlockedUntil = nil
				record.BlockedEye = nil
				record.BlockedAt = nil
				if steer(record, entry, rootPos, feetY, character, now) then
					record.PullCheckedAt = now
					record.PullFlat = entry.Flat
					pulled += 1
				end
			else
				record.BlockedUntil = now + m.CheckEvery
				record.BlockedEye = eye
				record.BlockedAt = entry.Position
				stopPull(record)
			end
		elseif steer(record, entry, rootPos, feetY, character, now) then
			pulled += 1
		end
	end
end

--[[
	One magnet pass (every 0.25 s from start; `now` = os.clock()): for each
	player with a magnet, the nearest wanted items (magnetWants) whose way
	is clear (no wall: line of sight; no intake zone; floor ahead) slide
	toward them, at most Magnet.MaxPulls and no more than their hands still
	take; every other pull lets go. An item that arrives goes into the
	owner's hands (setMagnetHands). Only that player's own items are looked
	at. Each player's part runs on its own (an error in one never stops the
	others).
]]
function ItemService.magnetStep(now: number)
	local active: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			local set = byOwner[player.UserId]
			local root, humanoid = nil, nil
			if set then
				root, humanoid = aliveRoot(player)
			end
			local radius = if root then magnetRadiusOf(player) else 0
			if set and root and radius > 0 then
				active[player.UserId] = true
				magnetFor(player, set, root, humanoid, radius, now)
			end
		end)
		if not ok then
			warn(`[ItemService] magnet error for user {player.UserId}: {err}`)
		end
	end
	-- a magnet that went away (unequipped, dead, left) lets go of its items
	for record in pulling do
		if not active[record.Owner] then
			stopPull(record)
		end
	end
end

-- Internals for the Lune tests only (tests/ItemService.spec.luau, tests/GearService.spec.luau).
ItemService._test = {
	-- one record's maintenance (its owner's root looked up now)
	maintain = function(record: ItemRecord, now: number)
		maintainOne(record, now, ownerRoot(record.Owner))
	end,
	-- forget every item record and parked model (the models are left alone)
	reset = function()
		table.clear(records)
		table.clear(byId)
		table.clear(byOwner)
		table.clear(staleCheckedAt)
		table.clear(pulling)
		table.clear(avoidParts)
		table.clear(parked)
		magnetRadiusOf = defaultMagnetRadius
		clearPath = defaultClearPath
		floorAhead = defaultFloorAhead
		handsRoom = nil
		handsCatch = nil
		carriedConsumed = nil
		rayParams = nil
		folder = nil :: any
	end,
	-- Workspace.Items in the game; the tests' own folder (items parked or
	-- reused must live in it)
	setFolder = function(f: Folder?)
		folder = f :: any
	end,
	-- the parked models of a user (the pool)
	parked = function(userId: number): number
		local list = parked[userId]
		return if list then #list else 0
	end,
	-- the magnet's radius per player and its line-of-sight check (nil = the
	-- real one), and its floor probe (nil = there is always a floor: the
	-- tests' world has nothing to raycast)
	setMagnet = function(
		radius: ((Player) -> number)?,
		path: ((Vector3, Vector3, Model?) -> boolean)?,
		floor: ((Vector3, Model?) -> boolean)?
	)
		magnetRadiusOf = radius or defaultMagnetRadius
		clearPath = path or defaultClearPath
		floorAhead = floor or function(_point: Vector3, _character: Model?): boolean
			return true
		end
	end,
	pulling = function(): { ItemRecord }
		local list = {}
		for record in pulling do
			table.insert(list, record)
		end
		return list
	end,
}

function ItemService.init()
	folder = Workspace:FindFirstChild("Items") :: Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Items"
		f.Parent = Workspace
		folder = f
	end
	setupCollisionGroups()

	-- Leaving players: keep their items in the Ore Pen (a rescue move).
	DataService.beforeRelease(function(player)
		for _, record in ItemService.ownedBy(player.UserId) do
			if record.State == "Loose" or record.State == "Carried" then
				ItemService.stash(record, nil)
			end
		end
		clearParked(player.UserId)
	end)
end

function ItemService.start()
	while true do
		task.wait(0.25)
		local now = os.clock()
		ItemService.maintainAll(now)
		-- the Ore Magnet (gear): own loose items slide to their owner
		local magnetOk, magnetErr = pcall(ItemService.magnetStep :: any, now)
		if not magnetOk then
			warn("[ItemService] magnet error: " .. tostring(magnetErr))
		end
	end
end

return ItemService
