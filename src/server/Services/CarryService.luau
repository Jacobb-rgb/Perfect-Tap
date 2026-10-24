--[[
	CarryService: pick up, carry (stacked in front of you), drop and throw
	physical items: no magic inventory for raw ore.

	Validation: the item exists, is loose, belongs to the player, is within
	reach, and the player has free carry capacity. Throw direction and power
	from the client are clamped.

	Carried items are welded to the HumanoidRootPart (massless, no collision),
	so the character owns their physics.

	Walk speed: this service is the ONLY writer of Humanoid.WalkSpeed. It is
	HoverboardData.walkSpeed, the one formula for walking and riding: on foot
	it equals Bonuses.carryWalkSpeed (Boots, Swift and WalkSpeed golems minus
	a capped slowdown per carried item, GearConfig); on a board (the
	character's HoverboardData.Attribute, set by HoverboardService, which
	calls updateWalkSpeed when it changes) the board's speed with the percent
	bonuses (Robux boards ignore the carry slowdown). It is set again on every pickup
	or drop, on spawn, after every save change (DataService.onChanged: a gear
	buy, a golem equipped...) and whenever refreshWalkSpeed(player) is called.

	Bonuses (src/server/Bonuses.luau) also give: the carry capacity
	(Bonuses.carryCapacity: the Backpack gear, any later provider, doubled by
	StrongBack; the only source, StateService shows the same), the pickup
	range (Gloves: Bonuses.pickupRange, plus PICKUP_SLACK for lag) and the
	throw power (Gloves: x Bonuses.throwMult). The player attributes
	CarryCount, CarryCapacity and PickupRange mirror them for the client
	(InteractController's highlight uses PickupRange). Beyond the base reach
	(GearConfig Gloves level 0) a grab needs a clear line from the root to
	the item (hasReach): long Gloves never reach through a wall, a floor or
	into the next mine floor.

	Gear (GearService buys it): every effect is read from the bonuses when
	it acts, so a buy works at once and after a respawn (hookCharacter sets
	the walk speed and the attributes again). An item dropped or thrown by
	hand is marked HandDropped: the Ore Magnet (ItemService) never pulls
	it back to you; picking it up again clears the mark. A Gloves throw
	may be faster than GameConfig.MaxItemSpeed: ItemService.allowSpeed
	lets the anti-teleport checks accept that one release. The Ore Magnet
	puts what it fetched into your hands: init gives ItemService the
	hands' free room and a quiet pickup (ItemService.setMagnetHands).

	The carried stack (stackOffset, Stack) stays the same size whatever the
	capacity: 6 in front of the chest (below the chin, so the view and the
	aim stay free), 6 on the back, every further item joins the back
	bundle (24 with Backpack V and Strong Back).

	Looks (docs/SERVER_PERF_AUDIT.md #3): belt items wear a light look; a
	pickup puts on the full one (ItemService.dress) before the weld.
	Only records still "Carried" count (Security #11): list, takeTop and
	drops skip and forget anything else, and ItemService tells this service
	when it consumes a carried record (onCarriedConsumed).
	Drops and throws add at most CharacterSpeedCap studs/s of the
	character's own (client-simulated) speed (Security #8).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GearConfig = require(Shared.Config.GearConfig)
local HoverboardData = require(Shared.Config.HoverboardData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)

local CarryService = {}

-- studs of lag slack on top of the pickup range the client checks
local PICKUP_SLACK = 2
-- the most of the character's own speed a drop or throw passes on (studs/s):
-- the character's physics belong to its client (Security #8)
CarryService.CharacterSpeedCap = 30
-- everyone's reach without Gloves: further grabs need a clear line (hasReach)
local BASE_REACH = GearConfig.value("Gloves", 0)

local carried: { [Player]: { ItemService.ItemRecord } } = {}
local pickupCallbacks: { (Player, ItemService.ItemRecord) -> () } = {}

function CarryService.onPickup(callback: (Player, ItemService.ItemRecord) -> ())
	table.insert(pickupCallbacks, callback)
end

-- Items the player can carry: Bonuses.carryCapacity (the Backpack gear line,
-- the old CarryLevel folded into it by Migrations, and any later provider),
-- doubled by StrongBack.
function CarryService.capacity(player: Player): number
	return Bonuses.carryCapacity(Bonuses.stats(player), player)
end

-- Studs the player can grab an item from (Gloves; the server allows PICKUP_SLACK more).
function CarryService.pickupRange(player: Player): number
	return Bonuses.pickupRange(Bonuses.stats(player))
end

-- Forgets every record in the hands' list that isn't "Carried" any more
-- (consumed, released...). Returns the list (nil = carries nothing).
local function prune(player: Player): { ItemService.ItemRecord }?
	local list = carried[player]
	if not list then
		return nil
	end
	for i = #list, 1, -1 do
		if list[i].State ~= "Carried" then
			table.remove(list, i)
		end
	end
	return list
end

function CarryService.list(player: Player): { ItemService.ItemRecord }
	return prune(player) or {}
end

-- The character's own velocity, at most CharacterSpeedCap long (zero when broken).
local function characterVelocity(root: BasePart): Vector3
	local v = root.AssemblyLinearVelocity
	local length = v.Magnitude
	if length ~= length or length == math.huge then
		return Vector3.zero
	end
	local cap = CarryService.CharacterSpeedCap
	return if length > cap then v.Unit * cap else v
end
CarryService.characterVelocity = characterVelocity

--[[
	Where the index-th carried item sits (root space). A big backpack
	(Backpack V with Strong Back: 24 items) must not build a tower that
	clips through tunnel ceilings or hides the view, so the stack is
	bounded whatever the count:
	  front  Stack.FrontColumns x Stack.FrontRows in front of the chest
	         (the first item in the middle), two rows that stay below the
	         chin, so the view over the shoulder and the aim stay free
	  back   Stack.BackColumns x Stack.BackRows as a bundle on the back,
	         below the shoulders; every further item joins that bundle
	         (a little further out and turned, the same slots again), so
	         it gets fuller, never taller.
]]
CarryService.Stack = {
	FrontColumns = 3,
	FrontRows = 2,
	BackColumns = 3,
	BackRows = 2,
	FrontZ = -2.1,
	BackZ = 1.6,
	ColumnStep = 1.3,
	RowStep = 1.12,
	FrontY = 0.2,
	BackY = -0.3,
}

-- the columns from the middle out
local COLUMN_ORDER = { 0, -1, 1, -2, 2 }

function CarryService.stackOffset(index: number): CFrame
	local stack = CarryService.Stack
	local i = math.max(0, math.floor(index) - 1)
	local front = stack.FrontColumns * stack.FrontRows
	if i < front then
		local column = COLUMN_ORDER[i % stack.FrontColumns + 1] or 0
		local row = math.floor(i / stack.FrontColumns)
		return CFrame.new(column * stack.ColumnStep, stack.FrontY + row * stack.RowStep, stack.FrontZ)
	end
	local j = i - front
	local slots = stack.BackColumns * stack.BackRows
	local layer = math.floor(j / slots)
	local k = j % slots
	local column = COLUMN_ORDER[k % stack.BackColumns + 1] or 0
	local row = math.floor(k / stack.BackColumns)
	local out = (layer % 3) * 0.3
	return CFrame.new(column * (stack.ColumnStep - 0.1), stack.BackY + row * (stack.RowStep - 0.07), stack.BackZ + out)
		* CFrame.Angles(0, layer * 0.6, 0)
end
local stackOffset = CarryService.stackOffset

-- Sets the Humanoid's WalkSpeed from the carried items and the board being ridden
-- (HoverboardData.walkSpeed: one formula for walking and riding).
local function updateWalkSpeed(player: Player)
	local count = #(carried[player] or {})
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
		local speed = HoverboardData.walkSpeed(board, count, Bonuses.walkSpeed(stats), stats.WalkSpeedPct)
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
	end
	player:SetAttribute("CarryCount", count)
	player:SetAttribute("CarryCapacity", CarryService.capacity(player))
	player:SetAttribute("PickupRange", CarryService.pickupRange(player))
end

-- Sets the player's walk speed (and carry attributes) from their bonuses now.
-- The gear / golem / enchant packages call it after a change (a save change
-- does it too, see the header).
function CarryService.refreshWalkSpeed(player: Player)
	updateWalkSpeed(player)
end

CarryService.updateWalkSpeed = updateWalkSpeed

local function attach(player: Player, root: BasePart, record: ItemService.ItemRecord, index: number)
	-- in the hands an item wears its full look (a belt item was light)
	ItemService.dress(record, false)
	local model = record.Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	model:PivotTo(root.CFrame * stackOffset(index))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = record.Body
	weld.Parent = record.Body
	ItemService.setState(record, "Carried")
	model:SetAttribute("CarriedBy", player.UserId)
end

local function detach(record: ItemService.ItemRecord)
	local weld = record.Body:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	record.Model:SetAttribute("CarriedBy", nil)
	for _, d in record.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = d == record.Body
		end
	end
end

-- Removes the top carried item without releasing it (for machines/selling).
function CarryService.takeTop(player: Player, predicate: ((ItemService.ItemRecord) -> boolean)?): ItemService.ItemRecord?
	-- only items still in the hands (never a consumed one: Security #11)
	local list = prune(player)
	if not list then
		return nil
	end
	for i = #list, 1, -1 do
		local record = list[i]
		if record.State == "Carried" and (not predicate or predicate(record)) then
			table.remove(list, i)
			detach(record)
			updateWalkSpeed(player)
			return record
		end
	end
	return nil
end

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

-- How many more items the player's hands take right now.
function CarryService.room(player: Player): number
	return math.max(0, CarryService.capacity(player) - #(carried[player] or {}))
end

function CarryService.pickup(player: Player, record: ItemService.ItemRecord): boolean
	local root = Guard.rootPart(player)
	if not root or not DataService.get(player) then
		return false
	end
	if record.Owner ~= player.UserId or record.State ~= "Loose" then
		return false
	end
	-- a dropper's Drop rides the belts only (DropperConfig): never in your hands
	if record.Kind == "Drop" then
		return false
	end
	if not CarryService.hasReach(player, root, record) then
		return false
	end
	local list = carried[player]
	if not list then
		list = {}
		carried[player] = list
	end
	if #list >= CarryService.capacity(player) then
		Net.fire("Notify", player, { Text = "Your hands are full! A bigger Ore Backpack from the SHOP holds more.", Kind = "Deny" })
		return false
	end
	table.insert(list, record)
	attach(player, root, record, #list)
	updateWalkSpeed(player)
	-- dirty ore keeps its secret: no ore color for raw chunks (design v2)
	Net.fire("Fx", player, "Pickup", record.Body.CFrame.Position, if record.Kind == "Raw" then nil else record.OreId)
	for _, callback in pickupCallbacks do
		task.spawn(callback, player, record)
	end
	return true
end

-- Where a dropped item appears: 3 studs ahead, but never inside/behind a wall.
local function dropCFrame(player: Player, root: BasePart): CFrame
	local origin = root.Position + Vector3.new(0, 0.8, 0)
	local ahead = root.CFrame.LookVector * 3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { Workspace:FindFirstChild("Items") :: Instance }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(origin, ahead, params)
	local position = if hit then hit.Position - root.CFrame.LookVector * 1.2 else origin + ahead
	return CFrame.new(position)
end
local dropSpot: (Player, BasePart) -> CFrame = dropCFrame

CarryService.TooManyText = "Too many of your items lie around: pick some up first."
CarryService.TooManyToastGap = 3 -- seconds between two of those toasts
local tooManyToastAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function dropTop(player: Player, velocity: Vector3?): ItemService.ItemRecord?
	local root = Guard.rootPart(player)
	local list = prune(player)
	if not root or not list or #list == 0 then
		return nil
	end
	-- the hard ceiling of loose items (GameConfig.MaxLooseItemsTotal): nobody
	-- pours a whole pen onto the map
	if ItemService.atTotalCap(player.UserId) then
		local now = os.clock()
		if now - (tooManyToastAt[player] or -math.huge) >= CarryService.TooManyToastGap then
			tooManyToastAt[player] = now
			Net.fire("Notify", player, { Text = CarryService.TooManyText, Kind = "Deny" })
		end
		return nil
	end
	local record = table.remove(list) :: ItemService.ItemRecord
	detach(record)
	ItemService.release(record, dropSpot(player, root), velocity or (characterVelocity(root) + root.CFrame.LookVector * 4))
	-- put down on purpose: the Ore Magnet leaves it alone until it is picked up again
	record.HandDropped = true
	updateWalkSpeed(player)
	return record
end

-- Drops everything (death, leaving, teleport).
function CarryService.dropAll(player: Player)
	local list = carried[player]
	carried[player] = nil
	if not list then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for i, record in list do
		if record.State == "Carried" then
			detach(record)
			-- at the hard ceiling of loose items they go into the pen instead
			if root and not ItemService.atTotalCap(player.UserId) then
				ItemService.release(record, root.CFrame * CFrame.new((i % 3 - 1) * 1.5, 1 + math.floor(i / 3), -2))
			else
				ItemService.stash(record, nil)
			end
		end
	end
	updateWalkSpeed(player)
end

local function onPickup(player: Player, target: any)
	local model = Guard.instance(target, "Model", Workspace:FindFirstChild("Items"))
	local record = model and ItemService.get(model)
	if record then
		CarryService.pickup(player, record)
	end
end

local function onDrop(player: Player)
	dropTop(player, nil)
end

local function onThrow(player: Player, direction: any, power: any)
	local dir = Guard.unitVector(direction)
	local charge = Guard.number(power, 0, 1)
	local root = Guard.rootPart(player)
	if not dir or not charge or not root then
		return
	end
	-- no throwing straight down through the floor or straight up
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.2 then
		flat = root.CFrame.LookVector
	end
	local pitch = math.clamp(dir.Y, -0.3, 0.85)
	local throwDir = (flat.Unit * math.sqrt(1 - pitch * pitch) + Vector3.new(0, pitch, 0)).Unit
	local stats = Bonuses.stats(player)
	local speed = (GameConfig.ThrowSpeedMin + (GameConfig.ThrowSpeedMax - GameConfig.ThrowSpeedMin) * charge) * Bonuses.throwMult(stats)
	local velocity = throwDir * speed + Vector3.new(0, 8, 0) + characterVelocity(root) * 0.5
	local record = dropTop(player, velocity)
	if record then
		-- Grip Gloves throw harder than GameConfig.MaxItemSpeed allows: this
		-- release may fly as fast as the throw plus half a legal run (the
		-- anti-teleport checks still hold a spoofed run speed to that)
		ItemService.allowSpeed(record, speed + 0.5 * Bonuses.walkSpeed(stats))
		Net.fireNear("Fx", root.Position, 80, nil, "Throw", root.Position)
	end
end

-- The Ore Magnet's catch: an item that flew to the player's feet goes into
-- their hands when they have room (quietly: no "hands full" toast).
function CarryService.magnetCatch(player: Player, record: ItemService.ItemRecord): boolean
	if CarryService.room(player) <= 0 then
		return false
	end
	return CarryService.pickup(player, record)
end

-- A carried record was consumed (ItemService.onCarriedConsumed): it leaves
-- its owner's hands' list, so nothing can take, clean or drop it again.
function CarryService.forget(record: ItemService.ItemRecord)
	local player = Players:GetPlayerByUserId(record.Owner)
	local list = player and carried[player]
	if not player or not list then
		return
	end
	local index = table.find(list, record)
	if index then
		table.remove(list, index)
		updateWalkSpeed(player)
	end
end

-- Internals for the Lune tests only (tests/GearService.spec.luau).
CarryService._test = {
	-- the line-of-sight check of long grabs (nil = the real raycast)
	setReach = function(check: ((Player, Vector3, ItemService.ItemRecord) -> boolean)?)
		reachClear = check or defaultReachClear
	end,
	-- where a drop appears (nil = the real raycast; the tests' world has nothing to hit)
	setDropSpot = function(spot: ((Player, BasePart) -> CFrame)?)
		dropSpot = spot or dropCFrame
	end,
	drop = onDrop,
	throw = onThrow,
}

function CarryService.init()
	Net.on("CarryPickup", onPickup)
	Net.on("CarryDrop", onDrop)
	Net.on("CarryThrow", onThrow)
	-- the Ore Magnet puts what it fetched into your hands
	ItemService.setMagnetHands(CarryService.room, CarryService.magnetCatch)
	-- a carried item consumed elsewhere (the engine destroyed it) leaves the hands
	ItemService.onCarriedConsumed(CarryService.forget)

	local function hookCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				CarryService.dropAll(player)
			end)
		end
		updateWalkSpeed(player)
	end
	local function setupPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			CarryService.dropAll(player)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	-- leaving: carried items become part of storage (ItemService stashes them)
	DataService.beforeRelease(function(player)
		carried[player] = nil
	end)
	DataService.onLoaded(function(player)
		updateWalkSpeed(player)
	end)
	-- gear, golems, enchants live in the save: a change may change the speed
	DataService.onChanged(function(player)
		Bonuses.invalidate(player)
		if player.Parent then
			updateWalkSpeed(player)
		end
	end)
end

return CarryService
