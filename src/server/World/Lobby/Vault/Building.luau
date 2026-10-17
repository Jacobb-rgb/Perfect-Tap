--[[
	The Blaster Vault's outside: the stone podium with its front steps, the
	stone-brick walls, the front columns with fire bowls and banners, the glass
	front with the doorway, the rough BLASTER VAULT sign, the facade bays with
	crystal niches, the pitched slate roof, both gables (crossed blasters and a
	medallion in front, a rose window at the back), the fire towers, the
	hologram blaster over the roof, the giant crystals, the lava falls, the
	rune circle and the searchlights.

	Design frame (the vault is built at design size and scaled down by the
	package): `ground` = the podium's foot center, front = +Z; the floor
	inside (`origin`) is PODIUM_H above it. Podium x -42..42, z -34..48.
]]

local Kit = require(script.Parent.Kit)

local Building = {}

local C = Kit.C
local V3 = Vector3.new
local CF = CFrame.new

Building.PODIUM_H = 1.6

---------------------------------------------------------------- stone

local function stoneTone(rng: any): Color3
	local stone, light, dark = Color3.fromRGB(98, 92, 110), Color3.fromRGB(122, 116, 136), Color3.fromRGB(72, 68, 84)
	local t = rng:next()
	if t < 0.07 then
		return C.Moss:Lerp(stone, rng:next() * 0.4)
	elseif t < 0.11 then
		return Color3.fromRGB(62, 58, 72)
	end
	return if rng:next() < 0.5 then stone:Lerp(light, rng:next() * 0.8) else stone:Lerp(dark, rng:next() * 0.8)
end

-- Staggered brick rows on one face of a wall (face frame: X along the wall, +Z out of the face).
local function brickFace(
	m: Model,
	face: CFrame,
	length: number,
	y0: number,
	y1: number,
	rows: number,
	minLen: number,
	rng: any,
	darken: number
)
	local half = length / 2
	local bh = (y1 - y0) / rows
	for r = 0, rows - 1 do
		local y = y0 + (r + 0.5) * bh
		local x = -half - (if r % 2 == 1 then minLen * 0.5 else 0)
		while x < half do
			local len = minLen + rng:next() * 2
			local a, b = math.max(x, -half), math.min(x + len, half)
			if b - a > 0.8 then
				local tone = stoneTone(rng)
				if darken > 0 then
					tone = tone:Lerp(Color3.new(0, 0, 0), darken)
				end
				Kit.bit(m, face * CF((a + b) / 2, y, 0.12), V3(b - a - 0.16, bh - 0.16, 0.5), tone, Kit.SLATE)
			end
			x += len
		end
	end
end

--[[
	A stone wall: a dark core (it collides), staggered bricks on the outer face
	(+Z) and the inner face, a base course of big blocks, a string course, a
	cornice, and on the outer face pilasters with fire sconces and glowing rune
	slits between them. cf = the wall's bottom center, its length along X.
]]
local function stoneWall(m: Model, cf: CFrame, length: number, height: number, thick: number, opts: { [string]: any })
	local rng = Kit.rng("Wall" .. tostring(opts.seed or 1))
	local half = length / 2
	Kit.block(m, cf * CF(0, height / 2, 0), V3(length, height, thick), C.Core, Kit.SLATE, Kit.solid())
	local outer = cf * CF(0, 0, thick / 2)
	local inner = cf * CF(0, 0, -thick / 2) * CFrame.Angles(0, math.pi, 0)
	-- base course on the outer face
	local x = -half
	while x < half - 0.2 do
		local len = math.min(half - x, 4.6 + rng:next() * 2.4)
		Kit.bit(
			m,
			outer * CF(x + len / 2, 1.1, 0.3),
			V3(len - 0.22, 2.0, 0.9),
			C.StoneDark:Lerp(Color3.fromRGB(98, 92, 110), rng:next() * 0.4),
			Kit.SLATE
		)
		x += len
	end
	brickFace(m, outer, length, 2.2, height - 1.4, opts.outerRows or 7, 4.2, rng, 0)
	if opts.inner then
		brickFace(m, inner, length, 0.4, height - 1.4, 5, 5.2, rng, 0.4)
	end
	-- string course and cornice (both faces), the coping
	Kit.bit(m, outer * CF(0, 2.2 + (height - 3.6) * 0.5, 0.3), V3(length, 0.45, 0.8), C.StoneLight:Lerp(C.StoneDark, 0.4), Kit.SLATE)
	Kit.block(m, cf * CF(0, height - 0.45, 0), V3(length + 1.0, 0.9, thick + 1.4), Color3.fromRGB(88, 82, 100), Kit.SLATE)
	Kit.block(m, cf * CF(0, height + 0.25, 0), V3(length + 0.6, 0.5, thick + 0.8), Color3.fromRGB(74, 70, 86), Kit.SLATE)
	-- pilasters, sconces, rune slits on the outer face
	local bays = math.max(1, math.floor(length / 10 + 0.5))
	local bay = length / bays
	for k = 0, bays do
		local px = -half + k * bay
		Kit.bit(m, outer * CF(px, height / 2, 0.6), V3(1.8, height - 1, 1.2), Color3.fromRGB(106, 100, 120), Kit.SLATE)
		Kit.bit(m, outer * CF(px, 1.2, 0.8), V3(2.6, 2.4, 1.8), C.StoneDark, Kit.SLATE)
		if opts.sconces and k % 2 == 1 then
			Kit.bit(m, outer * CF(px, 11.8, 1.6), V3(0.4, 0.4, 1.4), C.Iron)
			local flame = Kit.ball(m, (outer * CF(px, 12.6, 2.2)).Position, 1.1, C.Fire, Kit.NEON)
			flame.Name = "Sconce"
		end
		if opts.slits and k < bays then
			local sx = px + bay / 2
			Kit.bit(m, outer * CF(sx, 14.6, 0.35), V3(1.9, 6.4, 0.7), Color3.fromRGB(70, 66, 80), Kit.SLATE)
			Kit.glow(m, outer * CF(sx, 14.6, 0.42), V3(0.55, 5.2, 0.7), C.Fire)
			Kit.bit(m, outer * CF(sx, 18.1, 0.5), V3(2.6, 0.6, 0.9), Color3.fromRGB(112, 106, 126), Kit.SLATE)
		end
	end
	-- moss drips under the cornice
	for _ = 1, math.floor(length / 12) do
		local mx = -half + rng:next() * length
		local len = 1 + rng:next() * 3
		Kit.bit(m, outer * CF(mx, height - 1.6 - len / 2, 0.42), V3(0.5, len, 0.25), C.Moss)
	end
