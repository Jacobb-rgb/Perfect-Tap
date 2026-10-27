--[[
	WeatherConfig: the weather over Emberfall (owner reel 2026-10-27 "Make
	weather feel alive!", docs/plans/REELS_2026-10-27_BRIEF.md reel 3). Every
	number of the weather lives here; Weather/WeatherLogic is the pure math,
	Controllers/WeatherController + Effects/WeatherFx show it.

	  Rain      angled streaks, splashes and ripple rings on the ground, the
	            sky a little grey; a rainbow may follow it
	  Storm     heavier rain, the whole screen flashes, thunder a beat later
	  Hail      little ice balls that bounce off the ground and clack
	  Snow      slow drifting flakes; flakes settle on the ground for a while
	  Fog       soft layers of mist roll past near the ground, colours wash out
	  Wind      leaves blow across, the trees near you sway
	  Heatwave  warm tint, the sun cranked up, heat wobbling off the ground
	  Rainbow   (bonus) after a quick shower: a big arc opposite the sun

	The schedule needs no network at all: time is cut into slots of
	Schedule.Slot seconds and a slot's weather comes from a hash of the
	Seed and the slot number, so every player (and every server) computes
	the same weather from Workspace:GetServerTimeNow(). Most slots hold one
	event of 2-4 minutes, the rest of the time stays clear.

	Switches for the owner: Enabled turns the whole weather off, a kind's On
	= false (or Weight = 0) means it never comes. For a test in Studio set
	the Workspace attribute WeatherForce to a kind ("Rain", "Storm", "Hail",
	"Snow", "Fog", "Wind", "Heatwave", "Rainbow" or "Clear"); remove it to
	go back to the schedule.

	Phones get fewer particles (Phone), Reduce motion turns the lightning
	flashes and the tree sway off and halves the particles (Reduced).
	Weather shows only on the surface (Zones, OutsideMinY); the controller
	also hides it inside a LightingZone (the Blaster Vault), during the
	elevator ride, the cleaning close-up and the loading screen.
]]

local SoundConfig = require(script.Parent.SoundConfig)

-- "Clear" or one of Order: "Rain" | "Storm" | "Hail" | "Snow" | "Fog" | "Wind" | "Heatwave"
export type Kind = string

-- The weather's own ColorCorrectionEffect (WeatherTint): blended from neutral by the strength.
export type Tint = {
	Color: Color3, -- TintColor
	Brightness: number,
	Contrast: number,
	Saturation: number,
}

-- What a kind of weather does at full strength. Rates are particles per second on a PC
-- (Phone / Reduced scale them down); a missing rate = that emitter stays off.
export type Look = {
	On: boolean, -- false: never chosen by the schedule (WeatherForce still shows it)
	Weight: number, -- relative chance among the kinds that are on
	Duration: { number }, -- seconds { min, max } of the whole event, fades included
	Tint: Tint,
	Wind: number, -- studs per second: how far falling things drift (the rain's slant)
	Rain: number?, -- rain streaks
	Hail: number?, -- falling ice balls
	Snow: number?, -- flakes
	Leaves: number?, -- leaves blowing across (half green, half amber)
	Mist: number?, -- big soft mist puffs near the ground
	Heat: number?, -- faint heat wobble rising off the ground
	Splash: number?, -- per ground point: ripple rings + droplets
	Bounce: number?, -- per ground point: hail bouncing off the ground
	Settle: number?, -- per ground point: snow flakes lying on the ground
	Clack: number?, -- hail clacks per second (sounds at the ground points)
	Lightning: boolean?, -- flashes + thunder (Lightning)
	Rainbow: number?, -- chance of a rainbow once it ends (Rainbow)
	Sway: number?, -- radians: how far nearby trees lean (TreeSway)
	Loops: { [string]: number }?, -- loop sound (Sounds key) -> share of its volume
}

export type Particle = {
	Texture: string,
	Color: Color3,
	Color2: Color3?, -- a second colour (the amber leaves)
	Size: { number }, -- { min, max } studs (one random size per particle)
	Grow: number?, -- the size at the end of its life = Size * Grow (ripples grow)
	Speed: { number },
	Lifetime: { number },
	Transparency: number, -- while visible (it fades in and out at both ends)
	LightEmission: number,
	Squash: number?, -- stretches the particle along its velocity (rain streaks)
	Spread: number?, -- degrees
	Gravity: number?, -- studs/s^2 pulling down (droplets, bouncing hail)
	Drag: number?,
	RotSpeed: number?, -- degrees per second, random +-
	Orientation: string?, -- "VelocityParallel" | "VelocityPerpendicular" | "FacingCamera"
}

export type SoundDef = SoundConfig.SoundDef

local rgb = Color3.fromRGB

local WeatherConfig = {}

WeatherConfig.Enabled = true -- false: no weather anywhere (the controller does nothing)
WeatherConfig.ForceAttribute = "WeatherForce" -- Workspace attribute for tests in Studio (see the top)

-- The kinds in a fixed order (the weighted pick walks this list, so it is deterministic).
WeatherConfig.Order = { "Rain", "Storm", "Hail", "Snow", "Fog", "Wind", "Heatwave" } :: { Kind }

WeatherConfig.Schedule = {
	Seed = 271027, -- change to get a different sequence of weather
	Slot = 540, -- seconds: every 9 minutes at most one weather event
	EventChance = 0.7, -- share of the slots that get weather (the rest stay clear)
	FadeIn = 20, -- seconds the weather takes to build up
	FadeOut = 25, -- seconds it takes to clear
	Margin = 25, -- clear seconds at least at both ends of a slot
}

WeatherConfig.Kinds = {
	Rain = {
		On = true,
		Weight = 30,
		Duration = { 100, 190 },
		Tint = { Color = rgb(214, 224, 247), Brightness = -0.04, Contrast = 0.04, Saturation = -0.22 },
		Wind = 14,
		Rain = 650,
		Splash = 10,
		Rainbow = 0.6,
		Loops = { Rain = 0.75 },
	},
	Storm = {
		On = true,
		Weight = 14,
		Duration = { 150, 240 },
		Tint = { Color = rgb(156, 166, 212), Brightness = -0.12, Contrast = 0.1, Saturation = -0.42 },
		Wind = 24,
		Rain = 1000,
		Splash = 16,
		Leaves = 6,
		Lightning = true,
		Rainbow = 0.25,
		Sway = 0.035,
		Loops = { Rain = 1, Wind = 0.45 },
	},
	Hail = {
		On = true,
		Weight = 10,
		Duration = { 90, 150 },
		Tint = { Color = rgb(219, 229, 250), Brightness = -0.03, Contrast = 0.05, Saturation = -0.2 },
		Wind = 6,
		Rain = 110,
		Hail = 300,
		Bounce = 14,
		Clack = 9,
		Loops = { Rain = 0.35 },
	},
	Snow = {
		On = true,
		Weight = 12,
		Duration = { 150, 240 },
		Tint = { Color = rgb(237, 244, 255), Brightness = 0.04, Contrast = -0.04, Saturation = -0.18 },
		Wind = 4,
		Snow = 220,
		Settle = 3,
		Loops = { Wind = 0.25 },
	},
	Fog = {
		On = true,
		Weight = 14,
		Duration = { 150, 240 },
		Tint = { Color = rgb(236, 238, 250), Brightness = 0.07, Contrast = -0.24, Saturation = -0.4 },
		Wind = 2,
		Mist = 9,
	},
	Wind = {
		On = true,
		Weight = 12,
		Duration = { 120, 200 },
		Tint = { Color = rgb(255, 255, 255), Brightness = 0.01, Contrast = 0.03, Saturation = 0.03 },
		Wind = 26,
		Leaves = 40,
		Sway = 0.06,
		Loops = { Wind = 1 },
	},
	Heatwave = {
		On = true,
		Weight = 8,
		Duration = { 120, 200 },
		Tint = { Color = rgb(255, 230, 200), Brightness = 0.06, Contrast = 0.1, Saturation = 0.18 },
		Wind = 1,
		Heat = 6,
	},
} :: { [string]: Look }

-- The particles (shipped Roblox textures only: they load in every client with no upload).
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"

WeatherConfig.Particles = {
	Rain = {
		Texture = SQUARE,
		Color = rgb(206, 222, 255),
		Size = { 0.2, 0.26 }, -- Squash stretches it into a thin streak
		Speed = { 78, 92 },
		Lifetime = { 0.7, 0.85 },
		Transparency = 0.25,
		LightEmission = 0.25,
		Squash = 3,
		Spread = 2,
		Orientation = "VelocityParallel",
	},
	Hail = {
		Texture = SMOKE,
		Color = rgb(244, 250, 255),
		Size = { 0.4, 0.55 },
		Speed = { 58, 70 },
		Lifetime = { 0.95, 1.1 },
		Transparency = 0,
		LightEmission = 0.35,
		Spread = 3,
		RotSpeed = 180,
	},
	Snow = {
		Texture = SMOKE,
		Color = rgb(255, 255, 255),
		Size = { 0.35, 0.6 },
		Speed = { 4.5, 7 },
		Lifetime = { 7, 9 },
		Transparency = 0.05,
		LightEmission = 0.4,
		Spread = 12,
		Drag = 0.2,
		RotSpeed = 60,
	},
	Leaves = {
		Texture = SQUARE,
		Color = rgb(122, 196, 72),
		Color2 = rgb(236, 150, 52),
		Size = { 0.6, 1 },
		Speed = { 18, 28 },
		Lifetime = { 3, 4.2 },
		Transparency = 0,
		LightEmission = 0,
		Spread = 18,
		Gravity = 3,
		RotSpeed = 260,
	},
	Mist = {
		Texture = SMOKE,
		Color = rgb(240, 236, 246),
		Size = { 16, 26 },
		Speed = { 1, 3 },
		Lifetime = { 9, 12 },
		Transparency = 0.84,
		LightEmission = 0.15,
		Spread = 30,
		RotSpeed = 8,
	},
	Heat = {
		Texture = SMOKE,
		Color = rgb(255, 238, 214),
		Size = { 6, 10 },
		Speed = { 1.5, 2.6 },
		Lifetime = { 3, 4 },
		Transparency = 0.9,
		LightEmission = 0.3,
		Spread = 20,
		RotSpeed = 30,
	},
	-- at the ground points
	Ripple = {
		Texture = RING,
		Color = rgb(226, 236, 255),
		Size = { 0.2, 0.3 },
		Grow = 6,
		Speed = { 0.05, 0.05 },
		Lifetime = { 0.4, 0.55 },
		Transparency = 0.3,
		LightEmission = 0.3,
		Orientation = "VelocityPerpendicular",
	},
	Drop = {
		Texture = SMOKE,
		Color = rgb(226, 236, 255),
		Size = { 0.1, 0.16 },
		Speed = { 5, 8 },
		Lifetime = { 0.22, 0.3 },
		Transparency = 0.2,
		LightEmission = 0.3,
		Spread = 35,
		Gravity = 70,
	},
	Bounce = {
		Texture = SMOKE,
		Color = rgb(244, 250, 255),
		Size = { 0.24, 0.34 },
		Speed = { 6, 10 },
		Lifetime = { 0.4, 0.5 },
		Transparency = 0,
		LightEmission = 0.35,
		Spread = 40,
		Gravity = 85,
	},
	Settle = {
		Texture = SMOKE,
		Color = rgb(255, 255, 255),
		Size = { 0.9, 1.6 },
		Speed = { 0.05, 0.05 },
		Lifetime = { 7, 10 },
		Transparency = 0.15,
		LightEmission = 0.2,
		Orientation = "VelocityPerpendicular",
	},
} :: { [string]: Particle }

-- The boxes that follow the camera: the sky box (rain, hail, snow fall out of its bottom) and
-- the air box at eye height (leaves, mist, heat). Both lean a little ahead of the camera.
WeatherConfig.Box = {
	Size = Vector3.new(60, 2, 60), -- the sky box
	Height = 32, -- studs above the camera
	Ahead = 20, -- studs ahead of the camera (flat): most of what falls is in view
	Air = Vector3.new(70, 16, 70), -- the air box
	AirHeight = -2, -- its centre relative to the camera's height
	Upwind = 22, -- the air box sits this far upwind, so leaves cross the view
}

-- Ground points: a few invisible pads put down by raycasts near the camera; splashes,
-- bouncing hail, settling snow and the hail clacks come from them.
WeatherConfig.Ground = {
	Points = 6,
	Pad = 7, -- studs: a pad's width (its splashes spread over it)
	Ahead = 26, -- studs: the pads land round a spot this far ahead of the camera (flat)
	Radius = 26, -- around that spot (so all of them are in front of the camera)
	RayHeight = 60, -- the ray starts this far above the camera
	RayLength = 220,
	PerTick = 2, -- pads moved per check (they wander so the splashes spread)
}

WeatherConfig.Lightning = {
	First = 8, -- seconds into the storm before the first strike
	Window = 12, -- seconds: one strike per window at most (at a random moment in it)
	MinGap = 4, -- seconds between two strikes at least
	Chance = 0.85, -- share of the windows with a strike
	MinIntensity = 0.45, -- strikes only while the storm is at least this strong
	Delay = { 0.45, 2.6 }, -- seconds from the flash to its thunder (a beat later)
	CrackBelow = 0.9, -- a close strike (shorter delay) also cracks
	Peak = 0.42, -- WeatherTint.Brightness added by the flash
	Second = 0.24, -- the flicker after it
	Flicker = 0.11, -- seconds from the flash to the flicker
	Length = 0.55, -- seconds until the flash is gone
}

WeatherConfig.Rainbow = {
	On = true,
	Seconds = 55, -- how long it shows
	FadeIn = 6,
	FadeOut = 14,
	Lead = 10, -- it starts this many seconds before the rain is gone
	Distance = 420, -- studs from the camera to the centre of the arc (closer = less haze over it)
	Angle = 42, -- the arc's radius in degrees (a real rainbow's)
	Band = 1.1, -- degrees per colour band (wider than a real one: it reads on phones)
	Transparency = 0.42, -- of a band at full strength
	LightEmission = 0.65,
	FootFade = 0.92, -- the transparency at the arc's feet
	Colors = { -- outside in
		rgb(255, 92, 92),
		rgb(255, 168, 72),
		rgb(255, 236, 104),
		rgb(116, 222, 116),
		rgb(96, 168, 255),
		rgb(176, 120, 240),
	},
	Tint = { Color = rgb(255, 250, 238), Brightness = 0.03, Contrast = 0.04, Saturation = 0.1 }, -- the sun is back
}

-- Trees near you lean with the wind (Wind, Storm): models named "Tree" in the map, nearest
-- first, rotated about the bottom of their bounding box. Client only, restored exactly.
WeatherConfig.TreeSway = {
	On = true,
	Max = 6, -- trees at most
	Radius = 80, -- studs from the camera
	MaxParts = 40, -- a tree with more parts is skipped (cost)
	Speed = 1.6, -- radians per second of the sway wave
	Rescan = 2, -- seconds between picks of the nearest trees
}

WeatherConfig.Phone = {
	Rate = 0.45, -- particles
	GroundPoints = 3,
	Mist = 0.6, -- the big mist puffs cost the most (overdraw)
	TreeSway = 3,
}

WeatherConfig.Reduced = {
	Rate = 0.5,
	Flash = false, -- no lightning flashes (photosensitivity); the thunder still plays
	Sway = false,
}

-- Where weather shows: WorldLayout zones by Id (true = yes). Outside every zone box (the sea,
-- the sky islands) it shows above OutsideMinY. The Quarry is an open pit, but it is mine floor 1:
-- off like the other floors (set it true to have weather down there too).
WeatherConfig.Zones = {
	Emberfall = true,
	Outcrops = true,
	SkyHaven = true,
	Quarry = false,
} :: { [string]: boolean }
WeatherConfig.OutsideMinY = -20

WeatherConfig.GateFade = 0.6 -- seconds: weather fades this fast when you go down / indoors
WeatherConfig.CheckEvery = 0.25 -- seconds between the controller's checks
WeatherConfig.TintSmooth = 6 -- per second: how fast the tint follows its target

-- Sounds: Roblox's own public audio (creator id 1) and a shipped file, so they play with no
-- upload. Rain = "Rain Effect" (59 s loop), Thunder = HalloweenThunder.wav, Crack =
-- HalloweenLightning.wav, Clack = clickfast.wav sped up, Wind = the falling-wind loop slowed
-- (SoundConfig.AmbWind's sound). Snow, fog and the heatwave are silent.
WeatherConfig.Group = "TerraForgeWeather"
WeatherConfig.ParentGroup = "TerraForgeSfx" -- SettingsConfig.SfxGroup: the SETTINGS sound slider
WeatherConfig.Sounds = {
	Rain = { Id = "rbxassetid://1516791621", Volume = 0.45, Pitch = { 1, 1 }, Looped = true },
	Wind = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.32, Pitch = { 0.42, 0.48 }, Looped = true },
	Thunder = { Id = "rbxassetid://12222030", Volume = 0.65, Pitch = { 0.78, 0.98 } },
	Crack = { Id = "rbxassetid://12222019", Volume = 0.32, Pitch = { 0.95, 1.1 } },
	Clack = { Id = "rbxassetid://12221976", Volume = 0.09, Pitch = { 2.1, 2.9 } },
} :: { [string]: SoundDef }

export type Config = typeof(WeatherConfig)

return WeatherConfig
