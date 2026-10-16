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
]]

local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
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
}

local records: { [Model]: ItemRecord } = {}
local byId: { [string]: ItemRecord } = {}
-- owner UserId -> their records, so per-player counts don't walk every item
local byOwner: { [number]: { [ItemRecord]: boolean } } = {}
local folder: Folder
local lastCapToast: { [number]: number } = {}

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
	Puts an item descriptor into the player's Ore Pen (data.Storage), or
	pays its full value (Tobin's price) when the pen is full, so nothing is
	ever lost. 'Lost' only when the player's data isn't loaded or the
	descriptor is junk. With a reason, the player gets a toast.
	(Players filling the pen by hand are refused when it is full: PenService.)
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
	if #data.Storage < ItemService.penCapacity(data) then
		table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		result = "Stored"
		DataService.changed(player)
	else
		-- pen full: pay the full value instead of losing the item
		value = ItemData.value(desc.K, desc.O, desc.G, desc.R)
		EconomyService.award(player, value, "PenFull")
		result = "Sold"
	end
	if reason and player.Parent then
		Net.fire("Notify", player, {
			Text = if result == "Stored"
				then reason .. " (moved to your Ore Pen)"
				else `{reason} (Ore Pen full: sold it for {Format.money(value)})`,
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

--[[
	Can a machine believe where this item is? Always, while the server
	simulates it. While the owner's client does, the owner must be close
	(AntiTeleportRange) and the item can't have travelled further since its
	release than MaxItemSpeed allows (plus PlausibleSlack). `now` = os.clock().
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
	return flat <= math.max(0, now - record.ReleasedAt) * GameConfig.MaxItemSpeed + GameConfig.PlausibleSlack
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
	local cf = rescueCFrame(record.Owner)
	if cf then
		record.Body.AssemblyLinearVelocity = Vector3.zero
		ItemService.release(record, cf)
	else
		ItemService.stash(record, nil)
	end
end

local function maintainOne(record: ItemRecord, now: number)
	if not record.Model.Parent or not record.Body.Parent then
		-- destroyed by the engine (fell below FallenPartsDestroyHeight): keep it in the pen
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
	if position.Y < GameConfig.ItemFallKillY then
		rescue(record)
		return
	end
	if record.ClientOwnedUntil and now > record.ClientOwnedUntil then
		record.ClientOwnedUntil = nil
		setNetworkOwner(record, nil)
		-- a client moved it implausibly far while it simulated it: put it back
		if (position - record.ReleasePos).Magnitude > GameConfig.MaxItemTravel then
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

-- Internals for the Lune tests only (tests/ItemService.spec.luau).
ItemService._test = {
	maintain = maintainOne,
	-- forget every item record (the models are left alone)
	reset = function()
		table.clear(records)
		table.clear(byId)
		table.clear(byOwner)
		table.clear(lastCapToast)
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
	end
end

return ItemService
