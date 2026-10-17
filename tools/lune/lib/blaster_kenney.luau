--[[
	Kenney Blaster Kit shapes rebuilt from parts (data: kenney_blaster_shapes.luau,
	made by tools/kenney/blaster_shapes.py) with the "Ore Glow" skins of
	proposal D (tools/lune/lib/blaster_glow.luau). Prototype for the owner's
	review; the game still uses BlasterBuilder.

	Design frame like the other galleries: barrel along -Z, +Y up, the model
	centered on X; Kenney meters times `scale` studs.
]]

local roblox = require("@lune/roblox") :: any
local Concepts = require("./blaster_concepts")
local Shapes = require("./kenney_blaster_shapes") :: any

local Kenney = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum

local CF: any
local Geo: any

-- The right-angle corner of a WedgePart sits at local (+Z, -Y); these turn it to the other corners.
local function wedgeTurn(sz: number, sy: number): any
	if sz > 0 and sy < 0 then
		return CF.identity
	elseif sz < 0 and sy < 0 then
		return CF.Angles(0, math.pi, 0)
	elseif sz > 0 then
		return CF.Angles(0, 0, math.pi)
	end
	return CF.Angles(math.pi, 0, 0)
end

export type Region = { role: string, w: number, c: number, loops: { { number } }, prims: { any } }

