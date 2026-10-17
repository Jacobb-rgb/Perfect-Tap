-- Mine floors (owner, 2026-10-17): 5 floors, 6 home ores each, rocks Small/Big/Crystal
-- that the floor's weakest blaster breaks in about 5 s, special rocks, and their builder.
return function(T, Loader)
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")

	local KINDS = { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" }

	local function partsOf(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function count(model, name)
		local n = 0
		for _, child in model:GetChildren() do
			if child.Name == name then
				n += 1
			end
		end
		return n
	end

	local function averageIncome(weights)
		local total, sum = 0, 0
		for oreId, w in weights do
			total += w
			sum += w * OreData.get(oreId).Income
		end
		return sum / total
	end

	T.test("mine floors: 5 floors in order, deeper = stronger blaster", function()
		T.eq(#MineFloors.List, 5, "floor count")
		local last = 0
		for i, floor in MineFloors.List do
			T.eq(floor.Index, i, floor.Id .. " index")
			T.truthy(floor.MinBlaster > last, floor.Id .. " needs a stronger blaster than the floor above")
			T.truthy(floor.MinBlaster <= BlasterData.MaxLevel, floor.Id .. " blaster exists")
			T.truthy(LightingConfig.Presets[floor.Lighting] ~= nil, floor.Id .. " lighting preset " .. floor.Lighting)
			T.eq(floor.ViaElevator, i >= 4, floor.Id .. " elevator only for floors 4-5")
			last = floor.MinBlaster
		end
		T.truthy(MineFloors.ComingSoon.MinBlaster > BlasterData.MaxLevel, "floor 6 waits for blaster 11")
	end)

	T.test("mine floors: every ore has exactly one home floor, 6 per floor, better deeper", function()
		local home = {}
		local lastAverage = 0
		for _, floor in MineFloors.List do
			local n = 0
			for oreId, w in floor.Ores do
				T.truthy(OreData.ById[oreId] ~= nil, floor.Id .. " ore " .. oreId .. " exists")
				T.truthy(w > 0, floor.Id .. " " .. oreId .. " weight")
				T.truthy(home[oreId] == nil, oreId .. " has only one home floor")
				home[oreId] = floor.Index
				n += 1
			end
			T.eq(n, 6, floor.Id .. " home ores")
			for oreId in floor.CrystalOres do
				T.truthy(OreData.ById[oreId] ~= nil, floor.Id .. " crystal ore " .. oreId .. " exists")
			end
			local average = averageIncome(floor.Ores)
			T.truthy(average > lastAverage, floor.Id .. " pays more than the floor above")
			T.truthy(averageIncome(floor.CrystalOres) > average * 1.5, floor.Id .. " crystals hold much better ores")
			lastAverage = average
		end
		for _, ore in OreData.List do
			T.truthy(home[ore.Id] ~= nil, ore.Id .. " can be found on some floor")
		end
	end)

	T.test("mine floors: the weakest allowed blaster breaks rocks in about 5 s, deeper rocks are harder", function()
		local lastSmall = 0
		for _, floor in MineFloors.List do
			local damage = BlasterData.damage(floor.MinBlaster, "")
			for _, kind in { "Small", "Big", "Crystal" } do
				local seconds = MineFloors.rockHealth(floor.Index, kind) / damage
				T.truthy(math.abs(seconds - MineFloors.Seconds[kind]) < 0.2, floor.Id .. " " .. kind .. " takes " .. seconds .. " s")
				T.truthy(seconds <= 6.2, floor.Id .. " " .. kind .. " stays around 5 s")
			end
			local small = MineFloors.rockHealth(floor.Index, "Small")
			T.truthy(small < MineFloors.rockHealth(floor.Index, "Big"), floor.Id .. " big rocks are harder")
			T.truthy(MineFloors.rockHealth(floor.Index, "Big") < MineFloors.rockHealth(floor.Index, "Crystal"), floor.Id .. " crystals are a bit harder")
			T.truthy(small > lastSmall, floor.Id .. " rocks are harder than the floor above")
			lastSmall = small
		end
		T.eq(MineFloors.OreCount.Small, 3, "small rock ores")
		T.eq(MineFloors.OreCount.Big, 4, "big rock ores")
		T.eq(MineFloors.OreCount.Crystal, 3, "crystal ores")
		T.truthy(math.abs(MineFloors.SpawnChance.Crystal - 0.1) < 1e-9, "crystals spawn 10 %")
		T.truthy(MineFloors.Elevator.Price > 0, "elevator has a coin price")
	end)

	T.test("rock builder: every kind on every floor builds within its budget", function()
		for _, floor in MineFloors.List do
			for k, kind in KINDS do
				local weights = if kind == "Crystal" then floor.CrystalOres else floor.Ores
				local ores = {}
				for oreId in weights do
					if #ores < MineFloors.OreCount[kind] then
						table.insert(ores, oreId)
					end
				end
				local rock = RockBuilder.build(floor.Index, kind, ores, CF.new(0, 0, 0), k * 7 + floor.Index)
				local parts = partsOf(rock)
				local label = floor.Id .. " " .. kind
				T.le(#parts, RockBuilder.Budget[kind], label .. " parts")
				T.truthy(rock.PrimaryPart ~= nil and rock.PrimaryPart.Name == "Rock1", label .. " has Rock1")
				T.eq(rock:GetAttribute("Floor"), floor.Index, label .. " floor attribute")
				T.eq(rock:GetAttribute("Kind"), kind, label .. " kind attribute")
				T.eq(rock:GetAttribute("Stage"), 0, label .. " stage")
				T.truthy(rock:GetAttribute("OreId") == nil, label .. " keeps its ores secret")
				for _, part in parts do
					T.truthy(part.Anchored, label .. " " .. part.Name .. " anchored")
				end
				if kind == "Small" or kind == "Big" or kind == "Artifact" then
					T.eq(count(rock, "Glint"), #ores, label .. " one glint per ore")
				end
			end
		end
	end)

	T.test("rock builder: deeper floors have more and bigger crystals, crack stages still work", function()
		local last = 0
		for _, floor in MineFloors.List do
			-- average crystal volume over several rocks (one rock's random sizes can vary)
			local volume = 0
			for seed = 1, 8 do
				for _, part in partsOf(RockBuilder.build(floor.Index, "Small", { "Coal", "Coal", "Coal" }, CF.new(0, 0, 0), seed)) do
					if part.Name == "Crystal" then
						volume += part.Size.X * part.Size.Y * part.Size.Z / 8
					end
				end
			end
			T.truthy(volume > last, floor.Id .. " crystals grow with depth")
			last = volume
			local rock = RockBuilder.build(floor.Index, "Small", { "Coal", "Coal", "Coal" }, CF.new(0, 0, 0), 5)
			local cracks = 0
			for stage = 1, 2 do
				local broken = RockBuilder.applyStage(rock, stage, 3)
				T.truthy(#broken >= 1, floor.Id .. " stage " .. stage .. " breaks pieces off")
				for _, piece in broken do
					piece:Destroy()
				end
				T.eq(rock:GetAttribute("Stage"), stage, floor.Id .. " stage attribute")
				local now = count(rock, "Crack")
				T.truthy(now > cracks, floor.Id .. " stage " .. stage .. " adds cracks")
				cracks = now
			end
			T.truthy(rock:FindFirstChild("CrystalGroup") ~= nil, floor.Id .. " keeps its biggest crystal until the shatter")
		end
	end)
end
