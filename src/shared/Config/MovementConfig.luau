--[[
	Movement check and beam line of sight (docs/plans/MOVEMENT_CHECK_PLAN.md,
	security audit #3 and #12). MovementService (server) samples every
	character, MiningService asks it for the range position and casts the
	beam's line of sight. Pure rules: src/server/MovementLogic.luau.

	Rollout (the plan's "Rollout"):
	  step 1 (now)  Enforce = false: violations and flags are counted and
	                logged, trustedPosition is always the live position.
	  step 2        Enforce = true: while flagged, range checks use the last
	                good sample (MiningService today; the other services get
	                their one-line change then).
	  step 3        PullBack: a soft pull-back after repeated flags. Not built
	                yet: keep it false.
	Never a kick.
]]

local MovementConfig = {}

-- rollout switches
MovementConfig.Enforce = false -- false: trustedPosition returns the live position (logging only)
MovementConfig.PullBack = false -- step 3, not built yet
MovementConfig.BeamLos = true -- MiningService: no beam damage through walls

-- sampling
MovementConfig.SampleInterval = 0.3 -- seconds between two samples of every character (one loop over players)
MovementConfig.Slack = 6 -- studs on top of maxSpeed * dt (lag, physics pushes)
MovementConfig.SpeedFactor = 1.15 -- maxSpeed = (Humanoid.WalkSpeed + hoverboard speed) * SpeedFactor
MovementConfig.MaxWalkSpeed = 50 -- an unreadable WalkSpeed counts as this (Bonuses.walkSpeed tops out at 50)
MovementConfig.MaxHoverboardSpeed = 38 -- an unknown board counts as this (the fastest board, Royal Phoenix)
MovementConfig.HoverboardAttribute = "Hoverboard" -- character attribute while riding (HoverboardData.Attribute)
MovementConfig.UpSlack = 4 -- studs of upward move on top of the Humanoid's jump height
MovementConfig.ClimbPerStud = 1 -- upward studs allowed per stud of possible walking (stairs and ramps up to 45 degrees)
MovementConfig.DefaultJumpHeight = 7.2 -- an unreadable jump counts as this (the Roblox default JumpHeight)
MovementConfig.MaxJumpHeight = 50 -- a jump is never trusted above this
MovementConfig.BeltGroup = "Conveyors" -- collision group of every belt part (ConveyorService.CollisionGroup)
MovementConfig.BeltProbe = 8 -- studs the belt check looks down from the HumanoidRootPart

-- grace windows (the sample just resets)
MovementConfig.ServerMoveGrace = 2 -- seconds after MovementService.serverMoved (teleports, push-outs, respawns)
MovementConfig.JoinGrace = 5 -- seconds after joining (streaming, loading)
MovementConfig.StateGraceBudget = 4 -- seconds of FallingDown / Ragdoll / Physics state that skip the check...
MovementConfig.StateGraceWindow = 30 -- ...within this many seconds (the client reports its Humanoid state)

-- violations and flags
MovementConfig.ViolationsToFlag = 3 -- this many violations...
MovementConfig.ViolationWindow = 10 -- ...within this many seconds flag the player
MovementConfig.FlagSeconds = 30 -- a flag lasts this long
MovementConfig.FlagsToLog = 5 -- this many flags...
MovementConfig.FlagLogWindow = 300 -- ...within this many seconds write one server log line with the UserId

-- beam line of sight (MiningService)
MovementConfig.BeamLosCache = 0.5 -- seconds a (player, rock) result is reused
MovementConfig.BeamStopShort = 1.5 -- the ray stops this far before the rock (a wall behind it never counts)
MovementConfig.BeamIgnoreTag = "BeamIgnore" -- CollectionService tag: never blocks the beam
MovementConfig.BeamIgnoreAttribute = "BeamIgnore" -- attribute = true: never blocks the beam
MovementConfig.BeamMaxPasses = 2 -- casts per aim line (a BeamIgnore attribute hit casts on behind it)

return MovementConfig
