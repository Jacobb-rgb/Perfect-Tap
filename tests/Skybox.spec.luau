--[[
	The picture sky config (LightingConfig.Skybox): either no face is set
	(Roblox's default sky) or all six are valid asset ids, and the id parser
	accepts plain numbers and rbxassetid:// strings. skyboxReady() is what
	switches the sun's disc and Terrain.Clouds off.
]]
return function(T, Loader)
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")

	T.test("skybox ids parse", function()
		T.eq(LightingConfig.skyboxId("123456"), "rbxassetid://123456", "plain number")
		T.eq(LightingConfig.skyboxId(" rbxassetid://987 "), "rbxassetid://987", "content id")
		T.eq(LightingConfig.skyboxId(""), nil, "empty")
		T.eq(LightingConfig.skyboxId("abc"), nil, "junk")
	end)

	T.test("the skybox is all or nothing", function()
		local cfg = LightingConfig.Skybox
		local set = 0
		for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
			local value = cfg[face]
			T.eq(type(value), "string", face .. " is a string")
			if value ~= "" then
				T.truthy(LightingConfig.skyboxId(value), face .. " is an asset id")
				set += 1
			end
		end
		T.truthy(set == 0 or set == 6, "all six faces or none")
		T.eq(LightingConfig.skyboxReady(), set == 6, "ready only with all six")
	end)

	T.test("one missing face keeps the default sky", function()
		local cfg = LightingConfig.Skybox
		local saved = table.clone(cfg)
		for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
			cfg[face] = "123"
		end
		T.truthy(LightingConfig.skyboxReady(), "all six set")
		cfg.Up = ""
		T.falsy(LightingConfig.skyboxReady(), "five of six")
		for key, value in saved do
			cfg[key] = value
		end
	end)

	T.test("nothing covers the picture sky", function()
		T.eq(LightingConfig.Skybox.ShowSun, false, "no sun disc")
		T.eq(LightingConfig.Skybox.TerrainClouds, false, "no pink Terrain.Clouds")
	end)
end
