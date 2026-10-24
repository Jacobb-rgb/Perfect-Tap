--[[
	The Blaster Vault's inside: a marble checker floor with a fire border and a
	red runner, three stone steps with the ten weapon cases leaning forward on
	lit displays, a lava channel, the giant round vault door in the back wall,
	tie beams with candle chandeliers, the counter (tag VaultCounter, the shop
	hook) with the shopkeeper's spot behind it, and the wall decorations (a treasure
	map, an ore collection, a blaster blueprint, a volcano painting, a blaster
	rack, torches, banners, barrels).

	Frame: `origin` = the floor center (design size, front = +Z); the inside
	is x -28..28, z -22..24.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)
local Kit = require(script.Parent.Kit)

local Interior = {}

local C = Kit.C
local V3 = Vector3.new
local CF = CFrame.new

Interior.CounterTag = "VaultCounter"

---------------------------------------------------------------- floor and steps

function Interior.floor(m: Model, origin: CFrame)
	local A, B = Color3.fromRGB(44, 38, 54), Color3.fromRGB(70, 64, 84)
	local floor = Kit.block(m, origin * CF(0, -0.2, 1.25), V3(56, 0.4, 46.5), B, Kit.MARBLE, Kit.solid())
	floor.Name = "Floor"
	local size = 6.2
	for ix = 0, 8 do
		for iz = 0, 7 do
			local x = -27.9 + (ix + 0.5) * size
			local z = -22 + (iz + 0.5) * size
			if (ix + iz) % 2 == 0 and z < 23 then
				Kit.bit(m, origin * CF(x, 0.02, z), V3(size - 0.12, 0.06, size - 0.12), A, Kit.MARBLE)
			end
		end
	end
	for _, sx in { -1, 1 } do
		Kit.glow(m, origin * CF(sx * 26.6, 0.08, 11), V3(0.16, 0.06, 24), C.Fire)
	end
	Kit.glow(m, origin * CF(0, 0.08, 23.2), V3(53.4, 0.06, 0.16), C.Fire)
	-- the runner from the doorway to the counter
	local z0, z1 = 7.4, 24
	Kit.bit(m, origin * CF(0, 0.1, (z0 + z1) / 2), V3(7, 0.12, z1 - z0), C.Red, Kit.FABRIC)
	for _, sx in { -1, 1 } do
		Kit.bit(m, origin * CF(sx * 3.1, 0.12, (z0 + z1) / 2), V3(0.4, 0.13, z1 - z0), C.Gold)
	end
	for z = z0 + 2, z1 - 1.5, 3.4 do
		Kit.bit(m, origin * CF(0, 0.12, z) * CFrame.Angles(0, math.pi / 4, 0), V3(1.0, 0.13, 1.0), C.Gold)
	end
	-- the lava channel in front of the steps
	local lava = Kit.glow(m, origin * CF(0, 0.12, 2), V3(44, 0.12, 1.6), C.Lava)
	lava.Name = "Lava"
	Kit.bit(m, origin * CF(0, 0.08, 2), V3(46, 0.1, 2.6), Color3.fromRGB(40, 34, 36))
end

