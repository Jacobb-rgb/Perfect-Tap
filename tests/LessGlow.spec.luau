-- Less glow (owner 2026-10-27: "you can barely see anything", worst on mine floors 3, 5 and 6):
-- every lighting preset blooms only what is white or brighter (neon, the sun's glints), the
-- caves no longer push their exposure up, and those floors' PointLights burn at MineKit.LightScale.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local GoldenStatue = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GoldenStatue")
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Common = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.Common")

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
			-- (0.4-0.5 with the old bloom washed them out on 10-27; the owner has since asked
			-- twice for a bit more brightness, so the guard is "below the washed-out values")
			T.lt(lighting.ExposureCompensation, 0.4, name .. " exposure")
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

	T.test("less glow: the statue cancels the town's exposure step (owner 2026-10-28: not the statue)", function()
		local step = LightingConfig.Presets.Surface.Lighting.ExposureCompensation - GoldenStatue.TunedExposure
		T.near(GoldenStatue.shadeFactor(), 2 ^ (-step / 2.2), 1e-9, "factor from the Surface exposure")
		T.truthy(GoldenStatue.shadeFactor() <= 1, "the town is not darker than when the statue was tuned")
		local k = GoldenStatue.shadeFactor()
		local folder = roblox.Instance.new("Folder")
		local ring = roblox.Instance.new("Model")
		ring.Parent = folder
		local own = roblox.Instance.new("Part")
		own.Color = roblox.Color3.new(1, 0.5, 0.25)
		own.Parent = ring
		GoldenStatue.build(ring, folder, roblox.Vector3.new(0, 0, 0), 0)
		T.near(own.Color.R, 1, 1e-6, "the ring's own pieces keep their color")
		local statue = folder:FindFirstChild("GoldenStatue")
		-- a shared color (Style.C.Fire, the sign's glow line) is shaded too, not only the gold
		local glow = statue:FindFirstChild("SignGlow", true)
		T.truthy(glow ~= nil, "the sign's glow line")
		local STEP = 1 / 255 -- part colors are stored in 8 bits a channel
		T.near(glow.Color.G, Style.C.Fire.G * k, STEP, "SignGlow shaded")
		local ringGlow = ring:FindFirstChild("StatueGlow", true)
		T.truthy(ringGlow ~= nil, "the pedestal's glow ring")
		T.near(ringGlow.Color.G, Common.Colors.RingOrange.G * k, STEP, "StatueGlow shaded")
		local flames = 0
		for _, d in statue:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				flames += 1
				T.near(d.Color.Keypoints[1].Value.G, Style.C.Fire.G * k, 1e-4, d.Name .. " shaded")
			end
		end
		T.truthy(flames > 0, "the wing flames are there")
	end)
end
