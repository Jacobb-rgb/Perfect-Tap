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
	- Performance: max GameConfig.MaxLooseItemsPerPlayer loose items per
	  player; when exceeded the oldest one is moved into the Ore Pen (data),
	  so nothing is ever lost. Resting items sleep in Roblox physics by themselves.
	- Items that fall out of the world are put back next to their owner.
	- Leaving players: loose and carried items go into the Ore Pen.
	- The Ore Pen (data.Storage) holds EconomyConfig.penCapacity items;
	  storeDesc pays Tobin's price for anything beyond that.
	- Dirty ore hides its rarity: the replicated Value attribute of a Raw
	  item is 0 (the real price is only paid out by the server).
	- Fast throws (Grip Gloves): CarryService.onThrow raises the item's
	  plausible speed for that one release (allowSpeed), so isTrusted and
	  the MaxItemTravel snap-back scale with it instead of refusing a legal
	  long throw. Any other release goes back to GameConfig.MaxItemSpeed.
	- Items whose position isn't a finite number are put back next to their
	  owner (or into the pen) by the maintenance pass.
	- The Ore Magnet (gear, ItemService.Magnet): every 0.25 s, for each
	  player whose Bonuses.magnetRadius is above 0, their OWN loose items
	  within that radius slide to them (never another player's). Server
	  physics: the item gets a LinearVelocity in the ground plane (gravity
	  and walls still act, so nothing passes through a wall), and a ray from
	  the owner to the item must be clear before (and every CheckEvery
	  seconds while) it is pulled; a blocked item isn't tried again for
	  CheckEvery seconds and doesn't take a pull slot (at most RayBudget rays
	  per magnet per pass). It FETCHES, it doesn't herd: an item that reached
	  your feet (StopDistance) is done (MagnetDone) until it is picked up, so
	  nothing follows you around. Left alone: items you dropped or threw
	  yourself (HandDropped, until you pick them up again), items for
	  Magnet.Delay seconds after they appear, items a client still simulates
	  whose travel isn't plausible (isTrusted + MaxItemTravel: the magnet
	  never launders a client-moved item), items on or around a base (belts,
	  chutes, the Ore Pen's intake), items whose way to you passes an intake
	  zone (IntakeService.addZone registers every zone with magnetAvoid: the
	  SellBin, train hoppers..., so the magnet never pushes ore into a sale),
	  items far above or below you, items that aren't at a finite position,
	  and items already near your feet (a pull starts beyond StartDistance and
	  ends at StopDistance). At most MaxPulls items per magnet at once, the
	  nearest first. Replication stays small: one constraint per item, kept
	  and switched on / off (Enabled), its velocity rewritten only when it
	  changes by more than SteerChange; a pulled item's model carries the
	  CollectionService tag Magnet.Tag (clients draw a beam when its Owner
	  attribute is them).
]]

local HttpService = game:GetService("HttpService")
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
	Id: string,
	Model: Model,
	Body: BasePart,
	Kind: string,
	OreId: string,
	Grade: string?,
	Recipe: string?,
	Owner: number,
	State: string, -- Loose | Carried | Machine | Consumed
	CreatedAt: number, -- also reset when the item is dropped/ejected (loose-cap order)
	ClientOwnedUntil: number?,
	LastNearOwner: number, -- os.clock() when the item was last near its owner or a machine
	ReleasePos: Vector3, -- where it was last spawned or released (trust and snap-back)
	ReleasedAt: number, -- os.clock() of that release
	-- the flat speed (studs/s) this release may plausibly reach (a strong
	-- throw, allowSpeed); nil = GameConfig.MaxItemSpeed. Reset by every release.
	MaxSpeed: number?,
	-- the Ore Magnet (see the header): dropped / thrown by the owner's hand
	-- (CarryService sets it, picking it up clears it), already pulled to the
	-- owner's feet once (picking it up clears it), the pull constraint (kept
	-- once made, Enabled while pulled) and its last velocity
	HandDropped: boolean?,
	MagnetDone: boolean?,
	Pull: LinearVelocity?,
	PullVelocity: Vector2?,
	PullCheckedAt: number?, -- os.clock() of the last clear line-of-sight check
	BlockedUntil: number?, -- a wall was in the way: not tried again before this os.clock()
}

