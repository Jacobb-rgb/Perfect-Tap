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

	-- Physical items (performance)
	MaxLooseItemsPerPlayer = 30, -- above this, the oldest loose item is moved to storage
	ServerOwnershipAfter = 3, -- seconds after a drop/throw before the server takes back item physics
	PickupRange = 11,
	ThrowSpeedMin = 22,
	ThrowSpeedMax = 52,
	ItemFallKillY = -60, -- items below this fell out of the world and are rescued (lowest floor is -40)

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
