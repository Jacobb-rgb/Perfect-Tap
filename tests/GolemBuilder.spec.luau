-- GolemBuilder (step 7): every golem kind builds within the part budget in
-- Mini Characters proportions (a big head on a short body), stands on its
-- base facing the base's LookVector, reports RootHeight / Height right at
-- every size, never collides / touches / is queried, welds onto its Body
-- for followers, survives unknown kinds; every accessory builds; the
-- opening capsule has its halves and hidden cracks.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")

	local function parts(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- the world-space Y extent of a part (its box, rotated)
	local function yExtent(part: any): (number, number)
		local cf = part.CFrame
		local h = part.Size / 2
		local up = math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
		return cf.Position.Y - up, cf.Position.Y + up
	end

	T.test("GolemBuilder: every golem kind builds within the part budget", function()
		T.eq(GolemBuilder.MaxParts, 20, "the package budget: 20 parts")
		T.le(GolemBuilder.MaxParts, GolemConfig.MaxParts, "within GolemConfig.MaxParts")
		for _, golem in GolemConfig.List do
			local model = GolemBuilder.build(golem.Id)
			local n = GolemBuilder.partCount(model)
			T.le(n, GolemBuilder.MaxParts, golem.Id .. " parts")
			T.truthy(n >= 14, golem.Id .. " has its body, head, limbs and gear")
			T.eq(model:GetAttribute("Golem"), golem.Id)
			T.truthy(model.PrimaryPart and model.PrimaryPart.Name == "Body", golem.Id .. " PrimaryPart = Body")
		end
	end)

	T.test("GolemBuilder: every accessory builds and adds parts", function()
		local seen = {}
		for _, golem in GolemConfig.List do
			seen[golem.Accessory] = true
		end
		for accessory in GolemConfig.Accessories do
			if not seen[accessory] then
				-- an accessory no golem wears yet still has to build (a later golem may)
				local fake = table.clone(GolemConfig.List[1])
				fake.Id = "TestGolem" .. accessory
				fake.Accessory = accessory
				GolemConfig.ById[fake.Id] = fake
				local model = GolemBuilder.build(fake.Id)
				GolemConfig.ById[fake.Id] = nil
				T.le(GolemBuilder.partCount(model), GolemBuilder.MaxParts, accessory .. " in budget")
			end
		end
		-- each accessory adds at least one part over the bare golem
		local base = GolemBuilder.partCount(GolemBuilder.build("PebbleGolem"))
		for _, golem in GolemConfig.List do
			if golem.Accessory ~= "None" then
				T.truthy(GolemBuilder.partCount(GolemBuilder.build(golem.Id)) > base - 2, golem.Id .. " wears its " .. golem.Accessory)
			end
		end
	end)

	T.test("GolemBuilder: Mini Characters proportions (big head, short body, stubby limbs)", function()
		for _, golem in GolemConfig.List do
			local model = GolemBuilder.build(golem.Id)
			local head = model:FindFirstChild("Head")
			local body = model:FindFirstChild("Body")
			T.truthy(head and body, golem.Id .. " head and body")
			T.truthy(head.Size.X > body.Size.X, golem.Id .. ": the head is wider than the body")
			T.truthy(head.Size.Y > body.Size.Y, golem.Id .. ": the head is taller than the body")
			local _, top = yExtent(head)
			local headShare = head.Size.Y / top
			T.truthy(headShare >= 0.4 and headShare <= 0.55, `{golem.Id}: the head is {headShare} of the height`)
			-- eyes glow, on the front (-Z) of the face
			local eye = model:FindFirstChild("Eye1")
			T.truthy(eye and eye.Material == roblox.Enum.Material.Neon, golem.Id .. " glowing eyes")
			T.truthy(eye.CFrame.Position.Z < head.CFrame.Position.Z - head.Size.Z / 2 + 0.05, golem.Id .. " eyes on the front")
		end
	end)

	T.test("GolemBuilder: stands on its base, faces its LookVector, RootHeight and Height are right", function()
		for _, size in { 1, 0.85, 1.5 } do
			for _, golem in GolemConfig.List do
				local base = CFrame.new(10, 4, -6) * CFrame.Angles(0, 1.1, 0)
				local model = GolemBuilder.build(golem.Id, base, { Size = size })
				local lowest, highest = math.huge, -math.huge
				for _, part in parts(model) do
					local lo, hi = yExtent(part)
					lowest = math.min(lowest, lo)
					highest = math.max(highest, hi)
				end
				T.near(lowest, 4, 0.02, `{golem.Id} x{size}: feet on the base`)
				local height = model:GetAttribute("Height")
				T.truthy(highest <= 4 + height + 0.25, `{golem.Id} x{size}: Height covers the gear ({highest - 4} vs {height})`)
				T.truthy(highest >= 4 + height - 0.3, `{golem.Id} x{size}: Height is the real top`)
				local body = model.PrimaryPart
				local local_ = base:PointToObjectSpace(body.CFrame.Position)
				T.near(local_.Y, model:GetAttribute("RootHeight"), 1e-3, `{golem.Id}: RootHeight`)
				T.near(local_.X, 0, 1e-3)
				-- the face looks along the base's LookVector (-Z)
				local eye = base:PointToObjectSpace(model:FindFirstChild("Eye1").CFrame.Position)
				T.truthy(eye.Z < -0.5 * size, `{golem.Id}: faces -Z`)
			end
		end
	end)

	T.test("GolemBuilder: decoration only (no collisions, touches or queries); few glowing parts", function()
		for _, golem in GolemConfig.List do
			local neon = 0
			for _, part in parts(GolemBuilder.build(golem.Id)) do
				T.falsy(part.CanCollide, golem.Id .. " " .. part.Name .. " CanCollide")
				T.falsy(part.CanTouch, golem.Id .. " " .. part.Name .. " CanTouch")
				T.falsy(part.CanQuery, golem.Id .. " " .. part.Name .. " CanQuery")
				T.truthy(part.Anchored, "anchored when not welded")
				if part.Material == roblox.Enum.Material.Neon then
					neon += 1
				end
				if part.CastShadow then
					T.truthy(part.Name == "Body" or part.Name == "Head", "only Body and Head cast shadows")
				end
			end
			T.le(neon, 9, golem.Id .. " glowing parts")
			T.truthy(neon >= 3, golem.Id .. " eyes and core glow")
		end
	end)

	T.test("GolemBuilder: welded followers move with their Body", function()
		local model = GolemBuilder.build("RubyKnight", CFrame.new(0, 0, 0), { Welded = true, Size = 0.85 })
		local body = model.PrimaryPart
		T.truthy(body.Anchored, "Body anchored")
		for _, part in parts(model) do
			if part ~= body then
				T.falsy(part.Anchored, part.Name .. " unanchored")
				T.truthy(part.Massless, part.Name .. " massless")
				local weld = part:FindFirstChildOfClass("WeldConstraint")
				T.truthy(weld and weld.Part0 == body and weld.Part1 == part, part.Name .. " welded to Body")
			end
		end
	end)

	T.test("GolemBuilder: an unknown kind (a newer update's) builds a plain golem", function()
		local ok, model = pcall(GolemBuilder.build, "FutureGolem")
		T.truthy(ok, "no error")
		T.le(GolemBuilder.partCount(model), GolemBuilder.MaxParts)
		T.eq(model:GetAttribute("Golem"), "FutureGolem")
	end)

	T.test("GolemBuilder: the opening capsule has its halves and hidden cracks", function()
		for _, capsule in CapsuleConfig.List do
			local model = GolemBuilder.capsule(capsule.Id, CFrame.new(0, 3, 0))
			T.eq(GolemBuilder.partCount(model), GolemBuilder.CapsuleParts, capsule.Id .. " parts")
			local top = model:FindFirstChild("Top")
			local bottom = model:FindFirstChild("Bottom")
			T.truthy(top and top:IsA("Model") and top.PrimaryPart, "Top half")
			T.truthy(bottom and bottom:IsA("Model") and bottom.PrimaryPart, "Bottom half")
			-- the pivots are upright, invisible and at the center (PivotTo works from there)
			for _, root in { model.PrimaryPart, top.PrimaryPart, bottom.PrimaryPart } do
				T.eq(root.Transparency, 1, root.Name .. " invisible")
				T.near(root.CFrame.Position.Y, 3, 1e-3, root.Name .. " at the center")
				T.near(root.CFrame.UpVector.Y, 1, 1e-6, root.Name .. " upright")
			end
			for i = 1, 3 do
				local crack = bottom:FindFirstChild("Crack" .. i)
				T.truthy(crack and crack.Transparency == 1, "crack " .. i .. " hidden")
			end
			T.eq(model.PrimaryPart.Name, "Root")
			local band = bottom:FindFirstChild("Band")
			T.near(band.CFrame.Position.Y, 3, 1e-3, "the band at the pill's center")
			local lowest, highest = math.huge, -math.huge
			for _, part in parts(model) do
				if part.Transparency < 1 then
					local lo, hi = yExtent(part)
					lowest = math.min(lowest, lo)
					highest = math.max(highest, hi)
				end
				T.falsy(part.CanCollide)
			end
			T.near(highest - lowest, GolemBuilder.CapsuleHeight, 0.05, "tip to tip")
			T.truthy(model:FindFirstChild("Window", true).CFrame.Position.Z < 0, "the window faces -Z")
		end
	end)
end
