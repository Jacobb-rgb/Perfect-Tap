-- Studio's 3D Importer turns every uploaded model half round about Y (owner's upload 2026-11-13;
-- MeshKit: the templates' ImportYaw): the clones turn back, so every builder shows the processed
-- model the same with the turn as without it. Stand-in templates play the upload here.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = roblox.CFrame
	local V3 = roblox.Vector3
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MeshKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.MeshKit")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")

	local function with(yaw: number?, fn: () -> ())
		Fakes(Loader, true, yaw)
		local ok, err = pcall(fn)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end

	local function same(a: any, b: any, label: string)
		T.truthy(
			(a.Position - b.Position).Magnitude < 1e-4 and a.LookVector:Dot(b.LookVector) > 0.9999 and a.UpVector:Dot(b.UpVector) > 0.9999,
			label
		)
	end

	T.test("MeshTurn: a turned upload's clone stands in the asked frame; place keeps the turn", function()
		with(180, function()
			local cf = CF.new(3, 4, 5) * CF.Angles(0, 0.7, 0)
			local p = MeshKit.part("Prop_Museum", V3.new(4, 2, 2), cf)
			T.truthy(p, "a clone")
			same(MeshKit.frame(p), cf, "its frame is the asked one")
			T.truthy(p.CFrame.LookVector:Dot(cf.LookVector) < -0.9999, "the part itself is turned half round")
			T.truthy((p.CFrame.Position - cf.Position).Magnitude < 1e-4, "in the same place")
			local cf2 = CF.new(-1, 2, 0) * CF.Angles(0, -1.2, 0)
			MeshKit.place(p, cf2)
			same(MeshKit.frame(p), cf2, "place moves the frame")
		end)
		with(nil, function()
			local cf = CF.new(3, 4, 5) * CF.Angles(0, 0.7, 0)
			local p = MeshKit.part("Prop_Museum", V3.new(4, 2, 2), cf)
			same(p.CFrame, cf, "no turn: the part stands in cf")
			same(MeshKit.frame(p), cf, "and so does its frame")
		end)
	end)

	T.test("MeshTurn: a rock's mesh, glints and cracks are the same with the turn as without", function()
		local function build(): (any, { any })
			local m = RockBuilder.build(2, "Big", { "Emberite", "Cobalt" }, CF.new(10, 0, -5), "turn-test")
			local rock1 = m:FindFirstChild("Rock1")
			T.truthy(rock1 and rock1:IsA("MeshPart"), "the mesh rock")
			local list = {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d ~= rock1 then
					table.insert(list, d.CFrame.Position)
				end
			end
			return MeshKit.frame(rock1), list
		end
		local frame0, glints0, frame1, glints1
		with(nil, function()
			frame0, glints0 = build()
		end)
		with(180, function()
			frame1, glints1 = build()
		end)
		same(frame1, frame0, "the rock's frame")
		T.eq(#glints1, #glints0, "as many glints")
		for i = 1, #glints0 do
			T.truthy((glints1[i] - glints0[i]).Magnitude < 1e-3, "glint " .. i .. " in the same place")
		end
	end)
end
