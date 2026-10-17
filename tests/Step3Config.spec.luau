-- Step 3 contracts (docs/plans/STEP3_PLAN.md, "P0 contracts"): chute cells,
-- the Iron Box, Cleaning Plant quality, machine upgrades, the Tech shop
-- catalog, pen automation, new remotes and save fields.
return function(T, Loader)
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")

	local CELLS = GameConfig.PlotCells
	local CELL = GameConfig.CellSize
	local HALF = CELLS * CELL / 2

	local function entry(id: string, x: number, z: number, r: number?): any
		return { Id = id, X = x, Z = z, R = r or 0 }
	end

	---------------------------------------------------------------- chutes

	T.test("Step 3: three distinct chute cells on the back row", function()
		T.eq(#BaseLayout.ChuteNames, 3)
		local seen = {}
		for _, name in BaseLayout.ChuteNames do
			local chute = BaseLayout.Chutes[name]
			T.truthy(chute, "chute " .. name)
			T.eq(chute.Z, CELLS - 1, name .. " on the back row (next to the yard)")
			T.truthy(chute.X >= 0 and chute.X < CELLS and chute.X == math.floor(chute.X), name .. " X on the grid")
			T.falsy(seen[chute.X], name .. " shares a cell")
			seen[chute.X] = true
			local x, z = BaseLayout.chuteCell(name)
			T.eq(x, chute.X)
			T.eq(z, chute.Z)
			T.eq(BaseLayout.chuteAt(x, z), name, name .. " chuteAt")
		end
		local count = 0
		for _ in BaseLayout.Chutes do
			count += 1
		end
		T.eq(count, 3, "Chutes and ChuteNames agree")
		-- the precise decisions
		T.eq(BaseLayout.Chutes.Pen.X, 3)
		T.eq(BaseLayout.Chutes.Train.X, 6)
		T.eq(BaseLayout.Chutes.Foundry.X, 9)
		T.eq(BaseLayout.Chutes.Pen.Kind, "Source")
		T.eq(BaseLayout.Chutes.Train.Kind, "Source")
		T.eq(BaseLayout.Chutes.Foundry.Kind, "Sink")
		local dx, dz = Grid.dir(BaseLayout.SinkRotation)
		T.eq(dx, 0)
		T.eq(dz, 1, "a sink belt faces +Z, toward the yard")
		T.eq(BaseLayout.chuteAt(0, 0), nil)
		T.eq(BaseLayout.chuteAt(3, 10), nil)
		T.falsy(pcall(BaseLayout.chuteCell, "Nope"), "unknown chute names error")
	end)

	T.test("Step 3: chute points are cell centres on top of the pad", function()
		for _, name in BaseLayout.ChuteNames do
			local x, z = BaseLayout.chuteCell(name)
			local p = BaseLayout.chuteLocal(name)
			local belt = Grid.localCFrame("Conveyor", x, z, 0).Position
			T.near(p.X, belt.X, 1e-6, name .. " x")
			T.near(p.Z, belt.Z, 1e-6, name .. " z")
			T.eq(p.Y, 0, name .. " on the pad top")
			local gx, gz = Grid.cellFromLocal(p)
			T.eq(gx, x)
			T.eq(gz, z)
			T.truthy(p.Z > HALF - CELL and p.Z < HALF, name .. " in the last row before the yard")
			for _, plot in WorldLayout.Plots do
				local plotCF = WorldLayout.plotCFrame(plot)
				local world = BaseLayout.chuteWorld(plotCF, name)
				local want = (plotCF * CFrame.new(p.X, p.Y, p.Z)).Position
				T.truthy((world.Position - want).Magnitude < 1e-4, `{name} world point on plot {plot.Id}`)
			end
		end
		-- the pen chute sits on the pen's side of the grid, the foundry chute on the foundry's
		T.lt(BaseLayout.chuteLocal("Pen").X, 0, "pen chute on the pen side")
		T.lt(0, BaseLayout.chuteLocal("Foundry").X, "foundry chute on the foundry side")
	end)

	T.test("Step 3: Placement keeps everything but belts off the chute cells", function()
		T.truthy(#Placement.Reasons.Chute > 0, "Chute reason text")
		for _, name in BaseLayout.ChuteNames do
			local cx, cz = BaseLayout.chuteCell(name)
			for r = 0, 3 do
				T.truthy(Placement.validate({}, "Conveyor", cx, cz, r), `belt r{r} on the {name} chute`)
			end
			for _, machine in MachineData.List do
				if machine.IsConveyor then
					continue
				end
				for r = 0, 3 do
					local w, d = Grid.footprint(machine.Id, r)
					-- every origin whose footprint covers the chute cell
					for x = cx - w + 1, cx do
						for z = cz - d + 1, cz do
							if Placement.inBounds(machine.Id, x, z, r) then
								local ok, code = Placement.validate({}, machine.Id, x, z, r)
								T.falsy(ok, `{machine.Id} r{r} at {x},{z} over the {name} chute`)
								T.eq(code, "Chute", `{machine.Id} r{r} at {x},{z} code`)
								T.eq(Placement.chuteUnder(machine.Id, x, z, r), name)
							end
						end
					end
				end
			end
		end
		-- next to a chute is fine, and the back row between chutes too
		T.truthy(Placement.validate({}, "ClayFurnace", 4, 10, 0), "2x2 between the pen and train chutes")
		T.truthy(Placement.validate({}, "IronBox", 7, 10, 0), "2x2 between the train and foundry chutes")
		T.truthy(Placement.validate({}, "Crusher", 3, 9, 0), "right in front of a chute")
		-- a move onto a chute is refused and changes nothing
		local furnace = entry("ClayFurnace", 0, 0)
		local data = { PlacedMachines = { furnace }, MachineInventory = {}, Storage = {} }
		local ok, code = Placement.commitMove(data, furnace, 2, 10, 0)
		T.falsy(ok)
		T.eq(code, "Chute")
		T.eq(furnace.X, 0, "unchanged")
		-- a placement onto a chute keeps the machine in the inventory
		local buy = { PlacedMachines = {}, MachineInventory = { IronBox = 1 }, Storage = {} }
		local placed, reason = Placement.commitPlace(buy, "IronBox", 8, 10, 0, Placement.limits(0, false))
		T.eq(placed, nil)
		T.eq(reason, "Chute")
		T.eq(buy.MachineInventory.IronBox, 1)
	end)

	T.test("Step 3: sanitize moves a machine off a chute, keeps belts there", function()
		local blocker = entry("Crusher", 2, 10)
		blocker.In = { { K = "Clean", O = "Copper", G = "Rough" } }
		blocker.Out = { { K = "Crushed", O = "Copper", G = "Rough" } }
		local belt = entry("Conveyor", 6, 11, 2)
		local sink = entry("Conveyor", 9, 11, BaseLayout.SinkRotation)
		local fine = entry("ClayFurnace", 4, 4)
		local data = {
			PlacedMachines = { blocker, belt, sink, fine },
			MachineInventory = {},
			Storage = {},
			Coins = 0,
			TotalEarned = 0,
		}
		local displaced = Placement.sanitize(data)
		T.eq(#displaced, 1)
		T.eq(displaced[1], "Crusher")
		T.eq(data.MachineInventory.Crusher, 1, "back to the inventory")
		T.eq(#data.PlacedMachines, 3)
		T.eq(data.PlacedMachines[1], belt, "belts stay on chutes")
		T.eq(data.PlacedMachines[2], sink)
		T.eq(data.PlacedMachines[3], fine)
		T.eq(#data.Storage, 2, "its queues went to the pen")
		T.eq(blocker.In, nil)
		T.eq(blocker.Out, nil)
		T.eq(#Placement.sanitize(data), 0, "idempotent")
	end)

	T.test("Step 3: the starter kit and the Studio dev kit stay off the chutes", function()
		for _, e in MachineData.StarterKit do
			T.truthy(Placement.chuteAllows(e.Id, e.X, e.Z, e.R), "starter " .. e.Id)
		end
		local kit = GameConfig.StudioDevKit
		if kit then
			for _, e in kit.Layout do
				T.truthy(Placement.chuteAllows(e.Id, e.X, e.Z, e.R), "dev kit " .. e.Id)
			end
		end
	end)

	---------------------------------------------------------------- machines

	T.test("Step 3: the Iron Box", function()
		local box = MachineData.ById.IronBox
		T.truthy(box, "IronBox exists")
		T.eq(box.Name, "Iron Box")
		T.eq(box.Size[1], 2)
		T.eq(box.Size[2], 2)
		T.eq(box.Category, "Processing")
		T.eq(box.ConveyorFaces, "NoFront", "belts on every side but the front")
		T.eq(box.LoadText, "Sort")
		T.truthy(box.WrongHint and #box.WrongHint > 0, "WrongHint")
		T.lt(0, box.Price)
		for _, kind in { "Raw", "Clean", "Crushed", "Ingot" } do
			T.truthy(box.Accepts and box.Accepts[kind], "accepts " .. kind)
		end
		T.falsy(box.Accepts and box.Accepts.Gear, "no gear")
		T.falsy(box.Retired)
		T.truthy(table.find(MachineData.Buildable, box), "buildable")
		T.eq(box.Output, nil, "its service decides where items go")
		-- items wait in its queue like in a processor
		T.eq(MachineLogic.queueSize("IronBox"), GameConfig.MachineIntakeQueue)
		local e = entry("IronBox", 0, 0)
		for i = 1, GameConfig.MachineIntakeQueue do
			local desc = { K = "Clean", O = "Gold", G = "Clean" }
			T.truthy(MachineLogic.accepts("IronBox", desc, e, true), "item " .. i)
			MachineLogic.push(e, desc)
		end
		T.eq(select(2, MachineLogic.accepts("IronBox", { K = "Ingot", O = "Gold" }, e, true)), "Full")
		T.eq(select(2, MachineLogic.accepts("IronBox", { K = "Raw", O = "Gold" }, entry("IronBox", 0, 0), false)), "Foreign")
		T.eq(#MachineLogic.outputs("IronBox", { K = "Clean", O = "Gold" }, 0.5), 0, "no timed outputs")
		-- a front output on the shared grid position
		T.truthy(Grid.outputLocal("IronBox"), "front output")
	end)

	T.test("Step 3: the Cleaning Plant's quality levels", function()
		local plant = MachineData.ById.AutoCleaner
		T.eq(plant.Id, "AutoCleaner", "the id stays")
		T.eq(plant.Name, "Cleaning Plant")
		local levels = plant.QualityLevels
		T.eq(#levels, 6, "levels 0..5")
		T.eq(MachineData.upgradeMax("AutoCleaner", "Quality"), #levels - 1, "one Quality price per level above 0")
		local lastExpected = -1
		for i, odds in levels do
			local total, expected = 0, 0
			for gradeId, chance in odds do
				T.truthy(ItemData.GradeById[gradeId], `level {i - 1} grade {gradeId}`)
				T.lt(0, chance, `level {i - 1} {gradeId}`)
				total += chance
				expected += chance * ItemData.gradeLevel(gradeId)
			end
			T.near(total, 1, 1e-9, `level {i - 1} odds add up`)
			T.lt(lastExpected, expected, `level {i - 1} cleans better than the level below`)
			lastExpected = expected
			T.truthy(MachineData.gradeOdds(i - 1) == odds, `gradeOdds({i - 1})`)
		end
		-- the precise numbers at both ends
		T.near(levels[1].Rough, 0.6, 1e-9)
		T.near(levels[1].Clean, 0.4, 1e-9)
		T.eq(levels[6].Rough, nil)
		T.near(levels[6].Clean, 0.2, 1e-9)
		T.near(levels[6].Pristine, 0.5, 1e-9)
		T.near(levels[6].Flawless, 0.3, 1e-9)
		T.truthy(plant.GradeChances == levels[1], "no upgrades = level 0")
		T.truthy(MachineData.gradeOdds(-4) == levels[1], "clamped low")
		T.truthy(MachineData.gradeOdds(99) == levels[6], "clamped high")
		T.truthy(MachineData.gradeOdds(0 / 0) == levels[1], "NaN")
		T.truthy(MachineData.gradeOdds(2.7) == levels[3], "floored")
		-- MachineLogic rolls the level's odds (Flawless reachable at level 5)
		local raw = { K = "Raw", O = "Gold" }
		T.eq(MachineLogic.outputs("AutoCleaner", raw, 0.999, MachineData.gradeOdds(5))[1].G, "Flawless")
		T.eq(MachineLogic.outputs("AutoCleaner", raw, 0.0, MachineData.gradeOdds(5))[1].G, "Clean")
		T.eq(MachineLogic.outputs("AutoCleaner", raw, 0.999)[1].G, "Clean", "without odds: level 0")
		local smelted = MachineLogic.outputs("ClayFurnace", { K = "Clean", O = "Gold", G = "Pristine" }, 0.1, levels[1])
		T.eq(smelted[1].G, "Pristine", "odds only matter to the plant")
	end)

	T.test("Step 3: Speed and Quality upgrades per machine", function()
		local speed = { AutoCleaner = true, ClayFurnace = true, BlastFurnace = true, Crusher = true, IronBox = true }
		for _, machine in MachineData.List do
			local upgrades = machine.Upgrades
			T.eq(upgrades ~= nil and upgrades.Speed ~= nil, speed[machine.Id] == true, machine.Id .. " Speed")
			T.eq(upgrades ~= nil and upgrades.Quality ~= nil, machine.Id == "AutoCleaner", machine.Id .. " Quality")
			if upgrades then
				for kind, prices in upgrades :: any do
					T.truthy(table.find(MachineData.UpgradeKinds, kind), machine.Id .. " kind " .. kind)
					T.eq(#prices, MachineData.upgradeMax(machine.Id, kind))
					T.eq(prices, MachineData.upgradePrices(machine.Id, kind))
					for i, price in prices do
						T.lt(0, price, `{machine.Id} {kind} {i}`)
						T.eq(price, math.floor(price), `{machine.Id} {kind} {i} whole`)
						if i > 1 then
							-- fast growth: every level costs at least 4x the one before
							T.le(prices[i - 1] * 4, price, `{machine.Id} {kind} level {i} grows fast`)
						end
					end
				end
			end
		end
		T.eq(MachineData.upgradeMax("Conveyor", "Speed"), 0)
		T.eq(MachineData.upgradeMax("Nope", "Speed"), 0)
		T.eq(MachineData.upgradeMax("AutoCleaner", "Nope"), 0)
		T.eq(MachineData.upgradePrices("Crusher", "Quality"), nil)
		-- the base curves
		local curves = MachineData.UpgradeCurves
		for i, price in { 2000, 12000, 70000, 400000, 2.5e6 } do
			T.eq(curves.Speed[i], price, "Speed curve " .. i)
		end
		for i, price in { 5000, 40000, 300000, 2e6, 15e6 } do
			T.eq(curves.Quality[i], price, "Quality curve " .. i)
		end
		T.eq(MachineData.ById.AutoCleaner.Upgrades.Quality[1], 5000)
	end)

	T.test("Step 3: Speed levels shorten jobs, never under MinProcessTime", function()
		T.eq(MachineData.speedMult(0), 1)
		T.near(MachineData.speedMult(1), 0.88, 1e-9)
		T.near(MachineData.speedMult(5), 0.4, 1e-9)
		T.near(MachineData.speedMult(99), 0.4, 1e-9, "clamped")
		T.eq(MachineData.speedMult(-1), 1)
		T.eq(MachineData.speedMult(0 / 0), 1)
		T.eq(MachineData.speedMult(nil), 1)
		for level = 1, 5 do
			T.lt(MachineData.speedMult(level), MachineData.speedMult(level - 1), "level " .. level)
		end
		local furnace = MachineData.ById.ClayFurnace
		T.eq(MachineData.processTime(furnace, 0), 6, "no upgrades")
		T.eq(MachineData.processTime(furnace, 0, 0), 6)
		T.near(MachineData.processTime(furnace, 0, 1), 6 * 0.88, 1e-9)
		T.near(MachineData.processTime(furnace, 5, 5), 6 * 0.5 * 0.4, 1e-9, "Bellows and Speed stack")
		T.eq(MachineData.processTime(furnace, 0 / 0, 0 / 0), 6, "broken levels count as 0")
		T.eq(MachineData.processTime(MachineData.ById.Conveyor, 5, 5), 0, "no Time, no job")
		for _, machine in MachineData.List do
			if machine.Time then
				T.le(GameConfig.MinProcessTime, MachineData.processTime(machine, #MachineData.Bellows.Prices, 5), machine.Id .. " floor")
			end
		end
		T.eq(MachineData.processTime(MachineData.ById.BlastFurnace, 5, 5), GameConfig.MinProcessTime, "2.5 s * 0.2 hits the floor")
	end)

	T.test("Step 3: the Tech shop order is sensible", function()
		local orders = {}
		for i, machine in MachineData.Buildable do
			T.falsy(machine.Retired, machine.Id .. " retired machines are not sold")
			T.falsy(orders[machine.Order], machine.Id .. " shares its Order")
			orders[machine.Order] = true
			if i > 1 then
				T.lt(MachineData.Buildable[i - 1].Order, machine.Order, "Buildable sorted by Order")
			end
		end
		T.eq(MachineData.Buildable[1].Id, "Conveyor", "belts first")
		-- the automation line gets dearer step by step
		local function price(id: string): number
			return MachineData.ById[id].Price
		end
		T.lt(price("Conveyor"), price("ClayFurnace"))
		T.lt(price("ClayFurnace"), price("Crusher"))
		T.lt(price("Crusher"), price("AutoCleaner"))
		T.lt(price("AutoCleaner"), price("IronBox"))
		T.lt(price("IronBox"), price("BlastFurnace"))
		for id in MachineData.Retired do
			T.lt(80, MachineData.ById[id].Order, id .. " sorts after everything sold")
		end
	end)

	---------------------------------------------------------------- economy

	T.test("Step 3: the Tech shop catalog", function()
		local shop = EconomyConfig.TechShop
		T.eq(shop.Shop, "Tech")
		T.truthy(shop.MaxCount >= 10, "belts come in stacks")
		-- every buildable machine and every upgrade, once
		local items = {}
		for _, item in shop.Items do
			T.falsy(items[item.Item], "duplicate " .. item.Item)
			items[item.Item] = item
			T.eq(shop.ById[item.Item], item)
			T.eq(EconomyConfig.techItem(item.Item), item)
		end
		for _, machine in MachineData.Buildable do
			local item = items[machine.Id]
			T.truthy(item, "sells " .. machine.Id)
			T.eq(item.Kind, "Machine")
			T.eq(item.Machine, machine.Id)
			T.eq(item.Section, "Machines")
			for _, kind in MachineData.UpgradeKinds do
				local prices = MachineData.upgradePrices(machine.Id, kind)
				local upgrade = items[`Upgrade:{machine.Id}:{kind}`]
				T.eq(upgrade ~= nil, prices ~= nil, `{machine.Id} {kind} upgrade listed`)
				if upgrade then
					T.eq(upgrade.Kind, "Upgrade")
					T.eq(upgrade.Machine, machine.Id)
					T.eq(upgrade.Upgrade, kind)
					T.eq(upgrade.Prices, prices)
					T.eq(upgrade.Section, "Upgrades")
				end
			end
		end
		for id in MachineData.Retired do
			T.eq(items[id], nil, "retired " .. id .. " not sold")
		end
		T.eq(items.Bellows.Prices, MachineData.Bellows.Prices, "Bellows keeps its prices")
		T.eq(items.Slots.Prices, MachineData.SlotUpgrade.Prices, "Slots keep their prices")
		T.eq(items.PenAutomation.Prices, EconomyConfig.PenAutomation.Prices)
		T.eq(EconomyConfig.PenAutomation.Prices[1], 25000)
		T.eq(EconomyConfig.PenAutomation.Prices[2], 250000)
		T.eq(EconomyConfig.PenAutomation.Billboard, 1)
		T.eq(EconomyConfig.PenAutomation.DirectUnload, 2)
		for _, item in shop.Items do
			local prices = item.Prices
			if prices then
				for i = 2, #prices do
					T.lt(prices[i - 1], prices[i], `{item.Item} price {i} ascending`)
				end
			end
		end
		-- junk Item strings
		local junkItems = { "", "Nope", "Upgrade:Conveyor:Speed", "Upgrade:Crusher:Quality", "Upgrade:AutoCleaner:Luck" }
		table.insert(junkItems, "StorageCrate")
		table.insert(junkItems, "Anvil")
		table.insert(junkItems, string.rep("x", 200))
		for _, junk in junkItems do
			T.eq(EconomyConfig.techItem(junk), nil, "junk item " .. junk)
		end
		T.eq(EconomyConfig.techItem(42), nil, "not a string")
		T.eq(EconomyConfig.techItem(nil), nil)
	end)

	T.test("Step 3: Tech shop prices follow the save", function()
		local data = { MachineUpgrades = {}, Upgrades = { Bellows = 0, ExtraSlots = 0, PenLevel = 0, PenAutomation = 0 } }
		local belt = EconomyConfig.techItem("Conveyor")
		T.eq(EconomyConfig.techPrice(belt, data), MachineData.ById.Conveyor.Price)
		T.eq(EconomyConfig.techPrice(belt, data, 10), MachineData.ById.Conveyor.Price * 10)
		for _, bad in { 0, -1, 1.5, 0 / 0, math.huge, EconomyConfig.TechShop.MaxCount + 1, "3" } do
			local price, reason = EconomyConfig.techPrice(belt, data, bad)
			T.eq(price, nil, "bad count " .. tostring(bad))
			T.eq(reason, "BadCount")
		end
		T.eq(select(1, EconomyConfig.techLevel(belt, data)), 0)
		-- machine upgrades: level by level up to the top
		local quality = EconomyConfig.techItem("Upgrade:AutoCleaner:Quality")
		local prices = MachineData.ById.AutoCleaner.Upgrades.Quality
		for level = 0, #prices - 1 do
			data.MachineUpgrades.AutoCleaner = { Quality = level }
			local current, max = EconomyConfig.techLevel(quality, data)
			T.eq(current, level)
			T.eq(max, #prices)
			T.eq(EconomyConfig.techPrice(quality, data), prices[level + 1], "Quality level " .. level + 1)
			T.eq(EconomyConfig.upgradeLevel(data, "AutoCleaner", "Quality"), level)
		end
		data.MachineUpgrades.AutoCleaner = { Quality = #prices }
		local price, reason = EconomyConfig.techPrice(quality, data)
		T.eq(price, nil)
		T.eq(reason, "Max")
		-- Speed is separate from Quality, broken values count as 0
		local speed = EconomyConfig.techItem("Upgrade:AutoCleaner:Speed")
		T.eq(EconomyConfig.techPrice(speed, data), MachineData.ById.AutoCleaner.Upgrades.Speed[1])
		data.MachineUpgrades.AutoCleaner = { Speed = 0 / 0 }
		T.eq(EconomyConfig.upgradeLevel(data, "AutoCleaner", "Speed"), 0)
		data.MachineUpgrades.AutoCleaner = "junk"
		T.eq(EconomyConfig.upgradeLevel(data, "AutoCleaner", "Speed"), 0)
		T.eq(EconomyConfig.upgradeLevel({}, "AutoCleaner", "Speed"), 0, "no record at all")
		T.eq(EconomyConfig.upgradeLevel({ MachineUpgrades = { Crusher = { Speed = 99 } } }, "Crusher", "Speed"), 5, "clamped")
		-- base upgrades read data.Upgrades
		local pen = EconomyConfig.techItem("PenAutomation")
		T.eq(EconomyConfig.techPrice(pen, data), 25000)
		data.Upgrades.PenAutomation = 1
		T.eq(EconomyConfig.techPrice(pen, data), 250000)
		data.Upgrades.PenAutomation = 2
		T.eq(select(2, EconomyConfig.techPrice(pen, data)), "Max")
		local bellows = EconomyConfig.techItem("Bellows")
		data.Upgrades.Bellows = 2
		T.eq(EconomyConfig.techPrice(bellows, data), MachineData.Bellows.Prices[3])
		local slots = EconomyConfig.techItem("Slots")
		data.Upgrades.ExtraSlots = 1
		T.eq(EconomyConfig.techPrice(slots, data), MachineData.SlotUpgrade.Prices[2])
		T.eq(EconomyConfig.techPrice(slots, { Upgrades = "junk" }), MachineData.SlotUpgrade.Prices[1], "broken Upgrades count as 0")
	end)

	---------------------------------------------------------------- remotes and save

	T.test("Step 3: remotes", function()
		local limits = {
			PenAction = { 8, 12 },
			IronBoxAction = { 4, 6 },
			FoundryAction = { 4, 8 },
			ShopBuy = { 3, 5 },
		}
		for name, limit in limits do
			local declared = Net.Events[name]
			T.truthy(declared, "remote " .. name)
			T.eq(declared.Rate, limit[1], name .. " rate")
			T.eq(declared.Burst, limit[2], name .. " burst")
		end
		T.eq(Net.Events.FoundryBegin, false, "server -> client")
		T.eq(Net.Events.FoundryResult, false, "server -> client")
	end)

	T.test("Step 3: new save fields", function()
		T.eq(DataTemplate.Version, 3, "no version bump: reconcile fills the records")
		T.eq(type(DataTemplate.MachineUpgrades), "table")
		T.eq(next(DataTemplate.MachineUpgrades), nil, "no upgrades at first")
		T.eq(type(DataTemplate.KeepList), "table")
		T.eq(next(DataTemplate.KeepList), nil, "empty keep list = keep everything")
		T.eq(type(DataTemplate.Foundry), "table")
		T.eq(type(DataTemplate.Foundry.Stock), "table")
		T.eq(#DataTemplate.Foundry.Stock, 0)
		T.eq(DataTemplate.Upgrades.PenAutomation, 0)
		T.eq(DataTemplate.Stats.BlastersForged, 0)
		T.truthy(GameConfig.MaxFoundryStock >= 20 and GameConfig.MaxFoundryStock <= GameConfig.MaxStoredItems, "foundry stock cap")
		-- the stock can always hold a full recipe of the top blaster
		local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
		for level = 2, BlasterData.MaxLevel do
			local recipe = BlasterData.get(level).Recipe
			T.le(recipe.Ingots, GameConfig.MaxFoundryStock, "recipe " .. level .. " fits the stock")
		end
	end)
end
