-- The Epic, Legendary and Mythic ore looks from the owner's ore picture (OreShapesHigh):
-- every ore has its own recipe, keeps the clean / display part budgets and reads its rarity.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local NEON = roblox.Enum.Material.Neon
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreShapesHigh = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShapesHigh")

	local function parts(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("ore looks (high): every Epic+ ore has its own recipe from OreShapesHigh", function()
		local listed = {}
		for _, id in OreShapesHigh.Ores do
			listed[id] = true
			local ore = OreData.get(id)
			T.truthy(ore, id .. " is an ore")
			T.eq(ore.Shape, id, id .. " Shape = Id")
			T.truthy(ItemBuilder.Shapes[id], id .. " has a recipe")
			T.truthy(Rarity.get(ore.Rarity).Order >= 4, id .. " is Epic or rarer")
		end
		for _, ore in OreData.List do
			if Rarity.get(ore.Rarity).Order >= 4 then
				T.truthy(listed[ore.Id], ore.Id .. " is listed in OreShapesHigh.Ores")
			end
		end
	end)

	T.test("ore looks (high): clean and display copies keep their budgets", function()
		for _, id in OreShapesHigh.Ores do
			for _, seed in { 1, 7, "x" } do
				local clean = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Flawless" }, CF.new(0, 3, 0), seed)
				T.le(#parts(clean), ItemBuilder.Budget.Clean, id .. " clean parts")
				local shown = ItemBuilder.display({ K = "Clean", O = id, G = "Flawless" }, CF.new(0, 3, 0), seed)
				T.le(#parts(shown), ItemBuilder.Budget.Display, id .. " display parts")
			end
		end
	end)

	T.test("ore looks (high): no two looks share a silhouette", function()
		local seen = {}
		for _, id in OreShapesHigh.Ores do
			local sizes = {}
			for _, part in parts(ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 1)) do
				local s = part.Size
				table.insert(sizes, string.format("%.2f/%.2f/%.2f", s.X, s.Y, s.Z))
			end
			table.sort(sizes)
			local signature = table.concat(sizes, ";")
			T.falsy(seen[signature], id .. " looks like " .. tostring(seen[signature]))
			seen[signature] = id
		end
	end)

	T.test("ore looks (high): every look glows and the display has more detail than the loose ore", function()
		for _, id in OreShapesHigh.Ores do
			local clean = ItemBuilder.build({ Kind = "Clean", OreId = id }, CF.new(), 2)
			local shown = ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 2)
			local glowing = 0
			for _, part in parts(shown) do
				if part.Material == NEON and part.Name ~= "Mote" then
					glowing += 1
				end
			end
			T.truthy(glowing >= 1, id .. " display has glowing parts")
			local showParts = 0
			for _, part in parts(shown) do
				if part.Name ~= "Mote" then
					showParts += 1
				end
			end
			-- the clean ore also has its invisible Body
			T.truthy(showParts >= #parts(clean) - 1, id .. " display is at least as detailed as the clean ore")
		end
	end)
end
