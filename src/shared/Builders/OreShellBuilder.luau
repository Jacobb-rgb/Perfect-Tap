--[[
	Builds the close-up dirty clump for the spray-washing minigame from a
	pattern (CleaningPatterns): the default look of CleaningController (a
	look module may build its own from the same pattern). Client-only
	visuals, also used by the preview tools.

	Face space: (u, v) in the pattern's unit-disc coordinates, z toward the
	camera. World = WorkCF * (u * Scale, v * Scale, z).

	Layers (front to back):
	  dirt cells   one block per pattern cell, from z +0.11 out to about
	               DirtFront (thicker dirt sticks out more); crystals (Neon,
	               on a pale base) lean out to about z +0.31 so they read on
	               a phone
	  treasure     the real ore (ItemBuilder.display, the podium look) or the
	               dusty relic (ArtifactBuilder), turned three-quarters to the
	               camera and scaled to TreasureSize, its front just behind
	               the dirt: it shows as the dirt washes off
	  clump body   the outline shape in dark dirt, front at z = BodyFront,
	               plus lumps behind
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Geometry2D = require(script.Parent.Parent.Cleaning.Geometry2D)
local ItemBuilder = require(script.Parent.ItemBuilder)
local ArtifactBuilder = require(script.Parent.ArtifactBuilder)

local OreShellBuilder = {}

OreShellBuilder.Scale = 1.25
OreShellBuilder.CoreFront = 0.12
OreShellBuilder.DirtFront = 0.2 -- the spray plane (the front of an average dirt cell)
OreShellBuilder.DirtDepth = { Min = 0.05, Max = 0.16 } -- studs of dirt over the ore face, thin to thick cells
OreShellBuilder.CellOverlap = 1.18 -- dirt blocks are a little bigger than their cells (no gaps)
OreShellBuilder.BodyFront = -0.7 -- the clump's dark body behind the treasure
OreShellBuilder.TreasureSize = 1.85 -- studs across: the ore (or relic) under the dirt
OreShellBuilder.TreasureTurn = CFrame.Angles(-0.22, math.pi - 0.55, 0) -- three-quarters toward the camera
OreShellBuilder.CrystalBaseSize = 0.2 -- face units; the pale base under a crystal
OreShellBuilder.CrystalLean = 45 -- degrees out of the face, toward the camera
OreShellBuilder.DirtColors = { Color3.fromRGB(104, 78, 54), Color3.fromRGB(90, 68, 50), Color3.fromRGB(116, 88, 60) }

export type Shell = {
	Model: Model,
	WorkCF: CFrame,
	Scale: number,
	Treasure: Model, -- the ore (or relic) under the dirt
	Core: { BasePart }, -- the treasure's parts (they rise and spin in the reveal)
	TreasurePivot: CFrame, -- the treasure's middle, in the face's frame
	Dirt: { [number]: BasePart }, -- cell index -> its dirt block (attribute "FullSize": its size untouched)
	Fragile: { [number]: BasePart }, -- crystal index -> its glowing shard
	BackRock: { BasePart },
	Pattern: any,
}

local LOCAL = { Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = true }

local function props(extra: { [string]: any }?): { [string]: any }
	local p = table.clone(LOCAL)
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

function OreShellBuilder.toWorld(shell: Shell, u: number, v: number, z: number): Vector3
	return shell.WorkCF:PointToWorldSpace(Vector3.new(u * shell.Scale, v * shell.Scale, z))
end

-- Extrudes a convex face-space polygon between zBack and zFront.
local function prism(
	parent: Instance,
	workCF: CFrame,
	scale: number,
	poly: { Vector2 },
	zFront: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): { BasePart }
	local parts: { BasePart } = {}
	local normal = workCF.LookVector * -1 -- +Z in face space (toward the camera)
	for _, tri in Geometry2D.triangulateConvex(poly) do
		local a = workCF:PointToWorldSpace(Vector3.new(tri[1].X * scale, tri[1].Y * scale, zFront))
		local b = workCF:PointToWorldSpace(Vector3.new(tri[2].X * scale, tri[2].Y * scale, zFront))
		local c = workCF:PointToWorldSpace(Vector3.new(tri[3].X * scale, tri[3].Y * scale, zFront))
		for _, w in Geo.triangle(parent, a, b, c, depth, color, material, normal, props(extra)) do
			table.insert(parts, w :: BasePart)
		end
	end
	return parts
end

-- The visible parts' box in the face's frame (studs): min, max.
local function faceBox(model: Instance, workCF: CFrame): (Vector3, Vector3)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = workCF:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
						x0, y0, z0 = math.min(x0, p.X), math.min(y0, p.Y), math.min(z0, p.Z)
						x1, y1, z1 = math.max(x1, p.X), math.max(y1, p.Y), math.max(z1, p.Z)
					end
				end
			end
		end
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

local function forParts(model: Instance, fn: (BasePart) -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

--[[
	Fits the treasure behind the dirt: centred on the face, TreasureSize
	across (its box's corners inside the clump), its front just behind the
	dirt blocks.
]]
function OreShellBuilder.fitTreasure(model: Model, workCF: CFrame, pattern: any)
	local mn, mx = faceBox(model, workCF)
	local size = mx - mn
	local k = OreShellBuilder.TreasureSize / math.max(size.X, size.Y, 1e-3)
	local radius = math.huge
	for _, p in pattern.Outline do
		radius = math.min(radius, p.Magnitude)
	end
	local diagonal = math.sqrt(size.X * size.X + size.Y * size.Y)
	k = math.min(k, 2 * 0.95 * radius * OreShellBuilder.Scale / math.max(diagonal, 1e-3))
	local pivot = CFrame.new(workCF:PointToWorldSpace((mn + mx) / 2))
	forParts(model, function(part)
		local rel = pivot:ToObjectSpace(part.CFrame)
		part.Size *= k
		part.CFrame = pivot * CFrame.new(rel.Position * k) * (rel - rel.Position)
	end)
	mn, mx = faceBox(model, workCF)
	local shift = workCF:VectorToWorldSpace(Vector3.new(-(mn.X + mx.X) / 2, -(mn.Y + mx.Y) / 2, OreShellBuilder.CoreFront - 0.03 - mx.Z))
	forParts(model, function(part)
		part.CFrame = part.CFrame + shift
	end)
end

--[[
	workCF: CFrame at the ore center; its -LookVector points at the camera
	(build it with CFrame.lookAt(center, center - toCamera)).
]]
function OreShellBuilder.build(pattern: any, workCF: CFrame, parent: Instance?, relicId: string?): Shell
	local ore = OreData.get(pattern.OreId)
	local rng = Rng.new(pattern.Seed + 17)
	local scale = OreShellBuilder.Scale
	local model = Instance.new("Model")
	model.Name = "CleaningOre"

	-- clump body: the outline extruded backwards in dark dirt, plus lumps behind
	local bodyColor = ItemBuilder.DirtyCrustDark:Lerp(Color3.fromRGB(70, 52, 38), 0.4)
	local backRock = prism(
		model,
		workCF,
		scale,
		pattern.Outline,
		OreShellBuilder.BodyFront,
		1,
		bodyColor,
		Enum.Material.SmoothPlastic,
		{ Name = "RockBody" }
	)
	for _ = 1, 3 do
		local a = rng:range(0, math.pi * 2)
		local offset = Vector3.new(math.cos(a) * 0.55 * scale, math.sin(a) * 0.5 * scale, OreShellBuilder.BodyFront - 0.95)
		table.insert(
			backRock,
			Geo.block(
				model,
				workCF * CFrame.new(offset) * Geo.randomTilt(rng, 0.5),
				Vector3.new(1.1, 1, 0.9) * scale * rng:range(0.7, 0.95),
				Geo.vary(bodyColor, rng, 0.07),
				nil,
				props()
			)
		)
	end

	-- the treasure under the dirt: the real ore in its podium look, or the dusty relic
	local turn = workCF * OreShellBuilder.TreasureTurn
	local treasure: Model? = if relicId then ArtifactBuilder.build(relicId, turn, 1, true) else nil
	if not treasure then
		treasure = ItemBuilder.display({ K = "Clean", O = pattern.OreId }, turn, pattern.Seed)
	end
	local found = treasure :: Model
	found.Name = "Treasure"
	found.Parent = model
	OreShellBuilder.fitTreasure(found, workCF, pattern)
	local core: { BasePart } = {}
	forParts(found, function(part)
		part.CastShadow = false
		table.insert(core, part)
	end)
	local tmn, tmx = faceBox(found, workCF)
	local treasurePivot = workCF * CFrame.new(0, 0, (tmn.Z + tmx.Z) / 2)
	local glow = ItemBuilder.glowColor(ore.Glow)

	-- one dirt block per cell: thicker dirt sticks out more and is darker
	local most = 0
	for _, cell in pattern.Cells do
		most = math.max(most, cell.Amount)
	end
	local depth = OreShellBuilder.DirtDepth
	local dirt: { [number]: BasePart } = {}
	for _, cell in pattern.Cells do
		local thick = if most > 0 then cell.Amount / most else 1
		local studs = depth.Min + (depth.Max - depth.Min) * thick
		local size = pattern.CellSize * scale * OreShellBuilder.CellOverlap
		local color = rng:pick(OreShellBuilder.DirtColors):Lerp(Color3.fromRGB(58, 42, 30), 0.35 * thick)
		local block = Geo.block(
			model,
			workCF
				* CFrame.new(cell.Center.X * scale, cell.Center.Y * scale, OreShellBuilder.CoreFront + studs / 2 - 0.01)
				* CFrame.Angles(0, 0, rng:range(-0.15, 0.15)),
			Vector3.new(size * rng:range(1, 1.08), size * rng:range(1, 1.08), studs),
			color,
			nil,
			props({ Name = "Dirt", CastShadow = false })
		)
		block:SetAttribute("FullSize", block.Size)
		dirt[cell.Index] = block
	end

	-- glowing crystals leaning out toward the camera (so they read on a phone) on a small pale base
	local fragile: { [number]: BasePart } = {}
	for _, crystal in pattern.Crystals do
		local cf = workCF
			* CFrame.new(crystal.Center.X * scale, crystal.Center.Y * scale, OreShellBuilder.CoreFront + 0.02)
			* CFrame.Angles(0, 0, rng:range(-0.12, 0.12))
		local lean = cf * CFrame.Angles(0, 0, rng:range(-0.6, 0.6)) * CFrame.Angles(math.rad(OreShellBuilder.CrystalLean), 0, 0)
		-- (a darker Neon tone: the workbench bloom turns near-white Neon into a blob)
		local shard = Geo.block(
			model,
			lean * CFrame.new(0, 0.11, 0) * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(0.1, 0.24, 0.1) * scale,
			glow:Lerp(Color3.new(0, 0, 0), 0.2),
			Enum.Material.Neon,
			props({ Name = "Fragile", CastShadow = false })
		)
		fragile[crystal.Index] = shard
		local diameter = OreShellBuilder.CrystalBaseSize * scale
		local baseProps = props({ Name = "CrystalBase", CastShadow = false })
		baseProps.Shape = Enum.PartType.Cylinder
		-- a cylinder's axis is its X: turn it to face the camera
		baseProps.CFrame = cf * CFrame.new(0, 0, -0.025) * CFrame.Angles(0, math.pi / 2, 0)
		baseProps.Size = Vector3.new(0.03, diameter, diameter)
		baseProps.Color = Color3.fromRGB(236, 226, 200)
		baseProps.Material = Enum.Material.SmoothPlastic
		Geo.make("Part", baseProps, model)
	end

	model.PrimaryPart = backRock[1]
	if parent then
		model.Parent = parent
	end
	return {
		Model = model,
		WorkCF = workCF,
		Scale = scale,
		Treasure = found,
		Core = core,
		TreasurePivot = treasurePivot,
		Dirt = dirt,
		Fragile = fragile,
		BackRock = backRock,
		Pattern = pattern,
	}
end

-- Soft key light on the camera side so the ore face reads clearly in the close-up.
function OreShellBuilder.workLight(workCF: CFrame, parent: Instance): BasePart
	local holder = Geo.ball(
		parent,
		workCF:PointToWorldSpace(Vector3.new(0, 1.4, 3.2)),
		0.1,
		Color3.new(1, 1, 1),
		nil,
		props({ Name = "WorkLight", Transparency = 1, CastShadow = false })
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 238, 214)
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = holder
	return holder
end

return OreShellBuilder
