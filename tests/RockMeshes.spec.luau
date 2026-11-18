-- The owner's rock models (Meshy, 2026-11-13): with the upload, every floor rock is its mesh (Rock1)
-- plus a glint per ore; crack stages shrink it, crack its surface and break bits off. Stand-in
-- templates (tools/lune/lib/mesh_fakes) play the upload here.
return function(T, Loader)
	local CF = Loader.CFrame
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local MeshCatalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")

	local KINDS = { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" }
	local ORES = { "Coal", "Copper", "Tin", "Iron" }

	T.test("rock meshes: every floor and kind has a model, a tint and surface spots", function()
		for _, floor in MineFloors.List do
			for _, kind in KINDS do
				local name = "Rock_" .. floor.Id .. "_" .. kind
				T.truthy(MeshCatalog.Assets[name], name .. " in the catalog")
				local surface = MeshCatalog.Surface[name]
				T.truthy(surface, name .. " has a surface")
				T.le(4, #surface.Spots, name .. " spots")
				for _, spot in surface.Spots do
					T.le(math.abs(spot.P.X), 0.5, name .. " spot inside the box")
					T.le(math.abs(spot.P.Y), 0.5, name .. " spot inside the box")
					T.le(math.abs(spot.P.Z), 0.5, name .. " spot inside the box")
				end
			end
		end
	end)

	T.test("rock meshes: without the upload the part rocks are built", function()
		Fakes.unmount(Loader)
		local model = RockBuilder.build(1, "Small", { "Coal", "Copper", "Tin" }, CF.new(0, 0, 0), 7)
		T.falsy(model.PrimaryPart and model.PrimaryPart:IsA("MeshPart"), "part rock")
		T.truthy(model:FindFirstChild("Rock2"), "ring shards")
	end)

	T.test("rock meshes: a rock is its mesh plus one glint per ore", function()
		Fakes(Loader, true)
		for _, floor in MineFloors.List do
			for _, kind in KINDS do
				local ores = if kind == "Giant" then {} else table.move(ORES, 1, MineFloors.OreCount[kind], 1, {})
				local base = CF.new(10, 2, -30)
				local model = RockBuilder.build(floor.Index, kind, ores, base, kind .. floor.Id)
				local label = floor.Id .. " " .. kind
				local rock1 = model.PrimaryPart
				T.truthy(rock1 and rock1:IsA("MeshPart"), label .. ": Rock1 is the mesh")
				T.eq(rock1.Name, "Rock1", label)
				T.eq(rock1:GetAttribute("Asset"), "Rock_" .. floor.Id .. "_" .. kind, label .. " asset")
				T.truthy(rock1.CanCollide and rock1.CanQuery and rock1.Anchored, label .. ": solid, hit by the blaster ray")
				-- standing on the ground at the base
				T.near(rock1.CFrame.Position.Y - rock1.Size.Y / 2, 2, 0.01, label .. " foot on the ground")
				T.near(rock1.CFrame.Position.X, 10, 0.01, label .. " at the base")
				-- about the part rocks' size
				local longest = math.max(rock1.Size.X, rock1.Size.Y, rock1.Size.Z)
				-- (a stretched model: its longest side that much over)
				local stretch = RockBuilder.MeshStretch["Rock_" .. floor.Id .. "_" .. kind]
				local over = if stretch then math.max(stretch.X, stretch.Y, stretch.Z) else 1
				local want = RockBuilder.MeshSize[kind] * (RockBuilder.MeshFloorScale[floor.Id] or 1) * over
				T.le(want * 0.9, longest, label .. " size")
				T.le(longest, want * 1.1, label .. " size")
				local glints = 0
				for _, child in model:GetChildren() do
					if child.Name == "Glint" then
						glints += 1
						T.falsy(child.CanCollide or child.CanQuery, label .. " glint is a look")
						local d = (child.CFrame.Position - rock1.CFrame.Position).Magnitude
						T.le(d, longest * 0.75, label .. " glint on the rock")
					end
				end
				T.eq(glints, #ores, label .. " one glint per ore")
				T.eq(model:GetAttribute("Kind"), kind, label)
				T.eq(model:GetAttribute("Floor"), floor.Index, label)
				T.eq(model:GetAttribute("OreCount"), #ores, label)
				T.eq(model:GetAttribute("Stage"), 0, label)
				T.eq(model:GetAttribute("Artifact"), if kind == "Artifact" then true else nil, label)
				T.le(#model:GetDescendants(), RockBuilder.Budget[kind], label .. " parts")
			end
		end
		Fakes.unmount(Loader)
	end)

	T.test("rock meshes: floor 5's Thunder Shard crystals are thicker (owner 2026-11-17)", function()
		Fakes(Loader, true)
		local ok, err = pcall(function()
			local name = "Rock_StormglassRift_Crystal"
			local stretch = RockBuilder.MeshStretch[name]
			T.truthy(stretch ~= nil and stretch.X > 1.2 and stretch.Z > 1.2 and stretch.Y == 1, "wider and deeper, as tall")
			local floor = MineFloors.ById.StormglassRift
			local model = RockBuilder.build(floor.Index, "Crystal", { "Sunstone", "Moonstone", "StormGem" }, CF.new(0, 0, 0), 5)
			local rock1 = model.PrimaryPart
			T.eq(rock1:GetAttribute("Asset"), name, "his crystal model")
			local own = MeshCatalog.Assets[name].Box
			local s = rock1.Size
			T.near((s.X / s.Y) / (own.X / own.Y), stretch.X, 1e-3, "thicker for its height")
			T.near((s.Z / s.Y) / (own.Z / own.Y), stretch.Z, 1e-3, "both ways")
			-- as tall as before: the longest side of its own box at the floor's rock size
			local longest = s.Y * math.max(own.X, own.Y, own.Z) / own.Y
			local want = RockBuilder.MeshSize.Crystal * RockBuilder.MeshFloorScale.StormglassRift
			T.le(want * 0.9, longest, "its height as before")
			T.le(longest, want * 1.1, "its height as before")
			-- its glints stand on the spots' true normals (stretched: the normal by the inverse stretch;
			-- integrator 2026-11-18: 5.5-6.4 degrees off on its sloped spots without)
			local V3 = (require("@lune/roblox") :: any).Vector3
			local surface = MeshCatalog.Surface[name]
			local frame = rock1.CFrame * rock1.PivotOffset
			local i, worst = 0, 0
			for _, g in model:GetChildren() do
				if g.Name == "Glint" then
					i += 1
					local spot = surface.Spots[(i - 1) % #surface.Spots + 1]
					local p = frame:PointToWorldSpace(V3.new(spot.P.X * s.X, spot.P.Y * s.Y, spot.P.Z * s.Z))
					local true_ = V3.new(spot.N.X * own.X / s.X, spot.N.Y * own.Y / s.Y, spot.N.Z * own.Z / s.Z).Unit
					local n = frame:VectorToWorldSpace(true_).Unit
					local want = p + n * (g.Size.X * 0.2)
					T.near((g.CFrame.Position - want).Magnitude, 0, 1e-3, "a glint on its spot's true normal")
					worst = math.max(worst, math.deg(math.acos(math.clamp(true_:Dot(spot.N.Unit), -1, 1))))
				end
			end
			T.eq(i, 3, "a glint per ore")
			T.le(3, worst, "(a spot whose normal the stretch turns: the check above means something)")
			-- a crack stage keeps its shape
			RockBuilder.applyStage(model, 1, 5)
			T.near((rock1.Size.X / rock1.Size.Y), s.X / s.Y, 1e-3, "a stage keeps its shape")
			-- the other floors' crystals keep their shapes
			for _, other in MineFloors.List do
				local o = "Rock_" .. other.Id .. "_Crystal"
				if o ~= name then
					T.eq(RockBuilder.MeshStretch[o], nil, other.Id .. " crystal as it was")
				end
			end
		end)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end)

	T.test("rock meshes: stages crack and break bits off, nothing already there moves", function()
		Fakes(Loader, true)
		local model = RockBuilder.build(2, "Big", ORES, CF.new(0, 5, 0), 42)
		local rock1 = model.PrimaryPart
		local size0 = rock1.Size
		local foot0 = rock1.CFrame.Position.Y - rock1.Size.Y / 2
		local glint = model:FindFirstChild("Glint")
		local glintHeight0 = glint.CFrame.Position.Y - foot0
		for stage = 1, 3 do
			local broken = RockBuilder.applyStage(model, stage, 42)
			T.le(2, #broken, "stage " .. stage .. " bits")
			for _, bit in broken do
				T.eq(bit.Parent, model, "a bit is handed back inside the rock")
				T.falsy(bit.CanCollide, "a bit does not block")
			end
			T.eq(model:GetAttribute("Stage"), stage, "stage attribute")
		end
		-- (integrator review 2026-11-17: the clients' tremble holds each part's frame, a moved part
		-- snapped back and the rock floated) the body and its glints stay exactly where they were
		T.eq(model.PrimaryPart, rock1, "the same body")
		T.near((rock1.Size - size0).Magnitude, 0, 1e-6, "its size unchanged")
		T.near(rock1.CFrame.Position.Y - rock1.Size.Y / 2, foot0, 1e-6, "its foot on the ground")
		T.near(glint.CFrame.Position.Y - foot0, glintHeight0, 1e-6, "the glints where they were")
		local cracks = 0
		for _, child in model:GetChildren() do
			if child.Name == "Crack" then
				cracks += 1
			end
		end
		T.le(9 * 3, cracks, "cracks on the surface") -- 2 + 3 + 4 cracks of 3 parts each
		Fakes.unmount(Loader)
	end)
end
