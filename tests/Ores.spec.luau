-- WP-Ores: 30 unique ores (clean, display, ingot, crushed), Dirty Ore that hides the rarity,
-- and rocks that keep their content secret. Budgets come from the ore-design skill.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")

	local BUDGET = ItemBuilder.Budget
	local NEON = roblox.Enum.Material.Neon

	local function partsOf(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function countClass(model, className)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	local function lowestPoint(model)
		local lowest = math.huge
		for _, part in partsOf(model) do
			if part.Transparency < 1 then
				local _, _, _, _, _, _, r10, r11, r12 = part.CFrame:GetComponents()
				local h = part.Size / 2
				local halfY = math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z
				lowest = math.min(lowest, part.CFrame.Position.Y - halfY)
			end
		end
		return lowest
	end

	local function colorKey(c)
		return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end

	local function orderOf(ore)
		return Rarity.get(ore.Rarity).Order
	end

	T.test("ores: every kind builds for every ore within its part budget", function()
		for _, ore in OreData.List do
			local cf = CF.new(0, 5, 0)
			local raw = ItemBuilder.build({ Kind = "Raw", OreId = ore.Id }, cf, 3)
			T.le(#partsOf(raw), BUDGET.Raw, ore.Id .. " raw parts")
			for _, grade in { "Rough", "Clean", "Pristine", "Flawless" } do
				local clean = ItemBuilder.build({ Kind = "Clean", OreId = ore.Id, Grade = grade }, cf, 3)
				T.le(#partsOf(clean), BUDGET.Clean, ore.Id .. " clean parts")
				T.le(countClass(clean, "ParticleEmitter"), 1, ore.Id .. " clean: one sparkle emitter at most")
				T.eq(countClass(clean, "PointLight"), 0, ore.Id .. " clean: no lights on loose items")
			end
			local ingot = ItemBuilder.build({ Kind = "Ingot", OreId = ore.Id, Grade = "Flawless" }, cf, 3)
			T.le(#partsOf(ingot), BUDGET.Ingot, ore.Id .. " ingot parts")
			local crushed = ItemBuilder.build({ Kind = "Crushed", OreId = ore.Id }, cf, 3)
			T.le(#partsOf(crushed), BUDGET.Raw, ore.Id .. " crushed parts")
			for _, recipe in { "Dagger", "Greatsword", "ToolHead", "Helm" } do
				local gear = ItemBuilder.build({ Kind = "Gear", OreId = ore.Id, Recipe = recipe }, cf, 3)
				T.truthy(gear.PrimaryPart, ore.Id .. " " .. recipe)
			end
			for _, kind in { "Clean", "Raw", "Ingot", "Crushed" } do
				local shown = ItemBuilder.display({ K = kind, O = ore.Id, G = "Flawless" }, cf, 3)
				T.le(#partsOf(shown), BUDGET.Display, ore.Id .. " display " .. kind)
			end
		end
	end)

	T.test("ores: physical items have exactly one colliding Body, the rest is welded decor", function()
		for _, ore in OreData.List do
			for _, kind in { "Raw", "Clean", "Crushed", "Ingot" } do
				local model = ItemBuilder.build({ Kind = kind, OreId = ore.Id, Grade = "Flawless" }, CF.new(2, 3, 4), ore.Id)
				local label = ore.Id .. " " .. kind
				local body = model.PrimaryPart
				T.truthy(body, label .. " has a PrimaryPart")
				T.eq(body.Name, "Body", label .. " PrimaryPart is Body")
				T.falsy(body.Anchored, label .. " body unanchored")
				local colliding = 0
				-- (Lune hands out a new userdata per property read: compare with ==, not as table keys)
				local weldedParts = {}
				for _, d in model:GetDescendants() do
					if d:IsA("WeldConstraint") then
						T.eq(d.Part0, body, label .. " welds hang on the body")
						table.insert(weldedParts, d.Part1)
					end
				end
				local function isWelded(part)
					for _, other in weldedParts do
						if other == part then
							return true
						end
					end
					return false
				end
				for _, part in partsOf(model) do
					T.falsy(part.Anchored, label .. " " .. part.Name .. " unanchored")
					if part.CanCollide then
						colliding += 1
					end
					if part ~= body then
						T.truthy(part.Massless, label .. " decor is massless")
						T.truthy(isWelded(part), label .. " decor " .. part.Name .. " is welded")
					end
				end
				T.eq(colliding, 1, label .. " colliding parts")
				T.truthy(body.CanCollide, label .. " the body collides")
			end
		end
	end)

	T.test("ores: display copies stand on cf, anchored, no collisions, no welds", function()
		local cf = CF.new(3, 5, -2) * CF.Angles(0, 0.7, 0)
		for _, ore in OreData.List do
			for _, kind in { "Clean", "Raw", "Ingot", "Crushed" } do
				local model = ItemBuilder.display({ K = kind, O = ore.Id }, cf, 9)
				local label = ore.Id .. " display " .. kind
				T.truthy(model.PrimaryPart, label .. " PrimaryPart")
				T.eq(countClass(model, "WeldConstraint") + countClass(model, "Weld"), 0, label .. " no welds")
				for _, part in partsOf(model) do
					T.truthy(part.Anchored, label .. " anchored")
					T.falsy(part.CanCollide, label .. " no collision")
					T.falsy(part.CanTouch, label .. " no touch")
				end
				T.near(lowestPoint(model), 5, 0.06, label .. " stands on cf")
				local lights = countClass(model, "PointLight")
				if kind == "Clean" then
					local order = orderOf(ore)
					T.eq(lights, if order >= 5 then 1 else 0, label .. " lights (Legendary and Mythic only)")
					T.eq(countClass(model, "ParticleEmitter") > 0, order >= 4, label .. " sparkles from Epic up")
					local motes = 0
					for _, part in partsOf(model) do
						if part.Name == "Mote" then
							motes += 1
						end
					end
					T.eq(motes, if order >= 6 then 3 else 0, label .. " orbiting motes (Mythic only)")
				else
					T.eq(lights, 0, label .. " no light")
				end
			end
		end
	end)

	T.test("ores: dirty ore is the same chunk for every ore, only the glint color differs", function()
		local function snapshot(oreId, seed)
			local model = ItemBuilder.build({ Kind = "Raw", OreId = oreId }, CF.new(1, 2, 3), seed)
			local list = {}
			for _, part in partsOf(model) do
				table.insert(list, part)
			end
			return model, list
		end
		for _, seed in { 1, 77, "abc" } do
			local refModel, ref = snapshot("Coal", seed)
			for _, ore in OreData.List do
				local model, list = snapshot(ore.Id, seed)
				T.eq(#list, #ref, ore.Id .. " raw part count")
				T.eq(model.PrimaryPart.Size, refModel.PrimaryPart.Size, ore.Id .. " raw body size")
				local glints = 0
				for i, part in list do
					local other = ref[i]
					T.eq(part.Name, other.Name, ore.Id .. " raw part " .. i)
					T.eq(part.Size, other.Size, ore.Id .. " raw part " .. i .. " size")
					T.truthy((part.CFrame.Position - other.CFrame.Position).Magnitude < 1e-6, ore.Id .. " raw part " .. i .. " position")
					T.eq(part.Material, other.Material, ore.Id .. " raw part " .. i .. " material")
					if part.Name == "Glint" then
						glints += 1
						T.eq(part.Color, ItemBuilder.glowColor(ore.Glow), ore.Id .. " glint color")
					else
						T.eq(part.Color, other.Color, ore.Id .. " raw part " .. i .. " color (no hint)")
					end
				end
				T.truthy(glints >= 1, ore.Id .. " raw has a glint")
				T.eq(countClass(model, "PointLight"), 0, ore.Id .. " raw: no light")
				T.eq(countClass(model, "ParticleEmitter"), 0, ore.Id .. " raw: no particles")
			end
		end
	end)

	T.test("ores: every ore has its own recipe and its own silhouette", function()
		local shapes = {}
		local signatures = {}
		for _, ore in OreData.List do
			T.truthy(ItemBuilder.Shapes[ore.Shape], ore.Id .. " has a recipe for " .. ore.Shape)
			T.falsy(shapes[ore.Shape], ore.Id .. " shares its shape with " .. tostring(shapes[ore.Shape]))
			shapes[ore.Shape] = ore.Id
			-- signature: the part sizes of the display look (different recipes never match)
			local model = ItemBuilder.display({ K = "Clean", O = ore.Id }, CF.new(), 1)
			local sizes = {}
			for _, part in partsOf(model) do
				local s = part.Size
				table.insert(sizes, string.format("%.2f/%.2f/%.2f", s.X, s.Y, s.Z))
			end
			table.sort(sizes)
			local signature = table.concat(sizes, ";")
			T.falsy(signatures[signature], ore.Id .. " looks like " .. tostring(signatures[signature]))
			signatures[signature] = ore.Id
		end
	end)

	T.test("ores: neon keeps its color under bloom, Common ores do not glow", function()
		for _, ore in OreData.List do
			local order = orderOf(ore)
			for _, model in
				{
					ItemBuilder.build({ Kind = "Clean", OreId = ore.Id }, CF.new(), 4),
					ItemBuilder.display({ K = "Clean", O = ore.Id }, CF.new(), 4),
				}
			do
				local neon = 0
				for _, part in partsOf(model) do
					if part.Material == NEON then
						neon += 1
						local _, s, v = part.Color:ToHSV()
						T.truthy(s >= 0.45, ore.Id .. " neon " .. part.Name .. " is saturated (" .. s .. ")")
						T.truthy(v <= 0.86, ore.Id .. " neon " .. part.Name .. " is not near-white (" .. v .. ")")
						T.falsy(part.CastShadow, ore.Id .. " neon casts no shadow")
					end
				end
				if order == 1 then
					T.eq(neon, 0, ore.Id .. " (Common) has no glowing parts")
				else
					T.truthy(neon > 0, ore.Id .. " glows")
				end
			end
		end
	end)

	T.test("ores: the cleaning close-up builds for every ore in the ore's colors", function()
		local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
		local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
		for _, ore in OreData.List do
			for seed = 1, 3 do
				local pattern = Patterns.generate(ore.Id, seed * 131)
				local shell = OreShellBuilder.build(pattern, CF.new(0, 5, 0))
				local label = `{ore.Id} seed {seed}`
				T.truthy(#pattern.Cells >= 100, label .. " has dirt to wash")
				T.truthy(#shell.Core > 0, label .. " the real ore waits under the dirt")
				T.truthy(shell.Treasure:FindFirstChildWhichIsA("BasePart") ~= nil, label .. " in its podium look")
				for _, cell in pattern.Cells do
					T.truthy(shell.Dirt[cell.Index] ~= nil, label .. " every cell has its dirt block")
				end
				-- the ore sits behind the dirt (nothing pokes through) and inside the clump
				local work = CF.new(0, 5, 0)
				for _, part in shell.Core do
					if part.Transparency < 1 then
						local at = work:PointToObjectSpace(part.CFrame.Position)
						T.truthy(at.Z < OreShellBuilder.CoreFront, label .. " behind the dirt")
						T.truthy(math.sqrt(at.X * at.X + at.Y * at.Y) < 1.3 * OreShellBuilder.Scale, label .. " inside the clump")
					end
				end
			end
		end
	end)

	---------------------------------------------------------------- rocks

	local function zoneOres(zone)
		local ids = {}
		for oreId in zone.Ores do
			table.insert(ids, oreId)
		end
		table.sort(ids, function(a, b)
			return OreData.get(a).Income < OreData.get(b).Income
		end)
		return ids
	end

	T.test("rocks: 1-3 ores in every zone, within budget, the content stays secret", function()
		for _, zone in WorldLayout.Zones do
			local ids = zoneOres(zone)
			if #ids > 0 then
				local previous = 0
				for n = 1, 3 do
					local set = { ids[1], ids[math.max(1, #ids - 1)], ids[#ids] }
					local oreIds = table.move(set, 1, n, 1, {})
					local rock = OreNodeBuilder.buildRock(zone.Id, oreIds, CF.new(10, 0, 10), 42)
					local label = `{zone.Id} with {n} ores`
					T.eq(rock.Name, "Rock", label .. " name")
					T.truthy(rock.PrimaryPart, label .. " PrimaryPart")
					T.le(#partsOf(rock), 20, label .. " parts")
					T.eq(rock:GetAttribute("Zone"), zone.Id, label .. " Zone")
					T.eq(rock:GetAttribute("OreCount"), n, label .. " OreCount")
					T.eq(rock:GetAttribute("Stage"), 0, label .. " Stage")
					T.eq(rock:GetAttribute("OreId"), nil, label .. " has no OreId")
					for _, d in rock:GetDescendants() do
						T.eq(d:GetAttribute("OreId"), nil, label .. " no OreId on " .. d.Name)
						for _, ore in OreData.List do
							T.falsy(d.Name:find(ore.Id, 1, true), label .. ": a part is named after " .. ore.Id)
						end
					end
					T.eq(countClass(rock, "PointLight") + countClass(rock, "ParticleEmitter"), 0, label .. ": no lights or particles")
					-- glints in the ores' colors
					local colors = {}
					local glints = 0
					for _, part in partsOf(rock) do
						if part.Name == "Glint" then
							glints += 1
							colors[colorKey(part.Color)] = true
						end
					end
					T.eq(glints, if n == 1 then 3 else 2 * n, label .. " glints")
					for _, oreId in oreIds do
						T.truthy(colors[colorKey(ItemBuilder.glowColor(OreData.get(oreId).Glow))], label .. " glint for " .. oreId)
					end
					-- more ores = a bigger rock
					local size = rock.PrimaryPart.Size.X
					T.lt(previous, size, label .. " is bigger")
					previous = size
				end
			end
		end
	end)

	T.test("rocks: glints are the same size whatever the rarity", function()
		local common = OreNodeBuilder.buildRock("DeepHollow", { "Coal" }, CF.new(), 7)
		local mythic = OreNodeBuilder.buildRock("DeepHollow", { "Heartstone" }, CF.new(), 7)
		local a, b = partsOf(common), partsOf(mythic)
		T.eq(#a, #b, "same part count")
		for i, part in a do
			T.eq(part.Size, b[i].Size, "part " .. i .. " size")
			if part.Name ~= "Glint" then
				T.eq(part.Color, b[i].Color, "part " .. i .. " color")
			end
		end
	end)

	T.test("rocks: an unknown zone still builds a plain rock", function()
		local rock = OreNodeBuilder.buildRock("Nowhere", { "Coal", "Iron" }, CF.new(), 1)
		T.truthy(rock.PrimaryPart, "primary part")
		T.eq(rock:GetAttribute("OreCount"), 2)
	end)
end
