--[[
	A giant stone king statue beside the Blaster Vault (after the owner's
	concept art): a muscular body of grey stone blocks veined with glowing lava
	cracks, a crown, a bearded face with glowing eyes, layered shoulder plates,
	a purple tabard with the gold crest and a dark cape; one arm raises a lava
	blaster, the other holds an open treasure map toward the visitors. It
	stands on a stone pedestal with a fire line and a purple banner.

	ground = the pedestal's foot center, front = +Z; arm = the side of the
	blaster arm (+1 = the statue's local +X). About 280 parts, no lights.
]]

local Kit = require(script.Parent.Kit)

local Statue = {}

local C = Kit.C
local V3 = Vector3.new
local CF = CFrame.new

Statue.PedestalHeight = 8.4
Statue.K = 1.85 -- studs per body unit (the body is ~15 units tall)

-- Glowing zigzag cracks on a face: fcf = the face's center frame (Z out of it), hx, hy = its half size.
local function cracks(m: Model, fcf: CFrame, hx: number, hy: number, n: number, rng: any, thick: number)
	for _ = 1, n do
		local x, y = (rng:next() - 0.5) * hx * 1.4, (rng:next() - 0.5) * hy * 1.4
		local a = rng:next() * math.pi * 2
		for _ = 1, 2 + math.floor(rng:next() * 2) do
			a += (rng:next() - 0.5) * 1.4
			local len = (0.4 + rng:next() * 0.45) * math.min(hx, hy) * 1.4
			local nx = math.clamp(x + math.cos(a) * len, -hx * 0.92, hx * 0.92)
			local ny = math.clamp(y + math.sin(a) * len, -hy * 0.92, hy * 0.92)
			local dx, dy = nx - x, ny - y
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 0.05 then
				Kit.glow(
					m,
					fcf * CF((x + nx) / 2, (y + ny) / 2, 0.03) * CFrame.Angles(0, 0, math.atan2(dy, dx)),
					V3(l + thick, thick, 0.06),
					Color3.fromRGB(255, 136, 44)
				)
			end
			x, y = nx, ny
		end
	end
end

type Face = { offset: CFrame, hx: number, hy: number, turn: CFrame }

-- The face of a box (cf, size) whose normal points most along `dir`: its center frame and half size.
local function bestFace(cf: CFrame, size: Vector3, dir: Vector3): (CFrame, number, number)
	local faces: { Face } = {
		{ offset = CF(0, 0, size.Z / 2), hx = size.X / 2, hy = size.Y / 2, turn = CFrame.identity },
		{ offset = CF(0, 0, -size.Z / 2), hx = size.X / 2, hy = size.Y / 2, turn = CFrame.Angles(0, math.pi, 0) },
		{ offset = CF(size.X / 2, 0, 0), hx = size.Z / 2, hy = size.Y / 2, turn = CFrame.Angles(0, math.pi / 2, 0) },
		{ offset = CF(-size.X / 2, 0, 0), hx = size.Z / 2, hy = size.Y / 2, turn = CFrame.Angles(0, -math.pi / 2, 0) },
		{ offset = CF(0, size.Y / 2, 0), hx = size.X / 2, hy = size.Z / 2, turn = CFrame.Angles(-math.pi / 2, 0, 0) },
		{ offset = CF(0, -size.Y / 2, 0), hx = size.X / 2, hy = size.Z / 2, turn = CFrame.Angles(math.pi / 2, 0, 0) },
	}
	local best, bestDot = faces[1], -math.huge
	for _, f in faces do
		local d = -(cf * f.offset * f.turn).LookVector:Dot(dir) -- a frame's +Z (the face normal) is -LookVector
		if d > bestDot then
			best, bestDot = f, d
		end
	end
	return cf * best.offset * best.turn, best.hx, best.hy
end

-- A row of face blocks with rune inlays (cf = the strip's bottom center, X along it, +Z outward).
local function blockRow(m: Model, cf: CFrame, length: number, height: number, rng: any)
	local x, i = -length / 2, 0
	while x < length / 2 - 0.05 do
		local len = math.min(length / 2 - x, 4.2 + rng:next() * 2)
		Kit.bit(
			m,
			cf * CF(x + len / 2, height / 2, 0),
			V3(len - 0.14, height - 0.14, 0.6),
			C.Tiles[1 + math.floor(rng:next() * #C.Tiles)]:Lerp(C.StoneDark, 0.25),
			Kit.SLATE
		)
		if i % 3 == 1 and len > 3 then
			Kit.glow(m, cf * CF(x + len / 2, height / 2, 0.31), V3(0.9, 0.18, 0.04), C.Fire)
		end
		x += len
		i += 1
	end
end

function Statue.build(parent: Instance, ground: CFrame, arm: number, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	local rng = Kit.rng(name)
	local k = Statue.K
	-- the pedestal
	local PW, PD, PH = 14, 12, Statue.PedestalHeight
	Kit.block(m, ground * CF(0, 0.6, 0), V3(PW + 1.4, 1.2, PD + 1.4), Color3.fromRGB(70, 66, 78), Kit.SLATE, Kit.solid())
	Kit.block(m, ground * CF(0, PH / 2, 0), V3(PW, PH, PD), C.Core, Kit.SLATE, Kit.solid())
	local rows = 3
	for r = 0, rows - 1 do
		local y0 = 1.2 + r * (PH - 2) / rows
		local h = (PH - 2) / rows
		blockRow(m, ground * CF(0, y0, PD / 2 - 0.2), PW, h, rng)
		blockRow(m, ground * CF(0, y0, -PD / 2 + 0.2) * CFrame.Angles(0, math.pi, 0), PW, h, rng)
		for _, sx in { -1, 1 } do
			blockRow(m, ground * CF(sx * (PW / 2 - 0.2), y0, 0) * CFrame.Angles(0, sx * math.pi / 2, 0), PD, h, rng)
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.block(
				m,
				ground * CF(sx * (PW / 2 - 0.4), PH / 2, sz * (PD / 2 - 0.4)),
				V3(1.8, PH, 1.8),
				Color3.fromRGB(78, 74, 88),
				Kit.SLATE
			)
		end
	end
	Kit.block(m, ground * CF(0, PH + 0.4, 0), V3(PW + 1.0, 0.8, PD + 1.0), C.StoneLight, Kit.SLATE, Kit.solid())
	Kit.glow(m, ground * CF(0, PH - 0.1, PD / 2 + 0.52), V3(PW + 1.0, 0.16, 0.06), C.Fire)
	for _, sx in { -1, 1 } do
		Kit.glow(m, ground * CF(sx * (PW / 2 + 0.52), PH - 0.1, 0), V3(0.06, 0.16, PD + 1.0), C.Fire)
	end
	Kit.banner(m, ground * CF(0, PH - 0.5, PD / 2 + 0.7), 5.2, 6.4)

	-- the statue, in body units (x k studs) on the pedestal top
	local feet = ground * CF(0, PH + 0.8, 0)
	local fwd = -feet.LookVector -- the statue faces its +Z
	local crackDir = (fwd + V3(0, 0.25, 0)).Unit
	local function P(x: number, y: number, z: number): Vector3
		return (feet * CF(x * k, y * k, z * k)).Position
	end
	local function tone(): Color3
		return C.StatueStone[1 + math.floor(rng:next() * #C.StatueStone)]
	end
	local function crackOn(cf: CFrame, size: Vector3, n: number)
		if n > 0 then
			local fcf, hx, hy = bestFace(cf, size, crackDir)
			cracks(m, fcf, hx, hy, n, rng, 0.17 * k)
		end
	end
	local function blk(x: number, y: number, z: number, w: number, h: number, d: number, n: number, rot: CFrame?, color: Color3?): CFrame
		local cf = feet * CF(x * k, y * k, z * k) * (rot or CFrame.identity)
		local size = V3(w * k, h * k, d * k)
		Kit.block(m, cf, size, color or tone(), Kit.SLATE)
		crackOn(cf, size, n)
		return cf
	end
	local function limb(a: Vector3, b: Vector3, w: number, d: number, n: number): CFrame
		local cf = CFrame.lookAt((a + b) / 2, b, fwd)
		local size = V3(w * k, d * k, (b - a).Magnitude + 0.3 * k)
		Kit.block(m, cf, size, tone(), Kit.SLATE)
		crackOn(cf, size, n)
		return cf
	end
	-- legs: boots, knee guards, shins, thighs
	for _, s in { -1, 1 } do
		blk(s * 1.9, 0.45, 0.35, 1.6, 0.9, 2.4, 0, nil, C.StatueDark)
		local ankle, knee, hip = P(s * 1.9, 0.9, 0.2), P(s * 1.75, 3.7, 0.55), P(s * 1.05, 6.2, 0)
		limb(ankle, knee, 1.45, 1.55, 1)
		blk(s * 1.75, 3.7, 1.25, 1.3, 1.1, 0.5, 0, nil, Color3.fromRGB(78, 74, 84))
		limb(knee, hip, 2.1, 2.15, 2)
	end
	-- hips, belt with a glowing buckle, the tabard with the crest, the cape
	blk(0, 6.4, 0, 3.9, 1.3, 2.2, 0)
	blk(0, 6.95, 0, 4.1, 0.6, 2.4, 0, nil, Color3.fromRGB(60, 50, 46))
	Kit.glow(m, feet * CF(0, 6.95 * k, 1.22 * k) * CFrame.Angles(0, 0, math.pi / 4), V3(0.6 * k, 0.6 * k, 0.1 * k), C.Fire)
	local tab = feet * CF(0, 5.0 * k, 1.25 * k) * CFrame.Angles(-0.1, 0, 0)
	Kit.bit(m, tab, V3(1.9 * k, 3.4 * k, 0.16 * k), C.Purple, Kit.FABRIC)
	Kit.tri(
		m,
		(tab * CF(-0.95 * k, -1.7 * k, 0.08 * k)).Position,
		(tab * CF(0.95 * k, -1.7 * k, 0.08 * k)).Position,
		(tab * CF(0, -2.4 * k, 0.08 * k)).Position,
		0.16 * k,
		C.Purple,
		Kit.FABRIC,
		-tab.LookVector,
		Kit.tiny()
	)
	for _, sx in { -1, 1 } do
		Kit.bit(m, tab * CF(sx * 0.88 * k, 0, 0.1 * k), V3(0.12 * k, 3.4 * k, 0.04 * k), C.Gold, Kit.METAL)
	end
	Kit.crest(m, tab * CF(0, 0.3 * k, 0.1 * k), 0.75 * k, false)
	local cape = feet * CF(0, 6.6 * k, -1.45 * k) * CFrame.Angles(0.1, 0, 0)
	Kit.block(m, cape, V3(4.6 * k, 8.4 * k, 0.25 * k), C.PurpleDark, Kit.FABRIC)
	-- waist with abs, a broad chest with pecs, lats, deltoids, layered shoulder plates
	blk(0, 8.05, 0.05, 3.2, 1.9, 2.0, 1)
	for _, ax in { -0.5, 0.5 } do
		for _, ay in { 7.4, 7.98, 8.56 } do
			blk(ax, ay, 1.1, 0.92, 0.5, 0.36, 0)
		end
	end
	blk(0, 9.95, 0.05, 4.9, 2.4, 2.4, 1)
	for _, s in { -1, 1 } do
		blk(s * 2.0, 8.9, -0.1, 1.2, 1.9, 1.9, 1, CFrame.Angles(0, 0, s * 0.3))
		blk(s * 2.75, 10.2, 0.1, 1.5, 1.4, 1.9, 1)
		blk(s * 1.08, 10.25, 1.3, 2.25, 1.5, 0.72, 1, CFrame.Angles(0, s * 0.12, 0))
		for i, pl in { { 11.15, 2.3, 1.05, 2.6, 0.22 }, { 10.55, 2.1, 0.55, 2.5, 0.45 }, { 10.1, 1.9, 0.45, 2.3, 0.7 } } do
			blk(
				s * (2.6 + i * 0.22),
				pl[1],
				0,
				pl[2],
				pl[3],
				pl[4],
				if i == 1 then 1 else 0,
				CFrame.Angles(0, 0, -s * pl[5]),
				if i == 1 then Color3.fromRGB(122, 118, 128) else nil
			)
		end
	end
	blk(0, 11.25, -0.15, 2.7, 0.65, 1.5, 0)
	-- neck, head, brow, glowing eyes, nose, beard, crown with a gem
	blk(0, 11.7, 0, 1.3, 0.8, 1.3, 0)
	blk(0, 12.8, 0.1, 1.75, 1.95, 1.85, 1)
	blk(0, 13.15, 1.02, 1.8, 0.3, 0.42, 0, nil, Color3.fromRGB(96, 92, 100))
	for _, s in { -1, 1 } do
		Kit.glow(m, feet * CF(s * 0.42 * k, 12.93 * k, 1.04 * k), V3(0.38 * k, 0.14 * k, 0.08 * k), C.Fire)
	end
	blk(0, 12.6, 1.12, 0.32, 0.5, 0.32, 0)
	blk(0, 12.3, 1.1, 1.05, 0.2, 0.3, 0)
	blk(0, 11.9, 0.88, 1.65, 0.95, 0.65, 1)
	blk(0, 11.3, 0.95, 1.1, 0.65, 0.5, 0)
	blk(0, 13.95, 0.1, 1.95, 0.55, 2.05, 0, nil, Color3.fromRGB(122, 118, 128))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local h = if i == 2 then 0.85 else 0.6
		blk(
			math.cos(a) * 0.9,
			14.25 + h / 2,
			0.1 + math.sin(a) * 0.95,
			0.38,
			h,
			0.32,
			0,
			CFrame.Angles(0, -a, 0),
			Color3.fromRGB(122, 118, 128)
		)
	end
	Kit.glow(m, feet * CF(0, 13.95 * k, 1.15 * k) * CFrame.Angles(0, 0, math.pi / 4), V3(0.32 * k, 0.32 * k, 0.1 * k), C.Gem)
	-- the blaster arm: up and out, the forearm raised, a bracer, a fist with a lava blaster
	local S, E, H = P(arm * 2.85, 10.6, 0), P(arm * 4.6, 11.0, 0.7), P(arm * 4.95, 13.3, 1.15)
	limb(S, E, 1.9, 1.9, 2)
	blk(arm * 3.7, 11.6, 0.7, 1.3, 0.95, 1.3, 0)
	limb(E, H, 1.6, 1.65, 1)
	Kit.block(m, CFrame.lookAt(E:Lerp(H, 0.78), H, fwd), V3(1.6 * k, 1.65 * k, 0.6 * k), Color3.fromRGB(70, 66, 76), Kit.SLATE)
	Kit.block(m, CFrame.lookAt(H, H + (H - E).Unit, fwd), V3(1.5 * k, 1.5 * k, 1.3 * k), tone(), Kit.SLATE)
	local L = 7.6 * k
	local dir = (feet.Rotation * V3(arm * 0.18, 0.88, 0.42)).Unit
	local Z = -dir
	local X = (fwd - dir * fwd:Dot(dir)).Unit
	local Y = Z:Cross(X)
	-- place the blaster so its grip sits in the fist
	Kit.blaster(m, CFrame.fromMatrix(H + dir * 0.2 * k, X, Y, Z) * CF(0, 0.1 * L, -0.13 * L), L, Kit.LavaBlaster, true)
	-- the map arm: down and forward, holding an open map toward the visitors
	local S2, E2, H2 = P(-arm * 2.85, 10.6, 0), P(-arm * 3.45, 8.5, 1.3), P(-arm * 2.6, 8.9, 3.1)
	limb(S2, E2, 1.9, 1.9, 2)
	blk(-arm * 3.35, 9.9, 0.9, 1.2, 1.0, 1.3, 0)
	limb(E2, H2, 1.6, 1.65, 1)
	Kit.block(m, CFrame.lookAt(E2:Lerp(H2, 0.75), H2, fwd), V3(1.6 * k, 1.65 * k, 0.6 * k), Color3.fromRGB(70, 66, 76), Kit.SLATE)
	Kit.block(m, CFrame.lookAt(H2, H2 + (H2 - E2).Unit, fwd), V3(1.5 * k, 1.5 * k, 1.3 * k), tone(), Kit.SLATE)
	local map = feet * CF(-arm * 2.3 * k, 9.9 * k, 3.75 * k) * CFrame.Angles(0, arm * 0.3, 0) * CFrame.Angles(-0.2, 0, 0)
	for _, sx in { -1, 1 } do
		local half = map * CF(sx * 0.75 * k, 0, 0) * CFrame.Angles(0, -sx * 0.18, 0)
		Kit.bit(m, half, V3(1.5 * k, 2.1 * k, 0.08 * k), Color3.fromRGB(214, 188, 132))
		for j = 0, 1 do
			Kit.bit(
				m,
				half * CF((rng:next() - 0.5) * 0.8 * k, (0.5 - j * 0.6) * k, 0.05 * k) * CFrame.Angles(0, 0, (rng:next() - 0.5) * 1.2),
				V3((0.5 + rng:next() * 0.5) * k, 0.06 * k, 0.03 * k),
				C.Ink
			)
		end
		if sx > 0 then
			for _, r in { math.pi / 4, -math.pi / 4 } do
				Kit.bit(m, half * CF(0.2 * k, -0.3 * k, 0.06 * k) * CFrame.Angles(0, 0, r), V3(0.45 * k, 0.08 * k, 0.03 * k), C.InkRed)
			end
		else
			for j = 0, 2 do
				Kit.bit(m, half * CF((-0.45 + j * 0.3) * k, (-0.5 + j * 0.25) * k, 0.06 * k), V3(0.18 * k, 0.06 * k, 0.03 * k), C.InkRed)
			end
		end
	end
	return m
end

return Statue
