--[[
	General tuning and safety limits. Server and client both read this.
]]

export type DevKitEntry = { Id: string, X: number, Z: number, R: number }
export type DevKit = { Layout: { DevKitEntry }, Inventory: { [string]: number } }

-- Studio-only test layout (MachineService adds it once, together with the
-- StarterKit, and only in Studio sessions whose saves live in memory).
-- Set it to false to switch it off.
local STUDIO_DEV_KIT: DevKit | false = {
	Layout = {
		{ Id = "Crusher", X = 4, Z = 9, R = 0 },
		{ Id = "AutoCleaner", X = 0, Z = 10, R = 0 },
		{ Id = "BlastFurnace", X = 7, Z = 8, R = 0 },
	},
	Inventory = { Conveyor = 24, ClayFurnace = 1 },
}

local GameConfig = {
	Version = "0.1.0",
	CurrencyName = "Coins",
	StartingCoins = 0,

	-- Players / plots
	MaxPlayers = 8,
	PlotCells = 12, -- plot is PlotCells x PlotCells grid cells
	CellSize = 4, -- studs per grid cell

	-- Physical items (performance)
	MaxLooseItemsPerPlayer = 30, -- loose items per player on bases (machines / chutes stop below it) and, apart, away from bases (rocks stop giving ore)
	ServerOwnershipAfter = 3, -- seconds after a drop/throw before the server takes back item physics
	PickupRange = 11,
	ThrowSpeedMin = 22,
	ThrowSpeedMax = 52,
	ItemFallKillY = -60, -- items below this fell out of the world and are rescued (lowest floor is -40)

	-- Machines
	MachineIntakeQueue = 4, -- items a machine can buffer (includes the item being worked)
	ConveyorSpeed = 7, -- studs per second
	StorageCrateCapacity = 60, -- every placed crate adds this much to the shared store
	MaxStoredItems = 300, -- hard cap across all crates (DataStore size safety)
	MachineTick = 0.1, -- seconds between machine job/output updates
	MinProcessTime = 0.5, -- no upgrade makes a job faster than this
	OutputPop = { Forward = 6, Up = 4 }, -- velocity of an item leaving a machine's front
	OutputRetry = 1, -- seconds before a blocked output tries again
	LooseHeadroom = 2, -- machines pause output this many items below the loose-item cap

	-- Intake (items going into machines)
	IntakeTick = 0.2, -- seconds between intake scans
	IntakeMargin = 0.4, -- extra studs around a hopper's intake box
	FeedReachBelt = 1.6, -- belt-end feeder box: studs back onto the belt
	FeedReachInto = 1.5, -- belt-end feeder box: studs into the machine's cell
	RejectPop = { Out = 8, Up = 14 }, -- a refused item dropped into a hopper bounces out the front
	BeltRejectPop = { Side = 9, Up = 7 }, -- a refused item on a belt is pushed off the side
	RejectCooldown = 1.5, -- seconds before the same item can be refused again
	WrongHintCooldown = 10, -- seconds between wrong-item hints (per player, per machine type)
	ForeignItemReturn = 8, -- seconds before an item on someone else's plot goes back to its owner

	-- Range and anti-cheat
	MachineUseRange = 14, -- studs from a machine to use its actions
	BuildRange = 70, -- studs from your plot centre to build
	AntiTeleportRange = 40, -- an item's owner must be this close for it to enter a machine
	MaxItemSpeed = 75, -- studs/s an item can plausibly travel after a drop or throw
	PlausibleSlack = 6, -- extra studs allowed on top of MaxItemSpeed
	MaxItemTravel = 90, -- further than this from its release point, an item snaps back
	ClientPhysicsRange = 80, -- owners further away never simulate their items (below StreamingMinRadius 96)

	-- Conveyors
	ConveyorStuckSpeed = 0.6, -- slower than this on a belt counts as stuck
	ConveyorStuckSeconds = 1.5, -- stuck this long gets a nudge
	ConveyorMaxNudges = 5, -- this many nudges...
	ConveyorNudgeWindow = 30, -- ...within this many seconds pushes the item off the belt

	-- Selling and storage (the Ore Pen = data.Storage, design v2)
	SellComboWindow = 0.8, -- sales closer together than this count as one combo
	SellOthersRadius = 60, -- other players this close see the sell puff
	StorageTakeMax = 5, -- items per Take request

	-- Foundry (step 3): ingots wait in data.Foundry.Stock until a blaster is forged.
	-- The FOUNDRY chute (BaseLayout.Chutes.Foundry; owner's items only) puts an
	-- ingot the next blaster level can use (rarity >= that level's
	-- Recipe.MinRarity) into the stock while it is below MaxFoundryStock; every
	-- other item (other ingots, ore, any ingot once the blaster is at its top
	-- level) and usable ingots once the stock is full go into the Ore Pen. Only
	-- when the pen is full too does the item wait on the cell, and the
	-- receiver shows why ("Ore Pen full"), so a full stock never jams the line.
	-- Forging uses exactly Recipe.Ingots usable ingots: one of the skin ore
	-- (its lowest-value ingot) plus the lowest-value other usable ingots
	-- (ItemData.value ascending, ties in stock order), so the best ones stay.
	-- In the same step a successful forge moves the stock ingots the NEW next
	-- level can't use into the pen (as many as fit; the rest stay until
	-- FoundryAction "Take" moves them). "Take" moves stock ingots to the pen.
	MaxFoundryStock = 60, -- DataStore safety cap (Migrations moves extras to the pen)

	-- Anvil
	AnvilTimeout = 60, -- seconds before a forging session is cancelled
	AnvilWalkAway = 20, -- studs from the anvil that cancel a session
	AnvilMinStrikeGap = 0.18, -- seconds; no human hammers faster than this
	AnvilMinSecondsPerHit = 0.3, -- the last strike comes at least Hits x this after the start

	-- Studio testing
	StudioDevKit = STUDIO_DEV_KIT,

	-- Cleaning minigame (server sanity limits)
	CleaningTimeout = 300, -- seconds before an open session is cancelled
	CleaningMinSeconds = 3, -- no human can finish faster than this
	MaxTracePoints = 400, -- per chisel cut
	MaxPolishSamples = 1500,

	-- Remotes
	DefaultRateLimit = { Rate = 8, Burst = 16 }, -- events per second per player

	-- Saving (docs/SAVE_AUDIT.md)
	AutosaveInterval = 60, -- seconds: also refreshes the session lock (at most this much progress lost on a crash)
	StaleLockSeconds = 180, -- a lock not refreshed this long belongs to a crashed server (3 missed autosaves)
	SaveInStudio = true, -- needs "Enable Studio Access to API Services"
	-- Studio saves into its own DataStore (TerraForge_PlayerData_Studio) so command-bar tests never
	-- touch a real save; true = Studio reads and writes the live store (only to look into a live save)
	StudioLiveData = false,
}

return GameConfig
