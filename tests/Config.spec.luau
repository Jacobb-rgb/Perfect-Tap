-- Config sanity: every ore/pickaxe/item table is consistent.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")

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
	T.test("machine and belt slots: 10/13/16/22 and 40/60", function()
		T.eq(MachineData.machineSlots(0, false), 10)
		T.eq(MachineData.machineSlots(1, false), 13)
		T.eq(MachineData.machineSlots(2, false), 16)
		T.eq(MachineData.machineSlots(2, true), 22)
		T.eq(MachineData.machineSlots(0, true), 16)
		T.eq(MachineData.conveyorSlots(false), 40)
		T.eq(MachineData.conveyorSlots(true), 60)
		T.eq(MachineData.MaxOutBuffer, 4)
	end)

	T.test("storageKey and parseKey round-trip for every kind and grade", function()
		local grades = { false }
		for _, grade in ItemData.Grades do
			table.insert(grades, grade.Id)
		end
		for _, ore in OreData.List do
			for kind in ItemData.Kinds do
				for _, g in grades do
					local recipes = if kind == "Gear" then ItemData.Recipes else { false }
					for _, recipe in recipes do
						local desc = { K = kind, O = ore.Id, G = if g then g else nil, R = if recipe then recipe.Id else nil }
						local key = ItemData.storageKey(desc)
						T.truthy(#key <= 80, "key length " .. key)
						local back = ItemData.parseKey(key)
						T.truthy(back, "parse " .. key)
						T.eq(back.K, desc.K, key)
						T.eq(back.O, desc.O, key)
						T.eq(back.G, desc.G, key)
						T.eq(back.R, desc.R, key)
						T.eq(ItemData.storageKey(back), key, "same key again")
					end
				end
			end
		end
		T.eq(ItemData.storageKey({ K = "Raw", O = "Copper" }), "Raw|Copper||", "the format StateService sends")
	end)

	T.test("parseKey rejects junk", function()
		local junk = {
			"",
			"Raw",
			"Raw|Copper",
			"Raw|Copper|",
			"Raw|Copper|||",
			"Rock|Copper||",
			"Raw|Plastic||",
			"Clean|Copper|Shiny|",
			"Gear|Copper|Rough|",
			"Gear|Copper|Rough|Spoon",
			"Clean|Copper|Rough|Dagger",
			"raw|copper||",
			"Raw|Copper||" .. string.rep("x", 80),
			string.rep("|", 100),
		}
		for _, key in junk do
			T.eq(ItemData.parseKey(key), nil, "junk key '" .. key .. "'")
		end
		T.eq(ItemData.parseKey(42 :: any), nil, "not a string")
		T.eq(ItemData.parseKey(nil :: any), nil, "nil")
	end)

	T.test("machine metadata for step d", function()
		local faces = { All = true, NoFront = true }
		for _, machine in MachineData.List do
			if machine.ConveyorFaces ~= nil then
				T.truthy(faces[machine.ConveyorFaces], machine.Id .. " ConveyorFaces")
			end
			if machine.Output then
				T.truthy(machine.LoadText, machine.Id .. " LoadText")
				T.truthy(machine.WrongHint, machine.Id .. " WrongHint")
				T.eq(machine.ConveyorFaces, "NoFront", machine.Id .. " is fed from the sides and back")
			end
		end
		T.eq(MachineData.ById.StorageCrate.ConveyorFaces, "All")
		T.eq(MachineData.ById.SellChute.ConveyorFaces, "All")
		T.eq(MachineData.ById.Anvil.ConveyorFaces, "NoFront")
		T.eq(MachineData.ById.CleaningStation.ConveyorFaces, nil)
		T.eq(MachineData.ById.Conveyor.ConveyorFaces, nil)
		T.truthy(MachineData.ById.Anvil.WrongHint)
		T.truthy(MachineData.ById.StorageCrate.LoadText)
		T.truthy(MachineData.ById.SellChute.LoadText)
		for _, machine in MachineData.List do
			T.eq(machine.AcceptsForeign == true, machine.Id == "SellChute", machine.Id .. " AcceptsForeign")
		end
	end)

	T.test("grade chances sum to 1 and stay within the max grade", function()
		for _, machine in MachineData.List do
			if machine.GradeChances then
				local total = 0
				local maxLevel = ItemData.gradeLevel(machine.MaxGrade or "Flawless")
				for gradeId, chance in machine.GradeChances do
					T.truthy(ItemData.GradeById[gradeId], machine.Id .. " grade " .. gradeId)
					T.le(ItemData.gradeLevel(gradeId), maxLevel, machine.Id .. " " .. gradeId .. " above max")
					T.lt(0, chance, machine.Id .. " chance")
					total += chance
				end
				T.near(total, 1, 1e-9, machine.Id .. " chances sum")
			end
		end
		T.near(MachineData.ById.AutoCleaner.GradeChances.Rough, 0.6, 1e-9)
		T.near(MachineData.ById.AutoCleaner.GradeChances.Clean, 0.4, 1e-9)
	end)

	T.test("the Auto Cleaner beats selling raw but loses to hand-cleaning", function()
		local chances = MachineData.ById.AutoCleaner.GradeChances
		for _, ore in OreData.List do
			local expected = 0
			for gradeId, chance in chances do
				expected += chance * ItemData.value("Clean", ore.Id, gradeId)
			end
			T.lt(ItemData.value("Raw", ore.Id), expected, ore.Id .. " auto > raw")
			T.lt(expected, ItemData.value("Clean", ore.Id, "Clean"), ore.Id .. " auto < hand-cleaned Clean")
		end
	end)

	T.test("machine time never drops under the minimum", function()
		local maxBellows = #MachineData.Bellows.Prices
		for _, machine in MachineData.List do
			if machine.Time then
				T.le(GameConfig.MinProcessTime, MachineData.processTime(machine, maxBellows), machine.Id .. " at Bellows " .. maxBellows)
			end
		end
	end)

	T.test("step d tuning, sounds and remotes are declared", function()
		for _, key in {
			"MachineTick", "IntakeTick", "IntakeMargin", "FeedReachBelt", "FeedReachInto", "OutputRetry", "LooseHeadroom",
			"MinProcessTime", "RejectCooldown", "WrongHintCooldown", "MachineUseRange", "BuildRange", "AntiTeleportRange",
			"MaxItemSpeed", "PlausibleSlack", "MaxItemTravel", "ClientPhysicsRange", "ForeignItemReturn", "ConveyorStuckSpeed",
			"ConveyorStuckSeconds", "ConveyorMaxNudges", "ConveyorNudgeWindow", "SellComboWindow", "SellOthersRadius",
			"StorageTakeMax", "AnvilTimeout", "AnvilWalkAway", "AnvilMinStrikeGap", "AnvilMinSecondsPerHit",
		} do
			T.eq(type(GameConfig[key]), "number", "GameConfig." .. key)
		end
		T.eq(GameConfig.OutputPop.Forward, 6)
		T.eq(GameConfig.OutputPop.Up, 4)
		T.eq(GameConfig.RejectPop.Out, 8)
		T.eq(GameConfig.BeltRejectPop.Side, 9)
		T.lt(GameConfig.ClientPhysicsRange, 96, "physics range inside the streaming radius")
		T.lt(GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom, GameConfig.MaxLooseItemsPerPlayer)
		for _, name in { "Gulp", "MachineDone", "MachineHum", "Reject", "CoinBurst", "BuildRotate" } do
			local sound = SoundConfig[name]
			T.truthy(sound and sound.Id:sub(1, 11) == "rbxasset://", "sound " .. name)
		end
		T.truthy(SoundConfig.MachineHum.Looped, "hum loops")
		local limits = {
			BuildPlace = { 8, 12 },
			BuildMove = { 4, 6 },
			BuildPickup = { 6, 10 },
			MachineAction = { 8, 12 },
			AnvilSubmit = { 2, 3 },
			AnvilCancel = { 2, 3 },
		}
		for name, limit in limits do
			local declared = Net.Events[name]
			T.truthy(declared, "remote " .. name)
			T.eq(declared.Rate, limit[1], name .. " rate")
			T.eq(declared.Burst, limit[2], name .. " burst")
		end
		for _, name in { "BuildResult", "AnvilBegin", "AnvilResult", "OpenUI", "CleanStart" } do
			T.truthy(Net.Events[name] ~= nil, "remote " .. name)
		end
		T.eq(Net.Events.BuildResult, false, "server -> client")
	end)
end