local records: { [Model]: ItemRecord } = {}
local byId: { [string]: ItemRecord } = {}
-- owner UserId -> their records, so per-player counts don't walk every item
local byOwner: { [number]: { [ItemRecord]: boolean } } = {}
local folder: Folder
local lastCapToast: { [number]: number } = {}

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
	records[record.Model] = nil
	byId[record.Id] = nil
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

local function syncAttributes(record: ItemRecord)
	local m = record.Model
	m:SetAttribute("ItemId", record.Id)
	m:SetAttribute("Kind", record.Kind)
	m:SetAttribute("OreId", record.OreId)
	m:SetAttribute("Grade", record.Grade)
	m:SetAttribute("Recipe", record.Recipe)
	m:SetAttribute("Owner", record.Owner)
	m:SetAttribute("State", record.State)
	-- dirty ore keeps its secret until it is cleaned
	local value = if record.Kind == "Raw" then 0 else ItemData.value(record.Kind, record.OreId, record.Grade, record.Recipe)
	m:SetAttribute("Value", value)
end

local function markReleased(record: ItemRecord)
	record.ReleasePos = positionOf(record)
	record.ReleasedAt = os.clock()
	record.MaxSpeed = nil
end

function ItemService.get(model: Instance?): ItemRecord?
	if typeof(model) ~= "Instance" then
		return nil
	end
	return records[model :: Model]
end

function ItemService.getById(id: string): ItemRecord?
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

function ItemService.setState(record: ItemRecord, state: string)
	record.State = state
	if state ~= "Loose" then
		-- carried, in a machine...: the magnet lets go (and its constraint
		-- goes), and a hand-dropped or already fetched item counts as new
		-- again once it was picked up
		stopPull(record, true)
		record.HandDropped = nil
		record.MagnetDone = nil
		record.BlockedUntil = nil
	end
	if record.Model.Parent then
		record.Model:SetAttribute("State", state)
	end
end

-- The item as a storage descriptor (a fresh table).
function ItemService.descOf(record: ItemRecord): Desc
	return { K = record.Kind, O = record.OreId, G = record.Grade, R = record.Recipe }
end

function ItemService.looseCount(userId: number): number
	local count = 0
	local set = byOwner[userId]
	if set then
		for record in set do
			if record.State == "Loose" then
				count += 1
			end
		end
	end
	return count
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

function ItemService.destroy(record: ItemRecord)
	record.State = "Consumed"
	stopPull(record, true)
	unindex(record)
	record.Model:Destroy()
end

-- Takes an item out of the world (into a machine, a sale...) and returns
-- what it was. Works in any state except Consumed; a carried item should
-- come off the carry stack first (CarryService.takeTop).
function ItemService.absorb(record: ItemRecord): Desc
	assert(record.State ~= "Consumed", "absorb: item already consumed")
	local desc = ItemService.descOf(record)
	local weld = record.Body:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	record.Model:SetAttribute("CarriedBy", nil)
	ItemService.destroy(record)
	return desc
end

-- How many items the Ore Pen of this save holds (pen upgrades, DataStore cap).
function ItemService.penCapacity(data: { [string]: any }): number
	local upgrades = data.Upgrades
	local level = if type(upgrades) == "table" then upgrades.PenLevel else 0
	return EconomyConfig.penCapacity(level, GameConfig.MaxStoredItems)
end

--[[
	Puts an item descriptor into the player's Ore Pen (data.Storage). These
	are system moves (leaving, too many loose items, packing a machine up),
	so they may fill the pen past its capacity, up to the DataStore cap
	(GameConfig.MaxStoredItems); only beyond that is the item sold at
	Tobin's price, so nothing is ever lost and a dirty Mythic is never sold
	without the player choosing it. 'Lost' only when the player's data isn't
	loaded or the descriptor is junk. With a reason, the player gets a toast.
	(Players filling the pen by hand are refused at capacity: PenService.)
]]
function ItemService.storeDesc(player: Player, desc: Desc, reason: string?): StoreResult
	local data = DataService.get(player)
	if not data then
		return "Lost"
	end
	if type(desc) ~= "table" or type(desc.K) ~= "string" or type(desc.O) ~= "string" then
		warn("[ItemService] storeDesc got a bad item for " .. player.Name)
		return "Lost"
	end
	local result: StoreResult
	local value = 0
	if #data.Storage < GameConfig.MaxStoredItems then
		table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		result = "Stored"
		DataService.changed(player)
	else
		-- DataStore cap reached: pay the full value instead of losing the item
		value = ItemData.value(desc.K, desc.O, desc.G, desc.R)
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

