--[[
	Default save data for a new player. When you add a field, add it here;
	DataService fills missing fields into old saves automatically
	(record tables only: lists such as Podiums are repaired by Migrations).
	Keep it small: everything here is written to the DataStore.
]]

local DataTemplate = {
	Version = 6, -- Data/Migrations brings older saves up to this (4: the 16-cell build grid; 5: the player LEVEL; 6: one Furnace)

	Coins = 0, -- may hold fractions (podium income per second)
	-- the part of Coins bought with Robux and not spent yet (always <= Coins; spent
	-- last, kept through a rebirth: owner 2026-10-20)
	PaidCoins = 0,
	-- crystal shards (the Crystal Extractor finds them; the Enchant shop spends them)
	Shards = 0,
	-- crushed piles a Crusher made that the Crystal Extractor hasn't shaken yet
	-- (ProcessingService: each pile gets ONE shard roll, a loop finds nothing)
	ShardRolls = 0,
	TotalEarned = 0,

	-- blaster (design v2): level 1..10 and the ore it was forged from ("" = rusty starter)
	BlasterLevel = 1,
	BlasterOre = "",
	-- (CarryLevel is gone: carrying is the Backpack gear line, Migrations folds it in)

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
		-- rides to every unlocked floor (floors 4-6 are reachable only this way)
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
	-- placed machines on the plot: { { Id, X, Z, R, In?, Out?, C? } } (min grid cell +
	-- rotation 0-3). In = input queue (In[1] is being worked, max 4), Out = finished
	-- items waiting to leave (max 4); both are lists of { K, O, G?, R? }, nil when empty.
	-- C = the machine's own setting (Sorter: the lowest rarity sent right, a Rarity Order).
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

	-- steps 6-7 (rules in Shared/Config: GearConfig, EnchantConfig, BoostConfig,
	-- GolemConfig, WheelConfig, ArtifactConfig); Migrations keeps them sane
	-- gear levels 0..GearConfig.MaxLevel, bought at the Gear shop
	Gear = { Boots = 0, HelmetLamp = 0, Backpack = 0, Gloves = 0, Magnet = 0 },
	-- blaster enchants: Owned = { [enchantId] = tier }, Slots = exactly
	-- EnchantConfig.MaxSlots strings (an owned enchant id or "" = empty)
	Enchants = { Owned = {}, Slots = { "", "", "", "" } },
	-- luck boosts: os.time() second each one runs out (0 = never ran)
	Boosts = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 },
	-- golem pets: Owned = { { Id = number, Kind = golemId } }, Equipped = { Id }
	-- (at most GolemConfig.EquipSlots), NextId = the next Id to hand out, Pending = paid
	-- golems a Royal capsule receipt rolled past GolemConfig.MaxSaved (CapsuleService wakes them)
	Golems = { Owned = {}, Equipped = {}, NextId = 1, Pending = {} },
	-- the daily wheel: os.time() second the next free spin is ready (0 = now);
	-- Spins = the bought spins held (Robux, WheelService; used after the free one)
	Wheel = { NextSpinAt = 0, Spins = 0 },
	-- daily / weekly quests (QuestService, QuestLogic): Day / Week = the UTC day / week number
	-- the lists are for; Daily / Weekly = { { Id, Base (the Stat when given), Goal, Claimed } }
	-- (QuestLogic.refresh rerolls a stale or broken list, so no migration is needed)
	Quests = { Day = 0, Daily = {}, Week = 0, Weekly = {} },
	-- the 7-day login streak: Day = the streak day last claimed (1..7, 0 = never),
	-- Last = the UTC day number of that claim (a missed day starts at day 1 again)
	Streak = { Day = 0, Last = 0 },
	-- the Starter Pack (Robux, once per account: StarterPackService): BoughtAt = os.time() of
	-- the first grant (0 = not bought), Count = receipts granted (a second one only when two
	-- prompts were open at once)
	StarterPack = { BoughtAt = 0, Count = 0 },
	-- artifacts: Found = { [artifactId] = count }, Chapters = { [collectionId] = true } (read)
	Artifacts = { Found = {}, Chapters = {} },

	-- progression
	Discovered = {}, -- [oreId] = true
	Stats = {
		OresMined = 0,
		RocksBroken = 0,
		OresCleaned = 0,
		FlawlessCleans = 0,
		IngotsSmelted = 0,
		BlastersForged = 0,
		BlastersBought = 0, -- blaster cases bought at the Blaster Vault (VaultService)
		ItemsSold = 0,
		PodiumEarned = 0,
		TrainTrips = 0, -- trains unloaded into the Ore Pen (TrainService)
		PlaySeconds = 0,
		ArtifactsFound = 0, -- every artifact find, duplicates too (the ARTIFACTS board)
		CapsulesOpened = 0, -- golems woken from capsules (also free ones)
		WheelSpins = 0,
		WheelOres = 0, -- dirty ores the wheel's ore prize put into the Ore Pen (the tutorial doesn't count them)
		StarsEarned = 0, -- every Forge Star a rebirth paid (RebirthConfig.reset)
		BestBlaster = 0, -- the highest blaster level before a rebirth (BlasterData.priceLevel)
		RunForged = 0, -- the highest blaster level forged at the Foundry this rebirth run
		RunPaid = false, -- a blaster level was bought with Robux this run (RebirthConfig.reachedOf)
		BlastersPaid = 0, -- blaster levels bought with Robux (VaultService.grantNext "Robux")
		BlasterCredit = 0, -- Robux of off-band blaster receipts not yet spent on start lifts (VaultService.spendCredit)
	},
	-- the player LEVEL (LevelConfig, LevelService): never reset by a rebirth. Xp = towards
	-- the next level, Seen = { [counter id] = the value at the last look }, Ready = false on a
	-- save from before levels (its first look backfills the XP silently)
	Level = { Level = 1, Xp = 0, Seen = {}, Ready = false },
	Tutorial = { Step = 1, Done = false },
	-- (Daily, the 7-day Ember Chest streak, is retired: the daily wheel replaced it, Migrations removes it)
	-- the side menu's SETTINGS (SettingsConfig; SettingsService repairs it on load)
	Settings = { Music = 0.6, Sfx = 0.8, Shake = true, Rumble = true, FastSpin = false, ReduceMotion = false },
	-- the ORE CODEX's NEW badges (CodexService): Seen = { [oreId] = true } the discovered ores
	-- the player has looked at; Ready = false on a save made before this record (its
	-- discovered ores then count as seen, once)
	OreCodex = { Seen = {}, Ready = false },
	Badges = {}, -- [badgeKey] = true (local cache, Roblox is the source of truth)
	GroupRewardClaimed = false,
	ForgeName = "", -- raw text, always filtered by TextService before showing

	-- rebirth "STAR FORGE" (RebirthConfig, RebirthService): how many rebirths, the
	-- unspent Forge Stars and the Star Shop perks { [perkId] = level }
	Rebirths = 0,
	Stars = 0,
	StarPerks = {},
	-- the Plot Glow colour the plot shows (a RebirthConfig.GlowColors id, "" = off)
	PlotGlow = "",
	-- the STAR blasters (StarBlasterData, RebirthService), kept through every rebirth:
	-- RebirthWeapons = { [id] = true } the ones you own, RebirthWeaponPasses = { [id] = true }
	-- the ones a game pass gave (a refund takes back only those), StarBlaster = the
	-- equipped one ("" = your forged blaster)
	RebirthWeapons = {},
	RebirthWeaponPasses = {},
	StarBlaster = "",

	-- hoverboards (HoverboardService): Owned = { [boardId] = true } (bought once,
	-- coins or a game pass), Equipped = the board RIDE uses ("" = none),
	-- Passes = { [boardId] = true } for the boards a game pass gave (a refunded
	-- pass takes only those back)
	Hoverboards = { Owned = {}, Equipped = "", Passes = {} },

	-- monetization: purchase ids already granted (never grant twice)
	Purchases = {}, -- [purchaseId] = os.time()
	-- what each granted receipt was (support re-grants after a restore, docs/SUPPORT.md):
	-- [purchaseId] = { Product = MonetizationConfig key, At = os.time() }; trimmed with Purchases
	PurchaseLog = {},
	PurchaseCount = 0,
}

return DataTemplate