end

-- A row of face blocks (a podium side, a step): cf = the strip's bottom center, X along it, +Z outward.
local function blockRow(m: Model, cf: CFrame, length: number, height: number, rng: any, rune: Color3?)
	local x, i = -length / 2, 0
	while x < length / 2 - 0.05 do
		local len = math.min(length / 2 - x, 4.6 + rng:next() * 2.4)
		local tone = C.Tiles[1 + math.floor(rng:next() * #C.Tiles)]:Lerp(C.StoneDark, 0.25)
		Kit.bit(m, cf * CF(x + len / 2, height / 2, 0), V3(len - 0.14, height - 0.14, 0.6), tone, Kit.SLATE)
		if rune and i % 3 == 1 and len > 3 then
			Kit.glow(m, cf * CF(x + len / 2, height / 2, 0.31), V3(0.9, 0.18, 0.04), rune)
		end
		x += len
		i += 1
	end
end

---------------------------------------------------------------- podium and steps

--[[
	The podium: a core with a flagstone top (one slab, grout lines and a few
	loose stones), block faces with rune inlays, a coping rim, three front steps
	between two cheek walls with braziers.
]]
function Building.podium(m: Model, ground: CFrame)
	local rng = Kit.rng("Podium")
	local X0, X1, Z0, Z1 = -42, 42, -34, 42
	local H = Building.PODIUM_H
	local function at(x: number, y: number, z: number): CFrame
		return ground * CF(x, y, z)
	end
	local top = Kit.block(m, at(0, (H - 0.1) / 2, (Z0 + Z1) / 2), V3(X1 - X0, H - 0.1, Z1 - Z0), C.Tiles[2], Kit.SLATE, Kit.solid())
	top.Name = "PodiumTop"
	-- grout lines on the top (rows every 3.2, staggered cuts every 4-6) and some loose stones
	for z = Z0 + 3.2, Z1 - 1, 3.2 do
		Kit.bit(m, at(0, H - 0.08, z), V3(X1 - X0 - 1.6, 0.04, 0.16), C.Core, Kit.SLATE)
	end
	for _ = 1, 26 do
		local x, z = X0 + 2 + rng:next() * (X1 - X0 - 4), Z0 + 2 + rng:next() * (Z1 - Z0 - 4)
		if math.abs(x) > 29 or z > 26 or z < -26 then
			local tone = C.Tiles[1 + math.floor(rng:next() * #C.Tiles)]
			if rng:next() < 0.25 then
				tone = tone:Lerp(C.Moss, 0.5)
			end
			Kit.bit(m, at(x, H - 0.05, z), V3(2.4 + rng:next() * 2, 0.12, 2.8), tone, Kit.SLATE)
		end
	end
	-- block faces (the front split by the steps), coping rim
	local SW = 15.6
	for _, seg in { { X0, -SW }, { SW, X1 } } do
		blockRow(m, at((seg[1] + seg[2]) / 2, 0, Z1 - 0.2), seg[2] - seg[1], H, rng, C.Fire)
		Kit.bit(m, at((seg[1] + seg[2]) / 2, H - 0.1, Z1 - 0.3), V3(seg[2] - seg[1] + 0.6, 0.4, 1.4), C.StoneLight, Kit.SLATE)
	end
	blockRow(m, at(0, 0, Z0 + 0.2) * CFrame.Angles(0, math.pi, 0), X1 - X0, H, rng, nil)
	Kit.bit(m, at(0, H - 0.1, Z0 + 0.3), V3(X1 - X0 + 0.6, 0.4, 1.4), C.StoneLight, Kit.SLATE)
	for _, sx in { -1, 1 } do
		blockRow(m, at(sx * (X1 - 0.2), 0, (Z0 + Z1) / 2) * CFrame.Angles(0, sx * math.pi / 2, 0), Z1 - Z0, H, rng, C.Fire)
		Kit.bit(m, at(sx * (X1 - 0.3), H - 0.1, (Z0 + Z1) / 2), V3(1.4, 0.4, Z1 - Z0 + 0.6), C.StoneLight, Kit.SLATE)
	end
	-- the front steps, a fire line on the top nose
	for k = 1, 3 do
		local h = H * (3 - k + 1) / 3
		local z0 = Z1 + (k - 1) * 2
		Kit.block(m, at(0, h / 2, z0 + 1), V3(2 * SW - 1, h, 2), C.Core, Kit.SLATE, Kit.solid())
		Kit.bit(m, at(0, h - 0.12, z0 + 1), V3(2 * SW - 1.2, 0.3, 1.9), C.StoneLight, Kit.SLATE)
	end
	Kit.glow(m, at(0, H + 0.03, Z1 + 0.15), V3(2 * SW - 1.2, 0.06, 0.2), C.Fire)
	-- cheek walls with braziers
	for _, sx in { -1, 1 } do
		local x = sx * SW
		Kit.block(m, at(x, (H + 1.2) / 2, Z1 + 3), V3(2.4, H + 1.2, 6), C.StoneDark, Kit.SLATE)
		Kit.bit(m, at(x, H + 1.35, Z1 + 3), V3(2.8, 0.3, 6.4), C.StoneLight, Kit.SLATE)
		Kit.bit(m, at(x, H + 2.1, Z1 + 4.6), V3(1.6, 1.2, 1.6), C.StoneDark, Kit.SLATE)
		Kit.drum(m, at(x, H + 3.1, Z1 + 4.6), 0.9, 2.6, Color3.fromRGB(46, 42, 48), Kit.METAL)
		local flame = Kit.ball(m, (at(x, H + 3.9, Z1 + 4.6)).Position, 1.9, C.Fire, Kit.NEON)
		flame.Name = "Brazier"
	end
end

---------------------------------------------------------------- walls and front

function Building.walls(m: Model, origin: CFrame)
	stoneWall(
		m,
		origin * CF(0, 0, -25) * CFrame.Angles(0, math.pi, 0),
		68,
		22,
		6,
		{ inner = true, slits = true, sconces = true, seed = 11, outerRows = 6 }
	)
	for _, sx in { -1, 1 } do
		stoneWall(
			m,
			origin * CF(sx * 31, 0, -1) * CFrame.Angles(0, sx * math.pi / 2, 0),
			42,
			22,
			6,
			{ inner = true, slits = true, sconces = true, seed = 20 + sx }
		)
	end
end

-- A front column (base, shaft with two flutes, capital, abacus) with a fire bowl on top.
local function column(m: Model, base: CFrame)
	local stone = Color3.fromRGB(70, 66, 82)
	Kit.block(m, base * CF(0, 0.7, 0), V3(6, 1.4, 6), C.StoneDark, Kit.SLATE)
	Kit.block(m, base * CF(0, 6.6, 0), V3(4.4, 10.4, 4.4), stone, Kit.SLATE)
	for _, sx in { -1, 1 } do
		Kit.bit(m, base * CF(sx * 1.1, 6.6, 2.21), V3(0.5, 9.4, 0.06), C.Core, Kit.SLATE)
	end
	Kit.block(m, base * CF(0, 12.4, 0), V3(5.6, 1.2, 5.6), Color3.fromRGB(86, 82, 98), Kit.SLATE)
	Kit.block(m, base * CF(0, 13.4, 0), V3(6.2, 0.8, 6.2), C.StoneLight, Kit.SLATE)
	Kit.drum(m, base * CF(0, 14.3, 0), 1, 3.4, Color3.fromRGB(60, 56, 60), Kit.METAL)
	local flame = Kit.ball(m, (base * CF(0, 15.1, 0)).Position, 1.8, C.Fire, Kit.NEON)
	flame.Name = "FireBowl"
	return flame
end

--[[
	The front: four columns with fire bowls, a carved lintel, purple banners on
	the two inner columns, the glass front (sills, a doorway, a transom row).
	Returns the fire bowl flames (for embers).
]]
function Building.front(m: Model, origin: CFrame): { BasePart }
	local flames: { BasePart } = {}
	for _, x in { -24, 24, -13, 13 } do
		table.insert(flames, column(m, origin * CF(x, 0, 23)))
	end
	-- the lintel: a stone beam, a band, dentils
	Kit.block(m, origin * CF(0, 21.6, 23), V3(66, 3.2, 3.2), Color3.fromRGB(96, 90, 110), Kit.SLATE)
	Kit.block(m, origin * CF(0, 23.4, 23.2), V3(68, 0.6, 3.8), Color3.fromRGB(80, 76, 94), Kit.SLATE)
	for i = 0, 21 do
		Kit.bit(m, origin * CF(-31.5 + i * 3, 19.75, 24.4), V3(0.9, 0.5, 0.6), Color3.fromRGB(80, 76, 94), Kit.SLATE)
	end
	for _, x in { -13, 13 } do
		Kit.banner(m, origin * CF(x, 12.2, 25.55), 4.4, 8.6)
	end
	-- glass between the columns: steel frames, stone sills, the doorway in the middle
	local z = 20.9
	local function pane(x0: number, x1: number, y0: number, y1: number)
		local p = Kit.block(
			m,
			origin * CF((x0 + x1) / 2, (y0 + y1) / 2, z),
			V3(x1 - x0, y1 - y0, 0.25),
			C.GlassTint,
			Kit.GLASS,
			Kit.decor({ Transparency = 0.6, Reflectance = 0.12 })
		)
		p.Name = "GlassPane"
	end
	local function bar(x0: number, x1: number, y0: number, y1: number)
		Kit.bit(m, origin * CF((x0 + x1) / 2, (y0 + y1) / 2, z), V3(x1 - x0, y1 - y0, 0.6), C.SteelDark, Kit.METAL)
	end
	for _, sx in { -1, 1 } do
		local x0, x1 = math.min(sx * 16, sx * 21), math.max(sx * 16, sx * 21)
		Kit.bit(m, origin * CF((x0 + x1) / 2, 0.8, z), V3(5, 1.6, 1.2), C.StoneDark, Kit.SLATE)
		pane(x0, x1, 1.6, 12.6)
		bar((x0 + x1) / 2 - 0.15, (x0 + x1) / 2 + 0.15, 1.6, 12.6)
		bar(x0, x1, 7.0, 7.3)
		local c0, c1 = math.min(sx * 4.9, sx * 10), math.max(sx * 4.9, sx * 10)
		Kit.bit(m, origin * CF((c0 + c1) / 2, 0.5, z), V3(5.1, 1.0, 1.2), C.StoneDark, Kit.SLATE)
		pane(c0, c1, 1.0, 12.6)
		bar((c0 + c1) / 2 - 0.15, (c0 + c1) / 2 + 0.15, 1.0, 12.6)
		bar(math.min(sx * 4.4, sx * 4.9), math.max(sx * 4.4, sx * 4.9), 0, 11.6)
		Kit.glow(m, origin * CF(sx * 4.35, 5.8, z + 0.35), V3(0.12, 11.4, 0.08), C.Fire)
	end
	bar(-4.9, 4.9, 11, 11.6)
	Kit.glow(m, origin * CF(0, 10.95, z + 0.35), V3(8.8, 0.12, 0.08), C.Fire)
	pane(-4.9, 4.9, 11.6, 12.6)
	bar(-27, 27, 12.6, 13.4)
	Kit.glow(m, origin * CF(0, 13.0, z + 0.32), V3(54, 0.14, 0.06), C.Fire)
	local posts = { -27, -24, -19, -13, -7, 0, 7, 13, 19, 24, 27 }
	for i = 1, #posts - 1 do
		pane(posts[i], posts[i + 1], 13.4, 19.8)
	end
	for _, x in posts do
		bar(x - 0.2, x + 0.2, 13.4, 19.8)
	end
	bar(-27, 27, 19.8, 20.1)
	return flames
end

--[[
	The BLASTER VAULT sign: a dark stone board with pointed ends, a jagged
	stone frame with glowing cracks, iron corner brackets, heavy lettering,
	glass crystals around it. cf = its center, facing +Z.
]]
function Building.sign(m: Model, cf: CFrame)
	local rng = Kit.rng("Sign")
	local W, H = 27, 5.4
	local half, hh = W / 2, H / 2
	local tip = half + 2.8
	local board = Kit.block(m, cf, V3(W, H, 1.0), Color3.fromRGB(34, 30, 38), Kit.SLATE)
	board.Name = "SignBoard"
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			Kit.tri(
				m,
				(cf * CF(sx * half, sy * hh, 0.5)).Position,
				(cf * CF(sx * half, 0, 0.5)).Position,
				(cf * CF(sx * tip, 0, 0.5)).Position,
				1.0,
				Color3.fromRGB(34, 30, 38),
				Kit.SLATE,
				cf.LookVector * -1
			)
		end
	end
	Kit.label(
		m,
		cf * CF(0, 0, 0.55),
		V3(24, 4.0, 0.12),
		"BLASTER VAULT",
		Color3.fromRGB(46, 20, 14),
		Color3.fromRGB(255, 196, 96),
		Enum.Font.LuckiestGuy
	)
	for _, sy in { -1, 1 } do
		Kit.glow(m, cf * CF(0, sy * 2.15, 0.62), V3(24, 0.12, 0.06), C.Fire)
		-- the jagged frame (big stones, a little tilted)
		local x = -half - 0.4
		while x < half + 0.4 do
			local len = 2.6 + rng:next() * 2
			local tone = C.Tiles[1 + math.floor(rng:next() * #C.Tiles)]
			Kit.bit(
				m,
				cf * CF(x + len / 2, sy * (hh + 0.25), 0.3) * CFrame.Angles(0, 0, (rng:next() - 0.5) * 0.16),
				V3(len - 0.12, 0.8 + rng:next() * 0.3, 1.5),
				tone,
				Kit.SLATE
			)
			x += len
		end
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local a = (cf * CF(sx * half, sy * hh, 0.3)).Position
			local b = (cf * CF(sx * tip, 0, 0.3)).Position
			Kit.beam(m, a, b, 0.8, 1.5, C.Tiles[2], Kit.SLATE, nil, cf.LookVector * -1)
			-- an iron corner bracket
			local c = cf * CF(sx * (half - 0.9), sy * (hh - 0.6), 0.68)
			Kit.bit(m, c * CF(sx * 0.3, 0, 0), V3(1.8, 0.45, 0.12), C.Iron, Kit.METAL)
			Kit.bit(m, c * CF(sx * 0.65, -sy * 0.5, 0), V3(0.45, 1.4, 0.12), C.Iron, Kit.METAL)
		end
	end
	for _, p in { { -9, 1 }, { -2, -1 }, { 6, 1 }, { 11, -1 } } do
		Kit.glow(m, cf * CF(p[1], p[2] * (hh + 0.25), 1.07) * CFrame.Angles(0, 0, 0.5), V3(0.9, 0.09, 0.05), C.Fire)
	end
	-- crystals: big clusters on the points, small shards on the top edge
	for _, sx in { -1, 1 } do
		Kit.gemCluster(
			m,
			(cf * CF(sx * (tip - 0.6), 0.2, 0.2)).Position,
			(cf.Rotation * V3(sx * 0.7, 1, 0.2)).Unit,
			cf.Rotation * V3(sx, 0, 0),
			4.4,
			C.OrangeCrystal,
			C.OrangeCore,
			3
		)
	end
	for i, x in { -8.5, -3.2, 3.6, 8.8 } do
		local s = 1.4 + (i % 2) * 0.9
		Kit.glassShard(
			m,
			(cf * CF(x, hh + 0.5, 0.3)).Position,
			(cf.Rotation * V3((rng:next() - 0.5) * 0.6, 1, 0.15)).Unit,
			s * 0.32,
			s,
			C.OrangeCrystal,
			C.OrangeCore
		)
	end
end

-- The facade bays beside the entrance: a stone wall with a lit niche holding a glass ore crystal.
function Building.facade(m: Model, origin: CFrame)
	local rng = Kit.rng("Facade")
	for _, side in { { -1, 7 }, { 1, 9 } } do
		local sx = side[1]
		local look = Kit.Levels[side[2]]
		local cx = sx * 30.5
		local base = origin * CF(cx, 0, 21.5)
		Kit.block(m, base * CF(0, 10, 0), V3(7, 20, 3), C.Core, Kit.SLATE, Kit.solid())
		brickFace(m, base * CF(0, 0, 1.5), 7, 0.4, 19, 7, 3.0, rng, 0)
		Kit.block(m, base * CF(0, 19.6, 0), V3(7.8, 0.8, 3.8), Color3.fromRGB(88, 82, 100), Kit.SLATE)
		local zf = 1.5
		Kit.bit(m, base * CF(0, 8.6, zf + 0.06), V3(3.6, 9.2, 0.14), Color3.fromRGB(22, 18, 26))
		for _, jx in { -2.1, 2.1 } do
			Kit.bit(m, base * CF(jx, 8.6, zf + 0.35), V3(0.6, 9.2, 0.7), C.StoneLight, Kit.SLATE)
		end
		for i = 0, 4 do
			local a = i / 4 * math.pi
			Kit.bit(
				m,
				base * CF(math.cos(a) * 2.1, 13.2 + math.sin(a) * 2.1, zf + 0.35) * CFrame.Angles(0, 0, a),
				V3(0.6, 1.6, 0.7),
				C.StoneLight,
				Kit.SLATE
			)
		end
		Kit.bit(m, base * CF(0, 3.9, zf + 0.5), V3(4.6, 0.5, 1.2), C.StoneLight, Kit.SLATE)
		Kit.gemCluster(
			m,
			(base * CF(0, 4.15, zf + 0.25)).Position,
			V3(0, 1, 0),
			base.RightVector,
			3.8,
			look.Body,
			look.Body:Lerp(Color3.new(0, 0, 0), 0.35),
			3
		)
		Kit.glow(m, base * CF(0, 4.17, zf + 0.75), V3(4.4, 0.06, 0.3), look.Glow)
		Kit.glow(m, base * CF(0, 16.4, zf + 0.12) * CFrame.Angles(0, 0, math.pi / 4), V3(0.9, 0.9, 0.12), C.Fire)
	end
end

---------------------------------------------------------------- roof and gables

--[[
	The pitched roof: slate tile rows on an underlay from the eaves (x +-37,
	y 23.6) to the ridge (y 40), a ridge cap with a fire line, eave fascias,
	rafters underneath, friezes over the side walls, a crystal finial.
]]
function Building.roof(m: Model, origin: CFrame)
	local rng = Kit.rng("Roof")
	local EX, EY, RY = 37, 23.6, 40
	local ZB, ZF = -29.5, 26
	local len = ZF - ZB
	local zc = (ZB + ZF) / 2
	local slope = math.sqrt(EX * EX + (RY - EY) ^ 2)
	for _, sx in { -1, 1 } do
		local eave = origin * V3(sx * EX, EY, 0)
		local d = origin.Rotation * V3(-sx * EX, RY - EY, 0).Unit
		local nrm = origin.Rotation * V3(sx * (RY - EY), EX, 0).Unit
		local back = d:Cross(nrm)
		local function frame(s: number, out: number, z: number): CFrame
			return CFrame.fromMatrix(eave + d * s + nrm * out + origin.Rotation * V3(0, 0, z), d, nrm, back)
		end
		Kit.block(m, frame(slope / 2, -0.25, zc), V3(slope + 0.4, 0.5, len), C.Core, Kit.SLATE, Kit.ghost())
		local rows = 8
		local rowW = slope / rows
		for r = 0, rows - 1 do
			local seg = 11 + rng:next() * 4
			local z = ZB - (if r % 2 == 1 then seg / 2 else 0)
			while z < ZF - 0.05 do
				local a, b = math.max(z, ZB), math.min(z + seg, ZF)
				if b - a > 0.6 then
					local tone = C.Roof[1 + math.floor(rng:next() * #C.Roof)]
					Kit.bit(m, frame((r + 0.5) * rowW, 0.22 + r * 0.02, (a + b) / 2), V3(rowW - 0.14, 0.44, b - a - 0.14), tone, Kit.SLATE)
				end
				z += seg
			end
		end
		Kit.bit(m, origin * CF(sx * (EX + 0.3), EY - 0.4, zc), V3(0.6, 1.2, len + 0.4), C.RoofEdge, Kit.SLATE)
		Kit.glow(m, origin * CF(sx * (EX + 0.62), EY - 0.85, zc), V3(0.06, 0.18, len + 0.4), C.Fire)
		for _, z in { -24, -13, -2, 9, 20 } do
			Kit.bit(m, frame(slope / 2 - 1.5, -0.95, z), V3(slope - 4, 0.9, 1.0), C.Wood)
		end
		Kit.block(m, origin * CF(sx * 31, 23.45, -1.5), V3(6.2, 1.7, 51), C.StoneDark, Kit.SLATE)
		Kit.glow(m, origin * CF(sx * 34.15, 23.6, -1.5), V3(0.08, 0.22, 51), C.Fire)
	end
	Kit.block(m, origin * CF(0, RY + 0.35, zc), V3(2.4, 1.0, len + 0.6), C.RoofEdge, Kit.SLATE, Kit.ghost())
	Kit.glow(m, origin * CF(0, RY + 0.9, zc), V3(0.3, 0.12, len + 0.6), C.Fire)
	Kit.gemCluster(
		m,
		(origin * CF(0, RY + 0.8, ZB + 0.6)).Position,
		origin.Rotation * V3(0, 1, -0.3).Unit,
		origin.RightVector,
		3.2,
		C.OrangeCrystal,
		C.OrangeCore,
		3
	)
end

-- The back gable: a stone band, two stone triangles with fire rakes, a rose window.
function Building.backGable(m: Model, origin: CFrame)
	local zG = -27.4
	Kit.block(m, origin * CF(0, 23.3, zG), V3(69, 1.0, 2.6), C.StoneLight, Kit.SLATE)
	for _, sx in { -1, 1 } do
		local a = (origin * CF(sx * 34.4, 23.4, zG)).Position
		local b = (origin * CF(0, 23.4, zG)).Position
		local c = (origin * CF(0, 39.3, zG)).Position
		Kit.tri(m, a, b, c, 2.4, C.Tiles[2], Kit.SLATE)
		local mid = (a + c) / 2 + origin.Rotation * V3(0, 0, -1.3)
		Kit.beam(m, mid - (c - a) / 2, mid + (c - a) / 2, 0.35, 0.35, C.Fire, Kit.NEON)
	end
	local rose = origin * CF(0, 30.5, zG - 1.25) * CFrame.Angles(0, math.pi, 0)
	Kit.glow(m, rose * CF(0, 0, -0.05), V3(6.6, 6.6, 0.1), Color3.fromRGB(200, 80, 30))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Kit.bit(m, rose * CFrame.Angles(0, 0, a) * CF(3.7, 0, 0.1), V3(1.0, 3.0, 0.7), C.StoneLight, Kit.SLATE)
	end
	for i = 0, 3 do
		Kit.bit(m, rose * CFrame.Angles(0, 0, i * math.pi / 4) * CF(0, 0, 0.12), V3(6.4, 0.35, 0.35), C.StoneDark, Kit.SLATE)
	end
end

--[[
	The front gable: stone triangles, brick courses, a base cornice with
	dentils, raking cornices with fire lines, a dark medallion with a fire ring
	behind two crossed lava blasters and an orange crystal, crystal acroteria.
]]
function Building.frontGable(m: Model, origin: CFrame)
	local rng = Kit.rng("Gable")
	local zG = 23.8
	local zf = zG + 1.3
	for _, sx in { -1, 1 } do
		local a = (origin * CF(sx * 36, 24.0, zG)).Position
		local b = (origin * CF(0, 24.0, zG)).Position
		local c = (origin * CF(0, 40, zG)).Position
		Kit.tri(m, a, b, c, 2.6, Color3.fromRGB(70, 66, 84), Kit.SLATE)
	end
	-- brick courses (wider bricks than the walls)
	local y, row = 24.7, 0
	while y < 38.4 do
		local hw = 36 * (40 - (y + 0.65)) / 16 - 1.4
		local x = -hw - (if row % 2 == 1 then 2.4 else 0)
		while x < hw do
			local len = 4.6 + rng:next() * 2.4
			local a, b = math.max(x, -hw), math.min(x + len, hw)
			if b - a > 0.8 then
				Kit.bit(
					m,
					origin * CF((a + b) / 2, y, zf + 0.12),
					V3(b - a - 0.14, 1.16, 0.3),
					C.Tiles[1 + math.floor(rng:next() * #C.Tiles)],
					Kit.SLATE
				)
			end
			x += len
		end
		y += 1.3
		row += 1
	end
	Kit.bit(m, origin * CF(0, 24.2, zf + 0.3), V3(73, 0.8, 1.4), C.StoneLight, Kit.SLATE)
	for i = 0, 23 do
		Kit.bit(m, origin * CF(-34.5 + i * 3, 23.65, zf + 0.45), V3(0.9, 0.45, 0.6), C.StoneDark, Kit.SLATE)
	end
	for _, sx in { -1, 1 } do
		local a = (origin * CF(sx * 36, 24.4, zf + 0.5)).Position
		local c = (origin * CF(0, 40.2, zf + 0.5)).Position
		Kit.beam(m, a, c, 1.0, 0.9, C.StoneLight, Kit.SLATE, nil, origin.LookVector * -1)
		Kit.beam(m, a + origin.LookVector * -0.9, c + origin.LookVector * -0.9, 0.35, 0.35, C.Fire, Kit.NEON)
		Kit.gemCluster(
			m,
			(origin * CF(sx * 35.6, 24.6, zf + 0.4)).Position,
			origin.Rotation * V3(sx * 0.3, 1, 0).Unit,
			origin.RightVector * sx,
			2.4,
			C.OrangeCrystal,
			C.OrangeCore,
			2
		)
	end
	-- the medallion, the crossed blasters, the crystal over them
	local md = origin * CF(0, 31, zf + 0.4)
	Kit.cyl(m, md * CFrame.Angles(0, math.pi / 2, 0), 0.3, 10, Color3.fromRGB(34, 30, 40), Kit.SLATE)
	Kit.cyl(m, md * CF(0, 0, -0.1) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 10.7, C.Fire, Kit.NEON)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Kit.bit(
			m,
			md * CFrame.Angles(0, 0, a) * CF(5.9, 0, 0),
			V3(1.0, 4.2, 0.8),
			if i % 2 == 0 then C.StoneLight else C.Tiles[1],
			Kit.SLATE
		)
	end
	for _, roll in { 0.55, -0.55 } do
		Kit.blaster(
			m,
			origin * CF(0, 30.6, zG + 2.6) * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, -math.pi / 2, 0),
			16,
			Kit.LavaBlaster,
			true
		)
	end
	Kit.gemCluster(
		m,
		(origin * CF(0, 34.6, zG + 2.2)).Position,
		origin.Rotation * V3(0, 1, 0.35).Unit,
		origin.RightVector,
		4.2,
		C.OrangeCrystal,
		C.OrangeCore,
		3
	)
end

---------------------------------------------------------------- the wow layer

-- Fire towers on the back corners; returns their flames (for embers).
function Building.towers(m: Model, origin: CFrame): { BasePart }
	local flames: { BasePart } = {}
	for _, sx in { -1, 1 } do
		local x, z = sx * 32, -22
		Kit.block(m, origin * CF(x, 16, z), V3(7, 32, 7), Color3.fromRGB(104, 100, 120), Kit.SLATE)
		Kit.block(m, origin * CF(x, 32.4, z), V3(8.4, 1.2, 8.4), C.Slate, Kit.SLATE)
		for _, y in { 10, 20, 30 } do
			Kit.glow(m, origin * CF(x, y, z), V3(7.2, 0.3, 7.2), C.Fire)
		end
		local flame = Kit.ball(m, (origin * CF(x, 34.4, z)).Position, 4.6, C.Fire, Kit.NEON)
		flame.Name = "TowerFlame"
		table.insert(flames, flame)
	end
	return flames
end

--[[
	The hologram: a projector on the ridge, a faint beam, a big galaxy blaster
	floating high over the roof (Model "VaultHologram", tag Spin) and a ring of
	glowing gems turning the other way (Model "VaultGems", tag Spin).
]]
function Building.hologram(m: Model, origin: CFrame): (Model, Model)
	Kit.drum(m, origin * CF(0, 41.3, -6), 0.8, 7, C.Slate, Kit.SLATE)
	Kit.drum(m, origin * CF(0, 41.75, -6), 0.12, 6, C.Holo, Kit.NEON)
	local beam = Kit.drum(m, origin * CF(0, 50, -6), 16.4, 5.6, C.Holo, Kit.NEON)
	beam.Transparency = 0.9
	local holo = Instance.new("Model")
	holo.Name = "VaultHologram"
	holo.Parent = m
	local center = origin * CF(0, 63, -6)
	local pivot = Kit.bit(holo, center, V3(0.2, 0.2, 0.2), C.Holo)
	pivot.Name = "Pivot"
	pivot.Transparency = 1
	holo.PrimaryPart = pivot
	Kit.blaster(holo, center * CFrame.Angles(0, math.pi / 2 + 0.25, 0) * CFrame.Angles(0.12, 0, 0), 23, Kit.GalaxyBlaster, true)
	local gems = Instance.new("Model")
	gems.Name = "VaultGems"
	gems.Parent = m
	local gp = Kit.bit(gems, center, V3(0.2, 0.2, 0.2), C.Holo)
	gp.Name = "Pivot"
	gp.Transparency = 1
	gems.PrimaryPart = gp
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = (origin * CF(math.cos(a) * 16, 63 + math.sin(a * 2) * 2.5, -6 + math.sin(a) * 16)).Position
		Kit.glow(gems, CFrame.new(p) * CFrame.Angles(math.pi / 4, a, math.pi / 4), V3(1.4, 1.4, 1.4), Color3.fromRGB(220, 70, 130))
	end
	return holo, gems
end

-- Giant glass ore crystals on plinths beside the entrance; returns the light positions.
function Building.crystals(m: Model, origin: CFrame)
	for _, side in { { -1, 10 }, { 1, 9 } } do
		local sx = side[1]
		local look = Kit.Levels[side[2]]
		local x, z = sx * 30, 32
		Kit.block(m, origin * CF(x, 0.9, z), V3(7, 1.8, 7), C.StoneDark, Kit.SLATE)
		Kit.bit(m, origin * CF(x, 1.95, z), V3(7.6, 0.3, 7.6), C.StoneLight, Kit.SLATE)
		Kit.glow(m, origin * CF(x, 1.75, z), V3(7.2, 0.12, 7.2), look.Glow)
		Kit.gemCluster(
			m,
			(origin * CF(x, 2.1, z)).Position,
			V3(0, 1, 0),
			origin.RightVector * sx,
			11,
			look.Body,
			look.Body:Lerp(Color3.new(0, 0, 0), 0.35),
			4
		)
		Kit.light(m, (origin * CF(x, 7, z + 2)).Position, look.Glow, 20, 1.3)
	end
end

-- Lava falls down both side walls into glowing pools; returns one pool per side (for embers).
function Building.lavaFalls(m: Model, origin: CFrame): { BasePart }
	local pools: { BasePart } = {}
	for _, sx in { -1, 1 } do
		for i, z in { -12, 8 } do
			local x = sx * 34.4
			Kit.glow(m, origin * CF(x, 11.5, z), V3(0.5, 21, 3.4), C.Lava)
			Kit.glow(m, origin * CF(x + sx * 0.12, 11.5, z), V3(0.4, 21, 1.4), C.LavaCore)
			Kit.block(m, origin * CF(x + sx * 2.6, 0.4, z), V3(5.6, 0.8, 7), C.Slate, Kit.SLATE)
			local pool = Kit.glow(m, origin * CF(x + sx * 2.6, 0.82, z), V3(4.6, 0.12, 6), C.Lava)
			pool.Name = "Lava"
			if i == 1 then
				table.insert(pools, pool)
			end
		end
	end
	return pools
end

-- A rune circle on the forecourt (dark discs and glowing rings) and the two searchlights.
function Building.forecourt(m: Model, origin: CFrame)
	local cz = 33
	local ring = origin * CF(0, 0, cz)
	Kit.drum(m, ring * CF(0, 0.02, 0), 0.06, 13, Color3.fromRGB(46, 42, 56), Kit.SLATE)
	Kit.drum(m, ring * CF(0, 0.05, 0), 0.06, 11.6, C.Fire, Kit.NEON)
	Kit.drum(m, ring * CF(0, 0.08, 0), 0.06, 11.0, Color3.fromRGB(46, 42, 56), Kit.SLATE)
	Kit.drum(m, ring * CF(0, 0.11, 0), 0.06, 8.8, C.Fire, Kit.NEON)
	Kit.drum(m, ring * CF(0, 0.14, 0), 0.06, 8.2, Color3.fromRGB(46, 42, 56), Kit.SLATE)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.glow(
			m,
			ring * CF(math.cos(a) * 4.9, 0.12, math.sin(a) * 4.9) * CFrame.Angles(0, a + math.pi / 4, 0),
			V3(0.6, 0.06, 0.6),
			C.FireCore
		)
	end
	Kit.glow(m, ring * CF(0, 0.17, 0) * CFrame.Angles(0, math.pi / 4, 0), V3(2.2, 0.06, 2.2), C.Fire)
	for _, sx in { -1, 1 } do
		local base = origin * CF(sx * 32, 33.2, 19)
		local beam = Kit.glow(
			m,
			base * CFrame.Angles(0, 0, -sx * 0.38) * CFrame.Angles(0.18, 0, 0) * CF(0, 32, 0),
			V3(2.2, 64, 2.2),
			Color3.fromRGB(255, 220, 170)
		)
		beam.Transparency = 0.9
		beam.Name = "Searchlight"
	end
end

return Building
