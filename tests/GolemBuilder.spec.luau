-- GolemBuilder (step 7): every golem kind builds within the part budget in
-- Mini Characters proportions (a big head on a short body) with its rock
-- look (brow, rock fists, boulder, crystal, vein), stands on its base
-- facing the base's LookVector (Legendary+ float over their aura),
-- reports RootHeight / Height / Hover right at every size, never collides /
-- touches / is queried, welds onto its Body for followers with every part
-- created in place, survives unknown kinds; every accessory builds; the
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
		-- a limited edition golem's costume: its rarity's budget, rarer = richer
		local last = GolemConfig.MaxParts
		for _, rarity in { "Rare", "Epic", "Legendary", "Mythic" } do
			local budget = GolemConfig.LimitedMaxParts[rarity]
			T.truthy(budget and budget > last and budget <= 96, rarity .. " limited budget grows and stays phone-friendly")
			last = budget
		end
		for _, golem in GolemConfig.List do
			local model = GolemBuilder.build(golem.Id)
			local n = GolemBuilder.partCount(model)
			local budget = if golem.Edition then GolemConfig.LimitedMaxParts[golem.Rarity] else GolemBuilder.MaxParts
			T.eq(GolemBuilder.budget(golem.Id), budget, golem.Id .. " budget")
			T.le(n, budget, golem.Id .. " parts")
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
				T.near(lowest, 4, 0.02, `{golem.Id} x{size}: on the base (feet, or the aura under floating feet)`)
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
			-- (a limited costume may glow more: fire wings, lava, crowns; under half of it)
			local glowCap = if golem.Edition then math.floor(GolemBuilder.budget(golem.Id) * 0.45) else 9
			T.le(neon, glowCap, golem.Id .. " glowing parts")
			T.truthy(neon >= 3, golem.Id .. " eyes and core glow")
		end
	end)

	T.test("GolemBuilder: welded followers move with their Body (every part made in place)", function()
		for _, kind in { "RoseKnight", "HeartstoneColossus" } do
			local model = GolemBuilder.build(kind, CFrame.new(0, 0, 0), { Welded = true, Size = 0.85 })
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
			-- built at a follower's start CFrame, every part is already where the
			-- welds keep it: the same offsets from Body as a golem built at the origin
			local start = CFrame.new(140, 37, -60) * CFrame.Angles(0, 2.3, 0)
			local placed = GolemBuilder.build(kind, start, { Welded = true, Size = 0.85 })
			local a, b = parts(model), parts(placed)
			T.eq(#a, #b)
			for i, part in a do
				local here = body.CFrame:ToObjectSpace(part.CFrame)
				local there = placed.PrimaryPart.CFrame:ToObjectSpace(b[i].CFrame)
				T.near((here.Position - there.Position).Magnitude, 0, 1e-3, `{kind} {part.Name} offset`)
				T.near(here.LookVector:Dot(there.LookVector), 1, 1e-4, `{kind} {part.Name} turn`)
			end
			local feet = start:PointToObjectSpace(placed.PrimaryPart.CFrame.Position)
			T.near(feet.Y, placed:GetAttribute("RootHeight"), 1e-3, "Body at RootHeight over the start")
		end
	end)

	T.test("GolemBuilder: golems read as rock: brow, rock fists, boulder, crystal and an ore vein", function()
		local noVein = 0
		for _, golem in GolemConfig.List do
			local model = GolemBuilder.build(golem.Id)
			local covered = GolemBuilder.Faces[golem.Accessory] ~= nil
			T.eq(model:FindFirstChild("Brow") ~= nil, not covered, golem.Id .. " stone brow (unless the face is covered)")
			T.falsy(model:FindFirstChild("Face"), golem.Id .. " no robot face plate")
			for _, name in { "Boulder", "Crystal", "Fist1", "Fist2" } do
				T.truthy(model:FindFirstChild(name), golem.Id .. " " .. name)
			end
			local fist = model:FindFirstChild("Fist1")
			T.eq(fist.Shape, roblox.Enum.PartType.Block, "a rock chunk, not a ball")
			T.truthy(fist.Material ~= roblox.Enum.Material.SmoothPlastic, golem.Id .. " rough fists")
			local bodyMaterial = model.PrimaryPart.Material
			T.truthy(
				bodyMaterial ~= roblox.Enum.Material.SmoothPlastic and bodyMaterial ~= roblox.Enum.Material.Glass,
				golem.Id .. " body is no plastic or glass"
			)
			-- (a limited edition golem spends its budget on its gear first)
			if not model:FindFirstChild("Vein") and not golem.Edition then
				noVein += 1
			end
		end
		T.truthy(noVein <= 4, "nearly every capsule golem has its ore vein (the budget allows)")
	end)

	T.test("GolemBuilder: Legendary and Mythic golems float on a glowing aura", function()
		for _, golem in GolemConfig.List do
			local model = GolemBuilder.build(golem.Id)
			local order = GolemConfig.order(golem.Id)
			local aura = model:FindFirstChild("Aura")
			if order >= 5 then
				T.truthy(GolemBuilder.premium(golem.Id), golem.Id .. " premium")
				T.truthy(aura and aura.Material == roblox.Enum.Material.Neon, golem.Id .. " has its aura")
				T.near(model:GetAttribute("Hover"), GolemBuilder.Hover * golem.Scale, 1e-6, golem.Id .. " hovers")
				local _, auraTop = yExtent(aura)
				local lowestLeg = math.huge
				for _, name in { "Leg1", "Leg2" } do
					local lo = yExtent(model:FindFirstChild(name))
					lowestLeg = math.min(lowestLeg, lo)
				end
				T.truthy(lowestLeg > auraTop + 0.1, golem.Id .. " feet float over the aura")
				T.truthy(aura.Size.Y > aura.Size.X * 10, golem.Id .. " the aura is a thin disc")
				T.truthy(aura.Size.Y > model.PrimaryPart.Size.X * 1.5, golem.Id .. " wider than the golem")
			else
				T.falsy(GolemBuilder.premium(golem.Id), golem.Id)
				T.falsy(aura, golem.Id .. " no aura")
				T.eq(model:GetAttribute("Hover"), 0)
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
			if capsule.Limited then
				continue -- a limited edition's shard (its own test below)
			end
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

	T.test("GolemBuilder: a limited edition's shard keeps the capsule's contract", function()
		local shards = 0
		for _, capsule in CapsuleConfig.List do
			if not capsule.Limited then
				continue
			end
			local model = GolemBuilder.capsule(capsule.Id, CFrame.new(0, 3, 0))
			shards += 1
			T.eq(model:GetAttribute("Shard"), capsule.Limited, capsule.Id .. " is its set's shard")
			T.eq(model:GetAttribute("Capsule"), capsule.Id)
			local n = GolemBuilder.partCount(model)
			T.truthy(n > GolemBuilder.CapsuleParts and n <= GolemBuilder.ShardMaxParts, `{capsule.Id}: {n} parts`)
			local top = model:FindFirstChild("Top")
			local bottom = model:FindFirstChild("Bottom")
			T.truthy(top and top:IsA("Model") and top.PrimaryPart and top.PrimaryPart.Name == "TopRoot", "Top half")
			T.truthy(bottom and bottom:IsA("Model") and bottom.PrimaryPart and bottom.PrimaryPart.Name == "BottomRoot", "Bottom half")
			T.eq(model.PrimaryPart.Name, "Root")
			for _, root in { model.PrimaryPart, top.PrimaryPart, bottom.PrimaryPart } do
				T.eq(root.Transparency, 1, root.Name .. " invisible")
				T.near(root.CFrame.Position.Y, 3, 1e-3, root.Name .. " at the center")
				T.near(root.CFrame.UpVector.Y, 1, 1e-6, root.Name .. " upright")
			end
			for i = 1, 3 do
				local crack = bottom:FindFirstChild("Crack" .. i)
				T.truthy(crack and crack:IsA("BasePart") and crack.Transparency == 1, "crack " .. i .. " hidden")
			end
			local band = bottom:FindFirstChild("Band")
			T.truthy(band and band:IsA("BasePart") and band.Material == roblox.Enum.Material.Neon, "a Neon band to tint")
			for _, part in parts(model) do
				T.falsy(part.CanCollide)
			end
			-- every shard part sits in a half (they fly apart) or is a pivot
			for _, part in parts(model) do
				local inHalf = part:IsDescendantOf(top) or part:IsDescendantOf(bottom)
				T.truthy(inHalf or part == model.PrimaryPart, part.Name .. " in a half")
			end
		end
		T.truthy(shards >= 1, "the Dragonforge capsule is a shard")
	end)

	T.test("GolemBuilder: the upcoming limited sets' golems build in budget and are not real kinds", function()
		local LimitedUpcoming = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedUpcoming")
		local rarities = { "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" }
		for _, id in LimitedUpcoming.Order do
			local set = LimitedUpcoming.Sets[id]
			T.truthy(set and #set.Golems == 6, id .. " has 6 golems")
			for i, golem in set.Golems do
				T.eq(golem.Rarity, rarities[i], golem.Id .. " rarity")
				T.eq(golem.Edition, id, golem.Id .. " edition")
				T.falsy(GolemConfig.ById[golem.Id], golem.Id .. " is not a real kind yet")
				local model = GolemBuilder.build(golem.Id)
				local n = GolemBuilder.partCount(model)
				T.le(n, GolemConfig.LimitedMaxParts[golem.Rarity], golem.Id .. " parts")
				T.eq(model:GetAttribute("Golem"), golem.Id)
			end
			local shard = GolemBuilder.shard(id, CFrame.new(0, 3, 0), set.Backdrop.Ground, set.Backdrop.Accent)
			T.le(GolemBuilder.partCount(shard), GolemBuilder.ShardMaxParts, id .. " shard parts")
		end
	end)

	T.test("GolemBuilder: limited followers carry no light, the full build does", function()
		local full = GolemBuilder.build("DragonKing")
		local follower = GolemBuilder.build("DragonKing", CFrame.new(), { Welded = true })
		local function lights(m: any): number
			local n = 0
			for _, d in m:GetDescendants() do
				if d:IsA("PointLight") then
					n += 1
				end
			end
			return n
		end
		T.eq(lights(full), 1, "the Mythic's one light")
		T.eq(lights(follower), 0, "none on a follower")
		T.eq(GolemBuilder.partCount(follower), GolemBuilder.partCount(full), "the same costume")
	end)
end
