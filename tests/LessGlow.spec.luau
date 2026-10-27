-- Less glow (owner 2026-10-27: "you can barely see anything", worst on mine floors 3, 5 and 6):
-- every lighting preset blooms only what is white or brighter (neon, the sun's glints), the
-- caves no longer push their exposure up, and those floors' PointLights burn at MineKit.LightScale.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")

	T.test("less glow: every preset blooms only past white, small and soft", function()
		for name, preset in LightingConfig.Presets do
			local bloom = preset.Bloom
			if bloom.Threshold ~= nil then
				T.truthy(bloom.Threshold >= 1, `{name}: Threshold 1 or more (pale stone and sand must not bloom)`)
				T.le(bloom.Intensity, 1, `{name}: Intensity`)
				T.le(bloom.Size, 32, `{name}: Size`)
			end
		end
	end)

	T.test("less glow: floors 3, 5 and 6 keep their exposure low", function()
		for _, name in { "Lagoon", "Storm", "Core" } do
			local lighting = LightingConfig.Presets[name].Lighting
			-- (0.45-0.5 washed them out; 2026-10-28 a tiny bit brighter than 0.05)
			T.le(lighting.ExposureCompensation, 0.2, name .. " exposure")
			T.le(LightingConfig.Presets[name].Bloom.Intensity, 0.5, name .. " bloom")
		end
	end)

	T.test("less glow: MineKit.dimLights scales the listed floors only", function()
		for _, index in { 3, 5, 6 } do
			T.truthy(MineKit.LightScale[index] < 1, `floor {index} is dimmed`)
		end
		local function lit(): (any, any)
			local model = roblox.Instance.new("Model")
			local part = roblox.Instance.new("Part")
			part.Parent = model
			local light = roblox.Instance.new("PointLight")
			light.Brightness = 2
			light.Parent = part
			return model, light
		end
		local dimmed, a = lit()
		MineKit.dimLights(dimmed, 3)
		T.near(a.Brightness, 2 * MineKit.LightScale[3], 1e-6, "floor 3 light scaled")
		local kept, b = lit()
		MineKit.dimLights(kept, 1)
		T.near(b.Brightness, 2, 1e-6, "floor 1 light as built")
	end)
end
