--[[
	Backdrop kit: small builders the Backdrop pieces share (voxel stone
	columns, beams between points, lattice towers, ladders, railings,
	flanged pipes). Pure: Instance creation only, deterministic from rng.
	Colors come from Style.C (docs/ART_DIRECTION.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)

local C = Style.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local Kit = {}

export type Opts = { [string]: any }

-- A model for one LobbyLayout piece (named by its Id), plus the piece and its frame.
function Kit.piece(parent: Instance, id: string): (Model, LobbyLayout.Piece, CFrame)
	local piece = LobbyLayout.get(id)
	local m = Style.model(id, parent)
	m:SetAttribute("LobbyPiece", id)
	return m, piece, LobbyLayout.frame(piece)
end

-- A frame at `position` whose front (LookVector) is the horizontal `dir`.
function Kit.facing(position: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(position, position + Vector3.new(dir.X, 0, dir.Z))
end

-- Axis-aligned block from two world corners (any order).
function Kit.box(parent: Instance, a: Vector3, b: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	local min = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local max = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return Style.block(parent, CFrame.new((min + max) / 2), max - min, color, material, props)
end

-- Block in a frame from two local corners (any order).
function Kit.lbox(parent: Instance, frame: CFrame, a: Vector3, b: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	local min = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local max = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return Style.block(parent, frame * CFrame.new((min + max) / 2), max - min, color, material, props)
end

-- A square beam from a to b (thickness t). Vertical beams stay axis-aligned.
function Kit.beam(parent: Instance, a: Vector3, b: Vector3, t: number, color: Color3, material: Enum.Material?, props: Opts?): Part
	local d = b - a
	local length = d.Magnitude
	local mid = (a + b) / 2
	local dir = d / math.max(length, 1e-6)
	local cf: CFrame
	if math.abs(dir.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(math.pi / 2, 0, 0)
	else
		local right = Vector3.new(0, 1, 0):Cross(dir).Unit
		local up = dir:Cross(right)
		cf = CFrame.fromMatrix(mid, right, up, -dir)
	end
	return Style.block(parent, cf, Vector3.new(t, t, length), color, material, props or Style.tiny())
end

-- A rectangular slab from a to b (width across, `thick` along its up axis),
-- shifted by `offset` in its own frame (x = right, y = up). Chutes, jibs.
function Kit.slab(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?,
	offset: Vector3?
): Part
	local d = b - a
	local length = d.Magnitude
	local dir = d / math.max(length, 1e-6)
	local right = Vector3.new(0, 1, 0):Cross(dir)
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local up = dir:Cross(right)
	local cf = CFrame.fromMatrix((a + b) / 2, right, up, -dir) * CFrame.new(offset or Vector3.new(0, 0, 0))
	return Style.block(parent, cf, Vector3.new(width, thick, length), color, material, props or Style.tiny())
end

--[[
	Voxel stone column between world corners (x0, z0) and (x1, z1), from
	`bottom` to `top`. opts:
	  Color    stone shade (default StoneDark)
	  Cap      "Grass" (default: dirt band + grass slab), "Stone" (a stepped
	           light cap block), "None"
	  Tint     paints the cap in this colour instead of grass / light stone
	           (no dirt band); the random stream stays the same
	  AccentColors  the two shades of the accent stones (default Stone / StoneDeep)
	  Layers   builds the stone itself (parent, min, max) -> top block, e.g.
	           Spectrum strata; Color then only feeds the caps
	  Band     false: no dirt band under the grass
	  Front    Vector3 direction of the face that gets accent stones (or nil)
	  Accents  number of accent stones on that face (default 2)
	Returns the main block.
]]
function Kit.column(
	parent: Instance,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	bottom: number,
	top: number,
	rng: Rng.Rng,
	opts: Opts?
): Part
	local o: Opts = opts or {}
	local minX, maxX = math.min(x0, x1), math.max(x0, x1)
	local minZ, maxZ = math.min(z0, z1), math.max(z0, z1)
	local color = o.Color or C.StoneDark
	local tone = Style.vary(color, rng, 0.05)
	local layers: ((Instance, Vector3, Vector3) -> Part)? = o.Layers
	local main = if layers
		then layers(parent, Vector3.new(minX, bottom, minZ), Vector3.new(maxX, top, maxZ))
		else Kit.box(parent, Vector3.new(minX, bottom, minZ), Vector3.new(maxX, top, maxZ), tone, nil, Style.solid())
	local cap = o.Cap or "Grass"
	local tint: Color3? = o.Tint
	if cap == "Grass" then
		if o.Band ~= false then
			local dirt = Style.vary(C.DirtDark, rng, 0.04)
			if not tint then
				Kit.box(
					parent,
					Vector3.new(minX - 0.2, top - 1.6, minZ - 0.2),
					Vector3.new(maxX + 0.2, top - 0.1, maxZ + 0.2),
					dirt,
					nil,
					Style.tiny()
				)
			end
		end
		local grass = Style.vary(if rng:chance(0.3) then C.GrassLight else C.Grass, rng, 0.04)
		Kit.box(
			parent,
			Vector3.new(minX - 0.35, top - 0.1, minZ - 0.35),
			Vector3.new(maxX + 0.35, top + 0.8, maxZ + 0.35),
			tint or grass,
			nil,
			Style.solid()
		)
	elseif cap == "Stone" then
		local w, d = (maxX - minX), (maxZ - minZ)
		local cw, cd = math.floor(w * rng:range(0.55, 0.8)), math.floor(d * rng:range(0.55, 0.8))
		local h = math.floor(rng:range(2, 4))
		local cx = (minX + maxX) / 2 + rng:range(-(w - cw) / 2, (w - cw) / 2)
		local cz = (minZ + maxZ) / 2 + rng:range(-(d - cd) / 2, (d - cd) / 2)
		local stone = Style.vary(C.Stone, rng, 0.05)
		Kit.box(
			parent,
			Vector3.new(cx - cw / 2, top, cz - cd / 2),
			Vector3.new(cx + cw / 2, top + h, cz + cd / 2),
			tint or stone,
			nil,
			Style.solid()
		)
	end
	local front: Vector3? = o.Front
	if front then
		local n = o.Accents or 2
		local width = if math.abs(front.X) > 0.5 then maxZ - minZ else maxX - minX
		for _ = 1, n do
			local s = rng:range(1.6, 3.2)
			local y = rng:range(bottom + s, top - s - 1)
			if top - bottom > 2 * s + 2 then
				local along = rng:range(-width / 2 + s, width / 2 - s)
				local center: Vector3
				local size: Vector3
				if math.abs(front.X) > 0.5 then
					local x = if front.X > 0 then maxX + 0.3 else minX - 0.3
					center = Vector3.new(x, y, (minZ + maxZ) / 2 + along)
					size = Vector3.new(0.8, s, s * 1.3)
				else
					local z = if front.Z > 0 then maxZ + 0.3 else minZ - 0.3
					center = Vector3.new((minX + maxX) / 2 + along, y, z)
					size = Vector3.new(s * 1.3, s, 0.8)
				end
				local accents: { Color3 } = o.AccentColors or { C.Stone, C.StoneDeep }
				local shade = if rng:chance(0.5) then accents[1] else accents[2]
				Style.block(parent, CFrame.new(center), size, Style.vary(shade, rng, 0.05), nil, Style.tiny())
			end
		end
	end
	return main
end

--[[
	Split [a, b] into pieces of width minW..maxW, cutting at every value of
	`breaks` inside (a, b). Returns { {x0, x1}, ... } in order.
]]
function Kit.partition(a: number, b: number, breaks: { number }, minW: number, maxW: number, rng: Rng.Rng): { { number } }
	local cuts = { a }
	local sorted = table.clone(breaks)
	table.sort(sorted)
	for _, x in sorted do
		if x > a + 0.5 and x < b - 0.5 then
			table.insert(cuts, x)
		end
	end
	table.insert(cuts, b)
	local out: { { number } } = {}
	for i = 1, #cuts - 1 do
		local s, e = cuts[i], cuts[i + 1]
		local len = e - s
		local n = math.max(1, math.floor(len / ((minW + maxW) / 2) + 0.5))
		local weights: { number } = {}
		local total = 0
		for k = 1, n do
			local w = rng:range(minW, maxW)
			weights[k] = w
			total += w
		end
		local x = s
		for k = 1, n do
			local w = weights[k] / total * len
			local x1 = if k == n then e else math.floor((x + w) * 2 + 0.5) / 2
			table.insert(out, { x, x1 })
			x = x1
		end
	end
	return out
end

--[[
	Square lattice tower: 4 corner legs from `base` (bottom center, axis-
	aligned to its frame) up `height`, tapering to `topWidth`, with a ring
	of horizontal bars every `every` studs and one diagonal brace per face
	per level. Returns the top center CFrame.
]]
function Kit.lattice(
	parent: Instance,
	base: CFrame,
	width: number,
	topWidth: number,
	height: number,
	every: number,
	color: Color3,
	opts: Opts?
): CFrame
	local o: Opts = opts or {}
	local t = o.Thickness or 0.5
	local levels = math.max(1, math.floor(height / every + 0.5))
	local function corner(i: number, y: number): Vector3
		local w = width + (topWidth - width) * (y / height)
		local sx = if i == 1 or i == 4 then -1 else 1
		local sz = if i <= 2 then -1 else 1
		return base:PointToWorldSpace(Vector3.new(sx * w / 2, y, sz * w / 2))
	end
	for i = 1, 4 do
		Kit.beam(parent, corner(i, 0), corner(i, height), t * 1.2, color, nil, Style.decor())
	end
	local faces = o.Faces or { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 } }
	for level = 1, levels do
		local y0 = height * (level - 1) / levels
		local y1 = height * level / levels
		for f, face in faces do
			local a, b = face[1], face[2]
			Kit.beam(parent, corner(a, y1), corner(b, y1), t, color)
			if o.Cross then
				Kit.beam(parent, corner(a, y0), corner(b, y1), t * 0.8, color)
				Kit.beam(parent, corner(b, y0), corner(a, y1), t * 0.8, color)
			elseif o.Braces ~= false then
				if (level + f) % 2 == 0 then
					Kit.beam(parent, corner(a, y0), corner(b, y1), t * 0.8, color)
				else
					Kit.beam(parent, corner(b, y0), corner(a, y1), t * 0.8, color)
				end
			end
		end
	end
	return base * CFrame.new(0, height, 0)
end

-- Wooden ladder from `base` (bottom center, front = LookVector) up `height`.
function Kit.ladder(parent: Instance, base: CFrame, height: number, width: number?, rungEvery: number?)
	local w = width or 1.8
	for _, x in { -w / 2, w / 2 } do
		Style.block(parent, base * CFrame.new(x, height / 2, 0), Vector3.new(0.3, height, 0.3), C.WoodDark, nil, Style.tiny())
	end
	local every = rungEvery or 2
	local n = math.max(1, math.floor(height / every))
	for i = 1, n do
		Style.block(parent, base * CFrame.new(0, i * every - 0.6, 0), Vector3.new(w, 0.22, 0.22), C.Wood, nil, Style.tiny())
	end
end

-- Timber railing from a to b (points at deck level): posts and one top rail.
function Kit.railing(parent: Instance, a: Vector3, b: Vector3, height: number?, postEvery: number?)
	local h = height or 2.4
	local length = (b - a).Magnitude
	local n = math.max(1, math.ceil(length / (postEvery or 5)))
	for i = 0, n do
		local p = a + (b - a) * (i / n)
		Style.block(parent, CFrame.new(p + Vector3.new(0, h / 2, 0)), Vector3.new(0.45, h, 0.45), C.WoodDark, nil, Style.tiny())
	end
	Kit.beam(parent, a + Vector3.new(0, h - 0.2, 0), b + Vector3.new(0, h - 0.2, 0), 0.35, C.Wood)
end

--[[
	Octagonal pipe from a to b (two square prisms turned 45 degrees about
	the pipe axis), with flanges (wider octagon slabs + brass bolts) at the
	ends listed in `flanges` ("a", "b"). Kenney Factory Kit look.
]]
function Kit.pipe(parent: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3, flanges: { string }?)
	local d = b - a
	local length = d.Magnitude
	local dir = d / math.max(length, 1e-6)
	local ref = if math.abs(dir.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local right = ref:Cross(dir).Unit
	local up = dir:Cross(right)
	local frame = CFrame.fromMatrix((a + b) / 2, right, up, -dir)
	Style.block(parent, frame, Vector3.new(diameter, diameter, length), color, nil, Style.decor({ CastShadow = false }))
	Style.block(parent, frame * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(diameter, diameter, length), color, nil, Style.tiny())
	local ends: { string } = flanges or {}
	for _, which in ends do
		local z = if which == "a" then length / 2 - 0.25 else -length / 2 + 0.25
		local f = frame * CFrame.new(0, 0, z)
		local fw = diameter * 1.45
		Style.block(parent, f, Vector3.new(fw, fw, 0.5), C.IronLight, METAL, Style.tiny())
		Style.block(parent, f * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(fw, fw, 0.5), C.IronLight, METAL, Style.tiny())
		Style.block(parent, f * CFrame.new(0, fw * 0.42, 0), Vector3.new(0.35, 0.35, 0.65), C.Brass, nil, Style.tiny())
	end
end

-- A small neon bulb (warm dot) for strings of lights.
function Kit.bulb(parent: Instance, at: Vector3, size: number?, color: Color3?): Part
	local s = size or 0.6
	return Style.block(parent, CFrame.new(at), Vector3.new(s, s, s), color or C.Lamp, NEON, Style.tiny())
end

return Kit
