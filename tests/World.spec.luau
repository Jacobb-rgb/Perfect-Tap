return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
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
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		-- mobile budget for static map parts
		T.lt(parts, 6000, "part count")
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
		local rooms = {
			{ name = "EmberCaves", box = caves.EmberCaves },
			{ name = "DeepHollow", box = caves.DeepHollow },
			{ name = "Grotto", box = caves.Grotto },
		}
		local function insideModel(part, name)
			local node = part.Parent
			while node do
				if node.Name == name then
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
					if not insideModel(d, room.name) then
						local min = room.box.Min + roblox.Vector3.new(14, 2, 14)
						local max = room.box.Max - roblox.Vector3.new(14, 6, 14)
						local overlaps = p.X - hx < max.X and p.X + hx > min.X
							and p.Y - hy < max.Y and p.Y + hy > min.Y
							and p.Z - hz < max.Z and p.Z + hz > min.Z
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
end
