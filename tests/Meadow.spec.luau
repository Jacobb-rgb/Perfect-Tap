--[[
	Flora/Meadow: nothing of the meadow (ponds, trees, fences, lawn) grows
	where an ore rock grows at runtime (the node spawns), it stays pure
	decoration (non-collide, no shadows, no lights), its ponds are there, and
	the lawn behind the Blaster Vault (where the bigger plots first left a sea
	bay; owner 2026-10-22: "fill the gap") is decorated like the lawns either
	side.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
	local meadow = map.Emberfall.Lobby.Flora:FindFirstChild("Meadow")

	T.test("meadow: keeps off the ore rocks and stays decoration", function()
		T.truthy(meadow, "the meadow is built")
		local spawns = WorldBuilder.generateNodeSpawns()
		local lights = 0
		for _, d in meadow:GetDescendants() do
			if d:IsA("BasePart") then
				T.falsy(d.CanCollide or d.CastShadow or d.CanTouch, d:GetFullName() .. " is pure decoration")
				for _, s in spawns do
					if s.Zone == "Outcrops" then
						-- the ground distance from the rock to the part: its center less its
						-- half width (round ponds), or to its box in its own frame when that
						-- is farther (a long fence rail, measured along its length)
						local p = d.CFrame.Position
						local rock = Vector3.new(s.Position.X, p.Y, s.Position.Z)
						local round = (Vector3.new(p.X, 0, p.Z) - Vector3.new(rock.X, 0, rock.Z)).Magnitude
							- math.max(d.Size.X, d.Size.Z) / 2
						local q = d.CFrame:PointToObjectSpace(rock)
						local dx = math.max(math.abs(q.X) - d.Size.X / 2, 0)
						local dy = math.max(math.abs(q.Y) - d.Size.Y / 2, 0)
						local dz = math.max(math.abs(q.Z) - d.Size.Z / 2, 0)
						local dist = math.max(round, math.sqrt(dx * dx + dy * dy + dz * dz))
						T.truthy(dist > 3, `{d:GetFullName()} stays off the ore rock at {s.Position}`)
					end
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				lights += 1
			end
		end
		T.eq(lights, 0, "no lights")
	end)

	T.test("meadow: the ponds are there (owner: more ponds), spread out", function()
		local Meadow = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Meadow")
		local ponds = meadow:FindFirstChild("Ponds")
		local centers = {}
		for _, pond in (if ponds then ponds:GetChildren() else {}) do
			local water = pond:FindFirstChild("Water")
			if water then
				table.insert(centers, water.CFrame.Position)
			end
		end
		T.truthy(#centers >= Meadow.MinPonds and #centers <= Meadow.MaxPonds, `{#centers} meadow ponds`)
		for i, a in centers do
			T.truthy((Vector3.new(a.X, 0, a.Z) - Meadow.LanePond.Center).Magnitude >= 32, `pond {i} keeps off the stream's pond`)
			for j = i + 1, #centers do
				T.truthy((a - centers[j]).Magnitude >= 32, `ponds {i} and {j} are spread out`)
			end
		end
	end)

	T.test("meadow: the lawn's flat pieces never share a plane with what they overlap (no z-fighting)", function()
		-- a part's flat footprint, its top and whether it lies level
		local function footprint(part)
			local cf, size = part.CFrame, part.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
			local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
			local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
			return cf.Position, hx, cf.Position.Y + hy, hz, math.abs(u.Y) > 0.999
		end
		-- every level top near the ground (Land's tint patches, the wilds' slabs, the lawn itself)
		local low = {}
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				local c, hx, top, hz, level = footprint(d)
				if level and top > -0.1 and top < 1 and hx < 60 and hz < 60 then
					table.insert(low, { Part = d, C = c, HX = hx, HZ = hz, Top = top })
				end
			end
		end
		local lawns = { meadow.Lawn }
		local south = meadow:FindFirstChild("SouthLawn")
		if south then
			table.insert(lawns, south.Lawn)
		end
		local flats = 0
		for _, lawn in lawns do
			for _, part in lawn:GetChildren() do
				-- the grass patches (0.12 tall) and the flower beds' mounds (0.45)
				if part:IsA("BasePart") and (math.abs(part.Size.Y - 0.12) < 1e-3 or math.abs(part.Size.Y - 0.45) < 1e-3) then
					flats += 1
					local c, hx, top, hz = footprint(part)
					for _, o in low do
						if o.Part ~= part and math.abs(o.Top - top) < 0.005 then
							local overlap = math.abs(o.C.X - c.X) < hx + o.HX and math.abs(o.C.Z - c.Z) < hz + o.HZ
							T.falsy(overlap, `{part:GetFullName()} at {c} shares its top ({top}) with {o.Part:GetFullName()}`)
						end
					end
				end
			end
		end
		T.truthy(flats >= 60, `the lawn's flat pieces are there ({flats})`)
	end)

	T.test("meadow: the lawn behind the vault is decorated like the lawns either side", function()
		local Meadow = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Meadow")
		local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local south = Meadow.SouthLawn
		if not south then
			-- 12 cells: the south coast is z 150, no lawn behind the vault
			T.eq(WorldLayout.PlotGrid.SouthShift, 0, "a lawn behind the vault once the south band moves")
			T.falsy(meadow:FindFirstChild("SouthLawn"), "nothing planted")
			return
		end
		-- the box between the plot roads' inner verges, from the 12-cell coast to the south coast
		T.eq(south.Min.X, -52, "the lawn's west edge")
		T.eq(south.Max.X, 52, "the lawn's east edge")
		T.eq(south.Min.Z, 150, "the lawn starts at the 12-cell south coast")
		T.truthy(south.Max.Z >= WorldLayout.Island.Max.Z - 2, "the lawn reaches the south coast")
		local function inside(p): boolean
			return p.X > south.Min.X and p.X < south.Max.X and p.Z > south.Min.Z and p.Z < WorldLayout.Island.Max.Z
		end
		local flora = map.Emberfall.Lobby.Flora
		local parts, trees, ponds = 0, 0, 0
		for _, d in flora:GetDescendants() do
			if d:IsA("BasePart") and inside(d.CFrame.Position) then
				parts += 1
			elseif d:IsA("Model") then
				-- (a tree stands on its trunk, a pond holds water)
				local trunk = if d.Name == "Tree" then d:FindFirstChild("Trunk") else nil
				local water = if d.Name == "Pond" then d:FindFirstChild("Water") else nil
				if trunk and inside(trunk.CFrame.Position) then
					trees += 1
				elseif water and inside(water.CFrame.Position) then
					ponds += 1
				end
			end
		end
		T.truthy(parts >= 150, `flora parts on the lawn behind the vault ({parts})`)
		T.truthy(trees >= 6, `trees there ({trees})`)
		T.truthy(ponds >= 1, `a pond there ({ponds})`)
		-- its look is planned: the town's lawn and the wilds keep out of it
		local wilds = flora.Wilds
		for _, model in { meadow.Lawn, wilds.Pieces, wilds.Secrets } do
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					T.falsy(inside(d.CFrame.Position), `{d:GetFullName()} on the planned lawn at {d.CFrame.Position}`)
				end
			end
		end
		-- and it keeps off the Blaster Vault, its approach and the plot roads
		local vault = LobbyLayout.ById.BlasterVault
		for _, d in meadow.SouthLawn:GetDescendants() do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				local reach = math.max(d.Size.X, d.Size.Z) / 2
				T.truthy(LobbyLayout.distanceTo(vault, p) > reach, `{d:GetFullName()} keeps off the Vault`)
				T.truthy(math.abs(p.X) + reach < 70 - 4.5, `{d:GetFullName()} keeps off the plot roads`)
			end
		end
	end)

	T.test("meadow: the road fences in the street lamps' style run along the roads (owner 2026-10-25)", function()
		local RoadFence = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.RoadFence")
		local Common = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.Common")
		local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
		local fences = meadow:FindFirstChild("Fences")
		T.truthy(fences, "the meadow lays the road fences")
		if not RoadFence.Enabled then
			return
		end
		local lamps = map.Emberfall.Lobby.Plaza:FindFirstChild("StreetLamps")
		local feet = {}
		for _, lamp in (if lamps then lamps:GetChildren() else {}) do
			local foot = lamp:FindFirstChild("Foot")
			table.insert(feet, Vector3.new(foot.CFrame.Position.X, 0, foot.CFrame.Position.Z))
		end
		local total = 0
		local perStrip: { [string]: number } = {}
		for _, run in fences:GetChildren() do
			T.eq(run.Name, "RoadFence", "only the metal road fences (no timber ones, no fence lanterns)")
			local glow = run:FindFirstChild("RailGlow")
			T.truthy(glow and glow.Material == roblox.Enum.Material.Neon, "an orange neon strip along the top rail")
			T.truthy(glow.Color.R > 0.9 and glow.Color.G < 0.5, "deep orange, like the lamps' slots")
			local caps = 0
			for _, part in run:GetChildren() do
				if part.Name == "PostCap" then
					caps += 1
				elseif part.Name == "Post" then
					local p = Vector3.new(part.CFrame.Position.X, 0, part.CFrame.Position.Z)
					for _, strip in Common.strips() do
						T.truthy(
							LobbyLayout.distanceToStrip(strip.From, strip.To, strip.Width, p) > 0.6,
							`fence post at {p} stands off {strip.Id}`
						)
					end
					for _, foot in feet do
						T.truthy((foot - p).Magnitude > 1.4, `fence post at {p} clear of the street lamp at {foot}`)
					end
				end
			end
			T.eq(caps, 2, "a glowing cap on both end posts")
			local length = glow.Size.Z + 0.3
			total += length
			-- the strip the run follows: the nearest one to its middle
			local mid = Vector3.new(glow.CFrame.Position.X, 0, glow.CFrame.Position.Z)
			local best, bestId = math.huge, ""
			for _, strip in Common.strips() do
				local d = LobbyLayout.distanceToStrip(strip.From, strip.To, strip.Width, mid)
				if d < best then
					best, bestId = d, strip.Id
				end
			end
			perStrip[bestId] = (perStrip[bestId] or 0) + length
		end
		T.truthy(total >= 450, `road fences along the roads ({math.floor(total)} studs)`)
		for _, id in { "EastPlotRoad", "WestPlotRoad" } do
			T.truthy((perStrip[id] or 0) >= 120, `{id}'s town side is fenced ({math.floor(perStrip[id] or 0)} studs)`)
		end
		for _, id in { "RimRoad", "ForgePathEast", "ToNextArea" } do
			T.truthy((perStrip[id] or 0) >= 15, `{id} is fenced ({math.floor(perStrip[id] or 0)} studs)`)
		end
	end)
end
