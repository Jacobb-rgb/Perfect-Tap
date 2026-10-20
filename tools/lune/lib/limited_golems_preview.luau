--[[
	LIMITED EDITION golem proposals (Config/LimitedGolems, a prototype):
	one concept picture per theme, so the owner can pick the set for the
	Robux shop's FEATURED banner.

	  scene "limited_<Theme>" (Dragonforge, Galaxy, MechaNeon, FrostTitans)
	  for tools/lune/export_scene.luau, shots in
	  tools/preview/limited_golems_shots.json (1600 x 900, the scene's own
	  camera):
	    the theme's diorama (its own sky colours in the scene's Surface
	    preset, a big backdrop built from parts: a volcano, a lava river and
	    a dragon against the moon / planets, a nebula and stars / a neon
	    city and a synthwave sun / glaciers and the northern lights), a stage
	    with the set's 6 golems built by the game's GolemBuilder (left to
	    right: Epic, Legendary | the MYTHIC on a pedestal, bigger | Epic,
	    Rare, Rare), and the UI overlay "ui_limited_<Theme>" (the Pop kit):
	    the proposal letter, the title, LIMITED EDITION, the tagline, each
	    golem's name, rarity and banner odds under its feet, BUY 1/3/10/50.
	  Everything at once (pictures + icons + the sheets in
	  docs/screenshots/limited_golems/): bash tools/preview/limited_golems.sh
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local Enum = roblox.Enum
local rgb = Color3.fromRGB
local M = Enum.Material
local PI = math.pi

Preview.Width = 1600
Preview.Height = 900
Preview.Camera = { Position = Vector3.new(-1.5, 8.8, -46), Target = Vector3.new(-1.5, 10.6, 0), Fov = 40 }
Preview.Letters = { Dragonforge = "A", Galaxy = "B", MechaNeon = "C", FrostTitans = "D" }
Preview.StageTop = 1
Preview.PedestalTop = 2.8
-- where the set's golems stand: { index in the set, x, z, size }; the Mythic on its pedestal
-- (the camera looks along +Z: world -X is the picture's right)
Preview.Slots = {
	{ 2, -30.5, 9, 2.2 },
	{ 1, -21, 4.5, 2.2 },
	{ 3, -11.4, 1, 2.2 },
	{ 6, 0, -3.5, 2.9 },
	{ 5, 12.4, 1, 2.2 },
	{ 4, 24, 4.5, 2.2 },
}

---------------------------------------------------------------- part helpers

type Kit = {
	Folder: any,
	CF: any,
	Rng: any,
	Geo: any,
}

local function new(kit: Kit, className: string, props: { [string]: any }): any
	local p = kit.Geo.make(className, props, kit.Folder)
	p.CastShadow = props.CastShadow == true
	p.CanCollide = false
	return p
end

local function block(kit: Kit, cf: any, size: any, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function ball(kit: Kit, pos: any, diameter: number, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		Shape = Enum.PartType.Ball,
		CFrame = kit.CF.new(pos),
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

-- an upright cylinder (Roblox cylinders run along X)
local function disc(kit: Kit, cf: any, height: number, diameter: number, color: any, material: any?, transparency: number?): any
	return new(kit, "Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = cf * kit.CF.Angles(0, 0, PI / 2),
		Size = Vector3.new(height, diameter, diameter),
		Color = color,
		Material = material or M.SmoothPlastic,
		Transparency = transparency or 0,
	})
end

local function light(kit: Kit, pos: any, color: any, range: number, brightness: number)
	local holder = block(kit, kit.CF.new(pos), Vector3.new(0.2, 0.2, 0.2), color, nil, 1)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = holder
end

local function emitter(kit: Kit, pos: any, size: number, color: any, texture: string, name: string)
	local holder = block(kit, kit.CF.new(pos), Vector3.new(size, 1, size), color, nil, 1)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = roblox.ColorSequence.new(color)
	e.Parent = holder
end

-- a flat strip lying on the ground from a to b (rivers, grid lines)
local function strip(kit: Kit, a: any, b: any, width: number, y: number, color: any, material: any?, transparency: number?): any
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = kit.CF.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	return block(kit, cf, Vector3.new(width, 0.08, length + width * 0.6), color, material, transparency)
end

-- a cube balanced on its corner, half buried: a low-poly peak
local function peak(kit: Kit, pos: any, size: number, color: any, material: any?, spin: number?): any
	local cf = kit.CF.new(pos) * kit.CF.Angles(0, spin or 0, 0) * kit.CF.Angles(math.atan(1 / math.sqrt(2)), 0, PI / 4)
	return block(kit, cf, Vector3.new(size, size, size), color, material)
end

-- a low-poly mountain facing the camera: two faces meeting at a ridge, a
-- snowy cap on each (flat triangles, Geo.triangle)
local function mountain(kit: Kit, x: number, z: number, w: number, h: number, left: any, right: any, cap: any?)
	local apex = Vector3.new(x, h, z)
	local bl, br, front = Vector3.new(x + w, 0, z + w * 0.3), Vector3.new(x - w, 0, z + w * 0.3), Vector3.new(x + w * 0.08, 0, z - w * 0.6)
	kit.Geo.triangle(kit.Folder, apex, bl, front, 2, left, M.Glacier)
	kit.Geo.triangle(kit.Folder, apex, front, br, 2, right, M.Glacier)
	if cap then
		local toCam = Vector3.new(0, 0, -1.2)
		local k = 0.34
		local mid = apex + (front - apex) * (k * 1.15) + toCam
		kit.Geo.triangle(kit.Folder, apex + toCam, apex + (bl - apex) * k + toCam, mid, 1, cap, M.Snow)
		kit.Geo.triangle(kit.Folder, apex + toCam, mid, apex + (br - apex) * k + toCam, 1, cap:Lerp(right, 0.25), M.Snow)
	end
end

-- tiny glowing stars over a far wall of sky
local function stars(kit: Kit, count: number, z: number, x0: number, x1: number, y0: number, y1: number, colors: { any })
	for i = 1, count do
		local s = kit.Rng:range(0.5, 1.4)
		local star = block(
			kit,
			kit.CF.new(kit.Rng:range(x0, x1), kit.Rng:range(y0, y1), z + kit.Rng:range(-10, 10)) * kit.CF.Angles(0, 0, PI / 4),
			Vector3.new(s, s, 0.2),
			colors[(i % #colors) + 1],
			M.Neon
		)
		star.Transparency = kit.Rng:range(0, 0.45)
	end
end

---------------------------------------------------------------- the themes

type Look = {
	Preset: { [string]: any }, -- the scene's Surface preset (sky, light, fog, colour)
	Stage: any, -- stage colour
	StageMaterial: any,
	Rim: any, -- the stage's glowing rim
	Pedestal: any,
}

local THEMES: { [string]: (kit: Kit) -> Look } = {}

-- A: volcano, lava river, a dragon against a huge moon
THEMES.Dragonforge = function(kit)
	local CF, rng = kit.CF, kit.Rng
	local basalt, basaltDark = rgb(56, 40, 44), rgb(36, 26, 32)
	local lava, lavaHot = rgb(255, 96, 20), rgb(255, 170, 40)
	block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), rgb(46, 32, 36), M.Basalt)
	-- the volcano (the picture's left): a stepped basalt cone, a glowing crater, lava down its front
	local vx, vz = 74, 190
	local y = 0
	for i = 1, 9 do
		local d = 130 - i * 11.5
		local h = 9 - i * 0.35
		disc(kit, CF.new(vx, y + h / 2, vz) * CF.Angles(0, i * 0.7, 0), h, d, if i % 2 == 0 then basalt else basaltDark, M.Basalt)
		local r = d / 2
		for k, dx in { -8, 10 } do
			local x = dx * (1 - i * 0.06)
			local z = vz - math.sqrt(r * r - x * x) + 0.7
			block(kit, CF.new(vx + x, y + h / 2, z), Vector3.new(3 - i * 0.18, h + 0.3, 1.4), if i > 5 then lavaHot else lava, M.Neon)
			if k == 1 and i % 3 == 0 then
				block(kit, CF.new(vx + x * 0.5 + 1, y + h + 0.1, z + 2), Vector3.new(math.abs(x) + 3, 0.3, 2), lava, M.Neon)
			end
		end
		y += h
	end
	disc(kit, CF.new(vx, y + 0.2, vz), 0.6, 22, lavaHot, M.Neon)
	for i = 1, 3 do
		emitter(kit, Vector3.new(vx + (i - 2) * 6, y + 3, vz), 10, rgb(70, 46, 50), "rbxasset://textures/particles/smoke_main.dds", "Smoke")
	end
	emitter(kit, Vector3.new(vx, y + 2, vz - 10), 20, lavaHot, "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	-- a second, smaller peak further back on the right
	local y2 = 0
	for i = 1, 6 do
		local d = 90 - i * 11
		local h = 8 - i * 0.4
		disc(kit, CF.new(-150, y2 + h / 2, 300), h, d, if i % 2 == 0 then basalt else basaltDark, M.Basalt)
		y2 += h
	end
	disc(kit, CF.new(-150, y2 + 0.2, 300), 0.5, 18, lava, M.Neon)
	-- the huge moon (the picture's right) and a dragon flying across it
	local mx, my, mz = -78, 58, 300
	ball(kit, Vector3.new(mx, my, mz), 84, rgb(190, 104, 70), M.Neon)
	ball(kit, Vector3.new(mx, my, mz + 8), 112, rgb(150, 56, 44), M.Neon, 0.82)
	local ink = rgb(20, 6, 12)
	local d = CF.new(mx + 6, my + 2, mz - 50) * CF.Angles(0, 0, 0.1)
	local function piece(x: number, y_: number, angle: number, size: any)
		block(kit, d * CF.new(x, y_, 0) * CF.Angles(0, 0, angle), size, ink)
	end
	local function tri(a: { number }, b: { number }, c: { number })
		kit.Geo.triangle(
			kit.Folder,
			(d * CF.new(a[1], a[2], 0)).Position,
			(d * CF.new(b[1], b[2], 0)).Position,
			(d * CF.new(c[1], c[2], 0)).Position,
			1.5,
			ink
		)
	end
	piece(0, 0, 0.05, Vector3.new(24, 5.5, 2)) -- body
	piece(13, 4.5, 0.75, Vector3.new(12, 3.2, 2)) -- neck
	piece(19.5, 10, 0.25, Vector3.new(6, 3.4, 2)) -- head
	piece(24, 9.4, 0.05, Vector3.new(5, 2, 2)) -- snout
	piece(17.5, 12.6, 2.6, Vector3.new(5, 0.9, 2)) -- horns
	piece(16.8, 11.4, 2.85, Vector3.new(4.4, 0.8, 2))
	piece(-15, -2, 0.2, Vector3.new(12, 3.2, 2)) -- tail
	piece(-25, -5.2, 0.4, Vector3.new(10, 2, 2))
	piece(-33, -5.6, -0.5, Vector3.new(8, 1.4, 2))
	piece(-37.5, -2.6, 0.785, Vector3.new(4, 4, 2)) -- the tail's spade
	piece(6, -4.4, -0.5, Vector3.new(2, 5, 2)) -- legs
	piece(-6, -4.4, -0.35, Vector3.new(2, 5, 2))
	-- the near wing: arm up to the wrist, fingers fanning back, a scalloped edge
	tri({ 4, 2 }, { -2, 30 }, { -14, 2 })
	tri({ -2, 30 }, { -30, 22 }, { -14, 2 })
	tri({ -2, 30 }, { -18, 34 }, { -30, 22 })
	-- the far wing peeking over the body
	tri({ 8, 3 }, { 14, 24 }, { 2, 8 })
	tri({ 14, 24 }, { 2, 26 }, { 2, 8 })
	-- the lava river winding from the volcano toward the stage, lava pools
	local river = {
		Vector3.new(60, 0, 160),
		Vector3.new(40, 0, 132),
		Vector3.new(12, 0, 116),
		Vector3.new(-14, 0, 96),
		Vector3.new(-10, 0, 72),
		Vector3.new(10, 0, 58),
		Vector3.new(26, 0, 46),
	}
	for i = 1, #river - 1 do
		strip(kit, river[i], river[i + 1], 8 - i * 0.6, 0.05, lava, M.Neon)
		strip(kit, river[i], river[i + 1], 2.6 - i * 0.2, 0.1, lavaHot, M.Neon)
	end
	for _, p in { Vector3.new(-44, 0, 50), Vector3.new(-60, 0, 90), Vector3.new(48, 0, 80) } do
		disc(kit, CF.new(p.X, 0.06, p.Z), 0.1, rng:range(8, 14), lava, M.Neon)
	end
	light(kit, Vector3.new(10, 5, 56), lava, 34, 2)
	-- glowing cracks in the ground near the stage
	for _ = 1, 14 do
		local a = Vector3.new(rng:range(-70, 70), 0, rng:range(-16, 36))
		if math.abs(a.X) > 44 or a.Z > 20 then
			local b = a + Vector3.new(rng:range(-6, 6), 0, rng:range(-6, 6))
			strip(kit, a, b, 0.35, 0.03, lava, M.Neon)
		end
	end
	-- jagged basalt spires at the sides
	for _, k in { { 64, 60, 30 }, { 50, 36, 16 }, { 84, 30, 18 }, { -54, 40, 18 }, { -70, 62, 26 }, { -86, 30, 14 }, { 40, 110, 26 } } do
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
	-- embers in the air
	for _, p in { Vector3.new(-24, 1, 16), Vector3.new(26, 1, 16), Vector3.new(0, 1, 34), Vector3.new(-44, 1, 6), Vector3.new(44, 1, 6) } do
		emitter(kit, p, 14, lavaHot, "rbxasset://textures/particles/sparkles_main.dds", "Embers")
	end
	return {
		Preset = {
			Lighting = {
				Brightness = 2.4,
				Ambient = Color3.new(0.34, 0.2, 0.18),
				OutdoorAmbient = Color3.new(0.56, 0.36, 0.32),
				ExposureCompensation = 0.15,
				EnvironmentDiffuseScale = 0.3,
				EnvironmentSpecularScale = 0.4,
			},
			Atmosphere = {
				Density = 0.5,
				Offset = 0.2,
				Color = Color3.new(0.55, 0.22, 0.18),
				Decay = Color3.new(0.42, 0.14, 0.16),
				Glare = 0,
				Haze = 1.4,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.18, Saturation = 0.22, TintColor = Color3.new(1, 0.96, 0.94) },
			Bloom = { Intensity = 0.8, Size = 30, Threshold = 0.92 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(26, 8, 26),
				Mid = rgb(96, 20, 36),
				Horizon = rgb(255, 110, 50),
				HorizonAway = rgb(230, 80, 40),
				Sun = rgb(0, 0, 0),
				MidAngle = 14,
				CloudCover = 0.35,
			},
		},
		Stage = rgb(30, 24, 30),
		StageMaterial = M.Basalt,
		Rim = lava,
		Pedestal = rgb(24, 18, 24),
	}
end

-- B: planets, a nebula and stars over a little moon
THEMES.Galaxy = function(kit)
	local CF, rng = kit.CF, kit.Rng
	local surface = rgb(70, 60, 124)
	block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), surface, M.Slate)
	-- craters
	for _ = 1, 26 do
		local x, z, r = rng:range(-120, 120), rng:range(14, 200), rng:range(5, 16)
		disc(kit, CF.new(x, 0.02, z), 0.3, r * 1.2, rgb(88, 78, 150), M.Slate)
		disc(kit, CF.new(x, 0.08, z), 0.3, r, rgb(52, 44, 98), M.Slate)
	end
	-- glowing crystal clusters
	for _, k in { { -40, 26 }, { 38, 30 }, { -66, 64 }, { 62, 70 }, { -20, 90 }, { 26, 110 } } do
		for j = 1, 4 do
			local h = rng:range(4, 10)
			block(
				kit,
				CF.new(k[1] + rng:range(-3, 3), h / 2 - 0.5, k[2] + rng:range(-3, 3))
					* CF.Angles(rng:range(-0.4, 0.4), rng:range(0, PI), rng:range(-0.4, 0.4)),
				Vector3.new(h * 0.3, h, h * 0.3),
				if j % 2 == 0 then rgb(80, 230, 255) else rgb(220, 110, 255),
				M.Neon
			)
		end
	end
	light(kit, Vector3.new(-30, 6, 20), rgb(90, 220, 255), 40, 1.6)
	light(kit, Vector3.new(30, 6, 20), rgb(220, 110, 255), 40, 1.6)
	-- the nebula: big soft glowing clouds far away
	for _, k in
		{
			{ 150, 150, 150, rgb(120, 30, 110) },
			{ 40, 230, 170, rgb(60, 30, 140) },
			{ -170, 200, 140, rgb(30, 70, 140) },
			{ -40, 260, 150, rgb(110, 30, 120) },
		}
	do
		ball(kit, Vector3.new(k[1], k[2], 440), k[3], k[4], M.Neon, 0.9)
		ball(kit, Vector3.new(k[1] + 30, k[2] - 20, 430), k[3] * 0.6, k[4], M.Neon, 0.86)
	end
	stars(kit, 260, 380, -300, 300, 20, 280, { rgb(255, 255, 255), rgb(200, 230, 255), rgb(255, 240, 200) })
	-- a big ringed planet (left) and a small blue one with a moon (right)
	ball(kit, Vector3.new(-78, 66, 250), 64, rgb(255, 150, 100), M.SmoothPlastic)
	ball(kit, Vector3.new(-82, 74, 249), 50, rgb(255, 196, 140), M.SmoothPlastic, 0.55)
	disc(kit, CF.new(-78, 66, 250) * CF.Angles(-0.35, 0, 0.32), 0.6, 128, rgb(255, 210, 160), M.Neon, 0.55)
	disc(kit, CF.new(-78, 66, 250) * CF.Angles(-0.35, 0, 0.32), 0.7, 100, rgb(255, 150, 110), M.Neon, 0.75)
	ball(kit, Vector3.new(86, 92, 260), 30, rgb(80, 200, 230), M.SmoothPlastic)
	ball(kit, Vector3.new(110, 108, 255), 9, rgb(230, 226, 250), M.SmoothPlastic)
	-- shooting stars
	for _, k in { { 40, 60, 200, -0.4 }, { -150, 120, 300, -0.35 } } do
		for j = 1, 3 do
			local s = block(
				kit,
				CF.new(k[1] + j * 9, k[2] + j * 9 * -k[4], k[3]) * CF.Angles(0, 0, -k[4] - PI / 2 + PI / 2),
				Vector3.new(10, 0.7, 0.4),
				rgb(255, 255, 255),
				M.Neon
			)
			s.Transparency = (j - 1) * 0.3
		end
	end
	return {
		Preset = {
			Lighting = {
				Brightness = 2.2,
				Ambient = Color3.new(0.2, 0.18, 0.36),
				OutdoorAmbient = Color3.new(0.4, 0.36, 0.66),
				ExposureCompensation = 0.1,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.5,
			},
			Atmosphere = {
				Density = 0.3,
				Offset = 0.2,
				Color = Color3.new(0.3, 0.22, 0.55),
				Decay = Color3.new(0.25, 0.16, 0.48),
				Glare = 0,
				Haze = 1,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.2, Saturation = 0.3, TintColor = Color3.new(0.98, 0.97, 1) },
			Bloom = { Intensity = 0.65, Size = 28, Threshold = 0.93 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(6, 4, 24),
				Mid = rgb(34, 14, 74),
				Horizon = rgb(150, 60, 190),
				HorizonAway = rgb(120, 50, 180),
				Sun = rgb(0, 0, 0),
				MidAngle = 14,
				CloudCover = 0,
			},
		},
		Stage = rgb(40, 34, 84),
		StageMaterial = M.Slate,
		Rim = rgb(80, 230, 255),
		Pedestal = rgb(30, 24, 66),
	}
end

-- C: a neon city at night, a synthwave sun, a glowing grid floor
THEMES.MechaNeon = function(kit)
	local CF, rng = kit.CF, kit.Rng
	local pink, cyan, violet = rgb(255, 50, 190), rgb(0, 230, 255), rgb(150, 80, 255)
	local floor = block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), rgb(20, 18, 36), M.SmoothPlastic)
	floor.Reflectance = 0.25
	-- the glowing grid
	for x = -150, 150, 12 do
		strip(kit, Vector3.new(x, 0, 12), Vector3.new(x * 1.6, 0, 150), 0.35, 0.03, if x % 24 == 0 then pink else violet, M.Neon)
	end
	for z = 14, 150, 10 do
		strip(kit, Vector3.new(-260, 0, z), Vector3.new(260, 0, z), 0.3, 0.03, cyan, M.Neon, 0.25)
	end
	-- the synthwave sun behind the city: a big disc, stripes across its lower half
	local sx, sy, sz = 0, 52, 380
	ball(kit, Vector3.new(sx, sy, sz), 120, rgb(255, 90, 150), M.Neon)
	ball(kit, Vector3.new(sx, sy + 14, sz - 8), 96, rgb(255, 180, 90), M.Neon)
	for i = 1, 6 do
		block(kit, CF.new(sx, sy - 4 - i * 7.5, sz - 64), Vector3.new(130, 1 + i * 0.7, 1), rgb(30, 10, 50))
	end
	-- the skyline: dark towers with neon window bands, edges and signs
	for row, r in { { 140, 30, 110, 0.0 }, { 200, 50, 160, 0.3 } } do
		local z0 = r[1]
		local x = -260
		while x < 260 do
			local w = rng:range(14, 30)
			local h = rng:range(r[2], r[3]) * (if math.abs(x + w / 2) < 70 then (if row == 1 then 0.3 else 0.36) else 1)
			local z = z0 + rng:range(-10, 10)
			local tone = if row == 1 then rgb(30, 24, 60) else rgb(44, 30, 84)
			block(kit, CF.new(x + w / 2, h / 2, z), Vector3.new(w, h, 16), tone)
			-- window bands
			local bands = math.floor(h / 9)
			for b = 1, bands do
				if rng:range(0, 1) < 0.55 then
					block(
						kit,
						CF.new(x + w / 2, b * 9 - 3, z - 8.1),
						Vector3.new(w * rng:range(0.5, 0.85), 0.9, 0.2),
						if rng:range(0, 1) < 0.5 then cyan else pink,
						M.Neon,
						r[4]
					)
				end
			end
			-- glowing edges on some towers, beacons on the roofs
			if rng:range(0, 1) < 0.4 then
				block(kit, CF.new(x + 0.4, h / 2, z - 8.1), Vector3.new(0.6, h, 0.3), violet, M.Neon, r[4])
				block(kit, CF.new(x + w - 0.4, h / 2, z - 8.1), Vector3.new(0.6, h, 0.3), violet, M.Neon, r[4])
			end
			if rng:range(0, 1) < 0.5 then
				block(kit, CF.new(x + w / 2, h + 4, z), Vector3.new(0.6, 8, 0.6), rgb(60, 50, 90))
				ball(kit, Vector3.new(x + w / 2, h + 8.4, z), 1.6, rgb(255, 40, 60), M.Neon)
			end
			x += w + rng:range(2, 8)
		end
	end
	-- big signs on the front towers
	for _, k in { { -70, 52, 132, pink }, { 74, 46, 128, cyan }, { -130, 70, 134, cyan } } do
		local frame = k[4]
		block(kit, CF.new(k[1], k[2], k[3] - 9), Vector3.new(16, 0.8, 0.4), frame, M.Neon)
		block(kit, CF.new(k[1], k[2] - 10, k[3] - 9), Vector3.new(16, 0.8, 0.4), frame, M.Neon)
		block(kit, CF.new(k[1] - 7.6, k[2] - 5, k[3] - 9), Vector3.new(0.8, 10, 0.4), frame, M.Neon)
		block(kit, CF.new(k[1] + 7.6, k[2] - 5, k[3] - 9), Vector3.new(0.8, 10, 0.4), frame, M.Neon)
		block(kit, CF.new(k[1], k[2] - 5, k[3] - 9), Vector3.new(9, 3, 0.4), if frame == pink then cyan else pink, M.Neon)
	end
	-- light poles along the plaza
	for _, x in { -44, -30, 30, 44 } do
		local z = 24
		block(kit, CF.new(x, 7, z), Vector3.new(0.6, 14, 0.6), rgb(70, 74, 100), M.Metal)
		block(kit, CF.new(x, 14, z), Vector3.new(4, 0.6, 0.8), if x < 0 then pink else cyan, M.Neon)
		light(kit, Vector3.new(x, 12, z - 2), if x < 0 then pink else cyan, 28, 2)
	end
	light(kit, Vector3.new(-26, 6, -8), pink, 34, 1.4)
	light(kit, Vector3.new(26, 6, -8), cyan, 34, 1.4)
	return {
		Preset = {
			Lighting = {
				Brightness = 2.0,
				Ambient = Color3.new(0.2, 0.16, 0.34),
				OutdoorAmbient = Color3.new(0.38, 0.32, 0.6),
				ExposureCompensation = 0.1,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.8,
			},
			Atmosphere = {
				Density = 0.42,
				Offset = 0.2,
				Color = Color3.new(0.42, 0.14, 0.42),
				Decay = Color3.new(0.36, 0.12, 0.42),
				Glare = 0,
				Haze = 1.2,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.2, Saturation = 0.3, TintColor = Color3.new(1, 0.97, 1) },
			Bloom = { Intensity = 0.85, Size = 30, Threshold = 0.92 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(10, 6, 34),
				Mid = rgb(60, 14, 90),
				Horizon = rgb(255, 60, 160),
				HorizonAway = rgb(220, 50, 170),
				Sun = rgb(0, 0, 0),
				MidAngle = 12,
				CloudCover = 0,
			},
		},
		Stage = rgb(150, 156, 176),
		StageMaterial = M.Metal,
		Rim = cyan,
		Pedestal = rgb(60, 64, 90),
	}
end

-- D: glaciers, ice crystals and the northern lights over the snow
THEMES.FrostTitans = function(kit)
	local CF, rng = kit.CF, kit.Rng
	local snow, ice = rgb(150, 178, 214), rgb(150, 215, 255)
	block(kit, CF.new(0, -0.5, 150), Vector3.new(900, 1, 500), snow, M.Snow)
	-- the glacier mountains at night: deep blue peaks with snowy caps
	local capColor = rgb(214, 232, 250)
	for _, k in
		{
			{ -190, 360, 110, 110 },
			{ -80, 380, 120, 140 },
			{ 50, 370, 110, 128 },
			{ 170, 350, 100, 104 },
			{ -130, 280, 70, 66 },
			{ 120, 270, 66, 60 },
			{ -10, 300, 60, 52 },
		}
	do
		local tone = rng:range(0, 1)
		mountain(
			kit,
			k[1],
			k[2],
			k[3],
			k[4],
			rgb(70, 104, 160):Lerp(rgb(84, 118, 170), tone),
			rgb(40, 62, 110):Lerp(rgb(48, 72, 120), tone),
			capColor
		)
	end
	-- ice crystals near the stage (some glowing) and snow drifts
	for _, k in { { -44, 24 }, { 42, 26 }, { -66, 56 }, { 68, 58 }, { -32, 84 }, { 30, 100 } } do
		for j = 1, 4 do
			local h = rng:range(4, 12)
			block(
				kit,
				CF.new(k[1] + rng:range(-3, 3), h / 2 - 0.5, k[2] + rng:range(-3, 3))
					* CF.Angles(rng:range(-0.35, 0.35), rng:range(0, PI), rng:range(-0.35, 0.35)),
				Vector3.new(h * 0.32, h, h * 0.32),
				if j % 2 == 0 then rgb(40, 150, 200) else ice,
				if j % 2 == 0 then M.Neon else M.Glass
			)
		end
		peak(kit, Vector3.new(k[1] + 4, -2, k[2] + 4), rng:range(6, 10), rgb(180, 204, 234), M.Snow, rng:range(0, 1))
	end
	light(kit, Vector3.new(-30, 6, 18), rgb(90, 255, 200), 40, 1.4)
	light(kit, Vector3.new(30, 6, 18), rgb(110, 200, 255), 40, 1.4)
	-- the northern lights: tall glowing curtains along a wave across the sky
	for layer = 1, 2 do
		for i = 1, 44 do
			local t = (i - 22.5) / 22
			local x = t * 320 + layer * 7
			local z = 430 + layer * 30 + math.sin(t * 5 + layer) * 36
			local base = 66 + math.sin(t * 3 + 1 + layer) * 14 + layer * 10
			local h = 80 + math.cos(t * 4 + layer) * 24
			local color = if t < -0.3 then rgb(30, 200, 110) elseif t < 0.35 then rgb(24, 160, 190) else rgb(120, 60, 210)
			local curtain =
				block(kit, CF.new(x, base + h / 2, z) * CF.Angles(0, math.cos(t * 5) * 0.35, 0.05), Vector3.new(22, h, 1), color, M.Neon)
			curtain.Transparency = 0.72 + 0.1 * math.abs(math.sin(i * 1.3)) + (layer - 1) * 0.06
		end
	end
	stars(kit, 160, 460, -320, 320, 60, 320, { rgb(255, 255, 255), rgb(200, 240, 255) })
	ball(kit, Vector3.new(-150, 150, 440), 24, rgb(170, 200, 230), M.Neon)
	-- snowflakes in the air
	for _ = 1, 70 do
		ball(
			kit,
			Vector3.new(rng:range(-60, 60), rng:range(1, 30), rng:range(-10, 60)),
			rng:range(0.25, 0.5),
			rgb(255, 255, 255),
			M.SmoothPlastic
		)
	end
	return {
		Preset = {
			Lighting = {
				Brightness = 1.8,
				Ambient = Color3.new(0.16, 0.22, 0.34),
				OutdoorAmbient = Color3.new(0.32, 0.42, 0.6),
				ExposureCompensation = 0.0,
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.7,
			},
			Atmosphere = {
				Density = 0.4,
				Offset = 0.2,
				Color = Color3.new(0.16, 0.28, 0.42),
				Decay = Color3.new(0.12, 0.22, 0.36),
				Glare = 0,
				Haze = 1.2,
			},
			ColorCorrection = { Brightness = 0.0, Contrast = 0.2, Saturation = 0.24, TintColor = Color3.new(0.97, 0.99, 1) },
			Bloom = { Intensity = 0.8, Size = 30, Threshold = 0.92 },
			SunRays = { Intensity = 0, Spread = 0.6 },
			Sky = {
				Top = rgb(4, 8, 28),
				Mid = rgb(10, 30, 70),
				Horizon = rgb(30, 110, 120),
				HorizonAway = rgb(24, 90, 110),
				Sun = rgb(0, 0, 0),
				MidAngle = 14,
				CloudCover = 0,
			},
		},
		Stage = rgb(96, 140, 196),
		StageMaterial = M.Ice,
		Rim = rgb(60, 220, 255),
		Pedestal = rgb(70, 110, 170),
	}
end

---------------------------------------------------------------- the scene

-- Where the set's golems stand (feet CFrames, facing the camera a little inward).
function Preview.golemFrames(CF: any): { { Index: number, Feet: any, Size: number } }
	local out = {}
	local cam = Preview.Camera.Position
	for _, slot in Preview.Slots do
		local y = if slot[1] == 6 then Preview.PedestalTop else Preview.StageTop
		local pos = Vector3.new(slot[2], y, slot[3])
		local look = Vector3.new(cam.X + slot[2] * 0.3, y, cam.Z)
		table.insert(out, { Index = slot[1], Feet = CF.lookAt(pos, look), Size = slot[4] })
	end
	return out
end

-- Builds scene "limited_<themeId>"; returns the scene's Surface preset and camera.
function Preview.build(Loader: any, workspace: any, themeId: string): ({ [string]: any }, { [string]: any })
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local theme = LimitedGolems.Themes[themeId]
	assert(theme and THEMES[themeId], "unknown limited theme " .. tostring(themeId))

	local folder = Instance.new("Model")
	folder.Name = "Limited" .. themeId
	folder.Parent = workspace
	local kit: Kit = { Folder = folder, CF = CF, Rng = Rng.new(2026), Geo = Geo }
	local look = THEMES[themeId](kit)

	-- the stage: a wide platform with a glowing front rim, the Mythic's round pedestal
	local top = Preview.StageTop
	block(kit, CF.new(0, top / 2, 5), Vector3.new(84, top, 26), look.Stage, look.StageMaterial).CastShadow = false
	block(kit, CF.new(0, top + 0.02, -8.05), Vector3.new(84, 0.06, 0.16), look.Rim, M.Neon)
	local pedestal = Preview.PedestalTop - top
	disc(kit, CF.new(0, top + pedestal / 2, -3.5), pedestal, 11, look.Pedestal, look.StageMaterial)
	disc(kit, CF.new(0, Preview.PedestalTop - 0.25, -3.5), 0.12, 11.2, look.Rim, M.Neon)
	-- soft lights on the golems' faces
	light(kit, Vector3.new(0, 18, -22), rgb(255, 255, 255), 40, 0.7)
	light(kit, Vector3.new(-22, 12, -14), rgb(255, 255, 255), 34, 1.0)
	light(kit, Vector3.new(22, 12, -14), rgb(255, 255, 255), 34, 1.0)

	for _, g in Preview.golemFrames(CF) do
		local golem = theme.Golems[g.Index]
		GolemBuilder.build(golem.Id, g.Feet, { Size = g.Size }).Parent = folder
	end
	return look.Preset,
		{
			camera = { Preview.Camera.Position.X, Preview.Camera.Position.Y, Preview.Camera.Position.Z },
			target = { Preview.Camera.Target.X, Preview.Camera.Target.Y, Preview.Camera.Target.Z },
			fov = Preview.Camera.Fov,
		}
end

-- The set's data for the picture sheets (tools/preview/limited_sheet.mjs):
-- build/preview/limited_<themeId>_info.json.
function Preview.info(Loader: any, themeId: string): { [string]: any }
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local theme = LimitedGolems.Themes[themeId]
	local golems = {}
	for _, g in theme.Golems do
		local c = Rarity.ById[g.Rarity].Color
		table.insert(golems, {
			Id = g.Id,
			Name = g.Name,
			Rarity = g.Rarity,
			Odds = theme.Odds[g.Id],
			Color = string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)),
		})
	end
	return { Id = themeId, Letter = Preview.Letters[themeId], Title = theme.Title, Tagline = theme.Tagline, Golems = golems }
