--[[
	GolemFit: room for a golem, pure maths (GolemController and the specs
	use it).

	- radius(model, feet, below?): how far the golem reaches from the axis
	  through its feet (studs, whichever way it turns: wings, a staff,
	  floating rocks included); with `below`, only its parts that come
	  lower than that many studs over its feet (a huge golem's wings and
	  halo pass over a player's head: its Low reach, under PlayerHeight).
	- slots(sizes): where the followers walk, in owner space (+X right, +Z
	  behind; slot -> offset). Ordinary golems keep the Base slots (left,
	  right, back). A HUGE golem (GolemConfig Huge) walks beside and a
	  little further back (HugeBack), far enough out that it never overlaps
	  its player (PlayerRadius, by its Low reach) and Gap studs apart from
	  the others (an ordinary golem is no taller than a player: the Low
	  reach again; two huge golems: their whole reach, their wings meet
	  over the player's head), and out of the middle of Roblox's default
	  camera (CameraDistance behind the player, CameraPitch down): no part
	  of it comes nearer the line of sight than CameraClear (cameraX), so
	  the player and the path ahead stay in view; never in the back slot
	  straight behind the player: a huge golem equipped third swaps places
	  with a side golem that isn't huge (the right one first, the first
	  golem keeps its place), and with huge golems on both sides
	  it walks behind the left one. A golem in the back slot steps back to
	  clear the huge golems beside it, at most to BackMax (it stays out of
	  the camera's lap); the huge golems step out the rest of the way.
	- HugeFollowerSize: a HUGE golem follows at this size (its helm top
	  about 1.2 players tall; the reveal, the inventory and the pictures
	  show it whole), every other golem at GolemController.FollowerSize.
	- view(height, radius, aspect): the inventory's 3D portrait camera
	  (GolemController's ViewportFrame, FieldOfView ViewFov): the golem
	  turning on its feet at the origin fits the frame, a huge one with its
	  wings and floating rocks too.
]]

local GolemFit = {}

-- Radius: the whole reach, Low: the reach under PlayerHeight (nil: Radius)
export type Size = { Radius: number, Low: number?, Huge: boolean }

-- slots behind the owner (owner space: +X right, +Z behind): left, right, back
GolemFit.Base = { Vector3.new(-3.1, 0, 3.0), Vector3.new(3.1, 0, 3.0), Vector3.new(0, 0, 5.2) }
GolemFit.PlayerRadius = 1.6 -- studs: the player's own reach (an avatar, arms included)
GolemFit.PlayerHeight = 5.5 -- studs: a player (and an ordinary follower) is no taller
GolemFit.Gap = 0.5 -- studs between a huge golem and its player or another golem
GolemFit.HugeBack = 1.5 -- studs a huge golem walks further back than a side slot (the default camera still sees it)
GolemFit.HugeFollowerSize = 0.64 -- a HUGE follower's size: its helm top about 1.2 players tall (6.2 studs)
-- Roblox's default camera: CameraDistance behind the player's head, looking CameraPitch down; a
-- huge follower keeps out of its middle (CameraClear: the tangent of the clear corridor's half
-- angle, the middle third of a 16:9 screen)
GolemFit.CameraDistance = 12.5
GolemFit.CameraPitch = math.rad(15)
GolemFit.CameraClear = 0.42
GolemFit.BackMax = 7.0 -- studs: the back slot steps back at most this far (the default camera is 12.5 behind)
GolemFit.ViewFov = 30 -- the portrait camera's FieldOfView (degrees)
GolemFit.ViewYaw = 0.35 -- radians the portrait camera stands off the golem's front
GolemFit.ViewSpin = 0.7 -- radians the portrait golem turns either way
GolemFit.ViewMargin = 1.1 -- the portrait keeps this much room round a wide golem

-- a box's 8 corners (signs) and its 12 edges (corner pairs one sign apart)
local CORNERS: { Vector3 } = {}
local EDGES: { { number } } = {}
for i = 0, 7 do
	table.insert(CORNERS, Vector3.new(if i % 2 == 1 then 1 else -1, if i % 4 >= 2 then 1 else -1, if i >= 4 then 1 else -1))
end
for i = 0, 7 do
	for _, bit in { 1, 2, 4 } do
		if (i // bit) % 2 == 0 then
			table.insert(EDGES, { i + 1, i + bit + 1 })
		end
	end
end

local function flat(p: Vector3): number
	return math.sqrt(p.X * p.X + p.Z * p.Z)
end

--[[
	How far the golem reaches from the vertical axis through `feet`
	(studs): every part's farthest corner, so any turn stays inside. With
	`below`, only what comes lower than `below` studs over the feet (each
	part's box cut at that height: a wing rising from the shoulders counts
	up to there, its tip high over a player's head doesn't).
]]
function GolemFit.radius(model: Instance, feet: CFrame, below: number?): number
	local r = 0
	local corners: { Vector3 } = table.create(8)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = feet:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			for i, sign in CORNERS do
				local p = rel * (sign * h)
				corners[i] = p
				if below == nil or p.Y < below then
					r = math.max(r, flat(p))
				end
			end
			if below then
				for _, edge in EDGES do
					local a, b = corners[edge[1]], corners[edge[2]]
					if (a.Y < below) ~= (b.Y < below) then
						r = math.max(r, flat(a + (b - a) * ((below - a.Y) / (b.Y - a.Y))))
					end
				end
			end
		end
	end
	return r
end

-- The reach a golem keeps from its player and the ordinary golems.
local function low(size: Size): number
	return size.Low or size.Radius
end

--[[
	How far aside a golem reaching `r` (studs) must walk `z` studs behind
	its player so that, seen from the default camera, none of it comes
	nearer the line of sight than CameraClear: a point of its circle at
	angle t sits r * (k sin t + cos t) nearer, at most r * sqrt(1 + k^2).
]]
function GolemFit.cameraX(z: number, r: number): number
	local k = GolemFit.CameraClear
	local behind = GolemFit.CameraDistance * math.cos(GolemFit.CameraPitch) -- the camera over the ground
	return k * math.max(0, behind - z) + r * math.sqrt(1 + k * k)
end

-- The followers' offsets (see the header): sizes[slot] -> offsets[slot].
function GolemFit.slots(sizes: { [number]: Size }): { [number]: Vector3 }
	local base = GolemFit.Base
	-- slot -> place (1 left, 2 right, 3 back): a huge golem never takes the back place while a side has room
	local place = { 1, 2, 3 }
	local third = sizes[3]
	if third and third.Huge then
		for _, side in { 2, 1 } do
			local other = sizes[side]
			if not (other and other.Huge) then
				place[3], place[side] = side, 3
				break
			end
		end
	end
	local out: { [number]: Vector3 } = {}
	local huge: { number } = {} -- slots of the huge golems beside
	local back: number? = nil
	for slot = 1, 3 do
		local size = sizes[slot]
		if size then
			local p = place[slot]
			if p == 3 then
				back = slot
			elseif size.Huge then
				-- beside and further back, clear of its player and of the camera's middle
				local b = base[p]
				local z = b.Z + GolemFit.HugeBack
				local x = math.max(math.abs(b.X), GolemFit.PlayerRadius + GolemFit.Gap + low(size), GolemFit.cameraX(z, size.Radius))
				out[slot] = Vector3.new(if b.X < 0 then -x else x, 0, z)
				table.insert(huge, slot)
			else
				out[slot] = base[p]
			end
		end
	end
	-- huge golems on both sides keep their whole reach apart (their wings meet over the player's head)
	if #huge == 2 then
		local a, b = huge[1], huge[2]
		local short = sizes[a].Radius + sizes[b].Radius + GolemFit.Gap - math.abs(out[a].X - out[b].X)
		if short > 0 then
			for _, s in huge do
				local at = out[s]
				out[s] = Vector3.new(at.X + (if at.X < 0 then -short / 2 else short / 2), 0, at.Z)
			end
		end
	end
	local slot = back
	if not slot then
		return out
	end
	local size = sizes[slot] :: Size
	local left = sizes[1]
	if size.Huge and left then
		-- (a huge golem is left in the back place only with huge golems on both sides)
		-- behind the left one, never straight behind the player
		local at = out[1]
		local z = at.Z + left.Radius + size.Radius + GolemFit.Gap
		local x = math.max(math.abs(at.X), GolemFit.PlayerRadius + GolemFit.Gap + low(size), GolemFit.cameraX(z, size.Radius))
		out[slot] = Vector3.new(-x, 0, z)
		return out
	end
	-- the back slot steps back to clear the huge golems beside it (at most to BackMax) ...
	local z = base[3].Z
	for _, s in huge do
		local at, reach = out[s], low(sizes[s]) + size.Radius + GolemFit.Gap
		if reach > math.abs(at.X) then
			z = math.max(z, at.Z + math.sqrt(reach ^ 2 - at.X ^ 2))
		end
	end
	z = math.min(z, math.max(GolemFit.BackMax, base[3].Z))
	out[slot] = Vector3.new(0, 0, z)
	-- ... and they step out the rest of the way
	for _, s in huge do
		local at, reach = out[s], low(sizes[s]) + size.Radius + GolemFit.Gap
		local dz = z - at.Z
		if reach > math.abs(dz) then
			local x = math.max(math.abs(at.X), math.sqrt(reach ^ 2 - dz ^ 2))
			out[s] = Vector3.new(if at.X < 0 then -x else x, 0, at.Z)
		end
	end
	return out
end

--[[
	The portrait camera for a golem `height` studs tall reaching `radius`
	from its axis, its feet at the origin, in a frame `aspect` wide per
	unit of height: it looks at the golem's middle from in front (-Z),
	ViewYaw aside and a little above, as far as the golem's height needs
	(an ordinary golem's framing) or its reach needs, turning ViewSpin
	either way, whichever is further.
]]
function GolemFit.view(height: number, radius: number, aspect: number): CFrame
	local target = Vector3.new(0, height * 0.48, 0)
	local tanY = math.tan(math.rad(GolemFit.ViewFov) / 2)
	local tanX = tanY * math.max(aspect, 0.1)
	-- (a point `radius` from the axis looks widest, r / sqrt(d^2 - r^2), turned square to the
	-- camera's line: it must stay inside the frame's half width, with ViewMargin to spare)
	local distance = math.max(height * 2.6 + 1, radius * math.sqrt(1 + (GolemFit.ViewMargin / tanX) ^ 2))
	return CFrame.lookAt(
		target + Vector3.new(math.sin(GolemFit.ViewYaw) * distance, distance * 0.15, -math.cos(GolemFit.ViewYaw) * distance),
		target
	)
end

return GolemFit
