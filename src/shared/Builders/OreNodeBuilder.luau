--[[
	Builds mineable ore nodes and their crack stages.

	Node model layout:
	  OreNode (Model, PrimaryPart = Rock1)
	    Rock1..RockN   chunky crust blocks (ore.Crust)
	    Shard          ore crystals poking out (ore.Color / Neon for rare+)
	    Vein           thin glowing lines on the rock (ore.Glow)
	    Crack          added per stage (dark line + glow line inside)

	Stage 0 = intact, 1 = cracked, 2 = a chunk broke off, 3 = shattered.
]]

local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)
local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local OreNodeBuilder = {}

local CRACK_COLOR = Color3.fromRGB(28, 20, 18)

local function partProps(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = true, CanCollide = true }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

-- base: CFrame on the ground (bottom center). seed: number/string for the shape.
function OreNodeBuilder.build(oreId: string, base: CFrame, seed: number | string): Model
	local ore = OreData.get(oreId)
	local rarity = Rarity.get(ore.Rarity)
	local rng = Rng.new(seed)
	local scale = 1 + (rarity.Order - 1) * 0.07

	local model = Instance.new("Model")
	model.Name = "OreNode"

	-- Main crust block, slightly sunk into the ground.
	local mainSize = Vector3.new(rng:range(4.4, 5.2), rng:range(3.4, 4.2), rng:range(4.2, 5)) * scale
	local mainCf = base * CFrame.new(0, mainSize.Y * 0.42, 0) * CFrame.Angles(rng:range(-0.18, 0.18), rng:range(0, math.pi * 2), rng:range(-0.18, 0.18))
	local rock1 = Geo.block(model, mainCf, mainSize, Geo.vary(ore.Crust, rng, 0.05), Enum.Material.SmoothPlastic, partProps())
	rock1.Name = "Rock1"

	-- Two side blocks (Rock2 is the one that breaks off at stage 2).
	for i = 2, 3 do
		local angle = rng:range(0, math.pi * 2)
		local dist = mainSize.X * rng:range(0.32, 0.45)
		local s = mainSize * rng:range(0.45, 0.62)
		local cf = base * CFrame.new(math.cos(angle) * dist, s.Y * 0.4, math.sin(angle) * dist) * Geo.randomTilt(rng, 0.35)
		local rock = Geo.block(model, cf, s, Geo.vary(ore.Crust, rng, 0.08), Enum.Material.SmoothPlastic, partProps())
		rock.Name = "Rock" .. i
	end

	-- Crystals.
	local glowy = rarity.Order >= 3
	local shardCount = 3 + math.min(2, rarity.Order - 1)
	local biggest: BasePart? = nil
	for i = 1, shardCount do
		local yaw = (i / shardCount) * math.pi * 2 + rng:range(-0.4, 0.4)
		local tilt = rng:range(0.35, 0.8)
		local length = rng:range(1.6, 2.6) * scale
		local width = rng:range(0.75, 1.1) * scale
		local origin = mainCf.Position + Vector3.new(math.cos(yaw) * mainSize.X * 0.22, mainSize.Y * rng:range(0.05, 0.3), math.sin(yaw) * mainSize.Z * 0.22)
		local dir = CFrame.fromAxisAngle(Vector3.new(-math.sin(yaw), 0, math.cos(yaw)), tilt)
		-- diamond-prism body: a block turned 45 degrees around its long axis
		local bodyCf = CFrame.new(origin) * dir * CFrame.new(0, length * 0.5, 0) * CFrame.Angles(0, math.pi / 4 + rng:range(-0.2, 0.2), 0)
		local material = if glowy then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local color = if glowy then ore.Glow else ore.Color
		local shard = Geo.block(model, bodyCf, Vector3.new(width, length, width), color, material, partProps({ CastShadow = false }))
		shard.Name = "Shard"
		-- chisel-shaped tip on top
		local tipHeight = width * 1.1
		local tip = Geo.wedge(
			model,
			bodyCf * CFrame.new(0, length / 2 + tipHeight / 2, 0),
			Vector3.new(width, tipHeight, width),
			Geo.vary(color, rng, 0.04),
			material,
			partProps({ CastShadow = false })
		)
		tip.Name = "Shard"
		if not biggest or length > (biggest :: BasePart).Size.Y then
			biggest = shard
		end
	end

	-- Glowing veins across the main block (makes ore easy to spot in caves).
	local veins = if rarity.Order >= 2 then 3 else 2
	for _ = 1, veins do
		local face = rng:int(1, 4)
		local axis = if face <= 2 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		local sign = if face % 2 == 0 then 1 else -1
		local half = mainSize / 2
		local offset = axis * sign * (if axis.X ~= 0 then half.X else half.Z)
		local along = rng:range(-0.25, 0.25)
		local cf = mainCf
			* CFrame.new(offset + Vector3.new(0, along * mainSize.Y, 0))
			* CFrame.Angles(0, if axis.X ~= 0 then math.pi / 2 else 0, rng:range(-0.9, 0.9))
		local vein = Geo.block(
			model,
			cf,
			Vector3.new(rng:range(1.6, 2.6) * scale, 0.22, 0.12),
			ore.Glow,
			Enum.Material.Neon,
			{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
		)
		vein.Name = "Vein"
	end

	if glowy and biggest then
		local light = Instance.new("PointLight")
		light.Color = ore.Glow
		light.Range = 10 + rarity.Order * 1.5
		light.Brightness = 0.8 + rarity.Order * 0.15
		light.Shadows = false
		light.Parent = biggest
	end

	if rarity.Order >= 4 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Glint"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(ore.Glow)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Lifetime = NumberRange.new(0.8, 1.3)
		sparkle.Speed = NumberRange.new(0.2, 0.8)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 1.5 + rarity.Order * 0.5
		sparkle.LightEmission = 1
		sparkle.LightInfluence = 0
		sparkle.Parent = rock1
	end

	model.PrimaryPart = rock1
	model:SetAttribute("OreId", oreId)
	model:SetAttribute("Stage", 0)
	return model
end

-- Adds crack lines for a new stage. Returns parts that should fall off (stage 2).
function OreNodeBuilder.applyStage(model: Model, stage: number, seed: number | string): { BasePart }
	local oreId = model:GetAttribute("OreId") :: string
	local ore = OreData.get(oreId)
	local rng = Rng.new(tostring(seed) .. ":" .. stage)
	local rock1 = model:FindFirstChild("Rock1") :: BasePart?
	local broken = {}
	if not rock1 then
		return broken
	end
	local size = rock1.Size
	local cracks = if stage == 1 then 3 else 2
	for _ = 1, cracks do
		-- pick one of the 4 side faces or the top
		local face = rng:int(1, 5)
		local cf: CFrame
		if face == 5 then
			cf = rock1.CFrame * CFrame.new(rng:range(-0.25, 0.25) * size.X, size.Y / 2, rng:range(-0.25, 0.25) * size.Z) * CFrame.Angles(0, rng:range(0, 3.14), 0)
		else
			local xAxis = face <= 2
			local sign = if face % 2 == 0 then 1 else -1
			local offset = if xAxis then Vector3.new(sign * size.X / 2, 0, 0) else Vector3.new(0, 0, sign * size.Z / 2)
			cf = rock1.CFrame
				* CFrame.new(offset + Vector3.new(0, rng:range(-0.2, 0.25) * size.Y, 0))
				* CFrame.Angles(0, if xAxis then math.pi / 2 else 0, 0)
				* CFrame.Angles(0, 0, rng:range(-1.2, 1.2))
				* CFrame.Angles(math.pi / 2, 0, 0)
		end
		local length = rng:range(1.8, 3.2)
		local dark = Geo.block(
			model,
			cf,
			Vector3.new(length, 0.14, 0.32),
			CRACK_COLOR,
			Enum.Material.SmoothPlastic,
			{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
		)
		dark.Name = "Crack"
		local glow = Geo.block(
			model,
			cf * CFrame.new(0, 0.02, 0),
			Vector3.new(length * 0.75, 0.16, 0.1),
			ore.Glow,
			Enum.Material.Neon,
			{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
		)
		glow.Name = "Crack"
	end
	if stage == 2 then
		local rock2 = model:FindFirstChild("Rock2") :: BasePart?
		if rock2 then
			table.insert(broken, rock2)
		end
		for _, child in model:GetChildren() do
			if child.Name == "Shard" and #broken < 3 then
				table.insert(broken, child :: BasePart)
			end
		end
	end
	model:SetAttribute("Stage", stage)
	return broken
end

return OreNodeBuilder
