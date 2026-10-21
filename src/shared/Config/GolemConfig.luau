--[[
	Golem pets (step 7): little living stone and ore golems, woken from
	dormant golem cores in capsules (CapsuleConfig). Original designs in the
	proportions of Kenney's Mini Characters (big head, small chunky body),
	built from parts in the colors and materials of our ores, some with gear
	(helmets, visors, crowns, crystals on the back...). No Minecraft look or
	names.

	- 18 capsule kinds, Common..Mythic, plus the LIMITED EDITION sets
	  (Edition = the set's id, Config/LimitedGolems: sold only as their Robux
	  capsule in the shop's banner while the edition runs; once woken they
	  are ordinary golems forever). Each gives one bonus (BonusTypes) while
	  equipped; Golem Bond (enchant) and the Golemworks collection raise every
	  equipped golem's bonus by GolemBondPct.
	- 3 equipped at once (EquipSlots); at most InventoryCap golems in the
	  inventory (capsule opens that would pass it are refused). Saves keep up
	  to MaxSaved (a Robux receipt in step 8 may pass the cap: paid golems are
	  never lost).
	- Golems of a kind this server doesn't know (added by a newer update) stay
	  in the save (Migrations), count toward InventoryCap, give nothing, can't
	  be equipped, and are never deleted here (they may be paid ones).
	- Budgets (mobile, 8 players x 3 followers): a golem model has at most
	  MaxParts parts (a limited edition golem: LimitedMaxParts by rarity), no
	  lights (the Glow is a Neon part; Mythics may add one small PointLight,
	  Legendary and Mythic limited golems one slow ember ParticleEmitter). Followers are BUILT AND ANIMATED ON EACH CLIENT from
	  the player attribute EquippedAttribute ("PebbleGolem,EmberImp,..."): the
	  server replicates no golem parts or CFrames. Clients hide followers
	  further than FollowerHideDistance studs away and skip the idle bobbing
	  beyond FollowerLodDistance.

	Saved as data.Golems = {
	  Owned = { Entry },  -- Entry = { Id = number, Kind = golemId,
	                      --   Paid = true?    (from a Robux purchase: a paid
	                      --                    random item; trading checks
	                      --                    IsPaidItemTradingAllowed),
	                      --   Locked = true?  (the player's lock: never
	                      --                    deleted, see delete()),
	                      --   + scalar fields a newer server adds (trading,
	                      --     sources...): Migrations keeps them) }
	                      -- Id: whole, unique, >= 1
	  Equipped = { Id, ... }, -- at most EquipSlots ids from Owned
	  NextId = number,        -- > every Id in Owned
	  Pending = { { Kind = golemId, Paid = true } }, -- step 8: paid golems a Royal
	                          -- capsule receipt rolled past MaxSaved (a credit, never
	                          -- coins); CapsuleService wakes them into Owned as soon
	                          -- as there is room (at most MaxPending)
	}
	GolemAction ("Equip", { Id }) ("Unequip", { Id }) ("EquipBest")
	            ("Lock", { Id, Locked: boolean }) ("Delete", { Ids = { Id, ... } })
	The pure helpers below do the data writes, so every service (capsules,
	the wheel, step 8 receipts) changes the record the same way.
]]

local OreData = require(script.Parent.OreData)
local Rarity = require(script.Parent.Rarity)
local StatConfig = require(script.Parent.StatConfig)

export type BonusType = "Income" | "MiningSpeed" | "Luck" | "WalkSpeed" | "SellValue"

export type Golem = {
	Id: string,
	Name: string,
	Rarity: string,
	Ore: string?, -- OreData id the colors come from (nil = plain stone)
	Body: Color3,
	Trim: Color3, -- darker detail color (joints, feet, visor frame)
	Glow: Color3, -- eyes and core glow
	Material: Enum.Material,
	Accessory: string, -- GolemConfig.Accessories
	Scale: number, -- model scale (rarer golems are a bit bigger)
	Bonus: { Type: BonusType, Value: number },
	Lore: string,
	-- a LIMITED EDITION golem: its set's id (Config/LimitedGolems); its model
	-- may use GolemConfig.LimitedMaxParts[Rarity] for the set's costume
	Edition: string?,
}

export type Owned = { Id: number, Kind: string, Paid: boolean?, Locked: boolean? }

local GolemConfig = {}

