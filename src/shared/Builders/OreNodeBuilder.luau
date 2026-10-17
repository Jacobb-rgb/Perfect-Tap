--[[
	Builds mineable rocks and their crack stages.

	design v2: `buildRock(zoneId, oreIds, base, seed)` is the rock players
	blast (1-3 hidden ores, see below). `build(oreId, base, seed)` is the old
	single-ore node (kept for tools and tests).

	Old node layout:
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
local ItemBuilder = require(script.Parent.ItemBuilder)

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
	local mainCf = base
		* CFrame.new(0, mainSize.Y * 0.42, 0)
		* CFrame.Angles(rng:range(-0.18, 0.18), rng:range(0, math.pi * 2), rng:range(-0.18, 0.18))
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
		local origin = mainCf.Position
			+ Vector3.new(math.cos(yaw) * mainSize.X * 0.22, mainSize.Y * rng:range(0.05, 0.3), math.sin(yaw) * mainSize.Z * 0.22)
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

	-- lights only on Epic+ (rare ores already glow through Neon + Bloom); keeps phones fast
	if rarity.Order >= 4 and biggest then
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

--[[
	Rocks (design v2): a zone-styled boulder holding 1-3 ores (`oreIds`, the
	server rolled them). The rock hides what is inside: only small glints in
	the ores' Glow colors, all the same size whatever the rarity. More ores =
	a bigger rock with more lumps.

	  Rock (Model, PrimaryPart = Rock1)
	    Rock1          the main boulder (cracks are drawn on it)
	    Bulk           the boulder again, turned 45 degrees (more facets)
	    Cap / Skirt    lighter top slab, darker foot (three shades)
	    Rock2..Rock5   side lumps (Rock2 and the top lump fall off at stage 2)
	    Pebble         loose stones at the foot
	    Moss           grass tuft (Outcrops only)
	    Glint          tiny glowing crystals, 2-3 per ore
	Attributes: Zone, OreCount, Stage = 0. No OreId: the content is secret.
	Budget: <= 20 parts.
]]

export type RockStyle = { Mid: Color3, Light: Color3, Dark: Color3, Moss: Color3? }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

OreNodeBuilder.RockStyles = {
	Quarry = { Mid = rgb(124, 114, 104), Light = rgb(160, 148, 132), Dark = rgb(90, 82, 76) },
	Outcrops = { Mid = rgb(128, 120, 110), Light = rgb(164, 154, 140), Dark = rgb(92, 86, 80), Moss = rgb(86, 156, 58) },
	EmberCaves = { Mid = rgb(94, 54, 44), Light = rgb(128, 76, 58), Dark = rgb(62, 36, 32) },
	DeepHollow = { Mid = rgb(66, 76, 108), Light = rgb(100, 112, 150), Dark = rgb(42, 48, 70) },
	Grotto = { Mid = rgb(104, 92, 124), Light = rgb(142, 128, 164), Dark = rgb(72, 62, 88) },
} :: { [string]: RockStyle }

local RAW_GLOW = Color3.fromRGB(255, 170, 90) -- crack glow when a rock has no glints

local VERTEX_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, math.pi / 4, 0)
local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local SMALL = { CanTouch = false, CanQuery = true, CanCollide = false, CastShadow = false }

function OreNodeBuilder.buildRock(zoneId: string, oreIds: { string }, base: CFrame, seed: number | string): Model
	local style = OreNodeBuilder.RockStyles[zoneId] or OreNodeBuilder.RockStyles.Quarry
	local rng = Rng.new(seed)
	local count = math.clamp(#oreIds, 1, 3)
	local scale = 1 + (count - 1) * 0.2

	local model = Instance.new("Model")
	model.Name = "Rock"
	base = base * CFrame.Angles(0, rng:range(0, math.pi * 2), 0)

	-- main boulder, sunk a little into the ground
	local mainSize = Vector3.new(rng:range(4.4, 4.9), rng:range(3.3, 3.7), rng:range(4.0, 4.5)) * scale
	local mainCf = base * CFrame.new(0, mainSize.Y * 0.42, 0) * CFrame.Angles(rng:range(-0.1, 0.1), 0, rng:range(-0.1, 0.1))
	local rock1 = Geo.block(model, mainCf, mainSize, Geo.vary(style.Mid, rng, 0.03), Enum.Material.SmoothPlastic, SOLID)
	rock1.Name = "Rock1"
	-- the same boulder turned 45 degrees adds facets: a boulder, not a crate
	local bulkSize = Vector3.new(mainSize.X * 0.86, mainSize.Y * 0.92, mainSize.Z * 0.9)
	local bulk = Geo.block(
		model,
		base
			* CFrame.new(0, mainSize.Y * 0.4, 0)
			* CFrame.Angles(rng:range(-0.08, 0.08), math.pi / 4 + rng:range(-0.15, 0.15), rng:range(-0.08, 0.08)),
		bulkSize,
		Geo.vary(style.Mid:Lerp(style.Dark, 0.3), rng, 0.03),
		Enum.Material.SmoothPlastic,
		SOLID
	)
	bulk.Name = "Bulk"
	-- lighter cap and darker foot: the three-shade voxel look
	local cap = Geo.block(
		model,
		mainCf
			* CFrame.new(rng:range(-0.25, 0.25), mainSize.Y / 2 + 0.1, rng:range(-0.25, 0.25))
			* CFrame.Angles(rng:range(-0.08, 0.08), math.pi / 4 + rng:range(-0.3, 0.3), rng:range(-0.08, 0.08)),
		Vector3.new(mainSize.X * 0.66, 0.6, mainSize.Z * 0.62),
		Geo.vary(style.Light, rng, 0.03),
		Enum.Material.SmoothPlastic,
		SOLID
	)
	cap.Name = "Cap"
	local skirt = Geo.block(
		model,
		base * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.pi / 8 + rng:range(-0.2, 0.2), 0),
		Vector3.new(mainSize.X * 1.06, 0.8, mainSize.Z * 1.04),
		Geo.vary(style.Dark, rng, 0.03),
		Enum.Material.SmoothPlastic,
		SOLID
	)
	skirt.Name = "Skirt"

	-- side lumps; more ores = more lumps
	local lumps = 2 + (count - 1)
	local start = rng:range(0, math.pi * 2)
	for i = 1, lumps do
		local s: Vector3
		local cf: CFrame
		if i <= 2 then
			local angle = start + (i - 1) * 2.4 + rng:range(-0.3, 0.3)
			local dist = mainSize.X * rng:range(0.42, 0.5)
			s = mainSize * rng:range(0.42, 0.52)
			cf = base * CFrame.new(math.cos(angle) * dist, s.Y * 0.42, math.sin(angle) * dist) * Geo.randomTilt(rng, 0.3)
		else
			-- a lump on top of the boulder (bigger rocks are taller)
			local angle = start + 1.2 + i
			s = mainSize * rng:range(0.36, 0.44)
			cf = mainCf
				* CFrame.new(math.cos(angle) * mainSize.X * 0.18, mainSize.Y * 0.5 + s.Y * 0.3, math.sin(angle) * mainSize.Z * 0.18)
				* Geo.randomTilt(rng, 0.35)
		end
		local lump =
			Geo.block(model, cf, s, Geo.vary(if i % 2 == 0 then style.Light else style.Mid, rng, 0.05), Enum.Material.SmoothPlastic, SOLID)
		lump.Name = "Rock" .. (i + 1)
	end
	for i = 1, 2 do
		local angle = start + 1.2 + i * 2.1
		local dist = mainSize.X * rng:range(0.62, 0.72)
		local size = rng:range(0.7, 1.0) * scale
		local pebble = Geo.block(
			model,
			base * CFrame.new(math.cos(angle) * dist, size * 0.3, math.sin(angle) * dist) * Geo.randomTilt(rng, 0.4),
			Vector3.new(size, size * 0.7, size * 0.9),
			Geo.vary(style.Dark, rng, 0.06),
			Enum.Material.SmoothPlastic,
			SMALL
		)
		pebble.Name = "Pebble"
	end
	if style.Moss then
		local moss = Geo.block(
			model,
			cap.CFrame * CFrame.new(rng:range(-0.5, 0.5), 0.4, rng:range(-0.5, 0.5)) * CFrame.Angles(0, rng:range(0, 3), 0),
			Vector3.new(mainSize.X * 0.36, 0.42, mainSize.Z * 0.32),
			style.Moss,
			Enum.Material.SmoothPlastic,
			SMALL
		)
		moss.Name = "Moss"
	end

	-- glints: tiny glowing crystals in the ores' colors, peeking out of the boulder's sides
	local perOre = if count == 1 then 3 else 2
	local half = mainSize / 2
	for i = 1, count do
		local ore = OreData.ById[oreIds[i]]
		local color = ItemBuilder.glowColor(if ore then ore.Glow else RAW_GLOW)
		local sector = start + 0.6 + (i - 1) * (math.pi * 2 / count)
		for j = 1, perOre do
			local a = sector + (j - 1) * 0.55 + rng:range(-0.2, 0.2)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			-- push the point out to the boulder's side: the outer of the two boxes along dir
			local t = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Z / math.max(math.abs(dir.Z), 1e-3))
			local bx, bz = (dir.X - dir.Z) / math.sqrt(2), (dir.X + dir.Z) / math.sqrt(2) -- dir in the turned box
			local tBulk = math.min(bulkSize.X / 2 / math.max(math.abs(bx), 1e-3), bulkSize.Z / 2 / math.max(math.abs(bz), 1e-3))
			t = math.max(t, tBulk)
			local y = rng:range(-0.15, 0.3) * mainSize.Y
			local size = if j == 1 then 0.62 else 0.44
			local glint = Geo.block(
				model,
				mainCf * CFrame.new(dir.X * t, y, dir.Z * t) * CFrame.Angles(rng:range(-0.4, 0.4), a, rng:range(-0.4, 0.4)) * VERTEX_UP,
				Vector3.new(size, size, size),
				color,
				Enum.Material.Neon,
				{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
			)
			glint.Name = "Glint"
		end
	end

	model.PrimaryPart = rock1
	model:SetAttribute("Zone", zoneId)
	model:SetAttribute("OreCount", count)
	model:SetAttribute("Stage", 0)
	return model
end

-- Adds crack lines for a new stage. Returns parts that should fall off (stage 2).
function OreNodeBuilder.applyStage(model: Model, stage: number, seed: number | string): { BasePart }
	local oreId = model:GetAttribute("OreId")
	local glowColor = RAW_GLOW
	if type(oreId) == "string" and OreData.exists(oreId) then
		glowColor = OreData.get(oreId).Glow
	else
		local glint = model:FindFirstChild("Glint")
		if glint and glint:IsA("BasePart") then
			glowColor = glint.Color
		end
	end
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
			cf = rock1.CFrame
				* CFrame.new(rng:range(-0.25, 0.25) * size.X, size.Y / 2, rng:range(-0.25, 0.25) * size.Z)
				* CFrame.Angles(0, rng:range(0, 3.14), 0)
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
			glowColor,
			Enum.Material.Neon,
			{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
		)
		glow.Name = "Crack"
	end
	if stage == 2 then
		-- a side lump and the top lump (rocks with 2-3 ores) break off; old nodes also lose
		-- 2 crystals, rocks one glint (the others keep showing the colors inside)
		for _, name in { "Rock2", "Rock4", "Rock5" } do
			local piece = model:FindFirstChild(name)
			if piece and piece:IsA("BasePart") and #broken < 2 then
				table.insert(broken, piece)
			end
		end
		local crystals = 0
		for _, child in model:GetChildren() do
			local limit = if child.Name == "Shard" then 2 elseif child.Name == "Glint" then 1 else 0
			if crystals < limit and child:IsA("BasePart") then
				table.insert(broken, child)
				crystals += 1
			end
		end
	end
	model:SetAttribute("Stage", stage)
	return broken
end

return OreNodeBuilder
