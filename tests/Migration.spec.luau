-- Save migrations up to version 3: type clean-up, idempotent, no known
-- machine or well-formed item is ever deleted (retired machines are refunded
-- and their contents go to the pen).
return function(T, Loader)
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")

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

	local function v1Save(): { [string]: any }
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 1
		data.PlacedMachines = {
			"junk",
			{ Id = "Crusher", X = 0 / 0, Z = 1, R = 5 },
			{ Id = "ClayFurnace", X = 2.7, Z = 3, R = -1, In = { { K = "Clean", O = "Copper", G = "Rough" }, "bad" } },
		}
		data.MachineInventory = { Crusher = -1, Anvil = 2.5 }
		return data
	end

	T.test("Migration: template is version 3", function()
		T.eq(DataTemplate.Version, 3)
		T.eq(Migrations.Latest, 3)
	end)

	T.test("Migration: the plan's v1 example", function()
		local data = v1Save()
		local report = Migrations.run(data)
		T.eq(data.Version, 3)
		T.eq(#data.PlacedMachines, 1, "only the furnace stays placed")
		local furnace = data.PlacedMachines[1]
		T.eq(furnace.Id, "ClayFurnace")
		T.eq(furnace.X, 2, "X floored")
		T.eq(furnace.Z, 3)
		T.eq(furnace.R, 3, "R -1 becomes 3")
		T.eq(#furnace.In, 1, "bad queue item dropped")
		T.eq(furnace.In[1].O, "Copper")
		T.eq(furnace.Out, nil)
		T.eq(data.MachineInventory.Crusher, 1, "the Crusher went back to the inventory")
		T.eq(data.MachineInventory.Anvil, nil, "the retired Anvil left the inventory")
		T.eq(data.Coins, 1200, "2 anvils (count floored) refunded at 600")
		local keys = 0
		for _ in data.MachineInventory do
			keys += 1
		end
		T.eq(keys, 1, "inventory is exactly {Crusher=1}")
		T.truthy(report.Moved >= 1, "moved counted")
		T.truthy(report.Dropped >= 3, "dropped counted")
	end)

	T.test("Migration: running it twice gives an identical result", function()
		local once = v1Save()
		Migrations.run(once)
		local twice = ProfileStore.deepCopy(once)
		local report = Migrations.run(twice)
		T.truthy(deepEqual(once, twice), "second run changed the save")
		T.eq(report.Moved, 0)
		T.eq(report.Dropped, 0)
		-- a fresh template needs no repair at all
		local fresh = ProfileStore.deepCopy(DataTemplate)
		local copy = ProfileStore.deepCopy(fresh)
		report = Migrations.run(fresh)
		T.truthy(deepEqual(fresh, copy), "fresh save untouched")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration: queues, unknown items and unknown machines", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 1
		data.Storage = { { K = "Raw", O = "Copper" }, 42, "x", { K = "Ingot", O = "Iron", G = "Clean" } }
		data.PlacedMachines = {
			{ Id = "BlastFurnace", X = 1, Z = 1, R = 0, In = "nope", Out = {} },
			{ Id = "Crusher", X = 4, Z = 4, R = 0, In = { { K = "Clean", O = "Unobtainium", G = "Rough" }, { K = "Clean", O = "Iron", G = 7 } } },
			{ Id = "FutureMachine", X = 6, Z = 6, R = 2, In = { { K = "Raw", O = "Gold" } } },
			{ Id = "FutureMachine", X = math.huge, Z = 6, R = 0, In = { { K = "Raw", O = "Silver" } } },
			{ Id = "Crusher", X = 8, Z = "far", R = 0, Out = { { K = "Crushed", O = "Gold", G = "Clean" } } },
			{ Id = 12, X = 0, Z = 0, R = 0 },
			{ Id = "ClayFurnace", X = 9, Z = 9 },
		}
		data.MachineInventory = { [1] = 3, Conveyor = "5", StorageCrate = 1000, SellChute = 0 / 0, FutureMachine = 2 }
		local report = Migrations.run(data)
		T.eq(#data.Storage, 5, "2 good entries + 3 rescued items")
		T.eq(data.Storage[1].K, "Raw")
		T.eq(data.Storage[2].O, "Iron")
		-- rescued: unknown ore from the Crusher's In, then the lost machines' contents
		local rescued = {}
		for i = 3, #data.Storage do
			rescued[data.Storage[i].O] = true
		end
		T.truthy(rescued.Unobtainium, "unknown ore moved to Storage unchanged")
		T.truthy(rescued.Silver, "contents of a dropped unknown machine are kept")
		T.truthy(rescued.Gold, "contents of a machine sent to the inventory are kept")
		local blast = data.PlacedMachines[1]
		T.eq(blast.Id, "BlastFurnace")
		T.eq(blast.In, nil, "non-table In becomes nil")
		T.eq(blast.Out, nil, "empty Out becomes nil")
		local crusher = data.PlacedMachines[2]
		T.eq(crusher.In, nil, "both queue items left the Crusher")
		local future = data.PlacedMachines[3]
		T.eq(future.Id, "FutureMachine", "unknown ids with a position are kept")
		T.eq(#future.In, 1, "unknown machines keep well-formed contents")
		local furnace = data.PlacedMachines[4]
		T.eq(furnace.Id, "ClayFurnace")
		T.eq(furnace.R, 0, "missing rotation becomes 0")
		T.eq(#data.PlacedMachines, 4)
		T.eq(data.MachineInventory.Crusher, 1, "crusher without a usable Z went to the inventory")
		T.eq(data.MachineInventory.FutureMachine, 2, "unknown inventory ids are kept")
		T.eq(data.MachineInventory.Conveyor, nil, "string count dropped")
		T.eq(data.MachineInventory.StorageCrate, nil, "over 999 dropped")
		T.eq(data.MachineInventory.SellChute, nil, "NaN dropped")
		T.eq(data.MachineInventory[1], nil, "number key dropped")
		T.truthy(report.Dropped > 0 and report.Moved > 0)
		-- and once more: nothing left to do
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration: broken top-level fields become empty tables", function()
		local data = { Version = "one", PlacedMachines = "x", MachineInventory = 5, Storage = false }
		Migrations.run(data)
		T.eq(type(data.PlacedMachines), "table")
		T.eq(type(data.MachineInventory), "table")
		T.eq(type(data.Storage), "table")
		T.eq(data.Version, 3)
		local newer = { Version = 7, PlacedMachines = {}, MachineInventory = {}, Storage = {} }
		Migrations.run(newer)
		T.eq(newer.Version, 7, "a newer save's version is not lowered")
	end)

	T.test("Migration v3: retired machines, pickaxes, podiums and money", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 2
		data.Coins = 100
		data.Pickaxe = "IronPick"
		data.OwnedPickaxes = { StonePick = true, IronPick = true }
		data.BlasterLevel = nil
		data.BlasterOre = "Unobtainium"
		data.Storage = { { K = "Raw", O = "Coal" } }
		data.PlacedMachines = {
			{ Id = "StorageCrate", X = 1, Z = 7, R = 0 },
			{ Id = "Anvil", X = 4, Z = 4, R = 0, In = { { K = "Ingot", O = "Gold", G = "Clean" } } },
			{ Id = "ClayFurnace", X = 8, Z = 4, R = 0 },
		}
		data.MachineInventory = { SellChute = 1, Conveyor = 3 }
		data.Podiums = { "Clean|Gold|Pristine|", "Ingot|Iron|Rough|", "junk", nil :: any, "Clean|Nope|Rough|" }
		data.TotalEarned = -5
		data.LastSeen = 0 / 0
		local report = Migrations.run(data)
		T.eq(data.Version, 3)
		T.eq(#data.PlacedMachines, 1, "only the furnace stays")
		T.eq(data.PlacedMachines[1].Id, "ClayFurnace")
		T.eq(data.MachineInventory.SellChute, nil, "retired chute left the inventory")
		T.eq(data.MachineInventory.Conveyor, 3)
		T.eq(data.Coins, 100 + 150 + 600 + 1200, "crate, anvil and chute refunded")
		T.eq(#data.Storage, 3, "pen: coal + the anvil's ingot + the ingot from podium 2")
		T.eq(data.Storage[2].O, "Gold", "anvil contents kept")
		T.eq(data.Storage[3].K, "Ingot", "an ingot can't stand on a podium")
		T.eq(data.Pickaxe, nil)
		T.eq(data.OwnedPickaxes, nil)
		T.eq(data.BlasterLevel, 1)
		T.eq(data.BlasterOre, "", "unknown blaster ore reset")
		T.eq(#data.Podiums, 4, "exactly 4 podium slots")
		T.eq(data.Podiums[1], "Clean|Gold|Pristine|")
		T.eq(data.Podiums[2], "")
		T.eq(data.Podiums[3], "")
		T.eq(data.Podiums[4], "")
		T.eq(data.TotalEarned, 0)
		T.eq(data.LastSeen, 0)
		T.truthy(report.Moved > 0 and report.Dropped > 0)
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration v3: blaster level clamped, known ore kept", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BlasterLevel = 99.7
		data.BlasterOre = "Ruby"
		Migrations.run(data)
		T.eq(data.BlasterLevel, 10)
		T.eq(data.BlasterOre, "Ruby")
	end)

	T.test("Migration: train levels, cargo and trip times are cleaned", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Train = {
			CapacityLevel = 99.5,
			SpeedLevel = -3,
			Cargo = { { K = "Raw", O = "Coal" }, "junk", { K = "Raw", O = "Unobtainium" } },
			TripCargo = {},
			TripDepartAt = 0 / 0,
			TripArriveAt = 12345,
		}
		local report = Migrations.run(data)
		T.eq(data.Train.CapacityLevel, 5, "clamped to the top level")
		T.eq(data.Train.SpeedLevel, 0)
		T.eq(#data.Train.Cargo, 1, "the coal stays in the cargo")
		T.eq(data.Storage[#data.Storage].O, "Unobtainium", "unknown ore went to the pen")
		T.eq(data.Train.TripDepartAt, 0)
		T.eq(data.Train.TripArriveAt, 0, "no trip without cargo on the move")
		T.truthy(report.Dropped > 0 and report.Moved > 0)
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		-- a broken record becomes a clean one
		local broken = ProfileStore.deepCopy(DataTemplate)
		broken.Train = "x"
		Migrations.run(broken)
		T.eq(type(broken.Train), "table")
		T.eq(#broken.Train.Cargo, 0)
	end)
end
