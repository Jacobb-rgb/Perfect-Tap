--[[
	The DRAGONFORGE banner backdrop (tools/lune/lib/limited_golems_preview.luau
	loads it for scene "limited_Dragonforge"): returns the scene's Look.
	H = Preview.Helpers (block, ball, disc, light, emitter, strip, ...).
]]

local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local rgb = Color3.fromRGB
local M = roblox.Enum.Material
local PI = math.pi

-- a flat dragon silhouette in a frame `d` (x right, y up, facing the camera), `k` its size
local function dragon(kit: any, block: any, d: any, k: number, ink: any)
	local CF = kit.CF
	local function piece(x: number, y: number, angle: number, sx: number, sy: number)
		block(kit, d * CF.new(x * k, y * k, 0) * CF.Angles(0, 0, angle), Vector3.new(sx * k, sy * k, 1.5), ink)
	end
	local function tri(a: { number }, b: { number }, c: { number })
		kit.Geo.triangle(
			kit.Folder,
			(d * CF.new(a[1] * k, a[2] * k, 0)).Position,
			(d * CF.new(b[1] * k, b[2] * k, 0)).Position,
			(d * CF.new(c[1] * k, c[2] * k, 0)).Position,
			1.2,
			ink
		)
	end
	piece(0, 0, 0.05, 24, 5.5) -- body
	piece(13, 4.5, 0.75, 12, 3.2) -- neck
	piece(19.5, 10, 0.25, 6, 3.4) -- head
	piece(24, 9.4, 0.05, 5, 2) -- snout
	piece(17.5, 12.6, 2.6, 5, 0.9) -- horns
	piece(16.8, 11.4, 2.85, 4.4, 0.8)
	piece(-15, -2, 0.2, 12, 3.2) -- tail
	piece(-25, -5.2, 0.4, 10, 2)
	piece(-33, -5.6, -0.5, 8, 1.4)
	piece(-37.5, -2.6, 0.785, 4, 4) -- the tail's spade
	piece(6, -4.4, -0.5, 2, 5) -- legs
	piece(-6, -4.4, -0.35, 2, 5)
	-- the near wing: arm up to the wrist, fingers fanning back, a scalloped edge
	tri({ 4, 2 }, { -2, 30 }, { -14, 2 })
	tri({ -2, 30 }, { -30, 22 }, { -14, 2 })
	tri({ -2, 30 }, { -18, 34 }, { -30, 22 })
	-- the far wing peeking over the body
	tri({ 8, 3 }, { 14, 24 }, { 2, 8 })
	tri({ 14, 24 }, { 2, 26 }, { 2, 8 })
end

