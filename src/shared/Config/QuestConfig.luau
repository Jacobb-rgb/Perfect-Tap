--[[
	Daily / weekly quests and the 7-day login streak (docs/plans/DAILY_QUESTS_PLAN.md).
	All numbers live here; the rules are in Shared/Quests/QuestLogic.

	- 3 daily quests (new ones at 00:00 UTC) and 1 weekly quest (Monday 00:00
	  UTC), picked from Daily / Weekly by a seeded roll per player + day (week)
	  and saved, so they never change on a rejoin.
	- A quest counts one data.Stats counter from the moment it was given
	  (Stat). Goal at blaster level L: nice(Amount * (1 + Growth * (L - 1)));
	  Income quests: income per second * Income seconds (left out while the
	  player earns nothing). MinLevel: the blaster level it needs.
	  Capsules = true: left out where paid random items are restricted.
	- Rewards are paid at claim time. Coins = Seconds of podium income, never
	  under the floor (QuestLogic.coins). Never Robux-only items, nothing for
	  likes / favorites. Day 7's capsule is random: its odds are shown
	  (CapsuleConfig.odds, the ODDS panel).
]]

local QuestConfig = {}

export type QuestDef = {
	Id: string,
	Stat: string, -- a data.Stats counter
	Text: string, -- "%s" = the goal ("Mine %s ores")
	Short: string, -- the card's small label ("MINING")
	Amount: number?, -- the goal at blaster level 1
	Growth: number?, -- + this share of Amount per blaster level above 1
	Income: number?, -- the goal is this many seconds of podium income (instead of Amount)
	Weight: number?, -- roll weight (default 1)
	MinLevel: number?, -- blaster level needed (default 1)
	Capsules: boolean?, -- opens capsules: not where paid random items are restricted
	Paint: string, -- PopTheme paint of the card's badge
	Icon: string, -- IconAssets picture on the badge
}

export type Reward = {
	Coins: number?, -- seconds of podium income (QuestLogic.coins)
	Shards: number?,
	Boost: string?, -- BoostConfig kind ("TripleLucky" | "HexaLucky")
	BoostSeconds: number?,
	Capsule: string?, -- a free capsule of this kind (CapsuleConfig id)
}

export type StreakDay = Reward & { Day: number, Label: string, Paint: string, Icon: string }

QuestConfig.DailyCount = 3
QuestConfig.WeeklyCount = 1
QuestConfig.DaySeconds = 86400

QuestConfig.Daily = {
	{
		Id = "Mine",
		Icon = "ore_raw",
		Stat = "OresMined",
		Text = "Mine %s ores",
		Short = "MINING",
		Amount = 100,
		Growth = 0.08,
		Paint = "Orange",
	},
	{
		Id = "Rocks",
		Icon = "ore_copper",
		Stat = "RocksBroken",
		Text = "Break %s rocks",
		Short = "MINING",
		Amount = 35,
		Growth = 0.08,
		Paint = "Red",
	},
	{
		Id = "Clean",
		Icon = "ore_silver",
		Stat = "OresCleaned",
		Text = "Clean %s ores",
		Short = "CLEANING",
		Amount = 8,
		Growth = 0.05,
		Paint = "Blue",
	},
	{
		Id = "Flawless",
		Icon = "medal",
		Stat = "FlawlessCleans",
		Text = "Get %s Flawless cleans",
		Short = "CLEANING",
		Amount = 2,
		Growth = 0,
		Weight = 0.6,
		Paint = "Teal",
	},
	{
		Id = "Smelt",
		Icon = "ingot_gold",
		Stat = "IngotsSmelted",
		Text = "Smelt %s ingots",
		Short = "FACTORY",
		Amount = 12,
		Growth = 0.08,
		MinLevel = 2,
		Paint = "Yellow",
	},
	{
		Id = "Sell",
		Icon = "coins",
		Stat = "ItemsSold",
		Text = "Sell %s items",
		Short = "TRADE",
		Amount = 30,
		Growth = 0.08,
		Paint = "Green",
	},
	{
		Id = "Train",
		Icon = "train",
		Stat = "TrainTrips",
		Text = "Bring home %s trains",
		Short = "TRAIN",
		Amount = 4,
		Growth = 0,
		Paint = "Purple",
	},
	{
		Id = "Podium",
		Icon = "podium",
		Stat = "PodiumEarned",
		Text = "Earn %s on podiums",
		Short = "PODIUMS",
		Income = 900,
		Paint = "Yellow",
	},
	{
		Id = "Capsules",
		Icon = "golem",
		Stat = "CapsulesOpened",
		Text = "Open %s golem capsules",
		Short = "GOLEMS",
		Amount = 2,
		Growth = 0,
		Capsules = true,
		Paint = "Pink",
	},
	{
		Id = "Wheel",
		Icon = "wheel",
		Stat = "WheelSpins",
		Text = "Spin the daily wheel",
		Short = "WHEEL",
		Amount = 1,
		Growth = 0,
		Weight = 0.5,
		Paint = "Pink",
	},
} :: { QuestDef }

