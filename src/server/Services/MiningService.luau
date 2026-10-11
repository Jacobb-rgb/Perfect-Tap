--[[
	MiningService: ore nodes, pickaxe swings and chunk drops.

	- A node grows at every NodeSpawn marker (ore picked by the zone weights).
	- Swing validation: the node is real and alive, the player is close,
	  the swing cooldown of their pickaxe has passed, the pickaxe tier is high
	  enough, and VIP zones need the VIP pass.
	- Node HP falls in three visible stages: cracks (1), a chunk breaks off (2),
	  shatter (3). Each stage crossed drops one physical raw ore chunk owned by
	  the player who made the hit.
	- Shattered nodes regrow after the rarity's RespawnTime.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local ToolData = require(Shared.Config.ToolData)
local WorldLayout = require(Shared.Config.WorldLayout)
local OreNodeBuilder = require(Shared.Builders.OreNodeBuilder)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local WorldService = require(script.Parent.WorldService)
local Perks = require(script.Parent.Parent.Perks)

local MiningService = {}

type Node = {
	Model: Model,
	Marker: BasePart,
	Zone: string,
	OreId: string,
	Health: number,
	MaxHealth: number,
	Stage: number,
	Seed: number,
	Alive: boolean,
}

local nodes: { [Model]: Node } = {}
local lastSwing: { [Player]: number } = {}
local random = Random.new()
local nodesFolder: Folder

-- Listeners for other services (tutorial, badges, analytics).
local minedCallbacks: { (Player, string, number) -> () } = {}
function MiningService.onChunkMined(callback: (player: Player, oreId: string, count: number) -> ())
	table.insert(minedCallbacks, callback)
end

local function pickOre(zoneId: string): string?
	local zone = WorldLayout.ZoneById[zoneId]
	if not zone then
		return nil
	end
	local total = 0
	local keys = {}
	for oreId, weight in zone.Ores do
		if weight > 0 then
			total += weight
			table.insert(keys, oreId)
		end
	end
	table.sort(keys)
	local roll = random:NextNumber() * total
	for _, oreId in keys do
		roll -= zone.Ores[oreId]
		if roll <= 0 then
			return oreId
		end
	end
	return keys[#keys]
end

local function spawnNode(marker: BasePart)
	local zoneId = marker:GetAttribute("Zone") :: string?
	local oreId = zoneId and pickOre(zoneId)
	if not oreId or not zoneId then
		return
	end
	local ore = OreData.get(oreId)
	local seed = random:NextInteger(1, 1e9)
	local ground = marker.Position - Vector3.new(0, marker.Size.Y / 2, 0)
	local base = CFrame.new(ground) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local model = OreNodeBuilder.build(oreId, base, seed)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("OreNode")
	model:SetAttribute("Zone", zoneId)
	model:SetAttribute("Tier", ore.Tier)
	model:SetAttribute("Health", ore.Hardness)
	model:SetAttribute("MaxHealth", ore.Hardness)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Parent = nodesFolder
	nodes[model] = {
		Model = model,
		Marker = marker,
		Zone = zoneId,
		OreId = oreId,
		Health = ore.Hardness,
		MaxHealth = ore.Hardness,
		Stage = 0,
		Seed = seed,
		Alive = true,
	}
end

local function nodeRadius(node: Node): number
	local primary = node.Model.PrimaryPart
	return if primary then primary.Size.Magnitude / 2 else 3
end

local function dropChunks(player: Player, node: Node, count: number)
	local origin = (node.Model.PrimaryPart :: BasePart).Position + Vector3.new(0, 3, 0)
	for _ = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local cf = CFrame.new(origin + out * 1.5) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0)
		ItemService.spawn({ Kind = "Raw", OreId = node.OreId }, player.UserId, cf, out * random:NextNumber(7, 11) + Vector3.new(0, 16, 0))
	end
	local data = DataService.get(player)
	if data then
		data.Stats.OresMined += count
		local isNew = not data.Discovered[node.OreId]
		if isNew then
			data.Discovered[node.OreId] = true
			local ore = OreData.get(node.OreId)
			Net.fire("Notify", player, {
				Text = "New ore discovered: " .. ore.Name .. "!",
				Kind = "Discovery",
				Rarity = ore.Rarity,
			})
		end
		DataService.changed(player)
	end
	for _, callback in minedCallbacks do
		task.spawn(callback, player, node.OreId, count)
	end
end

-- Pieces that break off at stage 2 tumble away briefly, then vanish.
local function breakOff(parts: { BasePart }, away: Vector3)
	local debrisFolder = Workspace:FindFirstChild("Debris")
	for _, part in parts do
		part.Parent = debrisFolder
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.AssemblyLinearVelocity = away * 10 + Vector3.new(0, 14, 0)
		part.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-6, 6), random:NextNumber(-6, 6), random:NextNumber(-6, 6))
		task.delay(1.6, function()
			part:Destroy()
		end)
	end
