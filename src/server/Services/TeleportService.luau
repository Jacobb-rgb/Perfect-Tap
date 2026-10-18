--[[
	TeleportService: the quick teleports (TeleportConfig; owner 2026-10-17).

	Teleport (Net, rate limited) carries a destination name:
	  "Base"      the front of your own plot (PlotService.homeCFrame)
	  "Lobby"     the town spawn (the TownSpawn SpawnLocation, else WorldLayout.SpawnPoint)
	  "Vault"     in front of the Blaster Vault's steps (Lobby/Vault: Vault.origin())
	  "Elevator"  in front of the mine elevator stop (Models tagged
	              TeleportConfig.ElevatorTag) of the mine floor you are on
	              (WorldLayout zone -> MineFloors floor), else floor 1's stop,
	              else the lowest one; refused while the world has none. The
	              HUD's elevator button (ElevatorController) sends this; the
	              floor picker opens from the stop's prompt (owner 2026-10-18)
	Unknown names are ignored. Every other request gets a TeleportResult
	{ Destination, Ok, Reason? } (Reason = a TeleportConfig.Reasons code):
	  Cooldown  within ServerCooldown of your last teleport
	  Dead      no live character
	  Cleaning  in the middle of the cleaning minigame
	  NoBase / NotHere  the destination doesn't exist (yet)
	The area round the target is streamed in before the move (StreamingEnabled),
	the character gets off any seat and lands on the ground there, a little
	spread so players don't stack. Carried items stay welded to the character
	and come along.

	Workspace attribute TeleportConfig.ElevatorAttribute = true while an
	elevator stop exists (the client shows the side icon then).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeleportConfig = require(Shared.Config.TeleportConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local MineFloors = require(Shared.Config.MineFloors)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Vault = require(script.Parent.Parent.World.Lobby.Vault)
local PlotService = require(script.Parent.PlotService)

local TeleportService = {}

type Destination = TeleportConfig.Destination
export type Reason = "Cooldown" | "Dead" | "Cleaning" | "NoBase" | "NotHere"

-- The Blaster Vault's podium reaches this far in front of its origin (design
-- studs, Lobby/Vault/Building: podium z -34..48), scaled by Vault.Scale.
TeleportService.VaultPodiumFront = 48

local lastTeleport: { [Player]: number } = {}

local function reply(player: Player, destination: string, ok: boolean, reason: Reason?)
	Net.fire("TeleportResult", player, { Destination = destination, Ok = ok, Reason = reason })
end

-- The ground under a point (characters and loose items don't count), else the point itself.
function TeleportService.groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(ignore, items)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else position
end

-- A standing frame on the ground at `at`, looking toward `toward` (level).
local function standAt(at: Vector3, toward: Vector3, spread: number?): CFrame
	local offset = Vector3.zero
	if spread and spread > 0 then
		local angle = math.random() * math.pi * 2
		offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random() * spread
	end
	local ground = TeleportService.groundAt(at + offset)
	local position = ground + Vector3.new(0, TeleportConfig.StandHeight, 0)
	local look = Vector3.new(toward.X, position.Y, toward.Z)
	if (look - position).Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, look)
end

-- Is the player in the middle of the cleaning minigame? (CleaningService is
-- loaded on first use: it needs the whole game around it)
function TeleportService.isCleaning(player: Player): boolean
	local CleaningService = require(script.Parent.CleaningService) :: any
	return CleaningService.isCleaning(player)
end

--[[
	Picks a stop's Base plate from `stops`: the stop of `floor` when there is
	one, else floor 1's, else the lowest floor's (nil = no usable stop).
]]
function TeleportService.pickStop(stops: { Instance }, floor: number?): BasePart?
	local best: BasePart? = nil
	local bestFloor = math.huge
	local wanted: BasePart? = nil
	local first: BasePart? = nil
	for _, stop in stops do
		local base = stop:FindFirstChild("Base")
		local index = tonumber(stop:GetAttribute("Floor")) or math.huge
		if base and base:IsA("BasePart") and stop.Parent then
			if floor and index == floor then
				wanted = base
			end
			if index == 1 then
				first = base
			end
			if index < bestFloor then
				best, bestFloor = base, index
			end
		end
	end
	return wanted or first or best
end

-- The elevator stop for a floor (see pickStop; no floor = floor 1's or the lowest), if any.
function TeleportService.elevatorStop(floor: number?): BasePart?
	local stops: { Instance } = {}
	for _, stop in CollectionService:GetTagged(TeleportConfig.ElevatorTag) do
		if stop:IsDescendantOf(Workspace) then
			table.insert(stops, stop)
		end
	end
	return TeleportService.pickStop(stops, floor)
end

-- The mine floor whose area holds `position` (WorldLayout zone -> MineFloors), if any.
function TeleportService.floorAt(position: Vector3): number?
	local zone = WorldLayout.zoneAt(position)
	local floor = zone and MineFloors.ByZone[zone.Id]
	return if floor then floor.Index else nil
end

-- Where the town spawn is.
local function lobbySpawn(): Vector3
	local map = Workspace:FindFirstChild("Map")
	local spawn = map and map:FindFirstChild("TownSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame.Position
	end
	return WorldLayout.SpawnPoint
end

-- Where a destination puts this player (nil + a reason when it can't).
function TeleportService.targetOf(player: Player, destination: Destination): (CFrame?, Reason?)
	if destination == "Base" then
		local plotId = PlotService.plotOf(player)
		if not plotId then
			return nil, "NoBase"
		end
		local home = PlotService.homeCFrame(plotId)
		return standAt(home.Position, home.Position + home.LookVector * 10, TeleportConfig.Spread), nil
	elseif destination == "Lobby" then
		local spawn = lobbySpawn()
		return standAt(spawn, Vector3.new(0, spawn.Y, 0), TeleportConfig.Spread), nil
	elseif destination == "Vault" then
		local origin = Vault.origin()
		local front = TeleportService.VaultPodiumFront * Vault.Scale + TeleportConfig.VaultFront
		return standAt((origin * CFrame.new(0, 0, front)).Position, origin.Position, TeleportConfig.Spread), nil
	elseif destination == "Elevator" then
		local root = Guard.rootPart(player)
		local base = TeleportService.elevatorStop(if root then TeleportService.floorAt(root.CFrame.Position) else nil)
		if not base then
			return nil, "NotHere"
		end
		local front = base.CFrame * CFrame.new(0, 0, -(base.Size.Z / 2 + 3))
		return standAt(front.Position, base.CFrame.Position), nil
	end
	return nil, "NotHere"
end

local function onTeleport(player: Player, destination: any)
	local name = Guard.string(destination, 16)
	local spot: TeleportConfig.Spot? = if name then TeleportConfig.ById[name] else nil
	if not spot then
		return
	end
	local id: Destination = spot.Id
	local now = os.clock()
	local last = lastTeleport[player]
	if last and now - last < TeleportConfig.ServerCooldown then
		reply(player, id, false, "Cooldown")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = Guard.rootPart(player)
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		reply(player, id, false, "Dead")
		return
	end
	if TeleportService.isCleaning(player) then
		reply(player, id, false, "Cleaning")
		return
	end
	local target: CFrame?, reason: Reason? = TeleportService.targetOf(player, id)
	if not target then
		reply(player, id, false, reason)
		return
	end
	lastTeleport[player] = now
	-- load the area first so the character doesn't land in nothing
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 2)
	end)
	if player.Character ~= character or humanoid.Health <= 0 or not root.Parent then
		reply(player, id, false, "Dead")
		return
	end
	local seat = humanoid.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end
	character:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	reply(player, id, true, nil)
end

local function updateElevator()
	Workspace:SetAttribute(TeleportConfig.ElevatorAttribute, TeleportService.elevatorStop() ~= nil)
end

-- Internals for the Lune tests only (tests/Teleport.spec.luau).
TeleportService._test = {
	handle = onTeleport,
	updateElevator = updateElevator,
	reset = function()
		table.clear(lastTeleport)
	end,
}

function TeleportService.init()
	Net.on("Teleport", onTeleport)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTeleport[player] = nil
	end)
end

function TeleportService.start()
	updateElevator()
	CollectionService:GetInstanceAddedSignal(TeleportConfig.ElevatorTag):Connect(function()
		task.defer(updateElevator)
	end)
	CollectionService:GetInstanceRemovedSignal(TeleportConfig.ElevatorTag):Connect(function()
		task.defer(updateElevator)
	end)
end

return TeleportService