QuestConfig.Weekly = {
	{
		Id = "WMine",
		Icon = "ore_raw",
		Stat = "OresMined",
		Text = "Mine %s ores",
		Short = "MINING",
		Amount = 1200,
		Growth = 0.08,
		Paint = "Orange",
	},
	{
		Id = "WRocks",
		Icon = "ore_copper",
		Stat = "RocksBroken",
		Text = "Break %s rocks",
		Short = "MINING",
		Amount = 400,
		Growth = 0.08,
		Paint = "Red",
	},
	{
		Id = "WClean",
		Icon = "ore_silver",
		Stat = "OresCleaned",
		Text = "Clean %s ores",
		Short = "CLEANING",
		Amount = 80,
		Growth = 0.05,
		Paint = "Blue",
	},
	{
		Id = "WFlawless",
		Icon = "medal",
		Stat = "FlawlessCleans",
		Text = "Get %s Flawless cleans",
		Short = "CLEANING",
		Amount = 12,
		Growth = 0,
		Weight = 0.6,
		Paint = "Teal",
	},
	{
		Id = "WSmelt",
		Icon = "ingot_gold",
		Stat = "IngotsSmelted",
		Text = "Smelt %s ingots",
		Short = "FACTORY",
		Amount = 120,
		Growth = 0.08,
		MinLevel = 2,
		Paint = "Yellow",
	},
	{
		Id = "WSell",
		Icon = "coins",
		Stat = "ItemsSold",
		Text = "Sell %s items",
		Short = "TRADE",
		Amount = 350,
		Growth = 0.08,
		Paint = "Green",
	},
	{
		Id = "WTrain",
		Icon = "train",
		Stat = "TrainTrips",
		Text = "Bring home %s trains",
		Short = "TRAIN",
		Amount = 35,
		Growth = 0,
		Paint = "Purple",
	},
	{
		Id = "WPodium",
		Icon = "podium",
		Stat = "PodiumEarned",
		Text = "Earn %s on podiums",
		Short = "PODIUMS",
		Income = 9000,
		Paint = "Yellow",
	},
	{
		Id = "WArtifacts",
		Icon = "artifact",
		Stat = "ArtifactsFound",
		Text = "Find %s artifacts",
		Short = "ARTIFACTS",
		Amount = 4,
		Growth = 0,
		Paint = "Purple",
	},
	{
		Id = "WCapsules",
		Icon = "golem",
		Stat = "CapsulesOpened",
		Text = "Open %s golem capsules",
		Short = "GOLEMS",
		Amount = 12,
		Growth = 0,
		Capsules = true,
		Paint = "Pink",
	},
} :: { QuestDef }

QuestConfig.ById = {} :: { [string]: QuestDef }
for _, list in { QuestConfig.Daily, QuestConfig.Weekly } do
	for _, def in list do
		QuestConfig.ById[def.Id] = def
	end
end

-- What a finished quest pays.
QuestConfig.DailyReward = { Coins = 600, Shards = 10 } :: Reward
QuestConfig.WeeklyReward = { Coins = 3600, Shards = 100, Boost = "TripleLucky", BoostSeconds = 900 } :: Reward

-- Coins: never under max(MinCoins, FloorShare x the next blaster level's coin scale, BlasterData.coins)
-- per 600 seconds of the reward (new players with no podium income).
QuestConfig.MinCoins = 250
QuestConfig.FloorShare = 0.03
QuestConfig.FloorSeconds = 600
-- Triple Lucky only helps capsules: where every capsule is restricted it pays
-- this many seconds of income instead (WheelConfig does the same).
QuestConfig.LuckyFallbackSeconds = 300

-- The 7-day login streak: one claim per UTC day; a missed day starts at day 1 again.
QuestConfig.Streak = {
	{ Day = 1, Label = "Coins", Icon = "coins", Coins = 300, Paint = "Yellow" },
	{ Day = 2, Label = "15 Shards", Icon = "shard", Shards = 15, Paint = "Teal" },
	{ Day = 3, Label = "Coins", Icon = "coins", Coins = 600, Paint = "Yellow" },
	{ Day = 4, Label = "Triple Lucky 10m", Icon = "clover", Boost = "TripleLucky", BoostSeconds = 600, Paint = "Green" },
	{ Day = 5, Label = "Coins + 30 Shards", Icon = "coins", Coins = 600, Shards = 30, Paint = "Orange" },
	{ Day = 6, Label = "Hexa Lucky 10m", Icon = "clover", Boost = "HexaLucky", BoostSeconds = 600, Paint = "Blue" },
	{ Day = 7, Label = "Crystal Capsule", Icon = "golem", Capsule = "Crystal", Shards = 50, Paint = "Purple" },
} :: { StreakDay }

-- Client: the claim waits this long for an answer before the button comes back.
QuestConfig.ResultTimeout = 6
-- Server: how often the day numbers are compared (new quests at midnight for players online).
QuestConfig.CheckSeconds = 30
-- Client: the join popup waits at most this long for the tutorial / another panel.
QuestConfig.PopupWaitSeconds = 60

QuestConfig.Reasons = {
	NotDone = "Finish the quest first!",
	Claimed = "Already claimed.",
	Stale = "New quests are here!",
	BadQuest = "That quest isn't there anymore.",
	NoData = "Your save is still loading.",
	Tomorrow = "Come back tomorrow for the next day!",
	InventoryFull = "Your golem inventory is full: make room to claim the Crystal Capsule!",
} :: { [string]: string }

return QuestConfig
