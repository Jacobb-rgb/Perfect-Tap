--[[
	GolemGait: the running animation of golem followers (owner 2026-10-21:
	"the golems should really RUN after the characters"). The maths is pure:
	the client (Controllers/WorldMotionController) and the showreel preview
	run the same code.

	- classify(model): the follower's limb groups, worked out once per model.
	  GolemBuilder names its core parts (Body, Leg1/2, Arm1/2, Fist1/2, Head);
	  name families are named too (Core, Vein, Boulder, Crystal*, Wing*,
	  Tail*, Aura, Crack*, Cape*: they stay on the body, a cape follows the
	  torso; Pauldron*: the arm on its side; the rounded twins *Fill /
	  *Edge1..4 go with their block). Everything else (the gear of every
	  accessory and limited edition, up to any part count) moves with what
	  it is WELDED to (it touches it, or shares a weld): gear firmly welded
	  to gear is one weld group that moves as one, and a weld group follows
	  the named part it is welded to (a sword in the fist swings with that
	  arm, blade, guard and pommel together; a helm with its horns turns
	  with the head), or the gear it hangs on (the orb on a sceptre). Where
	  that leaves a choice, and for gear welded to nothing, it goes by where
	  it is, in the golem's own units (feet at 0, -X = its left): at or
	  above the neck -> the head; out at the sides below the shoulders ->
	  that arm; low and off-centre -> that leg; the rest -> the body. Each
	  group swings around its pivot: the hips, the shoulders, the neck.
	- step(gait, now, speed, yaw): the gait clock: the step phase advances by
	  the cadence (steps get quicker and longer with speed, and quicker for
	  small golems), the smoothed speed, the turn rate, braking.
	- pose(...): the limb angles and the body's lift / lean / bank for this
	  frame: walk (legs and arms swing opposite, a hip waddle), run (bigger
	  swing, the body leans forward and bounces once per step, the head looks
	  into the turn), sprint (catching up: longer strides, more lean), braking
	  (a lean back with the arms forward), idle (breathing, looking around, a
	  wave now and then), the equip jump (arms up, legs tucked); Premium
	  golems that hover fly instead: arms swept back, legs trailing, a tilt
	  into turns and a gentle bob. Reduce motion halves the swing and drops
	  the sprint lean and the bank.
	- controllerHop(...): GolemController's own whole-body hop (lift, pitch,
	  roll) for the same follower, so the hook can swap it for the gait.
	- lod / fits: full limbs only within LimbRange of the camera, on screen,
	  while the per-frame part cap allows (phones less).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("GolemBuilder"))

local GolemGait = {}

local TAU = math.pi * 2

export type Group = {
	Parts: { BasePart },
	Rest: { CFrame }, -- each part in the Body's frame
	Welds: { [BasePart]: WeldConstraint }, -- the weld that holds each part to the Body
	Pivot: CFrame, -- the joint in the Body's frame (studs)
	PivotInv: CFrame,
}

