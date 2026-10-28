--[[
	CrackLogic: the pure math of the growing rock cracks (the owner's mining
	reel, 2026-10-27: "every hit cuts a bigger crack"; Effects/RockCracks
	draws them in the game, the Lune previews draw the same ones). No
	services, no Instances.

	A crack is planned once per rock in the plane of the face toward you:
	two zig-zag arms out of a centre point, a few branches off the arms and
	gold flecks on some corners. Every segment draws in over its own range
	of the rock's damage (growth 0..1, from its Health), so each hit cuts the
	crack a little longer and the branches split off later. The client puts
	every plan point onto the real rock surface (a raycast along the face
	normal) and lays thin parts between them; the main arm's segments also
	carry a thinner warm gold glint (JuiceConfig.GlintColor: one neutral
	colour, never the ore's) that flares on every hit and cools down.

	  plan(seed, size, detail)        -> Plan (points in the face plane, studs)
	  growth(health, maxHealth)       -> 0..1 (0 = untouched)
	  fraction(seg, growth)           -> how much of a segment is drawn (0..1)
	  basis(normal)                   -> the face's right and up directions
	  flatPoint(origin, right, up, p) -> a plan point in the world (before the surface)
	  segmentFrame(a, b, normal, lift)-> a thin part's CFrame between two points, its length
	  sizeFor(extents)                -> the crack's reach for a rock this big
	  boxFace(box, size, view)        -> the middle and normal of the bounding box side a
	                                     viewer at `view` looks at (the chips' face when
	                                     Cracks is switched off)
	  glint(since, reduced?)          -> the glint's transparency `since` seconds after its last
	                                     flare (Reduce motion: steady, it never flares)
	  counts(detail)                  -> dark segments, glint segments, flecks a plan uses (pool size)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))

local CrackLogic = {}

export type Seg = {
	I: number, -- the start point (Plan.Points index)
	J: number, -- the end point
	Width: number, -- studs across
	Main: boolean, -- on the main crack (carries the gold glint)
	From: number, -- growth where it starts to draw in
	To: number, -- growth where it is fully drawn
}

export type Plan = {
	Points: { Vector2 }, -- studs from the crack's centre in the face plane (X = right, Y = up)
	Segs: { Seg },
	Flecks: { number }, -- point indices that get a gold fleck
	FleckFrom: { number }, -- the growth each fleck shows from
	Size: number,
}

export type Detail = { Main: number, Branches: number, Flecks: number }

CrackLogic.Detail = { Main = 4, Branches = 4, Flecks = 3 } :: Detail
CrackLogic.PhoneDetail = { Main = 3, Branches = 2, Flecks = 2 } :: Detail
CrackLogic.GlintFrom = 0.3 -- growth where the gold glint starts to show (about the first crack stage)
CrackLogic.Heat = 0.45 -- seconds a glint flares after a hit
CrackLogic.Lift = 0.03 -- studs a crack sits out of the surface (no z-fighting)
CrackLogic.Thickness = 0.07
CrackLogic.GlintWidth = 0.36 -- a glint's width share of its dark segment
CrackLogic.FleckSize = 0.16

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function rotate(v: Vector2, angle: number): Vector2
	local c, s = math.cos(angle), math.sin(angle)
	return Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
end

-- How many parts a plan of `detail` uses: dark segments, glints (main segments), flecks.
function CrackLogic.counts(detail: Detail): (number, number, number)
	local main = detail.Main * 2
	return main + detail.Branches * 2, main, detail.Flecks
end

-- The crack's reach (studs from its centre) for a rock whose bounding box is `extents`.
function CrackLogic.sizeFor(extents: Vector3): number
	local a, b, c = extents.X, extents.Y, extents.Z
	local middle = math.max(math.min(a, b), math.min(math.max(a, b), c))
	return math.clamp(middle * 0.42, 0.8, 4.5)
end

--[[
	The crack of one rock: two zig-zag arms out of the centre (`detail.Main`
	segments each, the first arm grows first), `detail.Branches` two-segment
	branches off the arms (later in the growth) and `detail.Flecks` gold
	flecks on arm corners. `size` = the reach in studs (sizeFor). Seeded:
	the same seed draws the same crack (every client sees the same shape).
]]
function CrackLogic.plan(seed: number | string, size: number, detail: Detail?): Plan
	local d = detail or CrackLogic.Detail
	local rng = Rng.new(seed)
	local scale = math.clamp(size / 2, 0.7, 1.6)
	local main = math.max(1, d.Main)
	local points: { Vector2 } = { Vector2.zero }
	local segs: { Seg } = {}
	local arms: { { number } } = {}
	local base = rng:range(0.45, 1.15) -- the first arm's angle from the face's right
	for arm = 1, 2 do
		local angle = if arm == 1 then base else base + math.pi + rng:range(-0.35, 0.35)
		local start = if arm == 1 then 0 else 0.08
		local span = if arm == 1 then 0.8 else 0.74
		local at = Vector2.zero
		local last = 1
		local list = { 1 }
		local zig = if rng:chance(0.5) then 1 else -1
		for k = 1, main do
			local length = size / main * rng:range(0.8, 1.15)
			local dir = angle + zig * rng:range(0.3, 0.65)
			zig = -zig
			at += Vector2.new(math.cos(dir), math.sin(dir)) * length
			table.insert(points, at)
			local j = #points
			local taper = if main > 1 then (k - 1) / (main - 1) else 0
			table.insert(segs, {
				I = last,
				J = j,
				Width = lerp(0.28, 0.14, taper) * scale,
				Main = true,
				From = start + span * (k - 1) / main,
				To = start + span * k / main,
			})
			last = j
			table.insert(list, j)
		end
		arms[arm] = list
	end
	for b = 1, d.Branches do
		local arm = arms[(b - 1) % 2 + 1]
		-- a corner along the arm: never the centre, never the tip
		local k = if main >= 2 then 2 + ((b - 1) // 2) % (main - 1) else 2
		local from = arm[math.min(k, #arm)]
		local before = arm[math.max(1, math.min(k, #arm) - 1)]
		local heading = points[from] - points[before]
		if heading.Magnitude < 1e-3 then
			heading = Vector2.new(1, 0)
		end
		local side = if rng:chance(0.5) then 1 else -1
		local dir = rotate(heading.Unit, side * rng:range(0.6, 1.1))
		local at = points[from]
		local last = from
		local first = math.min(0.32 + 0.14 * (b - 1), 0.84)
		for s = 1, 2 do
			local length = size * rng:range(0.18, 0.26)
			dir = rotate(dir, -side * rng:range(0.15, 0.45) * (if s == 2 then -1 else 1))
			at += dir * length
			table.insert(points, at)
			local j = #points
			table.insert(segs, {
				I = last,
				J = j,
				Width = (if s == 1 then 0.12 else 0.08) * scale,
				Main = false,
				From = first + 0.14 * (s - 1),
				To = math.min(1, first + 0.14 * s),
			})
			last = j
		end
	end
	local flecks: { number } = {}
	local fleckFrom: { number } = {}
	for f = 1, d.Flecks do
		local arm = arms[(f - 1) % 2 + 1]
		local k = math.min(#arm, 2 + (f - 1) // 2)
		table.insert(flecks, arm[k])
		table.insert(fleckFrom, 0.42 + 0.12 * (f - 1))
	end
	return { Points = points, Segs = segs, Flecks = flecks, FleckFrom = fleckFrom, Size = size }
end

-- How far a rock's crack has grown (0..1) from its Health attributes; 0 while it is whole.
function CrackLogic.growth(health: number?, maxHealth: number?): number
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 or health ~= health then
		return 0
	end
	local lost = math.clamp(1 - health / maxHealth, 0, 1)
	if lost <= 0 then
		return 0
	end
	return math.clamp(0.14 + 0.96 * lost, 0, 1)
end

-- How much of a segment is drawn at `growth` (0..1).
function CrackLogic.fraction(seg: Seg, growth: number): number
	local span = math.max(seg.To - seg.From, 1e-3)
	return math.clamp((growth - seg.From) / span, 0, 1)
end

-- The face's right and up directions for a surface `normal` (unit, perpendicular to it and each other).
function CrackLogic.basis(normal: Vector3): (Vector3, Vector3)
	local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.new(0, 0, 1)
	local ref = if math.abs(n.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local right = ref:Cross(n).Unit
	local up = n:Cross(right).Unit
	return right, up
end

--[[
	The side of a bounding box (`box` CFrame, `size`) that a viewer at `view`
	looks at: its middle and outward normal (world). The side whose axis the
	view point sticks out along most, in half-sizes.
]]
function CrackLogic.boxFace(box: CFrame, size: Vector3, view: Vector3): (Vector3, Vector3)
	local rel = box:PointToObjectSpace(view)
	local half = size / 2
	local ax = math.abs(rel.X) / math.max(half.X, 1e-3)
	local ay = math.abs(rel.Y) / math.max(half.Y, 1e-3)
	local az = math.abs(rel.Z) / math.max(half.Z, 1e-3)
	local n: Vector3
	if ax >= ay and ax >= az then
		n = Vector3.new(if rel.X < 0 then -1 else 1, 0, 0)
	elseif ay >= az then
		n = Vector3.new(0, if rel.Y < 0 then -1 else 1, 0)
	else
		n = Vector3.new(0, 0, if rel.Z < 0 then -1 else 1)
	end
	local middle = box:PointToWorldSpace(Vector3.new(n.X * half.X, n.Y * half.Y, n.Z * half.Z))
	return middle, box:VectorToWorldSpace(n)
end

-- A plan point in the world, in the face plane at `origin` (before it is put onto the surface).
function CrackLogic.flatPoint(origin: Vector3, right: Vector3, up: Vector3, p: Vector2): Vector3
	return origin + right * p.X + up * p.Y
end

--[[
	A thin part's CFrame from `a` to `b` on a surface with `normal`, lifted by
	`lift`: its Z axis runs along the segment, its Y axis out of the surface
	(Size = Vector3.new(width, Thickness, length)). Also the length.
]]
function CrackLogic.segmentFrame(a: Vector3, b: Vector3, normal: Vector3, lift: number): (CFrame, number)
	local mid = (a + b) / 2 + normal * lift
	local delta = b - a
	local length = delta.Magnitude
	if length < 1e-3 then
		return CFrame.new(mid), 0
	end
	local look = delta / length
	local up = normal - look * normal:Dot(look)
	if up.Magnitude < 1e-3 then
		up = if math.abs(look.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	end
	return CFrame.lookAt(mid, mid + look, up.Unit), length
end

CrackLogic.Steady = 0.45 -- a glint's transparency when it doesn't flare

--[[
	A glint's transparency `since` seconds after its last flare: white-hot at
	the flare, then the steady glow. `reduced` (Reduce motion): always steady.
]]
function CrackLogic.glint(since: number, reduced: boolean?): number
	if reduced then
		return CrackLogic.Steady
	end
	local k = math.clamp(since / CrackLogic.Heat, 0, 1)
	return CrackLogic.Steady * k ^ 0.7
end

return CrackLogic
