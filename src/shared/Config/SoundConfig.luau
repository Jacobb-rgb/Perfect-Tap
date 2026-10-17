--[[
	Sounds. Defaults are built-in Roblox client sounds (rbxasset://), which
	are free and need no upload. For better sounds, pick audio uploaded by
	Roblox in the Creator Store (Toolbox -> Audio) and paste the id like
	"rbxassetid://1234567". Pitch = random range for variation (juice!).
	See docs/ASSETS.md.
]]

export type SoundDef = { Id: string, Volume: number, Pitch: { number }, Looped: boolean? }

local SoundConfig: { [string]: SoundDef } = {
	-- laser blaster (placeholders: paste a laser hum / zap from the Creator Store here)
	BlasterHum = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.22, Pitch = { 2.3, 2.4 }, Looped = true },
	BlasterStart = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = { 0.5, 0.56 } },
	BlasterStop = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Pitch = { 0.6, 0.7 } },
	BlastHit = { Id = "rbxasset://sounds/snap.wav", Volume = 0.22, Pitch = { 1.7, 2.0 } },
	BlastBounce = { Id = "rbxasset://sounds/button.wav", Volume = 0.4, Pitch = { 0.5, 0.6 } },
	NodeCrack = { Id = "rbxasset://sounds/snap.wav", Volume = 0.6, Pitch = { 0.55, 0.7 } },
	NodeShatter = { Id = "rbxasset://sounds/glassbreak.wav", Volume = 0.55, Pitch = { 0.45, 0.6 } },
	Pickup = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Pitch = { 1.1, 1.3 } },
	Drop = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = { 0.9, 1.1 } },
	Throw = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.45, Pitch = { 1.0, 1.25 } },
	-- cleaning minigame
	ChiselCrack = { Id = "rbxasset://sounds/snap.wav", Volume = 0.75, Pitch = { 0.8, 1.15 } },
	ChiselScratch = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.25, Pitch = { 1.6, 1.9 } },
	Chip = { Id = "rbxasset://sounds/collide.wav", Volume = 0.5, Pitch = { 1.5, 1.8 } },
	Scrape = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.3, Pitch = { 0.55, 0.7 }, Looped = true },
	DirtPop = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Pitch = { 0.7, 1.0 } },
	Polish = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = { 1.6, 2.0 } },
	Reveal = { Id = "rbxasset://sounds/victory.wav", Volume = 0.6, Pitch = { 1.0, 1.0 } },
	-- machines and economy
	Sell = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = { 1.15, 1.3 } },
	Furnace = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4, Pitch = { 0.45, 0.55 } },
	Crusher = { Id = "rbxasset://sounds/collide.wav", Volume = 0.5, Pitch = { 0.45, 0.6 } },
	AnvilClang = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Pitch = { 0.8, 1.0 } },
	Place = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.6, Pitch = { 0.7, 0.8 } },
	Gulp = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.45, Pitch = { 1.3, 1.5 } },
	MachineDone = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.55, Pitch = { 0.75, 0.85 } },
	MachineHum = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.15, Pitch = { 0.3, 0.35 }, Looped = true },
	Reject = { Id = "rbxasset://sounds/button.wav", Volume = 0.4, Pitch = { 0.5, 0.6 } },
	CoinBurst = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = { 1.4, 1.6 } },
	BuildRotate = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3, Pitch = { 1.3, 1.4 } },
	UIClick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4, Pitch = { 1.0, 1.1 } },
	UIDeny = { Id = "rbxasset://sounds/button.wav", Volume = 0.4, Pitch = { 0.6, 0.7 } },
	Discovery = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Pitch = { 0.9, 0.9 } },
	-- ore trains: TrainController plays both on its own looping sounds (never the shared pool):
	-- the chuff pulses with the wheels (Pitch = slow..fast), the whistle is a short double toot.
	-- TODO(owner): both are the built-in falling-wind loop as a quiet, short-range stand-in (the
	-- "toot" is a soft hiss). Upload or pick a steam chuff loop and a steam whistle in the Creator
	-- Store and paste their rbxassetid:// ids here (then Volume ~0.4 / 0.35, whistle Pitch { 0.95, 1.05 }).
	TrainChuff = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.22, Pitch = { 0.45, 0.85 }, Looped = true },
	TrainWhistle = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.14, Pitch = { 1.75, 1.9 }, Looped = true },
}

return SoundConfig
