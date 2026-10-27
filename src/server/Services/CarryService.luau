--[[
	CarryService: the backpack (owner 2026-10-24: "everything into the
	backpack", docs/plans/OWNER_PLAYTEST_1024.md "4 + 5"). Nothing is
	carried in the hands any more: what you pick up goes into
	data.BackpackItems ({ [ItemData.storageKey] = whole count }) while it
	has room, and the services take it from there: the train, the Ore Pen,
	Tobin, the podiums, a machine's Put In, the Cleaning Station.

	Capacity: Bonuses.carryCapacity (the equipped pack's BackpackData
	capacity through Bonuses' "Backpack" source, the CarryCapacity bonuses
	on top, doubled by the StrongBack perk; StateService shows the same).
	The packs themselves (owned, equipped, the BACKPACKS shop) are
	BackpackService's. A smaller pack can hold more than it takes (the
	contents stay): nothing new goes in until it is under.

	Picking up (pickup): your own loose item (never a dropper's Drop) within
	reach (hasReach: Gloves' pickup range plus PICKUP_SLACK for lag; beyond
	the base reach only with a clear line, never through a wall or a floor)
	goes into the backpack (ItemService.absorb: the item leaves the world).
	Net CarryPickup (the client's F / tap) does it at once; the auto-pickup
	loop (owner: "by itself when you walk near") does it every AutoSeconds
	for every item of yours in reach: only your own loose items (at most
	GameConfig.MaxLooseItemsPerPlayer each), never a scan of the world, and
	never on a base (ItemService.onBase, like the magnet: belts, chutes,
	machine queues and the pen's gate work with loose items; F / tap still
	takes one there). A
	full backpack says so, at most every FullToastGap seconds, and only when
	something of yours lies in reach. The Ore Magnet puts what it fetched
	into the backpack too (ItemService.setMagnetHands). Nothing is dropped
	or thrown any more, and the backpack is saved: death, leaving and
	teleports keep it.

	The backpack's contents (no yield between taking and using them: the
	save is one table):
	  countOf(data) / count(player)     items inside
	  room(player)                      how many more it takes (0 when full)
	  stacks(player)                    { { Key, Desc, Count } } sorted by key
	  has(player, predicate)            any item matching (predicate: Desc -> boolean)
	  take(player, predicate, max?)     -> { Desc } taken, at most `max` (default all)
	  add(player, desc, count?, force?) -> how many went in (force: past the capacity)
	A change pushes the State (DataService.changed); the player attributes
	CarryCount (items inside), CarryCapacity and PickupRange mirror them for
	the client.

	Walk speed: this service is the ONLY writer of Humanoid.WalkSpeed. It is
	HoverboardData.walkSpeed, the one formula for walking and riding: on foot
	Bonuses.walkSpeed (Boots, Swift and WalkSpeed golems; a full backpack
	slows nobody down); on a board (the character's HoverboardData.Attribute,
	set by HoverboardService, which calls updateWalkSpeed when it changes)
	the board's speed with the percent bonuses. It is set again on spawn,
	after every save change (DataService.onChanged: a gear buy, a golem
	equipped...) and whenever refreshWalkSpeed(player) is called.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.GearConfig)
local HoverboardData = require(Shared.Config.HoverboardData)
local ItemData = require(Shared.Config.ItemData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)

local CarryService = {}

export type Desc = ItemService.Desc
export type Stack = { Key: string, Desc: Desc, Count: number }

-- studs of lag slack on top of the pickup range the client checks
local PICKUP_SLACK = 2
-- everyone's reach without Gloves: further grabs need a clear line (hasReach)
local BASE_REACH = GearConfig.value("Gloves", 0)

CarryService.AutoSeconds = 0.25 -- the auto-pickup loop's period
CarryService.FullToastGap = 8 -- seconds between two "backpack full" toasts
CarryService.FullText = "Your backpack is full! Bigger backpacks are sold at the BACKPACKS shop."

local fullToastAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local pickupCallbacks: { (Player, Desc) -> () } = {}

-- Called after every pickup the player asked for (F / tap: the player, what went in):
-- LeaderboardService counts it as server-checked activity (its ActivitySources). The
-- auto-pickup and the magnet ("quiet") never call it: standing by a pile isn't playing.
function CarryService.onPickup(callback: (Player, Desc) -> ())
	table.insert(pickupCallbacks, callback)
end

---------------------------------------------------------------- capacity and contents

-- Items the backpack holds: Bonuses.carryCapacity (the equipped pack, the
-- CarryCapacity bonuses, doubled by StrongBack).
function CarryService.capacity(player: Player): number
	return Bonuses.carryCapacity(Bonuses.stats(player), player)
end

-- Studs the player can grab an item from (Gloves; the server allows PICKUP_SLACK more).
function CarryService.pickupRange(player: Player): number
	return Bonuses.pickupRange(Bonuses.stats(player))
end

-- The save's backpack record (a fresh one when it is missing or broken).
local function itemsOf(data: { [string]: any }): { [string]: number }
	local items = data.BackpackItems
	if type(items) ~= "table" then
		items = {}
		data.BackpackItems = items
	end
	return items
end

local function whole(v: any): number
	return if type(v) == "number" and v == v and v > 0 and v < math.huge then math.floor(v) else 0
end

-- Items in a save's backpack.
function CarryService.countOf(data: { [string]: any }?): number
	if not data or type(data.BackpackItems) ~= "table" then
		return 0
	end
	local total = 0
	for _, n in data.BackpackItems do
		total += whole(n)
	end
	return total
end

function CarryService.count(player: Player): number
	return CarryService.countOf(DataService.get(player))
end

-- How many more items the backpack takes right now (0 when full or over).
function CarryService.room(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return math.max(0, CarryService.capacity(player) - CarryService.countOf(data))
end

-- The backpack's stacks, sorted by key (the same order every time). Keys this
-- build can't read (a newer build's ore or grade) are skipped: they stay in the save.
function CarryService.stacks(player: Player): { Stack }
	local data = DataService.get(player)
	local list: { Stack } = {}
	if not data or type(data.BackpackItems) ~= "table" then
		return list
	end
	for key, n in data.BackpackItems do
		local count = whole(n)
		local desc = if type(key) == "string" and count > 0 then ItemData.parseStoredKey(key) else nil
		if desc then
			table.insert(list, { Key = key, Desc = desc, Count = count })
		end
	end
	table.sort(list, function(a: Stack, b: Stack): boolean
		return a.Key < b.Key
	end)
	return list
end

-- Does the backpack hold an item matching `predicate`?
function CarryService.has(player: Player, predicate: ((Desc) -> boolean)?): boolean
	for _, stack in CarryService.stacks(player) do
		if not predicate or predicate(stack.Desc) then
			return true
		end
	end
	return false
end

--[[
	Takes up to `max` items matching `predicate` out of the backpack (all of
	them without `max`), stack by stack in key order, and returns them (one
	desc per item). The caller uses them in the same step (no yield).
]]
function CarryService.take(player: Player, predicate: ((Desc) -> boolean)?, max: number?): { Desc }
	local taken: { Desc } = {}
	local data = DataService.get(player)
	if not data then
		return taken
	end
	local limit = if max then whole(max) else math.huge
	local items = itemsOf(data)
	for _, stack in CarryService.stacks(player) do
		if #taken >= limit then
			break
		end
		if not predicate or predicate(stack.Desc) then
			local n = math.min(stack.Count, limit - #taken)
			for _ = 1, n do
				table.insert(taken, { K = stack.Desc.K, O = stack.Desc.O, G = stack.Desc.G, R = stack.Desc.R })
			end
			local left = stack.Count - n
			if left > 0 then
				items[stack.Key] = left
			else
				items[stack.Key] = nil :: any
			end
		end
	end
	if #taken > 0 then
		player:SetAttribute("CarryCount", CarryService.countOf(data))
		DataService.changed(player)
	end
	return taken
end

--[[
	Puts `count` (default 1) of an item into the backpack while it has room
	(`force`: past the capacity, for things that must never be lost, like
	the ore you take back out of a vise). Returns how many went in.
]]
function CarryService.add(player: Player, desc: Desc, count: number?, force: boolean?): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local wanted = if count == nil then 1 else whole(count)
	local n = if force then wanted else math.min(wanted, CarryService.room(player))
	if n <= 0 then
		return 0
	end
	local items = itemsOf(data)
	local key = ItemData.storageKey(desc)
	items[key] = whole(items[key]) + n
	player:SetAttribute("CarryCount", CarryService.countOf(data))
	DataService.changed(player)
	return n
end

---------------------------------------------------------------- walk speed

-- Sets the Humanoid's WalkSpeed from the bonuses and the board being ridden
-- (HoverboardData.walkSpeed: one formula for walking and riding; the backpack
-- never slows anyone down), and the attributes the client reads.
local function updateWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid then
		local stats = Bonuses.stats(player)
		-- the board being ridden (HoverboardService's character attribute; nil on foot)
		local ok, board = pcall(function(): any
			return (character :: any):GetAttribute(HoverboardData.Attribute)
		end)
		if not ok then
			board = nil
		end
		local speed = HoverboardData.walkSpeed(board, 0, Bonuses.walkSpeed(stats), stats.WalkSpeedPct)
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
	end
	player:SetAttribute("CarryCount", CarryService.count(player))
	player:SetAttribute("CarryCapacity", CarryService.capacity(player))
	player:SetAttribute("PickupRange", CarryService.pickupRange(player))
end

-- Sets the player's walk speed (and the backpack attributes) from their bonuses now.
-- The gear / golem / enchant packages call it after a change (a save change
-- does it too, see the header).
function CarryService.refreshWalkSpeed(player: Player)
	updateWalkSpeed(player)
end

CarryService.updateWalkSpeed = updateWalkSpeed

---------------------------------------------------------------- picking up

local reachParams: RaycastParams? = nil

-- Nothing solid between the root and the item (items and your own character don't count).
local function defaultReachClear(player: Player, from: Vector3, record: ItemService.ItemRecord): boolean
	local params = reachParams
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.RespectCanCollide = true
		reachParams = made
		params = made
	end
	local p = params :: RaycastParams
	local ignore: { Instance } = {}
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(ignore, items)
	end
	if player.Character then
		table.insert(ignore, player.Character)
	end
	p.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, record.Body.CFrame.Position - from, p) == nil
end
local reachClear: (Player, Vector3, ItemService.ItemRecord) -> boolean = defaultReachClear

-- Can the player at `root` grab this item from where they stand? Within
-- the pickup range (+ PICKUP_SLACK); beyond the base reach (no Gloves)
-- only with a clear line, never through a wall or a floor.
function CarryService.hasReach(player: Player, root: BasePart, record: ItemService.ItemRecord): boolean
	-- (Body.CFrame.Position = Body.Position; the Lune tests can read it)
	local distance = (record.Body.CFrame.Position - root.Position).Magnitude
	if not (distance <= CarryService.pickupRange(player) + PICKUP_SLACK) then
		return false
	end
	return distance <= BASE_REACH + PICKUP_SLACK or reachClear(player, root.Position, record)
end

local function fullToast(player: Player)
	local now = os.clock()
	if now - (fullToastAt[player] or -math.huge) >= CarryService.FullToastGap then
		fullToastAt[player] = now
		Net.fire("Notify", player, { Text = CarryService.FullText, Kind = "Deny" })
	end
end

--[[
	Puts one of your own loose items into the backpack (see the header).
	`quiet`: no "full" toast (the auto-pickup and the magnet say it their way).
]]
function CarryService.pickup(player: Player, record: ItemService.ItemRecord, quiet: boolean?): boolean
	local root = Guard.rootPart(player)
	if not root or not DataService.get(player) then
		return false
	end
	if record.Owner ~= player.UserId or record.State ~= "Loose" then
		return false
	end
	-- a dropper's Drop rides the belts only (DropperConfig): never in the backpack
	if record.Kind == "Drop" then
		return false
	end
	if not CarryService.hasReach(player, root, record) then
		return false
	end
	if CarryService.room(player) <= 0 then
		if not quiet then
			fullToast(player)
		end
		return false
	end
	local at = record.Body.CFrame.Position
	local kind, oreId = record.Kind, record.OreId
	-- no yield between taking it out of the world and into the backpack
	local desc = ItemService.absorb(record)
	CarryService.add(player, desc, 1, true)
	-- dirty ore keeps its secret: no ore color for raw chunks (design v2)
	Net.fire("Fx", player, "Pickup", at, if kind == "Raw" then nil else oreId)
	if not quiet then
		for _, callback in pickupCallbacks do
			task.spawn(callback, player, desc)
		end
	end
	return true
end

-- One auto-pickup pass for a player: every item of theirs in reach and off
-- the bases goes in while there is room.
local function autoPickup(player: Player, now: number)
	local root = Guard.rootPart(player)
	if not root or not DataService.get(player) then
		return
	end
	local reach = CarryService.pickupRange(player) + PICKUP_SLACK
	local blocked = false
	for _, record in ItemService.ownedBy(player.UserId) do
		if record.State == "Loose" and record.Kind ~= "Drop" and ItemService.isTrusted(record, now) then
			-- the cheap distance first, then the base test, the ray (hasReach) last
			local at = record.Body.CFrame.Position
			local near = (at - root.Position).Magnitude <= reach
			if near and not ItemService.onBase(at) and CarryService.hasReach(player, root, record) then
				if CarryService.room(player) <= 0 then
					blocked = true
					break
				end
				CarryService.pickup(player, record, true)
			end
		end
	end
	if blocked then
		fullToast(player)
	end
end

local function onPickup(player: Player, target: any)
	local model = Guard.instance(target, "Model", Workspace:FindFirstChild("Items"))
	local record = model and ItemService.get(model)
	if record then
		CarryService.pickup(player, record)
	end
end

-- Internals for the Lune tests only (tests/CarryService.spec.luau, GearService.spec.luau).
CarryService._test = {
	-- the line-of-sight check of long grabs (nil = the real raycast)
	setReach = function(check: ((Player, Vector3, ItemService.ItemRecord) -> boolean)?)
		reachClear = check or defaultReachClear
	end,
	autoPickup = autoPickup,
	pickupRequest = onPickup,
	reset = function()
		table.clear(fullToastAt)
	end,
}

function CarryService.init()
	Net.on("CarryPickup", onPickup)
	-- the Ore Magnet puts what it fetched into the backpack (quietly: no "full" toast)
	ItemService.setMagnetHands(CarryService.room, function(player: Player, record: ItemService.ItemRecord): boolean
		return CarryService.pickup(player, record, true)
	end)

	local function hookCharacter(player: Player, _character: Model)
		updateWalkSpeed(player)
	end
	local function setupPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	DataService.onLoaded(function(player)
		updateWalkSpeed(player)
	end)
	-- gear, golems, enchants and the backpack live in the save: a change may change them
	DataService.onChanged(function(player)
		Bonuses.invalidate(player)
		if player.Parent then
			updateWalkSpeed(player)
		end
	end)
end

function CarryService.start()
	while true do
		task.wait(CarryService.AutoSeconds)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function()
				autoPickup(player, now)
			end)
			if not ok then
				warn(`[CarryService] auto-pickup for {player.Name} failed: {err}`)
			end
		end
	end
end

return CarryService
