--[[
	Lobby package "Sky" (src/server/World/Lobby/Sky, docs/plans/LOBBY_PLAN.md
	6.1, docs/plans/VISUAL_UPGRADE_PLAN.md): every set piece is built inside
	its LobbyLayout footprint and part budget, clouds stay out of the lobby
	area and are puffy clusters with lit undersides, the three planets hang
	1500-3000 studs out in the north-west..north-east sky (big, cheap,
	two/three-tone, one ringed, never in front of the sun), the airship is a
	cheap bobbing Spin model, the balloon and the ships are tagged Spin, the
	build is deterministic, and the golden-hour Lighting in
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

	T.test("sky: balloon and ships are tagged Spin and stream as one piece", function()
		local root = build()
		local expected = {
			Balloon = { SpinSpeed = 0.05, BobHeight = 2, BobSpeed = 0.5 },
			ShipA = { SpinSpeed = 0, BobHeight = 0.5, BobSpeed = 0.8 },
			ShipB = { SpinSpeed = 0, BobHeight = 0.5, BobSpeed = 0.8 },
			Airship = { SpinSpeed = 0, BobHeight = 3, BobSpeed = 0.35 },
		}
		for id, attrs in expected do
			local m = root:FindFirstChild(id)
			T.truthy(table.find(m:GetTags(), "Spin"), id .. " is tagged Spin")
			T.truthy(m.PrimaryPart and m.PrimaryPart:IsDescendantOf(m), id .. " has a PrimaryPart")
			T.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, id .. " streams atomically")
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

	T.test("sky: clouds are puffy stacked clusters with lit undersides", function()
		local root = build()
		local clusters = 0
		for _, cloud in root.CloudBanks:GetChildren() do
			if cloud:IsA("Model") then
				clusters += 1
				local list = parts(cloud)
				T.truthy(#list >= 12, cloud:GetFullName() .. " is a stacked cluster, not a slab")
				local minY, maxY = math.huge, -math.huge
				local minX, maxX = math.huge, -math.huge
				local lowestGlow = math.huge
				for _, part in list do
					local p = part.CFrame.Position
					local half = part.Size.Y / 2
					minY = math.min(minY, p.Y - half)
					maxY = math.max(maxY, p.Y + half)
					minX = math.min(minX, p.X)
					maxX = math.max(maxX, p.X)
					if part.Material == roblox.Enum.Material.Neon and part.Size.Y < 0.5 then
						lowestGlow = math.min(lowestGlow, p.Y)
					end
				end
				-- a heap, not a slab: the cluster is at least a third as tall as wide
				-- (measured along the world X spread of its part centers)
				local width = math.max(1, maxX - minX)
				T.truthy((maxY - minY) / width > 0.3 or (maxY - minY) > 40, cloud:GetFullName() .. " is puffy")
				-- a glowing sheet under the belly lights the underside
				T.truthy(lowestGlow < minY + (maxY - minY) * 0.25, cloud:GetFullName() .. " has a lit underside")
			end
		end
		T.truthy(clusters >= 12, "a dozen or more cloud clusters")
	end)

	T.test("sky: three big Kenney-style planets frame the mountain", function()
		local root = build()
		local planets = root:FindFirstChild("Planets")
		T.truthy(planets and planets:IsA("Model"), "Planets model")
		local sun = LobbyLayout.SunDirection
		local ringed = 0
		local count = 0
		for _, spec in Planets.Specs do
			count += 1
			local m = planets:FindFirstChild(spec.Name)
			T.truthy(m and m:IsA("Model"), "planet " .. spec.Name)
			local list = parts(m)
			T.le(#list, Planets.MaxParts, spec.Name .. " parts")
			T.eq(m.LevelOfDetail, roblox.Enum.ModelLevelOfDetail.StreamingMesh, spec.Name .. " streams as a Lod mesh")
			local body = m:FindFirstChild("Body")
			T.truthy(body and body.Shape == roblox.Enum.PartType.Ball, spec.Name .. " has a Ball body")
			T.truthy(
				m:FindFirstChild("Rim") and m.Rim.Material == roblox.Enum.Material.Neon and m.Rim.Transparency > 0.5,
				spec.Name .. " glowing rim"
			)
			local center = body.CFrame.Position
			-- far away, high, from the north-west to the north-east, big on screen
			local flat = Vector3.new(center.X, 0, center.Z)
			T.truthy(flat.Magnitude >= 1500 and flat.Magnitude <= 3000, `{spec.Name} hangs 1500-3000 studs out ({flat.Magnitude})`)
			local bearing = math.deg(math.atan2(center.X, -center.Z)) % 360
			T.truthy(bearing >= 300 or bearing <= 60, `{spec.Name} is in the north-west..north-east sky ({bearing})`)
			T.truthy(center.Y > body.Size.X / 2 * 0.5, spec.Name .. " is high in the sky")
			local angular = math.deg(2 * math.atan(body.Size.X / 2 / center.Magnitude))
			T.truthy(angular >= 6, `{spec.Name} is big on screen ({angular} degrees)`)
			-- never in front of the sun: the whole planet (ring included) keeps clear of it
			local reach = math.deg(math.atan(body.Size.X * (if spec.Rings then 1.0 else 0.55) / center.Magnitude))
			local apart = math.deg(math.acos(math.clamp(center.Unit:Dot(sun), -1, 1)))
			T.truthy(apart > reach + 15, `{spec.Name} keeps clear of the sun ({apart} vs {reach})`)
			-- two/three-tone blotches: at least two colors besides the body
			local colors: { [string]: boolean } = {}
			local rings = 0
			for _, part in list do
				T.falsy(part.CanCollide, part:GetFullName() .. " never collides")
				T.falsy(part.CanQuery, part:GetFullName() .. " is not raycast")
				T.falsy(part.CanTouch, part:GetFullName() .. " is not touched")
				T.falsy(part.CastShadow, part:GetFullName() .. " casts no shadow")
				T.falsy(LobbyLayout.inArea(part.CFrame.Position), part:GetFullName() .. " is far outside the lobby")
				if part.Name:sub(1, 5) == "Patch" then
					colors[tostring(part.Color)] = true
				elseif part.Name:sub(1, 4) == "Ring" then
					rings += 1
				end
			end
			local tones = 0
			for color in colors do
				if color ~= tostring(body.Color) then
					tones += 1
				end
			end
			T.truthy(tones >= 2, spec.Name .. " has two or more blotch colors")
			if spec.Rings then
				ringed += 1
				T.truthy(rings >= 16, spec.Name .. " has a ring of flat segments")
			end
		end
		T.truthy(count >= 2 and count <= 3, "two or three planets")
		T.eq(ringed, 1, "one ringed gas giant")
	end)

	T.test("sky: the airship of concept v2", function()
		local root = build()
		local m = root:FindFirstChild("Airship")
		T.truthy(m and m:IsA("Model"), "Airship model")
		local list = parts(m)
		T.le(#list, Airship.MaxParts, "airship parts")
		T.eq(m.PrimaryPart and m.PrimaryPart.Name, "Envelope", "the airship bobs around its envelope")
		T.truthy(m:FindFirstChild("Gondola"), "a gondola under the envelope")
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
