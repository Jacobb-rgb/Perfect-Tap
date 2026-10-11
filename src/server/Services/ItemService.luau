--[[
	ItemService: every physical item (ore chunks, ingots, gear) in the world.

	- Items are Models in Workspace.Items with a single colliding Body part.
	- The server keeps the truth in `records`; attributes on the model are
	  only for clients (they can't change them).
	- Ownership: every item belongs to one player (Owner = UserId). Only the
	  owner can pick it up, and selling always pays the owner, so stealing
	  or griefing other players' items gains nothing.
	- Performance: max GameConfig.MaxLooseItemsPerPlayer loose items per
	  player; when exceeded the oldest one is moved into storage (data), so
	  nothing is ever lost. Items at rest for a while are anchored ("asleep").
	- Physics: network owner = the item's owner while loose (smooth throws).
	- Leaving players: loose and carried items go into storage.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)

local ItemService = {}

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
	CreatedAt: number,
	RestingSince: number?,
	Sleeping: boolean,
}

local records: { [Model]: ItemRecord } = {}
local byId: { [string]: ItemRecord } = {}
local folder: Folder

local function ownerPlayer(record: ItemRecord): Player?
	return Players:GetPlayerByUserId(record.Owner)
end

local function setNetworkOwner(record: ItemRecord, player: Player?)
	local body = record.Body
	if body.Anchored or not body:IsDescendantOf(Workspace) then
		return
	end
	pcall(function()
		if body:CanSetNetworkOwnership() then
			body:SetNetworkOwner(player)
		end
	end)
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
	m:SetAttribute("Value", ItemData.value(record.Kind, record.OreId, record.Grade, record.Recipe))
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
	record.RestingSince = nil
	if record.Model.Parent then
		record.Model:SetAttribute("State", state)
	end
end

function ItemService.wake(record: ItemRecord)
	if record.Sleeping then
		record.Sleeping = false
		record.Body.Anchored = false
		record.Model:SetAttribute("Sleeping", nil)
	end
	record.RestingSince = nil
end

function ItemService.looseCount(userId: number): number
	local count = 0
	for _, record in records do
		if record.Owner == userId and record.State == "Loose" then
			count += 1
		end
	end
	return count
end

-- Moves an item into the owner's storage data (or sells it if storage is full).
-- Returns true when the item was kept (stored).
function ItemService.stash(record: ItemRecord, reason: string?): boolean
	local player = ownerPlayer(record)
	local data = player and DataService.get(player)
	local stored = false
	if data and #data.Storage < GameConfig.MaxStoredItems then
		table.insert(data.Storage, {
			K = record.Kind,
			O = record.OreId,
			G = record.Grade,
			R = record.Recipe,
		})
		stored = true
	elseif data then
		-- storage full: pay the full value instead of losing the item
		local value = ItemData.value(record.Kind, record.OreId, record.Grade, record.Recipe)
		data.Coins += value
		data.TotalEarned += value
	end
	ItemService.destroy(record)
	if player and data then
		DataService.changed(player)
		if reason then
			Net.fire("Notify", player, {
				Text = if stored then reason .. " (moved to your Storage Crate)" else reason .. " (storage full: sold it)",
				Kind = "Info",
			})
		end
	end
	return stored
end

function ItemService.destroy(record: ItemRecord)
	record.State = "Consumed"
	records[record.Model] = nil
	byId[record.Id] = nil
	record.Model:Destroy()
end

local function enforceLooseLimit(userId: number)
	local loose = {}
	for _, record in records do
		if record.Owner == userId and record.State == "Loose" then
			table.insert(loose, record)
		end
	end
	if #loose <= GameConfig.MaxLooseItemsPerPlayer then
		return
	end
	table.sort(loose, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	for i = 1, #loose - GameConfig.MaxLooseItemsPerPlayer do
		ItemService.stash(loose[i], if i == 1 then "Too many loose items" else nil)
	end
end

--[[
	Spawns a physical item.
	info = { Kind, OreId, Grade?, Recipe? }, owner = UserId.
]]
function ItemService.spawn(info: ItemBuilder.ItemInfo, owner: number, cf: CFrame, velocity: Vector3?): ItemRecord?
	if not OreData.exists(info.OreId) or not ItemData.Kinds[info.Kind] then
		warn("[ItemService] bad item info", info.Kind, info.OreId)
		return nil
	end
	local id = HttpService:GenerateGUID(false)
	local model = ItemBuilder.build(info, cf, id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("Item")
	local body = model.PrimaryPart :: BasePart
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
		CreatedAt = os.clock(),
		RestingSince = nil,
		Sleeping = false,
	}
	records[model] = record
	byId[id] = record
	syncAttributes(record)
	model.Parent = folder
	if velocity then
		body.AssemblyLinearVelocity = velocity
		body.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
	end
	setNetworkOwner(record, Players:GetPlayerByUserId(owner))
	enforceLooseLimit(owner)
	return record
end

-- Re-creates an item from storage data next to a position.
function ItemService.spawnFromStorage(entry: { [string]: any }, owner: number, cf: CFrame): ItemRecord?
	return ItemService.spawn({ Kind = entry.K, OreId = entry.O, Grade = entry.G, Recipe = entry.R }, owner, cf)
end

-- Makes an item loose again at a CFrame (after being carried or ejected by a machine).
function ItemService.release(record: ItemRecord, cf: CFrame, velocity: Vector3?)
	ItemService.wake(record)
	local model = record.Model
	model:PivotTo(cf)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = d ~= record.Body
			d.CanCollide = d == record.Body
		end
	end
	record.Body.Anchored = false
	ItemService.setState(record, "Loose")
	if velocity then
		record.Body.AssemblyLinearVelocity = velocity
	end
	setNetworkOwner(record, ownerPlayer(record))
	enforceLooseLimit(record.Owner)
end

-- All items (any state) owned by a user.
function ItemService.ownedBy(userId: number): { ItemRecord }
	local list = {}
	for _, record in records do
		if record.Owner == userId then
			table.insert(list, record)
		end
	end
	return list
end

local function plotRescueCFrame(userId: number): CFrame?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.CFrame * CFrame.new(0, 2, -4)
	end
	return nil
end

-- Sleep resting items, rescue fallen ones. Runs ~twice a second.
local function maintenance()
	local now = os.clock()
	for _, record in records do
		if record.State == "Loose" and not record.Sleeping then
			local body = record.Body
			if body.Position.Y < GameConfig.ItemFallKillY then
				local rescue = plotRescueCFrame(record.Owner)
				if rescue then
					ItemService.release(record, rescue)
				else
					ItemService.stash(record, nil)
				end
			elseif body.AssemblyLinearVelocity.Magnitude < GameConfig.ItemSleepSpeed and not record.Model:GetAttribute("OnConveyor") then
				if not record.RestingSince then
					record.RestingSince = now
				elseif now - record.RestingSince > GameConfig.ItemSleepAfter then
					record.Sleeping = true
					body.Anchored = true
					record.Model:SetAttribute("Sleeping", true)
				end
			else
				record.RestingSince = nil
			end
		end
	end
end

function ItemService.init()
	folder = Workspace:FindFirstChild("Items") :: Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Items"
		f.Parent = Workspace
		folder = f
	end

	-- Leaving players: keep their items in storage (carried items are
	-- released by CarryService first, which also registers beforeRelease).
	DataService.beforeRelease(function(player)
		for _, record in ItemService.ownedBy(player.UserId) do
			if record.State == "Loose" or record.State == "Carried" then
				ItemService.stash(record, nil)
			end
		end
	end)
end

function ItemService.start()
	while true do
		task.wait(0.5)
		maintenance()
	end
end

return ItemService
