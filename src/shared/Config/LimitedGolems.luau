--[[
	LIMITED EDITION golems (PROTOTYPE, 2026-10-20): four themed sets the
	owner picks from for the Robux shop's FEATURED banner ("limited mega cool
	edition of golems": a themed background, the set's golems with their %
	odds, buy 1 / 3 / 10 / 50). NOT wired into the game yet: GolemConfig.List
	stays the 18 capsule golems, no capsule, product, save or service knows
	these ids. Only GolemBuilder builds them (its lookOf / premium read
	LimitedGolems.ById after GolemConfig.ById), so the previews, the shop
	icons and later the shop can show them.

	Each theme: 6 golems (Rare, Rare, Epic, Epic, Legendary, Mythic) in the
	GolemConfig.Golem shape, wearing the theme's own gear (GolemBuilder's
	limited accessories, GolemGearLimited), plus the banner's look:
	  Title / Tagline   the banner text
	  Backdrop          the banner and preview diorama colours
	  Odds              the banner odds (sum 1; shown to the player: Roblox rule)
	Limited golems may use up to GolemBuilder.LimitedMaxParts parts (=
	GolemConfig.MaxParts, the hard cap in GolemConfig's header) for their gear.

	To ship the winner: move its 6 entries into GolemConfig.List (or keep
	this module and let GolemConfig.ById include it), add its banner as a
	capsule-like Robux item with these Odds and products, and delete the
	other three themes and their gear.
]]

local GolemConfig = require(script.Parent.GolemConfig)
local Rarity = require(script.Parent.Rarity)

export type Backdrop = {
	SkyTop: Color3, -- banner gradient top / the preview sky's zenith
	SkyHorizon: Color3, -- banner gradient bottom / the sky low down
	Ground: Color3, -- the stage the golems stand on
	Accent: Color3, -- the theme's glow (title, rim lights)
	Title: { Color3 }, -- the title text gradient (top -> bottom)
}

export type Theme = {
	Id: string,
	Title: string,
	Tagline: string,
	Backdrop: Backdrop,
	Golems: { GolemConfig.Golem }, -- Rare, Rare, Epic, Epic, Legendary, Mythic
	Odds: { [string]: number }, -- golem id -> chance (sum 1)
}

local LimitedGolems = {}

-- The rarities of a set, in order (tests/LimitedGolems.spec.luau).
LimitedGolems.SetRarities = { "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" }
-- The banner odds by place in the set (sum 1).
LimitedGolems.SetOdds = { 0.34, 0.28, 0.2, 0.12, 0.05, 0.01 }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material

local function golem(entry: { [string]: any }): GolemConfig.Golem
	return (entry :: any) :: GolemConfig.Golem
end

local function theme(entry: { [string]: any }): Theme
	local odds = {}
	for i, g in entry.Golems do
		odds[g.Id] = LimitedGolems.SetOdds[i]
	end
	entry.Odds = odds
	return (entry :: any) :: Theme
end

