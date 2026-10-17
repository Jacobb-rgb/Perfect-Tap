--[[
	Backdrop Horizon (src/server/World/Lobby/Backdrop/Horizon): the outer sea
	closes every gap to the Land sea without overlaps and keeps each strip
	under Roblox's part size limit; everything out there is unreachable
	decoration (no collision, raycasts, touches, shadows or lights) far off
	the island and clear of the Sky pieces; turning models have a
	PrimaryPart; the build is deterministic and inside its part budget.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Horizon = Loader.requirePath("ServerScriptService.Server.World.Lobby.Backdrop.Horizon")

	local game = roblox.Instance.new("DataModel")
	local map = WorldBuilder.build(game:GetService("Workspace"))
	local horizon = map.Emberfall.Lobby.Backdrop:FindFirstChild("Horizon")

	local function parts(model): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

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

	T.test("horizon builds its ring, isles, ships and sky life", function()
		T.truthy(horizon, "Backdrop builds Horizon")
		for _, name in { "Ring", "Isles", "Pirates", "SkyLife" } do
			T.truthy(horizon:FindFirstChild(name), "Horizon." .. name)
		end
	end)

	T.test("the outer sea closes the gap to the Land sea without overlaps", function()
		local strips = {}
		for _, p in map.Land.Sea:GetChildren() do
			table.insert(strips, p)
		end
		local outer = horizon.Ring.OuterSea:GetChildren()
		T.eq(#outer, 10, "outer sea strips")
		for _, p in outer do
			table.insert(strips, p)
			T.truthy(p.Size.X <= 2048 and p.Size.Z <= 2048, `{p:GetFullName()} stays under the part size limit`)
		end
		local area = 0
		local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
		for i, a in strips do
			local amin, amax = bounds(a)
			T.near(amax.Y, -21, 1e-3, `{a:GetFullName()} top at sea level`)
			area += (amax.X - amin.X) * (amax.Z - amin.Z)
			lo = Vector3.new(math.min(lo.X, amin.X), 0, math.min(lo.Z, amin.Z))
			hi = Vector3.new(math.max(hi.X, amax.X), 0, math.max(hi.Z, amax.Z))
			for j = i + 1, #strips do
				local bmin, bmax = bounds(strips[j])
				local overlap = amin.X < bmax.X - 0.01 and amax.X > bmin.X + 0.01 and amin.Z < bmax.Z - 0.01 and amax.Z > bmin.Z + 0.01
				T.falsy(overlap, `{a:GetFullName()} overlaps {strips[j]:GetFullName()}`)
			end
		end
		-- no overlaps + the areas add up to the frame around the island = no gaps
		local island = WorldLayout.Island
		local hole = (island.Max.X - island.Min.X + 12) * (island.Max.Z - island.Min.Z + 36)
		T.near(area, (hi.X - lo.X) * (hi.Z - lo.Z) - hole, 1, "sea area")
		T.truthy(hi.X - lo.X > 5000 and hi.Z - lo.Z > 5000, "the sea reaches past the haze")
	end)

	T.test("the horizon is unreachable decoration without lights", function()
		for _, part in parts(horizon) do
			T.falsy(part.CanCollide or part.CanQuery or part.CanTouch or part.CastShadow, part:GetFullName() .. " is pure decoration")
		end
		for _, d in horizon:GetDescendants() do
			T.falsy(d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight"), d:GetFullName() .. " is a light")
			if d:IsA("Model") and table.find(d:GetTags(), "Spin") then
				T.truthy(d.PrimaryPart, d:GetFullName() .. " (Spin) has a PrimaryPart")
			end
		end
		T.eq(horizon.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent, "Horizon streams Persistent")
	end)

	T.test("the horizon keeps off the island and the Sky pieces", function()
		local island = WorldLayout.Island
		local keepMin = Vector3.new(island.Min.X - 150, 0, island.Min.Z - 150)
		local keepMax = Vector3.new(island.Max.X + 150, 0, island.Max.Z + 150)
		local sky = LobbyLayout.ofPackage("Sky")
		for _, part in parts(horizon) do
			local min, max = bounds(part)
			local sea = part.Parent and part.Parent.Name == "OuterSea"
			-- sky life may hang over the town, everything else stays far out
			local inSky = part:FindFirstAncestor("SkyLife") ~= nil and min.Y > 50
			if not sea and not inSky then
				local over = min.X < keepMax.X and max.X > keepMin.X and min.Z < keepMax.Z and max.Z > keepMin.Z
				T.falsy(over, `{part:GetFullName()} comes close to the island ({min} {max})`)
			end
			if not sea then
				for _, piece in sky do
					local frame = LobbyLayout.frame(piece)
					local hit = false
					for i = 0, 2 do
						for j = 0, 2 do
							for k = 0, 2 do
								local p = Vector3.new(min.X + (max.X - min.X) * i / 2, min.Y + (max.Y - min.Y) * j / 2, min.Z + (max.Z - min.Z) * k / 2)
								local lp = frame:PointToObjectSpace(Vector3.new(p.X, piece.Center.Y, p.Z))
								hit = hit
									or (
										math.abs(lp.X) <= piece.Size.X / 2 + 4
										and math.abs(lp.Z) <= piece.Size.Z / 2 + 4
										and p.Y >= piece.Center.Y - 2
										and p.Y <= piece.Center.Y + piece.Size.Y + 2
									)
							end
						end
					end
					T.falsy(hit, `{part:GetFullName()} is inside the Sky piece {piece.Id}`)
				end
			end
		end
	end)

	T.test("the horizon build is deterministic and inside its budget", function()
		local a = roblox.Instance.new("Model")
		local b = roblox.Instance.new("Model")
		Horizon.build(a, Rng.new("horizon-test"))
		Horizon.build(b, Rng.new("horizon-test"))
		local pa, pb = parts(a), parts(b)
		T.eq(#pa, #pb, "same part count")
		local sum = 0
		for i, part in pa do
			sum += (part.CFrame.Position - pb[i].CFrame.Position).Magnitude
		end
		T.near(sum, 0, 1e-6, "same positions")
		T.le(#parts(horizon), 1150, "Horizon parts")
	end)
end
