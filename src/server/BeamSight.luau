--[[
	BeamSight: the mining beam's line of sight (docs/plans/MOVEMENT_CHECK_PLAN.md,
	security audit #12). MiningService asks canHit before a damage tick while
	MovementConfig.BeamLos is on; blocked = no damage that tick (no toast).

	- One result per (player, rock) for MovementConfig.BeamLosCache seconds
	  (only the last rock per player is kept: a beam has one target).
	- From the character's Head (else the root + 1.5 up) toward the rock's box
	  (measured once per rock from its parts): its closest point, then its top
	  center (MovementLogic.beamLines), each line stopping BeamStopShort before
	  the rock, so the quarry wall right behind a rock never counts.
	- Never block: characters, the Items and Debris folders, the rocks folder,
	  CollectionService tag MovementConfig.BeamIgnoreTag (filter rebuilt at most
	  once a second), parts with CanCollide off (RespectCanCollide), CanQuery
	  off, water, and a hit part or its parent with the BeamIgnoreAttribute
	  attribute = true or the tag (cast on behind it, BeamMaxPasses casts).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))
local MovementLogic = require(script.Parent.MovementLogic)

local BeamSight = {}

type Entry = { Rock: Model, At: number, Clear: boolean }
type Box = { Min: Vector3, Max: Vector3 }

local cache: { [Player]: Entry } = {}
local boxes: { [Model]: Box } = setmetatable({}, { __mode = "k" }) :: any
local params: RaycastParams? = nil
local paramsAt = -math.huge

-- What the beam never hits (rebuilt at most once a second).
local function filter(rocks: Instance?): RaycastParams
	local now = os.clock()
	local current = params
	if current and now - paramsAt < 1 then
		return current
	end
	local ignore: { Instance } = {}
	for _, name in { "Items", "Debris" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	if rocks and rocks ~= Workspace then
		table.insert(ignore, rocks)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, tagged in CollectionService:GetTagged(MovementConfig.BeamIgnoreTag) do
		table.insert(ignore, tagged)
	end
	local fresh = current or RaycastParams.new()
	fresh.FilterType = Enum.RaycastFilterType.Exclude
	fresh.FilterDescendantsInstances = ignore
	fresh.IgnoreWater = true
	fresh.RespectCanCollide = true
	params, paramsAt = fresh, now
	return fresh
end

local rocksOfCast: Instance? = nil -- the rocks folder of the rock being checked

local function worldCast(origin: Vector3, direction: Vector3): MovementLogic.Hit?
	local result = Workspace:Raycast(origin, direction, filter(rocksOfCast))
	return if result then { Instance = result.Instance, Position = result.Position } else nil
end
local cast: MovementLogic.Cast = worldCast -- swappable for the Lune tests

-- A part (or its parent) tagged or attributed BeamIgnore never blocks the beam.
local function ignored(instance: Instance): boolean
	local node: Instance? = instance
	for _ = 1, 3 do
		if not node or node == Workspace then
			break
		end
		if node:GetAttribute(MovementConfig.BeamIgnoreAttribute) == true or node:HasTag(MovementConfig.BeamIgnoreTag) then
			return true
		end
		node = node.Parent
	end
	return false
end

-- The rock's world box (measured once per rock; rocks never move).
local function boxOf(rock: Model): (Vector3, Vector3)
	local box = boxes[rock]
	if not box then
		local pivot = rock:GetPivot().Position
		local lo, hi = pivot - Vector3.new(2, 0, 2), pivot + Vector3.new(2, 3, 2)
		local first = true
		for _, d in rock:GetDescendants() do
			if d:IsA("BasePart") then
				local a, b = MovementLogic.partBounds(d.CFrame, d.Size)
				if first then
					lo, hi, first = a, b, false
				else
					lo = Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
					hi = Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
				end
			end
		end
		box = { Min = lo, Max = hi }
		boxes[rock] = box
	end
	return box.Min, box.Max
end

-- Can the player's beam reach the rock? Cached per (player, rock) for BeamLosCache seconds.
function BeamSight.canHit(player: Player, character: Model, root: BasePart, rock: Model, now: number): boolean
	local entry = cache[player]
	if entry and entry.Rock == rock and now - entry.At < MovementConfig.BeamLosCache then
		return entry.Clear
	end
	local head = character:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local lo, hi = boxOf(rock)
	rocksOfCast = rock.Parent
	local clear = MovementLogic.beamClear(eye, lo, hi, cast, ignored, MovementConfig)
	rocksOfCast = nil
	cache[player] = { Rock = rock, At = now, Clear = clear }
	return clear
end

-- The player left (or stopped mattering): drop their cached result.
function BeamSight.forget(player: Player)
	cache[player] = nil
end

-- Internals for the Lune tests only (tests/MiningLos.spec.luau).
BeamSight._test = {
	-- forget everything; casts find nothing until setRaycast gives them walls
	reset = function()
		table.clear(cache)
		table.clear(boxes)
		cast = function(_origin: Vector3, _direction: Vector3): MovementLogic.Hit?
			return nil
		end
	end,
	-- fn(origin, direction) -> { Instance, Position }? replaces Workspace:Raycast
	setRaycast = function(fn: MovementLogic.Cast)
		cast = fn
	end,
}

return BeamSight