GolemConfig.EquipSlots = 3
GolemConfig.InventoryCap = 60
GolemConfig.MaxSaved = 80 -- Migrations hard cap (see above)
GolemConfig.MaxPending = 200 -- paid golems waiting past MaxSaved (Golems.Pending; more: the receipt waits)
GolemConfig.MaxDelete = 60 -- ids per "Delete"
GolemConfig.MaxParts = 25 -- parts in one golem model (see the header)
-- a LIMITED EDITION golem's budget by rarity (its set's costume: segmented
-- horns and tails, boned wings, armour, crowns). They are rare (a Mythic is
-- 1 % of one Robux capsule), so the worst case (8 players x 3 Mythic
-- followers x 82 = 1968; 10 of each go to its rounded corners welded, non-colliding parts, hidden beyond
-- FollowerHideDistance) stays far below a phone's budget.
GolemConfig.LimitedMaxParts = { Rare = 58, Epic = 64, Legendary = 72, Mythic = 82 } :: { [string]: number }
GolemConfig.EquippedAttribute = "EquippedGolems" -- comma-separated kinds, set by the server
GolemConfig.FollowerHideDistance = 120 -- studs: other players' followers vanish beyond this
GolemConfig.FollowerLodDistance = 60 -- studs: no idle animation beyond this

-- Bonus type -> StatConfig stat + card label
GolemConfig.BonusTypes = {
	Income = { Stat = "IncomePct", Label = "Income" },
	MiningSpeed = { Stat = "DamagePct", Label = "Mining speed" },
	Luck = { Stat = "OreLuckPct", Label = "Ore luck" },
	WalkSpeed = { Stat = "WalkSpeedPct", Label = "Walk speed" },
	SellValue = { Stat = "SellPct", Label = "Sell value" },
} :: { [string]: { Stat: string, Label: string } }

-- Gear a golem can wear (the pet builder knows each one).
GolemConfig.Accessories = {
	None = true,
	Goggles = true, -- round tinker goggles on the forehead
	PotHelmet = true, -- a dented tin pot
	CrystalBack = true, -- a cluster of crystals growing from the back
	SquireHelm = true, -- a small open helmet with a plume
	Hood = true, -- a stone hood with a glowing rune
	Leaf = true, -- a sprouting leaf on the head
	Horns = true, -- two small ember horns
	Visor = true, -- a diving visor with a glass front
	LampHelmet = true, -- a miner's helmet with a lamp
	KnightHelm = true, -- a closed helm with a slit
	Halo = true, -- a floating ring of light
	Crown = true, -- a little crown
	-- the LIMITED EDITION gear (Builders/GolemGearLimited)
	DragonHorns = true, -- Dragonforge: curved horns, a snout, little wings and a tail
	DragonEgg = true, -- Dragonforge: a cracked dragon eggshell cap, stubby wings and a tail
	DragonHelm = true, -- Dragonforge: a horned dragon-head helm and a dragon shield
	DragonWings = true, -- Dragonforge: big fiery wings, horns, a snout (Legendary: lava hands, a tail)
	DragonCrown = true, -- Dragonforge: a crown of flames and huge gold-boned wings (the Dragon King)
} :: { [string]: boolean }

-- GolemAction / ActionResult reason codes -> text for the player
GolemConfig.Reasons = {
	BadGolem = "That golem isn't yours",
	SlotsFull = "All 3 golem slots are full",
	NotEquipped = "That golem isn't equipped",
	InventoryFull = "Your golem inventory is full",
	BadIds = "Pick the golems to delete",
	BadLock = "Lock or unlock one of your golems",
} :: { [string]: string }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- One golem dressed in an ore's colors (Body = ore color, Glow = ore glow).
-- Its Ore must be an OreData id (asserted by OreData.get).
local function oreGolem(entry: { [string]: any }): Golem
	local ore = OreData.get(entry.Ore)
	entry.Body = entry.Body or ore.Color
	entry.Glow = entry.Glow or ore.Glow
	entry.Material = entry.Material or ore.Material
	return (entry :: any) :: Golem
end

-- One limited edition golem (no ore: its colours are its own).
local function limited(entry: { [string]: any }): Golem
	return (entry :: any) :: Golem
end

