--[[
	Lighting presets. "Surface" matches default.project.json (what you see in
	Studio; tests/LobbySky.spec.luau keeps them identical). The client tweens
	between presets when you walk into a zone (see WorldLayout.Zones[*].Lighting
	and LightingController).

	The town is always at golden hour (docs/ART_DIRECTION.md section 7): a low
	sun over the west sea (LobbyLayout.SunDirection), a warm glow toward the
	sun and cool lavender distance away from it, pink and purple clouds. The
	concept (docs/art/lobby_concept.webp) is crisp and saturated: light haze
	only on the far horizon, cool purple-blue shadows against warm sunlight.
]]

export type Preset = {
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	ColorCorrection: { [string]: any },
	Bloom: { [string]: any },
	SunRays: { [string]: any },
	-- Preview-only sky dome colors (tools/preview/viewer.js); Roblox draws its
	-- own sky from the Sky object, the Atmosphere and the Clouds below.
	Sky: { [string]: any }?,
}

local LightingConfig = {}

LightingConfig.TweenTime = 1.6

-- The sun: Lighting.ClockTime and GeographicLatitude (same values in
-- default.project.json). Roblox's sun path cannot be computed offline, so the
-- client also searches once for the ClockTime/latitude pair whose
-- Lighting:GetSunDirection() is closest to LobbyLayout.SunDirection
-- (LightingController.alignSun) and prints the result in Studio: paste it here
-- and into default.project.json.
LightingConfig.Sun = {
	ClockTime = 17.6,
	GeographicLatitude = 23.5,
	AutoAlign = true,
	MaxError = 0.12, -- keep the static values when the best match is worse than this
}

-- The Sky object (default skybox, big low sun, no stars at golden hour).
LightingConfig.Sky = {
	SunAngularSize = 16,
	MoonAngularSize = 11,
	StarCount = 0,
	CelestialBodiesShown = true,
}

