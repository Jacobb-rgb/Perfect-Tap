--[[
	MovementService: the server's movement check (docs/plans/MOVEMENT_CHECK_PLAN.md,
	security audit #3). Rollout step 1: logging only (MovementConfig.Enforce = false).

	- One loop over Players every MovementConfig.SampleInterval reads each
	  character's HumanoidRootPart position and feeds MovementLogic.step (the
	  rules live there): maxSpeed = (Humanoid.WalkSpeed, set by the server, +
	  the hoverboard being ridden) * SpeedFactor, the jump from JumpPower /
	  JumpHeight, the fastest belt while standing on a belt part (one downward
	  raycast, only for a move over the limit), seated / FallingDown / Ragdoll
	  / Physics states. No loops over parts.
	- serverMoved(player): EVERY server move of a character calls it (teleport
	  bar, PlotService.sendHome, BuildService lift-out, AccessService push-out;
	  a new character does it here). The samples start over for ServerMoveGrace.
	- isFlagged(player): ViolationsToFlag violations within ViolationWindow,
	  for FlagSeconds. FlagsToLog flags within FlagLogWindow write one warn
	  line with the UserId. Never a kick, never a pull-back (PullBack: step 3).
	- trustedPosition(player): the live root position; with Enforce on and the
	  player flagged, the last good sample instead. Range checks call
	  rangeOrigin(player, root.Position): the caller's live position while
	  Enforce is off (MiningService's beam range today).
	- Hoverboards: the character's MovementConfig.HoverboardAttribute (set by
	  the server while riding) adds HoverboardService.speedOf(player) when that
	  service exists, else MaxHoverboardSpeed.
	- State only for players in Players; cleared on PlayerRemoving (and the
	  table is weak-keyed).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local MovementConfig = require(Shared.Config.MovementConfig)
local MovementLogic = require(script.Parent.Parent.MovementLogic)

local MovementService = {}

type State = MovementLogic.State

-- studs per second of the fastest belt (the Express Conveyor)
MovementService.FastestBelt = MovementLogic.fastestBelt(MachineData.List, GameConfig.ConveyorSpeed)

local states: { [Player]: State } = setmetatable({}, { __mode = "k" }) :: any
local counters = { Samples = 0, Violations = 0, Flags = 0, Logs = 0 }

-- Swappable for the Lune tests.
local clock: () -> number = os.clock
local gravity: () -> number = function()
	return Workspace.Gravity
end
local logLine: (string) -> () = function(text: string)
	warn(text)
end
local boardSpeedOf: ((Player) -> number)? = nil -- nil = look for HoverboardService.speedOf once
local boardLookedUp = false

local function present(player: Player): boolean
	return player.Parent == Players
end

local function stateOf(player: Player, now: number): State?
	local state = states[player]
	if not state and present(player) then
		state = MovementLogic.newState(now)
		states[player] = state
	end
	return state
end

---------------------------------------------------------------- reading the character

-- The hoverboard's speed while the character rides one (0 on foot).
local function hoverboardSpeed(player: Player, character: Model): number
	if character:GetAttribute(MovementConfig.HoverboardAttribute) == nil then
		return 0
	end
	if not boardSpeedOf and not boardLookedUp then
		boardLookedUp = true
		-- loaded on first use: the mine floors package brings it (its speedOf(player) = the board's Speed)
		local module = script.Parent:FindFirstChild("HoverboardService")
		if module and module:IsA("ModuleScript") then
			local ok, service = pcall(require, module)
			if ok and type(service) == "table" and type((service :: any).speedOf) == "function" then
				boardSpeedOf = (service :: any).speedOf
			end
		end
	end
	local speedOf = boardSpeedOf
	if speedOf then
		local ok, speed = pcall(speedOf, player)
		if ok and type(speed) == "number" and speed == speed and speed >= 0 and speed < math.huge then
			return speed
		end
	end
	return MovementConfig.MaxHoverboardSpeed -- unknown board: the fastest
end

-- Is the character standing on a belt part? (one short raycast down)
local function beltBelow(character: Model, root: BasePart): boolean
	local params = RaycastParams.new()
	local ignore: { Instance } = { character }
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(ignore, items)
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -MovementConfig.BeltProbe, 0), params)
	return hit ~= nil and hit.Instance.CollisionGroup == MovementConfig.BeltGroup
end
local standsOnBelt = beltBelow -- swappable for the Lune tests

-- FallingDown / Ragdoll / Physics: knocked over or flung (skipped within MovementConfig.StateGraceBudget).
local function exemptState(state: Enum.HumanoidStateType): boolean
	return state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.Physics
end

