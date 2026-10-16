--[[
	Lobby package "Sky" (src/server/World/Lobby/Sky, docs/plans/LOBBY_PLAN.md
	6.1): every set piece is built inside its LobbyLayout footprint and part
	budget, clouds stay out of the lobby area, the balloon and the ships are
	tagged Spin, the build is deterministic, and the golden-hour Lighting in
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
