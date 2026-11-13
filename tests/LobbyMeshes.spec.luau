--[[
	The owner's Meshy models in the lobby (docs/plans/MESHY_MODELS_PLAN.md, package B,
	src/server/World/MeshNature.luau). With stand-in templates mounted (tools/lune/lib/mesh_fakes)
	every tree builder makes the owner's tree (one mesh, an invisible trunk where the old trunk
	collided), the oval ponds without a bridge are his lily pond (with a thin invisible Water part),
	the moss rocks and voxel cliffs his mossy cliff, and the contracts the game reads still hold:
	tree models keep their names and stay few-part and anchored (WeatherSway), the petals hang on
	the mesh (Trees.crownPart), the ponds keep their names and a part for the ambience, no random
	stream moves (the town keeps its layout) and the lobby keeps its budgets with far fewer parts.
	Then the lobby specs whose placement, overlap and budget checks the meshes could break run
	again with the meshes on. Without templates the lobby specs cover the old part looks.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WeatherConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WeatherConfig")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local MeshNature = Loader.requirePath("ServerScriptService.Server.World.MeshNature")
	local Props = Loader.requirePath("ServerScriptService.Server.World.Props")
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Kit")
	local Meadow = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Meadow")

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Trees.crownPart's pick: the first non-colliding, shadow-casting child part.
	local function crownPart(tree: any): any
		for _, child in tree:GetChildren() do
			if child:IsA("BasePart") and not child.CanCollide and child.CastShadow then
				return child
			end
		end
		return nil
	end

	local function world(): any
		return WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
	end

	-- Builds the same thing twice from the same seed, without and with the templates: the old
	-- look, the mesh look and the next draw of each random stream.
	local function twice(seed: string, build: (parent: any, rng: any) -> any): (any, any, number, number)
		Fakes.unmount(Loader)
		local rngA = Rng.new(seed)
		local plain = build(roblox.Instance.new("Model"), rngA)
		Fakes(Loader, true)
		local rngB = Rng.new(seed)
		local mesh = build(roblox.Instance.new("Model"), rngB)
		return plain, mesh, rngA:nextU32(), rngB:nextU32()
	end

	Fakes(Loader, true)

	T.test("lobby meshes: every tree builder makes the owner's tree on the old tree's foot", function()
		local origin = CFrame.new(10, 2, -6)
		local cases = {
			{
				"Style.tree Green",
				"Prop_TreeGreen",
				false,
				function(p, rng)
					return Style.tree(p, origin, "Green", rng, 1)
				end,
			},
			{
				"Style.tree Red",
				"Prop_TreeOrange",
				true,
				function(p, rng)
					return Style.tree(p, origin, "Red", rng, 1.2)
				end,
			},
			{
				"Style.tree Yellow",
				"Prop_TreeYellow",
				false,
				function(p, rng)
					return Style.tree(p, origin, "Yellow", rng, 0.9)
				end,
			},
			{
				"Kit.bigTree Cherry",
				"Prop_TreeOrange",
				true,
				function(p, rng)
					return Kit.bigTree(p, origin, "Cherry", rng, 1.4, 1)
				end,
			},
			{
				"Kit.beltTree Green",
				"Prop_TreeGreen",
				false,
				function(p, rng)
					return Kit.beltTree(p, origin, "Green", rng, 1.1, nil, 2.5)
				end,
			},
			{
				"Kit.beltTree leaning Orange",
				"Prop_TreeOrange",
				false,
				function(p, rng)
					return Kit.beltTree(p, origin, "Orange", rng, 1.1, Vector3.new(-1, 0, 0), 2.5)
				end,
			},
			{
				"Kit.leanTree Yellow",
				"Prop_TreeYellow",
				false,
				function(p, rng)
					return Kit.leanTree(p, origin, "Yellow", rng, 1)
				end,
			},
			{
				"Meadow.jungleTree",
				"Prop_TreeGreen",
				false,
				function(p, rng)
					return Meadow.jungleTree(p, origin.Position, 14, 4.5, rng, nil)
				end,
			},
			{
				"Meadow.jungleTree autumn",
				"Prop_TreeYellow",
				false,
				function(p, rng)
					return Meadow.jungleTree(p, origin.Position, 14, 4.5, rng, Style.TreeKinds.Yellow)
				end,
			},
			{
				"Props.tree",
				nil,
				false,
				function(p, rng)
					return Props.tree(p, origin, rng, "Green")
				end,
			},
		}
		for _, case in cases do
			local label, asset, tinted, build = case[1], case[2], case[3], case[4]
			local plain, mesh, drawA, drawB = twice(label, build)
			T.eq(drawA, drawB, label .. ": the mesh draws nothing from the random stream")
			T.eq(mesh.Name, plain.Name, label .. ": keeps its model name")
			local leaves = mesh:FindFirstChild("Leaves")
			T.truthy(leaves and leaves:IsA("MeshPart"), label .. ": one mesh")
			T.truthy(#parts(mesh) <= 2 and #parts(mesh) <= WeatherConfig.TreeSway.MaxParts, label .. ": two parts at most")
			if asset then
				T.eq(leaves:GetAttribute("Asset"), asset, label .. ": the right colour")
			end
			T.eq(leaves:GetAttribute("Tint") ~= nil, tinted, label .. ": tinted red or pink only")
			T.truthy(leaves.Anchored and not leaves.CanCollide and not leaves.CanQuery and not leaves.CanTouch, label .. ": a look only")
			T.eq(crownPart(mesh), leaves, label .. ": the petals hang on the mesh")
			-- it stands where the old trunk stood, never taller than the old tree
			local trunk = plain:FindFirstChild("Trunk") or plain:FindFirstChildWhichIsA("BasePart")
			if plain.Name == "JungleTree" then
				trunk = plain:GetChildren()[2]
			end
			local foot = trunk.CFrame.Position - Vector3.new(0, trunk.Size.Y / 2, 0)
			local p = leaves.CFrame.Position
			T.near(p.X, foot.X, 0.01, label .. ": on the trunk (x)")
			T.near(p.Z, foot.Z, 0.01, label .. ": on the trunk (z)")
			T.near(p.Y - leaves.Size.Y / 2, foot.Y, leaves.Size.Y * 0.02, label .. ": on the ground")
			local _, hi = MeshNature.bounds(plain)
			T.truthy(p.Y + leaves.Size.Y / 2 <= hi.Y + 0.01, label .. ": not taller than the old tree")
			-- the invisible trunk where the old one collided
			local collider = mesh:FindFirstChild("Trunk")
			T.truthy(collider and collider.CanCollide and collider.Transparency == 1 and collider.Anchored, label .. ": a solid trunk")
			T.truthy(MeshNature.isCollider(collider) and not collider.CastShadow, label .. ": marked, no shadow")
			T.truthy(collider.Size.X <= math.min(trunk.Size.X, trunk.Size.Z) + 1e-6, label .. ": never wider than the old trunk")
			T.eq(mesh:GetChildren()[1], collider, label .. ": the trunk comes first (FindFirstChildWhichIsA)")
		end
		-- a leaning belt tree keeps inside its old crown's box (off the bases)
		local plain, mesh = twice("lean", function(p, rng)
			return Kit.beltTree(p, CFrame.new(75.5, 0, 20), "Green", rng, 1.15, Vector3.new(-1, 0, 0), 2.5)
		end)
		local lo, hi = MeshNature.bounds(plain)
		local mlo, mhi = MeshNature.bounds(mesh)
		T.truthy(
			mlo.X >= lo.X - 0.01 and mhi.X <= hi.X + 0.01 and mlo.Z >= lo.Z - 0.01 and mhi.Z <= hi.Z + 0.01,
			"the leaning crown stays in its box"
		)
	end)

	T.test("lobby meshes: the lily pond fills an oval pond's footprint, its water marked", function()
		for _, case in { { 12, 9, nil }, { 10, 12, Vector3.new(1, 0, 0) }, { 13, 7, Vector3.new(0, 0, -1) } } do
			local sx, sz, front = case[1], case[2], case[3]
			local center = Vector3.new(-20, 0, 30)
			local plain, mesh, drawA, drawB = twice(`pond {sx}x{sz}`, function(p, rng)
				local pond = Style.pond(p, center, sx, sz, rng, { LilyPads = 3, Koi = 2 })
				MeshNature.pond(pond, center, sx, sz, { Front = front })
				return pond
			end)
			local label = `pond {sx} x {sz}`
			T.eq(drawA, drawB, label .. ": the mesh draws nothing")
			T.eq(mesh.Name, "Pond", label .. ": still a Pond")
			T.truthy(#parts(plain) > 2, label .. ": the old pond is parts")
			T.eq(#parts(mesh), 2, label .. ": the mesh and its water")
			local m = mesh:FindFirstChild("PondMesh")
			T.truthy(m and m:IsA("MeshPart") and m:GetAttribute("Asset") == "Prop_GardenPond", label .. ": the owner's pond")
			T.truthy(not m.CanCollide and not m.CanQuery and m.Anchored, label .. ": a look you wade through")
			local lo, hi = MeshNature.bounds(mesh)
			T.truthy(hi.X - lo.X <= sx + 0.01 and hi.Z - lo.Z <= sz + 0.01, label .. ": inside the footprint")
			T.truthy(hi.X - lo.X >= sx - 0.01 or hi.Z - lo.Z >= sz - 0.01, label .. ": scaled evenly to fill it")
			T.eq(hi.X - lo.X > hi.Z - lo.Z, sx > sz, label .. ": its long side along the footprint's")
			T.near(m.CFrame.Position.Y - m.Size.Y / 2, center.Y, m.Size.Y * 0.02, label .. ": on the ground")
			local water = mesh:FindFirstChild("Water")
			T.truthy(
				water and water.Transparency == 1 and not water.CanCollide and not water.CanQuery,
				label .. ": an invisible water mark"
			)
			T.truthy(
				water.CFrame.Position.Y > center.Y and water.CFrame.Position.Y < center.Y + m.Size.Y * 0.15,
				label .. ": at the surface"
			)
			if front then
				-- the mesh's low front rim (its +Z side) faces `front`
				T.truthy(m.CFrame.ZVector:Dot(front) > 0.99, label .. ": its low rim toward the front")
			end
		end
	end)

	T.test("lobby meshes: a voxel cliff is the owner's mossy cliff and stays solid", function()
		local base = CFrame.new(5, 0, 8) * CFrame.Angles(0, math.pi / 2, 0)
		local size = Vector3.new(30, 14, 9)
		local plain, mesh, drawA, drawB = twice("cliff", function(p, rng)
			return Style.voxelCliff(p, base, size, rng)
		end)
		T.eq(drawA, drawB, "the mesh draws nothing")
		T.eq(mesh.Name, plain.Name, "still a Cliff")
		local collider = mesh:FindFirstChild("CliffCollider")
		T.truthy(collider and collider.CanCollide and collider.CanQuery and collider.Transparency == 1, "one solid invisible box")
		T.truthy((collider.Size - size).Magnitude < 1e-4, "as big as the cliff")
		local pieces = 0
		for _, d in mesh:GetChildren() do
			if d:IsA("MeshPart") then
				pieces += 1
				T.eq(d:GetAttribute("Asset"), "Prop_MossyCliff", "a mossy cliff piece")
				T.falsy(d.CanCollide, "the pieces are looks")
				-- inside the box (its frame), the vines (+Z of the mesh) toward the front (LookVector)
				local q = base:PointToObjectSpace(d.CFrame.Position)
				T.truthy(math.abs(q.X) + d.Size.X / 2 <= size.X / 2 + 0.01, "inside the cliff's width")
				T.truthy(q.Y + d.Size.Y / 2 <= size.Y + 0.1, "not over its top")
				T.truthy(d.CFrame.ZVector:Dot(base.LookVector) > 0.99, "its vines to the front")
			end
		end
		T.truthy(pieces >= 2 and pieces < #parts(plain), `a few pieces ({pieces})`)
	end)

	-- the whole map, without and with the templates
	Fakes.unmount(Loader)
	local plainMap = world()
	Fakes(Loader, true)
	local map = world()
	local lobby = map.Emberfall.Lobby

	T.test("lobby meshes: the town's trees are the owner's trees, sway-safe and on their old spots", function()
		local feet: { [string]: boolean } = {}
		for _, d in plainMap.Emberfall.Lobby:GetDescendants() do
			if d:IsA("Model") and (d.Name == "Tree" or d.Name == "JungleTree") then
				local trunk = d:FindFirstChild("Trunk")
					or (if d.Name == "JungleTree" then d:GetChildren()[2] else d:FindFirstChildWhichIsA("BasePart"))
				if trunk then
					feet[string.format("%.1f,%.1f", trunk.CFrame.Position.X, trunk.CFrame.Position.Z)] = true
				end
			end
		end
		local trees, onSpot, colliders = 0, 0, 0
		for _, d in lobby:GetDescendants() do
			-- (the Vault's giant jungle trees and the horizon isles' block trees keep their look)
			if d:IsA("Model") and (d.Name == "Tree" or d.Name == "JungleTree") and not d:FindFirstAncestor("Horizon") then
				trees += 1
				local label = d:GetFullName()
				local leaves = d:FindFirstChild("Leaves")
				T.truthy(leaves and leaves:IsA("MeshPart"), label .. " is the owner's tree")
				local list = parts(d)
				T.truthy(#list <= WeatherConfig.TreeSway.MaxParts, label .. " sways (few parts)")
				for _, part in list do
					T.truthy(part.Anchored, part:GetFullName() .. " is anchored")
					if part.CanCollide then
						T.truthy(part.Name == "Trunk" and MeshNature.isCollider(part), part:GetFullName() .. " only the trunk collides")
						colliders += 1
					end
				end
				if leaves and leaves.CastShadow then
					T.eq(crownPart(d), leaves, label .. " hangs its petals on the mesh")
				end
				if leaves then
					local p = leaves.CFrame.Position
					if feet[string.format("%.1f,%.1f", p.X, p.Z)] then
						onSpot += 1
					end
				end
			end
		end
		T.truthy(trees >= 150, `the lobby has its trees ({trees})`)
		T.truthy(onSpot >= trees * 0.95, `the trees stand on the old trees' spots ({onSpot} of {trees})`)
		T.truthy(colliders >= 80, `solid trunks where the old ones were ({colliders})`)
		-- the walk-through ones (the meadow, the floating islands) have none
		for _, root in { lobby.Flora:FindFirstChild("Meadow"), lobby:FindFirstChild("Sky") } do
			for _, part in parts(root) do
				T.falsy(MeshNature.isCollider(part) and not part:FindFirstAncestor("SkyHaven"), part:GetFullName() .. " needs no collider")
			end
		end
	end)

	T.test("lobby meshes: the oval ponds are the owner's lily pond and keep their ambience", function()
		local meshPonds, partPonds = 0, 0
		for _, d in lobby:GetDescendants() do
			if d:IsA("Model") and (d.Name == "Pond" or d.Name == "StreamPond") then
				local water = d:FindFirstChild("Water")
				T.truthy(water and water:IsA("BasePart"), d:GetFullName() .. " has its water")
				if d:FindFirstChild("PondMesh") then
					meshPonds += 1
					T.eq(#parts(d), 2, d:GetFullName() .. " is the mesh and its water mark")
				else
					partPonds += 1
				end
			end
		end
		-- the lily pond, the stream's, the garden's side ponds and the meadow's; the koi pond and
		-- the garden's pond (bridges over them) and the cliff's splash pool keep their parts
		T.truthy(meshPonds >= 7, `the owner's lily ponds ({meshPonds})`)
		T.eq(partPonds, 3, "the long ponds under bridges and the splash pool stay")
		T.truthy(lobby.Flora.Water.LilyPond.Pond:FindFirstChild("PondMesh"), "the lily pond")
		T.truthy(lobby.Flora.Stream.StreamPond:FindFirstChild("PondMesh"), "the stream's pond")
		T.falsy(lobby.Flora.Water.KoiPond.Pond:FindFirstChild("PondMesh"), "the koi pond under the bridge")
		-- the ambience (built last by WorldBuilder) still hangs its pond spots on the ponds
		local ponds = 0
		for _, a in map:GetDescendants() do
			if a:IsA("Attachment") and a.Name == "AmbiencePond" then
				ponds += 1
				local pond = a.Parent:FindFirstAncestorWhichIsA("Model")
				T.truthy(pond and (pond.Name == "Pond" or pond.Name == "StreamPond"), "a pond spot rides on a pond")
			end
		end
		T.truthy(ponds >= 1, `pond sound spots ({ponds})`)
	end)

	T.test("lobby meshes: the moss rocks are the owner's mossy cliff, still pure decoration", function()
		local rocks = 0
		for _, d in lobby:GetDescendants() do
			if d:IsA("Model") and d.Name == "MossRock" then
				rocks += 1
				local list = parts(d)
				T.eq(#list, 1, d:GetFullName() .. " is one mesh")
				local m = list[1]
				T.eq(m:GetAttribute("Asset"), "Prop_MossyCliff", "the owner's mossy cliff")
				T.falsy(m.CanCollide or m.CastShadow or m.CanTouch or m.CanQuery, m:GetFullName() .. " is pure decoration")
			end
		end
		T.truthy(rocks >= 1, `moss rocks ({rocks})`)
	end)

	T.test("lobby meshes: the lobby keeps its budgets with far fewer parts", function()
		local function count(root: any): (number, number)
			local all, inLobby = 0, 0
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					all += 1
					if LobbyLayout.inArea(d.CFrame.Position) then
						inLobby += 1
					end
				end
			end
			return all, inLobby
		end
		local plainAll, plainLobby = count(plainMap)
		local all, inLobby = count(map)
		local floraAll, floraLobby = count(lobby.Flora)
		local b = LobbyLayout.Budget
		T.truthy(plainAll - all >= 1500, `the map saves parts ({plainAll} -> {all})`)
		T.truthy(plainLobby - inLobby >= 800, `the lobby area saves parts ({plainLobby} -> {inLobby})`)
		T.le(all, b.MapParts, "map parts")
		T.le(inLobby, b.LobbyParts, "lobby parts")
		T.le(floraAll, b.Packages.Flora.Parts, "Flora parts")
		T.le(floraLobby, b.Packages.Flora.LobbyParts, "Flora parts in the lobby area")
	end)

	-- the lobby specs that place and clear things round the trees and ponds (roads, plots, stalls,
	-- signs, aprons, sight lines, the meadow's lawn and fences, the street lamps), again with the
	-- meshes on (the budgets and the pond sound spots are checked above)
	local function again(prefix: string): any
		return setmetatable({
			test = function(name: string, fn: () -> ())
				T.test(prefix .. name, fn)
			end,
		}, { __index = T })
	end
	for _, name in { "LobbyFlora", "LobbyFloraClearance", "LobbyOverlap", "Meadow", "LobbyPlaza" } do
		local spec = require(`./{name}.spec`) :: any
		spec(again("meshes on: "), Loader)
	end

	Fakes.unmount(Loader)
end