-- Moves an item into the owner's Ore Pen (or sells it if the pen is full).
-- Returns true when the item was kept (stored).
function ItemService.stash(record: ItemRecord, reason: string?): boolean
	local player = ownerPlayer(record)
	local desc = ItemService.descOf(record)
	ItemService.destroy(record)
	if not player then
		return false
	end
	return ItemService.storeDesc(player, desc, reason) == "Stored"
end

local function enforceLooseLimit(userId: number)
	local loose = {}
	local set = byOwner[userId]
	if set then
		for record in set do
			if record.State == "Loose" then
				table.insert(loose, record)
			end
		end
	end
	if #loose <= GameConfig.MaxLooseItemsPerPlayer then
		return
	end
	table.sort(loose, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	local now = os.clock()
	local toast = now - (lastCapToast[userId] or 0) > 20
	if toast then
		lastCapToast[userId] = now
	end
	for i = 1, #loose - GameConfig.MaxLooseItemsPerPlayer do
		ItemService.stash(loose[i], if i == 1 and toast then "Too many loose items" else nil)
	end
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

local function create(info: ItemBuilder.ItemInfo, owner: number, cf: CFrame, velocity: Vector3?, serverOwned: boolean): ItemRecord?
	if not OreData.exists(info.OreId) or not ItemData.Kinds[info.Kind] then
		warn("[ItemService] bad item info", info.Kind, info.OreId)
		return nil
	end
	local id = HttpService:GenerateGUID(false)
	local model = ItemBuilder.build(info, cf, id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("Item")
	setGroup(model)
	local body = model.PrimaryPart :: BasePart
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
		CreatedAt = now,
		ClientOwnedUntil = nil,
		LastNearOwner = now,
		ReleasePos = cf.Position,
		ReleasedAt = now,
	}
	index(record)
	syncAttributes(record)
	model.Parent = folder
	markReleased(record)
	if velocity then
		body.AssemblyLinearVelocity = velocity
		body.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
	end
	if serverOwned then
		keepServerPhysics(record)
	else
		giveClientPhysics(record)
	end
	enforceLooseLimit(owner)
	return record
end

--[[
	Spawns a physical item.
	info = { Kind, OreId, Grade?, Recipe? }, owner = UserId.
]]
function ItemService.spawn(info: ItemBuilder.ItemInfo, owner: number, cf: CFrame, velocity: Vector3?): ItemRecord?
	return create(info, owner, cf, velocity, false)
end

--[[
	Spawns an item from a descriptor (machine output, storage). With
	`serverOwned` the server keeps its physics from the start: machine
	outputs riding belts are then never waiting on a client (see isTrusted).
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

-- Makes an item loose again at a CFrame (after being carried or ejected by a machine).
function ItemService.release(record: ItemRecord, cf: CFrame, velocity: Vector3?)
	local model = record.Model
	model:PivotTo(cf)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = d ~= record.Body
			d.CanCollide = d == record.Body
			d.Anchored = false
		end
	end
	ItemService.setState(record, "Loose")
	record.CreatedAt = os.clock()
	record.LastNearOwner = os.clock()
	markReleased(record)
	if velocity then
		record.Body.AssemblyLinearVelocity = velocity
	end
	giveClientPhysics(record)
	enforceLooseLimit(record.Owner)
end

-- Pops an item out of where it is (a refused item bouncing out of a hopper).
function ItemService.eject(record: ItemRecord, velocity: Vector3)
	ItemService.release(record, record.Model:GetPivot() + Vector3.new(0, 1.5, 0), velocity)
end

-- Anchors an item into a machine slot (state "Machine").
function ItemService.mount(record: ItemRecord, cf: CFrame)
	local model = record.Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(cf)
	record.ClientOwnedUntil = nil
	ItemService.setState(record, "Machine")
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

--[[
	Can a machine believe where this item is? Always, while the server
	simulates it. While the owner's client does, the owner must be close
	(AntiTeleportRange) and the item can't have travelled further since its
	release than its release's speed allows (MaxItemSpeed, or a strong
	throw's allowSpeed, plus PlausibleSlack). `now` = os.clock().
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

local function maintainOne(record: ItemRecord, now: number)
	if not record.Model.Parent or not record.Body.Parent then
		-- destroyed by the engine (fell below FallenPartsDestroyHeight): keep it in the pen
		pulling[record] = nil
		record.Pull = nil
		record.PullVelocity = nil
		unindex(record)
		if record.State ~= "Consumed" then
			record.State = "Consumed"
			local player = ownerPlayer(record)
			if player then
				ItemService.storeDesc(player, ItemService.descOf(record), nil)
			end
		end
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
	if record.ClientOwnedUntil and now > record.ClientOwnedUntil then
		record.ClientOwnedUntil = nil
		setNetworkOwner(record, nil)
		-- a client moved it implausibly far while it simulated it: put it back
		if (position - record.ReleasePos).Magnitude > ItemService.travelLimit(record) then
			warn(`[ItemService] item {record.Id} of user {record.Owner} travelled too far, returning it`)
			rescue(record)
			return
		end
	end
	-- remember when the owner was last close (machines use this against item teleporting)
	local root = ownerRoot(record.Owner)
	if root and (root.Position - position).Magnitude < 40 then
		record.LastNearOwner = now
	end
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

-- Nothing solid between `from` and `to` (items and the owner's character don't count).
local function defaultClearPath(from: Vector3, to: Vector3, character: Model?): boolean
	local params = rayParams
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.RespectCanCollide = true
		rayParams = made
		params = made
	end
	local p = params :: RaycastParams
	local ignore: { Instance } = { folder }
	if character then
		table.insert(ignore, character)
	end
	p.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, to - from, p) == nil
end
local clearPath: (Vector3, Vector3, Model?) -> boolean = defaultClearPath

-- A base in plot-local studs: the 12 x 12 machine grid and the yard behind it.
local BASE_HALF_X = math.max(GameConfig.PlotCells * GameConfig.CellSize / 2, BaseLayout.Yard.Size.X / 2)
local BASE_MIN_Z = -GameConfig.PlotCells * GameConfig.CellSize / 2
local BASE_MAX_Z = BaseLayout.Yard.Center.Z + BaseLayout.Yard.Size.Z / 2
local BASE_REACH = math.sqrt(BASE_HALF_X * BASE_HALF_X + math.max(-BASE_MIN_Z, BASE_MAX_Z) ^ 2) + 16
local baseFrames: { CFrame } = {}

-- Is a world position on or around any base (grid + yard, plus Magnet.BaseMargin)?
-- The magnet never pulls there: belts, chutes and the Ore Pen's intake work with loose items.
function ItemService.onBase(position: Vector3): boolean
	if #baseFrames == 0 then
		for _, plot in WorldLayout.Plots do
			table.insert(baseFrames, WorldLayout.plotCFrame(plot))
		end
	end
	local margin = ItemService.Magnet.BaseMargin
	for _, frame in baseFrames do
		local offset = position - frame.Position
		if offset.X * offset.X + offset.Z * offset.Z <= BASE_REACH * BASE_REACH then
			local p = frame:PointToObjectSpace(position)
			if
				math.abs(p.X) <= BASE_HALF_X + margin
				and p.Z >= BASE_MIN_Z - margin
				and p.Z <= BASE_MAX_Z + margin
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
	this item now (`now` = os.clock())? The line of sight and the intake
	zones are checked separately (magnetStep). Also returns the flat
	distance to the owner (0 when the item was turned down before that).
]]
function ItemService.magnetWants(record: ItemRecord, rootPos: Vector3, radius: number, now: number): (boolean, number)
	local m = ItemService.Magnet
	if record.State ~= "Loose" or record.HandDropped or record.MagnetDone or not (radius > 0) or not record.Model.Parent then
		return false, 0
	end
	if now - record.ReleasedAt < m.Delay then
		return false, 0
	end
	local position = positionOf(record)
	if not finiteVector(position) or not finiteVector(rootPos) then
		return false, 0
	end
	local dx, dz = rootPos.X - position.X, rootPos.Z - position.Z
	local flat = math.sqrt(dx * dx + dz * dz)
	-- hysteresis: a pull starts beyond StartDistance and goes on down to StopDistance
	local near = if pulling[record] then m.StopDistance else m.StartDistance
	if not (flat <= radius) or flat <= near or math.abs(rootPos.Y - position.Y) > m.MaxRise then
		return false, flat
	end
	if not plausible(record, now, position) or ItemService.onBase(position) then
		return false, flat
	end
	return true, flat
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

-- A living character's root part (nil when dead or not spawned).
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

type Wanted = { Record: ItemRecord, Flat: number, Position: Vector3 }

-- One player's part of a magnet pass (see magnetStep).
local function magnetFor(player: Player, set: { [ItemRecord]: boolean }, root: BasePart, radius: number, now: number)
	local m = ItemService.Magnet
	local rootPos = root.Position
	if not finiteVector(rootPos) then
		for record in set do
			stopPull(record)
		end
		return
	end
	local wanted: { Wanted } = {}
	for record in set do
		local wants, flat = ItemService.magnetWants(record, rootPos, radius, now)
		if wants then
			table.insert(wanted, { Record = record, Flat = flat, Position = positionOf(record) })
		elseif pulling[record] then
			stopPull(record)
			-- it reached your feet: fetched, not pulled again until picked up
			if record.State == "Loose" and flat > 0 and flat <= m.StopDistance then
				record.MagnetDone = true
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.Flat < b.Flat
	end)
	local zones = zonesNear(rootPos, radius)
	local pulled, rays = 0, 0
	for _, entry in wanted do
		local record = entry.Record
		local was = pulling[record] == true
		local blocked = record.BlockedUntil
		if pulled >= m.MaxPulls then
			stopPull(record)
		elseif #zones > 0 and ItemService.wayNearZone(entry.Position, rootPos, zones) then
			-- never push ore into a sale or a hopper
			stopPull(record)
		elseif not was and blocked and now < blocked then
			-- a wall was in the way a moment ago: not tried again yet
		else
			local checked = record.PullCheckedAt
			local due = not was or not checked or now - checked >= m.CheckEvery
			if due and rays >= m.RayBudget then
				-- no rays left this pass: a pull goes on and is checked next time
				if was then
					pullToward(record, rootPos, entry.Flat)
					pulled += 1
				end
			elseif due then
				rays += 1
				if clearPath(rootPos, entry.Position + Vector3.new(0, 0.5, 0), player.Character) then
					record.BlockedUntil = nil
					pullToward(record, rootPos, entry.Flat)
					record.PullCheckedAt = now
					pulled += 1
				else
					record.BlockedUntil = now + m.CheckEvery
					stopPull(record)
				end
			else
				pullToward(record, rootPos, entry.Flat)
				pulled += 1
			end
		end
	end
end

--[[
	One magnet pass (every 0.25 s from start; `now` = os.clock()): for each
	player with a magnet, the nearest wanted items (magnetWants) whose way
	is clear (no wall: line of sight; no intake zone) slide toward them, at
	most Magnet.MaxPulls; every other pull lets go. Only that player's own
	items are looked at. Each player's part runs on its own (an error in one
	never stops the others).
]]
function ItemService.magnetStep(now: number)
	local active: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			local set = byOwner[player.UserId]
			local root = if set then aliveRoot(player) else nil
			local radius = if root then magnetRadiusOf(player) else 0
			if set and root and radius > 0 then
				active[player.UserId] = true
				magnetFor(player, set, root, radius, now)
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
	maintain = maintainOne,
	-- forget every item record (the models are left alone)
	reset = function()
		table.clear(records)
		table.clear(byId)
		table.clear(byOwner)
		table.clear(lastCapToast)
		table.clear(pulling)
		table.clear(avoidParts)
		magnetRadiusOf = defaultMagnetRadius
		clearPath = defaultClearPath
	end,
	-- the magnet's radius per player and its line-of-sight check (nil = the real one)
	setMagnet = function(radius: ((Player) -> number)?, path: ((Vector3, Vector3, Model?) -> boolean)?)
		magnetRadiusOf = radius or defaultMagnetRadius
		clearPath = path or defaultClearPath
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

	-- Leaving players: keep their items in the Ore Pen.
	DataService.beforeRelease(function(player)
		for _, record in ItemService.ownedBy(player.UserId) do
			if record.State == "Loose" or record.State == "Carried" then
				ItemService.stash(record, nil)
			end
		end
		lastCapToast[player.UserId] = nil
	end)
end

function ItemService.start()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for _, record in records do
			local ok, err = pcall(function()
				maintainOne(record, now)
			end)
			if not ok then
				warn("[ItemService] maintenance error: " .. tostring(err))
			end
		end
		-- the Ore Magnet (gear): own loose items slide to their owner
		local magnetOk, magnetErr = pcall(function()
			ItemService.magnetStep(now)
		end)
		if not magnetOk then
			warn("[ItemService] magnet error: " .. tostring(magnetErr))
		end
	end
end

return ItemService
