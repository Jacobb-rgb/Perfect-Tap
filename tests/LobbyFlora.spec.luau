--[[
	Lobby package Flora (src/server/World/Lobby/Flora): ponds, creek,
	bridge, signpost, NEXT AREA + boardwalk, hero trees, the scatter and the
	town buildings (sites on free ground, inside their rectangles, no lights).
	Checks that nothing lands on roads, paths, plots, the bases' yards or
	the spawn, that the bridge, creek and boardwalk are walkable, the sight
	lines of LOBBY_PLAN 6.5, the budgets and determinism.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Flora = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora")
	local Scatter = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Scatter")
	local Signs = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Signs")
	local Town = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Town")

	local cachedMap = nil
	local function world()
		if not cachedMap then
			local game = roblox.Instance.new("DataModel")
			cachedMap = WorldBuilder.build(game:GetService("Workspace"))
		end
		return cachedMap
	end

	local function flora()
		return world().Emberfall.Lobby.Flora
	end

	local function parts(root): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Half extents of a part's world bounding box.
	local function halfExtents(part): any
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
		local s = part.Size
		return Vector3.new(
			math.abs(r00) * s.X / 2 + math.abs(r01) * s.Y / 2 + math.abs(r02) * s.Z / 2,
			math.abs(r10) * s.X / 2 + math.abs(r11) * s.Y / 2 + math.abs(r12) * s.Z / 2,
			math.abs(r20) * s.X / 2 + math.abs(r21) * s.Y / 2 + math.abs(r22) * s.Z / 2
		)
	end

	-- Y interval where the vertical line through (x, z) passes a part's box (nil if it misses).
	local function verticalHit(part, x: number, z: number): (number?, number?)
		local origin = Vector3.new(x, -100, z)
		local lo = part.CFrame:PointToObjectSpace(origin)
		local ld = part.CFrame:VectorToObjectSpace(Vector3.new(0, 1, 0))
		local tmin, tmax = -math.huge, math.huge
		for _, axis in { "X", "Y", "Z" } do
			local o, d, h = lo[axis], ld[axis], part.Size[axis] / 2
			if math.abs(d) < 1e-9 then
				if math.abs(o) > h then
					return nil, nil
				end
			else
				local t1, t2 = (-h - o) / d, (h - o) / d
				tmin = math.max(tmin, math.min(t1, t2))
				tmax = math.min(tmax, math.max(t1, t2))
			end
		end
		if tmin > tmax then
			return nil, nil
		end
		return -100 + tmin, -100 + tmax
	end

	-- Colliding parts near a strip of the map (pre-filter for the walk checks).
	local function collidersNear(roots: { any }, min, max): { any }
		local out = {}
		for _, root in roots do
			for _, part in parts(root) do
				if part.CanCollide then
					local p, e = part.CFrame.Position, halfExtents(part)
					if p.X + e.X >= min.X and p.X - e.X <= max.X and p.Z + e.Z >= min.Z and p.Z - e.Z <= max.Z then
						table.insert(out, part)
					end
				end
			end
		end
		return out
	end

	-- Standing height at (x, z): the highest collider top at or below `below`.
	local function surface(colliders: { any }, x: number, z: number, below: number): number?
		local best: number? = nil
		for _, part in colliders do
			local _, top = verticalHit(part, x, z)
			if top and top <= below and (best == nil or top > best) then
				best = top
			end
		end
		return best
	end

	-- Is there a collider between y0 and y1 at (x, z)?
	local function blocked(colliders: { any }, x: number, z: number, y0: number, y1: number): boolean
		for _, part in colliders do
			local bottom, top = verticalHit(part, x, z)
			if bottom and top and bottom < y1 and top > y0 then
				return true
			end
		end
		return false
	end

	T.test("flora: replaces the legacy scatter and builds every section", function()
		T.truthy(table.find(Flora.Replaces, "scatter"), "Flora replaces scatter")
		T.falsy(world().Emberfall:FindFirstChild("Nature"), "legacy scatter (Nature) is gone")
		local f = flora()
		for _, path in
			{
				"Water.LilyPond",
				"Water.KoiPond",
				"Water.CreekBridge",
				"Wayfinding.Signpost",
				"Wayfinding.NextArea",
				"Wayfinding.NextAreaBoardwalk",
				"HeroTrees.PinkGrove",
				"HeroTrees.RedTree",
				"HeroTrees.AutumnCorner",
				"HeroTrees.TownBelt",
				"Gardens",
				"Scatter",
				"Fences",
				"GardenLanterns",
				"Town",
			}
		do
			local node = f
			for name in string.gmatch(path, "[^%.]+") do
				node = node and node:FindFirstChild(name)
			end
			T.truthy(node, "Flora has " .. path)
		end
	end)

	T.test("flora: inside its part and light budgets", function()
		local b = LobbyLayout.Budget.Packages.Flora
		local total, inLobby, lights = 0, 0, 0
		for _, d in flora():GetDescendants() do
			if d:IsA("BasePart") then
				total += 1
				if LobbyLayout.inArea(d.CFrame.Position) then
					inLobby += 1
				end
				T.truthy(d.Anchored, d:GetFullName() .. " is anchored")
				if d.Material == roblox.Enum.Material.Neon then
					T.falsy(d.CastShadow, d:GetFullName() .. " neon casts no shadow")
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				lights += 1
				T.falsy(d.Shadows, "lights have shadows off")
				T.truthy(LobbyLayout.inArea(d.Parent.CFrame.Position), "Flora lights stay in the lobby area")
			end
		end
		T.lt(total, b.Parts + 1, "Flora parts")
		T.lt(inLobby, b.LobbyParts + 1, "Flora parts in the lobby area")
		T.lt(lights, b.Lights + 1, "Flora lights")
		local scatter = flora().Scatter
		T.lt(scatter:GetAttribute("Trees"), 46, "at most 45 scattered trees")
		T.lt(scatter:GetAttribute("Bushes"), 36, "at most 35 bushes")
		T.lt(scatter:GetAttribute("Flowers"), 51, "at most 50 flower patches")
		T.lt(scatter:GetAttribute("Boulders"), 16, "at most 15 boulders")
		-- (round 3: the bigger dig, wheel and stalls and the continuous belts take ground: 24+)
		T.truthy(scatter:GetAttribute("Trees") >= 24, "the scatter plants its trees")
		T.lt(#parts(scatter), 751, "scatter parts")
	end)

	T.test("flora: nothing on roads, paths, plots, yards, outcrops or the spawn", function()
		local spawn = WorldLayout.SpawnPoint
		-- (the bridge carries the south road over the koi pond)
		local walkable = { CreekBridge = true, KoiPond = true }
		for _, part in parts(flora()) do
			local onWalkable = false
			local node = part.Parent
			while node and node ~= flora() do
				onWalkable = onWalkable or walkable[node.Name] == true
				node = node.Parent
			end
			local p = part.CFrame.Position
			local flat = Vector3.new(p.X, 0, p.Z)
			-- overhead crowns and lamp arms may reach over a road; anything low or solid may not
			local low = p.Y < 5 or part.CanCollide
			if low and not onWalkable then
				-- the center, and for solid parts the corners of their footprint too
				local probes = { flat }
				if part.CanCollide then
					local e = halfExtents(part)
					for _, sx in { -1, 1 } do
						for _, sz in { -1, 1 } do
							table.insert(probes, flat + Vector3.new(sx * (e.X - 0.05), 0, sz * (e.Z - 0.05)))
						end
					end
				end
				for _, q in probes do
					for _, road in WorldLayout.Roads do
						T.truthy(
							LobbyLayout.distanceToStrip(road.From, road.To, road.Width, q) > 0.2,
							`{part:GetFullName()} on a road at {q}`
						)
					end
					for _, path in LobbyLayout.Paths do
						T.truthy(
							LobbyLayout.distanceToStrip(path.From, path.To, path.Width, q) > 0.2,
							`{part:GetFullName()} on path {path.Id} at {q}`
						)
					end
				end
			end
			for _, plot in WorldLayout.Plots do
				T.falsy(LobbyLayout.onBase(plot, flat, 0), `{part:GetFullName()} on base {plot.Id} (plot or yard) at {p}`)
			end
			T.truthy((flat - Vector3.new(spawn.X, 0, spawn.Z)).Magnitude >= 9, `{part:GetFullName()} on the spawn`)
			if part.CanCollide then
				for _, spot in WorldLayout.OutcropSpots do
					T.truthy((flat - Vector3.new(spot.X, 0, spot.Z)).Magnitude >= 5, `{part:GetFullName()} on an ore outcrop`)
				end
			end
		end
		-- the junction lanterns stand on free ground
		for _, l in Scatter.Lanterns do
			T.truthy(LobbyLayout.isFree(l.At, 0.5), `garden lantern at {l.At} is on free ground`)
		end
	end)

	T.test("flora: sight lines to the bridge and over the plaza stay open", function()
		local road = WorldLayout.Roads[1]
		for _, d in flora():GetDescendants() do
			if d:IsA("Model") and d.Name == "Tree" then
				for _, part in parts(d) do
					local p = part.CFrame.Position
					if p.Z >= 36 and p.Z <= 100 then
						T.truthy(
							LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p) >= 6,
							`{d:GetFullName()} within 6 studs of the south road at {p}`
						)
					end
				end
			end
		end
		for _, part in parts(flora()) do
			local p = part.CFrame.Position
			if Vector3.new(p.X, 0, p.Z).Magnitude < 35.6 + 10 then
				T.truthy(p.Y + halfExtents(part).Y <= 12.01, `{part:GetFullName()} taller than 12 near the plaza curb`)
			end
		end
	end)

	T.test("flora: the bridge carries the south road over the creek", function()
		local bridge = LobbyLayout.get("CreekBridge")
		local z0 = bridge.Center.Z - bridge.Size.Z / 2 - 2
		local z1 = bridge.Center.Z + bridge.Size.Z / 2 + 2
		local colliders = collidersNear({ flora().Water, world().Land }, Vector3.new(-6, 0, z0 - 1), Vector3.new(6, 0, z1 + 1))
		local peak = 0
		for _, x in { -3.5, 0, 3.5 } do
			local last: number? = nil
			for z = z0, z1, 0.5 do
				local y = surface(colliders, x, z, 8)
				T.truthy(y, `bridge has ground at {x}, {z}`)
				if y then
					if last then
						T.truthy(math.abs(y - last) <= 1, `bridge step at {x}, {z}: {last} -> {y}`)
					end
					T.falsy(blocked(colliders, x, z, y + 0.25, y + 5), `headroom on the bridge at {x}, {z}`)
					peak = math.max(peak, y)
					last = y
				end
			end
		end
		T.truthy(peak >= 2, "the bridge arches over the creek")
		-- the creek under the bridge crosses the road's line: water never collides
		for _, part in parts(flora()) do
			if part.Name == "Water" then
				T.falsy(part.CanCollide, part:GetFullName() .. " water does not collide")
			end
		end
	end)

	T.test("flora: creek and ponds are water over solid ground", function()
		local colliders = collidersNear({ world().Land }, Vector3.new(-60, 0, 25), Vector3.new(40, 0, 75))
		for _, id in { "LilyPond", "KoiPond" } do
			local piece = LobbyLayout.get(id)
			local c = piece.Center
			for _, dx in { -0.3, 0, 0.3 } do
				for _, dz in { -0.25, 0, 0.25 } do
					local x, z = c.X + dx * piece.Size.X, c.Z + dz * piece.Size.Z
					local y = surface(colliders, x, z, 1)
					T.truthy(y and math.abs(y) < 0.3, `{id} has solid ground under the water at {x}, {z}`)
				end
			end
		end
	end)

	T.test("flora: the NEXT AREA boardwalk is walkable from the path", function()
		local bw = Signs.Boardwalk
		local colliders = collidersNear(
			{ flora().Wayfinding.NextAreaBoardwalk, world().Land },
			Vector3.new(bw.StartX - 4, 0, bw.Z - 4),
			Vector3.new(bw.EndX + 4, 0, bw.Z + 4)
		)
		local last: number? = nil
		for x = bw.StartX - 2, bw.EndX, 0.5 do
			for _, dz in { -2, 0, 2 } do
				local y = surface(colliders, x, bw.Z + dz, 12)
				T.truthy(y, `boardwalk has a floor at {x}, {bw.Z + dz}`)
			end
			local y = surface(colliders, x, bw.Z, 12)
			if y and last then
				T.truthy(math.abs(y - last) <= 1, `boardwalk step at x {x}: {last} -> {y}`)
			end
			last = y
		end
	end)

	T.test("flora: signpost boards read on both faces", function()
		local post = flora().Wayfinding.Signpost
		for _, text in { "MINE", "UPGRADE", "EXPLORE", "BUILD" } do
			local board = post:FindFirstChild(text .. "Board")
			T.truthy(board, "signpost board " .. text)
			if board then
				for _, face in { "FrontText", "BackText" } do
					local gui = board:FindFirstChild(face)
					local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
					T.truthy(label and label.Text == text, `{text} board has {face}`)
				end
			end
		end
		local next = flora().Wayfinding.NextArea
		T.truthy(next:FindFirstChild("NextAreaSign"), "NEXT AREA sign")
		T.truthy(next:FindFirstChild("SoonPlank", true), "closed gate with a SOON plank")
	end)

	T.test("flora: hero trees stand in their footprints", function()
		for _, id in { "PinkGrove", "RedTree", "AutumnCorner" } do
			local piece = LobbyLayout.get(id)
			local m = flora().HeroTrees[id]
			local trees = 0
			for _, d in m:GetChildren() do
				if d:IsA("Model") and d.Name == "Tree" then
					trees += 1
					local trunk = d:FindFirstChildWhichIsA("BasePart")
					local p = trunk.CFrame.Position
					T.truthy(LobbyLayout.distanceTo(piece, p) <= 0.01, `{id} tree trunk inside the footprint at {p}`)
					T.truthy(p.Y + trunk.Size.Y / 2 < piece.Size.Y, `{id} trunk under the height budget`)
				end
			end
			T.truthy(trees >= 1, id .. " has trees")
		end
	end)

	-- The XZ box of a part (world), as min/max Vector3s.
	local function boxOf(part): (any, any)
		local p, e = part.CFrame.Position, halfExtents(part)
		return Vector3.new(p.X - e.X, 0, p.Z - e.Z), Vector3.new(p.X + e.X, 0, p.Z + e.Z)
	end

	-- Ground points covering a part's XZ box (corners, edges and inside, at most 0.5 apart).
	local function boxSamples(part): { any }
		local lo, hi = boxOf(part)
		local nx = math.max(1, math.ceil((hi.X - lo.X) / 0.5))
		local nz = math.max(1, math.ceil((hi.Z - lo.Z) / 0.5))
		local out = {}
		for i = 0, nx do
			for j = 0, nz do
				table.insert(out, Vector3.new(lo.X + (hi.X - lo.X) * i / nx, 0, lo.Z + (hi.Z - lo.Z) * j / nz))
			end
		end
		return out
	end

	T.test("flora: the clear aprons in front of CAPSULES and ENCHANT stay empty", function()
		local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Kit")
		local ids = {}
		for _, apron in Kit.Aprons do
			ids[apron.Id] = true
			T.truthy(apron.Depth >= 4, `{apron.Id} keeps at least 4 studs clear`)
		end
		T.truthy(ids.CapsuleStall and ids.EnchantShop, "aprons in front of CAPSULES and ENCHANT")
		for _, part in parts(flora()) do
			for _, apron in Kit.Aprons do
				for _, q in boxSamples(part) do
					T.truthy(Kit.apronDistance(apron, q) > 0, `{part:GetFullName()} stands in front of {apron.Id} at {q}`)
				end
			end
		end
	end)

	T.test("flora: trees keep a stud off the stalls (fences, walls, signs)", function()
		local stalls = {}
		for _, piece in LobbyLayout.Pieces do
			if piece.Package == "Districts" and LobbyLayout.isGroundPiece(piece) then
				table.insert(stalls, piece)
			end
		end
		for _, d in flora():GetDescendants() do
			if d:IsA("Model") and d.Name == "Tree" then
				for _, part in parts(d) do
					for _, piece in stalls do
						local gap = math.huge
						for _, q in boxSamples(part) do
							gap = math.min(gap, LobbyLayout.distanceTo(piece, q))
						end
						T.truthy(gap >= 1, `{d:GetFullName()} is {gap} studs from {piece.Id} at {part.CFrame.Position}`)
					end
				end
			end
		end
	end)

	T.test("flora: town buildings stand on free ground inside their sites", function()
		local sites = Town.Sites
		T.truthy(#sites >= 8 and #sites <= 14, `8-14 town buildings ({#sites})`)
		local town = flora():FindFirstChild("Town")
		T.truthy(town, "Flora has Town")
		for i, site in sites do
			T.truthy(site.Min.X < site.Max.X and site.Min.Y < site.Max.Y, site.Id .. " has a proper rectangle")
			-- off the coastal rail line (world |x| 160..172) with room to spare
			T.truthy(site.Max.X < Town.RailMinX - 1 and site.Min.X > -Town.RailMinX + 1, site.Id .. " stays off the rail line")
			-- every point of the site is free ground (roads, paths, plots, yards, outcrops, keep-outs, pieces)
			for x = site.Min.X, site.Max.X + 1e-6, 1 do
				for z = site.Min.Y, site.Max.Y + 1e-6, 1 do
					local q = Vector3.new(x, 0, z)
					T.truthy(LobbyLayout.isFree(q, 1), `{site.Id}: ({x}, {z}) is not free ground`)
					for _, plot in WorldLayout.Plots do
						local localPos = WorldLayout.plotCFrame(plot):PointToObjectSpace(Vector3.new(x, plot.Center.Y, z))
						local inYard = math.abs(localPos.X) < 28 and localPos.Z >= 25 and localPos.Z <= 66
						T.falsy(inYard, `{site.Id}: ({x}, {z}) is in the yard of base {plot.Id}`)
					end
				end
			end
			-- sites never overlap each other
			for j = i + 1, #sites do
				local o = sites[j]
				local apart = site.Max.X <= o.Min.X or o.Max.X <= site.Min.X or site.Max.Y <= o.Min.Y or o.Max.Y <= site.Min.Y
				T.truthy(apart, `{site.Id} overlaps {o.Id}`)
			end
			-- the building stays inside its site, glows with Neon windows and has no lights
			local m = town and town:FindFirstChild(site.Id)
			T.truthy(m, "town building " .. site.Id)
			if m then
				local glows, count = 0, 0
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						count += 1
						local lo, hi = boxOf(d)
						local inside = lo.X >= site.Min.X - 0.05
							and hi.X <= site.Max.X + 0.05
							and lo.Z >= site.Min.Y - 0.05
							and hi.Z <= site.Max.Y + 0.05
						T.truthy(inside, `{d:GetFullName()} pokes out of its site ({lo} .. {hi})`)
						if d.Name == "WindowGlow" then
							glows += 1
							T.truthy(d.Material == roblox.Enum.Material.Neon, d:GetFullName() .. " window glow is Neon")
						end
						-- small details (frames, panes, lamps, posts, bolts) cast no shadow
						if math.max(d.Size.X, d.Size.Y, d.Size.Z) < 1.2 or d.Material == roblox.Enum.Material.Neon then
							T.falsy(d.CastShadow, d:GetFullName() .. " small part casts no shadow")
						end
					elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
						T.truthy(false, d:GetFullName() .. ": town buildings glow with Neon, no lights")
					end
				end
				T.truthy(glows >= 3, `{site.Id} has lit windows ({glows})`)
				T.truthy(count <= 100, `{site.Id} part count {count} <= 100`)
			end
		end
	end)

	-- Is a world point inside a part's box (conservative for cylinders, balls and wedges)?
	local function contains(part, p): boolean
		local q = part.CFrame:PointToObjectSpace(p)
		local size = part.Size
		return math.abs(q.X) <= size.X / 2 and math.abs(q.Y) <= size.Y / 2 and math.abs(q.Z) <= size.Z / 2
	end

	local LOOK = {
		N = Vector3.new(0, 0, -1),
		S = Vector3.new(0, 0, 1),
		E = Vector3.new(1, 0, 0),
		W = Vector3.new(-1, 0, 0),
	}

	T.test("flora: town signs are readable and face the town", function()
		local town = flora().Town
		local texts = {}
		for _, site in Town.Sites do
			local m = town:FindFirstChild(site.Id)
			if site.Sign and m then
				local found = false
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d.Name == "TownSign" then
						local gui = d:FindFirstChild("FrontText")
						local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
						if label and label.Text == site.Sign then
							found = true
							texts[label.Text] = true
							-- dark navy board, white letters (high contrast like TOOLS / UPGRADES)
							local b = d.Color
							T.truthy(b.R + b.G + b.B < 0.6, `{site.Sign} board is dark`)
							local c = label.TextColor3
							T.truthy(c.R + c.G + c.B > 2.7, `{site.Sign} text is white`)
							T.truthy(d.Material ~= roblox.Enum.Material.Neon, `{site.Sign} board does not glow`)
							-- the sign looks out of the facade (toward the town, not into a wall)
							local look = d.CFrame.LookVector
							T.truthy(look:Dot(LOOK[site.Facing]) > 0.7, `{site.Sign} sign faces {site.Facing}`)
						end
					end
				end
				T.truthy(found, `{site.Id} has its {site.Sign} sign`)
			end
		end
		for _, text in { "TOOLS", "INN", "MAP", "ORE", "WORKS", "CARTS" } do
			T.truthy(texts[text], "town sign " .. text)
		end
		-- big glowing planes bloom to white in the renders: every Neon face stays small
		for _, part in parts(town) do
			if part.Material == roblox.Enum.Material.Neon then
				local x, y, z = part.Size.X, part.Size.Y, part.Size.Z
				local face = math.max(x * y, y * z, x * z)
				T.truthy(face <= 6.5, `{part:GetFullName()} neon face {face} <= 6.5 studs^2`)
			end
		end
	end)

	T.test("flora: every Flora section keeps off the town buildings", function()
		local f = flora()
		for _, section in f:GetChildren() do
			if section.Name ~= "Town" then
				for _, part in parts(section) do
					local lo, hi = boxOf(part)
					for _, site in Town.Sites do
						local apart = hi.X <= site.Min.X or lo.X >= site.Max.X or hi.Z <= site.Min.Y or lo.Z >= site.Max.Y
						T.truthy(apart, `{part:GetFullName()} overlaps the town building {site.Id}`)
					end
				end
			end
		end
		-- the scatter keeps the ground in front of every facade clear too
		for _, part in parts(f.Scatter) do
			local lo, hi = boxOf(part)
			for _, site in Town.Sites do
				local strip = Town.frontStrip(site, Town.FrontClearance)
				local apart = hi.X <= strip.Min.X or lo.X >= strip.Max.X or hi.Z <= strip.Min.Y or lo.Z >= strip.Max.Y
				T.truthy(apart, `{part:GetFullName()} stands in front of the town building {site.Id}`)
			end
		end
	end)

	T.test("flora: the ground in front of every town facade is clear", function()
		local map = world()
		local f = flora()
		-- other packages' parts that rise above the ground (y > 1) near the town
		local others = {}
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(f) then
				local p, e = d.CFrame.Position, halfExtents(d)
				if p.Y + e.Y > 1 and p.Y - e.Y < 14 and math.abs(p.X) < 120 then
					table.insert(others, d)
				end
			end
		end
		for _, site in Town.Sites do
			local strip = Town.frontStrip(site, Town.FrontClearance)
			local near = {}
			for _, d in others do
				local p, e = d.CFrame.Position, halfExtents(d)
				if p.X + e.X >= strip.Min.X and p.X - e.X <= strip.Max.X and p.Z + e.Z >= strip.Min.Y and p.Z - e.Z <= strip.Max.Y then
					table.insert(near, d)
				end
			end
			for x = strip.Min.X + 0.25, strip.Max.X - 0.24, 0.5 do
				for z = strip.Min.Y + 0.25, strip.Max.Y - 0.24, 0.5 do
					for _, y in { 1.25, 2.5, 4, 6, 9, 12 } do
						local q = Vector3.new(x, y, z)
						for _, d in near do
							T.falsy(contains(d, q), `{d:GetFullName()} stands in front of {site.Id} at {q}`)
						end
					end
				end
			end
		end
		-- and every site keeps 2.5 studs from the stalls and set pieces (no 1-2 stud alleys)
		for _, site in Town.Sites do
			for _, piece in LobbyLayout.Pieces do
				if piece.Package ~= "Flora" and LobbyLayout.isGroundPiece(piece) then
					local gap = math.huge
					for x = site.Min.X, site.Max.X + 1e-6, 0.5 do
						for _, z in { site.Min.Y, site.Max.Y } do
							gap = math.min(gap, LobbyLayout.distanceTo(piece, Vector3.new(x, 0, z)))
						end
					end
					for z = site.Min.Y, site.Max.Y + 1e-6, 0.5 do
						for _, x in { site.Min.X, site.Max.X } do
							gap = math.min(gap, LobbyLayout.distanceTo(piece, Vector3.new(x, 0, z)))
						end
					end
					T.truthy(gap >= 2.5, `{site.Id} is {gap} studs from {piece.Id} (>= 2.5)`)
				end
			end
		end
	end)

	T.test("flora: town blade signs, sign sizes, lanterns and windows", function()
		local town = flora().Town
		for _, site in Town.Sites do
			local m = town:FindFirstChild(site.Id)
			if m then
				local front = Town.footprint(site).w
				-- the main sign is big (about the facade's width, boards >= 3.2 tall) and hangs on the first
				-- storey (the MAP tower's on its top storey, over CAPSULES and the trees)
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d.Name == "TownSign" then
						local y = d.CFrame.Position.Y
						local top = if site.Id == "MapTower" then 17.5 else 12.5
						T.truthy(y >= 9 and y <= top, `{site.Id} sign on the first storey (y {y})`)
						T.truthy(d.Size.Y >= 3.2 - 1e-3, `{site.Id} sign board is at least 3.2 tall ({d.Size})`)
						local span = d:GetAttribute("Span") or d.Size.X
						local want = if site.Id == "Inn" then 6.5 else 0.7 * front
						T.truthy(span >= want - 1e-3, `{site.Id} sign spans {span} of a {front} wide site (>= {want})`)
					end
				end
				-- double-sided blade signs turned to the hero (south) / the street, perpendicular to the facade
				if site.Blade then
					local blade = m:FindFirstChild("BladeSign", true)
					T.truthy(blade, `{site.Id} has a blade sign`)
					if blade then
						for _, faceName in { "FrontText", "BackText" } do
							local gui = blade:FindFirstChild(faceName)
							local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
							T.truthy(label and label.Text == site.Sign, `{site.Id} blade sign reads {site.Sign} on {faceName}`)
						end
						local look = blade.CFrame.LookVector
						T.truthy(math.abs(look:Dot(LOOK[site.Facing])) < 0.3, `{site.Id} blade sign is perpendicular to the facade`)
						T.truthy(look:Dot(LOOK.S) > 0.7 or look:Dot(LOOK.W) > 0.7, `{site.Id} blade sign faces south or west`)
						T.truthy(
							blade.Size.X >= 6.5 - 1e-3 and blade.Size.Y >= 3 - 1e-3,
							`{site.Id} blade sign is at least 6.5 x 3 ({blade.Size})`
						)
					end
				end
				-- windows: lit panes glow, at most one unlit pane in six, unlit glass is light blue (never a black hole)
				local lit, dark = 0, 0
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						if d.Name == "WindowGlow" then
							lit += 1
						elseif d.Name == "Window" then
							dark += 1
							local c = d.Color
							T.truthy(c.R + c.G + c.B > 0.95, `{d:GetFullName()} unlit glass is not black`)
						elseif d.Name == "LanternGlow" then
							-- caged deep-amber lamps: small, no white blob
							T.truthy(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 0.6, `{d:GetFullName()} lantern cube is small`)
							T.truthy(d.Color.G < 0.7 and d.Color.B < 0.35, `{d:GetFullName()} lantern is deep amber`)
						elseif d.Material == roblox.Enum.Material.Neon and d.Size.X <= 0.45 and d.Size.Y <= 0.45 and d.Size.Z <= 0.45 then
							-- rooftop beacons are small dots, never a white cube
							T.truthy(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 0.35, `{d:GetFullName()} beacon is a small dot`)
						end
					end
				end
				T.truthy(dark * 5 <= lit, `{site.Id}: {dark} unlit panes for {lit} lit ones (at most 1 in 6)`)
			end
		end
	end)

	T.test("flora: town buildings are 2-3 storeys at avatar scale", function()
		for _, site in Town.Sites do
			local m = flora().Town:FindFirstChild(site.Id)
			local top, doors = 0, 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					if d.CanCollide then
						top = math.max(top, d.CFrame.Position.Y + halfExtents(d).Y)
					end
					-- street doors fit an R15 avatar (~5.2 studs): at least 6 tall and 3 wide
					if d.Name == "Door" then
						doors += 1
						T.truthy(d.Size.Y >= 6 - 1e-3 and d.Size.X >= 3 - 1e-3, `{d:GetFullName()} door is at least 3 x 6 ({d.Size})`)
					end
				end
			end
			T.truthy(top >= 14 and top <= 27, `{site.Id} is {top} studs tall (2-3 storeys: 14-27)`)
			T.truthy(doors >= 1, `{site.Id} has a street door`)
		end
	end)

	-- The six faces of a block part: outward normal, center, the two in-plane axes and half sizes.
	local function blockFaces(part): { any }
		local cf, size = part.CFrame, part.Size
		local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
		local half = { size.X / 2, size.Y / 2, size.Z / 2 }
		local out = {}
		for i = 1, 3 do
			for _, sign in { -1, 1 } do
				local n = axes[i] * sign
				table.insert(out, {
					n = n,
					c = cf.Position + n * half[i],
					u = axes[i % 3 + 1],
					v = axes[(i + 1) % 3 + 1],
					hu = half[i % 3 + 1],
					hv = half[(i + 1) % 3 + 1],
				})
			end
		end
		return out
	end

	-- Overlap area of two coplanar face rectangles (b projected into a's axes; exact when aligned).
	local function faceOverlap(a, b): number
		local d = b.c - a.c
		local cu, cv = d:Dot(a.u), d:Dot(a.v)
		local eu = math.abs(b.u:Dot(a.u)) * b.hu + math.abs(b.v:Dot(a.u)) * b.hv
		local ev = math.abs(b.u:Dot(a.v)) * b.hu + math.abs(b.v:Dot(a.v)) * b.hv
		local ou = math.min(a.hu, cu + eu) - math.max(-a.hu, cu - eu)
		local ov = math.min(a.hv, cv + ev) - math.max(-a.hv, cv - ev)
		if ou <= 0 or ov <= 0 then
			return 0
		end
		return ou * ov
	end

	T.test("flora: no z-fighting in the town (same-facing coplanar faces of different colours)", function()
		for _, building in flora().Town:GetChildren() do
			local blocks = {}
			for _, d in building:GetDescendants() do
				if d:IsA("Part") and d.Shape == roblox.Enum.PartType.Block then
					table.insert(blocks, d)
				end
			end
			local faces = {}
			for i, part in blocks do
				faces[i] = blockFaces(part)
			end
			for i = 1, #blocks do
				for j = i + 1, #blocks do
					local a, b = blocks[i], blocks[j]
					local reach = (a.Size.Magnitude + b.Size.Magnitude) / 2
					if (a.Color ~= b.Color or a.Material ~= b.Material) and (a.CFrame.Position - b.CFrame.Position).Magnitude <= reach then
						for _, fa in faces[i] do
							for _, fb in faces[j] do
								-- downward faces at ground level face the terrain and never show
								local ground = fa.n.Y < -0.99 and fa.c.Y < 0.1
								if not ground and fa.n:Dot(fb.n) > 0.999 and math.abs(fa.n:Dot(fb.c - fa.c)) < 0.01 then
									local area = faceOverlap(fa, fb)
									T.truthy(area <= 0.004, `{a:GetFullName()} and {b.Name} share a face plane at {fa.c} ({area} studs^2)`)
								end
							end
						end
					end
				end
			end
		end
	end)

	T.test("flora: deterministic build", function()
		local function signature(): (number, number)
			local m = roblox.Instance.new("Model")
			Flora.build(m, Rng.new("Lobby/Flora/test"))
			local count, sum = 0, 0
			for _, part in parts(m) do
				count += 1
				local p = part.CFrame.Position
				sum += p.X * 0.37 + p.Y * 1.3 + p.Z * 0.71
			end
			return count, sum
		end
		local c1, s1 = signature()
		local c2, s2 = signature()
		T.eq(c1, c2, "same part count")
		T.near(s1, s2, 1e-6, "same positions")
	end)
end
