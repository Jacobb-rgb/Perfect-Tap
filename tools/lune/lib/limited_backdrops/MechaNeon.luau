--[[
	The MECHA NEON banner backdrop (tools/lune/lib/limited_golems_preview.luau
	loads it for scene "limited_MechaNeon"): returns the scene's Look.
	H = Preview.Helpers (block, ball, disc, light, emitter, strip, ...).

	A synthwave night city: a huge striped retro sun setting between neon
	mountains, a giant mech silhouette with glowing eyes behind the city (the
	picture's left), a neon skyline with window bands, edge lights and
	billboards, a hologram robot head over a tower (the picture's right),
	searchlight beams, flying cars and drones with light trails, a neon grid
	floor running to the horizon, neon pylons with chevron rings beside the
	stage and sparks in the air.
	(The camera looks along +Z from (-1.5, 8.8, -46): world -X is the
	picture's right; the title covers the top centre.)
]]

local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local rgb = Color3.fromRGB
local M = roblox.Enum.Material
local PI = math.pi

local PINK = rgb(255, 46, 190)
local CYAN = rgb(0, 232, 255)
local VIOLET = rgb(150, 80, 255)
local YELLOW = rgb(255, 224, 70)
local ORANGE = rgb(255, 120, 60)
local RED = rgb(255, 40, 70)
local INK = rgb(14, 8, 30)
local WIN_CYAN = rgb(0, 150, 200)
local WIN_PINK = rgb(190, 36, 150)

-- a disc facing the camera (its axis along Z)
local function face(kit: any, H: any, pos: any, d: number, color: any, material: any?, transparency: number?): any
	return H.disc(kit, kit.CF.new(pos) * kit.CF.Angles(PI / 2, 0, 0), 0.6, d, color, material, transparency)
end

-- a bar between two points (any direction), w x w thick
local function bar(kit: any, H: any, a: any, b: any, w: number, color: any, material: any?, transparency: number?): any
	local cf = kit.CF.lookAt((a + b) / 2, b)
	return H.block(kit, cf, Vector3.new(w, w, (b - a).Magnitude), color, material, transparency)
end

-- the big retro sun: nested discs (orange rim to a yellow top) with dark stripes cut across its lower half
local function sun(kit: any, H: any, x: number, y: number, z: number, d: number)
	-- the glow around it
	face(kit, H, Vector3.new(x, y, z + 6), d * 1.5, rgb(255, 60, 170), M.Neon, 0.8)
	face(kit, H, Vector3.new(x, y, z + 3), d * 1.2, rgb(255, 70, 160), M.Neon, 0.6)
	local rings = { { 1, rgb(232, 40, 140) }, { 0.86, rgb(240, 84, 110) }, { 0.7, rgb(244, 136, 80) }, { 0.52, rgb(246, 190, 84) } }
	for i, k in rings do
		local dd = d * k[1]
		face(kit, H, Vector3.new(x, y + (d - dd) / 2, z - i * 0.7), dd, k[2], M.Neon)
	end
	-- the stripes: thicker toward the bottom, the colour of the sky behind
	for i = 1, 7 do
		local sy = y + d * 0.16 - i * d * 0.075
		local h = d * (0.008 + i * 0.0065)
		local r = d / 2
		local dy = math.abs(sy - y)
		local w = 2 * math.sqrt(math.max(r * r - dy * dy, 0)) + 4
		H.block(kit, kit.CF.new(x, sy, z - 6), Vector3.new(w, h, 0.4), rgb(54, 14, 70), M.SmoothPlastic)
	end
end

-- a dark mountain peak (a block on its edge) with neon ridge lines
local function peak(kit: any, H: any, x: number, z: number, w: number, h: number, edge: any)
	local CF = kit.CF
	local s = math.sqrt((w / 2) ^ 2 + h ^ 2)
	local tilt = math.atan2(w / 2, h)
	-- two leaning slabs meeting at the top
	for _, side in { -1, 1 } do
		local cf = CF.new(x + side * w / 4, h / 2, z) * CF.Angles(0, 0, side * tilt)
		H.block(kit, cf, Vector3.new(w / 2 + 2, s, 6), rgb(30, 12, 54), M.SmoothPlastic)
		bar(kit, H, Vector3.new(x, h, z - 3.2), Vector3.new(x + side * w / 2, 0, z - 3.2), 0.9, edge, M.Neon)
	end
	-- a ridge line down the middle
	bar(kit, H, Vector3.new(x, h, z - 3.4), Vector3.new(x + w * 0.12, 0, z - 3.4), 0.6, edge, M.Neon, 0.3)
end

-- a skyscraper: a dark tower with neon window bands, edge lights and a roof beacon
local function tower(kit: any, H: any, x: number, z: number, w: number, h: number, d: number, tone: any, fade: number)
	local CF, rng = kit.CF, kit.Rng
	H.block(kit, CF.new(x, h / 2, z), Vector3.new(w, h, d), tone, M.SmoothPlastic)
	local front = z - d / 2 - 0.15
	local bands = math.floor(h / 8)
	for b = 1, bands do
		if rng:range(0, 1) < 0.4 then
			H.block(
				kit,
				CF.new(x + rng:range(-w * 0.1, w * 0.1), b * 8 - 3, front),
				Vector3.new(w * rng:range(0.4, 0.8), 0.8, 0.2),
				if rng:range(0, 1) < 0.5 then WIN_CYAN else WIN_PINK,
				M.Neon,
				0.3 + fade
			)
		end
	end
	if rng:range(0, 1) < 0.45 then
		for _, side in { -1, 1 } do
			H.block(kit, CF.new(x + side * (w / 2 - 0.3), h / 2, front), Vector3.new(0.5, h, 0.2), VIOLET, M.Neon, 0.25 + fade)
		end
	end
	-- a stepped top or an antenna spire
	local roll = rng:range(0, 1)
	if roll < 0.35 then
		H.block(kit, CF.new(x, h + 3, z), Vector3.new(w * 0.6, 6, d * 0.6), tone, M.SmoothPlastic)
		H.block(kit, CF.new(x, h + 6.2, front + d * 0.2), Vector3.new(w * 0.6, 0.6, 0.2), PINK, M.Neon, fade)
	elseif roll < 0.7 then
		H.block(kit, CF.new(x, h + 6, z), Vector3.new(0.6, 12, 0.6), rgb(60, 50, 90), M.Metal)
		H.ball(kit, Vector3.new(x, h + 12.4, z), 1.8, RED, M.Neon)
	end
end

-- a billboard: a neon frame with an icon inside (a robot face, a bolt or an ore gem)
local function billboard(kit: any, H: any, x: number, y: number, z: number, w: number, h: number, frame: any, icon: string)
	local CF = kit.CF
	H.block(kit, CF.new(x, y, z + 0.4), Vector3.new(w, h, 0.4), rgb(20, 10, 40), M.SmoothPlastic)
	for _, s in { -1, 1 } do
		H.block(kit, CF.new(x, y + s * h / 2, z), Vector3.new(w + 0.8, 0.8, 0.4), frame, M.Neon)
		H.block(kit, CF.new(x + s * w / 2, y, z), Vector3.new(0.8, h, 0.4), frame, M.Neon)
	end
	local other = if frame == PINK then CYAN else PINK
	if icon == "face" then
		for _, s in { -1, 1 } do
			H.block(kit, CF.new(x + s * w * 0.2, y + h * 0.12, z - 0.1), Vector3.new(w * 0.16, h * 0.22, 0.3), other, M.Neon)
		end
		H.block(kit, CF.new(x, y - h * 0.22, z - 0.1), Vector3.new(w * 0.4, h * 0.08, 0.3), YELLOW, M.Neon)
	elseif icon == "bolt" then
		local k = h * 0.36
		bar(kit, H, Vector3.new(x - k * 0.3, y + k, z - 0.1), Vector3.new(x + k * 0.25, y, z - 0.1), k * 0.32, YELLOW, M.Neon)
		bar(kit, H, Vector3.new(x - k * 0.25, y, z - 0.1), Vector3.new(x + k * 0.3, y - k, z - 0.1), k * 0.32, YELLOW, M.Neon)
	else
		H.block(kit, CF.new(x, y, z - 0.1) * CF.Angles(0, 0, PI / 4), Vector3.new(h * 0.42, h * 0.42, 0.3), other, M.Neon)
		H.block(kit, CF.new(x, y, z - 0.3) * CF.Angles(0, 0, PI / 4), Vector3.new(h * 0.2, h * 0.2, 0.3), rgb(255, 255, 255), M.Neon)
	end
end

-- the giant mech silhouette behind the city (feet at y 0, `k` its size)
local function giantMech(kit: any, H: any, x: number, z: number, k: number)
	local CF = kit.CF
	local ink = rgb(36, 18, 66)
	local function piece(px: number, py: number, sx: number, sy: number, angle: number?)
		H.block(kit, CF.new(x + px * k, py * k, z) * CF.Angles(0, 0, angle or 0), Vector3.new(sx * k, sy * k, 4), ink, M.SmoothPlastic)
	end
	piece(-5, 14, 6, 28) -- legs
	piece(5, 14, 6, 28)
	piece(0, 31, 13, 8) -- hips
	piece(0, 44, 20, 20) -- the chest
	piece(0, 57, 30, 6) -- the shoulders' span
	piece(-17, 58, 9, 9, 0.2) -- shoulder pods
	piece(17, 58, 9, 9, -0.2)
	piece(-18, 42, 5, 22, -0.08) -- arms
	piece(18, 42, 5, 22, 0.08)
	piece(-19, 28, 7, 7) -- fists
	piece(19, 28, 7, 7)
	piece(0, 64, 9, 8) -- the head
	piece(-3, 71, 1.2, 8, 0.35) -- V-fins
	piece(3, 71, 1.2, 8, -0.35)
	-- its glowing eyes, chest core and shoulder lights
	local front = z - 2.3
	H.block(kit, CF.new(x, 64.4 * k, front), Vector3.new(7 * k, 1.4 * k, 0.4), CYAN, M.Neon)
	face(kit, H, Vector3.new(x, 46 * k, front), 6 * k, PINK, M.Neon)
	face(kit, H, Vector3.new(x, 46 * k, front - 0.4), 3 * k, rgb(255, 230, 255), M.Neon)
	for _, s in { -1, 1 } do
		H.ball(kit, Vector3.new(x + s * 17 * k, 61 * k, front), 1.6 * k, RED, M.Neon)
		H.block(kit, CF.new(x + s * 5 * k, 20 * k, front), Vector3.new(4.2 * k, 0.6 * k, 0.4), VIOLET, M.Neon)
		-- neon rim lines: the legs' outer edges, the arms, the chest's sides, the shoulder pods
		H.block(kit, CF.new(x + s * 7.8 * k, 14 * k, front), Vector3.new(0.4 * k, 28 * k, 0.4), PINK, M.Neon, 0.2)
		H.block(
			kit,
			CF.new(x + s * 20.3 * k, 42 * k, front) * CF.Angles(0, 0, s * 0.08),
			Vector3.new(0.4 * k, 22 * k, 0.4),
			PINK,
			M.Neon,
			0.2
		)
		H.block(kit, CF.new(x + s * 9.8 * k, 44 * k, front), Vector3.new(0.4 * k, 20 * k, 0.4), CYAN, M.Neon, 0.3)
		H.block(
			kit,
			CF.new(x + s * 17 * k, 62.6 * k, front) * CF.Angles(0, 0, -s * 0.2),
			Vector3.new(9 * k, 0.4 * k, 0.4),
			CYAN,
			M.Neon,
			0.2
		)
		H.block(kit, CF.new(x + s * 19 * k, 28 * k, front), Vector3.new(7 * k, 0.5 * k, 0.4), YELLOW, M.Neon, 0.2)
	end
	-- the chest's top edge and the head's fins
	H.block(kit, CF.new(x, 54 * k, front), Vector3.new(20 * k, 0.4 * k, 0.4), PINK, M.Neon, 0.2)
	H.block(kit, CF.new(x, 68 * k, front), Vector3.new(9 * k, 0.4 * k, 0.4), PINK, M.Neon, 0.2)
end

-- a flying car: a wedge body, a cyan canopy, red tail lights and a long light trail
local function flyingCar(kit: any, H: any, pos: any, dir: number, trail: any, size: number)
	local CF = kit.CF
	local cf = CF.new(pos) * CF.Angles(0, if dir > 0 then 0 else PI, 0)
	H.block(kit, cf, Vector3.new(4 * size, 0.9 * size, 1.8 * size), rgb(40, 36, 70), M.Metal)
	H.block(kit, cf * CF.new(0.5 * size, 0.6 * size, 0), Vector3.new(1.8 * size, 0.5 * size, 1.4 * size), CYAN, M.Neon, 0.2)
	H.block(kit, cf * CF.new(-2.05 * size, 0, 0), Vector3.new(0.2, 0.4 * size, 1.6 * size), RED, M.Neon)
	H.block(kit, cf * CF.new(0, -0.5 * size, 0), Vector3.new(3.6 * size, 0.16 * size, 1.4 * size), PINK, M.Neon)
	-- the trail streaming behind
	H.block(kit, cf * CF.new(-2.2 * size - 7 * size, 0, 0), Vector3.new(14 * size, 0.18 * size, 0.18 * size), trail, M.Neon, 0.35)
end

-- Mecha Neon: the synthwave city
return function(kit: any, H: any): any
	local block, ball, disc, light, emitter, strip = H.block, H.ball, H.disc, H.light, H.emitter, H.strip
	local CF, rng = kit.CF, kit.Rng
	local floor = block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), rgb(18, 12, 38), M.SmoothPlastic)
	floor.Reflectance = 0.3

	-- the neon grid running to the horizon
	for x = -156, 156, 12 do
		local far = Vector3.new(x * 2.4, 0, 260)
		strip(kit, Vector3.new(x, 0, 12), far, if x % 36 == 0 then 0.5 else 0.32, 0.03, if x % 36 == 0 then PINK else VIOLET, M.Neon, 0.25)
	end
	local z = 14
	local step = 4
	while z < 260 do
		strip(kit, Vector3.new(-420, 0, z), Vector3.new(420, 0, z), 0.3 + z * 0.002, 0.04, CYAN, M.Neon, 0.5)
		z += step
		step *= 1.22
	end

	-- the sun, setting between the mountains
	sun(kit, H, -1.5, 62, 400, 190)
	-- neon mountains on both sides of the sun
	for _, k in
		{
			{ 150, 330, 170, 70 },
			{ 230, 360, 160, 96 },
			{ 90, 300, 90, 40 },
			{ -150, 330, 170, 66 },
			{ -236, 360, 170, 90 },
			{ -96, 300, 90, 38 },
		}
	do
		peak(kit, H, k[1], k[2], k[3], k[4], if k[1] > 0 then PINK else CYAN)
	end

	-- stars in the upper sky
	for i = 1, 60 do
		local s = rng:range(0.6, 1.6)
		local x = rng:range(-300, 300)
		local y = rng:range(70, 170)
		local star = block(
			kit,
			CF.new(x, y, 420) * CF.Angles(0, 0, PI / 4),
			Vector3.new(s, s, 0.2),
			if i % 4 == 0 then CYAN else rgb(255, 230, 255),
			M.Neon
		)
		star.Transparency = rng:range(0, 0.5)
	end

	-- the giant mech behind the city (the picture's left), lit by searchlights
	giantMech(kit, H, 104, 196, 1.15)

	-- the skyline: a far row, a near row; open in the middle so the sun shows
	for row, r in { { 220, 40, 110, rgb(40, 24, 78), 0.35 }, { 150, 26, 76, rgb(26, 18, 56), 0 } } do
		local x = -250
		while x < 250 do
			local w = rng:range(12, 24)
			local cx = x + w / 2
			local off = math.abs(cx + 1.5)
			local middle = off < (if row == 1 then 34 else 44)
			local mech = cx > 70 and cx < 140 -- (in front of the giant mech: low)
			if not middle then
				-- (lower toward the middle gap, framing the sun)
				local frame = math.clamp((off - 30) / 80, 0.45, 1)
				local h = rng:range(r[2], r[3]) * (if mech then 0.3 else frame)
				tower(kit, H, cx, r[1] + rng:range(-8, 8), w, h, 14, r[4], r[5])
			end
			x += w + rng:range(2, 6)
		end
	end

	-- the hero tower on the picture's right: a billboard, a vertical sign, a hologram on its roof
	do
		local x, tz, w, h = -84, 118, 22, 34
		block(kit, CF.new(x, h / 2, tz), Vector3.new(w, h, 16), rgb(22, 14, 48), M.SmoothPlastic)
		for b = 1, 2 do
			block(kit, CF.new(x, b * 8 - 2, tz - 8.15), Vector3.new(w * 0.8, 0.7, 0.2), WIN_CYAN, M.Neon, 0.3)
		end
		for _, s in { -1, 1 } do
			block(kit, CF.new(x + s * (w / 2 - 0.3), h / 2, tz - 8.15), Vector3.new(0.6, h, 0.2), VIOLET, M.Neon)
		end
		block(kit, CF.new(x, h + 0.3, tz - 8.15), Vector3.new(w, 0.6, 0.2), PINK, M.Neon)
		billboard(kit, H, x, 28, tz - 9.5, 18, 11, CYAN, "face")
		-- the vertical sign blade on the inner edge
		local sx = x + w / 2 + 2
		block(kit, CF.new(sx, 24, tz - 6), Vector3.new(3.4, 26, 1), rgb(24, 12, 44), M.SmoothPlastic)
		for i = 1, 5 do
			block(kit, CF.new(sx, 13 + i * 4.2, tz - 6.6), Vector3.new(2.4, 2.4, 0.3), if i % 2 == 0 then YELLOW else PINK, M.Neon)
		end
		-- the hologram: a projector, a beam cone and a see-through robot head
		local hy = h + 12
		disc(kit, CF.new(x, h + 1, tz), 1.2, 9, rgb(60, 60, 90), M.Metal)
		disc(kit, CF.new(x, h + 1.7, tz), 0.3, 7, CYAN, M.Neon)
		block(kit, CF.new(x, h + 5, tz), Vector3.new(6, 6, 6), CYAN, M.Neon, 0.86)
		block(kit, CF.new(x, hy, tz), Vector3.new(19, 15, 15), CYAN, M.Neon, 0.8)
		block(kit, CF.new(x, hy, tz - 7.6), Vector3.new(16, 11, 0.3), rgb(10, 40, 70), M.SmoothPlastic, 0.4)
		for _, s in { -1, 1 } do
			block(kit, CF.new(x + s * 4.4, hy + 1.2, tz - 8), Vector3.new(4.4, 3, 0.4), rgb(220, 255, 255), M.Neon, 0.05)
			bar(kit, H, Vector3.new(x + s * 5, hy + 7.4, tz), Vector3.new(x + s * 8.4, hy + 14, tz), 1, CYAN, M.Neon, 0.3)
			H.ball(kit, Vector3.new(x + s * 8.6, hy + 14.4, tz), 2, PINK, M.Neon)
			H.block(kit, CF.new(x + s * 10.1, hy, tz), Vector3.new(1.2, 6, 6), CYAN, M.Neon, 0.5)
		end
		block(kit, CF.new(x, hy - 4, tz - 8), Vector3.new(8, 1, 0.4), PINK, M.Neon, 0.05)
		-- scan lines across the hologram
		for i = 1, 3 do
			block(kit, CF.new(x, hy - 9 + i * 4.6, tz - 7.8), Vector3.new(19.5, 0.25, 0.2), CYAN, M.Neon, 0.5)
		end
	end
	-- a second, smaller billboard on the left (a bolt) on a low tower in front of the mech's knees
	block(kit, CF.new(70, 12, 124), Vector3.new(18, 24, 14), rgb(24, 16, 50), M.SmoothPlastic)
	billboard(kit, H, 70, 20, 116.5, 15, 9, PINK, "bolt")

	-- searchlight beams fanning out from behind the city
	for _, k in
		{ { 84, 0.3, PINK }, { 66, 0.62, CYAN }, { -84, -0.34, CYAN }, { -120, -0.1, PINK }, { 170, 0.5, VIOLET }, { -170, -0.55, VIOLET } }
	do
		local base = Vector3.new(k[1], 0, 240)
		local top = base + Vector3.new(k[2] * 220, 220, 30)
		bar(kit, H, base, top, 4, k[3], M.Neon, 0.9)
		bar(kit, H, base, top, 1.2, k[3], M.Neon, 0.7)
	end

	-- flying cars and drones with light trails, near and far, on the sides
	for _, k in
		{
			{ Vector3.new(40, 25, 50), 1, PINK, 1.8 },
			{ Vector3.new(36, 34, 96), -1, CYAN, 1.6 },
			{ Vector3.new(-42, 23, 48), -1, CYAN, 1.8 },
			{ Vector3.new(-42, 36, 104), 1, PINK, 1.6 },
			{ Vector3.new(84, 50, 150), 1, YELLOW, 2.4 },
			{ Vector3.new(-120, 58, 180), -1, PINK, 2.6 },
		}
	do
		flyingCar(kit, H, k[1], k[2], k[3], k[4])
	end
	for _, p in { Vector3.new(30, 17, 26), Vector3.new(-31, 19, 30), Vector3.new(-22, 27, 64), Vector3.new(54, 38, 86) } do
		block(kit, CF.new(p), Vector3.new(1.8, 0.5, 1.8), rgb(60, 60, 96), M.Metal)
		ball(kit, p + Vector3.new(0, -0.4, -0.6), 0.7, PINK, M.Neon)
		for _, s in { -1, 1 } do
			block(kit, CF.new(p + Vector3.new(s * 1.4, 0.3, 0)), Vector3.new(1.4, 0.1, 1.4), CYAN, M.Neon, 0.3)
		end
	end

	-- sparks in the air
	for i = 1, 40 do
		local spark = ball(
			kit,
			Vector3.new(rng:range(-48, 48), rng:range(2, 32), rng:range(-14, 40)),
			rng:range(0.14, 0.34),
			if i % 3 == 0 then CYAN elseif i % 3 == 1 then PINK else YELLOW,
			M.Neon
		)
		spark.Transparency = rng:range(0, 0.4)
	end
	for _, p in { Vector3.new(-26, 1, 16), Vector3.new(28, 1, 16), Vector3.new(0, 1, 34) } do
		emitter(kit, p, 14, CYAN, "rbxasset://textures/particles/sparkles_main.dds", "Sparkles")
	end

	return {
		Preset = {
			Lighting = {
				Brightness = 1.5,
				Ambient = Color3.new(0.22, 0.17, 0.36),
				OutdoorAmbient = Color3.new(0.4, 0.34, 0.62),
				ExposureCompensation = 0.1,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.9,
			},
			Atmosphere = {
				Density = 0.38,
				Offset = 0.2,
				Color = Color3.new(0.42, 0.14, 0.44),
				Decay = Color3.new(0.36, 0.12, 0.44),
				Glare = 0,
				Haze = 1.1,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.2, Saturation = 0.3, TintColor = Color3.new(1, 0.97, 1) },
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 0.95 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(8, 4, 30),
				Mid = rgb(60, 12, 92),
				Horizon = rgb(255, 60, 160),
				HorizonAway = rgb(220, 50, 170),
				Sun = rgb(0, 0, 0),
				MidAngle = 12,
				CloudCover = 0,
			},
		},
		Stage = rgb(40, 20, 50),
		StageMaterial = M.SmoothPlastic,
		Rim = PINK,
		Pedestal = rgb(46, 22, 60),
	}
end
