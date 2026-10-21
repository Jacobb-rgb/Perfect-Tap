--[[
	The FROST TITANS banner backdrop (tools/lune/lib/limited_golems_preview.luau
	loads it for scene "limited_FrostTitans"): returns the scene's Look.
	H = Preview.Helpers (block, ball, disc, light, emitter, strip, ...).

	A polar night: a wall of snowy mountains, giant northern-lights curtains
	(green, cyan, violet) over them, a huge pale moon with light shafts (the
	picture's right) over a cliff with a frozen waterfall, an ice palace with
	glowing spires (the picture's left), a dark sea with icebergs and the
	aurora's reflection, snowy pines, glowing ice crystal clusters round the
	stage, stars and falling snow sparkles.
]]

local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local rgb = Color3.fromRGB
local M = roblox.Enum.Material
local PI = math.pi

local SNOW = rgb(226, 238, 252)
local SNOW_SHADE = rgb(170, 196, 230)
local ICE = rgb(96, 160, 230)
local ICE_PALE = rgb(200, 236, 255)
local ICE_CYAN = rgb(70, 210, 255)
local GLOW_CYAN = rgb(110, 240, 255)
local AURORA_GREEN = rgb(40, 255, 150)
local AURORA_CYAN = rgb(30, 210, 255)
local AURORA_VIOLET = rgb(130, 90, 255)
local ROCK = rgb(52, 70, 112)
local ROCK_DARK = rgb(30, 42, 78)
local PINE = rgb(24, 58, 70)

-- a flat triangle (two wedges)
local function tri(kit: any, a: any, b: any, c: any, thick: number, color: any, material: any)
	kit.Geo.triangle(kit.Folder, a, b, c, thick, color, material)
end

--[[
	A low-poly mountain facing the camera: a left face, a front ridge face and
	a right face meeting at the apex, a snowy cap over the top third
	(the caps lie a little toward the camera).
]]
local function mountain(kit: any, x: number, z: number, w: number, h: number, lit: any, mid: any, shade: any, cap: boolean)
	local apex = Vector3.new(x, h, z)
	local l, r = Vector3.new(x + w, 0, z + w * 0.25), Vector3.new(x - w, 0, z + w * 0.25)
	local fl, fr = Vector3.new(x + w * 0.35, 0, z - w * 0.55), Vector3.new(x - w * 0.3, 0, z - w * 0.5)
	tri(kit, apex, l, fl, 2, lit, M.Glacier)
	tri(kit, apex, fl, fr, 2, mid, M.Glacier)
	tri(kit, apex, fr, r, 2, shade, M.Glacier)
	if cap then
		local toCam = Vector3.new(0, 0.6, -1.6)
		local k = 0.27
		local function on(p: any, t: number): any
			return apex + (p - apex) * t + toCam
		end
		tri(kit, apex + toCam, on(l, k), on(fl, k * 1.2), 1, SNOW, M.Snow)
		tri(kit, apex + toCam, on(fl, k * 1.2), on(fr, k * 0.9), 1, SNOW:Lerp(SNOW_SHADE, 0.3), M.Snow)
		tri(kit, apex + toCam, on(fr, k * 0.9), on(r, k * 0.8), 1, SNOW_SHADE, M.Snow)
	end
end

-- a cube balanced on its corner, half buried: an iceberg / a snow drift
local function peak(kit: any, block: any, pos: any, size: number, color: any, material: any, spin: number)
	local CF = kit.CF
	local cf = CF.new(pos) * CF.Angles(0, spin, 0) * CF.Angles(math.atan(1 / math.sqrt(2)), 0, PI / 4)
	return block(kit, cf, Vector3.new(size, size, size), color, material)
end

-- a pointed spire: two crossed flat triangles (4 wedges) from a base of width w
local function spire(kit: any, x: number, y: number, z: number, w: number, h: number, color: any, material: any)
	local tip = Vector3.new(x, y + h, z)
	tri(kit, Vector3.new(x - w / 2, y, z), Vector3.new(x + w / 2, y, z), tip, w * 0.3, color, material)
	tri(kit, Vector3.new(x, y, z - w / 2), Vector3.new(x, y, z + w / 2), tip, w * 0.3, color, material)
end

-- an ice palace tower: a shaft, a glowing ring, a wider gallery, a spire, windows
local function tower(kit: any, H: any, x: number, z: number, d: number, h: number, spireH: number)
	local CF = kit.CF
	H.disc(kit, CF.new(x, h / 2, z), h, d, ICE, M.Glass)
	H.disc(kit, CF.new(x, h + 0.6, z), 1.2, d * 1.3, ICE_PALE, M.Ice)
	H.disc(kit, CF.new(x, h - 0.4, z), 0.5, d * 1.18, GLOW_CYAN, M.Neon)
	spire(kit, x, h + 1.2, z, d * 1.05, spireH, ICE_PALE, M.Glass)
	H.block(kit, CF.new(x, h + 1.2 + spireH * 0.32, z - d * 0.2), Vector3.new(d * 0.12, spireH * 0.4, d * 0.1), GLOW_CYAN, M.Neon)
	for i = 1, 2 do
		H.block(kit, CF.new(x, h * (0.3 + i * 0.22), z - d / 2), Vector3.new(d * 0.22, d * 0.36, 0.3), rgb(200, 255, 255), M.Neon)
	end
end

-- FrostTitans: a polar night with the northern lights
return function(kit: any, H: any): any
	local block, ball, disc, light, emitter, strip = H.block, H.ball, H.disc, H.light, H.emitter, H.strip
	local CF, rng = kit.CF, kit.Rng

	-- the snowfield (front) and the dark sea (behind the stage)
	block(kit, CF.new(0, -0.5, 20), Vector3.new(700, 1, 110), rgb(150, 182, 226), M.Snow)
	block(kit, CF.new(0, -0.6, 260), Vector3.new(900, 1, 400), rgb(10, 22, 52), M.SmoothPlastic)
	-- the shore: snow banks along the water
	for i = 1, 9 do
		local x = (i - 5) * 46 + rng:range(-8, 8)
		disc(kit, CF.new(x, -0.2, 76 + rng:range(-4, 6)) * CF.Angles(0, 0, 0), 1.6, rng:range(40, 60), SNOW_SHADE, M.Snow)
	end
	-- the aurora's reflection in the water: soft glowing streaks
	for i, k in { { 30, AURORA_GREEN }, { 0, AURORA_CYAN }, { -36, AURORA_VIOLET }, { 60, AURORA_CYAN }, { -70, AURORA_GREEN } } do
		local s = strip(kit, Vector3.new(k[1] + 4, 0, 110), Vector3.new(k[1] * 1.3, 0, 330), 10 - i, -0.05, k[2], M.Neon, 0.72)
		s.CastShadow = false
	end

	-- the wall of snowy mountains at the back (staggered rows)
	for _, k in
		{
			{ -230, 470, 120, 150 },
			{ -110, 500, 130, 175 },
			{ 20, 520, 120, 150 },
			{ 140, 500, 130, 182 },
			{ 260, 470, 120, 140 },
			{ -170, 400, 80, 96 },
			{ 200, 390, 84, 92 },
		}
	do
		local tone = rng:range(0, 1)
		mountain(
			kit,
			k[1],
			k[2],
			k[3],
			k[4],
			rgb(62, 92, 156):Lerp(rgb(74, 106, 170), tone),
			rgb(38, 58, 112):Lerp(rgb(46, 68, 124), tone),
			rgb(20, 30, 70):Lerp(rgb(26, 38, 80), tone),
			true
		)
	end

	-- the northern lights: three huge waving curtains, each a row of tall
	-- translucent glowing panels, brighter low and fading up
	local curtains = {
		{ z = 560, base = 90, h = 150, color = AURORA_GREEN, top = rgb(120, 255, 200), x0 = -340, x1 = 120, phase = 0 },
		{ z = 600, base = 120, h = 140, color = AURORA_CYAN, top = rgb(140, 200, 255), x0 = -200, x1 = 300, phase = 1.7 },
		{ z = 640, base = 150, h = 130, color = AURORA_VIOLET, top = rgb(255, 120, 220), x0 = -60, x1 = 380, phase = 3.1 },
	}
	for _, c in curtains do
		local n = 18
		for i = 1, n do
			local t = (i - 1) / (n - 1)
			local x = c.x0 + (c.x1 - c.x0) * t
			local z = c.z + math.sin(t * 9 + c.phase) * 40
			local base = c.base + math.sin(t * 5 + c.phase) * 26
			local h = c.h * (0.7 + 0.3 * math.sin(t * 7 + c.phase * 2))
			local yaw = math.cos(t * 9 + c.phase) * 0.6
			local w = (c.x1 - c.x0) / n * 1.15
			local soft = block(kit, CF.new(x, base + h * 0.45, z) * CF.Angles(0, yaw, 0), Vector3.new(w, h * 0.9, 1), c.color, M.Neon)
			soft.Transparency = 0.72 + 0.12 * math.abs(math.sin(i * 1.7))
			local rh = h * (0.5 + 0.5 * math.abs(math.sin(i * 2.9 + c.phase)))
			local ray = block(
				kit,
				CF.new(x + w * 0.2, base + rh * 0.5, z - 1.5) * CF.Angles(0, yaw, 0),
				Vector3.new(w * 0.22, rh, 0.6),
				c.color:Lerp(c.top, 0.3),
				M.Neon
			)
			ray.Transparency = 0.45 + 0.2 * math.abs(math.sin(i * 2.3))
			-- the bright hem along the curtain's bottom
			if i % 2 == 0 then
				local hem = block(
					kit,
					CF.new(x, base + 3, z - 2) * CF.Angles(0, yaw, 0),
					Vector3.new(w * 1.1, 5, 0.6),
					c.color:Lerp(rgb(255, 255, 255), 0.35),
					M.Neon
				)
				hem.Transparency = 0.35
			end
		end
	end

	-- stars
	for i = 1, 54 do
		local s = rng:range(0.8, 2.2)
		local star = block(
			kit,
			CF.new(rng:range(-420, 420), rng:range(70, 380), 700 + rng:range(-20, 20)) * CF.Angles(0, 0, PI / 4),
			Vector3.new(s, s, 0.3),
			if i % 4 == 0 then rgb(200, 230, 255) else rgb(255, 255, 255),
			M.Neon
		)
		star.Transparency = rng:range(0, 0.5)
	end

	-- the huge moon (the picture's right) with a halo and light shafts
	local moon = Vector3.new(-170, 150, 520)
	ball(kit, moon, 74, rgb(200, 226, 255), M.Neon)
	ball(kit, moon + Vector3.new(0, 0, 12), 104, rgb(90, 150, 240), M.Neon, 0.88)
	ball(kit, moon + Vector3.new(16, 14, -4), 20, rgb(190, 214, 240), M.Neon, 0.4)
	ball(kit, moon + Vector3.new(-20, -16, -4), 14, rgb(190, 214, 240), M.Neon, 0.45)
	ball(kit, moon + Vector3.new(24, -22, -4), 9, rgb(190, 214, 240), M.Neon, 0.5)

	-- the cliff with the frozen waterfall (the picture's right)
	local cx, cz = -120, 210
	for i, k in { { 0, 0, 50 }, { -30, 14, 58 }, { 26, -8, 36 }, { -60, 26, 46 }, { 44, 6, 26 } } do
		local size = k[3]
		local spin = rng:range(0, 1)
		local base = Vector3.new(cx + k[1], -size * 0.2, cz + k[2])
		peak(kit, block, base, size, if i % 2 == 0 then ROCK_DARK else ROCK, M.Slate, spin)
		-- a snow cap over its top corner
		peak(kit, block, base + Vector3.new(0, size * 0.62, -0.6), size * 0.3, SNOW, M.Snow, spin)
	end
	-- the frozen fall: ice sheets down the cliff face, a glowing core, a frozen pool, icicles
	local fx, fz = cx - 4, cz - 16
	block(kit, CF.new(fx, 26, fz - 0.5) * CF.Angles(0.06, 0, 0), Vector3.new(16, 54, 2), ICE_PALE, M.Ice)
	block(kit, CF.new(fx + 1, 26, fz - 1.8) * CF.Angles(0.06, 0, 0), Vector3.new(9, 54, 1), ICE, M.Glass)
	block(kit, CF.new(fx - 2, 26, fz - 2.5) * CF.Angles(0.06, 0, 0), Vector3.new(2, 52, 0.6), GLOW_CYAN, M.Neon)
	block(kit, CF.new(fx + 4, 24, fz - 2.5) * CF.Angles(0.06, 0, 0), Vector3.new(1.2, 46, 0.6), GLOW_CYAN, M.Neon)
	disc(kit, CF.new(fx, 0.2, fz - 12), 0.8, 34, ICE, M.Ice)
	disc(kit, CF.new(fx, 0.4, fz - 12), 0.4, 18, GLOW_CYAN, M.Neon, 0.4)
	for i = 1, 4 do
		local x, z, h = fx - 18 + i * 7, fz - 6 - (i % 2) * 6, rng:range(6, 12)
		tri(kit, Vector3.new(x - 1.8, 0.2, z), Vector3.new(x + 1.8, 0.2, z), Vector3.new(x, h, z), 1.4, ICE_PALE, M.Ice)
	end
	light(kit, Vector3.new(fx, 14, fz - 18), GLOW_CYAN, 60, 2)

	-- the ice palace (the picture's left): a keep with a tall spire, towers,
	-- walls with glowing gates, a glow behind it
	local px, pz = 118, 250
	tower(kit, H, px, pz, 18, 46, 46)
	tower(kit, H, px + 24, pz + 10, 12, 34, 30)
	tower(kit, H, px - 22, pz - 6, 12, 30, 28)
	tower(kit, H, px + 44, pz + 22, 9, 22, 22)
	tower(kit, H, px - 40, pz - 14, 8, 18, 18)
	-- the walls between the towers, crenels on top
	for _, k in { { px + 12, pz + 5, 26 }, { px - 12, pz - 3, 24 }, { px + 34, pz + 16, 22 }, { px - 31, pz - 10, 20 } } do
		block(kit, CF.new(k[1], 7, k[2]), Vector3.new(k[3], 14, 4), ICE_PALE, M.Ice)
		block(kit, CF.new(k[1], 14.4, k[2] - 0.4), Vector3.new(k[3] + 0.4, 1, 4.2), SNOW, M.Snow)
		block(kit, CF.new(k[1], 5, k[2] - 2.1), Vector3.new(k[3] * 0.25, 7, 0.3), rgb(200, 255, 255), M.Neon)
	end
	-- the great gate in the keep with an arch of light
	block(kit, CF.new(px, 8, pz - 9.4), Vector3.new(7, 14, 0.4), GLOW_CYAN, M.Neon, 0.3)
	disc(kit, CF.new(px, 15, pz - 9.6) * CF.Angles(PI / 2, 0, 0) * CF.Angles(0, 0, 0), 0.4, 9, GLOW_CYAN, M.Neon)
	-- a cold glow behind the palace and on its steps
	light(kit, Vector3.new(px, 20, pz - 30), GLOW_CYAN, 80, 2.4)
	-- the ice bridge / stair down to the shore
	for i = 1, 5 do
		block(kit, CF.new(px - 2, 0.2 + (5 - i) * 0.6, pz - 12 - i * 5), Vector3.new(14 - i * 0.4, 0.6 + (5 - i) * 1.2, 5), ICE_PALE, M.Ice)
	end

	-- icebergs in the dark sea
	for _, k in
		{
			{ 30, 160, 18, 0.3 },
			{ 44, 150, 10, 1.2 },
			{ -20, 200, 22, 0.8 },
			{ -40, 120, 12, 2.0 },
			{ 0, 260, 16, 0.4 },
			{ -150, 240, 26, 1.0 },
			{ 170, 260, 24, 0.6 },
			{ 60, 110, 8, 1.6 },
		}
	do
		peak(kit, block, Vector3.new(k[1], -k[3] * 0.18, k[2]), k[3], ICE_PALE, M.Ice, k[4])
		peak(kit, block, Vector3.new(k[1] + k[3] * 0.4, -k[3] * 0.3, k[2] - 2), k[3] * 0.7, ICE, M.Glass, k[4] + 0.7)
		local rim = disc(kit, CF.new(k[1], 0.0, k[2]), 0.12, k[3] * 1.5, GLOW_CYAN, M.Neon, 0.6)
		rim.CastShadow = false
	end

	-- snowy pines on both sides of the stage
	for _, k in
		{
			{ 46, 48, 16 },
			{ 58, 64, 20 },
			{ 40, 72, 13 },
			{ 70, 84, 18 },
			{ -44, 50, 15 },
			{ -58, 66, 21 },
			{ -40, 76, 12 },
			{ -72, 88, 17 },
		}
	do
		local x, z, h = k[1], k[2], k[3]
		disc(kit, CF.new(x, h * 0.12, z), h * 0.24, h * 0.1, rgb(70, 50, 50))
		for j = 1, 3 do
			local y = h * (0.2 + (j - 1) * 0.24)
			local d = h * (0.62 - (j - 1) * 0.16)
			local cone = h * 0.3
			tri(kit, Vector3.new(x - d / 2, y, z), Vector3.new(x + d / 2, y, z), Vector3.new(x, y + cone, z), d * 0.4, PINE, M.Grass)
			-- snow on each tier
			disc(kit, CF.new(x, y + cone * 0.35, z), cone * 0.18, d * 0.62, SNOW, M.Snow)
		end
	end

	-- glowing ice crystal clusters round the stage, snow drifts at their feet
	local function crystalSpike(pos: any, h: number, w: number, tilt: any, color: any, material: any)
		local cf = CF.new(pos) * tilt
		block(kit, cf * CF.new(0, h / 2, 0) * CF.Angles(0, PI / 4, 0), Vector3.new(w, h, w), color, material)
		block(
			kit,
			cf * CF.new(0, h, 0) * CF.Angles(0, PI / 4, 0) * CF.Angles(math.atan(1 / math.sqrt(2)), 0, PI / 4),
			Vector3.new(w * 0.71, w * 0.71, w * 0.71),
			color,
			material
		)
	end
	for c, k in { { -36, 22 }, { 36, 24 }, { -30, 40 }, { 32, 42 }, { -52, 58 }, { 54, 60 } } do
		local glow = if c % 2 == 0 then AURORA_CYAN else rgb(150, 110, 255)
		for j = 1, 3 do
			local h = rng:range(4, 8) * (if j == 1 then 1.5 else 1)
			local tilt = CF.Angles(rng:range(-0.35, 0.35), rng:range(0, PI), rng:range(-0.35, 0.35))
			local pos = Vector3.new(k[1] + rng:range(-3, 3), -0.4, k[2] + rng:range(-2, 3))
			crystalSpike(pos, h, h * 0.26, tilt, if j == 2 then glow else ICE_PALE, if j == 2 then M.Neon else M.Ice)
		end
		peak(kit, block, Vector3.new(k[1] + 2, -2.6, k[2] + 2), rng:range(6, 9), SNOW, M.Snow, rng:range(0, 1))
	end

	-- falling snow: white sparkles in the air near and far, the renderer's sparkle clouds
	for i = 1, 36 do
		local flake = ball(
			kit,
			Vector3.new(rng:range(-48, 48), rng:range(2, 32), rng:range(-14, 50)),
			rng:range(0.18, 0.42),
			if i % 5 == 0 then rgb(170, 240, 255) else rgb(255, 255, 255),
			M.Neon
		)
		flake.Transparency = rng:range(0, 0.4)
	end
	for _, p in { Vector3.new(-26, 4, 16), Vector3.new(28, 4, 16), Vector3.new(0, 8, 30), Vector3.new(-46, 2, 6), Vector3.new(46, 2, 6) } do
		emitter(kit, p, 16, rgb(220, 240, 255), "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	end

	return {
		Preset = {
			Lighting = {
				Brightness = 1.1,
				Ambient = Color3.new(0.1, 0.13, 0.24),
				OutdoorAmbient = Color3.new(0.18, 0.24, 0.4),
				ExposureCompensation = -0.1,
				EnvironmentDiffuseScale = 0.2,
				EnvironmentSpecularScale = 0.8,
			},
			Atmosphere = {
				Density = 0.22,
				Offset = 0.1,
				Color = Color3.new(0.12, 0.2, 0.36),
				Decay = Color3.new(0.08, 0.14, 0.32),
				Glare = 0,
				Haze = 0.5,
			},
			ColorCorrection = { Brightness = -0.02, Contrast = 0.24, Saturation = 0.3, TintColor = Color3.new(0.96, 0.99, 1) },
			Bloom = { Intensity = 0.55, Size = 22, Threshold = 0.95 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(4, 8, 30),
				Mid = rgb(12, 34, 84),
				Horizon = rgb(40, 150, 160),
				HorizonAway = rgb(30, 110, 140),
				Sun = rgb(0, 0, 0),
				MidAngle = 14,
				CloudCover = 0,
			},
		},
		Stage = rgb(52, 86, 150),
		StageMaterial = M.Ice,
		Rim = GLOW_CYAN,
		Pedestal = rgb(40, 64, 128),
	}
end
