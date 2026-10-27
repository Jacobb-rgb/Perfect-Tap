-- Save migrations up to version 4: type clean-up, idempotent, no known
-- machine or well-formed item is ever deleted (retired machines are refunded
-- and their contents go to the pen); version 4 moves a 12-cell layout onto the
-- 16-cell grid once, against the back wall and on its chutes.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")

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

	T.test("Migration: template is version 9", function()
		T.eq(DataTemplate.Version, 9)
		T.eq(Migrations.Latest, 9)
		T.eq(#DataTemplate.Podiums, EconomyConfig.Podiums.Max, "one template slot per podium")
	end)

	T.test("Migration v7: a v6 save's four podiums grow to five, ores stay where they stood", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 6
		data.Podiums = { "Clean|Gold|Pristine|", "", "Clean|Copper|Rough|", "Clean|Tin|Clean|" }
		Migrations.run(data)
		T.eq(data.Version, 9)
		T.eq(#data.Podiums, 5, "the 5th slot added")
		T.eq(data.Podiums[1], "Clean|Gold|Pristine|")
		T.eq(data.Podiums[2], "")
		T.eq(data.Podiums[3], "Clean|Copper|Rough|", "the old paid podium 3 is a free one now")
		T.eq(data.Podiums[4], "Clean|Tin|Clean|")
		T.eq(data.Podiums[5], "", "the new podium starts empty")
		local copy = ProfileStore.deepCopy(data)
		Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
	end)

	T.test("Migration v8: no Foundry: its ingots go to the pen once; Stats.RunIncome is a number >= 0", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 7
		data.Storage = { { K = "Raw", O = "Coal" } }
		data.Foundry = { Stock = { { K = "Ingot", O = "Gold", G = "Pristine" }, 42, { K = "Ingot", O = "Iron" } } }
		data.Stats.RunIncome = 0 / 0
		local report = Migrations.run(data)
		T.eq(data.Version, 9)
		T.eq(data.Foundry, nil, "the Foundry record goes")
		T.eq(#data.Storage, 3, "both ingots in the pen")
		T.eq(data.Storage[2].O, "Gold")
		T.eq(data.Storage[2].G, "Pristine", "grade kept")
		T.eq(data.Storage[3].O, "Iron")
		T.truthy(report.Moved >= 2 and report.Dropped >= 1, "moved the ingots, dropped the junk")
		T.eq(data.Stats.RunIncome, 0, "NaN income becomes 0")
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
		-- a fresh template save has no Foundry and a RunIncome of 0
		T.eq(DataTemplate.Foundry, nil)
		T.eq(DataTemplate.Stats.RunIncome, 0)
		for _, v in { -5, math.huge, "x" } do
			local s = ProfileStore.deepCopy(DataTemplate)
			s.Stats.RunIncome = v
			Migrations.run(s)
			T.eq(s.Stats.RunIncome, 0, `RunIncome {tostring(v)} -> 0`)
		end
		local s = ProfileStore.deepCopy(DataTemplate)
		s.Stats.RunIncome = 1234.5
		Migrations.run(s)
		T.eq(s.Stats.RunIncome, 1234.5, "a real income stays")
	end)

	T.test("Migration: the plan's v1 example", function()
		local data = v1Save()
		local report = Migrations.run(data)
		T.eq(data.Version, 9)
		T.eq(#data.PlacedMachines, 1, "only the furnace stays placed")
		local furnace = data.PlacedMachines[1]
		T.eq(furnace.Id, "ClayFurnace")
		T.eq(furnace.X, 2 + 2, "X floored, then moved onto the 16-cell grid")
		T.eq(furnace.Z, 3 + 4)
		T.eq(furnace.R, 3, "R -1 becomes 3")
		-- the bad queue item is dropped; the clean Copper goes to the pen (v6: the Furnace takes crushed ore only)
		T.eq(furnace.In, nil, "nothing the Furnace can smelt stays in its queue")
		T.eq(data.Storage[#data.Storage].O, "Copper", "the clean ore waits in the pen")
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
			{ Id = "FusionReactor", X = 1, Z = 1, R = 0, In = "nope", Out = {} },
			{
				Id = "Crusher",
				X = 4,
				Z = 4,
				R = 0,
				In = { { K = "Clean", O = "Unobtainium", G = "Rough" }, { K = "Clean", O = "Iron", G = 7 } },
			},
			{ Id = "FutureMachine", X = 6, Z = 6, R = 2, In = { { K = "Raw", O = "Gold" } } },
			{ Id = "FutureMachine", X = math.huge, Z = 6, R = 0, In = { { K = "Raw", O = "Silver" } } },
			{ Id = "Crusher", X = 8, Z = "far", R = 0, Out = { { K = "Crushed", O = "Gold", G = "Clean" } } },
			{ Id = 12, X = 0, Z = 0, R = 0 },
			{ Id = "ClayFurnace", X = 9, Z = 9 },
		}
		data.MachineInventory =
			{ [1] = 3, Conveyor = "5", IronBox = 1015, FutureMachine2 = 5000.5, SellChute = 0 / 0, FutureMachine = 2, Crusher = 0.5 }
		local report = Migrations.run(data)
		T.eq(#data.Storage, 5, "2 good entries + 3 rescued items")
		T.eq(data.Storage[1].K, "Raw")
		T.eq(data.Storage[2].O, "Iron")
		-- rescued: unknown ore from the Crusher's In, then the lost machines' contents
		local rescued = {}
		for i = 3, #data.Storage do
			rescued[data.Storage[i].O] = true
		end
		T.truthy(rescued.Unobtainium, "a newer build's ore waits in the pen (the machine would drop it)")
		T.truthy(rescued.Silver, "contents of a dropped unknown machine are kept")
		T.truthy(rescued.Gold, "contents of a machine sent to the inventory are kept")
		local blast = data.PlacedMachines[1] -- a 3x3 machine
		T.eq(blast.Id, "FusionReactor")
		T.eq(blast.In, nil, "non-table In becomes nil")
		T.eq(blast.Out, nil, "empty Out becomes nil")
		local crusher = data.PlacedMachines[2]
		T.eq(crusher.In, nil, "both queue items left the Crusher (one to the pen, the malformed one dropped)")
		local future = data.PlacedMachines[3]
		T.eq(future.Id, "FutureMachine", "unknown ids with a position are kept")
		T.eq(#future.In, 1, "unknown machines keep well-formed contents")
		local furnace = data.PlacedMachines[4]
		T.eq(furnace.Id, "ClayFurnace")
		T.eq(furnace.R, 0, "missing rotation becomes 0")
		T.eq(#data.PlacedMachines, 4)
		T.eq(data.MachineInventory.Crusher, 1, "crusher without a usable Z went to the inventory (a count under 1 was dropped first)")
		T.eq(data.MachineInventory.FutureMachine, 2, "unknown inventory ids are kept")
		T.eq(data.MachineInventory.Conveyor, nil, "string count dropped")
		T.eq(data.MachineInventory.IronBox, 999, "over 999 capped, never dropped")
		T.eq(data.MachineInventory.FutureMachine2, 999, "unknown ids are capped too")
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
		T.eq(data.Version, 9)
		local newer = { Version = 10, PlacedMachines = {}, MachineInventory = {}, Storage = {} }
		Migrations.run(newer)
		T.eq(newer.Version, 10, "a newer save's version is not lowered")
	end)

	---------------------------------------------------------------- version 4: the 16-cell grid

	-- A version 3 save's layout on the 12-cell grid: a belt on every cell, the belts on
	-- the old chutes (X 3 / 6 / 9 on the back row 11) turned the way they work there.
	local OLD_CELLS = 12
	local OLD_CHUTES = { Pen = 3, Train = 6, Foundry = 9 }
	local function v3Grid(): { [string]: any }
		local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 3
		data.PlacedMachines = {}
		for z = 0, OLD_CELLS - 1 do
			for x = 0, OLD_CELLS - 1 do
				local r = if z == OLD_CELLS - 1 and x == OLD_CHUTES.Foundry then BaseLayout.SinkRotation else 0
				table.insert(data.PlacedMachines, { Id = "Conveyor", X = x, Z = z, R = r })
			end
		end
		-- a queue and a setting ride along unchanged
		data.PlacedMachines[1].In = { { K = "Raw", O = "Copper" } }
		data.PlacedMachines[2].C = 3
		return data
	end

	T.test("Migration v4: a 12-cell layout moves to 2..13 / 4..15, its chute belts onto chutes 5 / 8 on row 15", function()
		local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
		local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
		T.eq(GameConfig.PlotCells, 16)
		for name, x in { Pen = 5, Train = 8 } do
			local cx, cz = BaseLayout.chuteCell(name)
			T.eq(cx, x, name .. " chute X")
			T.eq(cz, 15, name .. " chute on the back row")
		end
		local data = v3Grid()
		local before = ProfileStore.deepCopy(data.PlacedMachines)
		local report = Migrations.run(data)
		T.eq(data.Version, 9)
		T.eq(report.Moved + report.Dropped, 0, "a move, not a repair (no starter kit given yet: no v6 Crusher)")
		T.eq(#data.PlacedMachines, OLD_CELLS * OLD_CELLS, "every machine stays placed")
		local cells = {}
		local onChute = {}
		for i, entry in data.PlacedMachines do
			local old = before[i]
			T.eq(entry.X, old.X + 2, `X of ({old.X}, {old.Z})`)
			T.eq(entry.Z, old.Z + 4, `Z of ({old.X}, {old.Z})`)
			T.truthy(entry.X >= 2 and entry.X <= 13 and entry.Z >= 4 and entry.Z <= 15, "inside 2..13 / 4..15")
			T.eq(entry.R, old.R, "the turn stays")
			cells[entry.X * 100 + entry.Z] = true
			local chute = BaseLayout.chuteAt(entry.X, entry.Z)
			if chute then
				onChute[chute] = entry
			end
			if old.Z == OLD_CELLS - 1 then
				for name, x in OLD_CHUTES do
					if old.X == x and name ~= "Foundry" then
						T.eq(chute, name, `the belt on the old {name} chute is on the {name} chute`)
					end
				end
				if old.X == OLD_CHUTES.Foundry then
					-- (the FOUNDRY chute went with the Foundry, owner 2026-10-24: its belt is an ordinary belt)
					T.eq(chute, nil, "the old FOUNDRY cell is no chute any more")
					T.eq(entry.X, 11, "the old FOUNDRY belt still moved onto x 11")
					T.eq(entry.R, BaseLayout.SinkRotation, "and still runs off the edge")
				end
			end
		end
		T.eq(data.PlacedMachines[1].In[1].O, "Copper", "queues untouched")
		T.eq(data.PlacedMachines[2].C, 3, "settings untouched")
		local count = 0
		for _ in cells do
			count += 1
		end
		T.eq(count, OLD_CELLS * OLD_CELLS, "no two machines on one cell")
		T.truthy(onChute.Pen and onChute.Train, "the PEN and TRAIN chutes keep their belts")
		-- a second run (every later load) changes nothing
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "moved once only")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration v4: a v3 factory (chute belts, a deck belt, a 3x3 machine) loads with nothing displaced", function()
		local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
		local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 3
		data.PlacedMachines = {
			{ Id = "Conveyor", X = 3, Z = 11, R = 0 }, -- off the PEN chute
			{ Id = "Conveyor", X = 3, Z = 10, R = 0 },
			{ Id = "Conveyor", X = 6, Z = 11, R = 0 }, -- off the TRAIN chute
			{ Id = "Conveyor", X = 9, Z = 10, R = BaseLayout.SinkRotation },
			{ Id = "Conveyor", X = 9, Z = 11, R = BaseLayout.SinkRotation }, -- into the FOUNDRY
			{ Id = "Platform", X = 0, Z = 0, R = 0 },
			{ Id = "Conveyor", X = 0, Z = 0, R = 1, L = 1 }, -- on the deck
			{ Id = "FusionReactor", X = 5, Z = 5, R = 0 },
		}
		Migrations.run(data)
		local displaced = Placement.sanitize(data)
		T.eq(#displaced, 0, "nothing displaced")
		T.eq(#data.PlacedMachines, 8)
		T.eq(BaseLayout.chuteAt(data.PlacedMachines[1].X, data.PlacedMachines[1].Z), "Pen")
		T.eq(BaseLayout.chuteAt(data.PlacedMachines[3].X, data.PlacedMachines[3].Z), "Train")
		T.eq(data.PlacedMachines[5].X, 11, "the old FOUNDRY belt moved like every other")
		T.eq(data.PlacedMachines[5].Z, 15)
		local deck = data.PlacedMachines[7]
		T.eq(deck.X, 2, "the deck belt moved with its platform")
		T.eq(deck.Z, 4)
		T.eq(deck.L, 1)
		-- without the move the belts would miss the chutes (why version 4 exists)
		T.eq(BaseLayout.chuteAt(3, 11), nil, "the old PEN cell is no chute on the 16-cell grid")
	end)

	T.test("Migration v4: a save of version 4 or more is never moved; an old one without a Version is", function()
		for _, version in { 4, 5, Migrations.Latest + 1 } do
			local data = ProfileStore.deepCopy(DataTemplate)
			data.Version = version
			data.PlacedMachines = { { Id = "Conveyor", X = 0, Z = 0, R = 0 }, { Id = "Crusher", X = 14, Z = 14, R = 1 } }
			Migrations.run(data)
			T.eq(data.PlacedMachines[1].X, 0, `version {version}: X stays`)
			T.eq(data.PlacedMachines[1].Z, 0, `version {version}: Z stays`)
			T.eq(data.PlacedMachines[2].X, 14, `version {version}: X stays`)
			T.eq(data.PlacedMachines[2].Z, 14, `version {version}: Z stays`)
			T.eq(data.Version, math.max(version, Migrations.Latest), "a newer save's version is not lowered")
		end
		-- a fresh save (DataTemplate, version 4: the StarterKit is placed on the new grid) stays
		local fresh = ProfileStore.deepCopy(DataTemplate)
		fresh.PlacedMachines = { { Id = "Conveyor", X = 1, Z = 1, R = 0 } }
		Migrations.run(fresh)
		T.eq(fresh.PlacedMachines[1].X, 1)
		T.eq(fresh.PlacedMachines[1].Z, 1)
		-- no usable Version (DataService makes a missing one 1): an old save, moved
		for _, version in { 1, 2, 3, 3.5, "4", 0 / 0 } do
			local data = ProfileStore.deepCopy(DataTemplate)
			data.Version = version
			data.PlacedMachines = { { Id = "Conveyor", X = 0, Z = 0, R = 0 } }
			Migrations.run(data)
			T.eq(data.PlacedMachines[1].X, 2, `version {version}: moved across`)
			T.eq(data.PlacedMachines[1].Z, 4, `version {version}: moved back`)
			T.eq(data.Version, 9)
		end
	end)

	T.test("Migration v4: junk X/Z still goes to the inventory; floored before the move", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 3
		data.Coins = 0
		data.MachineInventory = {}
		data.PlacedMachines = {
			{ Id = "Crusher", X = 0 / 0, Z = 1, R = 0, In = { { K = "Raw", O = "Gold" } } },
			{ Id = "ClayFurnace", X = math.huge, Z = 3, R = 0 },
			{ Id = "FusionReactor", X = 4, Z = "far", R = 0 },
			{ Id = "Conveyor", X = 2.7, Z = 3.2, R = 6 },
		}
		local report = Migrations.run(data)
		T.eq(#data.PlacedMachines, 1)
		local belt = data.PlacedMachines[1]
		T.eq(belt.X, 4, "2.7 floored to 2, then + 2")
		T.eq(belt.Z, 7, "3.2 floored to 3, then + 4")
		T.eq(belt.R, 2)
		T.eq(data.MachineInventory.Crusher, 1, "the Crusher went back to the inventory")
		T.eq(data.MachineInventory.ClayFurnace, 1)
		T.eq(data.MachineInventory.FusionReactor, 1)
		T.eq(data.Storage[#data.Storage].O, "Gold", "its queue went to the pen")
		T.eq(report.Moved, 4, "3 machines and 1 item")
	end)

	T.test("Migration v6: one Furnace: old furnaces refunded with their queues, a Crusher once", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 5
		data.Coins = 0
		data.StarterKitGiven = true
		data.Storage = {}
		data.MachineInventory = { BrickFurnace = 2 }
		data.PlacedMachines = {
			{
				Id = "ClayFurnace",
				X = 2,
				Z = 4,
				R = 0,
				In = { { K = "Clean", O = "Copper", G = "Rough" }, { K = "Crushed", O = "Tin", G = "Rough" } },
			},
			{ Id = "BrickFurnace", X = 5, Z = 4, R = 0, In = { { K = "Crushed", O = "Iron", G = "Clean" } } },
			{ Id = "BlastFurnace", X = 8, Z = 4, R = 0, Out = { { K = "Ingot", O = "Gold", G = "Pristine" } } },
			{ Id = "PlasmaFurnace", X = 12, Z = 4, R = 0 },
		}
		data.MachineUpgrades = { BlastFurnace = { Speed = 2 }, PlasmaFurnace = { Speed = 9 }, ClayFurnace = { Speed = 1 } }
		Migrations.run(data)
		T.eq(data.Version, 9)
		T.eq(#data.PlacedMachines, 1, "only the Furnace stays placed")
		local furnace = data.PlacedMachines[1]
		T.eq(furnace.Id, "ClayFurnace")
		T.eq(#furnace.In, 1, "the Furnace keeps only crushed ore in its queue")
		T.eq(furnace.In[1].K, "Crushed")
		local prices = MachineData.ById
		local refund = prices.BrickFurnace.Price * 3 + prices.BlastFurnace.Price + prices.PlasmaFurnace.Price
		local blastSpeed = MachineData.upgradePrices("BlastFurnace", "Speed") :: { number }
		local plasmaSpeed = MachineData.upgradePrices("PlasmaFurnace", "Speed") :: { number }
		local speedPaid = blastSpeed[1] + blastSpeed[2]
		for i = 1, #plasmaSpeed do
			speedPaid += plasmaSpeed[i] -- a level above the top counts as the top
		end
		T.eq(data.Coins, refund + speedPaid, "every old furnace and its Speed levels are paid back")
		T.eq(data.MachineInventory.BrickFurnace, nil)
		local kinds = {}
		for _, item in data.Storage do
			kinds[item.K] = true
		end
		T.truthy(kinds.Crushed and kinds.Ingot, "their queues wait in the pen")
		T.truthy(kinds.Clean, "the clean ore from the Furnace's queue waits in the pen too")
		T.eq(data.MachineUpgrades.BlastFurnace, nil, "a retired machine's upgrades go")
		T.eq(data.MachineUpgrades.ClayFurnace.Speed, 1, "the Furnace keeps its own")
		T.eq(data.MachineInventory.Crusher, 1, "no Crusher anywhere: one in the Build menu")
		-- once only: a later load (Version 6) never gives another, even after it was sold
		data.MachineInventory.Crusher = nil
		local coins = data.Coins
		Migrations.run(data)
		T.eq(data.MachineInventory.Crusher, nil, "Version 6: no second Crusher")
		T.eq(data.Coins, coins, "and no second refund")
		-- a save whose starter kit wasn't given yet gets the kit's Crusher with the kit, not a gift
		local fresh = ProfileStore.deepCopy(DataTemplate)
		fresh.Version = 5
		fresh.StarterKitGiven = false
		fresh.MachineInventory = {}
		Migrations.run(fresh)
		T.eq(fresh.MachineInventory.Crusher, nil, "no gift before the starter kit")
		-- a save with a Crusher (placed or waiting) gets none
		for _, where in { "placed", "waiting" } do
			local old = ProfileStore.deepCopy(DataTemplate)
			old.Version = 5
			old.StarterKitGiven = true
			old.MachineInventory = {}
			old.PlacedMachines = {}
			if where == "placed" then
				table.insert(old.PlacedMachines, { Id = "Crusher", X = 4, Z = 4, R = 0 })
			else
				old.MachineInventory.Crusher = 2
			end
			Migrations.run(old)
			T.eq(old.MachineInventory.Crusher, if where == "placed" then nil else 2, where)
		end
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
		T.eq(data.Version, 9)
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
		T.eq(data.BlasterOre, "Unobtainium", "a blaster ore this server doesn't know is kept (a newer build's)")
		T.eq(#data.Podiums, 5, "the five podium slots")
		T.eq(data.Podiums[1], "Clean|Gold|Pristine|")
		T.eq(data.Podiums[2], "")
		T.eq(data.Podiums[3], "")
		T.eq(data.Podiums[4], "")
		T.eq(data.Podiums[5], "Clean|Nope|Rough|", "an ore this server does not know stays as it is (docs/SAVE_AUDIT.md #1(b))")
		T.eq(data.TotalEarned, 0)
		T.eq(data.LastSeen, 0)
		T.truthy(report.Moved > 0 and report.Dropped > 0)
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration v3: blaster level floored and kept above this server's top (readers clamp)", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BlasterLevel = 12.7
		data.BlasterOre = "Sapphire"
		Migrations.run(data)
		T.eq(data.BlasterLevel, 12, "a newer build's level 12 stays")
		T.eq(BlasterData.get(data.BlasterLevel).Level, BlasterData.MaxLevel, "read as this server's top level")
		T.eq(data.BlasterOre, "Sapphire")
		data.BlasterLevel = 1e9
		Migrations.run(data)
		T.eq(data.BlasterLevel, 99, "junk-sized levels are capped at 99")
	end)

	T.test("Migration: ores the owner's picture replaced take their new ids everywhere", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BlasterOre = "Ruby"
		data.Storage = { { K = "Clean", O = "Stormcore", G = "Pristine" }, { K = "Raw", O = "Coal" } }
		data.Podiums = { "Clean|Prismite|Flawless|", "", "Clean|Gold|Rough|", "" }
		data.PlacedMachines = {
			{
				Id = "ClayFurnace",
				X = 1,
				Z = 1,
				R = 0,
				In = { { K = "Crushed", O = "Azurium" } },
				Out = { { K = "Ingot", O = "Emerald" } },
			},
		}
		data.Train.Cargo = { { K = "Raw", O = "Magmacore" } }
		data.Version = 7 -- (a save with a Foundry: its ingots go to the pen, renamed first)
		data.Foundry = { Stock = { { K = "Ingot", O = "Solarite" } } }
		data.Discovered = { Ruby = true, Coal = true, Bronze = true, Skyglass = true }
		data.KeepList = { Voidstone = true, Bloodstone = false, GalaxyStone = true }
		Migrations.run(data)
		T.eq(data.BlasterOre, "Bronze")
		T.eq(data.Storage[1].O, "StormPearl", "pen item")
		T.eq(data.Podiums[1], "Clean|PhoenixFeather|Flawless|", "podium key")
		T.eq(data.Podiums[3], "Clean|Gold|Rough|", "kept ores stay")
		local machine = data.PlacedMachines[1]
		T.eq(machine.In[1].O, "DragonEgg", "machine queue")
		T.eq(machine.Out[1].O, "Jade", "machine output")
		T.eq(data.Train.Cargo[1].O, "VolcanicCore", "train cargo")
		T.eq(data.Foundry, nil, "no Foundry")
		T.eq(data.Storage[#data.Storage].O, "Sunstone", "the Foundry's ingot, renamed, in the pen")
		T.eq(data.Discovered.Ruby, nil)
		T.eq(data.Discovered.Bronze, true)
		T.eq(data.Discovered.StormGem, true, "Skyglass -> Storm Gem")
		T.eq(data.KeepList.RoyalAurum, true, "Voidstone -> Royal Aurum")
		T.eq(data.KeepList.GalaxyStone, true, "an existing choice for the new ore wins")
		T.eq(data.KeepList.Bloodstone, nil)
		for old, new in OreData.Renamed do
			T.truthy(OreData.ById[new], old .. " -> a real ore")
			T.eq(OreData.ById[old], nil, old .. " is gone")
			T.eq(OreData.current(old), new)
		end
		T.eq(OreData.current("Coal"), "Coal")
		T.eq(OreData.current("Unobtainium"), nil)
		local copy = ProfileStore.deepCopy(data)
		Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
	end)

	T.test("Migration: an old save with replaced ores AND steps 6-7 records migrates in one chain", function()
		local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
		local CodexService = Loader.requirePath("ServerScriptService.Server.Services.CodexService")
		local NOW = 1_800_000_000
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 2
		-- the old ore roster
		data.BlasterLevel = 10
		data.BlasterOre = "Starmetal"
		data.Storage = { { K = "Clean", O = "Ruby", G = "Flawless" } }
		data.Podiums = { "Clean|Skyglass|Pristine|", "", "", "" }
		data.Discovered = { Coal = true, Ruby = true, Skyglass = true, Starmetal = true }
		data.KeepList = { Starmetal = true }
		-- steps 6-7 records (and the records they replace) from the same save
		data.CarryLevel = 4
		data.Gear = nil
		data.Daily = { Streak = 3, LastClaim = NOW - 100 }
		data.Golems = {
			Owned = {
				{ Id = 1, Kind = "RubyKnight", Locked = true },
				{ Id = 2, Kind = "StormcoreTitan", Paid = true },
				{ Id = 3, Kind = "StarmetalSovereign" },
			},
			Equipped = { 1, 3 },
			NextId = 2,
		}
		data.Enchants = { Owned = { Lucky = 2, Midas = 1 }, Slots = { "Lucky", "Midas", "", "" } }
		data.Boosts = { TripleLuckyUntil = NOW + 600, HexaLuckyUntil = 0 }
		data.Artifacts = { Found = { CrownCoin = 2 }, Chapters = {} }
		data.OreCodex = { Seen = { Coal = true, Ruby = true, Skyglass = true }, Ready = true }
		Migrations.run(data, NOW)
		T.eq(data.Version, Migrations.Latest)
		-- the ores: renamed first, everywhere
		T.eq(data.BlasterOre, "CelestialCore")
		T.eq(data.Storage[1].O, "Bronze", "pen item")
		T.eq(data.Podiums[1], "Clean|StormGem|Pristine|", "podium key")
		T.eq(data.Discovered.Bronze, true)
		T.eq(data.Discovered.StormGem, true)
		T.eq(data.Discovered.CelestialCore, true)
		T.eq(data.Discovered.Ruby, nil)
		T.eq(data.KeepList.CelestialCore, true)
		-- the codex's seen ores follow the rename (no NEW badge for an ore already looked at)
		T.eq(data.OreCodex.Seen.Bronze, true, "Ruby seen -> Bronze seen")
		T.eq(data.OreCodex.Seen.StormGem, true, "Skyglass seen -> Storm Gem seen")
		T.eq(data.OreCodex.Seen.Ruby, nil)
		local codex = CodexService.prepare(data)
		T.truthy(codex.Seen.Bronze and codex.Seen.StormGem and codex.Seen.Coal, "CodexService keeps them (known + discovered)")
		T.eq(codex.Seen.CelestialCore, nil, "found but never looked at: still NEW")
		-- steps 6-7 after it: golems renamed (still locked / paid / equipped), gear, daily, enchants, boosts
		local kinds = {}
		for _, entry in data.Golems.Owned do
			kinds[entry.Id] = entry.Kind
			T.truthy(GolemConfig.ById[entry.Kind], entry.Kind .. " is a live golem")
		end
		T.eq(kinds[1], "RoseKnight")
		T.eq(kinds[2], "StormTitan")
		T.eq(kinds[3], "CelestialSovereign")
		T.eq(data.Golems.Owned[1].Locked, true)
		T.eq(data.Golems.Owned[2].Paid, true)
		T.truthy(table.find(data.Golems.Equipped, 1) and table.find(data.Golems.Equipped, 3), "still equipped")
		T.truthy(data.Golems.NextId > 3, "NextId above every Id")
		T.eq(data.CarryLevel, nil)
		T.eq(data.Gear.Backpack, nil, "CarryLevel 4 -> Backpack 3 -> a pack (Version 9)")
		T.eq(data.Backpacks.Equipped, "RookiePack", "level 3 held 5: the Rookie Pack")
		T.truthy(data.Gear.Boots >= 1)
		T.eq(data.Daily, nil)
		T.eq(data.Enchants.Slots[1], "Lucky")
		T.eq(data.Boosts.TripleLuckyUntil, NOW + 600)
		T.eq(data.Artifacts.Found.CrownCoin, 2)
		-- the golems' ores are the new roster's
		for _, kind in { "RoseKnight", "StormTitan", "CelestialSovereign" } do
			T.truthy(OreData.exists(GolemConfig.ById[kind].Ore), kind .. "'s ore exists")
		end
		-- one chain: a second run changes nothing
		local copy = ProfileStore.deepCopy(data)
		Migrations.run(data, NOW)
		T.truthy(deepEqual(copy, data), "idempotent")
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
		T.eq(data.Train.CapacityLevel, 99, "floored, kept above this server's top (TrainConfig clamps for the readers)")
		T.eq(data.Train.SpeedLevel, 0)
		T.eq(#data.Train.Cargo, 1, "the coal stays in the cargo")
		T.eq(data.Storage[#data.Storage].O, "Unobtainium", "a newer build's ore waits in the pen")
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

	T.test("Migration: a machine at the inventory cap is refunded, never lost", function()
		local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
		local cap = MachineData.MaxInventory
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Coins = 100
		data.MachineInventory = { Conveyor = 1015, Crusher = cap }
		data.PlacedMachines = {
			{ Id = "Crusher", X = "lost", Z = 0, R = 0 }, -- nowhere to put it, the Crusher stack is full
			{ Id = "ClayFurnace", X = 0 / 0, Z = 0, R = 0 }, -- nowhere to put it, room in the inventory
		}
		Migrations.run(data)
		T.eq(data.MachineInventory.Conveyor, cap, "capped")
		T.eq(data.MachineInventory.Crusher, cap, "still at the cap")
		T.eq(data.Coins, 100 + MachineData.ById.Crusher.Price, "the Crusher was refunded")
		T.eq(data.MachineInventory.ClayFurnace, 1, "the furnace went to the inventory")
		T.eq(#data.PlacedMachines, 0)
		local copy = ProfileStore.deepCopy(data)
		local report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration step 3 / v8: machine upgrades, keep list, the Foundry's stock into the pen, pen automation", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 7 -- a save from before the Foundry went
		data.Storage = { { K = "Raw", O = "Coal" } }
		data.MachineUpgrades = {
			AutoCleaner = { Speed = 2.9, Quality = 99, Luck = 3.5, [2] = 1 },
			Crusher = { Speed = -4, Quality = 2 },
			ClayFurnace = { Speed = 0 / 0 },
			Conveyor = { Speed = 1 }, -- a known machine this server sells no upgrade for
			StorageCrate = { Speed = 1 }, -- retired
			FutureMachine = { Speed = 1, Warp = 250 }, -- a newer server's machine
			BlastFurnace = "fast",
			IronBox = { Speed = 1 },
			[7] = { Speed = 1 },
		}
		data.KeepList = { Gold = true, Silver = "yes", Unobtainium = true, Diamond = false, [3] = true, Heartstone = true }
		data.KeepMode = "Everything"
		local stock = {}
		for _ = 1, 63 do
			table.insert(stock, { K = "Ingot", O = "Iron", G = "Clean" })
		end
		table.insert(stock, 1, { K = "Clean", O = "Gold", G = "Rough" }) -- not an ingot: to the pen too
		table.insert(stock, 2, "junk")
		table.insert(stock, 3, { K = "Ingot", O = "Unobtainium" }) -- an ore this server doesn't know: kept
		table.insert(stock, 4, { K = "Ingot", O = "Gold", G = "Shiny" }) -- a grade it doesn't know: kept
		table.insert(stock, 5, { K = "Ingot", O = "Gold", R = "Dagger" })
		table.insert(stock, 6, { K = "Ingot", O = "Sapphire" })
		data.Foundry = { Stock = stock, Extra = "gone with it" }
		data.Upgrades.PenAutomation = 7.5
		local report = Migrations.run(data)

		local up = data.MachineUpgrades
		T.eq(up.AutoCleaner.Speed, 2, "floored")
		T.eq(up.AutoCleaner.Quality, 99, "kept up to 99 (a newer server may sell more levels)")
		T.eq(EconomyConfig.upgradeLevel(data, "AutoCleaner", "Quality"), 5, "read as the top level this server sells")
		T.eq(up.AutoCleaner.Luck, 3, "an upgrade kind a newer server may sell is kept, floored")
		T.eq(up.AutoCleaner[2], nil, "number kind dropped")
		T.eq(up.Crusher.Speed, 0, "negative becomes 0")
		T.eq(up.Crusher.Quality, 2, "kept for a newer server (the Crusher has no Quality here)")
		T.eq(up.ClayFurnace, nil, "NaN level dropped, empty record removed")
		T.eq(up.Conveyor.Speed, 1, "kept for a newer server")
		T.eq(up.StorageCrate, nil, "retired machines are gone for good")
		T.eq(up.FutureMachine.Speed, 1, "unknown machine kept (rolling updates)")
		T.eq(up.FutureMachine.Warp, 99, "unknown levels clamped to 0..99")
		T.eq(EconomyConfig.upgradeLevel(data, "Crusher", "Quality"), 0, "readers clamp to what is sold")
		T.eq(up.BlastFurnace, nil, "not a record")
		T.eq(up.IronBox.Speed, 1, "a good record stays")
		T.eq(up[7], nil, "number key")

		local keep = data.KeepList
		T.eq(keep.Gold, true)
		T.eq(keep.Heartstone, true)
		T.eq(keep.Silver, nil, "only booleans count")
		T.eq(keep.Diamond, false, "an explicit 'send on' choice is kept")
		T.eq(keep.Unobtainium, true, "an ore this server doesn't know is kept (a newer build's)")
		T.eq(keep[3], nil)
		T.eq(data.KeepMode, "Everything", "a mode this server doesn't know is kept...")
		T.truthy(
			MachineData.keepsOre(data.KeepMode, keep, "Gold") == MachineData.keepsOre(MachineData.Keep.Default, keep, "Gold"),
			"...and read as the default"
		)

		-- v8: no Foundry (owner 2026-10-24): every well-formed item of its stock is in the pen
		T.eq(data.Foundry, nil, "the Foundry record goes")
		T.eq(#data.Storage, 1 + 5 + 63, "pen: coal + the 5 odd items + 63 iron ingots (only the junk dropped)")
		T.eq(data.Storage[2].K, "Clean", "the clean gold, in stock order")
		T.eq(data.Storage[3].O, "Unobtainium", "a newer build's ingot is kept")
		T.eq(data.Storage[4].G, "Shiny", "so is an unknown grade")
		T.eq(data.Storage[#data.Storage].O, "Iron", "the iron ingots")

		T.eq(data.Upgrades.PenAutomation, 7, "floored, kept for a newer server (readers clamp)")
		T.eq(select(1, EconomyConfig.techLevel(EconomyConfig.techItem("PenAutomation"), data)), 2, "read as the top level")
		T.truthy(report.Dropped > 0 and report.Moved > 0)

		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("Migration step 3: broken records become clean ones", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.MachineUpgrades = "x"
		data.KeepList = 5
		data.Version = 7
		data.Foundry = "forge"
		data.Upgrades = "none"
		data.KeepMode = 3
		Migrations.run(data)
		T.eq(type(data.MachineUpgrades), "table")
		T.eq(next(data.MachineUpgrades), nil)
		T.eq(type(data.KeepList), "table")
		T.eq(data.Foundry, nil, "a broken Foundry record goes too (v8)")
		T.eq(type(data.Upgrades), "table")
		T.eq(data.Upgrades.PenAutomation, 0)
		T.eq(data.Upgrades.Bellows, 0, "the other upgrade fields come back at 0")
		T.eq(data.Upgrades.PenLevel, 0)
		T.eq(data.KeepMode, "RarePlus", "keep mode back to the default")
		for _, mode in MachineData.Keep.Modes do
			local chosen = ProfileStore.deepCopy(DataTemplate)
			chosen.KeepMode = mode
			chosen.Upgrades.PenAutomation = 999
			Migrations.run(chosen)
			T.eq(chosen.KeepMode, mode, "keeps mode " .. mode)
			T.eq(chosen.Upgrades.PenAutomation, 99, "clamped to 99")
		end
		local stockless = ProfileStore.deepCopy(DataTemplate)
		stockless.Version = 7
		stockless.Foundry = { Stock = "x" }
		stockless.Upgrades.PenAutomation = 0 / 0
		Migrations.run(stockless)
		T.eq(stockless.Foundry, nil, "no Foundry")
		T.eq(stockless.Upgrades.PenAutomation, 0, "NaN")
		-- an old step 2 save gets the new records from reconcile, and they survive the migration
		local old = ProfileStore.deepCopy(DataTemplate)
		old.MachineUpgrades = nil
		old.KeepList = nil
		old.Foundry = nil
		old.Upgrades.PenAutomation = nil
		old.KeepMode = nil
		ProfileStore.reconcile(old, DataTemplate)
		local report = Migrations.run(old)
		T.eq(report.Moved + report.Dropped, 0, "nothing to repair")
		T.truthy(deepEqual(old, DataTemplate), "same as a fresh save")
	end)

	-- What a newer build may have written: ids, grades, kinds, modes, levels
	-- and slots this server doesn't know (docs/SAVE_AUDIT.md #1(b)).
	local NEWER_NOW = 1_800_000_000
	local function newerSave(): { [string]: any }
		local now = NEWER_NOW
		local data = ProfileStore.deepCopy(DataTemplate)
		Migrations.run(data, now) -- a clean baseline
		-- what a newer build may have written: ids, grades, kinds, modes and levels this server doesn't know
		data.Version = Migrations.Latest + 1
		data.BlasterLevel = 12
		data.BlasterOre = "Zzzium"
		-- six podiums: a newer build sells two more (a readable gold on the 5th)
		data.Podiums = { "Clean|Zzzium|Pristine|", "Clean|Gold|Mythical|", "Clean|Gold|Pristine|", "", "Clean|Gold|Pristine|", "" }
		data.KeepMode = "Smart"
		data.KeepList = { Zzzium = true, Gold = false }
		data.Discovered = { Zzzium = true, Gold = true }
		data.Storage = { { K = "Gem", O = "Zzzium" }, { K = "Clean", O = "Gold", G = "Mythical" } }
		-- a record this build doesn't know (an older build's Foundry, or a newer build's field): left alone
		data.Foundry = { Stock = { { K = "Ingot", O = "Zzzium", G = "Shiny" }, { K = "Ingot", O = "Gold" } } }
		data.Train.CapacityLevel = 12
		data.Train.SpeedLevel = 9
		data.Train.Cargo = { { K = "Raw", O = "Coal" } }
		data.PlacedMachines = {
			{ Id = "HyperForge", X = 1, Z = 1, R = 0, C = 12, In = { { K = "Raw", O = "Gold" } } },
			{ Id = "Crusher", X = 4, Z = 4, R = 1 },
		}
		data.MachineInventory = { HyperForge = 2, Crusher = 1 }
		data.MachineUpgrades = { HyperForge = { Warp = 4 }, Crusher = { Speed = 7 } }
		data.Upgrades.PenAutomation = 6
		data.Gear.Boots = 7
		data.Gear.Jetpack = 3
		-- six enchant slots: the newer build's 5th is empty, its 6th holds an owned enchant
		data.Enchants = { Owned = { Voidfire = 2, Power = 1, Starlight = 1 }, Slots = { "Voidfire", "Power", "", "", "", "Starlight" } }
		data.Boosts.MegaLuckyUntil = now + 100
		data.Golems = { Owned = { { Id = 1, Kind = "VoidGolem", Shiny = true } }, Equipped = { 1 }, NextId = 2 }
		data.Tutorial = { Step = 14, Done = false } -- the newer build's tutorial has more steps
		data.Artifacts = { Found = { VoidRelic = 1 }, Chapters = { VoidChapter = true } }
		data.Stats.VoidOres = 5
		data.Hoverboards = { Owned = { "Comet" } } -- a whole record this server has never heard of
		data.Artifacts.Equipped = "VoidCollection"
		data.Wheel.NextSpinAt = now + 60
		data.Settings.Language = "cs"
		data.OreCodex = { Seen = { Zzzium = true, Gold = true }, Ready = true }
		data.LastSeen = now
		-- rebirth: a perk level above this build's top and a perk this build doesn't sell
		data.Rebirths = 4
		data.Stars = 7
		data.StarPerks = { GoldenTouch = 12, StarMagnet = 3 }
		data.PlotGlow = "Aurora" -- a colour this build doesn't know
		data.Stats.StarsEarned = 30
		return data
	end

	T.test("Migration #1(b): a save from a newer build goes through unchanged (nothing it names is 'repaired' away)", function()
		local now = NEWER_NOW
		local data = newerSave()
		local before = ProfileStore.deepCopy(data)
		local report = Migrations.run(data, now)
		for key, value in before do
			T.truthy(deepEqual(value, data[key]), `{key} is unchanged`)
		end
		T.truthy(deepEqual(before, data), "the whole save is unchanged")
		T.eq(report.Moved, 0, "nothing moved")
		T.eq(report.Dropped, 0, "nothing dropped")
		-- a newer build's items inside machines and on the train wait in the pen (the runtime would drop them there)
		data.PlacedMachines[1].In = { { K = "Gem", O = "Zzzium", G = "Shiny", R = "Halo" } }
		data.Train.Cargo = { { K = "Gem", O = "Zzzium" } }
		local pen = #data.Storage
		Migrations.run(data, now)
		T.eq(#data.Storage, pen + 2, "both kept, in the pen")
		T.eq(data.Storage[#data.Storage].O, "Zzzium")
	end)

	T.test("Migration #1(b): a newer build's save survives the load hooks and a State snapshot unchanged", function()
		local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
		local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
		local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
		local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
		local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
		local TrainService = Loader.requirePath("ServerScriptService.Server.Services.TrainService")
		local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
		local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
		local BuildService = Loader.requirePath("ServerScriptService.Server.Services.BuildService")
		local CodexService = Loader.requirePath("ServerScriptService.Server.Services.CodexService")
		local SettingsService = Loader.requirePath("ServerScriptService.Server.Services.SettingsService")
		local TutorialService = Loader.requirePath("ServerScriptService.Server.Services.TutorialService")
		local GolemService = Loader.requirePath("ServerScriptService.Server.Services.GolemService")
		local GearService = Loader.requirePath("ServerScriptService.Server.Services.GearService")
		local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
		local RebirthService = Loader.requirePath("ServerScriptService.Server.Services.RebirthService")
		local Players = Loader.game:GetService("Players")
		local data = newerSave()
		local before = ProfileStore.deepCopy(data)
		local player: any = { UserId = 1901, Name = "Newer", Parent = true, attributes = {} }
		player.GetAttribute = function(self, key)
			return self.attributes[key]
		end
		player.SetAttribute = function(self, key, value)
			self.attributes[key] = value
		end
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(Net, "fire", function() end)
		patch(PlotService, "plotOf", function()
			return nil
		end)
		patch(Players, "GetPlayers", function()
			return { player }
		end)
		PodiumService._test.setClock(function()
			return NEWER_NOW
		end)
		TrainService._test.setClock(function()
			return NEWER_NOW
		end, function()
			return 100
		end, function() end)
		local ok, err = pcall(function()
			Migrations.run(data, NEWER_NOW)
			-- every DataService.onLoaded hook that reads or repairs the save
			CodexService.prepare(data)
			SettingsService.read(data)
			GolemService.refresh(player)
			GearService.refreshLamp(player)
			ArtifactService.applyRewards(player)
			PodiumService._test.loaded(player, data)
			TrainService._test.loaded(player, data)
			TutorialService._test.loaded(player, data)
			-- the State snapshot and its providers
			local snapshot = StateService.snapshot(player) :: any
			TrainService._test.provide(player, data, snapshot)
			PenService._test.provide(player, data, snapshot)
			BuildService._test.provide(player, data, snapshot)
			snapshot.Rebirth = RebirthService.snapshot(data)
			T.eq(snapshot.Rebirth.Count, 4, "the newer build's rebirths")
			T.eq(snapshot.Train.Capacity, TrainConfig.Capacity[#TrainConfig.Capacity].Value, "read as this build's top")
			T.eq(snapshot.BlasterLevel, BlasterData.MaxLevel, "read as this build's top")
		end)
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		PodiumService._test.reset()
		TrainService._test.reset()
		TutorialService._test.reset()
		Bonuses.invalidate(player)
		if not ok then
			error(err, 0)
		end
		for key, value in before do
			T.truthy(deepEqual(value, data[key]), `{key} is unchanged`)
		end
		T.truthy(deepEqual(before, data), "the whole save is unchanged")
	end)

	T.test("Migration #1(b): podium and enchant slots past this build's count: kept when well-formed, junk dropped", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BlasterLevel = 12
		data.Podiums = { "", "", "", "", 7, "Clean|Gold|Pristine|", "junk", { "table" } }
		data.Enchants = { Owned = { Power = 1, Lucky = 1 }, Slots = { "Power", "", "", "", "Power", 5, "Lucky", "NotOwned" } }
		local report = Migrations.run(data)
		T.eq(#data.Podiums, 6, "up to the last well-formed slot")
		T.eq(data.Podiums[5], "", "junk before it becomes empty")
		T.eq(data.Podiums[6], "Clean|Gold|Pristine|", "a newer build's 6th podium stays")
		T.eq(data.Podiums[7], nil, "junk after it is dropped")
		T.eq(#data.Enchants.Slots, 7, "up to the last well-formed slot")
		T.eq(data.Enchants.Slots[5], "", "an enchant slotted twice is slotted once")
		T.eq(data.Enchants.Slots[6], "", "junk becomes empty")
		T.eq(data.Enchants.Slots[7], "Lucky", "an owned enchant in a newer build's 7th slot stays")
		T.eq(data.Enchants.Slots[8], nil, "an enchant that isn't owned is dropped")
		T.eq(report.Dropped, 6, "5 junk entries and a double")
		local copy = ProfileStore.deepCopy(data)
		Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		local EnchantConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig")
		T.eq(EnchantConfig.stats(data.Enchants, data.BlasterLevel).OreLuckPct, nil, "this build reads only its own slots")
	end)

	T.test("Migration #1(b): the ORE CODEX and the settings keep what a newer build added", function()
		local CodexService = Loader.requirePath("ServerScriptService.Server.Services.CodexService")
		local SettingsService = Loader.requirePath("ServerScriptService.Server.Services.SettingsService")
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Discovered = { Gold = true }
		data.OreCodex = { Ready = true, Seen = { Gold = true, Zzzium = true, Silver = true, [3] = true } }
		CodexService.prepare(data)
		T.eq(data.OreCodex.Seen.Gold, true, "a found, seen ore")
		T.eq(data.OreCodex.Seen.Zzzium, true, "an ore a newer build knows stays seen")
		T.eq(data.OreCodex.Seen.Silver, nil, "a known ore that was never found isn't seen")
		T.eq(data.OreCodex.Seen[3], nil, "junk key")
		data.Settings = { Music = 0.5, Sfx = 0.8, Shake = true, Rumble = false, Language = "cs", Subtitles = true, [1] = "x" }
		local clean = SettingsService.read(data)
		T.eq(clean.Music, 0.5, "the known settings")
		T.eq(clean.Language, nil, "(the record handed to the game has only known keys)")
		T.eq(data.Settings.Language, "cs", "a setting a newer build added stays in the save")
		T.eq(data.Settings.Subtitles, true)
		T.eq(data.Settings[1], nil, "junk key")
	end)
	T.test("Migrations: the backpack's counts are whole stacks of at least 1; renamed ores join their new key", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BackpackItems = {
			["Raw|Coal||"] = 0.5, -- under 1: no stack
			["Raw|Iron||"] = -3,
			["Raw|Gold||"] = 0,
			["Raw|Tin||"] = 2.7, -- a fraction: its whole part
			["Raw|Copper||"] = 0 / 0,
			["Clean|Ruby|Rough|"] = 3, -- an old roster ore (OreData.Renamed: Ruby -> Bronze)
			["Clean|Bronze|Rough|"] = 1,
			["not a key"] = 4,
		}
		Migrations.run(data)
		local items = data.BackpackItems
		for _, gone in { "Raw|Coal||", "Raw|Iron||", "Raw|Gold||", "Raw|Copper||", "not a key", "Clean|Ruby|Rough|" } do
			T.eq(items[gone], nil, gone .. " dropped")
		end
		T.eq(items["Raw|Tin||"], 2, "2.7 -> 2")
		T.eq(items["Clean|Bronze|Rough|"], 4, "the renamed stack joined the new key")
		Migrations.run(data)
		T.eq(items["Clean|Bronze|Rough|"], 4, "idempotent")
	end)
	T.test("Migrations: the old Ore Backpack's coins come back, less the pack it becomes (Version 9, once)", function()
		local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
		local data = ProfileStore.deepCopy(DataTemplate)
		data.Version = 8
		data.Coins = 100
		data.Gear.Backpack = 5 -- held 12, paid 800 + 5K + 30K + 180K + 1.1M
		Migrations.run(data)
		local paid = 800 + 5000 + 30000 + 180000 + 1100000
		T.eq(data.Backpacks.Equipped, "TrailPack", "12 -> the Trail Pack (15)")
		T.eq(data.Coins, 100 + paid - BackpackData.ById.TrailPack.Price, "paid back, less the Trail Pack")
		Migrations.run(data)
		T.eq(data.Coins, 100 + paid - BackpackData.ById.TrailPack.Price, "once")
		local small = ProfileStore.deepCopy(DataTemplate)
		small.Version = 8
		small.Coins = 0
		small.Gear.Backpack = 1 -- held 2: the free Rookie pack
		Migrations.run(small)
		T.eq(small.Coins, 800, "level I paid back in full")
		local none = ProfileStore.deepCopy(DataTemplate)
		none.Version = 8
		none.Coins = 7
		none.Gear.Backpack = 0
		Migrations.run(none)
		T.eq(none.Coins, 7, "no levels, no coins")
	end)
end
