--[[
	Flora/Meadow: nothing of the meadow (ponds, trees, fences, lawn) grows
	where an ore rock grows at runtime (the node spawns), and it stays pure
	decoration (non-collide, no shadows, no lights).
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
end
