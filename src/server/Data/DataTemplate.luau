--[[
	Default save data for a new player. When you add a field, add it here;
	DataService fills missing fields into old saves automatically
	(record tables only: lists such as Podiums are repaired by Migrations).
	Keep it small: everything here is written to the DataStore.
]]

local DataTemplate = {
	Version = 3, -- Data/Migrations brings older saves up to this

	Coins = 0, -- may hold fractions (podium income per second)
	TotalEarned = 0,

	-- blaster (design v2): level 1..10 and the ore it was forged from ("" = rusty starter)
	BlasterLevel = 1,
	BlasterOre = "",
	CarryLevel = 1,

	-- upgrades bought with coins
	Upgrades = {
		Bellows = 0, -- machine speed level
		ExtraSlots = 0, -- machine slot upgrades bought
		PenLevel = 0, -- Ore Pen capacity level (EconomyConfig.Pen)
		-- pen automation (EconomyConfig.PenAutomation): 0 none, 1 the sorting
		-- billboard at the pen, 2 = 1 + the train's Direct Unload onto the TRAIN chute
		-- (readers use >= levels: a newer server may add more)
		PenAutomation = 0,
		-- the mine elevator (ElevatorService), bought once for MineFloors.Elevator.Price:
		-- rides to every unlocked floor (floors 4-5 are reachable only this way)
		Elevator = false,
	},
	-- Tech shop machine upgrades, per machine type (MachineData Upgrades):
	-- { [machineId] = { Speed = level?, Quality = level? } } (a missing level is 0)
	MachineUpgrades = {},
	-- what clean ore the Iron Box keeps (into the pen) and the pen's sorting
	-- billboard marks as kept (MachineData.Keep / keeps / keepsOre): "RarePlus"
	-- (Rare and better), "List" (the player's choices on KeepList; ores not on
	-- it follow the Rare+ rule) or "All". Dirty ore, crushed ore and ingots are
	-- never kept, they always pass on.
	KeepMode = "RarePlus",
	-- the player's choices for "List" mode: { [oreId] = true (keep) | false (send on) }
	KeepList = {},
	-- the Foundry on the base: ingots waiting to be forged into blasters,
	-- a list of { K = "Ingot", O = oreId, G = grade? } (at most GameConfig.MaxFoundryStock;
	-- FoundryAction "Take" moves them back to the pen)
	Foundry = {
		Stock = {},
	},

	-- machines: bought but not placed { [machineId] = count 1..MachineData.MaxInventory (999) } (no zero keys)
	MachineInventory = {},
	-- placed machines on the plot: { { Id, X, Z, R, In?, Out? } } (min grid cell +
	-- rotation 0-3). In = input queue (In[1] is being worked, max 4), Out = finished
	-- items waiting to leave (max 4); both are lists of { K, O, G?, R? }, nil when empty.
	PlacedMachines = {},
	StarterKitGiven = false,

	-- the Ore Pen on the base: every stored item, one list
	-- { { K = kind, O = oreId, G = grade?, R = recipe? } }
	Storage = {},
	-- the pen's sorting billboard (Upgrades.PenAutomation >= 1) sends unkept
	-- arrivals out of the PEN chute while this is on (PenAction "AutoSort";
	-- readers treat anything but false as on)
	AutoSort = true,
	-- what stands on each podium: an ItemData.storageKey ("Clean|Gold|Pristine|") or ""
	Podiums = { "", "", "", "" },
	-- os.time() of the last moment the podiums were paying (offline earnings)
	LastSeen = 0,

	-- your ore train (TrainConfig): Cargo waits at the station; TripCargo is on
	-- the moving train (saved, so leaving mid-trip never loses ore); trip times
	-- are os.time() seconds (0 = no trip)
	Train = {
		CapacityLevel = 0,
		SpeedLevel = 0,
		Cargo = {},
		TripCargo = {},
		TripDepartAt = 0,
		TripArriveAt = 0,
	},

	-- progression
	Discovered = {}, -- [oreId] = true
	Stats = {
		OresMined = 0,
		RocksBroken = 0,
		OresCleaned = 0,
		FlawlessCleans = 0,
		IngotsSmelted = 0,
		BlastersForged = 0,
		ItemsSold = 0,
		PodiumEarned = 0,
		TrainTrips = 0, -- trains unloaded into the Ore Pen (TrainService)
		PlaySeconds = 0,
	},
	Tutorial = { Step = 1, Done = false },
	Daily = { LastClaimDay = 0, Streak = 0 },
	Badges = {}, -- [badgeKey] = true (local cache, Roblox is the source of truth)
	GroupRewardClaimed = false,
	ForgeName = "", -- raw text, always filtered by TextService before showing

	-- monetization: purchase ids already granted (never grant twice)
	Purchases = {}, -- [purchaseId] = os.time()
	PurchaseCount = 0,
}

return DataTemplate
