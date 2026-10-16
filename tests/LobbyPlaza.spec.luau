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

	-- concept v2 look ------------------------------------------------------

	local NEON = roblox.Enum.Material.Neon
	local SMOOTH = roblox.Enum.Material.SmoothPlastic

	local function luma(c: any): number
		return 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
	end
	-- orange glow (Fire, Ember): red high, blue low
	local function isOrange(c: any): boolean
		return c.R > 0.9 and c.B < 0.3 and c.G > 0.3
	end
	-- blue glow (GlowEdge): blue high, red low
	local function isBlue(c: any): boolean
		return c.B > 0.9 and c.R < 0.45
	end

	T.test("plaza v2: dark polished slate floor with blue and orange neon rings", function()
		local paving = world().plaza.Paving
		local floor = paving.PlazaFloor
		T.truthy(floor.CanCollide, "the plaza floor collides")
		T.lt(luma(floor.Color), 0.25, "the floor (seams) is dark")
		local tiles, polished = 0, 0
		for _, part in paving:GetChildren() do
			if part:IsA("BasePart") and part ~= floor and part.Name ~= "CrystalFloor" then
				tiles += 1
				T.eq(part.Material, SMOOTH, "slate tiles are SmoothPlastic")
				T.lt(luma(part.Color), 0.45, "slate tiles are dark blue-grey")
				T.truthy(part.Color.B > part.Color.R, "slate tiles are cool (blue over red)")
				T.le(part.Reflectance, 0.2, "only a little reflectance")
				if part.Reflectance > 0.05 then
					polished += 1
				end
			end
		end
		T.truthy(tiles > 80, "rings of slate tiles")
		T.truthy(polished > tiles / 3, "most slabs are polished (Reflectance)")
		local orange, blue = {}, {}
		local piece = LobbyLayout.get("Plaza")
		for _, part in parts(paving.NeonRings) do
			T.eq(part.Material, NEON, part.Name .. " glows")
			T.falsy(part.CanCollide, part.Name .. " does not collide")
			local _, hi = bounds(part)
			T.lt(hi.Y, 0.46, part.Name .. " is flat in the floor")
			local r = (Vector3.new(part.CFrame.Position.X, 0, part.CFrame.Position.Z) - piece.Center).Magnitude
			T.lt(r, piece.Radius, part.Name .. " lies on the plaza")
			if isOrange(part.Color) then
				orange[part.Name] = (orange[part.Name] or 0) + 1
			elseif isBlue(part.Color) then
				blue[part.Name] = (blue[part.Name] or 0) + 1
			end
		end
		T.truthy((orange.InnerRing or 0) >= 20, "an orange neon ring round the crystal")
		T.truthy((blue.OuterRing or 0) >= 30, "a blue neon outer ring")
		T.truthy((blue.BlueDashRing or 0) > 0 and (orange.OrangeDashRing or 0) > 0, "thin light strips between them")
		local curbGlow = 0
		for _, part in parts(paving.Curb) do
			T.falsy(part.CanCollide, "the curb is walk-through")
			if part.Name == "CurbGlow" and part.Material == NEON then
				curbGlow += 1
			end
		end
		T.truthy(curbGlow > 12, "a blue neon edge along the curb (between the entrances)")
	end)

	T.test("plaza v2: the fire crystal sits in a chunky mechanical ring", function()
		local ring = world().plaza.FireCrystalRing
		local segments, slots, edges = 0, 0, 0
		for _, part in parts(ring) do
			if part.Name == "RingSegment" then
				segments += 1
				T.truthy(part.CanCollide, "housing segments are solid")
				T.lt(luma(part.Color), 0.35, "housing segments are dark metal")
			elseif part.Name == "RingSlot" and part.Material == NEON and isOrange(part.Color) then
				slots += 1
			elseif part.Name == "RingEdgeGlow" and part.Material == NEON and isBlue(part.Color) then
				edges += 1
			end
		end
		T.truthy(segments >= 12, "at least 12 housing segments")
		T.eq(slots, segments, "an orange glowing slot on every segment")
		T.eq(edges, segments, "a blue neon edge on every segment")
		-- the crystal (Spin, light) still rises out of it
		local crystal = world().plaza:FindFirstChild("FireCrystal")
		local ringTop = 0
		for _, part in parts(ring) do
			local _, hi = bounds(part)
			ringTop = math.max(ringTop, hi.Y)
		end
		local _, crystalTop = bounds(crystal.PrimaryPart)
		T.truthy(crystalTop.Y > ringTop + 6, "the crystal towers over its housing")
	end)

	T.test("plaza v2: neon walkways with orange edge strips and a chevron to the forge", function()
		local roads = world().plaza.Roads
		local glowing: { [string]: boolean } = {}
		for _, child in roads:GetChildren() do
			for _, part in parts(child) do
				if part.Name == "EdgeGlow" and part.Material == NEON and isOrange(part.Color) then
					glowing[child.Name] = true
				end
			end
		end
		-- (ToShop and ToUpgrades end right at the plaza rim under the stall fronts: no edge in view)
		for _, id in { "SouthRoad", "EastSpur", "WestSpur", "ForgePathEast", "ForgePathWest", "ToWheel", "ToFossil" } do
			T.truthy(glowing[id], id .. " has orange neon edge strips")
		end
		-- glowing chevrons on the south walkway between the plaza and the bridge
		local chevrons = 0
		for _, child in roads:GetChildren() do
			if child.Name == "SouthRoad" then
				for _, part in parts(child) do
					if part.Material == NEON and part.Name ~= "EdgeGlow" then
						local p = part.CFrame.Position
						T.truthy(p.Z > 36 and p.Z < 56 and math.abs(p.X) < 5, "chevron on the south walkway near the plaza")
						T.falsy(part.CanCollide, "chevrons do not collide")
						chevrons += 1
					end
				end
			end
		end
		T.truthy(chevrons >= 4, "a double chevron on the south walkway")
		-- and one in the spawn pad, pointing north (its arms trail south of the tip)
		local inlay = world().plaza.SpawnInlay
		local spawn = LobbyLayout.get("SpawnPad").Center
		local north = 0
		for _, part in parts(inlay) do
			if part.Material == NEON and isOrange(part.Color) and part.CFrame.Position.Z < spawn.Z - 5 then
				north += 1
			end
		end
		T.truthy(north >= 4, "a glowing double chevron north of the spawn")
	end)

	T.test("plaza v2: dark metal lantern pillars with glowing orange slots by the plaza", function()
		local plaza = world().plaza
		local pillars = 0
		for _, group in { plaza.EntranceLanterns, plaza.RoadLanterns } do
			for _, lantern in group:GetChildren() do
				local slots = 0
				for _, part in parts(lantern) do
					if part.Name == "LanternSlot" and part.Material == NEON and isOrange(part.Color) then
						slots += 1
					end
				end
				local p = lantern.PrimaryPart.CFrame.Position
				local near = Vector3.new(p.X, 0, p.Z).Magnitude < 50
				if group == plaza.EntranceLanterns or near then
					T.eq(slots, 2, lantern:GetFullName() .. " is a slotted lantern pillar")
				end
				if slots > 0 then
					pillars += 1
					T.eq(lantern.PrimaryPart.Name, "LanternGlow", "the lamp glows")
				end
			end
		end
		T.truthy(pillars >= 16, "lantern pillars along the walkways and at the entrances")
	end)

	T.test("plaza v2: the Great Forge has slate roofs, banners, a glowing emblem and wide stairs", function()
		local forge = world().plaza.GreatForge
		local GreatForge = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GreatForge")
		local roofs, emblemGlow, hammers = 0, 0, 0
		local stairs = {}
		for _, part in parts(forge) do
			if part.Name == "Roof" then
				roofs += 1
				T.truthy(part.Color.B >= part.Color.R, "dark slate roof (not red)")
				T.lt(luma(part.Color), 0.4, "the roof is dark")
			elseif part.Name == "EmblemGlow" and part.Material == NEON then
				emblemGlow += 1
			elseif part.Name == "EmblemHammers" and part.Material == NEON then
				hammers += 1
				T.truthy(math.abs(part.CFrame.Position.Y - GreatForge.EmblemY) < GreatForge.EmblemDiameter / 2, "hammers on the emblem")
			elseif part.Name == "Stair" then
				table.insert(stairs, part)
			end
		end
		T.eq(roofs, 6, "three slate gable roofs")
		T.truthy(emblemGlow > 0 and hammers >= 4, "a glowing crossed-hammers emblem")
		-- the board stays on the gable, under the emblem
		local sign = forge:FindFirstChild("ForgeSign")
		T.truthy(sign, "THE GREAT FORGE board")
		T.near(sign.CFrame.Position.Y, GreatForge.SignY, 0.01, "the board stays on the gable")
		T.truthy(GreatForge.EmblemY - GreatForge.EmblemDiameter / 2 >= GreatForge.SignY + 2.15, "the emblem sits above the board")
		-- two red banners with gold hammers left and right of the entrance
		local banners = {}
		for _, child in forge:GetChildren() do
			if child.Name == "Banner" then
				table.insert(banners, child)
			end
		end
		T.eq(#banners, 2, "two banners")
		local sides = 0
		for _, banner in banners do
			local cloth = banner:FindFirstChild("BannerCloth")
			T.truthy(cloth and cloth.Color.R > 0.7 and cloth.Color.G < 0.3, "red banner cloth")
			local _, hi = bounds(cloth)
			local lo = bounds(cloth)
			T.truthy(hi.Y - lo.Y > 7, "a tall banner")
			local icon = 0
			for _, part in parts(banner) do
				if part.Material == NEON then
					icon += 1
				end
			end
			T.truthy(icon >= 4, "gold hammers on the banner")
			sides += if cloth.CFrame.Position.X > 0 then 1 else -1
		end
		T.eq(sides, 0, "one banner on each side of the entrance")
		-- wide walkable stairs from the plaza apron up to the porch
		table.sort(stairs, function(a: any, b: any): boolean
			return a.Size.Y < b.Size.Y
		end)
		T.eq(#stairs, GreatForge.StairSteps - 1, "the stair blocks")
		local last = 0.4
		for _, step in stairs do
			local lo, hi = bounds(step)
			T.truthy(step.CanCollide, "the steps are solid")
			T.truthy(hi.X - lo.X >= 20, "wide stairs")
			T.lt(hi.Y - last, 0.5, "each riser is easy to walk up")
			last = hi.Y
		end
		T.lt(GreatForge.PlinthTop - last, 0.5, "the last riser reaches the porch")
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
