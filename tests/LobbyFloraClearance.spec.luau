--[[
	Lobby tree clearance (fix round 1): every tree crown in the lobby (the
	Flora hero trees, the town-edge belts and the scatter) keeps at least a
	stud of air to every stall (Districts piece footprints) and every town
	building site (Flora/Town.Sites), so no crown cuts into a facade, a sign
	or a roof.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Town = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Town")

	-- world XZ box of a part (rotation included)
	local function box(part: any): (any, any)
		local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = part.CFrame:GetComponents()
		local s = part.Size
		local ex = math.abs(r00) * s.X / 2 + math.abs(r01) * s.Y / 2 + math.abs(r02) * s.Z / 2
		local ez = math.abs(r20) * s.X / 2 + math.abs(r21) * s.Y / 2 + math.abs(r22) * s.Z / 2
		local p = part.CFrame.Position
		return Vector3.new(p.X - ex, 0, p.Z - ez), Vector3.new(p.X + ex, 0, p.Z + ez)
	end

	T.test("lobby trees: every crown keeps a stud off the stalls and the town buildings", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local flora = map.Emberfall.Lobby.Flora
		local stalls = {}
		for _, piece in LobbyLayout.Pieces do
			if piece.Package == "Districts" and LobbyLayout.isGroundPiece(piece) then
				table.insert(stalls, piece)
			end
		end
		local trees = 0
		for _, tree in flora:GetDescendants() do
			if tree:IsA("Model") and tree.Name == "Tree" then
				trees += 1
				-- the crown: every leaf block (the trunk and its stubs aside)
				local lo = Vector3.new(math.huge, 0, math.huge)
				local hi = Vector3.new(-math.huge, 0, -math.huge)
				local crown = 0
				for _, part in tree:GetDescendants() do
					if part:IsA("BasePart") and part.Name ~= "Trunk" and not part.CanCollide then
						-- (branch stubs and roots are trunk-brown; leaves never are)
						local trunkish = part.Color.R > part.Color.G and part.Color.G > part.Color.B and part.Color.G < 0.35
						if not trunkish then
							local a, b = box(part)
							lo = Vector3.new(math.min(lo.X, a.X), 0, math.min(lo.Z, a.Z))
							hi = Vector3.new(math.max(hi.X, b.X), 0, math.max(hi.Z, b.Z))
							crown += 1
						end
					end
				end
				if crown > 0 then
					for _, site in Town.Sites do
						local dx = math.max(site.Min.X - hi.X, 0, lo.X - site.Max.X)
						local dz = math.max(site.Min.Y - hi.Z, 0, lo.Z - site.Max.Y)
						local gap = math.sqrt(dx * dx + dz * dz)
						T.truthy(gap >= 1, `{tree:GetFullName()} crown is {gap} studs from the town building {site.Id}`)
					end
					for _, piece in stalls do
						local gap = math.huge
						for _, x in { lo.X, (lo.X + hi.X) / 2, hi.X } do
							for _, z in { lo.Z, (lo.Z + hi.Z) / 2, hi.Z } do
								gap = math.min(gap, LobbyLayout.distanceTo(piece, Vector3.new(x, 0, z)))
							end
						end
						T.truthy(gap >= 1, `{tree:GetFullName()} crown is {gap} studs from the stall {piece.Id}`)
					end
				end
			end
		end
		T.truthy(trees >= 60, `the lobby has its trees ({trees})`)
	end)
end
