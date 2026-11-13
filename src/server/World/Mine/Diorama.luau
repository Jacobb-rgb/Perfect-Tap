--!strict
--[[
	Mine floors from the owner's dioramas (made with Meshy, 2026-11-13; docs/plans/MESHY_MODELS_PLAN.md).
	The owner: "I made the six places much prettier, just scale them up and put them in the game".

	  Diorama.has(index)                        the floor is its diorama (MineFloors.usesDiorama)
	  Diorama.build(index, parent, origin, opts?) -> Model "MineFloor<N>" with MineKit's floor contract

	The diorama's tiles (Floor_<Id>_<NN>, looks only) are scaled evenly into the floor's footprint
	with its usual ground at local y = 0 and its centre at x = z = 0 (DioramaData, made by
	tools/meshy/floor_heights.py + floor_layout.py from the processed tiles). Players walk on
	invisible collision boxes made from the diorama's walk heights; the RockSpawns, the GiantSpawn,
	the Entrance, the elevator stop, the ore lift spot (a steel deck where the lift stands higher
	than the ground) and the blaster gate sit on flat ground found in the diorama. A few soft lights,
	the floor's ambience spots and, for the cave floors, a dark ceiling over the open diorama.
	The floor module adds its own extras (floor 6: the void enclosure and the VoidCatcher).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local MeshKit = require(Shared:WaitForChild("Builders"):WaitForChild("MeshKit"))
local MeshCatalog = require(Shared:WaitForChild("Config"):WaitForChild("MeshCatalog"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local MineAmbience = require(Shared:WaitForChild("Config"):WaitForChild("MineAmbience"))
local Mine = ServerScriptService:WaitForChild("Server"):WaitForChild("World"):WaitForChild("Mine")
local MineKit = require(Mine:WaitForChild("MineKit"))
local DioramaData = require(Mine:WaitForChild("DioramaData"))

local Diorama = {}

-- Per floor: a dark ceiling over the open diorama (the cave floors; the quarry is open sky and the
-- Heartstone Core has its own void enclosure), the light colour and strength.
-- (the dioramas' painted colours need near-white light to read; their caves are dark otherwise)
Diorama.Floors = {
	Quarry = { Ceiling = false, Light = Color3.fromRGB(255, 236, 214), Brightness = 0.8 },
	EmberCaves = { Ceiling = true, Light = Color3.fromRGB(255, 222, 196), Brightness = 1.4 },
	DeepHollow = { Ceiling = true, Light = Color3.fromRGB(220, 240, 255), Brightness = 1.8 },
	SunkenPalace = { Ceiling = true, Light = Color3.fromRGB(255, 232, 210), Brightness = 1.6 },
	StormglassRift = { Ceiling = true, Light = Color3.fromRGB(230, 236, 255), Brightness = 2.4 },
	HeartstoneCore = { Ceiling = false, Light = Color3.fromRGB(255, 226, 246), Brightness = 2.4 },
} :: { [string]: { Ceiling: boolean, Light: Color3, Brightness: number } }

Diorama.LightHeight = 14
Diorama.LightRange = 48
Diorama.BoxDepth = 6 -- collision boxes reach this far under their top (and below the lowest ground)

local GROUND = { CanTouch = false, CanQuery = true, CanCollide = true, CastShadow = false, Transparency = 1 }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local STEEL = Color3.fromRGB(70, 74, 88)

-- Whether floor `index` is built from its diorama (MineFloors.usesDiorama, and its layout exists).
function Diorama.has(index: number): boolean
	local floor = MineFloors.ByIndex[index]
	return floor ~= nil and DioramaData[floor.Id] ~= nil and MineFloors.usesDiorama(index)
end

-- The world CFrame of a local point (x, y, z) of the floor.
local function at(origin: CFrame, p: Vector3): CFrame
	return origin * CFrame.new(p)
end

function Diorama.build(index: number, parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	local floor = MineFloors.ByIndex[index]
	local data = DioramaData[floor.Id]
	local look = Diorama.Floors[floor.Id] or { Ceiling = false, Light = Color3.new(1, 1, 1), Brightness = 0.8 }
	local model = Instance.new("Model")
	model.Name = "MineFloor" .. index
	model:SetAttribute("Floor", index)
	model:SetAttribute("FloorId", floor.Id)
	model:SetAttribute("Diorama", true)
	model.Parent = parent

	-- the tiles: looks only (players stand on the boxes below)
	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Diorama"
	tilesFolder.Parent = model
	local s = data.Scale
	for _, name in MeshCatalog.Floors[floor.Id] do
		local entry = MeshCatalog.Assets[name]
		local c = entry.Center
		local pos = Vector3.new((c.X - data.CenterN.X) * s, (c.Y - data.GroundN) * s, (c.Z - data.CenterN.Y) * s)
		local tile = MeshKit.part(name, entry.Box * s, at(origin, pos), { CastShadow = true })
		if tile then
			tile.Parent = tilesFolder
		end
	end

	-- the ground: invisible boxes from the walk heights
	local groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = model
	local boxes = data.Boxes
	for i = 1, #boxes, 5 do
		local x0, z0, x1, z1, top = boxes[i], boxes[i + 1], boxes[i + 2], boxes[i + 3], boxes[i + 4]
		local bottom = math.min(top - Diorama.BoxDepth, data.Bottom - Diorama.BoxDepth)
		local box = Geo.block(groundFolder, at(origin, Vector3.new((x0 + x1) / 2, (top + bottom) / 2, (z0 + z1) / 2)), Vector3.new(x1 - x0, top - bottom, z1 - z0), floor.Palette.Ground, nil, GROUND)
		box.Name = "Ground"
	end

	-- the rock spawns and the Giant Crystal's spot
	local spawns = MineKit.spawns(model)
	for _, spawn in data.Spawns do
		spawns.add(at(origin, Vector3.new(spawn[1], spawn[2], spawn[3])), spawn[4] == true)
	end
	MineKit.marker(model, "GiantSpawn", at(origin, data.Giant))

	-- arrival: the entrance, the elevator stop facing the main path, the blaster gate over it
	local anchors = data.Anchors
	MineKit.marker(model, "Entrance", at(origin, anchors.Entrance))
	local e = anchors.Elevator
	MineKit.elevator(model, origin * CFrame.lookAt(e, Vector3.new(0, e.Y, e.Z)), index)
	local pal = floor.Palette
	MineKit.gate(model, at(origin, anchors.Gate), 12, floor.MinBlaster, { pal.Mid, pal.Light, pal.Dark })

	-- the ore lift (Railway builds it from TrainConfig at MineFloors.liftSpot): a steel deck under it
	-- where it stands higher than the diorama's ground
	local liftSpot = MineFloors.liftSpot(index)
	if liftSpot then
		local groundY = anchors.Lift and anchors.Lift.Y or 0
		if liftSpot.Y - groundY > 0.3 then
			local h = liftSpot.Y - groundY + 1
			local deck = Geo.block(model, at(origin, Vector3.new(liftSpot.X, liftSpot.Y - h / 2, liftSpot.Z)), Vector3.new(9, h, 9), STEEL, Enum.Material.DiamondPlate, SOLID)
			deck.Name = "LiftDeck"
		end
		MineKit.oreLift(model, origin:PointToWorldSpace(liftSpot), floor.Id)
	end

	-- soft lights over the walkable ground
	local lightFolder = Instance.new("Folder")
	lightFolder.Name = "Lights"
	lightFolder.Parent = model
	for _, p in data.Lights do
		local holder = Geo.block(lightFolder, at(origin, p + Vector3.new(0, Diorama.LightHeight, 0)), Vector3.new(0.4, 0.4, 0.4), look.Light, nil, GLOW)
		holder.Name = "Light"
		local light = Instance.new("PointLight")
		light.Color = look.Light
		light.Range = Diorama.LightRange
		light.Brightness = look.Brightness
		light.Shadows = false
		light.Parent = holder
	end

	-- a dark ceiling over the open diorama (the sky never shows in the caves)
	if look.Ceiling and not (opts and opts.Cutaway) then
		local width = data.Scale * 8.6
		local ceiling = Geo.block(model, at(origin, Vector3.new(0, data.Top + 3, 0)), Vector3.new(width, 2, width), floor.Palette.Dark, Enum.Material.Slate, {
			CanTouch = false,
			CanQuery = false,
			CanCollide = true,
			CastShadow = false,
		})
		ceiling.Name = "Ceiling"
	end

	-- ambience: the floor's kinds on ground boxes spread over the floor
	local kinds = MineAmbience.Floors[floor.Id] or {}
	if #kinds > 0 then
		for i = 1, math.min(6, #data.Lights) do
			MineKit.ambienceNear(groundFolder, kinds[(i - 1) % #kinds + 1], origin:PointToWorldSpace(data.Lights[i] + Vector3.new(0, 1, 0)))
		end
	end

	return model
end

return Diorama
