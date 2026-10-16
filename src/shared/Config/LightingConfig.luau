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

LightingConfig.Presets = {
	-- Golden-hour town: low sun over the west sea, a light warm haze toward
	-- the sun, lavender distance, cool purple-blue shadows, crisp colors.
	Surface = {
		Lighting = {
			Brightness = 2.4,
			Ambient = Color3.new(0.27, 0.25, 0.35),
			OutdoorAmbient = Color3.new(0.5, 0.48, 0.62),
			ExposureCompensation = 0.15,
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
		Bloom = { Intensity = 0.9, Size = 32, Threshold = 0.92 },
		SunRays = { Intensity = 0.12, Spread = 0.7 },
		Sky = SUNSET_SKY,
	},
	-- Open quarry: the same sunset, a bit dustier.
	Quarry = {
		Lighting = {
			Brightness = 2.4,
			Ambient = Color3.new(0.28, 0.25, 0.34),
			OutdoorAmbient = Color3.new(0.5, 0.47, 0.6),
			ExposureCompensation = 0.15,
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
		Bloom = { Intensity = 0.85, Size = 30, Threshold = 0.93 },
		SunRays = { Intensity = 0.1, Spread = 0.7 },
		Sky = SUNSET_SKY,
	},
	-- Ember Caves: dark, orange lava glow, ores pop.
	EmberCaves = {
		Lighting = {
			Brightness = 0.6,
			Ambient = Color3.new(0.32, 0.19, 0.14),
			OutdoorAmbient = Color3.new(0.2, 0.12, 0.09),
			ExposureCompensation = 0.35,
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
		Bloom = { Intensity = 1.0, Size = 32, Threshold = 0.92 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Deep Hollow: cold and mysterious; rare ores glow in many colors.
	DeepHollow = {
		Lighting = {
			Brightness = 0.3,
			Ambient = Color3.new(0.2, 0.2, 0.3),
			OutdoorAmbient = Color3.new(0.12, 0.12, 0.18),
			ExposureCompensation = 0.45,
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
		Bloom = { Intensity = 1.05, Size = 32, Threshold = 0.92 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- VIP Glimmer Grotto: sparkly teal.
	Grotto = {
		Lighting = {
			Brightness = 0.5,
			Ambient = Color3.new(0.18, 0.27, 0.28),
			OutdoorAmbient = Color3.new(0.08, 0.12, 0.12),
			ExposureCompensation = 0.4,
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
		Bloom = { Intensity = 1.0, Size = 32, Threshold = 0.92 },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Close-up while cleaning ore: soft focus, extra warmth.
	Workbench = {
		Lighting = {},
		Atmosphere = {},
		ColorCorrection = {
			Brightness = 0.04,
			Contrast = 0.12,
			Saturation = 0.12,
			TintColor = Color3.new(1, 0.95, 0.88),
		},
		Bloom = { Intensity = 1.1, Size = 32, Threshold = 0.9 },
		SunRays = {},
	},
} :: { [string]: Preset }

return LightingConfig