-- A step of the case stand: a core, two rows of blocks on the exposed front band, a marble top, end pilasters.
local function caseStep(m: Model, origin: CFrame, z: number, top: number, below: number, rng: any)
	Kit.block(m, origin * CF(0, top / 2, z - 4), V3(50, top, 8), C.Core, Kit.SLATE, Kit.solid())
	local band = top - below
	for r = 0, 1 do
		local y0 = below + r * band / 2
		local x = -25
		while x < 24.95 do
			local len = math.min(25 - x, 4.6 + rng:next() * 2.4)
			Kit.bit(
				m,
				origin * CF(x + len / 2, y0 + band / 4, z - 0.1),
				V3(len - 0.14, band / 2 - 0.14, 0.6),
				C.Tiles[1 + math.floor(rng:next() * #C.Tiles)]:Lerp(C.StoneDark, 0.25),
				Kit.SLATE
			)
			x += len
		end
	end
	Kit.bit(m, origin * CF(0, top - 0.15, z - 3.9), V3(50.4, 0.4, 8.4), C.StoneLight, Kit.MARBLE)
	Kit.glow(m, origin * CF(0, top + 0.06, z + 0.1), V3(50.2, 0.08, 0.2), C.Fire)
	for _, sx in { -1, 1 } do
		Kit.block(m, origin * CF(sx * 25.6, (top + 0.8) / 2, z - 4), V3(1.6, top + 0.8, 8.6), C.StoneDark, Kit.SLATE)
	end
end

local DISPLAY_TILT = 0.34 -- the cases lean forward toward the visitor

-- A case display: a dark base with a glowing rim, a tilted riser, a red cloth, a brass lip, the case, a level plate.
local function display(m: Model, cf: CFrame, level: number, s: number)
	local look = Kit.Levels[level]
	local w, d = 7.6 * s, 4.4 * s
	Kit.block(m, cf * CF(0, 0.35, 0), V3(w, 0.7, d), Color3.fromRGB(30, 31, 38))
	Kit.glow(m, cf * CF(0, 0.72, 0), V3(w + 0.1, 0.06, d + 0.1), look.Glow)
	local rise = d * math.tan(DISPLAY_TILT)
	Kit.wedge(m, cf * CF(0, 0.7 + rise / 2, 0) * CFrame.Angles(0, math.pi, 0), V3(w, rise, d), Color3.fromRGB(46, 42, 54))
	local top = cf * CF(0, 0.7 + rise / 2, 0) * CFrame.Angles(DISPLAY_TILT, 0, 0)
	local depth = d / math.cos(DISPLAY_TILT)
	Kit.bit(m, top * CF(0, 0.05, 0), V3(w - 0.2, 0.1, depth - 0.2), Color3.fromRGB(70, 30, 34), Kit.FABRIC)
	Kit.bit(m, top * CF(0, 0.3, depth / 2 - 0.15), V3(w - 0.2, 0.5, 0.25), C.Brass, Kit.METAL)
	Kit.case(m, top * CF(0, 0.1, -0.15), 6.8 * s, level)
	Kit.label(m, cf * CF(0, 0.35, d / 2 + 0.03), V3(1.7, 0.5, 0.04), "LV " .. level, Color3.fromRGB(30, 31, 38), look.Glow)
end

-- The three steps with the ten cases (4 + 3 + 3) and their fronts.
function Interior.cases(m: Model, origin: CFrame)
	local rng = Kit.rng("Steps")
	local steps = {
		{ below = 0, top = 3, z = -1, levels = { 1, 2, 3, 4 } },
		{ below = 3, top = 6.2, z = -8, levels = { 5, 6, 7 } },
		{ below = 6.2, top = 9.4, z = -15, levels = { 8, 9, 10 } },
	}
	for _, st in steps do
		caseStep(m, origin, st.z, st.top, st.below, rng)
		local n = #st.levels
		for k, level in st.levels do
			local x = (k - (n + 1) / 2) * 12
			display(m, origin * CF(x, st.top, st.z - 3.4), level, 0.72)
		end
	end
end

---------------------------------------------------------------- the back wall

-- The giant round vault door (cf = its center, facing +Z): voussoirs, a steel door, a fire ring, bolts, a wheel.
function Interior.door(m: Model, cf: CFrame, r: number)
	local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
	local n = 12
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		Kit.bit(
			m,
			cf * CFrame.Angles(0, 0, a) * CF(r + 1.1, 0, 0.2),
			V3(2.2, 2 * math.pi * (r + 1.1) / n - 0.18, 1.6),
			if i % 2 == 0 then C.StoneLight else C.Tiles[1],
			Kit.SLATE
		)
	end
	Kit.bit(m, cf * CF(0, r + 2.6, 0.5) * CFrame.Angles(0, 0, math.pi / 4), V3(1.8, 1.8, 1.8), C.StoneLight, Kit.SLATE)
	Kit.cyl(m, cf * ALONG_Z, 0.8, 2 * r, Color3.fromRGB(58, 60, 72), Kit.METAL)
	Kit.cyl(m, cf * CF(0, 0, 0.45) * ALONG_Z, 0.12, 2 * r - 1.2, C.Fire, Kit.NEON)
	Kit.cyl(m, cf * CF(0, 0, 0.5) * ALONG_Z, 0.14, 2 * r - 1.8, Color3.fromRGB(96, 100, 116), Kit.METAL)
	Kit.cyl(m, cf * CF(0, 0, 0.56) * ALONG_Z, 0.1, 2 * r - 4, Color3.fromRGB(58, 60, 72), Kit.METAL)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Kit.cyl(m, cf * CFrame.Angles(0, 0, a) * CF(r - 1.4, 0, 0.62) * ALONG_Z, 0.3, 0.6, Color3.fromRGB(150, 154, 170), Kit.METAL)
	end
	Kit.cyl(m, cf * CF(0, 0, 0.75) * ALONG_Z, 0.5, 3, Color3.fromRGB(96, 100, 116), Kit.METAL)
	for i = 0, 2 do
		local a = i * math.pi / 3
		Kit.bit(m, cf * CFrame.Angles(0, 0, a) * CF(0, 0, 1.15), V3(2 * r - 4.6, 0.45, 0.45), Color3.fromRGB(140, 110, 70), Kit.METAL)
		for _, sx in { -1, 1 } do
			Kit.bit(
				m,
				cf * CFrame.Angles(0, 0, a) * CF(sx * (r - 2.3), 0, 1.15),
				V3(0.7, 0.7, 0.7),
				Color3.fromRGB(170, 136, 80),
				Kit.METAL
			)
		end
	end
	Kit.glow(m, cf * CF(0, 0, 1.05) * CFrame.Angles(0, 0, math.pi / 4), V3(1.2, 1.2, 0.2), C.Fire)
end

-- An iron ring chandelier with candles hung from `top` by a chain.
local function chandelier(m: Model, top: CFrame, drop: number)
	Kit.bit(m, top * CF(0, -drop / 2, 0), V3(0.25, drop, 0.25), C.Iron)
	local ring = top * CF(0, -drop, 0)
	local n, r = 6, 2.6
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		Kit.bit(m, ring * CFrame.Angles(0, a, 0) * CF(r, 0, 0), V3(0.35, 0.35, 2 * math.pi * r / n + 0.1), C.Iron)
		local p = ring * CFrame.Angles(0, a + math.pi / n, 0) * CF(r, 0, 0)
		Kit.drum(m, p * CF(0, 0.55, 0), 0.9, 0.3, C.Candle)
		Kit.ball(m, (p * CF(0, 1.15, 0)).Position, 0.36, C.Flame, Kit.NEON)
	end
	for _, a in { 0, math.pi / 2 } do
		Kit.bit(m, ring * CFrame.Angles(0, a, 0), V3(2 * r, 0.25, 0.25), C.Iron)
	end
end

-- Two tie beams with candle chandeliers, and the two warm lights of the inside.
function Interior.ceiling(m: Model, origin: CFrame)
	for _, z in { -6, 12 } do
		Kit.block(m, origin * CF(0, 22.5, z), V3(66, 2.4, 2.4), C.Wood, nil, Kit.ghost())
		for _, x in { -14, 14 } do
			chandelier(m, origin * CF(x, 21.3, z), 5.5)
		end
	end
	Kit.light(m, (origin * CF(0, 16, -6)).Position, Color3.fromRGB(255, 196, 140), 30, 0.7)
	Kit.light(m, (origin * CF(0, 14, 12)).Position, C.Flame, 24, 0.6)
end

---------------------------------------------------------------- the counter and the keeper

-- The counter (its top is the shop hook, tag VaultCounter), a screen, a blaster on show and the
-- shopkeeper's spot behind it (the owner's miner, ShopkeeperController), facing the door (+Z).
function Interior.counter(m: Model, origin: CFrame): BasePart
	Kit.block(m, origin * CF(0, 2, 5), V3(16, 4, 4), C.Tiles[2], Kit.SLATE, Kit.solid())
	for i = 0, 3 do
		Kit.bit(m, origin * CF(-6 + i * 4, 2, 7.05), V3(3.4, 3, 0.2), C.Tiles[2 + i % 2], Kit.SLATE)
	end
	local top = Kit.block(m, origin * CF(0, 4.05, 5), V3(16.4, 0.3, 4.4), C.Wood, nil, Kit.solid())
	top.Name = "Counter"
	top:AddTag(Interior.CounterTag)
	Kit.glow(m, origin * CF(0, 3.85, 7.25), V3(16.4, 0.12, 0.08), C.Fire)
	-- a screen on a stand
	local sc = origin * CF(-5, 4.2, 4.6)
	Kit.bit(m, sc * CF(0, 0.5, 0), V3(0.4, 1, 0.4), Color3.fromRGB(30, 31, 38))
	Kit.bit(m, sc * CF(0, 1.9, 0) * CFrame.Angles(-0.15, 0, 0), V3(3.4, 2.1, 0.3), Color3.fromRGB(30, 31, 38))
	Kit.glow(m, sc * CF(0, 1.9, 0) * CFrame.Angles(-0.15, 0, 0) * CF(0, 0, 0.16), V3(3.0, 1.75, 0.04), Color3.fromRGB(255, 170, 80))
	Kit.blaster(m, origin * CF(3, 4.6, 5.3) * CFrame.Angles(0, -1.3, 0), 4.8, Kit.GalaxyBlaster, true)
	ShopkeeperConfig.mark(top, origin * CF(0, 0, 0.5) * CFrame.Angles(0, math.pi, 0), "Vault")
	return top
end

---------------------------------------------------------------- wall decorations

-- A frame on an inside wall: X to the viewer's right, Y up, Z out of the wall (side -1 = left wall).
local function wallFrame(origin: CFrame, side: number, z: number, y: number): CFrame
	return origin * CF(side * 27.2, y, z) * CFrame.Angles(0, -side * math.pi / 2, 0)
end

-- A picture frame (w x h) with a canvas; returns the canvas front frame.
local function pictureFrame(m: Model, f: CFrame, w: number, h: number, frameColor: Color3, canvas: Color3): CFrame
	Kit.bit(m, f * CF(0, 0, 0.1), V3(w, h, 0.2), canvas)
	for _, sy in { -1, 1 } do
		Kit.bit(m, f * CF(0, sy * (h / 2 + 0.25), 0.25), V3(w + 1, 0.5, 0.5), frameColor)
	end
	for _, sx in { -1, 1 } do
		Kit.bit(m, f * CF(sx * (w / 2 + 0.25), 0, 0.25), V3(0.5, h, 0.5), frameColor)
	end
	return f * CF(0, 0, 0.2)
end

local function ink(m: Model, f: CFrame, x: number, y: number, w: number, h: number, color: Color3, rot: number?, z: number?)
	Kit.bit(m, f * CF(x, y, z or 0.19) * CFrame.Angles(0, 0, rot or 0), V3(w, h, 0.06), color)
end

-- A treasure map of the island between two scroll rods: the island, a dashed route, an X, a compass.
local function treasureMap(m: Model, f: CFrame)
	local W, H = 12, 7.6
	Kit.bit(m, f * CF(0, 0, 0.1), V3(W, H, 0.12), C.Paper)
	for _, sy in { -1, 1 } do
		Kit.cyl(m, f * CF(0, sy * (H / 2 + 0.2), 0.3), W + 0.6, 0.6, Color3.fromRGB(112, 72, 46))
	end
	for _, p in { { -4.6, 2.6 }, { 3.8, 2.8 }, { -4.8, -2.9 } } do
		ink(m, f, p[1], p[2], 1.4, 0.1, Color3.fromRGB(120, 150, 150))
	end
	for i, r in { { -0.6, 0.0, 6.8, 3.6 }, { 0.6, -1.0, 5.0, 2.6 }, { -1.8, 1.3, 3.4, 1.8 } } do
		ink(m, f, r[1], r[2], r[3], r[4], Color3.fromRGB(214, 184, 118), 0, 0.2 + i * 0.005)
	end
	for _, r in { { -0.8, 0.2, 4.6, 2.0 }, { 0.8, -0.8, 3.2, 1.4 } } do
		ink(m, f, r[1], r[2], r[3], r[4], Color3.fromRGB(120, 150, 82), 0, 0.23)
	end
	ink(m, f, -1.4, 0.7, 1.0, 1.0, Color3.fromRGB(110, 86, 64), math.pi / 4, 0.25)
	local pts = { { -5.0, -2.2 }, { -2.8, -1.1 }, { -0.6, -0.2 }, { 0.6, 0.6 }, { 1.8, 0.2 } }
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		ink(m, f, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, 0.6, 0.14, C.InkRed, math.atan2(b[2] - a[2], b[1] - a[1]), 0.27)
	end
	for _, r in { math.pi / 4, -math.pi / 4 } do
		ink(m, f, 2.4, 0.2, 1.0, 0.22, C.InkRed, r, 0.27)
	end
	ink(m, f, 4.4, -2.4, 0.5, 0.5, C.Ink, math.pi / 4)
	ink(m, f, 4.4, -1.6, 0.16, 0.5, C.InkRed)
end

-- The ore collection: twelve ore gems on brass plates.
local function oreBoard(m: Model, f: CFrame)
	local c = pictureFrame(m, f, 9, 6.4, Color3.fromRGB(96, 62, 40), Color3.fromRGB(44, 32, 30))
	Kit.bit(m, c * CF(0, 2.65, 0.04), V3(5, 0.5, 0.06), C.Brass, Kit.METAL)
	local colors = {
		Color3.fromRGB(222, 120, 60),
		Color3.fromRGB(150, 150, 160),
		Color3.fromRGB(200, 210, 220),
		Color3.fromRGB(150, 84, 220),
		Color3.fromRGB(104, 196, 150),
		Color3.fromRGB(255, 96, 36),
		Color3.fromRGB(255, 200, 58),
		Color3.fromRGB(222, 30, 64),
		Color3.fromRGB(40, 200, 220),
		Color3.fromRGB(30, 64, 220),
		Color3.fromRGB(20, 176, 84),
		Color3.fromRGB(214, 242, 255),
	}
	for i, color in colors do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local gem = Kit.bit(
			m,
			c * CF(-3.15 + col * 2.1, 1.2 - row * 1.75, 0.4) * CFrame.Angles(0, 0, math.pi / 4) * CFrame.Angles(0.5, 0, 0),
			V3(0.8, 0.8, 0.8),
			color,
			Kit.GLASS
		)
		gem.Reflectance = 0.2
	end
	for row = 0, 2 do
		Kit.bit(m, c * CF(0, 0.45 - row * 1.75, 0.05), V3(7.6, 0.2, 0.06), C.Brass, Kit.METAL)
	end
end

-- A blueprint of the level 10 blaster: a blue board, a grid, the outline in white lines, a red stamp.
local function blueprint(m: Model, f: CFrame)
	local W, H = 12, 7
	local LINE = Color3.fromRGB(226, 238, 255)
	local c = pictureFrame(m, f, W, H, Color3.fromRGB(46, 42, 52), Color3.fromRGB(38, 78, 150))
	for i = 1, 5 do
		Kit.bit(m, c * CF(-W / 2 + i * 2, 0, 0.02), V3(0.05, H, 0.03), Color3.fromRGB(70, 112, 190))
	end
	for i = 1, 3 do
		Kit.bit(m, c * CF(0, -H / 2 + i * 1.75, 0.02), V3(W, 0.05, 0.03), Color3.fromRGB(70, 112, 190))
	end
	-- the rifle's outline (barrel to the left): stock, receiver, scope, handguard, barrel, brake, grip, magazine
	local outline = {
		{ { 4.6, 0.9 }, { 4.6, -0.5 } },
		{ { 4.6, 0.9 }, { 1.0, 0.9 } },
		{ { 4.6, -0.5 }, { 2.4, -0.2 } },
		{ { 1.0, 0.9 }, { -1.6, 0.9 } },
		{ { 2.4, -0.2 }, { -1.6, -0.2 } },
		{ { -1.6, 0.9 }, { -1.6, -0.2 } },
		{ { -1.6, 0.6 }, { -4.2, 0.6 } },
		{ { -1.6, 0.1 }, { -4.2, 0.1 } },
		{ { -4.2, 0.85 }, { -4.2, -0.15 } },
		{ { -4.8, 0.85 }, { -4.8, -0.15 } },
		{ { -1.4, 1.55 }, { 1.6, 1.55 } },
		{ { -1.4, 1.15 }, { 1.6, 1.15 } },
		{ { 1.6, -0.2 }, { 2.1, -1.6 } },
		{ { 0.2, -0.2 }, { -0.2, -1.3 } },
	}
	for _, seg in outline do
		local a, b = seg[1], seg[2]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		Kit.bit(
			m,
			c * CF((a[1] + b[1]) / 2, (a[2] + b[2]) / 2 + 0.6, 0.05) * CFrame.Angles(0, 0, math.atan2(dy, dx)),
			V3(math.sqrt(dx * dx + dy * dy) + 0.07, 0.07, 0.04),
			LINE
		)
	end
	for i, w in { 3.2, 2.2 } do
		Kit.bit(m, c * CF(-W / 2 + 0.6 + w / 2, -H / 2 + 0.5 + i * 0.35, 0.05), V3(w, 0.12, 0.04), LINE)
	end
	Kit.bit(m, c * CF(W / 2 - 1.3, -H / 2 + 1.0, 0.05) * CFrame.Angles(0, 0, 0.2), V3(1.6, 0.9, 0.04), Color3.fromRGB(220, 70, 60))
end

-- A sunset painting of a volcano in a gold frame.
local function volcanoPainting(m: Model, f: CFrame)
	local W, H = 9, 6
	local c = pictureFrame(m, f, W, H, Color3.fromRGB(196, 152, 66), Color3.fromRGB(70, 46, 90))
	local bandY = { 1.3, 0.0, -1.1 }
	local bandColor = { Color3.fromRGB(150, 80, 120), Color3.fromRGB(226, 120, 104), Color3.fromRGB(246, 168, 92) }
	for i = 1, 3 do
		Kit.bit(m, c * CF(0, bandY[i], 0.02 + i * 0.002), V3(W, 1.4, 0.04), bandColor[i])
	end
	Kit.cyl(m, c * CF(2.4, 0.4, 0.05) * CFrame.Angles(0, math.pi / 2, 0), 0.04, 1.6, Color3.fromRGB(255, 226, 150))
	local function tri(a: Vector2, b: Vector2, cc: Vector2, color: Color3)
		Kit.tri(
			m,
			(c * CF(a.X, a.Y, 0.09)).Position,
			(c * CF(b.X, b.Y, 0.09)).Position,
			(c * CF(cc.X, cc.Y, 0.09)).Position,
			0.05,
			color,
			nil,
			nil,
			Kit.tiny()
		)
	end
	Kit.bit(m, c * CF(0, -2.3, 0.08), V3(W, 1.4, 0.05), Color3.fromRGB(70, 56, 66))
	tri(Vector2.new(-3.6, -2.2), Vector2.new(1.6, -2.2), Vector2.new(-1.0, 1.4), Color3.fromRGB(56, 40, 50))
	tri(Vector2.new(-0.6, -2.2), Vector2.new(3.8, -2.2), Vector2.new(1.8, 0.0), Color3.fromRGB(84, 62, 72))
	Kit.glow(m, c * CF(-1.0, 1.3, 0.12), V3(0.9, 0.25, 0.04), Color3.fromRGB(255, 120, 40))
	Kit.glow(m, c * CF(-1.3, 0.3, 0.12) * CFrame.Angles(0, 0, 0.35), V3(0.16, 1.9, 0.04), Color3.fromRGB(255, 120, 40))
	Kit.glow(m, c * CF(-0.5, -0.1, 0.12) * CFrame.Angles(0, 0, -0.5), V3(0.14, 2.2, 0.04), Color3.fromRGB(255, 120, 40))
end

-- A wooden rack with two blasters on brass pegs.
local function weaponRack(m: Model, f: CFrame)
	Kit.bit(m, f * CF(0, 0, 0.15), V3(8.6, 5, 0.3), C.WoodDark)
	for _, sx in { -1, 1 } do
		Kit.bit(m, f * CF(sx * 4.5, 0, 0.3), V3(0.5, 5.6, 0.6), C.Wood)
	end
	for i, colors in { Kit.LavaBlaster, Kit.GalaxyBlaster } do
		local y = 1.2 - (i - 1) * 2.4
		for _, sx in { -1.6, 1.6 } do
			Kit.bit(m, f * CF(sx, y - 0.65, 0.6), V3(0.25, 0.25, 0.9), C.Brass, Kit.METAL)
		end
		Kit.blaster(m, f * CF(0, y, 0.8) * CFrame.Angles(0, -math.pi / 2, 0), 7, colors, i == 2)
	end
end

-- A wall torch: an iron bracket, a stick, a flame.
local function wallTorch(m: Model, f: CFrame)
	Kit.bit(m, f * CF(0, 0, 0.2), V3(0.8, 1.4, 0.4), C.Iron)
	Kit.bit(m, f * CF(0, 0.6, 0.7) * CFrame.Angles(0.5, 0, 0), V3(0.4, 1.8, 0.4), C.WoodDark)
	Kit.ball(m, (f * CF(0, 1.6, 1.15)).Position, 0.85, C.Flame, Kit.NEON)
end

-- Everything on the walls: decorations, torches, ore banners on the back wall, two barrels.
function Interior.decor(m: Model, origin: CFrame)
	treasureMap(m, wallFrame(origin, -1, 9.5, 12.5))
	oreBoard(m, wallFrame(origin, -1, -12.5, 15.5))
	blueprint(m, wallFrame(origin, 1, 9.5, 14))
	weaponRack(m, wallFrame(origin, 1, 9.5, 5.6))
	volcanoPainting(m, wallFrame(origin, 1, -12.5, 15.5))
	for _, side in { -1, 1 } do
		for _, z in { 1.5, 18.5 } do
			wallTorch(m, wallFrame(origin, side, z, 9))
		end
	end
	for i, x in { -23.2, -13.8, 13.8, 23.2 } do
		local look = Kit.Levels[({ 3, 6, 8, 10 })[i]]
		Kit.banner(m, origin * CF(x, 15, -21.6), 4, 8, look.Body:Lerp(Color3.new(0, 0, 0), 0.25))
	end
	for _, x in { -29, 29 } do
		local b = origin * CF(x, 0, 18)
		Kit.drum(m, b * CF(0, 1.6, 0), 3.2, 2.6, C.Wood, nil, Kit.decor())
		for _, y in { 0.5, 2.7 } do
			Kit.drum(m, b * CF(0, y, 0), 0.25, 2.7, C.Iron, Kit.METAL)
		end
		Kit.drum(m, b * CF(0, 3.22, 0), 0.06, 2.3, C.WoodDark)
	end
end

-- An invisible zone over the inside (tag LightingZone, attribute Preset): the client dims the light in it.
function Interior.zone(m: Model, origin: CFrame): BasePart
	local zone = Kit.block(m, origin * CF(0, 12, 1), V3(56, 24, 45), Color3.new(0, 0, 0), nil, Kit.tiny({ Transparency = 1 }))
	zone.Name = "VaultInterior"
	zone:SetAttribute("Preset", "VaultInterior")
	zone:AddTag("LightingZone")
	return zone
end

return Interior
