--[[
	Sounds. Pitch = random range for variation (juice!).

	Ids must play in today's Roblox clients. Only these files still ship in
	content/sounds (rbxasset://sounds/...): action_falling.ogg,
	action_footsteps_plastic.mp3, action_get_up.mp3, action_jump.mp3,
	action_jump_land.mp3, action_swim.mp3, impact_explosion_03.mp3,
	impact_water.mp3, oof.ogg, ouch.ogg, volume_slider.ogg. The classic
	sounds (clickfast.wav, snap.wav, glassbreak.wav ...) are gone from the
	client, but Roblox itself (user 1) uploaded them as public audio, so they
	play by id with no upload of our own:
	  button.wav 12221967 · clickfast.wav 12221976 · collide.wav 12221984 ·
	  electronicpingshort.wav 12221990 · flashbulb.wav 12221996 ·
	  glassbreak.wav 12222005 · hit.wav 12222046 · snap.wav 12222140 ·
	  swoosh.wav 12222200 · unsheath.wav 12222225 · victory.wav 12222253
	Other Roblox-made sounds used here: UFO Beam 162670130, Roblox Pinball
	low bells 16480570986. Better sounds from the Creator Store go in as
	"rbxassetid://<id>" (tests/BlasterFeel.spec.luau checks every id).
]]

export type SoundDef = { Id: string, Volume: number, Pitch: { number }, Looped: boolean? }

local SoundConfig: { [string]: SoundDef } = {
	-- laser blaster (MiningController, Effects/BlasterFx, BlasterFeel): the hum loop and a soft beam
	-- layer while firing, a zap when the trigger goes down, a crackle + a thud on hits, the break
	BlasterHum = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.22, Pitch = { 2.3, 2.4 }, Looped = true },
	BlasterStart = { Id = "rbxassetid://12221990", Volume = 0.35, Pitch = { 0.5, 0.56 } },
	BlasterStop = { Id = "rbxassetid://12221976", Volume = 0.25, Pitch = { 0.6, 0.7 } },
	BlastHit = { Id = "rbxassetid://12222140", Volume = 0.22, Pitch = { 1.7, 2.0 } },
	BlastBounce = { Id = "rbxassetid://12221967", Volume = 0.4, Pitch = { 0.5, 0.6 } },
	NodeCrack = { Id = "rbxassetid://12222140", Volume = 0.6, Pitch = { 0.55, 0.7 } },
	NodeShatter = { Id = "rbxassetid://12222005", Volume = 0.55, Pitch = { 0.45, 0.6 } },
	BlasterBeam = { Id = "rbxassetid://162670130", Volume = 0.12, Pitch = { 1.5, 1.6 }, Looped = true },
	BlasterZap = { Id = "rbxassetid://12221996", Volume = 0.35, Pitch = { 1.15, 1.3 } },
	BlastThud = { Id = "rbxassetid://12222046", Volume = 0.2, Pitch = { 0.85, 1.05 } },
	RockBreak = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.4, Pitch = { 1.3, 1.45 } },
	-- mine elevator (art/mine-floors): the arrival bell, the heavy door
	ElevatorDing = { Id = "rbxassetid://16480570986", Volume = 0.5, Pitch = { 1.0, 1.0 } },
	DoorThud = { Id = "rbxassetid://12221984", Volume = 0.6, Pitch = { 0.36, 0.42 } },
	-- the arrival sting with the floor banner, 0.2 s after the ding (victory.wav a little brighter)
	ElevatorArrive = { Id = "rbxassetid://12222253", Volume = 0.3, Pitch = { 1.2, 1.2 } },
	-- mine ambience (Config/MineAmbience; the lobby's AmbienceController plays them): quiet,
	-- positional, only shipped / Roblox-made ids. impact_water pitched way up is a thin drip,
	-- slowed down a thick lava blorp; the explosion slowed to a crawl a far rumble; the swim
	-- loop slowed down lapping water; swoosh.wav slowed a hollow breath through a hall and the
	-- pinball low bells lower still a far chime; the UFO beam slowed a crystal's hum and
	-- glassbreak.wav sped up its tinkle; the falling-wind loop slowed right down a low lava roar.
	-- (Not AmbPlop / AmbWaterfall / AmbBrook / ...: review/hory-noc has those names.)
	AmbDrip = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.1, Pitch = { 2.6, 3.2 } },
	AmbRumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.2, Pitch = { 0.28, 0.34 } },
	AmbLap = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.12, Pitch = { 0.66, 0.72 }, Looped = true },
	AmbRipple = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.06, Pitch = { 1.0, 1.2 } },
	AmbEcho = { Id = "rbxassetid://12222200", Volume = 0.06, Pitch = { 0.3, 0.36 } },
	AmbChime = { Id = "rbxassetid://16480570986", Volume = 0.05, Pitch = { 0.6, 0.66 } },
	AmbHum = { Id = "rbxassetid://162670130", Volume = 0.07, Pitch = { 0.62, 0.68 }, Looped = true },
	AmbTink = { Id = "rbxassetid://12222005", Volume = 0.03, Pitch = { 2.6, 3.0 } },
	AmbBubble = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.12, Pitch = { 0.42, 0.55 } },
	AmbLavaFlow = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.14, Pitch = { 0.3, 0.34 }, Looped = true },
	-- the Stormglass Rift's StormCrackle: snap.wav sped right up and soft is a spark's crackle,
	-- flashbulb.wav a little higher an electric zap
	AmbSpark = { Id = "rbxassetid://12222140", Volume = 0.05, Pitch = { 3.0, 3.6 } },
	AmbZap = { Id = "rbxassetid://12221996", Volume = 0.06, Pitch = { 1.5, 1.8 } },
	Pickup = { Id = "rbxassetid://12221976", Volume = 0.5, Pitch = { 1.1, 1.3 } },
	Drop = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = { 0.9, 1.1 } },
	Throw = { Id = "rbxassetid://12222200", Volume = 0.45, Pitch = { 1.0, 1.25 } },
	-- cleaning minigame (spray-washing; the chisel / scrape / polish keys stay: other packages may play them)
	Spray = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.35, Pitch = { 1.55, 1.7 }, Looped = true }, -- the hiss of the wand
	ChiselCrack = { Id = "rbxassetid://12222140", Volume = 0.75, Pitch = { 0.8, 1.15 } },
	ChiselScratch = { Id = "rbxassetid://12222200", Volume = 0.25, Pitch = { 1.6, 1.9 } },
	Chip = { Id = "rbxassetid://12221984", Volume = 0.5, Pitch = { 1.5, 1.8 } },
	Scrape = { Id = "rbxassetid://12222200", Volume = 0.3, Pitch = { 0.55, 0.7 }, Looped = true },
	DirtPop = { Id = "rbxassetid://12221976", Volume = 0.25, Pitch = { 0.7, 1.0 } },
	Polish = { Id = "rbxassetid://12221990", Volume = 0.25, Pitch = { 1.6, 2.0 } },
	Reveal = { Id = "rbxassetid://12222253", Volume = 0.6, Pitch = { 1.0, 1.0 } },
	-- machines and economy
	Sell = { Id = "rbxassetid://12221990", Volume = 0.5, Pitch = { 1.15, 1.3 } },
	Furnace = { Id = "rbxassetid://12222200", Volume = 0.4, Pitch = { 0.45, 0.55 } },
	Crusher = { Id = "rbxassetid://12221984", Volume = 0.5, Pitch = { 0.45, 0.6 } },
	AnvilClang = { Id = "rbxassetid://12222225", Volume = 0.6, Pitch = { 0.8, 1.0 } },
	Place = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.6, Pitch = { 0.7, 0.8 } },
	Gulp = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.45, Pitch = { 1.3, 1.5 } },
	MachineDone = { Id = "rbxassetid://12221976", Volume = 0.55, Pitch = { 0.75, 0.85 } },
	MachineHum = { Id = "rbxassetid://12222200", Volume = 0.15, Pitch = { 0.3, 0.35 }, Looped = true },
	Reject = { Id = "rbxassetid://12221967", Volume = 0.4, Pitch = { 0.5, 0.6 } },
	CoinBurst = { Id = "rbxassetid://12221990", Volume = 0.5, Pitch = { 1.4, 1.6 } },
	BuildRotate = { Id = "rbxassetid://12221976", Volume = 0.3, Pitch = { 1.3, 1.4 } },
	UIClick = { Id = "rbxassetid://12221976", Volume = 0.4, Pitch = { 1.0, 1.1 } },
	UIDeny = { Id = "rbxassetid://12221967", Volume = 0.4, Pitch = { 0.6, 0.7 } },
	Discovery = { Id = "rbxassetid://12221990", Volume = 0.55, Pitch = { 0.9, 0.9 } },
	-- ore trains: TrainController plays both on its own looping sounds (never the shared pool):
	-- the chuff pulses with the wheels (Pitch = slow..fast), the whistle is a short double toot.
	-- TODO(owner): both are the built-in falling-wind loop as a quiet, short-range stand-in (the
	-- "toot" is a soft hiss). Upload or pick a steam chuff loop and a steam whistle in the Creator
	-- Store and paste their rbxassetid:// ids here (then Volume ~0.4 / 0.35, whistle Pitch { 0.95, 1.05 }).
	TrainChuff = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.22, Pitch = { 0.45, 0.85 }, Looped = true },
	TrainWhistle = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.14, Pitch = { 1.75, 1.9 }, Looped = true },
	-- the Blaster Vault's crate opening (VaultController): the case lands, hums while it charges, bursts
	-- (glass crash + a soft boom), the blaster rises. Ids that play in today's clients: files shipped in
	-- content/sounds, or Roblox's own uploads of the classic sounds (12222005 = glassbreak.wav, 12222200 = swoosh.wav).
	CaseLand = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.75, Pitch = { 0.5, 0.55 } },
	CaseCharge = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.3, Pitch = { 1.5, 1.6 }, Looped = true },
	CaseBurst = { Id = "rbxassetid://12222005", Volume = 0.75, Pitch = { 0.42, 0.48 } },
	CaseBoom = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.35, Pitch = { 1.15, 1.25 } },
	CaseRise = { Id = "rbxassetid://12222200", Volume = 0.5, Pitch = { 0.55, 0.62 } },
	-- lobby ambience (AmbienceConfig, AmbienceController): quiet, positional, only shipped / Roblox-made ids.
	-- The swim loop slowed down is running water; impact_water a plop; electronicpingshort.wav sped up
	-- and repeated fast is a cricket's chirp; unsheath.wav a hammer ringing on the anvil; snap.wav high
	-- and soft the fire's crackle; the falling-wind loop slowed down the mountain wind.
	AmbWaterfall = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.4, Pitch = { 0.5, 0.56 }, Looped = true },
	AmbBrook = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.2, Pitch = { 0.85, 0.95 }, Looped = true },
	AmbPlop = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.12, Pitch = { 1.5, 1.9 } },
	AmbCricket = { Id = "rbxassetid://12221990", Volume = 0.05, Pitch = { 3.2, 3.6 } },
	AmbHammer = { Id = "rbxassetid://12222225", Volume = 0.25, Pitch = { 0.85, 1.0 } },
	AmbCrackle = { Id = "rbxassetid://12222140", Volume = 0.07, Pitch = { 1.8, 2.6 } },
	AmbWind = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.16, Pitch = { 0.5, 0.55 }, Looped = true },
}

return SoundConfig
