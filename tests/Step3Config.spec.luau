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
	-- the chute cells on the back row (they move with a bigger grid)
	local BACK = CELLS - 1
	local PX = BaseLayout.chuteCell("Pen")
	local TX = BaseLayout.chuteCell("Train")
	local FX = BaseLayout.chuteCell("Foundry")

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
		-- the precise decisions: 3 / 6 / 9 on a 12-cell grid, moved with a bigger one
		local shift = (CELLS - 12) / 2
		T.eq(BaseLayout.Chutes.Pen.X, 3 + shift)
		T.eq(BaseLayout.Chutes.Train.X, 6 + shift)
		T.eq(BaseLayout.Chutes.Foundry.X, 9 + shift)
		T.eq(BaseLayout.Chutes.Pen.Kind, "Source")
		T.eq(BaseLayout.Chutes.Train.Kind, "Source")
		T.eq(BaseLayout.Chutes.Foundry.Kind, "Sink")
		local dx, dz = Grid.dir(BaseLayout.SinkRotation)
		T.eq(dx, 0)
		T.eq(dz, 1, "a sink belt faces +Z, toward the yard")
		-- a Source never spawns onto a belt that runs off the grid into the yard
		for r = 0, 3 do
			T.eq(BaseLayout.sourceFeeds(r), r ~= BaseLayout.SinkRotation, "sourceFeeds r" .. r)
		end
		for _, bad in { -1, 4, 1.5, 0 / 0, "0" :: any, nil :: any } do
			T.falsy(BaseLayout.sourceFeeds(bad), "sourceFeeds " .. tostring(bad))
		end
		T.eq(BaseLayout.chuteAt(0, 0), nil)
		T.eq(BaseLayout.chuteAt(3, 10), nil)
		T.falsy(pcall(BaseLayout.chuteCell, "Nope"), "unknown chute names error")
		-- every chute can be drawn: a label, a color and a hint, all different
		local labels, colors = {}, {}
		for _, name in BaseLayout.ChuteNames do
			local chute = BaseLayout.Chutes[name]
			T.truthy(type(chute.Label) == "string" and #chute.Label > 0 and #chute.Label <= 8, name .. " label")
			T.eq(chute.Label, string.upper(chute.Label), name .. " label in capitals")
			T.truthy(type(chute.Hint) == "string" and #chute.Hint > 10, name .. " hint")
			T.falsy(labels[chute.Label], name .. " label shared")
			labels[chute.Label] = true
			local key = string.format("%.3f,%.3f,%.3f", chute.Color.R, chute.Color.G, chute.Color.B)
			T.falsy(colors[key], name .. " color shared")
			colors[key] = true
		end
	end)

	T.test("Step 3: the Foundry's receiver sits at the FOUNDRY chute", function()
		local intake = BaseLayout.FoundryIntake
		local cell = BaseLayout.chuteLocal("Foundry")
		local zone, mouth = intake.Zone, intake.Mouth
		local function inside(p: any, r: any): boolean
			return math.abs(p.X - r.Center.X) <= r.Size.X / 2 and math.abs(p.Z - r.Center.Z) <= r.Size.Z / 2
		end
		T.truthy(inside(mouth, zone), "mouth inside the zone")
		T.near(mouth.X, cell.X, 1e-6, "mouth over the chute's belt")
		T.truthy(mouth.Z > HALF - CELL / 2 and mouth.Z < HALF, "mouth at the cell's back edge")
		T.truthy(mouth.Y > 0.5 and mouth.Y < zone.Size.Y, "mouth at belt height")
		-- the zone covers only the chute's column (no other cell) and the wall behind it
		T.truthy(zone.Center.X - zone.Size.X / 2 >= cell.X - CELL / 2, "zone within the chute column (left)")
		T.truthy(zone.Center.X + zone.Size.X / 2 <= cell.X + CELL / 2, "zone within the chute column (right)")
		T.truthy(zone.Center.Z - zone.Size.Z / 2 >= HALF - CELL / 2, "zone reaches into the last half of the cell at most")
		T.truthy(zone.Center.Z + zone.Size.Z / 2 <= HALF + 2, "zone stays at the wall")
		-- clear of the yard gate and of every yard piece
		local gate = BaseLayout.YardGate
		T.truthy(zone.Center.X - zone.Size.X / 2 >= gate.CenterX + gate.Width / 2, "off the yard gate")
		for name, piece in BaseLayout.pieces() do
			local overlapX = math.abs(zone.Center.X - piece.Center.X) < (zone.Size.X + piece.Size.X) / 2
			local overlapZ = math.abs(zone.Center.Z - piece.Center.Z) < (zone.Size.Z + piece.Size.Z) / 2
			T.falsy(overlapX and overlapZ, "receiver overlaps " .. name)
		end
	end)

	T.test("Bigger plots: the base keeps its plot-local layout at any grid size", function()
		T.eq((CELLS - 12) % 2, 0, "the grid grows the same on both sides")
		T.eq(BaseLayout.GridShift, (CELLS - 12) / 2)
		-- the chutes keep their plot-local x, in line with the pen gate, the yard gate and the receiver
		T.near(BaseLayout.chuteLocal("Pen").X, -10, 1e-9, "PEN chute x")
		T.near(BaseLayout.chuteLocal("Train").X, 2, 1e-9, "TRAIN chute x")
		T.near(BaseLayout.chuteLocal("Foundry").X, 14, 1e-9, "FOUNDRY chute x")
		T.le(math.abs(BaseLayout.chuteLocal("Pen").X - BaseLayout.Pen.PromptPoint.X), 3, "PEN chute by the pen gate")
		local gate = BaseLayout.YardGate
		T.lt(math.abs(BaseLayout.chuteLocal("Train").X - gate.CenterX) + CELL / 2, gate.Width / 2 + 1e-9, "TRAIN chute in the yard gate")
		-- the yard starts at the pad's back wall line and is as wide as the pad
		local yard = BaseLayout.Yard
		T.eq(BaseLayout.YardZ0, HALF + 1)
		T.near(yard.Center.Z - yard.Size.Z / 2, HALF + 1, 1e-9, "the yard's front edge")
		T.near(yard.Size.X, 2 * (HALF + 1), 1e-9, "the yard is as wide as the pad")
		for name, piece in BaseLayout.pieces() do
			T.le(HALF + 1, piece.Center.Z - piece.Size.Z / 2, name .. " in the yard")
			T.le(math.abs(piece.Center.X) + piece.Size.X / 2, HALF + 1, name .. " between the yard walls")
		end
		T.lt(BaseLayout.TrainStop.Center.Z + BaseLayout.TrainStop.Size.Z / 2, BaseLayout.RailZ - 2.95, "train stop off the rail")
		-- the pen: closed by the left yard wall (PlotBuilder's pen), its right edge at x -1
		local pen = BaseLayout.Pen.Area
		T.lt(pen.Center.X - pen.Size.X / 2 + HALF + 1, 2.5, "the left yard wall closes the pen")
		T.near(pen.Center.X + pen.Size.X / 2, -1, 1e-9, "the pen's right edge stays")
		-- the starter kit keeps its plot-local x and its distance from the back wall
		local kit = MachineData.StarterKit
		T.eq(-HALF + kit[1].X * CELL, -8, "starter kit x")
		T.eq(2 * HALF - kit[1].Z * CELL, 32, "starter kit from the back wall")
		T.eq(kit[2].X - kit[1].X, 4, "the furnace beside the station")
		-- the Foundry building stands 2 studs into its rect
		local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
		local front = BaseLayout.Foundry.Center.Z - BaseLayout.Foundry.Size.Z / 2
		T.near(FoundryBuilder.AnvilLocal.Z - front, 2 + 3.0, 1e-9, "the Foundry's anvil follows the rect")
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
		T.truthy(Placement.validate({}, "ClayFurnace", PX + 1, BACK - 1, 0), "2x2 between the pen and train chutes")
		T.truthy(Placement.validate({}, "IronBox", TX + 1, BACK - 1, 0), "2x2 between the train and foundry chutes")
		T.truthy(Placement.validate({}, "Crusher", PX, BACK - 2, 0), "right in front of a chute")
		-- a move onto a chute is refused and changes nothing
		local furnace = entry("ClayFurnace", 0, 0)
		local data = { PlacedMachines = { furnace }, MachineInventory = {}, Storage = {} }
		local ok, code = Placement.commitMove(data, furnace, PX - 1, BACK - 1, 0)
		T.falsy(ok)
		T.eq(code, "Chute")
		T.eq(furnace.X, 0, "unchanged")
		-- a placement onto a chute keeps the machine in the inventory
		local buy = { PlacedMachines = {}, MachineInventory = { IronBox = 1 }, Storage = {} }
		local placed, reason = Placement.commitPlace(buy, "IronBox", FX - 1, BACK - 1, 0, Placement.limits(0, false))
		T.eq(placed, nil)
		T.eq(reason, "Chute")
		T.eq(buy.MachineInventory.IronBox, 1)
	end)

	T.test("Step 3: sanitize moves a machine off a chute, keeps belts there", function()
		local blocker = entry("Crusher", PX - 1, BACK - 1)
		blocker.In = { { K = "Clean", O = "Copper", G = "Rough" } }
		blocker.Out = { { K = "Crushed", O = "Copper", G = "Rough" } }
		local belt = entry("Conveyor", TX, BACK, 2)
		local sink = entry("Conveyor", FX, BACK, BaseLayout.SinkRotation)
		local fine = entry("ClayFurnace", 4, 4)
		local data = {
			PlacedMachines = { blocker, belt, sink, fine },
			MachineInventory = {},
			Storage = {},
			Coins = 0,
			TotalEarned = 0,
		}
		local displaced, reasons = Placement.sanitize(data)
		T.eq(#displaced, 1)
		T.eq(displaced[1], "Crusher")
		T.eq(reasons[1], "Chute", "moved off a chute (its own toast)")
		T.eq(data.MachineInventory.Crusher, 1, "back to the inventory")
		T.eq(#data.PlacedMachines, 3)
		T.eq(data.PlacedMachines[1], belt, "belts stay on chutes")
		T.eq(data.PlacedMachines[2], sink)
		T.eq(data.PlacedMachines[3], fine)
		T.eq(#data.Storage, 2, "its queues went to the pen")
		T.eq(blocker.In, nil)
		T.eq(blocker.Out, nil)
		T.eq(#Placement.sanitize(data), 0, "idempotent")
		-- every reason has a code the client can show
		local mixed = {
			PlacedMachines = {
				entry("Crusher", 0, 0),
				entry("ClayFurnace", 1, 1), -- overlaps the Crusher
				entry("BlastFurnace", CELLS - 2, CELLS - 2), -- off the plot
				entry("IronBox", FX - 1, BACK - 1), -- on the FOUNDRY chute
				{ Id = "Crusher", X = 4, Z = 4, R = 7 }, -- broken rotation
			},
			MachineInventory = {},
			Storage = {},
			Coins = 0,
		}
		local ids, why = Placement.sanitize(mixed)
		T.eq(#ids, 4)
		T.eq(#why, 4, "a reason per displaced machine")
		local expected = { "Overlap", "OutOfBounds", "Chute", "BadInput" }
		for i, code in expected do
			T.eq(why[i], code, ids[i] .. " reason")
			T.truthy(Placement.Reasons[code], code .. " has a text")
		end
	end)

	T.test("Step 3: a machine is never lost to the inventory cap", function()
		local cap = MachineData.MaxInventory
		T.eq(cap, 999)
		T.eq(EconomyConfig.TechShop.MaxOwned, cap, "the shop uses the same cap")
		-- picking up past the cap refunds the machine at its Price
		local belt = entry("Conveyor", 0, 0)
		local data = { PlacedMachines = { belt }, MachineInventory = { Conveyor = cap }, Storage = {}, Coins = 10, TotalEarned = 5 }
		local ok, refunded = Placement.commitPickup(data, belt)
		T.truthy(ok)
		T.eq(refunded, 1)
		T.eq(data.MachineInventory.Conveyor, cap, "stays at the cap")
		T.eq(data.Coins, 10 + MachineData.ById.Conveyor.Price, "refunded")
		T.eq(data.TotalEarned, 5, "a refund isn't income")
		T.eq(#data.PlacedMachines, 0)
		-- below the cap: a normal pickup
		local furnace = entry("ClayFurnace", 4, 4)
		local normal = { PlacedMachines = { furnace }, MachineInventory = { ClayFurnace = cap - 1 }, Storage = {}, Coins = 0 }
		ok, refunded = Placement.commitPickup(normal, furnace)
		T.truthy(ok)
		T.eq(refunded, 0)
		T.eq(normal.MachineInventory.ClayFurnace, cap)
		T.eq(normal.Coins, 0)
		-- addInventory splits a batch at the cap
		local batch = { MachineInventory = { Crusher = cap - 2 }, Coins = 0 / 0 }
		T.eq(Placement.addInventory(batch, "Crusher", 5), 3)
		T.eq(batch.MachineInventory.Crusher, cap)
		T.eq(batch.Coins, 3 * MachineData.ById.Crusher.Price, "a broken Coins value counts as 0")
		for _, bad in { 0, -2, 1.5, 0 / 0 } do
			T.eq(Placement.addInventory(batch, "Crusher", bad), 0, "bad count " .. tostring(bad))
		end
		T.eq(batch.MachineInventory.Crusher, cap)
		-- sanitize moving a machine off a chute at the cap refunds it too
		local onChute =
			{ PlacedMachines = { entry("IronBox", FX - 1, BACK - 1) }, MachineInventory = { IronBox = cap }, Storage = {}, Coins = 0 }
		Placement.sanitize(onChute)
		T.eq(onChute.MachineInventory.IronBox, cap)
		T.eq(onChute.Coins, MachineData.ById.IronBox.Price)
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
		-- a finished job passes the item on unchanged (a copy), so a generic complete() never loses it
		local shown = { K = "Clean", O = "Gold", G = "Pristine" }
		local passed = MachineLogic.outputs("IronBox", shown, 0.5)
		T.eq(#passed, 1, "one item out")
		T.truthy(passed[1] ~= shown, "a copy")
		T.eq(passed[1].K, "Clean")
		T.eq(passed[1].O, "Gold")
		T.eq(passed[1].G, "Pristine")
		T.eq(MachineLogic.outputs("IronBox", { K = "Raw", O = "Gold" }, 0.5)[1].G, nil, "dirty stays dirty")
		local job = entry("IronBox", 0, 0)
		MachineLogic.push(job, shown)
		MachineLogic.complete(job, MachineLogic.outputs("IronBox", shown, 0.5))
		T.eq(job.In, nil)
		T.eq(#job.Out, 1, "the item waits in Out to leave the front")
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
		local speed = {
			AutoCleaner = true,
			ClayFurnace = true,
			BlastFurnace = true,
			Crusher = true,
			IronBox = true,
			-- the machine roster (Speed = faster jobs / hand-overs, generators: more power)
			Splitter = true,
			Sorter = true,
			BrickFurnace = true,
			Polisher = true,
			RobotArm = true,
			CrystalExtractor = true,
			AlloyFurnace = true,
			PlasmaFurnace = true,
			SolarPanel = true,
			WindTurbine = true,
			FusionReactor = true,
			RestorationTable = true, -- cleans relics faster
		}
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
		-- the base curves (balance option 3, docs/BALANCE_SIM.md)
		local curves = MachineData.UpgradeCurves
		for i, price in { 20000, 400000, 8e6, 150e6, 2.5e9 } do
			T.eq(curves.Speed[i], price, "Speed curve " .. i)
		end
		for i, price in { 50000, 2e6, 50e6, 600e6, 6e9 } do
			T.eq(curves.Quality[i], price, "Quality curve " .. i)
		end
		T.eq(MachineData.ById.AutoCleaner.Upgrades.Quality[1], 50000)
		-- every level costs a lot more than the one before (goals across the journey)
		for _, curve in { curves.Speed, curves.Quality } do
			for i = 2, #curve do
				T.truthy(curve[i] >= curve[i - 1] * 10, "level " .. i .. " at least x10")
			end
		end
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

	T.test("Step 3: every Speed level still counts with full Bellows", function()
		local bellows = #MachineData.Bellows.Prices
		local checked = 0
		for _, machine in MachineData.List do
			-- machines with a job time (the others' Speed works elsewhere: hand-overs, power)
			local top = if machine.Time then MachineData.upgradeMax(machine.Id, "Speed") else 0
			for level = 1, top do
				local now = MachineData.processTime(machine, bellows, level)
				local before = MachineData.processTime(machine, bellows, level - 1)
				T.lt(now, before, `{machine.Id} Speed {level} is faster than {level - 1} with Bellows {bellows}`)
				checked += 1
			end
		end
		T.truthy(checked >= 25, "five machines, five levels")
	end)

	---------------------------------------------------------------- keeping

	T.test("Step 3: what the Iron Box and the billboard keep", function()
		local Keep = MachineData.Keep
		T.eq(Keep.Default, "RarePlus")
		T.eq(DataTemplate.KeepMode, Keep.Default, "new players start on the default")
		for _, mode in Keep.Modes do
			T.truthy(MachineData.isKeepMode(mode), mode)
		end
		for _, bad in { "", "all", "None", 3, {} :: any } do
			T.falsy(MachineData.isKeepMode(bad), "not a mode: " .. tostring(bad))
		end
		T.falsy(MachineData.isKeepMode(nil), "nil is not a mode")
		local function item(kind: string, ore: string): any
			return { K = kind, O = ore, G = if kind == "Raw" then nil else "Clean" }
		end
		-- dirty ore always passes on, in every mode (no peeking through the dirt)
		for _, mode in Keep.Modes do
			for _, ore in { "Coal", "Gold", "Heartstone" } do
				T.falsy(MachineData.keeps(mode, { [ore] = true }, item("Raw", ore)), `{mode}: dirty {ore} passes`)
			end
		end
		-- crushed ore and ingots always pass on too (on to a furnace, on to the Foundry)
		local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
		for _, mode in Keep.Modes do
			for _, ore in OreData.List do
				for _, kind in { "Crushed", "Ingot" } do
					T.falsy(MachineData.keeps(mode, { [ore.Id] = true }, item(kind, ore.Id)), `{mode}: {kind} {ore.Id} passes`)
				end
			end
		end
		-- RarePlus: clean ore of Rare and better
		local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
		local rareFrom = Rarity.get(Keep.RareFrom).Order
		local kept, sent = 0, 0
		for _, ore in OreData.List do
			local want = Rarity.get(ore.Rarity).Order >= rareFrom
			local clean = item("Clean", ore.Id)
			T.eq(MachineData.keeps("RarePlus", {}, clean), want, `RarePlus {ore.Id}`)
			T.eq(MachineData.keeps(nil, {}, clean), want, `no mode = default ({ore.Id})`)
			T.eq(MachineData.keeps("All", {}, clean), true, `All keeps {ore.Id}`)
			T.eq(MachineData.keeps("List", {}, clean), want, `an empty List keeps like Rare+ ({ore.Id})`)
			T.eq(MachineData.keepsOre("List", {}, ore.Id), want, `keepsOre {ore.Id}`)
			-- the player's explicit choice wins in List mode, and only there
			T.eq(MachineData.keeps("List", { [ore.Id] = true }, clean), true, `List keeps {ore.Id}`)
			T.eq(MachineData.keeps("List", { [ore.Id] = false }, clean), false, `List sends {ore.Id} on`)
			T.eq(MachineData.keeps("RarePlus", { [ore.Id] = not want }, clean), want, `RarePlus ignores the list ({ore.Id})`)
			if want then
				kept += 1
			else
				sent += 1
			end
		end
		T.truthy(kept > 0 and sent > 0, "RarePlus splits the ores")
		-- an ore the player never set follows Rare+: a first-ever top ore is kept, never smelted by surprise
		local top = OreData.List[1]
		for _, ore in OreData.List do
			if Rarity.get(ore.Rarity).Order > Rarity.get(top.Rarity).Order then
				top = ore
			end
		end
		T.truthy(MachineData.keeps("List", { Coal = false, Copper = true }, item("Clean", top.Id)), "unset top ore kept")
		T.falsy(MachineData.keeps("List", { Coal = false }, item("Clean", "Coal")))
		T.truthy(MachineData.keeps("List", { Coal = true }, item("Clean", "Coal")))
		T.eq(
			MachineData.keeps("List", "junk", item("Clean", "Coal")),
			MachineData.keeps("RarePlus", {}, item("Clean", "Coal")),
			"a broken list = Rare+"
		)
		T.eq(
			MachineData.keeps("List", { Coal = "yes" }, item("Clean", "Coal")),
			MachineData.keeps("RarePlus", {}, item("Clean", "Coal")),
			"only booleans count"
		)
		-- junk and odd items
		T.falsy(MachineData.keeps("All", {}, item("Clean", "Unobtainium")), "unknown ore")
		T.falsy(MachineData.keepsOre("All", {}, "Unobtainium"), "unknown ore")
		T.falsy(MachineData.keepsOre("All", {}, 5), "not an ore id")
		T.falsy(MachineData.keeps("All", {}, nil), "nil")
		T.falsy(MachineData.keeps("All", {}, "Gold"), "not a table")
		T.truthy(MachineData.keeps("List", {}, { K = "Gear", O = "Gold", G = "Clean", R = "Dagger" }), "old gear stays in the pen")
		-- only clean ore can be shown on podiums, which is why only clean ore is sorted
		local podiumKinds = 0
		for kind in EconomyConfig.Podiums.Kinds do
			T.eq(kind, "Clean", "podium kind " .. kind)
			podiumKinds += 1
		end
		T.eq(podiumKinds, 1)
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
		T.lt(price("Crusher"), price("IronBox"))
		T.lt(price("IronBox"), price("AutoCleaner"))
		T.lt(price("AutoCleaner"), price("BlastFurnace"))
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

	T.test("Step 3: a ShopBuy names the level it buys (no double buys)", function()
		local data = { MachineUpgrades = { AutoCleaner = { Quality = 3 } }, Upgrades = { Bellows = 0, ExtraSlots = 0, PenAutomation = 0 } }
		local quality = EconomyConfig.techItem("Upgrade:AutoCleaner:Quality")
		local prices = MachineData.ById.AutoCleaner.Upgrades.Quality
		T.eq(EconomyConfig.techQuote(quality, data, nil, 4), prices[4], "the next level")
		for _, bad in { 3, 5, 6, 0, -1, 4.5, "4" :: any, 0 / 0 } do
			local price, reason = EconomyConfig.techQuote(quality, data, nil, bad)
			T.eq(price, nil, "level " .. tostring(bad))
			T.eq(reason, "Stale", "level " .. tostring(bad))
		end
		T.eq(select(2, EconomyConfig.techQuote(quality, data)), "Stale", "a missing Level is refused")
		-- a double tap: the second request still names level 4 after it was bought
		data.MachineUpgrades.AutoCleaner.Quality = 4
		T.eq(select(2, EconomyConfig.techQuote(quality, data, nil, 4)), "Stale", "the repeat buys nothing")
		T.eq(EconomyConfig.techQuote(quality, data, nil, 5), prices[5])
		data.MachineUpgrades.AutoCleaner.Quality = 5
		T.eq(select(2, EconomyConfig.techQuote(quality, data, nil, 6)), "Max", "Max wins over Stale")
		-- base upgrades too
		local pen = EconomyConfig.techItem("PenAutomation")
		T.eq(EconomyConfig.techQuote(pen, data, nil, 1), 25000)
		T.eq(select(2, EconomyConfig.techQuote(pen, data, nil, 2)), "Stale")
		-- machines ignore Level and check Count
		local belt = EconomyConfig.techItem("Conveyor")
		T.eq(EconomyConfig.techQuote(belt, data, 4), MachineData.ById.Conveyor.Price * 4)
		T.eq(EconomyConfig.techQuote(belt, data, 4, 99), MachineData.ById.Conveyor.Price * 4)
		T.eq(select(2, EconomyConfig.techQuote(belt, data, 0)), "BadCount")
	end)

	T.test("Step 3: the Tech shop stops at MaxOwned machines of a type", function()
		local cap = EconomyConfig.TechShop.MaxOwned
		local belt = EconomyConfig.techItem("Conveyor")
		local price = MachineData.ById.Conveyor.Price
		local data: any = { MachineInventory = { Conveyor = 995 }, MachineUpgrades = {}, Upgrades = {} }
		local quote, reason = EconomyConfig.techQuote(belt, data, 20)
		T.eq(quote, nil, "995 + 20 is past the cap")
		T.eq(reason, "MaxOwned")
		T.eq(EconomyConfig.techQuote(belt, data, 4), price * 4, "up to the cap is fine")
		T.eq(select(2, EconomyConfig.techQuote(belt, data, 5)), "MaxOwned")
		data.MachineInventory.Conveyor = cap
		T.eq(select(2, EconomyConfig.techPrice(belt, data)), "MaxOwned", "a full stack buys nothing")
		-- other types and broken counts
		T.eq(EconomyConfig.techQuote(EconomyConfig.techItem("Crusher"), data, 20), MachineData.ById.Crusher.Price * 20)
		for _, broken in { "999" :: any, 0 / 0, -5, {} } do
			data.MachineInventory.Conveyor = broken
			T.eq(EconomyConfig.inventoryCount(data, "Conveyor"), 0, "broken count " .. tostring(broken))
			T.eq(EconomyConfig.techQuote(belt, data, 20), price * 20)
		end
		T.eq(EconomyConfig.inventoryCount({}, "Conveyor"), 0, "no inventory")
		T.eq(EconomyConfig.inventoryCount({ MachineInventory = { Conveyor = 12.7 } }, "Conveyor"), 12)
		-- BadCount is checked first
		data.MachineInventory.Conveyor = cap
		T.eq(select(2, EconomyConfig.techQuote(belt, data, 0)), "BadCount")
		-- every refusal code has a text for the shop card
		for _, code in { "BadItem", "BadCount", "MaxOwned", "Max", "Stale", "NoCoins", "TooFar" } do
			local text = EconomyConfig.TechShop.Reasons[code]
			T.truthy(type(text) == "string" and #text > 5, "reason text " .. code)
		end
	end)

	---------------------------------------------------------------- remotes and save

	T.test("Step 3: remotes", function()
		local limits = {
			PenAction = { 8, 12 },
			IronBoxAction = { 4, 12 },
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
		T.eq(Net.Events.ShopResult, false, "every ShopBuy gets an answer (server -> client)")
	end)

	T.test("Step 3: new save fields", function()
		T.eq(DataTemplate.Version, 3, "no version bump: reconcile fills the records")
		T.eq(type(DataTemplate.MachineUpgrades), "table")
		T.eq(next(DataTemplate.MachineUpgrades), nil, "no upgrades at first")
		T.eq(type(DataTemplate.KeepList), "table")
		T.eq(next(DataTemplate.KeepList), nil, "nothing on the list at first")
		T.eq(DataTemplate.KeepMode, "RarePlus", "keep Rare and better by default")
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
