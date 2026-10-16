-- Config sanity: every ore/blaster/item table is consistent.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local ToolData = Loader.requirePath("ReplicatedStorage.Shared.Config.ToolData")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")

	T.test("every ore has a known rarity and a reachable blaster tier", function()
		for _, ore in OreData.List do
			T.truthy(Rarity.ById[ore.Rarity], ore.Id .. " rarity")
			T.le(1, ore.Tier, ore.Id .. " tier")
			T.le(ore.Tier, BlasterData.MaxLevel, ore.Id .. " tier")
			T.lt(0, ore.Value, ore.Id .. " value")
			T.lt(0, ore.Hardness, ore.Id .. " hardness")
		end
		T.eq(ToolData.Pickaxes, nil, "no pickaxes any more")
		T.eq(ToolData.carryCapacity(1, false), 1, "carry levels stay")
		T.eq(ToolData.carryCapacity(99, true), ToolData.CarryLevels[#ToolData.CarryLevels].Capacity * 2)
	end)

	T.test("blasters: one Blaster tool per level, within budget, welded, with a Muzzle", function()
		local skins = { "", "Coal", "Gold", "Quartz", "Heartstone", "NotAnOre" }
		local counts = {}
		local reach = {}
		for level = 1, BlasterData.MaxLevel do
			for _, oreId in skins do
				local tool = BlasterBuilder.build(level, oreId)
				local label = `level {level} {oreId}`
				T.eq(tool.ClassName, "Tool", label)
				T.eq(tool.Name, "Blaster", label)
				T.eq(tool:GetAttribute("Level"), level, label)
				T.eq(tool:GetAttribute("Range"), BlasterData.get(level).Range, label)
				T.eq(typeof(tool:GetAttribute("Glow")), "Color3", label)
				local handle = tool:FindFirstChild("Handle")
				T.truthy(handle and handle:IsA("BasePart"), label .. " handle")
				local muzzle = handle:FindFirstChild("Muzzle")
				T.truthy(muzzle and muzzle:IsA("Attachment"), label .. " muzzle")
				local tip = handle.CFrame:PointToWorldSpace(muzzle.Position)
				-- in the hand (the grip attachment frame) the barrel points straight forward
				local hand = handle.CFrame * tool.Grip
				T.near(hand.LookVector.Z, -1, 1e-4, label .. " barrel along the arm")
				T.near(hand.UpVector.Y, 1, 1e-4, label .. " upright")
				T.lt(hand.Position.Y, tip.Y, label .. " hand below the barrel")
				-- the muzzle sits well ahead of the hand, at the very tip of the gun
				T.lt(tip.Z, hand.Position.Z - 1.2, label .. " muzzle ahead of the hand (-Z)")
				reach[level] = hand.Position.Z - tip.Z
				local parts = 0
				for _, d in tool:GetDescendants() do
					if d:IsA("BasePart") then
						parts += 1
						T.lt(tip.Z, d.CFrame.Position.Z, label .. " " .. d.Name .. " behind the muzzle")
						T.falsy(d.CanCollide, label .. " " .. d.Name .. " CanCollide")
						T.truthy(d.Massless, label .. " " .. d.Name .. " Massless")
						T.falsy(d.Anchored, label .. " " .. d.Name .. " Anchored")
						if d ~= handle then
							local weld = d:FindFirstChildOfClass("WeldConstraint")
							T.truthy(weld and weld.Part0 == handle and weld.Part1 == d, label .. " " .. d.Name .. " welded")
						end
					end
				end
				T.le(parts, BlasterBuilder.MaxParts, label .. " part budget")
				T.eq(tool:FindFirstChild("Barrel2") ~= nil, level >= 8, label .. " twin barrels from 8")
				counts[level] = parts
			end
		end
		T.lt(counts[1], counts[BlasterData.MaxLevel], "more detail at level 10")
		T.lt(reach[1] * 2, reach[BlasterData.MaxLevel], "the level 10 rifle is much longer than the starter pistol")
		for level = 2, BlasterData.MaxLevel do
			T.le(counts[level - 1], counts[level], "detail never drops at level " .. level)
		end
		-- level 1 is always the rusty starter, later levels take the ore's colors
		T.eq(BlasterBuilder.build(1, "Gold"):GetAttribute("Glow"), BlasterData.RustySkin.Glow, "rusty level 1")
		T.eq(BlasterBuilder.build(5, ""):GetAttribute("Glow"), BlasterData.RustySkin.Glow, "rusty without an ore")
		T.eq(BlasterBuilder.build(5, "Gold"):GetAttribute("Glow"), OreData.ById.Gold.Glow, "gold glow")
		T.eq(BlasterBuilder.build(5, "Gold").ToolTip, "Gold Forgefire Blaster")
		T.eq(BlasterBuilder.build(0 / 0, nil):GetAttribute("Level"), 1, "junk level")
	end)

	T.test("blaster sounds and remotes", function()
		for _, name in { "BlasterHum", "BlasterStart", "BlasterStop", "BlastHit", "BlastBounce", "NodeCrack", "NodeShatter" } do
			T.truthy(SoundConfig[name], "sound " .. name)
		end
		T.truthy(SoundConfig.BlasterHum.Looped, "the hum loops")
		T.eq(SoundConfig.PickHit, nil, "no pickaxe sounds")
		T.eq(Net.Events.MineSwing, nil, "the pickaxe swing remote is gone")
		T.truthy(Net.Events.MineBlast, "MineBlast is rate limited")
	end)

	T.test("ores get more valuable with rarity", function()
		for i = 2, #OreData.List do
			local a, b = OreData.List[i - 1], OreData.List[i]
			T.le(Rarity.ById[a.Rarity].Order, Rarity.ById[b.Rarity].Order, a.Id .. " before " .. b.Id)
			T.lt(a.Value, b.Value, a.Id .. " value < " .. b.Id)
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
