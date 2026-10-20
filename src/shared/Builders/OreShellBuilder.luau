--[[
	Builds the close-up dirty clump for the spray-washing minigame from a
	pattern (CleaningPatterns): the default look of CleaningController (a
	look module may build its own from the same pattern). Client-only
	visuals, also used by the preview tools.

	Face space: (u, v) in the pattern's unit-disc coordinates, z toward the
	camera. World = WorkCF * (u * Scale, v * Scale, z).

	Layers (front to back):
	  dirt cells   one block per pattern cell, from the ore face out to about
	               DirtFront (thicker dirt sticks out more); crystals (Neon,
	               on a pale base) lean out to about z +0.31 so they read on
	               a phone
	  ore face     z +0.12 .. -1.0 in the ore's colour (it shows as the dirt
	               washes off), a thin rim that glows in the reveal
	  clump body   the outline shape in dark dirt, front at z = -0.25, plus
	               lumps behind
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Geometry2D = require(script.Parent.Parent.Cleaning.Geometry2D)
local ItemBuilder = require(script.Parent.ItemBuilder)

local OreShellBuilder = {}

OreShellBuilder.Scale = 1.25
OreShellBuilder.CoreFront = 0.12
OreShellBuilder.DirtFront = 0.2 -- the spray plane (the front of an average dirt cell)
OreShellBuilder.DirtDepth = { Min = 0.05, Max = 0.16 } -- studs of dirt over the ore face, thin to thick cells
OreShellBuilder.CellOverlap = 1.18 -- dirt blocks are a little bigger than their cells (no gaps)
OreShellBuilder.CrystalBaseSize = 0.2 -- face units; the pale base under a crystal
OreShellBuilder.CrystalLean = 45 -- degrees out of the face, toward the camera
OreShellBuilder.DirtColors = { Color3.fromRGB(104, 78, 54), Color3.fromRGB(90, 68, 50), Color3.fromRGB(116, 88, 60) }

export type Shell = {
	Model: Model,
	WorkCF: CFrame,
	Scale: number,
	Core: { BasePart },
	CoreRim: { BasePart },
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

--[[
	workCF: CFrame at the ore center; its -LookVector points at the camera
	(build it with CFrame.lookAt(center, center - toCamera)).
]]
function OreShellBuilder.build(pattern: any, workCF: CFrame, parent: Instance?): Shell
	local ore = OreData.get(pattern.OreId)
	local rng = Rng.new(pattern.Seed + 17)
	local scale = OreShellBuilder.Scale
	local model = Instance.new("Model")
	model.Name = "CleaningOre"

	-- clump body: the outline extruded backwards in dark dirt, plus lumps behind
	local bodyColor = ItemBuilder.DirtyCrustDark:Lerp(Color3.fromRGB(70, 52, 38), 0.4)
	local backRock =
		prism(model, workCF, scale, pattern.Outline, -0.25, 1.15, bodyColor, Enum.Material.SmoothPlastic, { Name = "RockBody" })
	for _ = 1, 3 do
		local a = rng:range(0, math.pi * 2)
		local offset = Vector3.new(math.cos(a) * 0.55 * scale, math.sin(a) * 0.5 * scale, -1.15)
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

	-- the ore face under the dirt (a little inside the outline) + a rim that glows in the reveal
	local face = {}
	for _, p in pattern.Outline do
		table.insert(face, p * 0.97)
	end
	local glow = ItemBuilder.glowColor(ore.Glow)
	local core =
		prism(model, workCF, scale, face, OreShellBuilder.CoreFront, 1.1, ore.Color, Enum.Material.SmoothPlastic, { Name = "Core" })
	local rim: { BasePart } = {}
	for i = 1, #face do
		local a2 = face[i]
		local b2 = face[i % #face + 1]
		local a = workCF:PointToWorldSpace(Vector3.new(a2.X * scale, a2.Y * scale, OreShellBuilder.CoreFront - 0.05))
		local b = workCF:PointToWorldSpace(Vector3.new(b2.X * scale, b2.Y * scale, OreShellBuilder.CoreFront - 0.05))
		local edge = Geo.block(
			model,
			CFrame.lookAt((a + b) / 2, b),
			Vector3.new(0.09, 0.09, (b - a).Magnitude),
			glow,
			Enum.Material.Neon,
			props({ Name = "CoreRim", CastShadow = false, Transparency = 1 })
		)
		table.insert(rim, edge)
	end

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
		Core = core,
		CoreRim = rim,
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
