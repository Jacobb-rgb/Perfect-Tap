--[[
	Lobby package Backdrop (src/server/World/Lobby/Backdrop, Land.luau
	restyle; docs/plans/LOBBY_PLAN.md 6.2): every piece is built inside its
	footprint and part/light budget, the DEPTHS opening stays open and
	walkable, the massif keeps off the caves, the falls' pools and props keep
	off the quarry's node spawns, and Land keeps the base yards clear.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Backdrop = Loader.requirePath("ServerScriptService.Server.World.Lobby.Backdrop")

	local game = roblox.Instance.new("DataModel")
	local map = WorldBuilder.build(game:GetService("Workspace"))
	local backdrop = map.Emberfall.Lobby.Backdrop

	-- world AABB of a part
	local function bounds(part): (any, any)
		local cf, size = part.CFrame, part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		local p = cf.Position
		return Vector3.new(p.X - hx, p.Y - hy, p.Z - hz), Vector3.new(p.X + hx, p.Y + hy, p.Z + hz)
	end

	local function overlaps(aMin, aMax, bMin, bMax): boolean
		return aMin.X < bMax.X and aMax.X > bMin.X and aMin.Y < bMax.Y and aMax.Y > bMin.Y and aMin.Z < bMax.Z and aMax.Z > bMin.Z
	end

	local function parts(model): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function lights(model): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") then
				n += 1
			end
		end
		return n
	end

	-- Per-piece slack around the footprint (studs): horizontal, below, above.
	-- Plan-driven exceptions: the massif reaches the ground outside the caves,
	-- the DEPTHS frames go into the tunnel and the lintel covers the tunnel
	-- roof's front edge, the west fall pours from the tier-1 lip at y ~45,
	-- trees stand on top of the NW cliff.
	local slack = {
		ForgeMountain = { 3, 42, 8 },
		DepthsPortal = { 8, 1, 2 },
		QuarryFallsWest = { 10, 1, 12 },
		QuarryFallsEast = { 8, 1, 2 },
		NWCliff = { 6, 1, 16 },
		MineEntrance = { 6, 1, 4 },
		MineYard = { 6, 1, 5 }, -- the lantern post
	}
	-- Sub-models that leave the footprint on purpose (plan 6.2: the ore chute
	-- runs down to the quarry floor; the summit cascade falls down the massif;
	-- the Spectrum spires make the skyline behind and beside the massif).
	local exempt = { Chute = true, Cascade = true, Spires = true }

	T.test("backdrop builds every piece inside its footprint", function()
		for _, piece in LobbyLayout.ofPackage("Backdrop") do
			local model = backdrop:FindFirstChild(piece.Id)
			T.truthy(model and model:IsA("Model"), "Backdrop builds " .. piece.Id)
			local s = slack[piece.Id] or { 6, 1, 2 }
			local frame = LobbyLayout.frame(piece)
			for _, part in parts(model) do
				local skip = false
				local node = part.Parent
				while node and node ~= model do
					skip = skip or exempt[node.Name] == true
					node = node.Parent
				end
				if not skip then
					local min, max = bounds(part)
					for _, x in { min.X, max.X } do
						for _, z in { min.Z, max.Z } do
							local lp = frame:PointToObjectSpace(Vector3.new(x, piece.Center.Y, z))
							T.truthy(
								math.abs(lp.X) <= piece.Size.X / 2 + s[1] and math.abs(lp.Z) <= piece.Size.Z / 2 + s[1],
								`{part:GetFullName()} leaves the {piece.Id} footprint ({x}, {z})`
							)
						end
					end
					T.truthy(min.Y >= piece.Center.Y - s[2], `{part:GetFullName()} reaches below {piece.Id} ({min.Y})`)
					T.truthy(max.Y <= piece.Center.Y + piece.Size.Y + s[3], `{part:GetFullName()} rises above {piece.Id} ({max.Y})`)
				end
			end
		end
		-- the exempt spires stay on the island, behind the quarry and above the caves
		local spires = backdrop.ForgeMountain:FindFirstChild("Spires")
		if spires then
			local island = WorldLayout.Island
			for _, part in parts(spires) do
				local min, max = bounds(part)
				T.truthy(
					min.X >= island.Min.X and max.X <= island.Max.X and max.Z <= -240 and min.Z >= -440 and min.Y >= 23.9,
					`{part:GetFullName()} stays in the spire zone ({min} {max})`
				)
			end
		end
		-- the exempt chute stays between the works deck and the quarry floor
		local chute = backdrop.ForgeWorks:FindFirstChild("Chute")
		T.truthy(chute, "ForgeWorks has its ore chute")
		for _, part in parts(chute) do
			local min, max = bounds(part)
			T.truthy(
				min.X >= 17 and max.X <= 51 and min.Y >= -12.1 and max.Z <= -214 and min.Z >= -247,
				`{part:GetFullName()} stays on the chute line ({min} {max})`
			)
		end
	end)

	T.test("backdrop stays inside its part and light budgets", function()
		local budget = LobbyLayout.Budget.Packages.Backdrop
		local all = parts(backdrop)
		local inLobby = 0
		for _, part in all do
			if LobbyLayout.inArea(part.CFrame.Position) then
				inLobby += 1
			end
		end
		T.le(#all, budget.Parts, "Backdrop parts")
		T.le(inLobby, budget.LobbyParts, "Backdrop parts in the lobby")
		T.le(lights(backdrop), budget.Lights, "Backdrop lights")
		-- the per-piece budgets of LOBBY_PLAN 6.2
		local plan = {
			-- raised from 700 by the 2026-10 polish pass (grass drips, big
			-- crystals, huts, more trees); the massif stands outside the lobby
			-- area and streams as a StreamingMesh LOD
			-- 1500 with the Spectrum strata and spires (2026-10-17)
			ForgeMountain = { 1500, 2 },
			DepthsPortal = { 90, 1 },
			ForgeWorks = { 160, 1 },
			DepthsRails = { 60, 0 },
			QuarryFallsWest = { 40, 0 },
			QuarryFallsEast = { 40, 0 },
			ScaffoldWest = { 50, 0 },
			ScaffoldWest2 = { 50, 0 },
			Crane = { 60, 0 },
			Beacon = { 30, 1 },
			MineEntrance = { 140, 1 },
			MineYard = { 90, 0 },
		}
		for id, b in plan do
			local model = backdrop[id]
			T.le(#parts(model), b[1], id .. " parts")
			T.le(lights(model), b[2], id .. " lights")
		end
		T.le(#parts(backdrop.NWCliff) + #parts(backdrop.NWPool), 130, "NWCliff + NWPool parts")
		T.le(lights(backdrop.NWCliff) + lights(backdrop.NWPool), 1, "NWCliff + NWPool lights")
		-- Land grows by at most LandExtraParts and adds no lights over the old 28
		local landParts = #parts(map.Land)
		T.le(landParts, LobbyLayout.Budget.LandBaselineParts + LobbyLayout.Budget.LandExtraParts, "Land parts")
		T.le(lights(map.Land), 28, "Land lights")
	end)

	T.test("the DEPTHS opening is open and walkable", function()
		local openMin = Vector3.new(-9, -11.5, -246)
		local openMax = Vector3.new(9, 4, -222)
		for _, part in parts(map) do
			if part.CanCollide and part.Transparency < 1 and part.Name ~= "NodeSpawn" then
				local min, max = bounds(part)
				T.falsy(overlaps(min, max, openMin, openMax), part:GetFullName() .. " blocks the DEPTHS opening")
			end
		end
		-- solid floor along the walk from the quarry into the tunnel
		for _, z in { -244, -238, -232, -226 } do
			local probe = Vector3.new(0, -12.4, z)
			local floored = false
			for _, part in parts(map) do
				if part.CanCollide then
					local min, max = bounds(part)
					if overlaps(min, max, probe - Vector3.new(0.1, 0.1, 0.1), probe + Vector3.new(0.1, 0.1, 0.1)) then
						floored = true
						break
					end
				end
			end
			T.truthy(floored, `floor under the DEPTHS walk at z {z}`)
		end
	end)

	T.test("the massif keeps off the caves and stays low above the portal", function()
		for _, part in parts(backdrop.ForgeMountain) do
			local min, max = bounds(part)
			if max.X > -74 + 0.5 and min.X < 74 - 0.5 then
				T.truthy(min.Y >= 21.9, part:GetFullName() .. " goes below the cave roof")
			end
		end
		for _, part in parts(backdrop.ForgeMountain.Rock) do
			local min, max = bounds(part)
			local c = (min + max) / 2
			if c.X > -22 and c.X < 17 and c.Z > -256 then
				T.truthy(max.Y < 28, `{part:GetFullName()} hides the DEPTHS portal ({min} {max})`)
			end
		end
	end)

	T.test("signs and hooks of the backdrop exist", function()
		local texts = {}
		for _, d in backdrop:GetDescendants() do
			if d:IsA("TextLabel") then
				texts[d.Text] = true
			end
		end
		for _, text in { "DEPTHS", "PWR", "MINE" } do
			T.truthy(texts[text], "sign " .. text)
		end
		-- no board may carry another game's title (owner 2026-10-20: "The Forge" is one)
		for _, d in map:GetDescendants() do
			if d:IsA("TextLabel") then
				local plain = string.upper(string.gsub(d.Text, "%s+", " "))
				T.falsy(plain == "THE FORGE", `{d:GetFullName()} reads "THE FORGE"`)
			end
		end
		local mouth = backdrop.MineEntrance:FindFirstChild("MineMouth")
		T.truthy(mouth and mouth:IsA("BasePart"), "MineMouth part")
		for _, d in map.Land:GetDescendants() do
			if d:IsA("TextLabel") then
				T.falsy(d.Text == "EMBER CAVES", "Land's EMBER CAVES sign is gone")
			end
		end
	end)

	T.test("falls, rails and chute keep off the quarry's node spawns", function()
		local nodes = {}
		for _, s in WorldBuilder.generateNodeSpawns() do
			if s.Zone == "Quarry" then
				table.insert(nodes, s.Position)
			end
		end
		local function clear(model, radius)
			for _, part in parts(model) do
				local min, max = bounds(part)
				if min.Y < -8 then
					for _, n in nodes do
						local dx = math.max(min.X - n.X, 0, n.X - max.X)
						local dz = math.max(min.Z - n.Z, 0, n.Z - max.Z)
						T.truthy(math.sqrt(dx * dx + dz * dz) >= radius, `{part:GetFullName()} sits on the node at {n}`)
					end
				end
			end
		end
		clear(backdrop.QuarryFallsWest, 4)
		clear(backdrop.QuarryFallsEast, 4)
		clear(backdrop.DepthsRails, 2.5)
		clear(backdrop.ForgeWorks.Chute, 4)
	end)

	T.test("Land keeps the base yards flat and free of decoration", function()
		for _, part in parts(map.Land) do
			local min, max = bounds(part)
			if max.Y > 0.3 and part.Name ~= "Boundary" then
				for _, plot in WorldLayout.Plots do
					local hit = false
					for _, x in { min.X, (min.X + max.X) / 2, max.X } do
						for _, z in { min.Z, (min.Z + max.Z) / 2, max.Z } do
							hit = hit or LobbyLayout.onBase(plot, Vector3.new(x, 0, z), 0)
						end
					end
					T.falsy(hit, `{part:GetFullName()} stands on base {plot.Id} at {part.CFrame.Position}`)
				end
			end
		end
		-- the east and west rim stays outside the island's edge + 1 next to the
		-- yards (|x| 171 at 12 cells)
		local island = WorldLayout.Island
		local rimX = island.Max.X + 1
		local boardwalkX = 166 + WorldLayout.PlotGrid.CoastShift
		for _, part in parts(map.Land.Cliffs) do
			local min, max = bounds(part)
			if max.Y > 0 and min.Z < island.Max.Z then
				T.truthy(min.X > rimX or max.X < -rimX, `{part:GetFullName()} rim block inside |x| {rimX}`)
			end
			-- the NEXT AREA boardwalk crosses the east rim at deck height ~5
			if max.X > boardwalkX and min.Z < -111 and max.Z > -119 then
				T.truthy(max.Y <= 5, part:GetFullName() .. " clips the NEXT AREA boardwalk")
			end
		end
	end)

	T.test("SKY HAVEN can be reached: the south wall's gate and the plank bridge lead clear to the first stone", function()
		local gate = WorldLayout.SouthGate
		local coast = WorldLayout.Island.Max.Z
		local stoneZ = coast + 36 - 16 - 2.5 -- the first stone's near edge (SkyHaven: the spire 36 out, the stones 16 round it)
		-- nothing collidable stands in the walk from the lawn through the gate to the stone
		local lo = Vector3.new(gate.X - gate.Width / 2 + 0.3, 2.0, coast - 4)
		local hi = Vector3.new(gate.X + gate.Width / 2 - 0.3, 7, stoneZ)
		for _, part in parts(map) do
			if part.CanCollide then
				local min, max = bounds(part)
				T.falsy(overlaps(min, max, lo, hi), `{part:GetFullName()} blocks the way to SKY HAVEN`)
			end
		end
		-- and a solid bridge carries you from the gate over the rim and the sea to the stone
		local haven = map:FindFirstChild("SkyHaven", true)
		local carried = false
		for _, part in parts(haven) do
			local min, max = bounds(part)
			carried = carried
				or (
					part.CanCollide
					and min.X <= gate.X - 1
					and max.X >= gate.X + 1
					and min.Z <= coast + 4
					and max.Z >= stoneZ
					and max.Y >= 1.8
				)
		end
		T.truthy(carried, "a plank bridge from the gate to the first stone")
	end)

	T.test("the south coast runs straight, no sea bay behind the vault (owner 2026-10-22)", function()
		local island = WorldLayout.Island
		T.falsy(map.Land:FindFirstChild("Bay"), "no bay sea")
		-- north, west, east and the south wall in two pieces round SKY HAVEN's gate, its two short side walls
		T.eq(#map.Land.Bounds:GetChildren(), 7, "the island's invisible walls")
		-- the ground covers the lawn behind the vault (x -52..52, the plot
		-- roads' inner verges) from the 12-cell coast (z 150) out to the south coast
		local covered = false
		for _, part in map.Land:GetChildren() do
			if part.Name == "Ground" then
				local min, max = bounds(part)
				local whole = min.X <= -52 and max.X >= 52 and min.Z <= 150 and max.Z >= island.Max.Z
				covered = covered or (whole and math.abs(max.Y) < 0.01)
			end
		end
		T.truthy(covered, "the ground covers x -52..52 from z 150 to the south coast")
		-- the south wall spans the island's whole width but for SKY HAVEN's gate (WorldLayout.SouthGate):
		-- probe the coast every 2 studs just outside the island's edge
		local gate = WorldLayout.SouthGate
		local x = island.Min.X
		while x <= island.Max.X do
			local walled = false
			for _, part in map.Land.Bounds:GetChildren() do
				local min, max = bounds(part)
				walled = walled or (min.X <= x and max.X >= x and min.Z >= island.Max.Z and min.Z < island.Max.Z + 6)
			end
			local open = math.abs(x - gate.X) < gate.Width / 2
			T.eq(walled, not open, `south coast at x {x} walled (only the SKY HAVEN gate is open)`)
			x += 2
		end
		-- the south rim: one straight line of columns along the whole coast at its
		-- inner face (Land: the island's edge + 3), nothing of it inland; only the
		-- stream's waterfall keeps it low (Land.RimNotch)
		local rimZ = island.Max.Z + 3
		local caps = {}
		for _, part in parts(map.Land.Cliffs) do
			local min, max = bounds(part)
			if max.X > island.Min.X and min.X < island.Max.X and max.Z > island.Max.Z - 20 then
				T.truthy(min.Z >= rimZ - 0.35, `{part:GetFullName()} rim block inland at {part.CFrame.Position}`)
				if min.Z < rimZ and max.Y > -0.25 then
					table.insert(caps, { min.X, max.X })
				end
			end
		end
		local x = island.Min.X
		while x <= island.Max.X do
			local on = false
			for _, c in caps do
				on = on or (c[1] <= x and x <= c[2])
			end
			T.truthy(on, `the south rim runs on at x {x}`)
			x += 2
		end
	end)

	T.test("the backdrop build is deterministic", function()
		local a = roblox.Instance.new("Model")
		local b = roblox.Instance.new("Model")
		Backdrop.build(a, Rng.new("backdrop-test"))
		Backdrop.build(b, Rng.new("backdrop-test"))
		local pa, pb = parts(a), parts(b)
		T.eq(#pa, #pb, "same part count")
		local sum = 0
		for i, part in pa do
			sum += (part.CFrame.Position - pb[i].CFrame.Position).Magnitude
		end
		T.near(sum, 0, 1e-6, "same positions")
	end)
end
