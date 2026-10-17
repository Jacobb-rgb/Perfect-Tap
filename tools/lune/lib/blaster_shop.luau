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
local function display(K: any, parent: any, level: number, cf: any, s: number)
	local look = oreGlow(level)
	local w, d = 7.6 * s, 4.4 * s
	K.boxCF(cf * CF.new(0, 0.35, 0), V3.new(w, 0.7, d), DARK)
	neon(K, cf * CF.new(0, 0.72, 0), V3.new(w + 0.1, 0.06, d + 0.1), look.Glow)
	neon(K, cf * CF.new(0, 0.72 + 2.2 * s, 0), V3.new(w * 0.8, 4.4 * s, d * 0.7), look.Glow, 0.95) -- a soft glow over the case
	crate(parent, level, cf * CF.new(0, 0.76, 0) * CF.Angles(0, -math.pi / 2, 0), s)
	label(K, cf * CF.new(0, 0.35, d / 2 + 0.03), V3.new(1.7, 0.5, 0.04), "LV " .. level, DARK, look.Glow)
	light(K, (cf * CF.new(0, 3, 2)).Position, look.Glow, 8, 0.8)
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
	label(K, CF.new(at + V3.new(-2.5, 0, 0)), V3.new(1.4, 1.4, 0.12), "E", C3.fromRGB(245, 245, 250), C3.fromRGB(30, 30, 40))
	label(K, CF.new(at + V3.new(0.95, 0, 0)), V3.new(5.2, 1.4, 0.12), "BLASTER SHOP", C3.fromRGB(22, 22, 32), C3.fromRGB(255, 255, 255))
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
	local STONE = C3.fromRGB(124, 120, 140)
	local LIGHT = C3.fromRGB(150, 146, 166)
	local DARKS = C3.fromRGB(92, 88, 108)
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
			return C3.fromRGB(80, 76, 92)
		end
		return if rand() < 0.5 then STONE:Lerp(LIGHT, rand() * 0.8) else STONE:Lerp(DARKS, rand() * 0.8)
	end
	box(0, height / 2, 0, length, height, thick, C3.fromRGB(62, 58, 72)) -- the mortar core
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
					box((a + b) / 2, y, zf + f * 0.12, b - a - 0.16, bh - 0.16, 0.5, tone())
				end
				x += len
			end
		end
		-- string course, cornice with dentils
		box(0, y0 + bh * 6.5, zf + f * 0.3, length, 0.45, 0.8, LIGHT:Lerp(STONE, 0.4))
		box(0, height - 0.45, f * 0.4, length + 1.0, 0.9, thick + 1.4, C3.fromRGB(110, 106, 126))
		local n = math.floor(length / 1.4)
		for i = 0, n - 1 do
			box(-half + 0.7 + i * 1.4, height - 1.15, zf + f * 0.55, 0.6, 0.5, 0.6, C3.fromRGB(104, 100, 120))
		end
	end
	box(0, height + 0.25, 0, length + 0.6, 0.5, thick + 0.8, C3.fromRGB(96, 92, 110))
	-- outer face: pilasters, sconces, rune slits, moss drips
	local zo = thick / 2
	local bays = math.max(1, math.floor(length / 10 + 0.5))
	local bay = length / bays
	for k = 0, bays do
		local x = -half + k * bay
		box(x, height / 2, zo + 0.6, 1.8, height - 1, 1.2, C3.fromRGB(136, 132, 152))
		box(x, 1.2, zo + 0.8, 2.6, 2.4, 1.8, DARKS)
		box(x, height - 1.6, zo + 0.8, 2.6, 1.0, 1.8, C3.fromRGB(144, 140, 160))
		if opts.sconces and k % 2 == 1 then
			box(x, 11.8, zo + 1.6, 0.4, 0.4, 1.4, C3.fromRGB(40, 38, 44))
			local flame = K.part("Part", cf * CF.new(x, 12.6, zo + 2.2), V3.new(1.1, 1.3, 1.1), FIRE, NEON)
			flame.Shape = Enum.PartType.Ball
		end
		if opts.slits and k < bays then
			local xs = x + bay / 2
			box(xs, 14.6, zo + 0.35, 1.9, 6.4, 0.7, C3.fromRGB(70, 66, 80))
			box(xs, 14.6, zo + 0.42, 0.55, 5.2, 0.7, FIRE, NEON)
			box(xs, 18.1, zo + 0.5, 2.6, 0.6, 0.9, C3.fromRGB(144, 140, 160))
		end
	end
	for _ = 1, math.floor(length / 6) do
		local x = -half + rand() * length
		local len = 1 + rand() * 3
		box(x, height - 1.6 - len / 2, zo + 0.42, 0.5, len, 0.25, MOSS)
	end