LimitedGolems.Themes = {
	---------------------------------------------------------------- A: dragon fire
	Dragonforge = theme({
		Id = "Dragonforge",
		Title = "DRAGONFORGE",
		Tagline = "Golems forged in dragon fire!",
		Backdrop = {
			SkyTop = rgb(36, 10, 30),
			SkyHorizon = rgb(255, 96, 40),
			Ground = rgb(40, 30, 34),
			Accent = rgb(255, 128, 30),
			Title = { rgb(255, 236, 110), rgb(255, 90, 20) },
		},
		Golems = {
			golem({
				Id = "CinderWhelp",
				Name = "Cinder Whelp",
				Rarity = "Rare",
				Body = rgb(70, 62, 68),
				Trim = rgb(34, 28, 34),
				Glow = rgb(255, 128, 30),
				Material = M.Basalt,
				Accessory = "DragonHorns",
				Scale = 1.1,
				Bonus = { Type = "MiningSpeed", Value = 0.12 },
				Lore = "A baby dragon golem. When it sneezes, sparks fly.",
			}),
			golem({
				Id = "EmberHatchling",
				Name = "Ember Hatchling",
				Rarity = "Rare",
				Body = rgb(176, 52, 36),
				Trim = rgb(96, 24, 20),
				Glow = rgb(255, 196, 40),
				Material = M.Slate,
				Accessory = "DragonEgg",
				Scale = 1.1,
				Bonus = { Type = "Luck", Value = 0.12 },
				Lore = "Just hatched from a dragon egg and still wears the shell as a hat.",
			}),
			golem({
				Id = "ScaleKnight",
				Name = "Dragonscale Knight",
				Rarity = "Epic",
				Body = rgb(46, 40, 50),
				Trim = rgb(150, 30, 40),
				Glow = rgb(255, 72, 40),
				Material = M.Basalt,
				Accessory = "DragonHelm",
				Scale = 1.15,
				Bonus = { Type = "Income", Value = 0.18 },
				Lore = "Its armour is made of real dragon scales. They were a gift, it says.",
			}),
			golem({
				Id = "Flamewing",
				Name = "Flamewing",
				Rarity = "Epic",
				Body = rgb(190, 44, 44),
				Trim = rgb(90, 20, 26),
				Glow = rgb(255, 170, 40),
				Material = M.Slate,
				Accessory = "DragonWings",
				Scale = 1.15,
				Bonus = { Type = "WalkSpeed", Value = 0.15 },
				Lore = "Its little wings are too small to fly. It flaps them anyway, very fast.",
			}),
			golem({
				Id = "MagmaWyvern",
				Name = "Magma Wyvern",
				Rarity = "Legendary",
				Body = rgb(34, 28, 36),
				Trim = rgb(18, 14, 20),
				Glow = rgb(255, 100, 20),
				Material = M.Basalt,
				Accessory = "DragonWings",
				Scale = 1.22,
				Bonus = { Type = "MiningSpeed", Value = 0.3 },
				Lore = "Lava runs in its cracks. Rocks melt a little when it stares at them.",
			}),
			golem({
				Id = "DragonKing",
				Name = "Dragon King",
				Rarity = "Mythic",
				Body = rgb(38, 26, 36),
				Trim = rgb(200, 140, 40),
				Glow = rgb(255, 150, 30),
				Material = M.Basalt,
				Accessory = "DragonCrown",
				Scale = 1.3,
				Bonus = { Type = "Income", Value = 0.5 },
				Lore = "Crowned in the heart of the volcano. Every dragon in the sky bows to it.",
			}),
		},
	}),
	---------------------------------------------------------------- B: space
	Galaxy = theme({
		Id = "Galaxy",
		Title = "GALAXY GOLEMS",
		Tagline = "Golems from beyond the stars!",
		Backdrop = {
			SkyTop = rgb(10, 8, 34),
			SkyHorizon = rgb(120, 50, 170),
			Ground = rgb(36, 32, 70),
			Accent = rgb(80, 230, 255),
			Title = { rgb(150, 248, 255), rgb(170, 90, 255) },
		},
		Golems = {
			golem({
				Id = "AstroCadet",
				Name = "Astro Cadet",
				Rarity = "Rare",
				Body = rgb(226, 232, 248),
				Trim = rgb(70, 90, 170),
				Glow = rgb(90, 230, 255),
				Material = M.Slate,
				Accessory = "SpaceHelmet",
				Scale = 1.1,
				Bonus = { Type = "WalkSpeed", Value = 0.12 },
				Lore = "Its first space walk was yesterday. It still won't take the helmet off.",
			}),
			golem({
				Id = "CometCub",
				Name = "Comet Cub",
				Rarity = "Rare",
				Body = rgb(250, 150, 60),
				Trim = rgb(150, 70, 30),
				Glow = rgb(255, 226, 100),
				Material = M.Slate,
				Accessory = "Comet",
				Scale = 1.1,
				Bonus = { Type = "MiningSpeed", Value = 0.12 },
				Lore = "Fell from the sky with a comet on its head. The comet stayed.",
			}),
			golem({
				Id = "OrbitKeeper",
				Name = "Orbit Keeper",
				Rarity = "Epic",
				Body = rgb(110, 60, 190),
				Trim = rgb(56, 28, 110),
				Glow = rgb(120, 240, 255),
				Material = M.Slate,
				Accessory = "Orbiters",
				Scale = 1.15,
				Bonus = { Type = "Luck", Value = 0.18 },
				Lore = "Two tiny moons circle its head. It knows both of them by name.",
			}),
			golem({
				Id = "CosmoWizard",
				Name = "Cosmo Wizard",
				Rarity = "Epic",
				Body = rgb(46, 40, 130),
				Trim = rgb(24, 20, 70),
				Glow = rgb(255, 120, 230),
				Material = M.Slate,
				Accessory = "StarHat",
				Scale = 1.15,
				Bonus = { Type = "SellValue", Value = 0.2 },
				Lore = "Reads the stars like a shopping list. The stars say: sell now.",
			}),
			golem({
				Id = "NovaGuardian",
				Name = "Nova Guardian",
				Rarity = "Legendary",
				Body = rgb(40, 56, 150),
				Trim = rgb(220, 170, 60),
				Glow = rgb(80, 240, 255),
				Material = M.Slate,
				Accessory = "StarCrown",
				Scale = 1.22,
				Bonus = { Type = "Luck", Value = 0.3 },
				Lore = "Born in a star's last flash. A ring of light still follows it.",
			}),
			golem({
				Id = "NebulaTitan",
				Name = "Nebula Titan",
				Rarity = "Mythic",
				Body = rgb(100, 44, 176),
				Trim = rgb(40, 16, 86),
				Glow = rgb(255, 110, 240),
				Material = M.Slate,
				Accessory = "NebulaCrown",
				Scale = 1.3,
				Bonus = { Type = "Income", Value = 0.5 },
				Lore = "Made of a whole nebula, squeezed very small. Planets orbit its crown.",
			}),
		},
	}),
	---------------------------------------------------------------- C: robots
	MechaNeon = theme({
		Id = "MechaNeon",
		Title = "MECHA NEON",
		Tagline = "Chrome golems with neon power!",
		Backdrop = {
			SkyTop = rgb(14, 8, 40),
			SkyHorizon = rgb(220, 40, 170),
			Ground = rgb(28, 26, 44),
			Accent = rgb(0, 240, 255),
			Title = { rgb(120, 255, 255), rgb(255, 60, 200) },
		},
		Golems = {
			golem({
				Id = "BoltBot",
				Name = "Bolt Bot",
				Rarity = "Rare",
				Body = rgb(196, 204, 220),
				Trim = rgb(70, 76, 96),
				Glow = rgb(0, 230, 255),
				Material = M.Metal,
				Accessory = "NeonVisor",
				Scale = 1.1,
				Bonus = { Type = "MiningSpeed", Value = 0.12 },
				Lore = "Beeps when it finds ore. Beeps louder when it finds gold.",
			}),
			golem({
				Id = "BeatBot",
				Name = "Beat Bot",
				Rarity = "Rare",
				Body = rgb(255, 210, 60),
				Trim = rgb(60, 56, 80),
				Glow = rgb(255, 60, 200),
				Material = M.Metal,
				Accessory = "Headset",
				Scale = 1.1,
				Bonus = { Type = "WalkSpeed", Value = 0.12 },
				Lore = "Always dancing to music nobody else can hear.",
			}),
			golem({
				Id = "LaserRanger",
				Name = "Laser Ranger",
				Rarity = "Epic",
				Body = rgb(230, 236, 246),
				Trim = rgb(40, 70, 170),
				Glow = rgb(0, 255, 170),
				Material = M.Metal,
				Accessory = "MechaCrest",
				Scale = 1.15,
				Bonus = { Type = "Luck", Value = 0.18 },
				Lore = "Its scanner sees through rock. Hidden gems can't hide from it.",
			}),
			golem({
				Id = "RocketRex",
				Name = "Rocket Rex",
				Rarity = "Epic",
				Body = rgb(220, 50, 60),
				Trim = rgb(50, 46, 66),
				Glow = rgb(255, 230, 60),
				Material = M.Metal,
				Accessory = "Rockets",
				Scale = 1.15,
				Bonus = { Type = "MiningSpeed", Value = 0.18 },
				Lore = "Two rocket pods on its shoulders. They launch confetti.",
			}),
			golem({
				Id = "JetStriker",
				Name = "Jet Striker",
				Rarity = "Legendary",
				Body = rgb(60, 66, 90),
				Trim = rgb(24, 26, 40),
				Glow = rgb(0, 220, 255),
				Material = M.Metal,
				Accessory = "JetPack",
				Scale = 1.22,
				Bonus = { Type = "WalkSpeed", Value = 0.3 },
				Lore = "Its jet boots are always on. It hasn't touched the ground in years.",
			}),
			golem({
				Id = "OmegaMech",
				Name = "Omega Mech",
				Rarity = "Mythic",
				Body = rgb(236, 240, 250),
				Trim = rgb(30, 32, 52),
				Glow = rgb(255, 40, 190),
				Material = M.Metal,
				Accessory = "OmegaFrame",
				Scale = 1.3,
				Bonus = { Type = "Income", Value = 0.5 },
				Lore = "The last and greatest golem of the neon city. Its core runs on starlight.",
			}),
		},
	}),
	---------------------------------------------------------------- D: ice
	FrostTitans = theme({
		Id = "FrostTitans",
		Title = "FROST TITANS",
		Tagline = "Golems from the frozen north!",
		Backdrop = {
			SkyTop = rgb(8, 20, 50),
			SkyHorizon = rgb(60, 200, 170),
			Ground = rgb(196, 222, 240),
			Accent = rgb(110, 255, 210),
			Title = { rgb(240, 255, 255), rgb(70, 190, 255) },
		},
		Golems = {
			golem({
				Id = "Frostling",
				Name = "Frostling",
				Rarity = "Rare",
				Body = rgb(170, 220, 250),
				Trim = rgb(80, 140, 200),
				Glow = rgb(60, 200, 255),
				Material = M.Ice,
				Accessory = "IcicleHair",
				Scale = 1.1,
				Bonus = { Type = "WalkSpeed", Value = 0.12 },
				Lore = "Its icicle hair never melts, not even next to the furnace.",
			}),
			golem({
				Id = "GlacierCub",
				Name = "Glacier Cub",
				Rarity = "Rare",
				Body = rgb(220, 240, 255),
				Trim = rgb(120, 170, 220),
				Glow = rgb(70, 170, 255),
				Material = M.Ice,
				Accessory = "Beanie",
				Scale = 1.1,
				Bonus = { Type = "SellValue", Value = 0.12 },
				Lore = "Made of ice, and still always cold. Grandma knitted the hat.",
			}),
			golem({
				Id = "IceKnight",
				Name = "Icebound Knight",
				Rarity = "Epic",
				Body = rgb(130, 190, 240),
				Trim = rgb(40, 90, 170),
				Glow = rgb(100, 230, 255),
				Material = M.Ice,
				Accessory = "FrostHelm",
				Scale = 1.15,
				Bonus = { Type = "MiningSpeed", Value = 0.18 },
				Lore = "Guards the glacier gates. Its sword is a very sharp icicle.",
			}),
			golem({
				Id = "BlizzardSage",
				Name = "Blizzard Sage",
				Rarity = "Epic",
				Body = rgb(90, 120, 210),
				Trim = rgb(40, 50, 120),
				Glow = rgb(140, 255, 240),
				Material = M.Ice,
				Accessory = "SnowCloud",
				Scale = 1.15,
				Bonus = { Type = "Luck", Value = 0.18 },
				Lore = "Carries its own little snow cloud. It snows only on bad luck.",
			}),
			golem({
				Id = "PolarTitan",
				Name = "Polar Titan",
				Rarity = "Legendary",
				Body = rgb(200, 236, 255),
				Trim = rgb(70, 130, 200),
				Glow = rgb(0, 210, 255),
				Material = M.Ice,
				Accessory = "IcicleCrown",
				Scale = 1.22,
				Bonus = { Type = "SellValue", Value = 0.3 },
				Lore = "Wears a crown of icicles that grew on the highest peak of the north.",
			}),
			golem({
				Id = "AuroraColossus",
				Name = "Aurora Colossus",
				Rarity = "Mythic",
				Body = rgb(150, 210, 250),
				Trim = rgb(50, 70, 150),
				Glow = rgb(90, 255, 190),
				Material = M.Ice,
				Accessory = "AuroraCrown",
				Scale = 1.3,
				Bonus = { Type = "Income", Value = 0.5 },
				Lore = "The northern lights dance around its crown. Nobody has seen it melt.",
			}),
		},
	}),
} :: { [string]: Theme }

