--[[
	The LIMITED EDITION banner picture (Config/LimitedGolems): the set's
	diorama, its 6 golems and the banner overlay, as the concept the owner
	picked (Dragonforge, 2026-10-20) and the look the shop's FEATURED banner
	is built after.

	  scene "limited_<SetId>" (Dragonforge) for tools/lune/export_scene.luau,
	  shots in tools/preview/limited_golems_shots.json (1600 x 900, the
	  scene's own camera):
	    the sky in the scene's own Surface preset (deep purple to crimson to
	    lava orange), a volcano with lava falls and an eruption, a cliff with
	    a lava waterfall into a glowing pool, a lava river, a huge moon with a
	    dragon flying across it and two more dragons far off, embers in the
	    air, dark rocks framing the corners, and a stage with the set's 6
	    golems built by the game's GolemBuilder (left to right: Epic,
	    Legendary | the MYTHIC on a pedestal, bigger | Epic, Rare, Rare).
	    The UI overlay "ui_limited_<SetId>" (the Pop kit): LIMITED EDITION,
	    the title, the tagline, the real end date (Current.EndsAt), each
	    golem's name, rarity and odds under its feet, and the four packs with
	    their Robux prices.
	  Everything at once (the picture, the golem and capsule icons, the
	  sheets in docs/screenshots/limited_golems/): bash tools/preview/limited_golems.sh
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
Preview.Camera = { Position = Vector3.new(-1.5, 8.8, -46), Target = Vector3.new(-1.5, 10.2, 0), Fov = 40 }
Preview.StageTop = 1
Preview.PedestalTop = 2.8
-- where the set's golems stand: { index in the set, x, z, size }; the Mythic on its pedestal
-- (the camera looks along +Z: world -X is the picture's right)
Preview.Slots = {
	{ 2, -30.5, 9, 2.2 },
	{ 1, -21, 4.5, 2.2 },
	{ 3, -11.4, 1, 2.2 },
	{ 6, 0, -3.5, 2.9 },
	{ 5, 12.6, 1, 2.2 },
	{ 4, 24.5, 4.5, 2.2 },
}
Preview.Months = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

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

-- a flat strip lying on the ground from a to b (rivers, cracks)
local function strip(kit: Kit, a: any, b: any, width: number, y: number, color: any, material: any?, transparency: number?): any
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = kit.CF.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	return block(kit, cf, Vector3.new(width, 0.08, length + width * 0.6), color, material, transparency)
end

-- a flat dragon silhouette in a frame `d` (x right, y up, facing the camera), `k` its size
local function dragon(kit: Kit, d: any, k: number, ink: any)
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

---------------------------------------------------------------- the sets

type Look = {
	Preset: { [string]: any }, -- the scene's Surface preset (sky, light, fog, colour)
	Stage: any, -- stage colour
	StageMaterial: any,
	Rim: any, -- the stage's glowing rim
	Pedestal: any,
}

local SETS: { [string]: (kit: Kit) -> Look } = {}

-- Dragonforge: a volcano with lava falls, a lava waterfall, dragons against a huge moon
SETS.Dragonforge = function(kit)
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
	dragon(kit, CF.new(mx + 8, my + 2, mz - 60) * CF.Angles(0, 0, 0.1), 1.25, ink)
	-- two more far off: one over the volcano's smoke, one low over the horizon
	dragon(kit, CF.new(46, 86, 250) * CF.Angles(0, PI, -0.15), 0.42, rgb(40, 12, 22))
	dragon(kit, CF.new(-20, 58, 300) * CF.Angles(0, 0, 0.2), 0.28, rgb(56, 18, 26))

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

-- Builds scene "limited_<setId>"; returns the scene's Surface preset and camera.
function Preview.build(Loader: any, workspace: any, setId: string): ({ [string]: any }, { [string]: any })
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local golems = LimitedGolems.golems(setId)
	assert(#golems == 6 and SETS[setId], "unknown limited set " .. tostring(setId))

	local folder = Instance.new("Model")
	folder.Name = "Limited" .. setId
	folder.Parent = workspace
	local kit: Kit = { Folder = folder, CF = CF, Rng = Rng.new(2026), Geo = Geo }
	local look = SETS[setId](kit)

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
		GolemBuilder.build(golems[g.Index].Id, g.Feet, { Size = g.Size }).Parent = folder
	end
	return look.Preset,
		{
			camera = { Preview.Camera.Position.X, Preview.Camera.Position.Y, Preview.Camera.Position.Z },
			target = { Preview.Camera.Target.X, Preview.Camera.Target.Y, Preview.Camera.Target.Z },
			fov = Preview.Camera.Fov,
		}
end

-- The set's data for the picture sheet (tools/preview/limited_sheet.mjs):
-- build/preview/limited_<setId>_info.json.
function Preview.info(Loader: any, setId: string): { [string]: any }
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local set = LimitedGolems.Sets[setId]
	local capsule = CapsuleConfig.ById[set.CapsuleId]
	local golems = {}
	for _, g in LimitedGolems.golems(setId) do
		local c = Rarity.ById[g.Rarity].Color
		table.insert(golems, {
			Id = g.Id,
			Name = g.Name,
			Rarity = g.Rarity,
			Odds = capsule.Odds[g.Id],
			Bonus = GolemConfig.describe(g.Id),
			Color = string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)),
		})
	end
	return { Id = setId, Title = set.Title, Tagline = set.Tagline, CapsuleId = set.CapsuleId, Golems = golems }
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

-- The overlay "ui_limited_<setId>": the exported ScreenGui list.
function Preview.ui(Loader: any, setId: string): any
	local CF = Loader.CFrame
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local set = LimitedGolems.Sets[setId]
	local capsule = CapsuleConfig.ById[set.CapsuleId]
	local golems = LimitedGolems.golems(setId)

	local gui = Instance.new("ScreenGui")
	gui.Name = "LimitedBanner"
	gui.IgnoreGuiInset = true
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	-- LIMITED EDITION over the title, the tagline under it, the real end date
	Pop.title(root, set.Title, 108, set.Backdrop.Title, {
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 116),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Pop.tag(root, "LIMITED EDITION GOLEMS", "Red", Vector2.new(400, 46), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 44),
		Rotation = -3,
	})
	Pop.text(root, set.Tagline, 34, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 174),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local ends = os.date("!*t", LimitedGolems.Current.EndsAt) :: any
	Pop.tag(root, `ENDS {Preview.Months[ends.month]} {ends.day}`, "Night", Vector2.new(210, 44), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 28),
	})

	-- each golem's name, rarity and odds under its feet
	for _, g in Preview.golemFrames(CF) do
		local golem = golems[g.Index]
		local info = Rarity.ById[golem.Rarity]
		local mythic = golem.Rarity == "Mythic"
		local px, py = Preview.project(CF, g.Feet.Position + Vector3.new(0, 0, -2.4))
		local w, h = if mythic then 240 else 180, if mythic then 76 else 58
		local plate = Instance.new("Frame")
		plate.Name = "Odds" .. golem.Id
		plate.AnchorPoint = Vector2.new(0.5, 0)
		plate.Position = UDim2.fromOffset(math.floor(px + 0.5), math.floor(py + 6))
		plate.Size = UDim2.fromOffset(w, h)
		plate.Parent = root
		Pop.face(plate, { Top = rgb(40, 40, 52), Bottom = rgb(16, 16, 24), Edge = PopTheme.Outline }, 12, false)
		plate.BackgroundTransparency = 0.12
		Pop.text(plate, golem.Name, if mythic then 24 else 19, {
			Position = UDim2.fromOffset(0, if mythic then 5 else 4),
			Size = UDim2.new(1, 0, 0, if mythic then 28 else 22),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local percent = string.format("%g%%", capsule.Odds[golem.Id] * 100)
		Pop.title(
			plate,
			string.upper(info.Name) .. "  " .. percent,
			if mythic then 30 else 22,
			{ info.Color:Lerp(Color3.new(1, 1, 1), 0.45), info.Color },
			{
				Position = UDim2.fromOffset(0, if mythic then 36 else 28),
				Size = UDim2.new(1, 0, 0, if mythic then 34 else 26),
				TextXAlignment = Enum.TextXAlignment.Center,
			}
		)
	end

	-- the four packs: how many golems, the Robux price
	local packs = Instance.new("Frame")
	packs.Name = "Packs"
	packs.BackgroundTransparency = 1
	packs.AnchorPoint = Vector2.new(0.5, 1)
	packs.Position = UDim2.new(0.5, 0, 1, -10)
	packs.Size = UDim2.fromOffset(4 * 170 + 3 * 22, 84)
	packs.Parent = root
	for i, count in { 1, 3, 10, 50 } do
		local product = MonetizationConfig.get(CapsuleConfig.product(set.CapsuleId, count) :: string)
		local x = (i - 1) * 192
		Pop.text(packs, if count == 1 then "1 GOLEM" else `{count} GOLEMS`, 20, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(170, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Pop.price(packs, product.Robux, Vector2.new(170, 54), {
			Position = UDim2.fromOffset(x, 30),
		})
	end
	return UiExport.export({ gui })
end

return Preview
