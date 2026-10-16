--[[
	Builds physical items (ore chunks, ingots, gear). Each item is a Model
	whose PrimaryPart "Body" is the only colliding part; decoration parts are
	welded, massless and non-colliding, so one item = one cheap physics body.

	Attributes are set by ItemService on the server, not here.
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local ItemBuilder = {}

export type ItemInfo = {
	Kind: string, -- Raw | Clean | Crushed | Ingot | Gear
	OreId: string,
	Grade: string?,
	Recipe: string?,
}

local DECOR = {
	CanCollide = false,
	CanTouch = false,
	CanQuery = true, -- so clicking any part of the item targets it
	Massless = true,
	Anchored = false,
	CastShadow = false,
}

local function decorProps(extra: { [string]: any }?): { [string]: any }
	local props = table.clone(DECOR)
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function weld(body: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = part
	w.Parent = body
end

local function addDecor(model: Model, body: BasePart, part: BasePart)
	part.Parent = model
	weld(body, part)
end

local function body(model: Model, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Geo.make("Part", {
		Name = "Body",
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		CastShadow = true,
	})
	if shape then
		part.Shape = shape
		part.Size = size
	end
	-- light, slightly bouncy so throwing feels good
	part.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.5, 0.25, 1, 1)
	part.Parent = model
	model.PrimaryPart = part
	return part
end

local function rawChunk(model: Model, cf: CFrame, info: ItemInfo, rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local rarity = Rarity.get(ore.Rarity)
	local s = 1 + (rarity.Order - 1) * 0.05
	local b = body(model, cf, Vector3.new(1.7, 1.35, 1.5) * s, Geo.vary(ore.Crust, rng, 0.05))
	-- a second crust lump for a less boxy silhouette
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(rng:range(-0.3, 0.3), 0.35 * s, rng:range(-0.25, 0.25)) * Geo.randomTilt(rng, 0.5),
		Size = Vector3.new(1.1, 0.9, 1.0) * s,
		Color = Geo.vary(ore.Crust, rng, 0.08),
		Material = Enum.Material.SmoothPlastic,
	})))
	-- ore crystals poking out of the crust (the readable part of a chunk).
	-- Kept to 6 parts per chunk: many chunks can lie around (mobile budget).
	local glowy = rarity.Order >= 3
	local crystals = {
		{ x = 0.45, y = 0.55, z = 0.1, tilt = -0.55, size = 1.05 },
		{ x = -0.4, y = 0.5, z = -0.2, tilt = 0.6, size = 0.9 },
		{ x = 0.05, y = 0.62, z = 0.42, tilt = 0.15, size = 0.8 },
	}
	for i, c in crystals do
		local crystalCf = cf
			* CFrame.new(c.x * s, c.y * s, c.z * s)
			* CFrame.Angles(rng:range(-0.25, 0.25), 0, c.tilt)
			* CFrame.Angles(0, math.pi / 4 + i, 0)
		addDecor(model, b, Geo.make("Part", decorProps({
			CFrame = crystalCf,
			Size = Vector3.new(0.55, 1.15, 0.55) * s * c.size,
			Color = if glowy then ore.Glow else ore.Color,
			Material = if glowy then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		})))
	end
	-- glowing vein line
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, -0.1 * s, -0.76 * s) * CFrame.Angles(0, 0, rng:range(-0.7, 0.7)),
		Size = Vector3.new(1.3 * s, 0.2, 0.06),
		Color = ore.Glow,
		Material = Enum.Material.Neon,
	})))
end

local function cleanOre(model: Model, cf: CFrame, info: ItemInfo, _rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local b = body(model, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(1.15, 1.25, 1.15), ore.Color, Enum.Material.SmoothPlastic)
	b.Reflectance = 0.15
	-- faceted top and bottom (gem look)
	addDecor(model, b, Geo.make("WedgePart", decorProps({
		CFrame = b.CFrame * CFrame.new(0, 0.95, 0),
		Size = Vector3.new(1.15, 0.65, 1.15),
		Color = ore.Color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
	})))
	addDecor(model, b, Geo.make("WedgePart", decorProps({
		CFrame = b.CFrame * CFrame.new(0, -0.95, 0) * CFrame.Angles(math.pi, 0, 0),
		Size = Vector3.new(1.15, 0.65, 1.15),
		Color = ore.Color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
	})))
	-- inner glow band
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = b.CFrame,
		Size = Vector3.new(1.2, 0.18, 1.2),
		Color = ore.Glow,
		Material = Enum.Material.Neon,
	})))
	if info.Grade == "Flawless" or info.Grade == "Pristine" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "GradeSparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(if info.Grade == "Flawless" then Color3.fromRGB(255, 236, 140) else Color3.fromRGB(200, 255, 210))
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.2, 0.6)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = if info.Grade == "Flawless" then 3 else 1.2
		sparkle.LightEmission = 1
		sparkle.LightInfluence = 0
		sparkle.Parent = b
	end
end

local function crushed(model: Model, cf: CFrame, info: ItemInfo, rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local pileColor = ore.Color:Lerp(Color3.fromRGB(90, 80, 74), 0.25)
	local b = body(model, cf, Vector3.new(1.5, 0.7, 1.5), pileColor)
	for _ = 1, 4 do
		addDecor(model, b, Geo.make("Part", decorProps({
			CFrame = cf * CFrame.new(rng:range(-0.45, 0.45), rng:range(0.2, 0.45), rng:range(-0.45, 0.45)) * Geo.randomTilt(rng, 0.8),
			Size = Vector3.new(0.45, 0.4, 0.45),
			Color = Geo.vary(ore.Color, rng, 0.08),
			Material = Enum.Material.SmoothPlastic,
		})))
	end
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, 0.36, 0),
		Size = Vector3.new(1.1, 0.06, 1.1),
		Color = ore.Glow,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})))