export type Rig = {
	Body: BasePart,
	Scale: number, -- studs per golem unit (FollowerSize x the golem's Scale)
	LegL: Group,
	LegR: Group,
	ArmL: Group,
	ArmR: Group,
	Head: Group,
	Count: number, -- parts the limbs move
}

export type Gait = {
	Phase: number, -- radians: one stride (two steps) per 2 pi
	Speed: number, -- smoothed studs per second
	Accel: number, -- smoothed studs per second per second
	YawRate: number, -- smoothed radians per second
	LastNow: number,
	LastYaw: number,
	LastSpeed: number,
}

export type Pose = {
	LegL: number, -- hip pitch (radians, + = forward)
	LegR: number,
	LiftL: number, -- the swinging leg's lift (studs): the knee is implied
	LiftR: number,
	ArmL: number, -- shoulder pitch (+ = forward, up)
	ArmR: number,
	RollL: number, -- shoulder roll away from the body (radians)
	RollR: number,
	HeadPitch: number,
	HeadYaw: number,
	Lift: number, -- the body (studs)
	Pitch: number, -- (- = leaning forward)
	Roll: number,
}

-- Speeds (studs per second; a player walks 16)
GolemGait.Walk = 4 -- running starts here
GolemGait.Run = 12 -- full run from here
GolemGait.Sprint = 19 -- catching up from here
GolemGait.SprintFull = 28
GolemGait.Cadence = 3.0 -- strides per second at most for a golem of scale 1 (smaller: quicker)
GolemGait.LimbRange = 50 -- studs from the camera for the full limb animation
GolemGait.Cap = { PC = 160, Phone = 60 } -- limb parts moved per frame
GolemGait.WaveTime = 1.2 -- the idle wave
GolemGait.WaveEvery = { 6, 10 }

-- joints in golem units (feet at 0, front -Z, -X = the golem's left)
GolemGait.Hip = Vector3.new(0.3, 0.5, 0.02)
GolemGait.Shoulder = Vector3.new(0.78, 1.38, 0)
GolemGait.Neck = Vector3.new(0, GolemBuilder.HeadBottom, 0)

-- names that stay on the body whatever their height (prefixes; a cape and all its pieces follow the torso)
GolemGait.BodyNames = { "Body", "Core", "Vein", "Boulder", "Crystal", "Wing", "Tail", "Aura", "Crack", "Cape" }
-- names that go with the arm on their side (prefixes): shoulder armour sits on the arm's pivot and turns in
-- place there (never with the head)
GolemGait.ArmNames = { "Pauldron" }
GolemGait.Touch = 0.04 -- golem units: parts this close count as welded (touching)
GolemGait.Firm = 0.25 -- parts sharing this much of their volume are firmly welded
-- named parts of every golem that gear never hangs on (exact names): the shoulder boulder and crystal
-- reach into the head and the shoulders, the aura disc lies under the feet
GolemGait.Decor = { Boulder = true, Crystal = true, Aura = true } :: { [string]: boolean }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function frac(x: number): number
	return x - math.floor(x)
end

---------------------------------------------------------------- limb groups

-- The group a part's NAME decides: "LegL" | "LegR" | "ArmL" | "ArmR" | "Head" | "Body", or nil for gear
-- (it goes with its weld group). `p` is its spot in golem units (feet at 0): the side of a named limb.
function GolemGait.named(name: string, p: Vector3): string?
	-- (GolemBuilder.round's twins: "HeadFill", "HeadEdge1".. go with their block)
	local base = string.match(name, "^(%a+)Fill$") or string.match(name, "^(%a+)Edge%d+$")
	if base then
		local key = GolemGait.named(base, p)
		if key then
			return key
		end
	end
	local family = string.match(name, "^(%a+)") or name
	if family == "Leg" then
		return if p.X < 0 then "LegL" else "LegR"
	elseif family == "Arm" or family == "Fist" then
		return if p.X < 0 then "ArmL" else "ArmR"
	elseif family == "Head" then
		return "Head"
	end
	for _, prefix in GolemGait.BodyNames do
		if string.sub(name, 1, #prefix) == prefix then
			return "Body"
		end
	end
	for _, prefix in GolemGait.ArmNames do
		if string.sub(name, 1, #prefix) == prefix then
			return if p.X < 0 then "ArmL" else "ArmR"
		end
	end
	return nil
end

-- The group of gear welded to nothing named, by where it is (`p` in golem units, its weld group's centre).
function GolemGait.placed(p: Vector3): string
	if p.Y >= GolemGait.Neck.Y - 0.05 then
		return "Head"
	elseif math.abs(p.X) >= 0.62 and p.Y < GolemGait.Shoulder.Y + 0.1 then
		return if p.X < 0 then "ArmL" else "ArmR"
	elseif p.Y < GolemBuilder.LegHeight + 0.05 and math.abs(p.X) >= 0.08 then
		return if p.X < 0 then "LegL" else "LegR"
	end
	return "Body"
end

-- A part on its own: its name first, then its spot (helmets, crowns, horns, shields, boots, new gear).
function GolemGait.groupOf(name: string, p: Vector3): string
	return GolemGait.named(name, p) or GolemGait.placed(p)
end

local function newGroup(pivot: CFrame): Group
	return { Parts = {}, Rest = {}, Welds = {}, Pivot = pivot, PivotInv = pivot:Inverse() }
end

--[[
	Do two boxes overlap? `rel` = box B's frame in box A's, `a` / `b` their
	half sizes (the separating axis test: A's 3 axes, B's 3, their 9 cross
	products).
]]
local function boxTouch(rel: CFrame, a0: number, a1: number, a2: number, b0: number, b1: number, b2: number): boolean
	local tx, ty, tz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rel:GetComponents()
	local e = 1e-6 -- (parallel edges)
	local q00, q01, q02 = math.abs(r00) + e, math.abs(r01) + e, math.abs(r02) + e
	local q10, q11, q12 = math.abs(r10) + e, math.abs(r11) + e, math.abs(r12) + e
	local q20, q21, q22 = math.abs(r20) + e, math.abs(r21) + e, math.abs(r22) + e
	if math.abs(tx) > a0 + b0 * q00 + b1 * q01 + b2 * q02 then
		return false
	elseif math.abs(ty) > a1 + b0 * q10 + b1 * q11 + b2 * q12 then
		return false
	elseif math.abs(tz) > a2 + b0 * q20 + b1 * q21 + b2 * q22 then
		return false
	elseif math.abs(tx * r00 + ty * r10 + tz * r20) > b0 + a0 * q00 + a1 * q10 + a2 * q20 then
		return false
	elseif math.abs(tx * r01 + ty * r11 + tz * r21) > b1 + a0 * q01 + a1 * q11 + a2 * q21 then
		return false
	elseif math.abs(tx * r02 + ty * r12 + tz * r22) > b2 + a0 * q02 + a1 * q12 + a2 * q22 then
		return false
	elseif math.abs(tz * r10 - ty * r20) > a1 * q20 + a2 * q10 + b1 * q02 + b2 * q01 then
		return false
	elseif math.abs(tz * r11 - ty * r21) > a1 * q21 + a2 * q11 + b0 * q02 + b2 * q00 then
		return false
	elseif math.abs(tz * r12 - ty * r22) > a1 * q22 + a2 * q12 + b0 * q01 + b1 * q00 then
		return false
	elseif math.abs(tx * r20 - tz * r00) > a0 * q20 + a2 * q00 + b1 * q12 + b2 * q11 then
		return false
	elseif math.abs(tx * r21 - tz * r01) > a0 * q21 + a2 * q01 + b0 * q12 + b2 * q10 then
		return false
	elseif math.abs(tx * r22 - tz * r02) > a0 * q22 + a2 * q02 + b0 * q11 + b1 * q10 then
		return false
	elseif math.abs(ty * r00 - tx * r10) > a0 * q10 + a1 * q00 + b1 * q22 + b2 * q21 then
		return false
	elseif math.abs(ty * r01 - tx * r11) > a0 * q11 + a1 * q01 + b0 * q22 + b2 * q20 then
		return false
	elseif math.abs(ty * r02 - tx * r12) > a0 * q12 + a1 * q02 + b0 * q21 + b1 * q20 then
		return false
	end
	return true
end

function GolemGait.boxesTouch(rel: CFrame, a: Vector3, b: Vector3): boolean
	return boxTouch(rel, a.X, a.Y, a.Z, b.X, b.Y, b.Z)
end

-- one part of the model while it is sorted into groups (plain numbers: the pair tests run often)
type Piece = {
	Part: BasePart,
	Rest: CFrame, -- in the Body's frame
	HX: number, -- half its size plus half the touch margin
	HY: number,
	HZ: number,
	Radius: number?, -- a ball's (with the margin): tested as a ball, not its box
	MinX: number, -- its box in the Body's frame (axis aligned, with the margin)
	MinY: number,
	MinZ: number,
	MaxX: number,
	MaxY: number,
	MaxZ: number,
	Unit: Vector3, -- its centre in golem units (feet at 0)
	Volume: number, -- with the margin
	Named: boolean, -- its group comes from its name (else: gear, by its weld group)
	Anchor: boolean, -- named, and gear may hang on it (not GolemGait.Decor)
	Key: string?, -- its group
	Links: { number }, -- the pieces it touches or shares a weld with
	Shared: { number }, -- the volume it shares with each (a weld: WELDED)
}

local WELDED = math.huge -- a weld a builder made (or GolemBuilder.round's twin): always firm
local LIMBS = { "ArmL", "ArmR", "LegL", "LegR" }

-- (sample spots across a box, as fractions of its half size: 3 x 3 x 3)
local SAMPLE = { -2 / 3, 0, 2 / 3 }

local function boxesApart(a: Piece, b: Piece): boolean
	return a.MaxX < b.MinX or b.MaxX < a.MinX or a.MaxY < b.MinY or b.MaxY < a.MinY or a.MaxZ < b.MinZ or b.MaxZ < a.MinZ
end

-- Do A and B touch? (`rel` = B's frame in A's)
local function touching(a: Piece, b: Piece, rel: CFrame): boolean
	local ra, rb = a.Radius, b.Radius
	if not ra and not rb then
		return boxTouch(rel, a.HX, a.HY, a.HZ, b.HX, b.HY, b.HZ)
	end
	-- a ball: the nearest spot of the other part to its centre
	local box, centre = a, rel.Position -- (B's centre in A's frame)
	local radius = rb :: number
	if ra then
		box, centre, radius = b, rel:Inverse().Position, ra
	end
	local other = box.Radius
	if other then
		return centre.Magnitude <= radius + other
	end
	local dx = math.max(math.abs(centre.X) - box.HX, 0)
	local dy = math.max(math.abs(centre.Y) - box.HY, 0)
	local dz = math.max(math.abs(centre.Z) - box.HZ, 0)
	return dx * dx + dy * dy + dz * dz <= radius * radius
end

--[[
	About how much of A lies inside B (studs^3): `rel` = A's frame in B's;
	27 spots across A (within its ball, for a ball) are tested in B.
]]
local function sharedVolume(a: Piece, b: Piece, rel: CFrame): number
	local tx, ty, tz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rel:GetComponents()
	local hx, hy, hz = a.HX, a.HY, a.HZ
	local ra = a.Radius
	local rb = b.Radius
	local bx, by, bz = b.HX, b.HY, b.HZ
	local spots, inside = 0, 0
	for _, fx in SAMPLE do
		local x = fx * hx
		for _, fy in SAMPLE do
			local y = fy * hy
			for _, fz in SAMPLE do
				local z = fz * hz
				if not ra or x * x + y * y + z * z <= ra * ra then
					spots += 1
					local px = tx + r00 * x + r01 * y + r02 * z
					local py = ty + r10 * x + r11 * y + r12 * z
					local pz = tz + r20 * x + r21 * y + r22 * z
					if rb then
						if px * px + py * py + pz * pz <= rb * rb then
							inside += 1
						end
					elseif math.abs(px) <= bx and math.abs(py) <= by and math.abs(pz) <= bz then
						inside += 1
					end
				end
			end
		end
	end
	return if spots > 0 then inside / spots * a.Volume else 0
end

local function link(a: Piece, ia: number, b: Piece, ib: number, shared: number)
	table.insert(a.Links, ib)
	table.insert(a.Shared, shared)
	table.insert(b.Links, ia)
	table.insert(b.Shared, shared)
end

local function root(parents: { number }, i: number): number
	local r = i
	while parents[r] ~= r do
		r = parents[r]
	end
	while parents[i] ~= r do
		local up = parents[i]
		parents[i] = r
		i = up
	end
	return r
end

-- Is the volume `shared` by two pieces a firm weld? (Firm of the smaller one)
local function firm(shared: number, a: Piece, b: Piece): boolean
	return shared >= GolemGait.Firm * math.min(a.Volume, b.Volume)
end

-- The limb of `votes` (key -> volume) with the most, nil when it has none.
local function limbOf(votes: { [string]: number }): string?
	local best: string? = nil
	for _, key in LIMBS do
		local value = votes[key]
		if value and (best == nil or value > (votes[best] :: number)) then
			best = key
		end
	end
	return best
end

--[[
	The limb groups of a follower model (GolemBuilder.build, any opts): nil
	when it has no Body. The Body's frame is the golem's: its centre sits
	LegHeight + BodySize.Y / 2 units over the feet.

	Gear moves with what it is WELDED to (review anim/ship #8: a sword's
	blade left its hilt, cape flaps swung with the arms). Parts are welded
	when they touch (within Touch: an exact box test, balls as balls) or
	share a builder's weld; FIRMLY when they share at least Firm of the
	smaller one's volume. Gear firmly welded to other gear (rather than to
	a named part) makes one WELD GROUP that moves as one. A weld group goes
	  1. with the named parts it is firmly welded to (where it is when that
	     is one of them: a helm on the head, a guard and a pommel in the
	     fist; else a limb, else the head, else the body),
	  2. else with a limb it touches (a blade held up past the head, welded
	     to nothing but the fist and the arm: that arm),
	  3. else with the gear it shares the most with (the orb on a sceptre's
	     head on the sceptre held in the hand), when that holds firmer than
	     anything named it brushes,
	  4. else by where its centre is (GolemGait.placed): a halo floating
	     over the head, a crown of flames.
	Capes are named (BodyNames): they follow the torso.
]]
function GolemGait.classify(model: Model): Rig?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local s = body.Size.X / GolemBuilder.BodySize.X
	local bodyY = GolemBuilder.LegHeight + GolemBuilder.BodySize.Y / 2
	local function joint(v: Vector3): CFrame
		return CFrame.new(v.X * s, (v.Y - bodyY) * s, v.Z * s)
	end
	local h, sh, n = GolemGait.Hip, GolemGait.Shoulder, GolemGait.Neck
	local rig: Rig = {
		Body = body,
		Scale = s,
		LegL = newGroup(joint(Vector3.new(-h.X, h.Y, h.Z))),
		LegR = newGroup(joint(h)),
		ArmL = newGroup(joint(Vector3.new(-sh.X, sh.Y, sh.Z))),
		ArmR = newGroup(joint(sh)),
		Head = newGroup(joint(n)),
		Count = 0,
	}
	local cf = body.CFrame
	local pad = GolemGait.Touch * s / 2
	local margin = Vector3.one * pad
	local lift = Vector3.new(0, bodyY, 0)
	local pieces: { Piece } = {}
	local function add(part: BasePart, key: string?)
		local rest = cf:ToObjectSpace(part.CFrame)
		local half = part.Size / 2 + margin
		local radius: number? = nil
		local extent: Vector3
		if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
			local r = math.min(half.X, half.Y, half.Z)
			radius = r
			half = Vector3.one * r
			extent = half
		else
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rest:GetComponents()
			extent = Vector3.new(
				math.abs(r00) * half.X + math.abs(r01) * half.Y + math.abs(r02) * half.Z,
				math.abs(r10) * half.X + math.abs(r11) * half.Y + math.abs(r12) * half.Z,
				math.abs(r20) * half.X + math.abs(r21) * half.Y + math.abs(r22) * half.Z
			)
		end
		local unit = rest.Position / s + lift
		local named = key or GolemGait.named(part.Name, unit)
		local low, high = rest.Position - extent, rest.Position + extent
		table.insert(pieces, {
			Part = part,
			Rest = rest,
			HX = half.X,
			HY = half.Y,
			HZ = half.Z,
			Radius = radius,
			MinX = low.X,
			MinY = low.Y,
			MinZ = low.Z,
			MaxX = high.X,
			MaxY = high.Y,
			MaxZ = high.Z,
			Unit = unit,
			Volume = if radius then 4 / 3 * math.pi * radius ^ 3 else 8 * half.X * half.Y * half.Z,
			Named = named ~= nil,
			Anchor = named ~= nil and not GolemGait.Decor[part.Name],
			Key = named,
			Links = {},
			Shared = {},
		})
	end
	add(body, "Body")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			add(d, nil)
		end
	end
	local count = #pieces
	-- the welds: touching parts (gear with anything; two named parts never need it)
	for i = 1, count - 1 do
		local a = pieces[i]
		for j = i + 1, count do
			local b = pieces[j]
			if not (a.Named and b.Named) and not boxesApart(a, b) then
				local rel = a.Rest:ToObjectSpace(b.Rest) -- (B in A's frame)
				if touching(a, b, rel) then
					-- (the smaller one is sampled inside the bigger one)
					local shared = if a.Volume <= b.Volume then sharedVolume(a, b, rel:Inverse()) else sharedVolume(b, a, rel)
					link(a, i, b, j, shared)
				end
			end
		end
	end
	-- ... the welds a builder made between two parts (a follower's own all go to the Body: skipped)
	local function indexOf(part: Instance?): number?
		if part == nil or part == body then
			return nil
		end
		for k = 2, count do
			if pieces[k].Part == part then
				return k
			end
		end
		return nil
	end
	for i = 2, count do
		for _, child in pieces[i].Part:GetChildren() do
			if child:IsA("WeldConstraint") or child:IsA("JointInstance") then
				local i0 = indexOf((child :: any).Part0)
				local i1 = if i0 then indexOf((child :: any).Part1) else nil
				if i0 and i1 and i0 ~= i1 then
					link(pieces[i0], i0, pieces[i1], i1, WELDED)
				end
			end
		end
	end
	-- ... and GolemBuilder.round's twins of a gear block ("HelmFill", "HelmEdge1".. with the "Helm")
	local byName: { [string]: number } = {}
	for i = count, 2, -1 do
		byName[pieces[i].Part.Name] = i
	end
	for i = 2, count do
		local piece = pieces[i]
		if not piece.Named then
			local name = piece.Part.Name
			local base = string.match(name, "^(%a+)Fill$") or string.match(name, "^(%a+)Edge%d+$")
			local twin = if base then byName[base] else nil
			if twin and twin ~= i then
				link(piece, i, pieces[twin], twin, WELDED)
			end
		end
	end
	-- weld groups: gear firmly welded to gear, both ways (Firm of the bigger one too: a staff through
	-- a big cloud, a claw in a shell or a boot in a nebula stay apart)
	local parents: { number } = {}
	for i = 1, count do
		parents[i] = i
	end
	for i = 2, count do
		local a = pieces[i]
		if not a.Named then
			for k, j in a.Links do
				local b = pieces[j]
				local shared = a.Shared[k]
				if not b.Named and shared >= GolemGait.Firm * math.max(a.Volume, b.Volume) then
					parents[root(parents, i)] = root(parents, j)
				end
			end
		end
	end
	local groups: { [number]: { number } } = {}
	local order: { number } = {} -- (the groups in part order: the same result every time)
	for i = 2, count do
		if not pieces[i].Named then
			local r = root(parents, i)
			local list = groups[r]
			if not list then
				list = {}
				groups[r] = list
				table.insert(order, r)
			end
			table.insert(list, i)
		end
	end
	local function centreOf(list: { number }): Vector3
		local centre, volume = Vector3.zero, 0
		for _, m in list do
			centre += pieces[m].Unit * pieces[m].Volume
			volume += pieces[m].Volume
		end
		return if volume > 0 then centre / volume else pieces[list[1]].Unit
	end
	local function assign(list: { number }, key: string)
		for _, m in list do
			pieces[m].Key = key
		end
	end
	-- 1. firmly welded to named parts / 2. touching a limb
	local open: { number } = {}
	local firmly: { [string]: number } = {}
	local touched: { [string]: number } = {}
	for _, r in order do
		local list = groups[r]
		table.clear(firmly)
		table.clear(touched)
		local weldedTo: string? = nil -- (a builder's own weld to a named part decides)
		for _, m in list do
			local piece = pieces[m]
			for k, j in piece.Links do
				local other = pieces[j]
				local key = other.Key
				if other.Anchor and key then
					local shared = piece.Shared[k]
					if shared > 0 then
						touched[key] = math.max(touched[key] or 0, shared)
					end
					if firm(shared, piece, other) then
						firmly[key] = math.max(firmly[key] or 0, shared)
					end
					if shared == WELDED and not weldedTo then
						weldedTo = key
					end
				end
			end
		end
		local here = GolemGait.placed(centreOf(list))
		local key: string? = weldedTo
		if not key and next(firmly) ~= nil then
			key = if firmly[here] then here else limbOf(firmly) or (if firmly.Head then "Head" else "Body")
		end
		if not key then
			-- (a limb it reaches into, on one side only: a belt or a robe's hem between both legs isn't held)
			local limb = limbOf(touched)
			local left = touched.ArmL ~= nil or touched.LegL ~= nil
			local right = touched.ArmR ~= nil or touched.LegR ~= nil
			if limb and not (left and right) then
				key = limb
			end
		end
		if key then
			assign(list, key)
		else
			table.insert(open, r)
		end
	end
	--[[
		3. the gear it shares the most with, when that holds firmer than
		anything named it brushes: the firmest first, each time (a spike on
		an axe head waits for the head, which goes with the haft in the fist).
		How firmly two parts hold each other: the share of the bigger one (a
		backpack the big fishbowl helmet reaches into isn't the helmet's).
		`anyTouch`: a mere touch counts too (chains of gear touching nothing named).
	]]
	local function follow(anyTouch: boolean)
		while #open > 0 do
			local at, chosen, firmest = 0, nil :: string?, -1
			for o, r in open do
				local best: string? = nil
				local most, brush = -1, 0
				for _, m in groups[r] do
					local piece = pieces[m]
					for k, j in piece.Links do
						local other = pieces[j]
						local hold = piece.Shared[k] / math.max(piece.Volume, other.Volume)
						if other.Named then
							if other.Anchor then
								brush = math.max(brush, hold)
							end
						elseif other.Key and (hold > 0 or anyTouch) and hold > most then
							best, most = other.Key, hold
						end
					end
				end
				if best and most >= brush and most > firmest then
					at, chosen, firmest = o, best, most
				end
			end
			if not chosen then
				return
			end
			assign(groups[open[at]], chosen)
			table.remove(open, at)
		end
	end
	follow(false)
	-- 4. where it is: first the groups that touch a limb (a staff the fist only brushes), then those
	-- that touch something named, then the rest (after they follow any gear they touch); the gear on
	-- them follows each time
	local function touches(list: { number }, limbsOnly: boolean): boolean
		for _, m in list do
			for _, j in pieces[m].Links do
				local other = pieces[j]
				local key = other.Key
				if other.Anchor and key and (not limbsOnly or table.find(LIMBS, key) ~= nil) then
					return true
				end
			end
		end
		return false
	end
	for pass = 1, 3 do
		if pass == 3 then
			follow(true)
		end
		for o = #open, 1, -1 do
			local list = groups[open[o]]
			if pass == 3 or touches(list, pass == 1) then
				assign(list, GolemGait.placed(centreOf(list)))
				table.remove(open, o)
			end
		end
		follow(false)
	end
	for i = 2, count do
		local piece = pieces[i]
		local key = piece.Key
		if key and key ~= "Body" then
			local group = (rig :: any)[key] :: Group
			local d = piece.Part
			table.insert(group.Parts, d)
			table.insert(group.Rest, piece.Rest)
			local weld = d:FindFirstChildOfClass("WeldConstraint")
			if weld then
				group.Welds[d] = weld
			end
			rig.Count += 1
		end
	end
	return rig
end

---------------------------------------------------------------- the gait clock

function GolemGait.newGait(now: number, yaw: number): Gait
	return { Phase = 0, Speed = 0, Accel = 0, YawRate = 0, LastNow = now, LastYaw = yaw, LastSpeed = 0 }
end

-- Strides (two steps) per second at `speed` for a golem of `scale`: quicker with speed, quicker for small golems.
function GolemGait.cadence(speed: number, scale: number): number
	local s = math.max(0.3, scale)
	return GolemGait.Cadence / math.sqrt(s) * (1 - math.exp(-math.max(0, speed) / (5 * s)))
end

-- Studs per stride: longer with speed (the cadence levels off), shorter for small golems.
function GolemGait.stride(speed: number, scale: number): number
	local c = GolemGait.cadence(speed, scale)
	if c < 1e-4 then
		return 5 * math.max(0.3, scale) / (GolemGait.Cadence / math.sqrt(math.max(0.3, scale)))
	end
	return speed / c
end

-- (move, run, sprint) 0..1 for a speed.
function GolemGait.levels(speed: number): (number, number, number)
	return clamp01(speed / 1.5),
		clamp01((speed - GolemGait.Walk) / (GolemGait.Run - GolemGait.Walk)),
		clamp01((speed - GolemGait.Sprint) / (GolemGait.SprintFull - GolemGait.Sprint))
end

-- One frame of the gait clock (`speed` = GolemController's follower speed, `yaw` its facing).
function GolemGait.step(g: Gait, now: number, speed: number, yaw: number, scale: number)
	local dt = math.clamp(now - g.LastNow, 0, 0.1)
	g.LastNow = now
	if dt <= 0 then
		return
	end
	local k = 1 - math.exp(-dt * 10)
	local target = if speed == speed then math.clamp(speed, 0, 80) else 0
	g.Speed += (target - g.Speed) * k
	local accel = (g.Speed - g.LastSpeed) / dt
	g.LastSpeed = g.Speed
	g.Accel += (accel - g.Accel) * (1 - math.exp(-dt * 6))
	local turn = (yaw - g.LastYaw + math.pi) % TAU - math.pi
	g.LastYaw = yaw
	g.YawRate += (turn / dt - g.YawRate) * (1 - math.exp(-dt * 8))
	g.Phase = (g.Phase + TAU * GolemGait.cadence(g.Speed, scale) * dt) % (TAU * 64)
end

---------------------------------------------------------------- the pose

function GolemGait.newPose(): Pose
	return {
		LegL = 0,
		LegR = 0,
		LiftL = 0,
		LiftR = 0,
		ArmL = 0,
		ArmR = 0,
		RollL = 0,
		RollR = 0,
		HeadPitch = 0,
		HeadYaw = 0,
		Lift = 0,
		Pitch = 0,
		Roll = 0,
	}
end

-- The idle wave `w` seconds into it (0..WaveTime): 0..1, eased in and out.
local function waveEnvelope(w: number): number
	local k = w / GolemGait.WaveTime
	if k <= 0 or k >= 1 then
		return 0
	end
	return math.sin(math.pi * k) ^ 0.6
end

--[[
	Fills `pose` for this frame. `scale` = studs per golem unit, `floats` =
	a Premium golem (it flies), `celebrate` = seconds into the equip jump
	(nil = none, Golem.JumpTime long: see WorldMotionLogic), `jumpTime` its
	length.
]]
function GolemGait.pose(
	pose: Pose,
	g: Gait,
	now: number,
	scale: number,
	floats: boolean,
	seed: number,
	celebrate: number?,
	jumpTime: number,
	reduce: boolean
)
	local speed = g.Speed
	local move, run, sprint = GolemGait.levels(speed)
	local r = if reduce then 0.5 else 1
	local turn = math.clamp(g.YawRate * 0.12, -0.45, 0.45)
	if floats then
		-- flying: arms swept back, legs trailing, a tilt into the motion and the turns, a gentle bob
		local k = clamp01(speed / 8)
		local swayA = math.sin(now * 1.7 + seed)
		local back = if reduce then -0.8 else -1.25
		pose.ArmL = lerp(-0.12 + 0.08 * swayA, back, k)
		pose.ArmR = lerp(-0.12 - 0.08 * swayA, back, k)
		pose.RollL = lerp(0.2, 0.14, k)
		pose.RollR = pose.RollL
		local dangle = math.sin(now * 1.6 + seed) * 0.12
		local flutter = 0.07 * k * r
		pose.LegL = lerp(dangle, -0.55 * r, k) + flutter * math.sin(now * 5.2 + seed)
		pose.LegR = lerp(-dangle, -0.5 * r, k) + flutter * math.sin(now * 5.2 + seed + 2)
		pose.LiftL, pose.LiftR = 0, 0
		pose.Lift = scale * 0.06 * math.sin(now * 2.6 + seed)
		pose.Pitch = -0.32 * k * r
		-- (a left turn turns the yaw up: roll left into it)
		pose.Roll = if reduce then 0 else math.clamp(g.YawRate * 0.1, -0.35, 0.35) * k
		pose.HeadPitch = 0.2 * k * r
		pose.HeadYaw = turn * (1 - 0.5 * k) + 0.3 * math.sin(now * 0.45 + seed * 1.3) * (1 - k)
	else
		local swing = math.sin(g.Phase)
		local c = math.cos(g.Phase)
		local legAmp = (0.38 + 0.42 * run + 0.3 * sprint) * move * r
		local armAmp = legAmp * 1.2
		pose.LegL = legAmp * swing
		pose.LegR = -legAmp * swing
		-- the leg swinging forward lifts (a bent knee)
		local lift = scale * (0.05 + 0.08 * run) * move * r
		pose.LiftL = lift * math.max(0, c)
		pose.LiftR = lift * math.max(0, -c)
		-- arms pump opposite to the legs, held a little forward when running
		local hold = 0.25 * run * r
		pose.ArmL = hold - armAmp * swing
		pose.ArmR = hold + armAmp * swing
		pose.RollL = 0.06 + 0.1 * sprint * r
		pose.RollR = pose.RollL
		-- the body: highest with the legs together when walking, in the air between steps when running
		local bounce = scale * (0.05 + 0.13 * run + 0.08 * sprint) * move * r
		local a = math.abs(swing)
		pose.Lift = bounce * lerp(1 - a, a, run)
		local brake = clamp01(-g.Accel / 30) * run
		local lean = 0.04 * move + 0.18 * run + (if reduce then 0 else 0.16 * sprint)
		pose.Pitch = -lean * r + 0.2 * brake * r
		pose.Roll = (if reduce then 0 else math.clamp(g.YawRate * 0.05, -0.2, 0.2) * run) + math.sin(g.Phase) * 0.04 * move * (1 - run)
		pose.ArmL += 0.5 * brake
		pose.ArmR += 0.5 * brake
		pose.HeadPitch = lean * 0.5 * r + 0.04 * math.sin(2 * g.Phase) * run * r
		pose.HeadYaw = turn
		-- idle: breathing, looking around, now and then a wave with the right arm
		local idle = 1 - move
		if idle > 0 then
			local breath = math.sin(now * 1.9 + seed)
			pose.ArmL += 0.05 * breath * idle
			pose.ArmR -= 0.05 * breath * idle
			pose.Lift += scale * 0.015 * breath * idle
			pose.HeadYaw += 0.35 * math.sin(now * 0.45 + seed * 1.3) * idle
			local every = GolemGait.WaveEvery[1] + (GolemGait.WaveEvery[2] - GolemGait.WaveEvery[1]) * frac(seed * 0.618)
			local w = (now + seed * 2.3) % every
			local wave = waveEnvelope(w) * idle
			if wave > 0 then
				-- the arm goes out to the side and a little forward (clear of the big head) and waves;
				-- each golem waves with its own hand
				local roll = (1.9 + 0.4 * math.sin(w * 13)) * wave * r
				if frac(seed * 0.29) < 0.5 then
					pose.RollL += roll
					pose.ArmL += 0.7 * wave
				else
					pose.RollR += roll
					pose.ArmR += 0.7 * wave
				end
				pose.HeadYaw *= 1 - wave
			end
		end
	end
	-- the equip jump: arms up, legs tucked
	if celebrate and celebrate >= 0 and celebrate < jumpTime then
		local e = math.sin(math.pi * celebrate / jumpTime)
		pose.ArmL += (2.6 - pose.ArmL) * e
		pose.ArmR += (2.6 - pose.ArmR) * e
		if not floats then
			pose.LegL += (0.6 - pose.LegL) * e
			pose.LegR += (0.45 - pose.LegR) * e
		end
	end
end

---------------------------------------------------------------- GolemController's own hop

--[[
	The whole-body hop GolemController puts on a follower (its stepPets):
	(lift, pitch, roll). With the limbs running, the hook takes it back out
	and puts the gait's body pose in. Keep in step with GolemController.
]]
function GolemGait.controllerHop(phase: number, speed: number, walking: boolean, near: boolean, floats: boolean): (number, number, number)
	if not walking then
		return 0, 0, 0
	end
	local k = math.clamp(speed / 10, 0, 1)
	if floats then
		return 0, if near then -0.08 * k else 0, 0
	end
	return math.abs(math.sin(phase)) * 0.55 * k, if near then -0.12 * k else 0, if near then math.sin(phase) * 0.08 * k else 0
end

---------------------------------------------------------------- level of detail

-- Full limb animation for a golem `distance` studs from the camera?
function GolemGait.lod(distance: number, onScreen: boolean): boolean
	return onScreen and distance <= GolemGait.LimbRange
end

-- Do `need` more limb parts fit when `used` of this device's cap are taken?
function GolemGait.fits(used: number, need: number, phone: boolean): boolean
	return used + need <= (if phone then GolemGait.Cap.Phone else GolemGait.Cap.PC)
end

-- A group's frame this frame: the Body's frame turned around the joint (pitch, yaw, roll) and lifted.
function GolemGait.jointFrame(body: CFrame, group: Group, pitch: number, yaw: number, roll: number, lift: number): CFrame
	return body * CFrame.new(0, lift, 0) * group.Pivot * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) * group.PivotInv
end

return GolemGait
