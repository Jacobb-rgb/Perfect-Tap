--[[
	CarryService: pick up, carry (stacked in front of you), drop and throw
	physical items: no magic inventory for raw ore.

	Validation: the item exists, is loose, belongs to the player, is within
	reach, and the player has free carry capacity. Throw direction and power
	from the client are clamped.

	Carried items are welded to the HumanoidRootPart (massless, no collision),
	so the character owns their physics.

	Walk speed: this service is the ONLY writer of Humanoid.WalkSpeed. It is
	Bonuses.carryWalkSpeed (Boots, Swift and WalkSpeed golems minus a capped
	slowdown per carried item, GearConfig). It is set again on every pickup
	or drop, on spawn, after every save change (DataService.onChanged: a gear
	buy, a golem equipped...) and whenever refreshWalkSpeed(player) is called.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GearConfig = require(Shared.Config.GearConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)

local CarryService = {}

local carried: { [Player]: { ItemService.ItemRecord } } = {}
local pickupCallbacks: { (Player, ItemService.ItemRecord) -> () } = {}

function CarryService.onPickup(callback: (Player, ItemService.ItemRecord) -> ())
	table.insert(pickupCallbacks, callback)
end

-- Items the player can carry: the Backpack gear line (GearConfig; the old
-- CarryLevel was folded into it by Migrations), doubled by StrongBack.
function CarryService.capacity(player: Player): number
	local data = DataService.get(player)
	return GearConfig.carryCapacity(if data then data.Gear else nil, Perks.has(player, "StrongBack"))
end

function CarryService.list(player: Player): { ItemService.ItemRecord }
	return carried[player] or {}
end

local function stackOffset(index: number): CFrame
	-- two columns in front of the chest, rising up
	local column = (index - 1) % 2
	local row = math.floor((index - 1) / 2)
	return CFrame.new((column - 0.5) * 1.3, 0.2 + row * 1.15, -2.1)
end

local function updateWalkSpeed(player: Player)
	local count = #(carried[player] or {})
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speed = Bonuses.carryWalkSpeed(Bonuses.stats(player), count)
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
	end
	player:SetAttribute("CarryCount", count)
	player:SetAttribute("CarryCapacity", CarryService.capacity(player))
end

-- Sets the player's walk speed (and carry attributes) from their bonuses now.
-- The gear / golem / enchant packages call it after a change (a save change
-- does it too, see the header).
function CarryService.refreshWalkSpeed(player: Player)
	updateWalkSpeed(player)
end

local function attach(player: Player, root: BasePart, record: ItemService.ItemRecord, index: number)
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
	local list = carried[player]
	if not list then
		return nil
	end
	for i = #list, 1, -1 do
		local record = list[i]
		if not predicate or predicate(record) then
			table.remove(list, i)
			detach(record)
			updateWalkSpeed(player)
			return record
		end
	end
	return nil
end

function CarryService.pickup(player: Player, record: ItemService.ItemRecord): boolean
	local root = Guard.rootPart(player)
	if not root or not DataService.get(player) then
		return false
	end
	if record.Owner ~= player.UserId or record.State ~= "Loose" then
		return false
	end
	if (record.Body.Position - root.Position).Magnitude > GameConfig.PickupRange + 2 then
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
	Net.fire("Fx", player, "Pickup", record.Body.Position, if record.Kind == "Raw" then nil else record.OreId)
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

local function dropTop(player: Player, velocity: Vector3?)
	local root = Guard.rootPart(player)
	local list = carried[player]
	if not root or not list or #list == 0 then
		return
	end
	local record = table.remove(list) :: ItemService.ItemRecord
	detach(record)
	ItemService.release(record, dropCFrame(player, root), velocity or (root.AssemblyLinearVelocity + root.CFrame.LookVector * 4))
	updateWalkSpeed(player)
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
			if root then
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
	local speed = GameConfig.ThrowSpeedMin + (GameConfig.ThrowSpeedMax - GameConfig.ThrowSpeedMin) * charge
	local velocity = throwDir * speed + Vector3.new(0, 8, 0) + root.AssemblyLinearVelocity * 0.5
	dropTop(player, velocity)
	Net.fireNear("Fx", root.Position, 80, nil, "Throw", root.Position)
end

function CarryService.init()
	Net.on("CarryPickup", onPickup)
	Net.on("CarryDrop", onDrop)
	Net.on("CarryThrow", onThrow)

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
