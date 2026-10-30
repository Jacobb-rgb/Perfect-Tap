--[[
	MiningService: rocks, laser blasting and dirty ore drops (design v2).

	Mine floors (docs/plans/MINE_STEP_PLAN.md): a NodeSpawn marker with a Floor
	attribute grows a floor rock (MineFloors + RockBuilder): its kind is rolled
	from MineFloors.SpawnChance (Deep markers at the back of a floor roll more
	crystals and special rocks), its ores from the floor's Ores (CrystalOres for
	crystal, golden and geode rocks), its HP from MineFloors.rockHealth, its gate
	from the floor's MinBlaster. A floor rock with N ores cracks in N stages (at
	k/N of its HP lost): every stage drops one ore and breaks a shard and a
	crystal off (RockBuilder.applyStage); the last stage shatters it. Markers
	with Kind = "Giant" hold the floor's Giant Crystal: it appears every
	MineFloors.GiantCrystal.Interval seconds, everyone on the server can blast
	it, and when it shatters every player who dealt at least MinDamageShare of
	its HP gets OreCount.Giant ores from the floor's CrystalOres.
	Markers without a Floor (the VIP Grotto) keep the older rules below.

	- A rock grows at every NodeSpawn marker. It holds 1-3 ores
	  (BlasterData.oreCount) rolled by the marker zone's ore weights. The ores
	  stay on the server: clients only see the rock (OreNodeBuilder.buildRock)
	  and its Zone/OreCount/MinBlaster/Health attributes.
	- MineBlast(rock | nil): the client aims its held beam at a rock (or stops).
	  It only sets the player's target; nothing is damaged by the remote itself.
	- Every BlasterData.Beam.ServerTick the server damages each firing player's
	  target by BlasterData.damage(level, ore) * dt (x the equipped STAR
	  blaster's Mult, StarBlasterData; dt = time since that
	  player's last tick, capped at Beam.MaxTickGap so lag never bursts), while
	  the Blaster is in the character's hand, the rock is alive, the rock surface
	  is within the blaster Range + Beam.RangeSlack, the zone's MinBlaster <= the
	  level (else one "Needs a Level N blaster" toast per rock per 3 s + a
	  MineBounce Fx) and VIP zones need the ForgeVip perk.
	- HP falls in three stages (1/3, 2/3, 3/3 lost). Each stage crossed drops
	  the next rolled ore as a Raw chunk owned by the player whose damage
	  crossed it: 1 ore drops at the shatter, 2 ores at stages 2 and 3, 3 ores
	  at every stage. Dirty ore is unknown until cleaned, so there are no
	  "new ore" toasts here (CleaningService does that).
	- A shattered rock grows back after the rarest contained ore's RespawnTime.
	- Only players who are firing are looked at each tick (no loops over parts).
	- Bonuses (steps 6-7, src/server/Bonuses.luau) of the player whose damage
	  counts: damage x Bonuses.damageMult (Overcharge in the last third), range
	  + Bonuses.reach; ore luck (Lucky enchant, Luck golems, Hexa Lucky:
	  Bonuses.oreLuck above 1, growing with rarity) only UPGRADES a dropped
	  ore: an ore whose share grows with the luck always stays, one whose
	  share drops may become a rarer ore of the zone (BoostConfig.upgradeOre:
	  every chunk then has exactly the chances BoostConfig.oreOdds shows); a
	  chunk drops a twin with chance
	  Bonuses.twinDrop. When a rock shatters and an onArtifactRoll listener is
	  registered, one roll against Bonuses.artifactChance (zone chance x
	  Prospector) calls the listeners (player, zoneId, position) on success.
	  With no bonuses nothing extra is rolled.
	- Loose-item cap: while the shooter has GameConfig.MaxLooseItemsPerPlayer
	  loose items (ItemService.atLooseCap) their damage never crosses a stage
	  that would drop an ore (or break the rock): the HP stays just above it
	  (1 HP before the break) and they get "Pick up your ore first" (at most
	  every CAP_TOAST_GAP seconds). The ore stays in the rock (nothing is
	  rolled or lost); once they pick some up, the next hit goes on.
	- Network (docs/SERVER_PERF_AUDIT.md #8): the Health attribute replicates
	  at most every HEALTH_GAP seconds per rock (and at once when a stage is
	  crossed or the rock breaks); the last change always follows within
	  HEALTH_GAP (the tick flushes it). The shooter's beam colour is cached
	  until their blaster level or ore changes.
	- Movement check (docs/plans/MOVEMENT_CHECK_PLAN.md): with
	  MovementConfig.Enforce on the range is measured from
	  MovementService.trustedPosition (off today: the live position); with
	  MovementConfig.BeamLos on a tick deals no damage while BeamSight says a
	  wall stands between the head and the rock (no toast).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local MovementConfig = require(Shared.Config.MovementConfig)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local OreNodeBuilder = require(Shared.Builders.OreNodeBuilder)
local RockBuilder = require(Shared.Builders.RockBuilder)
local MineFloors = require(Shared.Config.MineFloors)
local Net = require(Shared.Net)
local BeamSight = require(script.Parent.Parent.BeamSight)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local SecretService = require(script.Parent.SecretService)
local MovementService = require(script.Parent.MovementService)
local WorldService = require(script.Parent.WorldService)

local MiningService = {}

MiningService.RockTag = "Rock"

local FX_RADIUS = 150 -- players this close see hits and cracks
local SHATTER_RADIUS = 180
local HIT_FX_GAP = 0.25 -- BlastHit at most 4 times a second per rock and shooter
local HEALTH_GAP = 0.3 -- the Health attribute replicates at most ~3 times a second per rock
local TOAST_GAP = 3 -- seconds between "Needs a Level N blaster" toasts for the same rock
local CAP_TOAST_GAP = 4 -- seconds between "Pick up your ore first" toasts per player
MiningService.CapText = "Pick up your ore first"
MiningService.NoSightText = "No clear shot: something is in the way" -- the beam has no line of sight (BeamSight)
local RESPAWN_CHECK = 1 -- seconds between respawn queue checks

type Rock = {
	Model: Model,
	Marker: BasePart?,
	Zone: WorldLayout.Zone,
	Floor: number?, -- mine floor rocks (MineFloors); nil for the older zone rocks
	Kind: string, -- MineFloors rock kind ("Small", "Crystal", "Giant", ...); "Zone" for older rocks
	MinBlaster: number,
	Stages: number, -- crack stages until the shatter (floor rocks: one per ore)
	Damage: { [Player]: number }, -- per player (the Giant Crystal's reward)
	Ores: { string }, -- server only, never sent to clients
	Weights: { [string]: number }, -- the weights its ores were rolled from (ore luck upgrades within them)
	Health: number,
	MaxHealth: number,
	Stage: number,
	Dropped: number,
	Seed: number,
	Alive: boolean,
	Center: Vector3,
	Radius: number,
	Crust: Color3,
	HitFx: { [Player]: number },
	HealthSentAt: number?, -- clock() of the last Health attribute write (nil = at spawn)
}

type Shooter = {
	Target: Rock?,
	Last: number, -- clock() of this player's last damage tick (or target change)
	Toasts: { [Model]: number }, -- last gate toast per rock
	CapToast: number?, -- clock() of the last "Pick up your ore first"
}

type Respawn = { At: number, Marker: BasePart }

type Giant = { Marker: BasePart, Floor: number, At: number, Rock: Rock? }

local rocks: { [Model]: Rock } = {}
local shooters: { [Player]: Shooter } = {}
local active: { [Player]: Shooter } = {} -- only players with a target
local respawns: { Respawn } = {}
local giants: { Giant } = {}
local nextRespawnCheck = 0
local rocksFolder: Instance? = nil
local brokenStages = false -- warned once if a builder's applyStage fails

-- Swappable for the Lune tests.
local clock: () -> number = os.clock
local random: () -> number = function()
	return math.random()
end

-- Listeners for other services (tutorial, badges, analytics).
local minedCallbacks: { (Player, string, number) -> () } = {}
function MiningService.onChunkMined(callback: (player: Player, oreId: string, count: number) -> ())
	table.insert(minedCallbacks, callback)
end

-- The Artifacts package listens here: (player, zoneId, position) when a
-- shattered rock's artifact roll succeeds (see the header).
export type ArtifactCallback = (player: Player, zoneId: string, position: Vector3) -> ()
local artifactCallbacks: { ArtifactCallback } = {}
function MiningService.onArtifactRoll(callback: ArtifactCallback)
	table.insert(artifactCallbacks, callback)
end

---------------------------------------------------------------- rocks

local function pickOre(zone: WorldLayout.Zone): string?
	local keys = {}
	local total = 0
	for oreId, weight in zone.Ores do
		if weight > 0 and OreData.ById[oreId] then
			total += weight
			table.insert(keys, oreId)
		end
	end
	if #keys == 0 then
		return nil
	end
	table.sort(keys)
	local roll = random() * total
	for _, oreId in keys do
		roll -= zone.Ores[oreId]
		if roll < 0 then
			return oreId
		end
	end
	return keys[#keys]
end

-- Center and a generous horizontal radius of a rock (its surface for range checks).
local function measure(model: Model): (Vector3, number)
	local primary = model.PrimaryPart
	local center = if primary then primary.CFrame.Position else model:GetPivot().Position
	local radius = if primary then math.max(primary.Size.X, primary.Size.Z) / 2 else 2
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			local flat = (d.CFrame.Position - center) * Vector3.new(1, 0, 1)
			radius = math.max(radius, flat.Magnitude + math.max(d.Size.X, d.Size.Z) * 0.4)
		end
	end
	return center, math.clamp(radius, 1.5, 9)
end

-- A weighted pick from a { [oreId] = weight } table (keys in name order, so rolls are stable).
local function pickWeighted(weights: { [string]: number }): string?
	local keys = {}
	local total = 0
	for oreId, weight in weights do
		if weight > 0 and OreData.ById[oreId] then
			total += weight
			table.insert(keys, oreId)
		end
	end
	if #keys == 0 then
		return nil
	end
	table.sort(keys)
	local roll = random() * total
	for _, oreId in keys do
		roll -= weights[oreId]
		if roll < 0 then
			return oreId
		end
	end
	return keys[#keys]
end

-- The kind of a new floor rock: specials, crystals and big rocks by MineFloors.SpawnChance
-- (deep spawns at the back of a floor double the crystal chance and raise the specials).
local KIND_ORDER = { "Golden", "Geode", "Artifact", "Crystal", "Big" }
function MiningService.rollKind(roll: number, deep: boolean): string
	local acc = 0
	for _, kind in KIND_ORDER do
		local chance = MineFloors.SpawnChance[kind] or 0
		if deep then
			chance *= if kind == "Crystal" then 2 elseif kind == "Big" then 1 else 1.5
		end
		acc += chance
		if roll < acc then
			return kind
		end
	end
	return "Small"
end

local function finishRock(model: Model, rock: Rock): Rock
	model.Name = "Rock"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag(MiningService.RockTag)
	model:SetAttribute("OreId", nil) -- what clients may know: never the ore ids
	model:SetAttribute("Zone", rock.Zone.Id)
	model:SetAttribute("OreCount", #rock.Ores)
	model:SetAttribute("MinBlaster", rock.MinBlaster)
	model:SetAttribute("VipOnly", rock.Zone.VipOnly == true)
	model:SetAttribute("Health", rock.Health)
	model:SetAttribute("MaxHealth", rock.MaxHealth)
	model:SetAttribute("Stage", 0)
	if rock.Floor then
		model:SetAttribute("Floor", rock.Floor)
		model:SetAttribute("Kind", rock.Kind)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local center, radius = measure(model)
	rock.Center, rock.Radius = center, radius
	local primary = model.PrimaryPart
	rock.Crust = if primary then primary.Color else rock.Crust
	model.Parent = rocksFolder
	rocks[model] = rock
	return rock
end

-- A mine floor rock on `marker` (forcedKind: "Giant" for the Giant Crystal).
local function spawnFloorRock(marker: BasePart, zone: WorldLayout.Zone, floor: MineFloors.Floor, forcedKind: string?): Rock?
	local markerKind = marker:GetAttribute("Kind")
	local kind = forcedKind
		or (if type(markerKind) == "string" and MineFloors.OreCount[markerKind :: any] and markerKind ~= "Giant" then markerKind else nil)
		or MiningService.rollKind(random(), marker:GetAttribute("Deep") == true)
	local rockKind: MineFloors.RockKind = kind :: any
	local rich = kind == "Crystal" or kind == "Golden" or kind == "Geode" or kind == "Giant"
	local ores = {}
	if kind ~= "Giant" then
		for _ = 1, MineFloors.OreCount[rockKind] or 3 do
			local oreId = pickWeighted(if rich then floor.CrystalOres else floor.Ores)
			if oreId then
				table.insert(ores, oreId)
			end
		end
		if #ores == 0 then
			return nil
		end
	end
	local seed = math.floor(random() * 1e9) + 1
	local ground = marker.CFrame.Position - Vector3.new(0, marker.Size.Y / 2, 0)
	local model = RockBuilder.build(floor.Index, rockKind, ores, CFrame.new(ground), seed)
	local health = MineFloors.rockHealth(floor.Index, rockKind)
	return finishRock(model, {
		Model = model,
		Marker = marker,
		Zone = zone,
		Floor = floor.Index,
		Kind = kind,
		MinBlaster = floor.MinBlaster,
		Stages = if kind == "Giant" then 3 else math.max(1, #ores),
		Damage = {},
		Ores = ores,
		Weights = if rich then floor.CrystalOres else floor.Ores,
		Health = health,
		MaxHealth = health,
		Stage = 0,
		Dropped = 0,
		Seed = seed,
		Alive = true,
		Center = ground,
		Radius = 2,
		Crust = floor.Palette.Mid,
		HitFx = {},
	})
end

local function spawnRock(marker: BasePart): Rock?
	local zoneId = marker:GetAttribute("Zone")
	local zone = if type(zoneId) == "string" then WorldLayout.ZoneById[zoneId] else nil
	local folder = rocksFolder
	if not zone or not folder then
		return nil
	end
	local floorIndex = marker:GetAttribute("Floor")
	local floor = if type(floorIndex) == "number" then MineFloors.ByIndex[floorIndex] else nil
	if floor then
		if marker:GetAttribute("Kind") == "Giant" then
			return nil -- the Giant Crystal comes and goes on its own timer (see tickGiants)
		end
		return spawnFloorRock(marker, zone, floor, nil)
	end
	local ores = {}
	for _ = 1, BlasterData.oreCount(random()) do
		local oreId = pickOre(zone)
		if oreId then
			table.insert(ores, oreId)
		end
	end
	if #ores == 0 then
		return nil
	end
	local seed = math.floor(random() * 1e9) + 1
	local ground = marker.CFrame.Position - Vector3.new(0, marker.Size.Y / 2, 0)
	local base = CFrame.new(ground) * CFrame.Angles(0, random() * math.pi * 2, 0)
	local model = OreNodeBuilder.buildRock(zone.Id, ores, base, seed)
	model.Name = "Rock"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag(MiningService.RockTag)
	local health = BlasterData.rockHealth(zone.RockHealth, ores)
	-- what clients may know: never the ore ids
	model:SetAttribute("OreId", nil)
	model:SetAttribute("Zone", zone.Id)
	model:SetAttribute("OreCount", #ores)
	model:SetAttribute("MinBlaster", zone.MinBlaster)
	model:SetAttribute("VipOnly", zone.VipOnly == true)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("Stage", 0)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local center, radius = measure(model)
	local primary = model.PrimaryPart
	model.Parent = folder
	local rock: Rock = {
		Model = model,
		Marker = marker,
		Zone = zone,
		Floor = nil,
		Kind = "Zone",
		MinBlaster = zone.MinBlaster,
		Stages = 3,
		Damage = {},
		Ores = ores,
		Weights = zone.Ores,
		Health = health,
		MaxHealth = health,
		Stage = 0,
		Dropped = 0,
		Seed = seed,
		Alive = true,
		Center = center,
		Radius = radius,
		Crust = if primary then primary.Color else Color3.fromRGB(120, 110, 100),
		HitFx = {},
	}
	rocks[model] = rock
	return rock
end

-- The point on the rock that faces `from` (where the beam hits).
local function hitPosition(rock: Rock, from: Vector3): Vector3
	local away = (from - rock.Center) * Vector3.new(1, 0, 1)
	local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	return rock.Center + direction * rock.Radius * 0.7 + Vector3.new(0, 0.5, 0)
end

-- The beam color of a player's blaster (rusty = orange; a star blaster's own glow).
local function glowOf(data: { [string]: any }): Color3
	local star = StarBlasterData.equipped(data)
	if star then
		return star.Glow
	end
	local ore = data.BlasterOre
	return BlasterBuilder.look(data.BlasterLevel, if type(ore) == "string" then ore else "").Glow
end

-- glowOf for a firing player, cached until their blaster level, ore or star blaster changes (it runs every tick).
local glowCache: { [Player]: { Key: string, Glow: Color3 } } = {}
local function cachedGlow(player: Player, data: { [string]: any }): Color3
	local ore = data.BlasterOre
	local star = StarBlasterData.equipped(data)
	local key = tostring(data.BlasterLevel) .. "|" .. (if type(ore) == "string" then ore else "") .. "|" .. (if star then star.Id else "")
	local cached = glowCache[player]
	if cached and cached.Key == key then
		return cached.Glow
	end
	local glow = glowOf(data)
	glowCache[player] = { Key = key, Glow = glow }
	return glow
end

-- Rocks whose Health changed since the attribute was last written (the tick flushes them).
local healthDirty: { [Rock]: boolean } = {}

-- Writes the Health attribute now (it replicates to every client near the rock).
local function sendHealth(rock: Rock, now: number)
	healthDirty[rock] = nil
	rock.HealthSentAt = now
	if rock.Alive then
		rock.Model:SetAttribute("Health", rock.Health)
	end
end

---------------------------------------------------------------- drops and stages

local function spawnChunk(player: Player, rock: Rock, oreId: string, from: Vector3)
	local toward = (from - rock.Center) * Vector3.new(1, 0, 1)
	local forward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.new(0, 0, 1)
	-- fly roughly toward the shooter, spread up to ~60 degrees to each side
	local out = CFrame.Angles(0, (random() - 0.5) * 2.1, 0):VectorToWorldSpace(forward)
	local origin = rock.Center + Vector3.new(0, rock.Radius * 0.5 + 1.5, 0) + out * 0.8
	local cf = CFrame.new(origin) * CFrame.Angles(random() * 6, random() * 6, 0)
	local velocity = out * (7 + random() * 4) + Vector3.new(0, 16, 0)
	ItemService.spawn({ Kind = "Raw", OreId = oreId }, player.UserId, cf, velocity)
	local data = DataService.get(player)
	if data then
		data.Stats.OresMined = (tonumber(data.Stats.OresMined) or 0) + 1
		DataService.changed(player)
	end
	for _, callback in minedCallbacks do
		task.spawn(callback, player, oreId, 1)
	end
end

-- Bonuses: ore luck may upgrade the rock's ore, Twin Drop may add a second chunk.
-- A mine floor's rock: the ore may turn into a SECRET ore (SecretService, the same luck raising it);
-- its twin stays the ore it was, so a secret is never doubled.
local function dropChunk(player: Player, rock: Rock, rolled: string, from: Vector3)
	local stats = Bonuses.stats(player)
	local oreId = Bonuses.rollOre(stats, rock.Weights, rolled, random)
	-- (only in the mine: the town's starter outcrops count as floor 1 but never hold a secret)
	local floor = if rock.Floor and rock.Zone.Id ~= "Outcrops" then MineFloors.ByIndex[rock.Floor] else nil
	local secret = if floor then SecretService.rollDrop(Bonuses.oreLuck(stats), floor.Id) else nil
	spawnChunk(player, rock, secret or oreId, from)
	local twin = Bonuses.twinDrop(stats)
	if twin > 0 and random() < twin then
		spawnChunk(player, rock, oreId, from)
	end
end

-- Bonuses: one artifact roll per shattered rock (only with a listener); artifact rocks always hit.
local function rollArtifact(player: Player, rock: Rock)
	if #artifactCallbacks == 0 then
		return
	end
	-- an artifact rock (a mine floor's special kind) always holds one
	local chance = if rock.Kind == "Artifact" then 1 else Bonuses.artifactChance(Bonuses.stats(player), rock.Zone.Id)
	if random() < chance then
		for _, callback in artifactCallbacks do
			task.spawn(callback, player, rock.Zone.Id, rock.Center)
		end
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
		part.AssemblyAngularVelocity = Vector3.new(random() * 12 - 6, random() * 12 - 6, random() * 12 - 6)
		task.delay(1.6, function()
			part:Destroy()
		end)
	end
end

-- Crack visuals of a stage (the builders belong to the art packages: never let them break mining).
local function crackVisual(rock: Rock, stage: number, from: Vector3)
	local apply = if rock.Floor then RockBuilder.applyStage else OreNodeBuilder.applyStage
	local ok, result = pcall(apply, rock.Model, stage, rock.Seed)
	if ok then
		if type(result) == "table" and #result > 0 then
			local away = (rock.Center - from) * Vector3.new(1, 0, 1)
			breakOff(result, if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1))
		end
	elseif not brokenStages then
		brokenStages = true
		warn("[MiningService] applyStage failed: " .. tostring(result))
	end
	rock.Model:SetAttribute("Stage", stage)
end

local function stopShootersOf(rock: Rock)
	for player, shooter in active do
		if shooter.Target == rock then
			shooter.Target = nil
			active[player] = nil
		end
	end
end

-- The Giant Crystal's reward: every player who dealt enough of its HP gets ores near them.
local function rewardGiant(rock: Rock)
	local floor = if rock.Floor then MineFloors.ByIndex[rock.Floor] else nil
	if not floor then
		return
	end
	local needed = rock.MaxHealth * MineFloors.GiantCrystal.MinDamageShare
	for helper, dealt in rock.Damage do
		if dealt >= needed and helper.Parent then
			local root = Guard.rootPart(helper)
			local from = if root then root.Position else rock.Center + Vector3.new(0, 0, rock.Radius + 4)
			for _ = 1, MineFloors.OreCount["Giant" :: MineFloors.RockKind] or 3 do
				local oreId = pickWeighted(floor.CrystalOres)
				if oreId then
					dropChunk(helper, rock, oreId, from)
				end
			end
			Net.fire("Notify", helper, { Text = "Giant Crystal shattered! Your share of crystal ores is here.", Kind = "Success" })
		end
	end
end

local function shatter(player: Player, rock: Rock, glow: Color3)
	rock.Alive = false
	rocks[rock.Model] = nil
	stopShootersOf(rock)
	local data = DataService.get(player)
	if data then
		data.Stats.RocksBroken = (tonumber(data.Stats.RocksBroken) or 0) + 1
		DataService.changed(player)
	end
	rollArtifact(player, rock)
	Net.fireNear("Fx", rock.Center, SHATTER_RADIUS, nil, "NodeShatter", rock.Center, rock.Crust, glow, rock.Floor, rock.Kind, rock.Radius)
	rock.Model:Destroy()
	if rock.Kind == "Giant" then
		rewardGiant(rock)
		for _, giant in giants do
			if giant.Rock == rock then
				giant.Rock = nil
				giant.At = clock() + MineFloors.GiantCrystal.Interval
			end
		end
		return
	end
	-- the rarest ore inside decides how long the rock takes to grow back
	local slowest = 0
	for _, oreId in rock.Ores do
		local ore = OreData.ById[oreId]
		if ore then
			slowest = math.max(slowest, Rarity.get(ore.Rarity).RespawnTime)
		end
	end
	local marker = rock.Marker
	if marker then
		table.insert(respawns, { At = clock() + slowest * (0.85 + random() * 0.3), Marker = marker })
	end
end

-- A stage was crossed by `player`'s damage: drop the next ore, crack or shatter.
-- (The last #Ores stages drop an ore each: every stage for floor rocks, whose Stages = #Ores.)
local function crossStage(player: Player, rock: Rock, stage: number, from: Vector3, glow: Color3)
	rock.Stage = stage
	local dropped: string? = nil
	if rock.Kind ~= "Giant" and stage > rock.Stages - #rock.Ores then
		rock.Dropped += 1
		dropped = rock.Ores[rock.Dropped]
		if dropped then
			dropChunk(player, rock, dropped, from)
		end
	end
	if stage >= rock.Stages then
		shatter(player, rock, glow)
	else
		crackVisual(rock, stage, from)
		local position = hitPosition(rock, from)
		local ore = if dropped then OreData.ById[dropped] else nil
		Net.fireNear("Fx", position, FX_RADIUS, nil, "NodeCrack", position, rock.Crust, stage, if ore then ore.Glow else glow, rock.Stages)
	end
end

local function shooterOf(player: Player): Shooter
	local shooter = shooters[player]
	if not shooter then
		shooter = { Target = nil, Last = clock(), Toasts = {} }
		shooters[player] = shooter
	end
	return shooter
end

-- The stage a health value has reached (0..3).
local function stageAt(rock: Rock, health: number): number
	local lost = 1 - health / rock.MaxHealth
	return math.clamp(math.floor(lost * rock.Stages + 1e-6), 0, rock.Stages)
end

--[[
	The loose-item cap (header): the health `player`'s damage may bring the
	rock down to. Unchanged unless it would cross a stage that drops an ore
	(or breaks the rock) while the player has the cap of loose items; then
	it stops just above that stage (1 HP above it, less on a tiny rock),
	never higher than the rock's health now. Second value: held.
]]
local function allowedHealth(player: Player, rock: Rock, health: number): (number, boolean)
	local reached = stageAt(rock, health)
	local drops: number? = nil
	for stage = rock.Stage + 1, reached do
		-- the break, or a stage that drops an ore (the last #Ores stages; a Giant drops only at the break)
		if stage >= rock.Stages or (rock.Kind ~= "Giant" and stage > rock.Stages - #rock.Ores) then
			drops = stage
			break
		end
	end
	if not drops or not ItemService.atLooseCap(player.UserId) then
		return health, false
	end
	local threshold = rock.MaxHealth * (1 - drops / rock.Stages)
	local hold = threshold + math.min(1, rock.MaxHealth / 6)
	return math.min(rock.Health, math.max(health, hold)), true
end

-- "Pick up your ore first" (at most every CAP_TOAST_GAP seconds) and a bounce.
local function capToast(player: Player, rock: Rock, from: Vector3, now: number)
	local shooter = shooterOf(player)
	local last = shooter.CapToast
	if last and now - last < CAP_TOAST_GAP and now >= last then
		return
	end
	shooter.CapToast = now
	Net.fire("Notify", player, { Text = MiningService.CapText, Kind = "Deny" })
	Net.fire("Fx", player, "MineBounce", hitPosition(rock, from))
end

local function damage(player: Player, data: { [string]: any }, rock: Rock, amount: number, from: Vector3, now: number)
	local health, held = allowedHealth(player, rock, math.max(0, rock.Health - amount))
	if held then
		capToast(player, rock, from, now)
	end
	-- the Giant Crystal's shares count the HP each player really took off
	rock.Damage[player] = (rock.Damage[player] or 0) + math.max(0, rock.Health - health)
	rock.Health = health
	local newStage = stageAt(rock, rock.Health)
	-- a crossed stage (or the break) shows at once; plain damage at most every HEALTH_GAP
	if newStage > rock.Stage or now - (rock.HealthSentAt or -math.huge) >= HEALTH_GAP then
		sendHealth(rock, now)
	else
		healthDirty[rock] = true
	end
	local glow = cachedGlow(player, data)
	local last = rock.HitFx[player]
	if not last or now - last >= HIT_FX_GAP then
		rock.HitFx[player] = now
		local position = hitPosition(rock, from)
		Net.fireNear("Fx", position, FX_RADIUS, player, "BlastHit", position, glow, newStage, player)
	end
	for stage = rock.Stage + 1, newStage do
		if not rock.Alive then
			break
		end
		crossStage(player, rock, stage, from, glow)
	end
end

---------------------------------------------------------------- blasting

-- One toast per rock every TOAST_GAP seconds, plus a bounce effect.
local function refuse(player: Player, shooter: Shooter, rock: Rock, text: string, from: Vector3, now: number)
	local last = shooter.Toasts[rock.Model]
	if last and now - last < TOAST_GAP then
		return
	end
	local count = 0
	for model, at in shooter.Toasts do
		count += 1
		if count > 12 and now - at >= TOAST_GAP then
			shooter.Toasts[model] = nil
		end
	end
	shooter.Toasts[rock.Model] = now
	Net.fire("Notify", player, { Text = text, Kind = "Deny" })
	Net.fire("Fx", player, "MineBounce", hitPosition(rock, from))
end

-- MineBlast(rock | nil): aim the held beam at a rock, or stop firing.
local function onBlast(player: Player, value: any)
	local shooter = shooterOf(player)
	local folder = rocksFolder
	local model = if folder then Guard.instance(value, "Model", folder) :: Model? else nil
	local rock = if model then rocks[model] else nil
	if not rock or not rock.Alive then
		-- nil, junk or a rock that is gone: the beam stops
		shooter.Target = nil
		active[player] = nil
		return
	end
	if shooter.Target ~= rock then
		shooter.Target = rock
		shooter.Last = clock()
	end
	active[player] = shooter
end

local function tickShooter(player: Player, shooter: Shooter, now: number)
	local rock = shooter.Target
	local dt = math.clamp(now - shooter.Last, 0, BlasterData.Beam.MaxTickGap)
	shooter.Last = now
	if not rock or not rock.Alive then
		shooter.Target = nil
		active[player] = nil
		return
	end
	local data = DataService.get(player)
	local root = Guard.rootPart(player)
	local character = player.Character
	if dt <= 0 or not data or not root or not character then
		return
	end
	local tool = character:FindFirstChild(BlasterBuilder.ToolName)
	if not tool or not tool:IsA("Tool") then
		return -- the blaster must be in hand
	end
	local blaster = BlasterData.get(data.BlasterLevel)
	local stats = Bonuses.stats(player)
	local from = root.Position
	local distance = (MovementService.rangeOrigin(player, from) - rock.Center).Magnitude - rock.Radius
	if distance > blaster.Range + Bonuses.reach(stats) + BlasterData.Beam.RangeSlack then
		return
	end
	local zone = rock.Zone
	if zone.VipOnly and not Perks.has(player, "ForgeVip") then
		refuse(player, shooter, rock, zone.Name .. " rocks are for Forge VIPs.", from, now)
		return
	end
	if blaster.Level < rock.MinBlaster then
		refuse(player, shooter, rock, "Needs a Level " .. rock.MinBlaster .. " blaster", from, now)
		return
	end
	if MovementConfig.BeamLos and not BeamSight.canHit(player, character, root, rock.Model, now) then
		-- a wall between: no damage this tick, and the player learns why (throttled per rock)
		refuse(player, shooter, rock, MiningService.NoSightText, from, now)
		return
	end
	local ore = data.BlasterOre
	-- (a STAR blaster hits Mult x the forged level's damage: StarBlasterData, power A)
	local amount = BlasterData.damage(blaster.Level, if type(ore) == "string" then ore else "") * StarBlasterData.mult(data) * dt
	amount *= Bonuses.damageMult(stats, rock.Stage >= 2)
	damage(player, data, rock, amount, from, now)
end

-- Players standing in a zone (for the Giant Crystal news).
local function playersIn(zone: WorldLayout.Zone): { Player }
	local list = {}
	local ok, all = pcall(function()
		return Players:GetPlayers()
	end)
	for _, player in if ok then all else {} do
		local root = Guard.rootPart(player)
		if root and WorldLayout.isInBox(root.Position, zone.Min, zone.Max) then
			table.insert(list, player)
		end
	end
	return list
end

-- The Giant Crystals: one per floor's GiantSpawn, back every Interval after it shattered.
local function tickGiants(now: number)
	for _, giant in giants do
		if not giant.Rock and now >= giant.At and giant.Marker.Parent then
			local zoneId = giant.Marker:GetAttribute("Zone")
			local zone = if type(zoneId) == "string" then WorldLayout.ZoneById[zoneId] else nil
			local floor = MineFloors.ByIndex[giant.Floor]
			if zone and floor then
				local rock = spawnFloorRock(giant.Marker, zone, floor, "Giant")
				giant.Rock = rock
				giant.At = math.huge
				if rock then
					for _, player in playersIn(zone) do
						Net.fire(
							"Notify",
							player,
							{ Text = "A Giant Crystal appeared in " .. floor.Name .. "! Blast it together.", Kind = "Info" }
						)
					end
				end
			end
		end
	end
end

local function tick(now: number)
	tickGiants(now)
	for player, shooter in active do
		local ok, err = pcall(function()
			tickShooter(player, shooter, now)
		end)
		if not ok then
			warn("[MiningService] tick failed for " .. player.Name .. ": " .. tostring(err))
			shooter.Target = nil
			active[player] = nil
		end
	end
	-- the last damage of a rock follows within HEALTH_GAP, also after everyone stopped
	for rock in healthDirty do
		if not rock.Alive then
			healthDirty[rock] = nil
		elseif now - (rock.HealthSentAt or -math.huge) >= HEALTH_GAP then
			sendHealth(rock, now)
		end
	end
	if now >= nextRespawnCheck and #respawns > 0 then
		nextRespawnCheck = now + RESPAWN_CHECK
		for i = #respawns, 1, -1 do
			local entry = respawns[i]
			if now >= entry.At then
				table.remove(respawns, i)
				if entry.Marker.Parent then
					spawnRock(entry.Marker)
				end
			end
		end
	end
end

local function forgetPlayer(player: Player)
	shooters[player] = nil
	active[player] = nil
	glowCache[player] = nil
	BeamSight.forget(player)
	for _, rock in rocks do
		rock.HitFx[player] = nil
	end
end

---------------------------------------------------------------- lifecycle

function MiningService.init()
	rocksFolder = Workspace:FindFirstChild("Nodes")
	Net.on("MineBlast", onBlast)
	Players.PlayerRemoving:Connect(forgetPlayer)
end

-- Remembers a GiantSpawn marker: its Giant Crystal first appears after half an Interval.
local function addGiant(marker: BasePart)
	local floorIndex = marker:GetAttribute("Floor")
	if type(floorIndex) == "number" and MineFloors.ByIndex[floorIndex] then
		table.insert(giants, { Marker = marker, Floor = floorIndex, At = clock() + MineFloors.GiantCrystal.Interval * 0.5, Rock = nil })
	end
end

function MiningService.start()
	local markers = WorldService.NodeSpawns
	if markers then
		for _, marker in markers:GetChildren() do
			if marker:IsA("BasePart") then
				if marker:GetAttribute("Kind") == "Giant" then
					addGiant(marker)
				else
					spawnRock(marker)
				end
			end
		end
	end
	while true do
		task.wait(BlasterData.Beam.ServerTick)
		local ok, err = pcall(function()
			tick(clock())
		end)
		if not ok then
			warn("[MiningService] " .. tostring(err))
		end
	end
end

-- For the tutorial arrow: nearest alive rock to a position (optionally one holding `oreId`).
function MiningService.nearestNode(position: Vector3, oreId: string?): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for model, rock in rocks do
		if rock.Alive and (not oreId or table.find(rock.Ores, oreId)) then
			local d = (rock.Center - position).Magnitude
			if d < bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	return best
end

-- Internals for the Lune tests only (tests/Mining.spec.luau).
MiningService._test = {
	-- forget every rock, shooter and respawn; `folder` holds the rocks
	reset = function(folder: Instance?)
		table.clear(rocks)
		table.clear(shooters)
		table.clear(active)
		table.clear(respawns)
		table.clear(giants)
		table.clear(minedCallbacks)
		table.clear(artifactCallbacks)
		table.clear(glowCache)
		table.clear(healthDirty)
		BeamSight._test.reset() -- an empty world (BeamSight._test.setRaycast adds walls)
		nextRespawnCheck = 0
		brokenStages = false
		rocksFolder = folder
		clock = os.clock
		random = function()
			return math.random()
		end
	end,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setRandom = function(fn: () -> number)
		random = fn
	end,
	spawnRock = spawnRock,
	addGiant = addGiant,
	giants = function(): { Giant }
		return giants
	end,
	blast = onBlast,
	tick = tick,
	forget = forgetPlayer,
	rock = function(model: Model): Rock?
		return rocks[model]
	end,
	target = function(player: Player): Model?
		local shooter = active[player]
		local rock = shooter and shooter.Target
		return if rock then rock.Model else nil
	end,
	respawns = function(): { Respawn }
		return respawns
	end,
}

return MiningService
