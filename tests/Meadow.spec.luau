--[[
	Flora/Meadow: nothing of the meadow (ponds, trees, fences, lawn) grows
	where an ore rock grows at runtime (the node spawns), it stays pure
	decoration (non-collide, no shadows, no lights), and its ponds are there.
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
				local p = d.CFrame.Position
				local h = math.max(d.Size.X, d.Size.Z) / 2
				for _, s in spawns do
					if s.Zone == "Outcrops" then
						local dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(s.Position.X, 0, s.Position.Z)).Magnitude - h
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
end
