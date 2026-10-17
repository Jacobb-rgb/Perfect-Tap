--[[
	Blaster shop proposals (owner review 2026-10): a shop built from Kenney kit
	pieces (Space Station Kit walls, doors, screens and consoles; Mini Dungeon
	stone walls, columns, banners and barrels; rebuilt from parts by
	tools/lune/lib/kenney_kit.luau), a shopkeeper you press E at, and the ten
	weapon cases (Kenney.crate) on display behind him.

	  A  Space Armory  a two-storey space station building with a glass shop
	                   front, a neon sign, searchlights and a blaster hologram
	                   on the roof; inside a counter, the keeper, a case wall
	  B  Forge Vault   a Mini Dungeon stone vault with columns, fire bowls,
	                   wooden beams and ore banners; the cases on stone steps
	                   behind the keeper, a glowing lava channel in front
	  C  Neon Stall    an open market stall (metal frames, a striped awning)
	                   whose case rack is seen from the plaza

	Frames, awnings and the keeper are built by hand: a single-projection
	rebuild cannot do open frames, slanted awnings or characters. Scene
	"blaster_shop", shots in tools/preview/blaster_shop_shots.json.
	Prototype only (not in the game).
]]

local roblox = require("@lune/roblox") :: any
local Concepts = require("./blaster_concepts")
local Kit = require("./kenney_kit")
local Kenney = require("./blaster_kenney")

local Shop = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METALM = Enum.Material.Metal

local CF: any
local L: any -- Loader

local DARK = C3.fromRGB(30, 31, 38)
local STEEL = C3.fromRGB(70, 74, 90)

-- Kenney's space station orange
local function isOrange(c: any): boolean
	return c.R > 0.85 and c.G > 0.5 and c.G < 0.85 and c.B < 0.45
end

local function label(K: any, cf: any, size: any, text: string, plate: any, ink: any)
	local p = K.boxCF(cf, size, plate)
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z
	gui.Parent = p
	local t = roblox.Instance.new("TextLabel")
	t.Text = text
	t.TextColor3 = ink
	t.FontFace = roblox.Font.fromEnum(Enum.Font.FredokaOne)
	t.Parent = gui
	return p
end

local function light(K: any, pos: any, color: any, range: number, brightness: number)
	local holder = K.part("Part", CF.new(pos), V3.new(0.1, 0.1, 0.1), color)
	holder.Transparency = 1
	local l = roblox.Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = holder
end

local function neon(K: any, cf: any, size: any, color: any, transparency: number?)
	local p = K.boxCF(cf, size, color, NEON)
	if transparency then
		p.Transparency = transparency
	end
	return p
end