GolemConfig.List = {
	---------------------------------------------------------------- Common
	oreGolem({
		Id = "PebbleGolem",
		Name = "Pebble Golem",
		Rarity = "Common",
		Ore = "Coal",
		Body = rgb(132, 126, 118),
		Trim = rgb(92, 86, 80),
		Glow = rgb(255, 170, 90),
		Material = Enum.Material.Slate,
		Accessory = "None",
		Scale = 1,
		Bonus = { Type = "Income", Value = 0.03 },
		Lore = "A round little heap of river stones. The first golem every apprentice wakes.",
	}),
	oreGolem({
		Id = "CopperTinker",
		Name = "Copper Tinker",
		Rarity = "Common",
		Ore = "Copper",
		Trim = rgb(120, 70, 40),
		Accessory = "Goggles",
		Scale = 1,
		Bonus = { Type = "MiningSpeed", Value = 0.04 },
		Lore = "Always fiddling with something. It hums while you blast.",
	}),
	oreGolem({
		Id = "CoalChomper",
		Name = "Coal Chomper",
		Rarity = "Common",
		Ore = "Coal",
		Trim = rgb(36, 32, 36),
		Accessory = "None",
		Scale = 1,
		Bonus = { Type = "SellValue", Value = 0.04 },
		Lore = "Its belly glows like a stove. Tobin swears it haggles for you.",
	}),
	oreGolem({
		Id = "TinTumbler",
		Name = "Tin Tumbler",
		Rarity = "Common",
		Ore = "Tin",
		Trim = rgb(110, 120, 108),
		Accessory = "PotHelmet",
		Scale = 1,
		Bonus = { Type = "WalkSpeed", Value = 0.03 },
		Lore = "Rolls more than it walks, and still keeps up.",
	}),
	---------------------------------------------------------------- Uncommon
	oreGolem({
		Id = "QuartzSprite",
		Name = "Quartz Sprite",
		Rarity = "Uncommon",
		Ore = "Quartz",
		Trim = rgb(170, 160, 160),
		Accessory = "CrystalBack",
		Scale = 1.05,
		Bonus = { Type = "Luck", Value = 0.05 },
		Lore = "Clear spikes grow on its back. It points at shiny things.",
	}),
	oreGolem({
		Id = "SilverSquire",
		Name = "Silver Squire",
		Rarity = "Uncommon",
		Ore = "Silver",
		Trim = rgb(120, 126, 140),
		Material = Enum.Material.Metal,
		Accessory = "SquireHelm",
		Scale = 1.05,
		Bonus = { Type = "Income", Value = 0.06 },
		Lore = "Bows to every podium it passes. Kaldrum's golems were very polite.",
	}),
	oreGolem({
		Id = "AmethystAcolyte",
		Name = "Amethyst Acolyte",
		Rarity = "Uncommon",
		Ore = "Amethyst",
		Trim = rgb(86, 50, 130),
		Accessory = "Hood",
		Scale = 1.05,
		Bonus = { Type = "SellValue", Value = 0.07 },
		Lore = "Wears a stone hood and whispers old prices to itself.",
	}),
	oreGolem({
		Id = "JadeGardener",
		Name = "Jade Gardener",
		Rarity = "Uncommon",
		Ore = "Jade",
		Trim = rgb(56, 120, 86),
		Accessory = "Leaf",
		Scale = 1.05,
		Bonus = { Type = "WalkSpeed", Value = 0.05 },
		Lore = "A leaf keeps sprouting on its head, however often it falls off.",
	}),
	---------------------------------------------------------------- Rare
	oreGolem({
		Id = "EmberImp",
		Name = "Ember Imp",
		Rarity = "Rare",
		Ore = "Emberite",
		Trim = rgb(120, 40, 20),
		Accessory = "Horns",
		Scale = 1.1,
		Bonus = { Type = "MiningSpeed", Value = 0.1 },
		Lore = "Tiny, hot and cheeky. Rocks crack faster when it giggles.",
	}),
	oreGolem({
		Id = "CobaltDiver",
		Name = "Cobalt Diver",
		Rarity = "Rare",
		Ore = "Cobalt",
		Trim = rgb(30, 50, 110),
		Accessory = "Visor",
		Scale = 1.1,
		Bonus = { Type = "Luck", Value = 0.1 },
		Lore = "Built to explore flooded tunnels. It still looks for treasure everywhere.",
	}),
	oreGolem({
		Id = "GildedPorter",
		Name = "Gilded Porter",
		Rarity = "Rare",
		Ore = "Gold",
		Trim = rgb(150, 100, 20),
		Accessory = "LampHelmet",
		Scale = 1.1,
		Bonus = { Type = "Income", Value = 0.1 },
		Lore = "Carried gold for the Royal Railway. Old habits: it counts your coins.",
	}),
	---------------------------------------------------------------- Epic
	oreGolem({
		Id = "RoseKnight",
		Name = "Rose Knight",
		Rarity = "Epic",
		Ore = "CrystalRose",
		Trim = rgb(110, 20, 36),
		Accessory = "KnightHelm",
		Scale = 1.15,
		Bonus = { Type = "MiningSpeed", Value = 0.16 },
		Lore = "Guarded the throne room of the Ember Kings. Now it guards you.",
	}),
	oreGolem({
		Id = "SapphireSage",
		Name = "Sapphire Sage",
		Rarity = "Epic",
		Ore = "Sapphire",
		Trim = rgb(20, 50, 120),
		Accessory = "Halo",
		Scale = 1.15,
		Bonus = { Type = "SellValue", Value = 0.18 },
		Lore = "Remembers what every ore was worth in Kaldrum, and tells Tobin.",
	}),
	oreGolem({
		Id = "DiamondDuke",
		Name = "Diamond Duke",
		Rarity = "Epic",
		Ore = "Diamond",
		Trim = rgb(150, 190, 220),
		Accessory = "Crown",
		Scale = 1.15,
		Bonus = { Type = "Income", Value = 0.15 },
		Lore = "Very sparkly and very proud. Podiums shine brighter when it walks by.",
	}),
	---------------------------------------------------------------- Legendary
	oreGolem({
		Id = "StormTitan",
		Name = "Storm Titan",
		Rarity = "Legendary",
		Ore = "StormGem",
		Trim = rgb(40, 50, 90),
		Accessory = "CrystalBack",
		Scale = 1.22,
		Bonus = { Type = "MiningSpeed", Value = 0.25 },
		Lore = "Lightning crawls over its back. Rocks fall apart in fear.",
	}),
	oreGolem({
		Id = "MoonstoneOracle",
		Name = "Moonstone Oracle",
		Rarity = "Legendary",
		Ore = "Moonstone",
		Trim = rgb(120, 130, 170),
		Accessory = "Halo",
		Scale = 1.22,
		Bonus = { Type = "Luck", Value = 0.25 },
		Lore = "Its eyes shift like the moon. It always knows which rock to break.",
	}),
	---------------------------------------------------------------- Mythic
	oreGolem({
		Id = "CelestialSovereign",
		Name = "Celestial Sovereign",
		Rarity = "Mythic",
		Ore = "CelestialCore",
		Trim = rgb(60, 50, 110),
		Accessory = "Crown",
		Scale = 1.3,
		Bonus = { Type = "Income", Value = 0.4 },
		Lore = "The last golem the Ember Kings ever crowned. It still expects a bow.",
	}),
	oreGolem({
		Id = "HeartstoneColossus",
		Name = "Heartstone Colossus",
		Rarity = "Mythic",
		Ore = "Heartstone",
		Trim = rgb(110, 20, 20),
		Accessory = "CrystalBack",
		Scale = 1.3,
		Bonus = { Type = "MiningSpeed", Value = 0.4 },
		Lore = "Woken by a true shard of the Heartstone. Small, but it beats like a forge.",
	}),
	---------------------------------------------------------------- Limited edition: Dragonforge
	-- (LimitedGolems: only from the Dragonforge capsule in the shop's banner)
	limited({
		Id = "CinderWhelp",
		Name = "Cinder Whelp",
		Rarity = "Rare",
		Body = rgb(74, 66, 72),
		Trim = rgb(40, 32, 38),
		Glow = rgb(255, 128, 30),
		Material = Enum.Material.Basalt,
		Accessory = "DragonHorns",
		Scale = 1.1,
		Bonus = { Type = "MiningSpeed", Value = 0.11 },
		Lore = "A baby dragon golem. When it sneezes, sparks fly.",
		Edition = "Dragonforge",
	}),
	limited({
		Id = "EmberHatchling",
		Name = "Ember Hatchling",
		Rarity = "Rare",
		Body = rgb(186, 56, 38),
		Trim = rgb(104, 26, 22),
		Glow = rgb(255, 196, 40),
		Material = Enum.Material.Slate,
		Accessory = "DragonEgg",
		Scale = 1.1,
		Bonus = { Type = "Luck", Value = 0.11 },
		Lore = "Just hatched from a dragon egg and still wears the shell as a hat.",
		Edition = "Dragonforge",
	}),
	limited({
		Id = "ScaleKnight",
		Name = "Dragonscale Knight",
		Rarity = "Epic",
		Body = rgb(48, 42, 54),
		Trim = rgb(160, 32, 42),
		Glow = rgb(255, 80, 40),
		Material = Enum.Material.Basalt,
		Accessory = "DragonHelm",
		Scale = 1.15,
		Bonus = { Type = "SellValue", Value = 0.19 },
		Lore = "Its armour is made of real dragon scales. They were a gift, it says.",
		Edition = "Dragonforge",
	}),
	limited({
		Id = "Flamewing",
		Name = "Flamewing",
		Rarity = "Epic",
		Body = rgb(200, 48, 44),
		Trim = rgb(96, 22, 28),
		Glow = rgb(255, 176, 40),
		Material = Enum.Material.Slate,
		Accessory = "DragonWings",
		Scale = 1.15,
		Bonus = { Type = "WalkSpeed", Value = 0.12 },
		Lore = "Its wings are a bit too small to fly. It flaps them anyway, very fast.",
		Edition = "Dragonforge",
	}),
	limited({
		Id = "MagmaWyvern",
		Name = "Magma Wyvern",
		Rarity = "Legendary",
		Body = rgb(40, 30, 36),
		Trim = rgb(20, 14, 20),
		Glow = rgb(255, 104, 20),
		Material = Enum.Material.CrackedLava,
		Accessory = "DragonWings",
		Scale = 1.22,
		Bonus = { Type = "MiningSpeed", Value = 0.28 },
		Lore = "Lava runs in its cracks. Rocks melt a little when it stares at them.",
		Edition = "Dragonforge",
	}),
	limited({
		Id = "DragonKing",
		Name = "Dragon King",
		Rarity = "Mythic",
		Body = rgb(38, 26, 36),
		Trim = rgb(200, 140, 40),
		Glow = rgb(255, 150, 30),
		Material = Enum.Material.Basalt,
		Accessory = "DragonCrown",
		Scale = 1.3,
		Bonus = { Type = "Income", Value = 0.45 },
		Lore = "Crowned in the heart of the volcano. Every dragon in the sky bows to it.",
		Edition = "Dragonforge",
	}),
} :: { Golem }

GolemConfig.ById = {} :: { [string]: Golem }
for _, golem in GolemConfig.List do
	GolemConfig.ById[golem.Id] = golem
end

-- Golem ids that were renamed (old id -> new id): Migrations rewrites saved
-- Kinds, so a golem woken under its old name keeps its rarity and bonus.
GolemConfig.Renamed = {
	RubyKnight = "RoseKnight",
	StormcoreTitan = "StormTitan",
	StarmetalSovereign = "CelestialSovereign",
} :: { [string]: string }

local function whole(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or v ~= math.floor(v) then
		return nil
	end
	return v
end

-- Rarity order of a golem kind (Common 1 .. Mythic 6; 0 when unknown).
function GolemConfig.order(kind: string): number
	local golem = GolemConfig.ById[kind]
	local info = if golem then Rarity.ById[golem.Rarity] else nil
	return if info then info.Order else 0
end

-- Sort score of a kind ("best" first): rarity, then bonus value.
function GolemConfig.score(kind: string): number
	local golem = GolemConfig.ById[kind]
	if not golem then
		return -1
	end
	return GolemConfig.order(kind) * 10 + golem.Bonus.Value
end

-- Card text of a kind's bonus: "+10% Income".
function GolemConfig.describe(kind: string, bondPct: number?): string
	local golem = GolemConfig.ById[kind]
	if not golem then
		return ""
	end
	local value = golem.Bonus.Value * (1 + (bondPct or 0))
	local percent = string.format("%.1f", value * 100):gsub("%.0$", "")
	return `+{percent}% {GolemConfig.BonusTypes[golem.Bonus.Type].Label}`
end

-- The record's Owned list / Equipped list (missing or broken = empty).
local function ownedList(golems: any): { any }
	local owned = if type(golems) == "table" then golems.Owned else nil
	return if type(owned) == "table" then owned else {}
end

local function equippedList(golems: any): { any }
	local equipped = if type(golems) == "table" then golems.Equipped else nil
	return if type(equipped) == "table" then equipped else {}
end

-- The owned entry with this Id (nil when there is none).
function GolemConfig.find(golems: any, id: any): Owned?
	if whole(id) == nil then
		return nil
	end
	for _, entry in ownedList(golems) do
		if type(entry) == "table" and entry.Id == id then
			return entry :: Owned
		end
	end
	return nil
end

function GolemConfig.count(golems: any): number
	return #ownedList(golems)
end

-- Free inventory places (0 when full or over the cap).
function GolemConfig.room(golems: any): number
	return math.max(0, GolemConfig.InventoryCap - GolemConfig.count(golems))
end

function GolemConfig.isEquipped(golems: any, id: any): boolean
	return table.find(equippedList(golems), id) ~= nil
end

-- Makes sure the record has its three fields (a pure fix-up for writers).
local function ensure(golems: { [string]: any })
	if type(golems.Owned) ~= "table" then
		golems.Owned = {}
	end
	if type(golems.Equipped) ~= "table" then
		golems.Equipped = {}
	end
	if whole(golems.NextId) == nil or golems.NextId < 1 then
		golems.NextId = 1
	end
end

-- Adds a golem of `kind`. Refused (nil) for an unknown kind or when the
-- inventory is at InventoryCap, unless `overCap` (a paid Robux receipt:
-- never lost; still never past MaxSaved). `paid`: it came from a Robux
-- purchase (saved as Paid = true; capsules bought with coins and wheel
-- prizes pass nil). Returns the new entry.
function GolemConfig.add(golems: { [string]: any }, kind: string, overCap: boolean?, paid: boolean?): Owned?
	if not GolemConfig.ById[kind] then
		return nil
	end
	ensure(golems)
	local count = #golems.Owned
	local cap = if overCap then GolemConfig.MaxSaved else GolemConfig.InventoryCap
	if count >= cap then
		return nil
	end
	local entry: Owned = { Id = golems.NextId, Kind = kind }
	if paid then
		entry.Paid = true
	end
	golems.NextId += 1
	table.insert(golems.Owned, entry)
	return entry
end

-- GolemAction "Equip": into the first free slot. true, or false + "BadGolem" | "SlotsFull".
-- Equipping an equipped golem again is a no-op success. A golem of an
-- unknown kind (a newer update's) can't be equipped ("BadGolem").
function GolemConfig.equip(golems: { [string]: any }, id: any): (boolean, string?)
	local entry = GolemConfig.find(golems, id)
	if not entry or not GolemConfig.ById[entry.Kind] then
		return false, "BadGolem"
	end
	ensure(golems)
	if table.find(golems.Equipped, id) then
		return true, nil
	end
	if #golems.Equipped >= GolemConfig.EquipSlots then
		return false, "SlotsFull"
	end
	table.insert(golems.Equipped, id)
	return true, nil
end

-- GolemAction "Unequip". true, or false + "NotEquipped".
function GolemConfig.unequip(golems: { [string]: any }, id: any): (boolean, string?)
	ensure(golems)
	local index = table.find(golems.Equipped, id)
	if not index then
		return false, "NotEquipped"
	end
	table.remove(golems.Equipped, index)
	return true, nil
end

-- GolemAction "EquipBest": the EquipSlots best owned golems of known kinds
-- (GolemConfig.score, then the oldest Id). Returns the new Equipped list.
function GolemConfig.equipBest(golems: { [string]: any }): { number }
	ensure(golems)
	local list = {}
	for _, entry in golems.Owned do
		if type(entry) == "table" and GolemConfig.ById[entry.Kind] then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a: any, b: any): boolean
		local sa, sb = GolemConfig.score(a.Kind), GolemConfig.score(b.Kind)
		if sa ~= sb then
			return sa > sb
		end
		return a.Id < b.Id
	end)
	local best = {}
	for i = 1, math.min(GolemConfig.EquipSlots, #list) do
		table.insert(best, list[i].Id)
	end
	golems.Equipped = best
	return best
end

-- GolemAction "Lock": sets or clears an owned golem's Locked flag (a locked
-- golem is never deleted). true, or false + "BadGolem" | "BadLock".
function GolemConfig.setLocked(golems: { [string]: any }, id: any, locked: any): (boolean, string?)
	if type(locked) ~= "boolean" then
		return false, "BadLock"
	end
	local entry = GolemConfig.find(golems, id)
	if not entry then
		return false, "BadGolem"
	end
	entry.Locked = if locked then true else nil
	return true, nil
end

-- GolemAction "Delete": removes the owned golems with these ids (also from
-- Equipped). `ids` must be a plain list of 1..MaxDelete whole numbers (the
-- check walks at most MaxDelete + 1 entries, whatever the client sent).
-- Locked golems and golems of unknown kinds (they may be paid ones from a
-- newer update) are never deleted: they are skipped and stay equipped.
-- Equipped golems the list names are deleted and unequipped (the UI asks
-- first). Returns how many were deleted (0 + "BadIds" for a bad list).
function GolemConfig.delete(golems: { [string]: any }, ids: any): (number, string?)
	if type(ids) ~= "table" then
		return 0, "BadIds"
	end
	local count = 0
	for key in ids do
		count += 1
		if count > GolemConfig.MaxDelete or type(key) ~= "number" then
			return 0, "BadIds"
		end
	end
	if count < 1 then
		return 0, "BadIds"
	end
	local wanted: { [number]: boolean } = {}
	for i = 1, count do
		local n = whole(ids[i])
		if n == nil then
			return 0, "BadIds" -- not 1..count, or not a whole number
		end
		wanted[n] = true
	end
	ensure(golems)
	local kept = {}
	local removed = 0
	for _, entry in golems.Owned do
		if type(entry) == "table" and wanted[entry.Id] and GolemConfig.ById[entry.Kind] and entry.Locked ~= true then
			removed += 1
		else
			table.insert(kept, entry)
			if type(entry) == "table" and type(entry.Id) == "number" then
				wanted[entry.Id] = nil -- kept (locked or an unknown kind): stays equipped too
			end
		end
	end
	golems.Owned = kept
	local equipped = {}
	for _, id in golems.Equipped do
		if not wanted[id] then
			table.insert(equipped, id)
		end
	end
	golems.Equipped = equipped
	return removed, nil
end

-- What the equipped golems give (Bonuses stats). `bondPct` (Golem Bond
-- enchant + collections) raises every golem's bonus by that share.
function GolemConfig.stats(golems: any, bondPct: number?): { [string]: number }
	local out: { [string]: number } = {}
	local bond = 1 + math.max(0, bondPct or 0)
	local seen: { [number]: boolean } = {}
	local used = 0
	for _, id in equippedList(golems) do
		if used >= GolemConfig.EquipSlots then
			break
		end
		local entry = if type(id) == "number" and not seen[id] then GolemConfig.find(golems, id) else nil
		local golem = if entry then GolemConfig.ById[entry.Kind] else nil
		if golem then
			seen[id] = true
			used += 1
			local stat = GolemConfig.BonusTypes[golem.Bonus.Type].Stat
			out[stat] = (out[stat] or 0) + golem.Bonus.Value * bond
		end
	end
	return out
end

-- The EquippedAttribute value for a record: the equipped known kinds in slot
-- order, comma-separated ("" when none). Clients build followers from it.
function GolemConfig.equippedKinds(golems: any): string
	local kinds = {}
	for _, id in equippedList(golems) do
		local entry = GolemConfig.find(golems, id)
		if entry and GolemConfig.ById[entry.Kind] and #kinds < GolemConfig.EquipSlots then
			table.insert(kinds, entry.Kind)
		end
	end
	return table.concat(kinds, ",")
end

-- Sanity: every kind's colors, accessory and bonus stat exist.
for _, golem in GolemConfig.List do
	assert(GolemConfig.Accessories[golem.Accessory], "GolemConfig: unknown accessory " .. golem.Accessory)
	assert(Rarity.ById[golem.Rarity], "GolemConfig: unknown rarity " .. golem.Rarity)
	local bonusType = GolemConfig.BonusTypes[golem.Bonus.Type]
	assert(bonusType and StatConfig.ById[bonusType.Stat], "GolemConfig: bad bonus on " .. golem.Id)
end
for old, new in GolemConfig.Renamed do
	assert(GolemConfig.ById[new] and not GolemConfig.ById[old], "GolemConfig: bad rename " .. old)
end

return GolemConfig