local function logFlags(player: Player, state: State)
	counters.Logs += 1
	logLine(
		string.format(
			"[MovementService] UserId %d flagged %d times within %d s (worst move %.1f studs over the limit; logging only, nothing done)",
			player.UserId,
			MovementConfig.FlagsToLog,
			MovementConfig.FlagLogWindow,
			state.LoggedWorst
		)
	)
end

-- One sample of one player.
local function samplePlayer(player: Player, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local found = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not found or not found:IsA("BasePart") or humanoid.Health <= 0 then
		return -- no live character: the next one starts over (new Character)
	end
	local root = found :: BasePart
	local state = stateOf(player, now)
	if not state then
		return
	end
	counters.Samples += 1
	local sample: MovementLogic.Sample = {
		Position = root.CFrame.Position,
		Character = character,
		Seated = humanoid.SeatPart ~= nil or humanoid.Sit,
		Exempt = exemptState(humanoid:GetState()),
		WalkSpeed = humanoid.WalkSpeed,
		BoardSpeed = hoverboardSpeed(player, character),
		JumpHeight = MovementLogic.jumpHeight(humanoid.UseJumpPower, humanoid.JumpPower, humanoid.JumpHeight, gravity(), MovementConfig),
		BeltSpeed = MovementService.FastestBelt,
		OnBelt = function(): boolean
			return standsOnBelt(character, root)
		end,
	}
	local outcome, flagged, log = MovementLogic.step(state, sample, now, MovementConfig)
	if outcome == "Violation" then
		counters.Violations += 1
	end
	if flagged then
		counters.Flags += 1
	end
	if log then
		logFlags(player, state)
	end
end

local function sampleAll()
	local now = clock()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			samplePlayer(player, now)
		end)
		if not ok then
			warn("[MovementService] sample failed for " .. player.Name .. ": " .. tostring(err))
		end
	end
end

---------------------------------------------------------------- API

-- Call at EVERY server move of a character (PivotTo and the like): the check starts over there.
function MovementService.serverMoved(player: Player)
	local now = clock()
	local state = stateOf(player, now)
	if state then
		MovementLogic.serverMoved(state, now, MovementConfig)
	end
end

function MovementService.isFlagged(player: Player): boolean
	local state = states[player]
	return state ~= nil and MovementLogic.isFlagged(state, clock())
end

-- The position range checks should use: the live root position, or (Enforce on, flagged) the last good sample.
function MovementService.trustedPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local live = if root and root:IsA("BasePart") then root.CFrame.Position else nil
	if not MovementConfig.Enforce then
		return live
	end
	local state = states[player]
	local trusted = if state then MovementLogic.trusted(state, clock()) else nil
	return trusted or live
end

--[[
	What a range check measures from: `live` (the root position the caller
	already read) while MovementConfig.Enforce is off, else trustedPosition.
	The one-liner for every range check: root.Position ->
	MovementService.rangeOrigin(player, root.Position).
]]
function MovementService.rangeOrigin(player: Player?, live: Vector3): Vector3
	if not MovementConfig.Enforce or not player then
		return live
	end
	return MovementService.trustedPosition(player) or live
end

-- Server-wide counts since the start (samples, violations, flags, log lines).
function MovementService.stats(): { Samples: number, Violations: number, Flags: number, Logs: number }
	return table.clone(counters)
end

local function forget(player: Player)
	states[player] = nil
end

---------------------------------------------------------------- lifecycle

function MovementService.init()
	local function watch(player: Player)
		stateOf(player, clock()) -- the join grace counts from here
		player.CharacterAdded:Connect(function()
			MovementService.serverMoved(player) -- respawn: placed by the server
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(forget)
end

function MovementService.start()
	while true do
		task.wait(MovementConfig.SampleInterval)
		sampleAll()
	end
end

-- Internals for the Lune tests only (tests/Movement.spec.luau).
MovementService._test = {
	reset = function()
		table.clear(states)
		for key in counters do
			counters[key] = 0
		end
		clock = os.clock
		gravity = function()
			return Workspace.Gravity
		end
		logLine = function(text: string)
			warn(text)
		end
		boardSpeedOf = nil
		boardLookedUp = false
		standsOnBelt = beltBelow
	end,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setGravity = function(fn: () -> number)
		gravity = fn
	end,
	setLog = function(fn: (string) -> ())
		logLine = fn
	end,
	setBoardSpeed = function(fn: ((Player) -> number)?)
		boardSpeedOf = fn
		boardLookedUp = true
	end,
	setBeltCheck = function(fn: (Model, BasePart) -> boolean)
		standsOnBelt = fn
	end,
	sample = samplePlayer,
	forget = forget,
	state = function(player: Player): State?
		return states[player]
	end,
}

return MovementService
