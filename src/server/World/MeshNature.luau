--!strict
--[[
	MeshNature: the owner's Meshy models (docs/plans/MESHY_MODELS_PLAN.md, package B) as the look of
	the lobby's trees, ponds and mossy cliffs.

	Every builder still builds its part look first (the same random draws, so the town's layout never
	moves) and then hands its model here. With the template uploaded (MeshKit) the parts make way
	for the owner's model in the old look's place; without it nothing happens and the old look
	stays, exactly as before. Meshes are looks only (no collision, raycasts or touches): where the
	old look was solid, an invisible primitive collider (attribute MeshCollider) keeps players out.

	  MeshNature.treeAsset(kind)                  the template of a tree kind ("Green", "Red", ...)
	  MeshNature.kindOf(color)                    the tree kind of a leaf colour (by its hue)
	  MeshNature.tree(m, kind, trunk, reach?)     the part tree `m` -> the owner's tree on the
	                                              trunk's foot (see below)
	  MeshNature.pond(m, center, sx, sz, opts?)   the part pond `m` -> the lily pond in its footprint
	                                              and a thin invisible "Water" part at its surface
	  MeshNature.cliffWall(parent, base, size)    mossy cliff pieces filling a box (front = LookVector)
	  MeshNature.cliff(m, base, size, solid?)     the part cliff `m` -> those pieces (+ a box collider)
	  MeshNature.swapInto(m, asset, frame, opts?) the part look `m` -> one mesh in its box (moss rocks)
	  MeshNature.treeBoxes(part)                  a mesh tree's trunk and crown as boxes (free-ground
	                                              indexes)
	  MeshNature.collider(parent, cf, size, name) an invisible anchored box that players bump into
	  MeshNature.dropColliders(root)              takes the colliders out of a model that a later
	                                              pass makes walk-through (meadow, sky islands)
	  MeshNature.clear(m)                         destroys every child of `m` (the old look)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local MeshKit = require(Shared.Builders.MeshKit)

local MeshNature = {}

MeshNature.Pond = "Prop_GardenPond"
MeshNature.Cliff = "Prop_MossyCliff"

-- The three trees the owner made (the same blobby tree in three crown colours); red and pink
-- crowns are the orange tree with a tint (SurfaceAppearance.Color multiplies its colour map:
-- orange leaves turn red, or coral for the pinks).
MeshNature.TreeAssets = {
	Green = "Prop_TreeGreen",
	Yellow = "Prop_TreeYellow",
	Orange = "Prop_TreeOrange",
	Red = "Prop_TreeOrange",
	Pink = "Prop_TreeOrange",
	Cherry = "Prop_TreeOrange",
} :: { [string]: string }
MeshNature.TreeTints = {
	Red = Color3.fromRGB(255, 120, 115),
	Pink = Color3.fromRGB(255, 170, 190),
	Cherry = Color3.fromRGB(255, 178, 200),
} :: { [string]: Color3 }

-- The mesh tree's trunk (measured in the processed file): about a fifth of the tree's width, the
-- crown starts near half its height.
MeshNature.TrunkWidth = 0.2
MeshNature.TrunkHeight = 0.5
-- The roots sink this much (of the tree's height) into the ground, so no root edge floats.
MeshNature.TreeSink = 0.01

-- The lily pond's open water (Prop_GardenPond, measured in the processed file), as fractions of
-- the mesh's box: its surface over the ground, its size and its centre's offset (X, Z).
MeshNature.PondWater = { Top = 0.075, Size = Vector2.new(0.5, 0.36), Offset = Vector2.new(-0.04, 0.07) }

---------------------------------------------------------------- shared helpers

-- Destroys every child of `m` (the old part look: parts, emitters, inner models).
function MeshNature.clear(m: Instance)
	for _, child in m:GetChildren() do
		child:Destroy()
	end
end

-- World box (min, max) of every part under `root`, rotation included; nil without parts.
function MeshNature.bounds(root: Instance): (Vector3?, Vector3?)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2
			local ey = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2
			local ez = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2
			local p = cf.Position
			x0, y0, z0 = math.min(x0, p.X - ex), math.min(y0, p.Y - ey), math.min(z0, p.Z - ez)
			x1, y1, z1 = math.max(x1, p.X + ex), math.max(y1, p.Y + ey), math.max(z1, p.Z + ez)
		end
	end
	if x0 > x1 then
		return nil, nil
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

-- A quarter turn picked from a position (no random draw: the builders' streams stay as they were).
local function turnAt(p: Vector3): CFrame
	local k = math.floor(p.X * 0.73 + p.Z * 1.37) % 4
	return CFrame.Angles(0, k * math.pi / 2, 0)
end

-- An invisible anchored box players bump into (the mesh is the look); attribute MeshCollider.
function MeshNature.collider(parent: Instance, cf: CFrame, size: Vector3, name: string?, canQuery: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name or "Collider"
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = canQuery == true
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("MeshCollider", true)
	p.Parent = parent
	return p
end

function MeshNature.isCollider(part: Instance): boolean
	return part:GetAttribute("MeshCollider") == true
end

-- The colliders under `root` go (a later pass makes the whole model walk-through anyway).
function MeshNature.dropColliders(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and MeshNature.isCollider(d) then
			d:Destroy()
		end
	end
end

-- Tints a mesh (its SurfaceAppearance's colour, where the template has one); the attribute Tint
-- keeps the colour for the previews.
local function tint(p: MeshPart, color: Color3)
	p:SetAttribute("Tint", color)
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		pcall(function()
			sa.Color = color
		end)
	end
end

---------------------------------------------------------------- trees

function MeshNature.treeAsset(kind: string): string
	return MeshNature.TreeAssets[kind] or MeshNature.TreeAssets.Green
end

-- The tree kind of a leaf colour, by its hue: green, yellow, orange, red or pink.
function MeshNature.kindOf(color: Color3): string
	local h, s = color:ToHSV()
	local deg = h * 360
	if s < 0.15 or (deg >= 70 and deg < 200) then
		return "Green"
	elseif deg >= 42 and deg < 70 then
		return "Yellow"
	elseif deg >= 18 and deg < 42 then
		return "Orange"
	elseif deg >= 200 and deg < 345 then
		return "Pink"
	end
	return "Red"
end

--[[
	The part tree in `m` (built by its builder) -> the owner's tree. It stands on the foot of
	`trunk` (a quarter turn picked from the spot), never taller than the old tree, its crown
	`reach` studs round the trunk (the room its placement planned) or, without `reach`, as wide
	as fits inside the old tree's box round the trunk. Where the old trunk collided an invisible box
	named "Trunk" stands in the mesh's trunk (never wider than the old one). The mesh ("Leaves")
	comes after it: the model's first non-colliding, shadow-casting part (Flora/Trees.crownPart
	hangs the petals on it). Returns the mesh, or nil (no template: `m` keeps its parts).
]]
function MeshNature.tree(m: Model, kind: string, trunk: BasePart, reach: number?): MeshPart?
	local asset = MeshNature.treeAsset(kind)
	local own = MeshKit.box(asset)
	if not MeshKit.has(asset) or not own then
		return nil
	end
	local lo, hi = MeshNature.bounds(m)
	if not lo or not hi then
		return nil
	end
	local foot = trunk.CFrame.Position - Vector3.new(0, trunk.Size.Y / 2, 0)
	local height = hi.Y - foot.Y
	local room = reach or math.min(foot.X - lo.X, hi.X - foot.X, foot.Z - lo.Z, hi.Z - foot.Z)
	local scale = math.min(height / own.Y, 2 * room / math.max(own.X, own.Z))
	local size = own * scale
	local cf = CFrame.new(foot.X, foot.Y + size.Y * (0.5 - MeshNature.TreeSink), foot.Z) * turnAt(foot)
	local mesh = MeshKit.part(asset, size, cf, { Name = "Leaves" })
	if not mesh then
		return nil
	end
	local color = MeshNature.TreeTints[kind]
	if color then
		tint(mesh, color)
	end
	local collides, canQuery = trunk.CanCollide, trunk.CanQuery
	local trunkWidth = math.min(trunk.Size.X, trunk.Size.Z)
	MeshNature.clear(m)
	if collides then
		local w = math.min(trunkWidth, size.X * MeshNature.TrunkWidth)
		local h = size.Y * MeshNature.TrunkHeight
		MeshNature.collider(m, CFrame.new(foot.X, foot.Y + h / 2, foot.Z), Vector3.new(w, h, w), "Trunk", canQuery)
	end
	mesh.Parent = m
	return mesh
end

export type Box = { Min: Vector3, Max: Vector3 }

--[[
	The space a mesh tree (MeshNature.tree's "Leaves") takes, as boxes for the free-ground indexes
	(Flora/Meadow): its trunk and the crown over it, so a fence, a lamp or a flower may stand under
	a crown's edge, like under the old crowns (the low root tips aside). nil for any other part.
]]
function MeshNature.treeBoxes(part: BasePart): { Box }?
	local asset = part:GetAttribute("Asset")
	if not part:IsA("MeshPart") or type(asset) ~= "string" or string.sub(asset, 1, 9) ~= "Prop_Tree" then
		return nil
	end
	local size = part.Size
	-- (quarter turns only: the boxes round the trunk stay the same)
	local w = math.max(size.X, size.Z)
	local p = part.CFrame.Position
	local ground = p.Y - size.Y / 2
	local function box(width: number, y0: number, y1: number): Box
		return {
			Min = Vector3.new(p.X - width / 2, ground + size.Y * y0, p.Z - width / 2),
			Max = Vector3.new(p.X + width / 2, ground + size.Y * y1, p.Z + width / 2),
		}
	end
	return {
		box(w * MeshNature.TrunkWidth, 0, MeshNature.TrunkHeight),
		box(w, MeshNature.TrunkHeight - 0.05, 1),
	}
end

---------------------------------------------------------------- ponds

export type PondOpts = {
	-- the long side as long as the footprint's (the short side then reaches a little past it:
	-- for ponds placed with free room round them); default: scaled evenly into the footprint
	Cover: boolean?,
	-- the side the low front rim faces (the reeds stand at the back); default: picked from the spot
	Front: Vector3?,
}

--[[
	The part pond in `m` (Style.pond and whatever its builder added: lily pads, koi, reeds) -> the
	owner's lily pond on the ground at `center`, its long side along the footprint's long side
	(sizeX x sizeZ), scaled evenly into the footprint. A thin invisible "Water" part marks the
	open water. Returns the mesh, or nil (no template: `m` keeps its parts).
]]
function MeshNature.pond(m: Model, center: Vector3, sizeX: number, sizeZ: number, opts: PondOpts?): MeshPart?
	local asset = MeshNature.Pond
	local own = MeshKit.box(asset)
	if not MeshKit.has(asset) or not own then
		return nil
	end
	local o: PondOpts = opts or {}
	local long, short = math.max(sizeX, sizeZ), math.min(sizeX, sizeZ)
	local scale = if o.Cover then long / own.X else math.min(long / own.X, short / own.Z)
	local size = own * scale
	-- the mesh's long side is its X: a quarter turn when the footprint runs along Z; then the
	-- half turn that faces its low front rim (its +Z side) toward `Front`
	local yaw = if sizeZ > sizeX then math.pi / 2 else 0
	local front = o.Front
	local flip = if front
		then Vector3.new(math.sin(yaw), 0, math.cos(yaw)):Dot(front) < 0
		else math.floor(center.X * 0.37 + center.Z * 0.61) % 2 == 1
	if flip then
		yaw += math.pi
	end
	local frame = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	local mesh = MeshKit.part(asset, size, frame * CFrame.new(0, size.Y * 0.49, 0), { Name = "PondMesh" })
	if not mesh then
		return nil
	end
	MeshNature.clear(m)
	mesh.Parent = m
	local w = MeshNature.PondWater
	local water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.CanTouch = false
	water.CastShadow = false
	water.Transparency = 1
	water.Size = Vector3.new(size.X * w.Size.X, 0.2, size.Z * w.Size.Y)
	water.CFrame = frame * CFrame.new(size.X * w.Offset.X, size.Y * w.Top - 0.1, size.Z * w.Offset.Y)
	water.Parent = m
	return mesh
end

---------------------------------------------------------------- mossy cliffs

-- The eight corners of a unit box (half sizes times these).
local CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, 1, 1),
}

--[[
	The part look in `m` -> one `asset` mesh, scaled evenly into the old parts' box as seen in
	`frame` (a yaw: the mesh turns with it), standing on the box's bottom. opts are MeshKit's
	(Name, CastShadow, ...). Returns the mesh, or nil (no template: `m` keeps its parts).
]]
function MeshNature.swapInto(m: Model, asset: string, frame: CFrame, opts: MeshKit.Opts?): MeshPart?
	local own = MeshKit.box(asset)
	if not MeshKit.has(asset) or not own then
		return nil
	end
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d.Size / 2
			for _, c in CORNERS do
				local q = frame:PointToObjectSpace(d.CFrame:PointToWorldSpace(h * c))
				x0, y0, z0 = math.min(x0, q.X), math.min(y0, q.Y), math.min(z0, q.Z)
				x1, y1, z1 = math.max(x1, q.X), math.max(y1, q.Y), math.max(z1, q.Z)
			end
		end
	end
	if x0 > x1 then
		return nil
	end
	local box = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	local size = own * math.min(box.X / own.X, box.Y / own.Y, box.Z / own.Z)
	local mesh = MeshKit.part(asset, size, frame * CFrame.new((x0 + x1) / 2, y0 + size.Y / 2, (z0 + z1) / 2), opts)
	if mesh then
		MeshNature.clear(m)
		mesh.Parent = m
	end
	return mesh
end

--[[
	Mossy cliff pieces (Prop_MossyCliff) filling a box: `base` = the box's bottom centre, its
	LookVector = the front (the side with the vines and the mossy ledges), size = (width, height,
	depth). The pieces are scaled evenly to the box's depth (never taller or wider than the box),
	stand side by side along the width (overlapping a little to fill it) and stack in rows up to
	its top. opts.Sink: studs the bottom row sinks into the ground. Returns the pieces (none
	without the template).
]]
function MeshNature.cliffWall(parent: Instance, base: CFrame, size: Vector3, opts: { Sink: number? }?): { MeshPart }
	local out: { MeshPart } = {}
	local asset = MeshNature.Cliff
	local own = MeshKit.box(asset)
	if not MeshKit.has(asset) or not own then
		return out
	end
	local sink = if opts and opts.Sink then opts.Sink else 0
	local tall = size.Y + sink
	local scale = math.min(size.Z / own.Z, tall / own.Y, size.X / own.X)
	local piece = own * scale
	local columns = math.max(1, math.ceil(size.X / piece.X - 0.05))
	local rows = math.max(1, math.ceil(tall / piece.Y - 0.05))
	-- the rows and columns share the box evenly (overlapping where they must)
	local rowStep = if rows > 1 then (tall - piece.Y) / (rows - 1) else 0
	local colStep = if columns > 1 then (size.X - piece.X) / (columns - 1) else 0
	-- (the mesh's front with the vines is its +Z side; the box's front is its LookVector, -Z)
	local front = base * CFrame.Angles(0, math.pi, 0)
	for row = 0, rows - 1 do
		for col = 0, columns - 1 do
			local x = if columns > 1 then -size.X / 2 + piece.X / 2 + col * colStep else 0
			local y = -sink + piece.Y / 2 + row * rowStep
			-- neighbours step a hair apart, so overlapping faces never share a plane
			local k = (row + col) % 2
			local at = front * CFrame.new(x, y + k * 0.05, if k == 0 then 0.06 else -0.06)
			local p = MeshKit.part(asset, piece, at, { Name = "MossyCliff" })
			if p then
				p.Parent = parent
				table.insert(out, p)
			end
		end
	end
	return out
end

--[[
	The part cliff in `m` -> mossy cliff pieces filling its box (MeshNature.cliffWall: `base` =
	the box's bottom centre, front = LookVector, `size`) and, when `solid`, one invisible box
	collider of that size ("CliffCollider", raycasts hit it like the old stone). Returns whether
	it swapped (no template: `m` keeps its parts).
]]
function MeshNature.cliff(m: Model, base: CFrame, size: Vector3, solid: boolean?): boolean
	if not MeshKit.has(MeshNature.Cliff) then
		return false
	end
	MeshNature.clear(m)
	if solid then
		MeshNature.collider(m, base * CFrame.new(0, size.Y / 2, 0), size, "CliffCollider", true)
	end
	MeshNature.cliffWall(m, base, size)
	return true
end

return MeshNature
