--[[
	Low-poly geometry helpers. Pure: only creates Instances (no services,
	no events), so the Lune tools can run it too.

	Style rules (stylized low-poly look, all original):
	- SmoothPlastic for most surfaces (flat, clean colors), Neon for glow.
	- Chunky, slightly rotated blocks; wedges for facets and roofs.
	- Decoration parts: CastShadow off for tiny bits, CanTouch/CanQuery off.
]]

local Rng = require(script.Parent.Parent.Util.Rng)

local Geo = {}

export type PartProps = { [string]: any }

local DEFAULTS = {
	Anchored = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	Material = Enum.Material.SmoothPlastic,
}

function Geo.make(className: string, props: PartProps?, parent: Instance?): any
	local instance = Instance.new(className)
	if className == "Part" or className == "WedgePart" or className == "CornerWedgePart" then
		for key, value in DEFAULTS do
			(instance :: any)[key] = value
		end
	end
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Decorative (non-interactive) part: no touch/query, optional no shadow.
function Geo.decor(props: PartProps): PartProps
	props.CanTouch = false
	props.CanQuery = false
	return props
end

function Geo.block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, extra: PartProps?): Part
	local props: PartProps = {
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return Geo.make("Part", props, parent)
end

function Geo.wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, extra: PartProps?): WedgePart
	local props: PartProps = {
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return Geo.make("WedgePart", props, parent)
end

-- Cylinder standing upright (Roblox cylinders run along X, so rotate).
function Geo.cylinder(parent: Instance, position: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, extra: PartProps?): Part
	local props: PartProps = {
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(height, diameter, diameter),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return Geo.make("Part", props, parent)
end

function Geo.ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?, extra: PartProps?): Part
	local props: PartProps = {
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(position),
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return Geo.make("Part", props, parent)
end

--[[
	A filled 3D triangle made from two WedgeParts (classic technique).
	The triangle face lies on the plane through a, b, c. `thickness` extrudes
	it *behind* the face, away from `normal` (if given).
]]
function Geo.triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	normal: Vector3?,
	extra: PartProps?
): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return {}
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local offset = Vector3.zero
	if normal then
		local sign = if right:Dot(normal) >= 0 then 1 else -1
		offset = -right * sign * thickness / 2
	end

	local w1 = Geo.wedge(
		parent,
		CFrame.fromMatrix((a + b) / 2 + offset, right, up, back),
		Vector3.new(thickness, math.max(height, 0.001), math.max(math.abs(ab:Dot(back)), 0.001)),
		color,
		material,
		extra
	)
	local w2 = Geo.wedge(
		parent,
		CFrame.fromMatrix((a + c) / 2 + offset, -right, up, -back),
		Vector3.new(thickness, math.max(height, 0.001), math.max(math.abs(ac:Dot(back)), 0.001)),
		color,
		material,
		extra
	)
	return { w1, w2 }
end

-- Vary a color slightly in brightness (keeps palettes lively but cohesive).
function Geo.vary(color: Color3, rng: Rng.Rng, amount: number?): Color3
	local h, s, v = color:ToHSV()
	local a = amount or 0.08
	return Color3.fromHSV(h, math.clamp(s + rng:range(-a, a) * 0.5, 0, 1), math.clamp(v + rng:range(-a, a), 0, 1))
end

function Geo.randomTilt(rng: Rng.Rng, maxTilt: number): CFrame
	return CFrame.Angles(rng:range(-maxTilt, maxTilt), rng:range(0, math.pi * 2), rng:range(-maxTilt, maxTilt))
end

--[[
	A chunky low-poly rock: 2-4 overlapping rotated blocks.
	`base` is the CFrame at the rock's bottom center, `size` its rough extents.
]]
function Geo.rock(
	parent: Instance,
	base: CFrame,
	size: Vector3,
	color: Color3,
	rng: Rng.Rng,
	material: Enum.Material?,
	extra: PartProps?
): { Part }
	local parts = {}
	local count = if size.Magnitude > 14 then 4 elseif size.Magnitude > 6 then 3 else 2
	for i = 1, count do
		local scale = if i == 1 then 1 else rng:range(0.45, 0.75)
		local s = Vector3.new(size.X * scale * rng:range(0.8, 1.05), size.Y * scale * rng:range(0.75, 1.0), size.Z * scale * rng:range(0.8, 1.05))
		local offset = if i == 1
			then Vector3.new(0, s.Y * 0.38, 0)
			else Vector3.new(rng:range(-0.35, 0.35) * size.X, s.Y * 0.3, rng:range(-0.35, 0.35) * size.Z)
		local cf = base * CFrame.new(offset) * Geo.randomTilt(rng, 0.28)
		local part = Geo.block(parent, cf, s, Geo.vary(color, rng, 0.06), material, extra)
		table.insert(parts, part)
	end
	return parts
end

return Geo
