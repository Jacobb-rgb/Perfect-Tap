--[[
	JuiceConfig: the game-feel extras from the owner's two reels of
	2026-10-27 ("How do games make MINING feel satisfying?" and "How do
	games make a LEVEL UP feel satisfying?", docs/plans/REELS_2026-10-27_BRIEF.md).
	Client-only visuals and sounds: the server is unchanged. Every switch is
	read when it is used, so flipping one in Studio works at once.

	Mining (Controllers/MineJuiceController, Effects/RockCracks, UI/BagFly)
	  Cracks   dark zig-zag cracks on the rock's face toward you that grow
	           with every hit (its Health drops) and branch out
	  Glints   warm gold glints and flecks in those cracks, flaring on a hit:
	           ONE neutral colour for every rock (dirty ore never shows its
	           rarity before it is cleaned, docs/DESIGN_V2_NOTES.md)
	  Chips    a few rock chips in the crust colour fly off every hit (RockFx pool)
	  Tok      a dry knock on every hit, a crunch at every crack stage
	  BagFly   an ore you pick up pops up glowing at its spot, flies into
	           your carry slots (or the backpack button) and a +1 bumps there
	The break itself stays RockFx's (dust, chunks, ground ring, its sounds):
	the owner turned down a comic word over it (2026-10-27).
	Reduce motion (UI/Motion.reduced; Effects/MineJuiceRules): the cracks
	still grow (a still change on a hit) but their glints glow steady and
	never flare; no chips, no gold sparkle, no flight, no bump (a pickup only
	plays its sound).
	LevelUp (Controllers/LevelController, UI/LevelView, Effects/LevelBurst)
	  SlowFill the level-up fill races, then slows right before full ("you hold
	           your breath"); the full bar flashes white-hot for a beat
	  Whoosh   a rising whoosh while it fills and a WHOOSH! word by the bar
	  Chime    a warm chime with LEVEL UP!
	  Ripples  rings ripple out across the floor and light rays shoot out of
	           the character (on top of the pillar and the shockwave)
	  Ticks    the reward rows tick in one by one with a click, the coins
	           count up in clicks
	Reduce motion (UI/Motion.reduced) keeps its rules: no flash, rays,
	burst, pops or flights; words fade in and out at full size.
]]

local rgb = Color3.fromRGB

local JuiceConfig = {
	Mining = {
		Cracks = true,
		Glints = true,
		Chips = true,
		Tok = true,
		BagFly = true,
	},
	LevelUp = {
		SlowFill = true,
		Whoosh = true,
		Chime = true,
		Ripples = true,
		Ticks = true,
	},

	-- the cracks (Effects/RockCracks, Effects/CrackLogic)
	CrackColor = rgb(30, 24, 22), -- the dark crack (a deep warm black, not pure black)
	GlintColor = rgb(255, 212, 128), -- a pale warm gold: the same for every rock and ore, unlike every Rarity colour
	CrackRocks = 3, -- rocks with cracks at once (the oldest hit gives its parts back)
	CrackRocksPhone = 2,
	KeepHit = 0.5, -- seconds: a cracked rock hit this recently keeps its crack (a new rock waits)
	CrackRange = 80, -- studs from the camera: farther rocks get no cracks
	GlintFlaresPerSecond = 2.5, -- a rock's glints flare at most this often (hits come ~3 a second)
	HitGap = 0.12, -- seconds: a rock's hits closer than this count once (tok, chips)
	ChipRange = 60, -- studs from the camera: farther hits throw no chips
	TokPerSecond = 8, -- all rocks together

	-- the bag flight (UI/BagFly)
	DirtyChunk = rgb(120, 114, 108), -- a dirty ore's colour (HudView.DirtyColor: no rarity)
	Flyers = 6, -- ore icons in flight at once (more pickups only bump)
	SoundGap = 0.3, -- seconds: pickups in one pass rise, land and click once (not once each)
}

return JuiceConfig
