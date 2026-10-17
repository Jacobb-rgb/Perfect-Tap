--[[
	Lobby package "Sky" (src/server/World/Lobby/Sky, docs/plans/LOBBY_PLAN.md
	6.1, docs/plans/VISUAL_UPGRADE_PLAN.md): every set piece is built inside
	its LobbyLayout footprint and part budget, clouds stay out of the lobby
	area and are puffy clusters and thin streaks with lit undersides at many
	heights (never straddling the hero frame's top edge), the three planets
	hang 1500-3000 studs out in the north-west..north-east sky (Kenney
	camouflage, cheap, one ringed, never in front of the sun, wholly inside
	the hero frame, not hidden from the spawn), the airship is a cheap
	bobbing Spin model with a rounded nose and tail, the balloon and the
	ships are tagged Spin, the build is deterministic, and the golden-hour
	Lighting in default.project.json is identical to
	LightingConfig.Presets.Surface.
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
		-- the glitter lies on the sea surface (Land: sea top at y -21)
		for _, part in parts(root.SunGlitter) do
			T.eq(part.Material, roblox.Enum.Material.Neon, "glitter is neon")
			T.truthy(math.abs(part.CFrame.Position.Y + part.Size.Y / 2 + 20.85) < 0.01, "glitter top at y -20.85")
			T.truthy(part.Transparency >= 0.25 and part.Transparency <= 0.5, "glitter transparency")
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
	local Color3White = roblox.Color3.new(1, 1, 1)

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
	-- fraction of a sphere's disc (as seen from `cf`) inside the frame
	local function inFrame(cf: any, tanY: number, center: any, radius: number): number
		local view = (center - cf.Position).Unit
		local e1 = view:Cross(Vector3.new(0, 1, 0)).Unit
		local e2 = e1:Cross(view).Unit
		local inside, total = 0, 0
		for i = -10, 10 do
			for j = -10, 10 do
				local u, v = i / 10, j / 10
				if u * u + v * v <= 1 then
					total += 1
					local x, y = project(cf, tanY, center + (e1 * u + e2 * v) * radius)
					if x and y and math.abs(x) <= 1 and math.abs(y) <= 1 then
						inside += 1
					end
				end
			end
		end
		return inside / total
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

	T.test("sky: clouds are rounded mounds and thin streaks with lit undersides", function()
		local root = build()
		local clusters, streaks = 0, 0
		local lowBase, highBase, smallest, largest = math.huge, -math.huge, math.huge, 0
		-- the lit skirts: translucent Neon sheets a clear stud under the block above them
		local function skirts(list: { any }, name: string): ({ any }, { any })
			local sheets, solids = {}, {}
			for _, part in list do
				if part.Material == roblox.Enum.Material.Neon and part.Size.Y < 0.5 then
					table.insert(sheets, part)
				else
					table.insert(solids, part)
				end
			end
			for _, sheet in sheets do
				T.eq(sheet.Name, "Skirt", name .. " sheet is a skirt")
				T.truthy(sheet.Transparency >= 0.3 and sheet.Transparency <= 0.45, name .. " skirt glows (Transparency 0.3-0.45)")
				local top = sheet.CFrame.Position.Y + sheet.Size.Y / 2
				-- the solid right above the skirt's middle
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
			return sheets, solids
		end
		for _, cloud in root.CloudBanks:GetChildren() do
			local name = cloud:GetFullName()
			local list = parts(cloud)
			if cloud:IsA("Model") and cloud.Name == "Cloud" then
				clusters += 1
				T.truthy(#list >= 20 and #list <= 26, name .. " is a stacked cluster, not a slab")
				-- the cluster frame: every block shares its yaw
				local frame = list[1].CFrame - list[1].CFrame.Position
				local sheets, solids = skirts(list, name)
				T.truthy(#sheets >= 6, name .. " has a lit skirt under every puff")
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
				-- the skirts sit under the cloud's lower part
				for _, sheet in sheets do
					T.truthy(sheet.CFrame.Position.Y < minY + height * 0.3, name .. " skirt sits under the cloud")
				end
			elseif cloud:IsA("Model") and cloud.Name == "Stratus" then
				streaks += 1
				T.truthy(#list >= 6 and #list <= 8, name .. " streak is 6-8 parts")
				local sheets, solids = skirts(list, name)
				T.truthy(#sheets >= 2, name .. " streak has a lit underside")
				-- its length along the streak (the frame X axis every puff shares)
				local frame = solids[1].CFrame - solids[1].CFrame.Position
				local minY, maxY, minX, maxX = math.huge, -math.huge, math.huge, -math.huge
				for _, part in solids do
					minY = math.min(minY, part.CFrame.Position.Y - part.Size.Y / 2)
					maxY = math.max(maxY, part.CFrame.Position.Y + part.Size.Y / 2)
					local l = frame:PointToObjectSpace(part.CFrame.Position)
					minX, maxX = math.min(minX, l.X - part.Size.X / 2), math.max(maxX, l.X + part.Size.X / 2)
				end
				local long = maxX - minX
				T.truthy(long >= 110 and maxY - minY < 0.15 * long, `{name} is a long thin streak ({long} long, {maxY - minY} tall)`)
			end
		end
		T.truthy(clusters >= 12, "a dozen or more cloud clusters")
		T.truthy(streaks >= 4 and streaks <= 6, "four to six stratus streaks")
		-- many heights and sizes, not one row of look-alike piles
		T.truthy(highBase - lowBase >= 200, `cloud bases spread over {highBase - lowBase} studs of height`)
		T.truthy(largest >= 2.5 * smallest, `cloud sizes vary ({smallest}..{largest} wide)`)
	end)

	-- The hero camera's frame top edge: a cloud is wholly above it or wholly
	-- below it (no cloud bottoms poking in at the top of the hero shot).
	T.test("sky: no cloud straddles the top edge of the hero shot", function()
		local root = build()
		local cf, tanY = camera("lobby_hero")
		for _, cloud in root.CloudBanks:GetChildren() do
			local above, below = 0, 0
			for _, part in parts(cloud) do
				for _, p in corners(part) do
					local x, y = project(cf, tanY, p)
					if x and y and math.abs(x) <= 1 then
						if y > 1 then
							above += 1
						else
							below += 1
						end
					end
				end
			end
			T.falsy(above > 0 and below > 0, `{cloud:GetFullName()} straddles the hero frame's top edge`)
		end
	end)

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

	-- Fraction of a sphere's disc (seen from `eye`) hidden behind any of the
	-- boxes ({ CFrame, Size }); boxes far off the line of sight are skipped.
	local function hidden(eye: any, center: any, radius: number, boxes: { any }): number
		local view = (center - eye).Unit
		local reach = math.atan(radius / (center - eye).Magnitude)
		local near = {}
		for _, b in boxes do
			local to = b.CFrame.Position - eye
			local spread = math.atan((b.Size.Magnitude / 2) / math.max(to.Magnitude, 1))
			if to.Magnitude < (center - eye).Magnitude and math.acos(math.clamp(to.Unit:Dot(view), -1, 1)) < reach + spread then
				table.insert(near, b)
			end
		end
		local e1 = view:Cross(Vector3.new(0, 1, 0)).Unit
		local e2 = e1:Cross(view).Unit
		local covered, total = 0, 0
		for i = -10, 10 do
			for j = -10, 10 do
				local u, v = i / 10, j / 10
				if u * u + v * v <= 1 then
					total += 1
					local p = center + (e1 * u + e2 * v) * radius
					for _, b in near do
						if rayHitsBox(eye, p, b.CFrame, b.Size) then
							covered += 1
							break
						end
					end
				end
			end
		end
		return covered / total
	end

	local function boxesOf(m: any): { any }
		local out = {}
		for _, part in parts(m) do
			table.insert(out, { CFrame = part.CFrame, Size = part.Size })
		end
		return out
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
						if b.Transparency == 0 then
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
					end
					if name ~= "Body" then
						covered += 1
					end
				end
			end
		end
		return covered / total
	end

	T.test("sky: three big Kenney-style planets frame the mountain", function()
		local root = build()
		local planets = root:FindFirstChild("Planets")
		T.truthy(planets and planets:IsA("Model"), "Planets model")
		local sun = LobbyLayout.SunDirection
		local heroCf, heroTan = camera("lobby_hero")
		local spawnCf = camera("lobby_spawn")
		local eye = spawnCf.Position
		-- what may stand in front of a planet from the spawn: the Sky set
		-- pieces (their real blocks) and the town skyline (building footprints)
		local skyBoxes = {}
		for _, id in { "FloatingIslandWest", "FloatingIslandEast", "Balloon", "NextIsland" } do
			for _, b in boxesOf(root:FindFirstChild(id)) do
				table.insert(skyBoxes, b)
			end
		end
		local townBoxes = {}
		for _, id in { "Shop", "ShopFront", "Upgrades", "UpgradesFront", "GreatForge" } do
			local piece = LobbyLayout.get(id)
			table.insert(townBoxes, { CFrame = LobbyLayout.frame(piece) * roblox.CFrame.new(0, piece.Size.Y / 2, 0), Size = piece.Size })
		end
		local ringed = 0
		local count = 0
		for _, spec in Planets.Specs do
			count += 1
			local m = planets:FindFirstChild(spec.Name)
			T.truthy(m and m:IsA("Model"), "planet " .. spec.Name)
			local list = parts(m)
			T.le(#list, Planets.MaxParts, spec.Name .. " parts")
			-- 1500 studs out is far past the 384-stud StreamingTargetRadius: Lod
			-- would only ever show the imposter mesh, so the planets stay streamed in
			T.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent, spec.Name .. " is always streamed")
			local body = m:FindFirstChild("Body")
			T.truthy(body and body.Shape == roblox.Enum.PartType.Ball, spec.Name .. " has a Ball body")
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
			-- far away, high, from the north-west to the north-east, big on screen
			local flat = Vector3.new(center.X, 0, center.Z)
			T.truthy(flat.Magnitude >= 1500 and flat.Magnitude <= 3000, `{spec.Name} hangs 1500-3000 studs out ({flat.Magnitude})`)
			local bearing = math.deg(math.atan2(center.X, -center.Z)) % 360
			T.truthy(bearing >= 300 or bearing <= 60, `{spec.Name} is in the north-west..north-east sky ({bearing})`)
			T.truthy(center.Y > radius * 0.5, spec.Name .. " is high in the sky")
			local angular = math.deg(2 * math.atan(radius / center.Magnitude))
			T.truthy(angular >= 4.5, `{spec.Name} is big on screen ({angular} degrees)`)
			-- never in front of the sun: the whole planet (ring included) keeps clear of it
			local reach = math.deg(math.atan(radius * (if spec.Ring then spec.Ring.Outer else 1.1) / center.Magnitude))
			local apart = math.deg(math.acos(math.clamp(center.Unit:Dot(sun), -1, 1)))
			T.truthy(apart > reach + 15, `{spec.Name} keeps clear of the sun ({apart} vs {reach})`)
			-- the whole disc with its rim and its ring inside the hero frame
			local frac = inFrame(heroCf, heroTan, center, radius * Planets.RimScale)
			T.truthy(frac >= 0.95, `{spec.Name} is {math.floor(frac * 100)}% inside the lobby_hero frame`)
			if spec.Ring then
				local inside, total = 0, 0
				for _, part in list do
					if part.Name == "Ring" then
						for _, p in corners(part) do
							total += 1
							local x, y = project(heroCf, heroTan, p)
							if x and y and math.abs(x) <= 1 and math.abs(y) <= 1 then
								inside += 1
							end
						end
					end
				end
				T.truthy(inside / total >= 0.95, `{spec.Name} ring is {math.floor(inside / total * 100)}% inside the lobby_hero frame`)
			end
			-- from the spawn: never behind the massif, at most a sliver behind
			-- the floating islands or the balloon, and only the lower edge
			-- behind the town skyline (the hero frame tops out ~13 degrees up and
			-- the SHOP / UPGRADES roofs reach ~9-11 degrees from the spawn, so a
			-- planet inside the hero frame cannot clear them completely)
			local mountain = LobbyLayout.get("ForgeMountain")
			local lo, hi = math.huge, -math.huge
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = mountain.Center + Vector3.new(sx * mountain.Size.X / 2, 0, sz * mountain.Size.Z / 2)
					local l = spawnCf:PointToObjectSpace(c)
					local b = math.deg(math.atan2(l.X, -l.Z))
					lo, hi = math.min(lo, b), math.max(hi, b)
				end
			end
			local lc = spawnCf:PointToObjectSpace(center)
			local b = math.deg(math.atan2(lc.X, -lc.Z))
			T.truthy(b < lo or b > hi, `{spec.Name} is not behind the massif from the spawn ({b} vs {lo}..{hi})`)
			local bySky = hidden(eye, center, radius, skyBoxes)
			T.le(bySky, 0.15, `{spec.Name} hidden behind the floating islands / balloon from the spawn`)
			local byTown = hidden(eye, center, radius, townBoxes)
			T.le(byTown, Planets.MaxSkylineCover, `{spec.Name} hidden behind the town skyline from the spawn`)
			-- every cap is much smaller than the body and pokes out steeply: no two
			-- differently colored surfaces ever meet at a grazing angle (z-fighting);
			-- a blotch crosses the shading more steeply still
			local balls = Planets.balls(spec)
			for i, a in balls do
				if i > 1 then
					T.le(a.Radius, radius * Planets.MaxPatchRadius + 1e-6, `{spec.Name} {a.Name} radius`)
				end
				for j = i + 1, #balls do
					local o = balls[j]
					local dist = (o.Offset - a.Offset).Magnitude
					if a.Color ~= o.Color and dist < a.Radius + o.Radius and dist > math.abs(a.Radius - o.Radius) then
						if creaseVisible(balls, i, j, toTown) then
							local angle = Planets.crease(a.Radius, o.Radius, dist)
							local min = if i > 1 and a.Shade ~= o.Shade then Planets.MinShadeCrease else Planets.MinCrease
							T.truthy(angle >= min, `{spec.Name} {a.Name}/{o.Name} crease {angle} degrees (min {min})`)
						end
					end
				end
			end
			-- the built balls are the balls of the spec
			for _, ball in balls do
				local part = m:FindFirstChild(ball.Name)
				T.truthy(part and (part.CFrame.Position - (center + ball.Offset)).Magnitude < 0.01, `{spec.Name} {ball.Name} built`)
				T.near(part.Transparency, ball.Transparency, 1e-6, `{spec.Name} {ball.Name} transparency`)
			end
			-- Kenney camouflage: about two thirds of the face patterned, caps of
			-- very different sizes, a translucent gloss in the body color (never
			-- a white blob)
			local cov = coverage(balls, toTown, radius)
			T.truthy(cov >= 0.55, `{spec.Name} face is {math.floor(cov * 100)}% patterned`)
			local smallest, largest, gloss = math.huge, 0, 0
			for _, patch in spec.Patches do
				if patch.Transparency then
					gloss += 1
					T.truthy(patch.Transparency >= 0.4, spec.Name .. " gloss is translucent")
					local light = spec.Body:Lerp(Color3White, Planets.GlossLighten)
					T.truthy(patch.Color == light, spec.Name .. " gloss is the body color lightened")
				elseif not patch.Shade then
					smallest, largest = math.min(smallest, patch.Size), math.max(largest, patch.Size)
				end
				local c = patch.Color
				T.falsy(math.min(c.R, c.G, c.B) > 0.8 and (patch.Transparency or 0) < 0.4, spec.Name .. " has no white blob")
			end
			T.truthy(gloss >= 2 and gloss <= 3, spec.Name .. " gloss streak of 2-3 small caps")
			T.truthy(largest >= 2 * smallest and largest >= 14, `{spec.Name} caps vary in size ({smallest}..{largest})`)
			-- two/three-tone blotches: at least two colors besides the body
			local colors: { [string]: boolean } = {}
			local ringColors: { [string]: boolean } = {}
			local rings = 0
			for _, part in list do
				T.falsy(part.CanCollide, part:GetFullName() .. " never collides")
				T.falsy(part.CanQuery, part:GetFullName() .. " is not raycast")
				T.falsy(part.CanTouch, part:GetFullName() .. " is not touched")
				T.falsy(part.CastShadow, part:GetFullName() .. " casts no shadow")
				T.falsy(LobbyLayout.inArea(part.CFrame.Position), part:GetFullName() .. " is far outside the lobby")
				if part.Name:sub(1, 5) == "Patch" and part.Transparency == 0 then
					colors[tostring(part.Color)] = true
				elseif part.Name == "Ring" then
					rings += 1
					ringColors[tostring(part.Color)] = true
				end
			end
			local tones = 0
			for color in colors do
				if color ~= tostring(body.Color) then
					tones += 1
				end
			end
			T.truthy(tones >= 3, spec.Name .. " has three or more blotch colors")
			if spec.Ring then
				ringed += 1
				T.eq(rings, 20, spec.Name .. " has a ring of 20 flat segments")
				local ringTones = 0
				for _ in ringColors do
					ringTones += 1
				end
				-- overlapping coplanar segments must share one color (no z-fight flicker)
				T.eq(ringTones, 1, spec.Name .. " ring is one color")
				T.truthy(luminance(spec.Ring.Color) < luminance(spec.Body), spec.Name .. " ring is darker than the body")
				T.truthy(spec.Ring.Outer >= 1.7 and spec.Ring.Outer <= 1.8, spec.Name .. " ring is wide (Outer 1.7-1.8)")
				T.truthy(spec.Lean >= 24 and spec.Lean <= 30, spec.Name .. " ring is open (Lean 24-30)")
			end
		end
		T.truthy(count >= 2 and count <= 3, "two or three planets")
		T.eq(ringed, 1, "one ringed gas giant")
	end)

	T.test("sky: clouds and the airship keep clear of the planets in the hero and spawn shots", function()
		local root = build()
		for _, shot in { "lobby_hero", "lobby_spawn" } do
			local cf, tanY = camera(shot)
			-- the planets' discs (with the rim, or the ring) on screen
			local discs = {}
			for _, spec in Planets.Specs do
				local body = root.Planets[spec.Name].Body
				local center = body.CFrame.Position
				local x, y = project(cf, tanY, center)
				local reach = if spec.Ring then spec.Ring.Outer * 0.75 else Planets.RimScale
				local edge = center + cf.UpVector * body.Size.X / 2 * reach
				local _, ey = project(cf, tanY, edge)
				if x and y and ey then
					table.insert(discs, { Name = spec.Name, X = x * ASPECT, Y = y, R = math.abs(ey - y) })
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
			local things = { root.Airship }
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
	end)

	T.test("sky: the airship of concept v2", function()
		local root = build()
		local m = root:FindFirstChild("Airship")
		T.truthy(m and m:IsA("Model"), "Airship model")
		local list = parts(m)
		T.le(#list, Airship.MaxParts, "airship parts")
		T.eq(m.PrimaryPart and m.PrimaryPart.Name, "Envelope", "the airship bobs around its envelope")
		T.truthy(m:FindFirstChild("Gondola"), "a gondola under the envelope")
		-- a rounded bullet like concept v2, not stepped drums: ball nose and tail
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
