--[[
	MineKit: shared pieces of the mine floor areas (docs/plans/MINE_FLOORS_PLAN.md).
	Every floor builder (Floor1Quarry ... Floor5Core) uses these so the parts that
	work the same on every floor also look the same:

	  MineKit.elevator(parent, cf, floorIndex)   the elevator stop (bought once, goes
	                                             to every unlocked floor); cf = floor
	                                             center of the stop, front = LookVector
	  MineKit.oreLift(parent, position, id)      the train's Mine Lift (Railway.buildLift)
	  MineKit.gate(parent, cf, width, level)     an arch with "BLASTER LV N+" over a way in
	  MineKit.spawns(model)                      the RockSpawns folder + spawn helpers
	  MineKit.crystals(parent, root, ...)        decoration crystal clusters that match
	                                             the rocks (RockBuilder.decorCluster)
	  MineKit.wall(parent, from, to, height, colors, rng, opts)
	                                             a jagged rock wall of stacked shards
	  MineKit.stalactites(parent, center, size, colors, rng, count)

	Contract of a floor builder (Floor<N><Name>.luau):
	  Floor.Index, Floor.Size (footprint X, height, Z)
	  Floor.build(parent, origin, opts?) -> Model "MineFloor<N>"
	    origin  ground center of the area; +Z (LookVector of origin is -Z) is the
	            FRONT where players arrive, -Z the BACK ("deep": better rocks)
	    opts.Cutaway  true for preview pictures: no front wall / no ceiling over
	            the front half, so a camera at +Z sees in
	  The model holds: Folder "RockSpawns" (parts named "RockSpawn", attribute Deep),
	  a part "GiantSpawn", a part "Entrance" (where players arrive), the elevator
	  stop, the ore lift and a blaster gate. Budgets in the game build: <= 2500
	  parts without rocks (floors 1-3: <= 1800), <= 24 PointLights.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local RockBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("RockBuilder"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local Railway = require(World:WaitForChild("Railway"))

local MineKit = {}

MineKit.PartBudget = 2500 -- every floor in the game build (floors 4-5 stream on their own, far from the town)
MineKit.NearPartBudget = 1800 -- floors 1-3 stream in with the town: keep them light for phones
MineKit.LightBudget = 24

local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local DECOR = { CanTouch = false, CanQuery = false, CanCollide = false }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local STEEL = Color3.fromRGB(118, 130, 186)
local STEEL_DARK = Color3.fromRGB(62, 68, 102)
local HAZARD = Color3.fromRGB(255, 196, 52)
local SIGN_GLOW = Color3.fromRGB(90, 220, 255)

---------------------------------------------------------------- spawns

export type Spawns = {
	Folder: Folder,
	add: (cf: CFrame, deep: boolean?) -> BasePart,
}

-- Creates the RockSpawns folder in `model`; spawns.add(cf, deep) adds one spawn point.
function MineKit.spawns(model: Model): Spawns
	local folder = Instance.new("Folder")
	folder.Name = "RockSpawns"
	folder.Parent = model
	local self = {} :: Spawns
	self.Folder = folder
	self.add = function(cf: CFrame, deep: boolean?): BasePart
		local p = Geo.block(folder, CFrame.new(cf.Position), Vector3.new(1, 1, 1), Color3.new(1, 1, 1), nil, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		p.Name = "RockSpawn"
		p:SetAttribute("Deep", deep == true)
		return p
	end
	return self
end

-- An invisible marker part (Entrance, GiantSpawn, ...).
function MineKit.marker(parent: Instance, name: string, cf: CFrame): BasePart
	local p = Geo.block(parent, cf, Vector3.new(1, 1, 1), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	p.Name = name
	return p
end

---------------------------------------------------------------- crystals

-- A decoration crystal cluster that matches the rocks; root = bottom, up = growth direction.
-- look: "Matte" | "Tipped" | "Shell" | "Glow".
function MineKit.crystals(parent: Instance, root: CFrame, count: number, height: number, look: string, colors: { Color3 }, seed: number | string): Model
	return RockBuilder.decorCluster(parent, root, count, height, look, colors, seed)
end

---------------------------------------------------------------- rock walls

export type WallOpts = { Depth: number?, Lean: number?, Glow: Color3?, Step: number? }

--[[
	A jagged rock wall from `from` to `to` (ground points) of tall stacked shards
	in `colors` (Mid, Light, Dark), facing the side `face` (unit vector toward the
	floor's open space). opts.Glow adds thin glowing veins across the wall;
	opts.Step is the shard spacing (default 5 studs; wider = fewer parts, for rock
	high up or far away).
]]
function MineKit.wall(parent: Instance, from: Vector3, to: Vector3, height: number, face: Vector3, colors: { Color3 }, rng: Rng.Rng, opts: WallOpts?): Model
	local o: WallOpts = opts or {}
	local m = Instance.new("Model")
	m.Name = "RockWall"
	m.Parent = parent
	local along = to - from
	local length = along.Magnitude
	local dir = along.Unit
	local depth = o.Depth or 6
	local n = math.max(2, math.floor(length / (o.Step or 5)))
	local step = length / n
	for i = 0, n - 1 do
		local p = from + dir * (step * (i + 0.5)) - face * (depth * 0.5)
		local h = height * rng:range(0.72, 1.0)
		local w = step * rng:range(1.05, 1.3)
		local cf = CFrame.lookAt(p, p + face) * CFrame.Angles(rng:range(-0.05, 0.05), rng:range(-0.12, 0.12), rng:range(-0.06, 0.06))
		Geo.block(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, depth), Geo.vary(colors[1], rng, 0.05), nil, SOLID)
		-- a facet shard in front and a lighter ledge make the wall read as broken rock
		local fh = h * rng:range(0.35, 0.7)
		Geo.block(m, cf * CFrame.new(rng:range(-w * 0.25, w * 0.25), fh / 2, -depth * 0.5 - 0.4) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(w * 0.45, fh, w * 0.45), Geo.vary(colors[3], rng, 0.05), nil, SOLID)
		if rng:chance(0.6) then
			Geo.block(m, cf * CFrame.new(0, h * rng:range(0.3, 0.7), -depth * 0.5 - 0.2), Vector3.new(w * 0.9, 0.5, 1.2), Geo.vary(colors[2], rng, 0.05), nil, DECOR)
		end
		if o.Glow and rng:chance(0.5) then
			Geo.block(m, cf * CFrame.new(0, h * rng:range(0.2, 0.8), -depth * 0.5 - 0.05) * CFrame.Angles(0, 0, rng:range(-0.9, 0.9)), Vector3.new(w * rng:range(0.6, 1.0), 0.22, 0.12), o.Glow, NEON, GLOW)
		end
	end
	return m
end

-- Hanging stalactites (wedge pairs) under a ceiling at `center` (its underside), spread over `size` (X, Z).
function MineKit.stalactites(parent: Instance, center: Vector3, size: Vector2, colors: { Color3 }, rng: Rng.Rng, count: number): Model
	local m = Instance.new("Model")
	m.Name = "Stalactites"
	m.Parent = parent
	for _ = 1, count do
		local p = center + Vector3.new(rng:range(-0.5, 0.5) * size.X, 0, rng:range(-0.5, 0.5) * size.Y)
		local h = rng:range(2, 6)
		local w = rng:range(0.8, 1.8)
		local cf = CFrame.new(p) * CFrame.Angles(math.pi, rng:range(0, math.pi), 0) * CFrame.new(0, h / 2, 0)
		Geo.wedge(m, cf * CFrame.new(0, 0, -w / 4), Vector3.new(w, h, w / 2), Geo.vary(colors[1], rng, 0.05), nil, DECOR)
		Geo.wedge(m, cf * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, h, w / 2), Geo.vary(colors[3], rng, 0.05), nil, DECOR)
	end
	return m
end

---------------------------------------------------------------- the elevator stop

--[[
	The elevator stop: a steel platform with hazard edges, four girder posts up to
	a machine head with a pulley wheel and cables, an open cage on the platform,
	a neon "ELEVATOR" sign and a "FLOOR N" plate, and a call panel with a glowing
	button (the prompt goes on its "PromptPoint" attachment). About 60 parts, one
	PointLight. Tagged "MineElevator", attribute Floor.
]]
function MineKit.elevator(parent: Instance, cf: CFrame, floorIndex: number): Model
	local m = Instance.new("Model")
	m.Name = "Elevator"
	m.Parent = parent
	m:AddTag("MineElevator")
	m:SetAttribute("Floor", floorIndex)
	local half = 4.2
	local height = 16
	local plate = Geo.block(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(half * 2 + 1.2, 0.6, half * 2 + 1.2), STEEL_DARK, METAL, SOLID)
	plate.Name = "Base"
	-- hazard stripes along the front edge
	for i = -3, 3 do
		local color = if i % 2 == 0 then HAZARD else Color3.fromRGB(30, 30, 34)
		Geo.block(m, cf * CFrame.new(i * 1.3, 0.62, -half - 0.35), Vector3.new(1.3, 0.06, 0.5), color, nil, GLOW)
	end
	-- girder posts with cross braces
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local post = cf * CFrame.new(sx * half, height / 2 + 0.6, sz * half)
			Geo.block(m, post, Vector3.new(0.7, height, 0.7), STEEL, METAL, SOLID)
			Geo.block(m, post * CFrame.new(-sx * 0.3, 0, 0), Vector3.new(0.18, height, 1.0), STEEL_DARK, METAL, DECOR)
		end
		for k = 1, 3 do
			local y = 0.6 + k * (height / 4)
			Geo.block(m, cf * CFrame.new(sx * half, y, 0) * CFrame.Angles(math.rad(if k % 2 == 0 then 38 else -38), 0, 0), Vector3.new(0.25, 0.3, half * 2.5), STEEL_DARK, METAL, DECOR)
		end
	end
	for _, sz in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(0, height + 0.6, sz * half), Vector3.new(half * 2 + 0.7, 0.7, 0.7), STEEL, METAL, SOLID)
	end
	-- machine head with the pulley wheel and cables
	Geo.block(m, cf * CFrame.new(0, height + 1.6, 0), Vector3.new(half * 1.4, 1.4, half * 1.2), STEEL_DARK, METAL, DECOR)
	local wheel = Geo.block(m, cf * CFrame.new(0, height + 2.8, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.5, 3, 3), HAZARD, METAL, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	wheel.Name = "Pulley"
	for _, sx in { -0.6, 0.6 } do
		Geo.block(m, cf * CFrame.new(sx, height * 0.5 + 3.6, 0), Vector3.new(0.14, height - 4, 0.14), Color3.fromRGB(26, 26, 30), METAL, DECOR)
	end
	-- the cage: a floor, corner bars, rails and a roof
	local cage = cf * CFrame.new(0, 0.6, 0.2)
	Geo.block(m, cage * CFrame.new(0, 0.15, 0), Vector3.new(6, 0.3, 6), Color3.fromRGB(96, 102, 116), METAL, SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Geo.block(m, cage * CFrame.new(sx * 2.85, 3.6, sz * 2.85), Vector3.new(0.3, 7, 0.3), HAZARD, METAL, DECOR)
		end
		Geo.block(m, cage * CFrame.new(sx * 2.85, 2.2, 0), Vector3.new(0.18, 0.18, 5.7), HAZARD, METAL, DECOR)
		Geo.block(m, cage * CFrame.new(sx * 2.85, 1.2, 0), Vector3.new(0.18, 0.18, 5.7), HAZARD, METAL, DECOR)
	end
	Geo.block(m, cage * CFrame.new(0, 2.2, 2.85), Vector3.new(5.7, 0.18, 0.18), HAZARD, METAL, DECOR)
	Geo.block(m, cage * CFrame.new(0, 7.2, 0), Vector3.new(6.2, 0.4, 6.2), STEEL, METAL, DECOR)
	local lamp = Geo.block(m, cage * CFrame.new(0, 6.9, 0), Vector3.new(2.4, 0.2, 2.4), Color3.fromRGB(255, 240, 210), NEON, GLOW)
	lamp.Name = "CageLamp"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = lamp
	-- signs: ELEVATOR over the front, FLOOR N on the head
	Style.sign(m, cf * CFrame.new(0, 9.4, -half - 0.6), "ELEVATOR", 7.5, 1.6, { Kind = "Glow", DoubleSided = true })
	Style.sign(m, cf * CFrame.new(0, height + 1.6, -half * 0.6 - 0.05), "FLOOR " .. floorIndex, 4.8, 1.1, { Kind = "Stone", Depth = 0.3 })
	-- call panel with the glowing button and the prompt point
	local panel = Geo.block(m, cf * CFrame.new(half + 1.4, 2.2, -half + 0.6), Vector3.new(1.2, 3.2, 0.6), STEEL_DARK, METAL, SOLID)
	panel.Name = "CallPanel"
	local button = Geo.block(m, panel.CFrame * CFrame.new(0, 0.6, -0.34), Vector3.new(0.6, 0.6, 0.12), SIGN_GLOW, NEON, GLOW)
	button.Name = "CallButton"
	local prompt = Instance.new("Attachment")
	prompt.Name = "PromptPoint"
	prompt.Position = Vector3.new(0, 0, -1.2)
	prompt.Parent = panel
	m.PrimaryPart = plate
	return m
end

---------------------------------------------------------------- ore lift and gate

-- In the game the Mine Lifts are built by Railway from TrainConfig.Lifts (their train hooks live
-- under Map.Railway); floor builders only mark the spot. Preview scenes set this to true so
-- the floor pictures show the lift.
MineKit.PreviewLifts = false

-- The train's Mine Lift at `position` on the floor (it faces the floor's middle along X), or in
-- the game an "OreLiftSpot" marker model (attribute LiftId) where TrainConfig puts the lift.
function MineKit.oreLift(parent: Instance, position: Vector3, id: string): Model
	if MineKit.PreviewLifts then
		return Railway.buildLift(parent, { Id = id, Position = position, Size = Vector3.new(6, 5, 6) })
	end
	local m = Instance.new("Model")
	m.Name = "OreLiftSpot"
	m:SetAttribute("LiftId", id)
	m.Parent = parent
	local spot = MineKit.marker(m, "Spot", CFrame.new(position + Vector3.new(0, 0.5, 0)))
	m.PrimaryPart = spot
	return m
end

-- An arch over a way in with "BLASTER LV N+" on it; cf = ground center, front = LookVector.
function MineKit.gate(parent: Instance, cf: CFrame, width: number, level: number, colors: { Color3 }): Model
	local m = Instance.new("Model")
	m.Name = "BlasterGate"
	m.Parent = parent
	m:SetAttribute("MinBlaster", level)
	local h = 11
	for _, sx in { -1, 1 } do
		Geo.block(m, cf * CFrame.new(sx * (width / 2 + 0.9), h / 2, 0), Vector3.new(1.8, h, 1.8), colors[1], nil, SOLID)
		Geo.block(m, cf * CFrame.new(sx * (width / 2 + 0.9), h + 0.3, 0), Vector3.new(2.3, 0.6, 2.3), colors[2], nil, DECOR)
	end
	Geo.block(m, cf * CFrame.new(0, h + 1.1, 0), Vector3.new(width + 4.2, 1.6, 2), colors[3], nil, SOLID)
	Style.sign(m, cf * CFrame.new(0, h + 1.1, -1.05), "BLASTER LV " .. level .. "+", width * 0.8, 1.2, { Kind = "Glow", DoubleSided = true, Depth = 0.25 })
	return m
end

return MineKit
