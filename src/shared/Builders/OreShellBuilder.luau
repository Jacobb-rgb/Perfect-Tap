--[[
	Builds the close-up ore for the cleaning minigame from a pattern
	(CleaningPatterns). Client-only visuals, also used by the preview tools.

	Face space: (u, v) in the pattern's unit-disc coordinates, z toward the
	camera. World = WorkCF * (u * Scale, v * Scale, z).

	Layers (front to back):
	  guide dots   z = +0.34 (on the crust)
	  crust caps   z +0.30 .. -0.25 (one Model per cut piece, welded)
	  dirt front at z = +0.17; fragile crystals (Neon, on a pale base) lean
	               out to about z +0.31 so they read on a phone
	  core         z +0.12 .. -1.0 (dull ore color until polished; its sides
	               show once the crust falls away)
	  rock body    the outline shape, front at z = -0.25, plus lumps behind
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Geometry2D = require(script.Parent.Parent.Cleaning.Geometry2D)
local ItemBuilder = require(script.Parent.ItemBuilder)

local OreShellBuilder = {}

OreShellBuilder.Scale = 1.25
OreShellBuilder.CapFront = 0.3
OreShellBuilder.CoreFront = 0.12
OreShellBuilder.DirtFront = 0.17
OreShellBuilder.DotZ = 0.34
OreShellBuilder.CrystalBaseSize = 0.2 -- face units; the pale base under a crystal (snap radius is 0.12)
OreShellBuilder.CrystalLean = 45 -- degrees out of the face, toward the camera

export type Shell = {
	Model: Model,
	WorkCF: CFrame,
	Scale: number,
	Caps: { [number]: { Model } }, -- cut index -> crust pieces it removes
	Core: { BasePart },
	CoreRim: { BasePart },
	Dirt: { [number]: BasePart },
	Fragile: { [number]: BasePart },
	Seams: { [number]: { BasePart } },
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
local function prism(parent: Instance, workCF: CFrame, scale: number, poly: { Vector2 }, zFront: number, depth: number, color: Color3, material: Enum.Material?, extra: { [string]: any }?): { BasePart }
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

local function weldAll(parts: { BasePart })
	local root = parts[1]
	for i = 2, #parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = parts[i]
		weld.Parent = root
	end
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

	-- rock body: the irregular outline extruded backwards, plus lumps behind
	-- the crust is the Dirty Ore crust (same for every ore): the ore only shows once it is cut free
	local crust = ItemBuilder.DirtyCrust
	local glow = ItemBuilder.glowColor(ore.Glow)
	local bodyColor = crust:Lerp(Color3.fromRGB(40, 32, 30), 0.25)
	local backRock = prism(model, workCF, scale, pattern.Outline, -0.25, 1.15, bodyColor, Enum.Material.SmoothPlastic, { Name = "RockBody" })
	for _ = 1, 3 do
		local a = rng:range(0, math.pi * 2)
		local offset = Vector3.new(math.cos(a) * 0.55 * scale, math.sin(a) * 0.5 * scale, -1.15)
		table.insert(backRock, Geo.block(model, workCF * CFrame.new(offset) * Geo.randomTilt(rng, 0.5), Vector3.new(1.1, 1, 0.9) * scale * rng:range(0.7, 0.95), Geo.vary(bodyColor, rng, 0.07), nil, props()))
	end

	-- core (dull until polished) + a thin rim that glows once exposed
	local dull = ore.Color:Lerp(Color3.fromRGB(70, 60, 55), 0.55)
	local core = prism(model, workCF, scale, pattern.Core, OreShellBuilder.CoreFront, 1.1, dull, Enum.Material.SmoothPlastic, { Name = "Core" })
	local rim: { BasePart } = {}
	for i = 1, #pattern.Core do
		local a2 = pattern.Core[i]
		local b2 = pattern.Core[i % #pattern.Core + 1]
		local a = workCF:PointToWorldSpace(Vector3.new(a2.X * scale, a2.Y * scale, OreShellBuilder.CoreFront - 0.05))
		local b = workCF:PointToWorldSpace(Vector3.new(b2.X * scale, b2.Y * scale, OreShellBuilder.CoreFront - 0.05))
		local edge = Geo.block(model, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.09, 0.09, (b - a).Magnitude), glow, Enum.Material.Neon, props({ Name = "CoreRim", CastShadow = false, Transparency = 1 }))
		table.insert(rim, edge)
	end

	-- crust caps, one welded model per piece
	local caps: { [number]: { Model } } = {}
	for _, cut in pattern.Cuts do
		caps[cut.Index] = {}
		for j, cap in cut.Caps do
			local capModel = Instance.new("Model")
			capModel.Name = `Cap_{cut.Index}_{j}`
			capModel.Parent = model
			-- crust reads as lighter, rough stone (clearly different from dirt and core)
			local color = Geo.vary(crust:Lerp(Color3.fromRGB(176, 160, 142), 0.45), rng, 0.05)
			local parts = prism(capModel, workCF, scale, cap, OreShellBuilder.CapFront, 0.55, color, Enum.Material.SmoothPlastic, { Name = "Crust" })
			-- a few pebbles on the crust for a rough look
			local centroid = Geometry2D.centroid(cap)
			if Geometry2D.area(cap) > 0.05 then
				local pebble = Geo.block(
					capModel,
					workCF * CFrame.new(centroid.X * scale, centroid.Y * scale, OreShellBuilder.CapFront + 0.05) * CFrame.Angles(0, 0, rng:range(0, 3)),
					Vector3.new(0.35, 0.3, 0.16) * rng:range(0.8, 1.3),
					Geo.vary(crust, rng, 0.1),
					nil,
					props({ CastShadow = false })
				)
				table.insert(parts, pebble)
				if cut.Index == 1 and j == 1 then
					-- the same tiny glint the Dirty Ore chunk shows; it falls away with the crust
					local glint = Geo.block(
						capModel,
						workCF * CFrame.new(centroid.X * scale + 0.18, centroid.Y * scale + 0.12, OreShellBuilder.CapFront + 0.04) * CFrame.Angles(0.6, 0.7, 0.3),
						Vector3.new(0.13, 0.13, 0.13),
						glow,
						Enum.Material.Neon,
						props({ Name = "Glint", CastShadow = false })
					)
					table.insert(parts, glint)
				end
			end
			weldAll(parts)
			capModel.PrimaryPart = parts[1]
			table.insert(caps[cut.Index], capModel)
		end
	end

	-- faint seams along every cut line, so you can see where pieces will break
	local seams: { [number]: { BasePart } } = {}
	for _, cut in pattern.Cuts do
		seams[cut.Index] = {}
		for i = 2, #cut.Line do
			local a = workCF:PointToWorldSpace(Vector3.new(cut.Line[i - 1].X * scale, cut.Line[i - 1].Y * scale, OreShellBuilder.CapFront + 0.005))
			local b = workCF:PointToWorldSpace(Vector3.new(cut.Line[i].X * scale, cut.Line[i].Y * scale, OreShellBuilder.CapFront + 0.005))
			local seam = Geo.block(model, CFrame.lookAt((a + b) / 2, b, workCF.LookVector * -1), Vector3.new(0.05, 0.02, (b - a).Magnitude), Color3.fromRGB(60, 46, 40), nil, props({ Name = "Seam", CastShadow = false }))
			table.insert(seams[cut.Index], seam)
		end
	end

	-- dirt patches and fragile crystals on the core face
	local dirtColors = { Color3.fromRGB(104, 78, 54), Color3.fromRGB(90, 68, 50), Color3.fromRGB(116, 88, 60) }
	local dirt: { [number]: BasePart } = {}
	local fragile: { [number]: BasePart } = {}
	for _, d in pattern.Dirt do
		local cf = workCF * CFrame.new(d.Center.X * scale, d.Center.Y * scale, OreShellBuilder.DirtFront - 0.04) * CFrame.Angles(0, 0, rng:range(-0.12, 0.12))
		if d.Fragile then
			-- A glowing crystal leaning out toward the camera (so it reads on a phone) on a small
			-- pale base: clearly not dirt, and smaller than the snap radius around it.
			local lean = cf * CFrame.Angles(0, 0, rng:range(-0.6, 0.6)) * CFrame.Angles(math.rad(OreShellBuilder.CrystalLean), 0, 0)
			-- (a darker Neon tone: the workbench bloom turns near-white Neon into a blob)
			local shard = Geo.block(model, lean * CFrame.new(0, 0.11, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.1, 0.24, 0.1) * scale, glow:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Neon, props({ Name = "Fragile", CastShadow = false }))
			fragile[d.Index] = shard
			local diameter = OreShellBuilder.CrystalBaseSize * scale
			local baseProps = props({ Name = "CrystalBase", CastShadow = false })
			baseProps.Shape = Enum.PartType.Cylinder
			-- a cylinder's axis is its X: turn it to face the camera
			baseProps.CFrame = cf * CFrame.new(0, 0, -0.025) * CFrame.Angles(0, math.pi / 2, 0)
			baseProps.Size = Vector3.new(0.03, diameter, diameter)
			baseProps.Color = Color3.fromRGB(236, 226, 200)
			baseProps.Material = Enum.Material.SmoothPlastic
			Geo.make("Part", baseProps, model)
		else
			local size = d.Size * scale * rng:range(1.05, 1.2)
			local patch = Geo.block(model, cf, Vector3.new(size, size * rng:range(0.9, 1.05), 0.1), rng:pick(dirtColors), nil, props({ Name = "Dirt", CastShadow = false }))
			dirt[d.Index] = patch
		end
	end

	model.PrimaryPart = backRock[1]
	if parent then
		model.Parent = parent
	end
	return {
		Model = model,
		WorkCF = workCF,
		Scale = scale,
		Caps = caps,
		Core = core,
		CoreRim = rim,
		Dirt = dirt,
		Fragile = fragile,
		Seams = seams,
		BackRock = backRock,
		Pattern = pattern,
	}
end

-- Guide dots along a cut's line (rebuilt for each active cut).
-- Soft key light on the camera side so the ore face reads clearly in the close-up.
function OreShellBuilder.workLight(workCF: CFrame, parent: Instance): BasePart
	local holder = Geo.ball(parent, workCF:PointToWorldSpace(Vector3.new(0, 1.4, 3.2)), 0.1, Color3.new(1, 1, 1), nil, props({ Name = "WorkLight", Transparency = 1, CastShadow = false }))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 238, 214)
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = holder
	return holder
end

function OreShellBuilder.guideDots(shell: Shell, cut: any, color: Color3, parent: Instance): { BasePart }
	local dots: { BasePart } = {}
	local spacing = 0.15 -- pattern units; gaps between dots read as a dashed guide
	local count = math.max(2, math.floor(cut.Length / spacing))
	for i = 0, count do
		local s = cut.Length * i / count
		local p = Geometry2D.pointAt(cut.Line, s)
		local world = OreShellBuilder.toWorld(shell, p.X, p.Y, OreShellBuilder.DotZ)
		local dot = Geo.ball(parent, world, 0.085, color, Enum.Material.Neon, props({ Name = "GuideDot", CastShadow = false }))
		dot:SetAttribute("S", s)
		table.insert(dots, dot)
	end
	-- start marker: a bigger ring-like dot at the first point
	return dots
end

-- The cut groove: thin dark line from the start of the cut to `progress` (0..1).
function OreShellBuilder.updateGroove(shell: Shell, cut: any, progress: number, direction: number, parts: { BasePart }, parent: Instance, glow: Color3): { BasePart }
	-- one groove part per polyline segment
	local length = cut.Length * math.clamp(progress, 0, 1)
	local line = cut.Line
	if direction < 0 then
		local reversed = {}
		for i = #line, 1, -1 do
			table.insert(reversed, line[i])
		end
		line = reversed
	end
	local walked = 0
	for i = 2, #line do
		local a2, b2 = line[i - 1], line[i]
		local segment = (b2 - a2).Magnitude
		local visible = math.clamp(length - walked, 0, segment)
		local part = parts[i - 1]
		if not part then
			part = Geo.block(parent, CFrame.new(), Vector3.new(0.1, 0.1, 0.1), glow, Enum.Material.Neon, props({ Name = "Groove", CastShadow = false }))
			parts[i - 1] = part
		end
		if visible <= 0.001 then
			part.Transparency = 1
		else
			local endPoint = a2 + (b2 - a2).Unit * visible
			local a = OreShellBuilder.toWorld(shell, a2.X, a2.Y, OreShellBuilder.CapFront + 0.02)
			local b = OreShellBuilder.toWorld(shell, endPoint.X, endPoint.Y, OreShellBuilder.CapFront + 0.02)
			part.Transparency = 0
			part.Size = Vector3.new(0.11, 0.06, math.max((b - a).Magnitude, 0.01))
			part.CFrame = CFrame.lookAt((a + b) / 2, b, shell.WorkCF.LookVector * -1)
		end
		walked += segment
	end
	return parts
end

return OreShellBuilder
