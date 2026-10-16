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
	},

	-- machines: bought but not placed { [machineId] = count 1..999 } (no zero keys)
	MachineInventory = {},
	-- placed machines on the plot: { { Id, X, Z, R, In?, Out? } } (min grid cell +
	-- rotation 0-3). In = input queue (In[1] is being worked, max 4), Out = finished
	-- items waiting to leave (max 4); both are lists of { K, O, G?, R? }, nil when empty.
	PlacedMachines = {},
	StarterKitGiven = false,

	-- the Ore Pen on the base: every stored item, one list
	-- { { K = kind, O = oreId, G = grade?, R = recipe? } }
	Storage = {},
	-- what stands on each podium: an ItemData.storageKey ("Clean|Gold|Pristine|") or ""
	Podiums = { "", "", "", "" },
	-- os.time() of the last moment the podiums were paying (offline earnings)
	LastSeen = 0,

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