-- Moves every part of `model` (built around its own origin) by cf, scaled by s.
local function place(model: any, cf: any, s: number, parent: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * s
			d.CFrame = cf * CF.new(d.CFrame.Position * s) * d.CFrame.Rotation
		end
	end
	model.Parent = parent
	return model
end

-- A weapon case of a level, its bottom at cf, scaled by s (its long side along cf's Z).
local function crate(parent: any, level: number, cf: any, s: number)
	local base, lid = Kenney.crate(L, level, Kenney.Lineup[level])
	local holder = roblox.Instance.new("Model")
	holder.Name = "Case" .. level
	base.Parent = holder
	lid.Parent = holder
	return place(holder, cf * CF.new(0, 0.14 * s, 0), s, parent)
end

local function oreGlow(level: number)
	local BlasterBuilder = L.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	return BlasterBuilder.look(level, Kenney.Lineup[level])
end

-- A case on a pedestal with a light beam and its level plate. cf = the pedestal's bottom center (front +Z).
local DISPLAY_TILT = 0.34 -- the cases lean forward toward the visitor

local function display(K: any, parent: any, level: number, cf: any, s: number)
	local look = oreGlow(level)
	local w, d = 7.6 * s, 4.4 * s
	K.boxCF(cf * CF.new(0, 0.35, 0), V3.new(w, 0.7, d), DARK)
	neon(K, cf * CF.new(0, 0.72, 0), V3.new(w + 0.1, 0.06, d + 0.1), look.Glow)
	local rise = d * math.tan(DISPLAY_TILT)
	K.part("WedgePart", cf * CF.new(0, 0.7 + rise / 2, 0) * CF.Angles(0, math.pi, 0), V3.new(w, rise, d), C3.fromRGB(46, 42, 54))
	local top = cf * CF.new(0, 0.7 + rise / 2, 0) * CF.Angles(DISPLAY_TILT, 0, 0)
	K.boxCF(top * CF.new(0, 0.05, 0), V3.new(w - 0.2, 0.1, d / math.cos(DISPLAY_TILT) - 0.2), C3.fromRGB(70, 30, 34))
	K.boxCF(
		top * CF.new(0, 0.3, d / 2 / math.cos(DISPLAY_TILT) - 0.15),
		V3.new(w - 0.2, 0.5, 0.25),
		C3.fromRGB(196, 152, 66),
		Enum.Material.Metal
	)
	crate(parent, level, top * CF.new(0, 0.1, -0.1) * CF.Angles(0, -math.pi / 2, 0), s)
	label(K, cf * CF.new(0, 0.35, d / 2 + 0.03), V3.new(1.7, 0.5, 0.04), "LV " .. level, DARK, look.Glow)
	light(K, (cf * CF.new(0, 3, 2)).Position, look.Glow, 7, 0.5)
end

--[[
	The Blastsmith (shopkeeper): a big blocky mechanic with arms crossed, goggles
	with glowing lenses, a cap, a beard, a tech pack with a glowing core and a
	blaster on his back. feet = CFrame at the feet, facing +Z; s = size (1: ~5.3
	studs). colors = { vest, accent, lens }.
]]
local function blastsmith(K: any, parent: any, feet: any, s: number, colors: any)
	local SKIN = C3.fromRGB(236, 190, 150)
	local PANTS = C3.fromRGB(46, 50, 64)
	local SHIRT = C3.fromRGB(36, 38, 48)
	local LEATHER = C3.fromRGB(72, 46, 32)
	local HAIR = C3.fromRGB(96, 58, 34)
	local function box(x: number, y: number, z: number, sx: number, sy: number, sz: number, color: any, rot: any?, mat: any?)
		return K.boxCF(feet * CF.new(x * s, y * s, z * s) * (rot or CF.identity), V3.new(sx * s, sy * s, sz * s), color, mat)
	end
	local function rbox(x: number, y: number, z: number, sx: number, sy: number, sz: number, r: number, color: any)
		-- rounded along Z (front view soft corners) via the kit's rounded box turned a quarter
		K.rboxCF(feet * CF.new(x * s, y * s, z * s) * CF.Angles(0, math.pi / 2, 0), V3.new(sz * s, sy * s, sx * s), r * s, color)
	end
	-- boots and legs
	for _, sx in { -1, 1 } do
		box(sx * 0.52, 0.3, 0.12, 1.05, 0.6, 1.3, DARK)
		box(sx * 0.52, 0.62, 0.12, 1.07, 0.08, 1.32, colors.accent, nil, NEON)
		box(sx * 0.52, 1.45, 0, 0.95, 1.6, 0.95, PANTS)
		box(sx * 0.52, 1.35, 0.5, 0.8, 0.5, 0.18, STEEL) -- knee pads
	end
	-- belt with a glowing buckle, torso and vest
	box(0, 2.35, 0, 2.12, 0.34, 1.12, LEATHER)
	box(0, 2.35, 0.57, 0.5, 0.3, 0.08, colors.lens, nil, NEON)
	box(0, 3.4, 0, 2.0, 1.9, 1.0, SHIRT)
	box(0, 3.45, 0, 2.1, 1.65, 1.08, colors.vest)
	box(0, 3.45, 0.55, 0.16, 1.5, 0.04, colors.accent, nil, NEON) -- the vest's zip
	box(0, 3.95, 0.56, 0.42, 0.42, 0.04, colors.lens, CF.Angles(0, 0, math.pi / 4), NEON) -- chest emblem
	-- shoulder pads, upper arms down, forearms crossed over the chest, big gloves
	for _, sx in { -1, 1 } do
		rbox(sx * 1.45, 4.2, 0, 1.0, 0.6, 1.2, 0.22, STEEL)
		box(sx * 1.45, 4.21, 0, 1.02, 0.08, 1.22, colors.accent, nil, NEON)
		box(sx * 1.45, 3.45, 0, 0.92, 1.2, 0.92, SHIRT)
	end
	box(0, 2.95, 0.72, 2.6, 0.78, 0.82, SHIRT, CF.Angles(0, 0, 0.08))
	box(0, 3.25, 0.86, 2.5, 0.72, 0.74, PANTS, CF.Angles(0, 0, -0.08))
	for _, sx in { -1, 1 } do
		box(sx * 1.3, 3.1 + sx * 0.15, 0.92, 0.72, 0.82, 0.86, DARK)
	end
	-- neck, head, beard
	box(0, 4.55, 0, 0.72, 0.3, 0.72, SKIN)
	box(0, 5.3, 0, 1.36, 1.36, 1.36, SKIN)
	box(0, 4.85, 0.64, 1.18, 0.6, 0.2, HAIR)
	box(0, 5.05, 0.72, 0.9, 0.14, 0.08, HAIR)
	box(0, 4.82, 0.7, 0.3, 0.1, 0.06, C3.fromRGB(60, 34, 26)) -- mouth
	-- goggles with glowing lenses
	box(0, 5.42, 0, 1.42, 0.3, 1.42, DARK)
	for _, sx in { -1, 1 } do
		box(sx * 0.32, 5.42, 0.72, 0.46, 0.3, 0.06, colors.lens, nil, NEON)
	end
	-- a cap turned backwards and a headset antenna
	box(0, 6.1, -0.03, 1.42, 0.42, 1.42, colors.vest)
	box(0, 5.98, -0.95, 1.0, 0.1, 0.55, colors.vest)
	box(0, 6.32, 0, 0.3, 0.06, 0.3, colors.accent, nil, NEON)
	box(0.76, 5.3, 0, 0.12, 0.5, 0.5, DARK)
	box(0.82, 6.1, 0, 0.06, 1.1, 0.06, STEEL)
	box(0.82, 6.68, 0, 0.16, 0.16, 0.16, colors.lens, nil, NEON)
	-- the tech pack with a glowing core and two exhausts, a blaster across the back
	box(0, 3.55, -0.92, 1.7, 1.9, 0.8, STEEL)
	K.cylCF(feet * CF.new(0, 3.65 * s, -1.34 * s) * CF.Angles(0, math.pi / 2, 0), 0.12 * s, 0.9 * s, colors.lens, NEON)
	for _, sx in { -1, 1 } do
		K.cylCF(feet * CF.new(sx * 0.6 * s, 2.55 * s, -1.0 * s) * CF.Angles(0, 0, math.pi / 2), 0.5 * s, 0.38 * s, DARK)
	end
	local gun = Kenney.gun(L, 9, "Stormcore")
	Concepts.present(
		gun,
		feet * CF.new(0.2 * s, 4.1 * s, -1.55 * s) * CF.Angles(0, 0, -0.75) * CF.Angles(0, math.pi / 2, 0),
		0.62 * s,
		parent
	)
end

-- A counter screen: a dark frame on a stand with a glowing display (facing +Z).
local function monitor(K: any, cf: any, color: any)
	K.boxCF(cf * CF.new(0, 0.5, 0), V3.new(0.4, 1, 0.4), DARK)
	K.boxCF(cf * CF.new(0, 1.9, 0) * CF.Angles(-0.15, 0, 0), V3.new(3.4, 2.1, 0.3), DARK)
	neon(K, cf * CF.new(0, 1.9, 0) * CF.Angles(-0.15, 0, 0) * CF.new(0, 0, 0.16), V3.new(3.0, 1.75, 0.04), color, 0.25)
end

-- A blaster lying on the counter for show.
local function counterBlaster(parent: any, cf: any)
	local gun = Kenney.gun(L, 7, "Sapphire")
	Concepts.present(gun, cf * CF.Angles(0, -1.3, 0) * CF.Angles(0, 0, math.pi / 2) * CF.Angles(0, 0, -math.pi / 2), 0.9, parent)
end

-- The "[E] BLASTER SHOP" prompt over the keeper (a ProximityPrompt in the game).
local function prompt(K: any, at: any)
	local key = label(K, CF.new(at + V3.new(-2.5, 0, 0)), V3.new(1.4, 1.4, 0.12), "E", C3.fromRGB(245, 245, 250), C3.fromRGB(30, 30, 40))
	local text =
		label(K, CF.new(at + V3.new(0.95, 0, 0)), V3.new(5.2, 1.4, 0.12), "BLASTER SHOP", C3.fromRGB(22, 22, 32), C3.fromRGB(255, 255, 255))
	key.Name = "FakePrompt" -- the Studio test uses a real ProximityPrompt instead
	text.Name = "FakePrompt"
end

-- A metal frame post with a neon line (stalls, shop fronts).
local function post(K: any, cf: any, h: number, accent: any)
	K.boxCF(cf * CF.new(0, h / 2, 0), V3.new(1.2, h, 1.2), STEEL)
	neon(K, cf * CF.new(0, h / 2, 0.62), V3.new(0.16, h - 1, 0.06), accent)
	K.boxCF(cf * CF.new(0, 0.3, 0), V3.new(1.6, 0.6, 1.6), DARK)
end

---------------------------------------------------------------- A: Space Armory

local function armory(K: any, parent: any, origin: any)
	local S = 12 -- studs per Kenney meter for the building
	local ACCENT = C3.fromRGB(255, 150, 40)
	local MATTE_ORANGE = C3.fromRGB(226, 128, 46)
	local function tone(c: any): any
		if isOrange(c) then
			return MATTE_ORANGE
		end
		return c:Lerp(C3.fromRGB(44, 48, 66), 0.45) -- Kenney's lavender steel, darker, so the neon reads
	end
	local function wall(key: string, cf: any)
		Kit.piece(L, parent, key, origin * cf, S, function(_, c)
			return tone(c)
		end)
	end
	local W, D = 5, 4
	local halfW, halfD = W * S / 2, D * S / 2
	-- floor with a neon grid, a front step
	K.boxCF(origin * CF.new(0, -0.5, 0), V3.new(W * S + 4, 1, D * S + 4), C3.fromRGB(40, 42, 54))
	K.boxCF(origin * CF.new(0, 0.05, 0), V3.new(W * S - 4, 0.1, D * S - 4), C3.fromRGB(24, 25, 32))
	for i = -2, 2 do
		neon(K, origin * CF.new(i * 11, 0.12, 0), V3.new(0.08, 0.04, D * S - 6), ACCENT, 0.5)
	end
	K.boxCF(origin * CF.new(0, 0.3, halfD + 4), V3.new(26, 0.6, 6), C3.fromRGB(50, 52, 66))
	neon(K, origin * CF.new(0, 0.62, halfD + 6.9), V3.new(26, 0.06, 0.12), ACCENT)
	-- ground floor front: a glass shop front around the space station door
	for i = 1, W do
		local x = -halfW + (i - 0.5) * S
		if i == 3 then
			wall("space/wall-door-wide", CF.new(x, 0, halfD))
		else
			K.boxCF(origin * CF.new(x, 0.6, halfD), V3.new(S, 1.2, 3.6), STEEL)
			K.boxCF(origin * CF.new(x, S - 0.6, halfD), V3.new(S, 1.2, 3.6), STEEL)
			local glass = K.boxCF(origin * CF.new(x, S / 2, halfD), V3.new(S - 0.6, S - 2.4, 0.3), C3.fromRGB(150, 200, 240), GLASS)
			glass.Transparency = 0.72
			K.boxCF(origin * CF.new(x - S / 2 + 0.3, S / 2, halfD), V3.new(0.6, S, 3.6), STEEL)
			neon(K, origin * CF.new(x, 1.25, halfD + 1.82), V3.new(S - 0.6, 0.1, 0.06), ACCENT)
			neon(K, origin * CF.new(x, S - 1.25, halfD + 1.82), V3.new(S - 0.6, 0.1, 0.06), ACCENT)
		end
		wall("space/wall-banner", CF.new(x, S, halfD))
		wall("space/wall", CF.new(x, 0, -halfD))
		wall("space/wall", CF.new(x, S, -halfD))
	end
	K.boxCF(origin * CF.new(halfW - 0.3, S / 2, halfD), V3.new(0.6, S, 3.6), STEEL)
	for j = 1, D do
		local z = -halfD + (j - 0.5) * S
		for _, sx in { -1, 1 } do
			wall(if j == 2 or j == 3 then "space/wall-window" else "space/wall", CF.new(sx * halfW, 0, z) * CF.Angles(0, math.pi / 2, 0))
			wall("space/wall-banner", CF.new(sx * halfW, S, z) * CF.Angles(0, math.pi / 2, 0))
		end
	end
	-- corner towers with neon bands
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K.boxCF(origin * CF.new(sx * halfW, S + 1.5, sz * halfD), V3.new(4.6, 2 * S + 3, 4.6), C3.fromRGB(60, 64, 82))
			for _, y in { 4, S, 2 * S - 2 } do
				neon(K, origin * CF.new(sx * halfW, y, sz * halfD), V3.new(4.8, 0.35, 4.8), ACCENT)
			end
			K.boxCF(origin * CF.new(sx * halfW, 2 * S + 3.3, sz * halfD), V3.new(5.4, 0.6, 5.4), C3.fromRGB(40, 42, 54))
		end
	end
	-- roof, the sign with neon frame, searchlight beams, the hologram
	K.boxCF(origin * CF.new(0, 2 * S + 0.5, 0), V3.new(W * S + 2, 1, D * S + 2), C3.fromRGB(56, 60, 76))
	neon(K, origin * CF.new(0, 2 * S + 1.05, halfD + 0.9), V3.new(W * S + 2.2, 0.25, 0.25), ACCENT)
	label(
		K,
		origin * CF.new(0, 2 * S + 5.4, halfD + 0.5),
		V3.new(32, 6.4, 0.6),
		"BLASTER SHOP",
		C3.fromRGB(20, 20, 30),
		C3.fromRGB(255, 196, 110)
	)
	for _, y in { 2 * S + 1.95, 2 * S + 8.85 } do
		neon(K, origin * CF.new(0, y, halfD + 0.55), V3.new(33, 0.3, 0.7), ACCENT)
	end
	for _, sx in { -1, 1 } do
		neon(K, origin * CF.new(sx * 16.4, 2 * S + 5.4, halfD + 0.55), V3.new(0.3, 7.2, 0.7), ACCENT)
		local base = origin * CF.new(sx * (halfW - 3), 2 * S + 3.6, -halfD + 4)
		K.cylCF(base * CF.Angles(0, 0, math.pi / 2), 1.4, 3, DARK)
		neon(
			K,
			base * CF.Angles(0, 0, sx * 0.32) * CF.Angles(-0.25, 0, 0) * CF.new(0, 30, 0),
			V3.new(2.4, 60, 2.4),
			C3.fromRGB(255, 220, 170),
			0.88
		)
	end
	local glow = oreGlow(10).Glow
	K.cylCF(origin * CF.new(0, 2 * S + 1.3, -2) * CF.Angles(0, 0, math.pi / 2), 0.7, 7, DARK)
	K.cylCF(origin * CF.new(0, 2 * S + 1.7, -2) * CF.Angles(0, 0, math.pi / 2), 0.12, 6, glow, NEON)
	local beam = K.cylCF(origin * CF.new(0, 2 * S + 8.5, -2) * CF.Angles(0, 0, math.pi / 2), 13.6, 5.6, glow, NEON)
	beam.Transparency = 0.9
	local holo = Kenney.gun(L, 10, "Heartstone")
	Concepts.present(holo, origin * CF.new(0, 2 * S + 18, -2) * CF.Angles(0, 1.2, 0) * CF.Angles(0.12, 0, 0), 3.4, parent)
	-- inside: a dark counter with a glowing edge and two space consoles, the keeper, the prompt
	K.boxCF(origin * CF.new(0, 1.9, 3), V3.new(18, 3.8, 4.2), C3.fromRGB(44, 46, 60))
	K.boxCF(origin * CF.new(0, 3.95, 3), V3.new(18.6, 0.3, 4.8), DARK)
	neon(K, origin * CF.new(0, 3.75, 5.45), V3.new(18.6, 0.12, 0.08), ACCENT)
	for _, x in { -6.5, 6.5 } do
		monitor(K, origin * CF.new(x, 4.1, 2.4), C3.fromRGB(110, 200, 255))
	end
	counterBlaster(parent, origin * CF.new(0, 4.7, 3.6))
	blastsmith(
		K,
		parent,
		origin * CF.new(0, 0.1, -2.5),
		1.25,
		{ vest = C3.fromRGB(196, 92, 36), accent = ACCENT, lens = C3.fromRGB(110, 230, 255) }
	)
	prompt(K, (origin * CF.new(0, 10.6, -2.5)).Position)
	-- the case wall: two shelves along the back wall, two wide screens above them
	for tier = 0, 1 do
		local y = 0.1 + tier * 6.6
		K.boxCF(origin * CF.new(0, y + 0.25, -halfD + 6), V3.new(W * S - 6, 0.5, 7.4), C3.fromRGB(46, 48, 62))
		neon(K, origin * CF.new(0, y + 0.52, -halfD + 9.7), V3.new(W * S - 6, 0.08, 0.12), ACCENT)
		for i = 1, 5 do
			display(K, parent, tier * 5 + i, origin * CF.new(-21.6 + (i - 1) * 10.8, y + 0.5, -halfD + 6), 0.78)
		end
	end
	for _, x in { -14, 14 } do
		Kit.piece(L, parent, "space/display-wall-wide", origin * CF.new(x, 15.4, -halfD + 2.3), 14, function(_, c)
			return tone(c)
		end)
	end
	light(K, (origin * CF.new(0, 18, 4)).Position, C3.fromRGB(255, 236, 214), 40, 1.2)
	light(K, (origin * CF.new(0, 9, 8)).Position, C3.fromRGB(255, 210, 160), 20, 1.0)
end

---------------------------------------------------------------- B: Forge Vault

local function lcg(seed: number): () -> number
	local state = (seed * 7919 + 12345) % 2147483647
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

--[[
	A detailed stone wall: a dark mortar core with staggered bricks of varied
	stone tones (some mossy) on its faces, a base course of big blocks, a
	middle string course, a cornice with dentils and moss drips, and on the
	outer face pilasters (fire sconces on every other one) with glowing rune
	slits between them. cf = the wall's bottom center; its length runs along
	local X and the outer face looks along local +Z.
]]
local function stoneWall(K: any, cf: any, length: number, height: number, thick: number, opts: any)
	local rand = lcg(opts.seed or 1)
	local half = length / 2
	local STONE = C3.fromRGB(98, 92, 110)
	local LIGHT = C3.fromRGB(122, 116, 136)
	local DARKS = C3.fromRGB(72, 68, 84)
	local MOSS = C3.fromRGB(86, 122, 78)
	local FIRE = C3.fromRGB(255, 140, 50)
	local function box(x: number, y: number, z: number, sx: number, sy: number, sz: number, color: any, mat: any?)
		return K.boxCF(cf * CF.new(x, y, z), V3.new(sx, sy, sz), color, mat)
	end
	local function tone(): any
		local t = rand()
		if t < 0.07 then
			return MOSS:Lerp(STONE, rand() * 0.4)
		elseif t < 0.11 then
			return C3.fromRGB(62, 58, 72)
		end
		return if rand() < 0.5 then STONE:Lerp(LIGHT, rand() * 0.8) else STONE:Lerp(DARKS, rand() * 0.8)
	end
	box(0, height / 2, 0, length, height, thick, C3.fromRGB(42, 38, 50)) -- the mortar core
	local faces = if opts.inner then { 1, -1 } else { 1 }
	for _, f in faces do
		local zf = f * thick / 2
		-- base course: big dark blocks
		local x = -half
		while x < half - 0.2 do
			local len = math.min(half - x, 3.6 + rand() * 2.2)
			box(x + len / 2, 1.1, zf + f * 0.3, len - 0.22, 2.0, 0.9, DARKS:Lerp(STONE, rand() * 0.4))
			x += len
		end
		-- staggered brick rows
		local rows, y0, y1 = 13, 2.2, height - 1.4
		local bh = (y1 - y0) / rows
		for r = 0, rows - 1 do
			local y = y0 + (r + 0.5) * bh
			x = -half - (if r % 2 == 1 then 1.6 else 0)
			while x < half do
				local len = 2.6 + rand() * 1.6
				local a, b = math.max(x, -half), math.min(x + len, half)
				if b - a > 0.6 then
					local t = tone()
					if f < 0 and opts.innerDark then
						t = t:Lerp(C3.new(0, 0, 0), opts.innerDark)
					end
					box((a + b) / 2, y, zf + f * 0.12, b - a - 0.16, bh - 0.16, 0.5, t)
				end
				x += len
			end
		end
		-- string course, cornice with dentils
		box(0, y0 + bh * 6.5, zf + f * 0.3, length, 0.45, 0.8, LIGHT:Lerp(STONE, 0.4))
		box(0, height - 0.45, f * 0.4, length + 1.0, 0.9, thick + 1.4, C3.fromRGB(88, 82, 100))
		local n = math.floor(length / 1.4)
		for i = 0, n - 1 do
			box(-half + 0.7 + i * 1.4, height - 1.15, zf + f * 0.55, 0.6, 0.5, 0.6, C3.fromRGB(80, 76, 94))
		end
	end
	box(0, height + 0.25, 0, length + 0.6, 0.5, thick + 0.8, C3.fromRGB(74, 70, 86))
	-- outer face: pilasters, sconces, rune slits, moss drips
	local zo = thick / 2
	local bays = math.max(1, math.floor(length / 10 + 0.5))
	local bay = length / bays
	for k = 0, bays do
		local x = -half + k * bay
		box(x, height / 2, zo + 0.6, 1.8, height - 1, 1.2, C3.fromRGB(106, 100, 120))
		box(x, 1.2, zo + 0.8, 2.6, 2.4, 1.8, DARKS)
		box(x, height - 1.6, zo + 0.8, 2.6, 1.0, 1.8, C3.fromRGB(112, 106, 126))
		if opts.sconces and k % 2 == 1 then
			box(x, 11.8, zo + 1.6, 0.4, 0.4, 1.4, C3.fromRGB(40, 38, 44))
			local flame = K.part("Part", cf * CF.new(x, 12.6, zo + 2.2), V3.new(1.1, 1.3, 1.1), FIRE, NEON)
			flame.Shape = Enum.PartType.Ball
		end
		if opts.slits and k < bays then
			local xs = x + bay / 2
			box(xs, 14.6, zo + 0.35, 1.9, 6.4, 0.7, C3.fromRGB(70, 66, 80))
			box(xs, 14.6, zo + 0.42, 0.55, 5.2, 0.7, FIRE, NEON)
			box(xs, 18.1, zo + 0.5, 2.6, 0.6, 0.9, C3.fromRGB(112, 106, 126))
		end
	end
	for _ = 1, math.floor(length / 6) do
		local x = -half + rand() * length
		local len = 1 + rand() * 3
		box(x, height - 1.6 - len / 2, zo + 0.42, 0.5, len, 0.25, MOSS)
	end
end

-- (defined with the vault's other decorations below)
local bigFern: (K: any, base: any, size: number, seed: number) -> ()

--[[
	A big jungle tree in the blocky style of Minecraft's jungle trees: a thick
	trunk of stacked bark blocks with grooves and flared roots, side branches
	with leaf clumps, a wide layered canopy of leaf voxels in two greens,
	hanging vines and a few cocoa pods. base = the trunk's foot.
]]
local function jungleTree(K: any, base: any, h: number, R: number, seed: number)
	local rand = lcg(seed)
	local BARK = C3.fromRGB(104, 76, 50)
	local BARK_D = C3.fromRGB(74, 52, 36)
	local LEAF = C3.fromRGB(48, 124, 42)
	local LEAF_L = C3.fromRGB(78, 158, 56)
	local VINE = C3.fromRGB(38, 102, 34)
	local T = 5.6
	local function at(x: number, y: number, z: number): any
		return CF.new(base + V3.new(x, y, z))
	end
	-- flared roots, the trunk in bark blocks, vertical grooves
	for i = 0, 3 do
		local a = i * math.pi / 2 + 0.4
		local d = V3.new(math.cos(a), 0, math.sin(a))
		K.boxCF(
			CF.new(base + d * (T / 2 + 0.9) + V3.new(0, 1.6, 0)) * CF.Angles(0, -a, 0) * CF.Angles(0, 0, 0.35),
			V3.new(3.4, 3.6, 2.4),
			BARK_D
		)
	end
	local y = 0
	while y < h do
		local seg = math.min(4, h - y)
		K.boxCF(at(0, y + seg / 2, 0), V3.new(T, seg, T), if math.floor(y / 4) % 2 == 0 then BARK else BARK:Lerp(BARK_D, 0.35))
		y += seg
	end
	for _, f in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		for _, o in { -1.3, 1.1 } do
			local x = f[1] * (T / 2 + 0.05) + (if f[1] == 0 then o else 0)
			local z = f[2] * (T / 2 + 0.05) + (if f[2] == 0 then o else 0)
			K.boxCF(at(x, h * 0.48, z), V3.new(if f[1] == 0 then 0.5 else 0.3, h * 0.9, if f[2] == 0 then 0.5 else 0.3), BARK_D)
		end
	end
	-- leaf voxels: one layer of the canopy (rows merged into long blocks)
	local u = 2.6
	local function layer(cy: number, r: number, holes: number)
		local n = math.ceil(r / u)
		for gz = -n, n do
			local run: number? = nil
			local runTone = LEAF
			local function flush(gx: number)
				if run then
					local x0, x1 = run * u, (gx - 1) * u
					K.boxCF(at((x0 + x1) / 2, cy, gz * u), V3.new(x1 - x0 + u, u, u), runTone)
					run = nil
				end
			end
			for gx = -n, n + 1 do
				local d = math.sqrt(gx * gx + gz * gz) * u
				local inside = gx <= n and d <= r + (rand() - 0.5) * u * 1.4 and rand() > holes
				local tone = if rand() < 0.35 then LEAF_L else LEAF
				if inside and run and tone ~= runTone and rand() < 0.5 then
					flush(gx)
				end
				if inside and not run then
					run = gx
					runTone = tone
				elseif not inside then
					flush(gx)
				end
			end
		end
	end
	layer(h - 0.5, R, 0.06)
	layer(h + u - 0.5, R * 0.86, 0.04)
	layer(h + 2 * u - 0.5, R * 0.62, 0.02)
	layer(h + 3 * u - 0.5, R * 0.3, 0)
	-- side branches with leaf clumps
	for i = 0, 2 do
		local a = i * 2.1 + rand()
		local d = V3.new(math.cos(a), 0, math.sin(a))
		local by = h * (0.55 + 0.12 * i)
		local tip = base + V3.new(0, by + 3, 0) + d * 8
		local from = base + V3.new(0, by, 0)
		K.boxCF(CF.lookAt((from + tip) / 2, tip), V3.new(1.8, 1.8, (tip - from).Magnitude), BARK)
		for _, o in { V3.new(0, 0, 0), V3.new(u, 0, 0), V3.new(-u, 0, 0), V3.new(0, 0, u), V3.new(0, u, 0), V3.new(0, 0, -u) } do
			K.boxCF(CF.new(tip + o), V3.new(u, u, u), if rand() < 0.4 then LEAF_L else LEAF)
		end
	end
	-- big ferns around the tree
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + rand() * 0.8
		bigFern(K, base + V3.new(math.cos(a), 0, math.sin(a)) * (T / 2 + 4 + rand() * 2.5), 6 + rand() * 2.5, seed * 10 + i)
	end
	-- ferns around the foot of the trunk
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + rand() * 0.3
		local d = V3.new(math.cos(a), 0, math.sin(a))
		local p = base + d * (T / 2 + 1.6 + rand() * 1.2)
		K.boxCF(
			CF.lookAt(p + V3.new(0, 0.7, 0), p + V3.new(0, 0.7, 0) + d + V3.new(0, 0.55, 0)),
			V3.new(0.9, 0.2, 3.2),
			if i % 2 == 0 then LEAF else LEAF_L
		)
	end
	-- vines hanging from the canopy edge, cocoa pods on the trunk
	for _ = 1, 16 do
		local a = rand() * math.pi * 2
		local r = R * (0.7 + rand() * 0.3)
		local len = 5 + rand() * 13
		K.boxCF(at(math.cos(a) * r, h - 1.8 - len / 2, math.sin(a) * r), V3.new(0.5, len, 0.4), VINE)
		if rand() < 0.5 then
			K.boxCF(at(math.cos(a) * r, h - 1.8 - len, math.sin(a) * r), V3.new(1.2, 1.2, 1.2), LEAF)
		end
	end
	for i = 0, 2 do
		local a = i * 2.2
		K.boxCF(
			at(math.cos(a) * (T / 2 + 0.5), h * 0.8 - i * 1.5, math.sin(a) * (T / 2 + 0.5)),
			V3.new(1.1, 1.5, 1.1),
			C3.fromRGB(176, 104, 50)
		)
	end
end

---------------------------------------------------------------- Forge Vault detail kit

-- The vault's stone tones.
local VS = {
	core = C3.fromRGB(40, 36, 48), -- grout, mortar
	tiles = { C3.fromRGB(94, 88, 106), C3.fromRGB(82, 76, 94), C3.fromRGB(104, 98, 116), C3.fromRGB(74, 70, 86) },
	moss = C3.fromRGB(78, 108, 70),
	light = C3.fromRGB(120, 114, 134),
	dark = C3.fromRGB(62, 58, 74),
	wood = C3.fromRGB(108, 64, 42),
	roof = { C3.fromRGB(84, 54, 50), C3.fromRGB(96, 62, 56), C3.fromRGB(72, 46, 44) },
}
local SLATEM = Enum.Material.Slate
local MARBLE = Enum.Material.Marble
local PODIUM_H = 1.6

--[[
	Staggered flagstones filling x0..x1, z0..z1 of cf's frame, their tops at
	y = top (a few a little higher). opts: seed, tones, depth, minLen, lenVar,
	gap, moss (chance), material.
]]
local function flagstones(K: any, cf: any, x0: number, x1: number, z0: number, z1: number, top: number, opts: any)
	local rand = lcg(opts.seed or 3)
	local depth = opts.depth or 3.2
	local gap = opts.gap or 0.16
	local z, row = z0, 0
	while z < z1 - 0.05 do
		local d = math.min(depth, z1 - z)
		local x = x0 - (if row % 2 == 1 then depth * 0.6 else 0)
		while x < x1 - 0.05 do
			local len = (opts.minLen or 2.8) + rand() * (opts.lenVar or 2.4)
			local a, b = math.max(x, x0), math.min(x + len, x1)
			if b - a > 0.5 then
				local tone = opts.tones[1 + math.floor(rand() * #opts.tones)]
				if opts.moss and rand() < opts.moss then
					tone = tone:Lerp(VS.moss, 0.5)
				end
				local h = 0.3 + (if rand() < 0.2 then 0.06 else 0)
				K.boxCF(cf * CF.new((a + b) / 2, top - 0.3 + h / 2, z + d / 2), V3.new(b - a - gap, h, d - gap), tone, opts.material)
			end
			x += len
		end
		z += d
		row += 1
	end
end

-- A row of face blocks (a podium side, a step): cf = the strip's bottom center, X along it, +Z outward.
local function blockRow(K: any, cf: any, length: number, height: number, seed: number, rune: any?)
	local rand = lcg(seed)
	local x, i = -length / 2, 0
	while x < length / 2 - 0.05 do
		local len = math.min(length / 2 - x, 3 + rand() * 2)
		local tone = VS.tiles[1 + math.floor(rand() * #VS.tiles)]:Lerp(VS.dark, 0.25)
		K.boxCF(cf * CF.new(x + len / 2, height / 2, 0), V3.new(len - 0.14, height - 0.14, 0.6), tone, SLATEM)
		if rune and i % 3 == 1 and len > 2.4 then
			neon(K, cf * CF.new(x + len / 2, height / 2, 0.31), V3.new(0.9, 0.18, 0.04), rune)
		end
		x += len
		i += 1
	end
end

--[[
	The stone podium the vault stands on (ground frame, front +Z): a grout core,
	block faces with small rune inlays, a lighter coping rim, flagstones on top
	around the building, three wide front steps between two cheek walls with
	braziers.
]]
local function podium(K: any, ground: any)
	local X0, X1, Z0, Z1 = -42, 42, -34, 42
	local H = PODIUM_H
	local FIRE = C3.fromRGB(255, 140, 50)
	local function at(x: number, y: number, z: number): any
		return ground * CF.new(x, y, z)
	end
	K.boxCF(at(0, (H - 0.3) / 2, (Z0 + Z1) / 2), V3.new(X1 - X0, H - 0.3, Z1 - Z0), VS.core)
	-- faces: front (split by the steps), back, sides
	local SW = 15.6
	for _, seg in { { X0, -SW }, { SW, X1 } } do
		blockRow(K, at((seg[1] + seg[2]) / 2, 0, Z1 - 0.2), seg[2] - seg[1], H, 5 + seg[1], FIRE)
	end
	blockRow(K, at(0, 0, Z0 + 0.2) * CF.Angles(0, math.pi, 0), X1 - X0, H, 7, FIRE)
	for _, sx in { -1, 1 } do
		blockRow(K, at(sx * (X1 - 0.2), 0, (Z0 + Z1) / 2) * CF.Angles(0, sx * math.pi / 2, 0), Z1 - Z0, H, 9 + sx, FIRE)
	end
	-- coping rim (a gap for the steps)
	local RIM = VS.light
	for _, seg in { { X0, -SW }, { SW, X1 } } do
		K.boxCF(at((seg[1] + seg[2]) / 2, H - 0.1, Z1 - 0.3), V3.new(seg[2] - seg[1] + 0.6, 0.4, 1.4), RIM, SLATEM)
	end
	K.boxCF(at(0, H - 0.1, Z0 + 0.3), V3.new(X1 - X0 + 0.6, 0.4, 1.4), RIM, SLATEM)
	for _, sx in { -1, 1 } do
		K.boxCF(at(sx * (X1 - 0.3), H - 0.1, (Z0 + Z1) / 2), V3.new(1.4, 0.4, Z1 - Z0 + 0.6), RIM, SLATEM)
	end
	-- flagstones around the building (the inside gets its own floor)
	local o = { tones = VS.tiles, moss = 0.08, material = SLATEM }
	local function fill(x0: number, x1: number, z0: number, z1: number, seed: number)
		o.seed = seed
		flagstones(K, ground, x0, x1, z0, z1, H, o)
	end
	fill(X0 + 0.8, X1 - 0.8, 24, Z1 - 0.8, 31)
	fill(X0 + 0.8, -28, Z0 + 0.8, 24, 32)
	fill(28, X1 - 0.8, Z0 + 0.8, 24, 33)
	fill(-28, 28, Z0 + 0.8, -22, 34)
	-- the front steps: three rows of blocks, a fire line on the top nose, cheek walls with braziers
	for k = 1, 3 do
		local top = H * (3 - k + 1) / 3
		local z0 = Z1 + (k - 1) * 2
		K.boxCF(at(0, top / 2, z0 + 1), V3.new(2 * SW - 1, top, 2), VS.core)
		blockRow(K, at(0, 0, z0 + 1.8), 2 * SW - 1, top, 40 + k)
		K.boxCF(at(0, top - 0.12, z0 + 1), V3.new(2 * SW - 1.2, 0.3, 1.9), VS.light, SLATEM)
	end
	neon(K, at(0, H + 0.03, Z1 + 0.15), V3.new(2 * SW - 1.2, 0.06, 0.2), FIRE)
	for _, sx in { -1, 1 } do
		local x = sx * SW
		K.boxCF(at(x, (H + 1.2) / 2, Z1 + 3), V3.new(2.4, H + 1.2, 6), VS.dark, SLATEM)
		K.boxCF(at(x, H + 1.35, Z1 + 3), V3.new(2.8, 0.3, 6.4), VS.light, SLATEM)
		-- a brazier on the front end
		K.boxCF(at(x, H + 2.1, Z1 + 4.6), V3.new(1.6, 1.2, 1.6), VS.dark, SLATEM)
		K.cylCF(at(x, H + 3.1, Z1 + 4.6) * CF.Angles(0, 0, math.pi / 2), 0.9, 2.6, C3.fromRGB(46, 42, 48), Enum.Material.Metal)
		local flame = K.part("Part", at(x, H + 3.9, Z1 + 4.6), V3.new(1.9, 1.7, 1.9), FIRE, NEON)
		flame.Shape = Enum.PartType.Ball
		local embers = roblox.Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Color = roblox.ColorSequence.new(FIRE)
		embers.Parent = flame
		light(K, (at(x, H + 5, Z1 + 5)).Position, FIRE, 16, 1)
	end
end

--[[
	A glass crystal shard with a glowing core (the big decorative crystals: a
	whole neon cluster blooms into a blob in Roblox). base = its foot, up =
	its direction, s = thickness, length.
]]
local function glassShard(K: any, base: any, up: any, s: number, length: number, color: any, core: any)
	local hint = if math.abs(up.X) > 0.9 then V3.new(0, 0, 1) else V3.new(1, 0, 0)
	local right = (hint - up * hint:Dot(up)).Unit
	local cf = CF.fromMatrix(base, right, up) * CF.Angles(0, math.pi / 4, 0)
	local colL = length * 0.66
	local tipL = length - colL
	local function glass(p: any)
		p.Material = Enum.Material.Glass
		p.Transparency = 0.3
		p.Reflectance = 0.15
		return p
	end
	glass(K.boxCF(cf * CF.new(0, colL / 2, 0), V3.new(s, colL, s), color))
	glass(K.part("WedgePart", cf * CF.new(0, colL + tipL / 2, -s / 4), V3.new(s, tipL, s / 2), color))
	glass(K.part("WedgePart", cf * CF.new(0, colL + tipL / 2, s / 4) * CF.Angles(0, math.pi, 0), V3.new(s, tipL, s / 2), color))
	K.boxCF(cf * CF.new(0, colL * 0.5, 0), V3.new(s * 0.42, colL * 0.82, s * 0.42), core, NEON)
end

local function gemCluster(K: any, base: any, up: any, side: any, size: number, color: any, core: any)
	glassShard(K, base - up * 0.04, up, size * 0.3, size, color, core)
	glassShard(K, base + side * size * 0.2 - up * 0.04, (up + side * 0.75).Unit, size * 0.24, size * 0.66, color, core)
	glassShard(K, base - side * size * 0.18 - up * 0.04, (up - side * 0.6).Unit, size * 0.2, size * 0.5, color, core)
	local back = up:Cross(side).Unit
	glassShard(K, base + back * size * 0.16, (up + back * 0.55).Unit, size * 0.18, size * 0.45, color, core)
end

--[[
	The giant round vault door set into the back wall (cf = its center, facing
	+Z): a stone frame of voussoirs, a steel door with a glowing ring, bolts, a
	hub with a three-spoke wheel and a fire diamond.
]]
local function vaultDoor(K: any, cf: any, r: number)
	local FIRE = C3.fromRGB(255, 140, 50)
	local STEELD = C3.fromRGB(58, 60, 72)
	local STEELL = C3.fromRGB(96, 100, 116)
	local ALONG_Z = CF.Angles(0, math.pi / 2, 0)
	local n = 16
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		K.boxCF(
			cf * CF.Angles(0, 0, a) * CF.new(r + 1.1, 0, 0.2),
			V3.new(2.2, 2 * math.pi * (r + 1.1) / n - 0.18, 1.6),
			if i % 2 == 0 then VS.light else VS.tiles[1],
			SLATEM
		)
	end
	K.boxCF(cf * CF.new(0, r + 2.6, 0.5) * CF.Angles(0, 0, math.pi / 4), V3.new(1.8, 1.8, 1.8), VS.light, SLATEM) -- keystone
	K.cylCF(cf * ALONG_Z, 0.8, 2 * r, STEELD, Enum.Material.Metal)
	K.cylCF(cf * CF.new(0, 0, 0.45) * ALONG_Z, 0.12, 2 * r - 1.2, FIRE, NEON)
	K.cylCF(cf * CF.new(0, 0, 0.5) * ALONG_Z, 0.14, 2 * r - 1.8, STEELL, Enum.Material.Metal)
	K.cylCF(cf * CF.new(0, 0, 0.56) * ALONG_Z, 0.1, 2 * r - 4, STEELD, Enum.Material.Metal)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		K.cylCF(cf * CF.Angles(0, 0, a) * CF.new(r - 1.4, 0, 0.62) * ALONG_Z, 0.3, 0.55, C3.fromRGB(150, 154, 170), Enum.Material.Metal)
	end
	-- the hub and the wheel
	K.cylCF(cf * CF.new(0, 0, 0.75) * ALONG_Z, 0.5, 3, STEELL, Enum.Material.Metal)
	for i = 0, 2 do
		local a = i * math.pi / 3
		K.boxCF(
			cf * CF.Angles(0, 0, a) * CF.new(0, 0, 1.15),
			V3.new(2 * r - 4.6, 0.45, 0.45),
			C3.fromRGB(140, 110, 70),
			Enum.Material.Metal
		)
		for _, sx in { -1, 1 } do
			K.boxCF(
				cf * CF.Angles(0, 0, a) * CF.new(sx * (r - 2.3), 0, 1.15),
				V3.new(0.7, 0.7, 0.7),
				C3.fromRGB(170, 136, 80),
				Enum.Material.Metal
			)
		end
	end
	neon(K, cf * CF.new(0, 0, 1.05) * CF.Angles(0, 0, math.pi / 4), V3.new(1.2, 1.2, 0.2), FIRE)
	light(K, (cf * CF.new(0, 0, 4)).Position, FIRE, 18, 0.9)
end

-- An iron ring chandelier with candles, hung from (top) by a chain.
local function chandelier(K: any, top: any, drop: number)
	local IRON = C3.fromRGB(40, 38, 44)
	local FLAME = C3.fromRGB(255, 176, 80)
	K.boxCF(top * CF.new(0, -drop / 2, 0), V3.new(0.25, drop, 0.25), IRON)
	local ring = top * CF.new(0, -drop, 0)
	local n, r = 10, 2.6
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		K.boxCF(ring * CF.Angles(0, a, 0) * CF.new(r, 0, 0), V3.new(0.35, 0.35, 2 * math.pi * r / n + 0.1), IRON)
		local p = ring * CF.Angles(0, a + math.pi / n, 0) * CF.new(r, 0, 0)
		K.cylCF(p * CF.new(0, 0.55, 0) * CF.Angles(0, 0, math.pi / 2), 0.9, 0.3, C3.fromRGB(236, 224, 200))
		local f = K.part("Part", p * CF.new(0, 1.15, 0), V3.new(0.32, 0.45, 0.32), FLAME, NEON)
		f.Shape = Enum.PartType.Ball
	end
	for _, a in { 0, math.pi / 2 } do
		K.boxCF(ring * CF.Angles(0, a, 0), V3.new(2 * r, 0.25, 0.25), IRON)
	end
	light(K, (ring * CF.new(0, 0.8, 0)).Position, FLAME, 16, 0.7)
end

--[[
	The pitched roof (vault frame): two slopes of slate tiles on an underlay from
	the eaves (x = +-37, y = 23.6) to the ridge (x = 0, y = 40), z from -29.5 to
	26; a ridge cap with a fire line, eave fascias, rafters underneath, friezes
	closing the gaps over the side walls, and the back gable with a rose window.
]]
local function pitchedRoof(K: any, parent: any, origin: any)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local FIRE = C3.fromRGB(255, 140, 50)
	local EX, EY, RY = 37, 23.6, 40
	local ZB, ZF = -29.5, 26
	local len = ZF - ZB
	local zc = (ZB + ZF) / 2
	local slope = math.sqrt(EX * EX + (RY - EY) ^ 2)
	local rand = lcg(77)
	for _, sx in { -1, 1 } do
		local eave = V3.new(sx * EX, EY, 0)
		local d = V3.new(-sx * EX, RY - EY, 0).Unit -- up the slope
		local nrm = V3.new(sx * (RY - EY), EX, 0).Unit -- out of the roof
		local back = d:Cross(nrm)
		local function frame(s: number, out: number, z: number): any
			return origin * CF.fromMatrix(eave + d * s + nrm * out + V3.new(0, 0, z), d, nrm, back)
		end
		K.boxCF(frame(slope / 2, -0.25, zc), V3.new(slope + 0.4, 0.5, len), VS.core, SLATEM)
		local rows = 9
		local rowW = slope / rows
		local seg = 3.5
		for r = 0, rows - 1 do
			local z = ZB - (if r % 2 == 1 then seg / 2 else 0)
			while z < ZF - 0.05 do
				local a, b = math.max(z, ZB), math.min(z + seg, ZF)
				if b - a > 0.6 then
					local tone = VS.roof[1 + math.floor(rand() * #VS.roof)]
					K.boxCF(frame((r + 0.5) * rowW, 0.22 + r * 0.02, (a + b) / 2), V3.new(rowW - 0.14, 0.44, b - a - 0.14), tone, SLATEM)
				end
				z += seg
			end
		end
		-- the eave fascia with a fire line, rafters under the slope
		K.boxCF(origin * CF.new(sx * (EX + 0.3), EY - 0.4, zc), V3.new(0.6, 1.2, len + 0.4), C3.fromRGB(46, 42, 56), SLATEM)
		neon(K, origin * CF.new(sx * (EX + 0.62), EY - 0.85, zc), V3.new(0.06, 0.18, len + 0.4), FIRE)
		for _, z in { -24, -13, -2, 9, 20 } do
			K.boxCF(frame(slope / 2 - 1.5, -0.95, z), V3.new(slope - 4, 0.9, 1.0), VS.wood)
		end
		-- a frieze over the side wall (closes the gap under the eaves) with a fire line
		K.boxCF(origin * CF.new(sx * 31, 23.45, -1.5), V3.new(6.2, 1.7, 51), VS.dark, SLATEM)
		neon(K, origin * CF.new(sx * 34.15, 23.6, -1.5), V3.new(0.08, 0.22, 51), FIRE)
	end
	-- the ridge cap, its fire line, a crystal finial at the back
	K.boxCF(origin * CF.new(0, RY + 0.35, zc), V3.new(2.4, 1.0, len + 0.6), C3.fromRGB(46, 42, 56), SLATEM)
	neon(K, origin * CF.new(0, RY + 0.9, zc), V3.new(0.3, 0.12, len + 0.6), FIRE)
	gemCluster(
		K,
		(origin * CF.new(0, RY + 0.8, ZB + 0.6)).Position,
		V3.new(0, 1, -0.3).Unit,
		V3.new(1, 0, 0),
		3.2,
		C3.fromRGB(240, 110, 50),
		C3.fromRGB(200, 70, 20)
	)
	-- the back gable: a stone band, two stone triangles, fire rakes, a rose window
	local zG = -27.4
	K.boxCF(origin * CF.new(0, 23.3, zG), V3.new(69, 1.0, 2.6), VS.light, SLATEM)
	for _, sx in { -1, 1 } do
		local a = (origin * CF.new(sx * 34.4, 23.4, zG)).Position
		local b = (origin * CF.new(0, 23.4, zG)).Position
		local c = (origin * CF.new(0, 39.3, zG)).Position
		Geo.triangle(parent, a, b, c, 2.4, VS.tiles[2], SLATEM, nil, { CanCollide = false })
		local rake = c - a
		local mid = (a + c) / 2 + (origin.Rotation * V3.new(0, 0, -1.3))
		K.boxCF(CF.lookAt(mid, mid + rake), V3.new(0.35, 0.35, rake.Magnitude), FIRE, NEON)
	end
	local rose = origin * CF.new(0, 30.5, zG - 1.25) * CF.Angles(0, math.pi, 0) -- facing -Z
	neon(K, rose * CF.new(0, 0, -0.05), V3.new(6.6, 6.6, 0.1), C3.fromRGB(200, 80, 30))
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		K.boxCF(rose * CF.Angles(0, 0, a) * CF.new(3.7, 0, 0.1), V3.new(1.0, 2.1, 0.7), VS.light, SLATEM)
	end
	for i = 0, 5 do
		K.boxCF(rose * CF.Angles(0, 0, i * math.pi / 6) * CF.new(0, 0, 0.12), V3.new(6.4, 0.35, 0.35), VS.dark, SLATEM)
	end
	K.cylCF(rose * CF.new(0, 0, 0.15) * CF.Angles(0, math.pi / 2, 0), 0.4, 1.6, VS.light, SLATEM)
	light(K, (rose * CF.new(0, 0, 3)).Position, FIRE, 14, 0.8)
end

-- One of the case steps: a grout core, block rows on its front, a polished top slab, end pilasters.
local function caseStep(K: any, origin: any, z: number, top: number, seed: number)
	local FIRE = C3.fromRGB(255, 140, 50)
	K.boxCF(origin * CF.new(0, top / 2, z - 4), V3.new(50, top, 8), VS.core)
	local rows = math.max(1, math.floor(top / 1.55 + 0.5))
	local rh = top / rows
	for r = 0, rows - 1 do
		blockRow(K, origin * CF.new(0, r * rh, z - 0.2 + 0.0) * CF.new(0, 0, 0), 50, rh, seed + r)
	end
	K.boxCF(origin * CF.new(0, top - 0.15, z - 3.9), V3.new(50.4, 0.4, 8.4), VS.light, MARBLE)
	neon(K, origin * CF.new(0, top + 0.06, z + 0.1), V3.new(50.2, 0.08, 0.2), FIRE)
	for _, sx in { -1, 1 } do
		K.boxCF(origin * CF.new(sx * 25.6, (top + 0.8) / 2, z - 4), V3.new(1.6, top + 0.8, 8.6), VS.dark, SLATEM)
		K.boxCF(origin * CF.new(sx * 25.6, top + 0.9, z - 4), V3.new(2.0, 0.3, 9.0), VS.light, SLATEM)
	end
end

-- The inside floor: a two-tone marble checker, a fire inlay border, and a red runner to the counter.
local function vaultFloor(K: any, origin: any)
	local FIRE = C3.fromRGB(255, 140, 50)
	local A, B = C3.fromRGB(44, 38, 54), C3.fromRGB(70, 64, 84)
	local size = 4
	for ix = 0, 13 do
		for iz = 0, 11 do
			local x = -28 + (ix + 0.5) * size
			local z = -22 + (iz + 0.5) * size
			if z < 24.5 then
				K.boxCF(origin * CF.new(x, -0.15, z), V3.new(size - 0.12, 0.3, size - 0.12), if (ix + iz) % 2 == 0 then A else B, MARBLE)
			end
		end
	end
	K.boxCF(origin * CF.new(0, -0.35, 1.25), V3.new(56, 0.3, 46.5), VS.core)
	for _, sx in { -1, 1 } do
		neon(K, origin * CF.new(sx * 26.6, 0.02, 11), V3.new(0.16, 0.06, 24), FIRE)
	end
	neon(K, origin * CF.new(0, 0.02, 23.2), V3.new(53.4, 0.06, 0.16), FIRE)
	-- the runner from the entrance to the counter
	local RED, GOLD = C3.fromRGB(128, 30, 40), C3.fromRGB(214, 168, 70)
	local z0, z1 = 7.4, 24
	K.boxCF(origin * CF.new(0, 0.06, (z0 + z1) / 2), V3.new(7, 0.12, z1 - z0), RED)
	for _, sx in { -1, 1 } do
		K.boxCF(origin * CF.new(sx * 3.1, 0.08, (z0 + z1) / 2), V3.new(0.4, 0.13, z1 - z0), GOLD)
	end
	for z = z0 + 2, z1 - 1.5, 3.4 do
		K.boxCF(origin * CF.new(0, 0.08, z) * CF.Angles(0, math.pi / 4, 0), V3.new(1.0, 0.13, 1.0), GOLD)
	end
	for i = 0, 13 do
		K.boxCF(origin * CF.new(-3.25 + i * 0.5, 0.06, z1 + 0.25), V3.new(0.18, 0.08, 0.5), GOLD)
	end
end

---------------------------------------------------------------- Forge Vault wall decorations

local BlasterShapes = require("./kenney_blaster_shapes") :: any

--[[
	A frame on an inside wall (vault frame): the decoration's local X runs to the
	viewer's right, Y up, Z out of the wall. side -1 = the left wall (x = -28),
	1 = the right wall (x = 28).
]]
local function wallFrame(origin: any, side: number, z: number, y: number): any
	-- in front of the bricks and the string course (they stand 0.7 out of the wall's inner face at 28)
	return origin * CF.new(side * 27.2, y, z) * CF.Angles(0, -side * math.pi / 2, 0)
end

-- A picture frame (w x h) with a canvas; returns the canvas front frame (z = its front face).
local function pictureFrame(K: any, f: any, w: number, h: number, frameColor: any, canvas: any): any
	K.boxCF(f * CF.new(0, 0, 0.1), V3.new(w, h, 0.2), canvas)
	for _, sy in { -1, 1 } do
		K.boxCF(f * CF.new(0, sy * (h / 2 + 0.25), 0.25), V3.new(w + 1, 0.5, 0.5), frameColor)
	end
	for _, sx in { -1, 1 } do
		K.boxCF(f * CF.new(sx * (w / 2 + 0.25), 0, 0.25), V3.new(0.5, h, 0.5), frameColor)
	end
	return f * CF.new(0, 0, 0.2)
end

-- A treasure map of the island: parchment between two scroll rods, the island, a dashed route, an X, a compass.
local function treasureMap(K: any, f: any)
	local PAPER, INK, RED = C3.fromRGB(226, 200, 146), C3.fromRGB(96, 66, 42), C3.fromRGB(168, 44, 34)
	local W, H = 12, 7.6
	K.boxCF(f * CF.new(0, 0, 0.1), V3.new(W, H, 0.12), PAPER)
	for _, sy in { -1, 1 } do
		K.cylCF(f * CF.new(0, sy * (H / 2 + 0.2), 0.3), W + 0.6, 0.6, C3.fromRGB(112, 72, 46))
		for _, sx in { -1, 1 } do
			K.cylCF(f * CF.new(sx * (W / 2 + 0.55), sy * (H / 2 + 0.2), 0.3), 0.3, 0.85, C3.fromRGB(176, 136, 70))
		end
	end
	local function ink(x: number, y: number, w: number, h: number, color: any, rot: number?)
		K.boxCF(f * CF.new(x, y, 0.19) * CF.Angles(0, 0, rot or 0), V3.new(w, h, 0.06), color)
	end
	-- sea waves
	for _, p in { { -4.6, 2.6 }, { 3.8, 2.8 }, { -4.8, -2.9 }, { 4.6, -0.6 }, { -1.2, 3.0 } } do
		ink(p[1], p[2], 1.1, 0.1, C3.fromRGB(120, 150, 150))
		ink(p[1] + 0.4, p[2] - 0.25, 0.8, 0.1, C3.fromRGB(120, 150, 150))
	end
	-- the island: sand, grass, a mountain, a shore line
	for _, r in { { -0.6, 0.0, 6.8, 3.6 }, { 0.6, -1.0, 5.0, 2.6 }, { -1.8, 1.3, 3.4, 1.8 }, { 2.4, 0.9, 2.6, 1.6 } } do
		ink(r[1], r[2], r[3] + 0.3, r[4] + 0.3, INK)
		K.boxCF(f * CF.new(r[1], r[2], 0.21), V3.new(r[3], r[4], 0.06), C3.fromRGB(214, 184, 118))
	end
	for _, r in { { -0.8, 0.2, 4.6, 2.0 }, { 0.8, -0.8, 3.2, 1.4 }, { -1.8, 1.2, 2.2, 1.0 } } do
		K.boxCF(f * CF.new(r[1], r[2], 0.23), V3.new(r[3], r[4], 0.06), C3.fromRGB(120, 150, 82))
	end
	K.boxCF(f * CF.new(-1.4, 0.7, 0.25) * CF.Angles(0, 0, math.pi / 4), V3.new(1.0, 1.0, 0.06), C3.fromRGB(110, 86, 64))
	-- the dashed route to the X
	local pts = { { -5.0, -2.2 }, { -3.4, -1.6 }, { -2.2, -0.6 }, { -0.6, -0.2 }, { 0.6, 0.6 }, { 1.8, 0.2 } }
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		ink(mx, my, 0.5, 0.14, RED, math.atan2(b[2] - a[2], b[1] - a[1]))
	end
	for _, r in { math.pi / 4, -math.pi / 4 } do
		K.boxCF(f * CF.new(2.4, 0.2, 0.27) * CF.Angles(0, 0, r), V3.new(1.0, 0.22, 0.06), RED)
	end
	-- compass rose
	for i = 0, 3 do
		K.boxCF(
			f * CF.new(4.4, -2.4, 0.21) * CF.Angles(0, 0, i * math.pi / 2) * CF.new(0, 0.45, 0) * CF.Angles(0, 0, math.pi / 4),
			V3.new(0.34, 0.34, 0.06),
			INK
		)
	end
	K.boxCF(f * CF.new(4.4, -1.5, 0.21), V3.new(0.16, 0.4, 0.06), RED)
end

-- A blueprint of the level 10 blaster (Kenney's blaster-e outline) on a blue board with a grid.
local function blueprint(K: any, f: any)
	local W, H = 12, 7
	local LINE = C3.fromRGB(226, 238, 255)
	local c = pictureFrame(K, f, W, H, C3.fromRGB(46, 42, 52), C3.fromRGB(38, 78, 150))
	for i = 1, 11 do
		K.boxCF(c * CF.new(-W / 2 + i, 0, 0.02), V3.new(0.05, H, 0.03), C3.fromRGB(70, 112, 190))
	end
	for i = 1, 6 do
		K.boxCF(c * CF.new(0, -H / 2 + i, 0.02), V3.new(W, 0.05, 0.03), C3.fromRGB(70, 112, 190))
	end
	local data = BlasterShapes["blaster-e"]
	local b = data.bounds
	local s = 10 / (b[2] - b[1])
	local cz, cy = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2
	for i, region in data.regions do
		if i <= 14 then
			for _, L in region.loops do
				local n = #L // 2
				for k = 1, n do
					local j = k % n + 1
					-- the barrel points left on the board (the muzzle at -Z in the data)
					local x0, y0 = (L[2 * k - 1] - cz) * s, (L[2 * k] - cy) * s + 0.4
					local x1, y1 = (L[2 * j - 1] - cz) * s, (L[2 * j] - cy) * s + 0.4
					local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
					if len > 0.12 then
						K.boxCF(
							c * CF.new((x0 + x1) / 2, (y0 + y1) / 2, 0.05) * CF.Angles(0, 0, math.atan2(y1 - y0, x1 - x0)),
							V3.new(len + 0.06, 0.07, 0.04),
							LINE
						)
					end
				end
			end
		end
	end
	-- "text" lines and a stamp
	for i, w in { 3.2, 2.2, 2.6 } do
		K.boxCF(c * CF.new(-W / 2 + 0.6 + w / 2, -H / 2 + 0.5 + i * 0.35, 0.05), V3.new(w, 0.12, 0.04), LINE)
	end
	K.boxCF(c * CF.new(W / 2 - 1.3, -H / 2 + 1.0, 0.05) * CF.Angles(0, 0, 0.2), V3.new(1.6, 0.9, 0.04), C3.fromRGB(220, 70, 60))
end

-- A sunset painting of a volcano in a gold frame.
local function volcanoPainting(K: any, parent: any, f: any)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local W, H = 9, 6
	local c = pictureFrame(K, f, W, H, C3.fromRGB(196, 152, 66), C3.fromRGB(70, 46, 90))
	for i, band in { { 1.3, C3.fromRGB(150, 80, 120) }, { 0.0, C3.fromRGB(226, 120, 104) }, { -1.1, C3.fromRGB(246, 168, 92) } } do
		K.boxCF(c * CF.new(0, band[1], 0.02 + i * 0.002), V3.new(W, 1.4, 0.04), band[2])
	end
	K.cylCF(c * CF.new(2.4, 0.4, 0.05) * CF.Angles(0, math.pi / 2, 0), 0.04, 1.6, C3.fromRGB(255, 226, 150))
	local function tri(a: any, b: any, cc: any, color: any)
		Geo.triangle(
			parent,
			(c * CF.new(a.X, a.Y, 0.09)).Position,
			(c * CF.new(b.X, b.Y, 0.09)).Position,
			(c * CF.new(cc.X, cc.Y, 0.09)).Position,
			0.05,
			color,
			nil,
			nil,
			{ CanCollide = false }
		)
	end
	tri(V3.new(-4.5, -3), V3.new(4.5, -3), V3.new(4.5, -1.6), C3.fromRGB(70, 56, 66))
	tri(V3.new(-4.5, -3), V3.new(4.5, -1.6), V3.new(-4.5, -1.2), C3.fromRGB(70, 56, 66))
	tri(V3.new(-3.6, -2.2), V3.new(1.6, -2.2), V3.new(-1.0, 1.4), C3.fromRGB(56, 40, 50))
	tri(V3.new(-0.6, -2.2), V3.new(3.8, -2.2), V3.new(1.8, 0.0), C3.fromRGB(84, 62, 72))
	K.boxCF(c * CF.new(-1.0, 1.3, 0.12), V3.new(0.9, 0.25, 0.04), C3.fromRGB(255, 120, 40), NEON)
	K.boxCF(c * CF.new(-1.3, 0.3, 0.12) * CF.Angles(0, 0, 0.35), V3.new(0.16, 1.9, 0.04), C3.fromRGB(255, 120, 40), NEON)
	K.boxCF(c * CF.new(-0.5, -0.1, 0.12) * CF.Angles(0, 0, -0.5), V3.new(0.14, 2.2, 0.04), C3.fromRGB(255, 120, 40), NEON)
	for i = 0, 3 do
		K.boxCF(c * CF.new(-1.0 + (i - 1.5) * 0.5, 2.0 + i * 0.3, 0.1), V3.new(0.7, 0.4, 0.04), C3.fromRGB(90, 80, 92))
	end
end

-- The ore collection: a dark board with twelve ore gems on brass plates.
local function oreBoard(K: any, f: any)
	local OreData = L.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local W, H = 9, 6.4
	local c = pictureFrame(K, f, W, H, C3.fromRGB(96, 62, 40), C3.fromRGB(44, 32, 30))
	K.boxCF(c * CF.new(0, H / 2 - 0.55, 0.04), V3.new(5, 0.5, 0.06), C3.fromRGB(196, 152, 66))
	local ores = { "Copper", "Iron", "Silver", "Amethyst", "Jade", "Emberite", "Gold", "Ruby", "Azurium", "Sapphire", "Emerald", "Diamond" }
	for i, id in ores do
		local ore = OreData.ById[id]
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local x, y = -3.15 + col * 2.1, 1.2 - row * 1.75
		local gem = K.boxCF(
			c * CF.new(x, y, 0.4) * CF.Angles(0, 0, math.pi / 4) * CF.Angles(0.5, 0, 0),
			V3.new(0.8, 0.8, 0.8),
			if ore then ore.Color else C3.new(1, 1, 1)
		)
		gem.Material = Enum.Material.Glass
		gem.Reflectance = 0.2
		K.boxCF(c * CF.new(x, y - 0.75, 0.05), V3.new(1.2, 0.24, 0.06), C3.fromRGB(196, 152, 66))
	end
end

-- A wooden rack with three blasters on pegs.
local function weaponRack(K: any, parent: any, f: any)
	local WOOD = C3.fromRGB(96, 62, 40)
	K.boxCF(f * CF.new(0, 0, 0.15), V3.new(8.6, 6.6, 0.3), WOOD)
	for _, sx in { -1, 1 } do
		K.boxCF(f * CF.new(sx * 4.5, 0, 0.3), V3.new(0.5, 7.2, 0.6), C3.fromRGB(70, 44, 30))
	end
	local guns = { { 3, 1.25 }, { 5, 1.15 }, { 7, 1.0 } }
	for i, g in guns do
		local y = 2.2 - (i - 1) * 2.2
		for _, sx in { -1.6, 1.6 } do
			K.boxCF(f * CF.new(sx, y - 0.75, 0.6), V3.new(0.25, 0.25, 0.9), C3.fromRGB(150, 120, 70), Enum.Material.Metal)
		end
		local gun = Kenney.gun(L, g[1], Kenney.Lineup[g[1]])
		Concepts.present(gun, f * CF.new(0, y, 0.8) * CF.Angles(0, -math.pi / 2, 0), g[2], parent)
	end
end

-- A wall torch: an iron bracket, a stick and a flame.
local function wallTorch(K: any, f: any)
	K.boxCF(f * CF.new(0, 0, 0.2), V3.new(0.8, 1.4, 0.4), C3.fromRGB(40, 38, 44))
	K.boxCF(f * CF.new(0, 0.6, 0.7) * CF.Angles(0.5, 0, 0), V3.new(0.4, 1.8, 0.4), C3.fromRGB(96, 62, 40))
	local flame = K.part("Part", f * CF.new(0, 1.6, 1.15), V3.new(0.8, 1.0, 0.8), C3.fromRGB(255, 150, 60), NEON)
	flame.Shape = Enum.PartType.Ball
	local embers = roblox.Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Color = roblox.ColorSequence.new(C3.fromRGB(255, 150, 60))
	embers.Parent = flame
	light(K, (f * CF.new(0, 1.8, 1.8)).Position, C3.fromRGB(255, 160, 80), 12, 0.7)
end

-- Everything on the inside side walls.
local function vaultWallDecor(K: any, parent: any, origin: any)
	treasureMap(K, wallFrame(origin, -1, 9.5, 12.5))
	oreBoard(K, wallFrame(origin, -1, -12.5, 15.5))
	blueprint(K, wallFrame(origin, 1, 9.5, 14))
	weaponRack(K, parent, wallFrame(origin, 1, 9.5, 5.6))
	volcanoPainting(K, parent, wallFrame(origin, 1, -12.5, 15.5))
	for _, side in { -1, 1 } do
		for _, z in { 1.5, 18.5 } do
			wallTorch(K, wallFrame(origin, side, z, 9))
		end
	end
end

--[[
	The front facade beside the entrance: a stone wall bay outside each outer
	column with a lit niche holding a glass ore crystal.
]]
local function vaultFacade(K: any, origin: any)
	for _, side in { { -1, 7 }, { 1, 9 } } do
		local sx = side[1]
		local look = oreGlow(side[2])
		local cx = sx * 30.5
		stoneWall(K, origin * CF.new(cx, 0, 21.5), 7, 20, 3, { inner = true, seed = 50 + sx, innerDark = 0.4 })
		local zf = 23
		K.boxCF(origin * CF.new(cx, 8.6, zf + 0.06), V3.new(3.6, 9.2, 0.14), C3.fromRGB(22, 18, 26))
		for _, jx in { -2.1, 2.1 } do
			K.boxCF(origin * CF.new(cx + jx, 8.6, zf + 0.35), V3.new(0.6, 9.2, 0.7), VS.light, SLATEM)
		end
		for i = 0, 6 do
			local a = i / 6 * math.pi
			K.boxCF(
				origin * CF.new(cx + math.cos(a) * 2.1, 13.2 + math.sin(a) * 2.1, zf + 0.35) * CF.Angles(0, 0, a),
				V3.new(0.6, 1.2, 0.7),
				VS.light,
				SLATEM
			)
		end
		K.boxCF(origin * CF.new(cx, 3.9, zf + 0.5), V3.new(4.6, 0.5, 1.2), VS.light, SLATEM)
		K.boxCF(origin * CF.new(cx, 4.6, zf + 0.25), V3.new(1.8, 0.9, 1.0), VS.dark, SLATEM)
		gemCluster(
			K,
			(origin * CF.new(cx, 5.05, zf + 0.25)).Position,
			V3.new(0, 1, 0),
			V3.new(1, 0, 0),
			3.8,
			look.Body,
			look.Body:Lerp(C3.new(0, 0, 0), 0.35)
		)
		neon(K, origin * CF.new(cx, 4.17, zf + 0.6), V3.new(4.4, 0.06, 0.6), look.Glow)
		light(K, (origin * CF.new(cx, 8, zf + 2)).Position, look.Glow, 9, 0.7)
		neon(K, origin * CF.new(cx, 16.4, zf + 0.12) * CF.Angles(0, 0, math.pi / 4), V3.new(0.9, 0.9, 0.12), C3.fromRGB(255, 140, 50))
	end
end

--[[
	Stonework on the front gable: brick courses, a base cornice with dentils,
	raking cornices under the fire lines, a dark medallion with a fire ring
	behind the crossed blasters, crystal acroteria on the corners.
]]
local function gableDetail(K: any, origin: any, zG: number)
	local rand = lcg(808)
	local zf = zG + 1.3 -- the gable's front face
	local y = 24.7
	local row = 0
	while y < 38.4 do
		local hw = 36 * (40 - (y + 0.65)) / 16 - 1.4
		local x = -hw - (if row % 2 == 1 then 1.3 else 0)
		while x < hw do
			local len = 2.4 + rand() * 1.4
			local a, b = math.max(x, -hw), math.min(x + len, hw)
			if b - a > 0.6 then
				local tone = VS.tiles[1 + math.floor(rand() * #VS.tiles)]
				K.boxCF(origin * CF.new((a + b) / 2, y, zf + 0.12), V3.new(b - a - 0.14, 1.16, 0.3), tone, SLATEM)
			end
			x += len
		end
		y += 1.3
		row += 1
	end
	K.boxCF(origin * CF.new(0, 24.2, zf + 0.3), V3.new(73, 0.8, 1.4), VS.light, SLATEM)
	for i = 0, 46 do
		K.boxCF(origin * CF.new(-34.5 + i * 1.5, 23.65, zf + 0.45), V3.new(0.6, 0.45, 0.6), VS.dark, SLATEM)
	end
	for _, sx in { -1, 1 } do
		local a = (origin * CF.new(sx * 36, 24.4, zf + 0.5)).Position
		local c = (origin * CF.new(0, 40.2, zf + 0.5)).Position
		K.boxCF(CF.lookAt((a + c) / 2, c), V3.new(1.0, 0.9, (c - a).Magnitude), VS.light, SLATEM)
		gemCluster(
			K,
			(origin * CF.new(sx * 35.6, 24.6, zf + 0.4)).Position,
			V3.new(sx * 0.3, 1, 0).Unit,
			V3.new(sx, 0, 0),
			2.4,
			C3.fromRGB(240, 110, 50),
			C3.fromRGB(200, 70, 20)
		)
	end
	-- the medallion behind the crossed blasters
	local m = origin * CF.new(0, 31, zf + 0.4)
	K.cylCF(m * CF.Angles(0, math.pi / 2, 0), 0.3, 10, C3.fromRGB(34, 30, 40), SLATEM)
	K.cylCF(m * CF.new(0, 0, -0.1) * CF.Angles(0, math.pi / 2, 0), 0.2, 10.7, C3.fromRGB(255, 140, 50), NEON)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		K.boxCF(m * CF.Angles(0, 0, a) * CF.new(5.9, 0, 0), V3.new(1.0, 2.1, 0.8), if i % 2 == 0 then VS.light else VS.tiles[1], SLATEM)
	end
end

---------------------------------------------------------------- Forge Vault: glazing, sign, statues, ferns

--[[
	Glass between the front columns so the front reads as one building: steel
	frames, stone sills in the side bays, an open doorway with glass beside and
	above it in the middle bay, and a row of glass transoms above the column
	tops up to the lintel, with a fire line along the transom bar. The glass
	plane is at z = 20.9, inside the columns' depth and behind the fire bowls.
]]
local function vaultGlazing(K: any, origin: any)
	local FIRE = C3.fromRGB(255, 140, 50)
	local STEELF = C3.fromRGB(48, 50, 60)
	local z = 20.9
	local function pane(x0: number, x1: number, y0: number, y1: number)
		local p =
			K.boxCF(origin * CF.new((x0 + x1) / 2, (y0 + y1) / 2, z), V3.new(x1 - x0, y1 - y0, 0.25), C3.fromRGB(150, 205, 235), GLASS)
		p.Transparency = 0.6
		p.Reflectance = 0.12
		p.Name = "GlassPane"
	end
	local function bar(x0: number, x1: number, y0: number, y1: number)
		K.boxCF(origin * CF.new((x0 + x1) / 2, (y0 + y1) / 2, z), V3.new(x1 - x0, y1 - y0, 0.6), STEELF, Enum.Material.Metal)
	end
	for _, sx in { -1, 1 } do
		-- the side bay between the columns at 13 and 24 (x 16..21): a stone sill, two panes
		local a, b = sx * 16, sx * 21
		local x0, x1 = math.min(a, b), math.max(a, b)
		K.boxCF(origin * CF.new((x0 + x1) / 2, 0.8, z), V3.new(5, 1.6, 1.2), VS.dark, SLATEM)
		K.boxCF(origin * CF.new((x0 + x1) / 2, 1.7, z + 0.1), V3.new(5.2, 0.2, 1.5), VS.light, SLATEM)
		pane(x0, x1, 1.8, 12.6)
		bar((x0 + x1) / 2 - 0.15, (x0 + x1) / 2 + 0.15, 1.8, 12.6)
		bar(x0, x1, 7.0, 7.3)
		-- beside the door in the middle bay (x 4.9..10)
		local c0, c1 = math.min(sx * 4.9, sx * 10), math.max(sx * 4.9, sx * 10)
		K.boxCF(origin * CF.new((c0 + c1) / 2, 0.5, z), V3.new(5.1, 1.0, 1.2), VS.dark, SLATEM)
		pane(c0, c1, 1.0, 12.6)
		bar((c0 + c1) / 2 - 0.15, (c0 + c1) / 2 + 0.15, 1.0, 12.6)
		-- the door frame posts
		bar(math.min(sx * 4.4, sx * 4.9), math.max(sx * 4.4, sx * 4.9), 0, 11.6)
		neon(K, origin * CF.new(sx * 4.35, 5.8, z + 0.35), V3.new(0.12, 11.4, 0.08), FIRE)
	end
	-- over the door: the header, its fire line, a glass strip
	bar(-4.9, 4.9, 11, 11.6)
	neon(K, origin * CF.new(0, 10.95, z + 0.35), V3.new(8.8, 0.12, 0.08), FIRE)
	pane(-4.9, 4.9, 11.6, 12.6)
	-- the transom bar across the whole front and the glass row above the column tops
	bar(-27, 27, 12.6, 13.4)
	neon(K, origin * CF.new(0, 13.0, z + 0.32), V3.new(54, 0.14, 0.06), FIRE)
	local posts = { -27, -24, -19, -13, -7, 0, 7, 13, 19, 24, 27 }
	for i = 1, #posts - 1 do
		pane(posts[i], posts[i + 1], 13.4, 19.8)
	end
	for _, x in posts do
		bar(x - 0.2, x + 0.2, 13.4, 19.8)
	end
	bar(-27, 27, 19.8, 20.1)
end

local function labelFont(K: any, cf: any, size: any, text: string, plate: any, ink: any, font: any)
	local p = label(K, cf, size, text, plate, ink)
	local t = p:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
	t.FontFace = roblox.Font.fromEnum(font)
	local stroke = roblox.Instance.new("UIStroke")
	stroke.Color = C3.fromRGB(20, 8, 6)
	stroke.Thickness = 3
	stroke.Parent = t
	return p
end

--[[
	The BLASTER VAULT sign, rougher: a dark stone board with pointed ends, a
	jagged stone frame with glowing cracks, iron corner brackets with rivets,
	heavy lettering, and glass crystals around it (big ones on the points,
	small ones on the top edge and the lower corners). cf = its center, facing +Z.
]]
local function vaultSign(K: any, parent: any, cf: any)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local FIRE = C3.fromRGB(255, 140, 50)
	local IRON = C3.fromRGB(38, 36, 42)
	local rand = lcg(515)
	local W, H = 27, 5.4
	local half, hh = W / 2, H / 2
	local tip = half + 2.8
	K.boxCF(cf, V3.new(W, H, 1.0), C3.fromRGB(34, 30, 38), SLATEM)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			Geo.triangle(
				parent,
				(cf * CF.new(sx * half, sy * hh, 0.5)).Position,
				(cf * CF.new(sx * half, 0, 0.5)).Position,
				(cf * CF.new(sx * tip, 0, 0.5)).Position,
				1.0,
				C3.fromRGB(34, 30, 38),
				SLATEM,
				(cf.Rotation * V3.new(0, 0, 1)),
				{ CanCollide = false }
			)
		end
	end
	-- the text plate and its fire lines
	labelFont(
		K,
		cf * CF.new(0, 0, 0.55),
		V3.new(24, 4.0, 0.12),
		"BLASTER VAULT",
		C3.fromRGB(46, 20, 14),
		C3.fromRGB(255, 196, 96),
		Enum.Font.LuckiestGuy
	)
	for _, sy in { -1, 1 } do
		neon(K, cf * CF.new(0, sy * 2.15, 0.62), V3.new(24, 0.12, 0.06), FIRE)
	end
	-- the jagged stone frame along the top and bottom edges, glowing cracks in it
	for _, sy in { -1, 1 } do
		local x = -half - 0.4
		while x < half + 0.4 do
			local len = 1.6 + rand() * 1.6
			local tone = VS.tiles[1 + math.floor(rand() * #VS.tiles)]
			K.boxCF(
				cf * CF.new(x + len / 2, sy * (hh + 0.25), 0.3) * CF.Angles(0, 0, (rand() - 0.5) * 0.16),
				V3.new(len - 0.12, 0.8 + rand() * 0.3, 1.5),
				tone,
				SLATEM
			)
			x += len
		end
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			-- blocks along the pointed ends
			local a = cf * CF.new(sx * half, sy * hh, 0.3)
			local b = cf * CF.new(sx * tip, 0, 0.3)
			local d = b.Position - a.Position
			for i = 0, 2 do
				local t = (i + 0.5) / 3
				local p = a.Position + d * t
				K.boxCF(CF.lookAt(p, p + d) * CF.new(0, 0, 0), V3.new(1.5, 0.8, d.Magnitude / 3 - 0.12), VS.tiles[1 + (i % 4)], SLATEM)
			end
			-- an iron corner bracket with rivets
			local c = cf * CF.new(sx * (half - 0.9), sy * (hh - 0.6), 0.68)
			K.boxCF(c * CF.new(sx * 0.3, 0, 0), V3.new(1.8, 0.45, 0.12), IRON, Enum.Material.Metal)
			K.boxCF(c * CF.new(sx * 0.65, -sy * 0.5, 0), V3.new(0.45, 1.4, 0.12), IRON, Enum.Material.Metal)
			for _, o in { { -0.2, 0 }, { 0.6, 0 }, { 0.65, -0.8 } } do
				K.cylCF(
					c * CF.new(sx * o[1], sy * o[2], 0.1) * CF.Angles(0, math.pi / 2, 0),
					0.12,
					0.26,
					C3.fromRGB(150, 140, 120),
					Enum.Material.Metal
				)
			end
		end
	end
	for _, p in { { -9, 1 }, { -2, -1 }, { 6, 1 }, { 11, -1 } } do
		local x, sy = p[1], p[2]
		neon(K, cf * CF.new(x, sy * (hh + 0.25), 1.07) * CF.Angles(0, 0, 0.5), V3.new(0.9, 0.09, 0.05), FIRE)
		neon(K, cf * CF.new(x + 0.6, sy * (hh + 0.2), 1.07) * CF.Angles(0, 0, -0.4), V3.new(0.7, 0.09, 0.05), FIRE)
	end
	-- crystals around the sign
	local ORANGE, CORE = C3.fromRGB(240, 110, 50), C3.fromRGB(200, 70, 20)
	for _, sx in { -1, 1 } do
		gemCluster(
			K,
			(cf * CF.new(sx * (tip - 0.6), 0.2, 0.2)).Position,
			(cf.Rotation * V3.new(sx * 0.7, 1, 0.2)).Unit,
			(cf.Rotation * V3.new(sx, 0, 0)),
			4.4,
			ORANGE,
			CORE
		)
		gemCluster(
			K,
			(cf * CF.new(sx * (half - 1.2), -hh - 0.3, 0.4)).Position,
			(cf.Rotation * V3.new(sx * 0.5, -1, 0.3)).Unit,
			(cf.Rotation * V3.new(sx, 0, 0)),
			2.0,
			ORANGE,
			CORE
		)
	end
	for i, x in { -8.5, -3.2, 3.6, 8.8 } do
		local s = 1.4 + (i % 2) * 0.9
		glassShard(
			K,
			(cf * CF.new(x, hh + 0.5, 0.3)).Position,
			(cf.Rotation * V3.new((rand() - 0.5) * 0.6, 1, 0.15)).Unit,
			s * 0.32,
			s,
			ORANGE,
			CORE
		)
	end
	light(K, (cf * CF.new(0, 0, 4)).Position, FIRE, 16, 0.8)
end

--[[
	A big fern: a rosette of fronds that rise and arch out, each with leaflets.
	base = its center on the ground, size ~ its reach.
]]
bigFern = function(K: any, base: any, size: number, seed: number)
	local rand = lcg(seed)
	local GREENS = { C3.fromRGB(56, 138, 50), C3.fromRGB(70, 158, 58), C3.fromRGB(46, 116, 42) }
	local n = 7
	local function seg(a: any, b: any, w: number, color: any)
		local d = b - a
		if d.Magnitude < 0.05 then
			return
		end
		K.boxCF(CF.lookAt((a + b) / 2, b), V3.new(w, 0.16, d.Magnitude + 0.1), color)
	end
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + rand() * 0.5
		local d = V3.new(math.cos(a), 0, math.sin(a))
		local side = V3.new(-d.Z, 0, d.X)
		local rise = 0.85 + rand() * 0.35
		local L1, L2 = size * (0.5 + rand() * 0.15), size * (0.42 + rand() * 0.12)
		local dir1 = (d * math.cos(rise) + V3.new(0, math.sin(rise), 0)).Unit
		local p1 = base + dir1 * L1
		local dir2 = (d + V3.new(0, -0.45, 0)).Unit
		local p2 = p1 + dir2 * L2
		local color = GREENS[1 + math.floor(rand() * #GREENS)]
		seg(base, p1, size * 0.13, color)
		seg(p1, p2, size * 0.1, color)
		for _, t in { 0.5, 0.85 } do
			local q = base + dir1 * (L1 * t)
			for _, sgn in { -1, 1 } do
				seg(q, q + side * sgn * size * 0.24 + dir1 * size * 0.08, size * 0.07, color)
			end
		end
		local q = p1 + dir2 * (L2 * 0.45)
		for _, sgn in { -1, 1 } do
			seg(q, q + side * sgn * size * 0.18 + V3.new(0, -size * 0.04, 0), size * 0.06, color)
		end
	end
end

-- Turns a model into grey stone (the statue's blaster): no glows, no particles.
local function stoneify(model: any)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			d.Parent = nil
		elseif d:IsA("BasePart") and d.Transparency < 0.99 then
			local c = d.Color
			local l = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
			local g = 0.38 + l * 0.26
			d.Color = C3.new(g, g, g * 1.02)
			d.Material = Enum.Material.Concrete
			d.Transparency = 0
			d.Reflectance = 0
		end
	end
end

--[[
	A grey stone statue of a rounded Roblox character with a helmet in the
	classic tool pose (the right arm out front holding a blaster), on a stone
	pedestal with an engraved plaque. feet = the pedestal's foot, facing +Z; u = studs per
	character unit (the character is ~5.4 u tall).
]]
local function guardianStatue(K: any, parent: any, feet: any, u: number)
	local G1, G2, G3, GD = C3.fromRGB(134, 134, 140), C3.fromRGB(118, 118, 124), C3.fromRGB(152, 152, 158), C3.fromRGB(92, 92, 98)
	local CONC = Enum.Material.Concrete
	local MOSS = C3.fromRGB(84, 112, 72)
	-- the pedestal
	K.boxCF(feet * CF.new(0, 0.6, 0), V3.new(14, 1.2, 14), C3.fromRGB(96, 96, 102), SLATEM)
	K.boxCF(feet * CF.new(0, 2.0, 0), V3.new(12, 1.6, 12), C3.fromRGB(116, 116, 122), SLATEM)
	K.boxCF(feet * CF.new(0, 3.0, 0), V3.new(12.8, 0.4, 12.8), C3.fromRGB(140, 140, 146), SLATEM)
	labelFont(
		K,
		feet * CF.new(0, 2.0, 6.04),
		V3.new(7, 0.95, 0.1),
		"VAULT GUARDIAN",
		C3.fromRGB(84, 84, 90),
		C3.fromRGB(196, 196, 202),
		Enum.Font.LuckiestGuy
	)
	for _, p in { { -5.6, 0.7, 6.2, 2.0 }, { 4.8, 0.5, -6.6, 1.6 }, { 6.6, 0.8, 3.0, 1.2 } } do
		K.boxCF(feet * CF.new(p[1], 1.2 + p[2] / 2, p[3]), V3.new(p[4], p[2], p[4] * 0.6), MOSS)
	end
	local base = feet * CF.new(0, 3.2, 0)
	local function at(x: number, y: number, z: number): any
		return base * CF.new(x * u, y * u, z * u)
	end
	local function rb(cf: any, sx: number, sy: number, sz: number, r: number, color: any)
		K.rboxCF(cf * CF.Angles(0, math.pi / 2, 0), V3.new(sz * u, sy * u, sx * u), r * u, color, CONC)
	end
	local function ball(p: any, d: number, color: any)
		local b = K.part("Part", CF.new(p), V3.new(d * u, d * u, d * u), color, CONC)
		b.Shape = Enum.PartType.Ball
	end
	local function cyl(cf: any, h: number, d: number, color: any)
		K.cylCF(cf * CF.Angles(0, 0, math.pi / 2), h * u, d * u, color, CONC)
	end
	-- boots, legs, belt
	for _, sx in { -1, 1 } do
		rb(at(sx * 0.5, 0.25, 0.08), 1.0, 0.5, 1.2, 0.15, GD)
		rb(at(sx * 0.5, 1.3, 0), 0.95, 1.7, 0.95, 0.22, G2)
	end
	K.boxCF(at(0, 2.2, 0), V3.new(2.04 * u, 0.36 * u, 1.06 * u), GD, CONC)
	K.boxCF(at(0, 2.2, 0.54), V3.new(0.42 * u, 0.3 * u, 0.06 * u), G3, CONC)
	-- torso, chest plate with grooves, shoulder pads, neck
	rb(at(0, 3.2, 0), 2.0, 1.8, 1.0, 0.32, G1)
	K.boxCF(at(0, 3.4, 0.5), V3.new(1.4 * u, 1.0 * u, 0.12 * u), G3, CONC)
	for _, y in { 3.15, 3.45, 3.75 } do
		K.boxCF(at(0, y, 0.57), V3.new(1.2 * u, 0.04 * u, 0.04 * u), GD, CONC)
	end
	for _, sx in { -1, 1 } do
		rb(at(sx * 1.45, 3.95, 0), 1.1, 0.55, 1.18, 0.25, G3)
	end
	cyl(at(0, 4.2, 0), 0.3, 0.62, G2)
	-- the head (a Roblox head: a rounded cylinder) and the face under the visor
	cyl(at(0, 4.85, 0), 1.15, 1.3, G1)
	K.boxCF(at(0, 4.5, 0.655), V3.new(0.36 * u, 0.06 * u, 0.04 * u), GD, CONC)
	-- the helmet: a round dome, a brim, a visor band, a low crest, chin straps
	ball((at(0, 5.35, 0)).Position, 1.5, G3)
	cyl(at(0, 5.2, 0), 0.1, 1.74, G2)
	K.boxCF(at(0, 4.95, 0.68), V3.new(1.25 * u, 0.26 * u, 0.12 * u), GD, CONC)
	K.boxCF(at(0, 6.0, 0), V3.new(0.2 * u, 0.3 * u, 1.1 * u), G2, CONC)
	for _, sx in { -1, 1 } do
		K.boxCF(at(sx * 0.67, 4.6, 0.1), V3.new(0.06 * u, 0.7 * u, 0.12 * u), GD, CONC)
	end
	-- the classic Roblox tool pose: the right arm straight out in front holding the
	-- blaster (pointing forward), the left arm down by his side; rounded Roblox arms
	rb(at(-1.48, 3.55, 0.5) * CF.Angles(math.pi / 2, 0, 0), 0.95, 2.0, 0.95, 0.24, G2)
	rb(at(1.48, 2.95, 0.05) * CF.Angles(-0.08, 0, 0.04), 0.95, 2.0, 0.95, 0.24, G2)
	-- a level 9 blaster (level 10's loose floating gems would hang in the air as stone)
	local gun, anchors = Kenney.gun(L, 9, "Stormcore")
	stoneify(gun)
	local gs = 3.0 * u / 3.6
	local R = feet.Rotation
	local gunCf = CF.fromMatrix((at(-1.48, 3.3, 1.3)).Position, R * V3.new(-1, 0, 0), R * V3.new(0, 1, 0), R * V3.new(0, 0, -1))
		* CF.new(-anchors.hand * gs)
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * gs
			d.CFrame = gunCf * CF.new(d.CFrame.Position * gs) * d.CFrame.Rotation
		end
	end
	gun.Parent = parent
end

---------------------------------------------------------------- Forge Vault: giant statues and banners

local PURPLE = C3.fromRGB(88, 46, 132)
local PURPLE_D = C3.fromRGB(58, 30, 88)
local GOLD = C3.fromRGB(222, 172, 72)
local FABRIC = Enum.Material.Fabric

-- The vault's gold crest (cf = its center on a surface facing +Z, s = its size).
local function crest(K: any, cf: any, s: number)
	local function g(x: number, y: number, w: number, h: number, rot: number)
		K.boxCF(cf * CF.new(x * s, y * s, 0.06) * CF.Angles(0, 0, rot), V3.new(w * s, h * s, 0.1), GOLD, Enum.Material.Metal)
	end
	-- a diamond outline, a solid core, a spike above, two sweeping wings, a stem below
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		g(math.cos(a + math.pi / 4) * 0.32, math.sin(a + math.pi / 4) * 0.32, 0.9, 0.14, a)
	end
	g(0, 0, 0.36, 0.36, math.pi / 4)
	g(0, 0.62, 0.16, 0.5, 0)
	g(0, 0.92, 0.26, 0.26, math.pi / 4)
	for _, sx in { -1, 1 } do
		g(sx * 0.62, 0.22, 0.6, 0.14, sx * 0.6)
		g(sx * 0.92, 0.52, 0.34, 0.12, sx * 1.2)
		g(sx * 0.5, -0.42, 0.44, 0.12, -sx * 0.7)
	end
	g(0, -0.72, 0.14, 0.44, 0)
end

--[[
	A hanging purple banner with a gold trim and the gold crest: an iron rod with
	finials on top, the cloth ending in a point. cf = the rod's center, facing +Z.
]]
local function banner(K: any, parent: any, cf: any, w: number, h: number)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local IRONB = C3.fromRGB(40, 36, 42)
	local pointH = w * 0.45
	K.cylCF(cf, w + 0.9, 0.35, IRONB, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		local b = K.part("Part", cf * CF.new(sx * (w / 2 + 0.5), 0, 0), V3.new(0.55, 0.55, 0.55), GOLD, Enum.Material.Metal)
		b.Shape = Enum.PartType.Ball
	end
	local body = h - pointH
	local cloth = K.boxCF(cf * CF.new(0, -body / 2 - 0.15, 0), V3.new(w, body, 0.14), PURPLE, FABRIC)
	cloth.Name = "BannerCloth"
	Geo.triangle(
		parent,
		(cf * CF.new(-w / 2, -body - 0.15, 0.07)).Position,
		(cf * CF.new(w / 2, -body - 0.15, 0.07)).Position,
		(cf * CF.new(0, -h - 0.15, 0.07)).Position,
		0.14,
		PURPLE,
		FABRIC,
		(cf.Rotation * V3.new(0, 0, 1)),
		{ CanCollide = false }
	)
	-- the gold trim: the sides, the top band, the point's edges
	for _, sx in { -1, 1 } do
		K.boxCF(cf * CF.new(sx * (w / 2 - 0.12), -body / 2 - 0.15, 0.09), V3.new(0.16, body, 0.04), GOLD, Enum.Material.Metal)
		local a = cf * CF.new(sx * (w / 2 - 0.12), -body - 0.15, 0.09)
		local b = cf * CF.new(0, -h - 0.05, 0.09)
		local d = b.Position - a.Position
		K.boxCF(
			CF.lookAt((a.Position + b.Position) / 2, b.Position, cf.LookVector * -1),
			V3.new(0.16, 0.04, d.Magnitude),
			GOLD,
			Enum.Material.Metal
		)
	end
	K.boxCF(cf * CF.new(0, -0.6, 0.09), V3.new(w, 0.16, 0.04), GOLD, Enum.Material.Metal)
	K.boxCF(cf * CF.new(0, -0.95, 0.09), V3.new(w - 0.6, 0.08, 0.04), PURPLE_D)
	crest(K, cf * CF.new(0, -body * 0.52, 0.07), w * 0.42)
end

--[[
	Glowing lava cracks on a face: fcf = the face's center frame (its Z out of
	the face), hx, hy = the face's half size; n zigzag cracks of 3-5 segments.
]]
local function cracks(K: any, fcf: any, hx: number, hy: number, n: number, rand: () -> number, thick: number)
	local LAVA = C3.fromRGB(255, 136, 44)
	for _ = 1, n do
		local x, y = (rand() - 0.5) * hx * 1.4, (rand() - 0.5) * hy * 1.4
		local a = rand() * math.pi * 2
		for _ = 1, 3 + math.floor(rand() * 3) do
			a += (rand() - 0.5) * 1.4
			local len = (0.3 + rand() * 0.4) * math.min(hx, hy) * 1.4
			local nx = math.clamp(x + math.cos(a) * len, -hx * 0.92, hx * 0.92)
			local ny = math.clamp(y + math.sin(a) * len, -hy * 0.92, hy * 0.92)
			local dx, dy = nx - x, ny - y
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 0.05 then
				local p = K.boxCF(
					fcf * CF.new((x + nx) / 2, (y + ny) / 2, 0.03) * CF.Angles(0, 0, math.atan2(dy, dx)),
					V3.new(l + thick, thick, 0.06),
					LAVA,
					NEON
				)
				p.CastShadow = false
			end
			x, y = nx, ny
		end
	end
end

-- The face of a box (cf, size) whose normal points most along `dir`: its center frame and half size.
local function bestFace(cf: any, size: any, dir: any): (any, number, number)
	local faces = {
		{ CF.new(0, 0, size.Z / 2), size.X / 2, size.Y / 2, CF.identity },
		{ CF.new(0, 0, -size.Z / 2), size.X / 2, size.Y / 2, CF.Angles(0, math.pi, 0) },
		{ CF.new(size.X / 2, 0, 0), size.Z / 2, size.Y / 2, CF.Angles(0, math.pi / 2, 0) },
		{ CF.new(-size.X / 2, 0, 0), size.Z / 2, size.Y / 2, CF.Angles(0, -math.pi / 2, 0) },
		{ CF.new(0, size.Y / 2, 0), size.X / 2, size.Z / 2, CF.Angles(-math.pi / 2, 0, 0) },
		{ CF.new(0, -size.Y / 2, 0), size.X / 2, size.Z / 2, CF.Angles(math.pi / 2, 0, 0) },
	}
	local best, bestDot = faces[1], -math.huge
	for _, f in faces do
		local n = (cf * f[1] * f[4]).LookVector * -1 -- a CFrame's LookVector is its -Z; the face's normal is its +Z
		local d = n:Dot(dir)
		if d > bestDot then
			best, bestDot = f, d
		end
	end
	return cf * best[1] * best[4], best[2], best[3]
end

--[[
	A giant stone king statue after the owner's concept art: a muscular body of
	grey stone blocks veined with glowing lava cracks, a crown, a bearded face
	with glowing eyes, layered shoulder plates, a purple tabard with the gold
	crest and a dark cape; one arm raises a glowing lava blaster, the other
	holds an open map forward. It stands on a stone pedestal with a purple
	banner and a fire line. ground = the pedestal's foot (front +Z); o = the
	side of the blaster arm (+1 = the statue's local +X, its left).
]]
local function giantStatue(K: any, parent: any, ground: any, o: number, seed: number)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local rand = lcg(seed)
	local k = 1.85
	local TONES = { C3.fromRGB(112, 108, 116), C3.fromRGB(98, 94, 102), C3.fromRGB(126, 122, 130), C3.fromRGB(86, 82, 92) }
	local DARKS = C3.fromRGB(64, 60, 70)
	local FIRE = C3.fromRGB(255, 140, 50)
	-- the pedestal: a bottom course, a block body, corner pilasters, a cap with a fire line, a banner
	local PW, PD, PH = 14, 12, 8.4
	K.boxCF(ground * CF.new(0, 0.6, 0), V3.new(PW + 1.4, 1.2, PD + 1.4), C3.fromRGB(70, 66, 78), SLATEM)
	K.boxCF(ground * CF.new(0, PH / 2, 0), V3.new(PW, PH, PD), VS.core)
	local rows = 5
	for r = 0, rows - 1 do
		local y0 = 1.2 + r * (PH - 2) / rows
		blockRow(K, ground * CF.new(0, y0, PD / 2 - 0.2), PW, (PH - 2) / rows, seed + r, FIRE)
		blockRow(K, ground * CF.new(0, y0, -PD / 2 + 0.2) * CF.Angles(0, math.pi, 0), PW, (PH - 2) / rows, seed + 10 + r)
		for _, sx in { -1, 1 } do
			blockRow(
				K,
				ground * CF.new(sx * (PW / 2 - 0.2), y0, 0) * CF.Angles(0, sx * math.pi / 2, 0),
				PD,
				(PH - 2) / rows,
				seed + 20 + r + sx
			)
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			K.boxCF(ground * CF.new(sx * (PW / 2 - 0.4), PH / 2, sz * (PD / 2 - 0.4)), V3.new(1.8, PH, 1.8), C3.fromRGB(78, 74, 88), SLATEM)
		end
	end
	K.boxCF(ground * CF.new(0, PH + 0.4, 0), V3.new(PW + 1.0, 0.8, PD + 1.0), VS.light, SLATEM)
	neon(K, ground * CF.new(0, PH - 0.1, PD / 2 + 0.52), V3.new(PW + 1.0, 0.16, 0.06), FIRE)
	for _, sx in { -1, 1 } do
		neon(K, ground * CF.new(sx * (PW / 2 + 0.52), PH - 0.1, 0), V3.new(0.06, 0.16, PD + 1.0), FIRE)
	end
	banner(K, parent, ground * CF.new(0, PH - 0.5, PD / 2 + 0.7), 5.2, 6.4)
	light(K, (ground * CF.new(0, PH - 1, PD / 2 + 3)).Position, FIRE, 12, 0.6)

	-- the statue, in design units (x k studs) on the pedestal top
	local feet = ground * CF.new(0, PH + 0.8, 0)
	local fwd = -feet.LookVector -- the statue faces its +Z (a CFrame's LookVector is its -Z)
	local function P(x: number, y: number, z: number): any
		return (feet * CF.new(x * k, y * k, z * k)).Position
	end
	local function tone(): any
		return TONES[1 + math.floor(rand() * #TONES)]
	end
	local function crackOn(cf: any, size: any, n: number)
		if n > 0 then
			local fcf, hx, hy = bestFace(cf, size, (fwd + V3.new(0, 0.25, 0)).Unit)
			cracks(K, fcf, hx, hy, n, rand, 0.15 * k)
		end
	end
	-- a block at (x, y, z) design units, size (w, h, d), turned by (rx, ry, rz)
	local function blk(x: number, y: number, z: number, w: number, h: number, d: number, n: number, rot: any?, color: any?)
		local cf = feet * CF.new(x * k, y * k, z * k) * (rot or CF.identity)
		local size = V3.new(w * k, h * k, d * k)
		K.boxCF(cf, size, color or tone(), SLATEM)
		crackOn(cf, size, n)
		return cf
	end
	-- a limb from a to b (world points), w x d thick (design units)
	local function limb(a: any, b: any, w: number, d: number, n: number, color: any?)
		local cf = CF.lookAt((a + b) / 2, b, fwd)
		local size = V3.new(w * k, d * k, (b - a).Magnitude + 0.3 * k)
		K.boxCF(cf, size, color or tone(), SLATEM)
		crackOn(cf, size, n)
		return cf
	end
	-- legs: boots, shins with knee guards, thick thighs
	for _, s in { -1, 1 } do
		blk(s * 1.9, 0.45, 0.35, 1.6, 0.9, 2.4, 0, nil, DARKS)
		blk(s * 1.9, 0.82, 1.45, 1.4, 0.5, 0.4, 0, nil, C3.fromRGB(78, 74, 84))
		local ankle, knee, hip = P(s * 1.9, 0.9, 0.2), P(s * 1.75, 3.7, 0.55), P(s * 1.05, 6.2, 0)
		limb(ankle, knee, 1.45, 1.55, 2)
		blk(s * 1.75, 3.7, 1.25, 1.3, 1.1, 0.5, 0, nil, C3.fromRGB(78, 74, 84))
		limb(knee, hip, 2.1, 2.15, 3)
	end
	-- hips, belt with a glowing buckle, the purple tabard and the cape
	blk(0, 6.4, 0, 3.9, 1.3, 2.2, 0)
	blk(0, 6.95, 0, 4.1, 0.6, 2.4, 0, nil, C3.fromRGB(60, 50, 46))
	K.boxCF(feet * CF.new(0, 6.95 * k, 1.22 * k) * CF.Angles(0, 0, math.pi / 4), V3.new(0.6 * k, 0.6 * k, 0.1 * k), FIRE, NEON)
	local tab = feet * CF.new(0, 5.0 * k, 1.25 * k) * CF.Angles(-0.1, 0, 0)
	K.boxCF(tab, V3.new(1.9 * k, 3.4 * k, 0.16 * k), PURPLE, FABRIC)
	Geo.triangle(
		parent,
		(tab * CF.new(-0.95 * k, -1.7 * k, 0.08 * k)).Position,
		(tab * CF.new(0.95 * k, -1.7 * k, 0.08 * k)).Position,
		(tab * CF.new(0, -2.4 * k, 0.08 * k)).Position,
		0.16 * k,
		PURPLE,
		FABRIC,
		tab.LookVector * -1,
		{ CanCollide = false }
	)
	for _, sx in { -1, 1 } do
		K.boxCF(tab * CF.new(sx * 0.88 * k, 0, 0.1 * k), V3.new(0.12 * k, 3.4 * k, 0.04 * k), GOLD, Enum.Material.Metal)
	end
	crest(K, tab * CF.new(0, 0.3 * k, 0.1 * k), 0.75 * k)
	local cape = feet * CF.new(0, 6.6 * k, -1.45 * k) * CF.Angles(0.1, 0, 0)
	K.boxCF(cape, V3.new(4.6 * k, 8.4 * k, 0.25 * k), PURPLE_D, FABRIC)
	for _, sx in { -1, 1 } do
		K.boxCF(
			cape * CF.new(sx * 2.3 * k, -0.5 * k, 0.4 * k) * CF.Angles(0, sx * 0.5, 0),
			V3.new(0.9 * k, 7.2 * k, 0.22 * k),
			PURPLE_D,
			FABRIC
		)
	end
	-- waist with abs, a broad chest with pecs, traps, layered shoulder plates
	blk(0, 8.05, 0.05, 3.2, 1.9, 2.0, 1)
	for _, ax in { -0.5, 0.5 } do
		for _, ay in { 7.4, 7.98, 8.56 } do
			blk(ax, ay, 1.1, 0.92, 0.5, 0.36, 1)
		end
	end
	blk(0, 9.95, 0.05, 4.9, 2.4, 2.4, 2)
	for _, s in { -1, 1 } do
		-- lats flaring out under the arms, the deltoids under the plates
		blk(s * 2.0, 8.9, -0.1, 1.2, 1.9, 1.9, 1, CF.Angles(0, 0, s * 0.3))
		blk(s * 2.75, 10.2, 0.1, 1.5, 1.4, 1.9, 1)
		blk(s * 1.08, 10.25, 1.3, 2.25, 1.5, 0.72, 2, CF.Angles(0, s * 0.12, 0))
		for i, pl in { { 11.15, 2.3, 1.05, 2.6, 0.22 }, { 10.55, 2.1, 0.55, 2.5, 0.45 }, { 10.1, 1.9, 0.45, 2.3, 0.7 } } do
			blk(
				s * (2.6 + i * 0.22),
				pl[1],
				0,
				pl[2],
				pl[3],
				pl[4],
				if i == 1 then 1 else 0,
				CF.Angles(0, 0, -s * pl[5]),
				if i == 1 then C3.fromRGB(122, 118, 128) else nil
			)
		end
	end
	blk(0, 11.25, -0.15, 2.7, 0.65, 1.5, 0)
	-- neck, head, brow, glowing eyes, nose, beard, crown
	blk(0, 11.7, 0, 1.3, 0.8, 1.3, 0)
	blk(0, 12.8, 0.1, 1.75, 1.95, 1.85, 1)
	blk(0, 13.15, 1.02, 1.8, 0.3, 0.42, 0, nil, C3.fromRGB(96, 92, 100))
	for _, s in { -1, 1 } do
		K.boxCF(feet * CF.new(s * 0.42 * k, 12.93 * k, 1.04 * k), V3.new(0.38 * k, 0.14 * k, 0.08 * k), FIRE, NEON)
	end
	blk(0, 12.6, 1.12, 0.32, 0.5, 0.32, 0)
	blk(0, 12.3, 1.1, 1.05, 0.2, 0.3, 0)
	blk(0, 11.9, 0.88, 1.65, 0.95, 0.65, 1)
	blk(0, 11.3, 0.95, 1.1, 0.65, 0.5, 0)
	blk(0, 10.9, 1.0, 0.6, 0.4, 0.4, 0)
	blk(0, 13.95, 0.1, 1.95, 0.55, 2.05, 1, nil, C3.fromRGB(122, 118, 128))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local h = if i == 2 then 0.85 else 0.6
		blk(math.cos(a) * 0.9, 14.25 + h / 2, 0.1 + math.sin(a) * 0.95, 0.38, h, 0.32, 0, CF.Angles(0, -a, 0), C3.fromRGB(122, 118, 128))
	end
	K.boxCF(
		feet * CF.new(0, 13.95 * k, 1.15 * k) * CF.Angles(0, 0, math.pi / 4),
		V3.new(0.32 * k, 0.32 * k, 0.1 * k),
		C3.fromRGB(190, 90, 255),
		NEON
	)
	-- the blaster arm: up and out, the forearm raised, a bracer, a fist holding a lava blaster
	local S, E, H = P(o * 2.85, 10.6, 0), P(o * 4.6, 11.0, 0.7), P(o * 4.95, 13.3, 1.15)
	limb(S, E, 1.9, 1.9, 3)
	blk(o * 3.7, 11.6, 0.7, 1.3, 0.95, 1.3, 1)
	limb(E, H, 1.6, 1.65, 2)
	local wrist = E:Lerp(H, 0.78)
	K.boxCF(CF.lookAt(wrist, H, fwd), V3.new(1.6 * k, 1.65 * k, 0.6 * k), C3.fromRGB(70, 66, 76), SLATEM)
	K.boxCF(CF.lookAt(H, H + (H - E).Unit, fwd), V3.new(1.5 * k, 1.5 * k, 1.3 * k), tone(), SLATEM)
	local gun, anchors = Kenney.gun(L, 10, "Magmacore")
	local gs = 7.6 * k / 5.56
	local dir = (feet.Rotation * V3.new(o * 0.18, 0.88, 0.42)).Unit
	local Z = -dir
	local X = (fwd - dir * fwd:Dot(dir)).Unit
	local Y = Z:Cross(X)
	local gunCf = CF.fromMatrix(H + dir * 0.2 * k, X, Y, Z) * CF.new(-anchors.hand * gs)
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * gs
			d.CFrame = gunCf * CF.new(d.CFrame.Position * gs) * d.CFrame.Rotation
		end
	end
	gun.Parent = parent
	-- the map arm: down and forward, holding an open map toward the visitors
	local S2, E2, H2 = P(-o * 2.85, 10.6, 0), P(-o * 3.45, 8.5, 1.3), P(-o * 2.6, 8.9, 3.1)
	limb(S2, E2, 1.9, 1.9, 3)
	blk(-o * 3.35, 9.9, 0.9, 1.2, 1.0, 1.3, 1)
	limb(E2, H2, 1.6, 1.65, 2)
	local wrist2 = E2:Lerp(H2, 0.75)
	K.boxCF(CF.lookAt(wrist2, H2, fwd), V3.new(1.6 * k, 1.65 * k, 0.6 * k), C3.fromRGB(70, 66, 76), SLATEM)
	K.boxCF(CF.lookAt(H2, H2 + (H2 - E2).Unit, fwd), V3.new(1.5 * k, 1.5 * k, 1.3 * k), tone(), SLATEM)
	local map = feet * CF.new(-o * 2.3 * k, 9.9 * k, 3.75 * k) * CF.Angles(0, o * 0.3, 0) * CF.Angles(-0.2, 0, 0)
	for _, sx in { -1, 1 } do
		local half = map * CF.new(sx * 0.75 * k, 0, 0) * CF.Angles(0, -sx * 0.18, 0)
		K.boxCF(half, V3.new(1.5 * k, 2.1 * k, 0.08 * k), C3.fromRGB(214, 188, 132))
		-- the map's drawing: coast lines, a dashed route, an X, a compass
		for j = 0, 2 do
			K.boxCF(
				half * CF.new((rand() - 0.5) * 0.8 * k, (0.6 - j * 0.5) * k, 0.05 * k) * CF.Angles(0, 0, (rand() - 0.5) * 1.2),
				V3.new((0.5 + rand() * 0.5) * k, 0.06 * k, 0.03 * k),
				C3.fromRGB(104, 74, 46)
			)
		end
		if sx > 0 then
			for _, r in { math.pi / 4, -math.pi / 4 } do
				K.boxCF(
					half * CF.new(0.2 * k, -0.3 * k, 0.06 * k) * CF.Angles(0, 0, r),
					V3.new(0.45 * k, 0.08 * k, 0.03 * k),
					C3.fromRGB(170, 44, 34)
				)
			end
		else
			for j = 0, 3 do
				K.boxCF(
					half * CF.new((-0.45 + j * 0.25) * k, (-0.5 + j * 0.2) * k, 0.06 * k),
					V3.new(0.16 * k, 0.06 * k, 0.03 * k),
					C3.fromRGB(170, 44, 34)
				)
			end
			for i = 0, 3 do
				K.boxCF(
					half
						* CF.new(-0.3 * k, 0.45 * k, 0.06 * k)
						* CF.Angles(0, 0, i * math.pi / 2)
						* CF.new(0, 0.12 * k, 0)
						* CF.Angles(0, 0, math.pi / 4),
					V3.new(0.1 * k, 0.1 * k, 0.03 * k),
					C3.fromRGB(104, 74, 46)
				)
			end
		end
	end
	light(K, (feet * CF.new(0, 9 * k, 4 * k)).Position, FIRE, 18, 0.5)
end

--[[
	The vault's "wow" layer (local frame of the vault: front +Z, 70 x 50 studs):
	a slate roof with fire towers, a stone gable over the entrance with two big
	crossed blasters and a glowing crystal, a big turning hologram blaster over
	the roof with floating crystals around it, giant ore crystals flanking the
	entrance, lava falls down both side walls into glowing pools, a rune circle
	on the forecourt and two searchlights.
]]
local function vaultWow(K: any, parent: any, origin: any)
	local Geo = L.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local FIRE = C3.fromRGB(255, 140, 50)
	local LAVA = C3.fromRGB(255, 96, 30)
	local SLATE = C3.fromRGB(52, 48, 60)
	local STONE = C3.fromRGB(104, 100, 120)
	local halfW, halfD = 35, 25
	local function at(x: number, y: number, z: number): any
		return origin * CF.new(x, y, z)
	end
	local function embers(part: any, color: any)
		local e = roblox.Instance.new("ParticleEmitter")
		e.Name = "Embers"
		e.Color = roblox.ColorSequence.new(color)
		e.Parent = part
	end
	pitchedRoof(K, parent, origin)
	-- fire towers on the back corners
	for _, sx in { -1, 1 } do
		local x, z = sx * (halfW - 3), -halfD + 3
		K.boxCF(at(x, 16, z), V3.new(7, 32, 7), STONE, SLATEM)
		K.boxCF(at(x, 32.4, z), V3.new(8.4, 1.2, 8.4), SLATE, SLATEM)
		for _, y in { 10, 20, 30 } do
			neon(K, at(x, y, z), V3.new(7.2, 0.3, 7.2), FIRE)
		end
		local flame = K.part("Part", at(x, 34.4, z), V3.new(4.6, 3.2, 4.6), FIRE, NEON)
		flame.Shape = Enum.PartType.Ball
		embers(flame, FIRE)
		light(K, (at(x, 36, z)).Position, FIRE, 24, 1.2)
	end
	-- the stone gable over the entrance: two triangles, a fire trim, crossed blasters, a crystal
	local zG = halfD - 1.2
	local base, peak = 24.0, 40
	for _, sx in { -1, 1 } do
		local a = (at(sx * 36, base, zG)).Position
		local b = (at(0, base, zG)).Position
		local c = (at(0, peak, zG)).Position
		Geo.triangle(parent, a, b, c, 2.6, STONE, nil, nil, { CanCollide = false })
		local rake = (c - a)
		local mid = (a + c) / 2
		K.boxCF(CF.lookAt(mid + V3.new(0, 0, 1.4), mid + V3.new(0, 0, 1.4) + rake), V3.new(0.35, 0.35, rake.Magnitude), FIRE, NEON)
	end
	for _, roll in { 0.55, -0.55 } do
		local gun = Kenney.gun(L, 10, "Magmacore")
		Concepts.present(gun, at(0, 30.6, zG + 2.4) * CF.Angles(0, 0, roll) * CF.Angles(0, -math.pi / 2, 0), 3.0, parent)
	end
	gableDetail(K, origin, zG)
	gemCluster(
		K,
		(at(0, 34.6, zG + 2.2)).Position,
		V3.new(0, 1, 0.35).Unit,
		V3.new(1, 0, 0),
		4.2,
		C3.fromRGB(240, 110, 50),
		C3.fromRGB(200, 70, 20)
	)
	light(K, (at(0, 33, zG + 6)).Position, FIRE, 22, 1.2)
	-- a big hologram blaster turning over the roof, its projector, floating crystals around it
	local holoGlow = C3.fromRGB(255, 120, 160)
	K.cylCF(at(0, 41.3, -6) * CF.Angles(0, 0, math.pi / 2), 0.8, 7, SLATE)
	K.cylCF(at(0, 41.75, -6) * CF.Angles(0, 0, math.pi / 2), 0.12, 6, holoGlow, NEON)
	local beam = K.cylCF(at(0, 50, -6) * CF.Angles(0, 0, math.pi / 2), 16.4, 5.6, holoGlow, NEON)
	beam.Transparency = 0.9
	local holo = Kenney.gun(L, 10, "Heartstone")
	holo.Name = "VaultHologram" -- turned by a script in the Studio test
	Concepts.present(holo, at(0, 63, -6) * CF.Angles(0, math.pi / 2 + 0.25, 0) * CF.Angles(0.12, 0, 0), 4.2, parent)
	local gems = roblox.Instance.new("Model")
	gems.Name = "VaultGems"
	gems.Parent = parent
	local KG = Concepts.kit(gems)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = (at(math.cos(a) * 16, 63 + math.sin(a * 2) * 2.5, -6 + math.sin(a) * 16)).Position
		KG.gem(p, V3.new(math.cos(a) * 0.3, 1, math.sin(a) * 0.3).Unit, 0.7, 2.6, C3.fromRGB(220, 70, 130), holoGlow)
	end
	-- giant ore crystals on plinths beside the entrance
	for _, side in { { -1, "Heartstone" }, { 1, "Stormcore" } } do
		local sx = side[1]
		local look = oreGlow(if side[2] == "Heartstone" then 10 else 9)
		local x, z = sx * 30, halfD + 7
		K.boxCF(at(x, 0.9, z), V3.new(7, 1.8, 7), VS.dark, SLATEM)
		K.boxCF(at(x, 1.95, z), V3.new(7.6, 0.3, 7.6), VS.light, SLATEM)
		neon(K, at(x, 1.75, z), V3.new(7.2, 0.12, 7.2), look.Glow)
		gemCluster(K, (at(x, 2.1, z)).Position, V3.new(0, 1, 0), V3.new(sx, 0, 0), 11, look.Body, look.Body:Lerp(C3.new(0, 0, 0), 0.35))
		light(K, (at(x, 7, z + 2)).Position, look.Glow, 20, 1.3)
	end
	-- lava falls down both side walls into glowing pools
	for _, sx in { -1, 1 } do
		for _, z in { -12, 8 } do
			local x = sx * (halfW - 0.6)
			neon(K, at(x, 11.5, z), V3.new(0.5, 21, 3.4), LAVA)
			neon(K, at(x + sx * 0.12, 11.5, z), V3.new(0.4, 21, 1.4), C3.fromRGB(255, 200, 90))
			K.boxCF(at(x + sx * 2.6, 0.4, z), V3.new(5.6, 0.8, 7), SLATE, SLATEM)
			local pool = neon(K, at(x + sx * 2.6, 0.82, z), V3.new(4.6, 0.12, 6), LAVA)
			embers(pool, FIRE)
			light(K, (at(x + sx * 3, 3, z)).Position, LAVA, 16, 1.2)
		end
	end
	-- a rune circle on the forecourt in front of the entrance, on a dark stone disc
	local cz = halfD + 8
	K.cylCF(at(0, 0.02, cz) * CF.Angles(0, 0, math.pi / 2), 0.08, 13, C3.fromRGB(46, 42, 56), SLATEM)
	for ring, r in { 5.6, 4.2 } do
		local n = 28
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2
			neon(
				K,
				at(math.cos(a) * r, 0.08, cz + math.sin(a) * r) * CF.Angles(0, -a, 0),
				V3.new(0.18, 0.05, 2 * math.pi * r / n * (ring == 1 and 0.85 or 0.6)),
				FIRE
			)
		end
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		neon(
			K,
			at(math.cos(a) * 4.9, 0.09, cz + math.sin(a) * 4.9) * CF.Angles(0, a + math.pi / 4, 0),
			V3.new(0.6, 0.06, 0.6),
			C3.fromRGB(255, 200, 110)
		)
	end
	neon(K, at(0, 0.1, cz) * CF.Angles(0, math.pi / 4, 0), V3.new(2.2, 0.06, 2.2), FIRE)
	-- two searchlights crossing over the roof
	for _, sx in { -1, 1 } do
		local base = at(sx * (halfW - 3), 33.2, halfD - 6)
		neon(
			K,
			base * CF.Angles(0, 0, -sx * 0.38) * CF.Angles(0.18, 0, 0) * CF.new(0, 32, 0),
			V3.new(2.2, 64, 2.2),
			C3.fromRGB(255, 220, 170),
			0.9
		)
	end
end

local function vault(K: any, parent: any, ground: any)
	podium(K, ground)
	local origin = ground * CF.new(0, PODIUM_H, 0)
	local S = 10
	local FIRE = C3.fromRGB(255, 140, 50)
	local function piece(key: string, cf: any, scale: number?, paint: any?)
		return Kit.piece(L, parent, key, origin * cf, scale or S, paint)
	end
	local W, D = 7, 5
	local halfW, halfD = W * S / 2, D * S / 2
	vaultFloor(K, origin)
	-- detailed stone walls on three sides (the outer faces look outward), columns in the open front
	stoneWall(
		K,
		origin * CF.new(0, 0, -halfD) * CF.Angles(0, math.pi, 0),
		2 * halfW - 2,
		22,
		6,
		{ inner = true, slits = true, sconces = true, seed = 11, innerDark = 0.4 }
	)
	for _, sx in { -1, 1 } do
		stoneWall(
			K,
			origin * CF.new(sx * (halfW - 4), 0, -1) * CF.Angles(0, sx * math.pi / 2, 0),
			42,
			22,
			6,
			{ inner = true, slits = true, sconces = true, seed = 20 + sx, innerDark = 0.4 }
		)
	end
	for _, x in { -halfW + S + 1, halfW - S - 1, -13, 13 } do
		piece("dungeon/column", CF.new(x, 0, halfD - 2), 12, function(_, c)
			return c:Lerp(C3.fromRGB(40, 36, 50), 0.42)
		end)
	end
	-- two tie beams with iron chandeliers (they stay clear of the vault door's top in the view from the entrance)
	for _, z in { -6, 12 } do
		K.boxCF(origin * CF.new(0, 22.5, z), V3.new(W * S - 4, 2.4, 2.4), VS.wood)
		for _, x in { -14, 14 } do
			chandelier(K, origin * CF.new(x, 21.3, z), 5.5)
		end
	end
	-- a carved stone lintel across the front: a band, dentils and a fire line
	K.boxCF(origin * CF.new(0, 21.6, halfD - 2), V3.new(W * S - 2, 3.2, 3.2), C3.fromRGB(118, 114, 134))
	K.boxCF(origin * CF.new(0, 23.4, halfD - 1.8), V3.new(W * S, 0.6, 3.8), C3.fromRGB(100, 96, 116))
	for i = 0, 44 do
		K.boxCF(origin * CF.new(-33 + i * 1.5, 19.75, halfD - 0.6), V3.new(0.6, 0.5, 0.6), C3.fromRGB(104, 100, 120))
	end
	vaultSign(K, parent, origin * CF.new(0, 17.9, halfD + 0.3))
	vaultGlazing(K, origin)
	-- ore banners on the back wall, fire bowls on the columns
	for i, x in { -23.2, -13.8, 13.8, 23.2 } do
		local body = oreGlow(({ 3, 6, 8, 10 })[i]).Body
		piece("dungeon/banner", CF.new(x, 7, -halfD + 11.5), 16, function(region, c)
			local _, sat = c:ToHSV()
			return if sat > 0.3 then body:Lerp(c, 0.2) else nil
		end)
	end
	for _, x in { -13, 13 } do
		banner(K, parent, origin * CF.new(x, 12.2, halfD + 1.35), 4.4, 8.6)
	end
	for _, x in { -halfW + S + 1, halfW - S - 1, -13, 13 } do
		K.cylCF(origin * CF.new(x, 13.6, halfD - 2) * CF.Angles(0, 0, math.pi / 2), 1, 3.4, C3.fromRGB(60, 56, 60))
		local flame = K.part("Part", origin * CF.new(x, 14.4, halfD - 2), V3.new(1.8, 1.6, 1.8), FIRE, NEON)
		flame.Shape = Enum.PartType.Ball
		local embers = roblox.Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Color = roblox.ColorSequence.new(FIRE)
		embers.Parent = flame
		light(K, (origin * CF.new(x, 15.5, halfD - 2)).Position, FIRE, 16, 1.1)
	end
	-- the cases on three stone steps (4 + 3 + 3), a lava channel in front of them
	local STONE = C3.fromRGB(116, 114, 132)
	local steps = {
		{ y = 0, z = -halfD + 24, levels = { 1, 2, 3, 4 } },
		{ y = 3.2, z = -halfD + 17, levels = { 5, 6, 7 } },
		{ y = 6.4, z = -halfD + 10, levels = { 8, 9, 10 } },
	}
	for k, st in steps do
		caseStep(K, origin, st.z, st.y + 3, 60 + k * 10)
		local n = #st.levels
		for k, level in st.levels do
			local x = (k - (n + 1) / 2) * 12
			display(K, parent, level, origin * CF.new(x, st.y + 3, st.z - 3.4), 0.72)
		end
	end
	neon(K, origin * CF.new(0, 0.05, -halfD + 27), V3.new(44, 0.12, 1.6), FIRE)
	K.boxCF(origin * CF.new(0, 0.1, -halfD + 27), V3.new(46, 0.1, 2.6), C3.fromRGB(40, 34, 36))
	-- the giant round vault door in the back wall, over the top step
	vaultDoor(K, origin * CF.new(0, 18.2, -halfD + 3.4), 6.6)
	-- a stone counter with a space console and a chest, the keeper and the prompt
	K.boxCF(origin * CF.new(0, 2, 5), V3.new(16, 4, 4), STONE, SLATEM)
	for i = 0, 3 do
		K.boxCF(origin * CF.new(-6 + i * 4, 2, 7.05), V3.new(3.4, 3, 0.2), VS.tiles[2 + i % 2], SLATEM)
	end
	K.boxCF(origin * CF.new(0, 4.05, 5), V3.new(16.4, 0.3, 4.4), C3.fromRGB(150, 86, 56))
	neon(K, origin * CF.new(0, 3.85, 7.25), V3.new(16.4, 0.12, 0.08), FIRE)
	monitor(K, origin * CF.new(-5, 4.2, 4.6), C3.fromRGB(255, 170, 80))
	counterBlaster(parent, origin * CF.new(3, 4.8, 5.4))
	blastsmith(
		K,
		parent,
		origin * CF.new(0, 0, 0.5),
		1.25,
		{ vest = C3.fromRGB(126, 54, 36), accent = FIRE, lens = C3.fromRGB(255, 176, 70) }
	)
	prompt(K, (origin * CF.new(0, 10.6, 0.5)).Position)
	for _, x in { -halfW + 6, halfW - 6 } do
		piece("dungeon/barrel", CF.new(x, 0, halfD - 7), 8)
	end
	light(K, (origin * CF.new(0, 16, -4)).Position, C3.fromRGB(255, 210, 160), 30, 0.6)
	vaultFacade(K, origin)
	vaultWallDecor(K, parent, origin)
	-- the inside, for the Studio test's darker interior lighting (an invisible zone)
	local zone = K.part("Part", origin * CF.new(0, 15, 0.5), V3.new(56, 30, 45), C3.new(0, 0, 0))
	zone.Name = "VaultInterior"
	zone.Transparency = 1
	vaultWow(K, parent, origin)
end

---------------------------------------------------------------- C: Neon Stall

local function stall(K: any, parent: any, origin: any)
	local NEONC = C3.fromRGB(190, 90, 255)
	local STRIPE = { C3.fromRGB(120, 54, 200), C3.fromRGB(34, 30, 50) }
	K.boxCF(origin * CF.new(0, -0.4, -3), V3.new(44, 0.8, 32), C3.fromRGB(38, 36, 52))
	neon(K, origin * CF.new(0, 0.05, 12.9), V3.new(44, 0.1, 0.3), NEONC)
	-- metal posts and beams, a roof slab with a neon edge
	for _, x in { -20, -7, 7, 20 } do
		for _, z in { 8, -16 } do
			post(K, origin * CF.new(x, 0, z), 13, NEONC)
		end
	end
	for _, z in { 8, -16 } do
		K.boxCF(origin * CF.new(0, 13.4, z), V3.new(42, 1.2, 1.2), STEEL)
	end
	K.boxCF(origin * CF.new(0, 14.4, -4), V3.new(44, 0.8, 27), C3.fromRGB(56, 58, 76))
	neon(K, origin * CF.new(0, 14.0, 9.6), V3.new(44.2, 0.3, 0.3), NEONC)
	-- a striped awning sloping down over the front
	local n = 11
	for i = 1, n do
		local x = -22 + (i - 0.5) * (44 / n)
		K.boxCF(origin * CF.new(x, 12.2, 11.6) * CF.Angles(0.5, 0, 0), V3.new(44 / n, 0.3, 5.2), STRIPE[i % 2 + 1])
		K.boxCF(origin * CF.new(x, 10.7, 13.9), V3.new(44 / n, 1.0, 0.25), STRIPE[i % 2 + 1])
	end
	neon(K, origin * CF.new(0, 10.15, 14.05), V3.new(44, 0.12, 0.12), NEONC)
	-- the sign on the roof, between two neon pillars
	label(K, origin * CF.new(0, 18.4, 8.5), V3.new(24, 5.2, 0.6), "BLASTERS", C3.fromRGB(22, 18, 34), C3.fromRGB(230, 190, 255))
	for _, y in { 15.6, 21.2 } do
		neon(K, origin * CF.new(0, y, 8.55), V3.new(25, 0.3, 0.7), NEONC)
	end
	-- the front counter, the keeper behind it, a two-tier case rack at the back (seen from the plaza)
	K.boxCF(origin * CF.new(0, 1.9, 5), V3.new(20, 3.8, 3.6), C3.fromRGB(48, 44, 68))
	K.boxCF(origin * CF.new(0, 3.95, 5), V3.new(20.6, 0.3, 4.2), DARK)
	neon(K, origin * CF.new(0, 3.75, 7.1), V3.new(20.6, 0.12, 0.08), NEONC)
	monitor(K, origin * CF.new(6.5, 4.1, 4.4), C3.fromRGB(220, 140, 255))
	counterBlaster(parent, origin * CF.new(-4, 4.7, 5.6))
	blastsmith(
		K,
		parent,
		origin * CF.new(0, 0, 0.2),
		1.25,
		{ vest = C3.fromRGB(96, 50, 170), accent = NEONC, lens = C3.fromRGB(250, 130, 255) }
	)
	prompt(K, (origin * CF.new(0, 10.6, 0.2)).Position)
	for tier = 0, 1 do
		local y = tier * 6.2
		K.boxCF(origin * CF.new(0, y + 0.3, -11.5), V3.new(40, 0.6, 7), C3.fromRGB(56, 52, 76))
		neon(K, origin * CF.new(0, y + 0.62, -8.05), V3.new(40, 0.08, 0.12), NEONC)
		for i = 1, 5 do
			display(K, parent, tier * 5 + i, origin * CF.new(-15.6 + (i - 1) * 7.8, y + 0.6, -11.5), 0.62)
		end
	end
	K.boxCF(origin * CF.new(0, 7, -15.6), V3.new(40, 14, 0.8), C3.fromRGB(34, 30, 48))
	light(K, (origin * CF.new(0, 11, -2)).Position, C3.fromRGB(230, 200, 255), 30, 1)
end

function Shop.build(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	L = Loader
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterShops"
	root.Parent = parent
	local K = Concepts.kit(root)
	K.boxCF(CF.new(200, -1.2, 10), V3.new(700, 1, 220), C3.fromRGB(96, 88, 92)) -- the plaza
	armory(K, root, CF.new(0, 0, 0))
	vault(K, root, CF.new(200, 0, 0))
	stall(K, root, CF.new(400, 0, 0))
	-- the keeper alone, for a close-up
	local Kc = Concepts.kit(root)
	blastsmith(
		Kc,
		root,
		CF.new(600, 0, 0),
		1.25,
		{ vest = C3.fromRGB(196, 92, 36), accent = C3.fromRGB(255, 150, 40), lens = C3.fromRGB(110, 230, 255) }
	)
	return root
end

--[[
	Scene "blaster_shop_lobby": a TEST placement of the Forge Vault in the lobby
	(preview only, nothing in the game changes). The vault, at 80 % size,
	stands at the end of the south road (z ~ 88..142, facing the plaza); the
	decorations inside its footprint (trees, flowers, lamps) are left out of
	the picture here and would be moved if the vault stays.
]]
Shop.LobbyCenter = { x = 0, z = 118, scale = 0.8 }
-- The two giant stone king statues in front of the side trees, lobby coordinates { x, z } (they face the plaza).
Shop.Statues = { { -43, 92 }, { 43, 92 } }
Shop.StatueUnit = 2.9

-- The jungle trees around it in lobby coordinates: { x, z, height, canopy radius, seed }.
Shop.Trees = {
	{ -29, 153, 48, 13, 1 },
	{ 29, 155, 52, 14, 2 },
	{ -45, 120, 40, 11, 3 },
	{ -47, 140, 44, 12, 4 },
	{ 45, 108, 40, 11, 5 },
	{ 46, 136, 44, 12, 6 },
}

function Shop.buildLobby(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	L = Loader
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	WorldBuilder.build(parent)
	local c = Shop.LobbyCenter
	-- leave out what stands inside the footprint (not the ground, roads or water)
	local removed = 0
	for _, d in parent:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local top = p.Y + d.Size.Y / 2
			if math.abs(p.X - c.x) < 36 and p.Z > 78 and p.Z < 147 and top > 0.45 and p.Y < 40 and d.Size.X < 60 and d.Size.Z < 60 then
				d.Transparency = 1
				removed += 1
			end
		end
	end
	print(string.format("lobby test: hid %d decoration parts in the vault footprint", removed))
	-- big jungle trees behind the vault and two on each side (decorations under them are hidden too)
	local trees = Shop.Trees
	for _, d in parent:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local p = d.CFrame.Position
			local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			for _, t in trees do
				if math.abs(p.X - t[1]) < 8 and math.abs(p.Z - t[2]) < 8 and p.Y + d.Size.Y / 2 > 0.45 and p.Y < 30 and big < 14 then
					d.Transparency = 1
					removed += 1
				end
			end
			for _, st in Shop.Statues do
				if
					d.Transparency < 1
					and math.abs(p.X - st[1]) < 10
					and math.abs(p.Z - st[2]) < 10
					and p.Y + d.Size.Y / 2 > 0.45
					and p.Y < 30
					and big < 14
				then
					d.Transparency = 1
					removed += 1
				end
			end
		end
	end
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterVaultTest"
	root.Parent = parent
	local KT = Concepts.kit(root)
	for _, t in trees do
		jungleTree(KT, V3.new(t[1], 0, t[2]), t[3], t[4], t[5])
	end
	for i, st in Shop.Statues do
		-- facing the plaza, turned a little toward the path; the blaster arm on the outer side
		local side = if st[1] < 0 then -1 else 1
		local feet = CF.new(st[1], 0, st[2]) * CF.Angles(0, math.pi + 0.3 * side, 0)
		giantStatue(KT, root, feet, -side, 900 + i)
		for _, sx in { -1, 1 } do
			bigFern(KT, (feet * CF.new(sx * 9, 0, 7.5)).Position, 5.5, 700 + i * 10 + sx)
		end
	end
	local holder = roblox.Instance.new("Model")
	vault(Concepts.kit(holder), holder, CF.identity)
	place(holder, CF.new(c.x, 0, c.z) * CF.Angles(0, math.pi, 0), c.scale, root)
	return root
end

--[[
	The ground around the vault in the Studio test (the lobby has its own): blocky
	grass cells in the lobby's voxel style (a few raised steps away from the
	vault), a cobbled path with curbs and lanterns from the podium steps, and
	flowers, grass tufts, rocks and bushes. s = the vault's scale.
]]
local function studioGround(K: any, s: number)
	local rand = lcg(404)
	local podX, podZ0, podZ1 = 42 * s + 1, -34 * s - 1, 48 * s
	local pathW = 10
	local GREENS = { C3.fromRGB(98, 170, 68), C3.fromRGB(88, 158, 60), C3.fromRGB(108, 180, 76), C3.fromRGB(82, 150, 58) }
	local function onPath(x: number, z: number, m: number): boolean
		return math.abs(x) < pathW / 2 + m and z > podZ1 - 2 and z < 100
	end
	local function onPodium(x: number, z: number, m: number): boolean
		return math.abs(x) < podX + m and z > podZ0 - m and z < podZ1 + m
	end
	local function level(x: number, z: number): number
		if onPath(x, z, 10) or onPodium(x, z, 10) then
			return 0
		end
		local f = math.sin(x * 0.045) + math.cos(z * 0.05) + math.sin((x + z) * 0.027)
		return if f > 1.3 then 0.9 elseif f > 0.55 then 0.45 else 0
	end
	local cell = 8
	for x = -124, 124 - cell, cell do
		for z = -100, 136 - cell, cell do
			local cx, cz = x + cell / 2, z + cell / 2
			-- skip only the cells the podium (or the path bed) covers completely
			local underPodium = math.abs(cx) + cell / 2 <= 42 * s and cz - cell / 2 >= -34 * s and cz + cell / 2 <= 42 * s
			local underPath = math.abs(cx) + cell / 2 <= pathW / 2 and cz - cell / 2 >= podZ1 - 2
			if not underPodium and not underPath then
				local h = level(cx, cz)
				local tone = GREENS[1 + math.floor(rand() * #GREENS)]:Lerp(C3.new(1, 1, 0.8), h * 0.08)
				K.boxCF(CF.new(cx, h - 1.5, cz), V3.new(cell, 3, cell), tone)
			end
		end
	end
	-- the cobbled path with a dark bed, curbs and lanterns
	K.boxCF(CF.new(0, -1.5, (podZ1 + 100) / 2), V3.new(pathW, 3, 100 - podZ1), C3.fromRGB(70, 64, 70))
	flagstones(K, CF.identity, -pathW / 2 + 0.6, pathW / 2 - 0.6, podZ1, 100, 0.12, {
		seed = 91,
		depth = 1.7,
		minLen = 1.4,
		lenVar = 1.3,
		gap = 0.14,
		tones = { C3.fromRGB(150, 140, 136), C3.fromRGB(132, 124, 122), C3.fromRGB(164, 154, 148), C3.fromRGB(120, 112, 112) },
		material = SLATEM,
	})
	for _, sx in { -1, 1 } do
		local z = podZ1
		while z < 100 do
			local len = 2 + rand() * 1.2
			K.boxCF(CF.new(sx * (pathW / 2 - 0.3), 0.15, z + len / 2), V3.new(0.7, 0.7, len - 0.12), VS.tiles[2], SLATEM)
			z += len
		end
		for _, lz in { podZ1 + 8, podZ1 + 22, podZ1 + 36 } do
			local base = CF.new(sx * (pathW / 2 + 1.4), 0, lz)
			K.boxCF(base * CF.new(0, 0.3, 0), V3.new(1.4, 0.6, 1.4), VS.dark, SLATEM)
			K.boxCF(base * CF.new(0, 3.3, 0), V3.new(0.6, 6, 0.6), C3.fromRGB(70, 46, 32))
			K.boxCF(base * CF.new(0, 6.5, 0), V3.new(1.5, 0.3, 1.5), C3.fromRGB(46, 40, 44))
			K.boxCF(base * CF.new(0, 7.3, 0), V3.new(1.2, 1.4, 1.2), C3.fromRGB(46, 40, 44))
			neon(K, base * CF.new(0, 7.3, 0), V3.new(0.9, 1.1, 1.3), C3.fromRGB(255, 196, 110))
			neon(K, base * CF.new(0, 7.3, 0), V3.new(1.3, 1.1, 0.9), C3.fromRGB(255, 196, 110))
			K.boxCF(base * CF.new(0, 8.15, 0), V3.new(1.7, 0.3, 1.7), C3.fromRGB(46, 40, 44))
			light(K, (base * CF.new(0, 7.3, 0)).Position, C3.fromRGB(255, 196, 110), 16, 0.9)
		end
	end
	-- flowers, grass tufts, rocks and bushes away from the vault and the path
	local function spot(): (number?, number?, number?)
		for _ = 1, 30 do
			local x, z = -110 + rand() * 220, -90 + rand() * 215
			local nearStatue = false
			for _, st in Shop.Statues do
				local sx, sz = -(st[1] - Shop.LobbyCenter.x), Shop.LobbyCenter.z - st[2]
				if math.abs(x - sx) < 13 and math.abs(z - sz) < 13 then
					nearStatue = true
				end
			end
			if not nearStatue and not onPodium(x, z, 4) and not onPath(x, z, 3) and (x * x + (z - 5) ^ 2) > 46 * 46 * s then
				return x, z, level(x, z)
			end
		end
		return nil, nil, nil
	end
	local PETALS = {
		C3.fromRGB(255, 120, 170),
		C3.fromRGB(255, 220, 90),
		C3.fromRGB(245, 245, 255),
		C3.fromRGB(180, 120, 255),
		C3.fromRGB(255, 90, 80),
	}
	for _ = 1, 70 do
		local x, z, h = spot()
		if x then
			local petal = PETALS[1 + math.floor(rand() * #PETALS)]
			for k = 0, 2 do
				local ox, oz = (rand() - 0.5) * 2.4, (rand() - 0.5) * 2.4
				K.boxCF(CF.new(x + ox, h + 0.45, z + oz), V3.new(0.2, 0.9, 0.2), C3.fromRGB(70, 140, 50))
				K.boxCF(CF.new(x + ox, h + 1.0, z + oz) * CF.Angles(0, rand() * 3, 0), V3.new(0.6, 0.35, 0.6), petal)
				if k == 0 then
					K.boxCF(CF.new(x, h + 0.12, z), V3.new(1.4, 0.24, 1.4), C3.fromRGB(76, 150, 56))
				end
			end
		end
	end
	for _ = 1, 110 do
		local x, z, h = spot()
		if x then
			local a = rand() * 3
			for k = 0, 1 do
				K.boxCF(
					CF.new(x, h + 0.6, z) * CF.Angles(0, a + k * 1.57, 0.2 - k * 0.4),
					V3.new(0.18, 1.3, 0.5),
					C3.fromRGB(86 + k * 12, 164, 60)
				)
			end
		end
	end
	for _ = 1, 26 do
		local x, z, h = spot()
		if x then
			local r = 1 + rand() * 1.8
			for k = 0, math.floor(rand() * 3) do
				local tone = C3.fromRGB(120, 118, 128):Lerp(C3.fromRGB(90, 88, 98), rand())
				K.boxCF(
					CF.new(x + (rand() - 0.5) * r, h + r * 0.25, z + (rand() - 0.5) * r) * CF.Angles(rand() * 0.4, rand() * 3, rand() * 0.4),
					V3.new(r * (1 + rand()), r * 0.8, r),
					tone,
					SLATEM
				)
			end
		end
	end
	for _ = 1, 22 do
		local x, z, h = spot()
		if x then
			for k = 0, 4 + math.floor(rand() * 3) do
				local o = V3.new((rand() - 0.5) * 3.2, rand() * 1.6, (rand() - 0.5) * 3.2)
				K.boxCF(
					CF.new(V3.new(x, h + 1.1, z) + o),
					V3.new(2.2, 2.2, 2.2),
					if rand() < 0.4 then C3.fromRGB(78, 158, 56) else C3.fromRGB(52, 128, 44)
				)
			end
		end
	end
end

--[[
	The Forge Vault alone for a Roblox Studio test place
	(tools/lune/export_vault_place.luau): the vault at 80 % size at the origin
	facing +Z, its six jungle trees, a grass ground and a stone path. Fixed up
	for the real engine: sign texts fill their plates, the particle emitters
	get real settings, solid parts collide, a real ProximityPrompt replaces the
	painted [E] sign, and the hologram gets a pivot at its center.
]]
function Shop.buildStudio(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	L = Loader
	local c = Shop.LobbyCenter
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterVault"
	root.Parent = parent
	local holder = roblox.Instance.new("Model")
	holder.Name = "Vault"
	vault(Concepts.kit(holder), holder, CF.identity)
	place(holder, CF.identity, c.scale, root)
	local trees = roblox.Instance.new("Model")
	trees.Name = "JungleTrees"
	trees.Parent = root
	local KT = Concepts.kit(trees)
	for _, t in Shop.Trees do
		-- lobby coordinates -> the vault's frame (the lobby turns it to face the plaza)
		jungleTree(KT, V3.new(-(t[1] - c.x), 0, c.z - t[2]), t[3], t[4], t[5])
	end
	local statues = roblox.Instance.new("Model")
	statues.Name = "GuardianStatues"
	statues.Parent = root
	local KS = Concepts.kit(statues)
	for i, st in Shop.Statues do
		local x = -(st[1] - c.x)
		local side = if x < 0 then -1 else 1
		local feet = CF.new(x, 0, c.z - st[2]) * CF.Angles(0, -0.3 * side, 0)
		giantStatue(KS, statues, feet, side, 900 + i)
		for _, sx in { -1, 1 } do
			bigFern(KT, (feet * CF.new(sx * 9, 0, 7.5)).Position, 5.5, 700 + i * 10 + sx)
		end
	end
	local ground = roblox.Instance.new("Model")
	ground.Name = "Ground"
	ground.Parent = root
	studioGround(Concepts.kit(ground), c.scale)

	-- the real engine: texts, particles, collisions, the prompt, the hologram pivot
	for _, d in root:GetDescendants() do
		if d:IsA("SurfaceGui") then
			d.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			d.PixelsPerStud = 40
			d.LightInfluence = 0
			local t = d:FindFirstChildWhichIsA("TextLabel")
			if t then
				t.Size = roblox.UDim2.fromScale(1, 1)
				t.BackgroundTransparency = 1
				t.TextScaled = true
			end
		elseif d:IsA("ParticleEmitter") then
			local hot = d.Name ~= "GunSpark"
			d.Rate = if d.Name == "Embers" then 14 else 10
			d.Lifetime = roblox.NumberRange.new(0.8, 2)
			d.Speed = roblox.NumberRange.new(if hot then 2 else 0.3, if hot then 5 else 1)
			d.SpreadAngle = roblox.Vector2.new(25, 25)
			d.Acceleration = roblox.Vector3.new(0, if hot then 3 else 0.5, 0)
			d.LightEmission = 1
			d.Size = roblox.NumberSequence.new({
				roblox.NumberSequenceKeypoint.new(0, if hot then 0.35 else 0.25),
				roblox.NumberSequenceKeypoint.new(1, 0),
			})
			d.Transparency = roblox.NumberSequence.new({
				roblox.NumberSequenceKeypoint.new(0, 0.1),
				roblox.NumberSequenceKeypoint.new(1, 1),
			})
			pcall(function()
				d.Shape = Enum.ParticleEmitterShape.Box
				d.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			end)
		elseif d:IsA("BasePart") then
			if d.Name == "FakePrompt" then
				d.Parent = nil
			elseif d.Name == "GlassPane" then
				d.CanCollide = true
			elseif
				d.Transparency < 0.5
				and d.Material ~= Enum.Material.Neon
				and (math.max(d.Size.X, d.Size.Y, d.Size.Z) >= 4 or (d.Size.Y <= 0.7 and d.Size.X >= 1.2 and d.Size.Z >= 1.2))
			then
				d.CanCollide = true
			end
		end
	end
	-- the shop prompt on the counter
	local promptPart = roblox.Instance.new("Part")
	promptPart.Name = "ShopPrompt"
	promptPart.Anchored = true
	promptPart.CanCollide = false
	promptPart.Transparency = 1
	promptPart.Size = V3.new(2, 2, 2)
	promptPart.CFrame = CF.new(0, 4.4, 4.4)
	promptPart.Parent = root
	local pp = roblox.Instance.new("ProximityPrompt")
	pp.ActionText = "Open Shop"
	pp.ObjectText = "Blaster Vault"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = promptPart
	-- the hologram and its gems turn around their own middle
	for _, name in { "VaultHologram", "VaultGems" } do
		local m = root:FindFirstChild(name, true)
		if m then
			local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					lo = lo:Min(d.CFrame.Position)
					hi = hi:Max(d.CFrame.Position)
				end
			end
			-- an invisible center part as PrimaryPart, so GetPivot() turns it around its middle
			local center = roblox.Instance.new("Part")
			center.Name = "Pivot"
			center.Anchored = true
			center.CanCollide = false
			center.Transparency = 1
			center.Size = V3.new(0.2, 0.2, 0.2)
			center.CFrame = CF.new((lo + hi) / 2)
			center.Parent = m
			m.PrimaryPart = center
		end
	end
	return root
end

-- The Studio test ground (in the vault's design frame, front +Z), shared with export_vault_game_place.luau.
Shop.studioGround = function(Loader: any, parent: any, s: number)
	Concepts.init(Loader)
	CF = Loader.CFrame
	L = Loader
	studioGround(Concepts.kit(parent), s)
end

return Shop