end

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
	-- a slate roof with a glowing edge, over the beams
	K.boxCF(at(0, 24.6, -1), V3.new(2 * halfW + 2, 1.2, 2 * halfD + 2), SLATE)
	neon(K, at(0, 24.05, halfD), V3.new(2 * halfW + 2.2, 0.25, 0.3), FIRE)
	-- fire towers on the back corners
	for _, sx in { -1, 1 } do
		local x, z = sx * (halfW - 3), -halfD + 3
		K.boxCF(at(x, 16, z), V3.new(7, 32, 7), STONE)
		K.boxCF(at(x, 32.4, z), V3.new(8.4, 1.2, 8.4), SLATE)
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
	K.cluster(
		(at(0, 33.6, zG + 1.6)).Position,
		V3.new(0, 1, 0.35).Unit,
		V3.new(1, 0, 0),
		4.2,
		C3.fromRGB(230, 90, 40),
		C3.fromRGB(255, 190, 90)
	)
	light(K, (at(0, 33, zG + 6)).Position, FIRE, 22, 1.2)
	-- a big hologram blaster turning over the roof, its projector, floating crystals around it
	local holoGlow = C3.fromRGB(255, 120, 160)
	K.cylCF(at(0, 25.6, -6) * CF.Angles(0, 0, math.pi / 2), 0.8, 8, SLATE)
	K.cylCF(at(0, 26.05, -6) * CF.Angles(0, 0, math.pi / 2), 0.12, 7, holoGlow, NEON)
	local beam = K.cylCF(at(0, 37.5, -6) * CF.Angles(0, 0, math.pi / 2), 23, 6.4, holoGlow, NEON)
	beam.Transparency = 0.9
	local holo = Kenney.gun(L, 10, "Heartstone")
	Concepts.present(holo, at(0, 56, -6) * CF.Angles(0, math.pi / 2 + 0.25, 0) * CF.Angles(0.12, 0, 0), 4.2, parent)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = (at(math.cos(a) * 16, 56 + math.sin(a * 2) * 2.5, -6 + math.sin(a) * 16)).Position
		K.gem(p, V3.new(math.cos(a) * 0.3, 1, math.sin(a) * 0.3).Unit, 0.7, 2.6, C3.fromRGB(220, 70, 130), holoGlow)
	end
	-- giant ore crystals on plinths beside the entrance
	for _, side in { { -1, "Heartstone" }, { 1, "Stormcore" } } do
		local sx = side[1]
		local look = oreGlow(if side[2] == "Heartstone" then 10 else 9)
		local x, z = sx * 30, halfD + 7
		K.boxCF(at(x, 0.9, z), V3.new(7, 1.8, 7), STONE)
		neon(K, at(x, 1.85, z), V3.new(7.2, 0.12, 7.2), look.Glow)
		K.cluster(
			(at(x, 1.8, z)).Position,
			V3.new(0, 1, 0),
			V3.new(sx, 0, 0),
			11,
			look.Body:Lerp(C3.new(0, 0, 0), 0.25),
			look.Body:Lerp(look.Glow, 0.3)
		)
		light(K, (at(x, 7, z + 2)).Position, look.Glow, 20, 1.3)
	end
	-- lava falls down both side walls into glowing pools
	for _, sx in { -1, 1 } do
		for _, z in { -12, 8 } do
			local x = sx * (halfW - 0.6)
			neon(K, at(x, 11.5, z), V3.new(0.5, 21, 3.4), LAVA)
			neon(K, at(x + sx * 0.12, 11.5, z), V3.new(0.4, 21, 1.4), C3.fromRGB(255, 200, 90))
			K.boxCF(at(x + sx * 2.6, 0.4, z), V3.new(5.6, 0.8, 7), SLATE)
			local pool = neon(K, at(x + sx * 2.6, 0.82, z), V3.new(4.6, 0.12, 6), LAVA)
			embers(pool, FIRE)
			light(K, (at(x + sx * 3, 3, z)).Position, LAVA, 16, 1.2)
		end
	end
	-- a rune circle on the forecourt in front of the entrance
	local cz = halfD + 8
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

