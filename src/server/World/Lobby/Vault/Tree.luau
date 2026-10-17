--[[
	A big jungle tree in the blocky style of Minecraft's jungle trees: a thick
	trunk of bark blocks with grooves and flared roots, a wide layered canopy
	of big leaf voxels in two greens, side branches with leaf clumps, hanging
	vines, cocoa pods and a big fern at its foot. About 80 parts.

	base = the trunk's foot (world position); h = trunk height; R = canopy radius.
]]

local Kit = require(script.Parent.Kit)

local Tree = {}

local C = Kit.C
local V3 = Vector3.new

--[[
	A big fern: a rosette of fronds that rise and arch out, each with one pair
	of leaflets. base = its center on the ground, size ~ its reach. 3 parts per frond.
]]
function Tree.fern(parent: Instance, base: Vector3, size: number, rng: any, fronds: number?)
	local n = fronds or 5
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + rng:next() * 0.5
		local d = V3(math.cos(a), 0, math.sin(a))
		local side = V3(-d.Z, 0, d.X)
		local rise = 0.85 + rng:next() * 0.35
		local L1, L2 = size * (0.5 + rng:next() * 0.15), size * (0.42 + rng:next() * 0.12)
		local dir1 = (d * math.cos(rise) + V3(0, math.sin(rise), 0)).Unit
		local p1 = base + dir1 * L1
		local p2 = p1 + (d + V3(0, -0.45, 0)).Unit * L2
		local color = C.Fern[1 + math.floor(rng:next() * #C.Fern)]
		Kit.beam(parent, base, p1, size * 0.14, 0.18, color)
		Kit.beam(parent, p1, p2, size * 0.11, 0.18, color)
		local q = base + dir1 * (L1 * 0.7)
		Kit.beam(parent, q - side * size * 0.24, q + side * size * 0.24, size * 0.08, 0.16, color, nil, nil, V3(0, 1, 0))
	end
end

function Tree.build(parent: Instance, base: Vector3, h: number, R: number, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	local rng = Kit.rng(name)
	local T = 5.6
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(base + V3(x, y, z))
	end
	-- flared roots, the trunk (three bark blocks), grooves
	for i = 0, 3 do
		local a = i * math.pi / 2 + 0.4
		local d = V3(math.cos(a), 0, math.sin(a))
		Kit.block(
			m,
			CFrame.new(base + d * (T / 2 + 0.9) + V3(0, 1.6, 0)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, 0.35),
			V3(3.4, 3.6, 2.4),
			C.BarkDark
		)
	end
	for i = 0, 2 do
		Kit.block(
			m,
			at(0, h * (i + 0.5) / 3, 0),
			V3(T, h / 3 + 0.02, T),
			if i % 2 == 0 then C.Bark else C.Bark:Lerp(C.BarkDark, 0.35),
			nil,
			Kit.solid()
		)
	end
	for _, f in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local o = rng:next() * 2 - 1
		local x = f[1] * (T / 2 + 0.05) + (if f[1] == 0 then o else 0)
		local z = f[2] * (T / 2 + 0.05) + (if f[2] == 0 then o else 0)
		Kit.bit(m, at(x, h * 0.48, z), V3(if f[1] == 0 then 0.5 else 0.3, h * 0.9, if f[2] == 0 then 0.5 else 0.3), C.BarkDark)
	end
	-- the canopy: layers of big leaf voxels (rows merged into long blocks)
	local u = 4
	local function layer(cy: number, r: number, holes: number)
		local n = math.ceil(r / u)
		for gz = -n, n do
			local run: number? = nil
			local runTone = C.Leaf
			local function flush(gx: number)
				if run then
					local x0, x1 = run * u, (gx - 1) * u
					Kit.block(m, at((x0 + x1) / 2, cy, gz * u), V3(x1 - x0 + u, u, u), runTone, nil, Kit.ghost())
					run = nil
				end
			end
			for gx = -n, n + 1 do
				local d = math.sqrt(gx * gx + gz * gz) * u
				local inside = gx <= n and d <= r + (rng:next() - 0.5) * u * 1.2 and rng:next() > holes
				local toneNow = if rng:next() < 0.35 then C.LeafLight else C.Leaf
				if inside and run and toneNow ~= runTone and rng:next() < 0.4 then
					flush(gx)
				end
				if inside and not run then
					run = gx
					runTone = toneNow
				elseif not inside then
					flush(gx)
				end
			end
		end
	end
	layer(h + u / 2 - 0.5, R, 0.06)
	layer(h + 1.5 * u - 0.5, R * 0.82, 0.04)
	layer(h + 2.5 * u - 0.5, R * 0.5, 0)
	-- side branches with leaf clumps
	for i = 0, 2 do
		local a = i * 2.1 + rng:next()
		local d = V3(math.cos(a), 0, math.sin(a))
		local by = h * (0.55 + 0.12 * i)
		local tip = base + V3(0, by + 3, 0) + d * 8
		Kit.beam(m, base + V3(0, by, 0), tip, 1.8, 1.8, C.Bark, nil, Kit.ghost())
		Kit.block(m, CFrame.new(tip), V3(u, u * 0.8, u), if rng:next() < 0.4 then C.LeafLight else C.Leaf, nil, Kit.ghost())
		Kit.block(m, CFrame.new(tip + d * u * 0.7 + V3(0, -0.6, 0)), V3(u * 0.7, u * 0.6, u * 0.7), C.Leaf, nil, Kit.ghost())
	end
	-- vines hanging from the canopy edge, cocoa pods on the trunk
	for _ = 1, 7 do
		local a = rng:next() * math.pi * 2
		local r = R * (0.7 + rng:next() * 0.3)
		local len = 6 + rng:next() * 12
		Kit.bit(m, at(math.cos(a) * r, h - 1.8 - len / 2, math.sin(a) * r), V3(0.6, len, 0.5), C.Vine)
	end
	for i = 0, 1 do
		local a = i * 2.6
		Kit.bit(m, at(math.cos(a) * (T / 2 + 0.5), h * 0.8 - i * 1.5, math.sin(a) * (T / 2 + 0.5)), V3(1.1, 1.5, 1.1), C.Cocoa)
	end
	local fa = rng:next() * math.pi * 2
	Tree.fern(m, base + V3(math.cos(fa), 0, math.sin(fa)) * (T / 2 + 4.5), 7, rng, 5)
	return m
end

return Tree
