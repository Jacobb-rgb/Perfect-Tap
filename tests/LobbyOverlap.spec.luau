--[[
	Lobby overlap checks (lobby fix round 2, axis-aligned boxes on the
	ground plane): every lantern (a Model named "Lantern" outside the town
	buildings) keeps 2 studs of air to the stall showcases, the cafe
	tables and the ponds' footprints, and every
	tree crown keeps clear of the signs, the showcases and the ponds.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	type Box = { Name: string, Lo: any, Hi: any }

	-- world XZ box of a part (rotation included)
	local function partBox(part: any): (any, any)
		local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = part.CFrame:GetComponents()
		local s = part.Size
		local ex = math.abs(r00) * s.X / 2 + math.abs(r01) * s.Y / 2 + math.abs(r02) * s.Z / 2
		local ez = math.abs(r20) * s.X / 2 + math.abs(r21) * s.Y / 2 + math.abs(r22) * s.Z / 2
		local p = part.CFrame.Position
		return Vector3.new(p.X - ex, 0, p.Z - ez), Vector3.new(p.X + ex, 0, p.Z + ez)
	end

	local function modelBox(m: any, filter: ((any) -> boolean)?): (any?, any?)
		local lo, hi = nil, nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and (not filter or filter(d)) then
				local a, b = partBox(d)
				lo = if lo then Vector3.new(math.min(lo.X, a.X), 0, math.min(lo.Z, a.Z)) else a
				hi = if hi then Vector3.new(math.max(hi.X, b.X), 0, math.max(hi.Z, b.Z)) else b
			end
		end
		return lo, hi
	end

	local function gap(aLo: any, aHi: any, bLo: any, bHi: any): number
		local dx = math.max(bLo.X - aHi.X, 0, aLo.X - bHi.X)
		local dz = math.max(bLo.Z - aHi.Z, 0, aLo.Z - bHi.Z)
		return math.sqrt(dx * dx + dz * dz)
	end

	-- the ponds' footprints (axis-aligned pieces)
	local function pieceBox(id: string): Box
		local piece = LobbyLayout.get(id)
		local c, s = piece.Center, piece.Size
		return { Name = id, Lo = Vector3.new(c.X - s.X / 2, 0, c.Z - s.Z / 2), Hi = Vector3.new(c.X + s.X / 2, 0, c.Z + s.Z / 2) }
	end

	local cached: any = nil
	local function world(): any
		if not cached then
			local game = roblox.Instance.new("DataModel")
			cached = WorldBuilder.build(game:GetService("Workspace"))
		end
		return cached
	end

	T.test("lobby overlap: lanterns keep 2 studs off showcases, town buildings, cafe tables and ponds", function()
		local lobby = world().Emberfall.Lobby
		local town = lobby.Flora:FindFirstChild("Town")
		local obstacles: { Box } = { pieceBox("LilyPond"), pieceBox("KoiPond") }
		for _, d in lobby:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Showcase" then
				local lo, hi = partBox(d)
				table.insert(obstacles, { Name = d:GetFullName(), Lo = lo, Hi = hi })
			end
		end
		-- the cafe tables of the town (the INN's street cafe)
		for _, d in lobby:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "CafeTable" then
				local lo, hi = partBox(d)
				table.insert(obstacles, { Name = d:GetFullName(), Lo = lo, Hi = hi })
			end
		end
		local checked = 0
		for _, m in lobby:GetDescendants() do
			-- free-standing lanterns (a town building's own wall lamps belong to it)
			if m:IsA("Model") and m.Name == "Lantern" and not (town and m:IsDescendantOf(town)) then
				local lo, hi = modelBox(m)
				if lo and hi then
					checked += 1
					for _, o in obstacles do
						local g = gap(lo, hi, o.Lo, o.Hi)
						T.truthy(g >= 2, `{m:GetFullName()} at {lo} is {g} studs from {o.Name}`)
					end
				end
			end
		end
		T.truthy(checked >= 20, `lanterns checked ({checked})`)
	end)

	T.test("lobby overlap: tree crowns keep clear of signs, showcases and ponds", function()
		local lobby = world().Emberfall.Lobby
		local obstacles: { Box } = { pieceBox("LilyPond"), pieceBox("KoiPond") }
		for _, d in lobby:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Showcase" or d.Name == "Sign" or d.Name == "TownSign" or d.Name == "BladeSign") then
				local lo, hi = partBox(d)
				table.insert(obstacles, { Name = d:GetFullName(), Lo = lo, Hi = hi })
			end
		end
		for _, tree in lobby.Flora:GetDescendants() do
			if tree:IsA("Model") and tree.Name == "Tree" then
				local lo, hi = modelBox(tree, function(part: any): boolean
					-- the crown: leaf blocks (not the trunk, not trunk-brown stubs)
					local c = part.Color
					local trunkish = c.R > c.G and c.G > c.B and c.G < 0.35
					return part.Name ~= "Trunk" and not part.CanCollide and not trunkish
				end)
				if lo and hi then
					for _, o in obstacles do
						local g = gap(lo, hi, o.Lo, o.Hi)
						T.truthy(g >= 0.5, `{tree:GetFullName()} crown at {lo} touches {o.Name} ({g})`)
					end
				end
			end
		end
	end)
end
