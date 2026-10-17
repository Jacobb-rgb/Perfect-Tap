--[[
	Lobby package "Sky" (src/server/World/Lobby/Sky, docs/plans/LOBBY_PLAN.md
	6.1, docs/plans/VISUAL_UPGRADE_PLAN.md): every set piece is built inside
	its LobbyLayout footprint and part budget; the clouds stay out of the
	lobby area and are puffy cumulus mounds with lit undersides, grouped
	into banks at many heights (no planks, nothing cut by the hero frame's
	edges, clear of the balloon); the three planets hang far out in the
	north-west..north-east sky, big, in the Kenney sprites' colors AFTER the
	evening haze (the preview's fog + tone mapping model), with streak
	camouflage, latitude bands and a light ring, never in front of the sun,
	at most a quarter hidden from the spawn behind anything in the built
	world (massif, islands, buildings, clouds, airship; ring included); the
	airship is a cheap bobbing Spin model tapering from a ball nose to a
	finned tail with a thin magenta jet; the balloon and the ships are
	tagged Spin; the build is deterministic; and the golden-hour Lighting in
	default.project.json is identical to LightingConfig.Presets.Surface.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local serde = require("@lune/serde")
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Sky = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky")
	local Planets = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.Planets")
	local Airship = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.Airship")
	local Clouds = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.Clouds")
	local Sea = Loader.requirePath("ServerScriptService.Server.World.Lobby.Sky.Sea")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	-- part budgets per piece (LOBBY_PLAN 6.1) and the pieces that may own a light
	local PIECE_PARTS = {
		CloudBanks = 350,
		SunGlitter = 120,
		ShipA = 90,
		ShipB = 60,
		CastleIsland = 90,
		FloatingIslandWest = 170,
		FloatingIslandEast = 200,
		NextIsland = 170,
		Balloon = 80,
		WestPier = 90,
	}
	local PIECE_LIGHTS = { Balloon = 1, NextIsland = 1, WestPier = 1 }
	-- the sky pieces that are not LobbyLayout pieces (built after them)
	local EXTRAS = { Planets = 3 * 40, Airship = 70 }

	-- the same random stream Town.build gives the package
	local function build(): any
		local game = roblox.Instance.new("DataModel")
		local root = roblox.Instance.new("Model")
		root.Name = "Sky"
		root.Parent = game:GetService("Workspace")
		Sky.build(root, Rng.new(`Lobby/Sky/{WorldLayout.Seed}`))
		return root
	end

	local function corners(part: any): { any }
		local out = {}
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(out, part.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
				end
			end
		end
		return out
	end

	local function parts(m: any): { any }
		local out = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function lights(m: any): { any }
		local out = {}
		for _, d in m:GetDescendants() do
			if (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Parent and d.Parent:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	T.test("sky: Replaces nothing and builds one model per Sky piece", function()
		T.eq(#Sky.Replaces, 0, "Sky replaces no legacy piece")
		local root = build()
		for _, piece in LobbyLayout.ofPackage("Sky") do
			local m = root:FindFirstChild(piece.Id)
			T.truthy(m and m:IsA("Model"), "model " .. piece.Id)
			T.truthy(#parts(m) > 0, piece.Id .. " has parts")
		end
	end)

	T.test("sky: every piece stays inside its footprint", function()
		local root = build()
		for _, piece in LobbyLayout.ofPackage("Sky") do
			local frame = LobbyLayout.frame(piece)
			local hx, hz = piece.Size.X / 2 + 1.5, piece.Size.Z / 2 + 1.5
			-- floating pieces hang below their ground point and stand on it
			local minY, maxY = piece.Center.Y - piece.Size.Y - 1, piece.Center.Y + piece.Size.Y + 1
			for _, part in parts(root:FindFirstChild(piece.Id)) do
				for _, p in corners(part) do
					local l = frame:PointToObjectSpace(p)
					if math.abs(l.X) > hx or math.abs(l.Z) > hz or p.Y < minY or p.Y > maxY then
						T.truthy(false, `{piece.Id}: {part:GetFullName()} pokes out of the footprint at {p}`)
						return
					end
				end
			end
		end
	end)

	T.test("sky: part and light budgets per piece and for the package", function()
		local root = build()
		local total, inLobby, lightCount, lobbyLights = 0, 0, 0, 0
		for _, piece in LobbyLayout.ofPackage("Sky") do
			local m = root:FindFirstChild(piece.Id)
			local list = parts(m)
			T.truthy(PIECE_PARTS[piece.Id], "budget for " .. piece.Id)
			T.le(#list, PIECE_PARTS[piece.Id] or 0, piece.Id .. " parts")
			total += #list
			for _, part in list do
				if LobbyLayout.inArea(part.CFrame.Position) then
					inLobby += 1
				end
			end
			local ls = lights(m)
			T.le(#ls, PIECE_LIGHTS[piece.Id] or 0, piece.Id .. " lights")
			lightCount += #ls
			for _, light in ls do
				T.falsy(light.Shadows, piece.Id .. " light casts no shadows")
				if LobbyLayout.inArea(light.Parent.CFrame.Position) then
					lobbyLights += 1
				end
			end
		end
		for id, maxParts in EXTRAS do
			local m = root:FindFirstChild(id)
			T.truthy(m and m:IsA("Model"), "model " .. id)
			local list = parts(m)
			T.le(#list, maxParts, id .. " parts")
			total += #list
			for _, part in list do
				if LobbyLayout.inArea(part.CFrame.Position) then
					inLobby += 1
				end
			end
			T.eq(#lights(m), 0, id .. " has no lights (neon glows)")
		end
		local budget = LobbyLayout.Budget.Packages.Sky
		T.le(total, budget.Parts, "Sky parts")
		T.le(inLobby, budget.LobbyParts, "Sky parts in the lobby area")
		T.le(lightCount, budget.Lights, "Sky lights")
		T.le(lobbyLights, budget.LobbyLights, "Sky lights in the lobby area")
	end)

	T.test("sky: clouds stay out of the lobby area, everything is anchored unreachable decor", function()
		local root = build()
		local area = LobbyLayout.Area
		for _, part in parts(root.CloudBanks) do
			for _, p in corners(part) do
				local inside = p.X > area.Min.X and p.X < area.Max.X and p.Z > area.Min.Z and p.Z < area.Max.Z
				T.falsy(inside, "cloud part over the lobby area at " .. tostring(p))
			end
			T.falsy(part.CanCollide, "clouds never collide")
			T.falsy(part.CastShadow, "clouds cast no shadow")
		end
		for _, part in parts(root) do
			T.truthy(part.Anchored, part:GetFullName() .. " is anchored")
			if part.Material == roblox.Enum.Material.Neon then
				T.falsy(part.CastShadow, part:GetFullName() .. " neon casts no shadow")
			end
			if LobbyLayout.inArea(part.CFrame.Position) then
				T.falsy(part.CanCollide, part:GetFullName() .. " floats over the town without colliding")
			end
		end
		-- the glitter lies on the sea surface (Land: sea top at y -21): deep
		-- gold / deep orange and translucent, so it stays a gold path under
		-- the bloom instead of burning white
		for _, part in parts(root.SunGlitter) do
			T.eq(part.Material, roblox.Enum.Material.Neon, "glitter is neon")
			T.truthy(math.abs(part.CFrame.Position.Y + part.Size.Y / 2 + 20.85) < 0.01, "glitter top at y -20.85")
			T.truthy(part.Transparency >= 0.5 and part.Transparency <= 0.62, "glitter transparency")
			T.truthy(part.Color == Sea.Glitter.Gold or part.Color == Sea.Glitter.Edge, "glitter is deep gold / orange")
			T.truthy(part.Color.G < 0.62 and part.Color.B < 0.2, "glitter is not a pale (white-burning) tone")
		end
	end)

	T.test("sky: balloon, ships and airship are tagged Spin and stream as one piece", function()
		local root = build()
		local expected = {
			Balloon = { SpinSpeed = 0.05, BobHeight = 2, BobSpeed = 0.5 },
			ShipA = { SpinSpeed = 0, BobHeight = 0.5, BobSpeed = 0.8 },
			ShipB = { SpinSpeed = 0, BobHeight = 0.5, BobSpeed = 0.8 },
			Airship = { SpinSpeed = 0, BobHeight = 3, BobSpeed = 0.35 },
		}
		-- the airship hangs ~400 studs out, at the 384-stud StreamingTargetRadius:
		-- Persistent, so it never pops in and out (still one piece)
		local mode = {
			Balloon = roblox.Enum.ModelStreamingMode.Atomic,
			ShipA = roblox.Enum.ModelStreamingMode.Atomic,
			ShipB = roblox.Enum.ModelStreamingMode.Atomic,
			Airship = roblox.Enum.ModelStreamingMode.Persistent,
		}
		for id, attrs in expected do
			local m = root:FindFirstChild(id)
			T.truthy(table.find(m:GetTags(), "Spin"), id .. " is tagged Spin")
			T.truthy(m.PrimaryPart and m.PrimaryPart:IsDescendantOf(m), id .. " has a PrimaryPart")
			T.eq(m.ModelStreamingMode, mode[id], id .. " streaming mode")
			for name, value in attrs do
				T.near(m:GetAttribute(name), value, 1e-6, `{id} {name}`)
			end
		end
		T.eq(root.Balloon.PrimaryPart.Name, "Basket", "the balloon turns around its basket")
		local burner = root.Balloon:FindFirstChild("Burner")
		T.truthy(burner and burner:FindFirstChildOfClass("PointLight"), "the burner carries the balloon's light")
		for _, id in { "CloudBanks", "SunGlitter" } do
			T.eq(root[id].ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent, id .. " is always streamed")
		end
		-- nothing else spins
		for _, d in root:GetDescendants() do
			if d:IsA("Model") and table.find(d:GetTags(), "Spin") then
				T.truthy(expected[d.Name], d:GetFullName() .. " is an expected spinner")
			end
		end
	end)

	local function luminance(c: any): number
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	-- Preview cameras (tools/preview/lobby_shots.json, rendered 1600 x 900).
	local shots = serde.decode("json", fs.readFile(process.cwd .. "/tools/preview/lobby_shots.json"))
	local ASPECT = 1600 / 900
	local function camera(name: string): (any, number)
		local s = shots[name]
		local position = Vector3.new(s.position[1], s.position[2], s.position[3])
		local target = Vector3.new(s.target[1], s.target[2], s.target[3])
		-- Loader.CFrame: the shim with the Roblox lookAt (Lune 0.8.9 negates its Z)
		return Loader.CFrame.lookAt(position, target), math.tan(math.rad(s.fov / 2))
	end
	-- normalized screen position (-1..1 inside the frame), or nil behind the camera
	local function project(cf: any, tanY: number, p: any): (number?, number?)
		local l = cf:PointToObjectSpace(p)
		if l.Z >= -0.1 then
			return nil, nil
		end
		return l.X / -l.Z / (tanY * ASPECT), l.Y / -l.Z / tanY
	end

	-- A crease between two intersecting balls (offsets from the planet center)
	-- is visible if part of their intersection circle faces the town and is
	-- not buried inside a third ball.
	local function creaseVisible(balls: { any }, i: number, j: number, toTown: any): boolean
		local a, b = balls[i], balls[j]
		local dvec = b.Offset - a.Offset
		local dist = dvec.Magnitude
		local u = dvec.Unit
		local x = (dist * dist + a.Radius * a.Radius - b.Radius * b.Radius) / (2 * dist)
		local h = math.sqrt(math.max(0, a.Radius * a.Radius - x * x))
		local e1 = u:Cross(Vector3.new(0, 1, 0))
		if e1.Magnitude < 1e-3 then
			e1 = u:Cross(Vector3.new(1, 0, 0))
		end
		e1 = e1.Unit
		local e2 = u:Cross(e1).Unit
		for k = 0, 23 do
			local t = k / 24 * 2 * math.pi
			local q = a.Offset + u * x + (e1 * math.cos(t) + e2 * math.sin(t)) * h
			if q:Dot(toTown) > 0 then
				local buried = false
				for n, c in balls do
					if n ~= i and n ~= j and (q - c.Offset).Magnitude < c.Radius - 0.5 then
						buried = true
						break
					end
				end
				if not buried then
					return true
				end
			end
		end
		return false
	end

	-- Does the segment from `origin` to `target` pass through the box (cf, size)?
	local function rayHitsBox(origin: any, target: any, cf: any, size: any): boolean
		local o = cf:PointToObjectSpace(origin)
		local d = cf:PointToObjectSpace(target) - o
		local half = size / 2
		local tmin, tmax = 0, 1
		for _, axis in { "X", "Y", "Z" } do
			local oa, da, h = o[axis], d[axis], half[axis]
			if math.abs(da) < 1e-9 then
				if math.abs(oa) > h then
					return false
				end
			else
				local t1, t2 = (-h - oa) / da, (h - oa) / da
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
				if tmin > tmax then
					return false
				end
			end
		end
		return true
	end

	-- Fraction of the town-facing disc of a planet covered by caps (the
	-- nearest opaque ball along each line of sight is not the body).
	local function coverage(balls: { any }, toTown: any, radius: number): number
		local e1 = toTown:Cross(Vector3.new(0, 1, 0)).Unit
		local e2 = e1:Cross(toTown).Unit
		local covered, total = 0, 0
		for i = -12, 12 do
			for j = -12, 12 do
				local u, v = i / 12, j / 12
				if u * u + v * v <= 0.98 then
					total += 1
					-- a ray from far in front of the face straight back at the planet
					local o = toTown * radius * 4 + (e1 * u + e2 * v) * radius
					local d = -toTown
					local best, name = math.huge, "Body"
					for _, b in balls do
						local oc = o - b.Offset
						local bb = oc:Dot(d)
						local disc = bb * bb - (oc:Dot(oc) - b.Radius * b.Radius)
						if disc >= 0 then
							local t = -bb - math.sqrt(disc)
							if t < best then
								best, name = t, b.Name
							end
						end
					end
					if name ~= "Body" then
						covered += 1
					end
				end
			end
		end
		return covered / total
	end

	---------------------------------------------------------------- clouds

	-- solid cloud blocks of a cluster (the thin lit skirts aside)
	local function cloudSolids(cloud: any): { any }
		local out = {}
		for _, part in parts(cloud) do
			if part.Name ~= "Skirt" then
				table.insert(out, part)
			end
		end
		return out
	end

	T.test("sky: clouds are rounded cumulus mounds with lit undersides, no planks", function()
		local root = build()
		local clusters = 0
		local lowBase, highBase, smallest, largest = math.huge, -math.huge, math.huge, 0
		for _, cloud in root.CloudBanks:GetChildren() do
			local name = cloud:GetFullName()
			T.eq(cloud.Name, "Cloud", name .. " is a cumulus cluster (no stratus planks)")
			clusters += 1
			local list = parts(cloud)
			T.truthy(#list >= 20 and #list <= 26, name .. " is a stacked cluster, not a slab")
			-- the cluster frame: every block shares its yaw
			local frame = list[1].CFrame - list[1].CFrame.Position
			local sheets, solids = {}, {}
			for _, part in list do
				if part.Material == roblox.Enum.Material.Neon and part.Size.Y < 0.5 then
					table.insert(sheets, part)
				else
					table.insert(solids, part)
				end
			end
			-- the lit skirts: translucent Neon sheets a clear stud under the block above them
			T.truthy(#sheets >= 6, name .. " has a lit skirt under every puff")
			for _, sheet in sheets do
				T.eq(sheet.Name, "Skirt", name .. " sheet is a skirt")
				T.truthy(sheet.Transparency >= 0.3 and sheet.Transparency <= 0.45, name .. " skirt glows (Transparency 0.3-0.45)")
				local top = sheet.CFrame.Position.Y + sheet.Size.Y / 2
				local above = math.huge
				for _, part in solids do
					local l = part.CFrame:PointToObjectSpace(sheet.CFrame.Position)
					local bottom = part.CFrame.Position.Y - part.Size.Y / 2
					if math.abs(l.X) <= part.Size.X / 2 and math.abs(l.Z) <= part.Size.Z / 2 and bottom > top then
						above = math.min(above, bottom)
					end
				end
				T.truthy(above < math.huge, name .. " skirt hangs under a block")
				T.truthy(above - top >= 1 and above - top <= 1.5, `{name} skirt is {above - top} studs under its block`)
			end
			-- no plank: every solid block at most 6x as long as it is tall
			for _, part in solids do
				local long = math.max(part.Size.X, part.Size.Z)
				T.truthy(long <= 6 * part.Size.Y, `{name} block {part.Size} is a plank`)
			end
			local minY, maxY = math.huge, -math.huge
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, part in solids do
				local p = part.CFrame.Position
				local half = part.Size.Y / 2
				minY = math.min(minY, p.Y - half)
				maxY = math.max(maxY, p.Y + half)
				local l = frame:PointToObjectSpace(p)
				minX, maxX = math.min(minX, l.X - part.Size.X / 2), math.max(maxX, l.X + part.Size.X / 2)
				minZ, maxZ = math.min(minZ, l.Z - part.Size.Z / 2), math.max(maxZ, l.Z + part.Size.Z / 2)
			end
			local height, width, depth = maxY - minY, maxX - minX, maxZ - minZ
			lowBase, highBase = math.min(lowBase, minY), math.max(highBase, minY)
			smallest, largest = math.min(smallest, width), math.max(largest, width)
			-- a mound, not a slab: tall and deep for its width
			T.truthy(height > 0.45 * width, `{name} is puffy ({height} tall, {width} wide)`)
			T.truthy(depth > 0.6 * width, `{name} has a deep footprint ({depth} deep, {width} wide)`)
			-- a stepped, lumpy underside: the low blocks sit at several heights
			local bottoms: { [number]: boolean } = {}
			local steps = 0
			for _, part in solids do
				local bottom = part.CFrame.Position.Y - part.Size.Y / 2
				local key = math.floor(bottom + 0.5)
				if bottom < minY + height * 0.2 and not bottoms[key] then
					bottoms[key] = true
					steps += 1
				end
			end
			T.truthy(steps >= 3, `{name} has a stepped underside ({steps} levels)`)
			-- the top is the lightest tone (lit by the sky), never the purple shade
			local topPart = solids[1]
			for _, part in solids do
				if part.CFrame.Position.Y + part.Size.Y / 2 > topPart.CFrame.Position.Y + topPart.Size.Y / 2 then
					topPart = part
				end
			end
			T.truthy(luminance(topPart.Color) > 0.7, `{name} has a lit top ({tostring(topPart.Color)})`)
			for _, sheet in sheets do
				T.truthy(sheet.CFrame.Position.Y < minY + height * 0.3, name .. " skirt sits under the cloud")
			end
		end
		T.eq(clusters, #Clouds.Spots, "one cluster per spot")
		T.truthy(clusters >= 12, "a dozen or more cloud clusters")
		-- many heights and sizes, not one row of look-alike piles
		T.truthy(highBase - lowBase >= 200, `cloud bases spread over {highBase - lowBase} studs of height`)
		T.truthy(largest >= 2.5 * smallest, `cloud sizes vary ({smallest}..{largest} wide)`)
	end)

	T.test("sky: clouds gather into banks: low banks on both hero horizons, loose high banks", function()
		-- the high clusters (over the plaza) are grouped: each has a neighbour
		-- within 12 degrees of bearing, and they form at most three banks
		local high = {}
		for _, spot in Clouds.Spots do
			if spot.Y >= 180 then
				table.insert(high, spot.Az % 360)
			end
		end
		table.sort(high, function(a, b)
			return ((a + 180) % 360) < ((b + 180) % 360)
		end)
		local banks = 0
		for i, az in high do
			local near = false
			for j, other in high do
				local diff = math.abs(((az - other + 180) % 360) - 180)
				if i ~= j and diff <= 12 then
					near = true
				end
			end
			T.truthy(near, `high cloud at bearing {az} has a neighbour in its bank`)
			local prev = high[i - 1]
			if not prev or math.abs(((az - prev + 180) % 360) - 180) > 12 then
				banks += 1
			end
		end
		T.truthy(banks >= 2 and banks <= 3, `high clouds form 2-3 banks ({banks})`)
		-- low banks the hero camera sees on the horizon on both sides of the massif
		local root = build()
		local cf, tanY = camera("lobby_hero")
		local left, right = 0, 0
		for _, cloud in root.CloudBanks:GetChildren() do
			local inside, xs = true, 0
			local list = cloudSolids(cloud)
			for _, part in list do
				local x, y = project(cf, tanY, part.CFrame.Position)
				if not (x and y and math.abs(x) <= 1 and math.abs(y) <= 1) then
					inside = false
					break
				end
				xs += x
			end
			if inside then
				if xs / #list < -0.4 then
					left += 1
				elseif xs / #list > 0.4 then
					right += 1
				end
			end
		end
		T.truthy(left >= 1 and right >= 1, `hero horizon banks left {left}, right {right}`)
	end)

	-- Every cloud is either wholly inside the hero frame or wholly outside it
	-- (no cloud cut by its top or side edges).
	T.test("sky: no cloud is cut by the edges of the hero shot", function()
		local root = build()
		local cf, tanY = camera("lobby_hero")
		for _, cloud in root.CloudBanks:GetChildren() do
			local inside, outside = 0, 0
			for _, part in cloudSolids(cloud) do
				for _, p in corners(part) do
					local x, y = project(cf, tanY, p)
					if x and y and math.abs(x) <= 1 and math.abs(y) <= 1 then
						inside += 1
					else
						outside += 1
					end
				end
			end
			T.falsy(inside > 0 and outside > 0, `{cloud:GetFullName()} is cut by the hero frame's edge`)
		end
	end)

	---------------------------------------------------------------- planets

	-- The preview's look of a far Neon part after the evening haze
	-- (tools/preview/viewer.js: Atmosphere fog mixed toward Color / Decay by
	-- the bearing to the sun, Neon x2.2, ACES tone mapping, ColorCorrection).
	local function s2l(c: number): number
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	local function l2s(c: number): number
		c = math.max(c, 0)
		return if c <= 0.0031308 then c * 12.92 else 1.055 * c ^ (1 / 2.4) - 0.055
	end
	local function linear(c: any): { number }
		return { s2l(c.R), s2l(c.G), s2l(c.B) }
	end
	local function hazed(color: any, eye: any, point: any): { number }
		local preset = LightingConfig.Presets.Surface
		local atm, cc = preset.Atmosphere, preset.ColorCorrection
		local density = atm.Density * 0.0019 * (1 + 0.35 * atm.Haze)
		local f = 1 - math.exp(-(density * (point - eye).Magnitude) ^ 2)
		local flat = Vector3.new(point.X - eye.X, 0, point.Z - eye.Z).Unit
		local sun = Vector3.new(LobbyLayout.SunDirection.X, 0, LobbyLayout.SunDirection.Z).Unit
		local warm = (0.5 + 0.5 * flat:Dot(sun)) ^ 1.6
		local away, toward, own = linear(atm.Decay), linear(atm.Color), linear(color)
		local m = {}
		for k = 1, 3 do
			local tint = away[k] * (1 - warm) + toward[k] * warm
			m[k] = own[k] * 2.2 * (1 - f) + tint * f
		end
		local peak = math.max(m[1], m[2], m[3])
		local exposure = 2 ^ preset.Lighting.ExposureCompensation / 0.6
		local IN = { { 0.59719, 0.35458, 0.04823 }, { 0.07600, 0.90834, 0.01566 }, { 0.02840, 0.13383, 0.83777 } }
		local OUT = { { 1.60475, -0.53108, -0.07367 }, { -0.10208, 1.10813, -0.00605 }, { -0.00327, -0.07276, 1.07602 } }
		local x = {}
		for r = 1, 3 do
			local v = 0
			for k = 1, 3 do
				v += IN[r][k] * m[k] * (if peak > 2.6 then 2.6 / peak else 1) * exposure
			end
			x[r] = (v * (v + 0.0245786) - 0.000090537) / (v * (0.983729 * v + 0.4329510) + 0.238081)
		end
		local out = {}
		for r = 1, 3 do
			local v = 0
			for k = 1, 3 do
				v += OUT[r][k] * x[k]
			end
			out[r] = l2s(math.clamp(v, 0, 1)) + cc.Brightness
			out[r] = (out[r] - 0.5) * (1 + cc.Contrast) + 0.5
		end
		local l = 0.2126 * out[1] + 0.7152 * out[2] + 0.0722 * out[3]
		local tint = { cc.TintColor.R, cc.TintColor.G, cc.TintColor.B }
		for r = 1, 3 do
			out[r] = math.clamp((l + (out[r] - l) * (1 + cc.Saturation)) * tint[r], 0, 1)
		end
		return out
	end
	-- hue (degrees), saturation, value of an RGB triple
	local function hsv(c: { number }): (number, number, number)
		local r, g, b = c[1], c[2], c[3]
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		local d = mx - mn
		local h = 0
		if d > 1e-6 then
			if mx == r then
				h = ((g - b) / d) % 6
			elseif mx == g then
				h = (b - r) / d + 2
			else
				h = (r - g) / d + 4
			end
		end
		return h * 60, if mx > 0 then d / mx else 0, mx
	end

	-- the planet's screen footprint as sample points: the body disc plus the
	-- ring (where it is not behind the body) as seen from `eye`
	local function samplePoints(spec: any, eye: any): { any }
		local center = Planets.center(spec)
		local radius = Planets.diameter(spec) / 2
		local view = (center - eye).Unit
		local e1 = view:Cross(Vector3.new(0, 1, 0)).Unit
		local e2 = e1:Cross(view).Unit
		local out = {}
		for i = -8, 8 do
			for j = -8, 8 do
				local u, v = i / 8, j / 8
				if u * u + v * v <= 1 then
					table.insert(out, center + (e1 * u + e2 * v) * radius)
				end
			end
		end
		local ring = spec.Ring
		if ring then
			local _, spin = Planets.frames(spec)
			for k = 0, 47 do
				local a = k / 48 * 2 * math.pi
				for _, r in { ring.Inner, (ring.Inner + ring.Outer) / 2, ring.Outer } do
					local p = spin:PointToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a)) * r * radius)
					-- behind the body? (the segment from the eye passes through the ball)
					local oc = eye - center
					local d = (p - eye).Unit
					local b = oc:Dot(d)
					local disc = b * b - (oc:Dot(oc) - radius * radius)
					local behind = disc > 0 and (-b - math.sqrt(disc)) < (p - eye).Magnitude
					if not behind then
						table.insert(out, p)
					end
				end
			end
		end
		return out
	end

	-- the built world once (the occluders of the planets: everything opaque
	-- but the planets themselves)
	local cachedOccluders: { any }? = nil
	local function occluders(): { any }
		if cachedOccluders then
			return cachedOccluders
		end
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local planets = map:FindFirstChild("Planets", true)
		local out = {}
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.5 and not (planets and d:IsDescendantOf(planets)) then
				table.insert(out, { CFrame = d.CFrame, Size = d.Size, Reach = d.Size.Magnitude / 2 })
			end
		end
		cachedOccluders = out
		return out
	end

	-- Fractions of the samples inside the camera's frame and hidden behind
	-- the occluders (of all samples).
	local function visibility(shot: string, spec: any): (number, number)
		local cf, tanY = camera(shot)
		local eye = cf.Position
		local samples = samplePoints(spec, eye)
		local center = Planets.center(spec)
		local reach = Planets.diameter(spec) / 2 * (if spec.Ring then spec.Ring.Outer else 1.1)
		local toCenter = (center - eye)
		local cone = math.atan(reach / toCenter.Magnitude)
		local near = {}
		for _, b in occluders() do
			local to = b.CFrame.Position - eye
			if to.Magnitude < toCenter.Magnitude then
				local spread = math.atan(b.Reach / math.max(to.Magnitude, 1))
				if math.acos(math.clamp(to.Unit:Dot(toCenter.Unit), -1, 1)) < cone + spread then
					table.insert(near, b)
				end
			end
		end
		local inside, hiddenCount = 0, 0
		for _, p in samples do
			local x, y = project(cf, tanY, p)
			if x and y and math.abs(x) <= 1 and math.abs(y) <= 1 then
				inside += 1
				for _, b in near do
					if rayHitsBox(eye, p, b.CFrame, b.Size) then
						hiddenCount += 1
						break
					end
				end
			end
		end
		return inside / #samples, hiddenCount / #samples
	end

	-- angular width of a planet seen from the town, ring included (degrees)
	local function angularWidth(spec: any): number
		local radius = Planets.diameter(spec) / 2 * (if spec.Ring then spec.Ring.Outer else 1)
		return math.deg(2 * math.atan(radius / (Planets.center(spec) - Planets.Town).Magnitude))
	end

	local function specOf(name: string): any
		for _, spec in Planets.Specs do
			if spec.Name == name then
				return spec
			end
		end
		error("no planet " .. name)
	end

	T.test("sky: three big Kenney-style planets frame the mountain", function()
		local root = build()
		local planets = root:FindFirstChild("Planets")
		T.truthy(planets and planets:IsA("Model"), "Planets model")
		local sun = LobbyLayout.SunDirection
		-- the farthest floating island, balloon or airship part
		local nearSky = 0
		for _, id in { "FloatingIslandWest", "FloatingIslandEast", "NextIsland", "Balloon", "Airship" } do
			for _, part in parts(root:FindFirstChild(id)) do
				local p = part.CFrame.Position
				nearSky = math.max(nearSky, Vector3.new(p.X, 0, p.Z).Magnitude)
			end
		end
		local count, ringed = 0, 0
		for _, spec in Planets.Specs do
			count += 1
			local m = planets:FindFirstChild(spec.Name)
			T.truthy(m and m:IsA("Model"), "planet " .. spec.Name)
			local list = parts(m)
			T.le(#list, Planets.MaxParts, spec.Name .. " parts")
			-- far past the 384-stud StreamingTargetRadius: Lod would only ever
			-- show the imposter mesh, so the planets stay streamed in
			T.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent, spec.Name .. " is always streamed")
			local body = m:FindFirstChild("Body")
			T.truthy(body and body.Shape == roblox.Enum.PartType.Ball, spec.Name .. " has a Ball body")
			T.eq(body.Material, roblox.Enum.Material.Neon, spec.Name .. " glows")
			local radius = body.Size.X / 2
			local center = body.CFrame.Position
			local toTown = (Planets.Town - center).Unit
			-- a thin translucent glowing edge, set back: its front stays inside
			-- the body (it never veils the face)
			local rim = m:FindFirstChild("Rim")
			T.truthy(rim and rim.Material == roblox.Enum.Material.Neon, spec.Name .. " glowing rim")
			T.truthy(rim.Transparency >= 0.5 and rim.Transparency <= 0.7, spec.Name .. " rim is translucent")
			T.truthy(rim.Size.X <= body.Size.X * 1.1, spec.Name .. " rim is a thin edge, not a bubble")
			local rimFront = rim.CFrame.Position + toTown * rim.Size.X / 2
			T.truthy((rimFront - center).Magnitude < radius, spec.Name .. " rim stays behind the face")
			-- far out (beyond the massif, the islands and most cloud banks),
			-- high, from the north-west to the north-east
			local flat = Vector3.new(center.X, 0, center.Z)
			T.truthy(flat.Magnitude >= 700 and flat.Magnitude <= 3000, `{spec.Name} hangs 700-3000 studs out ({flat.Magnitude})`)
			T.truthy(flat.Magnitude >= 1.5 * nearSky, `{spec.Name} hangs well beyond the islands and the airship ({nearSky})`)
			local bearing = math.deg(math.atan2(center.X, -center.Z)) % 360
			T.truthy(bearing >= 300 or bearing <= 60, `{spec.Name} is in the north-west..north-east sky ({bearing})`)
			T.truthy(center.Y > radius * 2, spec.Name .. " is high in the sky")
			-- never in front of the sun: the whole planet (ring included) keeps clear of it
			local reach = math.deg(math.atan(radius * (if spec.Ring then spec.Ring.Outer else 1.1) / center.Magnitude))
			local apart = math.deg(math.acos(math.clamp(center.Unit:Dot(sun), -1, 1)))
			T.truthy(apart > reach + 15, `{spec.Name} keeps clear of the sun ({apart} vs {reach})`)
			for _, part in list do
				T.falsy(part.CanCollide, part:GetFullName() .. " never collides")
				T.falsy(part.CanQuery, part:GetFullName() .. " is not raycast")
				T.falsy(part.CanTouch, part:GetFullName() .. " is not touched")
				T.falsy(part.CastShadow, part:GetFullName() .. " casts no shadow")
				T.falsy(LobbyLayout.inArea(part.CFrame.Position), part:GetFullName() .. " is far outside the lobby")
				T.eq(part.Material, roblox.Enum.Material.Neon, part:GetFullName() .. " is Neon (keeps its color in the haze)")
			end
			if spec.Ring then
				ringed += 1
			end
		end
		T.truthy(count >= 2 and count <= 3, "two or three planets")
		T.eq(ringed, 1, "one ringed gas giant")
		-- big: the gas giant (ring included) 11-13.5 degrees wide, the ember
		-- world >= 8, the teal world >= 6
		local giant = angularWidth(specOf("PlanetViolet"))
		T.truthy(giant >= 11 and giant <= 13.5, `the gas giant is {giant} degrees wide with its ring`)
		T.truthy(angularWidth(specOf("PlanetEmber")) >= 8, "the ember world is >= 8 degrees")
		T.truthy(angularWidth(specOf("PlanetTeal")) >= 6, "the teal world is >= 6 degrees")
	end)

	T.test("sky: from the spawn every planet is in frame and at most a quarter hidden (ring included)", function()
		build()
		for _, spec in Planets.Specs do
			local inside, hiddenFrac = visibility("lobby_spawn", spec)
			T.truthy(inside >= 0.95, `{spec.Name} is {math.floor(inside * 100)}% inside the lobby_spawn frame`)
			-- behind anything in the built world: massif, islands, waterfalls,
			-- buildings, clouds, airship, balloon
			T.le(hiddenFrac, 0.25, `{spec.Name} hidden from the spawn`)
		end
	end)

	T.test("sky: the hero shot frames the mountain with the ember world and the gas giant", function()
		build()
		local shown = 0
		for _, spec in Planets.Specs do
			local inside, hiddenFrac = visibility("lobby_hero", spec)
			-- either clearly in the frame (a deliberate crop at most) or out of it
			-- (no sliver at an edge)
			T.truthy(inside >= 0.4 or inside <= 0.02, `{spec.Name} is {math.floor(inside * 100)}% inside the lobby_hero frame`)
			if inside >= 0.4 then
				shown += 1
				T.le(hiddenFrac, 0.1, `{spec.Name} hidden in the hero shot`)
			end
		end
		T.truthy(shown >= 2, "two planets in the hero shot")
		local ember = visibility("lobby_hero", specOf("PlanetEmber"))
		T.truthy(ember >= 0.9, "the ember world is wholly in the hero frame (top left)")
		local giant = visibility("lobby_hero", specOf("PlanetViolet"))
		T.truthy(giant >= 0.4 and giant < 0.9, "the gas giant bleeds off the hero frame's right edge")
	end)

	T.test("sky: planet colors are the Kenney sprites' after the evening haze", function()
		-- checked as the plaza sees them through the Surface Atmosphere
		local eye = Planets.Town
		local P = Planets.Palette
		local function look(name: string, color: any): (number, number, number, { number })
			local c = hazed(color, eye, Planets.center(specOf(name)))
			local h, s, v = hsv(c)
			return h, s, v, c
		end
		-- ember (planet02/08): saturated orange, crimson and dark rust, no salmon
		local h, s, v = look("PlanetEmber", P.Orange)
		T.truthy(h >= 15 and h <= 35 and s >= 0.55, `ember orange hazes to h{h} s{s}`)
		h, s = look("PlanetEmber", P.Crimson)
		T.truthy((h >= 340 or h <= 8) and s >= 0.5, `ember crimson hazes to h{h} s{s}`)
		h, s, v = look("PlanetEmber", P.Rust)
		T.truthy((h >= 350 or h <= 20) and s >= 0.45 and v <= 0.8, `ember rust hazes to h{h} s{s} v{v}`)
		h, s = look("PlanetEmber", P.Flame)
		T.truthy(h >= 18 and h <= 40 and s >= 0.5, `ember light streak hazes to h{h} s{s}`)
		-- teal (planet00/03): ice body, teal-mint and a blue that never turns violet
		h, s, v = look("PlanetTeal", P.Ice)
		T.truthy(h >= 190 and h <= 215 and s <= 0.3 and v >= 0.95, `teal ice hazes to h{h} s{s} v{v}`)
		for _, mint in { P.Teal, P.Seafoam } do
			h, s = look("PlanetTeal", mint)
			T.truthy(h >= 150 and h <= 180 and s >= 0.3, `teal mint hazes to h{h} s{s}`)
		end
		h, s = look("PlanetTeal", P.DeepBlue)
		T.truthy(h >= 195 and h < 228 and s >= 0.35, `teal deep blue hazes to h{h} s{s} (no lavender)`)
		-- violet (planet09/01): saturated violet body, deep bands darker, lilac
		-- bands and the ring lighter
		local bh, bs, bv, body = look("PlanetViolet", P.Violet)
		T.truthy(bh >= 250 and bh <= 275 and bs >= 0.55, `violet body hazes to h{bh} s{bs}`)
		h, s, v = look("PlanetViolet", P.VioletDeep)
		T.truthy(h >= 245 and h <= 275 and v <= bv - 0.15, `violet deep hazes to h{h} v{v} (body v{bv})`)
		local _, _, lv = look("PlanetViolet", P.Lilac)
		T.truthy(lv >= bv, "the lilac bands are lighter than the body")
		local _, _, _, ring = look("PlanetViolet", P.Ring)
		local lum = function(c: { number }): number
			return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
		end
		T.truthy(lum(ring) >= lum(body) + 0.15, "the ring is clearly lighter than the body")
		-- every body/blotch tone reads apart from its body
		for _, spec in Planets.Specs do
			local base = hazed(spec.Body, eye, Planets.center(spec))
			for _, patch in spec.Patches do
				local c = hazed(patch.Color, eye, Planets.center(spec))
				local dist = math.sqrt((c[1] - base[1]) ^ 2 + (c[2] - base[2]) ^ 2 + (c[3] - base[3]) ^ 2)
				T.truthy(dist >= 0.12, `{spec.Name} {tostring(patch.Color)} stands out from the body ({dist})`)
			end
		end
	end)

	T.test("sky: Kenney camouflage streaks, latitude bands and a light ring", function()
		local root = build()
		for _, spec in Planets.Specs do
			local m = root.Planets[spec.Name]
			local body = m.Body
			local radius = body.Size.X / 2
			local center = body.CFrame.Position
			local toTown = (Planets.Town - center).Unit
			-- caps: small (4-12 degrees), low (they barely poke out, so the
			-- outline stays round), steep creases (no z-fighting)
			for _, patch in spec.Patches do
				T.truthy(patch.Size >= 4 and patch.Size <= Planets.MaxCap, `{spec.Name} cap size {patch.Size}`)
				T.truthy(patch.Lift <= 0.04 + 1e-9, `{spec.Name} cap lift {patch.Lift} <= 0.04`)
			end
			-- streaks: consecutive caps of one color along a row sit at most
			-- one cap radius apart (half a cap diameter), so they merge into an
			-- elongated streak; every color has streaks of 2+ caps
			local runs, longest = 0, 0
			local runLength = 1
			for i = 2, #spec.Patches + 1 do
				local a, b = spec.Patches[i - 1], spec.Patches[i]
				local same = b and a.Color == b.Color and math.abs(a.Lat - b.Lat) <= 6
				if same then
					local arc = math.deg(math.acos(math.clamp(Planets.direction(a.Lon, a.Lat):Dot(Planets.direction(b.Lon, b.Lat)), -1, 1)))
					T.truthy(arc <= math.min(a.Size, b.Size) * 1.05, `{spec.Name} streak caps {arc} degrees apart`)
					runLength += 1
				else
					runs += 1
					longest = math.max(longest, runLength)
					runLength = 1
				end
			end
			T.truthy(longest >= 3, `{spec.Name} has streaks of 3+ merged caps`)
			-- every cap meets the body (and every cap of another color it
			-- crosses) at a steep angle
			local balls = Planets.balls(spec)
			for i, a in balls do
				for j = i + 1, #balls do
					local o = balls[j]
					local dist = (o.Offset - a.Offset).Magnitude
					if a.Color ~= o.Color and dist < a.Radius + o.Radius and dist > math.abs(a.Radius - o.Radius) then
						if creaseVisible(balls, i, j, toTown) then
							local angle = Planets.crease(a.Radius, o.Radius, dist)
							T.truthy(angle >= Planets.MinCrease, `{spec.Name} {a.Name}/{o.Name} crease {angle} degrees`)
						end
					end
				end
			end
			-- the built balls are the balls of the spec
			for _, ball in balls do
				local part = m:FindFirstChild(ball.Name)
				T.truthy(part and (part.CFrame.Position - (center + ball.Offset)).Magnitude < 0.01, `{spec.Name} {ball.Name} built`)
			end
			-- gloss and shade crescents: thin translucent discs facing the town,
			-- inside the silhouette, showing only a crescent inside the limb
			for _, name in { "Gloss", "Shade" } do
				local disc = m:FindFirstChild(name)
				T.truthy(disc and disc.Shape == roblox.Enum.PartType.Cylinder, `{spec.Name} {name} crescent disc`)
				T.truthy(disc.Transparency >= 0.4 and disc.Transparency <= 0.6, `{spec.Name} {name} is translucent`)
				T.truthy(math.abs(disc.CFrame.RightVector:Dot(toTown)) > 0.999, `{spec.Name} {name} faces the town`)
				local l = disc.CFrame.Position - center
				local depth = l:Dot(toTown)
				local side = (l - toTown * depth).Magnitude
				T.truthy(side + disc.Size.Y / 2 <= radius * 0.98, `{spec.Name} {name} stays inside the outline`)
				T.truthy(depth > 0 and depth < radius * 0.8, `{spec.Name} {name} shows only a crescent`)
				T.truthy(disc.Size.X <= radius * 0.02, `{spec.Name} {name} is thin`)
			end
			-- ember and teal: two/three-tone camouflage over about half the face
			if not spec.Bands then
				local cov = coverage(balls, toTown, radius)
				T.truthy(cov >= 0.45, `{spec.Name} face is {math.floor(cov * 100)}% camouflaged`)
				local colors: { [string]: boolean } = {}
				local tones = 0
				for _, patch in spec.Patches do
					if not colors[tostring(patch.Color)] then
						colors[tostring(patch.Color)] = true
						tones += 1
					end
				end
				T.truthy(tones >= 2, spec.Name .. " has two or three blotch colors")
			end
		end
		-- the gas giant: latitude bands from thin discs coaxial with the
		-- spin axis, alternating deep and lilac, ~1.01-1.03 x the chord at
		-- their latitude, coming out of the surface steeply and never
		-- reaching past the outline seen from the town
		local spec = specOf("PlanetViolet")
		local m = root.Planets[spec.Name]
		local radius = m.Body.Size.X / 2
		local center = m.Body.CFrame.Position
		local _, spin = Planets.frames(spec)
		local bands = Planets.bandDiscs(spec)
		T.truthy(#bands >= 3 and #bands <= 4, "three or four latitude bands")
		for i, band in bands do
			local part = m:FindFirstChild(band.Name)
			T.truthy(part and part.Shape == roblox.Enum.PartType.Cylinder, `band {i} is a disc`)
			T.truthy(math.abs(part.CFrame.RightVector:Dot(spin.UpVector)) > 0.999, `band {i} is coaxial with the spin axis`)
			local off = part.CFrame.Position - center
			T.truthy((off - spin.UpVector * off:Dot(spin.UpVector)).Magnitude < 0.01, `band {i} is centered on the axis`)
			T.truthy(part.Size.X <= 0.16 * radius, `band {i} is thin`)
			local lat = spec.Bands[i].Lat
			local chord = 2 * radius * math.cos(math.rad(lat))
			local scale = part.Size.Y / chord
			T.truthy(scale >= 1 and scale <= 1.05, `band {i} is {scale} x the chord at its latitude`)
			if i > 1 then
				T.truthy(spec.Bands[i].Color ~= spec.Bands[i - 1].Color, "bands alternate colors")
			end
			local edge = math.abs(math.sin(math.rad(lat))) - spec.Bands[i].Width / 2
			T.truthy(math.deg(math.asin(edge)) >= Planets.MinBandCrease, `band {i} comes out of the surface steeply`)
			-- the far rim stays behind the body seen from the town (no flat lid on the outline)
			local h = math.abs(off:Dot(spin.UpVector)) + part.Size.X / 2
			local lean = math.rad(spec.Lean)
			T.truthy((h * math.cos(lean) + part.Size.Y / 2 * math.sin(lean)) / radius < 0.97, `band {i} stays inside the outline`)
		end
		-- the ring: 28-32 flat segments of one light warm lilac, wide and open
		local ring = spec.Ring
		local segments, colors = 0, {}
		for _, part in parts(m) do
			if part.Name == "Ring" then
				segments += 1
				colors[tostring(part.Color)] = true
			end
		end
		T.truthy(segments >= 28 and segments <= 32, `ring of {segments} segments`)
		local ringTones = 0
		for _ in colors do
			ringTones += 1
		end
		-- overlapping coplanar segments must share one color (no z-fight flicker)
		T.eq(ringTones, 1, "the ring is one color")
		T.truthy(luminance(ring.Color) > luminance(spec.Body) + 0.1, "the ring is lighter than the body")
		T.truthy(ring.Color.R > ring.Color.G, "the ring is a warm lilac")
		T.truthy(ring.Outer >= 1.7 and ring.Outer <= 1.8, "the ring is wide (Outer 1.7-1.8)")
		T.truthy(spec.Lean >= 24 and spec.Lean <= 30, "the ring is open (Lean 24-30)")
	end)

	T.test("sky: clouds, the airship and the balloon keep clear of the planets in the hero and spawn shots", function()
		local root = build()
		for _, shot in { "lobby_hero", "lobby_spawn" } do
			local cf, tanY = camera(shot)
			-- the planets' discs (with the rim, or the ring) on screen
			local discs = {}
			for _, spec in Planets.Specs do
				local body = root.Planets[spec.Name].Body
				local center = body.CFrame.Position
				local x, y = project(cf, tanY, center)
				local reach = if spec.Ring then spec.Ring.Outer * 0.8 else Planets.RimScale
				local edge = center + cf.UpVector * body.Size.X / 2 * reach
				local _, ey = project(cf, tanY, edge)
				-- only the planets (partly) inside this shot's frame
				local r = if ey then math.abs(ey - y) else 0
				if x and y and ey and math.abs(y) - r <= 1 and math.abs(x) * ASPECT - r <= ASPECT then
					table.insert(discs, { Name = spec.Name, X = x * ASPECT, Y = y, R = r })
				end
			end
			local function box(m: any): (number, number, number, number)
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
				for _, part in parts(m) do
					for _, p in corners(part) do
						local x, y = project(cf, tanY, p)
						if x and y then
							x0, y0, x1, y1 = math.min(x0, x * ASPECT), math.min(y0, y), math.max(x1, x * ASPECT), math.max(y1, y)
						end
					end
				end
				return x0, y0, x1, y1
			end
			local things = { root.Airship, root.Balloon }
			for _, cloud in root.CloudBanks:GetChildren() do
				table.insert(things, cloud)
			end
			for _, m in things do
				local x0, y0, x1, y1 = box(m)
				for _, d in if x0 <= x1 then discs else {} do
					local nx, ny = math.clamp(d.X, x0, x1), math.clamp(d.Y, y0, y1)
					local hit = math.sqrt((nx - d.X) ^ 2 + (ny - d.Y) ^ 2) < d.R
					T.falsy(hit, `{shot}: {m:GetFullName()} covers {d.Name}`)
				end
			end
			-- and the planets never cover each other
			for i, a in discs do
				for j = i + 1, #discs do
					local d = discs[j]
					T.truthy(math.sqrt((a.X - d.X) ^ 2 + (a.Y - d.Y) ^ 2) > a.R + d.R, `{shot}: {a.Name} and {d.Name} overlap`)
				end
			end
		end
		-- no cloud shares the balloon's screen box in the spawn shot
		local cf, tanY = camera("lobby_spawn")
		local function rect(m: any): (number, number, number, number)
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, part in parts(m) do
				for _, p in corners(part) do
					local x, y = project(cf, tanY, p)
					if x and y then
						x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
					end
				end
			end
			return x0, y0, x1, y1
		end
		local bx0, by0, bx1, by1 = rect(root.Balloon)
		for _, cloud in root.CloudBanks:GetChildren() do
			local x0, y0, x1, y1 = rect(cloud)
			local apart = x1 < bx0 or x0 > bx1 or y1 < by0 or y0 > by1
			T.truthy(apart, `lobby_spawn: {cloud:GetFullName()} crosses the balloon`)
		end
	end)

	T.test("sky: the airship of concept v2", function()
		local root = build()
		local m = root:FindFirstChild("Airship")
		T.truthy(m and m:IsA("Model"), "Airship model")
		local list = parts(m)
		T.le(#list, Airship.MaxParts, "airship parts")
		T.eq(m.PrimaryPart and m.PrimaryPart.Name, "Envelope", "the airship bobs around its envelope")
		T.truthy(m:FindFirstChild("Gondola"), "a gondola under the envelope")
		-- a bulbous ball nose and a ball tail
		for _, name in { "Nose", "Tail" } do
			local part = m:FindFirstChild(name)
			T.truthy(part and part.Shape == roblox.Enum.PartType.Ball, `the airship's {name} is a ball`)
		end
		-- a long cigar pitched a little nose-down like the concept
		local envelope = m.PrimaryPart
		local axis = envelope.CFrame.RightVector -- a Roblox cylinder runs along its X axis
		local pitch = math.deg(math.asin(math.abs(axis.Y)))
		T.truthy(pitch >= 6 and pitch <= 8, `airship pitch {pitch} degrees`)
		local diameter = envelope.Size.Y
		local lo, hi = math.huge, -math.huge
		for _, part in list do
			local along = (part.CFrame.Position - envelope.CFrame.Position):Dot(axis)
			lo, hi = math.min(lo, along), math.max(hi, along)
		end
		T.truthy(hi - lo >= 4 * diameter, `airship is long ({hi - lo} vs {diameter} wide)`)
		-- it tapers continuously toward the tail: the coaxial cylinders behind
		-- the nose get thinner and thinner (drums, then the cone)
		local nose = m.Nose.CFrame.Position
		-- the ship's axis from the nose toward the tail
		local aft = (m.Tail.CFrame.Position - nose).Unit
		local coaxial = {}
		for _, part in list do
			if part:IsA("Part") and part.Shape == roblox.Enum.PartType.Cylinder and part.Material ~= roblox.Enum.Material.Neon then
				local rel = part.CFrame.Position - nose
				local along = rel:Dot(aft)
				local off = (rel - aft * along).Magnitude
				local parallel = math.abs(part.CFrame.RightVector:Dot(aft)) > 0.999
				-- envelope drums and cone steps (longer than 2, the brass ribs aside)
				if parallel and off < 0.1 and along > 0 and part.Size.X > 2.5 and part.Color ~= Style.C.Brass then
					table.insert(coaxial, { Along = along, D = part.Size.Y })
				end
			end
		end
		table.sort(coaxial, function(a, b)
			return a.Along < b.Along
		end)
		T.truthy(#coaxial >= 6, `three envelope drums and a three-step cone ({#coaxial})`)
		for i = 2, #coaxial do
			T.truthy(coaxial[i].D < coaxial[i - 1].D, `the envelope tapers toward the tail ({coaxial[i - 1].D} -> {coaxial[i].D})`)
		end
		-- the exhaust: a thin bright magenta jet of three Neon cylinders,
		-- thinner and fainter toward its end
		local jets = {}
		for _, part in list do
			if part.Name == "Jet" then
				table.insert(jets, part)
			end
		end
		T.eq(#jets, 3, "three jet segments")
		table.sort(jets, function(a, b)
			return (a.CFrame.Position - nose):Dot(aft) < (b.CFrame.Position - nose):Dot(aft)
		end)
		for i, jet in jets do
			T.eq(jet.Shape, roblox.Enum.PartType.Cylinder, "the jet is round")
			T.eq(jet.Material, roblox.Enum.Material.Neon, "the jet glows")
			T.truthy(jet.Color.R > 0.9 and jet.Color.B > 0.6 and jet.Color.G < 0.45, "the jet is saturated magenta")
			if i > 1 then
				T.truthy(jet.Size.Y < jets[i - 1].Size.Y, "the jet gets thinner")
				T.truthy(jet.Transparency > jets[i - 1].Transparency, "the jet fades out")
			end
		end
		local windows = 0
		for _, part in list do
			T.falsy(part.CanCollide, part:GetFullName() .. " never collides")
			T.falsy(part.CastShadow, part:GetFullName() .. " casts no shadow")
			T.falsy(LobbyLayout.inArea(part.CFrame.Position), part:GetFullName() .. " flies outside the lobby area")
			if part.Material == roblox.Enum.Material.Neon and part.Color == Style.C.Lamp then
				windows += 1
			end
		end
		T.truthy(windows >= 8, "lit gondola windows")
	end)

	T.test("sky: the build is deterministic", function()
		local function signature(root: any): string
			local acc = {}
			for _, part in parts(root) do
				local p = part.CFrame.Position
				table.insert(acc, string.format("%s %.2f %.2f %.2f %.2f %s", part.Name, p.X, p.Y, p.Z, part.Size.X, tostring(part.Color)))
			end
			return table.concat(acc, "|")
		end
		T.eq(signature(build()), signature(build()), "same parts for the same seed")
	end)

	---------------------------------------------------------------- lighting

	local project = serde.decode("json", fs.readFile(process.cwd .. "/default.project.json"))
	local lightingNode = project.tree.Lighting

	local function same(actual: any, expected: any): boolean
		if type(expected) == "table" then
			-- project.json color array vs Color3
			return typeof(actual) == "Color3"
				and math.abs(actual.R - expected[1]) < 1e-3
				and math.abs(actual.G - expected[2]) < 1e-3
				and math.abs(actual.B - expected[3]) < 1e-3
		elseif type(expected) == "number" then
			return type(actual) == "number" and math.abs(actual - expected) < 1e-6
		end
		return actual == expected
	end

	-- Every property on both sides must agree (keys only one side has fail too).
	local function compare(label: string, config: { [string]: any }, props: { [string]: any }, ignore: { [string]: boolean }?)
		for key, value in props do
			if not (ignore and ignore[key]) then
				T.truthy(config[key] ~= nil, `{label}.{key} is in LightingConfig`)
				T.truthy(same(config[key], value), `{label}.{key}: project {tostring(value)} vs config {tostring(config[key])}`)
			end
		end
		for key in config do
			T.truthy(props[key] ~= nil, `{label}.{key} is in default.project.json`)
		end
	end

	T.test("lighting: the Surface preset matches default.project.json", function()
		local surface = LightingConfig.Presets.Surface
		compare("Lighting", surface.Lighting, lightingNode["$properties"], {
			Technology = true,
			ClockTime = true,
			GeographicLatitude = true,
			GlobalShadows = true,
			ShadowSoftness = true,
		})
		local effects = { Atmosphere = "Atmosphere", Bloom = "Bloom", ColorCorrection = "ColorCorrection", SunRays = "SunRays" }
		for group, child in effects do
			local node = lightingNode[child]
			T.truthy(node, child .. " exists in default.project.json")
			compare(group, (surface :: any)[group], node["$properties"])
		end
		local sky = lightingNode.Sky
		T.eq(sky["$className"], "Sky", "a Sky object")
		compare("Sky", LightingConfig.Sky, sky["$properties"])
		T.near(lightingNode["$properties"].ClockTime, LightingConfig.Sun.ClockTime, 1e-6, "ClockTime")
		T.near(lightingNode["$properties"].GeographicLatitude, LightingConfig.Sun.GeographicLatitude, 1e-6, "GeographicLatitude")
	end)

	T.test("lighting: golden hour (ART_DIRECTION 7)", function()
		local surface = LightingConfig.Presets.Surface
		local atm = surface.Atmosphere
		T.truthy(atm.Color.R > atm.Color.G and atm.Color.G > atm.Color.B, "orange haze")
		T.truthy(atm.Decay.B > atm.Decay.G, "purple distance")
		T.truthy(LightingConfig.Sun.ClockTime > 16.5 and LightingConfig.Sun.ClockTime < 18.5, "evening sun")
		T.eq(LightingConfig.Sky.StarCount, 0, "no stars at golden hour")
		T.truthy(LightingConfig.Sky.SunAngularSize >= 12, "a big low sun")
		T.truthy(LightingConfig.Clouds.Cover > 0.3 and LightingConfig.Clouds.Cover < 0.7, "clouds cover")
		-- the quarry keeps the same sunset, a bit dustier
		local quarry = LightingConfig.Presets.Quarry
		T.truthy(quarry.Atmosphere.Density >= atm.Density, "the quarry is dustier")
		T.truthy(quarry.Atmosphere.Color.R > quarry.Atmosphere.Color.B, "the quarry haze is warm too")
		-- the preview sky dome uses the Style palette
		for _, preset in { surface, quarry } do
			local sky = preset.Sky
			T.truthy(sky, "preview sky colors")
			T.eq(sky.Top, Style.C.SkyTop, "zenith = SkyTop")
			T.eq(sky.Mid, Style.C.SkyPurple, "mid sky = SkyPurple")
			T.eq(sky.Horizon, Style.C.SkyHorizon, "horizon = SkyHorizon")
			T.eq(sky.HorizonAway, Style.C.CloudPink, "horizon away from the sun = CloudPink")
			T.eq(sky.Sun, Style.C.Sun, "sun = Sun")
		end
	end)
end
