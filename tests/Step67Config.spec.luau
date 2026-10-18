-- Steps 6-7 P0 contracts: gear, enchants, boosts, golems + capsules, wheel,
-- artifacts + story, leaderboards, monetization placeholders, the new save
-- records and their migration, the Bonuses helper, shards and the policy
-- wrapper. Odds always sum to 1 (also boosted), boosts favour rarer results,
-- prices climb, leaderboard numbers survive the round trip in order, and no
-- name borrows from Minecraft.
return function(T, Loader)
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local EnchantConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig")
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local LeaderboardConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LeaderboardConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local StoryConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoryConfig")
	local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local Shards = Loader.requirePath("ServerScriptService.Server.Shards")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")

	local EPS = 1e-9
	local NOW = 1_800_000_000

	local function sum(list: { any }, field: string): number
		local total = 0
		for _, line in list do
			total += line[field]
		end
		return total
	end

	local function deepEqual(a: any, b: any): boolean
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function fresh(): { [string]: any }
		return ProfileStore.deepCopy(DataTemplate)
	end

	local function order(rarity: string): number
		return Rarity.ById[rarity].Order
	end

	---------------------------------------------------------------- names

	-- words that would borrow from Minecraft (checked lower-case, as substrings)
	local BANNED = {
		"minecraft",
		"creeper",
		"enderman",
		"ender pearl",
		"wither",
		"steve",
		"herobrine",
		"zombie",
		"piglin",
		"villager",
		"iron golem",
		"snow golem",
		"copper golem",
		"nether",
		"redstone",
		"allay",
		"warden",
		"ghast",
		"blaze rod",
		"elytra",
		"mooshroom",
	}

	local function allNames(): { string }
		local names = {}
		local function add(text: string)
			table.insert(names, text)
		end
		for _, golem in GolemConfig.List do
			add(golem.Name)
			add(golem.Id)
			add(golem.Lore)
		end
		for _, capsule in CapsuleConfig.List do
			add(capsule.Name)
			add(capsule.Description)
		end
		for _, enchant in EnchantConfig.List do
			add(enchant.Name)
			add(enchant.Description)
		end
		for _, line in GearConfig.Lines do
			add(line.Name)
		end
		for _, kind in BoostConfig.Kinds do
			add(kind.Name)
		end
		for _, artifact in ArtifactConfig.List do
			add(artifact.Name)
			add(artifact.Lore)
		end
		for _, collection in ArtifactConfig.Collections do
			add(collection.Name)
			add(collection.Reward.Title)
		end
		for _, chapter in StoryConfig.Chapters do
			add(chapter.Title)
			for _, page in chapter.Pages do
				add(page.Title)
				add(page.Text)
			end
		end
		for _, product in MonetizationConfig.List do
			add(product.Name)
			add(product.Description)
		end
		return names
	end

	T.test("Step67: no name or text borrows from Minecraft", function()
		for _, text in allNames() do
			local lower = text:lower()
			for _, word in BANNED do
				T.falsy(lower:find(word, 1, true), `"{text}" contains "{word}"`)
			end
		end
	end)

	---------------------------------------------------------------- stats

	T.test("Step67: StatConfig adds, multiplies and caps", function()
		local totals = StatConfig.combine({
			{ DamagePct = 0.1, OreLuckMult = 2.5, Junk = 5 },
			{ DamagePct = 0.2, OreLuckMult = 2, TwinDropChance = 0.4 },
			{ TwinDropChance = 0.4, WalkSpeed = 0 / 0, ThrowMult = -1 },
			"junk",
		})
		T.near(totals.DamagePct, 0.3, EPS, "Add stats sum")
		T.near(totals.OreLuckMult, 2.5, EPS, "Mult stats multiply, capped at Max (2.5 x 2 -> 2.5)")
		local mult = StatConfig.combine({ { ThrowMult = 1.2 }, { ThrowMult = 1.5 } })
		T.near(mult.ThrowMult, 1.8, EPS, "Mult stats multiply")
		T.near(totals.TwinDropChance, 0.5, EPS, "capped at Max")
		T.eq(totals.WalkSpeed, 0, "NaN skipped")
		T.eq(totals.ThrowMult, 1, "a Mult value <= 0 is skipped")
		T.eq(totals.Junk, nil, "unknown names skipped")
		T.eq(StatConfig.describe("DamagePct", 0.1), "+10% blaster damage")
		T.eq(StatConfig.describe("OreLuckMult", 2.5), "x2.5 ore luck")
		T.eq(StatConfig.describe("ReachStuds", 4), "+4 studs blaster range")
		T.eq(StatConfig.describe("WalkSpeed", 2), "+2 walk speed")
		-- real caps: the best gear today can reach them, the totals never pass them
		local caps = {
			DamagePct = 1.5,
			OreLuckPct = 1.5,
			OreLuckMult = 2.5,
			IncomePct = 2,
			SellPct = 3,
			WalkSpeedPct = 0.5,
			GolemBondPct = 1,
			ArtifactPct = 3,
			OverchargePct = 1,
			MagnetBonus = 20,
		}
		for id, max in caps do
			T.eq(StatConfig.ById[id].Max, max, id .. " cap")
			local huge = StatConfig.combine({ { [id] = 1000 } })
			T.truthy(huge[id] <= max, id .. " capped")
		end
		-- ore luck: the product is capped too, broken values are no luck
		T.eq(StatConfig.oreLuck(0, 1), 1)
		T.near(StatConfig.oreLuck(0.5, 2.5), 3.75, EPS)
		T.eq(StatConfig.oreLuck(1.5, 2.5), StatConfig.MaxOreLuck, "the two caps multiplied")
		T.near(StatConfig.MaxOreLuck, 6.25, EPS)
		T.eq(StatConfig.oreLuck(9, 9), StatConfig.MaxOreLuck, "never past it")
		-- Hexa Lucky is sold as "ore luck x2.5": exactly x2.5 at every OreLuckPct the caps allow
		for _, pct in { 0, 0.15, 0.3, 0.6, 0.75, 1.05, 1.25, 1.5, 3 } do
			local without, with = BoostConfig.hexaLuck(math.min(pct, StatConfig.ById.OreLuckPct.Max :: number))
			T.near(with / without, BoostConfig.Kinds.HexaLucky.Mult, EPS, `Hexa Lucky x2.5 at +{pct * 100}% ore luck`)
		end
		-- balance: the best damage stays within ~1.5 blaster levels (x1.8 each), the
		-- best income bonus at most x3, even with paid golems and Mythic enchants
		local best = StatConfig.combine({ { DamagePct = 10, OverchargePct = 10, IncomePct = 10 } })
		T.truthy(1 + best.DamagePct <= 2.5, "damage at most x2.5")
		T.truthy((1 + best.DamagePct) * (1 + best.OverchargePct) <= 5, "x5 at most on a cracked rock's last third")
		T.truthy(1 + best.IncomePct <= 3, "income at most x3")
		T.eq(StatConfig.oreLuck(0 / 0, -2), 1)
		T.eq(StatConfig.oreLuck(-1, 1), 1, "never below 1")
	end)

	---------------------------------------------------------------- gear

	T.test("Step67: gear lines, values per level and exponential prices", function()
		T.eq(#GearConfig.Lines, 5)
		T.eq(GearConfig.MaxLevel, 5)
		local expected = {
			Boots = { 16, 18, 20, 22, 24, 26 },
			HelmetLamp = { 0, 18, 26, 34, 44, 56 },
			Backpack = { 1, 2, 3, 5, 8, 12 },
			Gloves = { 11, 13, 15, 17, 20, 24 },
			Magnet = { 0, 14, 18, 24, 30, 38 },
		}
		for lineId, values in expected do
			for level = 0, 5 do
				T.eq(GearConfig.value(lineId, level), values[level + 1], `{lineId} level {level}`)
			end
			T.eq(GearConfig.value(lineId, 99), values[6], "clamped high")
			T.eq(GearConfig.value(lineId, -3), values[1], "clamped low")
			T.eq(GearConfig.value(lineId, 0 / 0), values[1], "NaN = level 0")
		end
		T.near(GearConfig.value("Gloves", 0, "ThrowMult"), 1, EPS)
		T.near(GearConfig.value("Gloves", 5, "ThrowMult"), 1.4, EPS)
		T.truthy(GearConfig.value("HelmetLamp", 5, "LampBrightness") > GearConfig.value("HelmetLamp", 1, "LampBrightness"))
		for _, line in GearConfig.Lines do
			T.eq(#line.Prices, GearConfig.MaxLevel, line.Id .. " has a price per level")
			T.truthy(line.Prices[1] >= 300 and line.Prices[1] <= 1500, line.Id .. " starts near 500")
			for level = 2, #line.Prices do
				local ratio = line.Prices[level] / line.Prices[level - 1]
				T.truthy(ratio >= 5 and ratio <= 7, `{line.Id} grows about x6 ({ratio})`)
			end
			for stat, values in line.Stats do
				T.truthy(StatConfig.ById[stat], line.Id .. " stat " .. stat)
				T.eq(#values, GearConfig.MaxLevel + 1)
				for level = 2, #values do
					T.truthy(values[level] > values[level - 1], `{line.Id} {stat} grows`)
				end
			end
			T.eq(GearConfig.nextPrice(line.Id, 0), line.Prices[1])
			T.eq(GearConfig.nextPrice(line.Id, GearConfig.MaxLevel), nil, "no price at the top")
		end
		T.eq(GearConfig.nextPrice("Cape", 0), nil)
	end)

	T.test("Step67: gear quote, stats and the ToolData shim", function()
		local gear = { Boots = 2, Backpack = 5 }
		T.eq(GearConfig.quote(gear, "Boots", 3), GearConfig.ById.Boots.Prices[3], "the next level")
		local price, reason = GearConfig.quote(gear, "Boots", 2)
		T.eq(price, nil)
		T.eq(reason, "Stale", "a repeat of the last level")
		price, reason = GearConfig.quote(gear, "Boots", nil)
		T.eq(reason, "Stale", "the level is required")
		price, reason = GearConfig.quote(gear, "Backpack", 6)
		T.eq(reason, "Max")
		price, reason = GearConfig.quote(gear, "Jetpack", 1)
		T.eq(reason, "BadItem")
		price, reason = GearConfig.quote(nil, "Magnet", 1)
		T.eq(price, GearConfig.ById.Magnet.Prices[1], "a missing record is all zeros")
		for _, code in { "BadItem", "Max", "Stale", "NoCoins", "TooFar" } do
			T.truthy(GearConfig.Reasons[code], "reason text " .. code)
		end
		local stats = GearConfig.stats(gear)
		T.eq(stats.WalkSpeed, 20)
		T.eq(stats.CarryCapacity, 12)
		T.eq(stats.MagnetRadius, 0)
		T.eq(stats.PickupRange, 11)
		T.eq(stats.LampRange, 0)
		T.eq(GearConfig.carryCapacity(gear, false), 12)
		T.eq(GearConfig.carryCapacity(gear, true), 24, "StrongBack doubles")
		T.eq(GearConfig.carryCapacity(nil, false), 1, "bare hands")
		-- the deprecated shim: old CarryLevel N = Backpack level N - 1
		T.eq(#ToolData.CarryLevels, GearConfig.MaxLevel + 1)
		local old = { 1, 2, 3, 5, 8 } -- the old CarryLevels 1..5
		for n, capacity in old do
			T.eq(ToolData.carryCapacity(n, false), capacity, "old carry level " .. n)
			T.eq(ToolData.CarryLevels[n].Capacity, GearConfig.value("Backpack", n - 1))
		end
		T.eq(ToolData.carryCapacity(nil, false), 1, "nil = bare hands")
	end)

	---------------------------------------------------------------- enchants

	T.test("Step67: enchants: 12 across every rarity, slots by blaster level", function()
		T.eq(#EnchantConfig.List, 12)
		local rarities = {}
		local ids = {}
		for _, enchant in EnchantConfig.List do
			T.falsy(ids[enchant.Id], "unique id " .. enchant.Id)
			ids[enchant.Id] = true
			rarities[enchant.Rarity] = true
			T.truthy(Rarity.ById[enchant.Rarity], enchant.Id .. " rarity")
			local tiers = #enchant.Coins
			T.truthy(tiers >= 1, enchant.Id .. " has a price")
			for stat, values in enchant.Effects do
				T.truthy(StatConfig.ById[stat], enchant.Id .. " effect " .. stat)
				T.eq(#values, tiers, enchant.Id .. " value per tier")
				for t = 2, tiers do
					T.truthy(values[t] > values[t - 1], enchant.Id .. " grows per tier")
				end
			end
			for t = 2, tiers do
				T.truthy(enchant.Coins[t] > enchant.Coins[t - 1], enchant.Id .. " coin prices climb")
			end
			if enchant.Shards then
				T.eq(#enchant.Shards, tiers)
			end
			T.eq(#EnchantConfig.describe(enchant.Id, 1) > 0, true)
		end
		for _, info in Rarity.List do
			T.truthy(rarities[info.Id], "an enchant of rarity " .. info.Id)
		end
		-- exponential by rarity: every rarity's cheapest first tier beats the previous rarity's dearest
		local cheapest, dearest = {}, {}
		for _, enchant in EnchantConfig.List do
			local o = order(enchant.Rarity)
			cheapest[o] = math.min(cheapest[o] or math.huge, enchant.Coins[1])
			dearest[o] = math.max(dearest[o] or 0, enchant.Coins[1])
		end
		for o = 2, #Rarity.List do
			T.truthy(cheapest[o] > dearest[o - 1], "rarity " .. o .. " costs more")
		end
		-- shards for the rarer ones, the two Mythics: enormous coins or 20 Robux
		for _, enchant in EnchantConfig.List do
			if enchant.Rarity == "Epic" or enchant.Rarity == "Legendary" then
				T.truthy(enchant.Shards, enchant.Id .. " sells for shards")
			end
		end
		for _, id in { "Heartfire", "Starbreaker" } do
			local enchant = EnchantConfig.ById[id]
			T.eq(enchant.Rarity, "Mythic")
			T.truthy(enchant.Coins[1] >= 1e11, id .. " costs an enormous amount")
			local product = MonetizationConfig.get(enchant.Product)
			T.truthy(product, id .. " has a product")
			T.eq(product.Robux, 20)
			T.eq(product.Enchant, id)
		end
		T.eq(EnchantConfig.MaxSlots, 4)
		local slotsAt = { [1] = 1, [3] = 1, [4] = 2, [6] = 2, [7] = 3, [9] = 3, [10] = 4 }
		for level, slots in slotsAt do
			T.eq(EnchantConfig.unlockedSlots(level), slots, "slots at blaster level " .. level)
		end
		T.eq(EnchantConfig.unlockedSlots(nil), 1)
	end)

	T.test("Step67: enchant quotes, grants, slots and stats", function()
		local enchants: any = { Owned = { Power = 1 }, Slots = { "", "", "", "" } }
		T.eq(EnchantConfig.quote(enchants, "Power", "Coins", 2), EnchantConfig.ById.Power.Coins[2])
		local _, reason = EnchantConfig.quote(enchants, "Power", "Coins", 1)
		T.eq(reason, "Stale")
		_, reason = EnchantConfig.quote(enchants, "Power", "Shards", 2)
		T.eq(reason, "BadCurrency", "Commons don't sell for shards")
		_, reason = EnchantConfig.quote(enchants, "Power", "Gold", 2)
		T.eq(reason, "BadCurrency")
		_, reason = EnchantConfig.quote(enchants, "Nope", "Coins", 1)
		T.eq(reason, "BadItem")
		T.eq(EnchantConfig.quote(enchants, "TwinDrop", "Shards", 1), EnchantConfig.ById.TwinDrop.Shards[1])
		_, reason = EnchantConfig.quote(enchants, "Heartfire", "Robux", 1)
		T.eq(reason, "Robux", "a Robux buy goes to PurchasePrompt")
		_, reason = EnchantConfig.quote(enchants, "Power", "Robux", 2)
		T.eq(reason, "BadCurrency", "no Robux for normal enchants")
		T.eq(EnchantConfig.grant(enchants, "Power"), 2)
		T.eq(EnchantConfig.grant(enchants, "Power"), 3)
		T.eq(EnchantConfig.grant(enchants, "Power"), 3, "stays at the top tier")
		_, reason = EnchantConfig.quote(enchants, "Power", "Coins", 4)
		T.eq(reason, "Max")
		T.eq(EnchantConfig.grant(enchants, "Heartfire"), 1)
		T.eq(EnchantConfig.grant(enchants, "Fake"), 0)
		-- slots: blaster level 4 opens 2
		local ok, why = EnchantConfig.setSlot(enchants, 4, 1, "Power")
		T.truthy(ok, "slot 1")
		ok, why = EnchantConfig.setSlot(enchants, 4, 3, "Heartfire")
		T.falsy(ok)
		T.eq(why, "Locked", "slot 3 needs blaster level 7")
		ok, why = EnchantConfig.setSlot(enchants, 4, 2, "Lucky")
		T.eq(why, "NotOwned")
		ok, why = EnchantConfig.setSlot(enchants, 4, 5, "Power")
		T.eq(why, "BadSlot")
		ok = EnchantConfig.setSlot(enchants, 4, 2, "Power")
		T.truthy(ok, "moving Power to slot 2")
		T.eq(enchants.Slots[1], "", "it left slot 1")
		T.eq(enchants.Slots[2], "Power")
		T.eq(EnchantConfig.firstFreeSlot(enchants, 4), 1)
		EnchantConfig.setSlot(enchants, 4, 1, "Heartfire")
		T.eq(EnchantConfig.firstFreeSlot(enchants, 4), nil, "both open slots used")
		local stats = EnchantConfig.stats(enchants, 4)
		T.near(stats.DamagePct, 0.35 + 0.75, EPS, "Power III + Heartfire")
		T.near(stats.OverchargePct, 0.5, EPS)
		-- a lower blaster level closes slot 2
		stats = EnchantConfig.stats(enchants, 1)
		T.near(stats.DamagePct, 0.75, EPS, "only slot 1 counts")
		ok = EnchantConfig.setSlot(enchants, 4, 1, nil)
		T.truthy(ok)
		T.eq(enchants.Slots[1], "", "emptied")
		for _, code in { "BadItem", "BadCurrency", "Max", "Stale", "NoCoins", "NoShards", "TooFar", "BadSlot", "Locked", "NotOwned" } do
			T.truthy(EnchantConfig.Reasons[code], "reason text " .. code)
		end
	end)

	---------------------------------------------------------------- golems + capsules

	T.test("Step67: 18 original golems from Common to Mythic", function()
		T.eq(#GolemConfig.List, 18)
		local names, rarities = {}, {}
		for _, golem in GolemConfig.List do
			T.falsy(names[golem.Name], "unique name " .. golem.Name)
			names[golem.Name] = true
			rarities[golem.Rarity] = true
			T.truthy(GolemConfig.Accessories[golem.Accessory], golem.Id .. " accessory")
			T.truthy(GolemConfig.BonusTypes[golem.Bonus.Type], golem.Id .. " bonus type")
			T.truthy(golem.Bonus.Value > 0 and golem.Bonus.Value <= 0.5, golem.Id .. " bonus size")
			T.eq(typeof(golem.Body), "Color3")
			T.eq(typeof(golem.Glow), "Color3")
			T.eq(typeof(golem.Trim), "Color3")
			T.eq(typeof(golem.Material), "EnumItem")
			T.truthy(golem.Ore == nil or OreData.exists(golem.Ore), golem.Id .. " ore")
		end
		for _, info in Rarity.List do
			T.truthy(rarities[info.Id], "a golem of rarity " .. info.Id)
		end
		-- rarer golems give at least as much as commoner ones of the same bonus type
		for _, a in GolemConfig.List do
			for _, b in GolemConfig.List do
				if a.Bonus.Type == b.Bonus.Type and order(a.Rarity) > order(b.Rarity) then
					T.truthy(a.Bonus.Value >= b.Bonus.Value, `{a.Id} >= {b.Id}`)
				end
			end
		end
		T.eq(GolemConfig.EquipSlots, 3)
		T.eq(GolemConfig.InventoryCap, 60)
		T.truthy(GolemConfig.MaxSaved >= GolemConfig.InventoryCap + 10, "room for a paid x10")
	end)

	T.test("Step67: golem record helpers", function()
		local golems: any = { Owned = {}, Equipped = {}, NextId = 1 }
		local a = GolemConfig.add(golems, "PebbleGolem")
		local b = GolemConfig.add(golems, "DiamondDuke")
		local c = GolemConfig.add(golems, "EmberImp")
		local d = GolemConfig.add(golems, "CelestialSovereign")
		T.eq(a.Id, 1)
		T.eq(d.Id, 4)
		T.eq(golems.NextId, 5)
		T.eq(GolemConfig.add(golems, "IronThing"), nil, "unknown kind")
		T.truthy(GolemConfig.equip(golems, a.Id))
		T.truthy(GolemConfig.equip(golems, a.Id), "equipping twice is fine")
		T.eq(#golems.Equipped, 1)
		T.truthy(GolemConfig.equip(golems, b.Id))
		T.truthy(GolemConfig.equip(golems, c.Id))
		local ok, why = GolemConfig.equip(golems, d.Id)
		T.falsy(ok)
		T.eq(why, "SlotsFull")
		ok, why = GolemConfig.equip(golems, 99)
		T.eq(why, "BadGolem")
		ok, why = GolemConfig.unequip(golems, d.Id)
		T.eq(why, "NotEquipped")
		local stats = GolemConfig.stats(golems, 0)
		T.near(stats.IncomePct, 0.03 + 0.15, EPS, "Pebble + Duke income")
		T.near(stats.DamagePct, 0.1, EPS, "Ember Imp mining speed")
		stats = GolemConfig.stats(golems, 0.5)
		T.near(stats.IncomePct, (0.03 + 0.15) * 1.5, EPS, "Golem Bond +50%")
		T.eq(GolemConfig.describe("DiamondDuke", 0), "+15% Income")
		local best = GolemConfig.equipBest(golems)
		T.eq(#best, 3)
		T.eq(best[1], d.Id, "the Mythic first")
		T.falsy(table.find(best, a.Id), "the Pebble Golem sits out")
		local removed = GolemConfig.delete(golems, { d.Id, 77 })
		T.eq(removed, 1)
		T.falsy(GolemConfig.isEquipped(golems, d.Id), "deleting unequips")
		T.eq(#golems.Equipped, 2)
		local n, reason = GolemConfig.delete(golems, { 1.5 })
		T.eq(n, 0)
		T.eq(reason, "BadIds")
		n, reason = GolemConfig.delete(golems, {})
		T.eq(reason, "BadIds")
		-- the cap: plain adds stop at InventoryCap, a paid receipt may pass it up to MaxSaved
		local full: any = { Owned = {}, Equipped = {}, NextId = 1 }
		for _ = 1, GolemConfig.InventoryCap do
			T.truthy(GolemConfig.add(full, "PebbleGolem"))
		end
		T.eq(GolemConfig.room(full), 0)
		T.eq(GolemConfig.add(full, "PebbleGolem"), nil, "full")
		T.truthy(GolemConfig.add(full, "PebbleGolem", true), "a receipt is never lost")
		-- a broken record is repaired by the writers
		local broken: any = { Owned = "x", NextId = 0 / 0 }
		T.truthy(GolemConfig.add(broken, "TinTumbler"))
		T.eq(broken.Owned[1].Id, 1)
	end)

	T.test("Step67: paid golems are marked, locked golems are never deleted", function()
		local golems: any = { Owned = {}, Equipped = {}, NextId = 1 }
		local coin = GolemConfig.add(golems, "PebbleGolem")
		local paid = GolemConfig.add(golems, "RoseKnight", true, true)
		local other = GolemConfig.add(golems, "EmberImp")
		T.eq(coin.Paid, nil, "a coin capsule's golem isn't paid")
		T.eq(paid.Paid, true, "a Robux receipt's golem is marked Paid")
		local ok, why = GolemConfig.setLocked(golems, paid.Id, true)
		T.truthy(ok)
		T.eq(GolemConfig.find(golems, paid.Id).Locked, true)
		ok, why = GolemConfig.setLocked(golems, 99, true)
		T.eq(why, "BadGolem")
		ok, why = GolemConfig.setLocked(golems, coin.Id, "yes")
		T.eq(why, "BadLock")
		GolemConfig.equip(golems, paid.Id)
		local removed = GolemConfig.delete(golems, { coin.Id, paid.Id, other.Id })
		T.eq(removed, 2, "the locked one is skipped")
		T.truthy(GolemConfig.find(golems, paid.Id), "still there")
		T.truthy(GolemConfig.isEquipped(golems, paid.Id), "and still equipped")
		T.truthy(GolemConfig.setLocked(golems, paid.Id, false))
		T.eq(GolemConfig.find(golems, paid.Id).Locked, nil, "unlocking clears the flag")
		T.eq(GolemConfig.delete(golems, { paid.Id }), 1, "unlocked: it can go")
		T.truthy(GolemConfig.Reasons.BadLock)
	end)

	T.test("Step67: renamed golems (the 36-ore roster names) keep their rarity, colors and saves", function()
		local renames = {
			{ Old = "RubyKnight", New = "RoseKnight", Name = "Rose Knight", Rarity = "Epic", Ore = "CrystalRose" },
			{ Old = "StormcoreTitan", New = "StormTitan", Name = "Storm Titan", Rarity = "Legendary", Ore = "StormGem" },
			{
				Old = "StarmetalSovereign",
				New = "CelestialSovereign",
				Name = "Celestial Sovereign",
				Rarity = "Mythic",
				Ore = "CelestialCore",
			},
		}
		for _, r in renames do
			local golem = GolemConfig.ById[r.New]
			T.truthy(golem, r.New)
			T.eq(GolemConfig.ById[r.Old], nil, r.Old .. " is gone")
			T.eq(GolemConfig.Renamed[r.Old], r.New, r.Old .. " -> " .. r.New)
			T.eq(golem.Name, r.Name)
			T.eq(golem.Rarity, r.Rarity, r.New .. " keeps its rarity")
			T.eq(golem.Ore, r.Ore)
			-- the 36-ore roster has the ore: the golem wears its own colors (no fallback ore)
			T.truthy(OreData.exists(r.Ore), r.Ore .. " is in OreData")
			T.eq(OreData.Renamed[r.Ore], nil, r.Ore .. " is a live id, not a renamed one")
			T.eq(golem.Glow, OreData.get(r.Ore).Glow, r.New .. " glows in its ore's colors")
			T.eq(golem.Body, OreData.get(r.Ore).Color, r.New .. " has its ore's body color")
			T.eq((golem :: any).FallbackOre, nil, r.New .. " has no FallbackOre")
		end
		for old, new in GolemConfig.Renamed do
			T.eq(GolemConfig.ById[old], nil, old .. ": an old id is never a live golem")
			T.truthy(GolemConfig.ById[new], new .. ": renamed to a live golem")
		end
		for _, golem in GolemConfig.List do
			local ore = golem.Ore
			if ore ~= nil then
				T.truthy(OreData.exists(ore), golem.Id .. ": its ore exists")
				T.eq(OreData.Renamed[ore], nil, golem.Id .. ": not an ore of the old roster")
			end
			T.eq((golem :: any).FallbackOre, nil, golem.Id .. ": no FallbackOre field")
		end
		for _, capsule in CapsuleConfig.List do
			for old in GolemConfig.Renamed do
				T.eq(capsule.Odds[old], nil, `{capsule.Id} rolls no old id`)
			end
		end
		-- a save from before the rename: the kinds take their new ids, stay equipped, twice
		local data = fresh()
		data.Golems = {
			Owned = {
				{ Id = 1, Kind = "RubyKnight", Locked = true },
				{ Id = 2, Kind = "StormcoreTitan" },
				{ Id = 3, Kind = "StarmetalSovereign", Paid = true },
				{ Id = 4, Kind = "PebbleGolem" },
			},
			Equipped = { 1, 2, 3 },
			NextId = 5,
		}
		for run = 1, 2 do
			Migrations.run(data, NOW)
			T.eq(data.Golems.Owned[1].Kind, "RoseKnight", `run {run}`)
			T.eq(data.Golems.Owned[1].Locked, true, `run {run}: the lock stays`)
			T.eq(data.Golems.Owned[2].Kind, "StormTitan", `run {run}`)
			T.eq(data.Golems.Owned[3].Kind, "CelestialSovereign", `run {run}`)
			T.eq(data.Golems.Owned[3].Paid, true, `run {run}: still a paid golem`)
			T.eq(data.Golems.Owned[4].Kind, "PebbleGolem", `run {run}`)
			T.eq(#data.Golems.Equipped, 3, `run {run}: all three stay equipped`)
			T.eq(GolemConfig.equippedKinds(data.Golems), "RoseKnight,StormTitan,CelestialSovereign", `run {run}: followers`)
		end
	end)

	T.test("Step67: golems of a newer update count, can't be equipped or deleted; Delete takes plain lists only", function()
		local golems: any = {
			Owned = { { Id = 1, Kind = "FutureGolem" }, { Id = 2, Kind = "PebbleGolem" }, { Id = 3, Kind = "RoseKnight" } },
			Equipped = {},
			NextId = 4,
		}
		T.eq(GolemConfig.count(golems), 3, "the unknown one counts toward the cap")
		T.eq(GolemConfig.room(golems), GolemConfig.InventoryCap - 3)
		local ok, why = GolemConfig.equip(golems, 1)
		T.falsy(ok)
		T.eq(why, "BadGolem", "an unknown kind can't be equipped")
		local best = GolemConfig.equipBest(golems)
		T.eq(#best, 2, "EquipBest skips it")
		T.falsy(table.find(best, 1))
		T.eq(GolemConfig.equippedKinds(golems), "RoseKnight,PebbleGolem", "the follower attribute")
		T.eq(next(GolemConfig.stats({ Owned = golems.Owned, Equipped = { 1 } }, 0)), nil, "gives nothing")
		local removed = GolemConfig.delete(golems, { 1, 2 })
		T.eq(removed, 1, "only the known one goes")
		T.truthy(GolemConfig.find(golems, 1), "the newer update's golem stays")
		T.eq(GolemConfig.find(golems, 2), nil)
		T.eq(GolemConfig.equippedKinds(golems), "RoseKnight")
		-- a client table with extra keys, holes or too many entries is refused
		local n, reason = GolemConfig.delete(golems, { 3, Extra = 1 })
		T.eq(n, 0)
		T.eq(reason, "BadIds", "not a plain list")
		n, reason = GolemConfig.delete(golems, { [1] = 3, [3] = 3 })
		T.eq(reason, "BadIds", "a hole")
		local many: any = {}
		for i = 1, 5000 do
			many[i] = 3
		end
		many.Junk = true
		n, reason = GolemConfig.delete(golems, many)
		T.eq(reason, "BadIds", "too many")
		T.truthy(GolemConfig.find(golems, 3), "nothing deleted")
		-- budgets for the followers and museum pieces
		T.truthy(GolemConfig.MaxParts <= 25 and ArtifactConfig.MaxParts <= 8)
		-- museums: 8 bases x 24 artifacts stay within ~1,500 parts; one real lamp light per client
		T.truthy(8 * #ArtifactConfig.List * ArtifactConfig.MaxParts <= 1600)
		T.eq(GearConfig.LampBudget.MaxLights, 1)
		T.eq(GearConfig.LampBudget.Shadows, false)
		T.truthy(GearConfig.LampBudget.OthersNeon)
		T.truthy(GolemConfig.FollowerHideDistance <= 150)
		T.eq(ArtifactConfig.LightRarity, "Mythic")
	end)

	T.test("Step67: capsules: exact odds sum to 1, Triple Lucky triples the rarest and keeps the sum", function()
		T.eq(#CapsuleConfig.List, 3)
		T.eq(CapsuleConfig.ById.Stone.Currency, "Coins")
		T.eq(CapsuleConfig.ById.Crystal.Currency, "Coins")
		T.eq(CapsuleConfig.ById.Royal.Currency, "Robux")
		T.truthy(CapsuleConfig.ById.Crystal.Price > CapsuleConfig.ById.Stone.Price * 10, "Crystal is expensive")
		local epicPlus = {}
		for _, capsule in CapsuleConfig.List do
			local base = CapsuleConfig.odds(capsule.Id, false)
			local lucky = CapsuleConfig.odds(capsule.Id, true)
			T.near(sum(base, "Chance"), 1, EPS, capsule.Id .. " odds sum to 1")
			T.near(sum(lucky, "Chance"), 1, EPS, capsule.Id .. " Triple Lucky odds sum to 1")
			T.eq(#base, #lucky)
			local from = order(capsule.LuckyFrom)
			local luckyShare = 0
			for i, line in base do
				T.eq(lucky[i].Golem, line.Golem)
				T.truthy(line.Chance > 0, "no zero odds")
				if GolemConfig.order(line.Golem) >= from then
					luckyShare += line.Chance
					T.near(lucky[i].Chance, line.Chance * 3, EPS, line.Golem .. " exactly x3")
				else
					T.truthy(lucky[i].Chance < line.Chance, line.Golem .. " gives way")
				end
			end
			T.truthy(luckyShare > 0 and luckyShare * 3 < 1, capsule.Id .. " can triple its lucky golems")
			-- rarer favoured: the chance of each rarity tier at or above LuckyFrom grows
			local baseR, luckyR = CapsuleConfig.rarityOdds(capsule.Id, false), CapsuleConfig.rarityOdds(capsule.Id, true)
			for rarity, chance in baseR do
				if order(rarity) >= from then
					T.truthy(luckyR[rarity] > chance, capsule.Id .. " " .. rarity .. " more likely")
				end
			end
			-- rolls follow the list; the edges stay inside
			T.eq(CapsuleConfig.roll(capsule.Id, false, 0), base[1].Golem)
			T.eq(CapsuleConfig.roll(capsule.Id, false, 0.9999999999), base[#base].Golem)
			T.eq(CapsuleConfig.roll(capsule.Id, true, 1), lucky[#lucky].Golem)
			local share = 0
			for rarity, chance in baseR do
				if order(rarity) >= order("Epic") then
					share += chance
				end
			end
			epicPlus[capsule.Id] = share
			-- paid random: Robux always, coins only while coins can be bought with Robux
			T.eq(
				CapsuleConfig.isPaidRandom(capsule.Id),
				capsule.Currency == "Robux" or MonetizationConfig.coinsBuyable(),
				capsule.Id .. " paid random"
			)
		end
		T.truthy(epicPlus.Royal > epicPlus.Crystal and epicPlus.Crystal > epicPlus.Stone, "Royal has the best odds")
		-- prices: 1 / 3 / 10, x10 a small discount
		T.eq(CapsuleConfig.price("Stone", 1), 2500)
		T.eq(CapsuleConfig.price("Stone", 3), 7500)
		T.eq(CapsuleConfig.price("Stone", 10), 22500, "x10 pays 9")
		T.eq(CapsuleConfig.price("Stone", 2), nil, "only 1, 3 or 10")
		T.eq(CapsuleConfig.price("Royal", 1), nil, "Royal is Robux")
		-- prices grow with the blaster level (never with income)
		T.eq(#CapsuleConfig.LevelScale, 10)
		local last = 0
		for level = 1, 10 do
			local scale = CapsuleConfig.LevelScale[level]
			T.truthy(scale >= last, "the scale never falls")
			last = scale
			T.eq(CapsuleConfig.price("Crystal", 1, level), 750000 * scale)
			T.eq(CapsuleConfig.price("Stone", 10, level), math.floor(2500 * scale * 9 + 0.5))
		end
		T.eq(CapsuleConfig.price("Stone", 1, 1), CapsuleConfig.price("Stone", 1), "nil = level 1")
		T.eq(CapsuleConfig.price("Stone", 1, 99), 2500 * CapsuleConfig.LevelScale[10], "above the table")
		T.eq(CapsuleConfig.price("Stone", 1, 0 / 0), 2500, "broken = level 1")
		T.truthy(CapsuleConfig.LevelScale[10] >= 1000, "late game prices are not pocket change")
		-- with coin packs off, a restricted player can still buy coin capsules
		T.eq(CapsuleConfig.allRestricted(false), false)
		T.eq(CapsuleConfig.allRestricted(true), MonetizationConfig.coinsBuyable())
		T.truthy(CapsuleConfig.ClientCooldown >= 1 and CapsuleConfig.ResultTimeout >= 5)
		for _, count in CapsuleConfig.Counts do
			local key = CapsuleConfig.product("Royal", count)
			local product = MonetizationConfig.get(key)
			T.truthy(product, "Royal x" .. count)
			T.eq(product.Count, count)
			T.eq(product.Capsule, "Royal")
			T.truthy(product.PaidRandom, "paid random")
		end
		local x1 = MonetizationConfig.get("RoyalCapsule1").Robux
		T.truthy(MonetizationConfig.get("RoyalCapsule10").Robux < x1 * 10, "x10 has a Robux discount")
		T.eq(#CapsuleConfig.odds("Nope", false), 0)
	end)

	---------------------------------------------------------------- boosts

	T.test("Step67: boosts stack to 2 hours, coin prices follow the blaster level", function()
		local boosts: any = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 }
		T.falsy(BoostConfig.active(boosts, "HexaLucky", NOW))
		T.eq(BoostConfig.extend(boosts, "HexaLucky", 300, NOW, true), NOW + 300)
		T.truthy(BoostConfig.active(boosts, "HexaLucky", NOW + 299))
		T.falsy(BoostConfig.active(boosts, "HexaLucky", NOW + 300))
		T.eq(BoostConfig.extend(boosts, "HexaLucky", 600, NOW + 100, true), NOW + 900, "adds to what is left")
		T.truthy(BoostConfig.canExtend(boosts, "HexaLucky", 3600, NOW))
		T.falsy(BoostConfig.canExtend(boosts, "HexaLucky", 7200, NOW), "past 2 h")
		T.eq(BoostConfig.extend(boosts, "HexaLucky", 7200, NOW, true), NOW + 7200, "capped")
		T.eq(BoostConfig.extend(boosts, "HexaLucky", 3600, NOW, false), NOW + 10800, "a paid receipt passes the cap")
		T.eq(BoostConfig.extend(boosts, "HexaLucky", 60, NOW, true), NOW + 10800, "capping never shortens")
		T.eq(BoostConfig.extend(boosts, "TripleLucky", -5, NOW, true), 0, "bad seconds change nothing")
		T.eq(BoostConfig.remaining(boosts, "TripleLucky", NOW), 0)
		T.eq(BoostConfig.remaining({ HexaLuckyUntil = 0 / 0 }, "HexaLucky", NOW), 0, "broken = off")
		local stats = BoostConfig.stats(boosts, NOW)
		T.eq(stats.OreLuckMult, 2.5, "Hexa Lucky = ore luck x2.5")
		T.eq(stats.CapsuleLuckMult, nil)
		BoostConfig.extend(boosts, "TripleLucky", 600, NOW, true)
		T.eq(BoostConfig.stats(boosts, NOW).CapsuleLuckMult, 3)
		-- offers: coin prices follow the blaster level (never the income)
		for _, offer in BoostConfig.CoinOffers do
			T.eq(offer.Seconds, 300, "coin boosts last 5 minutes")
			local last = 0
			for level = 1, 10 do
				local price = BoostConfig.coinPrice(offer.Id, level) :: number
				T.truthy(price >= last, offer.Id .. " never cheaper at a higher blaster level")
				last = price
			end
			T.truthy(last >= 1e8, offer.Id .. " is no pocket change late in the game")
			T.eq(BoostConfig.coinPrice(offer.Id, 0 / 0), BoostConfig.coinPrice(offer.Id, 1), "broken = level 1")
			T.eq(BoostConfig.isPaidRandom(offer.Id), MonetizationConfig.coinsBuyable(), offer.Id .. " paid random only with coin packs")
		end
		-- Triple Lucky pays off on Crystal capsules, so it is priced against them
		for level = 1, 10 do
			local crystal = CapsuleConfig.price("Crystal", 1, level) :: number
			local price = BoostConfig.coinPrice("TripleLucky5", level) :: number
			T.eq(price, 2 * crystal, "Triple Lucky 5 min = 2 Crystal capsules at blaster level " .. level)
			local twoHours = BoostConfig.MaxStackSeconds / 300 * price
			T.truthy(twoHours >= 24 * crystal, "2 h of coin Triple Lucky costs at least 24 Crystal capsules")
		end
		-- Hexa Lucky: 20 % of the next blaster forge (the top forge at the top), at least 2,500
		T.eq(BoostConfig.coinPrice("HexaLucky5", 1), 2500, "the minimum")
		T.eq(BoostConfig.coinPrice("HexaLucky5", 3), 3000, "20 % of the 15,000 forge")
		T.eq(BoostConfig.coinPrice("HexaLucky5", 4), 20000)
		T.eq(BoostConfig.coinPrice("HexaLucky5", 9), 3e8)
		T.eq(BoostConfig.coinPrice("HexaLucky5", 10), 3e8, "the level-10 forge at the top")
		T.eq(BoostConfig.coinPrice("HexaLucky5", 99), 3e8)
		-- coins only top a boost up: the Robux packs keep their place
		local wallet: any = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 }
		local price, why = BoostConfig.coinQuote(wallet, "TripleLucky5", 5, false, NOW)
		T.eq(price, BoostConfig.coinPrice("TripleLucky5", 5))
		T.eq(why, nil)
		BoostConfig.extend(wallet, "TripleLucky", 300, NOW, true)
		T.truthy(BoostConfig.coinQuote(wallet, "TripleLucky5", 5, false, NOW), "5 min left: a top-up is fine")
		BoostConfig.extend(wallet, "TripleLucky", 300, NOW, true)
		price, why = BoostConfig.coinQuote(wallet, "TripleLucky5", 5, false, NOW)
		T.eq(price, nil)
		T.eq(why, "CoinLimit", "10 min left: no more coin time")
		T.truthy(BoostConfig.coinQuote(wallet, "TripleLucky5", 5, false, NOW + 1), "9:59 left: fine again")
		T.truthy(BoostConfig.CoinBuyBelow + 300 <= 15 * 60, "coins keep at most 15 minutes running")
		T.truthy(BoostConfig.Reasons.CoinLimit)
		BoostConfig.extend(wallet, "HexaLucky", 3600, NOW, false) -- a Robux pack
		_, why = BoostConfig.coinQuote(wallet, "HexaLucky5", 5, false, NOW)
		T.eq(why, "CoinLimit", "a running Robux hour isn't topped up with coins")
		_, why = BoostConfig.coinQuote(wallet, "HexaLucky15", 5, false, NOW)
		T.eq(why, "BadOffer", "a Robux offer has no coin quote")
		_, why = BoostConfig.coinQuote(wallet, 42, 5, false, NOW)
		T.eq(why, "BadOffer")
		T.eq(BoostConfig.coinPrice("TripleLucky15", 3), nil, "a Robux offer has no coin price")
		for _, offer in BoostConfig.RobuxOffers do
			local product = MonetizationConfig.get(offer.Product)
			T.truthy(product and product.PaidRandom, offer.Id .. " product, paid random")
			T.truthy(BoostConfig.isPaidRandom(offer.Id))
		end
		T.truthy(BoostConfig.isPaidRandom("Nope"), "unknown = strict")
		-- expiry for the Bonuses cache
		local times: any = { TripleLuckyUntil = NOW + 50, HexaLuckyUntil = NOW + 20 }
		T.eq(BoostConfig.nextExpiry(times, NOW), NOW + 20)
		T.eq(BoostConfig.nextExpiry(times, NOW + 20), NOW + 50)
		T.eq(BoostConfig.nextExpiry(times, NOW + 50), nil)
		-- Hexa Lucky: does it do anything here? (zones with Rare+ ores)
		T.truthy(BoostConfig.hasEffect("TripleLucky", 1))
		T.truthy(BoostConfig.hasEffect("HexaLucky", 1), "the Quarry has Gold")
		T.falsy(BoostConfig.hasEffect("Nope", 1))
		local effects = BoostConfig.zoneEffects(1, false, 1, 2.5)
		local byZone = {}
		for _, effect in effects do
			byZone[effect.Zone] = effect
		end
		T.truthy(byZone.Outcrops and byZone.Outcrops.NoEffect, "Outcrops: no effect here")
		T.eq(byZone.Outcrops.Before, 0)
		T.eq(byZone.Outcrops.After, 0)
		T.eq(#byZone.Outcrops.Rarities, 0)
		T.truthy(byZone.Quarry and not byZone.Quarry.NoEffect)
		T.truthy(byZone.Quarry.After > byZone.Quarry.Before, "Quarry: Gold more likely")
		T.eq(#byZone.Quarry.Rarities, 1, "the Quarry's only lucky rarity: Rare (Gold)")
		T.eq(byZone.Quarry.Rarities[1].Rarity, "Rare")
		T.near(byZone.Quarry.Rarities[1].Before, byZone.Quarry.Before, EPS)
		T.eq(byZone.EmberCaves, nil, "a zone the blaster can't mine yet isn't listed")
		T.eq(byZone.Grotto, nil, "VIP zones only for VIP players")
		T.truthy(#BoostConfig.zoneEffects(10, true, 1, 2.5) > #effects)
		local now, with = BoostConfig.hexaLuck(0.5)
		T.near(now, 1.5, EPS)
		T.near(with, 3.75, EPS)
		local _, capped = BoostConfig.hexaLuck(1.5)
		T.eq(capped, StatConfig.MaxOreLuck, "the card shows the capped luck")
		T.truthy(BoostConfig.Reasons.NoEffect)
		T.truthy(BoostConfig.OfferById.TripleLucky15.Seconds == 900, "Triple Lucky 15 min")
		T.truthy(BoostConfig.OfferById.HexaLucky15.Seconds == 900, "Hexa Lucky 15 min")
	end)

	local function chanceOf(list: { any }, oreId: string): number
		for _, line in list do
			if line.Ore == oreId then
				return line.Chance
			end
		end
		return 0
	end

	local function rarityShare(list: { any }, rarity: string): number
		local share = 0
		for _, line in list do
			if OreData.ById[line.Ore].Rarity == rarity then
				share += line.Chance
			end
		end
		return share
	end

	T.test("Step67: ore luck grows with rarity: odds sum to 1 and favour rarer ores (Deep Hollow too)", function()
		-- the multipliers: luck ^ (Rare 1, Epic 1.5, Legendary 2, Mythic 2.5), never falling with rarity
		local table25 = BoostConfig.luckTable(2.5)
		T.eq(#table25, 4, "Rare, Epic, Legendary, Mythic")
		T.eq(table25[1].Rarity, "Rare")
		T.near(table25[1].Mult, 2.5, EPS, "Hexa Lucky: Rare x2.5")
		T.near(table25[2].Mult, 2.5 ^ 1.5, EPS, "Epic x3.95")
		T.near(table25[3].Mult, 6.25, EPS, "Legendary x6.25")
		T.near(table25[4].Mult, 2.5 ^ 2.5, EPS, "Mythic x9.88")
		local last = 0
		for _, info in Rarity.List do
			local mult = BoostConfig.rarityMult(info.Id, 4)
			T.truthy(mult >= last, info.Id .. ": never falls with rarity")
			last = mult
		end
		T.eq(BoostConfig.rarityMult("Common", 4), 1)
		T.eq(BoostConfig.rarityMult("Uncommon", 4), 1)
		T.eq(BoostConfig.rarityMult("Mythic", 1), 1, "no luck")
		T.eq(BoostConfig.rarityMult("Mythic", 0 / 0), 1, "broken luck = no luck")
		T.eq(BoostConfig.rarityMult("Nope", 4), 1)
		for _, zone in WorldLayout.Zones do
			local base = BoostConfig.zoneOdds(zone.Id, 1)
			if #base == 0 then
				continue
			end
			T.near(sum(base, "Chance"), 1, EPS, zone.Id .. " odds sum to 1")
			for _, luck in { 1.5, 2.5, 4 } do
				local boosted = BoostConfig.zoneOdds(zone.Id, luck)
				T.near(sum(boosted, "Chance"), 1, EPS, `{zone.Id} odds at luck {luck} sum to 1`)
				T.eq(#boosted, #base)
				-- the exact effect: an ore's chance relative to another's grows by the ratio of their multipliers
				local first = base[1].Ore
				local firstGain = chanceOf(boosted, first) / chanceOf(base, first)
				local byOrder: { [number]: number } = {}
				for i, line in base do
					T.eq(boosted[i].Ore, line.Ore)
					local gain = boosted[i].Chance / line.Chance
					local expected = BoostConfig.oreMult(line.Ore, luck) / BoostConfig.oreMult(first, luck)
					T.near(gain / firstGain, expected, 1e-9, `{zone.Id} {line.Ore} x{expected} at luck {luck}`)
					local o = order(OreData.ById[line.Ore].Rarity)
					byOrder[o] = gain
					if not BoostConfig.isLuckyOre(line.Ore) then
						T.truthy(gain <= 1 + EPS, zone.Id .. " " .. line.Ore .. " gives way")
					end
				end
				-- rarer ores gain at least as much as commoner ones, and the rarest always gains
				local prev, top = 0, 0
				for o = 1, #Rarity.List do
					local gain = byOrder[o]
					if gain then
						T.truthy(gain >= prev - EPS, `{zone.Id} rarity {o} gains at least as much`)
						prev = gain
						top = o
					end
				end
				if top >= order("Rare") and (byOrder[1] or byOrder[2]) then
					T.truthy(byOrder[top] > 1, zone.Id .. " the rarest ores get more likely")
				end
			end
		end
		-- Deep Hollow (the end game, mostly Rare+ already): luck still matters a lot
		local plain = BoostConfig.zoneOdds("DeepHollow", 1)
		local hexa = BoostConfig.zoneOdds("DeepHollow", 2.5)
		local capped = BoostConfig.zoneOdds("DeepHollow", StatConfig.MaxOreLuck)
		local mythic, mythicHexa = rarityShare(plain, "Mythic"), rarityShare(hexa, "Mythic")
		-- without luck: exactly the map weights (the Mythic share of Deep Hollow's weights, ~0.16 %)
		local deepTotal, deepMythic = 0, 0
		for oreId, weight in WorldLayout.ZoneById.DeepHollow.Ores do
			deepTotal += weight
			if OreData.ById[oreId].Rarity == "Mythic" then
				deepMythic += weight
			end
		end
		T.truthy(deepMythic > 0, "Deep Hollow has Mythic ores")
		T.near(mythic, deepMythic / deepTotal, 1e-12, "Mythic share without luck")
		T.truthy(mythicHexa > 3 * mythic, "Hexa Lucky: Mythic more than x3")
		T.truthy(rarityShare(capped, "Mythic") > 5 * mythic, "at the luck cap: Mythic more than x5")
		T.truthy(rarityShare(hexa, "Legendary") > 2 * rarityShare(plain, "Legendary"), "Legendary more than x2")
		T.truthy(chanceOf(hexa, "Heartstone") > 3 * chanceOf(plain, "Heartstone"), "Heartstone more than x3")
		-- the factors BoostConfig's header quotes for Deep Hollow (change the
		-- comment with these when the map weights change)
		local deepShares = BoostConfig.rarityShares(WorldLayout.ZoneById.DeepHollow.Ores, 1)
		local deepHexa = BoostConfig.rarityShares(WorldLayout.ZoneById.DeepHollow.Ores, 2.5)
		T.near(deepHexa.Mythic / deepShares.Mythic, 3.8, 0.05, "header: Mythic about x3.8")
		T.near(deepHexa.Legendary / deepShares.Legendary, 2.4, 0.05, "header: Legendary about x2.4")
		-- the Quarry's Bronze (its only Rare+ ore) is exactly x2.5 against the commons
		local quarryRare = {}
		for oreId in WorldLayout.ZoneById.Quarry.Ores do
			if BoostConfig.isLuckyOre(oreId) then
				table.insert(quarryRare, oreId)
			end
		end
		T.eq(table.concat(quarryRare, ","), "Bronze", "the Quarry's only Rare+ ore")
		local quarry = BoostConfig.zoneOdds("Quarry", 2.5)
		local q1 = BoostConfig.zoneOdds("Quarry", 1)
		T.truthy(chanceOf(q1, "Bronze") > 0 and chanceOf(q1, "Coal") > 0, "both in the Quarry")
		T.near((chanceOf(quarry, "Bronze") / chanceOf(quarry, "Coal")) / (chanceOf(q1, "Bronze") / chanceOf(q1, "Coal")), 2.5, 1e-9)
		-- rarityShares / rareShare agree with the odds
		local shares = BoostConfig.rarityShares(WorldLayout.ZoneById.DeepHollow.Ores, 2.5)
		T.near(shares.Mythic, mythicHexa, EPS)
		T.near(
			BoostConfig.rareShare(WorldLayout.ZoneById.DeepHollow.Ores, 2.5),
			1 - rarityShare(hexa, "Uncommon") - rarityShare(hexa, "Common"),
			EPS
		)
		-- rolls: luck 1 = the plain weights
		local weights = { Coal = 1, Gold = 1 }
		T.eq(BoostConfig.rollOre(weights, 1, 0.49), "Coal")
		T.eq(BoostConfig.rollOre(weights, 1, 0.51), "Gold")
		T.eq(BoostConfig.rollOre(weights, 3, 0.26), "Gold", "Gold (Rare) weighs 3 of 4 with luck 3")
		T.eq(BoostConfig.rollOre({}, 2, 0.5), nil)
		T.eq(BoostConfig.rollOre({ Unobtainium = 3 }, 2, 0.5), nil, "unknown ores skipped")
	end)

	-- a scripted random(): the values in order, counting the calls
	local function scripted(values: { number }): (() -> number, () -> number)
		local calls = 0
		return function(): number
			calls += 1
			return values[calls] or 0.5
		end, function(): number
			return calls
		end
	end

	-- rolls a rock's ore from plain odds, then lets luck upgrade it: N samples
	local function sample(zoneId: string, luck: number, n: number): { [string]: number }
		local weights = WorldLayout.ZoneById[zoneId].Ores
		local base = BoostConfig.zoneOdds(zoneId, 1)
		local counts: { [string]: number } = {}
		for _ = 1, n do
			local roll = math.random()
			local rolled = base[#base].Ore
			local acc = 0
			for _, line in base do
				acc += line.Chance
				if roll < acc then
					rolled = line.Ore
					break
				end
			end
			local ore = BoostConfig.upgradeOre(weights, luck, rolled, math.random)
			counts[ore] = (counts[ore] or 0) + 1
		end
		return counts
	end

	T.test("Step67: ore luck only upgrades: growing ores never change, the result matches oreOdds exactly", function()
		local caves = WorldLayout.ZoneById.EmberCaves.Ores
		local deep = WorldLayout.ZoneById.DeepHollow.Ores
		-- an ore whose share grows is kept, without a roll
		for _, luck in { 1.05, 2.5, 4 } do
			for _, line in BoostConfig.gains(caves, luck) do
				local random, calls = scripted({ 0, 0, 0 })
				T.eq(BoostConfig.upgradeOre(caves, luck, line.Ore, random), line.Ore, line.Ore .. " stays")
				T.eq(calls(), 0, "no roll for a growing ore")
				T.eq(BoostConfig.upgradeChance(caves, luck, line.Ore), 0)
			end
		end
		T.truthy(#BoostConfig.gains(caves, 2.5) > 0)
		-- a dropping ore: upgraded below the chance 1 - p'/p, kept above it
		local plain, lucky = BoostConfig.zoneOdds("EmberCaves", 1), BoostConfig.zoneOdds("EmberCaves", 2.5)
		local chance = BoostConfig.upgradeChance(caves, 2.5, "Iron")
		T.near(chance, 1 - chanceOf(lucky, "Iron") / chanceOf(plain, "Iron"), 1e-12, "1 - p'/p")
		T.near(BoostConfig.upgradeChance(caves, 2.5), chance, 1e-12, "no ore = a lower (x1) ore")
		T.near(BoostConfig.keepChance(caves, 2.5, "Iron"), 1 - chance, 1e-12)
		local random, calls = scripted({ chance + 1e-6 })
		T.eq(BoostConfig.upgradeOre(caves, 2.5, "Iron", random), "Iron", "above the chance: kept")
		T.eq(calls(), 1)
		random, calls = scripted({ chance * 0.5, 0 })
		local upgraded = BoostConfig.upgradeOre(caves, 2.5, "Iron", random)
		T.truthy(BoostConfig.isLuckyOre(upgraded), "below the chance: a Rare+ ore")
		T.eq(calls(), 2)
		random = scripted({ 0, 0.999999 })
		T.eq(BoostConfig.upgradeOre(caves, 2.5, "Iron", random), "Diamond", "the rarest pick is last")
		-- Deep Hollow: even a Rare ore gives way, and only ever to a rarer one
		local goldChance = BoostConfig.upgradeChance(deep, 2.5, "Gold")
		T.truthy(goldChance > 0, "Gold (Rare) can be upgraded in Deep Hollow")
		for _, line in BoostConfig.gains(deep, 2.5) do
			T.truthy(order(OreData.ById[line.Ore].Rarity) > order("Rare"), line.Ore .. " is rarer than Gold")
		end
		for _, roll in { 0, 0.3, 0.7, 0.999999 } do
			random = scripted({ 0, roll })
			local target = BoostConfig.upgradeOre(deep, 2.5, "Gold", random)
			T.truthy(order(OreData.ById[target].Rarity) > order("Rare"), "Gold -> " .. target)
		end
		-- no luck, no Rare+ ores, or an ore that isn't in the zone: kept, no roll
		random, calls = scripted({ 0, 0 })
		T.eq(BoostConfig.upgradeOre(caves, 1, "Iron", random), "Iron")
		T.eq(BoostConfig.upgradeOre(WorldLayout.ZoneById.Outcrops.Ores, 4, "Coal", random), "Coal")
		T.eq(BoostConfig.upgradeOre(caves, 4, "Coal", random), "Coal", "Coal isn't a Caves ore")
		T.eq(calls(), 0)
		T.eq(BoostConfig.upgradeChance(WorldLayout.ZoneById.Outcrops.Ores, 4), 0)
		T.eq(#BoostConfig.gains(WorldLayout.ZoneById.Outcrops.Ores, 4), 0)
		-- exact: rock ores rolled with the plain weights, then upgraded, give oreOdds(weights, luck)
		for _, zone in WorldLayout.Zones do
			local base = BoostConfig.zoneOdds(zone.Id, 1)
			if #base == 0 then
				continue
			end
			for _, luck in { 1.05, 1.5, 2.5, 4 } do
				local gains = BoostConfig.gains(zone.Ores, luck)
				local totalGain = sum(gains, "Chance")
				local final: { [string]: number } = {}
				local moved = 0
				for _, line in base do
					local keep = BoostConfig.keepChance(zone.Ores, luck, line.Ore)
					final[line.Ore] = line.Chance * keep
					moved += line.Chance * (1 - keep)
				end
				T.near(moved, totalGain, 1e-12, `{zone.Id}: what drops is what grows at luck {luck}`)
				for _, line in gains do
					final[line.Ore] += moved * line.Chance / totalGain
				end
				for _, line in BoostConfig.zoneOdds(zone.Id, luck) do
					T.near(final[line.Ore], line.Chance, 1e-12, `{zone.Id} {line.Ore} at luck {luck}`)
				end
			end
		end
		-- and the same by sampling (seeded, 100k chunks each)
		math.randomseed(12345)
		local N = 100000
		local counts = sample("EmberCaves", 2.5, N)
		for _, line in BoostConfig.zoneOdds("EmberCaves", 2.5) do
			T.near((counts[line.Ore] or 0) / N, line.Chance, 0.006, "sampled " .. line.Ore)
		end
		counts = sample("DeepHollow", 2.5, N)
		local byRarity: { [string]: number } = {}
		for oreId, n in counts do
			local rarity = OreData.ById[oreId].Rarity
			byRarity[rarity] = (byRarity[rarity] or 0) + n
		end
		local deepOdds = BoostConfig.zoneOdds("DeepHollow", 2.5)
		for _, info in Rarity.List do
			local expected = rarityShare(deepOdds, info.Id)
			local tolerance = if info.Id == "Mythic" then 0.0012 else 0.006
			T.near((byRarity[info.Id] or 0) / N, expected, tolerance, "Deep Hollow sampled " .. info.Id)
		end
	end)

	T.test("Step67: luck cards show the new odds before any buy (Hexa Lucky, Lucky, Prospector, Starbreaker)", function()
		local context = { BlasterLevel = 5, Vip = false, OreLuckPct = 0, OreLuckMult = 1, ArtifactPct = 0 }
		-- Hexa Lucky
		local hexa = BoostConfig.preview(context, { OreLuckMult = BoostConfig.Kinds.HexaLucky.Mult })
		T.eq(hexa.LuckBefore, 1)
		T.near(hexa.LuckAfter, 2.5, EPS)
		local zones = {}
		for _, effect in hexa.Zones do
			zones[effect.Zone] = effect
		end
		T.truthy(zones.DeepHollow, "blaster 5 mines Deep Hollow")
		local mythic
		for _, line in zones.DeepHollow.Rarities do
			if line.Rarity == "Mythic" then
				mythic = line
			end
		end
		T.truthy(mythic and mythic.After > 3 * mythic.Before, "the card shows Mythic 0.17 % -> 0.59 %")
		T.near(mythic.Before, rarityShare(BoostConfig.zoneOdds("DeepHollow", 1), "Mythic"), EPS)
		T.near(mythic.After, rarityShare(BoostConfig.zoneOdds("DeepHollow", 2.5), "Mythic"), EPS)
		for _, line in hexa.Artifacts do
			T.eq(line.Before, line.After, "Hexa Lucky doesn't touch artifacts")
		end
		-- Hexa Lucky while it runs: the same odds (it only adds time)
		local running = BoostConfig.preview({ BlasterLevel = 5, OreLuckPct = 0, OreLuckMult = 2.5, ArtifactPct = 0 }, { OreLuckMult = 2.5 })
		T.eq(running.LuckBefore, running.LuckAfter)
		-- the enchants: what the next tier adds once slotted
		local enchants: any = { Owned = {}, Slots = { "", "", "", "" } }
		T.near(EnchantConfig.nextDelta(enchants, 5, "Lucky").OreLuckPct, 0.15, EPS, "Lucky I")
		enchants.Owned.Lucky = 1
		T.near(EnchantConfig.nextDelta(enchants, 5, "Lucky").OreLuckPct, 0.3, EPS, "Lucky II, not slotted: all of it")
		EnchantConfig.setSlot(enchants, 5, 1, "Lucky")
		T.near(EnchantConfig.nextDelta(enchants, 5, "Lucky").OreLuckPct, 0.15, EPS, "Lucky II over a slotted Lucky I")
		enchants.Owned.Lucky = 3
		T.eq(next(EnchantConfig.nextDelta(enchants, 5, "Lucky")), nil, "top tier: nothing more")
		local lucky = BoostConfig.preview(context, EnchantConfig.nextDelta({ Owned = {}, Slots = {} }, 5, "Lucky"))
		T.near(lucky.LuckAfter, 1.15, EPS)
		local prospector = BoostConfig.preview(context, EnchantConfig.nextDelta({ Owned = {}, Slots = {} }, 5, "Prospector"))
		T.eq(prospector.LuckAfter, 1, "Prospector: artifacts only")
		for _, line in prospector.Artifacts do
			T.near(line.After, line.Before * 1.25, EPS, line.Zone .. " artifact chance +25 %")
			T.near(line.Before, ArtifactConfig.rockChance(line.Zone), EPS)
		end
		local star = BoostConfig.preview(context, EnchantConfig.nextDelta({ Owned = {}, Slots = {} }, 5, "Starbreaker"))
		T.near(star.LuckAfter, 1.75, EPS)
		T.truthy(star.Artifacts[1].After > star.Artifacts[1].Before)
		-- a capped player sees no change (what the game would apply)
		local capped = BoostConfig.preview(
			{ BlasterLevel = 5, OreLuckPct = 1.5, OreLuckMult = 1, ArtifactPct = 3 },
			{ OreLuckPct = 0.75, ArtifactPct = 0.5 }
		)
		T.eq(capped.LuckBefore, capped.LuckAfter)
		T.eq(capped.Artifacts[1].Before, capped.Artifacts[1].After)
		-- every odds booster is flagged, shows a change, and is a paid random item for Robux
		for _, enchant in EnchantConfig.List do
			local odds = false
			for stat in enchant.Effects do
				odds = odds or EnchantConfig.OddsStats[stat] == true
			end
			T.eq(enchant.OddsBoost == true, odds, enchant.Id .. " OddsBoost")
			if enchant.OddsBoost then
				local view = BoostConfig.preview(context, EnchantConfig.nextDelta({ Owned = {}, Slots = {} }, 5, enchant.Id))
				local changed = view.LuckAfter > view.LuckBefore
				for _, line in view.Artifacts do
					changed = changed or line.After > line.Before
				end
				T.truthy(changed, enchant.Id .. " card shows new odds")
				T.truthy(EnchantConfig.isPaidRandom(enchant.Id, "Robux"), enchant.Id .. " for Robux is paid random")
				T.eq(EnchantConfig.isPaidRandom(enchant.Id, "Coins"), MonetizationConfig.coinsBuyable())
			else
				T.falsy(EnchantConfig.isPaidRandom(enchant.Id, "Robux"), enchant.Id .. " changes no odds")
			end
			local product = if enchant.Product then MonetizationConfig.get(enchant.Product) else nil
			if product then
				T.eq(product.PaidRandom == true, enchant.OddsBoost == true, enchant.Id .. " product PaidRandom")
			end
		end
		T.truthy(EnchantConfig.isPaidRandom("Nope", "Coins"), "unknown = strict")
		-- restricted players: no Robux Starbreaker; Heartfire (no odds) and coin buys stay
		local none: any = { Owned = {}, Slots = {} }
		local _, why = EnchantConfig.quote(none, "Starbreaker", "Robux", 1, true)
		T.eq(why, "Restricted")
		_, why = EnchantConfig.quote(none, "Starbreaker", "Robux", 1, false)
		T.eq(why, "Robux")
		_, why = EnchantConfig.quote(none, "Heartfire", "Robux", 1, true)
		T.eq(why, "Robux", "Heartfire changes no odds")
		T.eq(EnchantConfig.quote(none, "Starbreaker", "Coins", 1, true), 1e12, "coins can't be bought with Robux")
		T.eq(MonetizationConfig.promptStatus("EnchantStarbreaker", true), "Restricted")
		T.eq(MonetizationConfig.promptStatus("EnchantHeartfire", true), "ComingSoon")
		T.truthy(EnchantConfig.Reasons.Restricted)
	end)

	---------------------------------------------------------------- wheel

	T.test("Step67: the daily wheel: 8 segments, exact odds, income-scaled coins", function()
		T.eq(#WheelConfig.Segments, 8)
		T.near(sum(WheelConfig.Segments, "Odds"), 1, EPS, "odds sum to 1")
		T.near(sum(WheelConfig.odds(), "Chance"), 1, EPS)
		local kinds, colors = {}, {}
		local Color3 = (require("@lune/roblox") :: any).Color3
		-- the lobby wheel's rainbow (src/server/World/Lobby/Districts/Wheel.luau SEGMENTS)
		local lobby = {
			Color3.fromRGB(130, 16, 26),
			Color3.fromRGB(150, 70, 8),
			Color3.fromRGB(150, 120, 8),
			Color3.fromRGB(84, 126, 10),
			Color3.fromRGB(14, 110, 46),
			Color3.fromRGB(8, 112, 122),
			Color3.fromRGB(18, 60, 150),
			Color3.fromRGB(56, 28, 150),
			Color3.fromRGB(100, 24, 140),
			Color3.fromRGB(140, 24, 90),
		}
		for i, segment in WheelConfig.Segments do
			T.eq(segment.Index, i)
			T.truthy(segment.Odds > 0)
			kinds[segment.Kind] = true
			local key = tostring(segment.Color)
			T.falsy(colors[key], "distinct colors")
			colors[key] = true
			local matches = false
			for _, color in lobby do
				if color == segment.Color then
					matches = true
				end
			end
			T.truthy(matches, segment.Id .. " uses a lobby wheel color")
		end
		for _, kind in { "Coins", "Boost", "Capsule", "Ore", "Shards" } do
			T.truthy(kinds[kind], "a " .. kind .. " prize")
		end
		T.eq(WheelConfig.ById.TripleLucky.Seconds, 600)
		T.eq(WheelConfig.ById.HexaLucky.Seconds, 600)
		T.eq(WheelConfig.ById.StoneCapsule.Capsule, "Stone")
		T.eq(WheelConfig.ById.CrystalCapsule.Capsule, "Crystal")
		-- pick walks the segments in order
		T.eq(WheelConfig.pick(0).Index, 1)
		T.eq(WheelConfig.pick(0.2999).Index, 1)
		T.eq(WheelConfig.pick(0.3001).Index, 2)
		T.eq(WheelConfig.pick(0.99999).Index, 8)
		T.eq(WheelConfig.pick(1).Index, 8)
		-- coins: 120 s / 600 s of podium income, at least 500 / 2500
		T.eq(WheelConfig.coins(WheelConfig.ById.Coins, 0), 500)
		T.eq(WheelConfig.coins(WheelConfig.ById.Coins, 100), 12000)
		T.eq(WheelConfig.coins(WheelConfig.ById.BigCoins, 1), 2500)
		T.eq(WheelConfig.coins(WheelConfig.ById.BigCoins, 100), 60000)
		T.eq(WheelConfig.coins(WheelConfig.ById.Shards, 100), 0)
		-- timer
		T.truthy(WheelConfig.ready(0, NOW))
		T.truthy(WheelConfig.ready(0 / 0, NOW), "broken = ready")
		T.falsy(WheelConfig.ready(NOW + 10, NOW))
		T.eq(WheelConfig.secondsLeft(NOW + 10, NOW), 10)
		T.eq(WheelConfig.CooldownSeconds, 86400)
		-- the ore prize: a dirty Rare+ ore, a step up from the best one found, from mines they can reach
		local day1 = { BlasterLevel = 1, BestIncome = OreData.ById.Copper.Income }
		local odds1 = WheelConfig.oreOdds(day1)
		T.near(sum(odds1, "Chance"), 1, EPS, "nested odds sum to 1")
		T.eq(#odds1, 1)
		T.eq(odds1[1].Ore, "Bronze", "a day-1 player wins a Bronze chunk (the Quarry's Rare ore)")
		T.eq(WheelConfig.pickOre(0, day1), "Bronze")
		T.eq(WheelConfig.pickOre(1, day1), "Bronze")
		T.eq(WheelConfig.OrePrize.MinIncome, OreData.ById.Bronze.Income)
		T.truthy(OreData.ById.Bronze.Income * 10 > WheelConfig.ById.Coins.Min, "on a podium it beats the plain Coins prize within seconds")
		-- nothing found yet: Bronze too
		T.eq(WheelConfig.oreOdds({ BlasterLevel = 1, BestIncome = 0 })[1].Ore, "Bronze")
		-- mid game (blaster 3, Bronze found): Ember Caves Rare+ ores up to 3x Bronze, the best the least likely
		local mid = { BlasterLevel = 3, BestIncome = OreData.ById.Bronze.Income }
		local seen = {}
		local midOdds = WheelConfig.oreOdds(mid)
		T.eq(#midOdds, 3)
		for _, line in midOdds do
			seen[line.Ore] = true
			T.truthy(OreData.ById[line.Ore].Income <= OreData.ById.Bronze.Income * 3)
		end
		T.truthy(seen.Silver and seen.Gold and seen.Jade, "mid game prizes")
		-- the Grotto's own ores (in no zone a blaster-3 player reaches without the pass)
		local reach3: { [string]: boolean } = {}
		for _, zone in BoostConfig.minableZones(3, false) do
			for oreId in zone.Ores do
				reach3[oreId] = true
			end
		end
		local grottoOnly: { [string]: boolean } = {}
		local grottoBest = 0
		for oreId in WorldLayout.ZoneById.Grotto.Ores do
			if not reach3[oreId] then
				grottoOnly[oreId] = true
				grottoBest = math.max(grottoBest, OreData.ById[oreId].Income)
			end
		end
		T.truthy(next(grottoOnly), "the Grotto has ores of its own at blaster 3")
		for oreId in grottoOnly do
			T.falsy(seen[oreId], `no Grotto ore ({oreId}) without VIP`)
		end
		-- a VIP who found the Grotto's best ore gets the same odds as anyone (no paid odds booster)
		local vip: any = { BlasterLevel = 3, BestIncome = grottoBest, Vip = true }
		local plainCtx = { BlasterLevel = 3, BestIncome = grottoBest }
		local vipOdds, plainOdds = WheelConfig.oreOdds(vip), WheelConfig.oreOdds(plainCtx)
		T.eq(#vipOdds, #plainOdds, "the same list with or without the pass")
		for i, line in vipOdds do
			T.eq(line.Ore, plainOdds[i].Ore)
			T.near(line.Chance, plainOdds[i].Chance, EPS)
			T.falsy(grottoOnly[line.Ore], "never one of the Grotto's own ores: " .. line.Ore)
		end
		T.eq(midOdds[3].Ore, "Jade", "the best one last")
		T.truthy(midOdds[3].Chance < midOdds[1].Chance, "the best one is the least likely")
		-- a deep ore never comes before the blaster can mine its zone
		for level = 1, 10 do
			for best = 0, 6 do
				local context = { BlasterLevel = level, BestIncome = 10 ^ best }
				for _, line in WheelConfig.oreOdds(context) do
					local reachable = false
					for _, zone in BoostConfig.minableZones(level, false) do
						if zone.Ores[line.Ore] then
							reachable = true
						end
					end
					T.truthy(reachable, `{line.Ore} reachable at blaster {level}`)
					T.truthy(BoostConfig.isLuckyOre(line.Ore), line.Ore .. " is Rare or rarer")
					T.truthy(
						OreData.ById[line.Ore].Income <= math.max(WheelConfig.OrePrize.MinIncome, 10 ^ best * 3),
						line.Ore .. " capped"
					)
				end
			end
		end
		T.eq(WheelConfig.bestIncome({ Coal = true, Gold = true, Fake = true }), OreData.ById.Gold.Income)
		T.eq(WheelConfig.bestIncome("junk"), 0)
		-- a full pen pays the prize's expected raw value: the coins don't tell which ore it was
		T.eq(WheelConfig.oreFallbackCoins(day1), ItemData.value("Raw", "Bronze"))
		local expected = 0
		for _, line in midOdds do
			expected += line.Chance * ItemData.value("Raw", line.Ore)
		end
		T.eq(WheelConfig.oreFallbackCoins(mid), math.floor(expected + 0.5))
		-- a full golem inventory pays a share of the capsule's price, never the whole
		T.eq(WheelConfig.capsuleFallbackCoins("Stone", 1), math.floor(2500 * WheelConfig.FallbackShare))
		T.eq(WheelConfig.capsuleFallbackCoins("Crystal", 10), math.floor((CapsuleConfig.price("Crystal", 1, 10) :: number) * 0.25))
		T.eq(WheelConfig.capsuleFallbackCoins("Royal", 1), math.floor(750000 * 0.25), "Royal counts as Crystal")
		T.truthy(WheelConfig.FallbackShare <= 0.3)
		-- players who can't buy any capsule get coins instead of Triple Lucky (same place and odds)
		local restricted = WheelConfig.segments(true)
		T.eq(#restricted, 8)
		T.near(sum(WheelConfig.odds(true), "Chance"), 1, EPS)
		T.eq(restricted[2].Id, "TripleLuckyCoins")
		T.eq(restricted[2].Kind, "Coins")
		T.eq(restricted[2].Odds, WheelConfig.ById.TripleLucky.Odds)
		T.eq(restricted[2].Color, WheelConfig.ById.TripleLucky.Color)
		T.eq(WheelConfig.pick(0.35, true).Id, "TripleLuckyCoins")
		T.eq(WheelConfig.pick(0.35, false).Id, "TripleLucky")
		T.eq(WheelConfig.pick(0.35).Id, "TripleLucky")
		T.truthy(WheelConfig.coins(restricted[2], 100) > 0)
		for i = 1, 8 do
			if i ~= 2 then
				T.eq(restricted[i], WheelConfig.Segments[i], "the other segments stay")
			end
		end
		T.truthy(WheelConfig.ClientCooldown >= 1 and WheelConfig.ResultTimeout >= 5)
	end)

	---------------------------------------------------------------- artifacts + story

	T.test("Step67: 24 artifacts in 4 collections, rarer deeper, odds sum to 1", function()
		T.eq(#ArtifactConfig.List, 24)
		T.eq(#ArtifactConfig.Collections, 4)
		local names = {}
		for _, collection in ArtifactConfig.Collections do
			T.eq(#ArtifactConfig.ByCollection[collection.Id], 6, collection.Id .. " has 6")
			T.truthy(ArtifactConfig.PodiumSkins[collection.Reward.PodiumSkin], collection.Id .. " skin")
			T.truthy(#collection.Reward.Title > 0)
			T.truthy(collection.Reward.Bonus.Value > 0)
			local chapter = StoryConfig.ByCollection[collection.Id]
			T.truthy(chapter, collection.Id .. " unlocks a chapter")
			T.truthy(#chapter.Pages >= 3 and #chapter.Pages <= 5, collection.Id .. " chapter has 3-5 pages")
			for _, page in chapter.Pages do
				T.truthy(#page.Title > 0 and #page.Text > 20)
				T.truthy(#page.Text <= 260, "short journal pages")
			end
		end
		T.eq(#StoryConfig.Chapters, #ArtifactConfig.Collections, "one chapter per collection")
		T.truthy(#StoryConfig.Prologue.Pages >= 1, "a prologue")
		for _, artifact in ArtifactConfig.List do
			T.falsy(names[artifact.Name], "unique name " .. artifact.Name)
			names[artifact.Name] = true
			T.truthy(ArtifactConfig.Shapes[artifact.Shape])
			T.eq(typeof(artifact.Primary), "Color3")
			T.truthy(#artifact.Lore > 10)
			T.truthy(ArtifactConfig.DuplicateShards[artifact.Rarity], "duplicate shards for " .. artifact.Rarity)
		end
		-- the drop chance comes from BlasterData.Rocks.ArtifactChance and grows deeper
		T.truthy(ArtifactConfig.rockChance("DeepHollow") > ArtifactConfig.rockChance("EmberCaves"))
		T.truthy(ArtifactConfig.rockChance("EmberCaves") > ArtifactConfig.rockChance("Quarry"))
		T.truthy(ArtifactConfig.rockChance("Quarry") > ArtifactConfig.rockChance("Outcrops"))
		local function meanOrder(zoneId: string): number
			local total = 0
			for _, line in ArtifactConfig.odds(zoneId) do
				total += line.Chance * order(ArtifactConfig.ById[line.Artifact].Rarity)
			end
			return total
		end
		for _, zone in WorldLayout.Zones do
			local list = ArtifactConfig.odds(zone.Id)
			T.near(sum(list, "Chance"), 1, EPS, zone.Id .. " artifact odds sum to 1")
		end
		T.near(sum(ArtifactConfig.odds("SomeNewFloor"), "Chance"), 1, EPS, "an unknown zone still works")
		T.truthy(meanOrder("DeepHollow") > meanOrder("EmberCaves"), "rarer deeper")
		T.truthy(meanOrder("EmberCaves") > meanOrder("Quarry"), "rarer deeper")
		T.truthy(meanOrder("Quarry") > meanOrder("Outcrops"), "rarer deeper")
		-- the Mythic only deep down
		local function chanceOf(zoneId: string, id: string): number
			for _, line in ArtifactConfig.odds(zoneId) do
				if line.Artifact == id then
					return line.Chance
				end
			end
			return 0
		end
		T.eq(chanceOf("Quarry", "HeartstoneFragment"), 0)
		T.truthy(chanceOf("DeepHollow", "HeartstoneFragment") > 0)
		T.eq(ArtifactConfig.pick("Quarry", 0), ArtifactConfig.odds("Quarry")[1].Artifact)
		T.truthy(ArtifactConfig.pick("DeepHollow", 0.999999))
	end)

	T.test("Step67: finding artifacts completes collections and gives their rewards", function()
		local artifacts: any = { Found = {}, Chapters = {} }
		local list = ArtifactConfig.ByCollection.CrownOfKaldrum
		for i, artifact in list do
			local count, isNew, completed = ArtifactConfig.add(artifacts, artifact.Id)
			T.eq(count, 1)
			T.truthy(isNew)
			if i < #list then
				T.eq(completed, nil, "not complete yet")
			else
				T.eq(completed, "CrownOfKaldrum", "the last one completes it")
			end
		end
		local count, isNew, completed = ArtifactConfig.add(artifacts, list[1].Id)
		T.eq(count, 2)
		T.falsy(isNew)
		T.eq(completed, nil, "a duplicate never completes again")
		T.eq(ArtifactConfig.add(artifacts, "Nope"), 0)
		T.truthy(ArtifactConfig.isComplete(artifacts, "CrownOfKaldrum"))
		T.falsy(ArtifactConfig.isComplete(artifacts, "RoyalRailway"))
		T.eq(ArtifactConfig.uniqueCount(artifacts), 6)
		T.eq(#ArtifactConfig.completed(artifacts), 1)
		T.eq(ArtifactConfig.titles(artifacts)[1], "Heir of Kaldrum")
		local stats = ArtifactConfig.stats(artifacts)
		T.near(stats.IncomePct, 0.05, EPS)
		artifacts.Found[list[2].Id] = 2 ^ 40
		T.eq(ArtifactConfig.countOf(artifacts, list[2].Id), ArtifactConfig.MaxCount, "counts are capped")
	end)

	---------------------------------------------------------------- leaderboards

	T.test("Step67: 4 leaderboards with versioned stores", function()
		T.eq(#LeaderboardConfig.Boards, 4)
		local titles = { "MONEY / SEC", "TOTAL EARNED", "ARTIFACTS", "HOURS PLAYED" }
		local stores = {}
		for i, board in LeaderboardConfig.Boards do
			T.eq(board.Index, i)
			T.eq(board.Title, titles[i])
			T.truthy(board.Store:match("_v%d+$"), board.Store .. " is versioned")
			T.falsy(stores[board.Store], "unique store")
			stores[board.Store] = true
			T.eq(LeaderboardConfig.ByIndex[i], board)
		end
		T.eq(LeaderboardConfig.RefreshSeconds, 60)
		T.eq(LeaderboardConfig.TopCount, 10, "the side menu panel")
		T.eq(LeaderboardConfig.BoardRows, 5, "the lobby boards: readable on phones")
		T.truthy(LeaderboardConfig.BoardRows <= LeaderboardConfig.TopCount)
	end)

	T.test("Step67: leaderboard encode/decode round-trips big numbers and keeps their order", function()
		local values = {
			0.5,
			1,
			1.5,
			9.99,
			10,
			123.456,
			999,
			1000,
			12345.678,
			1e6,
			3.3e9,
			1e12,
			7.77e15,
			1e18,
			1e18 * (1 + 1e-9),
			4.2e21,
			1e30,
			1e100,
			1e300,
		}
		for _, boardId in { "MoneyPerSec", "TotalEarned" } do
			local last = -1
			for _, v in values do
				local stored = LeaderboardConfig.encode(boardId, v)
				T.eq(stored, math.floor(stored), "whole number")
				T.truthy(stored >= 0 and stored < 2 ^ 53, "fits an OrderedDataStore")
				T.truthy(stored > last, `{boardId}: {v} sorts above the smaller value`)
				last = stored
				local back = LeaderboardConfig.decode(boardId, stored)
				T.truthy(math.abs(back - v) <= 1e-9 * math.max(1, v), `{boardId} round trip {v} -> {back}`)
			end
			T.eq(LeaderboardConfig.encode(boardId, 0), 0)
			T.eq(LeaderboardConfig.encode(boardId, -5), 0)
			T.eq(LeaderboardConfig.encode(boardId, 0 / 0), 0)
			T.truthy(LeaderboardConfig.encode(boardId, math.huge) < 2 ^ 53, "infinity is capped")
			T.eq(LeaderboardConfig.decode(boardId, 0), 0)
		end
		T.eq(LeaderboardConfig.encode("Artifacts", 37.9), 37)
		T.eq(LeaderboardConfig.decode("Artifacts", 37), 37)
		T.eq(LeaderboardConfig.encode("HoursPlayed", 3 * 3600 + 59), 180, "whole minutes")
		T.eq(LeaderboardConfig.decode("HoursPlayed", 180), 3 * 3600)
		T.truthy(LeaderboardConfig.encode("HoursPlayed", 61) > LeaderboardConfig.encode("HoursPlayed", 59))
		T.eq(LeaderboardConfig.format("HoursPlayed", 3 * 3600 + 1800), "3.5 h")
		T.eq(LeaderboardConfig.format("MoneyPerSec", 1300), "+$1.3K/s")
		T.eq(LeaderboardConfig.format("TotalEarned", 4.5e6), "$4.5M")
		T.eq(LeaderboardConfig.format("Artifacts", 1234), "1,234")
		T.eq(LeaderboardConfig.encode("Nope", 5), 0)
		-- the board shows what the player has: no off-by-one from the log encoding
		for _, boardId in { "MoneyPerSec", "TotalEarned" } do
			for _, v in { 1, 7, 25, 99, 100, 250, 999, 1000, 1001, 4321, 1e6, 3.2e6, 123456789, 1e12, 2.5e15, 1e18, 4.2e21 } do
				local back = LeaderboardConfig.decode(boardId, LeaderboardConfig.encode(boardId, v))
				T.eq(back, v, `{boardId} {v} decodes to itself`)
				T.eq(LeaderboardConfig.format(boardId, back), LeaderboardConfig.format(boardId, v), `{boardId} {v} shows the same`)
			end
			-- snapping keeps the order
			local last = -1
			for v = 0, 3000, 7 do
				local back = LeaderboardConfig.decode(boardId, LeaderboardConfig.encode(boardId, v + 0.37))
				T.truthy(back >= last, "order kept")
				last = back
			end
		end
	end)

	---------------------------------------------------------------- monetization

	T.test("Step67: every Robux item is a placeholder and never live", function()
		local required = {
			BigPass = 560,
			Podiums = 100,
			OfflineExtension = 99,
			TrainExpress = 199,
			RoyalCapsule1 = 49,
			EnchantHeartfire = 20,
			EnchantStarbreaker = 20,
		}
		for key, robux in required do
			local product = MonetizationConfig.get(key)
			T.truthy(product, key)
			T.eq(product.Robux, robux, key .. " price")
		end
		for _, key in
			{
				"RoyalCapsule3",
				"RoyalCapsule10",
				"TripleLucky15",
				"TripleLucky60",
				"HexaLucky15",
				"HexaLucky60",
				"CoinsSmall",
				"CoinsMedium",
				"CoinsLarge",
			}
		do
			T.truthy(MonetizationConfig.get(key), key)
		end
		local big = MonetizationConfig.get("BigPass")
		-- the pass opens the Grotto's odds: its text says them in numbers, from the map weights
		local grotto = WorldLayout.ZoneById.Grotto
		local gtotal = 0
		for _, weight in grotto.Ores do
			gtotal += weight
		end
		for oreId, weight in grotto.Ores do
			-- a whole percent as a whole number, else one decimal (grottoOddsText)
			local raw = weight / gtotal * 100
			local pct = if math.abs(raw - math.floor(raw + 0.5)) < 1e-9 then tostring(math.floor(raw + 0.5)) else string.format("%.1f", raw)
			T.truthy(big.Description:find(`{pct}% {OreData.ById[oreId].Name}`, 1, true), `BigPass names {oreId} at {pct}%`)
		end
		T.truthy(
			table.find(big.Perks, "Podiums") and table.find(big.Perks, "OfflineExtension"),
			"the big pass has podiums 3-4 and 12 h offline"
		)
		for _, product in MonetizationConfig.List do
			T.eq(product.Id, 0, product.Key .. " is a placeholder")
			T.falsy(MonetizationConfig.isLive(product.Id))
			T.falsy(MonetizationConfig.keyLive(product.Key))
			T.truthy(product.Robux > 0)
			T.eq(MonetizationConfig.Products[product.Key], product)
		end
		T.truthy(MonetizationConfig.isLive(123456))
		T.falsy(MonetizationConfig.isLive(0 / 0))
		T.falsy(MonetizationConfig.isLive("123"))
		T.eq(MonetizationConfig.promptStatus("RoyalCapsule1", false), "ComingSoon")
		T.eq(MonetizationConfig.promptStatus("RoyalCapsule1", true), "Restricted", "paid random + restricted")
		T.eq(MonetizationConfig.promptStatus("EnchantHeartfire", true), "ComingSoon", "not random: policy doesn't matter")
		T.eq(MonetizationConfig.promptStatus("EnchantHeartfire", false, true), "Owned")
		T.eq(MonetizationConfig.promptStatus("HexaLucky15", false, false, true), "Full")
		T.eq(MonetizationConfig.promptStatus("Nope", false), "Unknown")
		for _, status in { "ComingSoon", "Restricted", "Owned", "Full", "Unknown" } do
			T.truthy(MonetizationConfig.StatusText[status], status .. " text")
		end
		T.eq(MonetizationConfig.coinPackAmount("CoinsSmall", 0), 5000)
		T.eq(MonetizationConfig.coinPackAmount("CoinsSmall", 100), 60000)
		T.eq(MonetizationConfig.coinPackAmount("BigPass", 100), nil)
		-- one-time things are game passes (Roblox never sells a pass twice)
		for _, key in { "EnchantHeartfire", "EnchantStarbreaker" } do
			local pass = MonetizationConfig.get(key)
			T.eq(pass.Kind, "GamePass", key .. " is a game pass")
			T.truthy(pass.Enchant, key .. " grants an enchant")
		end
		-- Starbreaker raises ore luck and the artifact chance: an odds booster, so paid random
		T.truthy(MonetizationConfig.get("EnchantStarbreaker").PaidRandom, "Starbreaker is a paid odds booster")
		T.falsy(MonetizationConfig.get("EnchantHeartfire").PaidRandom, "Heartfire changes no odds")
		T.eq(MonetizationConfig.promptStatus("EnchantStarbreaker", true), "Restricted", "hidden where restricted")
		-- every luck product says what it does in numbers
		for _, key in { "HexaLucky15", "HexaLucky60", "EnchantStarbreaker" } do
			T.truthy(MonetizationConfig.get(key).Description:find("new odds shown before buying", 1, true), key .. " promises the odds")
		end
		-- a percent bonus can hit its cap: the pass says where (Hexa's x2.5 never does: MaxOreLuck)
		T.truthy(MonetizationConfig.get("EnchantStarbreaker").Description:find("at most +150%", 1, true), "Starbreaker names the cap")
		T.near((StatConfig.ById.OreLuckPct.Max :: number), 1.5, EPS, "the cap the Starbreaker text names")
		T.truthy(MonetizationConfig.PromptMemorySeconds >= 60, "a Royal prompt remembers the Triple Lucky state it showed")
		for _, product in MonetizationConfig.List do
			if product.Kind == "Product" then
				T.falsy(product.Enchant, product.Key .. ": no one-time item as a developer product")
				T.falsy(product.Perks, product.Key .. ": perks come from passes")
			end
		end
		-- coin packs wait for the owner: off, never offered, coins not buyable
		T.eq(MonetizationConfig.CoinPacksEnabled, false)
		T.falsy(MonetizationConfig.coinsBuyable())
		for _, key in { "CoinsSmall", "CoinsMedium", "CoinsLarge" } do
			T.truthy(MonetizationConfig.get(key).CoinPack)
			T.eq(MonetizationConfig.promptStatus(key, false), "Unknown", key .. " isn't offered")
		end
		MonetizationConfig.CoinPacksEnabled = true
		local ok, err = pcall(function()
			T.truthy(MonetizationConfig.coinsBuyable())
			T.eq(MonetizationConfig.promptStatus("CoinsSmall", false), "ComingSoon")
			T.truthy(CapsuleConfig.isPaidRandom("Stone"), "with coin packs coin capsules are paid random")
			T.truthy(BoostConfig.isPaidRandom("HexaLucky5"))
			T.truthy(CapsuleConfig.allRestricted(true))
		end)
		MonetizationConfig.CoinPacksEnabled = false
		T.truthy(ok, tostring(err))
		T.falsy(CapsuleConfig.isPaidRandom("Stone"))
		T.truthy(CapsuleConfig.isPaidRandom("Royal"))
	end)

	---------------------------------------------------------------- remotes + save

	T.test("Step67: the new remotes", function()
		for _, name in { "GearAction", "EnchantAction", "BoostAction", "CapsuleAction", "GolemAction", "WheelAction", "ArtifactAction" } do
			local limit = Net.Events[name]
			T.truthy(type(limit) == "table" and limit.Rate > 0 and limit.Burst >= 1, name .. " is rate limited")
			T.truthy(limit.Rate <= 4, name .. " is not spammable")
		end
		for _, name in { "ActionResult", "CapsuleResult", "WheelResult", "ArtifactFound", "PurchasePrompt" } do
			T.eq(Net.Events[name], false, name .. " is server -> client")
		end
		-- the 7-day Ember Chest is retired: the EmberChest hook belongs to the wheel alone
		T.eq(Net.Events.DailyClaim, nil)
		T.eq(WheelConfig.Tag, "EmberChest")
	end)

	T.test("Step67: the new save records", function()
		T.eq(DataTemplate.Version, 3, "still version 3")
		T.eq(DataTemplate.CarryLevel, nil, "CarryLevel is gone")
		T.eq(DataTemplate.Daily, nil, "the 7-day chest streak is gone (the wheel replaced it)")
		for _, lineId in GearConfig.LineIds do
			T.eq(DataTemplate.Gear[lineId], 0)
		end
		T.eq(#DataTemplate.Enchants.Slots, EnchantConfig.MaxSlots)
		T.eq(next(DataTemplate.Enchants.Owned), nil)
		T.eq(DataTemplate.Boosts.TripleLuckyUntil, 0)
		T.eq(DataTemplate.Boosts.HexaLuckyUntil, 0)
		T.eq(DataTemplate.Golems.NextId, 1)
		T.eq(DataTemplate.Wheel.NextSpinAt, 0)
		T.eq(next(DataTemplate.Artifacts.Found), nil)
		for _, stat in { "ArtifactsFound", "CapsulesOpened", "WheelSpins", "WheelOres" } do
			T.eq(DataTemplate.Stats[stat], 0)
		end
		-- an old save gets the records from reconcile
		local old = fresh()
		old.Gear, old.Enchants, old.Golems, old.Wheel, old.Artifacts, old.Boosts = nil, nil, nil, nil, nil, nil
		old.Stats.WheelSpins = nil
		ProfileStore.reconcile(old, DataTemplate)
		T.eq(old.Gear.Boots, 0)
		T.eq(#old.Enchants.Slots, 4)
		T.eq(old.Golems.NextId, 1)
		T.eq(old.Stats.WheelSpins, 0)
	end)

	---------------------------------------------------------------- migration

	T.test("Step67 migration: a fresh save is untouched, CarryLevel folds into the Backpack", function()
		local data = fresh()
		local copy = ProfileStore.deepCopy(data)
		local report = Migrations.run(data, NOW)
		T.truthy(deepEqual(data, copy), "fresh save untouched")
		T.eq(report.Moved + report.Dropped, 0)
		for carry, backpack in { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [9] = 4, [-2] = 0 } do
			local save = fresh()
			save.CarryLevel = carry
			Migrations.run(save, NOW)
			T.eq(save.Gear.Backpack, backpack, "CarryLevel " .. carry)
			T.eq(save.CarryLevel, nil, "removed")
			T.eq(ToolData.carryCapacity(math.clamp(carry, 1, 5), false), GearConfig.carryCapacity(save.Gear, false), "same capacity")
		end
		-- paid boost time stacked past MaxStackSeconds (Robux packs, uncapped) is never lost
		local paid = fresh()
		paid.Boosts.HexaLuckyUntil = NOW + 30 * 3600
		paid.Boosts.TripleLuckyUntil = NOW + 9 * 24 * 3600
		Migrations.run(paid, NOW)
		T.eq(paid.Boosts.HexaLuckyUntil, NOW + 30 * 3600, "a 30 h paid boost is kept")
		T.eq(paid.Boosts.TripleLuckyUntil, NOW + 9 * 24 * 3600, "9 days of paid boost are kept")
		T.lt(30 * 24 * 3600, BoostConfig.MaxSavedSeconds, "the save cap is only a junk guard")
		local bought = fresh()
		bought.CarryLevel = 2
		bought.Gear.Backpack = 4
		Migrations.run(bought, NOW)
		T.eq(bought.Gear.Backpack, 4, "the higher one wins")
		local junk = fresh()
		junk.CarryLevel = "lots"
		Migrations.run(junk, NOW)
		T.eq(junk.Gear.Backpack, 0)
		T.eq(junk.CarryLevel, nil)
	end)

	local function junkSave(): { [string]: any }
		local data = fresh()
		data.BlasterLevel = 4 -- 2 enchant slots open
		data.Gear = { Boots = 2.7, HelmetLamp = -1, Backpack = 99, Gloves = 0 / 0, Magnet = "3", Cape = 2 }
		data.Enchants = {
			Owned = { Power = 2.5, Lucky = 0, Midas = 9, Fake = 1, [3] = 1, Heartfire = 1 },
			Slots = { "Power", "Power", "Midas", 5, "x" },
		}
		data.Boosts = { TripleLuckyUntil = NOW + 10 ^ 9, HexaLuckyUntil = -5 }
		data.Golems = {
			Owned = {
				{
					Id = 1,
					Kind = "PebbleGolem",
					Extra = "kept",
					Locked = "yes", -- not a boolean
					Paid = true,
					Junk = { 1 }, -- not a scalar
					[5] = true, -- not a string key
					Long = string.rep("x", 100), -- too long
				},
				{ Id = 1, Kind = "EmberImp" }, -- duplicate id
				{ Id = 2.5, Kind = "EmberImp" },
				{ Id = 3, Kind = "IronGolem" }, -- unknown kind
				"junk",
				{ Id = 7, Kind = "DiamondDuke" },
			},
			Equipped = { 7, 7, 1, 99, "x" },
			NextId = 2,
		}
		data.Wheel = { NextSpinAt = NOW + 10 ^ 9 }
		data.Artifacts = {
			Found = { CrownCoin = 2.9, RoyalSeal = 0, Fake = 3, EmberCrown = 1e9 },
			Chapters = { CrownOfKaldrum = true, RoyalRailway = "yes", Nope = true },
		}
		data.Stats.ArtifactsFound = -3
		data.Stats.CapsulesOpened = 4.6
		data.Stats.WheelSpins = 0 / 0
		data.Stats.WheelOres = "two"
		return data
	end

	T.test("Step67 migration: junk is repaired (known ids, caps, whole levels, finite times)", function()
		local data = junkSave()
		local report = Migrations.run(data, NOW)
		T.truthy(report.Dropped > 0, "repairs counted")
		-- gear
		T.eq(data.Gear.Boots, 2)
		T.eq(data.Gear.HelmetLamp, 0)
		T.eq(data.Gear.Backpack, 99, "a higher level is kept (a newer server may sell it)")
		T.eq(GearConfig.level(data.Gear, "Backpack"), GearConfig.MaxLevel, "readers clamp")
		T.eq(data.Gear.Gloves, 0)
		T.eq(data.Gear.Magnet, 0, "a string level is junk")
		T.eq(data.Gear.Cape, 2, "a newer server's line is kept")
		-- enchants
		T.eq(data.Enchants.Owned.Power, 2)
		T.eq(data.Enchants.Owned.Lucky, nil)
		T.eq(data.Enchants.Owned.Midas, 9, "a higher tier is kept")
		T.eq(EnchantConfig.tierOf(data.Enchants, "Midas"), 3, "readers clamp")
		T.eq(data.Enchants.Owned.Fake, 1, "a newer server's enchant is kept")
		T.eq(data.Enchants.Owned[3], nil)
		T.eq(data.Enchants.Owned.Heartfire, 1)
		T.eq(#data.Enchants.Slots, 4)
		T.eq(data.Enchants.Slots[1], "Power")
		T.eq(data.Enchants.Slots[2], "", "an id sits in one slot only")
		T.eq(data.Enchants.Slots[3], "", "slot 3 isn't open at blaster level 4")
		T.eq(data.Enchants.Slots[4], "")
		T.eq(data.Enchants.Slots[5], nil)
		-- boosts
		T.eq(data.Boosts.TripleLuckyUntil, NOW + BoostConfig.MaxSavedSeconds, "capped")
		T.eq(data.Boosts.HexaLuckyUntil, 0)
		-- golems
		T.eq(#data.Golems.Owned, 3)
		T.eq(data.Golems.Owned[1].Id, 1)
		T.eq(data.Golems.Owned[1].Kind, "PebbleGolem")
		T.eq(data.Golems.Owned[1].Extra, "kept", "a well-formed extra field is kept (a newer server's)")
		T.eq(data.Golems.Owned[1].Paid, true)
		T.eq(data.Golems.Owned[1].Locked, nil, "Locked must be a boolean")
		T.eq(data.Golems.Owned[1].Junk, nil, "tables are dropped")
		T.eq(data.Golems.Owned[1][5], nil, "number keys are dropped")
		T.eq(data.Golems.Owned[1].Long, nil, "long strings are dropped")
		T.eq(data.Golems.Owned[2].Id, 3)
		T.eq(data.Golems.Owned[2].Kind, "IronGolem", "a newer server's kind is kept")
		T.eq(data.Golems.Owned[3].Id, 7)
		T.eq(#data.Golems.Equipped, 2)
		T.eq(data.Golems.Equipped[1], 7)
		T.eq(data.Golems.Equipped[2], 1)
		T.eq(data.Golems.NextId, 8, "above every owned id")
		-- wheel
		T.eq(data.Wheel.NextSpinAt, NOW + WheelConfig.CooldownSeconds)
		-- artifacts
		T.eq(data.Artifacts.Found.CrownCoin, 2)
		T.eq(data.Artifacts.Found.RoyalSeal, nil)
		T.eq(data.Artifacts.Found.Fake, 3, "a newer server's artifact is kept")
		T.eq(data.Artifacts.Found.EmberCrown, ArtifactConfig.MaxCount)
		T.eq(data.Artifacts.Chapters.CrownOfKaldrum, true)
		T.eq(data.Artifacts.Chapters.RoyalRailway, nil)
		T.eq(data.Artifacts.Chapters.Nope, true, "a newer server's chapter is kept")
		-- stats
		T.eq(data.Stats.ArtifactsFound, 0)
		T.eq(data.Stats.CapsulesOpened, 4)
		T.eq(data.Stats.WheelSpins, 0)
		T.eq(data.Stats.WheelOres, 0)
	end)

	T.test("Step67 migration: what a newer server added survives an old server (two runs)", function()
		local data = fresh()
		data.BlasterLevel = 10
		data.Gear.Boots = 7
		data.Gear.Jetpack = 3
		data.Enchants.Owned = { FutureEnchant = 2, Power = 5, Heartfire = 1 }
		data.Enchants.Slots = { "FutureEnchant", "Power", "Heartfire", "" }
		data.Golems = {
			Owned = {
				{ Id = 1, Kind = "FutureGolem" },
				-- saved under its old name (GolemConfig.Renamed)
				{ Id = 2, Kind = "RubyKnight", Paid = true, Locked = true, TradeLockUntil = NOW + 3600, Source = "Royal" },
				{ Id = 5, Kind = "FutureGolem", Paid = true },
			},
			Equipped = { 1, 2 },
			NextId = 6,
		}
		data.Daily = { LastClaimDay = 3, Streak = 2 } -- the retired 7-day chest
		data.Artifacts.Found = { FutureArtifact = 4, CrownCoin = 1 }
		data.Artifacts.Chapters = { FutureCollection = true }
		for run = 1, 2 do
			Migrations.run(data, NOW)
			T.eq(data.Gear.Boots, 7, `run {run}: Boots 7 kept`)
			T.eq(data.Gear.Jetpack, 3, `run {run}: a newer gear line kept`)
			T.eq(data.Enchants.Owned.FutureEnchant, 2, `run {run}: FutureEnchant kept`)
			T.eq(data.Enchants.Owned.Power, 5, `run {run}: Power V kept`)
			T.eq(data.Enchants.Slots[1], "FutureEnchant", `run {run}: still slotted`)
			T.eq(#data.Golems.Owned, 3, `run {run}: FutureGolems kept`)
			T.eq(data.Golems.Owned[1].Kind, "FutureGolem")
			T.eq(data.Golems.Owned[3].Kind, "FutureGolem")
			local rose = data.Golems.Owned[2]
			T.eq(rose.Kind, "RoseKnight", `run {run}: the old RubyKnight id takes its new name`)
			T.eq(rose.Paid, true, `run {run}: Paid kept`)
			T.eq(rose.Locked, true, `run {run}: Locked kept`)
			T.eq(rose.TradeLockUntil, NOW + 3600, `run {run}: a newer server's trading field kept`)
			T.eq(rose.Source, "Royal", `run {run}: a newer server's field kept`)
			T.eq(data.Golems.Owned[3].Paid, true, `run {run}: a paid unknown golem stays paid`)
			T.eq(data.Daily, nil, `run {run}: the retired chest streak is gone`)
			T.eq(#data.Golems.Equipped, 2, `run {run}: an unknown golem stays equipped (docs/SAVE_AUDIT.md #1(b))`)
			T.eq(data.Golems.Equipped[1], 1)
			T.eq(data.Golems.Equipped[2], 2)
			T.eq(GolemConfig.equippedKinds(data.Golems), "RoseKnight", `run {run}: only the known kind follows here`)
			T.eq(data.Golems.NextId, 6)
			T.eq(data.Artifacts.Found.FutureArtifact, 4, `run {run}: FutureArtifact kept`)
			T.eq(data.Artifacts.Chapters.FutureCollection, true)
		end
		-- this server reads them safely
		T.eq(GearConfig.level(data.Gear, "Boots"), GearConfig.MaxLevel)
		T.eq(GearConfig.stats(data.Gear).WalkSpeed, 26, "Boots read as this server's top level")
		local price, reason = GearConfig.quote(data.Gear, "Boots", 8)
		T.eq(price, nil)
		T.eq(reason, "Max", "nothing more to buy")
		T.eq(EnchantConfig.tierOf(data.Enchants, "FutureEnchant"), 0)
		T.eq(EnchantConfig.tierOf(data.Enchants, "Power"), 3)
		local stats = EnchantConfig.stats(data.Enchants, data.BlasterLevel)
		T.near(stats.DamagePct, 0.35 + 0.75, EPS, "Power III + Heartfire; the unknown slot gives nothing")
		T.eq(EnchantConfig.grant(data.Enchants, "Power"), 3)
		T.eq(data.Enchants.Owned.Power, 5, "grant never lowers a newer server's tier")
		T.eq(GolemConfig.count(data.Golems), 3, "they count toward the cap")
		T.eq(ArtifactConfig.countOf(data.Artifacts, "FutureArtifact"), 0)
		T.eq(ArtifactConfig.uniqueCount(data.Artifacts), 1)
		-- at most 8 extra fields per golem (the first by name); Paid / Locked always stay
		local many: any = { Id = 20, Kind = "PebbleGolem", Paid = true, Locked = false }
		for i = 1, 12 do
			many[string.format("F%02d", i)] = i
		end
		data.Golems.Owned[4] = many
		Migrations.run(data, NOW)
		local kept = data.Golems.Owned[4]
		local extras = 0
		for key in kept do
			if key ~= "Id" and key ~= "Kind" and key ~= "Paid" and key ~= "Locked" then
				extras += 1
			end
		end
		T.eq(extras, 8)
		T.eq(kept.F01, 1)
		T.eq(kept.F08, 8)
		T.eq(kept.F09, nil)
		T.eq(kept.Paid, true)
		T.eq(kept.Locked, false)
		table.remove(data.Golems.Owned, 4)
		-- junk inside those records still goes
		data.Golems.Owned[4] = { Id = 9, Kind = 5 }
		data.Golems.Owned[5] = { Id = 10, Kind = "" }
		data.Enchants.Owned.Bad = "x"
		data.Artifacts.Found.Bad = 0
		data.Gear.Bad = "fast"
		Migrations.run(data, NOW)
		T.eq(#data.Golems.Owned, 3)
		T.eq(data.Enchants.Owned.Bad, nil)
		T.eq(data.Artifacts.Found.Bad, nil)
		T.eq(data.Gear.Bad, nil)
	end)

	T.test("Step67 migration: idempotent, and records that aren't tables are rebuilt", function()
		local once = junkSave()
		Migrations.run(once, NOW)
		local twice = ProfileStore.deepCopy(once)
		local report = Migrations.run(twice, NOW)
		T.truthy(deepEqual(once, twice), "second run changed the save")
		T.eq(report.Moved + report.Dropped, 0)
		-- a later run (time moved on) changes nothing either
		local later = ProfileStore.deepCopy(once)
		Migrations.run(later, NOW + 5000)
		T.truthy(deepEqual(once, later), "a later run changed the save")
		local broken = fresh()
		broken.Gear = "x"
		broken.Enchants = 5
		broken.Boosts = true
		broken.Golems = "y"
		broken.Wheel = {}
		broken.Artifacts = { Found = "z" }
		broken.Stats = "w"
		local r = Migrations.run(broken, NOW)
		T.truthy(r.Dropped >= 6, "counted")
		T.eq(broken.Gear.Boots, 0)
		T.eq(#broken.Enchants.Slots, 4)
		T.eq(broken.Boosts.HexaLuckyUntil, 0)
		T.eq(broken.Golems.NextId, 1)
		T.eq(broken.Wheel.NextSpinAt, 0)
		T.eq(next(broken.Artifacts.Found), nil)
		T.eq(type(broken.Artifacts.Chapters), "table")
		T.eq(broken.Stats.WheelSpins, 0)
		T.eq(broken.Stats.OresMined, 0, "Stats rebuilt from the template")
		local again = ProfileStore.deepCopy(broken)
		local r2 = Migrations.run(again, NOW)
		T.truthy(deepEqual(broken, again))
		T.eq(r2.Moved + r2.Dropped, 0)
	end)

	---------------------------------------------------------------- Bonuses

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "P" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function withBonuses(name: string, fn: (any) -> ())
		T.test(name, function()
			local w: any = { byPlayer = {} }
			local savedGet = rawget(DataService, "get")
			rawset(DataService, "get", function(p)
				return w.byPlayer[p]
			end)
			Bonuses._test.reset()
			Bonuses._test.setClock(function()
				return NOW
			end)
			local ok, err = pcall(fn, w)
			rawset(DataService, "get", savedGet)
			Bonuses._test.reset()
			if not ok then
				error(err, 0)
			end
		end)
	end

	withBonuses("Step67 Bonuses: a fresh save is neutral", function(w)
		local stats = Bonuses.compute(fresh(), NOW, nil)
		T.eq(Bonuses.damageMult(stats, false), 1)
		T.eq(Bonuses.damageMult(stats, true), 1)
		T.eq(Bonuses.reach(stats), 0)
		T.eq(Bonuses.oreLuck(stats), 1)
		T.falsy(Bonuses.tripleLucky(stats))
		T.eq(Bonuses.twinDrop(stats), 0)
		T.near(Bonuses.artifactChance(stats, "Quarry"), ArtifactConfig.rockChance("Quarry"), EPS)
		T.eq(Bonuses.sellMult(stats), 1)
		T.eq(Bonuses.walkSpeed(stats), 16, "Boots level 0")
		T.eq(Bonuses.magnetRadius(stats), 0)
		T.eq(Bonuses.pickupRange(stats), 11)
		T.eq(Bonuses.throwMult(stats), 1)
		T.eq(Bonuses.carryCapacity(stats, nil), 1)
		local range, brightness = Bonuses.lamp(stats)
		T.eq(range, 0)
		T.eq(brightness, 0)
		-- no save at all behaves the same
		local none = Bonuses.compute(nil, NOW, nil)
		T.eq(Bonuses.walkSpeed(none), 16)
		T.eq(Bonuses.carryCapacity(none, nil), 1)
		local names = Bonuses._test.names()
		for _, source in { "Gear", "Enchants", "Golems", "Boosts", "Collections" } do
			T.truthy(table.find(names, source), "built-in source " .. source)
		end
		-- carrying: a capped slowdown, never below the floor
		T.eq(Bonuses.carryWalkSpeed(stats, 0), 16)
		T.eq(Bonuses.carryWalkSpeed(stats, 2), 15)
		T.eq(Bonuses.carryWalkSpeed(stats, 6), 13, "at most -3")
		T.eq(Bonuses.carryWalkSpeed(stats, 24), 13, "a full big backpack doesn't pin you")
		T.eq(Bonuses.carryWalkSpeed(stats, 0 / 0), 16)
		-- rollOre: no luck, no random call, the rock's ore stays
		local calls = 0
		local ore = Bonuses.rollOre(stats, { Coal = 1, Gold = 1 }, "Coal", function()
			calls += 1
			return 0.99
		end)
		T.eq(ore, "Coal")
		T.eq(calls, 0)
		local p = fakePlayer(1)
		w.byPlayer[p] = fresh()
		local summary = Bonuses.summary(p)
		T.eq(summary.WalkSpeed, 16)
		T.eq(summary.CarryCapacity, 1)
		T.eq(summary.TripleLucky, false)
		p.attrs.Perk_StrongBack = true
		T.eq(Bonuses.summary(p).CarryCapacity, 2, "StrongBack doubles")
	end)

	withBonuses("Step67 Bonuses: every source adds up", function(w)
		local data = fresh()
		data.BlasterLevel = 10
		data.Gear = { Boots = 5, HelmetLamp = 3, Backpack = 2, Gloves = 5, Magnet = 1 }
		data.Enchants = {
			Owned = { Power = 3, Swift = 2, Magnetism = 1, GolemBond = 2, TwinDrop = 3 },
			Slots = { "Power", "Swift", "Magnetism", "GolemBond" },
		}
		data.Golems = {
			Owned = { { Id = 1, Kind = "EmberImp" }, { Id = 2, Kind = "TinTumbler" }, { Id = 3, Kind = "GildedPorter" } },
			Equipped = { 1, 2, 3 },
			NextId = 4,
		}
		data.Boosts = { TripleLuckyUntil = NOW + 60, HexaLuckyUntil = NOW + 60 }
		for _, artifact in ArtifactConfig.ByCollection.Golemworks do
			ArtifactConfig.add(data.Artifacts, artifact.Id)
		end
		local p = fakePlayer(2)
		w.byPlayer[p] = data
		local stats = Bonuses.stats(p)
		local bond = 1 + 0.25 + 0.1 -- Golem Bond II + the Golemworks collection
		T.near(Bonuses.damageMult(stats, false), 1 + 0.35 + 0.1 * bond, EPS, "Power III + Ember Imp")
		T.near(Bonuses.walkSpeed(stats), (26 + 2) * (1 + 0.03 * bond), EPS, "Boots 5 + Swift II, Tin Tumbler")
		T.eq(Bonuses.magnetRadius(stats), 14 + 3, "Magnet 1 + Magnetism I")
		T.eq(Bonuses.pickupRange(stats), 24)
		T.near(Bonuses.throwMult(stats), 1.4, EPS)
		T.eq(Bonuses.carryCapacity(stats, p), 3)
		local range = Bonuses.lamp(stats)
		T.eq(range, 34)
		T.eq(Bonuses.oreLuck(stats), 2.5, "Hexa Lucky")
		T.truthy(Bonuses.tripleLucky(stats))
		T.eq(Bonuses.twinDrop(stats), 0, "Twin Drop is owned but not slotted")
		-- boots and backpack: the carry slowdown is capped, so Boots V still beat bare feet when full
		T.near(Bonuses.carryWalkSpeed(stats, 12), Bonuses.walkSpeed(stats) - 3, EPS)
		T.truthy(Bonuses.carryWalkSpeed(stats, 12) > 16)
		-- income: one total for EconomyService (the per-source numbers are for breakdowns)
		T.near(Bonuses.incomePct(p), 0.1 * bond, EPS, "Gilded Porter income")
		T.near((Bonuses.source(p, "Golems") :: any).IncomePct, 0.1 * bond, EPS)
		T.eq((Bonuses.source(p, "Gear") :: any).IncomePct, 0)
		T.eq(Bonuses.source(p, "Missing"), nil)
		EconomyService._test.reset()
		Bonuses.attachIncome()
		Bonuses.attachIncome()
		Bonuses.register("Golems", function(_, save)
			return GolemConfig.stats(save.Golems, bond - 1)
		end)
		T.eq(EconomyService._test.bonusCount(), 1, "added once, whatever registers")
		T.near(EconomyService.incomeMultiplier(p), 1 + 0.1 * bond, EPS, "counted exactly once")
		EconomyService._test.reset()
		Bonuses.attachIncome()
		-- boosts run out
		Bonuses._test.setClock(function()
			return NOW + 61
		end)
		stats = Bonuses.stats(p)
		T.eq(Bonuses.oreLuck(stats), 1, "Hexa Lucky ran out")
		T.falsy(Bonuses.tripleLucky(stats))
		-- ore luck upgrades a lower ore with chance 1 - T/T' (here 1 - 2/3.5 = 0.43)
		data.Boosts.HexaLuckyUntil = NOW + 600
		Bonuses.invalidate(p) -- what DataService.changed does
		stats = Bonuses.stats(p)
		local ore = Bonuses.rollOre(stats, { Coal = 1, Gold = 1 }, "Coal", function()
			return 0.3
		end)
		T.eq(ore, "Gold", "a 0.3 roll is below 0.43: upgraded")
		ore = Bonuses.rollOre(stats, { Coal = 1, Gold = 1 }, "Coal", function()
			return 0.5
		end)
		T.eq(ore, "Coal", "a 0.5 roll isn't")
		T.eq(
			Bonuses.rollOre(stats, { Coal = 1, Gold = 1 }, "Gold", function()
				return 0.99
			end),
			"Gold",
			"a Rare+ ore is never downgraded"
		)
	end)

	withBonuses("Step67 Bonuses: totals are cached until the save changes, a boost runs out or 30 s pass", function(w)
		local data = fresh()
		local p = fakePlayer(7)
		w.byPlayer[p] = data
		local now = NOW
		Bonuses._test.setClock(function()
			return now
		end)
		local first = Bonuses.stats(p)
		T.truthy(Bonuses._test.cached(p))
		T.eq(Bonuses.stats(p), first, "the same table: no recompute")
		data.Gear.Boots = 5
		T.eq(Bonuses.walkSpeed(Bonuses.stats(p)), 16, "stale until the save says it changed")
		Bonuses.invalidate(p)
		T.eq(Bonuses.walkSpeed(Bonuses.stats(p)), 26, "fresh after a change")
		-- a running boost: recomputed the moment it runs out
		data.Boosts.HexaLuckyUntil = now + 10
		Bonuses.invalidate(p)
		T.eq(Bonuses.oreLuck(Bonuses.stats(p)), 2.5)
		now += 9
		T.eq(Bonuses.oreLuck(Bonuses.stats(p)), 2.5)
		now += 1
		T.eq(Bonuses.oreLuck(Bonuses.stats(p)), 1, "ran out: recomputed")
		-- at most MaxCacheSeconds for sources outside the save
		local extra = 0
		Bonuses.register("Event", function()
			return { DamagePct = extra }
		end)
		T.eq(Bonuses.damageMult(Bonuses.stats(p), false), 1)
		extra = 0.5
		T.eq(Bonuses.damageMult(Bonuses.stats(p), false), 1, "cached")
		now += Bonuses.MaxCacheSeconds
		T.near(Bonuses.damageMult(Bonuses.stats(p), false), 1.5, EPS, "refreshed after MaxCacheSeconds")
		-- register clears every cache; an unloaded player isn't cached
		Bonuses.register("Event", function()
			return { DamagePct = 0.25 }
		end)
		T.near(Bonuses.damageMult(Bonuses.stats(p), false), 1.25, EPS)
		local ghost = fakePlayer(8)
		Bonuses.stats(ghost)
		T.falsy(Bonuses._test.cached(ghost))
	end)

	withBonuses("Step67 Bonuses: magnet, sell value and one carry capacity for every reader", function(w)
		local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
		local data = fresh()
		data.Enchants = { Owned = { Magnetism = 3, Midas = 2 }, Slots = { "Magnetism", "", "", "" } }
		local p = fakePlayer(11)
		w.byPlayer[p] = data
		-- Magnetism only adds to a real Ore Magnet
		T.eq(Bonuses.magnetRadius(Bonuses.stats(p)), 0, "no Ore Magnet: no pull, whatever the enchant")
		data.Gear.Magnet = 2
		Bonuses.invalidate(p)
		T.eq(Bonuses.magnetRadius(Bonuses.stats(p)), 18 + 10, "Magnet II + Magnetism III")
		T.eq(Bonuses.magnetRadius({ MagnetRadius = 55, MagnetBonus = 20 }), 60, "capped")
		-- sell value: whole coins
		T.eq(Bonuses.sellAmount({ SellPct = 0.2 }, 101), 121)
		T.eq(Bonuses.sellAmount({}, 101), 101)
		T.eq(Bonuses.sellAmount({ SellPct = 0.2 }, 0 / 0), 0)
		-- carry capacity: one source for CarryService and the State snapshot
		Bonuses.register("Event", function()
			return { CarryCapacity = 3 }
		end)
		local capacity = Bonuses.carryCapacity(Bonuses.stats(p), p)
		T.eq(capacity, 4, "Backpack 0 (1) + an event's 3")
		local snapshot = StateService.snapshot(p) :: any
		T.eq(snapshot.CarryCapacity, capacity, "the State shows what CarryService applies")
		T.eq(snapshot.Bonuses.CarryCapacity, capacity)
		p.attrs.Perk_StrongBack = true
		T.eq(StateService.snapshot(p).CarryCapacity, 8, "StrongBack doubles it")
	end)

	withBonuses("Step67 State: big records are sent only when they change", function(w)
		local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
		local data = fresh()
		local p = fakePlayer(12)
		w.byPlayer[p] = data
		local first = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(first.Kept, nil, "the first push is whole")
		-- (CodexSeen comes from CodexService's provider, there once it is in the game)
		local present = {}
		for _, key in StateService.Sticky do
			if first[key] ~= nil then
				table.insert(present, key)
			end
		end
		for _, key in { "Gear", "Enchants", "Golems", "Artifacts", "Bonuses", "Discovered" } do
			T.truthy(table.find(StateService.Sticky, key), key .. " is sticky")
			T.truthy(table.find(present, key), key .. " sent")
		end
		local second = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(#second.Kept, #present, "nothing changed: all kept")
		for _, key in StateService.Sticky do
			T.eq(second[key], nil, key .. " left out")
		end
		T.truthy(second.Coins ~= nil and second.Boosts ~= nil, "small fields always go")
		GolemConfig.add(data.Golems, "PebbleGolem")
		local third = StateService.trim(p, StateService.snapshot(p) :: any)
		T.truthy(third.Golems and #third.Golems.Owned == 1, "a new golem: Golems sent again")
		T.falsy(table.find(third.Kept, "Golems"))
		T.truthy(table.find(third.Kept, "Gear"), "Gear still kept")
		-- fingerprints: same content = same text, whatever the key order
		T.eq(StateService.fingerprint({ A = 1, B = { 2, 3 } }), StateService.fingerprint({ B = { 2, 3 }, A = 1 }))
		T.truthy(StateService.fingerprint({ A = 1 }) ~= StateService.fingerprint({ A = "1" }))
		T.truthy(StateService.fingerprint({ 1, 2 }) ~= StateService.fingerprint({ 2, 1 }))
	end)

	withBonuses("Step67 Bonuses: register replaces a source, bad providers count as nothing", function(w)
		local p = fakePlayer(3)
		w.byPlayer[p] = fresh()
		Bonuses.register("Event", function()
			return { DamagePct = 0.5 }
		end)
		T.near(Bonuses.damageMult(Bonuses.stats(p), false), 1.5, EPS)
		Bonuses.register("Event", function()
			return { DamagePct = 0.25 }
		end)
		T.near(Bonuses.damageMult(Bonuses.stats(p), false), 1.25, EPS, "replaced, not added")
		Bonuses.register("Broken", function()
			error("boom")
		end)
		Bonuses.register("Junk", function()
			return "nope"
		end)
		T.near(Bonuses.damageMult(Bonuses.stats(p), false), 1.25, EPS, "errors ignored")
		Bonuses.unregister("Event")
		T.eq(Bonuses.damageMult(Bonuses.stats(p), false), 1)
		Bonuses.register("Gear", function()
			return { WalkSpeed = 20 }
		end)
		T.eq(Bonuses.walkSpeed(Bonuses.stats(p)), 20, "a package may replace a built-in source")
	end)

	---------------------------------------------------------------- shards + policy

	T.test("Step67: shards are read defensively and never go negative", function()
		T.eq(Shards.get({}), 0, "no field yet")
		T.eq(Shards.get({ Shards = "12" }), 12)
		T.eq(Shards.get({ Shards = 0 / 0 }), 0)
		T.eq(Shards.get({ Shards = -4 }), 0)
		T.eq(Shards.get({ Shards = 7.9 }), 7)
		local data: any = {}
		T.eq(Shards.add(data, 25), 25)
		T.eq(Shards.add(data, 0.5), 25, "below 1 adds nothing")
		T.eq(Shards.add(data, 0 / 0), 25)
		T.falsy(Shards.spend(data, 26), "not enough")
		T.falsy(Shards.spend(data, 1.5), "whole numbers only")
		T.falsy(Shards.spend(data, -1))
		T.truthy(Shards.spend(data, 20))
		T.eq(Shards.get(data), 5)
		T.eq(Shards.add(data, 1e15), Shards.Max, "capped")
	end)

	T.test("Step67: the policy wrapper is strict until it knows, then caches", function()
		Policy._test.reset()
		local calls = 0
		Policy._test.setFetcher(function()
			calls += 1
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
		end)
		local p = fakePlayer(4)
		T.truthy(Policy.cached(p).PaidRandomRestricted, "strict before the first answer")
		T.falsy(Policy.paidRandomRestricted(p))
		T.falsy(Policy.paidRandomRestricted(p))
		T.eq(calls, 1, "asked once")
		T.eq(p.attrs.PaidRandomRestricted, false, "the client can read it")
		T.eq(p.attrs.PaidTradingAllowed, true)
		-- a failing call keeps the strict values and is tried again later
		local q = fakePlayer(5)
		Policy._test.setFetcher(function()
			error("PolicyService down")
		end)
		local now = 100
		Policy._test.setClock(function()
			return now
		end)
		T.truthy(Policy.paidRandomRestricted(q), "strict when the call fails")
		T.eq(q.attrs.PaidRandomRestricted, true)
		local asked = 0
		Policy._test.setFetcher(function()
			asked += 1
			return { ArePaidRandomItemsRestricted = true }
		end)
		-- right after a failure, requests get the strict answer without a new call (audit S1)
		for _ = 1, 5 do
			T.truthy(Policy.paidRandomRestricted(q))
		end
		T.eq(asked, 0, "no call storm while PolicyService is down")
		now += Policy.RefetchSeconds + 1
		T.truthy(Policy.paidRandomRestricted(q))
		T.eq(asked, 1, "asked again after RefetchSeconds")
		T.truthy(Policy.cached(q).Known, "known now")
		Policy._test.reset()
	end)

	T.test("Step67: requests wait for the retry loop instead of asking PolicyService again", function()
		Policy._test.reset()
		local scheduled: { () -> () } = {}
		Policy._test.setSchedule(function(_seconds, fn)
			table.insert(scheduled, fn)
		end)
		local calls = 0
		Policy._test.setFetcher(function()
			calls += 1
			error("PolicyService down")
		end)
		local p = fakePlayer(7)
		local ok, err = pcall(function()
			Policy.prefetch(p)
			T.eq(calls, 1)
			for _ = 1, 10 do
				T.truthy(Policy.paidRandomRestricted(p), "strict while unknown")
			end
			T.eq(calls, 1, "the retry loop is the only caller")
			Policy._test.setFetcher(function()
				calls += 1
				return { ArePaidRandomItemsRestricted = false }
			end)
			table.remove(scheduled, 1)()
			T.eq(calls, 2)
			T.falsy(Policy.paidRandomRestricted(p), "the loop's answer is used")
		end)
		Policy._test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("Step67: a failed policy call on join is retried with backoff until it is known", function()
		Policy._test.reset()
		local scheduled: { { Seconds: number, Fn: () -> () } } = {}
		Policy._test.setSchedule(function(seconds, fn)
			table.insert(scheduled, { Seconds = seconds, Fn = fn })
		end)
		local fails = 3
		local calls = 0
		Policy._test.setFetcher(function()
			calls += 1
			if calls <= fails then
				error("PolicyService down")
			end
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = false }
		end)
		local p = fakePlayer(6)
		local ok, err = pcall(function()
			Policy.prefetch(p) -- its thread runs right away (nothing in it yields here)
			T.eq(calls, 1)
			T.eq(p.attrs.PaidRandomRestricted, true, "strict after the failure")
			Policy.prefetch(p)
			T.eq(calls, 1, "a second prefetch doesn't start another loop")
			local waits = {}
			while #scheduled > 0 do
				local next = table.remove(scheduled, 1)
				table.insert(waits, next.Seconds)
				next.Fn()
			end
			T.eq(calls, fails + 1, "tried until it worked")
			T.eq(waits[1], Policy.RetrySeconds[1])
			T.eq(waits[2], Policy.RetrySeconds[2])
			T.eq(waits[3], Policy.RetrySeconds[3])
			T.eq(#waits, 3, "no more tries once known")
			T.truthy(Policy.cached(p).Known)
			T.eq(p.attrs.PaidRandomRestricted, false, "the attribute follows the real answer")
			-- a player who left stops the retries
			local gone = fakePlayer(9)
			Policy._test.setFetcher(function()
				error("still down")
			end)
			Policy.prefetch(gone)
			gone.Parent = nil
			local pending = table.remove(scheduled, 1)
			T.truthy(pending, "a retry was scheduled")
			pending.Fn()
			T.eq(#scheduled, 0, "no retry for a player who left")
		end)
		Policy._test.reset()
		if not ok then
			error(err, 0)
		end
	end)
end