end

local function ingot(model: Model, cf: CFrame, info: ItemInfo, _rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local b = body(model, cf, Vector3.new(1.9, 0.55, 0.9), ore.Color, Enum.Material.Metal)
	-- bevelled top
	addDecor(model, b, Geo.make("Part", decorProps({
		CFrame = cf * CFrame.new(0, 0.33, 0),
		Size = Vector3.new(1.6, 0.12, 0.62),
		Color = ore.Color:Lerp(Color3.new(1, 1, 1), 0.18),
		Material = Enum.Material.Metal,
	})))
	for _, side in { -1, 1 } do
		addDecor(model, b, Geo.make("WedgePart", decorProps({
			CFrame = cf * CFrame.new(0, 0.33, side * 0.38) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			Size = Vector3.new(1.6, 0.12, 0.14),
			Color = ore.Color,
			Material = Enum.Material.Metal,
		})))
	end
	if info.Grade == "Flawless" then
		addDecor(model, b, Geo.make("Part", decorProps({
			CFrame = cf * CFrame.new(0, 0.4, 0),
			Size = Vector3.new(0.3, 0.02, 0.3),
			Color = Color3.fromRGB(255, 236, 140),
			Material = Enum.Material.Neon,
		})))
	end
end

local function gear(model: Model, cf: CFrame, info: ItemInfo, _rng: Rng.Rng)
	local ore = OreData.get(info.OreId)
	local metal = ore.Color
	local grip = Color3.fromRGB(96, 60, 36)
	local recipe = info.Recipe or "Dagger"
	if recipe == "Dagger" or recipe == "Greatsword" then
		local long = recipe == "Greatsword"
		local bladeLength = if long then 3.4 else 1.6
		local b = body(model, cf, Vector3.new(bladeLength + 1, 0.35, 0.6), metal, Enum.Material.Metal)
		b.Transparency = 1 -- the collider is invisible; visible parts are decor
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4, 0, 0), Size = Vector3.new(bladeLength, 0.14, if long then 0.55 else 0.42), Color = metal, Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("WedgePart", decorProps({ CFrame = cf * CFrame.new(0.4 + bladeLength / 2 + 0.25, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), Size = Vector3.new(if long then 0.55 else 0.42, 0.14, 0.5), Color = metal, Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4 - bladeLength / 2 - 0.1, 0, 0), Size = Vector3.new(0.2, 0.24, if long then 1.4 else 1), Color = Color3.fromRGB(220, 180, 80), Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0.4 - bladeLength / 2 - 0.55, 0, 0), Size = Vector3.new(0.7, 0.22, 0.22), Color = grip, Material = Enum.Material.SmoothPlastic })))
	elseif recipe == "ToolHead" then
		local b = body(model, cf, Vector3.new(2.4, 0.5, 0.5), metal, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			addDecor(model, b, Geo.make("WedgePart", decorProps({
				CFrame = cf * CFrame.new(side * 1.45, 0, 0) * CFrame.Angles(0, side * math.pi / 2, 0),
				Size = Vector3.new(0.5, 0.5, 0.6),
				Color = metal,
				Material = Enum.Material.Metal,
			})))
		end
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0, 0), Size = Vector3.new(0.6, 0.62, 0.62), Color = metal:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Metal })))
	else -- Helm
		local b = body(model, cf, Vector3.new(1.6, 1.3, 1.6), metal, Enum.Material.Metal, Enum.PartType.Ball)
		b.Size = Vector3.new(1.6, 1.6, 1.6)
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, -0.45, 0), Size = Vector3.new(1.8, 0.25, 1.8), Color = metal:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Metal })))
		addDecor(model, b, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0.85, 0), Size = Vector3.new(0.25, 0.45, 1.2), Color = Color3.fromRGB(200, 60, 50), Material = Enum.Material.SmoothPlastic })))
	end
	-- every gear piece gets a small glowing ore inlay
	local primary = model.PrimaryPart :: BasePart
	addDecor(model, primary, Geo.make("Part", decorProps({ CFrame = cf * CFrame.new(0, 0.2, 0), Size = Vector3.new(0.2, 0.2, 0.2), Color = ore.Glow, Material = Enum.Material.Neon })))
end

local BUILDERS = {
	Raw = rawChunk,
	Clean = cleanOre,
	Crushed = crushed,
	Ingot = ingot,
	Gear = gear,
}

-- Returns a Model (not parented). `seed` only changes the random details.
function ItemBuilder.build(info: ItemInfo, cf: CFrame, seed: number | string): Model
	local model = Instance.new("Model")
	model.Name = info.Kind .. "_" .. info.OreId
	local builder = BUILDERS[info.Kind]
	assert(builder, "Unknown item kind " .. tostring(info.Kind))
	builder(model, cf, info, Rng.new(seed))
	return model
end

--[[
	Contract (design v2): a still, anchored display copy of an item for
	podiums and the Ore Pen pile. No collisions, no welds, no physics.
	`cf` is the bottom center of where it should stand. Budget: <= 14 parts
	and at most 1 light (Legendary and Mythic only).
	(P0 stub: the physical item, anchored. The ore package replaces it.)
]]
function ItemBuilder.display(desc: { K: string, O: string, G: string?, R: string? }, cf: CFrame, seed: number | string?): Model
	local model = ItemBuilder.build({ Kind = desc.K, OreId = desc.O, Grade = desc.G, Recipe = desc.R }, cf, seed or 1)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	model.Name = "Display_" .. desc.K .. "_" .. desc.O
	return model
end

return ItemBuilder
