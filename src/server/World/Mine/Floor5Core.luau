--[[
	Mine floor 5, HEARTSTONE CORE (blaster 9+, reached only by the elevator):
	the heart of the world, a starry violet void (docs/plans/MINE_FLOORS_PLAN.md,
	story: the Heartstone, the living ember at the world's core, cracked in the
	Shattering). Contract: MineKit's header.

	Layout (local to `origin`, +Z = front where players arrive):
	  Landing   (front)   elevator stop, the BLASTER LV 9+ gate, floor sign
	  Hub       (middle)  the Mine Lift under a floating hoist rock, a rune circle
	  West/East (sides)   rock fields
	  Deep      (back)    the richest rock field and the Giant Crystal spot,
	                      right under the Heartstone
	  Heartstone (far back) a giant cracked pink crystal heart floating over the
	                      void: bright core through the cracks, light beams,
	                      two rings of orbiting debris, a rock cradle under it
	Every island: a flat walkable top with a light rim and glowing low rails, a
	jagged faceted underside tapering down like an upside-down mountain, pink
	veins, crystals and hanging shards. Glowing bridges (pink/aqua edges) join
	them; star motes, floating shards and far islets fill the void.
	No ceiling, so opts.Cutaway changes nothing. About 2.6k parts, 18 lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local MineKit = require(World:WaitForChild("Mine"):WaitForChild("MineKit"))

local Floor = {}

Floor.Index = 5
Floor.Size = Vector3.new(160, 80, 140)

---------------------------------------------------------------- palette and part presets

local rgb = Color3.fromRGB
local PAL = MineFloors.get(5).Palette
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

local ROCK = PAL.Mid
local ROCK_LIGHT = PAL.Light
local ROCK_DARK = PAL.Dark
local PINK = PAL.Crystal
local AQUA = PAL.Crystal2
local ACCENT = PAL.Accent

local TOP = rgb(78, 62, 130) -- island tops (darker than the rocks so they pop)
local RIM = rgb(132, 112, 186) -- the light curb around every island
local BAND_A = rgb(104, 86, 156)
local BAND_B = rgb(84, 70, 134)
local UNDER_A = rgb(116, 88, 168) -- underside facets, light to dark toward the tip
local UNDER_B = rgb(92, 68, 142)
local UNDER_C = rgb(72, 52, 116)
local UNDER_D = rgb(54, 40, 92)
local PATH = rgb(112, 98, 166)
local PATH2 = rgb(100, 88, 154)
local DECK = rgb(118, 102, 172)
local DECK2 = rgb(100, 86, 154)
local POST = rgb(46, 38, 78)
local RAIL = rgb(196, 120, 255) -- violet rail glow
local HEART = rgb(255, 96, 162)
local HEART_LIGHT = rgb(255, 156, 204)
local HEART_DEEP = rgb(176, 30, 98)
local CORE = rgb(255, 222, 240)
local STARS = { rgb(255, 244, 255), rgb(255, 244, 255), rgb(255, 150, 214), rgb(150, 255, 232), rgb(196, 166, 255) }

local SOLID: Geo.PartProps = { CanTouch = false, CanQuery = true, CanCollide = true }
local DECOR: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = true }
local GHOST: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false }
local GLOW: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local RAILP: Geo.PartProps = { CanTouch = false, CanQuery = false, CanCollide = true, CastShadow = false }

local UP = Vector3.new(0, 1, 0)
local TOP_Y = 50 -- nothing reaches higher above the origin (Floor.Size.Y = 80: about -30 .. +50)

-- every builder below works in floor-local space; O maps it to the world
local O = CFrame.identity

---------------------------------------------------------------- part helpers

local function blk(parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, props: Geo.PartProps?): Part
	return Geo.block(parent, O * cf, size, color, mat or SMOOTH, props or DECOR)
end

local function wdg(parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, props: Geo.PartProps?): WedgePart
	return Geo.wedge(parent, O * cf, size, color, mat or SMOOTH, props or DECOR)
end

local function tri(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thick: number, color: Color3, mat: Enum.Material, normal: Vector3, props: Geo.PartProps)
	Geo.triangle(parent, O * a, O * b, O * c, thick, color, mat, O:VectorToWorldSpace(normal), props)
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

-- A frame at `pos` whose UpVector is `up`.
local function upFrame(pos: Vector3, up: Vector3): CFrame
	local u = up.Unit
	local ref = if math.abs(u.Z) < 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local right = u:Cross(ref).Unit
	local back = right:Cross(u).Unit
	return CFrame.fromMatrix(pos, right, u, back)
end

-- A bar from p to q (thick x thick cross-section).
local function bar(parent: Instance, p: Vector3, q: Vector3, thick: number, color: Color3, mat: Enum.Material, props: Geo.PartProps): Part?
	local d = q - p
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (p + q) / 2
	return blk(parent, CFrame.lookAt(mid, q), Vector3.new(thick, thick, len + thick * 0.5), color, mat, props)
end

-- A flat glowing strip from p to q lying on a surface whose normal is `up`.
local function strip(parent: Instance, p: Vector3, q: Vector3, up: Vector3, width: number, color: Color3)
	local d = q - p
	local len = d.Magnitude
	if len < 0.05 then
		return
	end
	local mid = (p + q) / 2
	blk(parent, CFrame.lookAt(mid, q, up), Vector3.new(width, 0.16, len + width * 0.5), color, NEON, GLOW)
end

-- A pointed shard (diamond body + ridge tip) growing from `base` along its UpVector.
local function shard(parent: Instance, base: CFrame, height: number, width: number, color: Color3, tipColor: Color3, mat: Enum.Material, props: Geo.PartProps)
	local body = base * CFrame.Angles(0, math.pi / 4, 0)
	local bodyH = height * 0.62
	local tipH = height - bodyH
	blk(parent, body * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), color, mat, props)
	local tipAt = body * CFrame.new(0, bodyH + tipH / 2, 0)
	wdg(parent, tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tipColor, mat, props)
	wdg(parent, tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(width, tipH, width / 2), color, mat, props)
end

-- A glowing crystal (Style.crystal: neon, lighter tip) in floor-local space.
local function crystal(parent: Instance, base: CFrame, height: number, width: number, color: Color3)
	Style.crystal(parent, O * base, height, width, color)
end

---------------------------------------------------------------- 2D polygon helpers (XZ plane)

local function v3(p: Vector2, y: number): Vector3
	return Vector3.new(p.X, y, p.Y)
end

local function lerp2(a: Vector2, b: Vector2, t: number): Vector2
	return a + (b - a) * t
end

