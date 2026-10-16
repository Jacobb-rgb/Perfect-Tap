--[[
	Lobby package Plaza (src/server/World/Lobby/Plaza, LOBBY_PLAN 6.3): the
	fire crystal's Spin hook, a clear and walkable spawn, a walkable plaza
	without holes, the Great Forge inside its footprint with the ridge low
	enough for the DEPTHS sign, flat roads, lanterns off the roads and the
	other pieces, and the package budgets.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Plaza = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza")

	local cached: any = nil
	local function world(): any
		if not cached then
			local game = roblox.Instance.new("DataModel")
			local map = WorldBuilder.build(game:GetService("Workspace"))
			local lobby = map.Emberfall:FindFirstChild("Lobby")
			cached = { map = map, plaza = lobby and lobby:FindFirstChild("Plaza") }
		end
		return cached
	end

	-- world-space axis-aligned bounds of a part
	local function bounds(part: any): (any, any)
		local cf, size = part.CFrame, part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		local p = cf.Position
		return p - Vector3.new(hx, hy, hz), p + Vector3.new(hx, hy, hz)
	end

	local function parts(root: any): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	type Box = { part: any, lo: any, hi: any }

	-- bounds of every colliding part of `list` (computed once per test)
	local function solidBoxes(list: { any }): { Box }
		local out = {}
		for _, part in list do
			if part.CanCollide and part.Transparency < 1 then
				local lo, hi = bounds(part)
				table.insert(out, { part = part, lo = lo, hi = hi })
			end
		end
		return out
	end

	-- XZ distance from a ground point to a box (0 when the point is above/below it)
	local function flatDistance(box: Box, p: any): number
		local dx = math.max(box.lo.X - p.X, 0, p.X - box.hi.X)
		local dz = math.max(box.lo.Z - p.Z, 0, p.Z - box.hi.Z)
		return math.sqrt(dx * dx + dz * dz)
	end

	-- highest floor top (between -0.5 and 1) among `boxes` right under ground point p
	local function floorTop(boxes: { Box }, p: any): number?
		local best: number? = nil
		for _, box in boxes do
			if p.X >= box.lo.X and p.X <= box.hi.X and p.Z >= box.lo.Z and p.Z <= box.hi.Z and box.hi.Y <= 1 and box.hi.Y > -0.5 then
				if not best or box.hi.Y > best then
					best = box.hi.Y
				end
			end
		end
		return best
	end

	T.test("plaza: module contract (Replaces roads, plaza, greatForge)", function()
		T.eq(type(Plaza.build), "function", "build")
		for _, piece in { "roads", "plaza", "greatForge" } do
			T.truthy(table.find(Plaza.Replaces, piece), "replaces " .. piece)
		end
		T.truthy(world().plaza, "Emberfall.Lobby.Plaza is built")
		local town = world().map.Emberfall
		for _, legacy in { "Roads", "Plaza", "GreatForge" } do
			T.falsy(town:FindFirstChild(legacy), "legacy " .. legacy .. " is no longer built")
		end
	end)

	T.test("plaza: the fire crystal spins (Spin tag, attributes, Atomic, PrimaryPart)", function()
		local plaza = world().plaza
		local spinners = {}
		for _, d in plaza:GetDescendants() do
			if table.find(d:GetTags(), "Spin") then
				table.insert(spinners, d)
			end
		end
		T.eq(#spinners, 1, "one spinning model in the plaza")
		local crystal = spinners[1]
		T.truthy(crystal:IsA("Model") and crystal.Name == "FireCrystal", "the Spin model is FireCrystal")
		local body = crystal.PrimaryPart
		T.truthy(body and body:IsDescendantOf(crystal), "PrimaryPart inside the model")
		T.near(body.CFrame.UpVector.Y, 1, 1e-3, "spin axis is vertical")
		local center = LobbyLayout.get("FireCrystal").Center
		T.lt((Vector3.new(body.CFrame.Position.X, 0, body.CFrame.Position.Z) - center).Magnitude, 0.05, "spin axis at the plaza center")
		for _, name in { "SpinSpeed", "BobHeight", "BobSpeed" } do
			T.eq(type(crystal:GetAttribute(name)), "number", name)
		end
		T.truthy(crystal:GetAttribute("SpinSpeed") > 0, "it turns")
		T.eq(crystal.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, "streams atomically")
		T.truthy(body:FindFirstChildWhichIsA("PointLight"), "the crystal carries the plaza light")
		for _, part in parts(crystal) do
			local _, hi = bounds(part)
			T.lt(hi.Y + crystal:GetAttribute("BobHeight"), 24.01, part.Name .. " inside the crystal's height budget")
			T.falsy(part.CanCollide, part.Name .. " (spinning) does not collide")
		end
	end)

	T.test("plaza: crystal ring and spawn inlay stay inside their circles", function()
		local plaza = world().plaza
		local crystal = LobbyLayout.get("FireCrystal")
		for _, part in parts(plaza.FireCrystalRing) do
			local p = part.CFrame.Position
			T.lt((Vector3.new(p.X, 0, p.Z) - crystal.Center).Magnitude, crystal.Radius + 1.3, part.Name .. " inside the crystal ring")
		end
		local spawn = LobbyLayout.get("SpawnPad")
		for _, part in parts(plaza.SpawnInlay) do
			local p = part.CFrame.Position
			local _, hi = bounds(part)
			T.lt((Vector3.new(p.X, 0, p.Z) - spawn.Center).Magnitude, spawn.Radius + 0.6, part.Name .. " inside the spawn pad")
			T.lt(hi.Y, 0.5, part.Name .. " is flush")
			T.falsy(part.CanCollide, part.Name .. " does not collide")
		end
	end)

	T.test("plaza: the spawn stays clear and walkable", function()
		local w = world()
		local spawn = WorldLayout.SpawnPoint
		-- nothing of the Plaza package that collides rises above y 0.6 within r 9 of the spawn
		for _, box in solidBoxes(parts(w.plaza)) do
			if box.hi.Y > 0.6 then
				T.truthy(flatDistance(box, spawn) >= 9, box.part:GetFullName() .. " collides near the spawn")
			end
		end
		-- a solid, level floor under the whole spawn area (any package)
		local near = {}
		for _, box in solidBoxes(parts(w.map)) do
			if flatDistance(box, spawn) < 10 then
				table.insert(near, box)
			end
		end
		for x = -8, 8, 2 do
			for z = -8, 8, 2 do
				if x * x + z * z <= 64 then
					local top = floorTop(near, spawn + Vector3.new(x, 0, z))
					T.truthy(top and top > 0.3 and top < 0.5, `level floor at the spawn ({x}, {z})`)
				end
			end
		end
	end)

	T.test("plaza: the plaza is walkable without holes or bumps", function()
		local w = world()
		local piece = LobbyLayout.get("Plaza")
		local floors = {}
		local obstacles = {}
		for _, box in solidBoxes(parts(w.plaza)) do
			if box.hi.Y <= 0.45 and box.lo.Y < 0.4 then
				table.insert(floors, box)
			elseif box.hi.Y > 0.45 and flatDistance(box, piece.Center) < piece.Radius then
				table.insert(obstacles, box)
			end
		end
		for x = -36, 36, 2 do
			for z = -36, 36, 2 do
				local r = math.sqrt(x * x + z * z)
				if r <= piece.Radius - 0.5 then
					local p = piece.Center + Vector3.new(x, 0, z)
					local top = floorTop(floors, p)
					T.truthy(top and math.abs(top - 0.4) < 0.05, `plaza floor at ({x}, {z})`)
					-- the walking ring between the crystal and the rim props is free
					if r > 14.5 and r < 31 then
						for _, box in obstacles do
							T.truthy(flatDistance(box, p) > 0, `{box.part:GetFullName()} blocks the plaza at ({x}, {z})`)
						end
					end
				end
			end
		end
	end)

	T.test("plaza: the Great Forge stays in its footprint, ridge <= 32", function()
		local forge = world().plaza.GreatForge
		local piece = LobbyLayout.get("GreatForge")
		local min = piece.Center - Vector3.new(piece.Size.X / 2, 0, piece.Size.Z / 2)
		local max = piece.Center + Vector3.new(piece.Size.X / 2, piece.Size.Y, piece.Size.Z / 2)
		local ridge = 0
		local hasGlow, hasSign = false, false
		for _, part in parts(forge) do
			local lo, hi = bounds(part)
			local name = part:GetFullName()
			T.truthy(lo.X >= min.X - 0.05 and hi.X <= max.X + 0.05, `{name} inside the forge footprint (x {lo.X} .. {hi.X})`)
			T.truthy(lo.Z >= min.Z - 0.05 and hi.Z <= max.Z + 0.05, `{name} inside the forge footprint (z {lo.Z} .. {hi.Z})`)
			T.truthy(lo.Y >= -0.05 and hi.Y <= max.Y, name .. " inside the forge height budget")
			if not part:FindFirstAncestor("Chimney") then
				ridge = math.max(ridge, hi.Y)
			end
			if part.Name == "ForgeGlow" and part.Material == roblox.Enum.Material.Neon then
				hasGlow = true
			end
			local gui = part:FindFirstChild("FrontText")
			if gui and gui:FindFirstChildWhichIsA("TextLabel").Text == "THE GREAT FORGE" then
				hasSign = true
			end
		end
		T.lt(ridge, 32.01, "ridge (everything but the chimneys) <= 32")
		T.truthy(ridge > 26, "the forge is a landmark (ridge > 26)")
		T.truthy(hasGlow, "glowing ForgeGlow interior")
		T.truthy(hasSign, "THE GREAT FORGE sign")
		local chimneys = 0
		for _, d in forge:GetChildren() do
			if d.Name == "Chimney" then
				chimneys += 1
				local top = 0
				for _, part in parts(d) do
					local _, hi = bounds(part)
					top = math.max(top, hi.Y)
				end
				T.truthy(top >= 40 and top <= 44, "chimney top between 40 and 44")
			end
		end
		T.eq(chimneys, 2, "two chimneys")
	end)

	T.test("plaza: roads and paths are flat walk-over strips", function()
		local roads = world().plaza.Roads
		for _, part in parts(roads) do
			local _, hi = bounds(part)
			T.falsy(part.CanCollide, part:GetFullName() .. " does not collide")
			T.lt(hi.Y, 0.6, part:GetFullName() .. " is flat")
		end
		local names = {}
		for _, child in roads:GetChildren() do
			names[child.Name] = true
		end
		for _, path in LobbyLayout.Paths do
			T.truthy(names[path.Id], "path " .. path.Id .. " is paved")
		end
		T.eq(#roads:GetChildren(), #WorldLayout.Roads + #LobbyLayout.Paths + 1, "every road (south road in two pieces) and path")
	end)

	T.test("plaza: lanterns stand off the roads and the other packages' pieces", function()
		local plaza = world().plaza
		local count = 0
		for _, group in { plaza.RoadLanterns, plaza.EntranceLanterns } do
			for _, lantern in group:GetChildren() do
				count += 1
				-- the post/pillar foot is the lantern's first, lowest part
				local foot = nil
				for _, part in lantern:GetChildren() do
					if part:IsA("BasePart") and (not foot or part.CFrame.Position.Y < foot.CFrame.Position.Y) then
						foot = part
					end
				end
				local p = Vector3.new(foot.CFrame.Position.X, 0, foot.CFrame.Position.Z)
				-- Flora lights the creek bridge: no road lanterns beside it
				T.falsy(math.abs(p.X) < 14 and p.Z >= 52 and p.Z <= 72, `lantern at {p} doubles up with the bridge lamps`)
				for _, road in WorldLayout.Roads do
					T.truthy(LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p) > 0.3, `lantern at {p} stands on a road`)
				end
				for _, path in LobbyLayout.Paths do
					T.truthy(
						LobbyLayout.distanceToStrip(path.From, path.To, path.Width, p) > 0.3,
						`lantern at {p} stands on path {path.Id}`
					)
				end
				for _, piece in LobbyLayout.Pieces do
					if piece.Package ~= "Plaza" and LobbyLayout.isGroundPiece(piece) then
						T.truthy(LobbyLayout.distanceTo(piece, p) > 0.3, `lantern at {p} stands in {piece.Id}`)
					end
				end
			end
		end
		T.truthy(count >= 20, "lantern rhythm along the roads")
	end)

	T.test("plaza: parts and lights inside the package budget", function()
		local plaza = world().plaza
		local budget = LobbyLayout.Budget.Packages.Plaza
		local n, lights = 0, 0
		for _, d in plaza:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				T.truthy(d.Anchored, d:GetFullName() .. " is anchored")
				if d.Material == roblox.Enum.Material.Neon then
					T.falsy(d.CastShadow, d:GetFullName() .. " (neon) casts no shadow")
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				lights += 1
				T.falsy(d.Shadows, "lights have shadows off")
			end
		end
		T.lt(n, budget.Parts + 1, "Plaza parts")
		T.lt(lights, budget.Lights + 1, "Plaza lights")
	end)
end
