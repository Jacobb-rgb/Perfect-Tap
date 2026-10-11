--[[
	Default save data for a new player. When you add a field, add it here;
	DataService fills missing fields into old saves automatically.
	Keep it small: everything here is written to the DataStore.
]]

local DataTemplate = {
	Version = 1,

	Coins = 0,
	TotalEarned = 0,

	-- tools
	Pickaxe = "StonePick",
	OwnedPickaxes = { StonePick = true },
	CarryLevel = 1,

	-- upgrades bought with coins
	Upgrades = {
		Bellows = 0, -- machine speed level
		ExtraSlots = 0, -- machine slot upgrades bought
	},

	-- machines: bought but not placed { [machineId] = count }
	MachineInventory = {},
	-- placed machines on the plot: { { Id, X, Z, R } } (grid cell + rotation 0-3)
	PlacedMachines = {},
	StarterKitGiven = false,

	-- items in storage crates: { { K = kind, O = oreId, G = grade?, R = recipe? } }
	Storage = {},

	-- progression
	Discovered = {}, -- [oreId] = true
	Stats = {
		OresMined = 0,
		OresCleaned = 0,
		FlawlessCleans = 0,
		IngotsSmelted = 0,
		GearForged = 0,
		ItemsSold = 0,
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