end

local function shatter(node: Node)
	node.Alive = false
	nodes[node.Model] = nil
	local position = (node.Model.PrimaryPart :: BasePart).Position
	Net.fireNear("Fx", position, 180, nil, "NodeShatter", position, node.OreId)
	node.Model:Destroy()
	local rarity = Rarity.get(OreData.get(node.OreId).Rarity)
	task.delay(rarity.RespawnTime * random:NextNumber(0.85, 1.15), function()
		if node.Marker.Parent then
			spawnNode(node.Marker)
		end
	end)
end

local function onSwing(player: Player, target: any)
	local model = Guard.instance(target, "Model", nodesFolder) :: Model?
	local node = model and nodes[model]
	if not node or not node.Alive then
		return
	end
	local root = Guard.rootPart(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local tool = character:FindFirstChild("Pickaxe")
	if not tool or not tool:IsA("Tool") then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local pickaxe = ToolData.PickaxeById[data.Pickaxe] or ToolData.PickaxeById[ToolData.DefaultPickaxe]

	-- cooldown (with leniency for network jitter)
	local now = os.clock()
	local last = lastSwing[player] or 0
	if now - last < pickaxe.Cooldown * GameConfig.SwingLeniency then
		return
	end
	lastSwing[player] = now

	-- distance from the character to the node surface
	local primary = node.Model.PrimaryPart :: BasePart
	local distance = (root.Position - primary.Position).Magnitude - nodeRadius(node)
	if distance > GameConfig.MineRange then
		return
	end

	local zone = WorldLayout.ZoneById[node.Zone]
	if zone and zone.VipOnly and not Perks.has(player, "ForgeVip") then
		Net.fire("Notify", player, { Text = "Glimmer Grotto ore is for Forge VIPs.", Kind = "Deny" })
		return
	end

	local ore = OreData.get(node.OreId)
	if pickaxe.Tier < ore.Tier then
		local needed = "a better pickaxe"
		for _, p in ToolData.Pickaxes do
			if p.Tier == ore.Tier then
				needed = "a " .. p.Name
				break
			end
		end
		Net.fire("Notify", player, { Text = ore.Name .. " needs " .. needed .. "!", Kind = "Deny" })
		Net.fire("Fx", player, "MineBounce", primary.Position, node.OreId)
		return
	end

	node.Health = math.max(0, node.Health - pickaxe.Damage)
	node.Model:SetAttribute("Health", node.Health)
	local lost = 1 - node.Health / node.MaxHealth
	local newStage = math.clamp(math.floor(lost * 3 + 1e-6), 0, 3)

	local hitPos = primary.Position
	Net.fireNear("Fx", hitPos, 150, player, "MineHit", hitPos, node.OreId, newStage)

	if newStage > node.Stage then
		local crossed = newStage - node.Stage
		for stage = node.Stage + 1, math.min(newStage, 2) do
			local broken = OreNodeBuilder.applyStage(node.Model, stage, node.Seed)
			if #broken > 0 then
				local away = (primary.Position - root.Position) * Vector3.new(1, 0, 1)
				breakOff(broken, if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1))
			end
		end
		node.Stage = newStage
		local chunks = crossed
		if newStage >= 3 then
			if random:NextNumber() < Rarity.get(ore.Rarity).BonusChunkChance then
				chunks += 1
			end
		end
		dropChunks(player, node, chunks)
		if newStage >= 3 then
			shatter(node)
		else
			Net.fireNear("Fx", hitPos, 150, nil, "NodeCrack", hitPos, node.OreId, newStage)
		end
	end
end

function MiningService.init()
	nodesFolder = Workspace:FindFirstChild("Nodes") :: Folder
	Net.on("MineSwing", onSwing)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

function MiningService.start()
	local markers = WorldService.NodeSpawns
	if not markers then
		return
	end
	for _, marker in markers:GetChildren() do
		if marker:IsA("BasePart") then
			spawnNode(marker)
		end
	end
end

-- For the tutorial arrow: nearest alive node of an ore to a position.
function MiningService.nearestNode(position: Vector3, oreId: string?): Model?
	local best, bestDistance = nil, math.huge
	for model, node in nodes do
		if node.Alive and (not oreId or node.OreId == oreId) and model.PrimaryPart then
			local d = (model.PrimaryPart.Position - position).Magnitude
			if d < bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	return best
end

return MiningService