local function segDist(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 1e-9 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end

local function inside(poly: { Vector2 }, p: Vector2): boolean
	local hit = false
	local n = #poly
	local j = n
	for i = 1, n do
		local a, b = poly[i], poly[j]
		if (a.Y > p.Y) ~= (b.Y > p.Y) then
			local x = (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X
			if p.X < x then
				hit = not hit
			end
		end
		j = i
	end
	return hit
end

local function edgeDist(poly: { Vector2 }, p: Vector2): number
	local best = math.huge
	for i = 1, #poly do
		best = math.min(best, segDist(p, poly[i], poly[i % #poly + 1]))
	end
	return best
end

-- Where the segment from `from` (inside the polygon) toward `to` leaves it.
local function exitPoint(poly: { Vector2 }, from: Vector2, to: Vector2): Vector2
	local d = to - from
	local best = 1
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local e = b - a
		local den = d.X * e.Y - d.Y * e.X
		if math.abs(den) > 1e-9 then
			local w = a - from
			local t = (w.X * e.Y - w.Y * e.X) / den
			local u = (w.X * d.Y - w.Y * d.X) / den
			if t > 0 and t < best and u >= 0 and u <= 1 then
				best = t
			end
		end
	end
	return from + d * best
end

-- Outward unit normal of edge a-b of a polygon around center c.
local function outward(c: Vector2, a: Vector2, b: Vector2): Vector2
	local e = (b - a).Unit
	local nrm = Vector2.new(e.Y, -e.X)
	if nrm:Dot((a + b) / 2 - c) < 0 then
		nrm = -nrm
	end
	return nrm
end

-- A rounded-rectangle outline (superellipse) with a little jitter: n points around c.
local function outline(c: Vector2, hx: number, hz: number, n: number, rng: Rng.Rng): { Vector2 }
	local pts = {}
	local spin = rng:range(0, 0.3)
	for i = 0, n - 1 do
		local a = spin + (i / n) * math.pi * 2 + rng:range(-0.06, 0.06)
		local ca, sa = math.cos(a), math.sin(a)
		local f = rng:range(0.94, 1.03)
		local x = hx * f * math.sign(ca) * math.abs(ca) ^ 0.62
		local z = hz * f * math.sign(sa) * math.abs(sa) ^ 0.62
		table.insert(pts, Vector2.new(c.X + x, c.Y + z))
	end
	return pts
end

---------------------------------------------------------------- floating rock bodies

type BodyOpts = {
	Band: number?, -- height of the vertical band under the top (default 4)
	TopColor: Color3?,
	Walk: boolean?, -- walkable top (raycastable)
	Ring: boolean?, -- a second ring of facets halfway down (default true)
	Veins: number?, -- chance of a glowing vein per facet
	Crystals: number?, -- crystals poking out of the underside
	Spikes: number?, -- hanging shards under the rim
	Debris: number?, -- crumbs floating under the tip
	Glow: Color3?, -- vein color
	Seam: Color3?, -- a glowing line along the bottom of the band
}

--[[
	A floating rock: a flat top (fan of triangles at `top`), a vertical band
	under the outline, and a jagged faceted underside tapering down `depth`
	studs like an upside-down mountain, with glowing veins, crystals and
	hanging shards.
]]
local function rockBody(parent: Instance, c: Vector2, top: number, poly: { Vector2 }, depth: number, rng: Rng.Rng, o: BodyOpts)
	local n = #poly
	local band = o.Band or 4
	local topColor = o.TopColor or TOP
	local topProps = if o.Walk then SOLID else DECOR
	local glow = o.Glow or PINK
	local center = v3(c, top)
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		tri(parent, center, v3(a, top), v3(b, top), 1.2, Geo.vary(topColor, rng, 0.025), SMOOTH, UP, topProps)
	end
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		local out = outward(c, a, b)
		local mid = (a + b) / 2
		local pos = v3(mid - out * 0.6, top - 0.3 - (band - 0.3) / 2)
		local cf = CFrame.lookAt(pos, pos + v3(out, 0))
		blk(parent, cf, Vector3.new((b - a).Magnitude + 0.9, band - 0.3, 1.6), Geo.vary(if i % 2 == 0 then BAND_A else BAND_B, rng, 0.03), SMOOTH, GHOST)
		if o.Seam then
			local seam = v3(mid + out * 0.32, top - band + 0.2)
			blk(parent, CFrame.lookAt(seam, seam + v3(out, 0)), Vector3.new((b - a).Magnitude + 0.5, 0.36, 0.3), o.Seam, NEON, GLOW)
		end
	end
	-- the underside: rim ring -> jittered middle ring -> apex
	local r0: { Vector3 } = {}
	local r1: { Vector3 } = {}
	for i = 1, n do
		local p = poly[i]
		local dir = p - c
		local out0 = if dir.Magnitude > 1e-3 then dir.Unit else Vector2.new(1, 0)
		r0[i] = v3(p + out0 * 0.2, top - band)
		r1[i] = v3(c + dir * rng:range(0.5, 0.72), top - band - depth * rng:range(0.26, 0.42))
	end
	local apex = Vector3.new(c.X + rng:range(-2, 2), top - depth, c.Y + rng:range(-2, 2))
	local ring = o.Ring ~= false
	for i = 1, n do
		local j = i % n + 1
		local midXZ = (poly[i] + poly[j]) / 2 - c
		local outN = v3(if midXZ.Magnitude > 1e-3 then midXZ.Unit else Vector2.new(1, 0), -0.5).Unit
		local colA = Geo.vary(if i % 2 == 0 then UNDER_A else UNDER_B, rng, 0.04)
		local colB = Geo.vary(if i % 2 == 0 then UNDER_C else UNDER_D, rng, 0.04)
		if ring then
			tri(parent, r0[i], r0[j], r1[j], 1.4, colA, SMOOTH, outN, GHOST)
			tri(parent, r0[i], r1[j], r1[i], 1.4, colA, SMOOTH, outN, GHOST)
			tri(parent, r1[i], r1[j], apex, 1.4, colB, SMOOTH, outN, GHOST)
		else
			tri(parent, r0[i], r0[j], apex, 1.4, colA, SMOOTH, outN, GHOST)
		end
		-- glowing veins running down the facet
		if ring and rng:chance(o.Veins or 0) then
			local u0 = rng:range(0.25, 0.75)
			local function on(u: number, v: number): Vector3
				return r0[i]:Lerp(r0[j], u):Lerp(r1[i]:Lerp(r1[j], u), v)
			end
			local faceN = (r0[j] - r0[i]):Cross(r1[i] - r0[i]).Unit
			if faceN:Dot(outN) < 0 then
				faceN = -faceN
			end
			local p1 = on(u0, 0.08) + faceN * 0.12
			local p2 = on(math.clamp(u0 + rng:range(-0.25, 0.25), 0.1, 0.9), 0.5) + faceN * 0.12
			local p3 = on(math.clamp(u0 + rng:range(-0.3, 0.3), 0.1, 0.9), 0.92) + faceN * 0.12
			strip(parent, p1, p2, faceN, 0.44, glow)
			strip(parent, p2, p3, faceN, 0.34, glow)
			if rng:chance(0.6) then
				local lowN = (r1[j] - r1[i]):Cross(apex - r1[i]).Unit
				if lowN:Dot(outN) < 0 then
					lowN = -lowN
				end
				local q1 = r1[i]:Lerp(r1[j], rng:range(0.3, 0.7)):Lerp(apex, 0.06) + lowN * 0.12
				local q2 = r1[i]:Lerp(r1[j], rng:range(0.35, 0.65)):Lerp(apex, rng:range(0.45, 0.7)) + lowN * 0.12
				strip(parent, q1, q2, lowN, 0.32, glow)
			end
		end
	end
	-- crystals poking out of the underside (pointing out and down)
	for _ = 1, o.Crystals or 0 do
		local i = rng:int(1, n)
		local j = i % n + 1
		local at = r0[i]:Lerp(r0[j], rng:range(0.3, 0.7)):Lerp(r1[i]:Lerp(r1[j], 0.5), rng:range(0.3, 0.6))
		local dirXZ = Vector3.new(at.X - c.X, 0, at.Z - c.Y)
		local dir = (dirXZ.Unit * 0.7 + Vector3.new(0, -0.7, 0)).Unit
		local h = rng:range(2.5, 5)
		crystal(parent, upFrame(at - dir * 0.6, dir), h, h * 0.26, if rng:chance(0.5) then PINK else AQUA)
	end
	-- hanging shards under the middle ring
	for _ = 1, o.Spikes or 0 do
		local i = rng:int(1, n)
		local at = r1[i]:Lerp(apex, rng:range(0.05, 0.3))
		local len = rng:range(5, 10)
		local w = rng:range(1.8, 3.2)
		local tilt = CFrame.Angles(math.pi + rng:range(-0.25, 0.25), rng:range(0, math.pi), rng:range(-0.25, 0.25))
		shard(parent, CFrame.new(at + UP * 1.2) * tilt, len, w, Geo.vary(ROCK, rng, 0.05), Geo.vary(ROCK_DARK, rng, 0.05), SMOOTH, GHOST)
	end
	-- crumbs floating under the tip
	for k = 1, o.Debris or 0 do
		local s = rng:range(0.8, 2.2)
		local at = apex + Vector3.new(rng:range(-3, 3), -1.5 - k * rng:range(1.1, 1.4), rng:range(-3, 3))
		blk(parent, CFrame.new(at) * Geo.randomTilt(rng, 1.2), Vector3.new(s, s * 0.8, s), Geo.vary(ROCK, rng, 0.06), SMOOTH, GHOST)
	end
end

---------------------------------------------------------------- islands

type Opening = { P: Vector2, R: number }

type Island = {
	Name: string,
	C: Vector2,
	Top: number,
	Poly: { Vector2 },
	Depth: number,
	Deep: boolean,
	Openings: { Opening },
	Paths: { { Vector2 } },
	Avoid: { Opening }, -- no rock spawns here (lift, giant, rune circle)
	Spawns: { Vector2 },
}

local function newIsland(name: string, c: Vector2, half: Vector2, top: number, depth: number, n: number, deep: boolean): Island
	local rng = Rng.new("Floor5Island" .. name)
	return {
		Name = name,
		C = c,
		Top = top,
		Poly = outline(c, half.X, half.Y, n, rng),
		Depth = depth,
		Deep = deep,
		Openings = {},
		Paths = {},
		Avoid = {},
		Spawns = {},
	}
end

local function pathDist(isl: Island, p: Vector2): number
	local best = math.huge
	for _, line in isl.Paths do
		for k = 1, #line - 1 do
			best = math.min(best, segDist(p, line[k], line[k + 1]))
		end
	end
	return best
end

local function nearOpening(isl: Island, p: Vector2): boolean
	for _, o in isl.Openings do
		if (p - o.P).Magnitude < o.R then
			return true
		end
	end
	return false
end

-- Points along the outline inset by `inset`, about `step` studs apart.
local function perimeter(isl: Island, inset: number, step: number): { Vector2 }
	local poly, c = isl.Poly, isl.C
	local n = #poly
	local ins: { Vector2 } = {}
	for i = 1, n do
		local prev, cur, nxt = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]
		local o1 = outward(c, prev, cur)
		local o2 = outward(c, cur, nxt)
		local bis = (o1 + o2).Unit
		ins[i] = cur - bis * (inset / math.max(0.5, bis:Dot(o1)))
	end
	local pts = {}
	for i = 1, n do
		local a, b = ins[i], ins[i % n + 1]
		local k = math.max(1, math.ceil((b - a).Magnitude / step))
		for s = 0, k - 1 do
			table.insert(pts, lerp2(a, b, s / k))
		end
	end
	return pts
end

-- The light curb and the glowing low rails around an island (gaps at its openings).
local function rails(parent: Instance, isl: Island)
	local pts = perimeter(isl, 0.7, 8.5)
	local n = #pts
	local top = isl.Top
	local open: { boolean } = {}
	for i = 1, n do
		open[i] = not nearOpening(isl, (pts[i] + pts[i % n + 1]) / 2)
	end
	for i = 1, n do
		local j = i % n + 1
		local a, b = pts[i], pts[j]
		if open[i] then
			local mid = (a + b) / 2
			local pos = v3(mid, top - 0.1)
			blk(parent, CFrame.lookAt(pos, v3(b, top - 0.1)), Vector3.new(1.4, 0.7, (b - a).Magnitude + 0.7), RIM, SMOOTH, SOLID)
			bar(parent, v3(a, top + 2.15), v3(b, top + 2.15), 0.34, RAIL, NEON, RAILP)
		end
		-- a post wherever a rail piece starts or ends
		local prev = (i - 2) % n + 1
		if open[i] or open[prev] then
			blk(parent, CFrame.new(v3(a, top + 1.35)), Vector3.new(0.7, 2.3, 0.7), POST, SMOOTH, SOLID)
			blk(parent, CFrame.new(v3(a, top + 2.6)) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.55, 0.3, 0.55), RAIL, NEON, GLOW)
		end
	end
end

-- Flagstone path tiles along the island's paths.
local function pathTiles(parent: Instance, isl: Island, rng: Rng.Rng)
	local placed: { Vector2 } = {}
	local k = 0
	for _, line in isl.Paths do
		for s = 1, #line - 1 do
			local a, b = line[s], line[s + 1]
			local d = b - a
			local len = d.Magnitude
			local count = math.max(1, math.floor(len / 3.3))
			local step = len / count
			for t = 0, count - 1 do
				local p = a + d.Unit * (step * (t + 0.5))
				local free = inside(isl.Poly, p) and edgeDist(isl.Poly, p) > 1.8
				for _, q in placed do
					if (q - p).Magnitude < 3.0 then
						free = false
						break
					end
				end
				if free then
					table.insert(placed, p)
					k += 1
					local y = isl.Top + (if k % 2 == 0 then 0.0 else 0.02)
					local pos = v3(p, y)
					local cf = CFrame.lookAt(pos, pos + v3(d, 0)) * CFrame.Angles(0, rng:range(-0.05, 0.05), 0)
					blk(parent, cf, Vector3.new(7.4, 0.24, step - 0.35), if k % 2 == 0 then PATH else PATH2, SMOOTH, SOLID)
				end
			end
		end
	end
end

-- Glowing cracks across an island top (away from the paths).
local function cracks(parent: Instance, isl: Island, rng: Rng.Rng, count: number)
	for _ = 1, count do
		local start: Vector2? = nil
		for _ = 1, 12 do
			local p = isl.C + Vector2.new(rng:range(-1, 1), rng:range(-1, 1)) * 18
			if inside(isl.Poly, p) and edgeDist(isl.Poly, p) > 4 and pathDist(isl, p) > 6 then
				start = p
				break
			end
		end
		if start then
			local p = start
			local a = rng:range(0, math.pi * 2)
			local color = if rng:chance(0.6) then PINK else AQUA
			for _ = 1, rng:int(3, 5) do
				local q = p + Vector2.new(math.cos(a), math.sin(a)) * rng:range(1.6, 3.2)
				if not inside(isl.Poly, q) or edgeDist(isl.Poly, q) < 2.5 or pathDist(isl, q) < 4.6 then
					break
				end
				strip(parent, v3(p, isl.Top + 0.05), v3(q, isl.Top + 0.05), UP, 0.3, color)
				p = q
				a += rng:range(-0.9, 0.9)
			end
		end
	end
end

-- Rock spawns on a hex grid: inside, 5 from the edge, clear of paths and avoid circles.
-- Tries every grid offset and keeps the one that fits the most rocks.
local function placeSpawns(isl: Island, spacing: number, spawns: MineKit.Spawns)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in isl.Poly do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
	end
	local function fits(p: Vector2): boolean
		if not inside(isl.Poly, p) or edgeDist(isl.Poly, p) < 5 or pathDist(isl, p) < 6.5 then
			return false
		end
		for _, a in isl.Avoid do
			if (p - a.P).Magnitude < a.R then
				return false
			end
		end
		return true
	end
	local best: { Vector2 } = {}
	local rowStep = spacing * 0.866
	for ox = 0, spacing - 0.5, 1 do
		for oz = 0, rowStep - 0.5, 1 do
			local found: { Vector2 } = {}
			local row = 0
			local z = minZ + oz
			while z <= maxZ do
				local x = minX + ox + (row % 2) * spacing * 0.5
				while x <= maxX do
					local p = Vector2.new(x, z)
					if fits(p) then
						table.insert(found, p)
					end
					x += spacing
				end
				z += rowStep
				row += 1
			end
			if #found > #best then
				best = found
			end
		end
	end
	for _, p in best do
		table.insert(isl.Spawns, p)
		spawns.add(O * CFrame.new(v3(p, isl.Top)), isl.Deep)
	end
end

-- Is `p` a free decoration spot of radius r on the island (not on paths, spawns, openings)?
local function freeSpot(isl: Island, p: Vector2, r: number): boolean
	if not inside(isl.Poly, p) or edgeDist(isl.Poly, p) < r + 1.4 or pathDist(isl, p) < r + 4.3 or nearOpening(isl, p) then
		return false
	end
	for _, s in isl.Spawns do
		if (s - p).Magnitude < r + 4.2 then
			return false
		end
	end
	for _, a in isl.Avoid do
		if (p - a.P).Magnitude < a.R then
			return false
		end
	end
	return true
end

type Link = { A: Island, B: Island, From: Vector2, To: Vector2, Rise: number, Edge: Color3, Under: Color3, PA: Vector2?, PB: Vector2? }

---------------------------------------------------------------- props

-- A standing rune stone with glowing glyphs on its front (base LookVector).
local function runeStone(parent: Instance, base: CFrame, h: number, glow: Color3, rng: Rng.Rng)
	local m = model("RuneStone", parent)
	local lean = base * CFrame.Angles(rng:range(-0.06, 0.06), 0, rng:range(-0.08, 0.08))
	blk(m, base * CFrame.new(0, 0.25, 0), Vector3.new(2.8, 0.5, 1.9), Geo.vary(ROCK_DARK, rng, 0.04), SMOOTH, DECOR)
	blk(m, lean * CFrame.new(0, h / 2 + 0.3, 0), Vector3.new(1.9, h, 0.95), Geo.vary(ROCK_LIGHT, rng, 0.04), SMOOTH, DECOR)
	wdg(m, lean * CFrame.new(0, h + 0.3 + 0.45, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.95, 0.9, 1.9), Geo.vary(ROCK_LIGHT, rng, 0.04), SMOOTH, GHOST)
	local face = lean * CFrame.new(0, h * 0.55 + 0.3, -0.5)
	blk(m, face, Vector3.new(0.26, h * 0.56, 0.1), glow, NEON, GLOW)
	blk(m, face * CFrame.new(-0.34, h * 0.14, 0) * CFrame.Angles(0, 0, 0.7), Vector3.new(0.24, h * 0.26, 0.1), glow, NEON, GLOW)
	blk(m, face * CFrame.new(0.34, -h * 0.08, 0) * CFrame.Angles(0, 0, -0.7), Vector3.new(0.24, h * 0.26, 0.1), glow, NEON, GLOW)
	blk(m, face * CFrame.new(0, -h * 0.36, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.42, 0.42, 0.1), glow, NEON, GLOW)
end

-- A dark post with a glowing crystal on top (marks bridge heads).
local function crystalLamp(parent: Instance, base: CFrame, h: number, color: Color3)
	blk(parent, base * CFrame.new(0, h / 2, 0), Vector3.new(0.9, h, 0.9), POST, SMOOTH, DECOR)
	crystal(parent, base * CFrame.new(0, h + 0.1, 0), 2.4, 0.85, color)
end

-- A sign board with a neon frame and big glowing letters (both faces); cf = board center.
local function glowSign(parent: Instance, cf: CFrame, text: string, width: number, height: number, frame: Color3, textColor: Color3)
	local board = blk(parent, cf, Vector3.new(width, height, 0.5), ROCK_DARK, SMOOTH, DECOR)
	board.Name = "Sign"
	for _, side in { -1, 1 } do
		local z = side * 0.3
		blk(parent, cf * CFrame.new(0, height / 2 - 0.15, z), Vector3.new(width + 0.3, 0.3, 0.2), frame, NEON, GLOW)
		blk(parent, cf * CFrame.new(0, -height / 2 + 0.15, z), Vector3.new(width + 0.3, 0.3, 0.2), frame, NEON, GLOW)
		blk(parent, cf * CFrame.new(-width / 2 + 0.15, 0, z), Vector3.new(0.3, height, 0.2), frame, NEON, GLOW)
		blk(parent, cf * CFrame.new(width / 2 - 0.15, 0, z), Vector3.new(0.3, height, 0.2), frame, NEON, GLOW)
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "FrontText" else "BackText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.9, 0.72)
		label.Position = UDim2.fromScale(0.05, 0.14)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = textColor
		label.TextStrokeColor3 = frame
		label.TextStrokeTransparency = 0.3
		label.FontFace = Font.fromEnum(Style.SignFont)
		label.Parent = gui
	end
	return board
end

---------------------------------------------------------------- bridges

--[[
	A glowing bridge from anchor a to anchor b (island edge points at their
	top heights): a gently arched deck of violet slabs with neon edges, a dark
	keel with a glowing underline, low glowing rails, crystal lamps at both
	heads and a crystal pendant under the middle.
]]
local function bridge(parent: Instance, a: Vector3, b: Vector3, rise: number, edge: Color3, under: Color3, rng: Rng.Rng)
	local m = model("Bridge", parent)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local h = flat.Unit
	local right = h:Cross(UP)
	local A = a - h * 1.6
	local B = b + h * 1.6
	local function point(t: number): Vector3
		return A:Lerp(B, t) + UP * (rise * 4 * t * (1 - t) + 0.2)
	end
	local len = (B - A).Magnitude
	local n = math.max(4, math.ceil(len / 4))
	local width = 9
	for i = 0, n - 1 do
		local p0, p1 = point(i / n), point((i + 1) / n)
		local seg = p1 - p0
		local mid = (p0 + p1) / 2
		local up = right:Cross(seg.Unit)
		local cf = CFrame.lookAt(mid, mid + seg, up)
		local segLen = seg.Magnitude + 0.3
		blk(m, cf * CFrame.new(0, -0.4, 0), Vector3.new(width, 0.8, segLen), Geo.vary(if i % 2 == 0 then DECK else DECK2, rng, 0.02), SMOOTH, SOLID)
		for _, side in { -1, 1 } do
			blk(m, cf * CFrame.new(side * (width / 2 + 0.2), 0.05, 0), Vector3.new(0.42, 0.7, segLen), edge, NEON, GLOW)
		end
		blk(m, cf * CFrame.new(0, -1.25, 0), Vector3.new(width * 0.5, 1.0, segLen), ROCK_DARK, SMOOTH, GHOST)
		blk(m, cf * CFrame.new(0, -1.8, 0), Vector3.new(0.6, 0.2, segLen), under, NEON, GLOW)
	end
	-- rails: posts every other segment, a glowing top bar and a dark middle bar
	local ts: { number } = {}
	for k = 0, n, 2 do
		table.insert(ts, k / n)
	end
	if ts[#ts] < 1 then
		table.insert(ts, 1)
	end
	for _, side in { -1, 1 } do
		local off = right * side * (width / 2 + 0.35)
		for k, t in ts do
			local p = point(t) + off
			blk(m, CFrame.new(p + UP * 1.2), Vector3.new(0.7, 2.4, 0.7), POST, SMOOTH, SOLID)
			if k < #ts then
				local q = point(ts[k + 1]) + off
				bar(m, p + UP * 2.2, q + UP * 2.2, 0.34, edge, NEON, RAILP)
			end
		end
	end
	-- crystal lamps at both heads
	for _, head in { a + h * 1.2, b - h * 1.2 } do
		for _, side in { -1, 1 } do
			crystalLamp(m, CFrame.new(head + right * side * (width / 2 + 1.4)), 3.2, edge)
		end
	end
	-- a crystal pendant under the middle
	local mid = point(0.5)
	crystal(m, upFrame(mid - UP * 1.85, -UP), rng:range(3, 4.5), 1.1, under)
	return m
end

---------------------------------------------------------------- the Heartstone

-- A dashed glowing orbit with rock debris and small crystals on it.
local function orbit(parent: Instance, frame: CFrame, rx: number, rz: number, chunks: number, trail: Color3, rng: Rng.Rng)
	local function at(a: number): Vector3
		return frame * Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz)
	end
	local k = 48
	for j = 0, k - 1, 3 do
		local a0, a1 = j / k * math.pi * 2, (j + 2) / k * math.pi * 2
		bar(parent, at(a0), at(a1), 0.42, trail, NEON, GLOW)
	end
	for i = 1, chunks do
		local a = (i / chunks) * math.pi * 2 + rng:range(-0.12, 0.12)
		local p = at(a) + Vector3.new(rng:range(-1.2, 1.2), rng:range(-1.5, 1.5), rng:range(-1.2, 1.2))
		if i % 3 == 0 then
			local h = rng:range(2.2, 4.2)
			crystal(parent, CFrame.new(p) * Geo.randomTilt(rng, 1.4), h, h * 0.28, if rng:chance(0.5) then PINK else AQUA)
		else
			local s = rng:range(1.2, 3.4)
			blk(parent, CFrame.new(p) * Geo.randomTilt(rng, 1.4), Vector3.new(s, s * rng:range(0.6, 0.9), s * rng:range(0.7, 1)), Geo.vary(if rng:chance(0.5) then ROCK_LIGHT else RIM, rng, 0.05), SMOOTH, GHOST)
		end
	end
end

--[[
	The Heartstone: two fat faceted crystal lobes tilted apart from a shared
	bottom tip (a heart shape, ~40 studs tall), every facet pushed out a
	little so the bright core shows through the cracks; crystals grow from
	its lobes, light beams fan out of the core, two debris rings orbit it and
	a broken rock cradle floats under its tip.
]]
local function heartstone(parent: Instance, tip: Vector3, rng: Rng.Rng): Model
	local m = model("Heartstone", parent)
	local eqDist, eqR, topLen, sides = 30, 11.5, 13, 7
	local lobeCenters: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local axis = CFrame.new(tip) * CFrame.Angles(0, 0, -s * 0.42) * CFrame.Angles(0, rng:range(0, 1), 0)
		local lobe = axis * Vector3.new(0, eqDist, 0)
		table.insert(lobeCenters, lobe)
		local ring: { Vector3 } = {}
		for i = 1, sides do
			local a = (i / sides) * math.pi * 2
			local r = eqR * rng:range(0.92, 1.05)
			ring[i] = axis * Vector3.new(math.cos(a) * r, eqDist + rng:range(-1.5, 1.5), math.sin(a) * r)
		end
		local apex = axis * Vector3.new(rng:range(-1, 1), eqDist + topLen, rng:range(-1, 1))
		-- facets: { a, b, cap, normal, upper, index }; the most front-facing upper and
		-- lower facet of each lobe broke off in the Shattering and drift in front of it
		type Facet = { A: Vector3, B: Vector3, Cap: Vector3, N: Vector3, Upper: boolean, I: number }
		local facets: { Facet } = {}
		local bestUp, bestLow = 0, 0
		for i = 1, sides do
			local a, b = ring[i], ring[i % sides + 1]
			for _, cap in { apex, tip } do
				local nrm = (b - a):Cross(cap - a).Unit
				if nrm:Dot((a + b + cap) / 3 - lobe) < 0 then
					nrm = -nrm
				end
				table.insert(facets, { A = a, B = b, Cap = cap, N = nrm, Upper = cap == apex, I = i })
				local k = #facets
				local score = nrm.Z + nrm.X * s * 0.4
				if cap == apex and (bestUp == 0 or score > facets[bestUp].N.Z + facets[bestUp].N.X * s * 0.4) then
					bestUp = k
				elseif cap ~= apex and (bestLow == 0 or score > facets[bestLow].N.Z + facets[bestLow].N.X * s * 0.4) then
					bestLow = k
				end
			end
		end
		for k, f in facets do
			local a, b, cap, nrm, i = f.A, f.B, f.Cap, f.N, f.I
			local broken = k == bestUp or k == bestLow
			local off = nrm * (if broken then rng:range(5, 7) else rng:range(1.1, 2.6))
			local color = if f.Upper then (if i % 2 == 0 then HEART_LIGHT else HEART) else (if i % 2 == 0 then HEART else HEART_DEEP)
			local mat = if not f.Upper and i % 2 == 1 and not broken then NEON else SMOOTH
			if broken then
				-- a smaller, slightly turned shard
				local centroid = (a + b + cap) / 3
				local turn = CFrame.fromAxisAngle(nrm:Cross(UP).Unit, rng:range(0.25, 0.45))
				local function shrink(p: Vector3): Vector3
					return centroid + turn * ((p - centroid) * 0.72) + off
				end
				tri(m, shrink(a), shrink(b), shrink(cap), 1.6, Geo.vary(HEART_LIGHT, rng, 0.03), SMOOTH, nrm, GHOST)
			else
				tri(m, a + off, b + off, cap + off, 1.6, Geo.vary(color, rng, 0.03), mat, nrm, GHOST)
				-- a bright zigzag crack across some facets
				if rng:chance(0.55) then
					local p1 = a:Lerp(b, rng:range(0.2, 0.8)):Lerp(cap, rng:range(0.05, 0.2)) + off + nrm * 0.1
					local p2 = a:Lerp(b, rng:range(0.25, 0.75)):Lerp(cap, rng:range(0.3, 0.45)) + off + nrm * 0.1
					local p3 = a:Lerp(b, rng:range(0.3, 0.7)):Lerp(cap, rng:range(0.55, 0.75)) + off + nrm * 0.1
					strip(m, p1, p2, nrm, 0.42, CORE)
					strip(m, p2, p3, nrm, 0.32, CORE)
				end
			end
		end
		-- the bright core inside the lobe, seen through the cracks
		for k = 1, 2 do
			blk(m, CFrame.new(lobe) * Geo.randomTilt(rng, math.pi), Vector3.new(11 - k, 11 - k, 11 - k), CORE, NEON, GLOW)
		end
		blk(m, axis * CFrame.new(0, eqDist * 0.55, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(6, eqDist * 0.85, 6), CORE, NEON, GLOW)
		-- crystals growing out of the lobe: up-and-out (pink) and sideways (aqua)
		local outer = axis.RightVector * s
		for k = 1, 3 do
			local dir = (axis.UpVector * rng:range(0.6, 1.0) + outer * rng:range(0.4, 1.0) + Vector3.new(0, 0, rng:range(-0.4, 0.4))).Unit
			local base = lobe + dir * (eqR * 0.7)
			local h = math.min(rng:range(7, 12) / k ^ 0.3, (TOP_Y - base.Y) / math.max(dir.Y, 0.2))
			crystal(m, upFrame(base, dir), h, h * 0.24, if k == 2 then AQUA else HEART_LIGHT)
		end
		for k = 1, 3 do
			local dir = (outer * rng:range(0.6, 1.0) + Vector3.new(0, rng:range(-0.9, -0.2), rng:range(-0.5, 0.5))).Unit
			local base = axis * Vector3.new(0, eqDist * rng:range(0.35, 0.75), 0)
			local h = rng:range(4, 8)
			crystal(m, upFrame(base + dir * 3, dir), h, h * 0.26, if k % 2 == 1 then AQUA else PINK)
		end
	end
	local heart = (lobeCenters[1] + lobeCenters[2]) / 2
	-- light: two lamps in front of the heart, one in each lobe for the cracks
	local lampA = blk(m, CFrame.new(heart + Vector3.new(-12, -2, 18)), Vector3.new(0.2, 0.2, 0.2), CORE, NEON, GLOW)
	lampA.Transparency = 1
	light(lampA, HEART, 60, 2.2)
	local lampB = blk(m, CFrame.new(heart + Vector3.new(12, 4, 18)), Vector3.new(0.2, 0.2, 0.2), CORE, NEON, GLOW)
	lampB.Transparency = 1
	light(lampB, HEART_LIGHT, 60, 1.8)
	local spark = blk(m, CFrame.new(heart + Vector3.new(0, -4, 0)) * CFrame.Angles(0.6, 0.8, 0.3), Vector3.new(5, 5, 5), CORE, NEON, GLOW)
	spark.Name = "HeartCore"
	Style.emitter(spark, "Sparkle", HEART_LIGHT, 10)
	-- light beams fanning out of the core
	for k, deg in { 12, 40, 66, 90, 114, 140, 168, 200, 232, 308, 340 } do
		local a = math.rad(deg + rng:range(-5, 5))
		local dir = Vector3.new(math.cos(a), math.sin(a), rng:range(-0.25, -0.05)).Unit
		local p0 = heart + dir * 11
		local length = rng:range(24, 34)
		if dir.Y > 0.05 then
			length = math.min(length, (TOP_Y - p0.Y) / dir.Y)
		end
		local beam = if length >= 4 then bar(m, p0, p0 + dir * length, if k % 3 == 0 then 0.9 else 0.5, if k % 2 == 0 then HEART_LIGHT else CORE, NEON, GLOW) else nil
		if beam then
			beam.Transparency = if k % 3 == 0 then 0.55 else 0.35
		end
	end
	-- two debris rings (squashed so they stay inside the floor's footprint)
	orbit(m, CFrame.new(heart + Vector3.new(0, -2, 0)) * CFrame.Angles(0.16, 0, 0.3), 31, 11, 22, ACCENT, rng)
	orbit(m, CFrame.new(heart + Vector3.new(0, 3, 0)) * CFrame.Angles(-0.12, 0, -0.36), 24, 9, 14, AQUA, rng)
	-- the broken rock cradle under the tip
	local cradleTop = tip.Y - 9
	local cc = Vector2.new(tip.X, tip.Z)
	local poly = outline(cc, 7, 7, 8, rng)
	rockBody(m, cc, cradleTop, poly, 14, rng, { Band = 2.5, Ring = false, Spikes = 2, Debris = 3 })
	for i = 1, 8, 2 do
		local p = poly[i]
		if p.Y - cc.Y > 3 then
			continue -- no claw toward the deep island's back rail
		end
		local dir = (Vector3.new(p.X - cc.X, 0, p.Y - cc.Y).Unit * 0.55 + UP).Unit
		local h = rng:range(5, 9)
		shard(m, upFrame(v3(p, cradleTop - 0.5) - Vector3.new(p.X - cc.X, 0, p.Y - cc.Y) * 0.12, dir), h, rng:range(1.6, 2.4), Geo.vary(ROCK, rng, 0.05), Geo.vary(ROCK_LIGHT, rng, 0.05), SMOOTH, GHOST)
	end
	local pool = blk(m, CFrame.new(cc.X, cradleTop + 0.1, cc.Y) * CFrame.Angles(0, math.pi / 8, 0), Vector3.new(8, 0.3, 8), PINK, NEON, GLOW)
	blk(m, CFrame.new(cc.X, cradleTop + 0.1, cc.Y) * CFrame.Angles(0, math.pi * 3 / 8, 0), Vector3.new(8, 0.3, 8), PINK, NEON, GLOW)
	light(pool, AQUA, 34, 1.6)
	local embers = blk(m, CFrame.new(cc.X, cradleTop + 1, cc.Y), Vector3.new(6, 0.2, 6), PINK, SMOOTH, GLOW)
	embers.Transparency = 1
	Style.emitter(embers, "Embers", HEART_LIGHT, 8)
	return m
end

---------------------------------------------------------------- the void

type Keepout = (p: Vector3) -> boolean

-- Star motes, floating crystal shards and little rocks drifting in the void.
local function voidDecor(parent: Instance, rng: Rng.Rng, blocked: Keepout)
	local m = model("Void", parent)
	local stars = model("StarMotes", m)
	local placed = 0
	for _ = 1, 900 do
		if placed >= 165 then
			break
		end
		local p = Vector3.new(rng:range(-80, 80), rng:range(-30, 48), rng:range(-70, 68))
		if not blocked(p) then
			placed += 1
			local color = STARS[rng:int(1, #STARS)]
			if rng:chance(0.1) then
				local s = rng:range(1.2, 2.2)
				local cf = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
				blk(stars, cf, Vector3.new(s, 0.18, 0.18), color, NEON, GLOW)
				blk(stars, cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(s, 0.18, 0.18), color, NEON, GLOW)
			else
				local s = rng:range(0.2, 0.55)
				blk(stars, CFrame.new(p) * Geo.randomTilt(rng, 1), Vector3.new(s, s, s), color, NEON, GLOW)
			end
		end
	end
	local drift = model("Drift", m)
	local count = 0
	for _ = 1, 400 do
		if count >= 28 then
			break
		end
		local p = Vector3.new(rng:range(-74, 74), rng:range(-22, 34), rng:range(-62, 60))
		if not blocked(p) then
			count += 1
			if count % 2 == 0 then
				local h = rng:range(1.4, 3.2)
				crystal(drift, CFrame.new(p) * Geo.randomTilt(rng, 1.5), h, h * 0.27, if rng:chance(0.55) then PINK else AQUA)
			else
				local s = rng:range(1.3, 3)
				local cf = CFrame.new(p) * Geo.randomTilt(rng, 1.5)
				blk(drift, cf, Vector3.new(s, s * 0.75, s * 0.9), Geo.vary(ROCK, rng, 0.06), SMOOTH, GHOST)
				blk(drift, cf * CFrame.new(s * 0.2, s * 0.32, 0) * Geo.randomTilt(rng, 0.5), Vector3.new(s * 0.6, s * 0.4, s * 0.6), Geo.vary(ROCK_LIGHT, rng, 0.05), SMOOTH, GHOST)
				if rng:chance(0.6) then
					crystal(drift, cf * CFrame.new(0, s * 0.3, 0), s * 0.9, s * 0.24, if rng:chance(0.5) then PINK else AQUA)
				end
			end
		end
	end
	return m
end

---------------------------------------------------------------- build

function Floor.build(parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	O = origin
	-- opts.Cutaway: no ceiling and no front wall here, so the cutaway looks the same
	local _cutaway = opts and opts.Cutaway
	local rng = Rng.new("Floor5Core")
	local m = model("MineFloor5", parent)
	m:SetAttribute("Floor", 5)
	local spawns = MineKit.spawns(m)

	-- islands (top center, half size, top height, underside depth)
	local landing = newIsland("Landing", Vector2.new(0, 56), Vector2.new(24, 12), 0, 22, 10, false)
	local hub = newIsland("Hub", Vector2.new(0, 16), Vector2.new(22, 17), 0, 25, 11, false)
	local west = newIsland("West", Vector2.new(-52, 12), Vector2.new(19, 18), 2.5, 27, 11, false)
	local east = newIsland("East", Vector2.new(52, 4), Vector2.new(19, 18), -2, 23, 11, false)
	local deep = newIsland("Deep", Vector2.new(0, -32), Vector2.new(40, 16), 3, 27, 14, true)
	local islands = { landing, hub, west, east, deep }

	-- bridges: anchors where the line between two inner points leaves each island
	local links: { Link } = {
		{ A = landing, B = hub, From = Vector2.new(0, 56), To = Vector2.new(0, 16), Rise = 1.2, Edge = AQUA, Under = PINK },
		{ A = hub, B = west, From = Vector2.new(0, 15), To = Vector2.new(-52, 15), Rise = 1.6, Edge = PINK, Under = AQUA },
		{ A = hub, B = east, From = Vector2.new(0, 7), To = Vector2.new(52, 7), Rise = 1.4, Edge = PINK, Under = AQUA },
		{ A = hub, B = deep, From = Vector2.new(0, 16), To = Vector2.new(0, -32), Rise = 2.0, Edge = PINK, Under = AQUA },
		{ A = west, B = deep, From = Vector2.new(-50, 8), To = Vector2.new(-30, -34), Rise = 1.6, Edge = AQUA, Under = PINK },
		{ A = east, B = deep, From = Vector2.new(50, 0), To = Vector2.new(30, -34), Rise = 1.2, Edge = AQUA, Under = PINK },
	}
	for _, link in links do
		local pa = exitPoint(link.A.Poly, link.From, link.To)
		local pb = exitPoint(link.B.Poly, link.To, link.From)
		link.PA, link.PB = pa, pb
		table.insert(link.A.Openings, { P = pa, R = 6.6 })
		table.insert(link.B.Openings, { P = pb, R = 6.6 })
	end
	local function anchor(k: number, first: boolean): Vector2
		local link = links[k]
		return (if first then link.PA else link.PB) :: Vector2
	end
	landing.Openings[1].R = 8.2 -- room for the gate posts

	-- paths (flagstones; rock spawns keep clear of them)
	local gateAt = anchor(1, true) + Vector2.new(0, 2.4)
	landing.Paths = { { Vector2.new(0, 63), anchor(1, true) }, { Vector2.new(-13, 52.5), Vector2.new(0, 51) } }
	hub.Paths = {
		{ anchor(1, false), anchor(4, true) },
		{ anchor(2, true), Vector2.new(0, 15) },
		{ anchor(3, true), Vector2.new(0, 7) },
	}
	west.Paths = { { anchor(2, false), Vector2.new(-41, 6), anchor(5, true) } }
	east.Paths = { { anchor(3, false), Vector2.new(41, -1), anchor(6, true) } }
	deep.Paths = { { anchor(5, false), Vector2.new(-18, -22), anchor(4, false), Vector2.new(18, -22), anchor(6, false) } }

	-- set pieces that keep rock spawns away
	local liftAt = Vector2.new(12, 25)
	local runeAt = Vector2.new(-12, 25)
	local giantAt = Vector2.new(0, -35)
	table.insert(hub.Avoid, { P = liftAt, R = 9 })
	table.insert(hub.Avoid, { P = runeAt, R = 9 })
	table.insert(deep.Avoid, { P = giantAt, R = 14 })
	table.insert(landing.Avoid, { P = Vector2.new(-13, 58), R = 10 }) -- elevator stop
	table.insert(landing.Avoid, { P = Vector2.new(15, 62), R = 9.5 }) -- floor sign

	-- island bodies, rails, paths, cracks
	local islandFolder = model("Islands", m)
	local bodyOpts: { [string]: BodyOpts } = {
		Landing = { Walk = true, Veins = 0.7, Crystals = 4, Spikes = 4, Debris = 3, Seam = ACCENT },
		Hub = { Walk = true, Veins = 0.7, Crystals = 5, Spikes = 5, Debris = 3, Glow = AQUA, Seam = AQUA },
		West = { Walk = true, Veins = 0.7, Crystals = 5, Spikes = 5, Debris = 3, Seam = ACCENT },
		East = { Walk = true, Veins = 0.7, Crystals = 5, Spikes = 4, Debris = 3, Glow = AQUA, Seam = AQUA },
		Deep = { Walk = true, Veins = 0.75, Crystals = 7, Spikes = 6, Debris = 3, Seam = ACCENT },
	}
	for _, isl in islands do
		local im = model(isl.Name .. "Island", islandFolder)
		local irng = Rng.new("Floor5Body" .. isl.Name)
		rockBody(im, isl.C, isl.Top, isl.Poly, isl.Depth, irng, bodyOpts[isl.Name])
		rails(im, isl)
		pathTiles(im, isl, irng)
	end

	-- rock spawns (the back island is the richest and all "deep")
	placeSpawns(hub, 8.6, spawns)
	placeSpawns(west, 10, spawns)
	placeSpawns(east, 10, spawns)
	placeSpawns(deep, 8.6, spawns)
	for _, isl in islands do
		cracks(islandFolder:FindFirstChild(isl.Name .. "Island") :: Instance, isl, Rng.new("Floor5Cracks" .. isl.Name), if isl.Deep then 4 else 2)
	end

	-- bridges
	local bridges = model("Bridges", m)
	for k, link in links do
		local pa, pb = anchor(k, true), anchor(k, false)
		bridge(bridges, v3(pa, link.A.Top), v3(pb, link.B.Top), link.Rise, link.Edge, link.Under, Rng.new("Floor5Bridge" .. k))
	end

	-- the landing: elevator stop at the left, the gate over the bridge head, the floor sign
	local props = model("Props", m)
	MineKit.elevator(m, O * CFrame.new(-13, 0, 59), Floor.Index)
	local gatePos = v3(gateAt, 0)
	MineKit.gate(m, O * CFrame.lookAt(gatePos, gatePos + Vector3.new(0, 0, 1)), 12, MineFloors.get(5).MinBlaster, { ROCK, ROCK_LIGHT, ROCK_DARK })
	local entrance = MineKit.marker(m, "Entrance", O * CFrame.new(0, 0, 60))
	entrance:SetAttribute("Floor", 5)
	-- a glowing arrival ring inlaid around the entrance
	for k = 0, 7 do
		local a0, a1 = k / 8 * math.pi * 2, (k + 1) / 8 * math.pi * 2
		local p0 = Vector3.new(math.cos(a0) * 3.6, 0.17, 60 + math.sin(a0) * 3.6)
		local p1 = Vector3.new(math.cos(a1) * 3.6, 0.17, 60 + math.sin(a1) * 3.6)
		strip(props, p0, p1, UP, 0.34, if k % 2 == 0 then AQUA else PINK)
	end
	local signAt = CFrame.new(15, 0, 62)
	for _, sx in { -6.4, 6.4 } do
		blk(props, signAt * CFrame.new(sx, 2.8, 0), Vector3.new(0.9, 5.6, 0.9), POST, SMOOTH, DECOR)
		blk(props, signAt * CFrame.new(sx, 5.75, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.7, 0.3, 0.7), PINK, NEON, GLOW)
	end
	-- the elevator's cables run up into a floating hoist rock
	local liftRock = model("ElevatorHoist", props)
	local erng = Rng.new("Floor5ElevatorHoist")
	local ec = Vector2.new(-13, 59)
	rockBody(liftRock, ec, 33, outline(ec, 4, 4, 7, erng), 7, erng, { Band = 2, Ring = false, Debris = 1, Seam = ACCENT })
	crystal(liftRock, CFrame.new(-12.4, 32.8, 59.5) * CFrame.Angles(0.15, 0, -0.2), 4.2, 1.1, AQUA)
	for _, sx in { -0.6, 0.6 } do
		blk(liftRock, CFrame.new(-13 + sx, 26.5, 59), Vector3.new(0.14, 13, 0.14), rgb(26, 26, 30), SMOOTH, GHOST)
	end
	glowSign(props, signAt * CFrame.new(0, 4.4, 0), "HEARTSTONE CORE", 12, 2.6, PINK, rgb(255, 236, 248))

	-- the hub: the Mine Lift under a floating hoist rock, a rune circle around a crystal
	MineKit.oreLift(m, O * v3(liftAt, hub.Top), "Floor5")
	local hoist = model("HoistRock", props)
	local hrng = Rng.new("Floor5Hoist")
	rockBody(hoist, liftAt, hub.Top + 33.5, outline(liftAt, 4.5, 4.5, 7, hrng), 8, hrng, { Band = 2, Ring = false, Debris = 1 })
	crystal(hoist, CFrame.new(v3(liftAt, hub.Top + 33.3)) * CFrame.Angles(0, 0, 0.2), 4, 1.1, PINK)
	for k = 1, 5 do
		local a = (k / 5) * math.pi * 2 + 0.3
		local p = runeAt + Vector2.new(math.cos(a), math.sin(a)) * 5.4
		local pos = v3(p, hub.Top)
		runeStone(props, CFrame.lookAt(pos, pos + (pos - v3(runeAt, hub.Top))), rng:range(3.2, 4.4), if k % 2 == 0 then AQUA else PINK, rng)
	end
	MineKit.crystals(props, O * CFrame.new(v3(runeAt, hub.Top)), 6, 6, "Glow", { PINK, AQUA, ACCENT }, "Floor5Rune")
	local runeLamp = blk(props, CFrame.new(v3(runeAt, hub.Top + 4)), Vector3.new(0.2, 0.2, 0.2), PINK, NEON, GLOW)
	runeLamp.Transparency = 1
	light(runeLamp, ACCENT, 22, 1.5)

	-- the Giant Crystal spot on the deep island, right in front of the Heartstone
	MineKit.marker(m, "GiantSpawn", O * CFrame.new(v3(giantAt, deep.Top)))

	-- crystal clusters and rune stones on free spots near the island corners
	-- (the landing also tries two spots beside the gate first)
	local lit: { [string]: number } = { Landing = 1, Hub = 0, West = 1, East = 1, Deep = 2 }
	local firstSpots: { [string]: { Vector2 } } = { Landing = { Vector2.new(9, 49), Vector2.new(-19, 48.5) } }
	for _, isl in islands do
		local drng = Rng.new("Floor5Decor" .. isl.Name)
		local spots: { Vector2 } = {}
		local first: { Vector2 } = firstSpots[isl.Name] or {}
		for _, q in first do
			table.insert(spots, q)
		end
		for _, v in isl.Poly do
			table.insert(spots, v + (isl.C - v).Unit * drng:range(4.6, 6))
		end
		local made = 0
		for i, p in spots do
			if made < (if isl.Deep then 4 else 2) and freeSpot(isl, p, 2) then
				made += 1
				local h = drng:range(3.5, 6.5)
				local colors = if made % 2 == 0 then { AQUA, PINK, ACCENT } else { PINK, ACCENT, AQUA }
				MineKit.crystals(props, O * CFrame.new(v3(p, isl.Top)) * CFrame.Angles(0, drng:range(0, 6), 0), drng:int(3, 5), h, "Glow", colors, "Floor5" .. isl.Name .. i)
				if (lit[isl.Name] or 0) > 0 then
					lit[isl.Name] -= 1
					local lamp = blk(props, CFrame.new(v3(p, isl.Top + h * 0.7)), Vector3.new(0.2, 0.2, 0.2), PINK, NEON, GLOW)
					lamp.Transparency = 1
					light(lamp, if made % 2 == 0 then AQUA else ACCENT, 22, 1.4)
				end
			elseif made >= 1 and drng:chance(0.5) and freeSpot(isl, p, 1.5) then
				local pos = v3(p, isl.Top)
				runeStone(props, CFrame.lookAt(pos, v3(isl.C, isl.Top)), drng:range(3, 4.2), if drng:chance(0.5) then AQUA else PINK, drng)
			end
		end
	end

	-- underside glows (light the faceted undersides from the void)
	for _, isl in { landing, hub, west, east, deep } do
		local front = exitPoint(isl.Poly, isl.C, isl.C + Vector2.new(0, 60))
		local lamp = blk(props, CFrame.new(v3(front + Vector2.new(0, if isl == landing then 1 else 5), isl.Top - isl.Depth * 0.45)), Vector3.new(0.2, 0.2, 0.2), PINK, NEON, GLOW)
		lamp.Transparency = 1
		light(lamp, if isl == hub or isl == east then AQUA else ACCENT, 26, 1.3)
		-- a soft violet wash over the top
		local wash = blk(props, CFrame.new(v3(isl.C, isl.Top + 14)), Vector3.new(0.2, 0.2, 0.2), PINK, NEON, GLOW)
		wash.Transparency = 1
		light(wash, rgb(214, 150, 255), 46, 1.25)
	end

	-- the Heartstone floating over the void behind the deep island
	local heartTip = Vector3.new(0, 6, -56)
	heartstone(m, heartTip, Rng.new("Floor5Heart"))

	-- far islets for depth
	local far = model("FarIslets", m)
	local farSpots = {
		Vector3.new(-69, -8, 44),
		Vector3.new(69, -11, 38),
		Vector3.new(-70, 10, -24),
		Vector3.new(70, 6, -30),
		Vector3.new(-62, 14, -56),
		Vector3.new(62, 18, -58),
	}
	for k, spot in farSpots do
		local frng = Rng.new("Floor5Far" .. k)
		local c = Vector2.new(spot.X, spot.Z)
		local r = frng:range(4, 6.5)
		rockBody(far, c, spot.Y, outline(c, r, r * frng:range(0.7, 1), 6, frng), r * 2.2, frng, { Band = 2, Ring = false, Debris = 1 })
		local h = frng:range(3, 5)
		crystal(far, CFrame.new(spot + Vector3.new(0, -0.2, 0)) * CFrame.Angles(frng:range(-0.2, 0.2), 0, frng:range(-0.2, 0.2)), h, h * 0.28, if k % 2 == 0 then AQUA else PINK)
		crystal(far, CFrame.new(spot + Vector3.new(1.5, -0.2, 1)) * CFrame.Angles(0.3, 0, -0.5), h * 0.6, h * 0.17, if k % 2 == 0 then PINK else AQUA)
	end

	-- star motes and drifting shards, kept out of islands, walkways, the heart and the front view
	local function blocked(p: Vector3): boolean
		if p.Z > 64 and p.Y > -10 then
			return true
		end
		for _, isl in islands do
			local xz = Vector2.new(p.X, p.Z)
			if p.Y > isl.Top - isl.Depth - 4 and p.Y < isl.Top + 16 then
				if inside(isl.Poly, xz) or edgeDist(isl.Poly, xz) < 4 then
					return true
				end
			end
		end
		for k, link in links do
			local pa, pb = anchor(k, true), anchor(k, false)
			local y = (link.A.Top + link.B.Top) / 2
			if segDist(Vector2.new(p.X, p.Z), pa, pb) < 9 and p.Y > y - 8 and p.Y < y + 14 then
				return true
			end
		end
		if (p - Vector3.new(0, 33, -56)).Magnitude < 34 then
			return true
		end
		for _, spot in farSpots do
			if (p - spot).Magnitude < 10 then
				return true
			end
		end
		if (p - v3(liftAt, 30)).Magnitude < 8 or (p - Vector3.new(-13, 30, 59)).Magnitude < 9 then
			return true
		end
		return false
	end
	voidDecor(m, Rng.new("Floor5Void"), blocked)

	-- a soft sparkle over the deep island and the landing
	local sparkA = blk(props, CFrame.new(v3(deep.C, deep.Top + 6)), Vector3.new(40, 0.2, 12), AQUA, SMOOTH, GLOW)
	sparkA.Transparency = 1
	Style.emitter(sparkA, "Sparkle", AQUA, 6)
	local sparkB = blk(props, CFrame.new(10, 5, 58), Vector3.new(16, 0.2, 8), PINK, SMOOTH, GLOW)
	sparkB.Transparency = 1
	Style.emitter(sparkB, "Sparkle", HEART_LIGHT, 4)

	return m
end

return Floor
