--[[
	Lobby layout and budget checks. The lobby is built by six parallel
	packages (src/server/World/Lobby/*); these tests keep their set pieces
	off the roads, plots and ore outcrops, apart from each other, and inside
	the mobile part/light budgets.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	-- Grid of ground points covering a piece's footprint (1 stud apart).
	local function footprint(piece): { any }
		local points = {}
		local cf = LobbyLayout.frame(piece)
		if piece.Radius then
			local r = piece.Radius
			for x = -r, r, 1 do
				for z = -r, r, 1 do
					if x * x + z * z <= r * r then
						table.insert(points, piece.Center + Vector3.new(x, 0, z))
					end
				end
			end
		else
			local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
			local nx, nz = math.max(1, math.ceil(piece.Size.X)), math.max(1, math.ceil(piece.Size.Z))
			for i = 0, nx do
				for j = 0, nz do
					local lx = -hx + piece.Size.X * i / nx
					local lz = -hz + piece.Size.Z * j / nz
					table.insert(points, cf:PointToWorldSpace(Vector3.new(lx, 0, lz)))
				end
			end
		end
		return points
	end

	-- (reservations, like the Vault's jungle trees, only keep the scatter
	-- away: they overlap their own package's pieces on purpose)
	local function solidGround(piece): boolean
		return LobbyLayout.isGroundPiece(piece) and not piece.Walkable and not piece.Reserve
	end

	T.test("lobby pieces belong to a package and have sane frames", function()
		local packages = {}
		for _, name in LobbyLayout.Packages do
			packages[name] = true
		end
		T.eq(#LobbyLayout.Packages, 6, "exactly six lobby packages")
		for _, piece in LobbyLayout.Pieces do
			T.truthy(packages[piece.Package], piece.Id .. " has a known package")
			T.truthy(math.abs(piece.Facing.Y) < 1e-6, piece.Id .. " faces horizontally")
			local cf = LobbyLayout.frame(piece)
			local look = cf.LookVector
			T.truthy((look - piece.Facing.Unit).Magnitude < 1e-3, piece.Id .. " frame looks along Facing")
		end
	end)

	T.test("solid lobby pieces stay off roads, plots, outcrops, keep-outs and the spawn", function()
		local spawn = WorldLayout.SpawnPoint
		for _, piece in LobbyLayout.Pieces do
			if solidGround(piece) then
				for _, p in footprint(piece) do
					for _, road in WorldLayout.Roads do
						local d = LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p)
						if d < 0.25 then
							T.truthy(false, `{piece.Id} is on a road at {p}`)
							return
						end
					end
					for _, plot in WorldLayout.Plots do
						local d = p - plot.Center
						if math.abs(d.X) < 27 and math.abs(d.Z) < 27 then
							T.truthy(false, `{piece.Id} is on plot {plot.Id}`)
							return
						end
					end
					for _, spot in WorldLayout.OutcropSpots do
						if (Vector3.new(p.X, 0, p.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < 6 then
							T.truthy(false, `{piece.Id} covers the ore outcrop at {spot}`)
							return
						end
					end
					if WorldLayout.isKeepOut(p) then
						T.truthy(false, `{piece.Id} is in a keep-out box at {p}`)
						return
					end
					if piece.Id ~= "FireCrystal" and (Vector3.new(p.X, 0, p.Z) - Vector3.new(spawn.X, 0, spawn.Z)).Magnitude < 9 then
						T.truthy(false, `{piece.Id} blocks the spawn`)
						return
					end
				end
			end
		end
	end)

	T.test("solid lobby pieces do not overlap each other", function()
		local solids = {}
		for _, piece in LobbyLayout.Pieces do
			if solidGround(piece) then
				table.insert(solids, piece)
			end
		end
		for i, a in solids do
			for j, b in solids do
				if i < j then
					local hit = nil
					for _, p in footprint(a) do
						if LobbyLayout.distanceTo(b, p) < 0.01 then
							hit = p
							break
						end
					end
					T.falsy(hit, `{a.Id} overlaps {b.Id}`)
				end
			end
		end
	end)

	T.test("lobby paths stay off plots and outcrops", function()
		for _, path in LobbyLayout.Paths do
			local a, b = path.From, path.To
			local length = (b - a).Magnitude
			for t = 0, length, 1 do
				local p = a + (b - a) * (t / length)
				for _, plot in WorldLayout.Plots do
					local d = p - plot.Center
					T.falsy(
						math.abs(d.X) < 27 + path.Width / 2 and math.abs(d.Z) < 27 + path.Width / 2,
						`path {path.Id} crosses plot {plot.Id}`
					)
				end
				for _, spot in WorldLayout.OutcropSpots do
					T.truthy(
						(Vector3.new(p.X, 0, p.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude >= 5 + path.Width / 2,
						`path {path.Id} crosses an outcrop`
					)
				end
			end
		end
	end)

	T.test("scatter helper keeps trees off the plaza, roads and pieces", function()
		T.falsy(LobbyLayout.isFree(Vector3.new(0, 0, 0), 2), "plaza center")
		T.falsy(LobbyLayout.isFree(Vector3.new(0, 0, 90), 2), "south road")
		T.falsy(LobbyLayout.isFree(Vector3.new(-104, 0, 28), 2), "plot")
		T.falsy(LobbyLayout.isFree(LobbyLayout.get("FossilDig").Center, 2), "fossil dig")
		T.falsy(LobbyLayout.isFree(Vector3.new(-150, 0, 40), 3), "a plot's yard (design v2) is not free")
		T.truthy(LobbyLayout.isFree(Vector3.new(-36, 0, 70), 3), "the lawn west of the south road is free")
		-- the Blaster Vault, its statues and its jungle trees (reservations, even past the area's edge)
		T.falsy(LobbyLayout.isFree(Vector3.new(0, 0, 112), 2), "blaster vault")
		T.falsy(LobbyLayout.isFree(Vector3.new(43, 0, 92), 2), "east statue")
		T.falsy(LobbyLayout.isFree(Vector3.new(36, 0, 120), 3), "the jungle tree east of the vault")
		T.falsy(LobbyLayout.isFree(Vector3.new(-40, 0, 147), 1), "the jungle trees behind the vault")
	end)

	T.test("world stays inside the mobile part and light budgets", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local mapParts, lobbyParts, lobbyLights = 0, 0, 0
		-- the mine floors count in the map budget, not in the lobby's (MineFloorAreas has their own)
		local mine = map:FindFirstChild("MineFloors")
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and mine and d:IsDescendantOf(mine) then
				mapParts += 1
				continue
			elseif mine and d:IsDescendantOf(mine) then
				continue
			end
			if d:IsA("BasePart") then
				mapParts += 1
				if LobbyLayout.inArea(d.CFrame.Position) then
					lobbyParts += 1
				end
			elseif (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and d.Parent and d.Parent:IsA("BasePart") then
				if LobbyLayout.inArea(d.Parent.CFrame.Position) then
					lobbyLights += 1
				end
			end
		end
		local budget = LobbyLayout.Budget
		T.lt(mapParts, budget.MapParts + 1, "map parts")
		T.lt(lobbyParts, budget.LobbyParts + 1, "lobby parts")
		T.lt(lobbyLights, budget.LobbyLights + 1, "lobby lights")

		-- each package inside its own budget
		local lobby = map:FindFirstChild("Emberfall") and map.Emberfall:FindFirstChild("Lobby")
		if lobby then
			for name, b in budget.Packages do
				local m = lobby:FindFirstChild(name)
				if m then
					local parts, inParts, lights, inLights = 0, 0, 0, 0
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							parts += 1
							if LobbyLayout.inArea(d.CFrame.Position) then
								inParts += 1
							end
						elseif
							(d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight"))
							and d.Parent
							and d.Parent:IsA("BasePart")
						then
							lights += 1
							if LobbyLayout.inArea(d.Parent.CFrame.Position) then
								inLights += 1
							end
						end
					end
					T.lt(parts, b.Parts + 1, name .. " parts")
					T.lt(inParts, b.LobbyParts + 1, name .. " parts in the lobby")
					T.lt(lights, b.Lights + 1, name .. " lights")
					T.lt(inLights, b.LobbyLights + 1, name .. " lights in the lobby")
				end
			end
		end

		-- Land (restyled by the Backdrop package) stays near its old size
		local landParts = 0
		for _, d in map.Land:GetDescendants() do
			if d:IsA("BasePart") then
				landParts += 1
			end
		end
		T.lt(landParts, budget.LandBaselineParts + budget.LandExtraParts + 1, "Land parts")
	end)

	T.test("the spawn stays clear and spinning decor streams as one piece", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local spawn = WorldLayout.SpawnPoint
		-- a player-sized box above the spawn pad must be free of colliding parts
		local min = Vector3.new(spawn.X - 4, 0.6, spawn.Z - 4)
		local max = Vector3.new(spawn.X + 4, 8, spawn.Z + 4)
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Transparency < 1 then
				local cf, size = d.CFrame, d.Size
				local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
				local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
				local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
				local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
				local p = cf.Position
				local overlaps = p.X - hx < max.X
					and p.X + hx > min.X
					and p.Y - hy < max.Y
					and p.Y + hy > min.Y
					and p.Z - hz < max.Z
					and p.Z + hz > min.Z
				T.falsy(overlaps, d:GetFullName() .. " blocks the spawn")
			end
			if d:IsA("Model") and table.find(d:GetTags(), "Spin") then
				T.truthy(d.PrimaryPart, d:GetFullName() .. " (Spin) has a PrimaryPart")
				local mode = d.ModelStreamingMode
				T.truthy(
					mode == roblox.Enum.ModelStreamingMode.Atomic or mode == roblox.Enum.ModelStreamingMode.Persistent,
					d:GetFullName() .. " (Spin) streams atomically"
				)
			end
		end
	end)

	T.test("gameplay hooks exist (new hooks once their package has landed)", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local tagged = {}
		for _, d in map:GetDescendants() do
			for _, tag in d:GetTags() do
				tagged[tag] = tagged[tag] or {}
				table.insert(tagged[tag], d)
			end
		end
		for _, tag in { "SellBin", "SellCounter", "ShopCounter", "EmberChest", "GuildBoard", "Spin" } do
			T.truthy(tagged[tag], "tag " .. tag)
		end
		for _, bin in tagged.SellBin or {} do
			local intake = bin:FindFirstChild("Intake")
			T.truthy(intake and intake:IsA("BasePart"), "SellBin has an Intake part")
			T.falsy(intake and intake.CanCollide, "SellBin Intake does not collide")
		end
		for _, tag in { "SellCounter", "ShopCounter" } do
			for _, inst in tagged[tag] or {} do
				T.truthy(inst:IsA("BasePart"), tag .. " is a part (prompts attach to it)")
			end
		end
		for _, tag in { "EmberChest", "GuildBoard" } do
			for _, inst in tagged[tag] or {} do
				T.truthy(inst:IsA("Model") and inst.PrimaryPart, tag .. " is a model with a PrimaryPart")
			end
		end
		T.truthy(map:FindFirstChild("TownSpawn", true), "TownSpawn exists")
		-- hooks the Districts package adds
		local districts = map.Emberfall:FindFirstChild("Lobby") and map.Emberfall.Lobby:FindFirstChild("Districts")
		if districts then
			for _, tag in { "UpgradeCounter", "OreCodex", "FossilDig" } do
				T.truthy(tagged[tag], "tag " .. tag)
			end
			local chest = (tagged.EmberChest or {})[1]
			local wheel = chest and chest:FindFirstAncestor("SpinWheel")
			T.truthy(wheel, "EmberChest sits on the SpinWheel model")
			for _, tag in { "SellBin", "SellCounter", "ShopCounter", "UpgradeCounter", "EmberChest", "GuildBoard", "OreCodex", "FossilDig" } do
				for _, inst in tagged[tag] or {} do
					T.truthy(inst:IsDescendantOf(districts), tag .. " is built by the Districts package")
				end
			end
		end
		-- the fire crystal spins once the Plaza package has landed
		local plaza = map.Emberfall:FindFirstChild("Lobby") and map.Emberfall.Lobby:FindFirstChild("Plaza")
		if plaza then
			local spins = false
			for _, inst in tagged.Spin or {} do
				spins = spins or inst:IsDescendantOf(plaza)
			end
			T.truthy(spins, "the Plaza's fire crystal is tagged Spin")
		end
	end)
end