-- The four proposals in the order the owner sees them (A, B, C, D).
LimitedGolems.Order = { "Dragonforge", "Galaxy", "MechaNeon", "FrostTitans" }

-- Every limited golem by id (GolemBuilder reads it after GolemConfig.ById).
LimitedGolems.ById = {} :: { [string]: GolemConfig.Golem }
-- The theme a limited golem belongs to.
LimitedGolems.ThemeOf = {} :: { [string]: string }

for _, id in LimitedGolems.Order do
	local set = LimitedGolems.Themes[id]
	assert(set and set.Id == id, "LimitedGolems: bad theme " .. id)
	assert(#set.Golems == #LimitedGolems.SetRarities, "LimitedGolems: " .. id .. " needs 6 golems")
	for i, g in set.Golems do
		assert(g.Rarity == LimitedGolems.SetRarities[i], `LimitedGolems: {g.Id} should be {LimitedGolems.SetRarities[i]}`)
		assert(Rarity.ById[g.Rarity], "LimitedGolems: unknown rarity " .. g.Rarity)
		assert(GolemConfig.Accessories[g.Accessory], "LimitedGolems: unknown accessory " .. g.Accessory)
		local bonusType = GolemConfig.BonusTypes[g.Bonus.Type]
		assert(bonusType ~= nil, "LimitedGolems: bad bonus on " .. g.Id)
		assert(not GolemConfig.ById[g.Id] and not LimitedGolems.ById[g.Id], "LimitedGolems: duplicate id " .. g.Id)
		LimitedGolems.ById[g.Id] = g
		LimitedGolems.ThemeOf[g.Id] = id
	end
end

return LimitedGolems
