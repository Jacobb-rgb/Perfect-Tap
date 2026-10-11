--[[
	Emberfall: the hub town. Interactive spots are tagged so services can
	attach prompts at runtime:
	  "SellBin"      drop items in to sell them        (TradingPost)
	  "SellCounter"  prompt: sell everything you carry (TradingPost)
	  "ShopCounter"  prompt: open the shop             (ToolSmithy)
	  "EmberChest"   prompt: daily reward
	  "GuildBoard"   prompt: group reward / name your forge
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local Town = {}

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function solid(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

local function decor(extra: { [string]: any }?): { [string]: any }
	local props = { CanTouch = false, CanQuery = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

-- Frame of a landmark: origin on the ground, LookVector = Facing.
local function landmarkCFrame(info: { Position: Vector3, Facing: Vector3 }): CFrame
	return CFrame.lookAt(info.Position, info.Position + info.Facing)
end

-- Gable roof made of two wedges along the frame's X axis.
local function gableRoof(parent: Instance, cf: CFrame, width: number, depth: number, height: number, color: Color3)
	local half = depth / 2
	-- WedgePart's tall side is at +Z: the front half needs no turn, the back half is turned around
	Geo.wedge(parent, cf * CFrame.new(0, height / 2, -half / 2), Vector3.new(width, height, half), color, nil, solid())
	Geo.wedge(parent, cf * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(width, height, half), color, nil, solid())
end

local function plaza(parent: Instance, rng: Rng.Rng)
	local m = model("Plaza", parent)
	local center = WorldLayout.Plaza.Center
	local radius = WorldLayout.Plaza.Radius
	Geo.cylinder(m, center + Vector3.new(0, 0.1, 0), 0.4, radius * 2, Palette.Plaza, nil, solid({ CastShadow = false }))
	Geo.cylinder(m, center + Vector3.new(0, 0.15, 0), 0.42, radius * 1.1, Palette.PlazaDark, nil, solid({ CastShadow = false }))
	Geo.cylinder(m, center + Vector3.new(0, 0.2, 0), 0.44, radius * 0.95, Palette.Plaza, nil, solid({ CastShadow = false }))
	-- border stones
	local count = 36
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (radius - 0.6)
		local open = math.abs(math.sin(a)) < 0.16 or math.abs(math.cos(a)) < 0.16
		if not open then
			Geo.block(m, CFrame.lookAt(p, center) * CFrame.new(0, 0.5, 0), Vector3.new(3.2, 1, 1.4), Geo.vary(Palette.StoneWarm, rng, 0.05), nil, solid({ CastShadow = false }))
		end
	end
	-- Heartstone monument: pedestal, anvil, floating shard
	local mon = model("HeartstoneMonument", m)
	Geo.cylinder(mon, center + Vector3.new(0, 1, 0), 2, 12, Palette.StoneDark, nil, solid())
	Geo.cylinder(mon, center + Vector3.new(0, 2.5, 0), 1, 9, Palette.Stone, nil, solid())
	Geo.block(mon, CFrame.new(center + Vector3.new(0, 4.4, 0)), Vector3.new(3, 2.8, 2.4), Palette.Metal, Enum.Material.Metal, solid())
	Geo.block(mon, CFrame.new(center + Vector3.new(0, 6.2, 0)), Vector3.new(6, 1.2, 2.6), Palette.Metal, Enum.Material.Metal, solid())
	Geo.wedge(mon, CFrame.new(center + Vector3.new(-4, 6.2, 0)) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), Vector3.new(2.6, 1.2, 2), Palette.Metal, Enum.Material.Metal, solid())
	local shardModel = model("HeartShard", mon)
	local shardCf = CFrame.new(center + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0.4, 0.2) * CFrame.Angles(0, math.pi / 4, 0)
	local shard = Geo.block(shardModel, shardCf, Vector3.new(1.8, 4, 1.8), Color3.fromRGB(255, 70, 120), Enum.Material.Neon, decor({ CastShadow = false }))
	shard.Name = "HeartShard"
	Geo.wedge(shardModel, shardCf * CFrame.new(0, 2.9, 0), Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(255, 90, 140), Enum.Material.Neon, decor({ CastShadow = false }))
	Geo.wedge(shardModel, shardCf * CFrame.new(0, -2.9, 0) * CFrame.Angles(math.pi, 0, 0), Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(255, 90, 140), Enum.Material.Neon, decor({ CastShadow = false }))
	Props.pointLight(shard, Color3.fromRGB(255, 80, 130), 22, 1.8)
	Props.emitter(shard, "Sparkle", Color3.fromRGB(255, 140, 180), 4)
	shardModel.PrimaryPart = shard
	-- stream in as one piece so the client can spin all three parts together
	shardModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	shardModel:AddTag("Spin")
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		Props.brazier(m, CFrame.new(center + Vector3.new(math.cos(a), 0, math.sin(a)) * 13), i % 2 == 0)
	end
end

local function greatForge(parent: Instance, rng: Rng.Rng)
	local info = WorldLayout.Landmarks.GreatForge
	local cf = landmarkCFrame(info)
	local m = model("GreatForge", parent)
	-- foundation and hall
	Geo.block(m, cf * CFrame.new(0, 1, 0), Vector3.new(44, 2, 26), Palette.StoneDark, nil, solid())
	Geo.block(m, cf * CFrame.new(0, 10, 2), Vector3.new(36, 16, 18), Palette.StoneWarm, nil, solid())
	-- stone trims
	Geo.block(m, cf * CFrame.new(0, 18.4, 2), Vector3.new(38, 1.2, 20), Palette.StoneDark, nil, solid())
	for _, x in { -17.5, 17.5 } do
		Geo.block(m, cf * CFrame.new(x, 10, -7.4), Vector3.new(2.4, 16, 2.4), Palette.Stone, nil, solid())
	end
	gableRoof(m, cf * CFrame.new(0, 19, 2), 40, 22, 9, Palette.RoofRed)
	-- forge mouth (glowing arch) facing the plaza
	local mouthCf = cf * CFrame.new(0, 7, -7.2)
	Geo.block(m, mouthCf * CFrame.new(0, 0, 0), Vector3.new(14, 11, 1), Palette.StoneDark, nil, solid())
	local glow = Geo.block(m, mouthCf * CFrame.new(0, -0.5, -0.3), Vector3.new(10, 8, 0.6), Palette.ForgeGlow, Enum.Material.Neon, decor({ CastShadow = false }))
	glow.Name = "ForgeGlow"
	Geo.wedge(m, mouthCf * CFrame.new(-4, 4.4, -0.35) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(0.7, 2, 2.2), Palette.StoneDark, nil, decor())
	Geo.wedge(m, mouthCf * CFrame.new(4, 4.4, -0.35) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.7, 2, 2.2), Palette.StoneDark, nil, decor())
	Props.pointLight(glow, Palette.ForgeGlow, 40, 3, false)
	Props.emitter(glow, "Embers", Palette.ForgeGlow, 10)
	Props.sign(m, cf * CFrame.new(0, 15.5, -7.6), "THE GREAT FORGE", 20, 3.2, Palette.WoodDark, Palette.Gold)
	-- chimneys with glowing tops and smoke
	for _, x in { -12, 12 } do
		Geo.block(m, cf * CFrame.new(x, 22, 8), Vector3.new(7, 36, 7), Palette.StoneDark, nil, solid())
		Geo.block(m, cf * CFrame.new(x, 40.5, 8), Vector3.new(8.4, 1.6, 8.4), Palette.Stone, nil, solid())
		local top = Geo.block(m, cf * CFrame.new(x, 41.4, 8), Vector3.new(5.6, 0.4, 5.6), Palette.Ember, Enum.Material.Neon, decor({ CastShadow = false }))
		Props.emitter(top, "Smoke", nil, 4)
		Props.emitter(top, "Embers", nil, 3)
	end
	-- molten channel to a basin in front
	local channel = Geo.block(m, cf * CFrame.new(0, 0.35, -15), Vector3.new(2.2, 0.5, 14), Palette.Lava, Enum.Material.Neon, decor({ CastShadow = false }))
	channel.Name = "MoltenChannel"
	Geo.block(m, cf * CFrame.new(-1.6, 0.6, -15), Vector3.new(1, 1, 14), Palette.StoneDark, nil, solid())
	Geo.block(m, cf * CFrame.new(1.6, 0.6, -15), Vector3.new(1, 1, 14), Palette.StoneDark, nil, solid())
	local basinPos = (cf * CFrame.new(0, 0, -23)).Position
	Geo.cylinder(m, basinPos + Vector3.new(0, 0.9, 0), 1.8, 8, Palette.StoneDark, nil, solid())
	local molten = Geo.cylinder(m, basinPos + Vector3.new(0, 1.85, 0), 0.2, 6.4, Palette.Lava, Enum.Material.Neon, decor({ CastShadow = false }))
	Props.pointLight(molten, Palette.ForgeGlow, 18, 1.5)
	Props.emitter(molten, "Embers", nil, 4)
	-- anvils, barrels and crates around the forge
	for _, x in { -15, 15 } do
		local p = cf * CFrame.new(x, 2, -11)
		Geo.block(m, p * CFrame.new(0, 1, 0), Vector3.new(2.4, 2, 2), Palette.WoodDark, nil, solid())
		Geo.block(m, p * CFrame.new(0, 2.5, 0), Vector3.new(3.6, 1, 1.6), Palette.Metal, Enum.Material.Metal, solid())
	end
	for i = 1, 4 do
		Props.barrel(m, cf * CFrame.new(rng:range(-21, -18), 2, rng:range(-6, 8)), rng)
		Props.crate(m, cf * CFrame.new(rng:range(18, 21), 2, rng:range(-6, 8)), rng)
		local _ = i
	end
end

local function stall(parent: Instance, name: string, cf: CFrame, awningA: Color3, awningB: Color3, title: string, rng: Rng.Rng): (Model, Part)
	local m = model(name, parent)
	-- platform
	Geo.block(m, cf * CFrame.new(0, 0.5, 2), Vector3.new(18, 1, 14), Palette.WoodDark, nil, solid())
	-- back wall + side walls
	Geo.block(m, cf * CFrame.new(0, 6, 8.5), Vector3.new(18, 10, 1), Palette.WoodLight, nil, solid())
	Geo.block(m, cf * CFrame.new(-8.5, 6, 4), Vector3.new(1, 10, 8), Palette.Wood, nil, solid())
	Geo.block(m, cf * CFrame.new(8.5, 6, 4), Vector3.new(1, 10, 8), Palette.Wood, nil, solid())
	-- posts
	for _, x in { -8.6, 8.6 } do
		Geo.block(m, cf * CFrame.new(x, 6, -4.4), Vector3.new(1, 10, 1), Palette.WoodDark, nil, solid())
	end
	-- striped awning (slanted)
	local stripes = 6
	local stripeW = 19 / stripes
	for i = 0, stripes - 1 do
		local x = -9.5 + stripeW * (i + 0.5)
		local color = if i % 2 == 0 then awningA else awningB
		Geo.wedge(m, cf * CFrame.new(x, 12.2, 2), Vector3.new(stripeW, 3, 14), color, nil, solid())
	end
	-- roof back block
	Geo.block(m, cf * CFrame.new(0, 11.2, 9), Vector3.new(19, 1, 1.4), Palette.WoodDark, nil, solid())
	-- counter
	local counter = Geo.block(m, cf * CFrame.new(0, 2.8, -3), Vector3.new(14, 3.6, 2.6), Palette.Wood, nil, solid())
	Geo.block(m, cf * CFrame.new(0, 4.75, -3), Vector3.new(14.6, 0.4, 3), Palette.WoodLight, nil, solid())
	Props.sign(m, cf * CFrame.new(0, 14.4, -4.5), title, 16, 2.6, Palette.WoodDark, Palette.Gold)
	Props.lantern(m, cf * CFrame.new(-10.5, 0, -5) * CFrame.Angles(0, math.pi / 2, 0), true)
	Props.lantern(m, cf * CFrame.new(10.5, 0, -5) * CFrame.Angles(0, -math.pi / 2, 0), false)
	local _ = rng
	return m, counter
end

local function tradingPost(parent: Instance, rng: Rng.Rng)
	local cf = landmarkCFrame(WorldLayout.Landmarks.TradingPost)
	local m, counter = stall(parent, "TradingPost", cf, Palette.Cloth, Palette.ClothCream, "PELL'S TRADING POST", rng)
	counter.Name = "SellCounter"
	counter:AddTag("SellCounter")
	Props.npc(m, cf * CFrame.new(0, 1, 1) * CFrame.Angles(0, 0, 0), "Pell the Trader", Color3.fromRGB(60, 130, 170), Color3.fromRGB(70, 60, 60), Color3.fromRGB(120, 80, 50))
	-- shelves with ore samples
	for i = 0, 4 do
		Geo.block(m, cf * CFrame.new(-6 + i * 3, 6.5, 7.6), Vector3.new(2.6, 0.3, 1.2), Palette.WoodDark, nil, decor())
		Geo.block(m, cf * CFrame.new(-6 + i * 3, 7.2, 7.6), Vector3.new(1, 1, 1), Color3.fromHSV(i / 5, 0.7, 1), Enum.Material.SmoothPlastic, decor())
	end
	-- the sell bin in front of the stall
	local bin = model("SellBin", m)
	local binCf = cf * CFrame.new(0, 0, -12)
	Geo.block(bin, binCf * CFrame.new(0, 0.4, 0), Vector3.new(9, 0.8, 7), Palette.WoodDark, nil, solid())
	Geo.block(bin, binCf * CFrame.new(0, 2, -3.3), Vector3.new(9, 4, 0.6), Palette.Wood, nil, solid())
	Geo.block(bin, binCf * CFrame.new(0, 2, 3.3), Vector3.new(9, 4, 0.6), Palette.Wood, nil, solid())
	Geo.block(bin, binCf * CFrame.new(-4.3, 2, 0), Vector3.new(0.6, 4, 7), Palette.Wood, nil, solid())
	Geo.block(bin, binCf * CFrame.new(4.3, 2, 0), Vector3.new(0.6, 4, 7), Palette.Wood, nil, solid())
	for _, z in { -3.3, 3.3 } do
		Geo.block(bin, binCf * CFrame.new(0, 3.4, z), Vector3.new(9.2, 0.5, 0.7), Palette.Gold, Enum.Material.Metal, decor())
	end
	local intake = Geo.block(bin, binCf * CFrame.new(0, 2.6, 0), Vector3.new(8, 5, 6), Palette.Gold, nil, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	intake.Name = "Intake"
	bin:AddTag("SellBin")
	Props.sign(bin, binCf * CFrame.new(0, 5.6, -3.4), "SELL", 5, 1.8, Palette.WoodDark, Palette.Gold)
	-- coin glow inside
	local coins = Geo.block(bin, binCf * CFrame.new(0, 1.0, 0), Vector3.new(7.6, 0.4, 5.6), Palette.Gold, Enum.Material.Neon, decor({ CastShadow = false }))
	coins.Name = "Coins"
	coins.Transparency = 0.2
end

local function toolSmithy(parent: Instance, rng: Rng.Rng)
	local cf = landmarkCFrame(WorldLayout.Landmarks.ToolSmithy)
	local m, counter = stall(parent, "ToolSmithy", cf, Palette.RoofTeal, Palette.ClothCream, "ULDA'S TOOL SMITHY", rng)
	counter.Name = "ShopCounter"
	counter:AddTag("ShopCounter")
	Props.npc(m, cf * CFrame.new(0, 1, 1), "Forgemaster Ulda", Color3.fromRGB(150, 60, 50), Color3.fromRGB(60, 50, 50), nil)
	-- pickaxe rack on the back wall
	local colors = { Color3.fromRGB(130, 128, 124), Color3.fromRGB(222, 120, 60), Color3.fromRGB(176, 182, 194), Color3.fromRGB(255, 96, 36), Color3.fromRGB(52, 128, 255) }
	for i, color in colors do
		local p = cf * CFrame.new(-6 + (i - 1) * 3, 7, 7.8)
		Geo.block(m, p, Vector3.new(0.35, 4.5, 0.35), Palette.WoodLight, nil, decor())
		Geo.block(m, p * CFrame.new(0, 2, 0), Vector3.new(2.4, 0.6, 0.5), color, Enum.Material.Metal, decor())
	end
	-- anvil + forge corner
	Geo.block(m, cf * CFrame.new(-11.5, 1.5, -2), Vector3.new(2.4, 3, 2), Palette.WoodDark, nil, solid())
	Geo.block(m, cf * CFrame.new(-11.5, 3.4, -2), Vector3.new(3.6, 1, 1.6), Palette.Metal, Enum.Material.Metal, solid())
	Props.brazier(m, cf * CFrame.new(11.8, 0, -1), true)
end

local function emberChest(parent: Instance)
	local info = WorldLayout.Landmarks.EmberChest
	local cf = landmarkCFrame(info)
	local m = model("EmberChest", parent)
	Geo.block(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(6, 0.6, 4.4), Palette.StoneDark, nil, solid())
	local body = Geo.block(m, cf * CFrame.new(0, 1.9, 0), Vector3.new(4.6, 2.6, 3), Palette.Wood, nil, solid())
	Geo.block(m, cf * CFrame.new(0, 3.6, 0), Vector3.new(4.8, 0.9, 3.2), Palette.WoodDark, nil, solid())
	for _, x in { -1.8, 1.8 } do
		Geo.block(m, cf * CFrame.new(x, 2.3, 0), Vector3.new(0.4, 3.4, 3.3), Palette.Gold, Enum.Material.Metal, decor())
	end
	local lock = Geo.block(m, cf * CFrame.new(0, 2.8, -1.6), Vector3.new(0.9, 1, 0.3), Palette.ForgeGlow, Enum.Material.Neon, decor({ CastShadow = false }))
	Props.pointLight(lock, Palette.ForgeGlow, 10, 1)
	Props.emitter(lock, "Embers", nil, 3)
	body.Name = "Chest"
	m:AddTag("EmberChest")
	m.PrimaryPart = body
end

local function guildBoard(parent: Instance)
	local cf = landmarkCFrame(WorldLayout.Landmarks.GuildBoard)
	local m = model("GuildBoard", parent)
	for _, x in { -3.4, 3.4 } do
		Geo.block(m, cf * CFrame.new(x, 3.5, 0), Vector3.new(0.6, 7, 0.6), Palette.WoodDark, nil, solid())
	end
	local board = Props.sign(m, cf * CFrame.new(0, 4.5, 0), "FORGEKEEPERS' GUILD", 7.2, 3.6, Palette.WoodLight, Palette.WoodDark)
	board.Name = "Board"
	Geo.wedge(m, cf * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(1.4, 1.2, 4), Palette.RoofRed, nil, decor())
	Geo.wedge(m, cf * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(1.4, 1.2, 4), Palette.RoofRed, nil, decor())
	m:AddTag("GuildBoard")
	m.PrimaryPart = board
end

local function roads(parent: Instance, rng: Rng.Rng)
	local m = model("Roads", parent)
	for _, road in WorldLayout.Roads do
		local from, to, width = road.From, road.To, road.Width
		local delta = to - from
		local length = delta.Magnitude
		local cf = CFrame.lookAt((from + to) / 2, to)
		Geo.block(m, cf * CFrame.new(0, 0.06, 0), Vector3.new(width, 0.3, length + width), Palette.Dirt, nil, decor({ CastShadow = false, CanCollide = false }))
		-- pebbles along the edges
		local steps = math.floor(length / 7)
		for i = 0, steps do
			if rng:chance(0.5) then
				local side = if rng:chance(0.5) then -1 else 1
				local p = cf * CFrame.new(side * (width / 2 + rng:range(0.3, 1)), 0.2, -length / 2 + i * 7)
				Geo.block(m, p * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(rng:range(0.8, 1.6), 0.6, rng:range(0.8, 1.6)), Geo.vary(Palette.Stone, rng, 0.06), nil, decor({ CastShadow = false }))
			end
		end
		-- lanterns every ~28 studs
		local lanterns = math.floor(length / 28)
		for i = 1, lanterns do
			local side = if i % 2 == 0 then -1 else 1
			local p = cf * CFrame.new(side * (width / 2 + 1.6), 0, -length / 2 + i * (length / (lanterns + 1)))
			local facing = p * CFrame.Angles(0, if side > 0 then math.pi / 2 else -math.pi / 2, 0)
			Props.lantern(m, facing, i % 2 == 0)
		end
	end
end

type Spot = { P: Vector3, R: number }

-- Is (x,z) free for decoration (not on roads, plaza, plots, buildings)?
local function isFree(p: Vector3, occupied: { Spot }, radius: number): boolean
	if (Vector3.new(p.X, 0, p.Z) - WorldLayout.Plaza.Center).Magnitude < WorldLayout.Plaza.Radius + radius + 4 then
		return false
	end
	for _, plot in WorldLayout.Plots do
		local d = p - plot.Center
		if math.abs(d.X) < 28 + radius and math.abs(d.Z) < 28 + radius then
			return false
		end
	end
	for _, road in WorldLayout.Roads do
		local a, b, width = road.From, road.To, road.Width
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local closest = a + ab * t
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(closest.X, 0, closest.Z)).Magnitude < width / 2 + radius + 2 then
			return false
		end
	end
	for _, spot in WorldLayout.OutcropSpots do
		if (p - spot).Magnitude < radius + 7 then
			return false
		end
	end
	for _, o in occupied do
		if (p - o.P).Magnitude < radius + o.R then
			return false
		end
	end
	return true
end

local function scatter(parent: Instance, rng: Rng.Rng)
	local m = model("Nature", parent)
	local occupied: { Spot } = {
		{ P = WorldLayout.Landmarks.GreatForge.Position, R = 30 },
		{ P = WorldLayout.Landmarks.TradingPost.Position + Vector3.new(-6, 0, 0), R = 16 },
		{ P = WorldLayout.Landmarks.ToolSmithy.Position + Vector3.new(6, 0, 0), R = 16 },
		{ P = WorldLayout.Landmarks.EmberChest.Position, R = 6 },
		{ P = WorldLayout.Landmarks.GuildBoard.Position, R = 6 },
		{ P = WorldLayout.SpawnPoint, R = 8 },
	}
	local island = WorldLayout.Island
	local trees = 0
	local tries = 0
	while trees < 85 and tries < 3000 do
		tries += 1
		local p = Vector3.new(rng:range(island.Min.X + 8, island.Max.X - 8), 0, rng:range(-116, island.Max.Z - 8))
		if isFree(p, occupied, 5) then
			table.insert(occupied, { P = p, R = 5 })
			if rng:chance(0.3) then
				Props.pine(m, CFrame.new(p), rng)
			else
				Props.tree(m, CFrame.new(p), rng)
			end
			trees += 1
		end
	end
	-- boulders and bushes
	local rocks = 0
	tries = 0
	while rocks < 60 and tries < 2000 do
		tries += 1
		local p = Vector3.new(rng:range(island.Min.X + 6, island.Max.X - 6), 0, rng:range(-116, island.Max.Z - 6))
		if isFree(p, occupied, 3) then
			table.insert(occupied, { P = p, R = 3 })
			if rng:chance(0.55) then
				Geo.rock(m, CFrame.new(p), Vector3.new(rng:range(2.5, 6), rng:range(2, 4.5), rng:range(2.5, 6)), Palette.Stone, rng, nil, solid())
			else
				local s = rng:range(2.2, 3.6)
				Geo.block(m, CFrame.new(p + Vector3.new(0, s * 0.35, 0)) * Geo.randomTilt(rng, 0.3), Vector3.new(s * 1.3, s, s * 1.2), Geo.vary(Palette.LeafDeep, rng, 0.06), nil, decor())
			end
			rocks += 1
		end
	end
	-- flowers: tiny bright blocks in clusters
	for _ = 1, 60 do
		local p = Vector3.new(rng:range(island.Min.X + 6, island.Max.X - 6), 0, rng:range(-110, island.Max.Z - 6))
		if isFree(p, occupied, 1) then
			local color = rng:pick({ Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 120, 120), Color3.fromRGB(250, 250, 250), Color3.fromRGB(190, 140, 255) })
			for _ = 1, 4 do
				local q = p + Vector3.new(rng:range(-1.5, 1.5), 0.35, rng:range(-1.5, 1.5))
				Geo.block(m, CFrame.new(q) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(0.45, 0.45, 0.45), color, nil, decor({ CastShadow = false, CanCollide = false }))
			end
		end
	end
end

function Town.build(map: Model, rng: Rng.Rng)
	local town = model("Emberfall", map)
	roads(town, rng)
	plaza(town, rng)
	greatForge(town, rng)
	tradingPost(town, rng)
	toolSmithy(town, rng)
	emberChest(town)
	guildBoard(town)
	scatter(town, rng)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(WorldLayout.SpawnPoint + Vector3.new(0, 0.25, 0))
	spawn.Color = Palette.PlazaDark
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Transparency = 0
	spawn.Parent = town
	-- no default decal: keep the stylized look
	return town
end

return Town
