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
	"Snow", "Wind", "Heatwave", "Rainbow" or "Clear"); remove it to go back
	to the schedule. (Fog was removed on 2026-10-27: the owner did not want it.)

	Always a clear view (owner 2026-10-27): no rain, hail or snow falls
	within a kind's Clear studs of the camera (a hole in the sky field round
	the camera's fall line, Box), the ring round that hole has smaller,
	fainter particles, the field moves with the camera (walking never
	carries the lens into falling flakes), and the ground pads stay
	Ground.Clear studs from the camera.

	Phones get fewer particles (Phone), Reduce motion turns the lightning
	flashes and the tree sway off and halves the particles (Reduced).
	Weather shows only on the surface (Zones, OutsideMinY, not in the
	Covered places); the controller also hides it under a roof (Roof: a few
	short rays up from the character, with a hold so it never blinks),
	inside a LightingZone (the Blaster Vault), during the elevator ride, the
	cleaning close-up and the loading screen.
]]

local SoundConfig = require(script.Parent.SoundConfig)
local LobbyLayout = require(script.Parent.LobbyLayout)
local WorldLayout = require(script.Parent.WorldLayout)

-- "Clear" or one of Order: "Rain" | "Storm" | "Hail" | "Snow" | "Wind" | "Heatwave"
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
	Heat: number?, -- faint heat wobble rising off the ground
	Splash: number?, -- per ground point: ripple rings + droplets
	Bounce: number?, -- per ground point: hail bouncing off the ground
	Settle: number?, -- per ground point: snow flakes lying on the ground
	Clack: number?, -- hail clacks per second (sounds at the ground points)
	Lightning: boolean?, -- flashes + thunder (Lightning)
	Rainbow: number?, -- chance of a rainbow once it ends (Rainbow)
	Sway: number?, -- radians: how far nearby trees lean (TreeSway)
	Loops: { [string]: number }?, -- loop sound (Sounds key) -> share of its volume
	Clear: number?, -- studs: no rain / hail / snow falls this close to the camera (Box.Clear if nil)
	Height: number?, -- studs: the sky field above the camera for this kind (Box.Height if nil)
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
WeatherConfig.Order = { "Rain", "Storm", "Hail", "Snow", "Wind", "Heatwave" } :: { Kind }

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
		Clear = 6,
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
		Clear = 6,
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
		Clear = 9,
	},
	Snow = {
		On = true,
		Weight = 12,
		Duration = { 150, 240 },
		Tint = { Color = rgb(237, 244, 255), Brightness = 0.04, Contrast = -0.04, Saturation = -0.18 },
		Wind = 2.5,
		Snow = 220,
		Settle = 3,
		Loops = { Wind = 0.25 },
		Clear = 14, -- big soft flakes: the widest clear view
		Height = 20, -- slow flakes start lower, so they come down round the player (WeatherLogic.travel)
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
		Lifetime = { 0.75, 0.9 },
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
		Speed = { 5.5, 7.5 },
		Lifetime = { 8, 10 },
		Transparency = 0.05,
		LightEmission = 0.4,
		Spread = 4, -- (small: the flakes must not drift into the clear view)
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
		Size = { 0.4, 0.75 }, -- small: a flake on the ground never reads as a smudge
		Speed = { 0.05, 0.05 },
		Lifetime = { 7, 10 },
		Transparency = 0.25,
		LightEmission = 0.2,
		Orientation = "VelocityPerpendicular",
	},
} :: { [string]: Particle }

