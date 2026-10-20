--[[
	Artifacts of Kaldrum (step 7): relics hidden in rocks. Breaking a rock
	may turn one up (MiningService rolls rockChance(zone) x the player's
	artifact bonus and calls its onArtifactRoll listeners; the Artifacts
	service then picks the artifact with pick(zone, roll)).

	- 24 artifacts in 4 collections of 6. Each has a rarity, look hints for a
	  parts-built model (Shape family + colors) and a lore line.
	- Rarer artifacts turn up deeper: every zone has a weight for EACH
	  artifact of a rarity (ZoneRarity; per artifact, not per rarity, so a
	  rarity with fewer artifacts never makes each of them easier to find:
	  in every zone the chance of one artifact falls with its rarity) and a
	  chance multiplier on BlasterData.Rocks.ArtifactChance (ZoneChance).
	  Zones that aren't listed (new mine floors) use the weights of their
	  depth class (by the zone's MinBlaster).
	- A duplicate find gives crystal shards (DuplicateShards) instead. The
	  ONE missing artifact of a collection can be restored with shards
	  (RestoreShards, restoreQuote; ArtifactAction "Restore"), once a zone
	  the player can mine turns up its rarity.
	- Completing a collection (every artifact found at least once) unlocks its
	  story chapter (StoryConfig, read at the Guild board / collection book)
	  and its reward: a title, a podium skin and a small permanent bonus
	  (Bonuses "Collections"; its IncomePct reaches the podiums through the one
	  income bonus Bonuses adds to EconomyService). The title (over the
	  player's head) and the skin (on the player's podiums) are the ones of
	  ONE completed collection at a time: the one picked in the collection
	  book (data.Artifacts.Equipped, "" = none), else the last completed one
	  (ArtifactService applies them; ArtifactAction "Equip").
	- New collections come with later updates: add a collection, its 6
	  artifacts and a StoryConfig chapter. Saves keep artifact and chapter
	  ids this server doesn't know (Migrations); every reader here ignores them.
	- Budgets (mobile, 8 base museums x 24 artifacts): an artifact model has
	  at most MaxParts (8) parts, all anchored, CanCollide/CanTouch/CanQuery
	  off, no lights except the Mythic ones (one small PointLight,
	  LightRarity); the Glow is a Neon part. A museum shows ONLY the
	  artifacts its owner has found (an empty shelf spot is one plain
	  plinth part, shared per shelf) and lives in the base model, so
	  StreamingEnabled streams it in only within the streaming radius; the
	  pieces are built once (and when a new artifact is found), no per-frame
	  animation on the server; a slow spin, if any, runs on clients within
	  MuseumAnimateDistance studs. Worst case: 8 bases x 24 x 8 = 1,536
	  parts, and only the bases near a player are streamed in.

	Saved as data.Artifacts = {
	  Found = { [artifactId] = count (whole 1..MaxCount) },
	  Chapters = { [collectionId] = true }, -- chapters the player has read
	  Equipped = collectionId?, -- whose title + podium skin show ("" = none, nil = the last completed)
	}
	plus data.Stats.ArtifactsFound (every find, duplicates too: the ARTIFACTS board).
	ArtifactAction ("ReadChapter", { Collection }) marks a completed collection's chapter read;
	ArtifactAction ("Equip", { Collection }) picks whose reward shows ("" = none);
ArtifactAction ("Restore", { Artifact }) buys back a collection's last missing artifact.
]]

local BlasterData = require(script.Parent.BlasterData)
local Rarity = require(script.Parent.Rarity)
local StatConfig = require(script.Parent.StatConfig)
local WorldLayout = require(script.Parent.WorldLayout)

export type Artifact = {
	Id: string,
	Name: string,
	Collection: string,
	Rarity: string,
	Shape: string, -- ArtifactConfig.Shapes
	Primary: Color3,
	Accent: Color3,
	Glow: Color3?, -- nil = no glow
	Lore: string,
}

export type Collection = {
	Id: string,
	Name: string,
	Order: number,
	Color: Color3,
	Reward: {
		Title: string,
		PodiumSkin: string, -- ArtifactConfig.PodiumSkins id
		Bonus: { Stat: string, Value: number },
	},
}

export type OddsLine = { Artifact: string, Chance: number }

local ArtifactConfig = {}

ArtifactConfig.MaxCount = 9999 -- copies of one artifact a save keeps count of
ArtifactConfig.MaxParts = 8 -- parts in one artifact model (see the header)
ArtifactConfig.LightRarity = "Mythic" -- only this rarity may carry a light
ArtifactConfig.MuseumAnimateDistance = 60 -- studs: clients animate museum pieces only this close

-- ArtifactAction / ActionResult reason codes -> text for the player
ArtifactConfig.Reasons = {
	BadCollection = "That collection doesn't exist",
	NotComplete = "Find every artifact of this collection first",
	BadArtifact = "That artifact doesn't exist",
	NotMissing = "You already have that artifact",
	NotLast = "Find all the others of this collection first",
	Locked = "Reach a mine where it turns up first",
	NoShards = "Not enough crystal shards",
} :: { [string]: string }

-- Shape families the artifact model builder knows.
ArtifactConfig.Shapes = {
	Coin = true, -- flat disc with a stamped face
	Seal = true, -- thick disc with a handle
	Gem = true, -- faceted stone in a setting
	Rod = true, -- a short rod with a head (scepter, finial)
	Crown = true,
	Spike = true,
	Whistle = true,
	Lantern = true,
	Tablet = true, -- flat slab with carved lines
	Crest = true, -- shield-shaped plate
	Gear = true,
	Vial = true,
	Scroll = true,
	Orb = true,
	Hammer = true,
	Book = true,
	Lens = true,
	Shard = true, -- a crystal shard
} :: { [string]: boolean }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

ArtifactConfig.Collections = {
	{
		Id = "CrownOfKaldrum",
		Name = "The Crown of Kaldrum",
		Order = 1,
		Color = rgb(255, 190, 60),
		Reward = { Title = "Heir of Kaldrum", PodiumSkin = "Royal", Bonus = { Stat = "IncomePct", Value = 0.05 } },
	},
	{
		Id = "RoyalRailway",
		Name = "The Royal Railway",
		Order = 2,
		Color = rgb(200, 140, 70),
		Reward = { Title = "Royal Conductor", PodiumSkin = "Railway", Bonus = { Stat = "SellPct", Value = 0.1 } },
	},
	{
		Id = "Golemworks",
		Name = "The Golemworks",
		Order = 3,
		Color = rgb(130, 200, 220),
		Reward = { Title = "Golemsmith", PodiumSkin = "Golemworks", Bonus = { Stat = "GolemBondPct", Value = 0.1 } },
	},
	{
		Id = "HeartstoneLore",
		Name = "The Heartstone Lore",
		Order = 4,
		Color = rgb(255, 80, 60),
		Reward = { Title = "Keeper of the Heartstone", PodiumSkin = "Heartstone", Bonus = { Stat = "IncomePct", Value = 0.1 } },
	},
} :: { Collection }

-- Podium skins (a collection reward; the podium builder colors the podium).
ArtifactConfig.PodiumSkins = {
	Royal = { Name = "Royal Velvet", Base = rgb(120, 30, 50), Trim = rgb(255, 196, 60), Glow = rgb(255, 220, 120) },
	Railway = { Name = "Brass Rails", Base = rgb(70, 60, 56), Trim = rgb(200, 150, 70), Glow = rgb(255, 170, 80) },
	Golemworks = { Name = "Golem Core", Base = rgb(90, 96, 110), Trim = rgb(150, 210, 230), Glow = rgb(120, 230, 255) },
	Heartstone = { Name = "Heartstone Ember", Base = rgb(60, 24, 24), Trim = rgb(255, 90, 60), Glow = rgb(255, 120, 60) },
} :: { [string]: { Name: string, Base: Color3, Trim: Color3, Glow: Color3 } }

ArtifactConfig.List = {
	---------------------------------------------------------------- The Crown of Kaldrum
	{
		Id = "CrownCoin",
		Name = "Ember King's Coin",
		Collection = "CrownOfKaldrum",
		Rarity = "Common",
		Shape = "Coin",
		Primary = rgb(214, 128, 70),
		Accent = rgb(120, 70, 40),
		Lore = "A copper coin stamped with a flame. Kaldrum paid its miners in these.",
	},
	{
		Id = "RoyalSeal",
		Name = "Royal Wax Seal",
		Collection = "CrownOfKaldrum",
		Rarity = "Common",
		Shape = "Seal",
		Primary = rgb(170, 40, 40),
		Accent = rgb(240, 190, 80),
		Lore = "The Ember Kings sealed every law with this mark of a crown in a flame.",
	},
	{
		Id = "QueensBrooch",
		Name = "Queen's Amethyst Brooch",
		Collection = "CrownOfKaldrum",
		Rarity = "Uncommon",
		Shape = "Gem",
		Primary = rgb(150, 84, 220),
		Accent = rgb(230, 200, 120),
		Glow = rgb(196, 130, 255),
		Lore = "Queen Amarra wore it on the day the city first lit the Great Forge.",
	},
	{
		Id = "ThroneFinial",
		Name = "Throne Finial",
		Collection = "CrownOfKaldrum",
		Rarity = "Uncommon",
		Shape = "Rod",
		Primary = rgb(230, 180, 70),
		Accent = rgb(110, 70, 30),
		Lore = "A golden knob broken off the Ember Throne. It is still warm to the touch.",
	},
	{
		Id = "EmberScepter",
		Name = "Ember Scepter",
		Collection = "CrownOfKaldrum",
		Rarity = "Rare",
		Shape = "Rod",
		Primary = rgb(200, 60, 40),
		Accent = rgb(250, 200, 90),
		Glow = rgb(255, 130, 60),
		Lore = "Raised over the Heartstone at every coronation, so the stone knew its king.",
	},
	{
		Id = "EmberCrown",
		Name = "The Ember Crown",
		Collection = "CrownOfKaldrum",
		Rarity = "Epic",
		Shape = "Crown",
		Primary = rgb(255, 196, 60),
		Accent = rgb(200, 40, 50),
		Glow = rgb(255, 140, 60),
		Lore = "The crown of the last Ember King. A tiny flame still dances in its ruby.",
	},
	---------------------------------------------------------------- The Royal Railway
	{
		Id = "GoldenSpike",
		Name = "Golden Rail Spike",
		Collection = "RoyalRailway",
		Rarity = "Common",
		Shape = "Spike",
		Primary = rgb(230, 180, 70),
		Accent = rgb(90, 80, 70),
		Lore = "Hammered in by the king himself to open the first line of the Royal Railway.",
	},
	{
		Id = "ConductorWhistle",
		Name = "Conductor's Whistle",
		Collection = "RoyalRailway",
		Rarity = "Common",
		Shape = "Whistle",
		Primary = rgb(200, 200, 210),
		Accent = rgb(150, 100, 50),
		Lore = "One blow and every golem porter on the platform stood up straight.",
	},
	{
		Id = "RailLantern",
		Name = "Rail Lantern",
		Collection = "RoyalRailway",
		Rarity = "Uncommon",
		Shape = "Lantern",
		Primary = rgb(60, 70, 80),
		Accent = rgb(220, 160, 70),
		Glow = rgb(255, 200, 110),
		Lore = "It hung on the last car of the night trains so the tunnels never felt empty.",
	},
	{
		Id = "LastTicket",
		Name = "Last Train Ticket",
		Collection = "RoyalRailway",
		Rarity = "Uncommon",
		Shape = "Tablet",
		Primary = rgb(235, 220, 180),
		Accent = rgb(170, 60, 50),
		Lore = "A brass ticket for the train that left the capital the night of the Shattering.",
	},
	{
		Id = "RoyalTimetable",
		Name = "Royal Timetable",
		Collection = "RoyalRailway",
		Rarity = "Rare",
		Shape = "Book",
		Primary = rgb(70, 90, 140),
		Accent = rgb(230, 190, 90),
		Lore = "Every station of the kingdom, every train, to the minute. Kaldrum loved order.",
	},
	{
		Id = "LocomotiveCrest",
		Name = "Locomotive Crest",
		Collection = "RoyalRailway",
		Rarity = "Epic",
		Shape = "Crest",
		Primary = rgb(150, 30, 40),
		Accent = rgb(255, 200, 80),
		Glow = rgb(255, 170, 80),
		Lore = "The crest from the front of the royal train, the Ember Express.",
	},
	---------------------------------------------------------------- The Golemworks
	{
		Id = "GolemCog",
		Name = "Golem Cog",
		Collection = "Golemworks",
		Rarity = "Common",
		Shape = "Gear",
		Primary = rgb(150, 156, 170),
		Accent = rgb(90, 80, 70),
		Lore = "A cog from a golem's knee. It turns on its own when you hum.",
	},
	{
		Id = "SparkVial",
		Name = "Spark Vial",
		Collection = "Golemworks",
		Rarity = "Uncommon",
		Shape = "Vial",
		Primary = rgb(180, 220, 230),
		Accent = rgb(120, 90, 60),
		Glow = rgb(120, 230, 255),
		Lore = "Golemsmiths kept Heartstone sparks in glass to wake their creations.",
	},
	{
		Id = "GolemBlueprint",
		Name = "Golem Blueprint",
		Collection = "Golemworks",
		Rarity = "Rare",
		Shape = "Scroll",
		Primary = rgb(70, 110, 180),
		Accent = rgb(230, 230, 240),
		Lore = "Plans for a little stone helper: big head, short legs, a spark for a heart.",
	},
	{
		Id = "CoreCasing",
		Name = "Dormant Core Casing",
		Collection = "Golemworks",
		Rarity = "Rare",
		Shape = "Orb",
		Primary = rgb(120, 120, 130),
		Accent = rgb(80, 200, 230),
		Glow = rgb(120, 230, 255),
		Lore = "The empty shell of a golem core. Something inside it is still dreaming.",
	},
	{
		Id = "GolemsmithHammer",
		Name = "Golemsmith's Hammer",
		Collection = "Golemworks",
		Rarity = "Epic",
		Shape = "Hammer",
		Primary = rgb(110, 110, 120),
		Accent = rgb(160, 100, 50),
		Glow = rgb(140, 220, 255),
		Lore = "Master Orvald shaped a thousand golems with it, one gentle tap at a time.",
	},
	{
		Id = "FirstGolemEye",
		Name = "Eye of the First Golem",
		Collection = "Golemworks",
		Rarity = "Legendary",
		Shape = "Orb",
		Primary = rgb(40, 50, 70),
		Accent = rgb(255, 200, 90),
		Glow = rgb(255, 220, 120),
		Lore = "The first golem watched over Kaldrum for three hundred years. It still blinks.",
	},
	---------------------------------------------------------------- The Heartstone Lore
	{
		Id = "StarMapFragment",
		Name = "Star Map Fragment",
		Collection = "HeartstoneLore",
		Rarity = "Uncommon",
		Shape = "Tablet",
		Primary = rgb(30, 40, 80),
		Accent = rgb(230, 230, 255),
		Glow = rgb(170, 190, 255),
		Lore = "Kaldrum's sky-watchers marked where the Heartstone fell from the stars.",
	},
	{
		Id = "EmberRune",
		Name = "Ember Rune Stone",
		Collection = "HeartstoneLore",
		Rarity = "Rare",
		Shape = "Tablet",
		Primary = rgb(70, 60, 60),
		Accent = rgb(255, 120, 60),
		Glow = rgb(255, 120, 60),
		Lore = "A rune that glows near ore. Forgekeepers still carve copies of it.",
	},
	{
		Id = "ForgekeeperOath",
		Name = "Forgekeeper's Oath",
		Collection = "HeartstoneLore",
		Rarity = "Rare",
		Shape = "Scroll",
		Primary = rgb(235, 215, 170),
		Accent = rgb(170, 50, 40),
		Lore = '"Keep the fire, share the ore, wake what sleeps." The Guild\'s first promise.',
	},
	{
		Id = "ShatteringChronicle",
		Name = "Chronicle of the Shattering",
		Collection = "HeartstoneLore",
		Rarity = "Epic",
		Shape = "Book",
		Primary = rgb(90, 30, 30),
		Accent = rgb(230, 190, 90),
		Glow = rgb(255, 120, 60),
		Lore = "The royal scribe's last book. The final page is burned around the edges.",
	},
	{
		Id = "SunlanceLens",
		Name = "Sunlance Lens",
		Collection = "HeartstoneLore",
		Rarity = "Legendary",
		Shape = "Lens",
		Primary = rgb(255, 220, 140),
		Accent = rgb(150, 100, 40),
		Glow = rgb(255, 230, 150),
		Lore = "The lens of the first Sunlance blaster. Light bends inside it like water.",
	},
	{
		Id = "HeartstoneFragment",
		Name = "Heartstone Fragment",
		Collection = "HeartstoneLore",
		Rarity = "Mythic",
		Shape = "Shard",
		Primary = rgb(255, 60, 80),
		Accent = rgb(255, 200, 120),
		Glow = rgb(255, 80, 60),
		Lore = "A true shard of the living ember. It beats, slowly, like a heart.",
	},
} :: { Artifact }

-- Chance multiplier on BlasterData.Rocks.ArtifactChance per zone.
ArtifactConfig.ZoneChance = {
	Outcrops = 0.5,
	Quarry = 1,
	EmberCaves = 1.25,
	Grotto = 1.25,
	DeepHollow = 1.5,
} :: { [string]: number }

-- The weight of EACH artifact of a rarity once one turns up in a zone
-- (rarer deeper; per artifact, so in every zone one artifact's chance falls
-- with its rarity: DeepHollow, 24 artifacts: one Common 5.5 %, Uncommon
-- 4.9 %, Rare 4.4 %, Epic 3.3 %, Legendary 1.6 %, the Mythic 0.66 %).
ArtifactConfig.ZoneRarity = {
	Outcrops = { Common = 14, Uncommon = 6, Rare = 1.5 },
	Quarry = { Common = 11, Uncommon = 6, Rare = 2.5, Epic = 0.8 },
	EmberCaves = { Common = 7, Uncommon = 6, Rare = 4, Epic = 2.5, Legendary = 1 },
	Grotto = { Common = 7, Uncommon = 6, Rare = 4, Epic = 2.5, Legendary = 1 },
	DeepHollow = { Common = 5, Uncommon = 4.5, Rare = 4, Epic = 3, Legendary = 1.5, Mythic = 0.6 },
} :: { [string]: { [string]: number } }

-- Zones not listed above: the depth class of their MinBlaster (shallow < 3 <= mid < 5 <= deep).
ArtifactConfig.DepthClass = { Shallow = "Quarry", Mid = "EmberCaves", Deep = "DeepHollow" }

-- Crystal shards a duplicate find gives, by rarity.
ArtifactConfig.DuplicateShards = {
	Common = 1,
	Uncommon = 2,
	Rare = 4,
	Epic = 8,
	Legendary = 16,
	Mythic = 40,
} :: { [string]: number }

--[[
	The end of a long chase: the ONE missing artifact of a collection (all
	the others found) can be restored with crystal shards (ArtifactAction
	"Restore"), at this price by its rarity; only once the player's blaster
	opens a zone where that rarity turns up (rarer stays deeper). About
	half the shards the duplicates of an average chase pay (Deep Hollow:
	~3.75 shards per duplicate; the Mythic's ~150 finds pay ~560), and the
	Enchant shop wants the same shards: a real choice, never a shortcut
	past the zones.
]]
ArtifactConfig.RestoreShards = {
	Common = 20,
	Uncommon = 30,
	Rare = 50,
	Epic = 80,
	Legendary = 150,
	Mythic = 300,
} :: { [string]: number }

ArtifactConfig.ById = {} :: { [string]: Artifact }
ArtifactConfig.CollectionById = {} :: { [string]: Collection }
ArtifactConfig.ByCollection = {} :: { [string]: { Artifact } }
for _, collection in ArtifactConfig.Collections do
	ArtifactConfig.CollectionById[collection.Id] = collection
	ArtifactConfig.ByCollection[collection.Id] = {}
	assert(ArtifactConfig.PodiumSkins[collection.Reward.PodiumSkin], "ArtifactConfig: unknown podium skin")
	assert(StatConfig.ById[collection.Reward.Bonus.Stat], "ArtifactConfig: unknown bonus stat")
end
for _, artifact in ArtifactConfig.List do
	ArtifactConfig.ById[artifact.Id] = artifact
	local list = ArtifactConfig.ByCollection[artifact.Collection]
	assert(list, "ArtifactConfig: unknown collection " .. artifact.Collection)
	assert(Rarity.ById[artifact.Rarity], "ArtifactConfig: unknown rarity " .. artifact.Rarity)
	assert(ArtifactConfig.Shapes[artifact.Shape], "ArtifactConfig: unknown shape " .. artifact.Shape)
	table.insert(list, artifact)
end

-- The rarity weights a zone uses (listed, or by its depth class).
function ArtifactConfig.rarityWeights(zoneId: string): { [string]: number }
	local listed = ArtifactConfig.ZoneRarity[zoneId]
	if listed then
		return listed
	end
	local zone = WorldLayout.ZoneById[zoneId]
	local depth = if zone then zone.MinBlaster else 1
	local class = if depth >= 5
		then ArtifactConfig.DepthClass.Deep
		elseif depth >= 3 then ArtifactConfig.DepthClass.Mid
		else ArtifactConfig.DepthClass.Shallow
	return ArtifactConfig.ZoneRarity[class]
end

-- Chance that breaking one rock in `zoneId` turns up an artifact (before bonuses).
function ArtifactConfig.rockChance(zoneId: string): number
	local mult = ArtifactConfig.ZoneChance[zoneId]
	if mult == nil then
		local zone = WorldLayout.ZoneById[zoneId]
		mult = if zone and zone.MinBlaster >= 5 then 1.5 elseif zone and zone.MinBlaster >= 3 then 1.25 else 1
	end
	return BlasterData.Rocks.ArtifactChance * (mult :: number)
end

-- Exact chance of each artifact once one turns up in `zoneId` (sums to 1):
-- every artifact weighs its rarity's ZoneRarity weight (per artifact). In
-- ArtifactConfig.List order.
function ArtifactConfig.odds(zoneId: string): { OddsLine }
	local weights = ArtifactConfig.rarityWeights(zoneId)
	local total = 0
	for _, artifact in ArtifactConfig.List do
		local weight = weights[artifact.Rarity] or 0
		if weight > 0 then
			total += weight
		end
	end
	local list: { OddsLine } = {}
	if total <= 0 then
		return list
	end
	for _, artifact in ArtifactConfig.List do
		local weight = weights[artifact.Rarity] or 0
		if weight > 0 then
			table.insert(list, { Artifact = artifact.Id, Chance = weight / total })
		end
	end
	return list
end

-- The artifact for a roll in [0, 1) in `zoneId`.
function ArtifactConfig.pick(zoneId: string, roll: number): string?
	local list = ArtifactConfig.odds(zoneId)
	local acc = 0
	for _, line in list do
		acc += line.Chance
		if roll < acc then
			return line.Artifact
		end
	end
	local last = list[#list]
	return if last then last.Artifact else nil
end

-- How many of an artifact a data.Artifacts record holds (0 = never found,
-- and 0 for an id this server doesn't know: a newer update's artifact).
function ArtifactConfig.countOf(artifacts: any, id: string): number
	if not ArtifactConfig.ById[id] then
		return 0
	end
	local found = if type(artifacts) == "table" then artifacts.Found else nil
	local n = if type(found) == "table" then found[id] else nil
	if type(n) ~= "number" or n ~= n or n < 1 then
		return 0
	end
	return math.min(math.floor(n), ArtifactConfig.MaxCount)
end

-- Different artifacts found (the collection book's "12 / 24").
function ArtifactConfig.uniqueCount(artifacts: any): number
	local count = 0
	for _, artifact in ArtifactConfig.List do
		if ArtifactConfig.countOf(artifacts, artifact.Id) > 0 then
			count += 1
		end
	end
	return count
end

-- Has every artifact of the collection been found?
function ArtifactConfig.isComplete(artifacts: any, collectionId: string): boolean
	local list = ArtifactConfig.ByCollection[collectionId]
	if not list or #list == 0 then
		return false
	end
	for _, artifact in list do
		if ArtifactConfig.countOf(artifacts, artifact.Id) == 0 then
			return false
		end
	end
	return true
end

-- The completed collection ids, in collection order.
function ArtifactConfig.completed(artifacts: any): { string }
	local list = {}
	for _, collection in ArtifactConfig.Collections do
		if ArtifactConfig.isComplete(artifacts, collection.Id) then
			table.insert(list, collection.Id)
		end
	end
	return list
end

-- Records one find of `id` (pure write; the caller also adds 1 to
-- data.Stats.ArtifactsFound and gives DuplicateShards for a duplicate).
-- Returns the new count, whether it is the first one, and the collection id
-- when this find completed it (nil otherwise). Unknown id: 0, false, nil.
function ArtifactConfig.add(artifacts: { [string]: any }, id: string): (number, boolean, string?)
	local artifact = ArtifactConfig.ById[id]
	if not artifact then
		return 0, false, nil
	end
	local found = artifacts.Found
	if type(found) ~= "table" then
		found = {}
		artifacts.Found = found
	end
	local before = ArtifactConfig.countOf(artifacts, id)
	local count = math.min(before + 1, ArtifactConfig.MaxCount)
	found[id] = count
	local isNew = before == 0
	local completed = if isNew and ArtifactConfig.isComplete(artifacts, artifact.Collection) then artifact.Collection else nil
	return count, isNew, completed
end

-- What the completed collections give (Bonuses stats).
function ArtifactConfig.stats(artifacts: any): { [string]: number }
	local out: { [string]: number } = {}
	for _, collectionId in ArtifactConfig.completed(artifacts) do
		local bonus = ArtifactConfig.CollectionById[collectionId].Reward.Bonus
		out[bonus.Stat] = (out[bonus.Stat] or 0) + bonus.Value
	end
	return out
end

-- The completed collection whose title + podium skin show (see the header):
-- data.Artifacts.Equipped when it is a completed collection, nil for "" (the
-- player hid them), else the last completed collection (nil: none yet).
function ArtifactConfig.equipped(artifacts: any): string?
	local pick = if type(artifacts) == "table" then artifacts.Equipped else nil
	if pick == "" then
		return nil
	end
	if type(pick) == "string" and ArtifactConfig.isComplete(artifacts, pick) then
		return pick
	end
	local done = ArtifactConfig.completed(artifacts)
	return done[#done]
end

-- The one missing artifact of a collection (nil: none or more than one missing).
function ArtifactConfig.lastMissing(artifacts: any, collectionId: string): string?
	local list = ArtifactConfig.ByCollection[collectionId]
	if not list then
		return nil
	end
	local missing: string? = nil
	for _, artifact in list do
		if ArtifactConfig.countOf(artifacts, artifact.Id) == 0 then
			if missing then
				return nil
			end
			missing = artifact.Id
		end
	end
	return missing
end

-- Does a zone the player can mine (WorldLayout zone MinBlaster <= blasterLevel;
-- VIP-only zones only with `vip`) turn up artifacts of this rarity?
function ArtifactConfig.rarityOpen(rarityId: string, blasterLevel: number, vip: boolean?): boolean
	for _, zone in WorldLayout.Zones do
		local minable = zone.MinBlaster <= blasterLevel and (vip == true or not zone.VipOnly)
		if minable and (ArtifactConfig.rarityWeights(zone.Id)[rarityId] or 0) > 0 then
			return true
		end
	end
	return false
end

--[[
	The shard price to restore `artifactId` (RestoreShards), or nil + a
	Reasons code: BadArtifact, NotMissing (already found), NotLast (more
	than this one missing in its collection), Locked (no open zone turns up
	its rarity; VIP-only zones count only with `vip`), NoShards (`shards` <
	price). Pure: the server checks and spends with no yield in between, the
	book shows the same answer.
]]
function ArtifactConfig.restoreQuote(
	artifacts: any,
	artifactId: string,
	blasterLevel: number,
	shards: number,
	vip: boolean?
): (number?, string?)
	local artifact = ArtifactConfig.ById[artifactId]
	local price = if artifact then ArtifactConfig.RestoreShards[artifact.Rarity] else nil
	if not artifact or not price then
		return nil, "BadArtifact"
	end
	if ArtifactConfig.countOf(artifacts, artifactId) > 0 then
		return nil, "NotMissing"
	end
	if ArtifactConfig.lastMissing(artifacts, artifact.Collection) ~= artifactId then
		return nil, "NotLast"
	end
	local level = if type(blasterLevel) == "number" and blasterLevel == blasterLevel then blasterLevel else 1
	if not ArtifactConfig.rarityOpen(artifact.Rarity, level, vip) then
		return nil, "Locked"
	end
	if type(shards) ~= "number" or shards ~= shards or shards < price then
		return nil, "NoShards"
	end
	return price, nil
end

-- The titles a player has earned (completed collections), in order.
function ArtifactConfig.titles(artifacts: any): { string }
	local list = {}
	for _, collectionId in ArtifactConfig.completed(artifacts) do
		table.insert(list, ArtifactConfig.CollectionById[collectionId].Reward.Title)
	end
	return list
end

return ArtifactConfig
