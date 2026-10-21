--[[
	The GALAXY banner backdrop (tools/lune/lib/limited_golems_preview.luau
	loads it for scene "limited_Galaxy"): returns the scene's Look.
	H = Preview.Helpers (block, ball, disc, light, emitter, strip, ...).

	Deep space over a little purple moon: a layered starfield with twinkling
	bright stars, glowing nebula clouds, a huge banded RINGED PLANET (the
	picture's left), a spiral GALAXY (the picture's right), a blue planet
	with its moon, comets with long tails, a rocket blasting off, a ring
	SPACE STATION with solar wings, crystal asteroids floating, glowing
	crystal fields and craters on the moon, a star-gate ring behind the
	Mythic, light shafts on the stage and sparkles in the air.
	(The camera looks along +Z: world +X is the picture's LEFT.)
]]

local roblox = require("@lune/roblox") :: any

local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local rgb = Color3.fromRGB
local M = roblox.Enum.Material
local PI = math.pi

local WHITE = rgb(255, 255, 255)
local CYAN = rgb(90, 236, 255)
local PINK = rgb(255, 96, 220)
local VIOLET = rgb(160, 90, 255)
local GOLD = rgb(255, 206, 90)

return function(kit: any, H: any): any
	local block, ball, disc, light, emitter = H.block, H.ball, H.disc, H.light, H.emitter
	local CF, rng = kit.CF, kit.Rng

	-- an ellipsoid (a block with a Sphere SpecialMesh, like the golems' gear)
	local function egg(cf: any, size: any, color: any, material: any?, transparency: number?): any
		local p = block(kit, cf, size, color, material, transparency)
		local mesh = H.Instance.new("SpecialMesh")
		mesh.MeshType = H.Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	-- a ring of `n` blocks round `center` in its XZ plane (planet rings, the gate, the station)
	local function ring(center: any, r: number, n: number, width: number, thick: number, color: any, material: any?, transparency: number?)
		local len = 2 * r * math.sin(PI / n) * 1.06
		for i = 1, n do
			local a = (i - 0.5) / n * 2 * PI
			block(
				kit,
				center * CF.new(math.cos(a) * r, 0, math.sin(a) * r) * CF.Angles(0, -a, 0),
				Vector3.new(width, thick, len),
				color,
				material,
				transparency
			)
		end
	end

	-- a four-point twinkle: a bright dot and two thin crossed rays
	local function twinkle(pos: any, size: number, color: any)
		ball(kit, pos, size * 0.35, WHITE, M.Neon)
		block(kit, CF.new(pos), Vector3.new(size * 2.4, size * 0.12, size * 0.12), color, M.Neon, 0.15)
		block(kit, CF.new(pos), Vector3.new(size * 0.12, size * 2.4, size * 0.12), color, M.Neon, 0.15)
	end

	-- a comet: a white-hot head and a long tail fading behind it along `dir`
	local function comet(head: any, dir: any, length: number, size: number, color: any)
		local back = dir.Unit
		local frame = CF.lookAt(head, head + back)
		ball(kit, head, size, WHITE, M.Neon)
		ball(kit, head, size * 1.9, color, M.Neon, 0.75)
		for i = 1, 5 do
			local t = i / 5
			local w = size * (1.15 - t * 0.55)
			egg(
				frame * CF.new(0, 0, -length * (t - 0.1)),
				Vector3.new(w, w, length * 0.34),
				if i <= 2 then WHITE:Lerp(color, 0.3) else color,
				M.Neon,
				0.15 + t * 0.7
			)
		end
	end

	---------------------------------------------------------------- the moon underfoot

	block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), rgb(58, 46, 112), M.Slate)
	block(kit, CF.new(0, 0.05, -30), Vector3.new(120, 0.1, 44), rgb(20, 16, 46), M.Slate) -- the dark foreground
	-- craters: a raised rim and a dark floor
	for _ = 1, 22 do
		local x, z, r = rng:range(-140, 140), rng:range(20, 190), rng:range(5, 15)
		if math.abs(x) > 34 or z > 40 then
			disc(kit, CF.new(x, 0.15, z), 0.6, r * 2.3, rgb(84, 70, 150), M.Slate)
			disc(kit, CF.new(x, 0.3, z), 0.6, r * 1.9, rgb(40, 32, 84), M.Slate)
		end
	end
	-- low moon ridges far off (a broken crater wall)
	for i = 1, 16 do
		local x = -260 + i * 32 + rng:range(-8, 8)
		local h = rng:range(6, 18) * (if math.abs(x) < 60 then 0.55 else 1)
		local z = 230 + rng:range(-20, 20)
		block(
			kit,
			CF.new(x, h * 0.3, z) * CF.Angles(rng:range(-0.2, 0.2), rng:range(0, PI), rng:range(-0.25, 0.25)),
			Vector3.new(h * 2.6, h, h * 1.8),
			if i % 2 == 0 then rgb(66, 52, 128) else rgb(48, 38, 98),
			M.Slate
		)
	end
	-- glowing crystal clusters on the moon (cyan, pink, violet)
	local clusters = {
		{ 40, 30, 1.0 },
		{ -44, 34, 1.0 },
		{ 70, 70, 1.4 },
		{ -78, 64, 1.4 },
		{ 22, 120, 1.6 },
		{ -30, 110, 1.4 },
		{ 110, 140, 2.0 },
		{ -120, 150, 2.0 },
	}
	local deep = { rgb(24, 96, 130), rgb(120, 28, 96), rgb(64, 36, 130) }
	for c, k in clusters do
		local tint = deep[(c - 1) % 3 + 1]
		for j = 1, 5 do
			local h = rng:range(3, 9) * k[3]
			block(
				kit,
				CF.new(k[1] + rng:range(-2.5, 2.5) * k[3], h * 0.4, k[2] + rng:range(-2.5, 2.5) * k[3])
					* CF.Angles(rng:range(-0.45, 0.45), rng:range(0, PI), rng:range(-0.45, 0.45)),
				Vector3.new(h * 0.28, h, h * 0.28),
				if j == 1 and c > 2 then WHITE:Lerp(tint, 0.5) else tint,
				M.Neon,
				if j % 2 == 0 then 0.15 else 0
			)
		end
		if c <= 4 then
			light(kit, Vector3.new(k[1], 5, k[2] - 4), tint, 30, 1.4)
		end
	end
	-- crystals framing the stage's back corners
	for _, k in { { 38, 16, deep[1] }, { -40, 17, deep[2] } } do
		for j = 1, 4 do
			local h = rng:range(3, 7)
			block(
				kit,
				CF.new(k[1] + rng:range(-2, 2), h * 0.4, k[2] + rng:range(-2, 2))
					* CF.Angles(rng:range(-0.5, 0.5), rng:range(0, PI), rng:range(-0.5, 0.5)),
				Vector3.new(h * 0.3, h, h * 0.3),
				if j == 1 then WHITE:Lerp(k[3], 0.4) else k[3],
				M.Neon
			)
		end
	end

	---------------------------------------------------------------- deep space

	-- nebula clouds: big soft glowing veils, far behind everything, layered
	for _, k in
		{
			{ 20, 70, 470, 240, 120, rgb(50, 12, 66), 0.45 },
			{ -70, 120, 480, 280, 130, rgb(16, 18, 70), 0.4 },
			{ 100, 140, 475, 220, 100, rgb(64, 16, 60), 0.5 },
			{ -10, 34, 460, 320, 76, rgb(80, 22, 80), 0.55 },
			{ -160, 50, 470, 240, 100, rgb(14, 36, 80), 0.5 },
			{ 180, 40, 470, 200, 90, rgb(36, 16, 72), 0.5 },
			{ 40, 56, 450, 130, 54, rgb(110, 40, 96), 0.7 },
			{ -50, 70, 450, 120, 50, rgb(40, 84, 120), 0.7 },
		}
	do
		egg(CF.new(k[1], k[2], k[3]) * CF.Angles(0, 0, rng:range(-0.4, 0.4)), Vector3.new(k[4], k[5], 30), k[6], M.Neon, k[7])
	end
	-- the starfield: hundreds of tiny stars, a few bright twinkles
	local starTints = { WHITE, rgb(200, 230, 255), rgb(255, 236, 200), rgb(255, 200, 250) }
	for i = 1, 230 do
		local x = rng:range(-330, 330)
		local y = rng:range(4, 230)
		local z = rng:range(400, 440)
		ball(kit, Vector3.new(x, y, z), rng:range(0.7, 2.0), starTints[i % 4 + 1], M.Neon, rng:range(0, 0.4))
	end
	for _, k in
		{
			{ 120, 150, 380, 5 },
			{ -95, 140, 380, 4 },
			{ 30, 125, 380, 3 },
			{ -40, 30, 300, 3.5 },
			{ 200, 105, 380, 4 },
			{ -230, 60, 380, 4.5 },
			{ 75, 40, 300, 3 },
			{ -150, 150, 380, 3.5 },
		}
	do
		twinkle(Vector3.new(k[1], k[2], k[3]), k[4], rgb(200, 230, 255))
	end

	---------------------------------------------------------------- the ringed planet (left)

	local px, py, pz, pr = 178, 72, 380, 46
	local planet = CF.new(px, py, pz) * CF.Angles(-0.12, 0, -0.32)
	ball(kit, Vector3.new(px, py, pz), 2 * pr, rgb(255, 150, 96), M.SmoothPlastic)
	-- the bands: thin cylinders poking out of the sphere at heights in its frame
	for i, k in
		{
			{ 0.62, 5, rgb(255, 214, 150) },
			{ 0.3, 7, rgb(214, 96, 70) },
			{ -0.05, 6, rgb(255, 190, 120) },
			{ -0.4, 8, rgb(190, 80, 90) },
			{ -0.72, 5, rgb(255, 170, 110) },
		}
	do
		local y = k[1] * pr
		local chord = 2 * math.sqrt(pr * pr - y * y)
		disc(kit, planet * CF.new(0, y, 0), k[2], chord + 0.3, k[3], M.SmoothPlastic)
	end
	-- a glowing rim of atmosphere
	ball(kit, Vector3.new(px, py, pz + 6), 2 * pr + 10, rgb(120, 50, 70), M.Neon, 0.6)
	-- the rings: three bands of segments (a gap between them)
	local rings = planet * CF.Angles(0.3, 0, 0)
	ring(rings, pr * 1.45, 44, 12, 0.3, rgb(150, 120, 86), M.Neon, 0.15)
	ring(rings, pr * 1.74, 48, 9, 0.3, rgb(130, 76, 56), M.Neon, 0.3)
	ring(rings, pr * 1.97, 52, 4, 0.3, rgb(120, 56, 100), M.Neon, 0.45)
	-- two moons of its own
	ball(kit, Vector3.new(px - 74, py + 72, pz - 30), 20, rgb(214, 210, 236), M.SmoothPlastic)
	ball(kit, Vector3.new(px - 78, py + 76, pz - 40), 6, rgb(170, 166, 200), M.SmoothPlastic)
	ball(kit, Vector3.new(px + 88, py - 52, pz - 20), 14, rgb(110, 220, 210), M.SmoothPlastic)

	---------------------------------------------------------------- the spiral galaxy (right)

	local gx, gy, gz = -200, 105, 420
	local galaxy = CF.new(gx, gy, gz) * CF.Angles(-1.05, 0.25, 0.35)
	egg(galaxy, Vector3.new(170, 6, 170), rgb(40, 20, 80), M.Neon, 0.5)
	egg(galaxy, Vector3.new(90, 10, 90), rgb(90, 46, 110), M.Neon, 0.5)
	ball(kit, Vector3.new(gx, gy, gz - 4), 22, rgb(255, 240, 220), M.Neon)
	ball(kit, Vector3.new(gx, gy, gz - 2), 36, rgb(130, 70, 120), M.Neon, 0.5)
	for arm = 0, 2 do
		for i = 1, 40 do
			local t = i / 40
			local a = arm * 2 * PI / 3 + t * 4.2
			local r = 10 + t * 78
			local tint = rgb(255, 210, 250):Lerp(if arm == 1 then rgb(90, 160, 255) else rgb(170, 90, 255), t)
			local p = galaxy * CF.new(math.cos(a) * r, 0, math.sin(a) * r)
			ball(kit, p.Position, (1 - t) * 7 + 2.5, tint, M.Neon, 0.1 + t * 0.6)
		end
	end

	---------------------------------------------------------------- the middle sky

	-- a blue planet with a cloud swirl and its little moon (behind the middle)
	ball(kit, Vector3.new(-30, 92, 360), 34, rgb(70, 150, 255), M.SmoothPlastic)
	egg(CF.new(-30, 96, 352) * CF.Angles(0, 0, 0.3), Vector3.new(30, 8, 22), rgb(220, 240, 255), M.SmoothPlastic, 0.3)
	ball(kit, Vector3.new(-30, 92, 362), 40, rgb(30, 70, 110), M.Neon, 0.6)
	ball(kit, Vector3.new(4, 110, 350), 9, rgb(230, 226, 250), M.SmoothPlastic)
	-- a small red planet low on the left
	ball(kit, Vector3.new(80, 30, 260), 16, rgb(236, 92, 64), M.SmoothPlastic)
	ball(kit, Vector3.new(80, 30, 262), 20, rgb(110, 40, 30), M.Neon, 0.6)
	-- comets streaking across
	comet(Vector3.new(-62, 70, 250), Vector3.new(-1, 0.45, 0.1), 70, 4, CYAN)
	comet(Vector3.new(58, 96, 300), Vector3.new(1, 0.55, 0), 56, 3.2, PINK)
	comet(Vector3.new(-120, 34, 240), Vector3.new(-0.8, 0.6, 0.2), 40, 2.4, rgb(255, 210, 120))

	---------------------------------------------------------------- the rocket (left of the middle)

	do
		local base = CF.new(70, 44, 170) * CF.Angles(0, 0, -0.42)
		local white, red = rgb(240, 242, 252), rgb(236, 60, 80)
		disc(kit, base, 14, 6, white, M.SmoothPlastic)
		disc(kit, base * CF.new(0, 9, 0), 4, 5, red, M.SmoothPlastic)
		disc(kit, base * CF.new(0, 12.2, 0), 2.4, 3.4, red, M.SmoothPlastic)
		disc(kit, base * CF.new(0, 14.2, 0), 1.6, 1.8, red, M.SmoothPlastic)
		disc(kit, base * CF.new(0, -7.6, 0), 1.6, 6.6, red, M.SmoothPlastic)
		-- the window
		ball(kit, (base * CF.new(0, 3, -2.6)).Position, 2.4, rgb(120, 230, 255), M.Neon)
		-- fins
		for _, side in { -1, 1 } do
			kit.Geo.triangle(
				kit.Folder,
				(base * CF.new(side * 3, -2, 0)).Position,
				(base * CF.new(side * 3, -8.4, 0)).Position,
				(base * CF.new(side * 7, -9.6, 0)).Position,
				0.8,
				red,
				M.SmoothPlastic
			)
		end
		-- the flame and its smoke trail down to the moon
		egg(base * CF.new(0, -11.5, 0), Vector3.new(4.6, 8, 4.6), rgb(255, 214, 70), M.Neon)
		egg(base * CF.new(0, -15, 0), Vector3.new(6, 10, 6), rgb(255, 120, 40), M.Neon, 0.35)
		for i = 1, 7 do
			local p = (base * CF.new(rng:range(-1, 1) * i * 0.4, -20 - i * 5.5, 0)).Position
			ball(kit, p, 6 + i * 1.6, rgb(220, 210, 255), M.SmoothPlastic, 0.35 + i * 0.07)
		end
		light(kit, (base * CF.new(0, -14, -6)).Position, rgb(255, 160, 60), 40, 2)
	end

	---------------------------------------------------------------- the space station (right of the middle)

	do
		local center = CF.new(-62, 48, 210) * CF.Angles(-1.2, 0.3, 0.25)
		local metal, dark = rgb(220, 226, 240), rgb(70, 80, 120)
		ring(center, 16, 18, 2.4, 2.4, metal, M.SmoothPlastic)
		ring(center, 16, 9, 0.6, 2.6, CYAN, M.Neon) -- windows glowing round the wheel
		-- the hub and its spokes
		ball(kit, center.Position, 8, metal, M.SmoothPlastic)
		disc(kit, center * CF.Angles(PI / 2, 0, 0), 22, 2.4, dark, M.SmoothPlastic)
		for i = 0, 2 do
			local a = i * PI / 3
			block(kit, center * CF.Angles(0, a, 0), Vector3.new(32, 1, 1), dark, M.SmoothPlastic)
		end
		-- solar wings on a mast
		local mast = center * CF.Angles(PI / 2, 0, 0) * CF.new(0, 0, 0)
		for _, side in { -1, 1 } do
			local wing = mast * CF.new(side * 24, 0, 0)
			block(kit, wing, Vector3.new(14, 0.4, 7), rgb(50, 80, 190), M.SmoothPlastic)
			block(kit, wing * CF.new(0, 0.3, 0), Vector3.new(13, 0.2, 0.4), rgb(140, 180, 255), M.Neon)
			block(kit, wing * CF.new(side * -10, 0, 0), Vector3.new(6, 0.6, 0.6), dark, M.SmoothPlastic)
		end
		ball(kit, (center * CF.new(0, 0, 0)).Position + Vector3.new(0, 0, -5), 2.2, rgb(255, 80, 120), M.Neon)
	end

	---------------------------------------------------------------- crystal asteroids floating

	for _, k in
		{
			{ -38, 28, 80, 6, PINK },
			{ 92, 52, 170, 9, VIOLET },
			{ -100, 22, 150, 8, CYAN },
			{ -22, 46, 110, 3, VIOLET },
		}
	do
		local p = Vector3.new(k[1], k[2], k[3])
		local s = k[4]
		local rock = CF.new(p) * CF.Angles(rng:range(0, PI), rng:range(0, PI), rng:range(0, PI))
		block(kit, rock, Vector3.new(s * 1.3, s, s * 1.1), rgb(120, 104, 180), M.Slate)
		block(kit, rock * CF.Angles(0.6, 0.4, 0.8), Vector3.new(s, s * 0.9, s * 0.9), rgb(96, 80, 156), M.Slate)
		for j = 1, 3 do
			local dir = CF.Angles(rng:range(-1.2, 1.2), rng:range(0, 2 * PI), rng:range(-1.2, 1.2))
			block(
				kit,
				CF.new(p) * dir * CF.new(0, s * 0.6, 0),
				Vector3.new(s * 0.26, s * (0.7 + j * 0.15), s * 0.26),
				if j == 2 then WHITE:Lerp(k[5], 0.4) else k[5],
				M.Neon
			)
		end
	end

	---------------------------------------------------------------- the stage's own magic

	-- (the shard showcase looks from close by: no gate, no near sparkles there)
	local banner = string.sub(kit.Folder.Name, 1, 7) == "Limited"
	-- the star gate: a glowing ring standing behind the Mythic, gold studs on it
	if banner then
		local gate = CF.new(0, 15, 30) * CF.Angles(PI / 2, 0, 0)
		ring(gate, 13, 32, 0.8, 0.8, rgb(46, 120, 170), M.Neon)
		ring(gate, 14.2, 32, 1.4, 1.4, rgb(48, 40, 110), M.SmoothPlastic)
		for i = 1, 8 do
			local a = (i - 0.5) / 8 * 2 * PI
			local p = gate * CF.new(math.cos(a) * 14.2, -0.6, math.sin(a) * 14.2)
			block(kit, p * CF.Angles(0, -a + PI / 4, 0), Vector3.new(1.6, 1.6, 1.6), GOLD, M.SmoothPlastic)
		end
		-- a soft veil inside it
		egg(CF.new(0, 15, 30.5), Vector3.new(26, 26, 0.6), rgb(30, 18, 66), M.Neon, 0.45)
		light(kit, Vector3.new(0, 14, 24), rgb(150, 120, 255), 30, 1.2)
	end
	-- sparkles in the air round the golems
	for i = 1, if banner then 36 else 0 do
		local p = Vector3.new(rng:range(-46, 46), rng:range(3, 30), rng:range(10, 40))
		if i % 6 == 0 then
			twinkle(p, rng:range(0.5, 0.8), if i % 2 == 0 then CYAN else PINK)
		else
			ball(kit, p, rng:range(0.15, 0.35), ({ WHITE, CYAN, PINK, GOLD })[i % 4 + 1], M.Neon, rng:range(0, 0.3))
		end
	end
	for _, p in { Vector3.new(-26, 1, 16), Vector3.new(28, 1, 16), Vector3.new(0, 1, 30), Vector3.new(-46, 1, 6), Vector3.new(46, 1, 6) } do
		emitter(kit, p, 16, rgb(200, 220, 255), "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	end
	if banner then
		light(kit, Vector3.new(-30, 8, -6), CYAN, 26, 0.8)
		light(kit, Vector3.new(30, 8, -6), PINK, 26, 0.8)
	end

	return {
		Preset = {
			Lighting = {
				Brightness = 2.2,
				Ambient = Color3.new(0.26, 0.22, 0.42),
				OutdoorAmbient = Color3.new(0.46, 0.4, 0.7),
				ExposureCompensation = 0.12,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.6,
			},
			Atmosphere = {
				Density = 0.22,
				Offset = 0.1,
				Color = Color3.new(0.3, 0.2, 0.55),
				Decay = Color3.new(0.22, 0.12, 0.45),
				Glare = 0,
				Haze = 0.6,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.22, Saturation = 0.32, TintColor = Color3.new(0.98, 0.97, 1) },
			Bloom = { Intensity = 0.7, Size = 28, Threshold = 0.92 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(4, 3, 18),
				Mid = rgb(22, 10, 58),
				Horizon = rgb(140, 50, 180),
				HorizonAway = rgb(90, 40, 170),
				Sun = rgb(0, 0, 0),
				MidAngle = 12,
				CloudCover = 0,
			},
		},
		Stage = rgb(22, 18, 50),
		StageMaterial = M.Slate,
		Rim = CYAN,
		Pedestal = rgb(18, 14, 42),
	}
end
