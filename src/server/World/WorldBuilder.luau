--[[
	Builds the whole Terra map into Workspace.Map.

	The same code runs in two places:
	  1. tools/lune/bake.luau bakes the map into build/TerraForge.rbxl, so you
	     can see and edit it in Studio.
	  2. WorldService at runtime, if Workspace has no Map (e.g. an empty place
	     synced with Rojo) or the baked map is from an older builder version.

	To keep a hand-edited map, give Workspace.Map the attribute KeepMap = true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Land = require(script.Parent.Land)
local Town = require(script.Parent.Town)
local PlotBuilder = require(script.Parent.PlotBuilder)

local WorldBuilder = {}

WorldBuilder.Version = 1

export type NodeSpawn = { Position: Vector3, Zone: string }

-- Deterministic node spots for every zone (rejection sampling with spacing).
function WorldBuilder.generateNodeSpawns(): { NodeSpawn }
	local rng = Rng.new(WorldLayout.Seed * 7 + 11)
	local spawns: { NodeSpawn } = {}
	for _, spot in WorldLayout.OutcropSpots do
		table.insert(spawns, { Position = spot, Zone = "Outcrops" })
	end
	for _, zone in WorldLayout.Zones do
		if zone.NodeCount > 0 then
			local placed = 0
			local tries = 0
			local margin = 9
			local minX, maxX = zone.Min.X + margin, zone.Max.X - margin
			local minZ, maxZ = zone.Min.Z + margin, zone.Max.Z - margin
			while placed < zone.NodeCount and tries < 4000 do
				tries += 1
				local p = Vector3.new(rng:range(minX, maxX), zone.FloorY, rng:range(minZ, maxZ))
				local ok = not WorldLayout.isKeepOut(p, 5)
				if ok then
					for _, other in spawns do
						if (other.Position - p).Magnitude < 12 then
							ok = false
							break
						end
					end
				end
				if ok then
					table.insert(spawns, { Position = p, Zone = zone.Id })
					placed += 1
				end
			end
		end
	end
	return spawns
end

function WorldBuilder.build(parent: Instance): Model
	local map = Instance.new("Model")
	map.Name = "Map"
	map:SetAttribute("BuilderVersion", WorldBuilder.Version)
	map:SetAttribute("Seed", WorldLayout.Seed)

	local spawns = WorldBuilder.generateNodeSpawns()
	local avoid = {}
	for _, s in spawns do
		table.insert(avoid, s.Position)
	end

	Land.build(map, Rng.new(WorldLayout.Seed + 1), avoid)
	Town.build(map, Rng.new(WorldLayout.Seed + 2))
	PlotBuilder.build(map, Rng.new(WorldLayout.Seed + 3))

	-- Invisible markers. Move/duplicate them in Studio to change where ore grows.
	local markers = Instance.new("Folder")
	markers.Name = "NodeSpawns"
	markers.Parent = map
	for index, s in spawns do
		local marker = Instance.new("Part")
		marker.Name = "NodeSpawn"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.CastShadow = false
		marker.Transparency = 1
		marker.Size = Vector3.new(2, 2, 2)
		marker.CFrame = CFrame.new(s.Position + Vector3.new(0, 1, 0))
		marker:SetAttribute("Zone", s.Zone)
		marker:SetAttribute("SpawnIndex", index)
		marker:AddTag("NodeSpawn")
		marker.Parent = markers
	end

	map.Parent = parent
	return map
end

return WorldBuilder