--[[
	Builds the parts of one Kenney model into `model` (in the design frame).
	paint(region) -> (color, material?, widthBonus?) picks every region's look.
	Returns the model data (bounds, regions) and the X center that was removed.
]]
function Kenney.shape(Loader: any, model: any, name: string, scale: number, paint: (Region) -> (any, any?, number?))
	CF = Loader.CFrame
	Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local data = Shapes[name]
	local b = data.bounds
	local cx = (b[5] + b[6]) / 2
	local K = Concepts.kit(model)
	for _, region in data.regions do
		local color, material, bonus = paint(region)
		local w = (region.w + (bonus or 0)) * scale
		local x = (region.c - cx) * scale
		for _, p in region.prims do
			local kind = p[1]
			if kind == "b" then
				local z0, z1, y0, y1 = p[2] * scale, p[3] * scale, p[4] * scale, p[5] * scale
				if z1 - z0 < 0.003 or y1 - y0 < 0.003 then
					continue -- slivers (flat parts render with broken normals)
				end
				K.boxCF(CF.new(x, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(w, y1 - y0, z1 - z0), color, material)
			elseif kind == "t" then
				local pz, py, az, by = p[2] * scale, p[3] * scale, p[4] * scale, p[7] * scale
				if math.abs(by - py) < 0.003 or math.abs(az - pz) < 0.003 then
					continue
				end
				local cf = CF.new(x, (py + by) / 2, (pz + az) / 2) * wedgeTurn(pz - az, py - by)
				K.part("WedgePart", cf, V3.new(w, math.abs(by - py), math.abs(az - pz)), color, material)
			else
				local a = V3.new(x, p[3] * scale, p[2] * scale)
				local bb = V3.new(x, p[5] * scale, p[4] * scale)
				local c = V3.new(x, p[7] * scale, p[6] * scale)
				Geo.triangle(model, a, bb, c, w, color, material, nil, { CanCollide = false, Anchored = true })
			end
		end
	end
	return data, cx
end

-- Kenney's own colors (to check the shapes against the kit).
Kenney.KenneyColors = {
	body = C3.fromRGB(150, 104, 214),
	light = C3.fromRGB(168, 180, 210),
	mid = C3.fromRGB(110, 122, 140),
	dark = C3.fromRGB(62, 62, 68),
}

-- "kenney_check": all 18 kit blasters in Kenney colors, side view, three rows.
function Kenney.buildCheck(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local root = roblox.Instance.new("Model")
	root.Name = "KenneyCheck"
	root.Parent = parent
	local K = Concepts.kit(root)
	K.boxCF(CF.new(0, 4, -3), V3.new(80, 30, 1), C3.fromRGB(40, 42, 50))
	local names = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r" }
	for i, n in names do
		local model = roblox.Instance.new("Model")
		Kenney.shape(Loader, model, "blaster-" .. n, 4, function(region)
			return Kenney.KenneyColors[region.role]
		end)
		local col = (i - 1) % 6
		local row = math.floor((i - 1) / 6)
		Concepts.present(model, CF.new(-25 + col * 10, 12 - row * 5, 0) * CF.Angles(0, -math.pi / 2, 0), 1, root)
	end
	return root
end

---------------------------------------------------------------- Ore Glow skins on the Kenney shapes

local Glow = require("./blaster_glow")
local NEON = Enum.Material.Neon
local BLACK = C3.new(0, 0, 0)

-- The Kenney model of every level (the same order as BlasterBuilder: b, c, a, j, m, g, r, p, d, e).
Kenney.Models =
	{ "blaster-b", "blaster-c", "blaster-a", "blaster-j", "blaster-m", "blaster-g", "blaster-r", "blaster-p", "blaster-d", "blaster-e" }
Kenney.Scale = 4 -- Kenney meters -> design studs
Kenney.Stocks = { ["blaster-g"] = true, ["blaster-p"] = true, ["blaster-d"] = true, ["blaster-e"] = true }

-- Hand points on the grips (Kenney meters, z then y), measured from the side profiles.
local HANDS = {
	["blaster-b"] = { 0.07, -0.095 },
	["blaster-c"] = { 0.13, -0.03 },
	["blaster-a"] = { 0.18, -0.14 },
	["blaster-j"] = { 0.2, -0.01 },
	["blaster-m"] = { 0.18, -0.08 },
	["blaster-g"] = { 0.24, -0.05 },
	["blaster-r"] = { 0.19, 0.02 },
	["blaster-p"] = { 0.21, -0.02 },
	["blaster-d"] = { 0.14, -0.02 },
	["blaster-e"] = { 0.97, -0.06 },
}
-- The left hand: under the front of the gun.
local SUPPORTS = {
	["blaster-b"] = { 0.1, -0.15 },
	["blaster-c"] = { 0.16, -0.08 },
	["blaster-a"] = { -0.2, -0.13 },
	["blaster-j"] = { -0.2, -0.03 },
	["blaster-m"] = { -0.15, -0.1 },
	["blaster-g"] = { -0.25, 0.04 },
	["blaster-r"] = { -0.28, 0.0 },
	["blaster-p"] = { -0.25, -0.04 },
	["blaster-d"] = { -0.24, -0.06 },
	["blaster-e"] = { 0.55, -0.07 },
}

local function signedArea(loop: { number }): number
	local a = 0
	local n = #loop // 2
	for i = 1, n do
		local j = i % n + 1
		a += loop[2 * i - 1] * loop[2 * j] - loop[2 * j - 1] * loop[2 * i]
	end
	return a / 2
end

-- Even-odd point in a polygon with holes (loops of { z, y, z, y, ... }).
local function insideLoops(loops: { { number } }, z: number, y: number): boolean
	local inside = false
	for _, L in loops do
		local n = #L // 2
		local j = n
		for i = 1, n do
			local zi, yi, zj, yj = L[2 * i - 1], L[2 * i], L[2 * j - 1], L[2 * j]
			if (yi > y) ~= (yj > y) and z < (zj - zi) * (y - yi) / (yj - yi) + zi then
				inside = not inside
			end
			j = i
		end
	end
	return inside
end

local function deepInside(loops: { { number } }, z: number, y: number, m: number): boolean
	return insideLoops(loops, z, y)
		and insideLoops(loops, z + m, y)
		and insideLoops(loops, z - m, y)
		and insideLoops(loops, z, y + m)
		and insideLoops(loops, z, y - m)
end

-- A glowing strip from (z0, y0) to (z1, y1) at x, through a region of width w (shows on both sides).
local function strip(K: any, x: number, z0: number, y0: number, z1: number, y1: number, thick: number, w: number, color: any)
	local dz, dy = z1 - z0, y1 - y0
	local len = math.sqrt(dz * dz + dy * dy)
	if len < 0.02 then
		return
	end
	local up = V3.new(0, -dz / len, dy / len)
	K.part(
		"Part",
		CF.fromMatrix(V3.new(x, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(1, 0, 0), up),
		V3.new(w, thick, len + thick * 0.5),
		color,
		NEON
	)
end

-- Glowing lines along the inside of a region's outline (every loop edge moved in by d).
local function rims(K: any, x: number, loops: { { number } }, w: number, d: number, thick: number, color: any)
	for _, L in loops do
		local n = #L // 2
		for i = 1, n do
			local j = i % n + 1
			local z0, y0, z1, y1 = L[2 * i - 1], L[2 * i], L[2 * j - 1], L[2 * j]
			local dz, dy = z1 - z0, y1 - y0
			local len = math.sqrt(dz * dz + dy * dy)
			if len > d * 3 then
				local tz, ty = dz / len, dy / len
				local nz, ny = -ty, tz
				local mz, my = (z0 + z1) / 2, (y0 + y1) / 2
				if not insideLoops(loops, mz + nz * d * 1.5, my + ny * d * 1.5) then
					nz, ny = -nz, -ny
				end
				strip(K, x, z0 + tz * d + nz * d, y0 + ty * d + ny * d, z1 - tz * d + nz * d, y1 - ty * d + ny * d, thick, w, color)
			end
		end
	end
end

-- The loops of a region in design studs.
local function scaledLoops(region: any, scale: number): { { number } }
	local out = {}
	for _, L in region.loops do
		local s = {}
		for i, v in L do
			s[i] = v * scale
		end
		table.insert(out, s)
	end
	return out
end

local function loopsArea(loops: { { number } }): number
	local a = 0
	for _, L in loops do
		a += signedArea(L)
	end
	return math.abs(a)
end

local function bbox(loops: { { number } }): (number, number, number, number)
	local z0, z1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, L in loops do
		for i = 1, #L, 2 do
			z0, z1 = math.min(z0, L[i]), math.max(z1, L[i])
			y0, y1 = math.min(y0, L[i + 1]), math.max(y1, L[i + 1])
		end
	end
	return z0, z1, y0, y1
end

local function randomDeep(loops: { { number } }, m: number, rand: () -> number): (number?, number?)
	local z0, z1, y0, y1 = bbox(loops)
	for _ = 1, 80 do
		local z, y = z0 + (z1 - z0) * rand(), y0 + (y1 - y0) * rand()
		if deepInside(loops, z, y, m) then
			return z, y
		end
	end
	return nil, nil
end

-- The ore pattern on one region (skin.magma: lava cracks; else galaxy stars and nebula).
local function pattern(K: any, skin: any, x: number, loops: { { number } }, w: number, main: boolean, rand: () -> number)
	local a = loopsArea(loops)
	local z0, z1, y0, y1 = bbox(loops)
	-- only real panels get a pattern (not the thin chamfer steps or small knobs)
	if a < 0.06 or z1 - z0 < 0.14 or y1 - y0 < 0.12 then
		return
	end
	local through = w + 0.014
	local rimColor = if skin.magma then (if skin.tier == 0 then skin.vein else skin.rim) else skin.edge
	local rimThick = if main then (if skin.tier == 0 then 0.016 else 0.022) else 0.016
	rims(K, x, loops, through, 0.045, rimThick, rimColor)
	if not main then
		return
	end
	if skin.magma then
		local density = ({ [0] = 5, [1] = 12, [2] = 14, [3] = 17 })[skin.tier]
		local count = math.clamp(math.floor(a * density + 0.5), 2, 22)
		local seeds = {}
		for _ = 1, count do
			local z, y = randomDeep(loops, 0.05, rand)
			if z then
				table.insert(seeds, { z, y })
			end
		end
		if #seeds < 2 then
			return
		end
		local box = { { z0, y0 }, { z1, y0 }, { z1, y1 }, { z0, y1 } }
		-- Voronoi edges of the seeds (each cell clipped like proposal D's cracks), cut to the region
		local edges = {}
		for i, si in seeds do
			local poly = {}
			for _, p in box do
				table.insert(poly, { p[1], p[2], 0 })
			end
			for j, sj in seeds do
				if j ~= i and #poly >= 3 then
					local mz, my = (si[1] + sj[1]) / 2, (si[2] + sj[2]) / 2
					local nz, ny = sj[1] - si[1], sj[2] - si[2]
					local out = {}
					for k = 1, #poly do
						local p, q = poly[k], poly[k % #poly + 1]
						local dp = (p[1] - mz) * nz + (p[2] - my) * ny
						local dq = (q[1] - mz) * nz + (q[2] - my) * ny
						if dp <= 0 then
							table.insert(out, { p[1], p[2], p[3] })
							if dq > 0 then
								local t = dp / (dp - dq)
								table.insert(out, { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, j })
							end
						elseif dq <= 0 then
							local t = dp / (dp - dq)
							table.insert(out, { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] })
						end
					end
					poly = out
				end
			end
			for k = 1, #poly do
				local p, q = poly[k], poly[k % #poly + 1]
				if p[3] > i then
					table.insert(edges, { p[1], p[2], q[1], q[2] })
				end
			end
		end
		local base = if skin.tier == 0 then 0.022 else 0.026 + 0.003 * skin.tier
		for _, e in edges do
			-- keep the parts of the crack that are inside the region (sampled)
			local ez0, ey0, ez1, ey1 = e[1], e[2], e[3], e[4]
			local len = math.sqrt((ez1 - ez0) ^ 2 + (ey1 - ey0) ^ 2)
			local steps = math.max(2, math.ceil(len / 0.02))
			local runStart: number? = nil
			local thick = base * (0.75 + rand() * 0.5)
			for k = 0, steps do
				local t = k / steps
				local ok = deepInside(loops, ez0 + (ez1 - ez0) * t, ey0 + (ey1 - ey0) * t, 0.04)
				if ok and not runStart then
					runStart = t
				end
				if runStart and (not ok or k == steps) then
					local t1 = if ok then t else (k - 1) / steps
					if (t1 - runStart) * len > 0.04 then
						strip(
							K,
							x,
							ez0 + (ez1 - ez0) * runStart,
							ey0 + (ey1 - ey0) * runStart,
							ez0 + (ez1 - ez0) * t1,
							ey0 + (ey1 - ey0) * t1,
							thick,
							through,
							skin.vein
						)
					end
					runStart = nil
				end
			end
		end
	else
		local stars = math.clamp(math.floor(a * (5 + 2 * skin.tier) + 0.5), 1, 14)
		for _ = 1, stars do
			local z, y = randomDeep(loops, 0.05, rand)
			if z then
				local s = 0.025 + rand() * 0.03
				K.boxCF(CF.new(x, y, z) * CF.Angles(math.pi / 4, 0, 0), V3.new(through + 0.004, s, s), skin.star, NEON)
			end
		end
		if a > 0.25 then
			for _ = 1, if skin.tier >= 2 then 2 else 1 do
				local z, y = randomDeep(loops, 0.14, rand)
				if z then
					K.cylCF(CF.new(x, y, z), w + 0.008, 0.14 + rand() * 0.1, skin.nebula, NEON).Transparency = 0.7
				end
			end
		end
	end
end

-- The highest / lowest surface over z (design studs), from the box prims.
local function surface(data: any, scale: number, z: number, top: boolean): number?
	local best: number? = nil
	for _, region in data.regions do
		for _, p in region.prims do
			if p[1] == "b" and p[2] * scale <= z and z <= p[3] * scale then
				local y = (if top then p[5] else p[4]) * scale
				if best == nil or (top and y > best) or (not top and y < best) then
					best = y
				end
			end
		end
	end
	return best
end

-- Builds a level's blaster: a Kenney shape with the Ore Glow skin. Returns the model, anchors, kind.
function Kenney.gun(Loader: any, level: number, oreId: string): (any, any, string)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local name = Kenney.Models[math.clamp(level, 1, #Kenney.Models)]
	local skin = Glow.skinFor(Loader, level, oreId)
	for _, key in { "vein", "rim", "edge" } do
		local c = skin[key]
		local luma = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		skin[key] = c:Lerp(BLACK, math.max(0, luma - 0.55) * 0.9)
	end
	local model = roblox.Instance.new("Model")
	model.Name = "Kenney" .. level .. oreId
	local S = Kenney.Scale
	local hue, sat = skin.base:ToHSV()
	local second = if skin.magma then C3.fromRGB(40, 36, 38) else C3.fromHSV(hue, sat, 0.4)
	local COLORS = { mid = C3.fromRGB(52, 55, 64), dark = C3.fromRGB(28, 29, 34) }
	local data, cx = Kenney.shape(Loader, model, name, S, function(region)
		if region.role == "body" then
			return skin.base, nil, 0
		elseif region.role == "light" then
			return second, nil, 0
		end
		return COLORS[region.role], nil, 0
	end)
	local K = Concepts.kit(model)
	local rand = Glow.rng(level * 7919 + #oreId * 104729 + 31)
	-- the pattern on the colored body and (rims only) on the light steel
	local largest, largestArea = nil, 0
	for _, region in data.regions do
		if region.role == "body" then
			local loops = scaledLoops(region, S)
			pattern(K, skin, (region.c - cx) * S, loops, region.w * S, true, rand)
			local a = loopsArea(loops)
			if a > largestArea then
				largest, largestArea = region, a
			end
		end
	end
	-- anchors (design studs)
	local b = data.bounds
	local zFront, zBack = b[1] * S, b[2] * S
	local muzzleY = 0
	do
		local sum, n = 0, 0
		for _, region in data.regions do
			for _, p in region.prims do
				if p[1] == "b" and p[2] * S <= zFront + 0.02 then
					sum += (p[4] + p[5]) / 2 * S
					n += 1
				end
			end
		end
		muzzleY = if n > 0 then sum / n else 0
	end
	local hand = HANDS[name]
	local support = SUPPORTS[name]
	local anchors: any = {
		hand = V3.new(0, hand[2] * S, hand[1] * S),
		support = V3.new(0, support[2] * S, support[1] * S),
		muzzle = V3.new(0, muzzleY, zFront),
	}
	if Kenney.Stocks[name] then
		local zs = zBack - 0.03
		local top = surface(data, S, zs, true) or 0
		local bottom = surface(data, S, zs, false) or 0
		anchors.stock = V3.new(0, (top + bottom) / 2, zBack)
	end
	if largest then
		local loops = scaledLoops(largest, S)
		local z0, z1, y0, y1 = bbox(loops)
		local zt = z0 + (z1 - z0) * 0.62
		anchors.top = V3.new(0, surface(data, S, zt, true) or y1, zt)
		anchors.side = V3.new((largest.w * S) / 2, (y0 + y1) / 2, z0 + (z1 - z0) * 0.3)
		local zst = zBack - (zBack - zFront) * 0.12
		anchors.stockTop = V3.new(0, surface(data, S, zst, true) or y1, zst)
		local zb = zFront + 0.25
		local t = surface(data, S, zb, true) or (muzzleY + 0.1)
		local bt = surface(data, S, zb, false) or (muzzleY - 0.1)
		anchors.barrel = { z0 = zFront + 0.05, z1 = zFront + 0.5, y = muzzleY, d = math.max(0.12, t - bt) }
		anchors.crown = { z = zFront + 0.35, r = math.max(0.06, (t - bt) / 2) }
	end
	Concepts.decorate(K, { shard = skin.shard, glow = skin.shard:Lerp(skin.glow, 0.45), ore = skin.ore }, skin.tier, anchors)
	-- flames / sparks around the gun from level 7
	if skin.tier >= 2 then
		local holder = K.part(
			"Part",
			CF.new(0, (b[3] + b[4]) / 2 * S, (zFront + zBack) / 2),
			V3.new(0.5, (b[4] - b[3]) * S, (zBack - zFront) * 0.85),
			skin.glow
		)
		holder.Transparency = 1
		holder.Name = "Effects"
		local emitter = roblox.Instance.new("ParticleEmitter")
		emitter.Name = if skin.magma then "GunFlame" else "GunSpark"
		emitter.Texture = if skin.magma
			then "rbxasset://textures/particles/fire_main.dds"
			else "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = roblox.ColorSequence.new(skin.glow)
		emitter.Parent = holder
	end
	local kind = if Kenney.Stocks[name] then "rifle" elseif level >= 3 then "carbine" else "pistol"
	return model, anchors, kind
end

-- The ore of every level in the showcase (BlasterBuilder gallery skins).
Kenney.Lineup = { "", "Copper", "Azurium", "Amethyst", "Gold", "Ruby", "Sapphire", "Emerald", "Stormcore", "Heartstone" }

-- "blaster_kenney": the ten levels floating in the evening sky (two rows), and close-ups off to the side.
function Kenney.build(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterKenney"
	root.Parent = parent
	for level, oreId in Kenney.Lineup do
		local model = Kenney.gun(Loader, level, oreId)
		local row = if level <= 5 then 0 else 1
		local col = (level - 1) % 5
		local x = -12 + col * 6 + (if row == 1 then 0.6 else 0)
		Concepts.present(model, CF.new(x, 205 - row * 4.2, 0) * CF.Angles(0, -1.3, 0) * CF.Angles(0.08, 0, 0.03), 1, root)
		-- the close-up copy
		local copy = Kenney.gun(Loader, level, oreId)
		Concepts.present(copy, CF.new(100 + level * 40, 200, 0) * CF.Angles(0, -1.25, 0) * CF.Angles(0.1, 0, 0.05), 1.4, root)
	end
	return root
end

return Kenney
