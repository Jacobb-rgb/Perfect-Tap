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

local function vault(K: any, parent: any, origin: any)
	local S = 10
	local FIRE = C3.fromRGB(255, 140, 50)
	local function piece(key: string, cf: any, scale: number?, paint: any?)
		return Kit.piece(L, parent, key, origin * cf, scale or S, paint)
	end
	local W, D = 7, 5
	local halfW, halfD = W * S / 2, D * S / 2
	K.boxCF(origin * CF.new(0, -0.5, 4), V3.new(W * S + 8, 1, D * S + 18), C3.fromRGB(64, 60, 70))
	-- stone walls (two rows) on three sides, columns and a beam across the open front
	for i = 1, W do
		local x = -halfW + (i - 0.5) * S
		for row = 0, 1 do
			piece("dungeon/wall", CF.new(x, row * 11, -halfD))
		end
	end
	for j = 2, D do
		local z = -halfD + (j - 1) * S
		for _, sx in { -1, 1 } do
			for row = 0, 1 do
				piece("dungeon/wall", CF.new(sx * (halfW - S / 2), row * 11, z))
			end
		end
	end
	for _, x in { -halfW + S + 1, halfW - S - 1, -13, 13 } do
		piece("dungeon/column", CF.new(x, 0, halfD - 2), 12)
	end
	for _, z in { -halfD + 12, 0, halfD - 2 } do
		K.boxCF(origin * CF.new(0, 21.5, z), V3.new(W * S - 4, 2.4, 2.4), C3.fromRGB(150, 86, 56))
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
		piece("dungeon/banner", CF.new(x, 7, -halfD + 10.4), 16, function(region, c)
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

return Shop