-- Dragonforge: a volcano with lava falls, a lava waterfall, dragons against a huge moon
return function(kit: any, H: any): any
	local block, ball, disc, light, emitter, strip = H.block, H.ball, H.disc, H.light, H.emitter, H.strip
	local CF, rng = kit.CF, kit.Rng
	local basalt, basaltDark = rgb(58, 40, 46), rgb(34, 24, 30)
	local lava, lavaHot, lavaDeep = rgb(255, 96, 20), rgb(255, 176, 40), rgb(200, 50, 16)
	block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), rgb(44, 30, 36), M.Basalt)

	-- the volcano (the picture's left): a stepped cone, an erupting crater, three lava falls
	local vx, vz = 76, 190
	local y = 0
	local tiers = 14
	local baseR, topR = 0, 0
	for i = 1, tiers do
		local d = 140 - i * 8.6
		local h = 6.4 - i * 0.12
		disc(kit, CF.new(vx, y + h / 2, vz) * CF.Angles(0, i * 0.7, 0), h, d, if i % 2 == 0 then basalt else basaltDark, M.Basalt)
		if i == 1 then
			baseR = d / 2
		end
		topR = d / 2
		y += h
	end
	local top = y
	-- three lava falls pouring from the crater's rim down the front, fanning
	-- out: long ribbons lying on the steps' edges (a hot core on each)
	for f, k in { { -2, -14, 4.5 }, { 1, 4, 6 }, { 3, 20, 4 } } do
		local a = Vector3.new(vx + k[1], top, vz - topR + 1)
		local b = Vector3.new(vx + k[2], 0, vz - math.sqrt(baseR * baseR - k[2] * k[2]) - 1)
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		local cf = CF.lookAt(mid, b)
		block(kit, cf * CF.new(0, 2.4, 0), Vector3.new(k[3], 1.2, length + 2), lava, M.Neon)
		block(kit, cf * CF.new(0, 2.9, 0), Vector3.new(k[3] * 0.4, 1, length), lavaHot, M.Neon)
		if f == 2 then
			light(kit, mid + Vector3.new(0, 4, -12), lava, 60, 2)
		end
	end
	disc(kit, CF.new(vx, top + 0.2, vz), 0.6, 2 * topR - 2, lavaHot, M.Neon)
	-- the eruption: glowing lava blobs over the crater, smoke and sparks
	for i = 1, 14 do
		local h = rng:range(4, 30)
		local blob = ball(
			kit,
			Vector3.new(vx + rng:range(-8, 8) * (1 + h / 30), top + h, vz + rng:range(-4, 4)),
			rng:range(1.6, 4.2) * (1 - h / 60),
			if i % 3 == 0 then lavaHot else lava,
			M.Neon
		)
		blob.Transparency = h / 50
	end
	for i = 1, 3 do
		emitter(
			kit,
			Vector3.new(vx + (i - 2) * 6, top + 4, vz),
			10,
			rgb(70, 44, 50),
			"rbxasset://textures/particles/smoke_main.dds",
			"Smoke"
		)
	end
	emitter(kit, Vector3.new(vx, top + 2, vz - 10), 24, lavaHot, "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	light(kit, Vector3.new(vx, top + 10, vz - 30), lava, 70, 3)
	-- the lava pool at the volcano's foot
	disc(kit, CF.new(vx + 2, 0.06, vz - 70), 0.1, 46, lava, M.Neon)
	disc(kit, CF.new(vx + 2, 0.1, vz - 70), 0.1, 26, lavaHot, M.Neon)

	-- a second, smaller peak far back on the right
	local y2 = 0
	for i = 1, 7 do
		local d = 100 - i * 11
		local h = 7.5 - i * 0.4
		disc(kit, CF.new(-170, y2 + h / 2, 330), h, d, if i % 2 == 0 then basalt else basaltDark, M.Basalt)
		y2 += h
	end
	disc(kit, CF.new(-170, y2 + 0.2, 330), 0.5, 18, lava, M.Neon)

	-- the huge moon (the picture's right) with a halo, a big dragon flying across it
	local mx, my, mz = -84, 64, 320
	ball(kit, Vector3.new(mx, my, mz), 96, rgb(196, 108, 72), M.Neon)
	ball(kit, Vector3.new(mx, my, mz + 10), 128, rgb(150, 50, 44), M.Neon, 0.82)
	ball(kit, Vector3.new(mx + 18, my + 14, mz - 2), 22, rgb(170, 92, 64), M.Neon, 0.45) -- a crater
	ball(kit, Vector3.new(mx - 22, my - 18, mz - 2), 14, rgb(170, 92, 64), M.Neon, 0.5)
	local ink = rgb(18, 6, 12)
	dragon(kit, block, CF.new(mx + 8, my + 2, mz - 60) * CF.Angles(0, 0, 0.1), 1.25, ink)
	-- two more far off: one over the volcano's smoke, one low over the horizon
	dragon(kit, block, CF.new(46, 86, 250) * CF.Angles(0, PI, -0.15), 0.42, rgb(40, 12, 22))
	dragon(kit, block, CF.new(-20, 58, 300) * CF.Angles(0, 0, 0.2), 0.28, rgb(56, 18, 26))

	-- the lava river winding from the volcano's pool toward the stage
	local river = {
		Vector3.new(70, 0, 122),
		Vector3.new(48, 0, 108),
		Vector3.new(20, 0, 98),
		Vector3.new(-6, 0, 86),
		Vector3.new(-14, 0, 66),
		Vector3.new(2, 0, 52),
		Vector3.new(22, 0, 42),
	}
	for i = 1, #river - 1 do
		strip(kit, river[i], river[i + 1], 9 - i * 0.7, 0.05, lavaDeep, M.Neon)
		strip(kit, river[i], river[i + 1], 5.5 - i * 0.45, 0.08, lava, M.Neon)
		strip(kit, river[i], river[i + 1], 2.2 - i * 0.15, 0.11, lavaHot, M.Neon)
	end
	light(kit, Vector3.new(4, 5, 54), lava, 34, 2)
	-- glowing cracks in the ground around the stage
	for _ = 1, 22 do
		local a = Vector3.new(rng:range(-80, 80), 0, rng:range(-20, 40))
		if math.abs(a.X) > 44 or a.Z > 18 then
			local b = a + Vector3.new(rng:range(-7, 7), 0, rng:range(-7, 7))
			strip(kit, a, b, 0.4, 0.03, lava, M.Neon)
		end
	end
	-- jagged basalt spires in the middle distance
	for _, k in { { 60, 62, 30 }, { 48, 40, 16 }, { 88, 36, 20 }, { 34, 110, 24 }, { -58, 60, 12 }, { -96, 44, 10 } } do
		local h = k[3]
		block(
			kit,
			CF.new(k[1], h / 2 - 1, k[2]) * CF.Angles(rng:range(-0.12, 0.12), rng:range(0, PI), rng:range(-0.12, 0.12)),
			Vector3.new(h * 0.42, h, h * 0.36),
			basaltDark,
			M.Basalt
		)
		block(
			kit,
			CF.new(k[1] + 2, h * 0.7, k[2] - 1) * CF.Angles(0.2, rng:range(0, PI), 0.3),
			Vector3.new(h * 0.24, h * 0.5, h * 0.24),
			basalt,
			M.Basalt
		)
	end
	-- dark rocks framing the bottom corners, close to the camera
	for _, k in { { 33, -26, 9, 0.4 }, { 30, -22, 6, 1.2 }, { -36, -26, 9, 2.1 }, { -32, -21, 5, 0.7 } } do
		block(
			kit,
			CF.new(k[1], k[3] * 0.3, k[2]) * CF.Angles(0.3, k[4], 0.25),
			Vector3.new(k[3], k[3] * 0.9, k[3] * 0.8),
			rgb(26, 16, 22),
			M.Basalt
		)
	end
	-- embers in the air: glowing sparks near and far, and the renderer's ember clouds
	for i = 1, 46 do
		local spark = ball(
			kit,
			Vector3.new(rng:range(-44, 44), rng:range(2, 30), rng:range(-12, 40)),
			rng:range(0.14, 0.32),
			if i % 3 == 0 then lavaHot else lava,
			M.Neon
		)
		spark.Transparency = rng:range(0, 0.35)
	end
	for _, p in { Vector3.new(-26, 1, 16), Vector3.new(28, 1, 16), Vector3.new(0, 1, 34), Vector3.new(-46, 1, 6), Vector3.new(46, 1, 6) } do
		emitter(kit, p, 14, lavaHot, "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	end
	return {
		Preset = {
			Lighting = {
				Brightness = 2.4,
				Ambient = Color3.new(0.34, 0.2, 0.2),
				OutdoorAmbient = Color3.new(0.56, 0.36, 0.34),
				ExposureCompensation = 0.15,
				EnvironmentDiffuseScale = 0.3,
				EnvironmentSpecularScale = 0.4,
			},
			Atmosphere = {
				Density = 0.5,
				Offset = 0.2,
				Color = Color3.new(0.55, 0.2, 0.2),
				Decay = Color3.new(0.38, 0.12, 0.2),
				Glare = 0,
				Haze = 1.4,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.2, Saturation = 0.26, TintColor = Color3.new(1, 0.96, 0.95) },
			Bloom = { Intensity = 0.85, Size = 30, Threshold = 0.92 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(22, 6, 32),
				Mid = rgb(104, 18, 48),
				Horizon = rgb(255, 116, 44),
				HorizonAway = rgb(236, 84, 40),
				Sun = rgb(0, 0, 0),
				MidAngle = 13,
				CloudCover = 0.32,
			},
		},
		Stage = rgb(30, 22, 30),
		StageMaterial = M.Basalt,
		Rim = lava,
		Pedestal = rgb(24, 16, 24),
	}
end
