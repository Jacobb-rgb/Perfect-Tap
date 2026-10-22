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
local Wilds = require(script.Parent.Lobby.Flora.Wilds)
local Stream = require(script.Parent.Lobby.Flora.Stream)
local Ambience = require(script.Parent.Lobby.Ambience)
local Life = require(script.Parent.Lobby.Plaza.Life)
local StreetLamps = require(script.Parent.Lobby.Plaza.StreetLamps)

local MineFloors = require(Shared.Config.MineFloors)
local Mine = script.Parent.Mine

local WorldBuilder = {}

WorldBuilder.Version = 50 -- 50: SKY HAVEN's parkour stones are little floating islets (grass, dirt, a hanging rock tip, a touch on top) and its spire has moss on the ledges, vines, mossy outcrops, bushes and a crystal crown (owner); 49: six more floating islands round the map (crystal, blossom, windmill, lava, twin islets, jungle) and SKY HAVEN (a parkour spire off the south-east coast up to a village island with the premium SKY EGG on its podium and a lit path to it), reached through a gate in the island's invisible south wall (WorldLayout.SouthGate: a walled corridor onto the plank bridge, an outer wall along the rim's sea edge); 48: the sea bay behind the Vault filled with island (owner): one straight south coast, the lawn behind the Vault with a koi pond, voxel trees, flower beds and a butterfly (Meadow.SouthLawn); 47: the EGGS rotunda replaces the CAPSULES stall (owner's concept: round gold pillars, EGGS sign with crowns, a giant crowned egg with orbit rings and a beam on the roof, the three eggs on podiums); 46: the HALL OF FAME gets a fifth board, LEVEL (owner 2026-10-21: player levels; boards 3.78 wide in the same hall); 45: bigger plots (owner): a 16x16 build grid in place of 12x12, the plots and their yards 16 studs further out, the plot columns 64 studs longer to the south, the island wider and longer to match, the south band (MINE hill, stream and pond, portals, hamlet lane) moved south with them; 44: the wilds (owner, nature chat): groups of pebbles, mossy rocks, tall grass, flowers, berry and blossom bushes, ferns, stumps, logs and mushrooms on the free lawns and the mountains' green tops, and five secrets (a lost miner's camp, a buried chest, a fairy ring, a fossil, a Kaldrum rune stone) (merged onto main 43); 43: every road and path a dark neon walkway like the forge paths (owner), the owner's street lamp picture built along every road (Tall on the plot and rim roads, Medium on the forge paths, spurs and the lane to the next area, Small on the scanner path and the MINE lane; every other one lit) in place of the road lanterns, belt posts and west street posts, gaps in the town belt round them, the road fences behind them (merged onto main 42); 42: the THE FORGE board on the mountain works removed (another game's title, owner); 41: THE GREAT FORGE is an open passage under its roof, board and banners (owner), the bridge garden runs under it to the quarry: a pond with a bridge, a stone path with bamboo, lanterns and two little ponds; stone pillars and wide even side roofs, crystals, jungle trees, fences along the forge roads, two stone kings at the steps (merged onto main 40); 40: the giant HALL OF FAME (four tall boards side by side, the champions' pedestals; moved 5 studs forward and turned to the plaza); 39: the Stormglass Rift trimmed to 11 PointLights (phones; neon carries the rest); 38: the Stormglass Rift (floor 5, gate 8) under the Sunken Palace, the Heartstone Core now floor 6; 37: the plot pieces in the machines' style A "Soft" (owner: ano; SoftKit): soft walls and round posts, the Ore Pen, the podiums and the train stop (the Foundry building and its chute receiver are built at server start); 36: the gallery guns on display lean to their ore color (no near-black Ore Glow bodies in the dark hall); 35: the blaster gallery's guns in the Kenney shapes (owner: ano) and the Vault cases of LV 4/6/7 follow rarity (Emberite, Sapphire, Amethyst); 34: the mine floors merged with main v33 (lobby night work, loading screen); 31: merged with main v27 (perf pass 1); 30: merged with main v26 (BeamIgnore tags) and the mine floors' solid decorations tagged BeamIgnore too; 29: merged with steps 6-7; 28 (mine): mine ambience spots (tagged Attachments on parts the five mine floors already have: no new parts); 27: mine floors 1-3 trimmed to ~3,450 parts together (phones at the quarry rim); 26: mine floors 4-5 trimmed under 2,400 parts each; 25: the five mine floor areas replace the quarry pit and the caves (MineFloors.Placement); main 33: the timber sheds in the town belts removed (owner); 32: main's perf pass 1 merged into the review branch (main's 27: perf pass 1 (plots: opaque holo-rings, no shadows from small trim, brick courses on the side walls; SHOP/UPGRADES share their bay pieces behind the walls; SPIN & WIN without hidden neon; the west-sea ships lie still); 26: the Blaster Vault's interior decorations carry the BeamIgnore tag (the mining beam's line of sight)); 31: main's steps 6-7 map merged into the review branch (main's 25: steps 6-7: the SPIN & WIN disc shows the daily wheel's 8 real prizes clockwise (WheelConfig.Segments), its crown on the frame, and an artifact museum in every plot's yard (ArtifactService, MuseumBuilder)); 30: lobby ambience spots (tagged Attachments on the waterfalls, the ponds, the stream, the forge and the spawn: no new parts); 29: the meadow ponds come back (a finer search, a small size where the drawn one finds no room, kept off the stream's pond and behind the forge); 28: phone trims (fewer grass tufts, lighter flower beds, 2-part fence lanterns, 4-part plaza lanterns); 27: the meadow keeps off the ore outcrops (no pond over an ore rock); 26: the horizon fleet lies still (no Spin bob: phone performance); 25: plaza life (miners, hanging lanterns and props at the stall fronts), the stream with its humped bridge and the waterfall off the south rim (the rim notch) (+ the concept pass: lanterns on the fences, bushes and rocks on the lawns, autumn jungle crowns, no spire shadows); 24: the Blaster Vault's crystals opaque with glowing tips (phones: 102 fewer see-through parts); 23: the 36 ores of the owner's ore picture (new looks in the rocks and on display); 22: the blaster gallery in THE GREAT FORGE's hall (LV 1-10 + LV 11 coming soon); 21: the Blaster Vault's display cases in the shop's case looks (BlasterData.Vault.Ores); 20: the town houses removed (owner), ponds and jungle trees on the lawns and the mountains; 19: the meadow (grass tufts, grass patches, flower beds, fences along the roads) and the paved main roads with kerbs and glowing studs; 18: the near west sea without its deep-water bands (no dark rectangle next to the horizon sea); 17: the horizon around the map (outer sea, Kenney kit isles and ships, ocean liner, more planets, constellations); 16: the owner's Candy mountains (Spectrum colours on the massif and the Land range, the voxel spire skyline); 15: the Blaster Vault at the end of the south road (giant statues, jungle trees), the MINE moved to the south-west corner, the MAP/WORKS/garden cottage hamlet in the south-east corner with its dirt lane, autumn trees off the MINE hill; 14: metal plot floors (slate band, light metal plate with tile seams, glowing strips); 13: lobby review merged with the railway; 12: lobby fix round 3 (THE GREAT FORGE board in front of the gable, glowing furnace hall, blue-grey slate plaza with thin neon tubes, planters and benches, a free-standing giant wheel, CAPSULES in the spawn view with a rounded glass pod, compact Hall of Fame by the forge porch, big open FOSSIL DIG, armored SHOP/UPGRADES, Tobin restyled, violet planet clear of the cliff, higher softer clouds, continuous town belts, plot hedges); 11: lobby fix round 2 (wider hero framing, koi pond + humped bridge, giant wheel with readable stairs, dark wet slate plaza, blue Tech neon, CAPSULES front-left with a wide glass jar, opaque two-tone clouds, taller Great Forge, FOSSIL DIG turned to the hero, west street); 10: lobby fix round 1 (wheel behind SHOP, front koi pond + humped bridge, town belts, slate plaza, restyled stalls, smaller planets); 9: wide SHOP/UPGRADES/SPIN & WIN, town re-sited, stall aprons; 8: visual upgrade (concept v2 stalls, plaza, planets, brick plot walls, town); 7: rocks keep off the train station, track and lifts; 6: lobby polish (plot lawns, massif, falls, clouds, signs); 4: base yards / 9: railway (quarry line, Mine Station, tunnel portals, coastal lines, Mine Lifts); 8: visual upgrade (concept v2 stalls, plaza, planets, brick plot walls, town); 7: rocks keep off the train station, track and lifts; 6: lobby polish (plot lawns, massif, falls, clouds, signs); 4: base yards

export type NodeSpawn = { Position: Vector3, Zone: string, Floor: number?, Deep: boolean?, Kind: string? }

-- The mine floor areas in floor order (src/server/World/Mine, contract in MineKit's header).
type FloorModule = { build: (Instance, CFrame, { Cutaway: boolean? }?) -> Model }
local FLOORS: { FloorModule } = {
	require(Mine.Floor1Quarry) :: any,
	require(Mine.Floor2Ember) :: any,
	require(Mine.Floor3Lagoon) :: any,
	require(Mine.Floor4Palace) :: any,
	require(Mine.Floor5Storm) :: any,
	require(Mine.Floor6Core) :: any,
}

-- Builds the mine floors into map.MineFloors and returns their rock spawns (the floors'
-- RockSpawns and GiantSpawn markers become NodeSpawns; the markers themselves are removed).
function WorldBuilder.buildMine(map: Instance): { NodeSpawn }
	local folder = Instance.new("Folder")
	folder.Name = "MineFloors"
	folder.Parent = map
	local spawns: { NodeSpawn } = {}
	for index, Floor in FLOORS do
		local floor = MineFloors.get(index)
		local model = Floor.build(folder, MineFloors.Placement[index], { Cutaway = false })
		local rockSpawns = model:FindFirstChild("RockSpawns")
		if rockSpawns then
			for _, p in rockSpawns:GetChildren() do
				if p:IsA("BasePart") then
					table.insert(
						spawns,
						{ Position = p.CFrame.Position, Zone = floor.ZoneId, Floor = index, Deep = p:GetAttribute("Deep") == true }
					)
				end
			end
			rockSpawns:Destroy()
		end
		local giant = model:FindFirstChild("GiantSpawn")
		if giant and giant:IsA("BasePart") then
			table.insert(spawns, { Position = giant.CFrame.Position, Zone = floor.ZoneId, Floor = index, Kind = "Giant" })
			giant:Destroy()
		end
	end
	return spawns
end

-- Deterministic node spots for every zone (rejection sampling with spacing).
function WorldBuilder.generateNodeSpawns(): { NodeSpawn }
	local rng = Rng.new(WorldLayout.Seed * 7 + 11)
	local spawns: { NodeSpawn } = {}
	-- the town's starter outcrops grow small Greystone rocks (mine floor 1's rocks)
	for _, spot in WorldLayout.OutcropSpots do
		table.insert(spawns, { Position = spot, Zone = "Outcrops", Floor = 1, Kind = "Small" })
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
	for _, s in WorldBuilder.buildMine(map) do
		table.insert(spawns, s)
	end
	-- the stream and the plaza life take their ground first, then the meadow
	-- fills what is left: grass, flowers, fences and trees where nothing stands
	Stream.build(map, Rng.new(WorldLayout.Seed + 5))
	Life.build(map, Rng.new(WorldLayout.Seed + 6))
	StreetLamps.build(map) -- after everything that stands by the roads, before the meadow fills the rest
	Meadow.build(map, Rng.new(WorldLayout.Seed + 4))
	-- then the wilds (owner, nature chat): groups of pebbles, tall grass, flowers,
	-- bushes, stumps and mushrooms on the lawns and the mountains' green tops,
	-- and five hidden secrets near the island's edges
	Wilds.build(map, Rng.new(WorldLayout.Seed + 7))
	-- the ambience spots ride on parts that are there now (waterfalls, ponds, the forge)
	Ambience.build(map)

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
		if s.Floor then
			marker:SetAttribute("Floor", s.Floor)
			marker:SetAttribute("Deep", s.Deep == true)
		end
		if s.Kind then
			marker:SetAttribute("Kind", s.Kind)
		end
		marker:AddTag("NodeSpawn")
		marker.Parent = markers
	end

	map.Parent = parent
	return map
end

return WorldBuilder
