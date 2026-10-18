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
local Railway = require(script.Parent.Railway)
local Meadow = require(script.Parent.Lobby.Flora.Meadow)

local WorldBuilder = {}

WorldBuilder.Version = 22 -- 22: concept pass (lanterns on the fences, bushes and rocks on the lawns, autumn jungle crowns), the spires cast no shadows; 21: the Blaster Vault's display cases in the shop's case looks (BlasterData.Vault.Ores); 20: the town houses removed (owner), ponds and jungle trees on the lawns and the mountains; 19: the meadow (grass tufts, grass patches, flower beds, fences along the roads) and the paved main roads with kerbs and glowing studs; 18: the near west sea without its deep-water bands (no dark rectangle next to the horizon sea); 17: the horizon around the map (outer sea, Kenney kit isles and ships, ocean liner, more planets, constellations); 16: the owner's Candy mountains (Spectrum colours on the massif and the Land range, the voxel spire skyline); 15: the Blaster Vault at the end of the south road (giant statues, jungle trees), the MINE moved to the south-west corner, the MAP/WORKS/garden cottage hamlet in the south-east corner with its dirt lane, autumn trees off the MINE hill; 14: metal plot floors (slate band, light metal plate with tile seams, glowing strips); 13: lobby review merged with the railway; 12: lobby fix round 3 (THE GREAT FORGE board in front of the gable, glowing furnace hall, blue-grey slate plaza with thin neon tubes, planters and benches, a free-standing giant wheel, CAPSULES in the spawn view with a rounded glass pod, compact Hall of Fame by the forge porch, big open FOSSIL DIG, armored SHOP/UPGRADES, Tobin restyled, violet planet clear of the cliff, higher softer clouds, continuous town belts, plot hedges); 11: lobby fix round 2 (wider hero framing, koi pond + humped bridge, giant wheel with readable stairs, dark wet slate plaza, blue Tech neon, CAPSULES front-left with a wide glass jar, opaque two-tone clouds, taller Great Forge, FOSSIL DIG turned to the hero, west street); 10: lobby fix round 1 (wheel behind SHOP, front koi pond + humped bridge, town belts, slate plaza, restyled stalls, smaller planets); 9: wide SHOP/UPGRADES/SPIN & WIN, town re-sited, stall aprons; 8: visual upgrade (concept v2 stalls, plaza, planets, brick plot walls, town); 7: rocks keep off the train station, track and lifts; 6: lobby polish (plot lawns, massif, falls, clouds, signs); 4: base yards / 9: railway (quarry line, Mine Station, tunnel portals, coastal lines, Mine Lifts); 8: visual upgrade (concept v2 stalls, plaza, planets, brick plot walls, town); 7: rocks keep off the train station, track and lifts; 6: lobby polish (plot lawns, massif, falls, clouds, signs); 4: base yards

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
				local ok = not WorldLayout.isKeepOut(p, 5) and not PlotBuilder.isInYard(p, 6)
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
	Railway.build(map) -- after the plots: it replaces their placeholder tracks
	-- last: grass, flowers, fences and trees only where nothing else stands
	Meadow.build(map, Rng.new(WorldLayout.Seed + 4))

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
