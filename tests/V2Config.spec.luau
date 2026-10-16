-- Design v2 configs: 30 ores, rocks and blasters, money, big numbers, the base yard.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local CFrame = Loader.CFrame

	T.test("v2: 30 ores, each with its own id, name and shape", function()
		T.eq(#OreData.List, 30)
		local ids, names, shapes = {}, {}, {}
		for _, ore in OreData.List do
			T.falsy(ids[ore.Id], "duplicate id " .. ore.Id)
			T.falsy(names[ore.Name], "duplicate name " .. ore.Name)
			T.falsy(shapes[ore.Shape], ore.Id .. " shares its shape with " .. tostring(shapes[ore.Shape]))
			ids[ore.Id], names[ore.Name], shapes[ore.Shape] = true, true, ore.Id
			T.truthy(Rarity.ById[ore.Rarity], ore.Id .. " rarity")
			T.eq(typeof(ore.Color), "Color3", ore.Id .. " color")
			T.eq(typeof(ore.Glow), "Color3", ore.Id .. " glow")
			T.eq(typeof(ore.Crust), "Color3", ore.Id .. " crust")
			T.eq(typeof(ore.Material), "EnumItem", ore.Id .. " material")
			T.truthy(#ore.Lore > 10, ore.Id .. " lore")
			T.eq(ore.Value, ore.Income * OreData.SellSeconds, ore.Id .. " value")
			T.lt(0, ore.Hardness, ore.Id .. " hardness")
		end
	end)

	T.test("v2: income grows with every ore, rarity never goes down", function()
		for i = 2, #OreData.List do
			local a, b = OreData.List[i - 1], OreData.List[i]
			T.lt(a.Income, b.Income, a.Id .. " < " .. b.Id)
			T.le(a.Hardness, b.Hardness, a.Id .. " hardness <= " .. b.Id)
			T.le(Rarity.ById[a.Rarity].Order, Rarity.ById[b.Rarity].Order, a.Id .. " rarity")
		end
		T.eq(OreData.ById.Diamond.Income, 1300, "the owner's example: a diamond earns 1,300/s")
	end)

	T.test("v2: every ore can be found, every zone ore exists", function()
		local found = {}
		for _, zone in WorldLayout.Zones do
			for oreId, weight in zone.Ores do
				T.truthy(OreData.ById[oreId], zone.Id .. " has unknown ore " .. oreId)
				T.lt(0, weight, zone.Id .. " weight " .. oreId)
				found[oreId] = true
			end
			T.truthy(zone.MinBlaster >= 1 and zone.MinBlaster <= BlasterData.MaxLevel, zone.Id .. " blaster gate")
			T.lt(0, zone.RockHealth, zone.Id .. " rock health")
		end
		for _, ore in OreData.List do
			T.truthy(found[ore.Id], ore.Id .. " is in no zone")
		end
	end)

	T.test("v2: blasters get stronger and pricier, level 11 is coming soon", function()
		T.eq(#BlasterData.Levels, BlasterData.MaxLevel + 1)
		T.truthy(BlasterData.Levels[BlasterData.MaxLevel + 1].ComingSoon, "level 11")
		T.eq(BlasterData.get(1).Recipe, nil, "everyone starts with level 1")
		for level = 2, BlasterData.MaxLevel do
			local a, b = BlasterData.get(level - 1), BlasterData.get(level)
			T.eq(b.Level, level)
			T.lt(a.Damage, b.Damage, "damage " .. level)
			T.le(a.Range, b.Range, "range " .. level)
			local recipe = b.Recipe
			T.truthy(recipe, "recipe " .. level)
			if recipe then
				T.truthy(Rarity.ById[recipe.MinRarity], "recipe rarity " .. level)
				local before = a.Recipe
				if before then
					T.lt(before.Coins, recipe.Coins, "price " .. level)
				end
			end
		end
		T.eq(BlasterData.get(0).Level, 1, "clamped low")
		T.eq(BlasterData.get(99).Level, 10, "clamped high")
		T.eq(BlasterData.get(0 / 0).Level, 1, "NaN")
		T.near(BlasterData.damage(2, "Heartstone"), 9 * 1.3, 1e-9, "mythic bonus")
		T.eq(BlasterData.damage(2, ""), 9, "rusty")
		T.eq(BlasterData.displayName(3, "Gold"), "Gold Spark Blaster")
		T.eq(BlasterData.displayName(1, ""), "Rusty Blaster")
	end)

	T.test("v2: zone gates let a level-1 blaster start and need upgrades deeper", function()
		T.eq(WorldLayout.ZoneById.Outcrops.MinBlaster, 1)
		T.eq(WorldLayout.ZoneById.Quarry.MinBlaster, 1)
		T.lt(WorldLayout.ZoneById.Quarry.MinBlaster, WorldLayout.ZoneById.EmberCaves.MinBlaster)
		T.lt(WorldLayout.ZoneById.EmberCaves.MinBlaster, WorldLayout.ZoneById.DeepHollow.MinBlaster)
		-- a starter rock breaks in a few seconds with the rusty blaster
		local hp = BlasterData.rockHealth(WorldLayout.ZoneById.Outcrops.RockHealth, { "Coal" })
		local seconds = hp / BlasterData.damage(1, "")
		T.truthy(seconds >= 1 and seconds <= 4, "starter rock takes " .. seconds .. " s")
	end)

	T.test("v2: rocks hold 1-3 ores and get tougher with more and harder ores", function()
		local sum = 0
		for _, chance in BlasterData.Rocks.OreCountOdds do
			sum += chance
		end
		T.near(sum, 1, 1e-9, "odds add up")
		T.eq(BlasterData.oreCount(0), 1)
		T.eq(BlasterData.oreCount(0.6), 2)
		T.eq(BlasterData.oreCount(0.999), 3)
		local one = BlasterData.rockHealth(100, { "Coal" })
		local two = BlasterData.rockHealth(100, { "Coal", "Coal" })
		local hard = BlasterData.rockHealth(100, { "Coal", "Heartstone" })
		T.lt(one, two)
		T.lt(two, hard)
		T.eq(BlasterData.rockHealth(100, {}), BlasterData.rockHealth(100, { "Coal" }), "empty counts as 1 soft ore")
	end)

	T.test("v2: podium income and the dirty name", function()
		T.eq(ItemData.income({ K = "Clean", O = "Diamond", G = "Rough" }), 1300)
		T.near(ItemData.income({ K = "Clean", O = "Diamond", G = "Flawless" }), 1300 * 2.4, 1e-9)
		T.eq(ItemData.income({ K = "Raw", O = "Diamond" }), 0, "dirty ore earns nothing on a podium")
		T.eq(ItemData.income({ K = "Ingot", O = "Diamond", G = "Rough" }), 0)
		T.eq(ItemData.income({ K = "Clean", O = "Nope", G = "Rough" }), 0)
		T.eq(ItemData.income(nil), 0)
		T.eq(ItemData.displayName("Raw", "Heartstone"), "Dirty Ore", "rarity stays hidden")
		T.eq(ItemData.displayName("Clean", "Diamond", "Pristine"), "Pristine Diamond")
		T.eq(ItemData.value("Clean", "Coal", "Rough"), 30, "Tobin pays 30 s of income")
	end)

	T.test("v2: offline earnings and pen capacity", function()
		T.eq(EconomyConfig.offlineEarnings(100, 30, false), 0, "under a minute pays nothing")
		T.eq(EconomyConfig.offlineEarnings(100, 3600, false), 100 * 0.5 * 3600)
		T.eq(EconomyConfig.offlineEarnings(100, 24 * 3600, false), 100 * 0.5 * 5 * 3600, "5 h cap")
		T.eq(EconomyConfig.offlineEarnings(100, 24 * 3600, true), 100 * 0.5 * 12 * 3600, "12 h with the extension")
		T.eq(EconomyConfig.offlineEarnings(0 / 0, 3600, true), 0)
		T.eq(EconomyConfig.offlineEarnings(100, 0 / 0, true), 0)
		T.eq(EconomyConfig.penCapacity(0, GameConfig.MaxStoredItems), EconomyConfig.Pen.BaseCapacity)
		T.eq(EconomyConfig.penCapacity(999, GameConfig.MaxStoredItems), EconomyConfig.Pen.BaseCapacity + EconomyConfig.Pen.PerLevel * #EconomyConfig.Pen.Prices)
		T.le(EconomyConfig.penCapacity(999, GameConfig.MaxStoredItems), GameConfig.MaxStoredItems)
		T.eq(EconomyConfig.multiplier({ 0.1, 0.25 }), 1.35)
		for i = 2, #EconomyConfig.Pen.Prices do
			T.lt(EconomyConfig.Pen.Prices[i - 1], EconomyConfig.Pen.Prices[i], "pen price " .. i)
		end
	end)

	T.test("v2: big numbers", function()
		T.eq(Format.big(0), "0")
		T.eq(Format.big(7), "7")
		T.eq(Format.big(0.5), "0.5")
		T.eq(Format.big(999), "999")
		T.eq(Format.big(1000), "1K")
		T.eq(Format.big(1234), "1.23K")
		T.eq(Format.big(45600000), "45.6M")
		T.eq(Format.big(2e9), "2B")
		T.eq(Format.big(3e12), "3T")
		T.eq(Format.big(1.5e15), "1.5Qa")
		T.eq(Format.big(1e18), "1Qi")
		T.eq(Format.big(999999), "1M", "rounds up into the next suffix")
		T.eq(Format.big(1e33), "1Dc")
		T.eq(Format.big(-1234), "-1.23K")
		T.eq(Format.big(0 / 0), "0")
		T.truthy(Format.big(1.2e40):find("e40") ~= nil, "scientific past Dc")
		T.eq(Format.money(1300), "$1.3K")
		T.eq(Format.perSecond(1300), "+$1.3K/s")
		T.eq(Format.short(1234), "1,234")
		T.eq(Format.short(12345), "12.3K")
	end)

	T.test("v2: the base yard stays off the machine grid and nothing overlaps", function()
		local half = GameConfig.PlotCells * GameConfig.CellSize / 2
		local pieces = BaseLayout.pieces()
		local names = {}
		for name, piece in pieces do
			table.insert(names, name)
			local minZ = piece.Center.Z - piece.Size.Z / 2
			T.truthy(minZ >= half + 1, name .. " overlaps the machine grid")
		end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local a, b = pieces[names[i]], pieces[names[j]]
				local overlapX = math.abs(a.Center.X - b.Center.X) < (a.Size.X + b.Size.X) / 2
				local overlapZ = math.abs(a.Center.Z - b.Center.Z) < (a.Size.Z + b.Size.Z) / 2
				T.falsy(overlapX and overlapZ, names[i] .. " overlaps " .. names[j])
			end
		end
		T.eq(#BaseLayout.Podiums, EconomyConfig.Podiums.Max)
		-- the coastal railway stays on the island (ground reaches |x| = Island.Max.X + 6)
		for _, plot in WorldLayout.Plots do
			local rail = (WorldLayout.plotCFrame(plot) * CFrame.new(0, 0, BaseLayout.RailZ)).Position
			T.lt(math.abs(rail.X), WorldLayout.Island.Max.X, "rail of plot " .. plot.Id)
		end
	end)
end
