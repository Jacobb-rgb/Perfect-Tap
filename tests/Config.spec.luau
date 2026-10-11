-- Config sanity: every ore/pickaxe/item table is consistent.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")

	T.test("every ore has a known rarity and a reachable pickaxe tier", function()
		local maxTier = 0
		for _, pick in ToolData.Pickaxes do
			maxTier = math.max(maxTier, pick.Tier)
		end
		for _, ore in OreData.List do
			T.truthy(Rarity.ById[ore.Rarity], ore.Id .. " rarity")
			T.le(ore.Tier, maxTier, ore.Id .. " tier")
			T.lt(0, ore.Value, ore.Id .. " value")
			T.lt(0, ore.Hardness, ore.Id .. " hardness")
		end
	end)

	T.test("ores get more valuable with rarity", function()
		for i = 2, #OreData.List do
			local a, b = OreData.List[i - 1], OreData.List[i]
			T.le(Rarity.ById[a.Rarity].Order, Rarity.ById[b.Rarity].Order, a.Id .. " before " .. b.Id)
			T.lt(a.Value, b.Value, a.Id .. " value < " .. b.Id)
		end
	end)

	T.test("pickaxes are ordered by tier, damage and price", function()
		for i = 2, #ToolData.Pickaxes do
			local a, b = ToolData.Pickaxes[i - 1], ToolData.Pickaxes[i]
			T.eq(b.Tier, a.Tier + 1, b.Id .. " tier")
			T.lt(a.Damage, b.Damage, b.Id .. " damage")
			T.lt(a.Price, b.Price, b.Id .. " price")
			T.le(b.Cooldown, a.Cooldown, b.Id .. " cooldown")
		end
	end)

	T.test("every zone ore exists and every ore spawns somewhere", function()
		local spawns = {}
		for _, zone in WorldLayout.Zones do
			for oreId in zone.Ores do
				T.truthy(OreData.ById[oreId], zone.Id .. " ore " .. oreId)
				spawns[oreId] = true
			end
		end
		for _, ore in OreData.List do
			T.truthy(spawns[ore.Id], ore.Id .. " spawns in a zone")
		end
	end)

	T.test("processing always increases value", function()
		for _, ore in OreData.List do
			local raw = ItemData.value("Raw", ore.Id)
			local clean = ItemData.value("Clean", ore.Id, "Rough")
			local crushedPair = ItemData.value("Crushed", ore.Id, "Rough") * 2
			local ingot = ItemData.value("Ingot", ore.Id, "Rough")
			T.lt(raw, clean, ore.Id .. " raw<clean")
			T.lt(clean, ingot, ore.Id .. " clean<ingot")
			T.le(clean, crushedPair, ore.Id .. " clean<=2 crushed")
			for _, recipe in ItemData.Recipes do
				local gear = ItemData.value("Gear", ore.Id, "Rough", recipe.Id)
				T.lt(ingot * recipe.Ingots, gear, ore.Id .. " " .. recipe.Id .. " gear > ingots")
			end
		end
	end)

	T.test("grades: higher score never gives a lower grade", function()
		local last = 0
		for score = 0, 1, 0.01 do
			local level = ItemData.gradeLevel(ItemData.gradeFromScore(score))
			T.le(last, level, "score " .. score)
			last = level
		end
		T.eq(ItemData.gradeFromScore(1), "Flawless")
		T.eq(ItemData.gradeFromScore(0), "Rough")
	end)
end