local function vault(K: any, parent: any, origin: any)
	local S = 10
	local FIRE = C3.fromRGB(255, 140, 50)
	local function piece(key: string, cf: any, scale: number?, paint: any?)
		return Kit.piece(L, parent, key, origin * cf, scale or S, paint)
	end
	local W, D = 7, 5
	local halfW, halfD = W * S / 2, D * S / 2
	K.boxCF(origin * CF.new(0, -0.5, 4), V3.new(W * S + 8, 1, D * S + 18), C3.fromRGB(64, 60, 70))
	-- detailed stone walls on three sides (the outer faces look outward), columns in the open front
	stoneWall(
		K,
		origin * CF.new(0, 0, -halfD) * CF.Angles(0, math.pi, 0),
		2 * halfW - 2,
		22,
		6,
		{ inner = true, slits = true, sconces = true, seed = 11 }
	)
	for _, sx in { -1, 1 } do
		stoneWall(
			K,
			origin * CF.new(sx * (halfW - 4), 0, -1) * CF.Angles(0, sx * math.pi / 2, 0),
			42,
			22,
			6,
			{ inner = true, slits = true, sconces = true, seed = 20 + sx }
		)
	end
	for _, x in { -halfW + S + 1, halfW - S - 1, -13, 13 } do
		piece("dungeon/column", CF.new(x, 0, halfD - 2), 12)
	end
	for _, z in { -halfD + 12, 0 } do
		K.boxCF(origin * CF.new(0, 21.5, z), V3.new(W * S - 4, 2.4, 2.4), C3.fromRGB(150, 86, 56))
	end
	-- a carved stone lintel across the front: a band, dentils and a fire line
	K.boxCF(origin * CF.new(0, 21.6, halfD - 2), V3.new(W * S - 2, 3.2, 3.2), C3.fromRGB(118, 114, 134))
	K.boxCF(origin * CF.new(0, 23.4, halfD - 1.8), V3.new(W * S, 0.6, 3.8), C3.fromRGB(100, 96, 116))
	for i = 0, 44 do
		K.boxCF(origin * CF.new(-33 + i * 1.5, 19.75, halfD - 0.6), V3.new(0.6, 0.5, 0.6), C3.fromRGB(104, 100, 120))
	end
	for _, x in { -20, 0, 20 } do
		K.boxCF(origin * CF.new(x, 22.8, -2), V3.new(2.4, 2.4, D * S - 2), C3.fromRGB(132, 74, 48))
	end
	label(K, origin * CF.new(0, 17.6, halfD - 0.2), V3.new(26, 5, 0.8), "BLASTER VAULT", C3.fromRGB(58, 34, 26), C3.fromRGB(255, 200, 110))
	neon(K, origin * CF.new(0, 20.3, halfD - 0.2), V3.new(27, 0.4, 0.9), FIRE)
	neon(K, origin * CF.new(0, 14.9, halfD - 0.2), V3.new(27, 0.4, 0.9), FIRE)
	-- ore banners on the back wall, fire bowls on the columns
	for i, x in { -27, -14, 14, 27 } do
		local body = oreGlow(({ 3, 6, 8, 10 })[i]).Body
		piece("dungeon/banner", CF.new(x, 7, -halfD + 11.5), 16, function(region, c)
			local _, sat = c:ToHSV()
			return if sat > 0.3 then body:Lerp(c, 0.2) else nil
		end)
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
	for _, st in steps do
		K.boxCF(origin * CF.new(0, (st.y + 3) / 2, st.z - 4), V3.new(50, st.y + 3, 8), STONE)
		neon(K, origin * CF.new(0, st.y + 3.02, st.z - 0.02), V3.new(50.2, 0.08, 0.2), FIRE)
		local n = #st.levels
		for k, level in st.levels do
			local x = (k - (n + 1) / 2) * 12
			display(K, parent, level, origin * CF.new(x, st.y + 3, st.z - 3.4), 0.72)
		end
	end
	neon(K, origin * CF.new(0, 0.05, -halfD + 27), V3.new(44, 0.12, 1.6), FIRE)
	K.boxCF(origin * CF.new(0, 0.1, -halfD + 27), V3.new(46, 0.1, 2.6), C3.fromRGB(40, 34, 36))
	-- a stone counter with a space console and a chest, the keeper and the prompt
	K.boxCF(origin * CF.new(0, 2, 5), V3.new(16, 4, 4), STONE)
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
	light(K, (origin * CF.new(0, 16, -4)).Position, C3.fromRGB(255, 210, 160), 40, 1.1)
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
			if math.abs(p.X - c.x) < 33 and p.Z > 85 and p.Z < 145 and top > 0.45 and p.Y < 40 and d.Size.X < 60 and d.Size.Z < 60 then
				d.Transparency = 1
				removed += 1
			end
		end
	end
	print(string.format("lobby test: hid %d decoration parts in the vault footprint", removed))
	-- big jungle trees behind the vault and two on each side (decorations under them are hidden too)
	local trees = {
		{ -29, 153, 48, 13, 1 },
		{ 29, 155, 52, 14, 2 },
		{ -45, 120, 40, 11, 3 },
		{ -47, 140, 44, 12, 4 },
		{ 45, 108, 40, 11, 5 },
		{ 46, 136, 44, 12, 6 },
	}
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
		end
	end
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterVaultTest"
	root.Parent = parent
	local KT = Concepts.kit(root)
	for _, t in trees do
		jungleTree(KT, V3.new(t[1], 0, t[2]), t[3], t[4], t[5])
	end
	local holder = roblox.Instance.new("Model")
	vault(Concepts.kit(holder), holder, CF.identity)
	place(holder, CF.new(c.x, 0, c.z) * CF.Angles(0, math.pi, 0), c.scale, root)
	return root
end

return Shop
