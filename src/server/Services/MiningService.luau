--[[
	MiningService: rocks, laser blasting and dirty ore drops (design v2).

	- A rock grows at every NodeSpawn marker. It holds 1-3 ores
	  (BlasterData.oreCount) rolled by the marker zone's ore weights. The ores
	  stay on the server: clients only see the rock (OreNodeBuilder.buildRock)
	  and its Zone/OreCount/MinBlaster/Health attributes.
	- MineBlast(rock | nil): the client aims its held beam at a rock (or stops).
	  It only sets the player's target; nothing is damaged by the remote itself.
	- Every BlasterData.Beam.ServerTick the server damages each firing player's
	  target by BlasterData.damage(level, ore) * dt (dt = time since that
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
	- Network (docs/SERVER_PERF_AUDIT.md #8): the Health attribute replicates
	  at most every HEALTH_GAP seconds per rock (and at once when a stage is
	  crossed or the rock breaks); the last change always follows within
	  HEALTH_GAP (the tick flushes it). The shooter's beam colour is cached
	  until their blaster level or ore changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local OreNodeBuilder = require(Shared.Builders.OreNodeBuilder)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local WorldService = require(script.Parent.WorldService)

local MiningService = {}

MiningService.RockTag = "Rock"

local FX_RADIUS = 150 -- players this close see hits and cracks
local SHATTER_RADIUS = 180
local HIT_FX_GAP = 0.25 -- BlastHit at most 4 times a second per rock and shooter
local HEALTH_GAP = 0.3 -- the Health attribute replicates at most ~3 times a second per rock
local TOAST_GAP = 3 -- seconds between "Needs a Level N blaster" toasts for the same rock
local RESPAWN_CHECK = 1 -- seconds between respawn queue checks

type Rock = {
	Model: Model,
	Marker: BasePart?,
	Zone: WorldLayout.Zone,
	Ores: { string }, -- server only, never sent to clients
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
}

type Respawn = { At: number, Marker: BasePart }

local rocks: { [Model]: Rock } = {}
local shooters: { [Player]: Shooter } = {}
local active: { [Player]: Shooter } = {} -- only players with a target
local respawns: { Respawn } = {}
local nextRespawnCheck = 0
local rocksFolder: Instance? = nil
local brokenStages = false -- warned once if OreNodeBuilder.applyStage fails

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

local function spawnRock(marker: BasePart): Rock?
	local zoneId = marker:GetAttribute("Zone")
	local zone = if type(zoneId) == "string" then WorldLayout.ZoneById[zoneId] else nil
	local folder = rocksFolder
	if not zone or not folder then
		return nil
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
		Ores = ores,
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

-- The beam color of a player's blaster (rusty = orange).
local function glowOf(data: { [string]: any }): Color3
	local ore = data.BlasterOre
	return BlasterBuilder.look(data.BlasterLevel, if type(ore) == "string" then ore else "").Glow
end

-- glowOf for a firing player, cached until their blaster level or ore changes (it runs every tick).
local glowCache: { [Player]: { Key: string, Glow: Color3 } } = {}
local function cachedGlow(player: Player, data: { [string]: any }): Color3
	local ore = data.BlasterOre
	local key = tostring(data.BlasterLevel) .. "|" .. (if type(ore) == "string" then ore else "")
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

local function dropChunk(player: Player, rock: Rock, oreId: string, from: Vector3)
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

-- Crack visuals of a stage (OreNodeBuilder belongs to the ore package: never let it break mining).
local function crackVisual(rock: Rock, stage: number, from: Vector3)
	local ok, result = pcall(OreNodeBuilder.applyStage, rock.Model, stage, rock.Seed)
	if ok then
		if type(result) == "table" and #result > 0 then
			local away = (rock.Center - from) * Vector3.new(1, 0, 1)
			breakOff(result, if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1))
		end
	elseif not brokenStages then
		brokenStages = true
		warn("[MiningService] OreNodeBuilder.applyStage failed: " .. tostring(result))
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

local function shatter(player: Player, rock: Rock, glow: Color3)
	rock.Alive = false
	rocks[rock.Model] = nil
	stopShootersOf(rock)
	local data = DataService.get(player)
	if data then
		data.Stats.RocksBroken = (tonumber(data.Stats.RocksBroken) or 0) + 1
		DataService.changed(player)
	end
	Net.fireNear("Fx", rock.Center, SHATTER_RADIUS, nil, "NodeShatter", rock.Center, rock.Crust, glow)
	rock.Model:Destroy()
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
local function crossStage(player: Player, rock: Rock, stage: number, from: Vector3, glow: Color3)
	rock.Stage = stage
	if stage > 3 - #rock.Ores then
		rock.Dropped += 1
		local oreId = rock.Ores[rock.Dropped]
		if oreId then
			dropChunk(player, rock, oreId, from)
		end
	end
	if stage >= 3 then
		shatter(player, rock, glow)
	else
		crackVisual(rock, stage, from)
		local position = hitPosition(rock, from)
		Net.fireNear("Fx", position, FX_RADIUS, nil, "NodeCrack", position, rock.Crust, stage)
	end
end

local function damage(player: Player, data: { [string]: any }, rock: Rock, amount: number, from: Vector3, now: number)
	rock.Health = math.max(0, rock.Health - amount)
	local lost = 1 - rock.Health / rock.MaxHealth
	local newStage = math.clamp(math.floor(lost * 3 + 1e-6), 0, 3)
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

local function shooterOf(player: Player): Shooter
	local shooter = shooters[player]
	if not shooter then
		shooter = { Target = nil, Last = clock(), Toasts = {} }
		shooters[player] = shooter
	end
	return shooter
end

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
	local from = root.Position
	local distance = (from - rock.Center).Magnitude - rock.Radius
	if distance > blaster.Range + BlasterData.Beam.RangeSlack then
		return
	end
	local zone = rock.Zone
	if zone.VipOnly and not Perks.has(player, "ForgeVip") then
		refuse(player, shooter, rock, zone.Name .. " rocks are for Forge VIPs.", from, now)
		return
	end
	if blaster.Level < zone.MinBlaster then
		refuse(player, shooter, rock, "Needs a Level " .. zone.MinBlaster .. " blaster", from, now)
		return
	end
	local ore = data.BlasterOre
	local amount = BlasterData.damage(blaster.Level, if type(ore) == "string" then ore else "") * dt
	damage(player, data, rock, amount, from, now)
end

local function tick(now: number)
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

function MiningService.start()
	local markers = WorldService.NodeSpawns
	if markers then
		for _, marker in markers:GetChildren() do
			if marker:IsA("BasePart") then
				spawnRock(marker)
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
		table.clear(minedCallbacks)
		table.clear(glowCache)
		table.clear(healthDirty)
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
