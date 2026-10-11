--[[
	Lighting presets. "Surface" matches default.project.json (what you see in
	Studio). The client tweens between presets when you walk into a zone
	(see WorldLayout.Zones[*].Lighting and LightingController).
]]

export type Preset = {
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	ColorCorrection: { [string]: any },
	Bloom: { [string]: any },
	SunRays: { [string]: any },
}

local LightingConfig = {}

LightingConfig.TweenTime = 1.6

LightingConfig.Presets = {
	-- Golden-hour town: warm, cozy, saturated.
	Surface = {
		Lighting = {
			Brightness = 2.6,
			Ambient = Color3.new(0.27, 0.2, 0.18),
			OutdoorAmbient = Color3.new(0.55, 0.45, 0.4),
			ExposureCompensation = 0.15,
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.7,
		},
		Atmosphere = {
			Density = 0.32,
			Offset = 0.2,
			Color = Color3.new(0.86, 0.68, 0.55),
			Decay = Color3.new(0.55, 0.36, 0.3),
			Glare = 0.35,
			Haze = 1.6,
		},
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.12,
			Saturation = 0.2,
			TintColor = Color3.new(1, 0.96, 0.9),
		},
		Bloom = { Intensity = 0.85, Size = 30, Threshold = 0.95 },
		SunRays = { Intensity = 0.07, Spread = 0.6 },
	},
	-- Open quarry: a bit dustier and brighter.
	Quarry = {
		Lighting = {
			Brightness = 2.8,
			Ambient = Color3.new(0.3, 0.24, 0.2),
			OutdoorAmbient = Color3.new(0.58, 0.48, 0.42),
			ExposureCompensation = 0.1,
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.6,
		},
		Atmosphere = {
			Density = 0.38,
			Offset = 0.25,
			Color = Color3.new(0.9, 0.74, 0.58),
			Decay = Color3.new(0.6, 0.42, 0.32),
			Glare = 0.3,
			Haze = 2.2,
		},
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.1,
			Saturation = 0.15,
			TintColor = Color3.new(1, 0.95, 0.88),
		},
		Bloom = { Intensity = 0.8, Size = 28, Threshold = 0.95 },
		SunRays = { Intensity = 0.05, Spread = 0.6 },
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
			Contrast = 0.16,
			Saturation = 0.28,
			TintColor = Color3.new(1, 0.95, 0.88),
		},
		Bloom = { Intensity = 1.1, Size = 32, Threshold = 0.9 },
		SunRays = {},
	},
} :: { [string]: Preset }

return LightingConfig
