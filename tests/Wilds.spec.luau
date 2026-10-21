--[[
	Flora/Wilds (owner 2026-10-21, nature chat): the pebble, grass, flower,
	bush and stump groups and the five secrets are there, stay pure decoration
	(anchored, non-collide, no shadows, no lights), keep off the ore rocks, the
	plots and the keep-outs, and stay inside their part cap.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Wilds = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Wilds")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")

	local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
	local wilds = map.Emberfall.Lobby.Flora:FindFirstChild("Wilds")

	T.test("wilds: the groups and all five secrets are built", function()
		T.truthy(wilds, "the wilds are built")
		T.truthy(#wilds.Pieces:GetChildren() >= 40, `town pieces ({#wilds.Pieces:GetChildren()})`)
		T.truthy(#wilds.Mountains:GetChildren() >= 30, `mountain pieces ({#wilds.Mountains:GetChildren()})`)
		T.lt(#wilds.Pieces:GetChildren(), Wilds.MaxTown + 1, "town pieces within the cap")
		T.lt(#wilds.Mountains:GetChildren(), Wilds.MaxMountain + 1, "mountain pieces within the cap")
		for _, name in Wilds.SecretOrder do
			T.truthy(wilds.Secrets:FindFirstChild(name), `secret {name} found a spot`)
		end
	end)

	T.test("wilds: pure decoration, no lights, at most 1,200 parts", function()
		local parts, lights = 0, 0
		for _, d in wilds:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.truthy(d.Anchored, d:GetFullName() .. " is anchored")
				T.falsy(d.CanCollide or d.CastShadow or d.CanTouch or d.CanQuery, d:GetFullName() .. " is pure decoration")
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			end
		end
		T.eq(lights, 0, "no lights")
		T.lt(parts, 1201, "parts")
	end)

	T.test("wilds: off the ore rocks, the plots and the keep-outs", function()
		local spawns = WorldBuilder.generateNodeSpawns()
		for _, folder in { wilds.Pieces, wilds.Secrets } do
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					local h = math.max(d.Size.X, d.Size.Z) / 2
					for _, s in spawns do
						if s.Zone == "Outcrops" then
							local dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(s.Position.X, 0, s.Position.Z)).Magnitude - h
							T.truthy(dist > 3, `{d:GetFullName()} stays off the ore rock at {s.Position}`)
						end
					end
					for _, plot in WorldLayout.Plots do
						T.falsy(LobbyLayout.onBase(plot, Vector3.new(p.X, 0, p.Z), 0), `{d:GetFullName()} stays off plot {plot.Id}`)
					end
					T.falsy(WorldLayout.isKeepOut(Vector3.new(p.X, 0, p.Z), 0), `{d:GetFullName()} stays out of the keep-outs`)
				end
			end
		end
	end)
end