--[[
	Space skybox (owner 2026-10-17): Kenney Skyboxes Space "band" (CC0, a
	Milky Way band over violet space), cut into Roblox's six faces by
	tools/kenney/skybox.mjs with Yaw 97 and Tilt 18 so the band's bright core
	arches over the northern sky (~33 degrees up, above the massif) and the
	sunset haze stays on the horizon. Roblox can only show uploaded images:
	the owner uploads the six PNGs (NAHRAJ_DO_ROBLOXU/obloha_mlecna_draha) and
	pastes each asset id here. Until all six are set the place keeps
	Roblox's default sky (LightingController.applySkybox).
]]
LightingConfig.Skybox = {
	Bk = "",
	Dn = "",
	Ft = "",
	Lf = "",
	Rt = "",
	Up = "",
	-- how the faces were cut (the preview renderer's shot.skyboxYaw / skyboxTilt)
	Yaw = 97,
	Tilt = 18,
}

-- "123456", "rbxassetid://123456" or "" -> the content id or nil.
function LightingConfig.skyboxId(value: string): string?
	local digits = string.match(value, "^%s*(%d+)%s*$") or string.match(value, "rbxassetid://(%d+)")
	return if digits then "rbxassetid://" .. digits else nil
end

-- Workspace.Terrain.Clouds (created by the client if the place has none).
LightingConfig.Clouds = {
	Cover = 0.5,
	Density = 0.6,
	Color = Color3.fromRGB(255, 196, 176),
}

-- Sunset sky colors for the preview dome (= Style.C.SkyTop / SkyPurple /
-- SkyHorizon / Sun / CloudPink). MidAngle = degrees above the horizon where
-- the sky turns purple.
local SUNSET_SKY = {
	Top = Color3.fromRGB(50, 52, 138),
	Mid = Color3.fromRGB(156, 114, 198),
	Horizon = Color3.fromRGB(255, 162, 86),
	HorizonAway = Color3.fromRGB(246, 156, 178),
	Sun = Color3.fromRGB(255, 222, 150),
	MidAngle = 26,
}

-- Bloom and exposure (owner 2026-10-27: "you can barely see anything, it
-- all glows", worst on mine floors 3, 5 and 6): Roblox blooms every pixel
-- brighter than Threshold, and under 1 that took the pale sunlit stone, the
-- sand and the gold along with the neon, so the screen washed out. Every
-- preset keeps its Threshold over 1 (only neon and the sun's glints bloom),
-- a smaller, softer bloom, and the caves no longer push their exposure up.
-- Owner 2026-10-28: "just a tiny bit brighter everywhere": every exposure
-- went up a small step (town +0.07, caves +0.1); the bloom stayed.
LightingConfig.Presets = {
	-- Golden-hour town: low sun over the west sea, a light warm haze toward
	-- the sun, lavender distance, cool purple-blue shadows, crisp colors.
	Surface = {
		Lighting = {
			Brightness = 2.4,
			Ambient = Color3.new(0.27, 0.25, 0.35),
			OutdoorAmbient = Color3.new(0.5, 0.48, 0.62),
			ExposureCompensation = 0.12,
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.6,
		},
		Atmosphere = {
			Density = 0.26,
			Offset = 0.2,
			Color = Color3.new(1, 0.74, 0.56),
			Decay = Color3.new(0.52, 0.54, 0.8),
			Glare = 0.5,
			Haze = 0.9,
		},
		ColorCorrection = {
			Brightness = 0.01,
			Contrast = 0.2,
			Saturation = 0.28,
			TintColor = Color3.new(1, 0.98, 0.97),
		},
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.15 },
		SunRays = { Intensity = 0.12, Spread = 0.7 },
		Sky = SUNSET_SKY,
	},
	-- Open quarry: the same sunset, a bit dustier.
	Quarry = {
		Lighting = {
			Brightness = 2.4,
			Ambient = Color3.new(0.28, 0.25, 0.34),
			OutdoorAmbient = Color3.new(0.5, 0.47, 0.6),
			ExposureCompensation = 0.12,
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.55,
		},
		Atmosphere = {
			Density = 0.32,
			Offset = 0.2,
			Color = Color3.new(0.98, 0.74, 0.58),
			Decay = Color3.new(0.6, 0.5, 0.76),
			Glare = 0.45,
			Haze = 1.3,
		},
		ColorCorrection = {
			Brightness = 0.01,
			Contrast = 0.18,
			Saturation = 0.26,
			TintColor = Color3.new(1, 0.97, 0.95),
		},
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.15 },
		SunRays = { Intensity = 0.1, Spread = 0.7 },
		Sky = SUNSET_SKY,
	},
	-- Ember Caves: dark, orange lava glow, ores pop.
	EmberCaves = {
		Lighting = {
			Brightness = 0.6,
			Ambient = Color3.new(0.32, 0.19, 0.14),
			OutdoorAmbient = Color3.new(0.2, 0.12, 0.09),
			ExposureCompensation = 0.3,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 0.8,
		},
		Atmosphere = {
			Density = 0.45,
			Offset = 0.05,
			Color = Color3.new(0.45, 0.22, 0.14),
			Decay = Color3.new(0.25, 0.1, 0.08),
			Glare = 0,
			Haze = 2.5,
		},
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.2,
			Saturation = 0.3,
			TintColor = Color3.new(1, 0.9, 0.82),
		},
		Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.1 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Deep Hollow: cold and mysterious; rare ores glow in many colors.
	DeepHollow = {
		Lighting = {
			Brightness = 0.3,
			Ambient = Color3.new(0.2, 0.2, 0.3),
			OutdoorAmbient = Color3.new(0.12, 0.12, 0.18),
			ExposureCompensation = 0.3,
			EnvironmentDiffuseScale = 0.15,
			EnvironmentSpecularScale = 0.9,
		},
		Atmosphere = {
			Density = 0.5,
			Offset = 0,
			Color = Color3.new(0.16, 0.14, 0.26),
			Decay = Color3.new(0.08, 0.06, 0.14),
			Glare = 0,
			Haze = 2.8,
		},
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.22,
			Saturation = 0.35,
			TintColor = Color3.new(0.9, 0.92, 1),
		},
		Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.1 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- VIP Glimmer Grotto: sparkly teal.
	Grotto = {
		Lighting = {
			Brightness = 0.5,
			Ambient = Color3.new(0.18, 0.27, 0.28),
			OutdoorAmbient = Color3.new(0.08, 0.12, 0.12),
			ExposureCompensation = 0.3,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
		},
		Atmosphere = {
			Density = 0.42,
			Offset = 0,
			Color = Color3.new(0.2, 0.36, 0.38),
			Decay = Color3.new(0.1, 0.18, 0.2),
			Glare = 0,
			Haze = 2.4,
		},
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.18,
			Saturation = 0.3,
			TintColor = Color3.new(0.92, 1, 1),
		},
		Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.1 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Floor 3 (Deep Hollow re-themed, MineFloors): a cool crystal lagoon, teal water glow.
	Lagoon = {
		Lighting = {
			Brightness = 0.4,
			Ambient = Color3.new(0.16, 0.26, 0.32),
			OutdoorAmbient = Color3.new(0.08, 0.14, 0.18),
			ExposureCompensation = 0.15,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
		},
		Atmosphere = {
			Density = 0.36,
			Offset = 0,
			Color = Color3.new(0.12, 0.28, 0.36),
			Decay = Color3.new(0.06, 0.14, 0.22),
			Glare = 0,
			Haze = 1.8,
		},
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.2,
			Saturation = 0.34,
			TintColor = Color3.new(0.9, 1, 1),
		},
		Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Floor 4, Sunken Palace: dim violet halls, warm gold glints.
	Palace = {
		Lighting = {
			Brightness = 0.35,
			Ambient = Color3.new(0.26, 0.22, 0.34),
			OutdoorAmbient = Color3.new(0.14, 0.12, 0.2),
			ExposureCompensation = 0.3,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
		},
		Atmosphere = {
			Density = 0.42,
			Offset = 0,
			Color = Color3.new(0.3, 0.24, 0.4),
			Decay = Color3.new(0.16, 0.12, 0.24),
			Glare = 0,
			Haze = 2.2,
		},
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.2,
			Saturation = 0.3,
			TintColor = Color3.new(1, 0.96, 1),
		},
		Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.1 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Floor 6, Heartstone Core: floating rocks in a starry violet void, pink heart glow.
	Core = {
		Lighting = {
			Brightness = 0.3,
			Ambient = Color3.new(0.24, 0.18, 0.34),
			OutdoorAmbient = Color3.new(0.14, 0.1, 0.22),
			ExposureCompensation = 0.1,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
		},
		Atmosphere = {
			Density = 0.3,
			Offset = 0,
			Color = Color3.new(0.3, 0.14, 0.36),
			Decay = Color3.new(0.12, 0.06, 0.2),
			Glare = 0,
			Haze = 1.6,
		},
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.22,
			Saturation = 0.36,
			TintColor = Color3.new(1, 0.94, 1),
		},
		Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.6 },
		Sky = {
			Top = Color3.fromRGB(14, 10, 34),
			Mid = Color3.fromRGB(48, 22, 82),
			Horizon = Color3.fromRGB(150, 44, 120),
			HorizonAway = Color3.fromRGB(90, 30, 110),
			Sun = Color3.fromRGB(255, 120, 190),
			MidAngle = 22,
		},
	},
	-- Floor 5, Stormglass Rift: a dark indigo storm cavern lit by yellow-white lightning,
	-- cool navy shadows.
	Storm = {
		Lighting = {
			Brightness = 0.35,
			Ambient = Color3.new(0.26, 0.28, 0.4),
			OutdoorAmbient = Color3.new(0.12, 0.14, 0.22),
			ExposureCompensation = 0.15,
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 1,
		},
		Atmosphere = {
			Density = 0.38,
			Offset = 0,
			Color = Color3.new(0.2, 0.24, 0.4),
			Decay = Color3.new(0.1, 0.12, 0.26),
			Glare = 0,
			Haze = 1.6,
		},
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.22,
			Saturation = 0.3,
			TintColor = Color3.new(0.96, 0.98, 1),
		},
		Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Close-up while cleaning ore: extra warmth (no blur: the owner wants it sharp).
	Workbench = {
		Lighting = {},
		Atmosphere = {},
		ColorCorrection = {
			Brightness = 0.04,
			Contrast = 0.12,
			Saturation = 0.12,
			TintColor = Color3.new(1, 0.95, 0.88),
		},
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.1 },
		SunRays = {},
	},
	-- Inside the Blaster Vault (a part tagged LightingZone with Preset =
	-- "VaultInterior", src/server/World/Lobby/Vault): darker and moodier, so
	-- the glowing cases, the vault door and the candles stand out.
	VaultInterior = {
		Lighting = {
			Ambient = Color3.new(0.05, 0.04, 0.07),
			OutdoorAmbient = Color3.new(0.2, 0.18, 0.26),
			ExposureCompensation = -0.38,
			EnvironmentDiffuseScale = 0.15,
		},
		Atmosphere = {},
		ColorCorrection = {
			Brightness = -0.02,
			Contrast = 0.32,
			Saturation = 0.34,
			TintColor = Color3.new(1, 0.95, 0.9),
		},
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.05 },
		SunRays = {},
	},
	-- The crate-opening cinematic's dark round room (VaultController,
	-- Builders/CrateOpeningStage): almost no sun or sky light, so the case's
	-- glow, the light pillar and the blaster carry the scene; strong bloom.
	CrateOpening = {
		Lighting = {
			Brightness = 0.2,
			Ambient = Color3.new(0.16, 0.14, 0.22),
			OutdoorAmbient = Color3.new(0.06, 0.06, 0.1),
			ExposureCompensation = 0.25,
			EnvironmentDiffuseScale = 0.1,
			EnvironmentSpecularScale = 0.8,
		},
		Atmosphere = {
			Density = 0.3,
			Offset = 0,
			Color = Color3.new(0.1, 0.08, 0.18),
			Decay = Color3.new(0.05, 0.04, 0.1),
			Glare = 0,
			Haze = 1.5,
		},
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.24,
			Saturation = 0.3,
			TintColor = Color3.new(0.96, 0.95, 1),
		},
		Bloom = { Intensity = 0.9, Size = 32, Threshold = 1.0 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
} :: { [string]: Preset }

return LightingConfig