end

---------------------------------------------------------------- the overlay

-- A world point -> render pixels (the scene camera).
function Preview.project(CF: any, point: any): (number, number)
	local cam = CF.lookAt(Preview.Camera.Position, Preview.Camera.Target)
	local p = cam:PointToObjectSpace(point)
	local depth = -p.Z
	local tanY = math.tan(math.rad(Preview.Camera.Fov) / 2)
	local tanX = tanY * Preview.Width / Preview.Height
	return Preview.Width / 2 + p.X / depth / tanX * Preview.Width / 2, Preview.Height / 2 - p.Y / depth / tanY * Preview.Height / 2
end

-- The overlay "ui_limited_<themeId>": the exported ScreenGui list.
function Preview.ui(Loader: any, themeId: string): any
	local CF = Loader.CFrame
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local theme = LimitedGolems.Themes[themeId]

	local gui = Instance.new("ScreenGui")
	gui.Name = "LimitedConcept"
	gui.IgnoreGuiInset = true
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	-- the title, LIMITED EDITION over it, the tagline under it
	Pop.title(root, theme.Title, 104, theme.Backdrop.Title, {
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(1, 0, 0, 112),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Pop.tag(root, "LIMITED EDITION GOLEMS", "Red", Vector2.new(400, 46), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 44),
		Rotation = -3,
	})
	Pop.text(root, theme.Tagline, 34, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 172),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	-- the proposal letter (top left)
	local badge = Instance.new("Frame")
	badge.Name = "Letter"
	badge.Size = UDim2.fromOffset(96, 96)
	badge.Position = UDim2.fromOffset(28, 26)
	badge.Parent = root
	Pop.face(badge, "Yellow", 48)
	Pop.title(badge, Preview.Letters[themeId], 70, "White", {
		FontFace = PopTheme.Heavy,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- each golem's name, rarity and odds under its feet
	for _, g in Preview.golemFrames(CF) do
		local golem = theme.Golems[g.Index]
		local info = Rarity.ById[golem.Rarity]
		local mythic = golem.Rarity == "Mythic"
		local px, py = Preview.project(CF, g.Feet.Position + Vector3.new(0, 0, -2.4))
		local w, h = if mythic then 250 else 186, if mythic then 84 else 66
		local plate = Instance.new("Frame")
		plate.Name = "Odds" .. golem.Id
		plate.AnchorPoint = Vector2.new(0.5, 0)
		plate.Position = UDim2.fromOffset(math.floor(px + 0.5), math.floor(py + 6))
		plate.Size = UDim2.fromOffset(w, h)
		plate.Parent = root
		Pop.face(plate, { Top = rgb(40, 40, 52), Bottom = rgb(16, 16, 24), Edge = PopTheme.Outline }, 12, false)
		plate.BackgroundTransparency = 0.12
		Pop.text(plate, golem.Name, if mythic then 26 else 20, {
			Position = UDim2.fromOffset(0, if mythic then 6 else 5),
			Size = UDim2.new(1, 0, 0, if mythic then 30 else 24),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local percent = string.format("%g%%", theme.Odds[golem.Id] * 100)
		Pop.title(
			plate,
			string.upper(info.Name) .. "  " .. percent,
			if mythic then 32 else 24,
			{ info.Color:Lerp(Color3.new(1, 1, 1), 0.45), info.Color },
			{
				Position = UDim2.fromOffset(0, if mythic then 40 else 32),
				Size = UDim2.new(1, 0, 0, if mythic then 36 else 28),
				TextXAlignment = Enum.TextXAlignment.Center,
			}
		)
	end
	-- the banner's buy buttons
	local buy = Instance.new("Frame")
	buy.Name = "Buy"
	buy.BackgroundTransparency = 1
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -22)
	buy.Size = UDim2.fromOffset(4 * 190 + 3 * 18, 58)
	buy.Parent = root
	for i, count in { 1, 3, 10, 50 } do
		Pop.button(buy, "BUY " .. count, if i == 4 then "Yellow" else "Green", Vector2.new(190, 58), {
			Position = UDim2.fromOffset((i - 1) * 208, 0),
		})
	end
	return UiExport.export({ gui })
end

return Preview
