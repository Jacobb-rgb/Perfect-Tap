return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	T.test("plots do not overlap and fit on the island", function()
		local size = GameConfig.PlotCells * GameConfig.CellSize
		T.eq(#WorldLayout.Plots, GameConfig.MaxPlayers, "one plot per player")
		for i, a in WorldLayout.Plots do
			T.truthy(math.abs(a.Center.X) + size / 2 < WorldLayout.Island.Max.X, "plot " .. i .. " inside island")
			for j, b in WorldLayout.Plots do
				if i < j then
					local d = a.Center - b.Center
					T.truthy(math.abs(d.X) >= size or math.abs(d.Z) >= size, "plots " .. i .. "/" .. j .. " overlap")
				end
			end
		end
	end)

	T.test("plot columns, yards and rails follow the plot grid and stay in the zones", function()
		local grid = WorldLayout.PlotGrid
		local island = WorldLayout.Island
		local pad = 2 * grid.Half + 2 -- the pad (walls at +-(Half + 1))
		for i, a in WorldLayout.Plots do
			-- the pad's road-side front and its column's ends
			T.eq(math.abs(a.Center.X) - pad / 2, grid.FrontX, `plot {i} front`)
			T.truthy(a.Center.Z - pad / 2 >= grid.NorthZ and a.Center.Z + pad / 2 <= grid.SouthZ, `plot {i} inside its column`)
			-- the alley between neighbouring pads stays walkable
			for j, b in WorldLayout.Plots do
				if i < j and a.Center.X == b.Center.X then
					T.truthy(math.abs(a.Center.Z - b.Center.Z) - pad >= 6, `plots {i}/{j}: alley of 6 studs`)
				end
			end
			-- every corner of the yard and its pieces, and the rail point, lie on the island in a
			-- surface zone (music, the HUD zone name, teleports and lighting need one)
			local cf = WorldLayout.plotCFrame(a)
			local rects = BaseLayout.pieces()
			rects.Yard = BaseLayout.Yard
			local points = { Rail = Vector3.new(0, 0, BaseLayout.RailZ) }
			for name, rect in rects do
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local x = rect.Center.X + sx * rect.Size.X / 2
						local z = rect.Center.Z + sz * rect.Size.Z / 2
						points[`{name} ({x}, {z})`] = Vector3.new(x, 0, z)
					end
				end
			end
			for name, localPos in points do
				local world = cf:PointToWorldSpace(localPos)
				local label = `plot {i} {name}`
				T.truthy(math.abs(world.X) < island.Max.X and world.Z > island.Min.Z and world.Z < island.Max.Z, label .. " on the island")
				local zone = WorldLayout.zoneAt(world + Vector3.new(0, 3, 0))
				T.truthy(zone and zone.Lighting == "Surface", label .. " in a surface zone")
			end
		end
	end)

	T.test("node spawns are inside their zone, spaced, and off the paths", function()
		local spawns = WorldBuilder.generateNodeSpawns()
		local perZone = {}
		for i, s in spawns do
			perZone[s.Zone] = (perZone[s.Zone] or 0) + 1
			if s.Zone ~= "Outcrops" then
				local zone = WorldLayout.ZoneById[s.Zone]
				T.truthy(WorldLayout.isInBox(s.Position, zone.Min, zone.Max), "spawn " .. i .. " in " .. s.Zone)
				T.falsy(WorldLayout.isKeepOut(s.Position), "spawn " .. i .. " in keep-out")
			end
			for j, o in spawns do
				if i < j then
					T.truthy((s.Position - o.Position).Magnitude >= 11.9, "spawns " .. i .. "/" .. j .. " too close")
				end
			end
		end
		for _, zone in WorldLayout.Zones do
			if zone.NodeCount > 0 then
				T.eq(perZone[zone.Id], zone.NodeCount, zone.Id .. " node count")
			end
		end
	end)

	T.test("world builds with all landmarks and a sane part count", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		for _, path in { "Land", "Emberfall", "Plots", "NodeSpawns" } do
			T.truthy(map:FindFirstChild(path), "map has " .. path)
		end
		local parts = 0
		-- the mine floors count too (each also within MineKit.PartBudget, tests/MineFloorAreas.spec.luau)
		local mine = map:FindFirstChild("MineFloors")
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		T.truthy(mine and #mine:GetChildren() == #MineFloors.List, "map has every mine floor")
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		-- mobile budget for static map parts (the same number tests/Lobby.spec.luau uses)
		T.lt(parts, LobbyLayout.Budget.MapParts + 1, "part count")
		local tags = {}
		for _, d in map:GetDescendants() do
			for _, tag in d:GetTags() do
				tags[tag] = (tags[tag] or 0) + 1
			end
		end
		for _, tag in { "SellBin", "SellCounter", "ShopCounter", "EmberChest", "GuildBoard", "Plot", "VipDoor", "NodeSpawn" } do
			T.truthy(tags[tag], "tag " .. tag)
		end
		T.eq(tags.Plot, #WorldLayout.Plots, "plot models")
	end)

	T.test("nothing from outside a cave intrudes into its walkable space", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local caves = WorldLayout.Caves
		-- (the Ember Caves and the Deep Hollow are the mine floor areas 2 and 3)
		local rooms = {
			{ name = "EmberCaves", box = caves.EmberCaves, model = "MineFloor2" },
			{ name = "DeepHollow", box = caves.DeepHollow, model = "MineFloor3" },
			{ name = "Grotto", box = caves.Grotto, model = "Grotto" },
		}
		-- (a cave's own model, or a Mine Lift standing in its cave: Railway)
		local function insideModel(part, name, own)
			local node = part.Parent
			while node do
				if node.Name == own or (node:HasTag("MineLift") and node:GetAttribute("LiftId") == name) then
					return true
				end
				node = node.Parent
			end
			return false
		end
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Ramp" and d.Name ~= "NodeSpawn" then
				local cf, size = d.CFrame, d.Size
				local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
				local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
				local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
				local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
				local p = cf.Position
				for _, room in rooms do
					if not insideModel(d, room.name, room.model) then
						local min = room.box.Min + roblox.Vector3.new(14, 2, 14)
						local max = room.box.Max - roblox.Vector3.new(14, 6, 14)
						local overlaps = p.X - hx < max.X
							and p.X + hx > min.X
							and p.Y - hy < max.Y
							and p.Y + hy > min.Y
							and p.Z - hz < max.Z
							and p.Z + hz > min.Z
						T.falsy(overlaps, d:GetFullName() .. " intrudes into " .. room.name)
					end
				end
			end
		end
	end)

	T.test("every ore can build a node and all 3 crack stages", function()
		for _, ore in OreData.List do
			local node = OreNodeBuilder.build(ore.Id, roblox.CFrame.new(0, 0, 0), 1)
			T.truthy(node.PrimaryPart, ore.Id .. " primary part")
			OreNodeBuilder.applyStage(node, 1, 1)
			local broken = OreNodeBuilder.applyStage(node, 2, 1)
			T.truthy(#broken >= 1, ore.Id .. " stage 2 breaks a piece off")
			T.eq(node:GetAttribute("Stage"), 2)
		end
	end)

	T.test("every zone can build rocks with 1-3 ores and all crack stages", function()
		for _, zone in WorldLayout.Zones do
			local ids = {}
			for oreId in zone.Ores do
				table.insert(ids, oreId)
			end
			table.sort(ids)
			for n = 1, math.min(3, #ids) do
				local oreIds = table.move(ids, 1, n, 1, {})
				for seed = 1, 5 do
					local label = `{zone.Id} {n} ores seed {seed}`
					local rock = OreNodeBuilder.buildRock(zone.Id, oreIds, roblox.CFrame.new(0, -12, 0), seed)
					T.truthy(rock.PrimaryPart, label .. " primary part")
					T.eq(rock:GetAttribute("Stage"), 0, label .. " stage 0")
					local before = #rock:GetChildren()
					OreNodeBuilder.applyStage(rock, 1, seed)
					T.eq(rock:GetAttribute("Stage"), 1, label .. " stage 1")
					local cracks = 0
					for _, child in rock:GetChildren() do
						if child.Name == "Crack" then
							cracks += 1
						end
					end
					T.truthy(cracks >= 2 and #rock:GetChildren() > before, label .. " stage 1 draws cracks")
					local broken = OreNodeBuilder.applyStage(rock, 2, seed)
					T.truthy(#broken >= 1, label .. " stage 2 breaks pieces off")
					for _, piece in broken do
						T.truthy(piece:IsA("BasePart") and piece.Parent == rock, label .. " broken pieces are rock parts")
						T.truthy(piece ~= rock.PrimaryPart, label .. " the main boulder stays")
					end
					T.eq(rock:GetAttribute("Stage"), 2, label .. " stage 2")
				end
			end
		end
	end)
end
