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
	local Common = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.Common")

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
				T.lt(luma(part.Color), 0.3, "slate tiles are dark charcoal blue-grey")
				T.truthy(part.Color.B > part.Color.R, "slate tiles are cool (blue over red)")
				T.le(part.Reflectance, 0.2, "only a little reflectance")
				if part.Reflectance > 0.05 then
					polished += 1
				end
			end
		end
		T.truthy(tiles > 80, "rings of slate tiles")
		T.eq(polished, tiles, "one polished finish on every slab (no glossy/matte patchwork)")
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
			local _, hi = bounds(part)
			T.lt(hi.Y, 0.4 + 0.6, "the curb is low (legs barely clip through it)")
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
		-- dark metal and orange dominate: thin blue edges, slots bigger than them, dark caps
		for _, part in parts(ring) do
			if part.Name == "RingEdgeGlow" then
				T.truthy(part.Size.X <= 0.16 and part.Size.Y <= 0.16, "a thin blue accent edge")
			elseif part.Name == "RingSlot" then
				T.truthy(part.Size.Y >= 0.45 and part.Size.Z >= 1.5, "long orange slots")
				T.truthy(part.Color.G < 0.45, "deep orange slots (they stay orange under bloom)")
			end
		end
		-- the low outer step of the two-tier ring, with a blue neon line at its foot
		local lip, lipGlow = ring:FindFirstChild("RingLip"), ring:FindFirstChild("LipGlow")
		T.truthy(lip and lipGlow, "a low outer lip with a glowing foot")
		T.falsy(lip.CanCollide, "the lip is walk-through")
		T.truthy(lipGlow.Material == NEON and isBlue(lipGlow.Color), "blue neon at the lip's foot")
		local _, lipTop = bounds(lip)
		T.lt(lipTop.Y, 1, "the lip is low")
		-- the crystal (Spin, light) still rises out of it
		local crystal = world().plaza:FindFirstChild("FireCrystal")
		local ringTop = 0
		for _, part in parts(ring) do
			local _, hi = bounds(part)
			ringTop = math.max(ringTop, hi.Y)
		end
		local crystalTop = 0
		for _, part in parts(crystal) do
			local _, hi = bounds(part)
			crystalTop = math.max(crystalTop, hi.Y)
		end
		T.truthy(crystalTop > ringTop + 5, "the crystal towers over its housing")
		-- but stays short, so the forge's glowing doorway shows above it from the spawn (eye y 9)
		T.lt(crystalTop + crystal:GetAttribute("BobHeight"), 9.6, "a short crystal cluster")
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
		T.truthy(chevrons >= 4, "glowing chevrons on the south walkway")
		-- crisp thin chevrons and dark, lightly polished walkway panels (no glare near the spawn)
		for _, child in roads:GetChildren() do
			for _, part in parts(child) do
				if part.Name == "Chevron" then
					T.truthy(part.Size.X <= 0.5, "thin chevron bars")
				elseif part.Name == "WalkPanel" then
					T.lt(luma(part.Color), 0.28, "dark walkway panels")
					T.truthy(part.Color.B > part.Color.R, "cool grey-blue walkway panels")
					T.le(part.Reflectance, Common.TileReflectance, "the plaza's light polish, no more (no glare)")
					local base = child:FindFirstChild("PathBase")
					T.truthy(luma(part.Color) > luma(base.Color) + 0.05, "panels lighter than the seams (the grid reads)")
				end
			end
		end
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
		-- the spawn pad is covered (no light flagstone pad in the dark plaza)
		local cover = false
		for _, part in parts(inlay) do
			local p = part.CFrame.Position
			if part.Size.X >= 7.8 and part.Size.Z >= 7.8 and (Vector3.new(p.X, 0, p.Z) - spawn).Magnitude < 0.1 then
				cover = true
			end
		end
		T.truthy(cover, "the spawn pad is dressed in slate")
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
					local core = lantern.PrimaryPart
					T.eq(core.Name, "LanternGlow", "the lamp glows")
					T.truthy(core.Color.G < 0.65 and core.Color.B < 0.25, "an amber lamp core (not white)")
					T.truthy(core.Size.X <= 0.7, "a small neon core")
					local glass = lantern:FindFirstChild("LanternGlass")
					T.truthy(glass and glass.Transparency > 0 and glass.Material ~= NEON, "orange glass panes round the core")
				end
			end
		end
		T.truthy(pillars >= 16, "lantern pillars along the walkways and at the entrances")
		-- the south entrance pair by the spawn glows without a light (the dark walkway stays dark)
		for _, lantern in plaza.EntranceLanterns:GetChildren() do
			if lantern.PrimaryPart.CFrame.Position.Z > 40 then
				T.falsy(lantern.PrimaryPart:FindFirstChildWhichIsA("PointLight"), "the south entrance lanterns are unlit")
			end
		end
	end)

	-- the 8 corners of a part's box (world space)
	local function corners(part: any): { any }
		local out = {}
		local h = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					table.insert(out, part.CFrame:PointToWorldSpace(Vector3.new(x * h.X, y * h.Y, z * h.Z)))
				end
			end
		end
		return out
	end

	T.test("plaza v2: the Great Forge has slate roofs with brick-red trim, banners, a framed emblem and monumental stairs", function()
		local forge = world().plaza.GreatForge
		local GreatForge = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GreatForge")
		local roofs, glow, hammers = 0, 0, 0
		local stairs = {}
		local apex = GreatForge.NaveEave + GreatForge.NaveRoofHeight
		local pitch = GreatForge.NaveRoofHeight / GreatForge.NaveRoofHalf
		for _, part in parts(forge) do
			if part.Name == "Roof" then
				roofs += 1
				T.truthy(part.Color.B >= part.Color.R, "dark slate roof (not red)")
				T.lt(luma(part.Color), 0.4, "the roof is dark")
			elseif part.Name == "EmblemGlow" or part.Name == "EmblemHammers" or part.Name == "Emblem" or part.Name == "EmblemBorder" then
				if part.Name == "EmblemGlow" then
					T.eq(part.Material, NEON, "the emblem halo glows")
					T.truthy(part.Color.G < 0.7 and part.Color.B < 0.2, "a deep-gold glow, not white")
					glow += 1
				elseif part.Name == "EmblemHammers" then
					T.truthy(part.Material ~= NEON, "solid gold hammers in front of the glow")
					hammers += 1
				end
				-- inside the gable triangle, above THE GREAT FORGE board
				for _, c in corners(part) do
					T.truthy(c.Y <= apex - pitch * math.abs(c.X) + 0.05, `{part.Name} inside the gable at ({c.X}, {c.Y})`)
					T.truthy(c.Y >= GreatForge.SignY + 2.2, part.Name .. " above the sign")
				end
			elseif part.Name == "Stair" then
				table.insert(stairs, part)
			end
		end
		T.eq(roofs, 6, "three slate gable roofs")
		-- a low, wide hall under one big gable (concept v2), not a two-storey house
		T.truthy(GreatForge.NaveEave <= 17.5, "the gable starts right over the entrance")
		T.truthy(GreatForge.NaveRoofHeight / (GreatForge.NaveEave + GreatForge.NaveRoofHeight) >= 0.4, "the gable is ~half the facade")
		T.truthy(GreatForge.EmblemSize >= GreatForge.NaveRoofHalf * 2 * 0.28, "a big emblem (~1/3 of the gable's width)")
		-- slate roofs with thin shingle courses (no thick rows or rafter seams)
		local courses = 0
		for _, part in parts(forge) do
			if part.Color == Common.Colors.RoofSlateDark then
				courses += 1
				T.truthy(math.min(part.Size.X, part.Size.Y, part.Size.Z) <= 0.16, "thin shingle courses and joints")
			end
		end
		T.truthy(courses >= 20, "shingle courses on the slate roofs")
		T.truthy(glow >= 4 and hammers >= 4, "a big glowing crossed-hammers emblem")
		-- brick-red trim (eaves, bargeboards) frames the slate roofs
		local trim = 0
		for _, part in parts(forge) do
			local c = part.Color
			if not part:FindFirstAncestor("Banner") and part.Material ~= NEON and c.R > 0.5 and c.R < 0.7 and c.G < 0.25 and c.B < 0.2 then
				trim += 1
			end
		end
		T.truthy(trim >= 8, "brick-red eaves and bargeboards")
		-- nothing pokes up over the gable apex (no ridge stub), the board stays on the gable
		for _, part in parts(forge) do
			if not part:FindFirstAncestor("Chimney") then
				local _, hi = bounds(part)
				T.lt(hi.Y, apex + 0.5, part.Name .. " stays under the apex (only the bargeboards meet over it)")
			end
		end
		local sign = forge:FindFirstChild("ForgeSign")
		T.truthy(sign, "THE GREAT FORGE board")
		T.near(sign.CFrame.Position.Y, GreatForge.SignY, 0.01, "the board stays on the gable")
		T.truthy(sign.CFrame.Position.Y + sign.Size.Y / 2 > GreatForge.NaveEave, "the board reaches over the gable's foot")
		T.truthy(sign.Size.X <= GreatForge.NaveRoofHalf * 2 - 4, "the board is no wider than the nave front (no floating billboard)")
		-- two crimson banners with gold hammers left and right of the entrance
		local banners = {}
		for _, child in forge:GetChildren() do
			if child.Name == "Banner" then
				table.insert(banners, child)
			end
		end
		T.eq(#banners, 2, "two banners")
		local sides = 0
		local cloths = {}
		for _, banner in banners do
			local cloth = banner:FindFirstChild("BannerCloth")
			T.truthy(cloth, "banner cloth")
			local c = cloth.Color
			T.truthy(c.R > 0.55 and c.G < 0.12 and c.B < c.R * 0.4, "crimson banner cloth (not orange)")
			table.insert(cloths, cloth)
			local lo, hi = bounds(cloth)
			T.truthy(hi.Y - lo.Y > 9, "a long banner")
			T.truthy((hi.Y - lo.Y) / GreatForge.BannerWidth > 2.7, "a long, narrow banner (concept: ~3.5 : 1)")
			T.truthy(hi.Y >= GreatForge.NaveEave - 1.5, "it hangs from just under the gable's eave")
			T.lt(lo.Y, GreatForge.PlinthTop + 1.2, "down to the porch")
			local cx = LobbyLayout.get("GreatForge").Center.X
			T.lt(math.min(math.abs(lo.X - cx), math.abs(hi.X - cx)), 10.5, "right beside the door pillars")
			local icon = 0
			for _, part in parts(banner) do
				if part.Name == "BannerIcon" then
					icon += 1
					T.truthy(part.Material ~= NEON, "matte gold icon (no bloom)")
				end
			end
			T.truthy(icon >= 4, "gold hammers on the banner")
			sides += if cloth.CFrame.Position.X > 0 then 1 else -1
		end
		T.eq(sides, 0, "one banner on each side of the entrance")
		-- no plaza light reaches the banners (warm light would turn them orange)
		for _, d in world().plaza:GetDescendants() do
			if d:IsA("PointLight") then
				local p = d.Parent.CFrame.Position
				for _, cloth in cloths do
					local lo, hi = bounds(cloth)
					local q = Vector3.new(math.clamp(p.X, lo.X, hi.X), math.clamp(p.Y, lo.Y, hi.Y), math.clamp(p.Z, lo.Z, hi.Z))
					T.truthy((q - p).Magnitude > d.Range, `{d.Parent:GetFullName()}'s light reaches a banner`)
				end
			end
		end
		-- a monumental, walkable flight of stairs up to a raised, tall doorway
		table.sort(stairs, function(a: any, b: any): boolean
			return a.Size.Y < b.Size.Y
		end)
		T.eq(#stairs, GreatForge.StairSteps - 1, "the stair blocks")
		T.truthy(GreatForge.StairSteps >= 9 and GreatForge.PlinthTop >= 4.5, "a tall flight (>= 9 risers up to a raised porch)")
		local last = 0.4
		for _, step in stairs do
			local lo, hi = bounds(step)
			T.truthy(step.CanCollide, "the steps are solid")
			T.truthy(hi.X - lo.X >= 15, "a wide flight")
			T.lt(hi.Y - last, 0.5, "each riser is easy to walk up")
			last = hi.Y
		end
		T.lt(GreatForge.PlinthTop - last, 0.5, "the last riser reaches the porch")
		T.truthy(GreatForge.DoorTop - GreatForge.PlinthTop >= 7.5, "the doorway keeps its clearance")
		-- stone cheeks with handrails (orange neon undersides) and a lit lantern pillar on each
		local rails, lanterns = 0, 0
		for _, part in parts(forge) do
			if part.Name == "StairGlow" and part.Material == NEON and isOrange(part.Color) then
				rails += 1
			end
		end
		for _, d in forge:GetChildren() do
			if d.Name == "Lantern" and d.PrimaryPart and d.PrimaryPart:FindFirstChildWhichIsA("PointLight") then
				lanterns += 1
			end
		end
		T.eq(rails, 2, "a handrail with an orange neon underside on each cheek")
		T.eq(lanterns, 2, "a lit lantern pillar on each stair cheek")
		-- a busy, glowing workshop behind the doorway
		local mouths = 0
		for _, part in parts(forge) do
			if (part.Name == "ForgeGlow" or part.Name == "FurnaceGlow") and part.Material == NEON then
				mouths += 1
				T.truthy(part.Color.G < 0.45, "deep orange furnace glow (not a yellow-white wall)")
			end
		end
		T.truthy(mouths >= 3, "three glowing furnace mouths")
		-- recessed behind grate bars in a warm-orange furnace wall, under an arched doorway
		local grates, arches = 0, 0
		for _, part in parts(forge) do
			if part.Name == "FurnaceGrate" then
				grates += 1
			elseif part.Name == "DoorArch" then
				arches += 1
			end
		end
		T.truthy(grates >= 6, "grate bars in front of the furnace mouths")
		T.eq(arches, 2, "an arched doorway (two haunches)")
		local wall = forge:FindFirstChild("FurnaceWall")
		T.truthy(
			wall and wall.Material ~= NEON and wall.Color.R > 0.7 and wall.Color.B < 0.25,
			"a warm-orange furnace wall (the hall glows)"
		)
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
