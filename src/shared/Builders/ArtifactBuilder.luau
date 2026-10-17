--[[
	Artifacts of Kaldrum as small parts-built relics (step 7), from the look
	hints in ArtifactConfig (Shape family, Primary / Accent / Glow colors).
	Pure: only Instance creation, so the server (the base museum), the
	client (the relic that pops out of a rock) and the Lune tools build the
	same models.

	- build(id, cf, scale?, noLight?) -> Model "Artifact" (nil for an unknown
	  id). `noLight`: no PointLight even on a Mythic (the base museums: a
	  plot keeps its one light; the client's pop-out relic keeps it).
	  `cf` is the spot the relic stands on: the model's origin is the bottom
	  centre, its front faces cf.LookVector (-Z). At scale 1 a relic is about
	  Height studs tall and fits a Footprint x Footprint square.
	- Budgets (ArtifactConfig, mobile: 8 museums x 24 relics): at most
	  ArtifactConfig.MaxParts parts, all anchored, CanCollide / CanTouch /
	  CanQuery and CastShadow off; the glow is a Neon part; only the
	  ArtifactConfig.LightRarity (Mythic) relics carry one small PointLight.
	- Attributes on the model: ArtifactId, Rarity. PrimaryPart = the main
	  body, so a client can spin the relic around it.
	- Every Shape family in ArtifactConfig.Shapes has a builder here (the
	  tests check it); a new family needs one before a new artifact uses it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ArtifactConfig = require(Shared.Config.ArtifactConfig)

local ArtifactBuilder = {}

ArtifactBuilder.MaxParts = ArtifactConfig.MaxParts
ArtifactBuilder.Height = 1.9 -- studs at scale 1 (the tallest relics)
ArtifactBuilder.Footprint = 1.5 -- studs at scale 1

local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic

local rgb = Color3.fromRGB
local STAND = rgb(58, 46, 40) -- the little dark display stands
local PAGES = rgb(240, 228, 196)
local ROCK = rgb(64, 54, 60)
local WOOD = rgb(124, 82, 52)

type Artifact = ArtifactConfig.Artifact

type Ctx = {
	Model: Model,
	Base: CFrame,
	S: number,
	Art: Artifact,
	Count: number,
}

local function shade(color: Color3, k: number): Color3
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local function tint(color: Color3, k: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), k)
end

-- A part of the relic: anchored, no collisions, no shadow.
local function add(ctx: Ctx, shape: Enum.PartType?, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or PLASTIC
	part.Color = color
	part.Size = size * ctx.S
	part.CFrame = cf
	ctx.Count += 1
	part.Name = if ctx.Count == 1 then "Body" else "Part" .. ctx.Count
	part.Parent = ctx.Model
	return part
end

-- A spot in the relic's own frame (studs at scale 1), turned by rx, ry, rz.
local function at(ctx: Ctx, x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	local s = ctx.S
	return ctx.Base * CFrame.new(x * s, y * s, z * s) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

local function block(ctx: Ctx, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return add(ctx, nil, cf, size, color, material)
end

-- Upright cylinder (its axis along the relic's Y).
local function upright(
	ctx: Ctx,
	x: number,
	y: number,
	z: number,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return add(ctx, Enum.PartType.Cylinder, at(ctx, x, y, z, 0, 0, math.pi / 2), Vector3.new(height, diameter, diameter), color, material)
end

-- Cylinder facing the front (its axis along the relic's Z): coins, gears, lenses.
local function facing(
	ctx: Ctx,
	x: number,
	y: number,
	z: number,
	depth: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return add(ctx, Enum.PartType.Cylinder, at(ctx, x, y, z, 0, math.pi / 2, 0), Vector3.new(depth, diameter, diameter), color, material)
end

-- Cylinder lying along the relic's X (scrolls, whistles).
local function lying(
	ctx: Ctx,
	x: number,
	y: number,
	z: number,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return add(ctx, Enum.PartType.Cylinder, at(ctx, x, y, z), Vector3.new(length, diameter, diameter), color, material)
end

local function ball(ctx: Ctx, x: number, y: number, z: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return add(ctx, Enum.PartType.Ball, at(ctx, x, y, z), Vector3.new(diameter, diameter, diameter), color, material)
end

-- The glow color and material (Neon) of a relic, or its accent when it has no glow.
local function glow(ctx: Ctx): (Color3, Enum.Material)
	local g = ctx.Art.Glow
	if g then
		return g, NEON
	end
	return ctx.Art.Accent, PLASTIC
end

-- A small dark display stand under relics that stand on an edge.
local function stand(ctx: Ctx, width: number, depth: number)
	block(ctx, at(ctx, 0, 0.08, 0), Vector3.new(width, 0.16, depth), STAND)
end

local BUILDERS: { [string]: (Ctx) -> () } = {}

BUILDERS.Coin = function(ctx)
	local a = ctx.Art
	facing(ctx, 0, 0.84, 0, 0.18, 1.3, a.Primary, METAL)
	stand(ctx, 0.9, 0.5)
	facing(ctx, 0, 0.84, -0.03, 0.2, 0.92, tint(a.Primary, 0.18), METAL)
	-- the stamped flame: a diamond and a little tip
	block(ctx, at(ctx, 0, 0.78, -0.12, 0, 0, math.pi / 4), Vector3.new(0.3, 0.3, 0.06), a.Accent)
	ball(ctx, 0, 1.03, -0.12, 0.16, a.Accent)
end

BUILDERS.Seal = function(ctx)
	local a = ctx.Art
	upright(ctx, 0, 0.15, 0, 0.3, 1.1, a.Primary)
	upright(ctx, 0, 0.34, 0, 0.1, 1.18, a.Accent, METAL)
	upright(ctx, 0, 0.68, 0, 0.6, 0.34, a.Accent, METAL)
	ball(ctx, 0, 1.12, 0, 0.6, a.Primary)
	block(ctx, at(ctx, 0, 1.48, 0, 0, math.pi / 4, 0), Vector3.new(0.24, 0.24, 0.24), a.Accent, METAL)
end

BUILDERS.Gem = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	facing(ctx, 0, 1.05, 0, 0.16, 1.0, a.Accent, METAL)
	stand(ctx, 0.7, 0.5)
	block(ctx, at(ctx, 0, 0.42, 0), Vector3.new(0.12, 0.54, 0.12), a.Accent, METAL)
	block(ctx, at(ctx, 0, 1.05, -0.12, 0, 0, math.pi / 4), Vector3.new(0.6, 0.6, 0.26), a.Primary)
	block(ctx, at(ctx, 0, 1.05, -0.24, 0, 0, math.pi / 4), Vector3.new(0.26, 0.26, 0.06), g, gm)
end

BUILDERS.Rod = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	upright(ctx, 0, 0.72, 0, 1.2, 0.18, a.Accent, METAL)
	upright(ctx, 0, 0.06, 0, 0.12, 0.56, STAND)
	upright(ctx, 0, 1.3, 0, 0.12, 0.38, a.Primary, METAL)
	ball(ctx, 0, 1.56, 0, 0.56, a.Primary, METAL)
	ball(ctx, 0, 1.9, 0, if ctx.Art.Glow then 0.28 else 0.18, g, gm)
end

BUILDERS.Crown = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	upright(ctx, 0, 0.45, 0, 0.45, 1.2, a.Primary, METAL)
	-- the royal cushion it rests on
	block(ctx, at(ctx, 0, 0.11, 0), Vector3.new(1.42, 0.22, 1.42), a.Accent)
	upright(ctx, 0, 0.46, 0, 0.47, 1.0, shade(a.Primary, 0.35))
	for i = 0, 3 do
		local yaw = math.pi / 4 + i * math.pi / 2
		local x, z = 0.5 * math.sin(yaw), -0.5 * math.cos(yaw)
		block(ctx, at(ctx, x, 0.78, z, 0, -yaw, math.pi / 4), Vector3.new(0.3, 0.3, 0.1), a.Primary, METAL)
	end
	ball(ctx, 0, 0.48, -0.6, 0.26, g, gm)
end

BUILDERS.Spike = function(ctx)
	local a = ctx.Art
	block(ctx, at(ctx, 0, 0.85, 0), Vector3.new(0.22, 1.1, 0.22), a.Primary, METAL)
	block(ctx, at(ctx, 0, 0.09, 0), Vector3.new(1.0, 0.18, 0.9), WOOD)
	block(ctx, at(ctx, 0, 0.3, 0), Vector3.new(1.4, 0.26, 0.5), a.Accent, METAL)
	block(ctx, at(ctx, -0.1, 1.45, 0), Vector3.new(0.5, 0.16, 0.32), a.Primary, METAL)
	block(ctx, at(ctx, 0.45, 0.47, 0), Vector3.new(0.5, 0.1, 0.5), shade(a.Accent, 0.8), METAL)
end

BUILDERS.Whistle = function(ctx)
	local a = ctx.Art
	lying(ctx, 0.1, 0.75, 0, 0.8, 0.44, a.Primary, METAL)
	stand(ctx, 1.0, 0.55)
	block(ctx, at(ctx, 0, 0.35, 0), Vector3.new(0.15, 0.4, 0.15), STAND)
	block(ctx, at(ctx, -0.52, 0.7, 0), Vector3.new(0.5, 0.2, 0.3), a.Primary, METAL)
	block(ctx, at(ctx, -0.04, 0.96, 0), Vector3.new(0.18, 0.06, 0.32), shade(a.Primary, 0.3))
	facing(ctx, 0.62, 0.88, 0, 0.07, 0.3, a.Accent, METAL)
end

BUILDERS.Lantern = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	block(ctx, at(ctx, 0, 0.55, 0), Vector3.new(0.5, 0.75, 0.5), g, gm)
	block(ctx, at(ctx, 0, 0.07, 0), Vector3.new(0.8, 0.14, 0.8), a.Primary, METAL)
	block(ctx, at(ctx, 0, 1.0, 0), Vector3.new(0.8, 0.14, 0.8), a.Primary, METAL)
	block(ctx, at(ctx, 0, 1.18, 0, 0, math.pi / 4, 0), Vector3.new(0.48, 0.22, 0.48), a.Primary, METAL)
	-- the cage: two thin walls through the light read as bars on every face
	block(ctx, at(ctx, 0, 0.55, 0), Vector3.new(0.86, 0.75, 0.07), a.Primary, METAL)
	block(ctx, at(ctx, 0, 0.55, 0), Vector3.new(0.07, 0.75, 0.86), a.Primary, METAL)
	facing(ctx, 0, 1.44, 0, 0.06, 0.36, a.Accent, METAL)
end

BUILDERS.Tablet = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	local slab = at(ctx, 0, 0.88, 0, math.rad(-8), 0, 0)
	block(ctx, slab, Vector3.new(1.1, 1.4, 0.18), a.Primary)
	stand(ctx, 1.2, 0.6)
	local s = ctx.S
	for i, y in { 0.32, 0.02, -0.28 } do
		local width = if i == 2 then 0.62 else 0.82
		block(ctx, slab * CFrame.new(0, y * s, -0.1 * s), Vector3.new(width, 0.07, 0.04), g, gm)
	end
	block(ctx, slab * CFrame.new(0, 0.56 * s, -0.1 * s) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.18, 0.18, 0.05), g, gm)
end

BUILDERS.Crest = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	block(ctx, at(ctx, 0, 1.25, 0), Vector3.new(1.1, 0.8, 0.16), a.Primary)
	stand(ctx, 1.0, 0.6)
	block(ctx, at(ctx, 0, 0.86, 0, 0, 0, math.pi / 4), Vector3.new(0.78, 0.78, 0.16), a.Primary)
	block(ctx, at(ctx, 0, 1.0, -0.02), Vector3.new(0.22, 1.25, 0.18), a.Accent, METAL)
	block(ctx, at(ctx, 0, 1.66, 0), Vector3.new(1.22, 0.12, 0.2), a.Accent, METAL)
	ball(ctx, 0, 1.22, -0.12, 0.34, g, gm)
end

BUILDERS.Gear = function(ctx)
	local a = ctx.Art
	facing(ctx, 0, 1.0, 0, 0.22, 1.0, a.Primary, METAL)
	stand(ctx, 0.9, 0.55)
	block(ctx, at(ctx, 0, 0.3, 0), Vector3.new(0.15, 0.3, 0.15), STAND)
	for i = 0, 3 do
		block(ctx, at(ctx, 0, 1.0, 0, 0, 0, i * math.pi / 4), Vector3.new(1.32, 0.2, 0.2), a.Primary, METAL)
	end
	facing(ctx, 0, 1.0, -0.02, 0.28, 0.36, a.Accent, METAL)
end

BUILDERS.Vial = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	local body = upright(ctx, 0, 0.53, 0, 0.85, 0.62, a.Primary, GLASS)
	body.Transparency = 0.35
	upright(ctx, 0, 0.05, 0, 0.1, 0.7, a.Accent, METAL)
	upright(ctx, 0, 0.42, 0, 0.6, 0.5, g, gm)
	local neck = upright(ctx, 0, 1.1, 0, 0.3, 0.28, a.Primary, GLASS)
	neck.Transparency = 0.35
	upright(ctx, 0, 1.33, 0, 0.2, 0.32, a.Accent)
end

BUILDERS.Scroll = function(ctx)
	local a = ctx.Art
	lying(ctx, 0, 0.56, 0, 1.1, 0.46, a.Primary)
	stand(ctx, 1.2, 0.5)
	block(ctx, at(ctx, 0, 0.25, 0), Vector3.new(1.0, 0.18, 0.3), STAND)
	lying(ctx, 0, 0.56, 0, 1.4, 0.18, a.Accent, METAL)
	lying(ctx, 0, 0.56, 0, 0.13, 0.5, a.Accent)
	-- the unrolled end hanging over the front
	block(ctx, at(ctx, 0.12, 0.36, -0.25, math.rad(12), 0, 0), Vector3.new(0.8, 0.46, 0.04), tint(a.Primary, 0.12))
end

BUILDERS.Orb = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	ball(ctx, 0, 0.86, 0, 0.96, a.Primary)
	upright(ctx, 0, 0.075, 0, 0.15, 0.7, a.Accent, METAL)
	upright(ctx, 0, 0.27, 0, 0.26, 0.3, a.Accent, METAL)
	upright(ctx, 0, 0.86, 0, 0.1, 1.0, a.Accent, METAL)
	ball(ctx, 0, 0.88, -0.3, 0.46, g, gm)
	ball(ctx, 0, 0.88, -0.5, 0.2, shade(a.Primary, 0.4))
end

BUILDERS.Hammer = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	block(ctx, at(ctx, 0, 0.37, 0), Vector3.new(0.95, 0.42, 0.42), a.Primary, METAL)
	stand(ctx, 1.1, 0.6)
	for _, x in { -0.5, 0.5 } do
		block(ctx, at(ctx, x, 0.37, 0), Vector3.new(0.1, 0.48, 0.48), shade(a.Primary, 0.75), METAL)
	end
	block(ctx, at(ctx, 0, 1.15, 0), Vector3.new(0.17, 1.15, 0.17), a.Accent)
	block(ctx, at(ctx, 0, 1.52, 0), Vector3.new(0.21, 0.36, 0.21), shade(a.Accent, 0.6))
	block(ctx, at(ctx, 0, 0.37, -0.22), Vector3.new(0.5, 0.1, 0.04), g, gm)
end

BUILDERS.Book = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	local book = at(ctx, 0, 0.82, 0, math.rad(-10), 0, 0)
	local s = ctx.S
	block(ctx, book * CFrame.new(0, 0, -0.15 * s), Vector3.new(0.95, 1.25, 0.06), a.Primary)
	stand(ctx, 1.2, 0.6)
	block(ctx, book * CFrame.new(0, 0, 0.15 * s), Vector3.new(0.95, 1.25, 0.06), a.Primary)
	block(ctx, book * CFrame.new(0.03 * s, 0, 0), Vector3.new(0.88, 1.17, 0.26), PAGES)
	block(ctx, book * CFrame.new(-0.47 * s, 0, 0), Vector3.new(0.08, 1.25, 0.36), a.Accent, METAL)
	block(ctx, book * CFrame.new(0.04 * s, 0.1 * s, -0.19 * s) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.3, 0.3, 0.04), g, gm)
end

BUILDERS.Lens = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	facing(ctx, 0, 1.2, 0, 0.2, 1.15, a.Accent, METAL)
	upright(ctx, 0, 0.075, 0, 0.15, 0.7, a.Accent, METAL)
	block(ctx, at(ctx, 0, 0.4, 0), Vector3.new(0.14, 0.5, 0.14), a.Accent, METAL)
	local glass = facing(ctx, 0, 1.2, 0, 0.22, 0.92, a.Primary, GLASS)
	glass.Transparency = 0.25
	facing(ctx, 0, 1.2, 0, 0.24, 0.38, g, gm)
end

BUILDERS.Shard = function(ctx)
	local a = ctx.Art
	local g, gm = glow(ctx)
	local main = block(ctx, at(ctx, 0, 0.82, 0, 0, math.pi / 4, math.rad(6)), Vector3.new(0.42, 1.15, 0.42), a.Primary, GLASS)
	main.Transparency = 0.3
	block(ctx, at(ctx, 0, 0.15, 0, 0, math.rad(20), 0), Vector3.new(0.9, 0.3, 0.8), ROCK)
	local tip = block(
		ctx,
		at(ctx, -0.06, 1.42, 0, math.atan(1 / math.sqrt(2)), math.pi / 4, math.pi / 4),
		Vector3.new(0.3, 0.3, 0.3),
		a.Primary,
		GLASS
	)
	tip.Transparency = 0.3
	local side = block(ctx, at(ctx, 0.32, 0.55, 0.05, 0, 0, math.rad(-28)), Vector3.new(0.24, 0.7, 0.24), a.Primary, GLASS)
	side.Transparency = 0.3
	block(ctx, at(ctx, 0, 0.8, 0, 0, math.pi / 4, math.rad(6)), Vector3.new(0.2, 0.9, 0.2), g, gm)
end

ArtifactBuilder.Builders = BUILDERS

-- Builds the relic `id` standing on `cf` (see the header). nil for an unknown id.
function ArtifactBuilder.build(id: string, cf: CFrame, scale: number?, noLight: boolean?): Model?
	local art = ArtifactConfig.ById[id]
	if not art then
		return nil
	end
	local builder = BUILDERS[art.Shape]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Artifact"
	model:SetAttribute("ArtifactId", id)
	model:SetAttribute("Rarity", art.Rarity)
	local ctx: Ctx = { Model = model, Base = cf, S = scale or 1, Art = art, Count = 0 }
	builder(ctx)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		model.PrimaryPart = body
	end
	-- only the rarest relics carry a light, on their glow part
	local glowColor = art.Glow
	if art.Rarity == ArtifactConfig.LightRarity and glowColor and not noLight then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child.Material == NEON then
				local light = Instance.new("PointLight")
				light.Color = glowColor
				light.Range = 6 * ctx.S
				light.Brightness = 1.2
				light.Shadows = false
				light.Parent = child
				break
			end
		end
	end
	return model
end

-- How many parts a relic has (tests, budgets). 0 for an unknown id.
function ArtifactBuilder.partCount(id: string): number
	local model = ArtifactBuilder.build(id, CFrame.new())
	if not model then
		return 0
	end
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	model:Destroy()
	return count
end

return ArtifactBuilder