-- What follows the camera. The sky field (rain, hail, snow fall out of it) is Field studs wide,
-- Height studs above the camera (or a kind's own Height), leaning with the wind, with a square
-- hole round the camera's fall line: a kind's Clear studs plus what the particles' spread can
-- drift on the way down (WeatherLogic.hole). It is 8 strips: the inner ring (NearWidth wide)
-- with smaller, fainter particles (NearSize, NearAlpha) and the outer ring. Whatever falls must
-- stay visible until Below studs under the camera (WeatherLogic.travel / reach, the spec). The
-- air box (leaves, heat) stands from the ground up, Ahead studs ahead of the camera and Upwind
-- studs upwind.
WeatherConfig.Box = {
	Field = 72,
	Height = 32,
	Below = 8, -- studs: what falls stays visible at least this far below the camera (the ground)
	Clear = 6, -- studs: the clear view of a kind without its own Clear
	NearWidth = 10,
	NearSize = 0.6, -- size share of a particle in the inner ring
	NearAlpha = 0.45, -- opacity share (1 - Transparency) in the inner ring
	Ahead = 20,
	Air = Vector3.new(70, 16, 70),
	Upwind = 22, -- so leaves cross the view
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
	Clear = 14, -- studs: no pad (splash, bouncing hail, settled flake) this close to the camera
	Tries = 3, -- raycasts per pad move to find a spot far enough
}

WeatherConfig.Lightning = {
	First = 8, -- seconds into the storm before the first strike
	Window = 12, -- seconds: one strike per window at most (at a random moment in it)
	MinGap = 4, -- seconds between two strikes at least
	Chance = 0.85, -- share of the windows with a strike
	MinIntensity = 0.45, -- strikes only while the storm is at least this strong
	Delay = { 0.45, 2.6 }, -- seconds from the flash to its thunder (a beat later)
	CrackBelow = 0.9, -- a close strike (shorter delay) also cracks
	MinFlashGap = 1, -- seconds between two flashes at least (with the flicker: at most 2 a second)
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

-- Under a roof (the DROPPERS shop, THE GREAT FORGE's nave) the weather goes. Every check one ray
-- goes straight up from the character and Rays more from round it (a triangle Spread studs out);
-- each goes on past what is no roof (WeatherLogic.roofCounts: see-through parts, trees, parts
-- that do not collide) for at most Hops hits and Reach studs (SKY HAVEN's islets and the sky
-- islands far above never count). Covered = the ray over the player AND Sides of the others hit
-- (a block or a wheel rim beside you never counts on its own), and the reading must hold Hold
-- seconds before the weather goes or comes back (no blinking under lamps and arches).
-- Ghost roofs (Style.ghost / tiny: CanQuery off, no ray sees them: the EGGS temple's drum, THE
-- GREAT FORGE's side roofs) are Covered shapes below instead.
WeatherConfig.Roof = {
	Rays = 3,
	Spread = 5,
	Sides = 1,
	Reach = 24, -- studs: about one building
	Hops = 4,
	Hold = 0.5,
	SeeThrough = 0.9, -- a part this transparent (or more) is no roof
}

-- A place with no weather even where the zones say surface: a box (CFrame at its centre, Size)
-- or, Round, an upright cylinder (Size.X across, Size.Y high).
export type Covered = {
	Name: string,
	CFrame: CFrame,
	Size: Vector3,
	Round: boolean?,
}

-- The Covered places, from the map's own layout (no map change):
--   GrottoTunnel  the tunnel from the Quarry to the VIP Glimmer Grotto (World/Land builds it
--                 between the two zones, under solid rock)
--   EggsTemple    under the EGGS temple's drum (Districts/Capsules: the drum is 17.4 across, its
--                 underside 10.5 up, centred 0.3 behind the piece's centre)
--   ForgeAisleL/R under THE GREAT FORGE's wide side roofs (Plaza/GreatForge: local x 14.2 .. 21
--                 either side, z NaveRoofZ0 + 0.6 = -10.6 .. 21.5, the eave 17.4 up at the edge)
do
	local grotto = WorldLayout.Caves.Grotto
	local door = grotto.Entrance
	local x0, x1 = WorldLayout.Quarry.Max.X - 1, grotto.Min.X + 1
	local y0, y1 = door.Position.Y - 3, door.Position.Y + door.Height + 1
	local z0, z1 = door.Position.Z - door.Width / 2 - 2, door.Position.Z + door.Width / 2 + 2
	local eggs = LobbyLayout.frame(LobbyLayout.get("CapsuleStall"))
	local forge = LobbyLayout.frame(LobbyLayout.get("GreatForge"))
	local aisleX0, aisleX1 = 13.7, 21 -- (a little under the nave's eave)
	local aisleZ0, aisleZ1 = -10.6, 21.5
	local aisleY0, aisleY1 = -3, 17.4
	local list: { Covered } = {
		{
			Name = "GrottoTunnel",
			CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
			Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		},
		{
			Name = "EggsTemple",
			CFrame = eggs * CFrame.new(0, (-2 + 10.5) / 2, 0.3),
			Size = Vector3.new(17.4, 10.5 + 2, 17.4),
			Round = true,
		},
	}
	for _, side in { -1, 1 } do
		table.insert(list, {
			Name = if side < 0 then "ForgeAisleL" else "ForgeAisleR",
			CFrame = forge * CFrame.new(side * (aisleX0 + aisleX1) / 2, (aisleY0 + aisleY1) / 2, (aisleZ0 + aisleZ1) / 2),
			Size = Vector3.new(aisleX1 - aisleX0, aisleY1 - aisleY0, aisleZ1 - aisleZ0),
		})
	end
	WeatherConfig.Covered = list
end

-- Trees near you lean with the wind (Wind, Storm): models named "Tree" in the map, nearest
-- first, rotated about the bottom of their bounding box. Client only, restored exactly.
WeatherConfig.TreeSway = {
	On = true,
	Max = 6, -- trees at most
	Radius = 80, -- studs from the camera
	MaxParts = 40, -- a tree with more parts is skipped (cost)
	Speed = 1.6, -- radians per second of the sway wave
	Rescan = 2, -- seconds between picks of the nearest trees
	ScanBudget = 0.001, -- seconds per frame the tree search may take (spread over frames: no hitch)
	ScanEvery = 200, -- children between two looks at the clock (a folder can hold thousands)
	ScanAge = 60, -- seconds a tree search stays good (the next windy spell after that searches again)
}

WeatherConfig.Phone = {
	Rate = 0.45, -- particles
	GroundPoints = 3,
	TreeSway = 3,
}

WeatherConfig.Reduced = {
	Rate = 0.5,
	Flash = false, -- no lightning flashes (photosensitivity); the thunder still plays
	Sway = false,
	Heat = false, -- no wobbling heat puffs (the warm tint stays)
	-- (the rainbow only fades in and out over seconds: it stays)
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
-- (SoundConfig.AmbWind's sound). Snow and the heatwave are silent.
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
