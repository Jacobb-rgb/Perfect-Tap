--[[
	General tuning and safety limits. Server and client both read this.
]]

local GameConfig = {
	Version = "0.1.0",
	CurrencyName = "Coins",
	StartingCoins = 0,

	-- Players / plots
	MaxPlayers = 8,
	PlotCells = 12, -- plot is PlotCells x PlotCells grid cells
	CellSize = 4, -- studs per grid cell

	-- Mining
	MineRange = 13, -- max studs from character to the node surface
	SwingLeniency = 0.85, -- server accepts swings at 85% of the cooldown (network jitter)

	-- Physical items (performance)
	MaxLooseItemsPerPlayer = 40, -- above this, the oldest loose item is moved to storage
	ItemSleepAfter = 10, -- seconds at rest before an item is anchored ("asleep")
	ItemSleepSpeed = 0.15, -- studs/s, below this an item counts as resting
	PickupRange = 11,
	ThrowSpeedMin = 22,
	ThrowSpeedMax = 52,
	ItemFallKillY = -200, -- items below this are rescued back to their owner's plot

	-- Machines
	MachineIntakeQueue = 4, -- items a machine can buffer
	ConveyorSpeed = 7, -- studs per second
	StorageCrateCapacity = 60,
	MaxStoredItems = 300, -- hard cap across all crates (DataStore size safety)

	-- Cleaning minigame (server sanity limits)
	CleaningTimeout = 300, -- seconds before an open session is cancelled
	CleaningMinSeconds = 3, -- no human can finish faster than this
	MaxTracePoints = 400, -- per chisel cut
	MaxPolishSamples = 1500,

	-- Remotes
	DefaultRateLimit = { Rate = 8, Burst = 16 }, -- events per second per player

	-- Saving
	AutosaveInterval = 120,
	SaveInStudio = true, -- needs "Enable Studio Access to API Services"
}

return GameConfig
